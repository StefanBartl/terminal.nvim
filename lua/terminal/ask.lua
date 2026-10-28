---@module 'terminal.ask'
--- Programs in a terminal ask this Neovim: the terminal.nvim side of lib.nvim's `bin/nvim-ask`.
---
--- A git hook has no terminal to ask on under Git for Windows (no `/dev/tty` at all), so a hook in a
--- terminal of this plugin -- or in lazygit run there -- could only abort. lib.nvim ships the bridge:
--- `lib.nvim.terminal.ask` shows the question as a dialog in this Neovim, `bin/nvim-ask` is the
--- client a hook calls with `$NVIM`. This module hands the client to the terminals: every native
--- terminal gets `$NVIM_ASK`, the absolute path of `nvim-ask`, so a script runs
--- `bash "$NVIM_ASK" "Question?" "Yes" "No"` without searching for it.
---
--- Multiplexer panes (tmux, WezTerm) are not children of Neovim: they get neither `$NVIM` nor
--- `$NVIM_ASK` (those backends take no `env`), and `:checkhealth terminal` says so.

local M = {}

---The client script, when lib.nvim has the bridge and the script is on disk.
---@return string|nil path
---@return string|nil reason  when there is none
function M.script()
  local ok, ask = pcall(require, "lib.nvim.terminal.ask")
  if not ok or type(ask) ~= "table" or type(ask.script) ~= "function" then
    return nil, "lib.nvim has no lib.nvim.terminal.ask (update lib.nvim)"
  end
  local path = ask.script()
  if vim.fn.filereadable(path) ~= 1 then
    return nil, "not on disk: " .. path
  end
  return path, nil
end

---The variables a native terminal gets for the bridge (empty when it is off or not available).
---@param cfg { enable: boolean }|nil  the `ask` option
---@return table<string, string>
function M.env(cfg)
  if cfg and cfg.enable == false then
    return {}
  end
  local path = M.script()
  if not path then
    return {}
  end
  return { NVIM_ASK = path }
end

---Report on the bridge for `:checkhealth terminal`.
---@param health { ok: fun(msg: string), warn: fun(msg: string, advice?: string[]), info: fun(msg: string) }
---@param cfg { enable: boolean }|nil  the `ask` option
---@param backend string|nil  the backend in use
function M.check(health, cfg, backend)
  if cfg and cfg.enable == false then
    health.info("Ask bridge: off (`ask.enable = false`); terminals get no $NVIM_ASK")
    return
  end
  local path, reason = M.script()
  if not path then
    health.warn("Ask bridge: not available -- " .. reason, {
      "Hooks in terminals then cannot ask this Neovim (git hooks on Windows can only abort)",
    })
    return
  end
  health.ok("Ask bridge: terminals get $NVIM_ASK = " .. path)
  -- Soft: an older lib.nvim without cross.bash only loses this line of the report.
  local ok_bash, cross_bash = pcall(require, "lib.nvim.cross.bash")
  local bash = ok_bash and cross_bash.find() or nil
  if not ok_bash then
    health.info("Ask bridge: cannot look for bash (lib.nvim has no cross.bash)")
  elseif bash then
    health.ok("Ask bridge: bash for nvim-ask: " .. bash)
  else
    health.warn(
      "Ask bridge: no bash found, nvim-ask cannot run",
      { "Install Git for Windows (Git Bash)" }
    )
  end
  if vim.v.servername == "" then
    health.warn("Ask bridge: this Neovim has no RPC address, nothing can reach it")
  end
  if backend == "tmux" or backend == "wezterm" then
    health.info(
      ("Ask bridge: %s panes are not started by Neovim and get neither $NVIM nor $NVIM_ASK"):format(
        backend
      )
    )
  end
end

return M
