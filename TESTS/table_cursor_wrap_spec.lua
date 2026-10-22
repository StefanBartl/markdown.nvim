-- TESTS/table_cursor_wrap_spec.lua -- the cursor follows its text when a table is re-wrapped:
-- with `reflow` (merged continuation rows above it) and when the cell wraps onto continuation rows.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local mdtable = require("markdown.commands.mdtable")

  local function open(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  local function under_cursor()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1]
    return line:sub(pos[2] + 1, pos[2] + 1), pos[1], line
  end

  -- (1) reflow: the wrapped row above the cursor is merged, the cursor row is mapped
  local buf = open({
    "| Key | Text |",
    "| --- | --- |",
    "| a | one two three |",
    "|  | four five six |",
    "| b | tail |",
    "| c | more |",
  })
  vim.api.nvim_win_set_cursor(0, { 5, 2 })
  mdtable.format_at_cursor(buf, { max = 40, reflow = true })
  local ch, row, line = under_cursor()
  eq(row, 4, "reflow: cursor stays on the row of `b` (merged row above)")
  eq(ch, "b", "reflow: cursor stays on the `b` cell text, got line " .. line)

  -- (2) overflow: the cell wraps, the cursor follows its text onto the continuation row
  buf = open({
    "| Key | Text |",
    "| --- | --- |",
    "| a | aaaa bbbb cccc dddd eeee ffff gggg |",
  })
  local last = #"| a | aaaa bbbb cccc dddd eeee ffff gggg" - 1
  vim.api.nvim_win_set_cursor(0, { 3, last })
  mdtable.format_at_cursor(buf, { max = 10 })
  ch, row = under_cursor()
  eq(ch, "g", "overflow: cursor stays on the last typed character")
  eq(row > 3, true, "overflow: cursor moved to a continuation row")
end
