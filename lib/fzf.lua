-- lib.fzf: reading fzf's screen, nothing else (pure; tests feed it saved
-- screens). The default layout: the prompt "> query" on the bottom line,
-- the info line "matched/total ───" above it, and the items above that, the
-- best match nearest the info line. Each item has a gutter ("▌", or ">" in
-- older versions); the current item's gutter is bold.
local M = {}

-- info(s): the info line's row, and the matched and total counts
function M.info(s)
  for row = s.rows, 1, -1 do
    local matched, total = s:line(row):match("^%s*(%d+)/(%d+)")
    if matched then return row, tonumber(matched), tonumber(total) end
  end
end

-- query(s): what the prompt holds (nil: no fzf on this screen)
function M.query(s)
  local row = M.info(s)
  if not row then return nil end
  return (s:line(row + 1):match("^>%s?(.*)$") or ""):gsub("%s+$", "")
end

local function item_at(s, row)
  local line = s:line(row)
  local name = line:match("^▌ (.*)$") or line:match("^> (.*)$") or line:match("^  (.+)$")
  if not name or name == "" then return nil end
  local gutter = s:cell(row, 1)
  return { name = name, row = row, selected = gutter ~= nil and gutter.bold == true }
end

-- items(s): {name, row, selected} the best match first
function M.items(s)
  local out, row = {}, M.info(s)
  if not row then return out end
  for r = row - 1, 1, -1 do
    local item = item_at(s, r)
    if not item then break end
    out[#out + 1] = item
  end
  return out
end

function M.selected(s)
  for _, item in ipairs(M.items(s)) do if item.selected then return item end end
end

-- elements(s, base): a term.screen refine: the items as list items (the
-- current one selected) and the info line as a status bar
function M.elements(s, base)
  local out = {}
  for _, e in ipairs(base) do if e.role ~= "listitem" then out[#out + 1] = e end end
  for _, item in ipairs(M.items(s)) do
    out[#out + 1] = { role = "listitem", name = item.name, row = item.row, col = 3, width = utf8.len(item.name) or #item.name, height = 1, selected = item.selected }
  end
  local row, matched, total = M.info(s)
  if row then out[#out + 1] = { role = "statusbar", name = matched .. "/" .. total, row = row, col = 1, width = s.cols, height = 1 } end
  return out
end

return M
