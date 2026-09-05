# Features

markdown.nvim's feature set, split by theme — one file per area, each
feature noting the module, keymap/command/autocmd it's wired to, and the
relevant config. For the full default-key list see
[keymaps.md](../keymaps.md); for every `:Markdown` subcommand see
[commands.md](../commands.md).

- [Headings](HEADINGS.md) — navigation, level shift, folding, TOC, headline
  spacing, Setext-underline decoration
- [Tables](TABLES.md) — GFM formatter, auto-format mode, floating
  browser/export, width-limited wrapping (`:MDTable*`)
- [Links and references](LINKS-AND-REFERENCES.md) — link wrap, scan,
  diagnostics, anchor sync (`refs`), filesystem creation from links
- [Editing and handlers](EDITING-AND-HANDLERS.md) — bold wrap, the
  cursor-action dispatcher (anchors/images/URLs/files/PDFs), image
  paste/screenshot
- [Highlighting and UI](HIGHLIGHTING-AND-UI.md) — fenced/inline code,
  blockquotes, link underline, fenced-block scope
- [Integrations](INTEGRATIONS.md) — render-markdown.nvim,
  markdown-preview.nvim, mdview.nvim, images.nvim/snacks.nvim/image.nvim,
  pdfport.nvim, nvzone/menu, picker backends, which-key, lib.nvim

For the module-by-module source layout instead of the feature/theme view,
see [Architecture](../architecture.md).
