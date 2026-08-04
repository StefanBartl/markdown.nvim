---@module 'markdown.commands.toc'
--- Orchestrates TOC generation together with the optional headline-separator
--- pass. Used by both the `<leader>toc` keymap and `:Markdown toc`.
local M = {}

local cfg = require("markdown.config").get

local DEFAULT_HEADER = "## Table of content"

--- Update/insert the TOC and, unless disabled, ensure every section is closed
--- with a `---` separator.
---@param header? string                       TOC header line
---@param opts? { min_level?: integer, max_level?: integer, marker?: string, separators?: boolean, anchor_style?: string, anchor_separator?: string, scan_first?: integer, scan_last?: integer, no_frontmatter?: boolean, exclude?: { first: integer, last: integer }[] }
---@return nil
function M.update(header, opts)
  opts = opts or {}

  -- config.toc supplies defaults for anything the caller didn't set explicitly.
  -- anchor_style/anchor_separator are config-only (no per-call override): the
  -- reference-sync engine reads the same config to keep anchors in agreement.
  local toc_cfg = cfg().toc or {}
  header = header or toc_cfg.header or DEFAULT_HEADER
  if opts.min_level == nil then opts.min_level = toc_cfg.min_level end
  if opts.max_level == nil then opts.max_level = toc_cfg.max_level end
  if opts.marker    == nil then opts.marker    = toc_cfg.marker end
  opts.anchor_style     = toc_cfg.anchor_style
  opts.anchor_separator = toc_cfg.anchor_separator

  -- When the cursor sits inside a markdown-family fenced block, scope the TOC to
  -- that block's interior (scan + insert stay inside the block).
  local scope = require("markdown.scope")
  local sc = scope.op_enabled("toc") and scope.detect() or nil
  local block_scoped = false

  if sc and sc.kind == "block" then
    block_scoped = true
    opts = vim.tbl_extend("force", opts, {
      scan_first     = sc.first,
      scan_last      = sc.last,
      no_frontmatter = true,
    })
  elseif sc and sc.kind == "buffer" then
    -- Outside any block: keep every fenced block's headings out of the outer TOC.
    opts = vim.tbl_extend("force", opts, { exclude = sc.exclude })
  end

  local toc_opts = opts --[[@as { min_level?: integer, max_level?: integer, marker?: string, anchor_style?: string, anchor_separator?: string, scan_first?: integer, scan_last?: integer, no_frontmatter?: boolean, exclude?: { first: integer, last: integer }[] }]]
  require("markdown.core.toc").update_markdown_toc(header or DEFAULT_HEADER, toc_opts)

  -- Section separators are a whole-document concern; skip them when the TOC was
  -- generated for a fenced sub-document.
  if block_scoped then return end

  -- Per-call override wins; otherwise fall back to the user config
  -- (`ensure_headline_spacing`, default true).
  local want_sep = opts.separators
  if want_sep == nil then
    want_sep = cfg().ensure_headline_spacing ~= false
  end

  if want_sep then
    local bufnr = vim.api.nvim_get_current_buf()
    require("markdown.core.headline_spacing").apply_headl_separators(bufnr, { notify = false })
  end
end

--- `:Markdown toc [level] [--sep|--no-sep] [min=N] [max=N] [marker=X]` entry point.
--- A bare numeric arg is shorthand for `max=N` (kept for backwards compat).
---@param argv string[]
---@return nil
function M.run(argv)
  argv = argv or {}
  local opts = {}

  for _, a in ipairs(argv) do
    local key, val = a:match("^([%w_]+)=(.+)$")
    local n = tonumber(a)
    if key == "min" then
      opts.min_level = tonumber(val)
    elseif key == "max" then
      opts.max_level = tonumber(val)
    elseif key == "marker" then
      opts.marker = val
    elseif n then
      opts.max_level = n
    elseif a == "--no-sep" then
      opts.separators = false
    elseif a == "--sep" then
      opts.separators = true
    end
  end

  M.update(nil, opts)
end

return M
