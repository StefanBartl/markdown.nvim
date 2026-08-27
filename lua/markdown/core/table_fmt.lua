---@module 'markdown.core.table_fmt'
---@brief Markdown table formatter with per-role and per-column alignment control.
---@description
--- Thin wrapper around `lib.nvim.markdown.table`'s parse/render engine — see
--- that module's README for why the engine lives there (it used to be two
--- byte-drifted copies, one here and one in buffer-ctx.nvim). This file keeps
--- everything the lib module deliberately doesn't do: config read (get_cfg),
--- notify wiring, the HTML import (parse_html_table, unescape_html,
--- strip_tags, rows_to_gfm), and the `:Markdown table format` argument
--- parsing/completion. Public API:
---   M.format_table_at_cursor(bufnr, opts)   – format the table under the cursor
---   M.format_tables_in_buffer(bufnr, opts)  – format every table in a buffer
---   M.format_tables_in_scope(opts)          – scope: "cursor"|"buffer"|"cwd"|<path>
---   M.parse_args(args)                      – parse :Markdown table format ARGS
---   M.complete(arg_lead)                    – completion for the format args
---   M.parse_html_table(html)                – parse an HTML <table> into rows of plain-text cells
---   M.rows_to_gfm(rows, opts)               – render parsed rows as GFM table lines (:Markdown table import)
---
--- Also re-exports lib.nvim.markdown.table's lower-level primitives under
--- their historical names (trim, display_width, pad_cell, is_table_line,
--- is_separator_line, parse_row, parse_all_tables, find_table_at_cursor,
--- calc_widths, gen_separator, format_row, resolve_overrides) so
--- `markdown.core.table_wrap`, `markdown.core.fold`, `markdown.core.table_mode`
--- and `markdown.commands.mdtable` keep working unchanged.

local notify = require("markdown.util.notify").create("[markdown.core.table_fmt]")
local lib_table = require("lib.nvim.markdown.table")
local collect_md_files = require("markdown.util.md_files").collect

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

---@internal
---@param warnings string[]|nil
local function report_warnings(warnings)
  for _, w in ipairs(warnings or {}) do
    notify.warn(w)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Re-exported primitives (see module doc: kept for table_wrap/fold/table_mode/mdtable)
-- ─────────────────────────────────────────────────────────────────────────────

M.trim = lib_table.trim
M.display_width = lib_table.display_width
M.pad_cell = lib_table.pad_cell
M.is_table_line = lib_table.is_table_line
M.is_separator_line = lib_table.is_separator_line
M.parse_row = lib_table.parse_row
M.parse_all_tables = lib_table.parse
M.find_table_at_cursor = lib_table.at_cursor
M.calc_widths = lib_table.calc_widths
M.gen_separator = lib_table.gen_separator
M.format_row = lib_table.format_row
M.resolve_overrides = lib_table.resolve_overrides

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
local function strip_tags(s) return M.trim((s:gsub("<[^>]*>", ""))) end

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

  local override_map, warnings =
    lib_table.resolve_overrides(opts.col_overrides or dcfg.col_overrides, rows[1], col_count)
  report_warnings(warnings)
  return lib_table.render(
    { rows = rows, col_count = col_count, separator_style = "compact" },
    { header_align = header_align, entry_align = entry_align, override_map = override_map }
  )
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--- Formats the GFM table under the cursor in `bufnr`.
---@param bufnr integer?
---@param opts? { header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return boolean ok
---@return string? err
function M.format_table_at_cursor(bufnr, opts)
  opts = opts or {}
  local dcfg = get_cfg()
  local ok, err, warnings = lib_table.format_at_cursor(bufnr, {
    header_align = opts.header_align or dcfg.header_align,
    entry_align = opts.entry_align or dcfg.entry_align,
    col_overrides = opts.col_overrides or dcfg.col_overrides,
  })
  report_warnings(warnings)
  return ok, err
end

--- Formats every GFM table in `bufnr`.
---@param bufnr integer?
---@param opts? { header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return boolean ok
---@return string? err
---@return integer count
function M.format_tables_in_buffer(bufnr, opts)
  opts = opts or {}
  local dcfg = get_cfg()
  local ok, err, count, warnings = lib_table.format_buffer(bufnr, {
    header_align = opts.header_align or dcfg.header_align,
    entry_align = opts.entry_align or dcfg.entry_align,
    col_overrides = opts.col_overrides or dcfg.col_overrides,
  })
  report_warnings(warnings)
  return ok, err, count
end

--- Formats table(s) per `opts.scope`: "cursor"|"buffer"|"cwd"|<path>.
---@param opts? { scope?: string, header_align?: string, entry_align?: string, col_overrides?: Mkdn.TableColOverride[] }
---@return boolean ok
---@return string? err
function M.format_tables_in_scope(opts)
  opts = opts or {}
  local scope = opts.scope or "cursor"
  local dcfg = get_cfg()
  local file_opts = {
    header_align = opts.header_align or dcfg.header_align,
    entry_align = opts.entry_align or dcfg.entry_align,
    col_overrides = opts.col_overrides or dcfg.col_overrides,
  }

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
      local ok, err, _, warnings = lib_table.format_file(path, file_opts)
      report_warnings(warnings)
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
    local ok, err, _, warnings = lib_table.format_file(path, file_opts)
    report_warnings(warnings)
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
