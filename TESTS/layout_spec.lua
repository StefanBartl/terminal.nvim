---@diagnostic disable: need-check-nil, undefined-field
-- TESTS/layout_spec.lua -- terminal.core.layout (pure geometry)

local layout = require("terminal.core.layout")

describe("terminal.core.layout", function()
  describe("resolve_size", function()
    it("treats 0 < x <= 1 as a fraction", function()
      assert.equals(40, layout.resolve_size(0.5, 80, 0.8))
      assert.equals(80, layout.resolve_size(1, 80, 0.8))
    end)

    it("treats x > 1 as absolute cells, clamped to the total", function()
      assert.equals(30, layout.resolve_size(30, 80, 0.8))
      assert.equals(80, layout.resolve_size(500, 80, 0.8))
    end)

    it("falls back to the default for unusable values", function()
      assert.equals(64, layout.resolve_size(0, 80, 0.8))
      assert.equals(64, layout.resolve_size(-3, 80, 0.8))
      assert.equals(64, layout.resolve_size(nil, 80, 0.8))
      assert.equals(64, layout.resolve_size("big", 80, 0.8))
      assert.equals(64, layout.resolve_size(0 / 0, 80, 0.8))
    end)

    it("never returns less than min, nor more than the total", function()
      assert.equals(5, layout.resolve_size(0.01, 80, 0.8, 5))
      assert.equals(3, layout.resolve_size(0.5, 3, 0.8, 10))
    end)
  end)

  describe("float", function()
    it("centres the window and subtracts the border from the content", function()
      local g = layout.float(100, 42, { width = 0.8, height = 0.5, border = "rounded" })
      -- usable lines = 40; outer 80x20; content 78x18
      assert.same({ row = 10, col = 10, width = 78, height = 18 }, g)
    end)

    it("keeps the content at the full size without a border", function()
      local g = layout.float(100, 42, { width = 0.8, height = 0.5, border = "none" })
      assert.equals(80, g.width)
      assert.equals(20, g.height)
    end)

    it("survives a tiny editor", function()
      local g = layout.float(10, 4, { width = 0.8, height = 0.8, border = "rounded" })
      assert.is_true(g.width >= 1 and g.height >= 1)
      assert.is_true(g.row >= 0 and g.col >= 0)
    end)
  end)

  describe("split", function()
    it("sizes a horizontal split along the lines and a vertical one along the columns", function()
      assert.equals(12, layout.split("split", 100, 42, 0.3))
      assert.equals(30, layout.split("vsplit", 100, 42, 0.3))
    end)
  end)
end)
