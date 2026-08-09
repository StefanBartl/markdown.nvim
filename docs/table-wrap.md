# Width-limited table wrapping

`table_fmt`'s formatter aligns columns to their *natural* width — the widest
cell wins, unbounded. `table_wrap` adds an opt-in width **cap**: cells that
exceed a column's planned width are wrapped onto continuation rows of the
same logical table row, while staying valid GFM (every physical row keeps
the same pipe count). Off by default — nothing changes until you run a
`:MDTable*` command or set `table.wrap.enabled = true`.

```markdown
| Name | Description                                                |
| ---- | ----------------------------------------------------------- |
| bb   | a somewhat long description that overflows the column width |
```

`:MDTableWrap` with `max = 20` turns the second row into:

```markdown
| Name | Description          |
| ---- | --------------------- |
| bb   | a somewhat long       |
|      | description that      |
|      | overflows the column  |
|      | width                  |
```

Continuation rows carry a `↳` gutter sign (virtual text — the buffer text
stays clean GFM, nothing is written for the marker itself).

## Commands

| Command | What |
|---|---|
| `:MDTableWrap` | Wrap the table at the cursor (falls back to every table in the buffer, off any table) |
| `:MDTableUnwrap` | Merge continuation rows back into one physical row each |
| `:MDTableWrapVisual[!]` | Wrap tables in the visual selection; `!` unwraps first for a clean recompute |
| `:MDTableWrapVisible[!]` | Wrap tables intersecting the visible window range; `!` unwraps first |
| `:MDTableReflowHeader` | Reflow only the header + separator; body rows untouched |
| `:MDTableFoldRow` | Fold the continuation block under the cursor |
| `:MDTableFoldAll` | Fold every continuation block in the buffer |
| `:MDTableProfile {compact\|docs\|wide}` | Load a named preset from `table.wrap_profiles` |
| `:MDTableCol {inc\|dec} [n]` | Widen/narrow the column under the cursor by `n` (default 1); takes it from (or gives it to) the neighboring column, so the row's total width is preserved |
| `:MDTableAlign {cycle\|left\|center\|right}` | Cycle (or set) the alignment of the column under the cursor |
| `:MDTableFlavor {github\|loose}` | `github`: strict GFM (min 3-dash separator, spaced style); `loose`: no forced minimum |
| `:MDTableLint` | Flag unequal cell counts, missing separators, empty header cells (`vim.diagnostic`, namespace `markdown_table`) |
| `:MDTableFixMissingSeparator` | Insert a separator line after every table block missing one |
| `:MDTableDebug` | Print the resolved column-width plan (avail/pipes/padding/sum, per-column width/natural/min/max/mode) |
| `:MDTableToCSV [path]` | Export the table at the cursor as CSV, to `path` or the `+` register |
| `:MDTableFromCSV [path]` | Insert a GFM table below the cursor, parsed from CSV (`path` or the `+` register) |

Vim user-command names may only contain alphanumerics, so the original
`:MDTableCol+`/`:MDTableCol-` idea became `:MDTableCol inc|dec [n]`.

## Configuration

```lua
require("markdown").setup({
  table = {
    wrap = {
      enabled = false,        -- plain `:Markdown table format`/table mode also wrap when true
      auto = false,           -- fit column widths to the window instead of a fixed `max`
      min = 3,
      max = nil,               -- nil = unlimited (still capped by `auto`)
      pad = 1,
      join = " ",              -- :MDTableUnwrap continuation-cell join: " " | "<br>"
      soft_break_chars = "/._-?,&=#@:",
      continuation_marker = "↳",
      flavor = "github",       -- "github" | "loose"
      auto_resize = false,     -- debounced reflow of auto-mode tables on VimResized/WinResized
      resize_debounce_ms = 300,
      selective_reflow = false, -- BufWritePre: only reflow tables that actually changed
    },
    wrap_profiles = {
      compact = { auto = false, min = 4, max = 20, pad = 0 },
      docs    = { auto = true,  min = 10, max = 40, pad = 1 },
      wide    = { auto = true,  min = 15, max = nil, pad = 1 },
    },
  },
})
```

`col_overrides` (see `table.col_overrides`, `:Markdown table format`) also
accepts `max`/`min` per column, on top of the existing `align`:

```lua
table.col_overrides = { { col = "Description", max = 40 } }
```

## Per-table directive

A comment immediately above a table overrides the config defaults for that
one table only:

```markdown
<!-- mdwrap: auto=false max=40 min=12 pad=1 join=br -->
| Name | Description |
| ---- | ------------ |
```

Recognized keys: `auto`, `max`, `min`, `pad`, `join` (`br`/`<br>` or anything
else for a plain space).

## Cell wrapping rules

Breaking prefers whitespace and `soft_break_chars`, and never splits inside
a `[text](url)` link or `` `code` `` span — wrapping a table full of links
would otherwise feed broken URLs straight into `:Markdown links check`. A
single unbreakable token wider than the planned width overflows on its own
line rather than being cut.

## Unwrap heuristic (and its one caveat)

Continuation rows carry no in-buffer marker (the `↳` hint is virtual text
only), so `:MDTableUnwrap`/`:MDTableWrapVisual!`/`:MDTableWrapVisible!`
detect them structurally: a non-separator row with at most one non-empty
cell, directly following another row of the same table, is treated as a
continuation of the nearest preceding "primary" row. This survives edits and
file reloads without any persisted state, at the cost of one edge case: a
genuine data row that happens to have only one non-empty cell right after
another row is indistinguishable from a continuation and gets merged too.

## Fold continuation blocks

`:MDTableFoldRow`/`:MDTableFoldAll` extend the existing heading `foldexpr`
(`core.fold`) rather than fighting it with a separate manual-fold pass: once
either command has run in a buffer, continuation rows fold one level deeper
than the heading section they're in. Both commands force
`foldmethod=expr`/a fold refresh, which reasserts the heading-fold settings
`fold` already installs.

## API hooks

```lua
require("markdown.core.table_wrap").on("before_reflow", function(bounds, opts) end)
require("markdown.core.table_wrap").on("after_reflow", function(bounds, opts) end)
```

`bounds` is `{ start_line, end_line }` (1-indexed, inclusive) for the table
being reflowed; `after_reflow` receives the post-reflow bounds. Errors inside
a hook are caught and ignored (`pcall`), so a broken hook can't break a wrap.
