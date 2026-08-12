# Tests

Headless spec suite for markdown.nvim. Covers the pure / buffer-level logic
that is trivially testable without a UI.

## Run

From the repo root:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
```

The runner prints one line per spec and exits non-zero on the first failure
(`MARKDOWN_TESTS_OK` on success).

## Layout

| File                 | Covers                                                          |
| -------------------- | --------------------------------------------------------------- |
| `harness.lua`        | Shared `eq`/`ok` assertions and a `scratch(ft)` buffer helper.  |
| `config_spec.lua`    | Config defaults + deep-merge of user options.                   |
| `table_fmt_spec.lua` | GFM formatter: `parse_args`, `complete`, buffer formatting.     |
| `link_scan_spec.lua` | `from_line` / `from_lines` link extraction (+ fenced skip).     |
| `headings_spec.lua`  | Heading level shift + nav (up/down, H6 clamp, H1 reach, column preservation, non-markdown no-op). |
| `handler_spec.lua`   | Cursor-action handler: silent mode suppresses the "no target" notification for mouse invocation. |
| `anchor_jump_spec.lua` | Anchor jump: successful jump notifies nothing, "no anchor under cursor" vs. "anchor resolves to no heading" are distinct info notifications (regression for the pcall-ok-flag-vs-result mixup), duplicate-slug disambiguation (`#note`/`#note-1`/`#note-2`), and the TOC-list-entry double-click end-to-end via the handler. |
| `tableview_spec.lua` | Floating TableView preview closes via `q`/`<Esc>`.              |
| `tableview_alignment_spec.lua` | TableView column alignment with multi-byte UTF-8 content (umlauts, em dashes, curly quotes, arrows, ellipses) — regression coverage for the byte-length-vs-display-width padding bug, using the new `renderer.validate_alignment(lines)` de-facto check (also verifies the validator itself catches a genuinely drifted table, not just rubber-stamps everything). |
| `browser_session_spec.lua` | TableView browser export (`browser`/`browsernice`) reuses one tab across calls: opens the system browser once per style, later calls overwrite the same fixed file instead of opening a new tab, a different style opens independently, and `force_new` ('reopen') opens a fresh tab on demand. |
| `fenced_scope_spec.lua` | Fenced-block scope: detection + TOC/nav/jump/shift/fold wiring. |
| `session_features_spec.lua` | De-facto coverage for refs sync, actions/keymaps, feature gating, the menu integration, double-click fold (ATX + Setext), the link-underline fix, the fold H2+ outline toggle, the fold-from-menu-context bug fix, TableView box style + configurable default, table mode/tableize/cell motions, and the Windows `platform.open` fix. Drives the real `:Markdown` commands and public `actions` API, not private internals. |
| `run.lua`            | Runner: loads every spec, reports results, sets the exit code.  |

### What can't be tested headless

A few things need a real UI and are out of scope for this suite — verify them
manually:

- **In-terminal image rendering** (snacks.image / kitty graphics) needs a real
  graphics-capable terminal (WezTerm). Open an image file or a markdown doc
  with an image link and check `:checkhealth snacks`.
- **The nvzone/menu popup actually appearing on RightMouse** is UI-only;
  `session_features_spec.lua` verifies the *entries* menu.items() builds
  (context-aware, opt-out), but not the popup rendering itself. Right-click a
  heading in a real Neovim session and try each entry.

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch`) and add its filename to the `specs` list in `run.lua`.
