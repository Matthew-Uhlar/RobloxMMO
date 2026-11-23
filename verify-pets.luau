-- Pets depth: data integrity, XP curves, ability effects, held items, candy,
-- the Roost upgrade timer, migrations and the companion client.
-- Part A checks Data.PetDepth (shared/GameData.lua); Part B the pet rules in
-- shared/Progression.lua (computeStats, XP shares, harvest/garden/combat
-- hooks); Part C runs server.server.lua with DataStore/clock/roll doubles and
-- plays every pet verb; Part D runs pets.client.lua against stub instances.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local PD = Data.PetDepth
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function near(a, b, case, eps)
	assert(type(a) == "number" and math.abs(a - b) <= (eps or 1e-6), case .. " expected ~" .. tostring(b) .. ", got " .. tostring(a))
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local X = Data.XP_TABLE

------------------------------------------------------------------------------
-- Part A: data integrity.
------------------------------------------------------------------------------
local partA = checks
ok(type(PD) == "table", "Data.PetDepth exists")
local species, seen = 0, {}
for _, pet in ipairs(Data.Pets) do
	species += 1
	ok(not seen[pet.id], pet.id .. " unique species id")
	seen[pet.id] = true
	eq(Data.PetById[pet.id], pet, pet.id .. " indexed")
	local itemDef = Data.Items[pet.id .. "Pet"]
	ok(itemDef ~= nil and itemDef.kind == "pet" and itemDef.pet == pet.id, pet.id .. " pet item")
	ok(PD.validRarity(pet.rarity), pet.id .. " base rarity valid")
	ok(Data.Skills[pet.skill] ~= nil, pet.id .. " skill " .. tostring(pet.skill) .. " exists")
	for stat in pairs(pet.perLevel) do ok(Data.Stats[stat] ~= nil, pet.id .. " perLevel stat " .. stat) end
	local list = PD.Abilities[pet.id]
	ok(list ~= nil and #list >= 2 and #list <= 3, pet.id .. " has 2-3 abilities")
	eq(list[1].rarity, "Common", pet.id .. " first ability unlocks at Common")
	local ids = {}
	for i, a in ipairs(list) do
		ok(not ids[a.id], pet.id .. " ability ids unique")
		ids[a.id] = true
		eq(a.index, i, pet.id .. " ability index")
		ok(PD.validRarity(a.rarity), pet.id .. " " .. a.name .. " unlock rarity")
		ok(type(a.per) == "number" and a.per > 0, pet.id .. " " .. a.name .. " scales")
		if i > 1 then ok(PD.rank(a.rarity) >= PD.rank(list[i - 1].rarity), pet.id .. " unlocks ascend") end
		if a.kind == "xp" then
			for _, s in ipairs(a.skills) do ok(Data.Skills[s] ~= nil, pet.id .. " xp skill " .. s) end
		elseif a.kind == "stat" then
			ok(Data.Stats[a.stat] ~= nil or a.stat == "damagePercent", pet.id .. " stat " .. a.stat)
		elseif a.kind == "family" then
			ok(Data.Slayers[a.line] ~= nil, pet.id .. " family line " .. a.line)
		elseif a.kind == "gather" then
			ok(Data.FortuneStat[a.skill] ~= nil, pet.id .. " gather skill " .. a.skill)
		elseif a.kind == "craft" then
			for _, s in ipairs(a.skills) do ok(Data.Skills[s] ~= nil, pet.id .. " craft skill " .. s) end
		else
			ok(a.kind == "garden", pet.id .. " known ability kind " .. tostring(a.kind))
		end
		ok(PD.abilityText(a, 5) ~= "", pet.id .. " " .. a.name .. " text")
	end
	ok(has(pet.ability, list[1].name), pet.id .. " summary names its first ability")
	ok(has(itemDef.description, list[#list].name), pet.id .. " item lists its abilities")
	ok(PD.Looks[pet.id] ~= nil, pet.id .. " has a companion look")
	for _, rarity in ipairs(PD.RARITIES) do
		local plan = PD.bodyPlan(pet.id, rarity)
		ok(#plan.parts >= 5 and #plan.parts <= PD.MAX_PARTS, pet.id .. " " .. rarity .. " body plan 5-15 parts (" .. #plan.parts .. ")")
	end
end
ok(species >= 24, "24+ species (" .. species .. ")")
eq(#PD.NEW_SPECIES, 10, "ten new species")
for _, id in ipairs(PD.NEW_SPECIES) do ok(Data.PetById[id] ~= nil, "new species " .. id) end
-- Every skill the brief lists has a pet.
local bySkill = {}
for _, pet in ipairs(Data.Pets) do bySkill[pet.skill] = true end
for _, skill in ipairs({"Agility", "Hunter", "Glyphcraft", "Fletching", "Cooking", "Alchemy", "Carpentry", "Mining", "Woodcutting", "Fishing", "Farming", "Combat", "Smithing", "Magic", "Ranged"}) do
	ok(bySkill[skill], skill .. " has a pet")
end
-- Every ability kind is used somewhere.
local kinds = {}
for _, list in pairs(PD.Abilities) do for _, a in ipairs(list) do kinds[a.kind] = true end end
for _, k in ipairs({"xp", "stat", "family", "garden", "gather", "craft"}) do ok(kinds[k], "ability kind " .. k .. " in use") end
-- Existing species keep their base rarity.
for id, r in pairs({Tidewing = "Rare", Burrowmole = "Uncommon", Mossback = "Uncommon", Sapling = "Rare", Emberfox = "Epic", Gloomwing = "Rare", Aurelion = "Legendary",
	Cindercrab = "Uncommon", Pearlwhisker = "Epic", Puffkin = "Uncommon", Glimmerfly = "Rare", Stormkid = "Epic", Gustling = "Rare", Shardling = "Legendary"}) do
	eq(Data.PetById[id].rarity, r, id .. " keeps its rarity")
end
-- Sources: every pet item drops, is a skilling pet or comes from the garden.
local sources = {}
local function scan(list) for _, d in ipairs(type(list) == "table" and list or {}) do if type(d) == "table" and d.item then sources[d.item] = true end end end
for _, m in pairs(Data.Monsters) do scan(m.drops) end
for _, m in pairs(Data.SeaCreatures) do scan(m.drops) end
for _, s in pairs(Data.Slayers) do for _, t in ipairs(s.tiers) do scan(t.drops) end end
for _, b in pairs(Data.WorldBosses or {}) do scan(b.loot) end
for _, loot in pairs(Data.Lairs and Data.Lairs.Loot or {}) do scan(loot) end -- Lairs: boss pets
scan(Data.Agility.LapDrops)
for _, c in ipairs(Data.Hunter.Creatures) do scan(c.drops) end
for _, id in pairs(PD.SkillPets) do sources[id] = true end
for _, l in ipairs(Data.Trophies and Data.Trophies.Ledger or {}) do if l.item then sources[l.item] = true end end -- §39: the Trophy Keeper's Glintgill
for _, pet in ipairs(Data.Pets) do ok(sources[pet.id .. "Pet"], pet.id .. " is obtainable") end
for skill, id in pairs(PD.SkillPets) do
	ok(Data.Skills[skill] ~= nil and Data.Items[id] and Data.Items[id].kind == "pet", "skilling pet " .. skill)
end
ok(sources.BellwispPet, "Bellwisp drops from a sea creature")
-- Held items: twelve, real effects, obtainable.
eq(#PD.HELD_ORDER, 12, "twelve held items")
local shop = {}
for _, e in ipairs(PD.Shop) do
	ok(Data.Items[e.item] ~= nil and e.coins > 0, "shop entry " .. e.item)
	eq(PD.ShopByItem[e.item], e, "shop indexed " .. e.item)
	shop[e.item] = true
end
for _, id in ipairs(PD.HELD_ORDER) do
	local h = PD.HeldItems[id]
	local def = Data.Items[id]
	ok(h ~= nil and def ~= nil and def.kind == "petitem" and def.petItem == "held", id .. " held item")
	ok(h.xp ~= nil or h.stats ~= nil or h.garden ~= nil, id .. " has an effect")
	for stat in pairs(h.stats or {}) do ok(Data.Stats[stat] ~= nil, id .. " stat " .. stat) end
	for cat in pairs(h.xp or {}) do ok(cat == "all" or cat == "gathering" or cat == "production" or cat == "combat" or cat == "support", id .. " xp category " .. cat) end
	ok(shop[id] or Data.Recipes[id] ~= nil or sources[id], id .. " is obtainable")
	ok(type(h.text) == "string" and #h.text > 4, id .. " text")
end
for id, c in pairs(PD.Candies) do
	ok(Data.Items[id] and Data.Items[id].petItem == "candy" and c.xp > 0, id .. " candy")
	ok(shop[id] or Data.Recipes[id] ~= nil or sources[id], id .. " obtainable")
end
-- No craft-and-sell mint: every pet recipe (gear, candy) sells for at most its inputs.
local petRecipes = 0
for id, rec in pairs(Data.Recipes) do
	local out = Data.Items[rec.output]
	if out and (out.kind == "petitem" or out.kind == "pet" or PD.RECIPE_CATEGORIES[rec.category]) then
		petRecipes += 1
		local input = 0
		for cost, n in pairs(rec.costs) do input += (Data.Items[cost] and Data.Items[cost].value or 0) * n end
		ok(out.value * (rec.amount or 1) <= input, string.format("%s value %d x%d <= inputs %d", id, out.value, rec.amount or 1, input))
	end
end
ok(petRecipes >= 8, "pet recipes value-checked (" .. petRecipes .. ")")
ok(Data.Items.PetCandy.value <= 162 and Data.Items.StarlitCandy.value < 4000, "candy no longer sells above its Hearth inputs")
ok(Data.Items.AscendantPrism.petItem == "tierBoost" and sources.AscendantPrism, "Ascendant Prism tier boost drops")
ok(sources.GlimmerClover and sources.TidepearlPendant and sources.StarlitCandy, "rare held items and Starlit Candy drop")
for id, rec in pairs(Data.Recipes) do
	if Data.Items[rec.output] and Data.Items[rec.output].kind == "petitem" then
		ok(Data.Skills[rec.skill] ~= nil and rec.station ~= nil and rec.repeatable == true, id .. " pet recipe")
		for cost in pairs(rec.costs) do ok(Data.Items[cost] ~= nil, id .. " cost " .. cost) end
	end
end
-- Roost costs.
for _, pet in ipairs(Data.Pets) do
	local prev
	local rarity = pet.rarity
	while PD.nextRarity(rarity) do
		local cost = PD.upgradeCost(pet, rarity)
		ok(cost ~= nil and cost.to == PD.nextRarity(rarity), pet.id .. " upgrade from " .. rarity)
		for id, n in pairs(cost.items) do ok(Data.Items[id] ~= nil and n > 0, pet.id .. " upgrade material " .. id) end
		if prev then ok(cost.coins > prev.coins and cost.seconds > prev.seconds, pet.id .. " upgrades cost more") end
		prev = cost
		rarity = cost.to
	end
	eq(PD.upgradeCost(pet, "Legendary"), nil, pet.id .. " stops at Legendary")
end
eq(PD.nextRarity("Common"), "Uncommon", "next rarity")
eq(PD.nextRarity("Legendary"), nil, "Legendary is the top")
eq(PD.nextRarity("Mythic"), nil, "no Mythic pets")
ok(not PD.validRarity("Mythic") and not PD.validRarity(5) and not PD.validRarity(nil), "invalid rarities")
-- XP curves.
for _, r in ipairs(PD.RARITIES) do
	for level = 1, 99 do
		local need = Data.petXpToNext(level, r)
		if level > 1 then ok(need > Data.petXpToNext(level - 1, r), r .. " curve rises at " .. level) end
		if r ~= "Common" then ok(need > Data.petXpToNext(level, PD.RARITIES[PD.rank(r) - 1]), r .. " costs more than the tier below at " .. level) end
	end
	eq(PD.totalXp(100, 0, r), PD.totalXpToMax(r), r .. " total to 100")
end
eq(Data.petXpToNext, PD.xpToNext, "Data.petXpToNext is the per-rarity curve")
eq(Data.petXpToNext(1, "Common"), 100, "Common level 1 needs 100")
eq(Data.petXpToNext(1, "Legendary"), 450, "Legendary level 1 needs 450")
local common, legendary = PD.totalXpToMax("Common"), PD.totalXpToMax("Legendary")
ok(common > 4000000 and common < 6000000, "Common to 100 ~5M (" .. common .. ")")
ok(legendary > 18000000 and legendary < 26000000, "Legendary to 100 ~22M (" .. legendary .. ")")
near(legendary / common, 4.5, "Legendary/Common spread", 0.01)
for _, r in ipairs(PD.RARITIES) do
	for _, level in ipairs({1, 2, 17, 50, 99}) do
		local total = PD.totalXp(level, 37, r)
		local l2, x2 = PD.fromTotal(total, r)
		eq(l2, level, r .. " roundtrip level " .. level)
		eq(x2, 37, r .. " roundtrip xp " .. level)
	end
	local lMax, xMax = PD.fromTotal(10 ^ 9, r)
	ok(lMax == 100 and xMax == 0, r .. " caps at 100")
end
-- Taming.
eq(PD.tamingXpBonus(1), 0, "Taming 1 no XP bonus")
eq(PD.tamingXpBonus(4), 0, "Taming 4 no XP bonus")
near(PD.tamingXpBonus(25), 0.25, "Taming 25 +25% pet XP")
near(PD.tamingXpBonus(99), 0.75, "Taming XP bonus cap")
eq(PD.tamingStatBonus(9), 0, "Taming 9 no stat bonus")
near(PD.tamingStatBonus(50), 0.125, "Taming 50 +12.5% stats")
-- Stat scaling: base rarity unchanged, lower weaker, higher stronger.
for _, pet in ipairs(Data.Pets) do
	near(PD.statScale(pet, pet.rarity, 1), 1, pet.id .. " base rarity scale")
	if pet.rarity ~= "Common" then ok(PD.statScale(pet, "Common", 1) < 1, pet.id .. " Common weaker") end
	if pet.rarity ~= "Legendary" then ok(PD.statScale(pet, "Legendary", 1) > 1, pet.id .. " Legendary stronger") end
end
-- Unlocks by rarity and level.
local function unlockedCount(id, level, rarity)
	local n = 0
	for _, row in ipairs(PD.abilityView(Data.PetById[id], level, rarity)) do if row.unlocked then n += 1 end end
	return n
end
eq(unlockedCount("Tidewing", 50, "Common"), 1, "Common: one ability")
eq(unlockedCount("Tidewing", 50, "Rare"), 2, "Rare: two abilities")
eq(unlockedCount("Tidewing", 50, "Legendary"), 3, "Legendary: three abilities")
eq(unlockedCount("Mossback", 49, "Epic"), 2, "level-gated ability locked below 50")
eq(unlockedCount("Mossback", 50, "Epic"), 3, "level-gated ability unlocks at 50")
eq(PD.abilityValue(PD.Abilities.Tidewing[1], 100, "Legendary"), 10, "Sky Diver +10% at Legendary 100")
eq(PD.abilityValue(PD.Abilities.Tidewing[1], 100, "Common"), 6, "Common abilities at 60%")
eq(PD.abilityValue(PD.Abilities.Tidewing[1], 500, "Legendary"), 10, "ability level clamps to 100")
local view = PD.abilityView(Data.PetById.Emberfox, 1, "Epic")
ok(view[3].unlocked == false and has(view[3].requires, "Legendary"), "locked ability names its requirement")
ok(has(view[2].text, "Beast"), "family text names the line")
-- Attribute codec.
eq(PD.attribute("Tidewing", "Rare", 12), "Tidewing:Rare:12", "attribute encodes")
local aid, ar, al = PD.parseAttribute("Bloomsnail:Legendary:100")
ok(aid == "Bloomsnail" and ar == "Legendary" and al == 100, "attribute decodes")
for _, bad in ipairs({"", "Nope:Rare:3", "Tidewing:Mythic:3", "Tidewing:Rare", 5, "Tidewing:Rare:x"}) do
	eq(PD.parseAttribute(bad), nil, "bad attribute " .. tostring(bad))
end
eq(select(3, PD.parseAttribute("Tidewing:Rare:900")), 100, "attribute level clamps")
-- Body plans: shapes, sizes, flapping wings for flyers, halos for Epic+.
for id in pairs(PD.Looks) do
	local plan = PD.bodyPlan(id, "Legendary")
	for _, part in ipairs(plan.parts) do
		ok(part.shape == "Ball" or part.shape == "Block" or part.shape == "Cylinder" or part.shape == "Wedge", id .. " part shape " .. part.name)
		ok(part.size[1] > 0 and part.size[2] > 0 and part.size[3] > 0 and #part.color == 6, id .. " part " .. part.name)
	end
end
local flaps = 0
for _, part in ipairs(PD.bodyPlan("Tidewing", "Rare").parts) do if part.flap then flaps += 1 end end
eq(flaps, 2, "flyers flap two wings")
ok(PD.bodyPlan("Tidewing", "Rare").floating and not PD.bodyPlan("Emberfox", "Rare").floating, "flyers hover, quadrupeds walk")
eq(#PD.bodyPlan("Emberfox", "Legendary").parts - #PD.bodyPlan("Emberfox", "Rare").parts, 2, "Legendary adds halo and gem")
ok(PD.bodyPlan("Emberfox", "Legendary").scale > PD.bodyPlan("Emberfox", "Common").scale, "rarer companions are larger")
-- Skilling pet chance.
near(PD.skillPetChance(10000, 0), 0.025, "skilling pet chance per step")
near(PD.skillPetChance(10000, 100), 0.05, "Pet Luck doubles (capped)")
eq(PD.skillPetChance(-5, 0), 0, "no negative chance")
print("PASS: " .. (checks - partA) .. " pet data assertions.")

------------------------------------------------------------------------------
-- Part B: progression rules.
------------------------------------------------------------------------------
local partB = checks
local function journal(pet, extra)
	local p = {xp = {}, items = {}, collection = {}, equipment = {}, pets = {pet}, activePet = 1}
	for k, v in pairs(extra or {}) do p[k] = v end
	return p
end
local function bare() return {xp = {}, items = {}, collection = {}, equipment = {}} end
local base = P.computeStats(bare(), 0)
-- Older pets (no rarity/item fields) keep the exact species numbers.
local old = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0}), 0)
near(old.strength - base.strength, 4, "Emberfox L10 strength unchanged")
near(old.critDamage - base.critDamage, 3, "Emberfox L10 crit damage unchanged")
eq(old.damagePercent, 0, "Ember Heart locked below Legendary")
eq(P.petRarity({id = "Emberfox"}), "Epic", "missing rarity reads as species rarity")
eq(P.petRarity({id = "Emberfox", rarity = "Bogus"}), "Epic", "invalid rarity reads as species rarity")
eq(P.petRarity({id = "Emberfox", rarity = "Rare"}), "Rare", "instance rarity")
-- Rarity scales stats and unlocks abilities.
local leg = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0, rarity = "Legendary"}), 0)
near(leg.strength - base.strength, 4.8, "Legendary Emberfox strength x1.2")
near(leg.damagePercent, 1, "Ember Heart +1% damage at Legendary 10")
local common = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0, rarity = "Common"}), 0)
near(common.strength - base.strength, 2.2, "Common Emberfox strength x0.55")
-- Taming boosts stats.
local tamed = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0}, {xp = {Taming = X[20]}}), 0)
near(tamed.strength - base.strength, 4 * 1.05, "Taming 20 +5% pet stats")
-- Held item stats.
local collared = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0, item = "IronbarkCollar"}), 0)
eq(collared.defense - old.defense, 25, "Ironbark Collar +25 Defense")
eq(collared.health - old.health, 20, "Ironbark Collar +20 Health")
local clover = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0, item = "GlimmerClover"}), 0)
near(clover.magicFind - old.magicFind, 6, "Glimmer Clover +6 Magic Find")
near(clover.petLuck - old.petLuck, 2, "Glimmer Clover +2 Pet Luck")
local unknown = P.computeStats(journal({id = "Emberfox", level = 10, xp = 0, item = "Ore"}), 0)
eq(unknown.defense, old.defense, "non-held items do nothing")
-- Stat abilities flow into computeStats (sea creatures, traps, fortune).
local tide = P.computeStats(journal({id = "Tidewing", level = 100, xp = 0, rarity = "Legendary"}), 0)
near(tide.seaCreatureChance - base.seaCreatureChance, 0.05 * 100 * 1.2 / 0.85 + 3, "Tidewing perLevel + Spray Sense", 0.06)
ok(Data.seaCreatureChance(tide) > Data.seaCreatureChance(base), "pet raises the sea creature roll")
local puff = P.computeStats(journal({id = "Puffkin", level = 100, xp = 0, rarity = "Rare"}), 0)
local creature = Data.Hunter.Creatures[1]
ok(Data.Hunter.catchChance(creature, 1, puff.trapLuck) > Data.Hunter.catchChance(creature, 1, base.trapLuck), "Puffkin trap luck lifts catch chance")
local mole = P.computeStats(journal({id = "Burrowmole", level = 50, xp = 0, rarity = "Rare"}), 0)
near(mole.miningFortune - base.miningFortune, 0.8 * 50 * 0.85 / 0.7 + 0.3 * 50 * 0.8, "Burrowmole fortune: perLevel + Tunnel Sense", 0.06)
local shard = P.computeStats(journal({id = "Shardling", level = 100, xp = 0}), 0)
near(shard.damagePercent, 10, "Shardling Shard Edge +10% damage")
-- Combat bridge stats: damagePercent raises melee and ranged damage.
local function fixed(v) return function() return v end end
local plain = P.meleeDamage({damage = 100, strength = 0, critChance = 0, critDamage = 0, combatBonus = 0, damagePercent = 0}, fixed(0.9))
local boosted = P.meleeDamage({damage = 100, strength = 0, critChance = 0, critDamage = 0, combatBonus = 0, damagePercent = shard.damagePercent}, fixed(0.9))
eq(boosted, math.floor(plain * 1.1), "pet damage % reaches melee damage")
local bow = {ranged = {power = 100}}
ok(P.rangedDamage({damagePercent = 10}, bow, nil, 1, fixed(0.9)) > P.rangedDamage({}, bow, nil, 1, fixed(0.9)), "pet damage % reaches ranged damage")
local owl = P.computeStats(journal({id = "Starquill", level = 100, xp = 0, rarity = "Legendary"}), 0)
ok(P.maxMana(owl) > P.maxMana(base) and P.manaRegen(P.maxMana(owl)) > P.manaRegen(P.maxMana(base)), "Mana Font raises max mana and regeneration")
-- Effects: skill XP, family, garden, gather, craft.
local tideP = journal({id = "Tidewing", level = 100, xp = 0, rarity = "Legendary"})
near(P.petSkillXpMult(tideP, "Fishing"), 1.1, "Sky Diver +10% Fishing XP")
eq(P.petSkillXpMult(tideP, "Mining"), 1, "no XP boost off-skill")
eq(P.petSkillXpMult(bare(), "Fishing"), 1, "no pet no boost")
near(P.petEffects(tideP).gather.Fishing, 15, "Undertow 15% doubled catches")
-- Doubled harvests are a yield candidate in gatherYieldMult (max, never stacked).
do
	local hit, miss = function() return 0 end, function() return 0.999 end
	local res = {resource = {skill = "Fishing"}}
	local mult, perks = P.gatherYieldMult(tideP, res, hit, 0)
	ok(mult == 2 and res.petDouble == true and perks == nil, "pet doubled harvest without mastery")
	local res2 = {resource = {skill = "Fishing"}}
	eq(P.gatherYieldMult(tideP, res2, miss, 0), 1, "missed pet roll")
	eq(res2.petDouble, nil, "no flag on a miss")
	local res3 = {resource = {skill = "Mining"}}
	local calls = 0
	eq(P.gatherYieldMult(tideP, res3, function() calls += 1 return 0 end, 0), 1, "off-skill pet: no double")
	eq(calls, 0, "off-skill pet draws no roll")
end
local foxR = journal({id = "Emberfox", level = 50, xp = 0, rarity = "Rare"})
near(P.petEffects(foxR).family.Bramble, 0.3 * 50 * 0.8, "Bramble Bane at Rare 50")
eq(P.petEffects(journal({id = "Emberfox", level = 50, xp = 0, rarity = "Uncommon"})).family.Bramble, nil, "Bramble Bane locked at Uncommon")
local moss = journal({id = "Mossback", level = 100, xp = 0, rarity = "Rare", item = "VerdantSprig"})
near(P.petEffects(moss).garden, 0.15 * 100 * 0.8 + 8, "Green Shell + Verdant Sprig growth")
local pup = journal({id = "Hearthpup", level = 100, xp = 0, rarity = "Legendary"})
near(P.petEffects(pup).craft.Cooking, 15, "Second Helping 15% extra meals")
eq(P.petEffects(bare()).garden, 0, "no pet no growth")
-- Garden: growth abilities speed plots, within the rate cap.
local G = Data.Garden
local plot = {crop = "Herb"}
local r0 = G.rate(plot, {level = 1})
near(G.rate(plot, {level = 1, petGrowth = 0.2}), r0 + 0.2, "pet growth adds to the rate")
eq(G.rate({compost = true}, {level = 15, set = true, petGrowth = 0.5}, true), G.MAX_RATE, "pet growth respects the cap")
eq(G.rate(plot, {level = 1, petGrowth = -3}), r0, "negative growth ignored")
local slow, fast = {crop = "Herb", grown = 0, at = 0}, {crop = "Herb", grown = 0, at = 0}
G.advance(slow, 100, {level = 1})
G.advance(fast, 100, {level = 1, petGrowth = 0.2})
ok(fast.grown > slow.grown, "faster plot grows more")
-- XP shares.
local mole1 = journal({id = "Burrowmole", level = 1, xp = 0})
P.addPetXp(mole1, "Mining", 40)
eq(mole1.pets[1].xp, 40, "own skill full share")
P.addPetXp(mole1, "Fishing", 40)
eq(mole1.pets[1].xp, 60, "same category half share")
P.addPetXp(mole1, "Combat", 40)
eq(mole1.pets[1].xp, 70, "other category quarter share")
local leveled, gained = P.addPetXp(mole1, "Mining", Data.petXpToNext(1, "Uncommon"))
ok(leveled and mole1.pets[1].level == 2, "pet levels on its rarity curve")
eq(gained, Data.petXpToNext(1, "Uncommon"), "gain reported")
local tamer = journal({id = "Burrowmole", level = 1, xp = 0}, {xp = {Taming = X[25]}})
P.addPetXp(tamer, "Mining", 100)
near(tamer.pets[1].xp, 125, "Taming 25 +25% pet XP")
local pouch = journal({id = "Burrowmole", level = 1, xp = 0, item = "ForagersPouch"})
P.addPetXp(pouch, "Mining", 100)
near(pouch.pets[1].xp, 120, "Forager's Pouch +20% from gathering")
P.addPetXp(pouch, "Combat", 100)
near(pouch.pets[1].xp, 145, "Forager's Pouch idle for combat XP")
local ribbon = journal({id = "Burrowmole", level = 1, xp = 0, item = "EverbloomRibbon"})
P.addPetXp(ribbon, "Combat", 100)
near(ribbon.pets[1].xp, 25 * 1.12, "Everbloom Ribbon boosts every skill")
local maxed = journal({id = "Burrowmole", level = 100, xp = 0})
local lv, g = P.addPetXp(maxed, "Mining", 5000)
ok(lv == false and g == 0 and maxed.pets[1].xp == 0, "level 100 pets stop earning")
eq(select(2, P.addPetXp(bare(), "Mining", 10)), 0, "no pet no XP")
-- addXpToPet and rarity changes keep lifetime XP.
local candyPet = {id = "Tidewing", level = 1, xp = 0, rarity = "Rare"}
local gainedLevels = P.addXpToPet(candyPet, 20000)
local expectL, expectX = PD.fromTotal(20000, "Rare")
eq(candyPet.level, expectL, "candy XP levels along the curve")
near(candyPet.xp, expectX, "candy XP remainder")
eq(gainedLevels, expectL - 1, "levels gained reported")
local total = PD.totalXp(candyPet.level, candyPet.xp, "Rare")
P.petSetRarity(candyPet, "Epic")
eq(candyPet.rarity, "Epic", "rarity changed")
near(PD.totalXp(candyPet.level, candyPet.xp, "Epic"), total, "lifetime XP kept on upgrade")
ok(candyPet.level <= expectL, "higher rarity recounts the level down")
local top = {id = "Tidewing", level = 100, xp = 0, rarity = "Epic"}
P.petSetRarity(top, "Legendary")
ok(top.level < 100 and top.level > 80, "a level-100 Epic becomes a high-level Legendary (" .. top.level .. ")")
print("PASS: " .. (checks - partB) .. " pet progression assertions.")

------------------------------------------------------------------------------
-- Part C: server verbs, hooks, timer and migration.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
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
local clock, utc = 10, 1600000000
local function advance(seconds) clock += seconds; utc += seconds end
local data, db = {}, {}
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
	HttpService = {GenerateGUID = function() return "pets-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end},
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
luau.load(fs.readFile("server.server.lua"):gsub("^\239\187\191", ""), {environment = env, injectGlobals = true})()
local remote, bridge
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
end
ok(remote ~= nil and bridge ~= nil, "IsleAction and IsleBridge found")
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3 and Vector3.zero or nil, Anchored = false}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function() end}
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
local function cmd(p, verb, item)
	advance(1)
	return remote.OnServerInvoke(p, verb, item)
end
local function st(p) advance(1) return remote.OnServerInvoke(p, "state") end
local function profileOf(p) leave(p); local prof = data["p" .. p.UserId].profile; return prof end

-- Adopt, summon, snapshot rows and the follower attribute.
local owner = seeded(801, function(p)
	p.items = {TidewingPet = 1, EmberfoxPet = 1, HearthpupPet = 1}
	p.coins = 2000000
end)
cmd(owner, "petAdopt", "TidewingPet")
cmd(owner, "petAdopt", "EmberfoxPet")
local s1 = cmd(owner, "petAdopt", "HearthpupPet")
eq(#s1.depth.pets, 3, "three pets adopted")
local row = s1.depth.pets[1]
eq(row.rarity, "Rare", "adopted at species rarity")
eq(row.candy, 0, "no candy yet")
eq(row.candyMax, PD.CANDY_MAX, "candy cap in the row")
eq(#row.abilities, 3, "ability rows")
ok(row.abilities[1].unlocked and row.abilities[2].unlocked and not row.abilities[3].unlocked, "Rare Tidewing: two of three unlocked")
ok(row.upgrade and row.upgrade.to == "Epic", "upgrade preview")
eq(row.next, Data.petXpToNext(1, "Rare"), "next XP on the rarity curve")
ok(type(s1.depth.petDepth) == "table" and s1.depth.petDepth.taming.level >= 1, "petDepth view")
eq(owner.attrs.ActivePet or "", "", "no follower before summoning")
cmd(owner, "petSummon", "2")
eq(owner.attrs.ActivePet, "Emberfox:Epic:1", "follower attribute replicates the summoned pet")
cmd(owner, "petSummon", "0")
eq(owner.attrs.ActivePet, "", "dismiss clears the follower")
cmd(owner, "petSummon", "1")
eq(owner.attrs.ActivePet, "Tidewing:Rare:1", "follower switches pets")

-- Roost shop.
local before = st(owner).coins
local bought = cmd(owner, "petShop", "PetCandy")
eq(bought.items.PetCandy, 1, "bought Pet Candy")
eq(bought.coins, before - PD.ShopByItem.PetCandy.coins, "shop charges coins")
ok(has(cmd(owner, "petShop", "AscendantPrism").message, "does not sell"), "prisms are not sold")
ok(has(cmd(owner, "petShop", "Ore").message, "does not sell"), "unknown shop item refused")
for _ = 1, 11 do cmd(owner, "petShop", "PetCandy") end
eq(st(owner).items.PetCandy, 12, "bought a stack")

-- Candy: XP, cap and validation.
local fed = cmd(owner, "petCandy", "1:Tidewing:PetCandy")
local fedRow = fed.depth.pets[1]
local eL, eX = PD.fromTotal(20000, "Rare")
eq(fedRow.level, eL, "candy levels the pet")
near(fedRow.xp, eX, "candy XP remainder")
eq(fedRow.candy, 1, "one candy eaten")
eq(fed.items.PetCandy, 11, "candy consumed")
ok(has(cmd(owner, "petCandy", "1:Tidewing:Ore").message, "Choose a Pet Candy"), "non-candy refused")
ok(has(cmd(owner, "petCandy", "9:Tidewing:PetCandy").message, "Choose one of your pets"), "missing pet refused")
ok(has(cmd(owner, "petCandy", "x:Tidewing:PetCandy").message, "Choose one of your pets"), "bad index refused")
ok(has(cmd(owner, "petCandy", "1:Tidewing:StarlitCandy").message, "You have no"), "unowned candy refused")
for _ = 2, PD.CANDY_MAX do cmd(owner, "petCandy", "1:Tidewing:PetCandy") end
local capped = st(owner)
eq(capped.depth.pets[1].candy, PD.CANDY_MAX, "candy uses reach the cap")
eq(capped.items.PetCandy, 12 - PD.CANDY_MAX, "one candy per use")
ok(has(cmd(owner, "petCandy", "1:Tidewing:PetCandy").message, "eaten all"), "capped pet refuses candy")
eq(st(owner).items.PetCandy, 12 - PD.CANDY_MAX, "refused candy is kept")

-- Held items: equip, swap (old returns), remove, validation, effect.
local giver = rejoin(owner, function(p) p.items.IronbarkCollar = 1; p.items.GlimmerClover = 1 end)
owner = giver
local defBefore = st(owner).depth.stats.defense
local held = cmd(owner, "petItem", "1:Tidewing:IronbarkCollar")
eq(held.depth.pets[1].item, "IronbarkCollar", "collar equipped")
eq(held.items.IronbarkCollar, 0, "collar moved from the satchel")
eq(held.depth.stats.defense - defBefore, 25, "collar defense applies to the summoned pet")
local swapped = cmd(owner, "petItem", "1:Tidewing:GlimmerClover")
eq(swapped.depth.pets[1].item, "GlimmerClover", "clover swapped in")
eq(swapped.items.IronbarkCollar, 1, "old item returned")
ok(has(cmd(owner, "petItem", "1:Tidewing:GlimmerClover").message, "already holds"), "same item refused")
ok(has(cmd(owner, "petItem", "1:Tidewing:IronbarkCollar").message, "now holds"), "swap back")
ok(has(cmd(owner, "petItem", "1:Tidewing:Ore").message, "held item"), "non-held item refused")
ok(has(cmd(owner, "petItem", "2:Emberfox:IronbarkCollar").message, "do not own"), "unowned held item refused")
local removed = cmd(owner, "petItem", "1:Tidewing:none")
eq(removed.depth.pets[1].item, nil, "item removed")
eq(removed.items.IronbarkCollar, 1, "removed item returns")
ok(has(cmd(owner, "petItem", "1:Tidewing:").message, "holds nothing"), "empty slot")

-- Tier Boost.
owner = rejoin(owner, function(p) p.items.AscendantPrism = 2 end)
local beforeTotal = (function() local r = st(owner).depth.pets[3] return PD.totalXp(r.level, r.xp, r.rarity) end)()
local boosted = cmd(owner, "petTierBoost", "3:Hearthpup")
eq(boosted.depth.pets[3].rarity, "Rare", "Hearthpup boosted Uncommon -> Rare")
eq(boosted.items.AscendantPrism, 1, "prism consumed")
near(boosted.depth.pets[3].totalXp, beforeTotal, "tier boost keeps lifetime XP")
owner = rejoin(owner, function(p) p.pets[3].rarity = "Legendary" end)
ok(has(cmd(owner, "petTierBoost", "3:Hearthpup").message, "already Legendary"), "Legendary cannot be boosted")
eq(st(owner).items.AscendantPrism, 1, "refused boost keeps the prism")

-- The Roost: costs, timer, claim exactly once, cancel.
owner = rejoin(owner, function(p) p.coins = 100 end)
ok(has(cmd(owner, "petUpgrade", "1:Tidewing").message, "The Roost asks"), "too poor for the Roost")
local cost = PD.upgradeCost(Data.PetById.Tidewing, "Rare")
owner = rejoin(owner, function(p)
	p.coins = cost.coins + 50
	for id, n in pairs(cost.items) do p.items[id] = n end
	p.activePet = 2
end)
local lvlBefore = st(owner).depth.pets[1].level
local started = cmd(owner, "petUpgrade", "1:Tidewing")
ok(has(started.message, "returns Epic"), "upgrade started: " .. tostring(started.message))
eq(#started.depth.pets, 2, "pet handed to the Roost")
eq(started.coins, 50, "coins paid")
for id in pairs(cost.items) do eq(started.items[id], 0, "material paid " .. id) end
eq(started.depth.pets[1].id, "Emberfox", "roster shifts")
eq(started.depth.pets[1].active, true, "active pointer follows the summoned pet")
local job = started.depth.petDepth.upgrade
ok(job and job.id == "Tidewing" and job.to == "Epic" and job.ready == false, "Roost job in the snapshot")
eq(job.remaining, cost.seconds, "timer runs for the tier's duration")
ok(has(cmd(owner, "petUpgrade", "1:Emberfox").message, "already caring"), "one Roost slot")
ok(has(cmd(owner, "petClaim").message, "more"), "early claim refused")
-- Persistence while waiting.
owner = rejoin(owner)
ok(data.p801.profile.petUpgrade ~= nil and data.p801.profile.petUpgrade.to == "Epic", "Roost job saved")
advance(cost.seconds)
owner = rejoin(owner) -- hours later: a fresh session (the journal lease lapsed)
local claimed = cmd(owner, "petClaim")
ok(has(claimed.message, "returns Epic"), "claimed: " .. tostring(claimed.message))
eq(#claimed.depth.pets, 3, "pet back in the roster")
eq(claimed.depth.pets[3].id, "Tidewing", "claimed pet appended")
eq(claimed.depth.pets[3].rarity, "Epic", "claimed pet upgraded")
ok(claimed.depth.pets[3].level <= lvlBefore, "level recounted on the Epic curve")
eq(claimed.depth.petDepth.upgrade, nil, "Roost empty")
ok(has(cmd(owner, "petClaim").message, "No pet"), "claim only once")
eq(#st(owner).depth.pets, 3, "second claim adds nothing")
-- Cancel returns the pet without a refund.
local cost2 = PD.upgradeCost(Data.PetById.Hearthpup, "Legendary")
eq(cost2, nil, "Legendary Hearthpup cannot be upgraded")
ok(has(cmd(owner, "petUpgrade", "2:Hearthpup").message, "already Legendary"), "Roost refuses Legendary pets")
local cost3 = PD.upgradeCost(Data.PetById.Emberfox, "Epic")
owner = rejoin(owner, function(p)
	p.coins = cost3.coins
	for id, n in pairs(cost3.items) do p.items[id] = n end
end)
cmd(owner, "petUpgrade", "1:Emberfox")
local cancelled = cmd(owner, "petCancel")
ok(has(cancelled.message, "not refunded"), "cancel message")
eq(cancelled.coins, 0, "cancel keeps the fee")
eq(#cancelled.depth.pets, 3, "cancelled pet returns")
eq(cancelled.depth.pets[3].rarity, "Epic", "cancelled pet keeps its rarity")
ok(has(cmd(owner, "petCancel").message, "No pet"), "nothing to cancel")

-- Ability hooks on the server: skill XP, extra crafts, Taming share, skilling pets.
local cook = seeded(802, function(p)
	p.xp.Cooking = X[20]
	p.levelRewards.Cooking = 20
	p.items = {Sunwheat = 30, Duskberry = 20, Starfruit = 5}
	p.pets = {{id = "Hearthpup", level = 100, xp = 0, rarity = "Legendary"}}
	p.activePet = 1
	p.petSkillXp = {Cooking = 9950}
end)
local xp0, tam0 = st(cook).xp.Cooking, st(cook).xp.Taming
-- The cook already owns a Hearthpup, so the banked skilling-pet roll is spent
-- without drawing a roll (no second copy of a species).
queue(0.1) -- Second Helping (15%) succeeds
local crafted = cmd(cook, "craft", "PetCandy")
eq(crafted.xp.Cooking - xp0, 99, "Taste Tester +10% Cooking XP")
eq(crafted.items.PetCandy, 2, "Second Helping doubled the craft")
ok(has(crafted.message, "from your pet"), "extra craft message")
eq(crafted.items.HearthpupPet, nil, "no skilling pet while the species is owned")
eq(crafted.xp.Taming - tam0, 0, "level-100 pets earn no XP, so no Taming share")
eq(data.p802 and true, true, "cook saved")
queue(0.9)
local plainCraft = cmd(cook, "craft", "PetCandy")
eq(plainCraft.items.PetCandy, 3, "failed proc crafts one")
eq(#rolls, 0, "owned species: the skilling-pet bank drew no roll")
eq(profileOf(cook).petSkillXp.Cooking, 9950 + 90 + 90 - PD.SKILL_PET_STEP, "owned species: banked XP still spent")
-- Skilling pets: the first copy drops at the usual pace; while one is owned
-- (satchel, roster or Roost) no further copy drops.
local chef = seeded(808, function(p)
	p.xp.Cooking = X[20]
	p.levelRewards.Cooking = 20
	p.items = {Sunwheat = 30, Duskberry = 20, Starfruit = 5}
	p.petSkillXp = {Cooking = 9950}
end)
queue(0.001)
local first = cmd(chef, "craft", "PetCandy")
eq(first.items.HearthpupPet, 1, "skilling pet drops after 10k banked XP")
chef = rejoin(chef, function(p) p.petSkillXp = {Cooking = 9950} end)
queue(0.001)
eq(cmd(chef, "craft", "PetCandy").items.HearthpupPet, 1, "no second skilling pet while one sits in the satchel")
eq(#rolls, 1, "no roll drawn for an owned species")
table.clear(rolls)
chef = rejoin(chef, function(p)
	p.items.HearthpupPet = nil
	p.pets = {}
	p.petUpgrade = {pet = {id = "Hearthpup", level = 3, xp = 0, rarity = "Uncommon"}, from = "Uncommon", to = "Rare", ends = utc + 999}
	p.petSkillXp = {Cooking = 9950}
end)
queue(0.001)
eq(cmd(chef, "craft", "PetCandy").items.HearthpupPet, nil, "a Hearthpup at the Roost still counts as owned")
table.clear(rolls)
chef = rejoin(chef, function(p) p.petUpgrade = nil; p.petSkillXp = {Cooking = 9950} end)
queue(0.001)
eq(cmd(chef, "craft", "PetCandy").items.HearthpupPet, 1, "with none of the species left, the pet can drop again")
-- Pace: the first-drop chance per 10k step is still 10k / 400k.
near(PD.skillPetChance(PD.SKILL_PET_STEP, 0), PD.SKILL_PET_STEP / PD.SKILL_PET_XP, "first drop ~1 per 400k XP")
-- Extra crafts never duplicate one-of-a-kind outputs (gear, tools, accessories).
local gearId
for id, rec in pairs(Data.Recipes) do
	local out = Data.Items[rec.output]
	if rec.skill == "Smithing" and not rec.repeatable and out.kind ~= "material" and out.kind ~= "consumable" and not rec.collectionTier then gearId = id break end
end
ok(gearId ~= nil, "found a one-of-a-kind Smithing recipe")
local gearRec = Data.Recipes[gearId]
local smith = seeded(809, function(p)
	p.xp.Smithing = Data.MAX_XP
	p.levelRewards.Smithing = 99
	p.items = table.clone(gearRec.costs)
	p.pets = {{id = "Cindercrab", level = 100, xp = 0, rarity = "Legendary"}}
	p.activePet = 1
end)
queue(0) -- would win the 10% Slag Sifter roll if gear rolled
local forged = cmd(smith, "craft", gearId)
eq(forged.items[gearRec.output], gearRec.amount, "gear crafted once: " .. tostring(forged.message))
ok(not has(forged.message, "from your pet"), "no pet extra on gear")
eq(#rolls, 1, "no extra-craft roll for one-of-a-kind outputs")
table.clear(rolls)
-- Taming share from a levelling pet.
local trainer = seeded(803, function(p)
	p.xp.Cooking = X[20]
	p.levelRewards.Cooking = 20
	p.items = {Sunwheat = 30, Duskberry = 20, Starfruit = 5}
	p.pets = {{id = "Hearthpup", level = 1, xp = 0}}
	p.activePet = 1
end)
local t0 = st(trainer).xp.Taming
local trained = cmd(trainer, "craft", "PetCandy")
eq(trained.xp.Taming - t0, 9, "pet XP trains Taming at 10%")
eq(trained.depth.pets[1].xp, 90, "pet earned its skill's full share")
eq(trained.depth.pets[1].rarity, "Uncommon", "older pet migrated to its species rarity")
-- Family bonus on kills: coins and slayer progress.
local hunter = seeded(804, function(p)
	p.pets = {{id = "Emberfox", level = 100, xp = 0, rarity = "Legendary"}}
	p.activePet = 1
	p.slayerQuest = {line = "Bramble", tier = 1, progress = 0, needed = 150, bossReady = false}
end)
local c0 = st(hunter).coins
bridge.OnInvoke("kill", hunter, {monster = "BramblebackBoar"})
local after = st(hunter)
eq(after.coins - c0, 4 + math.floor(4 * 0.3 + 0.5), "Bramble Bane +30% coins")
eq(after.depth.slayer.quest.progress, math.floor(12 * 1.3), "Bramble Bane +30% slayer progress")
bridge.OnInvoke("kill", hunter, {monster = "GloomfangSpider"})
eq(st(hunter).coins - after.coins, Data.Monsters.GloomfangSpider.coins, "no bonus off-family")
-- Migration of older and broken saves.
local legacy = seeded(805, function(p)
	p.pets = {{id = "Tidewing", level = 7, xp = 10}, {id = "Mossback", level = 3.7, xp = -5, item = "Ore", candy = 99, rarity = "Mythic"},
		{id = "Gustling", level = 4, xp = 1e9}}
	p.activePet = 1
	p.petUpgrade = {pet = {id = "Burrowmole", level = 5, xp = 0, rarity = "Uncommon"}, to = "Legendary", ends = utc + 50}
	p.petTamingCarry = "x"
	p.petSkillXp = {Cooking = 1e12, Nope = 5}
end)
local ls = st(legacy)
eq(ls.depth.pets[1].rarity, "Rare", "older pet gains its species rarity")
eq(ls.depth.pets[1].level, 7, "older pet keeps its level")
eq(ls.depth.pets[1].xp, 10, "older pet keeps its XP")
eq(ls.depth.pets[2].rarity, "Uncommon", "invalid rarity reset to species")
eq(ls.depth.pets[2].level, 3, "fractional level floored")
eq(ls.depth.pets[2].xp, 0, "negative XP cleared")
eq(ls.depth.pets[2].item, nil, "non-held item dropped")
eq(ls.depth.pets[2].candy, PD.CANDY_MAX, "candy clamped")
ok(ls.depth.pets[3].xp < Data.petXpToNext(4, "Rare"), "overflowing XP clamped below the next level")
eq(#ls.depth.pets, 4, "bad Roost job (skips a tier) returns the pet")
eq(ls.depth.pets[4].id, "Burrowmole", "returned pet appended")
eq(ls.depth.petDepth.upgrade, nil, "bad Roost job cleared")
local prof = profileOf(legacy)
eq(prof.petTamingCarry, nil, "bad carry cleared")
eq(prof.petSkillXp.Nope, nil, "unknown skilling bank dropped")
eq(prof.petSkillXp.Cooking, PD.SKILL_PET_STEP, "skilling bank clamped")
local junk = seeded(806, function(p) p.petUpgrade = {pet = {id = "Nope"}, to = "Rare", ends = 5} end)
eq(st(junk).depth.petDepth.upgrade, nil, "unknown Roost pet dropped")
local good = seeded(807, function(p) p.petUpgrade = {pet = {id = "Burrowmole", level = 5, xp = 0}, to = "Rare", ends = utc + 100} end)
local gs = st(good)
ok(gs.depth.petDepth.upgrade and gs.depth.petDepth.upgrade.from == "Uncommon", "valid Roost job kept and normalised")
-- Review fixes: Roost claims respect the roster cap, Cancel on a finished
-- job claims, migration never deletes a Roost pet.
local MAX_PETS = 64
local function roster(n)
	local list = {}
	for i = 1, n do list[i] = {id = "Gustling", level = 1, xp = 0} end
	return list
end
local full = seeded(811, function(p)
	p.pets = roster(MAX_PETS)
	p.petUpgrade = {pet = {id = "Burrowmole", level = 5, xp = 0, rarity = "Uncommon"}, from = "Uncommon", to = "Rare", ends = utc + 5}
end)
advance(10)
local refused = cmd(full, "petClaim")
ok(has(refused.message, "full"), "claim refused while the roster is full: " .. tostring(refused.message))
eq(#refused.depth.pets, MAX_PETS, "nothing added past the cap")
ok(refused.depth.petDepth.upgrade ~= nil and refused.depth.petDepth.upgrade.ready == true, "job stays at the Roost")
full = rejoin(full, function(p) table.remove(p.pets) end)
local finished = cmd(full, "petCancel")
ok(has(finished.message, "returns Rare"), "cancel on a finished job claims instead: " .. tostring(finished.message))
eq(finished.depth.pets[MAX_PETS].id, "Burrowmole", "finished pet returned")
eq(finished.depth.pets[MAX_PETS].rarity, "Rare", "finished cancel keeps the upgrade")
eq(finished.depth.petDepth.upgrade, nil, "Roost emptied once")
local crowded = seeded(812, function(p)
	p.pets = roster(MAX_PETS)
	p.petUpgrade = {pet = {id = "Burrowmole", level = 5, xp = 0, rarity = "Uncommon"}, to = "Legendary", ends = utc + 50}
end)
local cs = st(crowded)
eq(#cs.depth.pets, MAX_PETS + 1, "invalid Roost job returns its pet even past the cap")
eq(cs.depth.pets[MAX_PETS + 1].id, "Burrowmole", "returned pet kept")
-- Pet verbs name the pet as index:speciesId; a shifted roster is refused.
local named = seeded(813, function(p)
	p.pets = {{id = "Tidewing", level = 1, xp = 0}, {id = "Emberfox", level = 1, xp = 0}}
	p.items = {PetCandy = 3, AscendantPrism = 1}
end)
ok(has(cmd(named, "petCandy", "1:PetCandy").message, "Choose one of your pets"), "bare index (old form) refused")
ok(has(cmd(named, "petTierBoost", "1").message, "Choose one of your pets"), "bare index refused for tier boost")
ok(has(cmd(named, "petCandy", "1:Emberfox:PetCandy").message, "moved"), "species mismatch refused")
eq(st(named).items.PetCandy, 3, "mismatch spends nothing")
ok(has(cmd(named, "petTierBoost", "2:Tidewing").message, "moved"), "tier boost checks the species")
eq(st(named).items.AscendantPrism, 1, "prism kept on a mismatch")
ok(has(cmd(named, "petTierBoost", "2:Emberfox:x").message, "Choose one of your pets"), "extra argument refused")
ok(has(cmd(named, "petCandy", "2:Emberfox").message, "Choose one of your pets"), "candy needs a candy id")
ok(has(cmd(named, "petCandy", "2:Emberfox:PetCandy").message, "enjoys"), "matching species accepted")
-- Garden growth: the summoned pet's growth counts for the time it was summoned.
local function gardener(id, summoned)
	return seeded(id, function(p)
		p.pets = {{id = "Bloomsnail", level = 100, xp = 0, rarity = "Legendary"}}
		p.activePet = if summoned then 1 else nil
		p.garden = {plots = {{crop = "Herb", grown = 0, at = utc}}}
	end)
end
local withPet, without, lateGardener = gardener(814, true), gardener(815, false), gardener(816, false)
st(withPet); st(without); st(lateGardener)
advance(120)
local dismissed = cmd(withPet, "petSummon", "0")
local late = cmd(lateGardener, "petSummon", "1")
local control = st(without)
local fA, fB, fC = dismissed.garden.plots[1].fraction, control.garden.plots[1].fraction, late.garden.plots[1].fraction
ok(fB > 0.2 and fB < 1, "control plot still growing (" .. fB .. ")")
ok(fA - fB > 0.05, "growth before dismissal used the summoned pet (" .. fA .. " vs " .. fB .. ")")
ok(math.abs(fC - fB) < 0.03, "summoning late does not backdate growth (" .. fC .. " vs " .. fB .. ")")
-- Unknown verbs and malformed input.
ok(has(cmd(owner, "petUpgrade", "1:2").message, "Choose one of your pets"), "malformed index refused")
ok(has(cmd(owner, "petItem", nil).message, "Choose one of your pets"), "missing item refused")
print("PASS: " .. (checks - partC) .. " pet server assertions.")

------------------------------------------------------------------------------
-- Part D: companion client (stub instances).
------------------------------------------------------------------------------
local partD = checks
local created = {}
local function vec(x, y, z)
	local v = {X = x, Y = y, Z = z}
	return setmetatable(v, {
		__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
		__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
		__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end,
		__mul = function(a, b) if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end,
		__index = function(self, k)
			if k == "Magnitude" then return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2) end
			if k == "Lerp" then return function(a, b, t) return vec(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
		end,
	})
end
local function cf(pos)
	local c = {Position = pos or vec(0, 0, 0), LookVector = vec(0, 0, -1)}
	return setmetatable(c, {__mul = function(a, b)
		if type(b) == "table" and b.Position then return cf(a.Position + b.Position) end
		return cf(a.Position)
	end})
end
local CFrameStub = {new = function(x, y, z)
	if type(x) == "table" then return cf(x) end
	return cf(vec(x or 0, y or 0, z or 0))
end, Angles = function() return cf(vec(0, 0, 0)) end}
local heartbeat, removing = signal(), signal()
local players = {}
local bulk = 0
local clientWorkspace = {CurrentCamera = {CFrame = cf(vec(0, 0, 0))}, BulkMoveTo = function(_, parts, frames)
	assert(#parts == #frames, "one frame per part")
	bulk += 1
end}
local function instance(class)
	local o = {ClassName = class, children = {}}
	function o:Destroy() self.destroyed = true end
	setmetatable(o, {__newindex = function(t, k, v)
		rawset(t, k, v)
		if k == "Parent" and type(v) == "table" and v.children then table.insert(v.children, t) end
	end})
	table.insert(created, o)
	return o
end
local clientEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return {GetPlayers = function() return players end, PlayerRemoving = removing} end
		if name == "RunService" then return {Heartbeat = heartbeat} end
		return {WaitForChild = function() return "AetherData" end}
	end},
	require = function() return Data end,
	workspace = clientWorkspace,
	Instance = {new = instance},
	Vector3 = {new = vec},
	CFrame = CFrameStub,
	Color3 = {fromHex = function(hex) assert(#hex == 6, "hex colour") return {hex = hex} end, new = function() return {} end},
	Enum = {PartType = {Ball = "Ball", Block = "Block", Cylinder = "Cylinder"}, Material = {Neon = "Neon", SmoothPlastic = "SmoothPlastic"}, BulkMoveMode = {FireCFrameChanged = 1}},
}
load("pets.client.lua", clientEnv)
local folder
for _, o in ipairs(created) do if o.Name == "Companions" then folder = o end end
ok(folder ~= nil, "Companions folder created")
local function clientPlayer(name, attr, pos)
	local root = {Position = pos or vec(5, 3, 5), CFrame = cf(pos or vec(5, 3, 5)), AssemblyLinearVelocity = vec(0, 0, 0)}
	local pl = {Name = name, Parent = true, attrs = {ActivePet = attr}, root = root}
	function pl:GetAttribute(k) return self.attrs[k] end
	pl.Character = {FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end}
	table.insert(players, pl)
	return pl
end
local alice = clientPlayer("Alice", "Emberfox:Legendary:40")
local bob = clientPlayer("Bob", "")
local far = clientPlayer("Far", "Tidewing:Rare:3", vec(900, 0, 0))
heartbeat:Fire(0.05)
local models = {}
for _, o in ipairs(folder.children) do if not o.destroyed then table.insert(models, o) end end
eq(#models, 1, "one follower: summoned and nearby only")
local parts = 0
for _, o in ipairs(models[1].children) do
	parts += 1
	ok(o.Anchored == true and o.CanCollide == false and o.CanQuery == false and o.CanTouch == false and o.CastShadow == false, "cheap part " .. tostring(o.Name))
end
eq(parts, #PD.bodyPlan("Emberfox", "Legendary").parts, "follower built from the body plan")
ok(parts <= 15, "follower within 15 parts")
ok(bulk >= 1, "follower posed with BulkMoveTo")
ok(has(models[1].Name, "Alice"), "follower named for its owner")
-- Switching species rebuilds; dismissing releases.
alice.attrs.ActivePet = "Bellwisp:Rare:5"
heartbeat:Fire(0.05)
ok(models[1].destroyed, "old follower released on switch")
local live = 0
for _, o in ipairs(folder.children) do if not o.destroyed then live += 1 end end
eq(live, 1, "new follower built")
alice.attrs.ActivePet = ""
heartbeat:Fire(0.05)
live = 0
for _, o in ipairs(folder.children) do if not o.destroyed then live += 1 end end
eq(live, 0, "dismiss releases the follower")
alice.attrs.ActivePet = "Bogus:Rare:1"
heartbeat:Fire(0.05)
live = 0
for _, o in ipairs(folder.children) do if not o.destroyed then live += 1 end end
eq(live, 0, "unknown species ignored")
local _ = bob and far
-- Range hysteresis: built within 160 studs, kept until beyond 180 (no thrash at the edge).
local function edgeLive()
	local n = 0
	for _, o in ipairs(folder.children) do if not o.destroyed and has(o.Name, "Edge") then n += 1 end end
	return n
end
local edge = clientPlayer("Edge", "Tidewing:Rare:3", vec(170, 0, 0))
local function place(x) edge.root.Position = vec(x, 0, 0); edge.root.CFrame = cf(vec(x, 0, 0)) end
heartbeat:Fire(0.05)
eq(edgeLive(), 0, "not built at 170 studs")
place(150)
heartbeat:Fire(0.05)
eq(edgeLive(), 1, "built within 160 studs")
for _, x in ipairs({161, 170, 179, 165, 175}) do
	place(x)
	heartbeat:Fire(0.05)
	eq(edgeLive(), 1, "kept at " .. x .. " studs")
end
local builtBefore = #folder.children
place(160)
heartbeat:Fire(0.05)
eq(#folder.children, builtBefore, "no rebuild while it lingers at the edge")
place(181)
heartbeat:Fire(0.05)
eq(edgeLive(), 0, "released beyond 180 studs")
place(170)
heartbeat:Fire(0.05)
eq(edgeLive(), 0, "not rebuilt between 160 and 180")
print("PASS: " .. (checks - partD) .. " companion client assertions.")

print("Pets depth QA passed " .. checks .. " checks.")
print("SUITE-END verify-pets.luau")
