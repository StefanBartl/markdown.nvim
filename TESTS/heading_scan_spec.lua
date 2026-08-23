-- TESTS/heading_scan_spec.lua — core.heading_scan + `:Markdown list headings`:
--   * ATX headings are extracted with level/title/lnum.
--   * Frontmatter and fenced code blocks are skipped.
--   * `list` is registered as a gateable feature and a `:Markdown` subcommand,
--     and its completion offers the options first, then the scope vocabulary.

return function(H)
  local eq, ok = H.eq, H.ok
  local scan = require("markdown.core.heading_scan")

  -- Levels, titles and 1-based line numbers.
  local hs = scan.from_lines({
    "# One", -- 1
    "text", -- 2
    "## Two", -- 3
    "###### Six", -- 4
    "####### Seven", -- 5: 7 hashes is not a heading
    "#NoSpace", -- 6: needs whitespace after the hashes
  })
  eq(#hs, 3, "from_lines: three valid ATX headings")
  eq(hs[1].level, 1, "from_lines: first heading is level 1")
  eq(hs[1].title, "One", "from_lines: title has the hashes stripped")
  eq(hs[1].lnum, 1, "from_lines: lnum is 1-based")
  eq(hs[2].level, 2, "from_lines: second heading is level 2")
  eq(hs[2].lnum, 3, "from_lines: lnum tracks the source line")
  eq(hs[3].level, 6, "from_lines: level 6 is still a heading")

  -- Frontmatter is document metadata, not structure.
  local fm = scan.from_lines({
    "---", -- 1
    "# not-real", -- 2: inside frontmatter
    "---", -- 3
    "# Real", -- 4
  })
  eq(#fm, 1, "from_lines: headings inside frontmatter are skipped")
  eq(fm[1].title, "Real", "from_lines: the post-frontmatter heading survives")
  eq(fm[1].lnum, 4, "from_lines: lnum still counts frontmatter lines")

  -- A `#` line inside a fence is a shell comment, not a heading.
  local fenced = scan.from_lines({
    "# Before", -- 1
    "```sh", -- 2
    "# a comment", -- 3
    "```", -- 4
    "# After", -- 5
  })
  eq(#fenced, 2, "from_lines: fenced-code `#` lines are skipped")
  eq(fenced[1].title, "Before", "from_lines: heading before the fence kept")
  eq(fenced[2].title, "After", "from_lines: heading after the fence kept")

  -- from_buffer reads the current buffer contents.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Buf", "body", "## Sub" })
  local from_buf = scan.from_buffer(buf)
  eq(#from_buf, 2, "from_buffer: extracts the buffer's headings")
  ok(from_buf[1].file == nil, "from_buffer: buffer-scope headings carry no file")

  -- from_file tags each heading with its source path; an unreadable path is
  -- an empty result, not an error.
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile({ "# Filed", "## Nested" }, tmp)
  local from_file = scan.from_file(tmp)
  eq(#from_file, 2, "from_file: extracts the file's headings")
  eq(from_file[1].file, tmp, "from_file: headings are tagged with their path")
  vim.fn.delete(tmp)
  eq(#scan.from_file(tmp .. ".missing"), 0, "from_file: unreadable path yields no headings")

  -- `list` is gateable and wired into the dispatcher.
  local config = require("markdown.config")
  config.setup({})
  ok(vim.tbl_contains(config.features(), "list"), "config: 'list' is a gateable feature")
  ok(config.feature_enabled("list"), "config: 'list' is on by default")
  config.setup({ features = { just_enable = { "toc" } } })
  ok(not config.feature_enabled("list"), "config: 'list' respects just_enable gating")
  config.setup({})

  local cmds = require("markdown.commands")
  ok(
    vim.tbl_contains(cmds.complete("", "Markdown "), "list"),
    "commands: 'list' offered by :Markdown completion"
  )

  -- Completion: options on the first argument, scopes on the second.
  local list = require("markdown.commands.list")
  ok(
    vim.tbl_contains(list.complete("", "Markdown list "), "headings"),
    "list.complete: offers 'headings' as an option"
  )
  local scopes = list.complete("", "Markdown list headings ")
  ok(vim.tbl_contains(scopes, "cwd"), "list.complete: offers 'cwd' as a scope")
  ok(vim.tbl_contains(scopes, "%"), "list.complete: offers '%' as a scope")
  ok(
    not vim.tbl_contains(scopes, "headings"),
    "list.complete: the option is not re-offered in scope position"
  )
end
