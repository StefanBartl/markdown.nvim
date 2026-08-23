-- TESTS/usrcmd_complete_spec.lua — `:Markdown` argument completion past the
-- first argument.
--
-- The bug this pins down: the MARKDOWN_SUBARG composer type rebuilt a
-- synthetic cmdline from `arg_lead` alone, and each :Markdown route declared a
-- single positional slot. Between them, every argument after the first
-- completed to nothing — `:Markdown links show <Tab>` offered no scope, and
-- `:Markdown table view toggle <Tab>` never reached its scope branch at all.
--
-- Both halves are covered: the router (commands.complete, called with the
-- cmdline it would really see) and the registered command end to end
-- (vim.fn.getcompletion, which only works if the real cmdline reaches the
-- type's completer and the route declares enough slots).

return function(H)
  local eq, ok = H.eq, H.ok
  local commands = require("markdown.commands")

  ---@param list string[]
  ---@param want string
  ---@return boolean
  local function has(list, want)
    for _, v in ipairs(list) do
      if v == want then return true end
    end
    return false
  end

  require("markdown.config").setup({})

  -- ===========================================================================
  -- 1) The router: a later argument delegates on the cmdline, not on arglead
  -- ===========================================================================
  do
    local scope = commands.complete("", "Markdown links show ")
    ok(has(scope, "%"), "links show: offers the % (current buffer) scope")
    ok(has(scope, "cwd"), "links show: offers the cwd scope")

    eq(
      #commands.complete("", "Markdown links show % "),
      0,
      "links show: nothing past its single scope argument"
    )

    -- Third level: `table view <action> <scope>` is two arguments deep.
    local view_scope = commands.complete("", "Markdown table view toggle ")
    ok(has(view_scope, "%"), "table view toggle: offers the % scope")
    ok(has(view_scope, "cwd"), "table view toggle: offers the cwd scope")
    ok(
      has(commands.complete("", "Markdown table view browser "), "reopen"),
      "table view browser: offers reopen, not the toggle/box scopes"
    )

    -- `table format` takes an open-ended run of option tokens, so the same set
    -- stays on offer at every slot after the first.
    ok(
      has(commands.complete("", "Markdown table format left "), "header=center"),
      "table format: still completing options at the second one"
    )
  end

  -- ===========================================================================
  -- 2) A subcommand name is never a candidate in an argument position
  -- ===========================================================================
  do
    local out = commands.complete("", "Markdown refs rename ")
    eq(#out, 0, "refs rename: takes no completable argument, and is not one itself")
    ok(
      not has(commands.complete("", "Markdown links show "), "show"),
      "links show: the sub-subcommand names are gone once one is chosen"
    )
    eq(#commands.complete("", "Markdown zzz "), 0, "unknown subcommand: no candidates")
    ok(#commands.complete("", "Markdown ") > 0, "the subcommand slot itself still completes")
  end

  -- ===========================================================================
  -- 3) End to end through the registered :Markdown command
  -- ===========================================================================
  do
    -- Registering straight from the binding, rather than firing FileType:
    -- the suite runs with -u NONE, so the plugin's own autocmds are not
    -- necessarily installed, and :Markdown is what is under test here.
    local buf = H.scratch("markdown")
    require("markdown.bindings.usrcmds").apply({ buf = buf })
    eq(vim.fn.exists(":Markdown"), 2, ":Markdown is registered")

    local scope = vim.fn.getcompletion("Markdown links show ", "cmdline")
    ok(has(scope, "%"), "getcompletion: links show offers %")
    ok(has(scope, "cwd"), "getcompletion: links show offers cwd")

    local view_scope = vim.fn.getcompletion("Markdown table view toggle ", "cmdline")
    ok(has(view_scope, "cwd"), "getcompletion: table view toggle reaches its scope branch")

    ok(
      has(vim.fn.getcompletion("Markdown table format left ", "cmdline"), "cell=right"),
      "getcompletion: table format keeps completing past its first option"
    )
  end
end
