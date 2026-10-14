---@module 'terminal.core.env'
--- The one place that reads the environment variables which say what surrounds Neovim, and the one
--- predicate for "is that variable set". Before, eight modules each had their own check and five
--- assembled the same table.
---
--- `$TMUX` says Neovim runs inside tmux, `$TMUX_PANE` which pane, `$WEZTERM_PANE` the WezTerm pane,
--- and `$NVIM` is set by a Neovim in the terminals it starts (an outer Neovim's server address).

local M = {}

---@alias Terminal.Env table<string, string|nil>

--- Variables that identify a multiplexer or terminal emulator, most specific (innermost) first.
---@type { name: "tmux"|"wezterm", var: string }[]
M.SIGNALS = {
  { name = "tmux", var = "TMUX" },
  { name = "wezterm", var = "WEZTERM_PANE" },
}

--- Whether a variable has a value (an empty one counts as unset, like a shell's `[ -n "$X" ]`).
---@param value any
---@return boolean
function M.set(value)
  return type(value) == "string" and value ~= ""
end

--- The variables as they are now.
---@return Terminal.Env
function M.read()
  return {
    TMUX = vim.env.TMUX,
    TMUX_PANE = vim.env.TMUX_PANE,
    WEZTERM_PANE = vim.env.WEZTERM_PANE,
    NVIM = vim.env.NVIM,
  }
end

--- Whether Neovim runs inside `name`.
---@param env Terminal.Env
---@param name "tmux"|"wezterm"
---@return boolean
function M.inside(env, name)
  for _, signal in ipairs(M.SIGNALS) do
    if signal.name == name then
      return M.set(env[signal.var])
    end
  end
  return false
end

return M
