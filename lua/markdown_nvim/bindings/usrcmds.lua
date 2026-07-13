---@module 'markdown_nvim.bindings.usrcmds'
---@brief User commands: the global `:Markdown` plus buffer-local commands.
---@description
--- `apply` creates the global `:Markdown` dispatcher (once) and the buffer-local
--- `OpenWithSystemApplication`. `apply_tableview` creates the buffer-local
--- `:TableView*` commands. Command *logic* lives in `markdown_nvim.commands.*`
--- and `markdown_nvim.tableview.*`; this module only registers the commands.

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.bindings.usrcmds]")

local M = {}

local api = vim.api

local function create_open_command(bufnr)
  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if not ok then cmds = {} end
  if cmds["OpenWithSystemApplication"] then return end

  api.nvim_buf_create_user_command(bufnr, "OpenWithSystemApplication", function()
    require("markdown_nvim.handler").handle_cursor_action()
  end, {
    desc  = "[markdown.nvim] Open image/url/file under cursor",
    nargs = 0,
  })
end

local function create_markdown_command()
  if vim.fn.exists(":Markdown") == 2 then return end

  vim.api.nvim_create_user_command("Markdown", function(opts)
    require("markdown_nvim.commands").execute(opts.fargs, {
      range = opts.range,
      line1 = opts.line1,
      line2 = opts.line2,
    })
  end, {
    nargs    = "*",
    range    = true,
    complete = function(arglead, cmdline, cursorpos)
      return require("markdown_nvim.commands").complete(arglead, cmdline, cursorpos)
    end,
    desc = "[markdown.nvim] Markdown utility commands",
  })
end

--- Create the core commands for `args.buf` (global :Markdown + buffer OpenWith).
---@param args table # a FileType autocmd event ({ buf = n }).
---@return nil
function M.apply(args)
  if type(args) ~= "table" or type(args.buf) ~= "number" then return end
  local bufnr = args.buf
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)) then return end

  create_open_command(bufnr)
  create_markdown_command()
end

--- Create the buffer-local TableView commands for `ev.buf`.
---@param ev table # a FileType autocmd event ({ buf = n }).
---@return nil
function M.apply_tableview(ev)
  if type(ev) ~= "table" or type(ev.buf) ~= "number" then return end
  local bufnr = ev.buf
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)) then return end

  local ok, existing = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if ok and existing and existing["TableViewToggle"] then return end

  local ui                   = require("markdown_nvim.tableview.renderer")
  local parser               = require("markdown_nvim.tableview.parser")
  local browser_view_basic   = require("markdown_nvim.tableview.views.browser_basic")
  local browser_view_nice    = require("markdown_nvim.tableview.views.browser_niceified")
  local table_selector       = require("markdown_nvim.tableview.views.table_selector")

  -- The table spanning the cursor row, or nil (no notification here — the
  -- caller decides whether a miss falls back to "all tables" or is an error).
  local function table_at_cursor()
    local line = api.nvim_win_get_cursor(0)[1]
    for _, t in ipairs(parser.get_tables(bufnr)) do
      if t.start_line <= line and line <= (t.end_line or t.start_line) then
        return t
      end
    end
    return nil
  end

  local function all_tables()
    local list = parser.get_tables(bufnr)
    if #list == 0 then
      notify.info("No tables found in buffer")
      return nil
    end
    return list
  end

  -- Every table in every *.md file under `path` (recursive), or every table in
  -- `path` itself when it names a single file. Returns nil (with a
  -- notification) when the path doesn't resolve to anything with tables.
  ---@param path string
  ---@return table[]|nil
  local function tables_from_path(path)
    local expanded = vim.fn.expand(path)

    if vim.fn.isdirectory(expanded) == 1 then
      local files = require("markdown_nvim.util.md_files").collect(expanded)
      if #files == 0 then
        notify.info("No *.md files found under " .. expanded)
        return nil
      end
      local all = {}
      for _, f in ipairs(files) do
        vim.list_extend(all, parser.get_tables_from_file(f))
      end
      if #all == 0 then
        notify.info("No tables found under " .. expanded)
        return nil
      end
      return all
    end

    if vim.fn.filereadable(expanded) == 1 then
      local list = parser.get_tables_from_file(expanded)
      if #list == 0 then
        notify.info("No tables found in " .. expanded)
        return nil
      end
      return list
    end

    notify.warn("TableView: path not found: " .. path)
    return nil
  end

  -- Resolve what a TableView* invocation should act on, given its optional
  -- `scope` argument:
  --   scope == "%"           -> every table in the current buffer, stacked
  --   scope == "cwd"         -> every table in every *.md file under the cwd
  --   scope == <path>        -> every table in that file, or (if a directory)
  --                             every table in every *.md file under it
  --   scope == "" / nil       -> the table at the cursor; if there is none,
  --                             fall back to every table in the buffer
  -- Returns ("one", table) | ("all", table[]) | (nil, nil).
  local function resolve_target(scope)
    if scope == "%" then
      return "all", all_tables()
    elseif scope == "cwd" then
      local target = tables_from_path(vim.fn.getcwd())
      if not target then return nil, nil end
      return "all", target
    elseif scope ~= nil and scope ~= "" then
      local target = tables_from_path(scope)
      if not target then return nil, nil end
      return "all", target
    end

    local at_cursor = table_at_cursor()
    if at_cursor then return "one", at_cursor end
    return "all", all_tables()
  end

  -- Resolved default float style ("markdown" | "box"), from config.tableview.
  local function default_style()
    local cfg = require("markdown_nvim.config").get()
    return (cfg.tableview and cfg.tableview.style) or "markdown"
  end

  --- Build a TableViewToggle/Markdown/Box handler for a fixed `style`
  --- ("config" resolves default_style() at call time; "markdown"/"box" force it).
  ---@param style "config"|"markdown"|"box"
  local function make_view_handler(style)
    return function(cmd_opts)
      local scope = cmd_opts.args ~= "" and cmd_opts.args or nil
      local kind, target = resolve_target(scope)
      if not kind then return end
      local resolved_style = style == "config" and default_style() or style
      if kind == "one" then
        ui.toggle_table(target, { floating = true, style = resolved_style })
      else
        ui.toggle_tables(target, { floating = true, style = resolved_style })
      end
    end
  end

  --- Completion for the scope argument: `%`, `cwd`, then file/dir completion.
  ---@param arglead string
  ---@return string[]
  local function complete_scope(arglead)
    local out = {}
    if vim.startswith("%", arglead) then out[#out + 1] = "%" end
    if vim.startswith("cwd", arglead) then out[#out + 1] = "cwd" end
    vim.list_extend(out, vim.fn.getcompletion(arglead, "file"))
    return out
  end

  local view_desc = "[markdown.nvim] Toggle %s preview: table at cursor, or every table with"
    .. " scope=%%|cwd|<path> (falls back to all-in-buffer off any table)"

  api.nvim_buf_create_user_command(bufnr, "TableViewToggle", make_view_handler("config"), {
    desc     = view_desc:format("config-style"),
    nargs    = "?",
    complete = complete_scope,
  })

  api.nvim_buf_create_user_command(bufnr, "TableViewMarkdown", make_view_handler("markdown"), {
    desc     = view_desc:format("aligned-Markdown"),
    nargs    = "?",
    complete = complete_scope,
  })

  api.nvim_buf_create_user_command(bufnr, "TableViewBox", make_view_handler("box"), {
    desc     = view_desc:format("box-drawing"),
    nargs    = "?",
    complete = complete_scope,
  })

  api.nvim_buf_create_user_command(bufnr, "TableViewSelect", function()
    local tables = parser.get_tables(bufnr)
    if #tables == 0 then
      notify.info("No tables found in buffer")
      return
    end
    if #tables == 1 then
      ui.render_table(tables[1], { floating = true })
      return
    end
    table_selector(tables)
  end, { desc = "[markdown.nvim] Select and preview table", nargs = 0 })

  api.nvim_buf_create_user_command(bufnr, "TableViewClose", function()
    ui.close()
  end, { desc = "[markdown.nvim] Close persistent table preview", nargs = 0 })

  api.nvim_buf_create_user_command(bufnr, "TableViewOpenBrowser", function()
    browser_view_basic(bufnr)
  end, { desc = "[markdown.nvim] Open table in browser (basic HTML)", nargs = 0 })

  api.nvim_buf_create_user_command(bufnr, "TableViewOpenBrowserNice", function()
    browser_view_nice(bufnr)
  end, { desc = "[markdown.nvim] Open table in browser (nice HTML)", nargs = 0 })
end

return M
