#!/usr/bin/env bash
#
# Runs lua-language-server over the repository (lua/ and TESTS/) and fails on any finding at
# Warning level or above. The library paths differ per machine, so they are not in .luarc.json:
# this script writes a throw-away config with Neovim's runtime, lib.nvim and testing.nvim.
#
#   scripts/luals-check.sh            # exit 0: no findings; exit 1: findings (printed) or no tool
#
# lib.nvim and testing.nvim are found like in scripts/test.sh: $LIB_NVIM_DIR / $TESTING_NVIM_DIR,
# then .deps/<name>, then a sibling checkout.

set -euo pipefail
cd "$(dirname "$0")/.."

command -v lua-language-server >/dev/null || { echo "luals-check: lua-language-server not found" >&2; exit 1; }
command -v nvim >/dev/null || { echo "luals-check: nvim not found" >&2; exit 1; }

dep() { # name, env value
  local name=$1 env=${2:-}
  for c in "$env" ".deps/$name" "../$name"; do
    [ -n "$c" ] && [ -d "$c/lua" ] && { (cd "$c" && { pwd -W 2>/dev/null || pwd; }); return; }
  done
  echo "luals-check: $name not found (set its _DIR variable, or clone it to .deps/$name)" >&2
  exit 1
}

# forward slashes: a Windows path with backslashes is not valid inside the JSON below
runtime=$(nvim --headless -u NONE -c 'lua io.stdout:write(vim.env.VIMRUNTIME)' -c q 2>&1)
runtime=${runtime//\\//}
lib=$(dep lib.nvim "${LIB_NVIM_DIR:-}")
testing=$(dep testing.nvim "${TESTING_NVIM_DIR:-}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/luarc.json" <<JSON
{
  "runtime.version": "LuaJIT",
  "runtime.path": ["lua/?.lua", "lua/?/init.lua"],
  "diagnostics.globals": [],
  "diagnostics.unusedLocalExclude": ["_*"],
  "workspace.checkThirdParty": false,
  "workspace.ignoreDir": [".claude", ".deps", "docs"],
  "workspace.library": ["$runtime/lua", "$lib/lua", "$testing/lua"]
}
JSON

lua-language-server --check . --configpath "$work/luarc.json" --checklevel Warning \
  --logpath "$work/log" --check_out_path "$work/out.json" > "$work/report.txt" 2>&1 || true

if [ "$(tr -d '[:space:]' < "$work/out.json" 2>/dev/null)" = "[]" ]; then
  echo "luals-check: no findings"
else
  cat "$work/report.txt"
  exit 1
fi
