---@diagnostic disable: need-check-nil
-- need-check-nil is off for the whole file: a nil handle or reply makes the next check fail anyway, and the script then ends in RESULT failed.
-- TESTS/live/pin.lua -- pin and adopt against a REAL WezTerm.
--
-- Run it inside a WezTerm pane (not headless):
--
--   SMOKE_OUT=/tmp/terminal-pin.txt nvim -u NONE -i NONE -c "luafile TESTS/live/pin.lua"
--
-- Opens a native terminal, pins it (it restarts as a WezTerm pane, the native one disappears),
-- types into the pane and adopts it: a read-only buffer must show what the pane shows.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/pin%.lua$")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.env.LIB_NVIM_DIR or (root .. "/../lib.nvim"))

local out, failed = {}, false

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
  terminal.setup({
    commands = false,
    keymaps = { preset = false },
    status = { enable = false },
    start_insert = false,
  })
  local native = terminal.open({ name = "pinme" })
  check("a native terminal opened", native ~= nil and native.backend == "native", native)
  vim.wait(1500)

  local pinned_ok, perr, pinned = terminal.pin({ name = "pinme" }, { backend = "wezterm" })
  check("pin succeeded", pinned_ok == true, perr)
  check("it now lives in WezTerm", pinned ~= nil and pinned.backend == "wezterm")
  check("the native buffer is gone", native ~= nil and not vim.api.nvim_buf_is_valid(native.bufnr))
  vim.wait(2000)

  terminal.send("echo terminal-nvim-pin-check", { name = "pinme", newline = true })
  vim.wait(1500)
  local buf = terminal.adopt({ name = "pinme" })
  check("adopt returned a buffer", type(buf) == "number")
  assert(buf, "adopt returned no buffer") -- the checks below need it
  local seen = vim.wait(6000, function()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "")
    return select(2, text:gsub("terminal%-nvim%-pin%-check", "")) >= 2
  end, 300)
  check(
    "the buffer shows the pane (typed command and its output)",
    seen,
    vim.api.nvim_buf_get_lines(buf, 0, 8, false)
  )
  check("the buffer is read-only", vim.bo[buf].modifiable == false)

  check("close kills the pane", terminal.close({ name = "pinme" }) == true)
  check("nothing is left", #terminal.list(true) == 0)
end)
if not ok then
  failed = true
  out[#out + 1] = "FAIL error: " .. tostring(err)
end
out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
local f = io.open(vim.env.SMOKE_OUT or "terminal-pin.txt", "w")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
end
vim.cmd("qa!")
