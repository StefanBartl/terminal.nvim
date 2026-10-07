# Quickstart

1. **Toggle a terminal.** Press `<A-h>` (or run `:Terminal`). A floating terminal opens in
   your project's root and you are in terminal mode. Press `<A-h>` again to hide it — the
   shell keeps running. `<Esc>` leaves terminal mode (so you can scroll and yank).
2. **A second terminal.** `3<A-h>` opens terminal "3"; `:Terminal open build` opens one
   named "build". Each project root has its own set.
3. **Run something.** `:Terminal run npm test` types the line into the "run" terminal and
   presses Enter. `:Terminal run --direct make test` starts it as the terminal's own job
   and keeps the window after it ends.
4. **Send text from a buffer.** `:Terminal send line` types the current line;
   `:'<,'>Terminal send selection` the selection; `:Terminal send file` the buffer. Nothing
   is executed until you add `--exec` (several lines need it, since each would run).
5. **Look around.** `:Terminal list` picks one of the project's terminals;
   `:checkhealth terminal` says what is detected.

From Lua: `require("terminal").toggle()`, `.open({ name = "build", layout = "vsplit" })`,
`.send(text, { newline = true })`, `.run({ "git", "status" })`.
