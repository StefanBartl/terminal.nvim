# Navigation across pane borders

`terminal.navigate(dir, count)` (`dir` is `h`, `j`, `k` or `l`) moves to the window in that
direction. When **nothing is further in that direction inside Neovim**, the multiplexer around
it is asked to focus the neighbouring pane — one key moves from Neovim windows into the next
WezTerm / tmux pane, like `vim-tmux-navigator`.

```lua
require("terminal").navigate("l")      -- right; hands off at Neovim's right edge
require("terminal").navigate("h", 2)   -- two windows left
```

## Rules

- **Neovim first.** `wincmd` runs; only if the current window did not change is it the edge.
- **Floats never hand off.** A floating window has no neighbours.
- **Fire-and-forget.** The multiplexer command runs in the background; the key press returns at
  once and a failure (no pane in that direction, the normal case at the outer edge) is ignored.
- **Innermost first.** Inside tmux inside WezTerm only tmux is asked.
- **One process at a time.** A key held down at the edge does not start a process per repeat: while one
  hand-off runs, the latest press waits behind it (and the process has a 2 s timeout).

| Hand-off | Environment | Command |
|---|---|---|
| `wezterm` | `$WEZTERM_PANE` | `wezterm cli activate-pane-direction Left/Down/Up/Right` |
| `tmux` | `$TMUX` | `tmux if-shell -F '#{pane_at_left}' '' 'select-pane -L'` (and `-D`/`-U`/`-R` with `bottom`/`top`/`right`) |

`select-pane -L` alone wraps around at the window's edge and would focus the pane on the far side; the
`pane_at_*` test keeps the key a no-op there.

`navigate.handoff` is `"auto"` (what the environment has), a name, a list of names or `false`.

## Keys

- **Terminal mode** (on by default): `<C-h>` `<C-j>` `<C-k>` leave terminal mode and navigate
  (`window_right` is off, so `<C-l>` stays the shell's clear-screen).
- **Normal mode** (off by default, the editor config usually owns these keys): bind
  `nav_left` / `nav_down` / `nav_up` / `nav_right`, e.g. `keymaps = { nav_left = "<C-h>" }`; a count
  works (`3<C-h>`).

## The other side

For the keys to work *into* Neovim, WezTerm / tmux must pass `<C-h/j/k/l>` on to a pane that runs
Neovim, and handle them itself otherwise: see the WezTerm config's `docs/nvim-status.md`
(`is_nvim`) and the tmux counterpart. Neovim → multiplexer works without any of it.
