# tuios-nvim

Review what Claude Code changed, from Neovim, while Claude runs in a
[tuios](https://github.com/Gaurav-Gosain/tuios) pane. You can:
- read the diff of all its changes, or of its last turn only;
- leave notes on lines;
- send the notes back to Claude as one message;
- stage the hunks you accept.

Everything goes through tuios's own review verbs, so the notes also show up in
tuios's review screen. They also stay on their line when Claude edits the file.

Requirements: nvim ≥ 0.10, tuios ≥ 0.10.1, and nvim running inside a tuios pane.

## Install (lazy.nvim)

```lua
{ "7KiLL/tuios-nvim", cond = vim.env.TUIOS_ENV == "1", opts = {} }
```

## Keys and commands

| Key | Command | Does |
| --- | --- | --- |
| `<leader>rr` | `:TuiosReview` | All of Claude's changes in the quickfix list, one entry per hunk |
| `<leader>rt` | `:TuiosReview turn` | Only what Claude's last turn changed |
| `<leader>rv` | `:TuiosDiff` | Show or hide the old version beside the file (nvim diff mode) |
| `<leader>rc` | `:TuiosNote` | Add a note on the line, or on the selection in visual mode |
| `<leader>rl` | `:TuiosNotes` | List the notes in the quickfix list |
| `<leader>re` | `:TuiosNoteEdit` | Edit the note on this line |
| `<leader>rd` | `:TuiosNoteDelete` | Delete the note on this line |
| `<leader>rs` | `:TuiosSend` | Send unsent notes to Claude. It types them when Claude is at rest. |
| `<leader>ri` | `:TuiosPaste` | Paste unsent notes into Claude's input **without pressing Enter**, so you can add text. The pasted notes are removed from the list. |
| `<leader>ra` | `:TuiosStage` | Stage the hunk under the cursor |
| `<leader>rA` | `:TuiosStageFile` | Stage the whole file |
| `<leader>ru` | `:TuiosStageUndo` | Undo the last stage |
| `<leader>rp` | `:TuiosAgent` | Pick which Claude pane to review (only needed when there are several) |

Use `]q` / `[q` to walk the hunks.

When Claude finishes a turn, the review list and the notes refresh by themselves.

Claude sees the notes as coming "from pane <your nvim window's name>". Name
the window something clear, for example `review`.

Your own keymaps: `opts = { keymaps = false }`, then map the commands above.
To change the key prefix: `opts = { prefix = "<leader>c" }`.

Statusline: `require("tuios-nvim").statusline()` returns `💬 3` when 3 notes are unsent.

## Test

```sh
tests/smoke.sh   # runs a throwaway tuios daemon and a fake Claude, then checks every feature
```

## Credits

Inspired by [herdr-nvim](https://github.com/ChmaraX/herdr-nvim) by Adam Chmara,
which does the same job for the [herdr](https://herdr.dev) multiplexer. The
idea and the look of the notes (a bar in the sign column, a tinted line and the
note above it) come from there.

## License

MIT

