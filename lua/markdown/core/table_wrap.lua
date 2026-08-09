---@module 'markdown.core.table_wrap'
--- Width-limited table wrapping: per-column max/min/auto/pad column plans,
--- wrapping over-wide cell content onto GFM-valid continuation rows of the
--- same logical table row, and the reverse (unwrap). Builds on
--- `markdown.core.table_fmt`'s parse/format primitives rather than
--- duplicating them.
local table_fmt = require("markdown.core.table_fmt")

local M = {}

M.DEFAULT_SOFT_BREAK_CHARS = "/._-?,&=#@:"

-- ─────────────────────────────────────────────────────────────────────────────
-- API hooks: before_reflow(bounds, plan) / after_reflow(bounds, plan)
-- ─────────────────────────────────────────────────────────────────────────────

M._hooks = { before_reflow = {}, after_reflow = {} }

---Registers a callback for `event` ("before_reflow" | "after_reflow").
---@param event "before_reflow"|"after_reflow"
---@param fn function
function M.on(event, fn)
  M._hooks[event] = M._hooks[event] or {}
  table.insert(M._hooks[event], fn)
end

---@internal
---@param event string
local function fire(event, ...)
  for _, fn in ipairs(M._hooks[event] or {}) do
    pcall(fn, ...)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Column-plan resolution (max/min/align per column, by index or header name)
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param overrides table[]|nil  # { col, max?, min?, align? }[]
---@param header_cells string[]
---@param col_count integer
---@return table<integer, table>
local function resolve_col_overrides(overrides, header_cells, col_count)
  local by_idx = {}
  if not overrides then return by_idx end
  local name_to_idx = {}
  for i = 1, col_count do
    local key = table_fmt.trim(header_cells[i] or ""):lower()
    if key ~= "" then name_to_idx[key] = i end
  end
  for _, ov in ipairs(overrides) do
    local idx
    if type(ov.col) == "number" then
      idx = ov.col
    elseif type(ov.col) == "string" then
      idx = name_to_idx[ov.col:lower()]
    end
    if idx and idx >= 1 and idx <= col_count then
      by_idx[idx] = by_idx[idx] or {}
      if ov.max ~= nil then by_idx[idx].max = ov.max end
      if ov.min ~= nil then by_idx[idx].min = ov.min end
      if ov.align ~= nil then by_idx[idx].align = ov.align end
    end
  end
  return by_idx
end
M.resolve_col_overrides = resolve_col_overrides

-- ─────────────────────────────────────────────────────────────────────────────
-- Width plan: natural width, then clamp to min/max, then (if auto) shrink
-- proportionally to fit `win_width`.
-- ─────────────────────────────────────────────────────────────────────────────

---@class Mkdn.TableWrapPlan
---@field col_count integer
---@field widths integer[]  # final, post-clamp/shrink width per column
---@field natural integer[]
---@field mins integer[]
---@field maxs (integer|nil)[]
---@field modes ("max"|"auto"|"natural")[]
---@field pipes integer
---@field pad integer
---@field sum integer  # total physical line width (pipes + padding + content)
---@field avail integer|nil

---Computes the per-column width plan for `parsed` (a `table_fmt.parse_all_tables`
---entry) given wrap opts.
---@param parsed table
---@param opts table  # { min?, max?, auto?, pad?, win_width?, col_overrides? }
---@return Mkdn.TableWrapPlan
function M.plan(parsed, opts)
  opts = opts or {}
  local col_count = parsed.col_count
  local natural = table_fmt.calc_widths(parsed.rows, col_count)
  local by_idx = resolve_col_overrides(opts.col_overrides, parsed.rows[1], col_count)

  local mins, maxs, modes, widths = {}, {}, {}, {}
  for i = 1, col_count do
    local ov = by_idx[i] or {}
    mins[i] = ov.min or opts.min or 1
    maxs[i] = ov.max or opts.max
    modes[i] = maxs[i] and "max" or (opts.auto and "auto" or "natural")

    local w = natural[i]
    if w < mins[i] then w = mins[i] end
    if maxs[i] and w > maxs[i] then w = maxs[i] end
    widths[i] = w
  end

  if opts.auto and opts.win_width then
    local pad = opts.pad or 1
    local overhead = (col_count + 1) + col_count * pad * 2
    local avail = math.max(opts.win_width - overhead, col_count)
    local sum = 0
    for i = 1, col_count do
      sum = sum + widths[i]
    end
    if sum > avail then
      local shrinkable = 0
      for i = 1, col_count do
        shrinkable = shrinkable + math.max(widths[i] - mins[i], 0)
      end
      local over = sum - avail
      if shrinkable > 0 then
        for i = 1, col_count do
          local room = widths[i] - mins[i]
          if room > 0 then
            local cut = math.floor(over * (room / shrinkable) + 0.5)
            widths[i] = math.max(mins[i], widths[i] - cut)
          end
        end
      end
    end
  end

  local pad = opts.pad or 1
  local pipes = col_count + 1
  local sum = pipes
  for i = 1, col_count do
    sum = sum + widths[i] + pad * 2
  end

  return {
    col_count = col_count,
    widths = widths,
    natural = natural,
    mins = mins,
    maxs = maxs,
    modes = modes,
    pipes = pipes,
    pad = pad,
    sum = sum,
    avail = opts.win_width,
  }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cell wrapping: never split inside `[text](url)` or `` `code` ``; otherwise
-- break at whitespace or `soft_break_chars`.
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param text string
---@return { text: string, atomic: boolean }[]
local function tokenize_atomic(text)
  local tokens = {}
  local i, n = 1, #text
  while i <= n do
    local rest = text:sub(i)
    local link = rest:match("^%[[^%]]*%]%([^%)]*%)")
    local code = rest:match("^`[^`]*`")
    if link then
      tokens[#tokens + 1] = { text = link, atomic = true }
      i = i + #link
    elseif code then
      tokens[#tokens + 1] = { text = code, atomic = true }
      i = i + #code
    else
      local link_start = rest:find("%[[^%]]*%]%(")
      local code_start = rest:find("`")
      local stop = n - i + 2
      if link_start then stop = math.min(stop, link_start) end
      if code_start then stop = math.min(stop, code_start) end
      local chunk = rest:sub(1, math.max(stop - 1, 1))
      tokens[#tokens + 1] = { text = chunk, atomic = false }
      i = i + #chunk
    end
  end
  return tokens
end

---@internal
---@param text string
---@param soft_chars string
---@return string[]
local function split_units(text, soft_chars)
  local escaped = soft_chars:gsub("(%W)", "%%%1")
  local class = "[" .. escaped .. "]"
  local units, cur = {}, ""
  for i = 1, #text do
    local ch = text:sub(i, i)
    cur = cur .. ch
    if ch == " " or ch:match(class) then
      units[#units + 1] = cur
      cur = ""
    end
  end
  if cur ~= "" then units[#units + 1] = cur end
  return units
end

---Wraps `text` into lines of at most `width` display columns, without ever
---splitting a `[text](url)` link or `` `code` `` span, and preferring to
---break at whitespace / `soft_break_chars`. A single unbreakable unit wider
---than `width` is placed alone on its own (overflowing) line.
---@param text string
---@param width integer
---@param opts? { soft_break_chars?: string }
---@return string[] lines
function M.wrap_cell(text, width, opts)
  opts = opts or {}
  text = text or ""
  if width <= 0 then width = 1 end
  if table_fmt.display_width(text) <= width then return { text } end

  local soft = opts.soft_break_chars or M.DEFAULT_SOFT_BREAK_CHARS
  local units = {}
  for _, tok in ipairs(tokenize_atomic(text)) do
    if tok.atomic then
      units[#units + 1] = tok.text
    else
      for _, u in ipairs(split_units(tok.text, soft)) do
        units[#units + 1] = u
      end
    end
  end

  local lines, cur = {}, ""
  for _, u in ipairs(units) do
    local candidate = cur .. u
    if cur == "" or table_fmt.display_width(candidate) <= width then
      cur = candidate
    else
      lines[#lines + 1] = table_fmt.trim(cur)
      cur = u
    end
  end
  if cur ~= "" then lines[#lines + 1] = table_fmt.trim(cur) end
  if #lines == 0 then lines = { "" } end
  return lines
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Render: wraps every cell to the plan's widths, emits physical GFM rows +
-- a layout describing which physical row belongs to which logical row.
-- ─────────────────────────────────────────────────────────────────────────────

---@class Mkdn.TableWrapLayoutEntry
---@field logical_index integer  # 1 = header, 2.. = body rows; 0 = separator
---@field is_continuation boolean
---@field cont_index integer
---@field separator? boolean

---Renders `parsed` with width-limited wrapping. Returns GFM lines plus a
---layout array (one entry per output line) and the resolved plan.
---@param parsed table
---@param opts table  # same as `M.plan`, plus header_align/entry_align
---@return string[] lines
---@return Mkdn.TableWrapLayoutEntry[] layout
---@return Mkdn.TableWrapPlan colplan
function M.render(parsed, opts)
  opts = opts or {}
  local colplan = M.plan(parsed, opts)
  local by_idx = resolve_col_overrides(opts.col_overrides, parsed.rows[1], parsed.col_count)
  local align_map = {}
  for i, ov in pairs(by_idx) do
    if ov.align then align_map[i] = ov.align end
  end

  -- Pass 1: wrap every row at the planned widths, but track the actual
  -- (possibly overflowing) max width per column -- a single unbreakable
  -- token wider than the plan can't be split, so it overflows on its own
  -- line. Padding/separator must use that real width, or the column
  -- misaligns against every other row.
  local effective = {}
  for i = 1, parsed.col_count do
    effective[i] = colplan.widths[i]
  end

  local wrapped_rows = {}

  ---@param row_cells string[]
  ---@param logical_index integer
  local function wrap_row(row_cells, logical_index)
    local wrapped, max_lines = {}, 1
    for ci = 1, parsed.col_count do
      local lines = M.wrap_cell(row_cells[ci] or "", colplan.widths[ci], opts)
      wrapped[ci] = lines
      if #lines > max_lines then max_lines = #lines end
      for _, l in ipairs(lines) do
        local w = table_fmt.display_width(l)
        if w > effective[ci] then effective[ci] = w end
      end
    end
    wrapped_rows[logical_index] = { cells = wrapped, max_lines = max_lines }
  end

  wrap_row(parsed.rows[1], 1)
  for ri = 2, #parsed.rows do
    wrap_row(parsed.rows[ri], ri)
  end

  -- Pass 2: emit using the effective (overflow-safe) widths throughout.
  local out, layout = {}, {}

  ---@param logical_index integer
  ---@param default_align string
  local function emit(logical_index, default_align)
    local entry = wrapped_rows[logical_index]
    for li = 1, entry.max_lines do
      local cells = {}
      for ci = 1, parsed.col_count do
        cells[ci] = entry.cells[ci][li] or ""
      end
      out[#out + 1] = table_fmt.format_row(cells, effective, default_align, align_map)
      layout[#layout + 1] =
        { logical_index = logical_index, is_continuation = li > 1, cont_index = li - 1 }
    end
  end

  emit(1, opts.header_align or "center")
  out[#out + 1] = table_fmt.gen_separator(effective, opts.separator_style or parsed.separator_style)
  layout[#layout + 1] =
    { logical_index = 0, is_continuation = false, cont_index = 0, separator = true }
  for ri = 2, #parsed.rows do
    emit(ri, opts.entry_align or "center")
  end

  colplan.widths = effective
  return out, layout, colplan
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Unwrap: merge continuation rows back into one physical row per logical row.
--
-- Continuation rows carry no in-buffer marker (the `↳` hint is virtual text
-- only, so the GFM source stays clean) -- detected structurally instead: a
-- non-separator row with at most one non-empty cell, following another row
-- of the same table, is treated as a continuation of the nearest preceding
-- row with more than one non-empty cell. This is a heuristic, documented
-- caveat: a genuine data row that happens to have only one non-empty cell
-- right after another row is indistinguishable from a continuation.
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param row string[]
---@return integer
local function nonempty_count(row)
  local n = 0
  for _, c in ipairs(row) do
    if table_fmt.trim(c) ~= "" then n = n + 1 end
  end
  return n
end

---Merges continuation rows in `rows` (a `parsed.rows`-shaped table, header
---included) back into their logical row.
---@param rows string[][]
---@param join string  # separator used to join continuation text, e.g. " " or "<br>"
---@return string[][] merged
function M.unwrap_rows(rows, join)
  join = join or " "
  local merged = {}
  for _, row in ipairs(rows) do
    local is_continuation = #merged > 0 and nonempty_count(row) <= 1
    if is_continuation then
      local prev = merged[#merged]
      for ci, c in ipairs(row) do
        local t = table_fmt.trim(c)
        if t ~= "" then
          local existing = table_fmt.trim(prev[ci] or "")
          prev[ci] = (existing ~= "" and (existing .. join .. t)) or t
        end
      end
    else
      local copy = {}
      for ci, c in ipairs(row) do
        copy[ci] = c
      end
      merged[#merged + 1] = copy
    end
  end
  return merged
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lint: unequal cell counts, missing separator, empty header cells.
-- ─────────────────────────────────────────────────────────────────────────────

---@class Mkdn.TableLintIssue
---@field line integer  # 1-indexed buffer line
---@field message string

---Finds structural issues in every table block found in `lines`.
---@param lines string[]
---@return Mkdn.TableLintIssue[]
function M.find_issues(lines)
  local issues = {}
  local i, n = 1, #lines
  while i <= n do
    if not table_fmt.is_table_line(lines[i]) then
      i = i + 1
    else
      local start = i
      while i <= n and table_fmt.is_table_line(lines[i]) do
        i = i + 1
      end
      local stop = i - 1
      if stop - start >= 1 then
        local sep_ok = false
        if stop >= start + 1 then
          local is_sep = table_fmt.is_separator_line(lines[start + 1])
          sep_ok = is_sep
        end
        if not sep_ok then
          issues[#issues + 1] = {
            line = start,
            message = string.format("Missing separator line (expected on line %d)", start + 1),
          }
        end

        local header = table_fmt.parse_row(lines[start])
        local col_count = #header
        for ci, cell in ipairs(header) do
          if table_fmt.trim(cell) == "" then
            issues[#issues + 1] =
              { line = start, message = string.format("Empty header cell (column %d)", ci) }
          end
        end

        for ln = start + 1, stop do
          if not table_fmt.is_separator_line(lines[ln]) then
            local cells = table_fmt.parse_row(lines[ln])
            if #cells ~= col_count then
              issues[#issues + 1] = {
                line = ln,
                message = string.format("Row has %d cell(s), header has %d", #cells, col_count),
              }
            end
          end
        end
      end
    end
  end
  return issues
end

---Inserts a separator line after every table block missing one, built from
---the header row's natural widths.
---@param lines string[]
---@return string[] out
---@return integer fixed
function M.fix_missing_separators(lines)
  local out, fixed = {}, 0
  local i, n = 1, #lines
  while i <= n do
    if not table_fmt.is_table_line(lines[i]) then
      out[#out + 1] = lines[i]
      i = i + 1
    else
      local start = i
      out[#out + 1] = lines[i]
      i = i + 1
      local has_sep = i <= n and table_fmt.is_separator_line(lines[i])
      if not has_sep then
        local header = table_fmt.parse_row(lines[start])
        local widths = table_fmt.calc_widths({ header }, #header)
        out[#out + 1] = table_fmt.gen_separator(widths, "compact")
        fixed = fixed + 1
      end
      while i <= n and table_fmt.is_table_line(lines[i]) do
        out[#out + 1] = lines[i]
        i = i + 1
      end
    end
  end
  return out, fixed
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CSV roundtrip
-- ─────────────────────────────────────────────────────────────────────────────

---Renders parsed rows as RFC-4180 CSV lines.
---@param rows string[][]
---@return string[]
function M.to_csv(rows)
  local out = {}
  for _, row in ipairs(rows) do
    local parts = {}
    for _, c in ipairs(row) do
      local v = table_fmt.trim(c)
      if v:find('[",\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
      parts[#parts + 1] = v
    end
    out[#out + 1] = table.concat(parts, ",")
  end
  return out
end

---Parses RFC-4180 CSV `lines` into rows of plain-text cells.
---@param lines string[]
---@return string[][]
function M.from_csv(lines)
  local rows = {}
  for _, line in ipairs(lines) do
    if line ~= "" then
      local cells, cur, in_quotes = {}, "", false
      local i, n = 1, #line
      while i <= n do
        local ch = line:sub(i, i)
        if in_quotes then
          if ch == '"' then
            if line:sub(i + 1, i + 1) == '"' then
              cur = cur .. '"'
              i = i + 1
            else
              in_quotes = false
            end
          else
            cur = cur .. ch
          end
        else
          if ch == '"' then
            in_quotes = true
          elseif ch == "," then
            cells[#cells + 1] = cur
            cur = ""
          else
            cur = cur .. ch
          end
        end
        i = i + 1
      end
      cells[#cells + 1] = cur
      rows[#rows + 1] = cells
    end
  end
  return rows
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Debug plan view
-- ─────────────────────────────────────────────────────────────────────────────

---Renders a compact human-readable plan view for `:MDTableDebug`.
---@param colplan Mkdn.TableWrapPlan
---@return string[]
function M.format_debug(colplan)
  local lines = {}
  lines[#lines + 1] = string.format(
    "cols=%d  pipes=%d  pad=%d  sum=%d  avail=%s",
    colplan.col_count,
    colplan.pipes,
    colplan.pad,
    colplan.sum,
    tostring(colplan.avail)
  )
  for i = 1, colplan.col_count do
    lines[#lines + 1] = string.format(
      "  col %d: width=%d natural=%d min=%d max=%s mode=%s",
      i,
      colplan.widths[i],
      colplan.natural[i],
      colplan.mins[i],
      tostring(colplan.maxs[i]),
      colplan.modes[i]
    )
  end
  return lines
end

M._fire = fire

return M
