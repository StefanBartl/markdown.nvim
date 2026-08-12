-- TESTS/anchor_jump_spec.lua — markdown.anchor.jump: successful jumps, the
-- "no anchor under cursor" miss, the "anchor doesn't resolve to any heading"
-- miss, and duplicate-slug disambiguation (`#note`, `#note-1`, ...).
--
-- Regression coverage for the fix where a clean "not found" result was
-- indistinguishable from success: `M.jump()` checked pcall's own ok-flag
-- instead of `jump_to_anchor`'s returned boolean, so a real miss gave no
-- feedback at all.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local api = vim.api

  --- Fresh `markdown.anchor.jump` wired to a notify stub that records calls
  --- instead of depending on lib.nvim/vim.notify.
  ---@return table jump the freshly required module
  ---@return { level: string, msg: string }[] calls
  local function fresh_jump()
    package.loaded["markdown.util.notify"] = nil
    package.loaded["markdown.anchor.jump"] = nil
    local calls = {}
    package.loaded["markdown.util.notify"] = {
      create = function()
        return {
          info = function(msg) calls[#calls + 1] = { level = "info", msg = msg } end,
          warn = function(msg) calls[#calls + 1] = { level = "warn", msg = msg } end,
          error = function(msg) calls[#calls + 1] = { level = "error", msg = msg } end,
          debug = function() end,
        }
      end,
    }
    return require("markdown.anchor.jump"), calls
  end

  -- ---- successful jump: no notification on a hit ---------------------------
  do
    local jump, calls = fresh_jump()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Title",
      "",
      "## Section One",
      "",
      "See [Section One](#section-one) for details.",
    })
    api.nvim_win_set_cursor(0, { 5, 5 })
    jump.jump()
    eq(api.nvim_win_get_cursor(0)[1], 3, "cursor lands on the matching heading")
    eq(#calls, 0, "a successful jump notifies nothing")
  end

  -- ---- no anchor under cursor -----------------------------------------------
  do
    local jump, calls = fresh_jump()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "just plain prose, no anchor here" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    jump.jump()
    eq(api.nvim_win_get_cursor(0)[1], 1, "cursor does not move")
    eq(#calls, 1, "one notification for the miss")
    eq(calls[1].level, "info", "no-anchor miss is info-level")
    eq(calls[1].msg, "No anchor found under cursor")
  end

  -- ---- anchor present, but no heading resolves it ---------------------------
  -- The regression case: pcall's ok-flag (true — jump_to_anchor raised no
  -- error) used to be conflated with a found/not-found result, so this case
  -- silently did nothing. It must now surface a distinct info notification.
  do
    local jump, calls = fresh_jump()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Title",
      "",
      "See [Missing](#does-not-exist) for details.",
    })
    api.nvim_win_set_cursor(0, { 3, 5 })
    jump.jump()
    eq(api.nvim_win_get_cursor(0)[1], 3, "cursor does not move on a clean miss")
    eq(#calls, 1, "one notification for the unresolved anchor")
    eq(calls[1].level, "info", "unresolved-anchor miss is info-level, not a warning")
    eq(calls[1].msg, "No heading found for anchor: does-not-exist")
  end

  -- ---- duplicate heading slugs: base / -1 / -2 disambiguation ---------------
  do
    local jump, calls = fresh_jump()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Title",
      "## Note", -- -> #note
      "## Note", -- -> #note-1
      "## Note", -- -> #note-2
      "",
      "[first](#note)",
      "[second](#note-1)",
      "[third](#note-2)",
    })

    api.nvim_win_set_cursor(0, { 6, 2 })
    jump.jump()
    eq(api.nvim_win_get_cursor(0)[1], 2, "#note resolves to the first occurrence")

    api.nvim_win_set_cursor(0, { 7, 2 })
    jump.jump()
    eq(api.nvim_win_get_cursor(0)[1], 3, "#note-1 resolves to the second occurrence")

    api.nvim_win_set_cursor(0, { 8, 2 })
    jump.jump()
    eq(api.nvim_win_get_cursor(0)[1], 4, "#note-2 resolves to the third occurrence")

    eq(#calls, 0, "all three duplicate-slug jumps succeed without notifying")
  end

  -- ---- end-to-end: a TOC-style list entry double-clicked via the handler ----
  -- The bug this suite was added for: a plain TOC line
  -- `- [Title](#anchor)` must route to anchor.jump(), not fall through to
  -- image/link handling.
  do
    package.loaded["markdown.util.notify"] = nil
    package.loaded["markdown.anchor.jump"] = nil
    package.loaded["markdown.handler"] = nil
    local calls = {}
    package.loaded["markdown.util.notify"] = {
      create = function()
        return {
          info = function(msg) calls[#calls + 1] = { level = "info", msg = msg } end,
          warn = function(msg) calls[#calls + 1] = { level = "warn", msg = msg } end,
          error = function(msg) calls[#calls + 1] = { level = "error", msg = msg } end,
          debug = function() end,
        }
      end,
    }
    local handler = require("markdown.handler")

    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "## 2.2 Public API surface",
      "",
      "- [2.2 Public API surface](#22-public-api-surface)",
    })
    api.nvim_win_set_cursor(0, { 3, 5 })
    handler.handle_cursor_action({ silent = true, mouse = true })
    eq(api.nvim_win_get_cursor(0)[1], 1, "TOC entry double-click jumps to its heading")
    eq(#calls, 0, "the hit notifies nothing")

    package.loaded["markdown.handler"] = nil
  end

  package.loaded["markdown.util.notify"] = nil
  package.loaded["markdown.anchor.jump"] = nil
end
