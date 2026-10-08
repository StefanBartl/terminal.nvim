# Status export

terminal.nvim tells the terminal around it (WezTerm, tmux) what this Neovim is doing, so a
WezTerm tab can show the file name and the right status (WezTerm's, or tmux's `status-right`)
can show mode, branch and diagnostics — without asking Neovim anything.

## What is published

A small, versioned dataset of **raw values** (no icons, no colours — those belong to the
receiving side):

| Field | Meaning |
|---|---|
| `v` | schema version (now `1`); a receiver ignores unknown fields and refuses a higher version |
| `pid` | the Neovim process |
| `mode` | `nvim_get_mode().mode` (`n`, `i`, `v`, `V`, `t`, ...); the two control-character modes are spelled out: `^V` (blockwise Visual, `no^V` operator-pending) and `^S` (Select block) |
| `file`, `ft` | file name (last path component; `terminal` for terminal buffers) and filetype |
| `cwd`, `branch` | working directory and git branch (from gitsigns, else `.git/HEAD`). The search starts at the directory of the buffer's file, or at the working directory for a buffer that is not a file (a terminal, `oil://`), so the branch follows `:cd`. Where the repository was found is remembered for 2 s, so a `git init` below a known repository shows up within that time; a branch switch is seen at once, because the `HEAD` file is checked on every update. In a git worktree or a submodule (`.git` is a file there) there is no branch unless gitsigns supplies one |
| `e`, `w`, `i`, `h` | diagnostic counts: error, warning, info, hint |
| `rec` | register being recorded into, `""` when none |
| `mod` | the buffer is modified |

Every string is sanitised (control characters become `?`) and shortened; a dataset above
`status.max_bytes` (1024) is cut down field by field and finally refused rather than sent
half. The values are file and branch names: attacker-controlled text that ends up in a tab
title.

### Limits

Every free-text field comes from a name somebody else chose (a file, a directory, a branch, a
filetype) and has no length of its own, so each one is capped before it leaves Neovim:

| Field | Cap | Why |
|---|---|---|
| `mode` | 4 characters | the longest mode code is `no^V`; anything else is a code that does not exist |
| `file` | 120 | a tab title or status segment shows a fraction of that; a path component can be 255 bytes |
| `ft` | 40 | filetype names are short; a plugin or a modeline can set any text |
| `cwd` | 200 | a deep directory is shown shortened anyway |
| `branch` | 80 | a git ref name has no hard limit |
| `rec` | 4 | a register is one character; the rest is room for a multibyte one |
| `e`, `w`, `i`, `h` | 99999 | keeps the number short in a title |
| whole dataset | `status.max_bytes` (1024) | one update stays one small write to the terminal |

When the dataset is still above `status.max_bytes`, the longest fields are shortened in steps
until it fits: `cwd` to 80, then 40, then dropped; `file` to 60, 30, 12; `branch` to 40, 20, 8.
The most useful fields (mode, file, branch) are the last to lose characters. The file name is
found by scanning from the end of the path, not with a pattern, so a buffer name made of
thousands of slashes costs time in proportion to its length, not to its square (the pattern form
needed five seconds for 40,000 slashes).

## When it is sent

Only on events that can change a field — mode, buffer, directory, diagnostics, macro
recording, the modified flag, focus — debounced (`status.debounce_ms`, 80), and **only when
what an exporter publishes differs from what it sent last** (the tmux exporter carries mode, file, branch,
E/W counts, macro and modified flag: a change in `cwd`, filetype or the info and hint counts costs it no
process). An exporter that fails is switched off once, with one notice — and still cleaned up when
Neovim exits. A Neovim **without a UI** (a headless script) publishes nothing and leaves nothing behind to clean
up, so it exits without a notice; the status goes
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
owns its pane and exports. The outer Neovim's process id is **asked of the server** (a short-lived
`nvim --headless --server <address> --remote-expr getpid()` with a 1.5 s timeout, only when `$NVIM` is set and
answers; nothing is read from the address, so `NVIM_APPNAME`, a custom `--listen` name or a TCP address all work),
the process tree comes from `/proc` (or `ps`). Where either cannot be found out — the outer Neovim is busy
and does not answer in time, no readable process tree (Windows) — it is taken to own the pane and this one
stays out. A name (`export = "tmux"`) forces the exporter, and the options are removed on exit only by the
instance that wrote them. `set-environment -gu NVIM` in `tmux.conf` (the Configs repo has it) keeps the variable
out of the panes altogether.

## The WezTerm side

`Configs/terminals/wezterm/config/nvim_status.lua` reads the variables, validates them again
and returns the tab title text and the right-status items. See that repo's
`docs/nvim-status.md`.

## Measured

On WezTerm 20240203, Windows, Neovim 0.12: `nvim_ui_send` is the right channel from an embedded
Neovim to the host terminal; every update arrives, in order, without loss (200 updates at
~15 ms); payloads up to 64 KiB arrive intact; an empty value means "not set". `update-status`
only sees the focused pane of a window, so the right status shows the focused pane's Neovim;
the tab title is computed per tab.

Under tmux (measured 2026-10-07): a bare `OSC 1337` sequence never reaches the outer terminal;
wrapped in tmux's passthrough envelope it arrives only with `allow-passthrough on`
([tmux.md](tmux.md)). That is why the exporter wraps every sequence when `$TMUX` is set.

The tmux exporter writes no escape sequence: it sets the pane options through the `tmux` CLI
(one process per publication), so nothing in it depends on passthrough.

See also: [tmux.md](tmux.md) for the tmux side, [references.md](references.md) for the
WezTerm, iTerm2, tmux and Neovim documentation this rests on.
