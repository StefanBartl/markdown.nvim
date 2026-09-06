---@module 'markdown.commands.table'
--- `:Markdown table <sub>` router.
---   view     [toggle|markdown|box|select|close|browser|browsernice]  TableView actions
---   format   [ALIGN] [header=A] [cell=A] [skip=COL] [scope=cursor|buffer|cwd|PATH]
---   new      [cols] [rows]                              Insert an empty table
---   mode     [on|off|toggle]                            Per-buffer auto-format mode
---   tableize [format]                                   Delimited text -> GFM table
---   import [clipboard|PATH]     Parse an HTML <table> into a GFM table (round-
---                               trip with the TableView "open in browser" export).
---                               No arg: whole buffer, or the given range if any.
local notify = require("markdown.util.notify").create("[markdown.commands.table]")

local M = {}

-- ---------------------------------------------------------------------------
-- view  (delegates to the buffer-local TableView* user commands)
-- ---------------------------------------------------------------------------

local VIEW_ACTIONS = {
  toggle = "TableViewToggle",
  markdown = "TableViewMarkdown",
  box = "TableViewBox",
  select = "TableViewSelect",
  close = "TableViewClose",
  browser = "TableViewOpenBrowser",
  browsernice = "TableViewOpenBrowserNice",
}

---@internal
---@param argv string[]
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
  -- Forward any remaining argument (e.g. the `%` scope for toggle/markdown/box)
  -- to the buffer-local command: `:Markdown table view toggle %` -> `:TableViewToggle %`.
  local rest = {}
  for i = 2, #argv do
    rest[#rest + 1] = argv[i]
  end
  if #rest > 0 then
    vim.cmd(cmd .. " " .. table.concat(rest, " "))
  else
    vim.cmd(cmd)
  end
end

-- ---------------------------------------------------------------------------
-- format  (table_fmt)
-- ---------------------------------------------------------------------------

---@internal
---@param argv string[]
local function do_format(argv)
  local fmt = require("markdown.core.table_fmt")
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

  if not ok then notify.warn("table format: " .. (ferr or "unknown error")) end
end

-- ---------------------------------------------------------------------------
-- new  (insert an empty GFM table template)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- mode  (per-buffer auto-format, vim-table-mode style)
-- ---------------------------------------------------------------------------

---@internal
---@param argv string[]
local function do_mode(argv)
  local tm = require("markdown.core.table_mode")
  local action = (argv[1] or "toggle"):lower()
  local bufnr = vim.api.nvim_get_current_buf()
  if action == "on" then
    tm.enable(bufnr)
    notify.info("Table mode: on")
  elseif action == "off" then
    tm.disable(bufnr)
    notify.info("Table mode: off")
  elseif action == "toggle" then
    notify.info("Table mode: " .. (tm.toggle(bufnr) and "on" or "off"))
  else
    notify.warn("table mode: expected on|off|toggle")
  end
end

-- ---------------------------------------------------------------------------
-- tableize  (delimited text -> GFM table)
-- ---------------------------------------------------------------------------

--- Recover the separator argument as typed. `fargs` splits (and mangles) quoted
--- tokens, so a literal space in `:Markdown table tableize " "` is lost there;
--- when the full raw arg string is available (ctx.args) we take everything after
--- the `table tableize` path instead, preserving quotes. Falls back to argv[1].
---@param argv string[]
---@param ctx? table
---@return string|nil
---@internal
local function tableize_sep(argv, ctx)
  local raw = ctx and ctx.args
  if type(raw) == "string" then
    -- Strip the two leading path tokens ("table" "tableize"); keep the rest
    -- verbatim (quotes intact). resolve_delim/clean_spec handle the quoting.
    local rest = vim.trim((raw:gsub("^%s*%S+%s+%S+%s*", "")))
    if rest ~= "" then return rest end -- a literal space is passed quoted: `" "`
    return nil
  end
  return argv[1]
end

---@internal
---@param argv string[]
---@param ctx? table
local function do_tableize(argv, ctx)
  local tm = require("markdown.core.table_mode")
  local bufnr = vim.api.nvim_get_current_buf()

  -- Use the command's range when given (:'<,'> or :N,M), else the current line.
  local line1, line2
  if ctx and ctx.range and ctx.range > 0 then
    line1, line2 = ctx.line1, ctx.line2
  else
    line1 = vim.api.nvim_win_get_cursor(0)[1]
    line2 = line1
  end

  -- Optional separator: a format name (csv/tsv/psv/space/spaces/…), a bare
  -- punctuation char, or a quoted literal such as `" "`. nil = auto-detect.
  local delim = tableize_sep(argv, ctx)
  local ok, err = tm.tableize(bufnr, line1, line2, delim)
  if ok then
    notify.info("Tableized " .. (line2 - line1 + 1) .. " line(s)")
  else
    notify.warn(err or "tableize failed")
  end
end

-- ---------------------------------------------------------------------------
-- import  (HTML <table> -> GFM table; round-trip with the TableView browser export)
-- ---------------------------------------------------------------------------

--- Read the HTML source for `:Markdown table import [clipboard|PATH]`:
---   clipboard        — the "+"" register
---   PATH              — a file on disk
---   (nothing, ranged) — the given line range in the current buffer
---   (nothing)         — the whole current buffer
---@param source? string
---@param ctx? table
---@return string|nil html, string|nil err
---@internal
local function read_html_source(source, ctx)
  if source == "clipboard" then
    return table.concat(vim.fn.getreg("+", 1, true), "\n"), nil
  elseif source and source ~= "" then
    local path = vim.fn.expand(source)
    if vim.fn.filereadable(path) == 0 then
      return nil, string.format("File not readable: %q", path)
    end
    return table.concat(vim.fn.readfile(path), "\n"), nil
  elseif ctx and ctx.range and ctx.range > 0 then
    return table.concat(vim.api.nvim_buf_get_lines(0, ctx.line1 - 1, ctx.line2, false), "\n"), nil
  else
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), nil
  end
end

---@internal
---@param argv string[]
---@param ctx? table
local function do_import(argv, ctx)
  local tf = require("markdown.core.table_fmt")
  local source = argv[1]

  local html, rerr = read_html_source(source, ctx)
  if not html then
    notify.warn("table import: " .. rerr)
    return
  end

  local rows, perr = tf.parse_html_table(html)
  if not rows then
    notify.warn("table import: " .. (perr or "no table found"))
    return
  end

  local gfm = tf.rows_to_gfm(rows, {})
  local bufnr = vim.api.nvim_get_current_buf()

  -- A ranged call with no explicit source replaces the selected HTML in
  -- place; otherwise insert below the cursor.
  if (not source or source == "") and ctx and ctx.range and ctx.range > 0 then
    vim.api.nvim_buf_set_lines(bufnr, ctx.line1 - 1, ctx.line2, false, gfm)
  else
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, cur, cur, false, gfm)
  end

  notify.info(string.format("Imported HTML table: %d row(s), %d column(s)", #rows - 1, #rows[1]))
end

---@internal
---@param argv string[]
local function do_new(argv)
  local cols = math.max(1, tonumber(argv[1] or 2) or 2)
  local rows = math.max(1, tonumber(argv[2] or 2) or 2)

  local function row(fill)
    local cells = {}
    for c = 1, cols do
      cells[c] = fill(c)
    end
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
  view = do_view,
  format = do_format,
  new = do_new,
  mode = do_mode,
  tableize = do_tableize,
  import = do_import,
}

--- Runs `:Markdown table <view|format|new|mode|tableize|import> ...`.
---@param argv string[]
---@param ctx? table  forwarded command context (range/line1/line2)
---@return nil
function M.run(argv, ctx)
  argv = argv or {}
  local sub = argv[1]
  local fn = sub and subcommands[sub]
  if not fn then
    notify.info("Usage: :Markdown table <view|format|new|mode|tableize|import> ...")
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
  -- tokens: Markdown(1) table(2) <sub>(3) <args…>(4…). The slot being completed
  -- is the token under the cursor, or one past the last committed token when
  -- nothing has been typed for it yet. Subs taking a single argument match it
  -- exactly, so they stop offering that argument once it is filled in.
  local sub = tokens[3]
  local slot = (arglead == "") and (#tokens + 1) or #tokens

  -- `format` takes an open-ended run of option tokens, so every slot past the
  -- sub name offers the same set.
  if sub == "format" and slot >= 4 then
    return require("markdown.core.table_fmt").complete(arglead)
  end
  if sub == "view" then
    -- tokens: Markdown(1) table(2) view(3) <action>(4) <scope>(5)
    if slot == 5 then
      local action = (tokens[4] or ""):lower()
      local out = {}
      if action == "toggle" or action == "markdown" or action == "box" then
        if vim.startswith("%", arglead) then out[#out + 1] = "%" end
        if vim.startswith("cwd", arglead) then out[#out + 1] = "cwd" end
        vim.list_extend(out, vim.fn.getcompletion(arglead, "file"))
      elseif action == "browser" or action == "browsernice" then
        if vim.startswith("reopen", arglead) then out[#out + 1] = "reopen" end
      end
      return out
    end
    if slot == 4 then -- completing the action itself
      local out = {}
      for name in pairs(VIEW_ACTIONS) do
        if vim.startswith(name, arglead) then out[#out + 1] = name end
      end
      table.sort(out)
      return out
    end
  end
  if sub == "mode" and slot == 4 then
    local out = {}
    for _, name in ipairs({ "on", "off", "toggle" }) do
      if vim.startswith(name, arglead) then out[#out + 1] = name end
    end
    return out
  end
  if sub == "import" and slot == 4 then
    local out = {}
    if vim.startswith("clipboard", arglead) then out[#out + 1] = "clipboard" end
    vim.list_extend(out, vim.fn.getcompletion(arglead, "file"))
    return out
  end
  if sub == "tableize" and slot == 4 then
    -- Offer the named separator formats; a literal/quoted delimiter is typed
    -- freehand. `auto` is the default (omit the argument entirely).
    local out = {}
    local names = {
      "auto",
      "csv",
      "tsv",
      "psv",
      "scsv",
      "space",
      "spaces",
      "comma",
      "tab",
      "semicolon",
      "colon",
      "pipe",
      "whitespace",
    }
    for _, name in ipairs(names) do
      if vim.startswith(name, arglead) then out[#out + 1] = name end
    end
    return out
  end

  -- Past the sub-subcommand slot with nothing above matching: that sub takes no
  -- completable argument here. Falling through to the sub names would offer
  -- `format`/`view`/… again in an argument position.
  if slot >= 4 then return {} end

  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
