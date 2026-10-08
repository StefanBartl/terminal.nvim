---@module 'terminal.navigate.handoff'
--- Who takes over when the window under the cursor is at Neovim's edge: the multiplexer or
--- terminal Neovim runs in, asked to focus the pane in that direction.
---
--- Each hand-off is a name, an availability test over the environment and the command that does
--- it. The command is built here (pure, testable) and run elsewhere (`terminal.navigate`),
--- fire-and-forget: a key press must never wait for it.
---@see terminal.navigate

local navigate = require("terminal.core.navigate")

local M = {}

---@class Terminal.Handoff
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field argv fun(dir: Terminal.Direction): string[]

---@type table<string, Terminal.Handoff>
M.all = {
  tmux = {
    name = "tmux",
    available = function(env)
      if env.TMUX == nil or env.TMUX == "" then
        return false, "not inside tmux ($TMUX is not set)"
      end
      return true, nil
    end,
    -- `select-pane -L` alone wraps around at the window's edge (focusing the pane on the far
    -- side). The `pane_at_*` test keeps the key a no-op at the edge: `if-shell -F <cond> <then>
    -- <else>` with an empty `then`.
    argv = function(dir)
      local d = navigate.DIRECTIONS[dir]
      return {
        "tmux",
        "if-shell",
        "-F",
        "#{pane_at_" .. d.edge .. "}",
        "",
        "select-pane " .. d.tmux,
      }
    end,
  },
  wezterm = {
    name = "wezterm",
    available = function(env)
      if env.WEZTERM_PANE == nil or env.WEZTERM_PANE == "" then
        return false, "not running inside WezTerm ($WEZTERM_PANE is not set)"
      end
      return true, nil
    end,
    argv = function(dir)
      return { "wezterm", "cli", "activate-pane-direction", navigate.DIRECTIONS[dir].wezterm }
    end,
  },
}

---@internal
--- Innermost first: inside tmux inside WezTerm, tmux is asked first.
local ORDER = { "tmux", "wezterm" }

--- The hand-offs the config asks for that this environment supports, innermost first.
--- `handoff`: "auto", one name, a list of names, or `false` for none.
---@param handoff string|string[]|boolean
---@param env table<string, string|nil>
---@return Terminal.Handoff[] chosen
---@return string[] notes # Why a named hand-off is unusable
function M.choose(handoff, env)
  if handoff == false then
    return {}, {}
  end
  local names
  if handoff == "auto" then
    names = ORDER
  elseif type(handoff) == "string" then
    names = { handoff }
  else
    ---@cast handoff string[]
    names = handoff
  end
  local chosen, notes = {}, {}
  for _, name in ipairs(names) do
    local h = M.all[name]
    if not h then
      notes[#notes + 1] = ("navigation hand-off '%s' does not exist"):format(name)
    else
      local ok, reason = h.available(env)
      if ok then
        chosen[#chosen + 1] = h
      elseif handoff ~= "auto" then
        notes[#notes + 1] = ("navigation hand-off '%s' is not usable: %s"):format(
          name,
          reason or "?"
        )
      end
    end
  end
  return chosen, notes
end

return M
