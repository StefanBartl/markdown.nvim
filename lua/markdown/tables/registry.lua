---@module 'markdown.tables.registry'
---@brief Table formats behind one registry: find tables in lines, render a table in any format.
---@description
--- A format is a module under `markdown.tables.formats.<name>`:
---
---   scan(lines, opts?)   -> tables   embedded formats: every table in `lines`
---   parse(lines)         -> table    standalone formats (csv, tsv): all of `lines` is one table
---   render(tbl, opts?)   -> string[] the table written in this format
---   lossy?(tbl)          -> string[] what `render` cannot keep (shown as a warning by convert)
---
--- The table model is the one `tableview.parser` has always produced (`header.cells`,
--- `alignments`, `rows[].cells`, `start_line`, `end_line`, `raw_lines`), plus `format`.
--- Which embedded formats are looked for is `table.formats` (default `{ "gfm" }`), so
--- nothing changes for anybody who does not opt in.
---
---   M.find(lines, opts)        – tables of the enabled formats, in line order, no overlaps
---   M.render(name, tbl, opts)  – lines of `tbl` in format `name`
---   M.parse(name, lines)       – a standalone format as one table
---   M.names() / M.get(name)    – what exists

local M = {}

local BUILTIN = { "gfm", "org", "box", "csv", "tsv" }

---@type table<string, table>
local loaded = {}

---@param name string
---@return table|nil
function M.get(name)
  if loaded[name] == nil then
    local ok, mod = pcall(require, "markdown.tables.formats." .. name)
    loaded[name] = ok and mod or false
  end
  return loaded[name] or nil
end

---@return string[]
function M.names() return vim.deepcopy(BUILTIN) end

---Formats that live inside documents (they have `scan`).
---@return string[]
function M.embedded()
  local out = {}
  for _, n in ipairs(BUILTIN) do
    local f = M.get(n)
    if f and f.scan then out[#out + 1] = n end
  end
  return out
end

---@internal
---@return string[]
local function configured()
  local ok, config = pcall(require, "markdown.config")
  local list = ok and config.get().table and config.get().table.formats
  if type(list) == "table" and #list > 0 then return list end
  return { "gfm" }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Model helpers
-- ─────────────────────────────────────────────────────────────────────────────

---A table in the parser's model from plain strings.
---@param header string[]
---@param rows string[][]
---@param aligns? string[]
---@param extra? table
---@return table tbl
function M.from_strings(header, rows, aligns, extra)
  local function cells(list)
    local out = {}
    for i, c in ipairs(list) do
      out[i] = { content = c }
    end
    return out
  end
  local tbl = { header = { cells = cells(header) }, alignments = aligns or {}, rows = {} }
  for i, r in ipairs(rows) do
    tbl.rows[i] = { cells = cells(r) }
  end
  for c = 1, #header do
    tbl.alignments[c] = tbl.alignments[c] or "left"
  end
  return vim.tbl_extend("force", tbl, extra or {})
end

---The strings of a table in the parser's model.
---@param tbl table
---@return string[] header, string[][] rows, string[] aligns
function M.strings(tbl)
  local function plain(row)
    local out = {}
    for i, c in ipairs(row.cells) do
      out[i] = vim.trim(type(c) == "table" and c.content or c)
    end
    return out
  end
  local rows = {}
  for i, r in ipairs(tbl.rows) do
    rows[i] = plain(r)
  end
  return plain(tbl.header), rows, vim.deepcopy(tbl.alignments or {})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Find / render / parse
-- ─────────────────────────────────────────────────────────────────────────────

---Every table of the enabled formats in `lines`, ordered by line, none overlapping
---(on a clash the format listed first wins).
---@param lines string[]
---@param opts? { formats?: string[], skip_fences?: boolean }
---@return table[]
function M.find(lines, opts)
  opts = opts or {}
  local names = opts.formats or configured()
  local all = {}
  for rank, name in ipairs(names) do
    local f = M.get(name)
    if f and f.scan then
      for _, t in ipairs(f.scan(lines, { skip_fences = opts.skip_fences })) do
        t.format, t._rank = name, rank
        all[#all + 1] = t
      end
    end
  end
  if #names <= 1 then
    for _, t in ipairs(all) do
      t._rank = nil
    end
    return all
  end
  table.sort(all, function(a, b)
    if a._rank ~= b._rank then return a._rank < b._rank end
    return a.start_line < b.start_line
  end)
  local kept = {}
  for _, t in ipairs(all) do
    local clash = false
    for _, k in ipairs(kept) do
      if t.start_line <= k.end_line and k.start_line <= t.end_line then
        clash = true
        break
      end
    end
    if not clash then kept[#kept + 1] = t end
  end
  table.sort(kept, function(a, b) return a.start_line < b.start_line end)
  for _, t in ipairs(kept) do
    t._rank = nil
  end
  return kept
end

---@param name string
---@param tbl table
---@param opts? table
---@return string[]|nil lines, string|nil err
function M.render(name, tbl, opts)
  local f = M.get(name)
  if not f or not f.render then return nil, "no writer for format '" .. tostring(name) .. "'" end
  return f.render(tbl, opts), nil
end

---A standalone format (csv, tsv, ...) read as one table.
---@param name string
---@param lines string[]
---@param opts? table  # handed to the format (csv: `{ sep = ";" }`)
---@return table|nil tbl, string|nil err
function M.parse(name, lines, opts)
  local f = M.get(name)
  if not f or not f.parse then
    return nil, "'" .. tostring(name) .. "' is not a standalone format"
  end
  local tbl, err = f.parse(lines, opts)
  -- the format the table was read in (a csv model holds no GFM escapes: see csv.render)
  if tbl and not tbl.format then tbl.format = name end
  return tbl, err
end

---What `render` of format `name` cannot keep of `tbl`.
---@param name string
---@param tbl table
---@return string[]
function M.lossy(name, tbl)
  -- what the source format could not hold was lost by reading it; writing it back in the
  -- same format keeps everything the model holds (org rules, box rules and border)
  local out = tbl.format == name and {} or vim.deepcopy(tbl.lossy or {})
  -- `lost`: what the reader dropped without storing it, so no writer can bring it back
  vim.list_extend(out, tbl.lost or {})
  local f = M.get(name)
  if f and f.lossy then vim.list_extend(out, f.lossy(tbl)) end
  return out
end

return M
