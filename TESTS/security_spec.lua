---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/security_spec.lua -- property tests for everything that turns attacker-controlled text
-- (file names, branch names, selections, config values) into something a shell or a terminal
-- interprets. Seeded and deterministic: a failure reproduces.

local quote = require("terminal.core.quote")
local osc = require("terminal.core.osc")
local status = require("terminal.core.status")

-- A small deterministic generator (no math.random: the sequence must not change between runs).
local function lcg(seed)
  local state = seed
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return (state % n) + 1
  end
end

-- Characters that matter to shells and terminals.
local ALPHABET = {
  "a",
  "Z",
  "0",
  " ",
  "\t",
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

describe("terminal.core.quote (property)", function()
  it("posix: whatever the words, a POSIX shell parses the line back to the same words", function()
    local rand = lcg(20261007)
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

  it(
    "powershell: every quote character inside a quoted word is doubled, so none ends it",
    function()
      local rand = lcg(7)
      local quotes = { "'", "\226\128\152", "\226\128\153", "\226\128\154", "\226\128\155" }
      for _ = 1, 400 do
        local word = random_word(rand, 14)
        local q = quote.word(word, "powershell")
        if q:sub(1, 1) == "'" then
          local inner = q:sub(2, -2)
          for _, quote_char in ipairs(quotes) do
            -- Remove every doubled pair; what is left must contain no quote character.
            local rest = inner:gsub(quote_char .. quote_char, "")
            assert.is_nil(rest:find(quote_char, 1, true), ("%q -> %q"):format(word, q))
          end
        else
          assert.is_truthy(q:find("^[%w%._/:\\-]+$"), q)
        end
      end
    end
  )

  it("powershell: a bare word never starts a statement, splat, array or operator", function()
    local rand = lcg(11)
    for _ = 1, 400 do
      local q = quote.word(random_word(rand, 10), "powershell")
      if q:sub(1, 1) ~= "'" then
        assert.is_nil(q:find('[;&|<>(){}@,%%+=$`#!"]'), q)
      end
    end
  end)

  it("cmd: a quoted word never contains an unescaped quote or a percent sign", function()
    local rand = lcg(13)
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

  it("no family ever returns a line with a control character", function()
    local rand = lcg(17)
    for _, kind in ipairs({ "posix", "powershell", "cmd" }) do
      for _ = 1, 200 do
        local line = quote.argv_to_line({ "echo", random_word(rand, 10) }, kind)
        if line then
          assert.is_nil(line:find("[%z\1-\8\10-\31\127]"), kind)
        end
      end
    end
  end)
end)

describe("terminal.core.osc and status (property)", function()
  it(
    "a user-var sequence has exactly one introducer and one terminator, whatever the value",
    function()
      local rand = lcg(23)
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
    local seq = osc.wrap_tmux(osc.user_var("X", "\27\27\7\27\\"))
    -- Inside the envelope every ESC is doubled; the outer ESC P ... ESC \ is the only other use.
    local inner = seq:sub(8, -3)
    assert.equals("\27Ptmux;", seq:sub(1, 7))
    assert.equals("\27\\", seq:sub(-2))
    for run in inner:gmatch("\27+") do
      assert.equals(0, #run % 2, "an ESC run of odd length would end the envelope early")
    end
  end)

  it("sanitised status text never carries a control character", function()
    local rand = lcg(29)
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
      local rand = lcg(31)
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
