-- luacheck configuration for terminal.nvim
std = "luajit"

-- `luacheck .` walks everything under the repo root, including other
-- people's Lua: CI installs luacheck itself via luarocks into `.luarocks/`
-- and checks out its test dependencies under `.deps/`; locally, `.claude/` holds
-- sibling worktrees. Scanning those turned this gate into 257 warnings from
-- luarocks' own sources, enough to keep it red regardless of this repo.
exclude_files = {
  ".luarocks/",
  ".deps/",
  ".claude/",
}

-- `vim` is writable (we set vim.o.*, vim.bo[buf].* etc.); `read_globals` would
-- flag those field assignments as "setting a read-only field".
globals = { "vim" }
max_line_length = false

ignore = {
  "212/_.*", -- unused argument whose name starts with underscore
  "212/self", -- unused self
  "122", -- setting a read-only field of a global (e.g. vim.*): common in Neovim
}

-- Test specs use busted globals and partial config tables.
files["TESTS/**"] = {
  std = "luajit+busted",
  ignore = { "631", "211" },
}
