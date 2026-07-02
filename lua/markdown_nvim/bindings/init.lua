---@module 'markdown_nvim.bindings'
---@brief Orchestrates markdown.nvim's bindings: plugs, keymaps, usrcmds, autocmds.
---@description
--- Single entry point for every user-facing trigger. Defines the `<Plug>`
--- surface up front (available for manual remapping even with the default keys
--- off), registers the binding autocmds (see `markdown_nvim.bindings.autocmds`
--- for the enable_autocmds gating), and applies the optional which-key labels.

local M = {}

--- Wire up every binding for the resolved config.
---@param cfg Mkdn.Config
---@return nil
function M.setup(cfg)
  require("markdown_nvim.bindings.plugs").define()
  require("markdown_nvim.bindings.autocmds").setup(cfg)
  require("markdown_nvim.bindings.which_key").setup()
end

return M
