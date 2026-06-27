---@module 'markdown_nvim.commands.toc'
--- Orchestrates TOC generation together with the optional headline-separator
--- pass. Used by both the `<leader>toc` keymap and `:Markdown toc`.
local M = {}

local cfg = require("markdown_nvim.config").get

local DEFAULT_HEADER = "## Table of content"

--- Update/insert the TOC and, unless disabled, ensure every section is closed
--- with a `---` separator.
---@param header? string                       TOC header line
---@param opts? { min_level?: integer, max_level?: integer, separators?: boolean }
function M.update(header, opts)
  opts = opts or {}

  require("markdown_nvim.core.toc").update_markdown_toc(header or DEFAULT_HEADER, opts)

  -- Per-call override wins; otherwise fall back to the user config
  -- (`ensure_headline_spacing`, default true).
  local want_sep = opts.separators
  if want_sep == nil then
    want_sep = cfg().ensure_headline_spacing ~= false
  end

  if want_sep then
    local bufnr = vim.api.nvim_get_current_buf()
    require("markdown_nvim.core.headline_spacing").apply_headl_separators(bufnr, { notify = false })
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
