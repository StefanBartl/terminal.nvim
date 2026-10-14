---@module 'terminal.picker'
--- One list over this project's terminals: open one, close one, send a line to one. With the
--- kit of lib.nvim it is an interactive picker (typed words filter, a preview shows the last lines
--- of the terminal); without it (an older lib.nvim, no UI) `vim.ui.select` asks for the terminal
--- and then for the action.
---
--- The module takes the facade as an argument (`Terminal.PickerApi`), like `terminal.sessions`, so
--- specs hand in a double and nothing here needs a running backend.
---@see terminal.sessions

local M = {}

--- The prompt keys of the kit picker (`<CR>` opens, `<Tab>` marks, as in every kit picker).
M.KEYS = { close = "<C-x>", send = "<C-s>" }

--- How many trailing lines of a terminal the preview shows.
M.PREVIEW_LINES = 40

--- The facade functions this module needs; specs hand in a double.
---@class Terminal.PickerApi
---@field list fun(all?: boolean): Terminal.Handle[]
---@field open fun(target: Terminal.Target): Terminal.Handle|nil, string|nil
---@field close fun(target: Terminal.Target): boolean, string|nil
---@field send fun(text: string, opts?: Terminal.SendOpts): boolean, string|nil

---@class Terminal.PickerOpts
---@field all? boolean Every project's terminals, not just this one's
---@field engine? "auto"|"select" `select`: always `vim.ui.select`
---@field kit? table Test double for `lib.nvim.ui.kit.picker`
---@field select? fun(items: any[], opts: table, on_choice: fun(item: any|nil)) Default `vim.ui.select`
---@field input? fun(opts: table, on_confirm: fun(text: string|nil)) Default `vim.ui.input`

---@class Terminal.PickerItem
---@field handle Terminal.Handle
---@field text string What the typed words are matched against

---@internal
---@param h Terminal.Handle
---@return string
local function state_of(h)
  if h.exited then
    return h.exit_code and ("exited %d"):format(h.exit_code) or "exited"
  end
  return h.backend
end

--- The rows of the list: one per terminal, in creation order.
---@param handles Terminal.Handle[]
---@return Terminal.PickerItem[]
function M.items(handles)
  local items = {}
  for _, h in ipairs(handles) do
    if not h.disposed then
      items[#items + 1] = { handle = h, text = ("%s %s %s"):format(h.name, h.layout, state_of(h)) }
    end
  end
  return items
end

--- A row as highlighted text parts.
---@param item Terminal.PickerItem
---@return string[][]
function M.format(item)
  local h = item.handle
  return {
    { h.name, h.exited and "Comment" or "Title" },
    { ("  %s, %s"):format(h.layout, state_of(h)), "Comment" },
  }
end

--- The last lines of a terminal for the preview. Only a native terminal has a buffer to read; a
--- multiplexer pane lives in another process, and asking it would block on every cursor move.
---@param h Terminal.Handle
---@return string[]
function M.preview_lines(h)
  if h.bufnr and vim.api.nvim_buf_is_valid(h.bufnr) then
    -- Only the tail: a terminal buffer can hold thousands of lines of scrollback, and the rows
    -- below the cursor are blank padding up to the window height (cut below).
    local total = vim.api.nvim_buf_line_count(h.bufnr)
    local from = math.max(0, total - M.PREVIEW_LINES * 4)
    local lines = vim.api.nvim_buf_get_lines(h.bufnr, from, -1, false)
    while #lines > 0 and lines[#lines] == "" do
      lines[#lines] = nil
    end
    local first = math.max(1, #lines - M.PREVIEW_LINES + 1)
    return vim.list_slice(lines, first, #lines)
  end
  return {
    ("%s pane %s"):format(h.backend, h.pane or "?"),
    "(no preview: the pane is not a buffer)",
  }
end

---@internal
---@param api Terminal.PickerApi
---@param h Terminal.Handle
---@param opts Terminal.PickerOpts
local function send_line(api, h, opts)
  local ask = opts.input or vim.ui.input
  ask({ prompt = ("Send to %s (Enter runs it): "):format(h.name) }, function(text)
    if text and text ~= "" then
      api.send(text, { name = h.name, newline = true })
    end
  end)
end

---@internal
--- The picker of the kit; nil when the kit is not there or could not open.
---@param api Terminal.PickerApi
---@param opts Terminal.PickerOpts
---@return boolean opened
local function open_kit(api, opts)
  local kit = opts.kit
  if not kit then
    local ok, mod = pcall(require, "lib.nvim.ui.kit.picker")
    if not ok then
      return false
    end
    kit = mod
  end
  local p
  local function refresh()
    if p and not p.is_closed() then
      p.set_items(M.items(api.list(opts.all)))
    end
  end
  local opened, handle = pcall(kit.open, {
    title = "Terminals",
    items = M.items(api.list(opts.all)),
    key = function(item)
      return item.handle.id
    end,
    text = function(item)
      return item.text
    end,
    format = M.format,
    preview = function(item, surface)
      surface:set_lines(M.preview_lines(item.handle))
    end,
    on_submit = function(_, _, item)
      if item then
        api.open({ name = item.handle.name })
      end
    end,
    keys = {
      [M.KEYS.close] = function(handle)
        local item = handle.current()
        if item then
          api.close({ name = item.handle.name })
          refresh()
        end
      end,
      [M.KEYS.send] = function(handle)
        local item = handle.current()
        if item then
          handle.close()
          send_line(api, item.handle, opts)
        end
      end,
    },
  })
  p = opened and handle or nil
  return p ~= nil
end

---@internal
---@param api Terminal.PickerApi
---@param opts Terminal.PickerOpts
local function open_select(api, opts)
  local ask = opts.select or vim.ui.select
  local items = M.items(api.list(opts.all))
  ask(items, {
    prompt = "Terminal",
    format_item = function(item)
      return item.text
    end,
  }, function(item)
    if not item then
      return
    end
    local actions = { "open", "send a line", "close" }
    ask(actions, { prompt = item.handle.name }, function(action)
      if action == "open" then
        api.open({ name = item.handle.name })
      elseif action == "close" then
        api.close({ name = item.handle.name })
      elseif action == "send a line" then
        send_line(api, item.handle, opts)
      end
    end)
  end)
end

--- Open the list. Returns false when there is no terminal to list.
---@param api Terminal.PickerApi
---@param opts? Terminal.PickerOpts
---@return boolean listed
function M.open(api, opts)
  opts = opts or {}
  if #M.items(api.list(opts.all)) == 0 then
    return false
  end
  if opts.engine == "select" or not open_kit(api, opts) then
    open_select(api, opts)
  end
  return true
end

return M
