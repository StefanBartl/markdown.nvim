---@module 'markdown_nvim.commands.refs'
--- `:Markdown refs <sub>` router.
---   sync                     Reconcile now: propagate heading renames to links
---                            + refresh the TOC + report orphaned anchor links.
---   check                    Dry run: list broken `#anchor` links (quickfix).
---   live [on|off|toggle]     Control live (debounced) tracking for this buffer.
---   baseline                 Re-snapshot heading anchors (reset rename tracking).
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.commands.refs]")

local M = {}

-- Per-buffer live autocmd id, so `live off` can remove exactly what `live on` set.
local live_au = {}

local function do_sync()
  require("markdown_nvim.core.refs").reconcile(vim.api.nvim_get_current_buf())
end

local function do_check()
  require("markdown_nvim.core.refs").check(vim.api.nvim_get_current_buf())
end

local function do_baseline()
  require("markdown_nvim.core.refs").baseline(vim.api.nvim_get_current_buf())
  notify.info("refs: baseline reset")
end

local function live_is_on(bufnr)
  return live_au[bufnr] ~= nil
end

local function live_on(bufnr)
  local refs = require("markdown_nvim.core.refs")
  refs.attach(bufnr)
  if live_au[bufnr] then return end
  live_au[bufnr] = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function() refs.on_change(bufnr) end,
    desc = "[markdown.nvim] refs live tracking",
  })
  notify.info("refs live: on")
end

local function live_off(bufnr)
  if live_au[bufnr] then
    pcall(vim.api.nvim_del_autocmd, live_au[bufnr])
    live_au[bufnr] = nil
  end
  notify.info("refs live: off")
end

local function do_live(argv)
  local bufnr = vim.api.nvim_get_current_buf()
  local action = (argv[1] or "toggle"):lower()
  if action == "on" then
    live_on(bufnr)
  elseif action == "off" then
    live_off(bufnr)
  elseif action == "toggle" then
    if live_is_on(bufnr) then live_off(bufnr) else live_on(bufnr) end
  else
    notify.warn("refs live: expected on|off|toggle")
  end
end

local subcommands = {
  sync     = do_sync,
  check    = do_check,
  baseline = do_baseline,
  live     = do_live,
}

---@param argv string[]
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
