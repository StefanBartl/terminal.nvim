---@meta
--- Shared types of terminal.nvim.

---@alias Terminal.Layout "float"|"split"|"vsplit"|"tab"
---@alias Terminal.BackendName "auto"|"native"|"wezterm"|"tmux"
---@alias Terminal.CwdMode "project"|"buffer"|"cwd"
---@alias Terminal.ExitMode "close"|"close_on_success"|"keep"

---@class Terminal.FloatConfig
---@field width number Fraction of the editor (0 < x <= 1) or absolute columns (> 1).
---@field height number Fraction of the editor (0 < x <= 1) or absolute lines (> 1).
---@field border string|string[] Any value `nvim_open_win` accepts for `border`.
---@field title boolean Show the terminal name in the window title.
---@field title_pos "left"|"center"|"right"
---@field winblend integer 0 (opaque) .. 100 (transparent).
---@field zindex integer

---@class Terminal.SplitConfig
---@field size number Fraction of the editor (0 < x <= 1) or absolute cells (> 1).

---@class Terminal.WindowOptionsConfig
---@field enable boolean
---@field number boolean
---@field relativenumber boolean
---@field signcolumn string
---@field spell boolean
---@field cursorline boolean

---@class Terminal.KittyConfig
---@field enable boolean
---@field enter_padding integer
---@field enter_margin integer
---@field leave_padding integer
---@field leave_margin integer

---@class Terminal.AutoInsertConfig
---@field enable boolean
---@field events string[]

---@class Terminal.KeymapsConfig
---@field preset boolean|nil `false` binds nothing at all.
---@field toggle string|string[]|false
---@field normal_mode string|string[]|false
---@field clear string|string[]|false
---@field window_left string|string[]|false
---@field window_down string|string[]|false
---@field window_up string|string[]|false
---@field window_right string|string[]|false

---@class Terminal.RunConfig
---@field name string Name of the terminal `run`/`send` use when none is given.

---@class Terminal.Config
---@field backend Terminal.BackendName
---@field layout Terminal.Layout
---@field float Terminal.FloatConfig
---@field split Terminal.SplitConfig
---@field cwd Terminal.CwdMode
---@field shell string|string[] `""` = the 'shell' option.
---@field env table<string, string>
---@field start_insert boolean
---@field on_exit Terminal.ExitMode
---@field default_name string Name of the terminal `toggle()` uses without a name or count.
---@field window_options Terminal.WindowOptionsConfig
---@field kitty Terminal.KittyConfig
---@field auto_insert Terminal.AutoInsertConfig
---@field run Terminal.RunConfig
---@field keymaps Terminal.KeymapsConfig
---@field commands boolean

--- What a backend needs to start a terminal.
---@class Terminal.SpawnSpec
---@field name string
---@field root string|nil Project root; defaults to `cwd`.
---@field cmd string|string[]|nil nil = the configured shell.
---@field cwd string
---@field env table<string, string>|nil
---@field layout Terminal.Layout
---@field float Terminal.FloatConfig|nil
---@field split Terminal.SplitConfig|nil
---@field start_insert boolean|nil
---@field on_exit Terminal.ExitMode|nil
---@field on_exit_cb fun(code: integer)|nil Called once with the job's exit code.

--- One terminal as the registry and the backends see it.
---@class Terminal.Handle
---@field id string Unique, `<root>::<name>`.
---@field name string
---@field root string Project root (or cwd) the terminal belongs to.
---@field backend string Backend name.
---@field bufnr integer|nil Native backend only.
---@field job integer|nil Native backend only: the terminal channel.
---@field pane string|nil Multiplexer backends only: the pane id.
---@field layout Terminal.Layout
---@field exited boolean|nil
---@field exit_code integer|nil
---@field disposed boolean|nil Set once the terminal was removed on purpose.

---@class Terminal.Backend
---@field name string
---@field caps table<string, boolean> Optional abilities: `hide`, `show`, `status`.
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field spawn fun(spec: Terminal.SpawnSpec): Terminal.Handle|nil, string|nil
---@field send fun(handle: Terminal.Handle, text: string): boolean, string|nil
---@field focus fun(handle: Terminal.Handle): boolean, string|nil
---@field list fun(): Terminal.Handle[]
---@field close fun(handle: Terminal.Handle): boolean, string|nil
---@field set_status? fun(status: table): boolean, string|nil
---@field visible? fun(handle: Terminal.Handle): boolean
---@field focused? fun(handle: Terminal.Handle): boolean
---@field show? fun(handle: Terminal.Handle, spec: Terminal.SpawnSpec): boolean, string|nil
---@field hide? fun(handle: Terminal.Handle): boolean, string|nil
