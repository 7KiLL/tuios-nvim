-- tuios-nvim: review what Claude Code changed, from nvim, inside tuios.
local review = require("tuios-nvim.review")
local diff = require("tuios-nvim.diff")
local notes = require("tuios-nvim.notes")
local stage = require("tuios-nvim.stage")
local watch = require("tuios-nvim.watch")
local agent = require("tuios-nvim.agent")

local M = {}

M.config = {
  -- Set to false to define your own keymaps (see the commands in plugin/tuios-nvim.lua).
  keymaps = true,
  prefix = "<leader>r",
}

local function set_keymaps(prefix)
  local function map(mode, keys, action, description)
    vim.keymap.set(mode, prefix .. keys, action, { desc = "tuios review: " .. description })
  end

  map("n", "r", "<cmd>TuiosReview<cr>", "all changes")
  map("n", "t", "<cmd>TuiosReview turn<cr>", "last turn")
  map("n", "v", "<cmd>TuiosDiff<cr>", "toggle old version")
  map("n", "c", "<cmd>TuiosNote<cr>", "add note")
  map("x", "c", ":TuiosNote<cr>", "add note on selection")
  map("n", "l", "<cmd>TuiosNotes<cr>", "list notes")
  map("n", "e", "<cmd>TuiosNoteEdit<cr>", "edit note")
  map("n", "d", "<cmd>TuiosNoteDelete<cr>", "delete note")
  map("n", "s", "<cmd>TuiosSend<cr>", "send notes to Claude")
  map("n", "i", "<cmd>TuiosPaste<cr>", "paste notes into Claude's input")
  map("n", "a", "<cmd>TuiosStage<cr>", "stage hunk")
  map("n", "A", "<cmd>TuiosStageFile<cr>", "stage file")
  map("n", "u", "<cmd>TuiosStageUndo<cr>", "undo stage")
  map("n", "p", "<cmd>TuiosAgent<cr>", "pick Claude pane")
end

-- Refreshes the review and the notes after Claude finishes a turn.
local function on_turn_end()
  review.refresh()
  notes.refresh()
end

function M.setup(options)
  M.config = vim.tbl_extend("force", M.config, options or {})

  if M.config.keymaps then
    set_keymaps(M.config.prefix)
  end

  -- Outside tuios there is nothing to talk to, so stop here.
  if vim.env.TUIOS_ENV ~= "1" then
    return
  end

  -- Redraw a file's notes when it is opened or shown again.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("tuios-nvim", { clear = true }),
    callback = notes.refresh,
  })

  watch.start(on_turn_end)
end

-- The public API, for keymaps you define yourself.
M.open_review = review.open
M.toggle_diff = diff.toggle
M.add_note = notes.add
M.list_notes = notes.list
M.edit_note = notes.edit_on_cursor_line
M.delete_note = notes.delete_on_cursor_line
M.send_notes = notes.send
M.paste_notes = notes.paste
M.stage_hunk = stage.stage_hunk
M.stage_file = stage.stage_file
M.undo_stage = stage.undo
M.pick_agent = agent.ask

-- For a statusline: the number of unsent notes, or "" when there are none.
function M.statusline()
  local unsent = 0
  for _, note in ipairs(notes.all) do
    if not note.sent_at then
      unsent = unsent + 1
    end
  end
  if unsent == 0 then
    return ""
  end
  return "💬 " .. unsent
end

return M
