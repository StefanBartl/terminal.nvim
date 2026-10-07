---@module 'terminal.backends.tmux'
--- The `tmux` backend: terminals are **panes of the tmux window** Neovim runs in, driven through
--- the `tmux` CLI. Chosen explicitly (`backend = "tmux"`); `auto` keeps terminals native.
---
--- Mapping (like the wezterm backend, see docs/backends.md):
---   * `split` / `float` -> a pane below / to the right; `vsplit` -> right; `tab` -> a new window.
---   * `send` types the text with `send-keys -l -- <text>`: literal, and after `--`, so no word of
---     it can be read as a key name or an option.
---   * `hide` returns focus to Neovim's own pane; there is no `show` (a pane that is gone is
---     replaced).
---   * `env` is refused; the exit of the command is not reported.
---
--- The runner is injected (`new(registry, runner, own_pane, opts)`); `opts.socket` selects a
--- tmux server (`-L name`), which is how the specs run against a private server.

local registry_mod = require("terminal.core.registry")

local M = {}

---@class Terminal.TmuxRun
---@field code integer
---@field stdout string
---@field stderr string

---@alias Terminal.TmuxRunner fun(argv: string[], opts?: { timeout?: integer }): Terminal.TmuxRun

--- The real runner: `vim.system` with a timeout.
---@type Terminal.TmuxRunner
function M.default_runner(argv, opts)
  opts = opts or {}
  local ok, res = pcall(function()
    return vim.system(argv, { text = true, timeout = opts.timeout or 3000 }):wait()
  end)
  if not ok then
    return { code = 127, stdout = "", stderr = tostring(res) }
  end
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

--- Whether `tmux` can be used from here.
---@param env table<string, string|nil>
---@return boolean ok
---@return string|nil reason
function M.available(env)
  if env.TMUX == nil or env.TMUX == "" then
    return false, "not running inside tmux ($TMUX is not set)"
  end
  if env.TMUX_PANE == nil or env.TMUX_PANE == "" then
    return false, "$TMUX_PANE is not set"
  end
  if vim.fn.executable("tmux") ~= 1 then
    return false, "`tmux` is not on $PATH"
  end
  return true, nil
end

--- Create the tmux backend.
---@param registry Terminal.Registry
---@param runner? Terminal.TmuxRunner
---@param own_pane? string Pane Neovim runs in (default `$TMUX_PANE`)
---@param opts? { socket?: string }
---@return Terminal.Backend
function M.new(registry, runner, own_pane, opts)
  runner = runner or M.default_runner
  own_pane = own_pane or vim.env.TMUX_PANE or ""
  opts = opts or {}

  ---@type Terminal.Backend
  local backend = {
    name = "tmux",
    caps = { hide = true, show = false, status = true },
  }

  ---@internal
  ---@param args string[] Arguments after `tmux`
  ---@return Terminal.TmuxRun|nil
  ---@return string|nil err
  local function tmux(args)
    local argv = { "tmux" }
    if opts.socket then
      vim.list_extend(argv, { "-L", opts.socket })
    end
    vim.list_extend(argv, args)
    local res = runner(argv)
    if res.code ~= 0 then
      local why = vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
      return nil,
        ("tmux %s failed (%d): %s"):format(args[1], res.code, why ~= "" and why or "no output")
    end
    return res, nil
  end

  ---@internal
  --- Every pane tmux knows: id -> { active = pane active in its window, window_active }.
  ---@return table<string, { active: boolean, window_active: boolean }>|nil
  ---@return string|nil err
  local function panes()
    local res, err = tmux({
      "list-panes",
      "-a",
      "-F",
      "#{pane_id} #{pane_active} #{window_active}",
    })
    if not res then
      return nil, err
    end
    local by_id = {}
    for line in res.stdout:gmatch("[^\r\n]+") do
      local id, pane_active, window_active = line:match("^(%%%d+) (%d) (%d)$")
      if id then
        by_id[id] = { active = pane_active == "1", window_active = window_active == "1" }
      end
    end
    return by_id, nil
  end

  function backend.available(env)
    return M.available(env)
  end

  ---@param spec Terminal.SpawnSpec
  ---@return Terminal.Handle|nil
  ---@return string|nil
  function backend.spawn(spec)
    if spec.env and next(spec.env) ~= nil then
      return nil, "the tmux backend cannot set environment variables for a pane"
    end
    local args
    local keep_focus = spec.start_insert == false
    if spec.layout == "tab" then
      args = { "new-window", "-P", "-F", "#{pane_id}" }
    else
      args = { "split-window", "-P", "-F", "#{pane_id}", "-t", own_pane }
      args[#args + 1] = spec.layout == "split" and "-v" or "-h"
      local size = (spec.split or {}).size
      if type(size) == "number" and size > 0 and size <= 1 then
        vim.list_extend(args, { "-l", ("%d%%"):format(math.floor(size * 100)) })
      end
    end
    if keep_focus then
      args[#args + 1] = "-d"
    end
    if spec.cwd and spec.cwd ~= "" then
      vim.list_extend(args, { "-c", spec.cwd })
    end
    local cmd = spec.cmd
    if type(cmd) == "string" and cmd ~= "" then
      cmd = { cmd }
    end
    if type(cmd) == "table" and #cmd > 0 then
      vim.list_extend(args, cmd)
    end

    local res, err = tmux(args)
    if not res then
      return nil, err
    end
    local pane = vim.trim(res.stdout)
    if not pane:find("^%%%d+$") then
      return nil, ("unexpected output from tmux %s: %q"):format(args[1], res.stdout)
    end

    local root = spec.root or spec.cwd
    ---@type Terminal.Handle
    local handle = {
      id = registry_mod.make_id(root, spec.name),
      name = spec.name,
      root = root,
      backend = "tmux",
      pane = pane,
      layout = spec.layout,
    }
    registry:add(handle)
    return handle, nil
  end

  ---@param handle Terminal.Handle
  ---@param text string
  ---@return boolean
  ---@return string|nil
  function backend.send(handle, text)
    if text:find("%z") then
      return false, "text contains a NUL byte"
    end
    local res, err = tmux({ "send-keys", "-t", handle.pane, "-l", "--", text })
    if not res then
      return false, err
    end
    return true, nil
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  function backend.visible(handle)
    local all = panes()
    return all ~= nil and all[handle.pane] ~= nil
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  function backend.focused(handle)
    local all = panes()
    local mine = all and all[handle.pane]
    return mine ~= nil and mine.active and mine.window_active
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.focus(handle)
    local ok, err = tmux({ "select-window", "-t", handle.pane })
    if not ok then
      return false, err
    end
    local res, perr = tmux({ "select-pane", "-t", handle.pane })
    return res ~= nil, perr
  end

  --- The pane's visible text (`capture-pane -p`, plain text without escape sequences).
  ---@param handle Terminal.Handle
  ---@return string|nil
  ---@return string|nil
  function backend.capture(handle)
    local res, err = tmux({ "capture-pane", "-p", "-t", handle.pane })
    if not res then
      return nil, err
    end
    return res.stdout, nil
  end

  --- A pane cannot be hidden; "hide" gives focus back to Neovim's own pane.
  ---@param _handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.hide(_handle)
    if own_pane == "" then
      return false, "Neovim's own pane is unknown"
    end
    local ok, err = tmux({ "select-window", "-t", own_pane })
    if not ok then
      return false, err
    end
    local res, perr = tmux({ "select-pane", "-t", own_pane })
    return res ~= nil, perr
  end

  ---@return Terminal.Handle[]
  function backend.list()
    local all = panes()
    local out = {}
    for _, h in ipairs(registry:list()) do
      if h.backend == "tmux" then
        if all == nil or all[h.pane] ~= nil then
          out[#out + 1] = h
        else
          registry:remove(h.id)
        end
      end
    end
    return out
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.close(handle)
    if registry:get(handle.id) == handle then
      registry:remove(handle.id)
    end
    tmux({ "kill-pane", "-t", handle.pane })
    return true, nil
  end

  return backend
end

return M
