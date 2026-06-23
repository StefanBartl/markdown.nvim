---@module 'markdown_nvim.commands.markdown_links'
local M = {}

local uv = vim.uv
local clipboard = require("markdown_nvim.util.clipboard")
local default_ignore = require("markdown_nvim.util.ignore").as_set()

local function is_ignored(name, opts)
  if opts.noignore then return false end
  return default_ignore[name] == true
end

local function join_path(a, b)
  if vim.endswith(a, "/") then return a .. b end
  return a .. "/" .. b
end

local function resolve_root(root)
  if not root or root == "" then return nil end
  return vim.fn.expand(root)
end

local function make_link(title, path)
  return string.format("[%s](%s)", title, path)
end

local function file_to_link(path)
  local title = vim.fn.fnamemodify(path, ":t")
  return make_link(title, path)
end

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

local function collect_files(directory, opts)
  local result = {}
  scan(directory, opts, result)
  table.sort(result)
  return result
end

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

function M.run(args)
  local opts, path = parse_args(args)

  if not path or path == "" then
    vim.notify("Usage: :Markdown links [-r] [--noignore] [--root <path|$ENV>] <path>", vim.log.levels.ERROR)
    return
  end

  path = vim.fn.expand(path)
  local root = resolve_root(opts.root)
  local lines = {}

  if vim.fn.isdirectory(path) == 1 then
    local files = collect_files(path, opts)
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

  local result = table.concat(lines, "\n")
  clipboard.copy(result)
  print(result)
  vim.notify("Markdown links copied to clipboard", vim.log.levels.INFO)
end

return M
