# Assigning these features to their FEATURES themes

A closed working note. Every entry below is struck through: each of these
features has been filed into its theme in `docs/FEATURES/`. Kept as the record
of what moved where, not as open work.


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

- ~~**In-Neovim image preview**~~ — `mi` renders images in a floating window
  when images.nvim, snacks.nvim (`Snacks.image`) or image.nvim is installed,
  instead of always shelling out to the system viewer. All three are soft
  deps; `image.preview` (`"ask"`/`"preview"`/`"system"`) picks the
  behaviour, and with none installed nothing changes.
  `markdown/util/image_preview.lua` + `handler/image.lua`, mirroring the
  pdfport.nvim prompt on the PDF path. images.nvim is preferred when
  several are installed: it's the only one of the three that draws on
  native Windows Neovim in WezTerm — snacks.nvim/image.nvim both speak only
  Kitty APC, which Neovim's own output layer never gets drawn there.
- ~~**Live image preview in `:Markdown links show`, `:Markdown image`**~~ —
  images.nvim CROSS-PLUGIN.md item. When the scanned links include an image
  and both `snacks.picker` + images.nvim are installed, `links show` routes
  through a dedicated snacks picker with a live per-item preview
  (`images.browse.draw_in_window()`); `links.picker`'s four generic backends
  have no cross-backend preview hook, same constraint CROSS-PLUGIN.md
  documents for `pickers.nvim`. Falls back to the unchanged picker otherwise.
  `:Markdown image paste|screenshot` is a thin discoverability delegator to
  `:Image paste`/`:Image screenshot` — no new logic, images.nvim does the
  actual work. `commands/links.lua`, `commands/image.lua`.
