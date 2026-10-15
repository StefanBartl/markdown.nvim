# Health

```vim
:checkhealth markdown
```

Reports the Neovim version, the link opener chain with the last open attempts (what was started, how it ended), config
sanity, the optional host plugins (`:Markdown preview` / `mdview`, the picker backends),
required `lib.nvim` (the `:Markdown`/`:TableView*` command layer) plus its
optional `which-key` integration and picker-backend choice, and the
`fenced_scope` state (enabled ops + which fence-detection backend is active).

With mdview.nvim installed it also adds an info line (never a warning) when mdview's
`browser.focus` is not `"nvim"` or `browser.behavior` is not `"reuse"`, the two
settings that keep a screen-shared preview from stealing keyboard focus.
