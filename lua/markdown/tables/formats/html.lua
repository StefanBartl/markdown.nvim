---@module 'markdown.tables.formats.html'
---@brief HTML `<table>` with `colspan` / `rowspan`.
---@description
--- A table runs from a line with `<table` to the line with `</table>` (it may be one line). Rows are
--- `<tr>`, cells `<th>` / `<td>`; tags inside a cell are stripped (`<br>` stays), the common entities
--- are decoded. The header is the first row. `colspan` / `rowspan` are laid out on the grid: the
--- merged cell holds its text in the top-left slot, the slots it covers are empty, and the spans are
--- remembered in `spans` so this format writes them back. Every other format shows the covered slots
--- empty and reports the merge. `align=` and `style="text-align: .."` give the column alignment.

local M = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

---@param s string
---@return string
local function decode(s)
  s = s:gsub("&#(%d+);", function(n) return vim.fn.nr2char(tonumber(n)) end)
  return (s:gsub("&(%a+);", function(name) return ENTITIES[name] end))
end

---@param s string
---@return string
local function encode(s)
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  return (s:gsub("&lt;br&gt;", "<br>"))
end

---@param attrs string
---@param name string
---@return string|nil
local function attr(attrs, name)
  local v = attrs:match(name .. '%s*=%s*"([^"]*)"') or attrs:match(name .. "%s*=%s*'([^']*)'")
  return v or attrs:match(name .. "%s*=%s*([^%s>]+)")
end

---@param attrs string
---@return string|nil
local function align_of(attrs)
  local a = attr(attrs, "align")
  if not a then a = (attr(attrs, "style") or ""):match("text%-align%s*:%s*(%a+)") end
  a = a and a:lower()
  if a == "right" or a == "center" or a == "left" then return a end
  return nil
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if lines[i]:lower():find("<table[%s>]") and not fenced[i] then
      local j = i
      while j <= #lines and not lines[j]:lower():find("</table>", 1, true) do
        j = j + 1
      end
      if j <= #lines then
        local tbl = M.parse_block(vim.list_slice(lines, i, j), i)
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

---Rows of `{ text, colspan, rowspan, align }` from the HTML.
---@param html string
---@return table[][]
local function read_rows(html)
  local rows, row = {}, nil
  local pos = 1
  local cell
  local function close_cell(upto)
    if cell then
      local raw = html:sub(cell.from, upto - 1)
      raw = raw:gsub("<br%s*/?>", "\1"):gsub("<[^>]*>", "")
      raw = decode(raw):gsub("%s+", " "):gsub("\1", "<br>")
      cell.text = vim.trim(raw):gsub("%s*<br>%s*", "<br>")
      row[#row + 1] = cell
      cell = nil
    end
  end
  while true do
    local s, e, closing, name, attrs = html:find("<(/?)(%a+)([^>]*)>", pos)
    if not s then break end
    name = name:lower()
    if name == "tr" then
      close_cell(s)
      if closing == "" then
        row = {}
        rows[#rows + 1] = row
      end
    elseif (name == "td" or name == "th") and closing == "" then
      close_cell(s)
      if not row then
        row = {}
        rows[#rows + 1] = row
      end
      cell = {
        from = e + 1,
        colspan = math.max(1, tonumber(attr(attrs, "colspan") or "") or 1),
        rowspan = math.max(1, tonumber(attr(attrs, "rowspan") or "") or 1),
        align = align_of(attrs),
      }
    elseif (name == "td" or name == "th" or name == "table") and closing == "/" then
      close_cell(s)
    end
    pos = e + 1
  end
  close_cell(#html + 1)
  return rows
end

---@param block string[]
---@param start_line integer
---@return table|nil tbl
function M.parse_block(block, start_line)
  local registry = require("markdown.tables.registry")
  local rows = read_rows(table.concat(block, "\n"))
  if #rows == 0 then return nil end

  -- lay the cells out on the grid, rowspans reserve slots in the rows below
  local grid, spans, taken = {}, {}, {}
  local width = 0
  for r, row in ipairs(rows) do
    grid[r] = grid[r] or {}
    local c = 1
    for _, cell in ipairs(row) do
      while taken[r .. ":" .. c] do
        c = c + 1
      end
      grid[r][c] = cell.text
      if cell.colspan > 1 or cell.rowspan > 1 then
        spans[#spans + 1] = { r = r - 1, c = c, colspan = cell.colspan, rowspan = cell.rowspan }
      end
      for dr = 0, cell.rowspan - 1 do
        for dc = 0, cell.colspan - 1 do
          if dr > 0 or dc > 0 then taken[(r + dr) .. ":" .. (c + dc)] = true end
          grid[r + dr] = grid[r + dr] or {}
          if dr > 0 or dc > 0 then grid[r + dr][c + dc] = grid[r + dr][c + dc] or "" end
        end
      end
      width = math.max(width, c + cell.colspan - 1)
      c = c + cell.colspan
    end
  end
  local out = {}
  for r = 1, #grid do
    out[r] = {}
    for c = 1, width do
      out[r][c] = grid[r][c] or ""
    end
  end
  local header = table.remove(out, 1)

  -- alignment from the first row that sets one in a column
  local aligns = {}
  for _, row in ipairs(rows) do
    local c = 1
    for _, cell in ipairs(row) do
      if cell.align and not aligns[c] then aligns[c] = cell.align end
      c = c + cell.colspan
    end
  end
  for c = 1, width do
    aligns[c] = aligns[c] or "left"
  end

  local tbl = registry.from_strings(header, out, aligns, {
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
  if #spans > 0 then
    tbl.spans = spans
    tbl.lossy = { "merged cells (colspan / rowspan)" }
  end
  return tbl
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local n = #header
  -- `spans` keyed "row:col" (row 0 is the header), kept only while they fit the table
  local by_pos, covered = {}, {}
  for _, s in ipairs(tbl.spans or {}) do
    if s.c + s.colspan - 1 <= n and s.r + s.rowspan - 1 <= #rows then
      by_pos[s.r .. ":" .. s.c] = s
      for dr = 0, s.rowspan - 1 do
        for dc = 0, s.colspan - 1 do
          if dr > 0 or dc > 0 then covered[(s.r + dr) .. ":" .. (s.c + dc)] = true end
        end
      end
    end
  end
  local function cell_tag(tag, r, c, text)
    local a = aligns[c]
    local attrs = {}
    local sp = by_pos[r .. ":" .. c]
    if sp and sp.colspan > 1 then attrs[#attrs + 1] = ('colspan="%d"'):format(sp.colspan) end
    if sp and sp.rowspan > 1 then attrs[#attrs + 1] = ('rowspan="%d"'):format(sp.rowspan) end
    if a and a ~= "left" then attrs[#attrs + 1] = ('style="text-align: %s"'):format(a) end
    return ("<%s%s>%s</%s>"):format(
      tag,
      #attrs > 0 and (" " .. table.concat(attrs, " ")) or "",
      encode(text),
      tag
    )
  end
  local function row_html(tag, r, row)
    local parts = {}
    for c = 1, n do
      if not covered[r .. ":" .. c] then
        parts[#parts + 1] = "    " .. cell_tag(tag, r, c, row[c] or "")
      end
    end
    return { "  <tr>", unpack(parts) }
  end
  local out = { "<table>", "  <thead>" }
  vim.list_extend(out, row_html("th", 0, header))
  out[#out + 1] = "  </tr>"
  out[#out + 1] = "  </thead>"
  out[#out + 1] = "  <tbody>"
  for r, row in ipairs(rows) do
    vim.list_extend(out, row_html("td", r, row))
    out[#out + 1] = "  </tr>"
  end
  out[#out + 1] = "  </tbody>"
  out[#out + 1] = "</table>"
  return out
end

---What a spanning table cannot keep in a format without spans is told by `tbl.lossy`; writing it
---as HTML again keeps everything.
---@return string[]
function M.lossy() return {} end

return M
