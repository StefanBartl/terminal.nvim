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
| Windows 11 (the author's machine) | 0.12 | all specs, `TESTS/live/*` against a real WezTerm | by hand + `scripts/test.sh` |
| Linux / WSL | 0.12 | all specs, `TESTS/live/tmux.lua`, `nested.lua` against a real tmux 3.7 | by hand |
| ubuntu, windows, macos | stable | all specs + the conformance gate | CI `tests` |
| ubuntu | 0.11.0 (the minimum) | all specs + the conformance gate | CI `tests` |
| ubuntu | stable | the tmux backend and status exporter against a real tmux server (private socket), including the nested-Neovim ownership checks | CI `tmux-live` |

Not covered by CI, and so a hand check before a release: the real workflows in
a WezTerm window on Windows (`TESTS/live/wezterm.lua`, `navigate.lua`, `pin.lua`) and tmux on
Linux and macOS, and shells other than the ones the specs model (`nu`, `csh`; unknown shells are
quoted like POSIX shells, set `shell`). Specs that only make sense on one platform are not
registered elsewhere; the runner never counts a skip as a pass. The `0xC0000005` crash that
Neovim 0.12 on Windows shows when a running terminal is closed in the wrong order is guarded by
the teardown order in `architecture.md`; it cannot be reproduced on the other platforms.

Known, not covered by CI: on **Windows with Neovim 0.11.0** the editor itself died with
`0xC0000005` in the specs that close running terminals (`bindings_spec`, `native_spec`; measured
2026-10-14 with the 0.11.0 release build). The CI minimum run is therefore Linux only; on Windows
use 0.12 or newer.
