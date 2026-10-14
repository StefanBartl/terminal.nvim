# Common

What holds in (almost) every shell. `<CR>` on a line types its command into the terminal; `g?` switches back to the sheet of your shell, `s` picks another.

## In terminal.nvim

| Key / command | What it does |
|---|---|
| `<Esc>` or `<C-c>` | leave terminal mode (scroll, yank, search with `/`) |
| `i` | back into terminal mode |
| `<C-h>` `<C-j>` `<C-k>` | move to the window left / below / above (hands off to tmux / WezTerm at the edge) |
| `<A-h>` | show / hide the terminal; `3<A-h>` is terminal "3" |
| `:Terminal list` | pick a terminal: open, close (`<C-x>`), send a line (`<C-s>`) |
| `:Terminal run make test` | type a line into the run terminal and press Enter |
| `:Terminal send line` | type the current line (add `--exec` to press Enter) |
| `:Terminal cheat` | this cheatsheet |

## Moving around

| Command | What it does |
|---|---|
| `pwd` | where am I (`Get-Location` in PowerShell, the same alias works there) |
| `cd path` | go to a directory |
| `cd -` | back to the previous directory (bash, zsh, PowerShell 7) |
| `cd` | home directory (bash, zsh) |
| `ls` | list the directory (alias in PowerShell) |
| `cat file` | print a file (alias in PowerShell) |
| `mkdir name` | create a directory |

## Keys of the line editor

| Key | What it does |
|---|---|
| `<C-c>` | interrupt the running program |
| `<C-d>` | end of input / leave the shell on an empty line |
| `<C-l>` | clear the screen (stays the shell's own in terminal.nvim) |
| `<C-a>` `<C-e>` | start / end of the line (bash, zsh) |
| `<C-r>` | search the history backwards |
| `<Up>` `<Down>` | walk through the history |
| `<Tab>` | complete a name; twice lists the candidates |

## Words that mean the same everywhere

| Word | Meaning |
|---|---|
| `.` and `..` | this directory / the one above |
| `~` | the home directory (bash, zsh, PowerShell) |
| `*` `?` | wildcards in file names |
| `\|` | pipe: the output of one program is the input of the next |
| `>` `>>` | write / append the output to a file |
| `exit` | leave the shell |
