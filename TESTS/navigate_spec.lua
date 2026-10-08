---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/navigate_spec.lua -- window navigation with hand-off at Neovim's edge.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local core = require("terminal.core.navigate")
local handoff = require("terminal.navigate.handoff")

describe("terminal.core.navigate", function()
  it("knows exactly the four directions", function()
    for _, d in ipairs({ "h", "j", "k", "l" }) do
      assert.is_true(core.valid(d))
    end
    for _, bad in ipairs({ "x", "H", "", "hh", 1, nil }) do
      assert.is_false(core.valid(bad))
    end
  end)

  it("outcome: moved, edge, and float never hands off", function()
    assert.equals("moved", core.outcome(false, 1, 2))
    assert.equals("edge", core.outcome(false, 1, 1))
    assert.equals("float", core.outcome(true, 1, 1))
    assert.equals("float", core.outcome(true, 1, 2))
  end)
end)

describe("terminal.navigate.handoff", function()
  it("builds the commands", function()
    assert.same(
      { "wezterm", "cli", "activate-pane-direction", "Left" },
      handoff.all.wezterm.argv("h")
    )
    assert.same(
      { "wezterm", "cli", "activate-pane-direction", "Down" },
      handoff.all.wezterm.argv("j")
    )
    assert.same({
      "tmux",
      "if-shell",
      "-F",
      "#{pane_at_top}",
      "",
      "select-pane -U",
    }, handoff.all.tmux.argv("k"))
    assert.same({
      "tmux",
      "if-shell",
      "-F",
      "#{pane_at_right}",
      "",
      "select-pane -R",
    }, handoff.all.tmux.argv("l"))
  end)

  it("tmux: every direction is guarded by the matching pane_at_* edge test", function()
    local edge = { h = "left", j = "bottom", k = "top", l = "right" }
    local flag = { h = "-L", j = "-D", k = "-U", l = "-R" }
    for dir, side in pairs(edge) do
      local argv = handoff.all.tmux.argv(dir)
      -- tmux wraps `select-pane -L` around at the window's edge; the test keeps it a no-op there
      assert.equals("if-shell", argv[2])
      assert.equals("#{pane_at_" .. side .. "}", argv[4])
      assert.equals("", argv[5], "nothing happens at the edge")
      assert.equals("select-pane " .. flag[dir], argv[6])
    end
  end)

  local function names(list)
    return vim.tbl_map(function(h)
      return h.name
    end, list)
  end

  it("auto: what the environment has, the innermost first", function()
    assert.same({}, (handoff.choose("auto", {})))
    assert.same({ "wezterm" }, names((handoff.choose("auto", { WEZTERM_PANE = "1" }))))
    assert.same({ "tmux" }, names((handoff.choose("auto", { TMUX = "x" }))))
    assert.same(
      { "tmux", "wezterm" },
      names((handoff.choose("auto", { TMUX = "x", WEZTERM_PANE = "1" })))
    )
  end)

  it("false means never; an unknown or unusable name is reported", function()
    assert.same({}, (handoff.choose(false, { WEZTERM_PANE = "1" })))
    local chosen, notes = handoff.choose({ "nope" }, {})
    assert.same({}, chosen)
    assert.truthy(notes[1]:find("does not exist", 1, true))
    chosen, notes = handoff.choose("wezterm", {})
    assert.same({}, chosen)
    assert.truthy(notes[1]:find("not usable", 1, true))
  end)
end)

describe("terminal.navigate.go", function()
  local navigate, calls

  local function cfg(handoff_option)
    return { navigate = { handoff = handoff_option } }
  end

  before_each(function()
    package.loaded["terminal.navigate"] = nil
    navigate = require("terminal.navigate")
    calls = {}
    vim.cmd("silent! only")
    vim.cmd("enew")
  end)

  after_each(function()
    vim.cmd("silent! only")
  end)

  local function setup(option, env)
    navigate.setup(cfg(option), env, function(argv)
      calls[#calls + 1] = argv
    end)
  end

  it("a single window is at every edge: hands off in the right direction", function()
    setup("auto", { WEZTERM_PANE = "1" })
    assert.equals("edge", navigate.go("h"))
    assert.same({ "wezterm", "cli", "activate-pane-direction", "Left" }, calls[1])
    assert.equals("edge", navigate.go("j"))
    assert.same({ "wezterm", "cli", "activate-pane-direction", "Down" }, calls[2])
  end)

  it("moves inside Neovim first and hands off only once the edge is reached", function()
    setup("auto", { WEZTERM_PANE = "1" })
    vim.cmd("vsplit") -- cursor is in the left window now (the new one)
    local left = vim.api.nvim_get_current_win()
    vim.cmd("wincmd l")
    local right = vim.api.nvim_get_current_win()
    assert.not_equals(left, right)

    assert.equals("moved", navigate.go("h"))
    assert.equals(left, vim.api.nvim_get_current_win())
    assert.same({}, calls, "moving inside Neovim does not hand off")

    assert.equals("edge", navigate.go("h"))
    assert.equals(1, #calls)
  end)

  it("count 0 (no count typed) and nil both mean one window; junk raises", function()
    setup("auto", { WEZTERM_PANE = "1" })
    vim.cmd("vsplit")
    vim.cmd("vsplit")
    vim.cmd("wincmd b")
    local start = vim.api.nvim_get_current_win()
    assert.equals("moved", navigate.go("h", 0))
    local one_left = vim.api.nvim_get_current_win()
    assert.not_equals(start, one_left)
    assert.not_equals(vim.api.nvim_list_wins()[1], one_left)
    assert.equals("moved", navigate.go("l"))
    assert.equals(start, vim.api.nvim_get_current_win())
    for _, bad in ipairs({ "2", -1, 0 / 0, math.huge, {} }) do
      local ok, err = pcall(navigate.go, "h", bad)
      assert.is_false(ok, vim.inspect(bad))
      assert.truthy(tostring(err):find("count must be a number from 0 up", 1, true))
    end
    -- a huge but finite count is capped, not an error: Neovim stops at the last window
    assert.equals("moved", navigate.go("h", 1e30))
  end)

  it("a count moves that many windows", function()
    setup("auto", { WEZTERM_PANE = "1" })
    vim.cmd("vsplit")
    vim.cmd("vsplit")
    vim.cmd("wincmd b") -- the last (rightmost) window
    local start = vim.api.nvim_get_current_win()
    assert.equals("moved", navigate.go("h", 2))
    assert.not_equals(start, vim.api.nvim_get_current_win())
    -- two windows to the left of the rightmost one is the leftmost; one step would stop in the middle
    assert.equals(vim.api.nvim_list_wins()[1], vim.api.nvim_get_current_win())
    assert.same({}, calls)
  end)

  it(
    "a held key at the edge runs one process at a time; the latest press waits its turn",
    function()
      local started, finish, seen_opts = {}, nil, nil
      local original = vim.system
      vim.system = function(argv, opts, on_exit)
        started[#started + 1] = argv
        seen_opts = opts
        finish = on_exit
        return {}
      end
      navigate.setup(cfg("auto"), { WEZTERM_PANE = "1" }) -- the default (detached) runner
      for _ = 1, 6 do
        navigate.go("h")
      end
      navigate.go("j")
      assert.equals(1, #started, "the key repeat does not start a process per press")
      assert.equals(2000, seen_opts.timeout, "a hung multiplexer is reaped")
      finish()
      assert.is_true(vim.wait(500, function()
        return #started == 2
      end))
      assert.equals("Down", started[2][4], "the waiting press is the latest one")
      finish()
      vim.wait(50)
      assert.equals(2, #started)
      vim.system = original
    end
  )

  it("a floating window never hands off", function()
    setup("auto", { WEZTERM_PANE = "1" })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 3,
      style = "minimal",
    })
    assert.equals("float", navigate.go("h"))
    assert.same({}, calls)
  end)

  it("hands off to nothing with handoff = false", function()
    setup(false, { WEZTERM_PANE = "1" })
    assert.equals("edge", navigate.go("h"))
    assert.same({}, calls)
    assert.same({}, navigate.active())
  end)

  it("asks only the innermost multiplexer", function()
    setup("auto", { TMUX = "x", WEZTERM_PANE = "1" })
    navigate.go("l")
    assert.equals(1, #calls)
    assert.same({
      "tmux",
      "if-shell",
      "-F",
      "#{pane_at_right}",
      "",
      "select-pane -R",
    }, calls[1])
  end)

  it("hands off nothing outside any multiplexer", function()
    setup("auto", {})
    assert.equals("edge", navigate.go("h"))
    assert.same({}, calls)
  end)

  it("refuses an invalid direction", function()
    setup("auto", {})
    assert.has_error(function()
      navigate.go("x")
    end)
  end)
end)

describe("terminal navigation keymaps", function()
  local terminal

  local function wipe()
    for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
      pcall(vim.keymap.del, "t", lhs)
      pcall(vim.keymap.del, "n", lhs)
    end
    for _, lhs in ipairs({ "<A-h>", "<A-x>", "<A-y>" }) do
      pcall(vim.keymap.del, "n", lhs)
      pcall(vim.keymap.del, "t", lhs)
    end
  end

  before_each(function()
    wipe()
    for _, mod in ipairs({ "terminal", "terminal.config", "terminal.bindings", "terminal.navigate" }) do
      package.loaded[mod] = nil
    end
    terminal = require("terminal")
    vim.cmd("silent! only")
  end)

  after_each(function()
    wipe()
    vim.cmd("silent! only")
  end)

  it("nav_* are unbound by default", function()
    terminal.setup({ commands = false, status = { enable = false } })
    assert.same({}, vim.fn.maparg("<C-h>", "n", false, true))
  end)

  it("nav_left binds in normal mode and navigates (count included)", function()
    terminal.setup({
      commands = false,
      status = { enable = false },
      navigate = { handoff = false },
      keymaps = { nav_left = "<C-h>" },
    })
    local m = vim.fn.maparg("<C-h>", "n", false, true)
    assert.is_not_nil(m.callback)
    vim.cmd("vsplit")
    vim.cmd("wincmd l")
    local right = vim.api.nvim_get_current_win()
    m.callback()
    assert.not_equals(right, vim.api.nvim_get_current_win())
  end)

  it("a second setup unbinds the keys the first one bound", function()
    local base = { commands = false, status = { enable = false }, navigate = { handoff = false } }
    terminal.setup(
      vim.tbl_extend("force", base, { keymaps = { toggle = "<A-x>", nav_left = "<C-h>" } })
    )
    assert.is_not_nil(vim.fn.maparg("<A-x>", "n", false, true).callback)
    assert.is_not_nil(vim.fn.maparg("<C-h>", "n", false, true).callback)
    terminal.setup(
      vim.tbl_extend("force", base, { keymaps = { toggle = "<A-y>", nav_left = false } })
    )
    assert.same({}, vim.fn.maparg("<A-x>", "n", false, true), "a moved key is gone")
    assert.same({}, vim.fn.maparg("<A-x>", "t", false, true))
    assert.same({}, vim.fn.maparg("<C-h>", "n", false, true), "a dropped key is gone")
    assert.is_not_nil(vim.fn.maparg("<A-y>", "n", false, true).callback)
  end)

  it("a map the user put on a key afterwards survives a second setup", function()
    local base = { commands = false, status = { enable = false }, navigate = { handoff = false } }
    terminal.setup(vim.tbl_extend("force", base, { keymaps = { toggle = "<A-x>" } }))
    vim.keymap.set("n", "<A-x>", function() end, { desc = "mine" })
    terminal.setup(vim.tbl_extend("force", base, { keymaps = { toggle = "<A-y>" } }))
    assert.equals("mine", vim.fn.maparg("<A-x>", "n", false, true).desc)
  end)

  it("the terminal-mode window keys call the navigation instead of a raw <C-w>", function()
    terminal.setup({ commands = false, status = { enable = false } })
    local m = vim.fn.maparg("<C-h>", "t", false, true)
    assert.is_not_nil(m.callback, "a function, not the old <C-\\><C-w>h string")
  end)
end)
