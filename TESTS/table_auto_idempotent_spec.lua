-- TESTS/table_auto_idempotent_spec.lua -- `table format auto` is a fixed point after one pass:
-- the column plan comes from the unwrapped content, not from already wrapped widths.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local mdtable = require("markdown.commands.mdtable")

  local function open(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    return buf
  end

  local function get(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end

  local buf = open({
    "| Syntax | Meaning | Example |",
    "|---|---|---|",
    "| `a` | stdout of the left command becomes stdin of the right one and more words here | `ls` |",
    "| `b` | short | `npx vitest run --reporter verbose --bail --coverage --watch` |",
  })
  vim.api.nvim_win_set_width(0, 50)

  local ok1 = mdtable.format_at_cursor(buf, { auto = true })
  eq(ok1, true, "first auto format succeeds")
  local first = get(buf)
  for pass = 2, 4 do
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    mdtable.format_at_cursor(buf, { auto = true })
    eq(
      table.concat(get(buf), "|"),
      table.concat(first, "|"),
      "auto format pass " .. pass .. " leaves the table unchanged"
    )
  end
end
