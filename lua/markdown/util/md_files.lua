---@module 'markdown.util.md_files'
---@brief Collect every *.md file under a directory, recursively.
---@description
--- Shared by `core.table_fmt`'s `scope = "cwd"` / path formatting and
--- `tableview`'s `%`/path/`cwd` preview scopes, so both features agree on what
--- "every markdown file under this directory" means.
---
--- What counts: a regular file whose name ends in `.md` in any letter case (`README.MD` too), found by walking the
--- tree. What does not: a directory called `docs.md`, and everything below a vendored or generated folder
--- (`SKIP_DIRS`: `node_modules`, `.git`, `.deps`, ...). Those are somebody else's files, and `scope=cwd` rewrites the
--- files it finds. The folder the walk starts in is never skipped, whatever its name: running it inside
--- `node_modules/pkg` is a choice.

local M = {}

---Folders the walk does not enter (compared with the name of the folder, not the path). Version-control
---folders, dependency folders and the usual build output.
---@type table<string, true>
M.SKIP_DIRS = {
  node_modules = true,
  [".git"] = true,
  [".hg"] = true,
  [".svn"] = true,
  [".deps"] = true,
  [".venv"] = true,
  venv = true,
  vendor = true,
  target = true,
  __pycache__ = true,
}

---@param dir string
---@return string[]
function M.collect(dir)
  dir = dir:gsub("[/\\]+$", "")
  if dir == "" then dir = "/" end
  local result = {}
  local ok, iter = pcall(vim.fs.dir, dir, {
    depth = math.huge,
    -- vim.fs.dir asks with the path below `dir` ("a/node_modules"); `false` is "do not go in"
    skip = function(path) return not M.SKIP_DIRS[path:match("[^/\\]+$")] end,
  })
  if not ok then return result end
  for name, kind in iter do
    -- a link to a file is a file we can rewrite; a link to a directory is not walked by vim.fs.dir
    if (kind == "file" or kind == "link") and name:lower():match("%.md$") then
      local path = dir .. "/" .. name
      if vim.fn.isdirectory(path) == 0 then result[#result + 1] = path end
    end
  end
  table.sort(result, function(a, b) return a:lower() < b:lower() end)
  return result
end

return M
