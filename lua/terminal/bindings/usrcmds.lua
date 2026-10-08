---@module 'terminal.bindings.usrcmds'
--- `:Terminal` -- one compound command, `:Terminal <action> [args] [flags]`, with `<Tab>`
--- completion (`lib.nvim.bindings.usercmd.composer`).
---
---   :Terminal                          toggle the default terminal
---   :Terminal toggle|open [name] [--layout=]
---                                      show / focus (create when missing); `3` is the terminal "3"
---   :Terminal hide|close [name]
---   :Terminal pin [name] [--backend=] [--layout=]
---                                      restart a native terminal as a tmux / WezTerm pane
---   :Terminal adopt [name]             view a multiplexer pane's screen in a read-only buffer
---   :Terminal list                     pick one of this project's terminals
---   :Terminal send line|selection|file [name] [--exec]
---   :Terminal run [--name=] [--layout=] [--direct] [--] <command...>
---
--- `--layout=` takes float, split, vsplit or tab; `--backend=` takes tmux or wezterm.
---@see lib.nvim.bindings.usercmd.composer

local notify = require("terminal.notify")

local M = {}

local LAYOUTS = require("terminal.backends").LAYOUTS

---@internal
--- The optional terminal-name argument. `desc` is the line the option float shows for it; `kind`
--- is the argument type that completes it: `TERMINAL` offers what is open plus the configured
--- names and the counts and accepts any other name, `TERMINAL_LIVE` offers only what is open. An
--- unknown name is accepted at the prompt either way, the command then says there is none.
---@param desc string
---@param kind "TERMINAL"|"TERMINAL_LIVE"
---@return Lib.UserCmd.Composer.ArgSpec[]
local function name_arg(desc, kind)
  return { { name = "name", type = kind, optional = true, desc = desc } }
end

---@internal
--- A name that may be new (toggle, open): the terminal is created when missing.
---@type Lib.UserCmd.Composer.ArgSpec[]
local NAME_ARG =
  name_arg("Terminal name, created when missing (default: config default_name)", "TERMINAL")

---@internal
--- Where `send` types to: the `run.name` terminal unless named, created when missing.
---@type Lib.UserCmd.Composer.ArgSpec[]
local SEND_NAME_ARG =
  name_arg("Terminal to send to, created when missing (default: config run.name)", "TERMINAL")

---@internal
--- A terminal that has to exist (hide, close); the command says when there is none.
---@type Lib.UserCmd.Composer.ArgSpec[]
local LIVE_NAME_ARG =
  name_arg("Existing terminal of this project (default: config default_name)", "TERMINAL_LIVE")

---@internal
--- Candidates that start with what is typed.
---@param names string[]
---@param lead string
---@return string[]
local function starting_with(names, lead)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, names)
end

---@internal
--- Register the argument types for terminal names. Candidates are read when Tab is pressed, from
--- the registry, so a terminal opened a moment ago completes.
---@param composer table `lib.nvim.bindings.usercmd.composer`
---@return nil
local function register_name_types(composer)
  local function accept(raw)
    return true, raw, nil
  end
  composer.register_type("TERMINAL_LIVE", {
    desc = "name of a terminal open in this project",
    validate = accept,
    complete = function(lead)
      return starting_with(require("terminal").names(), lead)
    end,
  })
  composer.register_type("TERMINAL", {
    desc = "terminal name (new or existing); a number N is what <A-h> with count N uses",
    validate = accept,
    complete = function(lead)
      local config = require("terminal.config")
      local names = require("terminal").names()
      for _, name in ipairs({ config.get("default_name"), config.get("run.name") }) do
        names[#names + 1] = name
      end
      for count = 1, 9 do
        names[#names + 1] = tostring(count)
      end
      -- each name once, the open ones first
      local seen, out = {}, {}
      for _, name in ipairs(names) do
        if not seen[name] then
          seen[name] = true
          out[#out + 1] = name
        end
      end
      return starting_with(out, lead)
    end,
  })
end

---@internal
--- What each layout looks like, for the option float (the native backend's windows; a
--- multiplexer maps split/vsplit/tab to a pane below, a pane to the right and a new tab).
---@type table<string, string>
local LAYOUT_ENUM_DESC = {
  float = "floating window over the editor",
  split = "horizontal split below",
  vsplit = "vertical split on the right",
  tab = "separate tab page",
}

---@internal
---@type Lib.UserCmd.Composer.FlagSpec[]
local LAYOUT_FLAG = {
  {
    name = "layout",
    type = "STRING",
    enum = LAYOUTS,
    desc = "Window layout of the terminal (default: config layout)",
    enum_desc = LAYOUT_ENUM_DESC,
  },
}

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
--- Whether the command line that is running right now has the Visual marks as its range
--- (`'<,'>...`, with modifiers such as `silent` in front of it).
---
--- The command cannot tell by itself: `range.mode` and the `'<`/`'>` marks only say which
--- selection was made *last*, and a range typed by hand after it (`:2,3Terminal ...`) arrives
--- looking the same. Neovim writes `'<,'>` into the command line when `:` is pressed in Visual mode,
--- so the finished line is what shows that the range was meant as the selection. It is read at
--- `CmdlineLeave`, just before the line runs; it is the line that counts, not the command history,
--- which a mapped `:` line never reaches. `<Cmd>` mappings and Lua calls have no command line and
--- so never name the marks.
---
--- The flag is taken by the first command that asks (one line, one answer) and dropped at the end
--- of the event-loop turn, so a Lua call made later cannot pick up an earlier line.
local line_names_marks = false

---@internal
--- Modifiers (`silent`, `keepjumps`, `2verbose` ...) are lower case, a user command is not; so
--- everything in front of the range being lower case, digits, blanks, `:` and `!` means that
--- nothing but modifiers comes first. Neovim files `:silent` typed in Visual mode as
--- `silent:'<,'>cmd`. The range is `'<,'>` or its alias `*` (Neovim's `:*` is `:'<,'>`).
---@param line string
---@return boolean
local function names_marks(line)
  return line:find("^[%l%d%s:!]*'<,'>") ~= nil or line:find("^[%l%d%s:!]*%*") ~= nil
end

---@internal
--- `CmdlineLeave` handler: remember whether the line that is about to run named the marks.
---@return nil
local function note_command_line()
  line_names_marks = not vim.v.event.abort and names_marks(vim.fn.getcmdline())
  if line_names_marks then
    vim.schedule(function()
      line_names_marks = false
    end)
  end
end

---@internal
--- The text of the last blockwise Visual selection, as a yank of it gives. The marks cannot say it:
--- a block made with `$` (every row to its own end) leaves marks that look like any block whose
--- corner sits on a shorter row, and a corner drawn into the empty space past a line (`virtualedit`)
--- is dropped as soon as Visual mode is left. Both are known only in Visual mode itself, so it is
--- entered again with `gv` for the length of the reading and left again; the cursor and the view
--- are put back.
---
--- After `gv` the wanted column of the cursor (`curswant`) is `v:maxcol` exactly when `$` was used.
--- `getregion` knows nothing of that and cuts every row at the column of the cursor, which is past
--- the end of the row it is on and so not the end of the others; a block with `$` is therefore taken
--- row by row, from its left edge (`getregionpos` keeps a multibyte character whole and knows tabs)
--- to the end of THAT row, as a yank of it gives. A row that ends before the left edge has nothing
--- in the block (empty here, a yank pads it with blanks).
---@return string[]|nil rows nil when the selection cannot be had
local function block_text()
  local view = vim.fn.winsaveview()
  local ok, lines = pcall(function()
    vim.cmd("silent keepjumps normal! gv")
    local from, to = vim.fn.getpos("v"), vim.fn.getpos(".")
    if vim.fn.getcurpos()[5] ~= vim.v.maxcol then
      return vim.fn.getregion(from, to, { type = "\22" })
    end
    local out = {}
    for i, row in ipairs(vim.fn.getregionpos(from, to, { type = "\22" })) do
      local start = row[1]
      local line = vim.api.nvim_buf_get_lines(0, start[2] - 1, start[2], false)[1] or ""
      if start[3] == 0 or start[3] > #line then
        -- the row has no character at or after the left edge
        out[i] = ""
      elseif start[4] > 0 then
        -- The left edge cuts a Tab or a wide character in two (`start[4]` cells of it lie left of
        -- the edge): what is inside the block becomes blanks, as `getregion` and a yank do.
        local after = vim.fn.byteidx(line, vim.fn.charidx(line, start[3] - 1) + 1)
        local width = vim.fn.strdisplaywidth(line:sub(1, after))
          - vim.fn.strdisplaywidth(line:sub(1, start[3] - 1))
        out[i] = (" "):rep(math.max(width - start[4], 0)) .. line:sub(after + 1)
      else
        out[i] = line:sub(start[3])
      end
    end
    return out
  end)
  if vim.fn.mode():find("^[vV\22]") then
    pcall(function()
      vim.cmd("silent! normal! \27")
    end)
  end
  pcall(vim.fn.winrestview, view)
  if not ok or type(lines) ~= "table" or #lines == 0 then
    return nil
  end
  return lines
end

---@internal
--- The line range an Ex command gets for a mark pair: a closed fold is taken whole, so the range
--- starts at its first line and ends at its last, not at the line the mark is on.
---@param from integer[] `getpos("'<")`
---@param to integer[] `getpos("'>")`
---@return integer line1
---@return integer line2
local function marks_as_range(from, to)
  local first = vim.fn.foldclosed(from[2])
  local last = vim.fn.foldclosedend(to[2])
  return first ~= -1 and first or from[2], last ~= -1 and last or to[2]
end

---@internal
--- The text of a Visual selection that is exactly the range the command was given: the characters
--- of a characterwise selection, the block of a blockwise one (to the end of every row after `$`).
--- nil when the range does not come from a characterwise / blockwise selection: a linewise one, a
--- range typed by hand (`:2,3`, also when it covers the lines of an older selection), or a call
--- without a command line.
---@param range Lib.UserCmd.Composer.RangeInfo
---@return string[]|nil
local function visual_text(range)
  local named = line_names_marks
  line_names_marks = false
  if not named or (range.mode ~= "v" and range.mode ~= "\22") then
    return nil
  end
  local from, to = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  -- `'<,'>` can be followed by an offset (`'<,'>+1`): only trust the marks for the range they give.
  local line1, line2 = marks_as_range(from, to)
  if line1 ~= range.line1 or line2 ~= range.line2 then
    return nil
  end
  if range.mode == "\22" then
    return block_text()
  end
  local ok, lines = pcall(vim.fn.getregion, from, to, { type = range.mode })
  if not ok or type(lines) ~= "table" or #lines == 0 then
    return nil
  end
  return lines
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
    local text = visual_text(ctx.range)
    if text then
      return text
    end
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
    args = SEND_NAME_ARG,
    flags = {
      {
        name = "exec",
        bool = true,
        desc = what == "line" and "Press Enter after the line so the shell runs it"
          or "Press Enter after the text (required for several lines)",
      },
    },
    desc = ("Send the %s to a terminal (typed only; --exec presses Enter)"):format(what),
    run = function(ctx)
      local lines = lines_for(what, ctx)
      if #lines > 1 and ctx.flags.exec ~= true then
        -- Typing a line break into a shell presses Enter: every line but the last would run.
        notify.warn(
          ("%d lines would be executed one by one: add --exec to run them, or send a single line"):format(
            #lines
          )
        )
        return
      end
      local text = table.concat(lines, "\n")
      require("terminal").send(text, {
        name = ctx.args.name,
        newline = ctx.flags.exec == true,
      })
    end,
  }
end

--- Split the raw words of `:Terminal run ...` into the leading flags and the command.
---
--- The words come from the unparsed command line (`ctx.raw.fargs`), so what follows the flags is
--- passed on **verbatim**: a `--` ends the flags and is itself dropped, any later `--word` or a
--- second `--` stays part of the command.
---@param fargs string[] Words of the command line, starting with the subcommand `run`
---@return Terminal.RunOpts opts # name / layout / direct
---@return string[] command
function M.parse_run(fargs)
  local opts = {}
  local i = 2 -- fargs[1] is "run"
  while i <= #fargs do
    local w = fargs[i]
    if w == "--" then
      i = i + 1
      break
    elseif w == "--direct" then
      opts.direct = true
    elseif w:find("^%-%-name=") then
      opts.name = w:sub(8)
    elseif w:find("^%-%-layout=") then
      opts.layout = w:sub(10)
    else
      break
    end
    i = i + 1
  end
  local command = {}
  for j = i, #fargs do
    command[#command + 1] = fargs[j]
  end
  return opts, command
end

--- Register the `:Terminal` command.
---@return nil
function M.setup()
  local composer = require("lib.nvim.bindings.usercmd.composer")
  local terminal = require("terminal")
  register_name_types(composer)
  line_names_marks = false
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = vim.api.nvim_create_augroup("terminal.usrcmds", { clear = true }),
    pattern = ":",
    callback = note_command_line,
    desc = "terminal.nvim: note whether :Terminal send selection was given the '<,'> range",
  })

  composer.verb("Terminal", {
    desc = "Named terminals of this project",
    -- The command-level range comes from the verb, not from the first route that sets one:
    -- without this `:'<,'>Terminal send selection` fails with E481 (`send line` has none).
    range = true,
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
        args = LIVE_NAME_ARG,
        desc = "Hide a terminal's window; its job keeps running",
        run = function(ctx)
          local ok, err = terminal.hide(target_of(ctx))
          if not ok then
            notify.warn(err or "cannot hide")
          end
        end,
      },
      {
        path = { "close" },
        args = LIVE_NAME_ARG,
        desc = "Stop a terminal's job and remove it",
        run = function(ctx)
          local ok, err = terminal.close(target_of(ctx))
          if not ok then
            notify.warn(err or "cannot close")
          end
        end,
      },
      {
        path = { "pin" },
        args = name_arg(
          "Native terminal to restart as a pane (default: config default_name)",
          "TERMINAL_LIVE"
        ),
        flags = {
          {
            name = "backend",
            type = "STRING",
            enum = { "tmux", "wezterm" },
            desc = "Multiplexer for the new pane (default: tmux, else wezterm)",
          },
          {
            name = "layout",
            type = "STRING",
            enum = LAYOUTS,
            desc = "Pane layout in the multiplexer (default: vsplit)",
            enum_desc = {
              float = "pane to the right (a pane cannot float)",
              split = "pane below",
              vsplit = "pane to the right",
              tab = "new tab or window",
            },
          },
        },
        desc = "Restart a native terminal as a pane of tmux/WezTerm so it outlives Neovim",
        run = function(ctx)
          terminal.pin(
            { name = ctx.args.name },
            { backend = ctx.flags.backend, layout = ctx.flags.layout }
          )
        end,
      },
      {
        path = { "adopt" },
        args = name_arg(
          "Multiplexer terminal to view (default: config default_name)",
          "TERMINAL_LIVE"
        ),
        desc = "Show a tmux/WezTerm terminal's screen in a read-only buffer",
        run = function(ctx)
          terminal.adopt({ name = ctx.args.name })
        end,
      },
      {
        path = { "list" },
        desc = "Pick one of this project's terminals",
        run = function()
          local items = terminal.list()
          if #items == 0 then
            notify.info("no terminals in this project")
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
          {
            name = "name",
            type = "TERMINAL",
            desc = "Name of the terminal to use (default: config run.name)",
          },
          {
            name = "direct",
            bool = true,
            desc = "Start the command as the terminal's job, no shell",
          },
          LAYOUT_FLAG[1],
        },
        desc = "Run a command (typed as a line; --direct starts it as the job itself); put -- before a command with dashed words",
        run = function(ctx)
          local opts, command = M.parse_run(ctx.raw.fargs or {})
          if #command == 0 then
            notify.warn("run: no command given")
            return
          end
          if opts.direct then
            terminal.run(command, opts)
          else
            terminal.run(table.concat(command, " "), opts)
          end
        end,
      },
    },
  })
end

return M
