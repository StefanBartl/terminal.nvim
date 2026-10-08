---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/status_spec.lua -- the status dataset, its escape-sequence writer and the exporter.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local osc = require("terminal.core.osc")
local status = require("terminal.core.status")

describe("terminal.core.osc", function()
  it("sanitize turns every control character into ? and keeps text", function()
    assert.equals("a?b?c", osc.sanitize("a\27b\7c"))
    assert.equals("x?y", osc.sanitize("x\ny"))
    assert.equals("x?y", osc.sanitize("x\127y"))
    assert.equals("ünï", osc.sanitize("ünï"))
  end)

  it("sanitize cuts at a byte limit without splitting a UTF-8 character", function()
    assert.equals("abc", osc.sanitize("abcdef", 3))
    -- "ü" is two bytes: a cut in the middle of it steps back to the character boundary
    assert.equals("a", osc.sanitize("aüb", 2))
    assert.equals("aü", osc.sanitize("aüb", 3))
  end)

  it("sanitize accepts non-strings", function()
    assert.equals("", osc.sanitize(nil))
    assert.equals("12", osc.sanitize(12))
  end)

  it("user_var builds a SetUserVar sequence with a base64 value", function()
    local seq = osc.user_var("MUX_NVIM", "1")
    assert.equals("\27]1337;SetUserVar=MUX_NVIM=MQ==\7", seq)
  end)

  it("user_var refuses a name that could end or extend the sequence", function()
    for _, bad in ipairs({ "A=B", "A\7B", "A\27B", "", "A B", "A;B", 5 }) do
      local seq, err = osc.user_var(bad, "x")
      assert.is_nil(seq, tostring(bad))
      assert.truthy(err)
    end
  end)

  it("a hostile value cannot leave the base64 envelope", function()
    local seq = osc.user_var("X", "\7\27]0;pwned\7\27\\ and \n more")
    local body = seq:sub(#"\27]1337;SetUserVar=X=" + 1, -2)
    assert.truthy(body:find("^[A-Za-z0-9+/=]+$"))
    assert.equals("\7", seq:sub(-1))
    -- only one BEL (the terminator) and one ESC (the introducer) in the whole sequence
    assert.equals(1, select(2, seq:gsub("\7", "")))
    assert.equals(1, select(2, seq:gsub("\27", "")))
  end)

  it("wrap_tmux doubles every ESC of the inner sequence", function()
    local seq = assert(osc.user_var("A", "b"))
    assert.equals("\27Ptmux;\27\27]1337;SetUserVar=A=Yg==\7\27\\", osc.wrap_tmux(seq))
  end)

  it("user_vars joins several in one string and wraps each for tmux", function()
    local plain = osc.user_vars({ { "A", "1" }, { "B", "2" } }, false)
    assert.equals(osc.user_var("A", "1") .. osc.user_var("B", "2"), plain)
    local wrapped = osc.user_vars({ { "A", "1" }, { "B", "2" } }, true)
    local var_a = assert(osc.user_var("A", "1"))
    local var_b = assert(osc.user_var("B", "2"))
    assert.equals(osc.wrap_tmux(var_a) .. osc.wrap_tmux(var_b), wrapped)
    assert.is_nil((osc.user_vars({ { "bad name", "1" } }, false)))
  end)
end)

describe("terminal.core.status", function()
  ---@return Terminal.StatusSnapshot
  local function snap(over)
    return vim.tbl_extend("force", {
      mode = "n",
      file = "/home/u/proj/src/main.lua",
      buftype = "",
      cwd = "/home/u/proj",
      branch = "main",
      diag = { error = 2, warn = 1 },
      recording = "",
      modified = false,
      filetype = "lua",
      pid = 4242,
    }, over or {})
  end

  it("builds the dataset from raw values", function()
    local s = status.build(snap())
    assert.same({
      v = 1,
      pid = 4242,
      mode = "n",
      file = "main.lua",
      ft = "lua",
      cwd = "/home/u/proj",
      branch = "main",
      e = 2,
      w = 1,
      i = 0,
      h = 0,
      rec = "",
      mod = false,
    }, s)
  end)

  it("names special buffers instead of leaking their path", function()
    assert.equals(
      "terminal",
      status.build(snap({ buftype = "terminal", file = "term://~//1:sh" })).file
    )
    assert.equals("[No Name]", status.build(snap({ file = "" })).file)
    assert.equals("c.lua", status.build(snap({ file = "C:\\a\\b\\c.lua" })).file)
  end)

  it("sanitises hostile free text everywhere it appears", function()
    local s = status.build(snap({
      file = "/x/evil\27]0;owned\7.lua",
      branch = "b\27[31m",
      cwd = "/c\nd",
      mode = "n\27",
      recording = "q\7",
      filetype = "l\27ua",
    }))
    for _, field in ipairs({ "file", "branch", "cwd", "mode", "rec", "ft" }) do
      assert.is_nil(s[field]:find("[%z\1-\31\127]"), field)
    end
  end)

  it("blockwise Visual and Select-block survive as ^V / ^S instead of '?'", function()
    assert.equals("^V", status.build(snap({ mode = "\22" })).mode)
    assert.equals("^S", status.build(snap({ mode = "\19" })).mode)
    assert.equals("no^V", status.build(snap({ mode = "no\22" })).mode)
    assert.equals("^Vs", status.build(snap({ mode = "\22s" })).mode)
    -- every other control character still becomes '?'
    assert.equals("n?", status.build(snap({ mode = "n\27" })).mode)
    for _, mode in ipairs({ "n", "no", "nov", "V", "v", "i", "R", "c", "t", "ntT" }) do
      assert.equals(mode, status.build(snap({ mode = mode })).mode)
    end
  end)

  it("clamps counts to non-negative integers", function()
    local s = status.build(snap({ diag = { error = -3, warn = 2.7, info = "x", hint = 1e9 } }))
    assert.equals(0, s.e)
    assert.equals(2, s.w)
    assert.equals(0, s.i)
    assert.equals(99999, s.h)
  end)

  it("the same snapshot builds the same dataset, another mode a different one", function()
    assert.same(status.build(snap()), status.build(snap()))
    assert.not_same(status.build(snap()), status.build(snap({ mode = "i" })))
  end)

  it("encode returns compact JSON that round-trips", function()
    local json = assert(status.encode(status.build(snap())))
    local back = vim.json.decode(json)
    assert.equals(1, back.v)
    assert.equals("main.lua", back.file)
  end)

  it("encode shortens long text to fit and refuses what cannot fit", function()
    local long = string.rep("x", 400)
    local s = status.build(snap({ cwd = long, file = long, branch = long }))
    local json = status.encode(s, 300)
    assert.is_true(#json <= 300)
    local fitted = assert(status.encode(status.build(snap()), 1024))
    assert.equals("main.lua", vim.json.decode(fitted).file)
    local none, err = status.encode(s, 20)
    assert.is_nil(none)
    assert.truthy(err:find("over the limit", 1, true))
  end)
end)

describe("terminal.status (publishing)", function()
  local publisher, writes
  local original_send, original_uis

  before_each(function()
    package.loaded["terminal.status"] = nil
    publisher = require("terminal.status")
    writes = {}
    original_send, original_uis = vim.api.nvim_ui_send, vim.api.nvim_list_uis
    -- Test double: records what would be written to the terminal instead of sending it.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_ui_send = function(payload)
      writes[#writes + 1] = payload
    end
    -- Test double: pretends that one UI is attached.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_list_uis = function()
      return { {} }
    end
  end)

  after_each(function()
    -- The stubs go first: clear() asks the editor, not the double, whether a UI is attached, and
    -- a clear that runs against a UI-less double would print a notice nobody checks for.
    vim.api.nvim_ui_send, vim.api.nvim_list_uis = original_send, original_uis
    publisher.clear()
    pcall(vim.api.nvim_del_augroup_by_name, "terminal.status")
  end)

  local function cfg(over)
    return vim.tbl_deep_extend(
      "force",
      { status = { enable = true, export = "auto", debounce_ms = 5, max_bytes = 1024 } },
      over or {}
    )
  end

  ---@param payload string
  ---@return table vars Decoded user vars of one payload
  local function decode(payload)
    local vars = {}
    for name, b64 in payload:gmatch("SetUserVar=([%w_]+)=([%w+/=]*)\7") do
      vars[name] = vim.base64.decode(b64)
    end
    return vars
  end

  it("choose: auto takes the exporters whose environment signal is present", function()
    assert.same({}, publisher.choose("auto", {}))
    local chosen = publisher.choose("auto", { WEZTERM_PANE = "3" })
    assert.same(
      { "wezterm" },
      vim.tbl_map(function(e)
        return e.name
      end, chosen)
    )
  end)

  it("choose: auto outside tmux and WezTerm loads no exporter and no tmux backend", function()
    for _, mod in ipairs({
      "terminal.status.exporters.tmux",
      "terminal.status.exporters.wezterm",
      "terminal.backends.tmux",
      "terminal.core.osc",
    }) do
      package.loaded[mod] = nil
    end
    assert.same({}, (publisher.choose("auto", {})))
    for _, mod in ipairs({
      "terminal.status.exporters.tmux",
      "terminal.status.exporters.wezterm",
      "terminal.backends.tmux",
      "terminal.core.osc",
    }) do
      assert.is_nil(package.loaded[mod], mod .. " was loaded for nothing")
    end
    -- inside WezTerm only that exporter's module is loaded
    publisher.choose("auto", { WEZTERM_PANE = "3" })
    assert.is_not_nil(package.loaded["terminal.status.exporters.wezterm"])
    assert.is_nil(package.loaded["terminal.status.exporters.tmux"])
    assert.is_nil(package.loaded["terminal.backends.tmux"])
  end)

  it("choose: false means none; an unknown or unusable name is reported", function()
    assert.same({}, (publisher.choose(false, { WEZTERM_PANE = "3" })))
    local chosen, notes = publisher.choose({ "nope" }, {})
    assert.same({}, chosen)
    assert.truthy(notes[1]:find("does not exist", 1, true))
    chosen, notes = publisher.choose("wezterm", {})
    assert.same({}, chosen)
    assert.truthy(notes[1]:find("not usable", 1, true))
  end)

  it("publishes MUX_NVIM, MUX_PIPE and MUX_STATUS in ONE write", function()
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    assert.equals(1, #writes)
    local vars = decode(writes[1])
    assert.equals("1", vars.MUX_NVIM)
    assert.equals(vim.v.servername, vars.MUX_PIPE)
    local data = vim.json.decode(vars.MUX_STATUS)
    assert.equals(status.VERSION, data.v)
    assert.equals(vim.fn.getpid(), data.pid)
  end)

  it("writes again only when the dataset changed", function()
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    publisher.publish_now()
    assert.equals(1, #writes, "an identical dataset is not sent twice")
    vim.cmd("enew")
    vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. "-other.txt")
    publisher.publish_now()
    assert.equals(2, #writes)
  end)

  it("a burst of events becomes one debounced write", function()
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    writes = {}
    vim.cmd("enew")
    vim.cmd("enew")
    vim.cmd("enew")
    assert.is_true(vim.wait(1000, function()
      return #writes >= 1
    end))
    vim.wait(100)
    assert.equals(1, #writes)
  end)

  it("clear sends empty values", function()
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    publisher.clear()
    local vars = decode(writes[#writes])
    assert.equals("", vars.MUX_NVIM)
    assert.equals("", vars.MUX_PIPE)
    assert.equals("", vars.MUX_STATUS)
  end)

  it("publishes nothing when disabled or when no exporter fits", function()
    publisher.setup(cfg({ status = { enable = false } }), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    publisher.setup(cfg(), {})
    publisher.publish_now()
    assert.same({}, writes)
    assert.same({}, publisher.active())
  end)

  it("under tmux the writes are wrapped for passthrough", function()
    local saved = vim.env.TMUX
    vim.env.TMUX = "/tmp/tmux-1/default,1,0"
    publisher.setup(cfg(), { WEZTERM_PANE = "3", TMUX = "x" })
    publisher.publish_now()
    vim.env.TMUX = saved
    assert.equals("\27Ptmux;", writes[1]:sub(1, 7))
  end)

  it("without a UI nothing is published, silently, and the exporter stays on", function()
    local notices = {}
    local original_notify = vim.notify
    -- Test double: collects the notifications instead of showing them.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    -- Test double: no UI is attached.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_list_uis = function()
      return {}
    end
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    publisher.publish_now()
    vim.wait(50)
    vim.notify = original_notify
    assert.same({ "wezterm" }, publisher.active())
    assert.same({}, writes)
    assert.same({}, notices)
  end)

  it("a clear without a UI succeeds and warns about nothing (a headless run in a pane)", function()
    local notices = {}
    local original_notify = vim.notify
    -- Test double: collects the notifications instead of showing them.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    -- Test double: no UI is attached.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_list_uis = function()
      return {}
    end
    local exporter = require("terminal.status.exporters.wezterm")
    local ok, err = exporter.clear()
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.clear() -- what Neovim does on every exit, with or without a UI
    vim.wait(100)
    vim.notify = original_notify
    assert.is_true(ok, tostring(err))
    assert.is_nil(err)
    assert.same({}, writes, "no UI, nothing to write to")
    assert.same({}, notices, "nothing was left behind, so there is nothing to complain about")
  end)

  it("a clear that fails with a UI attached is still reported", function()
    local notices = {}
    local original_notify = vim.notify
    -- Test double: collects the notifications instead of showing them.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    -- Test double: the terminal channel breaks.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_ui_send = function()
      error("channel closed")
    end
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.clear()
    vim.wait(100)
    vim.notify = original_notify
    assert.equals(1, #notices, vim.inspect(notices))
    assert.truthy(notices[1]:find("could not clear", 1, true), notices[1])
    assert.truthy(notices[1]:find("channel closed", 1, true), notices[1])
  end)

  it("what could not be sent without a UI goes out once one attaches", function()
    local attached = false
    -- Test double: a UI that is attached only once `attached` is set.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_list_uis = function()
      return attached and { {} } or {}
    end
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    assert.same({}, writes)
    attached = true
    publisher.publish_now()
    assert.equals(1, #writes)
  end)

  it("a UI that attaches again gets the status even when nothing changed", function()
    local attached = true
    -- Test double: a UI that can go away and come back through `attached`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_list_uis = function()
      return attached and { {} } or {}
    end
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    assert.equals(1, #writes)
    -- the UI goes away and a new one (another WezTerm pane after `:detach`) attaches: it has seen
    -- nothing, so the unchanged dataset must go out again
    attached = false
    publisher.publish_now()
    attached = true
    writes = {}
    vim.api.nvim_exec_autocmds("UIEnter", { group = "terminal.status", modeline = false })
    assert.is_true(vim.wait(1000, function()
      return #writes >= 1
    end))
    local vars = decode(writes[1])
    assert.equals("1", vars.MUX_NVIM)
  end)

  it("without nvim_ui_send (Neovim 0.11) the exporter says why: it needs 0.12", function()
    local saved = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = nil
    local chosen, notes = publisher.choose("wezterm", { WEZTERM_PANE = "3" })
    vim.api.nvim_ui_send = saved
    assert.same({}, chosen)
    assert.equals(1, #notes)
    assert.truthy(notes[1]:find("0.12", 1, true), notes[1])
    assert.is_nil(notes[1]:find("0.11+ needed", 1, true))
  end)

  it("UIEnter is one of the events that trigger a publish", function()
    publisher.setup(cfg(), { WEZTERM_PANE = "3" })
    writes = {}
    vim.api.nvim_exec_autocmds("UIEnter", { group = "terminal.status", modeline = false })
    assert.is_true(vim.wait(1000, function()
      return #writes >= 1
    end))
  end)

  -- A fake exporter that counts what it was asked to do (used by the two blocks below).
  ---@class Terminal.Spec.FakeExporter: Terminal.StatusExporter
  ---@field publishes? integer How often publish() was called
  ---@field cleared? integer How often clear() was called

  describe("an exporter that fails", function()
    ---@type Terminal.Spec.FakeExporter
    local failing

    before_each(function()
      failing = {
        name = "wezterm",
        available = function()
          return true
        end,
        publish = function()
          failing.publishes = (failing.publishes or 0) + 1
          return false, "boom"
        end,
        clear = function()
          failing.cleared = (failing.cleared or 0) + 1
          return true
        end,
      }
      package.loaded["terminal.status.exporters.wezterm"] = failing
    end)

    after_each(function()
      package.loaded["terminal.status.exporters.wezterm"] = nil
    end)

    it("is switched off after one failure instead of retrying", function()
      publisher.setup(cfg(), { WEZTERM_PANE = "3" })
      publisher.publish_now()
      publisher.publish_now()
      vim.cmd("enew")
      publisher.publish_now()
      assert.equals(1, failing.publishes)
      assert.same({}, publisher.active())
    end)

    it("is still told to clean up when Neovim leaves", function()
      publisher.setup(cfg(), { WEZTERM_PANE = "3" })
      publisher.publish_now()
      publisher.clear()
      assert.equals(1, failing.cleared)
    end)

    it("a clear that reports failure is not dropped silently", function()
      ---@type string|nil
      local failure = "nope"
      failing.clear = function()
        return failure == nil, failure
      end
      publisher.setup(cfg(), { WEZTERM_PANE = "3" })
      local messages = {}
      local original = vim.notify
      -- Test double: collects the notifications instead of showing them.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg)
        messages[#messages + 1] = msg
      end
      publisher.clear()
      vim.wait(100)
      vim.notify = original
      -- the clear in after_each must not report the same failure a second time
      failure = nil
      assert.equals(1, #messages, vim.inspect(messages))
      assert.truthy(messages[1]:find("could not clear: nope", 1, true))
    end)
  end)

  describe("the delta gate looks at what an exporter publishes", function()
    ---@type Terminal.Spec.FakeExporter
    local probe

    before_each(function()
      probe = {
        name = "wezterm",
        available = function()
          return true
        end,
        key = function(data)
          return data.mode .. "|" .. data.file
        end,
        publish = function()
          probe.publishes = (probe.publishes or 0) + 1
          return true
        end,
        clear = function()
          return true
        end,
      }
      package.loaded["terminal.status.exporters.wezterm"] = probe
    end)

    after_each(function()
      package.loaded["terminal.status.exporters.wezterm"] = nil
    end)

    it("a change outside the key (the info count, the directory) is not published", function()
      publisher.setup(cfg(), { WEZTERM_PANE = "3" })
      publisher.publish_now()
      assert.equals(1, probe.publishes)
      local ns = vim.api.nvim_create_namespace("terminal-spec-info")
      vim.diagnostic.set(ns, 0, {
        { lnum = 0, col = 0, message = "i", severity = vim.diagnostic.severity.INFO },
      })
      publisher.publish_now()
      assert.equals(1, probe.publishes, "an info diagnostic is not in the key")
      vim.cmd("enew")
      vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. "-key.txt")
      publisher.publish_now()
      assert.equals(2, probe.publishes, "the file name is")
    end)
  end)

  it("a dataset over max_bytes is reported once, not on every event", function()
    local notices = {}
    local original_notify = vim.notify
    -- Test double: collects the notifications instead of showing them.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    publisher.setup(cfg({ status = { max_bytes = 20 } }), { WEZTERM_PANE = "3" })
    publisher.publish_now()
    publisher.publish_now()
    publisher.publish_now()
    vim.wait(100)
    vim.notify = original_notify
    local over = vim.tbl_filter(function(m)
      return m:find("over the limit", 1, true) ~= nil
    end, notices)
    assert.equals(1, #over)
    assert.same({}, writes)
  end)

  it("choose: a nested Neovim ($NVIM) is skipped by auto, but a name asks for it anyway", function()
    local tmux_exporter = require("terminal.status.exporters.tmux")
    local saved = tmux_exporter.alive
    -- Test double: the outer Neovim counts as running.
    ---@diagnostic disable-next-line: duplicate-set-field
    tmux_exporter.alive = function()
      return true -- the outer Neovim is running
    end
    local env = { TMUX = "/tmp/tmux-1/default,1,0", TMUX_PANE = "%1", NVIM = "/tmp/nvim.sock" }
    local auto = publisher.choose("auto", env)
    local named = publisher.choose("tmux", env)
    tmux_exporter.alive = saved
    assert.same({}, auto)
    assert.equals(1, #named)
    assert.equals("tmux", named[1].name)
  end)
end)
