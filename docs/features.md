# Features

| Module | What it does |
|--------|-------------|
| **headings** | Navigate (prev/next, by level), shift levels (normal/visual/whole-buffer, count-aware) |
| **fold** | Custom `foldexpr` for ATX and Setext headings, fold/unfold helpers |
| **TOC** | Insert or refresh a Table of Contents with GFM-like anchors and de-dup |
| **wrap** | Toggle `**bold**` on visual selection |
| **wrap\_link** | `<leader>[` — wrap word/selection in a Markdown link, auto-detecting URL vs. text |
| **headline\_spacing** | Ensure `[blank]---[blank]` separator between H2+ sections (incl. final closer) |
| **fenced\_fix** | Highlight override: injected-language colors shine through fenced blocks; inline `code` gets a distinct style |
| **blockquote HL** | Two-region blockquote coloring (`>` marker + text) via `matchadd` |
| **anchor / jump** | Jump to `#heading` anchors (GFM slug, duplicate handling) |
| **handler** | Double-click / `<C-LeftMouse>` / `ma`: open TOC links, HTML anchors, images; URLs in browser; media/binary in system app; text files via `:edit` |
| **tableview** | Floating Markdown table browser; HTML export (basic + styled) |
| **table\_fmt** | GFM table formatter (align columns, normalize separators) — self-contained |
| **table\_mode** | Auto-format table mode, `tableize`, cell motions — a dependency-free vim-table-mode core |
| **link\_scan** | Collect every link in a line/buffer; powers `:Markdown links show` and `create fs` |
| **fenced\_scope** | Treat a ` ```markdown ` / `md` / `mdx` block as its own sub-document: TOC, heading nav, anchor jump and shift scope to the block your cursor is in (see [Fenced-block scope](fenced-scope.md)) |
| **:Markdown** | Unified command: `links`, `toc`, `refs`, `table`, `render`, `preview`, `mdview`, `create`, `headline_spacing`, `scope` |
