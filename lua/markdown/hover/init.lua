---@module 'markdown.hover'
---@brief markdown.nvim's contribution to the hover, plus the public entry points.
---@description
--- The hover framework itself lives in `lib.nvim.hover` — classification, the
--- float, file/directory/URL previews, the debounce, the LRU cache, and
--- bare-path detection are all "a path is a path" and were never markdown.
--- What this module keeps is the part that genuinely is:
---
---   * **finding a target**: an inline link, a bare URL, an autolink
---     (`markdown.core.link_scan`), or a `<figure>` block resolved as a unit
---     (`markdown.core.html_links`), and
---   * **section previews**: `#heading` and `file.md#heading`, which need GFM
---     slugging and heading parsing (`markdown.hover.section`).
---
--- Both are handed over through `lib.nvim.hover.registry`, so the library
--- reaches them without knowing this plugin exists. `escalate()` stays here
--- too: opening the *full* thing is routed per target type into markdown.nvim's
--- own openers (mdview, the PDF chooser, the platform opener), none of which
--- belong in a library either.
---
--- `M.show`, `M.hide`, `M.trigger` and `M.attach` remain as they were, now
--- delegating — they were public API before the move.

local M = {}

local api = vim.api

local notify = require("markdown.util.notify").create("[markdown.hover]")

---@return table
local function lib() return require("lib.nvim.hover") end

---@type boolean
local _registered = false

---@internal
--- Hand markdown.nvim's source and section previews to the framework.
---
--- Called from every public entry point, not just `setup()`: without it, a
--- direct `markdown.hover.show()` (or a test, or another plugin calling
--- `link_under_cursor`) would ask a framework that has never been told this
--- plugin can read markdown links, and get back only bare-path results.
---
--- Idempotent twice over — the flag skips the work, and the registry keys
--- contributions by plugin name, so even a forced re-run replaces this
--- plugin's entry rather than stacking a second link scanner that would fire
--- on every hover.
---@return nil
local function register()
  if _registered then return end
  local ok, registry = pcall(require, "lib.nvim.hover.registry")
  if not ok then return end
  _registered = true

  registry.register("markdown.nvim", {
    sources = {
      ---@param bufnr integer
      ---@param row integer 1-based
      ---@param col integer 0-based
      ---@return string|nil target
      ---@return table|nil extra
      function(bufnr, row, col)
        local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        if not line then return nil end

        for _, link in ipairs(require("markdown.core.link_scan").from_line(line, row)) do
          if col >= link.col and col <= link.col_end then
            return link.target, { col = link.col, col_end = link.col_end, kind = "mdlink" }
          end
        end

        -- A `<figure>` block is one link spread over several lines, and the
        -- line the reader parks on is usually the `<figcaption>`, which
        -- carries no target of its own. Resolving the enclosing figure makes
        -- the caption hover like the picture it captions.
        local figure = require("markdown.core.html_links").figure_at(bufnr, row)
        if figure then return figure.target, { kind = "figure" } end

        return nil
      end,
    },
    previews = {
      -- In-page `#heading`, read out of the buffer being hovered in.
      anchor = function(target, opts, bufnr)
        return require("markdown.hover.section").anchor(target, opts, bufnr)
      end,
      -- `file.md#heading`. Without a fragment there is nothing markdown-
      -- specific to add, so it declines and the library's plain file preview
      -- (which already sets `filetype = markdown`) handles it.
      markdown = function(target, opts)
        if not (target.anchor and target.anchor ~= "") then return nil end
        return require("markdown.hover.section").file_anchor(target, opts)
      end,
    },
  })
end

--- The link (or bare path) under the cursor. Delegates to the framework,
--- which asks this plugin's registered source first.
---@param bufnr? integer
---@return Lib.Hover.Source|nil
function M.link_under_cursor(bufnr)
  register()
  return lib().target_under_cursor(bufnr)
end

--- Show the hover for whatever is under the cursor.
---@param opts? { force?: boolean }
---@return boolean shown
function M.show(opts)
  register()
  return lib().show(opts)
end

--- Close any open hover.
---@return nil
function M.hide() lib().hide() end

--- Debounced entry point used by the CursorHold/mouse autocmds.
---@return nil
function M.trigger()
  register()
  lib().trigger()
end

--- Install the hover autocmds for `bufnr`, after registering this plugin's
--- contributions.
---@param bufnr integer
---@return nil
function M.attach(bufnr)
  register()
  lib().attach(bufnr)
end

--- Push markdown.nvim's `hover` config into the framework.
---@param hover_cfg Lib.HoverConfig|nil
---@return nil
function M.configure(hover_cfg)
  register()
  lib().setup(hover_cfg)
end

--- Open the *full* thing the target under the cursor points at, in whatever
--- surface already owns that job: `mdview.nvim` for markdown, a full-screen
--- `images.zen` window for a picture, the existing PDF/file/URL openers for
--- everything else. The hover float is the fast, cheap answer; this is the
--- escalation for when it is not enough.
---
--- Deliberately reuses each target's existing opener rather than growing a
--- second one: `markdown.commands.mdview` already knows whether mdview.nvim
--- is installed and warns if not, `markdown.handler.file` already prompts
--- system-vs-pdfport for a `.pdf`, and `images.zen.open` takes an explicit
--- path.
---@return boolean handled
function M.escalate()
  register()
  local bufnr = api.nvim_get_current_buf()
  local found = M.link_under_cursor(bufnr)
  if not found then
    notify.info("escalate: no link under cursor")
    return false
  end

  local source = api.nvim_buf_get_name(bufnr)
  local target =
    require("lib.nvim.hover.classify").classify(found.target, source ~= "" and source or nil)

  if target.type == "markdown" then
    require("markdown.commands.mdview").run({ target.path })
    return true
  elseif target.type == "anchor" then
    -- In-page anchor: there is nowhere else to escalate to but a full render
    -- of the current file itself.
    require("markdown.commands.mdview").run({})
    return true
  elseif target.type == "image" then
    local ok, zen = pcall(require, "images.zen")
    if not ok or type(zen.open) ~= "function" then
      notify.warn("escalate: images.nvim not available")
      return false
    end
    zen.open(target.path)
    return true
  elseif target.type == "pdf" then
    require("markdown.handler.file").open_pdf(target.path)
    return true
  elseif target.type == "file" then
    require("markdown.handler.file").system_open(target.path)
    return true
  elseif target.type == "directory" then
    require("markdown.util.platform").open(target.path)
    return true
  elseif target.type == "url" then
    require("markdown.util.platform").open(target.url or target.raw)
    return true
  else -- "missing"
    notify.warn("escalate: " .. (target.reason or "target does not exist"))
    return false
  end
end

return M
