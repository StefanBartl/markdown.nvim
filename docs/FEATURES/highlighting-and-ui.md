# Highlighting and UI

Colorscheme-aware overrides for fenced/inline code, blockquotes, and inline
links, plus treating a fenced Markdown block as its own sub-document.

## Fenced-code and inline-code highlight override

Lets injected-language colors shine through fenced code blocks, and gives
inline `` `code` `` a distinct style instead of blending into prose.

- **Module:** `fenced_fix/init.lua`
- **Config:** `fenced_fix.inline_base_hl` (candidate highlight groups, first
  that exists wins), `fenced_fix.inline_style` (`bold`/`italic`),
  `fenced_fix.delimiter_hl` (backtick delimiter color). Feature name
  `fenced_fix`.
- No keymap/command — purely a highlight-group setup, reapplied on
  `ColorScheme`.

## Blockquote highlighting

Two-region blockquote coloring (the `>` marker and the text after it) via a
decoration provider; VS Code-style dimmed line background by default.

- **Module:** `hl_options/hl_groups/blockquote.lua`, orchestrated by
  `hl_options/init.lua`
- **Config:** `blockquote_hl.marker_fg`/`text_fg` (default a fixed VS
  Code-style green, independent of the active colorscheme; set to `false`
  to derive from the colorscheme instead), `text_bg` (`"dimm"` by default),
  `text_bold`/`text_italic`. Feature name `hl`.
- Re-derived on every `ColorScheme` event.

## Inline-link highlighting

Neovim's built-in markdown treesitter underlines link URLs/labels, which
draws a full-width underline across a wrapped line for long URLs — off by
default here.

- **Module:** `hl_options/hl_groups/link.lua`
- **Config:** `link_hl.underline` (default `false`; set `true` to restore
  the built-in behavior). Feature name `link_hl`.

## Fenced-block scope

Treats a `` ```markdown ``/`md`/`mdx`/`ascii-markdown`/`ascii-md` fenced
block as its own document scope: TOC, heading nav, anchor jump, and heading
shift act on the block's interior when the cursor is inside one, and skip
every fenced block's interior when it's outside. Full reference:
[fenced-scope.md](../fenced-scope.md).

- **Modules:** `scope/init.lua` (`detect`, `op_enabled`, `is_excluded`),
  `scope/builtin.lua` (fallback fence scanner)
- **Command:** `:Markdown scope [on|off|toggle|status]` (runtime override;
  see [commands.md](../commands.md#markdown-scope))
- **Config:** `fenced_scope.enable` (default `true`), `fenced_scope.langs`,
  `fenced_scope.provider` (`"auto"` default | `"color_my_ascii"` |
  `"builtin"`), `fenced_scope.operations` (per-op opt-out: `toc`, `nav`,
  `jump`, `shift`, `fold`). Feature name `fenced_scope`.
- **Optional host:** prefers
  [color_my_ascii](https://github.com/StefanBartl/color_my_ascii.nvim)'s
  fence-detection API when installed; falls back to the built-in scanner
  otherwise.
