---@module 'terminal.notify'
--- The plugin's one notifier: every message carries the `[terminal]` prefix and goes through
--- `lib.nvim.notify`.

return require("lib.nvim.notify").create("[terminal]")
