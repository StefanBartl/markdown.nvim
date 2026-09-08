> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

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
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)
[![CI](https://github.com/StefanBartl/markdown.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/markdown.nvim/actions/workflows/ci.yml)

A self-contained Markdown toolkit for Neovim, behind one `:Markdown` command.

Headings and folding, GFM tables, links and references, and a cursor-action
dispatcher that opens whatever is under the cursor. Everything is
FileType-scoped: no side effects on any buffer that is not Markdown.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Integrations](#integrations)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES/README.md) — one page per area: [headings](docs/FEATURES/HEADINGS.md), [tables](docs/FEATURES/TABLES.md), [links and references](docs/FEATURES/LINKS-AND-REFERENCES.md), [editing and handlers](docs/FEATURES/EDITING-AND-HANDLERS.md), [highlighting and UI](docs/FEATURES/HIGHLIGHTING-AND-UI.md), [integrations](docs/FEATURES/INTEGRATIONS.md).
- [Installation](docs/installation.md) — requirements, and a spec per plugin manager.
- [Configuration](docs/configuration.md) — every `setup()` option and its default, opening with the ready-to-paste snippets.
- [Config templates](docs/templates/README.md) — copy-paste `setup()` snippets: blockquote colors, feature subsets, picker backends, image preview.
- [Command reference](docs/commands.md) — `:Markdown`, subcommand by subcommand.
- [Keymaps](docs/keymaps.md) — the keys grouped by what they are for, how to remap or disable them, and the actions API.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand in one inventory.
- [Link hover preview](docs/hover.md) — the float that previews what a link or a bare path points at, and everything it can show.
- [Image captions](docs/image-captions.md) — implicit figures vs. an HTML `<figure>` vs. `@fig:` cross-references, and what each costs in the editor.
- [Fenced-block scope](docs/fenced-scope.md) — why a Markdown document inside another one needs its own scope.
- [Width-limited table wrapping](docs/table-wrap.md) — the `:MDTable*` family, and why the formatter aligns to natural width.
- [Menu integration](docs/menu.md) — the context-aware entries shipped for nvzone/menu.
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Workflow](docs/WORKFLOW.md) — how the features combine while actually writing a document, rather than what each one does.
- [Health](docs/health.md) — what `:checkhealth markdown` reports.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a handler or a command.

`:help markdown.nvim` is the same reference inside the editor.

---

## What it does

Markdown work in an editor splits into two halves that are usually served by
two different plugins: rendering it prettier, and actually operating on the
document. This one is the second half — structure, tables, links, and the thing
under the cursor — and delegates the first to whichever renderer you already
have.

| Area | Does |
| --- | --- |
| **Headings** | A generated and updatable table of contents, folding by level, enforced blank-dash-blank spacing between sections, text normalization (emphasis markers, whitespace, capitalization), and Setext-style underline decoration |
| **Tables** | The GFM formatter and aligner, width-limited wrapping and unwrapping, row and column folding, CSV round-trip, linting, flavor conversion, and a floating table browser |
| **Links and references** | Scan, list and open in a picker; create the files a link points at; sync reference-style anchors; flag dead links. `<img src>` and `<a href>` count as links everywhere |
| **Under the cursor** | One dispatcher over anchors, images, URLs, files and PDFs — and a hover float that previews what the target actually is |
| **Fenced-block scope** | A fenced code block treated as its own sub-document, so the commands above operate inside it |
| **Delegated rendering** | Preview, render and PDF export handed to render-markdown.nvim, markdown-preview.nvim, mdview.nvim, images.nvim and pdfport.nvim — whichever are installed |

Everything is installed by a `FileType` autocommand on Markdown buffers; only
`:Markdown` itself is global. There are no external tool requirements — `rg`
speeds up the reverse file-reference search and is the only one that exists.

---

## Around it

> **[cascade.nvim](https://github.com/StefanBartl/cascade.nvim)** — the list
> content inside the document: continue, renumber, rotate. markdown.nvim
> structures the document, cascade edits what is in it.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** — the host for
> the link preview. markdown.nvim contributes its link scanner and `#heading`
> previews; without it those simply do not exist.
>
> **[mdview.nvim](https://github.com/StefanBartl/mdview.nvim)** — renders the
> document outside the editor, for the moment you want to see it as a reader
> would.
>
> **[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)** — the PDF
> half: exports the buffer, and renders a `.pdf` link target into a Neovim
> buffer instead of handing it to the system reader.
>
> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — pasting and
> screenshotting images into the document, and drawing them in the preview.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Markdown` / `:TableView*` command layer, and buffer debouncing |

No external tools are required. Optional, each detected at runtime and
degrading to nothing when absent:

| | |
| --- | --- |
| `rg` (ripgrep) | Speeds up the reverse file-reference search |
| [hover.nvim](https://github.com/StefanBartl/hover.nvim) | The link and path preview float |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | `.pdf` targets rendered in a buffer, and `:Markdown export pdf` |
| [images.nvim](https://github.com/StefanBartl/images.nvim), [snacks.nvim](https://github.com/folke/snacks.nvim), [image.nvim](https://github.com/3rd/image.nvim) | Image previews in a float, and `:Markdown image paste\|screenshot` |
| [mdview.nvim](https://github.com/StefanBartl/mdview.nvim), render-markdown.nvim, markdown-preview.nvim | The rendering and preview back ends |
| telescope.nvim, fzf-lua, snacks.picker | Picker backends for link selection |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [Integrations](#integrations) |

`rg` is declared in [docs/install.json](docs/install.json) and read by lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup says what is missing the first time `setup()` runs after installing;
`:Lib deps show markdown.nvim` repeats it, `:Lib deps install markdown.nvim`
offers to install it and asks first. Turn the popup off with
`vim.g.lib_nvim_deps_disable_first_run = true`, or for this plugin only with
`vim.g.lib_nvim_deps_disabled_plugins = { "markdown.nvim" }`.

---

## Installation

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

`ft` rather than an event: everything this plugin installs is buffer-local to a
Markdown buffer anyway, so there is nothing to load before one is open. Other
plugin managers are in [docs/installation.md](docs/installation.md).

---

## Quickstart

Open a Markdown file and give it a table of contents:

```vim
:Markdown toc
```

Then the rest of the everyday set:

```vim
:Markdown links          " scan, list and open the links in a picker
:Markdown links create   " create the files the local links point at
:Markdown refs           " sync reference-style anchors
:Markdown table          " format and align the table under the cursor
:Markdown scope          " treat the fenced block under the cursor as its own document
:Markdown export pdf     " the buffer to PDF, via pdfport.nvim
```

Rest the cursor on any link and a small float previews what it points at — an
image, a PDF's first page, another file's section, a directory listing, an
in-page anchor, a URL — or says the target does not exist. A path written as
plain text hovers the same way, in any filetype: `./assets/diagram.png` in a
code comment, or a truncated `...nvim/init.lua:42` out of a log. That float is
[hover.nvim](https://github.com/StefanBartl/hover.nvim); the detail is
[docs/hover.md](docs/hover.md).

Verify your setup any time with:

```vim
:checkhealth markdown
```

---

## What you get with the defaults

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
[docs/templates/blockquote-hl.md](docs/templates/blockquote-hl.md) has the
ready-to-paste snippets.

The full surface is [docs/commands.md](docs/commands.md) and
[docs/BINDINGS.md](docs/BINDINGS.md).

---

## Integrations

Every integration below is soft and detected at runtime; the write-up is
[docs/FEATURES/INTEGRATIONS.md](docs/FEATURES/INTEGRATIONS.md).

### Context menu

`markdown.integrations.menu` contributes context-aware entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects — the fold actions only
appear on a heading, and each group can be switched off individually via
`config.menu`. markdown.nvim has **no** dependency on `menu` and never opens a
context menu itself; a host, typically your own `<RightMouse>` dispatcher,
composes these entries into its own menu. See [docs/menu.md](docs/menu.md).

### Rendering and preview

`:Markdown render`, `preview` and `mdview` hand the document to
render-markdown.nvim, markdown-preview.nvim or
[mdview.nvim](https://github.com/StefanBartl/mdview.nvim) — this plugin does
not draw a preview itself. `:Markdown export pdf` goes to
[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim), which also renders
a followed `.pdf` link into a buffer instead of opening the system reader.

### Images and pickers

`:Markdown image paste|screenshot` delegates to
[images.nvim](https://github.com/StefanBartl/images.nvim), which is also the
preferred image preview backend when several are installed — the only one that
draws on native Windows Neovim in WezTerm. Link selection runs through
telescope.nvim, fzf-lua or snacks.picker, whichever `links.picker` names; with
snacks.picker installed, `:Markdown links show` gets a live per-item image
preview too.

---

## Health check

```vim
:checkhealth markdown
```

Reports the Neovim version, which optional integrations resolved, and the state
of the declared external tools. [docs/health.md](docs/health.md) has the detail.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
project layout; [docs/architecture.md](docs/architecture.md) says which module
owns what.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/markdown.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/markdown.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
