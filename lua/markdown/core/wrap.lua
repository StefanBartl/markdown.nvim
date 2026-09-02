---@module 'markdown.core.wrap'
--- Toggle bold (`**`) around a normal-selection word or a visual selection.
local notify = require("markdown.util.notify").create("[markdown.core.wrap]")

local M = {}

local api = vim.api
local fn = vim.fn
local cfg = require("markdown.config").get

--- Whether `mode()` reports one of the three visual modes. Spelled out per
--- character rather than as a pattern class so blockwise mode's control
--- character does not have to appear as an escape in a Lua pattern.
---@internal
---@param mode string
---@return boolean
local function is_visual_mode(mode)
  local first = mode:sub(1, 1)
  return first == "v" or first == "V" or first:byte() == 22
end

--- Whether the selection being acted on is linewise (`V`).
---
--- Read from `mode()` while the mapping still runs in visual mode, and from
--- `visualmode()` when the selection is only reachable through the `'<`/`'>`
--- marks -- the `:'<,'>` entry point, where visual mode is already over.
---@internal
---@return boolean
local function selection_is_linewise()
  local mode = fn.mode()
  if is_visual_mode(mode) then return mode:sub(1, 1) == "V" end
  return fn.visualmode() == "V"
end

--- The 0-indexed row range a linewise selection covers.
---
--- Columns are deliberately not read: in `V` mode the cursor and the `v`
--- anchor still carry columns, and taking them literally is exactly the bug
--- this branch exists to avoid -- `V**` used to wrap from wherever the cursor
--- happened to sit to wherever the anchor happened to sit, mid-word, instead
--- of wrapping the line.
---@internal
---@return integer? first 0-indexed
---@return integer? last 0-indexed
local function get_linewise_rows()
  local row1, row2
  if is_visual_mode(fn.mode()) then
    row1 = api.nvim_win_get_cursor(0)[1] - 1
    local ok, vstart = pcall(fn.getpos, "v")
    if not (ok and vstart) then return nil, nil end
    row2 = vstart[2] - 1
  else
    local ok_start, start_pos = pcall(fn.getpos, "'<")
    local ok_end, end_pos = pcall(fn.getpos, "'>")
    if not (ok_start and ok_end and start_pos and end_pos) then return nil, nil end
    row1 = start_pos[2] - 1
    row2 = end_pos[2] - 1
  end
  return math.min(row1, row2), math.max(row1, row2)
end

---@internal
---@return integer? row
---@return integer? scol
---@return integer? ecol
local function get_visual_selection()
  if is_visual_mode(fn.mode()) then
    local cursor = api.nvim_win_get_cursor(0)
    local vstart_ok, vstart = pcall(fn.getpos, "v")
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
  fn.setpos("'<", { 0, row + 1, scol + 1, 0 })
  fn.setpos("'>", { 0, row + 1, ecol + 1, 0 })
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

  api.nvim_buf_set_text(bufnr, row, scol, row, ecol + 1, { wrapped })

  if cfg().keep_inner_selection then
    reselect_visual(row, scol + count, scol + count + #selected_text - 1)
  else
    reselect_visual(row, scol, ecol + (2 * count))
  end
end

--- Re-select `first`..`last` (0-indexed) after a linewise edit. `gv` restores
--- the visual *mode* on its own, so only the marks need moving -- the lines
--- were rewritten in place and their columns changed.
---@internal
---@param first integer
---@param last integer
local function reselect_linewise(first, last)
  fn.setpos("'<", { 0, first + 1, 1, 0 })
  fn.setpos("'>", { 0, last + 1, 1, 0 })
  local reselect = api.nvim_replace_termcodes("<Esc>gv", true, false, true)
  api.nvim_feedkeys(reselect, "nx", false)
end

--- Split a line into the part that must stay outside the wrap, its content,
--- and its trailing whitespace.
---
--- "The whole line" means the whole line's *text*, not its markup: indent, a
--- blockquote's `>`, a list bullet or number, a task-list checkbox and an ATX
--- heading's hashes all stay where they are, because `**- item**` is no longer
--- a list item and `**## Title**` is no longer a heading. Trailing whitespace
--- stays outside too -- two trailing spaces are markdown's hard line break,
--- and `**text  **` is neither bold nor a line break.
---@internal
---@param line string
---@return string lead Indent plus any block markers
---@return string body The text to wrap
---@return string trail
local function split_line(line)
  local lead = line:match("^%s*") or ""
  local pos = #lead + 1

  -- Blockquotes nest, so consume every `>` level.
  while true do
    local quote = line:match("^>%s*", pos)
    if not quote then break end
    lead, pos = lead .. quote, pos + #quote
  end

  local marker = line:match("^[-*+]%s+", pos)
    or line:match("^%d+[.)]%s+", pos)
    or line:match("^#+%s+", pos)
  if marker then
    lead, pos = lead .. marker, pos + #marker
    local checkbox = line:match("^%[[ xX]%]%s+", pos)
    if checkbox then
      lead, pos = lead .. checkbox, pos + #checkbox
    end
  end

  local body, trail = line:sub(pos):match("^(.-)(%s*)$")
  return lead, body or "", trail or ""
end

--- Whether a line's content is already wrapped in `**`. The same prefix/suffix
--- test the charwise path applies to its extended slice, so both halves of the
--- toggle agree on what "already bold" means.
---@internal
---@param body string
---@return boolean
local function is_bold(body) return #body >= 4 and body:sub(1, 2) == "**" and body:sub(-2) == "**" end

--- Toggle `**bold**` on every selected line, a whole line at a time.
---
--- The direction is decided once for the range rather than per line, so a
--- mixed selection has one predictable outcome: if every non-blank line is
--- already bold the range is unwrapped, otherwise the lines that are not bold
--- get wrapped and the ones that already are stay as they are. Blank lines are
--- skipped -- a lone `****` is not bold, just noise.
---@internal
---@param first integer 0-indexed
---@param last integer 0-indexed
local function toggle_linewise_bold(first, last)
  local bufnr = api.nvim_get_current_buf()
  local lines = api.nvim_buf_get_lines(bufnr, first, last + 1, false)
  if #lines == 0 then
    notify.warn("No valid selection")
    return
  end

  local all_bold, any_content = true, false
  for _, line in ipairs(lines) do
    local _, body = split_line(line)
    if body ~= "" then
      any_content = true
      if not is_bold(body) then all_bold = false end
    end
  end
  if not any_content then
    notify.warn("Nothing to bold")
    return
  end

  local out = {}
  for i, line in ipairs(lines) do
    local lead, body, trail = split_line(line)
    if body == "" or (is_bold(body) and not all_bold) then
      out[i] = line
    elseif all_bold then
      out[i] = lead .. body:sub(3, -3) .. trail
    else
      out[i] = lead .. "**" .. body .. "**" .. trail
    end
  end

  api.nvim_buf_set_lines(bufnr, first, last + 1, false, out)
  reselect_linewise(first, last)
end

---Toggles `**bold**` around the current visual selection.
---In linewise (`V`) mode the selection is the whole line, columns and all.
---@return nil
function M.toggle_visual_bold()
  if selection_is_linewise() then
    local first, last = get_linewise_rows()
    if not (first and last) then
      notify.warn("No valid selection")
      return
    end
    toggle_linewise_bold(first, last)
    return
  end

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
    api.nvim_buf_set_text(bufnr, row, inner_start, row, inner_end, { unwrapped })
    reselect_visual(row, inner_start, inner_start + #unwrapped - 1)
  else
    wrap_with_asterisks(2)
  end
end

return M
