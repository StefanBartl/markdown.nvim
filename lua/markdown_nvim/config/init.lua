---@module 'markdown_nvim.config'
---@brief Runtime config store: merge user options over DEFAULTS, expose get().
---@description
--- The public require path stays `markdown_nvim.config` (this init.lua). The
--- immutable defaults live in `markdown_nvim.config.DEFAULTS`; user options are
--- deep-merged on top on setup(). `get()` returns the resolved table.

local M = {}

local DEFAULTS = require("markdown_nvim.config.DEFAULTS")

local _cfg = vim.deepcopy(DEFAULTS)

---@param opts Mkdn.Config|nil
function M.setup(opts)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
end

---@return Mkdn.Config
function M.get()
  return _cfg
end

return M
