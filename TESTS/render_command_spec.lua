-- TESTS/render_command_spec.lua -- `:Markdown render` drives render-markdown.nvim and warns when
-- it is missing. The plugin is faked by a `:RenderMarkdown` user command.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok

  -- not installed: no error, no command run
  local warned = false
  local notify_mod = require("markdown.util.notify")
  local saved_create = notify_mod.create
  ---@diagnostic disable-next-line: duplicate-set-field
  notify_mod.create = function(...)
    local n = saved_create(...)
    return setmetatable({
      warn = function() warned = true end,
    }, { __index = n })
  end
  package.loaded["markdown.commands.render"] = nil
  local render_missing = require("markdown.commands.render")
  eq(vim.fn.exists(":RenderMarkdown"), 0, "the host plugin is not loaded in the spec")
  render_missing.run({ "on" })
  ok(warned, "a missing render-markdown.nvim only warns")
  notify_mod.create = saved_create
  package.loaded["markdown.commands.render"] = nil
  local render = require("markdown.commands.render")

  -- installed (faked): on / off / toggle map to enable / disable / toggle
  local seen = {}
  vim.api.nvim_create_user_command("RenderMarkdown", function(o) seen[#seen + 1] = o.args end, {
    nargs = 1,
  })
  render.run({ "on" })
  render.run({ "off" })
  render.run({})
  render.run({ "toggle" })
  eq(table.concat(seen, ","), "enable,disable,toggle,toggle", "actions forwarded to the plugin")

  -- completion
  -- invalid argument: a warning, the plugin is not called; the case does not matter
  seen = {}
  render.run({ "bogus" })
  eq(#seen, 0, "an invalid argument does not reach the plugin")
  render.run({ "ON" })
  eq(seen[1], "enable", "ON is on")

  -- the plugin resets conceallevel; with the table grid on it is raised again
  vim.api.nvim_create_user_command(
    "RenderMarkdown",
    function() vim.wo.conceallevel = 0 end,
    { nargs = 1 }
  )
  local tr = require("markdown.core.table_render")
  local rbuf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, { "| a |", "| - |", "| 1 |", "", "x" })
  tr.enable(rbuf)
  render.run({ "off" })
  vim.wait(200, function() return vim.wo.conceallevel >= 2 end)
  ok(vim.wo.conceallevel >= 2, "conceallevel is raised again for the table grid")
  tr.disable(rbuf)

  eq(table.concat(render.complete("t"), ","), "toggle", "completes toggle")
  eq(#render.complete(""), 3, "completes on / off / toggle")
  vim.api.nvim_del_user_command("RenderMarkdown")
end
