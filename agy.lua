-- agy: the Antigravity CLI as a term program. An agent (or a script) asks
-- agy something with one command instead of typing into its TUI: the
-- prompt goes into the agy session of a directory (one a person already has
-- open there, or a new one), agy answers it by running `term session
-- answer`, and a permission agy asks for mid-turn is handed to a person.
local flow, input, status, json = require "term.flow", require "term.input", require "term.status", require "term.json"

local START_S = 60    -- agy signs in and shows its prompt within this
local TURN_S = 1800   -- one turn's default limit
local PERSON_S = 600  -- a person answers a permission within this

-- the agy sessions running in dir (the newest first)
local function sessions_in(p, dir)
  local out = {}
  for _, row in ipairs(p:sessions()) do
    if row.process == "agy" and row.state ~= "exited" and (row.cwd == dir or row.cwd == "/private" .. dir) then
      table.insert(out, 1, row)
    end
  end
  return out
end

local function open(p, dir, new)
  if not new then
    local found = sessions_in(p, dir)[1]
    if found then return found end
  end
  local sess = p:session_open { argv = { "agy" }, cwd = dir, name = "agy" }
  p:log(("agy: started session %d in %s"):format(sess.id, dir))
  return sess
end

-- person: agy waits for a person (a permission, trusting a folder, a sign-in)
local function person(p, sess, s, opts)
  local why = status.message(s) ~= "" and status.message(s) or "agy asks for a permission"
  flow.within(p, opts.person, flow.handoff, p, sess, {
    reason = why, until_ = function(s) return not status.blocked(s) end,
  })
end

-- ready: agy waits at its prompt (a person is asked for what blocks it)
local function ready(p, sess, opts)
  while true do
    local _, s = flow.expect(p, sess, function(s) return status.idle(s) or status.blocked(s) end, { timeout = START_S })
    if not status.blocked(s) then return s end
    flow.with_lease(p, sess, function() person(p, sess, s, opts) end, { owner = "agy" })
  end
end

local function prompt_for(p, req, text)
  return text .. "\n\nWhen you are done, send your answer back by running this command with your shell tool"
    .. " (run it, do not just write it; add --failed after the id if you could not do it): "
    .. ("%s session answer %d --session %d '<your answer>'"):format(p.term, req.id, req.session)
end

-- turn(p, sess, req, opts): one agy turn for request req; agy answers it
-- itself, else it is answered failed once the turn is over
local function turn(p, sess, req, opts)
  local before = ready(p, sess, opts)
  flow.with_lease(p, sess, function()
    local gen = status.gen(before)
    p:send(sess, input.paste(prompt_for(p, req, req.body)), input.key("Enter"))
    while true do
      local _, s = flow.expect(p, sess, function(s)
        return status.since(s, gen) and (status.settled(s) or status.blocked(s))
      end, { timeout = opts.timeout })
      if not status.blocked(s) then break end
      gen = status.gen(s)
      person(p, sess, s, opts)
    end
  end, { owner = "agy" })
  pcall(p.answer, p, req, "agy ended its turn without answering", { failed = true }) -- refused when agy did answer
end

local function options(args)
  return { timeout = args.timeout or TURN_S, person = args.person or PERSON_S }
end

-- ask: one turn; this program takes the request it sends unless an agy
-- serve already listens there
local function ask(p, args)
  local text = table.concat(args.prompt or {}, " ")
  if text == "" then error(term.error("args", "ask needs a prompt"), 0) end
  local sess, opts = open(p, args.dir, args.new), options(args)
  local took = false
  local worker = p:spawn(function()
    local req = p:next_request(sess)
    took = true
    turn(p, sess, req, opts)
  end)
  p:sleep(0) -- its NEXT goes out before the TELL
  local answer, res = p:tell(sess, text, { timeout = opts.timeout + START_S, progress = function(n) p:log("agy: " .. n) end })
  if took then worker:join() else worker:cancel() end
  if args.json then
    p:print(json.encode { session = sess.id, request = res.id, answer = answer })
  else
    p:print(answer)
  end
end

local function serve(p, args)
  local sess, opts = open(p, args.dir, args.new), options(args)
  p:log(("agy: serving session %d (term session tell %d '<prompt>')"):format(sess.id, sess.id))
  flow.serve(p, sess, function(p, req) turn(p, sess, req, opts) end)
end

local function show(p, args)
  local out = {}
  for _, row in ipairs(sessions_in(p, args.dir)) do
    local s = p:snapshot(row)
    out[#out + 1] = { session = row.id, cwd = row.cwd, state = status.state(s), message = status.message(s), listening = row.listening, serving = row.serving }
  end
  if args.json then return p:print(json.encode(out)) end
  if #out == 0 then return p:print("no agy session in " .. args.dir) end
  for _, o in ipairs(out) do p:print(o.session, o.state, o.message, o.listening > 0 and "served" or "") end
end

local COMMANDS = { ask = ask, serve = serve, status = show }

return term.program {
  name = "agy",
  description = "Ask the Antigravity CLI (agy) in a directory and get its answer; or serve the requests sent to its session",
  args = {
    { "command", "ask <prompt…> | serve | status", required = true },
    { "prompt", "what to ask agy (ask)", many = true },
    { "--dir", "the project directory (default: here)" },
    { "--new", "start a new agy session even when one runs there", flag = true },
    { "--timeout", "seconds one turn may take", default = TURN_S },
    { "--person", "seconds a person has to answer a permission agy asks for", default = PERSON_S },
    { "--json", "print JSON", flag = true },
  },
  main = function(p, args)
    local run = COMMANDS[args.command] or error(term.error("args", "unknown command '" .. args.command .. "' (ask, serve, status)"), 0)
    args.dir = args.dir and (args.dir:sub(1, 1) == "/" and args.dir or p.cwd .. "/" .. args.dir) or p.cwd
    run(p, args)
  end,
}
