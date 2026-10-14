---@module 'markdown.tables.formats.org'
---@brief Org-mode tables: `| a | b |` rows, `|---+---|` rules, optional `<r>` / `<l>` / `<c>` cookie row.
---@description
--- A block of `|` lines is an org table when it has a rule line `|---+---|` (with a `+`,
--- which GFM separators never have), so a one-column org table with a plain `|---|` rule is
--- indistinguishable from GFM and is read as GFM. The first row is the header. A row made only of
--- alignment cookies gives the column alignment and is not data. `#+TBLFM:` lines after
--- the table are not part of it and stay untouched.

local lib_table = require("lib.nvim.markdown.table")

local M = {}

---@param line string
---@return boolean
local function is_rule(line)
  return line:match("^%s*|[-+]+|%s*$") ~= nil and line:find("+", 1, true) ~= nil
end

---A row without its closing pipe (org allows that) gets one, so it splits like the others. A row
---that ends in backslash + pipe is read as an escaped pipe (the GFM reader's rule, shared with
---`split_cells`; org itself has no escape): the pipe stays in the last cell. Rules are not
---tolerated without their closing pipe (`|---+---`).
---@param line string
---@return string
local function close_row(line)
  local t = vim.trim(line)
  if t:sub(-1) ~= "|" then return t .. " |" end
  local bs = 0
  while #t - 1 - bs >= 1 and t:sub(#t - 1 - bs, #t - 1 - bs) == "\\" do
    bs = bs + 1
  end
  return bs % 2 == 1 and (t .. " |") or t
end

---@param line string
---@return string[]|nil aligns
local function cookies(line)
  local cells = lib_table.split_cells(line)
  local out, real = {}, false
  for i, c in ipairs(cells) do
    local t = vim.trim(c)
    local k = t:match("^<([lrc])%d*>$")
    if k then
      real = true
    elseif t == "" then
      k = "l"
    else
      return nil
    end
    out[i] = (k == "r" and "right") or (k == "c" and "center") or "left"
  end
  -- a row of empty cells is a data row, only a real cookie makes it the alignment row
  return (real and #out > 0) and out or nil
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
  local rules_after = {} -- body row index -> a rule follows that row (the header rule is not listed)
  local header_rule, dropped = false, false -- a rule that is stored nowhere is reported as lost
  for _, raw in ipairs(block) do
    local line = is_rule(raw) and raw or close_row(raw)
    if is_rule(line) then
      rules = rules + 1
      if #rows > 1 then
        if rules_after[#rows - 1] then dropped = true end -- two rules in a row
        rules_after[#rows - 1] = true
      elseif #rows == 1 and not header_rule then
        header_rule = true
      else
        dropped = true -- above the header, or a second one under it / under the cookie row
      end
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
  if next(rules_after) then
    tbl.rules_after = rules_after
    tbl.lossy = { "horizontal rules between rows (org row groups)" }
  end
  if dropped then
    -- not kept by any target, org included (reported by every `registry.lossy`)
    tbl.lost = { "a horizontal rule above the header or a repeated one (not stored)" }
  end
  return tbl
end

---A cell as one org line: a newline becomes `<br>`, a pipe that is not escaped yet gets
---escaped (an odd run of backslashes before it already escapes it).
---@param s string
---@return string
local function esc(s)
  s = s:gsub("(\\*)|", function(bs)
    if #bs % 2 == 1 then return bs .. "|" end
    return bs .. "\\|"
  end)
  return (s:gsub("\r?\n", "<br>"))
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local function escape_row(r)
    local out = {}
    for c, v in ipairs(r) do
      out[c] = esc(v)
    end
    return out
  end
  header = escape_row(header)
  for i, r in ipairs(rows) do
    rows[i] = escape_row(r)
  end
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
  local rules_after = tbl.rules_after or {}
  local rule_line = out[2]
  for i, r in ipairs(rows) do
    out[#out + 1] = line(r)
    if rules_after[i] then out[#out + 1] = rule_line end
  end
  return out
end

return M
