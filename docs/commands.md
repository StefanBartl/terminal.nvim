# Commands (`:Terminal`)

One compound command, `:Terminal <action> [args] [flags]`, with `<Tab>` completion.

| Command | Does |
|---|---|
| `:Terminal` | Toggle the default terminal. |
| `:Terminal toggle [name] [--layout=]` | Focus when visible elsewhere, hide when focused, show when hidden, create when missing. |
| `:Terminal open [name] [--layout=]` | Show and focus; create when needed. |
| `:Terminal hide [name]` | Close the window; the job keeps running. |
| `:Terminal close [name]` | Stop the job and remove the terminal. |
| `:Terminal list` | Pick one of this project's terminals (`vim.ui.select`). |
| `:Terminal send line [name] [--exec]` | Type the current line. |
| `:'<,'>Terminal send selection [name] [--exec]` | Type the selected lines. |
| `:Terminal send file [name] [--exec]` | Type the whole buffer. |
| `:Terminal run [--name=] [--layout=] [--direct] <command...>` | Run a command (see below). |

`name` defaults to the configured `default_name` (`main`); `3` is the terminal "3" that
`3<A-h>` uses. `--layout=` is `float`, `split`, `vsplit` or `tab`.

## Typing versus executing

`send` only **types**: the text appears at the prompt. `--exec` adds the Enter key.
This is deliberate — a selection that contains a line break would otherwise run each line.

## `run`

- `:Terminal run npm test` types the line exactly as given into the `run` terminal and
  presses Enter. It is your text.
- From Lua, `require("terminal").run({ "git", "commit", "-m", msg })` takes an **argv list**
  and quotes every word for the terminal's shell (POSIX, PowerShell or cmd.exe), so a
  message with spaces, quotes or `$(...)` stays data. A word containing a line break or NUL
  is refused: it would end the command line.
- `--direct` starts the command as the job itself (no shell in between). The terminal stays
  after it ends, an earlier terminal of the same name is replaced, and from Lua
  `on_exit(code)` reports the exit code: `run({ "make" }, { direct = true, on_exit = fn })`.
  The words after `--direct` are the argv.

## Lua API

```lua
local terminal = require("terminal")
terminal.toggle({ name = "build", layout = "vsplit" })
terminal.open({ count = 3, focus = false })
terminal.hide(); terminal.close({ name = "build" })
terminal.list()          -- this project's terminals; list(true) for all
terminal.send("ls", { newline = true, name = "repl" })
terminal.run({ "git", "status" })
terminal.status()        -- { ready, backend, terminals }
```

Every function returns `nil, err` (or `false, err`) instead of raising, and reports the
problem to the user.
