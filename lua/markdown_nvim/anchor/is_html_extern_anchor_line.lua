---@module 'markdown_nvim.anchor.is_html_extern_anchor_line'
local api = vim.api

local function trim(s)
  if not s then return nil end
  return s:match("^%s*(.-)%s*$")
end

local function looks_like_file_uri(uri)
  if not uri or uri == "" then return false end
  uri = trim(uri)
  if not uri then return nil end
  if uri:match("^#") then return false end
  -- Windows drive-letter absolute path (`C:/…`, `C:\…`), not a URI scheme.
  if uri:match("^%a:[/\\]") then return true end
  if uri:match("^%w[%w+.-]*:") then return false end
  if uri:match("[/\\]") then return true end
  if uri:match("%.[%w%d]+%s*$") then return true end
  if uri:match("%.%w+[#]") or uri:match("%.%w+$") then return true end
  return false
end

local function extract_md_paren_target(line)
  if not line then return nil end
  local inner = line:match("%b()")
  if not inner then return nil end
  inner = inner:sub(2, -2)
  inner = trim(inner)
  if inner == "" then return nil end
  return inner
end

local function extract_html_attr(line)
  if not line then return nil end
  local href = line:match('<a[^>]-href%s*=%s*"(.-)"') or line:match("<a[^>]-href%s*=%s*'(.-)'")
  if href and href ~= "" then return href end
  href = line:match('<img[^>]-src%s*=%s*"(.-)"') or line:match("<img[^>]-src%s*=%s*'(.-)'")
  if href and href ~= "" then return href end
  href = line:match("<a[^>]-href%s*=%s*([^%s>]+)") or line:match("<img[^>]-src%s*=%s*([^%s>]+)")
  if href and href ~= "" then return href end
  return nil
end

local function find_attr_near_cursor(radius)
  radius = radius or 8
  local ok, bufnr = pcall(api.nvim_get_current_buf)
  if not ok or not bufnr then return nil end
  local ok2, cur = pcall(api.nvim_win_get_cursor, 0)
  local curline = (ok2 and cur and cur[1]) or 1
  local start_line = math.max(1, curline - radius)
  local end_line = math.min(api.nvim_buf_line_count(bufnr), curline + radius)
  local ok3, lines = pcall(api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if not ok3 or not lines then return nil end
  local joined = table.concat(lines, " ")
  local v = joined:match('href%s*=%s*"(.-)"')
    or joined:match("href%s*=%s*'(.-)'")
    or joined:match('src%s*=%s*"(.-)"')
    or joined:match("src%s*=%s*'(.-)'")
  if v and v ~= "" then return trim(v) end
  return nil
end

local function split_target_and_fragment(s)
  if not s or s == "" then return nil end
  if s:match("^<.+>$") then s = s:sub(2, -2) end
  s = trim(s)
  if not s then return nil end
  local token = s:match("^(%S+)") or s
  local before, frag = token:match("^(.-)#(.-)$")
  if before then return trim(before), trim(frag) end
  return token, nil
end

return function(line)
  if not line or line == "" then
    local near = find_attr_near_cursor(8)
    if near and looks_like_file_uri(near) then
      local t, f = split_target_and_fragment(near)
      if t then return { target = t, fragment = f } end
    end
    return nil
  end

  local md_target = extract_md_paren_target(line)
  if md_target and looks_like_file_uri(md_target) then
    local t, f = split_target_and_fragment(md_target)
    if t then return { target = t, fragment = f } end
  end

  local html_target = extract_html_attr(line)
  if html_target and looks_like_file_uri(html_target) then
    local t, f = split_target_and_fragment(html_target)
    if t then return { target = t, fragment = f } end
  end

  local near = find_attr_near_cursor(12)
  if near and looks_like_file_uri(near) then
    local t, f = split_target_and_fragment(near)
    if t then return { target = t, fragment = f } end
  end

  return nil
end
