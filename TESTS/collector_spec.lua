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

  -- The collector believes a root walk for 2000 ms (hrtime); a spec moves its clock instead of
  -- sleeping through that.
  local real_hrtime, skew_ms
  local cwd0
  local extra_dirs, extra_bufs

  --- Let `ms` milliseconds pass for the collector's memo.
  ---@param ms number
  local function advance(ms)
    skew_ms = skew_ms + ms
  end

  --- A fresh directory (removed after the case), optionally made a repository.
  ---@param head? string The content of `.git/HEAD`; nil: not a repository
  ---@return string dir
  local function scratch_dir(head)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    if head then
      make_repo(dir, head)
    end
    extra_dirs[#extra_dirs + 1] = dir
    return dir
  end

  --- Make `path` (a new file) the current buffer; it is wiped after the case.
  ---@param path string
  ---@return integer buf
  local function open_file(path)
    vim.fn.writefile({ "y" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local b = vim.api.nvim_get_current_buf()
    extra_bufs[#extra_bufs + 1] = b
    return b
  end

  before_each(function()
    package.loaded["terminal.status.collector"] = nil
    collector = require("terminal.status.collector")
    skew_ms, extra_dirs, extra_bufs = 0, {}, {}
    cwd0 = vim.fn.getcwd()
    real_hrtime = vim.uv.hrtime
    -- Test double: the clock the memo reads, with `advance()` as the only way to push it on.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.uv.hrtime = function()
      return real_hrtime() + skew_ms * 1e6
    end
    root = vim.fn.tempname()
    make_repo(root, "ref: refs/heads/main")
    file = root .. "/file.txt"
    vim.fn.writefile({ "x" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    buf = vim.api.nvim_get_current_buf()
  end)

  after_each(function()
    -- Restore the original.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.uv.hrtime = real_hrtime
    vim.api.nvim_set_current_dir(cwd0)
    vim.cmd("enew")
    for _, b in ipairs(extra_bufs) do
      pcall(function()
        vim.cmd("bwipeout! " .. b)
      end)
    end
    pcall(function()
      vim.cmd("bwipeout! " .. buf)
    end)
    vim.fn.delete(root, "rf")
    for _, dir in ipairs(extra_dirs) do
      vim.fn.delete(dir, "rf")
    end
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
    local plain = scratch_dir()
    open_file(plain .. "/o.txt")
    assert.is_nil(branch())
    make_repo(plain, "ref: refs/heads/fresh")
    -- "no repository" is remembered like any other answer, so the new one shows after the memo
    advance(2100)
    assert.equals("fresh", branch())
  end)

  it("a repository created BELOW a known one is found once the memo expires", function()
    -- `git init` or a clone in a directory of a dotfiles or monorepo checkout whose files were
    -- already visited: the answer "the outer repository" is remembered for that directory, and
    -- the outer HEAD stays readable, so no stat of it can notice the nearer repository.
    local sub = root .. "/sub"
    vim.fn.mkdir(sub, "p")
    open_file(sub .. "/f.txt")
    assert.equals("main", branch())
    make_repo(sub, "ref: refs/heads/inner")
    advance(2100)
    assert.equals("inner", branch())
  end)

  --- How often `vim.fs.root` runs while `fn` does.
  ---@param fn fun()
  ---@return integer
  local function count_root_walks(fn)
    local walks = 0
    local real_root = vim.fs.root
    -- Test double: counts the root walks and delegates to the real one; restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fs.root = function(...)
      walks = walks + 1
      return real_root(...)
    end
    local ok, err = pcall(fn)
    -- Restore the original.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fs.root = real_root
    assert.is_true(ok, tostring(err))
    return walks
  end

  it("the root walk of a repository is made once per memo window, then asked again", function()
    local walks = count_root_walks(function()
      for _ = 1, 5 do
        assert.equals("main", branch())
      end
      advance(2100)
      assert.equals("main", branch())
    end)
    assert.equals(2, walks)
  end)

  it("a directory outside any repository is walked once per memo window, not per event", function()
    local plain = scratch_dir()
    open_file(plain .. "/o.txt")
    local walks = count_root_walks(function()
      for _ = 1, 5 do
        assert.is_nil(branch())
      end
      advance(2100)
      assert.is_nil(branch())
    end)
    assert.equals(2, walks)
  end)

  it("a worktree (.git FILE) is walked once per memo window, not per event", function()
    vim.fn.delete(root .. "/.git", "rf")
    vim.fn.writefile({ "gitdir: /somewhere/else" }, root .. "/.git")
    local walks = count_root_walks(function()
      for _ = 1, 5 do
        assert.is_nil(branch())
      end
    end)
    assert.equals(1, walks)
  end)

  describe("a buffer that is not a file on disk", function()
    --- Make the current buffer a scratch buffer with this name and 'buftype'.
    ---@param name string
    ---@param buftype string
    local function label_buffer(name, buftype)
      vim.cmd("enew")
      local b = vim.api.nvim_get_current_buf()
      extra_bufs[#extra_bufs + 1] = b
      vim.bo[b].buftype = buftype
      vim.api.nvim_buf_set_name(b, name)
    end

    it("a terminal buffer follows :cd: its branch is the working directory's", function()
      -- The name of a terminal buffer never changes; what a lookup from it means does.
      local other = scratch_dir("ref: refs/heads/other")
      label_buffer("term://" .. root .. "//4242:sh", "nofile")
      vim.api.nvim_set_current_dir(root)
      assert.equals("main", branch())
      vim.api.nvim_set_current_dir(other)
      assert.equals("other", branch())
      vim.api.nvim_set_current_dir(root)
      assert.equals("main", branch())
    end)

    it("a buffer with a 'buftype' is looked up from the working directory too", function()
      -- an absolute name, but not a file (acwrite: the plugin that owns it writes it elsewhere)
      local other = scratch_dir("ref: refs/heads/other")
      label_buffer(root .. "/virtual.txt", "acwrite")
      vim.api.nvim_set_current_dir(other)
      assert.equals("other", branch())
    end)

    it("a nameless buffer is looked up from the working directory", function()
      local other = scratch_dir("ref: refs/heads/other")
      vim.cmd("enew")
      extra_bufs[#extra_bufs + 1] = vim.api.nvim_get_current_buf()
      vim.api.nvim_set_current_dir(other)
      assert.equals("other", branch())
      vim.api.nvim_set_current_dir(root)
      assert.equals("main", branch())
    end)
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
    pcall(function()
      vim.cmd("bwipeout! " .. second_buf)
    end)
    assert.equals("main", got)
  end)

  it("reads gitsigns_status_dict.head when gitsigns_head is not set", function()
    vim.b[buf].gitsigns_status_dict = { head = "from-dict" }
    assert.equals("from-dict", branch())
  end)
end)
