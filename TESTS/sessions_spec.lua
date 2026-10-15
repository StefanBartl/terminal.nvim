---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/sessions_spec.lua -- terminal.sessions: terminal definitions saved beside a sessions.nvim session and reopened on load.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

describe("terminal.sessions (definitions and a fake facade)", function()
  local sessions = require("terminal.sessions")
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  ---@param handles table[]
  ---@param calls? table[]
  ---@param fail_for? table<string, boolean>
  local function fake(handles, calls, fail_for)
    calls = calls or {}
    fail_for = fail_for or {}
    return {
      list = function()
        return handles
      end,
      open = function(target)
        calls[#calls + 1] = { "open", target.name, target.layout, target.focus }
        if fail_for[target.name] then
          return nil, "no way"
        end
        return { name = target.name }
      end,
      run = function(cmd, opts)
        calls[#calls + 1] = { "run", opts.name, table.concat(cmd, " "), opts.cwd, opts.direct }
        if fail_for[opts.name] then
          return false, "no way"
        end
        return true
      end,
      hide = function(target)
        calls[#calls + 1] = { "hide", target.name }
        return true
      end,
    }
  end

  it("the sidecar sits beside the session file, named like sessions.nvim's own", function()
    assert.equals("/s/.work.terminals.json", sessions.sidecar_path("/s/work.vim"))
  end)

  it("validate keeps what is safe to act on and drops the rest", function()
    local defs = sessions.validate({
      terminals = {
        { name = "main", layout = "float" },
        { name = "main", layout = "split" }, -- the same name twice
        { name = "", layout = "float" },
        { name = "x", layout = "nonsense" },
        { name = "build", layout = "split", cmd = { "make", "all" }, cwd = "/p" },
        { name = "bad-cmd", layout = "tab", cmd = { "make", 7 } },
        "not a table",
      },
    })
    assert.equals(3, #defs)
    assert.equals("main", defs[1].name)
    assert.same({ "make", "all" }, defs[2].cmd)
    assert.is_nil(defs[3].cmd)
    assert.same({}, sessions.validate("nonsense"))
    assert.same({}, sessions.validate({ terminals = "nonsense" }))
  end)

  it("snapshot takes live native terminals only", function()
    local api = fake({
      { name = "a", backend = "native", layout = "float", cwd = "/p" },
      { name = "b", backend = "native", layout = "split", cmd = { "x" }, cwd = "/p" },
      { name = "gone", backend = "native", layout = "float", exited = true },
      { name = "closed", backend = "native", layout = "float", disposed = true },
      { name = "pane", backend = "tmux", layout = "vsplit" },
      { name = "shell-string", backend = "native", layout = "float", cmd = "ls" },
    })
    local defs = sessions.snapshot(api)
    assert.equals(3, #defs)
    assert.equals("a", defs[1].name)
    assert.same({ "x" }, defs[2].cmd)
    assert.is_nil(defs[3].cmd) -- only an argv is a command worth restoring
  end)

  it("save writes the sidecar and removes it when no terminal is left", function()
    local path = dir .. "/work.vim"
    local file = sessions.sidecar_path(path)
    assert.is_true(
      (sessions.save(fake({ { name = "a", backend = "native", layout = "float" } }), path))
    )
    assert.equals(1, vim.fn.filereadable(file))
    assert.equals("a", sessions.read(path)[1].name)
    assert.is_true((sessions.save(fake({}), path)))
    assert.equals(0, vim.fn.filereadable(file))
  end)

  it("read of a missing or damaged sidecar is empty, never an error", function()
    local path = dir .. "/work.vim"
    assert.same({}, sessions.read(path))
    local f = assert(io.open(sessions.sidecar_path(path), "w"))
    f:write("{ not json")
    f:close()
    assert.same({}, sessions.read(path))
  end)

  it(
    "restore reopens hidden, runs commands directly and leaves existing terminals alone",
    function()
      local calls = {}
      local api = fake({ { name = "keep", backend = "native", layout = "float" } }, calls)
      local result = sessions.restore(api, {
        { name = "keep", layout = "float" },
        { name = "sh", layout = "split" },
        { name = "build", layout = "float", cmd = { "make", "all" }, cwd = "/p" },
      }, true)
      assert.equals(2, result.opened)
      assert.equals(1, result.skipped)
      assert.same({ "open", "sh", "split", false }, calls[1])
      assert.same({ "hide", "sh" }, calls[2])
      assert.same({ "run", "build", "make all", "/p", true }, calls[3])
      assert.same({ "hide", "build" }, calls[4])
    end
  )

  it("restore without commands opens the command terminals as plain shells", function()
    local calls = {}
    sessions.restore(fake({}, calls), {
      { name = "build", layout = "float", cmd = { "make" } },
    }, false)
    assert.same({ "open", "build", "float", false }, calls[1])
  end)

  it("restore reports what failed and goes on", function()
    local result = sessions.restore(
      fake({}, nil, { bad = true }),
      { { name = "bad", layout = "float" }, { name = "good", layout = "float" } },
      true
    )
    assert.equals(1, result.opened)
    assert.equals(1, #result.failed)
    assert.truthy(result.failed[1]:find("bad: no way", 1, true))
  end)

  describe("load", function()
    local path
    before_each(function()
      path = dir .. "/work.vim"
      sessions.save(fake({}), path)
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      f:write(vim.json.encode({
        version = 1,
        terminals = {
          { name = "sh", layout = "float" },
          { name = "build", layout = "float", cmd = { "make" } },
        },
      }))
      f:close()
    end)

    local function kinds(calls)
      local out = {}
      for _, c in ipairs(calls) do
        out[#out + 1] = c[1] .. ":" .. c[2]
      end
      return out
    end

    it("ask: asks once, and Start runs the commands", function()
      local calls, asked = {}, 0
      sessions.load(fake({}, calls), path, "ask", function(items, opts, on_choice)
        asked = asked + 1
        assert.truthy(opts.prompt:find("build: make", 1, true))
        on_choice(items[1])
      end)
      assert.equals(1, asked)
      assert.same({ "open:sh", "hide:sh", "run:build", "hide:build" }, kinds(calls))
    end)

    it("ask: plain shells open the terminals without the command", function()
      local calls = {}
      sessions.load(fake({}, calls), path, "ask", function(items, _, on_choice)
        on_choice(items[2])
      end)
      assert.same({ "open:sh", "hide:sh", "open:build", "hide:build" }, kinds(calls))
    end)

    it("ask: skipping, or dismissing the prompt, opens nothing", function()
      for _, pick in ipairs({ 3, 0 }) do
        local calls = {}
        sessions.load(fake({}, calls), path, "ask", function(items, _, on_choice)
          on_choice(items[pick])
        end)
        assert.same({}, calls)
      end
    end)

    it("run and never decide without asking", function()
      local function no_ask()
        error("must not ask")
      end
      local calls = {}
      sessions.load(fake({}, calls), path, "run", no_ask)
      assert.same({ "open:sh", "hide:sh", "run:build", "hide:build" }, kinds(calls))
      calls = {}
      sessions.load(fake({}, calls), path, "never", no_ask)
      assert.same({ "open:sh", "hide:sh", "open:build", "hide:build" }, kinds(calls))
    end)

    it("ask: the prompt shows the directory and spells out control characters", function()
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      f:write(vim.json.encode({
        terminals = {
          {
            name = "evil\nbuild: make",
            layout = "float",
            cmd = { "sh", "-c", "a\nb" },
            cwd = "/x",
          },
        },
      }))
      f:close()
      local prompt
      sessions.load(fake({}, {}), path, "ask", function(_, opts, on_choice)
        prompt = opts.prompt
        on_choice(nil)
      end)
      assert.is_nil(prompt:find("evil\n", 1, true), "no raw newline of an entry reaches the prompt")
      assert.truthy(prompt:find("evil\\x0abuild", 1, true))
      assert.truthy(prompt:find("a\\x0ab", 1, true))
      assert.truthy(prompt:find("(in /x)", 1, true), "the directory it would run in is shown")
      local _, lines = prompt:gsub("\n", "")
      assert.equals(1, lines, "the prompt keeps its own two lines only")
    end)

    it("ask: Unicode controls that reorder or hide text are spelled out too", function()
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      -- U+202E right-to-left override, U+200B zero width space, U+0085 C1 control, U+2066 isolate
      local rlo, zwsp, c1, lri = "\226\128\174", "\226\128\139", "\194\133", "\226\129\166"
      f:write(vim.json.encode({
        terminals = {
          {
            name = "a" .. rlo .. "b" .. zwsp .. "c",
            layout = "float",
            cmd = { "make" .. c1, "x" .. lri .. "y" },
          },
        },
      }))
      f:close()
      local prompt
      sessions.load(fake({}, {}), path, "ask", function(_, opts, on_choice)
        prompt = opts.prompt
        on_choice(nil)
      end)
      for _, raw in ipairs({ rlo, zwsp, c1, lri }) do
        assert.is_nil(prompt:find(raw, 1, true), "a raw control reached the prompt")
      end
      assert.truthy(prompt:find("\\xe2\\x80\\xae", 1, true))
      assert.truthy(prompt:find("\\xc2\\x85", 1, true))
      assert.truthy(prompt:find("\\xe2\\x81\\xa6", 1, true))
    end)

    it("ask: invisible characters and separators are spelled out as well", function()
      local invisible = {
        ["\\xef\\xbb\\xbf"] = "\239\187\191", -- U+FEFF
        ["\\xc2\\xad"] = "\194\173", -- U+00AD soft hyphen
        ["\\xd8\\x9c"] = "\216\156", -- U+061C Arabic letter mark
        ["\\xe2\\x80\\xa8"] = "\226\128\168", -- U+2028 line separator
        ["\\xe2\\x81\\xa0"] = "\226\129\160", -- U+2060 word joiner
        ["\\xf3\\xa0\\x80\\xa1"] = "\243\160\128\161", -- U+E0021 tag character
      }
      local words = {}
      for _, raw in pairs(invisible) do
        words[#words + 1] = "x" .. raw .. "y"
      end
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      f:write(vim.json.encode({
        terminals = { { name = "n", layout = "float", cmd = words } },
      }))
      f:close()
      local prompt
      sessions.load(fake({}, {}), path, "ask", function(_, opts, on_choice)
        prompt = opts.prompt
        on_choice(nil)
      end)
      for spelled, raw in pairs(invisible) do
        assert.is_nil(prompt:find(raw, 1, true), "raw " .. spelled .. " reached the prompt")
        assert.truthy(prompt:find(spelled, 1, true), spelled .. " is not spelled out")
      end
    end)

    it("ask: ordinary non-ASCII text is not touched", function()
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      f:write(vim.json.encode({
        terminals = {
          { name = "Bäume", layout = "float", cmd = { "echo", "größe £ © · – €" } },
        },
      }))
      f:close()
      local prompt
      sessions.load(fake({}, {}), path, "ask", function(_, opts, on_choice)
        prompt = opts.prompt
        on_choice(nil)
      end)
      assert.truthy(prompt:find("Bäume: echo größe £ © · – €", 1, true))
    end)

    it("ask: one very long entry is cut", function()
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      f:write(vim.json.encode({
        terminals = { { name = "x", layout = "float", cmd = { string.rep("a", 5000) } } },
      }))
      f:close()
      local prompt
      sessions.load(fake({}, {}), path, "ask", function(_, opts, on_choice)
        prompt = opts.prompt
        on_choice(nil)
      end)
      assert.is_true(#prompt < 400)
    end)

    describe("what a load did not bring back survives the next save", function()
      local function names(file_path)
        local out = {}
        for _, d in ipairs(sessions.read(file_path)) do
          out[#out + 1] = d.name .. (d.cmd and "+cmd" or "")
        end
        table.sort(out)
        return out
      end

      it("skipping keeps both definitions", function()
        sessions.load(fake({}, {}), path, "ask", function(items, _, on_choice)
          on_choice(items[3])
        end)
        assert.is_true((sessions.save(fake({}), path)))
        assert.same({ "build+cmd", "sh" }, names(path))
      end)

      it("an unanswered prompt keeps them too", function()
        sessions.load(fake({}, {}), path, "ask", function() end)
        assert.is_true((sessions.save(fake({}), path)))
        assert.same({ "build+cmd", "sh" }, names(path))
      end)

      it("plain shells keep the command of the terminal they replaced", function()
        local shells = {
          { name = "sh", backend = "native", layout = "float" },
          { name = "build", backend = "native", layout = "float" },
        }
        -- Nothing is live while the load runs; the plain shells it opens are what `shells` lists.
        sessions.load(fake({}, {}), path, "never")
        assert.is_true((sessions.save(fake(shells), path)))
        assert.same({ "build+cmd", "sh" }, names(path))
      end)

      it("a failed start is kept, the started one is written as it is", function()
        local live = { { name = "sh", backend = "native", layout = "float" } }
        sessions.load(fake({}, {}, { build = true }), path, "run")
        assert.is_true((sessions.save(fake(live), path)))
        assert.same({ "build+cmd", "sh" }, names(path))
      end)

      it("a full restore keeps nothing: closing the terminals removes the file", function()
        sessions.load(fake({}, {}), path, "run")
        assert.is_true((sessions.save(fake({}), path)))
        assert.equals(0, vim.fn.filereadable(sessions.sidecar_path(path)))
      end)

      it(
        "a live terminal of the same name wins, rename moves what was kept, delete drops it",
        function()
          sessions.load(fake({}, {}), path, "ask", function(items, _, on_choice)
            on_choice(items[3])
          end)
          local renamed = dir .. "/renamed.vim"
          sessions.rename(path, renamed)
          assert.is_true((sessions.save(fake({}), renamed)))
          assert.same({ "build+cmd", "sh" }, names(renamed))
          assert.is_true(
            (
              sessions.save(
                fake({ { name = "sh", backend = "native", layout = "split" } }),
                renamed
              )
            )
          )
          assert.equals(
            "split",
            sessions.read(renamed)[1].layout,
            "the live one is the newer truth"
          )
          sessions.delete(renamed)
          assert.is_true((sessions.save(fake({}), renamed)))
          assert.equals(0, vim.fn.filereadable(sessions.sidecar_path(renamed)))
        end
      )
    end)

    it("a session without commands is not asked about", function()
      local f = assert(io.open(sessions.sidecar_path(path), "w"))
      f:write(vim.json.encode({ terminals = { { name = "sh", layout = "float" } } }))
      f:close()
      local calls = {}
      sessions.load(fake({}, calls), path, "ask", function()
        error("must not ask")
      end)
      assert.same({ "open:sh", "hide:sh" }, kinds(calls))
    end)
  end)
end)

describe("terminal.sessions (the User events, on the real facade)", function()
  local terminal
  local dir
  local original_notify = vim.notify

  local function boot(extra)
    for _, mod in ipairs({
      "terminal",
      "terminal.config",
      "terminal.sessions",
      "terminal.backends.native",
      "terminal.bindings",
    }) do
      package.loaded[mod] = nil
    end
    terminal = require("terminal")
    terminal.setup(vim.tbl_deep_extend("force", {
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    }, extra or {}))
  end

  ---@param tab? boolean
  ---@param path string
  local function fire(event, path, tab)
    vim.api.nvim_exec_autocmds("User", {
      pattern = event,
      data = { name = "work", path = path, tab = tab or false },
    })
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    -- Test double: nothing in these specs is meant to reach the user; restored in after_each.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
  end)

  after_each(function()
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.api.nvim_clear_autocmds({ group = "terminal.sessions" })
    vim.fn.delete(dir, "rf")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = original_notify
  end)

  it(
    "SessionsSavePost writes the sidecar, SessionsLoadPost brings the terminals back hidden",
    function()
      boot({ sessions = { commands = "run" } })
      local session = dir .. "/work.vim"
      assert.truthy(terminal.open({ name = "alpha", layout = "split" }))
      assert.truthy(terminal.open({ name = "beta", layout = "float" }))
      fire("SessionsSavePost", session)
      assert.equals(1, vim.fn.filereadable(require("terminal.sessions").sidecar_path(session)))

      for _, h in ipairs(terminal.list(true)) do
        jobs.settle()
        terminal.close({ name = h.name })
      end
      assert.equals(0, #terminal.list(true))

      fire("SessionsLoadPost", session)
      local names = terminal.names()
      table.sort(names)
      assert.same({ "alpha", "beta" }, names)
      for _, h in ipairs(terminal.list()) do
        assert.same({}, vim.fn.win_findbuf(h.bufnr), h.name .. " comes back hidden")
      end

      -- Loading the same session again must not duplicate or replace anything.
      local before = {}
      for _, h in ipairs(terminal.list()) do
        before[h.name] = h.bufnr
      end
      fire("SessionsLoadPost", session)
      assert.equals(2, #terminal.list())
      for _, h in ipairs(terminal.list()) do
        assert.equals(before[h.name], h.bufnr)
      end
    end
  )

  it("SessionsRenamePost moves the sidecar, SessionsDeletePost removes it", function()
    boot()
    local sessions = require("terminal.sessions")
    local old, new = dir .. "/old.vim", dir .. "/new.vim"
    assert.truthy(terminal.open({ name = "alpha" }))
    fire("SessionsSavePost", old)
    local old_file, new_file = sessions.sidecar_path(old), sessions.sidecar_path(new)
    assert.equals(1, vim.fn.filereadable(old_file))

    -- A leftover sidecar of the new name must not survive the move.
    vim.fn.writefile({ "{}" }, new_file)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "SessionsRenamePost",
      data = { old_name = "old", old_path = old, name = "new", path = new },
    })
    assert.equals(0, vim.fn.filereadable(old_file))
    assert.equals(1, vim.fn.filereadable(new_file))
    assert.equals("alpha", sessions.read(new)[1].name)

    -- A rename without a sidecar of the old name is not an error, and an orphan at the new name goes.
    local orphan = sessions.sidecar_path(dir .. "/y.vim")
    vim.fn.writefile({ "{}" }, orphan)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "SessionsRenamePost",
      data = {
        old_name = "none",
        old_path = dir .. "/none.vim",
        name = "y",
        path = dir .. "/y.vim",
      },
    })
    assert.equals(0, vim.fn.filereadable(orphan), "an orphan sidecar must not outlive the rename")
    -- A rename without any sidecar is a no-op, not an error.
    vim.api.nvim_exec_autocmds("User", {
      pattern = "SessionsRenamePost",
      data = {
        old_name = "none",
        old_path = dir .. "/none.vim",
        name = "x",
        path = dir .. "/x.vim",
      },
    })
    assert.equals(0, vim.fn.filereadable(sessions.sidecar_path(dir .. "/x.vim")))

    vim.api.nvim_exec_autocmds("User", {
      pattern = "SessionsDeletePost",
      data = { name = "new", path = new },
    })
    assert.equals(0, vim.fn.filereadable(new_file))
  end)

  it("sessions.enable = false does not touch the sidecar on rename or delete", function()
    boot({ sessions = { enable = false } })
    local sessions = require("terminal.sessions")
    local old = dir .. "/old.vim"
    vim.fn.writefile({ "{}" }, sessions.sidecar_path(old))
    vim.api.nvim_exec_autocmds("User", {
      pattern = "SessionsDeletePost",
      data = { name = "old", path = old },
    })
    assert.equals(1, vim.fn.filereadable(sessions.sidecar_path(old)))
  end)

  it("a shell configured as an argv is not recorded as a command", function()
    boot()
    assert.truthy(terminal.open({ name = "alpha" }))
    assert.truthy(terminal.run(jobs.exit_with(0), { name = "job", direct = true, close = "never" }))
    local defs = require("terminal.sessions").snapshot(terminal)
    local by_name = {}
    for _, d in ipairs(defs) do
      by_name[d.name] = d
    end
    assert.is_nil(by_name.alpha.cmd)
  end)

  it("a tab snapshot carries no terminals", function()
    boot()
    local session = dir .. "/work.vim"
    assert.truthy(terminal.open({ name = "alpha" }))
    fire("SessionsSavePost", session, true)
    assert.equals(0, vim.fn.filereadable(require("terminal.sessions").sidecar_path(session)))
  end)

  it("sessions.enable = false listens to nothing", function()
    boot({ sessions = { enable = false } })
    local session = dir .. "/work.vim"
    assert.truthy(terminal.open({ name = "alpha" }))
    fire("SessionsSavePost", session)
    assert.equals(0, vim.fn.filereadable(require("terminal.sessions").sidecar_path(session)))
  end)

  it("calling setup again does not make a listener run twice", function()
    boot()
    terminal.setup({
      shell = jobs.sleeper(),
      start_insert = false,
      commands = false,
      keymaps = { preset = false },
    })
    local session = dir .. "/work.vim"
    assert.truthy(terminal.open({ name = "alpha" }))
    local writes = 0
    local sessions = require("terminal.sessions")
    local original = sessions.save
    -- Test double: counts the calls and runs the real thing; restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    sessions.save = function(...)
      writes = writes + 1
      return original(...)
    end
    fire("SessionsSavePost", session)
    sessions.save = original
    assert.equals(1, writes)
  end)
end)
