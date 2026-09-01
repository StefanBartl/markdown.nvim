# Link hover preview

Rest the cursor on a markdown link — or on a path written as plain text —
and a small float shows what it points at, whatever that is.

> **Where this lives.** The framework itself is
> [`hover.nvim`](https://github.com/StefanBartl/hover.nvim/blob/main/README.md),
> not this plugin: classification, the float, file/directory/URL previews,
> the debounce and bare-path detection are "a path is a path" and were never
> markdown. markdown.nvim contributes the two parts that genuinely are —
> finding a link or `<figure>` in a line, and resolving `#heading` sections —
> through that module's registry, alongside images.nvim (draws pictures),
> pdfport.nvim (rasterizes PDF pages) and gopath.nvim (truncated paths).
> Everything below still applies; `hover = { … }` in markdown.nvim's spec is
> handed to the framework unchanged.

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
| **Missing target** | A red ✗ saying it is missing, and the path that was tried |

That last row matters more than it looks. A hover that immediately says
"this file isn't there" catches broken links while you write them, long
before `:Markdown links check` runs.

## Paths without link syntax

A target does not have to be a link, and does not have to sit in a markdown
file. A path written as ordinary text hovers too — in prose, in a code
comment, in output pasted from a log:

```
./assets/diagram.png          → the picture
../docs/BINDINGS.md           → its first lines, markdown-highlighted
...AppData/Local/nvim/init.lua:42   → the file, found despite the truncation
```

Everything above under *What it previews* applies unchanged: detection is
the only thing that is new, so a bare `.png` gets the same picture float a
linked one gets, and a bare `.md` the same section preview.

Two rules keep this from firing constantly:

- **It must look like a path** — a separator, an extension, or a `...`
  truncation. `helper` is a word; `helper.lua` is a path.
- **A path that does not exist is reported only when it cannot have been
  anything else** — that is, when it carries a separator (`docs/gone.md`) or
  a `...` truncation. Those get the same red ✗ a broken link gets. A bare
  `name.ext` that resolves to nothing stays silent, because that is exactly
  how `vim.api`, `string.format` and every other identifier is spelled — and
  a ✗ on half the tokens in a Lua file is noise, not information.

```
┌ broken link ──────────────────────┐
│ ✗ no such file                    │
│ /home/you/docs/gone.md            │
└───────────────────────────────────┘
```

The ✗ uses the `HoverMissing` highlight group, linked to
`DiagnosticError` by default so it follows your colorscheme. Override it
before or after setup:

```lua
vim.api.nvim_set_hl(0, "HoverMissing", { fg = "#ff5555", bold = true })
```

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
      hover = false,       -- whether a link hovers at all — see "URL previews" below
      fetch = false,       -- and whether the page behind it is fetched
      timeout_ms = 2000,
    },
    office = {
      convert = false,     -- .docx/.xlsx/.pptx → PDF → page, see "Office documents"
      timeout_ms = 60000,
    },
  },
})
```

Turn it off entirely with `hover = { enabled = false }`, or via the feature
gate: `features = { disable = { "hover" } }`.

Both of those are read at startup. For the rest of a session there is
`:Hover toggle` (also `mode auto` / `mode off`), which comes from hover.nvim and works
whether or not markdown.nvim is loaded — the framework is hover.nvim's, and
so is the switch. It is announced when you throw it, because an off hover is
otherwise indistinguishable from a line that simply has no link on it.

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

Two switches, both **off by default**, and for two different reasons.

`url.hover` decides whether a link hovers at all. Off, because a markdown
document is largely made of links: with it on, resting the cursor almost
anywhere in a paragraph opens a float, and the float lands over the sentence
you were reading. On, the URL is parsed and shown broken into host, path and
decoded query — entirely locally, nothing leaves the machine.

`url.fetch` decides whether the page behind the link is fetched, for its
**status code** (`HTTP 404 Not Found`, `HTTP 500 Internal Server Error` — the
answer a link hover is really being asked for), its `<title>` and its
`<meta description>`. Off on top of that, because fetching would disclose
every link you brush past to its host and turn a link-heavy document into a
request storm while scrolling. Switching it on implies `url.hover`.

For a session, without touching the config:

```vim
:Hover links web on          " links hover, offline
:Hover links web fetch on    " …and are fetched for status/title
:Hover links web off         " back to silence on links
```

Both come from hover.nvim, like the rest of the framework, and they apply in
every filetype — a URL in a Lua comment or a `.txt` hovers the same way, from
hover.nvim's own bare-URL source. markdown.nvim contributes only the *finding*
of links inside markdown (inline links, autolinks, reference links).

Fetched results are cached per target for the session, so a server that has
since recovered keeps showing its old status until the cache is dropped —
which any of those three commands does.

### Office documents

`.docx`, `.xlsx`, `.pptx`, `.odt` and their legacy siblings cannot be read as
text: they are containers, and previewing their first lines produces mojibake.
By default they hover as a badge — `◆ Word document · DOCX · 24 KB` — and so
does any other file whose bytes are not text (archives, executables, media),
decided by looking at the bytes rather than at a list of extensions.

`office.convert = true` (or `:Hover office on`) turns that into a real
preview: [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) converts
the document to a PDF through LibreOffice, and the first page is drawn like
any other picture — with the same paging keys, because by then it *is* a PDF.
Opt-in because the first conversion of each document starts LibreOffice, which
is seconds; the result is cached per file and mtime, so only the first hover
pays.

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
  insert-mode entry, window scroll or buffer switch — or on `q` / `<Esc>`,
  which additionally keeps it closed while the cursor stays on that same
  target. Closing alone would not have been enough: `CursorHold` fires again
  after any keystroke plus `'updatetime'` of quiet, cursor movement or not,
  so a plain close would pop straight back while you are still standing on
  the link you wanted out of the way. The dismissal ends by itself at the
  next target, so there is nothing to remember and undo. The keys are
  hover.nvim's (`hover.dismiss_keys`), borrowed only while a float is on screen
  and *restored* — not deleted — when it closes, since the float is
  unfocusable and can hold no mapping of its own.
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

**The framework moved to hover.nvim; the markdown half stayed here.** It began
in this plugin, but almost none of it turned out to be *about* markdown —
classification, the float, the file/directory/URL previews, the debounce, the
cache and bare-path detection are all just "a path is a path". What genuinely
needs a markdown parser is roughly a tenth of the code, and that tenth is
what the `markdown.*` rows below still are. markdown.nvim hands it over through
`hover.registry` and is never named inside hover.nvim.

| Module | Responsibility |
| --- | --- |
| `markdown.hover` | The façade: registers this plugin's contributions, then delegates. Plus `escalate`, which is ours |
| `markdown.hover.section` | `#heading` and `file.md#heading` previews — the part that needs GFM slugging and heading parsing |
| `markdown.core.link_scan` / `markdown.core.html_links` | Registered as *sources*: the link, or the enclosing `<figure>`, under the cursor |
| `hover` | Trigger, debounce, cache, cancellation, dispatch — and the dismissal (`q`/`<Esc>`) and session switch |
| `hover.classify` | Target string → type (the only filesystem touch is one `fs_stat`) |
| `hover.float` | The window: cursor-relative, unfocused, single-instance |
| `hover.preview.text` · `.media` · `.url` | Files, directories, missing targets · images and PDFs · URL parsing and the optional fetch |
| `hover.preview.binary` · `.office` | "these bytes are not text" and what to call them · office documents, badge or converted page |
| `hover.bare_path` · `.bare_url` | A path, and a URL, carrying no link syntax at all, in any filetype |

Older notes name `markdown.hover.classify`, `markdown.hover.float` and
`markdown.hover.preview.*`, and notes written between the two moves name them
`lib.nvim.hover.*`. Both are pre-move spellings of the `hover.*` rows above.

Asynchronous previews (PDF rasterization, URL fetch) are guarded by a
generation counter in hover.nvim: if the cursor moves on before the result
lands, the result is dropped instead of opening a float for a link you have
already left.
