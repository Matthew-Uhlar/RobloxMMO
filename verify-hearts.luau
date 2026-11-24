-- Gathering Hearts (§46): Heart of the Deep (Mining), Rootheart (Woodcutting)
-- and Loamheart (Farming). Part A: the pure rules (Data.Hearts: perk lattice,
-- costs, caps, tiers, currency per break, sanitise / migration, respec, the
-- abilities, XP / hour bounds). Part B: the real server (server.server.lua
-- through the verify-gameplay harness, nodes struck with real `strike` verbs):
-- currency + tree XP per break, perks into strike damage, fortune and
-- regrowth, the verbs (validation, throttle, lease, alive), the abilities and
-- their server cooldown (persisted across a rejoin), Rootquake through the
-- real Strike state, respec, persistence and migration, no coin mint. Part C:
-- the clients (Menu › Hearts in the atlas, hearts.client.lua headless: key,
-- chip, gesture hook, VFX) and the sources / registration.
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
local function near(a, b, case) ok(type(a) == "number" and math.abs(a - b) < 1e-6, case .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")") end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function load(path, env)
	return luau.load((fs.readFile(path):gsub("^\239\187\191", "")), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local Progression = load("shared/Progression.lua", {script = nil})
Progression.useData(Data)
local HT, ST = Data.Hearts, Data.Strike

------------------------------------------------------------------------------
-- A. Rules
------------------------------------------------------------------------------
ok(type(HT) == "table", "Data.Hearts exists")
eq(#HT.Order, 3, "three trees")
eq(HT.SPEED_DIVISOR, ST.SPEED_DIVISOR, "the heart speed feeds the §42 divisor")
local names, currencies = {}, {}
for _, id in ipairs(HT.Order) do
	local tree = HT.Trees[id]
	ok(tree and tree.skill == id and HT.TreeOfSkill[id] == id, id .. ": tree keyed by its skill")
	ok(not names[tree.name] and not currencies[tree.currency], id .. ": original, unique name and currency")
	names[tree.name], currencies[tree.currency] = true, true
	ok(Data.Items[tree.currency] == nil, id .. ": the currency is not an item (never sold, traded or banked)")
	local seen, abilities, maxSums = {}, 0, {}
	for _, perk in ipairs(tree.perks) do
		ok(not seen[perk.id], id .. "/" .. perk.id .. ": unique id")
		seen[perk.id] = true
		ok(perk.tier >= 1 and perk.tier <= HT.MAX_TIER and perk.x >= 1 and perk.x <= 5 and perk.max >= 1 and perk.cost > 0, perk.id .. ": in the lattice")
		eq(#perk.requires == 0, perk.tier == 1, perk.id .. ": only tier 1 needs no link")
		for _, req in ipairs(perk.requires) do
			local r = tree.PerkById[req]
			ok(r and r.tier < perk.tier, perk.id .. ": linked to a lower-tier perk " .. req)
		end
		if perk.effect == "ability" then abilities += 1; eq(perk.tier, 3, id .. ": the ability slot is on tier 3") ; eq(perk.max, 1, "ability perk max 1")
		else
			ok(tree.caps[perk.effect] ~= nil, perk.id .. ": every effect has a documented cap (" .. perk.effect .. ")")
			maxSums[perk.effect] = (maxSums[perk.effect] or 0) + perk.per * perk.max
		end
		-- Costs grow per level.
		local last = 0
		for l = 1, perk.max do
			local c = HT.cost(perk, l)
			eq(c, math.floor(perk.cost * l ^ HT.GROWTH + 0.5), perk.id .. ": cost formula at " .. l)
			ok(c >= last, perk.id .. ": cost never falls")
			last = c
		end
	end
	eq(abilities, 1, id .. ": exactly one ability")
	eq(tree.abilityPerk, tree.ability.id, id .. ": the ability perk names the ability")
	for effect, total in pairs(maxSums) do
		ok(total <= tree.caps[effect] + 1e-9, id .. ": maxed " .. effect .. " (" .. total .. ") stays inside its cap " .. tree.caps[effect])
	end
	-- The documented caps (§46).
	eq(tree.caps.fortune, 45, id .. ": fortune cap 45")
	eq(tree.caps.regrowth, 10, id .. ": regrowth cap 10%")
	eq(tree.caps.dust, 50, id .. ": currency cap +50%")
	eq(tree.caps.cooldown, 20, id .. ": cooldown cap 20%")
	eq(tree.caps.speed, if id == "Mining" then 90 else 60, id .. ": speed cap")
	local total = HT.treeCost(tree)
	ok(total >= 120000 and total <= 160000, id .. ": a full tree costs " .. total .. " (deep, 20-40 h of breaks)")
	-- Clamp: a maxed tree with doubled levels never passes a cap.
	local over = {perks = {}}
	for _, perk in ipairs(tree.perks) do over.perks[perk.id] = perk.max * 3 end
	local b = HT.bonuses(tree, over)
	for effect, cap in pairs(tree.caps) do ok(b[effect] <= cap, id .. ": " .. effect .. " clamped (" .. b[effect] .. ")") end
end
eq(HT.Trees.Mining.currency, "Deepdust", "Mining's currency is Deepdust")
eq(HT.Trees.Mining.name, "Heart of the Deep", "Heart of the Deep")
eq(HT.Trees.Woodcutting.name, "Rootheart", "Rootheart")
eq(HT.Trees.Farming.name, "Loamheart", "Loamheart")
-- Tiers from tree XP.
eq(HT.tierFor(0), 1, "tier 1 at 0 XP")
eq(HT.tierFor(2499), 1, "tier 1 below 2,500")
eq(HT.tierFor(2500), 2, "tier 2 at 2,500")
eq(HT.tierFor(600000), 7, "tier 7 at 600k")
eq(select(2, HT.tierFor(600000)), nil, "no next tier at the top")
eq(select(2, HT.tierFor(13000)), 40000, "next tier threshold")
for t = 2, #HT.TIER_XP do ok(HT.TIER_XP[t] > HT.TIER_XP[t - 1], "tier thresholds rise") end
-- Currency per break.
do
	local tree = HT.Trees.Mining
	local ts = HT.blankTree()
	local ore = ST.resource("Ore")
	local got, xp = HT.earn(tree, ts, ore)
	ok(got == 2 and xp == 12 and ts.dust == 2 and ts.xp == 12, "a T1 break: 2 Deepdust, 12 tree XP")
	eq(HT.earn(tree, ts, ST.resource("Crownstone")), 10, "a T9 break: 10 Deepdust")
	-- +5% currency carries fractions exactly: 20 T1 breaks pay 42.
	local carry = HT.blankTree()
	carry.perks.DustSifter = 2 -- +4%
	local sum = 0
	for _ = 1, 25 do sum += HT.earn(tree, carry, ore) end
	eq(sum, 52, "+4% over 25 T1 breaks = 52 (2.08 x 25, fractions carried)")
	ok(carry.frac >= 0 and carry.frac < 1, "the carry stays a fraction")
	eq(carry.earned, 52, "earned counts every break")
end
-- Perk gates: tier, link, currency, max.
do
	local tree = HT.Trees.Mining
	local ts = HT.blankTree()
	local fine, why = HT.canLevel(tree, ts, "DeepGrip")
	ok(not fine and has(why, "needs 6 Deepdust"), "currency gate: " .. tostring(why))
	ts.dust = 100000
	ok(HT.levelUp(tree, ts, "DeepGrip"), "DeepGrip level 1")
	eq(ts.dust, 100000 - 6, "level 1 costs 6")
	eq(ts.spent, 6, "spent recorded")
	fine, why = HT.canLevel(tree, ts, "VeinSense")
	ok(not fine and has(why, "tier 2"), "tier gate: " .. tostring(why))
	ts.xp = 2500
	ok(HT.levelUp(tree, ts, "VeinSense"), "tier 2 opens VeinSense (linked to DeepGrip)")
	ts.xp = 600000
	fine, why = HT.canLevel(tree, ts, "StoneMemory")
	ok(not fine and why == "Unlock a linked perk first.", "link gate (StoneMemory needs Dust Sifter)")
	for _ = 2, 20 do HT.levelUp(tree, ts, "DeepGrip") end
	eq(ts.perks.DeepGrip, 20, "DeepGrip maxed")
	fine, why = HT.canLevel(tree, ts, "DeepGrip")
	ok(not fine and has(why, "maximum"), "max gate")
	eq(ts.spent, 6 + HT.totalCost(tree.PerkById.DeepGrip, 20) - 6 + HT.cost(tree.PerkById.VeinSense, 1), "spent is the sum of the level costs")
	ok(not HT.canLevel(tree, ts, "Bogus"), "unknown perk refused")
end
-- Bonuses, speed / fortune / regrowth helpers and the abilities.
do
	local h = HT.sanitize(nil, {}, 0)
	local m = h.trees.Mining
	m.perks = {DeepGrip = 20, QuarryRhythm = 10, Tremorstep = 10, VeinSense = 15, ResonantPick = 15, CoreFortune = 15, StoneMemory = 10, SeamMemory = 10}
	eq(HT.speedFor(h, "Mining", 0), 90, "maxed Mining speed perks = +90 (cap)")
	eq(HT.fortuneFor(h, "Mining", 0), 45, "maxed fortune = +45 (cap)")
	eq(HT.regrowthFor(h, "Mining"), 10, "maxed regrowth = 10% (cap)")
	eq(HT.speedFor(h, "Fishing", 0), 0, "Fishing has no heart")
	eq(HT.speedFor(nil, "Mining", 0), 0, "no hearts, no bonus")
	local mining = HT.Trees.Mining
	local a = HT.abilityStats(mining, m)
	ok(not a.unlocked, "the ability needs its perk")
	ok(not HT.activate(mining, m, 100), "a locked ability refuses")
	m.perks.DeepcallSurge = 1
	a = HT.abilityStats(mining, m)
	ok(a.unlocked and a.duration == 10 and a.cooldown == 120 and a.amount == 200, "Deepcall Surge: +200 Mining Speed, 10 s, 120 s")
	m.perks.Overcharge, m.perks.DeepPulse, m.perks.QuickRecall = 5, 5, 5
	a = HT.abilityStats(mining, m)
	ok(a.duration == 20 and a.cooldown == 96, "maxed: 20 s every 96 s")
	local fine, got = HT.activate(mining, m, 1000)
	ok(fine and got.duration == 20 and m.readyAt == 1096 and m.activeUntil == 1020, "activation sets the cooldown and the window")
	eq(HT.speedFor(h, "Mining", 1010), 290, "the surge adds +200 while active")
	eq(HT.speedFor(h, "Mining", 1020), 90, "and stops at the window's end")
	local refused, why = HT.activate(mining, m, 1050)
	ok(not refused and has(why, "recharges in 46s"), "cooldown: " .. tostring(why))
	ok(HT.activate(mining, m, 1096), "ready again after the cooldown")
	-- Damage: the strike formula at the caps.
	local ore = ST.resource("Ore")
	local plain = ST.damage(ore, 0, 0, 1)
	eq(ST.damage(ore, 0, 90, 1), math.floor(plain * 1.45), "+90 speed: x1.45 strike damage")
	eq(ST.damage(ore, 0, 290, 1), math.floor(plain * 2.45), "+290 during the surge")
	-- Farming fortune ability.
	local f = h.trees.Farming
	f.perks = {Tillhand = 1, Seedsense = 1, BountifulReaping = 1}
	local farm = HT.Trees.Farming
	ok(HT.activate(farm, f, 5000), "Bountiful Reaping fires")
	eq(HT.fortuneFor(h, "Farming", 5005), 101, "+100 Farming Fortune while active (+1 Seedsense)")
	eq(HT.fortuneFor(h, "Farming", 5010), 1, "then back to the perks")
	-- Rootquake numbers.
	local w = h.trees.Woodcutting
	w.perks = {Rootquake = 1}
	local q = HT.abilityStats(HT.Trees.Woodcutting, w)
	ok(q.amount == 50 and q.radius == 16 and q.cooldown == 60 and q.maxNodes == 6, "Rootquake: 50% within 16 studs, 60 s")
	w.perks.Deepquake, w.perks.Widequake, w.perks.Rootcall = 5, 4, 5
	q = HT.abilityStats(HT.Trees.Woodcutting, w)
	ok(q.amount == 70 and q.radius == 20 and q.cooldown == 48, "maxed Rootquake: 70% within 20 studs every 48 s")
	ok(has(HT.abilityText(HT.Trees.Woodcutting, w), "20 studs") and has(HT.abilityText(HT.Trees.Woodcutting, w), "70%"), "ability copy follows the perks")
end
-- Respec.
do
	local tree = HT.Trees.Mining
	local ts = HT.blankTree()
	ts.xp, ts.dust = 40000, 10000
	for _ = 1, 10 do HT.levelUp(tree, ts, "DeepGrip") end
	local spent = ts.spent
	local fee, refund = HT.respecQuote(tree, ts)
	ok(fee == 5000 * 4 and refund == math.floor(spent * 0.75), "respec: 5,000 coins a tier, 75% back")
	local fine, why = HT.respec(tree, ts, fee - 1, 0)
	ok(not fine and has(why, "costs 20000 coins"), "respec needs the coins")
	ts.activeUntil = 50
	fine, why = HT.respec(tree, ts, fee, 10)
	ok(not fine and has(why, "end first"), "no respec while the ability runs")
	local dust = ts.dust
	local done, back, paid = HT.respec(tree, ts, fee, 60)
	ok(done and back == refund and paid == fee and ts.dust == dust + refund and ts.spent == 0 and next(ts.perks) == nil and ts.respecs == 1, "respec clears the perks and refunds 75%")
	ok(spent - refund > 0, "a respec always loses currency")
	fine = HT.respec(tree, ts, fee, 60)
	ok(not fine, "nothing to reset")
end
-- Sanitise / migration.
do
	local h = HT.sanitize(nil, {Mining = 100000, Woodcutting = 10000000, Farming = -5}, 1000)
	eq(h.v, HT.VERSION, "versioned")
	eq(h.trees.Mining.xp, 5000, "veteran seed: 5% of the skill XP")
	eq(h.trees.Woodcutting.xp, HT.SEED_CAP, "seed capped at tier 4 (40,000)")
	eq(h.trees.Farming.xp, 0, "negative XP seeds nothing")
	eq(h.trees.Mining.dust, 0, "the seed never pays currency")
	local again = HT.sanitize(h, {Mining = 9e9}, 1000)
	eq(again.trees.Mining.xp, 5000, "the seed happens once (an existing record is kept)")
	local junk = HT.sanitize({trees = {Mining = {xp = -5, dust = "x", frac = 7, spent = 99999, perks = {Bogus = 3, DeepGrip = 999, VeinSense = "2", Overcharge = 2.7},
		readyAt = 9e12, activeUntil = 9e12, respecs = 0 / 0}, Farming = "junk"}, Woodcutting = 4}, {}, 1000)
	local m = junk.trees.Mining
	ok(m.xp == 0 and m.frac == 0 and m.respecs == 0, "junk numbers cleaned")
	ok(m.perks.Bogus == nil and m.perks.DeepGrip == 20 and m.perks.VeinSense == nil and m.perks.Overcharge == 2, "unknown perks dropped, levels clamped to max and whole")
	eq(m.spent, HT.totalCost(HT.Trees.Mining.PerkById.DeepGrip, 20) + HT.totalCost(HT.Trees.Mining.PerkById.Overcharge, 2), "spent recomputed from the kept levels")
	eq(m.dust, 99999 - m.spent, "what no longer exists is refunded")
	ok(m.readyAt <= 1000 + 120 and m.activeUntil <= 1000 + 20, "timers clamped to now + their longest value")
	ok(type(junk.trees.Farming) == "table" and type(junk.trees.Woodcutting) == "table", "missing trees rebuilt")
end
-- XP / hour: the regrowth cap moves per-node XP / hour by at most ~11%.
do
	local worst = 0
	for _, id in ipairs(HT.Order) do
		for _, r in ipairs(Data.ResourceTiers[id]) do
			local b = HT.balance(r, HT.Trees[id].caps.regrowth, Progression.regrowthTime)
			local gain = b.newXpHour / b.oldXpHour - 1
			ok(gain >= 0 and gain <= 0.11, r.id .. ": capped regrowth XP / hour +" .. string.format("%.1f", gain * 100) .. "% (≤ 11%)")
			worst = math.max(worst, gain)
			eq(b.oldXpHour, ST.balance(r).newXpHour, r.id .. ": the §42 baseline")
		end
	end
	ok(worst > 0.1, "the documented worst case is ~+10.6% (" .. string.format("%.3f", worst) .. ")")
	-- The speed cap never shortens a node's cycle (the §42 hand-back): only the active time.
	local ore = ST.resource("Ore")
	near(ST.nominalBreak(ore) + ST.regrowth(ore, 3), 4, "Copperstone cycle 4.0 s at the entry tool")
	near(0.7 + ST.regrowth(ore, 3, 0.7), 4, "a capped player breaking in 2 strikes still cycles 4.0 s per node")
end
-- Views.
do
	local h = HT.sanitize(nil, {}, 0)
	h.trees.Mining.dust, h.trees.Mining.xp = 10, 0
	local v = HT.view(h, 0)
	local m = v.trees.Mining
	ok(m.tier == 1 and m.nextAt == 2500 and m.dust == 10, "view: tier, next, currency")
	eq(m.states.DeepGrip, "available", "DeepGrip available")
	eq(m.states.VeinSense, "locked", "tier-2 perk locked")
	h.trees.Mining.dust = 0
	eq(HT.view(h, 0).trees.Mining.states.DeepGrip, "open", "affordability shows as 'open'")
	ok(HT.view(h, 0).trees.Mining.ability.unlocked == false, "ability locked in the view")
	eq(HT.effectText(HT.Trees.Mining, "fortune", 3), "+3 Mining Fortune", "fortune copy")
	eq(HT.effectText(HT.Trees.Woodcutting, "speed", 4), "+4 Chopping Power", "speed copy")
	eq(HT.effectText(HT.Trees.Farming, "regrowth", 1.5), "1.5% faster regrowth", "regrowth copy")
	eq(HT.effectText(HT.Trees.Mining, "dust", 4), "+4% Deepdust", "currency copy")
end
local partA = checks
print("Part A: " .. partA .. " rule checks.")

------------------------------------------------------------------------------
-- B. Server (the verify-gameplay harness; strikes are real `strike` verbs)
------------------------------------------------------------------------------
local src = (fs.readFile("verify-gameplay.luau"):gsub("\r\n", "\n"))
local cut = src:find("local checks=0\nlocal function eq", 1, true)
assert(cut, "verify-gameplay harness marker")
local prefix = src:sub(1, cut - 1)
local hooked
-- Rootquake reads AetherNode-tagged hosts from CollectionService: the suite owns the list.
prefix, hooked = prefix:gsub("RunService = {IsStudio=function%(%) return false end},",
	"RunService = {IsStudio=function() return false end},CollectionService = {GetTagged=function(_, tag) return if tag == \"AetherNode\" then __tagged else {} end},")
assert(hooked == 1, "harness CollectionService hook")
local H = luau.load("local __tagged={}\n" .. prefix .. "\nreturn {player=player,cmd=cmd,data=data,advance=advance,services=services,objects=objects,Data=Data,clock=function() return clock end,tagged=__tagged}",
	{debugName = "hearts-harness", injectGlobals = true})()
local SD = H.Data -- the server's own Data (the same tables the server reads)
local remote = H.objects.RemoteFunction
local X = Data.XP_TABLE
local function strike(p, node) return remote.OnServerInvoke(p, "strike", node) end
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
local function tv(p, tree) return state(p).hearts.trees[tree] end
local function verb(p, v, item) return H.cmd(p, v, item).message end
local world = roblox.Instance.new("Folder")
world.Parent = roblox.Instance.new("Workspace")
local function makeNode(id, at, attrs)
	local model = roblox.Instance.new("Model")
	model.Parent = world
	local part = roblox.Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	local pos = at or Vector3.zero
	part.Position = pos
	part.CFrame = roblox.CFrame.new(pos.X, pos.Y, pos.Z)
	part:SetAttribute("GatherNode", id)
	for k, v in pairs(attrs or {}) do part:SetAttribute(k, v) end
	part.Parent = model
	return part
end
-- Strikes until the break (each swing waits its cadence). Returns the last reply.
local function breakIt(p, node, limit)
	local last
	for _ = 1, limit or 12 do
		last = strike(p, node)
		if last and last.broken then return last end
		if last and last.reason == "cadence" then H.advance(last.wait + 0.01) else H.advance(ST.SWING.Mining + 0.01) end
	end
	return last
end
local function heartsOf(id, tree) return H.data["p" .. id].profile.hearts.trees[tree] end

-- Migration on a fresh journal; the snapshot carries the trees.
local a = H.player(7101)
do
	local s0 = state(a)
	ok(type(s0.hearts) == "table" and s0.hearts.trees.Mining and s0.hearts.trees.Woodcutting and s0.hearts.trees.Farming, "snapshot carries hearts for all three trees")
	ok(s0.hearts.trees.Mining.tier == 1 and s0.hearts.trees.Mining.dust == 0, "a new journal starts at tier 1 with no Deepdust")
end
-- Currency + tree XP per break, no coins.
do
	local ore = makeNode("Ore")
	local coins0 = state(a).coins
	H.advance(1)
	local r = breakIt(a, ore)
	ok(r and r.broken, "Copperstone broken through real strikes")
	-- A regrowing node pays nothing more.
	H.advance(0.8)
	local again = strike(a, ore)
	ok(again.reason == "regrowing", "regrowing")
	local m = tv(a, "Mining")
	ok(m.dust == 2 and m.earned == 2 and m.xp == 12, "+2 Deepdust and +12 Heart XP for a T1 vein")
	eq(state(a).coins, coins0, "currency never comes as coins")
	eq(tv(a, "Mining").dust, 2, "no currency from a refused strike")
	-- Trees and crops pay their own heart; fishing pays none.
	local tree = makeNode("Timber")
	H.advance(1)
	ok(breakIt(a, tree).broken, "a Meadow Tree felled")
	eq(tv(a, "Woodcutting").dust, 2, "+2 Rootsap")
	local herb = makeNode("Herb")
	H.advance(1)
	ok(breakIt(a, herb).broken, "a Meadow Herb harvested")
	eq(tv(a, "Farming").dust, 2, "+2 Loamglow")
	eq(tv(a, "Mining").dust, 2, "and nothing for the other trees")
end
-- A crew store (special node) pays nothing personal.
do
	local crew = makeNode("Ore", nil, {StrikeKind = "crew"})
	local before = tv(a, "Mining").dust
	H.advance(2)
	breakIt(a, crew, 6)
	eq(tv(a, "Mining").dust, before, "special strike nodes never pay currency")
end
-- The verbs: perks.
local miner = seeded(7102, function(pr) pr.hearts.trees.Mining.dust = 50000 end)
do
	local s = state(miner).hearts.trees.Mining
	eq(s.dust, 50000, "seeded Deepdust persisted")
	local msg = verb(miner, "heartPerk", "Mining:DeepGrip")
	ok(has(msg, "Deep Grip 1 / 20") and has(msg, "-6 Deepdust"), "heartPerk buys a level: " .. tostring(msg))
	eq(tv(miner, "Mining").perks.DeepGrip, 1, "level 1 saved")
	eq(tv(miner, "Mining").dust, 50000 - 6, "6 Deepdust spent")
	ok(has(verb(miner, "heartPerk", "Mining:VeinSense"), "tier 2"), "tier-gated perk refused")
	ok(has(verb(miner, "heartPerk", "Mining:Nope"), "Choose a perk"), "unknown perk refused")
	ok(has(verb(miner, "heartPerk", "Fishing:DeepGrip"), "Choose a heart perk"), "unknown tree refused")
	ok(has(verb(miner, "heartPerk", "Mining"), "Choose a heart perk"), "malformed item refused")
	ok(has(verb(miner, "heartPerk", nil), "Choose a heart perk"), "nil item refused")
	eq(tv(miner, "Mining").dust, 50000 - 6, "refusals spend nothing")
	-- Throttle: a second verb inside 0.25 s.
	H.advance(1)
	remote.OnServerInvoke(miner, "heartPerk", "Mining:DeepGrip")
	H.advance(0.1)
	local quick = remote.OnServerInvoke(miner, "heartPerk", "Mining:DeepGrip")
	ok(quick and quick.message == "One moment…", "heart verbs have their own 0.25 s throttle")
	eq(tv(miner, "Mining").perks.DeepGrip, 2, "only the first landed")
	-- Not enough currency.
	local poor = seeded(7103, function(pr) pr.hearts.trees.Mining.dust = 5 end)
	ok(has(verb(poor, "heartPerk", "Mining:DeepGrip"), "needs 6 Deepdust"), "currency gate on the server")
	-- Dead players and an expired lease are refused (perform).
	local humanoid = miner.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	ok(has(verb(miner, "heartPerk", "Mining:DeepGrip"), "Return to your island"), "a dead player cannot buy")
	humanoid.Health = 100
	H.advance(400)
	ok(has(verb(miner, "heartPerk", "Mining:DeepGrip"), "journal sync"), "an expired lease refuses (no write without the journal)")
	eq(tv(miner, "Mining").perks.DeepGrip, 2, "nothing bought without the lease")
	miner = rejoin(miner)
end
-- Perks into the strike: speed (damage), fortune (yield), regrowth.
do
	local ore = SD.Strike.resource("Ore")
	local plain = SD.Strike.damage(ore, 0, 0, 1)
	local fast = seeded(7104, function(pr) pr.hearts.trees.Mining.perks = {DeepGrip = 20, QuarryRhythm = 10, Tremorstep = 10} end)
	H.advance(1)
	local r = strike(fast, makeNode("Ore"))
	eq(r.dmg, SD.Strike.damage(ore, 0, 90, 1), "+90 Mining Speed reaches the server's strike damage (" .. tostring(r.dmg) .. " vs " .. plain .. ")")
	-- Cap enforced server-side even if data / a save says more.
	SD.Hearts.Trees.Mining.caps.speed = 40
	H.advance(1)
	local capped = strike(fast, makeNode("Ore"))
	eq(capped.dmg, SD.Strike.damage(ore, 0, 40, 1), "the cap clamps the server's speed")
	SD.Hearts.Trees.Mining.caps.speed = 90
	-- Woodcutting speed goes into the tool term.
	local chopper = seeded(7105, function(pr) pr.hearts.trees.Woodcutting.perks = {Barkbite = 15, Splitswing = 10, Longhaft = 10} end)
	H.advance(1)
	eq(strike(chopper, makeNode("Timber")).dmg, SD.Strike.damage(SD.Strike.resource("Timber"), 0, 60, 1), "+60 Chopping Power on trees")
	-- Regrowth: 10% off the base, then the §42 hand-back.
	local quick = seeded(7106, function(pr) pr.hearts.trees.Mining.perks = {StoneMemory = 10, SeamMemory = 10} end)
	local node = makeNode("Ore")
	H.advance(1)
	local broke = breakIt(quick, node)
	near(broke.regrow, SD.Strike.regrowth(ore, Progression.regrowthTime(3, 10), 1.42), "regrowth: 10% off the 3 s base before the hand-back")
	ok(broke.regrow < SD.Strike.regrowth(ore, 3, 1.42) - 0.29, "shorter than without the perks")
	-- Fortune: Bountiful Reaping's +100 guarantees one extra crop (rolls fixed high).
	local farmer = seeded(7107, function(pr)
		pr.hearts.trees.Farming.perks = {Tillhand = 1, Seedsense = 1, BountifulReaping = 1}
		pr.hearts.trees.Farming.xp = 12000
	end)
	local h1 = makeNode("Herb")
	local before = state(farmer).items.Herb or 0
	H.advance(1)
	breakIt(farmer, h1)
	local plainYield = (state(farmer).items.Herb or 0) - before
	eq(plainYield, 1, "one herb without the ability (fortune 1 does not roll at 0.999)")
	local msg = verb(farmer, "heartAbility", "Farming")
	ok(has(msg, "Bountiful Reaping!"), "Bountiful Reaping fires: " .. tostring(msg))
	before = state(farmer).items.Herb or 0
	H.advance(0.1)
	breakIt(farmer, makeNode("Herb"))
	eq((state(farmer).items.Herb or 0) - before, 2, "+100 Farming Fortune doubles the harvest while active")
	H.advance(15)
	before = state(farmer).items.Herb or 0
	breakIt(farmer, makeNode("Herb"))
	eq((state(farmer).items.Herb or 0) - before, 1, "and stops when the window ends")
end
-- Deepcall Surge: server cooldown, the attribute, damage while active, rejoin-safe.
do
	local p = seeded(7108, function(pr) pr.hearts.trees.Mining.xp = 12000 end)
	ok(has(verb(p, "heartAbility", "Mining"), "Unlock Deepcall Surge"), "a locked ability is refused")
	p = rejoin(p, function(pr) pr.hearts.trees.Mining.perks = {DeepGrip = 1, VeinSense = 1, DeepcallSurge = 1} end)
	local msg = verb(p, "heartAbility", "Mining")
	ok(has(msg, "Deepcall Surge!") and has(msg, "Recharges in 120s"), "Deepcall Surge fires: " .. tostring(msg))
	ok(type(p.HeartAbility) == "string" and string.match(p.HeartAbility, "^Mining:%d+:10:0$") ~= nil, "HeartAbility attribute for the client VFX: " .. tostring(p.HeartAbility))
	local seq1 = p.HeartAbility
	local ore = SD.Strike.resource("Ore")
	H.advance(0.5)
	local during = strike(p, makeNode("Ore"))
	eq(during.dmg, SD.Strike.damage(ore, 0, 2 + 200, 1), "the surge's +200 lands on the server's strike")
	local again = verb(p, "heartAbility", "Mining")
	ok(has(again, "recharges in"), "the cooldown is server-enforced: " .. tostring(again))
	eq(p.HeartAbility, seq1, "a refused activation never re-plays the VFX")
	H.advance(12)
	local after = strike(p, makeNode("Ore"))
	eq(after.dmg, SD.Strike.damage(ore, 0, 2, 1), "the surge ends after its window")
	-- Rejoin keeps the cooldown (persisted as os.time).
	p = rejoin(p)
	ok(has(verb(p, "heartAbility", "Mining"), "recharges in"), "a rejoin does not reset the cooldown")
	eq(heartsOf(7108, "Mining").readyAt > 0, true, "readyAt saved in the journal")
	H.advance(120)
	p.HeartAbility = nil
	ok(has(verb(p, "heartAbility", "Mining"), "Deepcall Surge!"), "ready again after 120 s")
	ok(type(p.HeartAbility) == "string" and has(p.HeartAbility, "Mining:"), "the new activation is published (a new player object starts its own seq)")

end
-- Rootquake through the real Strike state.
do
	local p = seeded(7109, function(pr)
		pr.hearts.trees.Woodcutting.perks = {Barkbite = 1, Grainreader = 1, Rootquake = 1}
		pr.hearts.trees.Woodcutting.xp = 12000
	end)
	local near1 = makeNode("Timber", Vector3.new(5, 0, 0))
	local near2 = makeNode("Timber", Vector3.new(0, 0, 9))
	local far = makeNode("Timber", Vector3.new(30, 0, 0))
	local other = makeNode("Timber", Vector3.new(3, 0, 3), {OwnerUserId = 99})
	local ore = makeNode("Ore", Vector3.new(4, 0, 0))
	local timber = SD.Strike.resource("Timber")
	local maxHp = SD.Strike.maxHp(timber)
	-- Nothing in reach: refused without spending the cooldown.
	table.clear(H.tagged)
	table.insert(H.tagged, far)
	ok(has(verb(p, "heartAbility", "Woodcutting"), "No trees you can fell within 16 studs"), "no tree in reach: refused")
	-- Soften near1 first with real strikes (30 -> 20 -> 10 at +2 speed? Barkbite 1 = +2).
	local dmg = SD.Strike.damage(timber, 0, 2, 1)
	H.advance(1)
	strike(p, near1)
	for _, n in ipairs({near1, near2, far, other, ore}) do table.insert(H.tagged, n) end
	H.advance(1)
	local msg = verb(p, "heartAbility", "Woodcutting")
	ok(has(msg, "Rootquake! 2 trees split for 50%"), "Rootquake hits the two own trees in reach (not the far one, not another island's, not ore): " .. tostring(msg))
	ok(string.match(p.HeartAbility or "", "^Woodcutting:%d+:0:2$") ~= nil, "attribute carries the hits: " .. tostring(p.HeartAbility))
	-- The shockwave went into this player's own progress; the next strike continues it.
	H.advance(0.1)
	local r2 = strike(p, near2)
	eq(r2.hp, maxHp - math.floor(maxHp * 0.5) - dmg, "near2: 50% from the quake, then the strike (" .. tostring(r2.reason) .. ")")
	H.advance(1)
	local r1 = strike(p, near1)
	ok(r1.broken or r1.hp == math.max(1, maxHp - dmg - math.floor(maxHp * 0.5)) - dmg, "near1 continues from its softened HP")
	-- The quake never deals the last blow: a node at low HP floors at 1.
	local p2 = seeded(7110, function(pr)
		pr.hearts.trees.Woodcutting.perks = {Barkbite = 1, Grainreader = 1, Rootquake = 1, Deepquake = 5}
		pr.hearts.trees.Woodcutting.xp = 40000
	end)
	local lone = makeNode("Timber", Vector3.new(2, 0, 0))
	table.clear(H.tagged)
	table.insert(H.tagged, lone)
	local logs0 = state(p2).items.Timber or 0
	H.advance(1)
	strike(p2, lone)
	H.advance(1)
	strike(p2, lone)
	ok(has(verb(p2, "heartAbility", "Woodcutting"), "1 tree split for 70%"), "maxed quake: 70%")
	H.advance(0.1)
	eq((state(p2).items.Timber or 0) - logs0, 0, "the quake harvested nothing by itself")
	H.advance(0.1)
	local last = strike(p2, lone)
	ok(last.broken, "the next real strike fells it")
	eq((state(p2).items.Timber or 0) - logs0, 1, "exactly one harvest")
	-- Hold: the quake's progress does not decay for 8 s.
	local held = makeNode("Timber", Vector3.new(3, 0, 0))
	table.clear(H.tagged)
	table.insert(H.tagged, held)
	H.advance(70)
	verb(p2, "heartAbility", "Woodcutting")
	H.advance(7)
	local hr = strike(p2, held)
	ok(hr.broken == true and maxHp - math.floor(maxHp * 0.7) <= SD.Strike.damage(timber, 0, 2, 1), "progress held through the 8 s hold: one strike fells the softened tree 7 s later (decay would have healed it)")
	table.clear(H.tagged)
end
-- Respec on the server: coins sink, 75% back, persisted.
do
	local p = seeded(7111, function(pr)
		pr.coins = 30000
		pr.hearts.trees.Mining.dust = 100000
		pr.hearts.trees.Mining.xp = 40000
	end)
	for _ = 1, 5 do verb(p, "heartPerk", "Mining:DeepGrip") end
	local m = tv(p, "Mining")
	eq(m.perks.DeepGrip, 5, "five levels bought")
	local spent, dust = m.spent, m.dust
	eq(m.respecFee, 20000, "tier 4 respec fee 20,000")
	local coins0 = state(p).coins
	local msg = verb(p, "heartRespec", "Mining")
	ok(has(msg, "reset for 20000 coins") and has(msg, "75%"), "respec: " .. tostring(msg))
	m = tv(p, "Mining")
	ok(m.spent == 0 and next(m.perks) == nil and m.dust == dust + math.floor(spent * 0.75), "perks cleared, 75% refunded")
	eq(state(p).coins, coins0 - 20000, "the fee is taken (a coin sink)")
	ok(has(verb(p, "heartRespec", "Mining"), "Nothing to reset"), "nothing left to reset")
	verb(p, "heartPerk", "Mining:DeepGrip")
	ok(has(verb(p, "heartRespec", "Mining"), "costs 20000 coins"), "too few coins: refused")
	ok(has(verb(p, "heartRespec", "Bogus"), "Choose a heart"), "unknown tree refused")
	p = rejoin(p)
	eq(heartsOf(7111, "Mining").respecs, 1, "respec count persisted")
	eq(heartsOf(7111, "Mining").perks.DeepGrip, 1, "perks persisted")
end
-- Persistence and migration through the real open().
do
	local vet = seeded(7112, function(pr)
		pr.hearts = nil
		pr.xp.Mining = X[60]
		pr.xp.Woodcutting = 20000
	end)
	local s = state(vet).hearts.trees
	eq(s.Mining.xp, math.min(40000, math.floor(X[60] * 0.05)), "a veteran's first load seeds tree XP from the skill")
	eq(s.Woodcutting.xp, 1000, "5% of 20,000")
	eq(s.Mining.dust, 0, "but never currency")
	vet = rejoin(vet, function(pr) pr.xp.Mining = X[99] end)
	eq(state(vet).hearts.trees.Mining.xp, math.min(40000, math.floor(X[60] * 0.05)), "the seed happens once")
	local junk = seeded(7113, function(pr)
		pr.hearts = {v = 1, trees = {Mining = {perks = {DeepGrip = 50, Ghost = 4}, spent = 999999, dust = 10}}}
	end)
	local m = state(junk).hearts.trees.Mining
	ok(m.perks.DeepGrip == 20 and m.perks.Ghost == nil, "a damaged save is cleaned on open")
	eq(m.dust, 10 + 999999 - HT.totalCost(HT.Trees.Mining.PerkById.DeepGrip, 20), "lost levels refunded")
	junk = rejoin(junk)
	eq(H.data["p7113"].profile.hearts.v, HT.VERSION, "saved versioned")
end
-- No mint: a long session of every heart verb never raises coins or items.
do
	local p = seeded(7114, function(pr)
		pr.coins = 50000
		pr.hearts.trees.Mining.dust = 1e6
		pr.hearts.trees.Mining.xp = 600000
		pr.hearts.trees.Farming.xp = 12000
		pr.hearts.trees.Farming.perks = {Tillhand = 1, Seedsense = 1, BountifulReaping = 1}
	end)
	local s0 = state(p)
	local coins0 = s0.coins
	local items0 = {}
	for k, v in pairs(s0.items) do items0[k] = v end
	local maxCoins = coins0
	for i = 1, 60 do
		local tree = HT.Trees.Mining
		local perk = tree.perks[(i % #tree.perks) + 1]
		verb(p, "heartPerk", "Mining:" .. perk.id)
		if i % 10 == 0 then verb(p, "heartRespec", "Mining") end
		if i % 7 == 0 then verb(p, "heartAbility", "Farming") end
		maxCoins = math.max(maxCoins, state(p).coins)
	end
	eq(maxCoins, coins0, "coins never rose")
	ok(state(p).coins < coins0, "respecs took coins")
	local s1 = state(p)
	for k, v in pairs(s1.items) do ok(v <= (items0[k] or 0), "no item minted: " .. k) end
end
print("Part B: " .. (checks - partA) .. " server checks.")
local partB = checks

------------------------------------------------------------------------------
-- C. Clients and sources
------------------------------------------------------------------------------
-- The atlas: Menu › Hearts.
do
	local UH = require("./tools/ui-harness")
	local snap = UH.snapshot()
	local h = HT.sanitize(nil, {}, 0)
	h.trees.Mining.xp, h.trees.Mining.dust = 13000, 500
	h.trees.Mining.perks = {DeepGrip = 3, VeinSense = 1, DeepcallSurge = 1}
	h.trees.Mining.readyAt = 40
	h = HT.sanitize(h, {}, 0) -- recomputes spent from the levels
	snap.hearts = HT.view(h, 0)
	snap.coins = 100000
	local ui = UH.runAtlas(roblox.Vector2.new(1366, 768), {snapshot = snap})
	local sidebar = UH.find(ui.gui, "Sidebar")
	UH.press(UH.find(sidebar, "AtlasButton"))
	UH.press(UH.find(ui.scroll, "MenuHearts"))
	ok(UH.find(ui.scroll, "HeartSummary") ~= nil, "Menu › Hearts draws the summary " .. table.concat(ui.warnings, " ; "))
	local canvas = UH.find(ui.scroll, "HeartCanvas")
	ok(canvas ~= nil, "the perk lattice is drawn")
	local hexes = 0
	for _, perk in ipairs(HT.Trees.Mining.perks) do if UH.find(canvas, "HeartPerk" .. perk.id) then hexes += 1 end end
	eq(hexes, #HT.Trees.Mining.perks, "one hex button per perk")
	ok(UH.find(canvas, "HeartPerkDeepGripHex") and #UH.find(canvas, "HeartPerkDeepGripHex"):GetChildren() == 3, "hex built from three rotated bars")
	for t = 1, HT.MAX_TIER do ok(UH.find(canvas, "Tier" .. t) ~= nil, "tier band " .. t) end
	ok(has(UH.find(UH.find(canvas, "HeartPerkDeepGrip"), "Level").Text, "3/20"), "the hex shows its level")
	local summary = UH.find(ui.scroll, "HeartSummary")
	local text = {}
	for _, o in ipairs(summary:GetDescendants()) do if o.Text then table.insert(text, o.Text) end end
	local all = table.concat(text, " | ")
	ok(has(all, "Heart of the Deep") and has(all, "500 Deepdust") and has(all, "tier 3"), "summary: name, currency, tier")
	ok(has(all, "13,000") or has(all, "13000"), "tier progress shows the Heart XP")
	-- Tooltip: select a perk.
	UH.press(UH.find(ui.scroll, "HeartPerkDeepGrip"))
	local tip = UH.find(ui.scroll, "HeartPerkTooltip")
	ok(tip ~= nil, "selecting a perk shows its tooltip card")
	local lines = {}
	for _, o in ipairs(tip:GetDescendants()) do if o.Text then table.insert(lines, o.Text) end end
	local tipText = table.concat(lines, " | ")
	ok(has(tipText, "+6 Mining Speed") and has(tipText, "+8 Mining Speed"), "tooltip: current and next level effect")
	ok(has(tipText, "Cost: " .. HT.cost(HT.Trees.Mining.PerkById.DeepGrip, 4)) and has(tipText, "Deepdust"), "tooltip: next level cost")
	local before = #ui.sent
	UH.press(UH.find(ui.scroll, "HeartPerkBuy"))
	ok(ui.sent[before + 1] and ui.sent[before + 1][1] == "heartPerk" and ui.sent[before + 1][2] == "Mining:DeepGrip", "Level up sends heartPerk Tree:Perk")
	-- Ability slot.
	ok(UH.find(ui.scroll, "HeartAbility") ~= nil, "ability slot card")
	before = #ui.sent
	UH.press(UH.find(ui.scroll, "HeartAbilityUse"))
	-- (the snapshot says 40 s of cooldown: the button is disabled, so nothing or a refused send)
	ok(#ui.sent == before or ui.sent[before + 1][1] == "heartAbility", "the ability button only sends heartAbility")
	-- Respec with a confirm.
	UH.press(UH.find(ui.scroll, "HeartRespec"))
	ok(UH.find(ui.scroll, "HeartRespecConfirm") ~= nil, "respec asks to confirm")
	before = #ui.sent
	UH.press(UH.find(ui.scroll, "HeartRespecConfirm"))
	ok(ui.sent[before + 1] and ui.sent[before + 1][1] == "heartRespec" and ui.sent[before + 1][2] == "Mining", "confirm sends heartRespec")
	-- Tree switch.
	UH.press(UH.find(ui.scroll, "HeartTreeWoodcutting"))
	ok(UH.find(ui.scroll, "HeartPerkRootquake") ~= nil, "Rootheart lattice")
	UH.press(UH.find(ui.scroll, "HeartTreeFarming"))
	ok(UH.find(ui.scroll, "HeartPerkBountifulReaping") ~= nil, "Loamheart lattice")
	-- Phone width.
	local phone = UH.runAtlas(roblox.Vector2.new(844, 390), {snapshot = snap, touch = true})
	UH.press(UH.find(UH.find(phone.gui, "Sidebar"), "AtlasButton"))
	UH.press(UH.find(phone.scroll, "MenuHearts"))
	ok(UH.find(phone.scroll, "HeartCanvas") ~= nil, "the lattice draws on a phone")
	ok(#ui.warnings == 0 and #phone.warnings == 0, "no atlas warnings")

	-- hearts.client.lua headless.
	local signal = function()
		local s = {handlers = {}}
		function s:Connect(f) table.insert(self.handlers, f) return {Disconnect = function() end} end
		function s:Fire(...) for _, f in ipairs(table.clone(self.handlers)) do f(...) end end
		return s
	end
	local replicated = UH.new("ReplicatedStorage")
	local localPlayer = UH.new("Player", {Name = "Voyager", UserId = 1})
	UH.new("PlayerGui").Parent = localPlayer
	local root = UH.new("Part", {Name = "HumanoidRootPart", Position = Vector3.new(0, 3, 0)})
	local character = UH.new("Model", {Name = "Voyager"})
	root.Parent = character
	localPlayer.Character = character
	local other = UH.new("Player", {Name = "Friend", UserId = 2})
	local otherRoot = UH.new("Part", {Name = "HumanoidRootPart", Position = Vector3.new(10, 3, 0)})
	local otherChar = UH.new("Model")
	otherRoot.Parent = otherChar
	other.Character = otherChar
	other:SetAttribute("HeartAbility", "Mining:7:10:0") -- history from before we joined
	local players = UH.new("Players", {LocalPlayer = localPlayer})
	players.PlayerAdded, players.PlayerRemoving = signal(), signal()
	function players.GetPlayers() return {localPlayer, other} end
	local heartbeat = signal()
	local input = UH.new("UserInputService", {TouchEnabled = false})
	local services = {Players = players, ReplicatedStorage = replicated, UserInputService = input, RunService = {Heartbeat = heartbeat}, TweenService = UH.new("TweenService")}
	local game = UH.new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local camera = UH.new("Camera", {ViewportSize = roblox.Vector2.new(1366, 768), CFrame = roblox.CFrame.new(0, 10, 20)})
	local workspace = UH.new("Workspace", {CurrentCamera = camera})
	local delays = {}
	local clock = 100
	local env = {game = game, workspace = workspace, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange, TweenInfo = {new = function() return {} end},
		Instance = {new = function(class) return UH.new(class) end},
		task = {spawn = function(f, ...) local co = coroutine.create(f); coroutine.resume(co, ...) end, delay = function(sec, f, ...) table.insert(delays, {sec, f}) end,
			wait = function() return 0 end, defer = function(f, ...) f(...) end},
		os = {clock = function() return clock end, time = os.time},
		typeof = function(v) return typeof(v) end, print = function() end, warn = function() end}
	local theme = UH.loadTheme(env)
	env.require = function(target) if target.Name == "AetherUiTheme" then return theme end return Data end
	for _, name in ipairs({"AetherUiTheme", "AetherData"}) do UH.new("ModuleScript", {Name = name}).Parent = replicated end
	local gestures = {}
	local gestureEvent = UH.new("BindableEvent", {Name = "IsleGestureLocal"})
	gestureEvent.Parent = replicated
	gestureEvent.Event:Connect(function(name, target) table.insert(gestures, {name, target}) end)
	luau.load(fs.readFile("hearts.client.lua"), {debugName = "hearts.client.lua", environment = env, injectGlobals = true})()
	local S = localPlayer:FindFirstChild("IsleHeartsApi").OnInvoke("state")
	players.PlayerAdded:Fire(other) -- (the mock's GetPlayers lists the local player only)
	players.PlayerAdded:Fire(other)
	ok(S.watched[other] == true and S.seen[other] == 7, "players are watched once; an existing value is history")
	ok(S and S.chip and not S.chip.Visible, "hearts client loaded; no chip before an ability is unlocked")
	local relayed, toasted = {}, {}
	replicated:FindFirstChild("IsleActionLocal").Event:Connect(function(v, item) table.insert(relayed, {v, item}) end)
	replicated:FindFirstChild("IsleToastLocal").Event:Connect(function(t) table.insert(toasted, t) end)
	-- G with nothing unlocked: a toast, no verb.
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.G}, false)
	ok(#relayed == 0 and #toasted == 1 and has(toasted[1], "Menu › Hearts"), "G without an ability explains where to unlock one")
	-- Snapshot with Deepcall Surge and Rootquake unlocked.
	local hv = HT.sanitize(nil, {}, 0)
	hv.trees.Mining.perks = {DeepcallSurge = 1}
	hv.trees.Woodcutting.perks = {Rootquake = 1}
	hv.trees.Mining.earned = 10
	replicated:FindFirstChild("IsleSnapshotLocal"):Fire({hearts = HT.view(hv, 0)})
	ok(S.chip.Visible, "the chip shows once an ability is unlocked")
	eq(S.pick(), "Mining", "first ready unlocked tree by default")
	replicated:FindFirstChild("IsleGatherSkill"):Fire("Woodcutting")
	eq(S.pick(), "Woodcutting", "the tree you last swung at wins")
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.G}, true)
	eq(#relayed, 0, "a processed key (typing) does nothing")
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.G}, false)
	ok(#relayed == 1 and relayed[1][1] == "heartAbility" and relayed[1][2] == "Woodcutting", "G relays heartAbility for the chosen tree")
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.G}, false)
	eq(#relayed, 1, "a double tap inside 0.3 s is debounced")
	clock += 1
	UH.press(S.chip)
	ok(#relayed == 2 and relayed[2][1] == "heartAbility", "the chip relays too")
	clock += 1
	input.InputBegan:Fire({KeyCode = roblox.Enum.KeyCode.ButtonL3}, false)
	eq(#relayed, 3, "gamepad L3 fires the ability")
	-- No gesture / VFX until the server confirms.
	eq(#gestures, 0, "nothing plays before the server accepts")
	-- Server confirms on the local player.
	localPlayer:SetAttribute("HeartAbility", "Woodcutting:1:0:2")
	ok(#gestures == 1 and gestures[1][1] == "chop", "one gesture call into the existing helper (chop)")
	local fx = workspace:FindFirstChild("IsleHeartsFx")
	ok(fx ~= nil and UH.find(fx, "HeartRing") ~= nil, "Rootquake shockwave ring spawned locally")
	ok(UH.find(root, "HeartFx") ~= nil, "leaf burst attached to the player")
	localPlayer:SetAttribute("HeartAbility", "Woodcutting:1:0:2")
	eq(#gestures, 1, "the same seq never re-plays")
	-- Another player's activation: VFX only, no gesture from us.
	eq(UH.find(otherRoot, "HeartFx"), nil, "history from before joining is never replayed")
	other:SetAttribute("HeartAbility", "Mining:8:10:0")
	ok(UH.find(otherRoot, "HeartFx") ~= nil, "a nearby player's Deepcall Surge shows its aura")
	eq(#gestures, 1, "no local gesture for someone else")
	-- FX cap.
	S.live = S.FX_CAP
	other:SetAttribute("HeartAbility", "Mining:9:10:0")
	ok(S.live == S.FX_CAP, "the effect cap holds")
	S.live = 0
	-- Malformed attribute ignored.
	other:SetAttribute("HeartAbility", "Bogus:x")
	eq(S.parse("Bogus:1:2:3"), nil, "unknown tree ignored")
	-- Cleanup timers release the effect slots.
	for _, d in ipairs(delays) do pcall(d[2]) end
	-- Currency pop on a paid break.
	hv.trees.Mining.earned = 14
	replicated:FindFirstChild("IsleSnapshotLocal"):Fire({hearts = HT.view(hv, 0)})
	ok(S.pop.Visible and has(S.pop.Text, "+4 Deepdust"), "a paid break pops +N Deepdust")
	hv.trees.Mining.earned = 20
	replicated:FindFirstChild("IsleSnapshotLocal"):Fire({hearts = HT.view(hv, 0), replay = true})
	ok(not has(S.pop.Text, "+6"), "a replayed snapshot never pops")
	-- Cooldown sweep from the snapshot.
	hv.trees.Woodcutting.readyAt = 30
	replicated:FindFirstChild("IsleSnapshotLocal"):Fire({hearts = HT.view(hv, 0)})
	S.refresh()
	ok(S.timer.Text == "30" and S.sweep.Size.Y.Scale > 0.4, "the chip shows the cooldown: " .. tostring(S.timer.Text))
	-- Layout: left of the hotbar on desktop, clear of it.
	UH.setScreen(roblox.Vector2.new(1366, 768))
	local L = S.layout()
	ok(not L.touch and S.chip.Position.X.Offset + S.chip.Size.X.Offset <= L.hotbar.x - 8, "desktop: the chip sits left of the hotbar")
	ok(S.chip.Position.Y.Offset >= L.hotbar.y - 4 and S.chip.Position.Y.Offset + S.chip.Size.Y.Offset <= L.hotbar.y + L.hotbar.h + 4, "desktop: level with the hotbar")
	UH.setScreen(roblox.Vector2.new(844, 390))
	L = S.layout()
	ok(L.touch and S.chip.Size.X.Offset >= 44, "phones: a 44 px touch target")
	ok(S.chip.Position.Y.Offset + S.chip.Size.Y.Offset <= L.band.y and S.chip.Position.X.Offset >= L.band.x, "phones: above the band, clear of the thumbstick corner")
end
-- Sources and registration.
do
	local hearts = fs.readFile("hearts.client.lua")
	local _, calls = hearts:gsub(":Fire%(HT%.Trees%[id%]%.ability%.gesture%)", "")
	eq(calls, 1, "the animation hook is a single call into the existing gesture helper")
	ok(not has(hearts, "Motor6D") and not has(hearts, "LoadAnimation"), "no animation code of its own (animate.client.lua owns poses)")
	ok(not has(fs.readFile("animate.client.lua"), "Hearts"), "animate.client.lua untouched by this feature")
	local project = fs.readFile("default.project.json")
	ok(has(project, '"IsleHearts": { "$path": "hearts.client.lua" }'), "registered in default.project.json")
	ok(has(fs.readFile("verify.luau"), 'IsleHearts = "hearts.client.lua"'), "registered in verify.luau")
	ok(has(fs.readFile("scripts/build.sh"), "verify-hearts.luau"), "in build.sh")
	ok(has(fs.readFile("build.ps1"), "'verify-hearts.luau'"), "in build.ps1")
	local server = fs.readFile("server.server.lua")
	ok(has(server, "if Hearts.speed then speed+=Hearts.speed(p,r.skill) end"), "Strike.speed reads the hearts")
	ok(has(server, "Hearts.fortune(p,skill,stats)") and has(server, "Hearts.regrowth(p,skill,baseRegrow)") and has(server, "Hearts.gather(player,p,resource)"), "Strike.harvest hooks")
	ok(has(server, "hearts=Hearts.state and Hearts.state(p)"), "snapshot field")
	ok(has(server, "Hearts.migrate(profile)"), "migration hook")
	ok(not string.find(server:match("%-%- >>> Gathering Hearts.-%-%- <<< END Gathering Hearts") or "", "p.coins%+="), "the hearts block never adds coins")
	ok(has(fs.readFile("docs/DEPTH-CONTRACT.md"), "## 46. Gathering Hearts"), "contract §46")
end
print("Part C: " .. (checks - partB) .. " client and source checks.")
print("PASS: " .. checks .. " Gathering Hearts checks.")
print("SUITE-END verify-hearts.luau")
