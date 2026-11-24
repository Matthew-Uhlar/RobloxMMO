-- Beaconry (§37): data rules, balance model, world pyres, the campfire
-- renderer and server behaviour.
-- Part A checks shared/GameData.lua (Data.Beaconry) with shared/Progression.lua.
-- Part B runs world.server.lua with real Roblox instances (the nine beacon
-- pyres) and beaconry.server.lua against them (campfires and beacon flames
-- drawn from the published attributes). Part C runs server.server.lua with a
-- deterministic clock, rolls, a DataStore double and a raycast double, and
-- plays kindling (success, failure, ground and spacing refusals, the
-- per-player cap, burn-out ash), campfire cooking (pacing, burning, walking
-- away, the fire going out), beacons (feeding, warmth for the lighter and a
-- bystander, basking, the weekly community total and its claim), quest flags,
-- commissions, the Everflame mantle, migration and persistence.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local B = Data.Beaconry
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local X = Data.XP_TABLE

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(B) == "table", "Data.Beaconry exists")
eq(Data.SkillOrder[#Data.SkillOrder], "Beaconry", "Beaconry appended last (old saves keep their order)")
do
	local def = Data.Skills.Beaconry
	ok(def and def.category == "production" and #def.color == 6 and def.title and def.description, "skill metadata")
	for stat, v in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil and v > 0 and v <= 1, "perLevel " .. stat .. " modest") end
	for id, other in pairs(Data.Skills) do
		if id ~= "Beaconry" then ok(other.title ~= def.title and other.color ~= def.color, "title/colour unique vs " .. id) end
	end
	local s1, s99 = P.computeStats({xp = {}, items = {}}, 0), P.computeStats({xp = {Beaconry = X[99]}, items = {}}, 0)
	ok(s99.health - s1.health >= 98 * def.perLevel.health - 1, "Beaconry 99 adds Health per level")
	ok(Data.Mastery.capePerk("Beaconry") == Data.Mastery.CapePerk.Beaconry and Data.Mastery.CapePerk.Beaconry.health == 30, "99 mantle perk registered")
	eq(Data.levelCoinReward(50), 12500, "level-up coins come from the shared table")
end
-- Logs: every Woodcutting tier, gated like Woodcutting, XP rising.
eq(#B.Logs, #Data.ResourceTiers.Woodcutting, "one log per wood tier")
for i, log in ipairs(B.Logs) do
	local r = Data.ResourceTiers.Woodcutting[i]
	eq(log.id, r.id, "log order follows the wood tiers")
	eq(log.level, r.level, log.id .. " level matches Woodcutting")
	ok(log.xp > r.xp and log.xp <= r.xp * 1.5 + 5, log.id .. " XP 1.0-1.5x its Woodcutting XP (OSRS ratio)")
	if i > 1 then ok(log.xp > B.Logs[i - 1].xp and log.seconds > B.Logs[i - 1].seconds, log.id .. " pays and burns more than the tier below") end
	ok(log.seconds >= 60 and log.seconds <= 180, log.id .. " campfire burns 1-3 minutes")
	eq(B.successChance(log.level - 1, log, 1), 0, log.id .. " cannot be kindled below its level")
	ok(math.abs(B.successChance(log.level, log, 1) - B.SUCCESS_BASE) < 1e-9, log.id .. " 45% at its level")
	eq(B.successChance(log.level + B.SUCCESS_FADE, log, 1), 1, log.id .. " certain 25 levels later")
	ok(B.successChance(log.level + 5, log, 3) > B.successChance(log.level + 5, log, 1), "better strikers kindle more often")
end
-- Strikers: Forge recipes, held class, no coin mint, never consumed.
for i, id in ipairs(B.StrikerOrder) do
	local def, rec = Data.Items[id], Data.Recipes[id]
	ok(def and def.heldClass == "striker" and def.tier == i, id .. " is a tier " .. i .. " striker")
	ok(rec and rec.station == "Forge" and rec.skill == "Smithing", id .. " forged at the Forge")
	ok(def.value <= B.valueOf(rec.costs), id .. " value <= inputs (no coin mint)")
	ok(Data.Held.holdable(id) and Data.Held.spec(id) and #Data.Held.spec(id).parts <= Data.Held.MAX_PARTS, id .. " holdable within the part budget")
	eq(Data.Held.classOf(def), "striker", id .. " resolves to the striker class")
end
ok(Data.Held.fits("kindle", "striker"), "the striker swings itself in the kindle gesture")
eq(B.bestStriker({FlintStriker = 1, SunsteelStriker = 1}, function() return 40 end).id, "SunsteelStriker", "best usable striker")
eq(B.bestStriker({FlintStriker = 1, SunsteelStriker = 1}, function() return 10 end).id, "FlintStriker", "striker level gate")
eq(B.bestStriker({}, nil), nil, "no striker")
-- Ash, Alchemy and Farming links.
ok(Data.Items.PyreAsh and table.find(Data.CollectionItems, "PyreAsh") ~= nil, "Pyre Ash is a collection")
ok(Data.Garden.organic("PyreAsh") > 0, "Pyre Ash feeds the composter (Farming)")
do
	local r = Data.Recipes.EmberwardDraught
	ok(r and r.skill == "Alchemy" and r.costs.PyreAsh and r.costs.GlassVial == 1, "Emberward Draught: ash + a vial (§22 vial rule)")
	ok(table.find(Data.Crafting.VIAL_POTIONS, "EmberwardDraught") ~= nil, "listed with the vial potions")
	ok(Data.Items.EmberwardDraught.value <= B.valueOf(r.costs), "draught value <= inputs")
end
-- Campfire recipes.
do
	local hearth, listed = 0, 0
	for id, r in pairs(Data.Recipes) do if r.skill == "Cooking" and r.station == "Hearth" then hearth += 1; ok(B.cookRecipe(id) == r, id .. " cooks on a campfire") end end
	for _, rec in ipairs(B.cookList()) do listed += 1 end
	eq(listed, hearth + #B.FireRecipeOrder, "campfire list = Hearth recipes + campfire dishes")
	for _, id in ipairs(B.FireRecipeOrder) do
		local rec = B.FireRecipes[id]
		ok(Data.Recipes[id] == nil, id .. " is campfire-only (the generic craft verb cannot make it)")
		ok(Data.Items[id].value <= B.valueOf(rec.costs), id .. " value <= inputs")
		eq(B.burnChance(1, rec), 0, id .. " never burns")
	end
	eq(B.cookRecipe("Timber"), nil, "not a recipe")
	eq(B.cookRecipe("BrassIngot"), nil, "a Forge recipe is not cooked")
	local meal = Data.Recipes.CookedFish
	ok(math.abs(B.burnChance(meal.level, meal) - B.BURN_BASE) < 1e-9, "35% burn at the recipe level")
	eq(B.burnChance(meal.level + B.BURN_FADE, meal), 0, "no burning 30 levels later")
	eq(B.cookXp(meal), math.floor(meal.xp * 1.1), "+10% Cooking XP at a campfire")
	local id, n = B.parseBatch("CookedFish:500")
	ok(id == "CookedFish" and n == B.MAX_BATCH, "batch clamped")
	for _, bad in ipairs({"CookedFish:0", "Nope:2", "CookedFish:-1", "CookedFish:1.5", "x"}) do eq(B.parseBatch(bad), nil, "bad batch " .. bad) end
end
-- Beacons: one per region on a real island, logs that exist.
eq(#B.BeaconOrder, #Data.Exploration.RegionOrder, "one beacon per region")
for _, region in ipairs(Data.Exploration.RegionOrder) do
	local b = B.Beacons[region]
	ok(b and b.region == region and B.LogById[b.log] and b.level >= 1 and b.level <= 99, region .. " beacon")
	ok(Data.Exploration.ShrineIsle[region] ~= nil, region .. " beacon has an island")
	ok(B.LogById[b.log].level <= b.level, region .. " beacon's log is open at its level")
	for stat, v in pairs(b.buff) do ok(Data.Stats[stat] ~= nil and v > 0 and v <= 40, region .. " warmth " .. stat .. " modest") end
end
ok(B.feedsBeacon(B.Beacons.Quarry, "EmberoakLog") and not B.feedsBeacon(B.Beacons.Quarry, "Timber"), "better logs feed, worse do not")
eq(B.beaconFuel(B.Beacons.Quarry, {Timber = 50, WindpineLog = 5, EmberoakLog = 6}).id, "EmberoakLog", "lowest full feed")
eq(B.beaconFuel(B.Beacons.Quarry, {WindpineLog = 5}), nil, "short feed")
-- QC H1: fuel only from logs the lighter can kindle; XP from the beacon's own tier.
eq(B.beaconFuel(B.Beacons.Hub, {ShatterbarkLog = 6}, 1), nil, "H1: Beaconry 1 cannot feed Shatterbark")
eq(B.beaconFuel(B.Beacons.Hub, {ShatterbarkLog = 6, Timber = 6}, 1).id, "Timber", "H1: Beaconry 1 feeds the Timber it can kindle")
eq(B.beaconXpFor(B.Beacons.Hub), B.beaconXp(B.LogById.Timber), "H1: Quayfire pays its own (Timber) tier")
do
	local c = B.migrate({})
	local paid = 0
	for _ = 1, B.BEACON_XP_PER_DAY + 3 do if B.takeBeaconXp(c, 500) then paid += 1 end end
	eq(paid, B.BEACON_XP_PER_DAY, "H1: beacon XP for the first N lightings of an isle day")
	ok(B.takeBeaconXp(c, 501), "H1: a new isle day pays again")
	ok(not B.takeBeaconXp(c, 499) and c.xpDay.id == 501, "H1: an earlier day never rewinds the counter")
	local m = B.migrate({xpDay = {id = 501, n = 99}})
	eq(m.xpDay.n, B.BEACON_XP_PER_DAY, "H1: xpDay migrated and clamped")
	-- Beacons can never beat banked kindling: a whole isle day of capped beacon XP
	-- (best beacon every time) is a small fraction of that day's banked kindling.
	local best = B.Logs[#B.Logs]
	local dayBeacon = B.BEACON_XP_PER_DAY * B.beaconXpFor(B.Beacons.ShatteredCrown)
	local dayBanked = B.bankedRate(99, best, 3) * Data.Calendar.dayLength / 3600
	ok(dayBeacon < 0.05 * dayBanked, string.format("H1: capped beacon XP/day %.0f < 5%% of banked kindling %.0f", dayBeacon, dayBanked))
end
-- QC M3: per-server contributions merge idempotently and fold.
do
	local v = B.weekMerge(nil, "jobA", {[10] = 3}, 40000)
	eq(B.weekSum(v), 3, "M3: first write")
	v = B.weekMerge(v, "jobA", {[10] = 3}, 40010)
	eq(B.weekSum(v), 3, "M3: a repeated (timed-out but committed) write never double counts")
	v = B.weekMerge(v, "jobA", {[10] = 5, [11] = 1}, 40020)
	v = B.weekMerge(v, "jobB", {[11] = 4}, 40030)
	eq(B.weekSum(v), 10, "M3: servers and segments sum on read")
	eq(B.weekSum(B.weekMerge(7, "jobC", {[11] = 2}, 40040)), 9, "M3: a legacy number is the base")
	local folded = B.weekMerge(v, "jobB", {[11] = 4}, 40030 + B.WEEK_FOLD + 1)
	eq(B.weekSum(folded), 10, "M3: folding keeps the sum")
	ok(folded.s["jobA:10"] == nil and folded.s["jobB:11"] ~= nil and folded.base == 6, "M3: idle entries fold into base")
end
-- Campfire ground rules.
local function chain(...) local out = {} for _, n in ipairs({...}) do table.insert(out, {name = n}) end return out end
ok(B.groundVerdict(chain("Meadow", "Compass Quay", "Islands"), 7), "open isle ground")
ok(not B.groundVerdict(chain("Path", "Compass Quay", "Islands"), 7), "no fires on paths")
ok(not B.groundVerdict(chain("Continuous bridge deck", "Compass Quay", "Islands"), 7), "no fires on bridges")
ok(not B.groundVerdict({{name = "Span", bridge = true}, {name = "Islands"}}, 7), "BridgeStyle parts refuse")
ok(not B.groundVerdict(chain("Rope bridge deck", "Course", "Islands"), 7), "no fires on rope decks")
ok(B.groundVerdict(chain("Meadow", "WayfarersRest_7", "AetherIsles"), 7), "your own home island")
ok(not B.groundVerdict(chain("Meadow", "WayfarersRest_8", "AetherIsles"), 7), "never another player's home")
ok(not B.groundVerdict(chain("Floor", "Arena", "LairInstances"), 7), "not in a lair")
ok(not B.groundVerdict({}, 7), "nothing underfoot")
ok(not B.spacingVerdict(Vector3.new(0, 0, 0), {{pos = Vector3.new(2, 0, 0)}}, {}), "fire spacing")
ok(B.spacingVerdict(Vector3.new(0, 0, 0), {{pos = Vector3.new(5, 0, 0)}}, {}), "spaced fires")
ok(not B.spacingVerdict(Vector3.new(0, 0, 0), {}, {Vector3.new(8, 0, 0)}), "beacon clearance")
-- QC L2: clearance from prompts / spawn markers / townsfolk anchors; never inside a station or stall.
ok(not B.spacingVerdict(Vector3.new(0, 0, 0), {}, {}, {Vector3.new(B.SPOT_CLEARANCE - 1, 0, 0)}), "L2: too close to a prompt, marker or anchor")
ok(B.spacingVerdict(Vector3.new(0, 0, 0), {}, {}, {Vector3.new(B.SPOT_CLEARANCE + 0.5, 0, 0)}), "L2: clear of busy spots")
ok(not B.groundVerdict(chain("Counter", "Quay Bank stall", "Compass Quay", "Islands"), 7), "L2: not inside a market stall")
ok(not B.groundVerdict(chain("Council dais", "Council Hall", "Compass Quay", "Islands"), 7), "L2: not on the Council dais")
ok(not B.groundVerdict(chain("Base", "Forge", "Compass Quay", "Islands"), 7), "L2: not inside a station model")
ok(B.groundVerdict(chain("Meadow", "Brassfall Quarry", "Islands"), 7), "L2: an isle's own name never refuses")
-- Profile migration and weeks.
do
	local m = B.migrate({kindled = {Timber = 5, Nope = 2, EmberoakLog = -3, WindpineLog = 0 / 0}, beacons = {Hub = 2, Fake = 1}, failed = "x", cooked = 1e99,
		week = {id = 10, lit = 4, claimed = "yes"}, weeks = -2})
	ok(m.kindled.Timber == 5 and m.kindled.Nope == nil and m.kindled.EmberoakLog == nil and m.kindled.WindpineLog == nil, "kindled sanitised")
	ok(m.beacons.Hub == 2 and m.beacons.Fake == nil, "beacons sanitised")
	ok(m.failed == 0 and m.cooked == B.MAX_COUNT and m.weeks == 0 and m.week.claimed == false and m.week.lit == 4, "counters clamped")
	B.rollWeek(m, 9)
	eq(m.week.id, 10, "weeks never roll back")
	B.rollWeek(m, 12)
	ok(m.week.id == 12 and m.week.lit == 0 and m.week.claimed == false, "a new week starts fresh")
	ok(not B.canClaim(m, 12, 999), "no claim without lighting")
	m.week.lit = 1
	ok(not B.canClaim(m, 12, B.WEEK_GOAL - 1), "no claim below the goal")
	ok(B.canClaim(m, 12, B.WEEK_GOAL), "claim at the goal")
	ok(not B.canClaim(m, 13, B.WEEK_GOAL), "a past week cannot be claimed")
	eq(B.weekOf(B.WEEK * 5 + 3), 5, "UTC weeks")
end
-- Integration: commissions, quests and the helper, renown, calculator, unlocks.
do
	local CL, n = Data.CommissionsLogs, 0
	for _, t in ipairs(CL.Tasks) do
		if t.kind == "kindle" then
			n += 1
			ok(t.skill == "Beaconry" and B.LogById[t.target] and t.levels.Beaconry >= B.LogById[t.target].level, t.id .. " kindle commission")
		end
	end
	eq(n, 4, "four kindle commissions")
	for _, id in ipairs({"KindlingLessons", "TheLongWatch"}) do
		local q = Data.QuestById[id]
		ok(q and q.line == "side" and Data.Quests[q.index] == q, id .. " registered")
		for _, o in ipairs(q.objectives) do
			ok(not has(Data.describeCheck(o), "Complete beacon") and Data.describeCheck(o) ~= "Unknown task", id .. " objective reads well: " .. Data.describeCheck(o))
			ok(Data.Systems.Helper.specsFor(o, {access = {}}) ~= nil, id .. " objective has a helper waypoint")
		end
		for stat in pairs(q.rewards.perk or {}) do ok(stat ~= "health" and stat ~= "defense", id .. " perk stays outside the Health/Defense budget") end
	end
	-- QC: the keeper the quest names exists (Hub folk with dialogue pointing at the network).
	local keeperNpc = Data.Townsfolk.NPCs[B.KEEPER]
	ok(keeperNpc and keeperNpc.anchorOnly and table.find(Data.Townsfolk.RegionFolkOrder, B.KEEPER) and Data.RegionArt.FolkByRole[B.KEEPER].region == "Hub", "Beaconkeeper is Hub folk")
	ok(has(Data.QuestById.KindlingLessons.story, keeperNpc.name) and not has(Data.QuestById.KindlingLessons.story, "Brannoch"), "Kindling Lessons names the Beaconkeeper")
	do
		local points, atlas = false, false
		for _, node in pairs(keeperNpc.nodes) do
			for _, o in ipairs(node.options) do
				if type(o.waypoint) == "table" and o.waypoint[1] == "anchor:Waypoint_Beacon_Hub" then points = true end
				if o.atlas == "Beaconry" then atlas = true end
				if o.to then ok(keeperNpc.nodes[o.to] ~= nil, "keeper option leads to a node: " .. o.to) end
			end
		end
		ok(points and atlas and has(keeperNpc.nodes.network.text, "Crownfire Beacon"), "keeper dialogue points to the beacon network")
	end
	local guide = Data.Systems.Helper.questGuide(Data.QuestById.KindlingLessons, nil, {accepted = true, access = {}})
	ok(guide and #guide.steps >= 3, "quest helper builds steps for Kindling Lessons")
	local RN = Data.Renown
	ok(RN.SourceById.beacons ~= nil, "renown source registered")
	local r0 = RN.breakdown({}, P, nil)
	local r1 = RN.breakdown({beaconry = {beacons = {Hub = 1, Meadow = 4, Bogus = 9}, weeks = 3}}, P, nil)
	eq(r1.total - r0.total, 2 * B.RENOWN_BEACON + 3 * B.RENOWN_WEEK, "renown: distinct beacons and weeks")
	local rMax = RN.breakdown({beaconry = {beacons = {Hub = 1}, weeks = 1e9}}, P, nil)
	eq(rMax.sources.beacons.xp, B.RENOWN_BEACON + B.RENOWN_WEEKS_CAP * B.RENOWN_WEEK, "renown weeks are capped")
	local acts = Data.Systems.Calc.actions("Beaconry")
	ok(#acts == #B.Logs + #B.BeaconOrder, "XP calculator lists logs and beacons")
	ok(table.find(Data.Systems.Calc.skills(), "Beaconry") ~= nil, "Beaconry in the calculator")
	local unlocks = B.unlocks()
	ok(#unlocks >= #B.Logs + #B.BeaconOrder, "unlock list")
end
-- Balance (documented in §37). Supply chain vs Woodcutting on the same log,
-- banked cadence vs the Crafting station, and time to 99.
do
	local rows = {}
	for _, log in ipairs(B.Logs) do
		local lvl = math.min(99, log.level + 10)
		local chain, wc, banked = B.chainRate(lvl, log, 1), B.woodcuttingRate(log), B.bankedRate(lvl, log, 1)
		ok(chain >= 0.6 * wc and chain <= 1.3 * wc, log.id .. " chop-and-kindle XP/h within 0.6-1.3x Woodcutting (" .. math.floor(chain) .. " vs " .. math.floor(wc) .. ")")
		ok(banked <= log.xp * 3600 / B.KINDLE_SECONDS + 1, log.id .. " banked rate is cadence-bound")
		table.insert(rows, string.format("%s L%d %d XP: chain %.1fk/h (WC %.1fk), banked %.0fk/h", log.id, log.level, log.xp, chain / 1000, wc / 1000, banked / 1000))
	end
	-- Banked kindling never outpaces a Crafting station on banked materials (Stormmantle 400 XP / 2.4 s).
	local best = B.Logs[#B.Logs]
	ok(B.bankedRate(99, best, 3) <= 400 * 3600 / 2.4, "banked Beaconry <= banked Crafting station")
	-- Hours to 99 kindling banked logs at the best log open at each level (OSRS Firemaking 99 ~ 25-40 h banked).
	local hours, xp = 0, 0
	for lvl = 1, 98 do
		local log = B.Logs[1]
		for _, l in ipairs(B.Logs) do if l.level <= lvl then log = l end end
		local need = X[lvl + 1] - X[lvl]
		hours += need / B.bankedRate(lvl, log, if lvl >= 60 then 3 elseif lvl >= 30 then 2 else 1)
		xp += need
	end
	ok(hours >= 15 and hours <= 60, string.format("banked 1-99 takes %.1f h (OSRS-like)", hours))
	print("Beaconry balance: " .. table.concat(rows, "; ") .. string.format(". Banked 1-99: %.1f h.", hours))
end
print("PASS: " .. (checks - partA) .. " Beaconry data/rule assertions.")

------------------------------------------------------------------------------
-- Part B: world pyres (real instances) and the campfire renderer.
------------------------------------------------------------------------------
local partB = checks
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f)
			local c = {Connected = true}
			function c:Disconnect() self.Connected = false end
			table.insert(listeners, {f, c})
			return c
		end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local worldEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function() end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
	UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local worldSource = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
luau.load(worldSource, {environment = worldEnv, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
local beaconPrompt, beaconModel = {}, {}
local pyreParts, anchors = 0, 0
for _, q in islands:GetDescendants() do
	if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "beaconLight" then
		local id = q:GetAttribute("IsleItem")
		ok(B.Beacons[id] ~= nil and beaconPrompt[id] == nil, "one prompt per beacon: " .. tostring(id))
		beaconPrompt[id] = q
		eq(q:GetAttribute("IsleRegion"), B.Beacons[id].region, id .. " prompt carries its region gate")
		ok(math.abs(q.HoldDuration - 0.36) < 1e-6 and q.MaxActivationDistance == 9, id .. " uses the interact hold")
		local node = q.Parent
		while node and not node:GetAttribute("BeaconId") do node = node.Parent end
		ok(node and node:GetAttribute("BeaconContent") == true and node:GetAttribute("BeaconId") == id, id .. " sits in its BeaconContent model")
		beaconModel[id] = node
	end
end
for _, id in ipairs(B.BeaconOrder) do
	local m = beaconModel[id]
	ok(m ~= nil, id .. " pyre built")
	local isle = islands:FindFirstChild(Data.Exploration.ShrineIsle[B.Beacons[id].region])
	ok(isle and m:IsDescendantOf(isle), id .. " on its region's island")
	local anchor = isle:FindFirstChild("Anchor_Waypoint_Beacon_" .. id, true)
	ok(anchor ~= nil, id .. " waypoint anchor")
	if anchor then anchors += 1 end
	local shapes, lights, neon = {}, 0, 0
	for _, obj in m:GetDescendants() do
		if obj:IsA("BasePart") then
			pyreParts += 1
			ok(obj.Anchored, obj.Name .. " anchored")
			if obj:GetAttribute("Shape") then shapes[obj:GetAttribute("Shape")] = true end
			if obj.Material == roblox.Enum.Material.Neon then neon += 1 end
		elseif obj:IsA("Light") then
			lights += 1
			ok(obj.Enabled == false and obj:GetAttribute("NightLight") == true and obj:GetAttribute("LightWanted") == false, id .. " light starts dark and unwanted (§35)")
			ok(obj.Brightness <= 1.5, id .. " light brightness modest")
		elseif obj:IsA("Fire") or obj:IsA("ParticleEmitter") then
			ok(obj.Enabled == false, id .. " " .. obj.Name .. " starts off")
		end
	end
	eq(lights, 1, id .. " one night light")
	eq(neon, 0, id .. " no Neon until lit (§30 neon budget)")
	for _, s in ipairs({"Column", "Cauldron", "TimberBundle"}) do ok(shapes[s], id .. " reuses the " .. s .. " mesh slot") end
	-- Clear of creature spawn markers.
	local pos = beaconPrompt[id].Parent.CFrame.Position
	for _, marker in world:FindFirstChild("MonsterSpawns"):GetChildren() do
		local c = marker.CFrame.Position
		ok(Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude >= 10, id .. " clear of " .. marker.Name)
	end
end
eq(pyreParts, 36, "documented pyre parts (4 x 9)")
do -- QC: the Beaconkeeper stands beside the Quayfire, clear of other townsfolk.
	local quay = islands:FindFirstChild(Data.Exploration.ShrineIsle.Hub)
	local keeper, others = nil, {}
	for _, obj in quay:GetDescendants() do
		if obj.Name == "Anchor_NPC_" .. B.KEEPER then ok(keeper == nil, "one keeper anchor") keeper = obj
		elseif obj:IsA("BasePart") and string.sub(obj.Name, 1, 11) == "Anchor_NPC_" then table.insert(others, obj.CFrame.Position) end
	end
	ok(keeper ~= nil, "Beaconkeeper anchor on Compass Quay")
	local pyre = beaconPrompt.Hub.Parent.CFrame.Position
	local k = keeper.CFrame.Position
	local d = Vector3.new(k.X - pyre.X, 0, k.Z - pyre.Z).Magnitude
	ok(d > beaconPrompt.Hub.MaxActivationDistance and d <= 16, string.format("keeper beside the Quayfire (%.1f studs)", d))
	for _, q in others do ok(Vector3.new(k.X - q.X, 0, k.Z - q.Z).Magnitude >= 6.9, "keeper clear of other townsfolk") end
end
eq(pyreParts + anchors, 45, "documented Beaconry static parts (45)")
do
	local total = 0
	for _, obj in world:GetDescendants() do if obj:IsA("BasePart") then total += 1 end end
	ok(total < 4000, "static world stays under the 4000 part budget (" .. total .. ")")
	print("World: " .. total .. " static parts (" .. (pyreParts + anchors) .. " Beaconry).")
end
-- Renderer: campfires and beacon flames from the published attributes.
local Pyre = load("beaconry.server.lua", {
	game = {GetService = function(_, name)
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return dataModule end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
	Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function() return Data end,
})
ok(type(Pyre) == "table" and Pyre.sync, "renderer loaded")
local T0 = 1000000
world:SetAttribute("BeaconryFires", "1:10.0:5.0:20.0:1:" .. (T0 + 60) .. ";2:30.5:5.0:-4.0:7:" .. (T0 + 5) .. ";junk;3:1:2")
world:SetAttribute("BeaconryBeacons", "Hub:" .. (T0 + 300) .. ";Meadow:" .. (T0 - 1) .. ";Fake:" .. (T0 + 99))
Pyre.sync(T0)
local camp = world:FindFirstChild("AetherIsles"):FindFirstChild("Campfires")
ok(camp ~= nil, "campfires live under AetherIsles (a §35 light root)")
eq(#camp:GetChildren(), 2, "two valid campfires drawn (malformed entries skipped)")
for _, m in camp:GetChildren() do
	local parts, light = 0, nil
	for _, obj in m:GetDescendants() do
		if obj:IsA("BasePart") then parts += 1; ok(not obj.CanCollide and obj.Anchored, "campfire parts never collide") end
		if obj:IsA("Light") then light = obj end
	end
	eq(parts, Pyre.PARTS, m.Name .. " has " .. Pyre.PARTS .. " parts")
	ok(light and light:GetAttribute("LightWanted") == true and light:GetAttribute("NightLight") == true and light.Brightness <= 1.5, m.Name .. " night light wanted")
	ok(m:FindFirstChild("Campfire flame"):FindFirstChildWhichIsA("Fire") ~= nil, m.Name .. " has a Fire")
	local logs = 0
	for _, obj in m:GetChildren() do if obj:GetAttribute("Shape") == "Log" then logs += 1 end end
	eq(logs, 2, m.Name .. " two crossed Log meshes")
end
local dw = camp:FindFirstChild("Campfire 2"):FindFirstChild("Campfire flame"):FindFirstChild("Flame")
ok(dw.Size < 3 + 7 * 0.4, "a campfire in its last seconds dwindles")
local hubFlame = beaconModel.Hub:FindFirstChild("Beacon flame", true)
ok(hubFlame.Transparency < 1 and hubFlame.Material == roblox.Enum.Material.Neon, "lit beacon shows its flame")
ok(hubFlame:FindFirstChildWhichIsA("Light"):GetAttribute("LightWanted") == true, "lit beacon light wanted (§35 director)")
ok(hubFlame:FindFirstChildWhichIsA("Fire").Enabled, "lit beacon fire on")
eq(beaconPrompt.Hub.ActionText, "Bask", "lit beacon prompt reads Bask")
local meadowFlame = beaconModel.Meadow:FindFirstChild("Beacon flame", true)
ok(meadowFlame.Transparency == 1 and meadowFlame:FindFirstChildWhichIsA("Light"):GetAttribute("LightWanted") == false, "expired beacon stays dark")
world:SetAttribute("BeaconryFires", "1:10.0:5.0:20.0:1:" .. (T0 + 60))
world:SetAttribute("BeaconryBeacons", "")
Pyre.sync(T0 + 10)
eq(#camp:GetChildren(), 1, "a burnt-out campfire is removed")
ok(hubFlame.Transparency == 1 and hubFlame:FindFirstChildWhichIsA("Light"):GetAttribute("LightWanted") == false and beaconPrompt.Hub.ActionText == "Light", "beacon goes dark")
do
	local many = {}
	for i = 1, B.MAX_FIRES + 10 do table.insert(many, i .. ":" .. (i * 4) .. ":5:0:1:" .. (T0 + 100)) end
	world:SetAttribute("BeaconryFires", table.concat(many, ";"))
	Pyre.sync(T0)
	ok(#camp:GetChildren() <= B.MAX_FIRES, "renderer never draws more than MAX_FIRES campfires")
	world:SetAttribute("BeaconryFires", "")
	Pyre.sync(T0)
	eq(#camp:GetChildren(), 0, "all campfires cleared")
end
print("PASS: " .. (checks - partB) .. " Beaconry world/renderer assertions.")

------------------------------------------------------------------------------
-- Part C: server behaviour.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local clock, utc = 10, B.WEEK * 2480 + 1000
local function advance(seconds) clock += seconds; utc += seconds end
local data = {}
local db = {}
function db:GetAsync(key) return copy(data[key]) end
local commitThenFail = false
function db:UpdateAsync(key, op)
	local value = op(copy(data[key]))
	if value ~= nil then data[key] = copy(value) end
	if commitThenFail then commitThenFail = false; error("DataStore request timed out (but committed)") end
	return copy(data[key])
end
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P}
local rolls, defaultRoll = {}, 0.999
local function nextRoll() if #rolls > 0 then return table.remove(rolls, 1) end return defaultRoll end
local function queue(...) for _, v in ipairs({...}) do table.insert(rolls, v) end end
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {FindFirstChild = function() return nil end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "beaconry-test" end},
	RunService = {IsStudio = function() return false end},
}
-- Ground under the kindler: a raycast double. ground = the node chain the ray hits.
local function node(name, parent) return {Name = name, Parent = parent, GetAttribute = function() return nil end} end
local fakeWorkspace = {attrs = {}}
local islandsNode = node("Islands", fakeWorkspace)
local quay = node("Compass Quay", islandsNode)
local GROUND = {
	meadow = node("Meadow", quay), path = node("Path", quay), bridge = node("Continuous bridge deck", quay),
	home7 = node("Meadow", node("WayfarersRest_7001", node("AetherIsles", fakeWorkspace))),
	other = node("Meadow", node("WayfarersRest_9999", node("AetherIsles", fakeWorkspace))),
	lair = node("Floor", node("Arena", node("LairInstances", fakeWorkspace))),
}
local ground = "meadow"
function fakeWorkspace:GetAttribute(key) return self.attrs[key] end
function fakeWorkspace:SetAttribute(key, value) self.attrs[key] = value end
function fakeWorkspace:FindFirstChild(name)
	if name == "Islands" then return islands end
	if name == "MonsterSpawns" then return world:FindFirstChild("MonsterSpawns") end
	return nil
end
function fakeWorkspace:Raycast(origin)
	if ground == "air" then return nil end
	return {Instance = GROUND[ground], Position = Vector3.new(origin.X, origin.Y - 4, origin.Z)}
end
local coroutines, yieldOf = {}, {}
closeHandlers = {}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function(_, f) closeHandlers = closeHandlers or {}; table.insert(closeHandlers, f) end},
	workspace = fakeWorkspace, Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function()
		local o = {Event = signal(), FireClient = function(_, player, state) player.last = state; player.pushes = (player.pushes or 0) + 1 end}
		table.insert(serverObjects, o)
		return o
	end},
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return nextRoll() end} end},
	task = {
		spawn = function(f, ...)
			local co = coroutine.create(f)
			local okRun, err = coroutine.resume(co, ...)
			assert(okRun, err)
			if coroutine.status(co) == "suspended" then table.insert(coroutines, co) end
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) yieldOf[coroutine.running()] = t; return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local ticker, saver
for _, co in ipairs(coroutines) do
	if yieldOf[co] == B.TICK then ok(ticker == nil, "exactly one Beaconry loop") ticker = co end
	if yieldOf[co] == 55 then saver = co end
end
ok(ticker ~= nil, "Beaconry loop runs every B.TICK")
eq(fakeWorkspace.attrs.BeaconryFires, "", "no campfires published at start")
ok(has(fakeWorkspace.attrs.BeaconryWeek, ":0:" .. B.WEEK_GOAL), "week published at start")
local function tick() assert(coroutine.resume(ticker, B.TICK)) end
local function run(seconds)
	local steps = math.ceil(seconds / B.TICK - 1e-9)
	for _ = 1, steps do advance(B.TICK + 1e-4); tick() end
end
local function player(id, name)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 10, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Name = name or ("Wayfarer" .. id), Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	services.Players.PlayerAdded:Fire(p)
	return p
end
local online = {}
local function leave(p) services.Players.PlayerRemoving:Fire(p); if online[p.UserId] == p then online[p.UserId] = nil end end
-- (Re)join with a mutated saved journal; an online session of that user leaves first.
local function seeded(id, mutate)
	if online[id] then leave(online[id]) end
	if not data["p" .. id] then leave(player(id)) end
	mutate(data["p" .. id].profile)
	online[id] = player(id)
	return online[id]
end
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction RemoteFunction found")
-- Leases last 180 s and are renewed by the 55 s autosave loop: every command
-- (and every long jump) runs one autosave pass first.
local function renew() if saver then assert(coroutine.resume(saver, 55)) end end
local function jump(seconds)
	while seconds > 0 do
		local s = math.min(100, seconds)
		advance(s)
		renew()
		seconds -= s
	end
end
local function cmd(p, verb, item)
	advance(1)
	renew()
	return remote.OnServerInvoke(p, verb, item)
end
local function use(p, q, offset)
	advance(1)
	renew()
	p.root.Position = q.Parent.CFrame.Position + (offset or Vector3.new(0, 0, 3))
	p.last = nil
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
local function fires() return fakeWorkspace.attrs.BeaconryFires or "" end
local function fireCount() local n = 0 for _ in string.gmatch(fires(), "[^;]+") do n += 1 end return n end

-- A new kindler: no striker, then the gates.
local k = seeded(7001, function(prof)
	prof.xp.Beaconry = X[16]
	prof.xp.Cooking = X[20]
	prof.items = {Timber = 10, WindpineLog = 3, EmberoakLog = 2, Fish = 4, Herb = 4}
	prof.questCompleted = 2
end)
local s0 = cmd(k, "state")
ok(type(s0.beaconry) == "table" and s0.beaconry.striker == nil and s0.beaconry.week.goal == B.WEEK_GOAL, "snapshot carries beaconry")
eq(s0.levels.Beaconry, 16, "Beaconry level in the snapshot")
ok(has(cmd(k, "kindle", "Timber").message, "Flint Striker"), "no kindling without a striker")
k = seeded(7001, function(prof) prof.items.FlintStriker = 1 end)
ok(has(cmd(k, "kindle", "EmberoakLog").message, "requires Beaconry 30"), "log level gate")
ok(has(cmd(k, "kindle", "Nope").message, "Choose a log"), "unknown log")
ok(has(cmd(k, "beaconLight", "Hub").message, "pyres"), "beacons are lit only at their pyre (prompt)")
-- Ground refusals.
for _, case in ipairs({{"path", "path or bridge"}, {"bridge", "path or bridge"}, {"other", "another wayfarer"}, {"lair", "open ground of the isles"}, {"air", "solid ground"}}) do
	ground = case[1]
	ok(has(cmd(k, "kindle", "Timber").message, case[2]), "refused on " .. case[1])
end
eq(cmd(k, "state").items.Timber, 10, "refusals spend nothing")
-- A failed spark keeps the log; the cadence holds the next strike.
ground = "meadow"
local chance = B.successChance(16, B.LogById.Timber, 1)
queue(0.999)
local f1 = cmd(k, "kindle", "Timber")
ok(has(f1.message, "fail to catch") and has(f1.message, math.floor(chance * 100 + .5) .. "%"), "a failed kindle shows the chance")
eq(f1.items.Timber, 10, "a failed kindle keeps the log")
ok(has(k.attrs.BeaconryGesture, "kindle:") and has(k.attrs.BeaconryGesture, ":FlintStriker"), "kindle gesture published with the striker")
eq(k.attrs.HeldItem, "FlintStriker", "the striker is in hand (§26 auto switch)")
eq(k.attrs.HeldAuto, true, "a temporary hold")
advance(0.3)
ok(has(remote.OnServerInvoke(k, "kindle", "Timber").message, "still smoking"), "one attempt per B.KINDLE_SECONDS")
advance(B.KINDLE_SECONDS)
-- Success: a campfire, XP, the flag and a commission credit.
local xp0 = f1.xp.Beaconry
queue(0.0)
local f2 = cmd(k, "kindle", "Timber")
ok(has(f2.message, "catches") and has(f2.message, "+" .. B.LogById.Timber.xp .. " Beaconry XP"), "kindle success")
eq(f2.items.Timber, 9, "one log spent")
eq(f2.xp.Beaconry, xp0 + B.LogById.Timber.xp, "Beaconry XP")
eq(fireCount(), 1, "campfire published")
ok(string.match(fires(), "^1:0%.0:7%.0:0%.0:1:%d+$") ~= nil, "fire entry id:x:y:z:tier:until at the ground point")
eq(f2.beaconry.kindled.Timber, 1, "kindled tally")
eq(#f2.beaconry.fires, 1, "own fire listed")
-- Commissions (§20): a "kindle" task on today's board takes one credit per campfire.
k = seeded(7001, function(prof)
	prof.commissions = prof.commissions or {}
	prof.commissions.day = Data.CommissionsLogs.dayOf(utc)
	prof.commissions.slots = {{id = "KindleTimber", progress = 0}}
end)
k.root.Position = Vector3.new(-20, 10, 40)
advance(B.KINDLE_SECONDS)
queue(0.0)
ok(has(cmd(k, "kindle", "Timber").message, "catches"), "kindle for the commission")
leave(k)
online[7001] = nil
do
	local slot = data["p7001"].profile.commissions.slots[1]
	ok(slot and slot.id == "KindleTimber" and slot.progress == 1, "kindle commission credited")
end
k = seeded(7001, function() end)
k.root.Position = Vector3.new(0, 10, 0)
-- Spacing: the same spot refuses.
advance(B.KINDLE_SECONDS)
ok(has(cmd(k, "kindle", "Timber").message, "already burning"), "campfires keep their spacing")
-- Per-player cap: a fifth fire snuffs the oldest (and its ash goes to the kindler).
for i = 1, B.MAX_PER_PLAYER do
	k.root.Position = Vector3.new(i * 6, 10, 0)
	advance(B.KINDLE_SECONDS)
	queue(0.0)
	cmd(k, "kindle", "Timber")
end
eq(fireCount(), B.MAX_PER_PLAYER, "at most MAX_PER_PLAYER fires per kindler")
eq(string.match(fires(), "^(%d+):"), "3", "the two oldest fires were snuffed")
local sAsh = cmd(k, "state")
eq(sAsh.items.PyreAsh, 2, "a snuffed fire leaves ash")
eq(sAsh.collection.PyreAsh, 2, "ash counts toward its collection (collect path)")
-- Campfire cooking on our own fire.
k.root.Position = Vector3.new(6, 10, 2) -- beside fire 2 (6, 7, 0)
ok(has(cmd(k, "fireCook", "BeaconwatchStew:2").message, "requires Cooking 58"), "Cooking level gate")
local c1 = cmd(k, "fireCook", "CookedFish:3")
ok(has(c1.message, "Cooking 3×") and has(c1.message, "1.8s each"), "campfire batch started")
eq(k.attrs.BeaconryJob, "CookedFish:0:3", "job published")
local cookXp0 = c1.xp.Cooking
queue(0.99) -- no burn
run(B.COOK_SECONDS)
local c2 = k.last
eq(c2.items.CookedFish, 1, "cooked one")
eq(c2.items.Fish, 3, "fish spent")
eq(c2.xp.Cooking, cookXp0 + B.cookXp(Data.Recipes.CookedFish), "+10% Cooking XP")
ok(has(k.attrs.BeaconryGesture, "flip:"), "flip gesture per cook")
-- A burn (Cooking 20 vs level 1: 35% x (1 - 19/30) = 12.8%).
queue(0.01)
run(B.COOK_SECONDS)
local c3 = k.last
eq(c3.items.CookedFish or 0, 1, "burnt food is lost")
eq(c3.items.Fish, 2, "ingredients spent on a burn")
eq(c3.beaconry.burnt, 1, "burn tally")
ok(has(c3.message, "burnt"), "burn message")
-- Walking away ends the batch.
k.root.Position = Vector3.new(200, 10, 0)
queue(0.99)
run(B.COOK_SECONDS)
ok(has(k.last.message, "stepped away"), "leaving the fire stops cooking")
eq(k.attrs.BeaconryJob, "", "job cleared")
eq(k.last.items.Fish, 2, "nothing spent away from the fire")
ok(has(cmd(k, "fireCook", "CookedFish:1").message, "Stand beside a lit campfire"), "no campfire, no cooking")
ok(has(cmd(k, "fireCook", "BrassIngot:1").message, "Choose a campfire recipe"), "only campfire recipes")
do -- QC L4: campfire cooking keeps every Data.Recipes gate (Progression.canCraft).
	local rec = Data.Recipes.CookedFish
	local saved = rec.collectionTier
	rec.collectionTier = {Fish = 9}
	ok(has(cmd(k, "fireCook", "CookedFish:1").message, "collection tier"), "L4: a collection-tier gate holds at the campfire")
	rec.collectionTier = saved
end
ok(has(cmd(k, "fireStop").message, "not cooking"), "stop with no job")
-- Campfire-only dish (never burns), then the fire burns out under the cook.
k = seeded(7001, function(prof) prof.xp.Cooking = X[30]; prof.items.Glassfin = 4; prof.items.Sunwheat = 4 end)
k.root.Position = Vector3.new(12, 10, 2) -- beside fire 3 (12, 7, 0)
local d1 = cmd(k, "fireCook", "HearthfireSkewer:2")
ok(has(d1.message, "Hearthfire Skewer"), "campfire dish batch")
queue(0.0)
run(B.COOK_SECONDS)
eq(k.last.items.HearthfireSkewer, 1, "campfire dish cooked even on a low roll (never burns)")
-- Burn-out: every remaining fire goes out on the tick; ash to the online kindler.
local ashBefore = k.last.items.PyreAsh or 0
jump(400)
tick()
eq(fireCount(), 0, "campfires burn out on the timer")
eq(k.attrs.BeaconryJob, "", "the cook stops when the fire burns out")
eq(cmd(k, "state").items.PyreAsh, ashBefore + B.MAX_PER_PLAYER, "every burnt-out fire leaves one Pyre Ash")
-- Beacons: a level-1 Quayfire at the hub pyre.
local hubQ = beaconPrompt.Hub
k = seeded(7001, function(prof) prof.items.Timber = 2 end)
ok(has(use(k, hubQ).message, "Feed the Quayfire Beacon " .. B.BEACON_LOGS), "a beacon needs a full feed")
k = seeded(7001, function(prof) prof.items.Timber = 8; prof.items.WindpineLog = 0 end)
local bystander = seeded(7002, function(prof) prof.xp.Beaconry = 0 end)
bystander.root.Position = hubQ.Parent.CFrame.Position + Vector3.new(30, 0, 0)
local far = seeded(7003, function(prof) end)
far.root.Position = hubQ.Parent.CFrame.Position + Vector3.new(500, 0, 0)
local xpB = cmd(k, "state").xp.Beaconry
local b1 = use(k, hubQ)
ok(has(b1.message, "blazes up") and has(b1.message, "Week: 1/" .. B.WEEK_GOAL), "beacon lit")
eq(b1.items.Timber, 2, "six logs fed")
eq(b1.xp.Beaconry, xpB + B.beaconXp(B.LogById.Timber), "beacon XP (x1.5 per log)")
ok(has(fakeWorkspace.attrs.BeaconryBeacons, "Hub:"), "lit beacon published")
local warmth = data["p7001"] and k.last.depth and k.last.depth.buffs and k.last.depth.buffs[B.WARMTH_ID]
ok(warmth and warmth.stats.health == 20, "Beacon Warmth on the lighter")
local bs = cmd(bystander, "state")
local bsXp = bs.xp.Beaconry or 0
ok(bs.depth.buffs[B.WARMTH_ID] ~= nil, "a bystander within the radius is warmed")
ok(cmd(far, "state").depth.buffs[B.WARMTH_ID] == nil, "a far player is not")
eq(b1.beaconry.lit.Hub, 1, "beacon tally")
ok(has(k.attrs.BeaconryGesture, "kindle:"), "L3: a lit beacon plays the strike once from BeaconryGesture")
eq(b1.beaconry.week.lit, 1, "week contribution")
-- A lit beacon: basking refreshes warmth, never lights again.
local b2 = use(bystander, hubQ)
ok(has(b2.message, "bask"), "basking at a lit beacon")
eq(b2.xp.Beaconry or 0, bsXp, "basking pays no XP")
-- Gated beacons: level and region.
ok(has(use(k, beaconPrompt.Quarry).message, "requires Beaconry 20"), "beacon level gate")
-- The community total flushes to the DataStore key for the week.
run(B.FLUSH + 1)
local key = B.WEEK_KEY .. B.weekOf(utc)
eq(B.weekSum(data[key]), 1, "community total written once per flush")
-- Claims: not before the goal; then once.
ok(has(cmd(k, "beaconClaim").message, "1/" .. B.WEEK_GOAL), "no claim below the goal")
ok(has(cmd(bystander, "beaconClaim").message, "Light a beacon"), "basking does not join the watch")
data[key].base = (data[key].base or 0) + B.WEEK_GOAL + 2 -- other servers lit the rest (shared total GOAL + 3)
-- One more lighting here (after the beacon burns out) pushes a flush that reads the shared total.
jump(B.BEACON_SECONDS + 1)
tick()
ok(not has(fakeWorkspace.attrs.BeaconryBeacons, "Hub:"), "beacon goes dark after B.BEACON_SECONDS")
k = seeded(7001, function(prof) prof.items.Timber = 6 end)
use(k, hubQ)
run(B.FLUSH + 1)
eq(B.weekSum(data[key]), B.WEEK_GOAL + 4, "flush adds to the shared total")
local week = cmd(k, "state").beaconry.week
ok(week.total >= B.WEEK_GOAL and week.canClaim, "goal reached and claimable")
local sC = cmd(k, "state")
local xpBefore, lvlBefore = sC.xp.Beaconry, sC.levels.Beaconry -- snapshot tables are live: read the numbers now
local cl = cmd(k, "beaconClaim")
ok(has(cl.message, "burned bright"), "weekly claim")
eq(cl.xp.Beaconry, xpBefore + B.weekXp(lvlBefore), "weekly XP (scaled by the level before the claim)")
ok(has(cmd(k, "beaconClaim").message, "already claimed"), "claimed once a week")
eq(cmd(k, "state").beaconry.weeks, 1, "weeks tally")
-- Persistence and rejoin: the journal keeps tallies and flags; fires do not follow.
k = seeded(7001, function(prof)
	ok(prof.beaconLit == true and prof.beaconKindled == true, "flags saved")
	ok(prof.beaconry.beacons.Hub == 2 and prof.beaconry.week.claimed == true and prof.beaconry.weeks == 1, "tallies saved")
	prof.beaconry.kindled.Bogus = 5
end)
eq(cmd(k, "state").beaconry.kindled.Bogus, nil, "migration drops unknown logs")
-- Week rollover: the journal entry starts fresh; the server total resets.
advance(B.WEEK)
tick()
local nw = cmd(k, "state").beaconry.week
ok(nw.lit == 0 and nw.claimed == false and nw.total == 0, "a new week starts fresh")
do
	local wkey = B.WEEK_KEY .. B.weekOf(utc)
	-- QC M2: a claim below the goal re-reads the shared total before refusing.
	k = seeded(7001, function(prof) prof.items.Timber = 12 end)
	use(k, hubQ)
	data[wkey] = {base = B.WEEK_GOAL, s = {}} -- other servers reached the goal
	local cl2 = cmd(k, "beaconClaim")
	ok(has(cl2.message, "burned bright"), "M2: a claim re-reads the shared total before refusing: " .. tostring(cl2.message))
	-- QC M2: with nothing pending the total is refreshed periodically (GetAsync).
	run(B.FLUSH + 1)
	eq(B.weekSum(data[wkey]), B.WEEK_GOAL + 1, "our lighting written once")
	data[wkey].base += 7
	run(B.WEEK_REFRESH + 1)
	eq(cmd(k, "state").beaconry.week.total, B.WEEK_GOAL + 8, "M2: idle servers refresh the shared total")
	-- QC M3: a write that timed out but committed is not counted twice on retry.
	jump(B.BEACON_SECONDS + 1)
	tick()
	use(k, hubQ)
	commitThenFail = true
	run(B.FLUSH + 1)
	eq(B.weekSum(data[wkey]), B.WEEK_GOAL + 9, "the timed-out write committed")
	run(B.FLUSH + 1)
	run(B.FLUSH + 1)
	eq(B.weekSum(data[wkey]), B.WEEK_GOAL + 9, "M3: retries never double count")
	eq(cmd(k, "state").beaconry.week.total, B.WEEK_GOAL + 9, "M3: the server's total matches the store")
	jump(B.BEACON_SECONDS + 1)
	tick()
end
-- Everflame: with the mantle worn, kindles never fail and fires burn longer.
local master = seeded(7010, function(prof)
	prof.xp.Beaconry = X[99]
	prof.items = {StarmetalStriker = 1, ShatterbarkLog = 2}
end)
local wear = cmd(master, "masteryWear", "cape:Beaconry")
ok(has(wear.message, "Mantle"), "mantle worn")
-- The hub layout moves with world art passes: try open meadow spots until one
-- is clear of stations, townsfolk and paths (placement rules are tested above).
local ev
for _, spot in ipairs({Vector3.new(-40, 10, 0), Vector3.new(40, 10, 40), Vector3.new(-60, 10, -60), Vector3.new(70, 10, -20), Vector3.new(-20, 10, 80), Vector3.new(0, 10, -90), Vector3.new(90, 10, 60), Vector3.new(-95, 10, 30)}) do
	master.root.Position = spot
	queue(0.9999)
	ev = cmd(master, "kindle", "")
	if not has(ev.message, "Too close") and not has(ev.message, "open ground") and not has(ev.message, "path") then break end
end
ok(has(ev.message, "Shatterbark") and has(ev.message, "catches"), "Everflame: a kindle never fails; '' picks the best log: " .. tostring(ev.message))
local untilAt = tonumber(string.match(fires(), ":(%d+)$"))
eq(untilAt - math.floor(utc), B.fireSeconds(B.LogById.ShatterbarkLog, true), "Everflame fires burn 50% longer")
ok(cmd(master, "state").beaconry.everflame == true, "snapshot shows Everflame")
-- Server cap: kindlers without a fire are refused once MAX_FIRES burn.
do
	local B2 = B.MAX_FIRES
	local made = 1
	local id = 7100
	while made < B2 do
		local kp = seeded(id, function(prof) prof.xp.Beaconry = X[99]; prof.items = {FlintStriker = 1, Timber = 5} end)
		for j = 1, B.MAX_PER_PLAYER do
			if made >= B2 then break end
			kp.root.Position = Vector3.new((id - 7100) * 10 + 5000, 10, j * 6)
			advance(B.KINDLE_SECONDS)
			queue(0.0)
			local r = cmd(kp, "kindle", "Timber")
			ok(has(r.message, "catches"), "cap filler kindles: " .. tostring(r.message))
			ok(fireCount() <= B.MAX_FIRES, "M1: total never exceeds MAX_FIRES")
			made += 1
		end
		id += 1
	end
	eq(fireCount(), B.MAX_FIRES, "server holds MAX_FIRES campfires")
	local late = seeded(7999, function(prof) prof.items = {FlintStriker = 1, Timber = 5} end)
	late.root.Position = Vector3.new(-300, 10, 0)
	ok(has(cmd(late, "kindle", "Timber").message, "Too many fires"), "server-wide fire cap")
	-- QC M1: at the cap a kindler who owns a fire (fewer than MAX_PER_PLAYER) snuffs their own oldest.
	master.root.Position = Vector3.new(-60, 10, 0)
	advance(B.KINDLE_SECONDS)
	local m1 = cmd(master, "kindle", "ShatterbarkLog")
	ok(has(m1.message, "catches"), "M1: a kindler with a fire may kindle at the cap: " .. tostring(m1.message))
	eq(fireCount(), B.MAX_FIRES, "M1: the server total never exceeds MAX_FIRES")
	eq(#m1.beaconry.fires, 1, "M1: the kindler's own oldest fire made room")
	ok(not string.find(fires(), ":%-40%.0:"), "M1: the old fire at -40 is gone")
end
-- QC H1: Shatterbark at Quayfire, Beaconry 1 — a log you cannot kindle never feeds a beacon.
do
	local novice = seeded(7300, function(prof) prof.xp.Beaconry = 0; prof.items = {FlintStriker = 1, ShatterbarkLog = 6} end)
	local r = use(novice, hubQ)
	ok(has(r.message, "Feed the Quayfire Beacon") and has(r.message, "you can kindle"), "H1: Shatterbark at Quayfire, Beaconry 1 is refused: " .. tostring(r.message))
	eq(r.items.ShatterbarkLog, 6, "H1: nothing spent")
	ok(not has(fakeWorkspace.attrs.BeaconryBeacons, "Hub:"), "H1: Quayfire stays dark")
	local vet = seeded(7301, function(prof) prof.xp.Beaconry = X[95]; prof.items = {FlintStriker = 1, ShatterbarkLog = 6} end)
	local xp0 = cmd(vet, "state").xp.Beaconry
	local r2 = use(vet, hubQ)
	ok(has(r2.message, "blazes up") and has(r2.message, "+" .. B.beaconXpFor(B.Beacons.Hub) .. " Beaconry XP"), "H1: a master feeds Shatterbark to Quayfire")
	eq(r2.xp.Beaconry - xp0, B.beaconXpFor(B.Beacons.Hub), "H1: Quayfire pays its own tier, not the Shatterbark spent")
	-- Server-hopping: the day's paid lightings live on the profile, so a fresh server pays nothing more.
	jump(B.BEACON_SECONDS + 1)
	tick()
	vet = seeded(7301, function(prof)
		prof.items.ShatterbarkLog = 6
		prof.beaconry.xpDay = {id = B.dayOf(utc), n = B.BEACON_XP_PER_DAY}
	end)
	local xp1 = cmd(vet, "state").xp.Beaconry
	local r3 = use(vet, hubQ)
	ok(has(r3.message, "blazes up") and has(r3.message, "no XP"), "H1: past the daily cap a beacon still lights")
	eq(r3.xp.Beaconry, xp1, "H1: no beacon XP past B.BEACON_XP_PER_DAY lightings per isle day")
	jump(B.BEACON_SECONDS + 1)
	tick()
end
-- QC L2: no campfire within B.SPOT_CLEARANCE of a prompt (stations, nodes, townsfolk).
do
	local spot
	-- A prompt clear of every beacon pyre (so the pyre rule cannot answer first).
	local pyres = {}
	for _, q in islands:GetDescendants() do
		if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "beaconLight" and q.Parent and q.Parent:IsA("BasePart") then table.insert(pyres, q.Parent.CFrame.Position) end
	end
	for _, q in islands:GetDescendants() do
		if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") ~= "beaconLight" and q.Parent and q.Parent:IsA("BasePart") then
			local p, clear = q.Parent.CFrame.Position, true
			for _, b in pyres do if Vector3.new(p.X - b.X, 0, p.Z - b.Z).Magnitude < B.BEACON_CLEARANCE + 8 then clear = false end end
			if clear then spot = p break end
		end
	end
	ok(spot ~= nil, "a world prompt to test against")
	local camper = seeded(7302, function(prof) prof.items = {FlintStriker = 1, Timber = 3}; prof.xp.Beaconry = X[50] end)
	camper.root.Position = spot + Vector3.new(B.SPOT_CLEARANCE - 2, 3, 0)
	ok(has(cmd(camper, "kindle", "Timber").message, "Too close to a station"), "L2: refused beside a prompt")
	local marker = world:FindFirstChild("MonsterSpawns"):GetChildren()[1]
	camper.root.Position = marker.CFrame.Position + Vector3.new(2, 3, 0)
	advance(B.KINDLE_SECONDS)
	ok(has(cmd(camper, "kindle", "Timber").message, "Too close to a station"), "L2: refused on a creature spawn marker")
	eq(cmd(camper, "state").items.Timber, 3, "L2: refusals spend nothing")
end
-- Leaving: the cook job ends, fires burn on (no ash for a departed kindler).
leave(master)
jump(400)
tick()
eq(fireCount(), 0, "fires of departed kindlers still burn out")
-- Ironman journals use every verb (no trade path).
local iron = seeded(7200, function(prof) prof.ironman = true; prof.items = {FlintStriker = 1, Timber = 2} end)
iron.root.Position = Vector3.new(-500, 10, 0)
queue(0.0)
ok(has(cmd(iron, "kindle", "Timber").message, "catches"), "Ironman kindles")
-- QC L1: BindToClose flushes pending lightings before the journals save.
do
	local wkey = B.WEEK_KEY .. B.weekOf(utc)
	local before = B.weekSum(data[wkey])
	k = seeded(7001, function(prof) prof.items.Timber = 6 end)
	ok(has(use(k, hubQ).message, "blazes up"), "a last lighting before shutdown")
	eq(B.weekSum(data[wkey]), before, "not yet flushed")
	ok(#closeHandlers >= 1, "BindToClose handler registered")
	local co = coroutine.create(closeHandlers[1])
	assert(coroutine.resume(co))
	eq(B.weekSum(data[wkey]), before + 1, "L1: BindToClose flushed the pending lighting")
end
print("PASS: " .. (checks - partC) .. " Beaconry server assertions.")
print("PASS: " .. checks .. " Beaconry assertions in total.")
print("SUITE-END verify-beaconry.luau")
