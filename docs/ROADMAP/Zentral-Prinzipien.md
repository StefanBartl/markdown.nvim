# Zentrale Prinzipien — applied to markdown.nvim

Application of [`Zentrale-Prinzipien.md`](../../../Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md)
— the per-module mental check. Legend: ✅ · 🟡 · ❌ · N/A.

| # | Principle | markdown.nvim | Status |
|---|---|---|---|
| 1 | Bundle events, decouple logic | All autocmds consolidated in `bindings/autocmds.lua` under named augroups; features register via the FileType driver, not scattered `nvim_create_autocmd` calls. | ✅ |
| 2 | Lazy-load own logic | Facade + bindings `require` feature modules **inside** the callbacks (`function() require("...").fn() end`), so nothing loads until used; plugin is `ft`-scoped. | ✅ |
| 3 | Context over repeated API calls | Handlers re-query `nvim_get_current_line` / cursor per call. Acceptable (one-shot, key-driven), but a small `ctx { bufnr, line, row }` would DRY `handler/*`. | 🟡 (A5) |
| 4 | Clean autocommand groups | Named groups (`MarkdownNvimKeymaps`, `…TableView`, `…TableViewLive`, `…Fold`), all `clear = true` → reload-safe. | ✅ |
| 5 | Event or command? | Auto behavior limited to FileType install + BufWritePost live refresh (guarded by `live.is_running()`); everything else is explicit keys/`:Markdown`. | ✅ |
| 6 | Treesitter necessary? | Not used — pure line-scan/regex, matching the "reicht ein Zeilen-Scan?" guidance. | ✅ |
| 7 | Cache present & explicit? | No repeated expensive computation; no cache needed. | N/A |
| 8 | Avoid hot-path allocations | No `CursorMoved`/`TextChanged`; `table_fmt` uses `t[#t+1]`+`concat`. No hot path. | ✅ |
| 9 | Debuggability planned? | `util/notify` tags every message with the module (`[markdown.x]`); `:checkhealth markdown` reports state. No dedicated debug switch. | 🟡 (A6) |
| 10 | Runtime > startup? | `ft`-scoped, minimal per-buffer work; startup cost negligible. | ✅ |

## Findings
markdown.nvim already satisfies the runtime/event discipline well (this is a
line-scan, key-driven plugin with no per-keystroke autocmds). Only two soft
improvements:

- **A5** — optional shared `ctx` helper for `handler/*` (build `{ bufnr, line, row }`
  once instead of re-querying). Low priority.
- **A6** — optional lightweight debug flag (e.g. `vim.g.markdown_debug`) that
  makes `util/notify` emit trace-level messages. Low priority.
