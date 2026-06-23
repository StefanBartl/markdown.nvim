---@module 'markdown_nvim.tableview.autocmds'
local api = vim.api
local M = {}

local filetypes = { "markdown", "markdown.mdx", "mdx", "md" }

function M.setup()
  local aug = api.nvim_create_augroup("MarkdownNvimTableView", { clear = true })

  api.nvim_create_autocmd("FileType", {
    group   = aug,
    pattern = filetypes,
    callback = function(ev)
      pcall(function()
        require("markdown_nvim.tableview.mappings").apply(ev.buf)
        require("markdown_nvim.tableview.commands").apply(ev)
      end)
    end,
    desc = "[markdown.nvim] Install buffer-local TableView maps & commands",
  })
end

return M
