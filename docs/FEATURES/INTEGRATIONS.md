# Integrations

Thin wrappers/adapters around optional host plugins — all soft
dependencies: absent, they warn instead of erroring, and `:checkhealth
markdown` reports whether each was detected.

## Native rendering (formerly render-markdown.nvim)

markdown.nvim renders in the buffer itself (`core/render.lua`, `core/table_render.lua`); no host
plugin is needed and none is called. `:Markdown render [on|off|toggle]` switches the native
renderer and the table grid on or off for the current buffer, `<leader>mrr` does the same,
`render.enabled = true` / `table.render.enabled = true` turn them on for every markdown buffer.

- **Draws:** headings (icon + background), bullets, checkboxes, code blocks (background + language
  label), thematic breaks, block quotes and callouts, inline code / links / images with the markup
  hidden. Everything is extmarks; the text is never touched and the cursor row shows its text.
- **Cost:** only the rows in and around the windows are drawn (`render.margin`), debounced after
  edits and when scrolling.
- **Config:** the `render` block (per-construct switches and icons), see
  [configuration](../configuration.md) and `config/DEFAULTS.lua`; highlight groups
  `MarkdownRender*` with default links.
- **Migrating from render-markdown.nvim:** remove it from the dependencies; if you keep it
  installed next to this, switch one of the two off, both conceal the same markup.
- **Health:** `:checkhealth markdown` reports the state.

## mdview.nvim

- **Modules:** `commands/preview.lua`, `commands/mdview.lua`
- **Commands:**
  - `:Markdown preview [start|stop|toggle]` — start/stop a session for the
    current buffer via `:MDView start`/`:MDView stop`. Once running,
    mdview.nvim follows buffer switches and drives scroll sync itself
    (`browser.behavior`, default `"reuse"`); no auto-refresh workaround is
    needed on this side.
  - `:Markdown mdview [path]` (default: current buffer's file) — delegates to
    `:MDView start`, idempotent (starts a session, or pushes the file into an
    already-running one)

## images.nvim

Live link-preview for image links, in-Neovim image preview for `mi`, and
the `:Markdown image` delegator — see
[EDITING-AND-HANDLERS.md](EDITING-AND-HANDLERS.md#image-paste--screenshot)
and [LINKS-AND-REFERENCES.md](LINKS-AND-REFERENCES.md#links-show--create)
for the two call sites. Preferred in-Neovim preview provider when several
are installed (snacks.nvim/image.nvim are Kitty-APC-only and don't draw on
native Windows Neovim in WezTerm; images.nvim's
`images.browse.draw_in_window()` does).

- **Config:** `image.preview` (`"ask"`|`"preview"`|`"system"`)

## pdfport.nvim

Optional host for two call sites: following a `.pdf` link from the
cursor-action handler, and `:Markdown export pdf`.

- **Modules:** `commands/export.lua` (`:Markdown export`), `handler/file.lua`
  (`open_pdf`)
- **Command:** `:Markdown export pdf [path]` (see
  [commands.md](../commands.md#markdown-export))
- **Reached via:** the cursor-action handler (`ma`/double-click/`<C-LeftMouse>`)
  on a `.pdf` link — see
  [EDITING-AND-HANDLERS.md](EDITING-AND-HANDLERS.md#cursor-action-handler)
- Following a `.pdf` link prompts "System app" vs. "pdfport (new buffer)" when
  pdfport.nvim is installed; without it, opens with the system application
  directly, no prompt. `:Markdown export pdf` exports the current buffer/file
  (or `path`) through pdfport's own producer chain (pandoc + a PDF engine) —
  markdown.nvim neither knows nor names one. Without pdfport.nvim installed,
  or without an available producer, both report a warning instead of
  erroring.

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

Labels the shared keymap-group prefixes: `<leader>t` as "Markdown",
`<leader>tv` as "Markdown TableView", `<leader>mt` as "Markdown Table".
Every other default key carries its own `desc`, no group needed.

- **Module:** `bindings/init.lua`, which forwards the groups to
  `lib.nvim.bindings.keymap.which_key` — lib.nvim owns the which-key
  version handling and the no-op when which-key isn't installed.

## lib.nvim (required, not soft)

- **Module:** `bindings/usrcmds.lua` (the command layer), `core/table_mode.lua` (the debounce)
- **Dependency:** lib.nvim — hard, not soft: without it the commands do not exist

Not an optional integration — the one hard runtime dependency. Supplies the
`:Markdown`/`:TableView*`/`:MDTable*` command layer
(`lib.nvim.bindings.usercmd.composer`) and `core/table_mode.lua`'s auto-format
debounce (`lib.nvim.debounce.buffer`).

**`conceallevel`.** The native renderer, the table grid and table truncate all need `conceallevel >= 2`.
`core/conceal_guard.lua` raises it per window, remembers the original once however many of them are on,
and gives it back when the last one lets go (also in splits and when a window shows another buffer).
