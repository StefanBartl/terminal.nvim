---@module 'terminal.bindings.usrcmds'
--- `:Terminal` -- one compound command, `:Terminal <action> [args] [flags]`, with `<Tab>`
--- completion (`lib.nvim.bindings.usercmd.composer`).
---
---   :Terminal                          toggle the default terminal
---   :Terminal toggle|open [name]       show / focus (create when missing); `3` is the terminal "3"
---   :Terminal hide|close [name]
---   :Terminal list                     pick one of this project's terminals
---   :Terminal send line|selection|file [name] [--exec]
---   :Terminal run [--name=] [--direct] <command...>

local M = {}

local LAYOUTS = { "float", "split", "vsplit", "tab" }

---@internal
---@type Lib.UserCmd.Composer.ArgSpec[]
local NAME_ARG = { { name = "name", type = "STRING", optional = true } }

---@internal
---@type Lib.UserCmd.Composer.FlagSpec[]
local LAYOUT_FLAG = { { name = "layout", type = "STRING", enum = LAYOUTS } }

---@internal
---@param ctx Lib.UserCmd.Composer.Ctx
---@return Terminal.Target
local function target_of(ctx)
  return {
    name = ctx.args.name,
    layout = ctx.flags.layout,
  }
end

---@internal
--- The lines a `send` route acts on.
---@param what "line"|"selection"|"file"
---@param ctx Lib.UserCmd.Composer.Ctx
---@return string[]
local function lines_for(what, ctx)
  local buf = vim.api.nvim_get_current_buf()
  if what == "file" then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  elseif what == "selection" then
    local first, last = ctx.range.line1, ctx.range.line2
    return vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  end
  return { vim.api.nvim_get_current_line() }
end

---@internal
---@param what "line"|"selection"|"file"
---@return Lib.UserCmd.Composer.Route
local function send_route(what)
  return {
    path = { "send", what },
    range = what == "selection",
    args = NAME_ARG,
    flags = { { name = "exec", bool = true } },
    desc = ("Send the %s to a terminal (typed only; --exec presses Enter)"):format(what),
    run = function(ctx)
      local text = table.concat(lines_for(what, ctx), "\n")
      require("terminal").send(text, {
        name = ctx.args.name,
        newline = ctx.flags.exec == true,
      })
    end,
  }
end

--- Register the `:Terminal` command.
---@return nil
function M.setup()
  local composer = require("lib.nvim.bindings.usercmd.composer")
  local terminal = require("terminal")

  composer.verb("Terminal", {
    desc = "Named terminals: toggle, open, hide, close, list, send, run",
    default = function()
      terminal.toggle()
    end,
    routes = {
      {
        path = { "toggle" },
        args = NAME_ARG,
        flags = LAYOUT_FLAG,
        desc = 'Toggle a terminal (the name "3" is what <A-h> with count 3 uses)',
        run = function(ctx)
          terminal.toggle(target_of(ctx))
        end,
      },
      {
        path = { "open" },
        args = NAME_ARG,
        flags = LAYOUT_FLAG,
        desc = "Show and focus a terminal, creating it when needed",
        run = function(ctx)
          terminal.open(target_of(ctx))
        end,
      },
      {
        path = { "hide" },
        args = NAME_ARG,
        desc = "Hide a terminal's window; its job keeps running",
        run = function(ctx)
          terminal.hide(target_of(ctx))
        end,
      },
      {
        path = { "close" },
        args = NAME_ARG,
        desc = "Stop a terminal's job and remove it",
        run = function(ctx)
          terminal.close(target_of(ctx))
        end,
      },
      {
        path = { "list" },
        desc = "Pick one of this project's terminals",
        run = function()
          local items = terminal.list()
          if #items == 0 then
            vim.notify("[terminal] no terminals in this project", vim.log.levels.INFO)
            return
          end
          vim.ui.select(items, {
            prompt = "Terminal",
            format_item = function(h)
              return ("%s%s"):format(h.name, h.exited and " (exited)" or "")
            end,
          }, function(choice)
            if choice then
              terminal.open({ name = choice.name })
            end
          end)
        end,
      },
      send_route("line"),
      send_route("selection"),
      send_route("file"),
      {
        path = { "run" },
        flags = {
          { name = "name", type = "STRING" },
          { name = "direct", bool = true },
          { name = "layout", type = "STRING", enum = LAYOUTS },
        },
        desc = "Run a command (typed as a line; --direct starts it as the job itself)",
        run = function(ctx)
          if #ctx.rest == 0 then
            vim.notify("[terminal] run: no command given", vim.log.levels.WARN)
            return
          end
          local opts =
            { name = ctx.flags.name, layout = ctx.flags.layout, direct = ctx.flags.direct }
          if ctx.flags.direct then
            terminal.run(ctx.rest, opts)
          else
            terminal.run(table.concat(ctx.rest, " "), opts)
          end
        end,
      },
    },
  })
end

return M
