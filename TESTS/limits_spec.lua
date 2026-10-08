---@diagnostic disable: need-check-nil, undefined-field
-- need-check-nil and undefined-field are off for the whole file: a nil in a spec body fails the next assertion anyway, and luassert's assert.* and the stubbed vim.* fields are not in the annotations.
-- TESTS/limits_spec.lua -- unbounded input: no pattern work that is quadratic in the input, and the
-- linear replacements say exactly what the quadratic patterns did.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local quote = require("terminal.core.quote")
local status = require("terminal.core.status")

--- The quadratic pattern code that `basename` and the cmd.exe quoting replaced, kept here as the
--- reference the new code is compared with.
---@param path string
---@return string
local function reference_basename(path)
  local p = path:gsub("[/\\]+$", "")
  return p:match("([^/\\]*)$") or p
end

---@param s string
---@return string
local function reference_cmd_body(s)
  local body = s:gsub('(\\*)"', function(slashes)
    return slashes .. slashes .. '""'
  end)
  local trailing = body:match("(\\+)$")
  if trailing then
    body = body .. trailing
  end
  return body
end

--- Every string over `alphabet` up to `max_len` characters.
---@param alphabet string[]
---@param max_len integer
---@return string[]
local function all_strings(alphabet, max_len)
  local out, layer = {}, { "" }
  for _ = 1, max_len do
    local next_layer = {}
    for _, prefix in ipairs(layer) do
      for _, ch in ipairs(alphabet) do
        next_layer[#next_layer + 1] = prefix .. ch
      end
    end
    vim.list_extend(out, next_layer)
    layer = next_layer
  end
  return out
end

--- Seconds `f` takes.
---@param f fun()
---@return number
local function seconds(f)
  local started = vim.uv.hrtime()
  f()
  return (vim.uv.hrtime() - started) / 1e9
end

--- A snapshot for `status.build` with the given file name.
---@param file string
---@return Terminal.StatusSnapshot
local function snapshot(file)
  return {
    mode = "n",
    file = file,
    buftype = "",
    cwd = "/",
    branch = nil,
    diag = { error = 0, warn = 0, info = 0, hint = 0 },
    recording = "",
    modified = false,
    filetype = "",
    pid = 1,
  }
end

describe("status: the file name of the buffer", function()
  it(
    "is the last component for both separators, exactly as the pattern code computed it",
    function()
      for _, path in ipairs(all_strings({ "/", "\\", "a", "b" }, 6)) do
        local got = status.build(snapshot(path)).file
        assert.equals(reference_basename(path), got, vim.inspect(path))
      end
    end
  )

  it("a long run of separators costs linear time, not quadratic", function()
    for _, sep in ipairs({ "/", "\\" }) do
      local trailing_x = sep:rep(200000) .. "x"
      local leading_x = "x" .. sep:rep(200000)
      local took = seconds(function()
        assert.equals("x", status.build(snapshot(trailing_x)).file)
        assert.equals("x", status.build(snapshot(leading_x)).file)
      end)
      assert.is_true(took < 1, ("took %.2f s"):format(took))
    end
  end)
end)

describe("quote: cmd.exe words", function()
  it(
    'are quoted exactly as the pattern code did, for every combination of \\ " a and space',
    function()
      for _, word in ipairs(all_strings({ "\\", '"', "a", " " }, 7)) do
        if not word:find("^[%w%._/:\\@+,-]+$") then
          local got, err = quote.word(word, "cmd")
          assert.is_nil(err)
          assert.equals('"' .. reference_cmd_body(word) .. '"', got, vim.inspect(word))
        end
      end
    end
  )

  it("a long run of backslashes costs linear time, not quadratic", function()
    for _, word in ipairs({
      ("\\"):rep(200000) .. " ",
      ("\\"):rep(200000),
      ("\\"):rep(100000) .. '"' .. ("\\"):rep(100000),
      ("a\\"):rep(100000) .. " ",
    }) do
      local got
      local took = seconds(function()
        got = quote.word(word, "cmd")
      end)
      assert.is_true(took < 1, ("took %.2f s"):format(took))
      assert.is_string(got)
    end
  end)

  it("the other shells take a long word in linear time too", function()
    local word = ("a'b\\c\" "):rep(30000)
    for _, kind in ipairs({ "posix", "fish", "powershell" }) do
      local took = seconds(function()
        quote.word(word, kind)
      end)
      assert.is_true(took < 1, ("%s took %.2f s"):format(kind, took))
    end
  end)
end)
