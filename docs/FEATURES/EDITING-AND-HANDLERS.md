# Editing and cursor-action handlers

Bold-toggling, and the "what does the thing under my cursor mean" dispatcher
that opens anchors, images, URLs, and files.

## Bold wrap

Toggle `**bold**` on a visual selection.

Charwise (`v`) wraps exactly what is selected. Linewise (`V`) wraps the whole
line — every selected line, one span each — because that is what selecting a
line means. Indent, a blockquote's `>`, a list bullet or number, a task-list
checkbox, an ATX heading's hashes and trailing hard-break spaces stay outside
the wrap: `**- item**` is no longer a list item. A range where every non-blank
line is already bold unwraps instead.

- **Module:** `core/wrap.lua`
- **Keymap:** `**` (visual mode) — id `toggle_bold` (see
  [keymaps.md](../keymaps.md#bold-wrap--link-wrap))
- **Config:** `map_double_asterisk` (default `true`), `keep_inner_selection`
  (default `true` — after wrapping, keep only the inner text selected, not
  the `**` markers; charwise only, a linewise toggle re-selects its lines)

## Cursor action handler

Dispatches on whatever is under the cursor: heading/TOC/HTML anchors jump
in-buffer, images open (system viewer or in-Neovim preview), URLs open in
the browser, local files open via the system app (media/binary) or `:edit`
(text-like), and a `.pdf` link gets its own choice — system app vs.
pdfport.nvim, when installed (see
[INTEGRATIONS.md](INTEGRATIONS.md#pdfportnvim)).

- **Module:** `handler/init.lua` (`handle_cursor_action`), delegating to
  `handler/url.lua`, `handler/file.lua`, `handler/image.lua`,
  `anchor/jump.lua`
- **Keymaps:** `<2-LeftMouse>`/`<C-LeftMouse>` (silent — a miss is a normal,
  frequent mouse-move outcome; double-click on a heading toggles its fold
  instead), `ma` (same, non-silent), `mi` (open image specifically), `mj`
  (jump to anchor specifically) — ids `cursor_action_2click`,
  `cursor_action_cclick`, `cursor_action`, `open_image`, `jump_anchor` (see
  [keymaps.md](../keymaps.md#cursor-action-handler))
- **Command:** `:OpenWithSystemApplication` (buffer-local; identical to `ma`
  — see [commands.md](../commands.md#buffer-local-commands-markdown-buffers-only))
- **Config:** `open.external_extensions` (which file extensions launch the
  system app instead of `:edit`); `image.preview` (`"ask"` default |
  `"preview"` | `"system"` — only meaningful with an in-Neovim image
  provider installed, see [INTEGRATIONS.md](INTEGRATIONS.md))

## Image paste / screenshot

Thin delegator to images.nvim's clipboard-image-to-file-and-link and
interactive-screenshot commands, exposed from `:Markdown <Tab>` for
discoverability rather than reimplemented.

- **Module:** `commands/image.lua`
- **Command:** `:Markdown image [paste|screenshot]` (default sub `paste`;
  see [commands.md](../commands.md#markdown-image))
- **Requires:** images.nvim (optional host, soft dependency — warns instead
  of erroring when absent). See
  [INTEGRATIONS.md](INTEGRATIONS.md#imagesnvim)
