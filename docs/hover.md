# Link hover preview

Rest the cursor on a markdown link and a small float shows what it points
at — whatever that is.

```markdown
See [the architecture doc](docs/architecture.md#modules) for details.
                          └─ hover here ─┘
```

```
┌ architecture.md ──────────────────┐
│ ## Modules                        │
│                                   │
│ Every module owns one directory   │
│ with an `init.lua` …              │
└───────────────────────────────────┘
```

## What it previews

| Target | Shown |
| --- | --- |
| **Image** (`png`, `jpg`, `gif`, `webp`, `svg`, …) | Dimensions, format, size — and the picture itself when a provider can draw it |
| **PDF** | Size, plus page 1 rendered inline (via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)) |
| **Markdown file** | First lines, markdown-highlighted |
| **Markdown file + `#anchor`** | Just that section — heading, body, and any deeper subsections, stopping at the next same-level heading |
| **In-page `#anchor`** | The section it points at, from the current buffer |
| **Other file** | First lines, plain |
| **Directory** | Its entries, directories first |
| **URL** | Host, path, decoded query — and optionally the page's `<title>`/description (off by default, see below) |
| **Missing target** | *That it is missing*, and the path that was tried |

That last row matters more than it looks. A hover that immediately says
"this file isn't there" catches broken links while you write them, long
before `:Markdown links check` runs.

## HTML targets and `<figure>` blocks

A hover does not need markdown syntax. Raw `<img src>` and `<a href>` are
link targets too, and a `<figure>` block resolves *as a block*: park the
cursor on the `<figcaption>` — the one line that contains no target at all —
and the float shows the image the caption belongs to.

```markdown
<figure>
  <img src="assets/start.png" alt="Start Screen">
  <figcaption>Abbildung 1: Start Screen</figcaption>
                └─ hover here shows assets/start.png ─┘
</figure>
```

That is what makes a captioned image behave like the plain
`![alt](assets/start.png)` it replaced. See
[Image captions](image-captions.md) for the three ways to caption an image
and what each costs.

## Configuration

```lua
require("markdown").setup({
  hover = {
    enabled = true,
    trigger = { "CursorHold" },  -- add "mouse" to follow the pointer
    delay_ms = 250,
    max_lines = 20,
    max_width = 80,
    border = "rounded",
    inline_images = true,
    url = {
      fetch = false,       -- see "URL previews" below
      timeout_ms = 2000,
    },
  },
})
```

Turn it off entirely with `hover = { enabled = false }`, or via the feature
gate: `features = { disable = { "hover" } }`.

### Triggers

`"CursorHold"` fires after `'updatetime'` ms of not moving — Neovim's own
idle signal, and the default.

`"mouse"` additionally previews what the pointer is over. It needs
`:set mousemoveevent`, which is a **global** Neovim setting; markdown.nvim
deliberately does not set it for you. Without it, the mouse trigger simply
never fires.

`delay_ms` debounces on top of the trigger. With the mouse this is not
optional — without it a hover would be recomputed on every pointer motion.

### URL previews

`url.fetch` is **off by default**, on purpose. A hover that silently issues
HTTP requests would:

- disclose every link you brush past to its host, and
- turn a link-heavy document into a request storm while scrolling.

With it off, URLs still preview — the URL is parsed and shown broken into
host, path and decoded query, entirely locally. Switch `fetch = true` on if
you want `<title>` and `<meta description>` fetched; results are cached per
target.

### Images and PDFs

Metadata (dimensions, size, format) is always shown and needs nothing
installed.

Drawing the actual picture into the hover needs
[images.nvim](https://github.com/StefanBartl/images.nvim): it is the only
supported provider that can draw into a window it does not own
(`browse.draw_in_window`). snacks.nvim and image.nvim need a buffer of
their own, which a borrowed hover window is not — with those installed you
still get the metadata float, just no inline picture. Set
`inline_images = false` to skip drawing entirely.

PDF page rendering additionally needs pdfport.nvim (which uses `pdftoppm`).
It runs asynchronously: the float appears immediately with `rendering page
1…`, and the page replaces it when ready. Move the cursor away first and
the render is discarded rather than popping up over unrelated text.

## On demand

Beyond the automatic trigger:

```lua
require("markdown").hover()       -- preview the link under the cursor now
require("markdown").hover_hide()  -- close it
```

`hover()` ignores the `enabled` flag, so it works as a keymap even with the
automatic hover switched off:

```lua
vim.keymap.set("n", "K", require("markdown").hover, { buffer = true })
```

## Behavior notes

- **The float never takes focus** and closes on the next cursor move,
  insert-mode entry, window scroll or buffer switch.
- **No fallback to "the only link on the line".** Unlike the link *opener*
  (`ml`), which will act on a line's single link wherever the cursor is, a
  hover only fires when the cursor is genuinely on the link — otherwise it
  would pop up while you type unrelated text.
- **Relative targets resolve against the document's own directory**, not
  the editor's working directory, which is what a markdown link means.
- **Results are cached** per target, keyed including the file's mtime, so
  an edited target is re-read rather than served stale.
- **`K` and LSP.** If you map `K` to the hover in a buffer that also has an
  LSP attached, you are replacing `vim.lsp.buf.hover` there. Map it
  buffer-locally (as above) rather than globally.

## Implementation

Nothing here re-parses markdown. Link detection is
[`markdown.core.link_scan`](../lua/markdown/core/link_scan.lua), which
already handles inline links, bare URLs, `<…>` autolinks and
trailing-punctuation trimming.

| Module | Responsibility |
| --- | --- |
| `markdown.hover` | Trigger, debounce, cache, cancellation, dispatch |
| `markdown.hover.classify` | Target string → type (the only filesystem touch is one `fs_stat`) |
| `markdown.hover.float` | The window: cursor-relative, unfocused, single-instance |
| `markdown.hover.preview.text` | Files, sections, anchors, directories, missing targets |
| `markdown.hover.preview.media` | Images and PDFs |
| `markdown.hover.preview.url` | URL parsing, optional metadata fetch |

Asynchronous previews (PDF rasterization, URL fetch) are guarded by a
generation counter: if the cursor moves on before the result lands, the
result is dropped instead of opening a float for a link you have already
left.
