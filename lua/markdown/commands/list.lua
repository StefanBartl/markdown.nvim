---@module 'markdown.commands.list'
--- `:Markdown list [what] [scope]` — collect document items in a scope, show
--- them in a picker, and jump to the chosen one.
---
---   what    `headings` (default)
---   scope   `%` current buffer (default) | `cwd` every *.md below the cwd
---           | a file path
---
--- The scope vocabulary is deliberately the same as `:Markdown links show`.
local M = {}

local notify = require("markdown.util.notify").create("[markdown.commands.list]")

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- collect
-- ---------------------------------------------------------------------------

--- Headings for a scope. Buffer-scope entries carry no `file` (they are already
--- in the current window); file- and cwd-scope entries carry their source path.
---@internal
---@param scope string
---@return Mkdn.Heading[]|nil # nil when the scope itself is invalid
local function collect_headings(scope)
  local scan = require("markdown.core.heading_scan")

  if scope == "" or scope == "%" then return scan.from_buffer(0) end

  if scope == "cwd" then
    local out = {}
    for _, path in ipairs(require("markdown.util.md_files").collect(vim.fn.getcwd())) do
      for _, h in ipairs(scan.from_file(path)) do
        out[#out + 1] = h
      end
    end
    return out
  end

  local path = vim.fn.expand(scope)
  if not uv.fs_stat(path) then
    notify.warn("list: scope not found: " .. tostring(scope))
    return nil
  end
  return scan.from_file(path)
end

-- ---------------------------------------------------------------------------
-- present
-- ---------------------------------------------------------------------------

---@internal
---@param h Mkdn.Heading
---@return string
local function format_heading(h)
  local indent = string.rep("  ", h.level - 1)
  local where = h.file and (" — " .. vim.fn.fnamemodify(h.file, ":t") .. ":" .. h.lnum)
    or (" — :" .. h.lnum)
  return string.format("%s%s %s%s", indent, string.rep("#", h.level), h.title, where)
end

--- Jump to a picked item, opening its file first when it lives elsewhere.
--- `m'` first so the jump is undoable with `<C-o>`.
---@internal
---@param h Mkdn.Heading
local function jump_to(h)
  vim.cmd("normal! m'")
  if h.file then vim.cmd.edit(vim.fn.fnameescape(h.file)) end

  -- The picked line number comes from a scan that may predate an edit, so clamp
  -- it: a stale lnum past the end would make nvim_win_set_cursor raise.
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.min(h.lnum, last), 0 })
  vim.cmd("normal! zz")
end

-- ---------------------------------------------------------------------------
-- kinds
-- ---------------------------------------------------------------------------

-- Each kind knows how to collect its items, label them, and act on a pick.
local KINDS = {
  headings = {
    collect = collect_headings,
    format = format_heading,
    on_choose = jump_to,
    label = "headings",
  },
}

-- ---------------------------------------------------------------------------
-- dispatch
-- ---------------------------------------------------------------------------

--- Runs `:Markdown list [what] [scope]`.
---@param argv string[]
---@param _ctx? table Unused; matches the dispatcher's (argv, ctx) convention.
---@return nil
function M.run(argv, _ctx)
  argv = argv or {}
  local what = argv[1] or "headings"

  local kind = KINDS[what]
  if not kind then
    notify.warn(
      string.format(
        "list: unknown option %q — expected one of: %s",
        what,
        table.concat(vim.tbl_keys(KINDS), ", ")
      )
    )
    return
  end

  local scope = argv[2] or "%"
  local items = kind.collect(scope)
  if not items then return end -- scope already reported as invalid
  if #items == 0 then
    notify.info(string.format("No %s found in scope: %s", kind.label, scope))
    return
  end

  local cfg = require("markdown.config").get()
  require("markdown.util.picker").select(items, {
    prompt = string.format("Markdown %s (%d)", kind.label, #items),
    format = kind.format,
    backend = (cfg.list and cfg.list.picker) or "hover_select",
  }, kind.on_choose)
end

--- Completion: the `what` option first, then the scope vocabulary.
---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local tokens = vim.split(vim.trim(cmdline), "%s+")
  -- tokens: {"Markdown", "list", [what], [scope]}
  local on_scope = #tokens > 3 or (#tokens == 3 and arglead == "")

  local candidates
  if on_scope then
    candidates = { "%", "cwd" }
  else
    candidates = vim.tbl_keys(KINDS)
  end

  local out = {}
  for _, c in ipairs(candidates) do
    if vim.startswith(c, arglead) then out[#out + 1] = c end
  end
  table.sort(out)
  return out
end

return M
