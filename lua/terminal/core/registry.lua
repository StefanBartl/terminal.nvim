---@module 'terminal.core.registry'
--- The set of terminals terminal.nvim knows about, keyed by `<root>::<name>`.
---
--- An instance (`Registry.new()`) holds the state; there is no module-level table, so specs and
--- parallel setups cannot leak into each other. Pure Lua: no `vim.*` calls.

local M = {}

---@class Terminal.Registry
---@field private items table<string, Terminal.Handle>
---@field private order string[]
local Registry = {}
Registry.__index = Registry

--- The id a terminal gets: project root plus name.
---@param root string
---@param name string
---@return string
function M.make_id(root, name)
  return root .. "::" .. name
end

---@return Terminal.Registry
function M.new()
  return setmetatable({ items = {}, order = {} }, Registry)
end

--- Add or replace a terminal.
---@param handle Terminal.Handle
---@return nil
function Registry:add(handle)
  if self.items[handle.id] == nil then
    self.order[#self.order + 1] = handle.id
  end
  self.items[handle.id] = handle
end

---@param id string
---@return Terminal.Handle|nil
function Registry:get(id)
  return self.items[id]
end

---@param root string
---@param name string
---@return Terminal.Handle|nil
function Registry:find(root, name)
  return self.items[M.make_id(root, name)]
end

--- The terminal that owns a buffer (native backend).
---@param bufnr integer
---@return Terminal.Handle|nil
function Registry:find_by_buf(bufnr)
  for _, h in pairs(self.items) do
    if h.bufnr == bufnr then
      return h
    end
  end
  return nil
end

---@param id string
---@return Terminal.Handle|nil removed
function Registry:remove(id)
  local h = self.items[id]
  if h == nil then
    return nil
  end
  self.items[id] = nil
  for i, v in ipairs(self.order) do
    if v == id then
      table.remove(self.order, i)
      break
    end
  end
  return h
end

--- All terminals in creation order, optionally only those of one project root.
---@param root? string
---@return Terminal.Handle[]
function Registry:list(root)
  local out = {}
  for _, id in ipairs(self.order) do
    local h = self.items[id]
    if h and (root == nil or h.root == root) then
      out[#out + 1] = h
    end
  end
  return out
end

---@return integer
function Registry:count()
  return #self.order
end

return M
