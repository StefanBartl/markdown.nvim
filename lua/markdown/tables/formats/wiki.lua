---@module 'markdown.tables.formats.wiki'
---@brief MediaWiki tables: `{| class="wikitable"`, `|-` rows, `! a !! b` header cells, `| a || b` cells, `|}`.
---@description
--- A table runs from a `{|` line to the `|}` line. The row with `!` cells is the header (without
--- one, the first row is). A cell may have attributes before a single `|` (`style="x" | text`):
--- they are dropped and reported. A line that starts with neither `|` nor `!` continues the
--- cell above (joined with `<br>`). `{{!}}` is a pipe in a cell. A caption (`|+`) is kept as
--- `caption` and written back by this format only.

local M = {}

---@param s string
---@return string
local function unescape(s) return (s:gsub("{{!}}", "|")) end

---Split a cell line on the separator, dropping `attrs |` in front of a cell.
---@param body string  # the line without its leading `|` / `!`
---@param sep string   # "||" or "!!"
---@return string[] cells
---@return boolean attrs  # a cell had attributes
local function split_cells(body, sep)
  local cells, attrs = {}, false
  local pos = 1
  while true do
    local s, e = body:find(sep, pos, true)
    local part = body:sub(pos, (s or #body + 1) - 1)
    local a, text = part:match("^([^|]-=[^|]*)|%s*(.*)$")
    if a and not part:find("||", 1, true) then
      attrs, part = true, text
    end
    cells[#cells + 1] = unescape(vim.trim(part))
    if not s then break end
    pos = e + 1
  end
  return cells, attrs
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if vim.trim(lines[i]):sub(1, 2) == "{|" and not fenced[i] then
      local j = i + 1
      while j <= #lines and not fenced[j] and vim.trim(lines[j]):sub(1, 2) ~= "|}" do
        j = j + 1
      end
      if j <= #lines and not fenced[j] then
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

---@param block string[]
---@param start_line integer
---@return table|nil tbl
function M.parse_block(block, start_line)
  local registry = require("markdown.tables.registry")
  local rows, header_row, caption, dropped = {}, nil, nil, false
  local cur, last_cell = nil, nil
  local function new_row()
    cur = {}
    rows[#rows + 1] = cur
    last_cell = nil
  end
  for k = 2, #block - 1 do
    local line = vim.trim(block[k])
    local head = line:sub(1, 2)
    if head == "|-" then
      cur = nil
    elseif head == "|+" then
      caption = vim.trim(line:sub(3))
    elseif line:sub(1, 1) == "!" or line:sub(1, 1) == "|" then
      if not cur then new_row() end
      local is_header = line:sub(1, 1) == "!"
      local cells, attrs = split_cells(line:sub(2), is_header and "!!" or "||")
      if is_header and line:find("||", 1, true) then
        cells, attrs = split_cells(line:sub(2), "||")
      end
      dropped = dropped or attrs
      if is_header and not header_row and #cur == 0 then header_row = #rows end
      for _, c in ipairs(cells) do
        cur[#cur + 1] = c
      end
      last_cell = #cur
    elseif line ~= "" and cur and last_cell then
      cur[last_cell] = (cur[last_cell] ~= "" and (cur[last_cell] .. "<br>") or "") .. unescape(line)
    end
  end
  -- drop rows without cells (a `|-` before the closing `|}`)
  local kept = {}
  for r, row in ipairs(rows) do
    if #row > 0 then
      kept[#kept + 1] = row
    elseif header_row and r < header_row then
      header_row = header_row - 1
    end
  end
  rows = kept
  if #rows == 0 then return nil end
  local header = table.remove(rows, (header_row and header_row <= #rows + 1) and header_row or 1)
  local width = #header
  for _, r in ipairs(rows) do
    width = math.max(width, #r)
  end
  for c = #header + 1, width do
    header[c] = ""
  end
  local tbl = registry.from_strings(header, rows, nil, {
    caption = caption ~= "" and caption or nil,
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
  if dropped then tbl.lost = { "cell attributes (style, colspan, rowspan)" } end
  return tbl
end

---@param s string
---@return string
local function esc(s)
  s = s:gsub("|", "{{!}}")
  return s
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local function cells(row, sep)
    local out = {}
    for c = 1, #header do
      out[c] = esc(row[c] or "")
    end
    return table.concat(out, sep)
  end
  local out = { '{| class="wikitable"' }
  if tbl.caption then out[#out + 1] = "|+ " .. tbl.caption end
  out[#out + 1] = "|-"
  out[#out + 1] = "! " .. cells(header, " !! ")
  for _, r in ipairs(rows) do
    out[#out + 1] = "|-"
    out[#out + 1] = "| " .. cells(r, " || ")
  end
  out[#out + 1] = "|}"
  return out
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  for _, a in ipairs(tbl.alignments or {}) do
    if a ~= "left" then return { "column alignment" } end
  end
  return {}
end

return M
