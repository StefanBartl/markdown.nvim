# Features

Markdown work in an editor splits into two halves that are usually served by
two different plugins: rendering it prettier, and actually operating on the
document. This one is the second half — structure, tables, links, and the
thing under the cursor — and delegates the first to whichever renderer you
already have.

| Area | Does |
| --- | --- |
| **Headings** | A generated and updatable table of contents, folding by level, enforced blank-dash-blank spacing between sections, text normalization (emphasis markers, whitespace, capitalization), and Setext-style underline decoration |
| **Tables** | The GFM formatter and aligner, width-limited wrapping and unwrapping, row and column folding, CSV round-trip, linting, flavor conversion, and a floating table browser |
| **Links and references** | Scan, list and open in a picker; create the files a link points at; sync reference-style anchors; flag dead links. `<img src>` and `<a href>` count as links everywhere |
| **Under the cursor** | One dispatcher over anchors, images, URLs, files and PDFs — and a hover float that previews what the target actually is |
| **Fenced-block scope** | A fenced code block treated as its own sub-document, so the commands above operate inside it |
| **Delegated rendering** | Preview, render and PDF export handed to render-markdown.nvim, mdview.nvim, images.nvim and pdfport.nvim — whichever are installed |

Everything is installed by a `FileType` autocommand on Markdown buffers; only
`:Markdown` itself is global. There are no external tool requirements — `rg`
speeds up the reverse file-reference search and is the only one that exists.

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
- [Integrations](INTEGRATIONS.md) — render-markdown.nvim, mdview.nvim,
  images.nvim/snacks.nvim/image.nvim, pdfport.nvim, nvzone/menu, picker
  backends, which-key, lib.nvim

For the module-by-module source layout instead of the feature/theme view,
see [Architecture](../architecture.md).
