---@module 'terminal.backends.native'
--- The `native` backend: terminals are Neovim `:terminal` buffers in a float, split, vsplit or
--- tab. Always available; every other backend falls back to it.
---
--- `new(registry)` returns a backend whose handles live in the given registry. The one thing
--- that is not per backend is the `BufWipeout` watcher: it is a named autocommand group, so it
--- is bound to the registry of the backend created last.

local layout_math = require("terminal.core.layout")
local registry_mod = require("terminal.core.registry")

local api = vim.api
local fn = vim.fn

--- How long `close` waits for a stopped job to report its exit: a shell reacts to the signal in
--- milliseconds, one that does not within a second is stuck.
local JOB_STOP_WAIT_MS = 1000

--- How long `close` keeps waiting for the process itself after that warning. Neovim ends a job
--- that ignores its stop signal on its own after a few seconds, and `jobwait` ignores its timeout
--- once `jobstop` was called, so this is an upper bound that is not expected to be reached.
local JOB_KILL_WAIT_MS = 5000

--- Windows only: how long a layout change (a window of this backend opened or closed) has to be in
--- the past before a job is stopped. Closing one terminal's window resizes its neighbours' ConPTYs,
--- and stopping the job of such a terminal within a few milliseconds kills Neovim (0xC0000005:
--- `close(a); close(b)` on two running splits, every time; 30 ms apart it never happened). Measured
--- steps: 10 ms crashed, 20 ms 3 of 4 survived, 30..150 ms 3 of 3. 100 ms keeps clear of it on a
--- loaded machine.
local LAYOUT_SETTLE_MS = 100

local M = {}

---@internal
--- The buffer a window shows after its terminal is gone: the one `:bdelete` would show -- the
--- alternate buffer, else the most recently used listed one -- and a fresh empty buffer only when
--- the editor has no other.
---@param exclude integer The terminal buffer that is going away
---@param win integer The window that shows it (its alternate buffer counts, not the current window's)
---@return integer bufnr
---@return boolean created True when the buffer is a new empty one (the caller owns it)
local function replacement(exclude, win)
  local function usable(b)
    return b > 0 and b ~= exclude and api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
  end
  local alt = api.nvim_win_call(win, function()
    return fn.bufnr("#")
  end)
  if usable(alt) then
    return alt, false
  end
  local listed = fn.getbufinfo({ buflisted = 1 })
  table.sort(listed, function(a, b)
    return a.lastused > b.lastused
  end)
  for _, info in ipairs(listed) do
    if usable(info.bufnr) then
      return info.bufnr, false
    end
  end
  return api.nvim_create_buf(true, false), true
end

---@internal
--- How many normal (not floating) windows a tab page has.
---@param tab integer
---@return integer
local function normal_windows(tab)
  return #vim.tbl_filter(function(w)
    return api.nvim_win_get_config(w).relative == ""
  end, api.nvim_tabpage_list_wins(tab))
end

---@internal
--- Whether closing `win` is not possible because it is the last normal window of the last tab
--- (`true`: it has to show another buffer instead). A floating window is never that: floats are not
--- "windows left to look at". `leave_window` acts on this answer, `replaced_windows` asks it ahead of
--- time.
---@param win integer
---@param normal_left integer Normal windows in the window's tab right now
---@param tabs_left integer Tab pages right now
---@return boolean replaced
local function is_replaced(win, normal_left, tabs_left)
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  return normal_left <= 1 and tabs_left <= 1
end

---@internal
--- The windows of the terminal buffer that closing will not close but give another buffer, worked
--- out in the order they are taken (closing one window can make the next one the last). At most one:
--- the last normal window of the last tab.
---@param bufnr integer
---@return integer[] wins
local function replaced_windows(bufnr)
  local out = {}
  local left = {}
  local tabs = #api.nvim_list_tabpages()
  for _, win in ipairs(fn.win_findbuf(bufnr)) do
    if api.nvim_win_get_config(win).relative == "" then
      local tab = api.nvim_win_get_tabpage(win)
      left[tab] = left[tab] or normal_windows(tab)
      if is_replaced(win, left[tab], tabs) then
        out[#out + 1] = win
      else
        left[tab] = left[tab] - 1
        if left[tab] == 0 then
          tabs = tabs - 1
        end
      end
    end
  end
  return out
end

---@internal
--- `nvim_win_close` that answers instead of raising.
---@param win integer
---@return boolean ok
---@return string|nil err
local function try_close(win)
  local ok, err = pcall(api.nvim_win_close, win, true)
  if ok then
    return true, nil
  end
  return false, tostring(err)
end

---@internal
--- The body of `close_window`; it may raise, `close_window` answers for it.
---@param win integer
---@param bufnr integer
---@return boolean ok
---@return string|nil err
local function leave_window(win, bufnr)
  if not api.nvim_win_is_valid(win) then
    return true, nil
  end
  local normal_left = normal_windows(api.nvim_win_get_tabpage(win))
  if not is_replaced(win, normal_left, #api.nvim_list_tabpages()) then
    return try_close(win)
  end
  local repl, created = replacement(bufnr, win)
  local shown, serr = pcall(api.nvim_win_set_buf, win, repl)
  if not shown then
    -- 'winfixbuf' (E1513) or a locked window: the empty buffer made for it must not stay behind.
    if created then
      pcall(api.nvim_buf_delete, repl, { force = true })
    end
    return false, tostring(serr)
  end
  return true, nil
end

---@internal
--- Close one window without ever closing the last window of the editor. Floating windows are not
--- "windows left to look at": with the terminal in the only normal window and a float open,
--- closing it would raise E444, so that case shows another buffer instead.
---
--- Answers instead of raising: Neovim refuses to close or change a window in places the plugin
--- does not control (textlock inside an `<expr>` mapping, the command-line window, a window with
--- 'winfixbuf'), and `hide`/`close` must tell the caller about that.
---@param win integer
---@param bufnr integer The terminal buffer the window shows (it is not a valid replacement)
---@return boolean ok False when the window still shows the terminal
---@return string|nil err Neovim's reason
local function close_window(win, bufnr)
  local ok, res, err = pcall(leave_window, win, bufnr)
  if not ok then
    return false, tostring(res)
  end
  return res, err
end

---@internal
--- Open a window for `bufnr` according to `spec.layout`; the window becomes the current one.
---@param bufnr integer
---@param spec Terminal.SpawnSpec
---@return integer|nil win
---@return string|nil err
local function open_window(bufnr, spec)
  local layout = spec.layout
  if layout == "float" then
    local float = spec.float or {}
    local geo = layout_math.float(vim.o.columns, vim.o.lines, float)
    local config = {
      relative = "editor",
      row = geo.row,
      col = geo.col,
      width = geo.width,
      height = geo.height,
      style = "minimal",
      border = float.border,
      zindex = float.zindex,
    }
    if float.title and float.border and float.border ~= "none" and float.border ~= "" then
      config.title = (" %s "):format(spec.title or spec.name)
      config.title_pos = float.title_pos
    end
    local ok, win = pcall(api.nvim_open_win, bufnr, true, config)
    if not ok then
      return nil, tostring(win)
    end
    if float.winblend then
      vim.wo[win].winblend = float.winblend
    end
    return win, nil
  elseif layout == "split" or layout == "vsplit" then
    ---@cast layout "split"|"vsplit"
    local size = layout_math.split(layout, vim.o.columns, vim.o.lines, (spec.split or {}).size)
    local config = layout == "split" and { split = "below", win = -1, height = size }
      or { split = "right", win = -1, width = size }
    local ok, win = pcall(api.nvim_open_win, bufnr, true, config)
    if not ok then
      return nil, tostring(win)
    end
    return win, nil
  elseif layout == "tab" then
    vim.cmd("$tabnew")
    local win = api.nvim_get_current_win()
    local placeholder = api.nvim_win_get_buf(win)
    api.nvim_win_set_buf(win, bufnr)
    if
      placeholder ~= bufnr
      and api.nvim_buf_is_valid(placeholder)
      and api.nvim_buf_get_name(placeholder) == ""
      and not vim.bo[placeholder].modified
    then
      pcall(api.nvim_buf_delete, placeholder, { force = true })
    end
    return win, nil
  end
  return nil, ("unknown layout '%s'"):format(tostring(layout))
end

--- Create the native backend.
---@param registry Terminal.Registry Where this backend's handles are kept
---@return Terminal.Backend
function M.new(registry)
  -- Filled by the `function backend.<name>` definitions below; `new` returns it as a
  -- `Terminal.Backend`, which is where the language server checks that nothing is missing.
  local backend = {
    name = "native",
  }

  ---@internal
  --- Remove `handle` from the registry -- but only if the registry still holds *this* handle. A
  --- terminal that was replaced under the same id (close + spawn in one tick) must not take its
  --- successor with it when its deferred exit handler or BufWipeout fires late.
  ---@param handle Terminal.Handle
  local function forget(handle)
    if registry:get(handle.id) == handle then
      registry:remove(handle.id)
    end
  end

  -- When a terminal buffer goes away by any other route (`:bwipeout`, a plugin), forget its handle.
  -- One autocommand for all terminals in a named group instead of one per buffer; a backend that
  -- is created again (a second `setup()`) replaces the group instead of doubling the handler.
  local Autocmd = require("lib.nvim.bindings.autocmd")
  Autocmd.create("BufWipeout", function(args)
    local h = registry:find_by_buf(args.buf)
    if h and h.backend == "native" then
      forget(h)
    end
  end, {
    group = Autocmd.group("terminal.native", true),
    desc = "terminal.nvim: forget a wiped terminal buffer",
  })

  -- When this backend last opened or closed a window (`vim.uv.hrtime()`, ns); see `settle_layout`.
  local layout_changed_at = 0

  ---@internal
  --- Note that a window of this backend was just opened or closed.
  local function layout_changed()
    layout_changed_at = vim.uv.hrtime()
  end

  ---@internal
  --- Windows only: let the last layout change be `LAYOUT_SETTLE_MS` old before a job is stopped (see
  --- there). Elsewhere, and when nothing changed lately, it returns at once.
  local function settle_layout()
    if fn.has("win32") ~= 1 then
      return
    end
    local left = LAYOUT_SETTLE_MS - (vim.uv.hrtime() - layout_changed_at) / 1e6
    if left > 0 then
      -- (a pause that cannot be had must not abort the close: `close` has marked the handle
      -- disposed by now and the job would be left running)
      pcall(vim.wait, math.ceil(left))
    end
  end

  -- A scratch buffer that could not be deleted (see `editing_blocked`); kept so the next probe
  -- reuses it instead of leaving another one behind (one at most, until the lock is gone).
  local probe_buf = nil

  ---@internal
  --- Why Neovim refuses, right now, to close windows or delete buffers; nil when it does not. It
  --- refuses both under a text lock (an `<expr>` mapping, E565) and in the command-line window
  --- (E11), and the only way to know is to ask with a buffer nobody cares about: a terminal must
  --- not be stopped first and found undeletable afterwards. The probe runs under `:noautocmd`: a
  --- `BufNew` handler of the user that fails for a scratch buffer must not read as a refusal, and
  --- none of them should see a buffer that is made and gone within a call. When the question
  --- cannot be asked at all the answer is "no obstacle known": the real operation then answers.
  ---@return string|nil reason Neovim's own words
  local function editing_blocked()
    if not (probe_buf and api.nvim_buf_is_valid(probe_buf)) then
      local made, res =
        pcall(api.nvim_exec2, "noautocmd echo nvim_create_buf(v:false, v:true)", { output = true })
      local buf = made and tonumber(res.output) or nil
      if not buf then
        return nil
      end
      probe_buf = buf
    end
    local deleted, err = pcall(
      api.nvim_exec2,
      ("noautocmd call nvim_buf_delete(%d, {'force': v:true})"):format(probe_buf),
      {}
    )
    if deleted then
      probe_buf = nil
      return nil
    end
    -- "nvim_exec2(), line 1: Vim(call):E5555: API call: E565: Not allowed ...": keep the last code
    return tostring(err):match(".*(E%d+: .*)$") or tostring(err)
  end

  ---@internal
  --- Whether taking the terminal's windows away (and its buffer after them) would be refused, found
  --- out BEFORE anything is stopped or changed: a refusal that only shows afterwards leaves a dead
  --- job in a window that stays, an empty buffer nobody asked for, or a terminal that is gone from the
  --- screen but not from the registry. Three things refuse: a text lock or the command-line window
  --- (see `editing_blocked`) and a window with 'winfixbuf' that would have to show another buffer.
  ---@param handle Terminal.Handle
  ---@param windows_only? boolean `hide` leaves the buffer alone: a hidden terminal has nothing to ask
  ---@return string|nil reason Ready to be returned to the caller
  local function closing_refusal(handle, windows_only)
    local bufnr = handle.bufnr
    if not bufnr or not api.nvim_buf_is_valid(bufnr) then
      return nil
    end
    local shown = #fn.win_findbuf(bufnr) > 0
    if windows_only and not shown then
      return nil
    end
    local blocked = editing_blocked()
    if blocked then
      return ("%s: %s"):format(
        shown and "cannot close the window" or "cannot delete the buffer",
        blocked
      )
    end
    for _, win in ipairs(replaced_windows(bufnr)) do
      if vim.wo[win].winfixbuf then
        return "cannot close the window: E1513: Cannot switch buffer. 'winfixbuf' is enabled"
      end
    end
    return nil
  end

  ---@internal
  --- Close every window that shows the terminal. Answers instead of raising: Neovim refuses in
  --- places the plugin does not control (textlock, the command-line window, 'winfixbuf').
  ---@param handle Terminal.Handle
  ---@return boolean ok
  ---@return string|nil err
  local function close_windows(handle)
    local bufnr = handle.bufnr
    if not bufnr or not api.nvim_buf_is_valid(bufnr) then
      return true, nil
    end
    for _, win in ipairs(fn.win_findbuf(bufnr)) do
      local ok, err = close_window(win, bufnr)
      if not ok then
        return false, ("cannot close the window: %s"):format(err)
      end
      layout_changed()
    end
    return true, nil
  end

  ---@internal
  --- Delete the terminal's buffer and forget the handle -- in that order, and only when the buffer
  --- is really gone: a buffer that cannot be deleted (textlock) must stay reachable.
  ---@param handle Terminal.Handle
  ---@return boolean ok
  ---@return string|nil err
  local function remove_buffer(handle)
    local bufnr = handle.bufnr
    if bufnr and api.nvim_buf_is_valid(bufnr) then
      local deleted, derr = pcall(api.nvim_buf_delete, bufnr, { force = true })
      if not deleted and api.nvim_buf_is_valid(bufnr) then
        return false, ("cannot delete the buffer: %s"):format(tostring(derr))
      end
    end
    forget(handle)
    return true, nil
  end

  ---@internal
  --- Remove a terminal that has no running job: its window(s) first, then the buffer. When a
  --- window cannot be closed the terminal stays as it is -- registered, buffer alive -- so that it
  --- is still reachable and `close` can be tried again; nothing is left behind that the registry
  --- does not know about.
  ---@param handle Terminal.Handle
  ---@return boolean ok
  ---@return string|nil err
  local function dispose(handle)
    local refusal = closing_refusal(handle)
    if refusal then
      return false, refusal
    end
    -- Set first: from here on the exit of the job must not run the `on_exit` mode.
    handle.disposed = true
    local ok, err = close_windows(handle)
    if not ok then
      handle.disposed = nil
      return false, err
    end
    ok, err = remove_buffer(handle)
    if not ok then
      handle.disposed = nil
      return false, err
    end
    return true, nil
  end

  --- Interface method (`Terminal.Backend`); native is always available, so the facade never asks.
  ---@param _env table<string, string|nil>
  ---@return boolean available
  ---@return string|nil reason
  function backend.available(_env)
    return true, nil
  end

  ---@param spec Terminal.SpawnSpec
  ---@return Terminal.Handle|nil handle
  ---@return string|nil err
  function backend.spawn(spec)
    local bufnr = api.nvim_create_buf(false, false)
    -- Closing the window (`hide`) must leave the buffer, and the job in it, alive.
    vim.bo[bufnr].bufhidden = "hide"

    local win, werr = open_window(bufnr, spec)
    if not win then
      pcall(api.nvim_buf_delete, bufnr, { force = true })
      return nil, werr
    end
    layout_changed()

    local root = spec.root or spec.cwd
    ---@type Terminal.Handle
    local handle = {
      id = registry_mod.make_id(root, spec.name),
      name = spec.name,
      root = root,
      backend = "native",
      bufnr = bufnr,
      layout = spec.layout,
      cmd = spec.cmd,
      cwd = spec.cwd,
    }

    local cmd = spec.cmd
    if cmd == nil or cmd == "" then
      cmd = vim.o.shell
    end
    local job_opts = {
      cwd = spec.cwd,
      env = spec.env,
      on_exit = function(_, code)
        vim.schedule(function()
          handle.exited = true
          handle.exit_code = code
          if spec.on_exit_cb then
            pcall(spec.on_exit_cb, code)
          end
          if handle.disposed then
            return
          end
          local mode = spec.on_exit or "close"
          if mode == "close" or (mode == "close_on_success" and code == 0) then
            -- Nobody asked, so nobody is told: a window that cannot be closed right now leaves
            -- the finished terminal registered, and `close` removes it later.
            dispose(handle)
          end
        end)
      end,
    }

    job_opts.term = true
    local ok, res = pcall(fn.jobstart, cmd, job_opts)
    local job = ok and res or -1
    if job <= 0 then
      close_window(win, bufnr)
      pcall(api.nvim_buf_delete, bufnr, { force = true })
      return nil, ("could not start '%s'"):format(type(cmd) == "table" and cmd[1] or cmd)
    end
    handle.job = job

    registry:add(handle)
    if spec.start_insert then
      vim.cmd("startinsert")
    end
    return handle, nil
  end

  ---@param handle Terminal.Handle
  ---@param text string
  ---@return boolean ok
  ---@return string|nil err
  function backend.send(handle, text)
    if handle.exited or not handle.bufnr or not api.nvim_buf_is_valid(handle.bufnr) then
      return false, "the terminal is not running"
    end
    local ok, err = pcall(api.nvim_chan_send, handle.job, text)
    if not ok then
      return false, tostring(err)
    end
    return true, nil
  end

  ---@param handle Terminal.Handle
  ---@return boolean visible
  function backend.visible(handle)
    return handle.bufnr ~= nil
      and api.nvim_buf_is_valid(handle.bufnr)
      and #fn.win_findbuf(handle.bufnr) > 0
  end

  ---@param handle Terminal.Handle
  ---@return boolean focused
  function backend.focused(handle)
    return handle.bufnr ~= nil and api.nvim_get_current_buf() == handle.bufnr
  end

  --- Visible and focused in one answer (the facade asks every backend this way).
  ---@param handle Terminal.Handle
  ---@return Terminal.Probe
  function backend.probe(handle)
    local visible = backend.visible(handle)
    return { visible = visible, focused = visible and backend.focused(handle) }
  end

  ---@param handle Terminal.Handle
  ---@return boolean ok
  ---@return string|nil err
  function backend.focus(handle)
    if not handle.bufnr or not api.nvim_buf_is_valid(handle.bufnr) then
      return false, "the terminal buffer is gone"
    end
    local wins = fn.win_findbuf(handle.bufnr)
    if #wins == 0 then
      return false, "the terminal is hidden"
    end
    api.nvim_set_current_win(wins[1])
    return true, nil
  end

  ---@param handle Terminal.Handle
  ---@param spec Terminal.SpawnSpec
  ---@return boolean ok
  ---@return string|nil err
  function backend.show(handle, spec)
    if not handle.bufnr or not api.nvim_buf_is_valid(handle.bufnr) then
      return false, "the terminal buffer is gone"
    end
    local win, err = open_window(handle.bufnr, spec)
    if not win then
      return false, err
    end
    layout_changed()
    handle.layout = spec.layout
    if spec.start_insert then
      vim.cmd("startinsert")
    end
    return true, nil
  end

  ---@param handle Terminal.Handle
  ---@return boolean ok
  ---@return string|nil err
  function backend.hide(handle)
    if not handle.bufnr or not api.nvim_buf_is_valid(handle.bufnr) then
      return false, "the terminal buffer is gone"
    end
    local refusal = closing_refusal(handle, true)
    if refusal then
      return false, refusal
    end
    return close_windows(handle)
  end

  ---@return Terminal.Handle[]
  function backend.list()
    local out = {}
    for _, h in ipairs(registry:list()) do
      if h.backend == "native" then
        if h.bufnr and api.nvim_buf_is_valid(h.bufnr) then
          out[#out + 1] = h
        else
          registry:remove(h.id)
        end
      end
    end
    return out
  end

  ---@param handle Terminal.Handle
  ---@return boolean ok
  ---@return string|nil err
  function backend.close(handle)
    -- Whether Neovim will let the windows and the buffer go is asked FIRST, before the job is
    -- touched: a refusal leaves the terminal exactly as it was, running and registered (a pin or a
    -- replacement must not kill a command it cannot replace). The windows are NOT closed before the
    -- job is stopped: a running terminal that is shown in two windows crashed Neovim on Windows
    -- (0xC0000005, every time, however long the pause) when `jobstop` followed the closing of its
    -- windows within one call; stopping the job first does not.
    local refusal = closing_refusal(handle)
    if refusal then
      return false, refusal
    end
    -- Set first: from here on the exit of the job is the answer to this call, not an `on_exit` event.
    handle.disposed = true
    -- Is the process still alive? Asked of the process, not of the exit flag: inside a `TermClose`
    -- handler the job is reaped but its `on_exit` is queued behind the handler. Asked BEFORE
    -- `jobstop`, because after it `jobwait` ignores its timeout.
    local running = handle.job ~= nil
      and not handle.exited
      and fn.jobwait({ handle.job }, 0)[1] == -1
    if running then
      -- Not right after another window opened or closed (see LAYOUT_SETTLE_MS).
      settle_layout()
      pcall(fn.jobstop, handle.job)
      -- Let the job actually end before its buffer goes away: deleting the buffer of a job that
      -- is still shutting down crashed Neovim 0.12 on Windows (0xC0000005, headless, splits).
      -- The wait is on the exit flag, which `on_exit` sets from a scheduled callback (`vim.wait`
      -- runs those). `jobwait` cannot time this: once `jobstop` was called it ignores its timeout
      -- and returns -3 after Neovim's own kill, never -1 for a job that is still alive.
      local stopped = vim.wait(JOB_STOP_WAIT_MS, function()
        return handle.exited == true
      end, 10)
      if not stopped then
        -- Still running after the wait: the terminal is removed anyway (the user asked for it),
        -- but a job that survives its own `jobstop` is worth a line.
        vim.schedule(function()
          require("terminal.notify").warn(
            ("terminal '%s': the job did not stop within %d ms"):format(
              handle.name,
              JOB_STOP_WAIT_MS
            )
          )
        end)
        -- Neovim ends such a job itself after a few seconds; the buffer must not be deleted
        -- before that (the ConPTY crash above).
        pcall(fn.jobwait, { handle.job }, JOB_KILL_WAIT_MS)
      end
    end
    -- The windows, now that nothing runs in them. The refusals that can be known were asked about
    -- above; one that could not (the editor changed while the job was stopping) leaves a finished
    -- terminal that is still registered, so the next `close` finishes the job.
    local ok, err = close_windows(handle)
    if ok then
      ok, err = remove_buffer(handle)
    end
    if not ok then
      handle.disposed = nil
      return false, err
    end
    return true, nil
  end

  return backend
end

return M
