---@module 'terminal.adopt'
--- `adopt`: a multiplexer terminal's screen in a read-only buffer -- a *view*, not a transfer.
---
--- The buffer refreshes once a second while it is visible and stops when the pane is gone. The text
--- is whatever the multiplexer reports for the pane, with control characters replaced.
---
--- Loaded by the facade (`terminal.adopt(target)` calls `run`); it needs the facade's internals
--- through the `host` table instead of requiring the facade back.
---@see terminal

local M = {}

--- Pause between two refreshes of the view. Started after a refresh ends, not on a fixed beat: a
--- multiplexer that answers slowly (the CLI has a 3 s timeout) must not pile up captures.
local REFRESH_MS = 1000

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

--- Show a multiplexer terminal's screen in a read-only buffer.
---@param host Terminal.Host
---@param target? Terminal.Target
---@return integer|nil bufnr
---@return string|nil err
function M.run(host, target)
  host.backend()
  local name, cwd_or_err, root = host.resolve(target)
  if not name then
    host.fail(cwd_or_err)
    return nil, cwd_or_err
  end
  local handle = host.state.registry:find(root, name)
  if not handle then
    local err = ("adopt: no terminal '%s' in this project"):format(name)
    host.fail(err)
    return nil, err
  end
  local b = host.backend_of(handle)
  local capture = b.capture
  if not capture then
    local err = ("adopt: terminal '%s' lives in %s, which has no pane to show"):format(
      name,
      handle.backend
    )
    host.fail(err)
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

  --- One refresh; false when the view is over (buffer gone, or the pane cannot be captured).
  local function refresh()
    if not vim.api.nvim_buf_is_valid(buf) then
      return false
    end
    local text, cerr = capture(handle)
    -- The capture blocks (up to the CLI timeout) and lets scheduled callbacks run: the buffer may
    -- have been wiped meanwhile.
    if not vim.api.nvim_buf_is_valid(buf) then
      return false
    end
    local lines = text and pane_lines(text) or { "-- " .. (cerr or "pane is gone") .. " --" }
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    return text ~= nil
  end
  refresh()

  -- A one-shot timer, armed again only after the refresh has ended: no overlapping captures, and
  -- `stop` is safe to call twice (closing a closed handle raises).
  local timer = vim.uv.new_timer()
  if timer then
    local done = false
    local function stop()
      if done then
        return
      end
      done = true
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end
    local tick
    tick = vim.schedule_wrap(function()
      if done then
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return stop()
      end
      if #vim.fn.win_findbuf(buf) > 0 and not refresh() then
        return stop()
      end
      if not done then
        timer:start(REFRESH_MS, 0, tick)
      end
    end)
    timer:start(REFRESH_MS, 0, tick)
  end
  -- Without a timer (libuv out of handles) the view still shows the screen as of now.

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  return buf, nil
end

return M
