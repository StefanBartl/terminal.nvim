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
:Terminal run --direct make test       run a command as the job, get its exit code
:Terminal send selection --exec        type the selection into the terminal and press Enter
```

The terminal layer is a **backend** behind one API. Today the `native` backend (Neovim's
own `:terminal`) and a `wezterm` backend (terminals as WezTerm panes) exist; the nvim status
also goes to WezTerm (tab title, right status). A tmux backend and navigation across pane
borders are the next steps.

## Table of contents

- [Documentation](#documentation)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md) — what is where, and which question each page
answers.

**The Basics**

- [Requirements](docs/requirements.md) — Neovim version and required plugins.
- [Installation](docs/installation.md) — plugin managers and load-trigger variants.
- [Quickstart](docs/quickstart.md) — the first things to run after installing.

**Configuration**

- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md)

**Navigation**

- [Navigation](docs/navigation.md) — one key from Neovim windows into the neighbouring pane.

**Backends**

- [Backends](docs/backends.md) — native windows or WezTerm panes.

**Status export**

- [Status export](docs/status.md) — mode, file, branch, diagnostics to WezTerm.

**Internals**

- [Architecture](docs/architecture.md) — core, backends, how a call travels.

`:help terminal.nvim` has the same in Vim help form (`doc/terminal.txt`).

## License

[MIT](LICENSE)
