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

---@internal
local function head() return require("markdown.core.headings") end
---@internal
local function fold() return require("markdown.core.fold") end
---@internal
local function fold_prev() return require("markdown.core.fold_prev") end
---@internal
local function fold_lvl() return require("markdown.core.fold_levels") end
---@internal
local function wrap() return require("markdown.core.wrap") end
---@internal
local function wrap_link() return require("markdown.core.wrap_link") end
---@internal
local function handler() return require("markdown.handler") end
---@internal
local function image() return require("markdown.handler.image") end
---@internal
local function anchor() return require("markdown.anchor.jump") end

-- Bold / link wrap ----------------------------------------------------------

---Toggles bold (`**`) on the current visual selection.
function M.toggle_bold_visual() wrap().toggle_visual_bold() end
---Wraps the word under the cursor in a markdown link (normal mode).
function M.wrap_link_normal() wrap_link().wrap_normal() end
---Wraps the current visual selection in a markdown link.
function M.wrap_link_visual() wrap_link().wrap_visual() end

-- Heading navigation --------------------------------------------------------

---Moves the cursor to the previous heading.
function M.prev_heading() head().goto_prev_heading() end
---Moves the cursor to the next heading.
function M.next_heading() head().goto_next_heading() end
---Moves the cursor to the previous heading at the current level.
function M.prev_heading_level() head().goto_prev_heading_level() end
---Moves the cursor to the next heading at the current level.
function M.next_heading_level() head().goto_next_heading_level() end

-- Folding -------------------------------------------------------------------

---Toggles the fold under the cursor.
function M.fold_toggle() fold().toggle_under_cursor() end
---Unfolds everything and centers the view.
function M.unfold_all() fold().unfold_all_center() end
---Folds the previous heading's section, then centers the view.
function M.fold_prev_heading() fold_prev().fold_prev_heading_then_center() end
---Folds every H2-and-deeper heading.
function M.fold_h2plus() fold_lvl().fold_h2_plus() end

-- TOC (count = max heading level) -------------------------------------------

---Inserts/refreshes the TOC. `vim.v.count` (if > 0) sets `max_level`.
function M.toc()
  local count = vim.v.count
  require("markdown.commands.toc").update(nil, count > 0 and { max_level = count } or nil)
end

-- Cursor action / image / anchor --------------------------------------------

---Runs the cursor action under the cursor (link/image/anchor/heading, etc).
function M.cursor_action() handler().handle_cursor_action() end
-- Mouse-triggered variant: a miss is a normal/frequent outcome (moving the
-- mouse over prose), so suppress the "nothing found" notification. `mouse`
-- also routes a double-click on a heading to a fold toggle (see the handler).
---Mouse-triggered variant of `cursor_action`: silent misses, double-click-to-fold.
function M.cursor_action_mouse() handler().handle_cursor_action({ silent = true, mouse = true }) end
---Opens the image under the cursor.
function M.open_image() image().open() end
---Jumps to the anchor under the cursor.
function M.jump_anchor() anchor().jump() end

-- Heading level shift (count = number of levels) ----------------------------

---Shifts the current line's heading down `vim.v.count1` levels.
function M.heading_inc()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  head().shift_range(row, row, vim.v.count1)
end
---Shifts the current line's heading up `vim.v.count1` levels.
function M.heading_dec()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  head().shift_range(row, row, -vim.v.count1)
end
---Shifts every heading in the visual selection down `vim.v.count1` levels.
function M.heading_inc_visual() head().shift_visual_selection(vim.v.count1) end
---Shifts every heading in the visual selection up `vim.v.count1` levels.
function M.heading_dec_visual() head().shift_visual_selection(-vim.v.count1) end

-- Whole-buffer heading shift. When the cursor is inside a markdown-family
-- fenced block, "all" means all headings *in that block* instead.
---@internal
---@param delta integer Levels to shift by (negative shifts up).
local function shift_all(delta)
  local scope = require("markdown.scope")
  local sc = scope.op_enabled("shift") and scope.detect() or nil
  if sc and sc.kind == "block" then
    head().shift_range(sc.first, sc.last, delta)
  else
    head().shift_range(1, vim.api.nvim_buf_line_count(0), delta)
  end
end

---Shifts every heading in the buffer (or scoped block) down `vim.v.count1` levels.
function M.heading_inc_all() shift_all(vim.v.count1) end
---Shifts every heading in the buffer (or scoped block) up `vim.v.count1` levels.
function M.heading_dec_all() shift_all(-vim.v.count1) end

-- Table (mode / cell motions, count = number of cells to move) --------------

-- table_mode's next_cell()/prev_cell() move at most one cell and report
-- success only via cursor movement (no return value), so a failed/no-op hop
-- is detected by comparing the cursor before and after each iteration —
-- matching the "don't error past the edge" behavior used elsewhere (e.g.
-- headings.goto_prev_heading's search-based loop just breaks on failure).
---@internal
---@param move fun() Single-cell move to repeat (`table_mode.next_cell`/`prev_cell`).
local function repeat_cell_move(move)
  local win = vim.api.nvim_get_current_win()
  for _ = 1, vim.v.count1 do
    local before = vim.api.nvim_win_get_cursor(win)
    move()
    local after = vim.api.nvim_win_get_cursor(win)
    if before[1] == after[1] and before[2] == after[2] then break end
  end
end

---Moves to the next table cell, repeated `vim.v.count1` times.
function M.table_next_cell() repeat_cell_move(require("markdown.core.table_mode").next_cell) end
---Moves to the previous table cell, repeated `vim.v.count1` times.
function M.table_prev_cell() repeat_cell_move(require("markdown.core.table_mode").prev_cell) end
---Toggles table mode for the current buffer.
function M.table_mode_toggle() require("markdown.core.table_mode").toggle() end

return M
