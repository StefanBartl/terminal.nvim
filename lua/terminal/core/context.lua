---@module 'terminal.core.context'
--- What a terminal is *for*: the project root it belongs to and the name it gets.
---
--- The editor is read through an injected `deps` table so the decisions are testable without
--- one; `from_editor()` builds the real thing.

local M = {}

---@class Terminal.ContextDeps
---@field cwd fun(): string Current working directory
---@field bufname fun(): string Name of the current buffer ("" when none)
---@field root fun(path: string): string|nil Project root for a path (nil = none found)

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
--- directory of the current buffer (else the cwd), "cwd" = the cwd.
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
  local root = normalize(project or cwd)

  if mode == "cwd" then
    return cwd, root
  elseif mode == "buffer" then
    return buf_dir or cwd, root
  end
  return root, root
end

--- The name a terminal gets when the caller gave none: the configured default for no count,
--- the count itself otherwise (`3<A-h>` -> terminal "3").
---@param count integer|nil
---@param default_name string
---@return string
function M.name_for_count(count, default_name)
  if type(count) == "number" and count > 0 then
    return tostring(math.floor(count))
  end
  return default_name
end

return M
