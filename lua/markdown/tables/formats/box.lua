---@module 'markdown.tables.formats.box'
---@brief Box-drawing tables (`┌─┬─┐ │ a │ b │ ├─┼─┤ └─┴─┘`), as TableView's box style, psql unicode, sqlite `.mode box`.
---@description
--- The block runs from a top border (`┌` or `╭`) to a bottom border (`└` or `╰`). The lines
--- between two rules form one row; several `│` lines in one group are one row with
--- multi-line cells, joined with `<br>`. The first group is the header. A table with rules
--- between its body rows is written back with them (`row_rules`).

local lib_table = require("lib.nvim.markdown.table")

local M = {}

local TOP = { ["┌"] = true, ["╭"] = true }
local BOTTOM = { ["└"] = true, ["╰"] = true }

---@param line string
---@return string
local function first_char(line) return vim.fn.strcharpart(vim.trim(line), 0, 1) end

---@param line string
---@return string[]
local function split(line)
  local t = vim.trim(line)
  t = t:gsub("^│", ""):gsub("│$", "")
  local out = {}
  for part in (t .. "│"):gmatch("(.-)│") do
    out[#out + 1] = vim.trim(part)
  end
  return out
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if TOP[first_char(lines[i])] and not fenced[i] then
      local j = i + 1
      while j <= #lines and not BOTTOM[first_char(lines[j])] do
        local c = first_char(lines[j])
        -- `├` is a rule between rows, `╞` the header rule TableView draws
        if c ~= "│" and c ~= "├" and c ~= "╞" then break end
        j = j + 1
      end
      if j <= #lines and BOTTOM[first_char(lines[j])] and j - i >= 2 then
        found[#found + 1] = M.parse_block(vim.list_slice(lines, i, j), i)
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
---@return table tbl
function M.parse_block(block, start_line)
  local registry = require("markdown.tables.registry")
  local groups, cur = {}, nil
  for _, line in ipairs(block) do
    local c = first_char(line)
    if c == "│" then
      cur = cur or {}
      cur[#cur + 1] = split(line)
    elseif cur then
      groups[#groups + 1] = cur
      cur = nil
    end
  end
  if cur then groups[#groups + 1] = cur end
  -- Rules between body rows mean "the lines between two rules are one row" (multi-line
  -- cells). With only the rule under the header (what TableView draws) every line is a row.
  local mids = 0
  for _, line in ipairs(block) do
    if first_char(line) == "├" then mids = mids + 1 end
  end
  local function merge(parts_list)
    local merged = {}
    for _, parts in ipairs(parts_list) do
      for c, v in ipairs(parts) do
        if merged[c] and merged[c] ~= "" then
          merged[c] = merged[c] .. (v ~= "" and ("<br>" .. v) or "")
        else
          merged[c] = v
        end
      end
    end
    return merged
  end
  local rows = {}
  if mids <= 1 then
    rows[1] = merge(groups[1] or {})
    for g = 2, #groups do
      for _, parts in ipairs(groups[g]) do
        rows[#rows + 1] = parts
      end
    end
  else
    for _, g in ipairs(groups) do
      rows[#rows + 1] = merge(g)
    end
  end
  local header = table.remove(rows, 1) or {}
  local width = #header
  for _, r in ipairs(rows) do
    width = math.max(width, #r)
  end
  for c = #header + 1, width do
    header[c] = ""
  end
  return registry.from_strings(header, rows, nil, {
    border = first_char(block[1]) == "╭" and "rounded" or "single",
    row_rules = mids > 1, -- rules between the body rows are written back
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
end

---@internal
---@param tbl table
---@return boolean
local function has_br(tbl)
  for _, r in ipairs(tbl.rows) do
    for _, c in ipairs(r.cells) do
      local s = type(c) == "table" and c.content or c
      -- a newline (a multi-line csv field) is a line break in the cell as much as `<br>`
      if type(s) == "string" and (s:find("<br>", 1, true) or s:find("\n", 1, true)) then
        return true
      end
    end
  end
  return false
end

---@param tbl table
---@param opts? { border?: string }
---@return string[]
function M.render(tbl, opts)
  local gfm = require("markdown.tables.formats.gfm").render(tbl)
  -- A multi-line cell (`<br>`) needs a rule between the rows, or the lines read back as rows.
  return require("markdown.core.table_render").to_lines(gfm, {
    border = opts and opts.border or tbl.border or "single",
    row_separator = tbl.row_rules == true or has_br(tbl),
  })
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  -- one body row cannot show where its lines end: no rule separates it from anything
  if #tbl.rows == 1 and has_br(tbl) then
    return { "multi-line cells of a single body row (read back as separate rows)" }
  end
  return {}
end

M._split = split
M._lib = lib_table

return M
