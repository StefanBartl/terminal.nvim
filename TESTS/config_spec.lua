---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/config_spec.lua -- terminal.config

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

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
          -- nothing valid is left in the section, so the section is not in `clean` at all
          assert.is_nil(clean.auto_insert, bad)
        end
      end
    )

    it("with no valid event left, the key is dropped so the default list applies", function()
      local p, clean = config.validate(DEFAULTS, { auto_insert = { events = { "Nope" } } })
      assert.equals(1, #p)
      assert.is_nil(clean.auto_insert)
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

  describe("a section the user's options leave empty", function()
    -- lib.lua.config.deep_merge takes `{}` for an empty list and replaces the whole default
    -- section with it; the sections below used to come out as `{}` and break setup() later.
    it("keeps the defaults when every key of the section is invalid", function()
      local problems = config.setup({
        navigate = { handof = "tmux" },
        status = { debounce_msx = 80 },
        float = { width = "x" },
      })
      assert.equals(3, #problems)
      assert.equals("auto", config.get("navigate.handoff"))
      assert.equals(80, config.get("status.debounce_ms"))
      assert.equals(0.8, config.get("float.width"))
      assert.equals("rounded", config.get("float.border"))
    end)

    it("keeps the defaults for an empty section and for empty keymaps/env", function()
      assert.same({}, config.setup({ float = {}, navigate = {}, keymaps = {}, env = {} }))
      assert.equals(0.8, config.get("float.width"))
      assert.equals("auto", config.get("navigate.handoff"))
      assert.equals("<A-h>", config.get("keymaps.toggle"))
      assert.same({}, config.get("env"))
    end)

    it("still lets keymaps = false switch every key map off", function()
      assert.same({}, config.setup({ keymaps = false }))
      assert.is_false(config.get("keymaps"))
    end)
  end)

  describe("value ranges", function()
    it("reports a size that is no usable number and keeps the default", function()
      for _, bad in ipairs({ 0, -1, 0 / 0, math.huge }) do
        local problems = config.setup({ float = { width = bad }, split = { size = bad } })
        assert.equals(2, #problems, tostring(bad))
        assert.truthy(problems[1]:find("a number above 0", 1, true))
        assert.equals(0.8, config.get("float.width"))
        assert.equals(0.3, config.get("split.size"))
      end
    end)

    it("accepts a fraction and a count of cells", function()
      assert.same({}, config.setup({ float = { width = 0.5, height = 40 }, split = { size = 12 } }))
      assert.equals(40, config.get("float.height"))
    end)

    it("checks winblend, zindex, debounce, max_bytes and the kitty cell counts", function()
      local problems = config.setup({
        float = { winblend = 101, zindex = 0 },
        status = { debounce_ms = -5, max_bytes = 0.5 },
        kitty = { enter_padding = -1, leave_margin = 1.5 },
      })
      assert.equals(6, #problems)
      assert.equals(0, config.get("float.winblend"))
      assert.equals(50, config.get("float.zindex"))
      assert.equals(80, config.get("status.debounce_ms"))
      assert.equals(1024, config.get("status.max_bytes"))
      assert.equals(0, config.get("kitty.enter_padding"))
      assert.equals(10, config.get("kitty.leave_margin"))
    end)

    it("checks float.border: a name nvim_open_win knows, or 1, 2, 4 or 8 pieces", function()
      for _, bad in ipairs({ "foo", "Rounded", {}, { "a", "b", "c" } }) do
        local problems = config.setup({ float = { border = bad } })
        assert.equals(1, #problems, vim.inspect(bad))
        assert.equals("rounded", config.get("float.border"))
      end
      for _, good in ipairs({
        "none",
        "single",
        "double",
        "rounded",
        "solid",
        "shadow",
        "",
        { "a", "b" },
        { "1", "2", "3", "4", "5", "6", "7", "8" },
      }) do
        assert.same({}, config.setup({ float = { border = good } }), vim.inspect(good))
      end
    end)

    it("checks window_options.signcolumn: the values 'signcolumn' takes", function()
      for _, bad in ipairs({ "bogus", "yes:0", "no:2", "number:3", "auto:1-", "", "yes:" }) do
        local problems = config.setup({ window_options = { signcolumn = bad } })
        assert.equals(1, #problems, bad)
        assert.equals("no", config.get("window_options.signcolumn"))
      end
      for _, good in ipairs({ "yes", "no", "auto", "number", "yes:2", "auto:1-3" }) do
        assert.same({}, config.setup({ window_options = { signcolumn = good } }), good)
      end
    end)

    it("wants a name for default_name and run.name that is not empty", function()
      local problems = config.setup({ default_name = "", run = { name = "" } })
      assert.equals(2, #problems)
      assert.equals("main", config.get("default_name"))
      assert.equals("run", config.get("run.name"))
    end)
  end)

  it('reads true as "auto" for status.export and navigate.handoff', function()
    assert.same({}, config.setup({ status = { export = true }, navigate = { handoff = true } }))
    assert.equals("auto", config.get("status.export"))
    assert.equals("auto", config.get("navigate.handoff"))
    config.setup({ status = { export = false }, navigate = { handoff = { "tmux" } } })
    assert.is_false(config.get("status.export"))
    assert.same({ "tmux" }, config.get("navigate.handoff"))
  end)

  it("keeps what the last setup() found in `problems` (for :checkhealth)", function()
    assert.same({}, config.problems)
    config.setup({ layout = "sideways" })
    assert.equals(1, #config.problems)
    config.setup({})
    assert.same({}, config.problems)
  end)
end)
