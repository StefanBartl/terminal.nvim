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

  it("treats a non-table argument as a problem, not an error", function()
    local problems = config.setup("nope")
    assert.equals(1, #problems)
    assert.equals("float", config.get("layout"))
  end)
end)
