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
---@field cheatsheet string|string[]|false

---@class Terminal.CheatsheetConfig
---@field shell string Force a sheet by shell name; `""` detects it.
---@field dir string Folder of `<shell>.md` files, searched before the built-in sheets.
---@field shells table<string, string> Sheet file by shell name.

---@class Terminal.StatusConfig
---@field enable boolean
---@field export string|string[]|boolean "auto", an exporter name, a list of names, or false
---@field debounce_ms integer
---@field max_bytes integer
---@field timeout_ms integer How long the tmux exporter waits for tmux (ms)

---@class Terminal.NavigateConfig
---@field handoff string|string[]|boolean "auto", a name ("tmux", "wezterm"), a list, or false
---@field timeout_ms integer How long the hand-off command may run (ms)

---@class Terminal.SessionsConfig
---@field enable boolean Save and reopen the terminals with a sessions.nvim session
---@field commands "ask"|"run"|"never" What happens to a saved command: ask once, start it, or open a plain shell

---@class Terminal.MultiplexerConfig
---@field timeout_ms integer How long a tmux / `wezterm cli` call may take before it counts as hung (ms)

---@class Terminal.AdoptConfig
---@field refresh_ms integer Pause between two refreshes of an adopt view (ms)

---@class Terminal.PinConfig
---@field layout Terminal.Layout Layout of the new pane when `--layout` is not given

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
---@field multiplexer Terminal.MultiplexerConfig
---@field adopt Terminal.AdoptConfig
---@field pin Terminal.PinConfig
---@field sessions Terminal.SessionsConfig
---@field cheatsheet Terminal.CheatsheetConfig
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
---@field cheatsheet? string|string[]|false

---@class Terminal.CheatsheetOptions
---@field shell? string Force a sheet by shell name; `""` detects it.
---@field dir? string Folder of `<shell>.md` files, searched before the built-in sheets.
---@field shells? table<string, string> Sheet file by shell name.

---@class Terminal.StatusOptions
---@field enable? boolean
---@field export? string|string[]|boolean "auto", an exporter name, a list of names, or false
---@field debounce_ms? integer
---@field max_bytes? integer
---@field timeout_ms? integer

---@class Terminal.NavigateOptions
---@field handoff? string|string[]|boolean "auto", a name ("tmux", "wezterm"), a list, or false
---@field timeout_ms? integer

---@class Terminal.SessionsOptions
---@field enable? boolean
---@field commands? "ask"|"run"|"never"

---@class Terminal.MultiplexerOptions
---@field timeout_ms? integer

---@class Terminal.AdoptOptions
---@field refresh_ms? integer

---@class Terminal.PinOptions
---@field layout? Terminal.Layout

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
---@field multiplexer? Terminal.MultiplexerOptions
---@field adopt? Terminal.AdoptOptions
---@field pin? Terminal.PinOptions
---@field sessions? Terminal.SessionsOptions
---@field cheatsheet? Terminal.CheatsheetOptions
---@field keymaps? Terminal.KeymapsOptions
---@field commands? boolean

--- Who a call is about: the project root plus a name identify a terminal.
---@class Terminal.Target
---@field name? string Terminal name; wins over `count`
---@field count? number `3` -> terminal "3" (fractions are cut off); 0/nil -> the default name (`send` and `run`: the `run.name` terminal)
---@field layout? Terminal.Layout Overrides the configured layout for this call
---@field focus? boolean Take focus (default true)

--- What `summary` reports for a statusline.
---@class Terminal.Summary
---@field count integer Live terminals of this project (a native one whose job ended is not counted)
---@field visible integer Of those, how many are shown in a window right now (native terminals)
---@field current? string The name of the terminal whose buffer is the current one

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
---@field env? table<string, string> With `direct`: extra environment for the job (native backend only: tmux and WezTerm refuse it)
---@field session? boolean With `direct`: `false` keeps the terminal out of a saved session (sessions integration), so it is never reopened without `env` and `on_open` (default true)
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
---@field with_rerun fun(spec: Terminal.SpawnSpec, rerun?: Terminal.RunRecord) Put a `run` with `direct`'s `close`, `title` and `float` (and the record) on a spec
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
---@field session? boolean `false`: the terminal is left out of a saved session (native backend, `Terminal.Handle.session`).
---@field rerun? Terminal.RunRecord What `run` with `direct` was given, kept on the handle (native backend, `Terminal.Handle.rerun`).

--- The options of a `run` with `direct` that a saved session repeats when it starts the command
--- again (`env` and the callbacks are not: a sidecar holds no secrets and no code).
---@class Terminal.RunRecord
---@field close? "always"|"success"|"never"
---@field title? string
---@field float? table Overrides of the `float` config

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
---@field session? boolean `false`: started by `run` with `session = false`, left out of a saved session (native backend only).
---@field rerun? Terminal.RunRecord Started by `run` with `direct`: its `close`, `title` and `float`, which a saved session repeats (native backend only).

---@class Terminal.Backend
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field spawn fun(spec: Terminal.SpawnSpec): Terminal.Handle|nil, string|nil
---@field send fun(handle: Terminal.Handle, text: string): boolean, string|nil
---@field focus fun(handle: Terminal.Handle): boolean, string|nil
---@field list fun(): Terminal.Handle[]
---@field close fun(handle: Terminal.Handle, opts?: Terminal.CloseOpts): boolean, string|nil
---@field ping? fun(): boolean, string|nil Whether the multiplexer answers right now (`pin` asks before it ends a terminal)
---@field preflight? fun(spec: Terminal.SpawnSpec): boolean, string|nil What the backend refuses to start, without side effects (multiplexer backends: `env`, an unknown layout); `pin` and `run` with `direct` ask it before they close the terminal they replace
---@field capture? fun(handle: Terminal.Handle): string|nil, string|nil Screen text (multiplexer panes only)
---@field capture_async? fun(handle: Terminal.Handle, on_done: fun(text: string|nil, err: string|nil)) `capture` without blocking; `on_done` runs on the main loop
---@field visible? fun(handle: Terminal.Handle): boolean|nil nil = could not be asked (a multiplexer that did not answer); never "gone"
---@field focused? fun(handle: Terminal.Handle): boolean
---@field probe? fun(handle: Terminal.Handle): Terminal.Probe|nil, string|nil Both in one query; nil = could not be asked
---@field show? fun(handle: Terminal.Handle, spec: Terminal.SpawnSpec): boolean, string|nil
---@field hide? fun(handle: Terminal.Handle): boolean, string|nil

-- ---------------------------------------------------------------------------
-- pin.lua

---@class Terminal.PinOpts
---@field backend? "tmux"|"wezterm" Where to start it (default: tmux inside tmux, else wezterm)
---@field layout? Terminal.Layout Default `pin.layout` ("vsplit")

---@class Terminal.PinPlan
---@field name string
---@field cwd string
---@field root string
---@field handle Terminal.Handle The native terminal that is replaced
---@field backend Terminal.Backend The multiplexer that takes over
---@field spec Terminal.SpawnSpec What the pane is started with
---@field restore Terminal.SpawnSpec What starts the native terminal again if the pane cannot be

return {}
