---@diagnostic disable: need-check-nil
-- need-check-nil is off for the whole file: a nil handle or reply makes the next check fail anyway, and the script then ends in RESULT failed.
-- TESTS/live/tmux.lua -- the tmux backend and status exporter against a REAL tmux server.
--
-- Headless is fine (nothing here needs a UI). It starts its own tmux server on a private socket
-- (`-L terminal-nvim-live`), so it never touches your sessions, and kills it at the end.
--
--   Linux/macOS:  SMOKE_OUT=/tmp/t.txt nvim --headless -u NONE -l TESTS/live/tmux.lua
--   Windows:      TMUX_LIVE_WSL=archlinux nvim --headless -u NONE -l TESTS/live/tmux.lua
--                 (runs `wsl.exe -d <distro> -e tmux ...`; tmux must be installed in that distro)
--
-- One line per check goes to $SMOKE_OUT (default: terminal-tmux.txt), ending in "RESULT ok" or
-- "RESULT failed".

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):gsub("\\", "/")
local root = here:match("^(.*)/TESTS/live/tmux%.lua$")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.env.LIB_NVIM_DIR or (root .. "/../lib.nvim"))

local SOCKET = "terminal-nvim-live"
local wsl = vim.env.TMUX_LIVE_WSL

local out, failed = {}, false

---@param name string
---@param cond boolean
---@param detail? any
local function check(name, cond, detail)
  if cond then
    out[#out + 1] = "ok   " .. name
  else
    failed = true
    out[#out + 1] = ("FAIL %s%s"):format(
      name,
      detail ~= nil and (" -- " .. vim.inspect(detail)) or ""
    )
  end
end

--- Run a command, through WSL when asked to.
---@param argv string[]
---@return { code: integer, stdout: string, stderr: string }
local function run(argv)
  local full = argv
  if wsl and wsl ~= "" then
    full = { "wsl.exe", "-d", wsl, "-e" }
    vim.list_extend(full, argv)
  end
  local res = vim.system(full, { text = true, timeout = 5000 }):wait()
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
end

local function tmux(...)
  return run(vim.list_extend({ "tmux", "-L", SOCKET }, { ... }))
end

local ok, err = pcall(function()
  local started =
    tmux("new-session", "-d", "-s", "live", "-x", "120", "-y", "40", "-P", "-F", "#{pane_id}")
  check("a private tmux server started", started.code == 0, started)
  local own = vim.trim(started.stdout)

  local registry = require("terminal.core.registry").new()
  local backend = require("terminal.backends.tmux").new(registry, function(argv)
    return run(argv)
  end, own, { socket = SOCKET })

  local h = backend.spawn({
    name = "live",
    root = "/live",
    cwd = "/tmp",
    layout = "vsplit",
    split = { size = 0.4 },
    start_insert = true,
    -- A plain `sh`: the pane must not depend on the login shell of the machine (a bare zsh
    -- without a config can sit in its first-run setup and never answer).
    cmd = { "sh" },
  })
  check("spawn creates a pane", h ~= nil and h.pane:find("^%%%d+$") ~= nil, h)
  assert(h, "spawn returned no handle") -- every check below needs the pane
  vim.wait(800)

  local sent = backend.send(h, "echo terminal-nvim-tmux-check\n")
  check("send reports success", sent == true)
  local seen = vim.wait(5000, function()
    local cap = tmux("capture-pane", "-p", "-t", h.pane)
    return cap.stdout:find("terminal%-nvim%-tmux%-check\n.*terminal%-nvim%-tmux%-check") ~= nil
      or select(2, cap.stdout:gsub("terminal%-nvim%-tmux%-check", "")) >= 2
  end, 250)
  check(
    "the command's output is in the pane",
    seen,
    tmux("capture-pane", "-p", "-t", h.pane).stdout
  )

  -- Hostile text is typed literally, not interpreted by tmux. A pane running `cat` shows every
  -- typed line twice (the tty's echo and cat's output), so the capture says exactly what arrived:
  -- a dropped trailing ';' or a lost backslash would show up as a different line.
  local cat = backend.spawn({
    name = "cat",
    root = "/live",
    cwd = "/tmp",
    layout = "split",
    split = { size = 0.3 },
    cmd = { "cat" },
    focus = false,
  })
  check("a pane running cat started", cat ~= nil, cat)
  assert(cat, "spawn returned no handle for cat") -- the typed lines go into it
  vim.wait(500)
  local samples = {
    "T1 select 1;",
    "T2 find . -exec rm {} \\;",
    "T3 a;",
    "T4 ;",
    "T5 x\\\\;",
    "T6 'C-c Enter; kill-server'",
    "T7 a;b;",
  }
  --- The pane's text once it contains `needle` (a plain string), or what it shows after 5 s. A pane
  --- is read after it had time to print; a fixed pause is too short on a loaded machine.
  ---@param pane string
  ---@param needle string
  ---@return string
  local function pane_text_with(pane, needle)
    local text = ""
    vim.wait(5000, function()
      text = tmux("capture-pane", "-p", "-t", pane).stdout
      return text:find(needle, 1, true) ~= nil
    end, 50)
    return text
  end

  --- The pane's text with its scrollback (the pane is only a few rows high), as a line -> count map.
  local function cat_lines()
    local cap = tmux("capture-pane", "-p", "-S", "-100", "-t", cat.pane).stdout
    local counts = {}
    for line in cap:gmatch("[^\n]+") do
      local trimmed = line:gsub("%s+$", "")
      counts[trimmed] = (counts[trimmed] or 0) + 1
    end
    return counts, cap
  end
  for _, text in ipairs(samples) do
    -- The text on its own, the Enter in a second call: the argument tmux gets must END in the
    -- ';' (with the newline appended it would not, and the escape would go untested).
    backend.send(cat, text)
    backend.send(cat, "\n")
    -- Wait for cat to answer before the next line is typed: the tty echoes what is typed at once,
    -- so a slow `cat` (a loaded machine) would print its answer behind the NEXT typed line and
    -- the capture would show the two glued together.
    vim.wait(5000, function()
      return (cat_lines()[text] or 0) >= 2
    end, 50)
  end
  local seen_lines, cap = cat_lines()
  for _, text in ipairs(samples) do
    -- both the echo and cat's own output: the typed line, byte for byte
    check("typed literally: " .. text, (seen_lines[text] or 0) == 2, cap)
  end
  check("the server survived hostile text", tmux("list-sessions").code == 0)
  backend.close(cat)

  -- Words of a command that end in ';' stay words: tmux must not start another command from them.
  local pwned = "/tmp/terminal-nvim-live-pwned"
  run({ "rm", "-f", pwned })
  local words = backend.spawn({
    name = "words",
    root = "/live",
    cwd = "/tmp",
    layout = "split",
    split = { size = 0.3 },
    cmd = {
      "sh",
      "-c",
      'printf "%s\\n" "$@"; sleep 20',
      "sh",
      "word;",
      "run-shell",
      "touch " .. pwned,
    },
    focus = false,
  })
  check("a command with ';' words spawned", words ~= nil, words)
  local wcap = words and pane_text_with(words.pane, "word;") or ""
  check("the ';' word arrived whole", wcap:find("word;", 1, true) ~= nil, wcap)
  check("no tmux command was started from it", run({ "test", "-e", pwned }).code ~= 0)
  if words then
    backend.close(words)
  end

  -- A ONE-word argv is data too: tmux would hand a lone argument to its default shell
  -- (`sh -c "<arg>"`), where `;` and `$(...)` are interpreted. The word names a program that does
  -- not exist; nothing it contains may run.
  local lone = "/tmp/terminal-nvim-live-lone"
  run({ "rm", "-f", lone })
  local single = backend.spawn({
    name = "single",
    root = "/live",
    cwd = "/tmp",
    layout = "split",
    split = { size = 0.3 },
    cmd = { "touch " .. lone .. "; sleep 20" },
    focus = false,
  })
  check("a one-word argv spawned", single ~= nil, single)
  vim.wait(1200)
  check("its ';' and spaces were not interpreted by a shell", run({ "test", "-e", lone }).code ~= 0)
  if single then
    backend.close(single)
  end

  check("the pane is visible and focused", backend.visible(h) == true and backend.focused(h))
  backend.hide(h)
  check("hide returns focus to Neovim's pane", backend.focused(h) == false)
  check("focus selects the pane again", backend.focus(h) == true and backend.focused(h) == true)
  check("list shows it", #backend.list() == 1)

  -- A directory whose name ends in ';' is still that directory (tmux reads a trailing ';' of -c as
  -- the end of the command).
  local odd_dir = "/tmp/terminal-nvim-live;cwd;"
  run({ "mkdir", "-p", odd_dir })
  local odd = backend.spawn({
    name = "odd",
    root = "/live",
    cwd = odd_dir,
    layout = "split",
    split = { size = 0.3 },
    cmd = { "sh", "-c", "pwd; sleep 20" },
    focus = false,
  })
  check("a pane in a ';'-named directory spawned", odd ~= nil, odd)
  local odd_cap = odd and pane_text_with(odd.pane, odd_dir) or ""
  check("it started in that directory", odd_cap:find(odd_dir, 1, true) ~= nil, odd_cap)
  if odd then
    backend.close(odd)
  end
  run({ "rm", "-rf", odd_dir })

  -- tmux expands the value of `-c` as a FORMAT (`#S`, `#{...}`, `#(...)`, `##` for a `#`): a
  -- directory called `C#` used to open the pane in $HOME without a word. Real directories with
  -- such names, and what tmux itself says the pane's directory is.
  local fmt_root = "/tmp/terminal-nvim-live-fmt"
  run({ "rm", "-rf", fmt_root })
  for n, case in ipairs({
    { name = "C#", layout = "split" },
    { name = "a##b", layout = "split" },
    { name = "#S", layout = "split" },
    { name = "#{pane_id}", layout = "split" },
    { name = "x#(echo hi)", layout = "split" },
    { name = "C#", layout = "tab" },
  }) do
    local dir = ("%s/%s"):format(fmt_root, case.name)
    local made = run({ "mkdir", "-p", dir })
    check("a directory named " .. case.name .. " was created", made.code == 0, made)
    local fmt = backend.spawn({
      name = "fmt" .. n,
      root = "/live",
      cwd = dir,
      layout = case.layout,
      split = { size = 0.3 },
      cmd = { "sleep", "20" },
      focus = false,
    })
    check(("a %s pane in %s spawned"):format(case.layout, dir), fmt ~= nil, fmt)
    if fmt then
      local where
      -- #{pane_current_path} follows the process, which needs a moment to start in the pane.
      vim.wait(3000, function()
        where =
          vim.trim(tmux("display-message", "-p", "-t", fmt.pane, "#{pane_current_path}").stdout)
        return where == dir
      end, 100)
      check(("it started in %s (tmux says %s)"):format(dir, where), where == dir, where)
      backend.close(fmt)
    end
  end
  run({ "rm", "-rf", fmt_root })

  -- Navigation hand-off at the edge: `select-pane -R` alone wraps around, the guarded form must not.
  local handoff = require("terminal.navigate.handoff").all.tmux
  local function hand_off(dir)
    local argv = handoff.argv(dir)
    local full = { "tmux", "-L", SOCKET }
    vim.list_extend(full, vim.list_slice(argv, 2))
    return run(full)
  end
  local function active_pane()
    return vim.trim(tmux("display-message", "-p", "-t", "live", "#{pane_id}").stdout)
  end
  backend.focus(h) -- the right-hand pane
  check("the terminal pane is the active one", active_pane() == h.pane, active_pane())
  hand_off("l")
  check("hand-off to the right at the right edge stays put", active_pane() == h.pane, active_pane())
  hand_off("h")
  check("hand-off to the left moves to the neighbour", active_pane() == own, active_pane())
  hand_off("h")
  check("hand-off to the left at the left edge stays put", active_pane() == own, active_pane())

  -- Status export as pane options on Neovim's own pane.
  local exporter = require("terminal.status.exporters.tmux")
  local saved_run, saved_pane = exporter.run, vim.env.TMUX_PANE
  vim.env.TMUX_PANE = own
  -- Test double: sends the exporter's tmux calls to the private socket of this script.
  ---@diagnostic disable-next-line: duplicate-set-field
  exporter.run = function(argv)
    -- argv[1] is "tmux": add the private socket
    local full = { "tmux", "-L", SOCKET }
    vim.list_extend(full, vim.list_slice(argv, 2))
    local r = run(full)
    return { code = r.code, stderr = r.stderr }
  end
  local published = exporter.publish(vim.json.encode({
    mode = "i",
    file = "main.lua",
    branch = "dev;",
    e = 2,
    w = 1,
    rec = "",
    mod = true,
  }))
  check("status publish succeeded", published == true)
  local mode = tmux("show-options", "-p", "-v", "-t", own, "@terminal_mode")
  local diag = tmux("show-options", "-p", "-v", "-t", own, "@terminal_diag")
  local fmt = tmux("display-message", "-p", "-t", own, "#{@terminal_file} #{@terminal_branch}")
  check("@terminal_mode is set", vim.trim(mode.stdout) == "i", mode)
  check("@terminal_diag is E2 W1", vim.trim(diag.stdout) == "E2 W1", diag)
  check(
    "a tmux format can read the options (a ';' value included)",
    vim.trim(fmt.stdout) == "main.lua dev;",
    fmt
  )
  exporter.clear()
  local cleared = tmux("show-options", "-p", "-v", "-t", own, "@terminal_mode")
  check("clear removes the options", vim.trim(cleared.stdout) == "", cleared)
  exporter.run, vim.env.TMUX_PANE = saved_run, saved_pane

  check("close kills the pane", backend.close(h) == true)
  vim.wait(300)
  check("the pane is gone", backend.visible(h) == false)
  check("nothing is left", #backend.list() == 0)
end)
if not ok then
  failed = true
  out[#out + 1] = "FAIL error: " .. tostring(err)
end
tmux("kill-server")
out[#out + 1] = failed and "RESULT failed" or "RESULT ok"
local f = io.open(vim.env.SMOKE_OUT or "terminal-tmux.txt", "w")
if f then
  f:write(table.concat(out, "\n") .. "\n")
  f:close()
end
vim.cmd("qa!")
