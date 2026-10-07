---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/tmux_backend_spec.lua -- the tmux backend and status exporter against a fake `tmux`.

local registry_mod = require("terminal.core.registry")
local tmux = require("terminal.backends.tmux")
local exporter = require("terminal.status.exporters.tmux")

--- A fake tmux: panes with ids `%N`, one active pane, every call recorded.
local function fake()
  local state = {
    calls = {},
    panes = { ["%0"] = true },
    active = "%0",
    next_id = 1,
  }
  local function run(argv)
    state.calls[#state.calls + 1] = vim.list_slice(argv, 2)
    local sub = argv[2]
    if sub == "-L" then
      sub = argv[4]
    end
    if sub == "split-window" or sub == "new-window" then
      local id = "%" .. state.next_id
      state.next_id = state.next_id + 1
      state.panes[id] = true
      if not vim.tbl_contains(argv, "-d") then
        state.active = id
      end
      return { code = 0, stdout = id .. "\n", stderr = "" }
    elseif sub == "list-panes" then
      local lines = {}
      for id in pairs(state.panes) do
        lines[#lines + 1] = ("%s %d 1"):format(id, state.active == id and 1 or 0)
      end
      return { code = 0, stdout = table.concat(lines, "\n") .. "\n", stderr = "" }
    elseif sub == "select-pane" or sub == "select-window" then
      local target = argv[#argv]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      if sub == "select-pane" then
        state.active = target
      end
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "kill-pane" then
      local target = argv[#argv]
      if not state.panes[target] then
        return { code = 1, stdout = "", stderr = "can't find pane: " .. target }
      end
      state.panes[target] = nil
      return { code = 0, stdout = "", stderr = "" }
    elseif sub == "send-keys" then
      return { code = 0, stdout = "", stderr = "" }
    end
    return { code = 1, stdout = "", stderr = "unknown command " .. tostring(sub) }
  end
  return run, state
end

describe("terminal.backends.tmux", function()
  local registry, backend, state

  before_each(function()
    registry = registry_mod.new()
    local runner
    runner, state = fake()
    backend = tmux.new(registry, runner, "%0")
  end)

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
        "make",
        "test",
      }, state.calls[1])
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
      backend.spawn(spec({ start_insert = false }))
      assert.truthy(vim.tbl_contains(state.calls[1], "-d"))
      assert.equals("%0", state.active)
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
      assert.same({ "-L", "spec", "split-window" }, vim.list_slice(state.calls[1], 1, 3))
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
