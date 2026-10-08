---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
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
  "=ls", -- zsh replaces a bare =ls by the path of ls
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
        -- the bare set: `=` is safe everywhere but in the first place (zsh: =ls is a path)
        if q:find("^[%w%._/:@%%+,-][%w%._/:=@%%+,-]*$") == nil then
          assert.equals("'", q:sub(1, 1), w)
          assert.equals("'", q:sub(-1), w)
        end
      end
    end)

    it("quotes a word that STARTS with '=': zsh would replace =ls by the path of ls", function()
      assert.equals("'=ls'", quote.word("=ls", "posix"))
      assert.equals("'=nosuchcmd'", quote.word("=nosuchcmd", "posix"))
      assert.equals("'='", quote.word("=", "posix"))
      assert.equals("'==x'", quote.word("==x", "posix"))
      -- inside a word `=` is literal in every shell: it stays readable
      assert.equals("a=b", quote.word("a=b", "posix"))
      assert.equals("--flag=x", quote.word("--flag=x", "posix"))
      assert.equals("printf '=ls' tail", quote.argv_to_line({ "printf", "=ls", "tail" }, "posix"))
    end)

    -- zsh exists on Linux and macOS machines, not on a stock Windows one: the case is registered
    -- only where it can run (a skipped case would count as not green).
    if vim.fn.executable("zsh") == 1 then
      it("zsh reads every hostile word back as itself, =ls and =nosuchcmd included", function()
        local words = vim.list_extend(vim.deepcopy(HOSTILE), { "=nosuchcmd", "==", "a=b", "=a=b" })
        local argv = vim.list_extend({ "printf", "%s\\n" }, words)
        local line = assert(quote.argv_to_line(argv, "posix"))
        -- -f: no startup files of the machine; -c: the line is the whole script. A bare `=ls`
        -- (the old behaviour) makes zsh search the PATH for `ls` and for `nosuchcmd`: a short PATH
        -- keeps that fast where the machine's PATH is long or slow (WSL lists the Windows one).
        local zsh = { vim.fn.exepath("zsh"), "-f", "-c", line }
        local res =
          vim.system(zsh, { clear_env = true, env = { PATH = "/usr/bin:/bin" } }):wait(10000)
        assert.equals(0, res.code, (res.stderr or "") .. "\n" .. line)
        -- printf ends every word with a line break, and no word contains one
        local got = vim.split(res.stdout or "", "\n", { plain = true })
        table.remove(got)
        assert.same(words, got, line)
      end)
    end
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

    it("refuses a word with a double quote: a program may receive it split or cut", function()
      -- Windows PowerShell 5.1 turns the first of these into three arguments, drops the quote of
      -- the second and swallows the third one's space.
      for _, word in ipairs({ 'x\\" --injected=1 "y', 'a"b', 'a" b', '"', 'say "hi"' }) do
        local w, err = quote.word(word, "powershell")
        assert.is_nil(w, word)
        assert.truthy(err and err:find("double quote", 1, true), err)
        assert.truthy(err and err:find("`direct = true`", 1, true), err)
        local line, line_err = quote.argv_to_line({ "git", "log", word }, "powershell")
        assert.is_nil(line, word)
        assert.truthy(line_err and line_err:find("argument 3: ", 1, true), line_err)
      end
    end)

    it(
      "refuses a word with white space that ends in a backslash: it swallows the next argument",
      function()
        local spaces = {
          " ",
          "\194\133", -- NEXT LINE
          "\194\160", -- NO-BREAK SPACE
          "\225\154\128", -- OGHAM SPACE MARK
          "\226\128\131", -- EM SPACE
          "\226\128\138", -- HAIR SPACE
          "\226\128\168", -- LINE SEPARATOR
          "\226\128\175", -- NARROW NO-BREAK SPACE
          "\226\129\159", -- MEDIUM MATHEMATICAL SPACE
          "\227\128\128", -- IDEOGRAPHIC SPACE
        }
        for _, space in ipairs(spaces) do
          for _, word in ipairs({
            "C:\\my" .. space .. "dir\\",
            "a" .. space .. "b\\\\",
            space .. "\\",
          }) do
            local w, err = quote.word(word, "powershell")
            assert.is_nil(w, vim.inspect(word))
            assert.truthy(err and err:find("backslash", 1, true), err)
            assert.truthy(err and err:find("`direct = true`", 1, true), err)
          end
        end
        local line = quote.argv_to_line({ "dir", "C:\\my dir\\", "tail" }, "powershell")
        assert.is_nil(line)
      end
    )

    it("keeps accepting the words every PowerShell hands over intact", function()
      -- a trailing backslash without white space is not wrapped in double quotes
      assert.equals("C:\\dir\\", quote.word("C:\\dir\\", "powershell"))
      -- white space with a backslash that is not the last character
      assert.equals("'C:\\my dir\\file'", quote.word("C:\\my dir\\file", "powershell"))
      assert.equals("'a\\ b'", quote.word("a\\ b", "powershell"))
      -- typographic double quotes are no quotes to the C runtime; neither is a letter whose UTF-8
      -- bytes end in 0xA0 (U+00E0) or the zero-width space next to the space separators
      assert.equals(
        "'a\226\128\156b c\226\128\157'",
        quote.word("a\226\128\156b c\226\128\157", "powershell")
      )
      assert.equals("'\195\160\\'", quote.word("\195\160\\", "powershell"))
      assert.equals("'a\226\128\139b\\'", quote.word("a\226\128\139b\\", "powershell"))
      assert.equals("''", quote.word("", "powershell"))
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
      -- Deliberately wrong type: the case checks the guard.
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.is_nil((quote.argv_to_line(nil, "posix")))
    end)

    it("refuses TAB: readline completes INSIDE the quotes and closes them", function()
      local line, err = quote.argv_to_line({ "echo", "x\t; touch f #" }, "posix")
      assert.is_nil(line)
      assert.truthy(err:find("TAB", 1, true), err)
    end)

    it("refuses non-string words", function()
      -- Deliberately wrong type: the case checks the guard.
      ---@diagnostic disable-next-line: assign-type-mismatch
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
