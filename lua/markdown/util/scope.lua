---@module 'markdown.util.scope'
---@brief Shared `scope=` vocabulary for `:Markdown` subcommands.
---@description
--- `:Markdown format` resolves its `scope=` argument through here. The
--- vocabulary matches what `links show`/`sanitize`, `list`, and
--- `table format` already accept by hand (`%`/buffer, `cwd`, an explicit
--- path) plus `cfile` -- the file named under the cursor, like `gf` -- which
--- none of those commands has needed before `format`.

local md_files = require("markdown.util.md_files")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

---@class Mkdn.ScopeResult
---@field kind "buffer"|"files"
---@field bufnr? integer   # kind == "buffer"
---@field paths? string[]  # kind == "files"; one entry for a single file

--- Resolve a `scope=` value to concrete targets.
---
---   nil / "" / "%" / "buffer"  -> the current buffer
---   "cfile"                    -> the file named under the cursor (`gf`-style)
---   "cwd"                      -> every *.md file under the working directory
---   anything else              -> an explicit file, or a directory (recurses
---                                 the same way "cwd" does)
---@param scope string?
---@return Mkdn.ScopeResult? result
---@return string? err
function M.resolve(scope)
  scope = scope or "%"

  if scope == "" or scope == "%" or scope == "buffer" then
    return { kind = "buffer", bufnr = vim.api.nvim_get_current_buf() }, nil
  end

  if scope == "cfile" then
    -- `<cfile>` is a Vim cmdline special read directly off the buffer under
    -- the cursor -- not user-typed argument text -- so `vim.fn.expand` here
    -- is the ordinary `gf` idiom, not the SEC-34 risk `expand_path` below
    -- guards against.
    local raw = vim.fn.expand("<cfile>")
    if raw == "" then return nil, "cfile: no filename under the cursor" end
    local path = require("markdown.util.path").resolve(raw)
    if not path or vim.fn.filereadable(path) == 0 then
      return nil, string.format("cfile: not a readable file: %q", raw)
    end
    return { kind = "files", paths = { path } }, nil
  end

  if scope == "cwd" then
    local cwd = vim.fn.getcwd()
    local files = md_files.collect(cwd)
    if #files == 0 then return nil, "no *.md files found under " .. cwd end
    return { kind = "files", paths = files }, nil
  end

  -- Explicit path: a directory recurses like "cwd"; a file stands alone.
  -- expand_path, not vim.fn.expand (SEC-34): `scope` is user-typed command
  -- argument text, not a Vim cmdline special.
  local path = expand_path(scope)
  if vim.fn.isdirectory(path) == 1 then
    local files = md_files.collect(path)
    if #files == 0 then return nil, "no *.md files found under " .. path end
    return { kind = "files", paths = files }, nil
  end
  if vim.fn.filereadable(path) == 0 then return nil, string.format("scope not found: %q", scope) end
  return { kind = "files", paths = { path } }, nil
end

--- Completion candidates for a bare scope argument.
---@return string[]
function M.complete_values() return { "%", "cfile", "cwd" } end

return M
