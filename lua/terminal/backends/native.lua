---@module 'terminal.backends.native'
--- The `native` backend: terminals are Neovim `:terminal` buffers in a float, split, vsplit or
--- tab. Always available; every other backend falls back to it.
---
--- `new(registry)` returns a backend whose handles live in the given registry; nothing is kept
--- at module level.

local layout_math = require("terminal.core.layout")
local registry_mod = require("terminal.core.registry")

local api = vim.api
local fn = vim.fn

--- How long `close` waits for a stopped job to end: a shell reacts to the signal in milliseconds,
--- one that does not within a second is stuck.
local JOB_STOP_WAIT_MS = 1000

local M = {}

---@internal
--- The buffer a window shows after its terminal is gone: the one `:bdelete` would show -- the
--- alternate buffer, else the most recently used listed one -- and a fresh empty buffer only when
--- the editor has no other.
---@param exclude integer The terminal buffer that is going away
---@return integer bufnr
local function replacement(exclude)
  local function usable(b)
    return b > 0 and b ~= exclude and api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
  end
  local alt = fn.bufnr("#")
  if usable(alt) then
    return alt
  end
  local listed = fn.getbufinfo({ buflisted = 1 })
  table.sort(listed, function(a, b)
    return a.lastused > b.lastused
  end)
  for _, info in ipairs(listed) do
    if usable(info.bufnr) then
      return info.bufnr
    end
  end
  return api.nvim_create_buf(true, false)
end

---@internal
--- Close one window without ever closing the last window of the editor. Floating windows are not
--- "windows left to look at": with the terminal in the only normal window and a float open,
--- closing it would raise E444, so that case shows another buffer instead.
---@param win integer
---@param bufnr integer The terminal buffer the window shows (it is not a valid replacement)
---@return nil
local function close_window(win, bufnr)
  if not api.nvim_win_is_valid(win) then
    return
  end
  if api.nvim_win_get_config(win).relative ~= "" then
    pcall(api.nvim_win_close, win, true)
    return
  end
  local tab = api.nvim_win_get_tabpage(win)
  local normal = vim.tbl_filter(function(w)
    return api.nvim_win_get_config(w).relative == ""
  end, api.nvim_tabpage_list_wins(tab))
  if #normal > 1 or #api.nvim_list_tabpages() > 1 then
    pcall(api.nvim_win_close, win, true)
    return
  end
  api.nvim_win_set_buf(win, replacement(bufnr))
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
  ---@type Terminal.Backend
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

  ---@internal
  --- Forget a terminal and remove its window(s) and buffer.
  ---@param handle Terminal.Handle
  local function dispose(handle)
    handle.disposed = true
    forget(handle)
    local bufnr = handle.bufnr
    if bufnr and api.nvim_buf_is_valid(bufnr) then
      for _, win in ipairs(fn.win_findbuf(bufnr)) do
        close_window(win, bufnr)
      end
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end
  end

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
    vim.bo[bufnr].bufhidden = "hide"

    local win, werr = open_window(bufnr, spec)
    if not win then
      pcall(api.nvim_buf_delete, bufnr, { force = true })
      return nil, werr
    end

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
  ---@return { visible: boolean, focused: boolean }
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
    for _, win in ipairs(fn.win_findbuf(handle.bufnr)) do
      close_window(win, handle.bufnr)
    end
    return true, nil
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
    if handle.job and not handle.exited then
      pcall(fn.jobstop, handle.job)
      -- Let the job actually end before its buffer goes away: deleting the buffer of a job that
      -- is still shutting down crashed Neovim 0.12 on Windows (0xC0000005, headless, splits).
      local ok, waited = pcall(fn.jobwait, { handle.job }, JOB_STOP_WAIT_MS)
      if ok and waited[1] == -1 then
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
      end
    end
    dispose(handle)
    return true, nil
  end

  return backend
end

return M
