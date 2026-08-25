# Image captions

Markdown has no caption syntax. There are three ways around that, and they
differ less in what they render than in what your editor can still do with
them afterwards — which is the part that usually decides the question.

markdown.nvim resolves all three, so the choice is about the renderer, not
about losing hover previews.

## The three options

### 1. Implicit figures — recommended

A single image on its own paragraph, nothing else:

```markdown
![Abbildung 1: Start Screen](assets/Device_und_TMA_READY.png)
```

Pandoc's `implicit_figures` extension (on by default for `markdown`) turns
exactly that shape into

```html
<figure>
  <img src="assets/Device_und_TMA_READY.png" alt="Abbildung 1: Start Screen">
  <figcaption>Abbildung 1: Start Screen</figcaption>
</figure>
```

and in LaTeX/PDF into a real floating `figure` with a `\caption`. The alt
text becomes the caption; put an empty alt (`![](x.png)`) to opt out of the
figure for one image.

Why this one first: it is plain markdown. Hover, `mi`, `ml`,
`:Markdown links check`, `:Image zen`, `:Image gallery` and dead-link
diagnostics all see it because there is nothing unusual to see. Nothing in
the toolchain has to be taught anything.

The catch is renderer support. Pandoc does it; GitHub, CommonMark and
markdown-it render the same source as an inline image inside a paragraph —
correct, just uncaptioned. If your target is GitHub, use option 2.

> `:Markdown export pdf` goes through pdfport.nvim → pandoc, so implicit
> figures apply to exports from this plugin.

### 2. An HTML `<figure>` block

```markdown
<figure>
  <img src="assets/Device_und_TMA_READY.png" alt="Start Screen">
  <figcaption>Abbildung 1: Start Screen</figcaption>
</figure>
```

Renders everywhere, because it *is* the output. The cost used to be that
Neovim went blind: none of the link machinery reads HTML, so a picture lost
its hover preview the moment it gained a caption.

That is fixed — see [What Neovim resolves](#what-neovim-resolves) below. The
remaining costs are inherent to the format: no PDF/LaTeX equivalent (pandoc
passes raw HTML through and drops it for non-HTML output), and markdown
inside the block is not processed by default, so a caption cannot contain
`*emphasis*` or a link.

### 3. `@fig:` cross-references

```markdown
![Start Screen](assets/Device_und_TMA_READY.png){#fig:startscreen}

See [@fig:startscreen] for the initial state.
```

This is not a third caption syntax — it is option 1 plus a label. The figure
still comes from `implicit_figures`; `pandoc-crossref` (a filter, installed
separately: `pandoc --filter pandoc-crossref`) numbers it and rewrites
`[@fig:startscreen]` into "Figure 1".

Take this when you need *numbering that stays correct* and references from
the text — a thesis, a manual, anything where figures get reordered. For a
README it is machinery you have to install and remember.

Because the underlying syntax is a normal markdown image, everything in
Neovim keeps working.

## What Neovim resolves

`markdown.core.html_links` reads `src` / `href` out of raw HTML and reports
them in the same shape as markdown links, so every consumer treats them
alike. `<img>`, `<a>`, `<source>`, `<video>`, `<audio>`, `<embed>` and
`<iframe>` are covered, quoted or unquoted.

| Cursor on | Resolves to |
| --- | --- |
| `![alt](x.png)` — including the `!` | `x.png` |
| `<img src="x.png">` anywhere in the tag | `x.png` |
| `<a href="doc.md#intro">text</a>` — tag *or* label | `doc.md#intro` |
| `<figure>` / `</figure>` / a blank line inside the block | the block's `<img>` |
| `<figcaption>Abbildung 1: …</figcaption>` | the block's `<img>` |
| any line inside a `<picture>` block | its `<source>` / `<img>` |
| an `<img>` whose attributes are split across lines, from inside its block | that `<img>` |
| prose *near* a figure, or the gap between two of them | nothing — deliberately |

The block rows are the point of the whole exercise. A `<figure>` is one
logical thing spread over four lines, and the line a reader parks on is the
caption — the one line that, taken alone, contains no target at all.
Resolving the enclosing block from anywhere inside it makes the figure
behave like the single `![alt](src)` it replaced.

The caption text, not `alt`, is used as the label in pickers and hover
titles when both exist: it is what a reader actually sees rendered.

The last table row is load-bearing. Resolution walks out to the block's real
`<figure>`/`</figure>` delimiters, so "inside a figure" and "near a figure"
are different answers — a paragraph a few lines below a picture is a
paragraph, and `ma`/`mi` on it do not open that picture.

This applies to:

- **hover** — the float previews the image from any line of the figure
- **`ma` / `mi`** — the cursor-action dispatcher and the image handler
- **`ml` / `:Markdown links show`** — HTML targets appear in the picker
- **`:Markdown links check`** — a dead `<img src>` is now a diagnostic
- **images.nvim** — `:Image zen`, `:Image gallery`, `:Image orphans` and the
  hover float all route their line scan through this plugin when it is
  installed, so a captioned image is drawable like any other

## Which to pick

| If | Use |
| --- | --- |
| Pandoc is your renderer (incl. `:Markdown export pdf`) | Implicit figures |
| GitHub / a CommonMark viewer must show the caption | `<figure>` |
| Figures need stable numbers and cross-references | `@fig:` + pandoc-crossref |
| You mix targets | Implicit figures, and `<figure>` for the few that must caption on GitHub |

## See also

- [Link hover preview](hover.md)
- [Links and references](FEATURES/links-and-references.md)
- [Editing and handlers](FEATURES/editing-and-handlers.md)
