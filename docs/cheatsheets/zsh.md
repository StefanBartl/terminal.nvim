# zsh

zsh in the form of its defaults and the usual `setopt`s. The basics it shares with bash (`$(cmd)`, `[[ ]]`, `&&`, `for ... do ... done`) are on the `bash` sheet (`s`, then `bash`); this sheet lists what zsh does its own way. `<CR>` on a line types its command into the terminal.

## Pipes and redirection

| Command | What it does |
|---|---|
| `cmd1 \| cmd2` | output of cmd1 is the input of cmd2 |
| `cmd1 \|& cmd2` | output and errors through the pipe |
| `cmd >! file` | overwrite even when `noclobber` is set (`>>!` appends) |
| `cmd &> file` | output and errors to a file |
| `cmd > a > b` | write to several files at once (`multios`, on by default) |
| `cmd \| tee a b` | show and write to several files |
| `diff <(cmd1) <(cmd2)` | the output of a command as a file name |
| `diff =(cmd1) =(cmd2)` | the same through a temporary file (for programs that need a real file) |
| `cmd < file` | read the input from a file |

## Filters

| Command | What it does |
|---|---|
| `grep -rn text .` | search recursively, with line numbers |
| `ls **/*.lua` | recursive glob: every `.lua` file below here |
| `ls *.(png\|jpg)` | glob with alternatives |
| `ls *(.)` | only regular files (`*(/)`: only directories, `*(@)`: links) |
| `ls -d *(om[1,5])` | the five most recently modified entries |
| `ls *(.L+1m)` | files larger than 1 MB |
| `print -l *.md(:t)` | the file names without directory, one per line |
| `sort \| uniq -c \| sort -rn` | count how often each line occurs |
| `awk '{print $1}'` | the first whitespace-separated field |

## Variables and quoting

| Command | What it does |
|---|---|
| `x=5` | set a variable (no spaces around `=`) |
| `echo $x` | a variable is not word-split, quoting is needed less often than in bash |
| `a=(one two three)` | an array |
| `echo $a[1]` | arrays start at 1 (`$a[-1]` is the last) |
| `echo ${#a}` | number of elements (`${#x}`: length of a string) |
| `echo ${x:u}` | upper case (`${x:l}`: lower case) |
| `echo ${(j:,:)a}` | join the elements with a comma (`${(s:,:)x}` splits) |
| `typeset -A m; m[k]=v` | an associative array |
| `export X=1` | pass the variable on to programs |
| `echo $?` | exit code of the last command (`$pipestatus`: of every part of a pipe) |

## Loops and conditions

| Command | What it does |
|---|---|
| `for f in *.md; do echo $f; done` | loop over files |
| `for i in {1..5}; do echo $i; done` | loop over a range |
| `for k v in ${(kv)m}; do echo $k $v; done` | loop over keys and values of an associative array |
| `repeat 3 echo hi` | repeat a command |
| `if [[ -f file ]]; then echo yes; fi` | test (`-f` file, `-d` directory, `-z` empty string) |
| `[[ $x == a* ]] && echo match` | pattern test |
| `[[ $x =~ ^a.c$ ]] && echo $MATCH` | regular expression, the match is in `$MATCH` |
| `case $x in a) echo A;; *) echo other;; esac` | choose by pattern |
| `while read -r line; do echo $line; done < file` | loop over the lines of a file |

## Paths and files

| Command | What it does |
|---|---|
| `setopt autocd` | typing a directory name changes into it |
| `setopt auto_pushd` | every `cd` pushes the old directory on a stack |
| `dirs -v` | the directory stack, numbered (`cd -2` goes to entry 2) |
| `cd -` | back to the previous directory |
| `echo ${PWD:t}` | the last component of a path (`:h` the rest, `:r` without extension, `:e` extension) |
| `mv file.{txt,bak}` | brace expansion: rename `file.txt` to `file.bak` |
| `cp -r a b` | copy (recursive) |
| `rm -r dir` | remove a directory (no undo) |
| `ln -s target link` | symbolic link |
| `du -sh *(/)` | size of each directory |

## Jobs and processes

| Command | What it does |
|---|---|
| `cmd &` | run in the background |
| `cmd &!` | run in the background and detach from the shell (survives closing it) |
| `jobs` | list background jobs |
| `fg %1` | bring job 1 to the front |
| `bg` | continue the suspended job in the background |
| `disown %1` | forget a job (the shell will not signal it on exit) |
| `kill %1` | end a job (`kill -9 pid`: force) |
| `wait` | wait for the background jobs |
| `ps aux \| grep name` | find a process |

## History and line editing

| Command | What it does |
|---|---|
| `history 1` | the whole history, numbered |
| `!!` | the previous command again |
| `!$` | the last word of the previous command |
| `^old^new` | the previous command with `old` replaced by `new` |
| `fc -ln -1` | the previous command as text |
| `setopt share_history` | histories of all open shells are shared |
| `<C-r>` | search the history while typing |
| `autoload -Uz edit-command-line; zle -N edit-command-line; bindkey '^x^e' edit-command-line` | make `<C-x><C-e>` edit the line in `$EDITOR` (not bound by default) |
| `<A-.>` | insert the last word of the previous command |

## Useful shortcuts

| Command | What it does |
|---|---|
| `whence -v name` | what is `name`: alias, function or program |
| `alias -g L='\| less'` | a global alias: `cmd L` expands anywhere in the line |
| `print -l $path` | the PATH, one entry per line (`$path` is an array) |
| `source ~/.zshrc` | load the configuration again |
| `autoload -Uz compinit && compinit` | switch on completion |
| `bindkey -e` | emacs keymap (`bindkey -v`: vi) |
| `setopt` | list the options that are on |
| `time cmd` | how long a command takes |
| `zmv '(*).txt' '$1.md'` | rename many files (`autoload -U zmv` first) |
