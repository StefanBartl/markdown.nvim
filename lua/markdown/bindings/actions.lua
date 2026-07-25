---@module 'markdown.bindings.actions'
---@brief Named editing actions — the single implementation surface for keymaps.
---@description
--- Every user-facing editing action is a plain function here. The default keys
--- (`markdown.bindings.keymaps`) bind straight onto these, and the table is
--- re-exported as `require("markdown").actions` so users can map their own
--- keys without any `<Plug>` indirection, e.g.:
--- >
---   vim.keymap.set("n", "<F2>", require("markdown").actions.fold_toggle,
---     { buffer = true, desc = "Fold toggle" })
--- <
--- Actions read `vim.v.count` / `vim.v.count1` directly, so counts work exactly
--- as they did through the old `<Plug>` layer.

local M = {}

local function head()      return require("markdown.core.headings") end
local function fold()      return require("markdown.core.fold") end
local function fold_prev() return require("markdown.core.fold_prev") end
local function fold_lvl()  return require("markdown.core.fold_levels") end
local function wrap()      return require("markdown.core.wrap") end
local function wrap_link() return require("markdown.core.wrap_link") end
local function handler()   return require("markdown.handler") end
local function image()     return require("markdown.handler.image") end
local function anchor()    return require("markdown.anchor.jump") end

-- Bold / link wrap ----------------------------------------------------------

function M.toggle_bold_visual() wrap().toggle_visual_bold() end
function M.wrap_link_normal()   wrap_link().wrap_normal() end
function M.wrap_link_visual()   wrap_link().wrap_visual() end

-- Heading navigation --------------------------------------------------------

function M.prev_heading()       head().goto_prev_heading() end
function M.next_heading()       head().goto_next_heading() end
function M.prev_heading_level() head().goto_prev_heading_level() end
function M.next_heading_level() head().goto_next_heading_level() end

-- Folding -------------------------------------------------------------------

function M.fold_toggle()       fold().toggle_under_cursor() end
function M.unfold_all()        fold().unfold_all_center() end
function M.fold_prev_heading() fold_prev().fold_prev_heading_then_center() end
function M.fold_h2plus()       fold_lvl().fold_h2_plus() end

-- TOC (count = max heading level) -------------------------------------------

function M.toc()
  local count = vim.v.count
  require("markdown.commands.toc").update(
    nil,
    count > 0 and { max_level = count } or nil
  )
end

-- Cursor action / image / anchor --------------------------------------------

function M.cursor_action()       handler().handle_cursor_action() end
-- Mouse-triggered variant: a miss is a normal/frequent outcome (moving the
-- mouse over prose), so suppress the "nothing found" notification. `mouse`
-- also routes a double-click on a heading to a fold toggle (see the handler).
function M.cursor_action_mouse() handler().handle_cursor_action({ silent = true, mouse = true }) end
function M.open_image()          image().open() end
function M.jump_anchor()         anchor().jump() end

-- Heading level shift (count = number of levels) ----------------------------

function M.heading_inc()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  head().shift_range(row, row, vim.v.count1)
end
function M.heading_dec()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  head().shift_range(row, row, -vim.v.count1)
end
function M.heading_inc_visual() head().shift_visual_selection(vim.v.count1) end
function M.heading_dec_visual() head().shift_visual_selection(-vim.v.count1) end

-- Whole-buffer heading shift. When the cursor is inside a markdown-family
-- fenced block, "all" means all headings *in that block* instead.
local function shift_all(delta)
  local scope = require("markdown.scope")
  local sc = scope.op_enabled("shift") and scope.detect() or nil
  if sc and sc.kind == "block" then
    head().shift_range(sc.first, sc.last, delta)
  else
    head().shift_range(1, vim.api.nvim_buf_line_count(0), delta)
  end
end

function M.heading_inc_all() shift_all(vim.v.count1) end
function M.heading_dec_all() shift_all(-vim.v.count1) end

-- Table (mode / cell motions) -----------------------------------------------

function M.table_next_cell()   require("markdown.core.table_mode").next_cell() end
function M.table_prev_cell()   require("markdown.core.table_mode").prev_cell() end
function M.table_mode_toggle() require("markdown.core.table_mode").toggle() end

return M
