-- Live check: the cell popup at the window edge
-- (task markdown.nvim/tabellen-kuerzung-und-zellen-popup-im-echten-fenster-pruefen, point 2).
-- Automated: in a small screen the popup for a cell at the right and bottom edge opens fully inside
-- the screen and closes on the next cursor move.
return {
  id = "table.popup-edge",
  title = "markdown.nvim: table cell popup at the window edge",
  task = "markdown.nvim/tabellen-kuerzung-und-zellen-popup-im-echten-fenster-pruefen",
  engine = "rpc",
  sizes = { { rows = 12, cols = 40 } },
  steps = {
    { lua = 'vim.opt.shortmess:append("I")' },
    { lua = 'require("markdown.config").setup({})' },
    {
      lua = [[local lines = {}
      for i = 1, 6 do lines[#lines + 1] = "filler " .. i end
      vim.list_extend(lines, {
        "| k | value                              |",
        "| - | ---------------------------------- |",
        "| x | the full text of the last cell here |",
      })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = "markdown"
      vim.cmd("normal! G$2h") -- inside the last cell (the closing pipe belongs to no cell)]],
      note = "a table whose last cell sits at the right and bottom edge",
    },
    {
      lua = 'require("markdown.core.table_popup").show(0, { force = true })',
      note = "open the popup",
    },
    {
      wait = [[(function()
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(w).relative ~= "" then return true end
        end
        return false
      end)()]],
      note = "a popup is open",
    },
    {
      expect = [[(function()
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(w).relative ~= "" then
            local pos = vim.api.nvim_win_get_position(w)
            local h, wd = vim.api.nvim_win_get_height(w), vim.api.nvim_win_get_width(w)
            if pos[1] < 0 or pos[2] < 0 or pos[1] + h > vim.o.lines or pos[2] + wd > vim.o.columns then
              return false
            end
          end
        end
        return true
      end)()]],
      note = "every float lies fully inside the screen",
    },
    { settle = 2000 },
    { screen = "edge" },
    { keys = "h", note = "the next cursor move" },
    {
      wait = [[#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins()) == 0]],
      note = "the popup is closed",
    },
  },
  judge = {
    "The popup at the edge is readable and not cut off",
  },
}
