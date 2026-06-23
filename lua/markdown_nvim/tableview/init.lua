---@module 'markdown_nvim.tableview'
local M = {}

function M.setup(_opts)
  require("markdown_nvim.tableview.autocmds").setup()
end

return M
