# Health

```vim
:checkhealth markdown
```

Reports the Neovim version, the cross-platform opener (`vim.ui.open`), config
sanity, the optional host plugins (`:Markdown preview` / `mdview`, the picker backends),
required `lib.nvim` (the `:Markdown`/`:TableView*` command layer) plus its
optional `which-key` integration and picker-backend choice, and the
`fenced_scope` state (enabled ops + which fence-detection backend is active).
