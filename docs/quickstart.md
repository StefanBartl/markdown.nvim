# Quickstart

Open a Markdown file and give it a table of contents:

```vim
:Markdown toc
```

Then the rest of the everyday set:

```vim
:Markdown links          " scan, list and open the links in a picker
:Markdown links create   " create the files the local links point at
:Markdown refs           " sync reference-style anchors
:Markdown table          " format and align the table under the cursor
:Markdown scope          " treat the fenced block under the cursor as its own document
:Markdown export pdf     " the buffer to PDF, via pdfport.nvim
```

Rest the cursor on any link and a small float previews what it points at — an
image, a PDF's first page, another file's section, a directory listing, an
in-page anchor, a URL — or says the target does not exist. A path written as
plain text hovers the same way, in any filetype: `./assets/diagram.png` in a
code comment, or a truncated `...nvim/init.lua:42` out of a log. That float is
[hover.nvim](https://github.com/StefanBartl/hover.nvim); the detail is
[hover.md](hover.md).

Verify your setup any time with:

```vim
:checkhealth markdown
```

See [what-you-get.md](what-you-get.md) for the rest of the surface at a
glance, or [commands.md](commands.md) for the full reference.
