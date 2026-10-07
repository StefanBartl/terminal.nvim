---@module 'terminal.navigate'
--- `go(dir)`: move to the window in that direction; when nothing is further in that direction
--- inside Neovim, ask the surrounding multiplexer to focus the neighbouring pane.
---
--- Floating windows never hand off (a float has no neighbours). The hand-off is fire-and-forget:
--- the key press returns at once, the multiplexer command runs in the background and its failure
--- (no neighbour in that direction, ...) is ignored -- it is the normal case at the outer edge.

local core = require("terminal.core.navigate")
local handoff = require("terminal.navigate.handoff")

local M = {}

---@class Terminal.NavigateRuntime
---@field handoffs Terminal.Handoff[]
---@field run fun(argv: string[])

---@type Terminal.NavigateRuntime
local runtime = { handoffs = {}, run = function() end }

---@internal
---@param argv string[]
local function spawn_detached(argv)
  pcall(vim.system, argv, { text = true }, function() end)
end

--- Choose the hand-offs from the config.
---@param cfg Terminal.Config
---@param env? table<string, string|nil> Default: the process's
---@param run? fun(argv: string[]) Command runner (default: detached `vim.system`)
---@return nil
function M.setup(cfg, env, run)
  env = env or { TMUX = vim.env.TMUX, WEZTERM_PANE = vim.env.WEZTERM_PANE }
  local chosen, notes = handoff.choose(cfg.navigate.handoff, env)
  if #notes > 0 then
    vim.schedule(function()
      local n = require("lib.nvim.notify").create("[terminal]")
      for _, note in ipairs(notes) do
        n.warn(note)
      end
    end)
  end
  runtime.handoffs = chosen
  runtime.run = run or spawn_detached
end

--- Move `count` windows in `dir`; at the edge, hand off to the multiplexer.
---@param dir Terminal.Direction
---@param count? integer Default 1
---@return "moved"|"float"|"edge" outcome
function M.go(dir, count)
  if not core.valid(dir) then
    error(("terminal.navigate: invalid direction %s"):format(vim.inspect(dir)), 2)
  end
  count = (type(count) == "number" and count >= 1) and math.floor(count) or 1

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
