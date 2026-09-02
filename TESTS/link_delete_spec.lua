-- Test code: when something here comes back nil -- a fixture write, a
-- resolution -- this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/link_delete_spec.lua — core.link_delete: which lines carry something
-- deletable, which do not, and that a line without one is still plain `dd`.
--
-- `M.candidate` is split out so the decision that precedes the dialog is
-- testable without one. The dialog itself is stubbed through `package.loaded`
-- rather than opened: `run` requires `lib.nvim.ui.kit.confirm` at call time,
-- so replacing the entry answers the question without a floating window --
-- which is how the delete path, the one that touches the filesystem, gets
-- covered at all. Both answers are exercised; "no" has to leave the fixture
-- file on disk, and that is the assertion that matters most in this file.

return function(H)
  local eq = H.eq
  local ok = H.ok

  package.loaded["markdown.util.path"] = nil
  package.loaded["markdown.core.link_delete"] = nil
  local link_delete = require("markdown.core.link_delete")

  local root = (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/mdnvim_linkdeletespec"):gsub(
    "\\",
    "/"
  )

  local run_ok, err = pcall(function()
    vim.fn.mkdir(root .. "/sub", "p")

    local fh = io.open(root .. "/target.md", "w")
    ok(fh ~= nil, "fixture write: target.md")
    fh:write("# Target\n")
    fh:close()

    local fh2 = io.open(root .. "/other.md", "w")
    ok(fh2 ~= nil, "fixture write: other.md")
    fh2:write("# Other\n")
    fh2:close()

    -- The buffer's own directory is the first base a relative target resolves
    -- against, so the fixture has to look like a file inside it.
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")

    -- ── Lines with nothing to delete ───────────────────────────────────────
    local nothing = {
      ["plain text"] = "just a sentence",
      ["a bare URL"] = "see https://example.com for details",
      ["a linked URL"] = "see [example](https://example.com)",
      ["a mailto:"] = "write to [me](mailto:me@example.com)",
      ["an in-document anchor"] = "jump to [Target](#target)",
      ["an empty line"] = "",
    }
    for what, line in pairs(nothing) do
      local cand, reason = link_delete.candidate(line, 1)
      eq(cand, nil, "no candidate for " .. what)
      eq(reason, nil, "and no complaint for " .. what)
    end

    -- ── A link that names a file, but not one that exists ───────────────────
    local missing, missing_reason = link_delete.candidate("[gone](gone.md)", 1)
    eq(missing, nil, "no candidate for a link to a file that is not there")
    ok(missing_reason ~= nil, "but it says why -- a dead link is worth reporting")

    -- A directory is a file-shaped target the key deliberately refuses.
    local dir_cand, dir_reason = link_delete.candidate("[sub](sub)", 1)
    eq(dir_cand, nil, "no candidate for a target that is a directory")
    ok(dir_reason ~= nil, "and it says so")

    -- ── The real thing ─────────────────────────────────────────────────────
    local cand = link_delete.candidate("see [Target](target.md)", 1)
    ok(cand ~= nil, "a link to an existing file is a candidate")
    eq(vim.fs.normalize(cand.resolved), root .. "/target.md", "resolved against the buffer's dir")
    eq(cand.target_path, "target.md", "target as written")
    eq(cand.total, 1, "one link on the line")

    -- A `#fragment` says where to land inside the file, not what is on disk.
    local frag = link_delete.candidate("see [Target](target.md#target)", 1)
    ok(frag ~= nil, "a fragment does not stop it")
    eq(vim.fs.normalize(frag.resolved), root .. "/target.md", "fragment stripped before resolving")
    eq(frag.target_path, "target.md", "and kept out of the target path")

    -- ── Several links: the first file wins, and the count is reported ──────
    local multi = link_delete.candidate("[a](https://x.test) [b](target.md) [c](other.md)", 1)
    ok(multi ~= nil, "a URL earlier on the line does not shadow a later file")
    eq(vim.fs.normalize(multi.resolved), root .. "/target.md", "first file link wins")
    eq(multi.total, 3, "the dialog is told how many links the line had")

    -- ── A line with no link is still `dd` ──────────────────────────────────
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second", "third" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    link_delete.run(buf)
    eq(
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ","),
      "first,third",
      "run() on a line without a link deletes exactly that line"
    )
    eq(vim.fn.getreg('"'), "second\n", "and the line is in the unnamed register, as after dd")

    -- The file the fixture links to is still there: nothing ran the delete
    -- path, and nothing should have.
    ok(vim.uv.fs_stat(root .. "/target.md") ~= nil, "no fixture file was deleted")

    -- ── The delete path, with the dialog stubbed ───────────────────────────
    local real_confirm = package.loaded["lib.nvim.ui.kit.confirm"]
    local asked ---@type string|nil

    --- Run `DD` on a one-line buffer linking to `rel`, answering the dialog
    --- with `answer`. Returns once the async reference scan and the answer
    --- have both been through the event loop.
    ---@param rel string
    ---@param answer boolean
    ---@return boolean finished
    local function press_DD(rel, answer)
      asked = nil
      local done = false
      package.loaded["lib.nvim.ui.kit.confirm"] = {
        open = function(opts)
          asked = opts.question
          opts.on_answer(answer)
          done = true
        end,
      }
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ("see [T](%s)"):format(rel) })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      link_delete.run(buf)
      return vim.wait(5000, function() return done end, 20)
    end

    ok(press_DD("other.md", false), "the dialog was reached (answer: no)")
    ok(asked:find("other.md", 1, true) ~= nil, "the dialog names the resolved path")
    ok(vim.uv.fs_stat(root .. "/other.md") ~= nil, "answering no keeps the file")
    eq(
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ","),
      "see [T](other.md)",
      "and keeps the line -- cancelling leaves the buffer as it was"
    )

    ok(press_DD("target.md", true), "the dialog was reached (answer: yes)")
    eq(vim.uv.fs_stat(root .. "/target.md"), nil, "answering yes deletes the file")
    eq(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ","), "", "and the line with it")

    package.loaded["lib.nvim.ui.kit.confirm"] = real_confirm
  end)

  vim.fn.delete(root, "rf")
  if not run_ok then error(err, 0) end
end
