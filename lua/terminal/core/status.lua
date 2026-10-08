---@module 'terminal.core.status'
--- The status dataset terminal.nvim publishes to the surrounding terminal / multiplexer: a small,
--- versioned table of *raw values* (mode, file, branch, diagnostics, ...). Rendering -- icons,
--- colours, which segment goes where -- belongs to the receiving side (the WezTerm config, the
--- tmux status line) and to ui.nvim for the in-editor statusline; this module never formats.
---
--- Pure: no `vim.*` state is read here (the snapshot is passed in), so every rule is testable.
--- Every string in the result is sanitised: file names, branch names and directory names are
--- attacker-controlled text that ends up in a terminal's tab title.

local osc = require("terminal.core.osc")

local M = {}

--- Schema version. A receiver ignores fields it does not know and refuses a higher version.
M.VERSION = 1

---@class Terminal.StatusSnapshot
---@field mode string `nvim_get_mode().mode`, e.g. "n", "i", "V", "\22", "t" (published as "^V" for "\22")
---@field file string Buffer name (may be a full path or "")
---@field buftype? string
---@field cwd string
---@field branch? string
---@field diag? Terminal.DiagCounts
---@field recording? string Register being recorded into, "" when none
---@field modified? boolean
---@field filetype? string
---@field pid? integer

---@class Terminal.Status
---@field v integer Schema version
---@field pid? integer
---@field mode string
---@field file string
---@field ft string
---@field cwd string
---@field branch string
---@field e integer Error count
---@field w integer Warning count
---@field i integer Info count
---@field h integer Hint count
---@field rec string
---@field mod boolean

---@internal
--- Blockwise Visual (CTRL-V, byte 22) and Select-block (CTRL-S, byte 19) are control characters in
--- `nvim_get_mode().mode`, so the sanitiser would turn them into `?`. They are spelled out as
--- `^V` / `^S` instead (`no^V` is operator-pending blockwise); every other mode code is plain
--- ASCII already.
---@type table<string, string>
local MODE_CODES = { ["\22"] = "^V", ["\19"] = "^S" }

---@internal
---@param mode string
---@return string
local function mode_code(mode)
  return (mode:gsub("[\19\22]", MODE_CODES))
end

---@internal
--- A diagnostic count as a non-negative integer, capped at 99999 (five digits) so that a count
--- can never grow the dataset.
---@param n any
---@return integer
local function count(n)
  if type(n) ~= "number" or n < 0 or n ~= n then
    return 0
  end
  return math.min(math.floor(n), 99999)
end

---@internal
--- Last path component, for both separators. Scanned from the end instead of matched with a
--- pattern: the buffer name is unbounded input and a `[/\\]+$` pattern is quadratic on a
--- long run of separators (40,000 of them took 5 s on every status event).
---@param path string
---@return string
local function basename(path)
  local last = #path
  while last > 0 and (path:byte(last) == 47 or path:byte(last) == 92) do
    last = last - 1
  end
  local first = last
  while first > 0 and path:byte(first) ~= 47 and path:byte(first) ~= 92 do
    first = first - 1
  end
  return path:sub(first + 1, last)
end

--- Build the dataset from an editor snapshot.
---
--- Length caps of the free-text fields, in bytes (`osc.sanitize` cuts on a character boundary).
--- These values are attacker-controlled text that ends up in a tab title or a status line, so
--- each field has an upper bound of its own (SEC-32):
---   mode    4    the longest mode code is `no^V` (operator-pending blockwise), see `mode_code`
---   file    120  the last path component only, for a tab title: a longer name is cut
---   ft      40   a filetype is a short identifier
---   cwd     200  a project directory; the widest field, so `encode` shortens it first
---   branch  80   room for a long feature-branch name
---   rec     4    a register is one character, and 4 bytes hold any UTF-8 character
---@param snap Terminal.StatusSnapshot
---@return Terminal.Status
function M.build(snap)
  local file = snap.file or ""
  local name
  if snap.buftype == "terminal" then
    name = "terminal"
  elseif file == "" then
    name = "[No Name]"
  else
    name = basename(file)
  end
  local diag = snap.diag or {}
  return {
    v = M.VERSION,
    pid = snap.pid,
    mode = osc.sanitize(mode_code(tostring(snap.mode or "n")), 4),
    file = osc.sanitize(name, 120),
    ft = osc.sanitize(snap.filetype or "", 40),
    cwd = osc.sanitize(snap.cwd or "", 200),
    branch = osc.sanitize(snap.branch or "", 80),
    e = count(diag.error),
    w = count(diag.warn),
    i = count(diag.info),
    h = count(diag.hint),
    rec = osc.sanitize(snap.recording or "", 4),
    mod = snap.modified == true,
  }
end

--- The wire form: compact JSON, within `max_bytes`. When it is too long the longest free-text
--- fields are shortened step by step (cwd, then file, then branch); a dataset that still does
--- not fit is refused rather than sent truncated mid-field.
---@param status Terminal.Status
---@param max_bytes? integer Default 1024
---@return string|nil json
---@return string|nil err
function M.encode(status, max_bytes)
  max_bytes = max_bytes or 1024
  local s = vim.deepcopy(status)
  -- Bytes each field is cut to, step by step, until the JSON fits (the plain caps: see `build`).
  -- A field goes through all its steps before the next is touched, so the order is the priority:
  -- `cwd` first (the widest field; its last step empties it), then `file`, then `branch`. The
  -- file name is what a tab title shows, so it keeps the most; a branch name is short anyway.
  local limits = { cwd = { 80, 40, 0 }, file = { 60, 30, 12 }, branch = { 40, 20, 8 } }
  local json = vim.json.encode(s)
  for _, field in ipairs({ "cwd", "file", "branch" }) do
    for _, limit in ipairs(limits[field]) do
      if #json <= max_bytes then
        return json, nil
      end
      s[field] = osc.sanitize(s[field], limit)
      json = vim.json.encode(s)
    end
  end
  if #json <= max_bytes then
    return json, nil
  end
  return nil, ("status dataset is %d bytes, over the limit of %d"):format(#json, max_bytes)
end

return M
