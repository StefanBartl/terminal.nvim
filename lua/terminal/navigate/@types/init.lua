---@meta
---@module 'terminal.navigate.@types'
--- Types of terminal.navigate, grouped by the file they used to sit in.

-- ---------------------------------------------------------------------------
-- navigate/handoff.lua

---@class Terminal.Handoff
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field argv fun(dir: Terminal.Direction): string[]

-- ---------------------------------------------------------------------------
-- navigate/init.lua

---@class Terminal.NavigateRuntime
---@field handoffs Terminal.Handoff[]
---@field run fun(argv: string[])

return {}
