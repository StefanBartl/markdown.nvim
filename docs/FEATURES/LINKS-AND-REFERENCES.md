# Links and references

Wrapping text into a link, scanning/collecting links, flagging dead ones,
keeping `#anchor` links and the TOC in sync when headings are renamed, and
turning link targets into real files.

## Link wrap

Wrap the word under the cursor (or a visual selection) in a Markdown link,
auto-classifying the inner text: a URL or file path lands in the `(target)`
part, plain text in the `[text]` part.

- **Module:** `core/wrap_link.lua`
- **Keymap:** `<leader>[` (n and v) — ids `wrap_link_n`, `wrap_link_v` (see
  [keymaps.md](../keymaps.md#bold-wrap--link-wrap))
- **Config:** `map_wrap_link` (default `true`)

## Link scan

Collects every link (`[text](target)`, bare URLs, `#anchor`s, and raw HTML
`<img src>` / `<a href>`) in a line or buffer — the shared primitive
`links show`/`create fs`/`link_diagnostics` all build on.

- **Module:** `core/link_scan.lua`, with HTML handled by `core/html_links.lua`
- Not a standalone command; powers `:Markdown links show` and
  `:Markdown create fs` below, plus `link_diagnostics` and the hover.

## HTML links and `<figure>` blocks

`src` / `href` attributes are reported in the same `Mkdn.Link` shape as
markdown links, and a multi-line `<figure>` resolves as one unit: the
`<figcaption>` line — which contains no target of its own — hovers and opens
the block's `<img>`. That is what lets a captioned image keep the hover,
`mi`, picker entry and dead-link check a plain `![alt](src)` has.

- **Module:** `core/html_links.lua`
- **Details:** [Image captions](../image-captions.md)

## Link diagnostics

Flags dead relative-file links and duplicate heading anchors via
`vim.diagnostic`.

- **Module:** `core/link_diagnostics.lua` (namespace `markdown_links`)
- **Command:** `:Markdown links check` (see
  [commands.md](../commands.md#markdown-links))
- **Config:** `links.diagnostics.mode` (`"off"` default | `"save"`)
- **Autocmd:** `MarkdownNvimLinkDiagnostics` augroup (`bindings/autocmds.lua`),
  `BufWritePost`, opt-in via `links.diagnostics.mode = "save"`

## Link sanitize

Normalizes inline-link targets: backslashes become forward slashes and a bare
relative path gets a `./` prefix (`[t](doc.md)` → `[t](./doc.md)`). URLs,
`mailto:`/scheme targets, `#anchor` links, absolute paths, and `~`-relative
paths are left untouched. Runs on every save by default — this is the one
`links.*` behavior that is on unless you turn it off, which is why a link
written as `.\foo\bar.md` shows up normalized the next time the file is
opened even if nothing else about the buffer's links was touched.

- **Module:** `core/link_sanitize.lua`
- **Command:** `:Markdown links sanitize [%|cwd|<file>]` — the manual, on-demand
  form of the same pass (see [commands.md](../commands.md#markdown-links))
- **Config:** `links.sanitize_on_save` (default `true`)
- **Autocmd:** `MarkdownNvimLinksSanitize` augroup (`bindings/autocmds.lua`),
  `BufWritePre`

## Links show / create

Scan for links and open the chosen one through a picker (URL → browser,
`#anchor` → in-buffer jump, file → system app or `:edit`); or generate
Markdown links from a directory tree to the clipboard.

- **Modules:** `commands/links.lua`, `commands/markdown_links.lua`
- **Command:** `:Markdown links show [%|cwd|<file>]`, `:Markdown links
  create [-r] [--noignore] [--root <path>] <path>` (see
  [commands.md](../commands.md#markdown-links))
- **Config:** `links.picker` (`"hover_select"` default | `"select"` |
  `"telescope"` | `"fzf"` — see [INTEGRATIONS.md](INTEGRATIONS.md#picker-backends))
- **Image-aware:** when the scanned links include an image and both
  `snacks.picker` and images.nvim are installed, `show` routes through a
  `snacks.picker` with a live per-item image preview instead.

## Reference sync (`refs`)

Keeps in-document `[text](#anchor)` links and the TOC consistent when
headings are renamed — heading identity is tracked with extmarks (plus a
positional fallback), so a rename is detected as `old-anchor → new-anchor`
and propagated to every inline link and the TOC.

- **Module:** `core/refs.lua` (`attach`, `reconcile`, `on_change`, `detach`)
- **Command:** `:Markdown refs sync|check|live [on|off|toggle]|baseline`
  (see [commands.md](../commands.md#markdown-refs))
- **Config:** `refs.mode` (`"off"`|`"save"` default|`"live"`),
  `refs.debounce_ms`, `refs.update_toc`, `refs.orphans`
- **Autocmd:** `MarkdownNvimRefs` augroup (`bindings/autocmds.lua`) —
  baseline snapshot on `FileType`, sync on `BufWritePre` (`"save"`) or
  debounced `TextChanged`/`TextChangedI` (`"live"`), teardown on
  `BufWipeout`. Feature name `refs`.

## Anchor jump and slug

Jump to a `#heading` anchor (GFM slug, duplicate-title handling); the slug
algorithm itself is shared by TOC, refs, and link diagnostics so anchors
stay consistent everywhere.

- **Modules:** `anchor/jump.lua`, `anchor/is_anchor_line.lua`,
  `anchor/is_html_anchor_line.lua`, `anchor/is_html_extern_anchor_line.lua`,
  `anchor/is_inside_toc_block.lua`, `core/slug.lua`
- **Keymap:** `mj` (see [keymaps.md](../keymaps.md#cursor-action-handler));
  also reachable via the generic cursor-action handler (double-click, `ma`)
  — see [EDITING-AND-HANDLERS.md](EDITING-AND-HANDLERS.md)
- **Config:** `toc.anchor_style` (`"gfm"` default | `"keep-case"`),
  `toc.anchor_separator` (default `"-"`)

## Create filesystem entries from links

Walks the Markdown-link targets in a range (or the whole buffer) and
creates the corresponding files/directories — a trailing `/` denotes a
directory. URLs, `mailto:`, and `#anchors` are skipped.

- **Module:** `commands/create.lua`
- **Command:** `:Markdown create fs` (see
  [commands.md](../commands.md#markdown-create))

## Delete a link and the file behind it

`DD` on a line whose first link resolves to an existing file offers to delete
the file along with the line. The confirmation dialog names the resolved path
and counts the *other* links pointing at the same file, so the answer is an
informed one rather than a reflex. On any other line — no link, a URL, a
`mailto:`, an in-document `#anchor`, a directory, or a target that is not on
disk — it is plain `dd`, `v:count` included.

Both the reference scan and the dialog are asynchronous, so the buffer is
re-read against the remembered line before anything is removed. Without
lib.nvim there is no dialog, and without a dialog the key degrades to `dd`
rather than deleting a file unasked.

`DD` shadows the built-in `D` for 'timeoutlen' in Markdown buffers; that is
the trade the key makes, and `keymaps.delete_link_file` moves or disables it.

- **Module:** `core/link_delete.lua`, counting via `core/file_refs.lua`
- **Keymap:** `DD` — id `delete_link_file` (see
  [keymaps.md](../keymaps.md#cursor-action-handler))
- **Dialog:** `lib.nvim`'s `ui.kit.confirm`
