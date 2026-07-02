---@module 'markdown_nvim.tableview.views.browser_basic'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.tableview.views.browser_basic]")

local api = vim.api
local parser = require("markdown_nvim.tableview.parser")

local function html_escape(s)
  if s == nil then return "" end
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  s = s:gsub('"', "&quot;"):gsub("'", "&#39;")
  return s
end

return function(bufnr)
  local line = api.nvim_win_get_cursor(0)[1]
  local tables = parser.get_tables(bufnr)
  local chosen = nil
  for _, t in ipairs(tables) do
    if t.start_line <= line and line <= (t.end_line or t.start_line) then
      chosen = t
      break
    end
  end
  if not chosen then
    notify.info("No table under cursor")
    return
  end

  local tmp = vim.fn.tempname() .. ".html"
  local fh = io.open(tmp, "w")
  if not fh then
    notify.error("Failed to create temp file for browser preview")
    return
  end

  fh:write("<!doctype html><html><head><meta charset='utf-8'><title>TableView</title>")
  fh:write("<style>table{border-collapse:collapse;font-family:system-ui,Segoe UI,Roboto,Arial;}th,td{border:1px solid #bbb;padding:6px;text-align:left}</style>")
  fh:write("</head><body><table><thead><tr>")
  for _, c in ipairs(chosen.header.cells) do
    fh:write("<th>" .. html_escape(c.content or "") .. "</th>")
  end
  fh:write("</tr></thead><tbody>")
  for _, r in ipairs(chosen.rows) do
    fh:write("<tr>")
    for _, c in ipairs(r.cells) do
      fh:write("<td>" .. html_escape(c.content or "") .. "</td>")
    end
    fh:write("</tr>")
  end
  fh:write("</tbody></table></body></html>")
  fh:close()

  local ok, err = require("markdown_nvim.util.platform").open(tmp)
  if not ok then
    notify.error("Failed to open browser preview: " .. tostring(err))
  end
end
