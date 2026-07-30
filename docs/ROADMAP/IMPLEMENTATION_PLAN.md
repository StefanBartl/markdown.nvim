# Implementation plan — markdown.nvim

Derived from reviewing [`docs/ROADMAP.md`](../ROADMAP.md) together with the
checklist findings in this folder (`Arch&Coding.md`, `Zentral-Prinzipien.md`,
`Checklist.md`). Ordered by value/effort; not binding.

## Phase 0 — hygiene / foundation (from the checklists) — ✅ DONE

IDs match the checklist docs.

1. **A1 — notify hygiene.** ✅ Raw `vim.notify`/`print` in `commands/init.lua`
   and `commands/markdown_links.lua` now route through `util/notify`, which
   bridges to `lib.nvim`'s notifier when present (soft dependency).
2. **A4 — cross-platform opener.** ✅ Single `util/platform.lua` (`os()`,
   `open()`); the six duplicated `xdg-open/open/start` branches
   (`handler/{file,image,url}.lua`, `tableview/live.lua`,
   `tableview/views/browser_{basic,niceified}.lua`) now delegate to it.
3. **A3 — `@types/` folder.** ✅ `lua/markdown/@types/init.lua` holds the
   shared `Mkdn.*` types; source files keep a one-line pointer.
4. **A7 — tooling.** ✅ `stylua.toml`, `.luacheckrc`, `.github/workflows/ci.yml`
   (headless test gate + advisory lint). *Follow-up: one `stylua .` pass, then
   drop the lint job's `continue-on-error`.*
5. **A2 — deferred handle re-validation.** ✅ Verified — **no change needed**.
   `tableview/renderer.lua` is synchronous with thorough `is_valid` guards; the
   only `vim.schedule` (`fenced_fix/init.lua`) emits a captured-string debug
   message and touches no handle.
6. **A6 — debug switch.** ✅ Already present (`vim.g.markdown_debug` gate in
   `util/notify`, used via `notify.debug`).
7. **A5 — handler `ctx` helper.** Deferred (low value): the per-call re-query in
   `handler/*` is cheap; not worth the churn now.

## Phase 1 — high-value features (ROADMAP.md) — ✅ DONE

6. ~~**Telescope / fzf-lua picker backends.**~~ ✅ `util/picker.lua` gained
   `"telescope"` and `"fzf"` branches behind `links.picker` (soft deps,
   fall back to `vim.ui.select` with a warning when the plugin is missing).
7. ~~**Configurable TOC header/markers.**~~ ✅ `config.toc = { header, marker,
   min_level, max_level, anchor_style, anchor_separator }`; `core/toc.lua` and
   `commands/toc.lua` read it, with `min=`/`max=`/`marker=` per-call overrides.
8. ~~**Table format options.**~~ ✅ `config.table = { header_align,
   entry_align, col_overrides }` supplies defaults for `table_fmt` /
   `:Markdown table format`, explicit command args still win per call.

## Phase 2 — nice-to-have

9a. ~~**In-nvim image preview via snacks.nvim (`snacks.image`) or image.nvim**~~
    — ✅ done, built exactly as specified: `markdown/util/image_preview.lua`
    detects either provider via `pcall(require, ...)` and renders into a
    float; `handler/image.lua` mirrors `handler/file.lua`'s PDF prompt. With
    no provider installed the system viewer is used directly, no prompt.
    Three points the entry did not specify, decided while implementing:
    - Configurable rather than always-prompt: `image.preview` is
      `"ask"`(default)`|"preview"|"system"`, so the prompt can be skipped in
      either direction. `"system"` reproduces the pre-9a behaviour exactly.
    - snacks wins when both are installed — it renders through its own
      buffer hook, so the float only has to `:edit` the path, with no
      placement or teardown to manage. image.nvim needs an explicit
      `from_file`/`render` and a `clear()` on `WinClosed`.
    - A failed preview (terminal without an image protocol, unreadable
      file) falls back to the system viewer instead of erroring — the user
      asked to see the image, not to use a particular renderer. A remote
      `http(s)://` target always goes to the system handler, since no
      provider has a local file to read.
    Covered by `TESTS/handler_image_spec.lua` (7 cases).
9. ~~**Link diagnostics**~~ — ✅ `core/link_diagnostics.lua` (dead relative-file
   links + duplicate heading titles) via `vim.diagnostic`
   (`:Markdown links check`; `links.diagnostics.mode = "save"` for automatic
   runs), reusing `core/link_scan` + the anchor slug logic.
10. ~~**Anchor style options**~~ — ✅ `core/slug.lua`'s `M.slugify` /
    `config.toc.anchor_style` (`"gfm"` default, opt-in `"keep-case"`) +
    `anchor_separator`.
11. ~~**Theme-derived blockquote/fenced colors**~~ — ✅ `blockquote_hl.marker_fg`/
    `text_fg` unset by default, derived from the active colorscheme
    (explicit config still overrides).
12. ~~**Per-key override table**~~ — ✅ done: `config.keymaps[id]` in
    `bindings/keymaps.lua`.
13. ~~**HTML→GFM table import**~~ — ✅ `table_fmt.parse_html_table` /
    `rows_to_gfm`, exposed via `:Markdown table import [clipboard|PATH]`.

## Phase 3 — testing

14. **Grow `TESTS/`** toward handler/anchor logic (currently: config,
    table_fmt (+ config-driven defaults, HTML import), link_scan,
    link_diagnostics, toc (+ config), picker, blockquote theme, headings).
    Pairs with A7's CI. Ongoing — extend further as new logic lands.

## Notes
- The four filetree-related gaps found during the Neo-tree audit
  (markdown-link bridge, pdfport, buffers-source, neotest) belong to
  **filetree.nvim**, not here — tracked in `filetree.nvim/docs/ROADMAP/NEOTREE_FEATURES.md`.
- markdown.nvim keeps `lib.nvim` as an *optional* dependency and its README in
  English (both intentional deviations from the config-module rules).
