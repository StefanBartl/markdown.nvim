# Configuration

Just want a ready-to-paste snippet for one specific thing (e.g. "turn off
the green blockquote coloring")? See [docs/templates/](templates/README.md)
instead — this page is the full reference.

Full reference with defaults:

```lua
require("markdown").setup({
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

  -- Heading navigation. fences = true: <C-p>/<C-f>/[[/]] also stop on a
  -- fenced block's opening and closing delimiter line. The by-level hops
  -- (<leader><C-p>/<leader><C-f>) stay headings-only either way.
  nav                    = { fences = true },

  -- Override zf to fold under cursor (instead of Vim's operator)
  use_zf_override        = true,

  -- Install FileType autocmds (keymaps + user commands)
  enable_autocmds        = true,

  -- Install buffer-local keymaps (requires enable_autocmds = true)
  enable_keymaps         = true,

  -- Only activate for markdown filetypes
  ft_only                = true,

  -- Default on: TOC refresh also ensures [blank]---[blank] between H2+ sections
  -- that have content (including a closing separator after the last section);
  -- a section with no text before the next heading just gets one blank line
  ensure_headline_spacing = true,

  -- Default on: TOC refresh also checks for skipped heading levels (e.g. an
  -- H1 followed directly by an H3) and offers to fix them immediately
  check_heading_gaps     = true,

  -- `:MarkdownNvimUnderlineHeadings` (manual, buffer-local): the underline
  -- character drawn below each ATX heading's text, matching its length.
  underline_headings = {
    char = "=",
  },

  -- nvzone/menu integration (opt-in on the host side; entries provided by
  -- markdown.integrations.menu). Per-entry opt-out; enable = false provides
  -- no entries at all.
  menu = {
    enable = true,
    fold   = true, -- fold/unfold entries (only shown on a heading)
    toc    = true, -- Insert/Refresh TOC
    refs   = true, -- Sync References
  },

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
    -- toc_header unset by default: falls back to toc.header below.
    -- toc_header = "## Table of content",
  },

  -- Table of Contents defaults for <leader>toc / :Markdown toc.
  -- `:Markdown toc [level|min=N|max=N|marker=X]` overrides per call, except
  -- anchor_style/anchor_separator (config-only, so core.refs always agrees
  -- with the TOC just generated).
  toc = {
    header    = "## Table of content",
    marker    = "-",           -- bullet prefix, e.g. "-" or "*"
    min_level = 2,
    max_level = 4,
    anchor_style     = "gfm",  -- "gfm" (default) | "keep-case"
    anchor_separator = "-",
  },

  -- :Markdown links show/check
  links = {
    -- picker backend: "hover_select" | "select" | "telescope" | "fzf"
    -- (telescope/fzf are soft deps; a missing plugin falls back to
    -- vim.ui.select with a warning)
    picker = "hover_select",
    -- Normalize inline-link targets before every write: backslashes become
    -- forward slashes, bare relative paths get a "./" prefix. URLs, anchors,
    -- absolute and ~-relative targets are left alone. :Markdown links
    -- sanitize runs the same pass on demand.
    sanitize_on_save = true,
    -- Dead relative-file links / duplicate heading anchors, via vim.diagnostic
    -- (namespace "markdown_links"). :Markdown links check always works
    -- manually; mode = "save" also reruns it on BufWritePost.
    diagnostics = {
      mode = "off", -- "off" | "save"
    },
  },

  -- :Markdown list [headings] [%|cwd|<file>]
  list = {
    -- picker backend, same values and fallback behavior as links.picker above
    picker = "hover_select",
  },

  -- Defaults for :Markdown table format; explicit command args (header=,
  -- cell=, skip=) always override these per call.
  table = {
    header_align = "center", -- "left" | "center" | "right"
    entry_align  = "center",
    -- col_overrides = { { col = 1, align = "left" }, { col = "Name", align = "left" } },
    -- Width-limited table wrapping (:MDTable* commands); off by default.
    -- See docs/table-wrap.md for the full option list, directives, profiles,
    -- and API hooks.
    wrap = { enabled = false, auto = false, min = 3, max = nil, pad = 1 },
    wrap_profiles = {
      compact = { auto = false, min = 4, max = 20, pad = 0 },
      docs    = { auto = true,  min = 10, max = 40, pad = 1 },
      wide    = { auto = true,  min = 15, max = nil, pad = 1 },
    },
  },

  -- Link/path hover preview under the cursor. See docs/hover.md for the full
  -- write-up — this is the same config, just placed in the "full reference"
  -- alongside everything else.
  hover = {
    enabled = true,
    -- "CursorHold" follows 'updatetime'. "mouse" additionally requires
    -- `:set mousemoveevent` (a global setting this plugin does not set for you).
    trigger              = { "CursorHold" },
    delay_ms             = 250,
    placeholder_grace_ms = 250, -- how long an async preview may take before a "rendering…" placeholder shows
    max_lines            = 20,
    max_width            = 80,
    border               = "rounded",
    -- Also hover a bare path with no link syntax — in prose, a code comment,
    -- a `:messages` dump. It must exist on disk to hover at all.
    bare_paths           = true,
    filetypes            = "*", -- which buffers get a hover; narrow to a filetype list to restrict it
    inline_images        = true, -- draw images/rasterized PDF pages into the float (needs images.nvim)
    url = {
      hover      = false, -- off by default: most of a markdown doc IS links
      fetch      = false, -- off by default: a hover that fetches discloses every link you brush past
      timeout_ms = 2000,
    },
    -- Office documents (.docx/.xlsx/.pptx/.odt, …) convert to PDF via
    -- pdfport.nvim + LibreOffice before previewing; off by default (LibreOffice
    -- startup costs seconds on the first conversion).
    office = {
      convert    = false,
      timeout_ms = 60000,
    },
  },

  -- Following an image target with `mi`. When an in-Neovim preview provider is
  -- installed — snacks.nvim (Snacks.image) or image.nvim, both soft deps —
  -- the image can be rendered in a floating window instead of being handed to
  -- the system viewer:
  --   "ask"     → prompt "System app" vs. "Preview in Neovim" (default)
  --   "preview" → always preview in Neovim, no prompt
  --   "system"  → always use the system viewer, no prompt (pre-option behaviour)
  -- With neither provider installed, every value behaves like "system".
  -- A remote (http/https) image always goes to the system handler, and a
  -- failed preview falls back to it too, so `mi` always shows the image.
  image = {
    preview = "ask",
  },

  -- How followed file targets open. Extensions in this list launch the system
  -- application (image viewer, PDF reader, …); everything else opens via :edit.
  -- Exception: "pdf" gets its own opener (markdown.handler.file.open_pdf) —
  -- if pdfport.nvim (github.com/StefanBartl/pdfport.nvim) is installed, you're
  -- asked "System app" vs. "pdfport (new buffer)" (the latter renders the PDF
  -- into a new buffer via pdfport's own backend fallback chain); without
  -- pdfport.nvim installed it opens via the system app directly, no prompt.
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

  -- Blockquote highlight colors. marker_fg/text_fg default to a fixed VS
  -- Code-style green, independent of the active colorscheme (some themes'
  -- Comment/String — the colorscheme-derived fallback — are muted greys/blues
  -- that don't read as "quoted"). Set either field to a hex color to override,
  -- or to `false` to opt back into colorscheme derivation (markdown-specific
  -- highlight group first, then Comment/String, then this same hex as the
  -- last-resort fallback; re-derived on every ColorScheme event). text_bg =
  -- "dimm" (the default) gives the whole quoted line a VS Code-style
  -- background — 20% of marker_fg mixed toward black, filled all the way to
  -- the window edge (not just behind the text characters) — set to a hex
  -- color or nil to override/disable.
  blockquote_hl = {
    marker_fg   = "#6A9955", -- color for the > token; false = colorscheme-derived
    text_fg     = "#7EE787", -- text after >; false = colorscheme-derived
    text_bg     = "dimm",
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
require("markdown").setup({
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
`scope`, `list`. A disabled subcommand drops out of completion and reports if invoked;
disabled keymaps/autocmds are never installed. (The legacy `enable_keymaps` /
`enable_autocmds` flags still work alongside this.)
