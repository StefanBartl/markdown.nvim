-- TESTS/table_mode_undo_spec.lua -- table mode and undo: the reformat is joined to the user's
-- edit, and the TextChanged an undo causes does not format the table again.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local tm = require("markdown.core.table_mode")

  local function keys(s)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s, true, false, true), "ntx", false)
  end
  local function settle()
    vim.wait(500, function() return false end)
  end

  local ORIG = { "| A | B |", "|---|---|", "| a | b |" }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, ORIG)
  vim.bo[buf].undolevels = 1000
  vim.bo[buf].undolevels = vim.bo[buf].undolevels -- start a clean undo history
  vim.api.nvim_win_set_cursor(0, { 3, 2 })

  tm.enable(buf)
  keys("ixyz<Esc>")
  settle()
  local formatted = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(formatted[3]:find("xyza", 1, true) ~= nil, true, "the edit is in the buffer")
  eq(formatted[1] ~= ORIG[1], true, "and table mode re-aligned the table")

  keys("u")
  settle()
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    table.concat(ORIG, "\n"),
    "one u takes back the edit together with the reformat"
  )
  settle()
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    table.concat(ORIG, "\n"),
    "and the undo does not trigger another reformat"
  )

  keys("<C-r>")
  settle()
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    table.concat(formatted, "\n"),
    "redo brings the formatted edit back in one step and it stays"
  )

  tm.disable(buf)
end
