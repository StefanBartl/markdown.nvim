-- TESTS/tableview_group_spec.lua -- opening the TableView popup must not wipe
-- the FileType autocmd that installs TableView maps/commands on markdown buffers.
--
-- Regression: the popup's BufWriteCmd used to be created through
-- `autocmd.group("MarkdownNvimTableView", true)` -- the very group setup() put
-- its FileType autocmd in, and `clear = true` empties a group. So the first
-- popup silently removed the autocmd, and every markdown buffer opened
-- afterwards had no TableView maps or commands. The FileType handlers now live
-- in `MarkdownNvimFileType` (behind one dispatcher) and the popup has its own
-- group; this pins that the two stay apart.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api

  local function filetype_autocmds()
    local found, list =
      pcall(api.nvim_get_autocmds, { group = "MarkdownNvimFileType", event = "FileType" })
    return found and #list or 0
  end

  require("markdown.config").setup({})
  require("markdown.bindings.autocmds").setup(require("markdown.config").get())
  ok(filetype_autocmds() > 0, "setup() installs the TableView FileType autocmd")

  local renderer = require("markdown.tableview.renderer")
  local mt = {
    header = { cells = { { content = "A" }, { content = "B" } } },
    rows = { { cells = { { content = "1" }, { content = "2" } } } },
    alignments = {},
  }

  renderer.render_markdowntable(mt, { floating = true })
  ok(api.nvim_win_is_valid(api.nvim_get_current_win()), "the popup opened")
  ok(filetype_autocmds() > 0, "the FileType autocmd survives opening the popup")

  -- The popup's own :w hook is still there, in its own group.
  local popup =
    api.nvim_get_autocmds({ group = "MarkdownNvimTableViewPopup", event = "BufWriteCmd" })
  eq(#popup, 1, "the popup's BufWriteCmd lives in its own group")

  -- Close, reopen: still intact after a second popup as well.
  api.nvim_feedkeys(api.nvim_replace_termcodes("q", true, false, true), "x", false)
  renderer.render_markdowntable(mt, { floating = true })
  ok(filetype_autocmds() > 0, "the FileType autocmd survives a second popup too")
  api.nvim_feedkeys(api.nvim_replace_termcodes("q", true, false, true), "x", false)
end
