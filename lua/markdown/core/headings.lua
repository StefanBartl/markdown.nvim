---@module 'markdown.core.headings'
--- Heading navigation (prev/next, by-level) and heading-level shifting.
local M = {}

local api, fn = vim.api, vim.fn
local cfg = require("markdown.config").get

-- `#\+` (one-or-more) so H1 is included; the old `##\+` (two-or-more) meant
-- goto_*_heading could never reach a level-1 heading.
local ANY_HEADING = "^#\\+\\s\\+.*$"

-- A fenced-code delimiter line: three-or-more backticks or tildes at the start
-- of the line, indent allowed, info string optional -- so both the opening
-- ```lang and its bare closing ``` match. `~` is escaped because in Vim's magic
-- mode a bare `~` means "the last substitute string", not a tilde character.
local FENCE_DELIM = "^\\s*\\%(`\\{3,}\\|\\~\\{3,}\\)"

-- Headings *or* fence delimiters, for the prev/next-heading keys.
local HEADING_OR_FENCE = "\\%(" .. ANY_HEADING .. "\\)\\|\\%(" .. FENCE_DELIM .. "\\)"

--- The pattern one prev/next-heading hop searches for: headings alone, or
--- headings plus fenced-code delimiters when `nav.fences` is on (the default).
---
--- A code block's two delimiter lines are the landmarks of a markdown file that
--- headings do not cover, and reaching one with the key that already walks
--- headings is the point. The by-level hops (`<leader><C-p>`/`<leader><C-f>`)
--- deliberately stay headings-only, so heading-only navigation is still one
--- keystroke away.
---@internal
---@return string
local function nav_pattern()
  local nav = cfg().nav
  if nav and nav.fences == false then return ANY_HEADING end
  return HEADING_OR_FENCE
end

---@internal
---@param level integer
---@return string
local function level_pattern(level) return "^" .. string.rep("#", level) .. "\\s\\+.*$" end

--- Move to `lnum`, restoring `col` (clipped to the line's length by `cursor()`)
--- so heading nav keeps the cursor's horizontal position instead of snapping
--- to column 1.
---@internal
---@param lnum integer
---@param col integer
local function restore_col(lnum, col) fn.cursor(lnum, col) end

--- Backward `fn.search` that never matches the line the cursor is already on.
---
--- Every nav pattern is `^`-anchored, so from any column past the first a plain
--- backward search matches the *start of the current line* whenever the cursor
--- sits on a heading or a fence delimiter -- and the hop then never leaves that
--- line (a `<C-p>` on a fenced block's `` ``` `` looped in place). `search()`
--- never accepts a match at the exact cursor position without the `c` flag, so
--- starting from column 1 lets it skip the cursor line and reach the previous
--- landmark. The caller restores the real column afterwards via `restore_col`.
---@internal
---@param pattern string
---@param flags string `fn.search` flags -- must contain `b`
---@return integer lnum
local function search_back(pattern, flags)
  fn.cursor(fn.line("."), 1)
  return fn.search(pattern, flags)
end

--- Resolve the fenced-block scope for `op`, or nil when scoping is off for it
--- (feature disabled or that op opted out) — callers then use the plain,
--- whole-buffer `fn.search` path, so behavior is unchanged when disabled.
---@internal
---@param op "nav"
---@return Mkdn.Scope|nil
local function op_scope(op)
  local scope = require("markdown.scope")
  if not scope.op_enabled(op) then return nil end
  return scope.detect()
end

--- One scope-bounded heading hop. Uses `fn.search`'s stopline to stay within
--- `scope.first`/`scope.last`, and skips matches that fall inside an excluded
--- fenced interior (buffer scope). Moves the cursor to the match on success;
--- on failure the cursor is restored to where the hop started, so a partial
--- count loop leaves it on the last real heading it reached.
---@internal
---@param pattern string Vim regex for the heading(s) to match
---@param backward boolean Search direction
---@param scope Mkdn.Scope
---@return integer lnum Matched line (1-indexed), or 0 if none in scope
local function scoped_search(pattern, backward, scope)
  local scope_mod = require("markdown.scope")
  local flags = (backward and "bW" or "W") .. "s"
  local stopline = backward and scope.first or scope.last
  local view = fn.winsaveview()
  -- Same `^`-anchor trap as `search_back`: a backward hop from a column past
  -- the first would match the current line's own start. Step to column 1 so
  -- `search()` skips it; the failure path below restores the view (column
  -- included) and the success path leaves `restore_col` to the caller.
  if backward then fn.cursor(fn.line("."), 1) end
  while true do
    local lnum = fn.search(pattern, flags, stopline)
    if lnum == 0 or lnum < scope.first or lnum > scope.last then
      fn.winrestview(view)
      return 0
    end
    if not scope_mod.is_excluded(scope, lnum) then return lnum end
    -- Match sits inside an excluded fenced interior: keep searching from here.
  end
end

---Moves to the previous heading -- or fenced-code delimiter, unless
---`nav.fences = false` -- `vim.v.count1` times.
---@return nil
function M.goto_prev_heading()
  local pattern = nav_pattern()
  local scope = op_scope("nav")
  if not scope then
    local col, from = fn.col("."), fn.line(".")
    local moved = false
    for _ = 1, vim.v.count1 do
      if search_back(pattern, "bWs") == 0 then break end
      moved = true
    end
    restore_col(moved and fn.line(".") or from, col)
    vim.cmd("nohlsearch")
    return
  end

  local col = fn.col(".")
  local moved = false
  for _ = 1, vim.v.count1 do
    if scoped_search(pattern, true, scope) == 0 then break end
    moved = true
  end
  if moved then restore_col(fn.line("."), col) end
  vim.cmd("nohlsearch")
end

---Moves to the next heading -- or fenced-code delimiter, unless
---`nav.fences = false` -- `vim.v.count1` times.
---@return nil
function M.goto_next_heading()
  local pattern = nav_pattern()
  local scope = op_scope("nav")
  if not scope then
    local col = fn.col(".")
    local moved = false
    for _ = 1, vim.v.count1 do
      if fn.search(pattern, "Ws") == 0 then break end
      moved = true
    end
    if moved then restore_col(fn.line("."), col) end
    vim.cmd("nohlsearch")
    return
  end

  local col = fn.col(".")
  local moved = false
  for _ = 1, vim.v.count1 do
    if scoped_search(pattern, false, scope) == 0 then break end
    moved = true
  end
  if moved then restore_col(fn.line("."), col) end
  vim.cmd("nohlsearch")
end

---Moves to the previous heading at `vim.v.count` level (any level if 0).
---@return nil
function M.goto_prev_heading_level()
  local count = vim.v.count
  local pattern = count > 0 and level_pattern(count) or ANY_HEADING
  local col, from = fn.col("."), fn.line(".")
  local scope = op_scope("nav")
  if not scope then
    restore_col(search_back(pattern, "bWs") ~= 0 and fn.line(".") or from, col)
    vim.cmd("nohlsearch")
    return
  end
  if scoped_search(pattern, true, scope) ~= 0 then restore_col(fn.line("."), col) end
  vim.cmd("nohlsearch")
end

---Moves to the next heading at `vim.v.count` level (any level if 0).
---@return nil
function M.goto_next_heading_level()
  local count = vim.v.count
  local pattern = count > 0 and level_pattern(count) or ANY_HEADING
  local col = fn.col(".")
  local scope = op_scope("nav")
  if not scope then
    if fn.search(pattern, "Ws") ~= 0 then restore_col(fn.line("."), col) end
    vim.cmd("nohlsearch")
    return
  end
  if scoped_search(pattern, false, scope) ~= 0 then restore_col(fn.line("."), col) end
  vim.cmd("nohlsearch")
end

---@internal
---@param line string
---@param delta integer
---@param min_level integer
---@param allow_creation boolean
---@return string out
---@return boolean changed
local function shift_heading_line(line, delta, min_level, allow_creation)
  if line == "" or line:match("^%s*$") then return line, false end

  local hashes, rest = line:match("^(%s*#+)%s+(.*)$")

  if not hashes then
    if delta > 0 and allow_creation then return "# " .. line, true end
    return line, false
  end

  local indent = hashes:match("^%s*") or ""
  local level = #hashes - #indent

  if level == 1 and delta < 0 then return rest, true end

  local new_level = math.max(min_level, math.min(6, level + delta))
  if new_level == level then return line, false end

  return string.format("%s%s %s", indent, string.rep("#", new_level), rest), true
end

---@internal
---@param bufnr integer
---@param srow integer
---@param erow integer
---@param delta integer
---@param min_level integer
---@param allow_creation boolean
---@return integer changed
local function shift_range_internal(bufnr, srow, erow, delta, min_level, allow_creation)
  local lines = api.nvim_buf_get_lines(bufnr, srow - 1, erow, false)
  local changed = 0
  local in_fence = false
  -- A fenced-code delimiter line: 3+ backticks or 3+ tildes, then an optional
  -- info string. NOTE: `{3,}` is NOT a Lua-pattern quantifier (it matches the
  -- literal characters `{3,}`), so we spell out three-or-more explicitly. Without
  -- this, `#`-prefixed lines inside code fences (shell comments, nested markdown)
  -- were wrongly treated as headings and shifted.
  local fence_pat = "^%s*[`~][`~][`~]+%S*%s*$"

  for i = 1, #lines do
    local line = lines[i]
    local fence = line:match(fence_pat)
    if fence then in_fence = not in_fence end
    if not in_fence then
      local out, did = shift_heading_line(line, delta, min_level, allow_creation)
      if did then
        lines[i] = out
        changed = changed + 1
      end
    end
  end

  if changed > 0 then api.nvim_buf_set_lines(bufnr, srow - 1, erow, false, lines) end

  return changed
end

---Shifts every heading's level in `[srow, erow]` by `delta`.
---@param srow integer
---@param erow integer
---@param delta integer
---@return integer changed
function M.shift_range(srow, erow, delta)
  if type(srow) ~= "number" or type(erow) ~= "number" then return 0 end
  if srow < 1 or erow < srow then return 0 end
  if type(delta) ~= "number" or delta == 0 then return 0 end
  if vim.bo.filetype ~= "markdown" then return 0 end

  local bufnr = api.nvim_get_current_buf()
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return 0 end

  local min_level = cfg().protect_h1 and 2 or 1
  local allow_creation = (srow == erow)

  local view = fn.winsaveview()
  local changed = shift_range_internal(bufnr, srow, erow, delta, min_level, allow_creation)
  if changed > 0 then fn.winrestview(view) end

  return changed
end

---Shifts every heading in the current visual selection by `delta`.
---@param delta integer
---@return nil
function M.shift_visual_selection(delta)
  if type(delta) ~= "number" or delta == 0 then return end
  if vim.bo.filetype ~= "markdown" then return end

  local bufnr = api.nvim_get_current_buf()
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return end

  local start_line = fn.line("v")
  local end_line = fn.line(".")
  local srow = math.min(start_line, end_line)
  local erow = math.max(start_line, end_line)

  vim.cmd("normal! \\<Esc>")

  if srow > 0 and erow > 0 then M.shift_range(srow, erow, delta) end
end

---@internal
---@return integer
local function op_get_repeat()
  local n = vim.b._markdown_heading_op_count
  if type(n) ~= "number" or n < 1 then return 1 end
  vim.b._markdown_heading_op_count = nil
  return n
end

---@internal
---@param _ string operator-func type char (unused).
function M._op_increase(_)
  local n = op_get_repeat()
  local srow = api.nvim_buf_get_mark(0, "[")[1]
  local erow = api.nvim_buf_get_mark(0, "]")[1]
  if srow and erow and srow > 0 and erow > 0 then
    M.shift_range(math.min(srow, erow), math.max(srow, erow), n)
  end
end

---@internal
---@param _ string operator-func type char (unused).
function M._op_decrease(_)
  local n = op_get_repeat()
  local srow = api.nvim_buf_get_mark(0, "[")[1]
  local erow = api.nvim_buf_get_mark(0, "]")[1]
  if srow and erow and srow > 0 and erow > 0 then
    M.shift_range(math.min(srow, erow), math.max(srow, erow), -n)
  end
end

return M
