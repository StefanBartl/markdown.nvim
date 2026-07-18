# Architecture

```
lua/markdown_nvim/
  init.lua                 setup() + public Lua facade
  config/
    init.lua               runtime store (setup/get)
    DEFAULTS.lua           typed default configuration
  health.lua               :checkhealth markdown_nvim
  util/
    notify.lua             vim.notify wrapper
    clipboard.lua          setreg("+") helper
    ignore.lua             default directory ignore list
    picker.lua             hover_select / vim.ui.select abstraction
  core/
    headings.lua           navigation + level shifting
    fold.lua               foldexpr, toggle, unfold
    fold_levels.lua        fold by heading level
    fold_prev.lua          fold previous heading
    toc.lua                TOC generator (GFM slugs, de-dup)
    wrap.lua               visual bold toggle
    wrap_link.lua          <leader>[ wrap word/selection in a link
    link_scan.lua          collect links from a line/buffer
    table_fmt.lua          GFM table formatter (self-contained)
    table_mode.lua         auto-format mode, tableize, cell motions
    slug.lua               shared GFM slug + anchor map (toc + refs)
    headline_spacing/
      init.lua             ensure blank-dash-blank between H2+ sections (+ final closer)
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
  fenced_fix/
    init.lua               fenced-code + inline-code HL override
  hl_options/
    init.lua               orchestrator; re-applies on ColorScheme
    hl_groups/
      blockquote.lua       matchadd-based blockquote coloring
  tableview/
    parser.lua             pipe-table parser
    renderer.lua           floating window renderer (Markdown + box style);
                            widths use display-width, not byte length;
                            validate_alignment(lines) checks a rendered
                            table's | / │ dividers actually line up
    views/
      browser_basic.lua    basic HTML export
      browser_niceified.lua styled HTML export
      table_selector.lua   pick-a-table floating UI
  commands/
    init.lua               :Markdown dispatcher + nested completion
    links.lua              :Markdown links show|create
    markdown_links.lua     directory-to-link generator (links create)
    toc.lua                :Markdown toc (TOC + separators)
    refs.lua               :Markdown refs sync|check|live|baseline
    table.lua              :Markdown table view|format|new
    render.lua             :Markdown render (render-markdown.nvim)
    preview.lua            :Markdown preview (markdown-preview.nvim)
    mdview.lua             :Markdown mdview (mdview.nvim)
    create.lua             :Markdown create fs
  bindings/                all keymaps, user commands and autocmds live here
    init.lua               orchestrator: setup(cfg)
    actions.lua            named editing actions (public via .actions)
    keymaps.lua            buffer-local default keys (editing + TableView)
    usrcmds.lua            :Markdown + OpenWith + TableView* command registration
    autocmds.lua           FileType / BufWritePost drivers
    which_key.lua          optional which-key group labels (guarded)
plugin/
  markdown_nvim.lua        guard (vim.g.loaded_markdown_nvim)
doc/
  markdown.nvim.txt        :h markdown.nvim vim help file
docs/
  BINDINGS.md             machine-readable binding cheatsheet
  ROADMAP.md               planned work
  TESTS/                   headless spec suite
```
