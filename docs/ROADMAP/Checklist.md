# Checklist (PR-Review / Coding) — applied to markdown.nvim

Application of [`Checklist.md`](../../../Notes/MyNotes/Checklists/Lua/Checklist.md).
Only the Neovim/Lua sections apply; the algorithm/data-structure/sorting
sections (sort selection, BST/heap/trie/…, complexity notation, bit tricks) are
**N/A** — markdown.nvim implements no such structures.

## Schnell-Check (10 points)

| Status | Check | markdown.nvim |
|---|---|---|
| ✅ | Error handling | `pcall`/`safe_call` around mutations & wiring |
| ✅ | Type guards | `type(...)` + nil checks before API |
| ✅ | Buffer/window valid | `nvim_buf_is_valid`/`is_loaded` before ops |
| ✅ | No global state | no `_G.*`; module-local state |
| ✅ | Single responsibility | clear module split (core/bindings/commands/handler) |
| 🟡 | UI cleanup | `tableview` closes floats via `ui.close()`; verify a `cleanup_all` path (A2) |
| ✅ | Performance hotspots | `table.concat`, no `..` loops, no hot autocmds |
| 🟡 | Annotations complete | heads + typed config ✅; **no `@types/` folder** (A3) |
| ✅ | Testability | `docs/TESTS/` spec suite |
| ✅ | Import order | System → utils → state/logic → bindings, consistently |

## PR-Review detail — deltas only
- **§1 Safety:** ✅ except raw `vim.notify`/`print` (see **A1**).
- **§2 Modularity:** ✅ `config/DEFAULTS.lua` present; no globals.
- **§3 Buffer/Window:** ✅; re-validate deferred callbacks in `tableview/renderer.lua` (**A2**).
- **§4 UI-State:** 🟡 `tableview/live.lua` keeps module-local `state` with `is_running()`
  accessor — fine; no getter/setter ceremony needed at this size.
- **§5 Docs/Annotations:** 🟡 → **A3** (`@types/` folder).
- **§6 Testability:** ✅.
- **§7 Tooling:** ✅ `.luarc.json` added; ❌ **no stylua/luacheck config or CI** → **A7**.

## Coding-checklist (A–F) — deltas only
- **A. Strings/tables:** ✅ (`table_fmt` uses `t[#t+1]` + `concat`).
- **B. Performance quickwins:** ✅ / N/A (no hot loops).
- **C. Neovim-API safety:** ✅; deferred re-validation (**A2**).
- **D. State models:** ✅ at current scope.
- **E. GC:** N/A (no large transient allocations).
- **F. Lazy-loading:** ✅ (require-on-call, `ft`-scoped).

## Architektur / Anti-Pattern / Import-struktur
- ✅ Low coupling / high cohesion; dependencies passed explicitly (`cfg` into
  `bindings.setup`).
- ✅ Adapter/registry-style: `commands/init.lua` dispatches subcommands; the
  `<Plug>` surface decouples keys from actions.
- ✅ Anti-patterns clean: no global state, no API-without-guards, no string-concat
  loops, no closures-in-loops in hot paths.
- 🟡 Import/file-structure: header tags ✅, but the project-wide `@types` folder is
  missing (**A3**).

## Action backlog (this checklist)
- **A1** — messages through `util/notify` (shared with Arch&Coding).
- **A2** — deferred-callback handle re-validation in `tableview/renderer.lua`.
- **A3** — `@types/` folder.
- **A7** — add `stylua.toml` + `.luacheckrc` (and a minimal CI running them + `docs/TESTS/run.lua`).
