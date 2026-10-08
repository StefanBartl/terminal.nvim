---@module 'terminal.core.context'
--- What a terminal is *for*: the project root it belongs to and the name it gets.
---
--- The editor is read through an injected `deps` table so the decisions are testable without
--- one; `from_editor()` builds the real thing.

local M = {}

---@class Terminal.ContextDeps
---@field cwd fun(): string Current working directory, spelled the way the user is in it
---@field bufname fun(): string Name of the current buffer ("" when none)
---@field root fun(path: string): string|nil Project root for a path, spelled like the path (nil = none found)
---@field key? fun(path: string): string The canonical form of a directory, for the registry id (default: as given)

--- The canonical spelling of a directory, so that one project has ONE registry key: the real path
--- (8.3 short names and symlinks resolved), forward slashes, an upper-case drive letter.
--- `getcwd()` keeps the spelling it was changed with while a file buffer's name arrives in the long
--- form; without this a terminal toggled from a terminal buffer would not find itself again.
--- Only the KEY is canonical: the shell starts in the directory the user is in, spelled as the
--- user spelled it (a junction or symlink stays what `:pwd` shows).
---@param path string
---@return string
local function canonical(path)
  local key = require("lib.nvim.fs.normkey")(path)
  return key ~= "" and key or path
end

--- The deps backed by the running editor.
---@return Terminal.ContextDeps
function M.from_editor()
  return {
    cwd = function()
      return vim.fn.getcwd()
    end,
    bufname = function()
      return vim.api.nvim_buf_get_name(0)
    end,
    root = function(path)
      local start = path ~= "" and path or vim.fn.getcwd()
      return vim.fs.root(start, { ".git" })
    end,
    key = canonical,
  }
end

---@internal
---@param p string
---@return string
local function normalize(p)
  local out = vim.fs.normalize(p):gsub("/+$", "")
  -- A filesystem root loses its only slash above: "/" -> "", "C:/" -> "C:" (a drive-relative path).
  if out == "" then
    return "/"
  elseif out:find("^%a:$") then
    return out .. "/"
  end
  return out
end

--- Directory a new terminal starts in, and the root that identifies its project.
---
--- `mode`: "project" = the git root of the current buffer (else the cwd), "buffer" = the
--- directory of the current buffer (else the cwd), "cwd" = the cwd. The first result is where
--- the shell starts (spelled as the user is in it); the second is the project's registry key
--- (canonical, the same for every spelling of the directory).
---@param mode Terminal.CwdMode
---@param deps Terminal.ContextDeps
---@return string cwd
---@return string root
function M.resolve(mode, deps)
  local cwd = normalize(deps.cwd())
  local bufname = deps.bufname()
  local buf_dir = nil
  if bufname ~= "" and not bufname:find("^%a[%w+.-]*://") then
    buf_dir = normalize(vim.fs.dirname(bufname))
  end

  local project = deps.root(buf_dir or cwd)
  local top = normalize(project or cwd)
  local root = deps.key and normalize(deps.key(top)) or top

  if mode == "cwd" then
    return cwd, root
  elseif mode == "buffer" then
    return buf_dir or cwd, root
  end
  return top, root
end

--- The name a terminal gets when the caller gave none: the configured default for no count,
--- the count itself otherwise (`3<A-h>` -> terminal "3"). "No count" is `nil` or `0` (what
--- `vim.v.count` is without one); anything else that is not a number from 1 up is a mistake of
--- the caller and is reported, not read as "no count".
---@param count integer|nil
---@param default_name string
---@return string|nil name
---@return string|nil err
function M.name_for_count(count, default_name)
  if count == nil or count == 0 then
    return default_name, nil
  end
  if type(count) == "number" and count >= 1 and count < math.huge then
    return tostring(math.floor(count)), nil
  end
  return nil,
    ("count must be a number from 1 up (0 or nil: the default terminal), got %s"):format(
      tostring(count)
    )
end

return M
