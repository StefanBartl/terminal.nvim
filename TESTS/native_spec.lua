---@diagnostic disable: need-check-nil, undefined-field
-- need-check-nil and undefined-field are off for the whole file: a nil in a spec body fails the next assertion anyway, and luassert's assert.* and the stubbed vim.* fields are not in the annotations.
-- TESTS/native_spec.lua -- terminal.backends.native: the backend contract on real windows/jobs.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local jobs = dofile(here .. "/support/jobs.lua")

local registry_mod = require("terminal.core.registry")
local native = require("terminal.backends.native")

describe("terminal.backends.native", function()
  local registry, backend

  before_each(function()
    registry = registry_mod.new()
    backend = native.new(registry)
  end)

  after_each(function()
    jobs.cleanup(backend, registry)
  end)

  --- Neovim's error codes are not translated; the words around them are.
  ---@param reason any The reason a call gave
  ---@param fragment string Neovim's error code, e.g. "E565", or a phrase of the plugin's own
  local function mentions(reason, fragment)
    local text = tostring(reason)
    assert.is_true(
      text:find(fragment, 1, true) ~= nil,
      ("expected %s in: %s"):format(fragment, text)
    )
  end

  ---@param over? table
  ---@return Terminal.SpawnSpec
  local function spec(over)
    return vim.tbl_extend("force", {
      name = "t1",
      root = "/proj",
      cwd = vim.fn.getcwd(),
      cmd = jobs.sleeper(),
      layout = "float",
      float = { width = 0.5, height = 0.5, border = "rounded", title = true, title_pos = "center" },
      split = { size = 0.3 },
      start_insert = false,
      on_exit = "close",
    }, over or {})
  end

  it("is always available", function()
    assert.is_true((backend.available({})))
  end)

  describe("spawn", function()
    it("starts a job in a float and registers the handle", function()
      local h, err = backend.spawn(spec())
      assert.is_nil(err)
      assert.equals("/proj::t1", h.id)
      assert.equals("native", h.backend)
      assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
      assert.equals("terminal", vim.bo[h.bufnr].buftype)
      assert.is_true(h.job > 0)
      local win = vim.fn.win_findbuf(h.bufnr)[1]
      assert.equals("editor", vim.api.nvim_win_get_config(win).relative)
      assert.equals(h, registry:get("/proj::t1"))
    end)

    it("shows the name in the title of a bordered float", function()
      local h = backend.spawn(spec())
      local win = vim.fn.win_findbuf(h.bufnr)[1]
      local title = vim.api.nvim_win_get_config(win).title
      assert.truthy(vim.inspect(title):find("t1", 1, true))
    end)

    it("opens a split below, a vsplit to the right and a tab", function()
      local wins_before = #vim.api.nvim_list_wins()
      local hs = backend.spawn(spec({ name = "s", layout = "split" }))
      local ws = vim.fn.win_findbuf(hs.bufnr)[1]
      assert.equals("", vim.api.nvim_win_get_config(ws).relative)
      assert.equals(wins_before + 1, #vim.api.nvim_list_wins())

      local hv = backend.spawn(spec({ name = "v", layout = "vsplit" }))
      local wv = vim.fn.win_findbuf(hv.bufnr)[1]
      assert.equals("", vim.api.nvim_win_get_config(wv).relative)

      local tabs_before = #vim.api.nvim_list_tabpages()
      local ht = backend.spawn(spec({ name = "t", layout = "tab" }))
      assert.equals(tabs_before + 1, #vim.api.nvim_list_tabpages())
      assert.equals(ht.bufnr, vim.api.nvim_get_current_buf())
    end)

    it("fails cleanly for a command that cannot run, leaving no window or buffer behind", function()
      local wins, bufs = #vim.api.nvim_list_wins(), #vim.api.nvim_list_bufs()
      local h, err = backend.spawn(spec({ cmd = { "definitely-not-a-program-xyz" } }))
      assert.is_nil(h)
      assert.truthy(err)
      assert.equals(wins, #vim.api.nvim_list_wins())
      assert.equals(bufs, #vim.api.nvim_list_bufs())
      assert.equals(0, registry:count())
    end)

    it("fails cleanly for an unknown layout", function()
      local h, err = backend.spawn(spec({ layout = "sideways" }))
      assert.is_nil(h)
      assert.truthy(err:find("layout", 1, true))
      assert.equals(0, registry:count())
    end)
  end)

  describe("visibility", function()
    it("hide keeps the buffer and the job, show opens a new window for the same buffer", function()
      local h = backend.spawn(spec())
      assert.is_true(backend.visible(h))
      jobs.settle()
      assert.is_true(backend.hide(h))
      assert.is_false(backend.visible(h))
      assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
      assert.equals(-1, vim.fn.jobwait({ h.job }, 0)[1])

      jobs.settle()
      assert.is_true(backend.show(h, spec({ layout = "split" })))
      assert.is_true(backend.visible(h))
      assert.equals("split", h.layout)
    end)

    it("focus moves to the terminal's window and reports focused()", function()
      local h = backend.spawn(spec())
      vim.cmd("wincmd p")
      assert.is_false(backend.focused(h))
      assert.is_true(backend.focus(h))
      assert.is_true(backend.focused(h))
    end)

    it("focus on a hidden terminal says so", function()
      local h = backend.spawn(spec())
      jobs.settle()
      backend.hide(h)
      local ok, err = backend.focus(h)
      assert.is_false(ok)
      assert.truthy(err:find("hidden", 1, true))
    end)

    it("hiding the only window of the editor does not quit it", function()
      local h = backend.spawn(spec({ layout = "tab" }))
      vim.cmd("tabclose 1")
      -- one tab left (the terminal's); hide must not close the editor's last window
      jobs.settle()
      assert.is_true(backend.hide(h))
      assert.equals(1, #vim.api.nvim_list_wins())
    end)

    describe("the terminal is the only normal window of the editor", function()
      local file, file_buf, float
      local extra = {} -- listed buffers a spec made; wiped in after_each

      before_each(function()
        file = vim.fn.tempname()
        vim.fn.writefile({ "the file you were editing" }, file)
        vim.cmd("silent! only")
        vim.cmd("silent! tabonly")
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        file_buf = vim.api.nvim_get_current_buf()
      end)

      after_each(function()
        if float and vim.api.nvim_win_is_valid(float) then
          vim.api.nvim_win_close(float, true)
        end
        float = nil
        vim.cmd("silent! tabonly")
        pcall(function()
          vim.cmd("bwipeout! " .. file_buf)
        end)
        for _, b in ipairs(extra) do
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
        extra = {}
        vim.fn.delete(file)
      end)

      --- A listed buffer of its own; it is wiped after the spec.
      ---@return integer
      local function listed_buffer()
        local b = vim.api.nvim_create_buf(true, false)
        extra[#extra + 1] = b
        return b
      end

      --- Show `bufnr` in `win` and then `back` again: `bufnr` is `win`'s alternate buffer after it.
      ---@param win integer
      ---@param bufnr integer
      ---@param back integer
      local function make_alternate(win, bufnr, back)
        vim.api.nvim_win_call(win, function()
          vim.cmd("buffer " .. bufnr)
          vim.cmd("buffer " .. back)
        end)
      end

      --- Use `bufnr` the way an editor does -- enter it in a window -- without changing the
      --- alternate buffer of a normal window: a float, closed again at once.
      ---@param bufnr integer
      local function use_in_float(bufnr)
        local w = vim.api.nvim_open_win(bufnr, true, {
          relative = "editor",
          row = 1,
          col = 1,
          width = 10,
          height = 3,
        })
        vim.api.nvim_win_close(w, true)
      end

      --- The alternate buffer of `win` (`#` evaluated in it), -1 or a gone buffer when it has none.
      ---@param win integer
      ---@return integer
      local function alternate_of(win)
        return vim.api.nvim_win_call(win, function()
          return vim.fn.bufnr("#")
        end)
      end

      ---@param bufnr integer
      ---@return integer seconds
      local function last_used(bufnr)
        return vim.fn.getbufinfo(bufnr)[1].lastused
      end

      --- The terminal alone in its tab, the file's tab closed.
      local function terminal_alone()
        local h = backend.spawn(spec({ layout = "tab" }))
        vim.cmd("1tabclose")
        assert.equals(1, #vim.api.nvim_list_tabpages())
        jobs.settle()
        return h
      end

      it("hide shows the buffer you were editing, not a new empty one", function()
        local h = terminal_alone()
        local win = vim.fn.win_findbuf(h.bufnr)[1]
        assert.is_true(backend.hide(h))
        assert.equals(file_buf, vim.api.nvim_win_get_buf(win))
      end)

      it("hide shows the alternate buffer, not the most recently used one", function()
        local h = terminal_alone()
        local win = vim.fn.win_findbuf(h.bufnr)[1]
        local alt, recent = listed_buffer(), listed_buffer()
        make_alternate(win, alt, h.bufnr)
        -- 'lastused' counts whole seconds: let `recent` be strictly newer than `alt`
        vim.wait(1100)
        use_in_float(recent)
        -- the scenario has to be the one the title names, or the case proves nothing
        assert.equals(alt, alternate_of(win))
        assert.is_true(last_used(recent) > last_used(alt))
        assert.is_true(backend.hide(h))
        assert.equals(alt, vim.api.nvim_win_get_buf(win))
      end)

      it("hide shows the most recently used listed buffer when there is no alternate", function()
        local h = terminal_alone()
        local win = vim.fn.win_findbuf(h.bufnr)[1]
        local recent = listed_buffer()
        vim.wait(1100) -- as above: `recent` is strictly newer than the file buffer
        use_in_float(recent)
        local alt = alternate_of(win)
        assert.is_false(
          alt > 0 and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted,
          "the terminal's window has no alternate buffer to fall back on"
        )
        assert.is_true(last_used(recent) > last_used(file_buf))
        assert.is_true(backend.hide(h))
        assert.equals(recent, vim.api.nvim_win_get_buf(win))
      end)

      it("hide shows the terminal window's own alternate buffer, not the current's", function()
        local h = terminal_alone()
        local win = vim.fn.win_findbuf(h.bufnr)[1]
        local own_alt, other, other_alt = listed_buffer(), listed_buffer(), listed_buffer()
        make_alternate(win, own_alt, h.bufnr)
        -- A float is the current window, with an alternate buffer of its own.
        float = vim.api.nvim_open_win(other, true, {
          relative = "editor",
          row = 1,
          col = 1,
          width = 10,
          height = 3,
        })
        make_alternate(float, other_alt, other)
        assert.equals(float, vim.api.nvim_get_current_win())
        assert.equals(other_alt, vim.fn.bufnr("#"))
        assert.equals(own_alt, alternate_of(win))
        assert.is_true(backend.hide(h))
        assert.equals(own_alt, vim.api.nvim_win_get_buf(win))
        assert.equals(float, vim.api.nvim_get_current_win(), "the float is left as it was")
      end)

      it("hide closes a terminal tab together with its tab while other tabs are open", function()
        local file_win = vim.api.nvim_get_current_win()
        local h = backend.spawn(spec({ layout = "tab" }))
        assert.equals(2, #vim.api.nvim_list_tabpages())
        jobs.settle()
        assert.is_true(backend.hide(h))
        assert.equals(
          1,
          #vim.api.nvim_list_tabpages(),
          "the tab goes with its terminal window; it is not turned into another buffer"
        )
        assert.same({ file_win }, vim.api.nvim_list_wins())
        assert.equals(file_buf, vim.api.nvim_win_get_buf(file_win))
        assert.is_false(backend.visible(h))
        assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
        assert.equals(-1, vim.fn.jobwait({ h.job }, 0)[1], "hide keeps the job")
      end)

      it("an unrelated float does not count as a window to fall back on", function()
        local h = terminal_alone()
        float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
          relative = "editor",
          row = 1,
          col = 1,
          width = 10,
          height = 3,
        })
        -- closing the terminal's window used to raise E444 here and leave the handle orphaned
        local ok, res = pcall(backend.hide, h)
        assert.is_true(ok, tostring(res))
        assert.is_true(res)
        assert.is_false(backend.visible(h))
        assert.is_true(vim.api.nvim_win_is_valid(float))
        local closed, cres = pcall(backend.close, h)
        assert.is_true(closed, tostring(cres))
        assert.equals(0, registry:count())
        assert.is_false(vim.api.nvim_buf_is_valid(h.bufnr))
      end)

      -- 'winfixbuf' (Neovim 0.10+) forbids showing another buffer in the window, so the fallback
      -- of the last window is refused. Registered only where the option exists.
      if vim.fn.exists("+winfixbuf") == 1 then
        it("hide answers false and raises nothing when 'winfixbuf' pins the terminal", function()
          local h = terminal_alone()
          local win = vim.fn.win_findbuf(h.bufnr)[1]
          vim.wo[win].winfixbuf = true
          local ok, hidden, err = pcall(backend.hide, h)
          assert.is_true(ok, tostring(hidden))
          assert.is_false(hidden)
          mentions(err, "E1513")
          assert.is_true(backend.visible(h))
          assert.equals(h, registry:get(h.id))
        end)

        it("a refused hide leaves no empty buffer behind", function()
          local h = terminal_alone()
          local win = vim.fn.win_findbuf(h.bufnr)[1]
          -- No other listed buffer: the fallback has to make an empty one, then fails to show it.
          local unlisted = {}
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if b ~= h.bufnr and vim.bo[b].buflisted then
              vim.bo[b].buflisted = false
              unlisted[#unlisted + 1] = b
            end
          end
          vim.wo[win].winfixbuf = true
          local before = #vim.api.nvim_list_bufs()
          local ok, hidden = pcall(backend.hide, h)
          local after = #vim.api.nvim_list_bufs()
          for _, b in ipairs(unlisted) do
            if vim.api.nvim_buf_is_valid(b) then
              vim.bo[b].buflisted = true
            end
          end
          assert.is_true(ok, tostring(hidden))
          assert.is_false(hidden)
          assert.equals(before, after)
        end)

        it("close answers false, keeps the terminal registered and can be retried", function()
          local h = terminal_alone()
          local win = vim.fn.win_findbuf(h.bufnr)[1]
          vim.wo[win].winfixbuf = true
          local ok, closed, err = pcall(backend.close, h)
          assert.is_true(ok, tostring(closed))
          assert.is_false(closed)
          mentions(err, "E1513")
          -- Not orphaned and not half-done: still registered, buffer and window still there,
          -- and the job still running (Neovim is asked first, nothing is stopped on a refusal).
          assert.equals(h, registry:get(h.id))
          assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
          assert.is_true(backend.visible(h))
          assert.is_falsy(h.exited)
          assert.equals(-1, vim.fn.jobwait({ h.job }, 0)[1], "the command was not killed")
          assert.is_falsy(h.disposed, "not removed, so not marked as removed")
          -- Once the obstacle is gone the same call finishes the job.
          vim.wo[win].winfixbuf = false
          assert.is_true(backend.close(h))
          assert.equals(0, registry:count())
          assert.is_false(vim.api.nvim_buf_is_valid(h.bufnr))
          assert.equals(file_buf, vim.api.nvim_win_get_buf(win))
        end)

        -- The question "would a window have to show another buffer?" is answered before anything
        -- is stopped, so it has to know WHICH window ends up the last one: closing one makes the
        -- next one the last. These cases pin that arithmetic (two windows, two tabs).
        local layouts = {
          {
            name = "two windows of one tab",
            make = function(h)
              vim.api.nvim_win_call(vim.fn.win_findbuf(h.bufnr)[1], function()
                vim.cmd("split")
              end)
            end,
          },
          {
            name = "two tabs, the terminal alone in each",
            make = function(h)
              vim.cmd("tabnew")
              vim.api.nvim_win_set_buf(0, h.bufnr)
            end,
          },
        }
        for _, layout in ipairs(layouts) do
          it(("close finds the window that is replaced: %s"):format(layout.name), function()
            local h = terminal_alone()
            layout.make(h)
            local wins = vim.fn.win_findbuf(h.bufnr)
            assert.equals(2, #wins)
            jobs.settle()
            -- the last window taken is the one that has to show another buffer
            vim.wo[wins[#wins]].winfixbuf = true
            local ok, closed, err = pcall(backend.close, h)
            assert.is_true(ok, tostring(closed))
            assert.is_false(closed)
            mentions(err, "E1513")
            assert.equals(-1, vim.fn.jobwait({ h.job }, 0)[1], "the command was not killed")
            assert.equals(2, #vim.fn.win_findbuf(h.bufnr), "no window was closed")
            -- on any other window 'winfixbuf' is no obstacle: it is simply closed
            vim.wo[wins[#wins]].winfixbuf = false
            vim.wo[wins[1]].winfixbuf = true
            assert.is_true(backend.close(h))
            assert.equals(0, registry:count())
          end)
        end
      end
    end)

    -- Neovim refuses to change windows under textlock -- inside an `<expr>` mapping, say -- and in
    -- the command-line window. The two are answered, not raised, and nothing is half-removed.
    describe("Neovim refuses to close the window", function()
      --- Run `fn` under textlock: an `<expr>` mapping is evaluated with it set.
      ---@param fn fun()
      local function under_textlock(fn)
        local lhs = "<Plug>(terminal-spec-textlock)"
        local failure
        vim.keymap.set("n", lhs, function()
          local ok, err = pcall(fn)
          if not ok then
            failure = err
          end
          return ""
        end, { expr = true })
        vim.api.nvim_feedkeys(vim.keycode(lhs), "x", false)
        pcall(vim.keymap.del, "n", lhs)
        if failure then
          error(failure, 0)
        end
      end

      for _, layout in ipairs({ "float", "vsplit" }) do
        it(("hide answers false for the %s window"):format(layout), function()
          local h = backend.spawn(spec({ layout = layout }))
          jobs.settle()
          local ok, hidden, err
          under_textlock(function()
            ok, hidden, err = pcall(backend.hide, h)
          end)
          assert.is_true(ok, tostring(hidden))
          assert.is_false(hidden)
          mentions(err, "E565")
          assert.is_true(backend.visible(h))
          assert.is_true(backend.hide(h), "it works again once the lock is gone")
          assert.is_false(backend.visible(h))
        end)

        it(("close keeps the %s terminal, answers false"):format(layout), function()
          local h = backend.spawn(spec({ layout = layout }))
          jobs.settle()
          local ok, closed, err
          under_textlock(function()
            ok, closed, err = pcall(backend.close, h)
          end)
          assert.is_true(ok, tostring(closed))
          assert.is_false(closed)
          mentions(err, "E565")
          assert.equals(h, registry:get(h.id))
          assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
          assert.is_true(backend.visible(h))
          assert.is_falsy(h.exited, "the job was not stopped")
          assert.equals(-1, vim.fn.jobwait({ h.job }, 0)[1], "the command was not killed")
          assert.is_falsy(h.disposed, "not removed, so not marked as removed")
          assert.is_true(backend.close(h))
          assert.equals(0, registry:count())
          assert.is_false(vim.api.nvim_buf_is_valid(h.bufnr))
        end)
      end

      -- No window to fail on here: the buffer is what Neovim refuses to delete.
      it("close keeps a hidden terminal registered when its buffer cannot be deleted", function()
        local h = backend.spawn(spec())
        jobs.settle()
        assert.is_true(backend.hide(h))
        assert.is_false(backend.visible(h))
        jobs.settle()
        local ok, closed, err
        local buffers = #vim.api.nvim_list_bufs()
        under_textlock(function()
          ok, closed, err = pcall(backend.close, h)
          -- asked again and again: the buffer the question is asked with is kept and reused
          pcall(backend.close, h)
          pcall(backend.close, h)
        end)
        assert.is_true(ok, tostring(closed))
        assert.is_false(closed)
        mentions(err, "E565")
        mentions(err, "cannot delete the buffer")
        assert.is_true(
          #vim.api.nvim_list_bufs() <= buffers + 1,
          "three refusals leave at most one scratch buffer behind"
        )
        -- Not left behind unknown to the registry, and not marked as removed.
        assert.equals(h, registry:get(h.id))
        assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
        assert.is_falsy(h.disposed, "not removed, so not marked as removed")
        -- And nothing was stopped on the way: the answer "false" means the command still runs.
        assert.is_falsy(h.exited, "the job was not stopped")
        assert.equals(-1, vim.fn.jobwait({ h.job }, 0)[1], "the command was not killed")
        jobs.settle()
        assert.is_true(backend.close(h), "it works again once the lock is gone")
        assert.equals(0, registry:count())
        assert.is_false(vim.api.nvim_buf_is_valid(h.bufnr))
      end)

      -- The question is asked with a scratch buffer made and deleted again: no autocommand of the
      -- user may see it (a BufNew handler that fails for a scratch buffer used to read as a refusal
      -- and locked hide / close / the cleanup of an exited terminal for good).
      it("hide and close work although a BufNew autocommand of the user fails", function()
        local h = backend.spawn(spec({ layout = "vsplit" }))
        jobs.settle()
        local id = vim.api.nvim_create_autocmd("BufNew", {
          callback = function()
            error("a plugin with a bug")
          end,
        })
        local hidden = { pcall(backend.hide, h) }
        local closed = { pcall(backend.close, h) }
        pcall(vim.api.nvim_del_autocmd, id)
        assert.is_true(hidden[1] and hidden[2] == true, tostring(hidden[2]) .. tostring(hidden[3]))
        assert.is_true(closed[1] and closed[2] == true, tostring(closed[2]) .. tostring(closed[3]))
        assert.equals(0, registry:count())
      end)

      -- The command-line window refuses window changes and buffer deletion like a text lock does.
      -- Entering it takes a normal-mode `q:`, which this editor's runner cannot do (it ends the
      -- run), so a child Neovim does it and writes what hide / close answered inside it.
      it("hide and close answer false inside the command-line window", function()
        local this_file =
          vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
        local root = this_file:match("^(.*)/TESTS/[^/]*$")
        -- where the live scripts look for lib.nvim: the variable the runner was given, else the
        -- directory next to this plugin
        local lib = vim.env.LIB_NVIM_DIR or (root and (root .. "/../lib.nvim"))
        assert.is_truthy(root and lib, "the plugin and lib.nvim are found")
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        local script, out =
          vim.fs.normalize(dir .. "/child.lua"), vim.fs.normalize(dir .. "/out.json")
        vim.fn.writefile({
          ("vim.opt.rtp:prepend(%q); vim.opt.rtp:append(%q)"):format(root, lib),
          'local registry = require("terminal.core.registry").new()',
          'local backend = require("terminal.backends.native").new(registry)',
          ("local h = backend.spawn({ name = 'a', root = '/proj', cwd = %q, cmd = %s, layout = 'vsplit',"):format(
            vim.fs.normalize(vim.fn.getcwd()),
            vim.inspect(jobs.sleeper())
          ),
          "  float = {}, split = { size = 0.3 }, start_insert = false, on_exit = 'close' })",
          "vim.wait(600)",
          "local result = {}",
          'vim.api.nvim_create_autocmd("CmdwinEnter", { once = true, callback = function()',
          "  result.hide = { pcall(backend.hide, h) }",
          "  result.close = { pcall(backend.close, h) }",
          "end })",
          'pcall(function() vim.cmd("normal! q:") end)',
          "result.running = vim.fn.jobwait({ h.job }, 0)[1] == -1",
          "result.registered = registry:get(h.id) == h",
          ("local f = assert(io.open(%q, 'w')); f:write(vim.json.encode(result)); f:close()"):format(
            out
          ),
          "vim.cmd('qa!')",
        }, script)
        local res = vim
          .system({ vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", script })
          :wait(60000)
        local text = vim.uv.fs_stat(out) and table.concat(vim.fn.readfile(out), "\n") or ""
        vim.fn.delete(dir, "rf")
        -- a plain assert: nothing below can be read without the child's answer
        assert(
          text ~= "",
          ("the child wrote no answer (exit %s, root %s, lib %s): %s %s"):format(
            tostring(res.code),
            tostring(root),
            tostring(lib),
            tostring(res.stdout),
            tostring(res.stderr)
          )
        )
        local result = vim.json.decode(text)
        assert.is_true(result.hide[1] and result.hide[2] == false, vim.inspect(result.hide))
        mentions(result.hide[3], "E11")
        assert.is_true(result.close[1] and result.close[2] == false, vim.inspect(result.close))
        mentions(result.close[3], "E11")
        assert.is_true(result.running, "the command was not killed")
        assert.is_true(result.registered)
      end)

      -- The last window cannot be closed, so a buffer is made to show in it; under the lock that
      -- buffer could not be taken away again and stayed behind, listed.
      it("hide of the terminal in the last window leaves no empty buffer behind", function()
        local h = backend.spawn(spec({ layout = "tab" }))
        vim.cmd("1tabclose")
        assert.equals(1, #vim.api.nvim_list_tabpages())
        jobs.settle()
        -- No other listed buffer: showing something else would need a new empty one.
        local unlisted = {}
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if b ~= h.bufnr and vim.bo[b].buflisted then
            vim.bo[b].buflisted = false
            unlisted[#unlisted + 1] = b
          end
        end
        -- Listed buffers: the scratch buffer the backend asks the lock with is unlisted, invisible
        -- and reused by the next question, so it does not count as something left behind.
        local function listed_count()
          return #vim.fn.getbufinfo({ buflisted = 1 })
        end
        local before = listed_count()
        local ok, hidden, err
        under_textlock(function()
          ok, hidden, err = pcall(backend.hide, h)
        end)
        local after = listed_count()
        for _, b in ipairs(unlisted) do
          if vim.api.nvim_buf_is_valid(b) then
            vim.bo[b].buflisted = true
          end
        end
        assert.is_true(ok, tostring(hidden))
        assert.is_false(hidden)
        mentions(err, "E565")
        assert.equals(before, after, "no listed buffer was made for the refused hide")
        assert.is_true(backend.visible(h))
      end)
    end)

    -- Closing the windows of a RUNNING terminal and stopping its job right after killed Neovim on
    -- Windows (0xC0000005) when the terminal was shown in more than one window. The runner reports
    -- a crash as a failure, so this case is the guard for the order of the two.
    describe("a running terminal shown in two windows", function()
      for _, how in ipairs({ "split", "vsplit" }) do
        it(("close ends the job and removes the terminal (%s)"):format(how), function()
          local h = backend.spawn(spec({ layout = "split" }))
          jobs.settle()
          local win = vim.fn.win_findbuf(h.bufnr)[1]
          vim.api.nvim_win_call(win, function()
            vim.cmd(how)
          end)
          assert.equals(2, #vim.fn.win_findbuf(h.bufnr))
          jobs.settle()
          local pid = h.job and vim.fn.jobpid(h.job)
          local ok, closed = pcall(backend.close, h)
          assert.is_true(ok, tostring(closed))
          assert.is_true(closed)
          assert.is_false(vim.api.nvim_buf_is_valid(h.bufnr))
          assert.equals(0, registry:count())
          assert.is_false(jobs.process_alive(pid), "the command is gone")
        end)
      end
    end)

    -- Closing a terminal's window resizes its neighbours; stopping a neighbour's job within a few
    -- milliseconds of that killed Neovim on Windows (0xC0000005, every time: close(a); close(b) on
    -- two running splits). No jobs.settle() between the two calls on purpose.
    describe("running terminals next to each other", function()
      for _, layout in ipairs({ "split", "vsplit" }) do
        it(("close(a); close(b) back to back (%s)"):format(layout), function()
          local a = backend.spawn(spec({ name = "a", layout = layout }))
          jobs.settle()
          local b = backend.spawn(spec({ name = "b", layout = layout }))
          jobs.settle()
          local pids = { vim.fn.jobpid(a.job), vim.fn.jobpid(b.job) }
          local ok_a, closed_a = pcall(backend.close, a)
          local ok_b, closed_b = pcall(backend.close, b)
          assert.is_true(ok_a and closed_a == true, tostring(closed_a))
          assert.is_true(ok_b and closed_b == true, tostring(closed_b))
          assert.equals(0, registry:count())
          for _, pid in ipairs(pids) do
            assert.is_false(jobs.process_alive(pid), "the command is gone")
          end
        end)
      end

      it("hide(a); close(b) back to back", function()
        local a = backend.spawn(spec({ name = "a", layout = "split" }))
        jobs.settle()
        local b = backend.spawn(spec({ name = "b", layout = "split" }))
        jobs.settle()
        assert.is_true(backend.hide(a))
        local ok, closed = pcall(backend.close, b)
        assert.is_true(ok and closed == true, tostring(closed))
        assert.is_true(backend.close(a))
        assert.equals(0, registry:count())
      end)
    end)
  end)

  describe("send", function()
    it("writes to the job's channel", function()
      local h = backend.spawn(spec())
      local ok, err
      local sent = jobs.record_sends(function()
        ok, err = backend.send(h, "typed text\n")
      end)
      assert.is_true(ok, err)
      assert.same({ { job = h.job, text = "typed text\n" } }, sent)
    end)

    it("refuses an exited terminal and a closed one", function()
      local h = backend.spawn(spec({ cmd = jobs.exit_with(0), on_exit = "keep" }))
      assert.is_true(jobs.wait(function()
        return h.exited == true
      end))
      local ok, err = backend.send(h, "x")
      assert.is_false(ok)
      assert.truthy(err:find("not running", 1, true))
    end)
  end)

  describe("exit handling", function()
    it("on_exit = close removes the terminal, its window and its buffer", function()
      local seen
      local h = backend.spawn(spec({
        cmd = jobs.exit_with(0),
        on_exit = "close",
        on_exit_cb = function(code)
          seen = code
        end,
      }))
      local bufnr = h.bufnr
      assert.is_true(jobs.wait(function()
        return seen ~= nil and registry:count() == 0
      end))
      assert.equals(0, seen)
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    end)

    it("on_exit = keep leaves the buffer and records the exit code", function()
      local h = backend.spawn(spec({ cmd = jobs.exit_with(3), on_exit = "keep" }))
      assert.is_true(jobs.wait(function()
        return h.exited == true
      end))
      assert.equals(3, h.exit_code)
      assert.is_true(vim.api.nvim_buf_is_valid(h.bufnr))
      assert.equals(1, registry:count())
    end)

    it("on_exit = close_on_success keeps a failed terminal and removes a successful one", function()
      -- One after the other: two jobs ending together can crash Neovim on Windows (see jobs.settle).
      local failed =
        backend.spawn(spec({ name = "bad", cmd = jobs.exit_with(2), on_exit = "close_on_success" }))
      assert.is_true(jobs.wait(function()
        return failed.exited == true
      end))
      jobs.settle()
      local good = backend.spawn(
        spec({ name = "good", cmd = jobs.exit_with(0), on_exit = "close_on_success" })
      )
      assert.is_true(jobs.wait(function()
        return registry:get(good.id) == nil
      end))
      assert.is_true(vim.api.nvim_buf_is_valid(failed.bufnr))
      assert.is_not_nil(registry:get(failed.id))
    end)
  end)

  describe("replacing a terminal under the same id", function()
    it("a late exit handler of the old terminal does not take the new one with it", function()
      local old = backend.spawn(spec({ name = "same", on_exit = "close" }))
      jobs.settle()
      -- Not closed first: the new terminal takes the old one's place in the registry while the
      -- old job is still running, so the old exit handler really comes late.
      local new = backend.spawn(spec({ name = "same", on_exit = "close" }))
      assert.equals(old.id, new.id)
      assert.equals(new, registry:get(new.id))
      jobs.settle()
      local old_bufnr = old.bufnr
      vim.fn.jobstop(old.job)
      -- The old terminal's `on_exit = "close"` removes the OLD terminal (its buffer goes), and
      -- that must not take the registry entry of the new one with it.
      assert.is_true(
        jobs.wait(function()
          return not vim.api.nvim_buf_is_valid(old_bufnr)
        end),
        "the old exit handler did not run"
      )
      assert.is_true(old.exited)
      assert.equals(new, registry:get(new.id))
      assert.is_true(vim.api.nvim_buf_is_valid(new.bufnr))
      assert.equals(-1, vim.fn.jobwait({ new.job }, 0)[1], "the new job still runs")
    end)
  end)

  describe("close and list", function()
    it("close stops the job and removes the terminal; closing again is harmless", function()
      local h = backend.spawn(spec())
      local bufnr = h.bufnr
      local pid = vim.fn.jobpid(h.job)
      jobs.settle()
      assert.is_true(jobs.process_alive(pid), "the command runs before it is closed")
      assert.is_true(backend.close(h))
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
      assert.equals(0, registry:count())
      assert.is_true(backend.close(h))
      -- Asked of the operating system: the channel of a deleted terminal answers "gone" whether
      -- or not its process lives.
      assert.is_false(jobs.process_alive(pid), "the command is stopped, not just forgotten")
    end)

    -- Inside `TermClose` the job is reaped, but its `on_exit` -- the only thing that sets
    -- `exited` -- is queued behind the handler: the process has to be asked, not the flag.
    it("close from a TermClose handler returns at once and says nothing", function()
      local h = backend.spawn(spec({ cmd = jobs.exit_with(0), on_exit = "keep" }))
      local bufnr = h.bufnr
      local seen = {}
      vim.api.nvim_create_autocmd("TermClose", {
        buffer = bufnr,
        once = true,
        callback = function()
          seen.exited = h.exited
          local started = vim.uv.hrtime()
          seen.ok, seen.closed = pcall(backend.close, h)
          seen.took = (vim.uv.hrtime() - started) / 1e6
        end,
      })
      local messages = jobs.capture_notify(function()
        assert.is_true(
          jobs.wait(function()
            return seen.took ~= nil
          end),
          "TermClose did not fire"
        )
        vim.wait(100) -- a warning would be scheduled: let it come
      end)
      assert.is_falsy(seen.exited, "the scenario: the exit flag is not set yet inside TermClose")
      assert.is_true(seen.ok, tostring(seen.closed))
      assert.is_true(seen.closed)
      assert.is_true(seen.took < 500, ("close blocked %d ms"):format(seen.took))
      assert.same({}, messages)
      assert.equals(0, registry:count())
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    end)

    it("list returns live handles and forgets a buffer wiped behind its back", function()
      local a = backend.spawn(spec({ name = "a" }))
      local b = backend.spawn(spec({ name = "b" }))
      assert.equals(2, #backend.list())
      jobs.settle()
      vim.api.nvim_buf_delete(a.bufnr, { force = true })
      local names = vim.tbl_map(function(h)
        return h.name
      end, backend.list())
      assert.same({ "b" }, names)
      assert.is_nil(registry:get(a.id))
      assert.is_not_nil(registry:get(b.id))
    end)

    -- Checked on the registry itself, never through list(): list() prunes a handle whose buffer
    -- is invalid too, so it would hide a missing BufWipeout handler.
    it("forgets a terminal whose buffer is wiped behind its back, without anyone asking", function()
      local a = backend.spawn(spec({ name = "a" }))
      local b = backend.spawn(spec({ name = "b" }))
      jobs.settle()
      vim.cmd("bwipeout! " .. a.bufnr)
      assert.is_nil(registry:get(a.id))
      assert.equals(b, registry:get(b.id))
      assert.equals(1, registry:count())
    end)

    it("a terminal replaced under the same id survives the wipe of the old one's buffer", function()
      local old = backend.spawn(spec({ name = "same" }))
      jobs.settle()
      -- Not closed first: the new terminal takes the old one's place in the registry while the
      -- old job and its buffer live on.
      local new = backend.spawn(spec({ name = "same" }))
      assert.equals(old.id, new.id)
      assert.equals(new, registry:get(new.id))
      jobs.settle()
      vim.cmd("bwipeout! " .. old.bufnr)
      -- the old job's exit handler runs late too: neither may take the new terminal along
      vim.wait(300)
      assert.equals(new, registry:get(new.id))
      assert.is_true(vim.api.nvim_buf_is_valid(new.bufnr))
    end)

    it("close of a healthy job returns once it reported its exit, and says nothing", function()
      local h = backend.spawn(spec())
      jobs.settle()
      local closed, exited_on_return
      local messages = jobs.capture_notify(function()
        closed = backend.close(h)
        exited_on_return = h.exited
        vim.wait(100) -- a warning would be scheduled: let it come
      end)
      assert.is_true(closed)
      assert.is_true(
        exited_on_return,
        "close waits for the exit flag, it does not return before it"
      )
      assert.same({}, messages)
      assert.equals(0, registry:count())
    end)

    it("close warns when the job does not report its exit in time, and still removes it", function()
      local h = backend.spawn(spec())
      jobs.settle()
      local real_wait = vim.wait
      local waits = {}
      -- Test double: the first wait runs out, as it does for a job that survives its stop; the
      -- real wait is back before the message is awaited (restored in every case below).
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.wait = function(ms, pred, interval)
        if #waits == 0 then
          waits[1] = { ms = ms, pred = pred, exited_at_call = pred and pred() }
          return false, -1
        end
        return real_wait(ms, pred, interval)
      end
      local ok, closed
      local messages = jobs.capture_notify(function(shown)
        ok, closed = pcall(backend.close, h)
        vim.wait = real_wait
        jobs.wait(function()
          return #shown > 0
        end, 1000)
      end)
      vim.wait = real_wait
      assert.is_true(ok, tostring(closed))
      assert.equals(1, #waits, "close waits for the job's exit with vim.wait")
      local first = waits[1] or {}
      assert.is_true((first.ms or 0) > 0)
      assert.is_false(first.exited_at_call, "the wait is on the exit flag, still unset here")
      assert.is_true(closed)
      assert.equals(0, registry:count(), "the terminal is removed anyway")
      assert.equals(1, #messages, vim.inspect(messages))
      assert.truthy((messages[1] or ""):find("did not stop", 1, true))
      assert.is_true(jobs.wait(function()
        return h.exited == true
      end))
      assert.is_true(first.pred ~= nil and first.pred(), "the wait ends with the exit flag")
    end)

    -- A real job that ignores TERM and HUP: Neovim has to kill it itself, which takes seconds.
    -- Registered only where such a job can be run (POSIX with sh); the case never skips itself.
    if jobs.stubborn() then
      it("close warns about a job that survives its stop, and removes it after the kill", function()
        local h = backend.spawn(spec({ cmd = jobs.stubborn() }))
        local bufnr = h.bufnr
        local pid = vim.fn.jobpid(h.job)
        assert.is_true(
          jobs.wait(function()
            return jobs.shows(bufnr, "ready")
          end),
          "the job did not start"
        )
        assert.is_true(jobs.process_alive(pid))
        local closed, took
        local messages = jobs.capture_notify(function(shown)
          local started = vim.uv.hrtime()
          closed = backend.close(h)
          took = (vim.uv.hrtime() - started) / 1e6
          jobs.wait(function()
            return #shown > 0
          end, 1000)
        end)
        assert.is_true(closed)
        assert.is_true(took < 7000, ("close blocked %d ms"):format(took))
        assert.equals(1, #messages, vim.inspect(messages))
        assert.truthy((messages[1] or ""):find("did not stop", 1, true))
        assert.equals(0, registry:count())
        assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
        -- Asked of the operating system: without the wait for Neovim's own kill the buffer of a
        -- live job is deleted and the process is still there when close returns.
        assert.is_false(jobs.process_alive(pid), "the process is gone when close returns")
      end)
    end

    it("watches wiped buffers with ONE named autocommand, however many terminals", function()
      backend.spawn(spec({ name = "a" }))
      backend.spawn(spec({ name = "b" }))
      native.new(registry_mod.new()) -- a second backend replaces the group, it does not add to it
      local found = vim.api.nvim_get_autocmds({ group = "terminal.native", event = "BufWipeout" })
      assert.equals(1, #found)
    end)
  end)
end)
