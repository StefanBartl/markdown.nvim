---@module 'markdown_nvim.bindings.keymaps'
---@brief Buffer-local default keymaps, bound onto the `<Plug>` surface.
---@description
--- `apply` installs the opinionated editing keys (heading nav/shift, folding,
--- TOC, cursor action, bold/link wrap) by mapping them to the stable
--- `<Plug>(markdown-*)` actions (see `markdown_nvim.bindings.plugs`); it is a
--- no-op when `enable_keymaps = false` (the `<Plug>` surface stays available).
--- `apply_tableview` installs the `<leader>tv*` TableView keys, which drive the
--- `:TableView*` commands and are independent of `enable_keymaps`.

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.bindings.keymaps]")

local M = {}

local cfg = require("markdown_nvim.config").get

local function map(bufnr, mode, lhs, rhs, desc)
  local ok, err = pcall(vim.keymap.set, mode, lhs, rhs, {
    buffer  = bufnr,
    noremap = false, -- rhs is a <Plug>; it must be remappable
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

  -- Ensure the <Plug> actions exist (idempotent).
  require("markdown_nvim.bindings.plugs").define()

  -- Bold toggle (visual)
  if cfg().map_double_asterisk then
    map(bufnr, "v", "**", "<Plug>(markdown-toggle-bold)", "Toggle bold")
  end

  -- Wrap word/selection in a Markdown link []()
  if cfg().map_wrap_link then
    map(bufnr, "n", "<leader>[", "<Plug>(markdown-wrap-link)", "Wrap word in link")
    map(bufnr, "v", "<leader>[", "<Plug>(markdown-wrap-link)", "Wrap selection in link")
  end

  -- Heading navigation
  map(bufnr, { "n", "v", "x" }, "<C-p>", "<Plug>(markdown-prev-heading)", "Prev heading")
  map(bufnr, "n", "[[", "<Plug>(markdown-prev-heading)", "Prev heading")
  map(bufnr, { "n", "v", "x" }, "<C-f>", "<Plug>(markdown-next-heading)", "Next heading")
  map(bufnr, "n", "]]", "<Plug>(markdown-next-heading)", "Next heading")

  map(bufnr, "n", "<leader><C-p>", "<Plug>(markdown-prev-heading-level)", "Prev heading of level")
  map(bufnr, "n", "<leader><C-f>", "<Plug>(markdown-next-heading-level)", "Next heading of level")

  -- Fold
  if cfg().use_zf_override then
    map(bufnr, "n", "zf", "<Plug>(markdown-fold-toggle)", "Fold toggle")
  end
  map(bufnr, "n", "<localleader>f", "<Plug>(markdown-fold-toggle)", "Fold toggle")
  map(bufnr, "n", "zu", "<Plug>(markdown-unfold-all)", "Unfold all")
  map(bufnr, "n", "zi", "<Plug>(markdown-fold-prev-heading)", "Fold prev heading")
  map(bufnr, "n", "zk", "<Plug>(markdown-fold-h2plus)", "Fold H2+")

  -- TOC (count = max_level); also ensures headline separators per config.
  map(bufnr, "n", "<leader>toc", "<Plug>(markdown-toc)", "Insert/refresh TOC")

  -- Cursor action (double-click, Ctrl+Click, ma). The mouse variants use the
  -- silent <Plug>: moving/clicking the mouse over prose with no link/anchor
  -- under it is a normal outcome, not worth a notification every time.
  map(bufnr, "n", "<2-LeftMouse>", "<Plug>(markdown-cursor-action-mouse)", "Handle cursor action")
  map(bufnr, "n", "<C-LeftMouse>", "<Plug>(markdown-cursor-action-mouse)", "Handle cursor action")
  map(bufnr, "n", "ma", "<Plug>(markdown-cursor-action)", "Handle cursor action")

  -- Image / anchor
  map(bufnr, "n", "mi", "<Plug>(markdown-open-image)", "Open image")
  map(bufnr, "n", "mj", "<Plug>(markdown-jump-anchor)", "Jump to anchor")

  -- Heading level shift (normal mode: single line); count = number of levels.
  map(bufnr, "n", "<C-Right>", "<Plug>(markdown-heading-inc)", "Increase heading level")
  map(bufnr, "n", "<C-Left>", "<Plug>(markdown-heading-dec)", "Decrease heading level")

  -- Heading level shift (visual mode: selection only)
  map(bufnr, { "v", "x" }, "<C-Right>", "<Plug>(markdown-heading-inc)", "Increase heading level (visual)")
  map(bufnr, { "v", "x" }, "<C-Left>", "<Plug>(markdown-heading-dec)", "Decrease heading level (visual)")

  -- Whole-buffer heading shift (S-Right / S-Left); count = number of levels.
  map(bufnr, "n", "<S-Right>", "<Plug>(markdown-heading-inc-all)", "Increase all headings")
  map(bufnr, "n", "<S-Left>", "<Plug>(markdown-heading-dec-all)", "Decrease all headings")
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
