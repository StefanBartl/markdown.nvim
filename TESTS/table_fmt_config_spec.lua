-- TESTS/table_fmt_config_spec.lua — config.table (header_align/entry_align/
-- col_overrides) supplies defaults for core.table_fmt, overridable per call.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("markdown.config")
  local tf = require("markdown.core.table_fmt")

  config.setup({})

  local function fresh_table(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "| Name | Age |",
      "|---|---|",
      "| Bob | 3 |",
      "| Alice | 40 |",
    })
  end

  -- Default (no config override, no opts): center alignment both roles.
  do
    local buf = H.scratch("markdown")
    fresh_table(buf)
    local okf, err = tf.format_table_at_cursor(buf, {})
    eq(okf, true, "format ok (" .. tostring(err) .. ")")
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- centered "Bob" has padding on both sides within its column width.
    ok(out[3]:match("^| %s*Bob%s* |") ~= nil, "default center alignment")
  end

  -- config.table.header_align/entry_align supply defaults when opts don't override.
  config.setup({ table = { header_align = "left", entry_align = "left" } })
  do
    local buf = H.scratch("markdown")
    fresh_table(buf)
    tf.format_table_at_cursor(buf, {})
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(out[1]:match("^| Name%s* |") ~= nil, "config header_align=left applied to header")
    ok(out[3]:match("^| Bob%s* |") ~= nil, "config entry_align=left applied to body")
  end

  -- Explicit opts still win over config defaults.
  config.setup({ table = { header_align = "left", entry_align = "left" } })
  do
    local buf = H.scratch("markdown")
    fresh_table(buf)
    tf.format_table_at_cursor(buf, { header_align = "right", entry_align = "right" })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(
      out[1]:match("Name%s* |$") == nil or out[1]:match("%s+Name |$") ~= nil,
      "explicit opts override config for header"
    )
  end

  -- config.table.col_overrides applies when the caller passes none.
  config.setup({
    table = {
      header_align = "center",
      entry_align = "center",
      col_overrides = { { col = "Name", align = "left" } },
    },
  })
  do
    local buf = H.scratch("markdown")
    fresh_table(buf)
    tf.format_tables_in_buffer(buf, {})
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ok(out[3]:match("^| Bob%s+ |") ~= nil, "config col_overrides left-aligns the Name column")
  end

  config.setup({})
end
