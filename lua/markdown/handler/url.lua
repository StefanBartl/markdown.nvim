---@module 'markdown.handler.url'
local notify = require("markdown.util.notify").create("[markdown.handler.url]")
local platform = require("markdown.util.platform")

local M = {}

M.config = {
  html_scan_radius = 12,
  notify_on_error = true,
}

local api = vim.api

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function is_explicit_url(target)
  if not target then return false end
  return target:match("^https?://") ~= nil
end

local function find_href_in_buffer_near_cursor(bufnr, curline, radius)
  radius = radius or M.config.html_scan_radius
  if not bufnr or not curline then return nil end

  local start_line = math.max(1, curline - radius)
  local end_line = curline + radius
  local ok, lines = pcall(api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if not ok or not lines then return nil end

  for _, l in ipairs(lines) do
    local href = l:match('<a[^>]-href%s*=%s*"(.-)"') or l:match("<a[^>]-href%s*=%s*'(.-)'")
    if href and href ~= "" then return trim(href) end
  end

  local joined = table.concat(lines, "\n")
  local href = joined:match('<a.-href%s*=%s*"(.-)"') or joined:match("<a.-href%s*=%s*'(.-)'")
  if href and href ~= "" then return trim(href) end

  return nil
end

local function extract_url_from_line(line)
  if not line or line == "" then return nil end

  local md = line:match("%[.-%]%((.-)%)")
  if md and type(md) == "string" and md ~= "" then
    md = trim(md)
    if md and md:match("^<.+>$") then md = md:sub(2, -2) end
    if md and is_explicit_url(md) then return md end
    return nil
  end

  local raw = line:match("https?://[%w%-%_%.%/%?%%=&~#@:+,;%%]+")
  if raw and raw ~= "" then
    raw = raw:gsub("[%.,;:%)%]%}]+$", "")
    return trim(raw)
  end

  local href = line:match('<a[^>]-href%s*=%s*"(.-)"') or line:match("<a[^>]-href%s*=%s*'(.-)'")
  if href and href ~= "" and is_explicit_url(href) then return trim(href) end

  local ok, bufnr = pcall(api.nvim_get_current_buf)
  if not ok or not bufnr then return nil end

  local ok2, cursor = pcall(api.nvim_win_get_cursor, 0)
  local curline = (ok2 and cursor and cursor[1]) or 1

  local found = find_href_in_buffer_near_cursor(bufnr, curline, M.config.html_scan_radius)
  if found and found ~= "" and is_explicit_url(found) then return found end

  return nil
end

local function open_with_system_viewer(url)
  local ok, err = platform.open(url)
  if not ok and M.config.notify_on_error then
    notify.error("Failed to open URL: " .. tostring(err or url))
  end
  return ok
end

function M.is_url_line(line)
  return extract_url_from_line(line) ~= nil
end

function M.extract(line)
  return extract_url_from_line(line)
end

function M.open(line)
  line = line or api.nvim_get_current_line()
  local target = extract_url_from_line(line)
  if not target then
    if M.config.notify_on_error then notify.info("No URL found under cursor") end
    return false
  end

  local ok = open_with_system_viewer(target)
  if ok then
    if M.config.notify_on_error then notify.info("Opening -> " .. target) end
  else
    if M.config.notify_on_error then notify.error("Failed to open -> " .. target) end
  end
  return ok
end

return M
