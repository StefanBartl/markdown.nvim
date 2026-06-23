---@module 'markdown_nvim.util.clipboard'
local M = {}

---@param text string
function M.copy(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg("*", text)
end

return M
