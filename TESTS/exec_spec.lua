---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/exec_spec.lua -- terminal.core.exec: the one runner behind the backends, the exporter and the health check.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local exec = require("terminal.core.exec")

--- A child Neovim that runs `ex` and quits: a program that exists on every platform.
---@param ex string
---@return string[]
local function nvim(ex)
  return { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-c", ex }
end

describe("terminal.core.exec", function()
  it("returns the exit code, stdout and stderr of a command that ran", function()
    local res =
      exec.run(nvim("lua io.stdout:write('out'); io.stderr:write('err'); vim.cmd('cquit 3')"))
    assert.equals(3, res.code)
    assert.truthy(res.stdout:find("out", 1, true), vim.inspect(res))
    assert.truthy(res.stderr:find("err", 1, true), vim.inspect(res))
  end)

  it("reports success as code 0", function()
    assert.equals(0, exec.run(nvim("qa!")).code)
  end)

  it("a program that does not exist is code 127 with the reason, never an error", function()
    local ok, res = pcall(exec.run, { "terminal-nvim-no-such-program-xyz" })
    assert.is_true(ok, tostring(res))
    assert.equals(127, res.code)
    assert.equals("", res.stdout)
    assert.is_true(#res.stderr > 0)
  end)

  it("a command that outlives its timeout is stopped and reported as failed", function()
    local started = vim.uv.hrtime()
    local res = exec.run(nvim("sleep 20"), { timeout = 300 })
    local took = (vim.uv.hrtime() - started) / 1e9
    assert.is_true(took < 10, ("took %.1f s"):format(took))
    assert.is_true(res.code ~= 0, vim.inspect(res))
  end)

  it("passes stdin on", function()
    local res = exec.run({ "sort" }, { stdin = "b\na\n" })
    assert.equals(0, res.code)
    assert.same({ "a", "b" }, vim.split(vim.trim(res.stdout), "%s+", { trimempty = true }))
  end)

  it("never hands the command to a shell: an argument stays one argument", function()
    local word = "a b;c & d $HOME `x`"
    local argv = nvim("lua io.stdout:write(vim.v.argv[#vim.v.argv]); vim.cmd('qa!')")
    vim.list_extend(argv, { "--", word })
    local res = exec.run(argv)
    assert.equals(0, res.code, vim.inspect(res))
    assert.equals(word, res.stdout)
  end)
end)
