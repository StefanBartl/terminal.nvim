---@module 'terminal.cheatsheet.parse'
--- A cheatsheet is a Markdown file: `# Title`, then one `## Section` per topic. This module cuts
--- the text into sections, searches them and finds the command on a line. Pure: no `vim.*`.

local M = {}

---@class Terminal.CheatSection
---@field title string
---@field lines string[]

---@class Terminal.CheatSheetText
---@field title? string The `# ` heading
---@field sections Terminal.CheatSection[]

---@internal
---@param lines string[]
local function trim_blank_ends(lines)
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    lines[#lines] = nil
  end
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
  end
end

--- Cut `text` into sections at its `## ` headings. A `##` inside a fenced code block is code, not a
--- heading. Text before the first section (apart from the `# ` title) becomes a section of its own,
--- named `About`, so nothing of the file is unreachable.
---@param text string
---@return Terminal.CheatSheetText
function M.parse(text)
  local result = { sections = {} }
  local intro = {}
  local current
  local fence = false
  for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    if line:match("^%s*```") or line:match("^%s*~~~") then
      fence = not fence
    end
    local heading = not fence and line:match("^##%s+(.-)%s*$")
    if heading and heading ~= "" then
      if current then
        trim_blank_ends(current.lines)
      end
      current = { title = heading, lines = {} }
      result.sections[#result.sections + 1] = current
    elseif not fence and not current and line:match("^#%s+%S") and not result.title then
      result.title = line:match("^#%s+(.-)%s*$")
    elseif current then
      current.lines[#current.lines + 1] = line
    else
      intro[#intro + 1] = line
    end
  end
  if current then
    trim_blank_ends(current.lines)
  end
  trim_blank_ends(intro)
  if #intro > 0 then
    table.insert(result.sections, 1, { title = "About", lines = intro })
  end
  return result
end

---@class Terminal.CheatMatch
---@field section integer
---@field line integer
---@field col integer 0-based byte column of the match

--- Every line that contains `query` (any case, no patterns), in reading order across all sections.
---@param sections Terminal.CheatSection[]
---@param query string
---@return Terminal.CheatMatch[]
function M.search(sections, query)
  local matches = {}
  if type(query) ~= "string" or query == "" then
    return matches
  end
  local needle = query:lower()
  for si, section in ipairs(sections) do
    for li, line in ipairs(section.lines) do
      local from = line:lower():find(needle, 1, true)
      if from then
        matches[#matches + 1] = { section = si, line = li, col = from - 1 }
      end
    end
  end
  return matches
end

---@internal
--- Split a table row at its unescaped `|`.
---@param row string
---@return string[]
local function cells(row)
  local out, buf, i = {}, {}, 1
  while i <= #row do
    local c = row:sub(i, i)
    if c == "\\" and row:sub(i + 1, i + 1) == "|" then
      buf[#buf + 1] = "\\|"
      i = i + 1
    elseif c == "|" then
      out[#out + 1] = table.concat(buf)
      buf = {}
    else
      buf[#buf + 1] = c
    end
    i = i + 1
  end
  out[#out + 1] = table.concat(buf)
  return out
end

--- The command on a line, for typing it into the terminal: the first code span (`` `...` ``) of the
--- first cell of a table row. `\|` in a table cell is a `|`. nil when the line has none, or when
--- the span is a key (`<C-r>`) or a Neovim command (`:...`): those are not typed into a shell.
---@param line string
---@return string|nil
function M.command_of(line)
  if type(line) ~= "string" then
    return nil
  end
  -- Only table rows hold commands; a code span in a sentence is a word of the text.
  if not line:match("^%s*|") then
    return nil
  end
  -- `| a | b |` splits into "", " a ", " b ", "": the first real cell is the second piece
  local text = cells(line)[2] or ""
  local code = text:match("`([^`]+)`")
  if not code then
    return nil
  end
  code = code:gsub("\\|", "|")
  -- Not a command: an empty span, a key (`<C-r>`) or a Neovim command (`:Terminal list`). And
  -- nothing with a control character: it would be typed into the shell as that key (`^O` runs the
  -- line in readline), and a sheet can come from a folder someone else filled.
  if code:match("^%s*$") or code:match("^<[%w%-]+>$") or code:match("^:") or code:find("%c") then
    return nil
  end
  return code
end

return M
