---@diagnostic disable: need-check-nil, undefined-field, redundant-parameter
-- need-check-nil, undefined-field and redundant-parameter are off for the whole file: a nil in a spec body fails the next assertion anyway, luassert's assert.* and the stubbed vim.* fields are not in the annotations, and luassert takes a failure message as its last argument, which its type stub does not declare.
-- TESTS/registry_spec.lua -- terminal.core.registry, terminal.core.context, terminal.backends

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local registry = require("terminal.core.registry")
local context = require("terminal.core.context")
local backends = require("terminal.backends")

---@return Terminal.Handle
local function handle(root, name, extra)
  return vim.tbl_extend("force", {
    id = registry.make_id(root, name),
    name = name,
    root = root,
    backend = "native",
    layout = "float",
  }, extra or {})
end

describe("terminal.core.registry", function()
  it("keeps instances apart: two registries share nothing", function()
    local a, b = registry.new(), registry.new()
    a:add(handle("/p", "main"))
    assert.equals(1, a:count())
    assert.equals(0, b:count())
  end)

  it("finds a terminal by root and name, and by buffer", function()
    local r = registry.new()
    r:add(handle("/p", "main", { bufnr = 7 }))
    assert.equals("main", r:find("/p", "main").name)
    assert.is_nil(r:find("/q", "main"))
    assert.equals("main", r:find_by_buf(7).name)
    assert.is_nil(r:find_by_buf(8))
  end)

  it("lists in creation order, optionally for one project, and survives a replace", function()
    local r = registry.new()
    r:add(handle("/p", "a"))
    r:add(handle("/q", "b"))
    r:add(handle("/p", "c"))
    r:add(handle("/p", "a", { layout = "tab" }))
    assert.equals(3, r:count())
    assert.same(
      { "a", "b", "c" },
      vim.tbl_map(function(h)
        return h.name
      end, r:list())
    )
    assert.same(
      { "a", "c" },
      vim.tbl_map(function(h)
        return h.name
      end, r:list("/p"))
    )
    assert.equals("tab", r:find("/p", "a").layout)
  end)

  it("removes a terminal and returns it; removing twice is harmless", function()
    local r = registry.new()
    r:add(handle("/p", "a"))
    assert.equals("a", r:remove(registry.make_id("/p", "a")).name)
    assert.is_nil(r:remove(registry.make_id("/p", "a")))
    assert.equals(0, r:count())
  end)
end)

describe("terminal.core.context", function()
  ---@param cwd string
  ---@param bufname string
  ---@param root string|nil
  local function deps(cwd, bufname, root)
    return {
      cwd = function()
        return cwd
      end,
      bufname = function()
        return bufname
      end,
      root = function()
        return root
      end,
    }
  end

  it("project mode: the git root; without one, the cwd", function()
    local cwd, root = context.resolve("project", deps("/w/cwd", "/w/proj/src/a.lua", "/w/proj"))
    assert.equals("/w/proj", cwd)
    assert.equals("/w/proj", root)
    cwd, root = context.resolve("project", deps("/w/cwd", "/x/a.lua", nil))
    assert.equals("/w/cwd", cwd)
    assert.equals("/w/cwd", root)
  end)

  it("buffer mode: the buffer's directory, the root stays the project", function()
    local cwd, root = context.resolve("buffer", deps("/w/cwd", "/w/proj/src/a.lua", "/w/proj"))
    assert.equals("/w/proj/src", cwd)
    assert.equals("/w/proj", root)
  end)

  it("cwd mode: the cwd", function()
    local cwd = context.resolve("cwd", deps("/w/cwd", "/w/proj/src/a.lua", "/w/proj"))
    assert.equals("/w/cwd", cwd)
  end)

  it("ignores a buffer that is not a file (URI-like names, no name)", function()
    local cwd, root = context.resolve("buffer", deps("/w/cwd", "term://~/x//123:sh", nil))
    assert.equals("/w/cwd", cwd)
    assert.equals("/w/cwd", root)
    cwd = context.resolve("buffer", deps("/w/cwd", "", nil))
    assert.equals("/w/cwd", cwd)
  end)

  it("keeps a filesystem root intact", function()
    local cwd, root = context.resolve("cwd", deps("/", "", nil))
    assert.equals("/", cwd)
    assert.equals("/", root)
    cwd = context.resolve("cwd", deps("C:/", "", nil))
    assert.equals("C:/", cwd)
  end)

  it("names the terminal by count, falling back to the default name", function()
    assert.equals("main", context.name_for_count(nil, "main"))
    assert.equals("main", context.name_for_count(0, "main"))
    assert.equals("3", context.name_for_count(3, "main"))
    assert.equals("3", context.name_for_count(3.9, "main"))
  end)

  it("refuses a count that is no number from 0 up, with a reason", function()
    for _, bad in ipairs({ "3", -1, 0 / 0, math.huge, {}, true }) do
      -- Deliberately wrong types: the case checks the guard.
      ---@diagnostic disable-next-line: param-type-mismatch
      local name, err = context.name_for_count(bad, "main")
      assert.is_nil(name, vim.inspect(bad))
      assert.truthy(err:find("count must be a number from 1 up", 1, true), vim.inspect(bad))
    end
  end)

  describe("the key is canonical, the start directory is the user's own spelling", function()
    -- A link to /real/proj: the user is in /link/proj, the registry has to see /real/proj.
    local function linked(cwd, bufname, root)
      local d = deps(cwd, bufname, root)
      d.key = function(path)
        return (path:gsub("^/link/", "/real/"))
      end
      return d
    end

    it("project mode starts in the project root as the user reaches it", function()
      local cwd, root = context.resolve("project", linked("/link/proj", "", "/link/proj"))
      assert.equals("/link/proj", cwd)
      assert.equals("/real/proj", root)
    end)

    it("cwd mode starts in the cwd as spelled and keys it canonically", function()
      local cwd, root = context.resolve("cwd", linked("/link/proj/src", "", "/link/proj"))
      assert.equals("/link/proj/src", cwd)
      assert.equals("/real/proj", root)
    end)

    it("buffer mode starts in the buffer's directory as spelled", function()
      local cwd, root =
        context.resolve("buffer", linked("/link/proj", "/link/proj/src/a.lua", "/link/proj"))
      assert.equals("/link/proj/src", cwd)
      assert.equals("/real/proj", root)
    end)

    it("two spellings of one project share one key", function()
      local _, via_link = context.resolve("project", linked("/link/proj", "", "/link/proj"))
      local _, via_real = context.resolve("project", linked("/real/proj", "", "/real/proj"))
      assert.equals(via_real, via_link)
    end)

    it("without a key function the root is the directory as given", function()
      local _, root = context.resolve("project", deps("/w/proj", "", "/w/proj"))
      assert.equals("/w/proj", root)
    end)
  end)
end)

describe("terminal.backends", function()
  it("detect: native is always last, specific signals come first", function()
    assert.same({ "native" }, backends.detect({}))
    assert.same({ "wezterm", "native" }, backends.detect({ WEZTERM_PANE = "0" }))
    assert.same({ "tmux", "native" }, backends.detect({ TMUX = "/tmp/tmux-1/default,1,0" }))
    assert.same(
      { "tmux", "wezterm", "native" },
      backends.detect({ TMUX = "x", WEZTERM_PANE = "0" })
    )
  end)

  it("detect: empty strings are not signals", function()
    assert.same({ "native" }, backends.detect({ TMUX = "", WEZTERM_PANE = "" }))
  end)

  it("resolve auto and native: terminals stay native, even inside a multiplexer", function()
    local env = { WEZTERM_PANE = "0", TMUX = "x" }
    local reg = { native = true, wezterm = true, tmux = true }
    assert.equals("native", (backends.resolve("auto", env, reg)))
    assert.equals("native", (backends.resolve("native", env, reg)))
    assert.equals("wezterm", (backends.resolve("wezterm", env, reg)))
  end)

  it("resolve: a named backend that is not registered falls back to native with a note", function()
    local name, note = backends.resolve("tmux", {}, { native = true })
    assert.equals("native", name)
    assert.truthy(note:find("tmux", 1, true))
  end)

  it("resolve: a named backend that is registered wins without a note", function()
    local name, note = backends.resolve("native", {}, { native = true })
    assert.equals("native", name)
    assert.is_nil(note)
  end)
end)
