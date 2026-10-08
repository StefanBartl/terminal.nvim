# Architecture

```
lua/terminal/
  init.lua            facade: setup, open, toggle, hide, close, list, send, run, navigate, status
  pin.lua             pin: restart a native terminal as a multiplexer pane (gets the facade's `host`)
  adopt.lua           adopt: a pane's screen in a read-only buffer (gets the facade's `host`)
  notify.lua          the one notifier, prefix "[terminal]"
  config/             DEFAULTS.lua (single source of truth), validation + store
  core/               pure logic, no editor state
    layout.lua          window geometry (fractions / absolute cells)
    quote.lua           shell quoting for POSIX, fish, PowerShell, cmd.exe
    registry.lua        the set of terminals (an instance, no module-level table)
    context.lua         project root + terminal name for a call
    navigate.lua        direction and outcome of a window move
    status.lua, osc.lua the status dataset and its terminal escape sequences
  backends/
    init.lua            detection ($TMUX, $WEZTERM_PANE) and resolution
    native.lua          Neovim :terminal in float / split / vsplit / tab
    tmux.lua            panes of the tmux server around Neovim
    wezterm.lua         panes of the WezTerm mux around Neovim
  navigate/             window moves and the hand-off to the multiplexer at the edge
  status/               status export to the terminal around Neovim (collector + exporters)
  bindings/             keymaps (named actions), autocommands, :Terminal
  health.lua            :checkhealth terminal
  @types/               class definitions
```

## How a call travels

`terminal.toggle({ count = 3 })`

1. `context.resolve` turns the configured `cwd` mode and the current buffer into a working
   directory and a **project root**; the name is `"3"`. Root plus name identify the terminal.
2. The registry is asked for a live terminal with that id.
3. The backend decides: visible and focused → `hide`; visible elsewhere → `focus`; hidden →
   `show`; missing → `spawn`. A terminal whose job ended is gone for these purposes.
4. Failures come back as `nil, err` and are reported (deferred, so a command run from a
   script never surfaces a raw Vim error).

## Backends

A backend is a table satisfying `Terminal.Backend`: `available`, `spawn`, `send`, `focus`,
`list`, `close`, plus `probe` (visible + focused in one answer) and optional `visible`,
`focused`, `show`, `hide`, `capture`, `preflight`, `ping`. The
interface is documented in `lua/terminal/@types/init.lua`. `backends.resolve` picks one from
the configured name and the environment; a backend that is not available falls back to
`native` with a notice. A backend keeps its handles in the registry it is given; nothing is
stored at module level, so specs and multiple setups cannot leak into each other.

## Design notes

- **Quoting is its own pure module.** `run` with an argv never builds a line from an
  unquoted string; `core/quote.lua` is tested against hostile words for each shell family.
- **`send` types, it does not execute**, unless asked (`newline = true` / `--exec`).
- **Teardown order:** closing a terminal stops the job, waits for it to end, then removes
  windows and buffer — Neovim 0.12 on Windows can crash when a terminal buffer disappears
  while its ConPTY is still shutting down.
