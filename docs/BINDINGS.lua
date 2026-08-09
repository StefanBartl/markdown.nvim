-- docs/BINDINGS.md — markdown.nvim binding cheatsheet.
--
-- A single, machine-readable overview of every keymap, user command and
-- autocommand markdown.nvim defines. DOCUMENTATION only: not required at
-- runtime. It mirrors the source of truth in lua/markdown/bindings/. If
-- you add or rename a binding there, update the matching entry here.
--
-- Structure:
--   actions       — named functions on require("markdown").actions
--                   (the implementation surface; bind your own keys to these).
--   default_keys  — buffer-local defaults, installed on markdown filetypes.
--                     .editing         — bindings/keymaps.lua (gated by
--                                        enable_keymaps + the map_* /
--                                        use_zf_override flags).
--                     .tableview       — bindings/keymaps.lua (apply_tableview);
--                                        these trigger/close the TableView popup
--                                        from a markdown buffer.
--                     .tableview_popup — tableview/renderer.lua (ensure_view);
--                                        active ONLY inside the popup buffer
--                                        itself, not on markdown buffers.
--   commands      — user commands.
--                     .markdown      — the global :Markdown dispatcher.
--                     .buffer_local  — commands created per markdown buffer.
--   autocmds      — autocommands registered by setup().

return {
  actions = {
    {
      action = "toggle_bold_visual",
      mode = "v",
      desc = "Toggle **bold** on selection",
    },
    {
      action = "wrap_link_normal",
      mode = "n",
      desc = "Wrap word under cursor in a Markdown link",
    },
    {
      action = "wrap_link_visual",
      mode = "v",
      desc = "Wrap selection in a Markdown link",
    },
    { action = "prev_heading", mode = { "n", "v", "x" }, desc = "Previous H2+ heading" },
    { action = "next_heading", mode = { "n", "v", "x" }, desc = "Next H2+ heading" },
    {
      action = "prev_heading_level",
      mode = "n",
      desc = "Previous heading of level {count}",
    },
    {
      action = "next_heading_level",
      mode = "n",
      desc = "Next heading of level {count}",
    },
    {
      action = "fold_toggle",
      mode = "n",
      desc = "Toggle fold under cursor",
    },
    { action = "unfold_all", mode = "n", desc = "Unfold all, center" },
    {
      action = "fold_prev_heading",
      mode = "n",
      desc = "Fold previous heading, center",
    },
    {
      action = "fold_h2plus",
      mode = "n",
      desc = "Fold below H2 / unfold (toggle outline: keep H1+H2)",
    },
    {
      action = "toc",
      mode = "n",
      desc = "Insert/refresh TOC ({count} = max level)",
    },
    {
      action = "cursor_action",
      mode = "n",
      desc = "Open anchor/image/URL/file under cursor",
    },
    {
      action = "cursor_action_mouse",
      mode = "n",
      desc = "Same, silent on miss; heading -> fold toggle (mouse)",
    },
    { action = "open_image", mode = "n", desc = "Open image under cursor" },
    {
      action = "jump_anchor",
      mode = "n",
      desc = "Jump to anchor under cursor",
    },
    {
      action = "heading_inc",
      mode = "n",
      desc = "Increase heading level ({count} levels)",
    },
    {
      action = "heading_dec",
      mode = "n",
      desc = "Decrease heading level ({count} levels)",
    },
    {
      action = "heading_inc_visual",
      mode = { "v", "x" },
      desc = "Increase heading level, selection",
    },
    {
      action = "heading_dec_visual",
      mode = { "v", "x" },
      desc = "Decrease heading level, selection",
    },
    {
      action = "heading_inc_all",
      mode = "n",
      desc = "Increase all headings in buffer",
    },
    {
      action = "heading_dec_all",
      mode = "n",
      desc = "Decrease all headings in buffer",
    },
  },

  default_keys = {
    -- `id` is the stable key for config.keymaps[id] = false | "<lhs>" | { … }.
    editing = {
      {
        id = "toggle_bold",
        lhs = "**",
        mode = "v",
        action = "toggle_bold_visual",
        flag = "map_double_asterisk",
        desc = "Toggle bold",
      },
      {
        id = "wrap_link_n",
        lhs = "<leader>[",
        mode = "n",
        action = "wrap_link_normal",
        flag = "map_wrap_link",
        desc = "Wrap word in link",
      },
      {
        id = "wrap_link_v",
        lhs = "<leader>[",
        mode = "v",
        action = "wrap_link_visual",
        flag = "map_wrap_link",
        desc = "Wrap selection in link",
      },
      {
        id = "prev_heading",
        lhs = "<C-p>",
        mode = { "n", "v", "x" },
        action = "prev_heading",
        desc = "Prev heading",
      },
      {
        id = "prev_heading_bracket",
        lhs = "[[",
        mode = "n",
        action = "prev_heading",
        desc = "Prev heading",
      },
      {
        id = "next_heading",
        lhs = "<C-f>",
        mode = { "n", "v", "x" },
        action = "next_heading",
        desc = "Next heading",
      },
      {
        id = "next_heading_bracket",
        lhs = "]]",
        mode = "n",
        action = "next_heading",
        desc = "Next heading",
      },
      {
        id = "prev_heading_level",
        lhs = "<leader><C-p>",
        mode = "n",
        action = "prev_heading_level",
        desc = "Prev heading of level",
      },
      {
        id = "next_heading_level",
        lhs = "<leader><C-f>",
        mode = "n",
        action = "next_heading_level",
        desc = "Next heading of level",
      },
      {
        id = "fold_toggle_zf",
        lhs = "zf",
        mode = "n",
        action = "fold_toggle",
        flag = "use_zf_override",
        desc = "Fold toggle",
      },
      {
        id = "fold_toggle",
        lhs = "<localleader>f",
        mode = "n",
        action = "fold_toggle",
        desc = "Fold toggle",
      },
      {
        id = "unfold_all",
        lhs = "zu",
        mode = "n",
        action = "unfold_all",
        desc = "Unfold all",
      },
      {
        id = "fold_prev_heading",
        lhs = "zi",
        mode = "n",
        action = "fold_prev_heading",
        desc = "Fold prev heading",
      },
      {
        id = "fold_h2plus",
        lhs = "zk",
        mode = "n",
        action = "fold_h2plus",
        desc = "Fold below H2 (toggle outline)",
      },
      {
        id = "toc",
        lhs = "<leader>toc",
        mode = "n",
        action = "toc",
        desc = "Insert/refresh TOC",
      },
      {
        id = "cursor_action_2click",
        lhs = "<2-LeftMouse>",
        mode = "n",
        action = "cursor_action_mouse",
        desc = "Cursor action / heading fold (silent miss)",
      },
      {
        id = "cursor_action_cclick",
        lhs = "<C-LeftMouse>",
        mode = "n",
        action = "cursor_action_mouse",
        desc = "Cursor action (silent miss)",
      },
      {
        id = "cursor_action",
        lhs = "ma",
        mode = "n",
        action = "cursor_action",
        desc = "Cursor action",
      },
      {
        id = "open_image",
        lhs = "mi",
        mode = "n",
        action = "open_image",
        desc = "Open image",
      },
      {
        id = "jump_anchor",
        lhs = "mj",
        mode = "n",
        action = "jump_anchor",
        desc = "Jump to anchor",
      },
      {
        id = "heading_inc",
        lhs = "<C-Right>",
        mode = "n",
        action = "heading_inc",
        desc = "Increase heading level",
      },
      {
        id = "heading_dec",
        lhs = "<C-Left>",
        mode = "n",
        action = "heading_dec",
        desc = "Decrease heading level",
      },
      {
        id = "heading_inc_visual",
        lhs = "<C-Right>",
        mode = { "v", "x" },
        action = "heading_inc_visual",
        desc = "Increase heading level (visual)",
      },
      {
        id = "heading_dec_visual",
        lhs = "<C-Left>",
        mode = { "v", "x" },
        action = "heading_dec_visual",
        desc = "Decrease heading level (visual)",
      },
      {
        id = "heading_inc_all",
        lhs = "<S-Right>",
        mode = "n",
        action = "heading_inc_all",
        desc = "Increase all headings",
      },
      {
        id = "heading_dec_all",
        lhs = "<S-Left>",
        mode = "n",
        action = "heading_dec_all",
        desc = "Decrease all headings",
      },
      {
        id = "table_next_cell",
        lhs = "]|",
        mode = "n",
        action = "table_next_cell",
        feature = "table",
        desc = "Next table cell",
      },
      {
        id = "table_prev_cell",
        lhs = "[|",
        mode = "n",
        action = "table_prev_cell",
        feature = "table",
        desc = "Prev table cell",
      },
    },

    tableview = {
      {
        lhs = "<leader>tvt",
        mode = "n",
        cmd = "TableViewToggle",
        desc = "Toggle table preview (config default style)",
      },
      {
        lhs = "<leader>tvx",
        mode = "n",
        cmd = "TableViewBox",
        desc = "Toggle table preview (box-drawing style)",
      },
      {
        lhs = "<leader>tvs",
        mode = "n",
        cmd = "TableViewSelect",
        desc = "Select and preview table",
      },
      {
        lhs = "<leader>tvb",
        mode = "n",
        cmd = "TableViewOpenBrowser",
        desc = "Open table in browser (basic HTML)",
      },
      { lhs = "<leader>tvc", mode = "n", cmd = "TableViewClose", desc = "Close TableView" },
      {
        lhs = "<leader>tvm",
        mode = "n",
        cmd = "Markdown table mode toggle",
        desc = "Toggle table mode (auto-format)",
      },
    },

    -- Buffer-local to the TableView popup itself (tableview/renderer.lua),
    -- Normal mode only — NOT active on markdown buffers, and not gated by
    -- enable_keymaps (this popup has no "editing" surface to opt out of).
    -- h/j/k/l duplicate the arrow-key actions: some terminals/multiplexers
    -- intercept <M-Up>/<M-Down> before Neovim sees them.
    tableview_popup = {
      {
        lhs = "<M-Right>",
        mode = "n",
        fn = "resize_current_column(1)",
        desc = "Widen the column under the cursor",
      },
      {
        lhs = "<M-l>",
        mode = "n",
        fn = "resize_current_column(1)",
        desc = "Same (letter-key alternate)",
      },
      {
        lhs = "<M-Left>",
        mode = "n",
        fn = "resize_current_column(-1)",
        desc = "Narrow the column under the cursor (floors at natural content width)",
      },
      {
        lhs = "<M-h>",
        mode = "n",
        fn = "resize_current_column(-1)",
        desc = "Same (letter-key alternate)",
      },
      {
        lhs = "<M-Up>",
        mode = "n",
        fn = "move_current_row(-1)",
        desc = "Move the row under the cursor up (swap with the row above)",
      },
      {
        lhs = "<M-k>",
        mode = "n",
        fn = "move_current_row(-1)",
        desc = "Same (letter-key alternate)",
      },
      {
        lhs = "<M-Down>",
        mode = "n",
        fn = "move_current_row(1)",
        desc = "Move the row under the cursor down (swap with the row below)",
      },
      {
        lhs = "<M-j>",
        mode = "n",
        fn = "move_current_row(1)",
        desc = "Same (letter-key alternate)",
      },
      {
        lhs = ":w",
        mode = "n",
        fn = "write_back()",
        desc = "Write the current row order back to the source buffer/file (BufWriteCmd); column widening is never written back",
      },
    },
  },

  commands = {
    markdown = {
      {
        name = "Markdown links show [%|cwd|<file>]",
        desc = "Collect links, pick one, open it",
      },
      {
        name = "Markdown links create [-r] [--noignore] [--root <p>] <path>",
        desc = "Generate links from a dir tree to clipboard",
      },
      {
        name = "Markdown toc [level] [--sep|--no-sep]",
        desc = "Insert/refresh the TOC",
      },
      {
        name = "Markdown refs [sync|check|live [on|off|toggle]|baseline]",
        desc = "Sync #anchor links + TOC on heading rename",
      },
      {
        name = "Markdown table view [toggle|markdown|box|select|close|browser|browsernice] [scope]",
        desc = "Render table preview; scope=%|cwd|<path> or off-table cursor = every matching table, stacked",
      },
      {
        name = "Markdown table format [options]",
        desc = "GFM table formatter at cursor/in scope",
      },
      {
        name = "Markdown table new [cols] [rows]",
        desc = "Insert an empty GFM table template",
      },
      {
        name = "Markdown table mode [on|off|toggle]",
        desc = "Per-buffer table auto-format (vim-table-mode style)",
      },
      {
        name = "Markdown table tableize [format]",
        desc = "Convert delimited text (range) into a GFM table (csv/tsv/psv/space/…)",
      },
      {
        name = "Markdown render [on|off|toggle]",
        desc = "render-markdown.nvim wrapper (optional host)",
      },
      {
        name = "Markdown preview [start|stop|toggle]",
        desc = "markdown-preview.nvim wrapper (optional host)",
      },
      {
        name = "Markdown mdview [path]",
        desc = "Open a file directly via mdview.nvim (optional host)",
      },
      {
        name = "Markdown create fs",
        desc = "Create files/dirs for local link targets",
      },
      {
        name = "Markdown headline_spacing",
        desc = "Enforce blank-dash-blank between H2+ sections",
      },
      {
        name = "Markdown scope [on|off|toggle|status]",
        desc = "Toggle fenced-block scope (TOC/nav/jump/shift/fold act on the block the cursor is in)",
      },
      {
        name = "Markdown image [paste|screenshot]",
        desc = "Delegates to images.nvim's :Image paste/screenshot (optional host); default sub is paste",
      },
    },

    buffer_local = {
      { name = "OpenWithSystemApplication", desc = "Same as 'ma' — open target under cursor" },
      {
        name = "MarkdownNvimUnderlineHeadings",
        desc = "Underline every ATX heading's text with '=' (Setext-style decoration, idempotent)",
      },
      { name = "MDTableWrap", desc = "Wrap the table at the cursor (or every table, off any)" },
      { name = "MDTableUnwrap", desc = "Merge continuation rows back into one row each" },
      {
        name = "MDTableWrapVisual[!]",
        desc = "Wrap tables in the visual selection; ! unwraps first",
      },
      {
        name = "MDTableWrapVisible[!]",
        desc = "Wrap tables in the visible window range; ! unwraps first",
      },
      { name = "MDTableReflowHeader", desc = "Reflow only the header + separator; body untouched" },
      { name = "MDTableFoldRow", desc = "Fold the continuation block under the cursor" },
      { name = "MDTableFoldAll", desc = "Fold every continuation block in the buffer" },
      { name = "MDTableProfile {compact|docs|wide}", desc = "Load a named width-profile preset" },
      {
        name = "MDTableCol {inc|dec} [n]",
        desc = "Widen/narrow the column under the cursor, preserving row total width",
      },
      { name = "MDTableAlign {cycle|left|center|right}", desc = "Cycle/set the current column's alignment" },
      { name = "MDTableFlavor {github|loose}", desc = "Strict GFM vs. loose separator style" },
      { name = "MDTableLint", desc = "Flag table structural issues via vim.diagnostic" },
      { name = "MDTableFixMissingSeparator", desc = "Insert missing separator lines" },
      { name = "MDTableDebug", desc = "Print the resolved column-width plan" },
      { name = "MDTableToCSV [path]", desc = "Export the table at the cursor as CSV" },
      { name = "MDTableFromCSV [path]", desc = "Insert a GFM table parsed from CSV" },
      {
        name = "TableViewToggle",
        desc = "Toggle floating table preview (config default style)",
      },
      {
        name = "TableViewMarkdown",
        desc = "Toggle floating table preview (aligned Markdown style)",
      },
      {
        name = "TableViewBox",
        desc = "Toggle floating table preview (box-drawing style)",
      },
      { name = "TableViewSelect", desc = "Pick a table from the buffer" },
      { name = "TableViewClose", desc = "Close floating preview" },
      {
        name = "TableViewOpenBrowser [reopen]",
        desc = "Export table as basic HTML; reuses one tab across calls (auto-refreshing), 'reopen' forces a new tab",
      },
      {
        name = "TableViewOpenBrowserNice [reopen]",
        desc = "Export table as styled HTML; reuses one tab across calls (auto-refreshing), 'reopen' forces a new tab",
      },
    },
  },

  autocmds = {
    {
      event = "FileType",
      group = "MarkdownNvimKeymaps",
      pattern = "markdown/mdx/md/markdown.*",
      desc = "Install buffer-local keymaps (if enable_keymaps)",
    },
    {
      event = "FileType",
      group = "MarkdownNvimUserCommands",
      pattern = "markdown/mdx/md/markdown.*",
      desc = "Install buffer-local user commands",
    },
    {
      event = "FileType",
      group = "MarkdownNvimFold",
      pattern = "markdown/mdx/md/markdown.*",
      desc = "Set foldmethod=expr + fold options",
    },
    {
      event = "FileType/BufWritePre/TextChanged",
      group = "MarkdownNvimRefs",
      pattern = "markdown/mdx/md/markdown.*",
      desc = "refs sync per config.refs.mode (off|save|live)",
    },
    {
      event = "ColorScheme",
      group = "(hl_options)",
      pattern = "*",
      desc = "Re-apply blockquote / fenced-code highlights",
    },
  },
}
