---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/quote_spec.lua -- terminal.core.quote (pure shell quoting)

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local quote = require("terminal.core.quote")
local shells =
  dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/shells.lua")

-- Strings an attacker (or an unlucky file name) could use to break out of a quoted word.
local HOSTILE = {
  "a b",
  "it's",
  'say "hi"',
  "$(whoami)",
  "`id`",
  "a;b",
  "a&b",
  "a|b",
  "a>b",
  "%PATH%",
  "$HOME",
  "-rf",
  "--flag=x",
  "",
  "ünïcödé",
  "back\\slash",
}

describe("terminal.core.quote", function()
  describe("shell_kind with arguments", function()
    it("finds the family in a command string", function()
      assert.equals("powershell", quote.shell_kind("pwsh -NoLogo"))
      assert.equals(
        "powershell",
        quote.shell_kind('"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -NoLogo')
      )
      assert.equals("cmd", quote.shell_kind("cmd.exe /k"))
      assert.equals("posix", quote.shell_kind("bash -l"))
    end)

    it("does not mistake a path component that merely contains the name", function()
      assert.equals("posix", quote.shell_kind("/opt/mycmdtools/zsh"))
    end)
  end)

  describe("fish", function()
    it(
      "is recognised by name, path or command string, and not by a path component that contains it",
      function()
        assert.equals("fish", quote.shell_kind("fish"))
        assert.equals("fish", quote.shell_kind("/usr/bin/fish"))
        assert.equals("fish", quote.shell_kind("fish -l"))
        assert.equals("posix", quote.shell_kind("/opt/fisheye/zsh"))
      end
    )

    it("escapes the backslash and the quote: inside '...' fish reads both as escapes", function()
      assert.equals("'it\\'s'", quote.word("it's", "fish"))
      assert.equals("'a\\\\b'", quote.word("a\\b", "fish"))
      assert.equals("'\\\\'", quote.word("\\", "fish"))
      assert.equals("''", quote.word("", "fish"))
      assert.equals("plain", quote.word("plain", "fish"))
    end)

    it(
      "round-trips what POSIX quoting would break: a word that holds backslash and quote",
      function()
        for _, word in ipairs({ "\\'; touch x; '", "a\\", "\\\\", "it's \\ here", "x\\'y" }) do
          local line = quote.argv_to_line({ "echo", word }, "fish")
          assert.same({ "echo", word }, shells.fish(line), word)
        end
      end
    )
  end)

  describe("shell_kind", function()
    it("recognises the families from a name or a path", function()
      assert.equals("powershell", quote.shell_kind("pwsh"))
      assert.equals("powershell", quote.shell_kind("C:\\Program Files\\PowerShell\\7\\pwsh.exe"))
      assert.equals("powershell", quote.shell_kind("powershell.exe"))
      assert.equals("cmd", quote.shell_kind("C:\\Windows\\System32\\cmd.exe"))
      assert.equals("posix", quote.shell_kind("/usr/bin/zsh"))
      assert.equals("posix", quote.shell_kind(nil))
      assert.equals("posix", quote.shell_kind(""))
    end)
  end)

  describe("posix", function()
    it("leaves safe words alone and quotes the rest", function()
      assert.equals("ls", quote.word("ls", "posix"))
      assert.equals("/usr/bin/x_y-z.1", quote.word("/usr/bin/x_y-z.1", "posix"))
      assert.equals("'a b'", quote.word("a b", "posix"))
      assert.equals("''", quote.word("", "posix"))
    end)

    it("escapes an embedded single quote", function()
      assert.equals([['it'\''s']], quote.word("it's", "posix"))
    end)

    it("leaves option-looking words bare: quoting cannot stop option parsing, `--` does", function()
      assert.equals("-rf", quote.word("-rf", "posix"))
      assert.equals("--flag=x", quote.word("--flag=x", "posix"))
      assert.equals("'--flag=a b'", quote.word("--flag=a b", "posix"))
    end)

    it("makes every hostile word one shell word: safe characters only, or fully quoted", function()
      for _, w in ipairs(HOSTILE) do
        local q = quote.word(w, "posix")
        if q:find("^[%w%._/:=@%%+,-]+$") == nil then
          assert.equals("'", q:sub(1, 1), w)
          assert.equals("'", q:sub(-1), w)
        end
      end
    end)
  end)

  describe("powershell", function()
    it("doubles an embedded single quote", function()
      assert.equals("'it''s'", quote.word("it's", "powershell"))
    end)

    it("single-quotes $(...) and backticks so nothing expands", function()
      assert.equals("'$(whoami)'", quote.word("$(whoami)", "powershell"))
      assert.equals("'`id`'", quote.word("`id`", "powershell"))
    end)

    it("doubles the typographic single quotes PowerShell also treats as quotes", function()
      for _, q in ipairs({ "\226\128\152", "\226\128\153", "\226\128\154", "\226\128\155" }) do
        local w = quote.word("x" .. q .. ";Write-Output INJECTED;" .. q, "powershell")
        assert.equals("'x" .. q .. q .. ";Write-Output INJECTED;" .. q .. q .. "'", w)
      end
    end)

    it("quotes words that would splat, build an array or read as an alias", function()
      assert.equals("'@args'", quote.word("@args", "powershell"))
      assert.equals("'a,b'", quote.word("a,b", "powershell"))
      assert.equals("'%'", quote.word("%", "powershell"))
      assert.equals("'a+b'", quote.word("a+b", "powershell"))
    end)

    it("adds the call operator when the program word itself is quoted", function()
      local line = quote.argv_to_line({ "C:\\Program Files\\x.exe", "a b" }, "powershell")
      assert.equals("& 'C:\\Program Files\\x.exe' 'a b'", line)
      assert.equals("git status", quote.argv_to_line({ "git", "status" }, "powershell"))
    end)
  end)

  describe("cmd", function()
    it("double-quotes unsafe words and doubles embedded quotes", function()
      assert.equals('"a b"', quote.word("a b", "cmd"))
      assert.equals('"say ""hi"""', quote.word('say "hi"', "cmd"))
      assert.equals('""', quote.word("", "cmd"))
    end)

    it("refuses a word with a percent sign: cmd.exe cannot quote it", function()
      local w, err = quote.word("%PATH%", "cmd")
      assert.is_nil(w)
      assert.truthy(err:find("%", 1, true))
      assert.is_nil((quote.argv_to_line({ "echo", "100%" }, "cmd")))
    end)

    it("doubles backslashes before the closing quote", function()
      assert.equals('"C:\\my dir\\\\"', quote.word("C:\\my dir\\", "cmd"))
    end)

    it(
      "doubles backslashes in front of an EMBEDDED quote too (else the C runtime reads a literal quote)",
      function()
        assert.equals('"a\\\\"" b"', quote.word('a\\" b', "cmd"))
        -- the argument-injection word: it used to come out as three arguments
        local word = 'a\\" --injected=1 "b'
        local line = quote.argv_to_line({ "node", word }, "cmd")
        assert.same({ "node", word }, shells.msvcrt(line))
      end
    )
  end)

  describe("argv_to_line", function()
    it("joins quoted words with single spaces", function()
      local line = quote.argv_to_line({ "git", "commit", "-m", "a b" }, "posix")
      assert.equals("git commit -m 'a b'", line)
    end)

    it("refuses an empty argv and a non-table", function()
      local line, err = quote.argv_to_line({}, "posix")
      assert.is_nil(line)
      assert.truthy(err)
      assert.is_nil((quote.argv_to_line(nil, "posix")))
    end)

    it("refuses TAB: readline completes INSIDE the quotes and closes them", function()
      local line, err = quote.argv_to_line({ "echo", "x\t; touch f #" }, "posix")
      assert.is_nil(line)
      assert.truthy(err:find("TAB", 1, true), err)
    end)

    it("refuses non-string words", function()
      local line, err = quote.argv_to_line({ "echo", 3 }, "posix")
      assert.is_nil(line)
      assert.truthy(err:find("argument 2", 1, true))
    end)

    it(
      "refuses control characters: a line break ends the command line, ESC is interpreted",
      function()
        for _, bad in ipairs({ "a\nb", "a\rb", "a\0b", "a\27[31mb", "a\127b", "a\tb" }) do
          for _, kind in ipairs({ "posix", "fish", "powershell", "cmd" }) do
            local line = quote.argv_to_line({ "echo", bad }, kind)
            assert.is_nil(line, ("%s / %q"):format(kind, bad))
          end
        end
      end
    )
  end)
end)
