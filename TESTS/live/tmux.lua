-- TESTS/live/tmux.lua -- the tmux backend and status exporter against a REAL tmux server.
--
-- Headless is fine (nothing here needs a UI). It starts its own tmux server on a private socket
-- (`-L terminal-nvim-live`), so it never touches your sessions, and kills it at the end.
--
--   Linux/macOS:  SMOKE_OUT=/tmp/t.txt nvim --headless -u NONE -l TESTS/live/tmux.lua
--   Windows:      TMUX_LIVE_WSL=archlinux nvim --headless -u NONE -l TESTS/live/tmux.lua
--                 (runs `wsl.exe -d <distro> -e tmux ...`; tmux must be installed in that distro)
--
-- One line per check goes to $SMOKE_OUT (default: terminal-tmux.txt), ending in "RESULT ok" or
-- "RESULT failed".

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/tmux%.lua$")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.env.LIB_NVIM_DIR or (root .. "/../lib.nvim"))

local SOCKET = "terminal-nvim-live"
local wsl = vim.env.TMUX_LIVE_WSL

local out, failed = {}, false

---@param name string
---@param cond boolean
---@param detail? any
local function check(name, cond, detail)
  if cond then
    out[#out + 1] = "ok   " .. name
  else
    failed = true
    out[#out + 1] = ("FAIL %s%s"):format(
      name,
      detail ~= nil and (" -- " .. vim.inspect(detail)) or ""
    )
  end
end

--- Run a command, through WSL when asked to.
---@param argv string[]
---@return { code: integer, stdout: string, stderr: string }
local function run(argv)
  local full = argv
  if wsl and wsl ~= "" then
    full = { "wsl.exe", "-d", wsl, "-e" }
    vim.list_extend(full, argv)
  end
  local res = vim.system(full, { text = true, timeout = 5000 }):wait()
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

local function tmux(...)
  return run(vim.list_extend({ "tmux", "-L", SOCKET }, { ... }))
end

local ok, err = pcall(function()
  local started =
    tmux("new-session", "-d", "-s", "live", "-x", "120", "-y", "40", "-P", "-F", "#{pane_id}")
  check("a private tmux server started", started.code == 0, started)
  local own = vim.trim(started.stdout)

  local registry = require("terminal.core.registry").new()
  local backend = require("terminal.backends.tmux").new(registry, function(argv)
    return run(argv)
  end, own, { socket = SOCKET })

  local h = backend.spawn({
    name = "live",
    root = "/live",
    cwd = "/tmp",
    layout = "vsplit",
    split = { size = 0.4 },
    start_insert = true,
  })
  check("spawn creates a pane", h ~= nil and h.pane:find("^%%%d+$") ~= nil, h)
  vim.wait(800)

  local sent = backend.send(h, "echo terminal-nvim-tmux-check\n")
  check("send reports success", sent == true)
  local seen = vim.wait(5000, function()
    local cap = tmux("capture-pane", "-p", "-t", h.pane)
    return cap.stdout:find("terminal%-nvim%-tmux%-check\n.*terminal%-nvim%-tmux%-check") ~= nil
      or select(2, cap.stdout:gsub("terminal%-nvim%-tmux%-check", "")) >= 2
  end, 250)
  check("the command's output is in the pane", seen)

  -- Hostile text is typed literally, not interpreted by tmux.
  backend.send(h, "echo 'C-c Enter; kill-server'\n")
  vim.wait(500)
  check("the server survived hostile text", tmux("list-sessions").code == 0)

  check("the pane is visible and focused", backend.visible(h) and backend.focused(h))
  backend.hide(h)
  check("hide returns focus to Neovim's pane", backend.focused(h) == false)
  check("focus selects the pane again", backend.focus(h) == true and backend.focused(h) == true)
  check("list shows it", #backend.list() == 1)

  -- Status export as pane options on Neovim's own pane.
  local exporter = require("terminal.status.exporters.tmux")
  local saved_run, saved_pane = exporter.run, vim.env.TMUX_PANE
  vim.env.TMUX_PANE = own
  exporter.run = function(argv)
    -- argv[1] is "tmux": add the private socket
    local full = { "tmux", "-L", SOCKET }
    vim.list_extend(full, vim.list_slice(argv, 2))
    local r = run(full)
    return { code = r.code, stderr = r.stderr }
  end
  local published = exporter.publish(vim.json.encode({
    mode = "i",
    file = "main.lua",
    branch = "dev",
    e = 2,
    w = 1,
    rec = "",
    mod = true,
  }))
  check("status publish succeeded", published == true)
  local mode = tmux("show-options", "-p", "-v", "-t", own, "@terminal_mode")
  local diag = tmux("show-options", "-p", "-v", "-t", own, "@terminal_diag")
  local fmt = tmux("display-message", "-p", "-t", own, "#{@terminal_file} #{@terminal_branch}")
  check("@terminal_mode is set", vim.trim(mode.stdout) == "i", mode)
  check("@terminal_diag is E2 W1", vim.trim(diag.stdout) == "E2 W1", diag)
  check("a tmux format can read the options", vim.trim(fmt.stdout) == "main.lua dev", fmt)
  exporter.clear()
  local cleared = tmux("show-options", "-p", "-v", "-t", own, "@terminal_mode")
  check("clear removes the options", vim.trim(cleared.stdout) == "", cleared)
  exporter.run, vim.env.TMUX_PANE = saved_run, saved_pane

  check("close kills the pane", backend.close(h) == true)
  vim.wait(300)
  check("the pane is gone", backend.visible(h) == false)
  check("nothing is left", #backend.list() == 0)
end)
if not ok then
  failed = true
  out[#out + 1] = "FAIL error: " .. tostring(err)
end
tmux("kill-server")
out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
local f = io.open(vim.env.SMOKE_OUT or "terminal-tmux.txt", "w")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
end
vim.cmd("qa!")
