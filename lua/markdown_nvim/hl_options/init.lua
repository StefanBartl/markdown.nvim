---@module 'markdown_nvim.hl_options'
local M = {}

local blockquote = require("markdown_nvim.hl_options.hl_groups.blockquote")

local _opts = {}

function M.setup(opts)
  _opts = opts or {}

  local aug = vim.api.nvim_create_augroup("MarkdownNvimHL", { clear = true })

  blockquote.setup_autocmds(aug)
  blockquote.apply(_opts)

  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = aug,
    pattern  = "*",
    callback = function()
      blockquote.apply(_opts)
    end,
  })
end

return M
