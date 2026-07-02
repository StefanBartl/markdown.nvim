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
| `headings_spec.lua`  | Heading level shift (up/down, H6 clamp, non-markdown no-op).    |
| `run.lua`            | Runner: loads every spec, reports results, sets the exit code.  |

## Adding a spec

Create `<name>_spec.lua` returning `function(H) … end` (use `H.eq` / `H.ok` /
`H.scratch`) and add its filename to the `specs` list in `run.lua`.
