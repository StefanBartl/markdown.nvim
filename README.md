```
                         __       __
   ____ ___  ____ ______/ /______/ /___ _      ______
  / __ `__ \/ __ `/ ___/ //_/ __  / __ \ | /| / / __ \
 / / / / / / /_/ / /  / ,< / /_/ / /_/ / |/ |/ / / / /
/_/ /_/ /_/\__,_/_/  /_/|_|\__,_/\____/|__/|__/_/ /_/
            a self-contained markdown toolkit
```

![version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

> 💡 Pairs well with [cascade.nvim](https://github.com/StefanBartl/cascade.nvim):
> markdown.nvim renders and structures the document (TOC, folding, tables),
> while cascade.nvim edits the list content inside it (continue, renumber, rotate).

A self-contained Markdown toolkit for Neovim. Pure FileType-scoped — zero side
effects on non-Markdown buffers. Requires Neovim >= 0.9 and
[lib.nvim](https://github.com/StefanBartl/lib.nvim) (the `:Markdown`/
`:TableView*` command layer, plus buffer debouncing); no external tools.

---

## Quickstart

```lua
-- lazy.nvim
{
  "StefanBartl/markdown.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown").setup()
  end,
}
```

See [docs/installation.md](docs/installation.md) for packer.nvim and vim-plug.

---

## Documentation

- [Features](docs/features.md) — full overview of every module (headings, fold, TOC, tables, links, and more).
- [Installation](docs/installation.md) — requirements and setup for lazy.nvim, packer.nvim, vim-plug.
- [Configuration](docs/configuration.md) — full `setup()` reference with defaults, and feature gating.
- [Keymaps](docs/keymaps.md) — every default keymap, remapping/disabling, and the actions API.
- [Commands](docs/commands.md) — the `:Markdown` command and all its subcommands.
- [Fenced-block scope](docs/fenced-scope.md) — treating a fenced Markdown block as its own sub-document.
- [Menu integration](docs/menu.md) — context-aware entries for nvzone/menu.
- [Health](docs/health.md) — what `:checkhealth markdown` reports.
- [Architecture](docs/architecture.md) — source tree layout and module responsibilities.
- [Bindings cheatsheet](docs/BINDINGS.lua) — machine-readable list of every binding.
- [Roadmap](docs/ROADMAP.md) — planned work.
