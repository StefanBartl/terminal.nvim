> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# terminal.nvim

```
████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗
╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║
   ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║
   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║
   ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝
                                                            .nvim
```

> Built on [lib.nvim](https://github.com/StefanBartl/lib.nvim) — keymaps, autocommands,
> the `:Terminal` command and notifications all come from it. Pairs well with
> [sessions.nvim](https://github.com/StefanBartl/sessions.nvim) and
> [ui.nvim](https://github.com/StefanBartl/ui.nvim).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/terminal.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/terminal.nvim/actions/workflows/ci.yml)
[![wkd](https://img.shields.io/badge/wkd-family-c6ff3d)](https://stefanbartl.github.io/wkd/p/terminal/)

> Part of the [wkd](https://stefanbartl.github.io/wkd/) family — see this plugin's [page](https://stefanbartl.github.io/wkd/p/terminal/) on the site.

Named, per-project terminals in Neovim: a float, split, vsplit or tab that you toggle
with one key, that keeps running while it is hidden, and that you can **type into** from
your buffers — a line, a selection, a file, or a command whose arguments are quoted for
your shell so a file name with a space or a `$(...)` stays data.

```
<A-h>         toggle the terminal       3<A-h>  toggle terminal "3"
:Terminal run --direct make test       run a command as the job; the window stays after it ends
:Terminal send selection --exec        type the selection into the terminal and press Enter
```

The terminal layer is a **backend** behind one API: `native` (Neovim's own `:terminal`, the
default), `tmux` and `wezterm` (terminals as panes of the multiplexer Neovim runs in).
`:Terminal pin` restarts a native terminal as such a pane so it outlives Neovim, and
`:Terminal adopt` shows a pane's screen in a read-only buffer. Beside that, Neovim reports
what it is doing (mode, file, branch, diagnostics) to tmux and WezTerm, and one key moves
from a Neovim window into the neighbouring pane across the border.

## Table of contents

- [Documentation](#documentation)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md) — what is where, and which question each page
answers.

### The Basics

- [Requirements](docs/requirements.md) — Neovim version (0.11+, 0.12+ for the WezTerm status export), tmux 3.1+, required plugins.
- [Installation](docs/installation.md) — plugin managers and load-trigger variants.
- [Quickstart](docs/quickstart.md) — the first things to run after installing.

### Configuration

- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md) — `:Terminal`, and every key and autocommand the plugin binds.

### Navigation

- [Navigation](docs/navigation.md) — one key from Neovim windows into the neighbouring tmux or WezTerm pane.

### Backends

- [Backends](docs/backends.md) — native windows, tmux panes or WezTerm panes.
- [tmux](docs/tmux.md) — the tmux backend, the status in `status-right`, a `tmux.conf` to start from.

### Status export

- [Status export](docs/status.md) — mode, file, branch, diagnostics to tmux (pane options) and WezTerm (tab title, right status).

### Internals

- [Architecture](docs/architecture.md) — core, backends, how a call travels.
- [References](docs/references.md) — the WezTerm, iTerm2, tmux and Neovim documentation the status export and the pane commands rest on.

`:help terminal.nvim` has the short version in Vim help form (`doc/terminal.txt`).

## License

[MIT](LICENSE)
