---@module 'markdown.tables.formats.psql'
---@brief psql's aligned output (and sqlite `.mode column`-like): ` id | name`, `----+------`, rows, `(2 rows)`.
---@description
--- A table is a header line, a rule made only of `-` and `+` (at least one `+`: a one-column result
--- has none and is not recognised), and the rows under it. The `|` of the header and of every row
--- sit in the columns of the rule's `+`; the rows end at the first line that does not (a blank line,
--- the `(N rows)` footer, which belongs to the table and is written back). Cells are cut by those
--- columns. Written back, every cell is left-aligned: psql right-aligns numbers and centres the
--- header, which a Markdown model cannot tell.

local slice = require("markdown.tables.slice")

local M = {}

---@param line string
---@return boolean
local function is_rule(line) return line:match("^[-+]+$") ~= nil and line:find("+", 1, true) ~= nil end

---@param line string
---@return boolean
local function is_footer(line) return line:match("^%(%d+ rows?%)$") ~= nil end

---@param line string
---@return integer[]
local function plus_cols(line)
  local cols = {}
  for i = 1, #line do
    if line:sub(i, i) == "+" then cols[#cols + 1] = i - 1 end
  end
  return cols
end

---@param line string
---@param cols integer[]
---@return boolean
local function has_pipes(line, cols)
  for _, c in ipairs(cols) do
    if slice.char_at(line, c) ~= "|" then return false end
  end
  return true
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local registry = require("markdown.tables.registry")
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 2
  while i <= #lines do
    local cols = (is_rule(lines[i]) and not fenced[i] and not fenced[i - 1]) and plus_cols(lines[i])
      or nil
    if cols and has_pipes(lines[i - 1], cols) then
      local ranges = {}
      for k = 0, #cols do
        ranges[k + 1] = { from = k == 0 and 0 or cols[k] + 1, to = cols[k + 1] }
      end
      local header = slice.cells(lines[i - 1], ranges)
      local rows = {}
      local j = i + 1
      while j <= #lines and not fenced[j] and has_pipes(lines[j], cols) do
        rows[#rows + 1] = slice.cells(lines[j], ranges)
        j = j + 1
      end
      local last = j - 1
      local footer = false
      if j <= #lines and is_footer(lines[j]) then
        last, footer = j, true
      end
      local first = i - 1
      found[#found + 1] = registry.from_strings(header, rows, nil, {
        footer = footer,
        start_line = first,
        end_line = last,
        raw_lines = vim.list_slice(lines, first, last),
      })
      i = last + 2
    else
      i = i + 1
    end
  end
  return found
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local n = #header
  local function flat(row)
    local out = {}
    for c = 1, n do
      out[c] = table.concat(slice.lines_of(row[c] or ""), " ")
    end
    return out
  end
  local all = { flat(header) }
  for _, r in ipairs(rows) do
    all[#all + 1] = flat(r)
  end
  local widths = {}
  for _, row in ipairs(all) do
    for c = 1, n do
      widths[c] = math.max(widths[c] or 1, vim.fn.strdisplaywidth(row[c]))
    end
  end
  local function line(row)
    local parts = {}
    for c = 1, n do
      local cell = c == n and row[c] or slice.pad(row[c], widths[c])
      parts[c] = " " .. cell
    end
    return (table.concat(parts, " |"):gsub("%s+$", ""))
  end
  local rule = {}
  for c = 1, n do
    rule[c] = ("-"):rep(widths[c] + 2)
  end
  local out = { line(all[1]), table.concat(rule, "+") }
  for r = 2, #all do
    out[#out + 1] = line(all[r])
  end
  out[#out + 1] = ("(%d row%s)"):format(#rows, #rows == 1 and "" or "s")
  return out
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  local registry = require("markdown.tables.registry")
  local out = {}
  local header, rows, aligns = registry.strings(tbl)
  for _, a in ipairs(aligns) do
    if a ~= "left" then
      out[#out + 1] = "column alignment (psql output is read back left-aligned)"
      break
    end
  end
  local function has_br(row)
    for _, v in ipairs(row) do
      if v:find("<br", 1, true) or v:find("\n", 1, true) then return true end
    end
    return false
  end
  local multi = has_br(header)
  for _, r in ipairs(rows) do
    multi = multi or has_br(r)
  end
  if multi then out[#out + 1] = "multi-line cells (joined with a space)" end
  return out
end

return M
