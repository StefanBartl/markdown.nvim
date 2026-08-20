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
--- JPEG dimensions. Unlike PNG/GIF/BMP there is no fixed offset: the size
--- lives in a start-of-frame segment somewhere behind a variable-length run
--- of metadata (an EXIF thumbnail from a phone camera is routinely tens of
--- kilobytes), so the segment chain has to be walked. `f` must be positioned
--- just after the two-byte SOI.
---@param f file*
---@return integer|nil width
---@return integer|nil height
local function jpeg_dimensions(f)
  for _ = 1, 256 do -- bounded: a malformed file must not spin here
    local marker = f:read(2)
    if not marker or #marker < 2 then return nil, nil end
    local lead, code = marker:byte(1, 2)
    if lead ~= 0xFF then return nil, nil end

    -- 0xFF doubles as segment padding; skip any run of them.
    while code == 0xFF do
      local nxt = f:read(1)
      if not nxt then return nil, nil end
      code = nxt:byte(1)
    end

    -- Standalone markers (TEM, RSTn) carry no length field.
    if not (code == 0x01 or (code >= 0xD0 and code <= 0xD7)) then
      local len_bytes = f:read(2)
      if not len_bytes or #len_bytes < 2 then return nil, nil end
      local len = len_bytes:byte(1) * 256 + len_bytes:byte(2)
      if len < 2 then return nil, nil end

      -- SOF0..SOF15 carry the frame header, except 0xC4/0xC8/0xCC, which are
      -- Huffman/arithmetic tables that happen to sit in the same range.
      local is_sof = code >= 0xC0
        and code <= 0xCF
        and code ~= 0xC4
        and code ~= 0xC8
        and code ~= 0xCC
      if is_sof then
        local body = f:read(5) -- precision, height (2 bytes), width (2 bytes)
        if not body or #body < 5 then return nil, nil end
        return body:byte(4) * 256 + body:byte(5), body:byte(2) * 256 + body:byte(3)
      end

      if not f:seek("cur", len - 2) then return nil, nil end
    end
  end
  return nil, nil
end

---@internal
--- Image dimensions without a decoder: parse just enough header bytes for
--- the common formats. Returns nil for anything else (SVG, WebP, AVIF, …)
--- rather than guessing; `pixel_size` falls back to ImageMagick there.
---@param path string
---@return integer|nil width
---@return integer|nil height
local function dimensions(path)
  local f = io.open(path, "rb")
  if not f then return nil, nil end
  local head = f:read(32) or ""
  if #head < 24 then
    f:close()
    return nil, nil
  end

  local byte = string.byte

  -- PNG: 8-byte signature, then IHDR with big-endian width/height at 16..23.
  if head:sub(1, 8) == "\137PNG\r\n\26\n" then
    f:close()
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
    f:close()
    return byte(head, 7) + byte(head, 8) * 256, byte(head, 9) + byte(head, 10) * 256
  end

  -- BMP: "BM", little-endian width/height at 18..25.
  if head:sub(1, 2) == "BM" then
    f:close()
    local function le32(offset)
      return byte(head, offset)
        + byte(head, offset + 1) * 0x100
        + byte(head, offset + 2) * 0x10000
        + byte(head, offset + 3) * 0x1000000
    end
    return le32(19), le32(23)
  end

  -- JPEG: SOI, then a segment chain.
  if byte(head, 1) == 0xFF and byte(head, 2) == 0xD8 then
    f:seek("set", 2)
    local w, h = jpeg_dimensions(f)
    f:close()
    return w, h
  end

  f:close()
  return nil, nil
end

---@internal
--- Pixel size of an image: header parse first, ImageMagick only as fallback.
--- That order is deliberate. The parse above is a handful of reads and covers
--- the formats a markdown document actually links, while `images.info` shells
--- out — worth it for a WebP or SVG the parser cannot read, not worth it for
--- every PNG.
---@param path string
---@return Images.Scale.Dims|nil
local function pixel_size(path)
  local w, h = dimensions(path)
  if w and h and w > 0 and h > 0 then return { width = w, height = h } end

  local ok, info = pcall(require, "images.info")
  if ok and type(info.collect) == "function" then
    local px = info.collect(path)
    if px and px.width and px.height and px.width > 0 and px.height > 0 then
      return { width = px.width, height = px.height }
    end
  end
  return nil
end

---@internal
--- Fit `image_px` into the hover's maximum box, in cells. Prefers
--- `images.scale.fit_cells` — the same function `images.zen` and
--- `images.redact` size their windows with, so a hover, a zen window and a
--- redaction box all letterbox identically. The local fallback covers an
--- images.nvim too old to have it.
---@param image_px Images.Scale.Dims|nil
---@param opts Mkdn.Hover.PreviewOpts
---@return integer cols
---@return integer rows
local function canvas_cells(image_px, opts)
  local max_cols = math.max(10, math.min(opts.max_width or 80, math.max(10, vim.o.columns - 4)))
  local max_rows = math.max(3, math.min(opts.max_lines or 20, math.max(3, vim.o.lines - 4)))

  local ok, scale = pcall(require, "images.scale")
  if ok and type(scale.fit_cells) == "function" then
    return scale.fit_cells(max_cols, max_rows, image_px)
  end

  if not image_px then return max_cols, max_rows end
  -- A terminal cell is roughly twice as tall as it is wide — the same 0.5
  -- assumption images.scale documents.
  local aspect = image_px.width / image_px.height
  local cols = math.floor(max_rows * aspect / 0.5)
  if cols <= max_cols then return math.max(1, cols), max_rows end
  return max_cols, math.max(1, math.floor(max_cols * 0.5 / aspect))
end

--- Image preview.
---
--- Two shapes, depending on whether the picture can actually be drawn:
---
--- * **Drawable** — a blank float sized to the image's aspect ratio, and
---   nothing else. No filename in the border, no dimension or size line: the
---   reader is looking at the picture, and a caption for it is noise. The
---   sizing is not only cosmetic — the drawing box handed to the terminal
---   *is* the float's geometry, so a float measured against two lines of text
---   squeezes the image into a box two cells tall.
--- * **Not drawable** (no provider, or `inline_images = false`) — the
---   metadata lines, which are then the only thing the hover can say at all.
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@return Mkdn.Hover.Content
function M.image(target, opts)
  local provider = require("markdown.util.image_preview").detect()

  if provider and opts.inline_images ~= false then
    local cols, rows = canvas_cells(pixel_size(target.path), opts)
    return { lines = {}, canvas = { cols = cols, rows = rows }, image_path = target.path }
  end

  local lines = {}
  local w, h = dimensions(target.path)
  if w and h then lines[#lines + 1] = ("%d × %d px"):format(w, h) end
  lines[#lines + 1] = ("%s · %s"):format((target.ext or "image"):upper(), human_size(target.size))
  if not provider then lines[#lines + 1] = "(no image provider installed)" end

  return { lines = lines, title = vim.fs.basename(target.path) }
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
