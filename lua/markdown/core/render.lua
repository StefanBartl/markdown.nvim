---@module 'markdown.core.render'
---@brief Native in-buffer rendering of Markdown (display only, replaces render-markdown.nvim).
---@description
--- Extmarks only, the text is never touched, and the row under the cursor shows its raw text.
--- Constructs: headings (icon + background), bullets, checkboxes, code blocks (background +
--- language label), thematic breaks, block quotes and callouts, inline code / links / images
--- (the markup is concealed). Tables are drawn by `core.table_render`.
---
--- Only the rows in and around the windows are drawn (`margin`), debounced after edits and on
--- scrolling, so a large file costs the same as a small one.
---
---   M.line_marks(line, i, ctx) – pure: the extmarks of one line
---   M.roles(lines)             – pure: per line "open" | "in" | "close" (fenced code) / "front"
---   M.enable/disable/toggle(bufnr), M.refresh(bufnr)

local fences = require("markdown.util.fence")

local M = {}

local api = vim.api
local NS = api.nvim_create_namespace("markdown_render")

M.DEFAULTS = {
  enabled = false, -- true: on for every markdown buffer
  margin = 40, -- rows drawn above and below the visible ones
  debounce_ms = 60,
  headings = {
    enabled = true,
    icons = { "◉ ", "○ ", "✸ ", "✿ ", "◆ ", "◇ " },
    background = true,
  },
  bullets = { enabled = true, icons = { "•", "◦", "▪" } },
  checkboxes = { enabled = true, unchecked = "☐", checked = "☑", partial = "◐" },
  code = { enabled = true, background = true, label = true },
  rules = { enabled = true, char = "─" },
  quotes = { enabled = true, icon = "▎", callouts = true },
  inline = { enabled = true, code = true, links = true, images = true },
}

local CALLOUTS = {
  NOTE = { "ⓘ Note", "MarkdownRenderInfo" },
  TIP = { "✦ Tip", "MarkdownRenderOk" },
  IMPORTANT = { "‼ Important", "MarkdownRenderHint" },
  WARNING = { "▲ Warning", "MarkdownRenderWarn" },
  CAUTION = { "✖ Caution", "MarkdownRenderError" },
}

---@internal
local function setup_highlights()
  local links = {
    MarkdownRenderH1Bg = "DiffAdd",
    MarkdownRenderH2Bg = "DiffChange",
    MarkdownRenderH3Bg = "DiffText",
    MarkdownRenderH4Bg = "DiffDelete",
    MarkdownRenderH5Bg = "DiffAdd",
    MarkdownRenderH6Bg = "DiffChange",
    MarkdownRenderH1 = "Title",
    MarkdownRenderH2 = "Title",
    MarkdownRenderH3 = "Title",
    MarkdownRenderH4 = "Title",
    MarkdownRenderH5 = "Title",
    MarkdownRenderH6 = "Title",
    MarkdownRenderCodeBg = "ColorColumn",
    MarkdownRenderCodeLabel = "Comment",
    MarkdownRenderCode = "@markup.raw.markdown_inline",
    MarkdownRenderLink = "@markup.link.label",
    MarkdownRenderImage = "@markup.link",
    MarkdownRenderRule = "Comment",
    MarkdownRenderQuote = "Comment",
    MarkdownRenderInfo = "DiagnosticInfo",
    MarkdownRenderOk = "DiagnosticOk",
    MarkdownRenderHint = "DiagnosticHint",
    MarkdownRenderWarn = "DiagnosticWarn",
    MarkdownRenderError = "DiagnosticError",
  }
  for name, target in pairs(links) do
    api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

---@internal
---@return table
local function cfg()
  local ok, config = pcall(require, "markdown.config")
  local t = (ok and config.get().render) or {}
  return vim.tbl_deep_extend("force", M.DEFAULTS, t)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure part
-- ─────────────────────────────────────────────────────────────────────────────

---Role of every line: "front" (front matter), "open" / "in" / "close" (fenced code).
---@param lines string[]
---@return table<integer, string> roles
---@return table<integer, string> langs  # info string of the opening fence lines
function M.roles(lines)
  local roles, langs = {}, {}
  local start = 1
  if lines[1] and lines[1]:match("^%-%-%-%s*$") then
    for i = 2, #lines do
      if lines[i]:match("^%-%-%-%s*$") or lines[i]:match("^%.%.%.%s*$") then
        for k = 1, i do
          roles[k] = "front"
        end
        start = i + 1
        break
      end
    end
  end
  local c, n
  for i = start, #lines do
    local line = lines[i]
    if not c then
      c, n = fences.open(line)
      if c then
        roles[i] = "open"
        langs[i] = vim.trim(line:gsub("^%s*[`~]+", ""))
      end
    else
      if fences.close(line, c, n) then
        roles[i] = "close"
        c, n = nil, nil
      else
        roles[i] = "in"
      end
    end
  end
  return roles, langs
end

---@class Mkdn.RenderMark
---@field col integer  # 0-based start byte
---@field opts table  # nvim_buf_set_extmark options

---@class Mkdn.RenderCtx
---@field role? string  # "open" | "in" | "close" | "front"
---@field lang? string
---@field prev? string  # the line above (setext headings are no thematic break)
---@field width integer  # columns a thematic break fills
---@field cfg table

---@internal
---@param out Mkdn.RenderMark[]
---@param col integer
---@param end_col integer
---@param conceal_text string
---@param extra? table
local function conceal(out, col, end_col, conceal_text, extra)
  local o = { end_col = end_col, conceal = conceal_text }
  if extra then o = vim.tbl_extend("force", o, extra) end
  out[#out + 1] = { col = col, opts = o }
end

---@internal
---Inline markup of `line` from byte `from` on (code spans first, so nothing inside them is touched).
---@param out Mkdn.RenderMark[]
---@param line string
---@param from integer  # 1-based
---@param c table  # cfg.inline
local function inline(out, line, from, c)
  local spans = {}
  if c.code then
    local pos = from
    while true do
      local s, e = line:find("`+", pos)
      if not s then break end
      local ticks = line:sub(s, e)
      local cs, ce = line:find(ticks, e + 1, true)
      if not cs then break end
      conceal(out, s - 1, e, "")
      conceal(out, cs - 1, ce, "")
      out[#out + 1] = { col = e, opts = { end_col = cs - 1, hl_group = "MarkdownRenderCode" } }
      spans[#spans + 1] = { s, ce }
      pos = ce + 1
    end
  end
  local function inside(p)
    for _, sp in ipairs(spans) do
      if p >= sp[1] and p <= sp[2] then return true end
    end
    return false
  end
  if c.links or c.images then
    local pos = from
    while true do
      local s, e, bang, text = line:find("(!?)%[([^%]]*)%]%(([^)]*)%)", pos)
      if not s then break end
      if not inside(s) then
        local is_img = bang == "!"
        if (is_img and c.images) or (not is_img and c.links) then
          local open_len = is_img and 2 or 1
          -- "[" / "![" before the text, "](url)" after it
          conceal(out, s - 1, s - 1 + open_len, is_img and "▣" or "")
          local text_end = s - 1 + open_len + #text
          out[#out + 1] = {
            col = s - 1 + open_len,
            opts = {
              end_col = text_end,
              hl_group = is_img and "MarkdownRenderImage" or "MarkdownRenderLink",
            },
          }
          conceal(out, text_end, e, "")
        end
      end
      pos = e + 1
    end
  end
end

---The extmarks of one line (pure).
---@param line string
---@param ctx Mkdn.RenderCtx
---@return Mkdn.RenderMark[]
function M.line_marks(line, ctx)
  local out = {}
  local c = ctx.cfg
  local role = ctx.role

  if role == "front" then return out end
  if role then
    if c.code.enabled then
      if c.code.background then
        out[#out + 1] = { col = 0, opts = { line_hl_group = "MarkdownRenderCodeBg" } }
      end
      if role == "open" and c.code.label and ctx.lang and ctx.lang ~= "" then
        out[#out + 1] = {
          col = 0,
          opts = {
            virt_text = { { ctx.lang, "MarkdownRenderCodeLabel" } },
            virt_text_pos = "right_align",
          },
        }
      end
    end
    return out
  end

  -- a table row is drawn by core.table_render: its columns must not shift
  if line:match("^%s*|") then return out end

  local rule_ch = line:gsub("%s", "")
  if
    c.rules.enabled
    and #rule_ch >= 3
    and ("-*_"):find(rule_ch:sub(1, 1), 1, true)
    and rule_ch == rule_ch:sub(1, 1):rep(#rule_ch)
    and not (rule_ch:sub(1, 1) == "-" and ctx.prev and ctx.prev:match("%S"))
  then
    out[#out + 1] = {
      col = 0,
      opts = {
        virt_text = { { (c.rules.char):rep(ctx.width), "MarkdownRenderRule" } },
        virt_text_pos = "overlay",
      },
    }
    return out
  end

  local text_from = 1

  local hashes = line:match("^(#+)%s")
  if hashes and #hashes <= 6 and c.headings.enabled then
    local lvl = #hashes
    local icon = c.headings.icons[lvl] or ""
    out[#out + 1] = {
      col = 0,
      opts = {
        end_col = lvl + 1,
        conceal = "",
        virt_text = { { icon, "MarkdownRenderH" .. lvl } },
        virt_text_pos = "inline",
      },
    }
    if c.headings.background then
      out[#out + 1] = { col = 0, opts = { line_hl_group = "MarkdownRenderH" .. lvl .. "Bg" } }
    end
    text_from = lvl + 2
  end

  if c.quotes.enabled and not hashes then
    local prefix = line:match("^%s*>[%s>]*")
    if prefix then
      for p = 1, #prefix do
        if prefix:sub(p, p) == ">" then
          conceal(out, p - 1, p, c.quotes.icon, { hl_group = "MarkdownRenderQuote" })
        end
      end
      text_from = #prefix + 1
      if c.quotes.callouts then
        local s, e, kind = line:find("^%[!(%a+)%]", text_from)
        local def = kind and CALLOUTS[kind:upper()]
        if def then
          out[#out + 1] = {
            col = s - 1,
            opts = {
              end_col = e,
              conceal = "",
              virt_text = { { def[1], def[2] } },
              virt_text_pos = "inline",
            },
          }
          text_from = e + 1
        end
      end
    end
  end

  if not hashes and not line:match("^%s*>") then
    local ind, marker = line:match("^(%s*)([-*+])%s")
    if marker and c.bullets.enabled then
      local cb, ce = line:find("^%[[ xX%-]%]%s", #ind + 3)
      if cb and c.checkboxes.enabled then
        local state = line:sub(cb + 1, cb + 1)
        local icon = (state == " " and c.checkboxes.unchecked)
          or (state == "-" and c.checkboxes.partial)
          or c.checkboxes.checked
        conceal(out, #ind, #ind + 1, "")
        conceal(out, cb - 1, cb + 2, icon)
        text_from = ce + 1
      else
        local level = math.floor(#ind / 2) % #c.bullets.icons + 1
        conceal(out, #ind, #ind + 1, c.bullets.icons[level])
        text_from = #ind + 2
      end
    end
  end

  if c.inline.enabled then inline(out, line, text_from, c.inline) end
  return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Buffer part
-- ─────────────────────────────────────────────────────────────────────────────

---@class Mkdn.RenderState
---@field group integer
---@field pending boolean
---@field tick integer  # changedtick the drawing is for
---@field drawn table<integer, integer[]>  # 1-based row -> its extmark ids ({} = deliberately blank)
---@field cursor table<integer, boolean>
---@field roles table<integer, string>
---@field langs table<integer, string>
---@field look string

---@type table<integer, Mkdn.RenderState>
local S = {}

---@internal
---@param bufnr integer
---@return table<integer, boolean>
local function cursor_rows(bufnr)
  local set = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    set[api.nvim_win_get_cursor(win)[1]] = true
  end
  return set
end

---@internal
---The narrowest window width and the row spans the windows show (overlapping ones merged), so two
---windows far apart do not drag every row in between into the drawing.
---@param bufnr integer
---@param margin integer
---@return integer|nil width, integer[][] spans  # { { first, last }, ... } 1-based, ascending
local function window_span(bufnr, margin)
  local width, spans = nil, {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local info = vim.fn.getwininfo(win)[1]
    local w = info.width - info.textoff
    width = width and math.min(width, w) or w
    spans[#spans + 1] = { math.max(1, info.topline - margin), info.botline + margin }
  end
  if not width then return nil, {} end
  table.sort(spans, function(x, y) return x[1] < y[1] end)
  local merged = {}
  for _, sp in ipairs(spans) do
    local lastm = merged[#merged]
    if lastm and sp[1] <= lastm[2] + 1 then
      lastm[2] = math.max(lastm[2], sp[2])
    else
      merged[#merged + 1] = { sp[1], sp[2] }
    end
  end
  return width, merged
end

---@internal
---@param bufnr integer
---@param st Mkdn.RenderState
---@param row integer  # 1-based
local function clear_row(bufnr, st, row)
  for _, id in ipairs(st.drawn[row] or {}) do
    pcall(api.nvim_buf_del_extmark, bufnr, NS, id)
  end
  st.drawn[row] = nil
end

---@internal
---@param bufnr integer
---@param st Mkdn.RenderState
---@param row integer
---@param line string
---@param prev string|nil
---@param width integer
---@param c table
local function draw_row(bufnr, st, row, line, prev, width, c)
  local ids = {}
  local marks = M.line_marks(line, {
    role = st.roles[row],
    lang = st.langs[row],
    prev = prev,
    width = width,
    cfg = c,
  })
  for _, m in ipairs(marks) do
    local ok, id = pcall(api.nvim_buf_set_extmark, bufnr, NS, row - 1, m.col, m.opts)
    if ok then ids[#ids + 1] = id end
  end
  st.drawn[row] = ids
end

---Draw the rows in and around the windows that are not drawn yet.
---@param bufnr integer
---@param force? boolean  # redraw everything in range
function M.refresh(bufnr, force)
  local st = S[bufnr]
  if not st or not api.nvim_buf_is_valid(bufnr) then return end
  local c = cfg()
  local width, spans = window_span(bufnr, c.margin)
  if not width then return end -- not shown: BufWinEnter draws it
  local tick = api.nvim_buf_get_changedtick(bufnr)
  local look = ("%d:%s"):format(width, vim.inspect(c))
  if force or st.tick ~= tick or st.look ~= look then
    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    st.drawn = {}
    st.roles, st.langs = M.roles(api.nvim_buf_get_lines(bufnr, 0, -1, false))
    st.tick, st.look = tick, look
  end
  local count = api.nvim_buf_line_count(bufnr)
  st.cursor = cursor_rows(bufnr)
  for _, sp in ipairs(spans) do
    local first, last = sp[1], math.min(sp[2], count)
    local lo = math.max(first - 1, 1) -- one row above the range: the "previous line" of its first row
    local seg = api.nvim_buf_get_lines(bufnr, lo - 1, last, false)
    for row = first, last do
      if not st.drawn[row] then
        if st.cursor[row] then
          st.drawn[row] = {}
        else
          local line = seg[row - lo + 1]
          local prev = seg[row - lo]
          if line then draw_row(bufnr, st, row, line, prev, width, c) end
        end
      end
    end
  end
end

---@internal
---The cursor moved: the row it left is drawn, the row it entered shows its text.
---@param bufnr integer
local function on_cursor(bufnr)
  local st = S[bufnr]
  if not st then return end
  local now, old = cursor_rows(bufnr), st.cursor or {}
  local same = true
  for r in pairs(now) do
    if not old[r] then same = false end
  end
  for r in pairs(old) do
    if not now[r] then same = false end
  end
  if same then return end
  if st.tick ~= api.nvim_buf_get_changedtick(bufnr) then
    st.cursor = now
    return -- the text debounce redraws
  end
  local c = cfg()
  local width = window_span(bufnr, c.margin)
  if not width then return end
  for r in pairs(now) do
    clear_row(bufnr, st, r)
    st.drawn[r] = {}
  end
  for r in pairs(old) do
    if not now[r] then
      clear_row(bufnr, st, r)
      local line = api.nvim_buf_get_lines(bufnr, r - 1, r, false)[1]
      local prev = r > 1 and api.nvim_buf_get_lines(bufnr, r - 2, r - 1, false)[1] or nil
      if line then draw_row(bufnr, st, r, line, prev, width, c) end
    end
  end
  st.cursor = now
end

---@internal
---@param bufnr integer
local function schedule(bufnr)
  local st = S[bufnr]
  if not st or st.pending then return end
  st.pending = true
  vim.defer_fn(function()
    if S[bufnr] then
      S[bufnr].pending = false
      M.refresh(bufnr)
    end
  end, cfg().debounce_ms)
end

local global_group

---@internal
local function ensure_global()
  if global_group then return end
  global_group = api.nvim_create_augroup("MarkdownNvimRender", { clear = true })
  api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized" }, {
    group = global_group,
    callback = function()
      for bufnr in pairs(S) do
        schedule(bufnr)
      end
    end,
    desc = "[markdown.nvim] render: draw what scrolled into view, re-fit rules after a resize",
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = global_group,
    callback = setup_highlights,
    desc = "[markdown.nvim] render: re-link the highlight groups",
  })
end

---@param bufnr? integer
---@return boolean
function M.is_enabled(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  return S[bufnr] ~= nil
end

---@param bufnr? integer
function M.enable(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if S[bufnr] then return end
  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.notify("markdown.nvim: render needs Neovim >= 0.10", vim.log.levels.WARN)
    return
  end
  ensure_global()
  setup_highlights()
  local group = api.nvim_create_augroup("MarkdownNvimRenderBuf" .. bufnr, { clear = true })
  S[bufnr] = {
    group = group,
    pending = false,
    tick = -1,
    drawn = {},
    cursor = {},
    roles = {},
    langs = {},
    look = "",
  }
  local guard = require("markdown.core.conceal_guard")
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = bufnr,
    callback = function() schedule(bufnr) end,
    desc = "[markdown.nvim] render: redraw after an edit",
  })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function() on_cursor(bufnr) end,
    desc = "[markdown.nvim] render: the cursor row shows its text",
  })
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      guard.apply("render_native", bufnr)
      schedule(bufnr)
    end,
    desc = "[markdown.nvim] render: conceallevel for a new window",
  })
  api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      vim.schedule(function()
        if S[bufnr] and api.nvim_buf_is_valid(bufnr) then guard.apply("render_native", bufnr) end
      end)
    end,
    desc = "[markdown.nvim] render: give a window that left its conceallevel back",
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      S[bufnr] = nil
      pcall(api.nvim_del_augroup_by_id, group)
    end,
  })
  guard.apply("render_native", bufnr)
  M.refresh(bufnr, true)
end

---@param bufnr? integer
function M.disable(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  local st = S[bufnr]
  if not st then return end
  pcall(api.nvim_del_augroup_by_id, st.group)
  S[bufnr] = nil
  if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_clear_namespace(bufnr, NS, 0, -1) end
  require("markdown.core.conceal_guard").restore("render_native", bufnr)
end

---@param bufnr? integer
---@return boolean now_enabled
function M.toggle(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
    return false
  end
  M.enable(bufnr)
  return true
end

return M
