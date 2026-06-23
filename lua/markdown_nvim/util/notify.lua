---@module 'markdown_nvim.util.notify'
local M = {}

---@param prefix string
---@return table
function M.create(prefix)
  local function notify(msg, level)
    vim.notify(prefix .. " " .. msg, level)
  end
  return {
    info  = function(msg) notify(msg, vim.log.levels.INFO) end,
    warn  = function(msg) notify(msg, vim.log.levels.WARN) end,
    error = function(msg) notify(msg, vim.log.levels.ERROR) end,
    debug = function(msg)
      if vim.g.markdown_nvim_debug then notify(msg, vim.log.levels.DEBUG) end
    end,
  }
end

return M
