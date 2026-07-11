---@module 'markdown_nvim.bindings.autocmds'
---@brief All FileType / BufWritePost autocmds that install markdown bindings.
---@description
--- Consolidates what used to live in setup/autocmds and tableview/{autocmds,
--- live}. TableView maps/commands and the live-preview refresh are always
--- installed; the main editing keymaps, the :Markdown / OpenWith commands and
--- the fold options are installed only when `enable_autocmds` is not false
--- (mirroring the previous behavior). All augroups are cleared on every setup().

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.bindings.autocmds]")

local M = {}

local api = vim.api

local function is_md(ft)
  if not ft then return false end
  return ft == "md" or ft == "mdx" or ft == "markdown" or ft:match("^markdown%.") ~= nil
end

local function keymaps() return require("markdown_nvim.bindings.keymaps") end
local function usrcmds() return require("markdown_nvim.bindings.usrcmds") end

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

  -- Always: TableView buffer-local maps + commands.
  local aug_tv = api.nvim_create_augroup("MarkdownNvimTableView", { clear = true })
  api.nvim_create_autocmd("FileType", {
    group = aug_tv,
    pattern = ftpat,
    callback = function(ev)
      pcall(function()
        keymaps().apply_tableview(ev.buf)
        usrcmds().apply_tableview(ev)
      end)
    end,
    desc = "[markdown.nvim] Install buffer-local TableView maps & commands",
  })

  -- Always: TableView live-preview refresh on save.
  local aug_live = api.nvim_create_augroup("MarkdownNvimTableViewLive", { clear = true })
  api.nvim_create_autocmd("BufWritePost", {
    group = aug_live,
    pattern = { "*.md", "*.markdown", "*.mdx" },
    callback = function(ev)
      local live = require("markdown_nvim.tableview.live")
      if live.is_running() then live.regenerate(ev.buf) end
    end,
    desc = "[markdown.nvim] Regenerate TableView live preview on save",
  })

  -- Reference sync automatic triggers (independent opt-in via config.refs.mode).
  -- "off" installs nothing; the manual :Markdown refs commands still work.
  local refs_mode = (cfg.refs and cfg.refs.mode) or "off"
  if refs_mode == "save" or refs_mode == "live" then
    local aug_refs = api.nvim_create_augroup("MarkdownNvimRefs", { clear = true })

    -- Snapshot heading anchors when a markdown buffer opens, so later reconciles
    -- can detect renames relative to this baseline.
    api.nvim_create_autocmd("FileType", {
      group = aug_refs,
      pattern = ftpat,
      callback = function(ev)
        if not is_md(vim.bo[ev.buf].filetype) then return end
        pcall(function() require("markdown_nvim.core.refs").attach(ev.buf) end)
      end,
      desc = "[markdown.nvim] refs: baseline heading anchors",
    })

    if refs_mode == "save" then
      api.nvim_create_autocmd("BufWritePre", {
        group = aug_refs,
        pattern = { "*.md", "*.markdown", "*.mdx" },
        callback = function(ev)
          pcall(function() require("markdown_nvim.core.refs").reconcile(ev.buf, { silent = true }) end)
        end,
        desc = "[markdown.nvim] refs: sync on save",
      })
    else -- "live"
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = aug_refs,
        pattern = ftpat,
        callback = function(ev)
          if not is_md(vim.bo[ev.buf].filetype) then return end
          pcall(function() require("markdown_nvim.core.refs").on_change(ev.buf) end)
        end,
        desc = "[markdown.nvim] refs: debounced live sync",
      })
    end

    -- Clean up timers/extmarks when a tracked buffer is wiped.
    api.nvim_create_autocmd("BufWipeout", {
      group = aug_refs,
      pattern = { "*.md", "*.markdown", "*.mdx" },
      callback = function(ev)
        pcall(function() require("markdown_nvim.core.refs").detach(ev.buf) end)
      end,
      desc = "[markdown.nvim] refs: teardown",
    })
  end

  -- Gated by enable_autocmds: main keymaps + user commands + fold options.
  if cfg.enable_autocmds ~= false then
    local aug_keymaps = api.nvim_create_augroup("MarkdownNvimKeymaps", { clear = true })
    api.nvim_create_autocmd("FileType", {
      group = aug_keymaps,
      pattern = ftpat,
      callback = function(ev)
        if not is_md(vim.bo[ev.buf].filetype) then return end
        local ok, err = pcall(keymaps().apply, ev.buf)
        if not ok then notify.warn("Error applying keymaps: " .. tostring(err)) end
      end,
      desc = "[markdown.nvim] Install buffer-local keymaps",
    })

    local aug_cmds = api.nvim_create_augroup("MarkdownNvimUserCommands", { clear = true })
    api.nvim_create_autocmd("FileType", {
      group = aug_cmds,
      pattern = ftpat,
      callback = function(ev)
        if not is_md(vim.bo[ev.buf].filetype) then return end
        local ok, err = pcall(usrcmds().apply, ev)
        if not ok then notify.warn("Error applying usercmds: " .. tostring(err)) end
      end,
      desc = "[markdown.nvim] Install buffer-local user commands",
    })

    local aug_fold = api.nvim_create_augroup("MarkdownNvimFold", { clear = true })
    api.nvim_create_autocmd("FileType", {
      group = aug_fold,
      pattern = ftpat,
      callback = function(ev)
        if not is_md(vim.bo[ev.buf].filetype) then return end
        vim.opt_local.foldmethod     = "expr"
        vim.opt_local.foldexpr       = "v:lua.require'markdown_nvim.core.fold'.foldexpr(v:lnum)"
        vim.opt_local.foldenable     = true
        vim.opt_local.foldlevel      = 99
        vim.opt_local.foldlevelstart = 99
      end,
      desc = "[markdown.nvim] Set fold options for markdown buffers",
    })
  end

  apply_to_already_loaded(cfg)
end

return M
