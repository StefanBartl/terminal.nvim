# Configuration

Every `setup()` option and its default (`lua/terminal/config/DEFAULTS.lua` is the source).
A key that is unknown, or has the wrong type, is reported once and ignored; a value outside
a closed set (`layout`, `backend`, `cwd`, `on_exit`, `float.title_pos`) falls back to its
default.

```lua
require("terminal").setup({
  -- Where terminals live: "auto" | "native" | "wezterm" | "tmux". "auto" and "native" are
  -- Neovim's own :terminal windows (also inside WezTerm/tmux); a multiplexer backend is chosen
  -- explicitly. Only native is implemented; the others fall back to it with a notice.
  backend = "auto",
  -- "float" | "split" | "vsplit" | "tab"
  layout = "float",

  float = {
    width = 0.8,            -- fraction of the editor (0 < x <= 1) or absolute columns (> 1)
    height = 0.8,           -- fraction or absolute lines
    border = "rounded",     -- anything nvim_open_win accepts; "none" removes it
    title = true,           -- show the terminal's name in a bordered float
    title_pos = "center",   -- "left" | "center" | "right"
    winblend = 0,           -- 0 opaque .. 100 transparent
    zindex = 50,
  },
  split = {
    size = 0.3,             -- fraction of the editor or absolute cells
  },

  -- Where a new terminal starts: "project" (git root of the buffer, else the cwd),
  -- "buffer" (directory of the buffer), "cwd".
  cwd = "project",
  shell = "",               -- "" = the 'shell' option; or a string / argv list
  env = {},                 -- extra environment variables, e.g. { FOO = "1" }

  start_insert = true,      -- enter terminal mode when a terminal gets focus through the API
  -- What happens when the job ends: "close" (remove window and buffer),
  -- "close_on_success" (only for exit code 0; failures stay readable), "keep".
  on_exit = "close",
  default_name = "main",    -- the terminal toggle()/open() use without a name or count

  window_options = {        -- applied to every terminal window on TermOpen
    enable = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    spell = false,
    cursorline = false,
  },

  kitty = {                 -- only inside Kitty: snug padding while editing, restored on exit
    enable = true,
    enter_padding = 0,
    enter_margin = 0,
    leave_padding = 20,
    leave_margin = 10,
  },

  auto_insert = {           -- enter Insert mode in every terminal buffer on these events
    enable = false,
    events = { "TermOpen" },
  },

  run = { name = "run" },   -- terminal used by `run` and `send` when no name is given

  -- Tell the terminal around Neovim what it is doing (see status.md).
  status = {
    enable = true,
    export = "auto",        -- "auto" | "wezterm" | { "wezterm" } | false
    debounce_ms = 80,
    max_bytes = 1024,       -- the dataset is shortened, then refused, above this
  },

  -- Keymaps are named actions. A string moves one, a list binds several keys, false drops
  -- it, preset = false binds nothing at all.
  keymaps = {
    preset = true,
    toggle = "<A-h>",                      -- normal and terminal mode; a count picks terminal N
    normal_mode = { "<Esc>", "<C-c>" },    -- terminal mode: leave to Terminal-Normal
    clear = false,                         -- terminal mode: type cls / clear (off: <C-l> clears in the shell)
    window_left = "<C-h>",                 -- terminal mode: window navigation
    window_down = "<C-j>",
    window_up = "<C-k>",
    window_right = false,                  -- off: <C-l> stays the shell's own clear-screen
  },

  commands = true,          -- register :Terminal
})
```

`setup()` may run again; options are replaced and existing terminals stay.
