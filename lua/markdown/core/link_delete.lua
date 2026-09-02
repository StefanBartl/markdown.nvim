---@module 'markdown.core.link_delete'
---@brief Delete a link's line and, on confirmation, the file it points at.
---@description
--- The action behind the `DD` key: on a line that links to a file which exists,
--- ask whether the file should go too, and delete both when the answer is yes.
--- On any other line it is plain `dd`, count included -- a key that is `dd`
--- plus something is only usable if it is never less than `dd`.
---
--- Deliberately narrow about what counts as deletable, because the failure mode
--- is unrecoverable:
---   * URLs, `mailto:`, in-document `#anchor` links -- nothing to delete.
---   * A target that resolves to a directory. Deleting a tree behind one
---     keypress is a different feature with a different confirmation.
---   * A target that does not exist on disk. The line is still deleted; the
---     notification says the file was not there, because "the link was dead"
---     is the useful half of that answer.
--- The first link on the line wins when there are several, and the dialog says
--- so. A chooser in front of the confirm dialog would be two prompts deep for a
--- key whose whole promise is "like dd, but more".
---
--- The reference count in the dialog is what makes it a decision rather than a
--- formality: `core.file_refs` finds every other `*.md` under the cwd whose
--- links resolve to the same file. It runs async (ripgrep prefilter), so the
--- dialog appears a moment after the key rather than blocking on the scan --
--- and because the buffer can move in that moment, the line is re-read and
--- compared before anything is deleted.
---
--- This is the feature `core.file_refs`'s module doc used to say markdown.nvim
--- does not have.

local link_scan = require("markdown.core.link_scan")
local path = require("markdown.util.path")
local file_refs = require("markdown.core.file_refs")
local notify = require("markdown.util.notify").create("[markdown.core.link_delete]")

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

---@internal
--- Split a raw link target into its path part and its `#fragment`.
--- `docs/foo.md#section` is a link to `docs/foo.md`; the fragment says where to
--- land inside it and is not part of what is on disk.
---@param target string
---@return string target_path, string|nil fragment
local function split_fragment(target)
  local before, frag = target:match("^(.-)#(.*)$")
  if before and before ~= "" then return before, frag end
  return target, nil
end

---@internal
--- True for targets that name no local file at all.
---@param target string
---@return boolean
local function is_non_file(target)
  if target == "" then return true end
  if target:sub(1, 1) == "#" then return true end -- in-document anchor
  if target:match("^%w[%w+.%-]*://") then return true end -- scheme://
  if target:match("^mailto:") then return true end
  return false
end

---@class Mkdn.LinkDeleteCandidate
---@field link Mkdn.Link       # The link the target came from.
---@field target_path string   # Raw target with any `#fragment` removed.
---@field resolved string      # Absolute path on disk (exists, and is a file).
---@field total integer        # How many links the line carried in total.

--- The first link on `line` that points at an existing file.
---
--- Exposed for tests and for anything that wants the same "is there something
--- to delete here" answer without the dialog.
---@param line string
---@param lnum integer
---@return Mkdn.LinkDeleteCandidate|nil candidate
---@return string|nil reason # Why there is none, when the line did carry links.
function M.candidate(line, lnum)
  local links = link_scan.from_line(line or "", lnum or 1)
  if #links == 0 then return nil, nil end

  local saw_file_target = false

  for _, link in ipairs(links) do
    if link.kind ~= "url" and not is_non_file(link.target) then
      local target_path = split_fragment(link.target)
      if not is_non_file(target_path) then
        saw_file_target = true
        local resolved = path.resolve(target_path)
        local stat = resolved and uv.fs_stat(resolved) or nil
        if stat and stat.type == "file" then
          return {
            link = link,
            target_path = target_path,
            resolved = resolved,
            total = #links,
          },
            nil
        end
      end
    end
  end

  if saw_file_target then return nil, "no link on this line points at a file that exists" end
  return nil, nil
end

---@internal
--- The `dd` this key stands in for, with whatever count was typed in front of
--- it -- and with *no* count when none was.
---
--- The difference matters beyond tidiness: `:normal! 1dd` leaves `v:count` at
--- 1 for whatever runs next, and the next thing is often another mapping that
--- reads it (in this plugin, the by-level heading hops). Spelling out a count
--- the user did not type turns this key into a source of that bug.
---@return string
local function plain_dd()
  local count = vim.v.count
  return (count > 0 and tostring(count) or "") .. "dd"
end

---@internal
--- Delete line `lnum` from `bufnr`, keeping the text in the unnamed register so
--- `p` puts it back the way it would after `dd`.
---@param bufnr integer
---@param lnum integer
---@param line string
---@return nil
local function cut_line(bufnr, lnum, line)
  vim.fn.setreg('"', line, "l")
  api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, {})
end

---@internal
--- How many *other* places link to `resolved` -- the ref being deleted does not
--- count as a reason to keep the file.
---@param refs MarkdownFileRef[]
---@param self_file string  Absolute path of the buffer the link lives in.
---@param lnum integer
---@return integer
local function count_others(refs, self_file, lnum)
  local wanted = self_file ~= "" and path.normalize(self_file):lower() or nil
  local n = 0
  for _, ref in ipairs(refs) do
    local same = wanted ~= nil and path.normalize(ref.file):lower() == wanted and ref.line == lnum
    if not same then n = n + 1 end
  end
  return n
end

---@internal
---@param cand Mkdn.LinkDeleteCandidate
---@param others integer
---@return string
local function question(cand, others)
  local lines = {
    "Delete the linked file as well?",
    "",
    cand.resolved,
  }
  if others == 1 then
    lines[#lines + 1] = "1 other link points at it."
  elseif others > 1 then
    lines[#lines + 1] = ("%d other links point at it."):format(others)
  end
  if cand.total > 1 then
    lines[#lines + 1] = ("(first of %d links on this line)"):format(cand.total)
  end
  return table.concat(lines, "\n")
end

--- `DD`: delete the current line, and the file its first link points at.
---
--- With no such link this is `dd` and nothing else, the count included.
--- With one, the line is only deleted after the dialog is answered -- so
--- cancelling leaves the buffer exactly as it was, not with the line gone.
---@param bufnr? integer  Defaults to the current buffer.
---@return nil
function M.run(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local lnum = api.nvim_win_get_cursor(0)[1]
  local line = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if line == nil then return end

  local cand, reason = M.candidate(line, lnum)

  if not cand then
    if reason then notify.info(reason) end
    -- Plain `dd`, including the count, so the key is never worse than the one
    -- it replaces.
    vim.cmd("normal! " .. plain_dd())
    return
  end

  local ok_confirm, confirm = pcall(require, "lib.nvim.ui.kit.confirm")
  if not ok_confirm then
    -- Without the dialog there is no way to ask, and deleting a file without
    -- asking is not a thing this key is allowed to do.
    notify.warn("lib.nvim's ui.kit is required to confirm the file deletion")
    vim.cmd("normal! " .. plain_dd())
    return
  end

  local self_file = api.nvim_buf_get_name(bufnr)

  file_refs.find_references_async(cand.resolved, nil, function(refs)
    if not api.nvim_buf_is_valid(bufnr) then return end

    -- The buffer was live while the scan ran. Deleting by remembered line
    -- number would delete whatever moved into that position instead.
    local now = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
    if now ~= line then
      notify.warn("line changed while looking for references -- nothing deleted")
      return
    end

    confirm.open({
      title = "markdown.nvim",
      question = question(cand, count_others(refs, self_file, lnum)),
      on_answer = function(yes)
        if not yes then return end
        if not api.nvim_buf_is_valid(bufnr) then return end

        local still = api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        if still ~= line then
          notify.warn("line changed while the dialog was open -- nothing deleted")
          return
        end

        if vim.fn.delete(cand.resolved) ~= 0 then
          -- The line stays: a link to a file that is still there is not a
          -- dangling reference, and removing it would hide the failure.
          notify.error("could not delete " .. cand.resolved)
          return
        end

        cut_line(bufnr, lnum, line)
        notify.info("deleted " .. cand.resolved)
      end,
    })
  end)
end

return M
