---@module 'markdown.core.fold'
--- Heading-based `foldexpr` plus the fold-toggle actions bound to keymaps.
local M = {}

---Computes the fold level for line `lnum` (used as `foldexpr`).
---@param lnum integer
---@return string|integer
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)

  local atx = line:match("^%s*(#+)%s+")
  if atx then
    -- Fenced-scope gating (opt-in via fenced_scope.operations.fold). A `#`-line
    -- inside a NON-markdown fenced block is code (e.g. a shell/python comment),
    -- not a heading, so it must not open a fold. Inside a markdown-family fence
    -- it stays a heading (the block is its own sub-document). Zero overhead when
    -- the fold op is disabled — the scope module isn't even consulted.
    local scope = require("markdown.scope")
    if scope.op_enabled("fold") then
      local kind = scope.row_fence_kind(vim.api.nvim_get_current_buf(), lnum - 1)
      if kind == "code" then
        return "="
      end
    end
    return ">" .. #atx
  end

  local prev = vim.fn.getline(lnum - 1)
  if prev and prev:match("^%s*%S") and line:match("^%s*[-=]+%s*$") then
    return ">2"
  end

  return "="
end

--- Resolve the row whose fold should toggle when acting on `row`, covering both
--- heading styles, or nil when `row` is not on a heading. Mirrors `foldexpr`:
---   * ATX (`#`, `##`, …)               → the heading line itself
---   * Setext underline (`===` / `---`) → that line (the fold starts here)
---   * Setext title (next line is an underline) → the underline row
--- Used by the mouse handler so a double-click on either half of a Setext
--- heading toggles the section, not just ATX headings.
---@param bufnr integer
---@param row integer  1-indexed
---@return integer|nil  1-indexed row to toggle, or nil
function M.heading_fold_row(bufnr, row)
  local function get(r)
    if r < 1 then return nil end
    return vim.api.nvim_buf_get_lines(bufnr, r - 1, r, false)[1]
  end

  local line = get(row) or ""

  -- ATX heading.
  if line:match("^%s*#+%s") then return row end

  local is_underline = function(s) return s ~= nil and s:match("^%s*[-=]+%s*$") ~= nil end

  -- Setext underline: a `===`/`---` line under a content line (not itself a
  -- heading or another underline). The fold starts on this line.
  if is_underline(line) then
    local prev = get(row - 1)
    if prev and prev:match("%S") and not prev:match("^%s*#") and not is_underline(prev) then
      return row
    end
  end

  -- Setext title: a content line whose next line is the underline. Toggle at the
  -- underline row (where the fold actually starts).
  if line:match("%S") and not line:match("^%s*#") and not is_underline(line) then
    if is_underline(get(row + 1)) then return row + 1 end
  end

  return nil
end

-- Re-assert the window's fold state before a normal-mode fold command. When
-- these run from a menu callback (nvzone/menu) rather than a keymap, 'foldenable'
-- may be off / the method reset, which makes `za`/`zR` silent no-ops. Mirrors
-- core.fold_levels.fold_levels(), which works from the menu for this reason.
---@internal
local function ensure_folding()
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldenable = true
end

---Toggles the fold under the cursor and centers the view.
---@return nil
function M.toggle_under_cursor()
  ensure_folding()
  vim.cmd("silent! normal! za")
  vim.cmd("silent! normal! zz")
end

---Unfolds everything and centers the view.
---@return nil
function M.unfold_all_center()
  ensure_folding()
  vim.cmd("silent! normal! zR")
  vim.cmd("silent! normal! zz")
end

return M
