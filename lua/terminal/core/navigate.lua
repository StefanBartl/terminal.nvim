---@module 'terminal.core.navigate'
--- Pure decisions for "move to the window in this direction, and past Neovim's edge into the
--- neighbouring terminal pane". No editor state is read here.

local M = {}

---@alias Terminal.Direction "h"|"j"|"k"|"l"

--- Direction keys and the words the multiplexers use.
---@type table<string, { wezterm: string, tmux: string }>
M.DIRECTIONS = {
  h = { wezterm = "Left", tmux = "-L" },
  j = { wezterm = "Down", tmux = "-D" },
  k = { wezterm = "Up", tmux = "-U" },
  l = { wezterm = "Right", tmux = "-R" },
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
