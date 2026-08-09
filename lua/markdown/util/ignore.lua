---@module 'markdown.util.ignore'
--- Default ignore list for directory scanning.
---@description
--- Prefers lib.nvim.fs.ignore.list's basenames when present — a broader,
--- shared list (`.claude`, `.direnv`, `zig-cache`, etc.) — falling back to
--- this plugin's own shorter list otherwise. Deliberately does NOT go through
--- lib.nvim's own `as_set()`/`normalize()` helpers: those lowercase keys on
--- Windows, which would break exact-case lookups callers here do without
--- normalizing first (e.g. a literal ".DS_Store" segment would stop matching
--- a lowercased ".ds_store" key).
local M = {}

local DEFAULT_IGNORE = {
  ".git",
  ".hg",
  ".svn",
  "node_modules",
  ".npm",
  ".pnpm",
  "__pycache__",
  ".venv",
  "venv",
  ".env",
  ".cache",
  ".tmp",
  "tmp",
  "build",
  "dist",
  "target",
  "out",
  ".DS_Store",
  "Thumbs.db",
  ".idea",
  ".vscode",
}

---@return table<string, boolean>
function M.as_set()
  local ok, lib_ignore = pcall(require, "lib.nvim.fs.ignore.list")
  local names = (ok and type(lib_ignore.basenames) == "table") and lib_ignore.basenames
    or DEFAULT_IGNORE

  local set = {}
  for _, v in ipairs(names) do
    set[v] = true
  end
  return set
end

return M
