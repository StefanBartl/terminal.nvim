---@module 'terminal.status.exporters.tmux'
--- Publishes the status dataset to tmux as **pane options**, so `status-right`, `pane-border-format`
--- or `window-status-format` can show them with `#{@terminal_mode}` and friends.
---
--- One `set-option -p` per field, sent as a single tmux command line (commands joined with `;`):
---   `@terminal_mode`   Neovim mode code (`n`, `i`, `v`, `V`, `^V`, `t`, ...)
---   `@terminal_file`   file name
---   `@terminal_branch` git branch ("" when none)
---   `@terminal_diag`   `E2 W1` (errors / warnings; "" when none)
---   `@terminal_rec`    macro register being recorded ("" when none)
---   `@terminal_mod`    `+` when the buffer is modified, else ""
--- Values are sanitised by the dataset (no control characters). tmux expands `#{...}` inside a
--- format *value* only where the user's format asks for it; the values themselves are set with
--- `set-option`, never interpolated into a command string. A value that ends in `;` is escaped
--- (`backends.tmux.word`): tmux would otherwise read it as the end of the command.
---
--- Whose pane it is: the options belong to `$TMUX_PANE`, so only the Neovim that *owns* the pane
--- may write them. `available()` refuses a Neovim inside another Neovim's terminal (`$NVIM`), `ready()`
--- refuses one without an attached UI (a headless child), and `clear()` removes the options only
--- when this instance wrote them.
---@see terminal.backends.tmux
---@see terminal.core.status

local tmux_backend = require("terminal.backends.tmux")

local M = {}

M.name = "tmux"

--- Whether this instance wrote the pane options (and so has to remove them).
local owned = false

--- Runs a tmux command. A status publish blocks the editor for as long as tmux takes (it runs
--- from the debounced event), so a hung tmux is given two seconds, not the backend's three.
---@type fun(argv: string[]): Terminal.ExecResult
M.run = function(argv)
  return require("terminal.core.exec").run(argv, { timeout = 2000 })
end

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
  if vim.fn.has("win32") == 0 and vim.fn.executable("ps") == 1 then
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
  if env.NVIM ~= nil and env.NVIM ~= "" and M.nested(env.NVIM) then
    return false,
      "this Neovim runs inside another Neovim's terminal ($NVIM is set); the outer one owns the pane"
  end
  return true, nil
end

--- Only a Neovim with an attached UI shows anything to the pane's user; a headless one (a
--- script, `--headless "+Lazy! sync"`) leaves the pane's options alone.
---@return boolean
function M.ready()
  return #vim.api.nvim_list_uis() > 0
end

---@internal
---@param pane string
---@param fields table<string, string>
---@param unset boolean
---@return string[] argv
local function command(pane, fields, unset)
  local argv = { "tmux" }
  local names = vim.tbl_keys(fields)
  table.sort(names)
  for i, name in ipairs(names) do
    if i > 1 then
      argv[#argv + 1] = ";"
    end
    vim.list_extend(argv, { "set-option", "-p" })
    if unset then
      argv[#argv + 1] = "-u"
    end
    vim.list_extend(argv, { "-t", pane, name })
    if not unset then
      argv[#argv + 1] = tmux_backend.word(fields[name])
    end
  end
  return argv
end

--- The pane options for a decoded dataset.
---@param data table
---@return table<string, string>
function M.fields(data)
  local diag = {}
  if (data.e or 0) > 0 then
    diag[#diag + 1] = "E" .. data.e
  end
  if (data.w or 0) > 0 then
    diag[#diag + 1] = "W" .. data.w
  end
  return {
    ["@terminal_mode"] = tostring(data.mode or ""),
    ["@terminal_file"] = tostring(data.file or ""),
    ["@terminal_branch"] = tostring(data.branch or ""),
    ["@terminal_diag"] = table.concat(diag, " "),
    ["@terminal_rec"] = tostring(data.rec or ""),
    ["@terminal_mod"] = data.mod and "+" or "",
  }
end

--- What this exporter publishes, as one string: the delta gate compares this, so a change the pane
--- options do not carry (cwd, filetype, info and hint counts) costs no tmux process.
---@param data table
---@return string
function M.key(data)
  local fields = M.fields(data)
  local names = vim.tbl_keys(fields)
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    parts[#parts + 1] = fields[name]
  end
  -- NUL cannot occur in a value (the dataset is sanitised), so the parts cannot run together.
  return table.concat(parts, "\0")
end

---@param json string The encoded dataset
---@param data? table The same dataset, already decoded
---@return boolean ok
---@return string|nil err
function M.publish(json, data)
  local pane = vim.env.TMUX_PANE
  if data == nil then
    local ok, decoded = pcall(vim.json.decode, json)
    if not ok or type(decoded) ~= "table" then
      return false, "dataset is not JSON"
    end
    data = decoded
  end
  -- Set before the call: a chain that fails half-way has still written some of the options.
  owned = true
  local res = M.run(command(pane, M.fields(data), false))
  if res.code ~= 0 then
    return false, vim.trim(res.stderr)
  end
  return true, nil
end

--- Remove the options (this Neovim leaves the pane). Nothing to do when this instance never
--- wrote them.
---@return boolean ok
---@return string|nil err
function M.clear()
  if not owned then
    return true, nil
  end
  owned = false
  local pane = vim.env.TMUX_PANE
  local res = M.run(command(pane, M.fields({}), true))
  if res.code ~= 0 then
    return false, vim.trim(res.stderr)
  end
  return true, nil
end

M._command = command

return M
