---@meta
---@module 'terminal.@types'
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
---@field preset? boolean `false` binds nothing at all.
---@field toggle string|string[]|false
---@field normal_mode string|string[]|false
---@field clear string|string[]|false
---@field window_left string|string[]|false
---@field window_down string|string[]|false
---@field window_up string|string[]|false
---@field window_right string|string[]|false
---@field nav_left string|string[]|false
---@field nav_down string|string[]|false
---@field nav_up string|string[]|false
---@field nav_right string|string[]|false

---@class Terminal.StatusConfig
---@field enable boolean
---@field export string|string[]|boolean "auto", an exporter name, a list of names, or false
---@field debounce_ms integer
---@field max_bytes integer

---@class Terminal.NavigateConfig
---@field handoff string|string[]|boolean "auto", a name ("tmux", "wezterm"), a list, or false

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
---@field status Terminal.StatusConfig
---@field navigate Terminal.NavigateConfig
---@field keymaps Terminal.KeymapsConfig
---@field commands boolean

---@class Terminal.FloatOptions
---@field width? number Fraction of the editor (0 < x <= 1) or absolute columns (> 1).
---@field height? number Fraction of the editor (0 < x <= 1) or absolute lines (> 1).
---@field border? string|string[] Any value `nvim_open_win` accepts for `border`.
---@field title? boolean Show the terminal name in the window title.
---@field title_pos? "left"|"center"|"right"
---@field winblend? integer 0 (opaque) .. 100 (transparent).
---@field zindex? integer

---@class Terminal.SplitOptions
---@field size? number Fraction of the editor (0 < x <= 1) or absolute cells (> 1).

---@class Terminal.WindowOptionsOptions
---@field enable? boolean
---@field number? boolean
---@field relativenumber? boolean
---@field signcolumn? string
---@field spell? boolean
---@field cursorline? boolean

---@class Terminal.KittyOptions
---@field enable? boolean
---@field enter_padding? integer
---@field enter_margin? integer
---@field leave_padding? integer
---@field leave_margin? integer

---@class Terminal.AutoInsertOptions
---@field enable? boolean
---@field events? string[]

---@class Terminal.KeymapsOptions
---@field preset? boolean `false` binds nothing at all.
---@field toggle? string|string[]|false
---@field normal_mode? string|string[]|false
---@field clear? string|string[]|false
---@field window_left? string|string[]|false
---@field window_down? string|string[]|false
---@field window_up? string|string[]|false
---@field window_right? string|string[]|false
---@field nav_left? string|string[]|false
---@field nav_down? string|string[]|false
---@field nav_up? string|string[]|false
---@field nav_right? string|string[]|false

---@class Terminal.StatusOptions
---@field enable? boolean
---@field export? string|string[]|boolean "auto", an exporter name, a list of names, or false
---@field debounce_ms? integer
---@field max_bytes? integer

---@class Terminal.NavigateOptions
---@field handoff? string|string[]|boolean "auto", a name ("tmux", "wezterm"), a list, or false

---@class Terminal.RunOptions
---@field name? string Name of the terminal `run`/`send` use when none is given.

--- What a user passes to `setup()`: the shape of `Terminal.Config` with every key optional -- a key
--- that is left out keeps its default. (`Terminal.Config` is the resolved result.)
---@class Terminal.Options
---@field backend? Terminal.BackendName
---@field layout? Terminal.Layout
---@field float? Terminal.FloatOptions
---@field split? Terminal.SplitOptions
---@field cwd? Terminal.CwdMode
---@field shell? string|string[] `""` = the 'shell' option.
---@field env? table<string, string>
---@field start_insert? boolean
---@field on_exit? Terminal.ExitMode
---@field default_name? string Name of the terminal `toggle()` uses without a name or count.
---@field window_options? Terminal.WindowOptionsOptions
---@field kitty? Terminal.KittyOptions
---@field auto_insert? Terminal.AutoInsertOptions
---@field run? Terminal.RunOptions
---@field status? Terminal.StatusOptions
---@field navigate? Terminal.NavigateOptions
---@field keymaps? Terminal.KeymapsOptions
---@field commands? boolean

--- Who a call is about: the project root plus a name identify a terminal.
---@class Terminal.Target
---@field name? string Terminal name; wins over `count`
---@field count? integer `3` -> terminal "3"; 0/nil -> the default name
---@field layout? Terminal.Layout Overrides the configured layout for this call
---@field focus? boolean Take focus (default true)

--- Options of `send`.
---@class Terminal.SendOpts: Terminal.Target
---@field newline? boolean Append a line ending (execute the line)

--- Options of `run`.
---@class Terminal.RunOpts: Terminal.Target
---@field direct? boolean Start the command as the terminal's job itself (needs an argv list)
---@field on_exit? fun(code: integer) With `direct`: called once with the exit code
---@field cwd? string With `direct`: working directory of the job (default: the project's)
---@field title? string With `direct`: window title of a float (default: the terminal's name)
---@field float? table With `direct`: overrides of the `float` config for this window
---@field close? "always"|"success"|"never" With `direct`: remove the terminal when the job ends (default "never")
---@field start_insert? boolean With `direct`: enter terminal mode when it has focus (default true)
---@field env? table<string, string> With `direct`: extra environment for the job
---@field on_open? fun(handle: Terminal.Handle) With `direct`: called once the window and job exist (set buffer keymaps here)

--- The facade's mutable state.
---@class Terminal.State
---@field ready boolean
---@field registry Terminal.Registry
---@field backends table<string, Terminal.Backend>
---@field backend? Terminal.Backend
---@field env table<string, string|nil> The environment `setup()` looked at
---@field unavailable table<string, string> Multiplexer backends found unusable, with the reason
---@field deps Terminal.ContextDeps

--- The facade's internals, handed to the modules it delegates to (`pin`, `adopt`) so they need not
--- require the facade back.
---@class Terminal.Host
---@field fail fun(err: string|nil) Report a problem to the user
---@field resolve fun(target: Terminal.Target|nil): string|nil, string, string On failure `nil, err`; else name, cwd, root
---@field find_live fun(root: string, name: string): Terminal.Handle|nil
---@field backend_of fun(handle: Terminal.Handle): Terminal.Backend
---@field multiplexer fun(name: string): Terminal.Backend|nil, string|nil
---@field backend fun(): Terminal.Backend
---@field build_spec fun(name: string, cwd: string, root: string, extra?: Terminal.SpawnExtra): Terminal.SpawnSpec
---@field state Terminal.State

--- What a backend needs to start a terminal.
---@class Terminal.SpawnSpec
---@field name string
---@field root? string Project root; defaults to `cwd`.
---@field cmd? string|string[] nil = the configured shell.
---@field cwd string
---@field env? table<string, string>
---@field layout Terminal.Layout
---@field float? Terminal.FloatConfig
---@field split? Terminal.SplitConfig
---@field start_insert? boolean Enter terminal mode (native backend) once it is up.
---@field focus? boolean `false`: the user stays where they were (default: the terminal takes focus).
---@field on_exit? Terminal.ExitMode
---@field on_exit_cb? fun(code: integer) Called once with the job's exit code.
---@field title? string Window title of a float (default: `name`).

--- The extras `build_spec` takes on top of the configuration.
---@class Terminal.SpawnExtra
---@field layout? Terminal.Layout
---@field start_insert? boolean
---@field focus? boolean
---@field on_exit_cb? fun(code: integer)

--- Where a terminal is and whether it has focus, from one query to its backend.
---@class Terminal.Probe
---@field visible boolean
---@field focused boolean

--- What the facade already learned about a terminal (`toggle` probed it) and hands to `open`.
---@class Terminal.OpenKnown
---@field handle Terminal.Handle
---@field where? Terminal.Probe nil = the backend could not be asked

--- Name, directory and project root of one call, resolved once.
---@class Terminal.Resolved
---@field name string
---@field cwd string
---@field root string

--- How a backend is asked to close a terminal.
---@class Terminal.CloseOpts
---@field gone? boolean The caller has just seen that the pane does not exist (multiplexer backends skip their CLI)

--- Diagnostic counts per severity.
---@class Terminal.DiagCounts
---@field error? integer
---@field warn? integer
---@field info? integer
---@field hint? integer

--- Where a floating terminal window goes, as `nvim_open_win` takes it. `width` and `height` are
--- the content size: a border takes its two cells out of what the user configured.
---@class Terminal.FloatGeometry
---@field row integer
---@field col integer
---@field width integer
---@field height integer

--- One terminal as the registry and the backends see it.
---
--- A handle is a **live reference** into the registry: the facade (`terminal.list()`, `open()`,
--- `run{direct}`, `pin()`) returns the very table the backends keep up to date. Read it, never
--- write to it -- a caller that changes `exited`, `job` or `pane` corrupts the registry. (Config
--- getters are the opposite: they return copies.)
---@class Terminal.Handle
---@field id string Unique, `<root>::<name>`.
---@field name string
---@field root string Project root (or cwd) the terminal belongs to.
---@field backend string Backend name.
---@field bufnr? integer Native backend only.
---@field job? integer Native backend only: the terminal channel.
---@field pane? string Multiplexer backends only: the pane id.
---@field layout Terminal.Layout
---@field exited? boolean
---@field exit_code? integer
---@field disposed? boolean Set once the terminal was removed on purpose.
---@field cmd? string|string[] The command it was started with (nil: the shell). Used by `pin`.
---@field cwd? string The directory it was started in. Used by `pin`.

---@class Terminal.Backend
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field spawn fun(spec: Terminal.SpawnSpec): Terminal.Handle|nil, string|nil
---@field send fun(handle: Terminal.Handle, text: string): boolean, string|nil
---@field focus fun(handle: Terminal.Handle): boolean, string|nil
---@field list fun(): Terminal.Handle[]
---@field close fun(handle: Terminal.Handle, opts?: Terminal.CloseOpts): boolean, string|nil
---@field ping? fun(): boolean, string|nil Whether the multiplexer answers right now (`pin` asks before it ends a terminal)
---@field preflight? fun(spec: Terminal.SpawnSpec): boolean, string|nil What the backend refuses to start, without side effects (multiplexer backends: `env`)
---@field capture? fun(handle: Terminal.Handle): string|nil, string|nil Screen text (multiplexer panes only)
---@field visible? fun(handle: Terminal.Handle): boolean|nil nil = could not be asked (a multiplexer that did not answer); never "gone"
---@field focused? fun(handle: Terminal.Handle): boolean
---@field probe? fun(handle: Terminal.Handle): Terminal.Probe|nil, string|nil Both in one query; nil = could not be asked
---@field show? fun(handle: Terminal.Handle, spec: Terminal.SpawnSpec): boolean, string|nil
---@field hide? fun(handle: Terminal.Handle): boolean, string|nil

return {}
