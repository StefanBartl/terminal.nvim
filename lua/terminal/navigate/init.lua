---@module 'terminal.navigate'
--- `go(dir)`: move to the window in that direction; when nothing is further in that direction
--- inside Neovim, ask the surrounding multiplexer to focus the neighbouring pane.
---
--- Floating windows never hand off (a float has no neighbours). The hand-off is fire-and-forget:
--- the key press does not wait for the multiplexer command (starting the process still costs a
--- few milliseconds, tens on Windows), it runs in the background and its failure (no neighbour in
--- that direction, ...) is ignored -- it is the normal case at the outer edge.

local core = require("terminal.core.navigate")

local M = {}

---@class Terminal.NavigateRuntime
---@field handoffs Terminal.Handoff[]
---@field run fun(argv: string[])

---@type Terminal.NavigateRuntime
local runtime = { handoffs = {}, run = function() end }

---@internal
--- At most one hand-off process runs at a time (the multiplexer may be slow or hung); a press
--- that arrives meanwhile replaces the one waiting behind it, so a held key at the edge costs
--- one process per round trip instead of one per key repeat. The process has a timeout, so a
--- hung multiplexer is reaped.
local inflight = false
---@type string[]|nil
local pending = nil

---@internal
---@param argv string[]
local function spawn_detached(argv)
  if inflight then
    pending = argv
    return
  end
  inflight = true
  local ok = pcall(vim.system, argv, { text = true, timeout = 2000 }, function()
    inflight = false
    local next_argv = pending
    pending = nil
    if next_argv then
      vim.schedule(function()
        spawn_detached(next_argv)
      end)
    end
  end)
  if not ok then
    inflight = false
  end
end

--- Choose the hand-offs from the config.
---@param cfg Terminal.Config
---@param env? table<string, string|nil> Default: the process's
---@param run? fun(argv: string[]) Command runner (default: detached `vim.system`)
---@return nil
function M.setup(cfg, env, run)
  env = env or { TMUX = vim.env.TMUX, WEZTERM_PANE = vim.env.WEZTERM_PANE }
  runtime.run = run or spawn_detached
  if cfg.navigate.handoff == false then
    -- nothing to choose: the hand-off module is not even loaded
    runtime.handoffs = {}
    return
  end
  local chosen, notes = require("terminal.navigate.handoff").choose(cfg.navigate.handoff, env)
  if #notes > 0 then
    vim.schedule(function()
      local notify = require("terminal.notify")
      for _, note in ipairs(notes) do
        notify.warn(note)
      end
    end)
  end
  runtime.handoffs = chosen
end

--- Most windows one `go` can move over. Neovim stops at the last window anyway; the cap only
--- keeps the `%d` of the `wincmd` string inside integer range.
local MAX_COUNT = 9999

--- Move `count` windows in `dir`; at the edge, hand off to the multiplexer.
---
--- Raises on a direction that is not h, j, k or l, and on a count that is neither nil nor a number
--- from 0 up (`vim.v.count` is 0 when no count was typed, which means 1): both are programmer
--- errors, not something the user can cause by typing.
---@param dir Terminal.Direction
---@param count? integer Windows to move (default 1; 0 also means 1)
---@return "moved"|"float"|"edge" outcome
function M.go(dir, count)
  if not core.valid(dir) then
    error(("terminal.navigate: invalid direction %s"):format(vim.inspect(dir)), 2)
  end
  if count ~= nil and not (type(count) == "number" and count >= 0 and count < math.huge) then
    error(
      ("terminal.navigate: count must be a number from 0 up, got %s"):format(vim.inspect(count)),
      2
    )
  end
  count = math.min(math.max(math.floor(count or 0), 1), MAX_COUNT)

  local before = vim.api.nvim_get_current_win()
  local was_float = vim.api.nvim_win_get_config(before).relative ~= ""
  vim.cmd(("%dwincmd %s"):format(count, dir))
  local outcome = core.outcome(was_float, before, vim.api.nvim_get_current_win())

  if outcome == "edge" then
    -- The innermost multiplexer that can take it; each is asked at most once per key press.
    local first = runtime.handoffs[1]
    if first then
      runtime.run(first.argv(dir))
    end
  end
  return outcome
end

--- The hand-offs in use, for health checks.
---@return string[]
function M.active()
  return vim.tbl_map(function(h)
    return h.name
  end, runtime.handoffs)
end

return M
