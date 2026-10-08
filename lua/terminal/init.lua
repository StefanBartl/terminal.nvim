---@module 'terminal'
--- Public facade of terminal.nvim: named terminals, the same API for every backend.
---
--- Every function resolves the target the same way: the *project root* (see
--- `terminal.core.context`) plus a *name* identify a terminal. `toggle()` without a name uses the
--- configured default name, `toggle({ count = 3 })` uses the terminal "3".
---
--- Failures are returned as `nil, err` (or `false, err`); only a programmer error such as an
--- invalid navigation direction raises. `open`, `toggle`, `send`, `run`, `pin` and `adopt` also
--- show the failure to the user, since they are actions the user asked for; `hide` and `close`
--- only answer (the `:Terminal` command shows their reason), so a script can probe with them.
--- The `Terminal.Handle` tables the functions return are live references into the registry: read
--- them, never write to them.
---@see terminal.core.context
---@see terminal.backends
---@see terminal.core.registry

local config = require("terminal.config")
local context = require("terminal.core.context")
local backends = require("terminal.backends")
local registry_mod = require("terminal.core.registry")
local notify = require("terminal.notify")

local M = {}

---@type Terminal.State
local state = {
  ready = false,
  registry = registry_mod.new(),
  backends = {},
  backend = nil,
  env = {},
  unavailable = {},
  deps = context.from_editor(),
}

---@internal
---@return table<string, string|nil>
local function environment()
  return {
    TMUX = vim.env.TMUX,
    WEZTERM_PANE = vim.env.WEZTERM_PANE,
    TMUX_PANE = vim.env.TMUX_PANE,
    NVIM = vim.env.NVIM,
  }
end

---@internal
--- Show a problem to the user (deferred, so a command run from a script never surfaces a raw error).
---@param err string|nil # nil is reported as an unknown error
---@return nil
local function fail(err)
  vim.schedule(function()
    notify.error(err or "unknown error")
  end)
end

---@internal
---@param name string
---@param cwd string
---@param root string
---@param extra? Terminal.SpawnExtra
---@return Terminal.SpawnSpec
local function build_spec(name, cwd, root, extra)
  extra = extra or {}
  local env = config.get("env")
  local start_insert = extra.start_insert
  if start_insert == nil then
    start_insert = config.get("start_insert")
  end
  return {
    name = name,
    root = root,
    cwd = cwd,
    cmd = config.shell_command(),
    env = next(env) ~= nil and env or nil,
    layout = extra.layout or config.get("layout"),
    float = config.get("float"),
    split = config.get("split"),
    start_insert = start_insert,
    focus = extra.focus,
    on_exit = config.get("on_exit"),
    on_exit_cb = extra.on_exit_cb,
  }
end

---@internal
--- The multiplexer backend `name`, registered on first use.
---@param name string "wezterm" or "tmux"
---@return Terminal.Backend|nil
---@return string|nil reason # Why it is not usable
local function multiplexer(name)
  if not vim.list_contains(backends.MULTIPLEXERS, name) then
    return nil, "not a multiplexer backend (use tmux or wezterm)"
  end
  local existing = state.backends[name]
  if existing then
    return existing, nil
  end
  if state.unavailable[name] then
    return nil, state.unavailable[name]
  end
  local mod = require("terminal.backends." .. name)
  local ok, reason = mod.available(state.env)
  if not ok then
    state.unavailable[name] = reason or "not available"
    return nil, state.unavailable[name]
  end
  state.backends[name] = mod.new(state.registry)
  return state.backends[name], nil
end

--- Set the plugin up. Safe to call again: the options are replaced, the terminals stay.
---@param opts Terminal.Options|nil
---@return nil
function M.setup(opts)
  config.setup(opts)

  local native = require("terminal.backends.native").new(state.registry)
  state.backends = { native = native }
  state.unavailable = {}
  local env = environment()
  state.env = env
  -- A multiplexer backend is looked at (and registered) only when the config names it, or later
  -- when `pin` or a pinned terminal needs it: whether its CLI is installed is a lookup over
  -- $PATH, which is slow on Windows (docs/backends.md) -- not something every startup pays.
  local wanted = config.get("backend")
  local reason
  if vim.list_contains(backends.MULTIPLEXERS, wanted) then
    local _, why = multiplexer(wanted)
    reason = why
  end
  local name, note = backends.resolve(wanted, env, state.backends)
  if note and reason then
    note = ("backend '%s' is not available (%s) -- using native"):format(wanted, reason)
  end
  state.backend = state.backends[name]
  if note then
    vim.schedule(function()
      notify.warn(note)
    end)
  end

  state.ready = true
  -- Each part on its own: a failure in one (a binding that cannot be created) must not leave
  -- status export and navigation unconfigured.
  local steps = {
    { "bindings", require("terminal.bindings").setup },
    {
      "status",
      function()
        require("terminal.status").setup(config.get_all(), env)
      end,
    },
    {
      "navigation",
      function()
        require("terminal.navigate").setup(config.get_all(), env)
      end,
    },
  }
  for _, step in ipairs(steps) do
    local ok, err = pcall(step[2])
    if not ok then
      fail(("setup: %s failed: %s"):format(step[1], tostring(err)))
    end
  end
end

---@internal
---@return Terminal.Backend
local function backend()
  if not state.ready then
    M.setup()
  end
  return state.backend
end

---@internal
--- The backend that owns `handle` (a pinned terminal lives in another backend than the default).
---@param handle Terminal.Handle
---@return Terminal.Backend
local function backend_of(handle)
  return state.backends[handle.backend] or multiplexer(handle.backend) or backend()
end

---@internal
--- Where `handle` is and whether it has focus: one question to its backend (a multiplexer answers
--- with ONE process instead of one per question). nil = the backend could not say; the terminal
--- is then assumed to be there and is never replaced on the strength of a failed query.
---@param b Terminal.Backend
---@param handle Terminal.Handle
---@return Terminal.Probe|nil
local function probe(b, handle)
  return (b.probe(handle))
end

---@internal
--- The boundary check of every public function that takes a target. The facade is a system
--- boundary (user config, other plugins call it), so a wrong type is reported with a reason
--- instead of raising from deep inside; `count` is checked where the name is made.
---@param target any
---@return string|nil err
local function check_target(target)
  if target == nil then
    return nil
  end
  if type(target) ~= "table" then
    return ("target must be a table, got %s"):format(type(target))
  end
  if target.name ~= nil and (type(target.name) ~= "string" or target.name == "") then
    return "target.name must be a non-empty string"
  end
  if target.layout ~= nil and not vim.list_contains(backends.LAYOUTS, target.layout) then
    return ("unknown layout %s (use float, split, vsplit or tab)"):format(tostring(target.layout))
  end
  if target.focus ~= nil and type(target.focus) ~= "boolean" then
    return "target.focus must be a boolean"
  end
  return nil
end

---@internal
--- Resolve target name, working directory and project root for one call. A call resolves ONCE and
--- hands the result on (`Terminal.Resolved`).
---@param target Terminal.Target|nil
---@return string|nil name # nil when the target is invalid
---@return string cwd_or_err # The working directory, or the reason the target is invalid
---@return string|nil root
local function resolve(target)
  local bad = check_target(target)
  if bad then
    return nil, bad
  end
  target = target or {}
  local name = target.name
  if not name then
    local nerr
    name, nerr = context.name_for_count(target.count, config.get("default_name"))
    if not name then
      return nil, nerr or "invalid count"
    end
  end
  local cwd, root = context.resolve(config.get("cwd"), state.deps)
  return name, cwd, root
end

---@internal
--- `resolve` into a record, or `nil, err`.
---@param target Terminal.Target|nil
---@return Terminal.Resolved|nil
---@return string|nil err
local function resolved(target)
  local name, cwd, root = resolve(target)
  if not name then
    return nil, cwd
  end
  return { name = name, cwd = cwd, root = root }, nil
end

---@internal
--- The live terminal for this target, or nil (an exited one counts as gone).
---@param root string
---@param name string
---@return Terminal.Handle|nil
local function find_live(root, name)
  local h = state.registry:find(root, name)
  if h and h.exited then
    return nil
  end
  return h
end

---@type Terminal.Host
local host = {
  fail = fail,
  resolve = resolve,
  find_live = find_live,
  backend_of = backend_of,
  multiplexer = multiplexer,
  backend = backend,
  build_spec = build_spec,
  state = state,
}

---@internal
--- `open`, optionally with what the caller already learned: `known` (`toggle` has probed the
--- terminal, so the multiplexer is not asked a second time) and `at` (the call's resolved target).
---@param target Terminal.Target|nil
---@param known? Terminal.OpenKnown
---@param at? Terminal.Resolved
---@return Terminal.Handle|nil handle
---@return string|nil err
local function open_impl(target, known, at)
  local default = backend()
  if not at then
    local rerr
    at, rerr = resolved(target)
    if not at then
      fail(rerr)
      return nil, rerr
    end
  end
  local name, cwd, root = at.name, at.cwd, at.root
  local focus = not (target and target.focus == false)
  local layout = target and target.layout or nil
  local previous = vim.api.nvim_get_current_win()
  -- Without focus the terminal must not grab Insert mode either; nil = the configured default.
  local start_insert = nil
  if not focus then
    start_insert = false
  end

  local handle, where
  if known then
    handle, where = known.handle, known.where
  else
    handle = find_live(root, name)
    where = handle and probe(backend_of(handle), handle)
  end
  local b = handle and backend_of(handle) or default
  if handle and where and not where.visible and not b.show then
    -- A backend that cannot show a hidden terminal again (a pane the user closed): start a new
    -- one. The pane is known to be gone; `close` only has to forget it.
    b.close(handle, { gone = true })
    handle = nil
  end
  local focus_err
  if handle then
    if where == nil or where.visible then
      if focus then
        local ok, ferr = b.focus(handle)
        if not ok then
          focus_err = ("terminal '%s': %s"):format(name, ferr or "cannot focus")
          fail(focus_err)
        end
      end
      return handle, focus_err
    end
    local spec =
      build_spec(name, cwd, root, { layout = layout, start_insert = start_insert, focus = focus })
    local ok, err = b.show(handle, spec)
    if not ok then
      fail(("terminal '%s': %s"):format(name, err or "cannot show"))
      return nil, err
    end
  else
    local stale = state.registry:find(root, name)
    if stale then
      backend_of(stale).close(stale)
    end
    local spec =
      build_spec(name, cwd, root, { layout = layout, start_insert = start_insert, focus = focus })
    local err
    handle, err = default.spawn(spec)
    if not handle then
      fail(("terminal '%s': %s"):format(name, err or "cannot start"))
      return nil, err
    end
  end

  if not focus and vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
  return handle, nil
end

--- Show the terminal (creating it when needed) and focus it.
---
--- With `focus = false` the terminal appears but the window that was current stays current.
---@param target Terminal.Target|nil
---@return Terminal.Handle|nil handle # Live reference into the registry: read it, never write to it
---@return string|nil err
function M.open(target)
  return open_impl(target, nil, nil)
end

---@internal
--- Hide the terminal `at` names. Never reports to the user, whatever the outcome: the caller
--- decides what to do with `false, reason`.
---@param at Terminal.Resolved
---@return boolean hidden
---@return string|nil err
local function hide_impl(at)
  local handle = find_live(at.root, at.name)
  if not handle then
    return false, ("no terminal '%s' in this project"):format(at.name)
  end
  local ok, err = backend_of(handle).hide(handle)
  if not ok then
    return false, ("terminal '%s': %s"):format(at.name, err or "cannot hide")
  end
  return true, nil
end

--- Hide the terminal's window; the job keeps running. Answers, does not report: a failure
--- (including "there is no such terminal") is returned, not shown; the `:Terminal hide` command
--- shows it.
---@param target Terminal.Target|nil
---@return boolean hidden
---@return string|nil err # Why not (also when there is no such terminal)
function M.hide(target)
  backend()
  local at, rerr = resolved(target)
  if not at then
    return false, rerr
  end
  return hide_impl(at)
end

--- Toggle: focus when it is visible elsewhere, hide when it has focus, show when it is hidden,
--- create when it does not exist.
---@param target Terminal.Target|nil
---@return boolean ok
---@return string|nil err
function M.toggle(target)
  backend()
  local at, rerr = resolved(target)
  if not at then
    fail(rerr)
    return false, rerr
  end
  local handle = find_live(at.root, at.name)
  ---@type Terminal.OpenKnown|nil
  local known
  if handle then
    local b = backend_of(handle)
    local where = probe(b, handle)
    if where == nil or where.visible then
      if where and where.focused then
        local hidden, herr = hide_impl(at)
        if not hidden then
          fail(herr)
        end
        return hidden, herr
      end
      local ok, err = b.focus(handle)
      if not ok then
        local msg = ("terminal '%s': %s"):format(at.name, err or "cannot focus")
        fail(msg)
        return false, msg
      end
      -- Insert mode belongs to a Neovim window; a multiplexer pane takes its own input, and
      -- Neovim must stay in Normal mode in the pane the user just left.
      if handle.backend == "native" and config.get("start_insert") then
        vim.cmd("startinsert")
      end
      return true, nil
    end
    known = { handle = handle, where = where }
  end
  local opened, err = open_impl(target, known, at)
  return opened ~= nil, err
end

--- Stop the terminal's job and remove it. Answers, does not report (like `hide`).
---@param target Terminal.Target|nil
---@return boolean closed
---@return string|nil err # Why not (also when there is no such terminal)
function M.close(target)
  backend()
  local at, rerr = resolved(target)
  if not at then
    return false, rerr
  end
  local handle = state.registry:find(at.root, at.name)
  if not handle then
    return false, ("no terminal '%s' in this project"):format(at.name)
  end
  local ok, err = backend_of(handle).close(handle)
  if not ok then
    return false, ("terminal '%s': %s"):format(at.name, err or "cannot close")
  end
  return true, nil
end

--- The terminals of the current project (all projects with `all = true`).
---@param all? boolean
---@return Terminal.Handle[] handles # Live references into the registry: read them, never write
function M.list(all)
  backend()
  -- Prune the handles whose buffer or pane is gone; a backend is asked once, and only when it
  -- owns a handle.
  local asked = {}
  for _, h in ipairs(state.registry:list()) do
    local b = backend_of(h)
    if not asked[b] then
      asked[b] = true
      b.list()
    end
  end
  if all then
    return state.registry:list()
  end
  local _, root = context.resolve(config.get("cwd"), state.deps)
  return state.registry:list(root)
end

--- The names of this project's terminals (all projects with `all = true`), straight from the
--- registry: no multiplexer is asked, so a pane the user closed a moment ago can still be named.
--- Cheap enough for completion on every key; `list` is the exact answer.
---@param all? boolean
---@return string[] names # In creation order
function M.names(all)
  backend()
  local root
  if not all then
    local _, project = context.resolve(config.get("cwd"), state.deps)
    root = project
  end
  return vim.tbl_map(function(h)
    return h.name
  end, state.registry:list(root))
end

---@internal
--- `send` with the target already resolved.
---@param text string
---@param opts Terminal.SendOpts
---@param at Terminal.Resolved
---@return boolean sent
---@return string|nil err
local function send_impl(text, opts, at)
  local target = vim.tbl_extend("keep", { name = at.name }, opts)
  if opts.focus == nil then
    target.focus = false
  end
  local handle, err = open_impl(target, nil, at)
  if not handle then
    return false, err
  end
  local payload = text
  if opts.newline then
    payload = payload .. (vim.fn.has("win32") == 1 and "\r" or "\n")
  end
  local ok, serr = backend_of(handle).send(handle, payload)
  if not ok then
    fail(("terminal '%s': %s"):format(handle.name, serr or "cannot send"))
    return false, serr
  end
  return true, nil
end

---@internal
--- A target for `send`/`run`: the caller's options, the `run.name` terminal when no name or count
--- is given.
---@param opts Terminal.Target
---@return Terminal.Target
local function with_run_name(opts)
  if opts.name == nil and (opts.count == nil or opts.count == 0) then
    -- 0 is what `vim.v.count` is without a count: the run terminal, like no count at all
    return vim.tbl_extend("force", opts, { name = config.get("run.name") })
  end
  return opts
end

--- Send text to a terminal as typed input. Nothing is executed unless `newline` is true (or the
--- text itself ends in a line ending). The terminal is created when it does not exist yet.
---@param text string
---@param opts? Terminal.SendOpts
---@return boolean sent
---@return string|nil err
function M.send(text, opts)
  if type(text) ~= "string" then
    local msg = "send: text must be a string"
    fail(msg)
    return false, msg
  end
  if opts ~= nil and type(opts) ~= "table" then
    local msg = ("send: opts must be a table, got %s"):format(type(opts))
    fail(msg)
    return false, msg
  end
  opts = opts or {}
  backend()
  local at, rerr = resolved(with_run_name(opts))
  if not at then
    fail(rerr)
    return false, rerr
  end
  return send_impl(text, opts, at)
end

---@internal
--- The quoting family for words typed into terminal `name`. A native terminal runs the configured
--- shell (or Neovim's 'shell'); so does a multiplexer pane when `shell` is configured. Without
--- one the pane runs the *multiplexer's* default shell -- unknown here, and not necessarily the
--- shell Neovim uses -- so only words that mean the same in every shell are accepted
--- ("portable"); anything else is refused instead of quoted for the wrong shell.
---@param at Terminal.Resolved
---@param default Terminal.Backend
---@return Terminal.ShellKind
local function line_shell_kind(at, default)
  local existing = find_live(at.root, at.name)
  local owner = existing and existing.backend or default.name
  if config.shell_command() ~= nil or owner == "native" then
    return require("terminal.core.quote").shell_kind(config.shell_executable())
  end
  return "portable"
end

---@internal
local CLOSE_MODES = { always = "close", success = "close_on_success", never = "keep" }

---@internal
--- `run` with `direct = true`: the command IS the job.
---@param b Terminal.Backend
---@param cmd string[]
---@param opts Terminal.RunOpts
---@param at Terminal.Resolved
---@return boolean started
---@return string|nil err
---@return Terminal.Handle|nil handle
local function run_direct(b, cmd, opts, at)
  local name, cwd, root = at.name, at.cwd, at.root
  local close_mode = CLOSE_MODES[opts.close or "never"]
  if not close_mode then
    local msg = ("run: close must be always, success or never, got %s"):format(tostring(opts.close))
    fail(msg)
    return false, msg
  end
  local old = state.registry:find(root, name)
  if old then
    local closed, cerr = backend_of(old).close(old)
    if not closed then
      -- The earlier terminal is still there (a pane that could not be killed): starting another
      -- under the same name would orphan it.
      local msg = ("terminal '%s': cannot replace the earlier one: %s"):format(
        name,
        cerr or "cannot close"
      )
      fail(msg)
      return false, msg
    end
  end
  local focus = opts.focus ~= false
  -- A throwing user callback is reported, not swallowed (and never takes the terminal with it).
  local on_exit = opts.on_exit
  local spec = build_spec(name, opts.cwd or cwd, root, {
    layout = opts.layout,
    start_insert = focus and opts.start_insert ~= false,
    focus = focus,
    on_exit_cb = on_exit and function(code)
      local ok, e = pcall(on_exit, code)
      if not ok then
        fail(("run: on_exit failed: %s"):format(tostring(e)))
      end
    end or nil,
  })
  spec.cmd = cmd
  spec.title = opts.title
  if opts.float then
    spec.float = vim.tbl_extend("force", spec.float or {}, opts.float)
  end
  if opts.env then
    spec.env = vim.tbl_extend("force", spec.env or {}, opts.env)
  end
  spec.on_exit = close_mode
  local previous = vim.api.nvim_get_current_win()
  local handle, err = b.spawn(spec)
  if not handle then
    fail(("terminal '%s': %s"):format(name, err or "cannot start"))
    return false, err
  end
  if opts.focus == false and vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
  if opts.on_open then
    local ok, e = pcall(opts.on_open, handle)
    if not ok then
      fail(("run: on_open failed: %s"):format(tostring(e)))
    end
  end
  return true, nil, handle
end

---@internal
--- `run` without `direct`: a line typed into the terminal's shell.
---@param b Terminal.Backend
---@param cmd string|string[]
---@param opts Terminal.RunOpts
---@param at Terminal.Resolved
---@return boolean started
---@return string|nil err
local function run_line(b, cmd, opts, at)
  ---@type string|nil
  local line
  if type(cmd) == "table" then
    local qerr
    line, qerr = require("terminal.core.quote").argv_to_line(cmd, line_shell_kind(at, b))
    if not line then
      local err = "run: " .. (qerr or "cannot quote the command")
      fail(err)
      return false, err
    end
  elseif type(cmd) == "string" and cmd ~= "" then
    line = cmd
  else
    local err = "run: empty command"
    fail(err)
    return false, err
  end
  return send_impl(line, vim.tbl_extend("force", opts, { newline = true }), at)
end

--- Run a command in a terminal.
---
--- * A **string** is typed as one shell line, exactly as given: that is the caller's own text.
--- * A **list** is an argv: every word is quoted for the terminal's shell, so file names with
---   spaces, quotes or `$(...)` stay data.
--- * With `direct = true` the command *is* the job (no shell in between), `on_exit(code)` reports
---   its exit code, and an earlier terminal of the same name is replaced.
---@param cmd string|string[]
---@param opts? Terminal.RunOpts
---@return boolean started
---@return string|nil err
---@return Terminal.Handle|nil handle # Only with `direct`
function M.run(cmd, opts)
  if opts ~= nil and type(opts) ~= "table" then
    local msg = ("run: opts must be a table, got %s"):format(type(opts))
    fail(msg)
    return false, msg
  end
  opts = opts or {}
  local b = backend()
  local at, rerr = resolved(with_run_name(opts))
  if not at then
    fail(rerr)
    return false, rerr
  end
  if opts.direct then
    if type(cmd) ~= "table" or #cmd == 0 then
      local err = "run: `direct` needs a non-empty argv list"
      fail(err)
      return false, err
    end
    for i, word in ipairs(cmd) do
      if type(word) ~= "string" or word == "" or word:find("\0", 1, true) then
        local err = ("run: argument %d must be a non-empty string without a NUL byte"):format(i)
        fail(err)
        return false, err
      end
    end
    return run_direct(b, cmd, opts, at)
  end
  return run_line(b, cmd, opts, at)
end

--- Move to the window in direction `dir` (h, j, k, l); at Neovim's edge the multiplexer around
--- it is asked to focus the neighbouring pane (`navigate.handoff`). A floating window never
--- hands off. Raises on a direction that is not h, j, k or l, or on a count that is not a number
--- from 0 up (a programmer error).
---@param dir Terminal.Direction
---@param count? integer Windows to move (default 1)
---@return "moved"|"float"|"edge"
function M.navigate(dir, count)
  if not state.ready then
    M.setup()
  end
  return require("terminal.navigate").go(dir, count)
end

--- Move a native terminal into the multiplexer so it outlives Neovim. See `terminal.pin`.
---@param target? Terminal.Target
---@param opts? Terminal.PinOpts
---@return boolean pinned
---@return string|nil err
---@return Terminal.Handle|nil handle
function M.pin(target, opts)
  return require("terminal.pin").run(host, target, opts)
end

--- Show a multiplexer terminal's screen in a read-only buffer (a *view*, not a transfer). See
--- `terminal.adopt`.
---@param target? Terminal.Target
---@return integer|nil bufnr
---@return string|nil err
function M.adopt(target)
  return require("terminal.adopt").run(host, target)
end

--- Read-only snapshot of what is going on, for health checks and bug reports.
---@return { ready: boolean, backend?: string, terminals: integer }
function M.status()
  return {
    ready = state.ready,
    backend = state.backend and state.backend.name or nil,
    terminals = state.registry:count(),
  }
end

return M
