---@module 'markdown.hl_options.hl_groups.blockquote'
local M = {}

local GROUP_MARKER = "MarkdownBlockquoteMarker"
local GROUP_TEXT   = "MarkdownBlockquoteText"
local PRIORITY     = 110
local NS           = vim.api.nvim_create_namespace("MarkdownNvimBlockquote")

-- Matches a single leading blockquote marker: optional indent, `>`, optional
-- following spaces. Deliberately not repeated (`(>%s*)+`), so nested markers
-- (`> > text`) colorize like the vim-regex predecessor: only the first `>` is
-- "marker", the rest (including a second `>`) is "text".
local PAT_MARKER = "^%s*>%s*"

local function dim_bg(fg)
  local r = tonumber(fg:sub(2, 3), 16) or 0x6A
  local g = tonumber(fg:sub(4, 5), 16) or 0x99
  local b = tonumber(fg:sub(6, 7), 16) or 0x55
  return string.format("#%02x%02x%02x",
    math.floor(r * 0.20), math.floor(g * 0.20), math.floor(b * 0.20))
end

--- First resolved (non-nil) `fg` among `groups`, as "#rrggbb"; `fallback` when
--- none of them resolve (e.g. no colorscheme loaded yet).
---@param groups string[]
---@param fallback string
---@return string
local function pick_group_fg(groups, fallback)
  for _, g in ipairs(groups) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = g, link = false })
    if ok and hl and hl.fg then
      return string.format("#%06x", hl.fg)
    end
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

local function set_hl(hl)
  local marker_fg = hl.marker_fg or hl.fg or theme_marker_fg()

  local text_bg = nil
  if hl.text_bg == "dimm" then
    text_bg = dim_bg(marker_fg)
  elseif hl.text_bg ~= nil then
    text_bg = hl.text_bg
  end

  if hl.link then
    vim.api.nvim_set_hl(0, GROUP_MARKER, { link = hl.link })
    vim.api.nvim_set_hl(0, GROUP_TEXT,   { link = hl.link })
    return
  end

  vim.api.nvim_set_hl(0, GROUP_MARKER, {
    fg     = marker_fg,
    bold   = hl.marker_bold   or false,
    italic = hl.marker_italic or false,
  })

  vim.api.nvim_set_hl(0, GROUP_TEXT, {
    fg     = hl.text_fg or theme_text_fg(),
    bg     = text_bg,
    italic = hl.text_italic or false,
    bold   = hl.text_bold   or false,
  })
end

---@param bufnr integer
---@return boolean
local function is_blockquote_ft(bufnr)
  local ft = vim.bo[bufnr].filetype
  return ft == "markdown" or ft == "markdown.mdx" or ft == "mdx"
end

--- Place the marker/text extmarks for buffer line `row` (0-indexed), if it is
--- a blockquote line. The text extmark uses `hl_eol = true`, so its background
--- fills the rest of the screen line past the last character — a VS Code-style
--- whole-line background, not just a highlight behind the actual text glyphs.
---@param bufnr integer
---@param row integer 0-indexed
function M.highlight_line(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then return end

  local _, marker_end = line:find(PAT_MARKER)
  if not marker_end then return end -- not a blockquote line

  vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
    end_col  = marker_end,
    hl_group = GROUP_MARKER,
    priority = PRIORITY,
    strict   = false,
  })
  vim.api.nvim_buf_set_extmark(bufnr, NS, row, marker_end, {
    end_row  = row + 1,
    end_col  = 0,
    hl_group = GROUP_TEXT,
    hl_eol   = true, -- extend the background past the text to the window edge
    priority = PRIORITY,
    strict   = false,
  })
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
    on_win = function(_, _, bufnr, _, _)
      return is_blockquote_ft(bufnr)
    end,
    on_line = function(_, _, bufnr, row)
      M.highlight_line(bufnr, row)
    end,
  })
end

function M.apply(opts)
  opts = opts or {}
  set_hl(opts.blockquote_hl or {})
  ensure_decoration_provider()
end

--- No-op: highlighting no longer needs per-buffer FileType/BufEnter tracking
--- (see `ensure_decoration_provider`). Kept so `hl_options/init.lua` doesn't
--- need to change its call sequence (it still passes the augroup id).
---@param _augroup integer
---@diagnostic disable-next-line: unused-local
function M.setup_autocmds(_augroup) end

return M
