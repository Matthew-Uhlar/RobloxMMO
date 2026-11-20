-- Aether Isles progression rules. Pure functions over a profile table so the
-- server, client previews and headless tests share one implementation.
--
-- Profile fields read here (all optional; server migrates defaults):
--   xp[skill], items[id], collection[id], equipment[slot]=itemId,
--   enchants[itemId][enchantId]=level, accessoryBag={itemId,...},
--   pets={{id,level,xp}}, activePet=index, buffs[id]={expires,stats},
--   bestiary[monsterId]=kills, slayerXp[line]=xp, companionBond, enchantRank
local Progression = {}
local Data
do
	local ok, result = pcall(function()
		return require(script.Parent:WaitForChild("AetherData"))
	end)
	if ok then Data = result end
end
function Progression.useData(data) Data = data end
function Progression.data() return Data end

------------------------------------------------------------------------------
-- Experience
------------------------------------------------------------------------------
function Progression.levelForXp(xp)
	xp = xp or 0
	local lo, hi = 1, Data.MAX_LEVEL
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if Data.XP_TABLE[mid] <= xp then lo = mid else hi = mid - 1 end
	end
	return lo
end
function Progression.xpForLevel(lvl)
	return Data.XP_TABLE[math.clamp(lvl, 1, Data.MAX_LEVEL)]
end
function Progression.progress(xp)
	local lvl = Progression.levelForXp(xp)
	if lvl >= Data.MAX_LEVEL then return {level=lvl,current=xp,floor=Data.XP_TABLE[lvl],ceiling=Data.XP_TABLE[lvl],fraction=1,maxed=true} end
	local floorXp, ceilXp = Data.XP_TABLE[lvl], Data.XP_TABLE[lvl+1]
	return {level=lvl,current=xp,floor=floorXp,ceiling=ceilXp,fraction=(xp-floorXp)/(ceilXp-floorXp),maxed=false}
end
-- Total level / average (OSRS total level, SkyBlock skill average).
function Progression.totals(p)
	local total, count = 0, 0
	for _, skill in ipairs(Data.SkillOrder) do
		total += Progression.levelForXp(p.xp and p.xp[skill] or 0)
		count += 1
	end
	return total, total / count
end
-- Adds XP with the 200M cap. Returns old level, new level.
function Progression.addXp(p, skill, amount)
	p.xp = p.xp or {}
	local before = p.xp[skill] or 0
	local oldLevel = Progression.levelForXp(before)
	p.xp[skill] = math.min(Data.MAX_XP, before + math.max(0, math.floor(amount)))
	return oldLevel, Progression.levelForXp(p.xp[skill])
end

------------------------------------------------------------------------------
-- Collections
------------------------------------------------------------------------------
function Progression.collectionThreshold(itemId, tier)
	local base = Data.CollectionTiers[tier]
	if not base then return nil end
	local scale = Data.CollectionScale[itemId] or 1
	return math.max(1, math.floor(base * scale))
end
function Progression.collectionTier(p, itemId)
	local count = p.collection and p.collection[itemId] or 0
	local tier = 0
	for t = 1, #Data.CollectionTiers do
		if count >= Progression.collectionThreshold(itemId, t) then tier = t else break end
	end
	return tier
end

------------------------------------------------------------------------------
-- Stats
------------------------------------------------------------------------------
local function addStats(into, stats, mult)
	if not stats then return end
	mult = mult or 1
	for k, v in pairs(stats) do into[k] = (into[k] or 0) + v * mult end
end
Progression.addStats = addStats

function Progression.slayerLevel(xp)
	local lvl = 0
	for i, need in ipairs(Data.SlayerLevels) do if (xp or 0) >= need then lvl = i else break end end
	return lvl
end
function Progression.accessorySlots(p)
	local bag = Data.AccessoryBag
	local combat = Progression.levelForXp(p.xp and p.xp.Combat or 0)
	local perk = math.clamp(math.floor(tonumber(p.perkAccessorySlots) or 0), 0, Data.MAX_PERK_SLOTS or 0)
	return math.min(bag.maxSlots, bag.baseSlots + combat // bag.slotsPerLevel.every) + perk
end
-- Quest/construction accessory-slot perks are counted above (server skips its wrapper).
Progression.perkSlotsIntegrated = true
function Progression.meetsRequirements(p, requires)
	if not requires then return true end
	for skill, lvl in pairs(requires) do
		if Progression.levelForXp(p.xp and p.xp[skill] or 0) < lvl then return false, skill.." "..lvl end
	end
	return true
end
-- Active accessories: owned, unique by id, within bag capacity, highest
-- rarity first (SkyBlock: duplicates do not stack).
function Progression.activeAccessories(p)
	local seen, list = {}, {}
	for _, id in ipairs(p.accessoryBag or {}) do
		local def = Data.Items[id]
		if def and def.kind == "accessory" and not seen[id] and (p.items[id] or 0) > 0 then
			seen[id] = true
			table.insert(list, id)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Data.Rarity[Data.Items[a].rarity].rank, Data.Rarity[Data.Items[b].rarity].rank
		if ra ~= rb then return ra > rb end
		return a < b
	end)
	local slots = Progression.accessorySlots(p)
	while #list > slots do table.remove(list) end
	return list
end
function Progression.magicalPower(p)
	local power = 0
	for _, id in ipairs(Progression.activeAccessories(p)) do power += Data.Rarity[Data.Items[id].rarity].power end
	return power
end
function Progression.petLevel(pet)
	return math.clamp(pet and pet.level or 1, 1, Data.PET_MAX_LEVEL)
end
function Progression.activePet(p)
	local pet = p.pets and p.activePet and p.pets[p.activePet]
	if pet and Data.PetById[pet.id] then return pet, Data.PetById[pet.id] end
	return nil
end
-- Pets earn the full XP of their skill and 25% of other skills.
function Progression.addPetXp(p, skill, amount)
	local pet, def = Progression.activePet(p)
	if not pet then return false end
	local gained = if def.skill == skill then amount else amount * 0.25
	pet.xp = (pet.xp or 0) + gained
	local leveled = false
	while pet.level < Data.PET_MAX_LEVEL do
		local need = Data.petXpToNext(pet.level, def.rarity)
		if pet.xp < need then break end
		pet.xp -= need
		pet.level += 1
		leveled = true
	end
	if pet.level >= Data.PET_MAX_LEVEL then pet.xp = 0 end
	return leveled
end
-- Valid equipped item: owned, matching slot, requirements met.
function Progression.equipped(p, slot)
	local id = p.equipment and p.equipment[slot]
	local def = id and Data.Items[id]
	if not def or def.slot ~= slot or (p.items[id] or 0) < 1 then return nil end
	if not Progression.meetsRequirements(p, def.requires) then return nil end
	return id, def
end
-- Legacy weapon/armor fall-back for older saves.
local function weaponFor(p)
	local id, def = Progression.equipped(p, "weapon")
	if id then return id, def end
	for _, legacy in ipairs({"Stormblade","Blade"}) do
		if (p.items[legacy] or 0) > 0 and Progression.meetsRequirements(p, Data.Items[legacy].requires) then return legacy, Data.Items[legacy] end
	end
	return nil
end
Progression.weaponFor = weaponFor

function Progression.enchantStats(p, itemId, kind, skill)
	local out = {}
	local enchants = p.enchants and p.enchants[itemId]
	if not enchants then return out end
	for enchantId, lvl in pairs(enchants) do
		local e = Data.Enchants[enchantId]
		if e and (e.appliesTo == kind or (kind=="armor" and e.appliesTo=="armor")) then
			for stat, v in pairs(e.perLevel) do
				if stat == "fortune" then
					if skill then out[Data.FortuneStat[skill]] = (out[Data.FortuneStat[skill]] or 0) + v * lvl end
				else
					out[stat] = (out[stat] or 0) + v * lvl
				end
			end
		end
	end
	return out
end

-- Full stat sheet. now = os.time() for buff expiry.
function Progression.computeStats(p, now)
	now = now or 0
	local s = {}
	for stat, def in pairs(Data.Stats) do s[stat] = def.base end
	s.damage, s.damagePercent, s.lifesteal = 0, 0, 0
	local breakdown = {}
	-- Skill levels
	for skill, def in pairs(Data.Skills) do
		local lvl = Progression.levelForXp(p.xp and p.xp[skill] or 0)
		addStats(s, def.perLevel, lvl - 1)
	end
	-- Combat level multiplies damage (SkyBlock: +4% per Combat level).
	s.combatBonus = (Progression.levelForXp(p.xp and p.xp.Combat or 0) - 1) * 4
	-- Weapon
	local weaponId, weapon = weaponFor(p)
	if weapon then
		addStats(s, weapon.stats)
		addStats(s, Progression.enchantStats(p, weaponId, "weapon"))
	end
	s.weapon = weaponId
	-- Armor + set bonus
	local setCount = {}
	for _, slot in ipairs(Data.ArmorSlots) do
		local id, def = Progression.equipped(p, slot)
		if not id and slot == "chest" and (p.items.Skyplate or 0) > 0 and not (p.equipment and p.equipment.chest) then
			id, def = "Skyplate", Data.Items.Skyplate
		end
		if def then
			addStats(s, def.stats)
			addStats(s, Progression.enchantStats(p, id, "armor"))
			if def.set then setCount[def.set] = (setCount[def.set] or 0) + 1 end
		end
	end
	s.activeSet = nil
	for setId, n in pairs(setCount) do
		if n >= 4 then addStats(s, Data.Sets[setId].bonus); s.activeSet = setId end
	end
	-- Accessories
	for _, id in ipairs(Progression.activeAccessories(p)) do addStats(s, Data.Items[id].stats) end
	s.magicalPower = Progression.magicalPower(p)
	-- Magical power grants scaling stats (SkyBlock accessory power).
	s.health += s.magicalPower * 1
	s.strength += math.floor(s.magicalPower / 4)
	-- Pet
	local pet, petDef = Progression.activePet(p)
	if pet then addStats(s, petDef.perLevel, Progression.petLevel(pet)) end
	-- Buffs
	for _, buff in pairs(p.buffs or {}) do
		if buff.expires and buff.expires > now then addStats(s, buff.stats) end
	end
	-- Bestiary: every milestone tier on any monster.
	local bestiaryTiers = 0
	for monsterId, kills in pairs(p.bestiary or {}) do
		if Data.Monsters[monsterId] then
			for _, need in ipairs(Data.BestiaryTiers) do if kills >= need then bestiaryTiers += 1 end end
		end
	end
	addStats(s, Data.BestiaryBonus, bestiaryTiers)
	s.bestiaryTiers = bestiaryTiers
	-- Slayer levels
	for line, def in pairs(Data.Slayers) do
		addStats(s, def.rewardStat, Progression.slayerLevel(p.slayerXp and p.slayerXp[line] or 0))
	end
	-- Mastery trees, running capstones and a worn mantle (no p.mastery: no change).
	if type(p.mastery) == "table" and Progression.masteryStats then
		for stat, v in pairs(Progression.masteryStats(p, now)) do s[stat] = (s[stat] or 0) + v end
	end
	-- Permanent perks from quests, achievement diaries and construction:
	-- p.perkStats = {[source] = {stat = value}}.
	if type(p.perkStats) == "table" then
		for _, perk in pairs(p.perkStats) do
			if type(perk) == "table" then
				for stat, v in pairs(perk) do
					if type(v) == "number" and v == v and (Data.Stats[stat] or stat == "damage") then s[stat] = (s[stat] or 0) + v end
				end
			end
		end
	end
	-- Legacy bonuses
	s.health += (p.companionBond or 0) * 2
	s.damage += (p.enchantRank or 0) * 3
	-- Caps and rounding
	for stat, def in pairs(Data.Stats) do
		if def.cap then s[stat] = math.min(def.cap, s[stat]) end
		s[stat] = math.floor(s[stat] * 10 + 0.5) / 10
	end
	s.health = math.floor(s.health)
	s.defense = math.floor(s.defense)
	s.effectiveHealth = math.floor(s.health * (1 + s.defense / 100))
	return s, breakdown
end

------------------------------------------------------------------------------
-- Combat math (SkyBlock formulas)
------------------------------------------------------------------------------
-- rng: function returning [0,1). Returns damage, crit.
function Progression.meleeDamage(stats, rng)
	local base = (5 + (stats.damage or 0)) * (1 + (stats.strength or 0) / 100)
	local mult = 1 + ((stats.combatBonus or 0) + (stats.damagePercent or 0)) / 100
	local crit = rng() * 100 < (stats.critChance or 0)
	local dmg = base * mult
	if crit then dmg *= 1 + (stats.critDamage or 0) / 100 end
	return math.max(1, math.floor(dmg)), crit
end
function Progression.damageReduction(defense)
	defense = math.max(0, defense or 0)
	return defense / (defense + 100)
end
function Progression.damageTaken(raw, defense)
	return math.max(1, math.floor(raw * (1 - Progression.damageReduction(defense))))
end
-- Walk speed from Speed stat (100 speed = Roblox default 16).
function Progression.walkSpeed(speed)
	return 16 * math.clamp(speed or 100, 50, 400) / 100
end

------------------------------------------------------------------------------
-- Gathering
------------------------------------------------------------------------------
function Progression.bestTool(p, skill)
	local kind = Data.ToolKind[skill]
	local bestId, bestDef = nil, nil
	for id, n in pairs(p.items or {}) do
		local def = Data.Items[id]
		if n > 0 and def and def.kind == "tool" and def.toolKind == kind and Progression.meetsRequirements(p, def.requires) then
			if not bestDef or def.toolTier > bestDef.toolTier or (def.toolTier == bestDef.toolTier and (def.value or 0) > (bestDef.value or 0)) then
				bestId, bestDef = id, def
			end
		end
	end
	return bestId, bestDef
end
function Progression.resource(resourceId)
	local skill = Data.ResourceSkill[resourceId]
	if not skill then return nil end
	for _, r in ipairs(Data.ResourceTiers[skill]) do if r.id == resourceId then return r end end
	return nil
end
-- Fortune: every 100 adds one guaranteed extra, remainder is a chance.
function Progression.fortuneRoll(base, fortune, rng)
	fortune = math.max(0, fortune or 0)
	local extra = math.floor(fortune / 100)
	local amount = base * (1 + extra)
	if rng() < (fortune % 100) / 100 then amount += base end
	return amount
end
-- Returns ok, reasonOrResult. result = {amount, xp, skill, tool}.
-- now (optional, os.time) lets running mastery capstones apply; mastery perks
-- may add result.bonus {[item]=n}, result.coins, result.respawnSkip.
function Progression.harvest(p, resourceId, stats, rng, bonusBase, now)
	local r = Progression.resource(resourceId)
	if not r then return false, "Unknown resource." end
	local lvl = Progression.levelForXp(p.xp and p.xp[r.skill] or 0)
	if lvl < r.level then return false, r.name.." requires "..r.skill.." "..r.level.."." end
	local toolId, tool = Progression.bestTool(p, r.skill)
	local toolTier = tool and tool.toolTier or 0
	if toolTier < r.tool then
		return false, r.name.." requires a tier "..r.tool.." "..string.lower(Data.ToolKind[r.skill]).."."
	end
	local fortuneStat = Data.FortuneStat[r.skill]
	local fortune = (stats and stats[fortuneStat] or 0)
	if tool then
		fortune += (tool.stats and tool.stats[fortuneStat] or 0)
		local ench = Progression.enchantStats(p, toolId, "tool", r.skill)
		fortune += ench[fortuneStat] or 0
	end
	local base = 1 + (bonusBase or 0)
	local amount = Progression.fortuneRoll(base, fortune, rng)
	local result = {amount=amount,xp=r.xp,skill=r.skill,tool=toolId,fortune=fortune,resource=r}
	if type(p.mastery) == "table" then Progression.applyGatherMastery(p, result, rng, now) end
	return true, result
end

------------------------------------------------------------------------------
-- Crafting
------------------------------------------------------------------------------
function Progression.canCraft(p, recipeId)
	local rec = Data.Recipes[recipeId]
	if not rec then return false, "Unknown recipe." end
	local lvl = Progression.levelForXp(p.xp and p.xp[rec.skill] or 0)
	if lvl < rec.level then return false, Data.Items[rec.output].name.." requires "..rec.skill.." "..rec.level.."." end
	for itemId, tier in pairs(rec.collectionTier or {}) do
		if Progression.collectionTier(p, itemId) < tier then
			return false, "Unlocks at "..Data.Items[itemId].name.." collection tier "..tier.." ("..Progression.collectionThreshold(itemId, tier).." lifetime)."
		end
	end
	for itemId, n in pairs(rec.costs) do
		if (p.items[itemId] or 0) < n then return false, "Needs "..n.." "..Data.Items[itemId].name.."." end
	end
	if not rec.repeatable and Data.Items[rec.output].kind ~= "material" and (p.items[rec.output] or 0) > 0
		and Data.Items[rec.output].kind ~= "consumable" then
		return false, "You already own "..Data.Items[rec.output].name.."."
	end
	return true
end

------------------------------------------------------------------------------
-- Loot
------------------------------------------------------------------------------
-- Magic Find boosts rare drops (chance < 5%) multiplicatively.
function Progression.rollDrops(drops, magicFind, rng, petLuck)
	local out = {}
	for _, d in ipairs(drops) do
		local chance = d.chance
		if chance < 0.05 then
			local bonus = (magicFind or 0)
			if Data.Items[d.item] and Data.Items[d.item].kind == "pet" then bonus += (petLuck or 0) end
			chance *= 1 + bonus / 100
		end
		if rng() < chance then
			local n = d.min + math.floor(rng() * (d.max - d.min + 1))
			out[d.item] = (out[d.item] or 0) + n
		end
	end
	return out
end

------------------------------------------------------------------------------
-- Combat styles (melee / ranged / magic triangle, mana). New, additive rules;
-- data in Data.CombatStyles, Data.Spells and the weapon/arrow item fields.
------------------------------------------------------------------------------
local STYLES = {melee=true,ranged=true,magic=true}
local function styles() return Data.CombatStyles end
-- Style of a weapon definition (nil/unarmed and swords are melee).
function Progression.weaponStyle(def)
	if type(def) == "table" and STYLES[def.style] then return def.style end
	return "melee"
end
-- Seconds between attacks for a weapon speed, reduced by Attack Speed (capped at 100).
function Progression.weaponCooldown(speed, attackSpeed)
	local as = math.clamp(tonumber(attackSpeed) or 0, 0, 100)
	return math.max(0.1, tonumber(speed) or 1) / (1 + as / 100)
end
-- Triangle modifier for a style against a monster/slayer definition.
-- Returns multiplier, tag ("weak" | "resist" | nil).
function Progression.styleModifier(style, def)
	local cs = styles()
	if type(def) ~= "table" or not STYLES[style] then return 1, nil end
	if def.weakness == style then return 1 + cs.weaknessBonus, "weak" end
	if def.defenceStyle == style then return 1 - cs.resistPenalty, "resist" end
	return 1, nil
end
-- Ranged hit chance (OSRS-style attack/defence rolls, softened for real time).
-- attack = (rangedLevel + 8) * (accuracy + 64); defence = (monsterLevel + 8) * (defense/4 + 64)
-- chance = parity + 0.5 * (attack - defence) / max(attack, defence), clamped.
function Progression.hitChance(accuracy, level, monsterLevel, monsterDefense)
	local cs = styles()
	local attack = (math.max(1, tonumber(level) or 1) + 8) * (math.max(0, tonumber(accuracy) or 0) + 64)
	local defence = (math.max(1, tonumber(monsterLevel) or 1) + 8) * (math.max(0, tonumber(monsterDefense) or 0) / 4 + 64)
	local chance = cs.accuracyParity + 0.5 * (attack - defence) / math.max(attack, defence)
	return math.clamp(chance, cs.hitFloor, cs.hitCeiling)
end
-- Ranged damage (SkyBlock bow formula with OSRS ammo):
-- (5 + bow power + arrow power) * (1 + rangedStrength/100)
--   * (1 + (4 * (rangedLevel - 1) + damagePercent)/100), crits like melee.
-- rng: function returning [0,1). Returns damage, crit.
function Progression.rangedDamage(stats, bow, arrow, rangedLevel, rng)
	stats = stats or {}
	local power = 5 + (bow and bow.ranged and bow.ranged.power or 0) + (arrow and arrow.ammo and arrow.ammo.power or 0)
	local base = power * (1 + (stats.rangedStrength or 0) / 100)
	local mult = 1 + (4 * (math.max(1, rangedLevel or 1) - 1) + (stats.damagePercent or 0)) / 100
	local crit = rng() * 100 < (stats.critChance or 0)
	local dmg = base * mult
	if crit then dmg *= 1 + (stats.critDamage or 0) / 100 end
	return math.max(1, math.floor(dmg)), crit
end
-- Spell damage (SkyBlock ability formula, scaled by Magic level; never crits):
-- (spell damage + weapon magic power) * (1 + intelligence/100 * scaling)
--   * (1 + abilityDamage/100) * (1 + 0.03 * (magicLevel - 1))
function Progression.spellDamage(stats, spell, weapon, magicLevel)
	stats = stats or {}
	if type(spell) ~= "table" or not spell.damage then return 0 end
	local power = spell.damage + (weapon and weapon.magic and weapon.magic.power or 0)
	local dmg = power * (1 + math.max(0, stats.intelligence or 0) / 100 * (spell.scaling or 0))
		* (1 + (stats.abilityDamage or 0) / 100) * (1 + 0.03 * (math.max(1, magicLevel or 1) - 1))
	return math.max(1, math.floor(dmg))
end
-- Mana (SkyBlock): max mana = Intelligence; regenerates a share of max per second.
function Progression.maxMana(stats)
	return math.max(0, math.floor(tonumber(stats and stats.intelligence) or 0))
end
function Progression.manaRegen(maxMana)
	return math.max(0, tonumber(maxMana) or 0) * styles().manaRegenPercent / 100
end
-- Glyph items a cast consumes: the spell's costs minus elemental glyphs the
-- wielded staff supplies (OSRS elemental staves).
function Progression.glyphCost(spell, weapon)
	local out = {}
	if type(spell) ~= "table" then return out end
	local free = {}
	for _, element in ipairs(weapon and weapon.magic and weapon.magic.elements or {}) do
		local e = styles().elements[element]
		if e then free[e.glyph] = true end
	end
	for id, n in pairs(spell.costs or {}) do
		if not free[id] then out[id] = n end
	end
	return out
end
-- XP for damage dealt with a style. monsterXp/monsterHp give the XP rate.
-- Melee trains Combat; ranged/magic train their skill plus a Combat share.
function Progression.styleXp(style, damage, monsterXp, monsterHp)
	local cs = styles()
	local out = {}
	damage, monsterXp, monsterHp = tonumber(damage) or 0, tonumber(monsterXp) or 0, tonumber(monsterHp) or 0
	if not STYLES[style] or damage <= 0 or monsterXp <= 0 or monsterHp <= 0 then return out end
	local xp = math.min(damage, monsterHp) * monsterXp / monsterHp * cs.damageXpRate
	out[cs.skill[style]] = xp
	if style ~= "melee" then out.Combat = (out.Combat or 0) + xp * cs.combatShare end
	return out
end
-- Can this profile cast the spell right now (level + weapon only; costs and
-- mana are checked by the caller)? Returns ok, reason.
function Progression.spellAllowed(loadout, spell)
	if type(spell) ~= "table" then return false, "spell" end
	local magic = loadout and loadout.levels and loadout.levels.Magic or 1
	if magic < (spell.level or 1) then return false, "level" end
	if spell.requiresWeapon and (not loadout or loadout.style ~= "magic") then return false, "weapon" end
	return true
end
-- Combat loadout for the server bridge and the snapshot: style from the
-- wielded weapon, quiver contents, combat supplies and style levels.
function Progression.combatLoadout(p)
	local weaponId, weapon = weaponFor(p)
	local ammoId = Progression.equipped(p, styles().ammoSlot)
	local supplies = {}
	for id, n in pairs(p.items or {}) do
		local def = Data.Items[id]
		if def and def.combatUse and type(n) == "number" and n > 0 then supplies[id] = n end
	end
	local levels = {}
	for _, skill in ipairs({"Combat","Ranged","Magic"}) do levels[skill] = Progression.levelForXp(p.xp and p.xp[skill] or 0) end
	local autocast = p.autocast
	local spell = type(autocast) == "string" and Data.Spells[autocast]
	if not spell or not spell.autocast or levels.Magic < spell.level then autocast = nil end
	return {style=Progression.weaponStyle(weapon),weapon=weaponId,ammo=ammoId,ammoCount=ammoId and (p.items[ammoId] or 0) or 0,
		supplies=supplies,levels=levels,autocast=autocast}
end

------------------------------------------------------------------------------
-- Mastery: perk trees, points, capstone abilities, milestones and mantles
-- (Data.Mastery). Pure functions over p.mastery (all optional):
--   p.mastery = {trees={[tree]={[node]=level}}, respecs={[tree]=n},
--     cooldowns={[tree]=readyAt}, active={[tree]={started,expires}}, cape=skill}
-- A profile without p.mastery gets exactly the pre-mastery numbers (and no
-- extra rng draws).
------------------------------------------------------------------------------
local function MA() return Data.Mastery end
local function masteryOf(p) return type(p) == "table" and type(p.mastery) == "table" and p.mastery or nil end
local function treeNodes(p, treeId)
	local m = masteryOf(p)
	local trees = m and type(m.trees) == "table" and m.trees
	local nodes = trees and trees[treeId]
	return type(nodes) == "table" and nodes or nil
end
local function skillLevel(p, skill) return Progression.levelForXp(p.xp and p.xp[skill] or 0) end
function Progression.masteryTree(treeId) return MA() and MA().TreeById[treeId] or nil end
function Progression.masteryNodeLevel(p, treeId, nodeId)
	local nodes = treeNodes(p, treeId)
	local v = nodes and nodes[nodeId]
	return type(v) == "number" and v == v and math.max(0, math.floor(v)) or 0
end
function Progression.masterySpent(p, treeId)
	local tree = Progression.masteryTree(treeId)
	if not tree then return 0 end
	local spent = 0
	for _, n in ipairs(tree.nodes) do spent += Progression.masteryNodeLevel(p, treeId, n.id) * n.cost end
	return spent
end
-- Points a skill has earned: 1 per level above POINT_START_LEVEL plus 1 per
-- POST_MAX_STEP XP beyond level 99 (OSRS-style post-99 progression).
function Progression.masteryEarned(p, skill)
	local ma = MA()
	local xp = math.max(0, tonumber(p.xp and p.xp[skill]) or 0)
	local points = math.max(0, Progression.levelForXp(xp) - ma.POINT_START_LEVEL)
	local beyond = xp - Data.XP_TABLE[Data.MAX_LEVEL]
	if beyond > 0 then points += math.floor(beyond / ma.POST_MAX_STEP) end
	return points
end
-- Mastery Tokens: one per collection that reached each TOKEN_TIERS tier.
function Progression.masteryTokens(p)
	local tokens = 0
	for _, id in ipairs(Data.CollectionItems) do
		local tier = Progression.collectionTier(p, id)
		for _, t in ipairs(MA().TOKEN_TIERS) do if tier >= t then tokens += 1 end end
	end
	return tokens
end
-- Full point accounting. Tokens pay for whatever a tree's own points cannot,
-- so token use is derived (never stored): used = sum(max(0, spent - earned)).
function Progression.masteryPoints(p)
	local out = {trees={}, tokens={earned=Progression.masteryTokens(p), used=0, free=0}}
	for _, tree in ipairs(MA().Trees) do
		local earned, spent = Progression.masteryEarned(p, tree.skill), Progression.masterySpent(p, tree.id)
		out.trees[tree.id] = {earned=earned, spent=spent, own=math.max(0, earned - spent)}
		out.tokens.used += math.max(0, spent - earned)
	end
	out.tokens.free = math.max(0, out.tokens.earned - out.tokens.used)
	for _, entry in pairs(out.trees) do entry.available = entry.own + out.tokens.free end
	return out
end
-- Node availability: "owned" (max level), "available" (can buy the next level
-- now), "open" (prerequisites met, short of points/level), "locked".
-- Returns ok, reason, cost.
function Progression.masteryCanUnlock(p, treeId, nodeId)
	local tree = Progression.masteryTree(treeId)
	if not tree then return false, "Unknown mastery tree." end
	local node = tree.NodeById[nodeId]
	if not node then return false, "Unknown mastery node." end
	local have = Progression.masteryNodeLevel(p, treeId, nodeId)
	if have >= node.max then return false, node.name.." is already at its maximum level." end
	if #node.requires > 0 then
		local linked = false
		for _, req in ipairs(node.requires) do
			if Progression.masteryNodeLevel(p, treeId, req) > 0 then linked = true break end
		end
		if not linked then
			local names = {}
			for _, req in ipairs(node.requires) do table.insert(names, tree.NodeById[req].name) end
			return false, node.name.." needs "..table.concat(names, " or ").." first."
		end
	end
	if skillLevel(p, tree.skill) < node.level then return false, node.name.." requires "..tree.skill.." "..node.level.."." end
	local points = Progression.masteryPoints(p)
	if points.trees[treeId].available < node.cost then
		return false, node.name.." costs "..node.cost.." mastery point"..(if node.cost == 1 then "" else "s").." ("..points.trees[treeId].available.." available)."
	end
	return true, nil, node.cost
end
function Progression.masteryNodeState(p, treeId, nodeId)
	local tree = Progression.masteryTree(treeId)
	local node = tree and tree.NodeById[nodeId]
	if not node then return "locked" end
	local have = Progression.masteryNodeLevel(p, treeId, nodeId)
	if have >= node.max then return "owned" end
	if Progression.masteryCanUnlock(p, treeId, nodeId) then return "available" end
	local linked = #node.requires == 0
	for _, req in ipairs(node.requires) do if Progression.masteryNodeLevel(p, treeId, req) > 0 then linked = true end end
	if linked then return if have > 0 then "partial" else "open" end
	return "locked"
end
local function ensureMastery(p)
	if type(p.mastery) ~= "table" then p.mastery = {} end
	local m = p.mastery
	for _, key in ipairs({"trees","respecs","cooldowns","active"}) do
		if type(m[key]) ~= "table" then m[key] = {} end
	end
	return m
end
Progression.ensureMastery = ensureMastery
-- Buys one level of a node. Returns ok, reasonOrNewLevel.
function Progression.masteryUnlock(p, treeId, nodeId)
	local ok, why = Progression.masteryCanUnlock(p, treeId, nodeId)
	if not ok then return false, why end
	local m = ensureMastery(p)
	m.trees[treeId] = m.trees[treeId] or {}
	local level = Progression.masteryNodeLevel(p, treeId, nodeId) + 1
	m.trees[treeId][nodeId] = level
	return true, level
end
-- Respec price for a tree right now.
function Progression.masteryRespecCost(p, treeId)
	local m = masteryOf(p)
	local count = m and type(m.respecs) == "table" and tonumber(m.respecs[treeId]) or 0
	return MA().respecCost(Progression.masterySpent(p, treeId), count)
end
-- Refunds every point in a tree for coins. Returns ok, reasonOrCost.
function Progression.masteryRespec(p, treeId)
	local tree = Progression.masteryTree(treeId)
	if not tree then return false, "Unknown mastery tree." end
	local spent = Progression.masterySpent(p, treeId)
	if spent <= 0 then return false, "Nothing to reset in the "..tree.name.."." end
	local cost = Progression.masteryRespecCost(p, treeId)
	if (tonumber(p.coins) or 0) < cost then return false, "Resetting the "..tree.name.." costs "..cost.." coins." end
	local m = ensureMastery(p)
	p.coins -= cost
	m.trees[treeId] = {}
	m.respecs[treeId] = (tonumber(m.respecs[treeId]) or 0) + 1
	m.active[treeId] = nil
	return true, cost
end
-- Capstone ability record while it runs (started <= now < expires).
function Progression.masteryActive(p, treeId, now)
	local tree = Progression.masteryTree(treeId)
	if not tree or not tree.capstone or Progression.masteryNodeLevel(p, treeId, tree.capstone) < 1 then return nil end
	local m = masteryOf(p)
	local a = m and type(m.active) == "table" and m.active[treeId]
	now = tonumber(now) or 0
	if type(a) == "table" and tonumber(a.started) and tonumber(a.expires) and now >= a.started and now < a.expires then
		return tree.NodeById[tree.capstone].ability, a
	end
	return nil
end
-- Seconds until a capstone may fire again (0 = ready).
function Progression.masteryCooldown(p, treeId, now)
	local m = masteryOf(p)
	local readyAt = m and type(m.cooldowns) == "table" and tonumber(m.cooldowns[treeId]) or 0
	return math.max(0, readyAt - (tonumber(now) or 0))
end
-- Fires a capstone. Returns ok, reasonOrAbility.
function Progression.masteryActivate(p, treeId, now)
	local tree = Progression.masteryTree(treeId)
	if not tree or not tree.capstone then return false, "Unknown mastery tree." end
	local node = tree.NodeById[tree.capstone]
	if Progression.masteryNodeLevel(p, treeId, node.id) < 1 then return false, "Unlock "..node.name.." in the "..tree.name.." first." end
	local wait = Progression.masteryCooldown(p, treeId, now)
	if wait > 0 then return false, node.name.." is recharging ("..math.ceil(wait).."s)." end
	local m = ensureMastery(p)
	m.active[treeId] = {started=now, expires=now + node.ability.duration}
	m.cooldowns[treeId] = now + node.ability.cooldown
	return true, node.ability
end
-- Summed perks of one tree (node perks x level, plus a running capstone's
-- perk fields). Chance perks cap at PERK_CAP.
local ABILITY_PERKS = {"yieldMult","respawnSkip","doubleYield","multishot","manaThrift","glyphSave","xpBoost"}
function Progression.masteryPerks(p, treeId, now)
	local out = {}
	local tree = Progression.masteryTree(treeId)
	if not tree or not treeNodes(p, treeId) then return out end
	for _, n in ipairs(tree.nodes) do
		local lvl = Progression.masteryNodeLevel(p, treeId, n.id)
		if lvl > 0 and n.perks then
			for k, v in pairs(n.perks) do out[k] = (out[k] or 0) + v * math.min(lvl, n.max) end
		end
	end
	local ability = Progression.masteryActive(p, treeId, now)
	if ability then
		for _, k in ipairs(ABILITY_PERKS) do
			if ability[k] then
				if k == "yieldMult" or k == "multishot" then out[k] = math.max(out[k] or 1, ability[k])
				else out[k] = (out[k] or 0) + ability[k] end
			end
		end
	end
	for k, v in pairs(out) do
		if k ~= "yieldMult" and k ~= "multishot" and k ~= "rareFind" then out[k] = math.min(MA().PERK_CAP, v) end
	end
	return out
end
-- Worn mantle (skillcape): the skill must be at level 99.
function Progression.masteryCape(p)
	local m = masteryOf(p)
	local skill = m and m.cape
	if type(skill) == "string" and Data.Skills[skill] and skillLevel(p, skill) >= Data.MAX_LEVEL then return skill end
	return nil
end
-- Stats from every tree, running capstones and the worn mantle.
function Progression.masteryStats(p, now)
	local out = {}
	if not masteryOf(p) then return out end
	for _, tree in ipairs(MA().Trees) do
		if treeNodes(p, tree.id) then
			for _, n in ipairs(tree.nodes) do
				local lvl = Progression.masteryNodeLevel(p, tree.id, n.id)
				if lvl > 0 and n.stats then addStats(out, n.stats, math.min(lvl, n.max)) end
			end
			local ability = Progression.masteryActive(p, tree.id, now)
			if ability and ability.stats then addStats(out, ability.stats) end
		end
	end
	local cape = Progression.masteryCape(p)
	if cape then addStats(out, MA().capePerk(cape)) end
	return out
end
-- Combat-side perks for combat.server.lua (bridge "stats" → result.mastery).
function Progression.masteryCombat(p, now)
	local melee, ranged, magic = Progression.masteryPerks(p, "Melee", now), Progression.masteryPerks(p, "Ranged", now), Progression.masteryPerks(p, "Magic", now)
	local active = {}
	for _, id in ipairs({"Melee","Ranged","Magic"}) do
		local _, a = Progression.masteryActive(p, id, now)
		if a then active[id] = a.expires end
	end
	return {
		melee={firstStrike=melee.firstStrike or 0, execute=melee.execute or 0, xpBoost=melee.xpBoost or 0},
		ranged={firstStrike=ranged.firstStrike or 0, execute=ranged.execute or 0, arrowSave=ranged.arrowSave or 0,
			multishot=math.max(1, ranged.multishot or 1), xpBoost=ranged.xpBoost or 0},
		magic={manaThrift=magic.manaThrift or 0, glyphSave=magic.glyphSave or 0, xpBoost=magic.xpBoost or 0},
		active=active,
	}
end
-- Gathering perks on a harvest result (yield, XP, regrowth, ingots, coins).
-- Rolls happen only for perks the profile owns, in a fixed order.
function Progression.applyGatherMastery(p, result, rng, now)
	local r = result.resource
	local treeId = MA().TreeOfSkill[r.skill]
	if not treeId then return result end
	local perks = Progression.masteryPerks(p, treeId, now)
	if not next(perks) then return result end
	if (perks.yieldMult or 1) > 1 then result.amount = math.floor(result.amount * perks.yieldMult); result.surge = true end
	if (perks.tripleYield or 0) > 0 and rng() < perks.tripleYield / 100 then
		result.amount *= 3; result.multiplied = 3
	elseif (perks.doubleYield or 0) > 0 and rng() < perks.doubleYield / 100 then
		result.amount *= 2; result.multiplied = 2
	end
	if (perks.xpBoost or 0) > 0 then result.xp = math.floor(result.xp * (1 + perks.xpBoost / 100)) end
	local skip = perks.respawnSkip or 0
	if skip >= 100 or (skip > 0 and rng() < skip / 100) then result.respawnSkip = true end
	local ingot = MA().SmeltOf[r.id]
	if ingot and Data.Items[ingot] and (perks.autoSmelt or 0) > 0 and rng() < perks.autoSmelt / 100 then
		result.bonus = result.bonus or {}
		result.bonus[ingot] = (result.bonus[ingot] or 0) + 1
	end
	if (perks.coinFind or 0) > 0 and rng() < perks.coinFind / 100 then result.coins = math.max(1, (r.value or 1) * 5) end
	return result
end
-- Hunter catch perks: drops x2 on a Twin Snare proc (or always under Lure
-- Song), XP boost. Returns drops, xp, doubled.
function Progression.applyHuntMastery(p, drops, xp, rng, now)
	local perks = Progression.masteryPerks(p, "Hunter", now)
	local doubled = false
	local chance = perks.doubleYield or 0
	if chance >= 100 or (chance > 0 and rng() < chance / 100) then
		for id, n in pairs(drops) do drops[id] = n * 2 end
		doubled = true
	end
	if (perks.xpBoost or 0) > 0 then xp = math.floor(xp * (1 + perks.xpBoost / 100)) end
	return drops, xp, doubled
end
-- Milestones for a skill with reached flags (OSRS-style unlock list).
function Progression.milestones(p, skill)
	local lvl = skillLevel(p, skill)
	local out = {}
	for _, m in ipairs(MA().milestones(skill)) do
		local entry = table.clone(m)
		entry.reached = lvl >= m.level
		table.insert(out, entry)
	end
	return out
end
-- Snapshot view (server → client depth.mastery). Points are computed once.
-- trees[id] = {nodes={[node]=level}, states={[node]=owned|available|partial|open|locked},
--   earned, spent, available, respecCost, respecs, cooldown (s), active (s left), capstone (owned)}
function Progression.masteryView(p, now)
	local points = Progression.masteryPoints(p)
	local m = masteryOf(p) or {}
	local trees = {}
	for _, tree in ipairs(MA().Trees) do
		local nodes, states = {}, {}
		local entry = points.trees[tree.id]
		local lvl = skillLevel(p, tree.skill)
		for _, n in ipairs(tree.nodes) do
			local have = Progression.masteryNodeLevel(p, tree.id, n.id)
			if have > 0 then nodes[n.id] = have end
			local st
			if have >= n.max then st = "owned"
			else
				local linked = #n.requires == 0
				for _, req in ipairs(n.requires) do if Progression.masteryNodeLevel(p, tree.id, req) > 0 then linked = true end end
				if not linked then st = "locked"
				elseif lvl >= n.level and entry.available >= n.cost then st = "available"
				else st = if have > 0 then "partial" else "open" end
			end
			states[n.id] = st
		end
		local _, active = Progression.masteryActive(p, tree.id, now)
		trees[tree.id] = {nodes=nodes, states=states, earned=entry.earned, spent=entry.spent, available=entry.available,
			respecCost=Progression.masteryRespecCost(p, tree.id), respecs=type(m.respecs) == "table" and tonumber(m.respecs[tree.id]) or 0,
			cooldown=Progression.masteryCooldown(p, tree.id, now), active=if active then active.expires - (tonumber(now) or 0) else 0,
			capstone=tree.capstone ~= nil and Progression.masteryNodeLevel(p, tree.id, tree.capstone) > 0}
	end
	local capes, titles = {}, {}
	for _, skill in ipairs(Data.SkillOrder) do
		local lvl = skillLevel(p, skill)
		if lvl >= Data.MAX_LEVEL then table.insert(capes, skill) end
		titles[skill] = MA().title(skill, lvl)
	end
	return {trees=trees, tokens=points.tokens, capes=capes, titles=titles, cape=Progression.masteryCape(p),
		aura=type(m.aura) == "string" and m.aura or nil, title=type(m.title) == "string" and m.title or nil}
end
-- Sanitises a loaded p.mastery: unknown trees/nodes dropped, levels clamped,
-- nodes whose prerequisites or skill gate fail removed (row order), and an
-- overspent tree (beyond its points + tokens) reset. Returns trees reset.
function Progression.masteryMigrate(p)
	if p.mastery == nil then return {} end
	local m = ensureMastery(p)
	local reset = {}
	local trees = {}
	for _, tree in ipairs(MA().Trees) do
		local raw = type(m.trees[tree.id]) == "table" and m.trees[tree.id] or {}
		local clean = {}
		local order = table.clone(tree.nodes)
		table.sort(order, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.index < b.index end)
		local lvl = skillLevel(p, tree.skill)
		for _, n in ipairs(order) do
			local v = tonumber(raw[n.id])
			if v and v == v and v >= 1 and lvl >= n.level then
				local linked = #n.requires == 0
				for _, req in ipairs(n.requires) do if (clean[req] or 0) > 0 then linked = true end end
				if linked then clean[n.id] = math.clamp(math.floor(v), 1, n.max) end
			end
		end
		trees[tree.id] = clean
	end
	m.trees = trees
	-- Overspend: reset trees (last in TreeOrder first) until tokens cover the deficit.
	local points = Progression.masteryPoints(p)
	local i = #MA().TreeOrder
	while points.tokens.used > points.tokens.earned and i >= 1 do
		local id = MA().TreeOrder[i]
		if points.trees[id].spent > points.trees[id].earned then
			m.trees[id] = {}
			table.insert(reset, id)
			points = Progression.masteryPoints(p)
		end
		i -= 1
	end
	for _, key in ipairs({"respecs","cooldowns"}) do
		local clean = {}
		for id, v in pairs(m[key]) do
			local n = tonumber(v)
			if MA().TreeById[id] and n and n == n and n >= 0 then clean[id] = math.floor(n) end
		end
		m[key] = clean
	end
	local active = {}
	for id, a in pairs(m.active) do
		if MA().TreeById[id] and type(a) == "table" and tonumber(a.started) and tonumber(a.expires) then
			active[id] = {started=tonumber(a.started), expires=tonumber(a.expires)}
		end
	end
	m.active = active
	for _, key in ipairs({"cape","aura","title"}) do
		if m[key] ~= nil and not (type(m[key]) == "string" and Data.Skills[m[key]]) then m[key] = nil end
	end
	return reset
end

return Progression
