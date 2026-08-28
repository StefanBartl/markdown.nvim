# Link hover preview

Rest the cursor on a markdown link — or on a path written as plain text —
and a small float shows what it points at, whatever that is.

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
| **Image** (`png`, `jpg`, `gif`, `webp`, `svg`, …) | The picture itself, in a float shaped to its aspect ratio — or dimensions, format and size where nothing can draw |
| **PDF** | Page 1 rendered inline, in a float shaped to the page (via [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)) — or size and a reason where it cannot be rendered |
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

## Paths without link syntax

A target does not have to be a link, and does not have to sit in a markdown
file. A path written as ordinary text hovers too — in prose, in a code
comment, in output pasted from a log:

```
./assets/diagram.png          → the picture
../ROADMAP/ROADMAP.md         → its first lines, markdown-highlighted
...AppData/Local/nvim/init.lua:42   → the file, found despite the truncation
```

Everything above under *What it previews* applies unchanged: detection is
the only thing that is new, so a bare `.png` gets the same picture float a
linked one gets, and a bare `.md` the same section preview.

Two rules keep this from firing constantly:

- **The path must exist.** A broken *link* is worth reporting — someone
  wrote it meaning to point somewhere. Plain prose is not, or every word
  under the cursor would open a "target does not exist" float.
- **It must look like a path** — a separator, an extension, or a `...`
  truncation. `helper` is a word; `helper.lua` is a path.

Truncated paths (`...nvim/init.lua`, `…/lua/config/init.lua`) and `:line:col`
suffixes are resolved by [gopath.nvim](https://github.com/StefanBartl/gopath.nvim),
a soft dependency — that is exactly its subject matter, so this plugin asks
it rather than reimplementing the search. Without gopath.nvim installed,
ordinary relative and absolute paths still hover; only the truncated forms
stop resolving.

Because a path is not a markdown phenomenon, the hover attaches in **every
filetype** by default (`hover.filetypes = "*"`). Non-file buffers — pickers,
file trees, terminals, dashboards — are always skipped. Narrow the scope
with a filetype list, or turn bare paths off entirely:

```lua
hover = {
  bare_paths = false,               -- links only, the pre-0.x behaviour
  filetypes = { "markdown", "text" }, -- or: only hover in these buffers
}
```

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
    -- How long an async preview (image, rasterized PDF page) may take before
    -- it is allowed to interrupt you with a "rendering…" placeholder. Below
    -- this, waiting quietly reads as instant; above it, silence reads as
    -- breakage. "Instant" is a property of the machine, hence the knob.
    placeholder_grace_ms = 250,
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

An image hover has two shapes, depending on whether the picture can
actually be drawn.

**Drawable** — the float is blank and sized to the image's aspect ratio,
and holds nothing but the picture: no filename in the border, no
`1810 × 1426 px` or `JPG · 612 KB` line. You are looking at the image; a
caption for it is noise. The sizing is not cosmetic either. The drawing box
handed to the terminal *is* the float's geometry, so a float measured
against two lines of text would squeeze the image into a box two cells
tall. `hover.max_width` and `hover.max_lines` bound that box; the ratio
within it comes from the file.

**Not drawable** — the metadata lines, which are then the only thing the
hover can say at all. Dimensions are parsed straight out of the file header
(PNG, GIF, BMP, and JPEG by walking its segment chain), so they need
nothing installed; ImageMagick is consulted only for formats the parser
cannot read, such as WebP.

Drawing the picture needs
[images.nvim](https://github.com/StefanBartl/images.nvim): it is the only
supported provider that can draw into a window it does not own
(`images.anchor.draw`, deferred — an undeferred draw is repainted over by
the float that was just opened). snacks.nvim and image.nvim need a buffer
of their own, which a borrowed hover window is not — with those installed
you get the metadata float instead. Set `inline_images = false` to skip
drawing entirely and always get metadata.

A PDF ends up in the same place — a blank float in the page's aspect ratio
— but has to be rasterized first, which needs pdfport.nvim (using
`pdftoppm`).

That render is asynchronous, so the hover is quiet about it for 250 ms. A
render that finishes inside that window shows the finished page and nothing
before it. One that takes longer gets a `rendering page 1…` float, because
by then the wait is real and silence would read as a broken hover.

Rendered pages are kept for the session, keyed by file *and* mtime, so a
second hover over the same PDF opens instantly and a PDF that changed on
disk is rasterized again. The files are removed at exit. Move the cursor
away mid-render and the page is still kept — it just does not pop up over
the link you already left.

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

## Escalating to the full thing

The hover float is deliberately small and fast. When it is not enough,
`hover_escalate()` opens the *full* preview for the link under the cursor —
in whatever surface already owns that job, not a new one built for this:

| Target | Opens via |
| --- | --- |
| Markdown file / in-page anchor | `:Markdown mdview` ([mdview.nvim](https://github.com/StefanBartl/mdview.nvim)) |
| Image | A full-screen window via [images.nvim](https://github.com/StefanBartl/images.nvim)'s `images.zen.open` |
| PDF | The same system-vs-pdfport prompt the cursor-action handler uses |
| Other file / directory | The system default application |
| URL | The system default browser |
| Missing target | Nothing to open — reports why |

```lua
vim.keymap.set("n", "<CR>", require("markdown").hover_escalate, { buffer = true })
```

No default keymap is bound — `<CR>` above is a suggestion, not something set
for you, since it is a common mapping already spoken for in some setups.
Each destination is reached through its existing opener (`markdown.commands
.mdview`, `markdown.handler.file`, `images.zen`), so a missing optional
dependency warns exactly the way it already does everywhere else in this
plugin, rather than through new logic here.

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
| `markdown.hover` | Trigger, debounce, cache, cancellation, dispatch, escalation |
| `markdown.hover.classify` | Target string → type (the only filesystem touch is one `fs_stat`) |
| `markdown.hover.float` | The window: cursor-relative, unfocused, single-instance |
| `markdown.hover.preview.text` | Files, sections, anchors, directories, missing targets |
| `markdown.hover.preview.media` | Images and PDFs |
| `markdown.hover.preview.url` | URL parsing, optional metadata fetch |

Asynchronous previews (PDF rasterization, URL fetch) are guarded by a
generation counter: if the cursor moves on before the result lands, the
result is dropped instead of opening a float for a link you have already
left.
