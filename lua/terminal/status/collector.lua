---@module 'terminal.status.collector'
--- Reads the running editor into a `Terminal.StatusSnapshot` -- the only place the status code
--- touches editor state. Every read is cheap (no shelling out, no scanning) because this runs on
--- every mode change, buffer switch and diagnostic update.
---@see terminal.core.status

local M = {}

---@internal
--- Most directories (and repositories) remembered; a long session visits many.
local MAX_REMEMBERED = 64

---@internal
--- How long an answer of the root walk is believed, in milliseconds. The walk is the part of a
--- lookup that costs something (it climbs to the filesystem root when there is no repository);
--- the answer changes when a repository appears *between* a directory and the one that was
--- found before (a `git init` or clone below a repository that is already known), which no stat
--- of the old `HEAD` can notice -- so it is asked again after this long.
local MEMO_MS = 2000

---@class Terminal.HeadMemo
---@field path string|false The `.git/HEAD` of the repository that contains the directory; false: there is none (no repository, or its `.git` is a file)
---@field at number `now_ms()` when the walk was made

---@internal
--- Directory -> the answer of its last root walk, positive or negative: a directory outside any
--- repository would otherwise be walked on every status event.
---@type table<string, Terminal.HeadMemo>
local head_paths = {}

---@internal
--- A monotonic clock in milliseconds. `vim.uv.now()` is only refreshed once per event-loop turn,
--- which a script that never yields would see standing still.
---@return number
local function now_ms()
  return vim.uv.hrtime() / 1e6
end

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
--- The answer, "none" included, is reused for `MEMO_MS`; what the file holds is read fresh (and
--- cheaply) by `branch_of` on every call.
---@param dir string
---@return string|nil
local function head_path(dir)
  local now = now_ms()
  local known = head_paths[dir]
  if known and now - known.at < MEMO_MS then
    return known.path or nil
  end
  local root = vim.fs.root(dir ~= "" and dir or vim.fn.getcwd(), ".git")
  if known == nil and vim.tbl_count(head_paths) >= MAX_REMEMBERED then
    head_paths = {}
    heads = {}
  end
  head_paths[dir] = { path = root and (root .. "/.git/HEAD") or false, at = now }
  return head_paths[dir].path or nil
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
    -- the repository is gone, or `.git` is a file (worktree): "none" until the walk is redone
    head_paths[dir].path = false
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
---@return Terminal.DiagCounts
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

---@internal
--- The directory the branch is looked up from: the directory of the buffer's file, or the working
--- directory for a buffer that is not a file on disk. The name of a terminal, `oil://` or
--- `fugitive://` buffer is a label, not a path: it would be resolved against whatever directory
--- Neovim is in *at the time of the walk*, while the memo files the answer under the name alone --
--- after a `:cd` the old repository's branch would stay. The working directory is the key that
--- follows the `:cd` (the same reading `terminal.core.context` makes).
---@param buf integer
---@param name string The buffer's name
---@return string
local function lookup_dir(buf, name)
  if name == "" or name:find("^%a[%w+.-]*://") or vim.bo[buf].buftype ~= "" then
    return vim.fn.getcwd()
  end
  return vim.fs.dirname(name)
end

--- The current state of the editor.
---@return Terminal.StatusSnapshot
function M.snapshot()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local dir = lookup_dir(buf, name)
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
