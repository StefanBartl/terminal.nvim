---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/errors_spec.lua -- terminal.core.errors: one line and a hint for a failed multiplexer call.

dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/]") or ".") .. "/support/env.lua").isolate()

local errors = require("terminal.core.errors")

describe("terminal.core.errors.reason", function()
  it("nothing printed is 'no output'", function()
    assert.equals("no output", errors.reason("tmux", ""))
    assert.equals("no output", errors.reason("tmux", "  \n "))
    assert.equals("no output", errors.reason("wezterm", nil))
  end)

  it("keeps a plain one-line message as it is", function()
    assert.equals("unknown command: x", errors.reason("tmux", "unknown command: x\n"))
  end)

  it("adds a hint for a failure with an obvious cause", function()
    local r = errors.reason("tmux", "no server running on /tmp/tmux-1000/default")
    assert.truthy(r:find("no server running on /tmp/tmux-1000/default", 1, true), r)
    assert.truthy(r:find("(start tmux", 1, true), r)
    assert.truthy(errors.reason("tmux", "can't find pane: %7"):find("the pane is gone", 1, true))
    assert.truthy(
      errors
        .reason("wezterm", "Error: failed to connect to the mux")
        :find("is WezTerm running", 1, true)
    )
  end)

  it("a hint belongs to its tool", function()
    assert.is_nil(errors.reason("wezterm", "can't find pane: %7"):find("the pane is gone", 1, true))
    assert.is_nil(errors.reason("tmux", "failed to connect"):find("WezTerm", 1, true))
  end)

  it(
    "keeps only the first line of a long chain and logs the whole output at debug level",
    function()
      local logged = {}
      local notify = require("terminal.notify")
      local original = notify.debug
      -- Test double: collects the debug messages; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      notify.debug = function(msg)
        logged[#logged + 1] = msg
      end
      local chain = "Error: pane 9 not found\nCaused by:\n    0: the mux said so\n    1: and so on"
      local r = errors.reason("wezterm", chain)
      notify.debug = original
      assert.is_nil(r:find("Caused by", 1, true), r)
      assert.is_nil(r:find("\n", 1, true))
      assert.truthy(r:find("Error: pane 9 not found", 1, true))
      assert.equals(1, #logged)
      assert.truthy(logged[1]:find("Caused by", 1, true), logged[1])
    end
  )

  it("a very long first line is cut", function()
    local r = errors.reason("tmux", string.rep("x", 500))
    assert.is_true(#r <= 210, #r)
    assert.truthy(r:find("...", 1, true))
  end)

  it("a hint comes from the first line, not from a later line of a chain", function()
    local chr10 = string.char(10)
    local r = errors.reason(
      "wezterm",
      "Error: something broke" .. chr10 .. "Caused by:" .. chr10 .. "    0: pane not found"
    )
    assert.is_nil(r:find("the pane is gone", 1, true), r)
  end)

  it("logs the whole output when a long single line is cut", function()
    local logged = {}
    local notify = require("terminal.notify")
    local original = notify.debug
    -- Test double: collects the debug messages; restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    notify.debug = function(msg)
      logged[#logged + 1] = msg
    end
    errors.reason("tmux", string.rep("x", 500))
    notify.debug = original
    assert.equals(1, #logged)
    assert.truthy(logged[1]:find(string.rep("x", 500), 1, true))
  end)
end)
