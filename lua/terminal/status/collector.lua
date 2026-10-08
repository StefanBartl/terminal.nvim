---@module 'terminal.status.collector'
--- Reads the running editor into a `Terminal.StatusSnapshot` -- the only place the status code
--- touches editor state. Every read is cheap (no shelling out, no scanning) because this runs on
--- every mode change, buffer switch and diagnostic update.

local M = {}

---@internal
--- Most directories (and repositories) remembered; a long session visits many.
local MAX_REMEMBERED = 64

---@internal
--- Directory -> its repository's `.git/HEAD`. The root walk is the part of a lookup that costs
--- something; the answer only changes when a repository appears or disappears, which the `HEAD`
--- stat below notices.
---@type table<string, string>
local head_paths = {}

---@class Terminal.HeadRead
---@field sec integer mtime of the file when it was read
---@field nsec integer
---@field size integer
---@field value string|false The branch, false when `HEAD` names none

---@internal
--- What was read from each `HEAD`, valid while the file's mtime and size stay the same. A status
--- update can fire several times a second (mode changes, buffer switches); the stat is far
--- cheaper than the read, and unlike a timer it never serves a branch from before a switch.
---@type table<string, Terminal.HeadRead>
local heads = {}

---@internal
--- The branch named by a `HEAD` file: `ref: refs/heads/<name>`, or the short hash when detached.
---@param path string
---@return string|false
local function parse_head(path)
  local f = io.open(path, "r")
  if not f then
    return false
  end
  local line = f:read("*l") or ""
  f:close()
  local ref = line:match("^ref:%s*refs/heads/(.+)$")
  if ref then
    return ref
  end
  return line:match("^%x%x%x%x%x%x%x") and line:sub(1, 7) or false
end

---@internal
--- The `HEAD` file of the repository that contains `dir`, nil outside one. A worktree or
--- submodule has a `.git` *file*, not a directory: its HEAD is not here, the branch is unknown.
---@param dir string
---@return string|nil
local function head_path(dir)
  local known = head_paths[dir]
  if known then
    return known
  end
  local root = vim.fs.root(dir ~= "" and dir or vim.fn.getcwd(), ".git")
  if not root then
    return nil
  end
  if vim.tbl_count(head_paths) >= MAX_REMEMBERED then
    head_paths = {}
    heads = {}
  end
  head_paths[dir] = root .. "/.git/HEAD"
  return head_paths[dir]
end

---@internal
--- Branch of the repository that contains `dir`: from gitsigns when the current buffer already has
--- it, else from `.git/HEAD`.
---
--- The gitsigns variables belong to the *current buffer*, not to `dir`, so they are read before
--- anything is cached -- a cache keyed by directory would hand one buffer's answer to another.
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
  local path = head_path(dir)
  if not path then
    return nil
  end
  local st = vim.uv.fs_stat(path)
  if not st then
    head_paths[dir] = nil -- the repository is gone, or `.git` is a file (worktree)
    heads[path] = nil
    return nil
  end
  local read = heads[path]
  if read and read.sec == st.mtime.sec and read.nsec == st.mtime.nsec and read.size == st.size then
    return read.value or nil
  end
  local value = parse_head(path)
  heads[path] = { sec = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, value = value }
  return value or nil
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
