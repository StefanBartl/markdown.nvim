---@module 'markdown.bindings.usrcmds'
---@brief User commands: the global `:Markdown` plus buffer-local commands,
--- built via lib.nvim.usercmd.composer.
---@description
--- `apply` creates the global `:Markdown` dispatcher (once) and the buffer-local
--- `OpenWithSystemApplication`. `apply_tableview` creates the buffer-local
--- `:TableView*` commands. Command *logic* lives in `markdown.commands.*`
--- and `markdown.tableview.*`; this module only registers the commands.
---
--- `:Markdown`'s subcommand routes forward ctx.raw.fargs (composer's
--- untouched nvim-callback fargs -- includes the subcommand token itself,
--- same shape M.execute already expects) straight into the unmodified
--- markdown.commands.execute()/.complete(); a shared MARKDOWN_SUBARG
--- composer type reuses M.complete() itself for first-arg completion by
--- synthesizing the "Markdown {subcmd} {arg_lead}" cmdline string
--- M.complete()'s own parsing expects, rather than duplicating its
--- per-subcommand delegation table.

local notify = require("markdown.util.notify").create("[markdown.bindings.usrcmds]")
local composer = require("lib.nvim.usercmd.composer")

local M = {}

local api = vim.api

---@internal
---@param bufnr integer
local function create_open_command(bufnr)
  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if not ok then cmds = {} end
  if cmds["OpenWithSystemApplication"] then return end

  composer.verb("OpenWithSystemApplication", {
    buffer = bufnr,
    desc = "[markdown.nvim] Open image/url/file under cursor",
    routes = {
      { path = {}, run = function() require("markdown.handler").handle_cursor_action() end },
    },
  })
end

---@internal
---@param bufnr integer
local function create_underline_headings_command(bufnr)
  if not require("markdown.config").feature_enabled("underline_headings") then return end

  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if not ok then cmds = {} end
  if cmds["MarkdownNvimUnderlineHeadings"] then return end

  composer.verb("MarkdownNvimUnderlineHeadings", {
    buffer = bufnr,
    desc = "[markdown.nvim] Underline every ATX heading's text with '=' (Setext-style decoration)",
    routes = {
      {
        path = {},
        run = function()
          local cfg = require("markdown.config").get()
          local char = (cfg.underline_headings and cfg.underline_headings.char) or "="
          require("markdown.core.underline_headings").apply(bufnr, { notify = true, char = char })
        end,
      },
    },
  })
end

---@internal Width-limited table wrapping: `:MDTable*` buffer-local commands.
--- Vim user-command names may only contain alphanumerics, so the roadmap's
--- `:MDTableCol+`/`:MDTableCol-` naming became `:MDTableCol inc|dec [n]`.
---@param bufnr integer
local function create_mdtable_commands(bufnr)
  if not require("markdown.config").feature_enabled("table_wrap") then return end

  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if not ok then cmds = {} end
  if cmds["MDTableWrap"] then return end

  local mdtable = require("markdown.commands.mdtable")

  composer.verb("MDTableWrap", {
    buffer = bufnr,
    desc = "[markdown.nvim] Wrap the table at the cursor (or every table, off any) to the resolved width plan",
    routes = { { path = {}, run = function() mdtable.wrap_at_cursor(bufnr) end } },
  })

  composer.verb("MDTableUnwrap", {
    buffer = bufnr,
    desc = "[markdown.nvim] Merge continuation rows of the table at the cursor back into one row each",
    routes = { { path = {}, run = function() mdtable.unwrap_at_cursor(bufnr) end } },
  })

  composer.verb("MDTableWrapVisual", {
    buffer = bufnr,
    bang = true,
    range = true,
    desc = "[markdown.nvim] Wrap tables in the visual selection; ! unwraps first for a clean recompute",
    routes = {
      {
        path = {},
        range = true,
        run = function(ctx) mdtable.wrap_visual(bufnr, ctx.range.line1, ctx.range.line2, ctx.bang) end,
      },
    },
  })

  composer.verb("MDTableWrapVisible", {
    buffer = bufnr,
    bang = true,
    desc = "[markdown.nvim] Wrap tables intersecting the visible window range; ! unwraps first",
    routes = { { path = {}, run = function(ctx) mdtable.wrap_visible(bufnr, ctx.bang) end } },
  })

  composer.verb("MDTableReflowHeader", {
    buffer = bufnr,
    desc = "[markdown.nvim] Reflow only the header + separator of the table at the cursor; body untouched",
    routes = { { path = {}, run = function() mdtable.reflow_header(bufnr) end } },
  })

  composer.verb("MDTableFoldRow", {
    buffer = bufnr,
    desc = "[markdown.nvim] Fold the continuation block under the cursor",
    routes = { { path = {}, run = function() mdtable.fold_row_at_cursor(bufnr) end } },
  })

  composer.verb("MDTableFoldAll", {
    buffer = bufnr,
    desc = "[markdown.nvim] Fold every table continuation block in the buffer",
    routes = { { path = {}, run = function() mdtable.fold_all(bufnr) end } },
  })

  composer.verb("MDTableProfile", {
    buffer = bufnr,
    desc = "[markdown.nvim] Load a named width profile (config.table.wrap_profiles) and re-wrap the table at the cursor",
    routes = {
      {
        path = {},
        args = { { name = "name", type = "STRING", enum = { "compact", "docs", "wide" } } },
        run = function(ctx) mdtable.set_profile(bufnr, ctx.args.name) end,
      },
    },
  })

  composer.verb("MDTableCol", {
    buffer = bufnr,
    desc = "[markdown.nvim] Widen/narrow the column under the cursor by n (default 1), preserving the row's total width",
    routes = {
      {
        path = { "inc" },
        args = { { name = "n", type = "INT", optional = true } },
        run = function(ctx) mdtable.col_nudge(bufnr, ctx.args.n or 1) end,
      },
      {
        path = { "dec" },
        args = { { name = "n", type = "INT", optional = true } },
        run = function(ctx) mdtable.col_nudge(bufnr, -(ctx.args.n or 1)) end,
      },
    },
  })

  composer.verb("MDTableAlign", {
    buffer = bufnr,
    desc = "[markdown.nvim] Cycle (or set) the alignment of the column under the cursor",
    routes = {
      {
        path = {},
        args = { { name = "mode", type = "STRING", enum = { "cycle", "left", "center", "right" } } },
        run = function(ctx) mdtable.align_cycle(bufnr, ctx.args.mode) end,
      },
    },
  })

  composer.verb("MDTableFlavor", {
    buffer = bufnr,
    desc = "[markdown.nvim] Switch GFM strictness (min-dash-length/spacing) and re-wrap the table at the cursor",
    routes = {
      {
        path = {},
        args = { { name = "flavor", type = "STRING", enum = { "github", "loose" } } },
        run = function(ctx) mdtable.set_flavor(bufnr, ctx.args.flavor) end,
      },
    },
  })

  composer.verb("MDTableLint", {
    buffer = bufnr,
    desc = "[markdown.nvim] Flag unequal cell counts, missing separators, empty header cells (vim.diagnostic)",
    routes = { { path = {}, run = function() mdtable.lint(bufnr) end } },
  })

  composer.verb("MDTableFixMissingSeparator", {
    buffer = bufnr,
    desc = "[markdown.nvim] Insert a separator line after every table block missing one",
    routes = { { path = {}, run = function() mdtable.fix_missing_separators(bufnr) end } },
  })

  composer.verb("MDTableDebug", {
    buffer = bufnr,
    desc = "[markdown.nvim] Show the resolved column-width plan for the table at the cursor",
    routes = { { path = {}, run = function() mdtable.debug_at_cursor(bufnr) end } },
  })

  composer.verb("MDTableToCSV", {
    buffer = bufnr,
    desc = "[markdown.nvim] Export the table at the cursor as CSV, to PATH or the + register",
    routes = {
      {
        path = {},
        args = { { name = "path", type = "PATH", optional = true } },
        run = function(ctx) mdtable.to_csv(bufnr, ctx.args.path) end,
      },
    },
  })

  composer.verb("MDTableFromCSV", {
    buffer = bufnr,
    desc = "[markdown.nvim] Insert a GFM table below the cursor, parsed from CSV (PATH or the + register)",
    routes = {
      {
        path = {},
        args = { { name = "path", type = "PATH", optional = true } },
        run = function(ctx) mdtable.from_csv(bufnr, ctx.args.path) end,
      },
    },
  })
end

-- :Markdown's 11 subcommands, feature-gated at registration time (matches
-- create_markdown_command()'s own idempotency: :Markdown is only ever
-- registered once per session, on the first buffer that triggers it, so a
-- feature flag flipped after that point was never live-checked either).
local SUBCOMMAND_NAMES = {
  "links",
  "toc",
  "gaps",
  "refs",
  "table",
  "render",
  "preview",
  "mdview",
  "create",
  "scope",
  "list",
  "headline_spacing",
  "image",
  "export",
}

-- How many positional slots each :Markdown route declares. Completion stops at
-- the last declared slot (composer has no variadic arg), and the deepest
-- surface here is `:Markdown table format <opt> <opt> ...` — an open-ended run
-- of option tokens. Six covers every documented invocation with room to spare;
-- tokens past it still EXECUTE fine (the handler reads ctx.raw.fargs, not the
-- bound args), they just stop offering <Tab>.
local MAX_SUBARGS = 6

composer.register_type("MARKDOWN_SUBARG", {
  validate = function(raw) return true, raw, nil end,
  -- `cmd_line` is the real command line, forwarded by composer's argtypes.
  -- markdown.commands.complete() decides which nested completer to delegate to
  -- by counting the tokens in it, so anything reconstructed from `arg_lead`
  -- alone pins every slot to the first argument. The synthetic fallback only
  -- applies when there is no command line to read (a direct call in a test).
  complete = function(arg_lead, spec, cmd_line)
    local line = cmd_line
    if not line or line == "" then line = "Markdown " .. spec.subcmd .. " " .. arg_lead end
    local ok, result = pcall(require("markdown.commands").complete, arg_lead, line, #line)
    return (ok and result) or {}
  end,
})

---@internal
local function create_markdown_command()
  if vim.fn.exists(":Markdown") == 2 then return end

  local commands_mod = require("markdown.commands")
  local feat = require("markdown.config").feature_enabled
  -- Mirrors commands/init.lua's own SUBCOMMAND_FEATURES gating exactly (a
  -- subcommand name usually equals its gating feature; `table` maps to
  -- either "table" or "tableview", and `gaps` (heading-level gap checker) is
  -- gated by the `toc` feature since it's a sub-behavior of TOC generation).
  local function enabled(name)
    local names
    if name == "table" then
      names = { "table", "tableview" }
    elseif name == "gaps" then
      names = { "toc" }
    else
      names = { name }
    end
    for _, n in ipairs(names) do
      if feat(n) then return true end
    end
    return false
  end

  local routes = {}
  for _, name in ipairs(SUBCOMMAND_NAMES) do
    if enabled(name) then
      local args = {}
      for i = 1, MAX_SUBARGS do
        args[i] = { name = "a" .. i, type = "MARKDOWN_SUBARG", optional = true, subcmd = name }
      end
      routes[#routes + 1] = {
        path = { name },
        args = args,
        run = function(ctx)
          commands_mod.execute(ctx.raw.fargs, {
            range = ctx.raw.range,
            line1 = ctx.raw.line1,
            line2 = ctx.raw.line2,
            -- Full unsplit argument text (quotes preserved). fargs mangles
            -- quoted tokens, so subcommands that take a literal separator
            -- (e.g. `:Markdown table tableize " "`) recover it from here.
            args = ctx.raw.args,
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
  create_underline_headings_command(bufnr)
  create_mdtable_commands(bufnr)
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

  local ui = require("markdown.tableview.renderer")
  local parser = require("markdown.tableview.parser")
  local browser_view_basic = require("markdown.tableview.views.browser_basic")
  local browser_view_nice = require("markdown.tableview.views.browser_niceified")
  local table_selector = require("markdown.tableview.views.table_selector")

  -- The table spanning the cursor row, or nil (no notification here — the
  -- caller decides whether a miss falls back to "all tables" or is an error).
  ---@internal
  ---@return table? tbl
  local function table_at_cursor()
    local line = api.nvim_win_get_cursor(0)[1]
    for _, t in ipairs(parser.get_tables(bufnr)) do
      if t.start_line <= line and line <= (t.end_line or t.start_line) then return t end
    end
    return nil
  end

  ---@internal
  ---@return table[]?
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
      local files = require("markdown.util.md_files").collect(expanded)
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
  ---@internal
  ---@param scope string?
  ---@return "one"|"all"|nil kind
  ---@return table|table[]|nil target
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
  ---@internal
  ---@return "markdown"|"box"
  local function default_style()
    local cfg = require("markdown.config").get()
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
        ---@cast target table
        ui.toggle_table(target, { floating = true, style = resolved_style })
      else
        ---@cast target table[]
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
    routes = {
      {
        path = {},
        run = function()
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
        end,
      },
    },
  })

  composer.verb("TableViewClose", {
    buffer = bufnr,
    desc = "[markdown.nvim] Close persistent table preview",
    routes = { { path = {}, run = function() ui.close() end } },
  })

  local reopen_arg =
    { { name = "reopen", type = "STRING", optional = true, values = { "reopen" } } }

  composer.verb("TableViewOpenBrowser", {
    buffer = bufnr,
    desc = "[markdown.nvim] Open table in browser (basic HTML); reuses the tab across calls, 'reopen' forces a new one",
    routes = {
      {
        path = {},
        args = reopen_arg,
        run = function(ctx)
          local force_new = (ctx.args.reopen or ""):lower() == "reopen"
          browser_view_basic(bufnr, force_new)
        end,
      },
    },
  })

  composer.verb("TableViewOpenBrowserNice", {
    buffer = bufnr,
    desc = "[markdown.nvim] Open table in browser (nice HTML); reuses the tab across calls, 'reopen' forces a new one",
    routes = {
      {
        path = {},
        args = reopen_arg,
        run = function(ctx)
          local force_new = (ctx.args.reopen or ""):lower() == "reopen"
          browser_view_nice(bufnr, force_new)
        end,
      },
    },
  })
end

return M
