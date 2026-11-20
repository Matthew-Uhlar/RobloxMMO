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
	eq(#Data.SkillOrder, 18, "eighteen skills (combat styles + Agility & Hunter)")
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
