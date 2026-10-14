-- TESTS/render_command_spec.lua -- `:Markdown render` drives the native renderer (core.render) and
-- the table grid for the current buffer; no host plugin is involved any more.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local render = require("markdown.commands.render")
  local native = require("markdown.core.render")
  local tables = require("markdown.core.table_render")

  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# T", "", "| a |", "| - |", "| 1 |", "", "x" })
  vim.api.nvim_win_set_cursor(0, { 7, 0 })

  render.run({ "on" })
  ok(native.is_enabled(buf), "on: native rendering is on")
  ok(tables.is_enabled(buf), "on: the table grid is on too")
  render.run({ "off" })
  ok(not native.is_enabled(buf) and not tables.is_enabled(buf), "off: both are off")
  render.run({})
  ok(native.is_enabled(buf), "no argument toggles on")
  render.run({ "toggle" })
  ok(not native.is_enabled(buf), "toggle goes off again")
  render.run({ "ON" })
  ok(native.is_enabled(buf), "the case does not matter")

  -- an invalid argument changes nothing
  render.run({ "bogus" })
  ok(native.is_enabled(buf), "an invalid argument leaves the state")
  render.run({ "off" })

  -- the table rows belong to the grid: `on` leaves no inline marks on them
  local ns = vim.api.nvim_create_namespace("markdown_render")
  local tb = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(
    tb,
    0,
    -1,
    false,
    { "| `a` | [b](u) |", "| - | - |", "| 1 | 2 |", "", "x" }
  )
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  render.run({ "on" })
  eq(#vim.api.nvim_buf_get_extmarks(tb, ns, 0, -1, {}), 0, "on: the grid owns the table rows")
  render.run({ "off" })
  -- a grid switched on later takes the rows over from a renderer that already drew them
  native.enable(tb)
  ok(
    #vim.api.nvim_buf_get_extmarks(tb, ns, 0, -1, {}) > 0,
    "without a grid the rows get inline marks"
  )
  tables.enable(tb)
  ok(
    vim.wait(1000, function() return #vim.api.nvim_buf_get_extmarks(tb, ns, 0, -1, {}) == 0 end, 20),
    "the grid switched on later removes them"
  )
  tables.disable(tb)
  ok(
    vim.wait(1000, function() return #vim.api.nvim_buf_get_extmarks(tb, ns, 0, -1, {}) > 0 end, 20),
    "and switched off gives them back"
  )
  native.disable(tb)

  eq(table.concat(render.complete("t"), ","), "toggle", "completes toggle")
  eq(#render.complete(""), 3, "completes on / off / toggle")
end
