-- fzf: pick from (or list) what fzf offers, by a query, without typing into
-- it by hand: in an fzf another program shows in a session (--session, a
-- picker some script opened), or in one this program opens on a command's
-- output (-- <command…>).
local flow, input, json = require "term.flow", require "term.input", require "term.json"
local fzf = require "lib.fzf"

local function quote(word) return "'" .. word:gsub("'", "'\\''") .. "'" end

local function shell(cmd)
  local words = {}
  for i, w in ipairs(cmd) do words[i] = quote(w) end
  return table.concat(words, " ") .. " | fzf"
end

-- target: the session showing fzf (opened here for a command; closed after)
local function target(p, args)
  if args.session then return p:session(tonumber(args.session) or args.session), false end
  if not args.cmd or #args.cmd == 0 then error(term.error("args", "give --session <id> or -- <command…> to pick from"), 0) end
  return p:session_open { argv = { "/bin/sh", "-c", shell(args.cmd) }, cwd = p.cwd, name = "fzf" }, true
end

-- filter: the query typed (what was there cleared); the screen once fzf
-- shows it and has stopped filtering
local function filter(p, sess, query, timeout)
  flow.expect(p, sess, function(s) return fzf.query(s) ~= nil end, { timeout = timeout })
  p:send(sess, input.key("Ctrl+U"))
  if query ~= "" then p:send(sess, input.text(query)) end
  local _, s = flow.expect(p, sess, function(s) return fzf.query(s) == query end, { timeout = timeout })
  local r = p:wait(sess, { since = s.gen, quiet = 0.2, timeout = 1 })
  return r.settled and p:snapshot(sess) or s
end

-- choose: move the current item to want, then Enter
local function choose(p, sess, want, timeout)
  for _ = 1, 200 do
    local s = p:snapshot(sess)
    local current = fzf.selected(s)
    if current and current.row == want.row then return p:send(sess, input.key("Enter")) end
    local gen = p:send(sess, input.key((current and want.row > current.row) and "ArrowDown" or "ArrowUp"))
    p:wait(sess, { since = gen, quiet = 0.05, timeout = timeout })
  end
  error(term.error("failed", "could not move to " .. want.name), 0)
end

-- picked: what fzf printed when it ended (its last line), when this
-- program ran it: fzf leaves the screen and its command ends
local function picked(p, sess, timeout)
  local deadline, s = p:now() + timeout, p:snapshot(sess)
  while fzf.query(s) ~= nil do
    local r = p:wait(sess, { since = s.gen, quiet = 0, timeout = math.max(deadline - p:now(), 0.01) })
    s = p:snapshot(sess)
    if not r.exited and not r.settled then error(term.error("timeout", "fzf did not end after Enter"), 0) end
  end
  local lines = s:lines()
  for row = #lines, 1, -1 do if lines[row] ~= "" then return lines[row] end end
end

return term.program {
  name = "fzf",
  description = "Pick from fzf (or list its matches, the best first) by a query: on a command's output (-- <command…>), or in a session that already shows fzf (--session)",
  args = {
    { "command", "pick: print the chosen item | list: print the matches, the best first", required = true },
    { "query", "what to type into fzf (\"\" for everything)", required = true },
    { "cmd", "after --: a command whose output fzf shows (in a session opened and closed for it)", many = true },
    { "--session", "instead of -- <command…>: the session (id or name) where an fzf already shows; the pick goes to its command" },
    { "--nth", "pick the nth match in list's order (1 = the best)", default = 1 },
    { "--timeout", "seconds to wait for fzf", default = 10 },
    { "--json", "print JSON", flag = true },
  },
  main = function(p, args)
    if args.command ~= "pick" and args.command ~= "list" then error(term.error("args", "unknown command '" .. args.command .. "' (pick, list)"), 0) end
    local sess, ours = target(p, args)
    if ours then p:defer(function() p:session_close(sess) end) end
    local s = filter(p, sess, args.query, args.timeout)
    local items, _, matched, total = fzf.items(s), fzf.info(s)
    if args.command == "list" then
      local names = {}
      for i, item in ipairs(items) do names[i] = item.name end
      if args.json then return p:print(json.encode { query = args.query, matched = matched, total = total, items = names }) end
      for _, n in ipairs(names) do p:print(n) end
      return
    end
    local want = items[args.nth]
    if not want then error(term.error("failed", ("no match %d for %q (%d match)"):format(args.nth, args.query, matched or 0)), 0) end
    choose(p, sess, want, args.timeout)
    local item = ours and picked(p, sess, args.timeout) or want.name
    if args.json then return p:print(json.encode { query = args.query, item = item }) end
    p:print(item)
  end,
}
