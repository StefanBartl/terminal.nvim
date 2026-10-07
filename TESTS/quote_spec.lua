---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/quote_spec.lua -- terminal.core.quote (pure shell quoting)

local quote = require("terminal.core.quote")

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

    it("neutralises percent signs", function()
      assert.equals('"^%PATH^%"', quote.word("%PATH%", "cmd"))
    end)
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

    it("refuses non-string words", function()
      local line, err = quote.argv_to_line({ "echo", 3 }, "posix")
      assert.is_nil(line)
      assert.truthy(err:find("argument 2", 1, true))
    end)

    it("refuses a word with a line break or NUL: that would end the command line", function()
      for _, bad in ipairs({ "a\nb", "a\rb", "a\0b" }) do
        for _, kind in ipairs({ "posix", "powershell", "cmd" }) do
          local line = quote.argv_to_line({ "echo", bad }, kind)
          assert.is_nil(line, ("%s / %q"):format(kind, bad))
        end
      end
    end)
  end)
end)
