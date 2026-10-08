---@module 'terminal.config'
--- Runtime configuration store for terminal.nvim.
---
--- Deep-merges user options over `terminal.config.DEFAULTS` and exposes a single
--- `get(path)` accessor (dot-separated path) so no other module reads a raw options table.
--- `validate` is pure: it returns the problems it found and never notifies, so it is
--- testable without a UI; `setup` reports them (deferred, see the comment there).
---@see terminal.config.DEFAULTS

local DEFAULTS = require("terminal.config.DEFAULTS")
local lib_config = require("lib.lua.config")
local notify = require("terminal.notify")

local M = {}

-- A deep copy, not DEFAULTS itself: `M.options` is public, a write through it before `setup()`
-- must not corrupt DEFAULTS for the rest of the session.
---@type Terminal.Config
M.options = vim.deepcopy(DEFAULTS)

--- What the last `setup()` found wrong with the options (so `:checkhealth` can show it after the
--- notification is gone). Empty before `setup()` ran.
---@type string[]
M.problems = {}

---@internal
--- Keys whose value must be one of a closed set. Dot-path -> allowed values.
---@type table<string, string[]>
local ENUMS = {
  backend = { "auto", "native", "wezterm", "tmux" },
  layout = require("terminal.backends").LAYOUTS,
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
  ["status.export"] = { "string", "table", "boolean" },
  ["navigate.handoff"] = { "string", "table", "boolean" },
}

---@internal
--- Tables whose own keys are the user's (not part of the schema): not descended into.
--- `keymaps` is checked by `lib.nvim.bindings.keymap.register`, which names a wrong action.
---@type table<string, true>
local OPEN_TABLES = { env = true, keymaps = true }

---@internal
--- Lists of autocommand event names: every entry must be an event Neovim knows. A bad name would
--- otherwise raise from `nvim_create_autocmd` in the middle of `setup()`.
---@type table<string, true>
local EVENT_LISTS = { ["auto_insert.events"] = true }

---@internal
--- A real, finite number (NaN and infinity pass `type(v) == "number"`).
---@param v any
---@return boolean
local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---@internal
---@param v number
---@return boolean
local function whole(v)
  return v % 1 == 0
end

---@internal
--- The border styles `nvim_open_win` and 'winborder' know by name (`:h nvim_open_win()`; `bold`
--- is not in every version of that list, but both accept it).
local BORDER_NAMES = { "none", "single", "double", "rounded", "solid", "shadow", "bold" }

---@internal
--- Keys whose value, once it has the right type, must also be in a range. A value that only
--- passes the type check would be quietly replaced by a fallback deep inside the code that uses
--- it (`layout.resolve_size`), so a typo in a size would never be reported.
---@type table<string, { ok: (fun(v: any): boolean), want: string }>
local DOMAINS = {
  ["float.width"] = {
    ok = function(v)
      return finite(v) and v > 0
    end,
    want = "a number above 0 (a fraction up to 1, or a count of cells)",
  },
  ["float.height"] = {
    ok = function(v)
      return finite(v) and v > 0
    end,
    want = "a number above 0 (a fraction up to 1, or a count of cells)",
  },
  ["split.size"] = {
    ok = function(v)
      return finite(v) and v > 0
    end,
    want = "a number above 0 (a fraction up to 1, or a count of cells)",
  },
  ["float.winblend"] = {
    ok = function(v)
      return finite(v) and whole(v) and v >= 0 and v <= 100
    end,
    want = "a whole number from 0 to 100",
  },
  ["float.zindex"] = {
    ok = function(v)
      return finite(v) and whole(v) and v >= 1
    end,
    want = "a whole number from 1 up",
  },
  ["status.debounce_ms"] = {
    ok = function(v)
      return finite(v) and v >= 0
    end,
    want = "a number of milliseconds from 0 up",
  },
  ["status.max_bytes"] = {
    ok = function(v)
      return finite(v) and whole(v) and v >= 1
    end,
    want = "a whole number of bytes from 1 up",
  },
  ["default_name"] = {
    ok = function(v)
      return v ~= ""
    end,
    want = "a non-empty name",
  },
  ["run.name"] = {
    ok = function(v)
      return v ~= ""
    end,
    want = "a non-empty name",
  },
}
DOMAINS["float.border"] = {
  ok = function(v)
    if type(v) == "string" then
      return v == "" or vim.list_contains(BORDER_NAMES, v)
    end
    -- A custom border: 1, 2, 4 or 8 pieces (`:h nvim_open_win()` border).
    local n = #v
    return n == 1 or n == 2 or n == 4 or n == 8
  end,
  want = "a border name ("
    .. table.concat(BORDER_NAMES, ", ")
    .. ") or a list of 1, 2, 4 or 8 pieces",
}
DOMAINS["window_options.signcolumn"] = {
  ok = function(v)
    local kind, rest = v:match("^(%a+)(.*)$")
    if kind == "no" or kind == "number" then
      return rest == ""
    elseif kind == "yes" then
      return rest == "" or rest:find("^:[1-9]$") ~= nil
    elseif kind == "auto" then
      if rest == "" or rest:find("^:[1-9]$") ~= nil then
        return true
      end
      -- `auto:N-M` takes a minimum below its maximum: 'signcolumn' answers E474 to `auto:3-2`
      -- and to `auto:2-2`, and the TermOpen autocommand that sets it would abort with it.
      -- (One digit each, so the strings compare like the numbers.)
      local low, high = rest:match("^:([1-9])%-([1-9])$")
      return low ~= nil and low < high
    end
    return false
  end,
  want = "yes, no, auto, number, yes:N, auto:N or auto:N-M (N below M; digits 1 to 9)",
}
for _, key in ipairs({ "enter_padding", "enter_margin", "leave_padding", "leave_margin" }) do
  DOMAINS["kitty." .. key] = {
    ok = function(v)
      return finite(v) and whole(v) and v >= 0
    end,
    want = "a whole number of cells from 0 up",
  }
end

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
    elseif EVENT_LISTS[path] then
      if type(v) ~= "table" then
        problems[#problems + 1] = ("config key '%s' should be a list of event names, got %s"):format(
          path,
          type(v)
        )
      else
        local events = {}
        for _, ev in ipairs(v) do
          -- `exists("##<name>")` also says yes to "TermOpen,TermClose" or "TermOpen " (a valid
          -- name followed by a separator), which `nvim_create_autocmd` rejects: names are letters.
          if type(ev) == "string" and ev:find("^%a+$") and vim.fn.exists("##" .. ev) == 1 then
            events[#events + 1] = ev
          else
            problems[#problems + 1] = ("config key '%s': %s is not an autocommand event -- ignored"):format(
              path,
              vim.inspect(ev)
            )
          end
        end
        -- Nothing valid left: the key is dropped and the default list applies.
        if #events > 0 then
          clean[k] = events
        end
      end
    elseif OPEN_TABLES[path] then
      if type(v) == "table" then
        -- An empty table means "no overrides": merged over the defaults it would replace them
        -- (see the section branch below).
        if next(v) ~= nil then
          clean[k] = v
        end
      elseif path == "keymaps" and v == false then
        clean[k] = v
      else
        problems[#problems + 1] = ("config key '%s' should be a table, got %s"):format(
          path,
          type(v)
        )
      end
    elseif WIDE_TYPES[path] then
      local domain = DOMAINS[path]
      if contains(WIDE_TYPES[path], type(v)) and domain and not domain.ok(v) then
        problems[#problems + 1] = ("config key '%s' must be %s, got %s"):format(
          path,
          domain.want,
          vim.inspect(v)
        )
      elseif contains(WIDE_TYPES[path], type(v)) then
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
        -- A section whose every key was dropped (or that was empty) must not reach the merge:
        -- `lib.lua.config.deep_merge` takes an empty table for an empty *list* and would replace
        -- the whole default section with it.
        if next(sub_clean) ~= nil then
          clean[k] = sub_clean
        end
      else
        problems[#problems + 1] = ("config key '%s' should be a table, got %s"):format(
          path,
          type(v)
        )
      end
    elseif type(v) == type(default_v) then
      local domain = DOMAINS[path]
      if domain and not domain.ok(v) then
        problems[#problems + 1] = ("config key '%s' must be %s, got %s"):format(
          path,
          domain.want,
          vim.inspect(v)
        )
      else
        clean[k] = v
      end
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
---@param opts Terminal.Options|nil
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
  -- Liberal in, canonical out: `true` means "auto" for the two keys that choose among
  -- environments, so nothing downstream has to know the spelling.
  if M.options.status.export == true then
    M.options.status.export = "auto"
  end
  if M.options.navigate.handoff == true then
    M.options.navigate.handoff = "auto"
  end
  M.problems = problems
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

--- The configured shell as a job command: nil = the editor's 'shell'.
---@return string|string[]|nil
function M.shell_command()
  local shell = M.options.shell
  if type(shell) == "table" then
    return #shell > 0 and vim.deepcopy(shell) or nil
  end
  if type(shell) == "string" and shell ~= "" then
    return shell
  end
  return nil
end

--- The executable of the shell terminals run -- the configured one, else Neovim's 'shell' --
--- for decisions that depend on the kind of shell (quoting, `cls` or `clear`).
---@return string
function M.shell_executable()
  local cmd = M.shell_command()
  if type(cmd) == "table" then
    return cmd[1]
  end
  return cmd or vim.o.shell
end

--- A deep-copied snapshot of the whole resolved config.
---@return Terminal.Config
function M.get_all()
  return vim.deepcopy(M.options)
end

return M
