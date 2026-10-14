---@meta
---@module 'terminal.core.@types'
--- Types of terminal.core, grouped by the file they used to sit in.

-- ---------------------------------------------------------------------------
-- core/exec.lua

---@class Terminal.ExecResult
---@field code integer Exit code; 127 when the command could not be started, 124 on a timeout, 128 + the signal when a signal ended it
---@field stdout string
---@field stderr string The program's stderr, or why it could not be started (code 127)

---@class Terminal.ExecOpts
---@field stdin? string Text written to the program's standard input
---@field timeout? integer Milliseconds (default `DEFAULT_TIMEOUT_MS`)

-- ---------------------------------------------------------------------------
-- core/env.lua

---@alias Terminal.Env table<string, string|nil>

-- ---------------------------------------------------------------------------
-- core/navigate.lua

---@alias Terminal.Direction "h"|"j"|"k"|"l"

---@class Terminal.DirectionWords
---@field wezterm string Argument of `wezterm cli activate-pane-direction`
---@field tmux string Flag of `tmux select-pane`
---@field edge string Side of the window, for the tmux format variable `#{pane_at_<edge>}`

-- ---------------------------------------------------------------------------
-- core/context.lua

---@class Terminal.ContextDeps
---@field cwd fun(): string Current working directory, spelled the way the user is in it
---@field bufname fun(): string Name of the current buffer ("" when none)
---@field root fun(path: string): string|nil Project root for a path, spelled like the path (nil = none found)
---@field key? fun(path: string): string The canonical form of a directory, for the registry id (default: as given)

-- ---------------------------------------------------------------------------
-- core/status.lua

---@class Terminal.StatusSnapshot
---@field mode string `nvim_get_mode().mode`, e.g. "n", "i", "V", "\22", "t" (published as "^V" for "\22")
---@field file string Buffer name (may be a full path or "")
---@field buftype? string
---@field cwd string
---@field branch? string
---@field diag? Terminal.DiagCounts
---@field recording? string Register being recorded into, "" when none
---@field modified? boolean
---@field filetype? string
---@field pid? integer

---@class Terminal.Status
---@field v integer Schema version
---@field pid? integer
---@field mode string
---@field file string
---@field ft string
---@field cwd string
---@field branch string
---@field e integer Error count
---@field w integer Warning count
---@field i integer Info count
---@field h integer Hint count
---@field rec string
---@field mod boolean

return {}
