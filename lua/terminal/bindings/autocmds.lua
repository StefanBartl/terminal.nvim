---@module 'terminal.bindings.autocmds'
--- Terminal-focused autocommands, one named augroup per feature:
--- window options on open, Kitty padding on startup/exit, auto-Insert.
---@see lib.nvim.bindings.autocmd

local M = {}

--- How long exit waits for `kitty @ set-spacing` to restore the padding. The process is local and
--- answers in milliseconds; a second is the point where a hung kitty is not worth holding up the
--- quit for.
local KITTY_RESTORE_WAIT_MS = 1000

---@internal
---@param name string
---@return integer
local function augroup(name)
  -- Through `Autocmd.group(name, true)`: clearing drops the feature's previous records too, so
  -- calling `setup()` twice replaces its rows instead of doubling them.
  return require("lib.nvim.bindings.autocmd").group("terminal." .. name, true)
end

---@internal
--- Normalized window options in every terminal window, on open.
---@param cfg Terminal.Config
---@return nil
local function window_options(cfg)
  local wo = cfg.window_options
  local group = augroup("window_options")
  if not wo.enable then
    return
  end
  require("lib.nvim.bindings.autocmd").create("TermOpen", function(ev)
    -- Local options: they must not bleed into non-terminal windows.
    vim.api.nvim_buf_call(ev.buf, function()
      vim.opt_local.number = wo.number
      vim.opt_local.relativenumber = wo.relativenumber
      vim.opt_local.signcolumn = wo.signcolumn
      vim.opt_local.spell = wo.spell
      vim.opt_local.cursorline = wo.cursorline
    end)
  end, { group = group, desc = "terminal.nvim: normalize terminal window options" })
end

---@internal
--- Snug Kitty padding while editing, restored when Neovim leaves.
---@param cfg Terminal.Config
---@return nil
local function kitty(cfg)
  local Autocmd = require("lib.nvim.bindings.autocmd")
  local g_enter = augroup("kitty_enter")
  local g_leave = augroup("kitty_leave")
  if not (cfg.kitty.enable and require("lib.nvim.terminal").is_kitty()) then
    return
  end
  -- An argv list through `vim.system`, never a `:!` shell string.
  local function kitty_argv(padding, margin)
    return {
      "kitty",
      "@",
      "set-spacing",
      ("padding=%d"):format(padding),
      ("margin=%d"):format(margin),
    }
  end
  local enter_argv = kitty_argv(cfg.kitty.enter_padding, cfg.kitty.enter_margin)
  local leave_argv = kitty_argv(cfg.kitty.leave_padding, cfg.kitty.leave_margin)
  local function run(argv, wait)
    local ok, proc = pcall(vim.system, argv, { text = true })
    if ok and wait then
      pcall(function()
        proc:wait(KITTY_RESTORE_WAIT_MS)
      end)
    end
  end
  Autocmd.create("VimEnter", function()
    run(enter_argv)
  end, { group = g_enter, desc = "terminal.nvim: snug Kitty padding while editing" })
  -- A plugin manager that loads this at VeryLazy is late: VimEnter has already fired.
  if vim.v.vim_did_enter == 1 then
    run(enter_argv)
  end
  Autocmd.create("VimLeavePre", function()
    run(leave_argv, true) -- Neovim is about to exit: wait for it
  end, { group = g_leave, desc = "terminal.nvim: restore Kitty padding on exit" })
end

---@internal
--- Insert mode in every terminal buffer, on the configured events.
---@param cfg Terminal.Config
---@return nil
local function auto_insert(cfg)
  local Autocmd = require("lib.nvim.bindings.autocmd")
  local group = augroup("auto_insert")
  if not cfg.auto_insert.enable then
    return
  end
  Autocmd.create(Autocmd.norm_events(cfg.auto_insert.events, { "TermOpen" }), function(args)
    local buf = args.buf
    -- Scheduled so other handlers finish first; re-check that this buffer is still current.
    vim.schedule(function()
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.bo[buf].buftype == "terminal"
        and vim.api.nvim_get_current_buf() == buf
      then
        vim.cmd("startinsert")
      end
    end)
  end, { group = group, desc = "terminal.nvim: enter Insert mode in terminals" })
end

--- Create the autocommands the config asks for. Features switched off leave an empty group.
---@param cfg Terminal.Config
---@return nil
function M.setup(cfg)
  window_options(cfg)
  kitty(cfg)
  auto_insert(cfg)
end

return M
