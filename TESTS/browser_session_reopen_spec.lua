-- TESTS/browser_session_reopen_spec.lua -- the table browser export opens its tab once per style,
-- but not on faith: when the last logged attempt to open the file failed, the next show opens again.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local session = require("markdown.tableview.views.browser_session")
  local platform = require("markdown.util.platform")

  local real_open, real_log = platform.open, platform.log
  local opens, entries = {}, {}
  platform.open = function(target)
    opens[#opens + 1] = target
    return true
  end
  platform.log = function() return entries end

  local okrun, err = pcall(function()
    local HTML = "<html><body><p>t</p></body></html>"
    local path = session._fixed_path("reopen_spec")

    ok(
      session.show(HTML, "reopen_spec", true),
      "the first show succeeds (force_new resets the flag)"
    )
    eq(#opens, 1, "the first show opens the file")
    eq(opens[1], path, "the fixed path is handed to the opener")

    entries = { { target = path, opener = "rundll32", result = "spawned" } }
    session.show(HTML, "reopen_spec")
    eq(#opens, 1, "a started opener: later shows only rewrite the file")

    entries = { { target = path, opener = "rundll32", result = "exit 0" } }
    session.show(HTML, "reopen_spec")
    eq(#opens, 1, "a clean exit: still one tab")

    entries = { { target = path, opener = "rundll32", result = "exit 3" } }
    session.show(HTML, "reopen_spec")
    eq(#opens, 2, "the last attempt exited non-zero: the next show opens again")

    entries = { { target = path, opener = "rundll32", result = "failed: ENOENT" } }
    session.show(HTML, "reopen_spec")
    eq(#opens, 3, "an opener that could not start: the next show opens again")

    -- the flag was set again by the reopen: with a healthy log it stays one tab
    entries = { { target = path, opener = "rundll32", result = "spawned" } }
    session.show(HTML, "reopen_spec")
    eq(#opens, 3, "after a healthy reopen no more tabs")

    -- another file's failure does not matter
    entries = { { target = path .. ".other", opener = "rundll32", result = "exit 3" } }
    session.show(HTML, "reopen_spec")
    eq(#opens, 3, "a failure logged for another target is ignored")

    -- explicit reopen still works
    session.show(HTML, "reopen_spec", true)
    eq(#opens, 4, "force_new still opens a new tab")
  end)

  platform.open, platform.log = real_open, real_log
  session._opened["reopen_spec"] = nil
  if not okrun then error(err, 0) end
end
