-- tests/fzf_screen: lib.fzf against fzf 0.74 screens saved with
-- `term session snapshot <id> --save` (the items "alpha beta gamma betamax
-- alphabet soup"; then the query "bet"; then one ArrowUp).
local fzf = require "lib.fzf"

local function names(items)
  local out = {}
  for i, item in ipairs(items) do out[i] = item.name end
  return table.concat(out, ",")
end

local CASES = {
  { "fzf-all.json", function(s)
    local _, matched, total = fzf.info(s)
    return { matched .. "/" .. total, fzf.query(s), names(fzf.items(s)), fzf.selected(s).name }
  end, { "5/5", "", "alpha,beta,gamma,betamax,alphabet soup", "alpha" } },
  { "fzf-bet.json", function(s)
    return { fzf.query(s), names(fzf.items(s)), fzf.selected(s).name }
  end, { "bet", "beta,betamax,alphabet soup", "beta" } },
  { "fzf-bet-up.json", function(s)
    local list = {}
    for _, e in ipairs(fzf.elements(s, {})) do list[#list + 1] = e.role .. ":" .. e.name .. (e.selected and "*" or "") end
    return { table.concat(list, ",") }
  end, { "listitem:beta,listitem:betamax*,listitem:alphabet soup,statusbar:3/5" } },
}

return term.program {
  name = "fzf_screen",
  description = "test lib.fzf on saved fzf screens",
  main = function(p)
    local failed = 0
    for _, case in ipairs(CASES) do
      local got = case[2](p:screen_load("fixtures/" .. case[1]))
      for i, want in ipairs(case[3]) do
        if got[i] ~= want then
          failed = failed + 1
          p:log(("%s [%d]: want %q, got %q"):format(case[1], i, want, tostring(got[i])))
        end
      end
    end
    if failed > 0 then error(term.error("failed", failed .. " checks failed"), 0) end
    p:print(("ok %d screens"):format(#CASES))
  end,
}
