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
