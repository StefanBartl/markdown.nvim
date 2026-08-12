# Features

markdown.nvim's feature set, split by theme — one file per area, each
feature noting the module, keymap/command/autocmd it's wired to, and the
relevant config. For the full default-key list see
[keymaps.md](../keymaps.md); for every `:Markdown` subcommand see
[commands.md](../commands.md).

- [Headings](headings.md) — navigation, level shift, folding, TOC, headline
  spacing, Setext-underline decoration
- [Tables](tables.md) — GFM formatter, auto-format mode, floating
  browser/export, width-limited wrapping (`:MDTable*`)
- [Links and references](links-and-references.md) — link wrap, scan,
  diagnostics, anchor sync (`refs`), filesystem creation from links
- [Editing and handlers](editing-and-handlers.md) — bold wrap, the
  cursor-action dispatcher (anchors/images/URLs/files/PDFs), image
  paste/screenshot
- [Highlighting and UI](highlighting-and-ui.md) — fenced/inline code,
  blockquotes, link underline, fenced-block scope
- [Integrations](integrations.md) — render-markdown.nvim,
  markdown-preview.nvim, mdview.nvim, images.nvim/snacks.nvim/image.nvim,
  pdfport.nvim, nvzone/menu, picker backends, which-key, lib.nvim

For the module-by-module source layout instead of the feature/theme view,
see [Architecture](../architecture.md).
