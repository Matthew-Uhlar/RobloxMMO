-- Endgame QA: the Shattered Crown data (region, monsters, tiers, gear, quests,
-- diary), world boss rules (phases, telegraphs, adds/ward, enrage, departure),
-- contribution loot weighting with deterministic rolls, anti-leech credit, the
-- calendar schedule and the Sovereign Altar. Pure: shared data + Progression +
-- the combat logic core through __CombatTestHarness (no Roblox services).
-- World placement lives in verify-world.luau (Endgame block), the server bridge
-- in verify-gameplay.luau, the HUD in verify-ui.luau.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local Combat
load("combat.server.lua", {
	Vector3 = Vector3, CFrame = CFrame, Color3 = Color3,
	__CombatTestHarness = function(exports) Combat = exports end,
})
assert(Combat, "combat harness")
local E = Data.Endgame
local WB = Data.WorldBosses

local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(actual, expected, case)
	assert(actual == expected, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function near(actual, expected, case)
	assert(math.abs(actual - expected) < 1e-6, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end

------------------------------------------------------------------------------
-- 1. Data integrity
------------------------------------------------------------------------------
local dataChecks = checks
do
	-- Region and gate.
	local region = Data.RegionById.ShatteredCrown
	ok(region ~= nil and table.find(Data.Regions, region) ~= nil, "region registered")
	eq(region.requires.skills.Combat, 60, "Combat 60 gate")
	eq(region.requires.questsDone[1], "CrownOfTempest", "quest gate")
	ok(Data.QuestById.CrownOfTempest ~= nil, "gate quest exists")
	ok(not E.regionOpen(region, {Combat = 59}, {CrownOfTempest = true}, 20), "Combat 59 refused")
	ok(not E.regionOpen(region, {Combat = 99}, {}, 20), "quest missing refused")
	ok(E.regionOpen(region, {Combat = 60}, {CrownOfTempest = true}, 0), "Combat 60 + quest opens")
	ok(E.regionOpen(Data.RegionById.Hub, {}, {}, 0), "ungated region open")
	ok(not E.regionOpen(Data.RegionById.Tempest, {Combat = 39}, {}, 0), "pure gate reads skills")
	local parts = E.requirementParts(region)
	ok(table.find(parts, "Combat 60") ~= nil and table.find(parts, "Quest: Crown of the Tempest") ~= nil, "requirement text")
	-- Monsters: 4 types, levels 85-110, triangle fields, drops valid.
	eq(#E.MonsterOrder, 4, "four regional monsters")
	local styles, lastLevel = {}, 0
	for _, id in ipairs(E.MonsterOrder) do
		local m = Data.Monsters[id]
		ok(rawget(Data.Monsters, id) == m, id .. " is a marker monster (pairs)")
		ok(m.level >= 85 and m.level <= 110, id .. " level 85-110")
		ok(m.level > lastLevel, id .. " tiers rise")
		lastLevel = m.level
		eq(m.region, "ShatteredCrown", id .. " region")
		ok(table.find(region.monsters, id) ~= nil, id .. " listed by the region")
		ok(m.hp > Data.Monsters.StarbornSentinel.hp, id .. " out-tanks the Starborn Sentinel")
		ok(m.attackStyle and m.weakness == Data.CombatStyles.beatenBy[m.attackStyle] and m.defenceStyle == Data.CombatStyles.beats[m.attackStyle], id .. " triangle")
		styles[m.attackStyle] = true
		ok(Combat.BODY_KIND[id] ~= nil, id .. " has a body")
		for _, d in ipairs(m.drops) do
			ok(Data.Items[d.item] ~= nil and d.chance > 0 and d.chance <= 1 and d.min <= d.max, id .. " drop " .. d.item)
		end
		local hasShard = false
		for _, d in ipairs(m.drops) do if d.item == "CrownShard" then hasShard = true end end
		ok(hasShard, id .. " drops Crown Shards")
	end
	ok(styles.melee and styles.magic and styles.ranged, "all three triangle styles among the monsters")
	-- Resource tiers: level 90+, tool tier 7, items + collections + skill lookup.
	for _, r in ipairs(E.Resources) do
		local tiers = Data.ResourceTiers[r.skill]
		local def = tiers[#tiers]
		eq(def.id, r.id, r.id .. " is the top " .. r.skill .. " tier")
		ok(def.level >= 90, r.id .. " level 90+")
		eq(def.tool, 7, r.id .. " needs a tier 7 tool")
		eq(Data.ResourceSkill[r.id], r.skill, r.id .. " skill lookup")
		eq(P.resource(r.id), def, r.id .. " Progression.resource")
		ok(Data.Items[r.id] and Data.Items[r.id].kind == "resource", r.id .. " item")
		ok(table.find(Data.CollectionItems, r.id) ~= nil, r.id .. " collection")
		ok(def.level > tiers[#tiers - 1].level, r.id .. " above the previous tier")
	end
	-- Crownforged tools: tier 8 via Smithing recipes.
	for _, id in ipairs(E.ToolOrder) do
		local def, rec = Data.Items[id], Data.Recipes[id]
		eq(def.toolTier, 8, id .. " tool tier 8")
		ok(rec and rec.skill == "Smithing" and rec.level >= 90 and rec.station == "Forge", id .. " Smithing 90 recipe")
		local celestial = Data.Items["Celestial" .. def.toolKind]
		ok(celestial and celestial.toolTier < def.toolTier, id .. " outranks the Celestial tool")
		for stat, v in pairs(celestial.stats) do ok((def.stats[stat] or 0) >= v, id .. " " .. stat .. " >= Celestial") end
	end
	-- Materials, collections.
	for _, id in ipairs({"CrownShard", "RiftHide", "SeerGlass", "ColossusCore", "DrakeScale", "SovereignEssence"}) do
		ok(Data.Items[id] ~= nil, id .. " item")
		ok(table.find(Data.CollectionItems, id) ~= nil and Data.CollectionScale[id] ~= nil, id .. " drop-scaled collection")
	end
	-- Every recipe in the section: valid items, skill, level, station.
	local endgameRecipes = {"CrownsteelIngot", "CookedRiftfin", "CrownSigil"}
	for _, id in ipairs(E.ToolOrder) do table.insert(endgameRecipes, id) end
	for _, id in ipairs(E.GearOrder) do table.insert(endgameRecipes, id) end
	for _, id in ipairs(endgameRecipes) do
		local rec = Data.Recipes[id]
		ok(rec ~= nil, id .. " recipe")
		ok(Data.Skills[rec.skill] ~= nil and rec.level >= 85 and rec.level <= 99, id .. " recipe skill/level")
		ok(rec.station == "Forge" or rec.station == "Workbench" or rec.station == "Cauldron" or rec.station == "Hearth", id .. " station")
		for item, n in pairs(rec.costs) do ok(Data.Items[item] ~= nil and n >= 1, id .. " cost " .. item) end
		ok(Data.Items[rec.output] ~= nil, id .. " output item")
	end
	-- Gear: one set per style, above Celestial, set bonus, systems apply.
	eq(#E.Sets, 3, "three endgame sets")
	local setStyles = {}
	local cel = Data.Items.CelestialSword.stats
	for _, set in ipairs(E.Sets) do
		setStyles[set.style] = true
		local dataSet = Data.Sets[set.id]
		eq(#dataSet.pieces, 4, set.id .. " four pieces")
		eq(Data.Recipes[set.weapon.id].skill, set.skill, set.id .. " weapon crafted with " .. set.skill)
		ok(set.level >= 90, set.id .. " crafted at 90+")
		local bonusTotal, celestialBonus = 0, 0
		for _, v in pairs(set.bonus) do bonusTotal += v end
		for _, v in pairs(Data.Sets.Celestial.bonus) do celestialBonus += v end
		ok(bonusTotal > celestialBonus, set.id .. " set bonus outweighs Ascendant")
		for _, piece in ipairs(dataSet.pieces) do
			local def = Data.Items[piece]
			local celestialPiece = Data.Items["Celestial" .. ({helmet = "Helm", chest = "Chestplate", legs = "Greaves", boots = "Boots"})[def.slot]]
			ok(def.stats.health > celestialPiece.stats.health, piece .. " health above Celestial")
			eq(Data.Gear.category(def), "armor", piece .. " reforge category")
			ok(Data.Gear.canStar("armor") and Data.Gear.canTemper("armor"), piece .. " stars and tempering")
			eq(Data.Recipes[piece].skill, set.skill, piece .. " crafted by " .. set.skill)
			ok(def.requires and next(def.requires) ~= nil, piece .. " has a requirement")
		end
		local weapon = Data.Items[set.weapon.id]
		eq(P.weaponStyle(weapon), set.style, set.weapon.id .. " style")
		eq(Data.Gear.category(weapon), set.style, set.weapon.id .. " reforge category")
		ok(Data.Recipes[set.weapon.id].costs.SovereignCrest == 1, set.weapon.id .. " needs a Sovereign Crest")
		ok(Data.Recipes[dataSet.pieces[2]].costs.SovereignCrest == 1, set.id .. " chestpiece needs a Sovereign Crest")
	end
	ok(setStyles.melee and setStyles.ranged and setStyles.magic, "one set per combat style")
	local blade = Data.Items.SovereignGreatblade.stats
	for stat, v in pairs(cel) do ok((blade[stat] or 0) > v, "Sovereign Greatblade " .. stat .. " above Celestial") end
	ok(Data.Items.EclipseLongbow.ranged.power > Data.Items.AetherheartLongbow.ranged.power, "Eclipse Longbow above Aetherheart")
	ok(Data.Items.RiftcrownStaff.magic.power > Data.Items.AetherheartStaff.magic.power, "Riftcrown Staff above Aetherheart")
	eq(#Data.Items.RiftcrownStaff.magic.elements, 4, "Riftcrown Staff supplies all four elements")
	-- Full sets through Progression.computeStats: the set bonus lands.
	for _, set in ipairs(E.Sets) do
		local p = {xp = {Combat = Data.XP_TABLE[80], Ranged = Data.XP_TABLE[80], Magic = Data.XP_TABLE[80]}, items = {}, equipment = {}, collection = {}}
		for _, piece in ipairs(Data.Sets[set.id].pieces) do
			p.items[piece] = 1
			p.equipment[Data.Items[piece].slot] = piece
		end
		local s = P.computeStats(p, 0)
		eq(s.activeSet, set.id, set.id .. " active set")
		for stat, v in pairs(set.bonus) do ok((s[stat] or 0) >= v, set.id .. " bonus " .. stat .. " applied") end
	end
	-- Reforge / stars / masterwork on endgame gear.
	local g = {reforges = {SovereignGreatblade = "Honed"}, stars = {SovereignGreatblade = 5}, books = {SovereignGreatblade = {masterwork = true}}}
	eq(Data.Gear.effectiveRarity(g, "SovereignGreatblade"), "Mythic", "masterwork lifts Legendary to Mythic")
	local up = Data.Gear.upgradeStats(g, "SovereignGreatblade")
	ok((up.damage or 0) > 0 and (up.critChance or 0) > 0, "stars and reforge add stats to endgame weapons")
	-- Uniques: pet, accessories, weapons.
	ok(Data.PetById.Shardling and Data.Items.ShardlingPet.kind == "pet", "Shardling pet")
	ok(Data.Items.SovereignSignet.kind == "accessory" and Data.Items.NyxwingCharm.kind == "accessory", "boss accessories")
	ok(Data.Recipes.SovereignSignet == nil and Data.Recipes.NyxwingCharm == nil, "boss accessories are drop-only")
	ok(Data.Items.Crownbreaker.stats.damage > blade.damage, "Crownbreaker tops the crafted blade")
	eq(P.weaponStyle(Data.Items.Duskpiercer), "ranged", "Duskpiercer is a bow")
	-- World bosses.
	eq(#E.BossOrder, 2, "two world bosses")
	local summons = {}
	for _, id in ipairs(E.BossOrder) do
		local def = WB[id]
		summons[def.summon] = true
		ok(def.worldBoss and def.id == id and def.region == "ShatteredCrown", id .. " flags")
		eq(Data.Monsters[id], def, id .. " resolves through Data.Monsters")
		eq(rawget(Data.Monsters, id), nil, id .. " is not a marker monster")
		ok(table.find(region.monsters, id) ~= nil, id .. " in the region bestiary list")
		ok(def.hp >= 1000000 and def.level > 110, id .. " is huge")
		ok(def.enrage < def.duration and def.enrage > 60, id .. " enrage before departure")
		ok(def.weakness ~= nil and def.attackStyle ~= nil, id .. " triangle")
		ok(Combat.blueprint(def.body, def.color, "world").scale > 3, id .. " towers (world scale)")
		local plan = Combat.blueprint(def.body, def.color, "world")
		ok(#plan.parts + 1 <= 25, id .. " body within 25 parts")
		local names = {}
		for _, part in ipairs(plan.parts) do ok(not names[part.name], id .. " unique part " .. part.name); names[part.name] = true end
		eq(def.phases[1].at, 1, id .. " phase 1 at full health")
		for i = 2, #def.phases do ok(def.phases[i].at < def.phases[i - 1].at, id .. " phase " .. i .. " deeper") end
		local kinds = {}
		for _, phase in ipairs(def.phases) do
			ok(#phase.attacks >= 2 and phase.interval > 0, id .. " " .. phase.name .. " rotation")
			for _, a in ipairs(phase.attacks) do ok(def.attacks[a] ~= nil, id .. " " .. phase.name .. " attack " .. a) end
		end
		for attackId, a in pairs(def.attacks) do
			kinds[a.kind] = true
			if a.kind == "adds" then
				ok(Data.Monsters[a.monster] and rawget(Data.Monsters, a.monster) and a.count >= 1, id .. " add wave " .. attackId)
			else
				ok(a.radius > 0 and a.windup >= 1.5 and a.mult > 0, id .. " telegraph " .. attackId .. " readable")
			end
		end
		ok(kinds.disc and kinds.ring and kinds.safe and kinds.adds, id .. " uses every telegraph kind")
		local rare = 0
		for _, d in ipairs(def.loot) do
			ok(Data.Items[d.item] ~= nil, id .. " loot " .. d.item)
			if d.chance < 0.05 then rare += 1 end
		end
		ok(rare >= 3, id .. " has rare uniques for Magic Find")
	end
	ok(summons.altar and summons.schedule, "one altar boss, one scheduled boss")
	-- Quests and diary.
	for i, id in ipairs(E.QuestLine) do
		local q = Data.QuestById[id]
		ok(q ~= nil and q.region == "ShatteredCrown" and q.line == "main", id .. " in the main line")
		ok(q.rewards.points and q.rewards.points > 0, id .. " pays Quest Points")
		local prev = if i == 1 then "CrownOfTempest" else E.QuestLine[i - 1]
		local chained = false
		for _, r in ipairs(q.requires) do if r.kind == "quest" and r.quest == prev then chained = true end end
		ok(chained, id .. " follows " .. prev)
		for _, o in ipairs(q.objectives) do
			ok(Data.describeCheck(o) ~= "Unknown task" and not Data.describeCheck(o):find("nil", 1, true), id .. " objective text " .. Data.describeCheck(o))
		end
	end
	local diary = Data.DiaryByRegion.ShatteredCrown
	ok(diary ~= nil, "Shattered Crown diary")
	for _, tier in ipairs(Data.DiaryTiers) do
		local n = #diary.tiers[tier].tasks
		ok(n >= 3 and n <= 5, "diary " .. tier .. " 3-5 tasks")
		ok(next(diary.tiers[tier].perk) ~= nil, "diary " .. tier .. " perk")
		for _, o in ipairs(diary.tiers[tier].tasks) do ok(Data.describeCheck(o) ~= "Unknown task", "diary task " .. Data.describeCheck(o)) end
	end
	-- Bestiary: world bosses count for milestones (Data.Monsters lookup).
	local stats = P.computeStats({xp = {}, items = {}, equipment = {}, bestiary = {Aurelith = 10, RiftmawStalker = 10}}, 0)
	eq(stats.bestiaryTiers, 2, "world boss kills count toward bestiary milestones")
end
print("PASS: " .. (checks - dataChecks) .. " endgame data assertions.")

------------------------------------------------------------------------------
-- 2. Pure rules: phases, rotation, telegraph geometry, tiers, eligibility
------------------------------------------------------------------------------
local ruleChecks = checks
do
	local def = WB.Aurelith
	eq(E.phaseFor(def, 1), 1, "full health phase 1")
	eq(E.phaseFor(def, 0.67), 1, "67% still phase 1")
	eq(E.phaseFor(def, 0.66), 2, "66% phase 2")
	eq(E.phaseFor(def, 0.34), 2, "34% phase 2")
	eq(E.phaseFor(def, 0.33), 3, "33% phase 3")
	eq(E.phaseFor(def, 0), 3, "0% phase 3")
	eq(E.attackAt(def, 1, 1), "slam", "rotation step 1")
	eq(E.attackAt(def, 1, 2), "nova", "rotation step 2")
	eq(E.attackAt(def, 1, 3), "slam", "rotation wraps")
	eq(E.attackAt(def, 3, 1), "eclipse", "phase 3 opens with the eclipse")
	eq(E.attackAt(def, 3, 0), "eclipse", "step clamps to 1")
	near(E.attackInterval(def, 1, false), 7, "phase 1 interval")
	near(E.attackInterval(def, 1, true), 7 * E.ENRAGE_TEMPO, "enraged interval")
	near(E.attackInterval(def, 9, false), 7, "unknown phase falls back")
	local c = Vector3.new(0, 0, 0)
	ok(E.struck({kind = "disc", radius = 9}, c, Vector3.new(8.9, 50, 0)), "inside a disc (height ignored)")
	ok(not E.struck({kind = "disc", radius = 9}, c, Vector3.new(9.1, 0, 0)), "outside a disc dodges")
	ok(E.struck({kind = "ring", radius = 18}, c, Vector3.new(0, 0, 17)), "inside the nova")
	ok(not E.struck({kind = "ring", radius = 18}, c, Vector3.new(0, 0, 19)), "outside the nova dodges")
	ok(E.struck({kind = "safe", radius = 14}, c, Vector3.new(15, 0, 0)), "outside the eclipse shelter is struck")
	ok(not E.struck({kind = "safe", radius = 14}, c, Vector3.new(13, 0, 0)), "inside the shelter is safe")
	ok(not E.struck({kind = "adds"}, c, c), "adds never strike")
	-- Contribution tiers.
	eq(E.contributionTier(0.5).id, "Champion", "50% Champion")
	eq(E.contributionTier(0.25).id, "Champion", "25% Champion")
	eq(E.contributionTier(0.2499).id, "Vanguard", "just under 25% Vanguard")
	eq(E.contributionTier(0.1).id, "Vanguard", "10% Vanguard")
	eq(E.contributionTier(0.05).id, "Valiant", "5% Valiant")
	eq(E.contributionTier(0.01).id, "Participant", "1% Participant")
	eq(E.contributionTier(0.0099), nil, "under 1% no tier")
	eq(E.contributionTier(0 / 0), nil, "NaN no tier")
	eq(E.contributionTier("x"), nil, "garbage no tier")
	for i = 2, #E.ContributionTiers do
		local a, b = E.ContributionTiers[i - 1], E.ContributionTiers[i]
		ok(a.minShare > b.minShare and a.weight > b.weight and a.coins > b.coins and a.essence > b.essence, a.id .. " outranks " .. b.id)
	end
	-- Loot weight: tier + rank + summoner (capped).
	near(E.lootWeight("Champion", 1, 0), 3.5, "champion rank 1")
	near(E.lootWeight("Champion", 4, 0), 3, "rank 4 has no bonus")
	near(E.lootWeight("Participant", 2, 1), 1.55, "participant rank 2 with one sigil")
	near(E.lootWeight("Participant", 9, 2), 1.5, "two sigils")
	near(E.lootWeight("Participant", 9, 9), 1 + E.SUMMONER_CAP, "summoner bonus capped")
	eq(E.lootWeight("Nope", 1, 0), 0, "unknown tier weight 0")
	-- Eligibility (anti-leech).
	local base = {share = 0.05, alive = true, distance = 10, ironman = false, lastHit = 100, now = 120}
	local function with(changes)
		local c2 = table.clone(base)
		for k, v in pairs(changes) do c2[k] = v end
		return c2
	end
	ok(E.eligible(def, base), "active contributor eligible")
	local okShare, whyShare = E.eligible(def, with({share = 0.009}))
	ok(not okShare and whyShare == "share", "under 1% refused")
	local okDead, whyDead = E.eligible(def, with({alive = false}))
	ok(not okDead and whyDead == "dead", "dead refused")
	local okRange, whyRange = E.eligible(def, with({distance = def.creditRange + 1}))
	ok(not okRange and whyRange == "range", "out of range refused")
	local okNil, whyNil = E.eligible(def, with({distance = false}))
	ok(not okNil and whyNil == "range", "unknown position refused")
	ok(E.eligible(def, with({distance = def.creditRange})), "range edge accepted")
	local okIdle, whyIdle = E.eligible(def, with({lastHit = 120 - E.ACTIVE_WINDOW - 1}))
	ok(not okIdle and whyIdle == "idle", "idle leech refused")
	ok(E.eligible(def, with({lastHit = 120 - E.ACTIVE_WINDOW})), "hit exactly a window ago accepted")
	local okIron, whyIron = E.eligible(def, with({ironman = true, share = 0.29}))
	ok(not okIron and whyIron == "ironman", "Ironman under 30% refused")
	ok(E.eligible(def, with({ironman = true, share = 0.3})), "Ironman at 30% accepted")
	ok(not E.eligible(def, nil), "missing record refused")
	-- Ranking: damage desc, ties by earliest last hit.
	local ranked = E.rank({{player = "a", damage = 10, lastHit = 5}, {player = "b", damage = 30, lastHit = 9}, {player = "c", damage = 10, lastHit = 2}}, 100)
	eq(ranked[1].player, "b", "top damage first")
	eq(ranked[2].player, "c", "tie: earlier last hit first")
	eq(ranked[3].rank, 3, "ranks assigned")
	near(ranked[1].share, 0.3, "share of max health")
	-- Altar rules.
	ok(E.canPlaceSigil("Aurelith", 0, 0, false), "empty altar accepts")
	local f1, r1 = E.canPlaceSigil("Aurelith", 4, 0, false)
	ok(not f1 and r1 == "full", "full altar refuses")
	local f2, r2 = E.canPlaceSigil("Aurelith", 1, E.ALTAR_PER_PLAYER, false)
	ok(not f2 and r2 == "mine", "per-player cap")
	local f3, r3 = E.canPlaceSigil("Aurelith", 0, 0, true)
	ok(not f3 and r3 == "active", "awake boss refuses")
	local f4, r4 = E.canPlaceSigil("Nyxwyrm", 0, 0, false)
	ok(not f4 and r4 == "boss", "scheduled boss has no altar")
	ok(not E.canPlaceSigil("Nope", 0, 0, false), "unknown boss")
end
print("PASS: " .. (checks - ruleChecks) .. " endgame rule assertions.")

------------------------------------------------------------------------------
-- 3. Loot weighting with deterministic rolls (Progression.rollDrops)
------------------------------------------------------------------------------
local lootChecks = checks
do
	eq(E.bossRewards("Nope", "Champion", 1, 0), nil, "unknown boss no rewards")
	eq(E.bossRewards("Aurelith", "Nope", 1, 0), nil, "unknown tier no rewards")
	local low = E.bossRewards("Aurelith", "Participant", 10, 0)
	local high = E.bossRewards("Aurelith", "Champion", 1, 2)
	eq(low.coins, E.TierById.Participant.coins, "participant coins")
	eq(high.coins, E.TierById.Champion.coins, "champion coins")
	eq(low.items.SovereignEssence, E.TierById.Participant.essence, "participant essence")
	eq(high.items.SovereignEssence, E.TierById.Champion.essence, "champion essence")
	near(high.weight, 3 + 0.5 + 0.5, "champion rank 1 summoner weight")
	local function row(plan, item) for _, d in ipairs(plan.drops) do if d.item == item then return d end end end
	for _, d in ipairs(WB.Aurelith.loot) do
		local a, b = row(low, d.item), row(high, d.item)
		ok(a and b, d.item .. " in both plans")
		if d.chance >= 1 then
			eq(a.chance, 1, d.item .. " guaranteed")
			ok(b.min > a.min and b.max > a.max, d.item .. " amounts scale with weight")
		else
			near(a.chance, d.chance, d.item .. " participant keeps the base chance")
			near(b.chance, math.min(1, d.chance * 4), d.item .. " champion chance x weight")
			ok(b.chance <= 1, d.item .. " capped at 1")
		end
	end
	-- Rolls: a queue of values.
	local function roller(values, default)
		local q = table.clone(values)
		return function() if #q > 0 then return table.remove(q, 1) end return default end
	end
	-- Crest base 6%: participant misses at 0.07, champion (x4 = 24%) hits.
	local crestRoll = 0.07
	local function rollFor(plan, item, value)
		local rolls = {}
		for _, d in ipairs(plan.drops) do
			if d.item == item then table.insert(rolls, value); table.insert(rolls, 0)
			else table.insert(rolls, 0.999); if d.chance >= 1 then table.insert(rolls, 0) end end
		end
		return P.rollDrops(plan.drops, 0, roller(rolls, 0.999), 0)
	end
	eq(rollFor(low, "SovereignCrest", crestRoll).SovereignCrest, nil, "participant misses the crest at 0.07")
	eq(rollFor(high, "SovereignCrest", crestRoll).SovereignCrest, 1, "champion hits the crest at 0.07")
	-- Magic Find applies to sub-5% rows after weighting: signet 1% -> 1.5% at 50 MF.
	local signetPlan = {drops = {{item = "SovereignSignet", chance = 0.01, min = 1, max = 1}}}
	eq(P.rollDrops(signetPlan.drops, 0, roller({0.012, 0}, 0.999), 0).SovereignSignet, nil, "1% signet misses 0.012 without Magic Find")
	eq(P.rollDrops(signetPlan.drops, 50, roller({0.012, 0}, 0.999), 0).SovereignSignet, 1, "50 Magic Find catches 0.012")
	-- Pet Luck also lifts the pet row.
	local petRow = row(low, "ShardlingPet")
	eq(P.rollDrops({petRow}, 0, roller({0.005, 0}, 0.999), 0).ShardlingPet, nil, "pet misses at 0.005")
	eq(P.rollDrops({petRow}, 0, roller({0.005, 0}, 0.999), 50).ShardlingPet, 1, "Pet Luck catches 0.005")
	-- Guaranteed rows always land; amounts follow the roll.
	local always = P.rollDrops(low.drops, 0, roller({}, 0.999), 0)
	ok((always.CrownShard or 0) >= row(low, "CrownShard").min, "guaranteed shards land at a high roll")
	eq(always.Crownbreaker, nil, "no unique at a high roll")
	local everything = P.rollDrops(high.drops, 0, roller({}, 0), 0)
	for _, d in ipairs(WB.Aurelith.loot) do ok((everything[d.item] or 0) >= 1, d.item .. " drops at roll 0") end
	-- Expected value strictly rises with tier (deterministic sweep of 200 rolls).
	local function expected(plan)
		local total = 0
		for i = 1, 200 do
			local v = (i - 0.5) / 200
			for _, d in ipairs(plan.drops) do if v < d.chance then total += (d.min + d.max) / 2 end end
		end
		return total
	end
	local last = math.huge
	for _, t in ipairs(E.ContributionTiers) do
		local value = expected(E.bossRewards("Nyxwyrm", t.id, 5, 0))
		ok(value < last, t.id .. " expected loot below the tier above")
		last = value
	end
end
print("PASS: " .. (checks - lootChecks) .. " endgame loot assertions.")

------------------------------------------------------------------------------
-- 4. Schedule (Skyward Calendar)
------------------------------------------------------------------------------
local scheduleChecks = checks
do
	local cal = Data.Calendar
	local S = E.SCHEDULE
	local day0 = cal.epoch + 50 * cal.dayLength
	local w = E.scheduleAt(day0 + 10)
	eq(w.starts, day0 + S.offset, "window starts offset seconds after dawn")
	eq(w.boss, "Nyxwyrm", "scheduled boss")
	ok(not w.open, "closed before the window")
	eq(w.warnAt, w.starts - S.warning, "warning lead")
	eq(w.key, "Nyxwyrm:" .. w.starts, "window key")
	local inside = E.scheduleAt(day0 + S.offset + 5)
	ok(inside.open and inside.key == w.key, "open inside the window")
	local edge = E.scheduleAt(day0 + S.offset + S.window - 1)
	ok(edge.open, "open until the window ends")
	local after = E.scheduleAt(day0 + S.offset + S.window)
	ok(not after.open and after.starts == day0 + cal.dayLength + S.offset, "after the window: the next isle day")
	ok(S.offset + S.window <= cal.dayLength, "the window fits inside an isle day")
	-- Every isle day has exactly one window: walk 3 days in 60 s steps.
	local keys, spawns = {}, 0
	local w2 = Combat.createLogic({Data = Data, Progression = P, now = function() return 0 end, rng = function() return 0.5 end,
		players = function() return {} end, alive = function() return false end, position = function() return nil end,
		heal = function() end, bridge = function() return nil end})
	local warns = 0
	for t = day0, day0 + 3 * cal.dayLength, 60 do
		local wnd = E.scheduleAt(t)
		keys[wnd.key] = true
		for _, ev in ipairs(w2.wbScheduleTick(t)) do
			if ev.kind == "spawn" then spawns += 1 elseif ev.kind == "warn" then warns += 1 end
		end
	end
	eq(spawns, 3, "one scheduled spawn per isle day")
	eq(warns, 3, "one warning per isle day")
	local count = 0
	for _ in pairs(keys) do count += 1 end
	ok(count >= 3 and count <= 4, "window keys are per day")
	-- A spawn the runtime could not build retries within the same window.
	local w3 = Combat.createLogic({Data = Data, Progression = P, now = function() return 0 end, rng = function() return 0.5 end,
		players = function() return {} end, alive = function() return false end, position = function() return nil end,
		heal = function() end, bridge = function() return nil end})
	local t0 = day0 + S.offset + 1
	local first = w3.wbScheduleTick(t0)
	eq(#first, 1, "spawn event once open")
	eq(#w3.wbScheduleTick(t0 + 1), 0, "same window does not repeat")
	w3.wbScheduleRetry(first[1].key)
	eq(#w3.wbScheduleTick(t0 + 2), 1, "retry re-offers the window")
end
print("PASS: " .. (checks - scheduleChecks) .. " endgame schedule assertions.")

------------------------------------------------------------------------------
-- 5. Combat logic: a world boss fight under doubles
------------------------------------------------------------------------------
local fightChecks = checks
local function world()
	local w = {clock = 1000, rolls = {}, calls = {}, positions = {}, alive = {}, stats = {}, list = {}, loot = {}, replies = {worldBoss = {ok = true, drops = {CrownShard = 9}, coins = 8000}}}
	function w.rng() if #w.rolls > 0 then return table.remove(w.rolls, 1) end return 0.5 end
	function w.player(name, pos, opts)
		opts = opts or {}
		local p = {Name = name, UserId = #w.list + 1}
		w.positions[p] = pos
		w.alive[p] = true
		w.stats[p] = {stats = opts.stats or {damage = 100000, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0}, combatLevel = 90, ironman = opts.ironman == true}
		table.insert(w.list, p)
		return p
	end
	function w.count(op, player)
		local n = 0
		for _, c in ipairs(w.calls) do if c.op == op and (player == nil or c.player == player) then n += 1 end end
		return n
	end
	function w.payloads(op)
		local out = {}
		for _, c in ipairs(w.calls) do if c.op == op then table.insert(out, c) end end
		return out
	end
	w.logic = Combat.createLogic({
		Data = Data, Progression = P,
		now = function() return w.clock end, time = function() return 0 end, rng = w.rng,
		players = function() return w.list end,
		alive = function(p) return w.alive[p] == true end,
		position = function(p) return w.positions[p] end,
		heal = function() end,
		bridge = function(op, player, payload, done)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			if done then done(w.replies[op]) end
			return nil
		end,
		wbLoot = function(player, r, entry, reply) table.insert(w.loot, {player = player, entry = entry, reply = reply}) end,
		lineOfSight = function() return true end,
	})
	return w
end
local ARENA = Vector3.new(0, 0, 0)
local function spawnBoss(w, id, summoners)
	local spec = w.logic.wbSpec(id)
	return w.logic.wbRegister(spec, {Name = id}, ARENA, {radius = 6, summoners = summoners})
end
local function hit(w, player, r, amount)
	-- Direct damage accrual (as an attack would, after mitigation).
	return w.logic.landHit(player, r, amount, "melee")
end
do
	local w = world()
	local L = w.logic
	eq(L.wbSpec("Nope"), nil, "unknown boss spec")
	eq(L.wbSpec("RiftmawStalker"), nil, "regular monsters are not world bosses")
	local r = spawnBoss(w, "Aurelith")
	ok(r and r.worldBoss and r.hp == WB.Aurelith.hp, "boss registered at full health")
	eq(L.wbActive("Aurelith"), r, "active lookup")
	eq(spawnBoss(w, "Aurelith"), nil, "one live boss per id")
	eq(#L.wbList(), 1, "boss list")
	eq(L.resolve(r.model), r, "boss model resolves for attacks")
	-- Marker monsters refuse world boss ids.
	local bad, reason = L.addMarker("k", "Aurelith", 1, ARENA)
	ok(bad == nil and reason == "unknown monster", "a spawn marker cannot name a world boss")
	-- Anyone may fight it (no owner check), snare immune.
	local a = w.player("A", Vector3.new(10, 0, 0))
	local b = w.player("B", Vector3.new(-10, 0, 0))
	ok(L.validateTarget(a, r.model, 14), "player A may strike")
	ok(L.validateTarget(b, r.model, 14), "player B may strike")
	-- Think: targets the nearest player inside the arena; leashes to the arena.
	w.positions[a] = Vector3.new(3, 0, 0)
	local act = L.think(r)
	ok(act.kind == "strike" or act.kind == "hold", "boss engages a player in reach")
	eq(r.target, a, "nearest arena player targeted")
	w.positions[a] = Vector3.new(WB.Aurelith.arenaRange + 5, 0, 0)
	w.positions[b] = Vector3.new(0, 0, WB.Aurelith.leash + 20)
	act = L.think(r)
	eq(act.kind, "chase", "boss chases inside the arena")
	ok((act.goal - ARENA).Magnitude <= WB.Aurelith.leash + 1e-6, "chase stops at the leash")
	w.positions[b] = Vector3.new(0, 0, WB.Aurelith.arenaRange + 5)
	r.position = Vector3.new(20, 0, 0)
	act = L.think(r)
	eq(act.kind, "leash", "nobody in the arena: walks home")
	r.position = ARENA
	eq(L.think(r).kind, "idle", "home and idle")
	-- Telegraph rotation: phase 1 slam (disc on a participant), then nova.
	w.calls = {} -- melee strikes from the think checks above
	w.positions[a], w.positions[b] = Vector3.new(5, 0, 0), Vector3.new(-12, 0, 0)
	w.clock = r.nextTelegraph
	w.rolls = {0}
	local events = L.wbTick()
	local tele
	for _, e in ipairs(events) do if e.kind == "telegraph" then tele = e.telegraph end end
	ok(tele and tele.kind == "disc" and tele.id == "slam", "first attack is a telegraphed slam")
	eq(tele.victim, a, "disc lands on a rolled participant")
	ok((tele.center - Vector3.new(5, 0, 0)).Magnitude < 1e-6, "disc centred under the victim")
	near(tele.resolveAt - w.clock, WB.Aurelith.attacks.slam.windup, "windup before the strike")
	eq(w.count("damage"), 0, "warning deals no damage yet")
	-- A dodges out of the disc; B stays clear: nobody is struck.
	w.positions[a] = Vector3.new(5 + WB.Aurelith.attacks.slam.radius + 1, 0, 0)
	w.clock = tele.resolveAt
	local strike
	for _, e in ipairs(L.wbTick()) do if e.kind == "strike" then strike = e end end
	ok(strike ~= nil and #strike.hits == 0, "dodged disc hits nobody")
	-- Next: nova (ring around the boss). A stands inside, B outside.
	w.clock = r.nextTelegraph
	w.positions[a], w.positions[b] = Vector3.new(6, 0, 0), Vector3.new(30, 0, 0)
	for _, e in ipairs(L.wbTick()) do if e.kind == "telegraph" then tele = e.telegraph end end
	eq(tele.id, "nova", "second attack is the nova")
	w.clock = tele.resolveAt
	for _, e in ipairs(L.wbTick()) do if e.kind == "strike" then strike = e end end
	eq(#strike.hits, 1, "nova strikes only the player inside")
	eq(strike.hits[1].player, a, "the close player is struck")
	eq(strike.hits[1].amount, math.floor(WB.Aurelith.damage * WB.Aurelith.attacks.nova.mult), "nova damage = boss damage x mult")
	eq(w.count("damage", a), 1, "bridge damage for the struck player")
	eq(w.count("damage", b), 0, "no damage for the dodger")
	-- Phase 2 at 66%: the rotation restarts, the next attack comes soon.
	hit(w, a, r, math.floor(r.maxHp * 0.35))
	events = L.wbTick()
	local phased = false
	for _, e in ipairs(events) do if e.kind == "phase" then phased = e.phase == 2 end end
	ok(phased and r.phase == 2 and r.step == 0, "phase 2 at 65% health")
	ok(r.nextTelegraph <= w.clock + 1.5, "phase change brings the next attack forward")
	eq(#L.wbTick(), 0, "phase announced once")
	-- Phase 2 rotation: slam, adds, nova. Adds ward the boss.
	w.clock = r.nextTelegraph
	L.wbTick()
	w.clock = r.nextTelegraph
	local wave
	for _, e in ipairs(L.wbTick()) do if e.kind == "adds" then wave = e end end
	ok(wave and wave.monster == "RiftmawStalker" and wave.count == 3, "phase 2 calls a Riftmaw pack")
	local adds = {}
	for i = 1, wave.count do
		local add = L.wbRegisterAdd(r, wave.monster, {Name = "add" .. i}, Vector3.new(14, 0, i), {radius = 2})
		ok(add and add.add and add.parent == r, "add " .. i .. " bound to the boss")
		table.insert(adds, add)
	end
	eq(L.wbRegisterAdd(r, "Aurelith", {}, ARENA), nil, "a world boss is never an add")
	ok(L.wbWarded(r), "living adds ward the boss")
	local wardedHit = L.mitigate(r, 100000, "melee")
	local plainR = {defense = r.defense, weakness = r.weakness, defenceStyle = r.defenceStyle}
	local plainHit = L.mitigate(plainR, 100000, "melee")
	eq(wardedHit, math.floor(plainHit * E.WARD), "ward halves damage")
	eq(L.liveCount(), 0, "adds never count as marker monsters")
	-- A wave never stacks on a living one.
	r.step = 1
	w.clock = r.nextTelegraph
	local stacked = false
	for _, e in ipairs(L.wbTick()) do if e.kind == "adds" then stacked = true end end
	ok(not stacked, "no second wave while adds live")
	-- Killing adds credits the killer like normal monsters and lifts the ward.
	for _, add in ipairs(adds) do
		hit(w, a, add, add.hp)
		L.kill(add)
	end
	eq(w.count("kill", a), 3, "add kills pay through kill")
	ok(not L.wbWarded(r), "ward lifts with the last add")
	-- Enrage.
	w.clock = r.enrageAt
	local enraged = false
	for _, e in ipairs(L.wbTick()) do if e.kind == "enrage" then enraged = true end end
	ok(enraged and r.enraged and r.damage == WB.Aurelith.damage * E.ENRAGE_DAMAGE, "enrage doubles damage")
	near(E.attackInterval(WB.Aurelith, r.phase, r.enraged), WB.Aurelith.phases[2].interval * E.ENRAGE_TEMPO, "enrage quickens the rotation")
	-- Phase 3: eclipse (safe zone). A inside the shelter, B outside.
	hit(w, b, r, r.hp - math.floor(r.maxHp * 0.3))
	L.wbTick()
	eq(r.phase, 3, "phase 3 at 30% health")
	w.clock = r.nextTelegraph
	for _, e in ipairs(L.wbTick()) do if e.kind == "telegraph" then tele = e.telegraph end end
	eq(tele.kind, "safe", "phase 3 opens with the eclipse")
	w.positions[a], w.positions[b] = Vector3.new(4, 0, 0), Vector3.new(25, 0, 0)
	local before = w.count("damage", b)
	w.clock = tele.resolveAt
	for _, e in ipairs(L.wbTick()) do if e.kind == "strike" then strike = e end end
	eq(#strike.hits, 1, "eclipse strikes outside the shelter")
	eq(strike.hits[1].player, b, "the far player is struck")
	eq(w.count("damage", b), before + 1, "far player damaged")
	eq(strike.hits[1].amount, math.floor(WB.Aurelith.damage * E.ENRAGE_DAMAGE * WB.Aurelith.attacks.eclipse.mult), "enraged eclipse damage")
	-- HUD payload.
	local hud = L.wbHud(r, a, function(p) return p.Name end)
	eq(hud.phase, 3, "hud phase")
	eq(hud.phases, 3, "hud phase count")
	eq(hud.phaseName, "Shattered", "hud phase name")
	ok(hud.enraged and hud.enrageIn == 0, "hud enrage")
	eq(#hud.top, 2, "hud lists both fighters")
	eq(hud.top[1].name, "A", "A leads the board")
	ok(hud.you and hud.you.rank == 1 and hud.you.tier == "Champion", "your rank and tier")
	local hudB = L.wbHud(r, b, function(p) return p.Name end)
	eq(hudB.you.rank, 2, "B ranked second")
	ok(hudB.top[2].you and not hudB.top[1].you, "board marks the viewer")
	local stranger = w.player("C", Vector3.new(5, 0, 5))
	eq(L.wbHud(r, stranger).you, nil, "non-contributors have no rank")
	eq(L.wbHud(r, stranger).fighters, 2, "fighter count")
end
print("PASS: " .. (checks - fightChecks) .. " world boss fight assertions.")

------------------------------------------------------------------------------
-- 6. Kill credit: contribution ranking, anti-leech, loot reports, XP
------------------------------------------------------------------------------
local creditChecks = checks
do
	local w = world()
	local L = w.logic
	local def = WB.Nyxwyrm
	local r = spawnBoss(w, "Nyxwyrm", {})
	local players = {}
	local function fighter(name, pos, share, opts)
		local p = w.player(name, pos, opts)
		if share > 0 then hit(w, p, r, math.floor(def.hp * share)) end
		players[name] = p
		return p
	end
	local champ = fighter("Champ", Vector3.new(10, 0, 0), 0.4)
	local van = fighter("Van", Vector3.new(-10, 0, 0), 0.15)
	local val = fighter("Val", Vector3.new(0, 0, 10), 0.05)
	local part = fighter("Part", Vector3.new(0, 0, -10), 0.015)
	local leech = fighter("Leech", Vector3.new(5, 0, 5), 0.005)
	local dead = fighter("Dead", Vector3.new(6, 0, 6), 0.1)
	local far = fighter("Far", Vector3.new(def.creditRange + 20, 0, 0), 0.1)
	local idle = fighter("Idle", Vector3.new(8, 0, 0), 0.05)
	local iron = fighter("Iron", Vector3.new(9, 0, 0), 0.06, {ironman = true})
	w.stats[iron].ironman = true
	L.statsFor(iron)
	-- Idle struck long ago: everyone else refreshes their last hit.
	r.contributors[idle].lastHit = w.clock - E.ACTIVE_WINDOW - 5
	w.alive[dead] = false
	local remaining = r.hp
	w.clock += 1
	hit(w, champ, r, remaining)
	ok(r.hp <= 0, "boss at zero")
	local credited = L.kill(r)
	local set = {}
	for _, p in ipairs(credited) do set[p] = true end
	ok(set[champ] and set[van] and set[val] and set[part], "active contributors credited")
	ok(not set[leech], "under 1% leech not credited")
	ok(not set[dead], "dead contributor not credited")
	ok(not set[far], "out-of-range contributor not credited")
	ok(not set[idle], "idle contributor not credited")
	ok(not set[iron], "Ironman under 30% not credited")
	eq(#credited, 4, "four credited")
	eq(L.wbActive("Nyxwyrm"), nil, "boss removed after the kill")
	-- Results carry reasons for the HUD.
	local reasons = {}
	for _, e in ipairs(r.results) do reasons[e.player] = e end
	eq(reasons[leech].reason, "share", "leech reason")
	eq(reasons[dead].reason, "dead", "dead reason")
	eq(reasons[far].reason, "range", "range reason")
	eq(reasons[idle].reason, "idle", "idle reason")
	eq(reasons[iron].reason, "ironman", "ironman reason")
	eq(reasons[champ].rank, 1, "champion ranked first")
	-- Bridge "worldBoss" payloads: tier by share, rank, fight id, once each.
	local paid = {}
	for _, c in ipairs(w.payloads("worldBoss")) do paid[c.player] = c.payload end
	eq(paid[champ].tier, "Champion", "champion tier")
	eq(paid[van].tier, "Vanguard", "vanguard tier")
	eq(paid[val].tier, "Valiant", "valiant tier")
	eq(paid[part].tier, "Participant", "participant tier")
	eq(paid[champ].rank, 1, "rank sent")
	eq(paid[champ].boss, "Nyxwyrm", "boss id sent")
	eq(paid[champ].fight, r.fight, "fight id sent")
	eq(paid[leech], nil, "no payload for the leech")
	eq(w.count("worldBoss"), 4, "one payload per credited player")
	ok(paid[champ].share > 0.45, "champion share includes the killing blow")
	eq(paid[champ].sigils, 0, "scheduled boss has no summoners")
	eq(#w.loot, 4, "every reply reaches the loot callback")
	-- Damage XP (on-kill accrual) for credited players only, per style.
	local xpTo = {}
	for _, c in ipairs(w.payloads("combatXp")) do xpTo[c.player] = (xpTo[c.player] or 0) + c.payload.damage; eq(c.payload.monster, "Nyxwyrm", "XP names the boss") end
	ok(xpTo[champ] and xpTo[van] and xpTo[part], "credited players earn damage XP")
	eq(xpTo[leech], nil, "leech earns no XP")
	eq(xpTo[far], nil, "out-of-range earns no XP")
	eq(xpTo[idle], nil, "idle earns no XP")
	eq(xpTo[van], math.floor(def.hp * 0.15), "XP accrues the damage actually dealt")
	-- An Ironman carrying 30%+ is credited.
	local w2 = world()
	local r2 = w2.logic.wbRegister(w2.logic.wbSpec("Aurelith"), {}, ARENA, {radius = 6, summoners = {}})
	local solo = w2.player("Solo", Vector3.new(4, 0, 0), {ironman = true})
	w2.logic.statsFor(solo)
	local helper = w2.player("Helper", Vector3.new(-4, 0, 0))
	w2.logic.landHit(helper, r2, math.floor(r2.maxHp * 0.6), "magic")
	w2.logic.landHit(solo, r2, r2.hp, "ranged")
	local c2 = w2.logic.kill(r2)
	eq(#c2, 2, "Ironman at 40% credited alongside the party")
	local styles = {}
	for _, c in ipairs(w2.payloads("combatXp")) do styles[c.payload.style] = true end
	ok(styles.magic and styles.ranged, "XP routed per style")
	-- Departure: timeout and empty arena (no loot, adds removed).
	local w3 = world()
	local L3 = w3.logic
	local r3 = w3.logic.wbRegister(L3.wbSpec("Aurelith"), {}, ARENA, {radius = 6})
	local p3 = w3.player("P", Vector3.new(5, 0, 0))
	L3.landHit(p3, r3, 1000, "melee")
	local add = L3.wbRegisterAdd(r3, "RiftmawStalker", {}, Vector3.new(10, 0, 0))
	w3.clock = r3.expires
	local gone
	for _, e in ipairs(L3.wbTick()) do if e.kind == "depart" then gone = e end end
	ok(gone and gone.reason == "timeout", "boss departs at its duration")
	eq(#gone.adds, 1, "adds leave with it")
	ok(not add.alive and not r3.alive, "records removed")
	eq(w3.count("worldBoss"), 0, "departure pays nothing")
	eq(w3.count("combatXp"), 0, "departure discards accrued XP")
	local r4 = L3.wbRegister(L3.wbSpec("Aurelith"), {}, ARENA, {radius = 6})
	ok(r4 ~= nil, "boss may return after departing")
	w3.positions[p3] = Vector3.new(500, 0, 0)
	w3.clock += L3.WB_EMPTY_DEPART + 1
	for _, e in ipairs(L3.wbTick()) do if e.kind == "depart" then gone = e end end
	eq(gone.reason, "empty", "empty arena departs")
	-- Leaving drops contribution (no credit for someone who left).
	local w5 = world()
	local L5 = w5.logic
	local r5 = L5.wbRegister(L5.wbSpec("Aurelith"), {}, ARENA, {radius = 6})
	local stay = w5.player("Stay", Vector3.new(3, 0, 0))
	local leaver = w5.player("Leaver", Vector3.new(-3, 0, 0))
	L5.landHit(leaver, r5, math.floor(r5.maxHp * 0.5), "melee")
	L5.playerRemoving(leaver)
	table.remove(w5.list, 2)
	L5.landHit(stay, r5, r5.hp, "melee")
	local c5 = L5.kill(r5)
	eq(#c5, 1, "only the player still present is credited")
	eq(c5[1], stay, "the stayer")
end
print("PASS: " .. (checks - creditChecks) .. " kill credit / anti-leech assertions.")

------------------------------------------------------------------------------
-- 7. Sovereign Altar summoning
------------------------------------------------------------------------------
local altarChecks = checks
do
	local w = world()
	local L = w.logic
	local a, b, c = w.player("A", ARENA), w.player("B", ARENA), w.player("C", ARENA)
	local need = WB.Aurelith.sigils
	local okA, why, count = L.placeSigil(a, "Aurelith")
	ok(okA and why == nil and count == 1, "first sigil placed")
	ok(L.placeSigil(a, "Aurelith"), "second sigil for the same player")
	local okA3, whyA3 = L.placeSigil(a, "Aurelith")
	ok(not okA3 and whyA3 == "mine", "per-player cap on the altar")
	eq(L.altarCount("Aurelith"), 2, "altar count")
	eq(L.altarMine("Aurelith", a), 2, "A placed two")
	eq(#L.wbDueSummons(), 0, "not yet full")
	ok(L.placeSigil(b, "Aurelith"), "B places one")
	local okC, whyC, countC, needed = L.placeSigil(c, "Aurelith")
	ok(okC and whyC == "ready" and countC == need and needed == need, "the last sigil readies the boss")
	local okD, whyD = L.placeSigil(c, "Aurelith")
	ok(not okD and whyD == "full", "full altar refuses more")
	local due = L.wbDueSummons()
	eq(#due, 1, "one due summon")
	eq(due[1].summoners[a], 2, "summoners recorded")
	local r = L.wbRegister(L.wbSpec("Aurelith"), {}, ARENA, {radius = 6, summoners = due[1].summoners})
	ok(r ~= nil, "summoned")
	eq(L.altarCount("Aurelith"), 0, "altar resets when the boss wakes")
	eq(#L.wbDueSummons(), 0, "nothing due after the summon")
	local okE, whyE = L.placeSigil(a, "Aurelith")
	ok(not okE and whyE == "active", "no sigils while the Sovereign is awake")
	local okN, whyN = L.placeSigil(a, "Nyxwyrm")
	ok(not okN and whyN == "boss", "Nyxwyrm has no altar")
	local okX, whyX = L.placeSigil(a, "Nope")
	ok(not okX and whyX == "boss", "unknown altar")
	-- Summoner bonus reaches the loot payload.
	L.landHit(a, r, math.floor(r.maxHp * 0.2), "melee")
	L.landHit(b, r, r.hp, "melee")
	L.kill(r)
	local sent = {}
	for _, call in ipairs(w.payloads("worldBoss")) do sent[call.player] = call.payload end
	eq(sent[a].sigils, 2, "A's sigils sent")
	eq(sent[b].sigils, 1, "B's sigil sent")
	near(E.lootWeight(sent[a].tier, sent[a].rank, sent[a].sigils), E.TierById.Vanguard.weight + E.RANK_BONUS[2] + 0.5, "A's weight includes the summoner bonus")
	-- A leaver's placements stay on the altar but lose their bonus.
	local w2 = world()
	local L2 = w2.logic
	local x, y = w2.player("X", ARENA), w2.player("Y", ARENA)
	L2.placeSigil(x, "Aurelith")
	L2.playerRemoving(x)
	eq(L2.altarCount("Aurelith"), 1, "placed sigil stays")
	eq(L2.altarMine("Aurelith", x), 0, "leaver forgotten")
	ok(L2.placeSigil(y, "Aurelith"), "others keep filling")
end
print("PASS: " .. (checks - altarChecks) .. " altar assertions.")

------------------------------------------------------------------------------
-- 8. Static runtime / client hooks
------------------------------------------------------------------------------
local staticChecks = checks
do
	local server = fs.readFile("combat.server.lua")
	local client = fs.readFile("combat.client.lua")
	local adventure = fs.readFile("server.server.lua")
	local worldSource = fs.readFile("world.server.lua")
	ok(server:find('"IsleWorldBoss"', 1, true) ~= nil, "combat publishes IsleWorldBoss")
	ok(adventure:find('FindFirstChild("IsleWorldBoss")', 1, true) ~= nil, "adventure asks IsleWorldBoss before spending a sigil")
	ok(server:find("Anchor_WorldBoss_", 1, true) ~= nil and worldSource:find('"WorldBoss_"', 1, true) == nil and worldSource:find('"WorldBoss_Aurelith"', 1, true) ~= nil, "arena anchors shared by name")
	for _, kind in ipairs({"worldBoss", "telegraph", "bossStrike", "worldBossAnnounce", "worldBossLoot"}) do
		ok(server:find('"' .. kind .. '"', 1, true) ~= nil, "server sends " .. kind)
		ok(client:find('kind == "' .. kind .. '"', 1, true) ~= nil, "client renders " .. kind)
	end
	for _, name in ipairs({"WorldBossBar", "WorldBossBoard", "WorldBossLoot"}) do ok(client:find('"' .. name .. '"', 1, true) ~= nil, "client builds " .. name) end
	ok(adventure:find('op=="worldBoss"', 1, true) ~= nil, "bridge handles worldBoss")
	ok(adventure:find("monster.worldBoss", 1, true) ~= nil, "kill refuses world bosses")
	ok(#luau.compile(server) > 0 and #luau.compile(client) > 0, "scripts compile")
	local _, loops = server:gsub("Heartbeat:Connect", "")
	eq(loops, 1, "world bosses ride the single AI loop")
end
print("PASS: " .. (checks - staticChecks) .. " endgame static assertions.")

print("Endgame QA passed " .. checks .. " checks.")
print("SUITE-END verify-endgame.luau")
