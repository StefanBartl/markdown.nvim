-- TESTS/render_screen_spec.lua -- the native rendering on a REAL screen (embedded Neovim via
-- testing.rpc): what the user sees, the cursor row, edits, scrolling in a long file, disable.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok

  local function root_of(file, up)
    local f = vim.api.nvim_get_runtime_file(file, false)[1]
    assert(f, "not on the runtimepath: " .. file)
    f = vim.fs.normalize(f)
    for _ = 1, up do
      f = vim.fs.dirname(f)
    end
    return f
  end
  local rpc = require("testing.rpc")
  local RTP = {
    root_of("lua/markdown/core/render.lua", 4),
    root_of("lua/lib/nvim", 3),
    root_of("lua/testing/rpc/init.lua", 4),
  }
  local c, err = rpc.spawn({ guard = false, rtp_prepend = RTP })
  assert(c, err)

  local function screen()
    local out = {}
    for i, l in ipairs(c.screen().lines) do
      out[i] = (l:gsub("%s+$", ""))
    end
    return out
  end

  local DOC = {
    "# Heading one",
    "## Two",
    "",
    "- item a",
    "  - nested",
    "- [ ] todo",
    "- [x] done",
    "",
    "> quote text",
    "> [!NOTE] Title",
    "",
    "---",
    "",
    "text with `code` and [link](http://x) and ![img](a.png)",
    "",
    "last line",
  }

  local function load(lines, cursor)
    c.lua(
      [[
      local lines, cursor = ...
      vim.cmd("only")
      local old = vim.api.nvim_get_current_buf()
      pcall(require("markdown.core.render").disable, old)
      vim.cmd("silent! enew!")
      vim.cmd("silent! bwipeout! " .. old)
      vim.o.swapfile = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = "markdown"
      vim.wo.conceallevel = 0
      vim.api.nvim_win_set_cursor(0, { cursor, 0 })
      require("markdown.core.render").enable(0)
    ]],
      lines,
      cursor
    )
    c.settle(500)
  end

  load(DOC, #DOC)
  local sc = screen()
  eq(sc[1], "◉ Heading one", "H1: icon instead of the hash")
  eq(sc[2], "○ Two", "H2")
  eq(sc[4], "• item a", "bullet")
  eq(sc[5], "  ◦ nested", "nested bullet")
  ok(vim.startswith(vim.trim(sc[6]), "☐ todo"), "unchecked checkbox: " .. sc[6])
  ok(vim.startswith(vim.trim(sc[7]), "☑ done"), "checked checkbox: " .. sc[7])
  eq(sc[9], "▎ quote text", "quote marker")
  ok(sc[10]:find("ⓘ Note", 1, true), "callout label: " .. sc[10])
  ok(
    vim.fn.strchars(sc[12]) >= 60 and not sc[12]:find("-", 1, true),
    "thematic break is a line: " .. sc[12]
  )
  ok(sc[14]:find("text with code and link and", 1, true), "inline markup is concealed: " .. sc[14])
  ok(not sc[14]:find("http://x", 1, true), "the url is hidden")
  eq(sc[16], "last line", "the cursor row is plain text")

  -- the cursor row shows the raw text, the row it left is drawn again
  c.feed("1G")
  c.settle(300)
  sc = screen()
  eq(sc[1], "# Heading one", "cursor on the heading: raw text")
  c.feed("2G")
  c.settle(300)
  sc = screen()
  eq(sc[1], "◉ Heading one", "and drawn again after the cursor left")
  eq(sc[2], "## Two", "the new cursor row is raw")

  -- an edit is drawn after the debounce
  c.feed("Gofoo<Esc>")
  c.feed("kkk")
  c.cmd("sleep 200m")
  c.settle(500)
  eq(c.lua_get("vim.api.nvim_buf_get_lines(0, -2, -1, false)[1]"), "foo", "text typed")
  c.feed("ggO# New<Esc>jj")
  c.cmd("sleep 200m")
  c.settle(500)
  sc = screen()
  eq(sc[1], "◉ New", "the new heading is drawn after the edit")

  -- a long file: scrolling to the end draws the rows there
  local long = {}
  for i = 1, 2000 do
    long[i] = "# Head " .. i
  end
  load(long, 1)
  eq(screen()[2], "◉ Head 2", "top of a long file")
  c.feed("G")
  c.cmd("sleep 200m")
  c.settle(500)
  local last = screen()
  local found
  for _, l in ipairs(last) do
    if l:find("◉ Head 199", 1, true) then found = true end
  end
  ok(found, "after jumping to the end the rows there are drawn")
  local marks = c.lua_get(
    "#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('markdown_render'), 0, -1, {})"
  )
  ok(marks < 1200, "far fewer marks than rows in a 2000-line file (" .. marks .. ")")

  -- disable gives everything back
  c.lua("require('markdown.core.render').disable(0)")
  c.settle(300)
  eq(c.lua_get("vim.wo.conceallevel"), 0, "conceallevel is back")
  ok(not screen()[1]:find("◉", 1, true), "plain text again")

  c.kill()
end
