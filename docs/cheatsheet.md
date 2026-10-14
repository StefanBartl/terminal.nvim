# Cheatsheet

`:Terminal cheat` shows a cheatsheet for the shell the terminal runs: pipes and redirection, filters, variables, loops, paths, jobs, history and shortcuts, one section at a time. It is a read-only Markdown float at the right edge of the editor, so the terminal it belongs to stays visible.

```vim
:Terminal cheat              " the sheet of the shell this terminal runs
:Terminal cheat powershell   " force a sheet
```

From Lua: `require("terminal").cheatsheet({ shell = "bash" })`. A key is off by default; give the action one to have it in terminal and normal mode: `keymaps = { cheatsheet = "<A-?>" }`. Called while the window is open (the key works inside it too), the command closes it instead of opening a second one.

## Keys in the window

| Key | What it does |
|---|---|
| `]]` `<Tab>` | next section (after the last comes the first) |
| `[[` `<S-Tab>` | previous section |
| `/` | search **all** sections of the sheet; the first match from the current section on is shown |
| `n` `N` | next / previous match |
| `g?` | the `common` sheet; again: back to the shell's |
| `s` | pick another sheet |
| `<CR>` | type the command of a table row into the terminal (no Enter, nothing runs) and close |
| `q` `<Esc>` | close; the cursor goes back where it was, in terminal mode when it came from there |

`<CR>` types the first code span of the row's first cell. Rows whose span is a key (`<C-r>`) or a Neovim command (`:Terminal list`) have nothing to type; prose is never typed, and neither is a span with a control character in it (a sheet can come from a folder someone else filled, and `^O` would run the line in readline). The command goes to the terminal the sheet was opened from, else to the `run` terminal.

## Which sheet

1. `cheatsheet.shell`, or the argument of `:Terminal cheat`.
2. A multiplexer pane (tmux, WezTerm backend): `common`, because its shell is not known here.
3. A native terminal: by the program it runs, else by the configured `shell` / Neovim's `'shell'`.

`pwsh` and `powershell` give the PowerShell sheet; `bash`, `sh`, `dash`, `ash` and `ksh` the bash sheet; `zsh` uses the bash sheet too; `fish`, `cmd` and any other program the `common` sheet. A shell without a sheet of its own is answered by the related one and, last, by `common`.

## Sheets are Markdown files

`docs/cheatsheets/<shell>.md` in the plugin: `common`, `bash`, `powershell`. A sheet is `# Title`, an optional introduction (shown as the section `About`) and one `## Section` per topic; the commands sit in tables, in the first cell, as code:

```markdown
# fish

## Pipes and redirection
| Command | What it does |
|---|---|
| `cmd1 \| cmd2` | output of cmd1 is the input of cmd2 |
```

A `|` inside code in a table cell is written `\|`.

Your own sheets:

```lua
require("terminal").setup({
  cheatsheet = {
    dir = "~/notes/cheatsheets",                -- <shell>.md files here win over the built-in ones
    shells = { fish = "~/notes/my-fish.md" },   -- a file for one shell (wins over `dir`)
    shell = "",                                 -- "bash" forces a sheet for every terminal
  },
})
```

A file that cannot be read or has no text is skipped for the next one of the same shell (your empty `bash.md` shows the built-in sheet). A shell name may contain letters, digits, `_` and `-` only.
