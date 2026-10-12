-- TESTS/table_popup_spec.lua -- popup with the full text of the table cell under the cursor
-- (core.table_popup): cell lookup on the escape-aware splitter, body wrapping, float lifecycle.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tp = require("markdown.core.table_popup")
  local bs = string.char(92)

  -- cell_at: the pipe in front of a cell belongs to it
  local line = "| a | b " .. bs .. "| c | d |"
  eq(tp.cell_at(line, 2).index, 1, "inside the first cell")
  eq(tp.cell_at(line, 0).index, 1, "the leading pipe belongs to the first cell")
  local c2 = tp.cell_at(line, 6)
  eq(c2.index, 2, "an escaped pipe does not start a new cell")
  eq(c2.text, "b | c", "the escape is shown as a plain pipe")
  eq(tp.cell_at(line, #line - 3).index, 3, "last cell")
  eq(tp.cell_at("|---|---|", 2), nil, "separator rows have no cell")
  eq(tp.cell_at("not a row", 2), nil, "non-table line has no cell")

  -- body wraps at word boundaries and cuts an over-long word
  local body = tp.body("alpha beta gamma delta", 11)
  eq(table.concat(body, "|"), "alpha beta|gamma delta", "wrapped at spaces")
  local cut = tp.body(string.rep("x", 25), 10)
  eq(#cut, 3, "an unbreakable word is cut by width")
  eq(table.concat(cut), string.rep("x", 25), "nothing is lost when cutting")
  eq(tp.body("", 10)[1], "", "empty text gives one empty line")

  -- show: float opens for a cut cell, not for a short one, forced shows any
  require("markdown.config").setup({ table = { truncate = { max = 10 } } })
  local long = string.rep("word ", 8)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "| A | B |",
    "|---|---|",
    "| ok | " .. long .. " |",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  eq(tp.show(buf), false, "a cell that fits shows no popup")
  eq(tp.show(buf, { force = true }), true, "force shows it anyway")
  ok(tp.is_open(), "the float is open")
  tp.close()
  eq(tp.is_open(), false, "close closes it")

  vim.api.nvim_win_set_cursor(0, { 3, 10 })
  eq(tp.show(buf), true, "a cut cell shows the popup")
  local wins = vim.api.nvim_list_wins()
  local float
  for _, w in ipairs(wins) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then float = w end
  end
  ok(float ~= nil, "a floating window exists")
  local text =
    table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false), " ")
  eq(text, vim.trim(long), "the float holds the full text")
  eq(vim.api.nvim_get_current_win() ~= float, true, "the float does not take focus")
  tp.close()
  require("markdown.config").setup({})
end
