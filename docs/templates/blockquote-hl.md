# Blockquote highlighting (`blockquote_hl`)

By default, a Markdown blockquote line (`> like this`) gets **VS Code-style
coloring**: the `>` marker and the quoted text are colored a fixed green
(`#6A9955` / `#7EE787`, independent of your colorscheme), and the whole line
gets a dimmed green background stretching to the window edge — not just
behind the text characters.

If that's not what you want, everything below is opt-in/opt-out via
`blockquote_hl` in `setup()`. See [docs/configuration.md](../configuration.md)
for the full field reference.

## Turn it off entirely

No color, no background — blockquote lines render like plain text.

```lua
require("markdown").setup({
  blockquote_hl = {
    marker_fg = false, -- fall through to your colorscheme's own colors
    text_fg   = false,
    text_bg   = nil,   -- no background fill
    text_bold = false,
  },
})
```

## Keep the coloring, drop the background dim

Marker/text stay green; the line no longer gets the extra background band.

```lua
require("markdown").setup({
  blockquote_hl = {
    text_bg = nil,
  },
})
```

## Use your colorscheme's colors instead of the fixed green

`false` opts a field back into colorscheme derivation: a markdown-specific
Tree-sitter group first (`@markup.quote.markdown` / `@text.quote`), then
`Comment` (marker) / `String` (text), then the same green hex as a last
resort if neither resolves. Colors re-derive automatically on every
`:colorscheme` change.

```lua
require("markdown").setup({
  blockquote_hl = {
    marker_fg = false,
    text_fg   = false,
    -- text_bg stays "dimm" here, so the background is still derived — from
    -- whatever marker_fg resolves to under your colorscheme, not the fixed
    -- green.
  },
})
```

## Pick your own fixed colors

Any field takes an explicit hex and always wins over both the default and
colorscheme derivation.

```lua
require("markdown").setup({
  blockquote_hl = {
    marker_fg   = "#61afef", -- e.g. a blue marker
    text_fg     = "#98c379",
    text_bg     = "dimm",    -- still derives a dim bg, now from marker_fg (blue)
    text_bold   = true,
    text_italic = false,
  },
})
```

## Link to an existing highlight group

Overrides every other field — both the marker and the text use exactly the
named group (fg, bg, everything).

```lua
require("markdown").setup({
  blockquote_hl = { link = "Comment" },
})
```
