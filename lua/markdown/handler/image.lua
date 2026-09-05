---@module 'markdown.handler.image'
local notify = require("markdown.util.notify").create("[markdown.handler.image]")
local platform = require("markdown.util.platform")

local M = {}

M.config = {
  resolve_relative_to_buffer = true,
  notify_on_error = true,
  -- What `mi` does when an in-Neovim preview provider (snacks.nvim or
  -- image.nvim) is installed. With none installed every value behaves like
  -- "system", since there is nothing else to offer.
  --   "ask"     → prompt for system app vs. in-Neovim preview (default)
  --   "preview" → always preview in Neovim, no prompt
  --   "system"  → always use the system viewer, no prompt (pre-9a behaviour)
  ---@type "ask"|"preview"|"system"
  preview = "ask",
}

local api = vim.api
-- DEP-01: matches the fallback pattern every other module in this repo
-- already uses, rather than the bare vim.loop this one had.
local uv = vim.uv or vim.loop

local function trim(s)
  if not s then return nil end
  return s:match("^%s*(.-)%s*$")
end

--- The image of the `<figure>`/`<picture>` block the cursor is *inside*.
---
--- This used to be a fixed-radius scan: any `<img src>` within a dozen lines
--- of the cursor, whether or not the cursor was in the same block -- or in
--- any block at all. That made `is_image_line()` true for ordinary prose
--- that merely sat near a picture, so `ma`/`mi` on a paragraph opened
--- whatever image happened to be nearby. `core.html_links` walks to the
--- block's real delimiters instead, so "inside a figure" and "near a figure"
--- stop being the same answer.
---@return string|nil
local function media_block_src()
  local ok_buf, bufnr = pcall(api.nvim_get_current_buf)
  if not ok_buf or not bufnr then return nil end

  local ok_cur, cursor = pcall(api.nvim_win_get_cursor, 0)
  local curline = (ok_cur and cursor and cursor[1]) or 1

  local link = require("markdown.core.html_links").media_at(bufnr, curline)
  return link and link.target or nil
end

local function extract_image_target_from_line(line)
  if not line or line == "" then return nil end

  -- Requires the leading `!` (real image syntax); a plain `[text](target)`
  -- link is not an image and must fall through to the link/file handlers.
  local t = line:match("!%b[]%(([^)]+)%)")

  if t and type(t) == "string" and t ~= "" then
    t = trim(t --[[@as string]])
    if t and t:match("^<.+>$") then t = t:sub(2, -2) end
    return t
  end

  local img_src = line:match('<img[^>]-src%s*=%s*"(.-)"') or line:match("<img[^>]-src%s*=%s*'(.-)'")
  if img_src and img_src ~= "" then return trim(img_src) end

  -- Nothing on this line -- but a `<figure>` is one picture spread over
  -- several, and the lines carrying no target of their own (the
  -- `<figcaption>`, the bare `</figure>`) are exactly where a reader parks.
  return media_block_src()
end

local function is_url(target) return target and target:match("^https?://") ~= nil end

local path = require("markdown.util.path")

local function resolve_target_to_path(target)
  if not target then return nil end
  if is_url(target) then return target end
  return path.resolve(target)
end

local function open_with_system_viewer(file_path)
  local ok, err = platform.open(file_path)
  if not ok and M.config.notify_on_error then
    notify.error("Failed to spawn viewer for: " .. tostring(err or file_path))
  end
  return ok
end

--- Render `path` inside Neovim, falling back to the system viewer if the
--- provider refuses (an unsupported terminal, a corrupt file). Falling back
--- rather than reporting an error keeps `mi` doing something useful either
--- way — the user asked to see the image, not to use a specific renderer.
---@param file_path string
---@return boolean ok
local function open_with_preview(file_path)
  local ok, err = require("lib.nvim.image_preview").preview(file_path)
  if ok then return true end
  if M.config.notify_on_error then
    notify.warn("In-Neovim preview failed (" .. tostring(err) .. "), using system viewer")
  end
  return open_with_system_viewer(file_path)
end

--- Open a resolved image. Mirrors `handler/file.lua`'s PDF path: if an
--- in-Neovim preview provider is installed, offer both; if not, go straight
--- to the system application with no prompt, since there is no alternative
--- to choose between.
---@param file_path string
---@return boolean ok
function M.open_image(file_path)
  -- A URL has no local file for a provider to read, so it always goes to the
  -- system handler (the browser), regardless of `preview`.
  if is_url(file_path) then return open_with_system_viewer(file_path) end

  local mode = M.config.preview or "ask"
  if mode == "system" then return open_with_system_viewer(file_path) end

  if not require("lib.nvim.image_preview").available() then
    return open_with_system_viewer(file_path)
  end

  if mode == "preview" then return open_with_preview(file_path) end

  require("markdown.util.picker").select(
    { "System app", "Preview in Neovim" },
    { prompt = "Open image with:" },
    function(choice)
      if choice == "Preview in Neovim" then
        open_with_preview(file_path)
      else
        open_with_system_viewer(file_path)
      end
    end
  )
  return true
end

function M.is_image_line(line) return extract_image_target_from_line(line) ~= nil end

function M.extract(line) return extract_image_target_from_line(line) end

function M.resolve(target) return resolve_target_to_path(target) end

function M.open(line)
  line = line or api.nvim_get_current_line()
  local target = extract_image_target_from_line(line)
  if not target then
    if M.config.notify_on_error then notify.info("No image/link found under cursor") end
    return false
  end

  local resolved = resolve_target_to_path(target)
  if not resolved or resolved == "" then
    if M.config.notify_on_error then
      notify.error("Could not resolve path: " .. tostring(target))
    end
    return false
  end

  if not is_url(resolved) then
    local stat = uv.fs_stat(resolved)
    if not stat then
      if M.config.notify_on_error then notify.warn("File does not exist: " .. resolved) end
      return false
    end
  end

  return M.open_image(resolved)
end

return M
