---@module 'terminal.core.tmux_word'
--- One data word as a tmux argument: typed text, a directory, the words of a command, an option
--- value. tmux's command parser ends a command at an argument that ends in `;` and turns a
--- trailing `\;` into `;`; a backslash in front of the final `;` makes it a literal again: `a;`
--- -> `a\;` (read as `a;`), `a\;` -> `a\\;` (read as `a\;`). Without it a bare word like
--- `select 1;` would lose its `;`, and a word like `notes;` followed by `run-shell` would start
--- another tmux command.
---
--- That is the escape for the *command parser*. The value of `-c` (the start directory) is also a
--- tmux *format*, which this does not know about: see `start_directory` in the tmux backend.
--- It lives in `core` because the tmux backend and the tmux status exporter both need it.

---@param s string
---@return string
return function(s)
  if s:sub(-1) == ";" then
    return s:sub(1, -2) .. "\\;"
  end
  return s
end
