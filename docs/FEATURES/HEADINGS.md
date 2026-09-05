# Headings

Navigation, level shifting, folding, the Table of Contents, section-spacing
enforcement, and the Setext-underline decoration — everything keyed off
ATX (`#`) headings (Setext `===`/`---` is understood by folding and the
`:MarkdownNvimUnderlineHeadings` decorator, but ATX is the format the rest
of the plugin writes).

## Navigation

Move to the previous/next heading — or fenced-code delimiter — or to a
specific level, count-aware.

- **Module:** `core/headings.lua` (`goto_prev_heading`, `goto_next_heading`,
  `goto_prev_heading_level`, `goto_next_heading_level`)
- **Keymaps:** `<C-p>`/`[[` (prev), `<C-f>`/`]]` (next), `{count}<leader><C-p>`/
  `{count}<leader><C-f>` (prev/next at level `count`) — ids `prev_heading`,
  `prev_heading_bracket`, `next_heading`, `next_heading_bracket`,
  `prev_heading_level`, `next_heading_level` (see [keymaps.md](../keymaps.md#navigation))
- **Config:** `nav.fences` (default `true`) — `<C-p>`/`<C-f>`/`[[`/`]]` also
  stop on a fenced block's opening and closing delimiter line. The by-level
  hops (`<leader><C-p>`/`<leader><C-f>`) stay headings-only, so heading-only
  navigation is always one keystroke away.
- **Scope-aware:** when [fenced-scope](../fenced-scope.md) is enabled and the
  cursor is inside a markdown-family fenced block, navigation stays within
  the block; outside, it skips over fenced interiors.

## Heading level shift

Increase/decrease a heading's level (`#` count), for the current line, a
visual selection, or the whole buffer/current fenced block.

- **Module:** `core/headings.lua` (`shift_range`, `shift_visual_selection`,
  `_op_increase`/`_op_decrease`)
- **Keymaps:** `<C-Right>`/`<C-Left>` (current line, n/v/x), `<S-Right>`/
  `<S-Left>` (whole buffer or current fenced block, n) — ids
  `heading_inc`/`heading_dec`, `heading_inc_visual`/`heading_dec_visual`,
  `heading_inc_all`/`heading_dec_all` (see [keymaps.md](../keymaps.md#heading-level-shift))
- **Config:** `protect_h1` (default `false`) — when `true`, H1 can't be
  shifted down into plain text.

## Folding

Custom `foldexpr` for ATX and Setext headings.

- **Module:** `core/fold.lua` (`foldexpr`, `toggle_under_cursor`,
  `unfold_all_center`, `heading_fold_row`), `core/fold_levels.lua`,
  `core/fold_prev.lua`
- **Keymaps:** `zf`/`<localleader>f` (toggle under cursor), `zu` (unfold all),
  `zi` (fold prev heading, count-aware `{n}zi`), `zk` (toggle outline,
  count-aware `{n}zk`) — ids `fold_toggle_zf`, `fold_toggle`, `unfold_all`,
  `fold_prev_heading`, `fold_h2plus` (see [keymaps.md](../keymaps.md#folding))
- **Config:** `use_zf_override` (default `true`) — remaps built-in `zf`.
  Feature name `fold` (gateable).
- **Autocmd:** `MarkdownNvimFold` augroup (`bindings/autocmds.lua`) sets
  `foldmethod=expr`/`foldexpr`/`foldenable`/`foldlevel` on `FileType`.
- **Extended by table-wrap:** when `:MDTableFoldRow`/`:MDTableFoldAll` (see
  [TABLES.md](TABLES.md#table_wrap--width-limited-wrapping-mdtable)) have run
  in a buffer, `foldexpr` also nests a table's continuation rows one level
  under their heading section (`vim.b.mdtable_fold_continuations`).

## Table of Contents

Insert or refresh a TOC with GFM-like anchors and duplicate-title handling.

- **Module:** `core/toc.lua`
- **Keymap:** `{count}<leader>toc` (count = max heading level) — id `toc`
  (see [keymaps.md](../keymaps.md#toc))
- **Command:** `:[range]Markdown toc [level] [min=N] [max=N] [marker=X]
  [--sep|--no-sep]` (see [commands.md](../commands.md#markdown-toc))
- **Config:** `toc` table (`header`, `marker`, `min_level`, `max_level`,
  `anchor_style`, `anchor_separator`). Feature name `toc`.
- **Scope-aware:** same fenced-scope behavior as navigation, above.

## Headline spacing

Enforces a `[blank]---[blank]` separator between consecutive H2+ sections,
including a closing separator after the final section — but only for
sections that actually have content. A section with nothing between its
heading and the next one (or EOF, for the final section) gets a single
blank line instead; no `---` is inserted where there's no text to
separate. Idempotent.

- **Module:** `core/headline_spacing/init.lua` (`apply_headl_separators`,
  `find_sections_needing_separator`)
- **Command:** `:Markdown headline_spacing` (on-demand form; see
  [commands.md](../commands.md#markdown-headline_spacing))
- **Config:** `ensure_headline_spacing` (default `true`) — also runs as part
  of a TOC refresh (`<leader>toc`/`:Markdown toc`), overridable per call with
  `--sep`/`--no-sep`. Feature name `headline_spacing`.

## Underline headings (Setext-style decoration)

Inserts/corrects a line of `=` below every ATX heading's text, matching its
length — a purely visual decoration (the `#` marker stays; applies at every
heading level, unlike real Setext syntax, which is only H1/H2). Idempotent;
fenced-code interiors are skipped.

- **Module:** `core/underline_headings.lua` (`apply`, `apply_range`)
- **Command:** `:MarkdownNvimUnderlineHeadings` (buffer-local; see
  [commands.md](../commands.md#buffer-local-commands-markdown-buffers-only))
- **Config:** `underline_headings.char` (default `"="`). Feature name
  `underline_headings` (gateable; `features.disable = { "underline_headings" }`
  turns the command off).
