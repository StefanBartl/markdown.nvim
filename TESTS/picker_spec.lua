-- TESTS/picker_spec.lua — util/picker.lua backend selection + fallback.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  package.loaded["markdown.util.picker"] = nil
  local picker = require("markdown.util.picker")

  local items = { "one", "two", "three" }

  -- Stub vim.ui.select so the fallback path never blocks on real input.
  local orig_select = vim.ui.select
  local last_select_items = nil
  vim.ui.select = function(select_items, _opts, on_choice)
    last_select_items = select_items
    on_choice(select_items[1])
  end

  -- "select" backend goes straight to vim.ui.select.
  do
    local chosen = nil
    picker.select(items, { backend = "select" }, function(it) chosen = it end)
    eq(chosen, "one", "select backend picks first item via vim.ui.select")
  end

  -- Unknown backend falls back to vim.ui.select (with a warning, not asserted here).
  do
    local chosen = nil
    picker.select(items, { backend = "does_not_exist" }, function(it) chosen = it end)
    eq(chosen, "one", "unknown backend falls back to vim.ui.select")
  end

  -- telescope/fzf backends: plugins aren't installed in the test env, so both
  -- must fall back to vim.ui.select rather than erroring.
  for _, backend in ipairs({ "telescope", "fzf" }) do
    local chosen = nil
    picker.select(items, { backend = backend }, function(it) chosen = it end)
    eq(chosen, "one", backend .. " backend falls back to vim.ui.select when plugin missing")
  end

  -- Empty item list: no callback invocation, no error.
  do
    local called = false
    picker.select({}, { backend = "select" }, function() called = true end)
    ok(not called, "empty items never invoke on_choose")
  end

  ok(last_select_items ~= nil, "vim.ui.select was invoked at least once")

  vim.ui.select = orig_select
end
