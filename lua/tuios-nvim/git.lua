-- Small git helpers.
local M = {}

-- The root folder of the git repository that holds `path`, or nil.
function M.root(path)
  local folder = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  local result = vim.system({ "git", "-C", folder, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout)
end

-- `path` relative to `root`, for example "lua/foo.lua".
-- Returns nil when the path is not inside root.
function M.relative(path, root)
  local prefix = root .. "/"
  if path:sub(1, #prefix) ~= prefix then
    return nil
  end
  return path:sub(#prefix + 1)
end

-- The lines of `path` as it was at `revision`.
-- Returns an empty list when the file did not exist there (a new file).
function M.show(root, revision, path)
  local result = vim.system({ "git", "-C", root, "show", revision .. ":" .. path }, { text = true }):wait()
  if result.code ~= 0 then
    return {}
  end
  local lines = vim.split(result.stdout, "\n")
  -- git output ends with a newline, which leaves one empty string at the end.
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

return M
