---@module 'markdown.tables.formats.tsv'
---@brief Tab-separated values: `formats.csv` with a tab.

local csv = require("markdown.tables.formats.csv")

local M = {}

---@param lines string[]
---@return table|nil tbl, string|nil err
function M.parse(lines)
  local saved = csv.sep
  csv.sep = "\t"
  local ok, tbl, err = pcall(csv.parse, lines)
  csv.sep = saved
  if not ok then return nil, tbl end
  return tbl, err
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local saved = csv.sep
  csv.sep = "\t"
  local ok, out = pcall(csv.render, tbl)
  csv.sep = saved
  if not ok then error(out) end
  return out
end

M.lossy = csv.lossy

return M
