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
  view   = do_view,
  format = do_format,
  new    = do_new,
}

---@param argv string[]
function M.run(argv)
  argv = argv or {}
  local sub = argv[1]
  local fn = sub and subcommands[sub]
  if not fn then
    notify.info("Usage: :Markdown table <view|format|new> ...")
    return
  end
  table.remove(argv, 1)
  fn(argv)
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

  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
