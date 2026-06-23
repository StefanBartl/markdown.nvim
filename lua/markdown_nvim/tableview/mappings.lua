---@module 'markdown_nvim.tableview.mappings'
local api = vim.api
local M = {}

local function with(o, extra)
  local out = {}
  if o then for k, v in pairs(o) do out[k] = v end end
  if extra then for k, v in pairs(extra) do out[k] = v end end
  return out
end

function M.apply(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  if not ft or not ft:match("markdown") then return end

  local opts = { buffer = bufnr, noremap = true, silent = true }

  vim.keymap.set("n", "<leader>tvt", function()
    vim.cmd("TableViewToggle")
  end, with(opts, { desc = "[markdown.nvim] Toggle table preview at cursor" }))

  vim.keymap.set("n", "<leader>tvs", function()
    vim.cmd("TableViewSelect")
  end, with(opts, { desc = "[markdown.nvim] Select and preview table" }))

  vim.keymap.set("n", "<leader>tvb", function()
    vim.cmd("TableViewOpenBrowser")
  end, with(opts, { desc = "[markdown.nvim] Open table in browser" }))

  vim.keymap.set("n", "<leader>tvc", function()
    vim.cmd("TableViewClose")
  end, with(opts, { desc = "[markdown.nvim] Close TableView" }))
end

return M
