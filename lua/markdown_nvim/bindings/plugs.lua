---@module 'markdown_nvim.bindings.plugs'
---@brief The stable `<Plug>(markdown-*)` surface for every editing action.
---@description
--- Defining `<Plug>` mappings (once, globally) decouples actions from concrete
--- keys: the default buffer-local keys in `markdown_nvim.bindings.keymaps` map
--- onto these, and users can remap or disable the defaults and bind their own
--- keys to the same `<Plug>` names. Idempotent — safe to call on every setup().

local M = {}

local function pmap(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "[markdown.nvim] " .. desc })
end

local defined = false

--- Define the whole `<Plug>` surface (no-op after the first call).
---@return nil
function M.define()
  if defined then return end
  defined = true

  local head      = require("markdown_nvim.core.headings")
  local fold      = require("markdown_nvim.core.fold")
  local fold_prev = require("markdown_nvim.core.fold_prev")
  local fold_lvl  = require("markdown_nvim.core.fold_levels")
  local wrap      = require("markdown_nvim.core.wrap")
  local wrap_link = require("markdown_nvim.core.wrap_link")
  local handler   = require("markdown_nvim.handler")
  local image     = require("markdown_nvim.handler.image")
  local anchor    = require("markdown_nvim.anchor.jump")

  -- Bold / link wrap
  pmap("v", "<Plug>(markdown-toggle-bold)", function() wrap.toggle_visual_bold() end, "Toggle bold")
  pmap("n", "<Plug>(markdown-wrap-link)", function() wrap_link.wrap_normal() end, "Wrap word in link")
  pmap("v", "<Plug>(markdown-wrap-link)", function() wrap_link.wrap_visual() end, "Wrap selection in link")

  -- Heading navigation
  pmap({ "n", "v", "x" }, "<Plug>(markdown-prev-heading)", function() head.goto_prev_heading() end, "Prev heading")
  pmap({ "n", "v", "x" }, "<Plug>(markdown-next-heading)", function() head.goto_next_heading() end, "Next heading")
  pmap("n", "<Plug>(markdown-prev-heading-level)", function() head.goto_prev_heading_level() end, "Prev heading of level")
  pmap("n", "<Plug>(markdown-next-heading-level)", function() head.goto_next_heading_level() end, "Next heading of level")

  -- Folding
  pmap("n", "<Plug>(markdown-fold-toggle)", function() fold.toggle_under_cursor() end, "Fold toggle")
  pmap("n", "<Plug>(markdown-unfold-all)", function() fold.unfold_all_center() end, "Unfold all")
  pmap("n", "<Plug>(markdown-fold-prev-heading)", function() fold_prev.fold_prev_heading_then_center() end, "Fold prev heading")
  pmap("n", "<Plug>(markdown-fold-h2plus)", function() fold_lvl.fold_h2_plus() end, "Fold H2+")

  -- TOC (count = max heading level)
  pmap("n", "<Plug>(markdown-toc)", function()
    local count = vim.v.count
    require("markdown_nvim.commands.toc").update(
      "## Table of content",
      count > 0 and { max_level = count } or nil
    )
  end, "Insert/refresh TOC")

  -- Cursor action / image / anchor
  pmap("n", "<Plug>(markdown-cursor-action)", function() handler.handle_cursor_action() end, "Handle cursor action")
  pmap("n", "<Plug>(markdown-open-image)", function() image.open() end, "Open image")
  pmap("n", "<Plug>(markdown-jump-anchor)", function() anchor.jump() end, "Jump to anchor")

  -- Heading level shift (normal = current line, visual = selection); count = levels
  pmap("n", "<Plug>(markdown-heading-inc)", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    head.shift_range(row, row, vim.v.count1)
  end, "Increase heading level")
  pmap("n", "<Plug>(markdown-heading-dec)", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    head.shift_range(row, row, -vim.v.count1)
  end, "Decrease heading level")
  pmap({ "v", "x" }, "<Plug>(markdown-heading-inc)", function() head.shift_visual_selection(vim.v.count1) end, "Increase heading level (visual)")
  pmap({ "v", "x" }, "<Plug>(markdown-heading-dec)", function() head.shift_visual_selection(-vim.v.count1) end, "Decrease heading level (visual)")

  -- Whole-buffer heading shift
  pmap("n", "<Plug>(markdown-heading-inc-all)", function()
    local total = vim.api.nvim_buf_line_count(0)
    head.shift_range(1, total, vim.v.count1)
  end, "Increase all headings")
  pmap("n", "<Plug>(markdown-heading-dec-all)", function()
    local total = vim.api.nvim_buf_line_count(0)
    head.shift_range(1, total, -vim.v.count1)
  end, "Decrease all headings")
end

return M
