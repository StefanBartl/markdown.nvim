# What you get with the defaults

| Command | Does |
| --- | --- |
| `:Markdown toc` | Generate or update the table of contents |
| `:Markdown links` | Scan, list and open links in a picker; `create` makes the files they point at; dead links are flagged |
| `:Markdown refs` | Sync reference-style link anchors |
| `:Markdown table` | GFM formatter, alignment, CSV import/export, linting, flavor conversion |
| `:MDTable*` | Twelve standalone commands: width-limited wrap and unwrap, row and column folding, CSV round-trip, lint |
| `:TableView*` | The floating table browser and its export toggle |
| `:Markdown scope` | Treat the fenced code block under the cursor as its own sub-document |
| `:Markdown headline_spacing` | Enforce blank-dash-blank spacing between H2+ sections |
| `:Markdown headings format` | Normalize heading text: emphasis markers off, whitespace collapsed, capitalized. `<leader><C-Left>`/`<leader><C-Right>` shift a level and apply it in one stroke |
| `:Markdown image paste` / `screenshot` | Put an image into the document, via images.nvim |
| `:Markdown render` / `preview` / `mdview` | Hand rendering to whichever renderer is installed |
| `:Markdown export pdf` | The buffer or file to PDF, via pdfport.nvim |
| `:MarkdownNvimUnderlineHeadings` | Setext-style underline decoration for headings |
| `:OpenWithSystemApplication` | Open the target under the cursor with the OS default application |
| Cursor-action dispatcher | One key over anchors, images, URLs, files and PDFs |

One default worth knowing about: a `> quoted` line gets VS Code-style coloring
regardless of your colorscheme — a green marker and text over a dimmed
full-width background. To turn it off, borrow your colorscheme's colors
instead, or pick your own,
[templates/blockquote-hl.md](templates/blockquote-hl.md) has the
ready-to-paste snippets.

The full surface is [commands.md](commands.md) and [BINDINGS.md](BINDINGS.md).
