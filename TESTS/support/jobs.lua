-- TESTS/support/jobs.lua -- commands the specs run as terminal jobs.
--
-- Interactive shells cannot be used here: in a headless Neovim on Windows a terminal job's stdin
-- is already closed, so cmd.exe / pwsh exit at once (measured 2026-10-07). A long-running
-- non-interactive program stands in for "a terminal that is alive"; commands that must have an
-- exit code use a one-line program with a known code.

local M = {}

local is_windows = vim.fn.has("win32") == 1

--- A job that stays alive for a minute without reading stdin.
---@return string[]
function M.sleeper()
  if is_windows then
    return { "ping", "-n", "60", "127.0.0.1" }
  end
  return { "sleep", "60" }
end

--- A job that exits at once with `code`.
---@param code integer
---@return string[]
function M.exit_with(code)
  if is_windows then
    return { "cmd", "/c", "exit", tostring(code) }
  end
  return { "sh", "-c", "exit " .. code }
end

--- A job that ignores TERM and HUP, so `jobstop` cannot end it and Neovim has to kill it after
--- its own grace period. It prints `ready` once the signals are ignored: stopping it earlier
--- would simply kill the shell. POSIX only -- `nil` where there is no `sh` or no signals, so a
--- spec that needs it is registered only when this returns a command.
---@return string[]|nil
function M.stubborn()
  if is_windows or vim.fn.executable("sh") ~= 1 then
    return nil
  end
  return { "sh", "-c", 'trap "" TERM HUP; echo ready; while :; do sleep 1; done' }
end

--- Whether the terminal buffer `bufnr` shows `text` somewhere.
---@param bufnr integer
---@param text string
---@return boolean
function M.shows(bufnr, text)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n"):find(text, 1, true) ~= nil
end

--- Whether the operating system still runs the process `pid`. Ask the process itself: `jobwait`
--- on the channel of a terminal that was closed answers the same whether the process lives or
--- not, so it cannot show that a job was really stopped.
---@param pid integer
---@return boolean
function M.process_alive(pid)
  return vim.uv.kill(pid, 0) == 0
end

--- Wait until `pred()` is true (up to `ms`).
---@param pred fun(): boolean
---@param ms? integer
---@return boolean
function M.wait(pred, ms)
  return vim.wait(ms or 5000, pred, 20)
end

--- Windows only: Neovim 0.12's ConPTY teardown races. A terminal that is closed within a few
--- hundred milliseconds of a resize (show/hide into another layout) or of another terminal job
--- ending takes the whole editor down (0xC0000005, measured 2026-10-07; 300-500 ms of distance
--- never crashed). Specs call `settle()` before they close or hide a terminal that has just
--- been moved. Elsewhere it returns at once.
---@param ms? integer
---@return nil
function M.settle(ms)
  if is_windows then
    vim.wait(ms or 400)
  end
end

--- Run `fn` with `nvim_chan_send` replaced by a recorder; returns what was sent.
--- A real send into a headless terminal job on Windows hangs the editor (stdin of the job is
--- closed, measured 2026-10-07), so the specs check what *would* be written; the live path is
--- covered by TESTS/live/ in a real UI.
---@param fn fun()
---@return { job: integer, text: string }[]
function M.record_sends(fn)
  local sent = {}
  local original = vim.api.nvim_chan_send
  -- Test double: records what would be sent to the job instead of writing to it.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_chan_send = function(job, text)
    sent[#sent + 1] = { job = job, text = text }
  end
  local ok, err = pcall(fn)
  vim.api.nvim_chan_send = original
  if not ok then
    error(err, 0)
  end
  return sent
end

--- Run `fn(messages)` with `vim.notify` replaced by a recorder and return what was shown. The
--- recorder stays in place while `fn` runs, so `fn` can wait for a scheduled message; it is
--- restored when `fn` ends, also when it raises.
---@param fn fun(messages: string[])
---@return string[] messages
function M.capture_notify(fn)
  local messages = {}
  local original = vim.notify
  -- Test double: captures what would be shown to the user; restored below.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    messages[#messages + 1] = msg
  end
  local ok, err = pcall(fn, messages)
  vim.notify = original
  if not ok then
    error(err, 0)
  end
  return messages
end

--- Close every terminal of `registry` through `backend` and reset the window layout. A terminal
--- that `close` could not remove (a spec left 'winfixbuf' on its window, say) is dropped by force:
--- nothing may leak into the next spec.
---@param backend Terminal.Backend
---@param registry Terminal.Registry
---@return nil
function M.cleanup(backend, registry)
  for _, h in ipairs(registry:list()) do
    M.settle()
    local bufnr = h.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        -- pcall: Neovim before 0.10 has no such option
        pcall(function()
          vim.wo[win].winfixbuf = false
        end)
      end
    end
    if not backend.close(h) then
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
      registry:remove(h.id)
    end
  end
  vim.cmd("silent! tabonly")
  vim.cmd("silent! only")
end

return M
