---@module 'markdown.tables.formats.csv'
---@brief CSV / TSV (RFC 4180: quoted fields, doubled quotes, separators and newlines inside quotes).
---@description
--- Standalone: all given lines are one table (no `scan`), the first record is the header.
--- `markdown.tables.formats.tsv` is this module with a tab as separator.

local M = {}

M.sep = ","

---Records of `text`. A quoted field may contain the separator, quotes (doubled) and newlines.
---@param text string
---@param sep string  # one character
---@return string[][] records
function M.records(text, sep)
  local records, row, field = {}, {}, {}
  local i, n, quoted, had_quote = 1, #text, false, false
  local function push_field()
    row[#row + 1] = table.concat(field)
    field = {}
  end
  local function push_row()
    push_field()
    -- a blank line is no record, but a quoted empty field (`""`) is one
    if not (#row == 1 and row[1] == "" and not had_quote) then records[#records + 1] = row end
    row, had_quote = {}, false
  end
  while i <= n do
    local ch = text:sub(i, i)
    if quoted then
      if ch == '"' then
        if text:sub(i + 1, i + 1) == '"' then
          field[#field + 1] = '"'
          i = i + 1
        else
          quoted = false
        end
      elseif not (ch == "\r" and text:sub(i + 1, i + 1) == "\n") then
        -- (the CR of a CRLF inside a quoted field is dropped: it is one newline)
        field[#field + 1] = ch
      end
    elseif ch == '"' and #field == 0 then
      quoted, had_quote = true, true
    elseif ch == sep then
      push_field()
    elseif ch == "\r" then
      if text:sub(i + 1, i + 1) == "\n" then i = i + 1 end
      push_row()
    elseif ch == "\n" then
      push_row()
    else
      field[#field + 1] = ch
    end
    i = i + 1
  end
  if #field > 0 or #row > 0 or had_quote then push_row() end
  return records
end

---@param lines string[]
---@param opts? { sep?: string }  # field separator, default `M.sep`
---@return table|nil tbl, string|nil err
function M.parse(lines, opts)
  local registry = require("markdown.tables.registry")
  local recs = M.records(table.concat(lines, "\n"), opts and opts.sep or M.sep)
  if #recs == 0 then return nil, "nothing to read" end
  local header = table.remove(recs, 1)
  local width = #header
  for _, r in ipairs(recs) do
    width = math.max(width, #r)
  end
  for c = #header + 1, width do
    header[c] = ""
  end
  local tbl = registry.from_strings(header, recs, nil, {
    start_line = 1,
    end_line = #lines,
    raw_lines = lines,
  })
  return tbl, nil
end

---@param tbl table
---@param opts? { sep?: string }  # field separator, default `M.sep`
---@return string[]
function M.render(tbl, opts)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local sep = opts and opts.sep or M.sep
  local function field(v)
    v = v:gsub("<br>", "\n")
    -- an escaped pipe (`\|`, GFM / org cell text) is a plain pipe in the data
    v = v:gsub("(\\*)|", function(bs)
      if #bs % 2 == 1 then return bs:sub(1, -2) .. "|" end
      return bs .. "|"
    end)
    if
      v:find('[%s"' .. vim.pesc(sep) .. "]")
      and (v:find('["\n' .. vim.pesc(sep) .. "]") or v:match("^%s") or v:match("%s$"))
    then
      return '"' .. v:gsub('"', '""') .. '"'
    end
    return v
  end
  local function line(cells)
    local out = {}
    for c = 1, #header do
      out[c] = field(cells[c] or "")
    end
    -- the only column of a row is empty: an empty line would read back as no record
    if #header == 1 and out[1] == "" then out[1] = '""' end
    return table.concat(out, sep)
  end
  local out = { line(header) }
  for _, r in ipairs(rows) do
    out[#out + 1] = line(r)
  end
  return vim.split(table.concat(out, "\n"), "\n", { plain = true })
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  local out = {}
  for _, a in ipairs(tbl.alignments or {}) do
    if a ~= "left" then
      out[#out + 1] = "column alignment"
      break
    end
  end
  return out
end

return M
