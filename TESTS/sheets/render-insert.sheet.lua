-- Live check: typing in insert mode inside a table and a heading
-- (task markdown.nvim/live-tests-im-echten-editor-snacks-fzf-lua-folds-insert-modu, point "Insert-Modus").
-- Automated: with rendering and the table grid on, text typed into a table cell and into a heading
-- reaches the buffer; the lines below keep their screen row while typing (no shift); after <Esc>
-- the grid is drawn again with the new cell text. Left for a person: flicker, which only shows live.
return {
  id = "render.insert",
  title = "markdown.nvim: typing in a table and a heading in insert mode",
  task = "markdown.nvim/live-tests-im-echten-editor-snacks-fzf-lua-folds-insert-modu",
  engine = "rpc",
  steps = {
    { lua = 'vim.opt.shortmess:append("I")' },
    { lua = 'require("markdown").setup({})', note = "the real setup (FileType wiring)" },
    {
      lua = [[vim.o.swapfile = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "# Title",
        "",
        "| Name | Note       |",
        "| ---- | ---------- |",
        "| a    | first row  |",
        "| b    | second row |",
        "",
        "## Section",
        "",
        "text below",
      })
      vim.bo.filetype = "markdown"
      vim.api.nvim_win_set_cursor(0, { 1, 0 })]],
      note = "a heading, a table, a second heading",
    },
    { lua = 'require("markdown.core.render").enable(0)', note = "rendering on" },
    { lua = 'require("markdown.core.table_render").enable(0)', note = "table grid on" },
    { settle = 1000 },
    {
      lua = [[_G.sheet_rows = { vim.fn.screenpos(0, 8, 1).row, vim.fn.screenpos(0, 10, 1).row }]],
      note = "remember where the lines below the table are on screen",
    },
    { screen = "before" },
    { keys = "5G0f|w", note = "cursor onto the second cell of row a" },
    { input = "i", note = "insert mode in the cell" },
    { wait = "vim.api.nvim_get_mode().mode == 'i'" },
    { input = "NEW " },
    {
      wait = [[vim.api.nvim_get_current_line():find("NEW first row", 1, true) ~= nil]],
      note = "the typed text is in the row",
    },
    { settle = 1000 },
    {
      expect = [=[vim.fn.screenpos(0, 8, 1).row == _G.sheet_rows[1] and vim.fn.screenpos(0, 10, 1).row == _G.sheet_rows[2]]=],
      note = "typing in the table moved no line below it",
    },
    { screen = "typing-in-table", mode = true },
    {
      input = "<Esc>",
      note = "leave insert mode (with keys, the next typed key was inserted as text)",
    },
    { wait = "vim.api.nvim_get_mode().mode == 'n'" },
    { keys = "gg", note = "cursor away from the table" },
    {
      wait = [[(function()
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("markdown_table_render"),
          0, -1, { details = true })) do
          for _, vl in ipairs(m[4].virt_lines or {}) do
            for _, chunk in ipairs(vl) do
              if chunk[1]:find("NEW first row", 1, true) then return true end
            end
          end
          for _, chunk in ipairs(m[4].virt_text or {}) do
            if chunk[1]:find("NEW first row", 1, true) then return true end
          end
        end
        return false
      end)()]],
      note = "the grid is drawn again with the new cell text",
    },
    { settle = 1000 },
    { screen = "table-after-edit" },
    { input = "A", note = "insert mode at the end of the heading" },
    { wait = "vim.api.nvim_get_mode().mode == 'i'" },
    { input = " more" },
    {
      wait = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "# Title more"]],
      note = "the typed text is in the heading",
    },
    { settle = 1000 },
    {
      expect = [=[vim.fn.screenpos(0, 8, 1).row == _G.sheet_rows[1] and vim.fn.screenpos(0, 10, 1).row == _G.sheet_rows[2]]=],
      note = "typing in the heading moved no line below it",
    },
    { screen = "typing-in-heading", mode = true },
    {
      input = "<Esc>",
      note = "leave insert mode (with keys, the next typed key was inserted as text)",
    },
  },
  judge = {
    "While typing in the cell, the row shows its source and the rows around it stay in place",
    "While typing in the heading, it shows its source; after <Esc> it is rendered again",
    "Live: no flicker while typing fast in the table and in the heading (look at it in the real editor)",
  },
}
