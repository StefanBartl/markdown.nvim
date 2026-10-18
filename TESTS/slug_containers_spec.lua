-- TESTS/slug_containers_spec.lua — headings inside block quotes and list items take part in the anchor numbering (as on
-- GitHub), a fence opened inside such a container still hides its lines, and the jump to an anchor counts the same way.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local api = vim.api
  local slug = require("markdown.core.slug")

  local function anchors(lines)
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local out = {}
    for _, item in ipairs(slug.heading_anchors(buf, { style = "gfm", separator = "-" }).list) do
      out[#out + 1] = item.anchor
    end
    return table.concat(out, ",")
  end

  eq(slug.strip_containers("> - ## Setup"), "## Setup", "nested quote and bullet are taken off")
  eq(slug.strip_containers("1. ## Setup"), "## Setup", "an ordered marker too")
  eq(slug.strip_containers("## Setup"), "## Setup", "a plain heading is unchanged")
  eq(slug.strip_containers("---"), "---", "a rule is not a bullet")
  eq(slug.strip_containers("* * *"), "*", "a spaced rule is taken apart, never into a heading")

  -- the example of the task: GitHub numbers all three
  eq(
    anchors({ "## Setup", "", "> ## Setup", "", "## Setup" }),
    "setup,setup-1,setup-2",
    "a heading in a block quote advances the counter"
  )
  eq(
    anchors({ "## Setup", "", "- ## Setup", "", "1. ## Setup", "", "> - ## Setup" }),
    "setup,setup-1,setup-2,setup-3",
    "list items and nested containers count too"
  )

  -- a fence inside a container is still a fence
  eq(
    anchors({ "## Setup", "", "> ```md", "> ## Setup", "> ```", "", "## Setup" }),
    "setup,setup-1",
    "headings inside a fenced block in a quote yield nothing"
  )
  eq(
    anchors({ "text #not-a-heading", "- #tag", "> text" }),
    "",
    "no heading without the space after the hashes"
  )

  -- the jump counts the same way
  local jump = require("markdown.anchor.jump")
  local buf = H.scratch("markdown")
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "## Setup",
    "",
    "> ## Setup",
    "",
    "## Setup",
    "",
    "[third](#setup-2)",
  })
  api.nvim_win_set_cursor(0, { 7, 3 })
  jump.jump()
  eq(
    api.nvim_win_get_cursor(0)[1],
    5,
    "#setup-2 is the third heading, the one after the quoted one"
  )
end
