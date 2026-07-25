---@module 'markdown.hl_options.hl_groups.blockquote'
local autocmd = require("lib.nvim.autocmd")

local M = {}

local GROUP_MARKER = "MarkdownBlockquoteMarker"
local GROUP_TEXT   = "MarkdownBlockquoteText"
local PRIORITY     = 110
local PAT_MARKER   = [[\v^\s*\>\s*]]
local PAT_TEXT     = [[\v^\s*\>\s*\zs.*$]]
local BUF_VAR_MARKER = "markdown_bq_match_marker"
local BUF_VAR_TEXT   = "markdown_bq_match_text"

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

local function add_match(bufnr)
  local prev_marker = vim.b[bufnr][BUF_VAR_MARKER]
  local prev_text   = vim.b[bufnr][BUF_VAR_TEXT]
  if prev_marker then pcall(vim.fn.matchdelete, prev_marker) end
  if prev_text   then pcall(vim.fn.matchdelete, prev_text)   end

  vim.b[bufnr][BUF_VAR_MARKER] = vim.fn.matchadd(GROUP_MARKER, PAT_MARKER, PRIORITY)
  vim.b[bufnr][BUF_VAR_TEXT]   = vim.fn.matchadd(GROUP_TEXT,   PAT_TEXT,   PRIORITY)
end

function M.apply(opts)
  opts = opts or {}
  local hl = opts.blockquote_hl or {}
  set_hl(hl)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if ft == "markdown" or ft == "markdown.mdx" or ft == "mdx" then
        local wins = vim.fn.win_findbuf(bufnr)
        if #wins > 0 then
          vim.api.nvim_win_call(wins[1], function()
            add_match(bufnr)
          end)
        end
      end
    end
  end
end

function M.setup_autocmds(augroup)
  autocmd.create({ "FileType", "BufEnter" }, function(ev)
    local bufnr = ev.buf
    local ft = vim.bo[bufnr].filetype
    if ft ~= "markdown" and ft ~= "markdown.mdx" and ft ~= "mdx" then return end
    add_match(bufnr)
  end, {
    group   = augroup,
    pattern = { "markdown", "markdown.mdx", "mdx" },
  })
end

return M
