---@module 'markdown_nvim.bindings.usrcmds'
---@brief User commands: the global `:Markdown` plus buffer-local commands,
--- built via lib.nvim.usercmd.composer.
---@description
--- `apply` creates the global `:Markdown` dispatcher (once) and the buffer-local
--- `OpenWithSystemApplication`. `apply_tableview` creates the buffer-local
--- `:TableView*` commands. Command *logic* lives in `markdown_nvim.commands.*`
--- and `markdown_nvim.tableview.*`; this module only registers the commands.
---
--- `:Markdown`'s subcommand routes forward ctx.raw.fargs (composer's
--- untouched nvim-callback fargs -- includes the subcommand token itself,
--- same shape M.execute already expects) straight into the unmodified
--- markdown_nvim.commands.execute()/.complete(); a shared MARKDOWN_SUBARG
--- composer type reuses M.complete() itself for first-arg completion by
--- synthesizing the "Markdown {subcmd} {arg_lead}" cmdline string
--- M.complete()'s own parsing expects, rather than duplicating its
--- per-subcommand delegation table.

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.bindings.usrcmds]")
local composer = require("lib.nvim.usercmd.composer")

local M = {}

local api = vim.api

local function create_open_command(bufnr)
  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if not ok then cmds = {} end
  if cmds["OpenWithSystemApplication"] then return end

  composer.verb("OpenWithSystemApplication", {
    buffer = bufnr,
    desc = "[markdown.nvim] Open image/url/file under cursor",
    routes = { { path = {}, run = function() require("markdown_nvim.handler").handle_cursor_action() end } },
  })
end

-- :Markdown's 10 subcommands, feature-gated at registration time (matches
-- create_markdown_command()'s own idempotency: :Markdown is only ever
-- registered once per session, on the first buffer that triggers it, so a
-- feature flag flipped after that point was never live-checked either).
local SUBCOMMAND_NAMES = {
  "links", "toc", "refs", "table", "render", "preview",
  "mdview", "create", "scope", "headline_spacing",
}

composer.register_type("MARKDOWN_SUBARG", {
  validate = function(raw) return true, raw, nil end,
  complete = function(arg_lead, spec)
    local synthetic = "Markdown " .. spec.subcmd .. " " .. arg_lead
    local ok, result = pcall(require("markdown_nvim.commands").complete, arg_lead, synthetic, 0)
    return (ok and result) or {}
  end,
})

local function create_markdown_command()
  if vim.fn.exists(":Markdown") == 2 then return end

  local commands_mod = require("markdown_nvim.commands")
  local feat = require("markdown_nvim.config").feature_enabled
  -- Mirrors commands/init.lua's own SUBCOMMAND_FEATURES gating exactly (a
  -- subcommand name usually equals its gating feature; `table` maps to
  -- either "table" or "tableview").
  local function enabled(name)
    local names = (name == "table") and { "table", "tableview" } or { name }
    for _, n in ipairs(names) do
      if feat(n) then return true end
    end
    return false
  end

  local routes = {}
  for _, name in ipairs(SUBCOMMAND_NAMES) do
    if enabled(name) then
      routes[#routes + 1] = {
        path = { name },
        args = { { name = "a1", type = "MARKDOWN_SUBARG", optional = true, subcmd = name } },
        run = function(ctx)
          commands_mod.execute(ctx.raw.fargs, {
            range = ctx.raw.range,
            line1 = ctx.raw.line1,
            line2 = ctx.raw.line2,
          })
        end,
      }
    end
  end

  composer.verb("Markdown", {
    desc = "[markdown.nvim] Markdown utility commands",
    range = true,
    routes = routes,
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
    return function(ctx)
      local scope = ctx.args.scope
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

  composer.register_type("MARKDOWN_TABLEVIEW_SCOPE", {
    validate = function(raw) return true, raw, nil end,
    complete = complete_scope,
  })

  local view_desc = "[markdown.nvim] Toggle %s preview: table at cursor, or every table with"
    .. " scope=%%|cwd|<path> (falls back to all-in-buffer off any table)"

  local scope_arg = { { name = "scope", type = "MARKDOWN_TABLEVIEW_SCOPE", optional = true } }

  composer.verb("TableViewToggle", {
    buffer = bufnr,
    desc = view_desc:format("config-style"),
    routes = { { path = {}, args = scope_arg, run = make_view_handler("config") } },
  })

  composer.verb("TableViewMarkdown", {
    buffer = bufnr,
    desc = view_desc:format("aligned-Markdown"),
    routes = { { path = {}, args = scope_arg, run = make_view_handler("markdown") } },
  })

  composer.verb("TableViewBox", {
    buffer = bufnr,
    desc = view_desc:format("box-drawing"),
    routes = { { path = {}, args = scope_arg, run = make_view_handler("box") } },
  })

  composer.verb("TableViewSelect", {
    buffer = bufnr,
    desc = "[markdown.nvim] Select and preview table",
    routes = { { path = {}, run = function()
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
    end } },
  })

  composer.verb("TableViewClose", {
    buffer = bufnr,
    desc = "[markdown.nvim] Close persistent table preview",
    routes = { { path = {}, run = function() ui.close() end } },
  })

  local reopen_arg = { { name = "reopen", type = "STRING", optional = true, values = { "reopen" } } }

  composer.verb("TableViewOpenBrowser", {
    buffer = bufnr,
    desc = "[markdown.nvim] Open table in browser (basic HTML); reuses the tab across calls, 'reopen' forces a new one",
    routes = { { path = {}, args = reopen_arg, run = function(ctx)
      local force_new = (ctx.args.reopen or ""):lower() == "reopen"
      browser_view_basic(bufnr, force_new)
    end } },
  })

  composer.verb("TableViewOpenBrowserNice", {
    buffer = bufnr,
    desc = "[markdown.nvim] Open table in browser (nice HTML); reuses the tab across calls, 'reopen' forces a new one",
    routes = { { path = {}, args = reopen_arg, run = function(ctx)
      local force_new = (ctx.args.reopen or ""):lower() == "reopen"
      browser_view_nice(bufnr, force_new)
    end } },
  })
end

return M
