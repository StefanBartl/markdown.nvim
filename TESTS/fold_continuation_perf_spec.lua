-- TESTS/fold_continuation_perf_spec.lua -- the continuation-row foldexpr stays linear.
-- Regression: is_table_continuation_line collected the table block from its first line down
-- to `lnum` on every call (prepending each line), and the fold level scanned upwards for the
-- heading on every continuation row, so a full fold pass over an N-row table cost O(N^2)
-- buffer lines (O(N^3) work). The block's delimiter row and heading level are now computed
-- once per block and changedtick; this pins the number of buffer lines a pass may fetch.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local fold = require("markdown.core.fold")

  local n = 2000
  local lines = { "# H", "", "| A | B |", "|---|---|" }
  for i = 1, n do
    lines[#lines + 1] = (i % 2 == 1) and ("| x" .. i .. " | y |") or "| | more |"
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].mdtable_fold_continuations = true

  -- Count every buffer line foldexpr fetches during one full pass.
  local orig = api.nvim_buf_get_lines
  local fetched = 0
  api.nvim_buf_get_lines = function(...)
    local got = orig(...)
    fetched = fetched + #got
    return got
  end
  local levels = {}
  local okpass, err = pcall(function()
    for lnum = 1, #lines do
      levels[lnum] = tostring(fold.foldexpr(lnum))
    end
  end)
  api.nvim_buf_get_lines = orig
  ok(okpass, "the fold pass runs: " .. tostring(err))

  -- Linear: a handful of lines per buffer line (the old code fetched ~N^2/2 = 2,000,000).
  local bound = 10 * #lines
  ok(
    fetched <= bound,
    ("a full fold pass fetches %d buffer lines (bound %d)"):format(fetched, bound)
  )

  -- And the pass still folds what it should.
  eq(levels[1], ">1", "the heading opens its section")
  eq(levels[5], "=", "the first data row is no continuation")
  eq(levels[6], ">2", "a continuation row folds one level under the heading")
  eq(levels[7], "=", "a data row is no continuation")
  eq(levels[#lines], ">2", "the last continuation row folds too")

  -- The cache follows the buffer: an edit (new changedtick) is seen by the next call.
  api.nvim_buf_set_lines(buf, 2, 4, false, { "| A | B |", "| C | D |" })
  eq(tostring(fold.foldexpr(6)), "=", "without a delimiter row nothing continues")
  api.nvim_buf_set_lines(buf, 0, 4, false, { "## H", "", "| A | B |", "|---|---|" })
  eq(tostring(fold.foldexpr(6)), ">3", "the restored table folds under the new heading level")

  -- Each table block has its own heading level and delimiter row.
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "| A | B |",
    "|---|---|",
    "| x | y |",
    "| | z |",
    "## S",
    "| A | B |",
    "| C | D |",
    "|---|---|",
    "| x | y |",
    "| | z |",
  })
  eq(tostring(fold.foldexpr(4)), ">1", "no heading above the first table: level 1")
  eq(tostring(fold.foldexpr(10)), ">3", "the second table folds under its `## S`")
  eq(tostring(fold.foldexpr(9)), "=", "its first data row sits under its own delimiter row")

  -- Two buffers in turn do not share the cached block.
  local other = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(other, 0, -1, false, { "| A | B |", "| C | D |", "| x | y |", "| | z |" })
  vim.b[other].mdtable_fold_continuations = true
  api.nvim_set_current_buf(other)
  eq(tostring(fold.foldexpr(4)), "=", "a table without a delimiter row in the other buffer")
  api.nvim_set_current_buf(buf)
  eq(tostring(fold.foldexpr(4)), ">1", "and the first buffer is still judged on its own")

  vim.b[buf].mdtable_fold_continuations = nil
  api.nvim_buf_delete(other, { force = true })
  api.nvim_buf_delete(buf, { force = true })
end
