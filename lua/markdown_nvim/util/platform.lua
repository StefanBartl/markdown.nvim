---@module 'markdown_nvim.util.platform'
---@brief Cross-platform helpers (single system-opener for the whole plugin).
---@description
--- One place for OS detection and "open this path/URL with the system default
--- application", so handlers and the table-view browser export don't each
--- reimplement the `xdg-open`/`open`/`start` branch. Prefers `vim.ui.open`
--- (Neovim 0.10+, shell-agnostic) and falls back to a detached per-OS launcher.

local M = {}

local uv = vim.uv or vim.loop

---@alias Mkdn.OS "windows"|"macos"|"unix"

--- Detect the OS family.
---@return Mkdn.OS
function M.os()
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

  local esc = vim.fn.shellescape(target)
  local os = M.os()
  local cmd
  if os == "windows" then
    cmd = string.format('cmd /C start "" %s', esc)
  elseif os == "macos" then
    cmd = string.format("open %s", esc)
  else
    cmd = string.format("xdg-open %s", esc)
  end

  local ok, jid = pcall(vim.fn.jobstart, cmd, { detach = true })
  if not ok or jid == 0 or jid == -1 then
    return false, "failed to launch system opener for: " .. target
  end
  return true
end

return M
