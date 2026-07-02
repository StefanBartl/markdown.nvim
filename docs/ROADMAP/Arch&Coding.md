# Arch & Coding-Regeln — applied to markdown.nvim

Application of [`Arch&Coding-Regeln.md`](../../../Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md)
to this repo. Status per rule group with concrete findings and action items.
Legend: ✅ compliant · 🟡 partial · ❌ gap · N/A not applicable.

## 1. Safety & error handling
- ✅ `pcall` around buffer mutations and keymap/command wiring (`bindings/keymaps.lua`,
  handlers, `core/table_fmt.lua` via `safe_call`).
- ✅ Type guards before API (`type(bufnr) ~= "number"`, `nvim_buf_is_valid`).
- ✅ Explicit `true/false (+ err)` returns in `handler/*`, `core/table_fmt.lua`.
- 🟡 **notify only in UI layers** — mostly via `util/notify.lua`, but there are
  **raw** calls to fix:
  - `commands/init.lua:22,28` → `vim.notify(...)`
  - `commands/markdown_links.lua:117,124` → `vim.notify(...)`, `:123` → `print(result)`
  - **Action A1:** route these through `util/notify` (drop the bare `print`).

## 2. Modularization & structure
- ✅ One responsibility per module; `core/` pure logic, `bindings/` triggers,
  `commands/` dispatch, `handler/` cursor actions.
- ✅ Pure functions where it counts (`core/table_fmt`, `core/link_scan`,
  `core/headings`, `core/toc` slug).
- ✅ Internal helpers kept `local`. No global state (`grep _G.` → none).

## 3. Buffer & window management
- ✅ Handle-first-then-validate in `bindings/usrcmds.lua`, `core/table_fmt.lua`
  (`nvim_buf_is_valid` / `is_loaded`).
- 🟡 `tableview/renderer.lua` floating windows — confirm every deferred callback
  re-validates the win/buf handle (checklist §Race Conditions). **Action A2** (review).

## 4. Methods, metatables, data models
- N/A — no metatable-based OO; plain module tables. Fine for this plugin's scope.

## 5. Documentation & annotations
- ✅ File head tags (`@module`/`@brief`/`@description`) throughout.
- ✅ Config now fully typed (`config/DEFAULTS.lua`: `Mkdn.Config` + sub-classes).
- ❌ **No project-wide `@types/` folder.** The rule wants a `lua/markdown_nvim/@types/`
  with type files that `return {}`, keeping source free of large annotation blocks.
  Types currently live inline in `config/DEFAULTS.lua` and scattered (`Mkdn.Link`
  in `core/link_scan.lua`, table types in `tableview/`).
  - **Action A3:** create `lua/markdown_nvim/@types/init.lua` (+ split files) and
    move shared `@class`/`@alias` there.

## 6. Testability & readability
- ✅ Headless spec suite in `docs/TESTS/` (config, table_fmt, link_scan, headings).
- 🟡 Handler/anchor logic still buffer-coupled; grow specs over time (matches ROADMAP).

## 7–10. Performance / caching / weak tables
- ✅ Pure line-scan, no Treesitter, no `CursorMoved`/`TextChanged` autocmds → no hot path.
- ✅ `core/table_fmt` builds rows via `parts[#parts+1]` + `table.concat` (no `..` loops).
- N/A — no caches/weak-tables needed at current scope; revisit only if a hot path appears.

## MISC — cross-platform & the `lib` library
- 🟡 **Cross-platform opener is duplicated.** `vim.ui.open` is preferred (good), but
  the legacy per-OS branch (`os_uname` → `xdg-open`/`open`/`cmd /C start`/`jobstart`)
  is copy-pasted across `handler/file.lua`, `handler/image.lua`, `handler/url.lua`,
  `tableview/live.lua`, `tableview/views/browser_basic.lua`, `browser_niceified.lua`.
  - **Action A4:** extract `util/platform.lua` (or `util/open.lua`) — one
    `open(path_or_url)` used everywhere. DRY + single place to maintain.
- **Intentional deviation:** the checklist's `lib.notify`/`lib.map`/… rule targets
  **nvim-config modules**. markdown.nvim is a **distributable standalone plugin**, so
  it must not hard-depend on the personal `/nvim/lua/lib`. It ships its own
  `util/notify.lua` and treats `lib.nvim` as an *optional* soft dependency
  (`util/picker.lua`). Keep this as-is.
- **Intentional deviation:** rule 5 wants a German README + English vimdoc for
  *config* modules. As a public plugin, markdown.nvim's README is English by design.

## Action backlog (this checklist)
- **A1** — route `commands/init.lua` + `commands/markdown_links.lua` messages through `util/notify`; drop bare `print`.
- **A2** — audit `tableview/renderer.lua` deferred callbacks for handle re-validation.
- **A3** — introduce `lua/markdown_nvim/@types/` and move shared types there.
- **A4** — extract a single cross-platform `util/platform.lua` opener; replace the 6 duplicated branches.
