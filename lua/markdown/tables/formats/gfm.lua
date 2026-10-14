---@module 'markdown.tables.formats.gfm'
---@brief GitHub-flavoured Markdown pipe tables (the format everything else converts through).

local M = {}

---@param lines string[]
---@param opts? { skip_fences?: boolean }
---@return table[]
function M.scan(lines, opts) return require("markdown.tableview.parser").scan_gfm(lines, opts) end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows, aligns = registry.strings(tbl)
  local function esc(s) return (s:gsub("|", "\\|"):gsub("\n", "<br>")) end
  local function row(cells)
    local out = {}
    for i, c in ipairs(cells) do
      out[i] = esc(c)
    end
    return "| " .. table.concat(out, " | ") .. " |"
  end
  local sep = {}
  for c = 1, #header do
    local a = aligns[c] or "left"
    sep[c] = (a == "center" and ":---:") or (a == "right" and "---:") or "---"
  end
  local lines = { row(header), "| " .. table.concat(sep, " | ") .. " |" }
  for _, r in ipairs(rows) do
    local cells = {}
    for c = 1, #header do
      cells[c] = r[c] or ""
    end
    lines[#lines + 1] = row(cells)
  end
  return require("lib.nvim.markdown.table").format_lines(lines)
end

return M
