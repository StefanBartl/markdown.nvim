---@module 'markdown.scope'
---@brief Resolve the "document scope" an operation should act on.
---@description
--- The single place that answers: *given the cursor, should this markdown
--- operation act on a fenced sub-document or on the whole file?* Every
--- scope-aware op (TOC, heading nav, anchor jump, heading shift) consults
--- `M.detect` instead of scanning the raw buffer itself.
---
--- Two scope kinds:
---   - `block`  → cursor sits inside a markdown-family fenced block; ops act on
---                the block interior only. `first`/`last` are 1-indexed inclusive.
---   - `buffer` → cursor is outside; ops act on the whole file but must skip
---                every fenced block interior (`exclude`, 1-indexed ranges).
---
--- When the feature is disabled, `M.detect` returns nil and callers fall back to
--- their original whole-buffer behavior, so turning it off is a true no-op.
---
--- Fence detection is delegated to color_my_ascii's public fence API when
--- available (the robust shared source of truth); otherwise a small built-in
--- scanner is used. See `markdown.scope.builtin`.

local notify = require("markdown.util.notify").create("[markdown.scope]")

local M = {}

local api = vim.api
local cfg = require("markdown.config").get

--- Runtime enable override set by `:Markdown scope on|off|toggle`.
--- nil = follow config; true/false = force.
---@type boolean|nil
local runtime_enable = nil

--- Resolved backend, memoized. Provider choice is a setup-time concern.
---@type { kind: "cma", fences: table }|{ kind: "builtin", mod: table }|nil
local backend = nil

--- Whether the fenced-scope feature is active.
---@return boolean
function M.enabled()
  -- Hard gate: the "fenced_scope" feature can be turned off entirely.
  if not require("markdown.config").feature_enabled("fenced_scope") then return false end
  if runtime_enable ~= nil then return runtime_enable end
  local c = cfg().fenced_scope
  return not (c and c.enable == false)
end

--- Whether a specific operation should be scoped (feature on AND op not opted out).
---@param op "toc"|"nav"|"jump"|"shift"|"fold"
---@return boolean
function M.op_enabled(op)
  if not M.enabled() then return false end
  local c = cfg().fenced_scope or {}
  local ops = c.operations or {}
  return ops[op] ~= false
end

--- Force the feature on/off at runtime (overrides config).
---@param value boolean
---@return nil
function M.set_enabled(value) runtime_enable = value and true or false end

--- Toggle the feature at runtime.
---@return boolean now Enabled state after toggling.
function M.toggle()
  M.set_enabled(not M.enabled())
  return M.enabled()
end

--- Clear the memoized backend (test/reload helper).
---@return nil
function M._reset_backend() backend = nil end

--- Configured markdown-family language tags.
---@return string[]
local function langs()
  local c = cfg().fenced_scope
  return (c and c.langs) or { "markdown", "md", "mdx", "ascii-markdown", "ascii-md" }
end

--- Build a lowercase set from the configured langs.
---@return table<string, boolean>
local function langs_set()
  local set = {}
  for _, l in ipairs(langs()) do
    if type(l) == "string" then set[l:lower()] = true end
  end
  return set
end

--- Resolve (and memoize) the fence-detection backend.
---@return { kind: "cma", fences: table }|{ kind: "builtin", mod: table }
local function get_backend()
  if backend then return backend end

  local pref = (cfg().fenced_scope and cfg().fenced_scope.provider) or "auto"

  if pref ~= "builtin" then
    local ok, cma = pcall(require, "color_my_ascii")
    if ok and type(cma) == "table" and type(cma.fences) == "table" then
      backend = { kind = "cma", fences = cma.fences }
      return backend
    end
    if pref == "color_my_ascii" then
      notify.warn("provider 'color_my_ascii' requested but unavailable; using built-in scanner")
    end
  end

  backend = { kind = "builtin", mod = require("markdown.scope.builtin") }
  return backend
end

--- Find the markdown-family fenced block whose interior contains `row0`.
---@param bufnr integer
---@param row0 integer 0-indexed
---@return table|nil block A block with open_row/close_row/content_start/content_end/lang
local function md_block_at(bufnr, row0)
  local be = get_backend()
  if be.kind == "cma" then return be.fences.block_at(bufnr, row0, { lang = langs() }) end
  return be.mod.block_at(bufnr, row0, { lang = langs_set() })
end

--- List every fenced block in the buffer (any language).
---@param bufnr integer
---@return table[]
local function all_blocks(bufnr)
  local be = get_backend()
  if be.kind == "cma" then return be.fences.list_blocks(bufnr) end
  return be.mod.list_blocks(bufnr)
end

---@class Mkdn.Scope
---@field kind "block"|"buffer"
---@field first integer 1-indexed first line the op may touch
---@field last integer 1-indexed last line the op may touch
---@field block? table The enclosing markdown block (kind == "block")
---@field exclude? { first: integer, last: integer }[] 1-indexed fenced interiors to skip (kind == "buffer")

--- Resolve the scope for `bufnr` at `row0` (defaults to the cursor row).
--- Returns nil when the feature is disabled (caller keeps its old behavior).
---@param bufnr? integer
---@param row0? integer 0-indexed
---@return Mkdn.Scope|nil
function M.detect(bufnr, row0)
  if not M.enabled() then return nil end
  bufnr = bufnr or api.nvim_get_current_buf()
  if row0 == nil then row0 = api.nvim_win_get_cursor(0)[1] - 1 end

  local block = md_block_at(bufnr, row0)
  if block then
    return {
      kind = "block",
      first = block.content_start + 1, -- 1-indexed first interior line
      last = block.content_end, -- 1-indexed last interior line
      block = block,
    }
  end

  local exclude = {}
  for _, b in ipairs(all_blocks(bufnr)) do
    if b.content_end > b.content_start then -- non-empty interior
      exclude[#exclude + 1] = { first = b.content_start + 1, last = b.content_end }
    end
  end

  return {
    kind = "buffer",
    first = 1,
    last = api.nvim_buf_line_count(bufnr),
    exclude = exclude,
  }
end

--- Whether a 1-indexed row falls inside an excluded fenced interior.
--- Always false for block scopes (their whole range is fair game).
---@param scope Mkdn.Scope
---@param row1 integer 1-indexed
---@return boolean
function M.is_excluded(scope, row1)
  if not scope or scope.kind ~= "buffer" or not scope.exclude then return false end
  for _, r in ipairs(scope.exclude) do
    if row1 >= r.first and row1 <= r.last then return true end
  end
  return false
end

-- Per-buffer memoized block list for the hot foldexpr path, keyed by changedtick.
---@type table<integer, { tick: integer, blocks: { content_start: integer, content_end: integer, is_md: boolean }[] }>
local fold_cache = {}

require("lib.nvim.bindings.autocmd").create(
  { "BufDelete", "BufWipeout" },
  function(ev) fold_cache[ev.buf] = nil end,
  {
    group = "MarkdownNvimScopeFoldCache",
    desc = "[markdown.nvim] Invalidate scope fold cache on buffer delete",
  }
)

---@param bufnr integer
---@return { content_start: integer, content_end: integer, is_md: boolean }[]
local function fold_blocks(bufnr)
  local tick = api.nvim_buf_get_changedtick(bufnr)
  local c = fold_cache[bufnr]
  if c and c.tick == tick then return c.blocks end

  local set = langs_set()
  local out = {}
  for _, b in ipairs(all_blocks(bufnr)) do
    out[#out + 1] = {
      content_start = b.content_start,
      content_end = b.content_end,
      is_md = set[(b.lang or ""):lower()] == true,
    }
  end
  fold_cache[bufnr] = { tick = tick, blocks = out }
  return out
end

--- Classify a 0-indexed row for folding:
---   "outside" → not inside any fenced block interior (incl. delimiter lines)
---   "md"      → inside a markdown-family fenced block interior
---   "code"    → inside any other fenced block interior
--- Memoized per changedtick, so it's cheap to call once per line in a foldexpr.
---@param bufnr integer
---@param row0 integer 0-indexed
---@return "outside"|"md"|"code"
function M.row_fence_kind(bufnr, row0)
  for _, b in ipairs(fold_blocks(bufnr)) do
    if row0 >= b.content_start and row0 <= (b.content_end - 1) then
      return b.is_md and "md" or "code"
    end
  end
  return "outside"
end

return M
