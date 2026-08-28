---@module 'markdown.hover'
---@brief Hover preview for the link under the cursor (or mouse).
---@description
--- Cursor sits on a markdown link ⇒ a small float shows what it points at,
--- whatever that is: an image, a PDF page, another markdown file's section,
--- a plain file's head, a directory listing, an in-page anchor, a URL — or,
--- when the target does not exist, *that*, which is often the most useful
--- answer of all.
---
--- Nothing here re-parses markdown: link detection is
--- `markdown.core.link_scan`, which already handles inline links, bare URLs,
--- `<…>` autolinks and trailing-punctuation trimming. Classification is
--- `markdown.hover.classify`, presentation `markdown.hover.float`, and the
--- per-type content comes from `markdown.hover.preview.*`.
---
--- Asynchronous previews (PDF rasterization, URL fetch) are guarded by a
--- generation counter: if the cursor moves on before the result lands, the
--- result is dropped rather than opening a float for a link the user has
--- already left.

local M = {}

local api = vim.api

local autocmd = require("lib.nvim.bindings.autocmd")
local classify = require("markdown.hover.classify")
local float = require("markdown.hover.float")
local notify = require("markdown.util.notify").create("[markdown.hover]")

---@type integer Bumped on every request; stale async results compare against it.
local _generation = 0
---@type Lib.Debounce.Handle|nil
local _debounced = nil
---@type table|nil LRU cache of built content, keyed by target identity.
local _cache = nil

---@internal
---@return Mkdn.HoverConfig
local function cfg()
  local ok, config = pcall(require, "markdown.config")
  local c = ok and config.get() or {}
  return c.hover or {}
end

---@internal
---@return table
local function cache()
  if _cache then return _cache end
  local ok, lru = pcall(require, "lib.lua.memo.lru")
  if ok and lru and lru.new then
    _cache = lru.new(64)
  else
    -- Plain table fallback: unbounded, but a hover cache holds short strings
    -- and the module still works without lib.lua.memo.
    local store = {}
    _cache = {
      get = function(_, key) return store[key] end,
      put = function(_, key, value) store[key] = value end,
    }
  end
  return _cache
end

---@internal
--- Identity of a target for caching. Includes mtime so an edited file is
--- re-read rather than served stale.
---@param target Mkdn.Hover.Target
---@return string
local function cache_key(target)
  local mtime = ""
  if target.path then
    local uv = vim.uv or vim.loop
    local stat = uv.fs_stat(target.path)
    if stat and stat.mtime then mtime = tostring(stat.mtime.sec) end
  end
  return table.concat(
    { target.type, target.raw, target.path or "", target.anchor or "", mtime },
    "|"
  )
end

--- The link under the cursor in `bufnr`, or nil.
---
--- Unlike `markdown.handler`, this does *not* fall back to "the only link on
--- the line": a hover must describe what the cursor is actually on, or it
--- would pop up while the cursor sits in unrelated text.
---@param bufnr? integer
---@return Mkdn.Link|nil
function M.link_under_cursor(bufnr)
  -- `0` means "current buffer" by Neovim convention but is truthy in Lua, so
  -- `bufnr or ...` would leave it as 0 and the window/buffer check below would
  -- then compare a real handle against 0 and always bail out.
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= bufnr then return nil end

  local pos = api.nvim_win_get_cursor(win)
  local row, col = pos[1], pos[2]
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line then return nil end

  local links = require("markdown.core.link_scan").from_line(line, row)
  for _, link in ipairs(links) do
    if col >= link.col and col <= link.col_end then return link end
  end

  -- Nothing on this line -- but a `<figure>` block is one link spread over
  -- several, and the line the reader parks on is usually the `<figcaption>`,
  -- which carries no target of its own. Resolving the enclosing figure's
  -- image makes the caption hover like the picture it captions.
  local figure = require("markdown.core.html_links").figure_at(bufnr, row)
  if figure then return figure end

  -- Still nothing: the text may be a path carrying no link syntax at all --
  -- a path in prose, in a code comment, in a `:messages` dump. Same target
  -- shape, so everything downstream (classify/build/preview) is unchanged.
  -- Opt-out via `hover.bare_paths`, and off entirely for a buffer that
  -- `attach` did not enable it for.
  if cfg().bare_paths == false then return nil end
  return require("markdown.hover.bare_path").under_cursor(bufnr)
end

---@internal
--- How long an async preview may take before it is allowed to interrupt the
--- reader with a placeholder. Below this, waiting quietly and showing only
--- the result reads as instant; above it, silence reads as breakage.
---
--- Configurable as `hover.placeholder_grace_ms`, because "instant" is a
--- property of the machine: on a fast one 250ms hides every placeholder that
--- would only have flickered, on a slow one it hides the reassurance that
--- something is happening at all.
---@return integer
local function placeholder_grace_ms()
  local ok, config = pcall(require, "markdown.config")
  if not ok or type(config.get) ~= "function" then return 250 end
  local n = ((config.get() or {}).hover or {}).placeholder_grace_ms
  return (type(n) == "number" and n >= 0) and n or 250
end

---@internal
--- Build the content for `target`, then hand it to `emit`. Synchronous
--- previewers call `emit` immediately; async ones later.
---@param target Mkdn.Hover.Target
---@param bufnr integer
---@param opts Mkdn.Hover.PreviewOpts
---@param emit fun(content: Mkdn.Hover.Content|nil)
local function build(target, bufnr, opts, emit)
  local text = require("markdown.hover.preview.text")

  if target.type == "anchor" then
    emit(text.anchor(target, opts, bufnr))
  elseif target.type == "missing" then
    emit(text.missing(target))
  elseif target.type == "directory" then
    emit(text.directory(target, opts))
  elseif target.type == "markdown" and target.anchor and target.anchor ~= "" then
    emit(text.file_anchor(target, opts))
  elseif target.type == "markdown" or target.type == "file" then
    emit(text.file(target, opts))
  elseif target.type == "image" then
    emit(require("markdown.hover.preview.media").image(target, opts))
  elseif target.type == "pdf" then
    local media = require("markdown.hover.preview.media")
    local generation = _generation
    local settled = false

    local provisional = media.pdf(target, opts, function(content)
      settled = true
      -- The cursor moved on while pdftoppm ran: the page is kept for the next
      -- hover (media owns it now), but nothing opens over the link the reader
      -- has already left.
      if generation ~= _generation then return end
      emit(content)
    end)

    if not provisional.pending then
      emit(provisional)
    else
      -- Hold the "rendering page 1…" float back. A render that beats the
      -- grace period shows the finished page and nothing else — no flash of
      -- a differently sized text float first. One that misses it has a real
      -- wait to explain, and then the float is worth its interruption.
      vim.defer_fn(function()
        if settled or generation ~= _generation then return end
        emit(provisional)
      end, placeholder_grace_ms())
    end
  elseif target.type == "url" then
    local url = require("markdown.hover.preview.url")
    if opts.url_fetch then
      local generation = _generation
      url.fetch(target, opts, function(content)
        if generation ~= _generation then return end
        vim.schedule(function()
          if generation == _generation then emit(content) end
        end)
      end)
    else
      emit(url.offline(target))
    end
  else
    emit(nil)
  end
end

--- Show the hover for the link under the cursor. No-op when there is none.
---@param opts? { force?: boolean } `force` ignores the enabled flag.
---@return boolean shown
function M.show(opts)
  opts = opts or {}
  local c = cfg()
  if not opts.force and c.enabled == false then return false end

  local bufnr = api.nvim_get_current_buf()
  local link = M.link_under_cursor(bufnr)
  if not link then
    float.close()
    return false
  end

  _generation = _generation + 1
  local generation = _generation

  local source = api.nvim_buf_get_name(bufnr)
  local target = classify.classify(link.target, source ~= "" and source or nil)

  local preview_opts = {
    max_lines = c.max_lines or 20,
    max_width = c.max_width or 80,
    inline_images = c.inline_images,
    url_fetch = c.url and c.url.fetch == true,
    url_timeout_ms = c.url and c.url.timeout_ms or 2000,
  }

  local key = cache_key(target)
  local cached = cache():get(key)

  local function present(content)
    if generation ~= _generation then return end
    if not content then return end
    float.open(content.lines, {
      title = content.title,
      filetype = content.filetype,
      canvas = content.canvas,
      max_width = c.max_width or 80,
      max_height = c.max_lines or 20,
      border = c.border,
    })
    -- An image target draws over the float it just opened.
    if content.image_path then
      local win = float.win()
      if win then
        local on_close = require("markdown.hover.preview.media").draw_into(content.image_path, win)
        if on_close then float.set_on_close(on_close) end
      end
    end
  end

  if cached and not cached.pending then
    present(cached)
    return true
  end

  build(target, bufnr, preview_opts, function(content)
    if content and not content.pending then cache():put(key, content) end
    present(content)
  end)

  return true
end

--- Close any open hover.
function M.hide() float.close() end

--- Open the *full* thing the link under the cursor points at, in whatever
--- surface already owns that job: `mdview.nvim` for markdown, a full-screen
--- `images.zen` window for a picture, the existing PDF/file/URL openers for
--- everything else. The hover float is the fast, cheap answer; this is the
--- escalation for when it is not enough.
---
--- Deliberately reuses each target's existing opener rather than growing a
--- second one here: `markdown.commands.mdview` already knows whether
--- mdview.nvim is installed and warns if not, `markdown.handler.file`
--- already prompts system-vs-pdfport for a `.pdf`, and `images.zen.open`
--- takes an explicit path -- it does not touch `images.nvim`'s own
--- under-cursor resolution, so this does not depend on that (currently
--- being reworked) matching logic at all.
---@return boolean handled
function M.escalate()
  local bufnr = api.nvim_get_current_buf()
  local link = M.link_under_cursor(bufnr)
  if not link then
    notify.info("escalate: no link under cursor")
    return false
  end

  local source = api.nvim_buf_get_name(bufnr)
  local target = classify.classify(link.target, source ~= "" and source or nil)

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

--- Debounced entry point used by the CursorHold/mouse autocmds.
function M.trigger()
  local c = cfg()
  if c.enabled == false then return end

  if not _debounced then
    local ok, debounce = pcall(require, "lib.nvim.debounce")
    if ok and debounce and debounce.new then
      _debounced = debounce.new(function() M.show() end, c.delay_ms or 250)
    else
      -- Without lib.nvim.debounce, run undebounced rather than not at all.
      _debounced = { call = function() M.show() end, cancel = function() end }
    end
  end
  _debounced.call()
end

--- Install the hover autocmds for `bufnr`.
---
--- Since `hover.filetypes` defaults to every filetype (see
--- `markdown.bindings.autocmds`), the buffers that must be excluded are
--- excluded here rather than by pattern: a picker, a file tree, a terminal or
--- a dashboard has no document to hover in, and a float opening over one is
--- always wrong. `buftype ~= ""` catches all of them in one check, which a
--- filetype blocklist could never keep up with.
---@param bufnr integer
function M.attach(bufnr)
  local c = cfg()
  if c.enabled == false then return end
  if not api.nvim_buf_is_valid(bufnr) then return end
  if vim.bo[bufnr].buftype ~= "" then return end

  local group = autocmd.group("MarkdownHover" .. bufnr, true)
  local triggers = c.trigger or { "CursorHold" }

  if vim.tbl_contains(triggers, "CursorHold") then
    autocmd.create("CursorHold", function() M.trigger() end, {
      group = group,
      buffer = bufnr,
      desc = "[markdown.nvim] hover: show the link under the cursor on CursorHold",
    })
  end

  if vim.tbl_contains(triggers, "mouse") then
    -- Mouse hovering needs `mousemoveevent`; it is a global user setting and
    -- is deliberately NOT set here (see README) -- without it this autocmd
    -- simply never fires.
    autocmd.create("CursorMoved", function() M.trigger() end, {
      group = group,
      buffer = bufnr,
      desc = "[markdown.nvim] hover: show the link under the mouse (needs 'mousemoveevent')",
    })
  end

  autocmd.create({ "BufLeave", "InsertEnter" }, function() M.hide() end, {
    group = group,
    buffer = bufnr,
    desc = "[markdown.nvim] hover: hide when leaving the buffer or entering insert",
  })
end

return M
