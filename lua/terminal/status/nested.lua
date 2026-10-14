---@module 'terminal.status.nested'
--- Is this Neovim running inside the terminal of another, still running Neovim? Such a Neovim stays
--- out of the multiplexer's status: the outer one owns the pane. The question is answered from the
--- environment variable `$NVIM` (the outer server's address), the outer server itself (its pid) and
--- the process tree. Used by the tmux exporter (`available`), kept apart from it because it is a
--- process-ancestry detector, not a tmux concern.
---@see terminal.status.exporters.tmux

local M = {}

--- Whether the Neovim at `address` (the value of `$NVIM`) is still running -- only that; whether
--- this Neovim is nested in it is `M.nested`. A tmux server that was started from a Neovim
--- terminal hands that variable to every pane for good, long after that Neovim exited: a dead
--- address is no outer Neovim.
---@type fun(address: string): boolean
M.alive = function(address)
  -- `--listen host:port` gives a TCP address (no path separator, ends in :<port>); everything
  -- else is a unix socket path or a Windows named pipe.
  local mode = (not address:find("[/\\]") and address:find(":%d+$")) and "tcp" or "pipe"
  local ok, channel = pcall(vim.fn.sockconnect, mode, address, { rpc = true })
  if not ok or type(channel) ~= "number" or channel <= 0 then
    return false
  end
  pcall(vim.fn.chanclose, channel)
  return true
end

--- The parent process id out of one line of `/proc/<pid>/stat`: `<pid> (<comm>) <state> <ppid> ...`.
--- The kernel ends `comm` at the LAST `)`, and `comm` can hold spaces and parentheses itself
--- (`x) R 1 (y`), so the pattern is greedy -- a balanced match would stop at the first one and read
--- a number out of the name.
---@param line string|nil
---@return integer|nil
function M.parse_stat(line)
  local ppid = line and line:match("^%d+ %(.*%) %S (%d+)")
  return ppid and tonumber(ppid) or nil
end

--- The parent process id of `pid`; nil when it cannot be read (no /proc and no `ps`).
---@type fun(pid: integer): integer|nil
M.parent_of = function(pid)
  local f = io.open(("/proc/%d/stat"):format(pid), "r")
  if f then
    local line = f:read("*l")
    f:close()
    local ppid = M.parse_stat(line)
    if ppid then
      return ppid
    end
  end
  -- Not on Windows: a `ps` there (Git Bash) numbers processes in its own namespace.
  if not require("lib.nvim.cross.platform.is_windows")() and vim.fn.executable("ps") == 1 then
    -- One second: `ps` answers at once, the limit only bounds a hang.
    local res = require("terminal.core.exec").run(
      { "ps", "-o", "ppid=", "-p", tostring(pid) },
      { timeout = 1000 }
    )
    local parent = res.code == 0 and tonumber(vim.trim(res.stdout)) or nil
    if parent then
      return parent
    end
  end
  return nil
end

--- Whether the process `pid` is an ancestor of this Neovim: true / false, nil when the chain
--- cannot be followed.
---@internal
---@param pid integer
---@return boolean|nil
local function is_ancestor(pid)
  local current = vim.uv.os_getpid()
  -- 64 levels: deeper than any real process chain, it only ends a loop in a broken parent table.
  for _ = 1, 64 do
    local parent = M.parent_of(current)
    if parent == nil then
      return nil
    end
    if parent == pid then
      return true
    end
    if parent <= 1 then
      return false
    end
    current = parent
  end
  return false
end

--- The process id of the Neovim server at `address`, asked of the server itself: nothing is
--- guessed from the address (a default servername is `<appname>.<pid>.<n>`, but a custom `--listen`
--- name or a TCP address can look like it or look like anything). Done by a child `nvim --server
--- <address> --remote-expr getpid()` with a timeout, never by an RPC call in this process: a
--- server that is busy (the outer Neovim sits in a blocking `:!`) must not freeze this one's start.
--- nil when it does not answer within 1.5 s: the limit bounds how long this start can wait, and
--- a server that stays silent is taken to own the pane anyway (`M.nested`).
---@type fun(address: string): integer|nil
M.server_pid = function(address)
  local res = require("terminal.core.exec").run({
    vim.v.progpath,
    -- `--headless`: without it a `--remote-expr` client prints nothing on Windows (and waits
    -- 1 s); `-u NONE -i NONE` keeps the client from loading a config and shada.
    "--headless",
    "-u",
    "NONE",
    "-i",
    "NONE",
    "--server",
    address,
    "--remote-expr",
    "getpid()",
  }, { timeout = 1500 })
  if res.code ~= 0 then
    return nil
  end
  return tonumber(vim.trim(res.stdout))
end

--- Whether this Neovim runs inside the terminal of the (running) Neovim at `address`: the one
--- `$NVIM` names. A Neovim in a pane of a tmux server that merely *was started* from that
--- terminal has the same `$NVIM` but is not a descendant of it -- it owns its pane. So a running
--- outer Neovim counts when it is an ancestor of this process (its pid asked of the server, the
--- process tree read from /proc or `ps`). When either cannot be found out -- the server does not
--- answer in time, no readable process tree (Windows) -- the outer Neovim is taken to own the pane
--- and this one stays out.
---@param address string
---@return boolean
function M.nested(address)
  if not M.alive(address) then
    return false
  end
  local pid = M.server_pid(address)
  if pid == nil then
    return true
  end
  local ancestor = is_ancestor(pid)
  if ancestor == nil then
    return true
  end
  return ancestor
end

return M
