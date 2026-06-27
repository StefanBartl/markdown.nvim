---@module 'markdown_nvim.setup.autocmds'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.setup.autocmds]")

local M = {}

local function is_md(ftname)
  if not ftname then return false end
  return ftname == "md"
    or ftname == "mdx"
    or ftname == "markdown"
    or ftname:match("^markdown%.")
end

local function apply_to_already_loaded_md_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if is_md(ft) then
        local ok, err = pcall(function()
          require("markdown_nvim.setup.keymaps").apply(bufnr)
          require("markdown_nvim.setup.usercmds").apply({ buf = bufnr })
        end)
        if not ok then
          notify.warn("Error applying to existing buffer " .. bufnr .. ": " .. tostring(err))
        end
      end
    end
  end
end

function M.setup()
  local aug_keymaps = vim.api.nvim_create_augroup("MarkdownNvimKeymaps", { clear = true })
  local aug_cmds    = vim.api.nvim_create_augroup("MarkdownNvimUserCommands", { clear = true })
  local aug_fold    = vim.api.nvim_create_augroup("MarkdownNvimFold", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group   = aug_keymaps,
    pattern = { "markdown", "mdx", "md", "markdown.*" },
    callback = function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      local ok, err = pcall(require("markdown_nvim.setup.keymaps").apply, ev.buf)
      if not ok then
        notify.warn("Error applying keymaps: " .. tostring(err))
      end
    end,
    desc = "[markdown.nvim] Install buffer-local keymaps",
  })

  vim.api.nvim_create_autocmd("FileType", {
    group   = aug_cmds,
    pattern = { "markdown", "mdx", "md", "markdown.*" },
    callback = function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      local ok, err = pcall(require("markdown_nvim.setup.usercmds").apply, ev)
      if not ok then
        notify.warn("Error applying usercmds: " .. tostring(err))
      end
    end,
    desc = "[markdown.nvim] Install buffer-local user commands",
  })

  vim.api.nvim_create_autocmd("FileType", {
    group   = aug_fold,
    pattern = { "markdown", "mdx", "md", "markdown.*" },
    once    = false,
    callback = function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      vim.opt_local.foldmethod    = "expr"
      vim.opt_local.foldexpr      = "v:lua.require'markdown_nvim.core.fold'.foldexpr(v:lnum)"
      vim.opt_local.foldenable    = true
      vim.opt_local.foldlevel     = 99
      vim.opt_local.foldlevelstart = 99
    end,
    desc = "[markdown.nvim] Set fold options for markdown buffers",
  })

  apply_to_already_loaded_md_buffers()
end

return M
