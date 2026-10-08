---@diagnostic disable: need-check-nil, undefined-field
-- need-check-nil and undefined-field are off for the whole file: a nil in a spec body fails the next assertion anyway, and luassert's assert.* and the stubbed vim.* fields are not in the annotations.
-- TESTS/context_spec.lua -- terminal.core.context against the real editor: one project, one key.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

local context = require("terminal.core.context")
local registry_mod = require("terminal.core.registry")

local is_windows = vim.fn.has("win32") == 1

describe("terminal.core.context (real editor)", function()
  local base, repo, saved_cwd

  before_each(function()
    saved_cwd = vim.fn.getcwd()
    -- A directory name longer than 8.3 allows, so a short spelling exists on Windows.
    base = vim.fn.tempname() .. "-a-long-directory-name"
    repo = base .. "/project"
    vim.fn.mkdir(repo .. "/.git", "p")
    vim.fn.writefile({ "x" }, repo .. "/file.txt")
  end)

  after_each(function()
    vim.cmd("silent! cd " .. vim.fn.fnameescape(saved_cwd))
    vim.cmd("enew")
    vim.fn.delete(base, "rf")
  end)

  --- The registry id a terminal named "main" gets when resolved from the current state.
  ---@return string
  local function id_now()
    local _, root = context.resolve("project", context.from_editor())
    return registry_mod.make_id(root, "main")
  end

  it("a file buffer and a cwd in the same project give the same registry id", function()
    vim.cmd("cd " .. vim.fn.fnameescape(repo))
    vim.cmd("enew")
    local from_cwd = id_now()
    vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/file.txt"))
    assert.equals(from_cwd, id_now())
  end)

  it("an 8.3 short spelling of the cwd is the same project as the long one", function()
    if not is_windows then
      -- Inside a running case busted's pending(name) alone marks it pending; the stub also wants a block.
      ---@diagnostic disable-next-line: missing-parameter
      return pending("8.3 short names exist on Windows only")
    end
    -- Neovim's ":8" modifier does nothing; cmd.exe's %~s gives the short spelling.
    local out = vim.fn.system({
      "cmd",
      "/c",
      ('for %%I in ("%s") do @echo %%~sI'):format((repo:gsub("/", "\\"))),
    })
    local short = vim.trim(out)
    if short == "" or short:lower() == repo:gsub("/", "\\"):lower() then
      -- Inside a running case busted's pending(name) alone marks it pending; the stub also wants a block.
      ---@diagnostic disable-next-line: missing-parameter
      return pending("this volume has no 8.3 names for the test directory")
    end
    vim.cmd("cd " .. vim.fn.fnameescape(short))
    vim.cmd("enew") -- no file buffer: the root comes from the cwd alone
    local from_short = id_now()
    vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/file.txt"))
    assert.equals(from_short, id_now())
    -- and a terminal buffer (term://...) has no directory either
    vim.cmd("enew")
    vim.api.nvim_buf_set_name(0, "term://" .. short .. "//123:sh")
    assert.equals(from_short, id_now())
  end)

  it("a symlinked cwd is the same project as its target", function()
    local link = base .. "/link"
    local ok = vim.uv.fs_symlink(repo, link, { dir = true })
    if not ok then
      -- Inside a running case busted's pending(name) alone marks it pending; the stub also wants a block.
      ---@diagnostic disable-next-line: missing-parameter
      return pending("cannot create a symlink here (needs a privilege on Windows)")
    end
    vim.cmd("cd " .. vim.fn.fnameescape(link))
    vim.cmd("enew")
    local from_link = id_now()
    vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/file.txt"))
    assert.equals(from_link, id_now())
  end)

  it("a directory without a git root is its own project, spelled one way", function()
    local plain = base .. "/plain"
    vim.fn.mkdir(plain, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(plain))
    vim.cmd("enew")
    local cwd, root = context.resolve("project", context.from_editor())
    assert.equals(cwd, root)
    assert.is_nil(cwd:find("\\", 1, true), "forward slashes only")
    assert.is_nil(cwd:find("/$"), "no trailing slash")
  end)
end)
