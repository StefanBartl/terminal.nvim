# bash

bash and the shells close to it (`sh`, `dash`, `zsh`, `ksh`); where zsh differs, the line says so. `<CR>` on a line types its command into the terminal.

## Pipes and redirection

| Command | What it does |
|---|---|
| `cmd1 \| cmd2` | output of cmd1 is the input of cmd2 |
| `cmd > file` | write the output to a file (overwrites) |
| `cmd >> file` | append to the file |
| `cmd 2> file` | write only the errors to a file |
| `cmd &> file` | output and errors to a file (bash, zsh) |
| `cmd 2>&1 \| less` | errors go through the pipe too |
| `cmd < file` | read the input from a file |
| `cmd \| tee file` | show and write at the same time |
| `diff <(cmd1) <(cmd2)` | use the output of a command as a file name (bash, zsh) |

## Filters

| Command | What it does |
|---|---|
| `grep -rn text .` | search recursively, with line numbers |
| `grep -v text` | lines that do not match |
| `sort \| uniq -c \| sort -rn` | count how often each line occurs |
| `cut -d, -f2` | the second comma-separated column |
| `awk '{print $1}'` | the first whitespace-separated field |
| `sed 's/a/b/g'` | replace a with b |
| `head -n 20` | the first 20 lines (`tail -n 20`: the last) |
| `wc -l` | count lines |
| `xargs -I{} cmd {}` | run cmd for every input line |
| `find . -name '*.lua'` | find files by name |

## Variables and quoting

| Command | What it does |
|---|---|
| `x=5` | set a variable (no spaces around `=`) |
| `echo "$x"` | use it, always in double quotes |
| `echo '$x'` | single quotes: no expansion at all |
| `echo "${x:-default}"` | the value, or `default` when unset or empty |
| `n=$(cmd)` | the output of a command |
| `export X=1` | pass the variable on to programs |
| `echo $?` | exit code of the last command |
| `echo "${#x}"` | length of the value |
| `set -euo pipefail` | stop on errors and unset variables (scripts) |

## Loops and conditions

| Command | What it does |
|---|---|
| `for f in *.md; do echo "$f"; done` | loop over files |
| `while read -r line; do echo "$line"; done < file` | loop over the lines of a file |
| `if [ -f file ]; then echo yes; fi` | test (`-f` file, `-d` directory, `-z` empty string) |
| `[[ $x == a* ]] && echo match` | pattern test (bash, zsh) |
| `cmd1 && cmd2` | cmd2 only when cmd1 succeeded |
| `cmd1 \|\| cmd2` | cmd2 only when cmd1 failed |
| `case "$x" in a) echo A;; *) echo other;; esac` | choose by pattern |

## Paths and files

| Command | What it does |
|---|---|
| `ls -la` | list with details, including hidden files |
| `cp -r a b` | copy (recursive) |
| `mv a b` | move or rename |
| `rm -r dir` | remove a directory (no undo) |
| `ln -s target link` | symbolic link |
| `basename path` | the last component (`dirname`: the rest) |
| `du -sh *` | size of each entry |
| `chmod +x file` | make a file executable |

## Jobs and processes

| Command | What it does |
|---|---|
| `cmd &` | run in the background |
| `jobs` | list background jobs |
| `fg` | bring the last job to the front |
| `<C-z>` then `bg` | suspend, then continue in the background |
| `ps aux \| grep name` | find a process |
| `kill pid` | ask a process to end (`kill -9`: force) |
| `wait` | wait for the background jobs |
| `nohup cmd &` | keep running after the shell ends |

## History and line editing

| Command | What it does |
|---|---|
| `history \| tail` | the latest commands |
| `!!` | the previous command again |
| `!$` | the last word of the previous command |
| `<C-r>` | search the history while typing |
| `<C-w>` | delete the word before the cursor |
| `<C-u>` | delete to the start of the line |
| `<A-.>` | insert the last word of the previous command |

## Useful shortcuts

| Command | What it does |
|---|---|
| `type name` | what is `name`: alias, function or program |
| `command -v name` | path of a program (script-friendly) |
| `alias ll='ls -la'` | define a short name |
| `source file` | run a file in this shell |
| `time cmd` | how long a command takes |
| `watch -n 2 cmd` | repeat a command every 2 seconds |
| `echo $PATH \| tr ':' '\n'` | the PATH, one entry per line |
| `cd "$(dirname "$0")"` | in a script: go to its own directory |
