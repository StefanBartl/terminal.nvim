---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/pin_adopt_spec.lua -- pin (restart in a multiplexer pane) and adopt (view a pane).

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")
local fakes = dofile(here .. "/support/fakes.lua")
local wezterm = require("terminal.backends.wezterm")

describe("terminal pin / adopt", function()
  local terminal, state
  local saved = {}
  local original_notify = vim.notify
  local notices

  ---@param with_wezterm boolean
  ---@param extra? table Further setup options
  local function boot(with_wezterm, extra)
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.bindings",
      "terminal.status",
      "terminal.navigate",
    }) do
      package.loaded[mod] = nil
    end
    local runner
    runner, state = fakes.wezterm()
    state.text = "line one\r\nred \27[31mtext\27[0m\nlast\n\n\n"
    saved.env = vim.env.WEZTERM_PANE
    saved.executable = vim.fn.executable
    saved.runner = wezterm.default_runner
    vim.env.WEZTERM_PANE = with_wezterm and "7" or nil
    vim.fn.executable = function(name)
      if name == "wezterm" then
        return 1
      end
      return saved.executable(name)
    end
    wezterm.default_runner = runner
    terminal = require("terminal")
    terminal.setup(vim.tbl_extend("force", {
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
      status = { enable = false },
      navigate = { handoff = false },
    }, extra or {}))
  end

  before_each(function()
    notices = {}
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    vim.cmd("silent! only")
  end)

  after_each(function()
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.env.WEZTERM_PANE = saved.env
    vim.fn.executable = saved.executable
    wezterm.default_runner = saved.runner
    vim.notify = original_notify
    vim.cmd("silent! only")
  end)

  describe("pin", function()
    it("closes the native terminal and starts the same command in a pane, same name", function()
      boot(true)
      local native = terminal.open({ name = "work" })
      assert.equals("native", native.backend)
      local bufnr, cmd = native.bufnr, native.cmd
      jobs.settle()

      local ok, err, pinned = terminal.pin({ name = "work" })
      assert.is_true(ok, err)
      assert.equals("wezterm", pinned.backend)
      assert.equals("work", pinned.name)
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr), "the native buffer is gone")

      local spawn
      for _, c in ipairs(state.calls) do
        if c.argv[1] == "split-pane" then
          spawn = c.argv
        end
      end
      local dash = vim.fn.index(spawn, "--")
      assert.same(cmd, vim.list_slice(spawn, dash + 2))
      assert.equals(1, #terminal.list())
      assert.equals("wezterm", terminal.list()[1].backend)
    end)

    it("then toggle/close act on the pane through its own backend", function()
      boot(true)
      terminal.open({ name = "work" })
      jobs.settle()
      terminal.pin({ name = "work" })
      assert.equals("8", state.active, "the pinned pane opens with focus")
      terminal.toggle({ name = "work" }) -- focused: toggle hands focus back to Neovim
      assert.equals("7", state.active)
      terminal.toggle({ name = "work" }) -- visible elsewhere: toggle focuses the pane
      assert.equals("8", state.active)
      assert.is_true(terminal.close({ name = "work" }))
      assert.equals(0, #terminal.list())
    end)

    it("keeps the native terminal when the pane cannot be started", function()
      -- `env` is something a multiplexer pane cannot take: the pane fails, the old terminal stays.
      boot(true, { env = { FOO = "1" } })
      local native = terminal.open({ name = "work" })
      jobs.settle()
      local ok, err = terminal.pin({ name = "work" })
      assert.is_false(ok)
      assert.truthy(err:find("environment", 1, true))
      assert.is_true(vim.api.nvim_buf_is_valid(native.bufnr), "the native terminal is still there")
      assert.equals(1, #terminal.list())
      assert.equals("native", terminal.list()[1].backend)
    end)

    it("keeps the native terminal when wezterm cli fails", function()
      boot(true)
      local native = terminal.open({ name = "work" })
      jobs.settle()
      local original = wezterm.default_runner
      wezterm.default_runner = function()
        return { code = 1, stdout = "", stderr = "mux is gone" }
      end
      local ok = terminal.pin({ name = "work" })
      wezterm.default_runner = original
      assert.is_false(ok)
      assert.is_true(vim.api.nvim_buf_is_valid(native.bufnr))
      assert.equals("native", terminal.list()[1].backend)
    end)

    it("says why when there is no multiplexer", function()
      boot(false)
      terminal.open({ name = "work" })
      local ok, err = terminal.pin({ name = "work" })
      assert.is_false(ok)
      assert.truthy(err:find("multiplexer", 1, true))
      assert.equals(1, #terminal.list(), "the native terminal is untouched")
    end)

    it("refuses a missing terminal and one that is pinned already", function()
      boot(true)
      local ok, err = terminal.pin({ name = "ghost" })
      assert.is_false(ok)
      assert.truthy(err:find("no terminal", 1, true))
      terminal.open({ name = "work" })
      jobs.settle()
      terminal.pin({ name = "work" })
      ok, err = terminal.pin({ name = "work" })
      assert.is_false(ok)
      assert.truthy(err:find("already", 1, true))
    end)
  end)

  describe("adopt", function()
    it("shows the pane's text in a read-only buffer, control characters replaced", function()
      boot(true)
      terminal.open({ name = "work" })
      jobs.settle()
      terminal.pin({ name = "work" })
      local buf = terminal.adopt({ name = "work" })
      assert.is_number(buf)
      assert.same(
        { "line one", "red ?[31mtext?[0m", "last" },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      assert.is_false(vim.bo[buf].modifiable)
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.truthy(vim.api.nvim_buf_get_name(buf):find("terminal://wezterm/", 1, true))
    end)

    it("refreshes while visible and notes a pane that is gone", function()
      boot(true)
      terminal.open({ name = "work" })
      jobs.settle()
      local _, _, pinned = terminal.pin({ name = "work" })
      local buf = terminal.adopt({ name = "work" })
      state.text = "changed\n"
      assert.is_true(vim.wait(3000, function()
        return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "changed"
      end, 100))
      state.panes[pinned.pane] = nil
      assert.is_true(vim.wait(3000, function()
        return (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""):find("not found", 1, true)
          ~= nil
      end, 100))
    end)

    it("refuses a native terminal: there is no pane to show", function()
      boot(true)
      terminal.open({ name = "work" })
      local buf, err = terminal.adopt({ name = "work" })
      assert.is_nil(buf)
      assert.truthy(err:find("no pane", 1, true))
    end)
  end)
end)
