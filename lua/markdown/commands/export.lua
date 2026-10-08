---@module 'markdown.commands.export'
--- `:Markdown export <sub>` router — thin delegators to pdfport.nvim (soft
--- dependency, pcall-guarded), not a reimplementation. Same pattern as
--- markdown.commands.image for images.nvim: `pdfport.create()` already does
--- the actual work (pandoc + a PDF engine, by default), markdown.nvim
--- neither knows nor names a producer.

local notify = require("markdown.util.notify").create("[markdown.commands.export]")
local expand_path = require("lib.nvim.cross.fs.expand_path")
local to_absolute = require("lib.nvim.cross.fs.to_absolute")
local normkey = require("lib.nvim.fs.normkey")

local M = {}

---@return table|nil pdfport module, if installed
local function pdfport()
  local ok, mod = pcall(require, "pdfport")
  return ok and mod or nil
end

--- True when both paths name the same file, whatever the spelling: relative or
--- absolute, either slash, `.`/`..` segments, a symlinked directory. A file that
--- does not exist yet (a new, unsaved buffer) is compared by its resolved
--- directory plus name. Windows paths ignore case.
---@param a string
---@param b string
---@return boolean
local function same_file(a, b)
  local ka, kb = normkey(to_absolute(a)), normkey(to_absolute(b))
  if vim.fn.has("win32") == 1 then
    ka, kb = ka:lower(), kb:lower()
  end
  return ka == kb
end

---@internal
--- Export the current buffer (or `path`, if given) to PDF via pdfport.nvim's
--- markdown producer chain.
---
--- A `path` naming another file always exports that file from disk: the
--- current buffer, modified or not, is not involved. Without a `path` (or with
--- one that names the current buffer's own file), an unmodified buffer with a
--- file on disk exports that file directly; otherwise the live buffer content is
--- sent instead (pdfport materializes it to a tmpfile itself, cleaned up after
--- the run).
---@param path string?
local function do_pdf(path)
  local mod = pdfport()
  if not mod then
    notify.warn("pdfport.nvim not installed — see https://github.com/StefanBartl/pdfport.nvim")
    return
  end
  if not mod.can_create("markdown") then
    notify.warn("pdfport.nvim has no available markdown producer (needs pandoc + a PDF engine)")
    return
  end

  local bufnr = 0
  local current = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then path = nil end
  -- expand_path, not vim.fn.expand (SEC-34): `path` is a user-typed
  -- command argument, not a Vim cmdline special.
  local file = path and expand_path(path) or current

  -- Another file was asked for: export it as it is on disk. Falling through to
  -- the live buffer here would write the wrong document into `<file>.pdf`.
  if path and not (current ~= "" and same_file(file, current)) then
    if vim.fn.filereadable(file) ~= 1 then
      notify.warn("export: file not readable: " .. file)
      return
    end
    mod.create({ inputs = { file }, from = "markdown" })
    return
  end

  local has_file = file ~= "" and vim.fn.filereadable(file) == 1

  if has_file and not vim.bo[bufnr].modified then
    mod.create({ inputs = { file }, from = "markdown" })
    return
  end

  -- No file on disk yet, or unsaved changes: export the live buffer content
  -- instead of what's (possibly stale) on disk.
  local output = has_file and (vim.fn.fnamemodify(file, ":r") .. ".pdf")
    or (vim.fn.getcwd() .. "/buffer.pdf")
  mod.create({ bufnr = bufnr, from = "markdown", output = output })
end

local subcommands = {
  pdf = do_pdf,
}

--- Runs `:Markdown export <sub> [path]` (default sub: `pdf`).
---@param argv string[]
---@return nil
function M.run(argv)
  argv = argv or {}
  local sub = argv[1] or "pdf"
  local fn = subcommands[sub]
  if not fn then
    notify.warn("export: unknown subcommand '" .. sub .. "' (supported: pdf)")
    return
  end
  fn(argv[2])
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
