# Fenced-block scope

A Markdown document often embeds *another* Markdown document inside a fenced
block — a `` ```markdown `` example, an `ascii-md` snippet, an `mdx` sample.
With `fenced_scope` enabled (the default), those blocks become their own
**document scope**: when your cursor is inside one, the heading-aware operations
act on the block's interior instead of the whole file; when your cursor is
outside, they act on the file but skip every fenced block's interior.

````markdown
## Some Headline

```markdown
# Start
## Second headline
### A level-3 heading
## Back to level 2
```
````

- **`<leader>toc`** inside the block inserts/refreshes a TOC **inside** the
  block (its own headings only). Outside, the outer TOC no longer picks up
  headings that live inside fenced blocks.
- **Heading nav** (`<C-f>`/`<C-p>`, `[[`/`]]`, `<leader><C-f>`/`<leader><C-p>`
  with a count) stays within the block; outside, it jumps *over* fenced blocks
  instead of landing on code lines.
- **Anchor jump** (`mj`) resolves within the block.
- **Shift-all** (`<S-Right>`/`<S-Left>`) shifts only the block's headings.

## Configuration

| Key | Default | Meaning |
|-----|---------|---------|
| `enable` | `true` | Master switch. Off ⇒ every op reverts to its whole-buffer behavior. |
| `langs` | `{ "markdown", "md", "mdx", "ascii-markdown", "ascii-md" }` | Fence tags that count as a Markdown sub-document. |
| `provider` | `"auto"` | Fence-detection backend. `"auto"` uses [color_my_ascii](https://github.com/StefanBartl/color_my_ascii.nvim)'s fence API when present, else a built-in scanner. |
| `operations` | all on | Per-op opt-out (`toc`, `nav`, `jump`, `shift`, `fold`). `fold` makes a `#` inside a non-markdown fence not open a fold. |

## Toggle at runtime

```vim
:Markdown scope on
:Markdown scope off
:Markdown scope toggle
:Markdown scope status
```

## Provider & nesting notes

- **color_my_ascii (optional, recommended).** When installed, its robust
  heuristic + treesitter fence detection is used as the source of truth. It's a
  *soft* dependency: markdown.nvim ships a small built-in fence scanner and works
  without it — install it for the most accurate detection. `:checkhealth
  markdown_nvim` reports which backend is active.
- **Nesting.** To nest a fenced block *inside* a `` ```markdown `` block, the
  outer fence must be longer (CommonMark rule), e.g. open the outer block with
  ```` ````markdown ````. The detector honours fence length, matching CommonMark.
