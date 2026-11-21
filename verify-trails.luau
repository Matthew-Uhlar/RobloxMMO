-- Treasure Trails: data, pool coverage, balance, world resolvability, server
-- behaviour and the Satchel › Trails page.
-- Part A checks shared/GameData.lua (Data.Trails) and the server-only step
-- module trails.lua: client-visible data holds no step answers; tiers, items, uniques,
-- reward tables (simulated unique rates, Magic Find), coins/h balance against
-- comparable Thieving income, scroll sources, the step pool (>= 120 steps,
-- every kind, tier gates), trail generation, the sliding puzzle and the
-- profile sanitiser. Part B builds world.server.lua and resolves every step
-- (anchors exist on the right island, dig points on solid ground, NPCs placed)
-- and checks gestures against gesture.server.lua's relay. Part C runs
-- server.server.lua (deterministic clock and rolls, DataStore doubles): scroll
-- drops, one scroll per tier, reading, every step kind, anti-skip, caskets and
-- the clue log, teleports, emotes, banners and persistence. Part D renders
-- Satchel › Trails at three atlas sizes and drives its buttons and puzzle box.
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
-- Shared = what clients receive (replicated AetherData); TR = the server-only
-- step module (trails.lua, ServerStorage.AetherTrails) over the shared rules.
local Shared = Data.Trails
local buildTrails = load("trails.lua")
local TR = buildTrails(Data)
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

------------------------------------------------------------------------------
-- Part A: data, rules and balance.
------------------------------------------------------------------------------
local partA = checks
ok(type(Shared) == "table", "Data.Trails exists")
ok(type(TR) == "table" and getmetatable(TR).__index == Shared, "the server step module reads through to the shared rules")
-- Client-visible data (the replicated AetherData module and its source text)
-- carries no step answers: no pool, anchors, offsets, riddle targets, emote
-- places, puzzle seeds, generation or step text.
do
	for _, key in ipairs({"Steps", "StepById", "Landmarks", "generate", "describe", "sanitize", "pool", "eligible", "requires",
		"skillTarget", "stream", "scramble", "stepSeed", "regionName"}) do
		eq(rawget(Shared, key), nil, "client data has no Data.Trails." .. key)
		ok(rawget(TR, key) ~= nil, "server module has TR." .. key)
	end
	local strings, seen = {}, {}
	local function collect(v)
		if type(v) == "string" then strings[v] = true
		elseif type(v) == "table" and not seen[v] then
			seen[v] = true
			for k, x in pairs(v) do collect(k); collect(x) end
		end
	end
	collect(Shared)
	local blob = {}
	for text in pairs(strings) do table.insert(blob, text) end
	blob = table.concat(blob, "\n")
	-- The replicated Trails section of GameData.lua (anchor names elsewhere are
	-- world data; a step's answer is its anchor/offset/target, here or nowhere).
	local whole = fs.readFile("shared/GameData.lua")
	local from = assert(string.find(whole, "-- Treasure Trails (Treasure Trails team; append-only section).", 1, true))
	local to = assert(string.find(whole, "-- End Treasure Trails section.", 1, true))
	local source = whole:sub(from, to)
	ok(#source > 1000, "Trails section found")
	local secrets = 0
	for _, step in ipairs(TR.Steps) do
		local answers = {step.id, step.text, step.sketch, step.target}
		if step.anchor and step.kind ~= "skill" then table.insert(answers, step.anchor) end
		for _, answer in pairs(answers) do
			if type(answer) == "string" and #answer >= 6 and not (step.kind == "skill" and answer == step.target) then
				secrets += 1
				local inData = strings[answer] == true or string.find(blob, answer, 1, true) ~= nil
				-- Teleport leaves land on public entrance anchors; those are not clue answers.
				local isLanding = false
				for _, tp in ipairs(Shared.Teleports) do if tp.anchor == answer then isLanding = true end end
				ok(not inData or isLanding, step.id .. " answer '" .. answer:sub(1, 24) .. "' is not in client data")
				ok(isLanding or not string.find(source, answer, 1, true), step.id .. " answer '" .. answer:sub(1, 24) .. "' is not in the replicated source")
			end
		end
	end
	ok(secrets >= 300, "every step's answers were checked (" .. secrets .. ")")
	ok(not string.find(source, "npc:", 1, true) and not string.find(source, "dig(", 1, true) and not string.find(source, "riddle(", 1, true), "no riddle targets or step builders in GameData.lua")
	-- Puzzle boards are never derivable on the client: only the moves are shared.
	ok(type(Shared.slide) == "function" and type(Shared.applyMoves) == "function" and Shared.SOLVED == "123456780", "clients keep the sliding rules")
end
eq(#TR.TierOrder, 6, "six tiers")
for i, id in ipairs({"Beginner", "Easy", "Medium", "Hard", "Elite", "Master"}) do eq(TR.TierOrder[i], id, "tier order " .. i) end
local prevMax = 0
for i, id in ipairs(TR.TierOrder) do
	local t = TR.Tiers[id]
	eq(t.index, i, id .. " index")
	eq(TR.tierIndex(id), i, id .. " tierIndex")
	ok(t.steps[1] >= 1 and t.steps[1] <= t.steps[2], id .. " step range")
	ok(t.steps[2] >= prevMax, id .. " step ceiling rises")
	prevMax = t.steps[2]
	for _, key in ipairs({"scroll", "casket"}) do
		local def = Data.Items[t[key]]
		ok(def ~= nil and def.kind == "trail" and def.trailTier == id, id .. " " .. key .. " item")
		ok(not Data.Economy.isCommodity(t[key]) and Data.Economy.auctionCategory(t[key]) == nil, id .. " " .. key .. " never trades (Ironman-safe)")
	end
	ok(#t.color == 6 and t.level >= 1 and t.stepSeconds > 0 and t.scramble >= 10, id .. " pacing data")
	for region in pairs(t.regions) do ok(Data.RegionById[region] ~= nil, id .. " region " .. region .. " exists") end
	if i > 1 then
		for region in pairs(TR.Tiers[TR.TierOrder[i - 1]].regions) do ok(t.regions[region], id .. " keeps " .. region) end
	end
end
eq(TR.Tiers.Beginner.steps[1], 1, "Beginner trails start at one step")
eq(TR.Tiers.Beginner.steps[2], 3, "Beginner trails reach three steps")
eq(TR.Tiers.Master.steps[1], 6, "Master trails start at six steps")
eq(TR.Tiers.Master.steps[2], 9, "Master trails reach nine steps")
eq(TR.tierIndex("Nope"), nil, "unknown tier index")
ok(Data.Items[TR.SPADE] ~= nil and Data.Recipes[TR.SPADE] ~= nil, "spade item and recipe")
eq(Data.Recipes[TR.SPADE].station, "Forge", "spade forged at a Forge")
eq(Data.Recipes[TR.SPADE].level, 1, "spade needs Smithing 1")
for cost in pairs(Data.Recipes[TR.SPADE].costs) do ok(Data.Items[cost] ~= nil, "spade cost " .. cost) end
-- Teleport leaves.
for _, tp in ipairs(TR.Teleports) do
	ok(Data.Items[tp.id] ~= nil and Data.Items[tp.id].category == "teleport", tp.id .. " item")
	ok(Data.RegionById[tp.region] ~= nil, tp.id .. " region")
	eq(TR.TeleportById[tp.id], tp, tp.id .. " indexed")
end
-- Uniques.
local uniqueCount, outfitPieces, banners, emoteScrolls, pets = 0, 0, 0, 0, 0
for _, id in ipairs(TR.TierOrder) do
	ok(#TR.Uniques[id] >= 3, id .. " has 3+ uniques")
	for _, u in ipairs(TR.Uniques[id]) do
		uniqueCount += 1
		local def = Data.Items[u]
		ok(def ~= nil, u .. " defined")
		eq(TR.UniqueTier[u], id, u .. " tier lookup")
		eq(def.trailUnique, id, u .. " marked as a " .. id .. " unique")
		if def.kind == "armor" then outfitPieces += 1; ok(def.slot ~= nil and def.stats ~= nil, u .. " wearable") end
		if def.category == "banner" then banners += 1 end
		if def.category == "emote" then emoteScrolls += 1; ok(TR.Emotes[def.emote] ~= nil, u .. " teaches a real emote") end
		if def.kind == "pet" then pets += 1; ok(Data.PetById[def.pet] ~= nil, u .. " species exists") end
	end
end
ok(uniqueCount >= 30, "30+ uniques (" .. uniqueCount .. ")")
ok(outfitPieces >= 21, "trail outfits across tiers (" .. outfitPieces .. " pieces)")
ok(banners >= 5 and emoteScrolls == 6 and pets == 1, "banners, emote scrolls and the pet")
for _, e in ipairs(TR.EmoteOrder) do ok(TR.Gestures[TR.Emotes[e].gesture] ~= nil, e .. " plays a trail gesture") end
-- The Trailhound pet species is wired like every other species.
do
	local PD = Data.PetDepth
	local hound = Data.PetById.Trailhound
	ok(hound ~= nil and Data.Items.TrailhoundPet.pet == "Trailhound", "Trailhound species and item")
	ok(#PD.Abilities.Trailhound >= 2 and #PD.Abilities.Trailhound <= 3, "Trailhound 2-3 abilities")
	ok(PD.Looks.Trailhound ~= nil and #PD.bodyPlan("Trailhound", "Legendary").parts >= 5, "Trailhound companion body")
	ok(has(hound.ability, PD.Abilities.Trailhound[1].name), "Trailhound summary names its first ability")
	local found = false
	for _, d in ipairs(Data.Monsters.VoidcrownDrake.drops) do if d.item == "TrailhoundPet" then found = d.chance < 0.001 end end
	ok(found, "Trailhound also drops (very rarely) from the Voidcrown Drake")
end

-- Rewards: tables, expected values, simulated rates and Magic Find.
local function streamRng(seed) return TR.stream(seed) end
for _, id in ipairs(TR.TierOrder) do
	local r = TR.Rewards[id]
	ok(r.rolls[1] >= 1 and r.rolls[1] <= r.rolls[2], id .. " rolls range")
	ok(r.totalWeight > 0, id .. " common weight")
	for _, row in ipairs(r.common) do
		if row.coins then ok(row.coins[1] > 0 and row.coins[1] <= row.coins[2], id .. " coin row")
		else ok(Data.Items[row.item] ~= nil and row.min >= 1 and row.min <= row.max, id .. " row " .. tostring(row.item)) end
	end
	eq(#r.rare, #TR.Uniques[id], id .. " every unique has a rare row")
	for _, row in ipairs(r.rare) do
		ok(row.chance > 0 and row.chance < 0.05, id .. " " .. row.item .. " rare (Magic Find applies)")
		eq(TR.UniqueTier[row.item], id, id .. " rare row " .. row.item .. " is that tier's unique")
	end
	ok(TR.expectedCasket(id, 100) > TR.expectedCasket(id, 0), id .. " Magic Find raises casket value")
end
for i = 2, #TR.TierOrder do
	ok(TR.expectedCasket(TR.TierOrder[i]) > TR.expectedCasket(TR.TierOrder[i - 1]), TR.TierOrder[i] .. " caskets are worth more than " .. TR.TierOrder[i - 1])
end
-- Balance: coins/h from trails stay at or below comparable activities. The
-- model takes each tier's FASTEST scroll source (kills, gathering, fishing,
-- thieving or hunter catches) and Elite also carries the Master trails its
-- caskets chain into (parallel tiers).
do
	-- The source paces are never slower than the systems allow.
	local TH, HU = Data.Thieving, Data.Hunter
	local ACTION, GATHER = 0.36 + 0.65, 1 + 0.65
	local derived = {}
	local function put(kind, tier, sec) derived[kind] = derived[kind] or {}; derived[kind][tier] = math.min(derived[kind][tier] or math.huge, sec) end
	for _, t in ipairs(TH.Targets) do put("thieve", TR.tierForLevel(t.level), (TH.ACTION + (1 - TH.MAX_CHANCE) * t.stun) / TH.MAX_CHANCE) end
	for _, c in ipairs(HU.Creatures) do
		local p = HU.catchChance(c, 99, HU.TRAP_LUCK_CAP)
		local perSec
		if c.method == "net" then
			perSec = math.min(3 / (c.respawn + (1 / p - 1) * math.max(HU.NET_MISS_COOLDOWN, ACTION)), p / ACTION)
		else
			local success = 1 - (1 - p) ^ HU.MAX_TICKS
			perSec = HU.MAX_TRAPS * success / (HU.TICK * success / p + 2 * ACTION)
		end
		put("catch", TR.tierForLevel(c.level), 1 / perSec)
	end
	for skill, tiers in pairs(Data.ResourceTiers) do for _, r in ipairs(tiers) do put(if skill == "Fishing" then "fish" else "gather", TR.tierForLevel(r.level), GATHER) end end
	for kind, list in pairs(derived) do
		for tier, sec in pairs(list) do
			local model = TR.SourceSeconds[kind] and TR.SourceSeconds[kind][tier]
			ok(model ~= nil and model <= sec + 1e-9, string.format("%s %s pace model %.2fs is not slower than the system (%.2fs)", kind, tier, model or -1, sec))
		end
	end
	for _, id in ipairs(TR.TierOrder) do
		if id ~= "Master" then
			local fastest, from = TR.scrollSeconds(id)
			ok(from ~= nil and fastest <= TR.Tiers[id].killSeconds / TR.SourceChance.kill[id], id .. " scrolls come from the fastest source (" .. tostring(from) .. ")")
			for kind, list in pairs(TR.SourceChance) do
				if list[id] then ok(TR.SourceSeconds[kind][id] / list[id] >= fastest, id .. " " .. kind .. " is never faster than the modelled fastest source") end
			end
		end
	end
	ok(TR.coinsPerHour("Elite") > 3600 * TR.expectedCasket("Elite") / TR.clueSeconds("Elite"), "Elite income carries its chained Master trails")
end
for _, id in ipairs(TR.TierOrder) do
	local cph, ref = TR.coinsPerHour(id), TR.referenceCoinsPerHour(id)
	ok(ref > 0, id .. " reference income exists")
	ok(cph <= ref, string.format("%s trails earn %.0f coins/h <= %.0f (Thieving at level %d)", id, cph, ref, TR.Tiers[id].level))
	ok(cph <= ref * 0.6, id .. " trails are not a coin farm (<= 60% of thieving)")
	ok(TR.coinsPerHour(id, 300) <= ref, id .. " stays below the reference even at 300 Magic Find")
	local bot = TR.coinsPerHour(id, 0, true)
	ok(bot <= ref, string.format("%s: a perfect bot (fastest source, every step at the %ds floor) earns %.0f <= %.0f", id, TR.MIN_STEP_SECONDS[id], bot, ref))
	ok(TR.clueSeconds(id) > 0, id .. " pacing positive")
	ok(TR.MIN_STEP_SECONDS[id] >= 8 and TR.MIN_STEP_SECONDS[id] <= 15, id .. " minimum step time 8-15 s")
end
for i = 2, #TR.TierOrder do ok(TR.MIN_STEP_SECONDS[TR.TierOrder[i]] >= TR.MIN_STEP_SECONDS[TR.TierOrder[i - 1]], TR.TierOrder[i] .. " steps take at least as long as lower tiers") end
ok(TR.TRAVEL_SPEED >= 64 and TR.WARP_SECONDS >= TR.MIN_STEP_SECONDS.Master, "travel model allows the fastest walk (64 studs/s) and a warp")
-- Simulated caskets: unique rates match their rows, Magic Find raises them.
for _, id in ipairs(TR.TierOrder) do
	local r = TR.Rewards[id]
	local rng = streamRng(424242 + TR.Tiers[id].index)
	local n = 30000
	local uniques, coins, rolls, masters = 0, 0, 0, 0
	for _ = 1, n do
		local loot = TR.openCasket(id, rng, 0, 0, P.rollDrops)
		coins += loot.coins
		for _, k in pairs(loot.uniques) do uniques += k end
		if loot.master then masters += 1 end
	end
	local perCasket = 0
	for _, row in ipairs(r.rare) do perCasket += row.chance end
	perCasket *= (r.rolls[1] + r.rolls[2]) / 2
	local observed = uniques / n
	ok(math.abs(observed - perCasket) <= perCasket * 0.35 + 0.0015, string.format("%s unique rate %.4f near %.4f per casket", id, observed, perCasket))
	ok(coins / n > 0, id .. " caskets pay coins")
	if id == "Elite" then
		ok(math.abs(masters / n - TR.MASTER_FROM_ELITE) < 0.02, string.format("Elite caskets hold a Master scroll %.3f of the time", masters / n))
	else
		eq(masters, 0, id .. " caskets never hold Master scrolls")
	end
	local rng2 = streamRng(9090 + TR.Tiers[id].index)
	local boosted = 0
	for _ = 1, n do for _, k in pairs(TR.openCasket(id, rng2, 200, 0, P.rollDrops).uniques) do boosted += k end end
	ok(boosted > uniques, id .. " +200 Magic Find finds more uniques (" .. boosted .. " > " .. uniques .. ")")
end

-- Scroll sources: every content id maps to a tier with a sane chance.
local order = {}
for i, id in ipairs(TR.TierOrder) do order[id] = i end
local lastTier = 1
for _, lvl in ipairs({1, 10, 14, 15, 29, 30, 49, 50, 74, 75, 99, 120}) do
	local t = TR.tierForLevel(lvl)
	ok(order[t] >= lastTier, "tier never falls as level rises (" .. lvl .. ")")
	lastTier = order[t]
end
eq(TR.tierForLevel(1), "Beginner", "level 1 content -> Beginner")
eq(TR.tierForLevel(99), "Elite", "level 99 content -> Elite")
local sourceTiers = {}
local function checkSource(kind, id)
	local list = TR.dropsFor(kind, id)
	ok(#list >= 1, kind .. " " .. id .. " can drop a scroll")
	for _, d in ipairs(list) do
		ok(TR.Tiers[d.tier] ~= nil and d.chance > 0 and d.chance <= 1 / 40, kind .. " " .. id .. " " .. d.tier .. " chance")
		sourceTiers[d.tier] = true
	end
end
for id in pairs(Data.Monsters) do checkSource("kill", id) end
for skill, tiers in pairs(Data.ResourceTiers) do for _, r in ipairs(tiers) do checkSource(if skill == "Fishing" then "fish" else "gather", r.id) end end
for _, t in ipairs(Data.Thieving.Targets) do checkSource("thieve", t.id) end
for _, c in ipairs(Data.Hunter.Creatures) do checkSource("catch", c.id) end
for _, id in ipairs(TR.TierOrder) do ok(sourceTiers[id] or id == "Master", id .. " scrolls drop somewhere") end
ok(sourceTiers.Master == true, "Master scrolls drop from the mightiest monsters too")
eq(#TR.dropsFor("kill", "Nope"), 0, "unknown monster drops nothing")
eq(#TR.dropsFor("dance", "Ore"), 0, "unknown event kind drops nothing")
for kind, list in pairs(TR.SourceChance) do
	local prev = 1
	for _, id in ipairs(TR.TierOrder) do
		if list[id] then ok(list[id] <= prev, kind .. " " .. id .. " rarer than the tier below"); prev = list[id] end
	end
end

-- The step pool.
ok(#TR.Steps >= 120, "120+ trail steps (" .. #TR.Steps .. ")")
local byKind = {}
for _, s in ipairs(TR.Steps) do byKind[s.kind] = (byKind[s.kind] or 0) + 1 end
ok((byKind.dig or 0) >= 30, "30+ dig steps")
ok((byKind.riddle or 0) >= 30, "30+ riddle steps")
ok((byKind.emote or 0) >= 20, "20+ emote steps")
ok((byKind.skill or 0) >= 30, "30+ skill steps")
ok((byKind.puzzle or 0) >= 5, "5+ puzzle boxes")
local maps, coords = 0, 0
local actions = {}
local riddleTexts = {}
for i, s in ipairs(TR.Steps) do
	eq(s.index, i, s.id .. " index")
	eq(TR.StepById[s.id], s, s.id .. " indexed")
	ok(s.tiers[1] >= 1 and s.tiers[1] <= s.tiers[2] and s.tiers[2] <= 6, s.id .. " tier gate")
	local anyTier = false
	for _, id in ipairs(TR.TierOrder) do if TR.eligible(s, id) then anyTier = true end end
	ok(anyTier, s.id .. " is drawable by some tier")
	local d = TR.describe(s)
	ok(type(d.text) == "string" and #d.text > 10 and type(d.hint) == "string" and #d.hint > 5, s.id .. " text and hint")
	if s.kind == "dig" then
		ok(TR.Landmarks[s.anchor] ~= nil, s.id .. " landmark")
		ok(math.abs(s.east) + math.abs(s.north) >= 3 and math.abs(s.east) <= 12 and math.abs(s.north) <= 12, s.id .. " offset hidden but close")
		if s.sketch then maps += 1; ok(not has(d.text, TR.Landmarks[s.anchor].name), s.id .. " map text never names its landmark"); eq(d.guide[1], "region:" .. s.region, s.id .. " map guide is region-only")
		else coords += 1; ok(has(d.text, "paces"), s.id .. " coordinate bearing") end
	elseif s.kind == "riddle" then
		ok(not riddleTexts[s.text], s.id .. " riddle text unique")
		riddleTexts[s.text] = true
		if s.npc then
			local npc = Data.Townsfolk.NPCs[s.npc]
			ok(npc ~= nil, s.id .. " NPC exists")
			ok(not has(s.text, npc.name) and not has(d.hint, npc.name), s.id .. " never names the NPC")
		else
			ok(TR.Landmarks[s.anchor] ~= nil, s.id .. " landmark")
			ok(not has(d.text, TR.Landmarks[s.anchor].name) and not has(d.hint, TR.Landmarks[s.anchor].name), s.id .. " never names the answer")
		end
		eq(#d.guide, 1, s.id .. " guide points only at a region")
		ok(has(d.guide[1], "region:"), s.id .. " guide is a region")
	elseif s.kind == "emote" then
		ok(TR.Landmarks[s.anchor] ~= nil and TR.Gestures[s.gesture] ~= nil, s.id .. " landmark and gesture")
		for _, w in ipairs(s.wear) do
			local def = Data.Items[w]
			ok(def ~= nil and def.slot ~= nil and (def.kind == "weapon" or def.kind == "armor"), s.id .. " wears " .. w)
		end
		local slots = {}
		for _, w in ipairs(s.wear) do ok(not slots[Data.Items[w].slot], s.id .. " one item per slot"); slots[Data.Items[w].slot] = true end
		if s.tiers[1] == 1 then eq(#s.wear, 0, s.id .. " Beginner emotes need no gear") end
	elseif s.kind == "skill" then
		local def = TR.skillTarget(s)
		ok(def ~= nil, s.id .. " target " .. s.target .. " exists")
		ok(s.count >= 1 and s.count <= 3, s.id .. " count")
		actions[s.action] = true
		local req = TR.requires(s)
		if req.region then ok(Data.RegionById[req.region] ~= nil, s.id .. " region") end
		if req.region then ok(TR.Tiers[TR.TierOrder[s.tiers[1]]].regions[req.region], s.id .. " task region open to its lowest tier") end
	elseif s.kind == "puzzle" then
		ok(s.tiers[1] >= 2, s.id .. " puzzle boxes start at Easy")
		eq(#d.guide, 0, s.id .. " puzzle guide reveals nothing")
	end
	if s.region then ok(Data.RegionById[s.region] ~= nil, s.id .. " region exists") end
end
ok(maps >= 10 and coords >= 10, "both map (" .. maps .. ") and coordinate (" .. coords .. ") digs")
for _, a in ipairs({"gather", "fish", "kill", "thieve", "catch", "craft"}) do ok(actions[a], "skill steps use " .. a) end
-- Every tier's pool can fill its longest trail several times over.
local fresh = {levels = {}, regions = {Hub = true, Meadow = true, Quarry = true}}
local maxed = {levels = {}, regions = {}}
for _, s in ipairs(Data.SkillOrder) do maxed.levels[s] = 99 end
for _, r in ipairs(Data.Regions) do maxed.regions[r.id] = true end
for _, id in ipairs(TR.TierOrder) do
	local t = TR.Tiers[id]
	local pool = TR.pool(id)
	ok(#pool >= t.steps[2] * 3, id .. " pool " .. #pool .. " >= 3x its longest trail")
	ok(#TR.pool(id, maxed) == #pool, id .. " a maxed reader qualifies for every step")
	local kinds = {}
	for _, s in ipairs(pool) do
		kinds[s.kind] = true
		ok(s.region == nil or t.regions[s.region], id .. " " .. s.id .. " region gated by tier")
	end
	for _, k in ipairs(TR.KindOrder) do
		if (t.kinds[k] or 0) > 0 then ok(kinds[k], id .. " pool offers " .. k) else ok(not kinds[k], id .. " pool never offers " .. k) end
	end
end
eq(#TR.pool("Beginner", fresh), #TR.pool("Beginner", maxed), "a brand-new journal qualifies for every Beginner step")
-- Generation: deterministic, distinct, sized by tier, filtered by the reader.
for _, id in ipairs(TR.TierOrder) do
	local t = TR.Tiers[id]
	local lengths = {}
	for seed = 1, 60 do
		local a = TR.generate(id, seed * 7717, maxed)
		local b = TR.generate(id, seed * 7717, maxed)
		eq(table.concat(a, ","), table.concat(b, ","), id .. " seed " .. seed .. " deterministic")
		ok(#a >= t.steps[1] and #a <= t.steps[2], id .. " seed " .. seed .. " length " .. #a)
		lengths[#a] = true
		local seen = {}
		for _, sid in ipairs(a) do
			ok(not seen[sid] and TR.eligible(TR.StepById[sid], id, maxed), id .. " " .. sid .. " distinct and eligible")
			seen[sid] = true
		end
	end
	ok(lengths[t.steps[1]] and lengths[t.steps[2]], id .. " trails span the full step range")
end
do
	local seen = {}
	for seed = 1, 400 do for _, sid in ipairs(TR.generate("Hard", seed * 31, maxed)) do seen[sid] = true end end
	local n = 0
	for _ in pairs(seen) do n += 1 end
	ok(n >= #TR.pool("Hard") * 0.9, "400 Hard trails touch 90% of the Hard pool (" .. n .. ")")
	-- A low-level reader never draws steps above their levels.
	local novice = {levels = {}, regions = fresh.regions}
	for seed = 1, 100 do
		for _, sid in ipairs(TR.generate("Medium", seed, novice)) do ok(TR.eligible(TR.StepById[sid], "Medium", novice), "novice Medium step " .. sid .. " fits the reader") end
	end
	eq(#TR.generate("Nope", 1), 0, "unknown tier generates nothing")
	-- A reader who qualifies for nothing gets nothing (never steps they cannot do).
	local nobody = {levels = {}, regions = {}}
	for _, s in ipairs(Data.SkillOrder) do nobody.levels[s] = 0 end
	for _, id in ipairs(TR.TierOrder) do
		if #TR.pool(id, nobody) == 0 then eq(#TR.generate(id, 99, nobody), 0, id .. ": an empty filtered pool generates no steps") end
	end
	ok(#TR.pool("Beginner", nobody) == 0, "the empty-pool case is exercised")
end
-- Sliding puzzle rules.
eq(TR.slide(TR.SOLVED, "D"), nil, "gap in the corner cannot move down")
eq(TR.slide(TR.SOLVED, "R"), nil, "nor right")
eq(TR.slide(TR.SOLVED, "U"), "123450786", "gap moves up")
eq(TR.slide(TR.SOLVED, "L"), "123456708", "gap moves left")
eq(TR.slide("12345678", "U"), nil, "short board refused")
eq(TR.slide("123456788", "U"), nil, "duplicate tile refused")
eq(TR.slide(TR.SOLVED, "X"), nil, "unknown move refused")
eq(TR.applyMoves(TR.SOLVED, "UL"), "123405786", "move string applies in order")
local _, badAt = TR.applyMoves(TR.SOLVED, "UDDD")
eq(badAt, 3, "first illegal move reported")
eq(TR.applyMoves(TR.SOLVED, string.rep("UD", 25)), nil, "too many moves at once")
eq(TR.applyMoves(TR.SOLVED, string.rep("UD", 24)), TR.SOLVED, "a full batch applies")
eq(TR.applyMoves(TR.SOLVED, ""), nil, "no moves")
-- BFS over the 181,440 solvable boards: every scramble is solvable.
local parent = {[TR.SOLVED] = false}
do
	local queue, head = {TR.SOLVED}, 1
	while head <= #queue do
		local b = queue[head]; head += 1
		for _, dir in ipairs({"U", "D", "L", "R"}) do
			local nb = TR.slide(b, dir)
			if nb and parent[nb] == nil then parent[nb] = TR.Opposite[dir]; table.insert(queue, nb) end
		end
	end
	eq(#queue, 181440, "the solvable half of the 3x3 boards")
end
local function solve(board)
	local moves = {}
	while board ~= TR.SOLVED do
		local m = parent[board]
		assert(m, "unsolvable board " .. board)
		table.insert(moves, m)
		board = TR.slide(board, m)
	end
	return table.concat(moves)
end
for _, id in ipairs(TR.TierOrder) do
	for seed = 1, 20 do
		local b = TR.scramble(seed * 101, TR.Tiers[id].scramble)
		ok(TR.validBoard(b) and b ~= TR.SOLVED and parent[b] ~= nil, id .. " scramble " .. seed .. " solvable and unsolved")
		eq(TR.applyMoves(b, solve(b):sub(1, 48)) == TR.SOLVED or #solve(b) > 48, true, id .. " scramble " .. seed .. " solved by its path")
	end
end
eq(TR.scramble(5, 30), TR.scramble(5, 30), "scramble deterministic")
-- Profile sanitiser.
do
	local clean = TR.sanitize(nil)
	ok(next(clean.active) == nil and #clean.emotes == 0, "empty record")
	for _, id in ipairs(TR.TierOrder) do eq(clean.log[id].completed, 0, id .. " log starts at 0") end
	local dirty = TR.sanitize({
		active = {Hard = {seed = 77, steps = {"DigMoonpool", "Nope"}, step = 9}, Easy = {seed = "x"}, Bogus = {seed = 3, steps = {"DigMoonpool"}},
			Medium = {seed = 5, steps = {"PuzzleCipher", "RiddleBanker"}, step = 1, board = "bad"}, Beginner = {seed = 9, steps = {"DigMoonpool"}, step = 1, board = "123456780"}},
		log = {Easy = {completed = -4, opened = 1e20}}, uniques = {TrailCapWayfarer = 2, Ore = 5}, emotes = {"CourtlyBow", "CourtlyBow", "Nope"}, banner = "Ore", r = -5,
	})
	ok(dirty.active.Hard ~= nil and #dirty.active.Hard.steps >= TR.Tiers.Hard.steps[1], "a trail with a lost step is re-drawn from its seed")
	eq(table.concat(dirty.active.Hard.steps, ","), table.concat(TR.generate("Hard", 77), ","), "re-draw uses the seed")
	eq(dirty.active.Easy, nil, "seedless trail dropped")
	eq(dirty.active.Bogus, nil, "unknown tier dropped")
	ok(TR.validBoard(dirty.active.Medium.board) and dirty.active.Medium.board ~= "bad", "tampered puzzle board re-scrambled")
	eq(dirty.active.Beginner.board, nil, "non-puzzle steps hold no board")
	eq(dirty.log.Easy.completed, 0, "negative counts clamped")
	ok(dirty.log.Easy.opened <= 1e9, "huge counts clamped")
	eq(dirty.uniques.TrailCapWayfarer, 2, "known unique kept")
	eq(dirty.uniques.Ore, nil, "non-unique dropped from the log")
	eq(#dirty.emotes, 1, "emotes deduplicated and validated")
	eq(dirty.banner, nil, "non-banner refused")
	eq(dirty.r, nil, "no roll stream is persisted (legacy r dropped)")
	-- Re-draws use the reader's context; a reader who qualifies for nothing loses the trail (tier listed for a refund).
	local novice = {levels = {}, regions = {Hub = true, Meadow = true, Quarry = true}}
	local redrawn, lost = TR.sanitize({active = {Medium = {seed = 31, steps = {"Nope"}, step = 1}}}, novice)
	ok(redrawn.active.Medium ~= nil and #lost == 0, "a novice's lost trail is re-drawn")
	for _, sid in ipairs(redrawn.active.Medium.steps) do ok(TR.eligible(TR.StepById[sid], "Medium", novice), "re-drawn step " .. sid .. " fits the reader") end
	local nobody = {levels = {}, regions = {}}
	for _, sk in ipairs(Data.SkillOrder) do nobody.levels[sk] = 0 end
	local dropped, lostTiers = TR.sanitize({active = {Beginner = {seed = 31, steps = {"Nope"}, step = 1}, Easy = {seed = 5, steps = {"DigMoonpool"}, step = 1}}}, nobody)
	eq(dropped.active.Beginner, nil, "an impossible re-draw drops the trail")
	eq(#lostTiers, 1, "one tier lost")
	eq(lostTiers[1], "Beginner", "the lost tier is reported for a refund")
	ok(dropped.active.Easy ~= nil, "valid stored steps are kept as they are")
	local paced = TR.sanitize({active = {Easy = {seed = 5, steps = {"DigMoonpool"}, step = 1, lt = 100, lx = 3, lz = -4}, Hard = {seed = 7, steps = {"DigMoonpool"}, step = 1, lt = 5, lx = "x"}}})
	ok(paced.active.Easy.lt == 100 and paced.active.Easy.lx == 3 and paced.active.Easy.lz == -4, "last location kept")
	eq(paced.active.Hard.lt, nil, "a malformed last location is dropped")
	eq(TR.sanitize({active = {Easy = {seed = 4, steps = {"DigMoonpool", "DigVaultSteps"}, step = 7}}}).active.Easy.step, 2, "step index clamped to the trail")
end
print("PASS: " .. (checks - partA) .. " Treasure Trails data assertions.")

------------------------------------------------------------------------------
-- Part B: every step resolves in the built world.
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
	UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
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
local anchorCache = {}
local function anchorPart(name)
	if anchorCache[name] == nil then anchorCache[name] = islands:FindFirstChild("Anchor_" .. name, true) or false end
	return anchorCache[name] or nil
end
local function regionOfIsland(isle) return isle:GetAttribute("RegionId") or isle:GetAttribute("Region") end
for name, lm in pairs(TR.Landmarks) do
	local a = anchorPart(name)
	ok(a ~= nil, "landmark anchor " .. name .. " exists")
	if a then eq(regionOfIsland(islandOf(a)), lm.region, name .. " lies on a " .. lm.region .. " island") end
end
local npcRoles = {}
for _, s in ipairs(TR.Steps) do
	if s.anchor then
		local a = anchorPart(s.anchor)
		ok(a ~= nil, s.id .. " anchor " .. s.anchor)
		local isle = islandOf(a)
		eq(regionOfIsland(isle), s.region, s.id .. " region matches its island")
		if s.kind == "dig" then
			local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
			local pos = a.CFrame.Position
			local x, z = pos.X + s.east, pos.Z - s.north
			local dist = Vector3.new(x - c.X, 0, z - c.Z).Magnitude
			ok(dist <= r * 0.85, string.format("%s dig point on the island (%.0f of %.0f studs)", s.id, dist, r))
			ok(Vector3.new(s.east, 0, s.north).Magnitude > TR.DIG_RADIUS - 2, s.id .. " standing on the landmark is not enough")
		end
		if s.npc then npcRoles[s.npc] = true end
	end
end
for role in pairs(npcRoles) do
	eq(Data.Townsfolk.NPCs[role].region, regionOfIsland(islandOf(anchorPart("NPC_" .. role))), role .. " NPC stands in its own region")
end
for _, tp in ipairs(TR.Teleports) do
	local a = anchorPart(tp.anchor)
	ok(a ~= nil, tp.id .. " lands on " .. tp.anchor)
	eq(regionOfIsland(islandOf(a)), tp.region, tp.id .. " lands in its region")
end
-- Gestures are names the relay accepts.
do
	local relay
	luau.load(fs.readFile("gesture.server.lua"), {environment = {__GestureRelayHarness = function(R) relay = R end}, injectGlobals = true})()
	ok(relay ~= nil, "gesture relay harness loaded")
	for name in pairs(TR.Gestures) do ok(relay.NAMES[name] == true, "gesture " .. name .. " is relayed") end
	for _, s in ipairs(TR.Steps) do if s.kind == "emote" then ok(relay.itemOk(Data, s.gesture, nil), s.id .. " gesture needs no held item") end end
end
print("PASS: " .. (checks - partB) .. " Treasure Trails world assertions.")

------------------------------------------------------------------------------
-- Part C: server behaviour.
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
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}, AetherTrails = {Name = "AetherTrails"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [markers.AetherTrails] = buildTrails}
-- npc.server.lua's travel gate double: true = open, a string = the refusal.
local gateVerdict, gateCalls = true, 0
local travelGate = {Invoke = function(_, who) gateCalls += 1; return gateVerdict end}
local gatePresent = true
-- Islands lookups (anchor cache misses must not re-scan every request).
local islandLookups = 0
-- Random.new() calls made by the server (seed argument recorded).
local randomNews = {}
-- Server entropy doubles for the trails stream: `entropy()` is unpredictable
-- across runs (seeded from the wall clock); `scripted(seed)` is a test-chosen
-- deterministic stream so drop-rate checks are exact. `counted` counts draws.
math.randomseed(math.floor((os.clock() * 1e6) % 2147483647) + math.floor(os.time() % 100000))
local function entropy()
	return {NextNumber = function() return math.random() end, NextInteger = function(_, lo, hi) return math.random(lo, hi) end}
end
local function scripted(seed)
	local rng = TR.stream(seed)
	return {NextNumber = function() return rng() end, NextInteger = function(_, lo, hi) return lo + math.floor(rng() * (hi - lo + 1)) end}
end
local draws = 0
local function counted(source)
	return {NextNumber = function(self) draws += 1; return source:NextNumber() end, NextInteger = function(self, lo, hi) draws += 1; return source:NextInteger(lo, hi) end}
end
local trailsApi
local rolls, defaultRoll = {}, 0.999
local function nextRoll() if #rolls > 0 then return table.remove(rolls, 1) end return defaultRoll end
local function queue(...) for _, v in ipairs({...}) do table.insert(rolls, v) end end
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name)
		if name == "AetherTrails" then return markers.AetherTrails end
		if name == "IsleTravelGate" and gatePresent then return travelGate end
		return nil
	end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "trails-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local serverWorkspace = {GetAttribute = function(self, key) return rawget(self, key) end,
	FindFirstChild = function(_, name) if name == "Islands" then islandLookups += 1; return islands end return nil end}
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
	Random = {new = function(seed)
		local r = {NextNumber = function() return nextRoll() end, NextInteger = function(_, lo, hi) return lo + math.floor(nextRoll() * (hi - lo + 1)) end}
		table.insert(randomNews, {seed = seed, object = r})
		return r
	end},
	__TrailsHarness = function(api) trailsApi = api end,
	task = {
		spawn = function(f, ...)
			local co = coroutine.create(f)
			local okRun, err = coroutine.resume(co, ...)
			assert(okRun, err)
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
ok(trailsApi ~= nil and trailsApi.enabled == true, "the Trails block loaded its server-only step module")
do
	-- The trails stream is a Random.new() without a seed (server entropy).
	local mine
	for _, r in ipairs(randomNews) do if r.object == trailsApi.random then mine = r end end
	ok(mine ~= nil and mine.seed == nil, "the trails stream is an unseeded Random.new() (server entropy)")
	ok(trailsApi.random ~= nil and trailsApi.rand == nil and trailsApi.seq == nil, "no per-profile roll stream or per-server seed counter")
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
local function use(p, q)
	advance(1)
	p.root.Position = q.Parent.CFrame.Position
	p.last = nil
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
local function standAt(p, anchorName, east, north, lift)
	local pos = anchorPart(anchorName).CFrame.Position
	p.root.Position = Vector3.new(pos.X + (east or 0), pos.Y + (lift or 3), pos.Z - (north or 0))
end
local function stored(p) leave(p); return data["p" .. p.UserId].profile end
local X = Data.XP_TABLE

-- A fresh journal: empty trails, migrated record, no scrolls.
local wanderer = player(9101)
local s0 = cmd(wanderer, "state")
ok(type(s0.trails) == "table", "snapshot carries trails")
eq(next(s0.trails.active), nil, "no active trails")
eq(s0.trails.spade, false, "no spade yet")
for _, id in ipairs(TR.TierOrder) do eq(s0.trails.log[id].completed, 0, id .. " log empty") end
eq(wanderer.attrs.TrailBanner, "", "no banner raised")
ok(has(cmd(wanderer, "trailBegin", "Easy").message, "no Weathered Trail Scroll"), "cannot read a scroll you lack")
ok(has(cmd(wanderer, "trailBegin", "Nope").message, "Choose a trail tier"), "unknown tier refused")
ok(has(cmd(wanderer, "trailOpen", "Easy").message, "no Weathered Trail Casket"), "cannot open a casket you lack")
ok(has(cmd(wanderer, "trailDig").message, "Wayfinder's Spade"), "digging needs a spade")
ok(has(cmd(wanderer, "trailSearch").message, "None of your trails"), "nothing to search for")
ok(has(cmd(wanderer, "trailSlide", "Easy:UL").message, "No puzzle box"), "no puzzle to slide")
ok(has(cmd(wanderer, "trailEmote", "dance").message, "Choose an emote"), "unknown gesture refused")
ok(has(cmd(wanderer, "trailAbandon", "Easy").message, "No such trail"), "nothing to abandon")
-- Forging the spade.
wanderer = rejoin(wanderer, function(prof) prof.items.AlloyIngot = 2; prof.items.Timber = 4 end)
local forged = cmd(wanderer, "craft", TR.SPADE)
eq(forged.items[TR.SPADE], 1, "spade forged")
eq(forged.trails.spade, true, "snapshot knows the spade")
ok(has(cmd(wanderer, "craft", TR.SPADE).message, "already own"), "one spade is enough")

-- Scroll drops from the kill bridge: one per tier at most.
do
	trailsApi.random = scripted(12345)
	local hunter = seeded(9102, function(prof) prof.trails.r = 12345 end) -- a legacy stream field is dropped on load
	eq(stored(hunter).trails.r, nil, "legacy roll stream removed by migrate")
	hunter = player(9102)
	local scrolls = 0
	for _ = 1, 400 do
		bridge.OnInvoke("kill", hunter, {monster = "BramblebackBoar"})
	end
	local after = cmd(hunter, "state")
	scrolls = after.items.TrailScrollBeginner or 0
	eq(scrolls, 1, "400 boar kills: a Beginner scroll, but only one")
	eq(after.items.TrailScrollEasy, nil, "boars never drop Easy scrolls")
	-- Holding the scroll, kills draw nothing from the stream (players cannot
	-- burn draws to steer the next casket).
	trailsApi.random = counted(scripted(4))
	draws = 0
	for _ = 1, 100 do bridge.OnInvoke("kill", hunter, {monster = "BramblebackBoar"}) end
	eq(draws, 0, "no draws while the drop could not be granted")
	trailsApi.random = scripted(12346)
	-- Rate with the gate lifted: read and abandon each scroll as it drops.
	cmd(hunter, "trailBegin", "Beginner")
	cmd(hunter, "trailAbandon", "Beginner")
	local drops = 0
	for _ = 1, 2000 do
		hunter.last = nil
		bridge.OnInvoke("kill", hunter, {monster = "Thornling"})
		if hunter.last and (hunter.last.items.TrailScrollBeginner or 0) > 0 then
			drops += 1
			ok(has(hunter.last.message, "Tattered Trail Scroll"), "kill notice names the scroll")
			cmd(hunter, "trailBegin", "Beginner")
			cmd(hunter, "trailAbandon", "Beginner")
		end
	end
	ok(drops >= 2000 / 40 * 0.6 and drops <= 2000 / 40 * 1.4, "Beginner kill drop rate near 1/40 (" .. drops .. " in 2000)")
	leave(hunter)
end
-- Mid-level kills drop the matching tier; an active trail blocks a second scroll.
do
	trailsApi.random = scripted(777)
	local fighter = seeded(9103, function() end)
	for _ = 1, 600 do bridge.OnInvoke("kill", fighter, {monster = "GaleSprite"}) end
	local st = cmd(fighter, "state")
	eq(st.items.TrailScrollEasy, 1, "Gale Sprites (level 24) drop an Easy scroll")
	eq(st.items.TrailScrollBeginner, nil, "and nothing of other tiers")
	local read = cmd(fighter, "trailBegin", "Easy")
	ok(has(read.message, "You unroll"), "reading begins the trail")
	eq(read.items.TrailScrollEasy, 0, "the scroll is consumed")
	ok(read.trails.active.Easy ~= nil, "Easy trail active")
	eq(read.trails.active.Easy.step, 1, "at step 1")
	for _ = 1, 600 do bridge.OnInvoke("kill", fighter, {monster = "GaleSprite"}) end
	eq(cmd(fighter, "state").items.TrailScrollEasy, 0, "no second Easy scroll while a trail is active")
	ok(has(cmd(fighter, "trailBegin", "Easy").message, "already following"), "cannot stack trails")
	local gone = cmd(fighter, "trailAbandon", "Easy")
	ok(has(gone.message, "go cold"), "abandon")
	eq(gone.trails.active.Easy, nil, "trail gone")
	leave(fighter)
end
-- Gathering, fishing and thieving drop scrolls too (through the world prompts).
local gatherPrompts, thievePrompts = {}, {}
for _, q in islands:GetDescendants() do
	if q:IsA("ProximityPrompt") then
		local act, id = q:GetAttribute("IsleAction"), q:GetAttribute("IsleItem")
		if act == "gather" and not gatherPrompts[id] then gatherPrompts[id] = q end
		if act == "thieve" then thievePrompts[id] = q end
	end
end
ok(gatherPrompts.Ore ~= nil and gatherPrompts.Fish ~= nil and gatherPrompts.Herb ~= nil, "gather prompts found")
do
	trailsApi.random = scripted(4242)
	local miner = seeded(9104, function() end)
	local got
	for i = 1, 1500 do
		if i % 4 == 0 then miner = rejoin(miner) end -- renew the journal lease (no autosave loop here)
		local s = use(miner, gatherPrompts.Ore)
		ok(s ~= nil and has(s.message, "Copperstone Ore"), "swing " .. i .. " mined ore: " .. tostring(s and s.message))
		advance(30)
		if s and (s.items.TrailScrollBeginner or 0) > 0 then got = i break end
	end
	ok(got ~= nil, "mining Copperstone found a Beginner scroll (after " .. tostring(got) .. " swings)")
	ok(has(miner.last.message, "You found a Tattered Trail Scroll"), "find notice")
	leave(miner)
	trailsApi.random = scripted(99)
	local angler = seeded(9105, function() end)
	got = nil
	for i = 1, 1500 do
		if i % 4 == 0 then angler = rejoin(angler) end
		local s = use(angler, gatherPrompts.Fish)
		ok(s ~= nil and has(s.message, "Minnow"), "cast " .. i .. " caught a minnow")
		advance(30)
		if s and (s.items.TrailScrollBeginner or 0) > 0 then got = i break end
	end
	ok(got ~= nil, "fishing found a Beginner scroll (after " .. tostring(got) .. " casts)")
	leave(angler)
	trailsApi.random = scripted(31337)
	local thief = seeded(9106, function() end)
	got = nil
	for i = 1, 1200 do
		if i % 20 == 0 then thief = rejoin(thief) end
		queue(0) -- success
		local s = use(thief, thievePrompts.Farmhand)
		advance(5)
		if s and (s.items.TrailScrollBeginner or 0) > 0 then got = i break end
	end
	ok(got ~= nil, "pickpocketing found a Beginner scroll (after " .. tostring(got) .. " thefts)")
	leave(thief)
	rolls = {}
end

-- A hand-built Master trail walks every step kind in order.
local route = {"DigMoonpool", "RiddleBanker", "EmoteMarket", "SkillGatherOre", "PuzzleTinker", "SkillCraftCookedFish", "SkillKillBramblebackBoar", "EmoteStarforge", "DigVaultSteps"}
local walker = seeded(9110, function(prof)
	prof.items[TR.SPADE] = 1
	prof.items.Fish, prof.items.Herb = 3, 3
	prof.items.Blade = 1
	prof.trails.active.Master = {seed = 4321, steps = route, step = 1}
end)
local st = cmd(walker, "state")
local row = st.trails.active.Master
eq(row.kind, "dig", "step 1 is a dig")
eq(row.style, "map", "the Moonpool dig is a map")
ok(not has(row.text, "Moonpool"), "map text keeps the landmark secret")
eq(row.guide[1], "region:Meadow", "map guide only names the region")
-- Too soon: a location step waits TR.MIN_STEP_SECONDS after it began, and the
-- wait is the same answer anywhere (it never confirms a location).
local digStep = TR.StepById.DigMoonpool
standAt(walker, "Waypoint_Moonpool", digStep.east, digStep.north)
local early = cmd(walker, "trailDig", "Master")
ok(has(early.message, "still fresh"), "an instant dig at the right spot is refused: " .. tostring(early.message))
eq(early.trails.active.Master.step, 1, "the early dig did not advance")
standAt(walker, "Waypoint_Bank", 0, 0)
local function unclocked(text) return (string.gsub(text, "%(%d+s%)", "")) end
eq(unclocked(cmd(walker, "trailDig", "Master").message), unclocked(early.message), "the wait reads the same at a wrong spot")
local function ripen() advance(TR.WARP_SECONDS) end
ripen()
-- Wrong place, wrong verb.
standAt(walker, "Waypoint_Moonpool", 0, 0)
ok(has(cmd(walker, "trailDig").message, "only soil"), "digging on the landmark itself finds nothing")
ok(has(cmd(walker, "trailSearch").message, "None of your trails is a riddle"), "searching is not digging")
ok(has(cmd(walker, "trailEmote", "flip").message, "Nobody seems to notice"), "an emote is not a dig")
eq(cmd(walker, "state").trails.active.Master.step, 1, "anti-skip: still step 1")
standAt(walker, "Waypoint_Moonpool", digStep.east + 3, digStep.north - 2)
local dug = cmd(walker, "trailDig", "Master")
ok(has(dug.message, "buried tin"), "dig within the radius succeeds")
eq(dug.trails.active.Master.step, 2, "advanced to step 2")
eq(dug.trails.active.Master.kind, "riddle", "step 2 is a riddle")
ok(not has(dug.trails.active.Master.text, "Odile"), "riddle never names the NPC")
ripen()
standAt(walker, "Waypoint_Moonpool", 0, 0)
ok(has(cmd(walker, "trailSearch").message, "find nothing"), "searching far from the answer")
standAt(walker, "NPC_Banker", 4, 4)
local found = cmd(walker, "trailSearch")
ok(has(found.message, "Odile Marrowcoin slips you a folded note"), "the banker hands over the next note")
eq(found.trails.active.Master.kind, "emote", "step 3 is an emote")
eq(found.trails.active.Master.gesture, "flip", "the step names its gesture")
standAt(walker, "Waypoint_Market", 2, 2)
ripen()
ok(has(cmd(walker, "trailEmote", "heal").message, "Nobody"), "wrong gesture does nothing")
local emoted = cmd(walker, "trailEmote", "flip")
ok(has(emoted.message, "hooded stranger"), "right gesture at the landmark")
eq(emoted.trails.active.Master.kind, "skill", "step 4 is a task")
eq(emoted.trails.active.Master.need, 3, "gather three ore")
eq(emoted.trails.active.Master.have, 0, "progress starts at 0")
for i = 1, 3 do
	use(walker, gatherPrompts.Ore)
	advance(30)
	walker = rejoin(walker)
	if i < 3 then eq(cmd(walker, "state").trails.active.Master.have, i, "ore progress " .. i) end
end
local afterOre = cmd(walker, "state").trails.active.Master
eq(afterOre.kind, "puzzle", "step 5 is a puzzle box")
ok(TR.validBoard(afterOre.board) and afterOre.board ~= TR.SOLVED, "the box arrives scrambled")
do
	local illegal
	for _, dir in ipairs({"U", "D", "L", "R"}) do if not TR.slide(afterOre.board, dir) then illegal = dir end end
	ok(has(cmd(walker, "trailSlide", "Master:" .. illegal).message, "cannot slide"), "illegal slides refused")
end
eq(cmd(walker, "state").trails.active.Master.board, afterOre.board, "a refused slide changes nothing")
ok(has(cmd(walker, "trailSlide", "Master:" .. string.rep("UD", 25)).message, "Too many"), "move batches are bounded")
ok(has(cmd(walker, "trailSlide", "Master:XYZ").message, "No puzzle"), "malformed moves refused")
local path = solve(afterOre.board)
local board = afterOre.board
local sentMoves = 0
while #path > 0 do
	local chunk = path:sub(1, 20)
	path = path:sub(21)
	local r = cmd(walker, "trailSlide", "Master:" .. chunk)
	board = TR.applyMoves(board, chunk)
	sentMoves += #chunk
	if #path > 0 then eq(r.trails.active.Master.board, board, "server tracks the board") else ok(has(r.message, "clicks open"), "the solved box opens") end
end
local crafted = cmd(walker, "state").trails.active.Master
eq(crafted.kind, "skill", "step 6 is a craft task")
eq(crafted.have, 0, "earlier crafts do not count")
local cooked = cmd(walker, "craft", "CookedFish")
eq(cooked.trails.active.Master.kind, "skill", "craft settled on the snapshot")
eq(cmd(walker, "state").trails.active.Master.need, 2, "step 7 asks for two boar kills")
bridge.OnInvoke("kill", walker, {monster = "ShaleCrawler"})
eq(cmd(walker, "state").trails.active.Master.have, 0, "other monsters do not count")
bridge.OnInvoke("kill", walker, {monster = "BramblebackBoar"})
bridge.OnInvoke("kill", walker, {monster = "BramblebackBoar"})
local em2 = cmd(walker, "state").trails.active.Master
eq(em2.kind, "emote", "step 8 is a geared emote")
eq(em2.wear[1], "Blade", "it lists the gear")
standAt(walker, "Waypoint_Starforge", 1, 1)
ripen()
ok(has(cmd(walker, "trailEmote", "hammer").message, "not wearing Copper Blade"), "gear is checked")
cmd(walker, "equip", "Blade")
local salute = cmd(walker, "trailEmote", "hammer")
ok(has(salute.message, "hooded stranger"), "geared emote accepted")
-- Persistence mid-trail.
walker = rejoin(walker)
local resumed = cmd(walker, "state").trails.active.Master
eq(resumed.step, 9, "step index survives a rejoin")
eq(resumed.style, "map", "the vault dig is a map")
standAt(walker, "Waypoint_Bank", TR.StepById.DigVaultSteps.east, TR.StepById.DigVaultSteps.north)
ripen()
local finish = cmd(walker, "trailDig")
ok(has(finish.message, "The Master trail ends"), "the last step ends the trail")
eq(finish.trails.active.Master, nil, "trail cleared")
eq(finish.items.TrailCasketMaster, 1, "an Aurora casket")
eq(finish.trails.log.Master.completed, 1, "clue log counts the completion")
-- Caskets.
local coinsBefore = finish.coins
local opened = cmd(walker, "trailOpen", "Master")
ok(has(opened.message, "Opened the Aurora Trail Casket"), "casket opened")
eq(opened.items.TrailCasketMaster, 0, "casket consumed")
ok(opened.coins > coinsBefore, "casket paid coins")
eq(opened.trails.log.Master.opened, 1, "clue log counts the opening")
leave(walker)
-- Uniques reach the clue log (many caskets, deterministic stream).
do
	trailsApi.random = scripted(2024)
	local lucky = seeded(9111, function(prof) prof.items.TrailCasketBeginner = 400 end)
	local last
	for i = 1, 400 do
		if i % 100 == 0 then lucky = rejoin(lucky) end
		last = cmd(lucky, "trailOpen", "Beginner")
	end
	eq(last.items.TrailCasketBeginner, 0, "every casket opened")
	eq(last.trails.log.Beginner.opened, 400, "400 Beginner caskets logged")
	local logged = 0
	for id, n in pairs(last.trails.uniques) do
		eq(TR.UniqueTier[id], "Beginner", id .. " logged under Beginner")
		eq(last.items[id], n, id .. " held as often as logged")
		logged += n
	end
	ok(logged >= 10 and logged <= 60, "400 Beginner caskets: " .. logged .. " uniques (expected ~" .. math.floor(400 * 2 * (1 / 40 + 1 / 50 + 1 / 45)) .. ")")
	-- Emote scrolls, banners.
	if (last.items.EmoteScrollJig or 0) > 0 then
		local learnt = cmd(lucky, "trailLearn", "EmoteScrollJig")
		ok(has(learnt.message, "Wayfarer's Jig"), "emote learned")
		eq(learnt.trails.emotes[1], "WayfarersJig", "emote recorded")
		if (learnt.items.EmoteScrollJig or 0) > 0 then ok(has(cmd(lucky, "trailLearn", "EmoteScrollJig").message, "already know"), "no double learning") end
	end
	if (last.items.BannerMeadowlark or 0) > 0 then
		cmd(lucky, "trailBanner", "BannerMeadowlark")
		eq(lucky.attrs.TrailBanner, "Meadowlark Pennant", "banner raised as an attribute")
		cmd(lucky, "trailBanner", "none")
		eq(lucky.attrs.TrailBanner, "", "banner lowered")
	end
	ok(has(cmd(lucky, "trailBanner", "Ore").message, "Choose a banner"), "only banners can be raised")
	ok(has(cmd(lucky, "trailLearn", "Ore").message, "Choose an emote scroll"), "only emote scrolls teach")
	leave(lucky)
end
-- Elite caskets can hold a Master scroll (only when none is held).
do
	trailsApi.random = scripted(55)
	local elite = seeded(9112, function(prof) prof.items.TrailCasketElite = 60 end)
	local masters = 0
	local crumbled = 0
	for _ = 1, 60 do
		local r = cmd(elite, "trailOpen", "Elite")
		if has(r.message, "tucked inside") then masters += 1 end
		if has(r.message, "crumbles") then crumbled += 1 end
	end
	eq(masters, 1, "one Master scroll kept")
	ok(crumbled >= 1, "later Master scrolls crumble while one is held (" .. crumbled .. ")")
	eq(cmd(elite, "state").items.TrailScrollMaster, 1, "exactly one Master scroll")
	leave(elite)
end
-- Teleport leaves respect region gates.
do
	local traveller = seeded(9113, function(prof) prof.items.TeleScrollMeadow = 1; prof.items.TeleScrollTempest = 1 end)
	ok(has(cmd(traveller, "trailTeleport", "TeleScrollTempest").message, "requires"), "a locked region refuses the leaf")
	eq(cmd(traveller, "state").items.TeleScrollTempest, 1, "refused leaf kept")
	local went = cmd(traveller, "trailTeleport", "TeleScrollMeadow")
	ok(has(went.message, "Meadow Reach"), "leaf travel")
	eq(went.items.TeleScrollMeadow, 0, "leaf consumed")
	local landing = anchorPart("Waypoint_Entrance_Meadow").CFrame.Position
	ok((traveller.root.Position - landing).Magnitude < 6, "the traveller stands at the Meadow gate")
	ok(has(cmd(traveller, "trailTeleport", "TeleScrollMeadow").message, "no Waystone"), "no leaf left")
	ok(has(cmd(traveller, "trailTeleport", "Ore").message, "Choose a waystone"), "only leaves teleport")
	leave(traveller)
end
-- Reading a scroll draws a trail the reader can walk (fresh journal, Beginner).
do
	for k = 1, 12 do
		trailsApi.random = scripted(1000 + k * 37)
		local novice = seeded(9200 + k, function(prof) prof.items.TrailScrollBeginner = 1 end)
		local r = cmd(novice, "trailBegin", "Beginner")
		local prof = stored(novice)
		local a = prof.trails.active.Beginner
		ok(a ~= nil and #a.steps >= 1 and #a.steps <= 3, "Beginner trail " .. k .. " has 1-3 steps")
		for _, sid in ipairs(a.steps) do ok(TR.eligible(TR.StepById[sid], "Beginner", fresh), "novice trail " .. k .. " step " .. sid .. " walkable") end
		ok(has(r.message, TR.describe(TR.StepById[a.steps[1]]).text), "the first step is read aloud")
	end
end
-- Tampered saves are cleaned on load.
do
	local cheat = seeded(9300, function(prof)
		prof.trails = {active = {Hard = {seed = 5, steps = {"Nope"}, step = 3}, Easy = {seed = 6, steps = {"DigMoonpool", "DigVaultSteps"}, step = 99}}, log = "x", uniques = {Ore = 9}}
	end)
	local s = cmd(cheat, "state").trails
	ok(s.active.Hard ~= nil, "a broken trail is re-drawn")
	eq(s.active.Easy.step, 2, "step index clamped")
	eq(s.uniques.Ore, nil, "fake uniques dropped")
	eq(s.log.Easy.completed, 0, "log rebuilt")
	leave(cheat)
end
-- Casket rolls come from server entropy: two journals with identical history
-- open identical caskets and get different loot; nothing about the stream is
-- stored with either profile.
do
	trailsApi.random = entropy()
	local function history(prof) prof.items.TrailCasketBeginner = 40; prof.items.TrailCasketHard = 40 end
	local function openAll(id)
		local twin = seeded(id, history)
		local out = {}
		for _ = 1, 40 do
			local r = cmd(twin, "trailOpen", "Beginner")
			table.insert(out, r.message)
			r = cmd(twin, "trailOpen", "Hard")
			table.insert(out, r.message)
		end
		local prof = stored(twin)
		local keys = {}
		for k in pairs(prof.trails) do table.insert(keys, k) end
		table.sort(keys)
		return table.concat(out, "|"), table.concat(keys, ","), prof
	end
	local a, keysA, profA = openAll(9401)
	local b, keysB = openAll(9402)
	ok(a ~= b, "identical histories open different caskets (server entropy)")
	eq(profA.trails.r, nil, "no roll stream persisted")
	eq(keysA, "active,emotes,log,uniques,version", "the stored trails record holds no stream state")
	eq(keysA, keysB, "both journals store the same shape")
	-- A fresh server stream (a new run) gives a different sequence again.
	trailsApi.random = entropy()
	local c = openAll(9403)
	ok(c ~= a and c ~= b, "a new run's stream differs too")
end
-- Trail seeds are drawn from the server stream (never from profile state).
do
	local fixed = {NextNumber = function() return 0.5 end, NextInteger = function(_, lo, hi) assert(lo == 1 and hi == 2147483646, "seed range"); return 424242 end}
	trailsApi.random = fixed
	local reader = seeded(9404, function(prof) prof.items.TrailScrollEasy = 1 end)
	cmd(reader, "trailBegin", "Easy")
	eq(stored(reader).trails.active.Easy.seed, 424242, "the trail seed comes from the server stream")
	local hidden = cmd(player(9404), "state").trails.active.Easy
	eq(hidden.seed, nil, "the seed never reaches the client")
	eq(hidden.steps, nil, "nor the step list")
	trailsApi.random = entropy()
end
-- Re-drawn trails fit the reader (migrate passes the reader's context).
do
	local novice = {levels = {}, regions = {Hub = true, Meadow = true, Quarry = true}}
	local redraw = seeded(9405, function(prof) prof.trails.active = {Hard = {seed = 99, steps = {"Nope"}, step = 1}} end)
	local a = stored(redraw).trails.active.Hard
	ok(a ~= nil and #a.steps >= 1, "lost Hard trail re-drawn on load")
	for _, sid in ipairs(a.steps) do ok(TR.eligible(TR.StepById[sid], "Hard", novice), "re-drawn step " .. sid .. " fits the novice reader") end
end
-- Teleport bots: location steps keep a per-step floor and a travel check.
local baseDigs = {}
for _, st in ipairs(TR.Steps) do
	if st.kind == "dig" and (st.region == "Hub" or st.region == "Meadow" or st.region == "Quarry") then table.insert(baseDigs, st) end
end
do
	local route9 = {}
	for i = 1, 9 do route9[i] = baseDigs[i].id end
	local bot = seeded(9406, function(prof) prof.items[TR.SPADE] = 1; prof.trails.active.Master = {seed = 77, steps = route9, step = 1} end)
	local started = utc
	local attempts = 0
	while true do
		local row = cmd(bot, "state").trails.active.Master
		if not row then break end
		local st = TR.StepById[route9[row.step]]
		standAt(bot, st.anchor, st.east, st.north) -- an instant teleport onto the answer
		attempts += 1
		cmd(bot, "trailDig", "Master")
		assert(attempts < 2000, "bot loop runs away")
	end
	local elapsed = utc - started
	ok(elapsed >= 9 * TR.MIN_STEP_SECONDS.Master, string.format("a teleporting bot needs %ds for a 9-step Master trail (floor %ds)", elapsed, 9 * TR.MIN_STEP_SECONDS.Master))
	ok(attempts > 9, "the bot's early digs were refused (" .. attempts .. " attempts)")
	eq(cmd(bot, "state").items.TrailCasketMaster, 1, "and it still finishes (the walk is only paced)")
	leave(bot)
end
do
	-- The farthest pair of base-region digs: arriving faster than the travel
	-- model allows is refused even after the step's floor; a warp-length wait is enough.
	local function point(st)
		local c = anchorPart(st.anchor).CFrame.Position
		return Vector3.new(c.X + st.east, c.Y, c.Z - st.north)
	end
	local digs = {}
	for _, st in ipairs(TR.Steps) do if st.kind == "dig" and st.region ~= "ShatteredCrown" then table.insert(digs, st) end end
	local fa, fb, far = nil, nil, 0
	for i = 1, #digs do
		for j = i + 1, #digs do
			local d = (point(digs[i]) - point(digs[j])).Magnitude
			if d > far then fa, fb, far = digs[i], digs[j], d end
		end
	end
	ok(far / TR.TRAVEL_SPEED > TR.MIN_STEP_SECONDS.Easy + 2, string.format("a long dig pair exists (%.0f studs, %s to %s)", far, fa.id, fb.id))
	local runner = seeded(9407, function(prof)
		prof.items[TR.SPADE] = 1
		for _, sk in ipairs(Data.SkillOrder) do prof.xp[sk] = X[99] end
		prof.questCompleted = 20
		prof.trails.active.Easy = {seed = 3, steps = {fa.id, fb.id}, step = 1}
	end)
	advance(TR.WARP_SECONDS)
	standAt(runner, fa.anchor, fa.east, fa.north)
	ok(has(cmd(runner, "trailDig", "Easy").message, "buried tin"), "first dig")
	advance(TR.MIN_STEP_SECONDS.Easy)
	standAt(runner, fb.anchor, fb.east, fb.north)
	local fast = cmd(runner, "trailDig", "Easy")
	ok(has(fast.message, "still fresh"), "arriving faster than " .. TR.TRAVEL_SPEED .. " studs/s is refused: " .. tostring(fast.message))
	eq(fast.trails.active.Easy.step, 2, "the step did not complete")
	advance(TR.WARP_SECONDS - TR.MIN_STEP_SECONDS.Easy)
	ok(has(cmd(runner, "trailDig", "Easy").message, "The Easy trail ends"), "after a warp's allowance the dig counts")
	leave(runner)
end
-- Waystone leaves: recall gates, cooldown, velocity.
do
	local hopper = seeded(9408, function(prof) prof.items.TeleScrollMeadow = 3; prof.items.TeleScrollQuarry = 1 end)
	gateVerdict = "You can't travel mid-fight. Catch your breath first."
	local before = hopper.root.Position
	ok(has(cmd(hopper, "trailTeleport", "TeleScrollMeadow").message, "mid-fight"), "the travel gate's refusal is relayed")
	eq(hopper.root.Position, before, "a refused traveller stays put")
	eq(cmd(hopper, "state").items.TeleScrollMeadow, 3, "a refused leaf is kept")
	gateVerdict = "The Observatory holds you. Finish or leave the expedition first."
	ok(has(cmd(hopper, "trailTeleport", "TeleScrollMeadow").message, "Observatory"), "no leaf out of an expedition")
	gateVerdict = 5
	ok(has(cmd(hopper, "trailTeleport", "TeleScrollMeadow").message, "will not carry"), "a malformed gate answer refuses")
	gatePresent = false
	ok(has(cmd(hopper, "trailTeleport", "TeleScrollMeadow").message, "will not carry"), "a missing gate refuses")
	gatePresent, gateVerdict = true, true
	eq(cmd(hopper, "state").items.TeleScrollMeadow, 3, "no leaf spent on refusals")
	hopper.root.AssemblyLinearVelocity = Vector3.new(120, 40, 0)
	local calls = gateCalls
	ok(has(cmd(hopper, "trailTeleport", "TeleScrollMeadow").message, "Meadow Reach"), "an open gate lets the leaf work")
	ok(gateCalls > calls, "the gate was consulted")
	eq(hopper.root.AssemblyLinearVelocity, Vector3.zero, "velocity zeroed on arrival")
	local cool = cmd(hopper, "trailTeleport", "TeleScrollQuarry")
	ok(has(cool.message, "still settling"), "leaves have a cooldown: " .. tostring(cool.message))
	eq(cool.items.TeleScrollQuarry, 1, "the cooling leaf is kept")
	advance(TR.TELEPORT_COOLDOWN)
	ok(has(cmd(hopper, "trailTeleport", "TeleScrollQuarry").message, "Cinder Shelf"), "after the cooldown the next leaf works")
	leave(hopper)
end
-- Anchor lookups: hits stay cached, misses are cached briefly.
do
	local before = islandLookups
	for _ = 1, 50 do eq(trailsApi.anchor("NoSuchAnchor"), nil, "missing anchor") end
	eq(islandLookups - before, 1, "50 lookups of a missing anchor search the world once")
	advance(TR.ANCHOR_MISS_SECONDS + 1)
	trailsApi.anchor("NoSuchAnchor")
	eq(islandLookups - before, 2, "a cached miss expires and is searched again")
	local hit = trailsApi.anchor("Waypoint_Bank")
	ok(hit ~= nil, "a real anchor resolves")
	local mid = islandLookups
	for _ = 1, 20 do trailsApi.anchor("Waypoint_Bank") end
	eq(islandLookups, mid, "a found anchor is never searched again while parented")
end
print("PASS: " .. (checks - partC) .. " Treasure Trails server assertions.")

------------------------------------------------------------------------------
-- Part D: Satchel › Trails.
------------------------------------------------------------------------------
local partD = checks
local H = require("./tools/ui-harness")
local function atlas(size, mutate)
	local snap = H.snapshot({xp = {Combat = X[20]}})
	snap.items[TR.SPADE], snap.items.TrailScrollEasy, snap.items.TrailCasketBeginner = 1, 1, 2
	snap.items.TeleScrollMeadow, snap.items.EmoteScrollBow, snap.items.BannerQuayward = 1, 1, 1
	snap.items.TrailCapWayfarer = 1
	snap.trails = {
		active = {
			Beginner = {step = 1, kind = "riddle", style = "riddle", text = "Riddle: Coins sleep behind my iron door.", hint = "Search for the answer somewhere in Aether Hub.", guide = {"region:Hub"}},
			Medium = {step = 2, kind = "puzzle", style = "puzzle", text = "Puzzle box: Gearwright's Box.", hint = "Slide tiles.", guide = {}, board = "123456708", moves = 4},
			Hard = {step = 3, kind = "emote", style = "emote", text = "Perform the Stir at the guild Hearth.", hint = "Stand close.", guide = {"anchor:Waypoint_Hearth", "region:Hub"}, gesture = "stir", wear = {"BrassHelm"}},
			Elite = {step = 1, kind = "skill", style = "skill", text = "Task: Gather Starmetal Ore x2.", hint = "Progress counts.", guide = {}, need = 2, have = 1},
			Master = {step = 4, kind = "dig", style = "coordinate", text = "Bearing: dig 6 paces north of the Moonpool.", hint = "Bring a spade.", guide = {"anchor:Waypoint_Moonpool", "region:Meadow"}},
		},
		log = {Beginner = {completed = 3, opened = 1}, Easy = {completed = 0, opened = 0}, Medium = {completed = 1, opened = 1}, Hard = {completed = 0, opened = 0},
			Elite = {completed = 0, opened = 0}, Master = {completed = 0, opened = 0}},
		uniques = {TrailCapWayfarer = 1}, emotes = {"WayfarersJig"}, spade = true,
	}
	if mutate then mutate(snap) end
	local ui = H.runAtlas(size, {snapshot = snap})
	H.press(H.find(ui.gui, "AtlasButton"))
	return ui, snap
end
local function open(ui)
	H.press(ui.tabs:FindFirstChild("SatchelButton"))
	H.press(H.find(ui.scroll, "SectionTrails"))
end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui)
	eq(#ui.warnings, 0, "Trails page renders without warnings" .. tag)
	ok(H.find(ui.scroll, "TrailsSummary") ~= nil, "summary card" .. tag)
	for _, id in ipairs(TR.TierOrder) do
		ok(H.find(ui.scroll, "Trail" .. id) ~= nil, id .. " card" .. tag)
		ok(H.find(ui.scroll, "TrailLogGrid" .. id) ~= nil, id .. " clue log grid" .. tag)
		for _, u in ipairs(TR.Uniques[id]) do ok(H.find(ui.scroll, "TrailUnique" .. u) ~= nil, u .. " log tile" .. tag) end
	end
	for i = 1, 9 do ok(H.find(ui.scroll, "TrailTileMedium" .. i) ~= nil, "puzzle tile " .. i .. tag) end
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	open(ui)
	local text = texts(ui.scroll)
	ok(has(text, "Coins sleep behind my iron door"), "riddle text shown")
	ok(has(text, "Aether Hub"), "region hint shown")
	ok(has(text, "1 OF") or has(text, "1 of"), "clue log counts uniques found")
	ok(has(text, "1 / 2"), "task progress bar")
	local function pressSends(name, verb, item)
		local before = #ui.sent
		H.press(H.find(ui.scroll, name))
		ok(#ui.sent > before, name .. " sends")
		eq(ui.sent[#ui.sent][1], verb, name .. " verb")
		eq(ui.sent[#ui.sent][2], item, name .. " payload")
		open(ui)
	end
	pressSends("TrailSearchBeginner", "trailSearch", "Beginner")
	pressSends("TrailBeginEasy", "trailBegin", "Easy")
	pressSends("TrailOpenBeginner", "trailOpen", "Beginner")
	pressSends("TrailDigMaster", "trailDig", "Master")
	pressSends("TrailEmoteHard", "trailEmote", "stir")
	pressSends("TrailCheckElite", "trailCheck", nil)
	pressSends("TrailAbandonHard", "trailAbandon", "Hard")
	pressSends("TrailTeleportTeleScrollMeadow", "trailTeleport", "TeleScrollMeadow")
	pressSends("TrailLearnEmoteScrollBow", "trailLearn", "EmoteScrollBow")
	pressSends("TrailBannerBannerQuayward", "trailBanner", "BannerQuayward")
	ok(H.find(ui.scroll, "TrailPerformWayfarersJig") ~= nil, "learned emote listed")
	ok(H.find(ui.scroll, "TrailGuideMaster") ~= nil, "coordinate steps offer a guide")
	ok(H.find(ui.scroll, "TrailGuideMedium") == nil, "puzzle boxes offer no guide")
	-- Puzzle: board 123456708 (gap at 8): tap tile 9 (right of the gap) -> R solves it.
	local before = #ui.sent
	H.press(H.find(ui.scroll, "TrailTileMedium1"))
	eq(#ui.sent, before, "a tile away from the gap does not move")
	open(ui)
	H.press(H.find(ui.scroll, "TrailTileMedium9"))
	eq(ui.sent[#ui.sent][1], "trailSlide", "solving locally sends the moves")
	eq(ui.sent[#ui.sent][2], "Medium:R", "the move string names the tier and moves")
	for _, entry in ipairs(ui.sent) do ok(entry[2] == nil or (type(entry[2]) == "string" and #entry[2] <= 64), "payload short: " .. entry[1]) end
end
do
	-- Buffered puzzle moves are never lost: they are sent after ~2 s idle, when
	-- the atlas closes and when the page changes.
	local ui = atlas(roblox.Vector2.new(1366, 768))
	open(ui)
	local function slides()
		local n = 0
		for _, entry in ipairs(ui.sent) do if entry[1] == "trailSlide" then n += 1 end end
		return n
	end
	-- Board 123456708 (gap at 8): tile 5 sits above the gap -> "U" (not solved).
	H.press(H.find(ui.scroll, "TrailTileMedium5"))
	eq(slides(), 0, "an unsolved move is buffered")
	ok(#ui.delays >= 1 and ui.delays[#ui.delays].seconds <= 2.5, "an idle flush is scheduled (~2 s)")
	ui.runDelays(2.5)
	eq(slides(), 1, "idle: the buffered move is sent")
	eq(ui.sent[#ui.sent][2], "Medium:U", "idle flush payload")
	-- Two quick moves then idle: one batch (the first timer is stale).
	open(ui)
	H.press(H.find(ui.scroll, "TrailTileMedium5"))
	H.press(H.find(ui.scroll, "TrailTileMedium8"))
	eq(slides(), 1, "quick moves stay buffered")
	ui.runDelays(2.5)
	eq(slides(), 2, "one batch after the last move goes idle")
	eq(ui.sent[#ui.sent][2], "Medium:UD", "the batch holds both moves")
	-- Closing the atlas sends what is buffered.
	open(ui)
	H.press(H.find(ui.scroll, "TrailTileMedium5"))
	ui.atlas.Visible = false
	eq(slides(), 3, "closing the atlas sends the buffered move")
	eq(ui.sent[#ui.sent][2], "Medium:U", "close flush payload")
	ui.runDelays(2.5)
	eq(slides(), 3, "the stale idle timer sends nothing more")
	-- Changing section sends what is buffered.
	ui.atlas.Visible = true
	open(ui)
	H.press(H.find(ui.scroll, "TrailTileMedium5"))
	H.press(H.find(ui.scroll, "SectionItems"))
	eq(slides(), 4, "leaving the Trails page sends the buffered move")
	ui.runDelays(2.5)
	eq(slides(), 4, "nothing is sent twice")
end
do
	-- No spade: the dig button stays local.
	local ui = atlas(roblox.Vector2.new(844, 390), function(snap) snap.trails.spade = false; snap.items[TR.SPADE] = nil end)
	open(ui)
	local before = #ui.sent
	H.press(H.find(ui.scroll, "TrailDigMaster"))
	eq(#ui.sent, before, "digging without a spade is not sent")
	ok(has(texts(ui.scroll), "Forge a Wayfinder's Spade"), "spade tip shown")
	-- Missing trails state renders.
	local bare = atlas(roblox.Vector2.new(730, 303), function(snap) snap.trails = nil end)
	open(bare)
	eq(#bare.warnings, 0, "page renders before trails sync")
	ok(H.find(bare.scroll, "TrailBeginner") ~= nil, "tier cards drawn while syncing")
end
print("PASS: " .. (checks - partD) .. " Treasure Trails page assertions.")
print("PASS: " .. checks .. " Treasure Trails assertions in total.")
print("SUITE-END verify-trails.luau")
