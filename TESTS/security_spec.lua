---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/security_spec.lua -- property tests for everything that turns attacker-controlled text
-- (file names, branch names, selections, config values) into something a shell or a terminal
-- interprets. Seeded and deterministic: a failure reproduces.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local quote = require("terminal.core.quote")
local osc = require("terminal.core.osc")
local status = require("terminal.core.status")

local bit = require("bit")

-- A small deterministic generator (no math.random: the sequence must not change between runs).
-- xorshift32 on LuaJIT's 32-bit `bit` operations: every bit is mixed. (An LCG written with Lua
-- doubles overflows 2^53, loses its low bits and then draws from a handful of values -- the
-- "random" bytes never contained ESC or BEL, the very characters these specs are about.)
local function xorshift(seed)
  local x = bit.tobit(seed ~= 0 and seed or 0x2545F491)
  local function step()
    x = bit.bxor(x, bit.lshift(x, 13))
    x = bit.bxor(x, bit.rshift(x, 17))
    x = bit.bxor(x, bit.lshift(x, 5))
    return x
  end
  for _ = 1, 24 do
    step() -- small seeds start in a poor corner of the sequence; let it mix
  end
  return function(n)
    return (step() % n) + 1
  end
end

-- Characters that matter to shells and terminals.
local ALPHABET = {
  "a",
  "Z",
  "0",
  " ",
  "'",
  '"',
  "`",
  "$",
  "(",
  ")",
  "{",
  "}",
  "[",
  "]",
  ";",
  "&",
  "|",
  "<",
  ">",
  "*",
  "?",
  "!",
  "#",
  "%",
  "^",
  "~",
  "\\",
  "/",
  ":",
  "=",
  ",",
  "@",
  "+",
  "-",
  ".",
  "_",
  "\226\128\152",
  "\226\128\153",
  "\195\188",
  "\240\159\152\128",
}

local function random_word(rand, max)
  local len = rand(max)
  local parts = {}
  for i = 1, len do
    parts[i] = ALPHABET[rand(#ALPHABET)]
  end
  return table.concat(parts)
end

-- Every quoting family there is.
local KINDS = { "posix", "fish", "powershell", "cmd", "portable" }

--- Why the powershell family refuses a word, written down independently of quote.lua: a double
--- quote, white space together with a trailing backslash, the empty word, the stop-parsing token
--- `--%`; nil when the word is accepted. (The generator's only white space is the ASCII blank, so
--- this is exact for its words.) The reason is the text the refusal names.
---@param word string
---@return "double quote"|"backslash"|"empty"|"--%"|nil
local function powershell_refusal(word)
  if word == "" then
    return "empty"
  elseif word == "--%" then
    return "--%"
  elseif word:find('"', 1, true) then
    return "double quote"
  elseif word:sub(-1) == "\\" and word:find(" ", 1, true) then
    return "backslash"
  end
  return nil
end

--- The words of a seeded draw, each followed by the same word with a backslash appended: a random
--- word rarely ends in one, and the rule about a trailing backslash is never reached otherwise.
---@param rand fun(n: integer): integer
---@param count integer How many words to draw
---@param max integer Longest drawn word
---@return string[]
local function words_with_backslash_twins(rand, count, max)
  local words = {}
  for _ = 1, count do
    local word = random_word(rand, max)
    words[#words + 1] = word
    words[#words + 1] = word .. "\\"
  end
  return words
end

--- A random word of raw bytes (0..255): control characters and invalid UTF-8 included.
local function random_bytes(rand, max)
  local raw = {}
  for i = 1, rand(max) do
    raw[i] = string.char(rand(256) - 1)
  end
  return table.concat(raw)
end

--- Undo POSIX single-quote quoting the way a POSIX shell parses it: returns the words.
local function posix_parse(line)
  local words, i, n = {}, 1, #line
  while i <= n do
    while i <= n and line:sub(i, i) == " " do
      i = i + 1
    end
    if i > n then
      break
    end
    local word = {}
    while i <= n and line:sub(i, i) ~= " " do
      local c = line:sub(i, i)
      if c == "'" then
        local close = line:find("'", i + 1, true)
        assert(close, "unterminated quote in: " .. line)
        word[#word + 1] = line:sub(i + 1, close - 1)
        i = close + 1
      elseif c == "\\" then
        word[#word + 1] = line:sub(i + 1, i + 1)
        i = i + 2
      else
        word[#word + 1] = c
        i = i + 1
      end
    end
    words[#words + 1] = table.concat(word)
  end
  return words
end

local shells =
  dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/shells.lua")

describe("quoting for the other shells (property)", function()
  it(
    "cmd: whatever the words, the C runtime reads them back (no % : cmd cannot quote it)",
    function()
      local rand = xorshift(77)
      for _ = 1, 600 do
        local argv = {}
        for i = 1, rand(4) do
          argv[i] = random_word(rand, 10)
        end
        local line = quote.argv_to_line(argv, "cmd")
        if line then
          assert.same(argv, shells.msvcrt(line), line)
        else
          -- refused: only a word with a percent sign may be
          assert.truthy(table.concat(argv):find("%", 1, true), vim.inspect(argv))
        end
      end
    end
  )

  it("fish: whatever the words, fish reads them back", function()
    local rand = xorshift(78)
    for _ = 1, 600 do
      local argv = {}
      for i = 1, rand(4) do
        argv[i] = random_word(rand, 10)
      end
      local line = assert(quote.argv_to_line(argv, "fish"))
      assert.same(argv, shells.fish(line), line)
    end
  end)

  it("a TAB anywhere is refused for every shell", function()
    for _, kind in ipairs(KINDS) do
      assert.is_nil((quote.argv_to_line({ "echo", "a\tb" }, kind)), kind)
    end
  end)
end)

describe("the property generator", function()
  it("covers its whole range, ESC and BEL included", function()
    for _, seed in ipairs({ 7, 23, 29, 20261007 }) do
      local rand = xorshift(seed)
      local seen = {}
      for _ = 1, 4000 do
        seen[rand(256)] = true
      end
      local distinct = 0
      for _ in pairs(seen) do
        distinct = distinct + 1
      end
      assert.is_true(distinct > 240, ("seed %d: only %d distinct values"):format(seed, distinct))
      assert.is_true(seen[28] and seen[8], ("seed %d never drew ESC or BEL"):format(seed))
    end
  end)
end)

describe("terminal.core.quote (property)", function()
  it("posix: whatever the words, a POSIX shell parses the line back to the same words", function()
    local rand = xorshift(20261007)
    for _ = 1, 400 do
      local argv = {}
      for i = 1, rand(5) do
        argv[i] = random_word(rand, 12)
      end
      local line = quote.argv_to_line(argv, "posix")
      assert.is_not_nil(line)
      assert.same(argv, posix_parse(line), line)
    end
  end)

  it("posix: a word that starts with '=' is always quoted (zsh makes a path of =word)", function()
    local rand = xorshift(19)
    for _ = 1, 200 do
      local word = "=" .. random_word(rand, 8)
      assert.equals("'", quote.word(word, "posix"):sub(1, 1), word)
    end
  end)

  it(
    "powershell: every quote character inside a quoted word is doubled, so none ends it",
    function()
      local rand = xorshift(7)
      local quotes = { "'", "\226\128\152", "\226\128\153", "\226\128\154", "\226\128\155" }
      local refused = { ["double quote"] = 0, backslash = 0 }
      for _, word in ipairs(words_with_backslash_twins(rand, 400, 14)) do
        local q, err = quote.word(word, "powershell")
        -- refused exactly when the documented rule says so, and for that rule's reason: nothing
        -- else is turned away, and nothing it names is let through
        local reason = powershell_refusal(word)
        assert.equals(reason ~= nil, q == nil, word)
        if reason then
          assert.truthy(err and err:find(reason, 1, true), ("%q: %s"):format(word, tostring(err)))
          refused[reason] = (refused[reason] or 0) + 1
        elseif q:sub(1, 1) == "'" then
          local inner = q:sub(2, -2)
          for _, quote_char in ipairs(quotes) do
            -- Remove every doubled pair; what is left must contain no quote character.
            local rest = inner:gsub(quote_char .. quote_char, "")
            assert.is_nil(rest:find(quote_char, 1, true), ("%q -> %q"):format(word, q))
          end
        else
          assert.is_truthy(q:find("^[%w%._/:\\-]+$"), q)
          assert.is_nil(q:find("^%-.*:"), "a bare -name:value splits into two arguments: " .. q)
        end
      end
      -- the draw must reach EACH refusal, or the rule above is never exercised: a loop that only
      -- ever meets the double-quote rule would not notice the backslash rule being gone
      for _, reason in ipairs({ "double quote", "backslash" }) do
        assert.is_true(
          refused[reason] > 10,
          ("only %d words refused for: %s"):format(refused[reason], reason)
        )
      end
    end
  )

  it("powershell: a bare word never starts a statement, splat, array or operator", function()
    local rand = xorshift(11)
    for _ = 1, 400 do
      local q = quote.word(random_word(rand, 10), "powershell")
      if q and q:sub(1, 1) ~= "'" then
        assert.is_nil(q:find('[;&|<>(){}@,%%+=$`#!"]'), q)
      end
    end
  end)

  it("powershell: a word that starts with '-' and holds ':' or '.' is never bare", function()
    -- Once a bare `--` is on the line PowerShell splits `-x:y` into `-x:` and `y`, and `-a.b` into
    -- `-a` and `.b`. The draw starts every word with a dash, so words with a colon or a dot behind
    -- it are common.
    local rand = xorshift(59)
    local quoted_with_colon, quoted_with_dot, bare = 0, 0, 0
    for _ = 1, 600 do
      local word = "-" .. random_word(rand, 6)
      local q = quote.word(word, "powershell")
      if q and q:sub(1, 1) ~= "'" then
        bare = bare + 1
        assert.is_nil(q:find("[:.]"), "bare, with a colon or a dot: " .. q)
      elseif q and word:find(":", 1, true) then
        quoted_with_colon = quoted_with_colon + 1
      elseif q and word:find(".", 1, true) then
        quoted_with_dot = quoted_with_dot + 1
      end
    end
    -- both branches must have been drawn, or this checks nothing
    assert.is_true(
      quoted_with_colon > 10,
      ("%d quoted words with a colon"):format(quoted_with_colon)
    )
    assert.is_true(quoted_with_dot > 10, ("%d quoted words with a dot"):format(quoted_with_dot))
    assert.is_true(bare > 10, ("%d bare words"):format(bare))
  end)

  it("posix and fish: a first word is bare only when it is a plain program name", function()
    -- `NAME=value` in front of a command is an environment assignment (the next word then runs
    -- as the command), `.` is source, `:` the null command, `%1` a job.
    local rand = xorshift(61)
    for _, kind in ipairs({ "posix", "fish" }) do
      local bare, quoted = 0, 0
      for _ = 1, 800 do
        local word = random_word(rand, 4)
        local suffix = " echo x"
        local line = assert(quote.argv_to_line({ word, "echo", "x" }, kind))
        assert.equals(suffix, line:sub(-#suffix))
        local first = line:sub(1, #line - #suffix)
        if first:sub(1, 1) == "'" then
          quoted = quoted + 1
        else
          bare = bare + 1
          assert.equals(word, first, kind)
          assert.is_truthy(first:find("^[%w_/.][%w_/.+-]*$"), kind .. " " .. first)
          assert.are_not.equals(".", first, kind)
        end
        local parse = kind == "fish" and shells.fish or posix_parse
        assert.same({ word, "echo", "x" }, parse(line), line)
      end
      assert.is_true(bare > 20, ("%s: %d bare first words"):format(kind, bare))
      assert.is_true(quoted > 20, ("%s: %d quoted first words"):format(kind, quoted))
    end
  end)

  it("posix and fish: a first word that contains '=' is always quoted", function()
    local rand = xorshift(67)
    for _, kind in ipairs({ "posix", "fish" }) do
      for _ = 1, 300 do
        -- `=` at every position: in front, inside, at the end, and as the only character
        local word = random_word(rand, 4) .. "=" .. random_word(rand, 4)
        for _, candidate in ipairs({ word, "=" .. word, word .. "=", "=" }) do
          local line = assert(quote.argv_to_line({ candidate, "echo", "x" }, kind))
          assert.equals("'", line:sub(1, 1), kind .. " " .. candidate)
        end
      end
      -- as an argument the same word stays readable where it is literal
      assert.equals("echo A=b", assert(quote.argv_to_line({ "echo", "A=b" }, kind)))
    end
  end)

  it("cmd: a quoted word never contains an unescaped quote or a percent sign", function()
    local rand = xorshift(13)
    for _ = 1, 400 do
      local word = random_word(rand, 12)
      local q, err = quote.word(word, "cmd")
      if word:find("%", 1, true) then
        assert.is_nil(q)
        assert.truthy(err)
      elseif q:sub(1, 1) == '"' then
        local inner = q:sub(2, -2):gsub('""', "")
        assert.is_nil(inner:find('"', 1, true), q)
      end
    end
  end)

  it(
    "no family accepts a word with a control character, whichever one and wherever it sits",
    function()
      local rand = xorshift(17)
      -- NUL, 1..31 (line breaks, TAB, ESC, ...) and DEL: the whole range, one byte at a time
      local controls = { "\0" }
      for byte = 1, 31 do
        controls[#controls + 1] = string.char(byte)
      end
      controls[#controls + 1] = "\127"
      local tried = 0
      for _, kind in ipairs(KINDS) do
        for _, control in ipairs(controls) do
          local base = random_word(rand, 6)
          -- in front, behind and in the middle of a word; as an argument and as the program word
          for _, word in ipairs({ control .. base, base .. control, base .. control .. base }) do
            for _, argv in ipairs({ { "echo", word }, { word, "x" } }) do
              local line, err = quote.argv_to_line(argv, kind)
              local where = ("%s / %q"):format(kind, word)
              assert.is_nil(line, where)
              -- the control refusal itself, not another family's rule that happens to apply
              assert.truthy(err and err:find("control character", 1, true), where)
              tried = tried + 1
            end
          end
        end
      end
      assert.equals(#KINDS * #controls * 3 * 2, tried)
    end
  )

  it("a line is returned only for words without control bytes, and it carries none", function()
    local rand = xorshift(18)
    local with_control, without = 0, 0
    for _, kind in ipairs(KINDS) do
      for _ = 1, 300 do
        local word = random_bytes(rand, 12)
        local line, err = quote.argv_to_line({ "echo", word }, kind)
        if word:find("[%z\1-\31\127]") then
          with_control = with_control + 1
          assert.is_nil(line, ("%s / %q"):format(kind, word))
          assert.truthy(err and err:find("control character", 1, true), kind)
        elseif line then
          without = without + 1
          assert.is_nil(line:find("[%z\1-\31\127]"), ("%s / %q"):format(kind, line))
        end
      end
    end
    -- both branches must have been drawn, or this is a loop that checks nothing
    assert.is_true(with_control > 200, ("%d words with a control byte"):format(with_control))
    assert.is_true(without > 50, ("%d accepted words"):format(without))
  end)
end)

-- The words the powershell family accepts, against the PowerShell that is installed on this
-- machine: a native program must receive each of them as it was given. PowerShell's own
-- single quotes are gone before the program sees the word, and what the program gets for a double
-- quote or a trailing backslash differs between Windows PowerShell 5.1, pwsh before 7.3 and later:
-- a model of that would prove nothing, so this runs the real shells. Registered only for the shells
-- that exist (a skipped case would count as not green).
--
-- Not in the list, because the family refuses them: the EMPTY word (Windows PowerShell 5.1 and
-- pwsh's legacy passing drop it, quoted or not) and the word `--%` (PowerShell removes it even when
-- it is quoted). The words that start with '-' and hold ':' are in it, and the case sends a bare
-- `--` in front of all of them: after it PowerShell reads a bare `-name:value` as a parameter with a
-- value and hands the program two arguments.
local POWERSHELL_WORDS = {
  "plain",
  "a b",
  "it's",
  "'",
  "x'; Write-Output INJECTED; '",
  "x\226\128\152;Write-Output INJECTED;\226\128\153y",
  "$(whoami)",
  "`id`",
  "$HOME",
  "a;b",
  "a&b",
  "a|b",
  "a>b",
  "a<b",
  "(a)",
  "{a}",
  "#a",
  "!a",
  "^a",
  "~",
  "*",
  "?",
  "%PATH%",
  "@args",
  "a,b",
  "a+b",
  "=ls",
  "-rf",
  "--flag=x",
  "--flag=a b",
  "-x:y",
  "-p:80",
  "-ErrorAction:Stop",
  "-Dkey:value",
  "-o:out.txt",
  "-L:C:/lib",
  "-a-b:c",
  "--flag:x",
  "-:",
  "-I./include",
  "-a.",
  "-a.b",
  "-o.out",
  "-a/.",
  "-_.x",
  "-1.5",
  "--a.b",
  "-.",
  "a-b:c",
  "a-b.c",
  "C:/lib",
  "./include",
  "\195\188n\195\175c\195\182d\195\169",
  "\240\159\152\128",
  "back\\slash",
  "C:\\dir\\",
  "C:\\dir\\\\",
  "C:\\my dir\\file",
  "a\\ b",
  "a b\\c",
  "a\226\128\156b c\226\128\157",
  "\195\160\\",
  "a\226\128\139b\\",
}

describe("terminal.core.quote against the real PowerShell (property)", function()
  local to_line = function(argv)
    return quote.argv_to_line(argv, "powershell")
  end

  --- A bare `--` first, then the fixed words, then a seeded draw of the generator's words (each
  --- with its backslash twin), minus what the family refuses. The `--` is part of what the
  --- program must receive, and every other word follows it.
  ---@return string[] accepted
  ---@return table<string, integer> refused How many drawn words the family turned away, per rule
  local function words_to_send()
    local words = { "--" }
    vim.list_extend(words, POWERSHELL_WORDS)
    for _, word in ipairs(words) do
      assert.is_not_nil(
        quote.word(word, "powershell"),
        "the fixed list holds accepted words: " .. word
      )
    end
    local rand = xorshift(53)
    local refused = { ["double quote"] = 0, backslash = 0 }
    for _, word in ipairs(words_with_backslash_twins(rand, 120, 10)) do
      if quote.word(word, "powershell") then
        words[#words + 1] = word
      else
        local reason = assert(powershell_refusal(word), "refused, but not by a documented rule")
        refused[reason] = (refused[reason] or 0) + 1
      end
    end
    return words, refused
  end

  -- Windows PowerShell is a Windows program: WSL puts powershell.exe on the Linux PATH too, but it
  -- cannot start the Linux Neovim by a Linux path, so it counts only on a Windows Neovim.
  local shells_here = {
    {
      exe = "powershell.exe",
      windows_only = true,
      command = { "powershell.exe", "-NoProfile", "-NonInteractive", "-Command" },
    },
    { exe = "pwsh", command = { "pwsh", "-NoProfile", "-NonInteractive", "-NoLogo", "-Command" } },
  }
  for _, shell in ipairs(shells_here) do
    -- the cheap test first, and `installed` instead of `executable`: on a WSL host the latter
    -- scans the Windows PATH over a 9p mount for seconds, while the file is being collected
    if (not shell.windows_only or vim.fn.has("win32") == 1) and shells.installed(shell.exe) then
      -- pwsh 7.3+ has a preference for how a native program gets its arguments, and its default
      -- gets everything right; the older behaviour (`Legacy`) is what Windows PowerShell 5.1
      -- always has and what pwsh 7.0-7.2 had. Setting the variable in an older pwsh does nothing.
      local modes = { { prefix = "", name = "default" } }
      if shell.exe == "pwsh" then
        modes[#modes + 1] = {
          prefix = "$PSNativeCommandArgumentPassing = 'Legacy'; ",
          name = "legacy argument passing",
        }
      end
      for _, mode in ipairs(modes) do
        it(
          ("%s (%s): every word the powershell family accepts reaches a program as itself"):format(
            shell.exe,
            mode.name
          ),
          function()
            local words, refused = words_to_send()
            -- the draw must reach each refusal, or the words it sends prove nothing about it
            assert.is_true(refused["double quote"] > 2, "the draw must include double-quote words")
            assert.is_true(refused.backslash > 2, "the draw must include trailing-backslash words")
            local received, diagnostics =
              shells.received_args(shell.command, to_line, words, mode.prefix)
            assert.is_not_nil(received, diagnostics)
            assert.same(words, received, diagnostics)
          end
        )
      end
    end
  end
end)

describe("terminal.core.osc and status (property)", function()
  it(
    "a user-var sequence has exactly one introducer and one terminator, whatever the value",
    function()
      local rand = xorshift(23)
      for _ = 1, 300 do
        local raw = {}
        for i = 1, rand(30) do
          raw[i] = string.char(rand(256) - 1)
        end
        local seq = osc.user_var("X", table.concat(raw))
        assert.equals(1, select(2, seq:gsub("\27", "")))
        assert.equals(1, select(2, seq:gsub("\7", "")))
        assert.equals("\7", seq:sub(-1))
      end
    end
  )

  it("a wrapped sequence contains no lone ESC except its own envelope", function()
    local var = assert(osc.user_var("X", "\27\27\7\27\\"))
    local seq = osc.wrap_tmux(var)
    -- Inside the envelope every ESC is doubled; the outer ESC P ... ESC \ is the only other use.
    local inner = seq:sub(8, -3)
    assert.equals("\27Ptmux;", seq:sub(1, 7))
    assert.equals("\27\\", seq:sub(-2))
    for run in inner:gmatch("\27+") do
      assert.equals(0, #run % 2, "an ESC run of odd length would end the envelope early")
    end
  end)

  it("sanitised status text never carries a control character", function()
    local rand = xorshift(29)
    for _ = 1, 300 do
      local bytes = {}
      for i = 1, rand(40) do
        bytes[i] = string.char(rand(256) - 1)
      end
      local s = status.build({
        mode = table.concat(bytes),
        file = table.concat(bytes),
        cwd = table.concat(bytes),
        branch = table.concat(bytes),
        recording = table.concat(bytes),
        filetype = table.concat(bytes),
      })
      for _, field in ipairs({ "mode", "file", "cwd", "branch", "rec", "ft" }) do
        assert.is_nil(s[field]:find("[%z\1-\31\127]"), field)
      end
    end
  end)

  it(
    "the encoded dataset stays within the byte limit or is refused, never truncated mid-field",
    function()
      local rand = xorshift(31)
      for _ = 1, 100 do
        local long = string.rep("x", rand(600))
        local s = status.build({ mode = "n", file = long, cwd = long, branch = long })
        local json, err = status.encode(s, 300)
        if json then
          assert.is_true(#json <= 300)
          assert.is_table(vim.json.decode(json))
        else
          assert.truthy(err)
        end
      end
    end
  )
end)

describe("terminal.backends.tmux (property)", function()
  local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/]") or "."
  local fake = dofile(here .. "/support/fakes.lua").tmux
  local tmux = require("terminal.backends.tmux")

  it("any word reaches tmux as itself: no trailing ';' ends the command or goes missing", function()
    local rand = xorshift(41)
    local run, state = fake()
    for _ = 1, 600 do
      local word = random_word(rand, 10)
      -- the interesting endings are over-represented on purpose
      local tail = ({ "", ";", ";", "\\;", ";;" })[rand(5)]
      word = word .. tail
      run({ "tmux", "send-keys", "-t", "%0", "-l", "--", tmux.word(word) })
      assert.equals(word, state.keys[#state.keys], ("%q"):format(word))
    end
    -- every call was one send-keys: nothing a word contained started another command
    for _, cmd in ipairs(state.executed) do
      assert.equals("send-keys", cmd[1])
    end
  end)
end)
