# Running only a subset of features (`just_enable`)

By default every gateable feature is on. `features.just_enable` is a hard
allowlist — only the listed names run, everything else (including keymaps
and `:Markdown` subcommands not in the list) is off. It wins over
`disable`/`enable`.

The full canonical feature-name list lives in
[docs/configuration.md](../configuration.md#feature-gating); the ones below
are the most commonly requested slices.

## Just the table stack (formatter, table mode, tableize, floating preview)

Useful if you only want `markdown.nvim` for its table tooling and already
have something else handling headings/TOC/links.

```lua
require("markdown").setup({
  features = {
    just_enable = { "table", "tableview" },
  },
})
```

## Just TOC + heading navigation

```lua
require("markdown").setup({
  features = {
    just_enable = { "toc", "fold" },
  },
})
```

## Everything except keymaps (you bind your own keys)

This is the one case where `disable` (not `just_enable`) is the right tool:
`just_enable` would also drop every non-keymap feature you didn't list.

```lua
require("markdown").setup({
  features = {
    disable = { "keymaps" },
  },
})
```

Then map the actions yourself via `require("markdown").actions` — see
[docs/keymaps.md](../keymaps.md) for the full actions table.

## Turn everything off, re-enable one thing

`disable = "all"` plus `enable` is the inverse of `just_enable` — same
result, different starting point. Prefer `just_enable` unless you're
toggling this dynamically and already have a `disable = "all"` base.

```lua
require("markdown").setup({
  features = {
    disable = "all",
    enable  = { "toc" },
  },
})
```
