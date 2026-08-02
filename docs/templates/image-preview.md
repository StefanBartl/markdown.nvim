# Image preview mode (`image.preview`)

`mi` (follow the image target under the cursor) can render the image inline
in a floating window instead of handing it to the system viewer — but only
when an in-Neovim preview provider is installed
([snacks.nvim](https://github.com/folke/snacks.nvim)'s `Snacks.image`, or
[image.nvim](https://github.com/3rd/image.nvim), both soft dependencies).
With neither installed, every mode below behaves like `"system"` — there's
no alternative to choose between.

## Default: ask each time

```lua
require("markdown").setup({
  image = { preview = "ask" },
})
```

## Always preview in Neovim (when a provider is available)

```lua
require("markdown").setup({
  image = { preview = "preview" },
})
```

## Always hand off to the system viewer

Skip the in-Neovim path entirely, even if a provider is installed.

```lua
require("markdown").setup({
  image = { preview = "system" },
})
```
