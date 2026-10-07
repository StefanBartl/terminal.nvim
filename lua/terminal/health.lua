---@module 'terminal.health'
--- `:checkhealth terminal` diagnostics. Read-only: never mutates state, never starts a job.

local M = {}

---@internal
---@param name string
---@return boolean
local function exe(name)
  return vim.fn.executable(name) == 1
end

--- Run the health check.
---@return nil
function M.check()
  local health = vim.health
  health.start("terminal.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("terminal.nvim needs Neovim 0.10+", { "Upgrade Neovim to 0.10 or newer" })
  end

  local required = {
    { "lib.nvim.notify", "notifications" },
    { "lib.nvim.bindings.keymap", "keymaps" },
    { "lib.nvim.bindings.autocmd", "autocommands" },
    { "lib.nvim.bindings.usercmd.composer", ":Terminal" },
    { "lib.lua.config", "configuration" },
  }
  for _, r in ipairs(required) do
    if pcall(require, r[1]) then
      health.ok(("lib.nvim provides %s (%s)"):format(r[1], r[2]))
    else
      health.error(
        ("%s not found -- %s will not work"):format(r[1], r[2]),
        { 'Install "StefanBartl/lib.nvim" (a hard dependency)' }
      )
    end
  end

  local ok, terminal = pcall(require, "terminal")
  if ok then
    local status = terminal.status()
    if status.ready then
      health.ok(
        ("setup() ran; backend '%s', %d terminal(s) open"):format(status.backend, status.terminals)
      )
    else
      health.info("setup() has not run yet (it runs on first use)")
    end
  end

  health.start("terminal.nvim: environment")
  local backends = require("terminal.backends")
  local detected = backends.detect({ TMUX = vim.env.TMUX, WEZTERM_PANE = vim.env.WEZTERM_PANE })
  health.info("Detected: " .. table.concat(detected, ", "))
  health.info("Only the 'native' backend is implemented; the others fall back to it.")

  local shell = vim.o.shell
  if shell ~= "" and exe(shell) then
    health.ok(("'shell' is executable: %s"):format(shell))
  else
    health.warn(("'shell' is not executable: %s"):format(shell), {
      "Set the 'shell' option or terminal.nvim's `shell` setting to an installed shell",
    })
  end
end

return M
