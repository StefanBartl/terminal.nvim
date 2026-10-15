# cmd

The Windows command prompt (`cmd.exe`). In a batch file `%f` is written `%%f`, and `%1` is the first argument. `<CR>` on a line types its command into the terminal.

## Pipes and redirection

| Command | What it does |
|---|---|
| `cmd1 \| cmd2` | output of cmd1 is the input of cmd2 |
| `cmd > file` | write the output to a file (overwrites) |
| `cmd >> file` | append to the file |
| `cmd 2> file` | write only the errors to a file |
| `cmd > file 2>&1` | output and errors to a file (the order matters) |
| `cmd 2>&1 \| more` | errors go through the pipe too |
| `cmd < file` | read the input from a file |
| `cmd > nul` | throw the output away |
| `cmd1 & cmd2` | run one after the other |
| `cmd1 && cmd2` | cmd2 only when cmd1 succeeded (`\|\|`: when it failed) |

## Filters

| Command | What it does |
|---|---|
| `findstr /s /n /i text *.md` | search recursively (`/s`), with line numbers (`/n`), any case (`/i`) |
| `findstr /v text file` | lines that do not contain `text` |
| `findstr /r "^a.*z$" file` | regular expression (a small dialect) |
| `find /c /v "" file` | count the lines of a file |
| `sort file` | sort the lines (`sort /r`: reversed) |
| `type file \| more` | page through a file |
| `more < file` | the same (`<Space>` next page, `q` quit) |
| `where name` | the paths of a program on the PATH |
| `for /f "tokens=1,2 delims=," %a in (file) do @echo %a %b` | split every line into fields |

## Variables and quoting

| Command | What it does |
|---|---|
| `set X=5` | set a variable (no spaces around `=`, they become part of the value) |
| `echo %X%` | use it |
| `set X=` | remove it |
| `set X` | show the variables that start with `X` (`set` alone: all of them) |
| `set /a n=1+2` | calculate |
| `set /p name=Name: ` | read a value from the keyboard |
| `setx X 1` | set it permanently for new windows |
| `echo %ERRORLEVEL%` | exit code of the last command |
| `echo a ^& b` | `^` takes the special meaning from the next character (`& \| < > ^`) |
| `setlocal enabledelayedexpansion` | in a batch file: `!X!` reads a variable inside a loop |

## Loops and conditions

| Command | What it does |
|---|---|
| `for %f in (*.md) do @echo %f` | loop over files |
| `for /l %i in (1,1,5) do @echo %i` | loop over a range (start, step, end) |
| `for /r %f in (*.lua) do @echo %f` | loop over files below the current directory |
| `for /d %d in (*) do @echo %d` | loop over directories |
| `if exist file echo yes` | test whether a file exists (`if not exist`) |
| `if "%X%"=="a" echo same` | compare strings (the quotes protect an empty value) |
| `if errorlevel 1 echo failed` | true when the exit code is 1 or more |
| `if %n% gtr 3 echo big` | compare numbers: `equ` `neq` `lss` `leq` `gtr` `geq` |
| `call :name args` | in a batch file: run the label `:name` as a subroutine |

## Paths and files

| Command | What it does |
|---|---|
| `cd /d D:\dir` | change directory and drive at once |
| `cd ..` | one directory up |
| `dir /a` | list including hidden files (`dir /s /b *.lua`: find files below here, bare names) |
| `copy a b` | copy a file |
| `xcopy a b /e /i` | copy a directory with its contents |
| `robocopy a b /mir` | mirror a directory (deletes in b what is not in a) |
| `move a b` | move or rename |
| `del /q file` | delete a file without asking |
| `rd /s /q dir` | remove a directory with its contents (no undo) |
| `mklink link target` | symbolic link (needs the right to create links) |
| `tree /f` | the directory tree, with files |

## Jobs and processes

| Command | What it does |
|---|---|
| `start notepad` | start a program in its own window, the prompt stays usable |
| `start /b cmd` | run in the background of this window |
| `tasklist` | list the processes |
| `tasklist \| findstr name` | find a process |
| `taskkill /im name.exe /f` | end processes by name (`/pid 123`: by number) |
| `timeout /t 5` | wait 5 seconds |
| `exit /b 1` | leave a batch file with an exit code |
| `<C-c>` | interrupt the running program |

## History and line editing

| Command | What it does |
|---|---|
| `doskey /history` | print the history |
| `<F7>` | the history as a list to choose from |
| `<F8>` | search the history for what you typed |
| `<F9>` | run the history entry with a given number |
| `<F3>` | type the previous command again |
| `<Esc>` | clear the line |
| `doskey ll=dir /a $*` | define a macro (`$*` stands for the arguments) |
| `cls` | clear the screen |

## Useful shortcuts

| Command | What it does |
|---|---|
| `help copy` | the documentation of a command (also `copy /?`) |
| `echo %PATH%` | the PATH |
| `set PATH=%PATH%;C:\tools` | extend the PATH for this window |
| `ver` | the Windows version |
| `ipconfig /all` | network settings |
| `chcp 65001` | switch the window to UTF-8 |
| `title name` | set the window title |
| `assoc .md` | which file type a file ending belongs to |
| `powershell -NoProfile` | start PowerShell from here |
