---@module 'markdown.tables.formats.tsv'
---@brief Tab-separated values: `formats.csv` with a tab.

local csv = require("markdown.tables.formats.csv")

local M = {}

---@param lines string[]
---@return table|nil tbl, string|nil err
function M.parse(lines) return csv.parse(lines, { sep = "\t" }) end

---@param tbl table
---@return string[]
function M.render(tbl) return csv.render(tbl, { sep = "\t" }) end

M.lossy = csv.lossy

return M
