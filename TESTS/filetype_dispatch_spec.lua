-- TESTS/filetype_dispatch_spec.lua -- the five markdown FileType handlers share one
-- autocmd (bindings/autocmds.lua, behind lib.nvim's dispatcher).
--
-- What is worth pinning is what a plain autocmd per handler could not do, or did
-- badly: a second `setup()` neither stacks handlers nor leaves behind one whose
-- feature is now off (a gate that is false used to skip the augroup, so the old
-- autocmd simply stayed), and the handlers still do their job on a real FileType.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api

  local config = require("markdown.config")
  local autocmds = require("markdown.bindings.autocmds")
  local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")

  --- The live markdown FileType dispatcher's owners, or nil when it is detached.
  ---@return table<string, true>|nil
  local function owners()
    for _, entry in ipairs(dispatcher.registry()) do
      if entry.name == "markdown_filetype" and entry.attached then
        local out = {}
        for _, h in ipairs(entry.handlers) do
          out[h.owner] = true
        end
        return out
      end
    end
    return nil
  end

  --- Handlers registered right now (a stacked re-setup would double this).
  ---@return integer
  local function handler_count()
    for _, entry in ipairs(dispatcher.registry()) do
      if entry.name == "markdown_filetype" and entry.attached then return #entry.handlers end
    end
    return 0
  end

  --- Distinct autocmd ids in the group (Neovim lists one row per pattern).
  ---@return integer
  local function autocmd_count()
    local found, list =
      pcall(api.nvim_get_autocmds, { group = "MarkdownNvimFileType", event = "FileType" })
    local ids = {}
    for _, au in ipairs(found and list or {}) do
      ids[au.id] = true
    end
    return vim.tbl_count(ids)
  end

  local function setup(opts)
    config.setup(opts or {})
    autocmds.setup(config.get())
  end

  -- ---------------------------------------------------------------------------
  -- Default config: all five, behind one autocmd.
  -- ---------------------------------------------------------------------------
  setup({})
  local o = owners()
  ok(o ~= nil, "the FileType dispatcher is attached after setup()")
  for _, name in ipairs({ "tableview", "refs", "keymaps", "usrcmds", "fold" }) do
    ok(o[name], "handler registered: " .. name)
  end
  eq(handler_count(), 5, "exactly five handlers")
  eq(autocmd_count(), 1, "behind ONE autocmd")

  -- ---------------------------------------------------------------------------
  -- They still do their job on a real FileType, and only for markdown.
  -- ---------------------------------------------------------------------------
  local md = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(md)
  vim.bo[md].filetype = "markdown"
  eq(vim.wo.foldmethod, "expr", "fold options are set on a markdown buffer")
  eq(vim.fn.exists(":TableViewToggle"), 2, "TableView commands are installed on a markdown buffer")

  local lua_buf = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(lua_buf)
  vim.wo.foldmethod = "manual"
  vim.bo[lua_buf].filetype = "lua"
  eq(vim.wo.foldmethod, "manual", "a non-markdown filetype is left alone")

  -- ---------------------------------------------------------------------------
  -- A second setup() does not stack.
  -- ---------------------------------------------------------------------------
  setup({})
  setup({})
  eq(handler_count(), 5, "repeated setup() does not stack handlers")
  eq(autocmd_count(), 1, "repeated setup() keeps a single autocmd")

  -- ---------------------------------------------------------------------------
  -- A feature turned off is taken back out; turned on again, it returns.
  -- ---------------------------------------------------------------------------
  setup({ features = { disable = { "tableview" } } })
  o = owners()
  ok(o and not o.tableview, "a disabled feature's handler is removed by the next setup()")
  ok(o.keymaps and o.fold, "the others are untouched")
  eq(handler_count(), 4, "four handlers left")

  setup({})
  ok(owners().tableview, "re-enabling brings it back")

  -- ---------------------------------------------------------------------------
  -- enable_autocmds = false keeps only what is always installed.
  -- ---------------------------------------------------------------------------
  setup({ enable_autocmds = false })
  o = owners()
  ok(o.tableview and o.refs, "TableView and refs baseline do not depend on enable_autocmds")
  ok(not o.keymaps and not o.usrcmds and not o.fold, "keymaps, user commands and fold do")

  -- restore the defaults for whatever spec runs next
  setup({})
end
