---@module 'terminal.status.collector'
--- Reads the running editor into a `Terminal.StatusSnapshot` -- the only place the status code
--- touches editor state. Every read is cheap (no shelling out, no scanning) because this runs on
--- every mode change, buffer switch and diagnostic update.

local M = {}

---@internal
--- Branch of the repository that contains `dir`: from gitsigns when it already knows, else by
--- reading `.git/HEAD` (one small file). A detached HEAD gives the short hash.
---@param dir string
---@return string|nil
local function branch_of(dir)
  local head = vim.b.gitsigns_head
  if type(head) == "string" and head ~= "" then
    return head
  end
  local dict = vim.b.gitsigns_status_dict
  if type(dict) == "table" and type(dict.head) == "string" and dict.head ~= "" then
    return dict.head
  end
  local root = vim.fs.root(dir ~= "" and dir or vim.fn.getcwd(), ".git")
  if not root then
    return nil
  end
  local f = io.open(root .. "/.git/HEAD", "r")
  if not f then
    return nil -- a worktree/submodule has a `.git` file, not a directory: unknown here
  end
  local line = f:read("*l") or ""
  f:close()
  local ref = line:match("^ref:%s*refs/heads/(.+)$")
  if ref then
    return ref
  end
  return line:match("^%x%x%x%x%x%x%x") and line:sub(1, 7) or nil
end

---@internal
---@return { error: integer, warn: integer, info: integer, hint: integer }
local function diagnostics()
  local counts = vim.diagnostic.count(0)
  local S = vim.diagnostic.severity
  return {
    error = counts[S.ERROR] or 0,
    warn = counts[S.WARN] or 0,
    info = counts[S.INFO] or 0,
    hint = counts[S.HINT] or 0,
  }
end

--- The current state of the editor.
---@return Terminal.StatusSnapshot
function M.snapshot()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  return {
    mode = vim.api.nvim_get_mode().mode,
    file = name,
    buftype = vim.bo[buf].buftype,
    cwd = vim.fn.getcwd(),
    branch = branch_of(dir),
    diag = diagnostics(),
    recording = vim.fn.reg_recording(),
    modified = vim.bo[buf].modified,
    filetype = vim.bo[buf].filetype,
    pid = vim.fn.getpid(),
  }
end

return M
