-- TESTS/table_delimiter_consumers_spec.lua -- the cell popup, the table lint and the
-- continuation-row fold tell the delimiter row by the table block (lib separator_index),
-- not by the line: a `| - | - |` data row, a dash header and a `| | - |` continuation row
-- are rows like any other.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local tp = require("markdown.core.table_popup")
  local table_wrap = require("markdown.core.table_wrap")
  local fold = require("markdown.core.fold")
  local dashes = ("-"):rep(50)

  -- popup: a cut dash data row and a cut dash header get the full-text popup
  require("markdown.config").setup({ table = { truncate = { max = 10 } } })
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "| A | B |",
    "|---|---|",
    "| " .. dashes .. " | - |",
    "| x | y |",
  })
  local cut = require("markdown.core.table_truncate").compute(
    api.nvim_buf_get_lines(buf, 0, -1, false),
    { max = 10 }
  )
  ok(cut[3] ~= nil, "precondition: truncation cuts the dash data row")
  api.nvim_win_set_cursor(0, { 3, 4 })
  eq(tp.show(buf), true, "a cut dash data row shows the popup")
  tp.close()
  eq(tp.in_table(buf, 3), true, "a dash data row sits in a table")
  api.nvim_win_set_cursor(0, { 2, 2 })
  eq(tp.show(buf, { force = true }), false, "the delimiter row has no cell")

  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "| " .. dashes .. " | - |",
    "|---|---|",
    "| x | y |",
  })
  api.nvim_win_set_cursor(0, { 1, 4 })
  eq(tp.show(buf), true, "a cut dash header shows the popup")
  tp.close()
  api.nvim_win_set_cursor(0, { 2, 2 })
  eq(tp.show(buf, { force = true }), false, "the delimiter under a dash header has no cell")

  -- cell_at: the caller says which line is the delimiter row; alone a dash line counts as one
  local row = "| - | - |"
  eq((tp.cell_at(row, 2, false) or {}).index, 1, "a dash data row has cells")
  eq(tp.cell_at(row, 2, true), nil, "the delimiter row has none")
  eq(tp.cell_at(row, 2), nil, "a lone dash line is judged on its own")
  require("markdown.config").setup({})

  -- lint: a dash data row has its cells counted, a dash header is fine
  local issues = table_wrap.find_issues({ "| A | B |", "|---|---|", "| - |" })
  eq(#issues, 1, "a one-cell dash data row is reported")
  eq(issues[1] and issues[1].line, 3, "on its own line")
  eq(
    #table_wrap.find_issues({ "| - | - |", "|---|---|", "| a | b |" }),
    0,
    "a dash header over a delimiter row is no issue"
  )
  local missing = table_wrap.find_issues({ "| A | B |", "| a | b |", "|---|---|" })
  eq(missing[1] and missing[1].line, 1, "a delimiter row not on line 2 is still missing")

  -- fold: continuation rows next to dash rows are found like any other
  local function is_cont(lnum) return tostring(fold.foldexpr(lnum)):sub(1, 1) == ">" end
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "| A | B |",
    "|---|---|",
    "| x | |",
    "| a | b |",
    "| | - |",
    "| - | - |",
    "| | more |",
  })
  vim.b[buf].mdtable_fold_continuations = true
  eq(is_cont(1), false, "the header is no continuation")
  eq(is_cont(2), false, "the delimiter row is no continuation")
  eq(is_cont(3), false, "the first data row is no continuation")
  eq(is_cont(5), true, "a `| | - |` row continues the row above")
  eq(is_cont(6), false, "a dash data row with two cells is a row")
  eq(is_cont(7), true, "a row under a dash data row continues it")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "| - | - |", "|---|---|", "| x | |", "| | y |" })
  eq(is_cont(3), false, "under a dash header the first data row is no continuation")
  eq(is_cont(4), true, "under a dash header the next one is")
  vim.b[buf].mdtable_fold_continuations = nil
  api.nvim_buf_delete(buf, { force = true })
end
