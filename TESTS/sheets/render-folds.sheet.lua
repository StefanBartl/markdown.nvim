-- Live check: rendering and table grid in folded regions
-- (task markdown.nvim/live-tests-im-echten-editor-snacks-fzf-lua-folds-insert-modu, point "Folds").
-- Automated: the real FileType wiring sets the heading foldexpr; with everything folded only the
-- headings are on screen, after `zo` the section's table is drawn as a grid again (extmarks of the
-- grid namespace inside the opened fold), the cursor row inside the table shows its source, and
-- `zM` / `zR` close and reopen everything. Left for a person: whether that reads well.
return {
  id = "render.folds",
  title = "markdown.nvim: rendering and table grid in folded regions",
  task = "markdown.nvim/live-tests-im-echten-editor-snacks-fzf-lua-folds-insert-modu",
  engine = "rpc",
  steps = {
    { lua = 'vim.opt.shortmess:append("I")' },
    { lua = 'require("markdown").setup({})', note = "the real setup (FileType wiring, folds)" },
    {
      lua = [[vim.o.swapfile = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "# First",
        "",
        "Some text with **bold** and `code`.",
        "",
        "| Name | Note        |",
        "| ---- | ----------- |",
        "| a    | first row   |",
        "| b    | second row  |",
        "",
        "# Second",
        "",
        "- item one",
        "- [ ] todo",
        "",
        "| K | V |",
        "| - | - |",
        "| x | y |",
        "",
        "# Third",
        "",
        "last line",
      })
      vim.bo.filetype = "markdown"
      vim.api.nvim_win_set_cursor(0, { 1, 0 })]],
      note = "three heading sections, two with a table",
    },
    {
      expect = [[vim.wo.foldmethod == "expr" and vim.wo.foldexpr:find("markdown.core.fold", 1, true) ~= nil]],
      note = "the FileType wiring set the heading foldexpr",
    },
    { lua = 'require("markdown.core.render").enable(0)', note = "rendering on" },
    { lua = 'require("markdown.core.table_render").enable(0)', note = "table grid on" },
    { settle = 1000 },
    { keys = "zM", note = "close every fold" },
    {
      expect = "vim.fn.foldclosed(1) == 1 and vim.fn.foldclosed(10) == 10 and vim.fn.foldclosed(19) == 19",
    },
    { settle = 1000 },
    { screen = "all-folded" },
    { keys = "zo", note = "open the first section (cursor on its heading)" },
    { expect = "vim.fn.foldclosed(5) == -1 and vim.fn.foldclosed(10) == 10" },
    {
      wait = [[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("markdown_table_render"),
        { 4, 0 }, { 8, 0 }, {}) > 0]],
      note = "the table of the opened section is drawn as a grid",
    },
    { settle = 1000 },
    { screen = "first-open" },
    { keys = "7G", note = "cursor onto a data row of the opened table" },
    { settle = 1000 },
    { screen = "cursor-in-table" },
    { keys = "zR", note = "open every fold" },
    { expect = "vim.fn.foldclosed(15) == -1" },
    {
      wait = [[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("markdown_table_render"),
        { 14, 0 }, { 17, 0 }, {}) > 0]],
      note = "the table of the second section is drawn after it was opened",
    },
    { keys = "gg" },
    { settle = 1000 },
    { screen = "all-open" },
  },
  judge = {
    "Folded: only the headings show, no grid or rendering pieces leak into the fold lines",
    "After zo / zR the tables are drawn as a grid right away, nothing is shifted",
    "The cursor row inside the table shows its source and the rows around it stay in place",
  },
}
