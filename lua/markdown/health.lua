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
  local error_ = health.error or health.report_error
  local info = health.info or health.report_info

  start("markdown.nvim")

  -- Neovim version.
  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    warn("markdown.nvim targets Neovim 0.10+ (vim.system, used unconditionally once rg is found)", {
      "Upgrade Neovim to 0.10+",
    })
  end

  -- System opener used by the link/file/image handlers: a chain, the same target asked for again
  -- within a few seconds starts one opener further down.
  do
    local platform = require("markdown.util.platform")
    local names = {}
    for _, o in ipairs(platform._chain()) do
      names[#names + 1] = o.name
    end
    ok("link opener chain: " .. table.concat(names, " -> "))
    local attempts = platform.log()
    if #attempts == 0 then
      info("no link/file opened in this session yet")
    else
      for i = math.max(1, #attempts - 4), #attempts do
        local a = attempts[i]
        info(("%s via %s: %s"):format(a.target, a.opener, a.result))
      end
    end
  end

  -- Config sanity.
  local cfg_ok, config = pcall(require, "markdown.config")
  if not cfg_ok then
    warn("config module failed to load: " .. tostring(config), { "Reinstall markdown.nvim" })
    return
  end
  local cfg = config.get()

  local picker = cfg.links and cfg.links.picker
  if picker == "hover_select" or picker == "select" then
    info("links picker: " .. picker)
  else
    warn(('links.picker is %q — expected "hover_select" or "select"'):format(tostring(picker)), {
      'Set links.picker to "hover_select" or "select" in setup()',
    })
  end
  info("links sanitize_on_save: " .. tostring(not cfg.links or cfg.links.sanitize_on_save ~= false))

  -- Unknown keys / out-of-range scalars the last setup() had to drop or
  -- degrade (ERR-50/ERR-22) -- setup() already warned once; this repeats it
  -- somewhere a user checking on the plugin's state will actually see it.
  local issues = config.issues and config.issues() or {}
  if #issues > 0 then
    for _, msg in ipairs(issues) do
      warn(msg)
    end
  else
    ok("config: no unknown or invalid setup() options")
  end

  info(
    ("autocmds: %s | keymaps: %s | ft_only: %s | headline_spacing: %s | heading_gaps: %s"):format(
      tostring(cfg.enable_autocmds ~= false),
      tostring(cfg.enable_keymaps ~= false),
      tostring(cfg.ft_only ~= false),
      tostring(cfg.ensure_headline_spacing ~= false),
      tostring(cfg.check_heading_gaps ~= false)
    )
  )

  -- Optional host plugins for :Markdown render / preview.
  ok(
    ("native rendering available (:Markdown render; render.enabled = %s)"):format(
      tostring((cfg.render or {}).enabled == true)
    )
  )
  if vim.fn.has("nvim-0.11") ~= 1 then
    info("Neovim < 0.11: the table grid (table.render) needs conceal_lines and stays off")
  end
  if vim.fn.exists(":MDView") == 2 then
    ok("mdview.nvim detected (:Markdown preview / :Markdown mdview available)")
    -- Hint for screen sharing, not a problem: the defaults are legitimate setups. Read behind a pcall,
    -- an mdview.nvim without these options simply gives no hint.
    local mdview_ok, mdview_cfg = pcall(require, "mdview.config")
    local browser = mdview_ok
      and type(mdview_cfg) == "table"
      and type(mdview_cfg.defaults) == "table"
      and mdview_cfg.defaults.browser
    if type(browser) == "table" then
      -- browser.focus only acts in open_mode "default"; in "isolated" mode it is a no-op, so
      -- recommending it there would point at a setting that changes nothing.
      if browser.focus ~= nil and browser.focus ~= "nvim" and browser.open_mode ~= "isolated" then
        info(
          ('mdview.nvim browser.focus = "%s"; recommended for screen sharing: "nvim" (keeps keyboard focus in Neovim; clean on macOS, best-effort on Windows, no effect on Linux)'):format(
            tostring(browser.focus)
          )
        )
      end
      if browser.behavior ~= nil and browser.behavior ~= "reuse" then
        info(
          ('mdview.nvim browser.behavior = "%s"; recommended for screen sharing: "reuse" (one tab follows the buffer you edit)'):format(
            tostring(browser.behavior)
          )
        )
      end
    end
  else
    info("mdview.nvim not found — :Markdown preview / :Markdown mdview will warn if used")
  end

  -- lib.nvim: required for the :Markdown/:TableView* command layer
  -- (lib.nvim.bindings.usercmd.composer) and core/table_mode.lua's buffer debouncing,
  -- both unconditional requires with no pcall.
  local composer_ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  if composer_ok then
    ok("lib.nvim detected (:Markdown/:TableView* command layer available)")
  else
    error_(
      "lib.nvim not found — :Markdown/:TableView* will fail to register",
      { 'Install "WKDSteve/lib.nvim"' }
    )
  end

  -- Optional ui.nvim integration on top of the above (the default float
  -- picker backend specifically — cosmetic, falls back cleanly).
  if pcall(require, "ui.kit") then
    ok("ui.kit detected (kit.select picker backend)")
  else
    info("ui.kit not found — picker falls back to vim.ui.select")
  end

  -- Optional which-key integration.
  if pcall(require, "which-key") then
    ok('which-key detected (<leader>t grouped as "Markdown")')
  else
    info("which-key not found — mappings still carry their own descriptions")
  end

  -- Optional picker backends (util/picker.lua) and the snacks image preview
  -- (commands/links.lua); each is a soft dependency, never an error.
  local pickers = {
    { "telescope", "telescope.pickers", "telescope picker backend" },
    { "fzf-lua", "fzf-lua", "fzf-lua picker backend" },
    { "snacks", "snacks.picker", "snacks image-preview picker for links" },
  }
  for _, dep in ipairs(pickers) do
    if pcall(require, dep[2]) then
      ok(dep[1] .. " found: " .. dep[3])
    else
      info(dep[1] .. " not installed: " .. dep[3] .. " unavailable")
    end
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
        "fenced_scope provider 'color_my_ascii' requested but its fence API is unavailable — using the built-in scanner",
        {
          "Install WKDSteve/color_my_ascii.nvim, or set fenced_scope.provider to 'auto' or 'builtin'",
        }
      )
    else
      info("color_my_ascii not found — fenced_scope uses the built-in fallback scanner")
    end
  end

  -- The declared external tools (docs/install.json), reported out of the
  -- spec rather than listed a second time by hand. Silent when lib.nvim.deps
  -- is absent (an older lib.nvim) or this plugin ships no spec.
  local ok_deps, deps_health = pcall(require, "lib.nvim.deps.health")
  if ok_deps then
    vim.health.start("markdown.nvim: declared tools (lib.nvim.deps)")
    deps_health.report_for("markdown.nvim")
  end

  -- Only hand off to the composer if it actually loaded above -- otherwise
  -- this would re-require the exact module just reported as missing and
  -- raise, aborting the report right after the health.error that was
  -- supposed to explain why (see health_spec's "lib.nvim missing" case).
  if composer_ok then
    -- :Markdown is registered lazily on the first markdown buffer; make sure
    -- it exists so a health check run before that does not report it missing.
    pcall(function() require("markdown.bindings.usrcmds").ensure_global() end)
    composer.checkhealth("Markdown")
  end
end

return M
