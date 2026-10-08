---@module 'terminal.pin'
--- `pin`: move a native terminal into the multiplexer so it outlives Neovim.
---
--- It is **not** transferred: the process cannot move between a Neovim `:terminal` and a pane. The
--- native terminal is closed and the same command is started again in a pane of the multiplexer,
--- under the same name and directory. Output and shell history of the old one are gone.
---
--- Loaded by the facade (`terminal.pin(target, opts)` calls `run`); it needs the facade's internals
--- through the `host` table instead of requiring the facade back.
---@see terminal
---@see terminal.backends

local backends = require("terminal.backends")

local M = {}

---@class Terminal.PinOpts
---@field backend? "tmux"|"wezterm" Where to start it (default: tmux inside tmux, else wezterm)
---@field layout? Terminal.Layout Default "vsplit"

---@class Terminal.PinPlan
---@field name string
---@field cwd string
---@field root string
---@field handle Terminal.Handle The native terminal that is replaced
---@field backend Terminal.Backend The multiplexer that takes over
---@field spec Terminal.SpawnSpec What the pane is started with
---@field restore Terminal.SpawnSpec What starts the native terminal again if the pane cannot be

---@internal
--- The multiplexer backend a pin goes to: the one named, else the first that is usable.
---@param host Terminal.Host
---@param named? string
---@return Terminal.Backend|nil
---@return string|nil why # The named backend's reason, when it was named and is unusable
local function pick_backend(host, named)
  if named then
    return host.multiplexer(named)
  end
  for _, candidate in ipairs(backends.MULTIPLEXERS) do
    local backend = host.multiplexer(candidate)
    if backend then
      return backend, nil
    end
  end
  return nil, nil
end

---@internal
--- Everything that can be found out before the native terminal is touched: that there is one to
--- pin, a multiplexer to take it, and that the multiplexer accepts the command and answers.
---@param host Terminal.Host
---@param target? Terminal.Target
---@param opts Terminal.PinOpts
---@return Terminal.PinPlan|nil plan
---@return string|nil err
local function check(host, target, opts)
  local name, cwd_or_err, root = host.resolve(target)
  if not name then
    return nil, cwd_or_err
  end
  local handle = host.find_live(root, name)
  if not handle then
    return nil, ("pin: no terminal '%s' in this project"):format(name)
  elseif handle.backend ~= "native" then
    return nil, ("pin: terminal '%s' already lives in %s"):format(name, handle.backend)
  end
  if opts.layout ~= nil and not vim.list_contains(backends.LAYOUTS, opts.layout) then
    return nil,
      ("pin: unknown layout %s (use float, split, vsplit or tab)"):format(vim.inspect(opts.layout))
  end
  local backend, why = pick_backend(host, opts.backend)
  if not backend then
    if why then
      return nil, ("pin: backend '%s' is not available (%s)"):format(tostring(opts.backend), why)
    end
    return nil, "pin: no multiplexer backend is available (not inside tmux or WezTerm)"
  end

  local cwd = handle.cwd or root
  local spec = host.build_spec(name, cwd, root, { layout = opts.layout or "vsplit" })
  if handle.cmd ~= nil and handle.cmd ~= "" then
    spec.cmd = handle.cmd
  end
  -- What the multiplexer is known to refuse (an `env` it cannot pass on) is found out BEFORE the
  -- native terminal is touched: such a pin changes nothing.
  if backend.preflight then
    local ok, refused = backend.preflight(spec)
    if not ok then
      return nil, ("pin: terminal '%s': %s"):format(name, refused or "cannot start")
    end
  end
  -- A multiplexer that does not answer is found out now, not after the terminal is gone.
  if backend.ping then
    local up, down = backend.ping()
    if not up then
      return nil,
        ("pin: terminal '%s': %s is not reachable (%s)"):format(
          name,
          backend.name,
          down or "no answer"
        )
    end
  end

  local restore = host.build_spec(name, cwd, root, { layout = handle.layout, start_insert = false })
  restore.cmd = spec.cmd
  return {
    name = name,
    cwd = cwd,
    root = root,
    handle = handle,
    backend = backend,
    spec = spec,
    restore = restore,
  },
    nil
end

---@internal
--- Replace the native terminal by the pane. The native terminal ends BEFORE the pane starts: a
--- long-running command (a server, a watcher, anything holding a port or a lock) must not run
--- twice at the same time, and the old job needs a moment to release what it holds.
---@param host Terminal.Host
---@param plan Terminal.PinPlan
---@return Terminal.Handle|nil pane
---@return string|nil err
local function swap(host, plan)
  local closed, cerr = host.backend_of(plan.handle).close(plan.handle)
  if not closed then
    -- The native terminal is still registered (its window refused to close): a pane under the
    -- same name would replace its entry and orphan it. The pin does not happen.
    local msg = ("pin: terminal '%s': cannot end the native terminal: %s"):format(
      plan.name,
      cerr or "cannot close"
    )
    host.fail(msg)
    return nil, msg
  end
  local pane, perr = plan.backend.spawn(plan.spec)
  if pane then
    return pane, nil
  end
  -- The multiplexer failed at run time (its CLI is gone, a timeout): the user keeps a terminal.
  -- It is a new one -- the output and history of the old one are lost either way.
  local restored, rerr = host.state.backends.native.spawn(plan.restore)
  local outcome = restored and "the native terminal was started again"
    or ("the native terminal could not be started again: %s"):format(rerr or "unknown reason")
  host.fail(("pin: terminal '%s': %s (%s)"):format(plan.name, perr or "cannot start", outcome))
  return nil, perr
end

--- Restart `target` (a native terminal) as a pane.
---@param host Terminal.Host
---@param target? Terminal.Target
---@param opts? Terminal.PinOpts
---@return boolean pinned
---@return string|nil err
---@return Terminal.Handle|nil handle
function M.run(host, target, opts)
  if opts ~= nil and type(opts) ~= "table" then
    local msg = ("pin: opts must be a table, got %s"):format(type(opts))
    host.fail(msg)
    return false, msg
  end
  host.backend()
  local plan, err = check(host, target, opts or {})
  if not plan then
    host.fail(err or "pin: nothing to pin")
    return false, err
  end
  local pane, perr = swap(host, plan)
  if not pane then
    return false, perr
  end
  return true, nil, pane
end

return M
