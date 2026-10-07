---@module 'terminal.bindings.keymaps'
--- Keymaps as named, overridable actions (`lib.nvim.bindings.keymap.register`).
---
--- Every action's default comes from `terminal.config.DEFAULTS.keymaps`; a user moves one with
--- `keymaps = { toggle = "<A-x>" }`, drops one with `toggle = false`, or binds nothing at all
--- with `preset = false`.

local DEFAULTS = require("terminal.config.DEFAULTS").keymaps

local M = {}

---@internal
--- `<C-\><C-n>` leaves terminal mode; the double backslash is Lua escaping.
local LEAVE = "<C-\\><C-n>"

---@internal
--- Clear the shell screen without leaving terminal mode: `cls` on Windows, `clear` elsewhere.
---@return nil
local function clear_screen()
  local job = vim.b.terminal_job_id
  if not job then
    return
  end
  local env = require("lib.nvim.system.env").get()
  vim.fn.chansend(job, { env.is_windows and "cls" or "clear", "" })
end

--- Register the actions and bind them.
---@param cfg Terminal.Config
---@return nil
function M.setup(cfg)
  local keymap = require("lib.nvim.bindings.keymap")
  local terminal = require("terminal")

  keymap.register("terminal", {
    order = {
      "toggle",
      "normal_mode",
      "clear",
      "window_left",
      "window_down",
      "window_up",
      "window_right",
    },
    actions = {
      toggle = {
        default = DEFAULTS.toggle,
        mode = { "n", "t" },
        rhs = function()
          terminal.toggle({ count = vim.v.count })
        end,
        desc = "Toggle the terminal (a count picks terminal N)",
      },
      normal_mode = {
        default = DEFAULTS.normal_mode,
        mode = "t",
        rhs = LEAVE,
        desc = "Leave terminal mode",
      },
      clear = {
        default = DEFAULTS.clear or nil,
        mode = "t",
        rhs = clear_screen,
        desc = "Clear the terminal screen",
      },
      window_left = {
        default = DEFAULTS.window_left,
        mode = "t",
        rhs = "<C-\\><C-w>h",
        desc = "Window left",
      },
      window_down = {
        default = DEFAULTS.window_down,
        mode = "t",
        rhs = "<C-\\><C-w>j",
        desc = "Window down",
      },
      window_up = {
        default = DEFAULTS.window_up,
        mode = "t",
        rhs = "<C-\\><C-w>k",
        desc = "Window up",
      },
      window_right = {
        default = DEFAULTS.window_right or nil,
        mode = "t",
        rhs = "<C-\\><C-w>l",
        desc = "Window right",
      },
    },
  }, cfg.keymaps)
end

return M
