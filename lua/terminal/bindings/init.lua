---@module 'terminal.bindings'
--- Orchestrates terminal.nvim's bindings: keymaps, autocommands and the `:Terminal` command.

local M = {}

--- Wire up every binding for the resolved config. Safe to call again: each part replaces what it
--- created before (named augroups, re-registered keymap actions and command).
---@return nil
function M.setup()
  local cfg = require("terminal.config").get_all()
  -- Each part on its own: a keymap or autocommand that cannot be created must not take the
  -- `:Terminal` command with it.
  local parts = {
    { "keymaps", require("terminal.bindings.keymaps").setup },
    { "autocommands", require("terminal.bindings.autocmds").setup },
  }
  if cfg.commands then
    parts[#parts + 1] = { ":Terminal", require("terminal.bindings.usrcmds").setup }
  end
  for _, part in ipairs(parts) do
    local ok, err = pcall(part[2], cfg)
    if not ok then
      vim.schedule(function()
        require("terminal.notify").error(
          ("%s could not be set up: %s"):format(part[1], tostring(err))
        )
      end)
    end
  end
end

return M
