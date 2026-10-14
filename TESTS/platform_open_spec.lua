-- TESTS/platform_open_spec.lua -- the system opener chain: a watched opener that fails hands over
-- to the next one, the same target again within RETRY_MS starts one opener further down, every
-- attempt is logged. No real browser is started: `_spawn`, `os` and `vim.ui.open` are replaced.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local platform = require("markdown.util.platform")

  local real_spawn, real_os, real_ui_open = platform._spawn, platform.os, vim.ui.open
  local real_notify = vim.notify
  local warned = {}
  vim.notify = function(msg) warned[#warned + 1] = msg end

  ---@type { argv: string[], on_exit: fun(code: integer)|nil }[]
  local spawned
  local ui_calls

  local function reset(target_os)
    platform._reset()
    spawned, ui_calls, warned = {}, {}, {}
    platform.os = function() return target_os end
    platform._spawn = function(argv, on_exit)
      spawned[#spawned + 1] = { argv = argv, on_exit = on_exit }
      return true
    end
    vim.ui.open = function(t)
      ui_calls[#ui_calls + 1] = t
      return {}, nil
    end
  end

  -- fire the exit of the n-th spawned process
  local function finish(n, code)
    spawned[n].on_exit(code)
    vim.wait(50, function() return false end) -- let the scheduled hand-over run
  end

  local URL = "https://example.com/a?b=1&c=2"

  -- ───────────── windows: rundll32 first, URL untouched (? and & survive) ─────────────
  reset("windows")
  local good = platform.open(URL)
  ok(good, "open reports a started opener")
  eq(spawned[1].argv[1], "rundll32.exe", "windows starts rundll32 first")
  eq(spawned[1].argv[2], "url.dll,FileProtocolHandler", "the ShellExecute entry point")
  eq(spawned[1].argv[3], URL, "the URL reaches it untouched, ? and & included")
  eq(#spawned[1].argv, 3, "and nothing else (no stray gsub count)")
  eq(#ui_calls, 0, "vim.ui.open (cmd.exe /c start) is not the first choice")

  -- the same target again within RETRY_MS: the next opener
  platform.open(URL)
  eq(spawned[2].argv[1], "powershell.exe", "asking again rotates to powershell Start-Process")
  eq(
    spawned[2].argv[#spawned[2].argv],
    "Start-Process -FilePath '" .. URL .. "'",
    "with the URL single-quoted (& and $ are literal there)"
  )
  platform.open(URL)
  eq(#ui_calls, 1, "and once more to vim.ui.open")
  platform.open(URL)
  eq(spawned[3].argv[1], "rundll32.exe", "then around to the first one again")

  -- explorer.exe is no opener: a URL with ?, & or %xx makes it open the Documents folder
  -- (hidden) instead of the browser, so it is nowhere in the chain
  for _, o in ipairs(platform._chain()) do
    local probe = {}
    platform._spawn = function(argv)
      probe[#probe + 1] = argv[1]
      return true
    end
    o.run("https://example.com/?a=1&b=%3F", function() end)
    for _, exe in ipairs(probe) do
      ok(exe ~= "explorer.exe", o.name .. " does not use explorer.exe")
    end
  end
  reset("windows")

  -- a path: absolute and backslashed, as ShellExecute wants it
  local path_open = platform.open("C:/tmp/some file.html")
  ok(path_open, "a path is opened")
  eq(#spawned[#spawned].argv, 3, "a path gives a three-element rundll32 argv")
  -- `:p` is the host's idea of absolute (on CI's Linux it prefixes $HOME): mirror it
  local want = (vim.fn.fnamemodify("C:/tmp/some file.html", ":p"):gsub("/", "\\"))
  eq(spawned[#spawned].argv[3], want, "absolute, with backslashes")
  ok(not spawned[#spawned].argv[3]:find("/", 1, true), "no forward slash is left")

  -- a single quote in a target is doubled for PowerShell
  reset("windows")
  platform.open("https://example.com/it's")
  platform.open("https://example.com/it's")
  eq(
    spawned[2].argv[#spawned[2].argv],
    "Start-Process -FilePath 'https://example.com/it''s'",
    "a ' inside the URL is doubled"
  )

  -- another target starts at the first opener again
  reset("windows")
  platform.open(URL)
  platform.open(URL .. "x")
  eq(spawned[#spawned].argv[1], "rundll32.exe", "a different target starts at the first opener")

  -- ───────────── a watched opener that fails hands over by itself ─────────────
  reset("windows")
  platform.open("https://example.com/other")
  eq(spawned[1].argv[1], "rundll32.exe", "rundll32 is running (exit code is reliable)")
  finish(1, 3)
  eq(spawned[2].argv[1], "powershell.exe", "a non-zero exit of rundll32 runs powershell")
  eq(#ui_calls, 0, "vim.ui.open is still in reserve")
  ok(
    vim.tbl_contains(
      vim.tbl_map(
        function(m) return m:find("rundll32 exited with code 3", 1, true) ~= nil end,
        warned
      ),
      true
    ),
    "and says so"
  )

  reset("windows")
  platform.open("https://example.com/third")
  finish(1, 0)
  eq(#spawned, 1, "a clean exit hands over to nobody")
  eq(#ui_calls, 0, "and vim.ui.open stays untouched")

  -- the rotation sticks: later requests, also after RETRY_MS, do not start with the opener that
  -- did nothing
  reset("windows")
  platform.open("https://example.com/sticky")
  platform.open("https://example.com/sticky") -- rotated to powershell
  local keep_retry = platform.RETRY_MS
  platform.RETRY_MS = 0 -- the repeat window is over
  platform.open("https://example.com/sticky")
  eq(spawned[#spawned].argv[1], "powershell.exe", "after the window it still starts at powershell")
  platform.open("https://example.com/another")
  eq(spawned[#spawned].argv[1], "powershell.exe", "and so does another target")
  platform.RETRY_MS = keep_retry

  -- a late hand-over (exit callback of an older request) does not take the place of a newer one
  reset("windows")
  platform.open("https://example.com/A")
  platform.open("https://example.com/A") -- powershell for A, watched
  platform.open("https://example.com/B") -- also starts at powershell (sticky), last = B
  finish(2, 3) -- A's powershell fails: vim.ui.open takes A over
  eq(#ui_calls, 1, "A was handed over")
  platform.open("https://example.com/B") -- repeat of B: must still rotate to the next opener
  eq(#ui_calls, 2, "the repeat of B rotated although A's hand-over came in between")

  -- URIs without // go through untouched
  reset("windows")
  platform.open("mailto:a@b.c")
  eq(spawned[1].argv[3], "mailto:a@b.c", "mailto: is no path")
  platform.open("ms-settings:network")
  eq(spawned[#spawned].argv[3], "ms-settings:network", "nor is ms-settings:")

  -- ───────────── an opener that cannot even start is skipped ─────────────
  reset("windows")
  platform._spawn = function(argv, on_exit)
    spawned[#spawned + 1] = { argv = argv, on_exit = on_exit }
    return false, "ENOENT"
  end
  local started, err = platform.open("https://example.com/none")
  eq(#spawned, 2, "rundll32 and powershell were both tried")
  eq(#ui_calls, 1, "and vim.ui.open took over")
  ok(started, "the request was served by the last opener: " .. tostring(err))

  reset("windows")
  platform._spawn = function() return false, "ENOENT" end
  vim.ui.open = function() return nil, "no handler" end
  local ok_all, err_all = platform.open("https://example.com/dead")
  eq(ok_all, false, "no opener works: false")
  ok(err_all and err_all:find("no opener left", 1, true), "with an error that says so")

  -- ───────────── the log ─────────────
  reset("windows")
  local before = #platform.log()
  platform.open("https://example.com/logged")
  local entries = platform.log()
  eq(entries[#entries].opener, "rundll32", "the log names the opener")
  eq(entries[#entries].result, "spawned", "and what happened")
  eq(#entries, before + 1, "one entry per attempt")

  eq(select(1, platform.open("")), false, "an empty target is refused")

  platform._spawn, platform.os, vim.ui.open = real_spawn, real_os, real_ui_open
  vim.notify = real_notify
end
