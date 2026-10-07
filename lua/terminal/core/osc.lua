---@module 'terminal.core.osc'
--- Pure builders for the escape sequences terminal.nvim writes to the host terminal.
---
--- The only sequence used is WezTerm's `OSC 1337 ; SetUserVar=<name>=<base64>` (also understood
--- by iTerm2): a named, per-pane variable that the terminal's own config can read. The value is
--- base64, so no byte of it can end the sequence early -- but the *name* is spliced in as is, so
--- it is validated, and text that was meant for display is sanitised before it is encoded.
---
--- Inside tmux a sequence only reaches the outer terminal when it is wrapped in tmux's DCS
--- passthrough envelope (`ESC P tmux ; <seq with every ESC doubled> ESC \`) *and* tmux has
--- `allow-passthrough on`. Measured 2026-10-07: a bare sequence never arrives, a wrapped one
--- arrives only with the option on.

local M = {}

local ESC = "\27"
local BEL = "\7"

--- Make text safe to show: every control character (C0, DEL) becomes `?`, then the result is
--- cut to at most `max` bytes without splitting a UTF-8 character.
---@param s any
---@param max? integer Byte limit (default 200)
---@return string
function M.sanitize(s, max)
  max = max or 200
  if type(s) ~= "string" then
    s = tostring(s == nil and "" or s)
  end
  s = s:gsub("[%z\1-\31\127]", "?")
  if #s <= max then
    return s
  end
  local cut = max
  -- Step back over UTF-8 continuation bytes (10xxxxxx) so a character is not cut in half.
  while cut > 0 do
    local b = s:byte(cut + 1)
    if b and b >= 0x80 and b < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  return s:sub(1, cut)
end

--- One `SetUserVar` sequence.
---@param name string `[A-Za-z0-9_]+`
---@param value string Any bytes; encoded as base64
---@return string|nil sequence
---@return string|nil err
function M.user_var(name, value)
  if type(name) ~= "string" or not name:find("^[%w_]+$") then
    return nil, "invalid user-var name"
  end
  if type(value) ~= "string" then
    return nil, "user-var value must be a string"
  end
  return ("%s]1337;SetUserVar=%s=%s%s"):format(ESC, name, vim.base64.encode(value), BEL), nil
end

--- Wrap a sequence in tmux's passthrough envelope.
---@param seq string
---@return string
function M.wrap_tmux(seq)
  return ESC .. "Ptmux;" .. seq:gsub(ESC, ESC .. ESC) .. ESC .. "\\"
end

--- Several user vars as one string (one write: the parts must not be separated by a redraw).
---@param vars { [1]: string, [2]: string }[] Ordered `{ name, value }` pairs
---@param in_tmux boolean Wrap each sequence for tmux passthrough
---@return string|nil payload
---@return string|nil err
function M.user_vars(vars, in_tmux)
  local parts = {}
  for _, pair in ipairs(vars) do
    local seq, err = M.user_var(pair[1], pair[2])
    if not seq then
      return nil, err
    end
    parts[#parts + 1] = in_tmux and M.wrap_tmux(seq) or seq
  end
  return table.concat(parts), nil
end

return M
