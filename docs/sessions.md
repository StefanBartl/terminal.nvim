# Terminals in sessions

With [sessions.nvim](https://github.com/StefanBartl/sessions.nvim) a session brings its terminals
back: the terminals of the project are written next to the session file when it is saved and
reopened when it is loaded. **No process is saved.** A reopened terminal is a fresh shell, or a
fresh start of its command, and it comes back **hidden**; `toggle` shows it.

The two plugins do not require each other. sessions.nvim fires two `User` events, terminal.nvim
listens:

| Event | Data | terminal.nvim |
|---|---|---|
| `SessionsSavePost` | `{ name, path, tab }` | writes `.<session>.terminals.json` beside the session file |
| `SessionsLoadPost` | `{ name, path, tab }` | reads it and reopens what is not there yet |

A tab snapshot (`:Session save-tab`) carries no terminals: `tab` is `true` and both events are
ignored.

## What is saved

For every live terminal of the project that runs in a native window: its **name**, **layout**,
**directory**, and the **command** when it was started with `run(cmd, { direct = true })`. A command
typed into a shell (`run` without `direct`, `send`) is not recorded; the shell is. Terminals in a
tmux or WezTerm pane are left out: the multiplexer keeps them, Neovim does not have to.

With no terminal left, the file is removed, so a session never brings back terminals it no longer
had.

## What happens on load

- A terminal that already exists under the same name is left alone. Loading a session twice, or
  with a terminal of that name open, neither duplicates nor replaces anything.
- A saved **command** is a recipe, and loading a session must not run it on its own accord.
  `sessions.commands` says what happens:

  | Value | Effect |
  |---|---|
  | `"ask"` (default) | once per load, when the session has any command: *Start the commands* / *Open plain shells* / *Skip the terminals*. Dismissing the prompt skips. |
  | `"run"` | start the commands |
  | `"never"` | open those terminals as plain shells |

  A session whose terminals are all plain shells is never asked about.
- What cannot be reopened is reported in one warning, and the rest is reopened anyway.

## Options

```lua
require("terminal").setup({
  sessions = {
    enable = true,       -- false: do not listen to the events at all
    commands = "ask",    -- "ask" | "run" | "never"
  },
})
```

## Trade-offs

- The sidecar belongs to the session file by name. `:Session rename` and `:Session delete` of
  sessions.nvim move and remove the sidecars they know, and this one is not among them: after a
  rename the session starts without terminals until it is saved once more, and a deleted session
  leaves its small file behind. Every save writes the file anew (or removes it), so a leftover never
  brings terminals back into a session saved later under that name.
- The directory of a `run` with `direct` is restored; a plain shell starts where the `cwd` option
  puts it (`project` by default), which for a session of one project is the same place.
