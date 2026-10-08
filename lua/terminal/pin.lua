---@module 'terminal.pin'
--- `pin`: move a native terminal into the multiplexer so it outlives Neovim.
---
--- It is **not** transferred: the process cannot move between a Neovim `:terminal` and a pane. The
--- native terminal is closed and the same command is started again in a pane of the multiplexer,
--- under the same name and directory. Output and shell history of the old one are gone.
---
--- Loaded by the facade (`terminal.pin(target, opts)` calls `run`); it needs the facade's internals
--- through the `host` table instead of requiring the facade back.

local backends = require("terminal.backends")

local M = {}

---@class Terminal.PinOpts
---@field backend? "tmux"|"wezterm" Where to start it (default: tmux inside tmux, else wezterm)
---@field layout? Terminal.Layout Default "vsplit"

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
  opts = opts or {}
  host.backend()
  local name, cwd_or_err, root = host.resolve(target)
  if not name then
    host.fail(cwd_or_err)
    return false, cwd_or_err
  end
  local handle = host.find_live(root, name)
  local err
  if not handle then
    err = ("pin: no terminal '%s' in this project"):format(name)
  elseif handle.backend ~= "native" then
    err = ("pin: terminal '%s' already lives in %s"):format(name, handle.backend)
  end
  local target_backend, why
  if opts.backend then
    target_backend, why = host.multiplexer(opts.backend)
  else
    for _, candidate in ipairs(backends.MULTIPLEXERS) do
      target_backend = host.multiplexer(candidate)
      if target_backend then
        break
      end
    end
  end
  if not err and not target_backend then
    err = "pin: no multiplexer backend is available (not inside tmux or WezTerm)"
    if why then
      err = ("pin: backend '%s' is not available (%s)"):format(tostring(opts.backend), why)
    end
  end
  if err or not handle or not target_backend then
    err = err or "pin: nothing to pin"
    host.fail(err)
    return false, err
  end

  local cmd, cwd = handle.cmd, handle.cwd or root
  local spec = host.build_spec(name, cwd, root, { layout = opts.layout or "vsplit" })
  if cmd ~= nil and cmd ~= "" then
    spec.cmd = cmd
  end
  -- What the multiplexer is known to refuse (an `env` it cannot pass on) is found out BEFORE the
  -- native terminal is touched: such a pin changes nothing.
  if target_backend.preflight then
    local ok, refused = target_backend.preflight(spec)
    if not ok then
      host.fail(("pin: terminal '%s': %s"):format(name, refused or "cannot start"))
      return false, refused
    end
  end

  -- A multiplexer that does not answer is found out now, not after the terminal is gone.
  if target_backend.ping then
    local up, down = target_backend.ping()
    if not up then
      host.fail(
        ("pin: terminal '%s': %s is not reachable (%s)"):format(
          name,
          target_backend.name,
          down or "no answer"
        )
      )
      return false, down
    end
  end

  -- The native terminal ends BEFORE the pane starts: a long-running command (a server, a watcher,
  -- anything holding a port or a lock) must not run twice at the same time, and the old job needs
  -- a moment to release what it holds.
  local restore = host.build_spec(name, cwd, root, { layout = handle.layout, start_insert = false })
  restore.cmd = spec.cmd
  host.backend_of(handle).close(handle)
  local pinned, perr = target_backend.spawn(spec)
  if not pinned then
    -- The multiplexer failed at run time (its CLI is gone, a timeout): the user keeps a terminal.
    -- It is a new one -- the output and history of the old one are lost either way.
    local restored, rerr = host.state.backends.native.spawn(restore)
    local outcome = restored and "the native terminal was started again"
      or ("the native terminal could not be started again: %s"):format(rerr or "unknown reason")
    host.fail(("pin: terminal '%s': %s (%s)"):format(name, perr or "cannot start", outcome))
    return false, perr
  end
  return true, nil, pinned
end

return M
