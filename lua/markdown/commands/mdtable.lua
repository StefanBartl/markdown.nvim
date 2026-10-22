---@module 'markdown.commands.mdtable'
---@brief High-level operations behind the `:MDTable*` commands: resolving
--- effective wrap opts (config -> profile -> per-table directive), applying
--- wrap/unwrap to a table (with logical-cell cursor restore + continuation
--- gutter signs), scope variants (cursor/buffer/visual/visible), column
--- nudge, alignment cycling, profiles, flavor, lint/fix, CSV roundtrip, and
--- the debounced-resize / selective-on-save reflow hooks.
local table_wrap = require("markdown.core.table_wrap")
local table_fmt = require("markdown.core.table_fmt")
local notify = require("markdown.util.notify").create("[markdown.commands.mdtable]")
local expand_path = require("lib.nvim.cross.fs.expand_path")
local clipboard = require("markdown.util.clipboard")

local api = vim.api
local M = {}

local SIGN_NS = api.nvim_create_namespace("markdown_table_wrap_signs")
local LINT_NS = api.nvim_create_namespace("markdown_table_lint")

-- ─────────────────────────────────────────────────────────────────────────────
-- Wrap-opt resolution: config.table.wrap -> wrap_profiles[b:mdtable_profile]
-- -> per-table `<!-- mdwrap: ... -->` directive -> explicit overrides.
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@return table
local function table_cfg()
  local ok, config = pcall(require, "markdown.config")
  return (ok and config.get().table) or {}
end

---Parses a `<!-- mdwrap: auto=false max=40 min=12 pad=1 join=br -->` directive line.
---@param line string?
---@return table? opts
function M.parse_directive(line)
  local body = line and line:match("^%s*<!%-%-%s*mdwrap:%s*(.-)%s*%-%->%s*$")
  if not body then return nil end
  local opts = {}
  for key, val in body:gmatch("([%w_]+)=(%S+)") do
    if key == "auto" then
      opts.auto = (val == "true" or val == "1")
    elseif key == "max" then
      opts.max = tonumber(val)
    elseif key == "min" then
      opts.min = tonumber(val)
    elseif key == "pad" then
      opts.pad = tonumber(val)
    elseif key == "join" then
      opts.join = (val == "br" or val == "<br>") and "<br>" or " "
    end
  end
  return opts
end

---@internal Directive comment line immediately above `table_start` (1-indexed), if any.
---@param bufnr integer
---@param table_start integer
---@return table? opts
local function find_directive(bufnr, table_start)
  if table_start <= 1 then return nil end
  local line = api.nvim_buf_get_lines(bufnr, table_start - 2, table_start - 1, false)[1]
  return M.parse_directive(line)
end

---Resolves the effective wrap opts for the table starting at `table_start`
---(config defaults -> active profile -> per-table directive -> `overrides`).
---@param bufnr integer|nil  # nil: no buffer (file scopes), no profile
---@param table_start integer?
---@param overrides table?
---@param lines string[]|nil  # the text the table is in, when there is no buffer to read the directive from
---@return table
function M.resolve_wrap_opts(bufnr, table_start, overrides, lines)
  local cfg = table_cfg()
  local base = cfg.wrap or {}
  local profile_name = bufnr and vim.b[bufnr] and vim.b[bufnr].mdtable_profile
  local profile = profile_name and (cfg.wrap_profiles or {})[profile_name]

  local directive
  if table_start then
    if lines then
      directive = table_start > 1 and M.parse_directive(lines[table_start - 1]) or nil
    elseif bufnr then
      directive = find_directive(bufnr, table_start)
    end
  end
  -- Later wins: config -> profile -> per-table directive -> explicit overrides
  -- (`max=` on the command line beats a directive comment).
  local opts =
    vim.tbl_deep_extend("force", {}, base, profile or {}, directive or {}, overrides or {})

  if opts.flavor == "github" then
    opts.min = math.max(opts.min or 1, 3)
    opts.separator_style = "spaced"
  elseif opts.flavor == "loose" then
    opts.separator_style = opts.separator_style or "compact"
  end

  if opts.auto then
    local ok, width = pcall(api.nvim_win_get_width, 0)
    opts.win_width = ok and width or nil
  end

  -- Configured overrides first, then the call's (`skip=`): per column the later
  -- entry wins field by field, so `skip=1` no longer drops a configured `max`.
  local col_overrides = vim.list_slice(cfg.col_overrides or {})
  vim.list_extend(col_overrides, (overrides and overrides.col_overrides) or {})
  opts.col_overrides = #col_overrides > 0 and col_overrides or nil
  opts.header_align = opts.header_align or cfg.header_align
  opts.entry_align = opts.entry_align or cfg.entry_align
  return opts
end

--- Column width `:Markdown table format` caps at when it wraps and neither a
--- `max` nor `auto` is configured ("a fixed maximum").
M.DEFAULT_FORMAT_MAX = 40

---Whether a `:Markdown table format` call wraps: an explicit `wrap` flag wins,
---then a given `max`/`auto`, then `table.wrap.enabled`.
---@param overrides table?
---@return boolean
function M.wants_wrap(overrides)
  overrides = overrides or {}
  if overrides.wrap ~= nil then return overrides.wrap and true or false end
  if overrides.max or overrides.auto then return true end
  return (table_cfg().wrap or {}).enabled == true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Continuation-row gutter signs (virtual, never written to the buffer).
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
local function clear_signs(bufnr, start_line, end_line)
  pcall(api.nvim_buf_clear_namespace, bufnr, SIGN_NS, math.max(start_line - 1, 0), end_line)
end

---@internal
---@param bufnr integer
---@param start_line integer
---@param layout Mkdn.TableWrapLayoutEntry[]
---@param opts table
local function place_signs(bufnr, start_line, layout, opts)
  local marker = opts.continuation_marker
  clear_signs(bufnr, start_line, start_line + #layout)
  if not marker or marker == "" then return end
  for i, entry in ipairs(layout) do
    if entry.is_continuation then
      local lnum = start_line - 1 + i - 1
      pcall(api.nvim_buf_set_extmark, bufnr, SIGN_NS, lnum, 0, {
        -- Character-based (not byte-based) slicing: sign_text allows up to 2
        -- display cells, but the default marker (`↳`) is multi-byte UTF-8 --
        -- a byte-count `:sub` would cut mid-codepoint and make the extmark
        -- call fail validation (silently, under this `pcall`).
        sign_text = vim.fn.strcharpart(marker, 0, 2),
        sign_hl_group = "Comment",
      })
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cursor <-> logical (row, col) mapping, so a reflow lands back in the same
-- logical cell instead of just the same physical line number.
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param line string
---@return { [1]: integer, [2]: integer }[] ranges  # 1-based byte range of each raw cell (escape-aware)
local function cell_ranges(line)
  local _, ranges = require("lib.nvim.markdown.table").split_cells(line)
  return ranges
end

---@internal
---@param bufnr integer
---@param line_1idx integer
---@param byte_col_0idx integer
---@param col_count integer
---@return integer col_index  1-indexed
local function column_at(bufnr, line_1idx, byte_col_0idx, col_count)
  local raw = api.nvim_buf_get_lines(bufnr, line_1idx - 1, line_1idx, false)[1] or ""
  local c1 = byte_col_0idx + 1
  local ranges = cell_ranges(raw)
  -- Before the first pipe (indent of a table in a list item): the first column.
  local col_index = (#ranges > 0 and c1 >= ranges[1][1] - 1) and #ranges or 1
  for i, rng in ipairs(ranges) do
    -- the pipe in front of a cell belongs to it
    if c1 >= rng[1] - 1 and c1 <= rng[2] then
      col_index = i
      break
    end
  end
  return math.min(col_index, math.max(col_count, 1))
end

---@internal
---@param parsed table
---@param cursor_line integer
---@return integer logical_row  # 0 = the separator row
local function logical_row_at(parsed, cursor_line)
  local physical_idx = cursor_line - parsed.start_line + 1
  if physical_idx <= 1 then return 1 end -- header
  if physical_idx == 2 then return 0 end -- separator: the layout has an entry for it
  return math.max(1, math.min(physical_idx - 1, #parsed.rows))
end

---@internal Where the cursor is inside its cell, in characters from the cell's first
---non-space character (0 when it is in the padding). Characters, not bytes: padding
---changes on a re-format, and a byte offset can land inside a multibyte character.
---@param raw string
---@param byte_col_0idx integer
---@param col_index integer
---@return integer
local function chars_into_cell(raw, byte_col_0idx, col_index)
  local rng = cell_ranges(raw)[col_index]
  if not rng then return 0 end
  local lead = #raw:sub(rng[1], rng[2]):match("^%s*")
  local content_start = rng[1] + lead
  local c1 = byte_col_0idx + 1
  if c1 <= content_start then return 0 end
  -- skipcc: `byteidx` (used to map it back) counts a base character with its
  -- composing marks / variation selector as one character, so must this.
  return vim.fn.strchars(raw:sub(content_start, c1 - 1), 1)
end

---@internal 0-indexed byte column of the cursor in cell `col_index` of `line`: `chars`
---characters into the cell content, clamped to the content, always on a character start.
---An empty cell keeps the cursor inside it (on its first byte).
---@param line string
---@param col_index integer
---@param chars? integer
---@return integer
local function col_in_cell(line, col_index, chars)
  local rng = cell_ranges(line)[col_index]
  if not rng then return 0 end
  local text = line:sub(rng[1], rng[2])
  local lead = #text:match("^%s*")
  if lead >= #text then return rng[1] - 1 end
  local col = rng[1] - 1 + lead -- first content byte
  if chars and chars > 0 then
    local content = vim.trim(text)
    local n = math.min(chars, math.max(vim.fn.strchars(content, 1) - 1, 0))
    col = col + vim.fn.byteidx(content, n)
  end
  return col
end

---@internal Find the physical (rendered) row/col for `logical_row`/`col_index`.
---@param rendered string[]
---@param layout Mkdn.TableWrapLayoutEntry[]
---@param logical_row integer
---@param col_index integer
---@param chars? integer  # characters into the cell content (see `chars_into_cell`)
---@return integer? physical_row  1-indexed into `rendered`
---@return integer? byte_col  0-indexed
local function restore_position(rendered, layout, logical_row, col_index, chars)
  local target_pi
  for i, entry in ipairs(layout) do
    if entry.logical_index == logical_row and not entry.is_continuation then
      target_pi = i
      break
    end
  end
  if not target_pi then return nil, nil end
  local line = rendered[target_pi]
  if not line then return nil, nil end
  return target_pi, col_in_cell(line, col_index, chars)
end

---Where the cursor is, as (row, cell, characters into the cell), for a caller that
---re-formats a table without continuation rows (table mode, natural widths) and
---puts the cursor back with `restore_cursor`. Nil when the current window does not
---show `bufnr`.
---@param bufnr integer
---@return { row: integer, col_index: integer, chars: integer }|nil
function M.snapshot_cursor(bufnr)
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= bufnr then return nil end
  local cur = api.nvim_win_get_cursor(win)
  local raw = api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], false)[1] or ""
  local col_index = column_at(bufnr, cur[1], cur[2], math.huge)
  return { row = cur[1], col_index = col_index, chars = chars_into_cell(raw, cur[2], col_index) }
end

---@param bufnr integer
---@param snap { row: integer, col_index: integer, chars: integer }
function M.restore_cursor(bufnr, snap)
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= bufnr then return end
  local row = math.min(snap.row, api.nvim_buf_line_count(bufnr))
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  pcall(api.nvim_win_set_cursor, win, { row, col_in_cell(line, snap.col_index, snap.chars) })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Core apply: wrap one table in place.
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param bufnr integer
---@param parsed table
---@param opts table
---@internal
---Copy of `parsed` with its continuation rows merged back (`reflow`, and `auto`: it plans
---from the content's natural widths, wrapped ones would shrink again on every pass).
---@param parsed table
---@param opts table
---@return table
local function unwrapped(parsed, opts)
  if parsed.col_count < 2 then return parsed end
  return vim.tbl_extend(
    "force",
    parsed,
    { rows = table_wrap.unwrap_rows(parsed.rows, opts.join or " ", parsed.col_count) }
  )
end

---@internal
local function apply_wrap(bufnr, parsed, opts)
  local win = api.nvim_get_current_win()
  local ok_cur, cur = pcall(api.nvim_win_get_cursor, win)
  -- A hidden buffer (resize hook over every loaded buffer) is not under this cursor.
  if api.nvim_win_get_buf(win) ~= bufnr then ok_cur = false end
  local logical_row, col_index, cell_chars
  if ok_cur and cur[1] >= parsed.start_line and cur[1] <= parsed.end_line then
    logical_row = logical_row_at(parsed, cur[1])
    col_index = column_at(bufnr, cur[1], cur[2], parsed.col_count)
    local raw = api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], false)[1] or ""
    cell_chars = chars_into_cell(raw, cur[2], col_index)
  end

  local bounds = { start_line = parsed.start_line, end_line = parsed.end_line }
  table_wrap._fire("before_reflow", bounds, opts)

  local rendered, layout =
    table_wrap.render((opts.reflow or opts.auto) and unwrapped(parsed, opts) or parsed, opts)
  local current = api.nvim_buf_get_lines(bufnr, parsed.start_line - 1, parsed.end_line, false)
  local wrote = not vim.deep_equal(current, rendered)
  if wrote then
    api.nvim_buf_set_lines(bufnr, parsed.start_line - 1, parsed.end_line, false, rendered)
  end
  place_signs(bufnr, parsed.start_line, layout, opts)

  local new_bounds =
    { start_line = parsed.start_line, end_line = parsed.start_line - 1 + #rendered }
  table_wrap._fire("after_reflow", new_bounds, opts)

  -- Unchanged table: the cursor is where it was; leave it alone.
  if wrote and logical_row and cur then
    local pi, col = restore_position(rendered, layout, logical_row, col_index, cell_chars)
    if pi then pcall(api.nvim_win_set_cursor, win, { parsed.start_line - 1 + pi, col }) end
  end
end

---@internal
---@param bufnr integer
---@param parsed table
---@param opts table
local function apply_unwrap(bufnr, parsed, opts)
  local merged = table_wrap.unwrap_rows(parsed.rows, opts.join or " ", parsed.col_count)
  local merged_parsed =
    { rows = merged, col_count = parsed.col_count, separator_style = parsed.separator_style }
  -- No wrapping on the write-back: natural widths only.
  local flat_opts = vim.tbl_extend("force", opts, { auto = false, min = 1 })
  flat_opts.max, flat_opts.win_width = nil, nil
  -- A per-column `max` would wrap the merged cells again: keep align/min only.
  local flat_overrides = {}
  for _, ov in ipairs(opts.col_overrides or {}) do
    local copy = vim.deepcopy(ov)
    copy.max = nil
    flat_overrides[#flat_overrides + 1] = copy
  end
  flat_opts.col_overrides = flat_overrides
  local rendered = table_wrap.render(merged_parsed, flat_opts)
  api.nvim_buf_set_lines(bufnr, parsed.start_line - 1, parsed.end_line, false, rendered)
  clear_signs(bufnr, parsed.start_line, parsed.start_line + #rendered)
  return #parsed.rows - #merged
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public: cursor / buffer / range scopes
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param bufnr integer
---@return table[] tables
---@return string[] lines
local function all_tables(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table_fmt.parse_all_tables(lines), lines
end

---@internal
local function table_at_cursor(bufnr)
  local tables = all_tables(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  return table_fmt.find_table_at_cursor(tables, cursor[1])
end

---Wraps the table at the cursor, or every table in the buffer when the
---cursor isn't inside one.
---@param bufnr integer?
---@param overrides table?
---@return integer count
function M.wrap_at_cursor(bufnr, overrides)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if parsed then
    apply_wrap(bufnr, parsed, M.resolve_wrap_opts(bufnr, parsed.start_line, overrides))
    return 1
  end
  return M.wrap_range(bufnr, 1, math.huge, overrides)
end

---Wraps every table intersecting `[first_line, last_line]`. Processed
---bottom-to-top so earlier tables' line numbers stay valid as later ones grow.
---@param bufnr integer?
---@param first_line integer
---@param last_line integer
---@param overrides table?
---@return integer count
function M.wrap_range(bufnr, first_line, last_line, overrides)
  bufnr = bufnr or api.nvim_get_current_buf()
  local tables = all_tables(bufnr)
  local targets = {}
  for _, t in ipairs(tables) do
    if t.end_line >= first_line and t.start_line <= last_line then targets[#targets + 1] = t end
  end
  table.sort(targets, function(a, b) return a.start_line > b.start_line end)
  for _, t in ipairs(targets) do
    apply_wrap(bufnr, t, M.resolve_wrap_opts(bufnr, t.start_line, overrides))
  end
  return #targets
end

---Unwraps the table at the cursor (merges continuation rows back).
---@param bufnr integer?
---@return boolean ok
function M.unwrap_at_cursor(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then
    notify.warn("Cursor is not inside a table")
    return false
  end
  local opts = M.resolve_wrap_opts(bufnr, parsed.start_line)
  local removed = apply_unwrap(bufnr, parsed, opts)
  notify.info(
    removed > 0 and string.format("Unwrapped %d continuation row(s)", removed)
      or "Nothing to unwrap"
  )
  return true
end

---Unwraps every table intersecting `[first_line, last_line]`.
---@param bufnr integer
---@param first_line integer
---@param last_line integer
function M.unwrap_range(bufnr, first_line, last_line)
  local tables = all_tables(bufnr)
  local targets = {}
  for _, t in ipairs(tables) do
    if t.end_line >= first_line and t.start_line <= last_line then targets[#targets + 1] = t end
  end
  table.sort(targets, function(a, b) return a.start_line > b.start_line end)
  for _, t in ipairs(targets) do
    apply_unwrap(bufnr, t, M.resolve_wrap_opts(bufnr, t.start_line))
  end
end

---`:MDTableWrapVisual[!]` — wrap tables in `[first_line, last_line]`; bang
---unwraps first for a clean recompute.
---@param bufnr integer?
---@param first_line integer
---@param last_line integer
---@param force boolean?
function M.wrap_visual(bufnr, first_line, last_line, force)
  bufnr = bufnr or api.nvim_get_current_buf()
  if force then M.unwrap_range(bufnr, first_line, last_line) end
  local count = M.wrap_range(bufnr, first_line, last_line)
  notify.info(string.format("Wrapped %d table(s) in selection", count))
end

---`:MDTableWrapVisible[!]` — wrap tables intersecting the visible window range.
---@param bufnr integer?
---@param force boolean?
function M.wrap_visible(bufnr, force)
  bufnr = bufnr or api.nvim_get_current_buf()
  local first, last = vim.fn.line("w0"), vim.fn.line("w$")
  if force then M.unwrap_range(bufnr, first, last) end
  local count = M.wrap_range(bufnr, first, last)
  notify.info(string.format("Wrapped %d table(s) in visible range", count))
end

---`:MDTableReflowHeader` — reformats only the header + separator; body rows
---(and any of their existing continuation rows) are left untouched.
---@param bufnr integer?
function M.reflow_header(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then
    notify.warn("Cursor is not inside a table")
    return
  end
  local opts = M.resolve_wrap_opts(bufnr, parsed.start_line)
  local colplan = table_wrap.plan(parsed, opts)

  -- One physical header line (a wrapped header above the separator is not GFM);
  -- the plan already floors every column at its header's width.
  local out = {}
  local cells = {}
  for ci = 1, parsed.col_count do
    cells[ci] = parsed.rows[1][ci] or ""
  end
  out[1] = table_fmt.format_row(cells, colplan.widths, opts.header_align or "left", {})
  out[#out + 1] =
    table_fmt.gen_separator(colplan.widths, opts.separator_style or parsed.separator_style)

  api.nvim_buf_set_lines(bufnr, parsed.start_line - 1, parsed.start_line + 1, false, out)
  notify.info("Reflowed header")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Debug plan view
-- ─────────────────────────────────────────────────────────────────────────────

---`:MDTableDebug` — prints the resolved column-width plan for the table at cursor.
---@param bufnr integer?
function M.debug_at_cursor(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then
    notify.warn("Cursor is not inside a table")
    return
  end
  local opts = M.resolve_wrap_opts(bufnr, parsed.start_line)
  local colplan = table_wrap.plan(parsed, opts)
  notify.info(table.concat(table_wrap.format_debug(colplan), "\n"))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lint / fix
-- ─────────────────────────────────────────────────────────────────────────────

---`:MDTableLint` — flags unequal cell counts, missing separators, empty
---header cells via `vim.diagnostic` (namespace `markdown_table`).
---@param bufnr integer?
---@return integer count
function M.lint(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local _, lines = all_tables(bufnr)
  local issues = table_wrap.find_issues(lines)
  local diagnostics = {}
  for _, iss in ipairs(issues) do
    diagnostics[#diagnostics + 1] = {
      lnum = iss.line - 1,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = iss.message,
      source = "markdown_table",
    }
  end
  vim.diagnostic.set(LINT_NS, bufnr, diagnostics)
  if #diagnostics == 0 then
    notify.info("No table issues found")
  else
    notify.warn(string.format("%d table issue(s) found", #diagnostics))
  end
  return #diagnostics
end

---`:MDTableFixMissingSeparator` — inserts a separator line after every table
---block missing one.
---@param bufnr integer?
---@return integer fixed
function M.fix_missing_separators(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local _, lines = all_tables(bufnr)
  local fixed_lines, count = table_wrap.fix_missing_separators(lines)
  if count > 0 then api.nvim_buf_set_lines(bufnr, 0, -1, false, fixed_lines) end
  notify.info(string.format("Fixed %d missing separator(s)", count))
  return count
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CSV roundtrip
-- ─────────────────────────────────────────────────────────────────────────────

---`:MDTableToCSV [path]` — table at cursor -> CSV file, or `+` register.
---@param bufnr integer?
---@param path string?
---@return boolean ok
function M.to_csv(bufnr, path)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then
    notify.warn("Cursor is not inside a table")
    return false
  end
  local csv_lines = table_wrap.to_csv(parsed.rows)
  if path and path ~= "" then
    -- expand_path, not vim.fn.expand (SEC-34): `path` is a user-typed
    -- command argument, not a Vim cmdline special.
    local expanded = expand_path(path)
    local fh, err = io.open(expanded, "w")
    if not fh then
      notify.error(string.format("Cannot write %q: %s", expanded, tostring(err)))
      return false
    end
    fh:write(table.concat(csv_lines, "\n") .. "\n")
    fh:close()
    notify.info("Wrote CSV to " .. expanded)
  else
    -- `clipboard.copy`, not a bare `pcall(vim.fn.setreg, ...)`: that pcall
    -- only proves the call didn't raise, and setreg("+", ...) never raises
    -- for lack of a clipboard provider either -- it just silently does
    -- nothing. clipboard.copy verifies the register actually holds what
    -- was written (or falls back to an external tool) before reporting
    -- success.
    if clipboard.copy(table.concat(csv_lines, "\n")) then
      notify.info("Copied CSV to the clipboard (+ register)")
    else
      notify.error("Failed to copy CSV to the clipboard")
    end
  end
  return true
end

---`:MDTableFromCSV [path]` — CSV file (or `+` register) -> GFM table, inserted
---below the cursor.
---@param bufnr integer?
---@param path string?
---@return boolean ok
function M.from_csv(bufnr, path)
  bufnr = bufnr or api.nvim_get_current_buf()
  local csv_lines
  if path and path ~= "" then
    -- expand_path, not vim.fn.expand (SEC-34): `path` is a user-typed
    -- command argument, not a Vim cmdline special.
    local expanded = expand_path(path)
    local fh, err = io.open(expanded, "r")
    if not fh then
      notify.error(string.format("Cannot read %q: %s", expanded, tostring(err)))
      return false
    end
    csv_lines = {}
    for line in fh:lines() do
      csv_lines[#csv_lines + 1] = line
    end
    fh:close()
  else
    local ok, reg = pcall(vim.fn.getreg, "+")
    if not ok or not reg or reg == "" then
      notify.warn("Clipboard is empty; pass a PATH or copy CSV first")
      return false
    end
    -- One-argument `getreg` answers with the string form; the `string[]` half
    -- of its type needs the third argument, which this call does not pass.
    ---@cast reg string
    csv_lines = vim.split(reg, "\n", { trimempty = true })
  end

  local rows = table_wrap.from_csv(csv_lines)
  if #rows == 0 then
    notify.warn("No rows parsed from CSV")
    return false
  end
  local gfm = table_fmt.rows_to_gfm(rows, {})
  local cursor = api.nvim_win_get_cursor(0)
  api.nvim_buf_set_lines(bufnr, cursor[1], cursor[1], false, gfm)
  notify.info(string.format("Inserted %d-row table from CSV", #rows))
  return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Column nudge / alignment cycle / profile / flavor
-- ─────────────────────────────────────────────────────────────────────────────

---`:MDTableCol+ [n]` / `:MDTableCol-` — widen/narrow the column under the
---cursor by `n` (default 1), taking it from (or giving it to) the
---neighboring column so the row's total width is preserved.
---@param bufnr integer?
---@param delta integer
function M.col_nudge(bufnr, delta)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then
    notify.warn("Cursor is not inside a table")
    return
  end
  local cursor = api.nvim_win_get_cursor(0)
  local col_index = column_at(bufnr, cursor[1], cursor[2], parsed.col_count)
  local neighbor = (col_index < parsed.col_count) and (col_index + 1) or (col_index - 1)
  if neighbor < 1 then
    notify.warn("Only one column; nothing to nudge against")
    return
  end

  local opts = M.resolve_wrap_opts(bufnr, parsed.start_line)
  local colplan = table_wrap.plan(parsed, opts)
  local widths = vim.deepcopy(colplan.widths)

  local wanted = math.max(1, widths[col_index] + delta)
  local applied = wanted - widths[col_index]
  local new_neighbor = math.max(1, widths[neighbor] - applied)
  applied = widths[neighbor] - new_neighbor
  widths[col_index] = widths[col_index] + applied
  widths[neighbor] = widths[neighbor] - applied

  local pinned = {}
  for i, w in ipairs(widths) do
    pinned[#pinned + 1] = { col = i, max = w, min = w }
  end
  local pin_opts =
    vim.tbl_extend("force", opts, { col_overrides = pinned, auto = false, win_width = nil })
  local rendered = table_wrap.render(parsed, pin_opts)
  api.nvim_buf_set_lines(bufnr, parsed.start_line - 1, parsed.end_line, false, rendered)
  notify.info(
    string.format(
      "Column %d: %d (neighbor %d: %d)",
      col_index,
      widths[col_index],
      neighbor,
      widths[neighbor]
    )
  )
end

local ALIGN_CYCLE = { left = "center", center = "right", right = "left" }

---`:MDTableAlign cycle|left|center|right` for the column under the cursor.
---@param bufnr integer?
---@param mode "cycle"|"left"|"center"|"right"
function M.align_cycle(bufnr, mode)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then
    notify.warn("Cursor is not inside a table")
    return
  end
  local cursor = api.nvim_win_get_cursor(0)
  local col_index = column_at(bufnr, cursor[1], cursor[2], parsed.col_count)

  local key = "mdtable_align_" .. col_index
  local configured = (require("markdown.config").get().table or {}).entry_align
  local current = (vim.b[bufnr] and vim.b[bufnr][key]) or configured or "left"
  local next_align = (mode == "left" or mode == "center" or mode == "right") and mode
    or (ALIGN_CYCLE[current] or "left")
  vim.b[bufnr][key] = next_align

  local ok, err = table_fmt.format_table_at_cursor(
    bufnr,
    { col_overrides = { { col = col_index, align = next_align } } }
  )
  if ok then
    notify.info(string.format("Column %d alignment: %s", col_index, next_align))
  else
    notify.error(err or "format failed")
  end
end

---`:MDTableProfile compact|docs|wide` — loads a named preset from
---`config.table.wrap_profiles` as this buffer's wrap opts, then re-wraps the
---table at the cursor.
---@param bufnr integer?
---@param name string
function M.set_profile(bufnr, name)
  bufnr = bufnr or api.nvim_get_current_buf()
  local profiles = table_cfg().wrap_profiles or {}
  if not profiles[name] then
    notify.error(
      string.format(
        "Unknown profile %q (known: %s)",
        name,
        table.concat(vim.tbl_keys(profiles), ", ")
      )
    )
    return
  end
  vim.b[bufnr].mdtable_profile = name
  M.wrap_at_cursor(bufnr)
  notify.info("Profile: " .. name)
end

---`:MDTableFlavor github|loose` — strict GFM (min 3-dash separator, spaced
---style) vs. loose (compact allowed, no forced minimum). Re-wraps the table
---at the cursor.
---@param bufnr integer?
---@param flavor "github"|"loose"
function M.set_flavor(bufnr, flavor)
  bufnr = bufnr or api.nvim_get_current_buf()
  if flavor ~= "github" and flavor ~= "loose" then
    notify.error("flavor must be 'github' or 'loose'")
    return
  end
  M.wrap_at_cursor(bufnr, { flavor = flavor })
  notify.info("Flavor: " .. flavor)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Resize hook / selective on-save reflow
-- ─────────────────────────────────────────────────────────────────────────────

---Re-wraps every table in `bufnr` that resolves to `auto = true`. Used by the
---debounced `VimResized`/`WinResized` hook (`config.table.wrap.auto_resize`).
---@param bufnr integer
---@return integer count
function M.reflow_auto_tables(bufnr)
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)) then return 0 end
  local tables = all_tables(bufnr)
  table.sort(tables, function(a, b) return a.start_line > b.start_line end)
  local count = 0
  for _, t in ipairs(tables) do
    local opts = M.resolve_wrap_opts(bufnr, t.start_line)
    if opts.auto then
      apply_wrap(bufnr, t, opts)
      count = count + 1
    end
  end
  return count
end

---BufWritePre hook (`config.table.wrap.selective_reflow`): only re-wraps
---tables whose raw text actually changed since the last snapshot, keyed by
---header text (survives small line-number shifts elsewhere in the buffer).
---@param bufnr integer
---@return integer count
function M.selective_reflow_on_save(bufnr)
  local cfgw = table_cfg().wrap or {}
  if not cfgw.selective_reflow then return 0 end

  local tables, lines = all_tables(bufnr)
  local last = vim.b[bufnr].mdtable_last_snapshot or {}
  local next_snapshot, to_process = {}, {}

  for _, t in ipairs(tables) do
    local sig = table.concat(t.rows[1] or {}, "|")
    local raw = table.concat(lines, "\n", t.start_line, t.end_line)
    next_snapshot[sig] = raw
    if last[sig] ~= raw then to_process[#to_process + 1] = t end
  end
  vim.b[bufnr].mdtable_last_snapshot = next_snapshot

  if #to_process == 0 then return 0 end
  table.sort(to_process, function(a, b) return a.start_line > b.start_line end)

  local count = 0
  for _, t in ipairs(to_process) do
    local opts = M.resolve_wrap_opts(bufnr, t.start_line)
    if opts.enabled then
      apply_wrap(bufnr, t, opts)
      count = count + 1
    end
  end
  return count
end

---Formats the table at the cursor like `:Markdown table format`, but capped at a
---maximum column width (cells wrap onto shared continuation rows). Already
---wrapped tables are not unwrapped first -- the continuation heuristic would
---merge genuine sparse rows -- run `:MDTableUnwrap` before changing `max`.
---@param bufnr integer?
---@param overrides table?  # { max?, auto?, min?, pad?, header_align?, entry_align?, col_overrides? }
---@return boolean ok
---@return string? err
function M.format_at_cursor(bufnr, overrides)
  bufnr = bufnr or api.nvim_get_current_buf()
  local parsed = table_at_cursor(bufnr)
  if not parsed then return false, "No table at cursor" end
  local opts = M.resolve_wrap_opts(bufnr, parsed.start_line, overrides)
  if not opts.max and not opts.auto then opts.max = M.DEFAULT_FORMAT_MAX end
  apply_wrap(bufnr, parsed, opts)
  return true, nil
end

---Same as `format_at_cursor` for every table in the buffer.
---@param bufnr integer?
---@param overrides table?
---@return boolean ok
---@return string? err
---@return integer count
function M.format_buffer(bufnr, overrides)
  bufnr = bufnr or api.nvim_get_current_buf()
  local tables = all_tables(bufnr)
  table.sort(tables, function(a, b) return a.start_line > b.start_line end)
  for _, t in ipairs(tables) do
    local opts = M.resolve_wrap_opts(bufnr, t.start_line, overrides)
    if not opts.max and not opts.auto then opts.max = M.DEFAULT_FORMAT_MAX end
    apply_wrap(bufnr, t, opts)
  end
  return true, nil, #tables
end

---Same as `format_buffer` on plain lines (no buffer, no window): used by the file
---scopes. Returns the new lines and the number of tables rendered.
---@param lines string[]
---@param overrides table?
---@return string[] out
---@return integer count
function M.format_lines(lines, overrides)
  local tables = table_fmt.parse_all_tables(lines)
  local out, from = {}, 1
  for _, t in ipairs(tables) do
    for ln = from, t.start_line - 1 do
      out[#out + 1] = lines[ln]
    end
    local opts = M.resolve_wrap_opts(nil, t.start_line, overrides, lines)
    if not opts.max and not opts.auto then opts.max = M.DEFAULT_FORMAT_MAX end
    local rendered = table_wrap.render((opts.reflow or opts.auto) and unwrapped(t, opts) or t, opts)
    -- A block whose every line ends in a CR (CRLF block of a mixed-ending file)
    -- keeps it: the parser trims the CR, the renderer never writes it.
    local cr = true
    for ln = t.start_line, t.end_line do
      if lines[ln]:sub(-1) ~= "\r" then
        cr = false
        break
      end
    end
    for _, l in ipairs(rendered) do
      out[#out + 1] = cr and (l .. "\r") or l
    end
    from = t.end_line + 1
  end
  for ln = from, #lines do
    out[#out + 1] = lines[ln]
  end
  return out, #tables
end

---Width-capped format of the tables in the file at `path`, in place. Keeps the BOM,
---the CRLF endings and a missing final newline, and writes only when something changed.
---@param path string
---@param overrides table?
---@return boolean ok
---@return string? err
---@return integer count
function M.format_file(path, overrides)
  local disk = require("markdown.util.disk_lines")
  local read_ok, lines, meta = pcall(disk.read, path)
  if not read_ok then return false, string.format("Cannot read %q", path), 0 end
  local out, count = M.format_lines(lines, overrides)
  if count == 0 or table.concat(out, "\n") == table.concat(lines, "\n") then
    return true, nil, count
  end
  if not disk.write(path, out, meta) then
    return false, string.format("Cannot write %q", path), 0
  end
  return true, nil, count
end

---`scope=cwd` or a file path for the width-capped format.
---@param scope string
---@param overrides table?
---@return boolean ok
---@return string? err
function M.format_scope(scope, overrides)
  local files
  if scope == "cwd" then
    files = require("markdown.util.md_files").collect(vim.fn.getcwd())
  else
    local path = expand_path(scope)
    if vim.fn.filereadable(path) == 0 then
      return false, string.format("File not readable: %q", path)
    end
    files = { path }
  end
  local errors, done = {}, 0
  for _, path in ipairs(files) do
    local ok, err = M.format_file(path, overrides)
    if ok then
      done = done + 1
    else
      errors[#errors + 1] = err
    end
  end
  notify.info(string.format("Formatted tables in %d file(s) (wrapped)", done))
  if #errors > 0 then return false, table.concat(errors, "; ") end
  return true, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Fold continuation blocks (delegates fold-level logic to `core.fold`)
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param bufnr integer
local function refresh_folds(bufnr)
  api.nvim_buf_call(bufnr, function()
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.cmd("normal! zx")
  end)
end

---`:MDTableFoldRow` — folds the continuation block under the cursor.
---@param bufnr integer?
function M.fold_row_at_cursor(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  vim.b[bufnr].mdtable_fold_continuations = true
  refresh_folds(bufnr)
  -- `vim.cmd` is a callable table, not a function, so it does not satisfy
  -- `pcall`'s first parameter -- the closure form does.
  api.nvim_buf_call(bufnr, function()
    pcall(function() vim.cmd("silent! normal! zc") end)
  end)
end

---`:MDTableFoldAll` — folds every continuation block in the buffer.
---@param bufnr integer?
function M.fold_all(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  vim.b[bufnr].mdtable_fold_continuations = true
  refresh_folds(bufnr)
  api.nvim_buf_call(bufnr, function()
    local n = api.nvim_buf_line_count(bufnr)
    for l = 1, n do
      if vim.fn.foldlevel(l) > 0 and vim.fn.foldclosed(l) == -1 then
        pcall(function() vim.cmd(l .. "foldclose") end)
      end
    end
  end)
end

return M
