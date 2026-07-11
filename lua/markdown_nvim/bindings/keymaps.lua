---@module 'markdown_nvim.bindings.keymaps'
---@brief Buffer-local default keymaps, bound directly to the action functions.
---@description
--- `apply` installs the opinionated editing keys (heading nav/shift, folding,
--- TOC, cursor action, bold/link wrap) by mapping them straight to the functions
--- in `markdown_nvim.bindings.actions`; it is a no-op when
--- `enable_keymaps = false`. Users who disable the defaults (or want extra keys)
--- can bind the same functions via `require("markdown_nvim").actions`.
--- `apply_tableview` installs the `<leader>tv*` TableView keys, which drive the
--- `:TableView*` commands and are independent of `enable_keymaps`.

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.bindings.keymaps]")

local M = {}

local cfg = require("markdown_nvim.config").get
local actions = require("markdown_nvim.bindings.actions")

local function map(bufnr, mode, lhs, rhs, desc)
  local ok, err = pcall(vim.keymap.set, mode, lhs, rhs, {
    buffer  = bufnr,
    silent  = true,
    desc    = "[markdown.nvim] " .. desc,
  })
  if not ok then
    notify.warn("keymap failed " .. lhs .. ": " .. tostring(err))
  end
end

--- Install the default editing keymaps for `bufnr`.
--- No-op when `enable_keymaps = false`.
---@param bufnr integer
---@return nil
function M.apply(bufnr)
  if type(bufnr) ~= "number" then return end
  if cfg().enable_keymaps == false then return end

  -- Bold toggle (visual)
  if cfg().map_double_asterisk then
    map(bufnr, "v", "**", actions.toggle_bold_visual, "Toggle bold")
  end

  -- Wrap word/selection in a Markdown link []()
  if cfg().map_wrap_link then
    map(bufnr, "n", "<leader>[", actions.wrap_link_normal, "Wrap word in link")
    map(bufnr, "v", "<leader>[", actions.wrap_link_visual, "Wrap selection in link")
  end

  -- Heading navigation
  map(bufnr, { "n", "v", "x" }, "<C-p>", actions.prev_heading, "Prev heading")
  map(bufnr, "n", "[[", actions.prev_heading, "Prev heading")
  map(bufnr, { "n", "v", "x" }, "<C-f>", actions.next_heading, "Next heading")
  map(bufnr, "n", "]]", actions.next_heading, "Next heading")

  map(bufnr, "n", "<leader><C-p>", actions.prev_heading_level, "Prev heading of level")
  map(bufnr, "n", "<leader><C-f>", actions.next_heading_level, "Next heading of level")

  -- Fold
  if cfg().use_zf_override then
    map(bufnr, "n", "zf", actions.fold_toggle, "Fold toggle")
  end
  map(bufnr, "n", "<localleader>f", actions.fold_toggle, "Fold toggle")
  map(bufnr, "n", "zu", actions.unfold_all, "Unfold all")
  map(bufnr, "n", "zi", actions.fold_prev_heading, "Fold prev heading")
  map(bufnr, "n", "zk", actions.fold_h2plus, "Fold H2+")

  -- TOC (count = max_level); also ensures headline separators per config.
  map(bufnr, "n", "<leader>toc", actions.toc, "Insert/refresh TOC")

  -- Cursor action (double-click, Ctrl+Click, ma). The mouse variants are
  -- silent: moving/clicking the mouse over prose with no link/anchor under it
  -- is a normal outcome, not worth a notification every time.
  map(bufnr, "n", "<2-LeftMouse>", actions.cursor_action_mouse, "Handle cursor action")
  map(bufnr, "n", "<C-LeftMouse>", actions.cursor_action_mouse, "Handle cursor action")
  map(bufnr, "n", "ma", actions.cursor_action, "Handle cursor action")

  -- Image / anchor
  map(bufnr, "n", "mi", actions.open_image, "Open image")
  map(bufnr, "n", "mj", actions.jump_anchor, "Jump to anchor")

  -- Heading level shift (normal mode: single line); count = number of levels.
  map(bufnr, "n", "<C-Right>", actions.heading_inc, "Increase heading level")
  map(bufnr, "n", "<C-Left>", actions.heading_dec, "Decrease heading level")

  -- Heading level shift (visual mode: selection only)
  map(bufnr, { "v", "x" }, "<C-Right>", actions.heading_inc_visual, "Increase heading level (visual)")
  map(bufnr, { "v", "x" }, "<C-Left>", actions.heading_dec_visual, "Decrease heading level (visual)")

  -- Whole-buffer heading shift (S-Right / S-Left); count = number of levels.
  map(bufnr, "n", "<S-Right>", actions.heading_inc_all, "Increase all headings")
  map(bufnr, "n", "<S-Left>", actions.heading_dec_all, "Decrease all headings")
end

--- Install the buffer-local TableView keys (`<leader>tv*`) for `bufnr`.
--- These drive the `:TableView*` commands and are independent of enable_keymaps.
---@param bufnr integer
---@return nil
function M.apply_tableview(bufnr)
  if type(bufnr) ~= "number" then return end
  local ft = vim.bo[bufnr].filetype
  if not ft or not ft:match("markdown") then return end

  map(bufnr, "n", "<leader>tvt", "<Cmd>TableViewToggle<CR>", "Toggle table preview at cursor")
  map(bufnr, "n", "<leader>tvs", "<Cmd>TableViewSelect<CR>", "Select and preview table")
  map(bufnr, "n", "<leader>tvb", "<Cmd>TableViewOpenBrowser<CR>", "Open table in browser")
  map(bufnr, "n", "<leader>tvc", "<Cmd>TableViewClose<CR>", "Close TableView")
end

return M
