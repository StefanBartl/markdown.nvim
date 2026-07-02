# Implementation plan — markdown.nvim

Derived from reviewing [`docs/ROADMAP.md`](../ROADMAP.md) together with the
checklist findings in this folder (`Arch&Coding.md`, `Zentral-Prinzipien.md`,
`Checklist.md`). Ordered by value/effort; not binding.

## Phase 0 — hygiene / foundation (from the checklists)

Small, low-risk, unblock the rest. IDs match the checklist docs.

1. **A1 — notify hygiene.** Replace raw `vim.notify` in `commands/init.lua`
   (2×) and `commands/markdown_links.lua` (1×) and the bare `print(result)`
   with `util/notify`. *~20 min.*
2. **A4 — cross-platform opener.** Extract `util/platform.lua` with a single
   `open(target)` and replace the duplicated `os_uname → xdg-open/open/start`
   branches in `handler/{file,image,url}.lua`, `tableview/live.lua`,
   `tableview/views/browser_{basic,niceified}.lua`. Prefer `vim.ui.open`,
   fall back to the platform branch in one place. *~1 h.* Also the natural home
   for the pdfport opener when that lands in filetree.nvim.
3. **A3 — `@types/` folder.** Create `lua/markdown_nvim/@types/` (files
   `return {}`) and move shared `@class`/`@alias` (config, `Mkdn.Link`, table
   types) out of source. *~1 h.*
4. **A7 — tooling.** Add `stylua.toml` + `.luacheckrc`; a minimal CI job that
   runs stylua --check, luacheck, and `docs/TESTS/run.lua`. *~1 h.*
5. **A2 — deferred handle re-validation.** Audit `tableview/renderer.lua`
   callbacks; re-check win/buf validity inside `vim.defer_fn`/schedule. *~30 min.*

## Phase 1 — high-value features (ROADMAP.md)

6. **Telescope / fzf-lua picker backends.** `util/picker.lua` already abstracts
   the backend (`hover_select`/`select`); add `"telescope"` and `"fzf"` branches
   behind `links.picker`. Guarded soft deps. *First step: a `backends/` table
   keyed by picker name.*
7. **Configurable TOC header/markers.** The TOC header (`## Table of content`)
   and bullet style are hard-coded in `core/toc.lua` + the `<Plug>(markdown-toc)`
   closure. Expose `toc = { header, marker, max_level }` in config. *Touches
   `config/DEFAULTS.lua`, `core/toc.lua`, `bindings/plugs.lua`.*
8. **Table format options.** Surface `table_fmt`'s alignment/padding
   (`header_align`, `entry_align`, `col_overrides`) as config defaults, not just
   `:Markdown table format` args.

## Phase 2 — nice-to-have

9. **Link diagnostics** — flag dead relative-file links / duplicate anchors
   (reuse `core/link_scan` + the anchor slug logic). Optionally a `vim.diagnostic`
   source.
10. **Anchor style options** — opt-in slug variants (keep-case, custom separators)
    for non-GFM renderers.
11. **Theme-derived blockquote/fenced colors** — derive `blockquote_hl` defaults
    from the active colorscheme (explicit config still overrides).
12. **Per-key override table** — on top of the `<Plug>` surface, an optional
    `keys = { … }` config to remap/disable individual defaults declaratively.
13. **HTML→GFM table import** (round-trip with the existing HTML export).

## Phase 3 — testing

14. **Grow `docs/TESTS/`** toward handler/anchor logic (currently: config,
    table_fmt, link_scan, headings). Pairs with A7's CI.

## Notes
- The four filetree-related gaps found during the Neo-tree audit
  (markdown-link bridge, pdfport, buffers-source, neotest) belong to
  **filetree.nvim**, not here — tracked in `filetree.nvim/docs/ROADMAP/NEOTREE_FEATURES.md`.
- markdown.nvim keeps `lib.nvim` as an *optional* dependency and its README in
  English (both intentional deviations from the config-module rules).
