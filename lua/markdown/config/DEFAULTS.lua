---@module 'markdown.config.DEFAULTS'
---@brief Immutable default configuration for markdown.nvim.
---@description
--- Single source of truth for every configurable value. `markdown.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.
--- Types (`Mkdn.Config` and friends) live in `markdown.@types`.

---@type Mkdn.Config
local DEFAULTS = {
  -- Feature gating. Reduce the plugin to a subset without unsetting each flag:
  --   disable = "all"                    -- turn every gateable feature off
  --   disable = { "tableview", "refs" }  -- turn off just these
  --   enable  = { "table" }              -- re-enable (applied after disable)
  --   just_enable = { "table", "toc" }   -- hard allowlist: ONLY these on
  -- just_enable wins over disable/enable. See config.features() for the names.
  features = {},

  map_double_asterisk = true,
  map_wrap_link = true,
  keep_inner_selection = true,
  protect_h1 = false,
  use_zf_override = true,
  enable_autocmds = true,
  enable_keymaps = true,
  ft_only = true,
  ensure_headline_spacing = true,

  -- `:MarkdownNvimUnderlineHeadings` (manual, buffer-local): the underline
  -- character drawn below each ATX heading's text, matching its length.
  underline_headings = {
    char = "=",
  },

  -- nvzone/menu integration (opt-in on the host side; entries provided by
  -- markdown.integrations.menu). Per-entry opt-out; set enable = false to
  -- provide no entries at all. See :help markdown.nvim (menu) if documented.
  menu = {
    enable = true,
    fold = true, -- fold/unfold entries (only shown on a heading)
    toc = true, -- Insert/Refresh TOC
    refs = true, -- Sync References
  },

  -- Per-binding keymap control, keyed by the stable ids in
  -- markdown.bindings.keymaps.defaults(). Each value may be:
  --   false                         -> disable this binding
  --   "<newlhs>"                    -> remap to a new key (same mode)
  --   { lhs = "<newlhs>", mode = … } -> remap key and/or mode
  -- Empty by default (every binding uses its documented default key).
  keymaps = {},

  -- Defaults for `:Markdown table format` / the GFM table formatter
  -- (core.table_fmt). Explicit command args (`header=`, `cell=`, `skip=`)
  -- always override these per call.
  table = {
    header_align = "center", -- "left" | "center" | "right"
    entry_align = "center",
    -- Per-column alignment overrides applied on every format. Unset by
    -- default; example:
    --   col_overrides = { { col = 1, align = "left" }, { col = "Name", align = "left" } }
    -- `col` may be a 1-based index or a header-cell name (case-insensitive).
  },

  -- Default style for the floating TableView (`:Markdown table view toggle` /
  -- <leader>tvt). "markdown" = aligned GFM table; "box" = Unicode box-drawing
  -- "spreadsheet" grid. The explicit `view markdown` / `view box` actions (and
  -- <leader>tvx) always override this default.
  tableview = {
    style = "markdown", -- "markdown" | "box"
  },

  -- `:Markdown links show` picker backend:
  --   "hover_select" — lib.nvim's float chooser (default)
  --   "select"       — vim.ui.select
  --   "telescope"    — nvim-telescope/telescope.nvim (soft dep)
  --   "fzf"          — ibhagwan/fzf-lua (soft dep)
  -- A requested backend whose plugin isn't installed falls back to
  -- vim.ui.select with a warning.
  links = {
    picker = "hover_select",
    -- Dead relative-file links / duplicate heading anchors, via vim.diagnostic
    -- (namespace "markdown_links"). ":Markdown links check" always works
    -- manually; mode = "save" also reruns it on BufWritePost.
    diagnostics = {
      mode = "off", -- "off" | "save"
    },
  },

  -- Following an image target (`mi`). When an in-Neovim preview provider is
  -- installed — snacks.nvim (`Snacks.image`) or image.nvim, both soft deps —
  -- `mi` can render the image in a floating window instead of handing it to
  -- the system viewer. With neither installed every value behaves like
  -- "system", since there is no alternative to choose between.
  --
  -- Mirrors how `handler/file.lua` treats PDFs when pdfport.nvim is present.
  image = {
    ---@type Mkdn.ImagePreviewMode
    preview = "ask", -- "ask" | "preview" | "system"
  },

  -- How followed file targets open. Media/binary extensions launch the system
  -- application; everything else (text-like) opens in the current window via
  -- :edit. Extend this list to taste.
  open = {
    external_extensions = {
      "png",
      "jpg",
      "jpeg",
      "gif",
      "bmp",
      "svg",
      "webp",
      "ico",
      "tif",
      "tiff",
      "pdf",
      "mp4",
      "mkv",
      "mov",
      "avi",
      "webm",
      "wmv",
      "flv",
      "mp3",
      "wav",
      "flac",
      "ogg",
      "m4a",
      "doc",
      "docx",
      "xls",
      "xlsx",
      "ppt",
      "pptx",
      "odt",
      "ods",
      "odp",
      "zip",
      "tar",
      "gz",
      "tgz",
      "7z",
      "rar",
      "exe",
      "msi",
      "dmg",
      "app",
    },
  },

  -- Fixed VS Code-style green by default, independent of the active
  -- colorscheme — some themes' Comment/String groups (the colorscheme-derived
  -- fallback) are muted greys/blues rather than green, which doesn't read as
  -- "quoted" the way VS Code's markdown coloring does. Override with your own
  -- hex to taste, or set marker_fg/text_fg to `false` to opt back into
  -- colorscheme-derived colors (markdown-specific highlight group first, then
  -- Comment/String, then this same hex as the last-resort fallback;
  -- re-derived on every ColorScheme event).
  blockquote_hl = {
    marker_fg = "#6A9955", -- the `>` token
    text_fg = "#7EE787", -- text after `>`
    text_bg = "dimm", -- whole line gets a dimmed bg derived from marker_fg
    text_bold = true,
    text_italic = false,
  },

  -- Inline-link highlight tweaks. Neovim's markdown treesitter underlines link
  -- URLs/labels; long URLs then draw a full-width underline across the wrapped
  -- line. Default off. Set underline = true to restore the built-in behaviour.
  link_hl = {
    underline = false,
  },

  -- Table of Contents: header text, bullet marker, and default heading-level
  -- range for `<leader>toc` / `:Markdown toc`. `:Markdown toc [level]` still
  -- overrides max_level per call; these are just the defaults.
  toc = {
    header = "## Table of content",
    marker = "-", -- bullet prefix for each entry, e.g. "-" or "*"
    min_level = 2,
    max_level = 4,
    -- Anchor slug style (shared with core.refs so links stay in sync):
    --   "gfm"       — GitHub-style: lowercase, non-word chars stripped (default)
    --   "keep-case" — same shape, original case preserved (some renderers keep it)
    anchor_style = "gfm",
    -- Separator between words in a generated anchor. Change only for renderers
    -- that don't use "-" (e.g. some static-site generators use "_").
    anchor_separator = "-",
  },

  -- Reference sync: keep `[text](#anchor)` links and the TOC consistent when
  -- headings are renamed. The manual `:Markdown refs sync` / `:Markdown refs
  -- check` commands work regardless of mode; `mode` only governs AUTOMATIC runs.
  refs = {
    -- "off"  — no automatic sync (manual commands only)
    -- "save" — reconcile on BufWritePre (default)
    -- "live" — reconcile debounced after edits (see debounce_ms)
    mode = "save",
    -- Live-mode debounce (ms). Deliberately generous: a rename is rare and a
    -- full buffer scan is cheap, but we never want to run it on every keystroke.
    -- 1500–3000 is a sane range.
    debounce_ms = 2000,
    -- Refresh an existing TOC block during a sync (never force-creates one).
    update_toc = true,
    -- "report" surfaces links whose #anchor matches no heading; "ignore" skips.
    orphans = "report",
    -- TOC header line to detect/refresh. Unset by default: falls back to
    -- `toc.header` above; only set this if refs should look for a DIFFERENT
    -- header than the one `:Markdown toc` itself generates.
    -- toc_header = "## Table of content",
  },

  fenced_fix = {
    inline_base_hl = { "DiagnosticWarn", "Special", "Constant", "String" },
    inline_style = { italic = false, bold = false },
    delimiter_hl = "Comment",
  },

  -- Treat a markdown-family fenced block (```markdown / md / mdx / ascii-markdown
  -- / ascii-md) as its own document scope: when the cursor is inside such a
  -- block, TOC/heading-nav/jump/shift operate on the block's interior instead of
  -- the whole file. When the cursor is outside, those ops treat the buffer as a
  -- whole but skip every fenced block's interior. Default on.
  --
  -- Fence detection is delegated to color_my_ascii (its parser is the robust
  -- shared source of truth); a small built-in scanner is used as a fallback when
  -- color_my_ascii isn't installed, so this stays usable standalone.
  fenced_scope = {
    enable = true,
    langs = { "markdown", "md", "mdx", "ascii-markdown", "ascii-md" },
    provider = "auto", -- "auto" | "color_my_ascii" | "builtin"
    operations = {
      toc = true,
      nav = true,
      jump = true,
      shift = true,
      fold = true, -- scope-aware foldexpr (a `#` inside a non-markdown fence won't fold)
    },
  },
}

return DEFAULTS
