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
  ordered = { enabled = true }, -- the number of `1.` / `1)` list items gets its own colour
  checkboxes = { enabled = true, unchecked = "☐", checked = "☑", partial = "◐" },
  code = { enabled = true, background = true, label = true },
  rules = { enabled = true, char = "─" },
  quotes = { enabled = true, icon = "▎", callouts = true },
  inline = {
    enabled = true,
    code = true,
    links = true,
    images = true,
    bold = true,
    italic = true,
    strike = true,
    comments = true,
  },
}

---How deep links inside the text of links are drawn (`[![badge](img)](url)` is two). Deeper nesting is pathological,
---and each level scans the rest of the line again.
M.MAX_LINK_DEPTH = 8

---The most runs of `*`, `_` and `~` one line is searched for emphasis (every run looks for its closer, so the work grows
---with the square of the runs).
M.MAX_EMPHASIS_RUNS = 256

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
    MarkdownRenderBold = "@markup.strong",
    MarkdownRenderItalic = "@markup.italic",
    MarkdownRenderStrike = "@markup.strikethrough",
    MarkdownRenderOrdered = "@markup.list.numbered",
    MarkdownRenderComment = "Comment",
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
  api.nvim_set_hl(0, "MarkdownRenderBoldItalic", { bold = true, italic = true, default = true })
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
---@field grid? boolean  # false: no table grid draws the table rows, so they get the inline marks (default true)
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
---The next `[text](url)` / `![alt](url)` at or after `pos`: balanced parentheses in the url, a
---`![img](src)` allowed inside the text of a link (a badge), a backslash-escaped `[` is skipped.
---@param line string
---@param pos integer
---@return integer|nil s, integer|nil e, string|nil bang, string|nil text
function M._link_at(line, pos)
  local init = pos
  while true do
    local s = line:find("[", init, true)
    if not s then return nil end
    local bang = ""
    local open = s
    if s > 1 and line:sub(s - 1, s - 1) == "!" then
      bang = "!"
      open = s - 1
    end
    local bs = 0
    local k = open - 1
    while k >= 1 and line:sub(k, k) == "\\" do
      bs = bs + 1
      k = k - 1
    end
    -- an escaped "!" is a literal "!" in front of a plain link
    if bang == "!" and bs % 2 == 1 then
      bang, open, bs = "", s, 0
    end
    if open < pos or bs % 2 == 1 then
      init = s + 1
    else
      -- the text: up to the "]" that closes this "[" (nested brackets of an image count)
      local depth, j = 0, s
      local close
      while j <= #line do
        local ch = line:sub(j, j)
        if ch == "\\" then
          j = j + 1
        elseif ch == "[" then
          depth = depth + 1
        elseif ch == "]" then
          depth = depth - 1
          if depth == 0 then
            close = j
            break
          end
        end
        j = j + 1
      end
      if close and line:sub(close + 1, close + 1) == "(" then
        local d, m = 0, close + 1
        local stop
        while m <= #line do
          local ch = line:sub(m, m)
          if ch == "(" then
            d = d + 1
          elseif ch == ")" then
            d = d - 1
            if d == 0 then
              stop = m
              break
            end
          end
          m = m + 1
        end
        if stop then return open, stop, bang, line:sub(s + 1, close - 1) end
      end
      init = s + 1
    end
  end
end

---@internal
---Whether `line` can be the text a `---` underlines (setext): plain paragraph text, not a
---heading, list item, quote, fence, table row or another rule.
---@param line string|nil
---@return boolean
function M._is_paragraph_line(line)
  if not line or not line:match("%S") then return false end
  return not (
    line:match("^%s*#+%s")
    or line:match("^%s*[-*+]%s")
    or line:match("^%s*%d+[.)]%s")
    or line:match("^%s*>")
    or line:match("^%s*```")
    or line:match("^%s*~~~")
    or line:match("^%s*|")
    or line:match("^%s*[-*_][-*_%s]*$")
  )
end

---@internal
---Emphasis of `line` from byte `from` on: `**bold**`, `__bold__`, `*italic*`, `_italic_`, `***both***` and `~~strike~~`.
---The markers are hidden and the text between them is highlighted. A run of markers opens when a non-space follows it and
---closes when a non-space precedes it; `_` never opens or closes inside a word (`snake_case_name`). A run closes the nearest
---later run of the same character and length, so `**bold *it* x**` nests; a backslash escapes a run. `skip(p)` says that
---byte `p` belongs to something else (a code span, the address of a link).
---@param out Mkdn.RenderMark[]
---@param line string
---@param from integer  # 1-based
---@param c table  # cfg.inline
---@param skip fun(p: integer): boolean
function M._emphasis(out, line, from, c, skip)
  local backslash = string.char(92)
  local runs = {}
  local i, n = from, #line
  while i <= n do
    local ch = line:sub(i, i)
    if
      (ch == "*" or ch == "_" or ch == "~")
      and not skip(i)
      and line:sub(i - 1, i - 1) ~= backslash
    then
      local j = i
      while line:sub(j + 1, j + 1) == ch do
        j = j + 1
      end
      runs[#runs + 1] = { s = i, e = j, ch = ch, len = j - i + 1 }
      i = j + 1
    else
      i = i + 1
    end
  end

  ---a character that makes `_` part of a word (a letter, a digit, any multibyte character)
  local function word(ch) return ch ~= "" and (ch:match("%w") ~= nil or ch:byte() >= 128) end
  local function space(ch) return ch == "" or ch:match("%s") ~= nil end
  local function can_open(r)
    local before, after = line:sub(r.s - 1, r.s - 1), line:sub(r.e + 1, r.e + 1)
    if space(after) then return false end
    return not (r.ch == "_" and word(before))
  end
  local function can_close(r)
    local before, after = line:sub(r.s - 1, r.s - 1), line:sub(r.e + 1, r.e + 1)
    if space(before) then return false end
    return not (r.ch == "_" and word(after))
  end
  ---the highlight group of a pair of runs of this character and length, or nil when that kind is switched off
  local function group_of(ch, len)
    if ch == "~" then return len == 2 and c.strike ~= false and "MarkdownRenderStrike" or nil end
    if len == 1 then return c.italic ~= false and "MarkdownRenderItalic" or nil end
    if len == 2 then return c.bold ~= false and "MarkdownRenderBold" or nil end
    if len == 3 then
      return (c.bold ~= false and c.italic ~= false) and "MarkdownRenderBoldItalic" or nil
    end
  end

  if #runs > M.MAX_EMPHASIS_RUNS then return end
  local used = {}
  for a = 1, #runs do
    local open = runs[a]
    local group = not used[a] and can_open(open) and group_of(open.ch, open.len) or nil
    if group then
      for b = a + 1, #runs do
        local close = runs[b]
        if not used[b] and close.ch == open.ch and close.len == open.len and can_close(close) then
          used[a], used[b] = true, true
          conceal(out, open.s - 1, open.e, "")
          conceal(out, close.s - 1, close.e, "")
          out[#out + 1] = { col = open.e, opts = { end_col = close.s - 1, hl_group = group } }
          break
        end
      end
    end
  end
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
      -- the closing run has exactly the length of the opening one (CommonMark)
      local cs, ce
      local q = e + 1
      while true do
        local rs, re = line:find("`+", q)
        if not rs then break end
        if re - rs == e - s then
          cs, ce = rs, re
          break
        end
        q = re + 1
      end
      if not cs then
        pos = e + 1 -- an unpaired run: look for the next one
      else
        conceal(out, s - 1, e, "")
        conceal(out, cs - 1, ce, "")
        out[#out + 1] = { col = e, opts = { end_col = cs - 1, hl_group = "MarkdownRenderCode" } }
        spans[#spans + 1] = { s, ce }
        pos = ce + 1
      end
    end
  end
  local function inside(p)
    for _, sp in ipairs(spans) do
      if p >= sp[1] and p <= sp[2] then return true end
    end
    return false
  end
  if c.comments ~= false then
    -- `<!-- a comment -->` on one line is dimmed, and nothing inside it is links or emphasis
    local pos = from
    while true do
      local s = line:find("<!--", pos, true)
      if not s then break end
      if inside(s) then
        pos = s + 4
      else
        local _, e = line:find("-->", s + 4, true)
        if not e then break end
        out[#out + 1] = { col = s - 1, opts = { end_col = e, hl_group = "MarkdownRenderComment" } }
        spans[#spans + 1] = { s, e }
        pos = e + 1
      end
    end
  end
  if c.links or c.images then
    -- `limit`: only links that end at or before it (the text of an enclosing link, a badge)
    local function scan_links(pos, limit, depth)
      -- a badge is two deep; a line that nests links further is not prose, and every level rescans the line
      if depth > M.MAX_LINK_DEPTH then return end
      while true do
        local s, e, bang, text = M._link_at(line, pos)
        if not s or (limit and e > limit) then break end
        if not inside(s) then
          local is_img = bang == "!"
          local open_len = is_img and 2 or 1
          local text_end = s - 1 + open_len + #text
          if (is_img and c.images) or (not is_img and c.links) then
            -- "[" / "![" before the text, "](url)" after it
            conceal(out, s - 1, s - 1 + open_len, is_img and "▣" or "")
            out[#out + 1] = {
              col = s - 1 + open_len,
              opts = {
                end_col = text_end,
                hl_group = is_img and "MarkdownRenderImage" or "MarkdownRenderLink",
              },
            }
            conceal(out, text_end, e, "")
            -- the `](url)` part is nobody's emphasis (`__init__` in an address)
            spans[#spans + 1] = { text_end + 1, e }
          end
          -- a link inside the text of this one: `[![alt](img)](url)`
          if text:find("[", 1, true) then scan_links(s + open_len, text_end, depth + 1) end
        end
        pos = e + 1
      end
    end
    scan_links(from, nil, 1)
  end
  if c.bold or c.italic or c.strike then M._emphasis(out, line, from, c, inside) end
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

  -- a table row is drawn by core.table_render / table_truncate: its columns must not shift
  if ctx.grid ~= false and line:match("^%s*|") then return out end

  local rule_ch = line:gsub("%s", "")
  if
    c.rules.enabled
    and #rule_ch >= 3
    and ("-*_"):find(rule_ch:sub(1, 1), 1, true)
    and rule_ch == rule_ch:sub(1, 1):rep(#rule_ch)
    -- only a run of dashes without spaces can underline a paragraph (setext); `- - -` is a rule
    and not (line:match("^%s*%-+%s*$") and M._is_paragraph_line(ctx.prev))
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
    -- `1. item` / `1) item`: the number is coloured; a checkbox after it is drawn like one after a bullet
    local oind, number, punct = line:match("^(%s*)(%d+)([.)])%s")
    if oind and number and punct and not marker and c.ordered.enabled then
      local marker_end = #oind + #number + 1
      out[#out + 1] =
        { col = #oind, opts = { end_col = marker_end, hl_group = "MarkdownRenderOrdered" } }
      text_from = marker_end + 2
      local cb, ce = line:find("^%[[ xX%-]%]%s", marker_end + 2)
      if cb and c.checkboxes.enabled then
        local state = line:sub(cb + 1, cb + 1)
        local icon = (state == " " and c.checkboxes.unchecked)
          or (state == "-" and c.checkboxes.partial)
          or c.checkboxes.checked
        conceal(out, cb - 1, cb + 2, icon)
        text_from = ce + 1
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
---Whether a table display (grid or truncation) owns the table rows of this buffer.
---@param bufnr integer
---@return boolean
local function grid_active(bufnr)
  for _, mod in ipairs({ "markdown.core.table_render", "markdown.core.table_truncate" }) do
    local m = package.loaded[mod]
    if m and m.is_enabled(bufnr) then return true end
  end
  return false
end

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
---@param grid boolean
local function draw_row(bufnr, st, row, line, prev, width, c, grid)
  local ids = {}
  local marks = M.line_marks(line, {
    role = st.roles[row],
    lang = st.langs[row],
    prev = prev,
    width = width,
    cfg = c,
    grid = grid,
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
  local grid = grid_active(bufnr)
  local look = ("%d:%s:%s"):format(width, tostring(grid), vim.inspect(c))
  if force or st.tick ~= tick or st.look ~= look then
    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    st.drawn = {}
    st.roles, st.langs = M.roles(api.nvim_buf_get_lines(bufnr, 0, -1, false))
    st.tick, st.look = tick, look
  end
  local count = api.nvim_buf_line_count(bufnr)
  local was = st.cursor
  st.cursor = cursor_rows(bufnr)
  -- a row that was a cursor row and is not any more (its window closed or left the buffer)
  -- is drawn again
  for r in pairs(was) do
    if not st.cursor[r] then clear_row(bufnr, st, r) end
  end
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
          if line then draw_row(bufnr, st, row, line, prev, width, c, grid) end
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
      if line then draw_row(bufnr, st, r, line, prev, width, c, grid_active(bufnr)) end
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
  -- WinClosed: a floating window closed from outside does not change the layout, so nothing else
  -- tells us that its cursor row is a normal row again
  api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized", "WinClosed" }, {
    group = global_group,
    callback = function()
      for bufnr in pairs(S) do
        schedule(bufnr)
      end
    end,
    desc = "[markdown.nvim] render: draw what scrolled into view, re-fit rules, redraw after a window closed",
  })
  api.nvim_create_autocmd("OptionSet", {
    group = global_group,
    pattern = { "number", "relativenumber", "signcolumn", "foldcolumn", "numberwidth" },
    callback = function()
      for bufnr in pairs(S) do
        schedule(bufnr)
      end
    end,
    desc = "[markdown.nvim] render: re-fit rules after a change of the text area width",
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = global_group,
    callback = setup_highlights,
    desc = "[markdown.nvim] render: re-link the highlight groups",
  })
end

---The table grid (or truncation) of `bufnr` was switched on or off: its rows change owner.
---@param bufnr integer
function M.grid_changed(bufnr)
  if S[bufnr] then schedule(bufnr) end
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
