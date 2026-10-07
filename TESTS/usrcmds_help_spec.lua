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

  it("leaves no flag without a description", function()
    local missing = {}
    for _, m in ipairs(composer.help.undocumented("Terminal")) do
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
end)
