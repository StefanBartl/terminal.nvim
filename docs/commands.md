# Commands (`:Terminal`)

One compound command, `:Terminal <action> [args] [flags]`, with `<Tab>` completion.

| Command | Does |
|---|---|
| `:Terminal` | Toggle the default terminal. |
| `:Terminal toggle [name] [--layout=]` | Focus when visible elsewhere, hide when focused, show when hidden, create when missing. |
| `:Terminal open [name] [--layout=]` | Show and focus; create when needed. |
| `:Terminal hide [name]` | Close the window; the job keeps running. |
| `:Terminal close [name]` | Stop the job and remove the terminal. |
| `:Terminal pin [name] [--backend=tmux\|wezterm] [--layout=]` | Restart a native terminal as a pane of tmux/WezTerm so it outlives Neovim (see below). |
| `:Terminal adopt [name]` | Show a tmux/WezTerm terminal's screen in a read-only buffer. |
| `:Terminal list` | Pick one of this project's terminals (`vim.ui.select`). |
| `:Terminal send line [name] [--exec]` | Type the current line. |
| `:'<,'>Terminal send selection [name] [--exec]` | Type the selection (see below). |
| `:Terminal send file [name] [--exec]` | Type the whole buffer. |
| `:Terminal run [--name=] [--layout=] [--direct] <command...>` | Run a command (see below). |

`name` defaults to the configured `default_name` (`main`); `3` is the terminal "3" that
`3<A-h>` uses. `--layout=` is `float`, `split`, `vsplit` or `tab`.

`<Tab>` completes `name` from the terminals that are open in this project, read when you press the
key. `hide`, `close`, `pin` and `adopt` offer only those; `toggle`, `open`, `send` and `--name=`
also offer `default_name`, `run.name` and the counts 1 to 9, and accept any other name (a name that
is not open is reported by the command).

## Pin and adopt

`pin` is **not** a transfer: a process cannot move between a Neovim `:terminal` and a pane. The
native terminal is closed and the same command (and directory) is started again in a pane of tmux
or WezTerm, under the same name; output and shell history of the old one are gone. The old job ends
**before** the pane starts (a server or watcher must not run twice at once). What the multiplexer is
known to refuse — `env` is set, which a pane cannot take — and a multiplexer that does not answer are
checked first, so such a pin changes nothing; if the pane cannot be started anyway (no room, a CLI error
after it answered), a native terminal is started again so you keep one (a new one: the old output is
gone either way) and the message says whether that worked. From
then on `toggle`, `send`, `close` act on the pane. The backend is tmux inside tmux, else WezTerm.

`adopt` shows a pane's screen (`wezterm cli get-text` / `tmux capture-pane -p`) in a read-only
buffer named `terminal://<backend>/<pane>/<name>`. It is a *view*: it refreshes once a second
while visible and says so when the pane is gone. Control characters in the text are replaced.

## What `send selection` sends

The selection is what you selected: a **characterwise** selection (`v`) sends exactly those
characters, a **blockwise** one (`CTRL-V`) the block (one line per row; made with `$`, every row to
its own end), a **linewise** one (`V`) or a plain range (`:2,3Terminal send selection`) whole lines.
A selection that spans several lines needs `--exec` (see below).

The selection is only used when the command line that runs the command starts with the range
`'<,'>` (or its alias `*`): `:` pressed in Visual mode, `:'<,'>Terminal send selection` typed by
hand, or a mapping whose right-hand side starts with `:`. A linewise selection, a numeric range
(`:2,3Terminal send selection`, also when it covers the lines of an older selection) and a call
without a command line (a `<Cmd>` mapping, `vim.cmd()` from Lua) send whole lines.

## Typing versus executing

`send` only **types**: the text appears at the prompt. `--exec` adds the Enter key.
This is deliberate — a selection that contains a line break would otherwise run each line.

## `run`

- `:Terminal run npm test` types the line exactly as given into the `run` terminal and
  presses Enter. It is your text.
- From Lua, `require("terminal").run({ "git", "commit", "-m", msg })` takes an **argv list**
  and quotes every word for the terminal's shell (POSIX, PowerShell or cmd.exe), so a
  message with spaces, quotes or `$(...)` stays data. A word with any control character —
  a line break, NUL, ESC, **TAB** — is refused: a line break ends the command line, and a TAB makes
  the shell's line editor complete inside the quotes and close them. Two shells refuse a little
  more: `cmd.exe` a word containing `%` (it cannot quote one), PowerShell a word containing a double
  quote, a word with white space that ends in a backslash, the empty word and the word `--%`
  (Windows PowerShell 5.1 and `pwsh` before 7.3 would hand the program the first two split, cut or
  swallowing the next argument, and the other two never arrive at all, so every argument after
  them would move up one place: no single quoting is right): pass such a word with
  `direct = true`. In POSIX shells and `fish` the first word, the program, stays bare only when it
  is a plain program name (letters, digits, `_ / . + -`); anything else is quoted, because a bare
  `NAME=value` in that place would be read as an environment assignment. The shells covered are POSIX
  (`sh`, `bash`, `zsh`), `fish`, PowerShell and `cmd.exe`; any other shell (`nu`, `csh`, ...) is quoted
  as POSIX, which is a guess for it. In a **tmux or WezTerm pane** the shell is the
  multiplexer's default, which Neovim cannot see: set `shell` (e.g. `shell = "pwsh"`) and the words
  are quoted for it; without it only words made of letters, digits and `. _ / : -` are accepted
  (they mean the same in every shell) and anything else is refused with that hint.
- `--direct` starts the command as the job itself (no shell in between; under tmux a one-word argv is run as a
  program, not read as a shell line). The terminal stays
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
terminal.names()         -- their names, straight from the registry (no multiplexer is asked)
terminal.send("ls", { newline = true, name = "repl" })
terminal.run({ "git", "status" })
terminal.status()        -- { ready, backend, terminals }
terminal.navigate("h", 2)  -- window left x2; at the edge the multiplexer takes over
```

Every function returns `nil, err` (or `false, err`) instead of raising. Only a programmer error
raises: `navigate` with a direction that is not `h`, `j`, `k` or `l`, or with a count that is not a
number from 0 up.

- `open`, `toggle`, `send`, `run`, `pin` and `adopt` also **show** the failure to the user.
- `hide` and `close` only **answer**: `false, "no terminal 'build' in this project"` when there is
  none, or `false, "...cannot close the window: E565: ..."` when Neovim refuses to close the window
  (`winfixbuf`, a text lock, the command-line window), without a message, so a script can probe with
  them. A terminal whose window will not close stays registered and can be closed again later. The
  `:Terminal hide|close` command shows the reason.
- A target must be a table with a non-empty string `name`, a `layout` of `float`, `split`, `vsplit`
  or `tab`, a boolean `focus`, and a `count` that is a number from 1 up (a fraction is cut off: `3.9`
  is terminal `"3"`; `0` or `nil` mean the default terminal; `count` is ignored when `name` is given);
  anything else fails with that reason and starts nothing. For `send` and `run` a `count` of `0` or
  `nil` means the `run.name` terminal.
- The program (first word) of a `run` argv with `direct = true` has to be a non-empty string; every
  word has to be a string without a NUL byte, and an empty word from the second on is data
  (`{ "rg", "", "file" }` searches for the empty pattern). `pin` takes the `layout` of the pane from `float`, `split`, `vsplit` or `tab` and refuses anything
  else before it touches the native terminal.
- The handles that come back (`open`, `list`, `run` with `direct`) are the registry's own records,
  not copies: read them, do not write to them.
- A throwing `on_open` or `on_exit` callback is reported (`run: on_exit failed: ...`) and does not
  take the terminal with it.

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
