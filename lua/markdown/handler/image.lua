---@module 'markdown.handler.image'
local notify = require("markdown.util.notify").create("[markdown.handler.image]")
local platform = require("markdown.util.platform")

local M = {}

M.config = {
  resolve_relative_to_buffer = true,
  notify_on_error = true,
}

local api = vim.api
local uv = vim.loop

local function trim(s)
  if not s then return nil end
  return s:match("^%s*(.-)%s*$")
end

local function find_img_src_in_buffer_near_cursor(bufnr, curline, radius)
  radius = radius or 8
  if not bufnr or not curline then return nil end
  local start_line = math.max(1, curline - radius)
  local end_line = curline + radius
  local ok, lines = pcall(api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if not ok or not lines then return nil end

  for _, l in ipairs(lines) do
    local single = l:match('<img[^>]-src%s*=%s*"(.-)"') or l:match("<img[^>]-src%s*=%s*'(.-)'")
    if single and single ~= "" then return trim(single) end
  end

  local joined = table.concat(lines, "\n")
  local src = joined:match('<img.-src%s*=%s*"(.-)"') or joined:match("<img.-src%s*=%s*'(.-)'")
  if src and src ~= "" then return trim(src) end

  local source_src = joined:match('<source.-src%s*=%s*"(.-)"') or joined:match("<source.-src%s*=%s*'(.-)'")
  if source_src and source_src ~= "" then return trim(source_src) end

  return nil
end

local function extract_image_target_from_line(line)
  if not line or line == "" then return nil end

  -- Requires the leading `!` (real image syntax); a plain `[text](target)`
  -- link is not an image and must fall through to the link/file handlers.
  local t = line:match("!%b[]%(([^)]+)%)")

  if t and type(t) == "string" and t ~= "" then
    t = trim(t --[[@as string]])
    if t and t:match("^<.+>$") then t = t:sub(2, -2) end
    return t
  end

  local img_src = line:match('<img[^>]-src%s*=%s*"(.-)"') or line:match("<img[^>]-src%s*=%s*'(.-)'")
  if img_src and img_src ~= "" then return trim(img_src) end

  local ok, bufnr = pcall(api.nvim_get_current_buf)
  if not ok or not bufnr then return nil end

  local ok2, cursor = pcall(api.nvim_win_get_cursor, 0)
  local curline = (ok2 and cursor and cursor[1]) or 1

  if line:match("<figure") or line:match("<img") or line:match("<picture") then
    local found = find_img_src_in_buffer_near_cursor(bufnr, curline, 12)
    if found and found ~= "" then return found end
  end

  local found = find_img_src_in_buffer_near_cursor(bufnr, curline, 12)
  if found and found ~= "" then return found end

  return nil
end

local function is_url(target)
  return target and target:match("^https?://") ~= nil
end

local path = require("markdown.util.path")

local function resolve_target_to_path(target)
  if not target then return nil end
  if is_url(target) then return target end
  return path.resolve(target)
end

local function open_with_system_viewer(path)
  local ok, err = platform.open(path)
  if not ok and M.config.notify_on_error then
    notify.error("Failed to spawn viewer for: " .. tostring(err or path))
  end
  return ok
end

function M.is_image_line(line)
  return extract_image_target_from_line(line) ~= nil
end

function M.extract(line)
  return extract_image_target_from_line(line)
end

function M.resolve(target)
  return resolve_target_to_path(target)
end

function M.open(line)
  line = line or api.nvim_get_current_line()
  local target = extract_image_target_from_line(line)
  if not target then
    if M.config.notify_on_error then notify.info("No image/link found under cursor") end
    return false
  end

  local resolved = resolve_target_to_path(target)
  if not resolved or resolved == "" then
    if M.config.notify_on_error then notify.error("Could not resolve path: " .. tostring(target)) end
    return false
  end

  if not is_url(resolved) then
    local stat = uv.fs_stat(resolved)
    if not stat then
      if M.config.notify_on_error then notify.warn("File does not exist: " .. resolved) end
      return false
    end
  end

  return open_with_system_viewer(resolved)
end

return M
