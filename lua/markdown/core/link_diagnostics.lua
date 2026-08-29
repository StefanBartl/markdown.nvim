---@module 'markdown.core.link_diagnostics'
--- Flag dead relative-file links and duplicate heading titles in a buffer,
--- reusing `core/link_scan` (link extraction) and `core/slug` (anchor
--- resolution) so results always agree with the TOC/refs anchor logic.
--- Surfaced via `vim.diagnostic` under a dedicated namespace and the manual
--- `:Markdown links check` command; `config.links.diagnostics.mode = "save"`
--- reruns it automatically on `BufWritePost`.

local M = {}

--- Shared namespace so repeated checks replace rather than accumulate.
M.namespace = vim.api.nvim_create_namespace("markdown_links")

local uv = vim.uv or vim.loop

---@internal
---@param target string
---@return boolean
local function is_external(target)
  return target:match("^%a[%w+.-]*://") ~= nil
    or target:match("^mailto:") ~= nil
    or target:match("^tel:") ~= nil
end

--- Split "path#anchor" into path, anchor. A leading "#..." (no path) yields a
--- nil path so callers can distinguish "same-file anchor" from "file link".
---@param target string
---@internal
---@return string|nil path
---@return string|nil anchor
local function split_target(target)
  local path, anchor = target:match("^(.-)#(.+)$")
  if path then
    if path == "" then return nil, anchor end
    return path, anchor
  end
  return target, nil
end

--- Resolve a relative file target against the buffer's own directory.
---@internal
---@param bufnr integer
---@param path string
---@return string
local function resolve_path(bufnr, path)
  if path:match("^/") or path:match("^%a:[/\\]") then return path end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local dir = bufname ~= "" and vim.fn.fnamemodify(bufname, ":p:h") or vim.fn.getcwd()
  return dir .. "/" .. path
end

--- Compute diagnostics for `bufnr` without touching `vim.diagnostic` (pure,
--- unit-testable). Findings:
---   * ERROR — a markdown-link's file target does not exist on disk.
---   * WARN  — a same-file `#anchor` link matches no heading.
---   * HINT  — two headings share a base slug (GFM auto-suffixes `-1`, `-2`, …).
--- Cross-file `path#anchor` links only check the file's existence: validating
--- an anchor inside another file is out of scope (would require scanning it).
---@param bufnr? integer
---@return Mkdn.LinkDiagnostic[]
function M.collect(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local scan = require("markdown.core.link_scan")
  local slug = require("markdown.core.slug")

  local links = scan.from_buffer(bufnr)
  local anchors = slug.heading_anchors(bufnr)

  local out = {}

  for _, lk in ipairs(links) do
    if lk.kind == "mdlink" then
      local path, anchor = split_target(lk.target)

      if path == nil and anchor then
        if not anchors.set[anchor] then
          out[#out + 1] = {
            lnum = lk.lnum - 1,
            col = lk.col,
            end_col = lk.col_end + 1,
            severity = vim.diagnostic.severity.WARN,
            message = string.format("No heading produces anchor #%s", anchor),
            source = "markdown_links",
          }
        end
      elseif path and path ~= "" and not is_external(path) then
        local full = resolve_path(bufnr, path)
        if uv.fs_stat(full) == nil then
          out[#out + 1] = {
            lnum = lk.lnum - 1,
            col = lk.col,
            end_col = lk.col_end + 1,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format("Dead link: %q not found", path),
            source = "markdown_links",
          }
        end
      end
    end
  end

  local seen_base = {}
  for _, h in ipairs(anchors.list) do
    local base = slug.gfm(h.title)
    seen_base[base] = (seen_base[base] or 0) + 1
  end
  for _, h in ipairs(anchors.list) do
    local base = slug.gfm(h.title)
    if seen_base[base] > 1 and h.anchor ~= base then
      out[#out + 1] = {
        lnum = h.row - 1,
        col = 0,
        end_col = 0,
        severity = vim.diagnostic.severity.HINT,
        message = string.format(
          "Duplicate heading title %q (anchor auto-suffixed to #%s)",
          h.title,
          h.anchor
        ),
        source = "markdown_links",
      }
    end
  end

  return out
end

--- Severity -> quickfix `type` column.
---
--- `HINT` maps to `N` (note) rather than `I`: the only hint this module emits
--- is the duplicate-heading one, which reports something already handled (the
--- anchor was auto-suffixed) and should not read as loudly as a real info item.
---@type table<integer, string>
local QF_TYPE = {
  [vim.diagnostic.severity.ERROR] = "E",
  [vim.diagnostic.severity.WARN] = "W",
  [vim.diagnostic.severity.INFO] = "I",
  [vim.diagnostic.severity.HINT] = "N",
}

--- Convert collected diagnostics into quickfix entries.
---
--- Index bases differ between the two APIs and silently produce off-by-ones:
--- `vim.diagnostic` is 0-based in both `lnum` and `col`, the quickfix list is
--- 1-based in both.
---@param diags Mkdn.LinkDiagnostic[]
---@param bufnr integer
---@return table[]
function M.to_qf_entries(diags, bufnr)
  local entries = {}
  for i, d in ipairs(diags) do
    entries[i] = {
      bufnr = bufnr,
      lnum = d.lnum + 1,
      col = d.col + 1,
      text = d.message,
      type = QF_TYPE[d.severity] or "I",
    }
  end
  return entries
end

--- Populate `vim.diagnostic` for `bufnr`, and mirror the findings into the
--- quickfix list.
---
--- Both, not either: the diagnostics carry the inline presentation (signs,
--- virtual text, `open_float`), the quickfix list is what lets you walk the
--- findings with `:cnext`. `refs.check` in this same plugin already set that
--- precedent for a buffer-local check -- quickfix, not the location list.
---
--- An empty result **clears** the list rather than leaving the previous run's
--- findings standing: "no issues" showing yesterday's dead links is worse than
--- showing nothing.
---@param bufnr? integer
---@return integer count
function M.check(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local diags = M.collect(bufnr)
  vim.diagnostic.set(M.namespace, bufnr, diags)
  -- Required here rather than at the top: this file loads its dependencies
  -- lazily, inside the functions that need them.
  require("lib.nvim.ui.list").qf(
    M.to_qf_entries(diags, bufnr),
    "markdown.nvim: link check",
    { open = false }
  )
  return #diags
end

--- Clear diagnostics previously set by `M.check`.
---@param bufnr? integer
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(M.namespace, bufnr)
end

return M
