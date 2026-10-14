---@module 'terminal.events'
--- The `User` events terminal.nvim fires for other plugins (a command log, a statusline, a notifier),
--- the counterpart of what it listens to from sessions.nvim. Any number of listeners, nothing to
--- register. A listener that raises is reported by Neovim itself and does not change what the firing
--- call returns.
---
---   `TerminalCommandPost`  a command was started in a terminal: a line typed *and executed*
---                          (`send` with `newline`, `run` without `direct`), or a `direct` job.
---                          `data = { name, backend, command, direct }`
---   `TerminalExitPost`     a `direct` job ended (native terminals report their exit code; a
---                          multiplexer pane outlives Neovim and reports none).
---                          `data = { name, backend, command, exit_code }`
---
--- `command` is the text as typed, or the argv joined with spaces for a `direct` job: for reading,
--- not for running again.
---@see terminal.sessions

local M = {}

---@param event "TerminalCommandPost"|"TerminalExitPost"
---@param data table
---@return nil
function M.fire(event, data)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = event, modeline = false, data = data })
end

--- A command (line or argv) as one display string.
---@param cmd string|string[]
---@return string
function M.text(cmd)
  if type(cmd) == "table" then
    return table.concat(cmd, " ")
  end
  return cmd
end

return M
