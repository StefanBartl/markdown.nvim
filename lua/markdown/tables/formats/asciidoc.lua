---@module 'markdown.tables.formats.asciidoc'
---@brief AsciiDoc tables: `[%header]`, `|===`, `|a |b` rows, a blank line after the header row, `|===`.
---@description
--- A table runs from a `|===` line to the next `|===`; an attribute line (`[%header]`,
--- `[options="header"]`, `[cols="1,2"]`) right above is part of it. Every line that starts with `|`
--- is a row of cells (`|a |b`, a `\|` is a pipe); a line without a leading `|` continues the cell
--- above (joined with `<br>`). The header is the first row when the attributes say `header` or when
--- a blank line follows it; otherwise the first row is used as the header all the same. Cell
--- specifiers (`2+|`, `a|`, `.2+|`) are not read: such a table is left alone.

local M = {}

---@param line string
---@return boolean
local function is_fence(line) return vim.trim(line) == "|===" end

---@param line string
---@return boolean
local function is_attr(line) return vim.trim(line):match("^%[.*%]$") ~= nil end

---Cells of one row line: split at every `|` that is not escaped.
---@param line string
---@return string[] cells
local function cells_of(line)
  local out = {}
  local cur = {}
  local i, n = 1, #line
  local started = false
  while i <= n do
    local ch = line:sub(i, i)
    if ch == "\\" and line:sub(i + 1, i + 1) == "|" then
      cur[#cur + 1] = "|"
      i = i + 1
    elseif ch == "|" then
      if started then out[#out + 1] = vim.trim(table.concat(cur)) end
      cur, started = {}, true
    else
      cur[#cur + 1] = ch
    end
    i = i + 1
  end
  if started then out[#out + 1] = vim.trim(table.concat(cur)) end
  return out
end

---A cell specifier sits right in front of a `|`: `2+|`, `.3+|`, `a|`, `^.^|`.
---@param line string
---@return boolean
local function has_specifier(line)
  for spec in line:gmatch("%s([%w%.%+<>%^]+)|") do
    if spec:match("^[%d%.]*%+$") or spec:match("^[%d%.]*[<>%^]*[ademhls]?$") and spec ~= "" then
      return true
    end
  end
  return false
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if is_fence(lines[i]) and not fenced[i] then
      local j = i + 1
      while j <= #lines and not fenced[j] and not is_fence(lines[j]) do
        j = j + 1
      end
      if j <= #lines and not fenced[j] then
        local first = i
        local attrs = {}
        if i > 1 and is_attr(lines[i - 1]) and not fenced[i - 1] then
          first = i - 1
          attrs[1] = lines[i - 1]
        end
        local tbl = M.parse_block(vim.list_slice(lines, first, j), first, #attrs)
        if tbl then found[#found + 1] = tbl end
        i = j + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return found
end

---@param block string[]
---@param start_line integer
---@param nattr integer  # attribute lines at the top of the block (0 or 1)
---@return table|nil tbl
function M.parse_block(block, start_line, nattr)
  local registry = require("markdown.tables.registry")
  local attr = nattr > 0 and block[1] or ""
  local header_attr = attr:find("header", 1, true) ~= nil
  local rows, last, blank_after_first = {}, nil, false
  for k = nattr + 2, #block - 1 do
    local line = block[k]
    if vim.trim(line) == "" then
      if #rows == 1 then blank_after_first = true end
      last = nil
    elseif vim.trim(line):sub(1, 1) == "|" then
      local t = vim.trim(line)
      if has_specifier(t) then return nil end
      local cells = cells_of(t)
      rows[#rows + 1] = cells
      last = { #rows, #cells }
    elseif last then
      local row = rows[last[1]]
      local cur = row[last[2]]
      row[last[2]] = (cur ~= "" and (cur .. "<br>") or "") .. vim.trim(line)
    end
  end
  if #rows == 0 then return nil end
  local width = #rows[1]
  local header = table.remove(rows, 1)
  for _, r in ipairs(rows) do
    width = math.max(width, #r)
  end
  for c = #header + 1, width do
    header[c] = ""
  end
  local tbl = registry.from_strings(header, rows, nil, {
    header_marked = header_attr or blank_after_first,
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
  return tbl
end

---@param s string
---@return string
local function esc(s) return (s:gsub("|", "\\|")) end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local function line(row)
    local out = {}
    for c = 1, #header do
      out[c] = "|" .. esc((row[c] or ""):gsub("<br>", "\n"))
    end
    return vim.split(table.concat(out, " "), "\n", { plain = true })
  end
  local out = { "[%header]", "|===" }
  vim.list_extend(out, line(header))
  out[#out + 1] = ""
  for _, r in ipairs(rows) do
    vim.list_extend(out, line(r))
  end
  out[#out + 1] = "|==="
  return out
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  for _, a in ipairs(tbl.alignments or {}) do
    if a ~= "left" then return { "column alignment (AsciiDoc uses cols= for it)" } end
  end
  return {}
end

return M
