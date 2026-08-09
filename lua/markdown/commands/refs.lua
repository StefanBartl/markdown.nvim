---@module 'markdown.commands.refs'
--- `:Markdown refs <sub>` router.
---   sync                     Reconcile now: propagate heading renames to links
---                            + refresh the TOC + report orphaned anchor links.
---   check                    Dry run: list broken `#anchor` links (quickfix).
---   live [on|off|toggle]     Control live (debounced) tracking for this buffer.
---   baseline                 Re-snapshot heading anchors (reset rename tracking).
local notify = require("markdown.util.notify").create("[markdown.commands.refs]")

local M = {}

-- Per-buffer live autocmd id, so `live off` can remove exactly what `live on` set.
local live_au = {}

---@internal
local function do_sync() require("markdown.core.refs").reconcile(vim.api.nvim_get_current_buf()) end

---@internal
local function do_check() require("markdown.core.refs").check(vim.api.nvim_get_current_buf()) end

---@internal
local function do_baseline()
  require("markdown.core.refs").baseline(vim.api.nvim_get_current_buf())
  notify.info("refs: baseline reset")
end

---@internal
---@param bufnr integer
---@return boolean
local function live_is_on(bufnr) return live_au[bufnr] ~= nil end

---@internal
---@param bufnr integer
local function live_on(bufnr)
  local refs = require("markdown.core.refs")
  refs.attach(bufnr)
  if live_au[bufnr] then return end
  -- Stays on the raw API deliberately -- lib.nvim.autocmd.create's opts only
  -- forward group/pattern/desc/once/nested, not `buffer`, so routing this
  -- through it would turn a per-buffer live-tracking hook into one firing
  -- for every buffer. The returned id is also needed as-is for
  -- nvim_del_autocmd in live_off() below.
  live_au[bufnr] = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function() refs.on_change(bufnr) end,
    desc = "[markdown.nvim] refs live tracking",
  })
  notify.info("refs live: on")
end

---@internal
---@param bufnr integer
local function live_off(bufnr)
  if live_au[bufnr] then
    pcall(vim.api.nvim_del_autocmd, live_au[bufnr])
    live_au[bufnr] = nil
  end
  notify.info("refs live: off")
end

---@internal
---@param argv string[]
local function do_live(argv)
  local bufnr = vim.api.nvim_get_current_buf()
  local action = (argv[1] or "toggle"):lower()
  if action == "on" then
    live_on(bufnr)
  elseif action == "off" then
    live_off(bufnr)
  elseif action == "toggle" then
    if live_is_on(bufnr) then
      live_off(bufnr)
    else
      live_on(bufnr)
    end
  else
    notify.warn("refs live: expected on|off|toggle")
  end
end

local subcommands = {
  sync = do_sync,
  check = do_check,
  baseline = do_baseline,
  live = do_live,
}

--- Runs `:Markdown refs <sync|check|live|baseline>` (default: `sync`).
---@param argv string[]
---@return nil
function M.run(argv)
  argv = argv or {}
  -- Bare `:Markdown refs` == `sync`.
  local sub = argv[1] or "sync"
  local fn = subcommands[sub]
  if not fn then
    notify.info("Usage: :Markdown refs <sync|check|live|baseline>")
    return
  end
  table.remove(argv, 1)
  fn(argv)
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local tokens = vim.split(vim.trim(cmdline), "%s+")
  -- tokens: Markdown, refs, <sub>, <args...>
  local sub = tokens[3]
  local on_args = #tokens > 3 or (#tokens == 3 and arglead == "")

  if sub == "live" and on_args then
    local out = {}
    for _, name in ipairs({ "on", "off", "toggle" }) do
      if vim.startswith(name, arglead) then out[#out + 1] = name end
    end
    return out
  end

  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
