---@module 'markdown.bindings.usrcmds'
---@brief User commands: the global `:Markdown` plus buffer-local commands,
--- built via lib.nvim.bindings.usercmd.composer.
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
local composer = require("lib.nvim.bindings.usercmd.composer")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

local api = vim.api

---@internal
---@param bufnr integer
local function create_open_command(bufnr)
  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  -- The empty fallback is checked against `vim.api.keyset.command_info`,
  -- whose every field Neovim's meta declares required -- there is nothing to
  -- put in a "the call failed" placeholder.
  ---@diagnostic disable-next-line: missing-fields
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
  -- The empty fallback is checked against `vim.api.keyset.command_info`,
  -- whose every field Neovim's meta declares required -- there is nothing to
  -- put in a "the call failed" placeholder.
  ---@diagnostic disable-next-line: missing-fields
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
  -- The empty fallback is checked against `vim.api.keyset.command_info`,
  -- whose every field Neovim's meta declares required -- there is nothing to
  -- put in a "the call failed" placeholder.
  ---@diagnostic disable-next-line: missing-fields
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
        args = {
          {
            name = "name",
            type = "STRING",
            enum = { "compact", "docs", "wide" },
            desc = "Width profile from config.table.wrap_profiles",
          },
        },
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
        args = {
          {
            name = "mode",
            type = "STRING",
            enum = { "cycle", "left", "center", "right" },
            desc = "Alignment of the column under the cursor",
            enum_desc = { cycle = "Step to the next alignment: left, center, right" },
          },
        },
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
        args = {
          {
            name = "flavor",
            type = "STRING",
            enum = { "github", "loose" },
            desc = "How strict the table follows GFM",
            enum_desc = {
              github = "Strict GFM: separators of at least 3 dashes, spaced",
              loose = "Compact separators allowed, no forced minimum",
            },
          },
        },
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

-- :Markdown's subcommands come from `markdown.commands.names()` (the dispatcher's own table) and
-- are feature-gated at registration time (matches create_markdown_command()'s own idempotency:
-- :Markdown is only ever registered once per session, on the first buffer that triggers it, so a
-- feature flag flipped after that point was never live-checked either).

-- What the positional slots of each `:Markdown <sub>` route mean, for the option float. The slots
-- are generic (`a1`..`a6`, bound by position only; the handler re-reads ctx.raw.fargs), so the
-- meaning is per subcommand and, past the first slot, per action typed before it. A number is
-- the slot; `rest` covers every slot without a text of its own. A subcommand with no entry here
-- shows up in `composer.help.undocumented(..., { args = true })` (TESTS/usrcmds_help_spec.lua).
---@type table<string, { [integer]: string, rest: string }>
local SUBARG_DESC = {
  links = {
    "Action: show, create, check or sanitize; a bare path means create",
    "show/sanitize: scope (%, cwd or a file); create: options or a path",
    rest = "create: more options (-r, --noignore, --root) and the path",
  },
  toc = { rest = "Max level, min=N, max=N, marker=X, --[no-]sep, --[no-]check-gaps" },
  gaps = { rest = "Not used: gaps takes no arguments" },
  refs = {
    "Action: sync (default), check, live or baseline",
    "live: on, off or toggle; the other actions take none",
    rest = "Not used: refs takes an action and, for live, a switch",
  },
  table = {
    "Action: view, format, new, mode, tableize or import",
    "Per action: view mode, option, columns, on/off, separator or source",
    "toggle/markdown/box: scope; browser(nice): reopen; new: rows; format: options",
    rest = "format: more options (header=, cell=, skip=, scope=); else unused",
  },
  render = {
    "Switch: on, off or toggle (default: toggle)",
    rest = "Not used: render takes a single switch",
  },
  preview = {
    "Action: start, stop or toggle (default: toggle)",
    rest = "Not used: preview takes a single action",
  },
  mdview = {
    "File to open in mdview; default: the current buffer",
    rest = "Not used: mdview takes a single file",
  },
  create = {
    "Kind: fs creates the files and folders the links point to",
    rest = "Not used: create takes a single kind",
  },
  scope = {
    "Switch: on, off, toggle or status (default: toggle)",
    rest = "Not used: scope takes a single switch",
  },
  list = {
    "What to list: headings (default)",
    "Scope: % (default), cwd or a file path",
    rest = "Not used: list takes what and scope",
  },
  headline_spacing = { rest = "Not used: headline_spacing takes no arguments" },
  image = {
    "Action: paste (default) or screenshot",
    rest = "Not used: image takes a single action",
  },
  export = {
    "Kind of export: pdf (the only one, default)",
    "File to export; default: the current buffer",
    rest = "Not used: export takes a kind and a file",
  },
  headings = {
    "Action: format (normalize the heading text)",
    rest = "Option: emphasis=, hashes=, whitespace=, punctuation=, capitalize=",
  },
  format = {
    "Op to apply, e.g. strip-bold or collapse-blank-lines (Tab lists all)",
    rest = "More ops, scope=%|cfile|cwd|PATH and dry-run (report only)",
  },
}

---@internal
---@param name string  the subcommand
---@param slot integer
---@return string|nil
local function subarg_desc(name, slot)
  local texts = SUBARG_DESC[name]
  return texts and (texts[slot] or texts.rest) or nil
end

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
    -- `subcmd` is this plugin's own payload on the arg spec (see the
    -- `register_type` call site below), not part of composer's shape.
    ---@cast spec Mkdn.SubargSpec
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
  for _, name in ipairs(commands_mod.names()) do
    if enabled(name) then
      local args = {}
      for i = 1, MAX_SUBARGS do
        args[i] = {
          name = "a" .. i,
          type = "MARKDOWN_SUBARG",
          optional = true,
          subcmd = name,
          desc = subarg_desc(name, i),
        }
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

--- Register the global `:Markdown` dispatcher (idempotent) without needing a
--- markdown buffer. `:checkhealth markdown` can run before any markdown file
--- was opened, when the verb would otherwise not exist yet.
---@return nil
function M.ensure_global() create_markdown_command() end

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
    -- expand_path, not vim.fn.expand (SEC-34): `path` is a user-typed
    -- command argument, not a Vim cmdline special.
    local expanded = expand_path(path)

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
    desc = "Tables to show: %, cwd or a path; default: the one at the cursor",
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

  local reopen_arg = {
    {
      name = "reopen",
      type = "STRING",
      optional = true,
      values = { "reopen" },
      desc = "Force a new browser tab instead of reusing the last one",
    },
  }

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
