---@module 'markdown.tables.formats.latex'
---@brief LaTeX `tabular`: `\begin{tabular}{lr}`, rows `a & b \\`, `\hline`, `\end{tabular}`.
---@description
--- A table runs from `\begin{tabular}{spec}` to `\end{tabular}`. Rules (`\hline`, `\toprule`,
--- `\midrule`, `\bottomrule`, `\cline{..}`) and `%` comments are dropped; rows end at `\\`, cells
--- at an unescaped `&`. The column spec gives the alignment (`l`, `c`, `r`; `p{..}` reads as left).
--- The first row is the header. `\&`, `\%`, `\$`, `\#`, `\_`, `\{`, `\}` and `\textbackslash{}` are
--- unescaped in the cells and escaped again when written. A table with `\multicolumn` or
--- `\multirow` is left alone (those cells cannot be shown in a plain grid).

local M = {}

local RULES = { "\\hline", "\\toprule", "\\midrule", "\\bottomrule" }

local UNESCAPE = {
  ["&"] = "&",
  ["%"] = "%",
  ["$"] = "$",
  ["#"] = "#",
  ["_"] = "_",
  ["{"] = "{",
  ["}"] = "}",
}

---A line without its comment (`%` that is not escaped, to the end).
---@param line string
---@return string
local function strip_comment(line)
  local i = 1
  while i <= #line do
    local ch = line:sub(i, i)
    if ch == "\\" then
      i = i + 1
    elseif ch == "%" then
      return line:sub(1, i - 1)
    end
    i = i + 1
  end
  return line
end

---Alignments from a column spec such as `|l|c|r|`, `lp{3cm}r` or `*{3}{c}`.
---@param spec string
---@return string[]
local function alignments(spec)
  -- `*{3}{c|}` is three times `c|`
  spec = spec:gsub(
    "%*%s*{(%d+)}%s*(%b{})",
    function(n, body) return body:sub(2, -2):rep(math.min(tonumber(n) or 1, 200)) end
  )
  local out = {}
  local i = 1
  while i <= #spec do
    local ch = spec:sub(i, i)
    if ch == "l" or ch == "c" or ch == "r" then
      out[#out + 1] = (ch == "l" and "left") or (ch == "c" and "center") or "right"
    elseif ch == "p" or ch == "m" or ch == "b" then
      out[#out + 1] = "left"
      if spec:sub(i + 1, i + 1) == "{" then
        local close = spec:find("}", i + 2, true)
        if close then i = close end
      end
    elseif ch == "@" or ch == ">" or ch == "<" then
      if spec:sub(i + 1, i + 1) == "{" then
        local close = spec:find("}", i + 2, true)
        if close then i = close end
      end
    end
    i = i + 1
  end
  return out
end

---The text of a row/cell run with LaTeX escapes undone.
---@param s string
---@return string
local function unescape(s)
  s = s:gsub("\\textbackslash%s*{}", "\1")
  s = s:gsub("\\textasciitilde%s*{}", "~")
  s = s:gsub("\\textasciicircum%s*{}", "^")
  s = s:gsub("%s*\\newline%s*", "<br>")
  s = s:gsub("\\(.)", function(ch) return UNESCAPE[ch] or ("\\" .. ch) end)
  return (s:gsub("\1", "\\"))
end

---Split the body of a tabular into rows of cells.
---@param body string
---@return string[][] rows
local function rows_of(body)
  local rows, row, cell = {}, {}, {}
  local i, n = 1, #body
  local function push_cell()
    row[#row + 1] = unescape(vim.trim(table.concat(cell)))
    cell = {}
  end
  local function push_row()
    push_cell()
    local blank = #row == 1 and row[1] == ""
    if not blank then rows[#rows + 1] = row end
    row = {}
  end
  while i <= n do
    local ch = body:sub(i, i)
    if ch == "\\" then
      local nxt = body:sub(i + 1, i + 1)
      if nxt == "\\" then
        push_row()
        i = i + 1
        -- a row's extra space, `\\[2pt]`
        local extra = body:match("^%[[^%]\n]*%]", i + 1)
        if extra then i = i + #extra end
      else
        cell[#cell + 1] = ch .. nxt
        i = i + 1
      end
    elseif ch == "&" then
      push_cell()
    elseif ch == "%" then
      local eol = body:find("\n", i, true) or n
      i = eol
    else
      cell[#cell + 1] = ch == "\n" and " " or ch
    end
    i = i + 1
  end
  if #cell > 0 or #row > 0 then push_row() end
  return rows
end

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts)
  local fenced = (opts and opts.skip_fences) and require("markdown.util.fence").mask(lines) or {}
  local found = {}
  local i = 1
  while i <= #lines do
    -- The table must start a line and end one: the lines are replaced as a whole when converting,
    -- so a `\resizebox{..}{!}{` before it or a closing `}` after it would be lost (and a mention in
    -- a sentence or code span is no table). Comments are not looked into.
    if strip_comment(lines[i]):find("^%s*\\begin{tabular}") and not fenced[i] then
      local j, depth, nested = i, 0, false
      while j <= #lines and not fenced[j] do
        local code = strip_comment(lines[j])
        for _ in code:gmatch("\\begin{tabular}") do
          depth = depth + 1
          if depth > 1 then nested = true end
        end
        for _ in code:gmatch("\\end{tabular}") do
          depth = depth - 1
        end
        if depth <= 0 then break end
        j = j + 1
      end
      local closed = j <= #lines
        and not fenced[j]
        and depth == 0
        and strip_comment(lines[j]):find("\\end{tabular}%s*$") ~= nil
      if closed then
        -- (a tabular inside a cell is left alone: its end is not the end of this one)
        local tbl = (not nested) and M.parse_block(vim.list_slice(lines, i, j), i) or nil
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
  local stripped = {}
  for k, line in ipairs(block) do
    stripped[k] = strip_comment(line)
  end
  local text = table.concat(stripped, "\n")
  local start_at = text:find("\\begin{tabular}", 1, true)
  if not start_at then return nil end
  -- (`%b{}` keeps a nested brace such as `p{3cm}` together; `[t]` is the vertical position)
  local spec_group, after =
    text:match("^%s*%[?[tbc]?%]?%s*(%b{})()", start_at + #"\\begin{tabular}")
  local spec = spec_group and spec_group:sub(2, -2)
  local stop = text:find("\\end{tabular}", after or 1, true)
  if not spec or not stop then return nil end
  local body = text:sub(after, stop - 1)
  if body:find("\\multicolumn", 1, true) or body:find("\\multirow", 1, true) then return nil end
  for _, rule in ipairs(RULES) do
    -- (`\toprule[1pt]` has an optional width)
    body = body:gsub(vim.pesc(rule) .. "%s*%[[^%]\n]*%]", ""):gsub(vim.pesc(rule), "")
  end
  body = body:gsub("\\cline%s*%b{}", "")
  local rows = rows_of(body)
  if #rows == 0 then return nil end
  local header = table.remove(rows, 1)
  local width = #header
  for _, r in ipairs(rows) do
    width = math.max(width, #r)
  end
  for c = #header + 1, width do
    header[c] = ""
  end
  local aligns = alignments(spec)
  return registry.from_strings(header, rows, #aligns > 0 and aligns or nil, {
    start_line = start_line,
    end_line = start_line + #block - 1,
    raw_lines = block,
  })
end

---@param s string
---@return string
local function esc(s, tbl)
  s = require("markdown.tables.slice").plain(s, tbl)
  s = s:gsub("\\", "\1")
  s = s:gsub("([&%%$#_{}])", "\\%1")
  s = s:gsub("~", "\\textasciitilde{}"):gsub("%^", "\\textasciicircum{}")
  s = s:gsub("<br>", " \\newline ")
  return (s:gsub("\1", "\\textbackslash{}"))
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local n = #header
  local spec = {}
  for c = 1, n do
    local a = aligns[c] or "left"
    spec[c] = (a == "right" and "r") or (a == "center" and "c") or "l"
  end
  local function line(row)
    local out = {}
    for c = 1, n do
      out[c] = esc(row[c] or "", tbl)
    end
    return table.concat(out, " & ") .. " \\\\"
  end
  local out =
    { "\\begin{tabular}{" .. table.concat(spec) .. "}", "\\hline", line(header), "\\hline" }
  for _, r in ipairs(rows) do
    out[#out + 1] = line(r)
  end
  out[#out + 1] = "\\hline"
  out[#out + 1] = "\\end{tabular}"
  return out
end

return M
