# Bindings

## Keymaps

Bound at `setup()` unless `keymaps = { preset = false }`. Move one with
`keymaps = { toggle = "<A-x>" }`, drop one with `toggle = false`.

| Action | Default | Mode | Does |
|---|---|---|---|
| `toggle` | `<A-h>` | normal, terminal | Toggle the terminal. A count picks terminal N (`3<A-h>`). |
| `normal_mode` | `<Esc>`, `<C-c>` | terminal | Leave terminal mode (`<C-\><C-n>`). |
| `clear` | off | terminal | `cls` on Windows, `clear` elsewhere. Off by default: `<C-l>` clears in the shell itself. |
| `window_left` | `<C-h>` | terminal | Window left (`<C-\><C-w>h`). |
| `window_down` | `<C-j>` | terminal | Window down. |
| `window_up` | `<C-k>` | terminal | Window up. |
| `window_right` | off | terminal | Window right. Off by default so `<C-l>` stays the shell's clear-screen. |

## Commands

See [commands.md](commands.md): `:Terminal` with `toggle open hide close list send run`.

## Autocommands

Each in its own augroup `terminal.<feature>`:

| Group | Event | Does | Option |
|---|---|---|---|
| `terminal.window_options` | `TermOpen` | Local window options for terminal windows. | `window_options.enable` |
| `terminal.kitty_enter` / `kitty_leave` | `VimEnter` / `VimLeavePre` | Kitty padding while editing. | `kitty.enable` |
| `terminal.auto_insert` | `auto_insert.events` | Enter Insert mode in terminal buffers. | `auto_insert.enable` |
