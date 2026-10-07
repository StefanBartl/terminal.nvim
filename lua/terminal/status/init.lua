---@module 'terminal.status'
--- Keeps the surrounding terminal informed about this Neovim: builds the status dataset when
--- something it contains changes, and hands it to every exporter that fits the environment.
---
--- *When* it runs is deliberately narrow: only on events that can change a field (mode, buffer,
--- directory, diagnostics, macro recording, modified flag, focus), never per key press, always
--- debounced, and nothing is written when the dataset equals the one sent last. An exporter that
--- fails is switched off after one notice, not retried on every event.

local status = require("terminal.core.status")

local M = {}

---@class Terminal.StatusExporter
---@field name string
---@field available fun(env: table<string, string|nil>): boolean, string|nil
---@field publish fun(json: string): boolean, string|nil
---@field clear fun(): boolean, string|nil

---@class Terminal.StatusRuntime
---@field exporters Terminal.StatusExporter[]
---@field last table<string, string> Last JSON per exporter
---@field debounce table|nil
---@field max_bytes integer

---@type Terminal.StatusRuntime
local runtime = { exporters = {}, last = {}, debounce = nil, max_bytes = 1024 }

---@internal
---@type table<string, fun(): Terminal.StatusExporter>
local EXPORTERS = {
  wezterm = function()
    return (require("terminal.status.exporters.wezterm"))
  end,
}

--- Which exporters the config asks for, filtered by what the environment supports.
--- `export`: "auto" (every one whose environment signal is present), a name, a list of names,
--- or `false` (none).
---@param export string|string[]|boolean
---@param env table<string, string|nil>
---@return Terminal.StatusExporter[] chosen
---@return string[] notes Why a named exporter was not usable
function M.choose(export, env)
  local names
  if export == false then
    return {}, {}
  elseif export == "auto" or export == true then
    names = vim.tbl_keys(EXPORTERS)
    table.sort(names)
  elseif type(export) == "string" then
    names = { export }
  else
    names = export
  end
  local chosen, notes = {}, {}
  for _, name in ipairs(names) do
    local make = EXPORTERS[name]
    if not make then
      notes[#notes + 1] = ("status exporter '%s' does not exist"):format(name)
    else
      local exporter = make()
      local ok, reason = exporter.available(env)
      if ok then
        chosen[#chosen + 1] = exporter
      elseif export ~= "auto" and export ~= true then
        notes[#notes + 1] = ("status exporter '%s' is not usable: %s"):format(name, reason or "?")
      end
    end
  end
  return chosen, notes
end

--- Build the dataset now and publish it to every exporter whose last value differs.
---@return nil
function M.publish_now()
  if #runtime.exporters == 0 then
    return
  end
  local snapshot = require("terminal.status.collector").snapshot()
  local json, err = status.encode(status.build(snapshot), runtime.max_bytes)
  if not json then
    vim.schedule(function()
      require("lib.nvim.notify").create("[terminal]").warn("status: " .. err)
    end)
    return
  end
  for i = #runtime.exporters, 1, -1 do
    local exporter = runtime.exporters[i]
    if runtime.last[exporter.name] ~= json then
      local ok, perr = exporter.publish(json)
      if ok then
        runtime.last[exporter.name] = json
      else
        table.remove(runtime.exporters, i)
        vim.schedule(function()
          require("lib.nvim.notify")
            .create("[terminal]")
            .warn(("status exporter '%s' switched off: %s"):format(exporter.name, perr or "?"))
        end)
      end
    end
  end
end

--- Tell every exporter this Neovim is leaving (or status export was switched off).
---@return nil
function M.clear()
  if runtime.debounce then
    runtime.debounce.cancel()
  end
  for _, exporter in ipairs(runtime.exporters) do
    pcall(exporter.clear)
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
  if not cfg.status.enable then
    return
  end

  env = env or { WEZTERM_PANE = vim.env.WEZTERM_PANE, TMUX = vim.env.TMUX }
  local chosen, notes = M.choose(cfg.status.export, env)
  if #notes > 0 then
    vim.schedule(function()
      local n = require("lib.nvim.notify").create("[terminal]")
      for _, note in ipairs(notes) do
        n.warn(note)
      end
    end)
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
  return vim.tbl_map(function(e)
    return e.name
  end, runtime.exporters)
end

return M
