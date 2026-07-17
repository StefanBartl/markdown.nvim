---@module 'markdown_nvim.tableview.views.browser_basic'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.tableview.views.browser_basic]")

local api = vim.api
local parser = require("markdown_nvim.tableview.parser")
local session = require("markdown_nvim.tableview.views.browser_session")

local function html_escape(s)
  if s == nil then return "" end
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  s = s:gsub('"', "&quot;"):gsub("'", "&#39;")
  return s
end

---@param bufnr integer
---@param force_new boolean|nil open a fresh tab even if one is already open
---                              (`reopen` argument — use if it was closed by hand)
return function(bufnr, force_new)
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

  local buf = {}
  local function w(s) buf[#buf + 1] = s end

  w("<!doctype html><html><head><meta charset='utf-8'><title>TableView</title>")
  w("<style>table{border-collapse:collapse;font-family:system-ui,Segoe UI,Roboto,Arial;}th,td{border:1px solid #bbb;padding:6px;text-align:left}</style>")
  w("</head><body><table><thead><tr>")
  for _, c in ipairs(chosen.header.cells) do
    w("<th>" .. html_escape(c.content or "") .. "</th>")
  end
  w("</tr></thead><tbody>")
  for _, r in ipairs(chosen.rows) do
    w("<tr>")
    for _, c in ipairs(r.cells) do
      w("<td>" .. html_escape(c.content or "") .. "</td>")
    end
    w("</tr>")
  end
  w("</tbody></table></body></html>")

  local ok, err = session.show(table.concat(buf), "basic", force_new)
  if not ok then
    notify.error("Failed to open browser preview: " .. tostring(err))
  end
end
