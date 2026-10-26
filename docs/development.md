# Development

The checks a change has to pass, and the tools behind them. All run from the repository root.

| Check | Command | Needs |
|---|---|---|
| Format | `stylua --check .` | [StyLua](https://github.com/JohnnyMorganz/StyLua) |
| Lint | `luacheck .` | [luacheck](https://github.com/lunarmodules/luacheck) |
| Specs | `scripts/test.sh` (`--file <part of a name>`, `--filter <text>`) | [testing.nvim](https://github.com/WKDSteve/testing.nvim), [lib.nvim](https://github.com/WKDSteve/lib.nvim) |
| Types | `scripts/luals-check.sh` | `lua-language-server`, lib.nvim, testing.nvim |
| Module map and layer rules | `nvim --headless -l scripts/gen_map.lua` | [docmap.nvim](https://github.com/WKDSteve/docmap.nvim) (dev dependency), lib.nvim |

lib.nvim, testing.nvim and docmap.nvim are found through `$LIB_NVIM_DIR`, `$TESTING_NVIM_DIR`,
`$DOCMAP_NVIM_DIR`, then `.deps/<name>`, then a sibling checkout. CI checks them out into `.deps/`.

## Types

`scripts/luals-check.sh` runs the language server over `lua/` and `TESTS/` and fails on any finding at
Warning level. The target is **zero**, and it is zero today. The library paths (Neovim's runtime,
lib.nvim, testing.nvim) differ per machine, so the script writes a throw-away config instead of
`.luarc.json` carrying them. `vim` stays a known global in `.luarc.json` deliberately: the runtime
library is not part of this repository. The specs' own globals (`describe`, `it`, the hooks) are
declared in `TESTS/support/busted_meta.lua`, which is never loaded.

## Module map

`scripts/gen_map.lua` is docmap.nvim's script with this repository's options at the bottom;
`.docmap.json` holds the facts about the tree. It writes `docs/map/` (ignored by git, derived output)
and exits non-zero on an error-level finding. The **layer rules** in `.docmap.json` are the part CI
enforces (job `map`): `terminal.core` does not reach into `backends`, `bindings` or `status`, and a
backend does not know `bindings`. Use `--check` only where a committed map exists; here there is none.

`doc-references-missing` is set to `info` on purpose: the autocommand groups in `docs/BINDINGS.md`
(`terminal.native`, `terminal.usrcmds`, ...) are names, not modules, and read as module references.
