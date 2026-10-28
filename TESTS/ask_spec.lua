---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/ask_spec.lua -- the ask bridge: native terminals get $NVIM_ASK (lib.nvim's bin/nvim-ask),
-- the user's own env wins, `ask.enable = false` turns it off, the multiplexer backends are never
-- handed it, and :checkhealth reports it.

dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local ask = require("terminal.ask")

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

local function has(log, prefix, text)
  for _, line in ipairs(log) do
    if line:sub(1, #prefix) == prefix and line:find(text, 1, true) then
      return true
    end
  end
  return false
end

--- Run `fn` with lib.nvim.terminal.ask unloadable. Forgets the cached path first: a path
--- resolved by an earlier test must not short-circuit this one.
local function without_lib_ask(fn)
  ask._forget_cache()
  local saved_loaded = package.loaded["lib.nvim.terminal.ask"]
  local saved_preload = package.preload["lib.nvim.terminal.ask"]
  package.loaded["lib.nvim.terminal.ask"] = nil
  package.preload["lib.nvim.terminal.ask"] = function()
    error("module 'lib.nvim.terminal.ask' not found")
  end
  local ok, err = pcall(fn)
  package.preload["lib.nvim.terminal.ask"] = saved_preload
  package.loaded["lib.nvim.terminal.ask"] = saved_loaded
  if not ok then
    error(err, 0)
  end
end

describe("terminal.ask", function()
  it("env names lib.nvim's nvim-ask, and nothing when switched off", function()
    local env = ask.env({ enable = true })
    assert.is_truthy(env.NVIM_ASK:match("/bin/nvim%-ask$"))
    assert.equals(1, vim.fn.filereadable(env.NVIM_ASK))
    assert.same({}, ask.env({ enable = false }))
  end)

  it("script() resolves once, then returns the cached path", function()
    ask._forget_cache()
    local calls = 0
    local real = require("lib.nvim.terminal.ask")
    local saved_loaded = package.loaded["lib.nvim.terminal.ask"]
    package.loaded["lib.nvim.terminal.ask"] = {
      script = function()
        calls = calls + 1
        return real.script()
      end,
    }
    local ok, err = pcall(function()
      local first = ask.script()
      local second = ask.script()
      assert.equals(first, second)
      assert.equals(1, calls)
    end)
    package.loaded["lib.nvim.terminal.ask"] = saved_loaded
    if not ok then
      error(err, 0)
    end
  end)

  it("without the bridge in lib.nvim: no env, and health says why", function()
    without_lib_ask(function()
      assert.same({}, ask.env({ enable = true }))
      local path, reason = ask.script()
      assert.is_nil(path)
      assert.is_truthy(reason:find("update lib.nvim", 1, true))
      local r, log = recorder()
      ask.check(r, { enable = true }, "native")
      assert.is_true(has(log, "warn", "not available"))
    end)
  end)

  it("health: ok with the path, off, and the multiplexer note", function()
    local r, log = recorder()
    ask.check(r, { enable = true }, "native")
    assert.is_true(has(log, "ok", "$NVIM_ASK = "))
    assert.is_false(has(log, "info", "panes are not started"))

    r, log = recorder()
    ask.check(r, { enable = true }, "tmux")
    assert.is_true(has(log, "info", "tmux panes are not started by Neovim"))

    r, log = recorder()
    ask.check(r, { enable = false }, "native")
    assert.is_true(has(log, "info", "off"))
  end)

  describe("native terminals", function()
    local terminal
    local out

    --- A terminal job that writes its $NVIM_ASK into `out` and exits.
    local function reporter()
      return {
        vim.v.progpath,
        "--clean",
        "--headless",
        "--cmd",
        ("lua vim.fn.writefile({ vim.env.NVIM_ASK or '<unset>' }, %q)"):format(out),
        "+qa!",
      }
    end

    local function seen()
      vim.wait(15000, function()
        return vim.fn.filereadable(out) == 1
      end, 50)
      local lines = vim.fn.filereadable(out) == 1 and vim.fn.readfile(out) or {}
      return lines[1]
    end

    local function open_with(opts)
      for _, mod in ipairs({
        "terminal",
        "terminal.config",
        "terminal.backends.native",
        "terminal.bindings",
      }) do
        package.loaded[mod] = nil
      end
      terminal = require("terminal")
      terminal.setup(vim.tbl_extend("force", {
        shell = reporter(),
        start_insert = false,
        commands = false,
        keymaps = { preset = false },
        on_exit = "keep",
      }, opts or {}))
      terminal.open({ name = "ask" })
      return seen()
    end

    before_each(function()
      out = vim.fn.tempname() .. ".txt"
    end)

    after_each(function()
      if terminal then
        for _, h in ipairs(terminal.list(true)) do
          terminal.close({ name = h.name })
        end
        terminal.teardown()
      end
      vim.cmd("silent! tabonly")
      vim.cmd("silent! only")
      pcall(vim.fn.delete, out)
    end)

    it("get $NVIM_ASK", function()
      local value = open_with()
      assert.is_truthy(value and value:match("/bin/nvim%-ask$"), tostring(value))
    end)

    it("the user's own env wins", function()
      assert.equals("mine", open_with({ env = { NVIM_ASK = "mine" } }))
    end)

    it("ask.enable = false: not set", function()
      assert.equals("<unset>", open_with({ ask = { enable = false } }))
    end)
  end)
end)
