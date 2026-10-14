---@module 'terminal.cheatsheet.ui'
--- The cheatsheet window: a read-only Markdown float at the right edge of the editor, so the
--- terminal it belongs to stays visible. One section at a time; `]]` / `[[` (or `<Tab>` /
--- `<S-Tab>`) turn the page, `/` searches every section, `g?` switches to the common sheet, `s` picks
--- another shell, `<CR>` types the command on the cursor line into the terminal (no Enter) and
--- `q` / `<Esc>` close it, back where the cursor was (in terminal mode when it came from there).
---@see terminal.cheatsheet

local parse = require("terminal.cheatsheet.parse")
local detect = require("terminal.cheatsheet.detect")

local api = vim.api

local M = {}

--- What the window needs from the caller: the sheet to show and how to reach the rest.
---@class Terminal.CheatContext
---@field load fun(key: string): Terminal.CheatSheet|nil, string|nil Load another sheet
---@field names fun(): string[] Keys that have a sheet
---@field type_line fun(text: string) Type a command into the terminal the sheet was opened from
---@field prev_win integer The window the cursor was in
---@field was_terminal boolean The cursor was in terminal mode
---@field zindex? integer
---@field notify fun(msg: string, level?: integer)
---@field select? fun(items: string[], opts: table, on_choice: fun(item: string|nil)) Default `vim.ui.select`
---@field input? fun(opts: table, on_confirm: fun(text: string|nil)) Default `vim.ui.input`

--- Where and how big the float is, for an editor of this size.
---@param columns integer
---@param lines integer
---@return { width: integer, height: integer, row: integer, col: integer }
function M.geometry(columns, lines)
  local width = math.min(72, math.max(36, math.floor(columns * 0.4)))
  width = math.min(width, math.max(columns - 4, 10))
  local usable = math.max(lines - 4, 3)
  local height = math.min(usable, math.max(10, math.floor(usable * 0.85)))
  return { width = width, height = height, row = 1, col = math.max(columns - width - 2, 0) }
end

--- The float's title: shell, position and the section.
---@param key string
---@param index integer
---@param total integer
---@param section string
---@return string
function M.title(key, index, total, section)
  return (" %s · %d/%d %s "):format(key, index, total, section)
end

--- The section after (`delta` = 1) or before (-1) `index`, turning around at the ends.
---@param index integer
---@param delta integer
---@param total integer
---@return integer
function M.turn(index, delta, total)
  return ((index - 1 + delta) % total) + 1
end

--- Open the window.
---@param sheet Terminal.CheatSheet
---@param ctx Terminal.CheatContext
---@return { close: fun(), buf: integer, win: integer }|nil
function M.open(sheet, ctx)
  local geo = M.geometry(vim.o.columns, vim.o.lines)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  local ok, win = pcall(api.nvim_open_win, buf, true, {
    relative = "editor",
    width = geo.width,
    height = geo.height,
    row = geo.row,
    col = geo.col,
    style = "minimal",
    border = "rounded",
    title = " cheatsheet ",
    title_pos = "center",
    zindex = ctx.zindex or 60,
  })
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    ctx.notify("cheatsheet: cannot open the window: " .. tostring(win), vim.log.levels.WARN)
    return nil
  end
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].cursorline = true

  local ns = api.nvim_create_namespace("terminal.cheatsheet")
  local state = { sheet = sheet, home = sheet.key, index = 1, matches = {}, match = 0 }

  local function section()
    return state.sheet.sections[state.index]
  end

  local function render()
    local sec = section()
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, sec.lines)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_set_cursor, win, { 1, 0 })
      pcall(api.nvim_win_set_config, win, {
        title = M.title(state.sheet.key, state.index, #state.sheet.sections, sec.title),
        title_pos = "center",
      })
    end
  end

  local function close()
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
    if api.nvim_win_is_valid(ctx.prev_win) then
      api.nvim_set_current_win(ctx.prev_win)
      if ctx.was_terminal and vim.bo[api.nvim_win_get_buf(ctx.prev_win)].buftype == "terminal" then
        vim.cmd("startinsert")
      end
    end
  end

  local function go(delta)
    state.index = M.turn(state.index, delta, #state.sheet.sections)
    render()
  end

  local function show_match()
    local m = state.matches[state.match]
    if not m then
      return
    end
    state.index = m.section
    render()
    local text = section().lines[m.line] or ""
    pcall(api.nvim_win_set_cursor, win, { m.line, m.col })
    pcall(api.nvim_buf_set_extmark, buf, ns, m.line - 1, m.col, {
      end_col = math.min(m.col + #state.query, #text),
      hl_group = "Search",
    })
  end

  local function step(delta)
    if #state.matches == 0 then
      ctx.notify("cheatsheet: no search yet (press /)")
      return
    end
    state.match = ((state.match - 1 + delta) % #state.matches) + 1
    show_match()
  end

  local function search()
    local ask = ctx.input or vim.ui.input
    ask({ prompt = "Search all sections: " }, function(query)
      if not query or query == "" then
        return
      end
      state.query = query
      state.matches = parse.search(state.sheet.sections, query)
      if #state.matches == 0 then
        ctx.notify(("cheatsheet: nothing matches '%s'"):format(query))
        return
      end
      -- start at the first match from the current section on
      state.match = 1
      for i, m in ipairs(state.matches) do
        if m.section >= state.index then
          state.match = i
          break
        end
      end
      show_match()
    end)
  end

  local function switch(key)
    local loaded, err = ctx.load(key)
    if not loaded then
      ctx.notify("cheatsheet: " .. tostring(err), vim.log.levels.WARN)
      return
    end
    state.sheet, state.index, state.matches, state.match = loaded, 1, {}, 0
    render()
  end

  local function toggle_common()
    switch(state.sheet.key == detect.COMMON and state.home or detect.COMMON)
  end

  local function pick_shell()
    local ask = ctx.select or vim.ui.select
    ask(ctx.names(), { prompt = "Cheatsheet for" }, function(choice)
      if choice then
        switch(choice)
      end
    end)
  end

  local function type_line()
    local cmd = parse.command_of(api.nvim_get_current_line())
    if not cmd then
      ctx.notify("cheatsheet: no command on this line")
      return
    end
    close()
    ctx.type_line(cmd)
  end

  local function map(lhs, fn, desc)
    vim.keymap.set(
      "n",
      lhs,
      fn,
      { buffer = buf, nowait = true, silent = true, desc = "cheatsheet: " .. desc }
    )
  end
  map("]]", function()
    go(1)
  end, "next section")
  map("<Tab>", function()
    go(1)
  end, "next section")
  map("[[", function()
    go(-1)
  end, "previous section")
  map("<S-Tab>", function()
    go(-1)
  end, "previous section")
  map("/", search, "search all sections")
  map("n", function()
    step(1)
  end, "next match")
  map("N", function()
    step(-1)
  end, "previous match")
  map("g?", toggle_common, "common sheet / back")
  map("s", pick_shell, "pick the shell")
  map("<CR>", type_line, "type the command on this line into the terminal")
  map("q", close, "close")
  map("<Esc>", close, "close")

  render()
  return { close = close, buf = buf, win = win, state = state }
end

return M
