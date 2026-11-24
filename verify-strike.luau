-- Gathering Feel (§42): struck gathering nodes. Part A: the pure rules
-- (Data.Strike: HP per tier, damage, cadence, regrowth hand-back and XP / hour
-- parity, decay, bite delay, labels). Part B: the real server (server.server.lua
-- through the verify-gameplay harness): strike validation, cadence and the
-- token bucket, server damage, per-player progress, exactly-once harvest on
-- the break, regrowth, decay, fishing cast / bite / reel, the retired gather
-- prompt, rejoin. Part C: the world (no gathering node has a prompt; hosts,
-- tags, HP and labels). Part D: the clients (combat strike loop, pooled bars
-- and splats, gesture routing, the overlay label, the hotbar context tool) and
-- gather.client.lua's per-player depleted visuals, run headless.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local checks = 0
local function ok(cond, case)
	if not cond then error("FAILED: " .. case, 2) end
	checks += 1
end
local function eq(actual, expected, case)
	if actual ~= expected then error("FAILED: " .. case .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")", 2) end
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function load(path, env)
	return luau.load((fs.readFile(path):gsub("^\239\187\191", "")), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local ST = Data.Strike

------------------------------------------------------------------------------
-- A. Rules
------------------------------------------------------------------------------
ok(type(ST) == "table", "Data.Strike exists")
for skill, tiers in pairs(Data.ResourceTiers) do
	local lastHp = -1
	for _, r in ipairs(tiers) do
		local hp = ST.maxHp(r)
		if skill == "Fishing" then
			eq(hp, 0, r.id .. ": fishing spots have no HP (cast / bite / reel)")
		else
			ok(hp >= lastHp and hp > 0, r.id .. ": HP never falls by tier (" .. hp .. ")")
			lastHp = hp
			local nominal = ST.damage(r, r.tool, ST.entrySpeed(r), r.level)
			eq(ST.strikesFor(r, nominal), ST.SWINGS[r.index] or 6, r.id .. ": the entry tool breaks it in the nominal strikes")
			ok(ST.damage(r, r.tool + 1, ST.entrySpeed(r), r.level) > nominal, r.id .. ": a better tool tier hits harder")
			ok(ST.damage(r, r.tool, ST.entrySpeed(r) + 100, r.level) > nominal, r.id .. ": more speed hits harder")
			ok(ST.damage(r, r.tool, ST.entrySpeed(r), r.level + 30) > nominal, r.id .. ": levels over the requirement hit harder")
			eq(ST.damage(r, r.tool, ST.entrySpeed(r), r.level + 500), ST.damage(r, r.tool, ST.entrySpeed(r), r.level + ST.LEVEL_BONUS_CAP), r.id .. ": level bonus capped")
		end
		local b = ST.balance(r)
		eq(b.newXpHour, b.oldXpHour, r.id .. ": XP / hour at the nominal tool equals the old hold prompt")
		ok(b.regrowth >= ST.REGROW_FLOOR and b.regrowth <= r.respawn, r.id .. ": regrowth handed back within [floor, respawn]")
		ok(string.sub(ST.label(r), 1, #ST.VERB[skill]) == ST.VERB[skill] and has(ST.label(r), "(" .. skill .. " " .. r.level .. ")"), r.id .. ": label " .. ST.label(r))
	end
end
eq(ST.label(ST.resource("Ore")), "Mine Copperstone Vein (Mining 1)", "the owner's example label")
eq(ST.label(ST.resource("Timber")), "Chop Meadow Tree (Woodcutting 1)", "trees chop")
eq(ST.label(ST.resource("Herb")), "Harvest Meadow Herb Patch (Farming 1)", "crops harvest")
eq(ST.decayed(10, 30, 2), 10, "no decay inside DECAY_AFTER")
eq(ST.decayed(10, 30, ST.DECAY_AFTER + 1), 10 + 30 * ST.DECAY_RATE, "abandoned progress heals")
eq(ST.decayed(10, 30, 99), 30, "fully healed")
for n = 1, 200 do
	local b = ST.biteDelay(12345, n)
	ok(b >= ST.FISH.biteMin and b <= ST.FISH.biteMax, "bite delay in range")
end
ok(ST.biteDelay(1, 1) ~= ST.biteDelay(1, 2), "bite delays vary per cast")
eq(ST.regrowth(ST.resource("Ore"), 0.5), ST.REGROW_FLOOR, "a mastery-shortened regrowth keeps the floor")
print("Part A: " .. checks .. " rule checks.")

------------------------------------------------------------------------------
-- B. Server
------------------------------------------------------------------------------
local src = (fs.readFile("verify-gameplay.luau"):gsub("\r\n", "\n"))
local cut = src:find("local checks=0\nlocal function eq", 1, true)
assert(cut, "verify-gameplay harness marker")
-- task.delay calls are recorded (never run) so the fishing bite push (QC L1) can be fired by hand.
local prefix = src:sub(1, cut - 1)
local delayHooks = 0
prefix, delayHooks = prefix:gsub("delay=function%(%) end", "delay=function(t,f,...) table.insert(__delays,{t=t,f=f,args=table.pack(...)}) end")
assert(delayHooks == 1, "harness task.delay hook")
local H = luau.load("local __delays={}\n" .. prefix .. "\nreturn {player=player,cmd=cmd,objects=objects,allObjects=allObjects,data=data,advance=advance,services=services,node=node,clock=function() return clock end,delays=__delays,Progression=Progression}",
	{debugName = "strike-harness", injectGlobals = true})()
local remote = H.objects.RemoteFunction
local X = Data.XP_TABLE
local function strike(p, node) return remote.OnServerInvoke(p, "strike", node) end
local function rootOf(p) return p.Character:FindFirstChild("HumanoidRootPart") end
local function seeded(id, mutate)
	local p = H.player(id)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. id].profile) end
	return H.player(id)
end
local function rejoin(p, mutate)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. p.UserId].profile) end
	return H.player(p.UserId)
end
local function state(p) return H.cmd(p, "state") end
local world = roblox.Instance.new("Folder")
world.Parent = roblox.Instance.new("Workspace") -- nodes are struck only inside a Workspace (QC L8)
local function makeNode(id, at, attrs)
	local model = roblox.Instance.new("Model")
	model.Parent = world
	local part = roblox.Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Position = at or Vector3.zero
	part.CFrame = roblox.CFrame.new((at or Vector3.zero).X, (at or Vector3.zero).Y, (at or Vector3.zero).Z)
	part:SetAttribute("GatherNode", id)
	for k, v in pairs(attrs or {}) do part:SetAttribute(k, v) end
	part.Parent = model
	return part
end

local a = H.player(5001)
local ore = makeNode("Ore")
-- Validation.
eq(strike(a, {GetAttribute = function() return "Ore" end}).reason, "node", "a client table is never a node")
eq(strike(a, "Ore").reason, "node", "a string is never a node")
local bare = roblox.Instance.new("Part"); bare.Parent = world
H.advance(1)
eq(strike(a, bare).reason, "node", "a part without the server's GatherNode is refused")
local loose = makeNode("Ore"); loose.Parent = nil
H.advance(1)
eq(strike(a, loose).reason, "node", "a removed node is refused")
H.advance(1)
eq(strike(a, makeNode("Shard")).reason, "node", "a non-resource node is refused")
H.advance(1)
local far = strike(a, makeNode("Ore", Vector3.new(30, 0, 0)))
eq(far.reason, "range", "out of reach (~10 studs) refused")
ok(far.pushed == true and has(a.last.message, "closer"), "a refusal with a message reaches the chat as a snapshot")
H.advance(1)
eq(strike(a, makeNode("Ore", nil, {OwnerUserId = 99})).reason, "owner", "another island's node refused")
H.advance(1)
eq(strike(a, makeNode("WindpineLog", nil, {IsleRegion = "Windpine"})).reason, "region", "a locked region refused")
H.advance(1)
eq(strike(a, makeNode("Brassite")).reason, "level", "the level gate comes before any damage")
-- Damage, cadence and the exactly-once harvest.
local before = state(a)
local ore0, mining0 = before.items.Ore or 0, before.xp.Mining or 0 -- (snapshots share live tables)
local hp = ST.maxHp(ST.resource("Ore"))
local dmg = ST.damage(ST.resource("Ore"), 0, 0, 1)
H.advance(2)
local r1 = strike(a, ore)
ok(r1.ok and r1.strike and r1.max == hp and r1.hp == hp - dmg and r1.dmg == dmg, "first strike: server damage " .. dmg .. " of " .. hp)
local r2 = strike(a, ore)
ok(r2.ok == false and r2.reason == "cadence" and (r2.wait or 0) > 0, "a strike inside the swing is refused (cadence)")
H.advance(0.3)
eq(strike(a, ore).reason, "cadence", "still inside the swing")
H.advance(0.4)
local r3 = strike(a, ore)
ok(r3.ok and r3.hp == hp - 2 * dmg, "second swing lands")
H.advance(ST.SWING.Mining)
a.last = nil
local r4 = strike(a, ore)
ok(r4.ok and r4.broken and r4.hp == 0, "third swing breaks the vein")
ok(math.abs(r4.regrow - ST.regrowth(ST.resource("Ore"), 3)) < 1e-6, "regrowth handed back (" .. tostring(r4.regrow) .. ")")
ok(a.last and has(a.last.message, "Copperstone Ore") and has(a.last.message, "+12 Mining XP"), "the break runs the harvest and pushes a snapshot")
eq((a.last.items.Ore or 0) - ore0, 1, "exactly one harvest")
eq((a.last.xp.Mining or 0) - mining0, 12, "XP granted once")
H.advance(ST.SWING.Mining)
local regrowing = strike(a, ore)
ok(regrowing.reason == "regrowing" and regrowing.regrow > 0, "the node regrows for its breaker")
eq(state(a).items.Ore, a.last.items.Ore, "no second harvest from a regrowing node")
-- Per-player progress: no kill-stealing.
local b = H.player(5002)
H.advance(0.1)
local rb = strike(b, ore)
ok(rb.ok and rb.hp == hp - dmg, "another player starts the same node at full HP (own progress)")
H.advance(ST.regrowth(ST.resource("Ore"), 3) + 0.05)
local ra = strike(a, ore)
ok(ra.ok and ra.hp == hp - dmg, "after regrowth the breaker starts afresh; B's hits never counted for A")
H.advance(0.05) -- B's own swing is long over; B is inside DECAY_AFTER
local rb2 = strike(b, ore)
eq(rb2.hp, hp - 2 * dmg, "B keeps B's own progress")
-- Decay of abandoned progress.
H.advance(ST.DECAY_AFTER + 10)
local rd = strike(a, ore)
eq(rd.hp, hp - dmg, "abandoned progress healed back to full before the hit")
-- Auto-clicker: the cadence holds, bursts never add swings.
local spam = seeded(5003)
local spamNode = makeNode("Ore")
local accepted, sent = 0, 0
local t0 = H.clock()
for _ = 1, 100 do
	H.advance(0.05)
	local r = strike(spam, spamNode)
	sent += 1
	if r and r.ok then accepted += 1 end
	if r and r.broken then H.advance(10) end
end
local elapsed = H.clock() - t0
ok(accepted <= math.floor(elapsed / ST.SWING.Mining) + 2, "an auto-clicker gets one strike a swing (" .. accepted .. " in " .. elapsed .. " s)")
local nils = 0
for _ = 1, 40 do if strike(spam, spamNode) == nil then nils += 1 end end
ok(nils >= 20, "the token bucket drops a flood (" .. nils .. ")")
-- Tool gate and mining speed.
local miner = seeded(5004, function(pr) pr.xp.Mining = X[20] end)
H.advance(1)
eq(strike(miner, makeNode("Brassite")).reason, "tool", "Brassite needs a tier 1 pickaxe")
miner = rejoin(miner, function(pr) pr.items.Pickaxe = 1 end)
H.advance(1)
local withPick = strike(miner, makeNode("Ore"))
miner = rejoin(miner, function(pr) pr.items.Pickaxe = 0; pr.items.ReinforcedPickaxe = 1 end)
H.advance(1)
local withBetter = strike(miner, makeNode("Ore"))
ok(withPick.ok and withBetter.ok and withBetter.dmg > withPick.dmg and withPick.dmg > dmg, "mining speed and tools matter (" .. dmg .. " < " .. withPick.dmg .. " < " .. withBetter.dmg .. ")")
-- XP / hour parity: an hour on one Copperstone vein with bare hands at level 1.
do
	local camper = seeded(5005)
	local node = makeNode("Ore")
	local xp0 = state(camper).xp.Mining or 0
	local startAt = H.clock()
	local harvests = 0
	while H.clock() - startAt < 3600 do
		local r = strike(camper, node)
		if r and r.broken then harvests += 1 end
		if r and r.reason == "regrowing" then H.advance(r.regrow + 0.01)
		elseif r and r.reason == "cadence" then H.advance(r.wait)
		else H.advance(0.01) end
		if r and r.broken and harvests % 40 == 0 then camper = rejoin(camper) end -- renew the journal lease
	end
	local old = math.floor(3600 / (ST.OLD_HOLD.Mining + 3)) -- the old prompt: hold 1 s + regrowth 3 s
	ok(math.abs(harvests - old) <= old * 0.05, "XP / hour parity: " .. harvests .. " harvests vs " .. old .. " with the hold prompt")
	local _ = xp0
end
-- Fishing: cast, bite, reel.
do
	local angler = seeded(5006)
	local spot = makeNode("Fish")
	local f0 = (state(angler).items.Fish or 0) + 0
	H.advance(1)
	local cast = strike(angler, spot)
	ok(cast.ok and cast.cast and cast.window == ST.FISH.window, "a click casts")
	eq(cast.bite, nil, "QC L1: the cast reply never carries the bite time")
	H.advance(0.1)
	eq(strike(angler, spot).reason, "early", "reeling before the bite loses the fish")
	eq(strike(angler, spot).reason, "cadence", "and no instant recast")
	H.advance(ST.FISH.gap)
	local cast2 = strike(angler, spot)
	ok(cast2.ok and cast2.cast, "recast after the gap")
	local bite2 = H.delays[#H.delays]
	ok(bite2 and bite2.t >= ST.FISH.biteMin and bite2.t <= ST.FISH.biteMax, "the bite is scheduled server-side (" .. tostring(bite2 and bite2.t) .. " s)")
	-- QC L1: the server pushes the bite to the angler when it happens.
	local biteRemote
	for _, o in ipairs(H.allObjects) do if o.Name == "IsleStrike" then biteRemote = o end end
	ok(biteRemote ~= nil, "the IsleStrike remote exists")
	local pushed = {}
	biteRemote.FireClient = function(_, who, ...) table.insert(pushed, {who = who, args = table.pack(...)}) end
	H.advance(bite2.t)
	bite2.f(table.unpack(bite2.args, 1, bite2.args.n))
	ok(#pushed == 1 and pushed[1].who == angler and pushed[1].args[1] == "bite" and pushed[1].args[2] == spot and pushed[1].args[3] == ST.FISH.window,
		"QC L1: the bite is pushed to the angler at bite time (kind, node, window)")
	H.advance(0.2)
	local reel = strike(angler, spot)
	ok(reel.ok and reel.broken and reel.reeled, "a click inside the bite window reels it in")
	eq((angler.last.items.Fish or 0) - f0, 1, "one fish landed")
	H.advance(ST.FISH.gap)
	local cast3 = strike(angler, makeNode("Fish"))
	ok(cast3.cast, "cast on another spot")
	H.advance(H.delays[#H.delays].t + ST.FISH.window + ST.FISH.late + 0.5)
	local late = strike(angler, makeNode("Fish"))
	ok(late.cast == true, "a missed bite expires; the next click casts again")
	-- A bite for a cast that is gone (reeled, replaced) pushes nothing.
	table.clear(pushed)
	bite2.f(table.unpack(bite2.args, 1, bite2.args.n))
	eq(#pushed, 0, "QC L1: a stale cast's bite is never pushed")
end
-- The retired gather prompt never harvests.
do
	local c = seeded(5007)
	local s0 = state(c).items.Ore or 0
	H.advance(2)
	H.services.ProximityPromptService.PromptTriggered:Fire(H.node("gather", "Ore"), c)
	ok(has(c.last.message, "struck now"), "a gather prompt is refused: " .. tostring(c.last.message))
	eq(state(c).items.Ore or 0, s0, "and grants nothing")
end
-- Rejoin: session-only progress and cadence.
do
	local d = seeded(5008)
	local node = makeNode("Ore")
	H.advance(1)
	ok(strike(d, node).ok, "progress started")
	d = rejoin(d)
	H.advance(0.1)
	eq(strike(d, node).hp, hp - dmg, "a rejoin starts the node afresh (no stale progress, no carried cadence debt)")
end
-- Root reach measured to the node's edge.
do
	local e = seeded(5009)
	local wide = makeNode("Ore", Vector3.new(14, 0, 0))
	wide.Size = Vector3.new(10, 2, 10)
	H.advance(1)
	ok(strike(e, wide).ok, "a wide node is reachable from its edge")
	rootOf(e).Position = Vector3.new(-1, 0, 0)
end
------------------------------------------------------------------------------
-- QC fixes (server).
------------------------------------------------------------------------------
local function breakIt(p, node, limit)
	local last
	for _ = 1, limit or 20 do
		last = strike(p, node)
		if last == nil then H.advance(0.25)
		elseif last.broken then return last
		elseif last.ok == false and last.reason == "cadence" then H.advance(math.max(0.02, last.wait))
		elseif last.ok == false then return last
		else H.advance(0.7) end
	end
	return last
end
-- H1: one gathering clock (casts and strikes share it; a strike drops a cast;
-- an accepted strike holds the action cooldown so a prompt cannot stack on it).
do
	local h = seeded(5101)
	local vein, spot = makeNode("Ore"), makeNode("Fish")
	H.advance(2)
	ok(strike(h, spot).cast, "H1: a cast")
	eq(strike(h, vein).reason, "cadence", "H1: a cast pushes the strike clock (no strike right after a cast)")
	H.advance(ST.FISH.gap)
	ok(strike(h, vein).ok, "H1: the strike after the cast gap lands")
	eq(strike(h, spot).reason, "cadence", "H1: a strike pushes the cast clock (no cast right after a swing)")
	H.advance(3)
	ok(strike(h, spot).cast, "H1: cast again")
	H.advance(ST.FISH.gap + 0.01)
	ok(strike(h, vein).ok, "H1: a strike elsewhere")
	H.advance(ST.SWING.Mining + 1.5)
	local after = strike(h, spot)
	ok(after.cast == true and not after.reeled, "H1: the strike dropped the cast (the next click on the spot casts, never reels)")
	H.advance(3)
	ok(strike(h, vein).ok, "H1: an accepted strike")
	H.services.ProximityPromptService.PromptTriggered:Fire(H.node("station", "Forge"), h)
	eq(h.last.message, "One moment…", "H1: an accepted strike holds the action cooldown (no prompt stacks on the swing)")
	H.advance(ST.SWING.Mining)
	H.services.ProximityPromptService.PromptTriggered:Fire(H.node("station", "Forge"), h)
	ok(has(h.last.message, "Forge"), "H1: the prompt works once the swing is over")
end
-- L2: a late swing does not push the schedule back by its whole lateness.
do
	local l = seeded(5102)
	local vein = makeNode("Ore")
	H.advance(2)
	ok(strike(l, vein).ok, "L2: first swing")
	H.advance(ST.SWING.Mining + 0.1) -- 0.1 s late
	ok(strike(l, vein).ok, "L2: a late swing")
	H.advance(0.5) -- the old schedule (max(now, next) + swing) refuses this until 0.58 s
	ok(strike(l, vein).ok, "L2: the next swing is due a swing after (late time − TOLERANCE), not a full swing after the late one")
end
-- L3: a refused harvest leaves the node at 1 HP (no progress lost, nothing granted).
do
	local c = seeded(5103)
	local vein = makeNode("Ore")
	local real = H.Progression.harvest
	H.Progression.harvest = function() return false, "Your satchel is full." end
	H.advance(2)
	local refused = breakIt(c, vein)
	H.Progression.harvest = real
	ok(refused and refused.ok == false and refused.reason == "harvest" and refused.hp == 1, "L3: a refused harvest leaves the node at 1 HP (" .. tostring(refused and refused.hp) .. ")")
	ok(has(refused.message, "satchel"), "L3: the refusal says why")
	H.advance(ST.SWING.Mining)
	local one = strike(c, vein)
	ok(one.broken == true, "L3: the next strike breaks it at once (progress kept, no regrowth started)")
end
-- L4: the regrowth is set before any reward, so a hook that throws can never
-- leave the node harvestable again.
do
	local d = seeded(5104)
	local vein = makeNode("Ore")
	local items = state(d).items
	items.Ore = nil
	setmetatable(items, {__newindex = function() error("reward hook exploded") end})
	H.advance(2)
	local failed = breakIt(d, vein)
	setmetatable(items, nil)
	ok(failed and failed.reason == "harvest" and has(failed.message, "crumbled"), "L4: a throwing reward hook fails the harvest")
	H.advance(ST.SWING.Mining)
	eq(strike(d, vein).reason, "regrowing", "L4: the regrowth was already set: no second harvest")
end
-- L5: busy is a timestamp; a harvest that never returns cannot lock the player out.
do
	local e = seeded(5105)
	local a1, a2 = makeNode("Ore"), makeNode("Ore")
	local real = H.Progression.harvest
	H.Progression.harvest = function() coroutine.yield() end
	H.advance(2)
	strike(e, a1); H.advance(0.7); strike(e, a1); H.advance(0.7)
	local co = coroutine.create(function() return strike(e, a1) end)
	coroutine.resume(co)
	H.Progression.harvest = real
	H.advance(0.7)
	eq(strike(e, a2).reason, "busy", "L5: busy while the harvest is out")
	H.advance(5.1)
	ok(strike(e, a2).ok, "L5: busy lapses after 5 s")
end
-- L6: the regrowth comes back from Strike.harvest (no module global).
local serverSrc = fs.readFile("server.server.lua")
ok(not serverSrc:find("Strike.lastRegrow", 1, true) and serverSrc:find("return message,true,regrow", 1, true) ~= nil, "L6: regrowth returned from the harvest, no Strike.lastRegrow")
-- L7: no journal, no state: a strike racing the leave never recreates it.
do
	local f = seeded(5106)
	local vein = makeNode("Ore")
	H.services.Players.PlayerRemoving:Fire(f)
	for _ = 1, 40 do strike(f, vein) end
	f = H.player(5106)
	local fresh = strike(f, vein)
	ok(fresh ~= nil and fresh.ok, "L7: strikes without a journal create no state (the rejoin has a full token bucket)")
end
-- L8: a GatherNode part outside the Workspace is never a node.
do
	local g = seeded(5107)
	H.advance(2)
	local stray = roblox.Instance.new("Part")
	stray:SetAttribute("GatherNode", "Ore")
	stray.Parent = roblox.Instance.new("Folder") -- (e.g. ReplicatedStorage)
	eq(strike(g, stray).reason, "node", "L8: a node outside the Workspace is refused")
end
-- M5: the regrowth hands back only the time the break really took: a
-- one-shotting player waits base + the old hold, never beating the old prompt.
do
	local o = seeded(5108, function(pr) pr.xp.Mining = X[99]; pr.items.Pickaxe = 1 end)
	local vein = makeNode("Ore")
	local copper = ST.resource("Ore")
	H.advance(2)
	local one = strike(o, vein)
	ok(one.broken == true, "M5: a level-99 miner with a pickaxe one-shots Copperstone")
	ok(math.abs(one.regrow - (copper.respawn + ST.OLD_HOLD.Mining)) < 1e-6, "M5: one-shot regrowth = base + old hold (" .. tostring(one.regrow) .. ")")
	local startAt, harvests = H.clock(), 0
	while H.clock() - startAt < 3600 do
		local r = strike(o, vein)
		if r and r.broken then harvests += 1 end
		if r and r.reason == "regrowing" then H.advance(r.regrow + 0.01)
		elseif r and r.reason == "cadence" then H.advance(r.wait)
		else H.advance(0.01) end
		if r and r.broken and harvests % 40 == 0 then o = rejoin(o) end
	end
	local old = math.floor(3600 / (ST.OLD_HOLD.Mining + copper.respawn))
	ok(harvests <= old * 1.03, "M5: a one-shotter's hour on one vein never beats the old prompt (" .. harvests .. " vs " .. old .. ")")
	ok(ST.regrowth(copper, 3, 0) == 4 and ST.regrowth(copper, 3) == ST.balance(copper).regrowth, "M5: Data.Strike.regrowth(r, base, elapsed)")
end
-- Owner decision: special strike nodes route the break; nothing personal is granted.
do
	local calls = {}
	local hook = {Invoke = function(_, mode, who, node)
		table.insert(calls, mode)
		if node:GetAttribute("CoopId") == "bad" then return false, "This is another group's homestead." end
		if mode == "credit" then return true, "+1 shared Timber • for building and Homestead XP", 5 end
		return true, ""
	end}
	H.services.ServerStorage.FindFirstChild = function(_, name) return if name == "IsleCoopStrike" then hook else nil end
	local cr = seeded(5109)
	local store = makeNode("Timber", nil, {StrikeKind = "crew", CoopId = "7", IsleCoopResource = "Timber"})
	local t0, w0 = state(cr).items.Timber or 0, state(cr).xp.Woodcutting or 0
	H.advance(2)
	local done = breakIt(cr, store)
	ok(done and done.broken and done.regrow == 5, "crew store: struck to a break, credited through IsleCoopStrike (regrowth 5 s)")
	ok(table.concat(calls, ",") == "check,check,credit", "crew store: checked before damage and before the break, credited once (" .. table.concat(calls, ",") .. ")")
	ok((state(cr).items.Timber or 0) == t0 and (state(cr).xp.Woodcutting or 0) == w0, "crew store: no personal Timber or XP (no new mint)")
	H.advance(ST.SWING.Woodcutting)
	eq(strike(cr, store).reason, "regrowing", "crew store: regrows for the striker")
	local other = makeNode("Timber", nil, {StrikeKind = "crew", CoopId = "bad", IsleCoopResource = "Timber"})
	H.advance(1)
	local no = strike(cr, other)
	ok(no.reason == "harvest" and no.hp == nil and has(no.message, "another group"), "crew store: another crew's store is refused before any damage")
	H.services.ServerStorage.FindFirstChild = nil
	local garden = seeded(5110)
	local plot = makeNode("Herb", nil, {StrikeKind = "garden", GardenHarvest = 1})
	H.advance(2)
	local g = breakIt(garden, plot)
	ok(g and g.reason == "harvest" and g.hp == 1 and has(g.message, "Plot 1"), "garden plot: the break runs the Garden harvest verb (an empty plot refuses, node kept at 1 HP)")
end
print("Part B: server checks done (" .. checks .. ").")

------------------------------------------------------------------------------
-- C. World and sources
------------------------------------------------------------------------------
local worldSrc = fs.readFile("world.server.lua")
do
	local body = worldSrc:gsub('assert%(action~="gather"[^\n]*', "")
	ok(not body:find('"gather","', 1, true) and not body:find(',"gather"', 1, true), "world.server.lua builds no gather prompt")
end
ok(worldSrc:find('assert(action~="gather"', 1, true) ~= nil, "prompt() refuses the gather action")
ok(worldSrc:find('Tags:AddTag(host,"AetherNode")', 1, true) ~= nil and worldSrc:find('SetAttribute("NodeMaxHp"', 1, true) ~= nil, "node hosts are tagged and carry their HP")
local server = fs.readFile("server.server.lua")
ok(server:find('if verb=="strike" then return Strike.action(player,item) end', 1, true) ~= nil, "strike is routed before the string-only gateway")
ok(server:find('Gathering nodes are struck now', 1, true) ~= nil, "the gather prompt branch only refuses")
ok(not server:find("TreeStump", 1, true) and not worldSrc:find("TreeStump", 1, true), "depleted variants are never server parts")
local project = fs.readFile("default.project.json")
ok(project:find('"IsleGather": { "$path": "gather.client.lua" }', 1, true) ~= nil, "gather.client.lua is a StarterPlayerScript")
local catalog = load("art/WorldCatalog.lua")
for _, shape in ipairs({"TreeStump", "DepletedRock", "TilledSoil"}) do ok(catalog.shapes[shape] ~= nil, shape .. " is a forge catalog shape") end
for _, f in ipairs({"scripts/build.sh", "build.ps1"}) do ok(fs.readFile(f):find("verify-strike.luau", 1, true) ~= nil, f .. " runs verify-strike") end

------------------------------------------------------------------------------
-- D. Clients
------------------------------------------------------------------------------
local combat = fs.readFile("combat.client.lua")
ok(combat:find('remote:InvokeServer("strike", node)', 1, true) ~= nil, "combat sends strike verbs")
ok(combat:find('gesture(ST.GESTURE[r.skill] or "mine", node)', 1, true) ~= nil, "a strike swings the §26 gesture for the skill")
ok(combat:find("task.delay(ST.IMPACT[r.skill] or 0.4, function() GN.send(node) end)", 1, true) ~= nil, "the strike lands at the swing's impact")
ok(combat:find("OB.touchNode(node, tonumber(reply.hp), tonumber(reply.max)", 1, true) ~= nil and combat:find("SP.show(GN.top(node), HD.splatStyle({amount = reply.dmg}", 1, true) ~= nil,
	"replies paint the pooled overhead bar and hitsplat")
ok(combat:find("GN.depleted:Fire(node,", 1, true) ~= nil, "a break hands the node to the depletion visuals")
ok(combat:find("Enum.KeyCode.ButtonR2", 1, true) and combat:find("attackButton.InputBegan", 1, true) and combat:find("TouchTapInWorld", 1, true), "mouse, tap, Attack button and gamepad all strike")
ok(fs.readFile("animate.client.lua"):find('if name == "release" then', 1, true) ~= nil, "the cast holds and the reel releases")
ok(fs.readFile("hotbar.client.lua"):find("IsleGatherSkill", 1, true) ~= nil, "the hotbar context tool follows the last strike")
local HD = load("shared/HudDepth.lua")
local Theme = {HudDepth = {}}
local opts = HD.targetOptions({kind = "node", item = "Ore", name = "Copperstone Vein"}, {Data = Data, levels = {Mining = 1}}, Theme)
eq(opts[1].verb .. " " .. opts[1].target .. " " .. opts[1].levelText, "Mine Copperstone Vein (Mining 1)", "§34 label: verb + node + requirement")
eq(opts[1]["local"], "strike", "left-click default is strike (no interact key)")
local depletedOpts = HD.targetOptions({kind = "node", item = "Ore", respawn = 11.2}, {Data = Data, levels = {Mining = 1}}, Theme)
ok(has(depletedOpts[1].levelText, "Respawns in 12s"), "a depleted node shows its respawn countdown")
ok(has(HD.examineText({kind = "node", item = "Ore"}, Data), "Needs Mining 1"), "examine a node")
ok(fs.readFile("overlay.client.lua"):find('kind == "strike"', 1, true) ~= nil, "the world menu's Mine option strikes")

-- gather.client.lua headless: depleted variant shown, regrowth restores,
-- per-player (per-client) state, props are local only.
local function signal()
	local list = {}
	return {Connect = function(_, f) table.insert(list, f) return {Disconnect = function() end} end, Fire = function(_, ...) for _, f in ipairs(list) do f(...) end end}
end
local function client(reducedMotion, queue)
	local now = 100
	local stored = {}
	local rs = {FindFirstChild = function(_, n) return stored[n] end, WaitForChild = function(_, n) return stored[n] or {Name = n} end}
	stored.AetherUiTheme = {Name = "AetherUiTheme"}
	stored.AetherData = {Name = "AetherData"}
	local heartbeat = signal()
	local ws = roblox.Instance.new("Workspace")
	local env
	env = {
		game = {GetService = function(_, name)
			if name == "Players" then return {LocalPlayer = {Character = nil}} end
			if name == "ReplicatedStorage" then return rs end
			if name == "RunService" then return {Heartbeat = heartbeat} end
			if name == "TweenService" then return {Create = function() return {Play = function() end, Completed = {Once = function(_, f) f() end}} end} end
			if name == "Workspace" then return ws end
			return nil
		end},
		require = function(m)
			if m.Name == "AetherUiTheme" then return {reducedMotion = function() return reducedMotion end} end
			return Data
		end,
		Instance = {new = function(class)
			if class == "BindableEvent" then local e = {Event = signal()}; function e:Fire(...) self.Event:Fire(...) end; return setmetatable(e, {__newindex = function(t, k, v) if k == "Parent" then stored[rawget(t, "Name")] = t end rawset(t, k, v) end}) end
			if class == "BindableFunction" then return setmetatable({}, {__newindex = function(t, k, v) if k == "Parent" then stored[rawget(t, "Name")] = t end rawset(t, k, v) end}) end
			return roblox.Instance.new(class)
		end},
		os = {clock = function() return now end},
		task = {delay = function(_, f, ...) if queue then table.insert(queue, table.pack(f, ...)) else f(...) end end,
			defer = function(f, ...) if queue then table.insert(queue, table.pack(f, ...)) else f(...) end end},
		Vector3 = Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, Enum = roblox.Enum, NumberRange = roblox.NumberRange,
		TweenInfo = {new = function() return {} end},
		UDim2 = roblox.UDim2, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, ColorSequence = roblox.ColorSequence, Vector2 = roblox.Vector2,
	}
	load("gather.client.lua", env)
	return {stored = stored, ws = ws, beat = function(s) now += s; heartbeat:Fire() end, api = stored.IsleNodeState, depleted = stored.IsleNodeDepleted}
end
-- A tree (host + trunk + crown), an ore vein, a crop patch and a fishing spot.
local function nodeModel(id, extra)
	local model = roblox.Instance.new("Model")
	local host = roblox.Instance.new("Part")
	host.Name = "Host"
	host.Size = Vector3.new(3, 1, 3)
	host.CFrame = roblox.CFrame.new(0, 0.5, 0)
	host:SetAttribute("GatherNode", id)
	host.LocalTransparencyModifier = 0 -- (Lune has no default for it)
	host.Parent = model
	for _, name in ipairs(extra or {}) do
		local p = roblox.Instance.new("Part")
		p.Name = name
		p.LocalTransparencyModifier = 0
		p.Parent = model
	end
	return model, host
end
local A, B = client(true), client(true)
ok(A.api and A.depleted, "gather.client publishes IsleNodeState and listens on IsleNodeDepleted")
for _, case in ipairs({{"Timber", "TreeStump", {"Trunk", "Crown"}}, {"Ore", "DepletedRock", {"Ore vein", "Crystal shard"}}, {"Herb", "TilledSoil", {"Herb tuft"}},
	{"Fish", nil, {"Ripple", "Bobber", "Fishing pier"}}}) do
	local id, shape, parts = case[1], case[2], case[3]
	local model, host = nodeModel(id, parts)
	local G = A.api.OnInvoke("state")
	A.depleted:Fire(host, 5)
	ok(A.api.OnInvoke(host) > 4.9, id .. ": depleted for this client with its respawn time")
	eq(B.api.OnInvoke(host), 0, id .. ": another client's node stays standing (per player)")
	local hidden = 0
	for _, p in ipairs(model:GetChildren()) do if p:IsA("BasePart") and p.LocalTransparencyModifier == 1 then hidden += 1 end end
	if shape then
		eq(hidden, #parts + 1, id .. ": the node's visuals hide locally")
		local prop = G.props[host]
		ok(prop and prop:GetAttribute("Shape") == shape and prop.Parent and prop.Parent.Name == "IsleNodeLocal", id .. ": shows the " .. shape .. " variant (a local forge slot)")
		ok(prop.Parent.Parent == A.ws, id .. ": the variant lives in the client's local folder")
	else
		eq(hidden, 2, id .. ": the water goes calm (ripples and bobber only)")
		eq(G.props[host], nil, id .. ": no prop for a fishing spot")
	end
	A.depleted:Fire(host, 5) -- a refusal re-syncs without stacking visuals
	A.beat(5.5)
	eq(A.api.OnInvoke(host), 0, id .. ": regrown")
	for _, p in ipairs(model:GetChildren()) do if p:IsA("BasePart") then eq(p.LocalTransparencyModifier, 0, id .. ": " .. p.Name .. " restored") end end
	if shape then ok(G.props[host].Parent == nil, id .. ": the variant is pooled away") end
end
-- Animated path loads too (tweens stubbed); the topple and sprout run.
local C = client(false)
local _, tree = nodeModel("WindpineLog", {"Trunk"})
C.depleted:Fire(tree, 2)
C.beat(2.5)
eq(C.api.OnInvoke(tree), 0, "animated topple and regrow complete")

------------------------------------------------------------------------------
-- QC fixes (clients).
------------------------------------------------------------------------------
local function flush(queue) while #queue > 0 do local job = table.remove(queue, 1); job[1](table.unpack(job, 2, job.n)) end end
local function lmt(model) local out = {} for _, p in ipairs(model:GetChildren()) do if p:IsA("BasePart") then out[p.Name] = p.LocalTransparencyModifier end end return out end
-- M1: a re-break while the regrow plays keeps the node hidden, then restores it fully.
do
	local queue = {}
	local Q = client(false, queue)
	local G = Q.api.OnInvoke("state")
	local model, tree = nodeModel("WindpineLog", {"Trunk", "Crown"})
	Q.depleted:Fire(tree, 2)
	flush(queue)
	Q.beat(2.5) -- the regrow starts (sprout pending in the queue)
	ok(G.depleted[tree] and G.depleted[tree].restoring == true, "M1: the entry stays depleted (restoring) while the regrow plays")
	eq(Q.api.OnInvoke(tree), 0, "M1: a restoring node reads as standing")
	Q.depleted:Fire(tree, 3) -- broken again mid-regrow
	flush(queue) -- the stale sprout finishes now
	for name, v in pairs(lmt(model)) do eq(v, 1, "M1: re-broken during the regrow: " .. name .. " stays hidden") end
	ok(G.props[tree].Parent ~= nil and Q.api.OnInvoke(tree) > 2.9, "M1: the stump and the new timer are back")
	Q.beat(3.5)
	flush(queue)
	for name, v in pairs(lmt(model)) do eq(v, 0, "M1: after the second regrow " .. name .. " is visible again (saved values restored)") end
	eq(G.depleted[tree], nil, "M1: the entry is gone after the regrow")
	-- L11: two trees fall at once, each with its own proxy; the pool is bounded.
	local _, t1 = nodeModel("Timber", {"Trunk"})
	local _, t2 = nodeModel("Timber", {"Trunk"})
	local a, ta = G.treeProxy()
	local b, tb = G.treeProxy()
	ok(a ~= b, "L11: two falling trees get two proxies")
	G.releaseTree(a, ta); G.releaseTree(b, tb)
	for _ = 1, G.TREE_POOL do G.treeProxy() end
	eq(G.treeProxy(), nil, "L11: the proxy pool is bounded (" .. G.TREE_POOL .. ")")
	local _ = t1; local _ = t2
end
-- L10 / L11 / L12: hidden parts are unqueryable, deferred hides after the
-- show do nothing, a forge release is hidden again, a world countdown shows.
do
	local queue = {}
	local Q = client(true, queue)
	local G = Q.api.OnInvoke("state")
	local model, host = nodeModel("Ore", {"Ore vein"})
	local vein = model:FindFirstChild("Ore vein")
	vein.CanQuery, host.CanQuery = true, true
	Q.depleted:Fire(host, 5)
	eq(vein.CanQuery, false, "L10: a hidden part takes no clicks or hover rays")
	eq(host.CanQuery, true, "L10: the host stays queryable (its hover reads the respawn)")
	vein.LocalTransparencyModifier = 0 -- the forge releases its mesh mid-depletion
	Q.beat(0.3)
	eq(vein.LocalTransparencyModifier, 1, "L11: a forge release while depleted is hidden again")
	local board = G.boards[host]
	ok(board and board.gui.Enabled and board.gui.Adornee == host and board.label.Text == "5s", "L12: a world countdown over the depleted node (" .. tostring(board and board.label.Text) .. ")")
	Q.beat(2)
	eq(board.label.Text, "3s", "L12: the countdown ticks")
	Q.beat(3.5)
	flush(queue)
	eq(vein.CanQuery, true, "L10: CanQuery restored on regrow")
	eq(board.gui.Enabled, false, "L12: the countdown hides on regrow")
	local entry = {node = host, saved = {}, query = {}, shown = true}
	local late = roblox.Instance.new("Part"); late.LocalTransparencyModifier = 0; late.Parent = model
	G.hidePart(entry, late)
	eq(late.LocalTransparencyModifier, 0, "L11: a deferred hide that lands after the show does nothing")
end
-- L11: the Aether Lotus grows in water: only its blooms go, no tilled soil.
do
	local Q = client(true)
	local G = Q.api.OnInvoke("state")
	local model, host = nodeModel("AetherLotus", {"Lily pad", "Lotus bloom"})
	Q.depleted:Fire(host, 4)
	local v = lmt(model)
	ok(v["Lotus bloom"] == 1 and v["Lily pad"] == 0 and v.Host == 0, "L11: lotus blooms hide, lily pads and the pool stay")
	eq(G.props[host], nil, "L11: no TilledSoil in the water")
	local crewModel, crew = nodeModel("Timber", {"Timber bundle"})
	crew:SetAttribute("StrikeKind", "crew")
	Q.depleted:Fire(crew, 5)
	ok(G.props[crew] == nil and lmt(crewModel)["Timber bundle"] == 1, "owner decision: a crew store empties with no stump or topple")
end
-- M3: nav indexes struck node hosts by GatherNode (other islands' nodes skipped).
do
	local function host(id, at, owner, kind)
		local p = roblox.Instance.new("Part")
		p.Position = at
		p:SetAttribute("GatherNode", id)
		if owner then p:SetAttribute("OwnerUserId", owner) end
		if kind then p:SetAttribute("StrikeKind", kind) end
		return p
	end
	local index = ST.indexNodes({host("Ore", Vector3.new(10, 0, 0)), host("Ore", Vector3.new(500, 0, 0)), host("WindpineLog", Vector3.new(0, 0, 40)),
		host("Timber", Vector3.new(0, 0, 9)), host("Fish", Vector3.new(-30, 0, 0)), host("Ore", Vector3.new(1, 0, 0), 99), host("Timber", Vector3.new(0, 0, 1), nil, "crew"),
		host("Shard", Vector3.zero)}, 7)
	local T = Data.Townsfolk
	eq(T.resolveTarget("gather:Ore", {gather = index}, Vector3.zero), Vector3.new(10, 0, 0), "M3: gather:Ore resolves to the nearest own / public vein (another island's skipped)")
	eq(T.resolveTarget("gather:WindpineLog", {gather = index}, Vector3.zero), Vector3.new(0, 0, 40), "M3: gather:<tree> resolves")
	eq(T.resolveTarget("gather:Timber", {gather = index}, Vector3.zero), Vector3.new(0, 0, 9), "M3: a crew store is never a waypoint")
	eq(T.resolveTarget("gather:Fish", {gather = index}, Vector3.zero), Vector3.new(-30, 0, 0), "M3: fishing spots resolve")
	eq(index.Shard, nil, "M3: non-resources are skipped")
	ok(fs.readFile("nav.client.lua"):find('GetTagged("AetherNode")', 1, true) ~= nil and fs.readFile("nav.client.lua"):find("Data.Strike.indexNodes(tagged, player.UserId, index.gather)", 1, true) ~= nil,
		"M3: nav builds index.gather from the AetherNode hosts")
end
-- combat.client.lua (source: the loop needs a live camera and input).
do
	local src = combat
	local gn = src:sub(src:find("local GN = {", 1, true), src:find("-- Test / tooling handle (no gameplay effect): the splat", 1, true))
	ok(not gn:find(":MoveTo(", 1, true) and gn:find('FindFirstChild("IsleWalkLocal")', 1, true) and gn:find('walk:Invoke("node", node, GN.reach(node))', 1, true),
		"M2: no straight MoveTo; the walk-up goes through the overlay's pathfinding")
	local overlay = fs.readFile("overlay.client.lua")
	ok(overlay:find('walkApi.Name = "IsleWalkLocal"', 1, true) and overlay:find("return S.walkPath(goal, function() return node.Parent ~= nil and gap() <= reach - 0.5 end", 1, true)
		and overlay:find("if (root.Position - at).Magnitude > S.WALK_MAX then toast(\"Too far: walk closer first.\") return false end", 1, true), "M2: the overlay walks to a node on its route, capped at WALK_MAX with a toast")
	ok(gn:find("if not auto and not GN.held then GN.walkUp(node) end", 1, true), "M2 / L13: no walk-up while a hold is active or from the hold loop")
	ok(gn:find("if fish and GN.usable(fish.node) then return fish.node end", 1, true) and select(2, gn:gsub("GN.padTarget%(%)", "")) >= 2, "M4: R2 and the Attack button reel the cast's spot")
	ok(gn:find("local fish = GN.endFish()\n\t\tif fish then OB.release(fish.node) end", 1, true), "H1: a swing at another node drops the cast")
	ok(not gn:find("reply.bite", 1, true) and gn:find('FindFirstChild("IsleStrike")', 1, true) and gn:find('if kind ~= "bite" or not fish', 1, true), "L1: the bite arrives as a push")
	ok(gn:find("WindowFocusReleased", 1, true) and gn:find("GN.target, GN.held, GN.buffered = nil, nil, nil", 1, true), "L13: focus loss and a break end the hold (no auto-retarget)")
	ok(select(2, gn:gsub("for _, node in ipairs%(GN%.nodes%) do", "")) == 2 and select(2, gn:gsub("GetTagged%(", "")) == 1 and gn:find('GetInstanceAddedSignal("AetherNode")', 1, true)
		and gn:find("if not fresh and now - GN.nearAt < 0.1", 1, true), "L14: the tagged list is cached and the nearest scan runs at most 10 Hz")
	ok(gn:find("GN.highlight = h", 1, true) and not gn:find("\t\t\tflash(node", 1, true), "L15: one reused Highlight for node flashes")
	ok(gn:find("if GN.next - now <= GN.BUFFER then GN.buffered = node end", 1, true) and gn:find("GN.BUFFER = 0.25", 1, true), "L16: a tap within 0.25 s of the swing is buffered")
end
-- Owner decision: no hold-to-gather anywhere (source sweep of every script).
do
	local WORDS = {"Gather", "Chop", "Mine", "Harvest", "Fish", "Pick", "Forage", "Pull", "Net", "Dig"}
	local bad = {}
	for _, file in ipairs(fs.readDir(".")) do
		if file:match("%.lua$") then
			local src = fs.readFile(file)
			for _, w in ipairs(WORDS) do
				for _, pat in ipairs({'ActionText%s*=%s*"' .. w, 'ActionText, [%w%.]+%.ObjectText = "' .. w, 'ActionText, prompt%.ObjectText = "' .. w, 'prompt%([%w_%.]+,%s*"' .. w}) do
					if src:find(pat) then table.insert(bad, file .. " · " .. w) end
				end
			end
			if file ~= "overlay.client.lua" and file ~= "ui.client.lua" and src:find("GATHER_HOLD", 1, true) then table.insert(bad, file .. " · GATHER_HOLD") end
		end
	end
	eq(table.concat(bad, "; "), "", "owner decision: no script builds a gather-like prompt")
	local raids = fs.readFile("raids.server.lua")
	ok(not raids:find("prompt(part, node.verb", 1, true) and raids:find('strikeNode(part, node, "node:" .. k .. ":" .. j)', 1, true), "owner decision: raid resource nodes are strike nodes")
	ok(fs.readFile("world.server.lua"):find('Node.special(base,name,"crew","Shared "..name)', 1, true) ~= nil, "owner decision: crew stores are strike nodes")
	ok(fs.readFile("world.server.lua"):find('Node.special(b.soil,"Herb","garden"', 1, true) ~= nil, "owner decision: ripe garden plots are strike nodes")
end
print("PASS: " .. checks .. " Gathering Feel checks.")
print("SUITE-END verify-strike.luau")
