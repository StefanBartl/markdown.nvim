---@module 'markdown.bindings.autocmds'
---@brief All FileType / BufWritePost autocmds that install markdown bindings.
---@description
--- Consolidates what used to live in setup/autocmds and tableview/{autocmds,
--- live}. TableView maps/commands and the live-preview refresh are always
--- installed; the main editing keymaps, the :Markdown / OpenWith commands and
--- the fold options are installed only when `enable_autocmds` is not false
--- (mirroring the previous behavior). All augroups are cleared on every setup().

local notify = require("markdown.util.notify").create("[markdown.bindings.autocmds]")
local autocmd = require("lib.nvim.autocmd")

local M = {}

local api = vim.api

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
  local ftpat = { "markdown", "mdx", "md", "markdown.*" }
  local feat = require("markdown.config").feature_enabled

  -- TableView buffer-local maps + commands. Gated by the "tableview" feature.
  if feat("tableview") then
    local aug_tv = api.nvim_create_augroup("MarkdownNvimTableView", { clear = true })
    autocmd.create("FileType", function(ev)
      keymaps().apply_tableview(ev.buf)
      usrcmds().apply_tableview(ev)
    end, {
      group = aug_tv,
      pattern = ftpat,
      desc = "[markdown.nvim] Install buffer-local TableView maps & commands",
    })
  end

  -- Link-target hover preview. Gated by the "hover" feature AND by
  -- `cfg.hover.enabled`; `markdown.hover.attach` installs the per-buffer
  -- CursorHold/mouse autocmds and re-checks the config itself, so toggling
  -- it off at runtime takes effect without re-running setup().
  if feat("hover") and (cfg.hover and cfg.hover.enabled) ~= false then
    local aug_hover = api.nvim_create_augroup("MarkdownNvimHover", { clear = true })
    autocmd.create("FileType", function(ev) require("markdown.hover").attach(ev.buf) end, {
      group = aug_hover,
      pattern = ftpat,
      desc = "[markdown.nvim] Install buffer-local link-hover preview",
    })
  end

  -- Reference sync automatic triggers (independent opt-in via config.refs.mode).
  -- "off" installs nothing; the manual :Markdown refs commands still work.
  local refs_mode = (cfg.refs and cfg.refs.mode) or "off"
  if feat("refs") and (refs_mode == "save" or refs_mode == "live") then
    local aug_refs = api.nvim_create_augroup("MarkdownNvimRefs", { clear = true })

    -- Snapshot heading anchors when a markdown buffer opens, so later reconciles
    -- can detect renames relative to this baseline.
    autocmd.create("FileType", function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      require("markdown.core.refs").attach(ev.buf)
    end, {
      group = aug_refs,
      pattern = ftpat,
      desc = "[markdown.nvim] refs: baseline heading anchors",
    })

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
        if timer then pcall(function() timer:stop() end) end
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
    local aug_keymaps = api.nvim_create_augroup("MarkdownNvimKeymaps", { clear = true })
    autocmd.create("FileType", function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      keymaps().apply(ev.buf)
    end, {
      group = aug_keymaps,
      pattern = ftpat,
      desc = "[markdown.nvim] Install buffer-local keymaps",
    })

    local aug_cmds = api.nvim_create_augroup("MarkdownNvimUserCommands", { clear = true })
    autocmd.create("FileType", function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      usrcmds().apply(ev)
    end, {
      group = aug_cmds,
      pattern = ftpat,
      desc = "[markdown.nvim] Install buffer-local user commands",
    })

    local aug_fold = api.nvim_create_augroup("MarkdownNvimFold", { clear = true })
    autocmd.create("FileType", function(ev)
      if not is_md(vim.bo[ev.buf].filetype) then return end
      if not feat("fold") then return end
      vim.opt_local.foldmethod = "expr"
      vim.opt_local.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
      vim.opt_local.foldenable = true
      vim.opt_local.foldlevel = 99
      vim.opt_local.foldlevelstart = 99
    end, {
      group = aug_fold,
      pattern = ftpat,
      desc = "[markdown.nvim] Set fold options for markdown buffers",
    })
  end

  apply_to_already_loaded(cfg)
end

return M
