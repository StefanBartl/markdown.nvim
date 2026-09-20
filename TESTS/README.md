# Tests

Headless spec suite for markdown.nvim. Covers the pure / buffer-level logic
that is trivially testable without a UI.

## Run

From the repo root:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile TESTS/run.lua" -c "qa!"
```

The runner prints one line per spec and exits non-zero on the first failure
(`MARKDOWN_TESTS_OK` on success). `run.lua` requires `lib.nvim` and
`hover.nvim` as sibling checkouts (`../lib.nvim`, `../hover.nvim`, or
`$LIB_NVIM_PATH`/`$HOVER_NVIM_PATH`) — both are hard runtime dependencies.
`color_my_ascii.nvim` (`../color_my_ascii.nvim` or
`$COLOR_MY_ASCII_NVIM_PATH`) is a soft, optional sibling: when present,
`scope_spec.lua` additionally exercises the real `color_my_ascii` fence API
backend; when absent, that one block is skipped with a `skip` line and
everything else still runs.

## Layout

| File                 | Covers                                                          |
| -------------------- | --------------------------------------------------------------- |
| `harness.lua`        | Shared `eq`/`ok` assertions and a `scratch(ft)` buffer helper.  |
| `config_spec.lua`    | Config defaults + deep-merge of user options.                   |
| `table_fmt_spec.lua` | GFM formatter: `parse_args`, `complete`, buffer formatting.     |
| `link_scan_spec.lua` | `from_line` / `from_lines` link extraction (+ fenced skip).     |
| `headings_spec.lua`  | Heading level shift + nav (up/down, H6 clamp, H1 reach, column preservation, non-markdown no-op). |
| `handler_spec.lua`   | Cursor-action handler: silent mode suppresses the "no target" notification for mouse invocation. |
| `handler_url_spec.lua` | `handler.url`: markdown-link / bare-URL / HTML-href / near-cursor-buffer-scan extraction, trailing-punctuation stripping, and `M.open`'s `platform.open` wiring (success and failure). |
| `anchor_jump_spec.lua` | Anchor jump: successful jump notifies nothing, "no anchor under cursor" vs. "anchor resolves to no heading" are distinct info notifications (regression for the pcall-ok-flag-vs-result mixup), duplicate-slug disambiguation (`#note`/`#note-1`/`#note-2`), and the TOC-list-entry double-click end-to-end via the handler. |
| `tableview_spec.lua` | Floating TableView preview closes via `q`/`<Esc>`.              |
| `tableview_alignment_spec.lua` | TableView column alignment with multi-byte UTF-8 content (umlauts, em dashes, curly quotes, arrows, ellipses) — regression coverage for the byte-length-vs-display-width padding bug, using the new `renderer.validate_alignment(lines)` de-facto check (also verifies the validator itself catches a genuinely drifted table, not just rubber-stamps everything). |
| `tableview_group_spec.lua` | Opening the TableView popup leaves the FileType autocmd that installs TableView maps/commands intact. Regression: the popup's `BufWriteCmd` used to be created via `autocmd.group("MarkdownNvimTableView", true)` — the group `setup()` puts that autocmd in — and `clear = true` emptied it, so buffers opened after the first popup got no TableView maps or commands. The popup now has its own group, `MarkdownNvimTableViewPopup`. |
| `browser_session_spec.lua` | TableView browser export (`browser`/`browsernice`) reuses one tab across calls: opens the system browser once per style, later calls overwrite the same fixed file instead of opening a new tab, a different style opens independently, and `force_new` ('reopen') opens a fresh tab on demand. |
| `fenced_scope_spec.lua` | Fenced-block scope: detection + TOC/nav/jump/shift/fold wiring, via the built-in fallback scanner (`provider="builtin"`, self-contained). |
| `scope_spec.lua` | `markdown.scope`'s own backend resolution (`get_backend`), separate from the ops `fenced_scope_spec.lua` drives: **(1)** regression for the fold-cache-invalidation augroup, which used to double up its `BufDelete`/`BufWipeout` handlers on every module reload instead of being idempotent; **(2)** `provider='color_my_ascii'` requested-but-unavailable still falls back to the built-in scanner at the `get_backend()` level (not just health.lua's separate warning); **(3)** when a real `color_my_ascii.nvim` sibling is on the runtimepath, `scope.detect` against its actual fence API (`cma.fences.block_at`/`list_blocks`) — markdown.nvim's own side of that integration contract, previously exercised nowhere in this suite. |
| `session_features_spec.lua` | De-facto coverage for refs sync, actions/keymaps, feature gating, the menu integration, double-click fold (ATX + Setext), the link-underline fix, the fold H2+ outline toggle, the fold-from-menu-context bug fix, TableView box style + configurable default, table mode/tableize/cell motions, and the Windows `platform.open` fix. Drives the real `:Markdown` commands and public `actions` API, not private internals. |
| `health_spec.lua` | `:checkhealth markdown` (`markdown.health`), via a `vim.health` recorder: a healthy report, `links.picker` sanity (bad value warns, valid value informs), `fenced_scope` enabled/disabled reporting, an explicitly-requested-but-unavailable `color_my_ascii` provider warning, a broken `markdown.config` reported rather than raised, and the crash regression below. |
| `underline_headings_spec.lua` | `core.underline_headings`: insertion, idempotent no-op on an already-correct underline, correcting a wrongly-sized one in place, multi-heading offset tracking, fenced-block skip, the configurable underline char, and the multi-byte display-width regression below. |
| `heading_gaps_spec.lua` | `core.heading_gaps`: no-gap cases (nested outline, first heading never a gap), single/multiple gaps (later gaps computed as if earlier ones were already fixed), fenced-block skip, `fix_gaps` rewriting level while preserving indent/title, and `M.check`'s `silent_ok` + `vim.fn.confirm` Yes/No branches. |
| `wrap_link_spec.lua` | `core.wrap_link`: the URL/path-vs-plain-text heuristic in both normal mode (word-under-cursor) and visual mode (live selection) — empty selection, plain word, URL, `mailto:`, path-with-separator, bare `name.ext`, and whitespace-only selection. |
| `clipboard_spec.lua` | `util.clipboard`: `M.copy()`'s return value in both the lib.nvim-present and no-lib.nvim (direct `setreg`+round-trip-verified-via-`getreg`) paths, the always-set `*` register, and the recently-fixed regression below. |
| `fold_prev_spec.lua` | `core.fold_prev` (`zi`): non-markdown no-op, no-heading-above view-restore, ATX heading above, repeated single-hop walking, and the Setext-heading bug regressions below. |
| `fenced_fix_spec.lua` | `fenced_fix`: the legacy + treesitter highlight-group cascade (`enable_legacy`/`enable_ts` gating, the base-highlight-plus-style override vs. plain-link branch, custom `delimiter_hl`), and `M.setup()`'s opts-merge + auto-apply. |
| `run.lua`            | Runner: loads every spec, reports results, sets the exit code.  |

### Bugs found and fixed this round

All four were found by code reading + empirical reproduction (a throwaway
repro script run against the pre-fix code), fixed directly (each is a small,
well-understood, low-risk change), and pinned with a real regression
assertion in the specs above:

1. **`health.lua` crash on a missing `lib.nvim`.** `M.check()` reported
   "lib.nvim not found" via `error_(...)` and then, unconditionally a few
   lines later, re-required the exact same module to hand the report off to
   it — raising and aborting the report right after the warning that was
   supposed to explain why. The same defect this campaign has now found in
   17+ other repos (and already fixed in `color_my_ascii.nvim`, whose fix
   this one mirrors). Fixed by reusing the `composer_ok`/`composer` already
   captured by the earlier `pcall`. See `health_spec.lua`.
2. **`scope/init.lua`'s fold-cache-invalidation augroup was not idempotent.**
   It registered its `BufDelete`/`BufWipeout` handler via
   `lib.nvim.bindings.autocmd.create` with `group` passed as a bare *string*
   ("MarkdownNvimScopeFoldCache") — which resolves an existing group by name
   **without** `clear = true`. A second load of the module (a hot-reload via
   `package.loaded` reset, or a plugin manager's `:Lazy reload`) therefore
   registered a second handler in the same group instead of replacing the
   first; confirmed before the fix, three reloads left six live autocmds
   where one was intended. Every other augroup in this codebase already uses
   the safe `vim.api.nvim_create_augroup(name, { clear = true })` form
   (several with an explicit comment explaining why) — this was the one spot
   that missed it. Fixed to match. See `scope_spec.lua`.
3. **`underline_headings.lua` used byte length instead of display width.**
   The Setext-style decoration's underline was built as
   `char:rep(#text)` — `#text` is a *byte* count, so a heading containing
   multi-byte UTF-8 (e.g. `"Über uns"`: 8 display columns, 9 bytes) got an
   underline one character too long. Fixed to
   `char:rep(vim.fn.strdisplaywidth(text))`. See `underline_headings_spec.lua`.
4. **`fold_prev.lua`'s manual Setext-heading search had two defects**, found
   incidentally while writing its (previously nonexistent) coverage:
   - it only ever matched a `-`-underline (`"^%s*%-%-+%s*$"`), never `=`,
     despite its own doc comment claiming to cover
     `"Setext-style ===/--- headings"` — `core/fold.lua`'s own
     `is_underline()` already uses `"^%s*[-=]+%s*$"` for the identical
     check, so this now matches that established convention;
   - the search loop's lower bound stopped at line 2
     (`for lnum = cur - 1, 2, -1`), so a Setext heading occupying the
     buffer's very first two lines was never reachable regardless of
     underline character — line 1 was never evaluated as a title candidate.

   Both fixed (pattern widened to `[%-=]+`, loop bound to `1`). See
   `fold_prev_spec.lua`.

### What's covered vs. what's still open

The four recurring bug patterns this campaign checks for on every repo were
looked for specifically:

- **(a) health.lua crashing on a missing dependency** — found and fixed (#1
  above); no other `M.check`/health-style function in this repo has the same
  shape.
- **(b) non-idempotent augroup via a name-cached wrapper** — found and fixed
  (#2 above); every other augroup registration in `lua/**` was audited by
  grep (`group = "..."` and `nvim_create_augroup`) and all others already use
  the safe `clear = true` form.
- **(c) byte-offset vs. display-column confusion** — found and fixed (#3
  above); `core/table_fmt.lua`/`core/table_wrap.lua`/`tableview/renderer.lua`
  already use `display_width`/`strdisplaywidth` throughout and have their
  own multi-byte regression coverage (`tableview_alignment_spec.lua`);
  `core/wrap.lua`/`core/wrap_link.lua` operate on Neovim API byte-columns
  consistently end-to-end, which is correct (not a mismatch) since
  `nvim_win_get_cursor`/`nvim_buf_get_text`/`nvim_buf_set_text` are all
  byte-indexed.
- **(d) Windows path/separator bugs** — `util/path.lua` was read closely
  (this repo's one path-resolution module, used by the link/file/image
  handlers and `core.file_refs`'s rename/retarget flow) and is already
  well-hardened: drive-letter detection uses `^%a:[/\\]`, not a naive
  `:find(":", ...)`; `path_spec.lua` already covers backslash-authored
  links, mixed separators, drive prefixes, and cwd-vs-buffer-dir fallback.
  No instance of this pattern was found.

Real, previously-zero-coverage modules with genuine branching logic closed
this round: `health.lua`, `core/underline_headings.lua`,
`core/heading_gaps.lua`, `core/wrap_link.lua`, `core/fold_prev.lua`,
`util/clipboard.lua` (including the just-landed `M.copy()` return-value fix
from commit `0d8f0ad`, which had no regression coverage), `handler/url.lua`,
`fenced_fix/init.lua`, and `scope/init.lua`'s backend resolution + the real
`color_my_ascii` integration branch.

**Not closed this round** (real gaps, left open rather than padded with
shallow tests to claim a number): `commands/create.lua`,
`commands/export.lua`, `commands/headings.lua` (its own argument-parsing
vocabulary), `commands/image.lua`, `commands/render.lua`,
`commands/scope.lua`, `commands/markdown_links.lua`'s link-generation logic
(`ignore`-filtered, sorted `:Markdown links create`), `tableview/views/*.lua`,
`util/md_files.lua`, `util/progress.lua`, and the `anchor/is_*_line.lua`
predicates. None of these hit any of the four bug patterns on inspection,
and `commands.table`/`commands.refs` (the two subcommands most exercised
elsewhere) showed no equivalent defect, but they have real logic and no
direct spec — a genuine remainder for a future pass, not a "this repo is
now 100% covered" claim.

### What can't be tested headless

A few things need a real UI and are out of scope for this suite — verify
them manually:

- **In-terminal image rendering** (snacks.image / kitty graphics) needs a
  real graphics-capable terminal (WezTerm). Open an image file or a markdown
  doc with an image link and check `:checkhealth snacks`.
- **The nvzone/menu popup actually appearing on RightMouse** is UI-only;
  `session_features_spec.lua` verifies the *entries* menu.items() builds
  (context-aware, opt-out), but not the popup rendering itself. Right-click a
  heading in a real Neovim session and try each entry.

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch`) and add its filename to the `specs` list in `run.lua`.
