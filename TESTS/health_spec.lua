---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
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
      -- Test double: a Neovim without nvim_ui_send; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_ui_send = nil
      local r, log = recorder()
      pcall(health.check_wezterm, r, { WEZTERM_PANE = "3" })
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
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
      -- Restore the originals.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = executable
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_ui_send = ui_send
    end)

    --- No hand-off and no export: what is left in `patch` is the only thing that can name a
    --- multiplexer, so a warning (or its absence) is that option's doing.
    ---@param patch table
    local function alone(patch)
      return cfg(vim.tbl_deep_extend("force", {
        navigate = { handoff = false },
        status = { export = false },
      }, patch))
    end

    it("a missing wezterm binary: each cause that relies on it warns on its own", function()
      -- Test double: no executable is on $PATH; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = function()
        return 0
      end
      for _, patch in ipairs({
        { backend = "wezterm" },
        { navigate = { handoff = "wezterm" } },
        { navigate = { handoff = { "wezterm" } } },
        { navigate = { handoff = "auto" } },
      }) do
        local r, log = recorder()
        health.check_wezterm(r, { WEZTERM_PANE = "3" }, alone(patch))
        assert.truthy(first(log, "warn", "`wezterm` is not on $PATH"), vim.inspect(patch))
      end
    end)

    it("a missing multiplexer binary: only the backend option names it", function()
      -- The backend alone makes the plugin rely on the multiplexer's command line: with the
      -- hand-off and the export off nothing else does, so `native` and `auto` only inform.
      -- Test double: no executable is on $PATH; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = function()
        return 0
      end
      local envs = {
        wezterm = { WEZTERM_PANE = "3" },
        tmux = { TMUX = "/tmp/tmux-1/default,1,0" },
      }
      local checks = { wezterm = health.check_wezterm, tmux = health.check_tmux }
      for _, name in ipairs({ "wezterm", "tmux" }) do
        local fragment = ("`%s` is not on $PATH"):format(name)
        local r, log = recorder()
        checks[name](r, envs[name], alone({ backend = name }))
        assert.truthy(first(log, "warn", fragment), name .. ": " .. table.concat(log, "\n"))
        for _, other in ipairs({ "native", "auto", name == "tmux" and "wezterm" or "tmux" }) do
          r, log = recorder()
          checks[name](r, envs[name], alone({ backend = other }))
          assert.truthy(
            first(log, "info", fragment),
            name .. " with backend " .. other .. ": " .. table.concat(log, "\n")
          )
          assert.is_nil(first(log, "warn", fragment), name .. " with backend " .. other)
        end
      end
    end)

    it("a missing wezterm binary is only info when nothing needs its command line", function()
      -- Test double: no executable is on $PATH; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
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
      -- Test double: no executable is on $PATH; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
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
      -- Test double: a Neovim without nvim_ui_send; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
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
      -- Test double: no executable is on $PATH; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
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
      -- Deliberately invalid value: the case checks that health reports it.
      ---@diagnostic disable-next-line: assign-type-mismatch
      config.setup({ layout = "sideways" })
      local real = vim.health
      local r, log = recorder()
      -- Test double: a health reporter that records what was said; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = r
      local ok, err = pcall(health.check)
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = real
      config.setup({})
      assert.is_true(ok, tostring(err))
      assert.truthy(first(log, "warn", "config: config key 'layout'"), table.concat(log, "\n"))
    end)

    it("the full check errors on a lib.nvim module the plugin needs but cannot find", function()
      local real_require = require
      -- Test double: require fails for one lib.nvim module; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      _G.require = function(name)
        if name == "lib.nvim.debounce" then
          error("module 'lib.nvim.debounce' not found")
        end
        return real_require(name)
      end
      local real = vim.health
      local r, log = recorder()
      -- Test double: a health reporter that records what was said; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = r
      local ok, err = pcall(health.check)
      -- Restore the originals.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = real
      ---@diagnostic disable-next-line: duplicate-set-field
      _G.require = real_require
      assert.is_true(ok, tostring(err))
      assert.truthy(first(log, "error", "lib.nvim.debounce not found"), table.concat(log, "\n"))
    end)

    it("the full check asks for exactly the lib modules the plugin requires", function()
      -- Both directions: a required module the check forgets would pass on a lib.nvim without
      -- it, a listed module nothing requires would fail the check for a feature that does not
      -- exist (it was `lib.nvim.system.env`, "keymap environment").
      local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/.."
      local wanted = {}
      for _, file in ipairs(vim.fn.globpath(root .. "/lua/terminal", "**/*.lua", false, true)) do
        local handle = assert(io.open(file, "rb"))
        local text = handle:read("*a")
        handle:close()
        for name in text:gmatch("require%(%s*[\"'](lib%.[%w_%.]+)[\"']%s*%)") do
          wanted[name] = true
        end
      end
      assert.is_true(next(wanted) ~= nil, "found no lib.nvim require under lua/terminal")

      local asked = {}
      local real_require = require
      -- Test double: records every lib.* module asked for, then loads it for real; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      _G.require = function(name)
        if type(name) == "string" and name:find("^lib%.") then
          asked[name] = true
        end
        return real_require(name)
      end
      local real = vim.health
      local r = recorder()
      -- Test double: a health reporter that records what was said; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = r
      local ok, err = pcall(health.check)
      -- Restore the originals.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = real
      ---@diagnostic disable-next-line: duplicate-set-field
      _G.require = real_require
      assert.is_true(ok, tostring(err))

      local function sorted(set)
        local names = vim.tbl_keys(set)
        table.sort(names)
        return names
      end
      assert.same(sorted(wanted), sorted(asked))
    end)

    it("a quoted 'shell' with a path with spaces and arguments counts as executable", function()
      local path = "C:\\Program Files\\Some Shell\\sh.exe"
      -- Test double: only the quoted shell path counts as executable; restored in after_each.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.executable = function(name)
        return name == path and 1 or 0
      end
      local shell = vim.o.shell
      vim.o.shell = '"' .. path .. '" -l'
      local real = vim.health
      local r, log = recorder()
      -- Test double: a health reporter that records what was said; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = r
      local ok, err = pcall(health.check)
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.health = real
      vim.o.shell = shell
      assert.is_true(ok, tostring(err))
      assert.truthy(first(log, "ok", "shell is executable"), table.concat(log, "\n"))
      assert.is_nil(first(log, "warn", "shell is not executable"))
    end)
  end)
end)
