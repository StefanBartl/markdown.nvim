---@module 'markdown.tables.formats.grid'
---@brief Grid tables: `+---+---+ | a | b | +===+===+`, as MySQL/MariaDB output, reStructuredText and Pandoc grid tables.
---@description
--- A block runs from a border line (`+---+---+`) to a border line; the lines in between are
--- `|` rows or more borders. All borders of a table have their `+` in the same columns and every
--- row has a `|` there: a table with spanning cells (a `+` or `|` missing somewhere) is not read at
--- all, so nothing is guessed. Cells are cut by those columns, so a `|` inside a cell is fine.
---
--- The header ends at a `+===+` border (reST, Pandoc; `+:===:+` gives the alignment). Without
--- one, the first row is the header (MySQL draws one border under it): with at most one border
--- inside the table every line is a row, otherwise the lines between two borders are one row
--- (multi-line cells, joined with `<br>`). Written back, `style = "mysql"` keeps `-` under the
--- header, anything else uses `=`.

local slice = require("markdown.tables.slice")

local M = {}

---@param line string
---@return boolean
local function is_border(line)
  local t = vim.trim(line)
  return #t >= 3 and t:match("^%+[-=:+]*%+$") ~= nil and t:find("[-=]") ~= nil
end

---@param line string
---@return boolean
local function is_row(line)
  local t = vim.trim(line)
  return #t >= 2 and t:sub(1, 1) == "|" and t:sub(-1) == "|"
end

---The columns of the `+` signs of a border (0-based; the indent counts).
---@param line string
---@return integer[]
local function plus_cols(line)
  local cols = {}
  for i = 1, #line do
    if line:sub(i, i) == "+" then cols[#cols + 1] = i - 1 end
  end
  return cols
end

---@param a integer[]
---@param b integer[]
---@return boolean
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if is_border(lines[i]) and not fenced[i] then
      local j = i
      while
        j + 1 <= #lines
        and not fenced[j + 1]
        and (is_border(lines[j + 1]) or is_row(lines[j + 1]))
      do
        j = j + 1
      end
      -- trailing rows without a closing border are not part of the table
      while j > i and not is_border(lines[j]) do
        j = j - 1
      end
      local tbl = j > i and M.parse_block(vim.list_slice(lines, i, j), i) or nil
      if tbl then
        found[#found + 1] = tbl
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
---@return table|nil tbl  # nil when the block is no plain grid (spans, misaligned columns, no row)
function M.parse_block(block, start_line)
  local registry = require("markdown.tables.registry")
  local cols = plus_cols(block[1])
  if #cols < 2 then return nil end

  local ranges = {}
  for k = 1, #cols - 1 do
    ranges[k] = { from = cols[k] + 1, to = cols[k + 1] }
  end

  -- groups of row lines between borders; `kinds[n]` is the border after group n
  local groups, cur, borders = {}, nil, {}
  for _, line in ipairs(block) do
    if is_border(line) then
      if not same(plus_cols(line), cols) then return nil end
      if cur then
        groups[#groups + 1] = cur
        cur = nil
      end
      borders[#borders + 1] = vim.trim(line)
    else
      for _, c in ipairs(cols) do
        if slice.char_at(line, c) ~= "|" then return nil end
      end
      cur = cur or {}
      cur[#cur + 1] = slice.cells(line, ranges)
    end
  end
  if #groups == 0 then return nil end

  local function merge(list)
    local merged = {}
    for _, parts in ipairs(list) do
      for c = 1, #ranges do
        local v = parts[c] or ""
        if merged[c] and merged[c] ~= "" then
          merged[c] = merged[c] .. (v ~= "" and ("<br>" .. v) or "")
        else
          merged[c] = v
        end
      end
    end
    return merged
  end

  -- where the header ends: the `=` border, else the first border under the first group
  local header_border
  for n = 2, #borders - 1 do
    if borders[n]:find("=", 1, true) then
      header_border = n
      break
    end
  end
  local rows = {}
  local header
  local inner = #borders - 2
  if header_border then
    -- the groups above the `=` border are all header lines
    local lines_of_header = {}
    for g = 1, header_border - 1 do
      for _, parts in ipairs(groups[g]) do
        lines_of_header[#lines_of_header + 1] = parts
      end
    end
    header = merge(lines_of_header)
    for g = header_border, #groups do
      rows[#rows + 1] = merge(groups[g])
    end
  elseif inner <= 1 then
    header = merge(groups[1])
    for g = 2, #groups do
      for _, parts in ipairs(groups[g]) do
        rows[#rows + 1] = parts
      end
    end
  else
    header = merge(groups[1])
    for g = 2, #groups do
      rows[#rows + 1] = merge(groups[g])
    end
  end

  -- alignment from the header border (`+:===:+`, pandoc), else from a `-` one with colons
  local aligns
  local sep = header_border and borders[header_border] or borders[2]
  if sep and sep:find(":", 1, true) then
    aligns = {}
    for k = 1, #ranges do
      local seg = sep:sub(cols[k] - cols[1] + 2, cols[k + 1] - cols[1])
      local l, r = seg:sub(1, 1) == ":", seg:sub(-1) == ":"
      aligns[k] = (l and r and "center") or (r and "right") or "left"
    end
  end

  return registry.from_strings(header, rows, aligns, {
    style = header_border and "rst" or "mysql",
    row_rules = not header_border and inner > 1,
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
end

---@param tbl table
---@return boolean
local function multiline(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local function has(row)
    for _, v in ipairs(row) do
      if v:find("<br", 1, true) or v:find("\n", 1, true) then return true end
    end
    return false
  end
  if has(header) then return true end
  for _, r in ipairs(rows) do
    if has(r) then return true end
  end
  return false
end

---@param tbl table
---@param opts? { style?: "rst"|"mysql" }
---@return string[]
function M.render(tbl, opts)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local n = #header
  local style = (opts and opts.style) or tbl.style or "rst"

  local function expand(row)
    local cells, height = {}, 1
    for c = 1, n do
      cells[c] = slice.lines_of(row[c] or "")
      height = math.max(height, #cells[c])
    end
    return cells, height
  end

  local widths = {}
  local expanded = {}
  local all = { header }
  vim.list_extend(all, rows)
  for r, row in ipairs(all) do
    local cells, height = expand(row)
    expanded[r] = { cells = cells, height = height }
    for c = 1, n do
      for _, text in ipairs(cells[c]) do
        widths[c] = math.max(widths[c] or 1, vim.fn.strdisplaywidth(text))
      end
    end
  end

  local function border(fill, with_aligns)
    local parts = {}
    for c = 1, n do
      local seg = fill:rep(widths[c] + 2)
      if with_aligns then
        local a = aligns[c] or "left"
        if a == "center" then
          seg = ":" .. seg:sub(2, -2) .. ":"
        elseif a == "right" then
          seg = seg:sub(1, -2) .. ":"
        end
      end
      parts[c] = seg
    end
    return "+" .. table.concat(parts, "+") .. "+"
  end

  local any_align = false
  for c = 1, n do
    if (aligns[c] or "left") ~= "left" then any_align = true end
  end
  local function row_lines(item)
    local out = {}
    for l = 1, item.height do
      local parts = {}
      for c = 1, n do
        parts[c] = " " .. slice.pad(item.cells[c][l] or "", widths[c]) .. " "
      end
      out[#out + 1] = "|" .. table.concat(parts, "|") .. "|"
    end
    return out
  end

  local between = style == "rst" or tbl.row_rules == true or multiline(tbl)
  local out = { border("-") }
  vim.list_extend(out, row_lines(expanded[1]))
  out[#out + 1] = border(style == "mysql" and not any_align and "-" or "=", any_align)
  for r = 2, #expanded do
    vim.list_extend(out, row_lines(expanded[r]))
    if between and r < #expanded then out[#out + 1] = border("-") end
  end
  out[#out + 1] = border("-")
  return out
end

M._is_border = is_border

return M
