---@module 'terminal.bindings.keymaps'
--- Keymaps as named, overridable actions (`lib.nvim.bindings.keymap.register`).
---
--- Every action's default comes from `terminal.config.DEFAULTS.keymaps`; a user moves one with
--- `keymaps = { toggle = "<A-x>" }`, drops one with `toggle = false`, or binds nothing at all
--- with `preset = false`. An action whose default is `false` exists but is unbound until the user
--- gives it a key.

local DEFAULTS = require("terminal.config.DEFAULTS").keymaps

local M = {}

---@internal
--- `<C-\><C-n>` leaves terminal mode; the double backslash is Lua escaping.
local LEAVE = "<C-\\><C-n>"

---@internal
--- Clear the shell screen without leaving terminal mode: `cls` for cmd.exe and PowerShell,
--- `clear` for everything else. It depends on the shell the terminal runs, not on the OS: Git
--- Bash or WSL on Windows want `clear`.
---@return nil
local function clear_screen()
  local job = vim.b.terminal_job_id
  if not job then
    return
  end
  local kind =
    require("terminal.core.quote").shell_kind(require("terminal.config").shell_executable())
  vim.fn.chansend(job, { (kind == "cmd" or kind == "powershell") and "cls" or "clear", "" })
end

---@internal
--- Window navigation from terminal mode: leave it, then move (and hand off at the edge).
---@param dir Terminal.Direction
---@return fun()
local function from_terminal(dir)
  return function()
    vim.cmd("stopinsert")
    require("terminal").navigate(dir, vim.v.count)
  end
end

---@internal
--- Window navigation from normal mode; a count moves that many windows.
---@param dir Terminal.Direction
---@return fun()
local function from_normal(dir)
  return function()
    require("terminal").navigate(dir, vim.v.count1)
  end
end

---@internal
--- Remove the maps an earlier `setup()` created. `keymap.register` replaces its own record on
--- every call but never deletes a key that has moved or been dropped since, so a re-setup (a config
--- reload) would leave the old keys active. Only a map that still carries this plugin's description
--- is deleted: one the user set on the same key afterwards stays.
---@param keymap table `lib.nvim.bindings.keymap`
---@return nil
local function unbind_previous(keymap)
  for _, entry in ipairs(keymap.registered("terminal")) do
    if entry.name and entry.bound and entry.lhs then
      local modes = type(entry.mode) == "table" and entry.mode or { entry.mode }
      for _, mode in ipairs(modes) do
        local current = vim.fn.maparg(entry.lhs, mode, false, true)
        if
          type(current) == "table"
          and type(current.desc) == "string"
          and vim.startswith(current.desc, "terminal: ")
        then
          pcall(vim.keymap.del, mode, entry.lhs)
        end
      end
    end
  end
end

--- Register the actions and bind them.
---@param cfg Terminal.Config
---@return nil
function M.setup(cfg)
  local keymap = require("lib.nvim.bindings.keymap")
  local terminal = require("terminal")
  unbind_previous(keymap)

  keymap.register("terminal", {
    order = {
      "toggle",
      "normal_mode",
      "clear",
      "window_left",
      "window_down",
      "window_up",
      "window_right",
      "nav_left",
      "nav_down",
      "nav_up",
      "nav_right",
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
        rhs = from_terminal("h"),
        desc = "Window left (hands off to the multiplexer at the edge)",
      },
      window_down = {
        default = DEFAULTS.window_down,
        mode = "t",
        rhs = from_terminal("j"),
        desc = "Window down (hands off at the edge)",
      },
      window_up = {
        default = DEFAULTS.window_up,
        mode = "t",
        rhs = from_terminal("k"),
        desc = "Window up (hands off at the edge)",
      },
      window_right = {
        default = DEFAULTS.window_right or nil,
        mode = "t",
        rhs = from_terminal("l"),
        desc = "Window right (hands off at the edge)",
      },
      nav_left = {
        default = DEFAULTS.nav_left or nil,
        mode = "n",
        rhs = from_normal("h"),
        desc = "Window left (count; hands off at the edge)",
      },
      nav_down = {
        default = DEFAULTS.nav_down or nil,
        mode = "n",
        rhs = from_normal("j"),
        desc = "Window down (count; hands off at the edge)",
      },
      nav_up = {
        default = DEFAULTS.nav_up or nil,
        mode = "n",
        rhs = from_normal("k"),
        desc = "Window up (count; hands off at the edge)",
      },
      nav_right = {
        default = DEFAULTS.nav_right or nil,
        mode = "n",
        rhs = from_normal("l"),
        desc = "Window right (count; hands off at the edge)",
      },
    },
  }, cfg.keymaps)
end

return M
