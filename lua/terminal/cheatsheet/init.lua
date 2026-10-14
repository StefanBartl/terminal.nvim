---@module 'terminal.cheatsheet'
--- Finds and loads the cheatsheet of a shell. The sheets are Markdown files, one per shell
--- (`docs/cheatsheets/<key>.md` in this plugin); the user adds or replaces some through
--- `cheatsheet.dir` (a folder searched first) and `cheatsheet.shells` (a file for a shell name).
---@see terminal.cheatsheet.detect
---@see terminal.cheatsheet.parse
---@see terminal.cheatsheet.ui

local detect = require("terminal.cheatsheet.detect")
local parse = require("terminal.cheatsheet.parse")

local M = {}

---@class Terminal.CheatOpts
---@field dir? string Folder with `<key>.md` files, searched before the built-in ones
---@field shells? table<string, string> Sheet file by shell key, searched before everything else

---@class Terminal.CheatSheet
---@field key string The sheet that was found (may differ from the one asked for)
---@field asked string The key that was asked for
---@field path string
---@field title? string
---@field sections Terminal.CheatSection[]

---@internal
--- The folder of the sheets that ship with the plugin, from the position of this file
--- (`<root>/lua/terminal/cheatsheet/init.lua`): independent of the runtimepath.
---@return string
local function builtin_dir()
  local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  local root = source:match("^(.*)/lua/terminal/cheatsheet/init%.lua$")
  return (root or ".") .. "/docs/cheatsheets"
end

---@internal
--- A key becomes part of a file name: letters, digits, `_` and `-` only, so a key can never name a
--- file outside the folders.
---@param key any
---@return boolean
local function valid_key(key)
  return type(key) == "string" and key:match("^[%w_%-]+$") ~= nil
end

---@internal
---@param path string
---@return boolean
local function readable(path)
  return vim.fn.filereadable(path) == 1
end

--- The files that can be the sheet `key`, best first: a file named in `opts.shells`,
--- `<opts.dir>/<key>.md`, the one that ships with the plugin. Only readable files.
---@param key string
---@param opts? Terminal.CheatOpts
---@return string[] paths
function M.paths(key, opts)
  local out = {}
  if not valid_key(key) then
    return out
  end
  opts = opts or {}
  local named = opts.shells and opts.shells[key]
  if type(named) == "string" and named ~= "" and readable(vim.fn.expand(named)) then
    out[#out + 1] = vim.fn.expand(named)
  end
  if type(opts.dir) == "string" and opts.dir ~= "" then
    local path = vim.fn.expand(opts.dir) .. "/" .. key .. ".md"
    if readable(path) then
      out[#out + 1] = path
    end
  end
  local path = builtin_dir() .. "/" .. key .. ".md"
  if readable(path) then
    out[#out + 1] = path
  end
  return out
end

--- The file of the sheet `key`: the first of `paths`. nil when there is none.
---@param key string
---@param opts? Terminal.CheatOpts
---@return string|nil path
function M.find(key, opts)
  return M.paths(key, opts)[1]
end

--- Load the sheet for `key`, or the closest related one (`zsh` -> `bash`) or `common`.
---@param key string
---@param opts? Terminal.CheatOpts
---@return Terminal.CheatSheet|nil sheet # nil only when not even `common` exists
---@return string|nil err
function M.load(key, opts)
  for _, candidate in ipairs(detect.candidates(valid_key(key) and key or detect.COMMON)) do
    -- A file that cannot be read or has no text falls back to the next file of the same shell (the
    -- user's empty `bash.md` shows the built-in sheet), then to the next shell.
    for _, path in ipairs(M.paths(candidate, opts)) do
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok then
        local parsed = parse.parse(table.concat(lines, "\n"))
        if #parsed.sections > 0 then
          return {
            key = candidate,
            asked = key,
            path = path,
            title = parsed.title,
            sections = parsed.sections,
          }
        end
      end
    end
  end
  return nil, ("no cheatsheet for '%s' (and no common one)"):format(tostring(key))
end

--- The keys that have a sheet right now: the built-in ones, the files in `opts.dir` and the names
--- in `opts.shells`. Sorted, each once.
---@param opts? Terminal.CheatOpts
---@return string[]
function M.names(opts)
  opts = opts or {}
  local seen = {}
  local function add_dir(dir)
    for _, file in ipairs(vim.fn.glob(dir .. "/*.md", false, true)) do
      local name = vim.fn.fnamemodify(file, ":t:r")
      if valid_key(name) then
        seen[name] = true
      end
    end
  end
  add_dir(builtin_dir())
  if type(opts.dir) == "string" and opts.dir ~= "" then
    add_dir(vim.fn.expand(opts.dir))
  end
  for name, path in pairs(opts.shells or {}) do
    if valid_key(name) and type(path) == "string" and path ~= "" then
      seen[name] = true
    end
  end
  local out = {}
  for name in pairs(seen) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

return M
