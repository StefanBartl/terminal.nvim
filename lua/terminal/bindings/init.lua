---@module 'terminal.bindings'
--- Orchestrates terminal.nvim's bindings: keymaps, autocommands and the `:Terminal` command.

local M = {}

--- Wire up every binding for the resolved config. Safe to call again: each part replaces what it
--- created before (named augroups, re-registered keymap actions and command).
---@return nil
function M.setup()
  local cfg = require("terminal.config").get_all()
  require("terminal.bindings.keymaps").setup(cfg)
  require("terminal.bindings.autocmds").setup(cfg)
  if cfg.commands then
    require("terminal.bindings.usrcmds").setup()
  end
end

return M
