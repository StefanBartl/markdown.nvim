---@module 'markdown.commands.toc'
--- Orchestrates TOC generation together with the optional headline-separator
--- pass. Used by both the `<leader>toc` keymap and `:Markdown toc`.
local M = {}

local cfg = require("markdown.config").get

local DEFAULT_HEADER = "## Table of content"

--- Update/insert the TOC and, unless disabled, ensure every section is closed
--- with a `---` separator.
---@param header? string                       TOC header line
---@param opts? { min_level?: integer, max_level?: integer, separators?: boolean }
function M.update(header, opts)
  opts = opts or {}

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

  require("markdown.core.toc").update_markdown_toc(header or DEFAULT_HEADER, opts)

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

--- `:Markdown toc [level] [--sep|--no-sep]` entry point.
---@param argv string[]
function M.run(argv)
  argv = argv or {}
  local opts = {}

  for _, a in ipairs(argv) do
    local n = tonumber(a)
    if n then
      opts.max_level = n
    elseif a == "--no-sep" then
      opts.separators = false
    elseif a == "--sep" then
      opts.separators = true
    end
  end

  M.update(DEFAULT_HEADER, opts)
end

return M
