-- TESTS/live/nested.lua -- the tmux status exporter's ownership test against a REAL process tree.
--
--   SMOKE_OUT=/tmp/terminal-nested.txt nvim --headless -u NONE -l TESTS/live/nested.lua
--
-- Linux / macOS only (the process tree is read from /proc or `ps`; tmux does not run on Windows):
-- on Windows it reports a skip and "RESULT ok". tmux must be installed.
--
-- This Neovim plays the OUTER one. It starts two inner Neovims that inherit its `$NVIM`:
--   * one in its own `:terminal` (what `git commit` does when it opens $EDITOR) -- it is NESTED,
--     the exporter must keep out of the pane the outer owns;
--   * one in a pane of a tmux server that was STARTED from this terminal -- the server hands this
--     `$NVIM` to every pane for good, but that Neovim owns its pane, the exporter must work.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/nested%.lua$")
vim.opt.rtp:prepend(root)
local lib = vim.env.LIB_NVIM_DIR or (root .. "/../lib.nvim")
vim.opt.rtp:append(lib)

local out, failed = {}, false
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

local function finish()
  out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
  local f = io.open(vim.env.SMOKE_OUT or "terminal-nested.txt", "w")
  if f then
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
  end
  vim.cmd("qa!")
end

if vim.fn.has("win32") == 1 then
  out[#out + 1] = "skip (needs /proc or ps and tmux: Linux / macOS)"
  return finish()
end
if vim.fn.executable("tmux") ~= 1 then
  check("tmux is installed", false)
  return finish()
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local inner = dir .. "/inner.lua"
local f = assert(io.open(inner, "w"))
f:write(([[
vim.opt.rtp:prepend(%q)
vim.opt.rtp:append(%q)
local e = require("terminal.status.exporters.tmux")
local env = { TMUX = vim.env.TMUX or "x", TMUX_PANE = vim.env.TMUX_PANE or "%%0", NVIM = vim.env.NVIM }
local available, why = e.available(env)
local o = assert(io.open(vim.env.RESULT_FILE, "w"))
o:write(("%%s|%%s|%%s"):format(tostring(e.alive(vim.env.NVIM or "")), tostring(available), tostring(why)))
o:close()
vim.cmd("qa!")
]]):format(root, lib))
f:close()

local function result(path)
  local r = io.open(path, "r")
  if not r then
    return nil
  end
  local text = r:read("*a")
  r:close()
  return text
end

local function run_in_terminal(cmd, env)
  vim.cmd("enew!")
  local job = vim.fn.jobstart(cmd, { term = true, env = env })
  -- vim.wait keeps the event loop running, so THIS Neovim still answers the inner one's question
  -- ("what is your pid?"); a blocking jobwait would not.
  vim.wait(20000, function()
    return vim.fn.jobwait({ job }, 0)[1] ~= -1
  end, 50)
end

local nested_file = dir .. "/nested.txt"
run_in_terminal(
  { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", inner },
  { RESULT_FILE = nested_file }
)
local nested = result(nested_file)
check("the inner Neovim ran in a terminal of this one", nested ~= nil, nested)
check(
  "it sees this Neovim alive and is refused (nested)",
  nested ~= nil and nested:find("^true|false|") ~= nil,
  nested
)

local pane_file = dir .. "/pane.txt"
local socket = "terminal-nvim-nested-" .. vim.uv.os_getpid()
local script = ("tmux -L %s -f /dev/null new-session -d '%s --headless -u NONE -i NONE -l %s'; "):format(
  socket,
  vim.v.progpath,
  inner
) .. ("i=0; while [ ! -s %s ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; tmux -L %s kill-server"):format(
  pane_file,
  socket
)
run_in_terminal({ "sh", "-c", script }, { RESULT_FILE = pane_file })
local pane = result(pane_file)
check(
  "the inner Neovim ran in a pane of a tmux server started from this terminal",
  pane ~= nil,
  pane
)
check(
  "it shares $NVIM (this Neovim is alive) but is NOT nested: the exporter is available",
  pane ~= nil and pane:find("^true|true|nil$") ~= nil,
  pane
)

-- A custom --listen name that merely LOOKS like "<appname>.<pid>.<n>" must not fool the pid lookup:
-- the pid is asked of the server, not read from its name.
local custom = dir .. "/custom.5.1"
vim.fn.serverstart(custom)
local custom_file = dir .. "/custom.txt"
run_in_terminal(
  { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", inner },
  { RESULT_FILE = custom_file, NVIM = custom }
)
local custom_result = result(custom_file)
check(
  "a custom listen name that looks like <appname>.<pid>.<n> does not fool it (still nested)",
  custom_result ~= nil and custom_result:find("^true|false|") ~= nil,
  custom_result
)

vim.fn.delete(dir, "rf")
finish()
