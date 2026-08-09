---@module 'markdown.commands.markdown_links'
--- Generates markdown links from filesystem paths for `:Markdown links create`.
local M = {}

local uv = vim.uv
local notify = require("markdown.util.notify").create("[markdown.commands.links]")
local clipboard = require("markdown.util.clipboard")
local default_ignore = require("markdown.util.ignore").as_set()

---@internal
---@param name string
---@param opts { noignore?: boolean }
---@return boolean
local function is_ignored(name, opts)
  if opts.noignore then return false end
  return default_ignore[name] == true
end

---@internal
---@param a string
---@param b string
---@return string
local function join_path(a, b)
  if vim.endswith(a, "/") then return a .. b end
  return a .. "/" .. b
end

---@internal
---@param root string?
---@return string?
local function resolve_root(root)
  if not root or root == "" then return nil end
  return vim.fn.expand(root)
end

---@internal
---@param title string
---@param path string
---@return string
local function make_link(title, path) return string.format("[%s](%s)", title, path) end

---@internal
---@param path string
---@return string
local function file_to_link(path)
  local title = vim.fn.fnamemodify(path, ":t")
  return make_link(title, path)
end

---@internal
---@param dir string
---@param opts { recursive?: boolean, noignore?: boolean }
---@param out string[]
local function scan(dir, opts, out)
  local handle = uv.fs_scandir(dir)
  if not handle then return end

  while true do
    local name, type_ = uv.fs_scandir_next(handle)
    if not name then break end
    if not is_ignored(name, opts) then
      local full_path = join_path(dir, name)
      if type_ == "file" then
        out[#out + 1] = full_path
      elseif type_ == "directory" and opts.recursive then
        scan(full_path, opts, out)
      end
    end
  end
end

---@internal
---@param directory string
---@param opts { recursive?: boolean, noignore?: boolean }
---@return string[]
local function collect_files(directory, opts)
  local result = {}
  scan(directory, opts, result)
  table.sort(result)
  return result
end

---@internal
---@param args string[]
---@return { recursive: boolean, noignore: boolean, root: string? } opts
---@return string path
local function parse_args(args)
  local opts = { recursive = false, noignore = false, root = nil }
  local path

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-r" or a == "--recursive" then
      opts.recursive = true
    elseif a == "--noignore" then
      opts.noignore = true
    elseif a == "--root" then
      opts.root = args[i + 1]
      i = i + 1
    else
      path = a
    end
    i = i + 1
  end

  return opts, path or ""
end

--- Generate links for a list of paths and return the result string.
--- Directories are expanded to their contained files.
---@param paths string[]
---@param opts? {recursive?: boolean, noignore?: boolean, root?: string}
---@return string
function M.for_paths(paths, opts)
  opts = opts or {}
  local root = resolve_root(opts.root)
  local scan_opts = {
    recursive = opts.recursive or false,
    noignore = opts.noignore or false,
  }
  local lines = {}

  for _, path in ipairs(paths) do
    path = vim.fn.expand(path)
    if vim.fn.isdirectory(path) == 1 then
      local files = collect_files(path, scan_opts)
      for i = 1, #files do
        local file_path = files[i]
        if root then file_path = join_path(root, file_path) end
        lines[#lines + 1] = file_to_link(file_path)
      end
    else
      local file_path = path
      if root then file_path = join_path(root, file_path) end
      lines[#lines + 1] = file_to_link(file_path)
    end
  end

  return table.concat(lines, "\n")
end

--- Runs `:Markdown links <path>`: generates links and copies them to the clipboard.
---@param args string[]
---@return nil
function M.run(args)
  local opts, path = parse_args(args)

  if not path or path == "" then
    notify.error("Usage: :Markdown links [-r] [--noignore] [--root <path|$ENV>] <path>")
    return
  end

  local result = M.for_paths({ path }, opts)
  clipboard.copy(result)
  notify.info("Markdown links copied to clipboard")
end

return M
