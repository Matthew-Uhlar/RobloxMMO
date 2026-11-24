-- Runebinding (§49): shards, Binding Altars, multiples, pouches, combination
-- runes, runes as spell reagents, the Glyph Rift, the Runebinder and the
-- client display helpers.
-- Part A: the pure rules (Data.Runebinding with shared/Progression.lua): skill
-- registration, altars and multiples, no coin mint (binds, combinations, the
-- rune shop), the XP / hour model against Mining, Beaconry and the 1-99 time,
-- pouch capacity / wear, the spell pay plan (runes, glyphs, combinations,
-- wildcards, elemental staves), the Rift rules and rewards, sanitising, quests,
-- the Runebinder and the economy (runes trade, shards never).
-- Part B: world.server.lua with real Roblox instances (the eleven altars on
-- their isles, the Shardgate, the Shardhollow, the Glyph Rift, the meshes).
-- Part C: server.server.lua through the verify-gameplay harness: the intro
-- gate, mining shards with real `strike` verbs, the carry cap and pouches,
-- binding (multiples, Lucent-only altars, combinations), pouch wear and
-- repair, travel, the Rift round lifecycle (lobby, active, fragments, shaping,
-- charging, a loss and a win, rewards only to present contributors, idle
-- removal), the Rift Points shop, lease / alive refusals, persistence and
-- migration.
-- Part D: sources and registration (combat pay plan, client script, gestures,
-- build lists).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local checks = 0
local function ok(cond, case)
	if not cond then error("FAILED: " .. case, 2) end
	checks += 1
end
local function eq(actual, expected, case)
	if actual ~= expected then error("FAILED: " .. case .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")", 2) end
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function load(path, env)
	return luau.load((fs.readFile(path):gsub("^\239\187\191", "")), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local RB = Data.Runebinding
local R = RB.Rift
local X = Data.XP_TABLE

------------------------------------------------------------------------------
-- A. Rules
------------------------------------------------------------------------------
local partA = checks
ok(type(RB) == "table", "Data.Runebinding exists")
eq(Data.SkillOrder[#Data.SkillOrder], "Runebinding", "Runebinding appended last (old saves keep their order)")
do
	local def = Data.Skills.Runebinding
	ok(def and def.category == "production" and #def.color == 6 and def.title == "Runebinder" and def.description, "skill metadata")
	for stat, v in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil and v > 0 and v <= 1, "perLevel " .. stat .. " modest") end
	for id, other in pairs(Data.Skills) do
		if id ~= "Runebinding" then ok(other.title ~= def.title and other.color ~= def.color, "title/colour unique vs " .. id) end
	end
	ok(Data.Mastery.capePerk("Runebinding") == Data.Mastery.CapePerk.Runebinding, "99 mantle perk registered")
	local s1, s99 = P.computeStats({xp = {}, items = {}}, 0), P.computeStats({xp = {Runebinding = X[99]}, items = {}}, 0)
	ok(s99.intelligence - s1.intelligence >= 98 - 1, "Runebinding 99 adds Intelligence per level")
end
-- Shards.
for _, id in ipairs(RB.ShardOrder) do
	local s, def = RB.Shards[id], Data.Items[id]
	ok(def and def.carry == true and def.category == "shard" and def.value == s.value, id .. " is a carried shard item")
	ok(Data.Strike.resource(s.entry) ~= nil and Data.Strike.resource(s.entry).skill == "Mining", id .. " swings as a Mining node")
	eq(Data.Strike.resource(s.entry).level, s.level, id .. " node gate matches the shard's Mining level")
	eq(Data.Economy.isCommodity(id), false, id .. " never trades on the Bazaar (carry loop)")
end
-- Altars: ascending levels and XP, original names, a real glyph, region and isle.
eq(#RB.Altars, 11, "eleven Binding Altars")
local glyphs = {}
for _, g in ipairs(Data.CombatStyles.glyphOrder) do glyphs[g] = true end
for i, a in ipairs(RB.Altars) do
	local rune = Data.Items[a.rune]
	ok(rune and rune.category == "rune" and rune.combatUse == true and rune.kind == "material", a.id .. " rune is a combat reagent")
	ok(Data.Economy.isCommodity(a.rune), a.id .. " rune trades on the Bazaar")
	ok(Data.RegionById[a.region] ~= nil, a.id .. " region exists")
	if a.glyph then ok(glyphs[a.glyph], a.id .. " pays a real spell glyph") end
	ok(a.glyph or a.wildcard, a.id .. " rune has a spell use")
	if i > 1 then
		local prev = RB.Altars[i - 1]
		ok(a.level > prev.level and a.xp > prev.xp, a.id .. " later altar: higher level and XP")
	end
	local last = a.level
	for _, at in ipairs(a.multiples) do ok(at > last and at <= 99, a.id .. " multiples ascend above the altar level"); last = at end
	eq(RB.runesPerShard(a.level - 1, a), 0, a.id .. " nothing below its level")
	eq(RB.runesPerShard(a.level, a), 1, a.id .. " one rune a shard at its level")
	eq(RB.runesPerShard(99, a), RB.maxRunesPerShard(a), a.id .. " every multiple by 99")
	for k, at in ipairs(a.multiples) do
		eq(RB.runesPerShard(at - 1, a), k, a.id .. " just below multiple " .. k)
		eq(RB.runesPerShard(at, a), k + 1, a.id .. " multiple " .. (k + 1) .. " at " .. at)
	end
	-- No coin mint: the best bind never sells for more than the cheapest shard it accepts.
	local cheapest = math.huge
	for _, sid in ipairs(RB.shardsFor(a)) do cheapest = math.min(cheapest, Data.Items[sid].value) end
	ok(RB.maxRunesPerShard(a) * rune.value <= cheapest, a.id .. " no mint: " .. RB.maxRunesPerShard(a) .. " x " .. rune.value .. " <= shard " .. cheapest)
end
eq(RB.runesPerShard(10, RB.AltarById.Gale), 1, "Gale x1 at 10")
eq(RB.runesPerShard(11, RB.AltarById.Gale), 2, "Gale x2 at 11")
eq(RB.runesPerShard(55, RB.AltarById.Gale), 3, "Gale x3 at 55")
eq(RB.runesPerShard(99, RB.AltarById.Crown), 1, "Crown never multiplies")
eq(RB.shardsFor(RB.AltarById.Void)[1], "LucentShard", "high altars take only Lucent")
eq(#RB.shardsFor(RB.AltarById.Void), 1, "only Lucent")
eq(#RB.shardsFor(RB.AltarById.Gale), 2, "low altars take either shard")
-- Combinations: real inputs, value <= inputs, chance curve.
for _, c in ipairs(RB.Combos) do
	local def = Data.Items[c.id]
	ok(def and def.category == "rune" and def.combatUse, c.id .. " reagent")
	ok(RB.AltarById[c.altar] and Data.Items[c.input] and RB.AltarOfRune[c.input].id ~= c.altar, c.id .. " made at one element's altar with the other's rune")
	ok(RB.AltarById[c.altar].level <= c.level and RB.AltarOfRune[c.input].level <= c.level, c.id .. " level covers both altars")
	ok(def.value <= RB.valueOf({AetherShard = 1, [c.input] = 1}), c.id .. " value <= shard + input rune (no mint)")
	for _, g in ipairs(c.glyphs) do ok(RB.ELEMENT_GLYPHS[g], c.id .. " holds elemental glyphs") end
	eq(RB.comboChance(c.level - 1, c), 0, c.id .. " not below its level")
	ok(math.abs(RB.comboChance(c.level, c) - 0.5) < 1e-9, c.id .. " 50% at its level")
	eq(RB.comboChance(c.level + 25, c), 1, c.id .. " certain 25 levels on")
	ok(c.xp > RB.AltarById[c.altar].xp, c.id .. " pays more XP than its altar's plain rune")
end
-- Rune shop: price per unit >= 1.3 x sell value; nothing the Rift sells for points is sold for coins.
for i, offer in ipairs(RB.ShopOffers) do
	local def = Data.Items[offer.item]
	ok(def ~= nil and offer.amount >= 1, "shop offer " .. i)
	ok(offer.price / offer.amount >= def.value * 1.3, offer.item .. " shop price " .. offer.price / offer.amount .. " >= 1.3 x " .. def.value)
	ok(RB.RiftShopById[offer.item] == nil, offer.item .. " is not also a Rift reward")
end
ok(Data.Items.SmallPouch ~= nil and Data.RegionArt.FolkByRole.Runebinder.shop == RB.ShopOffers, "the Runebinder sells runes and the small pouch")

-- XP / hour model (printed for the contract) and the 1-99 time.
print("Runebinding model (trip XP/h, best altar, Mining XP/h, ratio, Rift XP/h, Rift/trip):")
for _, lvl in ipairs({1, 5, 10, 20, 27, 30, 35, 44, 50, 60, 65, 70, 77, 85, 90, 99}) do
	local trip, altar = RB.bestTrip(lvl)
	local mine = RB.miningRate(lvl)
	local rift = RB.riftRate(lvl)
	print(string.format("  %2d  %7.0f  %-8s %7.0f  %.2f  %7.0f  %.2f", lvl, trip, altar.id, mine, trip / mine, rift, rift / trip))
	ok(trip / mine >= 0.4 and trip / mine <= 1.2, "level " .. lvl .. ": trips 0.4-1.2x the Mining rate (" .. string.format("%.2f", trip / mine) .. ")")
	ok(rift / trip >= 0.35 and rift / trip <= 1.1, "level " .. lvl .. ": the Rift 0.35-1.1x trips (points and runes on top)")
end
do
	local hours = RB.hoursTo99()
	print(string.format("  1-99 at the best trip: %.1f h (Beaconry banked ~42 h; OSRS Runecraft 100+ h)", hours))
	ok(hours >= 60 and hours <= 130, "1-99 takes 60-130 hours (" .. string.format("%.1f", hours) .. ")")
	-- Slower than Beaconry's banked kindling at the top: runebinding is a carry loop.
	local B = Data.Beaconry
	ok(RB.bestTrip(99) < B.bankedRate(99, B.Logs[#B.Logs], 3), "binding never beats banked kindling at 99")
	-- Monotone: never a worse best rate at a higher level.
	local last = 0
	for lvl = 1, 99 do local r = RB.bestTrip(lvl); ok(r >= last - 1e-6, "best trip never drops at " .. lvl); last = r end
end
-- Pouches: capacity by level, the Colossal replaces, wear halves, repair resets.
do
	local all = {}
	for _, id in ipairs(RB.PouchOrder) do all[id] = 1 end
	eq(RB.pouchCapacity(all, 1, {}), 3, "level 1: the small pouch")
	eq(RB.pouchCapacity(all, 25, {}), 9, "level 25: small + medium")
	eq(RB.pouchCapacity(all, 50, {}), 18, "level 50: + large")
	eq(RB.pouchCapacity(all, 75, {}), 30, "level 75: + giant")
	eq(RB.pouchCapacity(all, 85, {}), 40, "level 85: the Colossal replaces the rest")
	eq(RB.pouchCapacity({MediumPouch = 1}, 24, {}), 0, "a pouch above your level holds nothing")
	eq(RB.pouchCapacity({MediumPouch = 1}, 30, {MediumPouch = 45}), 3, "a worn pouch holds half")
	eq(RB.pouchCapacity({SmallPouch = 1}, 99, {SmallPouch = 9999}), 3, "the small pouch never wears")
	eq(RB.modelCapacity(1), RB.SATCHEL + 3, "model carry at 1")
	local e = RB.activePouches({GiantPouch = 1}, 80, {GiantPouch = 11})[1]
	ok(e.worn == true and e.cap == 6, "giant pouch worn after 11 trips")
	for _, pdef in ipairs(RB.Pouches) do ok(Data.Items[pdef.id].category == "pouch", pdef.id .. " item") end
end
-- Spell reagents: the pay plan.
do
	eq(RB.GlyphRune.GaleGlyph, "GaleRune", "Gale Rune pays the Gale Glyph")
	eq(RB.GlyphRune.SurgeGlyph, "VoidRune", "Void Rune pays the Surge Glyph (Lance catalyst)")
	eq(RB.GlyphRune.TorrentGlyph, "TorrentRune", "Torrent Rune pays the Torrent Glyph (Cascade catalyst)")
	local function same(a, b, case)
		for k, v in pairs(a or {}) do eq(b and b[k], v, case .. " " .. k) end
		for k, v in pairs(b or {}) do eq(a and a[k], v, case .. " " .. k) end
	end
	local dart = Data.Spells.GaleDart
	local costs = P.glyphCost(dart, nil)
	same(RB.payPlan(costs, {GaleRune = 5, SparkRune = 5}), {GaleRune = 1, SparkRune = 1}, "Gale Dart paid in runes")
	same(RB.payPlan(costs, {GaleGlyph = 5, SparkGlyph = 5}), {GaleGlyph = 1, SparkGlyph = 1}, "glyphs still work")
	same(RB.payPlan(costs, {GaleRune = 0, GaleGlyph = 2, SparkRune = 1}), {GaleGlyph = 1, SparkRune = 1}, "runes first, glyphs next")
	eq(RB.payPlan(costs, {SparkRune = 5}), nil, "no Gale reagent: refused")
	same(RB.payPlan(costs, {AstralRune = 1, SparkRune = 1}), {AstralRune = 1, SparkRune = 1}, "Astral pays an element")
	same(RB.payPlan(costs, {GaleRune = 1, CrownRune = 1}), {GaleRune = 1, CrownRune = 1}, "Crown pays a catalyst")
	same(RB.payPlan(costs, {MistRune = 3, SparkRune = 1}), {MistRune = 1, SparkRune = 1}, "a Mist rune pays the Gale glyph")
	-- Combinations pay two elements at once.
	local root = Data.Spells.Rootbind
	same(RB.payPlan(P.glyphCost(root, nil), {BindRune = 1, StoneRune = 1, DustRune = 1}), {BindRune = 1, StoneRune = 1, DustRune = 1}, "Rootbind: one Stone rune + one Dust")
	same(RB.payPlan({TideGlyph = 2, StoneGlyph = 1}, {TideRune = 1, SiltRune = 5}), {TideRune = 1, SiltRune = 1}, "one Silt pays a Tide and a Stone")
	eq(RB.payPlan({AstralRune = 1, CrownRune = 1}, {}), nil, "an unaffordable non-glyph cost is refused")
	same(RB.payPlan({HubwardTablet = 1}, {HubwardTablet = 2}), {HubwardTablet = 1}, "tablets pay as listed")
	-- Elemental staves: the staff's element is free, so no rune of it is spent.
	local staff = Data.Items.MeadowStaff
	same(RB.payPlan(P.glyphCost(dart, staff), {GaleRune = 9, SparkRune = 9}), {SparkRune = 1}, "a Gale staff supplies the Gale glyph: no Gale Rune spent")
	-- Every damage spell is payable from runes alone (the balance is unchanged: one rune per glyph).
	for _, id in ipairs(Data.SpellOrder) do
		local spell = Data.Spells[id]
		local c = P.glyphCost(spell, nil)
		local bag = {}
		for g, n in pairs(c) do bag[RB.GlyphRune[g] or g] = n end
		local plan = RB.payPlan(c, bag)
		ok(plan ~= nil, id .. " payable in runes")
		local total, glyphTotal = 0, 0
		for _, n in pairs(plan) do total += n end
		for _, n in pairs(c) do glyphTotal += n end
		eq(total, glyphTotal, id .. " costs exactly one rune per glyph")
		local n = 0
		for _ in pairs(plan) do n += 1 end
		ok(n <= 12, id .. " plan within the consume limit")
	end
	ok(Data.Items.GaleRune.value <= Data.Items.GaleGlyph.value, "a rune is never worth more than the glyph it replaces")
end
-- The Glyph Rift.
do
	local seen = {}
	for round = 0, 3 do
		for t = 0, R.ROUND, R.SWAP do
			local lo, hi = RB.riftPortals(round, t)
			ok(table.find(R.LOW, lo) and table.find(R.HIGH, hi), "portals: one low, one high")
			seen[lo], seen[hi] = true, true
		end
	end
	for _, id in ipairs(R.PORTALS) do ok(seen[id], id .. " portal opens over a few rounds") ; ok(RB.AltarById[id] ~= nil, id .. " portal is an altar") end
	local lo1 = RB.riftPortals(1, 0)
	local lo2 = RB.riftPortals(1, R.SWAP)
	ok(lo1 ~= lo2, "portals rotate every SWAP s")
	ok(RB.riftPowerPer(1) > RB.riftPowerPer(4) and RB.riftPowerPer(4) > 0, "a bigger party needs more essence each")
	eq(RB.riftWeight("Void"), 2, "the high portal counts double")
	eq(RB.riftWeight("Gale"), 1, "the low portal counts once")
	eq(RB.riftReward(R.MIN_CONTRIB - 1, true, 50), nil, "below the minimum: no reward")
	local r = RB.riftReward(120, true, 50)
	ok(r.points == math.min(R.POINT_CAP, 10) + R.WIN_POINTS and r.caches == 7 and r.xp == 500, "a won round's reward")
	local l = RB.riftReward(120, false, 50)
	ok(l.points == 10 and l.xp == 0, "a lost round pays points but no win bonus")
	eq(RB.riftReward(1e6, true, 99).points, R.POINT_CAP + R.WIN_POINTS, "points capped per round")
	eq(RB.riftReward(1e6, true, 99).caches, R.CACHE_CAP, "caches capped per round")
	-- Shop: every reward exists; outfit totals and gates.
	local outfit = 0
	for _, e in ipairs(RB.RiftShop) do
		ok(Data.Items[e.id] ~= nil and e.points > 0, e.id .. " reward")
		if Data.Items[e.id].set == RB.SET then outfit += e.points end
	end
	ok(outfit >= 600, "the full Shardweave outfit takes a few hours of rounds (" .. outfit .. " points)")
	eq(#Data.Sets[RB.SET].pieces, 4, "four outfit pieces")
	local b0 = RB.outfitBonus({})
	local b4 = RB.outfitBonus({helmet = "ShardweaveHood", chest = "ShardweaveRobe", legs = "ShardweaveLegwraps", boots = "ShardweaveBoots"})
	ok(b0 == 0 and math.abs(b4 - 0.06) < 1e-9, "outfit: +1% a piece, +6% with the set")
	ok(RB.lanternOn({RB.LANTERN}) and not RB.lanternOn({}), "the lantern counts from the accessory bag")
end
-- Sanitising.
do
	local m = RB.migrate({bound = {Gale = 5, Nope = 3, Tide = -2, Stone = 0 / 0}, pouch = {AetherShard = 9999, Junk = 1}, wear = {MediumPouch = 5, Bogus = 1},
		points = -5, rift = {rounds = "x", wins = 2}, combo = "Nope", failed = 1e99})
	ok(m.bound.Gale == 5 and m.bound.Nope == nil and m.bound.Tide == nil and m.bound.Stone == nil, "unknown / negative / NaN counts dropped")
	eq(m.pouch.AetherShard, 200, "pouch content clamped")
	eq(m.pouch.Junk, nil, "unknown shard dropped")
	ok(m.wear.MediumPouch == 5 and m.wear.Bogus == nil, "wear kept for real pouches")
	ok(m.points == 0 and m.rift.rounds == 0 and m.rift.wins == 2 and m.combo == nil and m.failed == RB.MAX_COUNT, "scalars clamped")
	local fresh = RB.migrate(nil)
	ok(type(fresh.bound) == "table" and fresh.points == 0, "a fresh journal")
end
-- Quests, helper, calculator, NPC, unlocks.
do
	local q1, q2 = Data.QuestById.WhispersInTheShard, Data.QuestById.HeartOfTheRift
	ok(q1 and q2 and q1.line == "side" and q2.requires[1].quest == q1.id, "the two-step Runebinder questline")
	eq(q1.rewards.items.SmallPouch, 1, "Whispers rewards the Small Shard Pouch")
	for _, q in ipairs({q1, q2}) do
		for _, o in ipairs(q.objectives) do
			local text = Data.describeCheck(o)
			ok(type(text) == "string" and not has(text, "Complete rb"), q.id .. " objective reads well: " .. tostring(text))
		end
	end
	local specs = Data.Systems.Helper.specsFor({kind = "flag", flag = "rbMined"}, {})
	ok(type(specs) == "table" and specs[1] == "anchor:Waypoint_Shardgate", "quest helper points at the Shardgate")
	local acts = Data.Systems.Calc.actions("Runebinding")
	eq(#acts, #RB.Altars + #RB.Combos, "XP calculator lists every altar and combination")
	ok(table.find(Data.Systems.Calc.skills(), "Runebinding") ~= nil, "Runebinding in the calculator")
	local T = Data.Townsfolk
	local npc = T.NPCs.Runebinder
	ok(npc and npc.anchorOnly and npc.nodes.hello and npc.nodes.rift and npc.nodes.combo and npc.nodes.shop, "the Runebinder's dialogue")
	ok(table.find(T.RegionFolkOrder, "Runebinder") ~= nil, "regional folk order lists the Runebinder")
	for _, node in pairs(npc.nodes) do
		for _, o in ipairs(node.options) do
			if o.verb then
				local v = T.Verbs[o.verb]
				ok(v ~= nil and (v.item == false or (type(v.item) == "table" and v.item[o.item])), "dialogue verb registered: " .. o.verb .. " " .. tostring(o.item))
			end
		end
	end
	local unlocks = RB.unlocks()
	ok(#unlocks >= #RB.Altars + #RB.Combos + #RB.Pouches, "unlock guide lists altars, multiples, combinations and pouches")
	for _, u in ipairs(unlocks) do ok(u.level >= 1 and u.level <= 99 and type(u.text) == "string", "unlock " .. u.text) end
end
-- Client display helpers.
do
	local r = RB.parseRift("active:95:42:100:Gale,Void:3:7")
	ok(r and r.phase == "active" and r.left == 95 and r.power == 42 and r.goal == 100 and r.low == "Gale" and r.high == "Void" and r.members == 3 and r.round == 7, "GlyphRift parses")
	local idle = RB.parseRift("idle:0:0:100:,:0:0")
	ok(idle and idle.low == nil and idle.high == nil, "idle rift parses")
	eq(RB.parseRift("garbage"), nil, "malformed rift ignored")
	local f, e, c = RB.parseRiftState("12:30:44")
	ok(f == 12 and e == 30 and c == 44, "RiftState parses")
	f, e, c = RB.parseRiftState(nil)
	ok(f == 0 and e == 0 and c == 0, "absent RiftState is zero")
	local rows = RB.pickerRows(20)
	eq(#rows, #RB.Altars, "picker lists every altar")
	ok(rows[1].open and rows[6].open and not rows[7].open, "picker gates by level")
	ok(has(RB.carryText({carried = 20, satchel = 28, pouchHeld = 3, pouchCap = 9, pouches = {{worn = true}}}), "◆ 20/28   ◇ 3/9   ⚠ worn"), "pouch indicator text")
	eq(RB.carryText(nil), "", "no state, no text")
end
print("Part A (rules): " .. (checks - partA) .. " checks")

------------------------------------------------------------------------------
-- B. World (real instances)
------------------------------------------------------------------------------
local partB = checks
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f) local c = {Connected = true}; function c:Disconnect() self.Connected = false end; table.insert(listeners, {f, c}); return c end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local tagged = {}
local worldEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function(_, inst, tag) tagged[tag] = tagged[tag] or {}; table.insert(tagged[tag], inst) end, RemoveTag = function() end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
	UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
luau.load(fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position"), {environment = worldEnv, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
local archipelago = world:FindFirstChild("AetherIsles")
local WorldCatalog = load("art/WorldCatalog.lua")
local function shapeOk(name) return WorldCatalog.shapes and WorldCatalog.shapes[name] ~= nil end
for _, name in ipairs({"BindingAltar", "GuardianPortal", "RiftMonolith"}) do
	local s = WorldCatalog.shapes[name]
	ok(s ~= nil and type(s.fit) == "table" and s.exactTint == true, name .. " is a forged mesh with a fit box and exact tints")
end
local altarPrompts = {}
for _, q in islands:GetDescendants() do
	if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "runeAltar" then
		local id = q:GetAttribute("IsleItem")
		ok(RB.AltarById[id] and altarPrompts[id] == nil, "one bind prompt per altar: " .. tostring(id))
		altarPrompts[id] = q
	end
end
local altarParts, neon, lights = 0, 0, 0
for _, a in ipairs(RB.Altars) do
	local q = altarPrompts[a.id]
	ok(q ~= nil, a.id .. " altar built")
	local isle = islands:FindFirstChild(a.isle)
	ok(isle ~= nil and q:IsDescendantOf(isle), a.id .. " on " .. a.isle)
	eq(isle:GetAttribute("RegionId"), a.region, a.id .. " isle is in its region")
	eq(q:GetAttribute("IsleRegion"), a.region, a.id .. " prompt carries the region gate")
	ok(math.abs(q.HoldDuration - 0.36) < 1e-6, a.id .. " interact hold")
	local base = q.Parent
	eq(base:GetAttribute("Shape"), "BindingAltar", a.id .. " forged altar mesh")
	eq(base:GetAttribute("Tint"), roblox.Color3.fromHex(a.color), a.id .. " tinted its rune's colour")
	eq(base:GetAttribute("AltarId"), a.id, a.id .. " AltarId")
	ok(table.find(tagged.RuneAltar or {}, base) ~= nil, a.id .. " tagged RuneAltar")
	ok(isle:FindFirstChild("Anchor_Waypoint_Altar_" .. a.id, true) ~= nil, a.id .. " waypoint anchor")
	local back
	for _, obj in base.Parent:GetDescendants() do
		if obj:IsA("BasePart") then
			altarParts += 1
			ok(obj.Anchored, obj.Name .. " anchored")
			if obj.Material == roblox.Enum.Material.Neon then neon += 1 end
		end
		if obj:IsA("Light") then lights += 1 end
		if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") == "rbTravel" then back = obj end
	end
	ok(back and back:GetAttribute("IsleItem") == "Field", a.id .. " keystone returns to the Shardhollow")
	-- Clear of other prompts (stations, pyres) by more than the activation reach.
	local pos = base.CFrame.Position
	for _, other in isle:GetDescendants() do
		if other:IsA("ProximityPrompt") and other.Parent ~= base and other.Parent.Parent ~= base.Parent and other.Parent:IsA("BasePart") then
			ok((other.Parent.CFrame.Position - pos).Magnitude > 6, a.id .. " clear of " .. other.Parent.Name)
		end
	end
end
eq(neon, 0, "altars add no Neon (the glow is client-side)")
eq(lights, 0, "altars add no server lights")
-- The Shardgate on Compass Quay and the Runebinder beside it.
do
	local quay = islands:FindFirstChild("Compass Quay")
	local gate
	for _, q in quay:GetDescendants() do if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "rbGate" then gate = q end end
	ok(gate ~= nil, "the Shardgate prompt")
	local landing = quay:FindFirstChild("Anchor_Waypoint_Shardgate", true)
	local mentor = quay:FindFirstChild("Anchor_NPC_Runebinder", true)
	ok(landing and mentor, "Shardgate landing and the Runebinder's anchor")
	ok((mentor.CFrame.Position - gate.Parent.CFrame.Position).Magnitude < 16, "the Runebinder stands by the Shardgate")
end
-- The Shardhollow.
local field = archipelago:FindFirstChild(RB.FIELD)
ok(field ~= nil and field:GetAttribute("RuneField") == true, "the Shardhollow is built off the chart (Workspace.AetherIsles)")
ok(islands:FindFirstChild(RB.FIELD) == nil, "and not on the Sky Chart islands")
local fieldParts, outcrops, heaps, portals, verbs = 0, {AetherShard = 0, LucentShard = 0}, 0, {}, {}
for _, obj in field:GetDescendants() do
	if obj:IsA("BasePart") then
		fieldParts += 1
		ok(obj.Anchored, obj.Name .. " anchored")
		if obj:GetAttribute("StrikeKind") == "shard" then
			local kind = obj:GetAttribute("ShardKind")
			outcrops[kind] += 1
			eq(obj:GetAttribute("GatherNode"), RB.Shards[kind].entry, kind .. " outcrop swings as its entry ore")
			ok(type(obj:GetAttribute("NodeMaxHp")) == "number" and obj:GetAttribute("NodeName") ~= nil, kind .. " stamped node")
		elseif obj:GetAttribute("StrikeKind") == "riftFragment" then heaps += 1 end
		if obj:GetAttribute("RiftPortal") then portals[obj:GetAttribute("RiftPortal")] = obj end
	end
	if obj:IsA("ProximityPrompt") then verbs[obj:GetAttribute("IsleAction") .. ":" .. tostring(obj:GetAttribute("IsleItem"))] = obj end
	ok(not obj:IsA("Light"), "no server lights in the Shardhollow")
end
eq(outcrops.AetherShard, 8, "eight Aether outcrops")
eq(outcrops.LucentShard, 4, "four Lucent outcrops")
eq(heaps, 2, "two fragment heaps")
for _, id in ipairs(R.PORTALS) do
	local portal = portals[id]
	ok(portal and portal:GetAttribute("Shape") == "GuardianPortal", id .. " guardian portal mesh")
	ok(verbs["riftCharge:" .. id] ~= nil, id .. " portal charges")
end
for _, v in ipairs({"rbWaygate:nil", "rbTravel:Quay", "riftJoin:nil", "riftShape:nil"}) do ok(verbs[v] ~= nil, "Shardhollow prompt " .. v) end
for _, name in ipairs({"Waypoint_Shardhollow", "Waypoint_Waygate", "Waypoint_Rift"}) do ok(field:FindFirstChild("Anchor_" .. name, true) ~= nil, name .. " anchor") end
ok(shapeOk("RiftMonolith"), "Rift Guardian mesh")
print(string.format("Part B (world): %d checks; %d altar parts, %d Shardhollow parts", checks - partB, altarParts, fieldParts))
ok(altarParts + fieldParts <= 130, "Runebinding stays inside its static part budget (" .. (altarParts + fieldParts) .. ")")

------------------------------------------------------------------------------
-- C. Server (the verify-gameplay harness; strikes are real `strike` verbs)
------------------------------------------------------------------------------
local partC = checks
local src = (fs.readFile("verify-gameplay.luau"):gsub("\r\n", "\n"))
local cut = src:find("local checks=0\nlocal function eq", 1, true)
assert(cut, "verify-gameplay harness marker")
local prefix = src:sub(1, cut - 1)
local n1, n2
prefix, n1 = prefix:gsub("local workspace = {GetAttribute=function%(self,key%) return self%[key%] end}", "local workspace = __ws")
prefix, n2 = prefix:gsub("\tworkspace=workspace,\n", "\tworkspace=workspace,CFrame=__roblox.CFrame,Vector3=__roblox.Vector3,\n")
assert(n1 == 1 and n2 == 1, "harness workspace hooks")
-- A fake world: anchors the server finds by name (Trails.anchor under
-- Islands, the Shardhollow under AetherIsles), at chosen positions.
local anchors = {}
local function place(name, pos) anchors[name] = {Name = "Anchor_" .. name, Parent = true, CFrame = CFrame.new(pos.X, pos.Y, pos.Z), Position = pos} end
local folder = {FindFirstChild = function(_, name) local key = string.match(name, "^Anchor_(.+)$"); return key and anchors[key] end}
local ws = {}
ws.GetAttribute = function(self, k) return rawget(self, k) end
ws.SetAttribute = function(self, k, v) rawset(self, k, v) end
ws.FindFirstChild = function(_, name)
	if name == "Islands" then return folder end
	if name == "AetherIsles" then return {FindFirstChild = function(_, n) return if n == RB.FIELD then folder else nil end} end
	return nil
end
local H = luau.load("local __ws, __roblox = ...\n" .. prefix .. "\nreturn {player=player,cmd=cmd,data=data,advance=advance,services=services,objects=objects,Data=Data,clock=function() return clock end,setRoll=function(v) defaultRoll=v end}",
	{debugName = "runebinding-harness", injectGlobals = true})(ws, roblox)
local SD = H.Data
local SRB = SD.Runebinding
local remote = H.objects.RemoteFunction
local function strike(p, node) return remote.OnServerInvoke(p, "strike", node) end
local function state(p) return H.cmd(p, "state") end
local function rb(p) return state(p).runebinding end
local function verb(p, v, item) return H.cmd(p, v, item).message end
local function rootOf(p) return p.Character:FindFirstChild("HumanoidRootPart") end
local function moveTo(p, pos) rootOf(p).Position = pos end
-- A prompt at `pos` (the player's root is moved onto it).
local function use(p, action, item, region, pos)
	pos = pos or Vector3.zero
	moveTo(p, pos)
	local q = {Enabled = true, MaxActivationDistance = 9, GetAttribute = function(_, key)
		return ({IsleAction = action, IsleItem = item, IsleRegion = region})[key]
	end, FindFirstAncestorWhichIsA = function() return {Position = pos} end}
	H.advance(1)
	p.last = nil
	H.services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last and p.last.message, p.last
end
local nodeRoot = roblox.Instance.new("Folder")
nodeRoot.Parent = roblox.Instance.new("Workspace")
local function makeNode(gather, attrs)
	local model = roblox.Instance.new("Model")
	model.Parent = nodeRoot
	local part = roblox.Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Position = Vector3.zero
	part.CFrame = CFrame.new(0, 0, 0)
	part:SetAttribute("GatherNode", gather)
	for k, v in pairs(attrs or {}) do part:SetAttribute(k, v) end
	part.Parent = model
	return part
end
local function breakIt(p, node, limit)
	moveTo(p, Vector3.zero)
	local last
	for _ = 1, limit or 12 do
		last = strike(p, node)
		if last and last.broken then return last end
		if last and last.reason == "cadence" then H.advance(last.wait + 0.01)
		elseif last and last.ok == false and last.reason ~= "cadence" then return last
		else H.advance(Data.Strike.SWING.Mining + 0.01) end
	end
	return last
end
local function seeded(id, mutate)
	local p = H.player(id)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. id].profile) end
	return H.player(id)
end
local function rejoin(p, mutate)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. p.UserId].profile) end
	local q = H.player(p.UserId)
	q.Character.PivotTo = function(_, cf) rootOf(q).Position = cf.Position end
	return q
end
place("Waypoint_Shardhollow", Vector3.new(1500, 200, 1450))
place("Waypoint_Waygate", Vector3.new(1500, 200, 1464))
place("Waypoint_Rift", Vector3.zero)
place("Waypoint_Shardgate", Vector3.new(-40, 0, 40))
place("NPC_Runebinder", Vector3.new(-40, 0, 46))
for _, a in ipairs(RB.Altars) do place("Waypoint_Altar_" .. a.id, Vector3.new(a.index * 100, 0, 0)) end

-- The intro gate and the snapshot.
local m = rejoin(H.player(9101), function(pr) pr.xp.Mining = X[35] end)
local aether = makeNode("Ore", {StrikeKind = "shard", ShardKind = "AetherShard", NodeName = "Aether Shard Outcrop"})
local lucent = makeNode("SunsteelOre", {StrikeKind = "shard", ShardKind = "LucentShard", NodeName = "Lucent Shard Outcrop"})
do
	local s0 = rb(m)
	ok(type(s0) == "table" and s0.intro == false and s0.satchel == RB.SATCHEL and s0.carried == 0, "snapshot carries runebinding")
	eq(state(m).levels.Runebinding, 1, "Runebinding level in the snapshot")
	local r = breakIt(m, aether)
	ok(r and r.ok == false and has(r.message, "Runebinder"), "shards need the Runebinder's lesson first")
	ok(has((use(m, "rbGate", nil)), "Speak to the Runebinder"), "the Shardgate stays shut")
	ok(has(verb(m, "rbIntro"), "Shardgate"), "rbIntro teaches")
	ok(has(verb(m, "rbIntro"), "already"), "rbIntro once")
	eq(rb(m).intro, true, "intro flag set")
end
-- Mining Aether Shards with real strikes.
do
	H.advance(2)
	local r = breakIt(m, aether)
	ok(r and r.broken and has(r.message, "+3 Aether Shard") and has(r.message, "Mining XP"), "a shard outcrop breaks for 3 shards: " .. tostring(r and r.message))
	local s = state(m)
	eq(s.items.AetherShard, 3, "shards in the satchel")
	eq(s.runebinding.mined.AetherShard, 3, "lifetime mined")
	H.advance(0.5)
	local again = strike(m, aether)
	ok(again.reason == "regrowing", "the outcrop regrows per player")
	local lr = breakIt(m, lucent)
	ok(lr and lr.ok == false and has(lr.message, "tier 2"), "Lucent outcrops need a tier 2 pickaxe (the Sunsteel node gate)")
end
-- Travel: the Shardgate, the Waygate picker and the altars.
m.Character.PivotTo = function(_, cf) rootOf(m).Position = cf.Position end
do
	local msg = use(m, "rbGate", nil)
	ok(has(msg, "Shardhollow"), "the Shardgate carries you: " .. tostring(msg))
	ok((rootOf(m).Position - Vector3.new(1500, 204, 1450)).Magnitude < 1e-3, "landed in the Shardhollow")
	ok(m:GetAttribute("FastTravelAt") ~= nil, "server travel marks FastTravelAt")
	local w0 = m:GetAttribute("RuneWaygate")
	ok(has((use(m, "rbWaygate", nil, nil, Vector3.new(1500, 200, 1464))), "Choose an altar"), "the Waygate opens the picker")
	ok(m:GetAttribute("RuneWaygate") ~= w0, "RuneWaygate bumps for the client picker")
	moveTo(m, Vector3.new(0, 0, 0))
	ok(has(verb(m, "rbTravel", "Gale"), "Stand on the Shardhollow Waygate"), "rbTravel needs the Waygate")
	moveTo(m, Vector3.new(1500, 200, 1460))
	H.advance(5)
	ok(has(H.cmd(m, "rbTravel", "Void").message, "requires Runebinding 35"), "altar level gate on travel")
	ok(has(H.cmd(m, "rbTravel", "Nope").message, "Choose a Binding Altar"), "unknown altar refused")
	moveTo(m, Vector3.new(1500, 200, 1460))
	local t = H.cmd(m, "rbTravel", "Gale").message
	ok(has(t, "Gale Altar"), "travel to the Gale Altar: " .. tostring(t))
	ok((rootOf(m).Position - Vector3.new(100, 4, 0)).Magnitude < 1e-3, "landed at the altar")
	moveTo(m, Vector3.new(1500, 200, 1460))
	ok(has(H.cmd(m, "rbTravel", "Gale").message, "settling"), "travel cooldown")
	ok(has(verb(m, "rbTravel", "Field"), "Step onto a waygate"), "Field / Quay only from a prompt")
end
-- Binding at the Gale Altar.
do
	local before = state(m)
	local xp0 = before.xp.Runebinding or 0
	local msg = use(m, "runeAltar", "Gale", "Hub")
	ok(has(msg, "Bound 3 Aether Shards into 3 Gale Runes") and has(msg, "+18 Runebinding XP"), "bind: " .. tostring(msg))
	local s = state(m)
	eq(s.items.GaleRune, 3, "runes in the satchel")
	eq(s.items.AetherShard or 0, 0, "shards spent")
	eq(s.xp.Runebinding, xp0 + 18, "6 XP a shard")
	eq(state(m).runebinding.bound.Gale, 3, "bound tally")
	ok(has(m:GetAttribute("RuneBind"), ":Gale:3"), "RuneBind attribute for the VFX")
	ok(has((use(m, "runeAltar", "Gale", "Hub")), "Bring Aether Shards"), "nothing to bind")
	ok(has((use(m, "runeAltar", "Tide", "Meadow")), "requires Runebinding 5"), "altar level gate")
	ok(has((use(m, "runeAltar", "Nope", "Hub")), "silent"), "unknown altar")
	ok(has(verb(m, "runeAltar", "Gale"), "Binding Altar"), "binding needs the altar prompt")
end
-- Multiples and Lucent-only altars (seeded journals).
do
	local hi = seeded(9102, function(pr)
		pr.xp.Runebinding = X[60]; pr.rbIntro = true; pr.xp.Mining = X[30]; pr.xp.Combat = X[15]
		pr.items = {AetherShard = 10, LucentShard = 4}
	end)
	local msg = use(hi, "runeAltar", "Gale", "Hub")
	ok(has(msg, "into 30 Gale Runes") and has(msg, "×3"), "Gale x3 at 60: " .. tostring(msg))
	local hum = use(hi, "runeAltar", "Gale", "Hub")
	ok(has(hum, "still humming"), "one bind per RB.BIND_SECONDS: " .. tostring(hum))
	eq(state(hi).items.LucentShard, 4, "a low altar spends Aether first and keeps the Lucent")
	H.advance(3)
	msg = use(hi, "runeAltar", "Gale", "Hub")
	ok(has(msg, "4 Lucent Shards"), "Lucent binds at a low altar when it is all you carry")
	hi = rejoin(hi, function(pr) pr.items.AetherShard = 5 end)
	ok(has((use(hi, "runeAltar", "Void", "Gloomhollow")), "only takes Lucent"), "Void refuses Aether")
	hi = rejoin(hi, function(pr) pr.items.LucentShard = 2 end)
	msg = use(hi, "runeAltar", "Void", "Gloomhollow")
	ok(has(msg, "into 2 Void Runes") and has(msg, "+50 Runebinding XP"), "Void: " .. tostring(msg))
	-- The region gate (Gloomhollow needs Mining 30 / Combat 15).
	local low = seeded(9103, function(pr) pr.xp.Runebinding = X[40]; pr.rbIntro = true; pr.items = {LucentShard = 3} end)
	ok(not has((use(low, "runeAltar", "Void", "Gloomhollow")), "Bound"), "a locked region refuses the altar")
end
-- The carry cap and pouches (auto-fill, wear on emptying, repair).
do
	local c = seeded(9104, function(pr)
		pr.xp.Runebinding = X[30]; pr.xp.Mining = X[10]; pr.rbIntro = true
		pr.items = {AetherShard = 26, SmallPouch = 1, MediumPouch = 1}
	end)
	local node = makeNode("Ore", {StrikeKind = "shard", ShardKind = "AetherShard"})
	local r = breakIt(c, node)
	ok(r and r.broken and has(r.message, "(1 into pouches)"), "the satchel fills to 28, the rest goes into pouches: " .. tostring(r and r.message))
	local s = rb(c)
	ok(s.carried == 28 and s.pouchHeld == 1 and s.pouchCap == 9, "28 in the satchel, 1 / 9 in pouches")
	c = rejoin(c, function(pr) pr.runebinding.pouch = {AetherShard = 9} end)
	local n2node = makeNode("Ore", {StrikeKind = "shard", ShardKind = "AetherShard"})
	local refused = breakIt(c, n2node)
	ok(refused and refused.ok == false and has(refused.message, "full of shards"), "a full carry refuses the strike before any damage")
	eq(state(c).items.AetherShard, 28, "nothing lost")
	-- Bind empties satchel + pouches in one go; the pouches wear one trip.
	local msg = use(c, "runeAltar", "Gale", "Hub")
	ok(has(msg, "Bound 37 Aether Shards"), "satchel and pouches bind together: " .. tostring(msg))
	-- Worn out: half capacity until repaired.
	c = rejoin(c, function(pr)
		eq(pr.rbBound, true, "bound flag saved")
		eq(pr.runebinding.wear.MediumPouch, 1, "the medium pouch wore one trip")
		eq(pr.runebinding.wear.SmallPouch, nil, "the small pouch never wears")
		pr.runebinding.wear.MediumPouch = 45; pr.coins = 50
	end)
	eq(rb(c).pouchCap, 6, "a worn medium pouch holds 3")
	moveTo(c, Vector3.new(-40, 0, 44)) -- beside the Runebinder
	ok(has(verb(c, "pouchRepair"), "costs 200 coins"), "repair without astral runes needs coins")
	c = rejoin(c, function(pr) pr.items.AstralRune = 2 end)
	moveTo(c, Vector3.new(-40, 0, 44))
	ok(has(verb(c, "pouchRepair"), "-1 Astral Rune"), "an Astral Rune repairs a pouch")
	eq(rb(c).pouchCap, 9, "repaired")
	eq(state(c).items.AstralRune, 1, "one Astral Rune spent")
	-- Away from the Runebinder (the anchor is known): refused.
	moveTo(c, Vector3.new(900, 0, 900))
	H.advance(1)
	ok(has(H.cmd(c, "pouchRepair").message, "Speak to the Runebinder"), "repair happens at the Runebinder")
end
-- Combination runes.
do
	local cb = seeded(9105, function(pr)
		pr.xp.Runebinding = X[10]; pr.rbIntro = true
		pr.items = {AetherShard = 10, GaleRune = 4}
	end)
	ok(has(verb(cb, "rbCombo", "MagmaRune"), "Runebinding 23"), "combination level gate")
	ok(has(verb(cb, "rbCombo", "MistRune"), "Mist Runes"), "choose Mist")
	H.setRoll(0.4) -- below the 58% hold at level 10
	local msg = use(cb, "runeAltar", "Tide", "Meadow")
	ok(has(msg, "Bound 4 Mist Runes from 4 shards"), "Mist at the Tide Altar: " .. tostring(msg))
	local s = state(cb)
	ok(s.items.MistRune == 4 and (s.items.GaleRune or 0) == 0 and s.items.AetherShard == 6, "one shard + one Gale Rune per Mist Rune")
	cb = rejoin(cb, function(pr) eq(pr.rbCombo, true, "combination flag saved"); pr.items.GaleRune = 3 end)
	H.setRoll(0.99) -- every attempt fails
	msg = use(cb, "runeAltar", "Tide", "Meadow")
	ok(has(msg, "Bound 0 Mist Runes from 3 shards"), "failed combinations: " .. tostring(msg))
	local s2 = state(cb)
	ok(s2.items.GaleRune == 3 and s2.items.AetherShard == 3, "a failed hold loses the shard, keeps the rune")
	H.setRoll(0.999)
	ok(has(verb(cb, "rbCombo", "none"), "plain runes"), "back to plain runes")
	H.advance(3)
	msg = use(cb, "runeAltar", "Tide", "Meadow")
	ok(has(msg, "into 3 Tide Runes"), "plain Tide Runes again: " .. tostring(msg))
end
-- The Glyph Rift: lobby, active round, fragments, shaping, charging, a loss and a win.
do
	SRB.Rift.ROUND, SRB.Rift.LOBBY, SRB.Rift.REST, SRB.Rift.IDLE = 100, 10, 10, 30 -- short rounds so the harness lease (180 s) covers one
	local low = seeded(9106, function(pr) pr.xp.Runebinding = X[5]; pr.rbIntro = true end)
	ok(has((use(low, "riftJoin", nil)), "Runebinding 10"), "the Rift needs Runebinding 10")
	local a1 = seeded(9107, function(pr) pr.xp.Runebinding = X[50]; pr.xp.Mining = X[20]; pr.rbIntro = true end)
	local a2 = seeded(9108, function(pr) pr.xp.Runebinding = X[12]; pr.rbIntro = true end)
	ok(has(verb(a1, "riftJoin"), "barrier"), "joining needs the plinth prompt")
	ok(has((use(a1, "riftJoin", nil)), "The round opens in"), "a1 joins: lobby")
	eq(rb(a1).rift.phase, "lobby", "lobby phase")
	ok(has(ws.GlyphRift, "lobby:"), "GlyphRift published")
	ok(has((use(a2, "riftJoin", nil)), "The round opens in"), "a2 joins")
	ok(has((use(a2, "riftJoin", nil)), "already"), "no double join")
	local heap = makeNode("Ore", {StrikeKind = "riftFragment"})
	local early = breakIt(a1, heap)
	ok(early and early.ok == false and has(early.message, "Glyph Rift round"), "heaps stay shut before the round")
	H.advance(SRB.Rift.LOBBY + 1)
	local st = rb(a1).rift
	ok(st.phase == "active" and st.member and st.round == 1 and st.members == 2, "the round opens with both binders")
	ok(has(a1:GetAttribute("RiftState"), "0:0:0"), "RiftState for the HUD")
	-- a1 mines, shapes, charges the open high portal (counts double).
	local r = breakIt(a1, heap)
	ok(r and r.broken and has(r.message, "+4 Rift fragments"), "a heap breaks for 4 fragments: " .. tostring(r and r.message))
	H.advance(1.5)
	r = breakIt(a1, heap)
	ok(r and r.broken, "and again")
	ok(has((use(a1, "riftShape", nil)), "Shaped 8 charged essence"), "the workbench shapes fragments into essence")
	local lo, hi = SRB.riftPortals(1, 0)
	local now = rb(a1).rift.portals
	lo, hi = now[1], now[2]
	local closed
	for _, id in ipairs(R.PORTALS) do if id ~= lo and id ~= hi then closed = id break end end
	ok(has((use(a1, "riftCharge", closed)), "is closed"), "a closed portal refuses")
	local msg = use(a1, "riftCharge", hi)
	local hiAltar = RB.AltarById[hi]
	if hiAltar.level <= 50 then
		ok(has(msg, "with 8 essence"), "charging the high portal: " .. tostring(msg))
		eq(rb(a1).rift.contrib, 16, "the high portal counts double")
	else
		ok(has(msg, "needs Runebinding"), "a portal above your level refuses")
		msg = use(a1, "riftCharge", lo)
		ok(has(msg, "with 8 essence"), "charging the low portal: " .. tostring(msg))
	end
	ok(rb(a1).rift.power > 0, "the Guardian gains power")
	-- a2 idles past R.IDLE and is let go; a1 keeps working until the round ends (a loss).
	for _ = 1, 8 do
		H.advance(1.5)
		breakIt(a1, heap)
	end
	use(a1, "riftShape", nil)
	local p2 = rb(a1).rift.portals
	local target = if RB.AltarById[p2[2]].level <= 50 then p2[2] else p2[1]
	use(a1, "riftCharge", target)
	-- a2 idles past R.IDLE while a1 keeps mining (a1 stays active).
	for _ = 1, 2 do H.advance(16); breakIt(a1, heap) end
	use(a1, "riftShape", nil)
	eq(rb(a2).rift.member, false, "an idle member is let go")
	ok(a2:GetAttribute("RiftState") == "", "and the HUD state clears")
	local pts0 = rb(a1).points
	local contrib = rb(a1).rift.contrib
	ok(contrib >= SRB.Rift.MIN_CONTRIB, "a1 contributed " .. contrib)
	H.advance(SRB.Rift.ROUND)
	local after = rb(a1)
	ok(after.rift.phase == "rest", "the round ends on time")
	local expected = math.min(R.POINT_CAP, contrib // R.POINT_EVERY)
	eq(after.points, pts0 + expected, "a lost round pays contribution points")
	eq(after.rift.rounds, 1, "round recorded")
	eq(after.rift.wins, 0, "not a win")
	-- Next round: a win (goal lowered for the harness) pays the win bonus and the flag.
	a1 = rejoin(a1) -- renew the lease (leaving drops Rift membership)
	SRB.Rift.GOAL = 6
	H.advance(SRB.Rift.REST + 1)
	ok(has((use(a1, "riftJoin", nil)), "join"), "rejoin the Rift")
	H.advance(SRB.Rift.LOBBY + 1)
	eq(rb(a1).rift.phase, "active", "round 2 opens")
	local h2 = makeNode("Ore", {StrikeKind = "riftFragment"})
	for _ = 1, 3 do H.advance(1.5); breakIt(a1, h2) end
	use(a1, "riftShape", nil)
	local p3 = rb(a1).rift.portals
	local pts1 = rb(a1).points
	local wins0 = rb(a1).rift.wins
	msg = use(a1, "riftCharge", if RB.AltarById[p3[2]].level <= 50 then p3[2] else p3[1])
	ok(has(msg, "Guardian"), "charge: " .. tostring(msg))
	local won = rb(a1)
	eq(won.rift.phase, "rest", "reaching the goal ends the round at once")
	eq(won.rift.wins, wins0 + 1, "a win recorded")
	ok(won.points > pts1 + R.WIN_POINTS - 1, "the win bonus is paid")
	ok(won.rift.member, "members stay for the next round")
	ok(has(verb(a1, "riftLeave"), "You leave"), "leave")
	ok(has(verb(a1, "riftLeave"), "not in"), "leave once")
	a1 = rejoin(a1, function(pr) eq(pr.rbRiftWin, true, "win flag saved (Heart of the Rift)") end)
	SRB.Rift.ROUND, SRB.Rift.LOBBY, SRB.Rift.REST, SRB.Rift.GOAL, SRB.Rift.IDLE = 240, 30, 20, 100, 60
end
-- The Rift Points shop.
do
	local b = seeded(9109, function(pr) pr.xp.Runebinding = X[30]; pr.runebinding = {points = 500} end)
	ok(has(verb(b, "riftBuy", "LargePouch"), "Runebinding 50"), "pouch level gate")
	ok(has(verb(b, "riftBuy", "Nope"), "not a Rift reward"), "unknown reward")
	ok(has(verb(b, "riftBuy", "MediumPouch"), "Bought Medium Shard Pouch"), "buy a pouch with points")
	local s = state(b)
	eq(s.items.MediumPouch, 1, "straight into the satchel")
	eq(s.runebinding.points, 420, "points spent")
	eq((s.collection or {}).MediumPouch, nil, "shop purchases never count as collection")
	ok(has(verb(b, "riftBuy", "MediumPouch"), "already own"), "one of each")
	ok(has(verb(b, "riftBuy", "ShardweaveRobe"), "Bought Shardweave Robe"), "an outfit piece")
	ok(has(verb(b, "riftBuy", "RiftlightLantern"), "costs 300"), "not enough points")
	-- Lease and life refusals (perform).
	local humanoid = b.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	ok(has(verb(b, "riftBuy", "ShardweaveHood"), "Return to your island"), "a dead player cannot buy")
	humanoid.Health = 100
	H.advance(400)
	ok(has(verb(b, "riftBuy", "ShardweaveHood"), "journal sync"), "an expired lease refuses")
	b = rejoin(b)
	eq(rb(b).points, 200, "points persisted (nothing bought without the lease)")
end
-- The lantern: one more shard a break while it is in the accessory bag.
do
	local l = seeded(9110, function(pr) pr.rbIntro = true; pr.items = {RiftlightLantern = 1}; pr.accessoryBag = {"RiftlightLantern"} end)
	local r = breakIt(l, makeNode("Ore", {StrikeKind = "shard", ShardKind = "AetherShard"}))
	ok(r and r.broken and has(r.message, "+4 Aether Shard"), "the Riftlight Lantern adds a shard: " .. tostring(r and r.message))
end
-- Outfit XP bonus through a real bind.
do
	local o = seeded(9111, function(pr)
		pr.rbIntro = true; pr.xp.Runebinding = X[10]
		pr.items = {AetherShard = 10, ShardweaveHood = 1, ShardweaveRobe = 1, ShardweaveLegwraps = 1, ShardweaveBoots = 1}
		pr.equipment = {helmet = "ShardweaveHood", chest = "ShardweaveRobe", legs = "ShardweaveLegwraps", boots = "ShardweaveBoots"}
	end)
	local msg = use(o, "runeAltar", "Gale", "Hub")
	ok(has(msg, "+" .. RB.bindXp(10, 6, 0.06) .. " Runebinding XP"), "the full outfit adds 6% bind XP: " .. tostring(msg))
end
-- Persistence and migration: everything survives a rejoin; junk is cleaned.
do
	local p = seeded(9112, function(pr)
		pr.rbIntro = true; pr.rbBound = "yes"
		pr.runebinding = {bound = {Gale = 7, Bogus = 2}, pouch = {AetherShard = 5}, wear = {MediumPouch = 3}, points = 77, combo = "MistRune", rift = {rounds = 4, wins = 1, best = 30}}
	end)
	local s = rb(p)
	ok(s.bound.Gale == 7 and s.bound.Bogus == nil and s.pouch.AetherShard == 5 and s.points == 77 and s.combo == "MistRune", "journal state persisted")
	ok(s.rift.rounds == 4 and s.rift.wins == 1 and s.rift.best == 30, "rift record persisted")
	eq(s.intro, true, "the intro flag survives")
	rejoin(p, function(pr) eq(pr.rbBound, nil, "a malformed flag is dropped"); eq(pr.runebinding.bound.Bogus, nil, "and the unknown altar") end)
end
-- Quests claim from the journal.
do
	local q = seeded(9113, function(pr)
		pr.questCompleted = 2; pr.rbIntro = true; pr.rbMined = true; pr.rbBound = true; pr.xp.Runebinding = X[5]
	end)
	local msg = verb(q, "quest", "WhispersInTheShard")
	ok(has(msg, "Quest complete") and has(msg, "Whispers in the Shard"), "Whispers in the Shard claims: " .. tostring(msg))
	eq(state(q).items.SmallPouch, 1, "the Small Shard Pouch reward")
	ok(has(verb(q, "quest", "HeartOfTheRift"), "requires"), "Heart of the Rift needs Runebinding 20")
end
print("Part C (server): " .. (checks - partC) .. " checks")

------------------------------------------------------------------------------
-- D. Sources and registration
------------------------------------------------------------------------------
local partD = checks
local combatServer = fs.readFile("combat.server.lua")
ok(has(combatServer, "RB.payPlan(costs, supplies)"), "combat.server pays spells through the rune plan")
ok(has(fs.readFile("combat.client.lua"), "RB.payPlan(costs, S.loadout.supplies)"), "combat.client affordability uses the rune plan")
local server = fs.readFile("server.server.lua")
ok(has(server, 'def.category=="glyph" or def.category=="rune"'), "Ink Thrift (glyphSave) also saves runes")
ok(has(server, "Strike.kinds.shard=") and has(server, "Strike.kinds.riftFragment="), "shard outcrops and fragment heaps are §42 special nodes")
local animate = fs.readFile("animate.client.lua")
ok(has(animate, 'runeAltar = "bind"') and has(animate, "bind = {fx = \"bind\""), "the bind gesture (§47 phrasing) on the altar prompt")
ok(has(fs.readFile("gesture.server.lua"), "bind = true"), "bind relays to observers")
local client = fs.readFile("runes.client.lua")
for _, needle in ipairs({"RB.carryText", "RB.parseRift", "RB.pickerRows", "\"rbTravel\"", "\"riftLeave\"", "RuneBind", "RuneWaygate", "reducedMotion"}) do
	ok(has(client, needle), "runes.client.lua uses " .. needle)
end
ok(has(fs.readFile("default.project.json"), '"IsleRunes": { "$path": "runes.client.lua" }'), "client registered in default.project.json")
ok(has(fs.readFile("verify.luau"), 'IsleRunes = "runes.client.lua"'), "client registered in verify.luau")
ok(has(fs.readFile("scripts/build.sh"), "verify-runebinding.luau"), "suite in build.sh")
ok(has(fs.readFile("build.ps1"), "'verify-runebinding.luau'"), "suite in build.ps1")
ok(has(fs.readFile("ui.client.lua"), "Data.Runebinding.unlocks()"), "the skills panel lists the Runebinding unlock guide")
ok(has(fs.readFile("docs/DEPTH-CONTRACT.md"), "## 49. Runebinding"), "contract §49")
print("Part D (sources): " .. (checks - partD) .. " checks")
print("verify-runebinding: " .. checks .. " checks passed")
print("SUITE-END verify-runebinding.luau")
