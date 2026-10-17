---@module 'markdown.core.fold'
--- Heading-based `foldexpr` plus the fold-toggle actions bound to keymaps.
local M = {}

---@internal
---@param bufnr integer
---@param lnum integer  1-indexed
---@return integer
local function ambient_heading_level(bufnr, lnum)
  for l = lnum - 1, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1] or ""
    local atx = line:match("^%s*(#+)%s+")
    if atx then return #atx end
  end
  return 0
end

---@class markdown.fold.TableBlock
---@field top integer       1-indexed first line of the table block
---@field sep integer|false 1-indexed delimiter row (lib separator_index), false when none
---@field level integer|nil heading level above the block, filled on first use

--- Per-buffer cache of the table blocks seen by `foldexpr`, valid for one changedtick.
--- `rows[lnum]` is the block that line `lnum` belongs to. Buffer numbers are never
--- reused, and every text change bumps the changedtick, so a stale entry is never read.
---@type { buf: integer, tick: integer, rows: table<integer, markdown.fold.TableBlock> }
local block_cache = { buf = -1, tick = -1, rows = {} }

local CHUNK = 64

--- The table block around table line `lnum` (whose text is `line`), computed once per
--- block and changedtick: a fold pass visits every line, and scanning the block from
--- each of them made a pass over an N-row table O(N^2) buffer lines.
---@internal
---@param bufnr integer
---@param lnum integer  1-indexed
---@param line string
---@return markdown.fold.TableBlock
local function table_block(bufnr, lnum, line)
  local api = vim.api
  local tick = api.nvim_buf_get_changedtick(bufnr)
  if block_cache.buf ~= bufnr or block_cache.tick ~= tick then
    block_cache = { buf = bufnr, tick = tick, rows = {} }
  end
  local hit = block_cache.rows[lnum]
  if hit then return hit end

  local is_table_line = require("markdown.core.table_fmt").is_table_line
  -- Lines above `lnum` (nearest first) and below it, fetched in chunks.
  local above, top, done = {}, lnum, false
  while not done and top > 1 do
    local chunk = api.nvim_buf_get_lines(bufnr, math.max(0, top - 1 - CHUNK), top - 1, false)
    for k = #chunk, 1, -1 do
      if not is_table_line(chunk[k]) then
        done = true
        break
      end
      above[#above + 1] = chunk[k]
      top = top - 1
    end
  end
  local below, bottom, line_count = {}, lnum, api.nvim_buf_line_count(bufnr)
  done = false
  while not done and bottom < line_count do
    local chunk = api.nvim_buf_get_lines(bufnr, bottom, bottom + CHUNK, false)
    for k = 1, #chunk do
      if not is_table_line(chunk[k]) then
        done = true
        break
      end
      below[#below + 1] = chunk[k]
      bottom = bottom + 1
    end
  end

  local block = {}
  for k = #above, 1, -1 do
    block[#block + 1] = above[k]
  end
  block[#block + 1] = line
  for k = 1, #below do
    block[#block + 1] = below[k]
  end
  local sep = require("markdown.core.table_fmt").separator_index(block, 1, #block)
  ---@type markdown.fold.TableBlock
  local info = { top = top, sep = sep and (top + sep - 1) or false }
  for l = top, bottom do
    block_cache.rows[l] = info
  end
  return info
end

--- Table-wrap continuation-row detection, mirroring
--- `core.table_wrap.unwrap_rows`'s heuristic (a table row other than the delimiter
--- row with exactly one non-empty cell, directly following a data row of the table).
--- Only consulted when `vim.b.mdtable_fold_continuations` is set (via
--- `:MDTableFoldRow`/`:MDTableFoldAll`), so this is zero-overhead otherwise.
---@internal
---@param bufnr integer
---@param lnum integer  1-indexed
---@return boolean is_continuation
---@return integer|nil level  the fold level to open (heading level above the table + 1)
local function is_table_continuation_line(bufnr, lnum)
  local table_fmt = require("markdown.core.table_fmt")
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
  if not table_fmt.is_table_line(line) then return false end

  -- The delimiter row is a property of the block (lib separator_index), not of the
  -- line: a `| | - |` continuation row or a `| - | - |` data row above it are rows.
  local block = table_block(bufnr, lnum, line)
  -- Header rows, the delimiter row and the first data row (right after the
  -- delimiter) never continue a row.
  if not block.sep or lnum <= block.sep + 1 then return false end

  local cells = table_fmt.parse_row(line)
  -- A one-cell row (a one-column table) can not be told from a continuation row;
  -- `unwrap_rows` guards the whole table by its column count, this by the row.
  if #cells < 2 then return false end
  local nonempty = 0
  for _, c in ipairs(cells) do
    if table_fmt.trim(c) ~= "" then nonempty = nonempty + 1 end
  end
  if nonempty ~= 1 then return false end
  -- A table line starts with `|`, so it is never an ATX heading: the heading level
  -- above any row of the block is the one above its first line.
  if not block.level then block.level = ambient_heading_level(bufnr, block.top) end
  return true, block.level + 1
end

---Computes the fold level for line `lnum` (used as `foldexpr`).
---@param lnum integer
---@return string|integer
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)

  if vim.b.mdtable_fold_continuations then
    local bufnr = vim.api.nvim_get_current_buf()
    local cont, level = is_table_continuation_line(bufnr, lnum)
    if cont then return ">" .. level end
  end

  local atx = line:match("^%s*(#+)%s+")
  if atx then
    -- Fenced-scope gating (on by default; gated by fenced_scope.operations.fold). A `#`-line
    -- inside a NON-markdown fenced block is code (e.g. a shell/python comment),
    -- not a heading, so it must not open a fold. Inside a markdown-family fence
    -- it stays a heading (the block is its own sub-document). Zero overhead when
    -- the fold op is disabled — the scope module isn't even consulted.
    local scope = require("markdown.scope")
    if scope.op_enabled("fold") then
      local kind = scope.row_fence_kind(vim.api.nvim_get_current_buf(), lnum - 1)
      if kind == "code" then return "=" end
    end
    return ">" .. #atx
  end

  local prev = vim.fn.getline(lnum - 1)
  if prev and prev:match("^%s*%S") and line:match("^%s*[-=]+%s*$") then return ">2" end

  return "="
end

--- Resolve the row whose fold should toggle when acting on `row`, covering both
--- heading styles, or nil when `row` is not on a heading. Mirrors `foldexpr`:
---   * ATX (`#`, `##`, …)               → the heading line itself
---   * Setext underline (`===` / `---`) → that line (the fold starts here)
---   * Setext title (next line is an underline) → the underline row
--- Used by the mouse handler so a double-click on either half of a Setext
--- heading toggles the section, not just ATX headings.
---@param bufnr integer
---@param row integer  1-indexed
---@return integer|nil  1-indexed row to toggle, or nil
function M.heading_fold_row(bufnr, row)
  local function get(r)
    if r < 1 then return nil end
    return vim.api.nvim_buf_get_lines(bufnr, r - 1, r, false)[1]
  end

  local line = get(row) or ""

  -- ATX heading.
  if line:match("^%s*#+%s") then return row end

  local is_underline = function(s) return s ~= nil and s:match("^%s*[-=]+%s*$") ~= nil end

  -- Setext underline: a `===`/`---` line under a content line (not itself a
  -- heading or another underline). The fold starts on this line.
  if is_underline(line) then
    local prev = get(row - 1)
    if prev and prev:match("%S") and not prev:match("^%s*#") and not is_underline(prev) then
      return row
    end
  end

  -- Setext title: a content line whose next line is the underline. Toggle at the
  -- underline row (where the fold actually starts).
  if line:match("%S") and not line:match("^%s*#") and not is_underline(line) then
    if is_underline(get(row + 1)) then return row + 1 end
  end

  return nil
end

-- Re-assert the window's fold state before a normal-mode fold command. When
-- these run from a menu callback (nvzone/menu) rather than a keymap, 'foldenable'
-- may be off / the method reset, which makes `za`/`zR` silent no-ops. Mirrors
-- core.fold_levels.fold_levels(), which works from the menu for this reason.
---@internal
local function ensure_folding()
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldenable = true
end

---Toggles the fold under the cursor and centers the view.
---@return nil
function M.toggle_under_cursor()
  ensure_folding()
  vim.cmd("silent! normal! za")
  vim.cmd("silent! normal! zz")
end

---Unfolds everything and centers the view.
---@return nil
function M.unfold_all_center()
  ensure_folding()
  vim.cmd("silent! normal! zR")
  vim.cmd("silent! normal! zz")
end

return M
