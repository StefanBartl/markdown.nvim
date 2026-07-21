---@module 'markdown.hl_options'
local M = {}

local autocmd = require("lib.nvim.autocmd")
local blockquote = require("markdown.hl_options.hl_groups.blockquote")
local link       = require("markdown.hl_options.hl_groups.link")

local _opts = {}

function M.setup(opts)
  _opts = opts or {}

  local feat = require("markdown.config").feature_enabled
  local want_bq   = feat("hl")
  local want_link = feat("link_hl")

  -- Raw nvim_create_augroup on purpose, not autocmd.group(): that caches by
  -- name and would skip the clear on a repeated M.setup() call, leaving
  -- earlier ColorScheme/blockquote autocmds registered alongside the new ones
  -- instead of replaced.
  local aug = vim.api.nvim_create_augroup("MarkdownNvimHL", { clear = true })

  if want_bq then
    blockquote.setup_autocmds(aug)
    blockquote.apply(_opts)
  end
  if want_link then
    link.apply(_opts)
  end

  autocmd.create("ColorScheme", function()
    if want_bq then blockquote.apply(_opts) end
    -- Colorschemes reset treesitter groups, so re-strip the link underline.
    if want_link then link.apply(_opts) end
  end, {
    group   = aug,
    pattern = "*",
  })
end

return M
