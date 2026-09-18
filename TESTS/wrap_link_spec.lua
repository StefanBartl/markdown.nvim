-- TESTS/wrap_link_spec.lua — core.wrap_link: wrap the word under the cursor
-- (normal mode) or the visual selection into a Markdown link, choosing
-- `[](target)` vs `[text]()` by a URL/path heuristic.

return function(H)
  local eq = H.eq
  local api = vim.api
  local wrap_link = require("markdown.core.wrap_link")

  -- Normal mode: empty line under cursor -> bare template, cursor inside [].
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    wrap_link.wrap_normal()
    eq(api.nvim_buf_get_lines(buf, 0, -1, false)[1], "[]()", "wrap_normal: empty line -> [] ()")
    local cur = api.nvim_win_get_cursor(0)
    eq(cur[1], 1, "wrap_normal: cursor row unchanged")
    eq(cur[2], 1, "wrap_normal: cursor lands inside [ ]")
  end

  -- Normal mode: plain word -> [text](), cursor inside ().
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
    api.nvim_win_set_cursor(0, { 1, 2 }) -- inside "hello"
    wrap_link.wrap_normal()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "[hello]()",
      "wrap_normal: plain word -> [text]()"
    )
    eq(api.nvim_win_get_cursor(0)[2], 8, "wrap_normal: cursor lands inside ( )")
  end

  -- Normal mode: URL -> [](target), cursor inside [].
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "https://example.com/x" })
    api.nvim_win_set_cursor(0, { 1, 5 })
    wrap_link.wrap_normal()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "[](https://example.com/x)",
      "wrap_normal: URL -> [](target)"
    )
    eq(api.nvim_win_get_cursor(0)[2], 1, "wrap_normal: cursor lands inside [ ] for a URL")
  end

  -- Normal mode: mailto: -> target form. Word-boundary chars are
  -- filesystem/URL-safe (alnum, '_./:\-') and deliberately exclude '@', so
  -- the "word" under the cursor for a bare address is the "mailto:x" part;
  -- use an address-free scheme to check the heuristic branch directly.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "mailto:contact" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    wrap_link.wrap_normal()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "[](mailto:contact)",
      "wrap_normal: mailto: -> target form"
    )
  end

  -- Visual mode: an explicit selection is used verbatim (no word-boundary
  -- character class involved), so a full mailto address with '@' works too.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "mailto:x@example.com" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v19l") -- select all 20 chars (0-indexed cols 0..19)
    wrap_link.wrap_visual()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "[](mailto:x@example.com)",
      "wrap_visual: full mailto: address (with '@') -> target form"
    )
  end

  -- Normal mode: path-looking text (contains a separator) -> target form.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "docs/readme.md" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    wrap_link.wrap_normal()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "[](docs/readme.md)",
      "wrap_normal: path with '/' -> target form"
    )
  end

  -- Normal mode: bare "name.ext" shape (no separator) -> target form.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "image.png" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    wrap_link.wrap_normal()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "[](image.png)",
      "wrap_normal: 'name.ext' shape -> target form"
    )
  end

  -- Normal mode: word boundary detection only grabs the path-ish word under
  -- the cursor, not the surrounding prose.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "see hello world here" })
    api.nvim_win_set_cursor(0, { 1, 6 }) -- inside "hello"
    wrap_link.wrap_normal()
    eq(
      api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "see [hello]() world here",
      "wrap_normal: only the word under the cursor is wrapped"
    )
  end

  -- Visual mode (charwise): selection wrapped as plain text.
  -- wrap_visual reads the LIVE selection (mode() + getpos('v') + cursor), so
  -- it must be called while still in visual mode, not after leaving it.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "pick this word" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v3l") -- select "pick" (cols 0..3 inclusive)
    wrap_link.wrap_visual()
    local line = api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    eq(line, "[pick]() this word", "wrap_visual: charwise selection -> [text]()")
  end

  -- Visual mode: selecting a URL-looking span produces the target form.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "go https://x.test now" })
    api.nvim_win_set_cursor(0, { 1, 3 }) -- start of the URL
    vim.cmd("normal! v13l") -- select "https://x.test" (14 chars, 0-indexed span)
    wrap_link.wrap_visual()
    local line = api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    eq(line, "go [](https://x.test) now", "wrap_visual: URL-looking selection -> [](target)")
  end

  -- Visual mode: an all-whitespace selection drops the bare template.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "a    b" })
    api.nvim_win_set_cursor(0, { 1, 1 }) -- first space of the run
    vim.cmd("normal! v3l") -- select the 4 spaces
    wrap_link.wrap_visual()
    local line = api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    eq(line, "a[]()b", "wrap_visual: whitespace-only selection -> bare [] ()")
  end
end
