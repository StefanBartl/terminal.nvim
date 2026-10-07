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
---@field mode string `nvim_get_mode().mode`, e.g. "n", "i", "V", "\22", "t"
---@field file string Buffer name (may be a full path or "")
---@field buftype? string
---@field cwd string
---@field branch? string|nil
---@field diag? { error?: integer, warn?: integer, info?: integer, hint?: integer }
---@field recording? string Register being recorded into, "" when none
---@field modified? boolean
---@field filetype? string
---@field pid? integer

---@class Terminal.Status
---@field v integer Schema version
---@field pid integer|nil
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
---@param n any
---@return integer
local function count(n)
  if type(n) ~= "number" or n < 0 or n ~= n then
    return 0
  end
  return math.min(math.floor(n), 99999)
end

---@internal
--- Last path component, for both separators.
---@param path string
---@return string
local function basename(path)
  local p = path:gsub("[/\\]+$", "")
  return p:match("([^/\\]*)$") or p
end

--- Build the dataset from an editor snapshot.
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
    mode = osc.sanitize(snap.mode or "n", 4),
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

--- Whether two datasets say the same thing.
---@param a Terminal.Status|nil
---@param b Terminal.Status|nil
---@return boolean
function M.equal(a, b)
  return vim.deep_equal(a, b)
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
