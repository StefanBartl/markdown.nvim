---@module 'markdown.commands.links'
--- `:Markdown links <sub>` router.
---   show     [%|cwd|<file>]   Collect links in the scope and open the chosen one.
---   create   [-r] [...] <p>   Generate markdown links from filesystem paths.
---   sanitize [%|cwd|<file>]   Normalize link-target paths (./, forward slashes).
--- A bare path (no known subcommand) defaults to `create` for backwards compat.
local notify = require("markdown.util.notify").create("[markdown.commands.links]")
local progress = require("markdown.util.progress")

local M = {}

local uv = vim.uv or vim.loop
local globbable = require("lib.nvim.fs.globbable")

--- Files processed per event-loop tick once a `cwd` scope spans more than
--- this. `collect` reads+parses each file and `sanitize` reads+writes each, so
--- a big docs tree freezes the editor in one synchronous loop. A smaller scope
--- stays synchronous with no indicator.
local CHUNK = 20

-- ---------------------------------------------------------------------------
-- create (delegates to the existing filesystem-link generator)
-- ---------------------------------------------------------------------------

---@internal
---@param argv string[]
local function do_create(argv) require("markdown.commands.markdown_links").run(argv) end

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

--- Collect links for a scope, delivering the enriched list (targets already
--- resolved for links from a file on disk) through `on_done`. The `%`/buffer
--- and single-file scopes finish synchronously — `on_done` just fires within
--- the call. A `cwd` scope over more than `CHUNK` files reads and parses them
--- in chunks across event-loop ticks with a progress indicator.
---@param scope string
---@param on_done fun(links: Mkdn.Link[])
local function collect(scope, on_done)
  local scan = require("markdown.core.link_scan")

  if scope == "" or scope == "%" then
    -- Current buffer: leave targets relative (handler resolves to buffer dir).
    on_done(scan.from_buffer(0))
    return
  end

  local function links_from_file(path)
    local lines = vim.fn.readfile(path)
    local base = vim.fn.fnamemodify(path, ":p:h")
    local found = scan.from_lines(lines)
    for _, lk in ipairs(found) do
      lk.target = resolve_against(lk.target, base)
      lk.file = path
    end
    return found
  end

  if scope == "cwd" then
    local md_files = vim.fn.globpath(globbable(vim.fn.getcwd()), "**/*.md", false, true)
    local out = {}

    if #md_files <= CHUNK then
      for _, path in ipairs(md_files) do
        for _, lk in ipairs(links_from_file(path)) do
          out[#out + 1] = lk
        end
      end
      on_done(out)
      return
    end

    local h = progress.create("scanning links…", #md_files)
    local i = 0
    local function step()
      if h and h.cancelled then
        on_done(out)
        return
      end
      local last = math.min(i + CHUNK, #md_files)
      for j = i + 1, last do
        for _, lk in ipairs(links_from_file(md_files[j])) do
          out[#out + 1] = lk
        end
      end
      i = last
      if h then h:update({ text = "scanning links…", current = i, total = #md_files }) end
      if i < #md_files then
        vim.schedule(step)
        return
      end
      if h then h:finish(string.format("%d link(s) in %d file(s)", #out, #md_files)) end
      on_done(out)
    end
    step()
    return
  end

  -- Treat scope as a file path.
  local path = vim.fn.expand(scope)
  if uv.fs_stat(path) then
    on_done(links_from_file(path))
    return
  end

  notify.warn("links show: scope not found: " .. tostring(scope))
  on_done({})
end

---@internal
---@param lk Mkdn.Link
---@return string
local function format_item(lk)
  local where = lk.file and (" — " .. vim.fn.fnamemodify(lk.file, ":t")) or ""
  return lk.display .. where
end

local IMAGE_EXTS = { png = 1, jpg = 1, jpeg = 1, gif = 1, webp = 1, bmp = 1, svg = 1 }

---@internal
--- Extension-only check, deliberately not a call into images.nvim's own
--- config (`extensions`): classifying a link as "image-shaped" for preview
--- purposes should not need images.nvim installed at all, only its presence
--- as a preview *provider* is optional (see `images_browse` below).
---@param target string|nil
---@return boolean
local function is_image_target(target)
  if not target then return false end
  local ext = target:match("%.([%w]+)%s*$") or target:match("%.([%w]+)[?#]")
  return ext ~= nil and IMAGE_EXTS[ext:lower()] == 1
end

---@internal
--- snacks.picker module, if installed.
---@return table|nil
local function snacks_picker()
  local ok, picker = pcall(require, "snacks.picker")
  return (ok and type(picker) == "table") and picker or nil
end

---@internal
--- images.nvim's browse module, soft dep — only its already-public
--- `draw_in_window(file, winid)` helper is used here (drawing an image into
--- an arbitrary already-open window's geometry), the same primitive
--- images.nvim's own `:Image pickers` preview uses. No new API needed there.
---@return table|nil
local function images_browse()
  local ok, browse = pcall(require, "images.browse")
  return (ok and type(browse) == "table" and browse.draw_in_window) and browse or nil
end

---@internal
--- `:Markdown links show` with a live image preview, via snacks.picker +
--- images.nvim (both soft deps, same "checked and only works with snacks"
--- reasoning as for `pickers.nvim` — the generic
--- `markdown.util.picker` abstraction has no cross-backend preview hook).
---@param links Mkdn.Link[]
---@param Picker table
---@param browse table
local function do_show_snacks(links, Picker, browse)
  local items = {}
  for i, lk in ipairs(links) do
    items[i] = { text = format_item(lk), link = lk }
  end

  Picker.pick({
    source = "markdown_links",
    title = string.format("Markdown links (%d)", #links),
    items = items,
    format = "text",
    preview = function(ctx)
      ctx.preview:reset()
      local lk = ctx.item.link
      if not (lk and is_image_target(lk.target)) then
        ctx.preview:notify("No preview for this link type", "info")
        return
      end
      local resolved = require("markdown.util.path").resolve(lk.target)
      if not resolved then
        ctx.preview:notify("Could not resolve: " .. lk.target, "warn")
        return
      end
      local ok_guard, guard = pcall(require, "images.guard")
      if ok_guard then pcall(guard.check) end
      if not browse.draw_in_window(resolved, ctx.win) then
        ctx.preview:notify("Image can't be drawn here", "warn")
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.link then require("markdown.handler").open_target(item.link.target) end
    end,
    -- The overlay is attached to the terminal, not the picker window — left
    -- hanging until the next full repaint otherwise, same reasoning as
    -- images.browse's own on_close.
    on_close = function()
      pcall(function() require("images.terminal").clear() end)
    end,
  })
end

---@internal
---@param argv string[]
local function do_show(argv)
  local cfg = require("markdown.config").get()
  local scope = argv[1] or "%"

  collect(scope, function(links)
    if #links == 0 then
      notify.info("No links found in scope: " .. scope)
      return
    end

    -- Live preview only pays for itself with snacks.picker + images.nvim both
    -- present, and only when there is actually an image link to preview —
    -- otherwise the plain cross-backend picker below is exactly as good.
    local has_image = false
    for _, lk in ipairs(links) do
      if is_image_target(lk.target) then
        has_image = true
        break
      end
    end

    if has_image then
      local Picker = snacks_picker()
      local browse = images_browse()
      if Picker and browse then
        do_show_snacks(links, Picker, browse)
        return
      end
    end

    local picker = require("markdown.util.picker")
    picker.select(links, {
      prompt = string.format("Markdown links (%d)", #links),
      format = format_item,
      backend = (cfg.links and cfg.links.picker) or "hover_select",
    }, function(lk) require("markdown.handler").open_target(lk.target) end)
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
    -- `:copen`, not `:lopen`. The old message named the location list, which
    -- `vim.diagnostic.set` never populates -- following that advice raised
    -- E776. `check` now fills the quickfix list, matching `refs check`.
    notify.warn(
      string.format("Link check: %d issue(s) — see vim.diagnostic.open_float() / :copen", count)
    )
  end
end

-- ---------------------------------------------------------------------------
-- sanitize
-- ---------------------------------------------------------------------------

local function do_sanitize(argv)
  local sanitize = require("markdown.core.link_sanitize")
  local scope = argv[1] or "%"

  if scope == "" or scope == "%" then
    local n = sanitize.buffer(0)
    notify.info(
      n > 0 and string.format("links sanitize: normalized %d link target(s)", n)
        or "links sanitize: nothing to normalize"
    )
    return
  end

  if scope == "cwd" then
    local files = vim.fn.globpath(globbable(vim.fn.getcwd()), "**/*.md", false, true)
    local total, touched = 0, 0

    local function done()
      notify.info(
        string.format(
          "links sanitize: normalized %d link target(s) across %d file(s)",
          total,
          touched
        )
      )
    end

    local function sanitize_one(path)
      local n = sanitize.path(path)
      if n > 0 then
        total = total + n
        touched = touched + 1
      end
    end

    if #files <= CHUNK then
      for _, path in ipairs(files) do
        sanitize_one(path)
      end
      done()
      return
    end

    -- Chunked: sanitize.path reads and writes each file, so a large tree is a
    -- multi-second freeze done in one loop.
    local h = progress.create("sanitizing links…", #files)
    local i = 0
    local function step()
      if h and h.cancelled then
        done()
        return
      end
      local last = math.min(i + CHUNK, #files)
      for j = i + 1, last do
        sanitize_one(files[j])
      end
      i = last
      if h then h:update({ text = "sanitizing links…", current = i, total = #files }) end
      if i < #files then
        vim.schedule(step)
        return
      end
      if h then h:finish(string.format("%d link(s) in %d file(s)", total, touched)) end
      done()
    end
    step()
    return
  end

  local path = vim.fn.expand(scope)
  if not uv.fs_stat(path) then
    notify.warn("links sanitize: scope not found: " .. tostring(scope))
    return
  end
  local n = sanitize.path(path)
  notify.info(
    n > 0 and string.format("links sanitize: normalized %d link target(s)", n)
      or "links sanitize: nothing to normalize"
  )
end

-- ---------------------------------------------------------------------------
-- dispatch
-- ---------------------------------------------------------------------------

local subcommands = {
  show = do_show,
  create = do_create,
  check = do_check,
  sanitize = do_sanitize,
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

--- Completion for `:Markdown links …`: the sub-subcommand, then whatever that
--- sub takes — `show`'s scope (`%` | `cwd` | a file), `create`'s paths.
---@param arglead string
---@param cmdline string?
---@return string[]
function M.complete(arglead, cmdline)
  -- tokens: Markdown(1) links(2) <sub>(3) <arg>(4…). The slot being completed
  -- is one past the last token when arglead is empty, else the last token.
  local tokens = vim.split(vim.trim(cmdline or ""), "%s+")
  local sub = tokens[3]
  local slot = (arglead == "") and (#tokens + 1) or #tokens

  if sub and slot >= 4 then
    if sub == "show" then
      -- One scope argument only; nothing to offer past it.
      if slot > 4 then return {} end
      local out = {}
      if vim.startswith("%", arglead) then out[#out + 1] = "%" end
      if vim.startswith("cwd", arglead) then out[#out + 1] = "cwd" end
      vim.list_extend(out, vim.fn.getcompletion(arglead, "file"))
      return out
    end
    -- `create` takes one or more filesystem paths (plus its own -r flag,
    -- which markdown_links parses); `check` takes nothing.
    if sub == "create" then return vim.fn.getcompletion(arglead, "file") end
    return {}
  end

  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
