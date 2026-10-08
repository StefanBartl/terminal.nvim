---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/health_spec.lua -- :checkhealth terminal

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

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

  it(
    "inside WezTerm on a Neovim without nvim_ui_send it warns that the export needs 0.12",
    function()
      local saved = vim.api.nvim_ui_send
      vim.api.nvim_ui_send = nil
      local r, log = recorder()
      pcall(health.check_wezterm, r, { WEZTERM_PANE = "3" })
      vim.api.nvim_ui_send = saved
      local warned = false
      for _, line in ipairs(log) do
        if
          line:find("^warn:")
          and line:find("nvim_ui_send", 1, true)
          and line:find("0.12", 1, true)
        then
          warned = true
        end
      end
      assert.is_true(warned, table.concat(log, "\n"))
    end
  )

  it("the full check runs without raising", function()
    local ok, err = pcall(health.check)
    assert.is_true(ok, tostring(err))
  end)

  describe("warn only when the options rely on what is missing", function()
    local DEFAULTS = require("terminal.config.DEFAULTS")
    local executable = vim.fn.executable
    local ui_send = vim.api.nvim_ui_send

    local function cfg(patch)
      return vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), patch or {})
    end

    local function first(log, level, fragment)
      for _, line in ipairs(log) do
        if line:find("^" .. level .. ":") and line:find(fragment, 1, true) then
          return line
        end
      end
    end

    after_each(function()
      vim.fn.executable = executable
      vim.api.nvim_ui_send = ui_send
    end)

    it("a missing wezterm binary: warn with the wezterm backend or the auto hand-off", function()
      vim.fn.executable = function()
        return 0
      end
      for _, patch in ipairs({
        { backend = "wezterm" },
        { navigate = { handoff = "wezterm" } },
        { navigate = { handoff = "auto" } },
      }) do
        local r, log = recorder()
        health.check_wezterm(r, { WEZTERM_PANE = "3" }, cfg(patch))
        assert.truthy(first(log, "warn", "`wezterm` is not on $PATH"), vim.inspect(patch))
      end
    end)

    it("a missing wezterm binary is only info when nothing needs its command line", function()
      vim.fn.executable = function()
        return 0
      end
      local r, log = recorder()
      health.check_wezterm(
        r,
        { WEZTERM_PANE = "3" },
        cfg({ navigate = { handoff = false }, status = { export = false } })
      )
      assert.truthy(first(log, "info", "`wezterm` is not on $PATH"), table.concat(log, "\n"))
      assert.is_nil(first(log, "warn", "wezterm"))
    end)

    it("inside tmux inside WezTerm the auto hand-off belongs to tmux, not to wezterm", function()
      vim.fn.executable = function()
        return 0
      end
      local r, log = recorder()
      health.check_wezterm(
        r,
        { WEZTERM_PANE = "3", TMUX = "/tmp/tmux-1/default,1,0" },
        cfg({ status = { export = false } })
      )
      assert.truthy(first(log, "info", "`wezterm` is not on $PATH"), table.concat(log, "\n"))
    end)

    it("a missing nvim_ui_send is a warning only while the wezterm export is wanted", function()
      vim.api.nvim_ui_send = nil
      local r, log = recorder()
      health.check_wezterm(r, { WEZTERM_PANE = "3" }, cfg())
      assert.truthy(first(log, "warn", "nvim_ui_send"))
      r, log = recorder()
      health.check_wezterm(r, { WEZTERM_PANE = "3" }, cfg({ status = { export = "tmux" } }))
      assert.truthy(first(log, "info", "nvim_ui_send"))
      r, log = recorder()
      health.check_wezterm(r, { WEZTERM_PANE = "3" }, cfg({ status = { enable = false } }))
      assert.truthy(first(log, "info", "nvim_ui_send"))
    end)

    it("a missing tmux binary follows the same rule", function()
      vim.fn.executable = function()
        return 0
      end
      local env = { TMUX = "/tmp/tmux-1/default,1,0" }
      local r, log = recorder()
      health.check_tmux(r, env, cfg())
      assert.truthy(first(log, "warn", "`tmux` is not on $PATH"))
      r, log = recorder()
      health.check_tmux(
        r,
        env,
        cfg({ navigate = { handoff = false }, status = { export = false } })
      )
      assert.truthy(first(log, "info", "`tmux` is not on $PATH"))
    end)

    it("the full check reports a problem the last setup() found in the options", function()
      local config = require("terminal.config")
      config.setup({ layout = "sideways" })
      local real = vim.health
      local r, log = recorder()
      vim.health = r
      local ok, err = pcall(health.check)
      vim.health = real
      config.setup({})
      assert.is_true(ok, tostring(err))
      assert.truthy(first(log, "warn", "config: config key 'layout'"), table.concat(log, "\n"))
    end)

    it("the full check errors on a lib.nvim module the plugin needs but cannot find", function()
      local real_require = require
      _G.require = function(name)
        if name == "lib.nvim.debounce" then
          error("module 'lib.nvim.debounce' not found")
        end
        return real_require(name)
      end
      local real = vim.health
      local r, log = recorder()
      vim.health = r
      local ok, err = pcall(health.check)
      vim.health = real
      _G.require = real_require
      assert.is_true(ok, tostring(err))
      assert.truthy(first(log, "error", "lib.nvim.debounce not found"), table.concat(log, "\n"))
    end)

    it("a quoted 'shell' with a path with spaces and arguments counts as executable", function()
      local path = "C:\\Program Files\\Some Shell\\sh.exe"
      vim.fn.executable = function(name)
        return name == path and 1 or 0
      end
      local shell = vim.o.shell
      vim.o.shell = '"' .. path .. '" -l'
      local real = vim.health
      local r, log = recorder()
      vim.health = r
      local ok, err = pcall(health.check)
      vim.health = real
      vim.o.shell = shell
      assert.is_true(ok, tostring(err))
      assert.truthy(first(log, "ok", "shell is executable"), table.concat(log, "\n"))
      assert.is_nil(first(log, "warn", "shell is not executable"))
    end)
  end)
end)
