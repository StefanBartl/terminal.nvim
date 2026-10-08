---@module 'terminal.core.exec'
--- Run an external command to completion and get what it did back as data. The one place in the
--- plugin that calls `vim.system(...):wait()`: the multiplexer backends, the tmux status exporter
--- and `:checkhealth` all need the same "start it, wait with a timeout, never raise" wrapper, so
--- it exists once.
---
--- Nothing here is asynchronous: the caller is blocked for at most `timeout`. Fire-and-forget
--- processes (`navigate`, Kitty padding) use `vim.system` with a callback directly.

local M = {}

---@class Terminal.ExecResult
---@field code integer Exit code; 127 when the command could not be started, 124 on a timeout
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
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

return M
