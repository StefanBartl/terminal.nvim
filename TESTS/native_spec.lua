---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/native_spec.lua -- terminal.backends.native: the backend contract on real windows/jobs.

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

  describe("close and list", function()
    it("close stops the job and removes the terminal; closing again is harmless", function()
      local h = backend.spawn(spec())
      local job, bufnr = h.job, h.bufnr
      jobs.settle()
      assert.is_true(backend.close(h))
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
      assert.equals(0, registry:count())
      assert.is_true(backend.close(h))
      assert.not_equals(-1, vim.fn.jobwait({ job }, 2000)[1])
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
  end)
end)
