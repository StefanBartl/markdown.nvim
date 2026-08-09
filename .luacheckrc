-- luacheck configuration for markdown.nvim
std = "lua51"
cache = true

-- Neovim injects `vim` as a read-only global.
read_globals = { "vim" }

-- Line length is handled by stylua, not luacheck.
max_line_length = false

ignore = {
  "212/_.*", -- unused argument whose name starts with underscore
  "211/_.*", -- unused local variable whose name starts with underscore
  "212/self", -- unused self
  "122", -- setting a read-only field of a global (e.g. vim.*): common in Neovim
}

-- Test specs intentionally use partial config tables.
files["docs/TESTS/**"] = {
  ignore = { "631", "211" },
}
