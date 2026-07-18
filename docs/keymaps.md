# Keymaps (all buffer-local, Markdown only)

## Navigation

| Key | Mode | Action |
|-----|------|--------|
| `<C-p>` / `[[` | n / v / x | Previous H2+ heading |
| `<C-f>` / `]]` | n / v / x | Next H2+ heading |
| `{count}<leader><C-p>` | n | Previous heading of level `count` |
| `{count}<leader><C-f>` | n | Next heading of level `count` |

## Heading level shift

A `{count}` prefix shifts by that many levels (e.g. `2<C-Right>`).

| Key | Mode | Action |
|-----|------|--------|
| `<C-Right>` | n | Increase level of current line |
| `<C-Left>`  | n | Decrease level of current line |
| `<C-Right>` | v / x | Increase level of selection (existing headings only) |
| `<C-Left>`  | v / x | Decrease level of selection |
| `<S-Right>` | n | Increase all headings in buffer |
| `<S-Left>`  | n | Decrease all headings in buffer |

## Folding

| Key | Mode | Action |
|-----|------|--------|
| `zf` / `<localleader>f` | n | Toggle fold under cursor |
| `zu` | n | Unfold all, center |
| `zi` | n | Fold previous heading then center |
| `zk` | n | Fold below H2 / unfold — toggle outline (keep H1 + H2 open) |

Use `set foldmethod=expr foldexpr=v:lua.require('markdown_nvim').foldexpr(v:lnum)`
in your config, or let the plugin handle it via the FileType autocmd.

## TOC

| Key | Mode | Action |
|-----|------|--------|
| `{count}<leader>toc` | n | Insert/refresh TOC; `count` = max heading level |

## Cursor action handler

| Key | Mode | Action |
|-----|------|--------|
| `<2-LeftMouse>` | n | Open anchor / image / URL / file under cursor |
| `<C-LeftMouse>` | n | Same |
| `ma` | n | Same |
| `mi` | n | Open image under cursor |
| `mj` | n | Jump to anchor under cursor |

## Bold wrap / link wrap

| Key | Mode | Action |
|-----|------|--------|
| `**` | v | Toggle `**bold**` on selection |
| `<leader>[` | n | Wrap word under cursor in a Markdown link |
| `<leader>[` | v | Wrap selection in a Markdown link |

`<leader>[` auto-detects the inner text: a URL or file path lands in the
`(target)` part (cursor jumps into `[]`), plain text lands in the `[text]`
part (cursor jumps into `()`). On empty space it inserts an empty `[]()`.

## Remapping / disabling

**Per-binding, in config (recommended).** Every default key has a stable `id`
(see the `editing` list in [BINDINGS.lua](BINDINGS.lua)). Set
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

## TableView

| Key | Mode | Action |
|-----|------|--------|
| `<leader>tvt` | n | Toggle table preview (floating, Markdown style) |
| `<leader>tvx` | n | Toggle table preview (box-drawing / spreadsheet style) |
| `<leader>tvs` | n | Select table from list |
| `<leader>tvb` | n | Open table in browser (basic HTML); reuses the same tab on later calls |
| `<leader>tvc` | n | Close TableView float |
| `<leader>tvm` | n | Toggle table mode (auto-format) |
| `]\|` / `[\|` | n | Next / previous table cell |

Column widths are computed from screen-display width (`vim.fn.strdisplaywidth`),
not byte length, so cells containing multi-byte UTF-8 (umlauts, em dashes,
curly quotes, arrows, …) still line up — see `renderer.validate_alignment()`
in [Architecture](architecture.md) if you want to verify a rendered table's `|`
columns programmatically instead of eyeballing it.
