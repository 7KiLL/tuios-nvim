-- Finds the Claude Code pane whose changes we review.
local tuios = require("tuios-nvim.tuios")
local git = require("tuios-nvim.git")

local M = {}

-- The agent the user picked. Reused until that pane goes away.
local chosen_agent = nil

-- Every Claude Code agent in this tuios session.
local function list_claude_agents()
  local reply, err = tuios.call("list-agents", { session = tuios.session() })
  if not reply then
    return nil, err
  end

  local agents = {}
  for _, agent in ipairs(reply.agents or {}) do
    if agent.harness_id == "claude-code" then
      table.insert(agents, agent)
    end
  end
  return agents
end

-- The agents working in the same git repository as nvim.
local function agents_in_this_repo(agents)
  local repo_root = git.root(vim.fn.getcwd())
  if not repo_root then
    return {}
  end

  local matches = {}
  for _, agent in ipairs(agents) do
    if agent.cwd == repo_root or git.relative(agent.cwd, repo_root) then
      table.insert(matches, agent)
    end
  end
  return matches
end

local function find_by_window(agents, window_id)
  for _, agent in ipairs(agents) do
    if agent.window_id == window_id then
      return agent
    end
  end
  return nil
end

-- Returns the agent when the choice is obvious, without asking:
-- the agent picked before, else the only Claude in this repo,
-- else the only Claude in the session. Returns nil when it is not obvious.
function M.find_without_asking()
  local agents = list_claude_agents()
  if not agents then
    return nil
  end

  if chosen_agent then
    local still_there = find_by_window(agents, chosen_agent.window_id)
    if still_there then
      chosen_agent = still_there
      return chosen_agent
    end
    chosen_agent = nil
  end

  local in_repo = agents_in_this_repo(agents)
  if #in_repo == 1 then
    return in_repo[1]
  end
  if #in_repo == 0 and #agents == 1 then
    return agents[1]
  end
  return nil
end

local function describe(agent)
  return string.format("%s · %s · %s", agent.name or "Claude Code", agent.state, vim.fn.fnamemodify(agent.cwd, ":~"))
end

-- Asks the user to pick one of the Claude agents, then calls on_agent(agent).
function M.ask(on_agent)
  local agents, err = list_claude_agents()
  if not agents then
    vim.notify("tuios-nvim: " .. err, vim.log.levels.ERROR)
    return
  end
  if #agents == 0 then
    vim.notify("tuios-nvim: no Claude Code pane in this tuios session", vim.log.levels.WARN)
    return
  end

  vim.ui.select(agents, { prompt = "Review which Claude?", format_item = describe }, function(agent)
    if agent then
      chosen_agent = agent
      on_agent(agent)
    end
  end)
end

-- Calls on_agent(agent) with the agent to review. Asks only when it is not obvious.
function M.pick(on_agent)
  local agent = M.find_without_asking()
  if agent then
    chosen_agent = agent
    on_agent(agent)
    return
  end
  M.ask(on_agent)
end

return M
