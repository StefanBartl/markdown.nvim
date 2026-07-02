---@module 'markdown_nvim.setup.keymaps'
---@brief Buffer-local default keymaps, bound onto the `<Plug>` surface.
---@description
--- Applies the opinionated default keys for a markdown buffer by mapping them to
--- the stable `<Plug>(markdown-*)` actions (see `markdown_nvim.setup.plugs`).
--- Users who want different keys can set `enable_keymaps = false` and bind their
--- own keys to the same `<Plug>` names. Honors the `map_double_asterisk`,
--- `map_wrap_link` and `use_zf_override` config flags.

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.setup.keymaps]")

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

--- Install the default buffer-local keymaps for `bufnr`.
--- No-op when `enable_keymaps = false`; the `<Plug>` surface stays available so
--- users can bind their own keys.
---@param bufnr integer
---@return nil
function M.apply(bufnr)
  if type(bufnr) ~= "number" then return end
  if cfg().enable_keymaps == false then return end

  -- Ensure the <Plug> actions exist (idempotent).
  require("markdown_nvim.setup.plugs").define()

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

  -- Cursor action (double-click, Ctrl+Click, ma)
  map(bufnr, "n", "<2-LeftMouse>", "<Plug>(markdown-cursor-action)", "Handle cursor action")
  map(bufnr, "n", "<C-LeftMouse>", "<Plug>(markdown-cursor-action)", "Handle cursor action")
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

return M
