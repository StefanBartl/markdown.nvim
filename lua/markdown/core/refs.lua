---@module 'markdown.core.refs'
---@brief Keep in-document `#anchor` links (and the TOC) in sync with headings.
---@description
--- When a heading's text changes its GFM anchor changes, orphaning every
--- `[text](#old-anchor)` link that pointed at it. This module tracks heading
--- *identity* with extmarks (which ride along as the buffer is edited) so a
--- rename can be detected as `old-anchor -> new-anchor` and propagated to every
--- inline link plus the TOC.
---
--- Triggers (wired in `bindings.autocmds`, gated by `config.refs.mode`):
---   * "save"   — reconcile on `BufWritePre`
---   * "live"   — reconcile debounced after `TextChanged` (generous default)
---   * "off"    — only the manual `:Markdown refs sync` runs it
--- `:Markdown refs check` is always a non-destructive dry run.

local notify = require("markdown.util.notify").create("[markdown.core.refs]")
local slug = require("markdown.core.slug")
local cfg = require("markdown.config").get

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

local NS = api.nvim_create_namespace("markdown_refs")

-- Per-buffer state: extmark id -> last known anchor, the ordered anchor snapshot
-- (positional fallback), and the debounce timer.
---@type table<integer, { marks: table<integer,string>, last_list: string[], timer: any }>
local S = {}

---@internal
---@param bufnr integer
---@return { marks: table<integer,string>, last_list: string[], timer: any }
local function state(bufnr)
  S[bufnr] = S[bufnr] or { marks = {}, timer = nil }
  return S[bufnr]
end

-- ---------------------------------------------------------------------------
-- Baseline: one extmark per heading line, remembering its resolved anchor.
-- ---------------------------------------------------------------------------

--- (Re)establish the extmark baseline for `bufnr`. Existing marks are cleared;
--- a fresh mark is placed on every heading line. Rename detection compares a
--- later scan against the anchors recorded here. Also snapshots the ordered
--- anchor list for the positional fallback (see `positional_renames`).
---@param bufnr integer
function M.baseline(bufnr)
  local st = state(bufnr)
  api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  st.marks = {}
  st.last_list = {}

  local anchors = slug.heading_anchors(bufnr)
  for _, h in ipairs(anchors.list) do
    -- row is 1-indexed; extmarks are 0-indexed.
    local ok, id = pcall(api.nvim_buf_set_extmark, bufnr, NS, h.row - 1, 0, {})
    if ok then st.marks[id] = h.anchor end
    st.last_list[#st.last_list + 1] = h.anchor
  end
end

--- Positional fallback for renames that extmarks miss (a full-line replacement —
--- `cc`, `:s`, a formatter — deletes the heading line and its mark). When the
--- heading *count* is unchanged we can diff the ordered anchor lists by index:
--- a differing entry whose neighbours are unchanged is an isolated rename, not a
--- structural shift (an insert/delete makes a contiguous tail differ, so a
--- boundary neighbour won't match and we correctly skip it).
---@param old string[]|nil  baseline ordered anchors
---@param new string[]      current ordered anchors
---@param into table<string,string>  rename map to fill (old -> new)
---@internal
local function positional_renames(old, new, into)
  if not old or #old ~= #new then return end
  local n = #new
  for i = 1, n do
    if old[i] ~= new[i] then
      local left_ok = (i == 1) or (old[i - 1] == new[i - 1])
      local right_ok = (i == n) or (old[i + 1] == new[i + 1])
      if left_ok and right_ok and not into[old[i]] then into[old[i]] = new[i] end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Link rewriting
-- ---------------------------------------------------------------------------

--- Rewrite every `](#old)` -> `](#new)` for each entry in `renames`.
--- Only in-document anchor links are touched (a `(file.md#old)` never matches).
---@param bufnr integer
---@param renames table<string,string>  old anchor -> new anchor
---@return integer replaced  number of individual `](#anchor)` links rewritten
---@internal
local function apply_renames(bufnr, renames)
  if next(renames) == nil then return 0 end
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local replaced = 0

  for i, line in ipairs(lines) do
    if line:find("%]%(#") then
      local new_line = line
      for old, new in pairs(renames) do
        local n
        new_line, n = new_line:gsub("%]%(#" .. vim.pesc(old) .. "%)", "](#" .. new .. ")")
        replaced = replaced + n
      end
      if new_line ~= line then api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line }) end
    end
  end
  return replaced
end

--- Collect inline links whose `#anchor` target has no matching heading.
---@param bufnr integer
---@param set table<string,true>  valid anchors
---@return { lnum: integer, target: string, display: string }[]
---@internal
local function collect_orphans(bufnr, set)
  local scan = require("markdown.core.link_scan")
  local out = {}
  for _, lk in ipairs(scan.from_buffer(bufnr)) do
    if lk.kind == "mdlink" and lk.target and lk.target:match("^#") then
      local anchor = lk.target:sub(2)
      if anchor ~= "" and not set[anchor] then
        out[#out + 1] = { lnum = lk.lnum, target = lk.target, display = lk.display }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Reconcile
-- ---------------------------------------------------------------------------

--- Detect heading renames since the baseline, propagate them to links, refresh
--- the TOC (if one exists and `update_toc`), and report orphans. Safe to call
--- with no baseline: it establishes one, rebuilds the TOC and reports orphans,
--- but cannot retro-detect renames that happened before tracking started.
---@param bufnr? integer
---@param opts? { silent?: boolean }
---@return { renamed: integer, links: integer, orphans: table[] }
function M.reconcile(bufnr, opts)
  bufnr = bufnr or api.nvim_get_current_buf()
  opts = opts or {}
  local conf = cfg().refs or {}
  local st = state(bufnr)

  local anchors = slug.heading_anchors(bufnr)
  local by_row = anchors.by_row -- 1-indexed row -> anchor

  -- 1a) Primary: each tracked heading extmark whose current anchor differs from
  --     the remembered one is a rename (survives edits within the line).
  local renames = {}
  for id, old in pairs(st.marks) do
    local pos = api.nvim_buf_get_extmark_by_id(bufnr, NS, id, {})
    if pos and pos[1] ~= nil then
      local cur = by_row[pos[1] + 1] -- extmark row is 0-indexed
      if cur and cur ~= old and not renames[old] then renames[old] = cur end
    end
  end

  -- 1b) Fallback: positional diff catches renames where the extmark was dropped
  --     by a whole-line replacement (relevant mostly for save-mode).
  local current_list = {}
  for _, h in ipairs(anchors.list) do
    current_list[#current_list + 1] = h.anchor
  end
  positional_renames(st.last_list, current_list, renames)

  local renamed = 0
  for _ in pairs(renames) do
    renamed = renamed + 1
  end

  -- 2) Propagate renames into inline links.
  local links_changed = apply_renames(bufnr, renames)

  -- 4) Refresh the TOC in place (only if one already exists; never force-create).
  if conf.update_toc ~= false then
    local header = conf.toc_header
      or (require("markdown.config").get().toc or {}).header
      or "## Table of content"
    local total = api.nvim_buf_line_count(bufnr)
    local re = "^%s*" .. vim.pesc(header) .. "%s*$"
    local has_toc = false
    for i = 1, total do
      local l = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if l and l:match(re) then
        has_toc = true
        break
      end
    end
    if has_toc then pcall(function() require("markdown.commands.toc").update(header, {}) end) end
  end

  -- 5) Report orphans (recompute anchors post-rewrite for accuracy).
  local final = slug.heading_anchors(bufnr)
  local orphans = {}
  if (conf.orphans or "report") ~= "ignore" then orphans = collect_orphans(bufnr, final.set) end

  -- 6) Reset the baseline to the post-rewrite state: re-places every extmark and
  --    re-snapshots the ordered anchor list, so the next reconcile detects the
  --    NEXT round of edits cleanly (also restores marks a line-replace dropped).
  M.baseline(bufnr)

  if not opts.silent then
    local parts = {}
    if renamed > 0 then
      parts[#parts + 1] =
        string.format("%d heading(s) renamed, %d link(s) updated", renamed, links_changed)
    end
    if #orphans > 0 then
      parts[#parts + 1] = string.format("%d orphaned anchor link(s)", #orphans)
    end
    if #parts == 0 then
      notify.info("refs: nothing to sync")
    else
      notify.info("refs: " .. table.concat(parts, "; "))
    end
  end

  return { renamed = renamed, links = links_changed, orphans = orphans }
end

-- ---------------------------------------------------------------------------
-- Check (dry run)
-- ---------------------------------------------------------------------------

--- Non-destructive: list `#anchor` links with no matching heading. Fills the
--- quickfix list and notifies a count.
---@param bufnr? integer
---@return { lnum: integer, target: string }[]
function M.check(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local anchors = slug.heading_anchors(bufnr)
  local orphans = collect_orphans(bufnr, anchors.set)

  if #orphans == 0 then
    notify.info("refs check: all anchor links resolve")
    return orphans
  end

  local items = {}
  for _, o in ipairs(orphans) do
    items[#items + 1] = {
      bufnr = bufnr,
      lnum = o.lnum,
      col = 1,
      text = "broken anchor: " .. o.target,
    }
  end
  vim.fn.setqflist({}, " ", { title = "markdown.nvim: broken anchors", items = items })
  notify.warn(string.format("refs check: %d broken anchor link(s) — see :copen", #orphans))
  return orphans
end

-- ---------------------------------------------------------------------------
-- Live tracking (debounced)
-- ---------------------------------------------------------------------------

--- Called on TextChanged in live mode. Debounces a reconcile by
--- `config.refs.debounce_ms` (generous default to protect performance).
---@param bufnr integer
function M.on_change(bufnr)
  local st = state(bufnr)
  local delay = (cfg().refs and cfg().refs.debounce_ms) or 2000

  if st.timer then
    st.timer:stop()
    pcall(function() st.timer:close() end)
    st.timer = nil
  end

  local timer = uv.new_timer()
  st.timer = timer
  timer:start(delay, 0, function()
    timer:stop()
    pcall(function() timer:close() end)
    if st.timer == timer then st.timer = nil end
    vim.schedule(function()
      if api.nvim_buf_is_valid(bufnr) then pcall(M.reconcile, bufnr, { silent = true }) end
    end)
  end)
end

--- Establish tracking for `bufnr` (baseline). Idempotent per buffer.
---@param bufnr integer
function M.attach(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return end
  M.baseline(bufnr)
end

--- Tear down state for a buffer (e.g. on BufWipeout).
---@param bufnr integer
function M.detach(bufnr)
  local st = S[bufnr]
  if not st then return end
  if st.timer then
    st.timer:stop()
    pcall(function() st.timer:close() end)
  end
  pcall(api.nvim_buf_clear_namespace, bufnr, NS, 0, -1)
  S[bufnr] = nil
end

return M
