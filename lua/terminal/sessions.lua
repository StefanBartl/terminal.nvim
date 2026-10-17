---@module 'terminal.sessions'
--- Terminals follow a session of sessions.nvim: the definitions (name, layout, directory and, for a
--- `run` with `direct`, the command with its `close`, `title` and `float`) are written next to the
--- session file when it is saved and
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
--- written: a multiplexer pane outlives Neovim and needs no restoring. A terminal started by `run`
--- with `session = false` is not written either.
---@see terminal.pin

local M = {}

local GROUP = "terminal.sessions"

---@class Terminal.SessionDef
---@field name string
---@field layout Terminal.Layout
---@field cwd? string
---@field cmd? string[] The argv of a `run` with `direct`; nil: a shell
---@field close? "always"|"success"|"never" With `cmd`: what `run` was given for the job's end
---@field title? string With `cmd`: the window title `run` was given
---@field float? table With `cmd`: the `float` overrides `run` was given

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

---@internal
local CLOSE = { always = true, success = true, never = true }

--- The `close`, `title` and `float` of a `run` with `direct` (`Terminal.RunRecord`), reduced to
--- what a sidecar may hold and a restore may hand back to `run`: an unknown close mode, a title
--- that is not a string or has control characters, and every `float` key the configuration would
--- refuse are left out. Used both for what a handle carries (a caller's table may hold anything)
--- and for what a sidecar says (untrusted: a shared or cloned session directory).
---@param rec any
---@param into table Gets `close`, `title`, `float`
---@return table into
function M.run_fields(rec, into)
  if type(rec) ~= "table" then
    return into
  end
  if CLOSE[rec.close] then
    into.close = rec.close
  end
  if type(rec.title) == "string" and not rec.title:find("%c") then
    into.title = rec.title
  end
  if type(rec.float) == "table" and not vim.islist(rec.float) then
    local _, clean = require("terminal.config").validate(
      require("terminal.config.DEFAULTS").float,
      rec.float,
      "float"
    )
    if next(clean) ~= nil then
      into.float = clean
    end
  end
  return into
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
      local def = {
        name = d.name,
        layout = d.layout,
        cwd = type(d.cwd) == "string" and d.cwd or nil,
        cmd = argv_ok(d.cmd) and d.cmd or nil,
      }
      out[#out + 1] = def.cmd and M.run_fields(d, def) or def
    end
  end
  return out
end

--- The definitions of this project's live native terminals, in creation order. A terminal started
--- by `run` with `session = false` is left out: its caller sets it up in `on_open`, which a restore
--- cannot repeat.
---@param api Terminal.SessionsApi
---@return Terminal.SessionDef[]
function M.snapshot(api)
  local defs = {}
  -- A configured `shell` given as an argv is every terminal's job, not a command of its own.
  local shell = require("terminal.config").shell_command()
  for _, h in ipairs(api.list()) do
    if h.backend == "native" and not h.exited and not h.disposed and h.session ~= false then
      local is_command = type(h.cmd) == "table" and not vim.deep_equal(h.cmd, shell)
      local def = {
        name = h.name,
        layout = h.layout,
        cwd = h.cwd,
        cmd = is_command and h.cmd or nil,
      }
      defs[#defs + 1] = is_command and M.run_fields(h.rerun, def) or def
    end
  end
  return defs
end

--- Definitions a load did not bring back (skipped by the prompt, a failed start, or a command
--- replaced by a plain shell), by session file. A save writes the live terminals, so without this
--- the next save (autosave, leaving Neovim) would delete what this machine could not or did not
--- want to restore now, and the session would lose it for good.
---@type table<string, Terminal.SessionDef[]>
local kept = {}

--- The names of this project's live native terminals that `run` kept out of the session
--- (`session = false`).
---@param api Terminal.SessionsApi
---@return table<string, true>
function M.opted_out(api)
  local names = {}
  for _, h in ipairs(api.list()) do
    if h.backend == "native" and not h.exited and not h.disposed and h.session == false then
      names[h.name] = true
    end
  end
  return names
end

--- The live terminals plus the definitions a load left behind. A live terminal of the same name
--- wins, except that it takes over the saved command when it was only opened as a plain shell.
--- A live terminal kept out of the session (`opted_out`) wins too: a definition of its name saved
--- before is dropped, not written again.
---@param live Terminal.SessionDef[]
---@param left_over Terminal.SessionDef[]|nil
---@param opted_out? table<string, true> Names of live terminals kept out of the session
---@return Terminal.SessionDef[]
function M.merge(live, left_over, opted_out)
  if not left_over or #left_over == 0 then
    return live
  end
  local saved = {}
  for _, def in ipairs(left_over) do
    saved[def.name] = def
  end
  local out, seen = {}, vim.deepcopy(opted_out or {})
  for _, def in ipairs(live) do
    seen[def.name] = true
    local before = saved[def.name]
    out[#out + 1] = (before and before.cmd and not def.cmd) and before or def
  end
  for _, def in ipairs(left_over) do
    if not seen[def.name] then
      out[#out + 1] = def
    end
  end
  return out
end

--- Write the definitions beside the session file; no terminals, no file (a stale one would bring
--- back terminals the session no longer has). A left-over definition whose name a live terminal
--- keeps out of the session is dropped for good, not only while that terminal is open.
---@param api Terminal.SessionsApi
---@param session_path string
---@return boolean ok
---@return string|nil err
function M.save(api, session_path)
  local file = M.sidecar_path(session_path)
  local opted_out = M.opted_out(api)
  -- `opted_out` only names live terminals: once the opted-out one is gone (a `close = "always"`
  -- job ended, the user closed it) a definition still in `kept` would be written again. So the
  -- names leave `kept` itself.
  local left_over = kept[session_path]
  if left_over and next(opted_out) ~= nil then
    left_over = vim.tbl_filter(function(def)
      return not opted_out[def.name]
    end, left_over)
    kept[session_path] = #left_over > 0 and left_over or nil
  end
  local defs = M.merge(M.snapshot(api), kept[session_path], opted_out)
  if #defs == 0 then
    os.remove(file)
    return true, nil
  end
  return require("lib.nvim.fs.json").write(file, { version = 1, terminals = defs })
end

--- A session was renamed: the sidecar goes with it. An existing sidecar of the new name is a
--- leftover of an earlier session of that name and is removed first; no old sidecar, nothing to move.
---@param old_path string
---@param new_path string
---@return boolean ok
---@return string|nil err
function M.rename(old_path, new_path)
  local old, new = M.sidecar_path(old_path), M.sidecar_path(new_path)
  -- The new name is free as a session, so a sidecar there is an orphan: it goes even when the old
  -- session had no terminals, or loading the renamed session would bring the orphan's back.
  os.remove(new)
  kept[new_path], kept[old_path] = kept[old_path], nil
  if vim.fn.filereadable(old) == 0 then
    return true, nil
  end
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
  kept[session_path] = nil
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
--- Text of a sidecar for the confirmation prompt, which exists so the user can see what "Start the
--- commands" would run: a sidecar is untrusted (a shared or cloned session directory), so control
--- characters are spelled out (no newline can scroll the real command away or fake a harmless
--- line) and one entry cannot grow without bound.
---@param s string
---@return string
local function esc(s)
  local function spell(m)
    return (m:gsub(".", function(c)
      return ("\\x%02x"):format(c:byte())
    end))
  end
  -- ASCII control characters, and the Unicode ones that change what is shown or are invisible:
  -- C1 controls and the soft hyphen (U+0080-009F, U+00AD), the Arabic letter mark (U+061C),
  -- zero-width and direction marks (U+200B-200F), line and paragraph separators and bidirectional
  -- embeddings and overrides (U+2028-202E, U+2066-2069), word joiner and invisible operators
  -- (U+2060-2064), the byte order mark / zero width no-break space (U+FEFF) and the tag characters
  -- (U+E0000-E007F, invisible text smuggled into a string). A command can be shown in another order
  -- or with parts missing from what it runs. Written as byte ranges (decimal escapes) so it also
  -- works where Lua has no `\x`.
  local out = s:gsub("%c", spell)
  for _, pattern in ipairs({
    "\194[\128-\159\173]", -- U+0080-009F, U+00AD
    "\216\156", -- U+061C
    "\226\128[\139-\143\168-\174]", -- U+200B-200F, U+2028-202E
    "\226\129[\160-\169]", -- U+2060-2069
    "\239\187\191", -- U+FEFF
    "\243\160[\128\129][\128-\191]", -- U+E0000-E007F
  }) do
    out = out:gsub(pattern, spell)
  end
  if vim.fn.strchars(out) > 120 then
    out = vim.fn.strcharpart(out, 0, 117) .. "..."
  end
  return out
end

---@internal
---@param def Terminal.SessionDef
---@return string
local function describe(def)
  if not def.cmd then
    return esc(def.name)
  end
  local line = ("%s: %s"):format(esc(def.name), esc(table.concat(def.cmd, " ")))
  return def.cwd and ("%s  (in %s)"):format(line, esc(def.cwd)) or line
end

---@class Terminal.SessionsRestored
---@field opened integer
---@field skipped integer Already there: left alone
---@field failed string[]
---@field left_over Terminal.SessionDef[] Not brought back as saved: failed starts, and commands that were opened as plain shells

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
  local result = { opened = 0, skipped = 0, failed = {}, left_over = {} }
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
        ok, err = api.run(def.cmd, {
          name = def.name,
          layout = def.layout,
          focus = false,
          direct = true,
          cwd = def.cwd,
          close = def.close,
          title = def.title,
          float = def.float,
        })
      else
        local handle
        handle, err = api.open({ name = def.name, layout = def.layout, focus = false })
        ok = handle ~= nil
      end
      if ok then
        api.hide({ name = def.name })
        result.opened = result.opened + 1
        if def.cmd and not with_commands then
          result.left_over[#result.left_over + 1] = def
        end
      else
        result.failed[#result.failed + 1] = ("%s: %s"):format(def.name, err or "failed")
        result.left_over[#result.left_over + 1] = def
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
  ---@param with_commands boolean
  local function bring_back(with_commands)
    local result = M.restore(api, defs, with_commands)
    kept[session_path] = #result.left_over > 0 and result.left_over or nil
    report(result)
  end
  if #with_cmd == 0 or commands == "run" then
    bring_back(true)
  elseif commands == "never" then
    bring_back(false)
  else
    -- Until the user has answered (or never answers, or skips), nothing was restored: a save in
    -- between must not drop the definitions.
    kept[session_path] = defs
    local start, shells, skip = "Start the commands", "Open plain shells", "Skip the terminals"
    local ask = select or vim.ui.select
    ask({ start, shells, skip }, {
      prompt = "terminal.nvim: this session had terminals with commands:\n  "
        .. table.concat(with_cmd, "\n  "),
    }, function(choice)
      if choice == start then
        bring_back(true)
      elseif choice == shells then
        bring_back(false)
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
