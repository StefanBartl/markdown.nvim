---@module 'markdown.bindings.autocmds'
---@brief All FileType / BufWritePost autocmds that install markdown bindings.
---@description
--- Consolidates what used to live in setup/autocmds and tableview/{autocmds,
--- live}. TableView maps/commands and the live-preview refresh are always
--- installed; the main editing keymaps, the :Markdown / OpenWith commands and
--- the fold options are installed only when `enable_autocmds` is not false
--- (mirroring the previous behavior). All augroups are cleared on every setup().
---
--- The five FileType handlers (TableView, refs baseline, keymaps, user commands,
--- fold) share ONE autocmd, through `lib.nvim.bindings.autocmd.dispatcher`. They
--- are independent of each other -- nothing depends on their order, and each is
--- gated on its own -- so this is about what a re-`setup()` does, not speed: a
--- handler whose feature is now off is taken back out (a plain autocmd behind a
--- gate that is false is simply never touched again, and stays), and the
--- registry can list what fires on a markdown FileType in one place.

local notify = require("markdown.util.notify").create("[markdown.bindings.autocmds]")
local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

local api = vim.api

--- The filetypes every markdown binding is installed for. Doubles as the
--- dispatcher's autocmd `pattern` (a miss stays in Neovim) and its handler keys,
--- so `ev.match` is checked against the same list twice, in C and in Lua.
---@type string[]
local FILETYPES = { "markdown", "mdx", "md", "markdown.*" }

--- The one group the FileType handlers live in.
local FILETYPE_GROUP = "MarkdownNvimFileType"

---@type Lib.Autocmd.Dispatcher.Handle|nil
local ft_handle = nil

--- Feature names registered on the FileType dispatcher, for `reset_filetype()`.
---@type table<string, true>
local ft_owners = {}

---@internal
---@return Lib.Autocmd.Dispatcher.Handle
local function ft_dispatcher()
  if not ft_handle then
    ft_handle = require("lib.nvim.bindings.autocmd.dispatcher").new({
      event = "FileType",
      name = "markdown_filetype",
      group = FILETYPE_GROUP,
      pattern = FILETYPES,
      desc = "[markdown.nvim] Dispatch a markdown FileType to its binding installers",
      key = function(ev) return ev.match end,
    })
  end
  return ft_handle
end

--- Take every FileType handler back out, so a `setup()` that runs again starts
--- from what the current config asks for, not from what the last one did.
---@internal
---@return nil
local function reset_filetype()
  if not ft_handle then return end
  for owner in pairs(ft_owners) do
    ft_handle.unregister(owner)
  end
  ft_owners = {}
  ft_handle.detach()
end

--- Register one FileType handler for markdown buffers.
---@internal
---@param owner string  feature name; what `reset_filetype()` takes back out
---@param desc string
---@param load fun(ctx: Lib.Autocmd.Dispatcher.Ctx)
---@return Lib.Autocmd.Dispatcher.Handle
local function on_filetype(owner, desc, load)
  local handle = ft_dispatcher()
  handle.attach() -- idempotent
  ft_owners[owner] = true
  -- A tail call, deliberately: lib records the `register()` call site off the
  -- stack, so a wrapper frame here would attribute every handler to this line
  -- instead of to the `setup()` step that registered it.
  return handle.register(FILETYPES, { load = load, desc = desc, owner = owner })
end

---@internal
---@param ft string? Buffer filetype.
---@return boolean
local function is_md(ft)
  if not ft then return false end
  return ft == "md" or ft == "mdx" or ft == "markdown" or ft:match("^markdown%.") ~= nil
end

---@internal
local function keymaps() return require("markdown.bindings.keymaps") end
---@internal
local function usrcmds() return require("markdown.bindings.usrcmds") end

---@internal
---@param cfg Mkdn.Config
local function apply_to_already_loaded(cfg)
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and is_md(vim.bo[bufnr].filetype) then
      local ok, err = pcall(function()
        if cfg.enable_autocmds ~= false then
          keymaps().apply(bufnr)
          usrcmds().apply({ buf = bufnr })
        end
      end)
      if not ok then
        notify.warn("Error applying to existing buffer " .. bufnr .. ": " .. tostring(err))
      end
    end
  end
end

--- Register every binding autocmd for the resolved config.
---@param cfg Mkdn.Config
---@return nil
function M.setup(cfg)
  local ftpat = FILETYPES
  local feat = require("markdown.config").feature_enabled

  reset_filetype()

  -- TableView buffer-local maps + commands. Gated by the "tableview" feature.
  if feat("tableview") then
    on_filetype(
      "tableview",
      "[markdown.nvim] Install buffer-local TableView maps & commands",
      function(ctx)
        keymaps().apply_tableview(ctx.buf)
        usrcmds().apply_tableview(ctx.ev)
      end
    )
  end

  -- Link-target hover preview. Gated by the "hover" feature AND by
  -- `cfg.hover.enabled`; `markdown.hover.attach` installs the per-buffer
  -- CursorHold/mouse autocmds and re-checks the config itself, so toggling
  -- it off at runtime takes effect without re-running setup().
  if feat("hover") and (cfg.hover and cfg.hover.enabled) ~= false then
    -- No autocmd of our own: `hover.enable` installs the FileType
    -- trigger (and attaches to already-open buffers), because the hover is not
    -- a markdown feature and must not be gated on this plugin having loaded.
    -- `configure` registers markdown.nvim's link source and section previews
    -- and hands over this plugin's `hover` block; `enable` then turns it on.
    --
    -- Note this only covers users who reach markdown.nvim at all — it is
    -- lazy-loaded on markdown filetypes in most specs, so a session that never
    -- opens a markdown file still needs `require("hover").enable()`
    -- from somewhere that is not lazy. See lua/lib/nvim/hover/README.md.
    --
    -- hover.nvim is a soft dependency (LUA-01: docs/installation.md and
    -- README.md both document it as optional) -- `configure` is soft
    -- internally, but `enable()` is a direct require with nothing else
    -- guarding it, and used to take the rest of setup() down with it
    -- (keymaps, user commands, fold options, sanitize-on-save all install
    -- AFTER this block) whenever hover.nvim just was not installed.
    require("markdown.hover").configure(cfg.hover)
    local ok_hover, hover_lib = pcall(require, "hover")
    if ok_hover then
      hover_lib.enable()
    else
      notify.warn(
        "hover.nvim not installed -- link/path hover preview is disabled (optional dependency, see docs/installation.md)"
      )
    end
  end

  -- Reference sync automatic triggers (independent opt-in via config.refs.mode).
  -- "off" installs nothing; the manual :Markdown refs commands still work.
  local refs_mode = (cfg.refs and cfg.refs.mode) or "off"
  if feat("refs") and (refs_mode == "save" or refs_mode == "live") then
    local aug_refs = api.nvim_create_augroup("MarkdownNvimRefs", { clear = true })

    -- Snapshot heading anchors when a markdown buffer opens, so later reconciles
    -- can detect renames relative to this baseline.
    on_filetype(
      "refs",
      "[markdown.nvim] refs: baseline heading anchors",
      function(ctx) require("markdown.core.refs").attach(ctx.buf) end
    )

    if refs_mode == "save" then
      autocmd.create(
        "BufWritePre",
        function(ev) require("markdown.core.refs").reconcile(ev.buf, { silent = true }) end,
        {
          group = aug_refs,
          pattern = { "*.md", "*.markdown", "*.mdx" },
          desc = "[markdown.nvim] refs: sync on save",
        }
      )
    else -- "live"
      autocmd.create({ "TextChanged", "TextChangedI" }, function(ev)
        if not is_md(vim.bo[ev.buf].filetype) then return end
        require("markdown.core.refs").on_change(ev.buf)
      end, {
        group = aug_refs,
        pattern = ftpat,
        desc = "[markdown.nvim] refs: debounced live sync",
      })
    end

    -- Clean up timers/extmarks when a tracked buffer is wiped.
    autocmd.create("BufWipeout", function(ev) require("markdown.core.refs").detach(ev.buf) end, {
      group = aug_refs,
      pattern = { "*.md", "*.markdown", "*.mdx" },
      desc = "[markdown.nvim] refs: teardown",
    })
  end

  -- Link diagnostics automatic trigger (independent opt-in via
  -- config.links.diagnostics.mode). "off" leaves the manual :Markdown links
  -- check command as the only way to run it.
  local links_diag_mode = (cfg.links and cfg.links.diagnostics and cfg.links.diagnostics.mode)
    or "off"
  if feat("links") and links_diag_mode == "save" then
    local aug_links = api.nvim_create_augroup("MarkdownNvimLinkDiagnostics", { clear = true })
    autocmd.create("BufWritePost", function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      require("markdown.core.link_diagnostics").check(ev.buf)
    end, {
      group = aug_links,
      pattern = { "*.md", "*.markdown", "*.mdx" },
      desc = "[markdown.nvim] link diagnostics: check on save",
    })
  end

  -- Table-wrap resize hook + selective on-save reflow (independent opt-in via
  -- config.table.wrap.auto_resize / .selective_reflow; both default off).
  if feat("table_wrap") then
    local wrapcfg = (cfg.table and cfg.table.wrap) or {}

    if wrapcfg.auto_resize then
      local aug_resize = api.nvim_create_augroup("MarkdownNvimTableWrapResize", { clear = true })
      local timer = nil
      autocmd.create({ "VimResized", "WinResized" }, function()
        if timer then
          -- PERF-62: a stopped vim.defer_fn timer only closes itself from
          -- inside its own callback -- one that never fires (because it was
          -- stopped here) leaks its libuv handle for the rest of the session
          -- unless it is closed explicitly too.
          pcall(function() timer:stop() end)
          pcall(function() timer:close() end)
          timer = nil
        end
        timer = vim.defer_fn(function()
          for _, bufnr in ipairs(api.nvim_list_bufs()) do
            if api.nvim_buf_is_loaded(bufnr) and is_md(vim.bo[bufnr].filetype) then
              pcall(require("markdown.commands.mdtable").reflow_auto_tables, bufnr)
            end
          end
        end, wrapcfg.resize_debounce_ms or 300)
      end, {
        group = aug_resize,
        desc = "[markdown.nvim] table-wrap: debounced reflow of auto-mode tables on resize",
      })
    end

    if wrapcfg.selective_reflow then
      local aug_sel = api.nvim_create_augroup("MarkdownNvimTableWrapSelective", { clear = true })
      autocmd.create("BufWritePre", function(ev)
        if not is_md(vim.bo[ev.buf].filetype) then return end
        pcall(require("markdown.commands.mdtable").selective_reflow_on_save, ev.buf)
      end, {
        group = aug_sel,
        pattern = { "*.md", "*.markdown", "*.mdx" },
        desc = "[markdown.nvim] table-wrap: reflow only tables that changed since last save",
      })
    end
  end

  -- Link-target sanitize on save (independent opt-out via
  -- config.links.sanitize_on_save, default on).
  local links_cfg = cfg.links or {}
  if feat("links") and links_cfg.sanitize_on_save ~= false then
    local aug_links = api.nvim_create_augroup("MarkdownNvimLinksSanitize", { clear = true })
    autocmd.create(
      "BufWritePre",
      function(ev) require("markdown.core.link_sanitize").buffer(ev.buf) end,
      {
        group = aug_links,
        pattern = { "*.md", "*.markdown", "*.mdx" },
        desc = "[markdown.nvim] links: sanitize link targets on save",
      }
    )
  end

  -- Gated by enable_autocmds: main keymaps + user commands + fold options.
  if cfg.enable_autocmds ~= false then
    on_filetype(
      "keymaps",
      "[markdown.nvim] Install buffer-local keymaps",
      function(ctx) keymaps().apply(ctx.buf) end
    )

    on_filetype(
      "usrcmds",
      "[markdown.nvim] Install buffer-local user commands",
      function(ctx) usrcmds().apply(ctx.ev) end
    )

    on_filetype("fold", "[markdown.nvim] Set fold options for markdown buffers", function()
      if not feat("fold") then return end
      vim.opt_local.foldmethod = "expr"
      vim.opt_local.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
      vim.opt_local.foldenable = true
      vim.opt_local.foldlevel = 99
      vim.opt_local.foldlevelstart = 99
    end)
  end

  apply_to_already_loaded(cfg)
end

return M
