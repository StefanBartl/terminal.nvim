---@module 'terminal.core.exec'
--- Run an external command to completion and get what it did back as data. The runner of the
--- multiplexer backends, the tmux status exporter and `:checkhealth`: they all need the same
--- "start it, wait with a timeout, never raise" wrapper, so it exists once.
---
--- Nothing here is asynchronous: the caller is blocked for at most `timeout`. Fire-and-forget
--- processes (`navigate`) and the Kitty padding restore at exit use `vim.system` directly.

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
  local code = res.code
  if code == 0 and (res.signal or 0) ~= 0 then
    -- A program that a signal ended (the OOM killer, SIGHUP at logout) did not succeed.
    code = 128 + res.signal
  end
  return { code = code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

return M
