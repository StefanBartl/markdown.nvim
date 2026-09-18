-- TESTS/scope_spec.lua — markdown.scope: backend resolution (get_backend)
-- and its own lifecycle autocmd, as opposed to fenced_scope_spec.lua which
-- drives the ops (TOC/nav/jump/shift/fold) that consult M.detect.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api

  -- ── Regression: the fold-cache invalidation augroup must be idempotent ──
  -- markdown.scope registers a BufDelete/BufWipeout autocmd (module load
  -- time) to invalidate its per-buffer fold_cache. It used to pass the group
  -- as a bare string to lib.nvim.bindings.autocmd.create, which resolves an
  -- existing group by name WITHOUT clear=true — so a second load of this
  -- module (package.loaded reset, e.g. a plugin manager's hot-reload)
  -- registered a second handler in the same group instead of replacing the
  -- first. Confirmed before the fix: three loads left six live autocmds.
  do
    require("markdown.config").setup({})
    for _ = 1, 3 do
      package.loaded["markdown.scope"] = nil
      require("markdown.scope")
    end
    local aus = api.nvim_get_autocmds({ group = "MarkdownNvimScopeFoldCache" })
    eq(
      #aus,
      2, -- BufDelete + BufWipeout, exactly once each
      "BUG regression: reloading markdown.scope 3x must not double up its augroup handlers"
    )
    package.loaded["markdown.scope"] = nil
    require("markdown.scope")
  end

  local scope = require("markdown.scope")

  -- ── provider='color_my_ascii' requested but unavailable: get_backend()
  -- itself (not just health.lua's separate warning) must still fall back to
  -- the builtin scanner and keep working, not error or return nil. ──
  do
    local saved = package.loaded["color_my_ascii"]
    package.loaded["color_my_ascii"] = nil
    package.preload["color_my_ascii"] = function() error("synthetic: not installed") end

    require("markdown.config").setup({ fenced_scope = { provider = "color_my_ascii" } })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# T", "```markdown", "## Inner", "```" })
    local s = scope.detect(buf, 2) -- inside the block
    package.preload["color_my_ascii"] = nil
    package.loaded["color_my_ascii"] = saved

    ok(s and s.kind == "block", "get_backend: falls back to builtin when cma is unavailable")
    eq(s.first, 3, "get_backend fallback: block scope resolved correctly via builtin")
  end

  -- ── The real color_my_ascii fence API, when actually on the runtimepath
  -- (a real sibling checkout, added by TESTS/run.lua's add_sibling — soft,
  -- not required), must be usable by scope.detect exactly like the builtin
  -- backend: this is markdown.nvim's own side of the color_my_ascii
  -- integration contract, previously exercised nowhere in this suite (only
  -- the builtin fallback backend had any coverage). ──
  do
    local cma_ok, cma = pcall(require, "color_my_ascii")
    if not (cma_ok and type(cma) == "table" and type(cma.fences) == "table") then
      print("skip  scope_spec.lua: color_my_ascii not on the runtimepath (optional sibling)")
    else
      require("markdown.config").setup({ fenced_scope = { provider = "color_my_ascii" } })
      scope._reset_backend()
      local buf = H.scratch("markdown")
      api.nvim_buf_set_lines(buf, 0, -1, false, {
        "# Outer", -- 1
        "", -- 2
        "```markdown", -- 3
        "## Inner A", -- 4
        "", -- 5
        "## Inner B", -- 6
        "```", -- 7
        "", -- 8
        "## Outer B", -- 9
      })

      local inside = scope.detect(buf, 3) -- 0-indexed row 3 = "## Inner A"
      ok(inside and inside.kind == "block", "cma backend: cursor inside block -> block scope")
      ---@cast inside -nil
      eq(inside.first, 4, "cma backend: block scope first line (1-indexed interior start)")
      eq(inside.last, 6, "cma backend: block scope last line (1-indexed interior end)")

      local outside = scope.detect(buf, 0) -- "# Outer"
      ok(outside and outside.kind == "buffer", "cma backend: cursor outside block -> buffer scope")
      ---@cast outside -nil
      ok(scope.is_excluded(outside, 4), "cma backend: buffer scope excludes the fenced interior")
      ok(not scope.is_excluded(outside, 9), "cma backend: buffer scope keeps the outer heading")

      require("markdown.config").setup({})
      scope._reset_backend()
    end
  end

  require("markdown.config").setup({})
  scope._reset_backend()
end
