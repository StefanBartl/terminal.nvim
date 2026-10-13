---@module 'terminal.core.osc'
--- The escape sequences terminal.nvim writes to the host terminal. The builders (sanitize, user_var,
--- tmux envelope) and the writer live in `lib.nvim.terminal.osc`; this module only adds the ordered
--- multi-variable payload.
---
--- The only sequence used is WezTerm's `OSC 1337 ; SetUserVar=<name>=<base64>` (also understood
--- by iTerm2): a named, per-pane variable that the terminal's own config can read. The value is
--- base64, so no byte of it can end the sequence early -- but the *name* is spliced in as is, so
--- it is validated, and text that was meant for display is sanitised before it is encoded.
---
--- Inside tmux a sequence only reaches the outer terminal when it is wrapped in tmux's DCS
--- passthrough envelope (`ESC P tmux ; <seq with every ESC doubled> ESC \`) *and* tmux has
--- `allow-passthrough on`. That is why `user_vars` wraps every sequence when asked to: a bare one
--- never reaches the outer terminal (measured, see docs/status.md#measured).

local lib = require("lib.nvim.terminal.osc")

local M = {
  sanitize = lib.sanitize,
  user_var = lib.user_var,
  wrap_tmux = lib.wrap_tmux,
}

--- Several user vars as one string (one write: the parts must not be separated by a redraw).
---@param vars { [1]: string, [2]: string }[] Ordered `{ name, value }` pairs
---@param in_tmux boolean Wrap each sequence for tmux passthrough
---@return string|nil payload
---@return string|nil err
function M.user_vars(vars, in_tmux)
  local parts = {}
  for _, pair in ipairs(vars) do
    local seq, err = lib.user_var(pair[1], pair[2])
    if not seq then
      return nil, err
    end
    parts[#parts + 1] = lib.wrap(seq, in_tmux)
  end
  return table.concat(parts), nil
end

return M
