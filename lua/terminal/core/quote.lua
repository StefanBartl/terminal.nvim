---@module 'terminal.core.quote'
--- Pure shell quoting for text that is typed into a terminal.
---
--- Anything that reaches a shell as one *line* must be quoted for **that** shell: a name with a
--- space, `;`, `$(...)`, a backtick or a quote would otherwise be interpreted instead of passed.
--- Three families are covered: POSIX (`sh`, `bash`, `zsh`; `fish` accepts the same single-quote
--- form), PowerShell (`powershell`, `pwsh`) and `cmd.exe`.
---
--- `argv_to_line` is the only entry the rest of the plugin uses; it never builds a line from an
--- unquoted string. A word that cannot be represented safely for the shell is **refused**
--- (`nil, err`), never guessed at.

local M = {}

---@alias Terminal.ShellKind "posix"|"powershell"|"cmd"

--- Which quoting family a shell belongs to. Unknown shells are treated as POSIX.
---
--- Takes an executable name, a path (spaces allowed) or a command string with arguments
--- (`pwsh -NoLogo`): the family is found by looking for the shell's name as a whole path
--- component or word.
---@param shell string|nil
---@return Terminal.ShellKind
function M.shell_kind(shell)
  local normalized = (shell or ""):gsub("\\", "/"):lower()
  local padded = " " .. normalized .. " "
  if padded:find('[/%s"]pwsh[%.%s"]') or padded:find('[/%s"]powershell[%.%s"]') then
    return "powershell"
  end
  if padded:find('[/%s"]cmd[%.%s"]') then
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
--- PowerShell treats the typographic single quotes U+2018..U+201B (UTF-8 below) as quote
--- characters too: one inside a '...' string would end it. Each is doubled like the ASCII one.
local CURLY = { "\226\128\152", "\226\128\153", "\226\128\154", "\226\128\155" }

---@internal
---@param s string
---@return string
local function powershell(s)
  if s == "" then
    return "''"
  end
  -- A deliberately small bare-word set: `@` starts splatting, `,` builds an array, `%` and `+`
  -- can read as an alias or operator, `=` and `$` have meaning. A leading dash stays bare (an
  -- option is written that way).
  if s:find("^[%w%._/:\\-]+$") then
    return s
  end
  local out = s:gsub("'", "''")
  for _, q in ipairs(CURLY) do
    out = out:gsub(q, q .. q)
  end
  return "'" .. out .. "'"
end

---@internal
--- cmd.exe has no way to quote `%VAR%` inside a word (`^` is a literal inside double quotes), so
--- a word containing `%` is refused. A run of backslashes before the closing quote is doubled
--- (otherwise the last one escapes the quote for the C runtime).
---@param s string
---@return string|nil
---@return string|nil err
local function cmd(s)
  if s == "" then
    return '""', nil
  end
  if s:find("%%") then
    return nil, "cmd.exe cannot quote a word containing '%'"
  end
  if s:find("^[%w%._/:\\@+,-]+$") then
    return s, nil
  end
  local body = s:gsub('"', '""')
  local trailing = body:match("(\\+)$")
  if trailing then
    body = body .. trailing
  end
  return '"' .. body .. '"', nil
end

--- Quote one word for the given shell family.
---@param s string
---@param kind Terminal.ShellKind
---@return string|nil word
---@return string|nil err Set when the word cannot be represented safely for this shell
function M.word(s, kind)
  if kind == "powershell" then
    return powershell(s), nil
  elseif kind == "cmd" then
    return cmd(s)
  end
  return posix(s), nil
end

--- A command line for `argv`, every word quoted for the shell family.
---
--- PowerShell needs the call operator when the program word itself is quoted
--- (`& 'C:\Program Files\x.exe' ...`); it is added only then. Control characters (line breaks,
--- NUL, ESC, ...) are refused: a line break would end the command line, the others would be
--- interpreted by the terminal's line editor. Tab is allowed.
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
    if a:find("[%z\1-\8\10-\31\127]") then
      return nil, ("argument %d contains a control character (line break, NUL, ESC, ...)"):format(i)
    end
    local w, err = M.word(a, kind)
    if not w then
      return nil, ("argument %d: %s"):format(i, err)
    end
    words[i] = w
  end
  local line = table.concat(words, " ")
  if kind == "powershell" and words[1]:sub(1, 1) == "'" then
    line = "& " .. line
  end
  return line, nil
end

return M
