-- Puts the agent's changes in the quickfix list, one entry per hunk.
--
-- Two modes:
--   "all"  - everything the agent changed, against the branch base (review-diff)
--   "turn" - only what the agent's last turn changed (checkpoint-diff)
local tuios = require("tuios-nvim.tuios")
local agent = require("tuios-nvim.agent")

local M = {}

local TITLE_PREFIX = "tuios review"

-- The review shown now. diff.lua and notes.lua read it.
-- Fields: mode, agent, root (repo folder), base (git revision of the old side).
M.current = nil

-- The line to jump to for a hunk: its first added line.
-- A hunk that only deletes has no added line, so use where the deletion was.
local function first_changed_line(hunk)
  for _, line in ipairs(hunk.lines) do
    if line.op == "add" then
      return line.new
    end
  end
  return math.max(hunk.new_start, 1)
end

local function count_changes(hunk)
  local added = 0
  local removed = 0
  for _, line in ipairs(hunk.lines) do
    if line.op == "add" then
      added = added + 1
    elseif line.op == "delete" then
      removed = removed + 1
    end
  end
  return added, removed
end

local function quickfix_items(files, root)
  local items = {}
  for _, file in ipairs(files) do
    for _, hunk in ipairs(file.hunks or {}) do
      local added, removed = count_changes(hunk)
      table.insert(items, {
        filename = root .. "/" .. file.path,
        lnum = first_changed_line(hunk),
        text = string.format("[%s] +%d -%d  %s", file.status, added, removed, hunk.header),
      })
    end
  end
  return items
end

-- Everything the agent changed. Returns the review, or nil and an error.
local function load_all_changes(the_agent)
  local reply, err = tuios.call("review-diff", { session = tuios.session(), window = the_agent.window_id })
  if not reply then
    return nil, err
  end
  return {
    mode = "all",
    agent = the_agent,
    root = reply.repo_root,
    base = reply.base_sha,
    files = reply.files or {},
    title = TITLE_PREFIX .. ": all changes",
  }
end

-- Only the agent's last turn. Returns the review, or nil and an error.
local function load_last_turn(the_agent)
  local params = { session = tuios.session(), window = the_agent.window_id }

  local list, err = tuios.call("list-checkpoints", params)
  if not list then
    return nil, err
  end
  local checkpoints = list.checkpoints or {}
  if #checkpoints == 0 then
    return nil, "no turns saved yet (tuios saves one when a turn that changed files ends)"
  end
  local newest = checkpoints[#checkpoints]

  params.n = newest.n
  local reply, diff_err = tuios.call("checkpoint-diff", params)
  if not reply then
    return nil, diff_err
  end
  return {
    mode = "turn",
    agent = the_agent,
    root = newest.worktree,
    -- The old side of a turn is the checkpoint before it. base_tree names it as a git tree.
    base = reply.base_tree,
    files = reply.files or {},
    title = string.format("%s: turn %d", TITLE_PREFIX, newest.turn),
  }
end

local function load(mode, the_agent)
  if mode == "turn" then
    return load_last_turn(the_agent)
  end
  return load_all_changes(the_agent)
end

-- Shows the agent's changes in the quickfix list and opens it.
function M.open(mode)
  agent.pick(function(the_agent)
    local review, err = load(mode, the_agent)
    if not review then
      vim.notify("tuios-nvim: " .. err, vim.log.levels.ERROR)
      return
    end

    M.current = review
    local items = quickfix_items(review.files, review.root)
    if #items == 0 then
      vim.notify("tuios-nvim: no changes to review", vim.log.levels.INFO)
      return
    end
    vim.fn.setqflist({}, " ", { title = review.title, items = items })
    vim.cmd("copen")
  end)
end

-- Reloads the review in place, when the quickfix list still shows it.
-- Called when the agent finishes a turn.
function M.refresh()
  if not M.current then
    return
  end
  local shown_title = vim.fn.getqflist({ title = 0 }).title
  if not vim.startswith(shown_title, TITLE_PREFIX) then
    return
  end

  local review = load(M.current.mode, M.current.agent)
  if not review then
    return
  end
  M.current = review
  -- "r" replaces the items of the current list without opening or moving anything.
  vim.fn.setqflist({}, "r", { title = review.title, items = quickfix_items(review.files, review.root) })
end

return M
