---@module 'markdown.tables.formats.org'
---@brief Org-mode tables: `| a | b |` rows, `|---+---|` rules, optional `<r>` / `<l>` / `<c>` cookie row.
---@description
--- A block of `|` lines is an org table when it has a rule line `|---+---|` (with a `+`,
--- which GFM separators never have). The first row is the header. A row made only of
--- alignment cookies gives the column alignment and is not data. `#+TBLFM:` lines after
--- the table are not part of it and stay untouched.

local lib_table = require("lib.nvim.markdown.table")

local M = {}

---@param line string
---@return boolean
local function is_rule(line)
  return line:match("^%s*|[-+]+|%s*$") ~= nil and line:find("+", 1, true) ~= nil
end

---@param line string
---@return string[]|nil aligns
local function cookies(line)
  local cells = lib_table.split_cells(line)
  local out = {}
  for i, c in ipairs(cells) do
    local t = vim.trim(c)
    local k = t:match("^<([lrc])%d*>$")
    if not k then
      if t == "" then
        k = "l"
      else
        return nil
      end
    end
    out[i] = (k == "r" and "right") or (k == "c" and "center") or "left"
  end
  return #out > 0 and out or nil
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match("^%s*|") and not fenced[i] then
      local j = i
      while j + 1 <= #lines and lines[j + 1]:match("^%s*|") and not fenced[j + 1] do
        j = j + 1
      end
      local has_rule = false
      for k = i, j do
        if is_rule(lines[k]) then has_rule = true end
      end
      if has_rule and j > i then
        found[#found + 1] = M.parse_block(vim.list_slice(lines, i, j), i)
      end
      i = j + 1
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
  local rows, aligns, rules = {}, nil, 0
  for _, line in ipairs(block) do
    if is_rule(line) then
      rules = rules + 1
    else
      local ck = (not aligns) and cookies(line)
      if ck and #rows >= 1 then
        aligns = ck
      else
        local cells = lib_table.split_cells(line)
        for c, v in ipairs(cells) do
          cells[c] = vim.trim(v)
        end
        rows[#rows + 1] = cells
      end
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
  local tbl = registry.from_strings(header, rows, aligns, {
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
  if rules > 1 then tbl.lossy = { "horizontal rules between rows (org row groups)" } end
  return tbl
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local n = #header
  local widths = {}
  local function measure(row)
    for c = 1, n do
      widths[c] = math.max(widths[c] or 1, vim.fn.strdisplaywidth(row[c] or ""))
    end
  end
  measure(header)
  for _, r in ipairs(rows) do
    measure(r)
  end
  local function line(row)
    local out = {}
    for c = 1, n do
      local v = row[c] or ""
      out[c] = v .. (" "):rep(widths[c] - vim.fn.strdisplaywidth(v))
    end
    return "| " .. table.concat(out, " | ") .. " |"
  end
  local rule = {}
  for c = 1, n do
    rule[c] = ("-"):rep(widths[c] + 2)
  end
  local out = { line(header), "|" .. table.concat(rule, "+") .. "|" }
  local has_align = false
  local cook = {}
  for c = 1, n do
    local a = aligns[c] or "left"
    cook[c] = (a == "right" and "<r>") or (a == "center" and "<c>") or ""
    has_align = has_align or cook[c] ~= ""
  end
  if has_align then out[#out + 1] = line(cook) end
  for _, r in ipairs(rows) do
    out[#out + 1] = line(r)
  end
  return out
end

return M
