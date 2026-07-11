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

  api.nvim_buf_create_user_command(bufnr, "TableViewToggle", function(_)
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
    ui.toggle_table(chosen, { floating = true })
  end, { desc = "[markdown.nvim] Toggle preview for table under cursor", nargs = 0 })

  api.nvim_buf_create_user_command(bufnr, "TableViewBox", function(_)
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
    ui.toggle_table(chosen, { floating = true, style = "box" })
  end, { desc = "[markdown.nvim] Toggle box-drawing table preview at cursor", nargs = 0 })

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
