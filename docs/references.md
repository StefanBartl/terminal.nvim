# References

The primary sources terminal.nvim rests on, and what depends on each. What was measured on
real terminals (as opposed to what the manuals promise) is in [status.md](status.md#measured).

## WezTerm

- [User variables](https://wezterm.org/recipes/passing-data.html) — the status export to
  WezTerm: the `wezterm` exporter sets per-pane user variables (`MUX_NVIM`, `MUX_PIPE`,
  `MUX_STATUS`) that the WezTerm config reads ([status.md](status.md)).
- [`wezterm cli`](https://wezterm.org/cli/cli/index.html) — the `wezterm` backend and the
  navigation hand-off: `split-pane`, `spawn`, `send-text`, `list`, `list-clients`, `get-text`,
  `activate-pane`, `activate-pane-direction` and `kill-pane`
  ([backends.md](backends.md), [navigation.md](navigation.md)).

## iTerm2

- [Proprietary escape codes](https://iterm2.com/documentation-escape-codes.html) — the
  `OSC 1337 ; SetUserVar=<name>=<base64 value>` sequence the WezTerm exporter writes is
  documented there (the same form WezTerm accepts).

## tmux

All of these are sections of the [tmux manual](https://man.openbsd.org/tmux.1):

- [`allow-passthrough`](https://man.openbsd.org/tmux.1#allow-passthrough) — without it a
  sequence for the outer terminal (the WezTerm user variables) never leaves tmux; the exporter
  wraps it in the passthrough envelope and `:checkhealth terminal` reports the option
  ([tmux.md](tmux.md)).
- [`set-option`](https://man.openbsd.org/tmux.1#set-option) — the pane options
  (`set-option -p`, `@terminal_mode` and the others) of the tmux status exporter.
- [`send-keys`](https://man.openbsd.org/tmux.1#send-keys) — `send` into a tmux pane (`-l --`:
  the text is typed literally, never read as a key name or an option).
- [`split-window`](https://man.openbsd.org/tmux.1#split-window),
  [`select-pane`](https://man.openbsd.org/tmux.1#select-pane) and
  [`capture-pane`](https://man.openbsd.org/tmux.1#capture-pane) — opening, focusing and viewing
  (`adopt`) a pane with the `tmux` backend.
- [`if-shell`](https://man.openbsd.org/tmux.1#if-shell) — the edge test of the navigation
  hand-off (`if-shell -F '#{pane_at_left}' ...`, [navigation.md](navigation.md)).

## Neovim

- [`nvim_ui_send()`](<https://neovim.io/doc/user/api/#nvim_ui_send()>) — how an embedded Neovim
  writes to the host terminal; the status export to WezTerm needs it, hence Neovim 0.12+
  ([requirements.md](requirements.md)).
- [`:help terminal`](https://neovim.io/doc/user/terminal/) — the `:terminal` buffers the
  `native` backend is built on.
