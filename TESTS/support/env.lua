-- TESTS/support/env.lua -- makes a spec independent of the terminal it is run from.
--
-- The facade picks its backends, status exporters and navigation hand-offs from the environment
-- (`$TMUX`, `$TMUX_PANE`, `$WEZTERM_PANE`, `$NVIM`). A spec run inside tmux or WezTerm would
-- otherwise drive the developer's real multiplexer and assert the wrong backend.

local M = {}

local NAMES = { "TMUX", "TMUX_PANE", "WEZTERM_PANE", "NVIM" }

--- Clear the variables that make the plugin look for a multiplexer. Returns a function that puts
--- them back (a spec file runs in its own Neovim, so calling it is optional).
---@return fun() restore
function M.isolate()
  local saved = {}
  for _, name in ipairs(NAMES) do
    saved[name] = vim.env[name]
    vim.env[name] = nil
  end
  return function()
    for _, name in ipairs(NAMES) do
      vim.env[name] = saved[name]
    end
  end
end

return M
