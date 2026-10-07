---@module 'terminal.backends'
--- Backend registry, environment detection and resolution.
---
--- A backend is a table that satisfies `Terminal.Backend`. `native` always exists; the
--- multiplexer backends register themselves when they are implemented. `detect` and `resolve`
--- are pure functions over an environment table, so they are testable without a real terminal.

local M = {}

---@internal
--- Variables that identify a multiplexer or terminal emulator, most specific first.
---@type { name: string, var: string }[]
local SIGNALS = {
  { name = "tmux", var = "TMUX" },
  { name = "wezterm", var = "WEZTERM_PANE" },
}

--- Which backends the environment makes available, most specific first; `native` is always last.
--- Nested environments (tmux inside WezTerm) report both.
---@param env table<string, string|nil>
---@return string[]
function M.detect(env)
  local found = {}
  for _, signal in ipairs(SIGNALS) do
    local v = env[signal.var]
    if v ~= nil and v ~= "" then
      found[#found + 1] = signal.name
    end
  end
  found[#found + 1] = "native"
  return found
end

--- Pick the backend to use.
---
--- `wanted` is the configured name. "auto" is `native`: terminals stay Neovim windows even inside
--- WezTerm or tmux (status export to those is a separate, additive feature). A multiplexer
--- backend is used only when it is named; one that is not registered (not implemented yet, or
--- not available here) falls back to `native` and says why.
---@param wanted Terminal.BackendName
---@param _env table<string, string|nil> Unused: kept so a future "auto" can read it
---@param registered table<string, any> Set of registered backend names
---@return string name
---@return string|nil note Why the choice differs from what was asked, nil when it does not
function M.resolve(wanted, _env, registered)
  if wanted == "auto" or wanted == "native" then
    return "native", nil
  end
  if registered[wanted] then
    return wanted, nil
  end
  return "native", ("backend '%s' is not available -- using native"):format(wanted)
end

return M
