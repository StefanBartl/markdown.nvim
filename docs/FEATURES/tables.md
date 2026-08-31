# Tables

Four layers, each usable independently: a GFM formatter, a live
auto-format/tableize mode, a floating browser/export view, and (opt-in)
width-limited wrapping.

## `table_fmt` — GFM formatter

Parses and re-renders pipe tables: column alignment (per-role and
per-column), separator normalization, HTML `<table>` import/export
round-trip.

- **Module:** `core/table_fmt.lua` (`format_table_at_cursor`,
  `format_tables_in_buffer`, `format_tables_in_scope`, `parse_html_table`,
  `rows_to_gfm`) — self-contained, no external dependency
- **Command:** `:Markdown table format [header=|cell=|skip=|scope=]`,
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
- **Autocmd:** `MarkdownNvimTableView` augroup (`bindings/autocmds.lua`)
  installs the buffer-local maps/commands on `FileType`, gated by the
  `tableview` feature.
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
- **Config:** `table.wrap` (`enabled`, `auto`, `min`, `max`, `pad`, `join`,
  `soft_break_chars`, `continuation_marker`, `flavor`, `auto_resize`,
  `resize_debounce_ms`, `selective_reflow`), `table.wrap_profiles`
- **Autocmds:** `MarkdownNvimTableWrapResize` (debounced `VimResized`/
  `WinResized` reflow, opt-in via `auto_resize`), `MarkdownNvimTableWrapSelective`
  (`BufWritePre`, opt-in via `selective_reflow`) — both in
  `bindings/autocmds.lua`
- **Fold integration:** extends `core/fold.lua`'s heading `foldexpr` rather
  than a competing manual-fold pass — see
  [headings.md](headings.md#folding)
- **API hooks:** `core.table_wrap.on("before_reflow"|"after_reflow", fn)`
