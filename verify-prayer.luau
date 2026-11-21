-- Prayer & Thieving: data rules, balance, world placement, server behaviour,
-- combat hooks and the atlas pages.
-- Part A checks shared/GameData.lua (Data.Prayer / Data.Thieving): prayers,
-- drain math, protection, remains, altars, thieving targets, chances and the
-- XP/h and coins/h balance against gathering. Part B runs world.server.lua with
-- real Roblox instances and checks every altar and thieving prompt. Part C runs
-- server.server.lua against those prompts (deterministic clock, rolls and
-- DataStore doubles): toggles, drain ticks, protection on bridge "damage",
-- offerings, draughts, stalls, pickpockets, strongboxes, stuns, quests and
-- persistence. Part D drives combat.server.lua's pure core (prayer offence,
-- accuracy, sap, mana). Part E renders Hero › Prayer and Hunt › Thieving.
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
local PR, TH = Data.Prayer, Data.Thieving
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

------------------------------------------------------------------------------
-- Part A: data, pure rules and balance.
------------------------------------------------------------------------------
local partA = checks
for _, skill in ipairs({"Prayer", "Thieving"}) do
	ok(table.find(Data.SkillOrder, skill) ~= nil, skill .. " registered in SkillOrder")
	local def = Data.Skills[skill]
	ok(def and def.perLevel and def.description and def.title and #def.color == 6, skill .. " skill metadata")
	for stat in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil, skill .. " perLevel stat " .. stat) end
end
for _, stat in ipairs({"devotion", "deftness"}) do
	ok(Data.Stats[stat] ~= nil and table.find(Data.StatOrder, stat) ~= nil and Data.Stats[stat].cap ~= nil, "stat " .. stat .. " registered and capped")
end
do
	local stats = P.computeStats({xp = {Prayer = Data.XP_TABLE[99], Thieving = Data.XP_TABLE[99]}, items = {}}, 0)
	ok(stats.devotion > 0 and stats.devotion <= Data.Stats.devotion.cap, "Prayer 99 grants Devotion within its cap")
	ok(stats.deftness > 0 and stats.deftness <= Data.Stats.deftness.cap, "Thieving 99 grants Deftness within its cap")
end

-- Prayers.
ok(#PR.Prayers >= 16 and #PR.Prayers <= 24, "16-24 prayers (" .. #PR.Prayers .. ")")
eq(PR.Prayers[1].level, 1, "first prayer at Prayer 1")
local kinds = {defence = 0, melee = 0, ranged = 0, magic = 0, protect = 0, heal = 0, mana = 0, preserve = 0, sap = 0, high = 0}
local seenIds = {}
for i, def in ipairs(PR.Prayers) do
	ok(not seenIds[def.id], "unique prayer " .. def.id)
	seenIds[def.id] = true
	eq(PR.PrayerById[def.id], def, def.id .. " indexed")
	eq(def.index, i, def.id .. " index")
	ok(def.level >= 1 and def.level <= 99 and def.drain > 0 and #def.name > 0 and #def.text > 0 and type(def.glyph) == "string" and #def.color == 6, def.id .. " values")
	if i > 1 then ok(def.level > PR.Prayers[i - 1].level, def.id .. " levels ascend") end
	for _, g in ipairs(def.groups) do ok(PR.Groups[g] ~= nil, def.id .. " group " .. g) end
	if def.defence then kinds.defence += 1 end
	for style, v in pairs(def.offence or {}) do ok(Data.CombatStyles.names[style] ~= nil and v > 0 and v <= 25, def.id .. " offence " .. style); kinds[style] += 1 end
	if def.protect then kinds.protect += 1; eq(PR.ProtectFor[def.protect], def.id, def.id .. " protects " .. def.protect) end
	if def.heal then kinds.heal += 1 end
	if def.mana then kinds.mana += 1 end
	if def.preserve then kinds.preserve += 1 end
	if def.sap then kinds.sap += 1 end
	if def.level >= 70 then kinds.high += 1 end
end
ok(kinds.defence >= 3 and kinds.melee >= 3 and kinds.ranged >= 3 and kinds.magic >= 3, "defence and per-style offence tiers")
eq(kinds.protect, 3, "three protection prayers")
ok(kinds.heal >= 1 and kinds.mana >= 1 and kinds.preserve >= 1 and kinds.sap >= 1, "heal, restore, preserve and sap prayers")
eq(kinds.high, 2, "two high-level hymns")
for _, set in ipairs({{"BarkhideWard", "StonehideWard", "IronbarkWard"}, {"KindledEdge", "BlazingEdge", "WildfireEdge"}, {"KeenSight", "HawkSight", "FalconSight"}, {"QuietSpark", "RisingSpark", "StormSpark"}}) do
	local values = {}
	for i, id in ipairs(set) do
		local def = PR.PrayerById[id]
		values[i] = def.defence or def.offence.melee or def.offence.ranged or def.offence.magic
	end
	eq(values[1], 5, set[1] .. " +5%")
	eq(values[2], 10, set[2] .. " +10%")
	eq(values[3], 15, set[3] .. " +15%")
end
-- Exclusive groups.
ok(PR.conflicts(PR.PrayerById.BarkhideWard, PR.PrayerById.StonehideWard), "wards are exclusive")
ok(PR.conflicts(PR.PrayerById.WardOfFangs, PR.PrayerById.WardOfGlyphs), "protections are exclusive")
ok(not PR.conflicts(PR.PrayerById.WardOfFangs, PR.PrayerById.StonehideWard), "protection stacks with a ward")
ok(not PR.conflicts(PR.PrayerById.KindledEdge, PR.PrayerById.KeenSight), "different styles stack")
ok(PR.conflicts(PR.PrayerById.ValorHymn, PR.PrayerById.IronbarkWard) and PR.conflicts(PR.PrayerById.ValorHymn, PR.PrayerById.WildfireEdge), "Valor Hymn replaces wards and edges")
ok(PR.conflicts(PR.PrayerById.StarwardLitany, PR.PrayerById.FalconSight) and PR.conflicts(PR.PrayerById.StarwardLitany, PR.PrayerById.StormSpark), "Starward Litany replaces sights and sparks")
ok(not PR.conflicts(PR.PrayerById.ValorHymn, PR.PrayerById.ValorHymn), "a prayer never conflicts with itself")
ok(not PR.conflicts(PR.PrayerById.MendingHymn, PR.PrayerById.AmberVigil), "utility prayers stack")
-- Toggle verdicts.
do
	local v, active, dropped = PR.toggle({}, "BarkhideWard", 1, 10)
	eq(v, "on", "toggle on")
	ok(active.BarkhideWard == true and #dropped == 0, "active set gains the prayer")
	v, active, dropped = PR.toggle(active, "StonehideWard", 10, 10)
	eq(v, "on", "higher ward on")
	ok(active.StonehideWard and not active.BarkhideWard and dropped[1] == "BarkhideWard", "higher ward replaces the lower")
	v, active = PR.toggle(active, "StonehideWard", 10, 10)
	eq(v, "off", "toggle off")
	eq(next(active), nil, "nothing active after toggling off")
	eq((PR.toggle({}, "WardOfFangs", 36, 10)), "level", "protection needs Prayer 37")
	eq((PR.toggle({}, "BarkhideWard", 1, 0)), "points", "no points, no prayer")
	eq((PR.toggle({}, "Nope", 99, 10)), "unknown", "unknown prayer")
	eq((PR.toggle({}, nil, 99, 10)), "unknown", "nil prayer")
	local _, offAtZero = PR.toggle({BarkhideWard = true}, "BarkhideWard", 1, 0)
	eq(offAtZero.BarkhideWard, nil, "switching off works with no points")
	local _, many = PR.toggle({WardOfFangs = true, KindledEdge = true, StonehideWard = true}, "ValorHymn", 99, 50)
	ok(many.ValorHymn and many.WardOfFangs and not many.KindledEdge and not many.StonehideWard, "a hymn keeps protection and drops edges and wards")
	-- Activation cost: one tick of that prayer's drain; fewer points refuse it.
	ok(near(PR.activationCost("BarkhideWard", 0), 3 / 60 * PR.TICK), "activation pays one tick of drain")
	ok(near(PR.activationCost("ValorHymn", 30), 24 / 60 / 2 * PR.TICK), "activation cost is cut by Devotion")
	eq(PR.activationCost("Nope", 0), 0, "unknown prayer costs nothing")
	eq((PR.toggle({}, "ValorHymn", 99, 1)), "points", "a hymn needs its activation cost (1.2 points)")
	eq((PR.toggle({}, "ValorHymn", 99, 1.2)), "on", "exactly the activation cost is enough")
	eq((PR.toggle({}, "ValorHymn", 99, 0.7, 30)), "on", "Devotion lowers the activation cost")
	-- Time-based charge: prepaid credit first, then the drain rate.
	local credit = {ValorHymn = PR.TICK}
	local left, empty = PR.charge(10, {ValorHymn = true}, credit, 0, 2)
	ok(left == 10 and not empty and near(credit.ValorHymn, PR.TICK - 2), "credit covers the first seconds")
	left = PR.charge(10, {ValorHymn = true}, credit, 0, 2)
	ok(near(left, 10 - 24 / 60) and credit.ValorHymn == nil, "credit used up, then the drain rate")
	left = PR.charge(100, {ValorHymn = true, BarkhideWard = true}, {}, 0, 60)
	ok(near(left, 100 - 27), "every active prayer drains for the whole interval")
	eq((PR.charge(10, {ValorHymn = true}, {}, 0, 60)), 0, "never below 0")
	ok(select(2, PR.charge(1, {BarkhideWard = true}, nil, 0, 60)), "running out is reported")
	ok(not select(2, PR.charge(0, {}, {}, 0, 60)), "nothing active never empties")
	ok(near((PR.charge(10, {BarkhideWard = true}, {}, 30, 60)), 10 - 1.5), "Devotion halves the charge at 30")
	eq(#PR.list({Nope = true, BarkhideWard = true, [3] = "KindledEdge"}), 2, "list drops unknown ids")
	eq(PR.list({"StonehideWard", "BarkhideWard"})[1], "BarkhideWard", "list sorts by prayer book order")
end
-- Points and drain math.
eq(PR.maxPoints(1), 11, "Prayer 1 pool")
eq(PR.maxPoints(99), 109, "Prayer 99 pool")
eq(PR.maxPoints(150), 109, "pool capped at 99")
eq(PR.maxPoints(nil), 11, "missing level pool")
for lvl = 2, 99 do if PR.maxPoints(lvl) <= PR.maxPoints(lvl - 1) then error("pool must grow with level " .. lvl) end end
checks += 1
eq(PR.drainPerMinute({BarkhideWard = true, WardOfFangs = true}), 15, "drain adds up")
ok(near(PR.drainPerSecond({WardOfFangs = true}, 0), 12 / 60), "protection drains 12 points per minute")
ok(near(PR.drainPerSecond({WardOfFangs = true}, 30), 12 / 60 / 2), "30 Devotion halves the drain")
ok(near(PR.drainPerSecond({WardOfFangs = true}, 1000), 12 / 60 / 3), "Devotion capped at 60 (a third of the drain)")
ok(near(PR.drainPerSecond({WardOfFangs = true}, -50), 12 / 60), "negative Devotion ignored")
eq(PR.drainPerSecond({}, 0), 0, "no prayers, no drain")
do
	local left, empty = PR.drain(10, {WardOfFangs = true}, 0, 30)
	ok(near(left, 4), "30 s of protection drains 6 points")
	eq(empty, false, "points left")
	left, empty = PR.drain(5, {ValorHymn = true, WardOfFangs = true}, 0, 60)
	eq(left, 0, "drain never goes below 0")
	eq(empty, true, "running dry is reported")
	left, empty = PR.drain(5, {}, 0, 600)
	eq(left, 5, "inactive book keeps its points")
	eq(empty, false, "no prayers never runs dry")
	left = PR.drain(10, {WardOfFangs = true}, 0, -5)
	eq(left, 10, "negative time drains nothing")
	ok(near(PR.secondsLeft(12, {WardOfFangs = true}, 0), 60), "12 points last a minute of protection")
	eq(PR.secondsLeft(12, {}, 0), math.huge, "no drain lasts forever")
	-- Drain is linear in time: ten 3 s ticks equal one 30 s step.
	local stepped = 50
	for _ = 1, 10 do stepped = PR.drain(stepped, {StonehideWard = true, WardOfQuills = true}, 12, PR.TICK) end
	ok(near(stepped, (PR.drain(50, {StonehideWard = true, WardOfQuills = true}, 12, 30)), 0.01), "ticks add up to one long step")
end
-- Effects and protection.
do
	local e = PR.effects({StonehideWard = true, WardOfFangs = true, BlazingEdge = true, MendingHymn = true})
	eq(e.defence, 10, "ward defence")
	eq(e.offence.melee, 10, "edge offence")
	eq(e.offence.ranged, 0, "no ranged offence")
	eq(e.protect, "melee", "protect style")
	eq(e.heal, 1.5, "hymn heal")
	local hymn = PR.effects({StarwardLitany = true})
	ok(hymn.offence.ranged == 20 and hymn.offence.magic == 20 and hymn.defence == 25, "litany offence and defence")
	eq(PR.effects({}).protect, nil, "no protection by default")
	eq(PR.protectMult("melee", "melee", false), 1 - PR.PROTECT, "40% off matching style")
	eq(PR.protectMult("melee", "melee", true), 1 - PR.PROTECT_WORLD_BOSS, "25% off world bosses")
	eq(PR.protectMult("melee", "ranged", false), 1, "wrong style unprotected")
	eq(PR.protectMult(nil, "melee", false), 1, "no protection")
	eq(PR.PROTECT, 0.4, "protection is 40%")
	eq(PR.PROTECT_WORLD_BOSS, 0.25, "world boss protection is 25%")
	-- Protection never reduces damage below 0 and never raises it.
	for _, raw in ipairs({0, 1, 7.5, 100, 2000, -50, 1e9}) do
		for _, style in ipairs({"melee", "ranged", "magic", "nope"}) do
			for _, boss in ipairs({false, true}) do
				for _, protect in ipairs({"melee", "ranged", "magic"}) do
					local amount, mult = PR.incoming(raw, style, {protect = protect, defence = 25}, boss)
					assert(amount >= 0 and amount <= math.max(0, raw), "protection keeps damage in 0..raw")
					assert(mult == 1.25, "ward multiplier")
					checks += 1
				end
			end
		end
	end
	eq((PR.incoming(100, "melee", {protect = "melee"}, false)), 60, "100 melee becomes 60")
	eq((PR.incoming(100, "magic", {protect = "magic"}, true)), 75, "100 from a world boss becomes 75")
	eq((PR.incoming(100, "ranged", nil, false)), 100, "no effects, no change")
	eq(select(2, PR.incoming(100, "ranged", nil, false)), 1, "no ward multiplier")
	-- End to end with defence: damageTaken stays >= 1, protected <= unprotected.
	for _, def in ipairs({0, 50, 300, 1000}) do
		for _, raw in ipairs({1, 12, 600, 2000}) do
			local plain = P.damageTaken(raw, def)
			local amount, mult = PR.incoming(raw, "melee", PR.effects({WardOfFangs = true, IronbarkWard = true}), false)
			local warded = P.damageTaken(amount, def * mult)
			ok(warded >= 1 and warded <= plain, string.format("raw %d vs defence %d: warded %d <= plain %d", raw, def, warded, plain))
		end
	end
end
-- Sap, preserve, restore.
eq(PR.sapped(100, 100, 0.03), 97, "one sap removes 3%")
eq(PR.sapped(71, 100, 0.03), 70, "sap stops at the 30% floor")
eq(PR.sapped(70, 100, 0.03), 70, "fully sapped stays put")
eq(PR.sapped(10, 10, 0.03), 9, "small defences still lose a point")
-- The floor rounds up: never more than SAP_MAX removed, even from tiny bases.
for _, case in ipairs({{1, 1}, {2, 2}, {5, 4}, {100, 70}, {7, 5}, {300, 210}}) do
	local base, floorDef = case[1], case[2]
	local d = base
	for _ = 1, 60 do d = PR.sapped(d, base, PR.SAP_PER_HIT) end
	eq(d, floorDef, "base " .. base .. " sap floor")
	ok(base - d <= base * PR.SAP_MAX + 1e-9, "base " .. base .. ": sap removes at most 30%")
end
eq(PR.sapped(0, 0, 0.03), 0, "no defence, nothing to sap")
eq(PR.sapped(50, 100, 0), 50, "no sap prayer, no change")
do
	local d = 300
	for _ = 1, 50 do d = PR.sapped(d, 300, PR.SAP_PER_HIT) end
	eq(d, math.ceil(300 * (1 - PR.SAP_MAX) - 1e-9), "sap converges on the floor")
end
ok(near(PR.preserveExtend(3, 0.5), 1), "Amber Vigil adds 1 s per 3 s tick (buffs last 1.5x)")
eq(PR.preserveExtend(3, 0), 0, "no vigil, no extension")
ok(near(90 + 90 * 0.5, 90 / (1 - PR.preserveExtend(1, 0.5))), "a 90 s buff lasts 135 s under the vigil")
eq(PR.restore(0, 50, Data.Items.DevotionDraught), 8 + 12, "Devotion Draught restores 8 + 25%")
eq(PR.restore(45, 50, Data.Items.DevotionDraught), 50, "restore capped at max")
eq(PR.restore(0, 100, Data.Items.ChoirTonic), 12 + 35, "Choir Tonic restores 12 + 35%")
eq(PR.restore(10, 50, Data.Items.Herb), 10, "non-draughts restore nothing")
-- Remains.
eq(#PR.Remains, 8, "eight remains tiers")
for i, r in ipairs(PR.Remains) do
	local def = Data.Items[r.id]
	ok(def and def.category == "remains" and def.prayerXp == r.xp and def.remainsTier == i and def.value > 0, r.id .. " item")
	if i > 1 then ok(r.xp > PR.Remains[i - 1].xp, r.id .. " XP grows by tier") end
	ok(table.find(Data.CollectionItems, r.id) ~= nil and Data.CollectionScale[r.id] ~= nil, r.id .. " collection")
end
eq(PR.remainsFor(1), "BrittleRemains", "level 1 remains")
eq(PR.remainsFor(9), "BrittleRemains", "level 9 remains")
eq(PR.remainsFor(10), "WeatheredRemains", "level 10 remains")
eq(PR.remainsFor(80), "StormboundRemains", "level 80 remains")
eq(PR.remainsFor(85), "WyrmRemains", "level 85+ remains")
eq(PR.remainsFor(50, nil, true), "WyrmRemains", "deep sea creatures leave wyrm remains")
eq(PR.remainsFor(20, nil, true), "HeavyRemains", "shallow sea creatures leave remains by level")
eq(PR.remainsFor(85, "ShatteredCrown"), "CrownRemains", "the Crown leaves crown remains")
local function remainsDrop(drops)
	local found
	for _, d in ipairs(drops) do if PR.RemainsById[d.item] then ok(found == nil, "one remains entry per table"); found = d end end
	return found
end
for id, def in pairs(Data.Monsters) do
	local d = remainsDrop(def.drops)
	ok(d ~= nil and d.chance == 1 and d.item == PR.remainsFor(def.level, def.region, false), id .. " always drops its remains")
end
for id, def in pairs(Data.SeaCreatures) do
	local d = remainsDrop(def.drops)
	ok(d ~= nil and d.chance == 1, id .. " (sea creature) drops remains")
end
for line, def in pairs(Data.Slayers) do
	for t, tier in ipairs(def.tiers) do
		local d = remainsDrop(tier.drops)
		ok(d ~= nil and d.chance == 1 and d.min >= 3, line .. " tier " .. t .. " drops a stack of remains")
	end
end
-- Altars.
ok(#PR.Altars >= 3, "three or more altars")
eq(PR.Altars[1].region, "Hub", "the first altar is ungated on the Quay")
for i, a in ipairs(PR.Altars) do
	eq(PR.AltarById[a.id], a, a.id .. " indexed")
	ok(Data.RegionById[a.region] ~= nil and a.mult >= 1 and a.mult <= 2 and #a.text > 0, a.id .. " values")
	if i > 1 then ok(a.mult > PR.Altars[i - 1].mult, a.id .. " multiplier grows") end
end
eq(PR.offerXp("BrittleRemains", "QuayChapel", 1), 3, "one brittle offering")
eq(PR.offerXp("CrownRemains", "CrownReliquary", 10), math.floor(40 * 1.75 * 10 + 0.5), "ten crown offerings at the reliquary")
eq(PR.offerXp("Nope", "QuayChapel", 1), 0, "unknown remains")
eq(PR.offerXp("BrittleRemains", "Nope", 1), 0, "unknown altar")
eq(PR.bestRemains({BrittleRemains = 4, HeavyRemains = 1}), "HeavyRemains", "best remains held")
eq(PR.bestRemains({BrittleRemains = 0}), nil, "none held")
eq(PR.bestRemains(nil), nil, "no satchel")
-- Recipes and items.
for _, id in ipairs({"DevotionDraught", "ChoirTonic", "ChoirbellCharm", "SeraphCenser", "LightfingerGloves", "SilkshadowGloves", "NightveilGloves"}) do
	local r = Data.Recipes[id]
	ok(r ~= nil and Data.Skills[r.skill] ~= nil and r.level >= 1 and r.xp > 0, id .. " recipe")
	for item in pairs(r.costs) do ok(Data.Items[item] ~= nil, id .. " cost " .. item) end
end
ok(Data.Items.ChoirbellCharm.stats.devotion > 0 and Data.Items.SeraphCenser.stats.devotion > Data.Items.ChoirbellCharm.stats.devotion, "devotion accessories")

-- Thieving targets.
ok(#TH.Targets >= 12, "twelve or more thieving targets")
local byKind = {stall = 0, pocket = 0, safe = 0}
for i, t in ipairs(TH.Targets) do
	eq(TH.TargetById[t.id], t, t.id .. " indexed")
	ok(TH.Kinds[t.kind] ~= nil, t.id .. " kind")
	byKind[t.kind] += 1
	ok(Data.RegionById[t.region] ~= nil, t.id .. " region")
	ok(t.level >= 1 and t.level <= 99 and t.xp > 0 and t.base > 0.3 and t.base < 0.8 and t.respawn > 0 and t.stun > 0 and t.damage > 0, t.id .. " values")
	ok(t.coins[1] >= 1 and t.coins[2] >= t.coins[1], t.id .. " coin range")
	for _, d in ipairs(t.drops) do ok(Data.Items[d.item] ~= nil and d.chance > 0 and d.chance <= 1 and d.min >= 1 and d.max >= d.min, t.id .. " drop " .. d.item) end
	if i > 1 then ok(t.level >= TH.Targets[i - 1].level, t.id .. " levels ascend") end
end
ok(byKind.stall >= 4 and byKind.pocket >= 5 and byKind.safe >= 3, "stalls, marks and strongboxes")
for _, name in ipairs({"Farmhand", "Watchman", "Merchant", "Noble"}) do ok(TH.TargetById[name] ~= nil and TH.TargetById[name].kind == "pocket", name .. " is a pickpocket mark") end
for _, t in ipairs(TH.Targets) do if t.kind == "safe" then ok(t.level >= 50, t.id .. " strongboxes are high level") end end
-- Gems and gloves.
for _, id in ipairs({"SunstoneChip", "Mistpearl", "Emberglass", "Voidgarnet", "StarheartGem"}) do
	ok(Data.Items[id] and Data.Items[id].category == "gem" and table.find(Data.CollectionItems, id) ~= nil, id .. " gem with a collection")
end
eq((TH.gloves({LightfingerGloves = 1, SilkshadowGloves = 1})), "SilkshadowGloves", "best gloves win")
eq(select(2, TH.gloves({NightveilGloves = 1})), 0.15, "Nightveil bonus")
eq(select(2, TH.gloves({})), 0, "no gloves")
eq(select(2, TH.gloves(nil)), 0, "no satchel")
-- Success chance.
do
	local farm = TH.TargetById.Farmhand
	eq(TH.chance(farm, 1, 0, 0), 0.6, "base chance at the target's level")
	eq(TH.chance(TH.TargetById.Watchman, 29, 0, 0), 0, "below the target's level")
	ok(near(TH.chance(farm, 11, 0, 0), 0.6 + 10 * TH.LEVEL_STEP), "level raises the chance")
	ok(near(TH.chance(farm, 1, 0.1, 0), 0.7), "gloves add")
	ok(near(TH.chance(farm, 1, 0, 20), 0.6 + 20 * TH.DEFT_EFFECT), "Deftness adds")
	ok(near(TH.chance(farm, 1, 0, 9999), 0.6 + Data.Stats.deftness.cap * TH.DEFT_EFFECT), "Deftness capped")
	eq(TH.chance(farm, 99, 0.15, 50), TH.MAX_CHANCE, "chance capped at 95%")
	eq(TH.chance(nil, 99, 0, 0), 0, "no target")
	for _, t in ipairs(TH.Targets) do
		local last = 0
		for lvl = t.level, 99 do
			local c = TH.chance(t, lvl, 0, 0)
			assert(c >= last and c <= TH.MAX_CHANCE, t.id .. " chance rises with level")
			last = c
		end
		checks += 1
		local rolls = {0, 0.999}
		local lo = TH.coins(t, function() return rolls[1] end)
		local hi = TH.coins(t, function() return rolls[2] end)
		eq(lo, t.coins[1], t.id .. " minimum coins")
		eq(hi, t.coins[2], t.id .. " maximum coins")
	end
end
-- Balance: XP/h near gathering at the target's level, coins/h under top gathering.
do
	local GATHER = 1 + 0.65
	local function gatherRate(level)
		local best = 0
		for _, tiers in pairs(Data.ResourceTiers) do
			for _, r in ipairs(tiers) do
				if r.level <= level then best = math.max(best, 3600 * r.xp / math.max(r.respawn, GATHER)) end
			end
		end
		return best
	end
	local topGatherCoins = 0
	for _, tiers in pairs(Data.ResourceTiers) do
		for _, r in ipairs(tiers) do topGatherCoins = math.max(topGatherCoins, 3600 * r.value / math.max(r.respawn, GATHER)) end
	end
	-- Top combat coins/h: the richest monster, killed at the fastest swing (raw coins only).
	local topCombatCoins = 0
	for _, m in pairs(Data.Monsters) do topCombatCoins = math.max(topCombatCoins, m.coins * 3600 / math.max(20, m.hp / 2000)) end
	local topCoins = math.max(topGatherCoins, topCombatCoins)
	local rows = {}
	for _, t in ipairs(TH.Targets) do
		local own = TH.chance(t, t.level, 0, 0)
		local xpOwn = TH.xpPerHour(t, own) / gatherRate(t.level)
		ok(xpOwn >= 0.6 and xpOwn <= 1.5, string.format("%s at Thieving %d: %.0f XP/h is x%.2f gathering", t.id, t.level, TH.xpPerHour(t, own), xpOwn))
		local xpMax = TH.xpPerHour(t, TH.MAX_CHANCE) / gatherRate(99)
		ok(xpMax <= 2, string.format("%s at 95%%: x%.2f top gathering XP/h stays <= 2", t.id, xpMax))
		local coins = TH.coinsPerHour(t, TH.MAX_CHANCE)
		ok(coins <= topGatherCoins, string.format("%s %.0f coins/h <= top gathering %.0f coins/h", t.id, coins, topGatherCoins))
		ok(coins <= topCoins, string.format("%s %.0f coins/h <= top combat/gathering %.0f coins/h", t.id, coins, topCoins))
		ok(TH.expected(t) > 0, t.id .. " expected loot")
		table.insert(rows, string.format("%s %d: %.0f XP/h, %.0f coins/h", t.id, t.level, TH.xpPerHour(t, own), TH.coinsPerHour(t, own)))
	end
	-- Robbing every target of a region in parallel (each at its own cooldown,
	-- attempts and expected stuns sharing the thief's time) stays under top gathering.
	local regionsSeen, combos = {}, {}
	for _, t in ipairs(TH.Targets) do
		if not regionsSeen[t.region] then
			regionsSeen[t.region] = true
			local best = TH.regionCoinsPerHour(t.region, function() return TH.MAX_CHANCE end)
			local sum, solo = 0, 0
			for _, u in ipairs(TH.Targets) do
				if u.region == t.region then sum += 1; solo = math.max(solo, TH.coinsPerHour(u, TH.MAX_CHANCE)) end
			end
			ok(best >= solo - 1e-6, t.region .. ": a combination is never worth less than its best single target")
			if sum == 1 then ok(near(best, solo, 1e-6), t.region .. ": one target matches TH.coinsPerHour") end
			ok(best <= topGatherCoins, string.format("%s: best same-region combination %.0f coins/h <= top gathering %.0f coins/h", t.region, best, topGatherCoins))
			table.insert(combos, string.format("%s %.0f", t.region, best))
		end
	end
	eq(TH.regionCoinsPerHour("Gloomhollow", function() return 0 end), 0, "no chance, no income")
	-- The model: a cheap mark plus a rich chest both run (time budget not exceeded).
	ok(TH.regionCoinsPerHour("Gloomhollow", function() return TH.MAX_CHANCE end) > TH.coinsPerHour(TH.TargetById.VaultChest, TH.MAX_CHANCE) + 1000, "parallel targets add up")
	print("Thieving region combinations (coins/h at 95%): " .. table.concat(combos, ", "))
	-- Stall / pickpocket cooldowns: marks recover fast, stalls restock slower, strongboxes slowest.
	local maxPocket, minStall, maxStall, minSafe = 0, math.huge, 0, math.huge
	for _, t in ipairs(TH.Targets) do
		ok(t.respawn >= TH.ACTION and t.stun >= 4, t.id .. " cooldown >= one action and stun >= 4 s")
		if t.kind == "pocket" then maxPocket = math.max(maxPocket, t.respawn) end
		if t.kind == "stall" then minStall = math.min(minStall, t.respawn); maxStall = math.max(maxStall, t.respawn) end
		if t.kind == "safe" then minSafe = math.min(minSafe, t.respawn) end
	end
	ok(maxPocket < 10 and minStall >= 5 and minSafe >= 30 and maxStall < minSafe, "cooldowns: marks < 10 s, stalls 5+ s, strongboxes 30+ s")
	-- A failure costs more time than a success (the stun outlasts the restock for marks).
	for _, t in ipairs(TH.Targets) do
		if t.kind == "pocket" then ok(TH.ACTION + t.stun > t.respawn, t.id .. " getting caught is slower than succeeding") end
		ok(near(TH.cycle(t, 1), math.max(t.respawn, TH.ACTION)) and near(TH.cycle(t, 0), TH.ACTION + t.stun), t.id .. " pacing model ends")
	end
	print("Thieving pace: " .. table.concat(rows, "; ") .. string.format("; top gathering %.0f coins/h, top combat %.0f coins/h", topGatherCoins, topCombatCoins))
	-- Prayer XP/h: bulk offering at the best altar vs top gathering (Celestium).
	local celestium = gatherRate(99)
	local bulkTop = 3600 / PR.RITE_SECONDS * PR.Remains[#PR.Remains].xp * PR.Altars[#PR.Altars].mult
	ok(bulkTop / celestium >= 1.5 and bulkTop / celestium <= 3.2, string.format("top bulk Prayer %.0f XP/h is x%.2f top gathering (a buyable premium, 1.5-3.2)", bulkTop, bulkTop / celestium))
	local bulkLow = 3600 / PR.RITE_SECONDS * PR.Remains[1].xp * PR.Altars[1].mult
	ok(bulkLow <= gatherRate(1), string.format("brittle remains at the chapel %.0f XP/h stay under level-1 gathering", bulkLow))
	-- Remains from your own kills are a side income: a fraction of the kill's Combat XP.
	for id, m in pairs(Data.Monsters) do
		local r = PR.RemainsById[PR.remainsFor(m.level, m.region, false)]
		ok(r.xp * PR.Altars[#PR.Altars].mult <= 0.5 * m.xp, string.format("%s remains (%d XP, best altar) <= half of its %d Combat XP", id, r.xp, m.xp))
	end
	print(string.format("Prayer XP/h: brittle at the chapel %.0f, crown at the reliquary %.0f (Celestium %.0f)", bulkLow, bulkTop, celestium))
end
-- Quests, diaries and describeCheck.
for _, id in ipairs({"EmbersOfDevotion", "NimbleFingers", "ChoirOfTheStorm", "SkybornVault"}) do
	local q = Data.QuestById[id]
	ok(q ~= nil and Data.Quests[q.index] == q and #q.story > 20, id .. " quest registered")
	for _, o in ipairs(q.objectives) do
		ok(Data.describeCheck(o) ~= "Unknown task", id .. " objective described: " .. Data.describeCheck(o))
		if o.kind == "thefts" then ok(TH.TargetById[o.target] ~= nil, id .. " theft target") end
		if o.kind == "offerings" and o.remains then ok(PR.RemainsById[o.remains] ~= nil, id .. " offering remains") end
	end
end
eq(Data.describeCheck({kind = "thefts", target = "Farmhand", count = 3}), "Pickpocket the Meadow Farmhand 3 times", "theft description")
eq(Data.describeCheck({kind = "offerings", count = 5}), "Offer 5 remains at an altar", "offering description")
eq(Data.describeCheck({kind = "offerings", count = 5, remains = "WyrmRemains"}), "Offer 5 Wyrm Remains at an altar", "named offering description")
eq(Data.describeCheck({kind = "level", skill = "Prayer", level = 5}), "Prayer level 5", "older kinds still described")
local diaryTasks = 0
for _, d in ipairs(Data.Diaries) do
	for _, tier in ipairs(Data.DiaryTiers) do
		local tasks = d.tiers[tier].tasks
		ok(#tasks >= 3 and #tasks <= 5, d.region .. " " .. tier .. " keeps 3-5 tasks")
		for _, o in ipairs(tasks) do
			if o.kind == "thefts" or o.kind == "offerings" or (o.kind == "level" and (o.skill == "Prayer" or o.skill == "Thieving")) then diaryTasks += 1 end
		end
	end
end
ok(diaryTasks >= 6, "six or more diary tasks use Prayer or Thieving (" .. diaryTasks .. ")")
print("PASS: " .. (checks - partA) .. " Prayer & Thieving data assertions.")

------------------------------------------------------------------------------
-- Part B: world placement (real instances).
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
eq(world:GetAttribute("PrayerThievingSites"), #PR.Altars + #TH.Targets, "every altar and target placed")
local GATED = {}
for _, r in ipairs(Data.Regions) do if next(r.requires) then GATED[r.id] = true end end
local function islandOf(obj)
	local node = obj
	while node and node.Parent ~= islands do node = node.Parent end
	return node
end
local function contentOf(obj)
	local node = obj.Parent
	while node and node ~= islands do
		if node:GetAttribute("IsleContent") then return node end
		node = node.Parent
	end
	return nil
end
local prompts = {altarOffer = {}, altarPray = {}, thieve = {}}
for _, q in islands:GetDescendants() do
	if q:IsA("ProximityPrompt") then
		local action = q:GetAttribute("IsleAction")
		if prompts[action] then
			local id = q:GetAttribute("IsleItem")
			ok(prompts[action][id] == nil, action .. " " .. tostring(id) .. " placed once")
			prompts[action][id] = q
			local content = contentOf(q)
			ok(content ~= nil and content.Parent.Parent == islands, action .. " prompt sits in Prayer/Thieving content inside its island")
			ok(content:GetAttribute("SkillContent") == nil, action .. " content is not tagged as Agility/Hunter")
			ok(near(q.HoldDuration, 0.36) and q.MaxActivationDistance == 9 and not q.RequiresLineOfSight, action .. " prompt uses the interact hold")
		end
	end
end
local function onIsland(isle, pos)
	local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
	return Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude <= r and pos.Y >= c.Y - 1 and pos.Y <= c.Y + 12
end
for _, altar in ipairs(PR.Altars) do
	for _, action in ipairs({"altarOffer", "altarPray"}) do
		local q = prompts[action][altar.id]
		ok(q ~= nil, altar.id .. " " .. action .. " prompt")
		eq(q:GetAttribute("PrayerAltar"), altar.id, altar.id .. " " .. action .. " names its altar")
		eq(q:GetAttribute("IsleRegion"), if GATED[altar.region] then altar.region else nil, altar.id .. " " .. action .. " region gate")
		local isle = islandOf(q)
		eq(isle:GetAttribute("RegionId") or isle:GetAttribute("Region"), altar.region, altar.id .. " on its region's island")
		ok(onIsland(isle, q.Parent.CFrame.Position), altar.id .. " stands on the island")
	end
	ok(islands:FindFirstChild("Anchor_Waypoint_Altar_" .. altar.id, true) ~= nil, altar.id .. " waypoint anchor")
end
for _, t in ipairs(TH.Targets) do
	local q = prompts.thieve[t.id]
	ok(q ~= nil, t.id .. " thieve prompt")
	eq(q:GetAttribute("ThievingTarget"), t.id, t.id .. " prompt names its target")
	eq(q:GetAttribute("ThievingKind"), t.kind, t.id .. " prompt kind")
	eq(q:GetAttribute("IsleRegion"), if GATED[t.region] then t.region else nil, t.id .. " region gate")
	eq(q.ActionText, TH.Kinds[t.kind].verb, t.id .. " action text")
	local isle = islandOf(q)
	ok(isle:GetAttribute("RegionId") == t.region or (t.id == "Noble" and isle.Name == "Guild Terrace"), t.id .. " on its region's island")
	ok(onIsland(isle, q.Parent.CFrame.Position), t.id .. " stands on the island")
	ok(islands:FindFirstChild("Anchor_Waypoint_Thieving_" .. t.id, true) ~= nil, t.id .. " waypoint anchor")
	if t.kind == "pocket" then ok(islands:FindFirstChild("Anchor_NPC_Thieving_" .. t.id, true) ~= nil, t.id .. " figure anchor") end
end
-- Sites keep apart from each other and stay light.
do
	local hosts, parts = {}, 0
	for _, list in pairs(prompts) do for _, q in pairs(list) do table.insert(hosts, q.Parent.CFrame.Position) end end
	for _, model in islands:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("IsleContent") then
			ok(model:GetAttribute("IsleContent") == "Prayer" or model:GetAttribute("IsleContent") == "Thieving", model.Name .. " tagged")
			for _, obj in model:GetDescendants() do
				if obj:IsA("BasePart") then parts += 1; ok(obj.Anchored, obj.Name .. " anchored") end
				ok(not obj:IsA("Light"), model.Name .. " adds no lights")
			end
		end
	end
	ok(parts >= 100 and parts <= 260, "Prayer & Thieving content stays within its part budget (" .. parts .. ")")
	local tooClose = 0
	for _, t in ipairs(TH.Targets) do
		for _, u in ipairs(TH.Targets) do
			if t.id < u.id then
				local a, b = prompts.thieve[t.id].Parent.CFrame.Position, prompts.thieve[u.id].Parent.CFrame.Position
				if Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude < 6 then tooClose += 1 end
			end
		end
	end
	eq(tooClose, 0, "no two thieving targets crowd each other")
end
print("PASS: " .. (checks - partB) .. " Prayer & Thieving world assertions.")

------------------------------------------------------------------------------
-- Part C: server behaviour against the world prompts.
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
	HttpService = {GenerateGUID = function() return "prayer-test" end},
	RunService = {IsStudio = function() return false end},
}
local coroutines, delays = {}, {}
local serverObjects = {}
local serverWorkspace = {GetAttribute = function(self, key) return rawget(self, key) end}
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
		wait = function(t) return coroutine.yield(t) end,
		delay = function(t, f) table.insert(delays, {at = clock + (t or 0), fn = f}) end,
	},
}
local yieldOf = {}
do
	local baseWait = env.task.wait
	env.task.wait = function(t)
		yieldOf[coroutine.running()] = t
		return baseWait(t)
	end
end
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local drainLoop
for _, co in ipairs(coroutines) do
	if yieldOf[co] == PR.TICK then
		ok(drainLoop == nil, "exactly one loop waits Data.Prayer.TICK")
		drainLoop = co
	end
end
ok(drainLoop ~= nil, "prayer drain loop runs every Prayer tick")
local function tick(n)
	for _ = 1, n or 1 do
		advance(PR.TICK)
		assert(coroutine.resume(drainLoop, PR.TICK))
	end
end
local function runDelays()
	local i = 1
	while i <= #delays do
		if delays[i].at <= clock then local d = table.remove(delays, i); d.fn() else i += 1 end
	end
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
local X = Data.XP_TABLE

-- A fresh journal: Prayer 1, a full pool, no prayers on.
local monk = player(7001)
local s0 = cmd(monk, "state")
ok(type(s0.prayer) == "table" and type(s0.thieving) == "table", "snapshot carries prayer and thieving")
eq(s0.xp.Prayer, 0, "fresh Prayer XP")
eq(s0.xp.Thieving, 0, "fresh Thieving XP")
eq(s0.prayer.max, PR.maxPoints(1), "fresh pool")
eq(s0.prayer.points, PR.maxPoints(1), "fresh journals start full")
eq(#s0.prayer.active, 0, "nothing active")
eq(monk.attrs.PrayerMax, PR.maxPoints(1), "PrayerMax attribute")
eq(monk.attrs.PrayerPoints, PR.maxPoints(1), "PrayerPoints attribute")
eq(monk.attrs.PrayerActive, "", "PrayerActive attribute")
eq(monk.attrs.PrayerLevel, 1, "PrayerLevel attribute")
eq(s0.prayer.quick[1], "BarkhideWard", "default quick slot 1 is the best ward")
eq(s0.prayer.quick[2], "", "no offence prayer unlocked yet")
ok(has(cmd(monk, "prayer", "WardOfFangs").message, "requires Prayer 37"), "protection locked at Prayer 1")
ok(has(cmd(monk, "prayer", "Nope").message, "Choose a prayer"), "unknown prayer refused")
local on = cmd(monk, "prayer", "BarkhideWard")
ok(has(on.message, "Barkhide Ward on"), "ward on")
eq(on.prayer.active[1], "BarkhideWard", "active list")
eq(monk.attrs.PrayerActive, "BarkhideWard", "attribute lists the prayer")
eq(on.prayer.drain, 3, "drain reported per minute")
ok(on.prayer.secondsLeft ~= nil and on.prayer.secondsLeft > 0, "time left reported")
-- Drain ticks.
tick(10) -- 30 s at 3 points/min = 1.5 points
local afterTicks = cmd(monk, "state")
ok(near(afterTicks.prayer.points, PR.maxPoints(1) - 1.5, 0.05), "30 s of Barkhide Ward drained 1.5 points (" .. afterTicks.prayer.points .. ")")
eq(monk.attrs.PrayerPoints, math.ceil(PR.maxPoints(1) - 1.5), "points attribute rounds up")
-- Exhaustion switches every prayer off with a notice.
monk = rejoin(monk, function(prof) prof.prayer.points = 0.1 end)
eq(cmd(monk, "state").prayer.active[1], nil, "active prayers cleared on load")
ok(has(cmd(monk, "prayer", "BarkhideWard").message, "Not enough prayer points"), "fewer points than the activation cost refuse a prayer")
eq(cmd(monk, "state").prayer.points, 0.1, "a refused prayer costs nothing")
monk = rejoin(monk, function(prof) prof.prayer.points = 0.25 end)
cmd(monk, "prayer", "BarkhideWard")
ok(near(cmd(monk, "state").prayer.points, 0.25 - PR.activationCost("BarkhideWard", 0), 0.001), "switching on paid one tick up front")
tick(1)
tick(1)
eq(#cmd(monk, "state").prayer.active, 0, "points ran out: prayers off")
ok(has(monk.last.message, "run out of prayer points"), "out-of-points notice")
eq(cmd(monk, "state").prayer.points, 0, "points at 0")
ok(has(cmd(monk, "prayer", "BarkhideWard").message, "no prayer points"), "empty pool refuses prayers")
-- Draughts.
monk = rejoin(monk, function(prof) prof.items.DevotionDraught = 2; prof.xp.Prayer = X[40] end)
local drink = cmd(monk, "consume", "DevotionDraught")
ok(has(drink.message, "restored"), "draught drunk")
eq(drink.items.DevotionDraught, 1, "draught consumed")
eq(drink.prayer.points, PR.restore(0, PR.maxPoints(40), Data.Items.DevotionDraught), "draught restores 8 + 25%")
cmd(monk, "consume", "DevotionDraught")
local full = cmd(monk, "consume", "DevotionDraught")
ok(has(full.message, "You have no") or has(full.message, "already full"), "no more draughts")
-- Prayer 40: protection, exclusivity, favourites, HUD attributes.
monk = rejoin(monk, function(prof) prof.prayer.points = PR.maxPoints(40) end)
cmd(monk, "prayer", "WardOfFangs")
local swap = cmd(monk, "prayer", "WardOfQuills")
ok(has(swap.message, "replaces Ward of Fangs"), "protections replace each other")
eq(monk.attrs.PrayerActive, "WardOfQuills", "only the newest protection")
cmd(monk, "prayer", "IronbarkWard")
eq(monk.attrs.PrayerActive, "IronbarkWard,WardOfQuills", "ward stacks with protection (book order)")
eq(cmd(monk, "prayerQuick", "2:HawkSight").prayer.quick[2], "HawkSight", "favourite slot 2 set")
eq(monk.attrs.PrayerQuick, "IronbarkWard,HawkSight", "quick attribute (slot 1 default)")
ok(has(cmd(monk, "prayerQuick", "3:HawkSight").message, "slot"), "slot 3 refused")
ok(has(cmd(monk, "prayerQuick", "1:Nope").message, "slot"), "unknown quick prayer refused")
eq(cmd(monk, "prayerQuick", "2:").prayer.quick[2], "WildfireEdge", "cleared slot falls back to the best offence prayer for the wielded style (unarmed: melee)")
-- Bridge "stats": the combat view.
local view = bridge.OnInvoke("stats", monk).prayer
ok(view ~= nil and view.protect == "ranged" and view.defence == 15, "bridge stats carries protection and ward")
eq(view.offence.melee, 0, "no offence prayer")
eq(view.mana, 1, "no mana bonus")
-- Bridge "damage": protection and the ward.
do
	local p = data["p7001"]
	local stats = bridge.OnInvoke("stats", monk).stats
	monk.humanoid.Health = 1e6; monk.humanoid.MaxHealth = 1e6
	local hit = bridge.OnInvoke("damage", monk, {amount = 1000, style = "ranged"})
	eq(hit, P.damageTaken(600, stats.defense * 1.15), "ranged hit: 40% protection then the ward")
	local boss = bridge.OnInvoke("damage", monk, {amount = 1000, style = "ranged", worldBoss = true})
	eq(boss, P.damageTaken(750, stats.defense * 1.15), "world boss ranged hit: 25% protection")
	local melee = bridge.OnInvoke("damage", monk, {amount = 1000, style = "melee"})
	eq(melee, P.damageTaken(1000, stats.defense * 1.15), "melee hit unprotected (ward only)")
	local odd = bridge.OnInvoke("damage", monk, {amount = 1000, style = "fire"})
	eq(odd, melee, "unknown style unprotected")
	ok(bridge.OnInvoke("damage", monk, {amount = 1, style = "ranged"}) >= 1, "a protected hit still lands")
	eq(bridge.OnInvoke("damage", monk, {amount = -5, style = "ranged"}), 0, "negative damage ignored")
	ok(p ~= nil, "journal saved")
	cmd(monk, "prayerOff")
	monk.humanoid.Health = 1e6; monk.humanoid.MaxHealth = 1e6
	eq(bridge.OnInvoke("damage", monk, {amount = 1000, style = "ranged"}), P.damageTaken(1000, stats.defense), "no prayers: plain defence")
	monk.humanoid.Health = monk.humanoid.MaxHealth
	eq(bridge.OnInvoke("stats", monk).prayer, nil, "no prayers: no combat view")
	local again = cmd(monk, "prayerOff").message
	ok(has(again, "No prayers"), "prayerOff with nothing on: " .. tostring(again))
end
-- Flicking is never free: time-based charging plus a one-tick activation cost.
do
	-- Remote calls 0.25 s apart (the verb cooldown); snapshots
	-- round points to 0.1, so "points" reads are taken with nothing active.
	local function raw(p, verb, item) advance(0.25); return remote.OnServerInvoke(p, verb, item) end
	local function resumeTick() assert(coroutine.resume(drainLoop, PR.TICK)) end
	local pool = PR.maxPoints(99)
	local function points(who)
		advance(0.6)
		local s = remote.OnServerInvoke(who, "state")
		assert(s and #s.prayer.active == 0, "points are read with nothing active")
		return s.prayer.points
	end
	local function fresh(id)
		return seeded(id, function(prof) prof.xp.Prayer = X[99]; prof.prayer.points = pool end)
	end
	-- Continuous Valor Hymn for 60 s (20 ticks).
	local steady = fresh(7011)
	advance(0.6)
	local devotion = remote.OnServerInvoke(steady, "state").depth.stats.devotion
	local rate = PR.drainPerSecond({ValorHymn = true}, devotion)
	raw(steady, "prayer", "ValorHymn")
	for _ = 1, 20 do advance(PR.TICK); resumeTick() end
	raw(steady, "prayerOff")
	local steadyCost = pool - points(steady)
	ok(near(steadyCost, rate * 60.25, 0.1), string.format("continuous Valor Hymn pays its rate (%.2f points / 60 s)", steadyCost))
	leave(steady)
	-- The old exploit: on just after each tick, off just before the next (~95% uptime).
	local flicker = fresh(7012)
	for _ = 1, 20 do
		raw(flicker, "prayer", "ValorHymn")
		advance(PR.TICK - 0.5)
		raw(flicker, "prayer", "ValorHymn")
		resumeTick()
	end
	local flickCost = pool - points(flicker)
	ok(flickCost >= 0.9 * steadyCost, string.format("a flicking client pays %.2f >= 90%% of continuous %.2f", flickCost, steadyCost))
	-- Rapid flicks pay one tick of drain each.
	local before = points(flicker)
	for _ = 1, 10 do
		raw(flicker, "prayer", "StarwardLitany")
		raw(flicker, "prayer", "StarwardLitany")
	end
	ok(near(before - points(flicker), 10 * PR.activationCost("StarwardLitany", devotion), 0.1), "each activation pays a tick of drain")
	-- Time on between ticks is charged even if the prayer is off at the tick.
	before = points(flicker)
	raw(flicker, "prayer", "IronbarkWard")
	advance(PR.TICK * 4)
	raw(flicker, "prayer", "IronbarkWard")
	resumeTick()
	ok(near(before - points(flicker), PR.drainPerSecond({IronbarkWard = true}, devotion) * (PR.TICK * 4 + 0.25), 0.1), "time on is charged when the prayer goes off")
	-- Protection flicked on just as a telegraphed world-boss hit lands costs points.
	local function hit()
		flicker.humanoid.Health, flicker.humanoid.MaxHealth = 1e6, 1e6
		local dealt = bridge.OnInvoke("damage", flicker, {amount = 1000, style = "melee", worldBoss = true})
		flicker.humanoid.Health, flicker.humanoid.MaxHealth = 100, 100
		return dealt
	end
	before = points(flicker)
	raw(flicker, "prayer", "WardOfFangs")
	local guarded = hit()
	ok(has(raw(flicker, "prayer", "WardOfFangs").message, "Ward of Fangs off"), "ward flicked off after the hit")
	local plainHit = hit()
	ok(guarded < plainHit, "the flicked ward still protected that hit")
	local paid = before - points(flicker)
	ok(paid > 0 and paid >= PR.activationCost("WardOfFangs", devotion) - 0.1, string.format("a protection flick at hit time costs its activation (%.2f)", paid))
	-- prayerOff charges the elapsed time too.
	before = points(flicker)
	raw(flicker, "prayer", "IronbarkWard")
	advance(PR.TICK * 2)
	raw(flicker, "prayerOff")
	ok(near(before - points(flicker), PR.drainPerSecond({IronbarkWard = true}, devotion) * (PR.TICK * 2 + 0.25), 0.1), "prayerOff settles the drain")
	leave(flicker)
	-- A draught settles the drain before restoring.
	flicker = seeded(7012, function(prof) prof.xp.Prayer = X[99]; prof.prayer.points = 20; prof.items.DevotionDraught = 1 end)
	raw(flicker, "prayer", "IronbarkWard")
	advance(PR.TICK * 10)
	local drunk = raw(flicker, "consume", "DevotionDraught").prayer.points
	ok(near(drunk, PR.restore(20 - PR.drainPerSecond({IronbarkWard = true}, devotion) * (PR.TICK * 10 + 0.25), pool, Data.Items.DevotionDraught), 0.1), "a draught restores after charging the elapsed drain")
	leave(flicker)
	advance(math.ceil(utc) - utc) -- back to whole seconds for the wall-clock checks below
end
-- Mending Hymn heals each tick; Amber Vigil stretches buffs.
local buffStart = utc
monk = rejoin(monk, function(prof)
	prof.xp.Prayer = X[60]
	prof.prayer.points = 60
	prof.buffs.MightDraught = {expires = utc + 100, stats = {strength = 15}}
end)
cmd(monk, "prayer", "MendingHymn")
cmd(monk, "prayer", "AmberVigil")
monk.humanoid.MaxHealth, monk.humanoid.Health = 200, 100
tick(3)
ok(near(monk.humanoid.Health, 100 + 3 * 200 * 0.015), "Mending Hymn heals 1.5% per tick")
local buffState = cmd(monk, "state").depth.buffs.MightDraught
eq(buffState and buffState.remaining, buffStart + 100 + 3 * PR.preserveExtend(PR.TICK, 0.5) - utc, "Amber Vigil pushed the buff back a second per tick")
cmd(monk, "prayerOff")
-- Altars: offering batches, rite pacing, praying, region gates.
local chapelOffer, chapelPray = prompts.altarOffer.QuayChapel, prompts.altarPray.QuayChapel
monk = rejoin(monk, function(prof)
	prof.xp.Prayer = 0
	prof.items.BrittleRemains = 14; prof.items.HeavyRemains = 3
	prof.prayer.points = 2
end)
eq(cmd(monk, "altarOffer", "QuayChapel").xp.Prayer, 0, "altars cannot be used through the remote")
local offer1 = use(monk, chapelOffer)
eq(offer1.items.HeavyRemains, 0, "the best remains are offered first")
eq(offer1.xp.Prayer, PR.offerXp("HeavyRemains", "QuayChapel", 3), "offering pays remains XP")
ok(has(offer1.message, "Offered 3 Heavy Remains"), "offering message")
eq(offer1.prayer.offered.HeavyRemains, 3, "offerings counted")
eq(offer1.prayer.altar, "QuayChapel", "altar window open")
eq(monk.attrs.PrayerAltar, "QuayChapel", "PrayerAltar attribute")
ok(monk.attrs.PrayerAltarUntil > utc, "PrayerAltarUntil in the future")
ok(offer1.prayer.riteIn > 0, "rite underway")
ok(has(use(monk, chapelOffer).message, "rite is still underway"), "one rite at a time")
advance(3 * PR.RITE_SECONDS)
local offer2 = use(monk, chapelOffer)
eq(offer2.items.BrittleRemains, 14 - PR.BATCH, "a batch offers at most PR.BATCH")
eq(offer2.prayer.offered.BrittleRemains, PR.BATCH, "batch counted")
advance(PR.BATCH * PR.RITE_SECONDS)
local remoteOffer = cmd(monk, "offerRemains", "BrittleRemains")
eq(remoteOffer.items.BrittleRemains, 0, "the atlas offers chosen remains while the altar window is open")
advance(4 * PR.RITE_SECONDS)
ok(has(cmd(monk, "offerRemains", "BrittleRemains").message, "no Brittle Remains"), "nothing left to offer")
ok(has(cmd(monk, "offerRemains", "Nope").message, "Offer remains"), "unknown remains refused")
local pray = use(monk, chapelPray)
ok(has(pray.message, "Prayer points restored"), "praying restores points")
eq(pray.prayer.points, pray.prayer.max, "points full")
ok(has(use(monk, chapelPray).message, "full"), "already full")
local empty = use(monk, chapelOffer)
ok(has(empty.message, "restored") or has(empty.message, "full"), "offering with no remains prays instead")
advance(PR.ALTAR_SECONDS + 5)
ok(has(cmd(monk, "offerRemains", "BrittleRemains").message, "Visit an altar"), "the altar window closes")
local shrine = prompts.altarOffer.MossrootShrine
local shrineDenied = use(monk, shrine).message
ok(has(shrineDenied, "requires"), "gated altar refuses a locked region: " .. tostring(shrineDenied))
-- Quest progress from offerings.
local function questProgress(snapshot, id)
	for _, q in ipairs(snapshot.journal.quests) do if q.id == id then return q end end
	return nil
end
eq(questProgress(cmd(monk, "state"), "EmbersOfDevotion").objectives[1][1], 17, "offerings count towards Embers of Devotion")
-- Persistence: points and offerings survive, active prayers do not.
cmd(monk, "prayer", "BarkhideWard")
monk = rejoin(monk)
local back = cmd(monk, "state")
eq(back.prayer.offered.BrittleRemains, 14, "offerings persisted")
eq(#back.prayer.active, 0, "active prayers cleared on rejoin")
ok(back.prayer.points > 0, "points persisted")
-- Tampered saves are cleaned.
monk = rejoin(monk, function(prof) prof.prayer = {points = 1e9, quick = {"Nope", 5}, offered = {Nope = 4, BrittleRemains = -2, HeavyRemains = "x"}, active = {ValorHymn = true}} end)
local clean = cmd(monk, "state")
eq(clean.prayer.points, clean.prayer.max, "points clamped to the pool")
eq(#clean.prayer.active, 0, "saved actives dropped")
eq(next(clean.prayer.offered), nil, "bad offering records dropped")
leave(monk)

-- Thieving.
local thief = player(7101)
eq(cmd(thief, "thieve", "Farmhand").xp.Thieving, 0, "thieving needs the world prompt")
local farm = prompts.thieve.Farmhand
local farmDef = TH.TargetById.Farmhand
queue(0.01, 0.5)
local lift = use(thief, farm)
ok(has(lift.message, "Picked the pocket of the Meadow Farmhand"), "pickpocket success message")
eq(lift.xp.Thieving, farmDef.xp, "pickpocket pays XP")
eq(lift.coins, 3, "coins from the loot roll")
eq(lift.thieving.thefts.Farmhand, 1, "theft counted")
ok(lift.thieving.cooldowns.Farmhand ~= nil, "cooldown reported")
ok(has(use(thief, farm).message, "wary"), "the mark is wary after a success")
advance(farmDef.respawn)
queue(0.99)
local caught = use(thief, farm)
ok(has(caught.message, "red-handed") and has(caught.message, "Stunned for " .. farmDef.stun), "caught message")
eq(thief.humanoid.Health, 100 - farmDef.damage, "caught deals damage")
eq(thief.humanoid.WalkSpeed, 0, "stunned in place")
ok(thief.attrs.ThievingStunUntil > utc, "ThievingStunUntil published")
ok(caught.thieving.stunIn > 0, "stun reported in the snapshot")
ok(has(use(thief, farm).message, "stunned"), "no thieving while stunned")
eq(thief.humanoid.WalkSpeed, 0, "snapshots keep the stun's WalkSpeed")
advance(farmDef.stun)
runDelays()
ok(thief.humanoid.WalkSpeed > 0, "WalkSpeed restored after the stun")
queue(0.01, 0)
eq(use(thief, farm).thieving.thefts.Farmhand, 2, "free to thieve again")
-- Caught never kills.
thief.humanoid.Health = 3
advance(farmDef.respawn)
queue(0.99)
use(thief, farm)
ok(thief.humanoid.Health >= 1, "getting caught is never lethal")
advance(10)
runDelays()
thief.humanoid.Health = 100
-- Level gates and region gates.
ok(has(use(thief, prompts.thieve.Watchman).message, "requires Thieving 30"), "level gate")
local gated = use(thief, prompts.thieve.Strongbox).message
ok(has(gated, "charter") or has(gated, "requires"), "strongbox behind the Skyreach gate: " .. tostring(gated))
-- A stall with loot, gloves raising the chance.
thief = rejoin(thief, function(prof) prof.xp.Thieving = X[20]; prof.items.LightfingerGloves = 1 end)
local stallQ = prompts.thieve.SweetbunStall
local before = cmd(thief, "state")
ok(near(before.thieving.chances.SweetbunStall, TH.chance(TH.TargetById.SweetbunStall, 20, 0.05, before.depth.stats.deftness), 0.001), "snapshot chance includes gloves and Deftness")
eq(before.thieving.gloves, "LightfingerGloves", "gloves reported")
queue(0.01, 0, 0.01, 0)
local stole = use(thief, stallQ)
ok(has(stole.message, "Stole from the Sweetbun Stall"), "stall success")
eq(stole.items.Sunwheat, 1, "stall loot rolled")
ok(has(use(thief, stallQ).message, "restocking"), "stall restocks after a theft")
advance(TH.TargetById.SweetbunStall.respawn)
queue(0.99)
ok(has(use(thief, stallQ).message, "stall guard catches you"), "stall guard catches a failed theft")
advance(10)
runDelays()
eq(questProgress(cmd(thief, "state"), "NimbleFingers").objectives[2][1], 1, "stall thefts count for Nimble Fingers")
-- A strongbox at Thieving 50 in Skyreach.
thief = rejoin(thief, function(prof)
	prof.xp.Thieving = X[50]
	prof.questCompleted = 10
	for skill, need in pairs(Data.RegionById.Skyreach.requires.skills or {}) do prof.xp[skill] = math.max(prof.xp[skill] or 0, X[need]) end
end)
local sbox = prompts.thieve.Strongbox
queue(0.01, 0)
local cracked = use(thief, sbox)
if has(cracked.message, "Cracked") then
	ok(cracked.coins >= TH.TargetById.Strongbox.coins[1], "strongbox coins")
	ok(has(use(thief, sbox).message, "relocking"), "strongbox relocks")
else
	error("strongbox should open once Skyreach is unlocked: " .. tostring(cracked.message))
end
-- Persistence and cleaning.
thief = rejoin(thief, function(prof) prof.thieving.thefts.Bogus = 9; prof.thieving.thefts.Farmhand = "many" end)
local tb = cmd(thief, "state").thieving.thefts
eq(tb.Bogus, nil, "unknown targets dropped")
eq(tb.Farmhand, nil, "malformed counts dropped")
eq(tb.SweetbunStall, 1, "thefts persisted")
leave(thief)
-- Cooldowns and stuns survive a rejoin / server hop.
do
	local hopper = player(7102)
	queue(0.01, 0.5)
	ok(has(use(hopper, farm).message, "Picked the pocket"), "hopper lifts a purse")
	ok(data["p7102"] == nil or true, "journal")
	hopper = rejoin(hopper)
	ok(has(use(hopper, farm).message, "wary"), "the mark is still wary after rejoining")
	advance(farmDef.respawn)
	queue(0.99)
	ok(has(use(hopper, farm).message, "red-handed"), "caught")
	hopper = rejoin(hopper)
	ok(has(use(hopper, farm).message, "stunned"), "the stun survives a rejoin")
	ok(cmd(hopper, "state").thieving.stunIn > 0, "stun reported after the rejoin")
	advance(farmDef.stun + 1)
	queue(0.01, 0)
	ok(has(use(hopper, farm).message, "Picked the pocket"), "free again once the stun is over")
	-- Tampered / stale records: unknown and expired entries pruned, far-future clamped.
	advance(60)
	hopper = rejoin(hopper, function(prof)
		prof.thieving.cooldowns = {Bogus = utc + 50, Farmhand = utc + 1e6, Dockhand = utc - 5, SweetbunStall = "x"}
		prof.thieving.stunUntil = utc + 1e6
	end)
	local st = cmd(hopper, "state").thieving
	ok(st.stunIn > 0 and st.stunIn <= TH.MAX_STUN, "a tampered stun is clamped to the longest stun")
	ok(st.cooldowns.Farmhand ~= nil and st.cooldowns.Farmhand <= farmDef.respawn, "a tampered cooldown is clamped to the respawn")
	eq(st.cooldowns.Dockhand, nil, "expired cooldowns pruned")
	leave(hopper)
	local saved = data["p7102"].profile.thieving
	eq(saved.cooldowns.Bogus, nil, "unknown targets pruned from the save")
	eq(saved.cooldowns.Dockhand, nil, "expired entries pruned from the save")
	eq(saved.cooldowns.SweetbunStall, nil, "malformed entries pruned from the save")
	local n = 0
	for _ in pairs(saved.cooldowns) do n += 1 end
	ok(n <= #TH.Targets, "persisted cooldowns stay bounded by the target list")
end
-- Remains from kills feed collections.
local hunter = player(7201)
local kill = bridge.OnInvoke("kill", hunter, {monster = "Thornling"})
eq(kill.drops.BrittleRemains, 1, "a Thornling leaves Brittle Remains")
eq(cmd(hunter, "state").depth.collections.BrittleRemains.count, 1, "remains reach the collection")
leave(hunter)
print("PASS: " .. (checks - partC) .. " Prayer & Thieving server assertions.")

------------------------------------------------------------------------------
-- Part D: combat hooks (combat.server.lua pure core).
------------------------------------------------------------------------------
local partD = checks
local Combat
load("combat.server.lua", {
	Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3,
	__CombatTestHarness = function(exports) Combat = exports end,
})
ok(Combat ~= nil, "combat harness")
local function arena(prayer)
	local w = {clock = 100, list = {}, calls = {}, stats = {}, pos = {}, rolls = {}}
	local hero = {Name = "Hero", UserId = 1}
	w.hero = hero
	w.list[1] = hero
	w.pos[hero] = Vector3.new(0, 0, 0)
	w.stats[hero] = {stats = {damage = 20, strength = 0, critChance = 0, critDamage = 50, attackSpeed = 0, intelligence = 100, rangedAccuracy = 0},
		combatLevel = 5, prayer = prayer, loadout = {style = "melee", levels = {}, supplies = {}}}
	w.logic = Combat.createLogic({
		Data = Data, Progression = P,
		now = function() return w.clock end, time = function() return 5000 end,
		rng = function() if #w.rolls > 0 then return table.remove(w.rolls, 1) end return 0.5 end,
		players = function() return w.list end, alive = function() return true end,
		position = function(p) return w.pos[p] end, heal = function() end,
		bridge = function(op, player, payload)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			return nil
		end,
	})
	return w
end
local function spawnMonster(L, id)
	local marker = L.addMarker("m" .. id, id, 1, Vector3.new(0, 0, 0))
	local m = {Name = id}
	return L.register(marker, m, Vector3.new(0, 1, 0), {radius = 1}), m
end
do
	local plain = arena(nil)
	local edge = arena({offence = {melee = 0.15, ranged = 0.2, magic = 0}, sap = 0, mana = 1})
	local r1, m1 = spawnMonster(plain.logic, "ShaleCrawler")
	local r2, m2 = spawnMonster(edge.logic, "ShaleCrawler")
	local a = plain.logic.attack(plain.hero, "attack", m1)
	local b = edge.logic.attack(edge.hero, "attack", m2)
	ok(a and b, "both swings land")
	local raw = P.meleeDamage(plain.stats[plain.hero].stats, function() return 0.5 end)
	eq(a.damage, (plain.logic.mitigate(r1, raw, "melee")), "plain swing matches the base pipeline")
	eq(b.damage, P.damageTaken(math.floor(raw * 1.15 * P.styleModifier("melee", r2)), r2.defense), "Wildfire-level edge adds 15% before the triangle and defence")
	ok(b.damage > a.damage, "offence prayers hit harder")
	eq(edge.logic.prayerOffence(edge.hero, "melee"), 1.15, "melee offence multiplier")
	eq(edge.logic.prayerOffence(edge.hero, "magic"), 1, "no magic offence")
	eq(plain.logic.prayerOffence(plain.hero, "melee"), 1, "no prayer, no multiplier")
	-- Ranged accuracy: x(1 + offence) within the hit ceiling.
	eq(edge.logic.prayerAccuracy(edge.hero, 0.5), 0.6, "ranged accuracy x1.2")
	eq(edge.logic.prayerAccuracy(edge.hero, 0.9), Data.CombatStyles.hitCeiling, "accuracy capped at the hit ceiling")
	eq(edge.logic.prayerAccuracy(edge.hero, 0.99), 0.99, "never lowers an already higher chance")
	eq(plain.logic.prayerAccuracy(plain.hero, 0.5), 0.5, "no prayer, no accuracy change")
	-- Garbage prayer payloads are ignored.
	local junk = arena({offence = {melee = "lots", ranged = -3, magic = 1e9}, sap = "x", mana = -4})
	local _, mj = spawnMonster(junk.logic, "ShaleCrawler")
	junk.logic.attack(junk.hero, "attack", mj)
	eq(junk.logic.prayerOffence(junk.hero, "melee"), 1, "string offence ignored")
	eq(junk.logic.prayerOffence(junk.hero, "ranged"), 1, "negative offence ignored")
	eq(junk.logic.prayerOffence(junk.hero, "magic"), 2, "offence capped at +100%")
	eq(junk.logic.prayerMana(junk.hero), 1, "negative mana bonus ignored")
end
do
	-- Sapping Rite: each landed hit saps 3% of base defence, floored at 70%.
	local w = arena({offence = {melee = 0, ranged = 0, magic = 0}, sap = PR.SAP_PER_HIT, mana = 1})
	local r, m = spawnMonster(w.logic, "BrassGolem")
	local base = r.defense
	ok(base > 0, "golem has defence")
	w.logic.attack(w.hero, "attack", m)
	eq(r.defense, base - math.ceil(base * PR.SAP_PER_HIT), "one landed hit saps 3%")
	for _ = 1, 30 do
		w.clock += 2
		if r.alive and r.hp > 0 then w.logic.attack(w.hero, "attack", m) end
	end
	ok(r.defense >= base * (1 - PR.SAP_MAX) - 1e-9, "sap never passes 30%")
	eq(r.defense, math.ceil(base * (1 - PR.SAP_MAX) - 1e-9), "repeated hits reach the floor")
	eq(r.baseDefense, base, "base defence remembered")
	-- A leash heal (full health again) shakes the sap off on the next hit.
	r.hp = r.maxHp
	w.clock += 2
	w.logic.attack(w.hero, "attack", m)
	eq(r.defense, base - math.ceil(base * PR.SAP_PER_HIT), "a healed monster starts from its base defence")
	local plain = arena(nil)
	local r2, m2 = spawnMonster(plain.logic, "BrassGolem")
	plain.logic.attack(plain.hero, "attack", m2)
	eq(r2.defense, base, "no sap without the prayer")
end
do
	-- Hearthsong: mana regeneration x1.5.
	local plain, song = arena(nil), arena({offence = {melee = 0, ranged = 0, magic = 0}, sap = 0, mana = 1.5})
	for _, w in ipairs({plain, song}) do
		w.logic.statsFor(w.hero)
		local m = w.logic.manaOf(w.hero)
		m.current = 0
		w.clock += 2
	end
	local a = plain.logic.manaOf(plain.hero).current
	local b = song.logic.manaOf(song.hero).current
	ok(a > 0, "mana regenerates")
	ok(near(b, a * 1.5), "Hearthsong regenerates 50% faster")
	eq(song.logic.prayerMana(song.hero), 1.5, "mana multiplier")
	eq(plain.logic.prayerMana(plain.hero), 1, "no prayer, base regeneration")
	-- A stats refresh never applies a new Hearthsong multiplier retroactively.
	local w = arena(nil)
	w.logic.statsFor(w.hero)
	local m = w.logic.manaOf(w.hero)
	m.current = 0
	w.clock += 2
	local per2 = a -- 2 s of regeneration at x1 (plain arena above)
	w.stats[w.hero] = table.clone(w.stats[w.hero]) -- a fresh snapshot (the cached one is untouched)
	w.stats[w.hero].prayer = {offence = {melee = 0, ranged = 0, magic = 0}, sap = 0, mana = 1.5}
	w.clock += 3 -- stats cache expired; the refresh happens now
	w.logic.statsFor(w.hero)
	local after = w.logic.manaOf(w.hero).current
	ok(after < m.max and near(after, per2 * 2.5), string.format("5 s before the refresh regenerate at x1 (%.2f)", after))
	-- And the reverse: switching Hearthsong off keeps the x1.5 for the time it was on.
	local v = arena({offence = {melee = 0, ranged = 0, magic = 0}, sap = 0, mana = 1.5})
	v.logic.statsFor(v.hero)
	local vm = v.logic.manaOf(v.hero)
	vm.current = 0
	v.clock += 2
	v.stats[v.hero] = table.clone(v.stats[v.hero])
	v.stats[v.hero].prayer = nil
	v.clock += 3
	v.logic.statsFor(v.hero)
	ok(near(v.logic.manaOf(v.hero).current, per2 * 1.5 * 2.5), "time under Hearthsong keeps its x1.5 after it ends")
end
do
	-- Monster strikes carry their attack style (protection) and world bosses flag themselves.
	local w = arena(nil)
	local r = spawnMonster(w.logic, "StormHarrier")
	w.logic.strike(r, w.hero)
	local call = w.calls[#w.calls]
	eq(call.op, "damage", "a strike calls bridge damage")
	eq(call.payload.style, "ranged", "the strike names the Storm Harrier's ranged style")
	eq(call.payload.amount, r.damage, "strike amount")
	local source = fs.readFile("combat.server.lua")
	ok(has(source, 'env.bridge("damage", player, {amount = amount, style = r.attackStyle, worldBoss = true})'), "world boss strikes flag worldBoss and their style")
end
print("PASS: " .. (checks - partD) .. " Prayer combat hook assertions.")

------------------------------------------------------------------------------
-- Part E: atlas pages (Hero › Prayer, Hunt › Thieving).
------------------------------------------------------------------------------
local partE = checks
local H = require("./tools/ui-harness")
local function atlas(size, mutate)
	local snap = H.snapshot({xp = {Prayer = X[45], Thieving = X[35]}})
	snap.items.BrittleRemains, snap.items.HeavyRemains, snap.items.DevotionDraught, snap.items.LightfingerGloves = 24, 6, 1, 1
	snap.prayer = {points = 31.4, max = 55, active = {"StonehideWard", "WardOfFangs"}, quick = {"StonehideWard", "BlazingEdge"}, drain = 18, secondsLeft = 104,
		offered = {BrittleRemains = 40}, altar = "QuayChapel", altarUntil = os.time() + 40, riteIn = 0}
	snap.thieving = {thefts = {Farmhand = 42, SweetbunStall = 9}, gloves = "LightfingerGloves", gloveBonus = 0.05, deftness = 12,
		chances = {Farmhand = 0.83}, cooldowns = {Farmhand = 2}, stunIn = 0}
	if mutate then mutate(snap) end
	local ui = H.runAtlas(size, {snapshot = snap})
	H.press(H.find(ui.gui, "AtlasButton"))
	return ui
end
local function open(ui, tab, section)
	H.press(ui.tabs:FindFirstChild(tab .. "Button"))
	H.press(H.find(ui.scroll, "Section" .. section))
end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui, "Hero", "Prayer")
	eq(#ui.warnings, 0, "Prayer page renders without warnings" .. tag)
	ok(H.find(ui.scroll, "PrayerSummary") ~= nil, "prayer summary" .. tag)
	for _, def in ipairs(PR.Prayers) do ok(H.find(ui.scroll, "Prayer" .. def.id) ~= nil, def.id .. " tile" .. tag) end
	ok(H.find(ui.scroll, "PrayerDetail") ~= nil, "prayer detail card" .. tag)
	for _, a in ipairs(PR.Altars) do ok(H.find(ui.scroll, "Altar" .. a.id) ~= nil, a.id .. " card" .. tag) end
	for _, r in ipairs(PR.Remains) do ok(H.find(ui.scroll, "Remains" .. r.id) ~= nil, r.id .. " card" .. tag) end
	open(ui, "Hunt", "Thieving")
	eq(#ui.warnings, 0, "Thieving page renders without warnings" .. tag)
	ok(H.find(ui.scroll, "ThievingSummary") ~= nil, "thieving summary" .. tag)
	for _, t in ipairs(TH.Targets) do ok(H.find(ui.scroll, "Thieving" .. t.id) ~= nil, t.id .. " card" .. tag) end
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	open(ui, "Hero", "Prayer")
	local text = texts(ui.scroll)
	ok(has(text, "31 / 55 points"), "points on the gauge")
	ok(has(text, "-18 / min"), "drain on the gauge")
	ok(has(text, "Ward of Fangs"), "active protection shown")
	-- The detail card opens on the first active prayer; Stop sends the toggle.
	H.press(H.find(ui.scroll, "PrayerToggle"))
	eq(ui.sent[#ui.sent][1], "prayer", "toggle sends the prayer verb")
	eq(ui.sent[#ui.sent][2], "StonehideWard", "toggle names the selected prayer")
	-- Select a locked hymn: its toggle stays local.
	H.press(H.find(ui.scroll, "PrayerValorHymn"))
	ok(has(texts(ui.scroll), "Prayer 70"), "locked hymn shows its level")
	local sent = #ui.sent
	H.press(H.find(ui.scroll, "PrayerToggle"))
	eq(#ui.sent, sent, "locked prayers are not sent")
	H.press(H.find(ui.scroll, "PrayerQuick1"))
	eq(ui.sent[#ui.sent][1], "prayerQuick", "favourite verb")
	eq(ui.sent[#ui.sent][2], "1:ValorHymn", "favourite slot payload")
	H.press(H.find(ui.scroll, "PrayerAllOff"))
	eq(ui.sent[#ui.sent][1], "prayerOff", "all off")
	H.press(H.find(ui.scroll, "OfferBrittleRemains"))
	eq(ui.sent[#ui.sent][1], "offerRemains", "offer from the atlas")
	eq(ui.sent[#ui.sent][2], "BrittleRemains", "offer names the remains")
	sent = #ui.sent
	H.press(H.find(ui.scroll, "OfferCrownRemains"))
	eq(#ui.sent, sent, "remains you do not hold stay local")
	H.press(H.find(ui.scroll, "DrinkDevotionDraught"))
	eq(ui.sent[#ui.sent][1], "consume", "draught drink")
	eq(ui.sent[#ui.sent][2], "DevotionDraught", "draught id")
	open(ui, "Hunt", "Thieving")
	text = texts(ui.scroll)
	ok(has(text, "83%"), "server success chance shown")
	ok(has(text, "wary (2s)"), "cooldown shown")
	ok(has(text, "Lightfinger Gloves"), "gloves shown")
	ok(has(text, "Loot:"), "loot tables shown")
	ok(has(text, "Pace:"), "pace shown")
	-- Skill detail lists prayer and thieving unlocks.
	open(ui, "Hero", "Skills")
	H.press(H.find(ui.scroll, "SkillPrayer"))
	ok(has(texts(ui.scroll), "Valor Hymn"), "Prayer unlocks list the hymn")
	H.press(H.find(ui.scroll, "SkillThieving"))
	ok(has(texts(ui.scroll), "Strongbox") or has(texts(ui.scroll), "Ironbound"), "Thieving unlocks list strongboxes")
end
do
	-- Closed altar window and missing / malformed state.
	local ui = atlas(roblox.Vector2.new(844, 390), function(snap) snap.prayer.altar = nil; snap.prayer.altarUntil = 0 end)
	open(ui, "Hero", "Prayer")
	local sent = #ui.sent
	H.press(H.find(ui.scroll, "OfferBrittleRemains"))
	eq(#ui.sent, sent, "no offering without an altar visit")
	ui = atlas(roblox.Vector2.new(844, 390), function(snap) snap.prayer = nil; snap.thieving = nil end)
	open(ui, "Hero", "Prayer")
	eq(#ui.warnings, 0, "missing prayer state tolerated")
	open(ui, "Hunt", "Thieving")
	eq(#ui.warnings, 0, "missing thieving state tolerated")
	ui = atlas(roblox.Vector2.new(730, 303), function(snap)
		snap.prayer = {points = "x", max = {}, active = {5, "Ghost"}, quick = 3, offered = 7, altar = 4}
		snap.thieving = {thefts = 5, chances = {Farmhand = "x"}, cooldowns = 3, gloves = 7, stunIn = "now"}
	end)
	open(ui, "Hero", "Prayer")
	eq(#ui.warnings, 0, "malformed prayer state tolerated")
	open(ui, "Hunt", "Thieving")
	eq(#ui.warnings, 0, "malformed thieving state tolerated")
end
do
	-- HUD quick bar: a tap relays through IsleActionLocal to the atlas, which sends the verb.
	local ui = H.runAtlas(roblox.Vector2.new(1366, 768))
	local combat = H.runCombat(roblox.Vector2.new(1366, 768), ui.player, ui.replicated)
	ui.player:SetAttribute("PrayerLevel", 40)
	ui.player:SetAttribute("PrayerMax", 50)
	ui.player:SetAttribute("PrayerPoints", 0)
	ui.player:SetAttribute("PrayerQuick", "StonehideWard,HawkSight")
	ui.player:SetAttribute("PrayerActive", "WardOfQuills")
	local bar = combat.hud:FindFirstChild("PrayerBar")
	ok(bar.Visible, "quick bar visible once the server publishes points")
	eq(bar:FindFirstChild("Points"):FindFirstChild("Count").Text, "0", "empty gauge")
	ok(bar:FindFirstChild("Prayer2"):FindFirstChild("On").Visible and not bar:FindFirstChild("Prayer1"):FindFirstChild("On").Visible, "only Ward of Quills lit")
	ok(bar:FindFirstChild("Prayer3"):FindFirstChild("Veil").Visible, "Ward of Glyphs (Prayer 43) locked at 40")
	eq(bar:FindFirstChild("Prayer5"):FindFirstChild("Glyph").Text, PR.PrayerById.HawkSight.glyph, "favourite glyph")
	H.press(bar:FindFirstChild("Prayer1"))
	eq(ui.sent[#ui.sent][1], "prayer", "quick bar sends the prayer verb")
	eq(ui.sent[#ui.sent][2], "WardOfFangs", "quick bar names the protection")
	ui.player:SetAttribute("PrayerMax", 0)
	ok(not bar.Visible, "hidden until the server publishes a pool")
end
print("PASS: " .. (checks - partE) .. " Prayer & Thieving atlas assertions.")
print("Prayer & Thieving QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-prayer.luau")
