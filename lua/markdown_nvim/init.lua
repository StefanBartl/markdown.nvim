---@module 'markdown_nvim'
--- markdown.nvim — a self-contained Markdown toolkit for Neovim.
--- Contains: heading navigation/shift, TOC, folding, bold wrap,
--- blockquote HL, fenced-code fix, anchor/url/image handler,
--- table viewer, and :Markdown commands.
local M = {}

local _setup_done = false

---@param opts Mkdn.Config|nil
function M.setup(opts)
  if _setup_done then return end
  _setup_done = true

  local cfg_mod = require("markdown_nvim.config")
  cfg_mod.setup(opts or {})
  local cfg = cfg_mod.get()

  -- TableView autocmds (buffer-local keymaps + commands)
  require("markdown_nvim.tableview").setup()

  -- TableView live autocmd (on BufWritePost)
  require("markdown_nvim.tableview.live").setup_autocmds()

  -- HL options (blockquote + ColorScheme)
  require("markdown_nvim.hl_options").setup(cfg)

  -- Fenced-code fix (inline code / fenced block highlights)
  local ff_opts = cfg.fenced_fix or {}
  require("markdown_nvim.fenced_fix").setup(ff_opts)

  -- Define the <Plug> surface up front so it is available for manual remapping
  -- even when the default keymaps are disabled.
  require("markdown_nvim.setup.plugs").define()

  -- Keymaps + user-commands via FileType autocmds
  if cfg.enable_autocmds ~= false then
    require("markdown_nvim.setup.autocmds").setup()
  end

  -- Optional which-key group labels (no-op if which-key is not installed).
  require("markdown_nvim.setup.which_key").setup()
end

-- Public façade -----------------------------------------------------------

M.foldexpr           = function(lnum) return require("markdown_nvim.core.fold").foldexpr(lnum) end
M.goto_prev_heading  = function() require("markdown_nvim.core.headings").goto_prev_heading() end
M.goto_next_heading  = function() require("markdown_nvim.core.headings").goto_next_heading() end
M.toggle_visual_bold = function() require("markdown_nvim.core.wrap").toggle_visual_bold() end

M.update_toc = function(header, opts)
  require("markdown_nvim.core.toc").update_markdown_toc(header, opts)
end

M.handle_cursor_action = function()
  require("markdown_nvim.handler").handle_cursor_action()
end

---Apply H2-level blank-line separators to the current (or given) buffer.
---@param bufnr? integer  defaults to current buffer
---@param opts?  { notify?: boolean }
M.apply_headline_separators = function(bufnr, opts)
  require("markdown_nvim.core.headline_spacing").apply_headl_separators(
    bufnr or vim.api.nvim_get_current_buf(), opts or { notify = true }
  )
end

return M
