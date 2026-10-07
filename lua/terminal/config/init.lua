---@module 'terminal.config'
--- Runtime configuration store for terminal.nvim.
---
--- Deep-merges user options over `terminal.config.DEFAULTS` and exposes a single
--- `get(path)` accessor (dot-separated path) so no other module reads a raw options table.
--- `validate` is pure: it returns the problems it found and never notifies, so it is
--- testable without a UI; `setup` reports them (deferred, see the comment there).

local DEFAULTS = require("terminal.config.DEFAULTS")
local lib_config = require("lib.lua.config")
local notify = require("lib.nvim.notify").create("[terminal]")

local M = {}

-- A deep copy, not DEFAULTS itself: `M.options` is public, a write through it before `setup()`
-- must not corrupt DEFAULTS for the rest of the session.
---@type Terminal.Config
M.options = vim.deepcopy(DEFAULTS)

---@internal
--- Keys whose value must be one of a closed set. Dot-path -> allowed values.
---@type table<string, string[]>
local ENUMS = {
  backend = { "auto", "native", "wezterm", "tmux" },
  layout = { "float", "split", "vsplit", "tab" },
  cwd = { "project", "buffer", "cwd" },
  on_exit = { "close", "close_on_success", "keep" },
  ["float.title_pos"] = { "left", "center", "right" },
}

---@internal
--- Keys that accept more than the type of their default: dot-path -> accepted Lua types.
---@type table<string, string[]>
local WIDE_TYPES = {
  shell = { "string", "table" },
  ["float.border"] = { "string", "table" },
}

---@internal
--- Tables whose own keys are the user's (not part of the schema): not descended into.
--- `keymaps` is checked by `lib.nvim.bindings.keymap.register`, which names a wrong action.
---@type table<string, true>
local OPEN_TABLES = { env = true, keymaps = true }

---@internal
---@param list string[]
---@param value any
---@return boolean
local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

--- Find every key in `opts` that `schema` does not know, whose type is wrong, or whose value is
--- outside its closed set. Pure. The second result is `opts` without every offending key, ready
--- to merge over the defaults.
---@param schema table DEFAULTS or one of its nested tables
---@param opts table The corresponding level of the user's options
---@param prefix? string Dot-path so far
---@return string[] problems
---@return table clean
function M.validate(schema, opts, prefix)
  prefix = prefix or ""
  local problems = {}
  local clean = {}
  for k, v in pairs(opts) do
    local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
    local default_v = schema[k]
    if default_v == nil then
      problems[#problems + 1] = ("unknown config key '%s' -- ignored"):format(path)
    elseif ENUMS[path] then
      if contains(ENUMS[path], v) then
        clean[k] = v
      else
        problems[#problems + 1] = ("config key '%s' must be one of %s, got %s"):format(
          path,
          table.concat(ENUMS[path], "|"),
          vim.inspect(v)
        )
      end
    elseif OPEN_TABLES[path] then
      if type(v) == "table" or (path == "keymaps" and v == false) then
        clean[k] = v
      else
        problems[#problems + 1] = ("config key '%s' should be a table, got %s"):format(
          path,
          type(v)
        )
      end
    elseif WIDE_TYPES[path] then
      if contains(WIDE_TYPES[path], type(v)) then
        clean[k] = v
      else
        problems[#problems + 1] = ("config key '%s' should be %s, got %s"):format(
          path,
          table.concat(WIDE_TYPES[path], " or "),
          type(v)
        )
      end
    elseif type(default_v) == "table" and not vim.islist(default_v) then
      if type(v) == "table" then
        local sub_problems, sub_clean = M.validate(default_v, v, path)
        vim.list_extend(problems, sub_problems)
        clean[k] = sub_clean
      else
        problems[#problems + 1] = ("config key '%s' should be a table, got %s"):format(
          path,
          type(v)
        )
      end
    elseif type(v) == type(default_v) then
      clean[k] = v
    else
      problems[#problems + 1] = ("config key '%s' should be %s, got %s"):format(
        path,
        type(default_v),
        type(v)
      )
    end
  end
  table.sort(problems)
  return problems, clean
end

--- Apply user options. A value that fails validation is reported and the default stays.
---
--- `deep_merge` copies `base` one level at a time, so untouched sub-tables of the result would
--- alias DEFAULTS again; `vim.deepcopy` severs that.
---@param opts Terminal.Config|table|nil
---@return string[] problems
function M.setup(opts)
  local problems = {}
  local merged_opts = {}
  if type(opts) == "table" then
    problems, merged_opts = M.validate(DEFAULTS, opts)
  elseif opts ~= nil then
    problems = { ("setup() expects a table, got %s"):format(type(opts)) }
  end

  -- Offending keys were dropped by `validate`, so a typo keeps that key's default.
  M.options = vim.deepcopy(lib_config.deep_merge(DEFAULTS, merged_opts))
  if #problems > 0 then
    -- Deferred: `setup()` can run during plugin load, before notifying is safe.
    vim.schedule(function()
      for _, p in ipairs(problems) do
        notify.warn(p)
      end
    end)
  end
  return problems
end

--- Read a value by dot-path, e.g. `get("float.width")`. A table result is a deep copy, never a
--- live reference into `M.options`.
---@param path string
---@return any
function M.get(path)
  local v = lib_config.get(M.options, path)
  if type(v) == "table" then
    return vim.deepcopy(v)
  end
  return v
end

--- A deep-copied snapshot of the whole resolved config.
---@return Terminal.Config
function M.get_all()
  return vim.deepcopy(M.options)
end

return M
