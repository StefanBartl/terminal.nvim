---@module 'terminal.core.exec'
--- Run an external command to completion and get what it did back as data. The runner of the
--- multiplexer backends, the tmux status exporter and `:checkhealth`: they all need the same
--- "start it, wait with a timeout, never raise" wrapper, so it exists once.
---
--- `run` blocks the caller for at most `timeout`; `spawn` does not block and reports the same
--- result table from the main loop when the process ends. Fire-and-forget processes (`navigate`)
--- and the Kitty padding restore at exit use `vim.system` directly.

-- Not `lib.nvim.cross.run_argv`: its timeout kills the whole process tree with a grace period
-- (measured on Windows: a 300 ms limit took 1.2 s to return), and `run` blocks the editor. The
-- result codes below are the same ones (124, 128 + signal).
local M = {}

---@class Terminal.ExecResult
---@field code integer Exit code; 127 when the command could not be started, 124 on a timeout, 128 + the signal when a signal ended it
---@field stdout string
---@field stderr string The program's stderr, or why it could not be started (code 127)

---@class Terminal.ExecOpts
---@field stdin? string Text written to the program's standard input
---@field timeout? integer Milliseconds (default `DEFAULT_TIMEOUT_MS`)

--- How long a command may take unless the caller names its own limit. A local multiplexer answers
--- in milliseconds; three seconds is where a hung one stops being worth waiting for.
M.DEFAULT_TIMEOUT_MS = 3000

--- Run `argv` (never a shell string) and wait for it.
---@param argv string[]
---@param opts? Terminal.ExecOpts
---@return Terminal.ExecResult
function M.run(argv, opts)
  opts = opts or {}
  local ok, res = pcall(function()
    return vim
      .system(argv, {
        text = true,
        stdin = opts.stdin,
        timeout = opts.timeout or M.DEFAULT_TIMEOUT_MS,
      })
      :wait()
  end)
  if not ok then
    return { code = 127, stdout = "", stderr = tostring(res) }
  end
  if res == nil then
    -- `wait()` gives nothing when the process was not reaped in time after the kill (a very
    -- short timeout, or a child that survives SIGKILL for the whole timeout again).
    return { code = 124, stdout = "", stderr = "timed out" }
  end
  return M.result(res)
end

--- The result table for a finished `vim.system` object.
---@param res vim.SystemCompleted
---@return Terminal.ExecResult
function M.result(res)
  local code = res.code
  if code == 0 and (res.signal or 0) ~= 0 then
    -- A program that a signal ended (the OOM killer, SIGHUP at logout) did not succeed.
    code = 128 + res.signal
  end
  return { code = code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

--- How long after the timeout a program that ignored the polite stop (SIGTERM) is killed for good.
--- `vim.system` only asks; without this a program that ignores it would keep `spawn`'s callback away
--- for ever, and whoever allows one process at a time would never start another.
local KILL_GRACE_MS = 1000

--- Start `argv` (never a shell string) without waiting. `on_done` gets the same result as `run`,
--- on the main loop (never inside a fast event), also when the command could not be started.
---@param argv string[]
---@param opts? Terminal.ExecOpts
---@param on_done fun(res: Terminal.ExecResult)
---@return vim.SystemObj|nil process # nil when it could not be started
function M.spawn(argv, opts, on_done)
  opts = opts or {}
  local timeout = opts.timeout or M.DEFAULT_TIMEOUT_MS
  local finished = false
  local timer = vim.uv.new_timer()
  local function stop_timer()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  local proc
  local ok, started = pcall(
    vim.system,
    argv,
    { text = true, stdin = opts.stdin, timeout = timeout },
    function(res)
      finished = true
      stop_timer()
      vim.schedule(function()
        on_done(M.result(res))
      end)
    end
  )
  if not ok then
    stop_timer()
    vim.schedule(function()
      on_done({ code = 127, stdout = "", stderr = tostring(started) })
    end)
    return nil
  end
  proc = started
  if timer then
    timer:start(timeout + KILL_GRACE_MS, 0, function()
      stop_timer()
      if not finished then
        pcall(proc.kill, proc, 9)
      end
    end)
  end
  return proc
end

return M
