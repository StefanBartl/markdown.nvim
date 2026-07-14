```
                         __       __
   ____ ___  ____ ______/ /______/ /___ _      ______
  / __ `__ \/ __ `/ ___/ //_/ __  / __ \ | /| / / __ \
 / / / / / / /_/ / /  / ,< / /_/ / /_/ / |/ |/ / / / /
/_/ /_/ /_/\__,_/_/  /_/|_|\__,_/\____/|__/|__/_/ /_/
            a self-contained markdown toolkit
```

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

> 💡 Pairs well with [cascade.nvim](https://github.com/StefanBartl/cascade.nvim):
> markdown.nvim renders and structures the document (TOC, folding, tables),
> while cascade.nvim edits the list content inside it (continue, renumber, rotate).

A self-contained Markdown toolkit for Neovim. Pure FileType-scoped — zero side
effects on non-Markdown buffers.

---

## Features

| Module | What it does |
|--------|-------------|
| **headings** | Navigate (prev/next, by level), shift levels (normal/visual/whole-buffer, count-aware) |
| **fold** | Custom `foldexpr` for ATX and Setext headings, fold/unfold helpers |
| **TOC** | Insert or refresh a Table of Contents with GFM-like anchors and de-dup |
| **wrap** | Toggle `**bold**` on visual selection |
| **wrap\_link** | `<leader>[` — wrap word/selection in a Markdown link, auto-detecting URL vs. text |
| **headline\_spacing** | Ensure `[blank]---[blank]` separator between H2+ sections (incl. final closer) |
| **fenced\_fix** | Highlight override: injected-language colors shine through fenced blocks; inline `code` gets a distinct style |
| **blockquote HL** | Two-region blockquote coloring (`>` marker + text) via `matchadd` |
| **anchor / jump** | Jump to `#heading` anchors (GFM slug, duplicate handling) |
| **handler** | Double-click / `<C-LeftMouse>` / `ma`: open TOC links, HTML anchors, images; URLs in browser; media/binary in system app; text files via `:edit` |
| **tableview** | Floating Markdown table browser; HTML export (basic + styled) |
| **table\_fmt** | GFM table formatter (align columns, normalize separators) — self-contained |
| **table\_mode** | Auto-format table mode, `tableize`, cell motions — a dependency-free vim-table-mode core |
| **link\_scan** | Collect every link in a line/buffer; powers `:Markdown links show` and `create fs` |
| **fenced\_scope** | Treat a ` ```markdown ` / `md` / `mdx` block as its own sub-document: TOC, heading nav, anchor jump and shift scope to the block your cursor is in (see below) |
| **:Markdown** | Unified command: `links`, `toc`, `refs`, `table`, `render`, `preview`, `mdview`, `create`, `headline_spacing`, `scope` |

---

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **>= 0.9** | core |

No external tools required. All features run on built-in Neovim APIs.

---

## Installation

The plugin is FileType-scoped, so `ft = { "markdown", "mdx", "md" }` is the
natural lazy trigger. Use `lazy = false` / eager loading only if you want the
`:Markdown` command available before opening a Markdown buffer.

### lazy.nvim

```lua
{
  "StefanBartl/markdown.nvim",
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown_nvim").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "StefanBartl/markdown.nvim",
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown_nvim").setup()
  end,
})
```

### vim-plug

```vim
Plug 'StefanBartl/markdown.nvim', { 'for': ['markdown', 'mdx', 'md'] }
```

```lua
require("markdown_nvim").setup()
```

---

## Configuration

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

  -- Per-binding keymap control by id (see "Remapping / disabling" and
  -- docs/BINDINGS.md). false disables; a string or { lhs, mode } remaps.
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

  -- Treat a markdown-family fenced block as its own document scope (see below).
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

### Feature gating

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

---

## Keymaps (all buffer-local, Markdown only)

### Navigation

| Key | Mode | Action |
|-----|------|--------|
| `<C-p>` / `[[` | n / v / x | Previous H2+ heading |
| `<C-f>` / `]]` | n / v / x | Next H2+ heading |
| `{count}<leader><C-p>` | n | Previous heading of level `count` |
| `{count}<leader><C-f>` | n | Next heading of level `count` |

### Heading level shift

A `{count}` prefix shifts by that many levels (e.g. `2<C-Right>`).

| Key | Mode | Action |
|-----|------|--------|
| `<C-Right>` | n | Increase level of current line |
| `<C-Left>`  | n | Decrease level of current line |
| `<C-Right>` | v / x | Increase level of selection (existing headings only) |
| `<C-Left>`  | v / x | Decrease level of selection |
| `<S-Right>` | n | Increase all headings in buffer |
| `<S-Left>`  | n | Decrease all headings in buffer |

### Folding

| Key | Mode | Action |
|-----|------|--------|
| `zf` / `<localleader>f` | n | Toggle fold under cursor |
| `zu` | n | Unfold all, center |
| `zi` | n | Fold previous heading then center |
| `zk` | n | Fold below H2 / unfold — toggle outline (keep H1 + H2 open) |

Use `set foldmethod=expr foldexpr=v:lua.require('markdown_nvim').foldexpr(v:lnum)`
in your config, or let the plugin handle it via the FileType autocmd.

### TOC

| Key | Mode | Action |
|-----|------|--------|
| `{count}<leader>toc` | n | Insert/refresh TOC; `count` = max heading level |

### Cursor action handler

| Key | Mode | Action |
|-----|------|--------|
| `<2-LeftMouse>` | n | Open anchor / image / URL / file under cursor |
| `<C-LeftMouse>` | n | Same |
| `ma` | n | Same |
| `mi` | n | Open image under cursor |
| `mj` | n | Jump to anchor under cursor |

### Bold wrap / link wrap

| Key | Mode | Action |
|-----|------|--------|
| `**` | v | Toggle `**bold**` on selection |
| `<leader>[` | n | Wrap word under cursor in a Markdown link |
| `<leader>[` | v | Wrap selection in a Markdown link |

`<leader>[` auto-detects the inner text: a URL or file path lands in the
`(target)` part (cursor jumps into `[]`), plain text lands in the `[text]`
part (cursor jumps into `()`). On empty space it inserts an empty `[]()`.

### Remapping / disabling

**Per-binding, in config (recommended).** Every default key has a stable `id`
(see the `editing` list in [docs/BINDINGS.md](docs/BINDINGS.md)). Set
`keymaps[id]` to disable or remap just that one — everything else keeps its
default:

```lua
require("markdown_nvim").setup({
  keymaps = {
    jump_anchor = false,            -- disable this binding entirely
    toc         = "<leader>T",      -- remap to a new key (same mode)
    fold_toggle = { lhs = "<F2>" }, -- table form; may also override `mode`
  },
})
```

`enable_keymaps = false` still turns off **all** default keys at once. The
legacy flags (`map_double_asterisk`, `map_wrap_link`, `use_zf_override`) keep
working too.

**Free-form, against the actions API.** Every action is also a plain function
on `require("markdown_nvim").actions`, so you can bind anything by hand — no
`<Plug>` indirection:

```lua
local a = require("markdown_nvim").actions
vim.keymap.set("n", "<C-n>", a.next_heading, { desc = "Next heading" })
vim.keymap.set("n", "gO",    a.toc,          { desc = "Insert/refresh TOC" })
```

If [which-key](https://github.com/folke/which-key.nvim) is installed, the
`<leader>t` prefix is labelled automatically (no config required).

### TableView

| Key | Mode | Action |
|-----|------|--------|
| `<leader>tvt` | n | Toggle table preview (floating, Markdown style) |
| `<leader>tvx` | n | Toggle table preview (box-drawing / spreadsheet style) |
| `<leader>tvs` | n | Select table from list |
| `<leader>tvb` | n | Open table in browser (basic HTML) |
| `<leader>tvc` | n | Close TableView float |
| `<leader>tvm` | n | Toggle table mode (auto-format) |
| `]\|` / `[\|` | n | Next / previous table cell |

Column widths are computed from screen-display width (`vim.fn.strdisplaywidth`),
not byte length, so cells containing multi-byte UTF-8 (umlauts, em dashes,
curly quotes, arrows, …) still line up — see `renderer.validate_alignment()`
in [Architecture](#architecture) if you want to verify a rendered table's `|`
columns programmatically instead of eyeballing it.

---

## Commands

Everything is funnelled through a single `:Markdown` command with subcommands.
The command supports a range, so visual selections are honoured where relevant.
Tab-completion works for every level (`:Markdown <Tab>`, `:Markdown table <Tab>`, …).

### `:Markdown links`

```vim
:Markdown links show [%|cwd|<file>]      " collect links, pick one, open it
:Markdown links create [-r] [--noignore] [--root <path>] <path>
```

- **show** — scan the current buffer (`%`, the default), the cwd, or a given
  file for links, list them in a picker, and open the chosen one (URL → browser,
  `#anchor` → in-buffer jump, file → system app or `:edit`).
- **create** — generate Markdown links from a directory tree and copy them to
  the clipboard. Options: `-r`/`--recursive`, `--noignore`,
  `--root <path>` (prefix, supports `$ENV_VAR`).
  A bare path without a subcommand is treated as `create <path>`.

### `:Markdown toc`

```vim
:Markdown toc [level] [--sep | --no-sep]
```

Insert/refresh the TOC. `level` caps the max heading depth. By default the
headline separators are applied too (per `ensure_headline_spacing`); override
per-call with `--sep` / `--no-sep`.

### `:Markdown refs`

Keep in-document `[text](#anchor)` links and the TOC consistent when headings
are renamed. Heading identity is tracked with extmarks (plus a positional
fallback), so a rename is detected as `old-anchor → new-anchor` and propagated
to every inline link and the TOC.

```vim
:Markdown refs sync                 " reconcile now: propagate renames + refresh TOC + report orphans
:Markdown refs check                " dry run: list broken #anchor links in the quickfix list
:Markdown refs live [on|off|toggle] " per-buffer debounced live tracking
:Markdown refs baseline             " re-snapshot heading anchors (reset rename tracking)
```

Automatic runs are governed by `refs.mode` (`"save"` — the default — reconciles
on `BufWritePre`; `"live"` reconciles debounced after edits; `"off"` disables
automatic runs). The manual commands work regardless. Live mode is debounced by
`refs.debounce_ms` (default 2000 ms) to keep it off the hot path.

### `:Markdown table`

The single namespace for every table action — preview, format, and a focused,
dependency-free reimplementation of the vim-table-mode essentials.

```vim
:Markdown table view [toggle|markdown|box|select|close|browser|browsernice] [scope]
:Markdown table format [options]        " align columns / normalize separators
:Markdown table new [cols] [rows]        " insert an empty GFM table template
:Markdown table mode [on|off|toggle]    " auto-format the table you're editing
:Markdown table tableize [delimiter]    " turn delimited text into a GFM table
```

- **view** renders a table (or every table) in a nicely formatted preview.
  `toggle` uses the configured default style (`tableview.style`, default
  `markdown`); `markdown` / `box` force the aligned-Markdown or Unicode
  box-drawing "spreadsheet" style; `browser` / `browsernice` open it as basic /
  GitHub-styled HTML in the system browser. `select` picks a table from a list;
  `close` closes the float (also `q` / `<Esc>` inside it).

  `toggle` / `markdown` / `box` accept an optional `scope`:
  | scope | Shows |
  |---|---|
  | *(none)* | The table at the cursor; off any table, falls back to every table in the current buffer |
  | `%` | Every table in the current buffer, even with the cursor on one |
  | `cwd` | Every table in every `*.md` file under the working directory (recursive) |
  | `<path>` | Every table in that file, or — if `<path>` is a directory — every table in every `*.md` file under it (recursive) |

  Multiple tables render stacked one after another, separated by a blank line
  and a label (`── Table i/N (line L) ──`, or `── path:line (Table i/N) ──`
  when the table came from a file on disk rather than the current buffer).
  Tab-completion on the scope argument offers `%`, `cwd`, and path completion.
  Same via the buffer-local commands directly: `:TableViewToggle`,
  `:TableViewToggle %`, `:TableViewBox cwd`, `:TableViewToggle ./docs`, …
- **format** runs the self-contained GFM formatter on the table at the cursor /
  in scope.
- **mode** turns on per-buffer *table mode*: after each edit inside a table it is
  re-aligned automatically (debounced, on `InsertLeave` / `TextChanged`), reusing
  the same alignment as `format`.
- **tableize** converts the current line (or a `:'<,'>` visual range) of
  delimited text into a GFM table — the delimiter is auto-detected (tab, comma,
  or runs of 2+ spaces) or given explicitly (`:Markdown table tableize ";"`).

Cell motions `[|` / `]|` jump to the previous / next cell on the current row.
Everything lives under the `table` feature, and stays available when only the
`tableview` feature is enabled, so the table stack works standalone.

### `:Markdown render` / `:Markdown preview` / `:Markdown mdview`

```vim
:Markdown render  [on|off|toggle]        " render-markdown.nvim (optional host)
:Markdown preview [start|stop|toggle]    " markdown-preview.nvim (optional host)
:Markdown mdview   [path]                " mdview.nvim (optional host)
```

Thin wrappers around the optional host plugins; they warn gracefully if the
plugin is not installed. `preview` also auto-refreshes on buffer switch while
active. `mdview` opens `path` (default: the current buffer's file) directly in
the browser via [mdview.nvim](https://github.com/StefanBartl/mdview.nvim)'s
`:MDViewStart`, which starts a session or — if one is already running — pushes
the file and re-opens the preview surface for it. It only does anything when
mdview.nvim is actually installed and loaded; `:checkhealth markdown_nvim`
reports whether it was detected.

### `:Markdown create`

```vim
:Markdown create fs                      " create files/dirs for local link targets
```

Walks the markdown-link targets in the range (visual selection) or the whole
buffer and creates the corresponding files/directories. Trailing `/` ⇒ directory.
URLs, `mailto:` and `#anchors` are skipped; existing paths are left untouched.

### `:Markdown headline_spacing`

```vim
:Markdown headline_spacing               " enforce blank-dash-blank between H2+ sections
```

### `:Markdown scope`

```vim
:Markdown scope toggle                   " toggle fenced-block scope (see "Fenced-block scope")
:Markdown scope on                       " force on
:Markdown scope off                      " force off
:Markdown scope status                   " report current state
```

### Buffer-local commands (Markdown buffers only)

```vim
:OpenWithSystemApplication   " same as 'ma' - open target under cursor

:TableViewToggle             " toggle floating table preview at cursor
:TableViewSelect             " pick a table from the buffer
:TableViewClose              " close floating preview
:TableViewOpenBrowser        " export table as basic HTML and open in browser
:TableViewOpenBrowserNice    " export table as styled HTML and open in browser
```

---

## Fenced-block scope

A Markdown document often embeds *another* Markdown document inside a fenced
block — a `` ```markdown `` example, an `ascii-md` snippet, an `mdx` sample.
With `fenced_scope` enabled (the default), those blocks become their own
**document scope**: when your cursor is inside one, the heading-aware operations
act on the block's interior instead of the whole file; when your cursor is
outside, they act on the file but skip every fenced block's interior.

````markdown
## Some Headline

```markdown
# Start
## Second headline
### A level-3 heading
## Back to level 2
```
````

- **`<leader>toc`** inside the block inserts/refreshes a TOC **inside** the
  block (its own headings only). Outside, the outer TOC no longer picks up
  headings that live inside fenced blocks.
- **Heading nav** (`<C-f>`/`<C-p>`, `[[`/`]]`, `<leader><C-f>`/`<leader><C-p>`
  with a count) stays within the block; outside, it jumps *over* fenced blocks
  instead of landing on code lines.
- **Anchor jump** (`mj`) resolves within the block.
- **Shift-all** (`<S-Right>`/`<S-Left>`) shifts only the block's headings.

### Configuration

| Key | Default | Meaning |
|-----|---------|---------|
| `enable` | `true` | Master switch. Off ⇒ every op reverts to its whole-buffer behavior. |
| `langs` | `{ "markdown", "md", "mdx", "ascii-markdown", "ascii-md" }` | Fence tags that count as a Markdown sub-document. |
| `provider` | `"auto"` | Fence-detection backend. `"auto"` uses [color_my_ascii](https://github.com/StefanBartl/color_my_ascii.nvim)'s fence API when present, else a built-in scanner. |
| `operations` | all on | Per-op opt-out (`toc`, `nav`, `jump`, `shift`, `fold`). `fold` makes a `#` inside a non-markdown fence not open a fold. |

### Toggle at runtime

```vim
:Markdown scope on
:Markdown scope off
:Markdown scope toggle
:Markdown scope status
```

### Provider & nesting notes

- **color_my_ascii (optional, recommended).** When installed, its robust
  heuristic + treesitter fence detection is used as the source of truth. It's a
  *soft* dependency: markdown.nvim ships a small built-in fence scanner and works
  without it — install it for the most accurate detection. `:checkhealth
  markdown_nvim` reports which backend is active.
- **Nesting.** To nest a fenced block *inside* a `` ```markdown `` block, the
  outer fence must be longer (CommonMark rule), e.g. open the outer block with
  ```` ````markdown ````. The detector honours fence length, matching CommonMark.

---

## Menu (nvzone/menu)

markdown.nvim ships context-aware entries for [nvzone/menu](https://github.com/nvzone/menu)
but does **not** depend on it. The plugin *owns* its entries; a host composes
them. Entries are context-aware — the fold actions only appear on a heading —
and opt-out via `config.menu`:

```lua
menu = {
  enable = true,
  fold   = true, -- Fold/Unfold Heading, Fold below H2 (toggle), Unfold All (on a heading)
  toc    = true, -- Insert/Refresh TOC
  refs   = true, -- Sync References
}
```

Wire it into your menu dispatcher — get a ready entry list (or a `Markdown ▸`
submenu) and compose it with your own menu:

```lua
local md = require("markdown_nvim.integrations.menu")

-- inline entries for the current context (empty table when nothing applies):
local items = md.items()               -- { { name, cmd, rtxt }, … }

-- or a single fly-out entry:
local sub = md.submenu()               -- { name = "  Markdown", items = {…} } | nil

-- e.g. in a RightMouse handler for markdown buffers:
--   local composed = vim.list_extend(md.items(), require("menus.custom"))
--   require("menu").open(composed, { mouse = true })
```

---

## Health

```vim
:checkhealth markdown_nvim
```

Reports the Neovim version, the cross-platform opener (`vim.ui.open`), config
sanity, the optional host plugins (`:Markdown render` / `preview` / `mdview`),
the optional `lib.nvim` / `which-key` integrations, and the `fenced_scope`
state (enabled ops + which fence-detection backend is active).

---

## Architecture

```
lua/markdown_nvim/
  init.lua                 setup() + public Lua facade
  config/
    init.lua               runtime store (setup/get)
    DEFAULTS.lua           typed default configuration
  health.lua               :checkhealth markdown_nvim
  util/
    notify.lua             vim.notify wrapper
    clipboard.lua          setreg("+") helper
    ignore.lua             default directory ignore list
    picker.lua             hover_select / vim.ui.select abstraction
  core/
    headings.lua           navigation + level shifting
    fold.lua               foldexpr, toggle, unfold
    fold_levels.lua        fold by heading level
    fold_prev.lua          fold previous heading
    toc.lua                TOC generator (GFM slugs, de-dup)
    wrap.lua               visual bold toggle
    wrap_link.lua          <leader>[ wrap word/selection in a link
    link_scan.lua          collect links from a line/buffer
    table_fmt.lua          GFM table formatter (self-contained)
    table_mode.lua         auto-format mode, tableize, cell motions
    slug.lua               shared GFM slug + anchor map (toc + refs)
    headline_spacing/
      init.lua             ensure blank-dash-blank between H2+ sections (+ final closer)
  anchor/
    is_anchor_line.lua
    is_html_anchor_line.lua
    is_html_extern_anchor_line.lua
    is_inside_toc_block.lua
    jump.lua               jump to #anchor under cursor
  handler/
    init.lua               cursor-action dispatcher
    image.lua              open image (system viewer)
    url.lua                open URL (system browser)
    file.lua               open file (system viewer / :edit)
  fenced_fix/
    init.lua               fenced-code + inline-code HL override
  hl_options/
    init.lua               orchestrator; re-applies on ColorScheme
    hl_groups/
      blockquote.lua       matchadd-based blockquote coloring
  tableview/
    parser.lua             pipe-table parser
    renderer.lua           floating window renderer (Markdown + box style);
                            widths use display-width, not byte length;
                            validate_alignment(lines) checks a rendered
                            table's | / │ dividers actually line up
    views/
      browser_basic.lua    basic HTML export
      browser_niceified.lua styled HTML export
      table_selector.lua   pick-a-table floating UI
  commands/
    init.lua               :Markdown dispatcher + nested completion
    links.lua              :Markdown links show|create
    markdown_links.lua     directory-to-link generator (links create)
    toc.lua                :Markdown toc (TOC + separators)
    refs.lua               :Markdown refs sync|check|live|baseline
    table.lua              :Markdown table view|format|new
    render.lua             :Markdown render (render-markdown.nvim)
    preview.lua            :Markdown preview (markdown-preview.nvim)
    mdview.lua             :Markdown mdview (mdview.nvim)
    create.lua             :Markdown create fs
  bindings/                all keymaps, user commands and autocmds live here
    init.lua               orchestrator: setup(cfg)
    actions.lua            named editing actions (public via .actions)
    keymaps.lua            buffer-local default keys (editing + TableView)
    usrcmds.lua            :Markdown + OpenWith + TableView* command registration
    autocmds.lua           FileType / BufWritePost drivers
    which_key.lua          optional which-key group labels (guarded)
plugin/
  markdown_nvim.lua        guard (vim.g.loaded_markdown_nvim)
doc/
  markdown.nvim.txt        :h markdown.nvim vim help file
docs/
  BINDINGS.md             machine-readable binding cheatsheet
  ROADMAP.md               planned work
  TESTS/                   headless spec suite
```
