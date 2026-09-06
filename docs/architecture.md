# Architecture

```
lua/markdown/
  init.lua                 setup() + public Lua facade
  @types/
    init.lua               shared LuaLS type annotations
  config/
    init.lua               runtime store (setup/get)
    DEFAULTS.lua           typed default configuration
  health.lua               :checkhealth markdown
  util/
    notify.lua             vim.notify wrapper
    clipboard.lua          setreg("+") helper
    ignore.lua             default directory ignore list
    picker.lua             hover_select / vim.ui.select abstraction
    path.lua               link target -> filesystem path (buffer dir, then cwd; Windows-safe)
    platform.lua           cross-platform "open with system default app" (vim.ui.open + per-OS fallback)
    md_files.lua           collect every *.md file under a directory, recursively
  core/
    headings.lua           navigation + level shifting
    fold.lua               foldexpr, toggle, unfold
    fold_levels.lua        fold by heading level
    fold_prev.lua          fold previous heading
    toc.lua                TOC generator (GFM slugs, de-dup)
    refs.lua               keep in-document #anchor links + TOC in sync with heading renames
    heading_gaps.lua       detect/fix skipped heading levels
    underline_headings.lua Setext-style underline decoration for headings
    wrap.lua               visual bold toggle
    wrap_link.lua          <leader>[ wrap word/selection in a link
    link_scan.lua          collect links from a line/buffer
    link_delete.lua        DD -- delete a link's line and, on confirm, the file it points to
    link_diagnostics.lua   flag dead file links + duplicate headings via vim.diagnostic
    link_sanitize.lua      normalize link targets (backslashes, ensure ./ prefix)
    file_refs.lua          reverse search: which *.md files link to a given path
    heading_scan.lua       collect ATX headings from lines/buffer/file
    html_links.lua         `<img src>` / `<a href>` / `<figure>` blocks as links
    table_fmt.lua          GFM table formatter (self-contained)
    table_mode.lua         auto-format mode, tableize, cell motions
    table_wrap.lua         width-limited wrapping, unwrap, lint, CSV, hooks (:MDTable*)
    slug.lua               shared GFM slug + anchor map (toc + refs)
    headline_spacing/
      init.lua             ensure blank-dash-blank between H2+ sections (+ final closer)
  scope/
    init.lua               resolve the document scope (whole buffer vs. fenced sub-block) an op acts on
    builtin.lua            fallback fenced-block scanner, used when color_my_ascii isn't installed
  anchor/
    is_anchor_line.lua
    is_html_anchor_line.lua
    is_html_extern_anchor_line.lua
    is_inside_toc_block.lua
    jump.lua               jump to #anchor under cursor
  handler/
    init.lua               cursor-action dispatcher
    image.lua              open image (system viewer)
    url.lua                open URL (system browser)
    file.lua               open file (system viewer / :edit)
  hover/
    init.lua               markdown.nvim's contribution to hover.nvim: target-finding + registration
    section.lua            the two previews that need markdown knowledge: #heading and file.md#heading
  fenced_fix/
    init.lua               fenced-code + inline-code HL override
  hl_options/
    init.lua               orchestrator; re-applies on ColorScheme
    hl_groups/
      blockquote.lua       decoration-provider blockquote coloring (hl_eol)
      link.lua             tame the underline on inline-link URLs/labels
  tableview/
    parser.lua             pipe-table parser
    renderer.lua           floating window renderer (Markdown + box style);
                            widths use display-width, not byte length;
                            validate_alignment(lines) checks a rendered
                            table's | / │ dividers actually line up
    views/
      browser_basic.lua    basic HTML export
      browser_niceified.lua styled HTML export
      browser_session.lua  shared "reuse one tab" plumbing for the two exports above
      table_selector.lua   pick-a-table floating UI
  integrations/
    menu.lua               context-aware entries for nvzone/menu (opt-in, host composes them)
  commands/
    init.lua               :Markdown dispatcher + nested completion
    links.lua              :Markdown links show|create
    list.lua               :Markdown list headings (picker + jump)
    markdown_links.lua     directory-to-link generator (links create)
    toc.lua                :Markdown toc (TOC + separators)
    refs.lua               :Markdown refs sync|check|live|baseline (thin wrapper over core/refs.lua)
    table.lua              :Markdown table view|format|new|mode|tableize|import
    render.lua             :Markdown render (render-markdown.nvim)
    preview.lua            :Markdown preview (markdown-preview.nvim)
    mdview.lua             :Markdown mdview (mdview.nvim)
    image.lua              :Markdown image paste|screenshot (images.nvim)
    export.lua             :Markdown export <sub> (pdfport.nvim)
    scope.lua              :Markdown scope [on|off|toggle|status]
    create.lua             :Markdown create fs
    mdtable.lua            :MDTable* operations (wrap/unwrap/lint/csv/profile/fold/...)
  bindings/                all keymaps, user commands and autocmds live here
    init.lua               orchestrator: setup(cfg) + which-key group labels (via lib.nvim)
    actions.lua            named editing actions (public via .actions)
    keymaps.lua            buffer-local default keys (editing + TableView)
    usrcmds.lua            :Markdown + OpenWith + TableView* + MDTable* command registration
    autocmds.lua           FileType / BufWritePost / VimResized / WinResized drivers
plugin/
  markdown.lua        guard (vim.g.loaded_markdown)
doc/
  markdown.nvim.txt        :h markdown.nvim vim help file
docs/
  BINDINGS.md             prose binding inventory (BINDINGS.lua = the same data, machine-readable)
TESTS/                     headless spec suite
```
