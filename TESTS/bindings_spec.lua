---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/bindings_spec.lua -- keymaps, autocommands and the :Terminal command.

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

--- Neovim reports `<A-h>` as `<M-h>` and `<C-n>` as `<C-N>`; compare keys in that one form.
---@param key string
---@return string
local function norm(key)
  return vim.fn.keytrans(vim.api.nvim_replace_termcodes(key, true, true, true))
end

---@param mode string
---@param lhs string
---@return table
local function map(mode, lhs)
  return vim.fn.maparg(lhs, mode, false, true)
end

--- The `lhs` of a mapping in normalised form ("" when there is none).
---@param mode string
---@param lhs string
---@return string
local function bound(mode, lhs)
  local m = map(mode, lhs)
  return m.lhs and norm(m.lhs) or ""
end

describe("terminal bindings", function()
  local terminal

  local function reload()
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.backends.native",
      "terminal.bindings",
      "terminal.bindings.keymaps",
      "terminal.bindings.autocmds",
      "terminal.bindings.usrcmds",
    }) do
      package.loaded[mod] = nil
    end
    terminal = require("terminal")
  end

  local function wipe_maps()
    for _, m in ipairs({
      { "n", "<A-h>" },
      { "t", "<A-h>" },
      { "t", "<Esc>" },
      { "t", "<C-c>" },
      { "t", "<A-l>" },
    }) do
      pcall(vim.keymap.del, m[1], m[2])
    end
    for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
      pcall(vim.keymap.del, "t", lhs)
    end
    pcall(vim.api.nvim_del_user_command, "Terminal")
  end

  before_each(function()
    wipe_maps()
    reload()
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
    wipe_maps()
  end)

  describe("keymaps", function()
    it("binds the toggle in normal and terminal mode, and the terminal-mode set", function()
      terminal.setup({ shell = jobs.sleeper() })
      assert.equals(norm("<A-h>"), bound("n", "<A-h>"))
      assert.equals(norm("<A-h>"), bound("t", "<A-h>"))
      assert.equals(norm("<Esc>"), bound("t", "<Esc>"))
      assert.equals(norm("<C-c>"), bound("t", "<C-c>"))
      assert.equals(norm("<A-l>"), bound("t", "<A-l>"))
      for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
        assert.equals(norm(lhs), bound("t", lhs))
      end
    end)

    it("the leave-terminal-mode keys send <C-\\><C-n>", function()
      terminal.setup({ shell = jobs.sleeper() })
      assert.equals(norm("<C-\\><C-n>"), norm(map("t", "<Esc>").rhs))
      assert.equals(norm("<C-\\><C-n>"), norm(map("t", "<C-c>").rhs))
    end)

    it("moves an action with a string and drops one with false", function()
      terminal.setup({
        shell = jobs.sleeper(),
        keymaps = { toggle = "<A-x>", clear = false },
      })
      assert.equals(norm("<A-x>"), bound("n", "<A-x>"))
      assert.same({}, map("n", "<A-h>"))
      assert.same({}, map("t", "<A-l>"))
    end)

    it("binds nothing with preset = false", function()
      terminal.setup({ shell = jobs.sleeper(), keymaps = { preset = false } })
      assert.same({}, map("n", "<A-h>"))
      assert.same({}, map("t", "<Esc>"))
    end)

    it("the toggle mapping toggles the terminal", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      map("n", "<A-h>").callback()
      assert.equals(1, #terminal.list())
      local h = terminal.list()[1]
      assert.equals(1, #vim.fn.win_findbuf(h.bufnr))
      jobs.settle()
      map("n", "<A-h>").callback()
      assert.equals(0, #vim.fn.win_findbuf(h.bufnr))
    end)
  end)

  describe(":Terminal", function()
    it("exists after setup and not with commands = false", function()
      terminal.setup({ shell = jobs.sleeper(), commands = false })
      assert.equals(0, vim.fn.exists(":Terminal"))
      reload()
      terminal.setup({ shell = jobs.sleeper() })
      assert.equals(2, vim.fn.exists(":Terminal"))
    end)

    it("completes the subcommands", function()
      terminal.setup({ shell = jobs.sleeper() })
      local items = vim.fn.getcompletion("Terminal ", "cmdline")
      for _, want in ipairs({ "toggle", "open", "hide", "close", "list", "send", "run" }) do
        assert.is_true(vim.tbl_contains(items, want), want)
      end
    end)

    it("completes the layouts for --layout=", function()
      terminal.setup({ shell = jobs.sleeper() })
      local items = vim.fn.getcompletion("Terminal open --layout=", "cmdline")
      assert.is_true(vim.tbl_contains(items, "--layout=vsplit"))
    end)

    it("open and close work through the command", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      vim.cmd("Terminal open build")
      assert.same(
        { "build" },
        vim.tbl_map(function(h)
          return h.name
        end, terminal.list())
      )
      vim.cmd("Terminal close build")
      assert.equals(0, #terminal.list())
    end)

    it("the bare command toggles the default terminal", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      vim.cmd("Terminal")
      assert.equals("main", terminal.list()[1].name)
    end)

    it("run --direct starts the arguments as the job", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      local argv = jobs.exit_with(0)
      vim.cmd("Terminal run --direct --name=job " .. table.concat(argv, " "))
      local h = terminal.list()[1]
      assert.equals("job", h.name)
      assert.same(argv[1], vim.fn.fnamemodify(argv[1], ":t"))
    end)

    it("send line types the current line without executing it", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      vim.cmd("enew")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo hello" })
      local sent = jobs.record_sends(function()
        vim.cmd("Terminal send line")
      end)
      assert.equals("run", terminal.list()[1].name)
      assert.equals("echo hello", sent[1].text, "typed, not executed: no line ending")
    end)
  end)

  describe("autocommands", function()
    it("normalises terminal window options on TermOpen", function()
      terminal.setup({
        shell = jobs.sleeper(),
        layout = "split",
        start_insert = false,
        window_options = { signcolumn = "no", number = false },
      })
      vim.wo.number = true
      local h = terminal.open()
      local win = vim.fn.win_findbuf(h.bufnr)[1]
      assert.is_false(vim.wo[win].number)
      assert.equals("no", vim.wo[win].signcolumn)
    end)

    it("creates no TermOpen handler with window_options.enable = false", function()
      terminal.setup({ shell = jobs.sleeper(), window_options = { enable = false } })
      assert.equals(
        0,
        #vim.api.nvim_get_autocmds({ group = "terminal.window_options", event = "TermOpen" })
      )
    end)

    it("calling setup twice does not double the handlers", function()
      terminal.setup({ shell = jobs.sleeper() })
      terminal.setup({ shell = jobs.sleeper() })
      assert.equals(
        1,
        #vim.api.nvim_get_autocmds({ group = "terminal.window_options", event = "TermOpen" })
      )
    end)
  end)
end)
