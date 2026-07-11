---@module 'markdown_nvim.commands.table'
--- `:Markdown table <sub>` router.
---   view   [toggle|select|close|browser|browsernice]   TableView actions
---   format [ALIGN] [header=A] [cell=A] [skip=COL] [scope=cursor|buffer|cwd|PATH]
---   new    [cols] [rows]                                Insert an empty table
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.commands.table]")

local M = {}

-- ---------------------------------------------------------------------------
-- view  (delegates to the buffer-local TableView* user commands)
-- ---------------------------------------------------------------------------

local VIEW_ACTIONS = {
  toggle      = "TableViewToggle",
  select      = "TableViewSelect",
  close       = "TableViewClose",
  browser     = "TableViewOpenBrowser",
  browsernice = "TableViewOpenBrowserNice",
}

local function do_view(argv)
  local action = (argv[1] or "toggle"):lower()
  local cmd = VIEW_ACTIONS[action]
  if not cmd then
    notify.warn("table view: unknown action '" .. action .. "'")
    return
  end
  if vim.fn.exists(":" .. cmd) ~= 2 then
    notify.warn("table view: " .. cmd .. " not available (open a markdown buffer first)")
    return
  end
  vim.cmd(cmd)
end

-- ---------------------------------------------------------------------------
-- format  (table_fmt)
-- ---------------------------------------------------------------------------

local function do_format(argv)
  local fmt = require("markdown_nvim.core.table_fmt")
  local opts, err = fmt.parse_args(argv)
  if err then
    notify.error("table format: " .. err)
    return
  end

  local scope = opts.scope or "cursor"
  local ok, ferr
  if scope == "cursor" then
    ok, ferr = fmt.format_table_at_cursor(vim.api.nvim_get_current_buf(), opts)
    if ok then notify.info("Table formatted") end
  else
    ok, ferr = fmt.format_tables_in_scope(opts)
  end

  if not ok then
    notify.warn("table format: " .. (ferr or "unknown error"))
  end
end

-- ---------------------------------------------------------------------------
-- new  (insert an empty GFM table template)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- mode  (per-buffer auto-format, vim-table-mode style)
-- ---------------------------------------------------------------------------

local function do_mode(argv)
  local tm = require("markdown_nvim.core.table_mode")
  local action = (argv[1] or "toggle"):lower()
  local bufnr = vim.api.nvim_get_current_buf()
  if action == "on" then
    tm.enable(bufnr); notify.info("Table mode: on")
  elseif action == "off" then
    tm.disable(bufnr); notify.info("Table mode: off")
  elseif action == "toggle" then
    notify.info("Table mode: " .. (tm.toggle(bufnr) and "on" or "off"))
  else
    notify.warn("table mode: expected on|off|toggle")
  end
end

-- ---------------------------------------------------------------------------
-- tableize  (delimited text -> GFM table)
-- ---------------------------------------------------------------------------

local function do_tableize(argv, ctx)
  local tm = require("markdown_nvim.core.table_mode")
  local bufnr = vim.api.nvim_get_current_buf()

  -- Use the command's range when given (:'<,'> or :N,M), else the current line.
  local line1, line2
  if ctx and ctx.range and ctx.range > 0 then
    line1, line2 = ctx.line1, ctx.line2
  else
    line1 = vim.api.nvim_win_get_cursor(0)[1]
    line2 = line1
  end

  local delim = argv[1] -- optional explicit delimiter ("," / ";" / "tab" / …)
  local ok, err = tm.tableize(bufnr, line1, line2, delim)
  if ok then notify.info("Tableized " .. (line2 - line1 + 1) .. " line(s)")
  else notify.warn(err or "tableize failed") end
end

local function do_new(argv)
  local cols = math.max(1, tonumber(argv[1] or 2) or 2)
  local rows = math.max(1, tonumber(argv[2] or 2) or 2)

  local function row(fill)
    local cells = {}
    for c = 1, cols do cells[c] = fill(c) end
    return "| " .. table.concat(cells, " | ") .. " |"
  end

  local lines = {}
  lines[#lines + 1] = row(function(c) return "Column " .. c end)
  lines[#lines + 1] = row(function() return "---" end)
  for _ = 1, rows do
    lines[#lines + 1] = row(function() return "" end)
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(bufnr, cur, cur, false, lines)
  notify.info(string.format("Inserted %dx%d table template", cols, rows))
end

-- ---------------------------------------------------------------------------
-- dispatch
-- ---------------------------------------------------------------------------

local subcommands = {
  view     = do_view,
  format   = do_format,
  new      = do_new,
  mode     = do_mode,
  tableize = do_tableize,
}

---@param argv string[]
---@param ctx? table  forwarded command context (range/line1/line2)
function M.run(argv, ctx)
  argv = argv or {}
  local sub = argv[1]
  local fn = sub and subcommands[sub]
  if not fn then
    notify.info("Usage: :Markdown table <view|format|new|mode|tableize> ...")
    return
  end
  table.remove(argv, 1)
  fn(argv, ctx)
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  -- Are we completing the sub-subcommand or its arguments?
  local tokens = vim.split(vim.trim(cmdline), "%s+")
  -- tokens: Markdown, table, <sub>, <args...>
  local sub = tokens[3]
  local on_args = #tokens > 3 or (#tokens == 3 and arglead == "")

  if sub == "format" and on_args then
    return require("markdown_nvim.core.table_fmt").complete(arglead)
  end
  if sub == "view" and on_args then
    local out = {}
    for name in pairs(VIEW_ACTIONS) do
      if vim.startswith(name, arglead) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
  end
  if sub == "mode" and on_args then
    local out = {}
    for _, name in ipairs({ "on", "off", "toggle" }) do
      if vim.startswith(name, arglead) then out[#out + 1] = name end
    end
    return out
  end

  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
