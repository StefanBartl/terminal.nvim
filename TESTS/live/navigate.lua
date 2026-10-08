---@diagnostic disable: need-check-nil
-- need-check-nil is off for the whole file: a nil handle or reply makes the next check fail anyway, and the script then ends in RESULT failed.
-- TESTS/live/navigate.lua -- the edge hand-off against a REAL WezTerm.
--
-- Run it inside a WezTerm pane (not headless):
--
--   SMOKE_OUT=/tmp/terminal-navigate.txt nvim -u NONE -i NONE -c "luafile TESTS/live/navigate.lua"
--
-- Splits a second pane to the right with `wezterm cli`, then presses "move right" from Neovim's
-- only window: nothing is further right inside Neovim, so WezTerm must focus the other pane.
-- One line per check goes to $SMOKE_OUT, ending in "RESULT ok" or "RESULT failed".

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/navigate%.lua$")
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

---@return table<string, table>
local function panes()
  local res = vim.system({ "wezterm", "cli", "list", "--format", "json" }, { text = true }):wait()
  local by_id = {}
  for _, p in ipairs(vim.json.decode(res.stdout)) do
    by_id[tostring(p.pane_id)] = p
  end
  return by_id
end

local ok, err = pcall(function()
  local own = vim.env.WEZTERM_PANE
  local terminal = require("terminal")
  terminal.setup({ commands = false, keymaps = { preset = false }, status = { enable = false } })

  local split = vim
    .system({ "wezterm", "cli", "split-pane", "--right", "--", "cmd", "/k" }, { text = true })
    :wait()
  local other = vim.trim(split.stdout or "")
  check("a second pane was created to the right", other:find("^%d+$") ~= nil, split)
  vim.wait(1500)
  -- A freshly split pane takes the focus itself; start from Neovim's pane.
  vim.system({ "wezterm", "cli", "activate-pane", "--pane-id", own }):wait()
  vim.wait(500)
  check("Neovim's pane is the active one", panes()[own] and panes()[own].is_active == true)

  check("move right at the edge reports `edge`", terminal.navigate("l") == "edge")
  local focused = vim.wait(5000, function()
    local p = panes()
    return p[other] ~= nil and p[other].is_active == true
  end, 100)
  check("WezTerm focused the pane on the right", focused)

  -- Come back (as the user would from the other pane) and try a direction with no neighbour.
  vim.system({ "wezterm", "cli", "activate-pane", "--pane-id", own }):wait()
  vim.wait(500)
  check("move left at the left edge is harmless", terminal.navigate("h") == "edge")
  vim.wait(800)
  check("focus stayed in Neovim's pane", panes()[own] and panes()[own].is_active == true)

  vim.system({ "wezterm", "cli", "kill-pane", "--pane-id", other }):wait()
end)
if not ok then
  failed = true
  out[#out + 1] = "FAIL error: " .. tostring(err)
end
out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
local f = io.open(vim.env.SMOKE_OUT or "terminal-navigate.txt", "w")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
end
vim.cmd("qa!")
