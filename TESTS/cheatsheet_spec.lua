---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/cheatsheet_spec.lua -- terminal.cheatsheet: which sheet a shell gets, how a sheet is cut into
-- sections and searched, how sheets are found and loaded, the built-in sheets themselves, the
-- window (pages, search, switching, typing a line) and the facade on a real terminal.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal.cheatsheet.detect", function()
  local detect = require("terminal.cheatsheet.detect")

  it("names the program of a shell command", function()
    assert.equals("bash", detect.program("C:\\Program Files\\Git\\usr\\bin\\bash.EXE"))
    assert.equals("pwsh", detect.program("/usr/bin/pwsh"))
    assert.equals("", detect.program(nil))
  end)

  it("maps shells to their sheet, unknown programs to common", function()
    assert.equals("powershell", detect.detect("pwsh.exe"))
    assert.equals(
      "powershell",
      detect.detect("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
    )
    assert.equals("bash", detect.detect("/bin/sh"))
    assert.equals("bash", detect.detect("dash"))
    assert.equals("zsh", detect.detect("/usr/bin/zsh"))
    assert.equals("fish", detect.detect("fish"))
    assert.equals("cmd", detect.detect("cmd.exe"))
    assert.equals("common", detect.detect("wsl.exe"))
    assert.equals("common", detect.detect("nu"))
    assert.equals("common", detect.detect(nil))
  end)

  it("tries the related sheet, then common", function()
    assert.same({ "zsh", "bash", "common" }, detect.candidates("zsh"))
    assert.same({ "bash", "common" }, detect.candidates("bash"))
    assert.same({ "common" }, detect.candidates("common"))
  end)

  describe("key_for", function()
    it("an explicit key wins, in lower case", function()
      assert.equals("powershell", detect.key_for({ explicit = "PowerShell", shell = "bash" }))
    end)

    it("a multiplexer pane runs an unknown shell: common", function()
      assert.equals("common", detect.key_for({ backend = "tmux", cmd = "bash", shell = "bash" }))
    end)

    it("a native terminal is judged by its command, else by the configured shell", function()
      assert.equals(
        "powershell",
        detect.key_for({ backend = "native", cmd = { "pwsh", "-NoLogo" }, shell = "bash" })
      )
      assert.equals(
        "bash",
        detect.key_for({ backend = "native", cmd = '"C:/Git/bin/bash.exe" -l', shell = "pwsh" })
      )
      assert.equals("powershell", detect.key_for({ backend = "native", shell = "pwsh.exe" }))
    end)

    it("no terminal at all: the configured shell", function()
      assert.equals("bash", detect.key_for({ shell = "/bin/bash" }))
    end)
  end)
end)

describe("terminal.cheatsheet.parse", function()
  local parse = require("terminal.cheatsheet.parse")

  it("cuts a sheet at its ## headings and keeps the title", function()
    local sheet = parse.parse("# bash\n\n## One\na\nb\n\n## Two\nc\n")
    assert.equals("bash", sheet.title)
    assert.equals(2, #sheet.sections)
    assert.equals("One", sheet.sections[1].title)
    assert.same({ "a", "b" }, sheet.sections[1].lines)
    assert.same({ "c" }, sheet.sections[2].lines)
  end)

  it("a ## inside a fenced code block is code", function()
    local sheet = parse.parse("## A\n```\n## not a heading\n```\n## B\nx\n")
    assert.equals(2, #sheet.sections)
    assert.equals("## not a heading", sheet.sections[1].lines[2])
  end)

  it("text before the first section is a section of its own, nothing is lost", function()
    local sheet = parse.parse("# T\nintro line\n\n## S\nx\n")
    assert.equals(2, #sheet.sections)
    assert.equals("About", sheet.sections[1].title)
    assert.same({ "intro line" }, sheet.sections[1].lines)
  end)

  it("a text without any heading has no sections", function()
    assert.equals(0, #parse.parse("").sections)
  end)

  it("handles Windows line endings", function()
    local sheet = parse.parse("## A\r\nx\r\n")
    assert.same({ "x" }, sheet.sections[1].lines)
  end)

  describe("search", function()
    local sections = {
      { title = "A", lines = { "Alpha beta", "gamma" } },
      { title = "B", lines = { "delta ALPHA" } },
    }

    it("finds every line across sections, any case, in reading order", function()
      local found = parse.search(sections, "alpha")
      assert.equals(2, #found)
      assert.same({ section = 1, line = 1, col = 0 }, found[1])
      assert.same({ section = 2, line = 1, col = 6 }, found[2])
    end)

    it("is plain text, not a pattern", function()
      assert.equals(0, #parse.search({ { title = "A", lines = { "a.b" } } }, "a%.b"))
      assert.equals(1, #parse.search({ { title = "A", lines = { "a.b" } } }, "a.b"))
    end)

    it("an empty query finds nothing", function()
      assert.equals(0, #parse.search(sections, ""))
    end)
  end)

  describe("command_of", function()
    it("takes the first code span of the first table cell", function()
      assert.equals(
        "grep -rn text .",
        parse.command_of("| `grep -rn text .` | search recursively |")
      )
    end)

    it("an escaped pipe in a cell is a pipe", function()
      assert.equals("a | b", parse.command_of("| `a \\| b` | text |"))
    end)

    it("a code span in a sentence is a word of the text, not a command", function()
      assert.is_nil(parse.command_of("run `ls` now"))
      assert.is_nil(parse.command_of("words | `ls` | more words"), "pipes alone do not make a row")
    end)

    it("a line without a command, a key or a Neovim command gives nil", function()
      assert.is_nil(parse.command_of("no code here"))
      assert.is_nil(parse.command_of("| `<C-r>` | search the history |"))
      assert.is_nil(parse.command_of("| `:Terminal list` | pick |"))
      assert.is_nil(parse.command_of("|---|---|"))
      assert.is_nil(parse.command_of(nil))
    end)

    it("a span with a control character is not typed (^O would run the line)", function()
      assert.is_nil(parse.command_of("| `a" .. string.char(15) .. "b` | text |"))
      assert.is_nil(parse.command_of("| `a" .. string.char(27) .. "[2Jb` | text |"))
      assert.is_nil(parse.command_of("| `a" .. string.char(9) .. "b` | text |"), "not even a tab")
    end)

    it("keeps a command that starts with <, like a process substitution", function()
      assert.equals("<(cmd) x", parse.command_of("| `<(cmd) x` | text |"))
    end)
  end)
end)

describe("terminal.cheatsheet (finding and loading sheets)", function()
  local sheets = require("terminal.cheatsheet")
  local parse = require("terminal.cheatsheet.parse")
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  ---@param name string
  ---@param text string
  local function write(name, text)
    vim.fn.writefile(vim.split(text, "\n", { plain = true }), dir .. "/" .. name)
    return dir .. "/" .. name
  end

  it("ships a sheet for bash, powershell, zsh, fish, cmd and common", function()
    for _, key in ipairs({ "bash", "powershell", "zsh", "fish", "cmd", "common" }) do
      local sheet = assert(sheets.load(key))
      assert.equals(key, sheet.key)
      assert.is_true(#sheet.sections >= 4, key)
    end
  end)

  it("every shell sheet has the eight areas, in the same order", function()
    local want = {
      "About",
      "Pipes and redirection",
      "Filters",
      "Variables and quoting",
      "Loops and conditions",
      "Paths and files",
      "Jobs and processes",
      "History and line editing",
      "Useful shortcuts",
    }
    for _, key in ipairs({ "bash", "powershell", "zsh", "fish", "cmd" }) do
      local titles = vim.tbl_map(function(s)
        return s.title
      end, assert(sheets.load(key)).sections)
      assert.same(want, titles, key)
    end
  end)

  it("every table row of the built-in sheets has as many cells as its header", function()
    for _, key in ipairs(sheets.names()) do
      for _, section in ipairs(assert(sheets.load(key)).sections) do
        local expected
        for _, line in ipairs(section.lines) do
          if line:match("^%s*|") then
            -- unescaped pipes only
            local _, pipes = line:gsub("\\|", ""):gsub("|", "")
            expected = expected or pipes
            assert.equals(expected, pipes, ("%s / %s: %s"):format(key, section.title, line))
          else
            expected = nil
          end
        end
      end
    end
  end)

  it("no built-in sheet holds a control character", function()
    for _, key in ipairs(sheets.names()) do
      for number, line in ipairs(vim.fn.readfile(assert(sheets.find(key)))) do
        assert.is_nil(line:find("%c"), ("%s line %d"):format(key, number))
      end
    end
  end)

  it(
    "builtin_dir finds the sheets from the runtimepath when the module's path says nothing",
    function()
      local root = sheets.builtin_dir():gsub("/docs/cheatsheets$", "")
      local rtp = vim.o.runtimepath
      vim.opt.runtimepath:prepend(root)
      local found = sheets.builtin_dir("@=[C]")
      vim.o.runtimepath = rtp
      assert.truthy(found)
      assert.equals(1, vim.fn.filereadable(found .. "/common.md"))
      assert.equals(sheets.builtin_dir(), found)
    end
  )

  it("a command in the built-in sheets is something to type", function()
    local sheet = assert(sheets.load("bash"))
    local section = sheet.sections[3] -- Filters
    local commands = 0
    for _, line in ipairs(section.lines) do
      if parse.command_of(line) then
        commands = commands + 1
      end
    end
    assert.is_true(commands >= 8)
  end)

  it("every section of a shell sheet offers commands to type", function()
    for _, key in ipairs({ "bash", "powershell", "zsh", "fish", "cmd" }) do
      for i, section in ipairs(assert(sheets.load(key)).sections) do
        if i > 1 then -- the first page is the introduction
          local commands = 0
          for _, line in ipairs(section.lines) do
            if parse.command_of(line) then
              commands = commands + 1
            end
          end
          assert.is_true(commands >= 3, ("%s / %s has %d"):format(key, section.title, commands))
        end
      end
    end
  end)

  it("zsh, fish and cmd have a sheet of their own, an unknown shell gets the common one", function()
    for _, key in ipairs({ "zsh", "fish", "cmd" }) do
      local sheet = assert(sheets.load(key))
      assert.equals(key, sheet.key)
      assert.equals(key, sheet.asked)
    end
    local unknown = assert(sheets.load("nu"))
    assert.equals("common", unknown.key)
    assert.equals("nu", unknown.asked)
  end)

  it("each shell program reaches its sheet", function()
    local detect = require("terminal.cheatsheet.detect")
    local wants = {
      ["C:/Windows/System32/cmd.exe"] = "cmd",
      ["/usr/bin/zsh"] = "zsh",
      ["/usr/bin/fish"] = "fish",
      ["pwsh"] = "powershell",
      ["/bin/dash"] = "bash",
    }
    for exe, want in pairs(wants) do
      assert.equals(want, assert(sheets.load(detect.detect(exe))).key, exe)
    end
  end)

  it("a folder of the user wins over the built-in sheet", function()
    write("bash.md", "# mine\n\n## Only\nx\n")
    local sheet = assert(sheets.load("bash", { dir = dir }))
    assert.equals(dir .. "/bash.md", sheet.path)
    assert.equals(1, #sheet.sections)
  end)

  it("a file named for a shell wins over the folder, and adds shells", function()
    write("fish.md", "## From dir\nx\n")
    local named = write("elsewhere.md", "## Named\ny\n")
    local sheet = assert(sheets.load("fish", { dir = dir, shells = { fish = named } }))
    assert.equals("Named", sheet.sections[1].title)
    local added = assert(sheets.load("nu", { shells = { nu = named } }))
    assert.equals("nu", added.key)
  end)

  it("a sheet without any section is skipped for the next candidate", function()
    write("bash.md", "just text, no heading at all\n")
    -- text without a heading is not nothing: it is the intro section
    assert.equals("bash", assert(sheets.load("bash", { dir = dir })).key)
    write("bash.md", "\n")
    assert.equals(
      "bash",
      assert(sheets.load("bash", { dir = dir })).key,
      "empty file: built-in sheet"
    )
    assert.not_equals(dir .. "/bash.md", sheets.load("bash", { dir = dir }).path)
  end)

  it("a key can never leave the folders", function()
    assert.is_nil(sheets.find("../x"))
    assert.is_nil(sheets.find("a/b"))
    assert.is_nil(sheets.find(nil))
    -- an odd key falls back to common instead of failing
    assert.equals("common", assert(sheets.load("../etc/passwd")).key)
  end)

  it("names lists the built-in sheets, the folder and the named shells, sorted, once", function()
    write("fish.md", "## A\nx\n")
    write("notes.txt", "x")
    local names =
      sheets.names({ dir = dir, shells = { nu = "/x.md", bash = "/y.md", ["bad key"] = "/z.md" } })
    assert.same({ "bash", "cmd", "common", "fish", "nu", "powershell", "zsh" }, names)
  end)
end)

describe("terminal.cheatsheet.ui (pure parts)", function()
  local ui = require("terminal.cheatsheet.ui")

  it("keeps the float inside the editor, at its right edge", function()
    local g = ui.geometry(200, 50)
    assert.equals(72, g.width)
    assert.is_true(g.col + g.width + 2 <= 200)
    assert.is_true(g.height <= 46)
    local small = ui.geometry(30, 8)
    assert.is_true(small.width <= 26)
    assert.is_true(small.height >= 3)
    assert.is_true(small.col >= 0)
  end)

  it("turns pages around the ends", function()
    assert.equals(2, ui.turn(1, 1, 3))
    assert.equals(1, ui.turn(3, 1, 3))
    assert.equals(3, ui.turn(1, -1, 3))
  end)

  it("titles the window with shell, position and section", function()
    assert.equals(" bash · 2/8 Filters ", ui.title("bash", 2, 8, "Filters"))
  end)
end)

describe("terminal.cheatsheet.ui (the window)", function()
  local ui = require("terminal.cheatsheet.ui")
  local sheets = require("terminal.cheatsheet")
  local api = vim.api
  local win

  ---@param extra? table
  ---@return table ctx, table log
  local function context(extra)
    local log = { typed = {}, messages = {} }
    local ctx = {
      load = function(key)
        return sheets.load(key)
      end,
      names = function()
        return { "bash", "common", "powershell" }
      end,
      type_line = function(text)
        log.typed[#log.typed + 1] = text
      end,
      prev_win = api.nvim_get_current_win(),
      was_terminal = false,
      notify = function(msg)
        log.messages[#log.messages + 1] = msg
      end,
    }
    return vim.tbl_extend("force", ctx, extra or {}), log
  end

  ---@param lhs string
  local function press(lhs)
    local map = api.nvim_buf_call(win.buf, function()
      return vim.fn.maparg(lhs, "n", false, true)
    end)
    assert.truthy(map.callback, "no mapping for " .. lhs)
    map.callback()
  end

  local function title()
    return api.nvim_win_get_config(win.win).title[1][1]
  end

  before_each(function()
    vim.cmd("silent! only")
    win = nil
  end)

  after_each(function()
    if win and api.nvim_win_is_valid(win.win) then
      win.close()
    end
    vim.cmd("silent! only")
  end)

  it("shows the first section with the shell and the position in the title", function()
    local sheet = assert(sheets.load("bash"))
    local ctx = context()
    win = ui.open(sheet, ctx)
    assert.is_true(api.nvim_win_is_valid(win.win))
    assert.same(sheet.sections[1].lines, api.nvim_buf_get_lines(win.buf, 0, -1, false))
    assert.truthy(title():find("bash · 1/9 About", 1, true))
    assert.is_false(vim.bo[win.buf].modifiable)
  end)

  it("]] and [[ turn the pages around the ends", function()
    local sheet = assert(sheets.load("bash"))
    win = ui.open(sheet, context())
    press("]]")
    assert.truthy(title():find("2/9 Pipes and redirection", 1, true))
    press("<Tab>")
    assert.truthy(title():find("3/9 Filters", 1, true))
    press("[[")
    press("<S-Tab>")
    press("[[")
    assert.truthy(title():find("9/9 Useful shortcuts", 1, true), "before the first comes the last")
    press("]]")
    assert.truthy(title():find("1/9", 1, true))
  end)

  it("/ searches every section, n and N walk through the matches", function()
    local sheet = assert(sheets.load("bash"))
    local ctx, log = context({
      input = function(_, on_confirm)
        on_confirm("uniq")
      end,
    })
    win = ui.open(sheet, ctx)
    press("/")
    assert.truthy(title():find("3/9 Filters", 1, true), "uniq is in the Filters section")
    local line = api.nvim_get_current_line()
    assert.truthy(line:find("uniq", 1, true))
    local marks = api.nvim_buf_get_extmarks(
      win.buf,
      api.nvim_create_namespace("terminal.cheatsheet"),
      0,
      -1,
      { details = true }
    )
    assert.equals(1, #marks, "the match is marked")
    press("n")
    press("N")
    assert.equals(0, #log.messages)
  end)

  it("a search without a hit says so and stays", function()
    local sheet = assert(sheets.load("bash"))
    local ctx, log = context({
      input = function(_, on_confirm)
        on_confirm("zzzzzz-nothing")
      end,
    })
    win = ui.open(sheet, ctx)
    press("/")
    assert.truthy(title():find("1/9", 1, true))
    assert.truthy(log.messages[1]:find("nothing matches", 1, true))
    press("n")
    assert.truthy(
      log.messages[2]:find("no search yet", 1, true) or log.messages[2]:find("press /", 1, true)
    )
  end)

  it("g? shows the common sheet and goes back to the shell's", function()
    local sheet = assert(sheets.load("bash"))
    win = ui.open(sheet, context())
    press("g?")
    assert.truthy(title():find("common · 1/", 1, true))
    press("g?")
    assert.truthy(title():find("bash · 1/9", 1, true))
  end)

  it("s switches to the sheet picked from the list", function()
    local sheet = assert(sheets.load("bash"))
    local seen
    local ctx = context({
      select = function(items, _, on_choice)
        seen = items
        on_choice("powershell")
      end,
    })
    win = ui.open(sheet, ctx)
    press("s")
    assert.same({ "bash", "common", "powershell" }, seen)
    assert.truthy(title():find("powershell · 1/9", 1, true))
  end)

  it("<CR> types the command on the line into the terminal and closes the window", function()
    local sheet = assert(sheets.load("bash"))
    local ctx, log = context()
    win = ui.open(sheet, ctx)
    press("]]") -- Pipes and redirection
    local row
    for i, text in ipairs(api.nvim_buf_get_lines(win.buf, 0, -1, false)) do
      if text:find("cmd 2> file", 1, true) then
        row = i
      end
    end
    assert.truthy(row)
    api.nvim_win_set_cursor(win.win, { row, 0 })
    local float = win.win
    press("<CR>")
    assert.same({ "cmd 2> file" }, log.typed)
    assert.is_false(api.nvim_win_is_valid(float))
    assert.equals(ctx.prev_win, api.nvim_get_current_win())
  end)

  it("<CR> on a line without a command types nothing and keeps the window", function()
    local sheet = assert(sheets.load("bash"))
    local ctx, log = context()
    win = ui.open(sheet, ctx)
    press("]]")
    api.nvim_win_set_cursor(win.win, { 1, 0 }) -- the table header
    press("<CR>")
    assert.same({}, log.typed)
    assert.is_true(api.nvim_win_is_valid(win.win))
    assert.truthy(log.messages[1]:find("no command", 1, true))
  end)

  it("an answer that comes after the window is gone does nothing and raises nothing", function()
    local sheet = assert(sheets.load("bash"))
    local late = {}
    local ctx = context({
      input = function(_, on_confirm)
        late.input = on_confirm
      end,
      select = function(_, _, on_choice)
        late.select = on_choice
      end,
    })
    win = ui.open(sheet, ctx)
    press("/")
    press("s")
    local float = win.win
    win.close()
    assert.is_false(api.nvim_win_is_valid(float))
    assert.has_no.errors(function()
      late.input("uniq")
      late.select("powershell")
    end)
    assert.is_nil(ui.active())
  end)

  it("active is the open window, and nothing once it is closed", function()
    local sheet = assert(sheets.load("bash"))
    win = ui.open(sheet, context())
    assert.equals(win.win, ui.active().win)
    win.close()
    assert.is_nil(ui.active())
  end)

  it("q and <Esc> close it and give the cursor back", function()
    local sheet = assert(sheets.load("bash"))
    for _, lhs in ipairs({ "q", "<Esc>" }) do
      local ctx = context()
      win = ui.open(sheet, ctx)
      local float = win.win
      press(lhs)
      assert.is_false(api.nvim_win_is_valid(float), lhs)
      assert.equals(ctx.prev_win, api.nvim_get_current_win(), lhs)
    end
  end)
end)

describe("terminal.cheatsheet on a real terminal (the facade)", function()
  local terminal
  local original_notify = vim.notify

  before_each(function()
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.backends.native",
      "terminal.bindings",
    }) do
      package.loaded[mod] = nil
    end
    -- Test double: nothing here is meant to reach the user; restored in after_each.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
    terminal = require("terminal")
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
      cheatsheet = { shell = "bash" },
    })
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if
        vim.api.nvim_win_get_config(win).relative ~= ""
        and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "markdown"
      then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = original_notify
  end)

  local function cheat_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_win_get_config(win).relative ~= "" and vim.bo[buf].filetype == "markdown" then
        return win, buf
      end
    end
  end

  it("opens the sheet of the configured shell and closes back to where it was", function()
    local before = vim.api.nvim_get_current_win()
    assert.is_true(terminal.cheatsheet())
    local win = cheat_window()
    assert.truthy(win)
    assert.truthy(vim.api.nvim_win_get_config(win).title[1][1]:find("bash", 1, true))
    vim.api.nvim_win_close(win, true)
    assert.equals(before, vim.api.nvim_get_current_win())
  end)

  it(
    "called again while the window is open, it closes the window instead of opening a second",
    function()
      assert.is_true(terminal.cheatsheet())
      local win = cheat_window()
      assert.truthy(win)
      assert.is_true(terminal.cheatsheet())
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.is_nil(cheat_window())
      -- and the key inside the float does the same
      assert.is_true(terminal.cheatsheet())
      assert.truthy(cheat_window())
      assert.is_true(terminal.cheatsheet({ shell = "powershell" }))
      assert.is_nil(cheat_window())
    end
  )

  it("the argument forces another sheet; an unknown shell shows the common one", function()
    assert.is_true(terminal.cheatsheet({ shell = "powershell" }))
    local win = cheat_window()
    assert.truthy(vim.api.nvim_win_get_config(win).title[1][1]:find("powershell", 1, true))
    vim.api.nvim_win_close(win, true)
    assert.is_true(terminal.cheatsheet({ shell = "nu" }))
    win = cheat_window()
    assert.truthy(vim.api.nvim_win_get_config(win).title[1][1]:find("common", 1, true))
  end)

  it("from a terminal, <CR> types the line into that terminal, without Enter", function()
    assert.truthy(terminal.open({ name = "repl", layout = "split" }))
    local handle = terminal.list()[1]
    assert.equals(handle.bufnr, vim.api.nvim_get_current_buf())
    local sent = jobs.record_sends(function()
      assert.is_true(terminal.cheatsheet({ shell = "bash" }))
      local win, buf = cheat_window()
      vim.api.nvim_buf_call(buf, function()
        vim.fn.maparg("]]", "n", false, true).callback()
      end)
      local row
      for i, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if text:find("cmd 2> file", 1, true) then
          row = i
        end
      end
      vim.api.nvim_win_set_cursor(win, { row, 0 })
      local map = vim.api.nvim_buf_call(buf, function()
        return vim.fn.maparg("<CR>", "n", false, true)
      end)
      map.callback()
    end)
    assert.equals(1, #sent)
    assert.equals("cmd 2> file", sent[1].text, "typed as is: no line ending, so nothing runs")
    assert.equals(handle.job, sent[1].job)
  end)

  it("a bad cheatsheet table in setup() is reported and the defaults stay", function()
    local config = require("terminal.config")
    local problems = config.setup({ cheatsheet = { shell = 7, dir = {}, shells = "x", other = 1 } })
    assert.equals(4, #problems)
    assert.equals("", config.get("cheatsheet.shell"))
    assert.same({}, config.get("cheatsheet.shells"))
  end)

  it(":Terminal cheat completes the sheets and is a command", function()
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      keymaps = { preset = false },
    })
    local items = vim.fn.getcompletion("Terminal cheat ", "cmdline")
    for _, want in ipairs({ "bash", "common", "powershell" }) do
      assert.is_true(vim.tbl_contains(items, want), want)
    end
    local subcommands = vim.fn.getcompletion("Terminal ", "cmdline")
    assert.is_true(vim.tbl_contains(subcommands, "cheat"))
    vim.cmd("Terminal cheat powershell")
    local win = cheat_window()
    assert.truthy(win)
    assert.truthy(vim.api.nvim_win_get_config(win).title[1][1]:find("powershell", 1, true))
  end)

  it("keymaps.cheatsheet binds a key; it is off by default", function()
    local DEFAULTS = require("terminal.config.DEFAULTS")
    assert.is_false(DEFAULTS.keymaps.cheatsheet)
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { cheatsheet = "<A-?>" },
    })
    local map = vim.fn.maparg("<A-?>", "n", false, true)
    assert.truthy(map.callback)
    assert.truthy(map.desc:find("Cheatsheet", 1, true))
  end)
end)
