---@module 'markdown.util.notify'
---@brief Prefixed notification helper.
---@description
--- Uses lib.nvim's notifier when available (soft dependency), otherwise falls
--- back to a minimal `vim.notify` wrapper so the plugin runs standalone. The
--- returned object always exposes `info`/`warn`/`error`/`debug(msg)`; `debug`
--- stays gated behind `vim.g.markdown_debug`.

local M = {}

--- Create a prefixed notifier.
---@param prefix string
---@return table
function M.create(prefix)
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok and type(lib) == "table" and type(lib.create) == "function" then
    local n = lib.create(prefix)
    -- Keep markdown.nvim's gated debug (lib's debug always emits).
    local lib_debug = n.debug
    n.debug = function(msg)
      if vim.g.markdown_debug then lib_debug(msg) end
    end
    return n
  end

  -- Standalone fallback.
  local p = prefix or ""
  if type(p) == "string" and p ~= "" and not p:match("%s$") then p = p .. " " end
  local function notify(msg, level) vim.notify(p .. tostring(msg), level) end
  return {
    notify = notify,
    info = function(msg) notify(msg, vim.log.levels.INFO) end,
    warn = function(msg) notify(msg, vim.log.levels.WARN) end,
    error = function(msg) notify(msg, vim.log.levels.ERROR) end,
    debug = function(msg)
      if vim.g.markdown_debug then notify(msg, vim.log.levels.DEBUG) end
    end,
  }
end

return M
