-- Talks to the tuios daemon.
-- Every request is one `tuios call <verb> <json>` and its JSON reply.
local M = {}

-- The tuios session nvim runs in.
function M.session()
  return vim.env.TUIOS_SESSION
end

-- Runs one tuios verb and returns its reply as a Lua table.
-- On failure it returns nil and an error message instead.
function M.call(verb, params)
  local command = { "tuios", "call", verb, vim.json.encode(params) }
  local result = vim.system(command, { text = true }):wait()

  -- Decode JSON null as Lua nil, so `if reply.notes then` does what it says.
  local ok, reply = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
  if not ok or type(reply) ~= "table" then
    local message = vim.trim(result.stderr or "")
    if message == "" then
      message = "tuios " .. verb .. " failed with exit code " .. result.code
    end
    return nil, message
  end

  if reply.error then
    return nil, reply.error.message or reply.error.code
  end

  return reply
end

return M
