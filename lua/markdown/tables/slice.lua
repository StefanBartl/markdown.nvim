---@module 'markdown.tables.slice'
---@brief Cut a text line into cells at display columns (fixed-width table formats).
---@description
--- Grid, psql and RST simple tables are drawn on a character grid: where a cell starts and ends
--- is a screen column, not a byte offset, so a cell with wide or multi-byte characters must be
--- cut by display width.

local M = {}

---The text of each column range of `line`, trimmed.
---@param line string
---@param ranges { from: integer, to?: integer }[]  # 0-based display columns, `to` exclusive (nil = rest of the line)
---@return string[] cells
function M.cells(line, ranges)
  local chars = vim.fn.split(line, "\\zs")
  local starts, col = {}, 0
  for i, ch in ipairs(chars) do
    starts[i] = col
    col = col + vim.fn.strdisplaywidth(ch)
  end
  local out = {}
  for k, r in ipairs(ranges) do
    local buf = {}
    for i, ch in ipairs(chars) do
      local s = starts[i]
      if s >= r.from and (r.to == nil or s < r.to) then buf[#buf + 1] = ch end
    end
    out[k] = vim.trim(table.concat(buf))
  end
  return out
end

---The character that covers display column `col` (0-based), or "" past the end.
---@param line string
---@param col integer
---@return string
function M.char_at(line, col)
  local pos = 0
  for _, ch in ipairs(vim.fn.split(line, "\\zs")) do
    local w = vim.fn.strdisplaywidth(ch)
    if col >= pos and col < pos + math.max(w, 1) then return ch end
    pos = pos + w
  end
  return ""
end

---`text` padded with blanks to `width` display columns.
---@param text string
---@param width integer
---@param align? "left"|"right"|"center"
---@return string
function M.pad(text, width, align)
  local gap = math.max(0, width - vim.fn.strdisplaywidth(text))
  if align == "right" then return (" "):rep(gap) .. text end
  if align == "center" then
    local left = math.floor(gap / 2)
    return (" "):rep(left) .. text .. (" "):rep(gap - left)
  end
  return text .. (" "):rep(gap)
end

---Split a cell's text into its lines (`<br>` and newlines end a line).
---@param s string
---@return string[]
function M.lines_of(s)
  local out = {}
  for part in (s:gsub("<br%s*/?>", "\n") .. "\n"):gmatch("(.-)\r?\n") do
    out[#out + 1] = vim.trim(part)
  end
  if #out == 0 then out[1] = "" end
  return out
end

---Cell text for a format that has no escape for a pipe: an escaped pipe (`\|`, GFM / org cell text)
---is a plain pipe in the data, and a newline is a line break. Not for a table read from csv / tsv,
---where `\|` is a literal backslash and a pipe (same rule as `csv.render`).
---@param s string
---@param tbl table
---@return string
function M.plain(s, tbl)
  if tbl.format ~= "csv" and tbl.format ~= "tsv" then
    s = s:gsub("(\\*)|", function(bs)
      if #bs % 2 == 1 then return bs:sub(1, -2) .. "|" end
      return bs .. "|"
    end)
  end
  return (s:gsub("\r?\n", "<br>"))
end

return M
