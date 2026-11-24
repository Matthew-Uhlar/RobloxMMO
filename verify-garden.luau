-- Verdant Garden: data rules, world rendering and server behaviour.
-- Part A checks shared/GameData.lua (Data.Garden): content, growth math
-- (offline, watering windows, compost, set and level boosts, the rate cap),
-- disease and pest rules, milestones, garden levels, the composter, visitor
-- generation, sanitising and the bounded save size. Part B runs
-- world.server.lua with real Roblox instances and drives the garden islet
-- through player attributes. Part C runs server.server.lua (deterministic
-- clock, rolls and DataStore doubles) and plays planting, growth, watering,
-- blight, pests, harvest fortune, milestones, the composter, visitors (claim
-- once), the shop, world prompts, the seed pouch, the tick loop and persistence.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local World = luau.load(fs.readFile("art/WorldCatalog.lua"), {injectGlobals = true})()
local G = Data.Garden
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function seq(...)
	local list, i = {...}, 0
	return function() i += 1; return list[i] or 0.999 end
end
local function constant(v) return function() return v end end

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(G) == "table", "Data.Garden exists")
eq(#G.Crops, 8, "eight garden crops")
local cropShapes = {CropWheat = true, CropGlowcap = true, CropBloom = true, CropBush = true}
for i, c in ipairs(G.Crops) do
	eq(c.index, i, c.id .. " index")
	eq(G.CropById[c.id], c, c.id .. " indexed")
	eq(G.CropBySeed[c.seed], c, c.seed .. " indexed by seed")
	local crop, seedDef = Data.Items[c.id], Data.Items[c.seed]
	ok(crop ~= nil and crop.kind == "resource" and crop.skill == "Farming", c.id .. " is a Farming resource")
	ok(seedDef ~= nil and seedDef.category == "seed" and seedDef.crop == c.id, c.seed .. " seed item")
	ok(cropShapes[c.shape] and World.shapes[c.shape] ~= nil, c.id .. " uses an existing crop mesh")
	ok(type(c.tint) == "string" and #c.tint == 6 and Color3.fromHex(c.tint) ~= nil, c.id .. " tint")
	ok(c.grow >= 300 and c.grow <= 14400 and c.yield >= 3 and c.xp > 0 and c.gxp > 0, c.id .. " values")
	ok(c.disease > 0 and c.disease < 0.25 and c.scale > 0 and c.scale <= 1, c.id .. " disease and milestone scale")
	if i > 1 then
		local prev = G.Crops[i - 1]
		ok(c.level > prev.level and c.grow > prev.grow and c.xp > prev.xp and c.gxp > prev.gxp, c.id .. " climbs the ladder")
	end
end
eq(G.Crops[1].level, 1, "first crop at Farming 1")
eq(G.Crops[1].grow, 300, "Meadow Herb grows in 5 minutes")
eq(G.Crops[#G.Crops].grow, 4 * 3600, "Aether Lotus grows in 4 hours")
for _, id in ipairs({"Herb", "Sunwheat", "Glowcap", "Moonbloom", "Starfruit", "AetherLotus"}) do
	ok(G.CropById[id] and Data.ResourceSkill[id] == "Farming", id .. " is also a field crop")
end
ok(Data.ResourceSkill.Duskberry == nil and Data.ResourceSkill.Cloudgourd == nil, "Duskberry and Cloudgourd are garden-only")
for _, id in ipairs({G.MARK, G.DUST, G.COMPOST, G.SALVE, G.CHITIN}) do ok(Data.Items[id] ~= nil and Data.Items[id].kind == "material", id .. " material") end
-- Recipes that use or make garden goods.
local salve = Data.Recipes[G.SALVE]
ok(salve and salve.skill == "Alchemy" and salve.station == "Cauldron" and salve.amount == 2, "Blightward Salve brewed at the Cauldron")
ok(Data.Recipes.DuskberryTart and Data.Recipes.DuskberryTart.skill == "Cooking" and Data.Recipes.DuskberryTart.costs.Duskberry, "Duskberry Tart cooked")
ok(Data.Recipes.CloudgourdBroth and Data.Recipes.CloudgourdBroth.costs.Cloudgourd and Data.Items.CloudgourdBroth.buff.stats.farmingFortune == 40, "Cloudgourd Broth feast")
ok(Data.Recipes.VerdantElixir and Data.Recipes.VerdantElixir.skill == "Alchemy" and Data.Items.VerdantElixir.category == "potion", "Verdant Elixir potion")
for id, r in pairs(Data.Recipes) do
	for item in pairs(r.costs) do ok(Data.Items[item] ~= nil, "recipe " .. id .. " ingredient " .. item) end
end
-- Garden gear.
local hoes = {"SproutwoodHoe", "GreenwardHoe", "EverbloomHoe"}
for i, id in ipairs(hoes) do
	local def = Data.Items[id]
	ok(def and def.kind == "tool" and def.toolKind == "Hoe" and def.slot == "hoe", id .. " is a hoe")
	if i > 1 then
		local prev = Data.Items[hoes[i - 1]]
		ok(def.toolTier > prev.toolTier and def.stats.farmingFortune > prev.stats.farmingFortune and def.requires.Farming > prev.requires.Farming, id .. " outclasses " .. hoes[i - 1])
		eq(G.ShopById[id].upgrade, hoes[i - 1], id .. " upgrades the previous hoe")
	end
end
local set = Data.Sets[G.SET]
ok(set and #set.pieces == 4 and set.bonus.farmingFortune == 40, "Rootwarden set with a bonus")
local slots = {}
for _, id in ipairs(set.pieces) do
	local def = Data.Items[id]
	ok(def.kind == "armor" and def.set == G.SET and def.stats.farmingFortune > 0, id .. " armor piece")
	slots[def.slot] = true
	ok(G.ShopById[id] ~= nil and G.ShopById[id].unique, id .. " sold once at the shop")
end
ok(slots.helmet and slots.chest and slots.legs and slots.boots, "Rootwarden covers every armor slot")
ok(Data.Items.VerdantCharm.kind == "accessory" and Data.Items.VerdantCharm.stats.farmingFortune == 15, "Verdant Charm accessory")
-- Shop.
local shopIds = {}
for i, e in ipairs(G.Shop) do
	ok(shopIds[e.id] == nil, e.id .. " unique shop id")
	shopIds[e.id] = true
	eq(G.ShopById[e.id], e, e.id .. " indexed")
	eq(e.index, i, e.id .. " shop index")
	ok(e.level >= 1 and e.level <= G.MAX_LEVEL, e.id .. " level gate in range")
	for id, n in pairs(e.cost) do ok((id == "coins" or Data.Items[id] ~= nil) and n > 0, e.id .. " cost " .. id) end
	if e.kind == "skin" then ok(G.SkinById[e.skin] ~= nil, e.id .. " skin exists")
	else ok(e.kind == "item" and Data.Items[e.item] ~= nil and e.amount >= 1, e.id .. " item exists") end
end
for _, c in ipairs(G.Crops) do ok(shopIds[c.seed], c.seed .. " sold at the shop") end
ok(G.SkinById.Loam and shopIds.SkinLoam == nil, "Tilled Loam is the free default skin")
for _, s in ipairs(G.Skins) do ok(#s.frame == 6 and #s.soil == 6, s.id .. " skin colours") end
-- Visitors and pests.
local rarityCount = {}
for i, v in ipairs(G.Visitors) do
	eq(G.VisitorById[v.id], v, v.id .. " indexed")
	ok(G.VisitorRarity[v.rarity] ~= nil and v.level >= 1 and v.level <= G.MAX_LEVEL, v.id .. " rarity and level")
	for _, like in ipairs(v.likes) do ok(G.CropById[like] ~= nil, v.id .. " likes " .. like) end
	ok(#v.name > 0 and #v.line > 0 and #v.color == 6, v.id .. " text")
	rarityCount[v.rarity] = (rarityCount[v.rarity] or 0) + 1
end
ok(#G.Visitors >= 10 and rarityCount.Common >= 3 and rarityCount.Legendary >= 1, "ten visitors across every rarity")
for _, p in ipairs(G.Pests) do ok(p.combatXp > 0 and #p.color == 6, p.id .. " pest") end
-- Garden levels.
for i = 2, #G.LEVEL_XP do ok(G.LEVEL_XP[i] > G.LEVEL_XP[i - 1], "level " .. i .. " needs more XP") end
eq(G.level(0), 1, "level 1 at 0 XP")
eq(G.level(59), 1, "level 1 below 60 XP")
eq(G.level(60), 2, "level 2 at 60 XP")
eq(G.level(26999), 14, "level 14 just below the cap")
eq(G.level(27000), 15, "level 15 at 27000 XP")
eq(G.level(1e9), G.MAX_LEVEL, "level capped")
eq(G.level("junk"), 1, "junk XP is level 1")
local l, floor, nextAt = G.progress(200)
ok(l == 3 and floor == 180 and nextAt == 400, "progress at 200 XP")
ok(select(3, G.progress(1e9)) == nil, "no next level at the cap")
-- Plot unlocks.
eq(G.plotCount(1, 1), 3, "three plots to start")
eq(G.plotCount(2, 1), 4, "garden level 2 adds a plot")
eq(G.plotCount(12, 1), 9, "garden levels add six plots")
eq(G.plotCount(1, 15), 4, "Farming 15 adds a plot")
eq(G.plotCount(1, 55), 6, "Farming levels add three plots")
eq(G.plotCount(15, 99), 12, "twelve plots at most")
for gl = 1, G.MAX_LEVEL do
	for fl = 1, 99, 7 do
		local n = G.plotCount(gl, fl)
		ok(n >= 3 and n <= 12 and n >= G.plotCount(math.max(1, gl - 1), fl) and n >= G.plotCount(gl, math.max(1, fl - 7)), "plots monotonic at " .. gl .. "/" .. fl)
	end
end
eq(G.nextPlotUnlock(1, 1), "Garden level 2 or Farming 15", "next unlock text")
eq(G.nextPlotUnlock(12, 1), "Farming 15", "only Farming unlocks left")
eq(G.nextPlotUnlock(15, 99), nil, "nothing left to unlock")
-- Milestones.
eq(G.milestoneThreshold("Herb", 1), 100, "Herb tier 1 at 100")
eq(G.milestoneThreshold("AetherLotus", 1), 25, "Lotus tier 1 scaled to 25")
eq(G.milestoneThreshold("Herb", 10), nil, "nine tiers")
eq(G.milestoneThreshold("Ghost", 1), nil, "unknown crop")
for _, c in ipairs(G.Crops) do
	for t = 2, #G.MILESTONES do ok(G.milestoneThreshold(c.id, t) > G.milestoneThreshold(c.id, t - 1), c.id .. " milestone " .. t .. " ascends") end
	eq(G.milestoneTier(c.id, 0), 0, c.id .. " starts at tier 0")
	eq(G.milestoneTier(c.id, G.milestoneThreshold(c.id, 3)), 3, c.id .. " tier 3 at its threshold")
	eq(G.milestoneTier(c.id, G.milestoneThreshold(c.id, 3) - 1), 2, c.id .. " tier 2 just below")
	eq(G.milestoneTier(c.id, 1e9), #G.MILESTONES, c.id .. " tier capped")
end
eq(G.milestoneReward("Herb", 1).coins, 150, "Herb tier 1 pays 150 coins")
eq(G.milestoneReward("Herb", 3).coins, 1350, "tier rewards grow with the square")
eq(G.milestoneReward("AetherLotus", 1).coins, math.floor(150 * 2.4), "rarer crops pay more")
eq(G.milestoneReward("Herb", 2).gxp, 30, "milestone garden XP")
eq((G.milestonePerk({})), nil, "no milestones, no perk")
local perk, tiers = G.milestonePerk({Herb = 300, AetherLotus = 25})
ok(perk.farmingFortune == 3 and tiers == 3, "milestone fortune sums across crops")
-- Growth rate.
local herb, lotus, moon = G.CropById.Herb, G.CropById.AetherLotus, G.CropById.Moonbloom
eq(G.rate({}, {level = 1}, false), 1, "base rate")
ok(near(G.rate({compost = true}, {level = 1}, false), 1.25), "compost +25%")
ok(near(G.rate({}, {level = 1}, true), 1.2), "water +20%")
ok(near(G.rate({}, {level = 1, set = true}, false), 1.1), "Rootwarden +10%")
ok(near(G.rate({}, {level = 6}, false), 1.05), "garden level +1% per level")
eq(G.rate({compost = true}, {level = 15, set = true}, true), G.MAX_RATE, "rate capped")
ok(near(G.rate({}, {level = 99}, false), 1.14), "level boost clamps at the max level")
-- Planting, advancing and offline growth.
local plot = G.plant({}, "Herb", 1000, constant(0.999))
ok(plot.crop == "Herb" and plot.grown == 0 and plot.at == 1000 and plot.blight == nil, "planted without blight")
eq(G.stage(plot), 1, "stage 1 after planting")
eq(G.timeLeft(plot, 1000, {level = 1}), 300, "300 s to ripen")
G.advance(plot, 1150, {level = 1})
eq(plot.grown, 150, "half grown")
eq(G.stage(plot), 2, "stage 2 at half")
G.advance(plot, 1100, {level = 1})
eq(plot.grown, 150, "time never runs backwards")
G.advance(plot, 1249, {level = 1})
eq(G.stage(plot), 3, "stage 3 before ripe")
ok(not G.ripe(plot), "not ripe at 249 s")
G.advance(plot, 1300, {level = 1})
ok(G.ripe(plot) and G.stage(plot) == 4, "ripe at 300 s")
eq(G.timeLeft(plot, 1300, {level = 1}), 0, "no time left once ripe")
G.advance(plot, 999999, {level = 1})
eq(plot.grown, herb.grow, "offline growth caps at ripe")
local offline = G.plant({}, "AetherLotus", 0, constant(0.999))
G.advance(offline, 100000, {level = 1})
ok(G.ripe(offline), "a whole offline night ripens the lotus")
-- Watering window, inside one offline span.
local wet = G.plant({}, "Moonbloom", 0, constant(0.999))
wet.water = 600
G.advance(wet, 1000, {level = 1})
ok(near(wet.grown, 600 * 1.2 + 400), "watering boosts only until it dries")
wet = G.plant({}, "Moonbloom", 0, constant(0.999))
wet.water = 1800
G.advance(wet, 1800, {level = 1})
ok(near(wet.grown, 2160), "watered half hour")
eq(G.timeLeft(wet, 1800, {level = 1}), 1440, "dry remainder")
wet.water = 3600
eq(G.timeLeft(wet, 1800, {level = 1}), 1200, "re-watered remainder at 1.2x")
-- timeLeft predicts advance for every crop and boost mix.
for _, c in ipairs(G.Crops) do
	for _, mix in ipairs({{}, {compost = true}, {water = true}, {set = true, level = 9}, {compost = true, water = true, set = true, level = 15}}) do
		local pl = G.plant({}, c.id, 0, constant(0.999))
		pl.compost = mix.compost
		if mix.water then pl.water = G.WATER_SECONDS end
		local ctx = {level = mix.level or 1, set = mix.set}
		local left = G.timeLeft(pl, 0, ctx)
		local a = table.clone(pl)
		G.advance(a, left - 1, ctx)
		ok(not G.ripe(a), c.id .. " not ripe a second early")
		G.advance(a, left, ctx)
		ok(G.ripe(a), c.id .. " ripe exactly on time")
	end
end
-- Disease.
ok(near(G.diseaseChance("Herb", false), herb.disease), "base blight chance")
ok(near(G.diseaseChance("Herb", true), herb.disease / 2), "compost halves blight")
eq(G.diseaseChance("Ghost", false), 0, "unknown crop")
local sick = G.plant({}, "Herb", 0, seq(0.01, 0.5))
eq(sick.blight, 0.5, "blight at half growth")
G.advance(sick, 100, {level = 1})
ok(sick.sick == nil and sick.grown == 100, "healthy until the blight point")
G.advance(sick, 200, {level = 1})
ok(sick.sick == 150 and sick.grown == 150, "blight strikes at 150 s and halts growth")
eq(G.timeLeft(sick, 200, {level = 1}), nil, "no timer while blighted")
ok(not G.ripe(sick) and G.stage(sick) == 2, "blighted crop is not ripe")
G.advance(sick, 150 + G.DEATH_SECONDS - 1, {level = 1})
ok(not sick.dead and sick.grown == 150, "still alive just before the death timer")
G.advance(sick, 150 + G.DEATH_SECONDS, {level = 1})
ok(sick.dead, "withers DEATH_SECONDS after the strike")
local lateStrike = G.plant({}, "Herb", 0, seq(0.01, 0.0))
eq(lateStrike.blight, 0.2, "earliest blight point")
G.advance(lateStrike, 99999, {level = 1})
ok(lateStrike.dead, "an offline strike can kill the crop")
local treated = G.plant({treated = true}, "Herb", 0, seq(0.01, 0.5))
eq(treated.blight, nil, "treated plots never roll blight")
local composted = G.plant({compost = true}, "Herb", 0, seq(herb.disease * 0.75, 0.5))
eq(composted.blight, nil, "compost halves the chance")
local raw = G.plant({}, "Herb", 0, seq(herb.disease * 0.75, 0.5))
eq(raw.blight, 0.5, "the same roll blights an uncomposted crop")
raw.treated = true
G.advance(raw, 400, {level = 1})
ok(G.ripe(raw), "treatment before the strike prevents it")
-- Pests.
local bug = G.plant({}, "Herb", 0, constant(0.999))
eq(G.pestRoll(bug, 599, constant(0)), false, "no roll before an interval passes")
eq(bug.pestCheck, 0, "check time kept")
eq(G.pestRoll(bug, 600, seq(0.01, 0.3)), true, "a pest arrives")
eq(bug.pest, 2, "pest picked by roll")
eq(bug.pestCheck, 600, "check time advanced")
eq(G.pestRoll(bug, 6000, constant(0)), false, "one pest at a time")
eq(bug.pestCheck, 6000, "intervals are still consumed")
local calm = G.plant({}, "Herb", 0, constant(0.999))
local calls = 0
G.pestRoll(calm, 100 * G.PEST_INTERVAL, function() calls += 1 return 0.999 end)
eq(calls, G.PEST_MAX_ROLLS, "offline pest rolls are capped")
eq(calm.pestCheck, 100 * G.PEST_INTERVAL, "offline check time catches up")
eq(G.pestRoll({}, 9999, constant(0)), false, "empty plots get no pests")
local deadPlot = G.plant({}, "Herb", 0, constant(0.999))
deadPlot.dead = true
eq(G.pestRoll(deadPlot, 9999, constant(0)), false, "withered crops get no pests")
-- Yield.
eq(G.yieldFor("Herb", 0, false, constant(0.5)), 6, "base yield")
eq(G.yieldFor("Herb", 150, false, constant(0.4)), 18, "fortune 150: double plus a 50% extra")
eq(G.yieldFor("Herb", 150, false, constant(0.6)), 12, "fortune 150 without the extra")
eq(G.yieldFor("Herb", 0, true, constant(0.5)), 3, "a pest cuts 40%")
eq(G.yieldFor("AetherLotus", 0, true, constant(0.5)), math.floor(22 * 0.6), "pest cut on the top crop")
-- L4: the mastery yield multiplier joins the base before fortune (field parity).
eq(G.yieldFor("Herb", 0, false, constant(0.5), 2), 12, "a Twin yield proc doubles the base")
eq(G.yieldFor("Herb", 150, false, constant(0.4), 2), 36, "mastery x2 then fortune 150 with the extra")
eq(G.yieldFor("Herb", 150, false, constant(0.6), 3), 36, "Bountiful x3 then fortune 150 without the extra")
eq(G.yieldFor("Herb", 0, true, constant(0.5), 2), 7, "pests cut the multiplied yield")
eq(G.yieldFor("Herb", 0, false, constant(0.5), "junk"), 6, "a junk multiplier is ignored")
-- M1: seeds are a consumable, never a loop. One seed on an 80% roll (plus a
-- small second chance for garden-only crops); seeds sell for a sliver of the crop.
eq(G.seedReturn("Herb", constant(0.79)), 1, "a seed saved under the return chance")
eq(G.seedReturn("Herb", constant(0.81)), 0, "no seed over the return chance")
eq(G.seedReturn("Herb", constant(0.0)), 1, "field crops never save two")
eq(G.seedReturn("Duskberry", constant(0.05)), 2, "garden-only crops may save a second seed")
eq(G.seedReturn("Ghost", constant(0)), 0, "unknown crop saves nothing")
do
	local state = 12345
	local function lcg() state = (state * 1103515245 + 12345) % 2147483648; return state / 2147483648 end
	for _, c in ipairs(G.Crops) do
		ok(c.exclusive == (Data.ResourceSkill[c.id] == nil), c.id .. " exclusive flag")
		local expected = G.expectedSeeds(c)
		ok(expected < 1 and expected <= 0.9, c.id .. " expects under one seed back per planting (" .. expected .. ")")
		-- Simulated balance: plant one seed per harvest, no pests or pouch.
		local balance, harvests = 0, 20000
		for _ = 1, harvests do balance += G.seedReturn(c, lcg) - 1 end
		local net = 1 + balance / harvests
		ok(net <= 0.92 and net >= 0.75, c.id .. " net seeds per planting " .. string.format("%.3f", net))
		ok(balance < 0, c.id .. " seed stock drains without pests, pouch or shop")
		local seedValue, cropValue = Data.Items[c.seed].value, Data.Items[c.id].value
		ok(seedValue >= 0 and seedValue <= 0.25 * cropValue, c.seed .. " sells for at most a quarter of the crop (" .. seedValue .. " vs " .. cropValue .. ")")
		ok(expected * seedValue < 0.25 * cropValue * c.yield, c.id .. " saved seeds are not a coin source")
	end
end
-- M2: the crop ladder climbs. XP per grow-second and coins per plot-hour rise
-- >= 1.1x per tier; every plot on the top crop at the rate cap stays under
-- top field Farming XP/h (per-player regrowth-limited).
do
	local top = Data.ResourceTiers.Farming[#Data.ResourceTiers.Farming]
	local fieldXpPerHour = top.xp * 3600 / top.respawn
	for i = 2, #G.Crops do
		local c, prev = G.Crops[i], G.Crops[i - 1]
		ok(G.xpPerSecond(c) >= 1.1 * G.xpPerSecond(prev), c.id .. " XP per grow-second >= 1.1x " .. prev.id
			.. string.format(" (%.4f vs %.4f)", G.xpPerSecond(c), G.xpPerSecond(prev)))
		ok(G.coinsPerHour(c) >= 1.1 * G.coinsPerHour(prev), c.id .. " coins per plot-hour >= 1.1x " .. prev.id
			.. string.format(" (%.1f vs %.1f)", G.coinsPerHour(c), G.coinsPerHour(prev)))
	end
	local last = G.Crops[#G.Crops]
	local gardenXpPerHour = G.xpPerSecond(last) * 3600 * G.MAX_PLOTS * G.MAX_RATE
	ok(gardenXpPerHour <= fieldXpPerHour, string.format("top garden XP/h %.0f (all plots, max rate) <= top field Farming XP/h %.0f", gardenXpPerHour, fieldXpPerHour))
	ok(G.xpPerSecond(G.Crops[1]) * 3600 * G.MAX_PLOTS * G.MAX_RATE <= Data.ResourceTiers.Farming[1].xp * 3600 / Data.ResourceTiers.Farming[1].respawn,
		"the first garden crop stays under first field crop XP/h")
	-- Shop seeds are listed cheapest first (G.autoSeed relies on the order).
	for i = 2, #G.Crops do
		local a, b = G.ShopById[G.Crops[i - 1].seed], G.ShopById[G.Crops[i].seed]
		ok(a.cost.coins / a.amount < b.cost.coins / b.amount, G.Crops[i].seed .. " costs more than " .. G.Crops[i - 1].seed)
	end
end
-- L2: the contextual plant uses the last chosen seed, else the cheapest owned
-- seed that is not bought with Verdant Marks.
ok(G.MarkSeeds.MoonbloomBulb and G.MarkSeeds.LotusBud and not G.MarkSeeds.MeadowSeeds and not G.MarkSeeds.GlowcapSpores, "Mark-bought seeds flagged")
eq(G.autoSeed({MeadowSeeds = 2, SunwheatSeeds = 3}, 99, nil).id, "Herb", "cheapest owned seed by default")
eq(G.autoSeed({MeadowSeeds = 2, SunwheatSeeds = 3}, 99, "SunwheatSeeds").id, "Sunwheat", "last chosen seed first")
eq(G.autoSeed({MeadowSeeds = 2, SunwheatSeeds = 0}, 99, "SunwheatSeeds").id, "Herb", "out of the last seed: cheapest owned")
eq(G.autoSeed({SunwheatSeeds = 3}, 10, nil), nil, "level-gated seeds are skipped")
eq(G.autoSeed({LotusBud = 1}, 99, nil), nil, "Mark seeds never auto-planted")
eq(G.autoSeed({LotusBud = 1, MeadowSeeds = 1}, 99, nil).id, "Herb", "cheap seed over an unchosen Mark seed")
eq(G.autoSeed({LotusBud = 1, MeadowSeeds = 1}, 99, "LotusBud").id, "AetherLotus", "a chosen Mark seed is replanted")
eq(G.autoSeed({LotusBud = 1}, 60, "LotusBud"), nil, "chosen seed still level-gated")
eq(G.autoSeed("junk", 99, 7), nil, "junk inputs")
eq(G.yieldFor("Ghost", 500, false, constant(0)), 0, "unknown crop yields nothing")
-- Composter.
eq(G.composterInterval(0), 600, "base compost interval")
eq(G.composterInterval(5), 240, "fully upgraded interval")
eq(G.composterInterval(99), 240, "upgrade clamps")
eq(G.matterCap(2), 7000, "matter cap grows")
eq(G.organic("Herb"), 2, "herb matter")
eq(G.organic("AetherLotus"), Data.Items.AetherLotus.value, "lotus matter")
eq(G.organic("PestChitin"), 12, "chitin matter")
eq(G.organic("Ore"), 0, "ore is not organic")
eq(G.organic("MeadowSeeds"), 0, "seeds are not compost")
local bin = {matter = 600, out = 0, dust = 0, cycles = 0, at = 0, upgrade = 0}
eq(G.composterAdvance(bin, 1799), 2, "two cycles by 1799 s")
eq(bin.at, 1200, "partial cycle time is banked")
eq(G.composterAdvance(bin, 2400), 2, "two more cycles")
ok(bin.out == 4 and bin.matter == 360 and bin.dust == 1 and bin.cycles == 4, "fourth compost leaves Bloom Dust")
local starved = {matter = 30, out = 0, dust = 0, cycles = 0, at = 0, upgrade = 0}
eq(G.composterAdvance(starved, 6000), 0, "no matter, no compost")
eq(starved.at, 6000, "idle time is not banked")
local full = {matter = 6000, out = 63, dust = 0, cycles = 3, at = 0, upgrade = 0}
eq(G.composterAdvance(full, 60000), 1, "output cap stops production")
ok(full.out == G.COMPOST_OUT_CAP and full.at == 60000, "full output idles")
local fast = {matter = 6000, out = 0, dust = 0, cycles = 0, at = 0, upgrade = 5}
eq(G.composterAdvance(fast, 2400), 10, "upgraded composter is faster")
-- Visitors.
eq(G.visitorCap(1), 2, "two visitors at level 1")
eq(G.visitorCap(5), 3, "three at level 5")
eq(G.visitorCap(15), G.MAX_VISITORS, "five at most")
local n, nxt = G.visitorsDue(100, 99, 0, 2)
ok(n == 0 and nxt == 100, "nobody before the arrival time")
n, nxt = G.visitorsDue(100, 100, 0, 2)
ok(n == 1 and nxt == 1000, "one arrival")
n, nxt = G.visitorsDue(0, 1000, 1, 5)
ok(n == 2 and nxt == 1800, "a backlog arrives together")
n, nxt = G.visitorsDue(0, 100000, 0, 2)
ok(n == 2 and nxt == 100000 + G.VISITOR_INTERVAL, "offline arrivals stop at the cap")
n, nxt = G.visitorsDue(0, 100000, 2, 2)
ok(n == 0 and nxt == 100000 + G.VISITOR_INTERVAL, "a full bench never banks time")
local v = G.makeVisitor(1, 1, 99, constant(0))
ok(v.npc == "Pell" and v.id == 1, "lowest roll picks the first visitor")
eq(v.wants.Herb, 9, "liked crop, smallest request")
eq(v.coins, 2 * 9 * 2, "coins: twice the crop value")
ok(v.marks == 2 and v.gxp == 9 and v.xp == math.floor(50 * 9 / 6 * 0.25), "marks, garden XP and Farming XP")
eq(next(v.items), nil, "commons bring no items")
local top = G.makeVisitor(2, 15, 99, constant(0.999))
eq(top.npc, "Auralie", "highest roll at level 15 picks the legendary")
local legendaryItems = G.makeVisitor(3, 15, 99, seq(0.999, 0.1, 0.1, 0.5, 0.5, 0.1, 0.5, 0.5, 0.1, 0.1, 0.05))
ok(legendaryItems.npc == "Auralie" and legendaryItems.items.BloomDust == 3 and legendaryItems.items.MossbackPet == 1, "legendary rewards: dust and a pet")
local farmer1 = G.makeVisitor(4, 15, 1, constant(0.5))
for id in pairs(farmer1.wants) do eq(id, "Herb", "Farming 1 visitors only want Meadow Herb") end
for i = 1, 400 do
	local lvl = (i % G.MAX_LEVEL) + 1
	local fl = (i * 7) % 99 + 1
	local r = G.makeVisitor(i, lvl, fl, function() return math.random() end)
	local def = G.VisitorById[r.npc]
	local wants = 0
	for id, count in pairs(r.wants) do
		wants += 1
		assert(G.CropById[id].level <= fl and count >= 2, "visitor wants a reachable crop")
	end
	assert(def.level <= lvl and wants >= 1 and wants <= 2 and #r.order == wants and r.coins > 0 and r.marks >= 2, "visitor " .. i .. " valid")
	for id in pairs(r.items) do assert(Data.Items[id] ~= nil, "visitor reward item") end
end
checks += 1
-- Fresh record and sanitising.
local fresh = G.fresh(5000)
ok(#fresh.plots == 12 and fresh.xp == 0 and fresh.skin == "Loam" and fresh.skins.Loam and fresh.nextVisitor == 5060, "fresh record")
local clean = G.sanitize(nil, 5000)
eq(#clean.plots, 12, "missing record becomes fresh")
local junkVisitors = {}
for i = 1, 9 do table.insert(junkVisitors, {id = i, npc = "Pell", wants = {Herb = 3, Ghost = 2}, coins = 5, marks = 2, gxp = 1, xp = 1, items = {Nope = 1, BloomDust = 1}}) end
table.insert(junkVisitors, 1, {id = 77, npc = "Nobody", wants = {Herb = 1}})
local dirty = G.sanitize({xp = -50, plots = {{crop = "Ghost", grown = 5}, {crop = "Herb", grown = 1e9, at = 1e12, pest = 9.7, water = 1e12, blight = 7, sick = -4}, "x", {compost = "yes", treated = true}},
	harvested = {Herb = 120, Ghost = 9, Sunwheat = -3}, milestones = {Herb = 99}, composter = {matter = 1e9, out = -2, upgrade = 99, at = 1e12},
	visitors = junkVisitors, seq = 2, nextVisitor = 1e12, skin = "Hacker", skins = {Starlit = true, Gold = true}}, 5000)
eq(dirty.xp, 0, "negative XP clamped")
eq(dirty.plots[1].crop, nil, "unknown crop dropped")
ok(dirty.plots[2].grown == herb.grow and dirty.plots[2].at == 5000, "growth and time clamped")
ok(dirty.plots[2].pest == 4 and dirty.plots[2].water == 5000 + G.WATER_SECONDS and dirty.plots[2].blight == 0.95 and dirty.plots[2].sick == 0, "plot fields clamped")
ok(dirty.plots[3].crop == nil and dirty.plots[4].treated == true and dirty.plots[4].compost == nil, "flags must be true")
ok(dirty.harvested.Herb == 120 and dirty.harvested.Ghost == nil and dirty.harvested.Sunwheat == 0, "harvest counts cleaned")
eq(dirty.milestones.Herb, #G.MILESTONES, "milestone tier clamped")
ok(dirty.composter.upgrade == 5 and dirty.composter.matter == G.matterCap(5) and dirty.composter.out == 0 and dirty.composter.at == 5000, "composter clamped")
eq(#dirty.visitors, G.MAX_VISITORS, "visitor list bounded")
ok(dirty.visitors[1].npc == "Pell" and dirty.visitors[1].wants.Ghost == nil and dirty.visitors[1].items.Nope == nil, "visitor entries cleaned")
eq(dirty.seq, 5, "sequence never reuses a visitor id")
eq(dirty.nextVisitor, 5000 + G.VISITOR_INTERVAL, "arrival clamped")
ok(dirty.skin == "Loam" and dirty.skins.Starlit and dirty.skins.Gold == nil, "skins cleaned")
eq(dirty.lastSeed, nil, "no last seed by default")
eq(G.sanitize({lastSeed = "LotusBud"}, 5000).lastSeed, "LotusBud", "last chosen seed kept")
eq(G.sanitize({lastSeed = "Ore"}, 5000).lastSeed, nil, "a non-seed last seed is dropped")
-- Worst-case save size stays small (DataStore profile budget).
do
	local big = G.fresh(2e9)
	big.xp = 999999999
	for i = 1, 12 do
		big.plots[i] = {crop = "AetherLotus", planted = 1999999999, at = 1999999999, grown = 14399.999999, water = 1999999999, blight = 0.123, sick = 1999999999,
			dead = true, pest = 4, pestCheck = 1999999999, compost = true, treated = true}
	end
	for _, c in ipairs(G.Crops) do big.harvested[c.id] = 999999999; big.milestones[c.id] = 9; big.fieldSeeds[c.id] = 999999999 end
	for i = 1, G.MAX_VISITORS do
		table.insert(big.visitors, {id = 999999990 + i, npc = "Auralie", wants = {AetherLotus = 9999, Starfruit = 9999}, order = {"Starfruit", "AetherLotus"},
			coins = 9999999, marks = 99, gxp = 99999, xp = 999999, items = {BloomDust = 99, LotusBud = 99, MossbackPet = 1}})
	end
	for _, s in ipairs(G.Skins) do big.skins[s.id] = true end
	big.lastSeed = "CloudgourdSeeds"
	big.composter = {matter = 11500, out = 64, dust = 999999, cycles = 999999999, at = 1999999999, upgrade = 5}
	local bytes = #serde.encode("json", big)
	ok(bytes < 4500, "worst-case garden record is small (" .. bytes .. " bytes)")
	local again = G.sanitize(serde.decode("json", serde.encode("json", big)), 2e9)
	eq(#again.visitors, G.MAX_VISITORS, "a JSON round trip keeps the record")
end
print("PASS: " .. (checks - partA) .. " Verdant Garden data/rule assertions.")

------------------------------------------------------------------------------
-- Part B: world rendering (real instances).
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
local worldPlayers = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local worldEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return worldPlayers end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function() end, RemoveTag = function() end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = Color3,
	UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local worldSource = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
luau.load(worldSource, {environment = worldEnv, injectGlobals = true})()
local archipelago = world:FindFirstChild("AetherIsles")
local function homeOwner(id, attributes)
	local changed = {}
	local p = {UserId = id, CharacterAdded = signal(), attributes = attributes or {}}
	function p:GetAttribute(key) return self.attributes[key] end
	function p:GetAttributeChangedSignal(key)
		changed[key] = changed[key] or signal()
		return changed[key]
	end
	function p:SetAttribute(key, value)
		self.attributes[key] = value
		self:GetAttributeChangedSignal(key):Fire()
	end
	worldPlayers.PlayerAdded:Fire(p)
	return p
end
local owner = homeOwner(31)
local home = archipelago:FindFirstChild("WayfarersRest_31")
ok(home ~= nil, "home built")
local garden = home:FindFirstChild("Verdant Garden")
ok(garden ~= nil and garden:IsA("Model"), "home gains a Verdant Garden islet")
eq(garden:GetAttribute("GardenOwner"), 31, "islet tagged with its owner")
eq(garden:GetAttribute("IslandRadius"), 14, "islet radius attribute")
eq(garden:GetAttribute("Region"), "Home", "islet region attribute")
local homeCenter = home:FindFirstChild("Meadow").CFrame.Position + Vector3.new(0, .25, 0)
local gc = garden:GetAttribute("IslandCenter")
local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
ok(near(flat(gc, homeCenter), math.sqrt(2) * 40, 0.05), "garden sits in its north-west district, ~57 studs out (§40 spread)")
ok(flat(gc, homeCenter) - 14 > 21 + 3, "islet clears the home meadow")
local terraceCenter = homeCenter + Vector3.new(Data.TERRACE_OFFSET.x, 0, Data.TERRACE_OFFSET.z)
ok(flat(gc, terraceCenter) > 14 + 11 + 2, "islet clears the Builder's Terrace")
ok(flat(gc, homeCenter + Vector3.new(0, 0, 46)) > 14 + 7 + 2, "islet clears the lookout deck")
ok(flat(gc, homeCenter) + 14 < Data.Home.radius(1), "garden stands inside the stage-0 build radius (§27)")
local plotPrompts, plotBeds = {}, {}
for _, obj in garden:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") == "gardenPlot" then
		local i = tonumber(obj:GetAttribute("IsleItem"))
		ok(i and plotPrompts[i] == nil, "plot prompt index unique")
		plotPrompts[i] = obj
		eq(obj:GetAttribute("OwnerUserId"), 31, "plot prompt owned")
		ok(near(obj.HoldDuration, 0.36) and obj.MaxActivationDistance == 9, "plot prompt uses the interact hold")
	end
end
for i = 1, G.MAX_PLOTS do
	ok(plotPrompts[i] ~= nil, "plot " .. i .. " prompt")
	local bed = garden:FindFirstChild("Plot" .. i)
	plotBeds[i] = bed
	ok(bed and bed:GetAttribute("GardenPlot") == i, "plot " .. i .. " model")
	local frame = bed:FindFirstChild("Plot frame")
	local pos = frame.CFrame.Position
	ok(flat(pos, gc) + 2.83 <= 14 - .5, "plot " .. i .. " stays on the islet")
	ok(near(pos.Y, gc.Y + .18, .01), "plot " .. i .. " rests on the meadow")
	eq(plotPrompts[i].Enabled, i <= G.BASE_PLOTS, "plot " .. i .. " starts " .. (if i <= 3 then "open" else "locked"))
end
for i = 1, G.MAX_PLOTS do
	for j = i + 1, G.MAX_PLOTS do
		local a, b = plotBeds[i]:FindFirstChild("Plot frame").CFrame.Position, plotBeds[j]:FindFirstChild("Plot frame").CFrame.Position
		assert(flat(a, b) >= 4.3, "plot beds never overlap")
	end
end
checks += 1
local composter = garden:FindFirstChild("Composter barrel", true)
ok(composter and composter:IsA("BasePart") and composter:GetAttribute("Shape") == "Barrel" and World.shapes.Barrel ~= nil, "composter is a Barrel mesh slot")
local binPrompt = composter:FindFirstChildOfClass("ProximityPrompt")
ok(binPrompt and binPrompt:GetAttribute("IsleAction") == "gardenOpen" and binPrompt:GetAttribute("OwnerUserId") == 31, "composter prompt opens the ledger")
ok(garden:FindFirstChild("Sign Verdant Garden") ~= nil, "garden ledger sign")
for _, name in ipairs({"Anchor_Waypoint_VerdantGarden", "Anchor_Garden_Composter", "Anchor_NPC_GardenVisitor"}) do
	local a = home:FindFirstChild(name, true)
	ok(a ~= nil and flat(a.CFrame.Position, gc) < 14, name .. " on the islet")
end
-- §27: the garden is a lawn on the big home island; no bridge is needed.
local lawn = garden:FindFirstChild("Meadow")
ok(lawn ~= nil and lawn.CanCollide and near(lawn.CFrame.Position.Y + lawn.Size.X / 2, homeCenter.Y + .04, .01), "garden lawn sits just above the home meadow")
local gardenZone
for _, c in ipairs(Data.Island.ProtectedCircles) do if c.name == "Verdant Garden" then gardenZone = c end end
ok(gardenZone and near(gardenZone.x, gc.X - homeCenter.X, .01) and near(gardenZone.z, gc.Z - homeCenter.Z, .01) and gardenZone.r >= 14, "the garden is a protected zone of the placement grid")
local function partCount(root)
	local count = 0
	for _, obj in root:GetDescendants() do if obj:IsA("BasePart") then count += 1 end end
	return count
end
local baseParts = partCount(garden)
-- World Art (§30): forged hull + 4-part bridge spans dropped the islet from ~60 to ~36 parts.
ok(baseParts >= 25 and baseParts <= 90, "garden islet part budget (" .. baseParts .. " parts)")
for _, obj in garden:GetDescendants() do if obj:IsA("BasePart") then assert(obj.Anchored, "garden parts anchored") end end
checks += 1
-- Solid garden geometry never intersects solid home geometry (floors excluded).
do
	local FLOOR = {Meadow = true, ["Floating foundation"] = true, ["Continuous bridge deck"] = true, ["Bridge guard"] = true}
	local function box(obj)
		local cf, s = obj.CFrame, obj.Size
		local function ext(axis) return math.abs(cf.RightVector[axis]) * s.X / 2 + math.abs(cf.UpVector[axis]) * s.Y / 2 + math.abs(cf.LookVector[axis]) * s.Z / 2 end
		local p = cf.Position
		return {p.X - ext("X"), p.X + ext("X"), p.Y - ext("Y"), p.Y + ext("Y"), p.Z - ext("Z"), p.Z + ext("Z")}
	end
	local mine, others = {}, {}
	for _, obj in home:GetDescendants() do
		if obj:IsA("BasePart") and obj.CanCollide and not FLOOR[obj.Name] and not string.find(obj.Name, "^Anchor_") then
			if obj:IsDescendantOf(garden) then table.insert(mine, box(obj)) else table.insert(others, box(obj)) end
		end
	end
	local hits = 0
	for _, A in mine do
		for _, B in others do
			if A[1] < B[2] - .3 and B[1] < A[2] - .3 and A[3] < B[4] - .3 and B[3] < A[4] - .3 and A[5] < B[6] - .3 and B[5] < A[6] - .3 then hits += 1 end
		end
	end
	eq(hits, 0, "solid garden geometry clears the home")
end
-- Attributes drive the plots.
local function bed(i) return garden:FindFirstChild("Plot" .. i) end
local function crop(i) return bed(i):FindFirstChild("Crop") end
owner:SetAttribute("GardenPlots", 5)
ok(plotPrompts[4].Enabled and plotPrompts[5].Enabled and not plotPrompts[6].Enabled, "unlocked plots open their prompts")
eq(plotPrompts[6].ActionText, "Locked", "locked plot prompt text")
eq(plotPrompts[1].ActionText, "Plant", "empty plot offers Plant")
owner:SetAttribute("GardenPlot1", "Herb:2:w")
local c1 = crop(1)
local c1Height = c1.Size.Y
ok(c1 ~= nil and c1:GetAttribute("Shape") == "CropBush" and c1:GetAttribute("ShapeScale") == G.STAGE_SCALE[2], "growing crop mesh slot at its stage scale")
eq(c1:GetAttribute("Tint"), Color3.fromHex(herb.tint), "crop tint")
eq(c1:GetAttribute("GardenStatus"), "growing", "growing status")
eq(plotPrompts[1].ActionText, "Water", "growing plot offers Water")
ok(has(plotPrompts[1].ObjectText, "Meadow Herb") and has(plotPrompts[1].ObjectText, "Growing"), "prompt names crop and stage")
local soilWet = bed(1):FindFirstChild("Plot soil").Color
owner:SetAttribute("GardenPlot1", "Herb:2:")
ok(bed(1):FindFirstChild("Plot soil").Color ~= soilWet, "watered soil darkens")
eq(crop(1), c1, "same stage keeps the crop part")
owner:SetAttribute("GardenPlot1", "Herb:3:c")
ok(crop(1) ~= c1 and crop(1):GetAttribute("ShapeScale") == G.STAGE_SCALE[3], "a new stage rebuilds the crop")
eq(bed(1):FindFirstChild("Plot soil").Material, roblox.Enum.Material.Mud, "composted soil")
ok(crop(1).Size.Y > c1Height, "fallback primitive grows with the stage")
owner:SetAttribute("GardenPlot1", "Herb:4:r")
ok(crop(1):GetAttribute("ShapeScale") == 1 and crop(1):GetAttribute("GardenStatus") == "ripe", "ripe crop at full size")
ok(bed(1):FindFirstChild("Ripe glint") ~= nil, "ripe glint")
-- §42 (owner decision): a ripe plot is struck with the hoe, never prompted.
do
	local soil = bed(1):FindFirstChild("Plot soil")
	ok(plotPrompts[1].Enabled == false, "§42: a ripe plot's prompt is off (no hold to harvest)")
	ok(soil:GetAttribute("GatherNode") == "Herb" and soil:GetAttribute("StrikeKind") == "garden" and soil:GetAttribute("GardenHarvest") == 1
		and soil:GetAttribute("OwnerUserId") == owner.UserId, "§42: the ripe plot's soil is the owner's garden strike node")
	ok(has(soil:GetAttribute("NodeName"), "Plot 1") and has(soil:GetAttribute("NodeName"), "Meadow Herb"), "§42: the node names its plot and crop")
end
owner:SetAttribute("GardenPlot1", "Herb:2:s")
ok(crop(1):GetAttribute("GardenStatus") == "sick" and crop(1):GetAttribute("Tint") ~= Color3.fromHex(herb.tint), "blight browns the crop")
ok(bed(1):FindFirstChild("Ripe glint") == nil and plotPrompts[1].ActionText == "Treat", "blighted plot offers Treat")
ok(plotPrompts[1].Enabled and bed(1):FindFirstChild("Plot soil"):GetAttribute("GatherNode") == nil and bed(1):FindFirstChild("Plot soil"):GetAttribute("StrikeKind") == nil,
	"§42: an unripe plot is a prompt again, not a node")
owner:SetAttribute("GardenPlot1", "Herb:2:x")
ok(crop(1):GetAttribute("GardenStatus") == "dead" and plotPrompts[1].ActionText == "Clear", "withered crop offers Clear")
owner:SetAttribute("GardenPlot1", "Herb:2:p2")
local pest = bed(1):FindFirstChild("Pest")
ok(pest ~= nil and pest:GetAttribute("PestId") == "Rootgrub" and plotPrompts[1].ActionText == "Swat pest", "pest shown and swattable")
owner:SetAttribute("GardenPlot1", "Herb:2:p2w")
eq(bed(1):FindFirstChild("Pest"), pest, "same pest keeps its part")
owner:SetAttribute("GardenPlot1", "Herb:2:")
eq(bed(1):FindFirstChild("Pest"), nil, "swatted pest removed")
owner:SetAttribute("GardenPlot1", "")
ok(crop(1) == nil and plotPrompts[1].ActionText == "Plant", "harvested plot is empty")
owner:SetAttribute("GardenPlot1", "nonsense")
ok(crop(1) == nil, "garbage codes render as empty")
owner:SetAttribute("GardenPlot1", "Ghost:3:")
ok(crop(1) == nil, "unknown crops render as empty")
for _, c in ipairs(G.Crops) do
	owner:SetAttribute("GardenPlot2", c.id .. ":4:r")
	ok(crop(2):GetAttribute("Shape") == c.shape and crop(2):GetAttribute("Tint") == Color3.fromHex(c.tint), c.id .. " uses its crop mesh and tint")
end
owner:SetAttribute("GardenPlot9", "Herb:4:r")
eq(crop(9), nil, "a locked plot renders nothing")
-- Skins.
owner:SetAttribute("GardenSkin", "Starlit")
eq(bed(1):FindFirstChild("Plot frame").Color, Color3.fromHex(G.SkinById.Starlit.frame), "skin recolours frames")
eq(bed(1):FindFirstChild("Plot soil").Color, Color3.fromHex(G.SkinById.Starlit.soil), "skin recolours soil")
owner:SetAttribute("GardenSkin", "Hacker")
eq(bed(1):FindFirstChild("Plot frame").Color, Color3.fromHex(G.SkinById.Loam.frame), "unknown skin falls back to Loam")
-- Composter states.
owner:SetAttribute("GardenComposter", "locked")
ok(has(binPrompt.ActionText, "garden level"), "locked composter explains the gate")
owner:SetAttribute("GardenComposter", "ready")
eq(binPrompt.ActionText, "Collect compost", "ready composter")
owner:SetAttribute("GardenComposter", "working")
eq(binPrompt.ActionText, "Open composter", "working composter")
-- Visitors.
local function visitors()
	local list = {}
	for _, obj in garden:GetChildren() do if obj:GetAttribute("GardenVisitor") then table.insert(list, obj) end end
	return list
end
eq(#visitors(), 0, "no visitors at first")
owner:SetAttribute("GardenVisitors", "Pell,Corvel")
eq(#visitors(), 2, "two visitor figures")
local talk = visitors()[1]:FindFirstChild("Visitor coat"):FindFirstChildOfClass("ProximityPrompt")
ok(talk and talk:GetAttribute("IsleAction") == "gardenOpen" and talk.ActionText == "Talk", "visitors can be talked to")
owner:SetAttribute("GardenVisitors", "Ghost,Pell")
ok(#visitors() == 1 and visitors()[1]:GetAttribute("GardenVisitor") == "Pell", "unknown visitors ignored")
owner:SetAttribute("GardenVisitors", "Pell,Odessa,Bramwick,Tamsin,Corvel,Mirabel,Gideon")
eq(#visitors(), 5, "at most five figures")
for _, fig in visitors() do
	local coat = fig:FindFirstChild("Visitor coat")
	ok(flat(coat.CFrame.Position, gc) + 1 < 14, fig.Name .. " stands on the islet")
end
-- Opening the ledger (owner only).
local strangerVisit = homeOwner(32)
promptSignals[binPrompt]:Fire(strangerVisit)
eq(strangerVisit:GetAttribute("IsleStation"), nil, "strangers cannot open another's ledger")
promptSignals[binPrompt]:Fire(owner)
ok(owner:GetAttribute("IsleStation") == "Garden" and owner:GetAttribute("IsleStationVisit") == 1, "composter opens Workshop › Garden")
promptSignals[talk]:Fire(owner)
eq(owner:GetAttribute("IsleStationVisit"), 2, "visitors open the ledger too")
-- Fully dressed garden stays within budget.
owner:SetAttribute("GardenPlots", 12)
for i = 1, 12 do owner:SetAttribute("GardenPlot" .. i, "AetherLotus:4:rp" .. ((i % 4) + 1)) end
local fullParts = partCount(garden)
ok(fullParts <= baseParts + 12 * 3 + 10 and fullParts <= 130, "a full garden stays within budget (" .. fullParts .. " parts)")
-- Every crop part is a contract mesh slot.
for i = 1, 12 do
	local cp = crop(i)
	ok(cp and World.shapes[cp:GetAttribute("Shape")] ~= nil and typeof(cp:GetAttribute("Tint")) == "Color3" and not cp.CanCollide, "plot " .. i .. " crop mesh slot")
end
-- Gardens are per player and leave with the home.
local other = archipelago:FindFirstChild("WayfarersRest_32"):FindFirstChild("Verdant Garden")
ok(other ~= nil and other ~= garden and other:GetAttribute("GardenOwner") == 32, "each home has its own garden")
ok(other:FindFirstChild("Plot1"):FindFirstChild("Crop") == nil, "another player's plots are untouched")
worldPlayers.PlayerRemoving:Fire(strangerVisit)
ok(archipelago:FindFirstChild("WayfarersRest_32") == nil and other.Parent == nil, "leaving removes the garden")
print("PASS: " .. (checks - partB) .. " Verdant Garden world assertions (" .. baseParts .. " base parts, " .. fullParts .. " fully dressed).")

------------------------------------------------------------------------------
-- Part C: server behaviour.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, val in value do out[k] = copy(val) end
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
local function queue(...) for _, r in ipairs({...}) do table.insert(rolls, r) end end
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "garden-test" end},
	RunService = {IsStudio = function() return false end},
}
local coroutines, yieldOf = {}, {}
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
			local okRun, err = coroutine.resume(co, ...)
			assert(okRun, err)
			if coroutine.status(co) == "suspended" then table.insert(coroutines, co) end
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) yieldOf[coroutine.running()] = t return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local ticker
for _, co in ipairs(coroutines) do if yieldOf[co] == G.TICK then ok(ticker == nil, "one garden loop") ticker = co end end
ok(ticker ~= nil, "garden loop runs every G.TICK seconds")
-- Leases last 180 s and are renewed by the autosave loop; tests jump hours ahead,
-- so every command first runs one autosave pass (as the 55 s loop would).
local autosave
for _, co in ipairs(coroutines) do if yieldOf[co] == 55 then autosave = co end end
ok(autosave ~= nil, "autosave loop found")
local function renew() local okR, errR = coroutine.resume(autosave, 55) assert(okR, tostring(errR) .. " " .. coroutine.status(autosave)) end
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
local function leave(p) p.Parent = nil; services.Players.PlayerRemoving:Fire(p) end
local function saved(p) return data["p" .. p.UserId].profile end
local function rejoin(p, mutate)
	leave(p)
	if mutate then mutate(saved(p)) end
	return player(p.UserId)
end
-- Visitors would consume rolls; a full bench keeps tests deterministic.
local function bench(g)
	g.visitors = {}
	for i = 1, G.MAX_VISITORS do table.insert(g.visitors, {id = 900 + i, npc = "Pell", wants = {Herb = 1}, order = {"Herb"}, coins = 1, marks = 1, gxp = 1, xp = 1, items = {}}) end
	g.seq = 905
end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	local profile = saved(p)
	bench(profile.garden)
	mutate(profile)
	return player(id)
end
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction RemoteFunction found")
-- §42: mock gather prompts harvest through real `strike` verbs (tools/strike-shim.luau).
require("./tools/strike-shim").install({signal = services.ProximityPromptService.PromptTriggered,
	invoke = function(p, verb, item) return remote.OnServerInvoke(p, verb, item) end, advance = advance})
local function cmd(p, verb, item)
	advance(1)
	renew()
	return remote.OnServerInvoke(p, verb, item)
end
local function plotOf(s, i) return s.garden.plots[i] end
local X = Data.XP_TABLE

-- C1: a fresh garden, first visitors, claim once.
local f = player(7001)
local s = cmd(f, "state")
ok(type(s.garden) == "table", "snapshot carries the garden")
ok(s.garden.level == 1 and s.garden.unlocked == 3 and #s.garden.plots == 12 and #s.garden.visitors == 0, "fresh garden")
eq(s.garden.nextVisitorIn, 59, "first visitor within a minute")
ok(f.attrs.GardenPlots == 3 and f.attrs.GardenPlot1 == "" and f.attrs.GardenComposter == "locked" and f.attrs.GardenSkin == "Loam", "world attributes published")
eq(f.attrs.GardenLevel, 1, "GardenLevel attribute")
ok(s.garden.composter.unlocked == false, "composter locked at level 1")
advance(60)
s = cmd(f, "state")
eq(#s.garden.visitors, 1, "a visitor arrives")
local first = s.garden.visitors[1]
ok(first.npc == "Bramwick" and first.id == 1, "highest roll picks Bramwick")
eq(first.wants.Herb, 26, "Farming 1 visitors want Meadow Herb")
ok(first.coins == 104 and first.marks == 2 and first.gxp == 9 and first.xp == 54, "visitor rewards")
eq(f.attrs.GardenVisitors, "Bramwick", "GardenVisitors attribute")
advance(100000)
s = cmd(f, "state")
eq(#s.garden.visitors, 2, "offline arrivals stop at the bench cap")
eq(s.garden.nextVisitorIn, nil, "no countdown while the bench is full")
s = cmd(f, "visitorAccept", "1")
ok(has(s.message, "wants 26") and #s.garden.visitors == 2, "requests need the crops")
f = rejoin(f, function(profile) profile.items.Herb = 100 end)
local coins0 = cmd(f, "state").coins
s = cmd(f, "visitorAccept", "1")
ok(has(s.message, "delighted"), "visitor accepts")
ok(s.coins == coins0 + 104 and s.items.VerdantMark == 2 and s.items.Herb == 74 and s.xp.Farming == 54, "coins, Marks, crops and Farming XP")
ok(#s.garden.visitors == 1 and s.garden.xp == 9 and s.garden.served == 1, "garden XP and served count")
s = cmd(f, "visitorAccept", "1")
ok(has(s.message, "already left") and s.coins == coins0 + 104, "a visitor pays once")
s = cmd(f, "visitorDecline", "2")
ok(has(s.message, "wanders off") and #s.garden.visitors == 0, "decline sends a visitor away")
eq(cmd(f, "visitorDecline", "2").message, "That visitor has already left.", "decline once")
eq(cmd(f, "visitorAccept", "abc").message, "That visitor has already left.", "junk ids refused")
advance(G.VISITOR_INTERVAL)
s = cmd(f, "state")
ok(#s.garden.visitors >= 1 and s.garden.visitors[1].id == 3, "visitor ids never repeat")

-- C2: planting, growth and harvest.
local g2 = seeded(7002, function(profile) profile.items.MeadowSeeds = 5 end)
s = cmd(g2, "plant", "1:MeadowSeeds")
ok(has(s.message, "Planted Meadow Herb in plot 1") and has(s.message, "5m 00s"), "planting reports the ripening time")
ok(s.items.MeadowSeeds == 4 and plotOf(s, 1).crop == "Herb" and plotOf(s, 1).stage == 1 and plotOf(s, 1).remaining == 300, "seed spent, crop planted")
eq(g2.attrs.GardenPlot1, "Herb:1:", "plot attribute")
ok(has(cmd(g2, "plant", "1:MeadowSeeds").message, "already planted"), "one crop per plot")
ok(has(cmd(g2, "plant", "4:MeadowSeeds").message, "locked"), "locked plots refuse seeds")
ok(has(cmd(g2, "plant", "2:SunwheatSeeds").message, "Farming 15"), "Farming level gate")
eq(cmd(g2, "plant", "2:Nope").message, "Choose a seed to plant.", "unknown seed")
eq(cmd(g2, "plant", "zz").message, "Choose a plot and a seed.", "malformed plant")
eq(cmd(g2, "plant", "13:MeadowSeeds").message, "Choose a garden plot.", "plot out of range")
eq(cmd(g2, "plant", "0:MeadowSeeds").message, "Choose a garden plot.", "plot zero")
ok(has(cmd(g2, "harvestPlot", "1").message, "not ripe"), "no early harvest")
ok(has(cmd(g2, "harvestPlot", "2").message, "empty"), "empty plot")
advance(140)
s = cmd(g2, "state")
ok(plotOf(s, 1).stage == 2 and plotOf(s, 1).remaining < 160 and not plotOf(s, 1).ripe, "growing in real time")
eq(g2.attrs.GardenPlot1, "Herb:2:", "stage published")
advance(160)
s = cmd(g2, "state")
ok(plotOf(s, 1).ripe and plotOf(s, 1).stage == 4 and plotOf(s, 1).remaining == 0, "ripe after five minutes")
eq(g2.attrs.GardenPlot1, "Herb:4:r", "ripe flag")
local herb0 = s.items.Herb or 0
queue(0.5, 0.1) -- fortune roll, then the seed-return roll
s = cmd(g2, "harvestPlot", "1")
ok(has(s.message, "+6 Meadow Herb") and has(s.message, "+50 Farming XP") and has(s.message, "+1 seed"), "harvest message")
ok(s.items.Herb == herb0 + 6 and s.items.MeadowSeeds == 5 and s.xp.Farming == 50, "crops, seed back and XP")
ok(s.garden.xp == 4 and plotOf(s, 1).crop == nil and s.garden.milestones.Herb.count == 6, "garden XP, empty plot, milestone count")
ok(s.collection.Herb >= 6, "garden harvests count toward collections")
eq(g2.attrs.GardenPlot1, "", "harvested plot cleared")
eq(cmd(g2, "harvestPlot", "all").message, "Nothing is ripe yet.", "nothing to harvest")
cmd(g2, "plant", "1:Herb")
cmd(g2, "plant", "2:MeadowSeeds")
advance(301)
queue(0.5, 0.1, 0.5, 0.1)
s = cmd(g2, "harvestPlot", "all")
ok(has(s.message, "+12 Meadow Herb") and has(s.message, "+2 seeds") and s.items.Herb == herb0 + 18, "harvest all")
queue(0.1)
cmd(g2, "plant", "3:MeadowSeeds")
advance(301)
local seedsBefore = cmd(g2, "state").items.MeadowSeeds
queue(0.5, 0.9)
s = cmd(g2, "harvestPlot", "3")
ok(has(s.message, "no seed saved") and s.items.MeadowSeeds == seedsBefore, "a missed seed roll saves nothing (M1: no seed loop)")

-- C3: harvest fortune (Farming level + hoe + crop milestone).
local g3 = seeded(7003, function(profile)
	profile.xp.Farming = X[26]
	profile.items.CopperHoe = 1
	profile.items.MeadowSeeds = 5
end)
cmd(g3, "plant", "1:MeadowSeeds")
advance(301)
queue(0.05)
s = cmd(g3, "harvestPlot", "1")
eq(s.depth.stats.farmingFortune, 100, "Farming 26 gives 100 fortune")
ok(has(s.message, "+18 Meadow Herb"), "fortune 110: double yield plus a lucky extra")
cmd(g3, "plant", "1:MeadowSeeds")
advance(301)
queue(0.5)
ok(has(cmd(g3, "harvestPlot", "1").message, "+12 Meadow Herb"), "fortune 110 without the extra")
eq(cmd(g3, "state").garden.unlocked, 4, "Farming 15 unlocks a fourth plot")
g3 = rejoin(g3, function(profile) profile.garden.harvested.Herb = 300; profile.garden.milestones.Herb = 2 end)
cmd(g3, "plant", "1:MeadowSeeds")
advance(301)
queue(0.21)
ok(has(cmd(g3, "harvestPlot", "1").message, "+12 Meadow Herb"), "milestone fortune counts (100 + hoe 10 + crop 8 + perk 2 = 120: roll 0.21 misses)")
cmd(g3, "plant", "1:MeadowSeeds")
advance(301)
queue(0.19)
ok(has(cmd(g3, "harvestPlot", "1").message, "+18 Meadow Herb"), "milestone fortune counts (120: roll 0.19 hits)")

-- C4: watering.
local g4 = seeded(7004, function(profile) profile.xp.Farming = X[15]; profile.items.SunwheatSeeds = 3 end)
cmd(g4, "plant", "1:SunwheatSeeds")
s = cmd(g4, "waterPlot", "1")
ok(has(s.message, "Watered plot 1") and plotOf(s, 1).watered == G.WATER_SECONDS, "watering")
ok(has(g4.attrs.GardenPlot1, "w"), "watered flag")
eq(plotOf(s, 1).remaining, 500, "water speeds growth: 599 s at 1.2x")
ok(has(cmd(g4, "waterPlot", "1").message, "still damp"), "no double watering")
ok(has(cmd(g4, "waterPlot", "2").message, "nothing to water"), "empty plot")
eq(cmd(g4, "waterPlot", "all").message, "Nothing needs water right now.", "water all with nothing to do")
local left = plotOf(cmd(g4, "state"), 1).remaining
advance(left - 2)
ok(not plotOf(cmd(g4, "state"), 1).ripe, "not ripe a second early")
advance(1)
ok(plotOf(cmd(g4, "state"), 1).ripe, "ripe right on time")
ok(has(cmd(g4, "waterPlot", "1").message, "ripe"), "ripe plots need no water")
cmd(g4, "plant", "2:SunwheatSeeds")
cmd(g4, "plant", "3:SunwheatSeeds")
ok(has(cmd(g4, "waterPlot", "all").message, "Watered 2 plots"), "water all")

-- C5: blight, treatment and withering.
local g5 = seeded(7005, function(profile) profile.items.MeadowSeeds = 6 end)
queue(0.01, 0.5)
cmd(g5, "plant", "1:MeadowSeeds")
advance(200)
s = cmd(g5, "state")
ok(plotOf(s, 1).sick and plotOf(s, 1).stage == 2 and plotOf(s, 1).remaining == nil, "blight struck and halted growth")
ok(plotOf(s, 1).deathIn and plotOf(s, 1).deathIn <= G.DEATH_SECONDS, "withering countdown")
ok(has(g5.attrs.GardenPlot1, "s"), "sick flag")
ok(has(cmd(g5, "harvestPlot", "1").message, "not ripe"), "blighted crops cannot be harvested")
ok(has(cmd(g5, "waterPlot", "1").message, "blighted"), "blighted crops refuse water")
ok(has(cmd(g5, "treatPlot", "1").message, "Blightward Salve"), "treatment needs a salve")
g5 = rejoin(g5, function(profile) profile.items.BlightwardSalve = 2 end)
s = cmd(g5, "treatPlot", "1")
ok(has(s.message, "cured") and not plotOf(s, 1).sick and plotOf(s, 1).treated and s.items.BlightwardSalve == 1, "salve cures the blight")
eq(plotOf(s, 1).remaining, 150, "growth resumes from the strike")
advance(151)
ok(plotOf(cmd(g5, "state"), 1).ripe, "cured crop ripens")
cmd(g5, "harvestPlot", "1")
queue(0.01, 0.0)
cmd(g5, "plant", "2:MeadowSeeds")
advance(60 + G.DEATH_SECONDS + 5)
s = cmd(g5, "state")
ok(plotOf(s, 2).dead and has(g5.attrs.GardenPlot2, "x"), "untreated blight withers the crop")
ok(has(cmd(g5, "harvestPlot", "2").message, "withered"), "withered crops yield nothing")
ok(has(cmd(g5, "treatPlot", "2").message, "beyond saving"), "too late to treat")
ok(has(cmd(g5, "gardenPlot", "2").message, "Cleared the withered"), "the plot prompt clears a withered crop")
s = cmd(g5, "treatPlot", "3")
ok(has(s.message, "next crop is immune") and plotOf(s, 3).treated, "pre-treat an empty plot")
queue(0.01, 0.5)
cmd(g5, "plant", "3:MeadowSeeds")
advance(301)
s = cmd(g5, "state")
ok(plotOf(s, 3).ripe, "pre-treated crop never blights")
ok(rolls[1] == 0.01, "a treated plot never rolls blight")
table.clear(rolls)
ok(has(cmd(g5, "treatPlot", "3").message, "already treated"), "one treatment per crop")
s = cmd(g5, "clearPlot", "3")
ok(has(s.message, "Cleared the Meadow Herb") and plotOf(s, 3).crop == nil and not plotOf(s, 3).treated, "uprooting clears the plot and its treatment")
ok(has(cmd(g5, "clearPlot", "3").message, "already clear"), "nothing to clear")

-- C6: composter and fertiliser.
local g6 = seeded(7006, function(profile) profile.garden.xp = 60; profile.items.Herb = 300; profile.items.MeadowSeeds = 5 end)
s = cmd(g6, "state")
ok(s.garden.level == 2 and s.garden.unlocked == 4 and s.garden.composter.unlocked, "garden level 2 opens the composter")
eq(g6.attrs.GardenComposter, "idle", "idle composter")
s = cmd(g6, "compost", "Herb:30")
ok(has(s.message, "Composted 30 Meadow Herb") and s.garden.composter.matter == 60 and s.items.Herb == 270, "feeding the composter")
eq(g6.attrs.GardenComposter, "working", "working composter")
eq(s.garden.composter.nextIn, 600, "first compost in ten minutes")
eq(cmd(g6, "compostClaim").message, "Nothing in the composter yet.", "nothing to collect yet")
ok(has(cmd(g6, "compost", "Ore").message, "only takes"), "inorganic items refused")
ok(has(cmd(g6, "compost", "AetherLotus").message, "You have no"), "must own the item")
advance(600)
s = cmd(g6, "state")
ok(s.garden.composter.out == 1 and s.garden.composter.matter == 0, "one compost made")
eq(g6.attrs.GardenComposter, "ready", "ready composter")
s = cmd(g6, "compostClaim")
ok(s.items.Compost == 1 and s.garden.composter.out == 0, "compost collected")
g6 = rejoin(g6, function(profile) profile.items.Herb = 5000 end)
s = cmd(g6, "compost", "Herb")
ok(s.garden.composter.matter == G.matterCap(0) and s.items.Herb == 5000 - G.matterCap(0) / 2, "feeding stops at the matter cap")
eq(cmd(g6, "compost", "Herb:1").message, "The composter is full.", "full composter")
advance(4 * 600)
s = cmd(g6, "state")
ok(s.garden.composter.out == 4 and s.garden.composter.dust == 1, "every fourth compost leaves Bloom Dust")
s = cmd(g6, "compostClaim")
ok(s.items.Compost == 5 and s.items.BloomDust == 1 and has(s.message, "Bloom Dust"), "dust collected")
ok(has(cmd(g6, "composterUpgrade").message, "costs 4 Bloom Dust"), "upgrade cost shown")
g6 = rejoin(g6, function(profile) profile.items.BloomDust = 4; profile.items.VerdantMark = 8 end)
s = cmd(g6, "composterUpgrade")
ok(s.garden.composter.upgrade == 1 and s.garden.composter.interval == 528 and s.items.BloomDust == 0 and s.items.VerdantMark == 0, "composter upgraded")
cmd(g6, "plant", "1:MeadowSeeds")
s = cmd(g6, "fertilise", "1")
ok(has(s.message, "+25% growth") and plotOf(s, 1).compost and s.items.Compost == 4, "fertilising spends compost")
eq(plotOf(s, 1).remaining, math.ceil(299 / 1.26), "compost and garden level speed growth")
ok(has(cmd(g6, "fertilise", "1").message, "already fertilised"), "one compost per crop")
queue(0.01, 0.5)
cmd(g6, "plant", "2:MeadowSeeds")
queue(0.1)
cmd(g6, "fertilise", "2")
advance(400)
s = cmd(g6, "state")
ok(plotOf(s, 2).ripe and not plotOf(s, 2).sick, "compost purged the hidden blight")
s = cmd(g6, "fertilise", "3")
ok(has(s.message, "next crop") and plotOf(s, 3).compost, "pre-fertilise an empty plot")
s = cmd(g6, "harvestPlot", "1")
ok(not plotOf(s, 1).compost, "harvest uses up the compost")

-- C7: pests.
local g7 = seeded(7007, function(profile) profile.items.MeadowSeeds = 5 end)
cmd(g7, "plant", "1:MeadowSeeds")
queue(0.01, 0.3)
advance(599)
s = cmd(g7, "state")
eq(plotOf(s, 1).pest, "Rootgrub", "a pest arrives after an interval")
ok(has(g7.attrs.GardenPlot1, "p2"), "pest flag published")
local herbBefore = s.items.Herb or 0
s = cmd(g7, "harvestPlot", "1")
ok(s.items.Herb == herbBefore + 3 and has(s.message, "pests cut"), "a pest cuts the harvest to 3")
cmd(g7, "plant", "2:MeadowSeeds")
queue(0.01, 0.9)
advance(599)
s = cmd(g7, "state")
eq(plotOf(s, 2).pest, "Thripling", "pest kind by roll")
local combat0, farm0, seeds0 = s.xp.Combat, s.xp.Farming, s.items.MeadowSeeds
queue(0.1)
s = cmd(g7, "clearPest", "2")
ok(has(s.message, "Swatted the Thripling"), "swat message")
ok(s.xp.Combat == combat0 + 26 and s.xp.Farming == farm0 + 8, "pests pay Combat and Farming XP")
ok(s.items.PestChitin == 1 and s.items.MeadowSeeds == seeds0 + 1, "pest drops: chitin and a seed")
ok(plotOf(s, 2).pest == nil and not has(g7.attrs.GardenPlot2, "p"), "pest cleared")
ok(has(cmd(g7, "clearPest", "2").message, "no pests"), "nothing to swat")
s = cmd(g7, "compost", "PestChitin")
ok(has(s.message, "locked") or has(s.message, "garden level"), "chitin waits for the composter")

-- C8: milestones, garden levels and migration.
local g8 = seeded(7008, function(profile) profile.items.MeadowSeeds = 5; profile.garden.harvested.Herb = 95; profile.garden.xp = 58 end)
local before = cmd(g8, "state")
local fortune0 = before.depth.stats.farmingFortune
cmd(g8, "plant", "1:MeadowSeeds")
advance(301)
s = cmd(g8, "harvestPlot", "1")
ok(has(s.message, "Meadow Herb milestone 1") and has(s.message, "+150 coins"), "milestone reward")
ok(has(s.message, "Garden level 2") and has(s.message, "New plot unlocked") and has(s.message, "composter is ready"), "garden level up")
ok(s.coins == before.coins + 150 and s.garden.level == 2 and s.garden.xp == 58 + 4 + 15, "milestone coins and garden XP")
eq(s.depth.stats.farmingFortune, fortune0 + G.MILESTONE_FORTUNE, "milestones raise Farming Fortune everywhere")
eq(s.garden.milestones.Herb.tier, 1, "milestone tier in the snapshot")
eq(s.garden.milestones.Herb.fortune, G.MILESTONE_CROP_FORTUNE, "crop fortune in the snapshot")
eq(s.garden.milestoneTiers, 1, "milestone tier total")
local g9 = seeded(7009, function(profile) profile.garden.harvested.Herb = 400; profile.garden.milestones = {} end)
local coins9 = cmd(g9, "state").coins
leave(g9)
eq(saved(g9).garden.milestones.Herb, 2, "migration baselines milestones")
g9 = player(7009)
eq(cmd(g9, "state").coins, coins9, "no retroactive milestone windfall")

-- C9: the shop, skins, hoe upgrades and the Rootwarden set.
local g10 = seeded(7010, function(profile) profile.coins = 5000 end)
s = cmd(g10, "gardenBuy", "MeadowSeeds")
ok(has(s.message, "Bought 4 Meadow Herb Seeds") and s.items.MeadowSeeds == 4 and s.coins == 4980, "buy seeds")
ok(has(cmd(g10, "gardenBuy", "LotusBud").message, "garden level 8"), "level-gated seeds")
eq(cmd(g10, "gardenBuy", "Nope").message, "The garden shop does not stock that.", "unknown entry")
ok(has(cmd(g10, "gardenBuy", "SkinMossbed").message, "garden level 2"), "level-gated skin")
ok(has(cmd(g10, "gardenSkin", "Starlit").message, "Unlock that skin"), "unowned skin")
g10 = rejoin(g10, function(profile) profile.garden.xp = 400; profile.items.VerdantMark = 400; profile.items.BloomDust = 100; profile.coins = 50 end)
s = cmd(g10, "gardenBuy", "SkinMossbed")
ok(has(s.message, "Mossbed") and g10.attrs.GardenSkin == "Mossbed" and s.items.VerdantMark == 385, "skin bought and applied")
ok(has(cmd(g10, "gardenBuy", "SkinMossbed").message, "already own"), "skins are bought once")
s = cmd(g10, "gardenSkin", "Loam")
ok(s.garden.skin == "Loam" and g10.attrs.GardenSkin == "Loam", "switch back to the free skin")
ok(has(cmd(g10, "gardenBuy", "SunwheatSeeds").message, "costs 60 coins"), "coins checked")
s = cmd(g10, "gardenBuy", "SproutwoodHoe")
ok(s.items.SproutwoodHoe == 1 and s.items.VerdantMark == 355 and s.items.BloomDust == 96, "hoe bought with Marks and Dust")
ok(has(cmd(g10, "gardenBuy", "SproutwoodHoe").message, "already own"), "unique hoe")
ok(has(cmd(g10, "gardenBuy", "GreenwardHoe").message, "garden level 7"), "hoe upgrade gated")
g10 = rejoin(g10, function(profile) profile.garden.xp = 3000 end)
s = cmd(g10, "gardenBuy", "GreenwardHoe")
ok(s.items.GreenwardHoe == 1 and (s.items.SproutwoodHoe or 0) == 0, "the upgrade consumes the old hoe")
ok(has(cmd(g10, "gardenBuy", "SproutwoodHoe").message, "already own"), "an upgraded hoe counts as owned")
local owned10 = cmd(g10, "state").garden.owned
ok(type(owned10) == "table" and owned10.SproutwoodHoe == true and owned10.GreenwardHoe == true and owned10.EverbloomHoe == nil,
	"L3: the snapshot lists shop entries owned through the upgrade chain")
ok(has(cmd(g10, "gardenBuy", "EverbloomHoe").message, "garden level 11"), "top hoe gated")
for _, a in ipairs(G.Armor) do cmd(g10, "gardenBuy", a.id) end
s = cmd(g10, "state")
for _, a in ipairs(G.Armor) do eq(s.items[a.id], 1, a.id .. " bought") end
eq(s.garden.setActive, false, "set not yet worn")
g10 = rejoin(g10, function(profile) profile.xp.Farming = X[10] end)
for _, a in ipairs(G.Armor) do cmd(g10, "equip", a.id) end
s = cmd(g10, "state")
ok(s.garden.setActive and s.depth.stats.activeSet == G.SET, "Rootwarden set active")
ok(near(s.garden.rate, 1 + G.SET_BOOST + G.LEVEL_BOOST * (s.garden.level - 1)), "set bonus speeds growth")
local broke = seeded(7015, function(profile) profile.coins = 0 end)
ok(has(cmd(broke, "gardenBuy", "MeadowSeeds").message, "costs 20 coins"), "cannot buy without coins")

-- C10: the contextual plot prompt and the world.
local g11 = seeded(31, function(profile) profile.items.MeadowSeeds = 3 end)
local prompt1 = plotPrompts[1]
local function use(p, q)
	advance(1)
	renew()
	p.root.Position = (if q:GetAttribute("GatherNode") then q else q.Parent).CFrame.Position -- §42: a node host is its own part
	p.last = nil
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
s = use(g11, prompt1)
ok(s and has(s.message, "Planted Meadow Herb in plot 1"), "the plot prompt plants the cheapest owned seed")
s = use(g11, prompt1)
ok(has(s.message, "Watered plot 1"), "then waters it")
s = use(g11, prompt1)
ok(has(s.message, "ripe in"), "then reports the timer")
advance(300)
s = use(g11, prompt1)
ok(has(s.message, "+6 Meadow Herb"), "then harvests")
local stranger = player(7099)
stranger.last = nil
advance(1)
stranger.root.Position = prompt1.Parent.CFrame.Position
services.ProximityPromptService.PromptTriggered:Fire(prompt1, stranger)
eq(stranger.last, nil, "another player cannot use your plot")
s = cmd(g11, "gardenPlot", "9")
ok(has(s.message, "locked"), "locked plot prompt")
s = use(g11, binPrompt)
ok(has(s.message, "Verdant Garden") and has(s.message, "level 1"), "ledger prompt summary")
g11 = rejoin(g11, function(profile) profile.items.MeadowSeeds = 0 end)
ok(has(cmd(g11, "gardenPlot", "1").message, "No seeds"), "no seeds to plant")

-- C11: the field seed pouch (every FIELD_SEED_EVERY-th field harvest).
local herbPrompt
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") and obj:GetAttribute("GatherNode") == "Herb" and obj:GetAttribute("IsleRegion") == nil then herbPrompt = obj break end -- §42: a struck node host
end
ok(herbPrompt ~= nil, "a field Meadow Herb node")
local g12 = player(7012)
local pouch
for i = 1, G.FIELD_SEED_EVERY do
	advance(4)
	local r = use(g12, herbPrompt)
	if i < G.FIELD_SEED_EVERY then assert(not has(r.message, "Seed pouch"), "no pouch before the twentieth harvest") end
	pouch = r
end
ok(has(pouch.message, "Seed pouch") and pouch.items.MeadowSeeds == 1, "twentieth field harvest bundles a seed")
leave(g12)
eq(saved(g12).garden.fieldSeeds.Herb, G.FIELD_SEED_EVERY, "field harvests counted")

-- C12: the garden loop publishes ripeness and visitors.
local g13 = seeded(7013, function(profile) profile.items.MeadowSeeds = 2 end)
cmd(g13, "plant", "1:MeadowSeeds")
advance(301)
g13.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
ok(g13.last and has(g13.last.message, "1 garden crop is ripe"), "the loop announces ripe crops")
eq(g13.attrs.GardenPlot1, "Herb:4:r", "the loop refreshes plot attributes")
g13.last = nil
assert(coroutine.resume(ticker, G.TICK))
eq(g13.last, nil, "no repeat announcement")
local g14 = player(7014)
advance(61)
g14.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
ok(g14.last and has(g14.last.message, "visitor is waiting"), "the loop announces a visitor")

-- C14 (L1+L6): garden news is never swallowed by a refresh. Refresh runs once
-- per second per garden; its events queue per garden and are told once: in
-- the next garden verb's message, or by the loop, which fires only while news
-- is pending. Non-garden snapshots leave the news pending.
local n1 = seeded(7020, function(profile) profile.items.MeadowSeeds = 4 end)
cmd(n1, "plant", "1:MeadowSeeds")
advance(301)
s = cmd(n1, "gardenOpen", "ledger")
ok(has(s.message, "1 ripe") and has(s.message, "1 garden crop is ripe"), "ripe news joins the next garden verb's message")
n1.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
eq(n1.last, nil, "the loop stays quiet once the news was told")
ok(not has(cmd(n1, "gardenOpen", "ledger").message, "is ripe"), "news is told once")
cmd(n1, "plant", "2:MeadowSeeds")
advance(301)
s = cmd(n1, "state")
ok(not has(s.message, "ripe") and plotOf(s, 2).ripe, "a non-garden snapshot refreshes (plot 2 ripe) but keeps the news pending")
n1.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
ok(n1.last and has(n1.last.message, "1 garden crop is ripe"), "the snapshot's refresh did not swallow it: the loop tells it")
n1.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
eq(n1.last, nil, "nothing pending: the loop does not fire")
cmd(n1, "plant", "3:MeadowSeeds")
advance(301)
s = cmd(n1, "waterPlot", "1")
ok(has(s.message, "harvest it") and has(s.message, "1 garden crop is ripe"), "news found by a verb's refresh joins that verb's message")
cmd(n1, "harvestPlot", "all")
cmd(n1, "plant", "1:MeadowSeeds")
advance(301)
s = cmd(n1, "harvestPlot", "1")
ok(has(s.message, "+6 Meadow Herb") and not has(s.message, "is ripe"), "a crop harvested in the same action is not announced")
n1.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
eq(n1.last, nil, "harvested news is dropped, not announced later")
local n2 = player(7021)
advance(61)
s = cmd(n2, "gardenOpen", "ledger")
ok(has(s.message, "1 visitor") and has(s.message, "A visitor is waiting"), "a visitor arriving during a verb is announced")
n2.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
eq(n2.last, nil, "the visitor is announced once")
advance(G.VISITOR_INTERVAL)
n2.last = nil
renew()
assert(coroutine.resume(ticker, G.TICK))
ok(n2.last and has(n2.last.message, "A visitor is waiting"), "the loop announces a pending visitor")
ok(not has(cmd(n2, "gardenOpen", "ledger").message, "waiting"), "and the next garden verb does not repeat it")

-- C15 (L2): the plot prompt replants the last chosen seed, else the cheapest
-- owned seed, and never spends Mark-bought seeds the player did not choose.
local l2 = seeded(7022, function(profile) profile.xp.Farming = X[80]; profile.items.MeadowSeeds = 2; profile.items.LotusBud = 2 end)
s = cmd(l2, "gardenPlot", "1")
ok(has(s.message, "Planted Meadow Herb in plot 1") and s.items.LotusBud == 2, "cheapest seed, Lotus Buds untouched")
s = cmd(l2, "plant", "2:LotusBud")
ok(has(s.message, "Planted Aether Lotus") and s.garden.lastSeed == "LotusBud", "choosing a seed remembers it")
s = cmd(l2, "gardenPlot", "3")
ok(has(s.message, "Planted Aether Lotus in plot 3") and (s.items.LotusBud or 0) == 0, "the prompt replants the chosen seed")
s = cmd(l2, "gardenPlot", "4")
ok(has(s.message, "Planted Meadow Herb in plot 4"), "out of the chosen seed: the cheapest owned")
leave(l2)
eq(saved(l2).garden.lastSeed, "LotusBud", "last seed persisted")
local l2b = seeded(7023, function(profile) profile.xp.Farming = X[80]; profile.items.LotusBud = 1; profile.items.StarfruitPit = 1 end)
s = cmd(l2b, "gardenPlot", "1")
ok(has(s.message, "Choose a seed in the garden ledger") and s.items.LotusBud == 1 and s.items.StarfruitPit == 1 and plotOf(s, 1).crop == nil,
	"Mark-bought seeds are never auto-planted")

-- C16 (L4): mastery Twin yield procs apply to garden harvests (base before fortune).
local l4 = seeded(7024, function(profile)
	profile.xp.Farming = X[30]
	profile.items.MeadowSeeds = 5
	profile.mastery = {trees = {Farming = {TilledRows = 1, BumperCrop = 5}}}
end)
s = cmd(l4, "state")
eq(s.depth.mastery.trees.Farming.nodes.BumperCrop, 5, "Bumper Crop owned (10% Twin yield)")
local fort = s.depth.stats.farmingFortune
local mult4 = 1 + math.floor(fort / 100)
cmd(l4, "plant", "1:MeadowSeeds")
advance(301)
local herb4 = cmd(l4, "state").items.Herb or 0
queue(0.05, 0.999, 0.999) -- Twin yield proc, fortune remainder miss, seed miss
s = cmd(l4, "harvestPlot", "1")
eq(s.items.Herb, herb4 + 6 * 2 * mult4, "a Twin yield proc doubles the garden base before fortune")
ok(has(s.message, "x2 yield"), "the proc is reported")
cmd(l4, "plant", "1:MeadowSeeds")
advance(301)
herb4 = cmd(l4, "state").items.Herb or 0
queue(0.5, 0.999, 0.999)
s = cmd(l4, "harvestPlot", "1")
eq(s.items.Herb, herb4 + 6 * mult4, "no proc: base yield with fortune")

-- C17 (L5): compost counts below one are refused with a reason.
local l5 = seeded(7025, function(profile) profile.garden.xp = 60; profile.items.Herb = 50 end)
s = cmd(l5, "compost", "Herb:0")
ok(has(s.message, "at least 1") and s.items.Herb == 50 and s.garden.composter.matter == 0, "a zero count is refused")
ok(not has(s.message, "full"), "a zero count is not reported as a full composter")
s = cmd(l5, "compost", "Herb:00")
ok(has(s.message, "at least 1"), "zero in any spelling")
s = cmd(l5, "compost", "Herb:3")
ok(has(s.message, "Composted 3 Meadow Herb") and s.items.Herb == 47, "a real count still composts")

-- C13: persistence, offline growth and tampering.
local g15 = seeded(7016, function(profile) profile.items.MeadowSeeds = 2; profile.garden.xp = 60; profile.items.Herb = 600 end)
cmd(g15, "plant", "1:MeadowSeeds")
cmd(g15, "waterPlot", "1")
cmd(g15, "compost", "Herb:300")
leave(g15)
local savedGarden = saved(g15).garden
ok(savedGarden.plots[1].crop == "Herb" and savedGarden.plots[1].water ~= nil and savedGarden.composter.matter == 600, "garden saved")
advance(10 * 600 + 5)
g15 = player(7016)
s = cmd(g15, "state")
ok(plotOf(s, 1).ripe, "crops ripen while offline")
ok(s.garden.composter.out == 10 and s.garden.composter.dust == 2 and s.garden.composter.matter == 0, "the composter works offline")
ok(s.garden.level == 2 and s.garden.xp == 60, "garden level persisted")
local bytes = #serde.encode("json", saved(g15).garden)
ok(bytes < 4500, "saved garden is small (" .. bytes .. " bytes)")
g15 = rejoin(g15, function(profile)
	profile.garden = {xp = "lots", plots = {{crop = "Ghost"}, {crop = "Herb", grown = 1e9, at = 1e15}}, visitors = {{id = 1, npc = "Nobody"}}, skin = "Gold", composter = "x"}
end)
s = cmd(g15, "state")
ok(s.garden.xp == 0 and plotOf(s, 1).crop == nil and plotOf(s, 2).ripe and s.garden.skin == "Loam", "tampered saves are sanitised")
ok(#s.garden.visitors <= G.MAX_VISITORS, "visitors bounded")
g15 = rejoin(g15, function(profile) profile.garden = nil end)
ok(cmd(g15, "state").garden.level == 1, "older saves gain a fresh garden")
eq(cmd(g15, "gardenOpen", "ledger").message, "Verdant Garden   ·   level 1   ·   0 ripe   ·   0 visitors", "ledger summary")
print("PASS: " .. (checks - partC) .. " Verdant Garden server assertions.")
print("Verdant Garden QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-garden.luau")
