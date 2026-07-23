---@module 'markdown.health'
---@brief `:checkhealth markdown` diagnostics.
---@description
--- Reports the Neovim version, config sanity, the state of the optional host
--- plugins (`:Markdown render` / `:Markdown preview` / `:Markdown mdview`),
--- required `lib.nvim` (the command layer + buffer debouncing; the picker
--- backend on top of that stays a soft, cosmetic choice), and the optional
--- `which-key` integration. Read-only: never mutates state.

local M = {}

--- Run the health check.
---@return nil
function M.check()
  local health = vim.health or require("health")
  local start = health.start or health.report_start
  local ok = health.ok or health.report_ok
  local warn = health.warn or health.report_warn
  local info = health.info or health.report_info

  start("markdown.nvim")

  -- Neovim version.
  if vim.fn.has("nvim-0.9") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    warn("markdown.nvim targets Neovim 0.9+")
  end

  -- System opener used by the link/file/image handlers (cross-platform path).
  if vim.ui and type(vim.ui.open) == "function" then
    ok("vim.ui.open available (native cross-platform opener for links/files)")
  else
    info("vim.ui.open missing (Neovim < 0.10) — using the legacy jobstart opener")
  end

  -- Config sanity.
  local cfg_ok, config = pcall(require, "markdown.config")
  if not cfg_ok then
    warn("config module failed to load: " .. tostring(config))
    return
  end
  local cfg = config.get()

  local picker = cfg.links and cfg.links.picker
  if picker == "hover_select" or picker == "select" then
    info("links picker: " .. picker)
  else
    warn(('links.picker is %q — expected "hover_select" or "select"'):format(tostring(picker)))
  end
  info("links sanitize_on_save: " .. tostring(not cfg.links or cfg.links.sanitize_on_save ~= false))

  info(
    ("autocmds: %s | keymaps: %s | ft_only: %s | headline_spacing: %s"):format(
      tostring(cfg.enable_autocmds ~= false),
      tostring(cfg.enable_keymaps ~= false),
      tostring(cfg.ft_only ~= false),
      tostring(cfg.ensure_headline_spacing ~= false)
    )
  )

  -- Optional host plugins for :Markdown render / preview.
  if vim.fn.exists(":RenderMarkdown") == 2 then
    ok("render-markdown.nvim detected (:Markdown render available)")
  else
    info("render-markdown.nvim not found — :Markdown render will warn if used")
  end
  if vim.fn.exists(":MarkdownPreview") == 2 then
    ok("markdown-preview.nvim detected (:Markdown preview available)")
  else
    info("markdown-preview.nvim not found — :Markdown preview will warn if used")
  end
  if vim.fn.exists(":MDViewStart") == 2 then
    ok("mdview.nvim detected (:Markdown mdview available)")
  else
    info("mdview.nvim not found — :Markdown mdview will warn if used")
  end

  -- lib.nvim: required for the :Markdown/:TableView* command layer
  -- (lib.nvim.usercmd.composer) and core/table_mode.lua's buffer debouncing,
  -- both unconditional requires with no pcall.
  if pcall(require, "lib.nvim.usercmd.composer") then
    ok("lib.nvim detected (:Markdown/:TableView* command layer available)")
  else
    warn(
      'lib.nvim not found — :Markdown/:TableView* will fail to register; install "StefanBartl/lib.nvim"'
    )
  end

  -- Optional lib.nvim integration on top of the above (the default float
  -- picker backend specifically — cosmetic, falls back cleanly).
  if pcall(require, "lib.nvim.ui.kit") then
    ok("lib.nvim.ui.kit detected (kit.select picker backend)")
  else
    info("lib.nvim.ui.kit not found — picker falls back to vim.ui.select")
  end

  -- Optional which-key integration.
  if require("markdown.bindings.which_key").available() then
    ok('which-key detected (<leader>t grouped as "Markdown")')
  else
    info("which-key not found — mappings still carry their own descriptions")
  end

  -- Fenced-block scope (treat ```markdown/md/mdx/… blocks as sub-documents).
  local fs = cfg.fenced_scope or {}
  if fs.enable == false then
    info("fenced_scope: disabled")
  else
    local ops = fs.operations or {}
    info(
      ("fenced_scope: enabled | provider: %s | ops toc:%s nav:%s jump:%s shift:%s fold:%s"):format(
        tostring(fs.provider or "auto"),
        tostring(ops.toc ~= false),
        tostring(ops.nav ~= false),
        tostring(ops.jump ~= false),
        tostring(ops.shift ~= false),
        tostring(ops.fold == true)
      )
    )
    info("fenced_scope langs: " .. table.concat(fs.langs or {}, ", "))

    local pref = fs.provider or "auto"
    local has_cma = false
    if pref ~= "builtin" then
      local cma_ok, cma = pcall(require, "color_my_ascii")
      has_cma = cma_ok and type(cma) == "table" and type(cma.fences) == "table"
    end
    if has_cma then
      ok(
        "fenced_scope provider: color_my_ascii fence API (robust heuristic + treesitter detection)"
      )
    elseif pref == "color_my_ascii" then
      warn(
        "fenced_scope provider 'color_my_ascii' requested but its fence API is unavailable — using the built-in scanner"
      )
    else
      info("color_my_ascii not found — fenced_scope uses the built-in fallback scanner")
    end
  end

  require("lib.nvim.usercmd.composer").checkhealth("Markdown")
end

return M
