-- docs/TESTS/handler_spec.lua — cursor-action handler: silent mode for mouse
-- invocation (a "no target" miss should not notify when triggered by the mouse).
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq

  -- Stub util.notify to record calls without depending on lib.nvim/vim.notify.
  package.loaded["markdown_nvim.util.notify"] = nil
  package.loaded["markdown_nvim.handler"] = nil
  local calls = {}
  package.loaded["markdown_nvim.util.notify"] = {
    create = function()
      return {
        info = function(msg) calls[#calls + 1] = { level = "info", msg = msg } end,
        warn = function(msg) calls[#calls + 1] = { level = "warn", msg = msg } end,
        error = function(msg) calls[#calls + 1] = { level = "error", msg = msg } end,
        debug = function() end,
      }
    end,
  }
  local handler = require("markdown_nvim.handler")

  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "just plain prose, no links or targets here" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  handler.handle_cursor_action({ silent = true })
  eq(#calls, 0, "silent mode: no notification on a miss")

  handler.handle_cursor_action()
  eq(#calls, 1, "default mode: one notification on a miss")
  eq(calls[1].level, "info", "miss notification is info-level")

  -- Restore the real notify module so later specs (if any run after this one
  -- in the same process) are unaffected.
  package.loaded["markdown_nvim.util.notify"] = nil
  package.loaded["markdown_nvim.handler"] = nil
end
