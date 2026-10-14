---@module 'markdown.core.conceal_guard'
---@brief Raises `conceallevel` in the windows showing a buffer and puts it back.
---@description
--- The display-only table features hide text with extmark conceal, which needs
--- `conceallevel` >= 2. Each feature (`owner`) remembers, per window, the value
--- the window had before, and restores exactly that:
---
---   * a window created later (`:split`, `:vsplit`, a buffer switched into an
---     existing window) is picked up by `M.apply` and gets the original of a
---     sibling window of the same buffer -- not the already raised value it
---     inherited from the window it was split from;
---   * `M.restore` puts every remembered window back, also those that were
---     split off in the meantime;
---   * a window that stopped showing the buffer is restored and forgotten by
---     the next `M.apply`.
---
---   M.apply(owner, bufnr)    – raise in all windows showing `bufnr`, restore the ones that left
---   M.restore(owner, bufnr)  – restore every remembered window of `bufnr`

local M = {}

local api = vim.api

---@type table<string, table<integer, { cl: integer, buf: integer }>>  # owner -> win -> saved
local saved = {}

---@internal
---@param win integer
---@param cl integer
local function put(win, cl)
  if api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_option_value, "conceallevel", cl, { scope = "local", win = win })
  end
end

---@param owner string
---@param bufnr integer
function M.apply(owner, bufnr)
  local st = saved[owner]
  if not st then
    st = {}
    saved[owner] = st
  end
  local showing = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    showing[win] = true
  end
  local sibling
  for win, e in pairs(st) do
    if e.buf == bufnr and showing[win] then sibling = e.cl end
  end
  for win in pairs(showing) do
    -- the window came from another buffer of this owner: give that one its level back first,
    -- or the raised value would be taken for the window's own
    if st[win] and st[win].buf ~= bufnr then
      put(win, st[win].cl)
      st[win] = nil
    end
    local cl = api.nvim_get_option_value("conceallevel", { win = win })
    if not st[win] or st[win].buf ~= bufnr then st[win] = { cl = sibling or cl, buf = bufnr } end
    if cl < 2 then put(win, 2) end
  end
  for win, e in pairs(st) do
    if e.buf == bufnr and not showing[win] then
      put(win, e.cl)
      st[win] = nil
    end
  end
end

---@param owner string
---@param bufnr integer
function M.restore(owner, bufnr)
  local st = saved[owner]
  if not st then return end
  for win, e in pairs(st) do
    if e.buf == bufnr then
      put(win, e.cl)
      st[win] = nil
    end
  end
end

return M
