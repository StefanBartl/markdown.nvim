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
