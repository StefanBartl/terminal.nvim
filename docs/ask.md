# Ask Neovim from a terminal

A program running in a terminal of terminal.nvim can ask **you** a question as a Neovim dialog
and get the answer back. This is for programs that have no terminal to ask on, above all
**git hooks**:

- git starts every hook with `/dev/null` as stdin;
- Git for Windows starts the hook's shell without any `/dev/tty` either -- not from lazygit, not
  from `git commit` typed into a terminal (measured 2026-10-28 with lazygit 0.61.1 and
  git 2.56.0.windows.4). A hook that asks "commit anyway?" can only abort there.

What does reach the hook is `$NVIM`, the address Neovim sets in every terminal it starts. lib.nvim
uses it: `lib.nvim.terminal.ask` shows the question in this Neovim, `bin/nvim-ask` is the client
a hook calls. terminal.nvim hands the client to its native terminals as **`$NVIM_ASK`**:

```sh
# in a hook or script started from a terminal.nvim terminal (or from lazygit in it)
choice="$(bash "$NVIM_ASK" --title " pre-commit " "2 files above 5 MB" \
  "Compress to .zip" "Commit anyway" "Abort")" || exit 1
```

Exit codes of `nvim-ask`: `0` answered (the choice on stdout), `1` dismissed, `2` no answer in
time (`--timeout`, default 120 s), `3` no Neovim to ask, `64` wrong usage. Neovim does not block
while the question is open; the dialog waits behind one that is already open. Details:
lib.nvim's `lua/lib/nvim/terminal/README.md`.

## Example: the large-files pre-commit hook

The pre-commit hook in the author's Neovim config (`scripts/git-hooks/pre-commit-large-files.sh`)
lists staged files above 5 MB and asks *Compress to .zip / Commit anyway / Abort*, then whether
to delete the compressed originals. It asks the terminal when `/dev/tty` opens (Linux, macOS) and
this Neovim through `nvim-ask` otherwise -- so a commit from lazygit on Windows gets the dialog
instead of an abort.

## Where it works

| Started from | `$NVIM` | `$NVIM_ASK` |
|---|---|---|
| a native terminal of terminal.nvim | yes | yes |
| lazygit (or anything) running in such a terminal | yes | yes |
| another Neovim terminal (`:terminal`, gitsuite's lazygit float) | yes | no -- a hook finds the script by asking Neovim (`require("lib.nvim.terminal.ask").script()`) |
| a tmux or WezTerm pane (`backend = "tmux"` / `"wezterm"`) | no | no -- the pane is not started by Neovim |

`ask.enable = false` stops handing out `$NVIM_ASK`; `env = { NVIM_ASK = ... }` overrides it.
`:checkhealth terminal` reports whether the bridge is there.
