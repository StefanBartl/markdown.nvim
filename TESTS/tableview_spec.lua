-- docs/TESTS/tableview_spec.lua — floating TableView preview closes via q/<Esc>.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local renderer = require("markdown.tableview.renderer")

  local mt = {
    header = { cells = { { content = "A" }, { content = "B" } } },
    rows = { { cells = { { content = "1" }, { content = "2" } } } },
    alignments = {},
  }

  renderer.render_markdowntable(mt, { floating = true })
  local win = vim.api.nvim_get_current_win()
  ok(vim.api.nvim_win_is_valid(win), "floating preview window opens")

  local qmap = vim.fn.maparg("q", "n", false, true)
  ok(qmap and qmap.buffer == 1, "q is bound buffer-locally on the preview buffer")
  local escmap = vim.fn.maparg("<Esc>", "n", false, true)
  ok(escmap and escmap.buffer == 1, "<Esc> is bound buffer-locally on the preview buffer")

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "x", false)
  eq(vim.api.nvim_win_is_valid(win), false, "q closes the floating preview")

  -- Re-open and close via <Esc> too.
  renderer.render_markdowntable(mt, { floating = true })
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  eq(vim.api.nvim_win_is_valid(win), false, "<Esc> closes the floating preview")
end
