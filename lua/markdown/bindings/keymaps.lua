---@module 'markdown.bindings.keymaps'
---@brief Buffer-local default keymaps, bound directly to the action functions.
---@description
--- `apply` installs the opinionated editing keys (heading nav/shift, folding,
--- TOC, cursor action, bold/link wrap) by mapping them straight to the functions
--- in `markdown.bindings.actions`; it is a no-op when
--- `enable_keymaps = false`. Users who disable the defaults (or want extra keys)
--- can bind the same functions via `require("markdown").actions`.
--- `apply_tableview` installs the `<leader>tv*` TableView keys, which drive the
--- `:TableView*` commands and are independent of `enable_keymaps`.
---
--- Both go through `lib.nvim.bindings.keymap`'s registry. The config shape is
--- unchanged -- `keymaps[id]` still takes `false`, an lhs, or
--- `{ lhs = ..., mode = ... }` -- and three things are new: an override may be
--- a *list* of keys, a wrong id is reported with its nearest match instead of
--- being silently ignored, and the TableView keys are overridable at all
--- (`keymaps.tableview_toggle = "<leader>mt"`), which they were not.

local libkeymap = require("lib.nvim.bindings.keymap")

local M = {}

local cfg = require("markdown.config").get
local actions = require("markdown.bindings.actions")

-- Default editing keymaps as DATA, each with a stable `id` the user config can
-- target. `flag` (optional) is a legacy boolean option that still gates the
-- binding when set to false. Order defines application order.
---@type { id: string, mode: string|string[], lhs: string, action: string, flag?: string, feature?: string, desc: string }[]
local DEFAULT_KEYMAPS = {
  {
    id = "toggle_bold",
    mode = "v",
    lhs = "**",
    action = "toggle_bold_visual",
    flag = "map_double_asterisk",
    desc = "Toggle bold",
  },
  {
    id = "wrap_link_n",
    mode = "n",
    lhs = "<leader>[",
    action = "wrap_link_normal",
    flag = "map_wrap_link",
    desc = "Wrap word in link",
  },
  {
    id = "wrap_link_v",
    mode = "v",
    lhs = "<leader>[",
    action = "wrap_link_visual",
    flag = "map_wrap_link",
    desc = "Wrap selection in link",
  },
  {
    id = "prev_heading",
    mode = { "n", "v", "x" },
    lhs = "<C-p>",
    action = "prev_heading",
    desc = "Prev heading / fence",
  },
  {
    id = "prev_heading_bracket",
    mode = "n",
    lhs = "[[",
    action = "prev_heading",
    desc = "Prev heading / fence",
  },
  {
    id = "next_heading",
    mode = { "n", "v", "x" },
    lhs = "<C-f>",
    action = "next_heading",
    desc = "Next heading / fence",
  },
  {
    id = "next_heading_bracket",
    mode = "n",
    lhs = "]]",
    action = "next_heading",
    desc = "Next heading / fence",
  },
  {
    id = "prev_heading_level",
    mode = "n",
    lhs = "<leader><C-p>",
    action = "prev_heading_level",
    desc = "Prev heading of level",
  },
  {
    id = "next_heading_level",
    mode = "n",
    lhs = "<leader><C-f>",
    action = "next_heading_level",
    desc = "Next heading of level",
  },
  {
    id = "fold_toggle_zf",
    mode = "n",
    lhs = "zf",
    action = "fold_toggle",
    flag = "use_zf_override",
    desc = "Fold toggle",
  },
  {
    id = "fold_toggle",
    mode = "n",
    lhs = "<localleader>f",
    action = "fold_toggle",
    desc = "Fold toggle",
  },
  {
    id = "unfold_all",
    mode = "n",
    lhs = "zu",
    action = "unfold_all",
    desc = "Unfold all",
  },
  {
    id = "fold_prev_heading",
    mode = "n",
    lhs = "zi",
    action = "fold_prev_heading",
    desc = "Fold prev heading",
  },
  {
    id = "fold_h2plus",
    mode = "n",
    lhs = "zk",
    action = "fold_h2plus",
    desc = "Fold below H2 (toggle outline)",
  },
  {
    id = "toc",
    mode = "n",
    lhs = "<leader>toc",
    action = "toc",
    feature = "toc",
    desc = "Insert/refresh TOC",
  },
  {
    id = "cursor_action_2click",
    mode = "n",
    lhs = "<2-LeftMouse>",
    action = "cursor_action_mouse",
    desc = "Cursor action / heading fold",
  },
  {
    id = "cursor_action_cclick",
    mode = "n",
    lhs = "<C-LeftMouse>",
    action = "cursor_action_mouse",
    desc = "Cursor action",
  },
  {
    id = "cursor_action",
    mode = "n",
    lhs = "ma",
    action = "cursor_action",
    desc = "Cursor action",
  },
  {
    id = "open_image",
    mode = "n",
    lhs = "mi",
    action = "open_image",
    desc = "Open image",
  },
  {
    id = "jump_anchor",
    mode = "n",
    lhs = "mj",
    action = "jump_anchor",
    desc = "Jump to anchor",
  },
  {
    id = "heading_inc",
    mode = "n",
    lhs = "<C-Right>",
    action = "heading_inc",
    desc = "Increase heading level",
  },
  {
    id = "heading_dec",
    mode = "n",
    lhs = "<C-Left>",
    action = "heading_dec",
    desc = "Decrease heading level",
  },
  {
    id = "heading_inc_visual",
    mode = { "v", "x" },
    lhs = "<C-Right>",
    action = "heading_inc_visual",
    desc = "Increase heading level (visual)",
  },
  {
    id = "heading_dec_visual",
    mode = { "v", "x" },
    lhs = "<C-Left>",
    action = "heading_dec_visual",
    desc = "Decrease heading level (visual)",
  },
  {
    id = "heading_inc_all",
    mode = "n",
    lhs = "<S-Right>",
    action = "heading_inc_all",
    desc = "Increase all headings",
  },
  {
    id = "heading_dec_all",
    mode = "n",
    lhs = "<S-Left>",
    action = "heading_dec_all",
    desc = "Decrease all headings",
  },
  {
    id = "table_next_cell",
    mode = "n",
    lhs = "]|",
    action = "table_next_cell",
    feature = "table",
    desc = "Next table cell",
  },
  {
    id = "table_prev_cell",
    mode = "n",
    lhs = "[|",
    action = "table_prev_cell",
    feature = "table",
    desc = "Prev table cell",
  },
  {
    id = "table_format",
    mode = "n",
    lhs = "<leader>mtf",
    action = "table_format",
    feature = "table",
    desc = "Format table at cursor",
  },
}

--- The default keymap specs (id/mode/lhs/action/desc), exposed for docs/tooling.
---@return table[]
function M.defaults() return DEFAULT_KEYMAPS end

--- The TableView keys, in declaration order.
---@type { id: string, lhs: string, cmd: string, desc: string }[]
local TABLEVIEW_KEYMAPS = {
  {
    id = "tableview_toggle",
    lhs = "<leader>tvt",
    cmd = "TableViewToggle",
    desc = "Toggle table preview at cursor",
  },
  {
    id = "tableview_box",
    lhs = "<leader>tvx",
    cmd = "TableViewBox",
    desc = "Toggle box-drawing table preview",
  },
  {
    id = "tableview_select",
    lhs = "<leader>tvs",
    cmd = "TableViewSelect",
    desc = "Select and preview table",
  },
  {
    id = "tableview_browser",
    lhs = "<leader>tvb",
    cmd = "TableViewOpenBrowser",
    desc = "Open table in browser",
  },
  { id = "tableview_close", lhs = "<leader>tvc", cmd = "TableViewClose", desc = "Close TableView" },
  {
    id = "tableview_mode",
    lhs = "<leader>tvm",
    cmd = "Markdown table mode toggle",
    desc = "Toggle table auto-format mode",
  },
}

--- Install the default editing keymaps for `bufnr`.
--- No-op when `enable_keymaps = false`.
---
--- Per-binding control via `config.keymaps[id]`:
---   * `false`                       -- disable this binding
---   * `"<newlhs>"`                  -- remap to a new key (same mode)
---   * `{ "<lhs1>", "<lhs2>" }`      -- several keys for the same action
---   * `{ lhs = "<newlhs>", mode = ... }` -- remap key and/or mode
--- The legacy boolean flags (`map_double_asterisk`, `map_wrap_link`,
--- `use_zf_override`) still disable their bindings when set to false.
---@param bufnr integer
---@return Lib.Keymap.Registered[]
function M.apply(bufnr)
  if type(bufnr) ~= "number" then return {} end
  if cfg().enable_keymaps == false then return {} end

  local feat = require("markdown.config").feature_enabled
  local overrides = cfg().keymaps or {}

  ---@type table<string, Lib.Keymap.Action>
  local decl = {}
  ---@type string[]
  local order = {}
  ---@type table<string, string|string[]|false>
  local user = {}

  for _, spec in ipairs(DEFAULT_KEYMAPS) do
    -- Legacy flag gate (e.g. map_double_asterisk = false).
    local flag_off = spec.flag and cfg()[spec.flag] == false
    -- Feature gate on the spec's effective feature: most bindings belong to the
    -- general "keymaps" feature, but a few (e.g. toc) carry a finer one so they
    -- can stay active under `just_enable = { "toc" }` even with "keymaps" off.
    local feature_off = not feat(spec.feature or "keymaps")
    local ov = overrides[spec.id]

    local mode = spec.mode
    -- An override may move the binding to another mode. That is the one part
    -- of the override the registry cannot read for itself: it takes the lhs
    -- from the user's table and everything else from the declaration, so the
    -- mode has to be folded into the declaration here.
    if type(ov) == "table" and ov.mode then mode = ov.mode end

    decl[spec.id] = {
      default = spec.lhs,
      mode = mode,
      rhs = actions[spec.action],
      desc = spec.desc,
      opts = { silent = true },
    }
    order[#order + 1] = spec.id

    -- A gate switched off is expressed as "this key is not bound", not as
    -- "there is no such action": `:checkhealth` and the generated docs ask
    -- what EXISTS, and those are different answers.
    if flag_off or feature_off then user[spec.id] = false end
  end

  -- Everything the user wrote that is not a TableView id, whether or not it
  -- names a real action: unknown ids are exactly what the registry reports,
  -- and pre-filtering them out would throw away the typo along with the
  -- report. The TableView ids live in the same table and belong to the other
  -- surface, so they are the one thing removed here.
  local tableview_id = {}
  for _, spec in ipairs(TABLEVIEW_KEYMAPS) do
    tableview_id[spec.id] = true
  end
  for id, ov in pairs(overrides) do
    if not tableview_id[id] and user[id] == nil then user[id] = ov end
  end

  return libkeymap.register(
    "markdown.nvim",
    { order = order, actions = decl },
    user,
    { buffer = bufnr, surface = "editing" }
  )
end

--- The TableView keymap specs, exposed for docs/tooling.
---@return table[]
function M.tableview_defaults() return TABLEVIEW_KEYMAPS end

--- Install the buffer-local TableView keys (`<leader>tv*`) for `bufnr`.
--- These drive the `:TableView*` commands and are independent of enable_keymaps.
---
--- Overridable by id through the same `config.keymaps` table as the editing
--- keys -- they were fixed strings before, which made `<leader>tv*` the one
--- prefix in this plugin nobody could move.
---@param bufnr integer
---@return Lib.Keymap.Registered[]
function M.apply_tableview(bufnr)
  if type(bufnr) ~= "number" then return {} end
  local ft = vim.bo[bufnr].filetype
  if not ft or not ft:match("markdown") then return {} end
  if not require("markdown.config").feature_enabled("tableview") then return {} end

  local overrides = cfg().keymaps or {}

  ---@type table<string, Lib.Keymap.Action>
  local decl = {}
  ---@type string[]
  local order = {}
  ---@type table<string, string|string[]|false>
  local user = {}
  for _, spec in ipairs(TABLEVIEW_KEYMAPS) do
    decl[spec.id] = {
      default = spec.lhs,
      rhs = ("<Cmd>%s<CR>"):format(spec.cmd),
      desc = spec.desc,
      opts = { silent = true },
    }
    order[#order + 1] = spec.id
    if overrides[spec.id] ~= nil then user[spec.id] = overrides[spec.id] end
  end

  return libkeymap.register(
    "markdown.nvim",
    { order = order, actions = decl },
    user,
    { buffer = bufnr, surface = "tableview" }
  )
end

return M
