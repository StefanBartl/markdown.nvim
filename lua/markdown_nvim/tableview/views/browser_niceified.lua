---@module 'markdown_nvim.tableview.views.browser_niceified'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.tableview.views.browser_niceified]")

local api = vim.api
local parser = require("markdown_nvim.tableview.parser")

local function html_escape(s)
  if s == nil then return "" end
  s = tostring(s)
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  s = s:gsub('"', "&quot;"):gsub("'", "&#39;")
  return s
end

local function build_html(chosen, source)
  local buf = {}
  local function w(s) table.insert(buf, s) end

  w("<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>")
  w("<title>TableView — Preview</title>")
  w([[<style>
    :root{--bg:#f7fafc;--card:#ffffff;--muted:#6b7280;--border:#c4c7cc;--accent:#0f172a;--header-bg:#0f172a;--header-fg:#ffffff;--zebra:#fbfdff;}
    html,body{height:100%;margin:0;background:var(--bg);font-family:Inter,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:var(--accent);}
    .wrap{max-width:1100px;margin:36px auto;padding:18px;}
    .card{background:var(--card);border-radius:10px;box-shadow:0 6px 24px rgba(15,23,42,0.08);overflow:hidden;border:2px solid var(--border);}
    header{padding:14px 18px;border-bottom:1px solid rgba(0,0,0,0.04);display:flex;align-items:center;gap:12px;}
    header h1{font-size:16px;margin:0;font-weight:600;color:var(--header-bg);}
    header .meta{margin-left:auto;font-size:12px;color:var(--muted);}
    .table-wrap{padding:18px;overflow:auto;}
    table{width:100%;border-collapse:separate;border-spacing:0;table-layout:auto;}
    thead th{background:linear-gradient(180deg,var(--header-bg),rgba(0,0,0,0.03));color:var(--header-fg);padding:10px 12px;text-align:left;font-weight:700;border-bottom:3px solid var(--border);font-size:13px;}
    tbody td{padding:10px 12px;border-bottom:1px solid rgba(0,0,0,0.04);vertical-align:top;font-size:13px}
    tbody tr:nth-child(odd){background:var(--zebra)}
    tbody tr:hover{background:rgba(15,23,42,0.03)}
    .caption{padding:12px 18px;border-top:1px solid rgba(0,0,0,0.04);font-size:12px;color:var(--muted);}
  </style>]])
  w("</head><body><div class='wrap'><div class='card'>")
  w("<header><h1>Table Preview</h1>")
  if source and source ~= "" then
    w("<div class='meta'>" .. html_escape(source) .. "</div>")
  end
  w("</header>")
  w("<div class='table-wrap'><table><thead><tr>")
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
  w("</tbody></table></div>")
  w("<div class='caption'><div>Rendered by markdown.nvim TableView.</div>")
  if source and source ~= "" then
    w("<div style='margin-top:6px;color:var(--muted)'>Source: " .. html_escape(source) .. "</div>")
  end
  w("</div></div></div></body></html>")
  return table.concat(buf, "")
end

return function(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)) then
    notify.error("Invalid buffer for browser preview")
    return
  end

  local cur_line = api.nvim_win_get_cursor(0)[1]
  local tables = parser.get_tables(bufnr)
  local chosen = nil
  for _, t in ipairs(tables) do
    if t.start_line <= cur_line and cur_line <= (t.end_line or t.start_line) then
      chosen = t
      break
    end
  end

  if not chosen then
    notify.info("No table under cursor")
    return
  end

  local headers = {}
  for _, c in ipairs(chosen.header.cells or {}) do
    table.insert(headers, c.content or "")
  end
  local source = string.format("col %d; %s", chosen.start_line or 0, table.concat(headers, ", "))

  local html = build_html(chosen, source)
  local tmp = vim.fn.tempname() .. ".html"
  local fh, err = io.open(tmp, "w")
  if not fh then
    notify.error("Failed to write preview file: " .. tostring(err))
    return
  end
  fh:write(html)
  fh:close()

  local esc = vim.fn.shellescape(tmp)
  local sys = vim.loop.os_uname().sysname or ""
  local cmd
  if sys:match("Windows") or sys:match("windows") then
    cmd = string.format('cmd /C start "" %s', esc)
  elseif sys == "Darwin" then
    cmd = string.format("open %s", esc)
  else
    cmd = string.format("xdg-open %s", esc)
  end
  pcall(vim.fn.jobstart, cmd, { detach = true })
end
