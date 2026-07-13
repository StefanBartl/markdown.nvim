---@module 'markdown_nvim.core.file_refs'
---@brief Find markdown files that link to a given filesystem path.
---@description
--- Project-wide reference search: scans every `*.md` file under a root
--- directory for inline links (`link_scan`) whose target resolves
--- (`util.path.resolve_from`) to the given path. Used by third-party
--- integrations (e.g. a file manager's delete-confirmation flow) to warn
--- before a linked-to file disappears; markdown.nvim itself has no delete
--- feature and does not act on the results.
---
--- Files are read directly off disk (not via buffers), so this works for
--- paths outside the current buffer's project without touching the jumplist
--- or opening windows.

local link_scan = require("markdown_nvim.core.link_scan")
local path      = require("markdown_nvim.util.path")
local ignore    = require("markdown_nvim.util.ignore")

local M = {}

---@class MarkdownFileRef
---@field file    string   Absolute path of the markdown file containing the link.
---@field line    integer  1-indexed line number.
---@field target  string   Raw link target as written (e.g. `./old.md`).
---@field display string   Full `[text](target)` as it appears in the file.

--- True when any path segment of `p` is in the default ignore set
--- (`.git`, `node_modules`, `dist`, …).
---@param p string
---@return boolean
local function is_ignored(p)
  local ignored = ignore.as_set()
  for seg in p:gmatch("[^/\\]+") do
    if ignored[seg] then return true end
  end
  return false
end

--- Find every `*.md` file under `root` whose link(s) resolve to `target_path`.
---@param target_path string  Absolute filesystem path being searched for.
---@param opts? { root?: string }  `root` defaults to the current working directory.
---@return MarkdownFileRef[]
function M.find_references(target_path, opts)
  opts = opts or {}
  if not target_path or target_path == "" then return {} end

  local root = opts.root or vim.fn.getcwd()
  local wanted = path.normalize(target_path):lower()

  local out = {}
  local files = vim.fn.globpath(root, "**/*.md", false, true)

  for _, file in ipairs(files) do
    if not is_ignored(file) then
      local ok, lines = pcall(vim.fn.readfile, file)
      if ok and lines then
        local file_dir = vim.fn.fnamemodify(file, ":h")
        for _, lk in ipairs(link_scan.from_lines(lines)) do
          if lk.kind == "mdlink" and lk.target and not lk.target:match("^#") then
            local resolved = path.resolve_from(lk.target, file_dir)
            if resolved and path.normalize(resolved):lower() == wanted then
              out[#out + 1] = {
                file    = file,
                line    = lk.lnum,
                target  = lk.target,
                display = lk.display,
              }
            end
          end
        end
      end
    end
  end

  return out
end

return M
