-- docs/TESTS/browser_session_spec.lua — TableView browser export: one tab
-- reused across calls (fixed file + open-once-per-session + auto-refresh
-- script), 'reopen' forcing a fresh tab. See
-- lua/markdown/tableview/views/browser_session.lua.

return function(H)
  local eq, ok = H.eq, H.ok

  local session = require("markdown.tableview.views.browser_session")

  local function read_file(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local content = fh:read("*a")
    fh:close()
    return content
  end

  -- Stub the system opener so no real browser launches; count invocations.
  local orig_ui_open = vim.ui and vim.ui.open
  local opens = 0
  if vim.ui then vim.ui.open = function(_target)
    opens = opens + 1
    return true
  end end

  local restored = false
  local function restore()
    if restored then return end
    restored = true
    if vim.ui then vim.ui.open = orig_ui_open end
  end
  -- Best-effort restore even if an assertion below errors out.
  local run_ok, run_err = pcall(function()
    -- 1) First call for a style opens the system browser exactly once.
    local okShow1, err1 = session.show("<html><body><p>v1</p></body></html>", "spec_style_a")
    ok(
      okShow1,
      "show: first call for a style succeeds" .. (err1 and (" (" .. tostring(err1) .. ")") or "")
    )
    eq(opens, 1, "show: first call opens the system browser")

    local path = session._fixed_path("spec_style_a")
    local content1 = read_file(path)
    ok(content1 ~= nil, "show: writes the fixed file")
    ok(content1 and content1:find("v1", 1, true) ~= nil, "show: file contains the rendered content")
    ok(
      content1 and content1:find("setInterval", 1, true) ~= nil,
      "show: file has the auto-refresh script injected"
    )

    -- 2) A second call for the SAME style updates the file but does not open
    --    a second tab — this is the actual "reuse" behavior under test.
    local okShow2 = session.show("<html><body><p>v2</p></body></html>", "spec_style_a")
    ok(okShow2, "show: second call for the same style succeeds")
    eq(opens, 1, "show: second call does NOT open a new tab (reuse)")

    local content2 = read_file(path)
    ok(
      content2 and content2:find("v2", 1, true) ~= nil,
      "show: second call overwrites the same file with new content"
    )
    ok(content2 and content2:find("v1", 1, true) == nil, "show: old content is gone, not appended")

    -- 3) A different style key gets its own independent "opened" tracking.
    local okShow3 = session.show("<html><body><p>other</p></body></html>", "spec_style_b")
    ok(okShow3, "show: first call for a different style succeeds")
    eq(opens, 2, "show: a different style opens its own tab independently")

    -- 4) force_new (the 'reopen' argument) re-opens even though a tab for
    --    this style was already considered open.
    local okShow4 = session.show("<html><body><p>v3</p></body></html>", "spec_style_a", true)
    ok(okShow4, "show: force_new call succeeds")
    eq(opens, 3, "show: force_new re-opens a tab even though one was already open")
  end)

  restore()
  if not run_ok then error(run_err, 0) end
end
