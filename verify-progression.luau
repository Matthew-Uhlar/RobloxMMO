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

------------------------------------------------------------------------------
-- Combat styles: data integrity, triangle, formulas, mana, glyphs, XP routing.
------------------------------------------------------------------------------
do
	local before = checks
	local CS = Data.CombatStyles
	ok(CS ~= nil, "combat styles config")
	-- Skills registered everywhere they are enumerated.
	for _, skill in ipairs({"Ranged", "Magic", "Fletching", "Glyphcraft"}) do
		ok(table.find(Data.SkillOrder, skill) ~= nil, skill .. " in SkillOrder")
		ok(Data.Skills[skill] ~= nil and Data.Skills[skill].perLevel ~= nil, skill .. " has perLevel rewards")
		for stat in Data.Skills[skill].perLevel do ok(Data.Stats[stat] ~= nil, skill .. " reward stat " .. stat) end
	end
	eq(#Data.SkillOrder, 20, "twenty skills (combat styles, Agility & Hunter, Prayer & Thieving)")
	local seen = {}
	for _, skill in ipairs(Data.SkillOrder) do ok(not seen[skill], "unique skill " .. skill); seen[skill] = true end
	for _, stat in ipairs({"rangedStrength", "rangedAccuracy", "abilityDamage"}) do
		ok(Data.Stats[stat] ~= nil and table.find(Data.StatOrder, stat) ~= nil, "stat registered " .. stat)
	end
	ok(table.find(Data.EquipSlots, "ammo") ~= nil, "ammo equip slot")
	eq(CS.slotNames.ammo, "Quiver", "ammo slot is the Quiver")
	-- Triangle: a cycle, and each style beats exactly one other.
	for _, style in ipairs(CS.order) do
		ok(CS.beats[style] ~= style and CS.beatenBy[CS.beats[style]] == style, "triangle " .. style)
		eq(CS.skill[style] ~= nil and Data.Skills[CS.skill[style]] ~= nil, true, "style skill " .. style)
	end
	eq(CS.beats[CS.beats[CS.beats.melee]], "melee", "triangle closes after three steps")
	-- Every monster, sea creature and slayer line has a full triangle profile.
	local function triangle(id, def)
		ok(CS.beats[def.attackStyle] ~= nil, id .. " attack style")
		ok(CS.beats[def.weakness] ~= nil and def.weakness ~= def.attackStyle, id .. " weakness")
		ok(CS.beats[def.defenceStyle] ~= nil and def.defenceStyle ~= def.weakness, id .. " defence style")
		eq(def.weakness, CS.beatenBy[def.attackStyle], id .. " weak to the style that beats it")
	end
	local weakTo = {melee = 0, ranged = 0, magic = 0}
	for id, def in Data.Monsters do triangle(id, def); weakTo[def.weakness] += 1 end
	for id, def in Data.SeaCreatures do triangle(id, def); weakTo[def.weakness] += 1 end
	for id, def in Data.Slayers do triangle(id, def) end
	for style, n in weakTo do ok(n >= 3, "at least three creatures weak to " .. style) end
	eq(Data.Monsters.TidewyrmMatriarch.weakness, "ranged", "sea creature reachable through Monsters")
	-- Arrows, bows, staves.
	eq(#CS.arrowOrder, 7, "seven arrow tiers")
	for i, id in ipairs(CS.arrowOrder) do
		local def = Data.Items[id]
		ok(def and def.slot == "ammo" and def.combatUse and def.ammo.tier == i, id .. " is tiered ammo")
		ok(Data.Recipes[id] and Data.Recipes[id].skill == "Fletching" and Data.Recipes[id].amount == 15, id .. " fletched in fifteens")
		local heads = CS.arrowTiers[i].heads
		ok(Data.Recipes[heads] and Data.Recipes[heads].skill == "Smithing", heads .. " smithed")
		eq(Data.Recipes[id].costs[heads], 15, id .. " uses its heads")
		if i > 1 then ok(def.ammo.power > Data.Items[CS.arrowOrder[i - 1]].ammo.power and def.requires.Ranged >= Data.Items[CS.arrowOrder[i - 1]].requires.Ranged, id .. " ladder") end
	end
	eq(#CS.bowOrder, 12, "shortbow and longbow per wood tier")
	for i = 1, #CS.bowOrder, 2 do
		local short, long = Data.Items[CS.bowOrder[i]], Data.Items[CS.bowOrder[i + 1]]
		ok(short.style == "ranged" and long.style == "ranged" and short.slot == "weapon", short.name .. " ranged weapons")
		ok(short.ranged.speed < long.ranged.speed, short.name .. " shoots faster than the longbow")
		ok(short.ranged.range < long.ranged.range and long.ranged.range <= 40, long.name .. " reaches further (max 40)")
		ok(long.ranged.power > short.ranged.power, long.name .. " hits harder")
		eq(Data.Recipes[CS.bowOrder[i]].skill, "Fletching", short.name .. " fletched")
		ok(short.ranged.maxAmmoTier >= 2 and short.ranged.maxAmmoTier <= #CS.arrowOrder, short.name .. " ammo tier cap")
	end
	eq(#CS.staffOrder, 12, "staff and wand per tier")
	for i = 1, #CS.staffOrder, 2 do
		local staff, wand = Data.Items[CS.staffOrder[i]], Data.Items[CS.staffOrder[i + 1]]
		ok(staff.style == "magic" and wand.style == "magic", staff.name .. " magic weapons")
		ok(wand.magic.speed < staff.magic.speed and staff.magic.power > wand.magic.power, wand.name .. " trades power for speed")
		ok(#staff.magic.elements >= 1 and #wand.magic.elements == 0, staff.name .. " elemental staff")
		eq(Data.Recipes[CS.staffOrder[i]].skill, "Glyphcraft", staff.name .. " glyphcrafted")
	end
	-- Glyphs and spells.
	for _, id in ipairs(CS.glyphOrder) do
		ok(Data.Items[id] and Data.Items[id].combatUse and Data.Items[id].category == "glyph", id .. " glyph item")
		eq(Data.Recipes[id].skill, "Glyphcraft", id .. " glyphcrafted")
	end
	ok(Data.Items.HubwardTablet.combatUse and Data.Recipes.HubwardTablet.skill == "Glyphcraft", "hub tablet")
	eq(#Data.SpellOrder, 15, "twelve combat spells and three utility spells")
	local kinds = {}
	for _, id in ipairs(Data.SpellOrder) do
		local spell = Data.Spells[id]
		kinds[spell.kind] = (kinds[spell.kind] or 0) + 1
		ok(spell.level >= 1 and spell.level <= 99 and spell.range <= 40, id .. " level and reach")
		for item, n in spell.costs do ok(Data.Items[item] and Data.Items[item].combatUse and n >= 1, id .. " cost " .. item) end
		ok(type(spell.color) == "string" and #spell.color == 6, id .. " colour")
	end
	eq(kinds.damage, 12, "damage spells")
	eq(kinds.snare, 1, "snare spell"); eq(kinds.heal, 1, "heal spell"); eq(kinds.teleport, 1, "teleport spell")
	for _, tier in ipairs(CS.spellTiers) do
		for _, element in ipairs(CS.elementOrder) do
			local spell = Data.Spells[element .. tier.id]
			ok(spell ~= nil and spell.autocast and spell.costs[tier.catalyst] == 1 and spell.costs[CS.elements[element].glyph] == tier.elementCost, element .. tier.id .. " costs")
		end
	end
	ok(Data.Spells.GaleDart.damage < Data.Spells.GaleLance.damage and Data.Spells.GaleLance.damage < Data.Spells.GaleCascade.damage, "spell tiers escalate")
	ok(not Data.Spells.Mend.requiresWeapon and not Data.Spells.Hubward.requiresWeapon and Data.Spells.Rootbind.requiresWeapon, "utility weapon rules")
	-- Drift plumes drop from sky creatures and are a collection.
	local plume = false
	for _, d in Data.Monsters.StormHarrier.drops do if d.item == "DriftPlume" then plume = true end end
	ok(plume, "harriers drop plumes")
	ok(table.find(Data.CollectionItems, "DriftPlume") ~= nil, "plume collection")

	-- Weapon style and cooldowns.
	eq(P.weaponStyle(nil), "melee", "unarmed is melee")
	eq(P.weaponStyle(Data.Items.BrassSword), "melee", "swords are melee")
	eq(P.weaponStyle(Data.Items.MeadowShortbow), "ranged", "bows are ranged")
	eq(P.weaponStyle(Data.Items.MeadowWand), "magic", "wands are magic")
	eq(P.weaponStyle({style = "bogus"}), "melee", "unknown style falls back")
	eq(P.weaponCooldown(1, 0), 1, "weapon speed")
	eq(P.weaponCooldown(1, 100), 0.5, "attack speed halves the cooldown")
	eq(P.weaponCooldown(1, 400), 0.5, "attack speed capped")
	eq(P.weaponCooldown(0, 0), 0.1, "cooldown floor")
	-- Triangle modifier.
	local boar = Data.Monsters.BramblebackBoar
	local m, tag = P.styleModifier("magic", boar)
	eq(m, 1.3, "+30% versus weakness"); eq(tag, "weak", "weakness tag")
	m, tag = P.styleModifier("ranged", boar)
	eq(m, 0.7, "-30% versus resisted style"); eq(tag, "resist", "resist tag")
	m, tag = P.styleModifier("melee", boar)
	eq(m, 1, "neutral style"); eq(tag, nil, "no tag")
	eq((P.styleModifier("bogus", boar)), 1, "unknown style neutral")
	eq((P.styleModifier("magic", nil)), 1, "no definition neutral")
	-- Ranged damage formula.
	local bow, arrow = Data.Items.MeadowShortbow, Data.Items.CopperArrow
	local base = 5 + bow.ranged.power + arrow.ammo.power
	eq(P.rangedDamage({}, bow, arrow, 1, seq({0.99})), base, "ranged base damage")
	eq(P.rangedDamage({rangedStrength = 100}, bow, arrow, 1, seq({0.99})), base * 2, "ranged strength doubles at 100")
	eq(P.rangedDamage({}, bow, arrow, 26, seq({0.99})), base * 2, "+4% per Ranged level")
	eq(P.rangedDamage({damagePercent = 50}, bow, arrow, 1, seq({0.99})), math.floor(base * 1.5), "Sharpness applies to bows")
	local rd, rc = P.rangedDamage({critChance = 100, critDamage = 100}, bow, arrow, 1, seq({0}))
	eq(rd, base * 2, "ranged crit"); ok(rc, "ranged crit flag")
	ok(P.rangedDamage({}, Data.Items.AetherheartLongbow, Data.Items.CelestialArrow, 1, seq({0.99})) > base * 10, "top tier bow and arrow")
	eq(P.rangedDamage({}, nil, nil, 1, seq({0.99})), 5, "no bow, no arrow")
	-- Hit chance.
	local parity = P.hitChance(0, 1, 1, 0)
	ok(math.abs(parity - CS.accuracyParity) < 1e-9, "matched rolls hit at parity")
	ok(P.hitChance(200, 99, 1, 0) == CS.hitCeiling, "hit chance ceiling")
	local hopeless = P.hitChance(0, 1, 99, 1000)
	ok(hopeless >= CS.hitFloor and hopeless < 0.4, "outmatched archers still land some shots")
	ok(P.hitChance(100, 50, 40, 90) > P.hitChance(0, 50, 40, 90), "accuracy raises hit chance")
	ok(P.hitChance(50, 50, 80, 300) < P.hitChance(50, 50, 80, 0), "defence lowers hit chance")
	-- Spell damage (SkyBlock ability formula).
	local dart = Data.Spells.GaleDart
	eq(P.spellDamage({intelligence = 0}, dart, nil, 1), dart.damage, "bare spell damage")
	eq(P.spellDamage({intelligence = 200}, dart, nil, 1), math.floor(dart.damage * (1 + 2 * dart.scaling)), "intelligence scaling")
	eq(P.spellDamage({intelligence = 0}, dart, Data.Items.MeadowStaff, 1), dart.damage + Data.Items.MeadowStaff.magic.power, "staff power adds")
	eq(P.spellDamage({intelligence = 0, abilityDamage = 50}, dart, nil, 1), math.floor(dart.damage * 1.5), "ability damage")
	eq(P.spellDamage({intelligence = 0}, dart, nil, 11), math.floor(dart.damage * 1.3), "+3% per Magic level")
	eq(P.spellDamage({}, Data.Spells.Mend, nil, 1), 0, "utility spells deal no damage")
	-- Mana.
	eq(P.maxMana({intelligence = 150}), 150, "max mana is intelligence")
	eq(P.maxMana(nil), 0, "no stats, no mana")
	eq(P.manaRegen(100), CS.manaRegenPercent, "regen percent of max per second")
	-- Glyph costs and elemental staves.
	local lance = Data.Spells.TideLance
	local full = P.glyphCost(lance, nil)
	eq(full.TideGlyph, 2, "lance element cost"); eq(full.SurgeGlyph, 1, "lance catalyst")
	local tideStaff = P.glyphCost(lance, Data.Items.WindpineStaff)
	eq(tideStaff.TideGlyph, nil, "tide staff supplies tide glyphs"); eq(tideStaff.SurgeGlyph, 1, "catalyst still paid")
	eq(P.glyphCost(lance, Data.Items.WindpineWand).TideGlyph, 2, "wands supply nothing")
	local omni = P.glyphCost(Data.Spells.EmberCascade, Data.Items.AetherheartStaff)
	eq(omni.EmberGlyph, nil, "aetherheart staff supplies every element"); eq(omni.TorrentGlyph, 1, "cascade catalyst paid")
	eq(P.glyphCost(Data.Spells.Hubward, nil).HubwardTablet, 1, "tablet consumed")
	-- XP routing.
	local melee = P.styleXp("melee", 60, 12, 120)
	eq(melee.Combat, 6, "melee damage trains Combat"); eq(melee.Ranged, nil, "melee trains no Ranged")
	local ranged = P.styleXp("ranged", 60, 12, 120)
	eq(ranged.Ranged, 6, "ranged damage trains Ranged"); eq(ranged.Combat, 2, "plus a third into Combat")
	local magic = P.styleXp("magic", 600, 12, 120)
	eq(magic.Magic, 12, "overkill damage capped at monster hp"); eq(magic.Combat, 4, "magic combat share")
	eq(next(P.styleXp("ranged", 0, 12, 120)), nil, "no damage, no xp")
	eq(next(P.styleXp("bogus", 10, 12, 120)), nil, "unknown style no xp")
	-- Spell permissions.
	local novice = {style = "melee", levels = {Magic = 1}}
	local okCast, why = P.spellAllowed(novice, dart)
	eq(okCast, false, "damage spell needs a magic weapon"); eq(why, "weapon", "weapon reason")
	eq((P.spellAllowed(novice, Data.Spells.Hubward)), true, "tablet needs no weapon")
	okCast, why = P.spellAllowed({style = "magic", levels = {Magic = 1}}, Data.Spells.GaleLance)
	eq(why, "level", "spell level gate")
	eq((P.spellAllowed({style = "magic", levels = {Magic = 30}}, Data.Spells.GaleLance)), true, "mage casts lance")
	eq(select(2, P.spellAllowed(novice, nil)), "spell", "unknown spell")
	-- Loadout: style from the weapon, quiver, supplies, autocast validation.
	local archer = {xp = {Ranged = Data.XP_TABLE[10]}, collection = {},
		items = {MeadowShortbow = 1, CopperArrow = 40, BrassArrow = 5, GaleGlyph = 9, Ore = 50},
		equipment = {weapon = "MeadowShortbow", ammo = "CopperArrow"}, autocast = "GaleDart"}
	local lo = P.combatLoadout(archer)
	eq(lo.style, "ranged", "bow loadout style"); eq(lo.weapon, "MeadowShortbow", "loadout weapon")
	eq(lo.ammo, "CopperArrow", "quiver arrow"); eq(lo.ammoCount, 40, "quiver count")
	eq(lo.supplies.GaleGlyph, 9, "glyph supplies"); eq(lo.supplies.CopperArrow, 40, "arrows are supplies"); eq(lo.supplies.Ore, nil, "ores are not")
	eq(lo.levels.Ranged, 10, "ranged level"); eq(lo.autocast, "GaleDart", "autocast kept")
	archer.equipment.ammo = "CelestialArrow"
	eq(P.combatLoadout(archer).ammo, nil, "unowned / unqualified arrows are not quivered")
	archer.autocast = "GaleCascade"
	eq(P.combatLoadout(archer).autocast, nil, "autocast above Magic level dropped")
	archer.autocast = "Mend"
	eq(P.combatLoadout(archer).autocast, nil, "utility spells cannot autocast")
	local mage = {xp = {}, collection = {}, items = {MeadowStaff = 1}, equipment = {weapon = "MeadowStaff"}}
	eq(P.combatLoadout(mage).style, "magic", "staff loadout style")
	eq(P.combatLoadout({xp = {}, collection = {}, items = {Blade = 1}, equipment = {}}).style, "melee", "legacy blade is melee")
	-- Stats: staves grant intelligence (more mana), new skills grant their rewards.
	local mageStats = P.computeStats(mage, 0)
	eq(mageStats.intelligence, 100 + Data.Items.MeadowStaff.stats.intelligence, "staff intelligence")
	local trained = {xp = {Ranged = Data.XP_TABLE[11], Magic = Data.XP_TABLE[11]}, items = {}, collection = {}}
	local ts = P.computeStats(trained, 0)
	eq(ts.rangedStrength, 10, "Ranged levels grant ranged strength")
	eq(ts.intelligence, 120, "Magic levels grant intelligence")
	eq(ts.abilityDamage, 2, "Magic levels grant ability damage")
	-- Existing behaviour unchanged: melee formula and an existing profile's stat sheet.
	eq(P.meleeDamage({damage = 40, strength = 100, critChance = 0, critDamage = 50, combatBonus = 20}, seq({0.5})), 108, "melee formula unchanged")
	eq(P.computeStats({xp = {}, items = {}, collection = {}}, 0).health, 100, "fresh health unchanged")
	-- Crafting gates.
	local fletcher = {xp = {}, collection = {}, items = {Timber = 10, BeastHide = 2, Herb = 4}}
	eq((P.canCraft(fletcher, "ArrowShaft")), true, "shafts at Fletching 1")
	eq((P.canCraft(fletcher, "Bowstring")), true, "bowstring at Fletching 1")
	local okBow, whyBow = P.canCraft(fletcher, "MeadowShortbow")
	ok(not okBow and whyBow:find("Bowstring") ~= nil, "bow needs a string")
	local okWind, whyWind = P.canCraft(fletcher, "WindpineShortbow")
	ok(not okWind and whyWind:find("Fletching 15") ~= nil, "windpine bow needs Fletching 15")
	local okHeads, whyHeads = P.canCraft({xp = {Smithing = Data.XP_TABLE[15]}, collection = {}, items = {BrassIngot = 1}}, "BrassHeads")
	ok(not okHeads and whyHeads:find("collection") ~= nil, "brass heads gated by collection")
	eq((P.canCraft({xp = {}, collection = {}, items = {Aetherite = 1}}, "GaleGlyph")), true, "gale glyphs at Glyphcraft 1")
	print("PASS: " .. (checks - before) .. " combat style data/formula assertions.")
end

-- Skill Mastery: tree integrity, point accounting, perks in stats/harvest,
-- capstones, respec costs, migration and milestones.
do
	local before = checks
	local MA = Data.Mastery
	local X = Data.XP_TABLE
	ok(type(MA) == "table", "mastery data present")
	eq(#MA.Trees, 8, "eight mastery trees")
	eq(#MA.TreeOrder, 8, "tree order lists every tree")
	local skillsSeen = {}
	for _, id in ipairs(MA.TreeOrder) do
		local tree = MA.TreeById[id]
		ok(tree ~= nil, "tree " .. id .. " registered")
		ok(Data.Skills[tree.skill] ~= nil, id .. " draws on a real skill")
		ok(not skillsSeen[tree.skill], id .. " skill unique")
		skillsSeen[tree.skill] = true
		eq(MA.TreeOfSkill[tree.skill], id, id .. " reverse lookup")
		ok(#tree.nodes >= 10 and #tree.nodes <= 14, id .. " has 10-14 nodes")
		ok(type(tree.name) == "string" and type(tree.blurb) == "string", id .. " named")
		ok(type(tree.color) == "string" and #tree.color == 6, id .. " colour")
		local ids, cells, capstones, roots, totalCost = {}, {}, 0, 0, 0
		for _, n in ipairs(tree.nodes) do
			ok(not ids[n.id], id .. " node id unique " .. n.id)
			ids[n.id] = true
			local cell = n.x .. ":" .. n.y
			ok(not cells[cell], id .. " node cell unique " .. cell)
			cells[cell] = true
			ok(n.x >= 1 and n.x <= 5 and n.y >= 1 and n.y <= 6, id .. " node on the lattice " .. n.id)
			ok(n.max >= 1 and n.cost >= 1 and n.level >= 1 and n.level <= Data.MAX_LEVEL, id .. " node numbers " .. n.id)
			for stat in pairs(n.stats or {}) do ok(Data.Stats[stat] ~= nil or stat == "lifesteal", id .. " stat " .. stat) end
			for perk in pairs(n.perks or {}) do ok(MA.Perks[perk] ~= nil, id .. " perk " .. perk) end
			ok(n.stats ~= nil or n.perks ~= nil or n.ability ~= nil, id .. " node has an effect " .. n.id)
			if n.ability then
				capstones += 1
				eq(n.max, 1, id .. " capstone single level")
				ok(n.ability.duration > 0 and n.ability.cooldown > n.ability.duration, id .. " capstone cooldown longer than its effect")
				ok(type(n.ability.text) == "string", id .. " capstone text")
			end
			if #n.requires == 0 then roots += 1 end
			totalCost += n.max * n.cost
		end
		eq(capstones, 1, id .. " exactly one capstone")
		eq(tree.capstone ~= nil, true, id .. " capstone recorded")
		eq(roots, 1, id .. " single root")
		ok(totalCost <= 89 + math.floor((Data.MAX_XP - X[99]) / MA.POST_MAX_STEP), id .. " maxable with post-99 points")
		ok(totalCost > 60, id .. " deep enough (" .. totalCost .. " points)")
		-- Prerequisites point upward (strictly smaller row): acyclic by construction.
		for _, n in ipairs(tree.nodes) do
			for _, req in ipairs(n.requires) do
				local r = tree.NodeById[req]
				ok(r ~= nil, id .. " prerequisite exists " .. n.id .. "<-" .. req)
				ok(r ~= nil and r.y < n.y, id .. " prerequisite above " .. n.id)
			end
		end
		-- DFS cycle check over the prerequisite graph.
		local color = {}
		local function visit(nodeId)
			if color[nodeId] == 1 then return false end
			if color[nodeId] == 2 then return true end
			color[nodeId] = 1
			for _, req in ipairs(tree.NodeById[nodeId].requires) do if not visit(req) then return false end end
			color[nodeId] = 2
			return true
		end
		local acyclic = true
		for _, n in ipairs(tree.nodes) do acyclic = acyclic and visit(n.id) end
		ok(acyclic, id .. " prerequisites acyclic")
		-- Reachability: every node (and the capstone) is reachable from the root.
		local reached, changed = {}, true
		while changed do
			changed = false
			for _, n in ipairs(tree.nodes) do
				if not reached[n.id] then
					local linked = #n.requires == 0
					for _, req in ipairs(n.requires) do if reached[req] then linked = true end end
					if linked then reached[n.id] = true; changed = true end
				end
			end
		end
		for _, n in ipairs(tree.nodes) do ok(reached[n.id], id .. " node reachable " .. n.id) end
		ok(reached[tree.capstone], id .. " capstone reachable")
	end
	for _, skill in ipairs({"Mining","Woodcutting","Fishing","Farming","Hunter","Combat","Ranged","Magic"}) do ok(skillsSeen[skill], "tree for " .. skill) end

	-- Points: 1 per level above 10, +1 per 1M XP beyond 99.
	local function prof(xp) return {xp = xp or {}, items = {}, collection = {}, coins = 0} end
	eq(P.masteryEarned(prof(), "Mining"), 0, "fresh skill earns nothing")
	eq(P.masteryEarned(prof({Mining = X[10]}), "Mining"), 0, "level 10 earns nothing")
	eq(P.masteryEarned(prof({Mining = X[11]}), "Mining"), 1, "level 11 earns one point")
	eq(P.masteryEarned(prof({Mining = X[50]}), "Mining"), 40, "level 50 earns 40")
	eq(P.masteryEarned(prof({Mining = X[99]}), "Mining"), 89, "level 99 earns 89")
	eq(P.masteryEarned(prof({Mining = X[99] + 999999}), "Mining"), 89, "just short of the first post-99 point")
	eq(P.masteryEarned(prof({Mining = X[99] + 1000000}), "Mining"), 90, "1M XP beyond 99 earns a point")
	eq(P.masteryEarned(prof({Mining = Data.MAX_XP}), "Mining"), 89 + math.floor((Data.MAX_XP - X[99]) / 1000000), "200M XP points")
	-- Tokens from collection tiers 5 and 9.
	local collector = prof()
	eq(P.masteryTokens(collector), 0, "no tokens without collections")
	collector.collection.Ore = P.collectionThreshold("Ore", 5)
	eq(P.masteryTokens(collector), 1, "tier 5 collection token")
	collector.collection.Ore = P.collectionThreshold("Ore", 9)
	eq(P.masteryTokens(collector), 2, "tier 9 collection token")
	collector.collection.Timber = P.collectionThreshold("Timber", 6)
	eq(P.masteryTokens(collector), 3, "tokens add up across collections")

	-- Unlocking: root, prerequisites, level gates, max level, costs, tokens.
	local miner = prof({Mining = X[12]})
	local pts = P.masteryPoints(miner)
	eq(pts.trees.Mining.earned, 2, "two Mining points at 12")
	eq(pts.trees.Mining.available, 2, "both available")
	eq(pts.trees.Woodcutting.available, 0, "other trees untouched")
	local okReq, whyReq = P.masteryUnlock(miner, "Mining", "QuarrySense")
	ok(not okReq and whyReq:find("Steady Pick") ~= nil, "prerequisite enforced")
	eq(P.masteryNodeState(miner, "Mining", "SteadyPick"), "available", "root available")
	eq(P.masteryNodeState(miner, "Mining", "QuarrySense"), "locked", "child locked")
	eq((P.masteryUnlock(miner, "Mining", "SteadyPick")), true, "root unlocked")
	eq(P.masteryNodeLevel(miner, "Mining", "SteadyPick"), 1, "root level 1")
	eq(P.masteryNodeState(miner, "Mining", "QuarrySense"), "available", "child opened")
	eq((P.masteryUnlock(miner, "Mining", "QuarrySense")), true, "child unlocked")
	local okPts, whyPts = P.masteryUnlock(miner, "Mining", "SteadyPick")
	ok(not okPts and whyPts:find("0 available") ~= nil, "points enforced")
	eq(P.masteryNodeState(miner, "Mining", "SteadyPick"), "partial", "root partially learned")
	eq(P.masteryPoints(miner).trees.Mining.spent, 2, "two points spent")
	local okLvl, whyLvl = P.masteryCanUnlock(prof({Mining = X[20]}), "Mining", "EmberVein")
	ok(not okLvl, "deeper node locked without its link")
	local deep = prof({Mining = X[20]})
	P.masteryUnlock(deep, "Mining", "SteadyPick"); P.masteryUnlock(deep, "Mining", "QuarrySense")
	okLvl, whyLvl = P.masteryCanUnlock(deep, "Mining", "EmberVein")
	ok(not okLvl and whyLvl:find("Mining 25") ~= nil, "skill gate enforced")
	eq(P.masteryNodeState(deep, "Mining", "EmberVein"), "open", "linked but gated node is open")
	local okBad = P.masteryUnlock(deep, "Mining", "Nope")
	eq(okBad, false, "unknown node refused")
	eq((P.masteryUnlock(deep, "Nowhere", "SteadyPick")), false, "unknown tree refused")
	-- Max level.
	local maxer = prof({Mining = X[40]})
	for _ = 1, 10 do P.masteryUnlock(maxer, "Mining", "SteadyPick") end
	eq(P.masteryNodeLevel(maxer, "Mining", "SteadyPick"), 10, "root maxed at 10")
	local okMax, whyMax = P.masteryUnlock(maxer, "Mining", "SteadyPick")
	ok(not okMax and whyMax:find("maximum") ~= nil, "max level enforced")
	eq(P.masteryNodeState(maxer, "Mining", "SteadyPick"), "owned", "maxed node owned")
	-- Tokens cover a tree's deficit; token use is derived from spending.
	local tokenUser = prof({Mining = X[11]})
	tokenUser.collection.Ore = P.collectionThreshold("Ore", 9)
	eq(P.masteryPoints(tokenUser).trees.Mining.available, 3, "own point + two tokens")
	eq(P.masteryPoints(tokenUser).trees.Fishing.available, 2, "tokens usable in any tree")
	P.masteryUnlock(tokenUser, "Mining", "SteadyPick")
	P.masteryUnlock(tokenUser, "Mining", "SteadyPick")
	local tp = P.masteryPoints(tokenUser)
	eq(tp.tokens.used, 1, "one token used")
	eq(tp.tokens.free, 1, "one token left")
	eq(tp.trees.Fishing.available, 1, "shared pool shrank")
	P.masteryUnlock(tokenUser, "Fishing", "PatientLine")
	eq(P.masteryPoints(tokenUser).tokens.free, 0, "tokens exhausted")
	eq((P.masteryUnlock(tokenUser, "Farming", "TilledRows")), false, "no points left anywhere")
	-- Cost-2 nodes.
	local mason = prof({Mining = X[60]})
	for _, step in ipairs({"SteadyPick","QuarrySense","EmberVein","EchoingSeam"}) do P.masteryUnlock(mason, "Mining", step) end
	local spentBefore = P.masterySpent(mason, "Mining")
	eq((P.masteryUnlock(mason, "Mining", "FaultLine")), true, "fault line bought")
	eq(P.masterySpent(mason, "Mining") - spentBefore, 2, "cost-2 node spends two points")

	-- Stats: no mastery = unchanged sheet; nodes add stats.
	local plain = {xp = {Mining = X[40]}, items = {}, collection = {}}
	local withEmpty = {xp = {Mining = X[40]}, items = {}, collection = {}, mastery = {}}
	local s1, s2 = P.computeStats(plain, 0), P.computeStats(withEmpty, 0)
	for key, v in pairs(s1) do if type(v) == "number" then eq(s2[key], v, "empty mastery leaves " .. key) end end
	local fortuneBefore = P.computeStats(maxer, 0).miningFortune
	eq(fortuneBefore - P.computeStats({xp = {Mining = X[40]}, items = {}, collection = {}}, 0).miningFortune, 20, "Steady Pick x10 = +20 Mining Fortune")
	local warrior = prof({Combat = X[70]})
	for _, step in ipairs({"IronGrip","BattleRhythm","KeenBlade","Bulwark","OpeningBlow","Bloodthirst"}) do eq((P.masteryUnlock(warrior, "Melee", step)), true, "melee path " .. step) end
	local ws = P.computeStats(warrior, 0)
	local wbase = P.computeStats(prof({Combat = X[70]}), 0)
	eq(ws.strength - wbase.strength, 2, "Iron Grip strength")
	eq(ws.attackSpeed - wbase.attackSpeed, 1, "Battle Rhythm attack speed")
	eq(ws.critChance - wbase.critChance, 1, "Keen Blade crit chance")
	eq(ws.defense - wbase.defense, 3, "Bulwark defense")
	eq(ws.lifesteal - wbase.lifesteal, 1, "Bloodthirst lifesteal")
	local wc = P.masteryCombat(warrior, 0)
	eq(wc.melee.firstStrike, 10, "Opening Blow first-strike chance")
	eq(wc.ranged.multishot, 1, "no volley")
	eq(wc.magic.manaThrift, 0, "no mana thrift")
	eq(next(wc.active), nil, "no running combat capstone")

	-- Harvest: no perks → identical result and no extra rolls.
	local function counted(values)
		local n, i = 0, 0
		return function() n += 1; i += 1; return values[(i - 1) % #values + 1] end, function() return n end
	end
	local gatherer = {xp = {Mining = X[60]}, items = {}, collection = {}}
	local rng1, calls1 = counted({0.999})
	local okH, plainResult = P.harvest(gatherer, "Ore", P.computeStats(gatherer, 0), rng1, 0, 100)
	eq(okH, true, "plain harvest ok")
	local A = plainResult.amount
	eq(A, 3, "plain harvest amount (236 fortune = two guaranteed extras)")
	eq(plainResult.xp, Data.ResourceTiers.Mining[1].xp, "plain harvest xp")
	eq(calls1(), 1, "plain harvest rolls fortune only")
	eq(plainResult.respawnSkip, nil, "no regrowth skip")
	eq(plainResult.regrowth, nil, "no regrowth override")
	eq(plainResult.bonus, nil, "no bonus ingot")
	gatherer.mastery = {trees = {Mining = {}}}
	local rng2, calls2 = counted({0.999})
	local _, emptyResult = P.harvest(gatherer, "Ore", P.computeStats(gatherer, 0), rng2, 0, 100)
	eq(emptyResult.amount, A, "empty tree harvest amount")
	eq(calls2(), 1, "empty tree adds no rolls")
	-- Perks: double yield, XP boost, regrowth skip, ember smelt, coin find.
	gatherer.mastery.trees.Mining = {SteadyPick = 1, QuarrySense = 5, SeamReader = 5, EmberVein = 5, EchoingSeam = 5, GlintEye = 5}
	local perks = P.masteryPerks(gatherer, "Mining", 0)
	eq(perks.doubleYield, 10, "Seam Reader 5 = 10% double")
	eq(perks.xpBoost, 10, "Quarry Sense 5 = +10% XP")
	eq(perks.autoSmelt, 15, "Ember Vein 5 = 15% smelt")
	eq(perks.respawnSkip, 20, "Echoing Seam 5 = 20% faster regrowth")
	eq(perks.coinFind, 10, "Glint Eye 5 = 10% coins")
	local _, lucky = P.harvest(gatherer, "Ore", P.computeStats(gatherer, 0), counted({0.999, 0, 0, 0, 0}), 0, 100)
	eq(lucky.amount, 2 * A, "double yield proc")
	eq(lucky.xp, math.floor(Data.ResourceTiers.Mining[1].xp * 1.1), "XP boost applied")
	eq(lucky.respawnSkip, true, "regrowth shortened")
	eq(lucky.regrowth, Data.ResourceTiers.Mining[1].respawn * 0.8, "20% faster regrowth is deterministic (no roll)")
	eq(lucky.bonus and lucky.bonus.AlloyIngot, 1, "copperstone smelts an alloy ingot")
	eq(lucky.coins, Data.ResourceTiers.Mining[1].value * 5, "coin find proc")
	local _, unlucky = P.harvest(gatherer, "Brassite", P.computeStats(gatherer, 0), counted({0.999}), 0, 100)
	eq(unlucky, "Brassite Ore requires a tier 1 pickaxe.", "tool gate still applies")
	gatherer.items.BrassPickaxe = 1
	local _, brass = P.harvest(gatherer, "Brassite", P.computeStats(gatherer, 0), counted({0.999, 0.999, 0.001, 0.999}), 0, 100)
	eq(brass.bonus and brass.bonus.BrassIngot, 1, "brassite smelts a brass ingot")
	eq(brass.amount, A, "no double without the proc")
	eq(brass.coins, nil, "no coins without the proc")
	local _, wood = P.harvest({xp = {}, items = {}, collection = {}, mastery = {trees = {Mining = {SteadyPick = 1}}}}, "Timber", {}, counted({0.999}), 0, 100)
	eq(wood.amount, 1, "mining perks never touch woodcutting")

	-- Capstones: activation, cooldown, effect window.
	local surge = {xp = {Mining = X[70]}, items = {}, collection = {}, coins = 0}
	local okNo, whyNo = P.masteryActivate(surge, "Mining", 1000)
	ok(not okNo and whyNo:find("Vein Surge") ~= nil, "capstone must be unlocked")
	for _, step in ipairs({"SteadyPick","QuarrySense","EmberVein","EchoingSeam","FaultLine","VeinSurge"}) do eq((P.masteryUnlock(surge, "Mining", step)), true, "surge path " .. step) end
	eq(P.masteryCooldown(surge, "Mining", 1000), 0, "capstone ready")
	local okA, ability = P.masteryActivate(surge, "Mining", 1000)
	eq(okA, true, "capstone fires")
	eq(ability.duration, 20, "vein surge lasts 20 s")
	eq(P.masteryCooldown(surge, "Mining", 1000), 300, "cooldown started")
	local okAgain, whyAgain = P.masteryActivate(surge, "Mining", 1100)
	ok(not okAgain and whyAgain:find("recharging") ~= nil, "cooldown enforced")
	eq(P.masteryCooldown(surge, "Mining", 1100), 200, "cooldown counts down")
	ok(P.masteryActive(surge, "Mining", 1010) ~= nil, "surge active inside window")
	eq(P.masteryActive(surge, "Mining", 1020), nil, "surge ends after 20 s")
	eq(P.masteryActive(surge, "Mining", 999), nil, "not active before it started")
	eq(P.masteryActive(surge, "Mining", 0), nil, "now=0 never counts as active")
	local _, surged = P.harvest(surge, "Ore", P.computeStats(surge, 1010), counted({0.999}), 0, 1010)
	eq(surged.amount % 2, 0, "vein surge yield even")
	eq(surged.surge, true, "surge flagged")
	local _, after = P.harvest(surge, "Ore", P.computeStats(surge, 1030), counted({0.999}), 0, 1030)
	eq(after.amount * 2, surged.amount, "vein surge doubled the yield; normal afterwards")
	eq((P.masteryActivate(surge, "Mining", 1300)), true, "capstone fires again after cooldown")
	-- Combat capstones raise stats while active.
	local berserk = prof({Combat = X[80]})
	for _, step in ipairs({"IronGrip","KeenBlade","OpeningBlow","Finisher","WeaponLore","WarcryCrescendo"}) do eq((P.masteryUnlock(berserk, "Melee", step)), true, "warcry path " .. step) end
	local calm = P.computeStats(berserk, 500)
	P.masteryActivate(berserk, "Melee", 500)
	local roaring = P.computeStats(berserk, 505)
	eq(roaring.strength - calm.strength, 60, "warcry strength")
	eq(roaring.critChance - calm.critChance, 20, "warcry crit chance")
	eq(P.computeStats(berserk, 600).strength, calm.strength, "warcry fades")
	eq(P.masteryCombat(berserk, 505).active.Melee, 515, "combat sees the warcry window")
	local archer = prof({Ranged = X[80]})
	for _, step in ipairs({"SteadyDraw","QuiverThrift","PinningShot","FletchersEye","Deadeye","Volley"}) do eq((P.masteryUnlock(archer, "Ranged", step)), true, "volley path " .. step) end
	eq(P.masteryCombat(archer, 0).ranged.arrowSave, 7, "quiver thrift 1 + fletcher's eye 1")
	P.masteryActivate(archer, "Ranged", 50)
	eq(P.masteryCombat(archer, 55).ranged.multishot, 3, "volley hits three targets")
	eq(P.masteryCombat(archer, 61).ranged.multishot, 1, "volley ends")
	local mage = prof({Magic = X[80]})
	for _, step in ipairs({"FocusedMind","InkThrift","ManaWeave","ArcaneSurge","ScribesPatience","Spellweaver","Glyphstorm"}) do eq((P.masteryUnlock(mage, "Magic", step)), true, "glyphstorm path " .. step) end
	P.masteryActivate(mage, "Magic", 10)
	local mc = P.masteryCombat(mage, 12)
	eq(mc.magic.glyphSave, 100, "glyphstorm saves every glyph (capped)")
	eq(mc.magic.manaThrift, 52, "glyphstorm halves mana on top of Mana Weave")
	-- Hunter perks on catches.
	local hunter = prof({Hunter = X[70]})
	for _, step in ipairs({"QuietStep","TrailLore","TwinSnare"}) do eq((P.masteryUnlock(hunter, "Hunter", step)), true, "hunter path " .. step) end
	local drops, xp, doubled = P.applyHuntMastery(hunter, {DownyPelt = 2}, 100, counted({0}), 0)
	eq(drops.DownyPelt, 4, "twin snare doubles drops")
	eq(xp, 102, "trail lore XP")
	eq(doubled, true, "twin catch flagged")
	local drops2, xp2, doubled2 = P.applyHuntMastery(prof(), {DownyPelt = 2}, 100, counted({0}), 0)
	eq(drops2.DownyPelt, 2, "no perks no doubling")
	eq(xp2, 100, "no perks no XP boost")
	eq(doubled2, false, "no perks not flagged")

	-- Respec: refunds, scaling cost, coins.
	local resetter = prof({Mining = X[40]})
	for _ = 1, 5 do P.masteryUnlock(resetter, "Mining", "SteadyPick") end
	local cost1 = P.masteryRespecCost(resetter, "Mining")
	eq(cost1, MA.respecCost(5, 0), "first respec price")
	eq(cost1, 1300, "1000 + 60 x 5")
	local okPoor, whyPoor = P.masteryRespec(resetter, "Mining")
	ok(not okPoor and whyPoor:find("1300") ~= nil, "respec needs coins")
	resetter.coins = 5000
	local okR, paid = P.masteryRespec(resetter, "Mining")
	eq(okR, true, "respec succeeds")
	eq(paid, 1300, "respec paid")
	eq(resetter.coins, 3700, "coins deducted")
	eq(P.masterySpent(resetter, "Mining"), 0, "points refunded")
	eq(P.masteryPoints(resetter).trees.Mining.available, 30, "all points available again")
	eq((P.masteryRespec(resetter, "Mining")), false, "empty tree cannot respec")
	for _ = 1, 5 do P.masteryUnlock(resetter, "Mining", "SteadyPick") end
	eq(P.masteryRespecCost(resetter, "Mining"), math.floor(1300 * 1.5), "second respec costs 1.5x")
	resetter.coins = 1e6
	P.masteryRespec(resetter, "Mining")
	for _ = 1, 5 do P.masteryUnlock(resetter, "Mining", "SteadyPick") end
	eq(P.masteryRespecCost(resetter, "Mining"), math.floor(1300 * 2.25), "third respec costs 2.25x")
	eq(MA.respecCost(10000, 30), MA.RESPEC_CAP, "respec cost capped")
	local reArmed = prof({Mining = X[70]})
	for _, step in ipairs({"SteadyPick","QuarrySense","EmberVein","EchoingSeam","FaultLine","VeinSurge"}) do P.masteryUnlock(reArmed, "Mining", step) end
	P.masteryActivate(reArmed, "Mining", 100)
	reArmed.coins = 1e6
	P.masteryRespec(reArmed, "Mining")
	eq(P.masteryActive(reArmed, "Mining", 105), nil, "respec ends a running capstone")
	eq(P.masteryCooldown(reArmed, "Mining", 105), 295, "respec keeps the cooldown")

	-- Migration: unknown trees/nodes, clamping, orphans, level gates, overspend.
	local legacy = prof({Mining = X[30], Fishing = X[5]})
	legacy.mastery = {trees = {Mining = {SteadyPick = 99, QuarrySense = 2.7, Ghost = 3, EchoingSeam = 1, EmberVein = 1}, Atlantis = {X = 1}, Fishing = {PatientLine = 3}},
		respecs = {Mining = "x", Fishing = 2}, cooldowns = {Mining = 50, Nowhere = 3}, active = {Mining = 5}, cape = "Nope"}
	local reset = P.masteryMigrate(legacy)
	eq(legacy.mastery.trees.Atlantis, nil, "unknown tree dropped")
	eq(legacy.mastery.trees.Mining.Ghost, nil, "unknown node dropped")
	eq(legacy.mastery.trees.Mining.EchoingSeam, nil, "node above the skill gate dropped")
	eq(legacy.mastery.respecs.Mining, nil, "bad respec count dropped")
	eq(legacy.mastery.respecs.Fishing, 2, "respec count kept")
	eq(legacy.mastery.cooldowns.Nowhere, nil, "unknown cooldown dropped")
	eq(legacy.mastery.cooldowns.Mining, 50, "cooldown kept")
	eq(legacy.mastery.active.Mining, nil, "malformed ability record dropped")
	eq(legacy.mastery.cape, nil, "invalid mantle dropped")
	eq(legacy.mastery.trees.Fishing.PatientLine, nil, "fishing overspent with no points: reset")
	ok(table.find(reset, "Fishing") ~= nil, "reset reported")
	eq(legacy.mastery.trees.Mining.SteadyPick, 10, "level clamped to max")
	eq(legacy.mastery.trees.Mining.QuarrySense, 2, "fractional level floored")
	eq(legacy.mastery.trees.Mining.EmberVein, 1, "linked node within its gate kept")
	ok(table.find(reset, "Mining") == nil, "mining within its 20 points kept")
	local greedy = prof({Mining = X[15]})
	greedy.mastery = {trees = {Mining = {SteadyPick = 10}}}
	P.masteryMigrate(greedy)
	eq(greedy.mastery.trees.Mining.SteadyPick, nil, "overspent tree reset (10 > 5 points)")
	local orphan = prof({Mining = X[60]})
	orphan.mastery = {trees = {Mining = {QuarrySense = 1}}}
	P.masteryMigrate(orphan)
	eq(orphan.mastery.trees.Mining.QuarrySense, nil, "orphaned node dropped")
	local clean = prof({Mining = X[60]})
	clean.mastery = {trees = {Mining = {SteadyPick = 3, SeamReader = 2}}}
	eq(#P.masteryMigrate(clean), 0, "valid tree untouched")
	eq(clean.mastery.trees.Mining.SteadyPick, 3, "valid levels kept")
	eq(#P.masteryMigrate(prof()), 0, "no mastery table: nothing to migrate")

	-- View (snapshot) states.
	local view = P.masteryView(maxer, 0)
	eq(view.trees.Mining.states.SteadyPick, "owned", "view owned")
	eq(view.trees.Mining.states.QuarrySense, "available", "view available")
	eq(view.trees.Mining.states.Stoneskin, "locked", "view locked")
	eq(view.trees.Mining.nodes.SteadyPick, 10, "view levels")
	eq(view.trees.Mining.available, 20, "view points")
	eq(view.trees.Mining.respecCost, MA.respecCost(10, 0), "view respec cost")
	eq(view.trees.Mining.capstone, false, "view capstone flag")
	eq(view.trees.Fishing.states.PatientLine, "open", "view open without points")

	-- Milestones, titles and mantles.
	for _, skill in ipairs(Data.SkillOrder) do
		local list = MA.milestones(skill)
		eq(#list, 5, skill .. " has five milestones")
		eq(list[5].kind, "cape", skill .. " mantle at 99")
		ok(next(list[5].stats) ~= nil, skill .. " mantle perk")
		for stat in pairs(list[5].stats) do ok(Data.Stats[stat] ~= nil, skill .. " mantle stat " .. stat) end
		eq(list[1].coins, Data.levelCoinReward(10), skill .. " milestone coins")
	end
	eq(MA.title("Mining", 9), nil, "no title before 10")
	eq(MA.title("Mining", 10), "Fledgling Prospector", "first title")
	eq(MA.title("Mining", 99), "Grand Prospector", "99 title")
	local ms = P.milestones(prof({Mining = X[50]}), "Mining")
	eq(ms[3].reached, true, "level 50 milestone reached")
	eq(ms[4].reached, false, "level 75 milestone pending")
	eq(ms[3].kind, "aura", "level 50 aura")
	local caped = prof({Mining = X[99]})
	caped.mastery = {cape = "Mining"}
	local capeBase = P.computeStats(prof({Mining = X[99]}), 0)
	local capeStats = P.computeStats(caped, 0)
	eq(capeStats.miningFortune - capeBase.miningFortune, 25, "mantle perk while worn")
	eq(P.masteryCape(caped), "Mining", "mantle worn")
	caped.mastery.cape = "Fishing"
	eq(P.masteryCape(caped), nil, "mantle needs level 99")
	eq(P.computeStats(caped, 0).miningFortune, capeBase.miningFortune, "unearned mantle grants nothing")
	print("PASS: " .. (checks - before) .. " skill mastery assertions.")
end

-- Mastery balance (review fixes): capstone/proc yield joins the base before
-- fortune and never stacks; realistic max single-click yield stays <= 2.5x the
-- pre-mastery max; Quick regrowth has a floor; capped Keen Nose Magic Find.
do
	local before = checks
	local MA = Data.Mastery
	local GATHER = {"Mining","Woodcutting","Fishing","Farming"}
	local function always(v) return function() return v end end
	-- First call (the fortune remainder) misses, every later roll (procs) hits.
	local function missThenHit() local first = true; return function() if first then first = false; return 0.9999 end return 0 end end
	local function fullTree(treeId)
		local out = {}
		for _, n in ipairs(MA.TreeById[treeId].nodes) do out[n.id] = n.max end
		return out
	end
	local function maxedXp()
		local xp = {}
		for skill in pairs(Data.Skills) do xp[skill] = Data.MAX_XP end
		for skill in pairs(Data.ResourceTiers) do xp[skill] = Data.MAX_XP end
		return xp
	end
	-- Pre-mastery "max fortune sources": level-99 sheet, the best tool of the kind
	-- with max Fortune enchant, plus the best tool reforge and every accessory carrying the stat.
	local function gearAllowance(skill)
		local stat, kind = Data.FortuneStat[skill], Data.ToolKind[skill]
		local reforge = 0
		for _, rf in pairs(Data.Gear.Reforges) do
			if rf.category == "tool" and rf.stats and rf.stats.fortune and (rf.toolKinds == nil or table.find(rf.toolKinds, kind)) then
				reforge = math.max(reforge, rf.stats.fortune)
			end
		end
		local accessories = 0
		for _, def in pairs(Data.Items) do
			if def.kind == "accessory" and def.stats and def.stats[stat] then accessories += def.stats[stat] end
		end
		return reforge + accessories
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
		for _, ev in pairs(Data.Events) do
			if ev.skill == skill then bonus = math.max(bonus, ev.gatherBonus or 0); mult = math.max(mult, ev.featuredMult or 1) end
		end
		return bonus, mult
	end
	local NOW = 5000
	local function gatherer(skill, mastered)
		local tool = bestTool(skill)
		local p = {xp = maxedXp(), items = {[tool] = 1}, collection = {}, coins = 0, enchants = {[tool] = {Fortune = Data.Enchants.Fortune.maxLevel}}}
		if mastered then
			local treeId = MA.TreeOfSkill[skill]
			p.mastery = {trees = {[treeId] = fullTree(treeId)}, active = {[treeId] = {started = NOW - 1, expires = NOW + 10}}, cape = skill}
		end
		return p
	end
	local function sheet(p, skill)
		local stats = P.computeStats(p, NOW)
		stats[Data.FortuneStat[skill]] += gearAllowance(skill)
		return stats
	end
	-- Worst case per click: every roll succeeds (fortune remainder, proc), capstone
	-- running, tier-1 node with every legacy/season/event base bonus, festival featured.
	local function clickMax(skill, mastered, rng)
		local p = gatherer(skill, mastered)
		local r = Data.ResourceTiers[skill][1]
		local evBonus, evMult = maxEventFor(skill)
		local bonus = 1 + 1 + 1 + 1 + evBonus + (if r.id == "Ore" then 2 else 0) -- tier 1, Skyreach, featured, season, event, reinforced pick
		local okH, res = P.harvest(p, r.id, sheet(p, skill), rng or always(0), bonus, NOW)
		assert(okH, "max-yield harvest " .. skill .. ": " .. tostring(res))
		return res.amount * evMult, res.fortune, res
	end
	print("Max single-click yield (all layers stacked; tier-1 node, festival featured):")
	print("  skill        fortune pre->post   pre   post   ratio   (remainder-miss ratio)")
	for _, skill in ipairs(GATHER) do
		local pre, f0 = clickMax(skill, false)
		local post, f1, res = clickMax(skill, true)
		local ratio = post / pre
		local missRatio = clickMax(skill, true, missThenHit()) / clickMax(skill, false, missThenHit())
		print(string.format("  %-12s %4d -> %4d       %4d  %5d   %.2fx   (%.2fx)", skill, f0, f1, pre, post, ratio, missRatio))
		ok(res.surge == true and res.multiplied == nil, skill .. ": capstone running, proc does not stack on top")
		-- Under 100 mastery fortune crosses at most one fortune step, so with a x2
		-- cap the ratio stays <= 2 x 6/5 = 2.4 whatever the gear (F0 >= 400 at 99).
		ok(f1 - f0 < 100, skill .. " mastery fortune (tree + mantle) " .. (f1 - f0) .. " < 100")
		ok(ratio <= 2.5, skill .. " max-yield ratio " .. string.format("%.2f", ratio) .. " <= 2.5")
		ok(missRatio <= 2.5, skill .. " remainder-miss ratio " .. string.format("%.2f", missRatio) .. " <= 2.5")
		-- Neither the capstone nor any proc exceeds x2 (they never stack).
		local perks = P.masteryPerks(gatherer(skill, true), MA.TreeOfSkill[skill], NOW)
		ok((perks.yieldMult or 1) <= 2, skill .. " capstone yieldMult <= 2")
		ok((perks.tripleYield or 0) == 0, skill .. " no triple proc above a x2 capstone")
	end

	-- Capstone and proc do not multiply: a proc during a surge = the surge alone.
	local farmer = gatherer("Farming", true)
	local fs = P.computeStats(farmer, NOW)
	local _, surgeOnly = P.harvest(farmer, "Herb", fs, always(0.9999), 0, NOW)
	local _, surgeProc = P.harvest(farmer, "Herb", fs, missThenHit(), 0, NOW)
	eq(surgeProc.amount, surgeOnly.amount, "double proc during a capstone adds nothing")
	eq(surgeProc.surge, true, "surge flagged")
	local _, plainProc = P.harvest(farmer, "Herb", fs, missThenHit(), 0, NOW + 100)
	eq(plainProc.multiplied, 2, "proc doubles outside the capstone")
	eq(plainProc.amount, surgeOnly.amount, "proc x2 equals surge x2")
	-- The multiplier joins the base before fortune: (1 + bonus) x 2, then the fortune factor once.
	local _, joined = P.harvest(farmer, "Herb", {farmingFortune = 0}, always(0.9999), 2, NOW)
	eq(joined.amount, (1 + 2) * 2 * (1 + math.floor(joined.fortune / 100)), "capstone multiplies the base, fortune applies once")

	-- Pets depth: the summoned pet's doubled harvest is one more x2 candidate in
	-- gatherYieldMult (max with capstone and procs, never stacked). Max single
	-- click with every roll hitting (fortune, mastery proc, pet proc) stays
	-- <= 2.5x the pre-mastery max; that baseline keeps the pet's stats (its
	-- fortune is a pre-mastery source) but not its proc.
	local PDp = Data.PetDepth
	print("Max single-click yield with a doubled-harvest pet (Legendary 100):")
	for _, skill in ipairs(GATHER) do
		local petId, best = nil, 0
		for _, def in ipairs(Data.Pets) do
			local v = PDp.effects(def, 100, "Legendary").gather[skill] or 0
			if v > best then petId, best = def.id, v end
		end
		ok(petId ~= nil, skill .. " has a doubled-harvest pet")
		local function click(mastered, proc, at, rng)
			local p = gatherer(skill, mastered)
			p.pets = {{id = petId, level = 100, xp = 0, rarity = "Legendary"}}
			p.activePet = 1
			local stats = sheet(p, skill)
			if not proc then p.activePet = nil end
			local r = Data.ResourceTiers[skill][1]
			local evBonus, evMult = maxEventFor(skill)
			local bonus = 1 + 1 + 1 + 1 + evBonus + (if r.id == "Ore" then 2 else 0)
			local okH, res = P.harvest(p, r.id, stats, rng or always(0), bonus, at or NOW)
			assert(okH, "pet max-yield harvest " .. skill .. ": " .. tostring(res))
			return res.amount * evMult, res
		end
		local pre = click(false, false)
		local petOnly, petRes = click(false, true)
		local capPet, capRes = click(true, true)
		local procPet, procRes = click(true, true, NOW + 100)
		local missPet = click(true, true, NOW + 100, missThenHit())
		local missPre = click(false, false, NOW, missThenHit())
		print(string.format("  %-12s pre %5d  pet %5d  capstone+pet %5d  proc+pet %5d  (%.2fx / %.2fx)", skill, pre, petOnly, capPet, procPet, capPet / pre, procPet / pre))
		ok(petRes.petDouble == true and petOnly == 2 * pre, skill .. " pet alone doubles the pre-mastery click")
		ok(capRes.surge == true and capRes.petDouble == nil and capRes.multiplied == nil, skill .. " capstone running: the pet proc does not stack")
		ok(not (procRes.multiplied and procRes.petDouble), skill .. " mastery proc and pet proc never both apply")
		ok(capPet / pre <= 2.5, skill .. " capstone+pet max-yield ratio " .. string.format("%.2f", capPet / pre) .. " <= 2.5")
		ok(procPet / pre <= 2.5, skill .. " proc+pet max-yield ratio " .. string.format("%.2f", procPet / pre) .. " <= 2.5")
		ok(missPet / missPre <= 2.5, skill .. " pet remainder-miss ratio " .. string.format("%.2f", missPet / missPre) .. " <= 2.5")
		-- The multiplier itself never exceeds x2 with a pet.
		local pm = gatherer(skill, true)
		pm.pets = {{id = petId, level = 100, xp = 0, rarity = "Legendary"}}
		pm.activePet = 1
		for _, at in ipairs({NOW, NOW + 100}) do
			local m = P.gatherYieldMult(pm, {resource = {skill = skill}}, always(0), at)
			ok(m <= 2, skill .. " yield multiplier with pet <= 2 (" .. m .. ")")
		end
	end

	-- Regrowth: shortened to a floor, never instant.
	eq(P.regrowthTime(15, 0), 15, "no skip keeps the timer")
	eq(P.regrowthTime(15, 20), 12, "20% faster")
	eq(P.regrowthTime(15, 100), 3.75, "full skip floors at 25% of the base")
	eq(P.regrowthTime(3, 100), 2, "full skip floors at 2 s on short nodes")
	eq(P.regrowthTime(1.5, 100), 1.5, "the floor never lengthens a short node")
	eq(P.regrowthTime(15, 500), 3.75, "over-100 skip clamps")
	ok(MA.PASSIVE_CAPS.respawnSkip <= 50, "passive regrowth capped at <= 50%")
	local swift = MA.TreeById.Woodcutting.NodeById.SwiftSaplings
	local savedSwift = swift.perks.respawnSkip
	swift.perks.respawnSkip = 40
	eq(P.masteryPerks({xp = maxedXp(), items = {}, collection = {}, mastery = {trees = {Woodcutting = {SwiftSaplings = 5}}}}, "Woodcutting", 0).respawnSkip,
		MA.PASSIVE_CAPS.respawnSkip, "passive regrowth total capped")
	swift.perks.respawnSkip = savedSwift
	-- Throughput: harvest the moment the node is ready (0.65 s click floor),
	-- over the capstone window and a full cooldown cycle, vs no mastery. Items
	-- per harvest = the mastery multiplier only (fortune is covered above):
	-- capstone yieldMult, else 1 + the expected double proc.
	local CLICK = 0.65
	print("Gathering throughput vs no mastery (worst node per skill):")
	for _, skill in ipairs(GATHER) do
		local treeId = MA.TreeOfSkill[skill]
		local tree = MA.TreeById[treeId]
		local ability = tree.NodeById[tree.capstone].ability
		local p = {xp = maxedXp(), items = {}, collection = {}, mastery = {trees = {[treeId] = fullTree(treeId)}, active = {[treeId] = {started = 0, expires = ability.duration}}}}
		local worst, worstWindow = 0, 0
		for _, r in ipairs(Data.ResourceTiers[skill]) do
			local function run(span, mastered)
				local t, items, harvests = 0, 0, 0
				while t < span do
					local perks = if mastered then P.masteryPerks(p, treeId, t) else {}
					items += math.max(perks.yieldMult or 1, 1 + math.min(100, perks.doubleYield or 0) / 100)
					harvests += 1
					t += math.max(CLICK, P.regrowthTime(r.respawn, perks.respawnSkip or 0))
				end
				return items, harvests
			end
			local windowItems, windowHarvests = run(ability.duration, true)
			local floor = math.min(r.respawn, math.max(MA.REGROWTH_FLOOR, r.respawn * MA.REGROWTH_FLOOR_SHARE))
			ok(windowHarvests <= math.ceil(ability.duration / floor), skill .. " " .. r.id .. " window respects the regrowth floor")
			local cycle = run(ability.cooldown, true) / run(ability.cooldown, false)
			worst = math.max(worst, cycle)
			worstWindow = math.max(worstWindow, windowItems / run(ability.duration, false))
			ok(cycle <= 2.0, skill .. " " .. r.id .. " cooldown-cycle throughput " .. string.format("%.2f", cycle) .. "x <= 2x")
		end
		print(string.format("  %-12s capstone window <= %.2fx, full cooldown cycle <= %.2fx", skill, worstWindow, worst))
	end
	-- Timber Tempest regression: 30 s on a 15 s node is a handful of harvests, not ~46.
	local feller = {xp = maxedXp(), items = {}, collection = {}, mastery = {trees = {Woodcutting = fullTree("Woodcutting")}, active = {Woodcutting = {started = 0, expires = 30}}}}
	local regrow = P.regrowthTime(15, P.masteryPerks(feller, "Woodcutting", 10).respawnSkip)
	ok(regrow >= 3.75, "Timber Tempest regrowth on a 15 s node >= 3.75 s (" .. regrow .. ")")
	ok(math.ceil(30 / regrow) <= 8, "Timber Tempest: at most 8 harvests of a 15 s node in 30 s")
	feller.items.CelestialHatchet = 1
	local okLog, logs = P.harvest(feller, "AetherheartLog", P.computeStats(feller, 10), always(0.9999), 0, 10)
	ok(okLog and logs.regrowth == regrow and logs.regrowth > 0, "capstone harvest still carries a regrowth timer")

	-- Keen Nose / Packmaster: Magic Find on catches capped at 15.
	local tracker = {xp = maxedXp(), items = {}, collection = {}, mastery = {trees = {Hunter = fullTree("Hunter")}}}
	local hp = P.masteryPerks(tracker, "Hunter", 0)
	ok(hp.rareFind > 0 and hp.rareFind <= 15, "full Hunter tree Magic Find <= 15 (" .. tostring(hp.rareFind) .. ")")
	eq(MA.PERK_CAPS.rareFind, 15, "rareFind cap")
	local nose = MA.TreeById.Hunter.NodeById.KeenNose
	local savedNose = nose.perks.rareFind
	nose.perks.rareFind = 40
	eq(P.masteryPerks(tracker, "Hunter", 0).rareFind, 15, "rareFind folded into the capped perk set")
	nose.perks.rareFind = savedNose
	print("PASS: " .. (checks - before) .. " mastery balance assertions.")
end

-- Gear depth (Data.Gear): reforges, stars, tomes and their stat layers.
do
	local before = checks
	local G = Data.Gear
	local near = function(a, b, case) ok(math.abs((a or 0) - (b or 0)) < 1e-6, case .. " expected " .. tostring(b) .. ", got " .. tostring(a)) end
	-- Data integrity.
	local borrowed = {Sharp=true,Spicy=true,Legendary=true,Fabled=true,Heroic=true,Fierce=true,Wise=true,Pure=true,Godly=true,Itchy=true,
		Bizarre=true,Ominous=true,Pleasant=true,Shiny=true,Strange=true,Zealous=true,Silky=true,Bloody=true,Keen=true,Lucky=true,Unreal=true,
		Precise=true,Rapid=true,Deadly=true,Fine=true,Grand=true,Hasty=true,Neat=true,Awkward=true,Fleet=true,Blessed=true,Fruitful=true,
		Magnetic=true,Refined=true,Stellar=true,Auspicious=true,Bountiful=true,Ancient=true,Necrotic=true,Renowned=true,Titanic=true,Smart=true,
		Clean=true,Fast=true,Heavy=true,Light=true,Gentle=true,Odd=true,Rich=true,Epic=true,Fair=true,Strong=true,Giant=true,Hurtful=true,
		Withered=true,Spiritual=true,Mossy=true,Rooted=true,Blooming=true,Salty=true,Treacherous=true,Submerged=true,Reinforced=true,Perfect=true,
		Empowered=true,Jaded=true,Fortunate=true,Lush=true,Robust=true,Zooming=true,Headstrong=true,Glistening=true,Stiff=true,Hefty=true,Mythic=true}
	local extraKeys = {damage=true,fortune=true,magicalPower=true}
	local names, pools, stones = {}, {}, {}
	for id, r in Data.Gear.Reforges do
		eq(r.id, id, "reforge id " .. id)
		ok(table.find(G.Categories, r.category) ~= nil, "reforge category " .. id)
		ok(not names[r.name] and not borrowed[r.name], "reforge name original and unique " .. r.name)
		ok(Data.Sets[r.name] == nil and Data.Items[id] == nil, "reforge name does not collide " .. id)
		names[r.name] = true
		ok(next(r.stats) ~= nil, "reforge has stats " .. id)
		for stat, v in r.stats do ok((Data.Stats[stat] ~= nil or extraKeys[stat]) and v > 0, "reforge stat " .. id .. ":" .. stat) end
		if r.stone then
			stones[id] = r.stone
			local s = Data.Items[r.stone]
			ok(s ~= nil and s.kind == "material" and s.reforgeStone == id, "stone item " .. r.stone)
			eq(G.StoneFor[id], r.stone, "stone lookup " .. id)
			ok(Data.Economy.isCommodity(r.stone), "stones trade on the Bazaar " .. r.stone)
		else
			pools[r.category] = (pools[r.category] or 0) + 1
		end
		if r.toolKinds then for _, kind in r.toolKinds do ok(r.category == "tool" and table.find({"Pickaxe","Hatchet","Rod","Hoe"}, kind) ~= nil, "tool kinds " .. id) end end
	end
	for _, category in G.Categories do
		ok(pools[category] >= 6 and pools[category] <= 8, category .. " has 6-8 anvil reforges")
		local hasStone = false
		for _, id in G.ReforgeOrder[category] do if G.Reforges[id].stone then hasStone = true end end
		ok(hasStone, category .. " has a stone reforge")
		eq(G.CategoryNames[category] ~= nil, true, "category name " .. category)
	end
	ok(#Data.RarityOrder == 6, "six rarities")
	for i, rarity in Data.RarityOrder do
		ok(G.RarityScale[rarity] ~= nil and G.ReforgeCost[rarity] ~= nil, "rarity tables " .. rarity)
		if i > 1 then
			ok(G.RarityScale[rarity] > G.RarityScale[Data.RarityOrder[i - 1]], "reforge scale rises " .. rarity)
			ok(G.ReforgeCost[rarity] > G.ReforgeCost[Data.RarityOrder[i - 1]], "anvil cost rises " .. rarity)
		end
	end
	-- Every stone, essence and tome drops somewhere (monsters, sea creatures, slayers, dungeon chests).
	local sources = {}
	local function scan(list, where)
		for _, d in list do
			ok(d.chance > 0 and d.chance <= 1 and d.min >= 1 and d.max >= d.min and Data.Items[d.item] ~= nil, "drop row " .. where .. ":" .. d.item)
			sources[d.item] = (sources[d.item] or 0) + 1
		end
	end
	for id, m in Data.Monsters do scan(m.drops, id) end
	for id, sc in Data.SeaCreatures do scan(sc.drops, id) end
	for line, s in Data.Slayers do for t, tier in s.tiers do scan(tier.drops, line .. t) end end
	for _, f in Data.DungeonFloors do scan(f.chest, f.name) end
	for _, stone in stones do ok((sources[stone] or 0) >= 1, "stone drops " .. stone) end
	for _, id in {"WildheartEssence","BrinelightEssence","ObservatoryEssence","TemperingTome","MasterworkTome"} do
		ok((sources[id] or 0) >= 1 and Data.Items[id].kind == "material", "upgrade material drops " .. id)
	end
	for _, line in Data.SlayerOrder do
		for t, tier in Data.Slayers[line].tiers do
			local found = false
			for _, d in tier.drops do if d.item == "WildheartEssence" then found = d.chance < 1 end end
			ok(found, "slayer essence " .. line .. t)
		end
	end
	for _, id in Data.SeaCreatureOrder do
		local found = false
		for _, d in Data.SeaCreatures[id].drops do if d.item == "BrinelightEssence" then found = d.chance < 1 end end
		ok(found, "sea creature essence " .. id)
	end
	ok(Data.Recipes.TemperingTome ~= nil and Data.Recipes.TemperingTome.repeatable, "Tempering Tome recipe")
	-- Categories.
	eq(G.category(Data.Items.BrassSword), "melee", "sword is melee")
	eq(G.category(Data.Items.Stormblade), "melee", "legacy blade is melee")
	eq(G.category(Data.Items.MeadowLongbow), "ranged", "bow category")
	eq(G.category(Data.Items.WindpineStaff), "magic", "staff category")
	eq(G.category(Data.Items.BrassHelm), "armor", "armor category")
	eq(G.category(Data.Items.BrassPickaxe), "tool", "tool category")
	eq(G.category(Data.Items.MeadowCharm), "accessory", "accessory category")
	eq(G.category(Data.Items.Ore), nil, "resources are not gear")
	eq(G.category(Data.Items.TemperingTome), nil, "tomes are not gear")
	eq(G.category(nil), nil, "missing item")
	-- Reforge stat scaling by rarity (Common x1 ... Mythic x5).
	near(G.reforgeStats("Honed", "Common").critChance, 1, "Honed common")
	near(G.reforgeStats("Honed", "Uncommon").critDamage, 4.5, "Honed uncommon")
	near(G.reforgeStats("Honed", "Legendary").critChance, 4, "Honed legendary")
	near(G.reforgeStats("Honed", "Mythic").critDamage, 15, "Honed mythic")
	near(G.reforgeStats("Gleaming", "Epic").magicalPower, 3, "accessory reforge Magical Power")
	near(G.reforgeStats("Thrifty", "Rare", "Mining").miningFortune, 8, "tool fortune maps to the skill")
	eq(G.reforgeStats("Thrifty", "Rare", "Mining").fortune, nil, "no raw fortune key with a skill")
	near(G.reforgeStats("Thrifty", "Rare").fortune, 8, "raw fortune without a skill")
	eq(next(G.reforgeStats("Nope", "Rare")), nil, "unknown reforge has no stats")
	-- Anvil pools and rolls.
	local swordPool = G.reforgePool(Data.Items.BrassSword)
	eq(#swordPool, pools.melee, "melee pool size")
	for _, id in swordPool do ok(not G.Reforges[id].stone, "pool excludes stones " .. id) end
	local pickPool, rodPool = G.reforgePool(Data.Items.BrassPickaxe), G.reforgePool(Data.Items.BrassRod)
	ok(table.find(pickPool, "Brined") == nil and table.find(pickPool, "Verdant") == nil, "pickaxe pool skips rod/hoe reforges")
	ok(table.find(rodPool, "Brined") ~= nil and table.find(rodPool, "Verdant") == nil, "rod pool includes Brined")
	ok(table.find(G.reforgePool(Data.Items.BrassHoe), "Verdant") ~= nil, "hoe pool includes Verdant")
	eq(G.rollReforge(Data.Items.BrassSword, nil, 0), swordPool[1], "roll 0 picks the first")
	eq(G.rollReforge(Data.Items.BrassSword, nil, 0.9999), swordPool[#swordPool], "roll ~1 picks the last")
	for i = 0, 40 do
		local r = i / 41
		local picked = G.rollReforge(Data.Items.BrassSword, swordPool[1], r)
		ok(picked ~= swordPool[1] and table.find(swordPool, picked) ~= nil, "reroll never repeats " .. i)
	end
	eq(G.rollReforge(Data.Items.Ore, nil, 0.5), nil, "non-gear cannot roll")
	ok(G.reforgeFits("Emberwrought", Data.Items.BrassSword), "melee stone fits a sword")
	ok(not G.reforgeFits("Emberwrought", Data.Items.MeadowLongbow), "melee stone does not fit a bow")
	ok(not G.reforgeFits("Tidebound", Data.Items.BrassPickaxe), "rod stone does not fit a pickaxe")
	ok(G.reforgeFits("Tidebound", Data.Items.BrassRod), "rod stone fits a rod")
	ok(G.reforgeFits("Deepvein", Data.Items.BrassHoe), "unrestricted tool stone fits any tool")
	-- Costs.
	local empty = {reforges = {}, stars = {}, books = {}}
	eq(G.reforgeCost(empty, "Blade"), 250, "common anvil cost")
	eq(G.reforgeCost(empty, "SunsteelSword"), 1000, "rare anvil cost")
	eq(G.reforgeCost({books = {SunsteelSword = {masterwork = true}}}, "SunsteelSword"), 2500, "masterwork raises anvil cost")
	local sc1 = G.starCost(Data.Items.BrassSword, 1)
	eq(sc1.essence, "WildheartEssence", "weapons star with Wildheart Essence")
	eq(sc1.amount, 12, "star 1 essence (uncommon)")
	eq(sc1.coins, 400, "star 1 coins (uncommon)")
	eq(G.starCost(Data.Items.BrassSword, 5).amount, 100, "star 5 essence (uncommon)")
	eq(G.starCost(Data.Items.BrassSword, 5).coins, 10000, "star 5 coins (uncommon)")
	eq(G.starCost(Data.Items.EclipseGlaive, 1).essence, "ObservatoryEssence", "dungeon gear stars with Observatory Essence")
	eq(G.starCost(Data.Items.EclipseGlaive, 1).amount, 17, "dungeon epic star 1 essence")
	eq(G.starCost(Data.Items.BrassRod, 1).essence, "BrinelightEssence", "tools star with Brinelight Essence")
	eq(G.starCost(Data.Items.Blade, 6), nil, "no sixth star")
	local total = 0
	for k = 1, 5 do total += G.starCost(Data.Items.Blade, k).amount end
	eq(total, 200, "common 5-star essence total")
	-- Stars and tomes.
	local s3 = G.starStats(Data.Items.BrassSword, 3)
	near(s3.damage, 2.4, "3 stars: +6% damage")
	near(s3.strength, 0.6, "3 stars: +6% strength")
	near(G.starStats(Data.Items.LenswrightSaber, 2).damage, 6.8, "dungeon stars: +4% each")
	eq(G.starPercent(Data.Items.LenswrightSaber), 4, "dungeon star percent")
	eq(G.starPercent(Data.Items.BrassSword), 2, "normal star percent")
	eq(next(G.starStats(Data.Items.BrassSword, 0)), nil, "no stars, no bonus")
	local t10 = G.tomeStats(Data.Items.BrassSword, 10)
	eq(t10.damage, 20, "10 tomes: +20 damage")
	eq(t10.strength, 20, "10 tomes: +20 strength")
	eq(G.tomeStats(Data.Items.BrassHelm, 3).health, 12, "armor tome health")
	eq(G.tomeStats(Data.Items.BrassHelm, 3).defense, 6, "armor tome defense")
	eq(G.tomeStats(Data.Items.MeadowLongbow, 2).rangedStrength, 4, "bow tome ranged strength")
	eq(G.tomeStats(Data.Items.WindpineStaff, 2).intelligence, 8, "staff tome intelligence")
	eq(next(G.tomeStats(Data.Items.BrassPickaxe, 5)), nil, "tools cannot be tempered")
	ok(not G.canTemper("accessory") and not G.canStar("accessory") and G.canStar("tool") and G.canTemper("magic"), "layer rules per category")
	-- Caps and malformed state.
	eq(G.starsOf({stars = {BrassSword = 99}}, "BrassSword"), 5, "stars capped at 5")
	eq(G.starsOf({stars = {BrassSword = -3}}, "BrassSword"), 0, "negative stars")
	eq(G.starsOf({stars = {BrassSword = "x"}}, "BrassSword"), 0, "malformed stars")
	eq(G.starsOf(nil, "BrassSword"), 0, "no gear state")
	eq(G.bookOf({books = {BrassSword = {tempering = 50}}}, "BrassSword").tempering, 10, "tempering capped at 10")
	eq(G.bookOf({books = {BrassSword = 4}}, "BrassSword").tempering, 0, "malformed book")
	eq(G.bookOf({books = {BrassSword = {masterwork = "yes"}}}, "BrassSword").masterwork, false, "masterwork must be true")
	eq(G.reforgeOf({reforges = {BrassSword = "Nope"}}, "BrassSword"), nil, "unknown reforge ignored")
	eq(G.breakdown({reforges = {BrassSword = "Lucid"}}, "BrassSword").reforge, nil, "mismatched reforge ignored")
	-- Masterwork rarity bump.
	eq(G.bumpRarity("Common"), "Uncommon", "bump common")
	eq(G.bumpRarity("Legendary"), "Mythic", "bump legendary")
	eq(G.bumpRarity("Mythic"), "Mythic", "mythic is the cap")
	local mw = {reforges = {SunsteelSword = "Honed"}, stars = {}, books = {SunsteelSword = {masterwork = true}}}
	eq(G.effectiveRarity(mw, "SunsteelSword"), "Epic", "masterwork Rare -> Epic")
	eq(P.effectiveRarity(mw, "SunsteelSword"), "Epic", "Progression.effectiveRarity")
	eq(P.effectiveRarity(empty, "SunsteelSword"), "Rare", "base rarity without a tome")
	eq(P.effectiveRarity(empty, "Nope"), "Common", "unknown item rarity")
	near(G.breakdown(mw, "SunsteelSword").reforgeStats.critChance, 3, "masterwork scales the reforge (Epic x3)")
	-- Breakdown, totals, names.
	local layered = {reforges = {BrassSword = "Vicious"}, stars = {BrassSword = 3}, books = {BrassSword = {tempering = 4}}}
	local b = G.breakdown(layered, "BrassSword")
	eq(b.reforge, "Vicious", "breakdown reforge")
	eq(b.stars, 3, "breakdown stars")
	eq(b.tempering, 4, "breakdown tempering")
	near(b.total.strength, 4.5 + 0.6 + 8, "strength = reforge + stars + tomes")
	near(b.total.damage, 2.4 + 8, "damage = stars + tomes")
	near(b.total.critDamage, 1.5, "crit damage from the reforge")
	eq(G.displayName(layered, "BrassSword"), "Vicious Brass Sword ★★★", "display name")
	eq(G.displayName(empty, "BrassSword"), "Brass Sword", "plain display name")
	ok(G.isUpgraded(layered, "BrassSword") and not G.isUpgraded(empty, "BrassSword"), "isUpgraded")
	ok(G.isUpgraded({books = {Blade = {masterwork = true}}}, "Blade") and P.isUpgraded({stars = {Blade = 1}}, "Blade"), "any layer counts as upgraded")
	-- computeStats folds the layers in only for equipped / active / best gear.
	local function hero(extra)
		local p = {xp = {Combat = Data.XP_TABLE[60], Mining = Data.XP_TABLE[20], Fishing = Data.XP_TABLE[20]}, collection = {}, items = {BrassSword = 1, BrassHelm = 1, BrassPickaxe = 1, BrassRod = 1, MeadowCharm = 1, QuarryTalisman = 1, SunsteelSword = 1},
			equipment = {weapon = "BrassSword", helmet = "BrassHelm"}, accessoryBag = {"MeadowCharm", "QuarryTalisman"}, reforges = {}, stars = {}, books = {}}
		for k, v in extra or {} do p[k] = v end
		return p
	end
	local base = P.computeStats(hero(), 0)
	local plain = P.computeStats({xp = hero().xp, collection = {}, items = hero().items, equipment = hero().equipment, accessoryBag = hero().accessoryBag}, 0)
	for _, stat in {"health","defense","strength","critChance","critDamage","damage","magicalPower","miningFortune","seaCreatureChance"} do
		eq(base[stat], plain[stat], "no upgrades = unchanged stats (" .. stat .. ")")
	end
	local up = P.computeStats(hero(layered), 0)
	near(up.strength - base.strength, b.total.strength, "weapon layers reach computeStats (strength)")
	near(up.damage - base.damage, b.total.damage, "weapon layers reach computeStats (damage)")
	local unequipped = P.computeStats(hero({reforges = {SunsteelSword = "Vicious"}, stars = {SunsteelSword = 5}, books = {SunsteelSword = {tempering = 10}}}), 0)
	eq(unequipped.strength, base.strength, "unequipped upgrades do nothing")
	local armored = P.computeStats(hero({reforges = {BrassHelm = "Bulwark"}, books = {BrassHelm = {tempering = 2}}}), 0)
	eq(armored.defense - base.defense, 6 + 4, "armor reforge + tomes defense")
	eq(armored.health - base.health, 8, "armor tome health")
	local tooled = P.computeStats(hero({reforges = {BrassPickaxe = "Thrifty", BrassRod = "Brined"}, stars = {BrassPickaxe = 5}}), 0)
	near(tooled.miningFortune - base.miningFortune, 6 + 3, "best pickaxe reforge + stars fortune")
	near(tooled.seaCreatureChance - base.seaCreatureChance, 0.5, "rod reforge sea creature chance (rounded)")
	near(tooled.fishingFortune - base.fishingFortune, 3, "rod reforge fishing fortune")
	-- Harvest picks the upgraded fortune up through the stat sheet.
	local miner = hero({reforges = {BrassPickaxe = "Thrifty"}})
	miner.xp.Mining = Data.XP_TABLE[20]
	local plainMiner = hero()
	plainMiner.xp.Mining = Data.XP_TABLE[20]
	local okH, res = P.harvest(miner, "Ore", P.computeStats(miner, 0), seq({0.999}))
	local okB, resBase = P.harvest(plainMiner, "Ore", P.computeStats(plainMiner, 0), seq({0.999}))
	ok(okH and okB, "harvests succeed")
	near(res.fortune - resBase.fortune, 6, "harvest fortune includes the tool reforge")
	-- Accessories: masterwork rarity bump and reforge Magical Power.
	local charmed = P.computeStats(hero({books = {MeadowCharm = {masterwork = true}}}), 0)
	eq(charmed.magicalPower - base.magicalPower, Data.Rarity.Uncommon.power - Data.Rarity.Common.power, "masterwork accessory power")
	eq(P.magicalPower(hero({books = {MeadowCharm = {masterwork = true}}})), Data.Rarity.Uncommon.power + Data.Rarity.Common.power, "magicalPower uses effective rarity")
	local gleam = hero({reforges = {MeadowCharm = "Gleaming"}, books = {MeadowCharm = {masterwork = true}}})
	near(P.magicalPower(gleam), Data.Rarity.Uncommon.power + Data.Rarity.Common.power + 1.5, "accessory reforge Magical Power")
	local gs = P.computeStats(gleam, 0)
	eq(gs.health, base.health + math.floor(gs.magicalPower - base.magicalPower), "Magical Power feeds health")
	near(P.upgradeStats(gleam, "MeadowCharm").magicalPower, 1.5, "upgradeStats keeps magicalPower")
	-- Active accessory order follows the effective rarity: a 3-slot bag keeps the
	-- masterwork talisman over the plain common charm.
	local tight = hero({books = {QuarryTalisman = {masterwork = true}}, xp = {}})
	tight.accessoryBag = {"MeadowCharm", "QuarryTalisman", "BrassBand", "HideBracer"}
	tight.items.BrassBand, tight.items.HideBracer = 1, 1
	eq(P.accessorySlots(tight), 3, "fresh bag has 3 slots")
	local active = P.activeAccessories(tight)
	ok(table.find(active, "QuarryTalisman") ~= nil and table.find(active, "MeadowCharm") == nil, "masterwork talisman outranks a common charm")
	-- Mythic items cannot be bumped further; a bumped Legendary reaches Mythic scaling.
	eq(G.effectiveRarity({books = {AetherHeartstone = {masterwork = true}}}, "AetherHeartstone"), "Mythic", "mythic stays mythic")
	near(G.breakdown({reforges = {CelestialSword = "Honed"}, books = {CelestialSword = {masterwork = true}}}, "CelestialSword").reforgeStats.critChance, 5, "legendary masterwork reaches mythic scaling")
	print("PASS: " .. (checks - before) .. " gear depth data/formula assertions.")
end

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-progression.luau")
