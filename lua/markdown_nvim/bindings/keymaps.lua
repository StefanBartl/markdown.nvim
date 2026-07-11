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

-- Default editing keymaps as DATA, each with a stable `id` the user config can
-- target. `flag` (optional) is a legacy boolean option that still gates the
-- binding when set to false. Order defines application order.
---@type { id: string, mode: string|string[], lhs: string, action: string, flag?: string, feature?: string, desc: string }[]
local DEFAULT_KEYMAPS = {
  { id = "toggle_bold",          mode = "v",               lhs = "**",             action = "toggle_bold_visual",  flag = "map_double_asterisk", desc = "Toggle bold" },
  { id = "wrap_link_n",          mode = "n",               lhs = "<leader>[",      action = "wrap_link_normal",    flag = "map_wrap_link",       desc = "Wrap word in link" },
  { id = "wrap_link_v",          mode = "v",               lhs = "<leader>[",      action = "wrap_link_visual",    flag = "map_wrap_link",       desc = "Wrap selection in link" },
  { id = "prev_heading",         mode = { "n", "v", "x" }, lhs = "<C-p>",          action = "prev_heading",        desc = "Prev heading" },
  { id = "prev_heading_bracket", mode = "n",               lhs = "[[",             action = "prev_heading",        desc = "Prev heading" },
  { id = "next_heading",         mode = { "n", "v", "x" }, lhs = "<C-f>",          action = "next_heading",        desc = "Next heading" },
  { id = "next_heading_bracket", mode = "n",               lhs = "]]",             action = "next_heading",        desc = "Next heading" },
  { id = "prev_heading_level",   mode = "n",               lhs = "<leader><C-p>",  action = "prev_heading_level",  desc = "Prev heading of level" },
  { id = "next_heading_level",   mode = "n",               lhs = "<leader><C-f>",  action = "next_heading_level",  desc = "Next heading of level" },
  { id = "fold_toggle_zf",       mode = "n",               lhs = "zf",             action = "fold_toggle",         flag = "use_zf_override",     desc = "Fold toggle" },
  { id = "fold_toggle",          mode = "n",               lhs = "<localleader>f", action = "fold_toggle",         desc = "Fold toggle" },
  { id = "unfold_all",           mode = "n",               lhs = "zu",             action = "unfold_all",          desc = "Unfold all" },
  { id = "fold_prev_heading",    mode = "n",               lhs = "zi",             action = "fold_prev_heading",   desc = "Fold prev heading" },
  { id = "fold_h2plus",          mode = "n",               lhs = "zk",             action = "fold_h2plus",         desc = "Fold H2+" },
  { id = "toc",                  mode = "n",               lhs = "<leader>toc",    action = "toc",                 feature = "toc", desc = "Insert/refresh TOC" },
  { id = "cursor_action_2click", mode = "n",               lhs = "<2-LeftMouse>",  action = "cursor_action_mouse", desc = "Cursor action / heading fold" },
  { id = "cursor_action_cclick", mode = "n",               lhs = "<C-LeftMouse>",  action = "cursor_action_mouse", desc = "Cursor action" },
  { id = "cursor_action",        mode = "n",               lhs = "ma",             action = "cursor_action",       desc = "Cursor action" },
  { id = "open_image",           mode = "n",               lhs = "mi",             action = "open_image",          desc = "Open image" },
  { id = "jump_anchor",          mode = "n",               lhs = "mj",             action = "jump_anchor",         desc = "Jump to anchor" },
  { id = "heading_inc",          mode = "n",               lhs = "<C-Right>",      action = "heading_inc",         desc = "Increase heading level" },
  { id = "heading_dec",          mode = "n",               lhs = "<C-Left>",       action = "heading_dec",         desc = "Decrease heading level" },
  { id = "heading_inc_visual",   mode = { "v", "x" },      lhs = "<C-Right>",      action = "heading_inc_visual",  desc = "Increase heading level (visual)" },
  { id = "heading_dec_visual",   mode = { "v", "x" },      lhs = "<C-Left>",       action = "heading_dec_visual",  desc = "Decrease heading level (visual)" },
  { id = "heading_inc_all",      mode = "n",               lhs = "<S-Right>",      action = "heading_inc_all",     desc = "Increase all headings" },
  { id = "heading_dec_all",      mode = "n",               lhs = "<S-Left>",       action = "heading_dec_all",     desc = "Decrease all headings" },
  { id = "table_next_cell",      mode = "n",               lhs = "]|",             action = "table_next_cell",     feature = "table", desc = "Next table cell" },
  { id = "table_prev_cell",      mode = "n",               lhs = "[|",             action = "table_prev_cell",     feature = "table", desc = "Prev table cell" },
}

--- The default keymap specs (id/mode/lhs/action/desc), exposed for docs/tooling.
---@return table[]
function M.defaults()
  return DEFAULT_KEYMAPS
end

--- Install the default editing keymaps for `bufnr`.
--- No-op when `enable_keymaps = false`.
---
--- Per-binding control via `config.keymaps[id]`:
---   * `false`                       — disable this binding
---   * `"<newlhs>"`                  — remap to a new key (same mode)
---   * `{ lhs = "<newlhs>", mode = … }` — remap key and/or mode
--- The legacy boolean flags (`map_double_asterisk`, `map_wrap_link`,
--- `use_zf_override`) still disable their bindings when set to false.
---@param bufnr integer
---@return nil
function M.apply(bufnr)
  if type(bufnr) ~= "number" then return end
  if cfg().enable_keymaps == false then return end

  local feat = require("markdown_nvim.config").feature_enabled
  local overrides = cfg().keymaps or {}

  for _, spec in ipairs(DEFAULT_KEYMAPS) do
    -- Legacy flag gate (e.g. map_double_asterisk = false).
    local flag_off = spec.flag and cfg()[spec.flag] == false
    -- Feature gate on the spec's effective feature: most bindings belong to the
    -- general "keymaps" feature, but a few (e.g. toc) carry a finer one so they
    -- can stay active under `just_enable = { "toc" }` even with "keymaps" off.
    local feature_off = not feat(spec.feature or "keymaps")
    local ov = overrides[spec.id]

    if not flag_off and not feature_off and ov ~= false then
      local lhs, mode = spec.lhs, spec.mode
      if type(ov) == "string" then
        lhs = ov
      elseif type(ov) == "table" then
        lhs = ov.lhs or lhs
        mode = ov.mode or mode
      end

      local fn = actions[spec.action]
      if fn then
        map(bufnr, mode, lhs, fn, spec.desc)
      end
    end
  end
end

--- Install the buffer-local TableView keys (`<leader>tv*`) for `bufnr`.
--- These drive the `:TableView*` commands and are independent of enable_keymaps.
---@param bufnr integer
---@return nil
function M.apply_tableview(bufnr)
  if type(bufnr) ~= "number" then return end
  local ft = vim.bo[bufnr].filetype
  if not ft or not ft:match("markdown") then return end
  if not require("markdown_nvim.config").feature_enabled("tableview") then return end

  map(bufnr, "n", "<leader>tvt", "<Cmd>TableViewToggle<CR>", "Toggle table preview at cursor")
  map(bufnr, "n", "<leader>tvs", "<Cmd>TableViewSelect<CR>", "Select and preview table")
  map(bufnr, "n", "<leader>tvb", "<Cmd>TableViewOpenBrowser<CR>", "Open table in browser")
  map(bufnr, "n", "<leader>tvc", "<Cmd>TableViewClose<CR>", "Close TableView")
  map(bufnr, "n", "<leader>tvm", "<Cmd>Markdown table mode toggle<CR>", "Toggle table auto-format mode")
end

return M
