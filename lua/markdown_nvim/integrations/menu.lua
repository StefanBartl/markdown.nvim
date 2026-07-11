---@module 'markdown_nvim.integrations.menu'
---@brief Context-aware menu entries for nvzone/menu (soft, opt-in integration).
---@description
--- markdown.nvim does not depend on a menu plugin. Instead it *provides* a list
--- of entries in the shape nvzone/menu expects (`{ name, cmd, rtxt }`, plus
--- `{ name = "separator" }`), and a host — typically the user's menu dispatcher —
--- composes them into its own menu for markdown buffers, e.g.:
--- >
---   local items = require("markdown_nvim.integrations.menu").items()
---   -- prepend `items` to your custom menu table, then menu.open(composed)
--- <
--- Entries are context-aware: the fold actions only appear when the cursor sits
--- on an ATX heading. Everything is opt-out via `config.menu` (see DEFAULTS).

local M = {}

--- Whether the cursor is currently on an ATX heading line (`#`, `##`, …).
---@return boolean
local function on_heading()
  return vim.api.nvim_get_current_line():match("^%s*#+%s") ~= nil
end

--- Build the markdown menu entries for the current context.
--- Returns an empty list when the integration (or every sub-entry) is disabled,
--- so a host can safely `vim.list_extend` it unconditionally.
---@param opts? { force_fold?: boolean }  force_fold: include fold entries even off a heading
---@return table[]  nvzone/menu entry list (possibly empty)
function M.items(opts)
  opts = opts or {}
  local cfg = require("markdown_nvim.config").get()
  local mcfg = cfg.menu or {}
  if mcfg.enable == false then return {} end

  local actions = require("markdown_nvim.bindings.actions")
  local items = {}

  -- Fold controls — only meaningful on a heading (or when forced).
  if mcfg.fold ~= false and (opts.force_fold or on_heading()) then
    items[#items + 1] = { name = "Fold / Unfold Heading", cmd = actions.fold_toggle,  rtxt = "za" }
    items[#items + 1] = { name = "Fold H2+",              cmd = actions.fold_h2plus,  rtxt = "zk" }
    items[#items + 1] = { name = "Unfold All",            cmd = actions.unfold_all,   rtxt = "zu" }
  end

  -- Document-level actions (always available in a markdown buffer).
  local doc = {}
  if mcfg.toc ~= false then
    doc[#doc + 1] = { name = "Insert / Refresh TOC", cmd = actions.toc, rtxt = "<leader>toc" }
  end
  if mcfg.refs ~= false then
    doc[#doc + 1] = {
      name = "Sync References",
      cmd = function() require("markdown_nvim.core.refs").reconcile() end,
    }
  end

  if #items > 0 and #doc > 0 then
    items[#items + 1] = { name = "separator" }
  end
  vim.list_extend(items, doc)

  return items
end

--- Convenience: the markdown entries wrapped as a single nested submenu entry,
--- for hosts that prefer a "Markdown ▸" fly-out instead of inline entries.
--- Returns nil when there is nothing to show.
---@param label? string  submenu label (default "  Markdown")
---@return table|nil
function M.submenu(label)
  local items = M.items()
  if #items == 0 then return nil end
  return { name = label or "  Markdown", hl = "Exblue", items = items }
end

return M
