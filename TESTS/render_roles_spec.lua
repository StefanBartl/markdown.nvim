-- TESTS/render_roles_spec.lua -- the roles of a buffer are worked out again only from the first changed row on, and the
-- result is the one a full read gives. A property check over random edits, plus the fence that stays open across an edit.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local r = require("markdown.core.render")

  local pool = {
    "text",
    "",
    "```",
    "```lua",
    "~~~",
    "````",
    "- item",
    "# Title",
    "> quote",
    "---",
    "    code",
    "$$",
    "$$ x = 1",
    "a + b $$",
    "$$x$$",
    "<!-- c",
    "d -->",
  }
  local function same(a, b)
    local keys = {}
    for k in pairs(a) do
      keys[k] = true
    end
    for k in pairs(b) do
      keys[k] = true
    end
    for k in pairs(keys) do
      if a[k] ~= b[k] then return false, k end
    end
    return true
  end

  math.randomseed(20261019)
  for iter = 1, 300 do
    local lines = {}
    for i = 1, math.random(1, 40) do
      lines[i] = pool[math.random(#pool)]
    end
    local roles, langs = r.roles(lines)
    -- an edit at row `first`: the lines from there on change (no front matter involved: row 1 is never edited)
    if #lines >= 2 then
      local first = math.random(2, #lines)
      local edited = vim.deepcopy(lines)
      for i = first, #edited do
        edited[i] = nil
      end
      for i = first, first + math.random(0, 8) do
        edited[i] = pool[math.random(#pool)]
      end
      local front = 0
      for row, role in pairs(roles) do
        if role == "front" then front = math.max(front, row) end
      end
      if first > front and not (lines[1] and lines[1]:match("^%-%-%-%s*$")) then
        local open_row = r._open_fence_row(roles, first)
        local tail = {}
        for i = first, #edited do
          tail[#tail + 1] = edited[i]
        end
        r.roles_after(
          roles,
          langs,
          first,
          tail,
          open_row and lines[open_row] or nil,
          r._comment_open(roles, first),
          r._math_open(roles, first)
        )
        local want_roles, want_langs = r.roles(edited)
        local equal, at = same(roles, want_roles)
        ok(equal, ("iteration %d: roles differ at row %s"):format(iter, tostring(at)))
        equal, at = same(langs, want_langs)
        ok(equal, ("iteration %d: langs differ at row %s"):format(iter, tostring(at)))
      end
    end
  end

  -- a fence open above the edit stays open into it
  local roles, langs = r.roles({ "text", "```lua", "code", "more", "```", "after" })
  eq(r._open_fence_row(roles, 4), 2, "the open fence above row 4 is the one on row 2")
  eq(r._open_fence_row(roles, 6), nil, "no fence is open after the closing one")
  eq(r._open_fence_row(roles, 2), nil, "and none above row 2")
  r.roles_after(roles, langs, 4, { "still code", "```", "after" }, "```lua")
  eq(roles[4], "in", "the edited row is still inside the fence")
  eq(roles[5], "close", "and the next fence line closes it")
  eq(langs[2], "lua", "the language of the opening line is kept")

  -- the buffer side: an edit at the end is drawn with the roles worked out from there on
  local buf = H.scratch("markdown")
  local lines = {}
  for i = 1, 30 do
    lines[i] = (i == 5 and "```") or (i == 9 and "```") or "line " .. i
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  r.enable(buf)
  r.refresh(buf, true)
  vim.api.nvim_buf_set_lines(buf, 29, 30, false, { "```", "tail" })
  r.refresh(buf)
  local ns = vim.api.nvim_create_namespace("markdown_render")
  local function code_bg(row)
    for _, m in
      ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true }))
    do
      if m[4].line_hl_group == "MarkdownRenderCodeBg" then return true end
    end
    return false
  end
  ok(code_bg(30), "the row behind the fence that the edit opened is code")
  ok(not code_bg(3), "a row of the plain text above is not")
  ok(code_bg(5), "and the fence that was there before is still code")
  -- closing the fence again: the row is plain text once more
  vim.api.nvim_buf_set_lines(buf, 29, 31, false, { "line 30" })
  r.refresh(buf)
  ok(not code_bg(29), "after the edit that removed the fence the last row is plain text")
  r.disable(buf)

  -- enable / disable / enable without an edit in between attaches the buffer once, not once per cycle
  do
    local b = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "a", "b" })
    local before = r._attach_count
    for _ = 1, 3 do
      r.enable(b)
      r.disable(b)
    end
    r.enable(b)
    eq(r._attach_count - before, 1, "one attach for four enables")
    vim.api.nvim_buf_set_lines(b, 1, 2, false, { "x" })
    r.refresh(b)
    r.disable(b)
    -- an edit while disabled detaches it; the next enable attaches again
    vim.api.nvim_buf_set_lines(b, 1, 2, false, { "y" })
    r.enable(b)
    eq(r._attach_count - before, 2, "attached again after the callback went")
    r.disable(b)
  end
end
