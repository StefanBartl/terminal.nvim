---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/tmux_backend_spec.lua -- the tmux backend and status exporter against a fake `tmux`.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local registry_mod = require("terminal.core.registry")
local tmux = require("terminal.backends.tmux")
local exporter = require("terminal.status.exporters.tmux")

local fake = dofile(
  (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/fakes.lua"
).tmux

describe("terminal.backends.tmux", function()
  local registry, backend, state

  before_each(function()
    registry = registry_mod.new()
    local runner
    runner, state = fake()
    backend = tmux.new(registry, runner, "%0")
  end)

  --- The recorded calls without the one-off `tmux -V` probe.
  local function calls()
    return vim.tbl_filter(function(c)
      return c[#c] ~= "-V"
    end, state.calls)
  end

  --- The commands tmux ran, without the version probe.
  local function ran()
    return vim.tbl_filter(function(c)
      return c[1] ~= "-V"
    end, state.executed)
  end

  ---@param over? table
  local function spec(over)
    return vim.tbl_extend("force", {
      name = "t1",
      root = "/proj",
      cwd = "/proj",
      cmd = { "make", "test" },
      layout = "vsplit",
      split = { size = 0.3 },
      start_insert = true,
    }, over or {})
  end

  it("available needs $TMUX and $TMUX_PANE", function()
    assert.is_false((tmux.available({})))
    assert.is_false((tmux.available({ TMUX = "x" })))
  end)

  describe("spawn", function()
    it("vsplit: split-window -h with percent size, cwd and the argv", function()
      local h = backend.spawn(spec())
      assert.equals("%1", h.pane)
      assert.equals("tmux", h.backend)
      assert.same({
        "split-window",
        "-P",
        "-F",
        "#{pane_id}",
        "-t",
        "%0",
        "-h",
        "-l",
        "30%",
        "-c",
        "/proj",
        "--",
        "make",
        "test",
      }, calls()[1])
      assert.equals(h, registry:get("/proj::t1"))
    end)

    it("split is -v, float is -h, tab is new-window", function()
      backend.spawn(spec({ name = "a", layout = "split" }))
      assert.truthy(vim.tbl_contains(state.calls[#state.calls], "-v"))
      backend.spawn(spec({ name = "b", layout = "float" }))
      assert.truthy(vim.tbl_contains(state.calls[#state.calls], "-h"))
      backend.spawn(spec({ name = "c", layout = "tab" }))
      assert.equals("new-window", state.calls[#state.calls][1])
    end)

    it("without focus the new pane is created detached (-d)", function()
      backend.spawn(spec({ focus = false }))
      assert.truthy(vim.tbl_contains(calls()[1], "-d"))
      assert.equals("%0", state.active)
    end)

    it("start_insert = false is not 'do not focus': the pane is still selected", function()
      backend.spawn(spec({ start_insert = false }))
      assert.is_false(vim.tbl_contains(calls()[1], "-d"))
      assert.equals("%1", state.active)
    end)

    it("a word that ends in ';' stays one word and starts no tmux command", function()
      backend.spawn(spec({ cmd = { "cat", "notes;", "run-shell", "touch /tmp/pwned" } }))
      assert.equals(1, #ran())
      assert.equals("split-window", ran()[1][1])
      assert.truthy(vim.tbl_contains(ran()[1], "notes;"))
      assert.truthy(vim.tbl_contains(ran()[1], "run-shell"))
    end)

    it("a directory ending in ';' stays the directory", function()
      backend.spawn(spec({ cwd = "/proj/odd;" }))
      assert.equals(1, #ran())
      local at
      for i, a in ipairs(ran()[1]) do
        if a == "-c" then
          at = i
        end
      end
      assert.equals("/proj/odd;", ran()[1][at + 1])
    end)

    it("an old tmux (before 3.1) gets -p <percent>, a new or unknown one -l <percent>%", function()
      local function size_args(version)
        local runner
        runner, state = fake()
        state.version = version
        tmux.new(registry_mod.new(), runner, "%0").spawn(spec())
        local split = vim.tbl_filter(function(c)
          return c[1] == "split-window"
        end, state.executed)[1]
        local i = vim.fn.index(split, "-h") + 1
        return split[i + 1], split[i + 2]
      end
      assert.same({ "-p", "30" }, { size_args("tmux 3.0a") })
      assert.same({ "-p", "30" }, { size_args("tmux 2.9") })
      assert.same({ "-l", "30%" }, { size_args("tmux 3.1") })
      assert.same({ "-l", "30%" }, { size_args("tmux next-3.5") })
      assert.same({ "-l", "30%" }, { size_args("tmux master") })
    end)

    it("asks for the version once, not on every spawn", function()
      backend.spawn(spec({ name = "a" }))
      backend.spawn(spec({ name = "b" }))
      local probes = vim.tbl_filter(function(c)
        return c[#c] == "-V"
      end, state.calls)
      assert.equals(1, #probes)
    end)

    it("refuses env, bad output and a failing tmux", function()
      local h, err = backend.spawn(spec({ env = { A = "1" } }))
      assert.is_nil(h)
      assert.truthy(err:find("environment", 1, true))
      local odd = tmux.new(registry, function()
        return { code = 0, stdout = "nope\n", stderr = "" }
      end, "%0")
      assert.is_nil((odd.spawn(spec())))
      local bad = tmux.new(registry, function()
        return { code = 1, stdout = "", stderr = "no server running" }
      end, "%0")
      local h2, err2 = bad.spawn(spec())
      assert.is_nil(h2)
      assert.truthy(err2:find("no server running", 1, true))
      assert.equals(0, registry:count())
    end)

    it("-L selects a private server", function()
      local runner
      runner, state = fake()
      local b = tmux.new(registry, runner, "%0", { socket = "spec" })
      b.spawn(spec())
      assert.same({ "-L", "spec", "-V" }, vim.list_slice(state.calls[1], 1, 3))
      assert.same({ "-L", "spec", "split-window" }, vim.list_slice(state.calls[2], 1, 3))
    end)
  end)

  describe("send", function()
    it("types literally and after --, so no word can be read as a key or option", function()
      local h = backend.spawn(spec())
      local ok = backend.send(h, "-l C-c Enter; kill-server")
      assert.is_true(ok)
      assert.same(
        { "send-keys", "-t", "%1", "-l", "--", "-l C-c Enter; kill-server" },
        state.calls[#state.calls]
      )
    end)

    it("a trailing ';' arrives as typed text, not as the end of the command", function()
      local h = backend.spawn(spec())
      for _, text in ipairs({ "select 1;", "find . -exec rm {} \\;", ";", "a;b;", "x\\\\;" }) do
        assert.is_true((backend.send(h, text)))
        assert.equals(text, state.keys[#state.keys], text)
      end
    end)

    it("refuses a NUL byte", function()
      local h = backend.spawn(spec())
      local ok, err = backend.send(h, "a\0b")
      assert.is_false(ok)
      assert.truthy(err:find("NUL", 1, true))
    end)
  end)

  describe("visibility, focus, hide, list, close", function()
    it("visible/focused follow the pane list; focus selects window and pane", function()
      local h = backend.spawn(spec())
      assert.is_true(backend.visible(h))
      assert.is_true(backend.focused(h))
      backend.hide(h)
      assert.equals("%0", state.active)
      assert.is_false(backend.focused(h))
      assert.is_true(backend.focus(h))
      assert.equals("%1", state.active)
      state.panes["%1"] = nil
      assert.is_false(backend.visible(h))
    end)

    it(
      "a failed list is 'unknown', not 'gone': visible is nil, the pane is not replaced",
      function()
        local h = backend.spawn(spec())
        state.list_fails = true
        assert.is_nil(backend.visible(h))
        assert.is_nil((backend.probe(h)))
        assert.is_false(backend.focused(h))
        state.list_fails = false
        assert.is_true(backend.visible(h))
      end
    )

    it("probe answers visible and focused with ONE list", function()
      local h = backend.spawn(spec())
      local before = #state.calls
      local p = backend.probe(h)
      assert.same({ visible = true, focused = true }, p)
      assert.equals(before + 1, #state.calls)
    end)

    it("focus and hide are one tmux process each", function()
      local h = backend.spawn(spec())
      local before = #state.calls
      backend.hide(h)
      backend.focus(h)
      assert.equals(before + 2, #state.calls)
    end)

    it("close with gone = true only forgets the handle: no process", function()
      local h = backend.spawn(spec())
      local before = #state.calls
      assert.is_true((backend.close(h, { gone = true })))
      assert.equals(before, #state.calls)
      assert.equals(0, registry:count())
    end)

    it("ping is one list and says whether tmux answers", function()
      local before = #state.calls
      assert.is_true((backend.ping()))
      assert.equals(before + 1, #state.calls)
      state.list_fails = true
      local up, err = backend.ping()
      assert.is_false(up)
      assert.truthy(err:find("timed out", 1, true))
      state.list_fails = false
    end)

    it("list asks tmux only when it owns a pane", function()
      assert.same({}, backend.list())
      assert.equals(0, #state.calls)
      backend.spawn(spec())
      local before = #state.calls
      backend.list()
      assert.equals(before + 1, #state.calls)
    end)

    it("close keeps the handle when the pane cannot be killed, and says so", function()
      local h = backend.spawn(spec())
      state.kill_fails = true
      local ok, err = backend.close(h)
      assert.is_false(ok)
      assert.truthy(err:find("cannot kill", 1, true))
      assert.equals(h, registry:get(h.id))
      state.kill_fails = false
      assert.is_true((backend.close(h)))
      assert.equals(0, registry:count())
    end)

    it("list forgets a pane that no longer exists", function()
      local a = backend.spawn(spec({ name = "a" }))
      backend.spawn(spec({ name = "b" }))
      state.panes[a.pane] = nil
      local names = vim.tbl_map(function(h)
        return h.name
      end, backend.list())
      assert.same({ "b" }, names)
    end)

    it("close kills the pane; closing twice is harmless", function()
      local h = backend.spawn(spec())
      assert.is_true(backend.close(h))
      assert.is_nil(state.panes[h.pane])
      assert.equals(0, registry:count())
      assert.is_true(backend.close(h))
    end)
  end)
end)

describe("terminal.backends.tmux (pure)", function()
  it("word: a trailing ';' gets a backslash, nothing else changes", function()
    assert.equals("a\\;", tmux.word("a;"))
    assert.equals("\\;", tmux.word(";"))
    assert.equals("a\\\\;", tmux.word("a\\;"))
    assert.equals("a;b", tmux.word("a;b"))
    assert.equals("plain", tmux.word("plain"))
    assert.equals("", tmux.word(""))
  end)

  it("parse_version reads tmux -V lines", function()
    assert.same({ 3, 4 }, { tmux.parse_version("tmux 3.4") })
    assert.same({ 3, 0 }, { tmux.parse_version("tmux 3.0a") })
    assert.same({ 3, 5 }, { tmux.parse_version("tmux next-3.5") })
    assert.is_nil((tmux.parse_version("tmux master")))
    assert.is_nil((tmux.parse_version("")))
  end)

  it("has_percent_size: 3.1 and later, unknown counts as new", function()
    assert.is_false(tmux.has_percent_size(3, 0))
    assert.is_false(tmux.has_percent_size(2, 9))
    assert.is_true(tmux.has_percent_size(3, 1))
    assert.is_true(tmux.has_percent_size(4, 0))
    assert.is_true(tmux.has_percent_size(nil, nil))
  end)
end)

describe("terminal.status.exporters.tmux", function()
  it("fields: the pane options for a dataset", function()
    local f = exporter.fields({
      mode = "i",
      file = "a.lua",
      branch = "main",
      e = 2,
      w = 1,
      rec = "q",
      mod = true,
    })
    assert.same({
      ["@terminal_mode"] = "i",
      ["@terminal_file"] = "a.lua",
      ["@terminal_branch"] = "main",
      ["@terminal_diag"] = "E2 W1",
      ["@terminal_rec"] = "q",
      ["@terminal_mod"] = "+",
    }, f)
    assert.equals("", exporter.fields({ mode = "n" })["@terminal_diag"])
    assert.equals("", exporter.fields({ mode = "n" })["@terminal_mod"])
  end)

  it("sets every field with one tmux command line; values are separate arguments", function()
    local argv = exporter._command(
      "%3",
      { ["@terminal_file"] = "a; kill-server.lua", ["@terminal_mode"] = "n" },
      false
    )
    assert.same({
      "tmux",
      "set-option",
      "-p",
      "-t",
      "%3",
      "@terminal_file",
      "a; kill-server.lua",
      ";",
      "set-option",
      "-p",
      "-t",
      "%3",
      "@terminal_mode",
      "n",
    }, argv)
  end)

  it("a value that ends in ';' is escaped so tmux keeps it", function()
    local argv = exporter._command("%3", { ["@terminal_branch"] = "feature;" }, false)
    assert.equals("feature\\;", argv[7])
  end)

  it(
    "key: only what the pane options carry (cwd, ft, info and hint counts do not count)",
    function()
      local base =
        { mode = "n", file = "a.lua", branch = "main", e = 1, w = 0, rec = "", mod = false }
      local key = exporter.key(base)
      local noise = { cwd = "/x", ft = "lua", i = 4, h = 9 }
      assert.equals(key, exporter.key(vim.tbl_extend("force", base, noise)))
      assert.are_not.equal(key, exporter.key(vim.tbl_extend("force", base, { mode = "i" })))
      assert.are_not.equal(key, exporter.key(vim.tbl_extend("force", base, { e = 2 })))
      assert.are_not.equal(key, exporter.key(vim.tbl_extend("force", base, { branch = "dev" })))
    end
  )

  it("available refuses a Neovim inside another LIVE Neovim's terminal ($NVIM)", function()
    local saved = exporter.alive
    exporter.alive = function()
      return true
    end
    local env = { TMUX = "/tmp/tmux-1/default,1,0", TMUX_PANE = "%1" }
    assert.is_true((exporter.available(env)))
    local nested = vim.tbl_extend("force", env, { NVIM = "/tmp/nvim.sock" })
    local ok, why = exporter.available(nested)
    exporter.alive = saved
    assert.is_false(ok)
    assert.truthy(why:find("NVIM", 1, true))
  end)

  it(
    "a $NVIM that points to a dead Neovim is no outer Neovim (tmux server started from a terminal)",
    function()
      -- a tmux server started inside a Neovim terminal hands $NVIM to every pane for good
      local env = {
        TMUX = "/tmp/tmux-1/default,1,0",
        TMUX_PANE = "%1",
        NVIM = vim.fn.tempname() .. "-gone.sock",
      }
      assert.is_false(exporter.alive(env.NVIM))
      assert.is_true((exporter.available(env)))
    end
  )

  --- A Neovim server in ANOTHER process. (Inside one process a server answers on any connect mode,
  --- so a check against `serverstart()` cannot tell a wrong mode from a right one.)
  ---@param address string
  ---@return integer job
  local function outer_neovim(address)
    local job = vim.fn.jobstart({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "--listen",
      address,
    })
    vim.wait(8000, function()
      return exporter.alive(address)
    end, 50)
    return job
  end

  local function free_port()
    local server = vim.uv.new_tcp()
    server:bind("127.0.0.1", 0)
    local port = server:getsockname().port
    server:close()
    return port
  end

  it("alive: a Neovim in another process answers on a unix socket / named pipe", function()
    local address = vim.fn.has("win32") == 1
        and ("\\\\.\\pipe\\terminal-nvim-spec-" .. vim.uv.os_getpid())
      or (vim.fn.tempname() .. ".sock")
    local job = outer_neovim(address)
    local up = exporter.alive(address)
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 3000)
    assert.is_true(up)
    assert.is_false(exporter.alive(address), "stopped: nobody answers")
  end)

  it(
    "alive: a Neovim in another process listening on TCP (--listen host:port) answers too",
    function()
      local address = "127.0.0.1:" .. free_port()
      local job = outer_neovim(address)
      local up = exporter.alive(address)
      vim.fn.jobstop(job)
      vim.fn.jobwait({ job }, 3000)
      assert.is_true(up, "judged dead: sockconnect needs the tcp mode for host:port")
      assert.is_false(exporter.alive(address), "stopped: nobody answers")
    end
  )

  it("nested: a running outer Neovim counts only when it is an ancestor of this process", function()
    local saved_alive, saved_parent = exporter.alive, exporter.parent_of
    exporter.alive = function()
      return true
    end
    local me = vim.uv.os_getpid()
    local parents = { [me] = 500, [500] = 400, [400] = 1 }
    exporter.parent_of = function(pid)
      return parents[pid]
    end
    local ok, err = pcall(function()
      assert.is_true(
        exporter.nested("/run/user/1/nvim.400.0"),
        "an ancestor: this Neovim is nested"
      )
      assert.is_false(
        exporter.nested("/run/user/1/nvim.999.0"),
        "running but not an ancestor (a tmux server that was started from its terminal): owns its pane"
      )
      assert.is_true(exporter.nested("127.0.0.1:6666"), "an address without a pid: assume nested")
      exporter.parent_of = function()
        return nil
      end
      assert.is_true(exporter.nested("/run/user/1/nvim.400.0"), "chain unreadable: assume nested")
      exporter.alive = function()
        return false
      end
      assert.is_false(exporter.nested("/run/user/1/nvim.400.0"), "outer Neovim gone")
    end)
    exporter.alive, exporter.parent_of = saved_alive, saved_parent
    assert(ok, err)
  end)

  it(
    "nested: available refuses an ancestor and accepts a Neovim that merely shares $NVIM",
    function()
      local saved_alive, saved_parent = exporter.alive, exporter.parent_of
      exporter.alive = function()
        return true
      end
      local me = vim.uv.os_getpid()
      exporter.parent_of = function(pid)
        return pid == me and 400 or 1
      end
      local env = { TMUX = "/tmp/tmux-1/default,1,0", TMUX_PANE = "%1" }
      local nested =
        exporter.available(vim.tbl_extend("force", env, { NVIM = "/run/user/1/nvim.400.0" }))
      local owner =
        exporter.available(vim.tbl_extend("force", env, { NVIM = "/run/user/1/nvim.777.0" }))
      exporter.alive, exporter.parent_of = saved_alive, saved_parent
      assert.is_false(nested)
      assert.is_true(owner)
    end
  )

  it("parent_of agrees with the OS where it can read the process tree", function()
    local parent = exporter.parent_of(vim.uv.os_getpid())
    -- nil where the tree cannot be read (Windows); the real parent everywhere else
    assert.is_true(parent == nil or parent == vim.uv.os_getppid(), tostring(parent))
  end)

  it("ready needs an attached UI (a headless run leaves the pane alone)", function()
    assert.equals(#vim.api.nvim_list_uis() > 0, exporter.ready())
  end)

  it("clear touches the pane only when this instance published", function()
    local saved_run, saved_pane = exporter.run, vim.env.TMUX_PANE
    vim.env.TMUX_PANE = "%9"
    local runs = 0
    exporter.run = function()
      runs = runs + 1
      return { code = 0, stderr = "" }
    end
    exporter.clear()
    assert.equals(0, runs)
    exporter.publish(vim.json.encode({ mode = "n" }))
    assert.equals(1, runs)
    exporter.clear()
    assert.equals(2, runs)
    exporter.clear()
    assert.equals(2, runs)
    exporter.run, vim.env.TMUX_PANE = saved_run, saved_pane
  end)

  it("a publish that fails half-way still counts as published (so clear cleans up)", function()
    local saved_run, saved_pane = exporter.run, vim.env.TMUX_PANE
    vim.env.TMUX_PANE = "%9"
    local seen = {}
    exporter.run = function(argv)
      seen[#seen + 1] = argv
      return { code = #seen == 1 and 1 or 0, stderr = "boom" }
    end
    assert.is_false((exporter.publish(vim.json.encode({ mode = "n" }))))
    exporter.clear()
    assert.equals(2, #seen)
    exporter.run, vim.env.TMUX_PANE = saved_run, saved_pane
  end)

  it("clear unsets instead of setting", function()
    local argv = exporter._command("%3", { ["@terminal_mode"] = "" }, true)
    assert.same({ "tmux", "set-option", "-p", "-u", "-t", "%3", "@terminal_mode" }, argv)
  end)

  it("publish runs the command with the pane from $TMUX_PANE and reports a failure", function()
    local saved_run, saved_pane = exporter.run, vim.env.TMUX_PANE
    local seen
    vim.env.TMUX_PANE = "%9"
    exporter.run = function(argv)
      seen = argv
      return { code = 0, stderr = "" }
    end
    assert.is_true((exporter.publish(vim.json.encode({ mode = "n", file = "x" }))))
    assert.equals("%9", seen[5])
    exporter.run = function()
      return { code = 1, stderr = "no server" }
    end
    local ok, err = exporter.publish(vim.json.encode({ mode = "n" }))
    assert.is_false(ok)
    assert.equals("no server", err)
    assert.is_false((exporter.publish("not json")))
    exporter.run, vim.env.TMUX_PANE = saved_run, saved_pane
  end)
end)

describe("terminal facade with the tmux backend", function()
  local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/]") or "."
  local jobs = dofile(here .. "/support/jobs.lua")
  local terminal, state
  local saved = {}

  ---@param extra? table
  local function boot(extra)
    for _, mod in ipairs({ "terminal", "terminal.config", "terminal.bindings", "terminal.status" }) do
      package.loaded[mod] = nil
    end
    local runner
    runner, state = fake()
    tmux.default_runner = runner
    terminal = require("terminal")
    terminal.setup(vim.tbl_extend("force", {
      backend = "tmux",
      layout = "vsplit",
      shell = { "sh" },
      commands = false,
      keymaps = { preset = false },
      status = { enable = false },
      navigate = { handoff = false },
    }, extra or {}))
  end

  before_each(function()
    saved.env = { TMUX = vim.env.TMUX, TMUX_PANE = vim.env.TMUX_PANE }
    saved.executable = vim.fn.executable
    saved.runner = tmux.default_runner
    vim.env.TMUX, vim.env.TMUX_PANE = "/tmp/tmux-1/default,1,0", "%0"
    vim.fn.executable = function(name)
      if name == "tmux" then
        return 1
      end
      return saved.executable(name)
    end
  end)

  after_each(function()
    for _, h in ipairs(terminal and terminal.list(true) or {}) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.env.TMUX, vim.env.TMUX_PANE = saved.env.TMUX, saved.env.TMUX_PANE
    vim.fn.executable = saved.executable
    tmux.default_runner = saved.runner
  end)

  local function count(sub)
    return #vim.tbl_filter(function(c)
      return c[1] == sub or c[#c] == sub
    end, state.calls)
  end

  it("is chosen when named and available", function()
    boot()
    assert.equals("tmux", terminal.status().backend)
  end)

  it("a failed list does not replace a live pane", function()
    boot()
    local first = terminal.open()
    state.list_fails = true
    terminal.toggle()
    local again = terminal.open()
    state.list_fails = false
    assert.equals(first, again)
    assert.equals(first, terminal.list()[1])
    assert.equals(1, #vim.tbl_filter(function(c)
      return c[1] == "split-window"
    end, state.calls))
    assert.equals(0, #vim.tbl_filter(function(c)
      return c[1] == "kill-pane"
    end, state.calls))
  end)

  it("toggle on a pane the user closed asks once, then splits (no kill, no second list)", function()
    boot()
    local first = terminal.open()
    state.panes[first.pane] = nil
    local before = #state.calls
    terminal.toggle()
    local subs = {}
    for i = before + 1, #state.calls do
      subs[#subs + 1] = state.calls[i][1]
    end
    assert.same({ "list-panes", "split-window" }, subs)
  end)

  it(
    "pin with an env the pane cannot take is refused before the native terminal is touched",
    function()
      boot({ backend = "auto", env = { FOO = "1" }, shell = jobs.sleeper() })
      local native = terminal.open({ name = "work", layout = "vsplit" })
      jobs.settle()
      local ok, err = terminal.pin({ name = "work" }, { backend = "tmux" })
      assert.is_false(ok)
      assert.truthy(err:find("environment", 1, true))
      assert.is_true(vim.api.nvim_buf_is_valid(native.bufnr))
      assert.equals(0, count("split-window"))
    end
  )

  it("pin refuses before ending the terminal when tmux does not answer", function()
    boot({ backend = "auto", shell = jobs.sleeper() })
    local native = terminal.open({ name = "work", layout = "vsplit" })
    jobs.settle()
    state.list_fails = true
    local ok, err = terminal.pin({ name = "work" }, { backend = "tmux" })
    state.list_fails = false
    assert.is_false(ok)
    assert.truthy(err:find("timed out", 1, true))
    assert.is_true(vim.api.nvim_buf_is_valid(native.bufnr))
    assert.equals(native, terminal.list()[1])
  end)

  it("run quotes only portable words in a pane whose shell is unknown", function()
    boot({ shell = "" })
    local original_notify = vim.notify
    vim.notify = function() end
    local ok, err = terminal.run({ "echo", "$(calc.exe)" }, { name = "other" })
    vim.notify = original_notify
    assert.is_false(ok)
    assert.truthy(err:find("default shell", 1, true))
    assert.is_true((terminal.run({ "git", "status", "--short" }, { name = "other" })))
    assert.equals("git status --short", (state.keys[#state.keys]:gsub("[\r\n]+$", "")))
  end)
end)
