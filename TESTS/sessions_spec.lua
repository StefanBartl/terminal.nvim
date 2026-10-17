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
        -- The whole options of each run, by name (a named key: `#calls` and calls[i] stay as they are).
        calls.run_opts = calls.run_opts or {}
        calls.run_opts[opts.name] = opts
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

  it("validate keeps close, title and float of a command, and only what is safe", function()
    local defs = sessions.validate({
      terminals = {
        {
          name = "lg",
          layout = "float",
          cmd = { "lazygit" },
          close = "success",
          title = "Git",
          float = { width = 0.9, border = "single" },
        },
        {
          name = "bad",
          layout = "float",
          cmd = { "x" },
          close = "sometimes",
          title = "a\nb",
          float = { width = -1, border = "nonsense", unknown = 1 },
        },
        { name = "sh", layout = "float", close = "always", title = "Shell", float = { width = 1 } },
        { name = "list-float", layout = "float", cmd = { "x" }, float = { 1, 2 } },
      },
    })
    assert.equals(4, #defs)
    assert.equals("success", defs[1].close)
    assert.equals("Git", defs[1].title)
    assert.same({ width = 0.9, border = "single" }, defs[1].float)
    -- An unknown close mode, a title with a control character and every bad float key are dropped.
    assert.is_nil(defs[2].close)
    assert.is_nil(defs[2].title)
    assert.is_nil(defs[2].float)
    -- A plain shell has nothing `run` would be given.
    assert.is_nil(defs[3].close)
    assert.is_nil(defs[3].title)
    assert.is_nil(defs[3].float)
    assert.is_nil(defs[4].float)
  end)

  it("snapshot writes close, title and float of a run with direct", function()
    local api = fake({
      {
        name = "lg",
        backend = "native",
        layout = "float",
        cmd = { "lazygit" },
        rerun = { close = "always", title = "Git", float = { height = 0.5, on_open = print } },
      },
      { name = "sh", backend = "native", layout = "float", rerun = { close = "always" } },
    })
    local defs = sessions.snapshot(api)
    assert.equals("always", defs[1].close)
    assert.equals("Git", defs[1].title)
    -- Only what the configuration knows: a function cannot go into a sidecar.
    assert.same({ height = 0.5 }, defs[1].float)
    assert.is_nil(defs[2].close)
  end)

  it("restore gives run the saved close, title and float", function()
    local calls = {}
    sessions.restore(fake({}, calls), {
      {
        name = "lg",
        layout = "float",
        cmd = { "lazygit" },
        close = "success",
        title = "Git",
        float = { width = 0.5 },
      },
    }, true)
    local opts = calls.run_opts.lg
    assert.equals("success", opts.close)
    assert.equals("Git", opts.title)
    assert.same({ width = 0.5 }, opts.float)
    assert.is_true(opts.direct)
  end)

  it("snapshot leaves out a terminal that run kept out of the session", function()
    local api = fake({
      { name = "keep", backend = "native", layout = "float", cmd = { "x" }, cwd = "/p" },
      { name = "lg", backend = "native", layout = "float", cmd = { "lazygit" }, session = false },
    })
    local defs = sessions.snapshot(api)
    assert.equals(1, #defs)
    assert.equals("keep", defs[1].name)
    assert.same({ lg = true }, sessions.opted_out(api))
  end)

  it("a live terminal kept out of the session drops its saved definition", function()
    local live = { { name = "a", layout = "float" } }
    local left_over = {
      { name = "lg", layout = "float", cmd = { "lazygit" } },
      { name = "build", layout = "split", cmd = { "make" } },
    }
    local merged = sessions.merge(live, left_over, { lg = true })
    local names = {}
    for _, def in ipairs(merged) do
      names[#names + 1] = def.name
    end
    assert.same({ "a", "build" }, names)
    -- Without opted-out names the left-over definition is written again.
    assert.equals(3, #sessions.merge(live, left_over))
  end)

  it("the drop of a saved definition outlives the terminal that was kept out", function()
    local path = dir .. "/work.vim"
    local f = assert(io.open(sessions.sidecar_path(path), "w"))
    f:write(vim.json.encode({
      version = 1,
      terminals = {
        { name = "lg", layout = "float", cmd = { "lazygit" } },
        { name = "build", layout = "split", cmd = { "make" } },
      },
    }))
    f:close()
    -- Loaded without commands: both come back as plain shells, and both stay left over.
    sessions.load(fake({}), path, "never")
    -- `run{ direct, session = false }` replaces lg; build is not open at all.
    local handles = {
      { name = "lg", backend = "native", layout = "float", cmd = { "lazygit" }, session = false },
    }
    assert.is_true((sessions.save(fake(handles), path)))
    local function names()
      local out = {}
      for _, def in ipairs(sessions.read(path)) do
        out[#out + 1] = def.name
      end
      return out
    end
    assert.same({ "build" }, names())
    -- lazygit ends (close = "always"): the handle is gone, and the next save must not bring the
    -- old lg definition back.
    assert.is_true((sessions.save(fake({}), path)))
    assert.same({ "build" }, names())
    -- An exited handle that is still listed counts as gone as well.
    handles[1].exited = true
    assert.is_true((sessions.save(fake(handles), path)))
    assert.same({ "build" }, names())
    sessions.delete(path)
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

  it("run with direct and session = false is not saved; a normal direct run is", function()
    boot()
    local sessions = require("terminal.sessions")
    local session = dir .. "/work.vim"
    local ok, _, lg = terminal.run(jobs.sleeper(), { name = "lg", direct = true, session = false })
    assert.is_true(ok)
    assert.is_false(lg.session)
    local ok2, _, watch = terminal.run(jobs.sleeper(), { name = "watch", direct = true })
    assert.is_true(ok2)
    assert.is_nil(watch.session)
    local names = {}
    for _, d in ipairs(sessions.snapshot(terminal)) do
      names[#names + 1] = d.name
    end
    assert.same({ "watch" }, names)
    fire("SessionsSavePost", session)
    local saved = sessions.read(session)
    assert.equals(1, #saved)
    assert.equals("watch", saved[1].name)
  end)

  it("a direct run comes back from the session with its close, title and float", function()
    boot({ sessions = { commands = "run" } })
    local session = dir .. "/work.vim"
    -- Not the configured shell's argv (that would be saved as a plain shell): 61 s, not 60.
    local cmd = vim.tbl_map(function(word)
      return word == "60" and "61" or word
    end, jobs.sleeper())
    assert.truthy(terminal.run(cmd, {
      name = "lg",
      direct = true,
      layout = "float",
      close = "success",
      title = "Git",
      float = { width = 0.5 },
    }))
    fire("SessionsSavePost", session)
    for _, h in ipairs(terminal.list(true)) do
      jobs.settle()
      terminal.close({ name = h.name })
    end
    assert.equals(0, #terminal.list(true))

    fire("SessionsLoadPost", session)
    local h = terminal.list()[1]
    assert.equals("lg", h.name)
    assert.same({ close = "success", title = "Git", float = { width = 0.5 } }, h.rerun)
    -- It came back hidden; shown again it has the title and size it was started with.
    jobs.settle()
    assert.truthy(terminal.open({ name = "lg" }))
    local cfg = vim.api.nvim_win_get_config(vim.fn.win_findbuf(h.bufnr)[1])
    assert.truthy(vim.inspect(cfg.title):find("Git", 1, true))
    assert.is_true(cfg.width < vim.o.columns * 0.6)
  end)

  it("a restored direct run ends the way its saved close says", function()
    boot({ sessions = { commands = "run" } })
    local session = dir .. "/work.vim"
    local sidecar = require("terminal.sessions").sidecar_path(session)
    local f = assert(io.open(sidecar, "w"))
    f:write(vim.json.encode({
      version = 1,
      terminals = {
        { name = "once", layout = "float", cmd = jobs.exit_with(0), close = "always" },
      },
    }))
    f:close()
    fire("SessionsLoadPost", session)
    assert.equals(1, #terminal.list(true), "the command was started")
    -- close = "always": the terminal goes when the job ends (without it, "never" keeps it).
    assert.is_true(jobs.wait(function()
      return #terminal.list(true) == 0
    end))
  end)

  it("a sidecar border nvim_open_win would refuse loses the border, not the terminal", function()
    boot({ sessions = { commands = "run" } })
    local session = dir .. "/work.vim"
    local sidecar = require("terminal.sessions").sidecar_path(session)
    -- Each of these passed a count-only check and made nvim_open_win fail the whole restore.
    local bad = {
      { 1 },
      { "ab" },
      { vim.NIL },
      { {} },
      { { "a", "b", "c" } },
      { "", "a" },
      { "\27" },
      { "\229\173\151" }, -- a two-cell character
    }
    local terminals = {}
    for i, border in ipairs(bad) do
      terminals[i] = {
        name = "t" .. i,
        layout = "float",
        cmd = jobs.sleeper(),
        float = { border = border, width = 0.5 },
      }
    end
    local f = assert(io.open(sidecar, "w"))
    f:write(vim.json.encode({ version = 1, terminals = terminals }))
    f:close()
    for i, def in ipairs(require("terminal.sessions").read(session)) do
      assert.same({ width = 0.5 }, def.float, vim.inspect(bad[i]))
    end
    fire("SessionsLoadPost", session)
    local names = terminal.names()
    table.sort(names)
    local want = {}
    for i = 1, #bad do
      want[i] = "t" .. i
    end
    table.sort(want)
    assert.same(want, names)
  end)

  it("run refuses a session option that is not a boolean, and starts nothing", function()
    boot()
    local ok, err = terminal.run(jobs.sleeper(), { name = "lg", direct = true, session = "no" })
    assert.is_false(ok)
    assert.truthy(err:find("session must be a boolean", 1, true))
    assert.equals(0, #terminal.list(true))
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
