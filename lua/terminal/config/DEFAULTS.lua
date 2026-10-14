---@module 'terminal.config.DEFAULTS'
--- Immutable default configuration for terminal.nvim.
---
--- Single source of truth for every configurable value. `terminal.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.

---@type Terminal.Config
local DEFAULTS = {
  -- Where terminals live. "auto" and "native" are Neovim's own :terminal windows; a multiplexer
  -- backend ("wezterm", "tmux") opens terminals as panes of that multiplexer instead and is
  -- always chosen explicitly. See docs/backends.md. An unavailable backend falls back to native with a
  -- notice that says why.
  backend = "auto",
  layout = "float",

  float = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
    title = true,
    title_pos = "center",
    winblend = 0,
    zindex = 50, -- what `nvim_open_win` uses for a float without one
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

  -- Publish what this Neovim is doing (mode, file, branch, diagnostics, ...) to the terminal
  -- around it: WezTerm reads it from per-pane user variables.
  status = {
    enable = true,
    -- "auto" (every exporter whose environment signal is present), a name ("wezterm"), a list
    -- of names, or false (none).
    export = "auto",
    -- Events closer together than this (a mode change and a buffer switch, say) publish once.
    debounce_ms = 80,
    -- The dataset is shortened, then refused, above this size.
    max_bytes = 1024,
    -- How long the tmux exporter waits for tmux before it gives up on a publish (a hung tmux is
    -- switched off once, with a notice). Milliseconds.
    timeout_ms = 2000,
  },

  -- The multiplexer programs (`tmux`, `wezterm cli`) are separate processes; this is how long a
  -- call may take before it counts as hung. Milliseconds. toggle/open/send wait for the answer, so
  -- a hung multiplexer blocks the editor for this long, once.
  multiplexer = {
    timeout_ms = 3000,
  },

  -- The read-only view of a multiplexer pane (`:Terminal adopt`).
  adopt = {
    -- Pause between two refreshes, counted from the end of the previous one. Milliseconds.
    refresh_ms = 1000,
  },

  -- `:Terminal pin`: restart a native terminal as a multiplexer pane.
  pin = {
    -- The layout of the new pane when `--layout` is not given: float | split | vsplit | tab.
    layout = "vsplit",
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
    -- Window navigation from NORMAL mode through terminal.nvim, so it can hand off at the edge.
    -- All off by default (the editor config usually owns <C-h/j/k/l> in normal mode); bind
    -- them here to get `3<C-h>`-style counts plus the hand-off.
    nav_left = false,
    nav_down = false,
    nav_up = false,
    nav_right = false,
  },

  -- Moving between windows past Neovim's edge: when nothing is further in that direction, the
  -- multiplexer around Neovim focuses the neighbouring pane. "auto" asks tmux inside tmux and
  -- WezTerm inside WezTerm; a name, a list of names, or false (never hand off) also work.
  navigate = {
    handoff = "auto",
    -- How long the hand-off command may run before it is stopped. Milliseconds.
    timeout_ms = 2000,
  },

  -- sessions.nvim: the terminals of a session are saved beside it and reopened (hidden) when it is
  -- loaded. Only the definitions: name, layout, directory and the command of a `run` with
  -- `direct`; no process survives. `commands` says what happens to those commands: "ask" (once,
  -- when a session has any), "run" (start them) or "never" (open plain shells instead).
  sessions = {
    enable = true,
    commands = "ask",
  },

  commands = true,
}

return DEFAULTS
