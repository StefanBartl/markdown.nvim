---@module 'markdown.hl_options.hl_groups.blockquote'
local M = {}

local GROUP_MARKER = "MarkdownBlockquoteMarker"
local GROUP_TEXT = "MarkdownBlockquoteText"
local PRIORITY = 110
local NS = vim.api.nvim_create_namespace("MarkdownNvimBlockquote")

-- Matches a single leading blockquote marker: optional indent, `>`, optional
-- following spaces. Deliberately not repeated (`(>%s*)+`), so nested markers
-- (`> > text`) colorize like the vim-regex predecessor: only the first `>` is
-- "marker", the rest (including a second `>`) is "text".
local PAT_MARKER = "^%s*>%s*"

-- How far the text background reaches (`blockquote_hl.width`):
--   "block"  (default) the widest line of the contiguous `>` block, so the
--            quote reads as one box instead of a bar across the whole window
--   "line"   only as far as each line's own text
--   "window" to the window edge (the original VS Code-style behaviour)
--   <n>      at least `n` display columns (a longer line is never cut)
local DEFAULT_WIDTH = "block"
local state = { width = DEFAULT_WIDTH }

-- bufnr -> { tick = changedtick, rows = { [row] = block width in columns } }.
-- The decoration provider asks once per visible line on every redraw; the
-- block is only scanned on the first ask for a row after the buffer changed.
local block_cache = {}

local function dim_bg(fg)
  local r = tonumber(fg:sub(2, 3), 16) or 0x6A
  local g = tonumber(fg:sub(4, 5), 16) or 0x99
  local b = tonumber(fg:sub(6, 7), 16) or 0x55
  return string.format(
    "#%02x%02x%02x",
    math.floor(r * 0.20),
    math.floor(g * 0.20),
    math.floor(b * 0.20)
  )
end

--- First resolved (non-nil) `fg` among `groups`, as "#rrggbb"; `fallback` when
--- none of them resolve (e.g. no colorscheme loaded yet).
---@param groups string[]
---@param fallback string
---@return string
local function pick_group_fg(groups, fallback)
  for _, g in ipairs(groups) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = g, link = false })
    if ok and hl and hl.fg then return string.format("#%06x", hl.fg) end
  end
  return fallback
end

-- Theme-derived defaults, used only when config.blockquote_hl doesn't set an
-- explicit hex value: a markdown-specific highlight first, broadly-available
-- generic groups next, and the historical hard-coded hex as the last resort.
local function theme_marker_fg()
  return pick_group_fg({ "@markup.quote.markdown", "@text.quote", "Comment" }, "#6A9955")
end

local function theme_text_fg()
  return pick_group_fg({ "@markup.quote.markdown", "@text.quote", "String" }, "#7EE787")
end

---@param v any
---@return "block"|"line"|"window"|integer
local function normalize_width(v)
  if v == "block" or v == "line" or v == "window" then return v end
  if type(v) == "number" and v >= 0 then return math.floor(v) end
  return DEFAULT_WIDTH
end

---@param bufnr integer
---@param row integer 0-indexed
---@return string|nil
local function quote_line(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if line and line:find(PAT_MARKER) then return line end
  return nil
end

--- Display width of the widest line in the contiguous blockquote block that
--- contains `row` (a blank line or any non-`>` line ends a block).
---@param bufnr integer
---@param row integer 0-indexed, must be a quote line
---@return integer
local function block_width(bufnr, row)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache = block_cache[bufnr]
  if not cache or cache.tick ~= tick then
    cache = { tick = tick, rows = {} }
    block_cache[bufnr] = cache
  end
  if cache.rows[row] then return cache.rows[row] end

  local first, last = row, row
  while first > 0 and quote_line(bufnr, first - 1) do
    first = first - 1
  end
  local count = vim.api.nvim_buf_line_count(bufnr)
  while last < count - 1 and quote_line(bufnr, last + 1) do
    last = last + 1
  end

  local width = 0
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, first, last + 1, false)) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  for r = first, last do
    cache.rows[r] = width
  end
  return width
end

local function set_hl(hl)
  local marker_fg = hl.marker_fg or hl.fg or theme_marker_fg()
  state.width = normalize_width(hl.width)

  local text_bg = nil
  if hl.text_bg == "dimm" then
    text_bg = dim_bg(marker_fg)
  elseif hl.text_bg ~= nil then
    text_bg = hl.text_bg
  end

  if hl.link then
    vim.api.nvim_set_hl(0, GROUP_MARKER, { link = hl.link })
    vim.api.nvim_set_hl(0, GROUP_TEXT, { link = hl.link })
    return
  end

  vim.api.nvim_set_hl(0, GROUP_MARKER, {
    fg = marker_fg,
    bold = hl.marker_bold or false,
    italic = hl.marker_italic or false,
  })

  vim.api.nvim_set_hl(0, GROUP_TEXT, {
    fg = hl.text_fg or theme_text_fg(),
    bg = text_bg,
    italic = hl.text_italic or false,
    bold = hl.text_bold or false,
  })
end

---@param bufnr integer
---@return boolean
local function is_blockquote_ft(bufnr)
  local ft = vim.bo[bufnr].filetype
  return ft == "markdown" or ft == "markdown.mdx" or ft == "mdx"
end

--- Place the marker/text extmarks for buffer line `row` (0-indexed), if it is
--- a blockquote line. How far the background reaches past the last character
--- is `blockquote_hl.width`: `"window"` uses `hl_eol` (to the window edge),
--- `"block"`/`<n>` pad with highlighted spaces up to the block's widest line /
--- `n` columns via an end-of-line virtual text, `"line"` adds nothing.
---@param bufnr integer
---@param row integer 0-indexed
function M.highlight_line(bufnr, row)
  -- Clear this row's previous extmarks first: nvim_buf_set_extmark below
  -- always creates a new mark rather than reusing one, so without this a
  -- line that stops being a blockquote (e.g. the leading `>` is deleted)
  -- would keep its stale highlight forever instead of losing it on redraw.
  --
  -- nvim_buf_clear_namespace(bufnr, NS, row, row + 1) is NOT safe here: the
  -- text extmark below spans to (row + 1, 0) so that hl_eol can fill past
  -- the last character, which makes it also start at `row`. Clearing the
  -- *next* row's range then deletes THIS row's still-valid text extmark
  -- (verified: it clears marks that merely overlap the range, not just
  -- ones starting in it). Deleting by id, scoped to marks that actually
  -- start at this row, avoids clobbering a neighboring row's marks.
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, NS, { row, 0 }, { row, -1 }, {})) do
    vim.api.nvim_buf_del_extmark(bufnr, NS, m[1])
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then return end

  local _, marker_end = line:find(PAT_MARKER)
  if not marker_end then return end -- not a blockquote line

  vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
    end_col = marker_end,
    hl_group = GROUP_MARKER,
    priority = PRIORITY,
    strict = false,
  })
  local mode = state.width
  if mode == "window" then
    vim.api.nvim_buf_set_extmark(bufnr, NS, row, marker_end, {
      end_row = row + 1,
      end_col = 0,
      hl_group = GROUP_TEXT,
      hl_eol = true, -- extend the background past the text to the window edge
      priority = PRIORITY,
      strict = false,
    })
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, NS, row, marker_end, {
    end_col = #line,
    hl_group = GROUP_TEXT,
    priority = PRIORITY,
    strict = false,
  })

  local target = mode == "line" and 0
    or (type(mode) == "number" and mode or block_width(bufnr, row))
  local pad = target - vim.fn.strdisplaywidth(line)
  if pad > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, NS, row, #line, {
      virt_text = { { string.rep(" ", pad), GROUP_TEXT } },
      virt_text_pos = "eol",
      hl_mode = "combine",
      priority = PRIORITY,
      strict = false,
    })
  end
end

-- Registered once: highlighting itself is driven by a decoration provider
-- (below), which re-evaluates every visible line on each redraw. That makes
-- it "live" the same way the old `matchadd`-based version was — no manual
-- re-scan needed on text change — while also supporting `hl_eol`, which
-- `matchadd` cannot do.
local _registered = false
local function ensure_decoration_provider()
  if _registered then return end
  _registered = true
  vim.api.nvim_set_decoration_provider(NS, {
    on_win = function(_, _, bufnr, _, _) return is_blockquote_ft(bufnr) end,
    on_line = function(_, _, bufnr, row) M.highlight_line(bufnr, row) end,
  })
end

function M.apply(opts)
  opts = opts or {}
  set_hl(opts.blockquote_hl or {})
  ensure_decoration_provider()
end

--- Highlighting needs no per-buffer FileType/BufEnter tracking (see
--- `ensure_decoration_provider`); the only autocmd is the wipe cleanup of the
--- block-width cache.
---@param augroup integer
function M.setup_autocmds(augroup)
  -- Only the width cache needs tracking: drop a buffer's entry when it goes away.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    desc = "[markdown.nvim] blockquote: drop the block-width cache of a wiped buffer",
    callback = function(ev) block_cache[ev.buf] = nil end,
  })
end

return M
