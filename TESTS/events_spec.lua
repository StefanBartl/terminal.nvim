---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/events_spec.lua -- terminal.events: the User events other plugins can follow
-- (TerminalCommandPost for an executed line or a direct job, TerminalExitPost for its exit).

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal.events", function()
  local terminal
  local seen
  local original_notify = vim.notify

  before_each(function()
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.backends.native",
      "terminal.bindings",
    }) do
      package.loaded[mod] = nil
    end
    -- Test double: nothing in these specs is meant to reach the user; restored in after_each.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
    terminal = require("terminal")
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    })
    seen = {}
    local group = vim.api.nvim_create_augroup("TerminalSpecEvents", { clear = true })
    for _, pattern in ipairs({ "TerminalCommandPost", "TerminalExitPost" }) do
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = pattern,
        callback = function(ev)
          seen[#seen + 1] = { pattern = pattern, data = ev.data }
        end,
      })
    end
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "TerminalSpecEvents")
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = original_notify
  end)

  it("an executed line announces the command without its line ending", function()
    jobs.record_sends(function()
      terminal.send("make test", { newline = true, name = "repl" })
    end)
    assert.equals(1, #seen)
    assert.equals("TerminalCommandPost", seen[1].pattern)
    assert.same(
      { name = "repl", backend = "native", command = "make test", direct = false },
      seen[1].data
    )
  end)

  it("typed text that is not executed announces nothing", function()
    jobs.record_sends(function()
      terminal.send("make test", { name = "repl" })
    end)
    assert.equals(0, #seen)
  end)

  it("text that ends in a line ending is an executed line", function()
    jobs.record_sends(function()
      terminal.send("ls\n", { name = "repl" })
    end)
    assert.equals(1, #seen)
    assert.equals("ls", seen[1].data.command)
  end)

  it("run without direct announces the line typed (an argv is quoted first)", function()
    jobs.record_sends(function()
      terminal.run("git status", { name = "repl" })
    end)
    assert.equals("git status", seen[1].data.command)
    assert.is_false(seen[1].data.direct)
  end)

  it("a direct job announces its start and, when it ends, its exit code", function()
    local code
    terminal.run(jobs.exit_with(3), {
      direct = true,
      name = "job",
      on_exit = function(c)
        code = c
      end,
    })
    assert.is_true(jobs.wait(function()
      return code ~= nil
    end))
    assert.equals(3, code, "the caller's on_exit still runs")
    assert.equals("TerminalCommandPost", seen[1].pattern)
    assert.is_true(seen[1].data.direct)
    assert.equals("job", seen[1].data.name)
    assert.equals(table.concat(jobs.exit_with(3), " "), seen[1].data.command)
    assert.equals("TerminalExitPost", seen[2].pattern)
    assert.equals(3, seen[2].data.exit_code)
    assert.equals(seen[1].data.command, seen[2].data.command)
  end)
end)
