---@diagnostic disable: undefined-field, redundant-parameter
-- undefined-field and redundant-parameter are off for the whole file: luassert's assert.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/usrcmds_help_spec.lua -- every flag of `:Terminal` has a line in the option float.
--
-- lib.nvim's help float (the option cheatsheet on the command line) shows one line per
-- `--flag` / `key=`, taken from the `desc` of its spec. This pins that no flag of the verb ships
-- without one, and that the lines stay what the float expects: one short line, no trailing full
-- stop.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

describe(":Terminal option float", function()
  local composer = require("lib.nvim.bindings.usercmd.composer")
  local entries = require("lib.nvim.bindings.usercmd.composer.help.entries")

  before_each(function()
    pcall(vim.api.nvim_del_user_command, "Terminal")
    require("terminal.bindings.usrcmds").setup()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_user_command, "Terminal")
  end)

  it("leaves no flag and no positional argument without a description", function()
    assert.is_truthy(composer.registry().Terminal)
    -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
    -- feature of the dependency, not a defect of this plugin; the case is reported as skipped.
    if type(composer.help.undocumented) ~= "function" then
      -- Inside a running case busted's pending(name) alone marks it pending; the stub also wants a block.
      ---@diagnostic disable-next-line: missing-parameter
      return pending("this lib.nvim has no help.undocumented")
    end
    local missing = {}
    for _, m in ipairs(composer.help.undocumented("Terminal", { args = true })) do
      missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
    end
    assert.equals("", table.concat(missing, ", "))
  end)

  it("keeps every description to one short line without a trailing full stop", function()
    local handle = composer.registry().Terminal
    assert.is_truthy(handle)
    local seen = 0
    for _, route in ipairs(handle:spec().routes or {}) do
      for _, flag in ipairs(route.flags or {}) do
        seen = seen + 1
        local text = entries.flag_desc(route, flag) or ""
        local what = ("--%s of %s"):format(flag.name, table.concat(route.path, " "))
        assert.is_true(text ~= "", what .. " shows a text")
        assert.is_nil(text:find("\n", 1, true), what .. " is one line")
        assert.is_true(#text <= 80, what .. " stays short")
        assert.is_nil(text:find("%.$"), what .. " has no trailing full stop")
        -- Every closed value is described, or none is (a half-described list reads as a bug).
        if flag.enum_desc then
          for _, value in ipairs(flag.enum) do
            assert.is_truthy(flag.enum_desc[value], what .. " describes " .. value)
          end
        end
      end
    end
    assert.is_true(seen > 0, "the routes' flags were actually walked")
  end)

  it("keeps every argument text to one short line without a trailing full stop", function()
    local handle = composer.registry().Terminal
    assert.is_truthy(handle)
    local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")
    local seen = 0
    -- Every text an argument can bring: its own `desc`, the `desc` of its type, its `enum_desc`.
    local function check(text, what)
      seen = seen + 1
      assert.is_string(text, what .. " is a string")
      assert.is_true(text ~= "", what .. " shows a text")
      assert.is_nil(text:find("\n", 1, true), what .. " is one line")
      assert.is_true(#text <= 80, what .. " stays short")
      assert.is_nil(text:find("%.$"), what .. " has no trailing full stop")
    end
    for _, route in ipairs(handle:spec().routes or {}) do
      for _, arg in ipairs(route.args or {}) do
        local what = ("argument %s of %s"):format(arg.name, table.concat(route.path, " "))
        if arg.desc then
          check(arg.desc, what)
        end
        local def = arg.type and argtypes.get(arg.type)
        if def and def.desc then
          check(def.desc, ("type %s of %s"):format(arg.type, what))
        end
        for value, text in pairs(arg.enum_desc or {}) do
          check(text, ("value %s of %s"):format(value, what))
        end
      end
    end
    assert.is_true(seen > 0, "the routes' arguments were actually walked")
  end)
end)
