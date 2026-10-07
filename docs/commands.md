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
- Put `--` before a command that has dashed words of its own: `:Terminal run -- git log --oneline`.
  Everything after the flags (or after the `--`) is passed on verbatim.
- `send` with several lines needs `--exec` (typing a line break presses Enter, so each line would run);
  a single line is just typed.

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
terminal.navigate("h", 2)  -- window left x2; at the edge the multiplexer takes over
```

Every function returns `nil, err` (or `false, err`) instead of raising, and reports the
problem to the user.

## Running a TUI from another plugin

`run` with `direct = true` is the entry for a plugin that wants a full-screen program
(lazygit, a REPL, a test watcher) in a terminal window without owning the window code:

```lua
local ok, err, handle = require("terminal").run({ "lazygit", "-p", repo_root }, {
  direct = true,
  name = "lazygit",              -- identity (with the project root); a second call replaces it
  title = "lazygit",             -- float title
  cwd = repo_root,
  float = { width = 0.9, height = 0.9 },
  close = "always",              -- remove window and buffer when the program ends
  env = { NVIM = vim.v.servername },
  on_open = function(h)          -- buffer keymaps etc.; h.bufnr, h.job
    vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = h.bufnr })
  end,
  on_exit = function(code) end,
})
```

`close` is `"always"`, `"success"` (only exit code 0, failures stay readable) or `"never"`
(default). Nothing here is lazygit-specific; the argv is the program.
