-- Commissions & Logs: commissions, Glimmerdust, Forgeheart, Collection Log and Museum.
-- Part A checks shared/GameData.lua (Data.CommissionsLogs): the task pool,
-- deterministic daily draws and their level/region gates, milestones, the
-- Forgeheart economy (rising costs, diminishing gains, discount, fortune
-- budget), gem rolls, Collection Log auto-generation (every unique in data
-- appears exactly once, found by an independent scan) and Museum categories.
-- Part B extends the max single-click yield rule (verify-progression) with
-- Forgeheart + commission + museum perks: still <= 2.5x the pre-mastery max.
-- Part C builds world.server.lua: the Commission Board and Aether Museum.
-- Part D runs server.server.lua: generation, persistence, UTC reset with
-- auto-claim, claim-once, gates, kill/gather/catch progress, Glimmerdust and
-- Forgeheart, gem rolls and regrowth, retroactive log credit, log rewards and
-- titles, museum donation rules (no duplication) and migration bounds.
-- Part E renders Journal › Commissions / Collection Log / Museum.
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
local CL = Data.CommissionsLogs
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

------------------------------------------------------------------------------
-- Part A: data and rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(CL) == "table", "Data.CommissionsLogs exists")
eq(CL.SLOTS, 4, "four daily slots")
ok(#CL.Tasks >= 38 and #CL.Tasks <= 45, "about forty commissions (" .. #CL.Tasks .. ")")
local kinds, groups = {}, {}
for _, t in ipairs(CL.Tasks) do
	eq(CL.TaskById[t.id], t, t.id .. " indexed")
	kinds[t.kind] = (kinds[t.kind] or 0) + 1
	groups[t.group] = (groups[t.group] or 0) + 1
	ok(type(t.name) == "string" and #t.name > 3, t.id .. " named")
	ok(t.amount >= 1 and t.amount <= 60, t.id .. " amount sane")
	ok(Data.Skills[t.skill] ~= nil, t.id .. " rewards a real skill")
	ok(t.xp > 0 and t.coins > 0 and t.dust > 0 and t.dust <= 120, t.id .. " pays XP, coins and dust")
	for skill, lvl in pairs(t.levels) do ok(Data.Skills[skill] ~= nil and lvl >= 1 and lvl <= 99, t.id .. " gate " .. skill) end
	if t.region then ok(Data.RegionById[t.region] ~= nil, t.id .. " region exists") end
	if t.kind == "gather" then ok(Data.ResourceSkill[t.target] ~= nil, t.id .. " gathers a resource")
	elseif t.kind == "kill" then ok(rawget(Data.Monsters, t.target) ~= nil, t.id .. " targets an iterated monster")
	elseif t.kind == "catch" then ok(Data.Hunter.CreatureById[t.target] ~= nil, t.id .. " targets a Hunter creature")
	else ok(false, t.id .. " unknown kind") end
	-- The task's level gate is at least the resource / creature requirement.
	if t.kind == "gather" then
		local r = P.resource(t.target)
		ok((t.levels[r.skill] or 0) >= r.level, t.id .. " gated at the resource level")
	end
end
ok((groups.Mining or 0) >= 10, "mining-heavy pool (" .. (groups.Mining or 0) .. ")")
ok((kinds.kill or 0) >= 10, "combat commissions (" .. (kinds.kill or 0) .. ")")
ok((kinds.catch or 0) >= 3 and (groups.Fishing or 0) >= 3 and (groups.Farming or 0) >= 3 and (groups.Woodcutting or 0) >= 3, "variety tasks")
for _, id in ipairs({"ShaleCrawler", "CinderMite", "GloomfangSpider", "VoidWisp"}) do ok(CL.TaskById["Slay" .. id] ~= nil, "quarry/cavern hunt " .. id) end
for _, r in ipairs(Data.ResourceTiers.Mining) do ok(CL.TaskById["Mine" .. r.id] ~= nil, "a commission for every ore tier: " .. r.id) end
-- Days.
eq(CL.dayOf(0), 0, "epoch day")
eq(CL.dayOf(86399), 0, "end of day 0")
eq(CL.dayOf(86400), 1, "day 1 starts at UTC midnight")
eq(CL.resetIn(86400 * 5 + 100), 86300, "reset countdown")
-- Draws: deterministic, distinct, gated, first slot mining.
local function ctxOf(levels, regions) return {levels = levels or {}, regions = regions or {}} end
local fresh = ctxOf({})
local allRegions = {}
for _, r in ipairs(Data.Regions) do allRegions[r.id] = true end
local maxed = {}
for skill in pairs(Data.Skills) do maxed[skill] = 99 end
local veteran = ctxOf(maxed, allRegions)
local seenIds = {}
for day = 20000, 20120 do
	for _, salt in ipairs({1, 777, 999999}) do
		local a = CL.draw(day, salt, fresh)
		local b = CL.draw(day, salt, fresh)
		eq(table.concat(a, ","), table.concat(b, ","), "draw deterministic d" .. day .. " s" .. salt)
		eq(#a, 4, "fresh journal gets four commissions")
		eq(CL.TaskById[a[1]].group, "Mining", "first slot is mining")
		local set = {}
		for _, id in ipairs(a) do
			ok(not set[id], "distinct slots")
			set[id] = true
			ok(CL.eligible(CL.TaskById[id], fresh), id .. " eligible for a fresh journal")
			for skill, lvl in pairs(CL.TaskById[id].levels) do ok(lvl <= 1, id .. " needs no levels from a fresh journal") end
			local reg = CL.TaskById[id].region
			ok(reg == nil or not next(Data.RegionById[reg].requires), id .. " is in an open region")
		end
		for _, id in ipairs(CL.draw(day, salt, veteran)) do seenIds[id] = true end
	end
end
local vets = 0
for _ in pairs(seenIds) do vets += 1 end
ok(vets >= 35, "a veteran sees most of the pool over 120 days (" .. vets .. ")")
ok(table.concat(CL.draw(20001, 5, fresh), ",") ~= table.concat(CL.draw(20002, 5, fresh), ",") or table.concat(CL.draw(20003, 5, fresh), ",") ~= table.concat(CL.draw(20002, 5, fresh), ","), "boards change between days")
ok(table.concat(CL.draw(20001, 5, veteran), ",") ~= table.concat(CL.draw(20001, 6, veteran), ",") or table.concat(CL.draw(20001, 7, veteran), ",") ~= table.concat(CL.draw(20001, 6, veteran), ","), "salt varies boards between journals")
-- Gates.
ok(not CL.eligible(CL.TaskById.MineVoidstone, ctxOf({Mining = 99})), "gated region refused without access")
ok(CL.eligible(CL.TaskById.MineVoidstone, ctxOf({Mining = 99}, {Gloomhollow = true})), "gated region allowed with access")
ok(not CL.eligible(CL.TaskById.MineVoidstone, ctxOf({Mining = 44}, {Gloomhollow = true})), "level gate refuses")
ok(CL.eligible(CL.TaskById.MineAetherite, ctxOf({Mining = 3})), "Aetherite at Mining 3")
ok(not CL.eligible(CL.TaskById.MineAetherite, ctxOf({Mining = 2})), "not at Mining 2")
-- Milestones.
local ats = {}
for i, m in ipairs(CL.Milestones) do ats[i] = m.at end
eq(table.concat(ats, ","), "1,5,15,50,150", "milestones at 1/5/15/50/150")
eq(CL.milestonePerks(0).reached, 0, "no milestone at 0")
eq(CL.milestonePerks(1).dustPct, 10, "first milestone +10% dust")
eq(CL.milestonePerks(5).gemChance, 0.25, "gem sense at 5")
eq(CL.milestonePerks(15).stats.health, 20, "grit at 15")
eq(CL.milestonePerks(50).dustPct, 35, "dust stacks to 35%")
eq(CL.milestonePerks(50).coinPct, 10, "coins +10% at 50")
eq(CL.milestonePerks(150).forgeDiscount, 20, "paragon discount")
eq(CL.milestonePerks(150).title, "Forgeheart Paragon", "paragon title")
eq(CL.milestonePerks(149).title, nil, "no title before 150")
for _, m in ipairs(CL.Milestones) do
	for stat in pairs(m.stats or {}) do ok(Data.Stats[stat] ~= nil and stat ~= "miningFortune" and stat ~= "miningSpeed", m.id .. " stat is real and yield-neutral") end
end
do
	local t = CL.TaskById.MineOre
	eq(CL.reward(t, 0).dust, t.dust, "base dust")
	eq(CL.reward(t, 1).dust, math.floor(t.dust * 1.1), "dust +10% after first")
	eq(CL.reward(t, 60).coins, math.floor(t.coins * 1.1), "coins +10% after 50")
	eq(CL.reward(t, 60).xp, t.xp, "xp unchanged")
end
-- Forgeheart economy.
eq(#CL.ForgeOrder, 3, "three Forgeheart perks")
for _, id in ipairs(CL.ForgeOrder) do
	local f = CL.Forge[id]
	ok(f.max >= 5, id .. " levels")
	local last = 0
	for lvl = 0, f.max - 1 do
		local cost = CL.forgeCost(id, lvl, 0)
		ok(cost > last, id .. " cost rises at " .. lvl)
		last = cost
		eq(CL.forgeCost(id, lvl, 20), math.max(1, math.floor(f.base * (lvl + 1) ^ 1.4 * 0.8 + 0.5)), id .. " discount " .. lvl)
		ok(CL.forgeCost(id, lvl, 20) < cost, id .. " discounted cheaper " .. lvl)
		if lvl > 0 then ok(f.gains[lvl + 1] <= f.gains[lvl], id .. " gains diminish at " .. lvl) end
	end
	eq(CL.forgeCost(id, f.max, 0), nil, id .. " no cost past max")
	eq(CL.forgeCost(id, -1, 0), nil, id .. " no negative level")
	eq(CL.forgeValue(id, 999), CL.forgeValue(id, f.max), id .. " value clamps")
end
eq(CL.forgeCost("Nope", 0, 0), nil, "unknown perk")
eq(CL.forgeValue("HearthglowFortune", 10), 48, "fortune perk total 48")
eq(CL.forgeValue("SteadfastPick", 10), 48, "speed perk total 48")
ok(math.abs(CL.forgeValue("Gemseeker", 5) - 0.6) < 1e-9, "gem perk total 0.6%")
eq(CL.forgeSkip({SteadfastPick = 10}), 20, "regrowth skip 20%")
eq(CL.forgeSkip({SteadfastPick = 3}), 6, "regrowth skip 6%")
-- Fortune budget shared with Mastery.
eq(CL.forgeStats({HearthglowFortune = 10}, 0).miningFortune, 48, "fortune with no mastery")
eq(CL.forgeStats({HearthglowFortune = 10}, 60).miningFortune, 39, "fortune fills the budget left")
eq(CL.forgeStats({HearthglowFortune = 10}, 99).miningFortune, nil, "no room above a full mastery")
eq(CL.forgeStats({HearthglowFortune = 10}, 150).miningFortune, nil, "never negative")
eq(CL.forgeStats({SteadfastPick = 2}, 99).miningSpeed, 15, "speed unaffected by the budget")
eq(next(CL.forgeStats({}, 0)), nil, "no perks, no stats")
ok(CL.FORTUNE_BUDGET < 100, "budget below one fortune step")
-- Total dust to finish Forgeheart vs income (~4 commissions/day).
do
	local cost = 0
	for _, id in ipairs(CL.ForgeOrder) do for lvl = 0, CL.Forge[id].max - 1 do cost += CL.forgeCost(id, lvl, 0) end end
	local avg = 0
	for _, t in ipairs(CL.Tasks) do avg += t.dust end
	avg /= #CL.Tasks
	local days = cost / (avg * 4 * 1.35)
	print(string.format("Forgeheart: %d Glimmerdust in total, ~%.0f dust/commission, ~%.0f days of full boards", cost, avg, days))
	ok(days >= 20 and days <= 120, "Forgeheart is a long-term goal (" .. math.floor(days) .. " days)")
end
-- Gem chance and gem picks.
eq(CL.gemChance({}, 0), 0, "no gem chance at start")
eq(CL.gemChance({}, 5), 0.25, "gem sense")
ok(math.abs(CL.gemChance({Gemseeker = 5}, 5) - 0.85) < 1e-9, "gem sense + gemseeker")
eq(CL.gemFor(1, 0), "SunstoneChip", "lowest roll")
eq(CL.gemFor(1, 0.999), "Mistpearl", "tier 1 tops at Mistpearl")
eq(CL.gemFor(8, 0.9999), "StarheartGem", "top tier can find Starheart")
eq(CL.gemFor(4, 0.9999), "Emberglass", "mid tier tops at Emberglass")
for t = 1, 9 do for r = 0, 0.99, 0.07 do ok(Data.Items[CL.gemFor(t, r)].category == "gem", "gem pick is a gem t" .. t) end end

-- Collection Log: auto-generated; an independent scan finds every unique exactly once.
local L = CL.log()
ok(L.total >= 90, "log has 90+ entries (" .. L.total .. ")")
eq(CL.log(), L, "log cached")
local expected = {}
for id, def in pairs(Data.Items) do
	if def.kind == "pet" or def.trailUnique or def.slayerUnique or def.minigameUnique then expected[id] = true end
end
do
	local seen = {}
	local function scan(t, depth)
		if seen[t] or depth > 12 then return end
		seen[t] = true
		local item, chance = rawget(t, "item"), rawget(t, "chance")
		if type(item) == "string" and Data.Items[item] and type(chance) == "number" and chance > 0 and chance < 0.05 then
			local def = Data.Items[item]
			if def.kind ~= "resource" and not (def.kind == "trail" and (def.category == "scroll" or def.category == "casket" or def.category == "spade" or def.category == "teleport")) then expected[item] = true end
		end
		for _, v in pairs(t) do if type(v) == "table" then scan(v, depth + 1) end end
	end
	for k, v in pairs(Data) do if type(v) == "table" and k ~= "Items" and k ~= "CommissionsLogs" then scan(v, 0) end end
	-- Non-iterated monsters (sea creatures, world bosses, superiors) too.
	for _, id in ipairs(Data.SeaCreatureOrder) do scan(Data.Monsters[id], 0) end
end
local appear = {}
for _, tab in ipairs(CL.LogTabOrder) do
	ok(CL.LogTabs[tab] ~= nil and CL.LogTabs[tab].coins > 0 and #CL.LogTabs[tab].title > 3, tab .. " tab reward defined")
	for _, id in ipairs(L.Tabs[tab]) do appear[id] = (appear[id] or 0) + 1; eq(L.Of[id], tab, id .. " indexed in " .. tab) end
end
local expectedCount = 0
for id in pairs(expected) do
	expectedCount += 1
	eq(appear[id], 1, id .. " appears exactly once in the log")
end
for id, n in pairs(appear) do ok(expected[id], id .. " is a real unique (" .. n .. ")") end
eq(L.total, expectedCount, "log total equals the independent scan")
for _, def in pairs(Data.Pets) do eq(L.Of[def.id .. "Pet"], "Pets", def.id .. " pet in Pets") end
for id, def in pairs(Data.Items) do
	if def.trailUnique then ok(L.Of[id] == "Trails" or L.Of[id] == "Pets", id .. " trail unique in Trails") end
	if def.slayerUnique then ok(L.Of[id] ~= nil, id .. " slayer unique logged") end
	if def.kind == "trail" and (def.category == "scroll" or def.category == "casket") then eq(L.Of[id], nil, id .. " scrolls/caskets are not uniques") end
	if def.kind == "resource" then eq(L.Of[id], nil, id .. " resources are not uniques") end
end
for _, tab in ipairs(L.Order) do ok(#L.Tabs[tab] > 0, tab .. " shown tab non-empty") end
for _, id in ipairs({"AurelionPet", "AstrolabeCharm", "StarFragment", "StarheartGem"}) do ok(L.Of[id] ~= nil, id .. " logged") end
for _, loot in ipairs(Data.WorldBosses.Aurelith.loot) do if loot.chance < 0.05 then ok(L.Of[loot.item] ~= nil, "world boss unique " .. loot.item) end end
-- A minigame unique added later is picked up on a rebuild.
do
	Data.Items.__LogProbe = {id = "__LogProbe", name = "Probe", kind = "material", rarity = "Rare", minigameUnique = true}
	local rebuilt = CL.log(true)
	eq(rebuilt.Of.__LogProbe, "Minigames", "minigame uniques get the Minigames tab")
	Data.Items.__LogProbe = nil
	CL.log(true)
	L = CL.log()
	eq(L.Of.__LogProbe, nil, "probe removed")
end
-- Score and rank.
do
	local score, max, found = CL.logScore({})
	eq(score, 0, "empty score")
	eq(found, 0, "nothing found")
	ok(max >= L.total, "max score counts rarity points")
	local all = {}
	for id in pairs(L.Of) do all[id] = 1 end
	local s2, m2, f2 = CL.logScore(all)
	eq(s2, m2, "full log = max score")
	eq(f2, L.total, "full log found")
	eq(CL.logRank(s2, m2).name, "Aether Annalist", "top rank")
	eq(CL.logRank(0, m2).name, "Driftling", "bottom rank")
	eq(CL.logRank(m2 * 0.5, m2).name, "Archivist", "half rank")
	eq(CL.logRank(m2 * 0.3, m2).name, "Lorekeeper", "lorekeeper rank")
	eq(CL.logRank(0, 0).name, "Driftling", "zero max safe")
end
-- Museum.
local M = CL.museum()
ok(M.total >= 150, "museum holds 150+ items (" .. M.total .. ")")
local inCat = {}
for _, c in ipairs(CL.MuseumOrder) do
	ok(#M.Cats[c] > 0, c .. " has items")
	for _, id in ipairs(M.Cats[c]) do
		ok(inCat[id] == nil, id .. " in one category")
		inCat[id] = c
		eq(CL.museumCategory(id), c, id .. " category lookup")
	end
end
for id, def in pairs(Data.Items) do
	if def.kind == "weapon" then eq(inCat[id], "Weapons", id .. " weapon") end
	if def.kind == "armor" then eq(inCat[id], "Armor", id .. " armor") end
	if def.kind == "accessory" then eq(inCat[id], "Rarities", id .. " rarity") end
	if def.kind == "pet" or def.kind == "consumable" or def.kind == "tool" then eq(inCat[id], nil, id .. " not donatable") end
	if def.category == "gem" then eq(inCat[id], "Minerals", id .. " gem is a mineral") end
end
for _, r in ipairs(Data.ResourceTiers.Mining) do eq(inCat[r.id], "Minerals", r.id .. " ore mineral") end
eq(CL.museumCategory("Nope"), nil, "unknown item")
eq(CL.museumCategory(nil), nil, "nil item")
local mAts = {}
local prevAt, prevCoins = 0, 0
for _, m in ipairs(CL.MuseumMilestones) do
	ok(m.at > prevAt and m.coins > prevCoins, "museum milestones rise")
	prevAt, prevCoins = m.at, m.coins
	for stat in pairs(m.stats) do ok(Data.Stats[stat] ~= nil and not string.find(stat, "Fortune") and stat ~= "miningSpeed", "museum stat " .. stat .. " is yield-neutral") end
end
ok(CL.MuseumMilestones[#CL.MuseumMilestones].at <= M.total, "last museum milestone reachable")
do
	local s, r = CL.museumPerks(0)
	eq(next(s), nil, "no museum perks at 0")
	eq(r, 0, "no museum milestone")
	s, r = CL.museumPerks(30)
	eq(r, 3, "three museum milestones at 30")
	eq(s.health, 10, "health perk")
	eq(s.defense, 5, "defense perk")
	eq(s.strength, 3, "strength perk")
end
print("PASS: " .. (checks - partA) .. " Commissions & Logs data assertions.")

------------------------------------------------------------------------------
-- Part B: max single-click yield with Forgeheart (extends verify-progression).
------------------------------------------------------------------------------
local partB = checks
do
	local MA = Data.Mastery
	local function always(v) return function() return v end end
	local function missThenHit() local first = true; return function() if first then first = false; return 0.9999 end return 0 end end
	local function maxedXp()
		local xp = {}
		for skill in pairs(Data.Skills) do xp[skill] = Data.MAX_XP end
		return xp
	end
	local function fullTree(treeId)
		local out = {}
		for _, n in ipairs(MA.TreeById[treeId].nodes) do out[n.id] = n.max end
		return out
	end
	local function gearAllowance(skill)
		local stat, kind = Data.FortuneStat[skill], Data.ToolKind[skill]
		local reforge = 0
		for _, rf in pairs(Data.Gear.Reforges) do
			if rf.category == "tool" and rf.stats and rf.stats.fortune and (rf.toolKinds == nil or table.find(rf.toolKinds, kind)) then reforge = math.max(reforge, rf.stats.fortune) end
		end
		local acc = 0
		for _, def in pairs(Data.Items) do if def.kind == "accessory" and def.stats and def.stats[stat] then acc += def.stats[stat] end end
		return reforge + acc
	end
	local function bestTool(skill)
		local stat, kind = Data.FortuneStat[skill], Data.ToolKind[skill]
		local bestId, best = nil, -1
		for id, def in pairs(Data.Items) do
			local f = def.kind == "tool" and def.toolKind == kind and def.stats and def.stats[stat] or -1
			if f > best then bestId, best = id, f end
		end
		return bestId
	end
	local function maxEventFor(skill)
		local bonus, mult = 0, 1
		for _, ev in pairs(Data.Events) do if ev.skill == skill then bonus = math.max(bonus, ev.gatherBonus or 0); mult = math.max(mult, ev.featuredMult or 1) end end
		return bonus, mult
	end
	local NOW = 5000
	-- Every progression layer: mastery (capstone running + mantle), Forgeheart
	-- maxed, every commission milestone and every museum milestone.
	local function gatherer(skill, mastered, forge, at)
		local tool = bestTool(skill)
		local p = {xp = maxedXp(), items = {[tool] = 1}, collection = {}, coins = 0, enchants = {[tool] = {Fortune = Data.Enchants.Fortune.maxLevel}}}
		if mastered then
			local treeId = MA.TreeOfSkill[skill]
			p.mastery = {trees = {[treeId] = fullTree(treeId)}, active = {[treeId] = {started = NOW - 1, expires = NOW + 10}}, cape = skill}
		end
		if forge then
			local levels = {}
			for _, id in ipairs(CL.ForgeOrder) do levels[id] = CL.Forge[id].max end
			local masteryFortune = p.mastery and P.masteryStats(p, at or NOW).miningFortune or 0
			p.perkStats = {forgeheart = CL.forgeStats(levels, masteryFortune), ["commissions:milestones"] = CL.milestonePerks(150).stats, museum = (CL.museumPerks(999))}
		end
		return p
	end
	local function clickMax(skill, mastered, forge, rng, at)
		local p = gatherer(skill, mastered, forge, at)
		local stats = P.computeStats(p, at or NOW)
		stats[Data.FortuneStat[skill]] += gearAllowance(skill)
		local r = Data.ResourceTiers[skill][1]
		local evBonus, evMult = maxEventFor(skill)
		local bonus = 1 + 1 + 1 + 1 + evBonus + (if r.id == "Ore" then 2 else 0)
		local okH, res = P.harvest(p, r.id, stats, rng or always(0), bonus, at or NOW)
		assert(okH, tostring(res))
		return res.amount * evMult, res.fortune, res
	end
	print("Max single-click yield with Forgeheart + milestones + museum:")
	for _, skill in ipairs({"Mining", "Woodcutting", "Fishing", "Farming"}) do
		for _, at in ipairs({NOW, NOW + 100}) do
			local pre, f0 = clickMax(skill, false, false, nil, at)
			local post, f1 = clickMax(skill, true, true, nil, at)
			local missPre = clickMax(skill, false, false, missThenHit(), at)
			local missPost = clickMax(skill, true, true, missThenHit(), at)
			local tag = skill .. (if at == NOW then " (capstone)" else " (proc)")
			print(string.format("  %-22s fortune %d -> %d   %d -> %d   %.2fx (miss %.2fx)", tag, f0, f1, pre, post, post / pre, missPost / missPre))
			ok(f1 - f0 < 100, tag .. " mastery + Forgeheart fortune < 100 (" .. (f1 - f0) .. ")")
			ok(post / pre <= 2.5, tag .. " ratio <= 2.5")
			ok(missPost / missPre <= 2.5, tag .. " remainder-miss ratio <= 2.5")
		end
	end
	-- Forgeheart alone (no mastery) helps a mid-game miner, still within the rule.
	local plain = gatherer("Mining", false, true)
	eq(plain.perkStats.forgeheart.miningFortune, 48, "no mastery: full Hearthglow Fortune")
	local caped = gatherer("Mining", true, true)
	eq(caped.perkStats.forgeheart.miningFortune, nil, "full mastery leaves no budget")
	local f0 = P.computeStats(gatherer("Mining", false, false), NOW).miningFortune
	local f1 = P.computeStats(plain, NOW).miningFortune
	eq(f1 - f0, 48, "Forgeheart fortune reaches the sheet")
	ok(P.computeStats(plain, NOW).miningSpeed >= 48, "Forgeheart mining speed reaches the sheet")
	-- Regrowth with Steadfast Pick never passes Mastery's passive cap / floor.
	for _, base in ipairs({3, 10, 25}) do
		for _, mastery in ipairs({0, 30, 50, 80}) do
			local total = math.max(mastery, math.min(MA.PASSIVE_CAPS.respawnSkip, mastery + CL.forgeSkip({SteadfastPick = 10})))
			local t = P.regrowthTime(base, total)
			ok(t >= P.regrowthTime(base, math.max(mastery, MA.PASSIVE_CAPS.respawnSkip)), "regrowth floor b" .. base .. " m" .. mastery)
			ok(t <= base, "regrowth never longer b" .. base)
		end
	end
end
print("PASS: " .. (checks - partB) .. " Commissions & Logs yield-rule assertions.")

------------------------------------------------------------------------------
-- Part C: world.
------------------------------------------------------------------------------
local partC = checks
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
luau.load(fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position"), {environment = worldEnv, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
ok(islands ~= nil, "islands built")
local boardModel = islands:FindFirstChild("Brassfall Quarry"):FindFirstChild("Commission Board")
local museumModel = islands:FindFirstChild("Compass Quay"):FindFirstChild("Aether Museum")
ok(boardModel ~= nil and boardModel:GetAttribute("LogsContent") == true, "Commission Board on Brassfall Quarry")
ok(museumModel ~= nil and museumModel:GetAttribute("LogsContent") == true, "Aether Museum on Compass Quay")
local logPrompts = {}
for _, m in ipairs({boardModel, museumModel}) do
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			eq(d:GetAttribute("IsleAction"), "logsBoard", d.Parent.Name .. " routes to logsBoard")
			table.insert(logPrompts, d)
		end
		if d:IsA("BasePart") and d:GetAttribute("Shape") then ok(type(d:GetAttribute("Shape")) == "string", d.Name .. " mesh slot") end
	end
end
eq(#logPrompts, 4, "board, anvil, display case and lectern prompts")
local items = {}
for _, q in ipairs(logPrompts) do items[q:GetAttribute("IsleItem")] = (items[q:GetAttribute("IsleItem")] or 0) + 1 end
eq(items.Commissions, 2, "two commission prompts")
eq(items.Museum, 1, "museum prompt")
eq(items.Log, 1, "log prompt")
ok(islands:FindFirstChild("Anchor_Waypoint_CommissionBoard", true) ~= nil, "board waypoint anchor")
ok(islands:FindFirstChild("Anchor_Waypoint_Museum", true) ~= nil, "museum waypoint anchor")
do
	local visitor = {attrs = {}}
	function visitor:SetAttribute(k, v) self.attrs[k] = v end
	function visitor:GetAttribute(k) return self.attrs[k] end
	for _, q in ipairs(logPrompts) do
		local before = visitor.attrs.IsleStationVisit or 0
		q.Triggered:Fire(visitor)
		eq(visitor.attrs.IsleStationVisit, before + 1, q.Parent.Name .. " bumps the visit counter")
		local want = ({Commissions = "Commissions", Museum = "Museum", Log = "CollectionLog"})[q:GetAttribute("IsleItem")]
		eq(visitor.attrs.IsleStation, want, q.Parent.Name .. " opens " .. want)
	end
	-- The museum stands on its island, clear of the plaza monument.
	local c = islands:FindFirstChild("Compass Quay"):GetAttribute("IslandCenter")
	local dais = museumModel:FindFirstChild("Museum dais")
	local d = Vector3.new(dais.CFrame.Position.X - c.X, 0, dais.CFrame.Position.Z - c.Z).Magnitude
	ok(d > 30 and d < islands:FindFirstChild("Compass Quay"):GetAttribute("IslandRadius") - 8, "museum dais on open hub ground (" .. math.floor(d) .. ")")
end
print("PASS: " .. (checks - partC) .. " Commissions & Logs world assertions.")

------------------------------------------------------------------------------
-- Part D: server behaviour.
------------------------------------------------------------------------------
local partD = checks
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
local buildTrails = load("trails.lua")
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}, AetherTrails = {Name = "AetherTrails"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [markers.AetherTrails] = buildTrails}
local rolls, defaultRoll = {}, 0.999
local function nextRoll() if #rolls > 0 then return table.remove(rolls, 1) end return defaultRoll end
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) if name == "AetherTrails" then return markers.AetherTrails end return nil end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "logs-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local logsApi
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end, FindFirstChild = function(_, name) if name == "Islands" then return islands end return nil end},
	Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function()
		local o = {Event = signal(), FireClient = function(_, player, state) player.last = state end}
		table.insert(serverObjects, o)
		return o
	end},
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return nextRoll() end, NextInteger = function(_, lo, hi) return lo + math.floor(nextRoll() * (hi - lo + 1)) end} end},
	__LogsHarness = function(api) logsApi = api end,
	task = {
		spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
ok(logsApi ~= nil and type(logsApi.migrate) == "function", "Logs block loaded")
local liveById = {}
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.zero, Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	if liveById[id] then services.Players.PlayerRemoving:Fire(liveById[id]) end
	liveById[id] = p
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) if liveById[p.UserId] == p then liveById[p.UserId] = nil end services.Players.PlayerRemoving:Fire(p) end
local function stored(p) leave(p); return data["p" .. p.UserId].profile end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	mutate(data["p" .. id].profile)
	return player(id)
end
local remote, bridge
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
end
ok(remote ~= nil and bridge ~= nil, "IsleAction and IsleBridge found")
local function cmd(p, verb, item) advance(1); return remote.OnServerInvoke(p, verb, item) end
-- A gather prompt double (server checks attributes, distance and Enabled).
local function node(item, region)
	local base = {CFrame = CFrame.new(0, 0, 0)}
	local q = {Enabled = true, MaxActivationDistance = 9, attrs = {IsleAction = "gather", IsleItem = item, IsleRegion = region}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function boardPrompt(item)
	local q = node(item)
	q.attrs.IsleAction = "logsBoard"
	return q
end
local function use(p, q) advance(30); p.last = nil; services.ProximityPromptService.PromptTriggered:Fire(q, p); return p.last end
local X = Data.XP_TABLE
local function today() return CL.dayOf(utc) end
local function slots(snap) return snap.logs.commissions.slots end

-- Fresh journal: a board of four, nothing claimed, retro credit of nothing.
local miner = player(7001)
local s0 = cmd(miner, "state")
ok(type(s0.logs) == "table", "snapshot carries logs")
eq(#slots(s0), 4, "four commissions")
eq(CL.TaskById[slots(s0)[1].id].group, "Mining", "first is mining")
eq(s0.logs.commissions.day, today(), "board for today")
eq(s0.logs.commissions.dust, 0, "no dust")
eq(s0.logs.commissions.total, 0, "no completions")
ok(s0.logs.commissions.resetIn > 0 and s0.logs.commissions.resetIn <= 86400, "reset timer")
for i, s in ipairs(slots(s0)) do
	eq(s.progress, 0, "slot " .. i .. " empty")
	eq(s.claimed, false, "slot " .. i .. " unclaimed")
	ok(s.reward.dust > 0, "slot " .. i .. " shows dust reward")
	ok(CL.eligible(CL.TaskById[s.id], {levels = {}, regions = {}}), "slot " .. i .. " gated for a fresh journal")
end
eq(s0.logs.log.found, 0, "empty log")
eq(s0.logs.log.retro, 0, "nothing to credit retroactively")
eq(s0.logs.museum.count, 0, "empty museum")
eq(miner.attrs.LogTitle, "", "no title")
local firstIds = {}
for i, s in ipairs(slots(s0)) do firstIds[i] = s.id end
-- Persistence and determinism: the same board after a rejoin.
local prof = stored(miner)
eq(prof.commissions.day, today(), "day stored")
ok(prof.commissions.salt >= 1, "salt stored")
eq(#prof.commissions.slots, 4, "slots stored")
miner = player(7001)
local s1 = cmd(miner, "state")
for i, s in ipairs(slots(s1)) do eq(s.id, firstIds[i], "rejoin keeps slot " .. i) end
-- The stored board is what CL.draw gives for this salt and context.
do
	local drawn = CL.draw(today(), prof.commissions.salt, {levels = {}, regions = {}})
	for i, id in ipairs(drawn) do eq(id, firstIds[i], "draw reproduces slot " .. i) end
end
-- Unfinished claims are refused.
for i = 1, 4 do ok(has(cmd(miner, "commissionClaim", tostring(i)).message, "not finished"), "unfinished slot " .. i .. " refused") end
ok(has(cmd(miner, "commissionClaim", "9").message, "Unknown commission"), "bad slot")
ok(has(cmd(miner, "commissionClaim", "x").message, "Unknown commission"), "non-number slot")
ok(has(cmd(miner, "commissionClaim", "1.5").message, "Unknown commission"), "fractional slot")
ok(has(cmd(miner, "commissionClaimAll").message, "No finished"), "nothing to claim all")

-- A fixed board to drive progress.
local function setBoard(prof, ids, progress)
	prof.commissions.day = CL.dayOf(utc)
	prof.commissions.slots = {}
	for i, id in ipairs(ids) do table.insert(prof.commissions.slots, {id = id, progress = (progress and progress[i]) or 0, claimed = false}) end
end
local worker = seeded(7002, function(prof)
	setBoard(prof, {"MineOre", "SlayShaleCrawler", "GatherTimber", "CatchPuffcapHopper"}, {CL.TaskById.MineOre.amount - 2, CL.TaskById.SlayShaleCrawler.amount - 1, 0, CL.TaskById.CatchPuffcapHopper.amount - 1})
end)
local ws = cmd(worker, "state")
eq(slots(ws)[1].id, "MineOre", "fixed board kept (valid ids)")
-- Gathering Ore progresses the Ore commission by one per harvest; Herb does not.
use(worker, node("Herb"))
eq(cmd(worker, "state").logs.commissions.slots[1].progress, CL.TaskById.MineOre.amount - 2, "other resources do not count")
local g1 = use(worker, node("Ore"))
ok(g1 ~= nil and has(g1.message, "Copperstone"), "ore harvested")
eq(g1.logs.commissions.slots[1].progress, CL.TaskById.MineOre.amount - 1, "harvest counted")
local g2 = use(worker, node("Ore"))
eq(g2.logs.commissions.slots[1].progress, CL.TaskById.MineOre.amount, "commission finished")
eq(g2.logs.commissions.slots[1].done, true, "done flag")
ok(has(g2.message, "Commission complete"), "completion note")
local g3 = use(worker, node("Ore"))
eq(g3.logs.commissions.slots[1].progress, CL.TaskById.MineOre.amount, "progress capped at the amount")
-- Claim once.
local before = cmd(worker, "state")
local xpBefore = before.xp.Mining
local claim = cmd(worker, "commissionClaim", "1")
local reward = CL.reward(CL.TaskById.MineOre, 0)
ok(has(claim.message, "claimed"), "claim message")
eq(claim.logs.commissions.dust, reward.dust, "dust paid")
eq(claim.logs.commissions.earned, reward.dust, "lifetime dust")
ok(claim.coins >= before.coins + reward.coins, "coins paid (plus any level-up coins)")
ok(claim.xp.Mining >= xpBefore + reward.xp, "Mining XP paid")
eq(claim.logs.commissions.total, 1, "one completion")
eq(claim.logs.commissions.milestone, 1, "first milestone")
eq(claim.logs.commissions.slots[1].claimed, true, "claimed flag")
ok(has(claim.message, "First Shift") or has(claim.message, "milestone"), "milestone note")
ok(has(cmd(worker, "commissionClaim", "1").message, "already claimed"), "second claim refused")
eq(cmd(worker, "state").logs.commissions.dust, reward.dust, "no double pay")
-- Kill bridge progress (right monster only).
bridge.OnInvoke("kill", worker, {monster = "CinderMite"})
eq(cmd(worker, "state").logs.commissions.slots[2].progress, CL.TaskById.SlayShaleCrawler.amount - 1, "other monsters do not count")
bridge.OnInvoke("kill", worker, {monster = "ShaleCrawler"})
local k = cmd(worker, "state")
eq(k.logs.commissions.slots[2].done, true, "kill commission finished")
-- Claim all pays both finished slots with the first-milestone dust boost.
local dustBefore = cmd(worker, "state").logs.commissions.dust
local all = cmd(worker, "commissionClaimAll")
eq(all.logs.commissions.total, 2, "claim all paid the finished kill slot")
eq(all.logs.commissions.dust, dustBefore + CL.reward(CL.TaskById.SlayShaleCrawler, 1).dust, "boosted dust")
eq(CL.reward(CL.TaskById.SlayShaleCrawler, 1).dust, math.floor(CL.TaskById.SlayShaleCrawler.dust * 1.1), "boost is +10%")
ok(has(cmd(worker, "commissionClaimAll").message, "No finished"), "claim all is once")
-- Rollover: a finished-but-unclaimed slot is auto-claimed, then a new board is drawn.
local roller = seeded(7003, function(prof) setBoard(prof, {"MineOre", "GatherHerb", "GatherTimber", "SlayShaleCrawler"}, {CL.TaskById.MineOre.amount, 3, 0, 0}) end)
local r0 = cmd(roller, "state")
eq(r0.logs.commissions.slots[1].done, true, "finished before midnight")
local day0 = r0.logs.commissions.day
advance(86400)
local r1 = cmd(roller, "state")
eq(r1.logs.commissions.day, day0 + 1, "new UTC day")
eq(r1.logs.commissions.total, 1, "auto-claimed at reset")
eq(r1.logs.commissions.dust, CL.reward(CL.TaskById.MineOre, 0).dust, "auto-claim paid dust once")
for i, s in ipairs(r1.logs.commissions.slots) do eq(s.progress, 0, "new board slot " .. i .. " fresh"); eq(s.claimed, false, "new slot " .. i .. " unclaimed") end
local saltR = stored(roller).commissions.salt
roller = player(7003)
local r2 = cmd(roller, "state")
local drawnR = CL.draw(CL.dayOf(utc), saltR, {levels = {Mining = P.levelForXp(r2.xp.Mining)}, regions = {}})
eq(r2.logs.commissions.slots[1].id, drawnR[1], "new board drawn from today's seed")
eq(r2.logs.commissions.total, 1, "auto-claim not repeated on rejoin")
advance(86400)
eq(cmd(roller, "state").logs.commissions.total, 1, "unfinished slots are not paid at reset")
-- Gates on the live server: a veteran with region access sees gated tasks; a novice never does.
local veteranP = seeded(7004, function(prof)
	for skill in pairs(prof.xp) do prof.xp[skill] = X[99] end
	prof.questCompleted = 8
	prof.commissions.day = 0
end)
local gatedSeen = false
for _ = 1, 20 do
	advance(86400)
	for _, s in ipairs(cmd(veteranP, "state").logs.commissions.slots) do
		local t = CL.TaskById[s.id]
		if t.region and next(Data.RegionById[t.region].requires) then gatedSeen = true end
	end
end
ok(gatedSeen, "a veteran draws gated-region commissions")
local novice = player(7005)
for _ = 1, 20 do
	advance(86400)
	for _, s in ipairs(cmd(novice, "state").logs.commissions.slots) do
		local t = CL.TaskById[s.id]
		for _, lvl in pairs(t.levels) do ok(lvl <= 1, "novice " .. s.id .. " level gate") end
		ok(t.region == nil or not next(Data.RegionById[t.region].requires), "novice " .. s.id .. " region gate")
	end
end

-- Forgeheart.
local smith = player(7006)
ok(has(cmd(smith, "forgeBuy", "HearthglowFortune").message, "needs"), "no dust: refused")
ok(has(cmd(smith, "forgeBuy", "Nope").message, "Unknown Forgeheart"), "unknown perk")
smith = seeded(7006, function(prof) prof.commissions.dust = 100000 end)
local spent = 0
for lvl = 0, 9 do
	local cost = CL.forgeCost("HearthglowFortune", lvl, 0)
	local r = cmd(smith, "forgeBuy", "HearthglowFortune")
	spent += cost
	eq(r.logs.commissions.forge.HearthglowFortune, lvl + 1, "fortune level " .. (lvl + 1))
	eq(r.logs.commissions.dust, 100000 - spent, "exact cost at level " .. (lvl + 1))
end
ok(has(cmd(smith, "forgeBuy", "HearthglowFortune").message, "mastered"), "max level refused")
local fs1 = cmd(smith, "state")
eq(fs1.logs.commissions.fortune, 48, "48 fortune active without mastery")
eq(fs1.depth.stats.miningFortune - Data.Stats.miningFortune.base, 48, "fortune on the stat sheet")
for _ = 1, 5 do cmd(smith, "forgeBuy", "Gemseeker") end
eq(cmd(smith, "state").logs.commissions.forge.Gemseeker, 5, "gemseeker maxed")
ok(math.abs(cmd(smith, "state").logs.commissions.gemChance - 0.6) < 1e-9, "gem chance 0.6% (no milestone yet)")
-- With a full Mining mastery tree the fortune budget leaves less room.
smith = seeded(7006, function(prof)
	local MA = Data.Mastery
	local tree = {}
	for _, n in ipairs(MA.TreeById[MA.TreeOfSkill.Mining].nodes) do tree[n.id] = n.max end
	prof.xp.Mining = X[99]
	prof.mastery = {trees = {[MA.TreeOfSkill.Mining] = tree}, cape = "Mining"}
end)
local ms = cmd(smith, "state")
local smithStored = stored(smith)
local masteryF = (smithStored.mastery and P.masteryStats(smithStored, math.floor(utc)).miningFortune) or 0
print("Mining mastery fortune after migrate: " .. masteryF)
smith = player(7006)
eq(ms.logs.commissions.fortune, math.max(0, math.min(48, CL.FORTUNE_BUDGET - masteryF)), "fortune trimmed by mastery (" .. masteryF .. ")")
-- Paragon discount.
local paragon = seeded(7007, function(prof) prof.commissions.total = 150; prof.commissions.dust = 50 end)
local pc = cmd(paragon, "state")
eq(pc.logs.commissions.discount, 20, "paragon discount active")
eq(pc.logs.commissions.costs.SteadfastPick, CL.forgeCost("SteadfastPick", 0, 20), "discounted cost shown")
cmd(paragon, "forgeBuy", "SteadfastPick")
eq(cmd(paragon, "state").logs.commissions.dust, 50 - CL.forgeCost("SteadfastPick", 0, 20), "discounted cost charged")
eq(cmd(paragon, "logTitle", "Paragon").message, "Now titled: Forgeheart Paragon.", "paragon title worn")
eq(paragon.attrs.LogTitle, "Forgeheart Paragon", "title attribute")
ok(has(cmd(smith, "logTitle", "Paragon").message, "not unlocked"), "title needs 150")
-- Milestone perks reach the sheet (15: +20 health, +5 defense).
local grit = seeded(7008, function(prof) prof.commissions.total = 15 end)
local gs = cmd(grit, "state")
local plainSheet = cmd(player(7009), "state")
eq(gs.depth.stats.health - plainSheet.depth.stats.health, 20, "grit health")
eq(gs.depth.stats.defense - plainSheet.depth.stats.defense, 5, "grit defense")
eq(gs.logs.commissions.gemChance, 0.25, "gem sense at 15")

-- Gem rolls and regrowth through the gather hook.
local gemmer = seeded(7010, function(prof) prof.commissions.total = 5; prof.commissions.forge = {Gemseeker = 5, SteadfastPick = 10} end)
defaultRoll = 0
local gem = use(gemmer, node("Ore"))
defaultRoll = 0.999
ok(has(gem.message, "Gemseeker"), "gem found on an always-hit roll")
eq(gem.items.SunstoneChip, 1, "lowest roll gives a Sunstone Chip")
local nogem = use(gemmer, node("Ore"))
ok(not has(nogem.message, "Gemseeker"), "no gem on a missed roll")
eq(nogem.items.SunstoneChip, 1, "no extra gem")
ok(nogem.logs.log.counts.SunstoneChip == 1, "gem logged in the Collection Log")
do
	local profile = {commissions = {forge = {SteadfastPick = 10}, total = 0, slots = {}, day = CL.dayOf(utc)}, xp = {Mining = 0}, items = {}, collection = {}, perkStats = {}}
	local result = {}
	logsApi.gather(profile, "Voidstone", result, P.resource("Voidstone"))
	eq(result.regrowth, P.regrowthTime(10, 20), "Steadfast Pick shortens Voidstone regrowth by 20%")
	local r2 = {}
	profile.commissions.forge = {}
	logsApi.gather(profile, "Voidstone", r2, P.resource("Voidstone"))
	eq(r2.regrowth, nil, "no perk, no regrowth change")
	local r3 = {}
	profile.commissions.forge = {SteadfastPick = 10}
	logsApi.gather(profile, "Timber", r3, P.resource("Timber"))
	eq(r3.regrowth, nil, "only Mining nodes")
	-- Catch progress through the shared event (Hunter hook).
	profile.commissions.slots = {{id = "CatchPuffcapHopper", progress = 0, claimed = false}}
	logsApi.event(profile, "catch", "PuffcapHopper")
	eq(profile.commissions.slots[1].progress, 1, "catch counted")
	logsApi.event(profile, "catch", "SunwingMoth")
	eq(profile.commissions.slots[1].progress, 1, "other creature not counted")
	logsApi.event(profile, "kill", "PuffcapHopper")
	eq(profile.commissions.slots[1].progress, 1, "kind must match")
end

-- Collection Log: retroactive credit on first load.
local veteranLog = seeded(7011, function(prof)
	prof.colLog = nil
	prof.items.BurrowmolePet = 2
	prof.collection.StarFragment = 3
	prof.items.LenswrightSaber = 1
	prof.equipment = {weapon = "LenswrightSaber"}
	prof.pets = {{id = "Emberfox", level = 3, xp = 0}}
	prof.trails = prof.trails or {}
	prof.trails.uniques = {TrailCapWayfarer = 1}
	prof.items.Ore = 500 -- resources are not log entries
end)
local vl = cmd(veteranLog, "state")
eq(vl.logs.log.retro, 5, "five entries credited retroactively")
eq(vl.logs.log.counts.BurrowmolePet, 2, "held pet items")
eq(vl.logs.log.counts.StarFragment, 3, "lifetime collection")
eq(vl.logs.log.counts.LenswrightSaber, 1, "worn weapon")
eq(vl.logs.log.counts.EmberfoxPet, 1, "adopted pet")
eq(vl.logs.log.counts.TrailCapWayfarer, 1, "clue log unique")
eq(vl.logs.log.counts.Ore, nil, "resources not logged")
eq(vl.logs.log.found, 5, "five found")
ok(vl.logs.log.score >= 5, "score counts rarity points")
local vlStored = stored(veteranLog)
eq(vlStored.colLog.retro, 5, "retro stored")
veteranLog = player(7011)
eq(cmd(veteranLog, "state").logs.log.retro, 5, "retro not repeated")
eq(cmd(veteranLog, "state").logs.log.counts.StarFragment, 3, "counts persisted")
-- New drops are logged through collect() (kill bridge, every roll hits).
local dropper = player(7012)
defaultRoll = 0
bridge.OnInvoke("kill", dropper, {monster = "ShaleCrawler"})
defaultRoll = 0.999
local dl = cmd(dropper, "state")
eq(dl.logs.log.counts.BurrowmolePet, 1, "rare pet drop logged")
eq(dl.logs.log.counts.ArcaneDust, nil, "common drops are not logged")
-- Tab rewards and titles (World Bosses: complete by seeding every entry).
local bossTab = CL.log().Tabs.Bosses
local collector = seeded(7013, function(prof)
	for i, id in ipairs(bossTab) do if i < #bossTab then prof.colLog.counts[id] = 1 end end
end)
ok(has(cmd(collector, "logClaim", "Bosses").message, "Complete every"), "incomplete tab refused")
ok(has(cmd(collector, "logClaim", "Nope").message, "Unknown log tab"), "unknown tab")
collector = seeded(7013, function(prof) prof.colLog.counts[bossTab[#bossTab]] = 1 end)
local cs = cmd(collector, "state")
eq(cs.logs.log.complete.Bosses, true, "tab complete")
local coins0 = cs.coins
local claimed = cmd(collector, "logClaim", "Bosses")
eq(claimed.coins, coins0 + CL.LogTabs.Bosses.coins, "tab coins paid")
eq(claimed.logs.log.claimed.Bosses, true, "tab claimed")
ok(has(cmd(collector, "logClaim", "Bosses").message, "already claimed"), "tab claim once")
eq(cmd(collector, "state").coins, claimed.coins, "no second payout")
ok(has(cmd(collector, "logTitle", "Pets").message, "not unlocked"), "unclaimed title refused")
ok(has(cmd(collector, "logTitle", "Nope").message, "not unlocked"), "unknown title refused")
eq(cmd(collector, "logTitle", "Bosses").message, "Now titled: Crownbreaker.", "tab title worn")
eq(collector.attrs.LogTitle, "Crownbreaker", "LogTitle attribute")
eq(cmd(collector, "state").logs.log.titleText, "Crownbreaker", "title in snapshot")
eq(cmd(collector, "logTitle", "none").message, "Title removed.", "title removed")
eq(collector.attrs.LogTitle, "", "attribute cleared")

-- Museum donations.
local curator = seeded(7014, function(prof)
	prof.items.BrassSword = 1
	prof.items.SunsteelSword = 2
	prof.items.BrassHelm = 1
	prof.equipment = {helmet = "BrassHelm"}
	prof.items.EmberfoxPet = 1
	prof.items.Ore = 10
	prof.items.Emberglass = 1
	prof.items.Tonic = 3
	prof.stars = {SunsteelSword = 1}
end)
local function museumOf(p) return cmd(p, "state").logs.museum end
ok(has(cmd(curator, "museumDonate", "Nope").message, "cannot be displayed"), "unknown item refused")
ok(has(cmd(curator, "museumDonate", "EmberfoxPet").message, "cannot be displayed"), "pets are not museum items")
ok(has(cmd(curator, "museumDonate", "Tonic").message, "cannot be displayed"), "consumables are not museum items")
ok(has(cmd(curator, "museumDonate", "StarmetalSword").message, "do not own"), "unowned refused")
ok(has(cmd(curator, "museumDonate", "BrassHelm").message, "Unequip"), "equipped refused")
eq(museumOf(curator).count, 0, "nothing donated by refusals")
local d1 = cmd(curator, "museumDonate", "BrassSword")
ok(has(d1.message, "donated"), "donation accepted")
eq(d1.items.BrassSword, 0, "donated item consumed")
eq(d1.logs.museum.count, 1, "one on display")
eq(d1.logs.museum.donated.BrassSword, true, "flagged")
ok(has(cmd(curator, "museumDonate", "BrassSword").message, "already on display"), "no second donation")
eq(cmd(curator, "state").items.BrassSword, 0, "no item restored")
-- Upgraded ids: the last copy is refused, a spare copy may go.
local d2 = cmd(curator, "museumDonate", "SunsteelSword")
eq(d2.items.SunsteelSword, 1, "spare upgraded copy donated")
eq(d2.logs.museum.donated.SunsteelSword, true, "upgraded id displayed")
cmd(curator, "museumDonate", "Ore")
cmd(curator, "museumDonate", "Emberglass")
eq(museumOf(curator).count, 4, "four on display")
-- Bagged accessories are refused.
local bagger = seeded(7015, function(prof)
	local acc
	for id, def in pairs(Data.Items) do if def.kind == "accessory" and not acc then acc = id end end
	prof.items[acc] = 1
	prof.accessoryBag = {acc}
	prof.__acc = acc
end)
local accId = stored(bagger).__acc
bagger = player(7015)
ok(has(cmd(bagger, "museumDonate", accId).message, "accessory bag"), "bagged accessory refused")
local upg = seeded(7016, function(prof) prof.items.StarmetalSword = 1; prof.stars = {StarmetalSword = 1} end)
ok(has(cmd(upg, "museumDonate", "StarmetalSword").message, "carries upgrades"), "last upgraded copy refused")
local ench = seeded(7017, function(prof) prof.items.BrassBow = 1; prof.enchants = {BrassBow = {Sharpness = 1}} end)
if Data.Items.BrassBow then ok(has(cmd(ench, "museumDonate", "BrassBow").message, "carries upgrades"), "enchanted last copy refused") end
-- Milestones: 5 donations pays coins and a health perk.
curator = seeded(7014, function(prof) prof.items.StarmetalSword = 1 end)
local beforeCoins = cmd(curator, "state").coins
local beforeHealth = cmd(curator, "state").depth.stats.health
local fifth = cmd(curator, "museumDonate", "StarmetalSword")
eq(fifth.logs.museum.count, 5, "five on display")
eq(fifth.coins, beforeCoins + CL.MuseumMilestones[1].coins, "milestone coins")
eq(fifth.logs.museum.milestone, 1, "milestone reached")
eq(fifth.depth.stats.health - beforeHealth, 10, "museum health perk on the sheet")
eq(fifth.logs.museum.stats.health, 10, "museum perks in snapshot")
-- No coins twice after a rejoin.
local mStored = stored(curator)
eq(mStored.museum.paid, 1, "milestone paid stored")
curator = player(7014)
eq(cmd(curator, "state").coins, fifth.coins, "no repeat milestone coins")
-- Ironman journals use every verb (nothing trades).
local iron = seeded(7018, function(prof)
	prof.ironman = true
	prof.items.BrassSword = 1
	setBoard(prof, {"MineOre", "GatherHerb", "GatherTimber", "GatherFish"}, {CL.TaskById.MineOre.amount, 0, 0, 0})
end)
eq(cmd(iron, "commissionClaim", "1").logs.commissions.total, 1, "ironman claims")
eq(cmd(iron, "museumDonate", "BrassSword").logs.museum.count, 1, "ironman donates")
-- World prompts answer.
ok(has(use(iron, boardPrompt("Commissions")).message, "Commission Board"), "board prompt")
ok(has(use(iron, boardPrompt("Museum")).message, "curator"), "museum prompt")
ok(has(use(iron, boardPrompt("Log")).message, "Collection Log"), "log prompt")
ok(has(cmd(iron, "logsBoard", "Museum").message, "in person"), "board verb needs a prompt")

-- Migration bounds: tampered saves are sanitised.
local tampered = seeded(7019, function(prof)
	prof.commissions = {day = CL.dayOf(utc), salt = -5, dust = 1e15, total = -3, earned = "x",
		slots = {{id = "MineOre", progress = 1e9, claimed = "yes"}, {id = "Bogus", progress = 1}, "junk", {id = "GatherHerb", progress = -4}, {id = "GatherTimber"}, {id = "GatherFish"}, {id = "MineAetherite"}},
		forge = {SteadfastPick = 999, HearthglowFortune = -2, Bogus = 4}}
	prof.colLog = {counts = {BurrowmolePet = 1e15, Bogus = 3, Ore = 5, AurelionPet = "x"}, claimed = {Bosses = true, Nope = true, Pets = "y"}, title = "Pets", retro = 1e9}
	prof.museum = {donated = {BrassSword = true, Bogus = true, Tonic = true, Ore = "yes"}, count = 999, paid = 99}
end)
local tp = stored(tampered)
eq(#tp.commissions.slots, 4, "slots capped at four")
eq(tp.commissions.slots[1].progress, CL.TaskById.MineOre.amount, "progress clamped")
eq(tp.commissions.slots[1].claimed, false, "non-boolean claimed reset")
eq(tp.commissions.slots[2].id, "GatherHerb", "unknown/junk slots dropped")
eq(tp.commissions.slots[2].progress, 0, "negative progress zeroed")
eq(tp.commissions.dust, CL.MAX_DUST, "dust clamped")
eq(tp.commissions.total, 0, "negative total zeroed")
ok(tp.commissions.salt >= 1, "salt repaired")
eq(tp.commissions.forge.SteadfastPick, CL.Forge.SteadfastPick.max, "forge level clamped")
eq(tp.commissions.forge.HearthglowFortune, nil, "negative forge dropped")
eq(tp.commissions.forge.Bogus, nil, "unknown perk dropped")
eq(tp.colLog.counts.BurrowmolePet, 1e9, "log count clamped")
eq(tp.colLog.counts.Bogus, nil, "unknown log id dropped")
eq(tp.colLog.counts.Ore, nil, "non-unique dropped")
eq(tp.colLog.counts.AurelionPet, nil, "malformed count dropped")
eq(tp.colLog.claimed.Bosses, true, "valid claim kept")
eq(tp.colLog.claimed.Nope, nil, "unknown claim dropped")
eq(tp.colLog.claimed.Pets, nil, "malformed claim dropped")
eq(tp.colLog.title, "", "unclaimed title dropped")
eq(tp.colLog.retro, CL.log().total, "retro clamped")
eq(tp.museum.donated.Bogus, nil, "unknown donation dropped")
eq(tp.museum.donated.Tonic, nil, "ineligible donation dropped")
eq(tp.museum.donated.Ore, nil, "malformed donation dropped")
eq(tp.museum.count, 1, "count recomputed")
eq(tp.museum.paid, 0, "paid clamped to reached milestones")
do
	-- Worst-case save size stays small.
	local full = {commissions = {day = 1, salt = 1, slots = {}, total = 1, dust = 1, earned = 1, forge = {}}, colLog = {counts = {}, claimed = {}, title = "", retro = 0}, museum = {donated = {}, count = 0, paid = 0}}
	for id in pairs(CL.log().Of) do full.colLog.counts[id] = 999999999 end
	for id in pairs(Data.Items) do if CL.museumCategory(id) then full.museum.donated[id] = true end end
	local size = 0
	for id in pairs(full.colLog.counts) do size += #id + 14 end
	for id in pairs(full.museum.donated) do size += #id + 8 end
	print("Worst-case Commissions & Logs save: ~" .. size .. " bytes")
	ok(size < 9000, "worst-case log + museum save under 9 KB")
end
print("PASS: " .. (checks - partD) .. " Commissions & Logs server assertions.")

------------------------------------------------------------------------------
-- Part E: Journal pages.
------------------------------------------------------------------------------
local partE = checks
local H = require("./tools/ui-harness")
local function sample()
	local snap = H.snapshot({xp = {Mining = X[20]}})
	snap.items.BrassSword = 1
	snap.items.SunsteelSword = 1
	local L2 = CL.log()
	local counts = {}
	for i, id in ipairs(L2.Tabs.Bosses) do counts[id] = i end
	counts[L2.Tabs.Pets[1]] = 2
	snap.logs = {
		commissions = {day = 20000, resetIn = 3725, total = 6, dust = 900, earned = 1200, milestone = 2, discount = 0, gemChance = 0.45, fortune = 16,
			forge = {HearthglowFortune = 2, Gemseeker = 1}, costs = {SteadfastPick = 40, HearthglowFortune = CL.forgeCost("HearthglowFortune", 2, 0), Gemseeker = CL.forgeCost("Gemseeker", 1, 0)},
			slots = {
				{id = "MineOre", progress = 28, claimed = false, done = true, reward = CL.reward(CL.TaskById.MineOre, 6)},
				{id = "SlayShaleCrawler", progress = 4, claimed = false, done = false, reward = CL.reward(CL.TaskById.SlayShaleCrawler, 6)},
				{id = "CatchPuffcapHopper", progress = 6, claimed = true, done = true, reward = CL.reward(CL.TaskById.CatchPuffcapHopper, 6)},
				{id = "GatherHerb", progress = 0, claimed = false, done = false, reward = CL.reward(CL.TaskById.GatherHerb, 6)},
			}},
		log = {counts = counts, claimed = {}, complete = {Bosses = true}, title = "", titleText = "", score = 12, max = 300, found = #L2.Tabs.Bosses + 1, rank = "Driftling", retro = 3},
		museum = {donated = {BrassHelm = true}, count = 1, milestone = 0, stats = {}},
	}
	return snap
end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
local function atlas(size, mutate)
	local snap = sample()
	if mutate then mutate(snap) end
	local ui = H.runAtlas(size, {snapshot = snap})
	H.press(H.find(ui.gui, "AtlasButton"))
	return ui
end
local function open(ui, section)
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui.scroll, "Section" .. section:gsub("[^%w]", "")))
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui, "Commissions")
	eq(#ui.warnings, 0, "Commissions renders without warnings" .. tag)
	ok(H.find(ui.scroll, "CommissionsSummary") ~= nil, "commissions summary" .. tag)
	for i = 1, 4 do ok(H.find(ui.scroll, "Commission" .. i) ~= nil, "slot card " .. i .. tag) end
	ok(H.find(ui.scroll, "CommissionMilestones") ~= nil, "milestones card" .. tag)
	for _, id in ipairs(CL.ForgeOrder) do ok(H.find(ui.scroll, "Forge" .. id) ~= nil, id .. " forge card" .. tag) end
	open(ui, "Collection Log")
	eq(#ui.warnings, 0, "Collection Log renders without warnings" .. tag)
	ok(H.find(ui.scroll, "LogSummary") ~= nil, "log summary" .. tag)
	for _, t in ipairs(CL.log().Order) do ok(H.find(ui.scroll, "LogTab" .. t) ~= nil, t .. " tab button" .. tag) end
	local firstTab = CL.log().Order[1]
	for _, id in ipairs(CL.log().Tabs[firstTab]) do ok(H.find(ui.scroll, "LogEntry" .. id) ~= nil, id .. " log tile" .. tag) end
	open(ui, "Museum")
	eq(#ui.warnings, 0, "Museum renders without warnings" .. tag)
	ok(H.find(ui.scroll, "MuseumSummary") ~= nil, "museum summary" .. tag)
	for _, c in ipairs(CL.MuseumOrder) do ok(H.find(ui.scroll, "MuseumCat" .. c) ~= nil, c .. " category button" .. tag) end
	for _, id in ipairs(CL.museum().Cats.Weapons) do ok(H.find(ui.scroll, "MuseumItem" .. id) ~= nil, id .. " museum tile" .. tag) end
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	local function pressSends(section, name, verb, item)
		open(ui, section)
		local before = #ui.sent
		local b = H.find(ui.scroll, name)
		ok(b ~= nil, name .. " exists")
		H.press(b)
		ok(#ui.sent > before, name .. " sends")
		eq(ui.sent[#ui.sent][1], verb, name .. " verb")
		eq(ui.sent[#ui.sent][2], item, name .. " payload")
	end
	pressSends("Commissions", "CommissionClaim1", "commissionClaim", "1")
	pressSends("Commissions", "CommissionClaimAll", "commissionClaimAll", nil)
	pressSends("Commissions", "ForgeBuyHearthglowFortune", "forgeBuy", "HearthglowFortune")
	open(ui, "Commissions")
	ok(H.find(ui.scroll, "CommissionClaim2") == nil, "unfinished slot has no claim")
	ok(H.find(ui.scroll, "CommissionClaim3") == nil, "claimed slot has no claim")
	local text = texts(ui.scroll)
	ok(has(text, "1h 02m"), "reset timer shown")
	ok(has(text, "Glimmerdust"), "dust named")
	ok(has(text, "Gem Sense"), "milestones listed")
	ok(has(text, "Hearthglow Fortune"), "forgeheart listed")
	-- Collection Log: switch to Bosses and claim.
	open(ui, "Collection Log")
	H.press(H.find(ui.scroll, "LogTabBosses"))
	ok(H.find(ui.scroll, "LogGridBosses") ~= nil, "bosses grid")
	local before = #ui.sent
	H.press(H.find(ui.scroll, "LogClaimBosses"))
	eq(ui.sent[#ui.sent][1], "logClaim", "claim tab sends")
	eq(ui.sent[#ui.sent][2], "Bosses", "claim tab payload")
	ok(#ui.sent == before + 1 or #ui.sent > before, "one send")
	ok(has(texts(ui.scroll), "Crownbreaker"), "tab title shown")
	-- An incomplete tab's claim stays local.
	open(ui, "Collection Log")
	H.press(H.find(ui.scroll, "LogTabPets"))
	local b2 = #ui.sent
	H.press(H.find(ui.scroll, "LogClaimPets"))
	eq(#ui.sent, b2, "incomplete tab claim not sent")
	-- Museum: pick an owned item, donate.
	open(ui, "Museum")
	H.press(H.find(ui.scroll, "MuseumItemBrassSword"))
	ok(H.find(ui.scroll, "MuseumPick") ~= nil, "donation card")
	local b3 = #ui.sent
	H.press(H.find(ui.scroll, "MuseumDonate"))
	eq(ui.sent[#ui.sent][1], "museumDonate", "donate sends")
	eq(ui.sent[#ui.sent][2], "BrassSword", "donate payload")
	ok(#ui.sent > b3, "donation sent once")
	-- An unowned item opens no donation card.
	open(ui, "Museum")
	H.press(H.find(ui.scroll, "MuseumItemStarmetalSword"))
	ok(H.find(ui.scroll, "MuseumPick") == nil, "unowned item: no donation")
	H.press(H.find(ui.scroll, "MuseumCatArmor"))
	ok(H.find(ui.scroll, "MuseumGridArmor") ~= nil, "armor wing")
	ok(H.find(ui.scroll, "MuseumItemBrassHelm") ~= nil, "donated helm tile")
	for _, entry in ipairs(ui.sent) do ok(entry[2] == nil or (type(entry[2]) == "string" and #entry[2] <= 64), "payload short: " .. entry[1]) end
end
do
	-- World prompts open the matching Journal page.
	local ui = atlas(roblox.Vector2.new(1366, 768))
	for station, section in pairs({Commissions = "CommissionsSummary", Museum = "MuseumSummary", CollectionLog = "LogSummary"}) do
		ui.atlas.Visible = false
		ui.player:SetAttribute("IsleStation", station)
		ui.player:SetAttribute("IsleStationVisit", (ui.player:GetAttribute("IsleStationVisit") or 0) + 1)
		ok(ui.atlas.Visible, station .. " opens the atlas")
		ok(H.find(ui.scroll, section) ~= nil, station .. " opens its page")
	end
	-- Pages render before the logs sync.
	local bare = atlas(roblox.Vector2.new(730, 303), function(snap) snap.logs = nil end)
	for _, section in ipairs({"Commissions", "Collection Log", "Museum"}) do
		open(bare, section)
		eq(#bare.warnings, 0, section .. " renders before sync")
	end
	ok(has(texts(bare.scroll), "SYNCING"), "syncing badge")
end
print("PASS: " .. (checks - partE) .. " Commissions & Logs page assertions.")
print("PASS: " .. checks .. " Commissions & Logs assertions in total.")
print("SUITE-END verify-logs.luau")
