---@module 'markdown_nvim.anchor.is_anchor_line'
---@param line string
---@return boolean
return function(line)
  if not line or line == "" then return false end
  local anchor = line:match("%((#[^)]+)%)")
  if anchor then
    if not anchor:match("^#") then return false end
    return true
  end
  return false
end
