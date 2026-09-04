> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# markdown.nvim

```
                         __       __
   ____ ___  ____ ______/ /______/ /___ _      ______
  / __ `__ \/ __ `/ ___/ //_/ __  / __ \ | /| / / __ \
 / / / / / / /_/ / /  / ,< / /_/ / /_/ / |/ |/ / / / /
/_/ /_/ /_/\__,_/_/  /_/|_|\__,_/\____/|__/|__/_/ /_/
            a self-contained markdown toolkit
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)

> 💡 Pairs well with [cascade.nvim](https://github.com/StefanBartl/cascade.nvim):
> markdown.nvim renders and structures the document (TOC, folding, tables),
> while cascade.nvim edits the list content inside it (continue, renumber, rotate).

A self-contained Markdown toolkit for Neovim: headings/TOC/folding, GFM
tables (format, align, width-limited wrap, CSV round-trip, linting),
links/references (scan, create, dead-link checks), a cursor-action
dispatcher (open whatever's under the cursor — anchor, image, URL, file,
PDF), fenced-block scope, and delegated preview/export (render-markdown.nvim,
mdview.nvim, image paste/screenshot via images.nvim, PDF export via
pdfport.nvim). Pure FileType-scoped — zero side effects on non-Markdown
buffers. Requires Neovim >= 0.9 and
[lib.nvim](https://github.com/StefanBartl/lib.nvim) (the `:Markdown`/
`:TableView*` command layer, plus buffer debouncing); no external tools.
The link/path hover lives in
[hover.nvim](https://github.com/StefanBartl/hover.nvim), which this plugin
contributes its link scanner and `#heading` previews to.

---

## Capabilities

| Capability | What it does | Details |
|---|---|---|
| `:Markdown links` | Scan/list/open links in a picker, create files from link targets, flag dead links | [Links and references](docs/FEATURES/links-and-references.md) |
| `:Markdown toc` | Generate/update a table of contents | [Headings](docs/FEATURES/headings.md) |
| `:Markdown refs` | Sync reference-style link anchors | [Links and references](docs/FEATURES/links-and-references.md) |
| `:Markdown table` | GFM table formatter, alignment, CSV import/export, linting, flavor conversion | [Tables](docs/FEATURES/tables.md) |
| `:MDTable*` family | Width-limited table wrapping/unwrapping, row/column folding, CSV round-trip, lint (12 standalone commands) | [Width-limited table wrapping](docs/table-wrap.md) |
| `:TableView*` family | Floating table browser/export toggle | [Tables](docs/FEATURES/tables.md) |
| `:Markdown render` / `preview` / `mdview` | Delegate rendering/preview to render-markdown.nvim, markdown-preview.nvim, or mdview.nvim | [Integrations](docs/FEATURES/integrations.md) |
| `:Markdown create` | Create files/directories for local link targets in the buffer or selection | [Links and references](docs/FEATURES/links-and-references.md) |
| `:Markdown scope` | Treat a fenced code block as its own sub-document | [Fenced-block scope](docs/fenced-scope.md) |
| `:Markdown headline_spacing` | Enforce blank-dash-blank spacing between H2+ sections | [Headings](docs/FEATURES/headings.md) |
| `:Markdown image` | Paste/screenshot an image into the document (delegates to images.nvim) | [Editing and handlers](docs/FEATURES/editing-and-handlers.md) |
| `:Markdown export` | Export the buffer/file to PDF (delegates to pdfport.nvim) | [Integrations](docs/FEATURES/integrations.md) |
| Cursor-action dispatcher | `<CR>`-style action on whatever's under the cursor: anchor, image, URL, file, PDF | [Editing and handlers](docs/FEATURES/editing-and-handlers.md) |
| Link hover preview | Floating preview of what a link — or a bare path, in any filetype — under the cursor points to | [Link hover preview](docs/hover.md) |
| HTML link resolution | `<img src>` / `<a href>` count as links everywhere — a captioned `<figure>` keeps its hover, `mi`, picker entry and dead-link check | [Image captions](docs/image-captions.md) |
| `:MarkdownNvimUnderlineHeadings` | Setext-style underline decoration for headings | [Headings](docs/FEATURES/headings.md) |
| `:OpenWithSystemApplication` | Open the file/link target under the cursor with the OS default application | [Editing and handlers](docs/FEATURES/editing-and-handlers.md) |

---

## Quickstart

```lua
-- lazy.nvim
{
  "StefanBartl/markdown.nvim",
  dependencies = {
    "StefanBartl/lib.nvim",
    -- Optional. markdown.nvim registers its link scanner and #heading
    -- previews into it; without it those simply do not exist.
    "StefanBartl/hover.nvim",
  },
  ft = { "markdown", "mdx", "md" },
  opts = {},
}
```

See [docs/installation.md](docs/installation.md) for packer.nvim and vim-plug.

> 💡 Rest the cursor on any link and a small float previews what it points
> at — an image, a PDF's first page, another file's section, a directory
> listing, an in-page anchor, a URL — or tells you the target doesn't
> exist. A path written as plain text hovers the same way, in any filetype:
> `./assets/diagram.png` in a code comment, or a truncated
> `...nvim/init.lua:42` out of a log. See [docs/hover.md](docs/hover.md).

> 💡 A `> quoted` line gets VS Code-style coloring by default (green marker +
> text, dimmed background across the whole line) regardless of your
> colorscheme. Don't want that? See
> [docs/templates/blockquote-hl.md](docs/templates/blockquote-hl.md) for
> ready-to-paste `setup()` snippets to turn it off, use your colorscheme's
> own colors instead, or pick different colors.

### Optional integrations

All soft dependencies — nothing below is required, and each is detected at
runtime:

| Plugin | What it adds |
| --- | --- |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | Following a `.pdf` link can render it into a Neovim buffer instead of opening the system reader. `:Markdown export pdf` exports the current buffer/file to PDF. |
| [images.nvim](https://github.com/StefanBartl/images.nvim) / [snacks.nvim](https://github.com/folke/snacks.nvim) / [image.nvim](https://github.com/3rd/image.nvim) | `mi` can preview an image in a floating window instead of the system viewer (`image.preview`) — images.nvim preferred when several are installed, the only one that draws on native Windows Neovim in WezTerm. With `snacks.picker` also installed, `:Markdown links show` gets a live per-item image preview too. `:Markdown image paste\|screenshot` delegates straight to `:Image paste`/`:Image screenshot`. |
| telescope.nvim / fzf-lua | Extra picker backends for link selection (`links.picker`). |

---

## Documentation

- [Features](docs/FEATURES/README.md) — per-theme write-up ([headings](docs/FEATURES/headings.md), [tables](docs/FEATURES/tables.md), [links](docs/FEATURES/links-and-references.md), [editing/handlers](docs/FEATURES/editing-and-handlers.md), [highlighting/UI](docs/FEATURES/highlighting-and-ui.md), [integrations](docs/FEATURES/integrations.md)) noting each feature's keymap/command/autocmd.
- [Installation](docs/installation.md) — requirements and setup for lazy.nvim, packer.nvim, vim-plug.
- [Configuration](docs/configuration.md) — full `setup()` reference with defaults, and feature gating.
- [Config templates](docs/templates/README.md) — copy-paste `setup()` snippets for common customizations (blockquote colors, feature subsets, picker backends, image preview).
- [Keymaps](docs/keymaps.md) — every default keymap, remapping/disabling, and the actions API.
- [Commands](docs/commands.md) — the `:Markdown` command and all its subcommands.
- [Link hover preview](docs/hover.md) — the float that previews a link target under the cursor, and everything it can show.
- [Image captions](docs/image-captions.md) — implicit figures vs. an HTML `<figure>` vs. `@fig:` cross-references, and what each one costs you in the editor.
- [Fenced-block scope](docs/fenced-scope.md) — treating a fenced Markdown block as its own sub-document.
- [Width-limited table wrapping](docs/table-wrap.md) — the `:MDTable*` command family (wrap/unwrap, lint, CSV, profiles, and more).
- [Menu integration](docs/menu.md) — context-aware entries for nvzone/menu.
- [Health](docs/health.md) — what `:checkhealth markdown` reports.
- [Declared external tools](docs/install.json) — the optional CLI tools (`rg`, which speeds up the reverse file-reference search) with why each matters. `:Lib deps show markdown.nvim` reports what's missing here, `:Lib deps install markdown.nvim` offers to install it — via [lib.nvim.deps](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md), which asks before it installs anything. A popup shows this once, the first time `setup()` runs after installing. Turn it off with `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) or `vim.g.lib_nvim_deps_disabled_plugins = { "markdown.nvim" }` (just this one).
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Bindings cheatsheet](docs/BINDINGS.lua) — machine-readable list of every binding.

## License

MIT — see [LICENSE](LICENSE).
