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
back to `native` with one notice that says why. A multiplexer backend is looked at only when the
config names it (or `pin` / a pinned terminal needs it): finding `wezterm` or `tmux` on `$PATH`
(a `vim.fn.executable` lookup) takes tens of milliseconds on Windows and `setup()` does not pay that
on every start.

A native terminal can be restarted as a multiplexer pane with `:Terminal pin`, and a pane's screen
shown in a read-only buffer with `:Terminal adopt` ([commands.md](commands.md#pin-and-adopt)).

## Asking a multiplexer

`open`, `toggle` and `list` ask the multiplexer **once** (one `list` process answers "does the pane
exist" and "does it have focus"); `list` asks nothing when no pane is registered. A query that
**fails** (a timeout, a hung mux) means "unknown", not "gone": the pane is never replaced or killed on the
strength of a failed question, and `close` keeps a pane it could not kill registered and says so.
Toggling a pane in another WezTerm tab asks the client which pane has focus (`list-clients`), because
`is_active` in the pane list only means "active within its own tab".

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
- **No shell in between**: a `shell` (or command) given as a string with arguments, `"pwsh -NoLogo"`, is split
  on white space for the pane (a string that is an executable as it stands, such as a path with spaces, is
  kept in one piece; quotes are not interpreted: use a list for those). `native` hands such a string to
  Neovim's `jobstart`, which runs it through the shell.
- **The exit of the command is not reported**: `run(..., { direct = true, on_exit = fn })`
  never calls `fn`, and `close = ...` has no effect; the pane closes when the program ends
  (WezTerm's own setting).
- A pane the user closed is replaced by a new one on the next `open`/`toggle`.
- Each call is a short blocking `wezterm cli` process with a timeout (3 s).

Specs run against a fake `wezterm cli` (`TESTS/wezterm_backend_spec.lua`); `TESTS/live/wezterm.lua`
drives a real one inside a WezTerm pane.

See also: [references.md](references.md) for the `wezterm cli` and tmux manual pages the multiplexer
backends call.
