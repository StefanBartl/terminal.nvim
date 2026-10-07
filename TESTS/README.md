# Tests

```sh
scripts/test.sh                 # every spec, on testing.nvim
scripts/test.sh --file native   # only spec files whose name contains "native"
```

The runner is [testing.nvim](https://github.com/StefanBartl/testing.nvim); `scripts/test.sh`
finds it and `lib.nvim` (`$TESTING_NVIM_DIR` / `$LIB_NVIM_DIR`, `.deps/`, a sibling checkout,
the plugin manager's folder) and exits non-zero when anything is missing or red.

| Spec | Covers |
|---|---|
| `config_spec.lua` | defaults, merge, validation (event names included) |
| `layout_spec.lua` | pure window geometry |
| `quote_spec.lua` | shell quoting for POSIX / PowerShell / cmd.exe / "portable", hostile words |
| `registry_spec.lua` | registry, project/name resolution, backend detection |
| `native_spec.lua` | the native backend on real windows and jobs |
| `api_spec.lua` | the public facade on the native backend |
| `bindings_spec.lua` | keymaps, autocommands, `:Terminal` |
| `status_spec.lua` | the status dataset, escape sequences, exporters, the delta gate, UI attach |
| `navigate_spec.lua` | window navigation, hand-off commands, the in-flight guard |
| `wezterm_backend_spec.lua` | the WezTerm backend and the facade on it (fake `wezterm cli`) |
| `tmux_backend_spec.lua` | the tmux backend, the tmux status exporter (ownership, `$NVIM`), the facade on it (fake `tmux`) |
| `conformance_spec.lua` | one contract run against every backend |
| `pin_adopt_spec.lua` | pin (order, preflight, ping, restore) and adopt |
| `security_spec.lua` | seeded property specs (xorshift32): quoting, escapes, tmux arguments |
| `health_spec.lua` | `:checkhealth terminal` |

`support/fakes.lua` is a fake `wezterm cli` (with tabs and `list-clients`) and a fake `tmux` that parses
arguments the way tmux does (a trailing `;`). `support/jobs.lua` holds the non-interactive jobs,
`support/env.lua` clears `$TMUX`, `$TMUX_PANE`, `$WEZTERM_PANE`, `$NVIM` so a run inside a multiplexer
behaves like one outside (every spec file starts with it).

## What the specs cannot do — and what covers it

A headless Neovim on **Windows** gives a terminal job a closed stdin: interactive shells
exit at once and writing to the job hangs the editor. So the specs use long-running
non-interactive programs (`support/jobs.lua`) and *record* what `send` would write.
`live/smoke.lua` does the real thing inside a real UI — run it before a release:

```sh
SMOKE_OUT=/tmp/terminal-smoke.txt nvim -u NONE -i NONE -c "luafile TESTS/live/smoke.lua"
```

The other live scripts (`wezterm.lua`, `navigate.lua`, `pin.lua` inside a WezTerm pane; `tmux.lua`
headless against a private tmux server, on Windows with `TMUX_LIVE_WSL=<distro>`; `nested.lua`, the
tmux status exporter's ownership test against a real process tree, Linux/macOS) each write one line per
check and end in `RESULT ok` / `RESULT failed`.

## A Windows crash to know about

Neovim 0.12 on Windows can die with `0xC0000005` when a terminal is closed within a few
hundred milliseconds of a resize or of another terminal job ending. `support/jobs.lua`
`settle()` puts 400 ms in between wherever a spec does that; 300–500 ms of distance never
crashed. It is a Neovim/ConPTY timing issue, not something the plugin can fix.
