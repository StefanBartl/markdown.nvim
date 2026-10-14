# Tables

Five layers, each usable independently: a GFM formatter, a live
auto-format/tableize mode, a floating browser/export view, (opt-in)
width-limited wrapping, and (opt-in) display-only truncation of over-wide
cells with a popup for the full text.

## `table_fmt` — GFM formatter

Parses and re-renders pipe tables: column alignment (per-role and
per-column), separator normalization, HTML `<table>` import/export
round-trip.

- **Module:** `core/table_fmt.lua` (`format_table_at_cursor`,
  `format_tables_in_buffer`, `format_tables_in_scope`, `parse_html_table`,
  `rows_to_gfm`) — self-contained, no external dependency
- **Command:** `:Markdown table format [header=|cell=|skip=|scope=|max=N|wrap|nowrap|auto|reflow]`
  (the width options hand the table to `table_wrap`, see below),
  `:Markdown table import [clipboard|PATH]` (see
  [commands.md](../commands.md#markdown-table))
- **Keymap:** `<leader>mtf` (format the table at the cursor — the
  argument-less `:Markdown table format`), id `table_format`
- **Config:** `table.header_align`, `table.entry_align`, `table.col_overrides`
  (per-column `align`, and — via `table_wrap`, below — `max`/`min`)
- Also exports its parse/format primitives (`parse_all_tables`,
  `calc_widths`, `gen_separator`, `format_row`, …) for reuse by
  `table_wrap.lua`, so the two never duplicate table-parsing logic.

## `table_mode` — live auto-format

A focused, dependency-free reimplementation of the vim-table-mode
essentials: auto-realign a table as you type, convert delimited text into a
GFM table (`tableize`), and jump between cells.

- **Module:** `core/table_mode.lua`
- **Command:** `:Markdown table mode [on|off|toggle]`, `:Markdown table
  tableize [csv|tsv|psv|space|…]`, `:Markdown table new [cols] [rows]` (see
  [commands.md](../commands.md#markdown-table))
- **Keymaps:** `<leader>tvm` (toggle table mode), `]|`/`[|` (next/prev cell,
  count-aware `{n}]|`) — ids covered under
  [keymaps.md](../keymaps.md#tableview) and the `table_next_cell`/
  `table_prev_cell` ids
- Requires `lib.nvim.debounce.buffer` for its auto-format debounce (the one
  hard runtime dependency beyond `lib.nvim.bindings.usercmd.composer`).
- `table_mode.insert_row(bufnr, row0, "below"|"above")` inserts an empty,
  column-matched row next to a table data row, aligns the table, and lands
  the cursor in the new row's first cell in insert mode — the table analogue
  of a list bullet's `o`/`O` continuation. `"below"` a header inserts after
  the separator instead of between it and the header; on the separator row
  itself, both `"below"` and `"above"` insert right after it (the only spot
  that keeps the header/separator shape intact). No-op (returns `false`)
  only for `"above"` a header row, since that would land the row between the
  header and its separator. Not bound to a key here —
  [cascade.nvim](https://github.com/StefanBartl/cascade.nvim) calls it as a
  soft-dependency fallback for its own `o`/`O` when the cursor line isn't a
  list item (see its `docs/integrations.md`).

## `tableview` — floating browser + export

A floating Markdown table preview (aligned-GFM or Unicode box-drawing
style), an interactive popup (resize columns, reorder rows, `:w`
write-back), and HTML export (basic/styled) with round-trip import.

- **Modules:** `tableview/parser.lua`, `tableview/renderer.lua`,
  `tableview/views/*` (browser_basic, browser_niceified, table_selector)
- **Commands (buffer-local):** `:TableViewToggle`/`Markdown`/`Box [scope]`,
  `:TableViewSelect`, `:TableViewClose`, `:TableViewOpenBrowser[Nice]
  [reopen]`; unified form `:Markdown table view [toggle|markdown|box|select|
  close|browser|browsernice] [scope|reopen]` (see
  [commands.md](../commands.md#markdown-table))
- **Keymaps:** `<leader>tvt`/`tvx`/`tvs`/`tvb`/`tvc` (see
  [keymaps.md](../keymaps.md#tableview)); inside the popup itself,
  `<M-Right>`/`<M-l>`, `<M-Left>`/`<M-h>`, `<M-Up>`/`<M-k>`,
  `<M-Down>`/`<M-j>`, `:w`
- **Autocmd:** the `tableview` handler of the `MarkdownNvimFileType` autocmd
  (`bindings/autocmds.lua`) installs the buffer-local maps/commands on
  `FileType`, gated by the `tableview` feature.
- **Config:** `tableview.style` (default `"markdown"`, or `"box"`)

## `table_wrap` — width-limited wrapping (`:MDTable*`)

Opt-in width **cap** on top of `table_fmt`'s natural, unbounded columns:
cells exceeding a column's planned width wrap onto GFM-valid continuation
rows of the same logical row. Off by default — nothing changes until a
`:MDTable*` command runs or `table.wrap.enabled = true`. Full reference:
[table-wrap.md](../table-wrap.md).

- **Modules:** `core/table_wrap.lua` (engine: plan/wrap_cell/render/
  unwrap_rows/find_issues/fix_missing_separators/to_csv/from_csv/hooks),
  `commands/mdtable.lua` (opt resolution, cursor/logical-cell restore,
  continuation-row gutter signs, scope variants)
- **Commands (buffer-local, feature `table_wrap`):** `:MDTableWrap`,
  `:MDTableUnwrap`, `:MDTableWrapVisual[!]`, `:MDTableWrapVisible[!]`,
  `:MDTableReflowHeader`, `:MDTableFoldRow`, `:MDTableFoldAll`,
  `:MDTableProfile {compact|docs|wide}`, `:MDTableCol {inc|dec} [n]`,
  `:MDTableAlign {cycle|left|center|right}`, `:MDTableFlavor {github|loose}`,
  `:MDTableLint`, `:MDTableFixMissingSeparator`, `:MDTableDebug`,
  `:MDTableToCSV [path]`, `:MDTableFromCSV [path]`
- **Format with a width cap:** `:Markdown table format max=40` (also
  `<leader>mtf` and table mode when `table.wrap.enabled = true`) wraps long cells
  onto shared continuation rows, for the cursor, buffer, `scope=cwd` and file
  scopes; `reflow` re-flows an already wrapped table.
- **Config:** `table.wrap` (`enabled`, `auto`, `min`, `max`, `pad`, `join`,
  `soft_break_chars`, `continuation_marker`, `flavor`, `auto_resize`,
  `resize_debounce_ms`, `selective_reflow`), `table.wrap_profiles`
- **Autocmds:** `MarkdownNvimTableWrapResize` (debounced `VimResized`/
  `WinResized` reflow, opt-in via `auto_resize`), `MarkdownNvimTableWrapSelective`
  (`BufWritePre`, opt-in via `selective_reflow`) — both in
  `bindings/autocmds.lua`
- **Fold integration:** extends `core/fold.lua`'s heading `foldexpr` rather
  than a competing manual-fold pass — see
  [HEADINGS.md](HEADINGS.md#folding)
- **API hooks:** `core.table_wrap.on("before_reflow"|"after_reflow", fn)`

## `table_list` — the tables of a scope in a picker

`:Markdown table list [scope=...] [style=grid|markdown]` (also `:TableViewList`,
`<leader>mtl`). One entry per table; with pickers.nvim the preview switches
between the file around the table and the table alone, formatted (`<M-t>`,
a `Pickers.Item.previews` feature of pickers.nvim). Details:
[commands.md](../commands.md#markdown-table).

- **Module:** `commands/table_list.lua` (pure `parse_args`, `collect`; `open`, `pick`)
- **Config:** `table.list = { picker = "auto" | "builtin", style = "grid" | "markdown" }`
- **Reuses:** `core.table_render.to_lines` for the grid, `util.scope` for the scope words

## `tables` — formats beyond GFM, one registry

`:Markdown table list|view|select|render` read tables through `markdown.tables.registry`. A
format is a module under `markdown.tables.formats.<name>` with `scan` (tables inside a
document) or `parse` (the whole text is one table) and `render` (write it back, which is what
`convert` and the TableView write-back use). The model is the parser's own (`header.cells`,
`alignments`, `rows`, `start_line`, `end_line`, `raw_lines`) plus `format`.

| format | where | notes |
|---|---|---|
| `gfm` | embedded | pipe tables; the default and the only one unless `table.formats` says more |
| `org` | embedded | `\|---+---\|` rules, `<r>`/`<l>`/`<c>` cookie row for alignment; `#+TBLFM:` lines are not part of the table and stay untouched |
| `box` | embedded | `┌─┬─┐ │ a │ b │ ├─┼─┤ └─┴─┘` as TableView's box style, psql unicode, sqlite `.mode box`; rules between body rows make multi-line cells (`<br>`) |
| `csv`, `tsv` | standalone | RFC 4180: quoted separators, doubled quotes, newlines in quotes; first record is the header; only through `convert from=csv\|tsv` |

- **Config:** `table.formats = { "gfm" }` (default) -- add `"org"` and/or `"box"` to find them in
  markdown buffers too. Overlapping matches: the format listed first wins, so `{ "org", "gfm" }`
  and `{ "gfm", "org" }` can read the same lines differently (a one-column org table without a `+`
  in its rule is indistinguishable from GFM and is read as GFM). Tables inside code
  fences are skipped by `list`.
- **Command:** `:Markdown table convert [from=auto] [to=gfm]` (and `:TableViewConvert`): the table
  at the cursor or in the `:range`, `from=auto` tries every embedded format (it does **not** follow `table.formats`, so a
  foreign table can be converted without configuring anything; `list` and the TableView only see
  the configured formats), `from=csv|tsv` reads
  the range (or the whole buffer) as delimited text. What the target cannot keep is reported:
  alignment in csv/tsv, org row groups, a `#+TBLFM:` line below an org table.
- **Write-back** from the TableView float uses the format the table was read in and keeps what
  that format holds: the rules between org row groups, the rounded or single border of a box
  table. A box table drawn by TableView itself (`╞═╪═╡` header rule) is read as well. A pipe in a
  cell is written escaped (`\|`) to org and gfm and plain to csv/tsv; a newline in a cell becomes
  `<br>`.
- **Not built (yet):** RST/pandoc grid and simple tables, HTML with spans, wiki tables, SQL result
  sets, JSON, LaTeX, AsciiDoc. They fit the same registry (see the analysis note in the tasks vault).
- **Modules:** `tables/registry.lua`, `tables/formats/{gfm,org,box,csv,tsv}.lua`,
  `commands/table_convert.lua`

## `table_render` — virtual grid that fits the window

Display-only rendering of every GFM table as a compact grid. The buffer text is
never touched: each row is hidden (extmark `conceal_lines`, Neovim >= 0.11) and
the grid is drawn as virtual lines hanging on the cursor row or on the line next
to the table (no inline virtual text: it leaves blank screen rows with `wrap` on).
Only changed tables are drawn again after an edit. Details and options: [table-wrap.md](../table-wrap.md#virtual-grid-rendering).

- **Module:** `core/table_render.lua` (pure `layout` / `row_lines` / `border`,
  extmark rendering, per-buffer enable/disable); `core/conceal_guard.lua` saves
  and restores `conceallevel` per window (shared with `table_truncate`)
- **Command:** `:Markdown table render [on|off|toggle]`; **keymap**
  `<leader>mtr` (id `table_render_toggle`)
- **Config:** `table.render` (`enabled`, `border`, `cursor`, `pad`, `min_width`,
  `max_width`, `row_separator`, `debounce_ms`); `enabled = true` turns it on for
  every markdown buffer (FileType dispatcher, like `truncate`)
- **Autocmds:** buffer-local `TextChanged[I]` / `InsertLeave` / `CursorMoved[I]`
  / `BufWinEnter` / `WinEnter` / `BufWinLeave` / `BufReadPost`; global `MarkdownNvimTableRender` group
  (`WinResized`, `VimResized`, `OptionSet`, `ColorScheme`), created on first use
- **Highlights:** `MarkdownTableBorder`, `MarkdownTableHead`,
  `MarkdownTableCode` (default links, override freely)
- **Exclusive with** `table_truncate` per buffer (the last one switched on wins)

## `table_truncate` + `table_popup` — one row per record, full text on demand

Alternative to wrapping: keep every table row on one line. A cell wider than
`table.truncate.max` (default 40 columns) is shown cut with `…`; the file text
is never touched (extmark `conceal`, padding and separator dashes of the other
cells are hidden too so the column stays aligned). With the cursor in a cut
cell, a small popup shows the whole text. Off by default.

- **Modules:** `core/table_truncate.lua` (pure `compute` + extmark rendering,
  per-buffer enable/disable), `core/table_popup.lua` (`cell_at`, popup float)
- **Commands:** `:Markdown table truncate [on|off|toggle|show]` (`show` opens the
  popup for any cell)
- **Keymaps:** `<leader>mtu` (toggle truncation), `<leader>mtp` (popup for the
  cell under the cursor); ids `table_truncate_toggle`, `table_cell_popup`
- **Config:** `table.truncate = { enabled = false, max = 40, marker = "…",
  popup = true }` — `enabled = true` turns it on for every markdown buffer;
  `table.popup` (default true, independent of truncation) opens the popup on
  `CursorHold` in any table cell, `table.popup = false` opts out
  The marker must be one display column wide (anything else falls back to the
  default); a double-width character at the cut is filled up so the rows keep one
  width; tables inside fenced code blocks are left alone. The whole buffer is
  re-laid-out on a change (no visible-range limit); `table.render` is the
  incremental alternative.
- **Needs:** `conceallevel >= 2` (set window-locally while on, then restored);
  the cursor line shows its full text unless `concealcursor` includes the mode
