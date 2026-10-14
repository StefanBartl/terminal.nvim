---@meta
---@module 'terminal.status.@types'
--- Types of terminal.status, grouped by the file they used to sit in.

-- ---------------------------------------------------------------------------
-- status/init.lua

---@class Terminal.StatusExporter
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field ready? fun(): boolean `false`: cannot publish right now (no UI attached); skipped without a notice, retried on the next event
---@field key? fun(data: Terminal.Status): string What the exporter actually publishes; the delta gate compares this (default: the whole JSON)
---@field publish fun(json: string, data?: Terminal.Status): boolean, string|nil
---@field publish_async? fun(json: string, data: Terminal.Status|nil, done: fun(ok: boolean, err?: string)): boolean, string|nil Like `publish`, without blocking: returns at once (`false, err` when the request is unusable, `done` is not called then); `done` runs later on the main loop for a request that actually ran. A request that was replaced by a newer one is never reported. Used instead of `publish` when present
---@field clear fun(): boolean, string|nil

---@class Terminal.StatusRuntime
---@field exporters Terminal.StatusExporter[]
---@field off table<string, true> Exporters that failed once
---@field last table<string, string> Key of the newest request handed to each exporter (an asynchronous exporter may not have applied it yet)
---@field debounce? table
---@field max_bytes integer
---@field oversize boolean A dataset over `max_bytes` was already reported

-- ---------------------------------------------------------------------------
-- status/collector.lua

---@class Terminal.HeadMemo
---@field path string|false The `.git/HEAD` of the repository that contains the directory; false: there is none (no repository, or its `.git` is a file)
---@field at number `now_ms()` when the walk was made

---@class Terminal.HeadRead
---@field sec integer mtime of the file when it was read
---@field nsec integer
---@field size integer
---@field value string|false The branch, false when `HEAD` names none

return {}
