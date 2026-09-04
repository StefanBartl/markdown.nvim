# markdown.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first, and a spec per plugin manager |
| [configuration.md](configuration.md) | Every option — and it opens with the ready-to-paste snippets, because most people arrive wanting one specific thing switched on |
| [health.md](health.md) | What `:checkhealth` reports |

## Using it

| Page | Answers |
| --- | --- |
| [commands.md](commands.md) | Everything funnelled through the single `:Markdown` command, subcommand by subcommand |
| [keymaps.md](keymaps.md) | The keys, grouped by what they are for — navigation first |
| [BINDINGS.md](BINDINGS.md) | Every keymap, user command and autocommand this plugin defines, in one inventory |
| [menu.md](menu.md) | The context-aware entries shipped for `nvzone/menu` |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each feature does, but how they combine while actually writing a document |

## The parts with a decision behind them

| Page | Answers |
| --- | --- |
| [FEATURES/](FEATURES/README.md) | One page per area — editing and handlers, headings, links and references, tables, highlighting and UI, integrations |
| [hover.md](hover.md) | The largest single integration: resting the cursor on a link or a bare path and seeing what it points at, and what markdown.nvim contributes to hover.nvim to make that work |
| [fenced-scope.md](fenced-scope.md) | Why a Markdown document embedded inside another one needs its own scope, and how that is decided |
| [image-captions.md](image-captions.md) | Markdown has no caption syntax; the three ways around that and which one this takes |
| [table-wrap.md](table-wrap.md) | Why the formatter aligns to natural width, and what happens when that does not fit |
| [architecture.md](architecture.md) | Which module does what |

## Here, but not prose

**`BINDINGS.lua`** is the same inventory as `BINDINGS.md`, machine-readable.
**`install.json`** declares the external tools this plugin can use, for
`:Lib deps show markdown.nvim`. **`templates/`** holds the document scaffolds
the plugin can insert.
