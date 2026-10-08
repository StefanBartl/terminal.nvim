---@module 'terminal.status'
--- Keeps the surrounding terminal informed about this Neovim: builds the status dataset when
--- something it contains changes, and hands it to every exporter that fits the environment.
---
--- *When* it runs is deliberately narrow: only on events that can change a field (mode, buffer,
--- directory, diagnostics, macro recording, modified flag, focus), never per key press, always
--- debounced, and nothing is written when what an exporter publishes equals what it sent last.
--- An exporter that fails is switched off after one notice, not retried on every event -- but it
--- stays in the list, so its published state is still cleaned up when Neovim leaves.

local status = require("terminal.core.status")

local M = {}

---@class Terminal.StatusExporter
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field ready? fun(): boolean `false`: cannot publish right now (no UI attached); skipped without a notice, retried on the next event
---@field key? fun(data: Terminal.Status): string What the exporter actually publishes; the delta gate compares this (default: the whole JSON)
---@field publish fun(json: string, data?: Terminal.Status): boolean, string|nil
---@field clear fun(): boolean, string|nil

---@class Terminal.StatusRuntime
---@field exporters Terminal.StatusExporter[]
---@field off table<string, true> Exporters that failed once
---@field last table<string, string> Last published key per exporter
---@field debounce table|nil
---@field max_bytes integer
---@field oversize boolean A dataset over `max_bytes` was already reported

---@type Terminal.StatusRuntime
local runtime =
  { exporters = {}, off = {}, last = {}, debounce = nil, max_bytes = 1024, oversize = false }

---@internal
--- The exporters by name: the module that implements it, and the environment variable that says
--- its terminal is there. "auto" looks at the variable first, so the module -- and everything it
--- pulls in -- is loaded only where it can work (a Neovim in a plain terminal loads none).
---@type table<string, { module: string, signal: string }>
local EXPORTERS = {
  tmux = { module = "terminal.status.exporters.tmux", signal = "TMUX" },
  wezterm = { module = "terminal.status.exporters.wezterm", signal = "WEZTERM_PANE" },
}

---@internal
---@param text string
local function warn(text)
  vim.schedule(function()
    require("terminal.notify").warn(text)
  end)
end

--- Which exporters the config asks for, filtered by what the environment supports.
--- `export`: "auto" (every one whose environment signal is present), a name, a list of names,
--- or `false` (none).
---
--- "auto" also stays out of a Neovim that runs inside the terminal of another *running* Neovim
--- (`$NVIM` names a server that answers and is an ancestor of this process): it would write to the
--- very pane the outer one owns. A dead `$NVIM`, or a live one that is no ancestor (a tmux server
--- that was only started from a Neovim terminal), does not count. A name asks for the exporter
--- anyway.
---@param export string|string[]|boolean
---@param env table<string, string|nil>
---@return Terminal.StatusExporter[] chosen
---@return string[] notes Why a named exporter was not usable
function M.choose(export, env)
  local names
  local auto = export == "auto"
  if export == false then
    return {}, {}
  elseif auto then
    names = vim.tbl_keys(EXPORTERS)
    table.sort(names)
  elseif type(export) == "string" then
    names = { export }
  else
    names = export
  end
  local asked = env
  if not auto then
    asked = vim.tbl_extend("force", {}, env)
    asked.NVIM = nil
  end
  local chosen, notes = {}, {}
  for _, name in ipairs(names) do
    local known = EXPORTERS[name]
    if not known then
      notes[#notes + 1] = ("status exporter '%s' does not exist"):format(name)
    elseif auto and (asked[known.signal] == nil or asked[known.signal] == "") then
      -- "auto" skips an exporter whose terminal is not there without loading it
      goto continue
    else
      ---@type Terminal.StatusExporter
      local exporter = require(known.module)
      local ok, reason = exporter.available(asked)
      if ok then
        chosen[#chosen + 1] = exporter
      elseif not auto then
        notes[#notes + 1] = ("status exporter '%s' is not usable: %s"):format(name, reason or "?")
      end
    end
    ::continue::
  end
  return chosen, notes
end

--- Build the dataset now and publish it to every exporter whose published state differs.
---@return nil
function M.publish_now()
  if #runtime.exporters == 0 then
    return
  end
  local snapshot = require("terminal.status.collector").snapshot()
  local data = status.build(snapshot)
  local json, err = status.encode(data, runtime.max_bytes)
  if not json then
    -- Once, not on every event: a limit below the smallest possible dataset would otherwise
    -- warn on every mode change.
    if not runtime.oversize then
      runtime.oversize = true
      warn("status: " .. err)
    end
    return
  end
  runtime.oversize = false
  for _, exporter in ipairs(runtime.exporters) do
    if not runtime.off[exporter.name] and (exporter.ready == nil or exporter.ready()) then
      local key = exporter.key and exporter.key(data) or json
      if runtime.last[exporter.name] ~= key then
        local ok, perr = exporter.publish(json, data)
        if ok then
          runtime.last[exporter.name] = key
        else
          runtime.off[exporter.name] = true
          warn(("status exporter '%s' switched off: %s"):format(exporter.name, perr or "?"))
        end
      end
    end
  end
end

--- Tell every exporter this Neovim is leaving (or status export was switched off). Also those
--- that failed: whatever they published before is still there.
---@return nil
function M.clear()
  if runtime.debounce then
    runtime.debounce.cancel()
  end
  for _, exporter in ipairs(runtime.exporters) do
    local ok, cleared, cerr = pcall(exporter.clear)
    if not ok or cleared == false then
      warn(("status exporter '%s' could not clear: %s"):format(exporter.name, cerr or cleared))
    end
  end
  runtime.last = {}
end

---@internal
local EVENTS = {
  "ModeChanged",
  "BufEnter",
  "BufFilePost",
  "BufModifiedSet",
  "DirChanged",
  "DiagnosticChanged",
  "RecordingEnter",
  "RecordingLeave",
  "FocusGained",
  "WinEnter",
}

--- Start (or restart) status export according to `cfg.status`.
---@param cfg Terminal.Config
---@param env? table<string, string|nil> Environment (default: the process's)
---@return nil
function M.setup(cfg, env)
  M.clear()
  local group = vim.api.nvim_create_augroup("terminal.status", { clear = true })
  runtime.exporters = {}
  runtime.off = {}
  runtime.oversize = false
  if not cfg.status.enable then
    return
  end

  env = env
    or {
      WEZTERM_PANE = vim.env.WEZTERM_PANE,
      TMUX = vim.env.TMUX,
      TMUX_PANE = vim.env.TMUX_PANE,
      NVIM = vim.env.NVIM,
    }
  local chosen, notes = M.choose(cfg.status.export, env)
  for _, note in ipairs(notes) do
    warn(note)
  end
  runtime.exporters = chosen
  runtime.max_bytes = cfg.status.max_bytes
  if #chosen == 0 then
    return
  end

  runtime.debounce = require("lib.nvim.debounce").new(M.publish_now, cfg.status.debounce_ms)
  vim.api.nvim_create_autocmd(EVENTS, {
    group = group,
    callback = function()
      runtime.debounce.call()
    end,
    desc = "terminal.nvim: publish the status dataset",
  })
  -- A UI that attaches (after startup: a GUI client, `:connect`, a new WezTerm pane after
  -- `:detach`) is a new terminal that has seen nothing yet: what could not be published without
  -- one goes out now, and so does what was published to the UI before it -- the delta gate must
  -- not hold it back.
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    callback = function()
      runtime.last = {}
      runtime.debounce.call()
    end,
    desc = "terminal.nvim: send the status to a newly attached UI",
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = M.clear,
    desc = "terminal.nvim: clear the published status",
  })
  -- First publication once the UI is up (setup() may run before it).
  if vim.v.vim_did_enter == 1 then
    runtime.debounce.call()
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function()
        runtime.debounce.call()
      end,
    })
  end
end

--- The exporters in use, for health checks.
---@return string[]
function M.active()
  local names = {}
  for _, e in ipairs(runtime.exporters) do
    if not runtime.off[e.name] then
      names[#names + 1] = e.name
    end
  end
  return names
end

return M
