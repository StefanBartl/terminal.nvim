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
---@field deps Terminal.ContextDeps

---@type Terminal.State
local state = {
  ready = false,
  registry = registry_mod.new(),
  backends = {},
  backend = nil,
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
---@param extra? { layout?: Terminal.Layout, start_insert?: boolean, on_exit_cb?: fun(code: integer) }
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
    on_exit = config.get("on_exit"),
    on_exit_cb = extra.on_exit_cb,
  }
end

--- Set the plugin up. Safe to call again: the options are replaced, the terminals stay.
---@param opts Terminal.Config|table|nil
---@return nil
function M.setup(opts)
  config.setup(opts)

  local native = require("terminal.backends.native").new(state.registry)
  state.backends = { native = native }
  local env = environment()
  local wezterm = require("terminal.backends.wezterm")
  local wezterm_ok, wezterm_reason = wezterm.available(env)
  if wezterm_ok then
    state.backends.wezterm = wezterm.new(state.registry)
  end
  local tmux = require("terminal.backends.tmux")
  local tmux_ok, tmux_reason = tmux.available(env)
  if tmux_ok then
    state.backends.tmux = tmux.new(state.registry)
  end
  local name, note = backends.resolve(config.get("backend"), env, state.backends)
  local wanted = config.get("backend")
  if note and wanted == "wezterm" and wezterm_reason then
    note = ("backend 'wezterm' is not available (%s) -- using native"):format(wezterm_reason)
  elseif note and wanted == "tmux" and tmux_reason then
    note = ("backend 'tmux' is not available (%s) -- using native"):format(tmux_reason)
  end
  state.backend = state.backends[name]
  if note then
    vim.schedule(function()
      notify.warn(note)
    end)
  end

  state.ready = true
  require("terminal.bindings").setup()
  require("terminal.status").setup(config.get_all())
  require("terminal.navigate").setup(config.get_all(), env)
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

--- Show the terminal (creating it when needed) and focus it.
---
--- With `focus = false` the terminal appears but the window that was current stays current.
---@param target Terminal.Target|nil
---@return Terminal.Handle|nil handle
---@return string|nil err
function M.open(target)
  local b = backend()
  local name, cwd, root = resolve(target)
  local focus = not (target and target.focus == false)
  local layout = target and target.layout or nil
  local previous = vim.api.nvim_get_current_win()
  -- Without focus the terminal must not grab Insert mode either; nil = the configured default.
  local start_insert = nil
  if not focus then
    start_insert = false
  end

  local handle = find_live(root, name)
  if handle and not b.show and b.visible and not b.visible(handle) then
    -- A backend that cannot show a hidden terminal again (a pane the user closed): start a new one.
    b.close(handle)
    handle = nil
  end
  if handle then
    if b.visible and b.visible(handle) then
      if focus then
        b.focus(handle)
      end
      return handle, nil
    end
    local spec = build_spec(name, cwd, root, { layout = layout, start_insert = start_insert })
    local ok, err = b.show(handle, spec)
    if not ok then
      fail(("terminal '%s': %s"):format(name, err or "cannot show"))
      return nil, err
    end
  else
    local stale = state.registry:find(root, name)
    if stale then
      b.close(stale)
    end
    local spec = build_spec(name, cwd, root, { layout = layout, start_insert = start_insert })
    local err
    handle, err = b.spawn(spec)
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

--- Hide the terminal's window; the job keeps running.
---@param target Terminal.Target|nil
---@return boolean hidden
function M.hide(target)
  local b = backend()
  local name, _, root = resolve(target)
  local handle = find_live(root, name)
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
  local b = backend()
  local name, _, root = resolve(target)
  local handle = find_live(root, name)
  if handle and b.visible and b.visible(handle) then
    if b.focused and b.focused(handle) then
      M.hide(target)
    else
      b.focus(handle)
      if config.get("start_insert") then
        vim.cmd("startinsert")
      end
    end
    return
  end
  M.open(target)
end

--- Stop the terminal's job and remove it.
---@param target Terminal.Target|nil
---@return boolean closed
function M.close(target)
  local b = backend()
  local name, _, root = resolve(target)
  local handle = state.registry:find(root, name)
  if not handle then
    return false
  end
  local ok, err = b.close(handle)
  if not ok then
    fail(("terminal '%s': %s"):format(name, err or "cannot close"))
  end
  return ok
end

--- The terminals of the current project (all projects with `all = true`).
---@param all? boolean
---@return Terminal.Handle[]
function M.list(all)
  local b = backend()
  b.list() -- prunes handles whose buffer is gone
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
  local b = backend()
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
  local ok, serr = b.send(handle, payload)
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
      b.close(old)
    end
    local focus = opts.focus ~= false
    local spec = build_spec(name, opts.cwd or cwd, root, {
      layout = opts.layout,
      start_insert = focus and opts.start_insert ~= false,
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
    line, qerr = quote.argv_to_line(cmd, quote.shell_kind(shell_executable()))
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
