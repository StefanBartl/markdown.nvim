-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "markdown",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "color_my_ascii.nvim", "hover.nvim", "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "MAGICK_*" },
  -- Guards (testing.nvim docs/GUARDS.md). The suite runs `isolated = "file"`, so setup() state
  -- and the child's own stdpath sandbox are harmless; everything below is checked strictly.
  guards = {
    fs = "error",
    state = "error",
    process_net = "error",
    -- Real finding: lua/markdown/tableview/renderer.lua uses the deprecated `vim.highlight`
    -- (removal in Nvim 2.0); hit by the tableview and session_features specs.
    deprecation = "warn",
  },
  guard_allow = {
    -- `rg` is the real search tool of the file-refs / link-delete features; `cmd` runs the
    -- short-name probe (`cmd /c for %I`) of the path resolver on Windows.
    spawn = { "rg", "cmd" },
  },
}
