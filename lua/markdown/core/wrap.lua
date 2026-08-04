---@module 'markdown.core.wrap'
--- Toggle bold (`**`) around a normal-selection word or a visual selection.
local notify = require("markdown.util.notify").create("[markdown.core.wrap]")

local M = {}

local api = vim.api
local fn = vim.fn
local cfg = require("markdown.config").get

---@internal
---@return integer? row
---@return integer? scol
---@return integer? ecol
local function get_visual_selection()
  local mode = fn.mode()
  local is_visual = mode:match('[vV\22]') ~= nil

  if is_visual then
    local cursor = api.nvim_win_get_cursor(0)
    local vstart_ok, vstart = pcall(fn.getpos, 'v')
    if not (vstart_ok and vstart) then return nil, nil, nil end

    local row1 = cursor[1] - 1
    local col1 = cursor[2]
    local row2 = vstart[2] - 1
    local col2 = vstart[3] - 1

    if row1 ~= row2 then return nil, nil, nil end

    return row1, math.min(col1, col2), math.max(col1, col2)
  else
    local ok_start, start_pos = pcall(fn.getpos, "'<")
    local ok_end, end_pos = pcall(fn.getpos, "'>")
    if not (ok_start and ok_end and start_pos and end_pos) then return nil, nil, nil end

    local start_row = start_pos[2] - 1
    local start_col = start_pos[3] - 1
    local end_row = end_pos[2] - 1
    local end_col = end_pos[3] - 1

    if start_row ~= end_row then return nil, nil, nil end

    return start_row, math.min(start_col, end_col), math.max(start_col, end_col)
  end
end

---@internal
---@param row integer
---@param scol integer
---@param ecol integer
local function reselect_visual(row, scol, ecol)
  fn.setpos("'<", {0, row + 1, scol + 1, 0})
  fn.setpos("'>", {0, row + 1, ecol + 1, 0})
  local reselect = api.nvim_replace_termcodes("<Esc>gv", true, false, true)
  api.nvim_feedkeys(reselect, "nx", false)
end

---@internal
---@param count integer
local function wrap_with_asterisks(count)
  local bufnr = api.nvim_get_current_buf()
  local row, scol, ecol = get_visual_selection()
  if not (row and scol and ecol) then
    notify.warn("No valid selection")
    return
  end

  local lines = api.nvim_buf_get_text(bufnr, row, scol, row, ecol + 1, {})
  local selected_text = table.concat(lines, "\n")
  local pad = string.rep("*", count)
  local wrapped = pad .. selected_text .. pad

  api.nvim_buf_set_text(bufnr, row, scol, row, ecol + 1, {wrapped})

  if cfg().keep_inner_selection then
    reselect_visual(row, scol + count, scol + count + #selected_text - 1)
  else
    reselect_visual(row, scol, ecol + (2 * count))
  end
end

---Toggles `**bold**` around the current visual selection.
---@return nil
function M.toggle_visual_bold()
  local bufnr = api.nvim_get_current_buf()
  local row, scol, ecol = get_visual_selection()
  if not (row and scol and ecol) then
    notify.warn("No valid selection")
    return
  end

  local check_start = math.max(0, scol - 2)
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  local check_end = math.min(#line, ecol + 3)
  local extended = line:sub(check_start + 1, check_end)

  if extended:match("^%*%*.-%*%*$") then
    local inner_start = scol - 2
    local inner_end = ecol + 3
    local unwrapped = line:sub(scol + 1, ecol + 1)
    api.nvim_buf_set_text(bufnr, row, inner_start, row, inner_end, {unwrapped})
    reselect_visual(row, inner_start, inner_start + #unwrapped - 1)
  else
    wrap_with_asterisks(2)
  end
end

return M
