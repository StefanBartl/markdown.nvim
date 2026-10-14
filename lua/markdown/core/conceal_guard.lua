---@module 'markdown.core.conceal_guard'
---@brief Raises `conceallevel` in the windows showing a buffer and puts it back.
---@description
--- The display-only features (table grid, table truncate, native rendering) hide text with
--- extmark conceal, which needs `conceallevel` >= 2. Each feature is an `owner`. A window keeps
--- ONE remembered original, however many owners hold it, and gets it back when the last owner
--- lets go:
---
---   * a window created later (`:split`, `:vsplit`, a buffer switched into an existing window)
---     is picked up by `M.apply` and gets the original of a sibling window of the same buffer
---     -- not the already raised value it inherited from the window it was split from;
---   * `M.restore` releases an owner for every window of the buffer;
---   * a window that stopped showing the buffer, or went to another buffer, is released by the
---     next `M.apply`.
---
---   M.apply(owner, bufnr)    – raise in all windows showing `bufnr`, release the ones that left
---   M.restore(owner, bufnr)  – release `owner` for every window of `bufnr`

local M = {}

local api = vim.api

---@class Mkdn.ConcealEntry
---@field cl integer  # the level the window had before anyone raised it
---@field buf integer
---@field owners table<string, boolean>

---@type table<integer, Mkdn.ConcealEntry>
local saved = {}

---The original level of a window that was released, kept per window: when its buffer comes back
---Neovim restores the raised value it remembered from the buffer, and that must not pass for the
---window's own level.
---@type table<integer, { buf: integer, cl: integer }>
local last = {}

---@internal
---@param win integer
---@param cl integer
local function put(win, cl)
  if api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_option_value, "conceallevel", cl, { scope = "local", win = win })
  end
end

---@internal
---Release the window. One that still shows the buffer gets its level back. One that went to
---another buffer gets it back only while it carries the raised value (2, inherited from the
---buffer it left); a different value is that buffer's own and must not be overwritten. The
---original is kept in `last` for the day the buffer returns. Known limit: the raised 2 and a
---buffer's own remembered 2 cannot be told apart by value, so the latter is reset to the original
---of the buffer that was left (the 3 / 0 / 1 cases are exact).
---@param win integer
local function drop(win)
  local e = saved[win]
  saved[win] = nil
  if not e then return end
  if not api.nvim_win_is_valid(win) then return end
  if api.nvim_win_get_buf(win) == e.buf then
    put(win, e.cl)
    last[win] = nil
  else
    if api.nvim_get_option_value("conceallevel", { win = win }) == 2 then put(win, e.cl) end
    last[win] = { buf = e.buf, cl = e.cl }
  end
end

---@param owner string
---@param bufnr integer
function M.apply(owner, bufnr)
  local showing = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    showing[win] = true
  end
  for win in pairs(last) do
    if not api.nvim_win_is_valid(win) then last[win] = nil end
  end
  local sibling
  for win, e in pairs(saved) do
    if e.buf == bufnr and showing[win] then sibling = e.cl end
  end
  for win in pairs(showing) do
    -- the window came from another buffer: give that one its level back first, or the raised
    -- value would be taken for the window's own
    if saved[win] and saved[win].buf ~= bufnr then drop(win) end
    local cl = api.nvim_get_option_value("conceallevel", { win = win })
    if not saved[win] then
      local own = cl
      -- an already raised value is not the window's own: take what it had here, or the sibling's
      if cl >= 2 then
        local l = last[win]
        if l and l.buf == bufnr then
          own = l.cl
        elseif sibling then
          own = sibling
        end
      end
      saved[win] = { cl = own, buf = bufnr, owners = {} }
    end
    saved[win].owners[owner] = true
    if cl < 2 then put(win, 2) end
  end
  for win, e in pairs(saved) do
    if e.buf == bufnr and not showing[win] then
      e.owners[owner] = nil
      if next(e.owners) == nil then drop(win) end
    end
  end
end

---@param owner string
---@param bufnr integer
function M.restore(owner, bufnr)
  for win, e in pairs(saved) do
    if e.buf == bufnr then
      e.owners[owner] = nil
      if next(e.owners) == nil then drop(win) end
    end
  end
end

return M
