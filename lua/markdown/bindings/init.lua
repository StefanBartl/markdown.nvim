---@module 'markdown.bindings'
---@brief Orchestrates markdown.nvim's bindings: keymaps, usrcmds, autocmds.
---@description
--- Single entry point for every user-facing trigger. The editing actions live
--- in `markdown.bindings.actions` (re-exported as
--- `require("markdown").actions` for manual remapping); the default keys in
--- `markdown.bindings.keymaps` bind straight onto them. This registers the
--- binding autocmds (see `markdown.bindings.autocmds` for the
--- enable_autocmds gating) and applies the optional which-key labels.

local M = {}

--- Wire up every binding for the resolved config.
---@param cfg Mkdn.Config
---@return nil
function M.setup(cfg)
  require("markdown.bindings.autocmds").setup(cfg)
  require("markdown.bindings.which_key").setup()
end

return M
