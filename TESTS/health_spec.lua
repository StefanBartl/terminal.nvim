---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/health_spec.lua -- :checkhealth terminal

local health = require("terminal.health")

--- A health reporter that records what was said.
local function recorder()
  local log = {}
  local r = {}
  for _, level in ipairs({ "ok", "warn", "error", "info", "start" }) do
    r[level] = function(msg)
      log[#log + 1] = level .. ": " .. msg
    end
  end
  return r, log
end

describe("terminal.health", function()
  it("reads the WezTerm release date from --version", function()
    assert.equals(20240203, health.parse_wezterm_version("wezterm 20240203-110809-5046fc22"))
    assert.equals(20250101, health.parse_wezterm_version("wezterm 20250101-000000-abcdef12"))
    assert.is_nil(health.parse_wezterm_version("wezterm nightly"))
    assert.is_nil(health.parse_wezterm_version(""))
  end)

  it("passthrough counts as enabled for on and all only", function()
    assert.is_true(health.passthrough_enabled("on"))
    assert.is_true(health.passthrough_enabled("all"))
    assert.is_false(health.passthrough_enabled("off"))
    assert.is_false(health.passthrough_enabled(nil))
    assert.is_false(health.passthrough_enabled(""))
  end)

  it("outside WezTerm and tmux it only informs", function()
    local r, log = recorder()
    health.check_wezterm(r, {})
    health.check_tmux(r, {})
    assert.same({ "info: WezTerm: not inside it", "info: tmux: not inside it" }, log)
  end)

  it("inside WezTerm it reports the pane and never raises, whatever is installed", function()
    local r, log = recorder()
    local ok = pcall(health.check_wezterm, r, { WEZTERM_PANE = "3" })
    assert.is_true(ok)
    assert.truthy(log[1]:find("WEZTERM_PANE = 3", 1, true))
  end)

  it("the full check runs without raising", function()
    local ok, err = pcall(health.check)
    assert.is_true(ok, tostring(err))
  end)
end)
