---@module 'terminal.core.navigate'
--- Pure decisions for "move to the window in this direction, and past Neovim's edge into the
--- neighbouring terminal pane". No editor state is read here.

local M = {}

---@alias Terminal.Direction "h"|"j"|"k"|"l"

---@class Terminal.DirectionWords
---@field wezterm string Argument of `wezterm cli activate-pane-direction`
---@field tmux string Flag of `tmux select-pane`
---@field edge string Side of the window, for the tmux format variable `#{pane_at_<edge>}`

--- Direction keys and the words the multiplexers use. `edge` is the tmux format variable
--- (`#{pane_at_<edge>}`) that is 1 when the pane touches that side of its window.
---@type table<string, Terminal.DirectionWords>
M.DIRECTIONS = {
  h = { wezterm = "Left", tmux = "-L", edge = "left" },
  j = { wezterm = "Down", tmux = "-D", edge = "bottom" },
  k = { wezterm = "Up", tmux = "-U", edge = "top" },
  l = { wezterm = "Right", tmux = "-R", edge = "right" },
}

--- Whether `dir` is one of h j k l.
---@param dir any
---@return boolean
function M.valid(dir)
  return type(dir) == "string" and M.DIRECTIONS[dir] ~= nil
end

--- What a navigation attempt amounted to.
---
---   * `"moved"`  -- the current window changed: Neovim handled it
---   * `"float"`  -- started in a floating window: a float has no neighbours, never hand off
---   * `"edge"`   -- the window did not change: there is nothing further in Neovim, hand off
---@param was_float boolean The window the attempt started in is a float
---@param before integer Window id before
---@param after integer Window id after
---@return "moved"|"float"|"edge"
function M.outcome(was_float, before, after)
  if was_float then
    return "float"
  end
  if before ~= after then
    return "moved"
  end
  return "edge"
end

return M
