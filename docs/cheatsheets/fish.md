# fish

fish 3 (3.5 or newer for the `path` command). fish is not POSIX: command substitution is `(cmd)` and splits at newlines only, there is no `export`, no `fi`/`done`; blocks end with `end`. `<CR>` on a line types its command into the terminal.

## Pipes and redirection

| Command | What it does |
|---|---|
| `cmd1 \| cmd2` | output of cmd1 is the input of cmd2 |
| `cmd > file` | write the output to a file (overwrites) |
| `cmd >> file` | append to the file |
| `cmd 2> file` | write only the errors to a file |
| `cmd &> file` | output and errors to a file |
| `cmd 2>&1 \| less` | errors go through the pipe too |
| `cmd < file` | read the input from a file |
| `cmd \| tee file` | show and write at the same time |
| `diff (cmd1 \| psub) (cmd2 \| psub)` | the output of a command as a file name |

## Filters

| Command | What it does |
|---|---|
| `grep -rn text .` | search recursively, with line numbers |
| `string match -r 'a.c' $x` | regular-expression match (without `-r`: wildcard match) |
| `string replace -a a b $x` | replace every a with b (`-r` for a regular expression) |
| `string split , $x` | split at commas, one list element each |
| `string join , $list` | join the elements with a comma |
| `string trim $x` | cut whitespace at both ends |
| `string length $x` | length of a string |
| `sort \| uniq -c \| sort -rn` | count how often each line occurs |
| `count $list` | number of elements |
| `ls **/*.lua` | recursive glob: every `.lua` file below here |

## Variables and quoting

| Command | What it does |
|---|---|
| `set x 5` | set a variable (`set -l` local, `set -g` global, `set -U` universal: kept across sessions) |
| `echo $x` | use it; a variable is never word-split, so quoting is rarely needed |
| `set -gx X 1` | export to programs (fish has no `export`) |
| `set -e x` | erase a variable |
| `set a 1 2 3` | a variable is a list |
| `echo $a[1]` | lists start at 1 (`$a[-1]` is the last, `$a[2..3]` a slice) |
| `set n (cmd)` | the output of a command (`$(cmd)` works since 3.4) |
| `echo $status` | exit code of the last command (`$pipestatus` for every part of a pipe) |
| `fish_add_path ~/bin` | put a directory on the PATH (`$PATH` is a list) |
| `echo "a $x b"` | double quotes expand variables, single quotes are literal |

## Loops and conditions

| Command | What it does |
|---|---|
| `for f in *.md; echo $f; end` | loop over files |
| `for i in (seq 5); echo $i; end` | loop over a range |
| `while read -l line; echo $line; end < file` | loop over the lines of a file |
| `if test -f file; echo yes; end` | test (`-f` file, `-d` directory, `-z` empty string) |
| `test $x = a; and echo same` | `and` runs when the last command succeeded (`or` when it failed) |
| `cmd1 && cmd2` | cmd2 only when cmd1 succeeded |
| `cmd1 \|\| cmd2` | cmd2 only when cmd1 failed |
| `switch $x; case a; echo A; case '*'; echo other; end` | choose by pattern |
| `function hi; echo hello $argv; end` | define a function (`$argv` holds the arguments) |
| `begin; cmd1; cmd2; end \| less` | group commands |

## Paths and files

| Command | What it does |
|---|---|
| `cd -` | back to the previous directory (`prevd` and `nextd` walk the history) |
| `dirh` | the directory history |
| `ls -la` | list with details, including hidden files |
| `path basename $f` | the last component (`path dirname`: the rest, `path extension`: the extension) |
| `path resolve .` | the full path |
| `cp -r a b` | copy (recursive) |
| `mkdir -p a/b` | create a directory with its parents |
| `rm -r dir` | remove a directory (no undo) |
| `ln -s target link` | symbolic link |
| `du -sh *` | size of each entry |

## Jobs and processes

| Command | What it does |
|---|---|
| `cmd &` | run in the background |
| `jobs` | list background jobs |
| `fg` | bring the last job to the front |
| `bg` | continue the suspended job in the background |
| `disown` | forget the job (it survives closing the shell) |
| `kill %1` | end job 1 (`kill -9 pid`: force) |
| `wait` | wait for the background jobs |
| `ps aux \| grep name` | find a process |
| `time cmd` | how long a command takes |

## History and line editing

| Command | What it does |
|---|---|
| `history \| head` | the latest commands |
| `history search text` | commands that contain `text` |
| `history delete --contains text` | remove entries from the history |
| `<Up>` | with text typed: walk through the commands that start with it |
| `<C-r>` | search the history in a list |
| `<Right>` | accept the grey autosuggestion (`<A-Right>`: one word) |
| `<A-.>` | insert the last word of the previous command |
| `<A-e>` | edit the line in `$EDITOR` |
| `<A-Up>` | search the words of the history |

## Useful shortcuts

| Command | What it does |
|---|---|
| `type name` | what is `name`: function, builtin or program |
| `functions name` | show the source of a function (`funced name` edits, `funcsave name` keeps it) |
| `abbr -a gst git status` | an abbreviation: `gst` expands to the full text as you type |
| `alias ll 'ls -la'` | define a short name (creates a function) |
| `source ~/.config/fish/config.fish` | load the configuration again |
| `fish_config` | configure colors and prompt in a browser |
| `contains -- a $list` | is `a` in the list |
| `set --show x` | where and how a variable is set |
| `help name` | open the documentation of a command |
