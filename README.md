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
[![wkd](https://img.shields.io/badge/wkd-family-c6ff3d)](https://stefanbartl.github.io/wkd/p/markdown/)

> Part of the [wkd](https://stefanbartl.github.io/wkd/) family — see this plugin's [page](https://stefanbartl.github.io/wkd/p/markdown/) on the site.

A self-contained Markdown toolkit for Neovim, behind one `:Markdown` command.
Headings and folding, GFM tables, links and references, and a cursor-action
dispatcher that opens whatever is under the cursor — all of it FileType-scoped,
with no side effects on any buffer that is not Markdown.

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
> dependency — see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

### The Basics

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — a spec per plugin manager.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the full command surface at a glance.
- [All options](docs/configuration.md) — every `setup()` option and its default, opening with the ready-to-paste snippets.
- [Config templates](docs/templates/README.md) — copy-paste `setup()` snippets: blockquote colors, feature subsets, picker backends, image preview.
- [Command reference](docs/commands.md) — `:Markdown`, subcommand by subcommand.
- [Keymaps](docs/keymaps.md) / [Bindings cheatsheet](docs/BINDINGS.md)

### The Rest

- [Features](docs/FEATURES/README.md) — one page per area: [headings](docs/FEATURES/HEADINGS.md), [tables](docs/FEATURES/TABLES.md), [links and references](docs/FEATURES/LINKS-AND-REFERENCES.md), [editing and handlers](docs/FEATURES/EDITING-AND-HANDLERS.md), [highlighting and UI](docs/FEATURES/HIGHLIGHTING-AND-UI.md), [integrations](docs/FEATURES/INTEGRATIONS.md).
- [Link hover preview](docs/hover.md) — the float that previews what a link or a bare path points at, and everything it can show.
- [Image captions](docs/image-captions.md) — implicit figures vs. an HTML `<figure>` vs. `@fig:` cross-references, and what each costs in the editor.
- [Fenced-block scope](docs/fenced-scope.md) — why a Markdown document inside another one needs its own scope.
- [Width-limited table wrapping](docs/table-wrap.md) — the `:MDTable*` family, and why the formatter aligns to natural width.
- [Menu integration](docs/menu.md) — the context-aware entries shipped for nvzone/menu.
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Workflow](docs/WORKFLOW.md) — how the features combine while actually writing a document, rather than what each one does.
- [Health check](docs/health.md) — what `:checkhealth markdown` reports.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a handler or a command.
- [Feedback](https://github.com/StefanBartl/markdown.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/markdown.nvim/discussions).

`:help markdown.nvim` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

markdown.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
