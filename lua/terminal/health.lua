---@module 'terminal.health'
--- `:checkhealth terminal` diagnostics. Read-only: never mutates state, never starts a job.
---
--- A `warn` is reserved for something the user can act on *and* that the configuration relies on:
--- the multiplexer backends and hand-offs are alternatives (native is always there), so the
--- absence of one is a `warn` only when the options name it (or `"auto"` would pick it); otherwise
--- it is `info`.
---@see terminal.config

local M = {}

---@internal
---@param name string
---@return boolean
local function exe(name)
  return vim.fn.executable(name) == 1
end

--- How long a health check waits for one multiplexer command. Long enough for a busy `wezterm
--- cli`, short enough that `:checkhealth` does not hang on a stuck one.
local CLI_TIMEOUT_MS = 2000

---@internal
--- The program of a 'shell' value: Neovim quotes a path with spaces itself (`"C:\Program
--- Files\Git\bin\bash.exe" -l`), and a value can carry arguments.
---@param shell string
---@return string|nil program Whatever `executable()` finds first, nil when nothing runs
local function shell_program(shell)
  if shell == "" then
    return nil
  end
  local candidates = {
    shell,
    shell:match('^%s*"([^"]+)"'),
    shell:match("^%s*(%S+)"),
  }
  for _, candidate in ipairs(candidates) do
    if candidate and exe(candidate) then
      return candidate
    end
  end
  return nil
end

---@internal
--- Does the option (`"auto"`, a name, a list of names, false) pick `name`?
---@param option string|string[]|boolean|nil
---@param name string
---@return boolean explicit The option names `name`
---@return boolean auto The option is `"auto"`
local function picks(option, name)
  if option == "auto" then
    return false, true
  elseif option == name then
    return true, false
  elseif type(option) == "table" and vim.list_contains(option, name) then
    return true, false
  end
  return false, false
end

---@internal
--- What the configuration relies on, per multiplexer: `cli` (the backend or the navigation
--- hand-off needs its command line) and `export` (the status export is on and would use it).
---@param cfg Terminal.Config
---@param name "wezterm"|"tmux"
---@param env table<string, string|nil>
---@return { cli: boolean, export: boolean }
local function reliance(cfg, name, env)
  local explicit, auto = picks(cfg.navigate.handoff, name)
  -- "auto" asks the innermost multiplexer only: inside tmux inside WezTerm that is tmux.
  local innermost = name == "tmux" or env.TMUX == nil or env.TMUX == ""
  local export_explicit, export_auto = picks(cfg.status.export, name)
  return {
    cli = cfg.backend == name or explicit or (auto and innermost),
    export = cfg.status.enable == true and (export_explicit or export_auto),
  }
end

---@internal
--- `warn` when the configuration relies on what is missing, else `info`.
---@param health table
---@param relied boolean
---@param msg string
---@param advice? string[]
local function report(health, relied, msg, advice)
  if relied then
    health.warn(msg, advice)
  else
    health.info(msg .. " (not needed by the current options)")
  end
end

--- Run the health check.
---@return nil
function M.check()
  local health = vim.health
  health.start("terminal.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("terminal.nvim needs Neovim 0.11+", { "Upgrade Neovim to 0.11 or newer" })
  end

  -- Every lib.nvim module the plugin requires without a fallback: an outdated lib.nvim that lacks
  -- one must not pass the check.
  local required = {
    { "lib.nvim.notify", "notifications" },
    { "lib.nvim.bindings.keymap", "keymaps" },
    { "lib.nvim.bindings.autocmd", "autocommands" },
    { "lib.nvim.bindings.usercmd.composer", ":Terminal" },
    { "lib.lua.config", "configuration" },
    { "lib.nvim.fs.normkey", "project paths" },
    { "lib.nvim.terminal", "kitty detection" },
    { "lib.nvim.system.env", "keymap environment" },
    { "lib.nvim.debounce", "status debounce" },
  }
  for _, r in ipairs(required) do
    if pcall(require, r[1]) then
      health.ok(("lib.nvim provides %s (%s)"):format(r[1], r[2]))
    else
      health.error(
        ("%s not found -- %s will not work"):format(r[1], r[2]),
        { 'Install "StefanBartl/lib.nvim" (a hard dependency) or update it' }
      )
    end
  end

  local config = require("terminal.config")
  for _, problem in ipairs(config.problems) do
    health.warn("config: " .. problem, { "Fix the option in your `setup()` call" })
  end

  local ok, terminal = pcall(require, "terminal")
  if ok then
    local status = terminal.status()
    if status.ready then
      health.ok(
        ("setup() ran; backend '%s', %d terminal(s) open"):format(status.backend, status.terminals)
      )
    else
      health.info("setup() has not run yet (it runs on first use)")
    end
  end

  health.start("terminal.nvim: environment")
  local backends = require("terminal.backends")
  local env = { TMUX = vim.env.TMUX, WEZTERM_PANE = vim.env.WEZTERM_PANE }
  health.info("Detected: " .. table.concat(backends.detect(env), ", "))

  if ok and terminal.status().ready then
    local want = config.get("backend")
    local got = terminal.status().backend
    if want ~= "auto" and want ~= got then
      health.warn(
        ("backend '%s' was requested but '%s' is in use"):format(want, got),
        { 'Run `:messages` for the reason, or use `backend = "auto"`' }
      )
    end
  end

  local cfg = config.get_all()
  M.check_wezterm(health, env, cfg)
  M.check_tmux(health, env, cfg)

  health.start("terminal.nvim: features")
  local ok_status, status = pcall(require, "terminal.status")
  if ok_status then
    local active = status.active()
    if #active > 0 then
      health.ok("Status export active: " .. table.concat(active, ", "))
    else
      health.info(
        "Status export: no exporter active (not inside WezTerm/tmux, disabled, "
          .. "or inside WezTerm on a Neovim older than 0.12)"
      )
    end
  end
  local ok_nav, nav = pcall(require, "terminal.navigate")
  if ok_nav then
    local active = nav.active()
    if #active > 0 then
      health.ok("Navigation hand-off at the edge: " .. table.concat(active, ", "))
    else
      health.info("Navigation hand-off: none (not inside a multiplexer, or disabled)")
    end
  end
  if vim.v.servername ~= "" then
    health.ok("RPC address for control from outside: " .. vim.v.servername)
  else
    health.warn(
      "This Neovim has no RPC address",
      { "Start it with `--listen` or leave the default" }
    )
  end

  -- The shell the terminals will run: the plugin's own `shell` setting, else Neovim's.
  local own = config.get("shell")
  local shell = vim.o.shell
  if type(own) == "table" and own[1] then
    shell = own[1]
  elseif type(own) == "string" and own ~= "" then
    shell = own
  end
  local program = shell_program(shell)
  if program then
    health.ok(("shell is executable: %s"):format(program))
  else
    health.warn(("shell is not executable: %s"):format(shell), {
      "Set the 'shell' option or terminal.nvim's `shell` setting to an installed shell",
    })
  end
end

--- WezTerm release date (`YYYYMMDD`) from `wezterm --version`; nil when unreadable.
---@param text string
---@return integer|nil
function M.parse_wezterm_version(text)
  local date = text:match("wezterm%s+(%d%d%d%d%d%d%d%d)")
  return date and tonumber(date) or nil
end

--- The first WezTerm release these features were tested on (2024-02-03).
M.WEZTERM_TESTED = 20240203

---@internal
---@param argv string[]
---@return string|nil out
local function run(argv)
  local ok, res = pcall(function()
    return vim.system(argv, { text = true, timeout = CLI_TIMEOUT_MS }):wait()
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  return vim.trim((res.stdout or "") .. (res.stderr or ""))
end

--- Report on WezTerm. `cfg` is the effective configuration (default: the current one); it
--- decides whether a missing piece is a `warn` or only an `info`.
---@param health table
---@param env table<string, string|nil>
---@param cfg? Terminal.Config
function M.check_wezterm(health, env, cfg)
  if env.WEZTERM_PANE == nil or env.WEZTERM_PANE == "" then
    health.info("WezTerm: not inside it")
    return
  end
  health.ok("WezTerm: $WEZTERM_PANE = " .. env.WEZTERM_PANE)
  local relied = reliance(cfg or require("terminal.config").get_all(), "wezterm", env)
  if type(vim.api.nvim_ui_send) ~= "function" then
    report(
      health,
      relied.export,
      "Neovim has no `nvim_ui_send` (needs 0.12+): the WezTerm status export is off",
      { "Upgrade Neovim to 0.12 or newer to get the tab title and right status" }
    )
  end
  if not exe("wezterm") then
    report(health, relied.cli, "`wezterm` is not on $PATH", {
      "The wezterm backend and the navigation hand-off need `wezterm cli`",
    })
    return
  end
  local version = run({ "wezterm", "--version" })
  local date = version and M.parse_wezterm_version(version)
  if date and date >= M.WEZTERM_TESTED then
    health.ok(("WezTerm %d (tested on %d)"):format(date, M.WEZTERM_TESTED))
  elseif date then
    report(
      health,
      relied.cli or relied.export,
      ("WezTerm %d is older than the tested %d"):format(date, M.WEZTERM_TESTED),
      { "Update WezTerm; user variables and `wezterm cli` behave differently in older releases" }
    )
  else
    health.info("Could not read the WezTerm version")
  end
  if run({ "wezterm", "cli", "list", "--format", "json" }) then
    health.ok("`wezterm cli list` works (the mux is reachable)")
  else
    report(
      health,
      relied.cli,
      "`wezterm cli list` failed",
      { "Is the WezTerm GUI running and WEZTERM_UNIX_SOCKET set?" }
    )
  end
end

--- `allow-passthrough` is usable when it is `on` or `all`.
---@param value string|nil
---@return boolean
function M.passthrough_enabled(value)
  return value == "on" or value == "all"
end

--- Report on tmux. `cfg` is the effective configuration (default: the current one); it decides
--- whether a missing piece is a `warn` or only an `info`.
---@param health table
---@param env table<string, string|nil>
---@param cfg? Terminal.Config
function M.check_tmux(health, env, cfg)
  if env.TMUX == nil or env.TMUX == "" then
    health.info("tmux: not inside it")
    return
  end
  health.ok("tmux: $TMUX is set")
  cfg = cfg or require("terminal.config").get_all()
  local relied = reliance(cfg, "tmux", env)
  if not exe("tmux") then
    report(health, relied.cli or relied.export, "`tmux` is not on $PATH")
    return
  end
  local banner = run({ "tmux", "-V" })
  local major, minor = require("terminal.backends.tmux").parse_version(banner or "")
  if major then
    health.ok(("tmux %d.%d"):format(major, minor))
    if not require("terminal.backends.tmux").has_percent_size(major, minor) then
      health.info("tmux is older than 3.1: pane sizes are passed as `-p <percent>`")
    end
  end
  local value = run({ "tmux", "show", "-gv", "allow-passthrough" })
  if M.passthrough_enabled(value) then
    health.ok("tmux allow-passthrough = " .. value .. " (status reaches the outer terminal)")
  else
    -- Passthrough carries the WezTerm status export out of tmux; the tmux exporter itself and
    -- everything else work without it.
    local wezterm = reliance(cfg, "wezterm", env)
    local needed = wezterm.export
      and env.WEZTERM_PANE ~= nil
      and env.WEZTERM_PANE ~= ""
      and type(vim.api.nvim_ui_send) == "function"
    report(health, needed, "tmux allow-passthrough is " .. tostring(value or "unknown"), {
      "Add `set -g allow-passthrough on` to tmux.conf; without it the WezTerm status export is silent",
    })
  end
end

return M
