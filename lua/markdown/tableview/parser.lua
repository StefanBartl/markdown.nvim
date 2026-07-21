---@module 'markdown.tableview.parser'
local M = {}

local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$")
end

local function parse_alignment(token)
  if not token then return "left" end
  token = trim(token)
  if token:match("^:%-+:$") then return "center"
  elseif token:match("^:%-+$") then return "left"
  elseif token:match("^-+:$") then return "right"
  else return "left" end
end

local function parse_row(line)
  local cells = {}
  line = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  for cell in line:gmatch("([^|]+)") do
    table.insert(cells, { content = trim(cell) })
  end
  return cells
end

local function is_separator_row(line)
  if not line then return false end
  local s = trim(line)
  if not s:match("-") then return false end
  return s:match("^|?%s*[:%-|%s]+%s*|?$") ~= nil
end

function M.parse_table(lines, start_line)
  if not lines or #lines < 2 then return nil end

  local header_line = lines[1]
  local sep_line = lines[2]
  if not is_separator_row(sep_line) then return nil end

  local tbl = {
    header = nil,
    alignments = {},
    rows = {},
    start_line = start_line,
    end_line = start_line,
  }

  tbl.header = { cells = parse_row(header_line) }

  local align_cells = parse_row(sep_line)
  for i, ac in ipairs(align_cells) do
    local token = ac.content or ac
    tbl.alignments[i] = parse_alignment(token)
  end

  for idx = 3, #lines do
    local l = lines[idx]
    if not l then break end
    if l:match("|") then
      table.insert(tbl.rows, { cells = parse_row(l) })
      tbl.end_line = start_line + idx - 1
    else
      break
    end
  end

  return tbl
end

--- Parse every GFM table out of a plain list of lines. Pure (no buffer or file
--- I/O), so it works equally for a live buffer's lines and a file read from
--- disk via `vim.fn.readfile`.
---@param lines string[]
---@return table[]
function M.get_tables_from_lines(lines)
  local tables = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line and line:match("|") and (i + 1) <= #lines and is_separator_row(lines[i + 1]) then
      local tbl_lines = { lines[i], lines[i + 1] }
      local j = i + 2
      while j <= #lines and lines[j] and lines[j]:match("|") do
        table.insert(tbl_lines, lines[j])
        j = j + 1
      end
      local parsed = M.parse_table(tbl_lines, i)
      if parsed then
        table.insert(tables, parsed)
        i = parsed.end_line + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  return tables
end

function M.get_tables(bufnr)
  bufnr = bufnr or 0
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok or not lines then return {} end
  return M.get_tables_from_lines(lines)
end

--- Parse every GFM table in a file on disk (no buffer needed — used for the
--- `%`/path/`cwd` TableView scopes reading files that are not open). Each
--- returned table additionally carries `.source = path`, so callers can label
--- which file a table came from when aggregating across several files.
---@param path string
---@return table[]
function M.get_tables_from_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return {} end
  local tables = M.get_tables_from_lines(lines)
  for _, t in ipairs(tables) do t.source = path end
  return tables
end

return M
