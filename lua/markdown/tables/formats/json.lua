---@module 'markdown.tables.formats.json'
---@brief JSON as a table (standalone): an array of objects or an array of arrays.
---@description
--- Standalone, like csv: all given lines are one JSON document. An array of objects gives the
--- columns in the order the keys first appear (`vim.json.decode` would lose that order, so the text
--- is read by a small parser of its own); an array of arrays takes the first array as the header; an
--- array of plain values is one column `value`. A cell holds the text of its value: a string as it
--- is, a number or `true`/`false` as written, `null` as an empty cell, an object or array as compact
--- JSON. Written back as an array of objects: a table read from JSON keeps the type of every
--- value that was not changed; a table from another format writes plain numbers (`12`, `-3.5`) as
--- numbers and everything else as strings.

local M = {}

---@class MarkdownJsonValue
---@field kind "string"|"number"|"boolean"|"null"|"object"|"array"
---@field text string          # the cell text
---@field keys? string[]       # object: keys in order
---@field map? table<string, MarkdownJsonValue>
---@field items? MarkdownJsonValue[]

---@param src string
---@return MarkdownJsonValue|nil value, string|nil err
local function parse(src)
  local pos = 1
  local function skip() pos = src:find("[^ \t\r\n]", pos) or #src + 1 end
  local value

  local function str()
    -- pos is on the opening quote: let vim.json decode the string itself
    local i = pos + 1
    while i <= #src do
      local ch = src:sub(i, i)
      if ch == "\\" then
        i = i + 2
      elseif ch == '"' then
        local raw = src:sub(pos, i)
        local ok, decoded = pcall(vim.json.decode, raw)
        if not ok or type(decoded) ~= "string" then return nil, "invalid string" end
        pos = i + 1
        return decoded
      else
        i = i + 1
      end
    end
    return nil, "unterminated string"
  end

  function value()
    skip()
    local ch = src:sub(pos, pos)
    if ch == '"' then
      local s, err = str()
      if not s then return nil, err end
      return { kind = "string", text = s }
    elseif ch == "{" then
      local start = pos
      pos = pos + 1
      local obj = { kind = "object", keys = {}, map = {} }
      skip()
      if src:sub(pos, pos) == "}" then
        pos = pos + 1
      else
        while true do
          skip()
          if src:sub(pos, pos) ~= '"' then return nil, "object key expected" end
          local key, kerr = str()
          if not key then return nil, kerr end
          skip()
          if src:sub(pos, pos) ~= ":" then return nil, "':' expected" end
          pos = pos + 1
          local v, verr = value()
          if not v then return nil, verr end
          if not obj.map[key] then obj.keys[#obj.keys + 1] = key end
          obj.map[key] = v
          skip()
          local sep = src:sub(pos, pos)
          pos = pos + 1
          if sep == "}" then break end
          if sep ~= "," then return nil, "',' or '}' expected" end
        end
      end
      obj.text = src:sub(start, pos - 1)
      return obj
    elseif ch == "[" then
      local start = pos
      pos = pos + 1
      local arr = { kind = "array", items = {} }
      skip()
      if src:sub(pos, pos) == "]" then
        pos = pos + 1
      else
        while true do
          local v, verr = value()
          if not v then return nil, verr end
          arr.items[#arr.items + 1] = v
          skip()
          local sep = src:sub(pos, pos)
          pos = pos + 1
          if sep == "]" then break end
          if sep ~= "," then return nil, "',' or ']' expected" end
        end
      end
      arr.text = src:sub(start, pos - 1)
      return arr
    end
    local lit = src:match("^-?%d[%d%.eE+-]*", pos)
    if lit then
      pos = pos + #lit
      return { kind = "number", text = lit }
    end
    for word, kind in pairs({ ["true"] = "boolean", ["false"] = "boolean", ["null"] = "null" }) do
      if src:sub(pos, pos + #word - 1) == word then
        pos = pos + #word
        return { kind = kind, text = kind == "null" and "" or word }
      end
    end
    return nil, ("unexpected character at %d"):format(pos)
  end

  local v, err = value()
  if not v then return nil, err end
  skip()
  if pos <= #src then return nil, "text after the JSON value" end
  return v, nil
end

---@param lines string[]
---@return table|nil tbl, string|nil err
function M.parse(lines)
  local registry = require("markdown.tables.registry")
  local root, err = parse(table.concat(lines, "\n"))
  if not root then return nil, "not JSON: " .. tostring(err) end
  if root.kind ~= "array" then return nil, "a table needs a JSON array at the top" end
  if #root.items == 0 then return nil, "the array is empty" end

  local header, rows, kinds = {}, {}, {}
  local first = root.items[1]
  if first.kind == "object" then
    local seen = {}
    for _, item in ipairs(root.items) do
      if item.kind ~= "object" then return nil, "mixed array: objects and other values" end
      for _, k in ipairs(item.keys) do
        if not seen[k] then
          seen[k] = true
          header[#header + 1] = k
        end
      end
    end
    for r, item in ipairs(root.items) do
      local row = {}
      kinds[r] = {}
      for c, k in ipairs(header) do
        local v = item.map[k]
        row[c] = v and v.text or ""
        kinds[r][c] = v and v.kind or "null"
      end
      rows[r] = row
    end
  elseif first.kind == "array" then
    local head = root.items[1]
    for c, v in ipairs(head.items) do
      header[c] = v.text
    end
    for r = 2, #root.items do
      local item = root.items[r]
      if item.kind ~= "array" then return nil, "mixed array: arrays and other values" end
      local row = {}
      kinds[r - 1] = {}
      for c, v in ipairs(item.items) do
        row[c] = v.text
        kinds[r - 1][c] = v.kind
      end
      rows[#rows + 1] = row
    end
    local width = #header
    for _, r in ipairs(rows) do
      width = math.max(width, #r)
    end
    for c = #header + 1, width do
      header[c] = ""
    end
  else
    header = { "value" }
    for r, item in ipairs(root.items) do
      rows[r] = { item.text }
      kinds[r] = { item.kind }
    end
  end
  local tbl = registry.from_strings(header, rows, nil, {
    start_line = 1,
    end_line = #lines,
    raw_lines = lines,
    json_kinds = kinds,
  })
  tbl.format = "json"
  return tbl, nil
end

---@param text string
---@return boolean
local function plain_number(text)
  return text:match("^-?[1-9]%d*$") ~= nil
    or text == "0"
    or text:match("^-?[1-9]%d*%.%d+$") ~= nil
    or text:match("^-?0%.%d+$") ~= nil
end

---@param text string
---@param kind? string  # the kind the value was read with (JSON tables only)
---@return string json
local function encode(text, kind)
  if kind == "null" and text == "" then return "null" end
  if kind == "number" or kind == "boolean" then
    if kind == "boolean" and (text == "true" or text == "false") then return text end
    if kind == "number" and text:match("^-?%d[%d%.eE+-]*$") then return text end
  end
  if kind == "object" or kind == "array" then
    local root = parse(text)
    if root then return text end
  end
  if kind == nil and plain_number(text) then return text end
  return vim.json.encode((text:gsub("<br>", "\n")))
end

---@param tbl table
---@return string[]
function M.render(tbl)
  local registry = require("markdown.tables.registry")
  local header, rows = registry.strings(tbl)
  local own = tbl.format == "json" and tbl.json_kinds or nil
  local out = { "[" }
  for r, row in ipairs(rows) do
    local parts = {}
    for c, key in ipairs(header) do
      local kind = own and own[r] and own[r][c] or nil
      -- (a changed cell keeps its kind only when the text still is that kind: see `encode`)
      parts[#parts + 1] = ("    %s: %s"):format(
        vim.json.encode(key == "" and ("column" .. c) or key),
        encode(row[c] or "", own and (kind or "string") or nil)
      )
    end
    out[#out + 1] = "  {"
    out[#out + 1] = table.concat(parts, ",\n")
    out[#out + 1] = "  }" .. (r < #rows and "," or "")
  end
  out[#out + 1] = "]"
  return vim.split(table.concat(out, "\n"), "\n", { plain = true })
end

---@param tbl table
---@return string[]
function M.lossy(tbl)
  local out = {}
  for _, a in ipairs(tbl.alignments or {}) do
    if a ~= "left" then
      out[#out + 1] = "column alignment"
      break
    end
  end
  return out
end

M._parse = parse

return M
