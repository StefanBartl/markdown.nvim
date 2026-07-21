---@module 'markdown.commands.create'
--- `:Markdown create fs` — create filesystem entries for the markdown-link
--- targets found in the given range (visual selection) or, without a range,
--- the whole buffer. Existing paths are left untouched.
local notify = require("markdown.util.notify").create("[markdown.commands.create]")

local M = {}

local uv = vim.uv or vim.loop

--- Resolve a link target to an absolute path, relative to the buffer dir.
---@param target string
---@param base_dir string
---@return string
local function resolve(target, base_dir)
  target = vim.fn.expand(target)
  if target:match("^/") or target:match("^%a:[/\\]") then
    return vim.fn.fnamemodify(target, ":p")
  end
  local base = (base_dir ~= "" and base_dir) or vim.fn.getcwd()
  return vim.fn.fnamemodify(base .. "/" .. target, ":p")
end

--- Ensure a path exists. Trailing slash => directory, otherwise a file (with
--- its parent directories).
---@param path string
---@return "created"|"exists"|"error"
local function ensure_path(path)
  if uv.fs_stat(path) then return "exists" end

  if path:match("[/\\]$") then
    local ok, res = pcall(vim.fn.mkdir, path, "p")
    return (ok and res == 1) and "created" or "error"
  end

  local dir = vim.fn.fnamemodify(path, ":h")
  if dir and dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    local ok = pcall(vim.fn.mkdir, dir, "p")
    if not ok then return "error" end
  end

  local fh = io.open(path, "a")
  if not fh then return "error" end
  fh:close()
  return "created"
end

--- Whether a link target denotes a local filesystem path we should create.
---@param target string
---@return boolean
local function is_local_path(target)
  if target == "" then return false end
  if target:match("^#") then return false end          -- in-document anchor
  if target:match("^%a[%w+.-]*://") then return false end -- url scheme (http, file, ...)
  if target:match("^mailto:") then return false end
  return true
end

---@param lines string[]
---@param base_dir string
local function do_fs(lines, base_dir)
  local scan = require("markdown.core.link_scan")
  local created, existed, errors = {}, 0, {}
  local seen = {}

  for i, line in ipairs(lines) do
    for _, lk in ipairs(scan.from_line(line, i)) do
      if lk.kind == "mdlink" and is_local_path(lk.target) then
        local path = resolve(lk.target, base_dir)
        if not seen[path] then
          seen[path] = true
          local status = ensure_path(path)
          if status == "created" then
            created[#created + 1] = path
          elseif status == "exists" then
            existed = existed + 1
          else
            errors[#errors + 1] = path
          end
        end
      end
    end
  end

  if #created == 0 and existed == 0 and #errors == 0 then
    notify.info("create fs: no local markdown-link paths found")
    return
  end

  notify.info(string.format(
    "create fs: %d created, %d already existed%s",
    #created, existed,
    #errors > 0 and (", " .. #errors .. " failed") or ""
  ))
  if #errors > 0 then
    notify.warn("create fs failed for:\n  " .. table.concat(errors, "\n  "))
  end
end

local subcommands = {
  fs = do_fs,
}

--- @param argv string[]
--- @param ctx? { range?: integer, line1?: integer, line2?: integer }
function M.run(argv, ctx)
  argv = argv or {}
  local sub = argv[1] or "fs"
  if not subcommands[sub] then
    notify.warn("create: unknown type '" .. sub .. "' (supported: fs)")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local base_dir = vim.fn.expand("%:p:h")

  local l1, l2
  if ctx and ctx.range and ctx.range > 0 then
    l1, l2 = ctx.line1, ctx.line2
  else
    l1, l2 = 1, vim.api.nvim_buf_line_count(bufnr)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, l1 - 1, l2, false)
  subcommands[sub](lines, base_dir)
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
