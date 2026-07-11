---@module 'markdown_nvim.hl_options'
local M = {}

local blockquote = require("markdown_nvim.hl_options.hl_groups.blockquote")
local link       = require("markdown_nvim.hl_options.hl_groups.link")

local _opts = {}

function M.setup(opts)
  _opts = opts or {}

  local feat = require("markdown_nvim.config").feature_enabled
  local want_bq   = feat("hl")
  local want_link = feat("link_hl")

  local aug = vim.api.nvim_create_augroup("MarkdownNvimHL", { clear = true })

  if want_bq then
    blockquote.setup_autocmds(aug)
    blockquote.apply(_opts)
  end
  if want_link then
    link.apply(_opts)
  end

  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = aug,
    pattern  = "*",
    callback = function()
      if want_bq then blockquote.apply(_opts) end
      -- Colorschemes reset treesitter groups, so re-strip the link underline.
      if want_link then link.apply(_opts) end
    end,
  })
end

return M
