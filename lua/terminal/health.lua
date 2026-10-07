---@module 'terminal.health'
--- `:checkhealth terminal` diagnostics. Read-only: never mutates state, never starts a job.

local M = {}

---@internal
---@param name string
---@return boolean
local function exe(name)
  return vim.fn.executable(name) == 1
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

  local required = {
    { "lib.nvim.notify", "notifications" },
    { "lib.nvim.bindings.keymap", "keymaps" },
    { "lib.nvim.bindings.autocmd", "autocommands" },
    { "lib.nvim.bindings.usercmd.composer", ":Terminal" },
    { "lib.lua.config", "configuration" },
  }
  for _, r in ipairs(required) do
    if pcall(require, r[1]) then
      health.ok(("lib.nvim provides %s (%s)"):format(r[1], r[2]))
    else
      health.error(
        ("%s not found -- %s will not work"):format(r[1], r[2]),
        { 'Install "StefanBartl/lib.nvim" (a hard dependency)' }
      )
    end
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
    local want = require("terminal.config").get("backend")
    local got = terminal.status().backend
    if want ~= "auto" and want ~= got then
      health.warn(
        ("backend '%s' was requested but '%s' is in use"):format(want, got),
        { 'Run `:messages` for the reason, or use `backend = "auto"`' }
      )
    end
  end

  M.check_wezterm(health, env)
  M.check_tmux(health, env)

  health.start("terminal.nvim: features")
  local ok_status, status = pcall(require, "terminal.status")
  if ok_status then
    local active = status.active()
    if #active > 0 then
      health.ok("Status export active: " .. table.concat(active, ", "))
    else
      health.info("Status export: no exporter active (not inside WezTerm/tmux, or disabled)")
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

  local shell = vim.o.shell
  if shell ~= "" and exe(shell) then
    health.ok(("'shell' is executable: %s"):format(shell))
  else
    health.warn(("'shell' is not executable: %s"):format(shell), {
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
    return vim.system(argv, { text = true, timeout = 2000 }):wait()
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  return vim.trim((res.stdout or "") .. (res.stderr or ""))
end

---@param health table
---@param env table<string, string|nil>
function M.check_wezterm(health, env)
  if env.WEZTERM_PANE == nil or env.WEZTERM_PANE == "" then
    health.info("WezTerm: not inside it")
    return
  end
  health.ok("WezTerm: $WEZTERM_PANE = " .. env.WEZTERM_PANE)
  if not exe("wezterm") then
    health.warn("`wezterm` is not on $PATH", {
      "The wezterm backend and the navigation hand-off need `wezterm cli`",
    })
    return
  end
  local version = run({ "wezterm", "--version" })
  local date = version and M.parse_wezterm_version(version)
  if date and date >= M.WEZTERM_TESTED then
    health.ok(("WezTerm %d (tested on %d)"):format(date, M.WEZTERM_TESTED))
  elseif date then
    health.warn(
      ("WezTerm %d is older than the tested %d"):format(date, M.WEZTERM_TESTED),
      { "Update WezTerm; user variables and `wezterm cli` behave differently in older releases" }
    )
  else
    health.warn("Could not read the WezTerm version")
  end
  if run({ "wezterm", "cli", "list", "--format", "json" }) then
    health.ok("`wezterm cli list` works (the mux is reachable)")
  else
    health.warn(
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

---@param health table
---@param env table<string, string|nil>
function M.check_tmux(health, env)
  if env.TMUX == nil or env.TMUX == "" then
    health.info("tmux: not inside it")
    return
  end
  health.ok("tmux: $TMUX is set")
  if not exe("tmux") then
    health.warn("`tmux` is not on $PATH")
    return
  end
  local value = run({ "tmux", "show", "-gv", "allow-passthrough" })
  if M.passthrough_enabled(value) then
    health.ok("tmux allow-passthrough = " .. value .. " (status reaches the outer terminal)")
  else
    health.warn("tmux allow-passthrough is " .. tostring(value or "unknown"), {
      "Add `set -g allow-passthrough on` to tmux.conf; without it the status export is silent",
    })
  end
end

return M
