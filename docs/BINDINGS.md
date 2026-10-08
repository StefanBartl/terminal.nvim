# Bindings

Everything the plugin binds: keymaps, the `:Terminal` command, and the autocommands. Nothing
else is defined (no other commands, no `<Plug>` mappings, no buffer-local maps).

## Keymaps

Bound at `setup()` unless `keymaps = { preset = false }`. Move one with
`keymaps = { toggle = "<A-x>" }`, drop one with `toggle = false`. A second `setup()` first removes
the maps the first one created (only those that still carry the plugin's description, so a map you
set on the same key afterwards stays), then binds again.

| Action | Default | Mode | Does |
|---|---|---|---|
| `toggle` | `<A-h>` | normal, terminal | Toggle the terminal. A count picks terminal N (`3<A-h>`). |
| `normal_mode` | `<Esc>`, `<C-c>` | terminal | Leave terminal mode (`<C-\><C-n>`). |
| `clear` | off | terminal | Types `cls` when the terminal's shell is cmd.exe or PowerShell and `clear` for every other shell. The shell decides (`shell`, else Neovim's `'shell'`), not the OS: Git Bash or WSL on Windows get `clear`. Off by default: `<C-l>` clears in the shell itself. |
| `window_left` | `<C-h>` | terminal | Window left; at Neovim's edge the multiplexer focuses the pane on that side ([navigation](navigation.md)). |
| `window_down` | `<C-j>` | terminal | Window down (hands off at the edge). |
| `window_up` | `<C-k>` | terminal | Window up (hands off at the edge). |
| `window_right` | off | terminal | Window right. Off by default so `<C-l>` stays the shell's clear-screen. |
| `nav_left` `nav_down` `nav_up` `nav_right` | off | normal | The same navigation from normal mode, with a count (`3<C-h>`). Off by default: bind them to the keys you use, e.g. `nav_left = "<C-h>"`. |

## Commands

One command, created unless `commands = false`; see [commands.md](commands.md): bare `:Terminal`
toggles the default terminal, and `:Terminal` with `toggle open hide close pin adopt list send run`
does the rest.

`<Tab>` completes the terminal name from the terminals that are open in this project (read when
the key is pressed). `:Terminal send selection` sends exactly the selected characters for a
characterwise (`v`) selection, the block for a blockwise one and whole lines for a linewise one or
a plain range.

## Autocommands

Each in a named augroup (`terminal.<feature>`); `setup()` clears and rebuilds them, so calling it
twice does not double a handler.

| Group | Event | Does | Option |
|---|---|---|---|
| `terminal.window_options` | `TermOpen` | Local window options for terminal windows. | `window_options.enable` |
| `terminal.kitty_enter` / `kitty_leave` | `VimEnter` / `VimLeavePre` | Kitty padding while editing (only inside Kitty). | `kitty.enable` |
| `terminal.auto_insert` | `auto_insert.events` (default `TermOpen`) | Enter Insert mode in terminal buffers. | `auto_insert.enable` (off by default) |
| `terminal.status` | `ModeChanged` `BufEnter` `BufFilePost` `BufModifiedSet` `DirChanged` `DiagnosticChanged` `RecordingEnter` `RecordingLeave` `FocusGained` `WinEnter` | Publish the status dataset (debounced; see [status.md](status.md)). | `status.enable` |
| `terminal.status` | `UIEnter` | Send the status to a newly attached UI; what was sent to an earlier one is not held back. | `status.enable` |
| `terminal.status` | `VimLeavePre` | Clear the published status (pane options, user variables). | `status.enable` |
| `terminal.status` | `VimEnter` (once) | First publication, only when `setup()` ran before Neovim had started; otherwise it is published at once. | `status.enable` |
| `terminal.native` | `BufWipeout` | Forget the handle of a native terminal whose buffer was wiped by other means (`:bwipeout`, another plugin). One autocommand for all terminals. | none: created with the native backend |

The `terminal.status` autocommands exist only while status export is on and at least one exporter
fits the environment (inside tmux or WezTerm, `status.export`); otherwise the group stays empty.
