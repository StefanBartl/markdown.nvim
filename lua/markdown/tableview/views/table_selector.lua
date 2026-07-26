---@module 'markdown.tableview.views.table_selector'
local ui = require("markdown.tableview.renderer")
local picker = require("markdown.util.picker")

local function format_item(t)
  local headers = {}
  if t.header and t.header.cells then
    for _, c in ipairs(t.header.cells) do
      table.insert(headers, c.content or "")
    end
  end
  local header_preview = (#headers > 0) and table.concat(headers, ", ") or ("Table@" .. tostring(t.start_line))
  return string.format("col %d; %s (%d rows)", t.start_line or 0, header_preview, #t.rows)
end

return function(tables)
  if not tables or #tables == 0 then return end

  picker.select(tables, {
    prompt = "Markdown tables",
    format = format_item,
  }, function(sel)
    ui.render_table(sel, { floating = true })
  end)
end
