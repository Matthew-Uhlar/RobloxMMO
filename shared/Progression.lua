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
	return math.min(bag.maxSlots, bag.baseSlots + combat // bag.slotsPerLevel.every)
end
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
function Progression.harvest(p, resourceId, stats, rng, bonusBase)
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
	return true, {amount=amount,xp=r.xp,skill=r.skill,tool=toolId,fortune=fortune,resource=r}
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

return Progression
