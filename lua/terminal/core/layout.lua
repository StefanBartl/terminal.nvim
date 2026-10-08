---@module 'terminal.core.layout'
--- Pure window geometry for terminal windows: no `vim.*` calls, so every number is testable.
---
--- A size is either a fraction of the available space (`0 < x <= 1`) or an absolute count of
--- cells (`x > 1`); anything else (0, negative, NaN, non-number) falls back to the default.

local M = {}

--- Resolve one size spec against the available space.
---@param spec number|nil Fraction (0 < x <= 1) or absolute cells (> 1)
---@param total integer Available cells on that axis
---@param default number Used when `spec` is not a usable number
---@param min? integer Smallest result (default 1)
---@return integer cells # Between `min` and `total`
function M.resolve_size(spec, total, default, min)
  min = min or 1
  local value = spec
  if type(value) ~= "number" or value ~= value or value <= 0 then
    value = default
  end
  local cells
  if value <= 1 then
    cells = math.floor(total * value)
  else
    cells = math.floor(value)
  end
  if cells > total then
    cells = total
  end
  if cells < min then
    cells = math.min(min, total)
  end
  return cells
end

--- Geometry of a floating window centred in the editor, for `nvim_open_win`.
---
--- The border takes two cells on each axis out of what the content gets, so the *outer* size
--- stays what the user configured.
---@param editor_cols integer `vim.o.columns`
---@param editor_lines integer `vim.o.lines`
---@param cfg { width: number, height: number, border: any }
---@return Terminal.FloatGeometry
function M.float(editor_cols, editor_lines, cfg)
  -- The command line and a possible statusline sit below the editor grid.
  local usable_lines = math.max(editor_lines - 2, 1)
  local bordered = cfg.border ~= nil and cfg.border ~= "none" and cfg.border ~= ""
  local frame = bordered and 2 or 0

  local outer_w = M.resolve_size(cfg.width, editor_cols, 0.8, 3)
  local outer_h = M.resolve_size(cfg.height, usable_lines, 0.8, 3)
  local width = math.max(outer_w - frame, 1)
  local height = math.max(outer_h - frame, 1)

  return {
    row = math.max(math.floor((usable_lines - outer_h) / 2), 0),
    col = math.max(math.floor((editor_cols - outer_w) / 2), 0),
    width = width,
    height = height,
  }
end

--- Size of a split window along its axis.
---@param layout "split"|"vsplit"
---@param editor_cols integer
---@param editor_lines integer
---@param spec number|nil
---@return integer cells # Height for "split", width for "vsplit"
function M.split(layout, editor_cols, editor_lines, spec)
  if layout == "vsplit" then
    return M.resolve_size(spec, editor_cols, 0.3, 5)
  end
  return M.resolve_size(spec, math.max(editor_lines - 2, 1), 0.3, 3)
end

return M
