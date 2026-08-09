# Integrations

Thin wrappers/adapters around optional host plugins — all soft
dependencies: absent, they warn instead of erroring, and `:checkhealth
markdown` reports whether each was detected.

## render-markdown.nvim

- **Module:** `commands/render.lua`
- **Command:** `:Markdown render [on|off|toggle]` (see
  [commands.md](../commands.md#markdown-render--markdown-preview--markdown-mdview))
- **Health:** `:checkhealth markdown` reports detection.

## markdown-preview.nvim

- **Module:** `commands/preview.lua`
- **Command:** `:Markdown preview [start|stop|toggle]` — also
  auto-refreshes on buffer switch while active (`BufEnter` for `*.md`)

## mdview.nvim

- **Module:** `commands/mdview.lua`
- **Command:** `:Markdown mdview [path]` (default: current buffer's file) —
  delegates to `:MDViewStart`, idempotent (starts a session, or pushes the
  file into an already-running one)

## images.nvim

Live link-preview for image links, in-Neovim image preview for `mi`, and
the `:Markdown image` delegator — see
[editing-and-handlers.md](editing-and-handlers.md#image-paste--screenshot)
and [links-and-references.md](links-and-references.md#links-show--create)
for the two call sites. Preferred in-Neovim preview provider when several
are installed (snacks.nvim/image.nvim are Kitty-APC-only and don't draw on
native Windows Neovim in WezTerm; images.nvim's
`images.browse.draw_in_window()` does).

- **Config:** `image.preview` (`"ask"`|`"preview"`|`"system"`)

## nvzone/menu

markdown.nvim doesn't depend on a menu plugin; it *provides* entries in the
shape nvzone/menu expects, for a host menu dispatcher to compose.

- **Module:** `integrations/menu.lua`
- **Config:** `menu.enable` (default `true`), `menu.fold`/`menu.toc`/
  `menu.refs` (per-entry opt-out)

## Picker backends

Selection backend used by `:Markdown links show` and other pick-one-of-many
prompts.

- **Module:** `util/picker.lua`
- **Config:** `links.picker` — `"hover_select"` (default, lib.nvim's float
  chooser) | `"select"` (`vim.ui.select`) | `"telescope"` | `"fzf"`
  (`fzf-lua`). A requested backend whose plugin isn't installed falls back
  to `vim.ui.select` with a warning.

## which-key

Labels the `<leader>t` keymap group as "Markdown" and `<leader>tv` as
"Markdown TableView"; every other default key carries its own `desc`, no
group needed. Soft-guarded — a no-op if which-key isn't installed. Handles
both which-key v3 (`wk.add`) and v2 (`wk.register`).

- **Module:** `bindings/which_key.lua`

## lib.nvim (required, not soft)

Not an optional integration — the one hard runtime dependency. Supplies the
`:Markdown`/`:TableView*`/`:MDTable*` command layer
(`lib.nvim.usercmd.composer`) and `core/table_mode.lua`'s auto-format
debounce (`lib.nvim.debounce.buffer`).
