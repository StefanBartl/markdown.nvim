---@module 'markdown.util.view_track'
---@brief Keep every window's view still while lines of a buffer are edited.
---@description
--- Rewriting lines that sit *above* what a window shows (a TOC, a section
--- separator) makes the text jump when that window's `topline` lies inside the
--- rewritten range: deleting the range clamps `topline` to its start, and
--- re-inserting new lines does not bring the old offset back. It happens on
--- BufWritePre (`refs.reconcile` refreshes the TOC on every save), so it looks
--- like the file "jumps" whenever anything in it changed.
---
--- Neovim alone cannot fix this after the fact, because by then the original
--- `topline` is gone. This module snapshots the view of every window on the
--- buffer up front, records each edit as (range, line-count delta), and maps
--- the snapshot through those edits afterwards:
---
---   local track = view_track.begin(bufnr)
---   track.set_lines(first0, last0, lines)   -- instead of nvim_buf_set_lines
---   ...
---   track.restore()
---
--- A line above an edit stays put, a line below it moves by the edit's delta,
--- a line *inside* a replaced range keeps its number (clamped to the buffer).
--- All edits made between `begin` and `restore` must go through
--- `track.set_lines`, otherwise the mapping is off by whatever bypassed it.

local api = vim.api

local M = {}

---@class Mkdn.ViewTrack
---@field set_lines fun(start: integer, end_: integer, lines: string[])  same arguments as `nvim_buf_set_lines(bufnr, start, end_, false, lines)`
---@field restore fun()  put every window back; a no-op when nothing was edited

---@internal
---@param edits { last: integer, delta: integer }[]
---@param n integer  1-based line, in the coordinates from before the first edit
---@return integer
local function remap(edits, n)
  -- Sequential on purpose: each edit was recorded in the coordinates that were
  -- current when it ran, i.e. after all edits before it.
  for _, e in ipairs(edits) do
    if n > e.last then n = n + e.delta end
  end
  return n
end

--- Snapshot the view of every window showing `bufnr`.
---@param bufnr integer
---@return Mkdn.ViewTrack
function M.begin(bufnr)
  ---@type { win: integer, view: table }[]
  local saved = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    saved[#saved + 1] = { win = win, view = api.nvim_win_call(win, vim.fn.winsaveview) }
  end

  ---@type { last: integer, delta: integer }[]
  local edits = {}

  ---@type Mkdn.ViewTrack
  return {
    set_lines = function(start, end_, lines)
      api.nvim_buf_set_lines(bufnr, start, end_, false, lines)
      -- 0-based half-open [start, end_) is 1-based inclusive [start + 1, end_];
      -- a pure insert (start == end_) is the empty range ending at `start`.
      edits[#edits + 1] = { last = end_, delta = #lines - (end_ - start) }
    end,

    restore = function()
      if #edits == 0 then return end
      for _, s in ipairs(saved) do
        if api.nvim_win_is_valid(s.win) then
          local last = api.nvim_buf_line_count(api.nvim_win_get_buf(s.win))
          local view = s.view
          view.lnum = math.max(1, math.min(remap(edits, view.lnum), last))
          view.topline = math.max(1, math.min(remap(edits, view.topline), last))
          pcall(api.nvim_win_call, s.win, function() vim.fn.winrestview(view) end)
        end
      end
    end,
  }
end

return M
