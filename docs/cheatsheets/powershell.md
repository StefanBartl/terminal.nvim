# PowerShell

Windows PowerShell 5.1 and PowerShell 7 (`pwsh`); a line says so where 7 is needed. The big difference to bash: the pipe carries **objects**, not text. `<CR>` on a line types its command into the terminal.

## Pipes and redirection

| Command | What it does |
|---|---|
| `Get-ChildItem \| Where-Object Length -gt 1mb` | objects go through the pipe, with their properties |
| `cmd > file` | write the output to a file (UTF-16 in 5.1, UTF-8 in 7) |
| `cmd >> file` | append to the file |
| `cmd 2> file` | write only the errors to a file |
| `cmd *> file` | all streams (output, errors, warnings, verbose) to a file |
| `cmd 2>&1` | errors into the output stream |
| `cmd \| Out-File file -Encoding utf8` | write with a chosen encoding |
| `cmd \| Tee-Object file` | show and write at the same time |
| `cmd \| Out-String` | the formatted output as one string |
| `cmd \| Out-Host -Paging` | page through the output |

## Filters

| Command | What it does |
|---|---|
| `Where-Object { $_.Length -gt 1kb }` | keep objects for which the block is true (alias `?`) |
| `Select-Object Name, Length` | keep only some properties |
| `Select-Object -First 5` | the first 5 objects (`-Last 5`: the last) |
| `Sort-Object Length -Descending` | sort by a property |
| `Group-Object Extension` | group by a property |
| `ForEach-Object { $_.Name }` | run a block for every object (alias `%`) |
| `Select-String text -Path *.md` | search in files, like grep |
| `Measure-Object -Sum Length` | count, sum, average |
| `Get-Content file \| Select-Object -First 20` | the first 20 lines of a file |
| `Format-Table -AutoSize` | show as a table (`Format-List` for all properties) |

## Variables and quoting

| Command | What it does |
|---|---|
| `$x = 5` | set a variable |
| `"value: $x"` | double quotes expand variables |
| `'value: $x'` | single quotes are literal |
| `"sum: $($a + $b)"` | an expression inside a string |
| `$env:PATH` | an environment variable (`$env:X = "1"` sets it for this session) |
| `$x = Get-Date` | the value of any command |
| `$?` | success of the last command (`$LASTEXITCODE`: exit code of a program) |
| `[int]$n = "5"` | a typed variable |
| `$null` | no value |
| `Get-Variable` | list the variables |

## Loops and conditions

| Command | What it does |
|---|---|
| `foreach ($f in Get-ChildItem *.md) { $f.Name }` | loop over objects |
| `1..5 \| ForEach-Object { $_ * 2 }` | loop over a range |
| `if (Test-Path file) { "yes" } else { "no" }` | condition |
| `while ($i -lt 3) { $i++ }` | while loop |
| `$a -eq $b` | compare: `-eq` `-ne` `-gt` `-lt` `-ge` `-le` (case-insensitive) |
| `$s -like "a*"` | wildcard match (`-match` for a regex) |
| `$a -and $b` | logic: `-and` `-or` `-not` |
| `cmd1 && cmd2` | cmd2 only when cmd1 succeeded (PowerShell 7) |
| `try { cmd } catch { $_.Exception.Message }` | handle an error |
| `switch ($x) { 1 { "one" } default { "other" } }` | choose by value |

## Paths and files

| Command | What it does |
|---|---|
| `Get-ChildItem -Force` | list including hidden files (alias `ls`, `dir`, `gci`) |
| `Get-ChildItem -Recurse -Filter *.lua` | find files by name |
| `Copy-Item a b -Recurse` | copy (alias `cp`) |
| `Move-Item a b` | move or rename (alias `mv`) |
| `Remove-Item dir -Recurse` | remove (alias `rm`; no undo, `-WhatIf` shows what would happen) |
| `New-Item -ItemType Directory name` | create a directory (alias `mkdir`) |
| `Test-Path file` | does it exist |
| `Join-Path $a $b` | build a path |
| `Split-Path $p -Leaf` | the last component (`-Parent`: the rest) |
| `Resolve-Path .` | the full path |
| `Set-Location -` | back to the previous directory (PowerShell 7; alias `cd -`) |

## Jobs and processes

| Command | What it does |
|---|---|
| `Get-Process` | list the processes (alias `ps`) |
| `Get-Process name \| Stop-Process` | end a process (`Stop-Process -Id 123 -Force`) |
| `Start-Process notepad` | start a program separately |
| `Start-Job { cmd }` | run a block in the background |
| `Get-Job` | list the background jobs |
| `Receive-Job 1 -Keep` | the output of job 1 |
| `cmd &` | run in the background (PowerShell 7) |
| `Wait-Job *` | wait for the jobs |
| `Get-Command name` | where does `name` come from |

## History and line editing

| Command | What it does |
|---|---|
| `Get-History` | the commands of this session |
| `Invoke-History 5` | run entry 5 again (alias `r`) |
| `<C-r>` | search the history while typing (PSReadLine) |
| `<Up>` `<Down>` | walk through the history |
| `(Get-PSReadLineOption).HistorySavePath` | the file that keeps the history across sessions |
| `<C-Left>` `<C-Right>` | move by word |
| `<Esc>` | clear the line |
| `<F2>` | choose from a list of completions (PSReadLine, 7.2+) |

## Useful shortcuts

| Command | What it does |
|---|---|
| `Get-Help Get-ChildItem -Examples` | examples of a command |
| `Get-Alias ls` | what an alias stands for |
| `Get-Member` | the properties and methods of what comes through the pipe |
| `$PROFILE` | the path of your profile script |
| `. $PROFILE` | load the profile again |
| `Measure-Command { cmd }` | how long a command takes |
| `$env:PATH -split ';'` | the PATH, one entry per line |
| `Clear-Host` | clear the screen (alias `cls`) |
