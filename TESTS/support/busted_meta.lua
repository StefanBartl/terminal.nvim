---@meta
-- TESTS/support/busted_meta.lua -- types for the globals the specs get from the runner
-- (testing.nvim, dialect `busted`). Never loaded: it exists so the language server knows
-- `describe`, `it` and the hooks and reports nothing for them. `assert` is Lua's own global; the
-- luassert fields hanging off it (`assert.equals` ...) are covered by the per-file
-- `---@diagnostic disable` line at the top of each spec.

---@param name string
---@param fn fun()
function describe(name, fn) end

---@param name string
---@param fn fun()
function it(name, fn) end

---@param name string
---@param fn? fun()
function pending(name, fn) end

---@param fn fun()
function before_each(fn) end

---@param fn fun()
function after_each(fn) end

---@param fn fun()
function setup(fn) end

---@param fn fun()
function teardown(fn) end
