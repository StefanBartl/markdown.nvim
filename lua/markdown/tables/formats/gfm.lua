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
  -- a pipe that is already escaped (an odd run of backslashes before it) stays as it is
  local function esc(s)
    s = s:gsub("(\\*)|", function(bs)
      if #bs % 2 == 1 then return bs .. "|" end
      return bs .. "\\|"
    end)
    return (s:gsub("\n", "<br>"))
  end
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
  local out = require("lib.nvim.markdown.table").format_lines(lines)
  -- format_lines pads the separator with plain dashes: put the alignment colons back
  if out[2] then
    local inner = out[2]:match("^|(.*)|$")
    if inner then
      local cells, c = {}, 0
      for cell in (inner .. "|"):gmatch("([^|]*)|") do
        c = c + 1
        local w = #vim.trim(cell)
        local a = aligns[c] or "left"
        local mark
        if a == "center" then
          mark = ":" .. ("-"):rep(math.max(w - 2, 1)) .. ":"
        elseif a == "right" then
          mark = ("-"):rep(math.max(w - 1, 1)) .. ":"
        else
          mark = ("-"):rep(math.max(w, 1))
        end
        cells[c] = " " .. mark .. " "
      end
      out[2] = "|" .. table.concat(cells, "|") .. "|"
    end
  end
  return out
end

return M
