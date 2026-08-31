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

  -- Group labels for the prefixes the default keys share. Everything else
  -- which-key needs it reads off the mappings themselves.
  require("lib.nvim.bindings.keymap.which_key").add_group({
    { prefix = "<leader>t", group = "Markdown" },
    { prefix = "<leader>tv", group = "Markdown TableView" },
    { prefix = "<leader>mt", group = "Markdown Table" },
  })
end

return M
