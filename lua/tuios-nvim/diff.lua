-- Shows the current file next to its old version, with nvim's built-in diff mode.
local review = require("tuios-nvim.review")
local git = require("tuios-nvim.git")

local M = {}

-- The window showing an old version, if one is open in this tab.
local function find_old_version_window()
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buffer = vim.api.nvim_win_get_buf(window)
    if vim.b[buffer].tuios_old_version then
      return window
    end
  end
  return nil
end

local function close(old_window)
  vim.api.nvim_win_close(old_window, true)
  vim.cmd("diffoff!")
end

local function open()
  if not review.current then
    vim.notify("tuios-nvim: open a review first (:TuiosReview)", vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  local path = git.relative(file, review.current.root)
  if not path then
    vim.notify("tuios-nvim: this file is not in the reviewed repository", vim.log.levels.WARN)
    return
  end

  local old_lines = git.show(review.current.root, review.current.base, path)
  local filetype = vim.bo.filetype

  vim.cmd("diffthis")
  vim.cmd("leftabove vnew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, old_lines)
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.modifiable = false
  vim.bo.filetype = filetype
  vim.b.tuios_old_version = true
  vim.api.nvim_buf_set_name(0, "old: " .. path)
  vim.cmd("diffthis")

  -- Go back to the real file, so the cursor stays where the user was working.
  vim.cmd("wincmd p")
end

-- Opens the old version beside the current file, or closes it if open.
function M.toggle()
  local old_window = find_old_version_window()
  if old_window then
    close(old_window)
  else
    open()
  end
end

return M
