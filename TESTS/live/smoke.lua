---@diagnostic disable: need-check-nil
-- need-check-nil is off for the whole file: a nil handle or reply makes the next check fail anyway, and the script then ends in RESULT failed.
-- TESTS/live/smoke.lua -- the part the headless specs cannot cover: real terminals in a real UI.
--
-- Run it inside a real Neovim (a terminal window, not --headless):
--
--   SMOKE_OUT=/tmp/terminal-smoke.txt nvim -u NONE -i NONE -c "luafile TESTS/live/smoke.lua"
--
-- It opens an interactive shell terminal, types a command into it, reads the echo back from
-- the buffer, toggles it away and back, runs a command with an exit code, closes everything,
-- writes one line per check to $SMOKE_OUT and quits. Every line starting with "FAIL" is a
-- failed check; the file ends with "RESULT ok" or "RESULT failed".
--
-- Why this exists: in a headless Neovim on Windows the stdin of a terminal job is closed
-- (interactive shells exit at once, writing to the job hangs the editor), so TESTS/*_spec.lua
-- records what `send` would write instead of writing it. This script writes for real.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/smoke%.lua$")
local lib = vim.env.LIB_NVIM_DIR or (root .. "/../lib.nvim")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(lib)

local out = {}
local failed = false

---@param name string
---@param cond boolean
---@param detail? any
local function check(name, cond, detail)
  if cond then
    out[#out + 1] = "ok   " .. name
  else
    failed = true
    out[#out + 1] = ("FAIL %s%s"):format(
      name,
      detail ~= nil and (" -- " .. vim.inspect(detail)) or ""
    )
  end
end

local ok, err = pcall(function()
  local terminal = require("terminal")
  terminal.setup({ on_exit = "keep", start_insert = false })

  local h = terminal.open()
  check("open creates a terminal", h ~= nil)
  vim.wait(1500)
  check("the shell is still running after 1.5 s", h ~= nil and h.exited ~= true)

  local sent = terminal.send("echo terminal-nvim-live-check", { newline = true, name = h.name })
  check("send reports success", sent == true)
  local seen = vim.wait(5000, function()
    for _, l in ipairs(vim.api.nvim_buf_get_lines(h.bufnr, 0, -1, false)) do
      -- The typed command line also contains the word; only the OUTPUT line is exactly the word.
      if l:find("^terminal%-nvim%-live%-check%s*$") then
        return true
      end
    end
    return false
  end, 100)
  check("the echo appears in the terminal buffer", seen)

  local wins = #vim.fn.win_findbuf(h.bufnr)
  check("visible after open", wins == 1, wins)
  terminal.toggle()
  check("toggle hides it", #vim.fn.win_findbuf(h.bufnr) == 0)
  terminal.toggle()
  check("toggle shows it again", #vim.fn.win_findbuf(h.bufnr) == 1)

  local code
  local argv = vim.fn.has("win32") == 1 and { "cmd", "/c", "exit", "3" } or { "sh", "-c", "exit 3" }
  terminal.run(argv, {
    direct = true,
    name = "job",
    on_exit = function(c)
      code = c
    end,
  })
  vim.wait(5000, function()
    return code ~= nil
  end, 50)
  check("direct run reports the exit code", code == 3, code)

  check("close removes the main terminal", terminal.close() == true)
  check("close removes the job terminal", terminal.close({ name = "job" }) == true)
  check("nothing is left", #terminal.list(true) == 0, #terminal.list(true))
end)
if not ok then
  failed = true
  out[#out + 1] = "FAIL error: " .. tostring(err)
end

out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
local f = io.open(vim.env.SMOKE_OUT or "terminal-smoke.txt", "w")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
end
vim.cmd("qa!")
