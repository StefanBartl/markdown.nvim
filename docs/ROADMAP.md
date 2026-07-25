# Roadmap

Planned extensions beyond the current feature set. Roughly ordered by
value/effort, not binding.

## Done

- ~~**Telescope / fzf-lua picker backends**~~ — `links.picker` supports
  `"telescope"` / `"fzf"` (soft deps) alongside `"hover_select"` / `"select"`
  in `util/picker.lua`; a missing plugin falls back to `vim.ui.select`.
- ~~**Link diagnostics**~~ — `core/link_diagnostics.lua` flags dead
  relative-file links and duplicate heading titles via `vim.diagnostic`
  (`:Markdown links check`; `links.diagnostics.mode = "save"` for automatic
  runs), reusing `link_scan` + the anchor slug logic.
- ~~**Configurable TOC header/markers**~~ — `config.toc` exposes
  `header`/`marker`/`min_level`/`max_level`; `:Markdown toc` accepts
  `min=`/`max=`/`marker=` per-call overrides.
- ~~**Anchor style options**~~ — `config.toc.anchor_style` (`"gfm"` default,
  opt-in `"keep-case"`) and `anchor_separator`, in `core/slug.lua`, shared by
  the TOC generator, `core.refs`, and `core.link_diagnostics`.
- ~~**Table format options**~~ — `config.table` (`header_align`,
  `entry_align`, `col_overrides`) supplies defaults for `table_fmt` /
  `:Markdown table format`; explicit command args still override per call.
- ~~**Round-trip HTML import**~~ — `table_fmt.parse_html_table` /
  `rows_to_gfm`, exposed via `:Markdown table import [clipboard|PATH]`.
- ~~**Theme-derived blockquote colors**~~ — `blockquote_hl.marker_fg`/`text_fg`
  are unset by default and derived from the active colorscheme (markdown
  highlight group, then `Comment`/`String`, then the historical hex),
  re-derived on every `ColorScheme` event; an explicit config value still
  overrides.
- ~~**Per-key override table**~~ — `config.keymaps[id]` (`false` disables, a
  string or `{ lhs, mode }` remaps) in `bindings/keymaps.lua`; see
  `docs/keymaps.md`.

## Cross-cutting

- **Test suite growth** — ongoing; extend `TESTS/` further toward
  handler/anchor edge cases as new logic lands (the specs above already added
  coverage for the anchor/slug and diagnostics logic).
