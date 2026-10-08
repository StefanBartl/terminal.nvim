-- TESTS/support/shells.lua -- small models of how the target programs read a quoted word, so a
-- spec can check that quoting survives the round trip instead of comparing strings.
--
--   posix(line)   one word out of a POSIX single-quote line (as security_spec always did)
--   fish(line)    fish: inside '...' a backslash escapes `\` and `'`, any other backslash is literal
--   msvcrt(line)  the C runtime's argv rules (what a program started from cmd.exe receives):
--                 2n backslashes + quote -> n backslashes and the quote toggles,
--                 2n+1 backslashes + quote -> n backslashes and a literal quote,
--                 inside quotes `""` is a literal quote, white space outside quotes splits

local M = {}

--- Words of a line quoted with single quotes only (the POSIX form; backslash is literal).
---@param line string
---@return string[]
function M.posix(line)
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

--- Words of a fish line.
---@param line string
---@return string[]
function M.fish(line)
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
        i = i + 1
        while true do
          assert(i <= n, "unterminated quote in: " .. line)
          local q = line:sub(i, i)
          if q == "'" then
            i = i + 1
            break
          elseif
            q == "\\" and (line:sub(i + 1, i + 1) == "\\" or line:sub(i + 1, i + 1) == "'")
          then
            word[#word + 1] = line:sub(i + 1, i + 1)
            i = i + 2
          else
            word[#word + 1] = q
            i = i + 1
          end
        end
      else
        word[#word + 1] = c
        i = i + 1
      end
    end
    words[#words + 1] = table.concat(word)
  end
  return words
end

--- Arguments of a command line read by the C runtime.
---@param line string
---@return string[]
function M.msvcrt(line)
  local args, current, in_quotes, started = {}, {}, false, false
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == "\\" then
      local j = i
      while line:sub(j, j) == "\\" do
        j = j + 1
      end
      local count = j - i
      if line:sub(j, j) == '"' then
        current[#current + 1] = string.rep("\\", math.floor(count / 2))
        if count % 2 == 1 then
          current[#current + 1] = '"'
          j = j + 1
        end
      else
        current[#current + 1] = string.rep("\\", count)
      end
      i = j
      started = true
    elseif c == '"' then
      if in_quotes and line:sub(i + 1, i + 1) == '"' then
        current[#current + 1] = '"'
        i = i + 2
      else
        in_quotes = not in_quotes
        i = i + 1
      end
      started = true
    elseif c:find("%s") and not in_quotes then
      if started then
        args[#args + 1] = table.concat(current)
        current, started = {}, false
      end
      i = i + 1
    else
      current[#current + 1] = c
      started = true
      i = i + 1
    end
  end
  if started then
    args[#args + 1] = table.concat(current)
  end
  return args
end

return M
