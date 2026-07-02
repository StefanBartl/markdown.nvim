# Roadmap

Planned extensions beyond the current feature set. Roughly ordered by
value/effort, not binding.

## Links & pickers

- **Telescope / fzf-lua picker backends** — `links.picker` currently supports
  `"hover_select"` (lib.nvim) and `"select"` (`vim.ui.select`). Add
  `"telescope"` / `"fzf"` backends in `util/picker.lua` (the abstraction already
  anticipates this).
- **Link diagnostics** — flag dead relative-file links / duplicate anchors in a
  buffer (reuse `link_scan` + the anchor slug logic).

## TOC & headings

- **Configurable TOC header/markers** — the TOC header (`## Table of content`)
  and bullet style are currently fixed; expose them via config.
- **Anchor style options** — GFM slug is assumed; add opt-in variants (e.g.
  keep-case, custom separators) for other renderers.

## Tables

- **Table format options** — alignment presets and padding as config for
  `table_fmt` / `:Markdown table format`.
- **Round-trip HTML import** — parse an HTML table back into a GFM table.

## Highlighting

- **Theme-derived blockquote/fenced colors** — derive `blockquote_hl` defaults
  from the active colorscheme instead of hard-coded hex, with the explicit
  config still overriding.

## Cross-cutting

- **Test suite growth** — extend `docs/TESTS/` beyond the pure-function specs
  (toc slug, table_fmt, link_scan, headings) toward the handler/anchor logic.
- **Per-key override table** — on top of the `<Plug>` surface, an optional
  `keys = { … }` config to remap/disable individual defaults declaratively.
