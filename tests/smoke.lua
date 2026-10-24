-- Run by tests/smoke.sh. Drives the plugin like a user would and checks the results.
-- Exits nvim with status 0 when every check passes, 1 otherwise.

local function fail(message)
  io.stderr:write("FAIL: " .. message .. "\n")
  vim.cmd("cquit 1")
end

local function check(condition, message)
  if not condition then
    fail(message)
  end
end

local function step(name, test)
  local ok, err = pcall(test)
  if not ok then
    fail(name .. ": " .. tostring(err))
  end
  io.stdout:write("ok   " .. name .. "\n")
end

-- The user's answers to prompts: vim.ui.input returns these in order.
local answers = {}
vim.ui.input = function(_, on_answer)
  on_answer(table.remove(answers, 1))
end

-- Show errors from the plugin as test failures, not as silent messages.
vim.notify = function(message, level)
  if level == vim.log.levels.ERROR then
    fail("plugin error: " .. message)
  end
end

require("tuios-nvim").setup({})
local tuios = require("tuios-nvim.tuios")
local review = require("tuios-nvim.review")
local notes = require("tuios-nvim.notes")
local diff = require("tuios-nvim.diff")
local stage = require("tuios-nvim.stage")
local watch_called = false

step("finds the Claude pane without asking", function()
  local agent = require("tuios-nvim.agent").find_without_asking()
  check(agent ~= nil, "no agent found")
  check(agent.harness_id == "claude-code", "wrong agent")
end)

step("all changes go to the quickfix list", function()
  review.open("all")
  local list = vim.fn.getqflist({ title = 0, items = 0 })
  check(list.title == "tuios review: all changes", "title was " .. list.title)
  check(#list.items == 1, "expected 1 hunk, got " .. #list.items)
end)

step("last turn shows only turn 2", function()
  review.open("turn")
  local list = vim.fn.getqflist({ title = 0, items = 0 })
  check(list.title == "tuios review: turn 2", "title was " .. list.title)
  check(list.items[1].lnum == 8, "expected line 8, got " .. list.items[1].lnum)
end)

step("diff opens and closes the old version", function()
  vim.cmd("cclose")
  vim.cmd("cfirst")
  diff.toggle()
  check(#vim.api.nvim_tabpage_list_wins(0) == 2, "old version window did not open")
  local old_lines = vim.api.nvim_buf_get_lines(vim.fn.winbufnr(vim.fn.winnr("#")), 0, -1, false)
  check(old_lines[8] == "  return a - b", "old side should be before turn 2, got " .. tostring(old_lines[8]))
  diff.toggle()
  check(#vim.api.nvim_tabpage_list_wins(0) == 1, "old version window did not close")
end)

step("a note is added and drawn", function()
  answers = { "drop this comment" }
  notes.add(8, 8)
  check(#notes.all == 1, "expected 1 note, got " .. #notes.all)
  check(notes.all[1].line == 8, "note on wrong line")
  local marks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
  check(#marks >= 1, "note was not drawn")
end)

step("a range note says its lines", function()
  answers = { "whole function" }
  notes.add(3, 5)
  local found = false
  for _, note in ipairs(notes.all) do
    if note.text == "(lines 3-5) whole function" then
      found = true
    end
  end
  check(found, "range note not found")
end)

step("a note is edited and deleted", function()
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  answers = { "whole function, edited" }
  notes.edit_on_cursor_line()
  check(notes.all[1].text == "whole function, edited" or notes.all[2].text == "whole function, edited", "edit failed")
  notes.delete_on_cursor_line()
  check(#notes.all == 1, "delete failed, " .. #notes.all .. " notes left")
end)

step("notes are sent to Claude", function()
  notes.send(false)
  check(notes.all[1].sent_at ~= nil, "note not marked sent")
  vim.wait(3000, function()
    local screen = vim.system({ "tuios", "capture-pane", "-s", tuios.session(), "-w", "claude" }, { text = true }):wait().stdout
    return screen:find("drop this comment", 1, true) ~= nil
  end)
  local screen = vim.system({ "tuios", "capture-pane", "-s", tuios.session(), "-w", "claude" }, { text = true }):wait().stdout
  check(screen:find("Review notes on your changes", 1, true), "Claude's pane did not get the review")
end)

step("notes are pasted without sending, then removed", function()
  answers = { "pasted note" }
  notes.add(4, 4)
  notes.paste()
  vim.wait(3000, function()
    local screen = vim.system({ "tuios", "capture-pane", "-s", tuios.session(), "-w", "claude" }, { text = true }):wait().stdout
    return screen:find("pasted note", 1, true) ~= nil
  end)
  local screen = vim.system({ "tuios", "capture-pane", "-s", tuios.session(), "-w", "claude" }, { text = true }):wait().stdout
  check(screen:find("pasted note", 1, true), "the note was not pasted into Claude's pane")
  for _, note in ipairs(notes.all) do
    check(note.text ~= "pasted note", "the pasted note was not removed")
  end
end)

step("the hunk under the cursor is staged, then unstaged", function()
  local function staged()
    return vim.system({ "git", "diff", "--cached", "--name-only" }, { text = true }):wait().stdout
  end
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  stage.stage_hunk()
  check(staged():find("math.lua"), "math.lua was not staged")
  stage.undo()
  check(staged() == "", "undo did not unstage")
end)

step("a finished turn triggers the watcher", function()
  -- Wrap the refresh so we can see that the watcher called it.
  local real_refresh = review.refresh
  review.refresh = function()
    watch_called = true
    real_refresh()
  end
  local session = tuios.session()
  vim.system({ "tuios", "set-agent-state", "working", "-s", session, "-w", "claude", "--harness", "claude-code" }):wait()
  vim.system({ "tuios", "set-agent-state", "done", "-s", session, "-w", "claude", "--harness", "claude-code" }):wait()
  vim.wait(5000, function()
    return watch_called
  end)
  check(watch_called, "turn end was not noticed")
end)

io.stdout:write("all checks passed\n")
vim.cmd("qall!")
