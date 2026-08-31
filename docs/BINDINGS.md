# markdown.nvim — Binding Cheatsheet

Every keymap, user command and autocommand `markdown.nvim` defines, in one
place. This file is documentation only; the source of truth is
`lua/markdown/bindings/` (`keymaps.lua`, `usrcmds.lua`, `autocmds.lua`,
`actions.lua`, `which_key.lua`) plus `tableview/renderer.lua` for the popup's
own keys. A change there must be reflected here.

[`docs/BINDINGS.lua`](BINDINGS.lua) carries the same data as a Lua table, for
tools that want to read it rather than a human.

**Almost everything here is buffer-local.** The editing keys and the
buffer-local commands are installed by a `FileType` autocommand on markdown
buffers (see [Autocommands](#autocommands)); only `:Markdown` itself is global.

## Table of content

  - [Keymaps — editing](#keymaps--editing)
  - [Keymaps — TableView trigger](#keymaps--tableview-trigger)
  - [Keymaps — inside the TableView popup](#keymaps--inside-the-tableview-popup)
  - [Actions](#actions)
  - [User commands — `:Markdown`](#user-commands--markdown)
  - [User commands — buffer-local](#user-commands--buffer-local)
  - [Autocommands](#autocommands)
  - [which-key](#which-key)

---

## Keymaps — editing

Buffer-local on markdown filetypes, gated by `enable_keymaps` and, where a
`flag` column is filled, by that individual flag. Remap or drop a single key
with `keymaps.<id> = "<lhs>"` / `= false`.

| id | lhs | mode | action | flag | desc |
| --- | --- | --- | --- | --- | --- |
| `toggle_bold` | `**` | v | `toggle_bold_visual` | `map_double_asterisk` | Toggle bold |
| `wrap_link_n` | `<leader>[` | n | `wrap_link_normal` | `map_wrap_link` | Wrap word in link |
| `wrap_link_v` | `<leader>[` | v | `wrap_link_visual` | `map_wrap_link` | Wrap selection in link |
| `prev_heading` | `<C-p>` | n, v, x | `prev_heading` | | Prev heading |
| `prev_heading_bracket` | `[[` | n | `prev_heading` | | Prev heading |
| `next_heading` | `<C-f>` | n, v, x | `next_heading` | | Next heading |
| `next_heading_bracket` | `]]` | n | `next_heading` | | Next heading |
| `prev_heading_level` | `<leader><C-p>` | n | `prev_heading_level` | | Prev heading of level |
| `next_heading_level` | `<leader><C-f>` | n | `next_heading_level` | | Next heading of level |
| `fold_toggle_zf` | `zf` | n | `fold_toggle` | `use_zf_override` | Fold toggle |
| `fold_toggle` | `<localleader>f` | n | `fold_toggle` | | Fold toggle |
| `unfold_all` | `zu` | n | `unfold_all` | | Unfold all |
| `fold_prev_heading` | `zi` | n | `fold_prev_heading` | | Fold prev heading |
| `fold_h2plus` | `zk` | n | `fold_h2plus` | | Fold below H2 (toggle outline) |
| `toc` | `<leader>toc` | n | `toc` | | Insert/refresh TOC |
| `cursor_action_2click` | `<2-LeftMouse>` | n | `cursor_action_mouse` | | Cursor action / heading fold (silent miss) |
| `cursor_action_cclick` | `<C-LeftMouse>` | n | `cursor_action_mouse` | | Cursor action (silent miss) |
| `cursor_action` | `ma` | n | `cursor_action` | | Cursor action |
| `open_image` | `mi` | n | `open_image` | | Open image |
| `jump_anchor` | `mj` | n | `jump_anchor` | | Jump to anchor |
| `heading_inc` | `<C-Right>` | n | `heading_inc` | | Increase heading level |
| `heading_dec` | `<C-Left>` | n | `heading_dec` | | Decrease heading level |
| `heading_inc_visual` | `<C-Right>` | v, x | `heading_inc_visual` | | Increase heading level (visual) |
| `heading_dec_visual` | `<C-Left>` | v, x | `heading_dec_visual` | | Decrease heading level (visual) |
| `heading_inc_all` | `<S-Right>` | n | `heading_inc_all` | | Increase all headings |
| `heading_dec_all` | `<S-Left>` | n | `heading_dec_all` | | Decrease all headings |
| `table_next_cell` | `]\|` | n | `table_next_cell` | feature `table` | Next table cell |
| `table_prev_cell` | `[\|` | n | `table_prev_cell` | feature `table` | Prev table cell |
| `table_format` | `<leader>mtf` | n | `table_format` | feature `table` | Format table at cursor |

`zf` is an override of a builtin. It only takes effect with
`use_zf_override = true`; `<localleader>f` does the same thing without touching
the builtin, and is the reason the override is optional rather than the only
way in.

## Keymaps — TableView trigger

Buffer-local on markdown buffers; they open/close the popup from the source
buffer. Each is a thin wrapper around the corresponding command.

| lhs | mode | id | command | desc |
| --- | --- | --- | --- | --- |
| `<leader>tvt` | n | `tableview_toggle` | `:TableViewToggle` | Toggle table preview (config default style) |
| `<leader>tvx` | n | `tableview_box` | `:TableViewBox` | Toggle table preview (box-drawing style) |
| `<leader>tvs` | n | `tableview_select` | `:TableViewSelect` | Select and preview table |
| `<leader>tvb` | n | `tableview_browser` | `:TableViewOpenBrowser` | Open table in browser (basic HTML) |
| `<leader>tvc` | n | `tableview_close` | `:TableViewClose` | Close TableView |
| `<leader>tvm` | n | `tableview_mode` | `:Markdown table mode toggle` | Toggle table mode (auto-format) |

These are overridable by id through the same `keymaps` table as the editing
keys (`keymaps = { tableview_toggle = "<leader>mt" }`) — they were fixed
strings before, which made `<leader>tv*` the one prefix here nobody could
move.

## Keymaps — inside the TableView popup

Registered by `tableview/renderer.lua` on the popup buffer itself, normal mode
only. **Not** active on markdown buffers, and **not** gated by
`enable_keymaps` — the popup has no editing surface to opt out of.

The `h`/`j`/`k`/`l` rows duplicate the arrow keys on purpose: some terminals
and multiplexers swallow `<M-Up>`/`<M-Down>` before Neovim sees them.

| lhs | alternate | action | desc |
| --- | --- | --- | --- |
| `<M-Right>` | `<M-l>` | `resize_current_column(1)` | Widen the column under the cursor |
| `<M-Left>` | `<M-h>` | `resize_current_column(-1)` | Narrow the column under the cursor (floors at natural content width) |
| `<M-Up>` | `<M-k>` | `move_current_row(-1)` | Move the row under the cursor up |
| `<M-Down>` | `<M-j>` | `move_current_row(1)` | Move the row under the cursor down |
| `:w` | | `write_back()` | Write the current row order back to the source buffer/file (`BufWriteCmd`). Column widening is never written back |

## Actions

The named functions on `require("markdown").actions` — the implementation
surface the keymaps above point at. Bind your own keys to these instead of
remapping, if you prefer.

| action | mode | desc |
| --- | --- | --- |
| `toggle_bold_visual` | v | Toggle `**bold**` on selection |
| `wrap_link_normal` | n | Wrap word under cursor in a Markdown link |
| `wrap_link_visual` | v | Wrap selection in a Markdown link |
| `prev_heading` | n, v, x | Previous H2+ heading |
| `next_heading` | n, v, x | Next H2+ heading |
| `prev_heading_level` | n | Previous heading of level `{count}` |
| `next_heading_level` | n | Next heading of level `{count}` |
| `fold_toggle` | n | Toggle fold under cursor |
| `unfold_all` | n | Unfold all, center |
| `fold_prev_heading` | n | Fold previous heading, center |
| `fold_h2plus` | n | Fold below H2 / unfold (toggle outline: keep H1+H2) |
| `toc` | n | Insert/refresh TOC (`{count}` = max level) |
| `cursor_action` | n | Open anchor/image/URL/file under cursor |
| `cursor_action_mouse` | n | Same, silent on miss; heading → fold toggle (mouse) |
| `open_image` | n | Open image under cursor |
| `jump_anchor` | n | Jump to anchor under cursor |
| `heading_inc` | n | Increase heading level (`{count}` levels) |
| `heading_dec` | n | Decrease heading level (`{count}` levels) |
| `heading_inc_visual` | v, x | Increase heading level, selection |
| `heading_dec_visual` | v, x | Decrease heading level, selection |
| `heading_inc_all` | n | Increase all headings in buffer |
| `heading_dec_all` | n | Decrease all headings in buffer |
| `table_format` | n | Format table at cursor (`:Markdown table format`) |

## User commands — `:Markdown`

The one global dispatcher. Everything else this plugin registers is
buffer-local.

| command | desc |
| --- | --- |
| `:Markdown links show [%\|cwd\|<file>]` | Collect links, pick one, open it |
| `:Markdown links create [-r] [--noignore] [--root <p>] <path>` | Generate links from a dir tree to clipboard |
| `:Markdown toc [level] [--sep\|--no-sep]` | Insert/refresh the TOC |
| `:Markdown refs [sync\|check\|live [on\|off\|toggle]\|baseline]` | Sync `#anchor` links + TOC on heading rename |
| `:Markdown table view [toggle\|markdown\|box\|select\|close\|browser\|browsernice] [scope]` | Render table preview; `scope=%\|cwd\|<path>` or an off-table cursor = every matching table, stacked |
| `:Markdown table format [options]` | GFM table formatter at cursor/in scope |
| `:Markdown table new [cols] [rows]` | Insert an empty GFM table template |
| `:Markdown table mode [on\|off\|toggle]` | Per-buffer table auto-format (vim-table-mode style) |
| `:Markdown table tableize [format]` | Convert delimited text (range) into a GFM table (csv/tsv/psv/space/…) |
| `:Markdown render [on\|off\|toggle]` | render-markdown.nvim wrapper (optional host) |
| `:Markdown preview [start\|stop\|toggle]` | markdown-preview.nvim wrapper (optional host) |
| `:Markdown mdview [path]` | Open a file directly via mdview.nvim (optional host) |
| `:Markdown create fs` | Create files/dirs for local link targets |
| `:Markdown headline_spacing` | Enforce blank-dash-blank between H2+ sections |
| `:Markdown scope [on\|off\|toggle\|status]` | Toggle fenced-block scope (TOC/nav/jump/shift/fold act on the block the cursor is in) |
| `:Markdown image [paste\|screenshot]` | Delegates to images.nvim's `:Image paste/screenshot` (optional host); default sub is `paste` |
| `:Markdown export [pdf] [path]` | Delegates to pdfport.nvim's `create()` (optional host); default sub is `pdf` |
| `:Markdown gaps` | Check for skipped heading levels; offers to fix them |

## User commands — buffer-local

Created per markdown buffer by the `MarkdownNvimUserCommands` autocommand.

| command | desc |
| --- | --- |
| `:OpenWithSystemApplication` | Same as `ma` — open target under cursor |
| `:MarkdownNvimUnderlineHeadings` | Underline every ATX heading's text with `=` (Setext-style decoration, idempotent) |
| `:MDTableWrap` | Wrap the table at the cursor (or every table, off any) |
| `:MDTableUnwrap` | Merge continuation rows back into one row each |
| `:MDTableWrapVisual[!]` | Wrap tables in the visual selection; `!` unwraps first |
| `:MDTableWrapVisible[!]` | Wrap tables in the visible window range; `!` unwraps first |
| `:MDTableReflowHeader` | Reflow only the header + separator; body untouched |
| `:MDTableFoldRow` | Fold the continuation block under the cursor |
| `:MDTableFoldAll` | Fold every continuation block in the buffer |
| `:MDTableProfile {compact\|docs\|wide}` | Load a named width-profile preset |
| `:MDTableCol {inc\|dec} [n]` | Widen/narrow the column under the cursor, preserving row total width |
| `:MDTableAlign {cycle\|left\|center\|right}` | Cycle/set the current column's alignment |
| `:MDTableFlavor {github\|loose}` | Strict GFM vs. loose separator style |
| `:MDTableLint` | Flag table structural issues via `vim.diagnostic` |
| `:MDTableFixMissingSeparator` | Insert missing separator lines |
| `:MDTableDebug` | Print the resolved column-width plan |
| `:MDTableToCSV [path]` | Export the table at the cursor as CSV |
| `:MDTableFromCSV [path]` | Insert a GFM table parsed from CSV |
| `:TableViewToggle` | Toggle floating table preview (config default style) |
| `:TableViewMarkdown` | Toggle floating table preview (aligned Markdown style) |
| `:TableViewBox` | Toggle floating table preview (box-drawing style) |
| `:TableViewSelect` | Pick a table from the buffer |
| `:TableViewClose` | Close floating preview |
| `:TableViewOpenBrowser [reopen]` | Export table as basic HTML; reuses one tab across calls (auto-refreshing), `reopen` forces a new tab |
| `:TableViewOpenBrowserNice [reopen]` | Export table as styled HTML; reuses one tab across calls (auto-refreshing), `reopen` forces a new tab |

## Autocommands

| event | group | pattern | desc |
| --- | --- | --- | --- |
| `FileType` | `MarkdownNvimKeymaps` | markdown/mdx/md/markdown.* | Install buffer-local keymaps (if `enable_keymaps`) |
| `FileType` | `MarkdownNvimUserCommands` | markdown/mdx/md/markdown.* | Install buffer-local user commands |
| `FileType` | `MarkdownNvimFold` | markdown/mdx/md/markdown.* | Set `foldmethod=expr` + fold options |
| `FileType`, `BufWritePre`, `TextChanged` | `MarkdownNvimRefs` | markdown/mdx/md/markdown.* | refs sync per `config.refs.mode` (`off`/`save`/`live`) |
| `ColorScheme` | (`hl_options`) | `*` | Re-apply blockquote / fenced-code highlights |

## which-key

`lua/markdown/bindings/which_key.lua` labels the leader groups this plugin
occupies when which-key.nvim is installed; a no-op otherwise. Every individual
key carries a `desc`, so which-key lists them without extra wiring.
