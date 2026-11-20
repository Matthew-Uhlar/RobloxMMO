-- Headless checks for shared/GameData.lua and shared/Progression.lua.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function seq(values) local i = 0; return function() i += 1; return values[(i - 1) % #values + 1] end end

-- OSRS experience table landmarks.
eq(Data.XP_TABLE[2], 83, "level 2 xp")
eq(Data.XP_TABLE[10], 1154, "level 10 xp")
eq(Data.XP_TABLE[50], 101333, "level 50 xp")
eq(Data.XP_TABLE[92], 6517253, "level 92 xp (half of 99)")
eq(Data.XP_TABLE[99], 13034431, "level 99 xp")
eq(P.levelForXp(0), 1, "zero xp")
eq(P.levelForXp(82), 1, "below level 2")
eq(P.levelForXp(83), 2, "exact level 2")
eq(P.levelForXp(13034431), 99, "level 99")
eq(P.levelForXp(200000000), 99, "cap")
local prog = P.progress(100)
eq(prog.level, 2, "progress level")
ok(prog.fraction > 0 and prog.fraction < 1, "progress fraction")
local profile = {xp = {Mining = 199999990}, items = {}, collection = {}}
P.addXp(profile, "Mining", 1000)
eq(profile.xp.Mining, Data.MAX_XP, "200M cap")

-- Data integrity: every recipe ingredient/output and drop references an item.
local recipeCount, itemCount = 0, 0
for id, def in Data.Items do
	itemCount += 1
	ok(def.name and def.kind and Data.Rarity[def.rarity], "item metadata " .. id)
	ok(type(def.color) == "string" and #def.color == 6, "item colour " .. id)
end
for id, rec in Data.Recipes do
	recipeCount += 1
	ok(Data.Items[rec.output] ~= nil, "recipe output " .. id)
	ok(Data.Skills[rec.skill] ~= nil, "recipe skill " .. id)
	for itemId in rec.costs do ok(Data.Items[itemId] ~= nil, "recipe ingredient " .. id .. ":" .. itemId) end
	for itemId in rec.collectionTier or {} do ok(Data.Items[itemId] ~= nil, "recipe collection " .. id .. ":" .. itemId) end
end
for id, m in Data.Monsters do
	ok(Data.RegionById[m.region] ~= nil, "monster region " .. id)
	for _, d in m.drops do ok(Data.Items[d.item] ~= nil, "drop " .. id .. ":" .. d.item) end
end
for line, s in Data.Slayers do
	eq(#s.tiers, 4, "slayer tiers " .. line)
	for _, t in s.tiers do for _, d in t.drops do ok(Data.Items[d.item] ~= nil, "slayer drop " .. d.item) end end
end
for _, r in Data.Regions do for _, m in r.monsters or {} do ok(Data.Monsters[m] ~= nil, "region monster " .. m) end end
for _, id in Data.CollectionItems do ok(Data.Items[id] ~= nil, "collection item " .. id) end
for _, set in Data.Sets do eq(#set.pieces, 4, "set pieces " .. set.id) end
ok(itemCount >= 120, "item breadth " .. itemCount)
ok(recipeCount >= 80, "recipe breadth " .. recipeCount)

-- Resource tiers progress monotonically in level, xp and tool tier.
for skill, tiers in Data.ResourceTiers do
	for i = 2, #tiers do
		ok(tiers[i].level > tiers[i - 1].level and tiers[i].xp > tiers[i - 1].xp and tiers[i].tool >= tiers[i - 1].tool, "tier ladder " .. skill .. i)
	end
end

-- Gathering: level gate, tool gate, fortune.
local gatherer = {xp = {}, items = {}, collection = {}}
local okGather, result = P.harvest(gatherer, "Ore", {}, seq({0.99}))
ok(okGather and result.amount == 1 and result.xp == 12, "basic harvest")
local denied, reason = P.harvest(gatherer, "Brassite", {}, seq({0.5}))
ok(not denied and reason:find("Mining 15"), "level gate")
gatherer.xp.Mining = Data.XP_TABLE[15]
denied, reason = P.harvest(gatherer, "Brassite", {}, seq({0.5}))
ok(not denied and reason:find("tier 1 pickaxe"), "tool gate")
gatherer.items.Pickaxe = 1
okGather, result = P.harvest(gatherer, "Brassite", {miningFortune = 150}, seq({0.2}))
-- 150 fortune: +1 guaranteed, 50% chance of another; roll .2 succeeds.
ok(okGather and result.amount == 3, "fortune roll " .. tostring(result and result.amount))
eq(P.fortuneRoll(1, 150, seq({0.9})), 2, "fortune remainder miss")

-- Collections and crafting gates.
local smith = {xp = {Smithing = Data.XP_TABLE[15]}, items = {BrassIngot = 20, WindpineLog = 5}, collection = {Brassite = 60}}
eq(P.collectionTier(smith, "Brassite"), 1, "collection tier 1")
local can, why = P.canCraft(smith, "BrassSword")
ok(not can and why:find("collection tier 2"), "collection gate " .. tostring(why))
smith.collection.Brassite = 100
ok(P.canCraft(smith, "BrassSword"), "sword unlocked")
eq(P.collectionThreshold("SlayerToken", 1), 2, "scaled drop collection")
smith.xp.Smithing = 0
ok(not P.canCraft(smith, "BrassSword"), "smithing level gate")

-- Stats: skills, gear, set bonus, accessories, pet, buffs.
local fighter = {xp = {Combat = Data.XP_TABLE[20], Mining = Data.XP_TABLE[10]}, items = {}, collection = {}, equipment = {}}
local s = P.computeStats(fighter, 0)
eq(s.health, 100, "base health with no health skills")
eq(s.defense, 9, "mining defense per level")
eq(s.critChance, 30 + 19 * 0.5, "combat crit chance")
eq(s.combatBonus, 76, "combat damage bonus")
for _, slot in Data.ArmorSlots do
	local id = Data.Sets.Brass.pieces[table.find(Data.ArmorSlots, slot)]
	fighter.items[id] = 1
	fighter.equipment[slot] = id
end
fighter.items.BrassSword = 1
fighter.equipment.weapon = "BrassSword"
s = P.computeStats(fighter, 0)
eq(s.activeSet, "Brass", "set bonus active")
eq(s.weapon, "BrassSword", "weapon equipped")
ok(s.defense > 9 + 30 + 40, "armor and set defense " .. s.defense)
fighter.items.MeadowCharm, fighter.items.QuarryTalisman = 1, 1
fighter.accessoryBag = {"MeadowCharm", "QuarryTalisman", "MeadowCharm"}
eq(P.magicalPower(fighter), 6, "unique accessory power")
fighter.pets = {{id = "Emberfox", level = 10, xp = 0}}
fighter.activePet = 1
fighter.buffs = {MightDraught = {expires = 100, stats = {strength = 15}}}
local buffed = P.computeStats(fighter, 50)
local expired = P.computeStats(fighter, 200)
eq(buffed.strength - expired.strength, 15, "buff expires")
-- Requirements: unequip when Combat too low.
local weak = {xp = {}, items = {BrassSword = 1}, collection = {}, equipment = {weapon = "BrassSword"}}
eq(P.computeStats(weak, 0).weapon, nil, "combat requirement gates weapon")

-- Combat math.
local dmg, crit = P.meleeDamage({damage = 40, strength = 100, critChance = 100, critDamage = 50, combatBonus = 0}, seq({0}))
eq(dmg, 135, "skyblock damage formula with crit")
ok(crit, "crit flag")
eq(P.meleeDamage({damage = 40, strength = 100, critChance = 0, critDamage = 50, combatBonus = 20}, seq({0.5})), 108, "combat bonus multiplier")
eq(P.damageTaken(200, 100), 100, "defense halves damage at 100")
eq(P.walkSpeed(150), 24, "speed stat to walkspeed")

-- Loot and magic find.
local drops = P.rollDrops({{item = "StarFragment", chance = 0.01, min = 1, max = 1}}, 100, seq({0.015}))
eq(drops.StarFragment, 1, "magic find doubles rare chance")
drops = P.rollDrops({{item = "StarFragment", chance = 0.01, min = 1, max = 1}}, 0, seq({0.015}))
eq(drops.StarFragment, nil, "no magic find")

-- Pets and slayer levels.
local tamer = {xp = {}, items = {}, pets = {{id = "Burrowmole", level = 1, xp = 0}}, activePet = 1}
P.addPetXp(tamer, "Mining", Data.petXpToNext(1, "Uncommon"))
eq(tamer.pets[1].level, 2, "pet level up with matching skill")
P.addPetXp(tamer, "Combat", 4)
eq(tamer.pets[1].xp, 1, "off-skill pet xp quarter")
eq(P.slayerLevel(14), 1, "slayer level 1")
eq(P.slayerLevel(1000000), 9, "slayer level 9")
eq(P.accessorySlots({xp = {Combat = Data.XP_TABLE[25]}}), 8, "accessory slots grow with combat")

print("PASS: " .. checks .. " progression/data assertions (" .. itemCount .. " items, " .. recipeCount .. " recipes).")
do
	local perky = {xp = {}, items = {}, collection = {}, perkStats = {diaryMeadow = {health = 25, strength = 5}, quest = {defense = 10, bogus = 99, health = 0/0}}}
	local st = P.computeStats(perky, 0)
	assert(st.health == 125 and st.strength == 5 and st.defense == 10 and st.bogus == nil, "perk stats flow into the stat sheet")
	print("PASS: perk stat hook.")
end
do
	local bag = {xp = {Combat = Data.XP_TABLE[25]}, perkAccessorySlots = 99}
	assert(P.accessorySlots(bag) == 8 + Data.MAX_PERK_SLOTS, "perk accessory slots capped")
	assert(P.perkSlotsIntegrated == true, "server wrapper disabled")
	print("PASS: accessory slot perks.")
end
