-- Live check: `:Markdown table list` in the snacks and fzf-lua pickers
-- (task markdown.nvim/live-tests-im-echten-editor-snacks-fzf-lua-folds-insert-modu, point "snacks und fzf-lua").
-- A manual sheet on purpose: the list goes through pickers.nvim, whose engines are snacks.nvim and
-- fzf-lua. None of the three is a dependency of this plugin; the suite does not check them out (CI on
-- three systems, fzf-lua also needs the fzf binary). The backend choice and the two preview modes are
-- covered headless by TESTS/table_list_spec.lua (stubbed pickers.nvim). What is left is the real
-- picker: its preview and the jump.
return {
  id = "table.list-pickers",
  title = "markdown.nvim: :Markdown table list in snacks and fzf-lua",
  task = "markdown.nvim/live-tests-im-echten-editor-snacks-fzf-lua-folds-insert-modu",
  engine = "manual",
  manual = {
    "snacks engine: in a file with several tables, :Markdown table list shows every table with a preview of the file",
    "snacks engine: <M-c> switches the preview to the table alone (grid) and back",
    "snacks engine: choosing an entry jumps to that table",
    "fzf-lua engine: the same three points (preview, <M-c>, jump)",
  },
}
