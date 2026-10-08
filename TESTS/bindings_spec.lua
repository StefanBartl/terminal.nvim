---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/bindings_spec.lua -- keymaps, autocommands and the :Terminal command.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

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
    pcall(vim.api.nvim_del_augroup_by_name, "terminal.usrcmds")
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
      for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>" }) do
        assert.equals(norm(lhs), bound("t", lhs))
      end
    end)

    it("leaves <C-l> and <A-l> alone by default: the shell clears the screen itself", function()
      terminal.setup({ shell = jobs.sleeper() })
      assert.same({}, map("t", "<C-l>"))
      assert.same({}, map("t", "<A-l>"))
    end)

    it("binds clear and window_right when asked to", function()
      terminal.setup({
        shell = jobs.sleeper(),
        keymaps = { clear = "<A-l>", window_right = "<C-l>" },
      })
      assert.equals(norm("<A-l>"), bound("t", "<A-l>"))
      assert.equals(norm("<C-l>"), bound("t", "<C-l>"))
    end)

    it("clear types cls for cmd.exe and PowerShell, clear for every other shell", function()
      local chansend = vim.fn.chansend
      local typed
      -- Test double: capture what the clear key types into the job; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.chansend = function(_, data)
        typed = data
        return 1
      end
      vim.b.terminal_job_id = 1
      local ok, err = pcall(function()
        for shell, want in pairs({
          ["bash"] = "clear",
          ["C:\\Program Files\\Git\\bin\\bash.exe"] = "clear",
          ["/usr/bin/fish"] = "clear",
          ["C:\\Windows\\System32\\cmd.exe"] = "cls",
          ["pwsh"] = "cls",
          ["powershell.exe"] = "cls",
        }) do
          terminal.setup({ shell = shell, keymaps = { clear = "<A-l>" } })
          typed = nil
          map("t", "<A-l>").callback()
          assert.same({ want, "" }, typed, shell)
        end
        -- an argv shell: its first word decides
        terminal.setup({ shell = { "pwsh", "-NoLogo" }, keymaps = { clear = "<A-l>" } })
        map("t", "<A-l>").callback()
        assert.same({ "cls", "" }, typed)
      end)
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.chansend = chansend
      vim.b.terminal_job_id = nil
      assert.is_true(ok, tostring(err))
    end)

    it("the leave-terminal-mode keys send <C-\\><C-n>", function()
      terminal.setup({ shell = jobs.sleeper() })
      assert.equals(norm("<C-\\><C-n>"), norm(map("t", "<Esc>").rhs))
      assert.equals(norm("<C-\\><C-n>"), norm(map("t", "<C-c>").rhs))
    end)

    it("moves an action with a string and drops one with false", function()
      terminal.setup({
        shell = jobs.sleeper(),
        keymaps = { toggle = "<A-x>", window_left = false },
      })
      assert.equals(norm("<A-x>"), bound("n", "<A-x>"))
      assert.same({}, map("n", "<A-h>"))
      assert.same({}, map("t", "<C-h>"))
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
    it("is still created when another part of the bindings fails", function()
      local original_notify = vim.notify
      -- Test double: swallow the notification of the expected failure; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function() end
      package.loaded["terminal.bindings.autocmds"] = {
        setup = function()
          error("boom")
        end,
      }
      terminal.setup({ shell = jobs.sleeper() })
      vim.wait(100)
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = original_notify
      package.loaded["terminal.bindings.autocmds"] = nil
      assert.equals(2, vim.fn.exists(":Terminal"))
    end)

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

    describe("completes terminal names from the registry at Tab time", function()
      before_each(function()
        terminal.setup({ shell = jobs.sleeper(), start_insert = false })
        terminal.open({ name = "build", focus = false })
        terminal.open({ name = "repl", focus = false })
      end)

      it("hide, close, pin and adopt offer only the terminals that are open", function()
        for _, verb in ipairs({ "hide", "close", "pin", "adopt" }) do
          local items = vim.fn.getcompletion("Terminal " .. verb .. " ", "cmdline")
          table.sort(items)
          assert.same({ "build", "repl" }, items, verb)
        end
        assert.same({ "build" }, vim.fn.getcompletion("Terminal close b", "cmdline"))
      end)

      it("toggle, open and send also offer the configured names and the counts", function()
        for _, line in ipairs({
          "Terminal toggle ",
          "Terminal open ",
          "Terminal send line ",
          "Terminal send selection ",
          "Terminal send file ",
        }) do
          local items = vim.fn.getcompletion(line, "cmdline")
          for _, want in ipairs({ "build", "repl", "main", "run", "1", "9" }) do
            assert.is_true(vim.tbl_contains(items, want), line .. want)
          end
          local seen = {}
          for _, item in ipairs(items) do
            assert.is_nil(seen[item], "offered twice: " .. item)
            seen[item] = true
          end
        end
      end)

      it("run --name= completes the same names", function()
        local items = vim.fn.getcompletion("Terminal run --name=", "cmdline")
        assert.is_true(vim.tbl_contains(items, "--name=build"), vim.inspect(items))
        assert.is_true(vim.tbl_contains(items, "--name=run"), vim.inspect(items))
      end)

      it(
        "a name that is not open is accepted: the command says there is no such terminal",
        function()
          vim.cmd("Terminal close ghost")
          assert.equals(2, #terminal.list())
        end
      )
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

    it("hide and close of an unknown terminal tell the user why (the API only answers)", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      local msgs = {}
      local original = vim.notify
      -- Test double: capture what would be shown to the user; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg)
        msgs[#msgs + 1] = msg
      end
      vim.cmd("Terminal hide ghost")
      vim.cmd("Terminal close ghost")
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = original
      assert.equals(2, #msgs, vim.inspect(msgs))
      for _, msg in ipairs(msgs) do
        assert.truthy(msg:find("[terminal]", 1, true), msg)
        assert.truthy(msg:find("no terminal 'ghost' in this project", 1, true), msg)
      end
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
      -- the exit code proves the arguments were run as the job's argv
      assert.is_true(jobs.wait(function()
        return h.exited == true
      end))
      assert.equals(0, h.exit_code)
    end)

    it("run keeps dashed words of the command after --", function()
      local opts, command = require("terminal.bindings.usrcmds").parse_run({
        "run",
        "--direct",
        "--name=job",
        "--",
        "git",
        "log",
        "--oneline",
        "--",
        "x",
      })
      assert.same({ direct = true, name = "job" }, opts)
      assert.same({ "git", "log", "--oneline", "--", "x" }, command)
      local _, plain = require("terminal.bindings.usrcmds").parse_run({ "run", "npm", "test" })
      assert.same({ "npm", "test" }, plain)
    end)

    it("send selection types the selected lines; several lines need --exec", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      vim.cmd("enew")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
      local notified
      local original = vim.notify
      -- Test double: capture what would be shown to the user; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg)
        notified = msg
      end
      local refused = jobs.record_sends(function()
        vim.cmd("2,3Terminal send selection")
      end)
      -- Restore the original.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = original
      assert.same({}, refused, "two lines without --exec must not be sent")
      assert.truthy(notified and notified:find("--exec", 1, true))

      local sent = jobs.record_sends(function()
        vim.cmd("2,3Terminal send selection --exec")
      end)
      assert.equals("two\nthree" .. (vim.fn.has("win32") == 1 and "\r" or "\n"), sent[1].text)

      local single = jobs.record_sends(function()
        vim.cmd("2Terminal send selection")
      end)
      assert.equals("two", single[1].text)
    end)

    describe("send selection follows the kind of Visual selection", function()
      local function eol()
        return vim.fn.has("win32") == 1 and "\r" or "\n"
      end

      --- Type `keys` the way a user does: through the typeahead, so that a command line really
      --- opens, is left and runs (`:` in Visual mode fills in `'<,'>` itself). The first key
      --- leaves whatever mode an earlier spec left pending (the `startinsert` of a terminal that
      --- was opened with `start_insert` on would turn the keys into text).
      ---@param keys string
      local function type_keys(keys)
        local termcodes = vim.api.nvim_replace_termcodes("<C-\\><C-n>" .. keys, true, false, true)
        vim.api.nvim_feedkeys(termcodes, "xt", false)
      end

      --- The text `send selection` typed into the terminal, for one run of `keys`.
      ---@param keys string
      ---@return string
      local function sent_by(keys)
        local sent = jobs.record_sends(function()
          type_keys(keys)
        end)
        -- a plain assert: one send per run is what the helper is built on, and a soft failure
        -- would only run on into an index error
        assert(#sent == 1, "expected one send, got " .. vim.inspect(sent))
        return sent[1].text
      end

      before_each(function()
        terminal.setup({ shell = jobs.sleeper(), start_insert = false })
        vim.cmd("enew")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo hello world", "ghijkl", "mnopqr" })
      end)

      it("characterwise: only the selected characters", function()
        assert.equals("hello", sent_by("gg0wviw:Terminal send selection<CR>"))
      end)

      it("characterwise over several lines: from the first character to the last", function()
        -- "hello world", then the "g" at the start of line 2
        local text = sent_by("gg0wvj0:Terminal send selection --exec<CR>")
        assert.equals("hello world\ng" .. eol(), text)
      end)

      it("blockwise: the block, one line per row", function()
        -- columns 2-3 of lines 1-2
        local text = sent_by("gg0l<C-v>jl:Terminal send selection --exec<CR>")
        assert.equals("ch\nhi" .. eol(), text)
      end)

      --- What a yank of the selection `keys` makes gives, as lines.
      ---@param keys string
      ---@return string[]
      local function yanked(keys)
        type_keys(keys .. '"zy')
        return vim.fn.getreg("z", 1, true)
      end

      --- The selection `keys` makes, sent and yanked: both as lines.
      ---@param keys string Ends with the Visual selection; the command or the yank follows it
      ---@return string[] sent
      ---@return string[] yanked
      local function sent_and_yanked(keys)
        local yank = yanked(keys)
        local text = sent_by(keys .. ":Terminal send selection --exec<CR>")
        -- --exec ends the text with the line ending of the platform
        return vim.split(text:sub(1, -#eol() - 1), "\n", { plain = true }), yank
      end

      it("blockwise with $: every row from the left edge to the end of THAT row", function()
        -- the cursor is past the end of the short line: a cut at that column loses "ld"
        local sent, yank = sent_and_yanked("gg0l<C-v>j$")
        assert.same({ "cho hello world", "hijkl" }, yank, "what a yank gives")
        assert.same(yank, sent)
      end)

      it("blockwise with $ in every direction the selection can grow", function()
        -- the row the cursor ends on is the SHORTER one in each case: a cut at its column would
        -- lose the end of the longer rows
        local long, short = "echo hello world", "ghijkl"
        local cases = {
          -- buffer, keys, rows
          { { long, short, "mnopqr" }, "gg0l<C-v>jj$", { "cho hello world", "hijkl", "nopqr" } },
          { { long, short }, "gg0l<C-v>$j", { "cho hello world", "hijkl" } }, -- $ first, then down
          -- upwards: it is the mark '< that sits past the end of its line
          { { short, long, "mnopqr" }, "G0l<C-v>kk$", { "hijkl", "cho hello world", "nopqr" } },
          { { short, long }, "G0l<C-v>$k", { "hijkl", "cho hello world" } },
        }
        for _, case in ipairs(cases) do
          vim.api.nvim_buf_set_lines(0, 0, -1, false, case[1])
          local sent, yank = sent_and_yanked(case[2])
          assert.same(case[3], yank, case[2] .. ": what a yank gives")
          assert.same(case[3], sent, case[2])
        end
      end)

      it("blockwise with $ keeps multibyte characters, wide ones and tabs whole", function()
        local cases = {
          -- two-byte letters: the left edge is the second one, and a cut at the byte column of the
          -- short row would split a letter of the long one
          {
            { "αβγδ ε ζ", "ηθικ" },
            "gg0l<C-v>j$",
            { "βγδ ε ζ", "θικ" },
          },
          -- three-byte, two-cell characters: the left edge is the first of them
          {
            { "ab日本語テキスト", "cd日本" },
            "gg0ll<C-v>j$",
            { "日本語テキスト", "日本" },
          },
          -- a tab starts the block
          {
            { "a\tb and more text", "cdefghijk" },
            "gg0l<C-v>j$",
            { "\tb and more text", "defghijk" },
          },
        }
        for _, case in ipairs(cases) do
          vim.api.nvim_buf_set_lines(0, 0, -1, false, case[1])
          local sent, yank = sent_and_yanked(case[2])
          assert.same(case[3], yank, vim.inspect(case[1]) .. ": what a yank gives")
          assert.same(case[3], sent, vim.inspect(case[1]))
        end
      end)

      it(
        "blockwise with $: a row that ends before the left edge has nothing in the block",
        function()
          vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo hello world", "mn", "ghijklmnopqrs" })
          -- left edge at column 8; a yank pads the short row with blanks, which nobody wants typed
          local sent = sent_and_yanked("gg07l<C-v>jj$")
          assert.same({ "llo world", "", "nopqrs" }, sent)
        end
      )

      it(
        "blockwise without $: a block that ends on an empty line is still the plain block",
        function()
          -- the mark of an empty line is column 1, as it is for any selection that ends there
          vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "ghijkl", "" })
          local sent, yank = sent_and_yanked("gg0l<C-v>jj")
          assert.same({ "ab", "gh", "" }, yank, "what a yank gives")
          assert.same(yank, sent)
        end
      )

      it("linewise: whole lines", function()
        local text = sent_by("ggVj:Terminal send selection --exec<CR>")
        assert.equals("echo hello world\nghijkl" .. eol(), text)
      end)

      it("a command-line modifier in front of the range changes nothing", function()
        assert.equals("hello", sent_by("gg0wviw:silent Terminal send selection<CR>"))
        assert.equals("hello", sent_by("gg0wviw:keepjumps Terminal send selection<CR>"))
      end)

      it("the range typed as * (Neovim's alias for '<,'>) is the selection too", function()
        assert.equals("hello", sent_by("gg0wviw<Esc>:*Terminal send selection<CR>"))
        assert.equals("hello", sent_by("gg0wviw<Esc>:silent *Terminal send selection<CR>"))
        assert.equals("hello", sent_by("gg0wviw<Esc>:'<,'>Terminal send selection<CR>"))
        -- a blockwise one as well
        assert.equals(
          "ch\nhi" .. eol(),
          sent_by("gg0l<C-v>jl<Esc>:*Terminal send selection --exec<CR>")
        )
      end)

      it("an offset behind the marks is a plain range: whole lines, not the selection", function()
        -- the marks still say "hello" on line 1, but the range is lines 1-2
        local plus = sent_by("gg0wviw<Esc>:'<,'>+1Terminal send selection --exec<CR>")
        assert.equals("echo hello world\nghijkl" .. eol(), plus)
        -- and lines 1-2 again when a selection over lines 1-3 loses its last line
        local minus = sent_by("gg0wvjj<Esc>:'<,'>-1Terminal send selection --exec<CR>")
        assert.equals("echo hello world\nghijkl" .. eol(), minus)
      end)

      it("a mapping that starts with ':' from Visual mode sends the selection", function()
        vim.keymap.set("x", "<F9>", ":Terminal send selection --exec<CR>")
        local ok, text = pcall(sent_by, "gg0wviw<F9>")
        vim.keymap.del("x", "<F9>")
        assert.is_true(ok, tostring(text))
        assert.equals("hello" .. eol(), text)
      end)

      it("a typed range is whole lines, also over the lines of an older selection", function()
        -- the marks and 'visualmode()' still describe the "hello" of line 1
        vim.cmd("normal! gg0wviw\27")
        local one = sent_by(":1Terminal send selection --exec<CR>")
        assert.equals("echo hello world" .. eol(), one, "line 1, typed by hand, is the line")
        -- a characterwise selection over lines 2-3, then exactly those lines as a plain range
        vim.cmd("normal! 2Gllvj$\27")
        local two = sent_by(":2,3Terminal send selection --exec<CR>")
        assert.equals("ghijkl\nmnopqr" .. eol(), two, "lines 2,3, typed by hand, are the lines")
      end)

      it("a plain range on other lines than the older selection is whole lines", function()
        vim.cmd("normal! gg0wviw\27") -- leaves charwise marks on line 1
        local text = sent_by(":2,3Terminal send selection --exec<CR>")
        assert.equals("ghijkl\nmnopqr" .. eol(), text)
      end)

      it("a call without a command line (Lua, <Cmd>) sends whole lines", function()
        vim.cmd("normal! gg0wviw\27") -- charwise marks on line 1, 'visualmode()' is "v"
        local sent = jobs.record_sends(function()
          vim.cmd("'<,'>Terminal send selection")
        end)
        assert.equals("echo hello world", sent[1].text)
      end)

      it("a cancelled command line is not remembered", function()
        type_keys("gg0wviw:<Esc>")
        local sent = jobs.record_sends(function()
          vim.cmd("'<,'>Terminal send selection")
        end)
        assert.equals("echo hello world", sent[1].text)
      end)

      it("a command line is read once: the next call from Lua is not that line", function()
        assert.equals("hello", sent_by("gg0wviw:Terminal send selection<CR>"))
        local sent = jobs.record_sends(function()
          vim.cmd("'<,'>Terminal send selection")
        end)
        assert.equals("echo hello world", sent[1].text)
      end)

      it("a line that ran another command does not reach a later call from Lua", function()
        type_keys("gg0wviw:normal! l<CR>") -- runs as `:'<,'>normal! l`, never asks for the marks
        vim.wait(50) -- the event-loop turn ends
        local sent = jobs.record_sends(function()
          vim.cmd("'<,'>Terminal send selection")
        end)
        assert.equals("echo hello world", sent[1].text)
      end)
    end)

    it("send file types the whole buffer with --exec", function()
      terminal.setup({ shell = jobs.sleeper(), start_insert = false })
      vim.cmd("enew")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b" })
      local sent = jobs.record_sends(function()
        vim.cmd("Terminal send file --exec")
      end)
      assert.equals("a\nb" .. (vim.fn.has("win32") == 1 and "\r" or "\n"), sent[1].text)
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
