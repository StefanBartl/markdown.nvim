---@module 'markdown.commands.links'
--- `:Markdown links <sub>` router.
---   show   [%|cwd|<file>]   Collect links in the scope and open the chosen one.
---   create [-r] [...] <p>   Generate markdown links from filesystem paths.
--- A bare path (no known subcommand) defaults to `create` for backwards compat.
local notify = require("markdown.util.notify").create("[markdown.commands.links]")

local M = {}

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- create (delegates to the existing filesystem-link generator)
-- ---------------------------------------------------------------------------

---@internal
---@param argv string[]
local function do_create(argv)
  require("markdown.commands.markdown_links").run(argv)
end

-- ---------------------------------------------------------------------------
-- show
-- ---------------------------------------------------------------------------

--- Resolve a relative link target against a source-file directory so it can be
--- opened independently of the current buffer. URLs and absolute paths pass
--- through unchanged.
---@param target string
---@param base_dir string
---@return string
local function resolve_against(target, base_dir)
  if target:match("^https?://") then return target end
  if target:match("^#") then return target end
  if target:match("^/") or target:match("^%a:[/\\]") then
    return vim.fn.fnamemodify(target, ":p")
  end
  return vim.fn.fnamemodify(base_dir .. "/" .. target, ":p")
end

--- Collect links for a scope. Returns enriched links whose `target` is already
--- resolved when they originate from a file on disk.
---@param scope string
---@return Mkdn.Link[]
local function collect(scope)
  local scan = require("markdown.core.link_scan")

  if scope == "" or scope == "%" then
    -- Current buffer: leave targets relative (handler resolves to buffer dir).
    return scan.from_buffer(0)
  end

  local function links_from_file(path)
    local lines = vim.fn.readfile(path)
    local base  = vim.fn.fnamemodify(path, ":p:h")
    local found = scan.from_lines(lines)
    for _, lk in ipairs(found) do
      lk.target = resolve_against(lk.target, base)
      lk.file   = path
    end
    return found
  end

  if scope == "cwd" then
    local out = {}
    local md_files = vim.fn.globpath(vim.fn.getcwd(), "**/*.md", false, true)
    for _, path in ipairs(md_files) do
      for _, lk in ipairs(links_from_file(path)) do out[#out + 1] = lk end
    end
    return out
  end

  -- Treat scope as a file path.
  local path = vim.fn.expand(scope)
  if uv.fs_stat(path) then
    return links_from_file(path)
  end

  notify.warn("links show: scope not found: " .. tostring(scope))
  return {}
end

---@internal
---@param lk Mkdn.Link
---@return string
local function format_item(lk)
  local where = lk.file and (" — " .. vim.fn.fnamemodify(lk.file, ":t")) or ""
  return lk.display .. where
end

---@internal
---@param argv string[]
local function do_show(argv)
  local cfg = require("markdown.config").get()
  local scope = argv[1] or "%"

  local links = collect(scope)
  if #links == 0 then
    notify.info("No links found in scope: " .. scope)
    return
  end

  local picker = require("markdown.util.picker")
  picker.select(links, {
    prompt  = string.format("Markdown links (%d)", #links),
    format  = format_item,
    backend = (cfg.links and cfg.links.picker) or "hover_select",
  }, function(lk)
    require("markdown.handler").open_target(lk.target)
  end)
end

-- ---------------------------------------------------------------------------
-- check (dead relative-file links / duplicate heading anchors)
-- ---------------------------------------------------------------------------

---@internal
---@param _argv string[]
local function do_check(_argv)
  local diag = require("markdown.core.link_diagnostics")
  local bufnr = vim.api.nvim_get_current_buf()
  local count = diag.check(bufnr)
  if count == 0 then
    notify.info("Link check: no issues found")
  else
    notify.warn(string.format("Link check: %d issue(s) — see vim.diagnostic.open_float() / :lopen", count))
  end
end

-- ---------------------------------------------------------------------------
-- dispatch
-- ---------------------------------------------------------------------------

local subcommands = {
  show   = do_show,
  create = do_create,
  check  = do_check,
}

--- Runs `:Markdown links <sub>` (defaults to `create` for a bare path).
---@param argv string[]
---@return nil
function M.run(argv)
  argv = argv or {}
  local sub = argv[1]

  local fn = sub and subcommands[sub]
  if fn then
    table.remove(argv, 1)
    fn(argv)
    return
  end

  -- Backwards compatible: `:Markdown links <path>` == create.
  do_create(argv)
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
