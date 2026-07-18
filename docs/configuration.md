# Configuration

Full reference with defaults:

```lua
require("markdown_nvim").setup({
  -- Feature gating (see "Feature gating" below). Empty = everything on.
  features = {},

  -- Toggle ** mapping in visual mode
  map_double_asterisk    = true,

  -- Map <leader>[ to wrap the word/selection in a Markdown link
  map_wrap_link          = true,

  -- After toggling bold: keep the inner text selected (not the asterisks)
  keep_inner_selection   = true,

  -- Protect H1 from being shifted down
  protect_h1             = false,

  -- Override zf to fold under cursor (instead of Vim's operator)
  use_zf_override        = true,

  -- Install FileType autocmds (keymaps + user commands)
  enable_autocmds        = true,

  -- Install buffer-local keymaps (requires enable_autocmds = true)
  enable_keymaps         = true,

  -- Only activate for markdown filetypes
  ft_only                = true,

  -- Default on: TOC refresh also ensures [blank]---[blank] between H2+ sections
  -- (including a closing separator after the last section)
  ensure_headline_spacing = true,

  -- Per-binding keymap control by id (see docs/keymaps.md "Remapping / disabling"
  -- and docs/BINDINGS.lua). false disables; a string or { lhs, mode } remaps.
  keymaps = {},

  -- Inline-link highlight tweaks. Neovim's markdown treesitter underlines link
  -- URLs; long URLs then draw a full-width underline across the wrapped line.
  -- Default off; set underline = true to restore the built-in behaviour.
  link_hl = {
    underline = false,
  },

  -- Default float style for :Markdown table view toggle / <leader>tvt.
  -- "markdown" = aligned GFM table; "box" = Unicode spreadsheet grid. The
  -- explicit `view markdown` / `view box` actions always override this.
  tableview = {
    style = "markdown", -- "markdown" | "box"
  },

  -- Keep [text](#anchor) links + the TOC in sync when headings are renamed.
  -- Manual :Markdown refs sync|check work regardless of mode; `mode` only
  -- governs AUTOMATIC runs.
  refs = {
    mode        = "save",  -- "off" | "save" (on BufWritePre, default) | "live" (debounced)
    debounce_ms = 2000,    -- live-mode debounce; 1500–3000 is a sane range
    update_toc  = true,    -- refresh an existing TOC block on sync (never force-creates)
    orphans     = "report",-- "report" surfaces #anchor links with no heading; "ignore" skips
    toc_header  = "## Table of content",
  },

  -- :Markdown links show — picker backend: "hover_select" | "select"
  links = {
    picker = "hover_select",
  },

  -- How followed file targets open. Extensions in this list launch the system
  -- application (image viewer, PDF reader, …); everything else opens via :edit.
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

  -- Blockquote highlight colors
  blockquote_hl = {
    marker_fg   = "#6A9955",   -- color for the > token
    text_fg     = "#7EE787",   -- text after >
    text_bold   = true,
    text_italic = false,
  },

  -- Fenced-code / inline-code highlight override
  fenced_fix = {
    inline_base_hl = { "DiagnosticWarn", "Special", "Constant", "String" },
    inline_style   = { italic = false, bold = false },
    delimiter_hl   = "Comment",
  },

  -- Treat a markdown-family fenced block as its own document scope
  -- (see docs/fenced-scope.md).
  fenced_scope = {
    enable   = true, -- master switch (default on)
    langs    = { "markdown", "md", "mdx", "ascii-markdown", "ascii-md" },
    provider = "auto", -- "auto" | "color_my_ascii" | "builtin"
    operations = {     -- per-operation opt-out (all on by default)
      toc   = true,
      nav   = true,
      jump  = true,
      shift = true,
      fold  = true,    -- scope-aware foldexpr: a `#` inside a non-markdown fence won't fold
    },
  },
})
```

## Feature gating

Reduce the plugin to a subset without unsetting each option, via `features`:

```lua
require("markdown_nvim").setup({
  features = {
    -- disable = "all"                    -- turn every gateable feature off
    -- disable = { "tableview", "refs" }  -- turn off just these
    -- enable  = { "table" }              -- re-enable (applied after disable)
    just_enable = { "table", "toc" },     -- hard allowlist: ONLY these run
  },
})
```

Precedence: `just_enable` (if set) wins — only the listed features are on,
everything else off. Otherwise the resolver starts all-on, applies `disable`,
then re-applies `enable`. Unknown names emit a warning.

Gateable features: `keymaps`, `fold`, `hl`, `link_hl`, `fenced_fix`,
`fenced_scope`, `tableview`, `refs`, and the `:Markdown` subcommand features
`links`, `toc`, `table`, `render`, `preview`, `mdview`, `create`, `headline_spacing`,
`scope`. A disabled subcommand drops out of completion and reports if invoked;
disabled keymaps/autocmds are never installed. (The legacy `enable_keymaps` /
`enable_autocmds` flags still work alongside this.)
