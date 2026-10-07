# Tests

```sh
scripts/test.sh                 # every spec, on testing.nvim
scripts/test.sh --file native   # only spec files whose name contains "native"
```

The runner is [testing.nvim](https://github.com/StefanBartl/testing.nvim); `scripts/test.sh`
finds it and `lib.nvim` (`$TESTING_NVIM_DIR` / `$LIB_NVIM_DIR`, `.deps/`, a sibling checkout,
the plugin manager's folder) and exits non-zero when anything is missing or red.

| Spec | Covers |
|---|---|
| `config_spec.lua` | defaults, merge, validation |
| `layout_spec.lua` | pure window geometry |
| `quote_spec.lua` | shell quoting for POSIX / PowerShell / cmd.exe, hostile words |
| `registry_spec.lua` | registry, project/name resolution, backend detection |
| `native_spec.lua` | the native backend on real windows and jobs |
| `api_spec.lua` | the public facade |
| `bindings_spec.lua` | keymaps, autocommands, `:Terminal` |

## What the specs cannot do — and what covers it

A headless Neovim on **Windows** gives a terminal job a closed stdin: interactive shells
exit at once and writing to the job hangs the editor. So the specs use long-running
non-interactive programs (`support/jobs.lua`) and *record* what `send` would write.
`live/smoke.lua` does the real thing inside a real UI — run it before a release:

```sh
SMOKE_OUT=/tmp/terminal-smoke.txt nvim -u NONE -i NONE -c "luafile TESTS/live/smoke.lua"
```

## A Windows crash to know about

Neovim 0.12 on Windows can die with `0xC0000005` when a terminal is closed within a few
hundred milliseconds of a resize or of another terminal job ending. `support/jobs.lua`
`settle()` puts 400 ms in between wherever a spec does that; 300–500 ms of distance never
crashed. It is a Neovim/ConPTY timing issue, not something the plugin can fix.
