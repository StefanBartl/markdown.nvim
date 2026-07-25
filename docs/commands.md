# Commands

Everything is funnelled through a single `:Markdown` command with subcommands.
The command supports a range, so visual selections are honoured where relevant.
Tab-completion works for every level (`:Markdown <Tab>`, `:Markdown table <Tab>`, …).

## `:Markdown links`

```vim
:Markdown links show [%|cwd|<file>]      " collect links, pick one, open it
:Markdown links create [-r] [--noignore] [--root <path>] <path>
:Markdown links check                    " flag dead links / duplicate anchors
```

- **show** — scan the current buffer (`%`, the default), the cwd, or a given
  file for links, list them in a picker, and open the chosen one (URL → browser,
  `#anchor` → in-buffer jump, file → system app or `:edit`). Picker backend is
  `links.picker`: `hover_select` (default) | `select` | `telescope` | `fzf`
  (the latter two are soft deps; a missing plugin falls back to
  `vim.ui.select` with a warning).
- **create** — generate Markdown links from a directory tree and copy them to
  the clipboard. Options: `-r`/`--recursive`, `--noignore`,
  `--root <path>` (prefix, supports `$ENV_VAR`).
  A bare path without a subcommand is treated as `create <path>`.
- **check** — flag dead relative-file links and duplicate heading titles in
  the current buffer via `vim.diagnostic` (namespace `markdown_links`),
  reusing `core.link_scan` + `core.slug`. Cross-file `path#anchor` links only
  check that the file exists. `links.diagnostics.mode = "save"` reruns this
  automatically on `BufWritePost`; default is manual-only (`"off"`).

## `:Markdown toc`

```vim
:Markdown toc [level] [min=N] [max=N] [marker=X] [--sep | --no-sep]
```

Insert/refresh the TOC, using `config.toc` (header/marker/min_level/max_level/
anchor_style/anchor_separator) for anything not given here. A bare `level` is
shorthand for `max=N` (legacy). By default the headline separators are
applied too (per `ensure_headline_spacing`); override per-call with `--sep` /
`--no-sep`.

## `:Markdown refs`

Keep in-document `[text](#anchor)` links and the TOC consistent when headings
are renamed. Heading identity is tracked with extmarks (plus a positional
fallback), so a rename is detected as `old-anchor → new-anchor` and propagated
to every inline link and the TOC.

```vim
:Markdown refs sync                 " reconcile now: propagate renames + refresh TOC + report orphans
:Markdown refs check                " dry run: list broken #anchor links in the quickfix list
:Markdown refs live [on|off|toggle] " per-buffer debounced live tracking
:Markdown refs baseline             " re-snapshot heading anchors (reset rename tracking)
```

Automatic runs are governed by `refs.mode` (`"save"` — the default — reconciles
on `BufWritePre`; `"live"` reconciles debounced after edits; `"off"` disables
automatic runs). The manual commands work regardless. Live mode is debounced by
`refs.debounce_ms` (default 2000 ms) to keep it off the hot path.

## `:Markdown table`

The single namespace for every table action — preview, format, and a focused,
dependency-free reimplementation of the vim-table-mode essentials.

```vim
:Markdown table view [toggle|markdown|box|select|close|browser|browsernice] [scope|reopen]
:Markdown table format [options]        " align columns / normalize separators
:Markdown table new [cols] [rows]        " insert an empty GFM table template
:Markdown table mode [on|off|toggle]    " auto-format the table you're editing
:Markdown table tableize [format]       " turn delimited text into a GFM table
:Markdown table import [clipboard|PATH] " parse an HTML <table> into a GFM table
```

- **view** renders a table (or every table) in a nicely formatted preview.
  `toggle` uses the configured default style (`tableview.style`, default
  `markdown`); `markdown` / `box` force the aligned-Markdown or Unicode
  box-drawing "spreadsheet" style; `browser` / `browsernice` open it as basic /
  GitHub-styled HTML in the system browser. `select` picks a table from a list;
  `close` closes the float (also `q` / `<Esc>` inside it).

  `toggle` / `markdown` / `box` accept an optional `scope`:
  | scope | Shows |
  |---|---|
  | *(none)* | The table at the cursor; off any table, falls back to every table in the current buffer |
  | `%` | Every table in the current buffer, even with the cursor on one |
  | `cwd` | Every table in every `*.md` file under the working directory (recursive) |
  | `<path>` | Every table in that file, or — if `<path>` is a directory — every table in every `*.md` file under it (recursive) |

  Multiple tables render stacked one after another, separated by a blank line
  and a label (`── Table i/N (line L) ──`, or `── path:line (Table i/N) ──`
  when the table came from a file on disk rather than the current buffer).
  Tab-completion on the scope argument offers `%`, `cwd`, and path completion.
  Same via the buffer-local commands directly: `:TableViewToggle`,
  `:TableViewToggle %`, `:TableViewBox cwd`, `:TableViewToggle ./docs`, …

  `browser` / `browsernice` write to a fixed file per style and open the
  system browser only the **first** call per Neovim session; later calls just
  update that file, and a small script embedded in the page auto-refreshes it
  (scroll position preserved) — so re-checking a table repeatedly reuses the
  same tab instead of piling up a new one each time. Pass `reopen` if you
  closed that tab by hand and want a fresh one: `:Markdown table view browser
  reopen`, `:TableViewOpenBrowserNice reopen`.
- **format** runs the self-contained GFM formatter on the table at the cursor /
  in scope. Defaults come from `config.table` (`header_align`, `entry_align`,
  `col_overrides`) when the command args don't set them.
- **mode** turns on per-buffer *table mode*: after each edit inside a table it is
  re-aligned automatically (debounced, on `InsertLeave` / `TextChanged`), reusing
  the same alignment as `format`.
- **tableize** converts the current line (or a `:'<,'>` visual range) of
  delimited text into a GFM table. The separator is auto-detected (tab, comma,
  or runs of 2+ spaces) or named explicitly:

  | argument | separator |
  |---|---|
  | *(none)* / `auto` | auto-detect: tab, then comma, then runs of 2+ spaces |
  | `csv` / `comma` | a single comma |
  | `tsv` / `tab` | a tab |
  | `psv` / `pipe` | a single `\|` |
  | `scsv` / `semicolon` | a single `;` |
  | `colon` | a single `:` |
  | `space` | a single space |
  | `spaces` / `whitespace` | a run of 2+ whitespace |
  | `";"`, `":"`, `"\|"`, … | any bare or quoted literal delimiter |

  Single-character separators honor **RFC-4180 double quoting**, so a field
  wrapped in `"…"` may contain the delimiter (`"Smith, John",42` → two cells),
  and `""` inside such a field is a literal quote. **Consecutive separators
  produce empty cells**, so leading separators map to leading empty columns.

  A literal space must be quoted — `:Markdown table tableize " "` — because
  Neovim splits the command line on unquoted spaces. Note that with a single
  space `header header2 header 3` becomes **four** columns; quote a value that
  should stay whole: `header header2 "header 3"`.
- **import** parses an HTML `<table>` into a GFM table — round-trips with the
  TableView "open in browser" export. The first row (`<th>` or `<td>`)
  becomes the header; tags inside cells are stripped and entities (`&amp;`,
  `&lt;`, `&gt;`, `&quot;`, `&apos;`/`&#39;`, `&nbsp;`) unescaped. Source:
  `clipboard` (the `+` register), a file `PATH`, or — with no argument — the
  command's range if any (`:'<,'>Markdown table import` replaces the selected
  HTML in place), otherwise the whole buffer (inserted below the cursor).

Cell motions `[|` / `]|` jump to the previous / next cell on the current row.
Everything lives under the `table` feature, and stays available when only the
`tableview` feature is enabled, so the table stack works standalone.

## `:Markdown render` / `:Markdown preview` / `:Markdown mdview`

```vim
:Markdown render  [on|off|toggle]        " render-markdown.nvim (optional host)
:Markdown preview [start|stop|toggle]    " markdown-preview.nvim (optional host)
:Markdown mdview   [path]                " mdview.nvim (optional host)
```

Thin wrappers around the optional host plugins; they warn gracefully if the
plugin is not installed. `preview` also auto-refreshes on buffer switch while
active. `mdview` opens `path` (default: the current buffer's file) directly in
the browser via [mdview.nvim](https://github.com/StefanBartl/mdview.nvim)'s
`:MDViewStart`, which starts a session or — if one is already running — pushes
the file and re-opens the preview surface for it. It only does anything when
mdview.nvim is actually installed and loaded; `:checkhealth markdown`
reports whether it was detected.

## `:Markdown create`

```vim
:Markdown create fs                      " create files/dirs for local link targets
```

Walks the markdown-link targets in the range (visual selection) or the whole
buffer and creates the corresponding files/directories. Trailing `/` ⇒ directory.
URLs, `mailto:` and `#anchors` are skipped; existing paths are left untouched.

## `:Markdown headline_spacing`

```vim
:Markdown headline_spacing               " enforce blank-dash-blank between H2+ sections
```

## `:Markdown scope`

```vim
:Markdown scope toggle                   " toggle fenced-block scope (see fenced-scope.md)
:Markdown scope on                       " force on
:Markdown scope off                      " force off
:Markdown scope status                   " report current state
```

## Buffer-local commands (Markdown buffers only)

```vim
:OpenWithSystemApplication   " same as 'ma' - open target under cursor

:TableViewToggle             " toggle floating table preview at cursor
:TableViewSelect             " pick a table from the buffer
:TableViewClose              " close floating preview
:TableViewOpenBrowser        " export table as basic HTML and open in browser
:TableViewOpenBrowserNice    " export table as styled HTML and open in browser
```
