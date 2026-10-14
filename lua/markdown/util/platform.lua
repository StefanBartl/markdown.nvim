---@module 'markdown.util.platform'
---@brief Cross-platform helpers (single system-opener for the whole plugin).
---@description
--- One place for OS detection and "open this path/URL with the system default
--- application", so handlers and the table-view browser export don't each
--- reimplement the `xdg-open`/`open`/`start` branch.
---
--- Opening is a chain of openers per OS. A spawned process is not an opened tab: an opener can
--- start, exit non-zero (or do nothing) and the old "spawned = success" report said "Opening"
--- while no browser tab appeared. So:
---
---   * an opener whose exit code is reliable (`trust_exit`) is watched; a non-zero code runs the
---     next opener of the chain and says so;
---   * asking for the same target again within `RETRY_MS` starts one opener further down the
---     chain (the first one evidently did not work), wrapping around;
---   * every attempt is kept in a small log (`M.log()`, shown by `:checkhealth markdown`).
---
--- Windows: `explorer.exe` first (no cmd.exe tokenizer: a `&` in the URL survives; its exit code is
--- always 1, so it is not watched), then `rundll32 url.dll,FileProtocolHandler` (exit code
--- reliable), then `vim.ui.open` (`cmd.exe /c start ""`). Elsewhere: `vim.ui.open`,
--- `lib.nvim.cross.open_default`, then the plain `open` / `xdg-open`.

local M = {}

local uv = vim.uv or vim.loop

---A second request for the same target within this many ms rotates to the next opener.
M.RETRY_MS = 15000
local LOG_MAX = 20

---@class Mkdn.OpenAttempt
---@field target string
---@field opener string
---@field result string  # "spawned" | "exit 0" | "exit N" | "failed: ..." | "running"
---@field at? integer  # uv.now() ms, set by `record`

---@type Mkdn.OpenAttempt[]
local log = {}

---@type { target: string|nil, at: integer, idx: integer }
local last = { target = nil, at = 0, idx = 0 }

---The opener a request starts with: moves one down the chain whenever a request was repeated.
local preferred = 1

---@param name string
---@return function|nil
local function try_lib_detector(name)
  local ok, fn = pcall(require, "lib.nvim.cross.platform." .. name)
  if ok and type(fn) == "function" then return fn end
  return nil
end

--- Detect the OS family (`Mkdn.OS` is declared in `markdown.@types`).
--- Delegates to `lib.nvim.cross.platform.*` when present (soft dependency,
--- matching this repo's `util/notify.lua`/`util/picker.lua` pattern), falling
--- back to a native `uv.os_uname()` check otherwise.
---@return Mkdn.OS
function M.os()
  local is_windows = try_lib_detector("is_windows")
  if is_windows then
    if is_windows() then return "windows" end
    local is_macos = try_lib_detector("is_macos")
    if is_macos and is_macos() then return "macos" end
    return "unix"
  end

  local s = (uv.os_uname() and uv.os_uname().sysname) or ""
  if s:match("[Ww]indows") then
    return "windows"
  elseif s == "Darwin" then
    return "macos"
  end
  return "unix"
end

---@internal
---@param entry Mkdn.OpenAttempt
local function record(entry)
  entry.at = uv.now()
  log[#log + 1] = entry
  if #log > LOG_MAX then table.remove(log, 1) end
end

---Forget the attempts and the repeat-rotation state (tests).
function M._reset()
  log = {}
  last = { target = nil, at = 0, idx = 0 }
  preferred = 1
end

---The last attempts, oldest first.
---@return Mkdn.OpenAttempt[]
function M.log() return vim.deepcopy(log) end

---Run `argv` detached. `on_exit(code)` (scheduled onto the main loop) is called when it ends.
---Replaceable in tests.
---@param argv string[]
---@param on_exit? fun(code: integer)
---@return boolean ok, string|nil err
function M._spawn(argv, on_exit)
  local ok, err = pcall(
    vim.system,
    argv,
    { detach = true, stdout = false, stderr = false },
    function(res)
      if on_exit then vim.schedule(function() on_exit(res.code) end) end
    end
  )
  if not ok then return false, tostring(err) end
  return true
end

---A Windows target as `explorer.exe` resolves it: an URL untouched, a path absolute and with
---backslashes (a relative or forward-slashed path opens a folder window instead).
---@param target string
---@return string
local function windows_target(target)
  -- any URI (https://, mailto:, ms-settings:, file:...) goes untouched; a drive letter `C:` has a
  -- one-character "scheme" and is a path
  if target:match("^%a[%w+.-]+:") then return target end
  local abs = vim.fn.fnamemodify(target, ":p")
  return ((abs ~= "" and abs or target):gsub("/", "\\"))
end

---@class Mkdn.Opener
---@field name string
---@field trust_exit boolean  # the exit code says whether it worked
---@field run fun(target: string, on_exit: fun(code: integer)): boolean, string|nil

---@param name string
---@param argv fun(target: string): string[]
---@param trust_exit boolean
---@return Mkdn.Opener
local function argv_opener(name, argv, trust_exit)
  return {
    name = name,
    trust_exit = trust_exit,
    run = function(target, on_exit) return M._spawn(argv(target), on_exit) end,
  }
end

---@type Mkdn.Opener
local ui_opener = {
  name = "vim.ui.open",
  trust_exit = false,
  run = function(target)
    if not (vim.ui and type(vim.ui.open) == "function") then return false, "vim.ui.open missing" end
    local ok, obj, err = pcall(vim.ui.open, target)
    if not ok then return false, tostring(obj) end
    if err ~= nil or obj == nil then return false, tostring(err) end
    return true
  end,
}

M.ui_opener = ui_opener -- test seam: specs run a chain of only this one

---@type Mkdn.Opener
local lib_opener = {
  name = "lib.nvim open_default",
  trust_exit = false,
  run = function(target)
    local ok_lib, open_default = pcall(require, "lib.nvim.cross.open_default")
    if not ok_lib then return false, "lib.nvim.cross.open_default missing" end
    return open_default(target)
  end,
}

---The openers of this OS in the order they are tried.
---@return Mkdn.Opener[]
function M._chain()
  local os = M.os()
  if os == "windows" then
    return {
      -- exit code is always 1 for a handed-over request: not watched
      argv_opener(
        "explorer.exe",
        function(t) return { "explorer.exe", windows_target(t) } end,
        false
      ),
      argv_opener(
        "rundll32",
        function(t) return { "rundll32.exe", "url.dll,FileProtocolHandler", windows_target(t) } end,
        true
      ),
      ui_opener,
    }
  end
  return {
    ui_opener,
    lib_opener,
    argv_opener(
      os == "macos" and "open" or "xdg-open",
      function(t) return { os == "macos" and "open" or "xdg-open", t } end,
      true
    ),
  }
end

---@internal
---@param msg string
local function warn(msg) require("markdown.util.notify").create("[markdown.platform]").warn(msg) end

--- Open a path or URL with the system default application.
--- Returns `true` when an opener could be started, or `false` plus an error message when none
--- could. A watched opener that fails later hands over to the next one by itself.
---@param target string
---@return boolean ok, string|nil err
function M.open(target)
  if type(target) ~= "string" or target == "" then return false, "empty target" end

  local chain = M._chain()
  local start = (preferred - 1) % #chain + 1
  if last.target == target and (uv.now() - last.at) < M.RETRY_MS then
    -- the same target again so soon: the opener that was used did not work for the user. The
    -- next one becomes the starting point for later requests too, until the session ends: an
    -- opener that failed once silently is not asked first again.
    start = last.idx % #chain + 1
    preferred = start
  end

  ---@param idx integer
  ---@param tried integer  # openers already given up on for this request
  ---@param late boolean  # called from an exit callback, not from `M.open` itself
  ---@return boolean ok, string|nil err
  local function attempt(idx, tried, late)
    local opener = chain[idx]
    local nxt = idx % #chain + 1

    ---Give up on `opener` and run the next one, if any is left.
    ---@param why string
    ---@param from_exit boolean
    ---@return boolean ok, string|nil err
    local function hand_over(why, from_exit)
      if tried + 1 >= #chain then
        return false, ("%s %s, no opener left for %s"):format(opener.name, why, target)
      end
      warn(("%s %s -- trying %s"):format(opener.name, why, chain[nxt].name))
      return attempt(nxt, tried + 1, late or from_exit)
    end

    local spawned, err = opener.run(target, function(code)
      record({ target = target, opener = opener.name, result = "exit " .. tostring(code) })
      if opener.trust_exit and code ~= 0 then
        local ok, why = hand_over("exited with code " .. tostring(code), true)
        if not ok then warn(why or "no opener left") end
      end
    end)

    if not spawned then
      record({ target = target, opener = opener.name, result = "failed: " .. tostring(err) })
      return hand_over("could not be started (" .. tostring(err) .. ")", false)
    end
    record({ target = target, opener = opener.name, result = "spawned" })
    -- a hand-over from an exit callback must not take the place of a newer request
    if not late then last = { target = target, at = uv.now(), idx = idx } end
    return true
  end

  return attempt(start, 0, false)
end

return M
