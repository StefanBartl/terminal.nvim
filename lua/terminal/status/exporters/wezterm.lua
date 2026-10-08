---@module 'terminal.status.exporters.wezterm'
--- Publishes the status dataset to WezTerm as per-pane user variables (OSC 1337 `SetUserVar`).
---
--- The variables, read on the WezTerm side with `pane:get_user_vars()`:
---   `MUX_NVIM`    "1" while this Neovim runs in the pane, "" after it left
---   `MUX_PIPE`    this Neovim's RPC address (`vim.v.servername`), for control from outside
---   `MUX_STATUS`  the dataset as compact JSON (see `terminal.core.status`)
--- The names keep the `MUX_` prefix: they are part of the contract with the WezTerm config, not
--- of the plugin's name.
---
--- The channel is `nvim_ui_send` (measured, see docs/status.md#measured); under tmux the sequence
--- is wrapped for passthrough (`core/osc.lua`).
---@see terminal.core.status
---@see terminal.core.osc

local osc = require("terminal.core.osc")

local M = {}

M.name = "wezterm"

--- Whether this exporter can work here.
---@param env table<string, string|nil>
---@return boolean ok
---@return string|nil reason
function M.available(env)
  if env.WEZTERM_PANE == nil or env.WEZTERM_PANE == "" then
    return false, "not running inside WezTerm ($WEZTERM_PANE is not set)"
  end
  -- `nvim_ui_send` exists since Neovim 0.12; before that there is no way to write to the host
  -- terminal from the (embedded) Neovim server.
  if type(vim.api.nvim_ui_send) ~= "function" then
    return false, "nvim_ui_send is missing (the WezTerm status export needs Neovim 0.12+)"
  end
  return true, nil
end

--- Without an attached UI there is no terminal to write to (a headless run); that is the normal
--- state of a script, not a failure. The status goes out when a UI attaches (`UIEnter`).
---@return boolean
function M.ready()
  return #vim.api.nvim_list_uis() > 0
end

---@internal
---@param vars { [1]: string, [2]: string }[]
---@return boolean ok
---@return string|nil err
local function send(vars)
  if #vim.api.nvim_list_uis() == 0 then
    return false, "no UI attached"
  end
  local payload, err = osc.user_vars(vars, vim.env.TMUX ~= nil and vim.env.TMUX ~= "")
  if not payload then
    return false, err
  end
  -- ONE call: a redraw between the parts would show a half-updated state.
  local ok, serr = pcall(vim.api.nvim_ui_send, payload)
  if not ok then
    return false, tostring(serr)
  end
  return true, nil
end

--- Publish a dataset.
---@param json string The encoded dataset
---@return boolean ok
---@return string|nil err
function M.publish(json)
  return send({
    { "MUX_NVIM", "1" },
    { "MUX_PIPE", vim.v.servername or "" },
    { "MUX_STATUS", json },
  })
end

--- Tell WezTerm this pane no longer hosts a Neovim (empty values).
---@return boolean ok
---@return string|nil err
function M.clear()
  return send({ { "MUX_NVIM", "" }, { "MUX_PIPE", "" }, { "MUX_STATUS", "" } })
end

return M
