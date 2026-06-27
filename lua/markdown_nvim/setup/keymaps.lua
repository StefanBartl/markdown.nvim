---@module 'markdown_nvim.setup.keymaps'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.setup.keymaps]")

local M = {}

local cfg = require("markdown_nvim.config").get

local function map(bufnr, mode, lhs, rhs, desc)
  local ok, err = pcall(vim.keymap.set, mode, lhs, rhs, {
    buffer  = bufnr,
    noremap = true,
    silent  = true,
    desc    = "[markdown.nvim] " .. desc,
  })
  if not ok then
    notify.warn("keymap failed " .. lhs .. ": " .. tostring(err))
  end
end

function M.apply(bufnr)
  if type(bufnr) ~= "number" then return end

  local head      = require("markdown_nvim.core.headings")
  local fold      = require("markdown_nvim.core.fold")
  local fold_prev = require("markdown_nvim.core.fold_prev")
  local fold_lvl  = require("markdown_nvim.core.fold_levels")
  local wrap      = require("markdown_nvim.core.wrap")
  local wrap_link = require("markdown_nvim.core.wrap_link")
  local handler   = require("markdown_nvim.handler")
  local image     = require("markdown_nvim.handler.image")
  local anchor    = require("markdown_nvim.anchor.jump")

  -- Bold toggle (visual)
  if cfg().map_double_asterisk then
    map(bufnr, "v", "**", function() wrap.toggle_visual_bold() end, "Toggle bold")
  end

  -- Wrap word/selection in a Markdown link []()
  if cfg().map_wrap_link then
    map(bufnr, "n", "<leader>[", function() wrap_link.wrap_normal() end, "Wrap word in link")
    map(bufnr, "v", "<leader>[", function() wrap_link.wrap_visual() end, "Wrap selection in link")
  end

  -- Heading navigation
  map(bufnr, { "n", "v", "x" }, "<C-p>", function() head.goto_prev_heading() end, "Prev heading")
  map(bufnr, "n", "[[",    function() head.goto_prev_heading() end, "Prev heading")
  map(bufnr, { "n", "v", "x" }, "<C-f>", function() head.goto_next_heading() end, "Next heading")
  map(bufnr, "n", "]]",    function() head.goto_next_heading() end, "Next heading")

  map(bufnr, "n", "<leader><C-p>", function() head.goto_prev_heading_level() end, "Prev heading of level")
  map(bufnr, "n", "<leader><C-f>", function() head.goto_next_heading_level() end, "Next heading of level")

  -- Fold
  local zf_rhs = function() fold.toggle_under_cursor() end
  if cfg().use_zf_override then
    map(bufnr, "n", "zf", zf_rhs, "Fold toggle")
  end
  map(bufnr, "n", "<localleader>f", zf_rhs, "Fold toggle")
  map(bufnr, "n", "zu", function() fold.unfold_all_center() end, "Unfold all")
  map(bufnr, "n", "zi", function() fold_prev.fold_prev_heading_then_center() end, "Fold prev heading")
  map(bufnr, "n", "zk", function() fold_lvl.fold_h2_plus() end, "Fold H2+")

  -- TOC (count = max_level); also ensures headline separators per config.
  map(bufnr, "n", "<leader>toc", function()
    local count = vim.v.count
    require("markdown_nvim.commands.toc").update(
      "## Table of content",
      count > 0 and { max_level = count } or nil
    )
  end, "Insert/refresh TOC")

  -- Cursor action (double-click, Ctrl+Click, ma)
  map(bufnr, "n", "<2-LeftMouse>",  function() handler.handle_cursor_action() end, "Handle cursor action")
  map(bufnr, "n", "<C-LeftMouse>",  function() handler.handle_cursor_action() end, "Handle cursor action")
  map(bufnr, "n", "ma",             function() handler.handle_cursor_action() end, "Handle cursor action")

  -- Image / anchor
  map(bufnr, "n", "mi", function() image.open() end,  "Open image")
  map(bufnr, "n", "mj", function() anchor.jump() end, "Jump to anchor")

  -- Heading level shift (normal mode: single line); count = number of levels.
  map(bufnr, "n", "<C-Right>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    head.shift_range(row, row, vim.v.count1)
  end, "Increase heading level")

  map(bufnr, "n", "<C-Left>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    head.shift_range(row, row, -vim.v.count1)
  end, "Decrease heading level")

  -- Heading level shift (visual mode: selection only)
  map(bufnr, { "v", "x" }, "<C-Right>", function()
    head.shift_visual_selection(vim.v.count1)
  end, "Increase heading level (visual)")

  map(bufnr, { "v", "x" }, "<C-Left>", function()
    head.shift_visual_selection(-vim.v.count1)
  end, "Decrease heading level (visual)")

  -- Whole-buffer heading shift (S-Right / S-Left); count = number of levels.
  map(bufnr, "n", "<S-Right>", function()
    local total = vim.api.nvim_buf_line_count(0)
    head.shift_range(1, total, vim.v.count1)
  end, "Increase all headings")

  map(bufnr, "n", "<S-Left>", function()
    local total = vim.api.nvim_buf_line_count(0)
    head.shift_range(1, total, -vim.v.count1)
  end, "Decrease all headings")
end

return M
