-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/handler_pdf_spec.lua — PDF targets: system-app/pdfport.nvim choice.
--
-- `.pdf` targets get their own opener (markdown.handler.file.open_pdf):
--   * pdfport.nvim not installed -> open with the system app directly, no
--     prompt (there is no in-nvim alternative to offer).
--   * pdfport.nvim installed     -> ask via markdown.util.picker; "pdfport"
--     renders into a new buffer via pdfport.open({ mode = "buffer" }),
--     "System app" falls through to the same system opener as any other
--     external extension.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq

  local function reset()
    package.loaded["markdown.handler.file"] = nil
    package.loaded["pdfport"] = nil
    package.loaded["markdown.util.picker"] = nil
  end

  -- Case 1: pdfport.nvim not installed -> straight to the system opener.
  do
    reset()
    local system_opened = nil
    local orig_ui_open = vim.ui.open
    -- A test double over typed `vim.ui` surface: replacing the field is the
    -- point of the case, not a second definition of it.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.open = function(p)
      system_opened = p
      return true, nil
    end

    local ok_run, err_run = pcall(function()
      local file = require("markdown.handler.file")
      local ok = file.open_pdf("C:/docs/report.pdf")
      eq(ok, true, "open_pdf reports success")
    end)

    vim.ui.open = orig_ui_open
    if not ok_run then error(err_run, 0) end
    eq(
      system_opened,
      "C:/docs/report.pdf",
      "no pdfport.nvim -> opened via the system app, no prompt"
    )
  end

  -- Case 2: pdfport.nvim installed, user picks "pdfport (new buffer)".
  do
    reset()
    local pdfport_opened = nil
    package.loaded["pdfport"] = {
      open = function(opts) pdfport_opened = opts end,
    }
    package.loaded["markdown.util.picker"] = {
      select = function(items, opts, on_choose)
        eq(opts.prompt, "Open PDF with:", "picker prompt describes the choice")
        on_choose(items[2])
      end,
    }

    local file = require("markdown.handler.file")
    file.open_pdf("C:/docs/report.pdf")

    eq(type(pdfport_opened), "table", "pdfport.open called")
    ---@cast pdfport_opened table
    eq(pdfport_opened.path, "C:/docs/report.pdf", "pdfport.open gets the resolved path")
    eq(pdfport_opened.mode, "buffer", "pdfport renders into a new buffer (its own fallback chain)")
  end

  -- Case 3: pdfport.nvim installed, user picks "System app" instead.
  do
    reset()
    package.loaded["pdfport"] = {
      open = function() error("pdfport.open must not be called when 'System app' is chosen") end,
    }
    package.loaded["markdown.util.picker"] = {
      select = function(items, _opts, on_choose) on_choose(items[1]) end,
    }

    local system_opened = nil
    local orig_ui_open = vim.ui.open
    -- A test double over typed `vim.ui` surface: replacing the field is the
    -- point of the case, not a second definition of it.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.open = function(p)
      system_opened = p
      return true, nil
    end

    local ok_run, err_run = pcall(function()
      local file = require("markdown.handler.file")
      file.open_pdf("C:/docs/report.pdf")
    end)

    vim.ui.open = orig_ui_open
    if not ok_run then error(err_run, 0) end
    eq(system_opened, "C:/docs/report.pdf", "'System app' choice still opens via the system app")
  end

  reset()
end
