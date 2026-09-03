# Workflow — getting real use out of markdown.nvim day to day

Every feature here is documented on its own elsewhere ([Features](FEATURES/README.md),
[Commands](commands.md), [Keymaps](keymaps.md)). This is the different
question: once several features exist, *how do they actually combine* while
writing and reorganizing a real document, rather than used once and
forgotten.

## Writing a new doc: TOC first, then let it ride

`{count}<leader>toc` (or `:Markdown toc`) does two things on every run, not
one: it inserts/refreshes the Table of Contents *and* enforces the
`[blank]---[blank]` separator between H2+ sections (`ensure_headline_spacing`,
default on) — only where a section actually has content; an empty section
(nothing but the next heading) gets a single blank line instead, no `---`.
That combination is the reason to reach for it constantly
instead of only at the end — running it after adding a section both updates
the TOC and fixes the spacing in one keystroke, so there is no separate
"now go clean up the separators" pass. Override per-call with `--sep`/
`--no-sep` if a particular run shouldn't touch spacing (e.g. inside a
fenced-scope block where you don't want the outer separator convention).

`count` sets the max heading level shown (`3<leader>toc` = H1–H3). Rerunning
with a different count re-derives the TOC from scratch — it doesn't merge
with whatever was there.

**It also checks for skipped heading levels on every refresh** (an H1 followed
directly by an H3), reports them and offers to renumber the offending headings
on the spot. That is a sub-behaviour of TOC generation rather than a feature of
its own, which is why it is on by default (`check_heading_gaps`) and overridable
per call with `--check-gaps`/`--no-check-gaps`. `:Markdown gaps` runs the check
alone — reach for that on somebody else's document, where you want to see the
structure problem before touching the file.

## Renaming headings: pick `refs.mode` for how you actually write

`core/refs.lua` keeps `[text](#anchor)` links and the TOC in sync when a
heading is renamed, but the three modes trade responsiveness for cost
differently — picking the wrong one for your editing style is the trap:

| Mode | When it reconciles | Fits |
|---|---|---|
| `"off"` | Never automatically | You run `:Markdown refs sync`/`check` by hand, deliberately |
| `"save"` (default) | `BufWritePre` | Normal editing — renames get fixed right before the file hits disk, no mid-edit overhead |
| `"live"` | Debounced `TextChanged`/`TextChangedI` (`refs.debounce_ms`, default 2000ms) | Long editing sessions where you want links correct *while* you work, not just at save — e.g. jumping between sections via stale-looking links mid-edit |

`:Markdown refs check` is the dry run regardless of mode — run it before a
big rename pass to see the current orphan/broken-link state in the quickfix
list, then `:Markdown refs sync` to actually reconcile. `:Markdown refs
baseline` resets the extmark-tracked heading identities; reach for it if a
merge/rebase left the tracking looking wrong rather than debugging why a
rename wasn't detected.

## The four table layers — use the cheapest one that answers the question

`table_fmt`, `table_mode`, `tableview`, and `table_wrap` are independent and
stack, but reaching for the heaviest one out of habit wastes a step:

| Layer | Command/key | Use it for |
|---|---|---|
| `table_fmt` | `:Markdown table format` | A one-off cleanup — align columns, normalize separators, right now |
| `table_mode` | `<leader>tvm` / `:Markdown table mode` | Building a table interactively — realigns after every edit, no manual format step |
| `tableview` | `<leader>tvt`/`tvx` | Reading a table you're not editing — a wide table off-screen, or checking alignment without touching the buffer |
| `table_wrap` | `:MDTable*` (opt-in) | A table whose natural width already blows past your line-length convention — caps column width with continuation rows |

A concrete combination: **`table mode` on while drafting → `:MDTableWrap`
once the content is real** — table mode's live realign uses natural
(unbounded) widths, so switching a wide table to width-limited wrapping is a
deliberate one-time step at the end, not something table mode does for you
automatically (`table.wrap.enabled = true` would make *every* format/mode
pass wrap, which is the "always capped" choice instead — pick one).

`:MDTableProfile {compact|docs|wide}` is the fast way to try a width
convention without hand-writing `min`/`max`/`pad` — `docs` is a reasonable
default to reach for first on prose-heavy tables.

**Trap:** `:MDTableUnwrap`'s continuation-row detection is structural, not
marked — a genuine one-cell data row directly after another row of the same
table is indistinguishable from a wrapped continuation and gets merged into
it. If a table has real single-cell rows by design, expect to fix that row
by hand after an unwrap rather than trusting it blindly.

## Fenced-block scope: writing docs *about* Markdown

If you're editing this repo's own kind of file — a README with a
` ```markdown ` example embedded in it — `fenced_scope` (on by default)
means `<leader>toc`, heading nav, `mj`, and `<S-Right>`/`<S-Left>` all
switch behavior depending on which side of the fence the cursor is on: run
`<leader>toc` with the cursor inside the example and you get a TOC of the
*example's* headings inserted into the example, not the outer document's.
The trap this prevents: without scope-awareness, generating a TOC anywhere
in a doc with a nested Markdown example would either pick up the example's
headings in the outer TOC (wrong) or need you to manually exclude the fence
every time.

`:Markdown scope status` is worth running once when a heading operation
does something unexpected inside a fence — it reports whether scope is on,
and which provider (color_my_ascii vs. the built-in scanner) is resolving
fence boundaries; a mismatch between the two is the usual cause of a nested
block not scoping the way you expected.

## Opening what's under the cursor: the "ask" trap

`ma` / double-click / `mi` all funnel through the same cursor-action
dispatcher, but three different targets — images, PDFs, and everything
else — resolve differently, and the default is easy to misread as
inconsistent if you don't know the rule:

- **Images** (`mi` or generic): `image.preview` (default `"ask"`) prompts
  System app vs. Preview in Neovim, *if* a provider (images.nvim, then
  snacks.nvim, then image.nvim) is installed. With none installed, every
  mode behaves like `"system"` — there's nothing to choose between.
- **PDFs**: no config knob at all — the prompt (System app vs. pdfport's
  own buffer render) appears automatically whenever pdfport.nvim is
  installed, and never otherwise. There is no `pdf.preview` setting to set
  to `"preview"` the way there is for images.
- **Everything else** (media/binary via `open.external_extensions`, or
  text-like): no prompt, ever — straight to the system app or `:edit`.

So "why did opening this image ask me something but this other file didn't"
is almost always "the other file isn't an image or a PDF", not a config
inconsistency. Set `image.preview = "preview"` once you know you always
want the in-buffer route and are tired of the prompt; there's no equivalent
override for PDFs — install or don't install pdfport.nvim instead.

**Provider trap on Windows Neovim in WezTerm specifically**: snacks.nvim and
image.nvim only speak the Kitty graphics protocol, which that combination
never draws — install images.nvim (OSC 1337) if that's your setup, or `mi`
will silently fall through to the system viewer every time despite a
provider being "installed". `:checkhealth markdown` doesn't check for any
of the three providers, so a silent no-op there isn't a bug report waiting
to happen — check `require("markdown.util.image_preview").detect()`
directly if `mi` isn't previewing and you expect it to.

## Two link-hygiene passes, and they answer different questions

`:Markdown links check` answers *does this target exist* — it publishes
diagnostics and mirrors the findings into the **quickfix** list, so the loop is
`:copen` and work the list. Quickfix rather than the location list on purpose:
`refs check` in this same plugin already set that precedent, and two sibling
`check` subcommands landing in different lists is the odder outcome.

`:Markdown links sanitize` answers the other one — *is this target written the
way this project writes targets*. It normalizes inline-link spelling only:
backslashes become forward slashes, and a bare relative path gains its `./`
(`[t](doc.md)` → `[t](./doc.md)`). URLs, scheme targets, anchors, absolute
paths and `~`-relative paths are left alone, so it is safe to run over a
document you did not write.

It also runs on `BufWritePre` unless `links.sanitize_on_save = false` — the
same shape as `refs.mode = "save"`. Which means in normal use you never type
it: the one time to reach for `:Markdown links sanitize cwd` by hand is right
after importing a tree of documents written on Windows, where every link is
backslashed at once.

## `:Markdown list headings` when you know the heading, the TOC when you are structuring

The TOC is a *document artifact* — it belongs in the file and it is regenerated.
`:Markdown list headings` is navigation and writes nothing: it collects ATX
headings for a scope and jumps to the chosen one, opening the file first if the
heading is in another one.

The scope vocabulary is the same as `:Markdown links show`: `%` for this
buffer, `cwd` for every `*.md` beneath the working directory, or a named file.
`cwd` is the one worth the habit — "which document was that section in" is a
question no single-file TOC can answer.

It skips frontmatter and fenced code blocks, so its results match what
`:Markdown toc` would generate rather than being a superset that includes
`# comments` inside a shell block.

## A captioned image is HTML, and it stays live now

Captioning a picture in Markdown means an HTML `<figure>` block or a pandoc
implicit figure. The block form renders everywhere, and it used to go dark
inside Neovim the moment it appeared: none of the link machinery read HTML, so
adding a caption cost the picture its hover preview, its `mi`, its picker entry
and its dead-link check all at once.

`src`/`href` out of `<img>`, `<a>`, `<source>`, `<video>`, `<audio>`, `<embed>`
and `<iframe>` now resolve in the same shape the Markdown scanner produces, and
a multi-line `<figure>` resolves as one unit. Practical consequence: you no
longer have to choose between a caption and the tooling — and if a link check
suddenly reports targets it never mentioned before, this is why.

## Hover, then escalate — one key deeper instead of a different command

The hover shows what is under the cursor; `hover_escalate()` hands the same
target to whatever already owns the full view — mdview.nvim for Markdown,
`images.zen` for a picture, and the existing PDF/file/URL openers otherwise. No
new opener logic, and **no default keymap**: it is worth binding if you read
more than you write, and worth leaving unbound if the hover is usually enough.

The picture case takes an explicit path rather than going through images.nvim's
own under-cursor resolution, so it escalates the link you are looking at even
where the two would disagree.

## Underline headings: run it once, not as a habit

`:MarkdownNvimUnderlineHeadings` is idempotent (a correctly-sized underline
is left alone), so it's safe to rerun after edits without double-inserting
anything — but it's a purely visual decoration on top of the ATX `#`
markers, not a Setext conversion. Run it after a heading's text changes
(the underline's `=` count no longer matches) rather than binding it to
every save; nothing else in the plugin calls it automatically.

## Remapping: per-binding first, actions API only when you need a key nothing owns

`keymaps = { toc = "<leader>T" }` in `setup()` covers remapping or disabling
any single default binding without touching the rest — reach for this
first. The actions API (`require("markdown").actions.toc()` bound by hand)
is for the other direction: a key combo the default table has no `id` for,
or wiring markdown.nvim's actions into a which-key group you're building
yourself rather than the auto-labelled `<leader>t` one. Don't reach for the
actions API just to change `<leader>toc` to something else — that's a
one-line `keymaps` entry, not a rebind.
