# Installation

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **>= 0.10** | core (`vim.system`, used unconditionally by the reverse-reference search behind `DD` once `rg` is on `$PATH`) |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | **required** | the `:Markdown`/`:TableView*` command layer (`lib.nvim.bindings.usercmd.composer`), plus buffer debouncing |
| `rg` (ripgrep) | optional | speeds up the reverse file-reference search (`core.file_refs`); see [docs/install.json](install.json) |

No other external tools are required — every other integration below is a
plugin, not a CLI, and every one of them is optional:

| | Buys you |
| --- | --- |
| [hover.nvim](https://github.com/StefanBartl/hover.nvim) | The link and path preview float |
| [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) | `.pdf` targets rendered in a buffer, and `:Markdown export pdf` |
| [images.nvim](https://github.com/StefanBartl/images.nvim), [snacks.nvim](https://github.com/folke/snacks.nvim), [image.nvim](https://github.com/3rd/image.nvim) | Image previews in a float, and `:Markdown image paste\|screenshot` |
| [mdview.nvim](https://github.com/StefanBartl/mdview.nvim), render-markdown.nvim, markdown-preview.nvim | The rendering and preview back ends |
| telescope.nvim, fzf-lua, snacks.picker | Picker backends for link selection |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md) |
| [ui.nvim](https://github.com/StefanBartl/ui.nvim) | `ui.kit.select` is the default picker backend and `ui.kit.confirm` backs the `DD` delete-linked-file confirm dialog — both fall back to `vim.ui.select`/a plain `dd` when absent |

`rg` is declared in [install.json](install.json) and read by lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup says what is missing the first time `setup()` runs after installing;
`:Lib deps show markdown.nvim` repeats it, `:Lib deps install markdown.nvim`
offers to install it and asks first. Turn the popup off with
`vim.g.lib_nvim_deps_disable_first_run = true`, or for this plugin only with
`vim.g.lib_nvim_deps_disabled_plugins = { "markdown.nvim" }`.

## Setup

The plugin is FileType-scoped, so `ft = { "markdown", "mdx", "md" }` is the
natural lazy trigger. Use `lazy = false` / eager loading only if you want the
`:Markdown` command available before opening a Markdown buffer.

### lazy.nvim

```lua
{
  "StefanBartl/markdown.nvim",
  dependencies = { "StefanBartl/lib.nvim", "StefanBartl/hover.nvim" },
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "StefanBartl/markdown.nvim",
  requires = { "StefanBartl/lib.nvim", "StefanBartl/hover.nvim" },
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown").setup()
  end,
})
```

### vim-plug

```vim
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/markdown.nvim', { 'for': ['markdown', 'mdx', 'md'] }
```

```lua
require("markdown").setup()
```
