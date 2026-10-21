---@module 'markdown.tables.formats.rst'
---@brief reStructuredText simple tables: `=====  =====`, header, `=====  =====`, rows, `=====  =====`.
---@description
--- A block starts at a border (groups of `=` separated by blanks, at least two columns) and ends at
--- the next border that follows another one, so the border under the header is not the end. With
--- a border under the first line(s) the text between the first two borders is the header; with only
--- two borders the first row is the header. Cells are cut by the borders' columns (the last column
--- may run past its border). A row whose first column is blank and that has text elsewhere
--- continues the row above, as in reST (joined with `<br>`). A blank first cell is written `..`.
--- Spanning-column underlines (`-----`) are not read: such a block is skipped.

local slice = require("markdown.tables.slice")

local M = {}

---@param line string
---@return boolean
local function is_border(line)
  local t = vim.trim(line)
  return t:match("^=+[ ]+=[= ]*$") ~= nil
end

---Column ranges of a border: each group of `=`, the last one open to the right.
---@param line string
---@return { from: integer, to?: integer }[]
local function ranges_of(line)
  local out = {}
  local pos = 1
  while true do
    local s, e = line:find("=+", pos)
    if not s then break end
    out[#out + 1] = { from = s - 1 }
    pos = e + 1
  end
  for k = 1, #out - 1 do
    -- a cell reaches up to the start of the next column
    out[k].to = out[k + 1].from
  end
  return out
end

---@param line string
---@return string
local function key(line) return (line:gsub("%s+$", "")) end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if is_border(lines[i]) and not fenced[i] then
      local border = key(lines[i])
      local ends = {}
      local j = i + 1
      while j <= #lines and not fenced[j] and lines[j]:match("%S") do
        if key(lines[j]) == border then ends[#ends + 1] = j end
        j = j + 1
      end
      -- the table ends at its last identical border (2 or 3 borders in all)
      local last = ends[#ends]
      local nborders = #ends + 1
      if last and last == j - 1 and (nborders == 2 or nborders == 3) and last - i >= 2 then
        local tbl = M.parse_block(vim.list_slice(lines, i, last), i)
        if tbl then
          found[#found + 1] = tbl
          i = last + 1
        else
          i = i + 1
        end
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
---@return table|nil tbl
function M.parse_block(block, start_line)
  local registry = require("markdown.tables.registry")
  local ranges = ranges_of(block[1])
  if #ranges < 2 then return nil end
  local border = key(block[1])

  local header_lines, row_lines, borders_seen = {}, {}, 0
  for k, line in ipairs(block) do
    if k > 1 and key(line) == border then
      borders_seen = borders_seen + 1
    elseif k > 1 then
      if line:find("-", 1, true) and line:match("^%s*[- ]+$") then return nil end -- column span underline
      local cells = slice.cells(line, ranges)
      if borders_seen == 0 then
        header_lines[#header_lines + 1] = cells
      else
        row_lines[#row_lines + 1] = cells
      end
    end
  end

  local two_borders = borders_seen == 1
  local header
  local rows = {}
  local source = two_borders and header_lines or row_lines
  if two_borders then
    -- no header border: the first line is the header, the rest are rows
    header = table.remove(source, 1)
    row_lines = source
  else
    header = {}
    for c = 1, #ranges do
      local parts = {}
      for _, cells in ipairs(header_lines) do
        if cells[c] ~= "" then parts[#parts + 1] = cells[c] end
      end
      header[c] = table.concat(parts, "<br>")
    end
  end
  if not header then return nil end

  for _, cells in ipairs(row_lines) do
    local blank_first = cells[1] == "" and #rows > 0
    local rest = false
    for c = 2, #ranges do
      if cells[c] ~= "" then rest = true end
    end
    if blank_first and rest then
      local prev = rows[#rows]
      for c = 1, #ranges do
        if cells[c] ~= "" then
          prev[c] = prev[c] ~= "" and (prev[c] .. "<br>" .. cells[c]) or cells[c]
        end
      end
    else
      for c = 1, #ranges do
        if cells[c] == ".." then cells[c] = "" end
      end
      rows[#rows + 1] = cells
    end
  end

  return registry.from_strings(header, rows, nil, {
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local n = #header
  local all = { header }
  vim.list_extend(all, rows)
  local widths = {}
  local lines_of = {}
  for r, row in ipairs(all) do
    lines_of[r] = {}
    for c = 1, n do
      local v = row[c] or ""
      -- the first column cannot hold several lines: its text is joined
      lines_of[r][c] = c == 1 and { table.concat(slice.lines_of(v), " ") } or slice.lines_of(v)
      for _, text in ipairs(lines_of[r][c]) do
        local shown = (c == 1 and text == "") and ".." or text
        widths[c] = math.max(widths[c] or 2, vim.fn.strdisplaywidth(shown))
      end
    end
  end
  local function border()
    local parts = {}
    for c = 1, n do
      parts[c] = ("="):rep(widths[c])
    end
    return table.concat(parts, "  ")
  end
  local function emit(r, out)
    local height = 1
    for c = 1, n do
      height = math.max(height, #lines_of[r][c])
    end
    for l = 1, height do
      local parts = {}
      for c = 1, n do
        local text = lines_of[r][c][l] or ""
        if c == 1 and text == "" and l == 1 then text = ".." end
        parts[c] = slice.pad(text, widths[c])
      end
      out[#out + 1] = (table.concat(parts, "  "):gsub("%s+$", ""))
    end
  end
  local out = { border() }
  emit(1, out)
  out[#out + 1] = border()
  for r = 2, #all do
    emit(r, out)
  end
  out[#out + 1] = border()
  return out
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local out = {}
  for _, a in ipairs(aligns) do
    if a ~= "left" then
      out[#out + 1] = "column alignment (not part of a simple table)"
      break
    end
  end
  local function multi(v) return v:find("<br", 1, true) ~= nil or v:find("\n", 1, true) ~= nil end
  local first_col = multi(header[1] or "")
  for _, r in ipairs(rows) do
    first_col = first_col or multi(r[1] or "")
  end
  if first_col then out[#out + 1] = "multi-line text in the first column (joined with a space)" end
  return out
end

return M
