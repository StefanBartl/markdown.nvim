# Installation

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| Neovim | **>= 0.9** | core |

No external tools required. All features run on built-in Neovim APIs.

## Setup

The plugin is FileType-scoped, so `ft = { "markdown", "mdx", "md" }` is the
natural lazy trigger. Use `lazy = false` / eager loading only if you want the
`:Markdown` command available before opening a Markdown buffer.

### lazy.nvim

```lua
{
  "StefanBartl/markdown.nvim",
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown_nvim").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "StefanBartl/markdown.nvim",
  ft = { "markdown", "mdx", "md" },
  config = function()
    require("markdown_nvim").setup()
  end,
})
```

### vim-plug

```vim
Plug 'StefanBartl/markdown.nvim', { 'for': ['markdown', 'mdx', 'md'] }
```

```lua
require("markdown_nvim").setup()
```
