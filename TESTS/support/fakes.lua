-- TESTS/support/fakes.lua -- fake `wezterm cli` and `tmux` for the specs: panes in memory, every
-- call recorded. Shared by the backend specs and the conformance suite.

local M = {}

--- A fake `wezterm cli`: keeps a list of panes, records every call.
---@return Terminal.WezTermRunner runner
---@return table state { calls, panes, active, stdin }
local function wezterm()
  local state =
    { calls = {}, panes = { ["7"] = { pane_id = 7, tab_id = 1 } }, active = "7", next_id = 8 }
  local function run(argv, opts)
    state.calls[#state.calls + 1] = { argv = vim.list_slice(argv, 3), stdin = opts and opts.stdin }
    local sub = argv[3]
    if sub == "split-pane" or sub == "spawn" then
      local id = tostring(state.next_id)
      state.next_id = state.next_id + 1
      state.panes[id] = { pane_id = tonumber(id), tab_id = sub == "spawn" and 2 or 1 }
      state.active = id
      return { code = 0, stdout = id .. "\n", stderr = "" }
    elseif sub == "list" then
      local out = {}
      for id, p in pairs(state.panes) do
        out[#out + 1] = vim.tbl_extend("force", p, { is_active = state.active == id })
      end
      return { code = 0, stdout = vim.json.encode(out), stderr = "" }
    elseif sub == "send-text" then
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "activate-pane" then
      local id = argv[5]
      if not state.panes[id] then
        return { code = 1, stdout = "", stderr = "pane " .. id .. " not found" }
      end
      state.active = id
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "kill-pane" then
      local id = argv[5]
      if not state.panes[id] then
        return { code = 1, stdout = "", stderr = "pane " .. id .. " not found" }
      end
      state.panes[id] = nil
      return { code = 0, stdout = "", stderr = "" }
    end
    return { code = 2, stdout = "", stderr = "unknown subcommand " .. tostring(sub) }
  end
  return run, state
end
M.wezterm = wezterm

--- A fake tmux: panes with ids `%N`, one active pane, every call recorded.
local function tmux()
  local state = {
    calls = {},
    panes = { ["%0"] = true },
    active = "%0",
    next_id = 1,
  }
  local function run(argv)
    state.calls[#state.calls + 1] = vim.list_slice(argv, 2)
    local sub = argv[2]
    if sub == "-L" then
      sub = argv[4]
    end
    if sub == "split-window" or sub == "new-window" then
      local id = "%" .. state.next_id
      state.next_id = state.next_id + 1
      state.panes[id] = true
      if not vim.tbl_contains(argv, "-d") then
        state.active = id
      end
      return { code = 0, stdout = id .. "\n", stderr = "" }
    elseif sub == "list-panes" then
      local lines = {}
      for id in pairs(state.panes) do
        lines[#lines + 1] = ("%s %d 1"):format(id, state.active == id and 1 or 0)
      end
      return { code = 0, stdout = table.concat(lines, "\n") .. "\n", stderr = "" }
    elseif sub == "select-pane" or sub == "select-window" then
      local target = argv[#argv]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      if sub == "select-pane" then
        state.active = target
      end
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "kill-pane" then
      local target = argv[#argv]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      state.panes[target] = nil
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "send-keys" then
      return { code = 0, stdout = "", stderr = "" }
    end
    return { code = 1, stdout = "", stderr = "unknown command " .. tostring(sub) }
  end
  return run, state
end
M.tmux = tmux

return M
