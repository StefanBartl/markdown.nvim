---@module 'markdown_nvim.setup.usercmds'
local M = {}

local api = vim.api

local function create_open_command(bufnr)
  local ok, cmds = pcall(api.nvim_buf_get_commands, bufnr, { builtin = false })
  if not ok then cmds = {} end
  if cmds["OpenWithSystemApplication"] then return end

  api.nvim_buf_create_user_command(bufnr, "OpenWithSystemApplication", function()
    require("markdown_nvim.handler").handle_cursor_action()
  end, {
    desc  = "[markdown.nvim] Open image/url/file under cursor",
    nargs = 0,
  })
end

local function create_markdown_command()
  if vim.fn.exists(":Markdown") == 2 then return end

  vim.api.nvim_create_user_command("Markdown", function(opts)
    require("markdown_nvim.commands").execute(opts.fargs)
  end, {
    nargs    = "*",
    complete = function(arglead, cmdline, cursorpos)
      return require("markdown_nvim.commands").complete(arglead, cmdline, cursorpos)
    end,
    desc = "[markdown.nvim] Markdown utility commands",
  })
end

function M.apply(args)
  if type(args) ~= "table" or type(args.buf) ~= "number" then return end
  local bufnr = args.buf
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)) then return end

  create_open_command(bufnr)
  create_markdown_command()
end

return M
