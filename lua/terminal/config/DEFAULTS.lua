---@module 'terminal.config.DEFAULTS'
--- Immutable default configuration for terminal.nvim.
---
--- Single source of truth for every configurable value. `terminal.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.

---@type Terminal.Config
local DEFAULTS = {
  -- "auto" picks a backend from the environment: $TMUX -> "tmux", $WEZTERM_PANE ->
  -- "wezterm", else "native". Only "native" exists yet; the others fall back to it.
  backend = "auto",
  layout = "float",

  float = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
    title = true,
    title_pos = "center",
    winblend = 0,
    zindex = 50,
  },
  split = {
    size = 0.3,
  },

  cwd = "project",
  shell = "",
  env = {},

  start_insert = true,
  on_exit = "close",
  default_name = "main",

  window_options = {
    enable = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    spell = false,
    cursorline = false,
  },

  kitty = {
    enable = true,
    enter_padding = 0,
    enter_margin = 0,
    leave_padding = 20,
    leave_margin = 10,
  },

  auto_insert = {
    enable = false,
    events = { "TermOpen" },
  },

  run = {
    name = "run",
  },

  keymaps = {
    preset = true,
    toggle = "<A-h>",
    normal_mode = { "<Esc>", "<C-c>" },
    -- Off by default: <C-l> reaches the shell and clears the screen there, like in any terminal.
    -- Set a key to have the plugin type `cls` / `clear` for you instead.
    clear = false,
    window_left = "<C-h>",
    window_down = "<C-j>",
    window_up = "<C-k>",
    -- Off by default so <C-l> stays the shell's own clear-screen. Set "<C-l>" (or another key)
    -- for a window move to the right from terminal mode.
    window_right = false,
  },

  commands = true,
}

return DEFAULTS
