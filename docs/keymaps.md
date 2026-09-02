# Keymaps (all buffer-local, Markdown only)

## Navigation

| Key | Mode | Action |
|-----|------|--------|
| `<C-p>` / `[[` | n / v / x | Previous heading **or fenced-code delimiter** |
| `<C-f>` / `]]` | n / v / x | Next heading **or fenced-code delimiter** |
| `{count}<leader><C-p>` | n | Previous heading of level `count` (headings only) |
| `{count}<leader><C-f>` | n | Next heading of level `count` (headings only) |

`<C-p>`/`<C-f>` stop on a fenced block's opening ` ```lang ` line and on its
closing ` ``` ` line as well as on headings — a code block is the other
landmark of a markdown file, and it used to take a separate motion to reach.
Set `nav = { fences = false }` for the old headings-only behavior; the
`<leader>` variants are headings-only either way.

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

Use `set foldmethod=expr foldexpr=v:lua.require('markdown').foldexpr(v:lnum)`
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
| `**` | V | Toggle `**bold**` on every selected line |
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
require("markdown").setup({
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
on `require("markdown").actions`, so you can bind anything by hand — no
`<Plug>` indirection:

```lua
local a = require("markdown").actions
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
| `<leader>mtf` | n | Format the table at the cursor (`:Markdown table format`) |

Inside the floating preview itself (buffer-local to the popup, Normal mode
only — not active anywhere else):

| Key | Action |
|-----|--------|
| `<M-Right>` / `<M-l>` | Widen the column under the cursor |
| `<M-Left>` / `<M-h>` | Narrow the column under the cursor (floors at its natural content width) |
| `<M-Up>` / `<M-k>` | Move the row under the cursor up (swap with the row above) |
| `<M-Down>` / `<M-j>` | Move the row under the cursor down (swap with the row below) |
| `:w` | Write the current row order back to the source buffer/file |

h/j/k/l are a fallback for terminals that intercept `<M-Up>`/`<M-Down>`.
Column widening is a reading aid only, never written back (`:w` always
writes natural, unpadded widths). See [Commands](commands.md#markdown-table)
for the full behavior (no-ops on border/separator/label lines, independent
per-table state in a stacked multi-table view, buffer-vs-file write-back
semantics).

Column widths are computed from screen-display width (`vim.fn.strdisplaywidth`),
not byte length, so cells containing multi-byte UTF-8 (umlauts, em dashes,
curly quotes, arrows, …) still line up — see `renderer.validate_alignment()`
in [Architecture](architecture.md) if you want to verify a rendered table's `|`
columns programmatically instead of eyeballing it.
