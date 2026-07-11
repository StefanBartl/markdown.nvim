---@module 'markdown_nvim.config.DEFAULTS'
---@brief Immutable default configuration for markdown.nvim.
---@description
--- Single source of truth for every configurable value. `markdown_nvim.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.
--- Types (`Mkdn.Config` and friends) live in `markdown_nvim.@types`.

---@type Mkdn.Config
local DEFAULTS = {
  -- Feature gating. Reduce the plugin to a subset without unsetting each flag:
  --   disable = "all"                    -- turn every gateable feature off
  --   disable = { "tableview", "refs" }  -- turn off just these
  --   enable  = { "table" }              -- re-enable (applied after disable)
  --   just_enable = { "table", "toc" }   -- hard allowlist: ONLY these on
  -- just_enable wins over disable/enable. See config.features() for the names.
  features = {},

  map_double_asterisk    = true,
  map_wrap_link          = true,
  keep_inner_selection   = true,
  protect_h1             = false,
  use_zf_override        = true,
  enable_autocmds        = true,
  enable_keymaps         = true,
  ft_only                = true,
  ensure_headline_spacing = true,

  -- nvzone/menu integration (opt-in on the host side; entries provided by
  -- markdown_nvim.integrations.menu). Per-entry opt-out; set enable = false to
  -- provide no entries at all. See :help markdown.nvim (menu) if documented.
  menu = {
    enable = true,
    fold   = true, -- fold/unfold entries (only shown on a heading)
    toc    = true, -- Insert/Refresh TOC
    refs   = true, -- Sync References
  },

  -- Per-binding keymap control, keyed by the stable ids in
  -- markdown_nvim.bindings.keymaps.defaults(). Each value may be:
  --   false                         -> disable this binding
  --   "<newlhs>"                    -> remap to a new key (same mode)
  --   { lhs = "<newlhs>", mode = … } -> remap key and/or mode
  -- Empty by default (every binding uses its documented default key).
  keymaps = {},

  -- Default style for the floating TableView (`:Markdown table view toggle` /
  -- <leader>tvt). "markdown" = aligned GFM table; "box" = Unicode box-drawing
  -- "spreadsheet" grid. The explicit `view markdown` / `view box` actions (and
  -- <leader>tvx) always override this default.
  tableview = {
    style = "markdown", -- "markdown" | "box"
  },

  -- `:Markdown links show` picker backend: "hover_select" | "select"
  -- ("select" uses vim.ui.select; telescope/fzf can be added later).
  links = {
    picker = "hover_select",
  },

  -- How followed file targets open. Media/binary extensions launch the system
  -- application; everything else (text-like) opens in the current window via
  -- :edit. Extend this list to taste.
  open = {
    external_extensions = {
      "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico", "tif", "tiff",
      "pdf",
      "mp4", "mkv", "mov", "avi", "webm", "wmv", "flv",
      "mp3", "wav", "flac", "ogg", "m4a",
      "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp",
      "zip", "tar", "gz", "tgz", "7z", "rar",
      "exe", "msi", "dmg", "app",
    },
  },

  blockquote_hl = {
    marker_fg  = "#6A9955",
    text_fg    = "#7EE787",
    text_bold  = true,
    text_italic = false,
  },

  -- Inline-link highlight tweaks. Neovim's markdown treesitter underlines link
  -- URLs/labels; long URLs then draw a full-width underline across the wrapped
  -- line. Default off. Set underline = true to restore the built-in behaviour.
  link_hl = {
    underline = false,
  },

  -- Reference sync: keep `[text](#anchor)` links and the TOC consistent when
  -- headings are renamed. The manual `:Markdown refs sync` / `:Markdown refs
  -- check` commands work regardless of mode; `mode` only governs AUTOMATIC runs.
  refs = {
    -- "off"  — no automatic sync (manual commands only)
    -- "save" — reconcile on BufWritePre (default)
    -- "live" — reconcile debounced after edits (see debounce_ms)
    mode        = "save",
    -- Live-mode debounce (ms). Deliberately generous: a rename is rare and a
    -- full buffer scan is cheap, but we never want to run it on every keystroke.
    -- 1500–3000 is a sane range.
    debounce_ms = 2000,
    -- Refresh an existing TOC block during a sync (never force-creates one).
    update_toc  = true,
    -- "report" surfaces links whose #anchor matches no heading; "ignore" skips.
    orphans     = "report",
    -- TOC header line to detect/refresh (matches the toc command default).
    toc_header  = "## Table of content",
  },

  fenced_fix = {
    inline_base_hl = { "DiagnosticWarn", "Special", "Constant", "String" },
    inline_style   = { italic = false, bold = false },
    delimiter_hl   = "Comment",
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
    enable   = true,
    langs    = { "markdown", "md", "mdx", "ascii-markdown", "ascii-md" },
    provider = "auto", -- "auto" | "color_my_ascii" | "builtin"
    operations = {
      toc   = true,
      nav   = true,
      jump  = true,
      shift = true,
      fold  = true, -- scope-aware foldexpr (a `#` inside a non-markdown fence won't fold)
    },
  },
}

return DEFAULTS
