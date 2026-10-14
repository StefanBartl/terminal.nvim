---@module 'terminal.sessions'
--- Terminals follow a session of sessions.nvim: the definitions (name, layout, directory and, for a
--- `run` with `direct`, the command) are written next to the session file when it is saved and
--- reopened when it is loaded. No process is saved: a reopened terminal is a fresh shell (or a fresh
--- start of the command), and it comes back hidden, so `toggle` shows it.
---
--- The coupling is `User` events and nothing else: sessions.nvim fires `SessionsSavePost` /
--- `SessionsLoadPost` (`ev.data = { name, path, tab }`), `SessionsRenamePost` (`{ old_name,
--- old_path, name, path }`) and `SessionsDeletePost` (`{ name, path }`), this module listens.
--- Neither plugin requires the other. Tab snapshots carry no terminals.
---
--- The sidecar `.<session>.terminals.json` sits beside the session file, like sessions.nvim's own
--- `.<session>.meta.json` and `.<session>.bufs.json`. Only the project's native terminals are
--- written: a multiplexer pane outlives Neovim and needs no restoring.
---@see terminal.pin

local M = {}

local GROUP = "terminal.sessions"

---@class Terminal.SessionDef
---@field name string
---@field layout Terminal.Layout
---@field cwd? string
---@field cmd? string[] The argv of a `run` with `direct`; nil: a shell

--- The facade functions this module needs; specs hand in a double.
---@class Terminal.SessionsApi
---@field list fun(all?: boolean): Terminal.Handle[]
---@field open fun(target: Terminal.Target): Terminal.Handle|nil, string|nil
---@field hide fun(target: Terminal.Target): boolean, string|nil
---@field run fun(cmd: string|string[], opts: Terminal.RunOpts): boolean|nil, string|nil

--- Where the definitions of the session file `path` are kept.
---@param path string
---@return string
function M.sidecar_path(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  local base = vim.fn.fnamemodify(path, ":t:r")
  return dir .. "/." .. base .. ".terminals.json"
end

---@internal
---@param v any
---@return boolean
local function argv_ok(v)
  if type(v) ~= "table" or #v == 0 then
    return false
  end
  for _, word in ipairs(v) do
    if type(word) ~= "string" then
      return false
    end
  end
  return true
end

--- What a file may say, reduced to what is safe to act on: a malformed entry is dropped, never
--- repaired.
---@param decoded any
---@return Terminal.SessionDef[]
function M.validate(decoded)
  local out = {}
  if type(decoded) ~= "table" or type(decoded.terminals) ~= "table" then
    return out
  end
  local layouts = require("terminal.backends").LAYOUTS
  local seen = {}
  for _, d in ipairs(decoded.terminals) do
    if
      type(d) == "table"
      and type(d.name) == "string"
      and d.name ~= ""
      and not seen[d.name]
      and vim.list_contains(layouts, d.layout)
    then
      seen[d.name] = true
      out[#out + 1] = {
        name = d.name,
        layout = d.layout,
        cwd = type(d.cwd) == "string" and d.cwd or nil,
        cmd = argv_ok(d.cmd) and d.cmd or nil,
      }
    end
  end
  return out
end

--- The definitions of this project's live native terminals, in creation order.
---@param api Terminal.SessionsApi
---@return Terminal.SessionDef[]
function M.snapshot(api)
  local defs = {}
  -- A configured `shell` given as an argv is every terminal's job, not a command of its own.
  local shell = require("terminal.config").shell_command()
  for _, h in ipairs(api.list()) do
    if h.backend == "native" and not h.exited and not h.disposed then
      local is_command = type(h.cmd) == "table" and not vim.deep_equal(h.cmd, shell)
      defs[#defs + 1] = {
        name = h.name,
        layout = h.layout,
        cwd = h.cwd,
        cmd = is_command and h.cmd or nil,
      }
    end
  end
  return defs
end

--- Write the definitions beside the session file; no terminals, no file (a stale one would bring
--- back terminals the session no longer has).
---@param api Terminal.SessionsApi
---@param session_path string
---@return boolean ok
---@return string|nil err
function M.save(api, session_path)
  local file = M.sidecar_path(session_path)
  local defs = M.snapshot(api)
  if #defs == 0 then
    os.remove(file)
    return true, nil
  end
  return require("lib.nvim.fs.json").write(file, { version = 1, terminals = defs })
end

--- A session was renamed: the sidecar goes with it. An existing sidecar of the new name is a
--- leftover of an earlier session of that name and is replaced; no sidecar, nothing to move.
---@param old_path string
---@param new_path string
---@return boolean ok
---@return string|nil err
function M.rename(old_path, new_path)
  local old, new = M.sidecar_path(old_path), M.sidecar_path(new_path)
  if vim.fn.filereadable(old) == 0 then
    return true, nil
  end
  os.remove(new)
  local ok, err = os.rename(old, new)
  if not ok then
    return false, err
  end
  return true, nil
end

--- A session was deleted: its sidecar goes too.
---@param session_path string
---@return nil
function M.delete(session_path)
  os.remove(M.sidecar_path(session_path))
end

--- The definitions saved for the session file `path` (none when there is no sidecar or it is
--- unreadable).
---@param session_path string
---@return Terminal.SessionDef[]
function M.read(session_path)
  local file = M.sidecar_path(session_path)
  if vim.fn.filereadable(file) == 0 then
    return {}
  end
  local decoded = require("lib.nvim.fs.json").read(file)
  return M.validate(decoded)
end

---@internal
---@param def Terminal.SessionDef
---@return string
local function describe(def)
  return def.cmd and ("%s: %s"):format(def.name, table.concat(def.cmd, " ")) or def.name
end

---@class Terminal.SessionsRestored
---@field opened integer
---@field skipped integer Already there: left alone
---@field failed string[]

--- Reopen `defs` (hidden), except the terminals that already exist: loading a session twice, or
--- with a terminal of the same name open, must not duplicate or replace anything.
---
--- `with_commands`: start the saved commands (true), or open those terminals as plain shells
--- (false).
---@param api Terminal.SessionsApi
---@param defs Terminal.SessionDef[]
---@param with_commands boolean
---@return Terminal.SessionsRestored
function M.restore(api, defs, with_commands)
  local result = { opened = 0, skipped = 0, failed = {} }
  local present = {}
  for _, h in ipairs(api.list()) do
    present[h.name] = true
  end
  for _, def in ipairs(defs) do
    if present[def.name] then
      result.skipped = result.skipped + 1
    else
      local ok, err
      if def.cmd and with_commands then
        ok, err = api.run(
          def.cmd,
          { name = def.name, layout = def.layout, focus = false, direct = true, cwd = def.cwd }
        )
      else
        local handle
        handle, err = api.open({ name = def.name, layout = def.layout, focus = false })
        ok = handle ~= nil
      end
      if ok then
        api.hide({ name = def.name })
        result.opened = result.opened + 1
      else
        result.failed[#result.failed + 1] = ("%s: %s"):format(def.name, err or "failed")
      end
    end
  end
  return result
end

---@internal
---@param result Terminal.SessionsRestored
local function report(result)
  if #result.failed > 0 then
    require("terminal.notify").warn(
      "sessions: could not reopen " .. table.concat(result.failed, "; ")
    )
  end
end

--- Reopen the terminals saved with the session `path`, asking first when `commands` is "ask" and
--- one of them would start a command: a session file is a recipe, and loading it must not run a
--- failing or surprising command on its own.
---@param api Terminal.SessionsApi
---@param session_path string
---@param commands "ask"|"run"|"never"
---@param select? fun(items: string[], opts: table, on_choice: fun(item: string|nil)) Default `vim.ui.select`
---@return nil
function M.load(api, session_path, commands, select)
  local defs = M.read(session_path)
  if #defs == 0 then
    return
  end
  local with_cmd = {}
  for _, def in ipairs(defs) do
    if def.cmd then
      with_cmd[#with_cmd + 1] = describe(def)
    end
  end
  if #with_cmd == 0 or commands == "run" then
    report(M.restore(api, defs, true))
  elseif commands == "never" then
    report(M.restore(api, defs, false))
  else
    local start, shells, skip = "Start the commands", "Open plain shells", "Skip the terminals"
    local ask = select or vim.ui.select
    ask({ start, shells, skip }, {
      prompt = "terminal.nvim: this session had terminals with commands:\n  "
        .. table.concat(with_cmd, "\n  "),
    }, function(choice)
      if choice == start then
        report(M.restore(api, defs, true))
      elseif choice == shells then
        report(M.restore(api, defs, false))
      end
    end)
  end
end

--- Listen to sessions.nvim (or anything that fires the same events). Safe to call again.
---@param cfg Terminal.Config
---@param api? Terminal.SessionsApi Default: the facade
---@return nil
function M.setup(cfg, api)
  local group = require("lib.nvim.bindings.autocmd").group(GROUP, true)
  if not cfg.sessions.enable then
    return
  end
  local function facade()
    return api or require("terminal")
  end
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "SessionsSavePost",
    desc = "terminal.nvim: write the terminal definitions beside the session",
    callback = function(ev)
      if type(ev.data) ~= "table" or ev.data.tab or type(ev.data.path) ~= "string" then
        return
      end
      local ok, err = M.save(facade(), ev.data.path)
      if not ok then
        require("terminal.notify").warn("sessions: terminals not saved: " .. tostring(err))
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "SessionsLoadPost",
    desc = "terminal.nvim: reopen the terminals saved with the session",
    callback = function(ev)
      if type(ev.data) ~= "table" or ev.data.tab or type(ev.data.path) ~= "string" then
        return
      end
      M.load(facade(), ev.data.path, require("terminal.config").get("sessions.commands"))
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "SessionsRenamePost",
    desc = "terminal.nvim: move the terminal definitions with a renamed session",
    callback = function(ev)
      local d = ev.data
      if type(d) ~= "table" or type(d.old_path) ~= "string" or type(d.path) ~= "string" then
        return
      end
      local ok, err = M.rename(d.old_path, d.path)
      if not ok then
        require("terminal.notify").warn("sessions: terminals not moved: " .. tostring(err))
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "SessionsDeletePost",
    desc = "terminal.nvim: remove the terminal definitions of a deleted session",
    callback = function(ev)
      if type(ev.data) == "table" and type(ev.data.path) == "string" then
        M.delete(ev.data.path)
      end
    end,
  })
end

return M
