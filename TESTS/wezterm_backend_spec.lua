---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/wezterm_backend_spec.lua -- the wezterm backend against a fake `wezterm cli`.

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
      backend.spawn(spec({ start_insert = false }))
      assert.same({ "activate-pane", "--pane-id", "7" }, state.calls[2].argv)
      assert.equals("7", state.active)
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

  it("send types into the pane", function()
    terminal.send("ls", { newline = true })
    local last = state.calls[#state.calls]
    assert.equals("send-text", last.argv[1])
    assert.truthy(last.stdin:find("^ls"))
  end)
end)
