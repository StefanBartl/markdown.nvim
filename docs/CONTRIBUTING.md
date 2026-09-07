# Contributing to markdown.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/markdown.nvim/issues); pull
requests very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it
to the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/markdown.nvim")
require("markdown").setup({})
```

[lib.nvim](https://github.com/StefanBartl/lib.nvim) has to be on the runtime
path too — the `:Markdown` and `:TableView*` command layer is built on it.
Nothing else is required; `rg` only speeds up the reverse file-reference
search.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation, `.stylua.toml` decides
  the rest.
- **Nothing happens outside a Markdown buffer.** Everything the plugin
  installs is buffer-local, put there by a `FileType` autocommand; only
  `:Markdown` itself is global. A change that touches a global option, a global
  keymap or a non-Markdown buffer is a bug, not a feature — the one deliberate
  exception is the bare-path hover, which is opt-in and lives in
  [`hover.md`](hover.md).
- **This plugin does not render.** Preview, rendering and PDF export are
  delegated to whichever of render-markdown.nvim, markdown-preview.nvim,
  mdview.nvim, images.nvim and pdfport.nvim is installed. Drawing a preview
  here would duplicate four plugins and be worse than all of them.
- **Every integration is soft.** Detected at runtime, absent means one feature
  missing rather than an error. Never `require` an optional plugin at
  `setup()` time.
- **Scope before operating.** An operation acts on the scope
  `lua/markdown/scope/` resolves — the whole buffer, or the fenced block the
  cursor is in. Reimplementing "find the region" inside a command is how the
  two drift apart; see [`fenced-scope.md`](fenced-scope.md).
- **Slugs come from one place.** `core/slug.lua` is the shared GFM slug and
  anchor map. The TOC generator, the reference sync and the anchor jump all use
  it, because a second implementation means anchors that only work in one of
  the three.
- **Deleting a file is confirmed.** `DD` removes a link's line and, only after
  a confirmation, the file it points at. Any new operation that can lose data
  asks first, in the same shape.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/markdown/core/` | The document operations: headings, folding, TOC, refs, link scanning and diagnostics, the table formatter and `table_wrap`, slugs, headline spacing |
| `lua/markdown/commands/` | One module per `:Markdown` subcommand, over the core |
| `lua/markdown/handler/` | The cursor-action dispatcher and its targets: image, url, file |
| `lua/markdown/anchor/` | Anchor-line recognition and the `#anchor` jump |
| `lua/markdown/hover/` | What this plugin contributes to hover.nvim: target finding, registration, and the two previews that need Markdown knowledge |
| `lua/markdown/scope/` | Whole buffer vs. fenced sub-block, and the fallback fenced scanner |
| `lua/markdown/tableview/` | The floating table browser and its renderer |
| `lua/markdown/fenced_fix/`, `hl_options/` | Fenced-block repair and the highlighting options |
| `lua/markdown/integrations/` | `menu.lua` — the nvzone/menu entries |
| `lua/markdown/bindings/` | Keymaps, user commands and the `FileType` autocommand that installs them |
| `lua/markdown/config/` | `DEFAULTS.lua` and the runtime store |
| `lua/markdown/util/` | notify, clipboard, ignore list, picker abstraction, path resolution, platform open, markdown-file collection |
| `doc/`, `docs/` | The vimdoc, and everything the README links to |
| `TESTS/` | The spec suite |

[`architecture.md`](architecture.md) is the same tree with a line per file.

## Adding a command

1. Put the logic in `lua/markdown/core/` — a function over lines or a buffer
   that returns data. Commands render, core computes.
2. Add the subcommand module under `lua/markdown/commands/` and route it in
   `lua/markdown/bindings/`, with completion.
3. Resolve the target region through `lua/markdown/scope/`, never by scanning
   for a fence yourself.
4. Add a spec under `TESTS/`.
5. Document it in [`commands.md`](commands.md), the matching page under
   [`FEATURES/`](FEATURES/README.md), and — if it binds a key or an
   autocommand — in [`BINDINGS.md`](BINDINGS.md) **and**
   [`BINDINGS.lua`](BINDINGS.lua), which carry the same inventory for humans
   and for tools respectively.

## Adding a cursor handler

The dispatcher in `handler/init.lua` decides what is under the cursor and hands
it to a handler.

1. Add the handler under `lua/markdown/handler/`, taking the resolved target.
2. Register the recognizer with the dispatcher rather than adding a branch to
   an existing handler.
3. Resolve paths through `util/path.lua` — buffer directory first, then cwd,
   Windows-safe — and open through `util/platform.lua`.
4. If the target type can also be previewed, contribute it in
   `lua/markdown/hover/` too, so the hover and the action agree on what a link
   points at.
5. Add a spec, and cover the not-found case: saying nothing is there is part of
   the contract.

## Tests

`TESTS/` is a headless spec suite over fixture documents.

```
LIB_NVIM_PATH=/path/to/lib.nvim HOVER_NVIM_PATH=/path/to/hover.nvim \
  nvim --headless -i NONE -u NONE -c "set rtp+=." -c "luafile TESTS/run.lua" -c "qa!"
```

Exit 0 is a pass. The two paths are how the runner finds the dependencies; the
hover specs need the second one. [GitHub Actions](../.github/workflows/ci.yml) runs it plus
stylua and luacheck on every push and pull request to `main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
