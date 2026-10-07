# Requirements

- **Neovim 0.11+.** Terminals start with `jobstart({ term = true })` (`termopen()` is deprecated),
  the split layouts use `nvim_open_win({ split = ... })`, the WezTerm status export uses
  `nvim_ui_send`.
- **[lib.nvim](https://github.com/StefanBartl/lib.nvim)** — required. It provides the
  keymap registry, the autocommand helpers, the `:Terminal` command composer, notifications
  and the config helpers.

Optional: a Nerd Font is not needed; nothing here draws icons.

`:checkhealth terminal` reports what it found.
