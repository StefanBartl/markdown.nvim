---@module 'markdown_nvim.core.fold'
local M = {}

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)

  local atx = line:match("^%s*(#+)%s+")
  if atx then
    -- Fenced-scope gating (opt-in via fenced_scope.operations.fold). A `#`-line
    -- inside a NON-markdown fenced block is code (e.g. a shell/python comment),
    -- not a heading, so it must not open a fold. Inside a markdown-family fence
    -- it stays a heading (the block is its own sub-document). Zero overhead when
    -- the fold op is disabled — the scope module isn't even consulted.
    local scope = require("markdown_nvim.scope")
    if scope.op_enabled("fold") then
      local kind = scope.row_fence_kind(vim.api.nvim_get_current_buf(), lnum - 1)
      if kind == "code" then
        return "="
      end
    end
    return ">" .. #atx
  end

  local prev = vim.fn.getline(lnum - 1)
  if prev and prev:match("^%s*%S") and line:match("^%s*[-=]+%s*$") then
    return ">2"
  end

  return "="
end

function M.toggle_under_cursor()
  vim.cmd.normal({ args = { "za" }, bang = false })
  vim.cmd.normal({ args = { "zz" }, bang = false })
end

function M.unfold_all_center()
  vim.cmd.normal({ args = { "zR" }, bang = false })
  vim.cmd.normal({ args = { "zz" }, bang = false })
end

return M
