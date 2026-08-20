---@module 'markdown.hover.preview.media'
---@brief Image and PDF hover previews.
---@description
--- Both go through the same two-tier idea: show *metadata* in the float
--- always, and additionally draw the picture inline when a provider can do
--- it. Metadata alone is genuinely useful (dimensions, size, page count) and
--- always works; inline drawing depends on terminal graphics support that
--- cannot be assumed.
---
--- Neither previewer reimplements anything: image drawing goes through
--- `markdown.util.image_preview`'s provider detection (images.nvim / snacks
--- / image.nvim), and a PDF page becomes a PNG via `pdfport.render_page`,
--- whose own docs name exactly this use case ("lets consumers like
--- images.nvim show a PDF page as an image").

local M = {}

---@internal
---@param n integer|nil
---@return string
local function human_size(n)
  if not n then return "?" end
  local ok, fmt = pcall(require, "lib.lua.strings.format")
  if ok and fmt and fmt.format_bytes then return fmt.format_bytes(n) end
  return tostring(n) .. " B"
end

---@internal
--- Image dimensions without a decoder: parse just enough header bytes for
--- the common formats. Returns nil for anything else (SVG, AVIF, …) rather
--- than guessing — the float simply omits the dimension line then.
---@param path string
---@return integer|nil width
---@return integer|nil height
local function dimensions(path)
  local f = io.open(path, "rb")
  if not f then return nil, nil end
  local head = f:read(32) or ""
  f:close()
  if #head < 24 then return nil, nil end

  local byte = string.byte

  -- PNG: 8-byte signature, then IHDR with big-endian width/height at 16..23.
  if head:sub(1, 8) == "\137PNG\r\n\26\n" then
    local function be32(offset)
      return byte(head, offset) * 0x1000000
        + byte(head, offset + 1) * 0x10000
        + byte(head, offset + 2) * 0x100
        + byte(head, offset + 3)
    end
    return be32(17), be32(21)
  end

  -- GIF: "GIF87a"/"GIF89a", then little-endian width/height.
  if head:sub(1, 3) == "GIF" then
    return byte(head, 7) + byte(head, 8) * 256, byte(head, 9) + byte(head, 10) * 256
  end

  -- BMP: "BM", little-endian width/height at 18..25.
  if head:sub(1, 2) == "BM" then
    local function le32(offset)
      return byte(head, offset)
        + byte(head, offset + 1) * 0x100
        + byte(head, offset + 2) * 0x10000
        + byte(head, offset + 3) * 0x1000000
    end
    return le32(19), le32(23)
  end

  -- JPEG needs segment walking rather than a fixed offset; deliberately not
  -- done here (the size/type lines still render).
  return nil, nil
end

--- Image preview: metadata lines, plus the path for optional inline drawing.
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@return Mkdn.Hover.Content
function M.image(target, opts)
  local lines = {}
  local w, h = dimensions(target.path)
  if w and h then lines[#lines + 1] = ("%d × %d px"):format(w, h) end
  lines[#lines + 1] = ("%s · %s"):format((target.ext or "image"):upper(), human_size(target.size))

  local provider = require("markdown.util.image_preview").detect()
  if not provider then lines[#lines + 1] = "(no image provider installed)" end

  return {
    lines = lines,
    title = vim.fs.basename(target.path),
    image_path = opts.inline_images ~= false and provider and target.path or nil,
  }
end

--- PDF preview. Asynchronous: rasterizing page 1 shells out to pdftoppm via
--- `pdfport.render_page`, so the metadata float is returned immediately and
--- the rendered page arrives later through `on_image`.
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@param on_image fun(png_path: string|nil, err: string|nil)
---@return Mkdn.Hover.Content
function M.pdf(target, opts, on_image)
  local lines = { ("PDF · %s"):format(human_size(target.size)) }

  local ok_pdfport, pdfport = pcall(require, "pdfport")
  if not ok_pdfport or type(pdfport.render_page) ~= "function" then
    lines[#lines + 1] = "(pdfport.nvim not installed — no page preview)"
    return { lines = lines, title = vim.fs.basename(target.path) }
  end

  if opts.inline_images == false then
    return { lines = lines, title = vim.fs.basename(target.path) }
  end

  local provider = require("markdown.util.image_preview").detect()
  if not provider then
    lines[#lines + 1] = "(no image provider installed)"
    return { lines = lines, title = vim.fs.basename(target.path) }
  end

  lines[#lines + 1] = "rendering page 1…"
  pdfport.render_page(target.path, 1, nil, function(png_path, err) on_image(png_path, err) end)

  return { lines = lines, title = vim.fs.basename(target.path), pending = true }
end

--- Draw `png_path` into an already-open hover window, if a provider can.
--- Returns a teardown function to run when the hover closes, or nil when
--- no provider could draw at all.
---
--- The draw is deferred by one tick (`images.anchor`'s `defer` option), and
--- that is the whole reason this goes through `images.anchor` rather than
--- `images.browse.draw_in_window`: the hover float is opened in the *same*
--- tick this runs in. `nvim_ui_send` puts the image on the terminal at once,
--- but Neovim repaints everything that turned dirty since the last return to
--- its main loop — including the cells of the float that was just created —
--- and paints straight over it. Float there, image gone. `browse
--- .draw_in_window` never needed the defer (its snacks picker window has
--- stood for a while by then), so it draws immediately and is the wrong
--- primitive here.
---
--- Because the draw happens later, whether it succeeded is not known when
--- this returns; the teardown is registered on the strength of the provider
--- being present, and clearing when nothing was drawn is a no-op anyway.
---@param png_path string
---@param win integer
---@return (fun())|nil on_close
function M.draw_into(png_path, win)
  local provider = require("markdown.util.image_preview").detect()
  if provider ~= "images.nvim" then
    -- Only images.nvim can draw into an arbitrary existing window;
    -- snacks/image.nvim need a buffer they own, which a borrowed hover
    -- window is not.
    return nil
  end

  local ok_anchor, anchor = pcall(require, "images.anchor")
  if ok_anchor and type(anchor.draw) == "function" then
    pcall(anchor.draw, win, "full", png_path, { defer = true })
  else
    -- images.nvim without `images.anchor`: fall back to the older public
    -- entry point, undeferred -- worse, but better than no image.
    local ok, browse = pcall(require, "images.browse")
    if not ok or type(browse.draw_in_window) ~= "function" then return nil end
    local drawn = false
    pcall(function() drawn = browse.draw_in_window(png_path, win) end)
    if not drawn then return nil end
  end

  return function()
    pcall(function() require("images.terminal").clear() end)
  end
end

return M
