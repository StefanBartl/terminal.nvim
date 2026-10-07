# Status export

terminal.nvim tells the terminal around it what this Neovim is doing, so a WezTerm tab can
show the file name and the right status can show mode, branch and diagnostics — without
asking Neovim anything.

## What is published

A small, versioned dataset of **raw values** (no icons, no colours — those belong to the
receiving side):

| Field | Meaning |
|---|---|
| `v` | schema version (now `1`); a receiver ignores unknown fields and refuses a higher version |
| `pid` | the Neovim process |
| `mode` | `nvim_get_mode().mode` (`n`, `i`, `v`, `V`, `t`, ...); the two control-character modes are spelled out: `^V` (blockwise Visual, `no^V` operator-pending) and `^S` (Select block) |
| `file`, `ft` | file name (last path component; `terminal` for terminal buffers) and filetype |
| `cwd`, `branch` | working directory and git branch (from gitsigns, else `.git/HEAD`) |
| `e`, `w`, `i`, `h` | diagnostic counts: error, warning, info, hint |
| `rec` | register being recorded into, `""` when none |
| `mod` | the buffer is modified |

Every string is sanitised (control characters become `?`) and shortened; a dataset above
`status.max_bytes` (1024) is cut down field by field and finally refused rather than sent
half. The values are file and branch names: attacker-controlled text that ends up in a tab
title.

## When it is sent

Only on events that can change a field — mode, buffer, directory, diagnostics, macro
recording, the modified flag, focus — debounced (`status.debounce_ms`, 80), and **only when
what an exporter publishes differs from what it sent last** (the tmux exporter carries mode, file, branch,
E/W counts, macro and modified flag: a change in `cwd`, filetype or the info and hint counts costs it no
process). An exporter that fails is switched off once, with one notice — and still cleaned up when
Neovim exits. A Neovim **without a UI** (a headless script) publishes nothing, silently; the status goes
out when a UI attaches (`UIEnter`) — also to a UI that attaches *again* (another WezTerm pane after
`:detach`): it has seen nothing, so the "nothing changed" gate is reset for it. A dataset over `status.max_bytes` is reported once, not on every event.

## Exporters

| Exporter | Where | How |
|---|---|---|
| `tmux` | inside tmux (`$TMUX`) | pane options `@terminal_mode`, `@terminal_file`, `@terminal_branch`, `@terminal_diag`, `@terminal_rec`, `@terminal_mod` ([tmux.md](tmux.md)) |
| `wezterm` | inside WezTerm (`$WEZTERM_PANE`) | per-pane user variables via OSC 1337 `SetUserVar` (`MUX_NVIM`, `MUX_PIPE`, `MUX_STATUS`) |

`status.export = "auto"` uses every exporter whose environment signal is present; a name or
a list picks explicitly; `false` sends nothing. The sequence is written with
`nvim_ui_send` (**Neovim 0.12+**) in **one** call; under tmux it is wrapped in the passthrough
envelope (and tmux needs `set -g allow-passthrough on`).

The tmux exporter writes options of the pane in `$TMUX_PANE`, so only the Neovim that **owns** the pane
may: `auto` skips a Neovim that runs inside the terminal of another **running** Neovim (`$NVIM` names a
server that answers *and* is an ancestor of this process — `git commit` opening a nested editor must not
overwrite the outer one's status). A tmux server that was merely *started* from a Neovim terminal hands
`$NVIM` to every pane for good, but a Neovim in one of its panes is not a descendant of that terminal: it
owns its pane and exports (the process tree is read from `/proc`, or `ps`; where it cannot be read, or the
address names no process — a custom `--listen` — a running outer Neovim counts as the owner). A name
(`export = "tmux"`) forces the exporter, and the options are removed on exit only by the instance that wrote
them. `set-environment -gu NVIM` in `tmux.conf` (the Configs repo has it) keeps the variable out of the panes
altogether.

## The WezTerm side

`Configs/terminals/wezterm/config/nvim_status.lua` reads the variables, validates them again
and returns the tab title text and the right-status items. See that repo's
`docs/nvim-status.md`.

## Measured

On WezTerm 20240203, Windows, Neovim 0.12: every update arrives, in order, without loss
(200 updates at ~15 ms); payloads up to 64 KiB arrive intact; an empty value means "not
set". `update-status` only sees the focused pane of a window, so the right status shows the
focused pane's Neovim; the tab title is computed per tab.
