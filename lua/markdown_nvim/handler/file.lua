---@module 'markdown_nvim.handler.file'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.handler.file]")

local M = {}

M.config = {
  resolve_relative_to_buffer = true,
  cmd_unix    = "xdg-open",
  cmd_macos   = "open",
  cmd_windows = "cmd",
  notify_on_error = true,
  html_scan_radius = 12,
}

local api = vim.api
local uv = vim.loop

local function trim(s)
  return s:match("^%s*(.-)%s*$") or ""
end

local function find_href_or_imgsrc_in_buffer_near_cursor(bufnr, curline, radius)
  radius = radius or M.config.html_scan_radius
  if not bufnr or not curline then return nil end

  local start_line = math.max(1, curline - radius)
  local end_line = curline + radius
  local ok, lines = pcall(api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if not ok or not lines then return nil end

  for _, l in ipairs(lines) do
    local href = l:match('<a[^>]-href%s*=%s*"(.-)"') or l:match("<a[^>]-href%s*=%s*'(.-)'")
    if href and href ~= "" then return trim(href) end
    local img = l:match('<img[^>]-src%s*=%s*"(.-)"') or l:match("<img[^>]-src%s*=%s*'(.-)'")
    if img and img ~= "" then return trim(img) end
  end

  local joined = table.concat(lines, "\n")
  local href = joined:match('<a.-href%s*=%s*"(.-)"') or joined:match("<a.-href%s*=%s*'(.-)'")
  if href and href ~= "" then return trim(href) end

  local img = joined:match('<img.-src%s*=%s*"(.-)"') or joined:match("<img.-src%s*=%s*'(.-)'")
  if img and img ~= "" then return trim(img) end

  local source_src = joined:match('<source.-src%s*=%s*"(.-)"') or joined:match("<source.-src%s*=%s*'(.-)'")
  if source_src and source_src ~= "" then return trim(source_src) end

  return nil
end

local function extract_file_target_from_line(line)
  if not line or line == "" then return nil end

  local target = line:match("%[.-%]%((.-)%)")
  if target and target ~= "" then
    target = trim(target)
    if target and target:match("^<.+>$") then target = target:sub(2, -2) end
    return target
  end

  local href = line:match('<a[^>]-href%s*=%s*"(.-)"') or line:match("<a[^>]-href%s*=%s*'(.-)'")
  if href and href ~= "" then return trim(href) end

  local img_src = line:match('<img[^>]-src%s*=%s*"(.-)"') or line:match("<img[^>]-src%s*=%s*'(.-)'")
  if img_src and img_src ~= "" then return trim(img_src) end

  local ok, bufnr = pcall(api.nvim_get_current_buf)
  if not ok or not bufnr then return nil end

  local ok2, cursor = pcall(api.nvim_win_get_cursor, 0)
  local curline = (ok2 and cursor and cursor[1]) or 1

  local found = find_href_or_imgsrc_in_buffer_near_cursor(bufnr, curline, M.config.html_scan_radius)
  if found and found ~= "" then return found end

  return nil
end

local function is_url(target)
  return target and target:match("^https?://") ~= nil
end

local function resolve_target_to_path(target)
  if not target then return nil end
  if is_url(target) then return target end

  local expanded = vim.fn.expand(target)

  if M.config.resolve_relative_to_buffer and not expanded:match("^/") and not expanded:match("^%a:[/\\]") then
    local bufdir = vim.fn.expand("%:p:h")
    if bufdir and bufdir ~= "" then
      expanded = vim.fn.fnamemodify(bufdir .. "/" .. expanded, ":p")
    else
      expanded = vim.fn.fnamemodify(expanded, ":p")
    end
  else
    expanded = vim.fn.fnamemodify(expanded, ":p")
  end

  return expanded
end

local function open_with_system_viewer(path)
  if not path or path == "" then return false end

  -- Preferred path (Neovim 0.10+): robust across shell=pwsh/cmd.
  if vim.ui and type(vim.ui.open) == "function" then
    local ok, _obj, err = pcall(vim.ui.open, path)
    if ok and err == nil then
      return true
    end
    if M.config.notify_on_error then
      notify.error("Failed to open: " .. tostring(err or path))
    end
    return false
  end

  -- Legacy fallback for older Neovim.
  local esc = vim.fn.shellescape(path)
  local sysname = (uv.os_uname() and uv.os_uname().sysname) or ""
  local cmd

  if sysname:match("Windows") or sysname:match("windows") then
    cmd = string.format('cmd /C start "" %s', esc)
  elseif sysname == "Darwin" then
    cmd = string.format("open %s", esc)
  else
    cmd = string.format("%s %s", M.config.cmd_unix, esc)
  end

  local ok, jid = pcall(vim.fn.jobstart, cmd, { detach = true })
  if not ok or jid == 0 or jid == -1 then
    if M.config.notify_on_error then notify.error("Failed to spawn viewer for: " .. tostring(path)) end
    return false
  end
  return true
end

--- Open an already-resolved path with the system application.
---@param path string
---@return boolean ok
function M.system_open(path)
  return open_with_system_viewer(path)
end

function M.is_file_line(line)
  local target = extract_file_target_from_line(line)
  if not target then return false end
  return not is_url(target)
end

function M.extract(line)
  return extract_file_target_from_line(line)
end

function M.resolve(target)
  return resolve_target_to_path(target)
end

function M.open(line)
  line = line or api.nvim_get_current_line()
  local target = extract_file_target_from_line(line)
  if not target then
    if M.config.notify_on_error then notify.info("No link/file found under cursor") end
    return false
  end

  local resolved = resolve_target_to_path(target)
  if not resolved or resolved == "" then
    if M.config.notify_on_error then notify.error("Could not resolve path: " .. tostring(target)) end
    return false
  end

  if is_url(resolved) then return open_with_system_viewer(resolved) end

  local stat = uv.fs_stat(resolved)
  if not stat then
    if M.config.notify_on_error then notify.warn("File does not exist: " .. resolved) end
    return false
  end

  local ok = open_with_system_viewer(resolved)
  if ok then
    if M.config.notify_on_error then notify.info("Opening -> " .. resolved) end
  else
    if M.config.notify_on_error then notify.error("Failed to open -> " .. resolved) end
  end
  return ok
end

return M
