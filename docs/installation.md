# Installation

## lazy.nvim

```lua
{
  "StefanBartl/terminal.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  -- The toggle key and the terminal-mode keys are global; load at startup (cheap: setup()
  -- only registers keymaps, autocommands and one command).
  event = "VeryLazy",
  cmd = { "Terminal" },
  opts = {},
}
```

`opts = {}` is all it needs. Every option is listed in [configuration.md](configuration.md).

## Load triggers

| You want | Use |
|---|---|
| The keys (`<A-h>` …) available at once | `event = "VeryLazy"` (above) |
| Only the command, loaded on first use | `cmd = { "Terminal" }` and set `keymaps = { preset = false }` |

With `cmd` alone, lazy.nvim defines a stub `:Terminal` that loads the plugin and re-runs;
the keys exist only after that first load.

## Without a plugin manager

Put the repository and `lib.nvim` on the `runtimepath`, then:

```lua
require("terminal").setup({})
```
