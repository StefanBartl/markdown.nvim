---@module 'markdown_nvim.util.ignore'
--- Default ignore list for directory scanning.
local M = {}

local DEFAULT_IGNORE = {
  ".git", ".hg", ".svn",
  "node_modules", ".npm", ".pnpm",
  "__pycache__", ".venv", "venv", ".env",
  ".cache", ".tmp", "tmp",
  "build", "dist", "target", "out",
  ".DS_Store", "Thumbs.db",
  ".idea", ".vscode",
}

---@return table<string, boolean>
function M.as_set()
  local set = {}
  for _, v in ipairs(DEFAULT_IGNORE) do
    set[v] = true
  end
  return set
end

return M
