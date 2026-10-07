---@module 'terminal.status.exporters.tmux'
--- Publishes the status dataset to tmux as **pane options**, so `status-right`, `pane-border-format`
--- or `window-status-format` can show them with `#{@terminal_mode}` and friends.
---
--- One `set-option -p` per field, sent as a single tmux command line (commands joined with `;`):
---   `@terminal_mode`   Neovim mode code (`n`, `i`, `v`, `V`, `t`, ...)
---   `@terminal_file`   file name
---   `@terminal_branch` git branch ("" when none)
---   `@terminal_diag`   `E2 W1` (errors / warnings; "" when none)
---   `@terminal_rec`    macro register being recorded ("" when none)
---   `@terminal_mod`    `+` when the buffer is modified, else ""
--- Values are sanitised by the dataset (no control characters). tmux expands `#{...}` inside a
--- format *value* only where the user's format asks for it; the values themselves are set with
--- `set-option`, never interpolated into a command string.

local M = {}

M.name = "tmux"

---@type fun(argv: string[]): { code: integer, stderr: string }
M.run = function(argv)
  local ok, res = pcall(function()
    return vim.system(argv, { text = true, timeout = 2000 }):wait()
  end)
  if not ok then
    return { code = 127, stderr = tostring(res) }
  end
  return { code = res.code, stderr = res.stderr or "" }
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
  return true, nil
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
      argv[#argv + 1] = fields[name]
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

---@param json string The encoded dataset
---@return boolean ok
---@return string|nil err
function M.publish(json)
  local pane = vim.env.TMUX_PANE
  local ok, data = pcall(vim.json.decode, json)
  if not ok or type(data) ~= "table" then
    return false, "dataset is not JSON"
  end
  local res = M.run(command(pane, M.fields(data), false))
  if res.code ~= 0 then
    return false, vim.trim(res.stderr)
  end
  return true, nil
end

--- Remove the options (this Neovim leaves the pane).
---@return boolean ok
---@return string|nil err
function M.clear()
  local pane = vim.env.TMUX_PANE
  local res = M.run(command(pane, M.fields({}), true))
  if res.code ~= 0 then
    return false, vim.trim(res.stderr)
  end
  return true, nil
end

M._command = command

return M
