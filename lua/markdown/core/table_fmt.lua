---@module 'markdown.core.table_fmt'
---@brief Markdown table formatter with per-role and per-column alignment control.
---@description
--- Adapted from buffer-ctx's format.table_fmt so markdown.nvim is self-contained
--- (no buffer-ctx dependency). Public API:
---   M.format_table_at_cursor(bufnr, opts)   – format the table under the cursor
---   M.format_tables_in_buffer(bufnr, opts)  – format every table in a buffer
---   M.format_tables_in_scope(opts)          – scope: "cursor"|"buffer"|"cwd"|<path>
---   M.parse_args(args)                      – parse :Markdown table format ARGS
---   M.complete(arg_lead)                    – completion for the format args
---   M.parse_html_table(html)                – parse an HTML <table> into rows of plain-text cells
---   M.rows_to_gfm(rows, opts)               – render parsed rows as GFM table lines (:Markdown table import)

local notify = require("markdown.util.notify").create("[markdown.core.table_fmt]")

local M = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Module-level defaults
-- ─────────────────────────────────────────────────────────────────────────────

--- `config.table` (header_align/entry_align/col_overrides), read lazily so a
--- call before `markdown.config` is set up still gets sane hard-coded defaults.
---@return { header_align: string, entry_align: string, col_overrides: table[]|nil }
---@internal
local function get_cfg()
  local ok, config = pcall(require, "markdown.config")
  local t = (ok and config.get().table) or {}
  return {
    header_align = t.header_align or "center",
    entry_align = t.entry_align or "center",
    col_overrides = t.col_overrides,
  }
end

local VALID_ALIGN = { left = true, center = true, right = true }

-- ─────────────────────────────────────────────────────────────────────────────
-- Utilities
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param fn function
---@return boolean ok
---@return any ...
local function safe_call(fn, ...) return pcall(fn, ...) end

---@internal
---@param str string
---@return integer
local function display_width(str)
  if type(str) ~= "string" then return 0 end
  local ok, w = safe_call(vim.fn.strdisplaywidth, str)
  return ok and w or #str
end

local ok_lib_trim, lib_trim = pcall(require, "lib.lua.strings.core")

---@internal
---@param str string
---@return string
local function trim(str)
  if type(str) ~= "string" then return "" end
  if ok_lib_trim then return lib_trim.trim(str) end
  return str:match("^%s*(.-)%s*$") or ""
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cell padding
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param str string
---@param width integer
---@param align "left"|"center"|"right"
---@return string
local function pad_cell(str, width, align)
  local content = trim(str)
  local cw = display_width(content)
  if cw >= width then return content end
  local pad = width - cw
  if align == "left" then
    return content .. string.rep(" ", pad)
  elseif align == "right" then
    return string.rep(" ", pad) .. content
  else
    local lp = math.floor(pad / 2)
    return string.rep(" ", lp) .. content .. string.rep(" ", pad - lp)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Column-override resolution
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param overrides Mkdn.TableColOverride[]|nil
---@param header_cells string[]
---@param col_count integer
---@return table<integer, string>
local function resolve_overrides(overrides, header_cells, col_count)
  local map = {}
  if not overrides or #overrides == 0 then return map end
  local name_to_idx = {}
  for i = 1, col_count do
    local key = trim(header_cells[i] or ""):lower()
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
      map[idx] = ov.align
    else
      notify.warn(string.format("col_overrides: column %q not found (ignored)", tostring(ov.col)))
    end
  end
  return map
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Table parsing helpers
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param line any
---@return boolean
local function is_table_line(line)
  if type(line) ~= "string" then return false end
  return trim(line):match("^|.*|$") ~= nil
end

---@internal
---@param line any
---@return boolean is_sep
---@return "spaced"|"compact"|nil style
local function is_separator_line(line)
  if type(line) ~= "string" then return false, nil end
  local t = trim(line)
  if not t:match("%-") then return false, nil end
  if not t:match("^|.*|$") then return false, nil end
  local inner = t:match("^|(.+)|$")
  if not inner then return false, nil end
  if not inner:match("^[%-%s:|]+$") then return false, nil end
  local spaced = inner:match("%s%-") or inner:match("%-%s")
  return true, spaced and "spaced" or "compact"
end

---@internal
---@param line string
---@return string[]
local function parse_row(line)
  local cells = {}
  local trimmed = trim(line)
  local inner = trimmed:match("^|(.-)%s*|$") or trimmed:match("^|(.*)|$")
  if not inner then return cells end
  local cur = ""
  for i = 1, #inner do
    local ch = inner:sub(i, i)
    if ch == "|" then
      cells[#cells + 1] = trim(cur)
      cur = ""
    else
      cur = cur .. ch
    end
  end
  cells[#cells + 1] = trim(cur)
  return cells
end

---@internal
---@param lines string[]
---@return table[] tables
local function parse_all_tables(lines)
  local tables = {}
  local i = 1
  while i <= #lines do
    if not is_table_line(lines[i]) then
      i = i + 1
    else
      local start = i
      while i <= #lines and is_table_line(lines[i]) do
        i = i + 1
      end
      local stop = i - 1
      if stop - start < 2 then goto continue end
      local rows, sep_style, sep_line_idx, col_count = {}, nil, nil, 0
      for ln = start, stop do
        local is_sep, style = is_separator_line(lines[ln])
        if is_sep then
          if not sep_line_idx then
            sep_line_idx = ln
            sep_style = style
          end
        else
          local cells = parse_row(lines[ln])
          rows[#rows + 1] = cells
          if #rows == 1 then col_count = #cells end
        end
      end
      if #rows >= 2 and sep_line_idx and sep_line_idx == start + 1 then
        for _, row in ipairs(rows) do
          while #row < col_count do
            row[#row + 1] = ""
          end
        end
        tables[#tables + 1] = {
          start_line = start,
          end_line = stop,
          rows = rows,
          separator_style = sep_style or "compact",
          col_count = col_count,
        }
      end
      ::continue::
    end
  end
  return tables
end

---@internal
---@param tables table[]
---@param cursor_line integer
---@return table? tbl
---@return string? err
local function find_table_at_cursor(tables, cursor_line)
  for _, tbl in ipairs(tables) do
    if cursor_line >= tbl.start_line and cursor_line <= tbl.end_line then return tbl, nil end
  end
  return nil, "Cursor is not inside a table"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Formatting / rendering
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param rows string[][]
---@param col_count integer
---@return integer[]
local function calc_widths(rows, col_count)
  local widths = {}
  for i = 1, col_count do
    widths[i] = 1
  end
  for _, row in ipairs(rows) do
    for ci, cell in ipairs(row) do
      if ci <= col_count then widths[ci] = math.max(widths[ci], display_width(cell)) end
    end
  end
  return widths
end

---@internal
---@param widths integer[]
---@param style "spaced"|"compact"
---@return string
local function gen_separator(widths, style)
  local parts = {}
  if style == "spaced" then
    for _, w in ipairs(widths) do
      parts[#parts + 1] = " " .. string.rep("-", w) .. " "
    end
    return "|" .. table.concat(parts, "|") .. "|"
  else
    for _, w in ipairs(widths) do
      parts[#parts + 1] = string.rep("-", w + 2)
    end
    return "|" .. table.concat(parts, "|") .. "|"
  end
end

---@internal
---@param cells string[]
---@param widths integer[]
---@param default_align "left"|"center"|"right"
---@param override_map table<integer, string>
---@return string
local function format_row(cells, widths, default_align, override_map)
  local parts = {}
  for ci, w in ipairs(widths) do
    local align = override_map[ci] or default_align
    parts[#parts + 1] = pad_cell(cells[ci] or "", w, align)
  end
  return "| " .. table.concat(parts, " | ") .. " |"
end

---@internal
---@param parsed table
---@param header_align "left"|"center"|"right"
---@param entry_align "left"|"center"|"right"
---@param override_map table<integer, string>
---@return string[]
local function render_table(parsed, header_align, entry_align, override_map)
  local widths = calc_widths(parsed.rows, parsed.col_count)
  local out = {}
  out[1] = format_row(parsed.rows[1], widths, header_align, override_map)
  out[2] = gen_separator(widths, parsed.separator_style)
  for i = 2, #parsed.rows do
    out[#out + 1] = format_row(parsed.rows[i], widths, entry_align, override_map)
  end
  return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HTML import (round-trip with the TableView browser export)
-- ─────────────────────────────────────────────────────────────────────────────

local HTML_ENTITIES = {
  { "&quot;", '"' },
  { "&apos;", "'" },
  { "&#39;", "'" },
  { "&lt;", "<" },
  { "&gt;", ">" },
  { "&nbsp;", " " },
  { "&amp;", "&" }, -- last: avoids re-decoding entities produced by earlier passes
}

---@internal
---@param s string
---@return string
local function unescape_html(s)
  for _, pair in ipairs(HTML_ENTITIES) do
    s = s:gsub(pair[1], pair[2])
  end
  return s
end

---@internal
---@param s string
---@return string
local function strip_tags(s) return trim((s:gsub("<[^>]*>", ""))) end

--- Parse the first `<table>...</table>` in `html` into rows of plain-text
--- cells: HTML tags inside a cell are stripped and entities unescaped. The
--- first row (whether `<th>` or `<td>`) becomes the GFM header row.
---@param html string
---@return string[][]|nil rows
---@return string|nil err
function M.parse_html_table(html)
  if type(html) ~= "string" or html == "" then return nil, "No HTML given" end

  local body = html:match("<[Tt][Aa][Bb][Ll][Ee][^>]*>(.-)</[Tt][Aa][Bb][Ll][Ee]>")
  if not body then return nil, "No <table> element found" end

  local rows = {}
  for tr in body:gmatch("<[Tt][Rr][^>]*>(.-)</[Tt][Rr]>") do
    local cells = {}
    for content in tr:gmatch("<[Tt][HhDd][^>]*>(.-)</[Tt][HhDd]>") do
      cells[#cells + 1] = unescape_html(strip_tags(content))
    end
    if #cells > 0 then rows[#rows + 1] = cells end
  end

  if #rows == 0 then return nil, "No rows found in <table>" end
  return rows, nil
end

--- Render already-parsed HTML rows (`M.parse_html_table`'s result) as GFM
--- table lines, using the same alignment/width machinery as `format_*`. The
--- first row is treated as the header.
---@param rows string[][]
---@param opts? { header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return string[]
function M.rows_to_gfm(rows, opts)
  opts = opts or {}
  local dcfg = get_cfg()
  local header_align = opts.header_align or dcfg.header_align
  local entry_align = opts.entry_align or dcfg.entry_align

  local col_count = 0
  for _, r in ipairs(rows) do
    col_count = math.max(col_count, #r)
  end
  for _, r in ipairs(rows) do
    while #r < col_count do
      r[#r + 1] = ""
    end
  end

  local override_map =
    resolve_overrides(opts.col_overrides or dcfg.col_overrides, rows[1], col_count)
  local parsed = { rows = rows, col_count = col_count, separator_style = "compact" }
  return render_table(parsed, header_align, entry_align, override_map)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Buffer helpers
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param bufnr integer
---@return string[]? lines
---@return string? err
local function buf_get_lines(bufnr)
  local ok, lines = safe_call(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  return (ok and type(lines) == "table") and lines or nil, ok and nil or "Failed to read buffer"
end

---@internal
---@param bufnr integer
---@param tables { parsed: table, rendered: string[] }[]
---@return boolean ok
---@return string? err
local function apply_tables_to_buf(bufnr, tables)
  table.sort(tables, function(a, b) return a.parsed.start_line > b.parsed.start_line end)
  for _, entry in ipairs(tables) do
    local ok = safe_call(
      vim.api.nvim_buf_set_lines,
      bufnr,
      entry.parsed.start_line - 1,
      entry.parsed.end_line,
      false,
      entry.rendered
    )
    if not ok then return false, "Failed to update buffer at line " .. entry.parsed.start_line end
  end
  return true, nil
end

---@internal
---@param path string
---@param header_align "left"|"center"|"right"
---@param entry_align "left"|"center"|"right"
---@param col_overrides Mkdn.TableColOverride[]|nil
---@return boolean ok
---@return string? err
local function format_file(path, header_align, entry_align, col_overrides)
  local fh, err = io.open(path, "r")
  if not fh then return false, string.format("Cannot open %q: %s", path, err or "?") end
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = line
  end
  fh:close()

  local tables = parse_all_tables(lines)
  if #tables == 0 then return true, nil end

  table.sort(tables, function(a, b) return a.start_line > b.start_line end)
  for _, parsed in ipairs(tables) do
    local om = resolve_overrides(col_overrides, parsed.rows[1], parsed.col_count)
    local rendered = render_table(parsed, header_align, entry_align, om)
    for ri, rl in ipairs(rendered) do
      lines[parsed.start_line - 1 + ri] = rl
    end
  end

  local wh, werr = io.open(path, "w")
  if not wh then return false, string.format("Cannot write %q: %s", path, werr or "?") end
  for _, line in ipairs(lines) do
    wh:write(line .. "\n")
  end
  wh:close()
  return true, nil
end

local collect_md_files = require("markdown.util.md_files").collect

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal re-exports (for markdown.core.table_wrap — avoids duplicating the
-- parse/format primitives)
-- ─────────────────────────────────────────────────────────────────────────────

M.trim = trim
M.display_width = display_width
M.pad_cell = pad_cell
M.is_table_line = is_table_line
M.is_separator_line = is_separator_line
M.parse_row = parse_row
M.parse_all_tables = parse_all_tables
M.find_table_at_cursor = find_table_at_cursor
M.calc_widths = calc_widths
M.gen_separator = gen_separator
M.format_row = format_row
M.resolve_overrides = resolve_overrides

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--- Formats the GFM table under the cursor in `bufnr`.
---@param bufnr integer?
---@param opts? { header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return boolean ok
---@return string? err
function M.format_table_at_cursor(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then return false, "Invalid buffer" end

  local dcfg = get_cfg()
  local header_align = opts.header_align or dcfg.header_align
  local entry_align = opts.entry_align or dcfg.entry_align
  local ok_c, cursor = safe_call(vim.api.nvim_win_get_cursor, 0)
  if not ok_c then return false, "Failed to get cursor position" end

  local lines, re = buf_get_lines(bufnr)
  if not lines then return false, re end

  local tables = parse_all_tables(lines)
  local parsed, fe = find_table_at_cursor(tables, cursor[1])
  if not parsed then return false, fe end

  local override_map =
    resolve_overrides(opts.col_overrides or dcfg.col_overrides, parsed.rows[1], parsed.col_count)
  local rendered = render_table(parsed, header_align, entry_align, override_map)
  local ok_s = safe_call(
    vim.api.nvim_buf_set_lines,
    bufnr,
    parsed.start_line - 1,
    parsed.end_line,
    false,
    rendered
  )
  return ok_s and true or false, ok_s and nil or "Failed to update buffer"
end

--- Formats every GFM table in `bufnr`.
---@param bufnr integer?
---@param opts? { header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return boolean ok
---@return string? err
---@return integer count
function M.format_tables_in_buffer(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then return false, "Invalid buffer", 0 end

  local dcfg = get_cfg()
  local header_align = opts.header_align or dcfg.header_align
  local entry_align = opts.entry_align or dcfg.entry_align
  local lines, re = buf_get_lines(bufnr)
  if not lines then return false, re, 0 end

  local tables = parse_all_tables(lines)
  if #tables == 0 then return true, nil, 0 end

  local pending = {}
  for _, parsed in ipairs(tables) do
    local override_map =
      resolve_overrides(opts.col_overrides or dcfg.col_overrides, parsed.rows[1], parsed.col_count)
    local rendered = render_table(parsed, header_align, entry_align, override_map)
    pending[#pending + 1] = { parsed = parsed, rendered = rendered }
  end

  local ok, err = apply_tables_to_buf(bufnr, pending)
  return ok, err, #pending
end

--- Formats table(s) per `opts.scope`: "cursor"|"buffer"|"cwd"|<path>.
---@param opts? { scope?: string, header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return boolean ok
---@return string? err
function M.format_tables_in_scope(opts)
  opts = opts or {}
  local scope = opts.scope or "cursor"
  local dcfg = get_cfg()
  local header_align = opts.header_align or dcfg.header_align
  local entry_align = opts.entry_align or dcfg.entry_align
  local col_overrides = opts.col_overrides or dcfg.col_overrides

  if scope == "cursor" then
    return M.format_table_at_cursor(nil, opts)
  elseif scope == "buffer" then
    local ok, err, count = M.format_tables_in_buffer(nil, opts)
    if ok then notify.info(string.format("Formatted %d table(s) in buffer", count)) end
    return ok, err
  elseif scope == "cwd" then
    local cwd = vim.fn.getcwd()
    local files = collect_md_files(cwd)
    if #files == 0 then
      notify.info("No *.md files found under " .. cwd)
      return true, nil
    end
    local errors, cnt = {}, 0
    for _, path in ipairs(files) do
      local ok, err = format_file(path, header_align, entry_align, col_overrides)
      if ok then
        cnt = cnt + 1
      else
        errors[#errors + 1] = err
      end
    end
    if #errors > 0 then
      notify.warn(
        string.format(
          "Formatted %d/%d files; %d error(s):\n  %s",
          cnt,
          #files,
          #errors,
          table.concat(errors, "\n  ")
        )
      )
    else
      notify.info(string.format("Formatted tables in %d file(s)", cnt))
    end
    return #errors == 0, #errors > 0 and table.concat(errors, "; ") or nil
  else
    local path = vim.fn.expand(scope)
    if vim.fn.filereadable(path) == 0 then
      return false, string.format("File not readable: %q", path)
    end
    local ok, err = format_file(path, header_align, entry_align, col_overrides)
    if ok then notify.info(string.format("Formatted tables in %q", path)) end
    return ok, err
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Argument parsing for `:Markdown table format ...`
-- ─────────────────────────────────────────────────────────────────────────────

--- Parses `:Markdown table format ARGS` into format opts.
---@param args string[]
---@return table opts, string|nil err
function M.parse_args(args)
  local opts, positional = {}, {}
  for _, raw in ipairs(args) do
    local key, val = raw:match("^([%w_]+)=(.+)$")
    if key and val then
      key = key:lower()
      if key == "header" then
        if not VALID_ALIGN[val] then
          return opts, string.format("Invalid alignment for header=: %q", val)
        end
        opts.header_align = val
      elseif key == "cell" or key == "entry" then
        if not VALID_ALIGN[val] then
          return opts, string.format("Invalid alignment for cell=: %q", val)
        end
        opts.entry_align = val
      elseif key == "skip" then
        opts.col_overrides = opts.col_overrides or {}
        for part in val:gmatch("[^,]+") do
          part = part:match("^%s*(.-)%s*$")
          opts.col_overrides[#opts.col_overrides + 1] =
            { col = tonumber(part) or part, align = "left" }
        end
      elseif key == "scope" then
        opts.scope = val
      else
        return opts, string.format("Unknown option: %q", raw)
      end
    elseif VALID_ALIGN[raw:lower()] then
      positional[#positional + 1] = raw:lower()
    else
      return opts, string.format("Unknown argument: %q", raw)
    end
  end
  if #positional >= 1 and not opts.header_align then opts.header_align = positional[1] end
  if #positional >= 2 and not opts.entry_align then
    opts.entry_align = positional[2]
  elseif #positional == 1 and not opts.entry_align then
    opts.entry_align = positional[1]
  end
  return opts, nil
end

--- Completion for `:Markdown table format` arguments.
---@param arg_lead string
---@return string[]
function M.complete(arg_lead)
  local candidates = {
    "left",
    "center",
    "right",
    "header=left",
    "header=center",
    "header=right",
    "cell=left",
    "cell=center",
    "cell=right",
    "skip=",
    "scope=cursor",
    "scope=buffer",
    "scope=cwd",
  }
  local out = {}
  for _, c in ipairs(candidates) do
    if vim.startswith(c, arg_lead) then out[#out + 1] = c end
  end
  return out
end

return M
