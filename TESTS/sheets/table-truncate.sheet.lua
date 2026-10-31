-- Live check: table cell truncation in a real window
-- (task markdown.nvim/tabellen-kuerzung-und-zellen-popup-im-echten-fenster-pruefen, points 1 and 4).
-- Automated: a table with an over-wide column is shown cut with "…"; the cursor line shows its full
-- text; insert mode on that line; a double-width character right at the cut. Left for a person:
-- whether that reads well, and the collision with render-markdown/markview.
return {
  id = "table.truncate",
  title = "markdown.nvim: table cell truncation in a real window",
  task = "markdown.nvim/tabellen-kuerzung-und-zellen-popup-im-echten-fenster-pruefen",
  engine = "rpc",
  steps = {
    { lua = 'vim.opt.shortmess:append("I")' },
    { lua = 'require("markdown.config").setup({ table = { truncate = { max = 12 } } })' },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "Text above the table.",
        "",
        "| Name | Note                                  |",
        "| ---- | ------------------------------------- |",
        "| a    | a very long note that does not fit    |",
        "| b    | short                                 |",
        "| c    | 漢字漢字漢字漢字漢字 wide at the cut  |",
      })
      vim.bo.filetype = "markdown"
      vim.api.nvim_win_set_cursor(0, { 1, 0 })]],
      note = "a table with an over-wide column, cursor above it",
    },
    { lua = 'require("markdown.core.table_truncate").enable(0)', note = "truncation on" },
    { wait = "vim.wo.conceallevel >= 2", note = "conceallevel raised while truncation is on" },
    { settle = 2000 },
    { screen = "cut" },
    { keys = "4j", note = "cursor onto the long row" },
    { expect = "vim.api.nvim_win_get_cursor(0)[1] == 5" },
    { settle = 2000 },
    { screen = "cursor-line-full" },
    { input = "A", note = "insert mode at the end of the long row (keys would leave it again)" },
    { wait = "vim.api.nvim_get_mode().mode == 'i'" },
    { settle = 2000 },
    { screen = "insert" },
    { keys = "<Esc>" },
  },
  judge = {
    "The cut rows read well; the cursor line shows the full text and moving over the hidden text is usable",
    "In insert mode the full text is there to edit",
    "The double-width row is at most one column narrower than the others at the cut",
  },
  manual = {
    "With render-markdown or markview installed nothing collides",
  },
}
