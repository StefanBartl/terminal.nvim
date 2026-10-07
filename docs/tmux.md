# tmux

Inside tmux three things work together:

| Part | What it does |
|---|---|
| `backend = "tmux"` | terminals are tmux panes (`split-window`, `send-keys -l --`, `select-pane`, `kill-pane`); see [backends.md](backends.md) |
| status export | the status dataset becomes pane options `@terminal_mode`, `@terminal_file`, `@terminal_branch`, `@terminal_diag`, `@terminal_rec`, `@terminal_mod` for `status-right` / `pane-border-format` ([status.md](status.md)) |
| navigation | at Neovim's edge `tmux select-pane -L/-D/-U/-R` ([navigation.md](navigation.md)) |

## tmux.conf

```tmux
# Let the status reach an OUTER terminal (WezTerm) too: bare sequences never arrive, wrapped ones
# only with this option on.
set -g allow-passthrough on

# Show what Neovim is doing (empty when no Neovim with terminal.nvim runs in the pane).
set -g status-right '#{?#{@terminal_mode},#{@terminal_mode} #{@terminal_branch} #{@terminal_diag} | ,}%H:%M'
```

`:checkhealth terminal` reports `allow-passthrough` and the detected tmux.

## Differences from `native`

Same as the WezTerm backend: no floats (`float` is a right split), `env` is refused, the exit of the
command is not reported, a pane that was closed is replaced on the next `open`. `send` types
literally after `--`, so text like `-l C-c Enter; kill-server` is typed, not interpreted.

## Tests

`TESTS/tmux_backend_spec.lua` runs against a fake `tmux`. `TESTS/live/tmux.lua` starts a **private**
server (`tmux -L terminal-nvim-live`) and drives a real one; on Windows with
`TMUX_LIVE_WSL=<distro>` through `wsl.exe -e tmux`. CI runs it on ubuntu.
