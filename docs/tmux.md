# tmux

Inside tmux three things work together:

| Part | What it does |
|---|---|
| `backend = "tmux"` | terminals are tmux panes (`split-window`, `send-keys -l --`, `select-pane`, `kill-pane`); see [backends.md](backends.md) |
| status export | the status dataset becomes pane options `@terminal_mode`, `@terminal_file`, `@terminal_branch`, `@terminal_diag`, `@terminal_rec`, `@terminal_mod` for `status-right` / `pane-border-format` ([status.md](status.md)) |
| navigation | at Neovim's edge `tmux if-shell -F '#{pane_at_left}' '' 'select-pane -L'` (and the other three directions): a no-op at the edge of the tmux window instead of `select-pane`'s wrap-around ([navigation.md](navigation.md)) |

## tmux.conf

```tmux
# Let the status reach an OUTER terminal (WezTerm) too: bare sequences never arrive, wrapped ones
# only with this option on.
set -g allow-passthrough on

# Show what Neovim is doing (empty when no Neovim with terminal.nvim runs in the pane).
# The pane's command has to look like a Vim as well: a Neovim that crashed cannot remove its options.
set -g status-right '#{?#{&&:#{@terminal_mode},#{||:#{m:*vim*,#{pane_current_command}},#{||:#{m:vi,#{pane_current_command}},#{m:view,#{pane_current_command}}}}},#{@terminal_mode} #{@terminal_branch} #{@terminal_diag} | ,}%H:%M'
```

`:checkhealth terminal` reports `allow-passthrough` and the detected tmux. The option matters only for
the WezTerm status export (the tmux exporter and the backend never write an escape sequence): measured on
2026-10-07, a bare `OSC 1337` sequence never leaves tmux and a wrapped one arrives only with the option
on ([status.md](status.md#measured)).

A theme plugin that sets `status-right` itself (catppuccin-tmux does, unconditionally, while TPM loads it) replaces
that line. The author's `Configs/terminals/tmux/tmux.conf` keeps the segment in a user option
(`@terminal_status_segment`), references it with `#{E:@terminal_status_segment}` and, after `run '.../tpm'`, puts it
back in front of whatever the theme made; `Configs/terminals/tmux/tests/tmux_conf_check.sh` runs the file against a
fake theme.

## Differences from `native`

Same as the WezTerm backend: no floats (`float` is a right split), `env` is refused, the exit of the
command is not reported, a pane that was closed is replaced on the next `open`. `send` types
literally after `--`, so text like `-l C-c Enter; kill-server` is typed, not interpreted.

tmux reads a trailing `;` of any argument as the end of a command (and `\;` as an escaped one), so every
piece of data that becomes an argument — typed text, a directory, the words of a command, a pane-option
value — is escaped with a backslash in front of a final `;` (`backends.tmux.word`). Without that,
`select 1;` would lose its semicolon and a command word `notes;` followed by `run-shell` would start a
tmux command. `TESTS/live/tmux.lua` types such lines into a pane running `cat` and compares the screen.

The start directory (`-c`) has a second escape: tmux expands that one value as a *format* (`#S`, `#{...}`,
`#(...)`, and `##` for a literal `#`), so a directory called `C#` or `#S` would silently open the pane in `$HOME`.
Every `#` of the directory is doubled before it is passed (`C#` is sent as `C##`). Typed text, command words and
option values are not expanded, so only `-c` needs this. `TESTS/live/tmux.lua` starts panes in real directories
named `C#`, `a##b`, `#S`, `#{pane_id}` and `x#(echo hi)` and asks tmux for `#{pane_current_path}`.

A layout the backend does not know (`float`, `split`, `vsplit` and `tab` are the four) is refused instead of being
guessed as a split. The refusal is part of the backend's `preflight`, so `pin` finds out before it ends the native
terminal.

`tmux 3.1+` takes `split-window -l 30%`; an older tmux gets `-p 30` (the version is asked once, on the
first split; `:checkhealth terminal` shows it).

## Tests

`TESTS/tmux_backend_spec.lua` runs against a fake `tmux`. `TESTS/live/tmux.lua` starts a **private**
server (`tmux -L terminal-nvim-live`) and drives a real one; on Windows with
`TMUX_LIVE_WSL=<distro>` through `wsl.exe -e tmux`. CI runs it on ubuntu.

See also: [references.md](references.md) for the tmux manual sections (`allow-passthrough`,
`set-option`, `send-keys`, `split-window`) the backend and the exporter rest on.
