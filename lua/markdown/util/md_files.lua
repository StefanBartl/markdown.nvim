---@module 'markdown.util.md_files'
---@brief Collect every *.md file under a directory, recursively.
---@description
--- Shared by `core.table_fmt`'s `scope = "cwd"` / path formatting and
--- `tableview`'s `%`/path/`cwd` preview scopes, so both features agree on what
--- "every markdown file under this directory" means.

local M = {}

---@param dir string
---@return string[]
function M.collect(dir)
  dir = dir:gsub("[/\\]$", "")
  local found = vim.fn.glob(dir .. "/**/*.md", false, true)
  for _, f in ipairs(vim.fn.glob(dir .. "/*.md", false, true)) do
    found[#found + 1] = f
  end

  -- `dir/**/*.md` already matches dir's own direct children (Vim's `**` spans
  -- zero or more directories), so the plain `dir/*.md` pass above duplicates
  -- top-level files. Dedupe on a normalized path (case-insensitive, forward
  -- slashes) rather than dropping one of the two globs, since keeping both
  -- patterns is the more portable form across glob implementations.
  local seen, result = {}, {}
  for _, f in ipairs(found) do
    local key = f:gsub("\\", "/"):lower()
    if not seen[key] then
      seen[key] = true
      result[#result + 1] = f
    end
  end
  return result
end

return M
