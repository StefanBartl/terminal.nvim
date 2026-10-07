---@module 'terminal'
--- Public facade of terminal.nvim: named terminals, the same API for every backend.
---
--- Every function resolves the target the same way: the *project root* (see
--- `terminal.core.context`) plus a *name* identify a terminal. `toggle()` without a name uses the
--- configured default name, `toggle({ count = 3 })` uses the terminal "3". Failures are returned
--- as `nil, err` and also reported to the user; nothing raises.

local config = require("terminal.config")
local context = require("terminal.core.context")
local backends = require("terminal.backends")
local registry_mod = require("terminal.core.registry")
local quote = require("terminal.core.quote")
local notify = require("lib.nvim.notify").create("[terminal]")

local M = {}

---@class Terminal.State
---@field ready boolean
---@field registry Terminal.Registry
---@field backends table<string, Terminal.Backend>
---@field backend Terminal.Backend|nil
---@field env table<string, string|nil> The environment `setup()` looked at
---@field unavailable table<string, string> Multiplexer backends found unusable, with the reason
---@field deps Terminal.ContextDeps

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

---@class Terminal.Target
---@field name? string Terminal name; wins over `count`
---@field count? integer `3` -> terminal "3"; 0/nil -> the default name
---@field layout? Terminal.Layout Overrides the configured layout for this call
---@field focus? boolean Take focus (default true)

---@internal
---@return table<string, string|nil>
local function environment()
  return {
    TMUX = vim.env.TMUX,
    WEZTERM_PANE = vim.env.WEZTERM_PANE,
    TMUX_PANE = vim.env.TMUX_PANE,
  }
end

---@internal
--- The configured shell as a job command: nil = the editor's 'shell'.
---@return string|string[]|nil
local function shell_command()
  local shell = config.get("shell")
  if type(shell) == "table" then
    return #shell > 0 and shell or nil
  end
  if type(shell) == "string" and shell ~= "" then
    return shell
  end
  return nil
end

---@internal
--- The shell executable name, for quoting decisions.
---@return string
local function shell_executable()
  local cmd = shell_command()
  if type(cmd) == "table" then
    return cmd[1]
  end
  return cmd or vim.o.shell
end

---@internal
---@param err string
---@return nil
local function fail(err)
  vim.schedule(function()
    notify.error(err)
  end)
end

---@internal
---@param extra? { layout?: Terminal.Layout, start_insert?: boolean, focus?: boolean, on_exit_cb?: fun(code: integer) }
---@param name string
---@param cwd string
---@param root string
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
    cmd = shell_command(),
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
---@param name "wezterm"|"tmux"
---@return Terminal.Backend|nil
---@return string|nil reason Why it is not usable
local function multiplexer(name)
  if name ~= "wezterm" and name ~= "tmux" then
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
---@param opts Terminal.Config|table|nil
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
  -- $PATH, which costs tens of milliseconds on Windows -- not something every startup pays.
  local wanted = config.get("backend")
  local reason
  if wanted == "wezterm" or wanted == "tmux" then
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
        require("terminal.status").setup(config.get_all())
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
---@return { visible: boolean, focused: boolean }|nil
local function probe(b, handle)
  if b.probe then
    return (b.probe(handle))
  end
  local visible = b.visible ~= nil and b.visible(handle) == true
  return { visible = visible, focused = visible and b.focused ~= nil and b.focused(handle) == true }
end

---@internal
--- Resolve target name, working directory and project root for one call.
---@param target Terminal.Target|nil
---@return string name
---@return string cwd
---@return string root
local function resolve(target)
  target = target or {}
  local cwd, root = context.resolve(config.get("cwd"), state.deps)
  local name = target.name or context.name_for_count(target.count, config.get("default_name"))
  return name, cwd, root
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

---@internal
--- `open`, optionally with what the caller already learned about the terminal (`toggle` has
--- probed it): `known = { handle, where }`, so the multiplexer is not asked a second time.
---@param target Terminal.Target|nil
---@param known? { handle: Terminal.Handle, where: { visible: boolean, focused: boolean }|nil }
---@return Terminal.Handle|nil handle
---@return string|nil err
local function open_impl(target, known)
  local default = backend()
  local name, cwd, root = resolve(target)
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
  if handle then
    if where == nil or where.visible then
      if focus then
        local ok, ferr = b.focus(handle)
        if not ok then
          fail(("terminal '%s': %s"):format(name, ferr or "cannot focus"))
        end
      end
      return handle, nil
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
---@return Terminal.Handle|nil handle
---@return string|nil err
function M.open(target)
  return open_impl(target, nil)
end

--- Hide the terminal's window; the job keeps running.
---@param target Terminal.Target|nil
---@return boolean hidden
function M.hide(target)
  backend()
  local name, _, root = resolve(target)
  local handle = find_live(root, name)
  local b = handle and backend_of(handle)
  if not handle or not b.hide then
    return false
  end
  local ok, err = b.hide(handle)
  if not ok then
    fail(("terminal '%s': %s"):format(name, err or "cannot hide"))
  end
  return ok
end

--- Toggle: focus when it is visible elsewhere, hide when it has focus, show when it is hidden,
--- create when it does not exist.
---@param target Terminal.Target|nil
---@return nil
function M.toggle(target)
  backend()
  local name, _, root = resolve(target)
  local handle = find_live(root, name)
  local b = handle and backend_of(handle)
  local where = handle and probe(b, handle)
  if handle and (where == nil or where.visible) then
    if where and where.focused then
      M.hide(target)
    else
      local ok, err = b.focus(handle)
      if not ok then
        fail(("terminal '%s': %s"):format(name, err or "cannot focus"))
      end
      -- Insert mode belongs to a Neovim window; a multiplexer pane takes its own input, and
      -- Neovim must stay in Normal mode in the pane the user just left.
      if ok and handle.backend == "native" and config.get("start_insert") then
        vim.cmd("startinsert")
      end
    end
    return
  end
  open_impl(target, handle and { handle = handle, where = where } or nil)
end

--- Stop the terminal's job and remove it.
---@param target Terminal.Target|nil
---@return boolean closed
function M.close(target)
  backend()
  local name, _, root = resolve(target)
  local handle = state.registry:find(root, name)
  if not handle then
    return false
  end
  local ok, err = backend_of(handle).close(handle)
  if not ok then
    fail(("terminal '%s': %s"):format(name, err or "cannot close"))
  end
  return ok
end

--- The terminals of the current project (all projects with `all = true`).
---@param all? boolean
---@return Terminal.Handle[]
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

--- Send text to a terminal as typed input. Nothing is executed unless `newline` is true (or the
--- text itself ends in a line ending). The terminal is created when it does not exist yet.
---@param text string
---@param opts? Terminal.Target & { newline?: boolean }
---@return boolean sent
---@return string|nil err
function M.send(text, opts)
  opts = opts or {}
  if type(text) ~= "string" then
    return false, "text must be a string"
  end
  backend()
  local target = vim.tbl_extend("keep", { name = opts.name or config.get("run.name") }, opts)
  if opts.focus == nil then
    target.focus = false
  end
  local handle, err = M.open(target)
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

---@class Terminal.RunOpts: Terminal.Target
---@field direct? boolean Start the command as the terminal's job itself (needs an argv list)
---@field on_exit? fun(code: integer) With `direct`: called once with the exit code
---@field cwd? string With `direct`: working directory of the job (default: the project's)
---@field title? string With `direct`: window title of a float (default: the terminal's name)
---@field float? table With `direct`: overrides of the `float` config for this window
---@field close? "always"|"success"|"never" With `direct`: remove the terminal when the job ends (default "never")
---@field start_insert? boolean With `direct`: enter terminal mode when it has focus (default true)
---@field env? table<string, string> With `direct`: extra environment for the job
---@field on_open? fun(handle: Terminal.Handle) With `direct`: called once the window and job exist (set buffer keymaps here)

---@internal
--- The quoting family for words typed into terminal `name`. A native terminal runs the configured
--- shell (or Neovim's 'shell'); so does a multiplexer pane when `shell` is configured. Without
--- one the pane runs the *multiplexer's* default shell -- unknown here, and not necessarily the
--- shell Neovim uses -- so only words that mean the same in every shell are accepted
--- ("portable"); anything else is refused instead of quoted for the wrong shell.
---@param root string
---@param name string
---@param default Terminal.Backend
---@return Terminal.ShellKind|"portable"
local function line_shell_kind(root, name, default)
  local existing = find_live(root, name)
  local owner = existing and existing.backend or default.name
  if shell_command() ~= nil or owner == "native" then
    return quote.shell_kind(shell_executable())
  end
  return "portable"
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
---@return Terminal.Handle|nil handle Only with `direct`
function M.run(cmd, opts)
  opts = opts or {}
  local b = backend()
  local target = vim.tbl_extend("keep", { name = opts.name or config.get("run.name") }, opts)

  if opts.direct then
    if type(cmd) ~= "table" or #cmd == 0 then
      local err = "run: `direct` needs a non-empty argv list"
      fail(err)
      return false, err
    end
    local name, cwd, root = resolve(target)
    local old = state.registry:find(root, name)
    if old then
      backend_of(old).close(old)
    end
    local focus = opts.focus ~= false
    local spec = build_spec(name, opts.cwd or cwd, root, {
      layout = opts.layout,
      start_insert = focus and opts.start_insert ~= false,
      focus = focus,
      on_exit_cb = opts.on_exit,
    })
    spec.cmd = cmd
    spec.title = opts.title
    if opts.float then
      spec.float = vim.tbl_extend("force", spec.float or {}, opts.float)
    end
    if opts.env then
      spec.env = vim.tbl_extend("force", spec.env or {}, opts.env)
    end
    local close_modes = { always = "close", success = "close_on_success", never = "keep" }
    spec.on_exit = close_modes[opts.close or "never"] or "keep"
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
      pcall(opts.on_open, handle)
    end
    return true, nil, handle
  end

  local line = cmd
  if type(cmd) == "table" then
    local qerr
    local name, _, root = resolve(target)
    line, qerr = quote.argv_to_line(cmd, line_shell_kind(root, name, b))
    if not line then
      fail("run: " .. qerr)
      return false, qerr
    end
  elseif type(cmd) ~= "string" or cmd == "" then
    local err = "run: empty command"
    fail(err)
    return false, err
  end
  target.newline = true
  return M.send(line, target)
end

--- Move to the window in direction `dir` (h, j, k, l); at Neovim's edge the multiplexer around
--- it is asked to focus the neighbouring pane (`navigate.handoff`). A floating window never
--- hands off.
---@param dir Terminal.Direction
---@param count? integer Windows to move (default 1)
---@return "moved"|"float"|"edge"
function M.navigate(dir, count)
  if not state.ready then
    M.setup()
  end
  return require("terminal.navigate").go(dir, count)
end

---@class Terminal.PinOpts
---@field backend? "tmux"|"wezterm" Where to start it (default: tmux inside tmux, else wezterm)
---@field layout? Terminal.Layout Default "vsplit"

--- Move a native terminal into the multiplexer so it outlives Neovim.
---
--- It is **not** transferred: the process cannot move between a Neovim `:terminal` and a pane. The
--- native terminal is closed and the same command is started again in a pane of the multiplexer,
--- under the same name and directory. Output and shell history of the old one are gone.
---@param target? Terminal.Target
---@param opts? Terminal.PinOpts
---@return boolean pinned
---@return string|nil err
---@return Terminal.Handle|nil handle
function M.pin(target, opts)
  opts = opts or {}
  backend()
  local name, _, root = resolve(target)
  local handle = find_live(root, name)
  local err
  if not handle then
    err = ("pin: no terminal '%s' in this project"):format(name)
  elseif handle.backend ~= "native" then
    err = ("pin: terminal '%s' already lives in %s"):format(name, handle.backend)
  end
  local target_backend, why
  if opts.backend then
    target_backend, why = multiplexer(opts.backend)
  else
    target_backend = multiplexer("tmux") or multiplexer("wezterm")
  end
  if not err and not target_backend then
    err = "pin: no multiplexer backend is available (not inside tmux or WezTerm)"
    if why then
      err = ("pin: backend '%s' is not available (%s)"):format(tostring(opts.backend), why)
    end
  end
  if err then
    fail(err)
    return false, err
  end

  local cmd, cwd = handle.cmd, handle.cwd or root
  local spec = build_spec(name, cwd, root, { layout = opts.layout or "vsplit" })
  if cmd ~= nil and cmd ~= "" then
    spec.cmd = cmd
  end
  -- What the multiplexer is known to refuse (an `env` it cannot pass on) is found out BEFORE the
  -- native terminal is touched: such a pin changes nothing.
  if target_backend.preflight then
    local ok, refused = target_backend.preflight(spec)
    if not ok then
      local msg = ("pin: terminal '%s': %s"):format(name, refused or "cannot start")
      fail(msg)
      return false, refused
    end
  end

  -- The native terminal ends BEFORE the pane starts: a long-running command (a server, a watcher,
  -- anything holding a port or a lock) must not run twice at the same time, and the old job needs
  -- a moment to release what it holds.
  local restore = build_spec(name, cwd, root, { layout = handle.layout, start_insert = false })
  restore.cmd = spec.cmd
  backend_of(handle).close(handle)
  local pinned, perr = target_backend.spawn(spec)
  if not pinned then
    -- The multiplexer failed at run time (its CLI is gone, a timeout): the user keeps a terminal.
    -- It is a new one -- the output and history of the old one are lost either way.
    state.backends.native.spawn(restore)
    fail(
      ("pin: terminal '%s': %s (the native terminal was started again)"):format(
        name,
        perr or "cannot start"
      )
    )
    return false, perr
  end
  return true, nil, pinned
end

---@internal
--- Text from a multiplexer pane made safe for a buffer: no control characters.
---@param text string
---@return string[]
local function pane_lines(text)
  local lines = {}
  for _, line in ipairs(vim.split(text, string.char(10), { plain = true })) do
    -- Carriage returns vanish, every other control character becomes `?`.
    lines[#lines + 1] = (
      line:gsub("%c", function(c)
        return c:byte() == 13 and "" or "?"
      end)
    )
  end
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  return lines
end

--- Show a multiplexer terminal's screen in a read-only buffer (a *view*, not a transfer).
---
--- The buffer refreshes once a second while it is visible and stops when the pane is gone. The
--- text is whatever the multiplexer reports for the pane, with control characters replaced.
---@param target? Terminal.Target
---@return integer|nil bufnr
---@return string|nil err
function M.adopt(target)
  backend()
  local name, _, root = resolve(target)
  local handle = state.registry:find(root, name)
  local b = handle and backend_of(handle)
  local err
  if not handle then
    err = ("adopt: no terminal '%s' in this project"):format(name)
  elseif not b.capture then
    err = ("adopt: terminal '%s' lives in %s, which has no pane to show"):format(
      name,
      handle.backend
    )
  end
  if err then
    fail(err)
    return nil, err
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  pcall(
    vim.api.nvim_buf_set_name,
    buf,
    ("terminal://%s/%s/%s"):format(handle.backend, handle.pane, name)
  )

  local function refresh()
    if not vim.api.nvim_buf_is_valid(buf) then
      return false
    end
    local text, cerr = b.capture(handle)
    local lines = text and pane_lines(text) or { "-- " .. (cerr or "pane is gone") .. " --" }
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    return text ~= nil
  end
  refresh()

  local timer = vim.uv.new_timer()
  timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        return
      end
      if #vim.fn.win_findbuf(buf) > 0 and not refresh() then
        timer:stop()
        timer:close()
      end
    end)
  )
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  return buf, nil
end

--- Read-only snapshot of what is going on, for health checks and bug reports.
---@return { ready: boolean, backend: string|nil, terminals: integer }
function M.status()
  return {
    ready = state.ready,
    backend = state.backend and state.backend.name or nil,
    terminals = state.registry:count(),
  }
end

return M
