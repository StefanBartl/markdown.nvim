# markdown.vim — feasibility analysis (pure-Vim port)

**Question.** Can we produce a `markdown.vim` that runs in a **pure Vim** instance
(not Neovim), either as its own plugin or inside this repo — and is a separate
`.vim` plugin justified? **Goal:** run as many features as possible under plain
Vim.

This is a first analysis, not a port.

---

## 1. The hard constraint

markdown.nvim is Lua built on the **Neovim API** (`vim.api.nvim_*`, `vim.fn`,
`vim.keymap`, `vim.ui.open`, `vim.loop/uv`, floating windows, `vim.health`).
None of that exists in Vim. Three facts decide everything:

1. **Vim has no Neovim API.** `nvim_buf_*`, `nvim_open_win`, `vim.keymap.set`,
   `vim.ui.open`, `vim.health` are Neovim-only.
2. **Vim's Lua (`+lua`) is a *different, optional* interface.** It is the old
   `vim.buffer()/vim.window()/vim.eval()/vim.command()` binding, compiled in only
   when Vim is built `+lua`. Relying on it means the plugin *doesn't* run in a
   "pure Vim instance" (many Vims ship without `+lua`). So Lua is not a portable
   target.
3. **The only universal language for every modern Vim is vim9script**
   (legacy Vimscript as fallback). That is what a pure-Vim port must be written in.

**Consequence:** a pure-Vim version cannot share Lua source with markdown.nvim.
It is a **reimplementation in vim9script**. The only shareable artifacts are the
*specification* and the *test fixtures* (input → expected output), not code.

The one thing working in our favor: markdown.nvim **deliberately avoids
Treesitter** and is almost all line-scan/text logic, so the *algorithms* port
cleanly — it's the API surface that has to be rewritten.

---

## 2. Feature portability inventory

Legend: 🟢 portable (pure Vimscript/vim9) · 🟡 portable with a different Vim API ·
🔴 Neovim-only (drop or rethink).

| Feature | markdown.nvim impl / API dependency | Pure-Vim path | Port |
|---|---|---|---|
| Heading nav (prev/next, by level) | `core/headings`, cursor + line scan | `search()`, `cursor()` | 🟢 |
| Heading level shift (n/v/buffer, count) | `core/headings.shift_range`, `nvim_buf_get/set_lines` | `getline()`/`setline()`, `substitute()` | 🟢 |
| Folding (ATX + Setext foldexpr) | `core/fold.foldexpr` | Vim `foldexpr` (Vimscript) | 🟢 |
| TOC insert/refresh (GFM slugs, de-dup) | `core/toc`, buffer read/write | `getline()`/`append()`/`setline()` | 🟢 |
| Bold wrap (visual `**`) | `core/wrap` | visual marks + `setline()` | 🟢 |
| Link wrap (`<leader>[`) | `core/wrap_link` | same | 🟢 |
| Headline spacing (`---` between H2+) | `core/headline_spacing` | line insert logic | 🟢 |
| GFM table formatter | `core/table_fmt` (pure text) | direct 1:1 rewrite | 🟢 |
| Link scan (line/buffer) | `core/link_scan` (pure text) | direct 1:1 rewrite | 🟢 |
| Anchor jump (`#heading`) | `anchor/jump`, line scan | `search()` | 🟢 |
| `:Markdown` command + subcommands | `commands/*`, `nvim_create_user_command` | `:command` + `<Plug>` | 🟢 |
| Blockquote highlight | `hl_options/blockquote`, `matchadd` | `matchadd()` exists in Vim | 🟢 |
| Open under cursor (URL/file/image) | `handler/*` → `vim.ui.open`/`jobstart` | `netrw#BrowseX()` or `job_start()`/`system()` | 🟡 |
| System opener (`util/platform`) | `vim.ui.open` + `jobstart` | `job_start()` per-OS (already isolated!) | 🟡 |
| TableView preview (floating window) | `tableview/renderer`, `nvim_open_win` | Vim **`popup_create()`** (Vim 8.2+) | 🟡 |
| Live browser export/preview | `tableview/live`, temp HTML + opener | `writefile()` + `job_start()` | 🟡 |
| Fenced-code HL fix | `fenced_fix`, targets Treesitter `@markup.*` groups + `nvim_set_hl` | Vim `syntax`/`markdownCode*` groups only | 🟡 (different groups) |
| `:checkhealth markdown_nvim` | `health.lua`, `vim.health` | no Vim equivalent | 🔴 drop |
| which-key labels | `bindings/which_key` | Neovim plugin | 🔴 drop |
| render-markdown / markdown-preview wrappers | `commands/{render,preview}` | Neovim plugins | 🔴 drop (Vim has its own preview plugins) |
| lib.nvim notify/picker soft-deps | `util/{notify,picker}` | Vim: `echomsg` / `popup_menu()` | 🟡 |

**Tally:** ~13 features 🟢 straight rewrite, ~6 🟡 need a different Vim API,
~3 🔴 Neovim-only (correctly dropped). i.e. **~90 % of the user-facing value is
reachable in pure Vim** — but only via a vim9script rewrite.

---

## 3. Architecture options

### A. Same plugin, dual-target (lua/ + autoload/ in one repo)
Ship both a Lua tree (Neovim) and a vim9script tree (Vim) in this repo, chosen at
load time by `has('nvim')`.
- **Pro:** one repo/issue tracker; shared README, docs, and test fixtures.
- **Con:** **near-zero code sharing** (the two language runtimes can't call each
  other's core), so it is effectively two parallel implementations under one roof.
  Doubles the maintenance surface and muddies the Lua-first structure we just
  cleaned up (`bindings/`, `@types/`, checkhealth). The repo would carry a large
  `autoload/markdown/` vim9 tree that most (Neovim) users never load.
- **Verdict:** not worth it. The only real sharing (docs + `docs/TESTS` fixtures)
  can be had without co-locating the source.

### B. Separate `markdown.vim` repo (vim9script)
A standalone plugin implementing the portable subset in vim9script.
- **Pro:** idiomatic for Vim users; clean install (`ft=markdown`); Neovim repo
  stays Lua-pure; each repo has one language and one audience.
- **Con:** a genuine second implementation to maintain; parity drift risk. Shares
  only the spec + test fixtures (copy or git-submodule the `docs/TESTS` cases).
- **Verdict:** the **only technically clean way** to actually run in pure Vim.

### C. Subset-only (either A or B, but scoped)
Port just the **editing core** (headings, TOC, fold, table format, wrap, headline
spacing, link scan/open) and skip the UI-heavy and Neovim-only bits. ~70 % of the
value for ~40 % of the effort; the floating TableView (popup) and live preview
come later.

---

## 4. Is a separate `.vim` plugin justified?

**Short answer: only if there is real pure-Vim usage/demand — otherwise no.**

- The audience for *pure Vim, no `+lua`, wanting a markdown toolkit* is small and
  shrinking; Neovim is the growth platform.
- markdown.nvim's Treesitter-free design makes the port *feasible*, but "feasible"
  still means a full vim9script reimplementation + ongoing parity maintenance of a
  second codebase.
- Dual-target in one repo (option A) buys almost no sharing while taxing every
  future change — actively harmful to the Lua repo's clarity.

**Recommendation.**
1. **Do not** dual-target inside this repo.
2. If pure-Vim support is wanted (personal use or user demand), create a
   **separate `markdown.vim`** repo in **vim9script**, scoped to the **editing
   core** first (option B + C):
   - Phase 1 (🟢, high ROI): heading nav/shift, folding, TOC, table format, bold/
     link wrap, headline spacing, link scan, anchor jump, `:Markdown` + `<Plug>`.
   - Phase 2 (🟡): open-under-cursor via `netrw#BrowseX`/`job_start`, TableView via
     `popup_create`, live export via `writefile`+`job_start`.
   - Dropped (🔴): checkhealth, which-key, render-markdown/preview wrappers.
3. **Share the spec, not the code:** lift `docs/TESTS`' input→output fixtures into
   a language-neutral form (e.g. plain `.md`/`.json` cases) both plugins test
   against, to keep parity honest.

**Rough effort (separate repo, vim9script):** Phase 1 ≈ a few focused days
(the logic is simple, the rewrite is mechanical); Phase 2 ≈ similar again for the
popup/preview surface. Maintenance: a second, smaller codebase to keep in parity.

---

## 5. First concrete steps (if pursued)

1. Freeze a **portable spec** from the current core: extract the pure input→output
   behavior of `core/{table_fmt,link_scan,headings,toc,headline_spacing}` into
   fixtures under a neutral folder.
2. Scaffold `markdown.vim` (`autoload/markdown/*.vim`, `plugin/markdown.vim`,
   `<Plug>` surface mirroring `docs/BINDINGS.lua`, `g:markdown_*` config mirroring
   `Mkdn.Config`).
3. Port Phase-1 features against the fixtures; wire the `:Markdown` command +
   `<Plug>` maps to match markdown.nvim's names for muscle-memory parity.
4. Revisit Phase 2 (popup TableView, preview) once Phase 1 is stable.

**Bottom line:** technically ~90 % of markdown.nvim can live in pure Vim, but only
as a separate vim9script plugin sharing the spec/tests — a same-repo dual-target
is not justified, and the port itself is justified only by actual Vim demand.
