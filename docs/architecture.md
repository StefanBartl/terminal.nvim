# Architecture

```
lua/terminal/
  init.lua            facade: setup, open, toggle, hide, close, list, send, run, navigate, status
  pin.lua             pin: restart a native terminal as a multiplexer pane (gets the facade's `host`)
  adopt.lua           adopt: a pane's screen in a read-only buffer (gets the facade's `host`)
  notify.lua          the one notifier, prefix "[terminal]"
  config/             DEFAULTS.lua (single source of truth), validation + store
  core/               logic that does not depend on the backend
    layout.lua          window geometry (fractions / absolute cells)
    registry.lua        the set of terminals (an instance, no module-level table)
    context.lua         project root + terminal name for a call
    navigate.lua        direction and outcome of a window move
    env.lua             the one reader of $TMUX / $TMUX_PANE / $WEZTERM_PANE / $NVIM and "inside tmux?"
    errors.lua          how a failed multiplexer call is worded (first line, hint, debug log)
    tmux_word.lua       a data word as a tmux argument (shared by the backend and the exporter)
    exec.lua            process runner for the multiplexer CLIs (`multiplexer.timeout_ms`, 3 s by default)
    status.lua, osc.lua the status dataset and its terminal escape sequences
  backends/
    init.lua            detection ($TMUX, $WEZTERM_PANE) and resolution
    native.lua          Neovim :terminal in float / split / vsplit / tab
    tmux.lua            panes of the tmux server around Neovim
    wezterm.lua         panes of the WezTerm mux around Neovim
  navigate/             window moves and the hand-off to the multiplexer at the edge
  status/               status export to the terminal around Neovim (collector + exporters; nested.lua
                        answers "inside the terminal of another running Neovim?")
  bindings/             keymaps (named actions), autocommands, :Terminal
  health.lua            :checkhealth terminal
  @types/               class definitions (shared ones here; core/, backends/, navigate/ and status/
                        each have their own @types/init.lua, grouped by the file the type belongs to)
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
`list`, `close`, plus the optional `probe` (visible + focused in one answer), `visible`,
`focused`, `show`, `hide`, `capture` (and `capture_async`, used by the `adopt` refresh), `preflight`, `ping`. The
interface is documented in `lua/terminal/@types/init.lua`. `backends.resolve` picks one from
the configured name and the environment; a backend that is not available falls back to
`native` with a notice. A backend keeps its handles in the registry it is given; nothing is
stored at module level (the one exception: the `BufWipeout` watcher of the native backend is a
named autocommand group, bound to the registry of the backend created last), so specs and
multiple setups cannot leak into each other.

## Design notes

- **Quoting is its own pure module.** `run` with an argv never builds a line from an
  unquoted string; `lib.nvim.cross.shell_quote` (the quoting itself, shared with other plugins) is tested against hostile words for each shell family, here with property specs and a real PowerShell.
- **Dependencies are explicit where it pays.** The environment is read once (`core/env.lua`) and
  handed down as a table (`setup()`, `available(env)`, `reliance`), backends and navigation take
  their runner and registry as arguments, and the specs replace single functions (`exporter.run`,
  `default_runner`, `nested.alive`) rather than whole modules. A constructor-injection layer for the
  facade and the exporters (a deps table in `setup()`) was considered and not built: it would add a
  public surface that only the specs use, and the seams above already let them run without a real
  multiplexer.
- **Errors are display strings.** Every function answers `nil, err` or `false, err` with text a person
  can read; there is no error object, and nobody inside the plugin or among its callers branches on
  the kind of failure. A structured type (`lib.lua.error`, kinds such as unavailable / refused / failed)
  would change the documented contract of every function while this is a beta, for no caller that
  needs it. What a failed tmux or WezTerm call says is decided in one place, `core/errors.lua`: the
  first line of the output, plus a short hint where the cause is known ("no server running" -> start
  tmux); the complete output goes to the debug log.
- **`send` types, it does not execute**, unless asked (`newline = true` / `--exec`).
- **Teardown order:** closing a terminal first asks whether Neovim will let its windows and its
  buffer go (a text lock, the command-line window, `winfixbuf` on the window that would have to
  show another buffer); a refusal there leaves the terminal exactly as it was — running, registered,
  no window closed, no listed buffer made (the question is asked with a scratch buffer under
  `:noautocmd`; one unlisted scratch buffer may stay until a text lock is gone). Only then it stops
  the job and waits for it to end, closes the windows and deletes the buffer. A change that happens
  while the job stops (an autocommand of the user) can still leave a finished terminal that is
  registered and visible; the next `close` removes it.
  The order and the pauses are what Neovim 0.12 on Windows survives (`0xC0000005` otherwise):
  the job goes first, because closing the windows of a running terminal that is shown in two
  windows and stopping its job right after kills it every time, however long the pause; and a job is
  stopped no sooner than 100 ms after the last window of this backend was opened or closed, because
  closing one terminal's window resizes its neighbours and stopping a neighbour's job within a few
  milliseconds of that kills it too (`close(a); close(b)` on two running splits). The pause is
  tracked per backend and applies on Windows only. A terminal buffer that disappears while its
  ConPTY is still shutting down can crash it as well: the buffer is deleted after the job ended.
