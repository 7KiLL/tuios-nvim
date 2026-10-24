-- Accepts the agent's changes by staging them in git (only the index changes).
local tuios = require("tuios-nvim.tuios")
local agent = require("tuios-nvim.agent")
local git = require("tuios-nvim.git")

local M = {}

-- What tuios returned for the last stage, so it can be undone.
local last_undo = nil

-- The current buffer's path inside its repository, or nil with a warning.
local function current_path()
  local filename = vim.api.nvim_buf_get_name(0)
  local root = git.root(filename)
  if filename == "" or not root then
    vim.notify("tuios-nvim: this buffer is not a file in a git repository", vim.log.levels.WARN)
    return nil
  end
  return git.relative(filename, root)
end

-- The unstaged hunk of `path` that holds `line`, or nil.
local function find_hunk(the_agent, path, line)
  local reply, err = tuios.call("review-diff", {
    session = tuios.session(),
    window = the_agent.window_id,
    index = "unstaged",
    paths = { path },
  })
  if not reply then
    return nil, err
  end

  for _, file in ipairs(reply.files or {}) do
    for _, hunk in ipairs(file.hunks or {}) do
      local last_line = hunk.new_start + math.max(hunk.new_lines, 1) - 1
      if line >= hunk.new_start and line <= last_line then
        return hunk
      end
    end
  end
  return nil, "no unstaged change on this line"
end

local function run_stage(the_agent, params)
  params.session = tuios.session()
  params.window = the_agent.window_id
  local reply, err = tuios.call("review-stage", params)
  if not reply then
    vim.notify("tuios-nvim: " .. err, vim.log.levels.ERROR)
    return
  end
  last_undo = reply.undo
  vim.notify("tuios-nvim: staged " .. params.path)
end

-- Stages the hunk under the cursor.
function M.stage_hunk()
  local path = current_path()
  if not path then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]

  agent.pick(function(the_agent)
    local hunk, err = find_hunk(the_agent, path, line)
    if not hunk then
      vim.notify("tuios-nvim: " .. err, vim.log.levels.WARN)
      return
    end
    run_stage(the_agent, { action = "stage", path = path, hunk = hunk.header })
  end)
end

-- Stages the whole current file.
function M.stage_file()
  local path = current_path()
  if not path then
    return
  end
  agent.pick(function(the_agent)
    run_stage(the_agent, { action = "stage", path = path })
  end)
end

-- Undoes the last stage.
function M.undo()
  if not last_undo then
    vim.notify("tuios-nvim: nothing to undo", vim.log.levels.INFO)
    return
  end
  agent.pick(function(the_agent)
    local _, err = tuios.call("review-stage", {
      action = "undo",
      session = tuios.session(),
      window = the_agent.window_id,
      undo = last_undo,
    })
    if err then
      vim.notify("tuios-nvim: " .. err, vim.log.levels.ERROR)
      return
    end
    last_undo = nil
    vim.notify("tuios-nvim: stage undone")
  end)
end

return M
