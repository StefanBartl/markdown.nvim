-- docs/BINDINGS.md — markdown.nvim binding cheatsheet.
--
-- A single, machine-readable overview of every keymap, user command and
-- autocommand markdown.nvim defines. DOCUMENTATION only: not required at
-- runtime. It mirrors the source of truth in lua/markdown_nvim/bindings/. If
-- you add or rename a binding there, update the matching entry here.
--
-- Structure:
--   plug          — the stable <Plug>(markdown-*) surface (always defined).
--   default_keys  — buffer-local defaults, installed on markdown filetypes.
--                     .editing   — setup/keymaps.lua (gated by enable_keymaps
--                                  + the map_* / use_zf_override flags).
--                     .tableview — tableview/mappings.lua.
--   commands      — user commands.
--                     .markdown      — the global :Markdown dispatcher.
--                     .buffer_local  — commands created per markdown buffer.
--   autocmds      — autocommands registered by setup().

return {
  plug = {
    { lhs = "<Plug>(markdown-toggle-bold)",        mode = "v",            desc = "Toggle **bold** on selection" },
    { lhs = "<Plug>(markdown-wrap-link)",          mode = { "n", "v" },   desc = "Wrap word/selection in a Markdown link" },
    { lhs = "<Plug>(markdown-prev-heading)",       mode = { "n", "v", "x" }, desc = "Previous H2+ heading" },
    { lhs = "<Plug>(markdown-next-heading)",       mode = { "n", "v", "x" }, desc = "Next H2+ heading" },
    { lhs = "<Plug>(markdown-prev-heading-level)", mode = "n",            desc = "Previous heading of level {count}" },
    { lhs = "<Plug>(markdown-next-heading-level)", mode = "n",            desc = "Next heading of level {count}" },
    { lhs = "<Plug>(markdown-fold-toggle)",        mode = "n",            desc = "Toggle fold under cursor" },
    { lhs = "<Plug>(markdown-unfold-all)",         mode = "n",            desc = "Unfold all, center" },
    { lhs = "<Plug>(markdown-fold-prev-heading)",  mode = "n",            desc = "Fold previous heading, center" },
    { lhs = "<Plug>(markdown-fold-h2plus)",        mode = "n",            desc = "Fold H2+ (keep H1 open)" },
    { lhs = "<Plug>(markdown-toc)",                mode = "n",            desc = "Insert/refresh TOC ({count} = max level)" },
    { lhs = "<Plug>(markdown-cursor-action)",      mode = "n",            desc = "Open anchor/image/URL/file under cursor" },
    { lhs = "<Plug>(markdown-cursor-action-mouse)", mode = "n",           desc = "Same, but silent when nothing is found (mouse-triggered)" },
    { lhs = "<Plug>(markdown-open-image)",         mode = "n",            desc = "Open image under cursor" },
    { lhs = "<Plug>(markdown-jump-anchor)",        mode = "n",            desc = "Jump to anchor under cursor" },
    { lhs = "<Plug>(markdown-heading-inc)",        mode = { "n", "v", "x" }, desc = "Increase heading level ({count} levels)" },
    { lhs = "<Plug>(markdown-heading-dec)",        mode = { "n", "v", "x" }, desc = "Decrease heading level ({count} levels)" },
    { lhs = "<Plug>(markdown-heading-inc-all)",    mode = "n",            desc = "Increase all headings in buffer" },
    { lhs = "<Plug>(markdown-heading-dec-all)",    mode = "n",            desc = "Decrease all headings in buffer" },
  },

  default_keys = {
    editing = {
      { lhs = "**",              mode = "v",               rhs = "<Plug>(markdown-toggle-bold)",        flag = "map_double_asterisk", desc = "Toggle bold" },
      { lhs = "<leader>[",       mode = { "n", "v" },      rhs = "<Plug>(markdown-wrap-link)",          flag = "map_wrap_link",       desc = "Wrap in link" },
      { lhs = "<C-p>",           mode = { "n", "v", "x" }, rhs = "<Plug>(markdown-prev-heading)",       desc = "Prev heading" },
      { lhs = "[[",              mode = "n",               rhs = "<Plug>(markdown-prev-heading)",       desc = "Prev heading" },
      { lhs = "<C-f>",           mode = { "n", "v", "x" }, rhs = "<Plug>(markdown-next-heading)",       desc = "Next heading" },
      { lhs = "]]",              mode = "n",               rhs = "<Plug>(markdown-next-heading)",       desc = "Next heading" },
      { lhs = "<leader><C-p>",   mode = "n",               rhs = "<Plug>(markdown-prev-heading-level)", desc = "Prev heading of level" },
      { lhs = "<leader><C-f>",   mode = "n",               rhs = "<Plug>(markdown-next-heading-level)", desc = "Next heading of level" },
      { lhs = "zf",              mode = "n",               rhs = "<Plug>(markdown-fold-toggle)",        flag = "use_zf_override", desc = "Fold toggle" },
      { lhs = "<localleader>f",  mode = "n",               rhs = "<Plug>(markdown-fold-toggle)",        desc = "Fold toggle" },
      { lhs = "zu",              mode = "n",               rhs = "<Plug>(markdown-unfold-all)",         desc = "Unfold all" },
      { lhs = "zi",              mode = "n",               rhs = "<Plug>(markdown-fold-prev-heading)",  desc = "Fold prev heading" },
      { lhs = "zk",              mode = "n",               rhs = "<Plug>(markdown-fold-h2plus)",        desc = "Fold H2+" },
      { lhs = "<leader>toc",     mode = "n",               rhs = "<Plug>(markdown-toc)",                desc = "Insert/refresh TOC" },
      { lhs = "<2-LeftMouse>",   mode = "n",               rhs = "<Plug>(markdown-cursor-action-mouse)", desc = "Cursor action (silent miss)" },
      { lhs = "<C-LeftMouse>",   mode = "n",               rhs = "<Plug>(markdown-cursor-action-mouse)", desc = "Cursor action (silent miss)" },
      { lhs = "ma",              mode = "n",               rhs = "<Plug>(markdown-cursor-action)",      desc = "Cursor action" },
      { lhs = "mi",              mode = "n",               rhs = "<Plug>(markdown-open-image)",         desc = "Open image" },
      { lhs = "mj",              mode = "n",               rhs = "<Plug>(markdown-jump-anchor)",        desc = "Jump to anchor" },
      { lhs = "<C-Right>",       mode = { "n", "v", "x" }, rhs = "<Plug>(markdown-heading-inc)",        desc = "Increase heading level" },
      { lhs = "<C-Left>",        mode = { "n", "v", "x" }, rhs = "<Plug>(markdown-heading-dec)",        desc = "Decrease heading level" },
      { lhs = "<S-Right>",       mode = "n",               rhs = "<Plug>(markdown-heading-inc-all)",    desc = "Increase all headings" },
      { lhs = "<S-Left>",        mode = "n",               rhs = "<Plug>(markdown-heading-dec-all)",    desc = "Decrease all headings" },
    },

    tableview = {
      { lhs = "<leader>tvt", mode = "n", cmd = "TableViewToggle",     desc = "Toggle table preview at cursor" },
      { lhs = "<leader>tvs", mode = "n", cmd = "TableViewSelect",     desc = "Select and preview table" },
      { lhs = "<leader>tvb", mode = "n", cmd = "TableViewOpenBrowser", desc = "Open table in browser (basic HTML)" },
      { lhs = "<leader>tvc", mode = "n", cmd = "TableViewClose",      desc = "Close TableView" },
    },
  },

  commands = {
    markdown = {
      { name = "Markdown links show [%|cwd|<file>]",                    desc = "Collect links, pick one, open it" },
      { name = "Markdown links create [-r] [--noignore] [--root <p>] <path>", desc = "Generate links from a dir tree to clipboard" },
      { name = "Markdown toc [level] [--sep|--no-sep]",                desc = "Insert/refresh the TOC" },
      { name = "Markdown table view [toggle|select|close|browser|browsernice]", desc = "Drive the floating TableView" },
      { name = "Markdown table format [options]",                     desc = "GFM table formatter at cursor/in scope" },
      { name = "Markdown table new [cols] [rows]",                    desc = "Insert an empty GFM table template" },
      { name = "Markdown render [on|off|toggle]",                     desc = "render-markdown.nvim wrapper (optional host)" },
      { name = "Markdown preview [start|stop|toggle]",                desc = "markdown-preview.nvim wrapper (optional host)" },
      { name = "Markdown create fs",                                  desc = "Create files/dirs for local link targets" },
      { name = "Markdown headline_spacing",                           desc = "Enforce blank-dash-blank between H2+ sections" },
    },

    buffer_local = {
      { name = "OpenWithSystemApplication",  desc = "Same as 'ma' — open target under cursor" },
      { name = "TableViewToggle",            desc = "Toggle floating table preview at cursor" },
      { name = "TableViewSelect",            desc = "Pick a table from the buffer" },
      { name = "TableViewClose",             desc = "Close floating preview" },
      { name = "TableViewOpenBrowser",       desc = "Export table as basic HTML and open in browser" },
      { name = "TableViewOpenBrowserNice",   desc = "Export table as styled HTML and open in browser" },
    },
  },

  autocmds = {
    { event = "FileType",     group = "MarkdownNvimKeymaps",      pattern = "markdown/mdx/md/markdown.*", desc = "Install buffer-local keymaps (if enable_keymaps)" },
    { event = "FileType",     group = "MarkdownNvimUserCommands", pattern = "markdown/mdx/md/markdown.*", desc = "Install buffer-local user commands" },
    { event = "FileType",     group = "MarkdownNvimFold",         pattern = "markdown/mdx/md/markdown.*", desc = "Set foldmethod=expr + fold options" },
    { event = "BufWritePost", group = "(tableview.live)",         pattern = "markdown",                   desc = "Live table preview refresh" },
    { event = "ColorScheme",  group = "(hl_options)",             pattern = "*",                          desc = "Re-apply blockquote / fenced-code highlights" },
  },
}
