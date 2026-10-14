---@module 'terminal.core.errors'
--- How a failed multiplexer call is told to the user: one line, with a short hint for the failures
--- that are known to have an obvious cause. The program's complete output goes to the debug log
--- (WezTerm's "Error ... Caused by" chains run over many lines and would flood a notification).
---
--- The public contract stays what it was: errors are display strings (`nil, err` / `false, err`).
--- This module only decides what the string says.

local M = {}

--- Failures with an obvious cause: a plain (case-insensitive) fragment of the output, and what to
--- tell the user. The first match wins.
---@type { tool: string, fragment: string, hint: string }[]
local KNOWN = {
  { tool = "tmux", fragment = "no server running", hint = "start tmux, or run Neovim inside it" },
  { tool = "tmux", fragment = "error connecting to", hint = "the tmux server is not reachable" },
  { tool = "tmux", fragment = "can't find pane", hint = "the pane is gone" },
  { tool = "tmux", fragment = "can't find window", hint = "the window is gone" },
  { tool = "tmux", fragment = "can't find session", hint = "the session is gone" },
  {
    tool = "wezterm",
    fragment = "failed to connect",
    hint = "is WezTerm running? ($WEZTERM_UNIX_SOCKET)",
  },
  { tool = "wezterm", fragment = "not found", hint = "the pane is gone" },
  {
    tool = "wezterm",
    fragment = "no such file or directory",
    hint = "is the WezTerm GUI running?",
  },
}

--- Longest first line kept, in characters.
local MAX_LINE = 200

--- The first non-empty line of `text`, cut to `MAX_LINE`.
---@param text string
---@return string
local function first_line(text)
  for line in (text or ""):gmatch("[^\r\n]+") do
    local t = vim.trim(line)
    if t ~= "" then
      return #t > MAX_LINE and (t:sub(1, MAX_LINE) .. "...") or t
    end
  end
  return ""
end

--- The reason to show for a failed call: the first line of its output, plus a hint when the failure
--- is a known one. The complete output is logged at debug level.
---@param tool "tmux"|"wezterm"
---@param output string stderr (or stdout when stderr is empty)
---@return string reason ("no output" when there was none)
function M.reason(tool, output)
  output = vim.trim(output or "")
  if output == "" then
    return "no output"
  end
  local why = first_line(output)
  local lowered = output:lower()
  for _, known in ipairs(KNOWN) do
    if known.tool == tool and lowered:find(known.fragment, 1, true) then
      why = ("%s (%s)"):format(why, known.hint)
      break
    end
  end
  if output ~= why and output:find("[\r\n]") then
    pcall(function()
      require("terminal.notify").debug(("%s: %s"):format(tool, output))
    end)
  end
  return why
end

return M
