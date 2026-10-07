---@module 'terminal.backends.wezterm'
--- The `wezterm` backend: terminals are **panes of the WezTerm window** Neovim runs in, driven
--- through `wezterm cli`. Chosen explicitly (`backend = "wezterm"`); `auto` keeps terminals native.
---
--- What maps and what does not:
---   * `split` / `float` -> a pane below / to the right (WezTerm has no floats); `vsplit` -> right;
---     `tab` -> a new tab.
---   * `send` types the text into the pane (`send-text --no-paste`, text on stdin, so no word of it
---     can be read as an option).
---   * `hide` returns focus to Neovim's own pane (a pane cannot be hidden); `show` does not exist --
---     a pane that is gone is replaced by a new one.
---   * `env` is not supported (`wezterm cli` has no per-command environment) and is refused.
---   * The exit of the command is not reported (`on_exit_cb` is never called); `list()` notices a
---     pane that no longer exists.
---
--- Every call is a short blocking `wezterm cli` process with a timeout. The runner is injected
--- (`new(registry, runner)`), so the specs run against a fake `wezterm` instead of a real one.

local registry_mod = require("terminal.core.registry")

local M = {}

---@class Terminal.WezTermRun
---@field code integer
---@field stdout string
---@field stderr string

---@alias Terminal.WezTermRunner fun(argv: string[], opts?: { stdin?: string, timeout?: integer }): Terminal.WezTermRun

--- The real runner: `vim.system`, with a timeout.
---@type Terminal.WezTermRunner
function M.default_runner(argv, opts)
  opts = opts or {}
  local ok, res = pcall(function()
    return vim
      .system(argv, { text = true, stdin = opts.stdin, timeout = opts.timeout or 3000 })
      :wait()
  end)
  if not ok then
    return { code = 127, stdout = "", stderr = tostring(res) }
  end
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

--- Whether `wezterm cli` can be used from here.
---@param env table<string, string|nil>
---@return boolean ok
---@return string|nil reason
function M.available(env)
  if env.WEZTERM_PANE == nil or env.WEZTERM_PANE == "" then
    return false, "not running inside WezTerm ($WEZTERM_PANE is not set)"
  end
  if vim.fn.executable("wezterm") ~= 1 then
    return false, "`wezterm` is not on $PATH"
  end
  return true, nil
end

--- Create the wezterm backend.
---@param registry Terminal.Registry
---@param runner? Terminal.WezTermRunner
---@param own_pane? string Pane Neovim runs in (default `$WEZTERM_PANE`)
---@return Terminal.Backend
function M.new(registry, runner, own_pane)
  runner = runner or M.default_runner
  own_pane = own_pane or vim.env.WEZTERM_PANE or ""

  ---@type Terminal.Backend
  local backend = {
    name = "wezterm",
    caps = { hide = true, show = false, status = false },
  }

  ---@internal
  ---@param args string[] Arguments after `wezterm cli`
  ---@param opts? { stdin?: string }
  ---@return Terminal.WezTermRun|nil run
  ---@return string|nil err
  local function cli(args, opts)
    local argv = { "wezterm", "cli" }
    vim.list_extend(argv, args)
    local res = runner(argv, opts)
    if res.code ~= 0 then
      local why = vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
      return nil,
        ("wezterm cli %s failed (%d): %s"):format(
          args[1],
          res.code,
          why ~= "" and why or "no output"
        )
    end
    return res, nil
  end

  ---@internal
  --- Every pane WezTerm knows, by id.
  ---@return table<string, table>|nil panes
  ---@return string|nil err
  local function panes()
    local res, err = cli({ "list", "--format", "json" })
    if not res then
      return nil, err
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok or type(data) ~= "table" then
      return nil, "wezterm cli list returned something that is not JSON"
    end
    local by_id = {}
    for _, p in ipairs(data) do
      by_id[tostring(p.pane_id)] = p
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
      return nil, "the wezterm backend cannot set environment variables for a pane"
    end
    local args
    if spec.layout == "tab" then
      args = { "spawn", "--pane-id", own_pane }
    else
      args =
        { "split-pane", "--pane-id", own_pane, spec.layout == "split" and "--bottom" or "--right" }
      local size = (spec.split or {}).size
      if type(size) == "number" and size > 0 and size <= 1 then
        vim.list_extend(args, { "--percent", tostring(math.floor(size * 100)) })
      end
    end
    if spec.cwd and spec.cwd ~= "" then
      vim.list_extend(args, { "--cwd", spec.cwd })
    end
    local cmd = spec.cmd
    if type(cmd) == "string" and cmd ~= "" then
      cmd = { cmd }
    end
    if type(cmd) == "table" and #cmd > 0 then
      args[#args + 1] = "--"
      vim.list_extend(args, cmd)
    end

    local res, err = cli(args)
    if not res then
      return nil, err
    end
    local pane = vim.trim(res.stdout)
    if not pane:find("^%d+$") then
      return nil, ("unexpected output from wezterm cli %s: %q"):format(args[1], res.stdout)
    end

    local root = spec.root or spec.cwd
    ---@type Terminal.Handle
    local handle = {
      id = registry_mod.make_id(root, spec.name),
      name = spec.name,
      root = root,
      backend = "wezterm",
      pane = pane,
      layout = spec.layout,
    }
    registry:add(handle)
    -- A new pane takes focus; without focus the caller wants to stay where it was.
    if spec.start_insert == false and own_pane ~= "" then
      cli({ "activate-pane", "--pane-id", own_pane })
    end
    return handle, nil
  end

  ---@param handle Terminal.Handle
  ---@param text string
  ---@return boolean
  ---@return string|nil
  function backend.send(handle, text)
    local res, err = cli({ "send-text", "--pane-id", handle.pane, "--no-paste" }, { stdin = text })
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
    return mine ~= nil and mine.is_active == true
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.focus(handle)
    local res, err = cli({ "activate-pane", "--pane-id", handle.pane })
    return res ~= nil, err
  end

  --- A pane cannot be hidden; "hide" gives focus back to Neovim's own pane.
  ---@param _handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.hide(_handle)
    if own_pane == "" then
      return false, "Neovim's own pane is unknown"
    end
    local res, err = cli({ "activate-pane", "--pane-id", own_pane })
    return res ~= nil, err
  end

  ---@return Terminal.Handle[]
  function backend.list()
    local all = panes()
    local out = {}
    for _, h in ipairs(registry:list()) do
      if h.backend == "wezterm" then
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
    -- A pane that is already gone makes `kill-pane` fail; the terminal is closed either way.
    cli({ "kill-pane", "--pane-id", handle.pane })
    return true, nil
  end

  return backend
end

return M
