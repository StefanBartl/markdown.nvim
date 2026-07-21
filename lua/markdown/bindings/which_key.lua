---@module 'markdown.bindings.which_key'
---@brief Optional, guarded which-key group labels for markdown.nvim prefixes.
---@description
--- which-key is a **soft** dependency: if it is not installed this is a no-op.
--- When present, the `<leader>t` prefix (`<leader>toc`, `<leader>tv*`) is grouped
--- under a "Markdown" label so the default keys read as a menu instead of a bare
--- prefix. Individual keys already carry their own `desc`, so only group labels
--- are registered. Supports the which-key v3 (`add`) and v2 (`register`) APIs.

local M = {}

--- Register markdown.nvim's group labels with which-key, if available.
---@return boolean registered
function M.setup()
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end
  if type(wk.add) == "function" then
    -- which-key v3
    wk.add({
      { "<leader>t", group = "Markdown" },
      { "<leader>tv", group = "Markdown TableView" },
    })
    return true
  elseif type(wk.register) == "function" then
    -- which-key v2
    wk.register({
      ["<leader>t"] = { name = "+Markdown" },
      ["<leader>tv"] = { name = "+Markdown TableView" },
    })
    return true
  end
  return false
end

--- Whether which-key is installed (for :checkhealth reporting).
---@return boolean
function M.available()
  local ok, wk = pcall(require, "which-key")
  return ok and type(wk) == "table"
end

return M
