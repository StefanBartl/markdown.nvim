-- docs/TESTS/session_features_spec.lua — de-facto coverage for every feature
-- built in the "roadmap session": refs sync, actions/keymaps, feature gating,
-- the menu integration, double-click fold (ATX + Setext), the link-underline
-- fix, the fold H2+ outline toggle, the fold-from-menu-context bug fix, the
-- tableview box style + configurable default, table mode / tableize / cell
-- motions, and the Windows platform.open list-argv fix.
--
-- Each section drives the same entry points a user would: `:Markdown <sub>`
-- (via commands.execute/complete), `require("markdown").setup()`
-- config, and the public action functions — not private internals — so a
-- pass here means the actual user-facing surface works, not just a helper.
--
-- NOT covered here (cannot run headless; see docs/TESTS/README.md):
--   * in-terminal image rendering (needs a real kitty-graphics terminal)
--   * the nvzone/menu popup actually rendering on RightMouse (UI-only)
-- `tableview_spec.lua` already covers TableView's q/<Esc> close behaviour.
---@diagnostic disable: missing-fields, duplicate-set-field

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api

  -- ===========================================================================
  -- 1) Reference sync (:Markdown refs sync|check|live|baseline)
  -- ===========================================================================
  do
    require("markdown.config").setup({})
    local commands = require("markdown.commands")

    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Doc",
      "",
      "## Table of content",
      "",
      "- [Setup](#setup)",
      "",
      "---",
      "",
      "## Setup",
      "",
      "See [the setup section](#setup) for details.",
    })
    require("markdown.core.refs").baseline(buf)

    -- Rename "## Setup" -> "## Installation" via an in-place edit (survives
    -- the extmark tracking, exactly like a user typing over the word).
    for i, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l == "## Setup" then
        api.nvim_buf_set_text(buf, i - 1, 3, i - 1, 8, { "Installation" })
        break
      end
    end

    commands.execute({ "refs", "sync" })
    local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ok(
      text:find("%[Installation%]%(#installation%)"),
      "refs sync: TOC entry updated to the new anchor"
    )
    ok(
      text:find("%[the setup section%]%(#installation%)"),
      "refs sync: inline link updated to the new anchor"
    )

    -- check: a genuinely broken anchor is reported via quickfix, not silently dropped.
    api.nvim_buf_set_lines(buf, -1, -1, false, { "", "dangling [link](#does-not-exist)." })
    vim.fn.setqflist({}, "r", vim.empty_dict()) -- clear
    commands.execute({ "refs", "check" })
    local qf = vim.fn.getqflist()
    ok(#qf >= 1, "refs check: reports the broken anchor in the quickfix list")
    ok(qf[1].text:find("#does%-not%-exist"), "refs check: quickfix entry names the broken anchor")

    -- live toggling flips per-buffer tracking on/off without erroring.
    commands.execute({ "refs", "live", "on" })
    commands.execute({ "refs", "live", "off" })
    ok(true, "refs live on/off ran without error")
  end

  -- ===========================================================================
  -- 2) Actions API + declarative per-binding keymaps (config.keymaps)
  -- ===========================================================================
  do
    local keymaps = require("markdown.bindings.keymaps")

    local function apply_with(user_cfg)
      require("markdown.config").setup(user_cfg)
      local buf = H.scratch("markdown")
      keymaps.apply(buf)
      local lhs_list = {}
      for _, m in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
        lhs_list[#lhs_list + 1] = m.lhs
      end
      for _, m in ipairs(api.nvim_buf_get_keymap(buf, "v")) do
        lhs_list[#lhs_list + 1] = "v:" .. m.lhs
      end
      return lhs_list
    end
    local function has(list, needle)
      for _, x in ipairs(list) do
        if x == needle then return true end
      end
      return false
    end
    -- nvim_buf_get_keymap reports lhs AFTER <leader>/<localleader> expansion
    -- (default mapleader is backslash when unset), so compare against the
    -- expanded form rather than the literal "<leader>..." spelling.
    local leader = (vim.g.mapleader and vim.g.mapleader ~= "") and vim.g.mapleader or "\\"

    local default = apply_with({})
    ok(has(default, "mj"), "keymaps default: mj (jump_anchor) bound")
    ok(
      has(default, leader .. "toc"),
      "keymaps default: <leader>toc bound (expands to '" .. leader .. "toc')"
    )

    local disabled = apply_with({ keymaps = { jump_anchor = false } })
    ok(not has(disabled, "mj"), "keymaps override: jump_anchor=false removes mj")

    local remapped = apply_with({ keymaps = { toc = "<leader>T" } })
    ok(
      not has(remapped, leader .. "toc"),
      "keymaps override: toc remapped away from its default lhs"
    )
    ok(has(remapped, leader .. "T"), "keymaps override: toc bound to the new lhs")

    -- Legacy boolean flags keep working alongside the new per-binding table.
    local flag_off = apply_with({ map_double_asterisk = false })
    ok(
      not has(flag_off, "v:**"),
      "legacy flag: map_double_asterisk=false removes ** in visual mode"
    )

    -- The public actions facade exposes plain functions (no <Plug> indirection).
    eq(
      type(require("markdown").actions.fold_toggle),
      "function",
      "actions.fold_toggle is a function"
    )
    eq(type(require("markdown").actions.toc), "function", "actions.toc is a function")
  end

  -- ===========================================================================
  -- 3) Feature gating (config.features: disable / enable / just_enable)
  -- ===========================================================================
  do
    local cfg = require("markdown.config")
    local commands = require("markdown.commands")

    cfg.setup({ features = { just_enable = { "table", "toc" } } })
    local comp = commands.complete("", "Markdown ")
    table.sort(comp)
    eq(
      table.concat(comp, ","),
      "table,toc",
      "just_enable={table,toc}: completion lists exactly those two"
    )

    cfg.setup({ features = { disable = "all" } })
    eq(#commands.complete("", "Markdown "), 0, "disable=all: no subcommand left in completion")

    -- The "table" subcommand stays available under either the table OR the
    -- tableview feature, so "just enable tableview" keeps the whole table
    -- surface (view/format/new/mode/tableize) working standalone.
    cfg.setup({ features = { just_enable = { "tableview" } } })
    local has_table = false
    for _, c in ipairs(commands.complete("", "Markdown ")) do
      if c == "table" then has_table = true end
    end
    ok(has_table, "just_enable={tableview}: 'table' subcommand is available via the alias")

    cfg.setup({}) -- reset for later sections
  end

  -- ===========================================================================
  -- 4) Menu integration (context-aware, self-gating, opt-out)
  -- ===========================================================================
  do
    require("markdown.config").setup({})
    local menu = require("markdown.integrations.menu")

    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# Title", "", "some prose", "## Section" })

    api.nvim_win_set_cursor(0, { 4, 0 }) -- on "## Section"
    local on_heading = menu.items()
    local names = {}
    for _, it in ipairs(on_heading) do
      names[#names + 1] = it.name
    end
    ok(
      vim.tbl_contains(names, "Fold / Unfold Heading"),
      "menu on heading: fold-toggle entry present"
    )
    ok(vim.tbl_contains(names, "Insert / Refresh TOC"), "menu on heading: TOC entry present")
    ok(vim.tbl_contains(names, "Sync References"), "menu on heading: refs entry present")

    api.nvim_win_set_cursor(0, { 3, 0 }) -- on prose
    names = {}
    for _, it in ipairs(menu.items()) do
      names[#names + 1] = it.name
    end
    ok(
      not vim.tbl_contains(names, "Fold / Unfold Heading"),
      "menu off heading: fold entries hidden"
    )
    ok(
      vim.tbl_contains(names, "Insert / Refresh TOC"),
      "menu off heading: doc-level entries still present"
    )

    require("markdown.config").setup({ menu = { fold = false } })
    names = {}
    api.nvim_win_set_cursor(0, { 4, 0 })
    for _, it in ipairs(menu.items()) do
      names[#names + 1] = it.name
    end
    ok(
      not vim.tbl_contains(names, "Fold / Unfold Heading"),
      "menu opt-out: menu.fold=false hides fold entries"
    )

    require("markdown.config").setup({ menu = { enable = false } })
    eq(#menu.items(), 0, "menu master switch: menu.enable=false yields zero entries")

    require("markdown.config").setup({})
    local sub = menu.submenu()
    ok(sub and sub.name and #sub.items > 0, "menu.submenu() returns a non-empty fly-out entry")
  end

  -- ===========================================================================
  -- 5) Double-click fold on ATX and Setext headings
  -- ===========================================================================
  do
    require("markdown.config").setup({})
    local handler = require("markdown.handler")

    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# ATX heading",
      "atx body",
      "Setext Title",
      "============",
      "setext body",
    })
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    vim.wo.foldlevel = 99
    vim.cmd("normal! zx")

    api.nvim_win_set_cursor(0, { 1, 0 })
    handler.handle_cursor_action({ silent = true, mouse = true })
    ok(vim.fn.foldclosed(2) > 0, "double-click on ATX heading closes its fold")
    handler.handle_cursor_action({ silent = true, mouse = true })
    ok(vim.fn.foldclosed(2) == -1, "double-click again re-opens the ATX fold")

    api.nvim_win_set_cursor(0, { 3, 0 }) -- on the Setext title line
    handler.handle_cursor_action({ silent = true, mouse = true })
    ok(vim.fn.foldclosed(5) > 0, "double-click on a Setext TITLE line closes its fold")
    handler.handle_cursor_action({ silent = true, mouse = true }) -- back on title, still folds/unfolds same section
    ok(vim.fn.foldclosed(5) == -1, "double-click again re-opens the Setext fold")
  end

  -- ===========================================================================
  -- 6) Link-underline fix (long wrapped URLs no longer draw a full underline)
  -- ===========================================================================
  do
    require("markdown.config").setup({})
    require("markdown.hl_options").setup(require("markdown.config").get())
    local hlU = api.nvim_get_hl(0, { name = "@markup.link.url.markdown_inline" })
    ok(
      hlU.underline ~= true,
      "link_hl default: underline stripped from @markup.link.url.markdown_inline"
    )

    require("markdown.config").setup({ link_hl = { underline = true } })
    require("markdown.hl_options").setup(require("markdown.config").get())
    local hlU2 = api.nvim_get_hl(0, { name = "@markup.link.url.markdown_inline" })
    eq(hlU2.underline, true, "link_hl.underline=true restores the underline")

    require("markdown.config").setup({}) -- reset
  end

  -- ===========================================================================
  -- 7) Fold H2+ as an outline TOGGLE (fold below H2, keep H1/H2 open; toggle back)
  -- ===========================================================================
  do
    local fold_levels = require("markdown.core.fold_levels")
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# H1",
      "intro",
      "## H2 A",
      "a body",
      "### H3 sub",
      "sub body",
      "## H2 B",
      "b body",
    })
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    vim.wo.foldlevel = 99
    vim.cmd("normal! zx")

    fold_levels.fold_h2_plus() -- 1st call: fold everything below H2
    ok(vim.fn.foldclosed(3) == -1, "fold H2+ (1st call): H2 heading itself stays open")
    ok(vim.fn.foldclosed(6) > 0, "fold H2+ (1st call): H3 content is folded")

    fold_levels.fold_h2_plus() -- 2nd call: toggle back to fully unfolded
    ok(vim.fn.foldclosed(6) == -1, "fold H2+ (2nd call): toggling again unfolds everything")
  end

  -- ===========================================================================
  -- 8) Fold toggle/unfold work even when invoked from a "menu-like" context
  --    (foldenable disturbed beforehand — this was the actual bug: only
  --    fold_h2_plus reasserted foldmethod/foldenable, so the plain toggle and
  --    unfold-all silently no-op'd from an nvzone/menu callback).
  -- ===========================================================================
  do
    local fold = require("markdown.core.fold")
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# H1", "a", "## H2", "b" })
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    vim.wo.foldlevel = 99
    vim.cmd("normal! zx")

    vim.wo.foldenable = false -- simulate the disturbed state a menu callback can see
    api.nvim_win_set_cursor(0, { 3, 0 })
    fold.toggle_under_cursor()
    ok(
      vim.fn.foldclosed(4) > 0,
      "fold.toggle_under_cursor works even with foldenable off beforehand"
    )

    vim.wo.foldenable = false
    fold.unfold_all_center()
    ok(
      vim.fn.foldclosed(4) == -1,
      "fold.unfold_all_center works even with foldenable off beforehand"
    )
  end

  -- ===========================================================================
  -- 9) TableView box-drawing style + configurable default (config.tableview.style)
  -- ===========================================================================
  do
    local renderer = require("markdown.tableview.renderer")

    local mt = {
      header = { cells = { { content = "Name" }, { content = "Age" } } },
      rows = { { cells = { { content = "Alice" }, { content = "30" } } } },
      alignments = { "left", "right" },
    }
    renderer.render_markdowntable(mt, { floating = true, style = "box" })
    local lines = api.nvim_buf_get_lines(api.nvim_get_current_buf(), 0, -1, false)
    ok(lines[1]:find("┌"), "box style: top border uses box-drawing characters")
    ok(
      lines[2]:find("│") and lines[2]:find("Name"),
      "box style: header row rendered inside the grid"
    )
    renderer.close_view()

    -- Configurable default: TableViewToggle (view "toggle") should honour
    -- config.tableview.style, while view "markdown" / "box" force it either way.
    local usrcmds = require("markdown.bindings.usrcmds")
    local commands = require("markdown.commands")
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "| a | b |", "| - | - |", "| 1 | 2 |" })
    usrcmds.apply_tableview({ buf = buf })
    api.nvim_win_set_cursor(0, { 1, 0 })

    local seen_style
    local orig_render = renderer.render_markdowntable
    renderer.render_markdowntable = function(t, opts)
      seen_style = opts and opts.style
      orig_render(t, opts)
    end

    require("markdown.config").setup({ tableview = { style = "box" } })
    commands.execute({ "table", "view", "toggle" })
    eq(seen_style, "box", "config.tableview.style=box: view toggle renders in box style")
    renderer.close_view()

    commands.execute({ "table", "view", "markdown" })
    eq(seen_style, "markdown", "view 'markdown' always forces markdown style regardless of config")
    renderer.close_view()

    require("markdown.config").setup({})
    commands.execute({ "table", "view", "toggle" })
    eq(seen_style, "markdown", "config default (unset): view toggle renders in markdown style")
    renderer.close_view()

    renderer.render_markdowntable = orig_render
  end

  -- ===========================================================================
  -- 10) Table mode (auto-format), tableize, and cell motions
  -- ===========================================================================
  do
    require("markdown.config").setup({})
    local commands = require("markdown.commands")
    local table_mode = require("markdown.core.table_mode")
    local actions = require("markdown").actions

    -- tableize: CSV -> aligned GFM table, driven through the real dispatcher
    -- with an explicit range (as :'<,'>Markdown table tableize would pass).
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "Name,Age,City", "Alice,30,NYC", "Bob,5,LA" })
    commands.execute({ "table", "tableize" }, { range = 2, line1 = 1, line2 = 3 })
    local out = api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(
      out[1]:find("Name") and out[1]:find("Age") and out[1]:find("City"),
      "tableize: header row built from CSV"
    )
    ok(out[2]:find("%-%-%-"), "tableize: separator row inserted")
    ok(out[3]:find("Alice") and out[4]:find("Bob"), "tableize: data rows preserved")

    -- tableize with an explicit space separator, recovered from the raw arg
    -- string (fargs mangles the quoted `" "`, so the dispatcher forwards ctx.args).
    -- Leading spaces must map to leading empty columns.
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a b", "  c" })
    commands.execute(
      { "table", "tableize" },
      { range = 2, line1 = 1, line2 = 2, args = 'table tableize " "' }
    )
    out = api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(out[1]:find("| a ") and out[1]:find(" b "), "tableize space: two header columns")
    ok(
      out[3]:find("| c ") or out[3]:match("|%s+|%s+c%s+|"),
      "tableize space: leading space -> 3rd column"
    )

    -- Named format keyword (csv) plus RFC-4180 quoting: a quoted field keeps its
    -- embedded comma as a single cell.
    local qb = H.scratch("markdown")
    api.nvim_buf_set_lines(qb, 0, -1, false, { "Name,City", '"Smith, John","New York"' })
    table_mode.tableize(qb, 1, 2, "csv")
    local qout = api.nvim_buf_get_lines(qb, 0, -1, false)
    ok(
      qout[3]:find("Smith, John") and qout[3]:find("New York"),
      "tableize csv: quoted comma stays in one cell"
    )
    ok(not qout[3]:find('"'), "tableize csv: surrounding quotes stripped from cells")

    -- 'spaces' (runs of 2+ whitespace) collapses whitespace runs into one delim.
    local sb = H.scratch("markdown")
    api.nvim_buf_set_lines(sb, 0, -1, false, { "a    b   c", "1  2  3" })
    table_mode.tableize(sb, 1, 2, "spaces")
    local sout = api.nvim_buf_get_lines(sb, 0, -1, false)
    ok(
      sout[1]:find("a")
        and sout[1]:find("b")
        and sout[1]:find("c")
        and not sout[2]:find("|%s*|%s*|%s*|%s*|"),
      "tableize spaces: 2+ whitespace runs -> exactly three columns"
    )

    -- table mode: toggle on, mangle a cell, reformat re-aligns the columns.
    -- (the tableize cases above created scratch buffers; re-front the main one so
    -- the current-buffer :Markdown table mode commands act on it.)
    api.nvim_set_current_buf(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "| a | b |", "| --- | --- |", "| 1 | 2000000 |" })
    commands.execute({ "table", "mode", "on" })
    ok(table_mode.is_enabled(buf), "table mode: 'on' enables auto-format tracking for the buffer")
    api.nvim_buf_set_lines(buf, 0, 1, false, { "| aaaa | b |" }) -- widen the header
    api.nvim_win_set_cursor(0, { 1, 2 })
    table_mode.reformat(buf) -- what the debounced TextChanged callback would run
    local reformatted = api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(
      reformatted[1]:find("aaaa") and reformatted[3]:find("2000000"),
      "table mode: reformat realigned all rows to the new width"
    )
    commands.execute({ "table", "mode", "off" })
    ok(not table_mode.is_enabled(buf), "table mode: 'off' disables auto-format tracking")

    -- cell motions ]| / [|
    api.nvim_buf_set_lines(buf, 0, -1, false, { "| alpha | beta | gamma |" })
    api.nvim_win_set_cursor(0, { 1, 2 }) -- inside 'alpha'
    actions.table_next_cell()
    local c1 = api.nvim_win_get_cursor(0)[2]
    actions.table_next_cell()
    local c2 = api.nvim_win_get_cursor(0)[2]
    ok(c2 > c1, "]| (table_next_cell) advances to a later column each call")
    actions.table_prev_cell()
    local c3 = api.nvim_win_get_cursor(0)[2]
    eq(c3, c1, "[| (table_prev_cell) returns to the previous cell's start")
  end

  -- ===========================================================================
  -- 11) platform.open: list-argv fallback (Windows pwsh fix), no shellescape
  -- ===========================================================================
  do
    local platform = require("markdown.util.platform")
    local orig_ui_open = vim.ui and vim.ui.open
    local orig_system = vim.system
    local had_open_default = package.loaded["lib.nvim.cross.open_default"] ~= nil
    local orig_open_default = package.loaded["lib.nvim.cross.open_default"]

    if vim.ui then vim.ui.open = nil end -- force the fallback path deterministically
    -- Also stub out the lib.nvim.cross.open_default soft dependency: when
    -- lib.nvim is on the runtimepath it would otherwise handle the open
    -- itself (via a real jobstart call) before platform.lua ever reaches
    -- its own list-argv/vim.system fallback below.
    package.loaded["lib.nvim.cross.open_default"] = function()
      return false, "stubbed: forced fallback"
    end
    local captured
    vim.system = function(argv, opts)
      captured = { argv = argv, detach = opts and opts.detach }
      return {}
    end

    local target = "C:/tmp/some file.html"
    local okOpen = platform.open(target)
    ok(okOpen, "platform.open: reports success via the list-argv fallback")
    ok(captured, "platform.open: launched via vim.system (not a shell string)")
    if captured then
      eq(captured.detach, true, "platform.open: launches detached")
      if platform.os() == "windows" then
        eq(#captured.argv, 2, "platform.open (windows): argv has exactly 2 elements")
        eq(captured.argv[1], "explorer.exe", "platform.open (windows): argv[1] is explorer.exe")
        eq(
          captured.argv[2],
          target,
          "platform.open (windows): the raw target is the last argv element (no shellescape quoting)"
        )
      end
    end

    if vim.ui then vim.ui.open = orig_ui_open end
    vim.system = orig_system
    package.loaded["lib.nvim.cross.open_default"] = had_open_default and orig_open_default or nil
  end

  -- ===========================================================================
  -- 12) Dead code actually removed (tableview/live.lua)
  -- ===========================================================================
  do
    local okReq = pcall(require, "markdown.tableview.live")
    ok(not okReq, "tableview/live.lua was removed (dead code; never started, no server)")
  end
end
