---@module 'markdown_nvim.util.platform'
---@brief Cross-platform helpers (single system-opener for the whole plugin).
---@description
--- One place for OS detection and "open this path/URL with the system default
--- application", so handlers and the table-view browser export don't each
--- reimplement the `xdg-open`/`open`/`start` branch. Prefers `vim.ui.open`
--- (Neovim 0.10+, shell-agnostic) and falls back to a detached per-OS launcher.

local M = {}

local uv = vim.uv or vim.loop

---@param name string
---@return function|nil
local function try_lib_detector(name)
  local ok, fn = pcall(require, "lib.nvim.cross.platform." .. name)
  if ok and type(fn) == "function" then
    return fn
  end
  return nil
end

--- Detect the OS family (`Mkdn.OS` is declared in `markdown_nvim.@types`).
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

--- Open a path or URL with the system default application.
--- Returns `true` on success, or `false` plus an error message.
---@param target string
---@return boolean ok, string|nil err
function M.open(target)
  if type(target) ~= "string" or target == "" then
    return false, "empty target"
  end

  -- Preferred (Neovim 0.10+): does not route through 'shell', so it works
  -- regardless of shell=pwsh/cmd. Fall through to the launcher on failure.
  if vim.ui and type(vim.ui.open) == "function" then
    local ok, _obj, err = pcall(vim.ui.open, target)
    if ok and err == nil then
      return true
    end
  end

  -- lib.nvim.cross.open_default (soft dependency, matching this repo's
  -- util/notify.lua/util/picker.lua pattern): same per-OS dispatch as the
  -- manual fallback below, plus WSL->Windows path translation via wslpath,
  -- which the manual fallback does not have.
  local ok_lib, open_default = pcall(require, "lib.nvim.cross.open_default")
  if ok_lib then
    local ok_open, err = open_default(target)
    if ok_open then
      return true
    end
  end

  -- Fallback: launch with a LIST argv so the call bypasses 'shell' entirely.
  -- The previous string form went through &shell + vim.fn.shellescape, which
  -- breaks on Windows when shell=pwsh (single-quoted path that cmd's `start`
  -- cannot parse). A list argv needs no shell-specific quoting.
  local os = M.os()
  local argv
  if os == "windows" then
    -- Empty "" is the (required) window title for `start` when the target may
    -- contain spaces; cmd.exe is invoked directly, not via the user's shell.
    argv = { "cmd.exe", "/c", "start", "", target }
  elseif os == "macos" then
    argv = { "open", target }
  else
    argv = { "xdg-open", target }
  end

  if vim.system then
    local ok = pcall(vim.system, argv, { detach = true })
    if ok then return true end
  end

  local ok, jid = pcall(vim.fn.jobstart, argv, { detach = true })
  if not ok or jid == 0 or jid == -1 then
    return false, "failed to launch system opener for: " .. target
  end
  return true
end

return M
