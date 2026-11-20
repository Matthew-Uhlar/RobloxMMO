-- Slayer tasks: OSRS-style Slayer masters, tasks, streaks, points, blocks,
-- unlocks, superiors and slayer-only monsters.
-- Part A checks shared/GameData.lua (Data.SlayerTasks): the skill, families,
-- masters, weighting, reachability, streak math, shop rules, superiors and
-- slayer-only monsters. Part B runs server.server.lua (deterministic clock,
-- rolls and DataStore doubles): task flow, kill credit, completion rewards,
-- skip/cancel/block, the shop, superior tickets, boss-line Slayer XP and
-- persistence/migration. Part C drives combat.server.lua's pure core (Slayer
-- damage gate, visor, superior spawns and ownership). Part D renders Hunt › Slayer.
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
local ST = Data.SlayerTasks
local X = Data.XP_TABLE
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
-- Deterministic PRNG (xorshift32) with a Random-like NextNumber in [0, 1).
local function rand(seed)
	local s = (seed * 2654435761) % 4294967296
	if s == 0 then s = 1 end
	return {NextNumber = function(self)
		s = bit32.bxor(s, bit32.lshift(s, 13)); s = bit32.bxor(s, bit32.rshift(s, 17)); s = bit32.bxor(s, bit32.lshift(s, 5))
		return s / 4294967296
	end}
end

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
ok(ST ~= nil, "Data.SlayerTasks present")
ok(table.find(Data.SkillOrder, "Slayer") ~= nil, "Slayer is a skill in SkillOrder")
eq(Data.SkillOrder[#Data.SkillOrder], "Slayer", "Slayer appended last (old saves keep their order)")
do
	local def = Data.Skills.Slayer
	ok(def and def.category == "combat" and #def.color == 6 and def.title and def.description, "Slayer skill metadata")
	for stat in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil, "Slayer perLevel stat " .. stat) end
	local stats = P.computeStats({xp = {Slayer = X[99]}, items = {}}, 0)
	local base = P.computeStats({xp = {}, items = {}}, 0)
	ok(stats.critDamage > base.critDamage and stats.strength > base.strength, "Slayer 99 raises Crit Damage and Strength")
end
-- Boss lines stay untouched (line ranks).
eq(#Data.SlayerOrder, 3, "three boss lines kept")
eq(#Data.SlayerLevels, 9, "line ranks 1-9 kept")

-- Families.
ok(#ST.Families >= 12, "at least 12 families (" .. #ST.Families .. ")")
local seenMonster, seaFamilies, endgame = {}, 0, false
for i, f in ipairs(ST.Families) do
	eq(ST.FamilyById[f.id], f, f.id .. " indexed")
	eq(f.index, i, f.id .. " index")
	ok(#f.name > 0 and #f.color == 6 and f.slayer >= 1 and f.slayer <= 99, f.id .. " values")
	ok(#f.monsters >= 1, f.id .. " has monsters")
	if i > 1 then ok(f.slayer >= ST.Families[i - 1].slayer, f.id .. " slayer levels ascend") end
	for _, id in ipairs(f.monsters) do
		ok(not seenMonster[id], id .. " in exactly one family")
		seenMonster[id] = true
		eq(ST.FamilyOf[id], f.id, id .. " maps to " .. f.id)
		local m = Data.Monsters[id]
		ok(m ~= nil, id .. " resolves")
		if f.sea then ok(m.seaCreature == true, id .. " is a sea creature") else ok(rawget(Data.Monsters, id) == m, id .. " is a marker monster") end
		if m.region == "ShatteredCrown" then endgame = true end
	end
	if f.sea then seaFamilies += 1 else ok(type(f.epithet) == "string", f.id .. " names its superiors") end
end
ok(seaFamilies >= 1, "a sea creature family")
ok(endgame, "an endgame (Shattered Crown) family")
-- Every marker monster belongs to a family.
for id in pairs(Data.Monsters) do ok(ST.FamilyOf[id] ~= nil, id .. " is assignable") end
ok(ST.inFamily("Thicketkin", "Thornling") and not ST.inFamily("Thicketkin", "ShaleCrawler") and not ST.inFamily(nil, "Thornling"), "inFamily")

-- Slayer-only monsters.
eq(#ST.SlayerOnlyOrder, 4, "four slayer-only monsters")
local onlyLevels = {}
for _, id in ipairs(ST.SlayerOnlyOrder) do
	local m = Data.Monsters[id]
	ok(rawget(Data.Monsters, id) == m, id .. " is a marker monster")
	ok(m.slayerLevel and m.slayerLevel >= 40, id .. " needs Slayer 40+")
	table.insert(onlyLevels, m.slayerLevel)
	ok(Data.RegionById[m.region] and table.find(Data.RegionById[m.region].monsters, id), id .. " listed in its region")
	ok(m.attackStyle and m.weakness and m.defenceStyle, id .. " has combat styles")
	eq(Data.CombatStyles.monsterStyle[id], m.attackStyle, id .. " style registered")
	local remains, unique = false, false
	for _, d in ipairs(m.drops) do
		ok(Data.Items[d.item] ~= nil, id .. " drop " .. d.item .. " exists")
		if Data.Prayer.RemainsById[d.item] then remains = true end
		if Data.Items[d.item].slayerUnique then unique = true; ok(d.chance < 0.01, id .. " unique is rare") end
	end
	ok(remains and unique, id .. " drops remains and a unique")
	local f = ST.FamilyById[ST.FamilyOf[id]]
	ok(f.slayer >= m.slayerLevel, id .. " family needs at least its damage level")
	local can, need = ST.canHarm(id, m.slayerLevel - 1)
	ok(not can and need == m.slayerLevel, id .. " cannot be harmed one level short")
	ok((ST.canHarm(id, m.slayerLevel)), id .. " harmable at its level")
end
eq(table.concat(onlyLevels, ","), "40,60,75,85", "slayer-only levels 40/60/75/85")
ok((ST.canHarm("Thornling", 1)), "ordinary monsters need no Slayer level")
eq(ST.slayerLevelFor("Nope"), 0, "unknown monster has no gate")
eq(ST.slayerLevelFor(nil), 0, "nil monster has no gate")

-- Masters.
ok(#ST.Masters >= 3 and #ST.Masters <= 4, "3-4 masters")
for i, m in ipairs(ST.Masters) do
	eq(ST.MasterById[m.id], m, m.id .. " indexed")
	if i > 1 then
		ok(m.combat > ST.Masters[i - 1].combat, m.id .. " combat gate ascends")
		ok(m.points > ST.Masters[i - 1].points and m.bounty > ST.Masters[i - 1].bounty, m.id .. " pays more")
	end
	ok(Data.RegionById[m.region] ~= nil, m.id .. " region")
	local fams = {}
	for _, t in ipairs(m.tasks) do
		ok(ST.FamilyById[t.family] ~= nil and t.weight > 0 and t.min >= 1 and t.max >= t.min and t.max <= ST.MAX_AMOUNT / ST.EXTEND_MULT, m.id .. " task " .. t.family)
		ok(not fams[t.family], m.id .. " lists " .. t.family .. " once")
		fams[t.family] = true
	end
	ok(#m.tasks >= 6, m.id .. " offers 6+ families")
end
do
	local top = ST.Masters[#ST.Masters]
	local hasSea, hasCrown = false, false
	for _, t in ipairs(top.tasks) do
		if ST.FamilyById[t.family].sea then hasSea = true end
		if t.family == "Crownbound" then hasCrown = true end
	end
	ok(hasSea and hasCrown, "the top master assigns sea creatures and endgame monsters")
end

-- Reachability and availability.
local function ctx(combat, slayer, levels, regions)
	local l = levels or {}
	l.Combat, l.Slayer = combat, slayer
	return {combat = combat, slayer = slayer, levels = l, regions = regions or {Hub = true, Meadow = true, Quarry = true}}
end
ok((ST.familyReachable("Thicketkin", ctx(1, 1))), "Thicketkin reachable in the Meadow")
local okR, why = ST.familyReachable("Galeborn", ctx(10, 9))
ok(not okR and has(why, "Slayer 10"), "Galeborn needs Slayer 10")
okR, why = ST.familyReachable("Galeborn", ctx(10, 10))
ok(not okR and has(why, "Windpine"), "Galeborn needs Windpine or Skyreach access")
ok((ST.familyReachable("Galeborn", ctx(10, 10, nil, {Windpine = true}))), "Galeborn via Windpine")
ok((ST.familyReachable("Galeborn", ctx(10, 10, nil, {Skyreach = true}))), "Galeborn via Skyreach")
ok((ST.familyReachable("Automatons", ctx(40, 20, nil, {Tempest = true}))), "Automatons via the Tempest only")
okR, why = ST.familyReachable("Deepwater", ctx(60, 50, {Fishing = 39}))
ok(not okR and has(why, "Fishing 40"), "Deepwater needs Fishing 40")
ok((ST.familyReachable("Deepwater", ctx(60, 50, {Fishing = 40}, {Tidewater = true}))), "Coralback in Tidewater at Fishing 40")
okR = ST.familyReachable("Deepwater", ctx(60, 50, {Fishing = 45}, {}))
ok(not okR, "Fishing 45 without Tidewater: no reachable water")
ok((ST.familyReachable("Deepwater", ctx(60, 50, {Fishing = 50}, {}))), "Stormcoil Serpents bite in any water at Fishing 50")
ok(not ST.familyReachable("Crownbound", ctx(99, 99, nil, {Tempest = true})), "Crownbound needs the Shattered Crown")
ok((ST.familyReachable("Crownbound", ctx(99, 70, nil, {ShatteredCrown = true}))), "Crownbound with Crown access")
ok(not ST.familyReachable("Nope", ctx(99, 99)), "unknown family")
ok(not ST.familyReachable("Thicketkin", nil), "nil context reaches nothing")
for _, m in ipairs(ST.Masters) do
	local a, r = ST.masterAvailable(m.id, ctx(m.combat - 1, 99))
	ok(not a and has(r, "Combat " .. m.combat), m.id .. " combat gate")
	ok((ST.masterAvailable(m.id, ctx(m.combat, m.slayer))), m.id .. " available at its gates")
	if m.slayer > 1 then
		a, r = ST.masterAvailable(m.id, ctx(99, m.slayer - 1))
		ok(not a and has(r, "Slayer " .. m.slayer), m.id .. " slayer gate")
	end
end
ok(not ST.masterAvailable("Nope", ctx(99, 99)), "unknown master")

-- Weighted assignment.
do
	local c = ctx(5, 1)
	local list, total = ST.candidates("Ysolde", c, {})
	eq(#list, 2, "Ysolde at Slayer 1 in the starting isles: two families")
	eq(total, 16, "weights 8 + 8")
	local t = ST.assign("Ysolde", c, {}, {}, 0.1, 0)
	eq(t.family, "Thicketkin", "low roll picks the first family")
	eq(t.amount, 15, "low amount roll gives the minimum")
	eq(t.killed, 0, "fresh task")
	eq(t.master, "Ysolde", "task names its master")
	ok(not t.extended, "not extended")
	t = ST.assign("Ysolde", c, {}, {}, 0.6, 0.9999999)
	eq(t.family, "Burrowers", "high roll picks the second family")
	eq(t.amount, 40, "high amount roll gives the maximum")
	t = ST.assign("Ysolde", c, {"Thicketkin"}, {}, 0.1, 0.5)
	eq(t.family, "Burrowers", "blocked family never assigned")
	t = ST.assign("Ysolde", c, {}, {}, 0.1, 0.5, "Thicketkin")
	eq(t.family, "Burrowers", "the family just finished is avoided")
	t = ST.assign("Ysolde", c, {"Burrowers"}, {}, 0.1, 0.5, "Thicketkin")
	eq(t.family, "Thicketkin", "avoidance yields when nothing else is left")
	local none, reason = ST.assign("Ysolde", c, {"Thicketkin", "Burrowers"}, {}, 0.1, 0.5)
	ok(none == nil and has(reason, "No task"), "everything blocked: no task")
	none, reason = ST.assign("Ysolde", ctx(2, 1), {}, {}, 0.1, 0.5)
	ok(none == nil and has(reason, "Combat 3"), "master gate refuses")
	-- Statistical weighting: frequency follows weight.
	local full = ctx(99, 99, {Fishing = 99}, {})
	for _, r in ipairs(Data.Regions) do full.regions[r.id] = true end
	for _, m in ipairs(ST.Masters) do
		local counts, n, sum = {}, 4000, 0
		for _, e in ipairs(m.tasks) do sum += e.weight end
		local seed = rand(m.index * 77)
		for _ = 1, n do
			local task = ST.assign(m.id, full, {}, {}, seed:NextNumber(), seed:NextNumber())
			counts[task.family] = (counts[task.family] or 0) + 1
			local e
			for _, x in ipairs(m.tasks) do if x.family == task.family then e = x end end
			ok(task.amount >= e.min and task.amount <= e.max, m.id .. " amount in range")
		end
		for _, e in ipairs(m.tasks) do
			local expected = e.weight / sum
			local got = (counts[e.family] or 0) / n
			ok(math.abs(got - expected) < 0.035, string.format("%s %s frequency %.3f ~ %.3f", m.id, e.family, got, expected))
		end
	end
	-- Extended tasks.
	local entry = ST.MasterById.Maelis.tasks[3]
	eq(entry.family, "Voidspawn", "Maelis Voidspawn entry")
	local lo, hi, ext = ST.amountRange(entry, {ExtendVoidspawn = true})
	ok(ext and lo == math.floor(entry.min * 1.5) and hi == math.floor(entry.max * 1.5), "extension multiplies the range")
	lo, hi, ext = ST.amountRange(entry, {})
	ok(not ext and lo == entry.min and hi == entry.max, "unextended range")
	lo, hi, ext = ST.amountRange(ST.MasterById.Ysolde.tasks[1], {ExtendThicketkin = true})
	ok(not ext, "families without an extension stay unextended")
end

-- Streaks, points and XP.
eq(ST.streakMult(1), 1, "task 1 x1")
eq(ST.streakMult(9), 1, "task 9 x1")
eq(ST.streakMult(10), 5, "every 10th x5")
eq(ST.streakMult(20), 5, "20th x5")
eq(ST.streakMult(50), 15, "every 50th x15")
eq(ST.streakMult(100), 25, "every 100th x25")
eq(ST.streakMult(150), 15, "150th x15")
eq(ST.streakMult(250), 35, "every 250th x35")
eq(ST.streakMult(1000), 50, "every 1000th x50")
eq(ST.streakMult(0), 1, "no streak x1")
eq(ST.streakMult(-3), 1, "negative streak x1")
eq(ST.streakMult("x"), 1, "garbage streak x1")
for n = 1, 120 do
	local m = ST.streakMult(n)
	local expected = if n % 100 == 0 then 25 elseif n % 50 == 0 then 15 elseif n % 10 == 0 then 5 else 1
	eq(m, expected, "streak " .. n)
end
eq(ST.pointsFor("Vesper", 10), 75, "Vesper 10th task 15 x5")
eq(ST.pointsFor("Ysolde", 3), 2, "Ysolde base points")
eq(ST.pointsFor("Nope", 3), 0, "unknown master pays nothing")
eq(ST.bountyFor("Corvane", {}), 600, "bounty")
eq(ST.bountyFor("Corvane", {GildedBounty = true}), 1200, "gilded bounty doubles")
eq(ST.killXp(Data.Monsters.Thornling), 9, "Thornling 220 hp -> 9 Slayer XP")
eq(ST.killXp(Data.Monsters.GloomfangSpider), 160, "Gloomfang 4000 hp -> 160")
eq(ST.killXp({hp = 1}), 1, "at least 1 XP")
eq(ST.killXp(nil), 0, "no definition, no XP")
eq(ST.bossXp("Bramble", 1), 30, "Bramble I 1500 hp -> 30 Slayer XP")
eq(ST.bossXp("Tempest", 4), 30000, "Tempest IV -> 30000")
eq(ST.bossXp("Nope", 1), 0, "unknown line")
for id, m in pairs(Data.Monsters) do
	local xp = ST.killXp(m)
	ok(xp >= 1 and xp <= m.xp * 2.5, id .. " task XP close to its Combat XP")
end

-- Shop.
local kinds = {}
for i, e in ipairs(ST.Shop) do
	eq(ST.ShopById[e.id], e, e.id .. " indexed")
	ok(#e.name > 0 and #e.text > 0 and e.cost >= 0, e.id .. " values")
	kinds[e.kind] = (kinds[e.kind] or 0) + 1
	for id in pairs(e.gives or {}) do ok(Data.Items[id] ~= nil, e.id .. " gives " .. id) end
	for id in pairs(e.costs or {}) do ok(Data.Items[id] ~= nil, e.id .. " costs " .. id) end
	if e.kind == "extend" then ok(ST.FamilyById[e.family] and e.id == "Extend" .. e.family, e.id .. " names its family") end
end
ok(kinds.unlock >= 4 and kinds.extend >= 5 and kinds.consumable >= 2 and kinds.title >= 1 and kinds.craft >= 2, "unlocks, extensions, consumables, titles and crafts")
local base = {points = 1000, unlocks = {}, levels = {Slayer = 99}, items = {}}
ok((ST.canBuy("SuperiorCalling", base)), "unlock affordable")
local bought, reason = ST.canBuy("SuperiorCalling", {points = 149, unlocks = {}, levels = {}, items = {}})
ok(not bought and has(reason, "150"), "too few points")
bought, reason = ST.canBuy("SuperiorCalling", {points = 999, unlocks = {SuperiorCalling = true}})
ok(not bought and has(reason, "already"), "one-time unlock")
ok((ST.canBuy("BuySlayersBrew", {points = 35, unlocks = {BuySlayersBrew = true}})), "consumables repeat")
bought, reason = ST.canBuy("CraftHuntersVisor", base)
ok(not bought and has(reason, "Visorwright"), "visor needs the lore")
bought, reason = ST.canBuy("CraftHuntersVisor", {points = 0, unlocks = {VisorCrafting = true}, levels = {Slayer = 39}, items = {}})
ok(not bought and has(reason, "Slayer 40"), "visor needs Slayer 40")
bought, reason = ST.canBuy("CraftHuntersVisor", {points = 0, unlocks = {VisorCrafting = true}, levels = {Slayer = 40}, items = {SlayerToken = 10, HushcapSpore = 19, BeastHide = 40}})
ok(not bought and has(reason, "Hushcap"), "visor needs every material")
ok((ST.canBuy("CraftHuntersVisor", {points = 0, unlocks = {VisorCrafting = true}, levels = {Slayer = 40}, items = {SlayerToken = 10, HushcapSpore = 20, BeastHide = 40}})), "visor assembles")
bought, reason = ST.canBuy("TitleNightstalker", {points = 999, unlocks = {}, levels = {Slayer = 59}})
ok(not bought and has(reason, "Slayer 60"), "title level gate")
ok(not ST.canBuy("Nope", base), "unknown entry")
ok(not ST.canBuy(nil, base), "nil entry")
eq(ST.blockSlots({}), 3, "three block slots")
eq(ST.blockSlots({WiderLedger = true}), 5, "Wider Ledger: five")
eq(ST.blockSlots(nil), 3, "nil unlocks")

-- Gear.
do
	local visor, radiant = Data.Items.HuntersVisor, Data.Items.RadiantHuntersVisor
	ok(visor.kind == "armor" and visor.slot == "helmet" and visor.requires.Slayer == 40, "Hunter's Visor is Slayer 40 headgear")
	ok(radiant.slot == "helmet" and radiant.requires.Slayer == 75, "Radiant visor Slayer 75")
	local v = ST.visorBonus("HuntersVisor")
	ok(v.damage == 15 and v.accuracy == 15, "visor +15/+15")
	v = ST.visorBonus("RadiantHuntersVisor")
	ok(v.damage > 15 and v.accuracy > 15, "radiant visor stronger")
	eq(ST.visorBonus("Skyplate"), nil, "ordinary armour gives no bonus")
	eq(ST.visorBonus(nil), nil, "no helmet")
	ok(Data.Items.SlayersBrew.buff and Data.Items.SlayersBrew.buff.duration == 600, "Slayer's Brew buff")
	ok(P.meetsRequirements({xp = {Slayer = X[40]}}, visor.requires) and not P.meetsRequirements({xp = {Slayer = X[39]}}, visor.requires), "Slayer requirement uses the skill level")
end

-- Superiors.
do
	local n = 0
	for _, f in ipairs(ST.Families) do
		for _, baseId in ipairs(f.monsters) do
			local id = ST.SuperiorOf[baseId]
			if f.sea then eq(id, nil, baseId .. " (sea) has no superior")
			else
				n += 1
				local def, baseDef = ST.Superiors[id], Data.Monsters[baseId]
				eq(Data.Monsters[id], def, id .. " resolves through Data.Monsters")
				eq(rawget(Data.Monsters, id), nil, id .. " is not iterated")
				ok(def.superior and def.base == baseId and def.family == f.id, id .. " links back")
				eq(def.hp, baseDef.hp * ST.SUPERIOR_HP, id .. " 8x health")
				ok(def.damage > baseDef.damage and def.level > baseDef.level, id .. " hits harder")
				ok(has(def.name, baseDef.name) and has(def.name, f.epithet), id .. " name")
				eq(def.slayerLevel, baseDef.slayerLevel, id .. " inherits the slayer gate")
				local ichor, sigil = false, false
				for _, d in ipairs(def.drops) do
					ok(Data.Items[d.item] ~= nil and d.chance > 0 and d.chance <= 1, id .. " drop " .. d.item)
					if d.item == "EclipsedIchor" and d.chance == 1 then ichor = true end
					if d.item == "DuskhunterSigil" then sigil = true end
				end
				ok(ichor and sigil, id .. " unique table")
				ok(ST.killXp(def) == ST.killXp(baseDef) * 8 or math.abs(ST.killXp(def) - ST.killXp(baseDef) * 8) <= 8, id .. " pays ~8x Slayer XP")
			end
		end
	end
	eq(#ST.SuperiorOrder, n, "every land monster has a superior")
	-- Seas, world bosses still resolve.
	ok(Data.Monsters.ShellsnapCrab and Data.Monsters.Aurelith, "sea creatures and world bosses still resolve")
	eq(Data.Monsters.NopeMonster, nil, "unknown id resolves to nil")
	-- Chance.
	eq(ST.rollSuperior(false, "Thornling", function() return 0 end), nil, "locked: never")
	eq(ST.rollSuperior(true, "Thornling", function() return 0 end), "SuperiorThornling", "a low roll raises it")
	eq(ST.rollSuperior(true, "Thornling", function() return 1 / 150 end), nil, "1/150 is the edge")
	eq(ST.rollSuperior(true, "ShellsnapCrab", function() return 0 end), nil, "sea creatures have none")
	eq(ST.rollSuperior(true, "Thornling", nil), nil, "no roll function")
	local rng, hits, trials = rand(5), 0, 300000
	for _ = 1, trials do if ST.rollSuperior(true, "Thornling", function() return rng:NextNumber() end) then hits += 1 end end
	ok(math.abs(hits / trials - 1 / 150) < 0.0012, string.format("superior rate %.5f ~ 1/150", hits / trials))
end

-- Townsfolk.
do
	local T = Data.Townsfolk
	for _, m in ipairs(ST.Masters) do
		local npc = T.NPCs[m.npc]
		ok(npc ~= nil and table.find(T.Order, m.npc) ~= nil, m.id .. " stands in the isles")
		eq(T.Verbs.slayerTask.item[m.id], true, m.id .. " whitelisted for slayerTask")
		local found = false
		for _, o in ipairs(npc.nodes.hello.options) do if o.verb == "slayerTask" and o.item == m.id then found = true end end
		ok(found, m.id .. " offers a task in dialogue")
		if m.npc ~= "Slayer" then eq(npc.name, m.name, m.id .. " name") eq(npc.region, m.region, m.id .. " region") end
	end
	ok(T.Conditions.taskIdle({slayerTasks = {}}) and not T.Conditions.taskIdle({slayerTasks = {task = {}}}) and not T.Conditions.taskIdle({}), "taskIdle condition")
	ok(has(T.Tips.slayerTask({slayerTasks = {task = {family = "Thicketkin", killed = 3, amount = 20}, streak = 4, points = 8}}), "Thicketkin 3 / 20"), "task tip")
	ok(has(T.Tips.slayerTask({}), "master"), "tip without state")
end
print("PASS: " .. (checks - partA) .. " Slayer data/rule assertions.")

------------------------------------------------------------------------------
-- Part B: server behaviour.
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
	HttpService = {GenerateGUID = function() return "slayer-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end}, Vector3 = Vector3, CFrame = CFrame,
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
			assert(coroutine.resume(co, ...))
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
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
local remote, bridge
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
end
ok(remote ~= nil and bridge ~= nil, "IsleAction and IsleBridge found")
local function cmd(p, verb, item)
	advance(1)
	return remote.OnServerInvoke(p, verb, item)
end
local function kill(p, id) advance(0.1) return bridge.OnInvoke("kill", p, {monster = id}) end

-- Fresh journal.
local rookie = player(9001)
local s0 = cmd(rookie, "state")
ok(type(s0.slayerTasks) == "table", "snapshot carries slayerTasks")
eq(s0.xp.Slayer, 0, "fresh Slayer XP")
eq(s0.slayerTasks.points, 0, "no points")
eq(s0.slayerTasks.streak, 0, "no streak")
eq(s0.slayerTasks.task, nil, "no task")
eq(s0.slayerTasks.blockSlots, 3, "three block slots")
eq(#s0.slayerTasks.blocked, 0, "nothing blocked")
eq(s0.slayerTasks.level, 1, "Slayer 1")
eq(s0.slayerTasks.nextMult, 1, "next task x1")
ok(s0.slayerTasks.masters.Ysolde.ok == false and has(s0.slayerTasks.masters.Ysolde.reason, "Combat 3"), "Ysolde needs Combat 3")
ok(s0.slayerTasks.families.Thicketkin.ok and not s0.slayerTasks.families.Gloomweavers.ok, "family reach in the snapshot")
eq(rookie.attrs.SlayerTask, "", "SlayerTask attribute empty")
eq(rookie.attrs.SlayerLevel, 1, "SlayerLevel attribute")
ok(has(cmd(rookie, "slayerTask", "Ysolde").message, "Combat 3"), "combat gate on the server")
ok(has(cmd(rookie, "slayerTask", "Nope").message, "Choose a Slayer master"), "unknown master")
ok(has(cmd(rookie, "slayerTask", nil).message, "Choose a Slayer master"), "nil master")
ok(has(cmd(rookie, "slayerSkip").message, "no task"), "nothing to skip")
ok(has(cmd(rookie, "slayerCancel").message, "no task"), "nothing to cancel")

-- A Combat 5 journal takes a task.
local hunter = seeded(9002, function(p) p.xp.Combat = X[5] end)
queue(0.1, 0)
local s1 = cmd(hunter, "slayerTask", "Ysolde")
ok(has(s1.message, "slay 15 Thicketkin"), "Ysolde assigns 15 Thicketkin (" .. s1.message .. ")")
eq(s1.slayerTasks.task.family, "Thicketkin", "task family")
eq(s1.slayerTasks.task.amount, 15, "task amount")
eq(hunter.attrs.SlayerTask, "Thicketkin:0:15", "task attribute")
ok(has(cmd(hunter, "slayerTask", "Ysolde").message, "already have a task"), "one task at a time")
-- Credit: only the assigned family.
local before = copy(cmd(hunter, "state"))
local r1 = kill(hunter, "ShaleCrawler")
ok(r1 ~= nil and r1.superior == nil, "off-task kill pays normally")
local afterOff = cmd(hunter, "state")
eq(afterOff.slayerTasks.task.killed, 0, "off-task kills do not count")
eq(afterOff.xp.Slayer, before.xp.Slayer, "off-task kills pay no Slayer XP")
kill(hunter, "Thornling")
local afterOn = cmd(hunter, "state")
eq(afterOn.slayerTasks.task.killed, 1, "task kill counts")
eq(afterOn.xp.Slayer, 9, "task kill pays Slayer XP")
eq(hunter.attrs.SlayerTask, "Thicketkin:1:15", "attribute tracks progress")
kill(hunter, "BramblebackBoar")
kill(hunter, "BarkStalker")
local s2 = cmd(hunter, "state")
eq(s2.slayerTasks.task.killed, 3, "every family member counts")
eq(s2.xp.Slayer, 9 + ST.killXp(Data.Monsters.BramblebackBoar) + ST.killXp(Data.Monsters.BarkStalker), "XP per monster health")
-- Unknown, sea creature, world boss and superior ids never credit via "kill".
eq(kill(hunter, "Nope"), nil, "unknown monster refused")
eq(kill(hunter, "ShellsnapCrab"), nil, "sea creature refused on kill")
eq(kill(hunter, "SuperiorThornling"), nil, "superior refused on kill")
eq(kill(hunter, "Aurelith"), nil, "world boss refused on kill")
eq(cmd(hunter, "state").slayerTasks.task.killed, 3, "refused kills credit nothing")
-- Finish the task.
for _ = 4, 14 do kill(hunter, "Thornling") end
local coinsBefore = cmd(hunter, "state").coins
kill(hunter, "Thornling")
local done = cmd(hunter, "state")
eq(done.slayerTasks.task, nil, "task complete clears it")
eq(done.slayerTasks.streak, 1, "streak 1")
eq(done.slayerTasks.completed, 1, "one completed")
eq(done.slayerTasks.points, 2, "Ysolde pays 2 points")
eq(done.coins - coinsBefore, Data.Monsters.Thornling.coins + 150, "kill coins + 150 bounty")
eq(hunter.attrs.SlayerTask, "", "attribute cleared")
ok(has(hunter.last.message, "Slayer task complete"), "completion notice")
-- The next task avoids the family just finished.
queue(0.1, 0)
eq(cmd(hunter, "slayerTask", "Ysolde").slayerTasks.task.family, "Burrowers", "just-finished family avoided")
-- Cancel resets the streak.
local cancelled = cmd(hunter, "slayerCancel")
ok(has(cancelled.message, "streak of 1 is broken"), "cancel notice")
eq(cancelled.slayerTasks.streak, 0, "streak reset")
eq(cancelled.slayerTasks.points, 2, "points kept")

-- Streak multipliers on completion.
local streaker = seeded(9003, function(p)
	p.xp.Combat = X[5]
	p.slayerTasks = {task = {master = "Ysolde", family = "Burrowers", amount = 20, killed = 19}, streak = 9, completed = 9, points = 0}
end)
kill(streaker, "CinderMite")
local st10 = cmd(streaker, "state").slayerTasks
eq(st10.streak, 10, "10th task")
eq(st10.points, 10, "10th task pays x5")
ok(has(streaker.last.message, "x5"), "streak notice")
streaker = rejoin(streaker, function(p) p.slayerTasks.task = {master = "Ysolde", family = "Burrowers", amount = 20, killed = 19}; p.slayerTasks.streak = 49 end)
kill(streaker, "CinderMite")
eq(cmd(streaker, "state").slayerTasks.points, 10 + 30, "50th task pays x15")
streaker = rejoin(streaker, function(p) p.slayerTasks.task = {master = "Ysolde", family = "Burrowers", amount = 20, killed = 19}; p.slayerTasks.streak = 99 end)
kill(streaker, "CinderMite")
local st100 = cmd(streaker, "state").slayerTasks
eq(st100.points, 40 + 50, "100th task pays x25")
eq(st100.completed, 12, "completed count")
eq(st100.nextMult, 1, "101st x1")

-- Skip, block, unblock.
local blocker = seeded(9004, function(p)
	p.xp.Combat = X[5]
	p.slayerTasks = {task = {master = "Ysolde", family = "Thicketkin", amount = 20, killed = 5}, streak = 7, points = 29}
end)
ok(has(cmd(blocker, "slayerSkip").message, "30 Slayer points"), "skip needs points")
blocker = rejoin(blocker, function(p) p.slayerTasks.points = 380 end)
queue(0.9, 0)
local skipped = cmd(blocker, "slayerSkip")
ok(has(skipped.message, "Task skipped"), "skip notice")
eq(skipped.slayerTasks.points, 350, "skip costs 30")
eq(skipped.slayerTasks.streak, 7, "skip keeps the streak")
eq(skipped.slayerTasks.task.family, "Burrowers", "skip assigns a new task")
eq(skipped.slayerTasks.task.killed, 0, "new task starts fresh")
local blocked = cmd(blocker, "slayerBlock", "Burrowers")
ok(has(blocked.message, "Burrowers blocked") and has(blocked.message, "dropped"), "blocking the current task drops it")
eq(blocked.slayerTasks.points, 250, "block costs 100")
eq(blocked.slayerTasks.task, nil, "current task dropped")
eq(blocked.slayerTasks.streak, 7, "block keeps the streak")
eq(blocked.slayerTasks.blocked[1], "Burrowers", "block list")
ok(has(cmd(blocker, "slayerBlock", "Burrowers").message, "already blocked"), "no double block")
ok(has(cmd(blocker, "slayerBlock", "Nope").message, "Choose"), "unknown family")
for _, roll in ipairs({0.01, 0.5, 0.99}) do
	queue(roll, 0.5)
	eq(cmd(blocker, "slayerTask", "Ysolde").slayerTasks.task.family, "Thicketkin", "blocked family never assigned (roll " .. roll .. ")")
	cmd(blocker, "slayerCancel")
end
cmd(blocker, "slayerBlock", "Galeborn")
local three = cmd(blocker, "slayerBlock", "Reefstalkers")
eq(#three.slayerTasks.blocked, 3, "three blocks")
eq(three.slayerTasks.points, 50, "three blocks paid")
blocker = rejoin(blocker, function(p) p.slayerTasks.points = 500 end)
ok(has(cmd(blocker, "slayerBlock", "Automatons").message, "block slot is full"), "slots full")
local unb = cmd(blocker, "slayerUnblock", "Galeborn")
ok(has(unb.message, "Galeborn unblocked"), "unblock")
eq(#unb.slayerTasks.blocked, 2, "slot freed")
eq(unb.slayerTasks.points, 500, "no refund, no cost")
ok(has(cmd(blocker, "slayerUnblock", "Galeborn").message, "not blocked"), "unblock twice")
ok(has(cmd(blocker, "slayerUnblock", nil).message, "not blocked"), "unblock nil")
queue(0.01, 0.5)
eq(cmd(blocker, "slayerTask", "Ysolde").slayerTasks.task.family, "Thicketkin", "Thicketkin left")
cmd(blocker, "slayerCancel")
cmd(blocker, "slayerBlock", "Thicketkin")
ok(has(cmd(blocker, "slayerTask", "Ysolde").message, "No task you can reach"), "everything blocked: no task")
cmd(blocker, "slayerBuy", "WiderLedger")
local wide = cmd(blocker, "state").slayerTasks
eq(wide.blockSlots, 5, "Wider Ledger: five slots")
eq(wide.points, 200, "Wider Ledger costs 200 (500 - 100 block - 200)")

-- Region reach on the server: Corvane at Combat 20 with nothing else unlocked.
local wanderer = seeded(9005, function(p) p.xp.Combat = X[20]; p.xp.Slayer = X[50] end)
for _, roll in ipairs({0.01, 0.3, 0.6, 0.99}) do
	queue(roll, 0.5)
	local s = cmd(wanderer, "slayerTask", "Corvane")
	eq(s.slayerTasks.task.family, "Thicketkin", "only reachable families (roll " .. roll .. ")")
	cmd(wanderer, "slayerCancel")
end
wanderer = rejoin(wanderer, function(p) p.xp.Woodcutting = X[10] end)
local seen = {}
for i = 1, 12 do
	queue((i - 0.5) / 12, 0.5)
	local s = cmd(wanderer, "slayerTask", "Corvane")
	seen[s.slayerTasks.task.family] = true
	cmd(wanderer, "slayerCancel")
end
ok(seen.Galeborn and seen.Thicketkin and not seen.Gloomweavers and not seen.Stormwraiths, "Windpine access adds Galeborn only")
ok(has(cmd(wanderer, "slayerTask", "Maelis").message, "Combat 45"), "Maelis combat gate")
wanderer = rejoin(wanderer, function(p) p.xp.Combat = X[45]; p.xp.Slayer = X[10] end)
ok(has(cmd(wanderer, "slayerTask", "Maelis").message, "Slayer 20"), "Maelis slayer gate")

-- Shop on the server.
local shopper = seeded(9006, function(p)
	p.xp.Combat = X[50]; p.xp.Slayer = X[45]
	p.slayerTasks = {points = 700}
	p.items.SlayerToken, p.items.HushcapSpore, p.items.BeastHide = 12, 25, 50
end)
ok(has(cmd(shopper, "slayerBuy", "CraftHuntersVisor").message, "Visorwright"), "visor locked without the lore")
local lore = cmd(shopper, "slayerBuy", "VisorCrafting")
ok(has(lore.message, "Unlocked Visorwright"), "lore unlocked")
eq(lore.slayerTasks.points, 620, "lore costs 80")
ok(table.find(lore.slayerTasks.unlocks, "VisorCrafting") ~= nil, "unlock listed")
ok(has(cmd(shopper, "slayerBuy", "VisorCrafting").message, "already yours"), "no double unlock")
local visor = cmd(shopper, "slayerBuy", "CraftHuntersVisor")
ok(has(visor.message, "Assembled: Hunter's Visor"), "visor assembled")
eq(visor.items.HuntersVisor, 1, "visor in the satchel")
eq(visor.items.SlayerToken, 2, "tokens spent")
eq(visor.items.HushcapSpore, 5, "spores spent")
eq(visor.items.BeastHide, 10, "hides spent")
eq(visor.slayerTasks.points, 620, "crafts cost no points")
ok(has(cmd(shopper, "slayerBuy", "CraftHuntersVisor").message, "needs"), "materials gone")
cmd(shopper, "equip", "HuntersVisor")
local view = bridge.OnInvoke("stats", shopper).slayer
ok(view ~= nil and view.level == 45 and view.family == nil, "bridge stats carries the Slayer level")
ok(view.visor and view.visor.damage == 15 and view.visor.accuracy == 15, "bridge stats carries the visor")
local brew = cmd(shopper, "slayerBuy", "BuySlayersBrew")
eq(brew.items.SlayersBrew, 1, "brew bought")
eq(brew.slayerTasks.points, 585, "brew costs 35")
eq(cmd(shopper, "slayerBuy", "BuySlayersBrew").items.SlayersBrew, 2, "consumables repeat")
local drank = cmd(shopper, "consume", "SlayersBrew")
ok(drank.depth and drank.depth.buffs and drank.depth.buffs.SlayersBrew ~= nil, "the brew is a working buff")
local titled = cmd(shopper, "slayerBuy", "TitleGravewarden")
eq(shopper.attrs.SlayerTitle, "Gravewarden", "title attribute")
eq(titled.slayerTasks.title, "TitleGravewarden", "title worn")
cmd(shopper, "slayerTitle", "none")
eq(shopper.attrs.SlayerTitle, "", "title hidden")
cmd(shopper, "slayerTitle", "TitleGravewarden")
eq(shopper.attrs.SlayerTitle, "Gravewarden", "title worn again")
ok(has(cmd(shopper, "slayerTitle", "TitleNightstalker").message, "not earned"), "unowned title refused")
ok(has(cmd(shopper, "slayerBuy", "TitleNightstalker").message, "Slayer 60"), "title level gate")
ok(has(cmd(shopper, "slayerBuy", "Nope").message, "Choose"), "unknown shop entry")
ok(has(cmd(shopper, "slayerBuy", "SuperiorCalling").message, "150"), "too few points left")

-- Superiors.
local caller = seeded(9007, function(p)
	p.xp.Combat = X[30]; p.xp.Slayer = X[30]
	p.slayerTasks = {task = {master = "Ysolde", family = "Thicketkin", amount = 30, killed = 0}, points = 0}
end)
defaultRoll = 0
local locked = kill(caller, "BarkStalker")
defaultRoll = 0.999
eq(locked.superior, nil, "no superiors before Call of the Superior")
caller = rejoin(caller, function(p) p.slayerTasks.unlocks = {SuperiorCalling = true} end)
local plain = kill(caller, "BarkStalker")
eq(plain.superior, nil, "a high roll raises nothing")
defaultRoll = 0
local off = kill(caller, "ShaleCrawler")
local rise = kill(caller, "BarkStalker")
defaultRoll = 0.999
eq(off.superior, nil, "off-task kills never raise superiors")
ok(rise.superior ~= nil and rise.superior.id == "SuperiorBarkStalker" and rise.superior.seq == 1, "a task kill raises the superior")
ok(has(caller.last.message, "Thornsworn Bark Stalker emerges"), "superior notice")
local beforeSup = copy(cmd(caller, "state")) -- snapshots share live tables
eq(beforeSup.slayerTasks.superiorsLive, 1, "one live ticket")
local wrong = bridge.OnInvoke("slayerSuperior", caller, {seq = 2, monster = "SuperiorBarkStalker", result = "kill"})
eq(wrong.reason, "ticket", "unknown seq refused")
wrong = bridge.OnInvoke("slayerSuperior", caller, {seq = 1, monster = "SuperiorThornling", result = "kill"})
eq(wrong.reason, "ticket", "wrong monster refused")
wrong = bridge.OnInvoke("slayerSuperior", caller, {seq = 1.5, monster = "SuperiorBarkStalker", result = "kill"})
eq(wrong.reason, "invalid", "fractional seq invalid")
wrong = bridge.OnInvoke("slayerSuperior", caller, {seq = 1, monster = "SuperiorBarkStalker", result = "win"})
eq(wrong.reason, "invalid", "bad result invalid")
local other = seeded(9008, function(p) p.xp.Combat = X[30] end)
eq(bridge.OnInvoke("slayerSuperior", other, {seq = 1, monster = "SuperiorBarkStalker", result = "kill"}).reason, "ticket", "only the owner's ticket settles")
local paid = bridge.OnInvoke("slayerSuperior", caller, {seq = 1, monster = "SuperiorBarkStalker", result = "kill"})
ok(paid.ok == true, "owner's superior kill settles")
ok((paid.drops.EclipsedIchor or 0) >= 1 and (paid.drops.SlayerToken or 0) >= 1, "guaranteed unique loot")
ok(has(caller.last.message, "Thornsworn Bark Stalker slain"), "superior kill notice")
local afterSup = cmd(caller, "state")
eq(afterSup.xp.Slayer - beforeSup.xp.Slayer, ST.killXp(ST.Superiors.SuperiorBarkStalker), "superior Slayer XP")
ok(afterSup.coins - beforeSup.coins >= ST.Superiors.SuperiorBarkStalker.coins, "superior coins (plus any collection tier rewards)")
eq(afterSup.slayerTasks.superiors.SuperiorBarkStalker, 1, "superior log")
eq(afterSup.slayerTasks.task.killed, beforeSup.slayerTasks.task.killed + 1, "superior counts toward the task")
eq(afterSup.slayerTasks.superiorsLive, 0, "ticket settled")
eq(bridge.OnInvoke("slayerSuperior", caller, {seq = 1, monster = "SuperiorBarkStalker", result = "kill"}).reason, "ticket", "settles once")
-- Live cap and despawns.
defaultRoll = 0
local a = kill(caller, "Thornling")
local b = kill(caller, "BramblebackBoar")
local c3 = kill(caller, "Thornling")
defaultRoll = 0.999
ok(a.superior and b.superior and c3.superior == nil, "at most two live superiors")
eq(b.superior.id, "SuperiorBramblebackBoar", "each superior matches its base")
local gone = bridge.OnInvoke("slayerSuperior", caller, {seq = a.superior.seq, monster = a.superior.id, result = "despawn"})
ok(gone.ok == true, "a despawn frees the ticket")
eq(cmd(caller, "state").slayerTasks.superiors.SuperiorThornling, nil, "despawns are not logged")
-- Expiry.
clock += ST.SUPERIOR_LIFETIME + 30 -- os.clock only: the journal lease (os.time) stays valid
eq(bridge.OnInvoke("slayerSuperior", caller, {seq = b.superior.seq, monster = b.superior.id, result = "kill"}).reason, "expired", "expired tickets pay nothing")
-- Tickets are session-only.
defaultRoll = 0
local d = kill(caller, "Thornling")
defaultRoll = 0.999
caller = rejoin(caller)
eq(bridge.OnInvoke("slayerSuperior", caller, {seq = d.superior.seq, monster = d.superior.id, result = "kill"}).reason, "ticket", "rejoining forgets tickets")
-- Slayer damage refusal notice.
local weak = seeded(9009, function(p) p.xp.Combat = X[50] end)
weak.last = nil
eq(bridge.OnInvoke("slayerDenied", weak, {monster = "HollowcapShrieker"}), nil, "denied op returns nothing")
ok(weak.last and has(weak.last.message, "Slayer 40"), "player told the Slayer level")
weak.last = nil
bridge.OnInvoke("slayerDenied", weak, {monster = "HollowcapShrieker"})
eq(weak.last, nil, "rate-limited")
advance(4)
bridge.OnInvoke("slayerDenied", weak, {monster = "Thornling"})
eq(weak.last, nil, "ungated monsters say nothing")

-- Boss lines train the Slayer skill too.
local bossHunter = seeded(9010, function(p)
	p.xp.Combat = X[10]
	p.slayerQuest = {line = "Bramble", tier = 1, progress = 150, needed = 150, bossReady = true}
end)
local xpBefore = cmd(bossHunter, "state").xp.Slayer
local win = bridge.OnInvoke("slayerBoss", bossHunter, {result = "win"})
ok(win.ok, "boss win settles")
local afterBoss = cmd(bossHunter, "state")
eq(afterBoss.xp.Slayer - xpBefore, ST.bossXp("Bramble", 1), "boss pays Slayer skill XP")
eq(afterBoss.depth.slayer.lines.Bramble.xp, Data.Slayers.Bramble.tiers[1].xp, "line rank XP unchanged")

-- Persistence and migration.
local keeper = seeded(9011, function(p)
	p.xp.Combat = X[5]
	p.slayerTasks = {task = {master = "Ysolde", family = "Burrowers", amount = 20, killed = 4, extended = false}, streak = 3, completed = 8, points = 77,
		blocked = {"Galeborn"}, unlocks = {SuperiorCalling = true}, superiors = {SuperiorThornling = 2}, title = ""}
end)
kill(keeper, "CinderMite")
keeper = rejoin(keeper)
local kept = cmd(keeper, "state").slayerTasks
eq(kept.task.killed, 5, "progress persisted")
eq(kept.points, 77, "points persisted")
eq(kept.streak, 3, "streak persisted")
eq(kept.completed, 8, "completed persisted")
eq(kept.blocked[1], "Galeborn", "blocks persisted")
eq(kept.superiors.SuperiorThornling, 2, "superior log persisted")
ok(table.find(kept.unlocks, "SuperiorCalling") ~= nil, "unlocks persisted")
eq(keeper.attrs.SlayerTask, "Burrowers:5:20", "attribute restored on load")
eq(data["p9011"].profile.slayerTasks.task.killed, 5, "the DataStore record holds the progress")
local garbage = seeded(9012, function(p)
	p.slayerTasks = {task = {master = "Nope", family = "Thicketkin", amount = 10, killed = 2}, points = -5, streak = "x", completed = 1e99,
		blocked = {"Thicketkin", "Fake", "Thicketkin", "Burrowers", "Galeborn", "Voidspawn"}, unlocks = {SuperiorCalling = true, Fake = true, BuySlayersBrew = true, WiderLedger = "yes"},
		superiors = {SuperiorThornling = 3, Fake = 2, SuperiorBarkStalker = -1}, title = "TitleGravewarden", last = "Nope"}
end)
local g = cmd(garbage, "state").slayerTasks
eq(g.task, nil, "unknown master drops the task")
eq(g.points, 0, "negative points clamp")
eq(g.streak, 0, "garbage streak")
eq(#g.blocked, 3, "blocks deduplicated, unknown dropped, capped to slots")
eq(table.concat(g.blocked, ","), "Thicketkin,Burrowers,Galeborn", "blocks kept in order")
eq(#g.unlocks, 1, "only real one-time unlocks kept")
eq(g.unlocks[1], "SuperiorCalling", "SuperiorCalling kept")
eq(g.superiors.SuperiorThornling, 3, "valid superior log kept")
eq(g.superiors.Fake, nil, "unknown superior dropped")
eq(g.superiors.SuperiorBarkStalker, nil, "non-positive log dropped")
eq(g.title, "", "unowned title dropped")
local overrun = seeded(9013, function(p)
	p.slayerTasks = {task = {master = "Ysolde", family = "Thicketkin", amount = 10, killed = 10}}
end)
eq(cmd(overrun, "state").slayerTasks.task, nil, "a finished task is not restored")
local huge = seeded(9014, function(p)
	p.slayerTasks = {task = {master = "Ysolde", family = "Thicketkin", amount = 1e9, killed = 0}, blocked = {"Thicketkin"}}
end)
eq(cmd(huge, "state").slayerTasks.task, nil, "a task of a blocked family is dropped")
local legacy = seeded(9015, function(p) p.slayerTasks = nil; p.xp.Slayer = nil end)
local l = cmd(legacy, "state")
eq(l.xp.Slayer, 0, "old saves gain Slayer XP")
ok(type(l.slayerTasks) == "table" and l.slayerTasks.points == 0, "old saves gain a ledger")
local junk = seeded(9016, function(p) p.slayerTasks = "junk" end)
eq(cmd(junk, "state").slayerTasks.streak, 0, "non-table ledger replaced")
-- Hooks are in place.
do
	local server = fs.readFile("server.server.lua")
	ok(has(server, "SlayerTasks.onKill(player,p,monsterId,monster)"), "kill hook")
	ok(has(server, "SlayerTasks.onKill(player,p,id,monster,true)"), "sea creature hook")
	ok(has(server, 'grantXp(p,"Slayer",skillXp)'), "boss-line hook")
	for verb in pairs({slayerTask = 1, slayerSkip = 1, slayerCancel = 1, slayerBlock = 1, slayerUnblock = 1, slayerBuy = 1, slayerTitle = 1}) do
		ok(has(server, 'verb=="' .. verb .. '"'), "server verb " .. verb)
	end
end
print("PASS: " .. (checks - partB) .. " Slayer server assertions.")

------------------------------------------------------------------------------
-- Part C: combat (pure core).
------------------------------------------------------------------------------
local partC = checks
local Combat
load("combat.server.lua", {
	Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3,
	__CombatTestHarness = function(exports) Combat = exports end,
})
ok(Combat ~= nil, "combat harness")
local function arena(slayer)
	local w = {clock = 100, list = {}, calls = {}, stats = {}, pos = {}, rolls = {}, alive = {}}
	local function hero(name, uid, s)
		local h = {Name = name, UserId = uid}
		table.insert(w.list, h)
		w.pos[h] = Vector3.new(0, 0, 0)
		w.alive[h] = true
		w.stats[h] = {stats = {damage = 40, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0, intelligence = 100, rangedAccuracy = 0, rangedStrength = 0},
			combatLevel = 5, slayer = s, loadout = {style = "melee", levels = {}, supplies = {}}}
		return h
	end
	w.hero = hero("Hero", 1, slayer)
	w.rival = hero("Rival", 2, {level = 99})
	w.logic = Combat.createLogic({
		Data = Data, Progression = P,
		now = function() return w.clock end, time = function() return 5000 end,
		rng = function() if #w.rolls > 0 then return table.remove(w.rolls, 1) end return 0.5 end,
		players = function() return w.list end, alive = function(p) return w.alive[p] == true end,
		position = function(p) return w.pos[p] end, heal = function() end,
		bridge = function(op, player, payload, done)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			if op == "kill" and done then done(w.killReply) end
			return nil
		end,
	})
	return w
end
local function spawn(L, id, key)
	local marker = L.addMarker(key or ("m" .. id), id, 1, Vector3.new(0, 0, 0))
	local m = {Name = id}
	return L.register(marker, m, Vector3.new(0, 1, 0), {radius = 1}), m
end
local function callsOf(w, op)
	local out = {}
	for _, c in ipairs(w.calls) do if c.op == op then table.insert(out, c) end end
	return out
end
-- Bodies.
for _, id in ipairs(ST.SlayerOnlyOrder) do
	local kind = Combat.BODY_KIND[id]
	ok(type(kind) == "string" and kind ~= "blob", id .. " has its own body")
	local plan = Combat.blueprint(kind, Data.Monsters[id].color, false)
	ok(#plan.parts >= 8 and #plan.parts + 1 <= 25, id .. " body part budget")
	local names = {}
	for _, part in ipairs(plan.parts) do ok(not names[part.name], id .. " unique part " .. part.name); names[part.name] = true end
	local boss = Combat.blueprint(kind, Data.Monsters[id].color, true)
	ok(boss.scale > 1 and boss.hitbox.Y > plan.hitbox.Y, id .. " superior scale")
end
-- Slayer level gate.
do
	local w = arena({level = 39})
	local r, m = spawn(w.logic, "HollowcapShrieker")
	local hit, why = w.logic.attack(w.hero, "attack", m)
	ok(hit == nil and why == "slayer", "Slayer 39 cannot hit a Shrieker")
	eq(r.hp, r.maxHp, "no damage dealt")
	local denied = callsOf(w, "slayerDenied")
	eq(#denied, 1, "the refusal is reported for a notice")
	eq(denied[1].payload.monster, "HollowcapShrieker", "notice names the monster")
	eq((w.logic.mitigate(r, 1000, "melee", w.hero)), 0, "mitigate deals nothing below the gate")
	ok(w.logic.mitigate(r, 1000, "melee", nil) > 0, "unattributed damage is not gated")
	eq(w.logic.slayerLevelOf(w.hero), 39, "level from the cached stats")
	w.stats[w.hero] = table.clone(w.stats[w.hero])
	w.stats[w.hero].slayer = {level = 40}
	w.clock += 2
	local landed = w.logic.attack(w.hero, "attack", m)
	ok(landed ~= nil and landed.damage > 0, "Slayer 40 hits it")
	local plainW = arena(nil)
	local _, pm = spawn(plainW.logic, "HollowcapShrieker")
	local _, reason = plainW.logic.attack(plainW.hero, "attack", pm)
	eq(reason, "slayer", "no slayer info counts as Slayer 1")
	local _, tm = spawn(plainW.logic, "Thornling")
	ok(plainW.logic.attack(plainW.hero, "attack", tm) ~= nil, "ordinary monsters need nothing")
	eq(#callsOf(plainW, "slayerDenied"), 1, "only the gated swing reported")
end
-- Visor bonus.
do
	local plainW = arena({level = 99, family = "Burrowers"})
	local visorW = arena({level = 99, family = "Burrowers", visor = {damage = 15, accuracy = 15}})
	local offW = arena({level = 99, family = "Thicketkin", visor = {damage = 15, accuracy = 15}})
	local junkW = arena({level = 99, family = "Burrowers", visor = {damage = "x", accuracy = -5}})
	local r1, m1 = spawn(plainW.logic, "ShaleCrawler")
	local r2, m2 = spawn(visorW.logic, "ShaleCrawler")
	local _, m3 = spawn(offW.logic, "ShaleCrawler")
	local _, m4 = spawn(junkW.logic, "ShaleCrawler")
	local a = plainW.logic.attack(plainW.hero, "attack", m1)
	local b = visorW.logic.attack(visorW.hero, "attack", m2)
	local c = offW.logic.attack(offW.hero, "attack", m3)
	local dd = junkW.logic.attack(junkW.hero, "attack", m4)
	local raw = P.meleeDamage(plainW.stats[plainW.hero].stats, function() return 0.5 end)
	eq(a.damage, (plainW.logic.mitigate(r1, raw, "melee")), "no visor: base damage")
	eq(b.damage, P.damageTaken(math.floor(raw * 1.15 * P.styleModifier("melee", r2)), r2.defense), "visor +15% vs the task family")
	ok(b.damage > a.damage, "visor hits harder")
	eq(c.damage, a.damage, "visor does nothing off task")
	eq(dd.damage, a.damage, "garbage visor values ignored")
	eq(visorW.logic.prayerAccuracy(visorW.hero, 0.5), 0.5, "accuracy unchanged outside a ranged hit")
	-- Ranged accuracy inside a hit.
	local bow, arrow
	for id, def in pairs(Data.Items) do
		if type(def.ranged) == "table" and def.ranged.maxAmmoTier and def.ranged.maxAmmoTier >= 1 and (not bow or def.ranged.power < Data.Items[bow].ranged.power) then bow = id end
		if type(def.ammo) == "table" and def.ammo.tier == 1 then arrow = id end
	end
	ok(bow and arrow, "a bow and arrows exist")
	local function shot(w, id)
		local r = spawn(w.logic, id, "shot" .. id)
		local hit = {record = r, style = "ranged"}
		w.logic.rangedHit(w.hero, r, hit, w.stats[w.hero].stats, Data.Items[bow], Data.Items[arrow], 1, w.logic.perks({}, "ranged"))
		return hit, r
	end
	local h1, rr = shot(plainW, "CinderMite")
	local h2 = shot(visorW, "CinderMite")
	local h3 = shot(offW, "CinderMite")
	local baseChance = P.hitChance(0, 1, rr.level, rr.defense)
	ok(near(h1.chance, baseChance), "base ranged chance")
	ok(near(h2.chance, math.min(math.max(baseChance, Data.CombatStyles.hitCeiling), baseChance * 1.15)), "visor raises accuracy 15%")
	ok(h2.chance > h1.chance, "visor accuracy higher")
	ok(near(h3.chance, baseChance), "no accuracy bonus off task")
end
-- Multishot never splashes gated monsters or others' superiors.
do
	local w = arena({level = 1})
	local primary = spawn(w.logic, "Thornling", "p")
	local gated = spawn(w.logic, "HollowcapShrieker", "g")
	local free = spawn(w.logic, "ShaleCrawler", "f")
	w.logic.statsFor(w.hero)
	local targets = w.logic.multishotTargets(w.hero, primary, Vector3.new(0, 0, 0), 40, 2)
	ok(table.find(targets, free) ~= nil, "ungated monster splashed")
	eq(table.find(targets, gated), nil, "gated monster never splashed")
end
-- Superiors.
do
	local w = arena({level = 99, family = "Burrowers"})
	local L = w.logic
	local r, m = spawn(L, "ShaleCrawler")
	w.killReply = {superior = {id = "SuperiorShaleCrawler", seq = 4}}
	r.hp = 1
	local res = L.attack(w.hero, "attack", m)
	ok(res.killed, "monster killed")
	local killCalls = callsOf(w, "kill")
	eq(#killCalls, 1, "kill reported")
	local due = L.pendingSuperiors()
	eq(#due, 1, "the reply queues one superior")
	eq(#L.pendingSuperiors(), 0, "queue drains")
	local spec = due[1]
	ok(spec.player == w.hero and spec.id == "SuperiorShaleCrawler" and spec.seq == 4, "spec owner, id, seq")
	ok(spec.at == r.position, "spawns where the monster died")
	local model = {Name = "sup"}
	local sr = L.registerSuperior(spec, model, Vector3.new(0, 1, 0), {radius = 1})
	ok(sr and sr.superior and sr.owner == w.hero, "superior registered for its owner")
	eq(sr.maxHp, ST.Superiors.SuperiorShaleCrawler.hp, "superior health")
	eq(sr.target, w.hero, "superior targets its owner")
	eq(L.registerSuperior(spec, {}, Vector3.zero), nil, "a spec registers once")
	eq(L.superiorCount(w.hero), 1, "owner has one")
	local _, why = L.attack(w.rival, "attack", model)
	eq(why, "owner", "only the owner may hit it")
	ok(L.hasPlayerState(w.hero), "superior counts as player state")
	sr.hp = 1
	w.clock += 2
	local fin = L.attack(w.hero, "attack", model)
	ok(fin.killed and fin.credited[1] == w.hero, "owner kills and is credited")
	local sup = callsOf(w, "slayerSuperior")
	eq(#sup, 1, "settled once")
	ok(sup[1].payload.result == "kill" and sup[1].payload.seq == 4 and sup[1].payload.monster == "SuperiorShaleCrawler", "kill settlement payload")
	eq(#callsOf(w, "kill"), 1, "a superior never reports a plain kill")
	local xpCalls = callsOf(w, "combatXp")
	eq(xpCalls[#xpCalls].payload.monster, "SuperiorShaleCrawler", "superior damage XP")
	eq(L.superiorCount(w.hero), 0, "unregistered")
	-- Mismatched and garbage replies queue nothing.
	local r2 = spawn(L, "ShaleCrawler", "m2")
	eq(L.onKillReply(w.hero, r2, {superior = {id = "SuperiorThornling", seq = 5}}), nil, "superior must match the base")
	eq(L.onKillReply(w.hero, r2, {superior = {id = "Nope", seq = 5}}), nil, "unknown superior")
	eq(L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 0}}), nil, "bad seq")
	eq(L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 1.5}}), nil, "fractional seq")
	eq(L.onKillReply(w.hero, r2, nil), nil, "no reply")
	eq(L.onKillReply(w.hero, r2, {drops = {}}), nil, "reply without superior")
	eq(#L.pendingSuperiors(), 0, "nothing queued")
	-- A second superior from another kill: the owner credited again when adjacent.
	local spec2 = L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 6}})
	L.pendingSuperiors()
	local near2 = L.registerSuperior(spec2, {Name = "near"}, Vector3.new(0, 1, 0), {})
	near2.hp = 1
	w.clock += 2
	local again = L.attack(w.hero, "attack", near2.model)
	ok(again.killed and again.credited[1] == w.hero, "adjacent owner credited")
	-- Owner too far at the kill: withdrawn, not credited.
	local spec3 = L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 7}})
	L.pendingSuperiors()
	local away = L.registerSuperior(spec3, {Name = "away"}, Vector3.new(0, 1, 0), {})
	L.landHit(w.hero, away, 10, "melee")
	w.pos[w.hero] = Vector3.new(500, 0, 0)
	local credited = L.kill(away)
	eq(#credited, 0, "owner out of range: no credit")
	local last = callsOf(w, "slayerSuperior")
	eq(last[#last].payload.result, "despawn", "uncredited superior frees the ticket")
	w.pos[w.hero] = Vector3.new(0, 0, 0)
	-- Expiry.
	local spec4 = L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 8}})
	L.pendingSuperiors()
	local timed = L.registerSuperior(spec4, {Name = "timed"}, Vector3.new(0, 1, 0), {})
	eq(#L.superiorTick(), 0, "fresh superior stays")
	w.clock += L.superiorLifetime() + 1
	local expired = L.superiorTick()
	eq(expired[1], timed, "superior withdraws after its lifetime")
	last = callsOf(w, "slayerSuperior")
	ok(last[#last].payload.result == "despawn" and last[#last].payload.seq == 8, "withdrawal reported")
	-- Owner leaving: silent removal.
	local spec5 = L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 9}})
	L.pendingSuperiors()
	local leaving = L.registerSuperior(spec5, {Name = "leaving"}, Vector3.new(0, 1, 0), {})
	local queued = L.onKillReply(w.hero, r2, {superior = {id = "SuperiorShaleCrawler", seq = 10}})
	ok(queued ~= nil, "a second superior queued")
	local n = #callsOf(w, "slayerSuperior")
	local removed = L.playerRemoving(w.hero)
	ok(table.find(removed, leaving) ~= nil, "owner leaving removes the superior")
	eq(#callsOf(w, "slayerSuperior"), n, "silently (the server forgets the ticket)")
	eq(#L.pendingSuperiors(), 0, "queued spawns dropped")
	ok(not L.hasPlayerState(w.hero), "no player state left")
	eq(L.resolve(leaving.model), nil, "record gone")
	-- Superiors never respawn or count as marker monsters.
	ok(L.liveCount() >= 0, "live count sane")
end
do
	local source = fs.readFile("combat.server.lua")
	ok(has(source, 'env.bridge("kill", player, {monster = r.id}, function(reply) L.onKillReply(player, r, reply) end)'), "kill bridge carries the superior hook")
	ok(has(source, "slayerStep() -- Slayer tasks section"), "runtime spawns superiors")
end
print("PASS: " .. (checks - partC) .. " Slayer combat assertions.")

------------------------------------------------------------------------------
-- Part D: Hunt › Slayer.
------------------------------------------------------------------------------
local partD = checks
local H = require("./tools/ui-harness")
local function ledger(extra)
	local masters, families = {}, {}
	for _, m in ipairs(ST.Masters) do masters[m.id] = {ok = m.combat <= 50, reason = m.combat > 50 and ("Requires Combat " .. m.combat) or nil} end
	for _, f in ipairs(ST.Families) do families[f.id] = {ok = f.slayer <= 45, reason = f.slayer > 45 and ("Requires Slayer " .. f.slayer) or nil} end
	local st = {task = {master = "Corvane", family = "Gloomweavers", amount = 60, killed = 24, extended = false}, streak = 9, completed = 41, points = 260,
		blocked = {"Reefstalkers"}, blockSlots = 3, unlocks = {"SuperiorCalling", "TitleGravewarden"}, superiors = {SuperiorGloomfangSpider = 2}, title = "TitleGravewarden",
		level = 45, masters = masters, families = families, superiorsLive = 0, nextMult = 5}
	for k, v in pairs(extra or {}) do st[k] = v end
	return st
end
local function atlas(size, mutate)
	local snap = H.snapshot({xp = {Slayer = X[45], Combat = X[50]}})
	snap.slayerTasks = ledger()
	snap.items.SlayerToken, snap.items.HushcapSpore, snap.items.BeastHide = 10, 20, 40
	if mutate then mutate(snap) end
	local ui = H.runAtlas(size, {snapshot = snap})
	H.press(H.find(ui.gui, "AtlasButton"))
	return ui
end
local function open(ui)
	H.press(ui.tabs:FindFirstChild("HuntButton"))
	H.press(H.find(ui.scroll, "SectionSlayer"))
end
local function viewOf(ui, name) H.press(H.find(ui.scroll, "SlayerView" .. name)) end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui)
	eq(#ui.warnings, 0, "Slayer page renders" .. tag)
	for _, v in ipairs({"Tasks", "Masters", "Families", "Shop", "Superiors"}) do ok(H.find(ui.scroll, "SlayerView" .. v) ~= nil, v .. " view button" .. tag) end
	ok(H.find(ui.scroll, "SlayerTaskSummary") ~= nil, "summary" .. tag)
	ok(H.find(ui.scroll, "SlayerTaskCurrent") ~= nil, "current task" .. tag)
	ok(H.find(ui.scroll, "SlayerBramble") ~= nil, "boss lines kept below" .. tag)
	viewOf(ui, "Masters")
	eq(#ui.warnings, 0, "masters view" .. tag)
	for _, m in ipairs(ST.Masters) do ok(H.find(ui.scroll, "SlayerMaster" .. m.id) ~= nil, m.id .. " card" .. tag) end
	viewOf(ui, "Families")
	eq(#ui.warnings, 0, "families view" .. tag)
	for _, f in ipairs(ST.Families) do ok(H.find(ui.scroll, "SlayerFamily" .. f.id) ~= nil, f.id .. " card" .. tag) end
	viewOf(ui, "Shop")
	eq(#ui.warnings, 0, "shop view" .. tag)
	for _, e in ipairs(ST.Shop) do ok(H.find(ui.scroll, "SlayerShop" .. e.id) ~= nil, e.id .. " card" .. tag) end
	viewOf(ui, "Superiors")
	eq(#ui.warnings, 0, "superiors view" .. tag)
	ok(H.find(ui.scroll, "SlayerSuperiorSummary") ~= nil, "superior summary" .. tag)
	for _, id in ipairs(ST.SuperiorOrder) do ok(H.find(ui.scroll, "SlayerSuperior" .. id) ~= nil, id .. " log row" .. tag) end
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	open(ui)
	local text = texts(ui.scroll)
	ok(has(text, "Gloomweavers"), "task family shown")
	ok(has(text, "24 / 60"), "task progress shown")
	ok(has(text, "Warden Corvane Mossgrave"), "master shown")
	ok(has(text, "260 pts"), "points shown")
	ok(has(text, "Gloomfang Spider"), "task targets listed")
	ok(has(text, "line ranks") or has(text, "LINE RANKS"), "boss lines labelled as line ranks")
	H.press(H.find(ui.scroll, "SlayerSkip"))
	eq(ui.sent[#ui.sent][1], "slayerSkip", "skip verb")
	H.press(H.find(ui.scroll, "SlayerCancel"))
	local sent = #ui.sent
	ok(H.find(ui.scroll, "SlayerCancelConfirm") ~= nil, "cancel asks to confirm")
	eq(#ui.sent, sent, "first press sends nothing")
	H.press(H.find(ui.scroll, "SlayerCancelConfirm"))
	eq(ui.sent[#ui.sent][1], "slayerCancel", "confirmed cancel")
	viewOf(ui, "Masters")
	sent = #ui.sent
	H.press(H.find(ui.scroll, "SlayerGetTaskYsolde"))
	eq(#ui.sent, sent, "holding a task: masters refuse locally")
	viewOf(ui, "Families")
	H.press(H.find(ui.scroll, "SlayerUnblockReefstalkers"))
	eq(ui.sent[#ui.sent][1], "slayerUnblock", "unblock verb")
	eq(ui.sent[#ui.sent][2], "Reefstalkers", "unblock names the family")
	H.press(H.find(ui.scroll, "SlayerBlockVoidspawn"))
	eq(ui.sent[#ui.sent][1], "slayerBlock", "block verb")
	eq(ui.sent[#ui.sent][2], "Voidspawn", "block names the family")
	ok(has(texts(ui.scroll), "BLOCKED"), "blocked badge")
	viewOf(ui, "Shop")
	H.press(H.find(ui.scroll, "SlayerBuyVisorCrafting"))
	eq(ui.sent[#ui.sent][1], "slayerBuy", "buy verb")
	eq(ui.sent[#ui.sent][2], "VisorCrafting", "buy names the entry")
	sent = #ui.sent
	H.press(H.find(ui.scroll, "SlayerBuyCraftHuntersVisor"))
	eq(#ui.sent, sent, "visor locked without the lore stays local")
	H.press(H.find(ui.scroll, "SlayerBuySuperiorCalling"))
	eq(#ui.sent, sent, "owned unlocks stay local")
	H.press(H.find(ui.scroll, "SlayerWearTitleGravewarden"))
	eq(ui.sent[#ui.sent][1], "slayerTitle", "title verb")
	eq(ui.sent[#ui.sent][2], "none", "worn title hides")
	viewOf(ui, "Superiors")
	ok(has(texts(ui.scroll), "Gravesilk Gloomfang Spider"), "met superior named")
	ok(has(texts(ui.scroll), "CALLING"), "unlocked badge")
end
do
	-- No task: masters send the verb; families gate by points.
	local ui = atlas(roblox.Vector2.new(844, 390), function(snap) snap.slayerTasks = ledger({points = 20}); snap.slayerTasks.task = nil end)
	open(ui)
	ok(H.find(ui.scroll, "SlayerTaskNone") ~= nil, "no-task card")
	viewOf(ui, "Masters")
	H.press(H.find(ui.scroll, "SlayerGetTaskCorvane"))
	eq(ui.sent[#ui.sent][1], "slayerTask", "task verb")
	eq(ui.sent[#ui.sent][2], "Corvane", "task names the master")
	local sent = #ui.sent
	H.press(H.find(ui.scroll, "SlayerGetTaskVesper"))
	eq(#ui.sent, sent, "locked master stays local")
	viewOf(ui, "Families")
	H.press(H.find(ui.scroll, "SlayerBlockVoidspawn"))
	eq(#ui.sent, sent, "too few points to block")
	-- Missing or malformed state.
	ui = atlas(roblox.Vector2.new(730, 303), function(snap) snap.slayerTasks = nil end)
	open(ui)
	eq(#ui.warnings, 0, "missing ledger tolerated")
	for _, v in ipairs({"Masters", "Families", "Shop", "Superiors"}) do viewOf(ui, v); eq(#ui.warnings, 0, "missing ledger on " .. v) end
	ui = atlas(roblox.Vector2.new(730, 303), function(snap)
		snap.slayerTasks = {task = {family = "Ghost", killed = "x"}, points = "lots", blocked = 4, unlocks = 3, superiors = 2, masters = 1, families = "x", streak = {}}
	end)
	open(ui)
	eq(#ui.warnings, 0, "malformed ledger tolerated")
	for _, v in ipairs({"Masters", "Families", "Shop", "Superiors"}) do viewOf(ui, v); eq(#ui.warnings, 0, "malformed ledger on " .. v) end
end
print("PASS: " .. (checks - partD) .. " Slayer atlas assertions.")
print("Slayer tasks QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-slayer-tasks.luau")
