# Backends

A backend decides **where a terminal lives**. The API (`toggle`, `open`, `send`, `run`, ...) is
the same for all of them.

| Backend | Terminals are | Chosen |
|---|---|---|
| `native` | Neovim `:terminal` windows (float, split, vsplit, tab) | `backend = "auto"` (default) or `"native"` |
| `wezterm` | panes / tabs of the WezTerm window Neovim runs in | `backend = "wezterm"` |
| `tmux` | panes of the tmux window ([tmux.md](tmux.md)) | `backend = "tmux"` |

`auto` is `native`, also inside WezTerm or tmux: a multiplexer backend is a deliberate choice.
Reporting Neovim's *status* to WezTerm is separate and additive: see [status.md](status.md).
A backend that is named but not available (not inside WezTerm, `wezterm` not on `$PATH`) falls
back to `native` with one notice that says why.

## The `tmux` backend

Panes through the `tmux` CLI (needs `$TMUX`, `$TMUX_PANE`); the same mapping and the same
differences as below. See [tmux.md](tmux.md).

## The `wezterm` backend

Driven through `wezterm cli`; needs `$WEZTERM_PANE` and `wezterm` on `$PATH`.

| API | In WezTerm |
|---|---|
| `open` | `split-pane` (below for `split`, right for `vsplit` and `float`, sized by `split.size`) or `spawn` (`tab`), started in the terminal's directory; the new pane takes focus |
| `send` / `run` | `send-text --no-paste`, the text on **stdin** (no word of it can be read as an option) |
| `toggle` | focuses the pane; when it is focused already, hands focus back to Neovim's pane |
| `hide` | there is no hiding: focus goes back to Neovim's pane |
| `close` | `kill-pane` |
| `list` | `list --format json`; a pane the user closed disappears from the list |

Differences from `native`, on purpose:

- **No floats.** `float` becomes a right split.
- **`env` is refused**: `wezterm cli` cannot set environment variables for a command.
- **The exit of the command is not reported**: `run(..., { direct = true, on_exit = fn })`
  never calls `fn`, and `close = ...` has no effect; the pane closes when the program ends
  (WezTerm's own setting).
- A pane the user closed is replaced by a new one on the next `open`/`toggle`.
- Each call is a short blocking `wezterm cli` process with a timeout (3 s).

Specs run against a fake `wezterm cli` (`TESTS/wezterm_backend_spec.lua`); `TESTS/live/wezterm.lua`
drives a real one inside a WezTerm pane.
