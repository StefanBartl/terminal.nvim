# Requirements

- **Neovim 0.11+.** Terminals start with `jobstart({ term = true })` (`termopen()` is deprecated),
  the split layouts use `nvim_open_win({ split = ... })`.
- **Neovim 0.12+ for the WezTerm status export** (tab title, right status): it writes to the host
  terminal with `nvim_ui_send`, which exists since 0.12. On 0.11 everything else works; the export
  stays off and `:checkhealth terminal` says why.
- **tmux 3.1+** for the `tmux` backend's percentage sizes (`split-window -l 30%`); older releases
  get `-p 30` instead (detected once, on the first split).
- **[lib.nvim](https://github.com/StefanBartl/lib.nvim)** — required. It provides the
  keymap registry, the autocommand helpers, the `:Terminal` command composer, notifications
  and the config helpers.

Optional: a Nerd Font is not needed; nothing here draws icons.

`:checkhealth terminal` reports what it found.

## Where it is tested

| Platform | Neovim | What runs | Where |
|---|---|---|---|
| Windows 11 (the author's machine) | 0.12 | all specs; by hand `TESTS/live/smoke.lua` (real UI) and, inside a WezTerm pane, `wezterm.lua`, `navigate.lua`, `pin.lua` | `scripts/test.sh` + by hand |
| Linux / WSL | 0.12 and 0.11 | all specs; `TESTS/live/tmux.lua` and `nested.lua` against a real tmux 3.7 | `scripts/test.sh` + by hand |
| ubuntu, windows, macos | stable | all specs + the conformance gate | CI `tests` |
| ubuntu | 0.11.0 (the minimum) | all specs except the cases that only exist from 0.12 on, + the conformance gate | CI `tests` |
| ubuntu | stable | `TESTS/live/tmux.lua` and `nested.lua` (twice: default and `NVIM_APPNAME`): the tmux backend and status exporter against a real tmux server on a private socket, and the nested-Neovim ownership checks | CI `tmux-live` |

Not covered by CI, and so a hand check before a release: the real workflows in a WezTerm window
(`wezterm.lua`, `navigate.lua`, `pin.lua`; WezTerm has no CI job), the real-UI smoke run
(`smoke.lua`), tmux on macOS, and shells other than the ones the specs model (`nu`, `csh`; unknown
shells are quoted like POSIX shells, set `shell`). Specs that only make sense on one platform are not
registered elsewhere; the runner never counts a skip as a pass. The `0xC0000005` crash that Neovim
0.12 on Windows shows when a running terminal is closed in the wrong order is guarded by the
teardown order in `architecture.md`; it was not seen on the other platforms.

Measured, and not covered by CI: with the **0.11.0 release build on Windows** Neovim itself died with
`0xC0000005` in the specs that close running terminals (`bindings_spec`, `native_spec`; 2026-10-14).
Later 0.11 releases were not tried there. Windows runs on stable in CI.
