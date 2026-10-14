---@meta
---@module 'terminal.backends.@types'
--- Types of terminal.backends, grouped by the file they used to sit in.

-- ---------------------------------------------------------------------------
-- backends/tmux.lua

---@alias Terminal.TmuxRun Terminal.ExecResult

---@alias Terminal.TmuxRunner fun(argv: string[], opts?: Terminal.ExecOpts): Terminal.TmuxRun

--- The state of one pane in `list-panes`, as far as focus is concerned.
---@class Terminal.TmuxPane
---@field active boolean The pane is the active one of its window
---@field window_active boolean Its window is the active one of the session

-- ---------------------------------------------------------------------------
-- backends/wezterm.lua

---@alias Terminal.WezTermRun Terminal.ExecResult

---@alias Terminal.WezTermRunner fun(argv: string[], opts?: Terminal.ExecOpts): Terminal.WezTermRun

return {}
