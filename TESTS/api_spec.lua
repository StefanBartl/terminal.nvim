---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/api_spec.lua -- the public facade (`require("terminal")`) on the native backend.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal (facade)", function()
  local terminal
  local original_notify = vim.notify
  local notices

  before_each(function()
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.backends.native",
      "terminal.bindings",
    }) do
      package.loaded[mod] = nil
    end
    notices = {}
    vim.notify = function(msg, level)
      notices[#notices + 1] = { msg = msg, level = level }
    end
    terminal = require("terminal")
    -- Commands and keymaps are not the subject here; the sleeper is the terminal's job.
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    })
  end)

  after_each(function()
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.notify = original_notify
  end)

  it("setup resolves the native backend and reports it", function()
    local s = terminal.status()
    assert.is_true(s.ready)
    assert.equals("native", s.backend)
    assert.equals(0, s.terminals)
  end)

  it("falls back to native when a named backend does not exist yet", function()
    terminal.setup({ backend = "tmux", commands = false, keymaps = { preset = false } })
    assert.equals("native", terminal.status().backend)
    vim.wait(100) -- the note is scheduled
    local found = false
    for _, n in ipairs(notices) do
      if n.msg:find("tmux", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("setup does not look for wezterm or tmux on $PATH unless the config names them", function()
    local looked = {}
    local original = vim.fn.executable
    vim.fn.executable = function(name)
      looked[#looked + 1] = name
      return original(name)
    end
    local saved_wez, saved_tmux, saved_pane = vim.env.WEZTERM_PANE, vim.env.TMUX, vim.env.TMUX_PANE
    vim.env.WEZTERM_PANE, vim.env.TMUX, vim.env.TMUX_PANE = "7", "/tmp/tmux-1/default,1,0", "%1"
    terminal.setup({ commands = false, keymaps = { preset = false } })
    vim.env.WEZTERM_PANE, vim.env.TMUX, vim.env.TMUX_PANE = saved_wez, saved_tmux, saved_pane
    vim.fn.executable = original
    assert.is_false(vim.tbl_contains(looked, "wezterm"))
    assert.is_false(vim.tbl_contains(looked, "tmux"))
  end)

  it("a failing part of setup does not leave status and navigation unconfigured", function()
    local saved_pane = vim.env.WEZTERM_PANE
    vim.env.WEZTERM_PANE = "7"
    package.loaded["terminal.bindings"] = {
      setup = function()
        error("boom")
      end,
    }
    package.loaded["terminal.navigate"] = nil
    terminal.setup({ commands = false, keymaps = { preset = false } })
    vim.env.WEZTERM_PANE = saved_pane
    vim.wait(100)
    assert.same({ "wezterm" }, require("terminal.navigate").active())
    local told = false
    for _, n in ipairs(notices) do
      if n.msg:find("bindings failed", 1, true) then
        told = true
      end
    end
    assert.is_true(told)
    package.loaded["terminal.bindings"] = nil
  end)

  it("a bad auto_insert event is reported and does not break setup", function()
    terminal.setup({
      commands = false,
      keymaps = { preset = false },
      auto_insert = { enable = true, events = { "TermEnterr" } },
    })
    vim.wait(100)
    assert.is_true(terminal.status().ready)
    local told = false
    for _, n in ipairs(notices) do
      if n.msg:find("TermEnterr", 1, true) then
        told = true
      end
    end
    assert.is_true(told)
  end)

  it("toggle on a native terminal that is visible elsewhere still enters Insert mode", function()
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = true,
      commands = false,
      keymaps = { preset = false },
    })
    terminal.open({ layout = "vsplit" })
    jobs.settle()
    vim.cmd("wincmd p") -- focus leaves the terminal, it stays visible
    local starts = 0
    local original = vim.cmd
    vim.cmd = function(command, ...)
      if command == "startinsert" then
        starts = starts + 1
      end
      return original(command, ...)
    end
    local ok, err = pcall(terminal.toggle)
    vim.cmd = original
    assert(ok, err)
    assert.equals(1, starts)
  end)

  describe("open / toggle / hide / close", function()
    it("open creates the default terminal once and returns the same handle again", function()
      local a = terminal.open()
      local b = terminal.open()
      assert.equals("main", a.name)
      assert.equals(a.id, b.id)
      assert.equals(1, #terminal.list())
    end)

    it("open without focus keeps the current window current", function()
      local before = vim.api.nvim_get_current_win()
      local h = terminal.open({ focus = false })
      assert.equals(before, vim.api.nvim_get_current_win())
      assert.is_true(#vim.fn.win_findbuf(h.bufnr) > 0)
    end)

    it("toggle: hides a focused terminal, shows a hidden one, creates a missing one", function()
      terminal.toggle()
      local h = terminal.list()[1]
      assert.is_not_nil(h)
      assert.equals(1, #vim.fn.win_findbuf(h.bufnr))

      jobs.settle()
      terminal.toggle() -- focused -> hide
      assert.equals(0, #vim.fn.win_findbuf(h.bufnr))
      assert.equals(1, #terminal.list(), "hiding keeps the terminal")

      jobs.settle()
      terminal.toggle() -- hidden -> show
      assert.equals(1, #vim.fn.win_findbuf(h.bufnr))
      assert.equals(1, #terminal.list())
    end)

    it("toggle on a visible but unfocused terminal focuses it instead of hiding it", function()
      local h = terminal.open()
      vim.cmd("wincmd p")
      assert.not_equals(h.bufnr, vim.api.nvim_get_current_buf())
      terminal.toggle()
      assert.equals(h.bufnr, vim.api.nvim_get_current_buf())
    end)

    it("a count picks the terminal of that number", function()
      terminal.toggle({ count = 3 })
      local names = vim.tbl_map(function(h)
        return h.name
      end, terminal.list())
      assert.same({ "3" }, names)
    end)

    it("an explicit name wins over a count", function()
      terminal.open({ name = "build", count = 3 })
      assert.equals("build", terminal.list()[1].name)
    end)

    it("honours a per-call layout", function()
      local h = terminal.open({ layout = "vsplit" })
      assert.equals("vsplit", h.layout)
      assert.equals("", vim.api.nvim_win_get_config(vim.fn.win_findbuf(h.bufnr)[1]).relative)
    end)

    it("hide returns false for a terminal that does not exist", function()
      assert.is_false(terminal.hide({ name = "ghost" }))
    end)

    it("close removes the terminal; closing a missing one returns false", function()
      terminal.open()
      assert.is_true(terminal.close())
      assert.equals(0, #terminal.list())
      assert.is_false(terminal.close())
    end)

    it("an exited terminal is replaced on the next open", function()
      terminal.setup({
        shell = jobs.exit_with(0),
        on_exit = "keep",
        commands = false,
        keymaps = { preset = false },
        start_insert = false,
      })
      local first = terminal.open()
      assert.is_true(jobs.wait(function()
        return first.exited == true
      end))
      terminal.setup({
        shell = jobs.sleeper(),
        commands = false,
        keymaps = { preset = false },
        start_insert = false,
      })
      local second = terminal.open()
      assert.is_not_nil(second)
      assert.not_equals(first.bufnr, second.bufnr)
      assert.is_false(second.exited == true)
    end)
  end)

  describe("send", function()
    local function eol()
      return vim.fn.has("win32") == 1 and "\r" or "\n"
    end

    it("creates the run terminal on demand and writes the text as typed", function()
      local ok, err
      local sent = jobs.record_sends(function()
        ok, err = terminal.send("some text")
      end)
      assert.is_true(ok, err)
      assert.equals(1, #sent)
      assert.equals("some text", sent[1].text)
      assert.equals(terminal.list()[1].job, sent[1].job)
      local names = vim.tbl_map(function(h)
        return h.name
      end, terminal.list())
      assert.same({ "run" }, names)
    end)

    it("presses Enter only with newline = true", function()
      local sent = jobs.record_sends(function()
        terminal.send("ls", { newline = true })
      end)
      assert.equals("ls" .. eol(), sent[1].text)
    end)

    it("sends to the terminal of the given name", function()
      jobs.record_sends(function()
        terminal.send("x", { name = "repl" })
      end)
      assert.same(
        { "repl" },
        vim.tbl_map(function(h)
          return h.name
        end, terminal.list())
      )
    end)

    it("does not steal focus by default", function()
      local before = vim.api.nvim_get_current_win()
      jobs.record_sends(function()
        terminal.send("x")
      end)
      assert.equals(before, vim.api.nvim_get_current_win())
    end)

    it("rejects a non-string", function()
      local ok, err = terminal.send(42)
      assert.is_false(ok)
      assert.truthy(err)
    end)
  end)

  describe("run", function()
    it("direct: the command is the job and its exit code reaches on_exit", function()
      local code
      local ok = terminal.run(jobs.exit_with(3), {
        direct = true,
        name = "job",
        on_exit = function(c)
          code = c
        end,
      })
      assert.is_true(ok)
      assert.is_true(jobs.wait(function()
        return code ~= nil
      end))
      assert.equals(3, code)
    end)

    it("direct: runs again under the same name and replaces the earlier terminal", function()
      terminal.run(jobs.sleeper(), { direct = true, name = "job", focus = false })
      local first = terminal.list()[1]
      jobs.settle()
      terminal.run(jobs.sleeper(), { direct = true, name = "job", focus = false })
      assert.equals(1, #terminal.list())
      assert.not_equals(first.bufnr, terminal.list()[1].bufnr)
    end)

    it(
      "direct: close = always removes the terminal when the job ends, on_open sees the handle",
      function()
        local opened, code
        terminal.run(jobs.exit_with(0), {
          direct = true,
          name = "tui",
          close = "always",
          on_open = function(h)
            opened = h
          end,
          on_exit = function(c)
            code = c
          end,
        })
        assert.is_not_nil(opened)
        assert.equals("tui", opened.name)
        assert.is_true(jobs.wait(function()
          return code ~= nil and #terminal.list() == 0
        end))
        assert.equals(0, code)
      end
    )

    it("direct: close = success keeps a failed job readable", function()
      local code
      terminal.run(jobs.exit_with(4), {
        direct = true,
        name = "tui",
        close = "success",
        on_exit = function(c)
          code = c
        end,
      })
      assert.is_true(jobs.wait(function()
        return code ~= nil
      end))
      vim.wait(100)
      assert.equals(1, #terminal.list())
      assert.equals(4, terminal.list()[1].exit_code)
    end)

    it("direct: title, cwd and float overrides reach the window and the job", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local _, _, h = terminal.run(jobs.sleeper(), {
        direct = true,
        name = "git",
        title = "lazygit",
        cwd = dir,
        float = { width = 0.5, height = 0.5 },
      })
      -- Assert first, clean up always: a failed assertion must not leave the directory behind.
      local ok, err = pcall(function()
        local win = vim.fn.win_findbuf(h.bufnr)[1]
        local cfg = vim.api.nvim_win_get_config(win)
        assert.truthy(vim.inspect(cfg.title):find("lazygit", 1, true))
        assert.is_true(cfg.width < vim.o.columns * 0.6)
        assert.equals(dir, h.cwd, "the job starts in the directory that was asked for")
      end)
      vim.fn.delete(dir, "d")
      if not ok then
        error(err, 0)
      end
    end)

    it("direct: needs an argv list", function()
      local ok, err = terminal.run("make test", { direct = true })
      assert.is_false(ok)
      assert.truthy(err:find("argv", 1, true))
      assert.equals(0, #terminal.list())
    end)

    it("an argv with a line break is refused before any terminal is started", function()
      local ok, err = terminal.run({ "echo", "a\nrm -rf /" })
      assert.is_false(ok)
      assert.truthy(err)
      assert.equals(0, #terminal.list())
    end)

    it("refuses an empty command", function()
      assert.is_false((terminal.run("")))
      assert.is_false((terminal.run({})))
    end)

    it("an argv is quoted for the shell and typed into the run terminal with Enter", function()
      local ok, err
      local sent = jobs.record_sends(function()
        ok, err = terminal.run({ "echo", "a b", "it's" })
      end)
      assert.is_true(ok, err)
      assert.equals("run", terminal.list()[1].name)
      -- the shell is the sleeper program (a POSIX-style name), so POSIX quoting applies
      assert.equals(
        [[echo 'a b' 'it'\''s']] .. (vim.fn.has("win32") == 1 and "\r" or "\n"),
        sent[1].text
      )
    end)

    it("a string is typed exactly as given", function()
      local sent = jobs.record_sends(function()
        terminal.run("make test && echo $HOME")
      end)
      assert.equals(
        "make test && echo $HOME" .. (vim.fn.has("win32") == 1 and "\r" or "\n"),
        sent[1].text
      )
    end)
  end)

  it("list(true) shows every project, list() only the current one", function()
    terminal.open({ name = "a", focus = false })
    assert.equals(1, #terminal.list())
    assert.equals(1, #terminal.list(true))
  end)
end)
