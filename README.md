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
| **link\_scan** | Collect every link in a line/buffer; powers `:Markdown links show` and `create fs` |
| **fenced\_scope** | Treat a ` ```markdown ` / `md` / `mdx` block as its own sub-document: TOC, heading nav, anchor jump and shift scope to the block your cursor is in (see below) |
| **:Markdown** | Unified command: `links`, `toc`, `refs`, `table`, `render`, `preview`, `create`, `headline_spacing`, `scope` |

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

  -- Inline-link highlight tweaks. Neovim's markdown treesitter underlines link
  -- URLs; long URLs then draw a full-width underline across the wrapped line.
  -- Default off; set underline = true to restore the built-in behaviour.
  link_hl = {
    underline = false,
  },

  -- Keep [text](#anchor) links + the TOC in sync when headings are renamed.
  -- Manual :Markdown refs sync|check work regardless of mode; `mode` only
  -- governs AUTOMATIC runs.
  refs = {
    mode        = "off",   -- "off" | "save" (on BufWritePre) | "live" (debounced)
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
| `zk` | n | Fold H2+ (keep H1 open) |

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

Every action is exposed as a stable `<Plug>(markdown-*)` mapping (see
[docs/BINDINGS.md](docs/BINDINGS.md) for the full list). To use your own keys,
set `enable_keymaps = false` and bind against the `<Plug>` names — the surface
stays available even with the defaults off:

```lua
require("markdown_nvim").setup({ enable_keymaps = false })

vim.keymap.set("n", "<C-n>", "<Plug>(markdown-next-heading)")
vim.keymap.set("n", "<C-p>", "<Plug>(markdown-prev-heading)")
vim.keymap.set("n", "gO",    "<Plug>(markdown-toc)")
```

If [which-key](https://github.com/folke/which-key.nvim) is installed, the
`<leader>t` prefix is labelled automatically (no config required).

### TableView

| Key | Mode | Action |
|-----|------|--------|
| `<leader>tvt` | n | Toggle table preview (floating) |
| `<leader>tvs` | n | Select table from list |
| `<leader>tvb` | n | Open table in browser (basic HTML) |
| `<leader>tvc` | n | Close TableView float |

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

Automatic runs are opt-in via `refs.mode` (`"off"` | `"save"` | `"live"`); the
manual commands work regardless. Live mode is debounced by `refs.debounce_ms`
(default 2000 ms) to keep it off the hot path.

### `:Markdown table`

```vim
:Markdown table view [toggle|select|close|browser|browsernice]
:Markdown table format [options]        " align columns / normalize separators
:Markdown table new [cols] [rows]        " insert an empty GFM table template
```

`view` drives the floating TableView (defaults to `toggle`). `format` runs the
self-contained GFM formatter on the table at the cursor / in scope.

### `:Markdown render` / `:Markdown preview`

```vim
:Markdown render  [on|off|toggle]        " render-markdown.nvim (optional host)
:Markdown preview [start|stop|toggle]    " markdown-preview.nvim (optional host)
```

Thin wrappers around the optional host plugins; they warn gracefully if the
plugin is not installed. `preview` also auto-refreshes on buffer switch while
active.

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

## Health

```vim
:checkhealth markdown_nvim
```

Reports the Neovim version, the cross-platform opener (`vim.ui.open`), config
sanity, the optional host plugins (`:Markdown render` / `preview`), the optional
`lib.nvim` / `which-key` integrations, and the `fenced_scope` state (enabled
ops + which fence-detection backend is active).

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
    renderer.lua           floating window renderer
    live.lua               live preview helper (started by :Markdown table ...)
    views/
      browser_basic.lua    basic HTML export
      browser_niceified.lua styled HTML export
      table_selector.lua   pick-a-table floating UI
  commands/
    init.lua               :Markdown dispatcher + nested completion
    links.lua              :Markdown links show|create
    markdown_links.lua     directory-to-link generator (links create)
    toc.lua                :Markdown toc (TOC + separators)
    table.lua              :Markdown table view|format|new
    render.lua             :Markdown render (render-markdown.nvim)
    preview.lua            :Markdown preview (markdown-preview.nvim)
    create.lua             :Markdown create fs
  bindings/                all keymaps, user commands and autocmds live here
    init.lua               orchestrator: setup(cfg)
    plugs.lua              <Plug>(markdown-*) surface
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
