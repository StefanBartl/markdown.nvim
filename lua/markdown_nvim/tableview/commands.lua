---@module 'markdown_nvim.tableview.commands'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.tableview.commands]")

local M = {}

local api = vim.api
local create_user_command = api.nvim_buf_create_user_command
local ui = require("markdown_nvim.tableview.renderer")
local parser = require("markdown_nvim.tableview.parser")
local browser_view_basic = require("markdown_nvim.tableview.views.browser_basic")
local browser_view_niceified = require("markdown_nvim.tableview.views.browser_niceified")
local table_selector = require("markdown_nvim.tableview.views.table_selector")

function M.apply(ev)
  if type(ev) ~= "table" or type(ev.buf) ~= "number" then return end
  local bufnr = ev.buf
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)) then return end

  local ok, existing = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if ok and existing and existing["TableViewToggle"] then return end

  create_user_command(bufnr, "TableViewToggle", function(_)
    local line = api.nvim_win_get_cursor(0)[1]
    local tables = parser.get_tables(bufnr)
    local chosen = nil
    for _, t in ipairs(tables) do
      if t.start_line <= line and line <= (t.end_line or t.start_line) then
        chosen = t
        break
      end
    end
    if not chosen then
      notify.info("No table under cursor")
      return
    end
    ui.toggle_table(chosen, { floating = true })
  end, { desc = "[markdown.nvim] Toggle preview for table under cursor", nargs = 0 })

  create_user_command(bufnr, "TableViewSelect", function()
    local tables = parser.get_tables(bufnr)
    if #tables == 0 then
      notify.info("No tables found in buffer")
      return
    end
    if #tables == 1 then
      ui.render_table(tables[1], { floating = true })
      return
    end
    table_selector(tables)
  end, { desc = "[markdown.nvim] Select and preview table", nargs = 0 })

  create_user_command(bufnr, "TableViewClose", function()
    ui.close()
  end, { desc = "[markdown.nvim] Close persistent table preview", nargs = 0 })

  create_user_command(bufnr, "TableViewOpenBrowser", function()
    browser_view_basic(bufnr)
  end, { desc = "[markdown.nvim] Open table in browser (basic HTML)", nargs = 0 })

  create_user_command(bufnr, "TableViewOpenBrowserNice", function()
    browser_view_niceified(bufnr)
  end, { desc = "[markdown.nvim] Open table in browser (nice HTML)", nargs = 0 })
end

return M
