---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/picker_spec.lua -- terminal.picker (rows, preview, kit and select paths with doubles) and
-- terminal.summary() (what a statusline reads, against the real facade).

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal.picker (rows and actions against a fake facade)", function()
  local picker = require("terminal.picker")

  ---@param name string
  ---@param extra? table
  local function handle(name, extra)
    return vim.tbl_extend("force", {
      id = "root::" .. name,
      name = name,
      root = "root",
      backend = "native",
      layout = "split",
    }, extra or {})
  end

  ---@param handles table[]
  ---@param calls table[]
  local function fake(handles, calls)
    return {
      list = function()
        return handles
      end,
      open = function(target)
        calls[#calls + 1] = { "open", target.name }
        return { name = target.name }
      end,
      close = function(target)
        calls[#calls + 1] = { "close", target.name }
        for i, h in ipairs(handles) do
          if h.name == target.name then
            table.remove(handles, i)
            break
          end
        end
        return true
      end,
      send = function(text, opts)
        calls[#calls + 1] = { "send", text, opts.name, opts.newline }
        return true
      end,
    }
  end

  it(
    "items: one row per terminal, a removed one is left out, the text carries name and state",
    function()
      local items = picker.items({
        handle("main"),
        handle("gone", { disposed = true }),
        handle("job", { exited = true, exit_code = 2 }),
      })
      assert.equals(2, #items)
      assert.equals("main split native", items[1].text)
      assert.equals("job split exited 2", items[2].text)
    end
  )

  it("format: the name first, an exited terminal muted", function()
    local live = picker.format(picker.items({ handle("main") })[1])
    local dead = picker.format(picker.items({ handle("job", { exited = true }) })[1])
    assert.equals("main", live[1][1])
    assert.equals("Title", live[1][2])
    assert.equals("Comment", dead[1][2])
  end)

  it("preview_lines: the last lines of a native buffer, trailing blanks cut", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}
    for i = 1, picker.PREVIEW_LINES + 10 do
      lines[i] = "line " .. i
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local got = picker.preview_lines(handle("main", { bufnr = buf }))
    assert.equals(picker.PREVIEW_LINES, #got)
    assert.equals("line " .. (picker.PREVIEW_LINES + 10), got[#got])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("preview_lines: output above a tall blank padding is still found", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = { "one", "two", "three" }
    for _ = 1, 500 do
      lines[#lines + 1] = ""
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    assert.same({ "one", "two", "three" }, picker.preview_lines(handle("main", { bufnr = buf })))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("preview_lines: an empty terminal previews nothing", function()
    local buf = vim.api.nvim_create_buf(false, true)
    assert.same({}, picker.preview_lines(handle("main", { bufnr = buf })))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("preview_lines: a pane has no buffer and says so without asking the multiplexer", function()
    local got = picker.preview_lines(handle("remote", { backend = "tmux", pane = "%3" }))
    assert.equals("tmux pane %3", got[1])
    assert.truthy(got[2]:find("no preview", 1, true))
  end)

  it("open: nothing to list is false and opens nothing", function()
    local calls = {}
    local opened = false
    local ok = picker.open(fake({}, calls), {
      kit = {
        open = function()
          opened = true
        end,
      },
    })
    assert.is_false(ok)
    assert.is_false(opened)
  end)

  it("kit: <CR> opens the terminal, <C-x> closes it and refreshes, <C-s> sends a line", function()
    local calls = {}
    local handles = { handle("a"), handle("b") }
    local api = fake(handles, calls)
    local opts, refreshed, closed
    local current = 1
    local p = {
      is_closed = function()
        return false
      end,
      current = function()
        return picker.items(handles)[current]
      end,
      set_items = function(items)
        refreshed = items
      end,
      close = function()
        closed = true
      end,
    }
    local kit = {
      open = function(o)
        opts = o
        return p
      end,
    }
    local sent
    assert.is_true(picker.open(api, {
      kit = kit,
      input = function(o, on_confirm)
        sent = o.prompt
        on_confirm("make test")
      end,
    }))
    assert.equals(2, #opts.items)
    assert.equals("root::a", opts.key(opts.items[1]))

    opts.on_submit(1, "a", opts.items[2])
    assert.same({ "open", "b" }, calls[1])

    opts.keys[picker.KEYS.close](p)
    assert.same({ "close", "a" }, calls[2])
    assert.equals(1, #refreshed, "the list is rebuilt without the closed terminal")
    assert.equals("b", refreshed[1].handle.name)

    current = 1 -- now "b"
    opts.keys[picker.KEYS.send](p)
    assert.is_true(closed, "the picker closes before the prompt for the line")
    assert.truthy(sent:find("b", 1, true))
    assert.same({ "send", "make test", "b", true }, calls[3])
  end)

  it("kit: a kit that raises while opening falls back to vim.ui.select", function()
    local calls = {}
    local asked = 0
    local ok = picker.open(fake({ handle("a") }, calls), {
      kit = {
        open = function()
          error("no UI")
        end,
      },
      select = function()
        asked = asked + 1
      end,
    })
    assert.is_true(ok)
    assert.equals(1, asked)
  end)

  it("kit: a preview failure does not matter here, the surface receives the lines", function()
    local calls = {}
    local opts
    picker.open(fake({ handle("a") }, calls), {
      kit = {
        open = function(o)
          opts = o
          return {}
        end,
      },
    })
    local got
    opts.preview(opts.items[1], {
      set_lines = function(_, lines)
        got = lines
      end,
    })
    assert.equals("native pane ?", got[1])
  end)

  it(
    "select: a kit that does not open falls back to vim.ui.select, terminal then action",
    function()
      local calls = {}
      local asked = {}
      local ok = picker.open(fake({ handle("a"), handle("b") }, calls), {
        kit = {
          open = function()
            return nil
          end,
        },
        select = function(items, o, on_choice)
          asked[#asked + 1] = o.prompt
          if #asked == 1 then
            assert.equals(2, #items)
            assert.equals("a split native", o.format_item(items[1]))
            on_choice(items[2])
          else
            assert.same({ "open", "send a line", "close" }, items)
            on_choice("close")
          end
        end,
      })
      assert.is_true(ok)
      assert.same({ "Terminal", "b" }, asked)
      assert.same({ { "close", "b" } }, calls)
    end
  )

  it("select: engine = select never touches the kit, cancelling does nothing", function()
    local calls = {}
    local touched = false
    picker.open(fake({ handle("a") }, calls), {
      engine = "select",
      kit = {
        open = function()
          touched = true
        end,
      },
      select = function(_, _, on_choice)
        on_choice(nil)
      end,
    })
    assert.is_false(touched)
    assert.same({}, calls)
  end)

  it("select: sending asks for the line, an empty answer sends nothing", function()
    for _, case in ipairs({ { answer = "ls", sent = 1 }, { answer = "", sent = 0 } }) do
      local calls = {}
      picker.open(fake({ handle("a") }, calls), {
        engine = "select",
        select = function(items, _, on_choice)
          if items[1] == "open" then
            on_choice("send a line")
          else
            on_choice(items[1])
          end
        end,
        input = function(_, on_confirm)
          on_confirm(case.answer)
        end,
      })
      assert.equals(case.sent, #calls)
      if case.sent == 1 then
        assert.same({ "send", "ls", "a", true }, calls[1])
      end
    end
  end)
end)

describe("terminal.summary (the statusline's data, real facade)", function()
  local terminal
  local original_notify = vim.notify

  local function boot()
    for _, mod in ipairs({ "terminal", "terminal.config", "terminal.backends.native" }) do
      package.loaded[mod] = nil
    end
    terminal = require("terminal")
    return terminal
  end

  before_each(function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
  end)

  after_each(function()
    if terminal then
      for _, h in ipairs(terminal.list(true)) do
        jobs.settle()
        terminal.close({ name = h.name })
      end
    end
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = original_notify
  end)

  it("before setup there is nothing to count and nothing is started", function()
    boot()
    assert.same({ count = 0, visible = 0 }, terminal.summary())
    assert.is_false(terminal.status().ready)
  end)

  it("counts the project's live terminals, the shown ones and names the current one", function()
    boot().setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    })
    assert.truthy(terminal.open({ name = "alpha", layout = "split" }))
    assert.truthy(terminal.open({ name = "beta", layout = "split" }))
    terminal.hide({ name = "beta" })
    local s = terminal.summary()
    assert.equals(2, s.count)
    assert.equals(1, s.visible)
    assert.equals("alpha", s.current)

    local bufnr = terminal.list()[1].bufnr
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(win) ~= bufnr then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
    assert.is_nil(terminal.summary().current)
    assert.equals(1, terminal.summary().visible, "leaving the window hides nothing")
  end)
end)
