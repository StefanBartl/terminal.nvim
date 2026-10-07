-- TESTS/live/wezterm.lua -- the wezterm backend against a REAL WezTerm.
--
-- Run it inside a WezTerm pane (not headless):
--
--   SMOKE_OUT=/tmp/terminal-wezterm.txt nvim -u NONE -i NONE -c "luafile TESTS/live/wezterm.lua"
--
-- Opens a pane through `wezterm cli`, types a command into it, reads the pane's text back with
-- `wezterm cli get-text`, focuses, hides, closes. One line per check goes to $SMOKE_OUT, ending
-- in "RESULT ok" or "RESULT failed". Needs `wezterm` on PATH and $WEZTERM_PANE.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/wezterm%.lua$")
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

local function pane_text(pane)
  local res = vim
    .system({ "wezterm", "cli", "get-text", "--pane-id", pane }, { text = true })
    :wait()
  return res.stdout or ""
end

local ok, err = pcall(function()
  local terminal = require("terminal")
  terminal.setup({
    backend = "wezterm",
    layout = "vsplit",
    commands = false,
    keymaps = { preset = false },
    status = { enable = false },
  })
  check("the wezterm backend is chosen", terminal.status().backend == "wezterm", terminal.status())

  local h = terminal.open()
  check("open creates a pane", h ~= nil and h.pane ~= nil, h)
  vim.wait(2500)
  check(
    "the pane exists",
    h ~= nil and require("terminal.backends.wezterm").available(vim.env) and #terminal.list() == 1
  )

  local sent = terminal.send("echo terminal-nvim-wezterm-check", { newline = true, name = h.name })
  check("send reports success", sent == true)
  -- The pane is narrow, so long lines are hard-wrapped: join the lines first. The word appears
  -- once in the typed command and once in its output.
  local seen = vim.wait(8000, function()
    local joined = pane_text(h.pane):gsub("%c", "")
    local _, n = joined:gsub("terminal%-nvim%-wezterm%-check", "")
    return n >= 2
  end, 300)
  check("the command's output is in the pane", seen, seen and nil or pane_text(h.pane):sub(-500))

  terminal.toggle() -- the pane is focused after open -> hands focus back to Neovim
  vim.wait(500)
  local focused_back = vim
    .system({ "wezterm", "cli", "list", "--format", "json" }, { text = true })
    :wait()
  local active
  for _, p in ipairs(vim.json.decode(focused_back.stdout)) do
    if tostring(p.pane_id) == vim.env.WEZTERM_PANE then
      active = p.is_active
    end
  end
  check("toggle hands focus back to Neovim's pane", active == true, active)

  -- A pane in another TAB: `is_active` in `wezterm cli list` is true for the active pane of every
  -- tab, so "focused" has to come from the client's focused pane (`list-clients`).
  local backend = require("terminal.backends.wezterm").new(
    require("terminal.core.registry").new(),
    nil,
    vim.env.WEZTERM_PANE
  )
  local tab = backend.spawn({
    name = "tab",
    root = "/live",
    cwd = vim.uv.cwd(),
    layout = "tab",
  })
  check("a pane in a new tab was created", tab ~= nil, tab)
  if tab then
    vim.wait(1500)
    check("the new tab's pane has the focus", backend.focused(tab) == true)
    backend.hide(tab)
    vim.wait(800)
    check(
      "back in Neovim's tab the tab pane is visible but not focused",
      backend.visible(tab) == true and backend.focused(tab) == false
    )
    backend.focus(tab)
    vim.wait(800)
    check("focus brings the tab back", backend.focused(tab) == true)
    backend.hide(tab)
    vim.wait(500)
    check("the tab pane closes", backend.close(tab) == true)
    vim.wait(500)
  end

  check("close removes the terminal", terminal.close() == true)
  vim.wait(800)
  local after = vim.system({ "wezterm", "cli", "list", "--format", "json" }, { text = true }):wait()
  local still = false
  for _, p in ipairs(vim.json.decode(after.stdout)) do
    if tostring(p.pane_id) == h.pane then
      still = true
    end
  end
  check("the pane is gone", not still)
  check("nothing is left", #terminal.list(true) == 0)
end)
if not ok then
  failed = true
  out[#out + 1] = "FAIL error: " .. tostring(err)
end
out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
local f = io.open(vim.env.SMOKE_OUT or "terminal-wezterm.txt", "w")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
end
vim.cmd("qa!")
