-- Listens for the agent finishing a turn, and refreshes the review when it does.
local tuios = require("tuios-nvim.tuios")
local agent = require("tuios-nvim.agent")

local M = {}

-- States that mean "the agent stopped working".
local TURN_ENDED = { done = true, idle = true, needs_input = true }

local job = nil

-- Called on the main loop for each event line printed by `tuios subscribe`.
local function handle_event(line, on_turn_end)
  local ok, event = pcall(vim.json.decode, line)
  if not ok or type(event) ~= "table" or event.type ~= "agent-state" then
    return
  end
  if not TURN_ENDED[event.state] then
    return
  end
  local the_agent = agent.find_without_asking()
  if the_agent and the_agent.window_id == event.window then
    on_turn_end()
  end
end

-- Starts listening. on_turn_end() runs each time the reviewed agent finishes a turn.
function M.start(on_turn_end)
  if job then
    return
  end

  -- stdout arrives in chunks, not lines. Keep the unfinished end of each chunk.
  local unfinished = ""
  local function on_stdout(_, chunk)
    if not chunk then
      return
    end
    local text = unfinished .. chunk
    local lines = vim.split(text, "\n")
    unfinished = table.remove(lines)
    for _, line in ipairs(lines) do
      vim.schedule(function()
        handle_event(line, on_turn_end)
      end)
    end
  end

  local command = { "tuios", "subscribe", "-s", tuios.session(), "--types", "agent-state" }
  job = vim.system(command, { text = true, stdout = on_stdout }, function()
    -- The stream ended, for example because the tuios daemon restarted.
    -- Try again in a few seconds.
    job = nil
    vim.defer_fn(function()
      M.start(on_turn_end)
    end, 5000)
  end)
end

return M
