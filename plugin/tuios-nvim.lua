-- The :Tuios* commands. Keymaps are set by require("tuios-nvim").setup().
local function command(name, action, options)
  vim.api.nvim_create_user_command(name, action, options or {})
end

command("TuiosReview", function(args)
  local mode = args.args == "turn" and "turn" or "all"
  require("tuios-nvim.review").open(mode)
end, {
  nargs = "?",
  complete = function()
    return { "all", "turn" }
  end,
  desc = "Review Claude's changes: all (default) or only the last turn",
})

command("TuiosDiff", function()
  require("tuios-nvim.diff").toggle()
end, { desc = "Show or hide the old version of this file" })

command("TuiosNote", function(args)
  require("tuios-nvim.notes").add(args.line1, args.line2)
end, { range = true, desc = "Add a review note on this line or range" })

command("TuiosNotes", function()
  require("tuios-nvim.notes").list()
end, { desc = "List review notes" })

command("TuiosNoteEdit", function()
  require("tuios-nvim.notes").edit_on_cursor_line()
end, { desc = "Edit the review note on this line" })

command("TuiosNoteDelete", function()
  require("tuios-nvim.notes").delete_on_cursor_line()
end, { desc = "Delete the review note on this line" })

command("TuiosSend", function(args)
  require("tuios-nvim.notes").send(args.bang)
end, { bang = true, desc = "Send unsent notes to Claude (! queues even if one already waits)" })

command("TuiosPaste", function()
  require("tuios-nvim.notes").paste()
end, { desc = "Paste unsent notes into Claude's input without pressing Enter" })

command("TuiosStage", function()
  require("tuios-nvim.stage").stage_hunk()
end, { desc = "Stage the hunk under the cursor" })

command("TuiosStageFile", function()
  require("tuios-nvim.stage").stage_file()
end, { desc = "Stage this whole file" })

command("TuiosStageUndo", function()
  require("tuios-nvim.stage").undo()
end, { desc = "Undo the last stage" })

command("TuiosAgent", function()
  require("tuios-nvim.agent").ask(function() end)
end, { desc = "Pick which Claude pane to review" })
