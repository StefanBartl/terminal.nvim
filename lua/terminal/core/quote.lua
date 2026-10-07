---@module 'terminal.core.quote'
--- Pure shell quoting for text that is typed into a terminal.
---
--- Anything that reaches a shell as one *line* must be quoted for **that** shell: a name with a
--- space, `;`, `$(...)`, a backtick or a quote would otherwise be interpreted instead of passed.
--- Three families are covered: POSIX (`sh`, `bash`, `zsh`, `fish` accepts the same single-quote
--- form), PowerShell (`powershell`, `pwsh`) and `cmd.exe`.
---
--- `argv_to_line` is the only entry the rest of the plugin uses; it never builds a line from an
--- unquoted string.

local M = {}

---@alias Terminal.ShellKind "posix"|"powershell"|"cmd"

--- Which quoting family a shell executable belongs to. Unknown shells are treated as POSIX.
---@param shell string|nil Executable name or path, e.g. `pwsh`, `C:\Windows\System32\cmd.exe`
---@return Terminal.ShellKind
function M.shell_kind(shell)
  local normalized = (shell or ""):gsub("\\", "/")
  local name = vim.fs.basename(normalized):lower():gsub("%.exe$", "")
  if name == "pwsh" or name == "powershell" then
    return "powershell"
  end
  if name == "cmd" then
    return "cmd"
  end
  return "posix"
end

---@internal
---@param s string
---@return string
local function posix(s)
  if s == "" then
    return "''"
  end
  -- Safe characters need no quotes; keeps simple commands readable in the terminal. A leading
  -- dash stays bare on purpose: quoting cannot stop a program from reading a word as an option
  -- (that needs `--`, the caller's business) and `-m` is how an option is written.
  if s:find("^[%w%._/:=@%%+,-]+$") then
    return s
  end
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

---@internal
---@param s string
---@return string
local function powershell(s)
  if s == "" then
    return "''"
  end
  if s:find("^[%w%._/:\\@%%+,-]+$") and not s:find("^-") then
    return s
  end
  -- Single quotes are literal in PowerShell; a quote inside is doubled.
  return "'" .. s:gsub("'", "''") .. "'"
end

---@internal
---@param s string
---@return string
local function cmd(s)
  if s == "" then
    return '""'
  end
  if s:find("^[%w%._/:\\@%+,-]+$") then
    return s
  end
  -- cmd.exe has no way to quote %VAR% safely inside a double-quoted word; `^` escapes the
  -- metacharacters outside quotes. Quote the word and double the quotes and carets.
  return '"' .. s:gsub('"', '""'):gsub("%%", "^%%") .. '"'
end

--- Quote one word for the given shell family.
---@param s string
---@param kind Terminal.ShellKind
---@return string
function M.word(s, kind)
  if kind == "powershell" then
    return powershell(s)
  elseif kind == "cmd" then
    return cmd(s)
  end
  return posix(s)
end

--- A command line for `argv`, every word quoted for the shell family.
---
--- PowerShell needs the call operator when the program word itself is quoted
--- (`& 'C:\Program Files\x.exe' ...`); it is added only then.
---@param argv string[] Non-empty; every element a string
---@param kind Terminal.ShellKind
---@return string|nil line
---@return string|nil err
function M.argv_to_line(argv, kind)
  if type(argv) ~= "table" or #argv == 0 then
    return nil, "empty command"
  end
  local words = {}
  for i, a in ipairs(argv) do
    if type(a) ~= "string" then
      return nil, ("argument %d is not a string"):format(i)
    end
    if a:find("[%z\r\n]") then
      return nil, ("argument %d contains a NUL, CR or LF"):format(i)
    end
    words[i] = M.word(a, kind)
  end
  local line = table.concat(words, " ")
  if kind == "powershell" and words[1]:sub(1, 1) == "'" then
    line = "& " .. line
  end
  return line, nil
end

return M
