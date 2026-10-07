-- TESTS/support/fakes.lua -- fake `wezterm cli` and `tmux` for the specs: panes in memory, every
-- call recorded. Shared by the backend specs and the conformance suite.

local M = {}

--- A fake `wezterm cli`: keeps a list of panes, records every call.
---
--- Like the real one it has tabs: `is_active` in `list` means "the active pane of ITS tab" (so a
--- pane in a tab nobody looks at is active too), and only `list-clients` says which pane has the
--- user's focus (`state.active`). Activating a pane also brings its tab to the front.
---@return Terminal.WezTermRunner runner
---@return table state { calls, panes, active, tab_active, stdin }
local function wezterm()
  local state = {
    calls = {},
    panes = { ["7"] = { pane_id = 7, tab_id = 1 } },
    active = "7",
    tab_active = { [1] = "7" },
    next_id = 8,
  }
  local function run(argv, opts)
    state.calls[#state.calls + 1] = { argv = vim.list_slice(argv, 3), stdin = opts and opts.stdin }
    local sub = argv[3]
    if sub == "split-pane" or sub == "spawn" then
      local id = tostring(state.next_id)
      state.next_id = state.next_id + 1
      local tab = sub == "spawn" and 2 or 1
      state.panes[id] = { pane_id = tonumber(id), tab_id = tab }
      state.tab_active[tab] = id
      state.active = id
      return { code = 0, stdout = id .. "\n", stderr = "" }
    elseif sub == "list" then
      if state.list_fails then
        return { code = 124, stdout = "", stderr = "timed out" }
      end
      local out = {}
      for id, p in pairs(state.panes) do
        out[#out + 1] = vim.tbl_extend("force", p, { is_active = state.tab_active[p.tab_id] == id })
      end
      return { code = 0, stdout = vim.json.encode(out), stderr = "" }
    elseif sub == "list-clients" then
      return {
        code = 0,
        stdout = vim.json.encode({ { focused_pane_id = tonumber(state.active) } }),
        stderr = "",
      }
    elseif sub == "get-text" then
      local id = argv[5]
      if not state.panes[id] then
        return { code = 1, stdout = "", stderr = "pane " .. id .. " not found" }
      end
      return { code = 0, stdout = state.text or "", stderr = "" }
    elseif sub == "send-text" then
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "activate-pane" then
      local id = argv[5]
      if not state.panes[id] then
        return { code = 1, stdout = "", stderr = "pane " .. id .. " not found" }
      end
      state.active = id
      state.tab_active[state.panes[id].tab_id] = id
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "kill-pane" then
      local id = argv[5]
      if not state.panes[id] then
        return { code = 1, stdout = "", stderr = "pane " .. id .. " not found" }
      end
      if state.kill_fails then
        return { code = 1, stdout = "", stderr = "cannot kill" }
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
---
--- Arguments are read the way tmux reads them: a lone `;` separates commands, and an argument that
--- ends in `;` ends its command (`a\;` stays `a;`), so a word that was not escaped is cut or starts
--- another command here too. `state.executed` lists every command that ran (after that parsing);
--- `state.keys` collects the text every `send-keys` received.
local function tmux()
  local state = {
    calls = {},
    panes = { ["%0"] = true },
    active = "%0",
    next_id = 1,
    keys = {},
    executed = {},
    version = "tmux 3.7c",
  }

  ---@param cmd string[] One command: name first
  local function exec(cmd)
    state.executed[#state.executed + 1] = cmd
    local sub = cmd[1]
    if sub == "-V" then
      return { code = 0, stdout = state.version .. "\n", stderr = "" }
    elseif sub == "split-window" or sub == "new-window" then
      local id = "%" .. state.next_id
      state.next_id = state.next_id + 1
      state.panes[id] = true
      if not vim.tbl_contains(cmd, "-d") then
        state.active = id
      end
      return { code = 0, stdout = id .. "\n", stderr = "" }
    elseif sub == "list-panes" then
      if state.list_fails then
        return { code = 124, stdout = "", stderr = "timed out" }
      end
      local lines = {}
      for id in pairs(state.panes) do
        lines[#lines + 1] = ("%s %d 1"):format(id, state.active == id and 1 or 0)
      end
      return { code = 0, stdout = table.concat(lines, "\n") .. "\n", stderr = "" }
    elseif sub == "select-pane" or sub == "select-window" then
      local target = cmd[#cmd]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      if sub == "select-pane" then
        state.active = target
      end
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "kill-pane" then
      local target = cmd[#cmd]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      if state.kill_fails then
        return { code = 1, stdout = "", stderr = "cannot kill" }
      end
      state.panes[target] = nil
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "capture-pane" then
      local target = cmd[#cmd]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      return { code = 0, stdout = state.text or "", stderr = "" }
    elseif sub == "send-keys" then
      state.keys[#state.keys + 1] = cmd[#cmd]
      return { code = 0, stdout = "", stderr = "" }
    end
    return { code = 1, stdout = "", stderr = "unknown command " .. tostring(sub) }
  end

  local function run(argv)
    state.calls[#state.calls + 1] = vim.list_slice(argv, 2)
    local args = vim.list_slice(argv, 2)
    if args[1] == "-L" then
      args = vim.list_slice(args, 3)
    end
    local result = { code = 0, stdout = "", stderr = "" }
    local current = {}
    local function flush()
      if #current > 0 then
        result = exec(current)
        current = {}
      end
      return result.code == 0
    end
    for _, arg in ipairs(args) do
      local word, ends = arg, false
      if word:sub(-1) == ";" then
        word = word:sub(1, -2)
        if word:sub(-1) == "\\" then
          word = word:sub(1, -2) .. ";"
        else
          ends = true
        end
      end
      if not ends or word ~= "" then
        current[#current + 1] = word
      end
      if ends and not flush() then
        return result
      end
    end
    flush()
    return result
  end
  return run, state
end
M.tmux = tmux

return M
