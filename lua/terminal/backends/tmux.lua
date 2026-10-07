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
---
--- Every piece of *data* that becomes a tmux argument (typed text, a directory, the words of a
--- command, an option value) goes through `M.word`: tmux reads a trailing `;` of an argument as a
--- command separator, so a bare word like `select 1;` would lose its `;` and a word like
--- `notes;` followed by `run-shell` would start another tmux command.

local registry_mod = require("terminal.core.registry")

local M = {}

--- One data word as a tmux argument. tmux's command parser ends a command at an argument that
--- ends in `;` and turns a trailing `\;` into `;`; a backslash in front of the final `;` makes it
--- a literal again: `a;` -> `a\;` (read as `a;`), `a\;` -> `a\\;` (read as `a\;`).
---@param s string
---@return string
function M.word(s)
  if s:sub(-1) == ";" then
    return s:sub(1, -2) .. "\\;"
  end
  return s
end

--- The `[major, minor]` of a `tmux -V` line (`tmux 3.4`, `tmux 3.0a`, `tmux next-3.5`); nil for
--- builds without a number (`tmux master`).
---@param text string
---@return integer|nil major
---@return integer|nil minor
function M.parse_version(text)
  local major, minor = tostring(text):match("tmux%s+[%a%-]*(%d+)%.(%d+)")
  if not major then
    return nil, nil
  end
  return tonumber(major), tonumber(minor)
end

--- Whether `split-window -l <n>%` exists (tmux 3.1+); older releases take `-p <n>`. An unknown
--- version counts as new.
---@param major integer|nil
---@param minor integer|nil
---@return boolean
function M.has_percent_size(major, minor)
  if major == nil then
    return true
  end
  return major > 3 or (major == 3 and (minor or 0) >= 1)
end

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
  --- Whether the running tmux takes `split-window -l <n>%`. Asked once, on the first split (a
  --- process the setup must not pay for); an unreadable version counts as new.
  ---@type boolean|nil
  local percent_size

  ---@internal
  ---@return boolean
  local function takes_percent_size()
    if percent_size == nil then
      local res = tmux({ "-V" })
      if res then
        percent_size = M.has_percent_size(M.parse_version(res.stdout))
      else
        percent_size = true
      end
    end
    return percent_size
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

  ---@internal
  --- Make `pane` the one the user sees: its window first, then the pane (one tmux process).
  ---@param pane string
  ---@return boolean ok
  ---@return string|nil err
  local function select_pane(pane)
    local res, err = tmux({ "select-window", "-t", pane, ";", "select-pane", "-t", pane })
    return res ~= nil, err
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
    if spec.layout == "tab" then
      args = { "new-window", "-P", "-F", "#{pane_id}" }
    else
      args = { "split-window", "-P", "-F", "#{pane_id}", "-t", own_pane }
      args[#args + 1] = spec.layout == "split" and "-v" or "-h"
      local size = (spec.split or {}).size
      if type(size) == "number" and size > 0 and size <= 1 then
        local percent = math.floor(size * 100)
        if takes_percent_size() then
          vim.list_extend(args, { "-l", ("%d%%"):format(percent) })
        else
          vim.list_extend(args, { "-p", tostring(percent) })
        end
      end
    end
    -- `-d`: the new pane is not selected, the user stays where they are.
    if spec.focus == false then
      args[#args + 1] = "-d"
    end
    if spec.cwd and spec.cwd ~= "" then
      vim.list_extend(args, { "-c", M.word(spec.cwd) })
    end
    local cmd = spec.cmd
    if type(cmd) == "string" and cmd ~= "" then
      cmd = { cmd }
    end
    if type(cmd) == "table" and #cmd > 0 then
      -- `--`: a first word that starts with a dash is the program, not an option of tmux.
      args[#args + 1] = "--"
      for _, word in ipairs(cmd) do
        args[#args + 1] = M.word(word)
      end
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
    local res, err = tmux({ "send-keys", "-t", handle.pane, "-l", "--", M.word(text) })
    if not res then
      return false, err
    end
    return true, nil
  end

  --- Whether the pane exists and whether it has the user's focus, from ONE `list-panes`.
  --- nil (with the reason) when tmux cannot be asked: the state is unknown, not "gone".
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
    return { visible = true, focused = mine.active and mine.window_active }, nil
  end

  ---@param handle Terminal.Handle
  ---@return boolean|nil visible nil when tmux could not be asked
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
    return select_pane(handle.pane)
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
    return select_pane(own_pane)
  end

  ---@return Terminal.Handle[]
  function backend.list()
    ---@type Terminal.Handle[]
    local mine = {}
    for _, h in ipairs(registry:list()) do
      if h.backend == "tmux" then
        mine[#mine + 1] = h
      end
    end
    -- Nothing of ours: no reason to start a tmux process.
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
  --- whose state cannot be read) stays registered and the failure is reported.
  ---@param handle Terminal.Handle
  ---@return boolean
  ---@return string|nil
  function backend.close(handle)
    local res, err = tmux({ "kill-pane", "-t", handle.pane })
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
