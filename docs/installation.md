# Installation

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **>= 0.9** | core |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | **required** | the `:Markdown`/`:TableView*` command layer (`lib.nvim.bindings.usercmd.composer`), plus buffer debouncing |

No other external tools required beyond lib.nvim — every other feature runs
on built-in Neovim APIs.

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
