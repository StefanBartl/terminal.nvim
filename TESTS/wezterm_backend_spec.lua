---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/wezterm_backend_spec.lua -- the wezterm backend against a fake `wezterm cli`.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local registry_mod = require("terminal.core.registry")
local wezterm = require("terminal.backends.wezterm")

local fake = dofile(
  (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/fakes.lua"
).wezterm

describe("terminal.backends.wezterm", function()
  local registry, backend, state

  before_each(function()
    registry = registry_mod.new()
    local runner
    runner, state = fake()
    backend = wezterm.new(registry, runner, "7")
  end)

  ---@param over? table
  ---@return Terminal.SpawnSpec
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

  describe("available", function()
    it("needs $WEZTERM_PANE", function()
      local ok, why = wezterm.available({})
      assert.is_false(ok)
      assert.truthy(why:find("WEZTERM_PANE", 1, true))
    end)
  end)

  describe("spawn", function()
    it("splits to the right for vsplit, with percent, cwd and the command after --", function()
      local h = backend.spawn(spec())
      assert.equals("8", h.pane)
      assert.equals("wezterm", h.backend)
      assert.same({
        "split-pane",
        "--pane-id",
        "7",
        "--right",
        "--percent",
        "30",
        "--cwd",
        "/proj",
        "--",
        "make",
        "test",
      }, state.calls[1].argv)
      assert.equals(h, registry:get("/proj::t1"))
    end)

    it("maps split to --bottom, float to a right split, tab to spawn", function()
      backend.spawn(spec({ name = "a", layout = "split" }))
      assert.truthy(vim.tbl_contains(state.calls[#state.calls].argv, "--bottom"))
      backend.spawn(spec({ name = "b", layout = "float" }))
      assert.truthy(vim.tbl_contains(state.calls[#state.calls].argv, "--right"))
      backend.spawn(spec({ name = "c", layout = "tab" }))
      assert.equals("spawn", state.calls[#state.calls].argv[1])
    end)

    it("starts the default shell when there is no command", function()
      backend.spawn(spec({ cmd = "" }))
      assert.is_false(vim.tbl_contains(state.calls[1].argv, "--"))
    end)

    it("keeps argv words that look like options after the --", function()
      backend.spawn(spec({ cmd = { "git", "log", "--oneline", "--cwd=x" } }))
      local argv = state.calls[1].argv
      local dash = vim.fn.index(argv, "--")
      assert.same({ "git", "log", "--oneline", "--cwd=x" }, vim.list_slice(argv, dash + 2))
    end)

    it("without focus, hands focus back to Neovim's own pane", function()
      backend.spawn(spec({ focus = false }))
      assert.same({ "activate-pane", "--pane-id", "7" }, state.calls[2].argv)
      assert.equals("7", state.active)
    end)

    it("start_insert = false is not 'do not focus': the new pane keeps the focus", function()
      backend.spawn(spec({ start_insert = false }))
      assert.equals(1, #state.calls)
      assert.equals("8", state.active)
    end)

    it("refuses environment variables: wezterm cli has no way to set them", function()
      local h, err = backend.spawn(spec({ env = { A = "1" } }))
      assert.is_nil(h)
      assert.truthy(err:find("environment", 1, true))
      assert.same({}, state.calls)
    end)

    it("reports a failing wezterm cli with its stderr, registering nothing", function()
      local failing = wezterm.new(registry, function()
        return { code = 1, stdout = "", stderr = "no such domain" }
      end, "7")
      local h, err = failing.spawn(spec())
      assert.is_nil(h)
      assert.truthy(err:find("no such domain", 1, true))
      assert.equals(0, registry:count())
    end)

    it("refuses output that is not a pane id", function()
      local odd = wezterm.new(registry, function()
        return { code = 0, stdout = "hello\n", stderr = "" }
      end, "7")
      local h, err = odd.spawn(spec())
      assert.is_nil(h)
      assert.truthy(err:find("unexpected output", 1, true))
    end)
  end)

  describe("send", function()
    it("types the text through stdin, never as an argument", function()
      local h = backend.spawn(spec())
      local ok = backend.send(h, "rm -rf --no-preserve-root /\n")
      assert.is_true(ok)
      local call = state.calls[#state.calls]
      assert.same({ "send-text", "--pane-id", "8", "--no-paste" }, call.argv)
      assert.equals("rm -rf --no-preserve-root /\n", call.stdin)
    end)

    it("returns the error when the pane is gone", function()
      local gone = wezterm.new(registry, function()
        return { code = 1, stdout = "", stderr = "pane not found" }
      end, "7")
      local ok, err = gone.send({ pane = "99" }, "x")
      assert.is_false(ok)
      assert.truthy(err:find("pane not found", 1, true))
    end)
  end)

  describe("visibility, focus, hide", function()
    it("visible and focused follow the pane list", function()
      local h = backend.spawn(spec())
      assert.is_true(backend.visible(h))
      assert.is_true(backend.focused(h)) -- a new pane is active
      backend.focus({ pane = "7" })
      assert.is_false(backend.focused(h))
      state.panes["8"] = nil
      assert.is_false(backend.visible(h))
    end)

    it("focus activates the pane; hide returns focus to Neovim's pane", function()
      local h = backend.spawn(spec())
      backend.hide(h)
      assert.equals("7", state.active)
      assert.is_true(backend.focus(h))
      assert.equals("8", state.active)
    end)

    it("a pane in another tab is focused only when the client's focus is in it", function()
      -- `is_active` is "active within ITS tab": the terminal tab's pane says true even while the
      -- user looks at Neovim's tab, so the client's focused pane has to decide.
      local h = backend.spawn(spec({ layout = "tab" }))
      assert.is_true(backend.focused(h)) -- the new tab is in front
      backend.hide(h) -- back to Neovim's pane (and tab)
      assert.equals("7", state.active)
      assert.is_true(state.tab_active[2] == h.pane) -- the tab's own active pane is still it
      assert.is_false(backend.focused(h))
      assert.is_true(backend.visible(h))
    end)

    it("a failed list is 'unknown', not 'gone': visible is nil", function()
      local h = backend.spawn(spec())
      state.list_fails = true
      assert.is_nil(backend.visible(h))
      assert.is_nil((backend.probe(h)))
      assert.is_false(backend.focused(h))
      state.list_fails = false
      assert.is_true(backend.visible(h))
    end)

    it("probe answers visible and focused with ONE list for a pane in Neovim's tab", function()
      local h = backend.spawn(spec())
      local before = #state.calls
      assert.same({ visible = true, focused = true }, backend.probe(h))
      assert.equals(before + 1, #state.calls)
    end)
  end)

  describe("list and close", function()
    it("list forgets a pane that no longer exists", function()
      local a = backend.spawn(spec({ name = "a" }))
      local b = backend.spawn(spec({ name = "b" }))
      state.panes[a.pane] = nil
      local names = vim.tbl_map(function(h)
        return h.name
      end, backend.list())
      assert.same({ "b" }, names)
      assert.is_nil(registry:get(a.id))
      assert.is_not_nil(registry:get(b.id))
    end)

    it("close kills the pane and removes the terminal; closing twice is harmless", function()
      local h = backend.spawn(spec())
      assert.is_true(backend.close(h))
      assert.is_nil(state.panes[h.pane])
      assert.equals(0, registry:count())
      assert.is_true(backend.close(h))
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

    it("a command string is split on any run of white space, empty pieces are dropped", function()
      backend.spawn(spec({ cmd = "  pwsh \t -NoLogo   -NoProfile  " }))
      local argv = state.calls[#state.calls].argv
      local dash = vim.fn.index(argv, "--")
      assert.same({ "pwsh", "-NoLogo", "-NoProfile" }, vim.list_slice(argv, dash + 2))
    end)

    it(
      "white space plus a path separator: split unless the string is an executable as it stands",
      function()
        local original = vim.fn.executable
        local executables = {}
        vim.fn.executable = function(name)
          if executables[name] then
            return 1
          end
          return original(name)
        end
        local function argv_of(cmd, executable)
          executables = executable and { [cmd] = true } or {}
          backend.spawn(spec({ name = cmd, cmd = cmd }))
          local argv = state.calls[#state.calls].argv
          return vim.list_slice(argv, vim.fn.index(argv, "--") + 2)
        end
        -- not an executable: the separator alone does not keep it in one piece
        assert.same({ "pwsh", "-File", "C:/x/y.ps1" }, argv_of("pwsh -File C:/x/y.ps1", false))
        assert.same({ "git", "-C", "/tmp/a", "status" }, argv_of("git -C /tmp/a status", false))
        -- an executable with a space in its path: one word, with either kind of separator
        assert.same({ "/opt/my tools/x" }, argv_of("/opt/my tools/x", true))
        assert.same(
          { "C:/Program Files/PowerShell/7/pwsh.exe" },
          argv_of("C:/Program Files/PowerShell/7/pwsh.exe", true)
        )
        vim.fn.executable = original
      end
    )

    it("the PATH scan is not paid for a string without a path separator", function()
      local looked = {}
      local original = vim.fn.executable
      vim.fn.executable = function(name)
        looked[#looked + 1] = name
        return original(name)
      end
      backend.spawn(spec({ name = "a", cmd = "pwsh -NoLogo" }))
      backend.spawn(spec({ name = "b", cmd = "pwsh" }))
      vim.fn.executable = original
      assert.same({}, looked)
    end)

    it("close with gone = true only forgets the handle: no process", function()
      local h = backend.spawn(spec())
      local before = #state.calls
      assert.is_true((backend.close(h, { gone = true })))
      assert.equals(before, #state.calls)
      assert.equals(0, registry:count())
    end)

    it("ping is one list and says whether the mux answers", function()
      local before = #state.calls
      assert.is_true((backend.ping()))
      assert.equals(before + 1, #state.calls)
      state.list_fails = true
      local up, err = backend.ping()
      assert.is_false(up)
      assert.truthy(err:find("timed out", 1, true))
      state.list_fails = false
    end)

    it("a command string that is an executable as it stands is kept in one piece", function()
      local original = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "C:\\Program Files\\PowerShell\\7\\pwsh.exe" then
          return 1
        end
        return original(name)
      end
      backend.spawn(spec({ cmd = "C:\\Program Files\\PowerShell\\7\\pwsh.exe" }))
      vim.fn.executable = original
      local argv = state.calls[#state.calls].argv
      local dash = vim.fn.index(argv, "--")
      assert.same({ "C:\\Program Files\\PowerShell\\7\\pwsh.exe" }, vim.list_slice(argv, dash + 2))
    end)

    it("list asks wezterm only when it owns a pane", function()
      assert.same({}, backend.list())
      assert.equals(0, #state.calls)
      backend.spawn(spec())
      local before = #state.calls
      backend.list()
      assert.equals(before + 1, #state.calls)
    end)
  end)
end)

describe("terminal facade with the wezterm backend", function()
  local terminal, state
  local saved = {}

  before_each(function()
    for _, mod in ipairs({ "terminal", "terminal.config", "terminal.bindings", "terminal.status" }) do
      package.loaded[mod] = nil
    end
    local runner
    runner, state = fake()
    saved.env = vim.env.WEZTERM_PANE
    saved.executable = vim.fn.executable
    saved.runner = wezterm.default_runner
    vim.env.WEZTERM_PANE = "7"
    vim.fn.executable = function(name)
      if name == "wezterm" then
        return 1
      end
      return saved.executable(name)
    end
    wezterm.default_runner = runner
    terminal = require("terminal")
    terminal.setup({
      backend = "wezterm",
      layout = "vsplit",
      shell = { "pwsh" },
      commands = false,
      keymaps = { preset = false },
      status = { enable = false },
    })
  end)

  after_each(function()
    vim.env.WEZTERM_PANE = saved.env
    vim.fn.executable = saved.executable
    wezterm.default_runner = saved.runner
  end)

  it("is chosen when named and available", function()
    assert.equals("wezterm", terminal.status().backend)
  end)

  it("open creates a pane; a second open focuses it instead of creating another", function()
    local h = terminal.open()
    assert.equals("wezterm", h.backend)
    local before = #state.calls
    terminal.open()
    local subs = vim.tbl_map(function(c)
      return c.argv[1]
    end, vim.list_slice(state.calls, before + 1))
    assert.is_false(vim.tbl_contains(subs, "split-pane"))
  end)

  it("replaces a pane the user closed instead of failing to show it", function()
    local first = terminal.open()
    state.panes[first.pane] = nil
    local second = terminal.open()
    assert.not_equals(first.pane, second.pane)
    assert.equals(1, #terminal.list())
  end)

  it("toggle on the focused pane gives focus back to Neovim", function()
    terminal.open()
    terminal.toggle()
    assert.equals("7", state.active)
  end)

  it(
    "toggle focuses a pane that is visible elsewhere, and does not start Insert mode in Neovim",
    function()
      -- `:startinsert` only takes effect when control returns to the main loop, so mode() right after
      -- the call cannot tell: count the calls instead.
      local starts = 0
      local original = vim.cmd
      vim.cmd = function(command, ...)
        if command == "startinsert" then
          starts = starts + 1
        end
        return original(command, ...)
      end
      local ok, err = pcall(function()
        terminal.open()
        terminal.toggle() -- focus back to Neovim's pane
        assert.equals("7", state.active)
        starts = 0
        terminal.toggle()
        assert.equals("8", state.active)
      end)
      vim.cmd = original
      assert(ok, err)
      assert.equals(
        0,
        starts,
        "a multiplexer pane takes its own input; Neovim stays in Normal mode"
      )
    end
  )

  it("toggle on a pane the user closed costs ONE list and starts a new pane", function()
    local first = terminal.open()
    state.panes[first.pane] = nil
    local before = #state.calls
    terminal.toggle()
    local subs = {}
    for i = before + 1, #state.calls do
      subs[#subs + 1] = state.calls[i].argv[1]
    end
    assert.same({ "list", "split-pane" }, subs)
  end)

  it("toggle costs ONE list, open on a visible pane too", function()
    terminal.open()
    local function lists(from)
      local n = 0
      for i = from + 1, #state.calls do
        if state.calls[i].argv[1] == "list" then
          n = n + 1
        end
      end
      return n
    end
    local before = #state.calls
    terminal.toggle()
    assert.equals(1, lists(before))
    before = #state.calls
    terminal.open()
    assert.equals(1, lists(before))
  end)

  it("a failed list does not replace a live pane", function()
    local first = terminal.open()
    state.list_fails = true
    terminal.toggle()
    local again = terminal.open()
    state.list_fails = false
    assert.is_not_nil(state.panes[first.pane])
    assert.equals(1, #terminal.list())
    -- the same pane, not a second one next to it: "gone" would have spawned a replacement
    assert.equals(first, again)
    assert.equals(first, terminal.list()[1])
    local function count(sub)
      return #vim.tbl_filter(function(c)
        return c.argv[1] == sub
      end, state.calls)
    end
    assert.equals(1, count("split-pane"))
    assert.equals(0, count("kill-pane"))
  end)

  it(
    "run --direct does not start a second pane under the name of one it could not close",
    function()
      local first = terminal.open({ name = "build" })
      state.kill_fails = true
      local ok, err = terminal.run({ "make" }, { direct = true, name = "build" })
      state.kill_fails = false
      assert.is_false(ok)
      assert.truthy(err:find("cannot replace", 1, true), err)
      assert.equals(first, terminal.list()[1])
      local splits = vim.tbl_filter(function(c)
        return c.argv[1] == "split-pane"
      end, state.calls)
      assert.equals(1, #splits)
    end
  )

  it(
    "a shell given as a string with arguments is split for the pane (no shell sits in between)",
    function()
      terminal.setup({
        backend = "wezterm",
        layout = "vsplit",
        shell = "pwsh -NoLogo",
        commands = false,
        keymaps = { preset = false },
        status = { enable = false },
      })
      terminal.open({ name = "str" })
      local split
      for _, c in ipairs(state.calls) do
        if c.argv[1] == "split-pane" then
          split = c.argv
        end
      end
      local dash = vim.fn.index(split, "--")
      assert.same({ "pwsh", "-NoLogo" }, vim.list_slice(split, dash + 2))
    end
  )

  it("start_insert = false still focuses the pane it opens", function()
    terminal.setup({
      backend = "wezterm",
      layout = "vsplit",
      shell = { "pwsh" },
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
      status = { enable = false },
    })
    local h = terminal.open()
    assert.equals(h.pane, state.active)
  end)

  it("run quotes for the configured shell; without one only portable words go through", function()
    local original_notify = vim.notify
    vim.notify = function() end
    local function typed()
      for i = #state.calls, 1, -1 do
        if state.calls[i].argv[1] == "send-text" then
          return (state.calls[i].stdin:gsub("[\r\n]+$", ""))
        end
      end
    end
    -- shell = pwsh is configured: words are quoted for PowerShell
    assert.is_true((terminal.run({ "echo", "a b", "$(calc.exe)" })))
    assert.equals("echo 'a b' '$(calc.exe)'", typed())

    -- no shell configured: the pane runs WezTerm's default shell, which is unknown here
    terminal.setup({
      backend = "wezterm",
      layout = "vsplit",
      commands = false,
      keymaps = { preset = false },
      status = { enable = false },
    })
    local ok, err = terminal.run({ "echo", "$(calc.exe)" }, { name = "other" })
    assert.is_false(ok)
    assert.truthy(err:find("default shell", 1, true))
    assert.is_true((terminal.run({ "git", "status", "--short" }, { name = "other" })))
    assert.equals("git status --short", typed())
    vim.notify = original_notify
  end)

  it("send types into the pane", function()
    terminal.send("ls", { newline = true })
    local last = state.calls[#state.calls]
    assert.equals("send-text", last.argv[1])
    assert.truthy(last.stdin:find("^ls"))
  end)
end)
