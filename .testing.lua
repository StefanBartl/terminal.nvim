-- .testing.lua -- configuration of testing.nvim for this project.
-- Every key is optional; the keys are documented in testing.nvim's docs/CONFIG.md. Loading this
-- file executes it (same trust as running the specs).
return {
  -- Lua module root of the project.
  plugin = "terminal",
  -- How the spec files are run: "auto" = sniffed per file.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath.
  deps = { "lib.nvim" },
  -- One nvim per spec file: nothing leaks from one file into the next (terminal jobs, windows).
  isolated = "file",
  host = "c",
  -- A case without assertions fails: a spec that asserts nothing proves nothing.
  assertions = "error",
  guards = {
    fs = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- The native backend starts real shell jobs in specs that exercise it, so process_net stays
    -- at its default; specs for the pure core never start one.
  },
}
