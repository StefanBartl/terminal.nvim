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

---@internal
--- The objects in the JSON list a `wezterm cli` command printed. That output is a foreign API's
--- answer: whatever is not an object (a number, a JSON null) is dropped, and a null inside an
--- object is an absent field -- never `vim.NIL`, which is truthy and not equal to nil.
---@param stdout string
---@return table[]|nil objects nil when the text is not JSON or not a list
local function decode_objects(stdout)
  local ok, data = pcall(vim.json.decode, stdout, { luanil = { object = true } })
  if not ok or type(data) ~= "table" then
    return nil
  end
  local objects = {}
  for _, entry in ipairs(data) do
    if type(entry) == "table" then
      objects[#objects + 1] = entry
    end
  end
  return objects
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
    local data = decode_objects(res.stdout)
    if not data then
      return nil, "wezterm cli list returned something that is not JSON"
    end
    local by_id = {}
    for _, p in ipairs(data) do
      if p.pane_id ~= nil then
        by_id[tostring(p.pane_id)] = p
      end
    end
    return by_id, nil
  end

  function backend.available(env)
    return M.available(env)
  end

  --- What this backend refuses to start, found out without side effects (`pin` asks before it
  --- touches the terminal it is about to replace).
  ---@param spec Terminal.SpawnSpec
  ---@return boolean ok
  ---@return string|nil refused
  function backend.preflight(spec)
    if spec.env and next(spec.env) ~= nil then
      return false, "the wezterm backend cannot set environment variables for a pane"
    end
    return true, nil
  end

  --- Whether the multiplexer answers right now (one cheap query). `pin` asks before it ends the
  --- terminal it is about to replace.
  ---@return boolean up
  ---@return string|nil err
  function backend.ping()
    local all, err = panes()
    return all ~= nil, err
  end

  ---@param spec Terminal.SpawnSpec
  ---@return Terminal.Handle|nil
  ---@return string|nil
  function backend.spawn(spec)
    local ok, refused = backend.preflight(spec)
    if not ok then
      return nil, refused
    end
    if not vim.list_contains(require("terminal.backends").LAYOUTS, spec.layout) then
      return nil, ("unknown layout '%s'"):format(tostring(spec.layout))
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
      -- No shell sits between WezTerm and the program: "pwsh -NoLogo" would be looked up as ONE
      -- program name. A string without white space is one word. One with white space is split --
      -- unless it names an executable as it stands (a path with spaces), which is only possible
      -- with a path separator in it: the PATH scan of `executable()` (tens of milliseconds on
      -- Windows) is not paid for "pwsh -NoLogo". Quotes are not interpreted: use a list for those.
      if not cmd:find("%s") or (cmd:find("[/\\]") and vim.fn.executable(cmd) == 1) then
        cmd = { cmd }
      else
        cmd = vim.split(cmd, "%s+", { trimempty = true })
      end
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
    if spec.focus == false and own_pane ~= "" then
      local back, berr = cli({ "activate-pane", "--pane-id", own_pane })
      if not back then
        vim.schedule(function()
          require("terminal.notify").warn(
            ("terminal '%s': could not give focus back to Neovim's pane: %s"):format(
              spec.name,
              berr or "?"
            )
          )
        end)
      end
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

  ---@internal
  --- The pane the user's WezTerm client has focus in (`wezterm cli list-clients`), as a string.
  ---@return string|nil
  local function client_focus()
    local res = cli({ "list-clients", "--format", "json" })
    if not res then
      return nil
    end
    for _, client in ipairs(decode_objects(res.stdout) or {}) do
      -- A client without a focused pane reports null: the next client may have one.
      if type(client.focused_pane_id) == "number" then
        return tostring(client.focused_pane_id)
      end
    end
    return nil
  end

  --- Whether the pane exists and whether it has the user's focus, from ONE `wezterm cli list`
  --- (plus a `list-clients` only for a pane in another tab). nil (with the reason) when WezTerm
  --- cannot be asked: the state is unknown, not "gone".
  ---
  --- `is_active` in the pane list only means "active within its own tab", so it says nothing
  --- about a pane in a tab the user is not looking at; for that case the client's focused pane
  --- decides.
  ---@param handle Terminal.Handle
  ---@return { visible: boolean, focused: boolean }|nil
  ---@return string|nil err
  function backend.probe(handle)
    local all, err = panes()
    if not all then
      return nil, err
    end
    local mine = all[handle.pane]
    if not mine then
      return { visible = false, focused = false }, nil
    end
    local focused = mine.is_active == true
    local own = all[own_pane]
    if focused and own and own.tab_id ~= nil and mine.tab_id ~= own.tab_id then
      focused = client_focus() == handle.pane
    end
    return { visible = true, focused = focused }, nil
  end

  ---@param handle Terminal.Handle
  ---@return boolean|nil visible nil when WezTerm could not be asked
  function backend.visible(handle)
    local state = backend.probe(handle)
    return state and state.visible
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  function backend.focused(handle)
    local state = backend.probe(handle)
    return state ~= nil and state.focused
  end

  ---@param handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.focus(handle)
    local res, err = cli({ "activate-pane", "--pane-id", handle.pane })
    return res ~= nil, err
  end

  --- The pane's visible text (`wezterm cli get-text`).
  ---@param handle Terminal.Handle
  ---@return string|nil
  ---@return string|nil
  function backend.capture(handle)
    local res, err = cli({ "get-text", "--pane-id", handle.pane })
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
    local res, err = cli({ "activate-pane", "--pane-id", own_pane })
    return res ~= nil, err
  end

  ---@return Terminal.Handle[]
  function backend.list()
    ---@type Terminal.Handle[]
    local mine = {}
    for _, h in ipairs(registry:list()) do
      if h.backend == "wezterm" then
        mine[#mine + 1] = h
      end
    end
    -- Nothing of ours: no reason to start a wezterm process.
    if #mine == 0 then
      return mine
    end
    local all = panes()
    local out = {}
    for _, h in ipairs(mine) do
      if all == nil or all[h.pane] ~= nil then
        out[#out + 1] = h
      else
        registry:remove(h.id)
      end
    end
    return out
  end

  --- Kill the pane. A pane that is already gone counts as closed; one that cannot be killed (or
  --- whose state cannot be read) stays registered and the failure is reported. `gone`: the caller
  --- has just seen that the pane does not exist, so there is nothing to ask WezTerm.
  ---@param handle Terminal.Handle
  ---@param how? { gone?: boolean }
  ---@return boolean
  ---@return string|nil
  function backend.close(handle, how)
    if how and how.gone then
      if registry:get(handle.id) == handle then
        registry:remove(handle.id)
      end
      return true, nil
    end
    local res, err = cli({ "kill-pane", "--pane-id", handle.pane })
    if not res then
      local all = panes()
      if not (all and all[handle.pane] == nil) then
        return false, err
      end
    end
    if registry:get(handle.id) == handle then
      registry:remove(handle.id)
    end
    return true, nil
  end

  return backend
end

return M
