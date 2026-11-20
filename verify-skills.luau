-- Agility & Hunter: data rules, world placement and server behaviour.
-- Part A checks shared/GameData.lua (Data.Agility / Data.Hunter) and the
-- stat rules in shared/Progression.lua. Part B runs world.server.lua with
-- real Roblox instances and checks every course obstacle, shortcut, hunting
-- spot and vendor prompt. Part C runs server.server.lua against those same
-- world prompts (deterministic clock, rolls and DataStore doubles) and plays
-- laps, failures, skips, shortcuts, vendors, traps, nets and persistence.
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
local AG, HU = Data.Agility, Data.Hunter
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
for _, skill in ipairs({"Agility", "Hunter"}) do
	ok(table.find(Data.SkillOrder, skill) ~= nil, skill .. " registered in SkillOrder")
	local def = Data.Skills[skill]
	ok(def and def.perLevel and def.description and def.title and #def.color == 6, skill .. " skill metadata")
	for stat in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil, skill .. " perLevel stat " .. stat) end
end
eq(Data.Skills.Agility.perLevel.speed, 0.5, "Agility grants Speed per level")
for _, stat in ipairs({"surefoot", "trapLuck", "huntingFortune"}) do
	ok(Data.Stats[stat] ~= nil and table.find(Data.StatOrder, stat) ~= nil, "stat " .. stat .. " registered")
end
-- Courses.
ok(#AG.Courses >= 6 and #AG.Courses <= 8, "6-8 agility courses (" .. #AG.Courses .. ")")
eq(AG.Courses[1].level, 1, "first course at Agility 1")
ok(AG.Courses[#AG.Courses].level >= 75 and AG.Courses[#AG.Courses].level <= 80, "top course near Agility 80")
local courseIds, courseRegions = {}, {}
for i, course in ipairs(AG.Courses) do
	ok(courseIds[course.id] == nil, "unique course id " .. course.id)
	courseIds[course.id] = true
	courseRegions[course.region] = true
	eq(AG.CourseById[course.id], course, course.id .. " indexed")
	if i > 1 then ok(course.level > AG.Courses[i - 1].level, course.id .. " levels ascend") end
	ok(Data.RegionById[course.region] ~= nil, course.id .. " region exists")
	local n = #course.obstacles
	ok(n >= 5 and n <= 8, course.id .. " has 5-8 obstacles")
	eq(course.obstacles[1].kind, "climb", course.id .. " starts with a climb off the island")
	ok(course.obstacles[n].kind == "drop" or course.obstacles[n].kind == "zip", course.id .. " ends by returning to the island")
	ok(course.markChance > 0 and course.markChance < 1 and course.lapXp > 0, course.id .. " lap rewards")
	local risky, previousXp = 0, nil
	for j, o in ipairs(course.obstacles) do
		eq(o.index, j, course.id .. " obstacle index " .. j)
		ok(AG.Kinds[o.kind] ~= nil, course.id .. " obstacle kind " .. o.kind)
		ok(o.xp > 0 and o.duration > 0 and o.risk >= 0 and o.risk <= 0.3 and #o.name > 0, course.id .. " obstacle " .. j .. " values")
		if o.risk > 0 then risky += 1 end
	end
	ok(risky >= 1, course.id .. " has failure-prone obstacles")
	ok(AG.lapTotal(course) > course.lapXp, course.id .. " lap total includes obstacles")
	if i > 1 then ok(AG.lapTotal(course) > AG.lapTotal(AG.Courses[i - 1]), course.id .. " lap XP grows with level") end
end
local regionCount = 0
for _ in pairs(courseRegions) do regionCount += 1 end
ok(regionCount >= 6, "courses span six or more regions")
for kind, spec in pairs(AG.Kinds) do ok(type(spec.verb) == "string" and type(spec.anim) == "string" and spec.duration > 0, "kind " .. kind) end
-- Failure chance.
do
	local course = AG.CourseById.QuayRigging
	local o = course.obstacles[4]
	ok(o.risk > 0, "Hull ledge is risky")
	ok(near(AG.failChance(course, o, course.level, 0), o.risk), "full risk at the course level")
	ok(near(AG.failChance(course, o, course.level + 10, 0), o.risk / 2), "half risk ten levels above")
	eq(AG.failChance(course, o, course.level + AG.FAIL_FADE, 0), 0, "no risk FAIL_FADE levels above")
	ok(near(AG.failChance(course, o, course.level, 50), o.risk / 2), "Surefoot 50 halves the risk")
	eq(AG.failChance(course, o, course.level, 100), 0, "Surefoot 100 removes the risk")
	eq(AG.failChance(course, course.obstacles[1], 1, 0), 0, "riskless obstacle never fails")
	local last = 1
	for lvl = 1, 25 do local c = AG.failChance(course, o, lvl, 0); ok(c <= last, "fail chance falls with level " .. lvl); last = c end
	eq(AG.markChance(course, course.level), course.markChance, "full Skymark chance in range")
	eq(AG.markChance(course, course.level + AG.OVERLEVEL), course.markChance / 2, "overlevelled Skymark chance halves")
end
-- Run state machine.
do
	local c = AG.CourseById.QuayRigging
	local v, run = AG.step(nil, "QuayRigging", 2, 0)
	eq(v, "order", "cannot begin mid-course")
	eq(run, nil, "no run from an out-of-order start")
	v, run = AG.step(nil, "QuayRigging", 1, 10)
	eq(v, "start", "obstacle 1 starts a lap")
	eq(run.next, 2, "next obstacle after start")
	eq(run.readyAt, 10 + c.obstacles[1].duration, "busy for the obstacle duration")
	eq(run.deadline, run.readyAt + AG.STEP_WINDOW, "deadline after landing")
	eq((AG.step(run, "QuayRigging", 2, run.readyAt - 0.1)), "busy", "still moving")
	eq((AG.step(run, "QuayRigging", 3, run.readyAt + 1)), "order", "skipping obstacle 2 refused")
	eq((AG.step(run, "MosswakeHedgerow", 2, run.readyAt + 1)), "order", "another course refused")
	eq((AG.step(run, "QuayRigging", 2, run.deadline + 0.1)), "expired", "late obstacle breaks the lap")
	local r2
	v, r2 = AG.step(run, "QuayRigging", 2, run.readyAt + 1)
	eq(v, "next", "in-order obstacle")
	eq(r2.startedAt, 10, "lap start time kept")
	local cur, t = r2, r2.readyAt
	for i = 3, #c.obstacles do
		v, cur = AG.step(cur, "QuayRigging", i, t)
		t = cur.readyAt
	end
	eq(v, "lap", "final obstacle completes the lap")
	eq(cur.next, 1, "a lap returns to obstacle 1")
	eq((AG.step(cur, "QuayRigging", 2, t)), "order", "a new lap starts at obstacle 1")
	eq((AG.step(cur, "QuayRigging", 1, t)), "start", "restart after a lap")
	eq((AG.step(nil, "QuayRigging", 0, 0)), "order", "index 0 refused")
	eq((AG.step(nil, "QuayRigging", 1.5, 0)), "order", "fractional index refused")
	eq((AG.step(nil, "QuayRigging", 99, 0)), "order", "index past the end refused")
	eq((AG.step(nil, "Nowhere", 1, 0)), "order", "unknown course refused")
end
-- Lap milestones.
eq((AG.lapPerk({})), nil, "no lap milestones")
eq(AG.lapPerk({QuayRigging = 25}).speed, 1, "25 laps grants a Speed milestone")
eq(AG.lapPerk({QuayRigging = 250, TempestStormrun = 100}).speed, 5, "milestones add across courses")
eq((AG.lapPerk({Bogus = 500})), nil, "unknown courses grant nothing")
-- Shortcuts.
ok(#AG.Shortcuts >= 4, "four or more shortcuts")
local windpineShortcut = false
for _, sc in ipairs(AG.Shortcuts) do
	eq(AG.ShortcutById[sc.id], sc, sc.id .. " indexed")
	ok(AG.Kinds[sc.kind] ~= nil and sc.level >= 1 and sc.level <= 99 and sc.duration > 0 and sc.xp > 0, sc.id .. " values")
	ok(sc.region == nil or Data.RegionById[sc.region] ~= nil, sc.id .. " destination region")
	if sc.region == "Windpine" and sc.level == 20 then windpineShortcut = true end
end
ok(windpineShortcut, "an Agility 20 shortcut leads to Windpine Grove")
-- Windrunner outfit and the Skymark Exchange.
local wr = Data.Sets.Windrunner
eq(#wr.pieces, 4, "Windrunner has four pieces")
ok(wr.bonus.speed > 0 and wr.bonus.surefoot > 0, "Windrunner set bonus: Speed and Surefoot")
local slots = {}
for _, id in ipairs(wr.pieces) do
	local def = Data.Items[id]
	ok(def and def.kind == "armor" and def.set == "Windrunner" and def.requires.Agility ~= nil, id .. " is a Windrunner piece")
	ok(not slots[def.slot], id .. " has its own slot")
	slots[def.slot] = true
	ok((def.stats.speed or 0) > 0 and (def.stats.surefoot or 0) > 0, id .. " grants Speed and Surefoot")
end
eq(Data.Items.Skymark.kind, "material", "Skymarks are items")
for _, e in ipairs(AG.Shop) do
	ok(Data.Items[e.item] ~= nil and (e.cost.Skymark or 0) > 0, "Skymark Exchange sells " .. e.item .. " for Skymarks")
end
-- Hunter.
ok(#HU.Creatures >= 6 and #HU.Creatures <= 8, "6-8 hunter creatures")
eq(HU.Creatures[1].level, 1, "first creature at Hunter 1")
eq(HU.Creatures[#HU.Creatures].level, 80, "top creature at Hunter 80")
local methods = {}
for i, c in ipairs(HU.Creatures) do
	eq(HU.CreatureById[c.id], c, c.id .. " indexed")
	ok(HU.Methods[c.method] ~= nil, c.id .. " method")
	methods[c.method] = true
	ok(Data.RegionById[c.region] ~= nil, c.id .. " region")
	if i > 1 then ok(c.level > HU.Creatures[i - 1].level and c.xp > HU.Creatures[i - 1].xp, c.id .. " level and XP ascend") end
	eq(c.drops[1].chance, 1, c.id .. " always drops its primary material")
	for _, d in ipairs(c.drops) do ok(Data.Items[d.item] ~= nil and d.min >= 1 and d.max >= d.min, c.id .. " drop " .. d.item) end
	ok(c.base > 0 and c.base < 1, c.id .. " base chance")
	local lastChance = 0
	for lvl = c.level, 99, 7 do
		local chance = HU.catchChance(c, lvl, 0)
		ok(chance >= lastChance and chance <= 0.95, c.id .. " catch chance rises with level " .. lvl)
		lastChance = chance
	end
	ok(HU.catchChance(c, c.level, 20) > HU.catchChance(c, c.level, 0), c.id .. " Trap Luck helps")
end
for _, m in ipairs({"snare", "box", "bird", "net"}) do ok(methods[m], "creatures use " .. m) end
eq(HU.maxTraps(1), 1, "one trap at Hunter 1")
eq(HU.maxTraps(19), 1, "one trap at Hunter 19")
eq(HU.maxTraps(20), 2, "two traps at Hunter 20")
eq(HU.maxTraps(40), 3, "three traps at Hunter 40")
eq(HU.maxTraps(80), 5, "five traps at Hunter 80")
eq(HU.maxTraps(99), HU.MAX_TRAPS, "trap count capped")
-- Trap Luck is capped: more than HU.TRAP_LUCK_CAP buys nothing.
for _, c in ipairs(HU.Creatures) do
	ok(math.abs(HU.catchChance(c, 99, 1000) - HU.catchChance(c, 99, HU.TRAP_LUCK_CAP)) < 1e-12, c.id .. " Trap Luck capped")
	ok(HU.catchChance(c, 99, HU.TRAP_LUCK_CAP) <= HU.catchChance(c, 99, 0) * 1.26, c.id .. " Trap Luck adds at most +25%")
end
-- XP/h pacing model (from data). One action = interact hold 0.36 s + the
-- server's 0.65 s prompt cooldown; a gather is one hold (1 s) + cooldown, at
-- best every node respawn. Traps: every spot of the ground the player may
-- tend (min(maxTraps, spots)), each cycle = rolls until a catch or collapse
-- plus collecting and re-setting (two actions). Nets: three spots whose
-- shared post-catch swarm cooldown is creature.respawn, the player's own miss
-- cooldown HU.NET_MISS_COOLDOWN, with the best net bonus, capped by the swing rate.
do
	local ACTION, GATHER = 0.36 + 0.65, 1 + 0.65
	local TRAP_SPOTS, NET_SPOTS = 4, 3
	local bestNet = 0
	for _, id in ipairs(HU.Kits.net) do bestNet = math.max(bestNet, Data.Items[id].netBonus or 0) end
	local function gatherRate(level)
		local best = 0
		for _, tiers in pairs(Data.ResourceTiers) do
			for _, r in ipairs(tiers) do
				if r.level <= level then best = math.max(best, 3600 * r.xp / math.max(r.respawn, GATHER)) end
			end
		end
		return best
	end
	local function hunterRate(c, level, luck)
		local p = HU.catchChance(c, level, luck)
		if c.method == "net" then
			p = math.min(0.95, p + bestNet)
			local perSpot = c.respawn + (1 / p - 1) * math.max(HU.NET_MISS_COOLDOWN, ACTION)
			return 3600 * c.xp * math.min(NET_SPOTS / perSpot, p / ACTION)
		end
		local traps = math.min(HU.maxTraps(level), TRAP_SPOTS)
		local success = 1 - (1 - p) ^ HU.MAX_TICKS
		local rolls = success / p
		return traps * 3600 * c.xp * success / (HU.TICK * rolls + 2 * ACTION)
	end
	local celestium = 3600 * 300 / 20
	for _, r in ipairs(Data.ResourceTiers.Mining) do if r.id == "Celestium" then celestium = 3600 * r.xp / math.max(r.respawn, GATHER) end end
	local rows = {}
	for i, c in ipairs(HU.Creatures) do
		local nextLevel = if HU.Creatures[i + 1] then HU.Creatures[i + 1].level - 1 else 99
		for _, at in ipairs({{c.level, 0}, {c.level, HU.TRAP_LUCK_CAP}, {nextLevel, 0}, {nextLevel, HU.TRAP_LUCK_CAP}}) do
			local h, g = hunterRate(c, at[1], at[2]), gatherRate(at[1])
			local ratio = h / g
			ok(ratio >= 0.5 and ratio <= 1.5, string.format("%s at Hunter %d (Trap Luck %d): %.0f XP/h vs gathering %.0f (x%.2f) within 0.5..1.5",
				c.id, at[1], at[2], h, g, ratio))
		end
		table.insert(rows, string.format("%s %d: %.0f-%.0f XP/h (gathering %.0f)", c.id, c.level, hunterRate(c, c.level, 0), hunterRate(c, nextLevel, HU.TRAP_LUCK_CAP), gatherRate(c.level)))
	end
	local top = hunterRate(HU.Creatures[#HU.Creatures], 99, HU.TRAP_LUCK_CAP)
	ok(top / celestium >= 1.15 and top / celestium <= 1.45, string.format("top Hunter %.0f XP/h is about 1.3x Celestium mining %.0f (x%.2f)", top, celestium, top / celestium))
	print("Hunter XP/h: " .. table.concat(rows, "; ") .. string.format("; top %.0f vs Celestium %.0f", top, celestium))
end
for method, kits in pairs(HU.Kits) do
	for _, kit in ipairs(kits) do
		local def = Data.Items[kit]
		ok(def and def.kind == "material" and def.category == "trap" and def.hunterMethod == method, kit .. " is a " .. method .. " kit (not a gather tool)")
	end
end
eq((HU.logPerk({})), nil, "empty hunter log")
local logStats, logTiers = HU.logPerk({PuffcapHopper = 25, SunwingMoth = 10})
eq(logTiers, 3, "hunter log milestones counted")
eq(logStats.trapLuck, 1.5, "hunter log Trap Luck")
local ts = Data.Sets.Thicketstalker
eq(#ts.pieces, 4, "Thicketstalker has four pieces")
for _, id in ipairs(ts.pieces) do
	ok(Data.Recipes[id] and Data.Recipes[id].skill == "Hunter" and Data.Items[id].set == "Thicketstalker", id .. " crafted with Hunter")
end
-- Material links into Fletching, Cooking and Alchemy.
local links = {}
for _, rec in pairs(Data.Recipes) do
	for id in pairs(rec.costs) do
		for _, c in ipairs(HU.Creatures) do
			for _, d in ipairs(c.drops) do if d.item == id then links[rec.skill] = true end end
		end
	end
end
for _, skill in ipairs({"Fletching", "Cooking", "Alchemy", "Hunter"}) do ok(links[skill], "hunted materials feed " .. skill) end
for _, id in ipairs({"Skymark", "DownyPelt", "GrouseQuill", "GlintEssence", "ShadowPelt", "StormmaneHide"}) do
	ok(table.find(Data.CollectionItems, id) ~= nil and Data.CollectionScale[id] ~= nil, id .. " has a collection")
end
for _, pet in ipairs({"Puffkin", "Glimmerfly", "Stormkid", "Gustling"}) do
	ok(Data.PetById[pet] ~= nil and Data.Items[pet .. "Pet"] ~= nil, pet .. " pet registered")
end
-- Quests and diaries.
local skillQuests = 0
for _, q in ipairs(Data.Quests) do
	eq(Data.QuestById[q.id], q, q.id .. " indexed")
	for _, o in ipairs(q.objectives) do
		if o.kind == "laps" then skillQuests += 1; ok(AG.CourseById[o.course] ~= nil, q.id .. " laps course") end
		if o.kind == "catches" then skillQuests += 1; ok(HU.CreatureById[o.creature] ~= nil, q.id .. " catches creature") end
	end
end
ok(skillQuests >= 4, "quests use laps and catches")
eq(Data.describeCheck({kind = "laps", course = "QuayRigging", count = 5}), "Run 5 laps of the Quay Rigging Run", "laps check text")
eq(Data.describeCheck({kind = "catches", creature = "PuffcapHopper", count = 3}), "Catch 3 Puffcap Hopper", "catches check text")
eq(Data.describeCheck({kind = "level", skill = "Agility", level = 5}), "Agility level 5", "older checks still described")
local diaryTasks = 0
for _, d in ipairs(Data.Diaries) do
	for _, tier in ipairs(Data.DiaryTiers) do
		local tasks = d.tiers[tier].tasks
		ok(#tasks >= 3 and #tasks <= 5, d.region .. " " .. tier .. " keeps 3-5 tasks")
		for _, t in ipairs(tasks) do if t.kind == "laps" or t.kind == "catches" then diaryTasks += 1 end end
	end
end
ok(diaryTasks >= 6, "diaries include Agility and Hunter tasks")
-- Stats: Speed per Agility level and both outfit set bonuses.
do
	local runner = {xp = {Agility = Data.XP_TABLE[51]}, items = {}, collection = {}, equipment = {}}
	local base = P.computeStats({xp = {}, items = {}, collection = {}, equipment = {}}, 0)
	local s = P.computeStats(runner, 0)
	eq(s.speed, base.speed + 25, "Agility 51 adds 25 Speed")
	for i, id in ipairs(wr.pieces) do
		runner.items[id] = 1
		runner.equipment[Data.Items[id].slot] = id
		s = P.computeStats(runner, 0)
		eq(s.activeSet == "Windrunner", i == 4, "Windrunner bonus only with four pieces (" .. i .. ")")
	end
	local pieces = 0
	for _, id in ipairs(wr.pieces) do pieces += Data.Items[id].stats.surefoot end
	eq(s.surefoot, pieces + wr.bonus.surefoot, "Surefoot = pieces + set bonus")
	local hunter = {xp = {Hunter = Data.XP_TABLE[30]}, items = {}, collection = {}, equipment = {}}
	for _, id in ipairs(ts.pieces) do hunter.items[id] = 1; hunter.equipment[Data.Items[id].slot] = id end
	s = P.computeStats(hunter, 0)
	eq(s.activeSet, "Thicketstalker", "Thicketstalker set active")
	ok(s.trapLuck >= ts.bonus.trapLuck and s.huntingFortune >= ts.bonus.huntingFortune + 29, "Thicketstalker + Hunter levels add Trap Luck and Hunting Fortune")
	hunter.xp.Hunter = 0
	eq(P.computeStats(hunter, 0).activeSet, nil, "outfit needs its Hunter levels")
end
print("PASS: " .. (checks - partA) .. " Agility & Hunter data assertions.")

------------------------------------------------------------------------------
-- Part B: world placement (real instances).
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
-- Lune has no Instance events: give prompts a Destroying signal the server can watch.
local destroyingSignals = {}
roblox.implementProperty("ProximityPrompt", "Destroying", function(prompt)
	if not destroyingSignals[prompt] then destroyingSignals[prompt] = signal() end
	return destroyingSignals[prompt]
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
	UDim2 = roblox.UDim2, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local worldSource = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
luau.load(worldSource, {environment = worldEnv, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
ok(islands ~= nil, "Workspace.Islands built")
local function islandOf(obj)
	local node = obj
	while node and node.Parent ~= islands do node = node.Parent end
	return node
end
local function onIsland(isle, pos, margin)
	local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
	return Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude <= r - (margin or 0) and pos.Y >= c.Y - 1 and pos.Y <= c.Y + 12
end
local function contentOf(obj)
	local node = obj.Parent
	while node and node ~= islands do
		if node:GetAttribute("SkillContent") then return node end
		node = node.Parent
	end
	return nil
end
local prompts = {agility = {}, shortcut = {}, trap = {}, net = {}, skillVendor = {}}
local GATED = {}
for _, r in ipairs(Data.Regions) do if next(r.requires) then GATED[r.id] = true end end
for _, q in islands:GetDescendants() do
	if q:IsA("ProximityPrompt") then
		local action = q:GetAttribute("IsleAction")
		if prompts[action] then
			table.insert(prompts[action], q)
			ok(contentOf(q) ~= nil, action .. " prompt sits inside Agility/Hunter content")
			ok(near(q.HoldDuration, 0.36) and q.MaxActivationDistance == 9 and not q.RequiresLineOfSight, action .. " prompt uses the interact hold")
		end
	end
end
local parts, collidable = 0, 0
for _, model in islands:GetDescendants() do
	if model:IsA("Model") and model:GetAttribute("SkillContent") then
		ok(model:GetAttribute("SkillContent") == "Agility" or model:GetAttribute("SkillContent") == "Hunter", model.Name .. " tagged by skill")
		ok(model.Parent.Parent == islands, model.Name .. " sits directly inside its island model")
		for _, obj in model:GetDescendants() do
			if obj:IsA("BasePart") then
				parts += 1
				ok(obj.Anchored, obj.Name .. " anchored")
				if obj.CanCollide then collidable += 1 end
			end
		end
	end
end
ok(parts >= 300 and parts <= 1000, "skill content stays within its part budget (" .. parts .. ")")
-- Agility courses: every obstacle prompt, in order, landing at the next obstacle.
local byCourse = {}
for _, q in ipairs(prompts.agility) do
	local id = q:GetAttribute("AgilityCourse")
	byCourse[id] = byCourse[id] or {}
	ok(byCourse[id][q:GetAttribute("AgilityIndex")] == nil, id .. " obstacle index unique")
	byCourse[id][q:GetAttribute("AgilityIndex")] = q
end
local obstacleTotal = 0
for _, course in ipairs(AG.Courses) do
	local list = byCourse[course.id]
	ok(list ~= nil, course.id .. " built in the world")
	local n = #course.obstacles
	obstacleTotal += n
	local isle
	for i, o in ipairs(course.obstacles) do
		local q = list[i]
		ok(q ~= nil, course.id .. " obstacle " .. i .. " has a prompt")
		eq(q:GetAttribute("IsleItem"), course.id .. ":" .. i, course.id .. " obstacle " .. i .. " IsleItem")
		eq(q:GetAttribute("AgilityKind"), o.kind, course.id .. " obstacle " .. i .. " kind")
		eq(q.ActionText, AG.Kinds[o.kind].verb, course.id .. " obstacle " .. i .. " verb")
		ok(has(q.ObjectText, o.name) and has(q.ObjectText, "Lv " .. course.level), course.id .. " obstacle " .. i .. " label")
		eq(q:GetAttribute("IsleRegion"), if GATED[course.region] then course.region else nil, course.id .. " obstacle " .. i .. " region gate")
		eq(typeof(q:GetAttribute("AgilityEnd")), "Vector3", course.id .. " obstacle " .. i .. " landing")
		eq(typeof(q:GetAttribute("AgilityFall")), "Vector3", course.id .. " obstacle " .. i .. " fall landing")
		isle = isle or islandOf(q)
		eq(islandOf(q), isle, course.id .. " obstacles share one island")
		eq(isle:GetAttribute("Region"), course.region, course.id .. " island region matches data")
		-- Chain: obstacle i lands where obstacle i+1 starts (the last returns to the start).
		local nextHost = list[i % n + 1].Parent.CFrame.Position
		local landing = q:GetAttribute("AgilityEnd")
		ok((landing - nextHost).Magnitude <= 10, course.id .. " obstacle " .. i .. " lands at the next obstacle")
		ok((landing - nextHost).Magnitude <= q.MaxActivationDistance, course.id .. " landing within prompt reach of the next obstacle")
		ok((q.Parent.CFrame.Position - landing).Magnitude >= 8, course.id .. " obstacle " .. i .. " actually travels")
		ok(onIsland(isle, q:GetAttribute("AgilityFall"), 2), course.id .. " falls land on the island")
	end
	ok(onIsland(isle, list[1].Parent.CFrame.Position, 2), course.id .. " starts on the island")
	local floating = 0
	for i = 2, n do if not onIsland(isle, list[i].Parent.CFrame.Position, -3) then floating += 1 end end
	eq(floating, n - 1, course.id .. " perches float beyond the island rim")
	local model = contentOf(list[1])
	local guards, perches = 0, 0
	for _, obj in model:GetDescendants() do
		if obj.Name == "Perch guard" then guards += 1; ok(obj.CanCollide and obj.Transparency == 1, "perch guard invisible and solid") end
		if obj.Name == "Agility perch" then perches += 1; ok(obj.CanCollide and obj:GetAttribute("Shape") == "AgilityPerch", "perch is a solid mesh slot") end
	end
	eq(perches, n - 1, course.id .. " floating perches")
	eq(guards, 4 * (n - 1), course.id .. " every perch is guarded")
	ok(isle:FindFirstChild("Anchor_Waypoint_Agility_" .. course.id) ~= nil, course.id .. " waypoint anchor")
	ok(model:FindFirstChild("Sign " .. course.name) ~= nil, course.id .. " sign")
end
eq(#prompts.agility, obstacleTotal, "one prompt per obstacle")
-- Shortcuts: two ends, each landing at the other.
local ends = {}
for _, q in ipairs(prompts.shortcut) do
	local id, tag = string.match(q:GetAttribute("IsleItem"), "^(%w+):([AB])$")
	ok(id and AG.ShortcutById[id], "shortcut prompt names a shortcut")
	ends[id] = ends[id] or {}
	ok(ends[id][tag] == nil, id .. " end " .. tag .. " unique")
	ends[id][tag] = q
end
for _, sc in ipairs(AG.Shortcuts) do
	local e = ends[sc.id]
	ok(e and e.A and e.B, sc.id .. " has both ends")
	for _, pair in ipairs({{e.A, e.B}, {e.B, e.A}}) do
		local q, other = pair[1], pair[2]
		local to = q:GetAttribute("ShortcutTo")
		eq(typeof(to), "Vector3", sc.id .. " landing")
		ok((to - other.Parent.CFrame.Position).Magnitude <= 9, sc.id .. " lands at the far post")
		ok(onIsland(islandOf(other), to, 2), sc.id .. " lands on the far island")
		ok(islandOf(q) ~= islandOf(other), sc.id .. " joins two islands")
		eq(q:GetAttribute("IsleRegion"), if sc.region and GATED[sc.region] then sc.region else nil, sc.id .. " region gate")
		local dest = islandOf(other):GetAttribute("Region")
		eq(q:GetAttribute("ShortcutRegion"), if dest and GATED[dest] then dest else "", sc.id .. " end gates on its own destination region")
		eq(q:GetAttribute("AgilityKind"), sc.kind, sc.id .. " animation kind")
		ok(has(q.ObjectText, "Agility " .. sc.level), sc.id .. " shows its level")
	end
	ok(islandOf(e.B):GetAttribute("Region") == sc.region or sc.region == nil, sc.id .. " B end is in the destination region")
end
eq(#prompts.shortcut, 2 * #AG.Shortcuts, "two prompts per shortcut")
-- Hunting grounds.
local spots, spotIds = {}, {}
for _, q in ipairs(prompts.trap) do table.insert(spots, q) end
for _, q in ipairs(prompts.net) do table.insert(spots, q) end
local perCreature = {}
for _, q in ipairs(spots) do
	local c = HU.CreatureById[q:GetAttribute("IsleItem")]
	ok(c ~= nil, "hunting prompt names a creature")
	eq(q:GetAttribute("IsleAction"), if HU.Methods[c.method].trap then "trap" else "net", c.id .. " prompt action matches its method")
	eq(q:GetAttribute("HunterMethod"), c.method, c.id .. " method attribute")
	local spot = q:GetAttribute("HunterSpot")
	ok(spotIds[spot] == nil and q.Parent:GetAttribute("HunterSpot") == spot, c.id .. " spot id unique")
	spotIds[spot] = true
	eq(q.Parent:GetAttribute("TrapState"), "", c.id .. " spot starts empty")
	eq(q:GetAttribute("IsleRegion"), if GATED[c.region] then c.region else nil, c.id .. " region gate")
	eq(islandOf(q):GetAttribute("Region"), c.region, c.id .. " ground in its region")
	ok(onIsland(islandOf(q), q.Parent.CFrame.Position, 4), c.id .. " spot on open island ground")
	ok(not q.Parent.CanCollide, c.id .. " spot does not block movement")
	perCreature[c.id] = (perCreature[c.id] or 0) + 1
end
for _, c in ipairs(HU.Creatures) do
	eq(perCreature[c.id], if HU.Methods[c.method].trap then 4 else 3, c.id .. " spot count")
	local found = false
	for _, isle in islands:GetChildren() do if isle:FindFirstChild("Anchor_Waypoint_Hunting_" .. c.id) then found = true end end
	ok(found, c.id .. " hunting ground waypoint")
end
-- Vendors.
eq(#prompts.skillVendor, 2, "two skill vendors")
local vendorSkills = {}
for _, q in ipairs(prompts.skillVendor) do vendorSkills[q:GetAttribute("IsleItem")] = islandOf(q) end
eq(vendorSkills.Agility and vendorSkills.Agility.Name, "Compass Quay", "Skymark Exchange in the hub")
eq(vendorSkills.Hunter and vendorSkills.Hunter:GetAttribute("Region"), "Meadow", "Trackers' Lodge in Meadow Reach")
for _, name in ipairs({"Anchor_NPC_Skymaster", "Anchor_NPC_Trapper", "Anchor_Waypoint_SkymarkExchange", "Anchor_Waypoint_TrackersLodge"}) do
	ok(world:FindFirstChild(name, true) ~= nil, name .. " exists")
end
-- New solid geometry never intersects existing solid geometry (floors excluded).
do
	local FLOOR = {Meadow = true, ["Floating foundation"] = true, ["Mineral stratum"] = true, ["Lower basalt"] = true, ["Edge guard"] = true, ["Grassy hillock"] = true}
	local function box(obj)
		local cf, s = obj.CFrame, obj.Size
		local function ext(axis) return math.abs(cf.RightVector[axis]) * s.X / 2 + math.abs(cf.UpVector[axis]) * s.Y / 2 + math.abs(cf.LookVector[axis]) * s.Z / 2 end
		local p = cf.Position
		return {p.X - ext("X"), p.X + ext("X"), p.Y - ext("Y"), p.Y + ext("Y"), p.Z - ext("Z"), p.Z + ext("Z")}
	end
	local mine, others = {}, {}
	for _, obj in islands:GetDescendants() do
		if obj:IsA("BasePart") and obj.CanCollide and not FLOOR[obj.Name] and not string.find(obj.Name, "^Anchor_") then
			if contentOf(obj) then table.insert(mine, {obj, box(obj)}) else table.insert(others, {obj, box(obj)}) end
		end
	end
	local hits = 0
	for _, a in mine do
		for _, b in others do
			local A, B = a[2], b[2]
			if A[1] < B[2] - .3 and B[1] < A[2] - .3 and A[3] < B[4] - .3 and B[3] < A[4] - .3 and A[5] < B[6] - .3 and B[5] < A[6] - .3 then
				hits += 1
				print("overlap: " .. a[1]:GetFullName() .. " / " .. b[1]:GetFullName())
			end
		end
	end
	eq(hits, 0, "solid skill geometry clears existing solid geometry")
end
print("PASS: " .. (checks - partB) .. " Agility & Hunter world assertions (" .. parts .. " parts, " .. collidable .. " solid, "
	.. #prompts.agility .. " obstacles, " .. #prompts.shortcut .. " shortcut ends, " .. #spots .. " hunting spots).")

------------------------------------------------------------------------------
-- Part C: server behaviour against the world prompts.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local clock, utc = 10, 1500000000
local function advance(seconds) clock += seconds; utc += seconds end
local data = {}
local db = {}
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
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
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "skills-test" end},
	RunService = {IsStudio = function() return false end},
}
local coroutines = {}
local serverObjects = {}
local serverWorkspace = {GetAttribute = function(self, key) return rawget(self, key) end}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = serverWorkspace, Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function()
		local o = {Event = signal(), FireClient = function(_, player, state) player.last = state end}
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
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
-- Capture each coroutine's requested wait so the sweep loop can be identified.
local yieldOf = {}
do
	local baseWait = env.task.wait
	env.task.wait = function(t)
		yieldOf[coroutine.running()] = t
		return baseWait(t)
	end
end
-- Lune does not derive BasePart.Position from CFrame (as the engine does); world parts are real instances here.
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
-- Instance-keyed state must be strong (Roblox can collect Instance wrappers held
-- only by weak keys): the only weak tables left are keyed by profile tables.
for line in string.gmatch(serverSource, "[^\n]+") do
	if string.find(line, "__mode", 1, true) then
		ok(string.match(line, "^local notes=") ~= nil or string.match(line, "^local CombatStyles=") ~= nil,
			"no weak Instance-keyed table: " .. line)
	end
end
local sweeper
for _, co in ipairs(coroutines) do if yieldOf[co] == HU.TICK then sweeper = co end end
ok(sweeper ~= nil, "trap sweep loop runs every Hunter tick")
local loopCount = #coroutines
-- Finish every movement coroutine started since the server loaded.
local function finishMoves()
	local i = loopCount + 1
	while i <= #coroutines do
		local co = coroutines[i]
		while coroutine.status(co) == "suspended" do assert(coroutine.resume(co)) end
		table.remove(coroutines, i)
	end
end
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.zero, Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) services.Players.PlayerRemoving:Fire(p) end
local function rejoin(p, mutate)
	leave(p)
	if mutate then mutate(data["p" .. p.UserId].profile) end
	return player(p.UserId)
end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	mutate(data["p" .. id].profile)
	return player(id)
end
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction RemoteFunction found")
local function cmd(p, verb, item)
	advance(1)
	return remote.OnServerInvoke(p, verb, item)
end
-- Trigger a world prompt; stand=false keeps the player where the server left them.
local function use(p, q, stand)
	advance(1)
	if stand ~= false then p.root.Position = q.Parent.CFrame.Position end
	p.last = nil
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
local X = Data.XP_TABLE
local quay = AG.CourseById.QuayRigging
local Q = byCourse.QuayRigging

-- A full lap: order, busy, skip, movement, XP, lap bonus, Skymark.
local runner = player(5001)
local s0 = cmd(runner, "state")
ok(type(s0.agilityHunter) == "table" and s0.agilityHunter.agility and s0.agilityHunter.hunter, "snapshot carries agilityHunter")
eq(s0.xp.Agility, 0, "fresh Agility XP")
eq(s0.xp.Hunter, 0, "fresh Hunter XP")
eq(s0.agilityHunter.hunter.maxTraps, 1, "snapshot max traps")
local remoteTry = cmd(runner, "agility", "QuayRigging:1")
eq(remoteTry.xp.Agility, 0, "obstacles cannot be run through the remote")
eq(cmd(runner, "shortcut", "MosswakeRopeBridge:A").xp.Agility, 0, "shortcuts cannot be used through the remote")
local st = use(runner, Q[1])
eq(st.xp.Agility, quay.obstacles[1].xp, "first obstacle pays XP")
ok(has(st.message, quay.obstacles[1].name), "obstacle named in the message")
ok(has(runner.attrs.AgilityMove, "climb:"), "AgilityMove names the animation")
eq(runner.attrs.AgilityMoveDuration, quay.obstacles[1].duration, "AgilityMoveDuration published")
ok((runner.attrs.AgilityMoveTo - Q[1]:GetAttribute("AgilityEnd")).Magnitude < 1e-3, "AgilityMoveTo published")
eq(runner.attrs.AgilityRun, "QuayRigging:2:" .. #quay.obstacles, "AgilityRun shows the next obstacle")
ok(runner.attrs.AgilityRunExpires > utc, "AgilityRunExpires in the future")
eq(runner.root.Anchored, true, "root anchored while the server moves it")
local busy = use(runner, Q[2])
eq(busy.message, "Still moving…", "no obstacle while moving")
eq(busy.xp.Agility, quay.obstacles[1].xp, "busy attempt pays nothing")
advance(3)
local skip = use(runner, Q[3])
ok(has(skip.message, "in order") and has(skip.message, quay.obstacles[2].name), "skipping an obstacle is refused and names the next")
eq(skip.xp.Agility, quay.obstacles[1].xp, "skip pays nothing")
finishMoves()
ok((runner.root.Position - Q[1]:GetAttribute("AgilityEnd")).Magnitude < 1e-3, "server moved the runner to the landing")
eq(runner.root.Anchored, false, "root released after the move")
eq(runner.attrs.AgilityMove, "", "AgilityMove cleared after the move")
local xp = quay.obstacles[1].xp
for i = 2, #quay.obstacles do
	if i == #quay.obstacles then queue(0.01) end -- Skymark roll on the lap
	local s = use(runner, Q[i], false)
	ok(s ~= nil, "obstacle " .. i .. " reachable from the previous landing")
	xp += quay.obstacles[i].xp
	if i == #quay.obstacles then xp += quay.lapXp end
	eq(s.xp.Agility, xp, "obstacle " .. i .. " XP in order")
	finishMoves()
	advance(3)
	if i == #quay.obstacles then
		ok(has(s.message, "Lap 1") and has(s.message, "Skymark"), "lap message with Skymark")
		eq(s.items.Skymark, 1, "Skymark granted as an item")
		eq(s.collection.Skymark, 1, "Skymark collection counted")
		eq(s.agilityHunter.agility.laps.QuayRigging, 1, "lap counted")
		ok(s.agilityHunter.agility.best.QuayRigging > 0, "best lap time recorded")
		eq(xp, AG.lapTotal(quay), "one lap pays lapTotal")
	end
end
eq(runner.attrs.AgilityRun, "", "run cleared after the lap")
-- A second lap without a Skymark roll.
for i = 1, #quay.obstacles do use(runner, Q[i], false); finishMoves(); advance(3) end
local s2 = cmd(runner, "state")
eq(s2.agilityHunter.agility.laps.QuayRigging, 2, "second lap counted")
eq(s2.items.Skymark, 1, "failed Skymark roll pays none")
eq(s2.xp.Agility, 2 * AG.lapTotal(quay), "two laps of XP")
-- Position: an obstacle out of reach does nothing at all.
runner.root.Position = Vector3.new(0, 500, 0)
eq(use(runner, Q[2], false), nil, "out-of-reach obstacle ignored")
-- Timing: too long between obstacles breaks the lap.
runner = rejoin(runner)
use(runner, Q[1]); finishMoves()
advance(AG.STEP_WINDOW + 5)
local slow = use(runner, Q[2], false)
ok(has(slow.message, "Too slow"), "late obstacle refused")
eq(slow.xp.Agility, 2 * AG.lapTotal(quay) + quay.obstacles[1].xp, "late obstacle pays nothing")
eq(runner.attrs.AgilityRun, "", "broken lap cleared")
ok(has(use(runner, Q[3]).message, "start at the"), "after a broken lap you start again")
-- Failure: risky obstacle, low level, low roll.
runner = rejoin(runner, function(prof) prof.xp.Agility = 0 end)
use(runner, Q[1], true); finishMoves(); advance(3)
use(runner, Q[2], false); finishMoves(); advance(3)
local risky = quay.obstacles[3]
ok(risky.risk > 0, "obstacle 3 is risky")
local before = runner.humanoid.Health
queue(0.0)
local fall = use(runner, Q[3], false)
ok(has(fall.message, "fall"), "failure message")
ok(runner.humanoid.Health < before and runner.humanoid.Health >= 1, "failure deals non-lethal damage")
ok(has(runner.attrs.AgilityMove, "fall:"), "fall animation published")
eq(fall.xp.Agility, quay.obstacles[1].xp + quay.obstacles[2].xp, "failed obstacle pays nothing")
finishMoves()
ok((runner.root.Position - Q[3]:GetAttribute("AgilityFall")).Magnitude < 1e-3, "fall drops the runner at the course start")
advance(1)
ok(has(use(runner, Q[4], true).message, "start at the"), "failure resets the lap")
-- High level: the same roll cannot fail.
runner = rejoin(runner, function(prof) prof.xp.Agility = X[30] end)
use(runner, Q[1], true); finishMoves(); advance(3)
use(runner, Q[2], false); finishMoves(); advance(3)
queue(0.0)
local safe = use(runner, Q[3], false)
ok(not has(safe.message, "fall"), "no failures 20+ levels above the course")
eq(#rolls, 1, "no failure roll is even made 20+ levels above")
table.clear(rolls)
finishMoves()
-- Level and region gates.
local novice = player(5014)
local gated = use(novice, byCourse.BrassfallScaffold[1])
ok(has(gated.message, "requires Agility 20"), "course level gate")
eq(gated.xp.Agility, 0, "level gate pays nothing")
leave(novice)
local regionGate = use(runner, byCourse.WindpineCanopy[1])
ok(has(regionGate.message, "Windpine Grove requires"), "gated region course refused")
eq(regionGate.xp.Agility, X[30] + quay.obstacles[1].xp + quay.obstacles[2].xp + quay.obstacles[3].xp, "gates pay nothing")
-- Speed per level.
local slowRunner = player(5002)
local fastRunner = seeded(5003, function(prof) prof.xp.Agility = X[51] end)
eq(cmd(fastRunner, "state").depth.stats.speed - cmd(slowRunner, "state").depth.stats.speed, 25, "Agility 51 adds 25 Speed")
eq(fastRunner.humanoid.WalkSpeed > slowRunner.humanoid.WalkSpeed, true, "Speed raises walk speed")
leave(slowRunner); leave(fastRunner)

-- Persistence and migration.
leave(runner)
local saved = data.p5001.profile
eq(saved.agility.laps.QuayRigging, 2, "laps persist")
ok(saved.agility.best.QuayRigging > 0, "best lap persists")
eq(saved.items.Skymark, 1, "Skymarks persist as items")
eq(saved.traps, nil, "no trap state in the save")
local migrated = seeded(5004, function(prof)
	prof.agility = {laps = {Bogus = 5, QuayRigging = "x", TempestStormrun = -3, MosswakeHedgerow = 4.7}, best = {QuayRigging = 1e9, MosswakeHedgerow = 12.5}}
	prof.hunterLog = {PuffcapHopper = 3.7, Nope = 1, SunwingMoth = "bad"}
end)
local mig = cmd(migrated, "state").agilityHunter
eq(mig.agility.laps.Bogus, nil, "unknown course dropped")
eq(mig.agility.laps.QuayRigging, nil, "non-numeric laps dropped")
eq(mig.agility.laps.TempestStormrun, nil, "negative laps dropped")
eq(mig.agility.laps.MosswakeHedgerow, 4, "fractional laps floored")
eq(mig.agility.best.QuayRigging, nil, "absurd lap time dropped")
eq(mig.agility.best.MosswakeHedgerow, 12.5, "valid lap time kept")
eq(mig.hunter.log.PuffcapHopper, 3, "hunter log floored")
eq(mig.hunter.log.Nope, nil, "unknown creature dropped")
eq(mig.hunter.log.SunwingMoth, nil, "bad log entry dropped")
local legacy = seeded(5005, function(prof) prof.agility = nil; prof.hunterLog = nil; prof.xp.Agility = nil; prof.xp.Hunter = nil end)
local leg = cmd(legacy, "state")
eq(leg.xp.Agility, 0, "older saves gain Agility XP")
eq(leg.xp.Hunter, 0, "older saves gain Hunter XP")
ok(next(leg.agilityHunter.agility.laps) == nil and next(leg.agilityHunter.hunter.log) == nil, "older saves gain empty records")
leave(migrated); leave(legacy)

-- Quests with laps and catches.
local quester = seeded(5006, function(prof)
	prof.questCompleted = 3
	prof.xp.Agility = X[5]
	prof.agility = {laps = {QuayRigging = 4}, best = {}}
end)
local early = cmd(quester, "quest", "FirstFootfalls")
eq(early.items.Skymark, nil, "four laps do not finish First Footfalls")
quester = rejoin(quester, function(prof) prof.agility.laps.QuayRigging = 5 end)
local done = cmd(quester, "quest", "FirstFootfalls")
eq(done.items.Skymark, 3, "First Footfalls pays Skymarks")
quester = rejoin(quester, function(prof)
	prof.hunterLog = {PuffcapHopper = 10}
	prof.items.DownyPelt = 5
	prof.xp.Hunter = X[10]
end)
local trapper = cmd(quester, "quest", "TrappersApprentice")
eq(trapper.items.BirdSnare, 1, "Trapper's Apprentice pays a Bird Snare")
eq(trapper.items.DownyPelt, 0, "pelts handed in")
leave(quester)

-- Shortcuts.
local A = ends.MosswakeRopeBridge.A
local scout = player(5007)
ok(has(use(scout, A).message, "Windpine Grove requires"), "shortcut destination region gate")
scout = rejoin(scout, function(prof) prof.xp.Woodcutting = X[10] end)
ok(has(use(scout, A).message, "requires Agility 20"), "shortcut level gate")
scout = rejoin(scout, function(prof) prof.xp.Agility = X[20] end)
local went = use(scout, A)
eq(went.xp.Agility, X[20] + AG.ShortcutById.MosswakeRopeBridge.xp, "shortcut pays XP")
ok(has(scout.attrs.AgilityMove, "balance:"), "shortcut animation published")
eq(use(scout, A).message, "Still moving…", "no second shortcut mid-crossing")
finishMoves()
ok((scout.root.Position - A:GetAttribute("ShortcutTo")).Magnitude < 1e-3, "shortcut lands at the far end")
advance(8)
local back = use(scout, ends.MosswakeRopeBridge.B, false)
ok(back ~= nil and has(back.message, "Rope Bridge"), "return trip from the landing")
finishMoves()
ok((scout.root.Position - ends.MosswakeRopeBridge.B:GetAttribute("ShortcutTo")).Magnitude < 1e-3, "return lands at the start")
ok(has(use(scout, ends.TempestGaleLine.A).message, "Tempest Spire requires"), "high shortcut gated by its destination")
-- Reverse trip: Tempest -> Skyreach needs the Skyreach charter, not Tempest access.
eq(ends.TempestGaleLine.B:GetAttribute("ShortcutRegion"), "Skyreach", "Tempest end leads to Skyreach")
scout = rejoin(scout, function(prof) prof.xp.Agility = X[70]; prof.xp.Combat = X[40]; prof.questCompleted = 0 end)
local reverse = use(scout, ends.TempestGaleLine.B)
ok(has(reverse.message, "Skyreach charter"), "Tempest -> Skyreach refused without the Skyreach charter")
eq(reverse.xp.Agility, X[70], "refused reverse trip pays nothing")
ok(has(use(scout, ends.TempestGaleLine.A).message, "Gale Line"), "Skyreach -> Tempest only needs Tempest access")
leave(scout)

-- Skymark Exchange and the Windrunner outfit.
local shopper = seeded(5008, function(prof) prof.items.Skymark = 100; prof.xp.Agility = X[5] end)
ok(has(cmd(shopper, "skillBuy", "Agility:WindrunnerHood").message, "Visit the Skymark Exchange"), "buying needs a vendor visit")
local agVendor, huVendor
for _, q in ipairs(prompts.skillVendor) do if q:GetAttribute("IsleItem") == "Agility" then agVendor = q else huVendor = q end end
local visit = use(shopper, agVendor)
ok(has(visit.message, "Skymark Exchange"), "vendor greets")
eq(shopper.attrs.SkillVendor, "Agility", "SkillVendor attribute")
eq(shopper.attrs.IsleStation, "SkymarkExchange", "vendor opens the atlas page")
ok(shopper.attrs.SkillVendorUntil > utc, "vendor window open")
local spent = 0
for _, id in ipairs(wr.pieces) do
	local bought = cmd(shopper, "skillBuy", "Agility:" .. id)
	local cost
	for _, e in ipairs(AG.Shop) do if e.item == id then cost = e.cost.Skymark end end
	spent += cost
	eq(bought.items[id], 1, "bought " .. id)
	eq(bought.items.Skymark, 100 - spent, id .. " costs Skymarks")
end
ok(has(cmd(shopper, "skillBuy", "Agility:WindrunnerHood").message, "already own"), "outfit pieces are unique")
ok(has(cmd(shopper, "skillBuy", "Agility:Ore").message, "does not stock"), "vendor stock enforced")
ok(has(cmd(shopper, "skillBuy", "Hunter:SnareKit").message, "Visit the Trackers' Lodge"), "vendors are separate")
ok(has(cmd(shopper, "skillBuy", "nonsense").message, "Choose an item"), "malformed purchase refused")
for _, id in ipairs(wr.pieces) do cmd(shopper, "equip", id) end
local dressed = cmd(shopper, "state")
eq(dressed.depth.stats.activeSet, "Windrunner", "Windrunner set bonus active")
ok(dressed.depth.stats.surefoot >= wr.bonus.surefoot, "Surefoot from the outfit")
shopper.attrs.SkillVendorUntil = utc - 1
ok(has(cmd(shopper, "skillBuy", "Agility:GaleDraught").message, "Visit"), "vendor window expires")
local broke = seeded(5009, function(prof) prof.items.Skymark = 2 end)
use(broke, agVendor)
local poor = cmd(broke, "skillBuy", "Agility:WindrunnerHood")
ok(has(poor.message, "costs"), "too few Skymarks refused")
eq(poor.items.Skymark, 2, "refusal spends nothing")
eq(cmd(broke, "skillBuy", "Agility:SkymarkSatchel").items.SkymarkSatchel, 1, "consumable stock is repeatable")
leave(shopper); leave(broke)

-- Hunter: kits, trap limits, ticking, collection, dismantling, collapse.
local hop = {}
for _, q in ipairs(prompts.trap) do if q:GetAttribute("IsleItem") == "PuffcapHopper" then table.insert(hop, q) end end
table.sort(hop, function(a, b) return a:GetAttribute("HunterSpot") < b:GetAttribute("HunterSpot") end)
local hunter = seeded(5010, function(prof) prof.coins = 1000 end)
ok(has(use(hunter, hop[1]).message, "Snare Kit"), "trapping needs a kit")
eq(cmd(hunter, "trap", "PuffcapHopper").xp.Hunter, 0, "traps cannot be set through the remote")
use(hunter, huVendor)
local kit = cmd(hunter, "skillBuy", "Hunter:SnareKit")
eq(kit.items.SnareKit, 1, "bought a Snare Kit")
eq(kit.coins, 950, "Snare Kit costs coins")
local set = use(hunter, hop[1])
ok(has(set.message, "Snare set"), "snare set")
eq(hop[1].Parent:GetAttribute("TrapState"), "set", "TrapState published on the spot")
eq(hop[1].Parent:GetAttribute("TrapOwner"), 5010, "TrapOwner published")
eq(hunter.attrs.HunterTraps, "1/1", "HunterTraps attribute")
eq(set.agilityHunter.hunter.traps[1].state, "set", "snapshot lists the trap")
ok(has(use(hunter, hop[2]).message, "tend 1 trap"), "trap limit at Hunter 1")
local rival = seeded(5011, function(prof) prof.items.SnareKit = 1 end)
ok(has(use(rival, hop[1]).message, "Another hunter"), "spots hold one trap")
local status = use(hunter, hop[1])
ok(has(status.message, "is set"), "using a set trap reports progress")
local picked = use(hunter, hop[1])
ok(has(picked.message, "pick up"), "second use within the window dismantles")
eq(hop[1].Parent:GetAttribute("TrapState"), "", "dismantled spot cleared")
eq(hunter.attrs.HunterTraps, "0/1", "trap returned")
-- Lazy roll on use: two misses then a catch.
use(hunter, hop[1])
advance(HU.TICK * 3 - 0.5) -- three ticks elapse by the next use
queue(0.9, 0.9, 0.01)
local caught = use(hunter, hop[1])
ok(has(caught.message, "Caught a Puffcap Hopper"), "trap catch collected")
eq(caught.xp.Hunter, HU.CreatureById.PuffcapHopper.xp, "catch XP")
eq(caught.items.DownyPelt, 1, "primary drop")
eq(caught.agilityHunter.hunter.log.PuffcapHopper, 1, "hunter log counts the catch")
eq(hop[1].Parent:GetAttribute("TrapState"), "", "collected spot cleared")
-- The sweep loop springs traps without the player.
use(hunter, hop[1])
queue(0.01)
advance(HU.TICK)
assert(coroutine.resume(sweeper, HU.TICK)) -- task.wait returns the elapsed time
eq(hop[1].Parent:GetAttribute("TrapState"), "caught", "sweep marks a caught trap")
eq(hunter.attrs.HunterTrapsCaught, 1, "HunterTrapsCaught attribute")
ok(has(use(rival, hop[1]).message, "Another hunter"), "a rival cannot collect your catch")
ok(has(use(hunter, hop[1]).message, "Caught"), "owner collects the swept catch")
-- Collapse after MAX_TICKS misses.
hunter = rejoin(hunter)
use(hunter, hop[2])
advance(HU.TICK * HU.MAX_TICKS)
local empty = use(hunter, hop[2])
ok(has(empty.message, "collapsed"), "unsprung trap collapses")
eq(empty.agilityHunter.hunter.log.PuffcapHopper, 2, "collapse catches nothing")
-- Level gate, more traps at Hunter 20, leaving frees spots.
local ibex
for _, q in ipairs(prompts.trap) do if q:GetAttribute("IsleItem") == "StormmaneIbex" then ibex = q end end
hunter = rejoin(hunter, function(prof) prof.xp.Combat = X[40] end)
ok(has(use(hunter, ibex).message, "requires Hunter 80"), "high creature gated by Hunter level")
hunter = rejoin(hunter, function(prof) prof.xp.Hunter = X[20] end)
ok(has(use(hunter, hop[1]).message, "Traps 1/2"), "first of two traps")
ok(has(use(hunter, hop[2]).message, "Traps 2/2"), "second trap at Hunter 20")
ok(has(use(hunter, hop[3]).message, "tend 2 traps"), "third trap refused")
leave(hunter)
eq(hop[1].Parent:GetAttribute("TrapState"), "", "leaving clears your traps")
rival = rejoin(rival) -- the longer trap collapse outlasts the test double's journal lease
ok(has(use(rival, hop[1]).message, "Snare set"), "freed spot reusable")
leave(rival)
-- Trap state is held strongly and cleared when the prompt itself goes away.
local destroyer = seeded(5015, function(prof) prof.items.SnareKit = 1 end)
ok(has(use(destroyer, hop[4]).message, "Snare set"), "trap set before its prompt is destroyed")
eq(destroyer.attrs.HunterTraps, "1/1", "trap counted")
ok(destroyingSignals[hop[4]] ~= nil, "the server watches the trap prompt")
destroyingSignals[hop[4]]:Fire()
eq(hop[4].Parent:GetAttribute("TrapState"), "", "a destroyed prompt drops its trap")
eq(destroyer.attrs.HunterTraps, "0/1", "and frees the owner's trap slot")
ok(has(use(destroyer, hop[4]).message, "Snare set"), "a re-registered prompt starts clean")
leave(destroyer)
-- Nets and the log milestone.
local moth
for _, q in ipairs(prompts.net) do if q:GetAttribute("IsleItem") == "SunwingMoth" then moth = q end end
local netter = player(5012)
ok(has(use(netter, moth).message, "requires Hunter 9"), "net level gate")
netter = rejoin(netter, function(prof) prof.xp.Hunter = X[9] end)
ok(has(use(netter, moth).message, "Sky Net"), "net needs a kit")
netter = rejoin(netter, function(prof) prof.items.SkyNet = 1; prof.hunterLog = {SunwingMoth = 9} end)
queue(0.01)
local netted = use(netter, moth)
ok(has(netted.message, "Caught a Sunwing Moth") and has(netted.message, "milestone"), "net catch reaches a log milestone")
ok((netted.items.SunwingDust or 0) >= 1, "net drop")
eq(netted.depth.stats.trapLuck, HU.LogBonus.trapLuck, "log milestone grants Trap Luck")
ok(has(use(netter, moth).message, "scattered"), "swarm cooldown")
local poacher = seeded(5014, function(prof) prof.xp.Hunter = X[9]; prof.items.SkyNet = 1 end)
ok(has(use(poacher, moth).message, "scattered"), "a catch scatters the swarm for every player at the spot")
leave(poacher)
advance(HU.CreatureById.SunwingMoth.respawn)
queue(0.99)
local miss = use(netter, moth)
ok(has(miss.message, "slips"), "net miss")
eq(miss.agilityHunter.hunter.log.SunwingMoth, 10, "miss counts nothing")
eq(cmd(netter, "net", "SunwingMoth").agilityHunter.hunter.log.SunwingMoth, 10, "nets cannot be swung through the remote")
leave(netter)
-- Material links: quills to plumes, haunch to a meal.
local cook = seeded(5013, function(prof)
	prof.xp.Fletching = X[10]; prof.xp.Cooking = X[5]
	prof.items.GrouseQuill = 1; prof.items.HopperHaunch = 1; prof.items.Herb = 1
end)
eq(cmd(cook, "craft", "QuillPlumes").items.DriftPlume, 10, "Grouse Quill fletches arrow plumes")
eq(cmd(cook, "craft", "RoastHopper").items.RoastHopper, 1, "hopper haunch cooks a meal")
leave(cook)
print("PASS: " .. (checks - partC) .. " Agility & Hunter server assertions.")
print("Agility & Hunter QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-skills.luau")
