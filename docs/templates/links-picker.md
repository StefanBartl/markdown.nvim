# Link picker backend (`links.picker`)

`:Markdown links show` (and anything else that needs to let you pick from a
list of links) uses `links.picker` to decide what UI shows the list. Default
is `hover_select` (lib.nvim's own float chooser — no extra dependency). A
requested backend whose plugin isn't installed falls back to
`vim.ui.select` with a warning, so these are safe to set even before you've
installed the corresponding plugin.

## Default: lib.nvim's float chooser

```lua
require("markdown").setup({
  links = { picker = "hover_select" },
})
```

## Plain `vim.ui.select`

Whatever your `vim.ui.select` override provides (dressing.nvim, snacks.nvim,
telescope-ui-select, or Neovim's builtin prompt if you haven't overridden it).

```lua
require("markdown").setup({
  links = { picker = "select" },
})
```

## telescope.nvim

Requires `nvim-telescope/telescope.nvim` installed (soft dependency, not
declared in this plugin's own deps).

```lua
require("markdown").setup({
  links = { picker = "telescope" },
})
```

## fzf-lua

Requires `ibhagwan/fzf-lua` installed (soft dependency).

```lua
require("markdown").setup({
  links = { picker = "fzf" },
})
```
