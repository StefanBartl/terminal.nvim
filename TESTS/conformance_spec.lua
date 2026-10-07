---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/conformance_spec.lua -- the contract EVERY backend must keep, run against each one:
-- native (real windows and jobs), wezterm and tmux (fake CLIs, see support/fakes.lua). A new
-- backend adds one `contract(...)` call.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")
local fakes = dofile(here .. "/support/fakes.lua")

local registry_mod = require("terminal.core.registry")

---@class Terminal.ConformanceContext
---@field backend Terminal.Backend
---@field registry Terminal.Registry
---@field spec fun(over?: table): Terminal.SpawnSpec
---@field send fun(handle: Terminal.Handle, text: string): boolean, string|nil
---@field failing fun(): Terminal.Backend, Terminal.SpawnSpec A backend + spec whose spawn must fail
---@field cleanup fun()

---@param name string
---@param make fun(): Terminal.ConformanceContext
local function contract(name, make)
  describe("backend contract: " .. name, function()
    local ctx

    before_each(function()
      ctx = make()
    end)

    after_each(function()
      ctx.cleanup()
    end)

    it("has a name, optional abilities and a boolean availability answer", function()
      assert.equals(name, ctx.backend.name)
      assert.is_table(ctx.backend.caps)
      local ok, reason = ctx.backend.available({})
      assert.is_boolean(ok)
      if not ok then
        assert.is_string(reason)
      end
    end)

    it("spawn returns a handle registered under <root>::<name>", function()
      local h, err = ctx.backend.spawn(ctx.spec())
      assert.is_nil(err)
      assert.equals(registry_mod.make_id("/proj", "t1"), h.id)
      assert.equals("t1", h.name)
      assert.equals("/proj", h.root)
      assert.equals(name, h.backend)
      assert.equals(h, ctx.registry:get(h.id))
    end)

    it("a spawned terminal is listed and visible", function()
      local h = ctx.backend.spawn(ctx.spec())
      local ids = vim.tbl_map(function(x)
        return x.id
      end, ctx.backend.list())
      assert.same({ h.id }, ids)
      assert.is_true(ctx.backend.visible(h))
    end)

    it("send succeeds for a live terminal", function()
      local h = ctx.backend.spawn(ctx.spec())
      local ok, err = ctx.send(h, "echo hi\n")
      assert.is_true(ok, err)
    end)

    it("focus succeeds for a visible terminal", function()
      local h = ctx.backend.spawn(ctx.spec())
      local ok, err = ctx.backend.focus(h)
      assert.is_true(ok, err)
    end)

    it("two terminals with different names coexist", function()
      local a = ctx.backend.spawn(ctx.spec({ name = "a" }))
      jobs.settle()
      local b = ctx.backend.spawn(ctx.spec({ name = "b" }))
      assert.not_equals(a.id, b.id)
      assert.equals(2, #ctx.backend.list())
    end)

    it(
      "close removes the terminal from the registry and the list; closing again is harmless",
      function()
        local h = ctx.backend.spawn(ctx.spec())
        jobs.settle()
        assert.is_true((ctx.backend.close(h)))
        assert.is_nil(ctx.registry:get(h.id))
        assert.same({}, ctx.backend.list())
        assert.is_true((ctx.backend.close(h)))
      end
    )

    it("a failed spawn returns nil and an error and registers nothing", function()
      local b, spec = ctx.failing()
      local h, err = b.spawn(spec)
      assert.is_nil(h)
      assert.is_string(err)
      assert.equals(0, ctx.registry:count())
    end)

    it("refuses a layout it does not know without registering anything", function()
      local h, err = ctx.backend.spawn(ctx.spec({ layout = "sideways" }))
      -- Multiplexer backends map unknown layouts to a split; native refuses. Either way: no
      -- half-registered terminal for an error.
      if h == nil then
        assert.is_string(err)
        assert.equals(0, ctx.registry:count())
      else
        assert.equals(h, ctx.registry:get(h.id))
      end
    end)
  end)
end

local function base_spec(over)
  return vim.tbl_extend("force", {
    name = "t1",
    root = "/proj",
    cwd = vim.fn.getcwd(),
    cmd = jobs.sleeper(),
    layout = "vsplit",
    float = { width = 0.5, height = 0.5, border = "rounded", title = true, title_pos = "center" },
    split = { size = 0.3 },
    start_insert = false,
    on_exit = "close",
  }, over or {})
end

contract("native", function()
  local registry = registry_mod.new()
  local backend = require("terminal.backends.native").new(registry)
  return {
    backend = backend,
    registry = registry,
    spec = base_spec,
    send = function(h, text)
      local ok, err
      jobs.record_sends(function()
        ok, err = backend.send(h, text)
      end)
      return ok, err
    end,
    failing = function()
      return backend, base_spec({ cmd = { "definitely-not-a-program-xyz" } })
    end,
    cleanup = function()
      jobs.cleanup(backend, registry)
    end,
  }
end)

contract("wezterm", function()
  local registry = registry_mod.new()
  local runner = fakes.wezterm()
  local backend = require("terminal.backends.wezterm").new(registry, runner, "7")
  return {
    backend = backend,
    registry = registry,
    spec = base_spec,
    send = function(h, text)
      return backend.send(h, text)
    end,
    failing = function()
      local bad = require("terminal.backends.wezterm").new(registry, function()
        return { code = 1, stdout = "", stderr = "boom" }
      end, "7")
      return bad, base_spec()
    end,
    cleanup = function() end,
  }
end)

contract("tmux", function()
  local registry = registry_mod.new()
  local runner = fakes.tmux()
  local backend = require("terminal.backends.tmux").new(registry, runner, "%0")
  return {
    backend = backend,
    registry = registry,
    spec = base_spec,
    send = function(h, text)
      return backend.send(h, text)
    end,
    failing = function()
      local bad = require("terminal.backends.tmux").new(registry, function()
        return { code = 1, stdout = "", stderr = "boom" }
      end, "%0")
      return bad, base_spec()
    end,
    cleanup = function() end,
  }
end)
