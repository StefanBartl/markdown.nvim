# Config templates

Copy-paste-ready `setup()` snippets for common customizations. Each file
covers one topic in isolation — merge just the block you need into your own
`require("markdown").setup({ ... })` call; you don't need to (and shouldn't)
paste a whole file verbatim over your existing config.

For the full option reference with every default explained, see
[docs/configuration.md](../configuration.md). This directory is the
"I just want X" complement to that reference.

| Template | What it's for |
| --- | --- |
| [blockquote-hl.md](blockquote-hl.md) | Turn off / restyle the default VS Code-style `>` quote coloring |
| [minimal.md](minimal.md) | Run only a subset of features (`just_enable`) instead of the full plugin |
| [links-picker.md](links-picker.md) | Switch the link picker backend (telescope / fzf-lua / vim.ui.select) |
| [image-preview.md](image-preview.md) | Control how `mi` (follow image) previews — floating window vs system viewer |

Missing something you'd find useful here? Open an issue or a PR — this
directory is meant to grow with real questions, not to be exhaustive upfront.
