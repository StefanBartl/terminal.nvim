---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
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
    -- Test double: reports `wezterm` as installed, everything else as the real function does.
    ---@diagnostic disable-next-line: duplicate-set-field
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
    -- Test double: collects the notifications instead of showing them.
    ---@diagnostic disable-next-line: duplicate-set-field
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

    it("leaves the native terminal untouched when the multiplexer would refuse the pane", function()
      -- `env` is something a pane cannot take: known up front, so nothing is closed.
      boot(true, { env = { FOO = "1" } })
      local native = terminal.open({ name = "work" })
      jobs.settle()
      local ok, err = terminal.pin({ name = "work" })
      assert.is_false(ok)
      assert.truthy(err:find("environment", 1, true))
      assert.is_true(vim.api.nvim_buf_is_valid(native.bufnr), "the same terminal is still there")
      assert.equals(native, terminal.list()[1])
      for _, c in ipairs(state.calls) do
        assert.not_equals("split-pane", c.argv[1])
      end
    end)

    --- WezTerm answers every query but cannot split a pane: the failure comes AFTER the ping.
    local function split_fails()
      local original = wezterm.default_runner
      -- Test double: a runner that fails `split-pane` and forwards everything else.
      ---@diagnostic disable-next-line: duplicate-set-field
      wezterm.default_runner = function(argv, opts)
        if argv[3] == "split-pane" then
          return { code = 1, stdout = "", stderr = "mux is gone" }
        end
        return original(argv, opts)
      end
      return function()
        wezterm.default_runner = original
      end
    end

    it("refuses before the terminal ends when the multiplexer does not answer at all", function()
      boot(true)
      local native = terminal.open({ name = "work" })
      jobs.settle()
      local original = wezterm.default_runner
      -- Test double: a multiplexer that does not answer at all (timed out).
      ---@diagnostic disable-next-line: duplicate-set-field
      wezterm.default_runner = function()
        return { code = 124, stdout = "", stderr = "timed out" }
      end
      local ok, err = terminal.pin({ name = "work" })
      wezterm.default_runner = original
      assert.is_false(ok)
      assert.truthy(err:find("timed out", 1, true))
      assert.is_true(
        vim.api.nvim_buf_is_valid(native.bufnr),
        "the running terminal was not touched"
      )
      assert.equals(native, terminal.list()[1])
      vim.wait(100)
      assert.truthy(table.concat(notices, "\n"):find("not reachable", 1, true))
    end)

    it("starts a native terminal again when the pane cannot be split at run time", function()
      boot(true)
      local native = terminal.open({ name = "work" })
      jobs.settle()
      local undo = split_fails()
      local ok, err = terminal.pin({ name = "work" })
      undo()
      vim.wait(100)
      assert.truthy(table.concat(notices, "\n"):find("was started again", 1, true))
      assert.is_false(ok)
      assert.truthy(err:find("mux is gone", 1, true))
      -- the old terminal ended (its output and history are gone), the user still has a terminal
      assert.is_false(vim.api.nvim_buf_is_valid(native.bufnr))
      assert.equals(1, #terminal.list())
      local again = terminal.list()[1]
      assert.equals("native", again.backend)
      assert.equals("work", again.name)
      assert.same(native.cmd, again.cmd)
      assert.is_true(vim.api.nvim_buf_is_valid(again.bufnr))
    end)

    it(
      "the old job has ended before the pane starts (no two copies of a server at once)",
      function()
        boot(true)
        local native = terminal.open({ name = "work" })
        jobs.settle()
        local old_job = native.job
        local running_at_spawn
        local runner = wezterm.default_runner
        -- Test double: notes whether the old job still ran when the pane was split, then forwards.
        ---@diagnostic disable-next-line: duplicate-set-field
        wezterm.default_runner = function(argv, opts)
          if argv[3] == "split-pane" then
            running_at_spawn = vim.fn.jobwait({ old_job }, 0)[1] == -1
          end
          return runner(argv, opts)
        end
        -- the facade creates the wezterm backend lazily, so it picks this runner up now
        local ok = terminal.pin({ name = "work" })
        wezterm.default_runner = runner
        assert.is_true(ok)
        assert.is_false(running_at_spawn, "the native job was still running when the pane started")
      end
    )

    it("says so when the native terminal could not be started again either", function()
      local real = require("terminal.backends.native")
      local fail_spawn = false
      package.loaded["terminal.backends.native"] = {
        new = function(registry)
          local backend = real.new(registry)
          local spawn = backend.spawn
          backend.spawn = function(spec)
            if fail_spawn then
              return nil, "no room for a window"
            end
            return spawn(spec)
          end
          return backend
        end,
      }
      local ok, err = pcall(function()
        boot(true)
        terminal.open({ name = "work" })
        jobs.settle()
        fail_spawn = true
        local undo = split_fails()
        local pinned = terminal.pin({ name = "work" })
        undo()
        assert.is_false(pinned)
        vim.wait(100)
        assert.equals(
          0,
          #terminal.list(true),
          "the terminal is lost, and the message must not claim otherwise"
        )
        local said = table.concat(notices, "\n")
        assert.truthy(said:find("could not be started again", 1, true), said)
        assert.truthy(said:find("no room for a window", 1, true), said)
        assert.is_nil(said:find("was started again", 1, true), said)
      end)
      package.loaded["terminal.backends.native"] = real
      assert(ok, err)
    end)

    it("an unknown backend is a failure, not an error", function()
      boot(true)
      terminal.open({ name = "work" })
      jobs.settle()
      local called, ok, err = pcall(terminal.pin, { name = "work" }, { backend = "screen" })
      assert.is_true(called)
      assert.is_false(ok)
      assert.truthy(err:find("screen", 1, true))
      assert.equals(1, #terminal.list(), "the native terminal is untouched")
    end)

    it("refuses a layout the multiplexer would refuse BEFORE the native terminal ends", function()
      boot(true)
      local native = terminal.open({ name = "work" })
      local bufnr, job = native.bufnr, native.job
      jobs.settle()
      for _, bad in ipairs({ "bogus", "", "Float" }) do
        local ok, err = terminal.pin({ name = "work" }, { layout = bad })
        assert.is_false(ok)
        assert.truthy(err:find("unknown layout", 1, true), bad)
      end
      -- nothing was touched: the same buffer, the same running job, the same handle
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
      assert.equals(-1, vim.fn.jobwait({ job }, 0)[1])
      assert.equals(native, terminal.list()[1])
      for _, c in ipairs(state.calls) do
        assert.not_equals("split-pane", c.argv[1], "no pane was started")
      end
    end)

    it("says why when there is no multiplexer", function()
      boot(false)
      terminal.open({ name = "work" })
      local ok, err = terminal.pin({ name = "work" })
      assert.is_false(ok)
      assert.truthy(err:find("multiplexer", 1, true))
      assert.equals(1, #terminal.list(), "the native terminal is untouched")
    end)

    -- needs a Neovim with 'winfixbuf' (0.10+); not registered on an older one
    if vim.fn.exists("&winfixbuf") == 1 then
      it("a native terminal whose window will not close is not replaced by a pane", function()
        boot(true)
        local native = terminal.open({ name = "work", layout = "tab" })
        vim.cmd("1tabclose") -- the terminal is alone in the only window now
        jobs.settle()
        local win = vim.fn.win_findbuf(native.bufnr)[1]
        vim.wo[win].winfixbuf = true
        local called, ok, err = pcall(terminal.pin, { name = "work" })
        vim.wo[win].winfixbuf = false
        assert.is_true(called, tostring(ok))
        assert.is_false(ok)
        assert.truthy(tostring(err):find("cannot end the native terminal", 1, true), tostring(err))
        assert.equals(native, terminal.list()[1], "the native terminal is still the registered one")
        for _, c in ipairs(state.calls) do
          assert.not_equals("split-pane", c.argv[1], "no pane was started")
          assert.not_equals("spawn", c.argv[1], "no tab was started")
        end
      end)
    end

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

    it("a capture slower than the refresh interval never overlaps the next one", function()
      boot(true)
      terminal.open({ name = "work" })
      jobs.settle()
      local _, _, pinned = terminal.pin({ name = "work" })
      local running, deepest, captures = 0, 0, 0
      local buf = terminal.adopt({ name = "work" })
      -- from now on a capture takes 1.5 s: longer than the 1 s between two refreshes. The wait
      -- lets the event loop run, exactly like `vim.system():wait()` does.
      state.on_get_text = function()
        captures = captures + 1
        running = running + 1
        deepest = math.max(deepest, running)
        vim.wait(1500)
        running = running - 1
      end
      vim.v.errmsg = ""
      -- the pane disappears while the first slow capture runs: the view ends after that capture
      state.panes[pinned.pane] = nil
      assert.is_true(vim.wait(6000, function()
        return captures >= 1
          and (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""):find("not found", 1, true)
            ~= nil
      end, 50))
      vim.wait(2500) -- time for ticks that must not happen
      assert.equals(1, deepest, "two captures ran at the same time")
      assert.equals(1, captures, "the view kept refreshing a pane that is gone")
      assert.equals("", vim.v.errmsg)
    end)

    it("no room for the view's window: nil, err, and no buffer or timer left behind", function()
      boot(true)
      terminal.open({ name = "work" })
      jobs.settle()
      terminal.pin({ name = "work" })
      local views_before = #vim.tbl_filter(function(b)
        return vim.api.nvim_buf_get_name(b):find("terminal://", 1, true) ~= nil
      end, vim.api.nvim_list_bufs())
      -- split until Neovim says "E36: Not enough room"
      local splits = 0
      while splits < 300 and pcall(function()
        vim.cmd("split")
      end) do
        splits = splits + 1
      end
      local ok, buf, err = pcall(terminal.adopt, { name = "work" })
      vim.cmd("silent! only")
      assert.is_true(ok, tostring(buf))
      assert.is_nil(buf)
      assert.truthy(tostring(err):find("cannot open a window", 1, true), tostring(err))
      local views_after = #vim.tbl_filter(function(b)
        return vim.api.nvim_buf_get_name(b):find("terminal://", 1, true) ~= nil
      end, vim.api.nvim_list_bufs())
      assert.equals(views_before, views_after, "the half-made view buffer was deleted")
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
