---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/config_spec.lua -- terminal.config

describe("terminal.config", function()
  local config, DEFAULTS

  before_each(function()
    package.loaded["terminal.config"] = nil
    package.loaded["terminal.config.DEFAULTS"] = nil
    config = require("terminal.config")
    DEFAULTS = require("terminal.config.DEFAULTS")
  end)

  it("starts with the shipped defaults before setup() ran", function()
    assert.equals("auto", config.get("backend"))
    assert.equals("float", config.get("layout"))
    assert.equals(0.8, config.get("float.width"))
    assert.equals("<A-h>", config.get("keymaps.toggle"))
  end)

  it("deep-merges a partial override and keeps untouched defaults", function()
    config.setup({ float = { width = 0.5 } })
    assert.equals(0.5, config.get("float.width"))
    assert.equals(0.8, config.get("float.height"))
    assert.equals("rounded", config.get("float.border"))
  end)

  it("never aliases DEFAULTS: writing through get() or options cannot corrupt them", function()
    config.setup({ layout = "split" })
    local copy = config.get("float")
    copy.width = 0.1
    config.options.float.height = 0.1
    assert.equals(0.8, DEFAULTS.float.width)
    assert.equals(0.8, DEFAULTS.float.height)
  end)

  describe("validate", function()
    it("reports an unknown key by its dot-path", function()
      local p = config.validate(DEFAULTS, { float = { wdith = 1 } })
      assert.same({ "unknown config key 'float.wdith' -- ignored" }, p)
    end)

    it("reports a wrong leaf type", function()
      local p = config.validate(DEFAULTS, { start_insert = "yes" })
      assert.equals(1, #p)
      assert.truthy(p[1]:find("start_insert", 1, true))
      assert.truthy(p[1]:find("boolean", 1, true))
    end)

    it("reports a value outside a closed set and names the allowed ones", function()
      local p = config.validate(DEFAULTS, { layout = "sideways" })
      assert.equals(1, #p)
      assert.truthy(p[1]:find("float|split|vsplit|tab", 1, true))
    end)

    it("drops an auto_insert event Neovim does not know and keeps the others", function()
      local p, clean =
        config.validate(DEFAULTS, { auto_insert = { events = { "TermOpen", "TermEnterr", 5 } } })
      assert.equals(2, #p)
      assert.truthy(p[1]:find("auto_insert.events", 1, true))
      assert.same({ "TermOpen" }, clean.auto_insert.events)
    end)

    it(
      "a valid name with a separator after it is not an event (nvim_create_autocmd rejects it)",
      function()
        for _, bad in ipairs({ "TermOpen,TermClose", "TermOpen ", "TermOpen,", "TermOpen|x" }) do
          local p, clean = config.validate(DEFAULTS, { auto_insert = { events = { bad } } })
          assert.equals(1, #p, bad)
          assert.is_nil(clean.auto_insert.events, bad)
        end
      end
    )

    it("with no valid event left, the key is dropped so the default list applies", function()
      local p, clean = config.validate(DEFAULTS, { auto_insert = { events = { "Nope" } } })
      assert.equals(1, #p)
      assert.is_nil(clean.auto_insert.events)
      config.setup({ auto_insert = { enable = true, events = { "Nope" } } })
      assert.same({ "TermOpen" }, config.get("auto_insert.events"))
    end)

    it("wants a list of event names, not a string", function()
      local p = config.validate(DEFAULTS, { auto_insert = { events = "TermOpen" } })
      assert.equals(1, #p)
      assert.truthy(p[1]:find("list of event names", 1, true))
    end)

    it("accepts the wide types: string or list shell, string or list border", function()
      assert.same({}, config.validate(DEFAULTS, { shell = "pwsh" }))
      assert.same({}, config.validate(DEFAULTS, { shell = { "pwsh", "-NoLogo" } }))
      assert.same({}, config.validate(DEFAULTS, { float = { border = { "a", "b" } } }))
    end)

    it("accepts keymaps overrides of any shape (the keymap registry checks the names)", function()
      assert.same({}, config.validate(DEFAULTS, { keymaps = { toggle = false, anything = "x" } }))
      assert.same({}, config.validate(DEFAULTS, { keymaps = false }))
    end)

    it("accepts arbitrary env keys", function()
      assert.same({}, config.validate(DEFAULTS, { env = { FOO = "1" } }))
    end)
  end)

  it("falls back to the default of an enum key that failed validation", function()
    local problems = config.setup({ layout = "sideways", on_exit = "keep" })
    assert.equals(1, #problems)
    assert.equals("float", config.get("layout"))
    assert.equals("keep", config.get("on_exit"))
  end)

  it("a table key given a scalar is reported and keeps its defaults (no error)", function()
    for _, bad in ipairs({ "x", false, 3 }) do
      local ok, problems = pcall(config.setup, { float = bad, split = bad, kitty = bad })
      assert.is_true(ok, tostring(problems))
      assert.equals(3, #problems)
      assert.equals(0.8, config.get("float.width"))
      assert.equals("center", config.get("float.title_pos"))
      assert.equals(0.3, config.get("split.size"))
    end
  end)

  it("a wrongly typed leaf is dropped, the default stays, valid siblings apply", function()
    local problems =
      config.setup({ float = { width = "wide", height = 0.5 }, start_insert = "yes" })
    assert.equals(2, #problems)
    assert.equals(0.8, config.get("float.width"))
    assert.equals(0.5, config.get("float.height"))
    assert.is_true(config.get("start_insert"))
  end)

  it("treats a non-table argument as a problem, not an error", function()
    local problems = config.setup("nope")
    assert.equals(1, #problems)
    assert.equals("float", config.get("layout"))
  end)
end)
