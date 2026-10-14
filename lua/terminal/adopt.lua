---@module 'terminal.adopt'
--- `adopt`: a multiplexer terminal's screen in a read-only buffer -- a *view*, not a transfer.
---
--- The buffer refreshes once a second while it is visible and stops when the pane is gone. The
--- first picture is taken synchronously; the refreshes do not block the editor. The text
--- is whatever the multiplexer reports for the pane, with control characters replaced.
---
--- Loaded by the facade (`terminal.adopt(target)` calls `run`); it needs the facade's internals
--- through the `host` table instead of requiring the facade back.
---@see terminal

local M = {}

--- Pause between two refreshes of the view. Started after a refresh ends, not on a fixed beat: a
--- multiplexer that answers slowly (the CLI has a 3 s timeout) must not pile up captures. The pause is
--- `adopt.refresh_ms` (1000 by default).
---@return integer
local function refresh_ms()
  return require("terminal.core.exec").configured("adopt.refresh_ms", 1000)
end

---@internal
--- The views that have a refresh timer: buffer -> the function that stops it. Kept so that
--- `close_all` can reach what `run` started; an entry goes when its view ends.
---@type table<integer, fun()>
local views = {}

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

  -- Show the buffer first: "no room for a split" (E36) must not leave a buffer and a timer behind.
  local origin = vim.api.nvim_get_current_win()
  local shown, serr = pcall(function()
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
  end)
  if not shown then
    if vim.api.nvim_get_current_win() ~= origin then
      pcall(function()
        vim.cmd("close")
      end)
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    local err = ("adopt: cannot open a window for the view: %s"):format(tostring(serr))
    host.fail(err)
    return nil, err
  end

  --- Show a capture; false when the view is over (buffer gone, or the pane cannot be captured).
  ---@param text string|nil
  ---@param cerr string|nil
  ---@return boolean
  local function apply(text, cerr)
    if not vim.api.nvim_buf_is_valid(buf) then
      return false
    end
    local lines = text and pane_lines(text) or { "-- " .. (cerr or "pane is gone") .. " --" }
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    return text ~= nil
  end

  -- The first picture is taken synchronously, so the buffer has content when `adopt` returns (a
  -- command the user just typed); every later refresh runs without blocking the editor.
  apply(capture(handle))

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
      views[buf] = nil
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end
    views[buf] = stop
    local tick
    local function rearm()
      if not done then
        timer:start(refresh_ms(), 0, tick)
      end
    end
    tick = vim.schedule_wrap(function()
      if done then
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return stop()
      end
      if #vim.fn.win_findbuf(buf) == 0 then
        return rearm()
      end
      if b.capture_async then
        b.capture_async(handle, function(text, cerr)
          if done then
            return
          end
          if not apply(text, cerr) then
            return stop()
          end
          rearm()
        end)
      else
        if not apply(capture(handle)) then
          return stop()
        end
        rearm()
      end
    end)
    timer:start(refresh_ms(), 0, tick)
  end
  -- Without a timer (libuv out of handles) the view still shows the screen as of now.

  return buf, nil
end

--- End every view: stop its timer and wipe its buffer. Idempotent; nothing happens to the panes.
---@return integer count Views that were ended
function M.close_all()
  local count = 0
  for buf, stop in pairs(vim.tbl_extend("force", {}, views)) do
    count = count + 1
    stop()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  return count
end

return M
