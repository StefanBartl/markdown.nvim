---@module 'markdown_nvim.handler'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.handler]")

local M = {}

local api = vim.api
local image = require("markdown_nvim.handler.image")
local url = require("markdown_nvim.handler.url")
local file = require("markdown_nvim.handler.file")
local anchor = require("markdown_nvim.anchor.jump")
local is_inside_toc_block = require("markdown_nvim.anchor.is_inside_toc_block")
local is_html_anchor_line = require("markdown_nvim.anchor.is_html_anchor_line")
local is_html_extern_anchor_line = require("markdown_nvim.anchor.is_html_extern_anchor_line")

local uv = vim.loop
local cfg = require("markdown_nvim.config").get

--- Decide whether a path should open in the system application (media/binary)
--- rather than via :edit (text-like). Driven by config.open.external_extensions.
---@param path string
---@return boolean
local function should_open_externally(path)
  local ext = path:match("%.([%w]+)$")
  if not ext then return false end
  ext = ext:lower()
  local list = (cfg().open and cfg().open.external_extensions) or {}
  for _, e in ipairs(list) do
    if e:lower() == ext then return true end
  end
  return false
end

local function slugify(s)
  if not s then return "" end
  local t = s:lower()
  t = t:gsub("%s*{#.-}$", "")
  t = t:gsub("<.->", "")
  t = t:gsub("[^%w%s-]", "")
  t = t:gsub("%s+", "-")
  t = t:gsub("-+", "-")
  t = t:gsub("^%-", ""):gsub("%-$", "")
  return t
end

local function escape_lua_pattern(s)
  return (s:gsub("([^%w])", "%%%1"))
end

local function strip_leading_hash(s)
  if not s then return s end
  return s:gsub("^%s*#%s*", "")
end

local function search_and_jump_to_fragment(fragment)
  if not fragment or fragment == "" then return false end

  local frag = strip_leading_hash(fragment)
  local frag_esc = escape_lua_pattern(frag)

  local bufnr = api.nvim_get_current_buf()
  local total = api.nvim_buf_line_count(bufnr)
  local in_fence = false
  local fence_pattern = "^%s*([`~]{3,})%S*%s*$"

  for i = 1, total do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""

    if line:match(fence_pattern) then
      in_fence = not in_fence
    end
    if not in_fence then
      local id_pattern = "id%s*=%s*['\"]?#?" .. frag_esc .. "['\"]?"
      if line:match(id_pattern) then
        api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end

      if line:match("{#*" .. frag_esc .. "}") then
        api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end

      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local base = slugify(title)
        if base == "" then base = "section-" .. i end
        if base == frag then
          api.nvim_win_set_cursor(0, { i, 0 })
          vim.cmd("normal! zz")
          return true
        end
        if frag:match("^" .. escape_lua_pattern(base) .. "%-?%d*$") then
          api.nvim_win_set_cursor(0, { i, 0 })
          vim.cmd("normal! zz")
          return true
        end
      end
    end
  end

  local radius = 5
  for i = 1, total do
    local start_line = i
    local end_line = math.min(total, i + radius)
    local ok, chunk_lines = pcall(api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
    if ok and chunk_lines then
      local chunk = table.concat(chunk_lines, " ")
      if chunk:match("id%s*=%s*['\"]?#?" .. frag_esc .. "['\"]?") or chunk:match("{#*" .. frag_esc .. "}") then
        api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end
      if
        (chunk:lower():match("<figure") or chunk:lower():match("<img") or chunk:lower():match("<figcaption"))
        and chunk:match(frag_esc)
      then
        api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end
    end
  end

  for i = 1, total do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""
    if line:match(frag_esc) then
      if line:match("id") or line:match("style") or line:match("figure")
        or line:match("img") or line:match("figcaption")
        or line:match("src") or line:match("alt")
      then
        api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end
    end
  end

  return false
end

local function resolve_target_path(target)
  if not target then return nil end
  if target:match("^https?://") then return target end
  local expanded = vim.fn.expand(target)
  if not expanded:match("^/") and not expanded:match("^%a:[/\\]") then
    local bufdir = vim.fn.expand("%:p:h")
    if bufdir and bufdir ~= "" then
      expanded = vim.fn.fnamemodify(bufdir .. "/" .. expanded, ":p")
    else
      expanded = vim.fn.fnamemodify(expanded, ":p")
    end
  else
    expanded = vim.fn.fnamemodify(expanded, ":p")
  end
  return expanded
end

local function open_file_in_current_window(path)
  if not path or path == "" then return false end
  if path:match("^https?://") then return url.open(path) end
  local stat = uv.fs_stat(path)
  if not stat then
    notify.warn("External anchor: target file not found: " .. tostring(path))
    return false
  end
  -- Media/binary -> system app; text-like -> open in the current window.
  if should_open_externally(path) then
    return file.system_open(path)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return true
end

--- Open a raw target string (URL / path / anchor), resolving relative paths
--- against the current buffer's directory. URLs open in the system browser,
--- in-document anchors jump within the buffer, existing files open in the
--- current window. Used by `:Markdown links show` and the multi-link `ml`
--- fallback.
---@param target string
---@return boolean ok
function M.open_target(target)
  if not target or target == "" then return false end

  if target:match("^https?://") then
    return url.open(target)
  end

  if target:match("^#") then
    return search_and_jump_to_fragment(target)
  end

  local resolved = resolve_target_path(target)
  if not resolved then
    notify.warn("Could not resolve target: " .. tostring(target))
    return false
  end
  return open_file_in_current_window(resolved)
end

--- Handle the cursor/mouse action (open anchor/image/URL/file under cursor).
--- `opts.silent`: suppress the final "nothing found" info notification —
--- used for mouse-triggered invocations (double-click / ctrl-click), where a
--- miss is a normal, frequent outcome rather than something to report. Actual
--- problems (unresolvable target, missing file, ...) still notify regardless.
---@param opts? { silent?: boolean }
function M.handle_cursor_action(opts)
  local silent = opts and opts.silent
  local line = api.nvim_get_current_line()

  if line and line:match("%(#[^)]+%)") then
    if is_inside_toc_block() or line:match("^%s*%-+%s*%[") then
      anchor.jump()
      return
    end
  end

  if is_html_anchor_line(line) then
    anchor.jump()
    return
  end

  local ext = is_html_extern_anchor_line(line)
  if ext and ext.target then
    local target = ext.target
    local fragment = ext.fragment
    local resolved = resolve_target_path(target)
    if not resolved then
      notify.warn("External anchor: could not resolve target: " .. tostring(target))
    else
      local ok = open_file_in_current_window(resolved)
      if ok then
        if fragment and fragment ~= "" then
          local jumped = search_and_jump_to_fragment(fragment)
          if not jumped then
            notify.info("External anchor: opened file but anchor '" .. fragment .. "' not found")
          end
        end
        return
      end
    end
  end

  if image.is_image_line(line) then
    image.open(line)
    return
  end

  -- Cursor-aware link/URL resolution (Feature 4):
  --   * cursor on a link  -> use that one
  --   * exactly one link  -> use it even if the cursor is elsewhere
  --   * multiple links    -> let the user choose via the picker
  local scan = require("markdown_nvim.core.link_scan")
  local row = api.nvim_win_get_cursor(0)[1]
  local links = scan.from_line(line, row)

  if #links > 0 then
    local col = api.nvim_win_get_cursor(0)[2]

    for _, lk in ipairs(links) do
      if col >= lk.col and col <= lk.col_end then
        M.open_target(lk.target)
        return
      end
    end

    if #links == 1 then
      M.open_target(links[1].target)
      return
    end

    local conf = cfg()
    require("markdown_nvim.util.picker").select(links, {
      prompt  = string.format("Links on line (%d)", #links),
      format  = function(lk) return lk.display end,
      backend = (conf.links and conf.links.picker) or "hover_select",
    }, function(lk)
      M.open_target(lk.target)
    end)
    return
  end

  -- No structured markdown link / URL found: fall back to the legacy
  -- single-target heuristics (handles bare file paths, HTML src, etc.).
  if file.is_file_line(line) then
    file.open(line)
    return
  end

  if not silent then
    notify.info("Handler: No recognized target under cursor")
  end
end

return M
