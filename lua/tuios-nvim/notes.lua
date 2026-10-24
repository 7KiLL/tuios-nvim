-- Review notes: add, list, edit, delete and send them, and draw them in buffers.
--
-- The notes live in the tuios daemon, not in nvim. That way they follow their
-- line when the agent edits the file, and tuios's own review screen shows them too.
local tuios = require("tuios-nvim.tuios")
local agent = require("tuios-nvim.agent")
local git = require("tuios-nvim.git")

local M = {}

local namespace = vim.api.nvim_create_namespace("tuios-nvim-notes")

-- Users can override these highlight groups to change the colours.
vim.api.nvim_set_hl(0, "TuiosNote", { default = true, fg = "#d7a65f" })
vim.api.nvim_set_hl(0, "TuiosNoteSent", { default = true, link = "Comment" })
vim.api.nvim_set_hl(0, "TuiosNoteLine", { default = true, link = "CursorLine" })

-- The notes from the last refresh. Each note has: id, path, line, text,
-- sent_at (nil until sent), and filename (the absolute path we added).
M.all = {}

local function notify_error(err)
  vim.notify("tuios-nvim: " .. err, vim.log.levels.ERROR)
end

-- Reads the notes from tuios.
-- Notes come from review-diff, not from review-note list: only review-diff
-- moves a note to its new line after the agent edited the file.
local function fetch_notes(the_agent)
  local reply, err = tuios.call("review-diff", { session = tuios.session(), window = the_agent.window_id })
  if not reply then
    return nil, err
  end
  local notes = reply.notes or {}
  for _, note in ipairs(notes) do
    note.filename = reply.repo_root .. "/" .. note.path
  end
  return notes
end

-- Draws the notes of one buffer: a bar in the sign column, a tinted line,
-- and the note text above the line.
local function draw_buffer(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  local filename = vim.api.nvim_buf_get_name(buffer)
  local line_count = vim.api.nvim_buf_line_count(buffer)

  for _, note in ipairs(M.all) do
    if note.filename == filename and note.line <= line_count then
      local highlight = note.sent_at and "TuiosNoteSent" or "TuiosNote"
      local label = note.sent_at and "✓ " or "💬 "
      vim.api.nvim_buf_set_extmark(buffer, namespace, note.line - 1, 0, {
        sign_text = "▌",
        sign_hl_group = highlight,
        line_hl_group = "TuiosNoteLine",
        virt_lines = { { { "╭─ " .. label .. note.text, highlight } } },
        virt_lines_above = true,
      })
    end
  end
end

local function draw_all_buffers()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) then
      draw_buffer(buffer)
    end
  end
end

-- Fetches the notes again and redraws every buffer.
-- Quiet on purpose: it runs on BufEnter, so it must not ask or complain.
function M.refresh()
  local the_agent = agent.find_without_asking()
  if not the_agent then
    return
  end
  local notes = fetch_notes(the_agent)
  if not notes then
    return
  end
  M.all = notes
  draw_all_buffers()
end

-- Adds a note on lines first_line..last_line of the current buffer.
-- tuios notes sit on one line, so a range is written into the note text.
function M.add(first_line, last_line)
  local filename = vim.api.nvim_buf_get_name(0)
  local root = git.root(filename)
  if filename == "" or not root then
    vim.notify("tuios-nvim: this buffer is not a file in a git repository", vim.log.levels.WARN)
    return
  end
  local path = git.relative(filename, root)

  agent.pick(function(the_agent)
    vim.ui.input({ prompt = "Note: " }, function(text)
      if not text or text == "" then
        return
      end
      if first_line ~= last_line then
        text = string.format("(lines %d-%d) %s", first_line, last_line, text)
      end

      local _, err = tuios.call("review-note", {
        action = "add",
        session = tuios.session(),
        window = the_agent.window_id,
        path = path,
        line = first_line,
        text = text,
      })
      if err then
        notify_error(err)
        return
      end
      M.refresh()
    end)
  end)
end

-- Shows every note in the quickfix list.
function M.list()
  M.refresh()
  if #M.all == 0 then
    vim.notify("tuios-nvim: no review notes", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, note in ipairs(M.all) do
    local status = note.sent_at and "[sent] " or ""
    table.insert(items, { filename = note.filename, lnum = note.line, text = status .. note.text })
  end
  vim.fn.setqflist({}, " ", { title = "tuios review notes", items = items })
  vim.cmd("copen")
end

-- Calls on_note(note) with the note on the cursor line.
-- Asks which one when the line has several.
local function pick_note_on_cursor_line(on_note)
  local filename = vim.api.nvim_buf_get_name(0)
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local notes_here = {}
  for _, note in ipairs(M.all) do
    if note.filename == filename and note.line == line then
      table.insert(notes_here, note)
    end
  end

  if #notes_here == 0 then
    vim.notify("tuios-nvim: no note on this line", vim.log.levels.INFO)
  elseif #notes_here == 1 then
    on_note(notes_here[1])
  else
    vim.ui.select(notes_here, {
      prompt = "Which note?",
      format_item = function(note)
        return note.text
      end,
    }, function(note)
      if note then
        on_note(note)
      end
    end)
  end
end

-- Runs one review-note action (edit or remove) on a note, then redraws.
local function change_note(the_agent, params)
  params.session = tuios.session()
  params.window = the_agent.window_id
  local _, err = tuios.call("review-note", params)
  if err then
    notify_error(err)
    return
  end
  M.refresh()
end

function M.edit_on_cursor_line()
  agent.pick(function(the_agent)
    pick_note_on_cursor_line(function(note)
      vim.ui.input({ prompt = "Edit note: ", default = note.text }, function(text)
        if text and text ~= "" and text ~= note.text then
          change_note(the_agent, { action = "edit", id = note.id, text = text })
        end
      end)
    end)
  end)
end

function M.delete_on_cursor_line()
  agent.pick(function(the_agent)
    pick_note_on_cursor_line(function(note)
      change_note(the_agent, { action = "remove", id = note.id })
    end)
  end)
end

-- True when an earlier review still waits in the agent's queue.
-- tuios types one queued message per agent rest, so a second one would wait behind it.
local function review_already_waiting(the_agent)
  local reply = tuios.call("list-queued", { session = tuios.session(), window = the_agent.window_id })
  if not reply then
    return false
  end
  for _, entry in ipairs(reply.entries or {}) do
    if entry.state == "waiting" then
      return true
    end
  end
  return false
end

local function count_unsent()
  local count = 0
  for _, note in ipairs(M.all) do
    if not note.sent_at then
      count = count + 1
    end
  end
  return count
end

-- Sends every unsent note to the agent as one message.
-- tuios types it when the agent is at rest, never over a question it is asking.
-- With force = false it refuses when an earlier message still waits in the queue.
function M.send(force)
  agent.pick(function(the_agent)
    M.refresh()
    local unsent = count_unsent()
    if unsent == 0 then
      vim.notify("tuios-nvim: no unsent notes", vim.log.levels.INFO)
      return
    end

    if not force and review_already_waiting(the_agent) then
      vim.notify(
        "tuios-nvim: a message already waits for Claude to finish its turn. Use :TuiosSend! to queue this one behind it.",
        vim.log.levels.WARN
      )
      return
    end

    local reply, err = tuios.call("send-review", { session = tuios.session(), window = the_agent.window_id })
    if not reply then
      notify_error(err)
      return
    end

    if reply.delivering then
      vim.notify(string.format("tuios-nvim: sent %d note(s) to Claude", unsent))
    else
      vim.notify(string.format("tuios-nvim: %d note(s) queued, Claude gets them when it is at rest", unsent))
    end
    M.refresh()
  end)
end

-- The message for pasting, in the same shape as the one send-review types.
local function format_message(unsent_notes)
  local lines = { "Review notes on your changes:", "" }
  for number, note in ipairs(unsent_notes) do
    table.insert(lines, string.format('%d. %s:%d, on "%s"', number, note.path, note.line, note.quote or ""))
    table.insert(lines, "   " .. note.text)
  end
  table.insert(lines, "")
  table.insert(lines, "Address each note, then say which you changed.")
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

-- Pastes every unsent note into Claude's input box without pressing Enter,
-- so you can add your own words before you send it.
--
-- tuios has no way to mark notes as sent without sending them itself, so the
-- pasted notes are removed; otherwise :TuiosSend would send them a second time.
function M.paste()
  agent.pick(function(the_agent)
    -- Pasting while Claude asks a question would type into that question,
    -- for example a permission prompt.
    if the_agent.state == "needs_input" then
      vim.notify("tuios-nvim: Claude is waiting on a question, answer it first", vim.log.levels.WARN)
      return
    end

    M.refresh()
    local unsent_notes = {}
    for _, note in ipairs(M.all) do
      if not note.sent_at then
        table.insert(unsent_notes, note)
      end
    end
    if #unsent_notes == 0 then
      vim.notify("tuios-nvim: no unsent notes", vim.log.levels.INFO)
      return
    end

    local _, err = tuios.call("send-text", {
      session = tuios.session(),
      window = the_agent.window_id,
      text = format_message(unsent_notes),
      -- As a paste, the newlines stay inside the text instead of pressing Enter.
      paste = true,
    })
    if err then
      notify_error(err)
      return
    end

    for _, note in ipairs(unsent_notes) do
      tuios.call("review-note", {
        action = "remove",
        session = tuios.session(),
        window = the_agent.window_id,
        id = note.id,
      })
    end
    vim.notify(string.format("tuios-nvim: pasted %d note(s) into Claude's input, add your text and press Enter", #unsent_notes))
    M.refresh()
  end)
end

return M
