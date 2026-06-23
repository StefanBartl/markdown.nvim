# markdown.nvim

```
  __  __         _       _
 |  \/  |__ _ _ | |_____| |_____ __ ___ _
 | |\/| / _` | '_| / / -_) / (_-</ _` \ V /
 |_|  |_\__,_|_| |_\_\___|_\_/__/\__,_|\_/
              nvim
```

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

A self-contained Markdown toolkit for Neovim. Pure FileType-scoped — zero side
effects on non-Markdown buffers.

---

## Features

| Module | What it does |
|--------|-------------|
| **headings** | Navigate (prev/next, by level), shift levels (normal/visual/whole-buffer) |
| **fold** | Custom `foldexpr` for ATX and Setext headings, fold/unfold helpers |
| **TOC** | Insert or refresh a Table of Contents with GFM-like anchors and de-dup |
| **wrap** | Toggle `**bold**` on visual selection |
| **headline\_spacing** | Ensure `[blank]---[blank]` separator between H2+ sections |
| **fenced\_fix** | Highlight override: injected-language colors shine through fenced blocks; inline `code` gets a distinct style |
| **blockquote HL** | Two-region blockquote coloring (`>` marker + text) via `matchadd` |
| **anchor / jump** | Jump to `#heading` anchors (GFM slug, duplicate handling) |
| **handler** | Double-click / `<C-LeftMouse>` / `ma`: open TOC links, HTML anchors, images, URLs, local files |
| **tableview** | Floating Markdown table browser; HTML export (basic + styled) via `:TableViewOpenBrowser*` |
| **:Markdown links** | Generate Markdown links from a directory tree and copy to clipboard |

---

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **>= 0.9** | core |

No external tools required. All features run on built-in Neovim APIs.

---

## Installation

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

### Local development

```lua
{
  dir = "E:/repos/markdown.nvim",
  ft  = { "markdown", "mdx", "md" },
  config = function()
    require("markdown_nvim").setup()
  end,
}
```

---

## Configuration

Full reference with defaults:

```lua
require("markdown_nvim").setup({
  -- Toggle ** mapping in visual mode
  map_double_asterisk    = true,

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

  -- Automatically ensure [blank]---[blank] between H2+ sections on save
  ensure_headline_spacing = true,

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
})
```

---

## Keymaps (all buffer-local, Markdown only)

### Navigation

| Key | Mode | Action |
|-----|------|--------|
| `<C-p>` / `[[` | n | Previous H2+ heading |
| `<C-f>` / `]]` | n | Next H2+ heading |
| `{count}<leader><C-p>` | n | Previous heading of level `count` |
| `{count}<leader><C-f>` | n | Next heading of level `count` |

### Heading level shift

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

### Bold wrap

| Key | Mode | Action |
|-----|------|--------|
| `**` | v | Toggle `**bold**` on selection |

### TableView

| Key | Mode | Action |
|-----|------|--------|
| `<leader>tvt` | n | Toggle table preview (floating) |
| `<leader>tvs` | n | Select table from list |
| `<leader>tvb` | n | Open table in browser (basic HTML) |
| `<leader>tvc` | n | Close TableView float |

---

## Commands

### Global

```vim
:Markdown links [-r] [--noignore] [--root <path>] <path>
```

Generate Markdown links from a directory tree and copy them to the clipboard.

Options:
- `-r` / `--recursive` — include sub-directories
- `--noignore` — do not apply the default ignore list
- `--root <path>` — prefix all paths with this root (supports `$ENV_VAR`)

### Buffer-local (Markdown buffers only)

```vim
:OpenWithSystemApplication   " same as 'ma' - open target under cursor

:TableViewToggle             " toggle floating table preview at cursor
:TableViewSelect             " pick a table from the buffer
:TableViewClose              " close floating preview
:TableViewOpenBrowser        " export table as basic HTML and open in browser
:TableViewOpenBrowserNice    " export table as styled HTML and open in browser
```

---

## Architecture

```
lua/markdown_nvim/
  init.lua                 setup() + public Lua facade
  config.lua               merged defaults
  util/
    notify.lua             vim.notify wrapper
    clipboard.lua          setreg("+") helper
    ignore.lua             default directory ignore list
  core/
    headings.lua           navigation + level shifting
    fold.lua               foldexpr, toggle, unfold
    fold_levels.lua        fold by heading level
    fold_prev.lua          fold previous heading
    toc.lua                TOC generator (GFM slugs, de-dup)
    wrap.lua               visual bold toggle
    headline_spacing/
      init.lua             ensure blank-dash-blank between H2+ sections
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
    init.lua               setup (autocmds)
    autocmds.lua           FileType autocmd -> install maps + commands
    mappings.lua           buffer-local keymaps
    commands.lua           buffer-local user commands
    parser.lua             pipe-table parser
    renderer.lua           floating window renderer
    live.lua               BufWritePost-based live preview helper
    views/
      browser_basic.lua    basic HTML export
      browser_niceified.lua styled HTML export
      table_selector.lua   pick-a-table floating UI
  commands/
    init.lua               :Markdown dispatcher + completion
    markdown_links.lua     :Markdown links implementation
  setup/
    keymaps.lua            buffer-local keymap installer
    autocmds.lua           FileType autocmd driver
    usercmds/
      init.lua             buffer-local user-command installer
plugin/
  markdown_nvim.lua        guard (vim.g.loaded_markdown_nvim)
doc/
  markdown.nvim.txt        :h markdown.nvim vim help file
```

---

## License

MIT
