---@module 'terminal.cheatsheet.detect'
--- Which cheatsheet belongs to a shell. Pure: it reads a program name and nothing else, so every
--- rule is testable without a terminal.
---
--- The key is the name of the sheet file (`bash`, `powershell`, ...). A shell without a sheet of its
--- own is answered by a related one (`zsh` and `sh` by `bash`) and, last, by `common`, which holds
--- what is the same everywhere.

local M = {}

--- The sheet that is used last, and the key of "no shell is known".
M.COMMON = "common"

---@internal
--- Program name (without directory and `.exe`, lower case) -> sheet key.
---@type table<string, string>
local BY_PROGRAM = {
  pwsh = "powershell",
  powershell = "powershell",
  cmd = "cmd",
  fish = "fish",
  zsh = "zsh",
  bash = "bash",
  sh = "bash",
  dash = "bash",
  ash = "bash",
  ksh = "bash",
}

---@internal
--- Keys that are answered by another sheet when they have none of their own.
---@type table<string, string>
local RELATED = { zsh = "bash" }

--- The program name of a shell command: the last path component without `.exe`, lower case.
---@param exe string|nil
---@return string
function M.program(exe)
  if type(exe) ~= "string" then
    return ""
  end
  local name = exe:gsub("\\", "/"):match("([^/]*)$") or ""
  return (name:gsub("%.[eE][xX][eE]$", ""):lower())
end

--- The sheet key for a shell executable (`C:\Program Files\Git\bin\bash.exe` -> `bash`). A program
--- that is not a known shell (`wsl.exe`, `nu`) gives `common`.
---@param exe string|nil
---@return string
function M.detect(exe)
  return BY_PROGRAM[M.program(exe)] or M.COMMON
end

--- Which sheet to use for a terminal. The configured shell wins, then what the terminal runs.
---
--- A multiplexer pane runs the multiplexer's own shell, which is not known here: `common`.
---@param opts { explicit?: string, backend?: string, cmd?: string|string[], shell?: string }
--- `explicit`: `cheatsheet.shell` or the argument of the command; `backend`/`cmd`: the terminal
--- the sheet is for (nil when the cursor is not in one); `shell`: the shell terminals run.
---@return string key
function M.key_for(opts)
  if type(opts.explicit) == "string" and opts.explicit ~= "" then
    return opts.explicit:lower()
  end
  if opts.backend ~= nil and opts.backend ~= "native" then
    return M.COMMON
  end
  local cmd = opts.cmd
  if type(cmd) == "table" then
    return M.detect(cmd[1])
  elseif type(cmd) == "string" and cmd ~= "" then
    return M.detect(cmd:match('^%s*"([^"]+)"') or cmd:match("^%s*(%S+)"))
  end
  return M.detect(opts.shell)
end

--- The keys to try for `key`, in order, ending in `common`.
---@param key string
---@return string[]
function M.candidates(key)
  local out = { key }
  if RELATED[key] then
    out[#out + 1] = RELATED[key]
  end
  if key ~= M.COMMON then
    out[#out + 1] = M.COMMON
  end
  return out
end

return M
