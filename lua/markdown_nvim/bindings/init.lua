---@module 'markdown_nvim.bindings'
---@brief Orchestrates markdown.nvim's bindings: keymaps, usrcmds, autocmds.
---@description
--- Single entry point for every user-facing trigger. The editing actions live
--- in `markdown_nvim.bindings.actions` (re-exported as
--- `require("markdown_nvim").actions` for manual remapping); the default keys in
--- `markdown_nvim.bindings.keymaps` bind straight onto them. This registers the
--- binding autocmds (see `markdown_nvim.bindings.autocmds` for the
--- enable_autocmds gating) and applies the optional which-key labels.

local M = {}

--- Wire up every binding for the resolved config.
---@param cfg Mkdn.Config
---@return nil
function M.setup(cfg)
  require("markdown_nvim.bindings.autocmds").setup(cfg)
  require("markdown_nvim.bindings.which_key").setup()
end

return M
