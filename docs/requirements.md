# Requirements

- **Neovim 0.10+.** Terminals start with `jobstart({ term = true })` on 0.11+ and with
  `termopen()` on 0.10. The split layouts use `nvim_open_win({ split = ... })` (0.10).
- **[lib.nvim](https://github.com/StefanBartl/lib.nvim)** — required. It provides the
  keymap registry, the autocommand helpers, the `:Terminal` command composer, notifications
  and the config helpers.

Optional: a Nerd Font is not needed; nothing here draws icons.

`:checkhealth terminal` reports what it found.
