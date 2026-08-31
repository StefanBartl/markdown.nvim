-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- docs/TESTS/handler_spec.lua — cursor-action handler: silent mode for mouse
-- invocation (a "no target" miss should not notify when triggered by the mouse).
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq

  -- Stub util.notify to record calls without depending on lib.nvim/vim.notify.
  package.loaded["markdown.util.notify"] = nil
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
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "just plain prose, no links or targets here" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  handler.handle_cursor_action({ silent = true })
  eq(#calls, 0, "silent mode: no notification on a miss")

  handler.handle_cursor_action()
  eq(#calls, 1, "default mode: one notification on a miss")
  eq(calls[1].level, "info", "miss notification is info-level")

  -- A plain `[text](target)` link is not an image (regression: the fallback
  -- pattern in handler/image.lua used to match ANY markdown link, not just
  -- `![alt](src)`, so every link was misclassified as an image and opened
  -- externally instead of via :edit).
  do
    local image = require("markdown.handler.image")
    eq(
      image.is_image_line("[Review answer](C:/repos/foo/bar.md)"),
      false,
      "plain link is not an image"
    )
    eq(
      image.is_image_line("![alt](C:/repos/foo/pic.png)"),
      true,
      "real image syntax still recognized"
    )
  end

  -- A Windows drive-letter absolute path (`C:/…`) is a file target, not a
  -- URI scheme (regression: `^%w[%w+.-]*:` matched `C:` the same as `http:`).
  do
    local is_extern = require("markdown.anchor.is_html_extern_anchor_line")
    local extern = is_extern("[Review answer](C:/repos/foo/bar.md)")
    eq(type(extern), "table", "drive-letter path recognized as a file target")
    eq(extern.target, "C:/repos/foo/bar.md", "extracted target unchanged")

    -- Real URI schemes must still be rejected (not treated as file targets).
    eq(is_extern("[mail](mailto:foo@bar.com)"), nil, "mailto: still rejected")
    eq(is_extern("[site](http://example.com)"), nil, "http: still rejected")
  end

  -- End-to-end: double-clicking a `[text](C:/…)` link opens the target via
  -- :edit in the current window, never via the system's default application.
  do
    package.loaded["markdown.handler"] = nil
    local h2 = require("markdown.handler")

    local target = vim.fn.tempname() .. "_mdnvim_target.md"
    local fh = io.open(target, "w")
    if fh then
      fh:write("# target")
      fh:close()
    end
    local target_slash = (target:gsub("\\", "/"))
    -- Force a drive-letter-style prefix regardless of host OS so the
    -- regression (Windows-only) is exercised everywhere the suite runs.
    local drive_target = target_slash:match("^%a:/") and target_slash or ("C:" .. target_slash)

    local system_opened = nil
    local orig_ui_open = vim.ui.open
    vim.ui.open = function(p)
      system_opened = p
      return true, nil
    end

    local run_ok, run_err = pcall(function()
      local buf = H.scratch("markdown")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "[Review answer](" .. drive_target .. ")" })
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      h2.handle_cursor_action({ silent = true, mouse = true })
    end)

    vim.ui.open = orig_ui_open
    pcall(vim.fn.delete, target)

    if not run_ok then error(run_err, 0) end
    eq(system_opened, nil, "drive-letter .md link opens via :edit, not the system app")
    eq(vim.api.nvim_buf_get_name(0), target, "current buffer is the linked file")
  end

  -- Restore the real notify module so later specs (if any run after this one
  -- in the same process) are unaffected.
  package.loaded["markdown.util.notify"] = nil
  package.loaded["markdown.handler"] = nil
end
