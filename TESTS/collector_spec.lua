---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/collector_spec.lua -- terminal.status.collector: the branch lookup.
-- Disabled diagnostics: busted's globals and the optional fields of `vim.b` are outside the
-- annotations the language server knows.

-- Hermetic: no multiplexer variables from the terminal the specs are run in.
dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/support/env.lua").isolate()

describe("terminal.status.collector branch", function()
  local collector
  local root, file, buf

  --- A directory that looks like a repository: `.git/HEAD` with `content`.
  ---@param dir string
  ---@param content string
  local function make_repo(dir, content)
    vim.fn.mkdir(dir .. "/.git", "p")
    vim.fn.writefile({ content }, dir .. "/.git/HEAD")
  end

  --- Rewrite HEAD so that mtime and size are exactly as given (a switch can keep the size).
  ---@param dir string
  ---@param content string
  ---@param mtime integer Seconds
  local function rewrite_head(dir, content, mtime)
    vim.fn.writefile({ content }, dir .. "/.git/HEAD")
    vim.uv.fs_utime(dir .. "/.git/HEAD", mtime, mtime)
  end

  local function branch()
    return collector.snapshot().branch
  end

  before_each(function()
    package.loaded["terminal.status.collector"] = nil
    collector = require("terminal.status.collector")
    root = vim.fn.tempname()
    make_repo(root, "ref: refs/heads/main")
    file = root .. "/file.txt"
    vim.fn.writefile({ "x" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    buf = vim.api.nvim_get_current_buf()
  end)

  after_each(function()
    vim.cmd("enew")
    pcall(vim.cmd, "bwipeout! " .. buf)
    vim.fn.delete(root, "rf")
  end)

  it("reads the branch from .git/HEAD", function()
    assert.equals("main", branch())
  end)

  it("sees a switch at once: the cache is the file's mtime, not a timer", function()
    assert.equals("main", branch())
    rewrite_head(root, "ref: refs/heads/feature", os.time() + 10)
    assert.equals("feature", branch())
  end)

  it("sees a switch to a branch name of the same length", function()
    rewrite_head(root, "ref: refs/heads/aaaa", 1000000)
    assert.equals("aaaa", branch())
    rewrite_head(root, "ref: refs/heads/bbbb", 2000000)
    assert.equals("bbbb", branch())
  end)

  it("a detached HEAD gives the short hash", function()
    rewrite_head(root, "0123456789abcdef0123456789abcdef01234567", os.time() + 20)
    assert.equals("0123456", branch())
  end)

  it("outside a repository there is no branch, and a repository created later is seen", function()
    local plain = vim.fn.tempname()
    vim.fn.mkdir(plain, "p")
    local other = plain .. "/o.txt"
    vim.fn.writefile({ "y" }, other)
    vim.cmd("edit " .. vim.fn.fnameescape(other))
    local other_buf = vim.api.nvim_get_current_buf()
    local ok, err = pcall(function()
      assert.is_nil(branch())
      make_repo(plain, "ref: refs/heads/fresh")
      assert.equals("fresh", branch())
    end)
    vim.cmd("enew")
    pcall(vim.cmd, "bwipeout! " .. other_buf)
    vim.fn.delete(plain, "rf")
    assert.is_true(ok, tostring(err))
  end)

  it("a repository that disappears stops being reported", function()
    assert.equals("main", branch())
    vim.fn.delete(root .. "/.git", "rf")
    assert.is_nil(branch())
  end)

  it("a .git FILE (worktree, submodule) is unknown, not an error", function()
    vim.fn.delete(root .. "/.git", "rf")
    vim.fn.writefile({ "gitdir: /somewhere/else" }, root .. "/.git")
    assert.is_nil(branch())
  end)

  it("gitsigns' answer for the CURRENT buffer is never served to another buffer", function()
    assert.equals("main", branch()) -- the directory's answer is remembered
    vim.b[buf].gitsigns_head = "wt-feature"
    assert.equals("wt-feature", branch())
    -- a second buffer in the same directory has no gitsigns variable
    local second = root .. "/second.txt"
    vim.fn.writefile({ "z" }, second)
    vim.cmd("edit " .. vim.fn.fnameescape(second))
    local second_buf = vim.api.nvim_get_current_buf()
    local got = branch()
    vim.cmd("buffer " .. buf)
    pcall(vim.cmd, "bwipeout! " .. second_buf)
    assert.equals("main", got)
  end)

  it("reads gitsigns_status_dict.head when gitsigns_head is not set", function()
    vim.b[buf].gitsigns_status_dict = { head = "from-dict" }
    assert.equals("from-dict", branch())
  end)
end)
