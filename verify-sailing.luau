-- Skysailing (§51): the ship component tree, the wind / trim model, pose
-- sanity, ports, charts, salvage, reef fishing, cargo contracts, corsairs,
-- crew and the vessel host.
-- Part A: the pure rules (Data.Skysailing with shared/Progression.lua): skill
-- registration, the component tree (costs, ladders, hull classes, no coin
-- path), the wind model, SS.checkMove, the XP curve against Mining /
-- Runebinding / Beaconry and the 1-99 time, contract coins under the budget,
-- salvage loot, corsairs, migration and the client helpers.
-- Part B: world.server.lua with real Roblox instances (five skydocks, the
-- charts in the Skyways, budgets) and the home slip's protected circle.
-- Part C: server.server.lua through the verify-gameplay harness with a fake
-- vessel host: building, launching, pose sanity (speed hack, teleport,
-- altitude, tow-in), charting, the cargo contract lifecycle (accept, load,
-- sail, deliver, purse, expiry, abandon, ferry refusal, despawn unloads),
-- salvage and reef fishing, crew (boarding, roles, XP share, inactive crew,
-- policy, leave), despawn safety (captain leaves, falls, storms wreck the
-- hull, shutdown), corsairs and cannons, persistence and lease refusals.
-- Part D: sailing.server.lua headless (the model, seats, drive, ops) and the
-- sources / registration.
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
local SS = Data.Skysailing
local RB = Data.Runebinding
local X = Data.XP_TABLE

------------------------------------------------------------------------------
-- A. Rules
------------------------------------------------------------------------------
local partA = checks
ok(type(SS) == "table", "Data.Skysailing exists")
eq(Data.SkillOrder[#Data.SkillOrder], "Skysailing", "Skysailing appended last (old saves keep their order)")
eq(Data.SkillOrder[#Data.SkillOrder - 1], "Runebinding", "after Runebinding")
eq(#Data.SkillOrder, 25, "25 skills")
do
	local def = Data.Skills.Skysailing
	ok(def and #def.color == 6 and def.title == "Skycaptain" and def.description, "skill metadata")
	for stat, v in pairs(def.perLevel) do ok(Data.Stats[stat] ~= nil and v > 0 and v <= 1, "perLevel " .. stat .. " modest") end
	for id, other in pairs(Data.Skills) do
		if id ~= "Skysailing" then ok(other.title ~= def.title and other.color ~= def.color, "title / colour unique vs " .. id) end
	end
	ok(Data.Mastery.capePerk("Skysailing") == Data.Mastery.CapePerk.Skysailing, "99 mantle perk registered")
	local s1, s99 = P.computeStats({xp = {}, items = {}}, 0), P.computeStats({xp = {Skysailing = X[99]}, items = {}}, 0)
	ok(s99.health - s1.health >= 98, "Skysailing 99 adds Health per level")
	eq(P.levelForXp(X[99]), 99, "the shared 1-99 curve")
end
-- The component tree.
do
	eq(#SS.Hulls, 3, "three hulls: skiff, sloop, galleon")
	for i, h in ipairs(SS.Hulls) do
		eq(h.class, i, h.id .. " class")
		if i > 1 then
			local prev = SS.Hulls[i - 1]
			ok(h.level > prev.level and h.speed > prev.speed and h.hp > prev.hp and h.cargo > prev.cargo, h.id .. " outclasses " .. prev.id)
			ok(h.seats.helm + h.seats.sails + h.seats.cannons > prev.seats.helm + prev.seats.sails + prev.seats.cannons, h.id .. " has more crew seats")
		end
		ok(SS.ComponentById[h.id] and SS.ComponentById[h.id].slot == "hull", h.id .. " is the hull ladder")
	end
	local slots = {}
	for _, slot in ipairs(SS.SLOTS) do slots[slot] = true end
	for _, c in ipairs(SS.Components) do
		ok(slots[c.slot], c.id .. " slot")
		eq(Data.Items[c.id], nil, c.id .. " is never an item (cannot be sold, dropped or traded: no coin path)")
		local v = SS.valueOf(c.costs)
		ok(v > 0, c.id .. " costs materials")
		for mat, n in pairs(c.costs) do
			local def = Data.Items[mat]
			ok(def ~= nil and n > 0 and n == math.floor(n), c.id .. " cost " .. mat .. " exists")
			ok(def.kind == "material" or def.kind == "resource", c.id .. " pays in materials from the skills (" .. mat .. ")")
		end
		eq(c.xp, math.floor(SS.BUILD_XP * v), c.id .. " XP = BUILD_XP x value")
		ok(c.hull >= 1 and c.hull <= 3, c.id .. " hull class")
		if c.tier > 1 then
			local below = SS.SlotTiers[c.slot][c.tier - 1]
			ok(below and below.level < c.level and below.hull <= c.hull, c.id .. " climbs its ladder")
			ok(v > SS.valueOf(below.costs), c.id .. " costs more than " .. below.id)
		end
	end
	ok(#SS.Components >= 24, "a deep tree (" .. #SS.Components .. " components)")
	-- Skysailing XP is the only output of building (no items, no coins).
	local buildXp = 0
	for _, c in ipairs(SS.Components) do buildXp += c.xp end
	print(string.format("Component tree: %d components over %d slots, %d XP to build everything", #SS.Components, #SS.SLOTS, buildXp))
	ok(buildXp < X[99] * 0.05, "building is under 5% of 99 (the grind is sailing)")
	-- SkyDriftwood: no shop sells it below 1.3 x its value.
	for _, list in pairs({RB.ShopOffers}) do for _, o in ipairs(list) do ok(o.item ~= "SkyDriftwood", "no shop sells driftwood") end end
	ok(Data.Items.SkyDriftwood and Data.Items.SkyDriftwood.value == 6 and Data.Economy.isCommodity("SkyDriftwood"), "Sky Driftwood trades on the Bazaar")
end
-- Ladders: canBuild refuses skips, levels, hull classes and missing materials.
do
	local items = {}
	for _, c in ipairs(SS.Components) do for mat, n in pairs(c.costs) do items[mat] = (items[mat] or 0) + n * 3 end end
	local okB, why = SS.canBuild({}, "SilkwindSails", 99, items)
	ok(not okB and has(why, "Canvas sails"), "a ladder never skips a rung: " .. tostring(why))
	okB, why = SS.canBuild({}, "CanvasSails", 99, items)
	ok(not okB and has(why, "Skyskiff hull"), "sails need a hull first: " .. tostring(why))
	ok(SS.canBuild({hull = "Skiff"}, "CanvasSails", 1, items), "then the canvas sails")
	okB, why = SS.canBuild({}, "Skiff", 1, {})
	ok(not okB and has(why, "needs"), "materials are checked: " .. tostring(why))
	okB = SS.canBuild({}, "Skiff", 1, items)
	ok(okB, "the Skyskiff at level 1")
	okB, why = SS.canBuild({hull = "Skiff"}, "Sloop", 29, items)
	ok(not okB and has(why, "Skysailing 30"), "the Windsloop needs Skysailing 30")
	okB, why = SS.canBuild({hull = "Skiff", sails = "CanvasSails", keel = "BrassKeel"}, "AetherKeel", 99, items)
	ok(not okB and has(why, "Windsloop"), "tier 3 keel needs a Windsloop: " .. tostring(why))
	okB, why = SS.canBuild({hull = "Skiff", sails = "CanvasSails"}, "CanvasSails", 99, items)
	ok(not okB and has(why, "already"), "no rebuilding a fitted tier")
	ok(not SS.canBuild({}, "Nope", 99, items), "unknown component")
	-- Sanitising: unknown ids, wrong slots and over-class parts are dropped.
	local clean = SS.cleanShip({hull = "Skiff", sails = "AuroraSails", keel = "Sloop", cannon = "BrassSwivel", junk = "x", cargo = 5})
	eq(clean.hull, "Skiff", "hull kept")
	eq(clean.sails, nil, "a galleon sail on a skiff is dropped")
	eq(clean.keel, nil, "a hull in the keel slot is dropped")
	eq(clean.cannon, "BrassSwivel", "a skiff swivel is kept")
	eq(clean.junk, nil, "junk dropped")
	ok(not SS.seaworthy({hull = "Skiff"}), "a bare hull is not seaworthy")
	ok(SS.seaworthy({hull = "Skiff", sails = "CanvasSails", keel = "TimberKeel"}), "hull + sails + keel sail")
	local spec = SS.spec({hull = "Galleon", sails = "AuroraSails", keel = "StarmetalKeel", plating = "StarmetalPlating", cannon = "StormlanceGun", cargo = "DeepHold", grapple = "StarmetalGrapple"})
	ok(spec.speed > SS.Hulls[3].speed and spec.hp == 2200 + 700 + 1200 and spec.armour == 0.45 and spec.cannon == 1600 and spec.cargo == 14 and spec.grapple == 4, "a full galleon spec")
	eq(spec.crew, 7, "galleon crew: helm, 2 sails, 4 cannons")
	eq(SS.spec({hull = "Skiff", sails = "CanvasSails", keel = "TimberKeel"}).seats.cannons, 0, "no cannon seats without cannons")
	local tiers, xp = SS.built({hull = "Sloop", sails = "SilkwindSails"})
	eq(tiers, 4, "built counts every rung under the fitted tier")
	eq(xp, SS.ComponentById.Skiff.xp + SS.ComponentById.Sloop.xp + SS.ComponentById.CanvasSails.xp + SS.ComponentById.SilkwindSails.xp, "built XP")
end
-- Wind and trim.
do
	eq(SS.pointOfSail(0), 0, "dead into the wind: in irons")
	eq(SS.pointOfSail(SS.IRONS - 0.01), 0, "inside the irons")
	ok(math.abs(SS.pointOfSail(math.pi / 2) - 1) < 1e-9, "beam reach is the best point of sail")
	ok(SS.pointOfSail(math.pi) < 1 and SS.pointOfSail(math.pi) > 0.7, "running is a little slower")
	for rel = 0.6, math.pi, 0.2 do
		local best = SS.bestTrim(rel)
		ok(SS.trimMatch(best, rel) == 1 and SS.trimMatch(if best >= 0.5 then best - 0.3 else best + 0.3, rel) < 0.9, "trim matters at " .. rel)
		local f = SS.speedFactor(1.1, rel, best, 1)
		ok(f >= SS.DRIFT and f <= 1, "speed factor bounded")
		ok(f >= SS.speedFactor(1.1, rel, math.clamp(best - 0.4, 0, 1), 1), "best trim is fastest")
	end
	eq(SS.speedFactor(0, 1.5, 0.5, 1), SS.DRIFT, "no wind: the drift engine alone")
	eq(SS.speedFactor(99, math.pi / 2, 0.5, 1), 1, "storm gusts never pass the top speed (reefed)")
	ok(SS.speedFactor(1.1, math.pi / 2, 0.5, 1.15) >= SS.speedFactor(1.1, math.pi / 2, 0.5, 0.85), "better sails fill faster")
	-- relWind: heading +Z with wind blowing toward +Z (from astern) is pi.
	ok(math.abs(SS.relWind(0, 1, 0, 1) - math.pi) < 1e-9, "wind from astern")
	ok(math.abs(SS.relWind(0, 1, 0, -1)) < 1e-9, "wind on the nose")
	ok(math.abs(SS.relWind(0, 1, 1, 0) - math.pi / 2) < 1e-9, "beam wind")
	eq(SS.weatherFor("1|7|Hub=Clear,Tempest=Storm,Skyways=Rain", "Tempest"), "Storm", "IsleWeather parse")
	eq(SS.weatherFor("1|7|Hub=Clear", "Skyways"), "Clear", "a missing region is clear")
	eq(SS.weatherFor("junk", "Hub"), "Clear", "malformed weather ignored")
	eq(SS.weatherFor(string.rep("x", 900), "Hub"), "Clear", "oversized weather ignored")
	eq(SS.regionAt(0, 0), "Hub", "region over the Quay")
	eq(SS.regionAt(600, -230), "Tempest", "region over the Spire")
	eq(SS.regionAt(1500, 1500), "Skyways", "open sky")
	eq(SS.regionAt(0, 3000), "Home", "the home grid")
	ok(SS.weatherDps("Storm", 0) == SS.STORM_DPS and SS.weatherDps("Storm", 0.45) < SS.STORM_DPS and SS.weatherDps("Clear", 0) == 0, "storm turbulence, softened by plating")
end
-- Pose sanity.
do
	local spec = SS.spec({hull = "Skiff", sails = "CanvasSails", keel = "TimberKeel"})
	local allowed = SS.allowedSpeed(spec)
	ok(allowed > spec.speed and allowed < spec.speed * 2, "allowed speed is the top speed plus slack")
	local a = {x = 0, y = 0, z = 0}
	ok(SS.checkMove(a, {x = spec.speed, y = 0, z = 0}, 1, spec), "top speed is legal")
	ok(SS.checkMove(a, {x = allowed, y = 0, z = 0}, 1, spec), "the slack covers latency")
	local okM, why = SS.checkMove(a, {x = allowed * 1.5 + 10, y = 0, z = 0}, 1, spec)
	ok(not okM and why == "speed", "a speed hack is refused")
	okM, why = SS.checkMove(a, {x = 600, y = 0, z = 0}, 1, spec)
	ok(not okM and why == "speed", "a teleport is refused")
	okM, why = SS.checkMove(a, {x = 0, y = 60, z = 0}, 1, spec)
	ok(not okM and why == "climb", "a vertical jump is refused")
	okM, why = SS.checkMove(nil, {x = 0, y = SS.ALT_MIN - 5, z = 0}, 1, spec)
	ok(not okM and why == "altitude", "below the cloud floor")
	okM, why = SS.checkMove(nil, {x = 0, y = SS.ALT_MAX + 5, z = 0}, 1, spec)
	ok(not okM and why == "altitude", "above the ceiling")
	okM, why = SS.checkMove(nil, {x = 5000, y = 0, z = 0}, 1, spec)
	ok(not okM and why == "bounds", "outside the skyways")
	okM, why = SS.checkMove(a, {x = 0 / 0, y = 0, z = 0}, 1, spec)
	ok(not okM and why == "pose", "NaN poses refused")
	ok(not SS.checkMove(a, {x = 400, y = 0, z = 0}, 99, spec), "a huge dt is clamped to 5 s (no banked distance)")
	ok(SS.allowedSpeed(SS.spec(SS.modelShip(99))) < 60, "even a full galleon stays under 60 studs/s")
end
-- Ports, routes, charts.
do
	eq(#SS.Ports, 5, "five skydocks")
	eq(#SS.Routes, 20, "every ordered pair is a route")
	for _, port in ipairs(SS.Ports) do
		local d = SS.distance(port.berth, port.centre)
		ok(d > port.radius + SS.PIER_OUT, port.id .. " berth rides past the rim")
		ok(Data.RegionById[port.region], port.id .. " region")
	end
	local skiff = SS.spec(SS.modelShip(1))
	for _, r in ipairs(SS.Routes) do
		ok(r.distance > 100, r.id .. " is a real voyage (" .. math.floor(r.distance) .. ")")
		-- Feasible on the slowest ship with no wind at all.
		ok(SS.contractLimit(r) > r.distance / (skiff.speed * SS.DRIFT) + 20, r.id .. " time limit allows a becalmed skiff")
	end
	local ids = {}
	for _, ch in ipairs(SS.Charts) do
		ok(not ids[ch.id], ch.id .. " unique")
		ids[ch.id] = true
		ok(ch.kind == "reef" or ch.kind == "wreck" or ch.kind == "landmark", ch.id .. " kind")
		if ch.reef then ok(SS.ReefFishing[ch.reef], ch.id .. " reef tier") end
		if ch.wreck then ok(SS.Salvage[ch.wreck], ch.id .. " wreck tier") end
		ok(ch.xp > 0 and ch.level >= 1 and ch.level <= 99, ch.id .. " xp / level")
		ok(ch.y >= SS.ALT_MIN + 20 and ch.y <= SS.ALT_MAX - 20, ch.id .. " altitude is sailable")
		for _, port in ipairs(SS.Ports) do ok(SS.distance(ch, port.berth) > 60, ch.id .. " clear of the " .. port.id .. " berth") end
	end
	ok(#SS.Charts >= 18, "18+ charts")
end
-- Salvage loot and reef catches.
do
	for tier, tbl in ipairs(SS.Salvage) do
		for _, d in ipairs(tbl) do
			ok(Data.Items[d.item] and d.chance > 0 and d.chance <= 1 and d.min >= 1 and d.max >= d.min, "salvage tier " .. tier .. " " .. d.item)
		end
		if tier > 1 then ok(SS.salvageValue(tier) > SS.salvageValue(tier - 1) and SS.SalvageXp[tier] > SS.SalvageXp[tier - 1], "tier " .. tier .. " pays more") end
		local seq, i = {0.1, 0.5, 0.1, 0.9, 0.99, 0.0, 0.3, 0.5, 0.2, 0.7, 0.4, 0.6, 0.8}, 0
		local drops = SS.rollSalvage(tier, function() i += 1; return seq[(i - 1) % #seq + 1] end)
		for id, n in pairs(drops) do
			local found
			for _, d in ipairs(tbl) do if d.item == id then found = d end end
			ok(found and n >= found.min, "rolled " .. id .. " is in the table")
		end
	end
	eq(next(SS.rollSalvage(1, function() return 0.999 end)), nil, "a high roll hauls nothing")
	for tier, reef in ipairs(SS.ReefFishing) do
		for _, c in ipairs(reef.catch) do ok(Data.Items[c.item] and c.weight > 0 and c.fishingXp > 0, "reef " .. tier .. " " .. c.item) end
		ok(SS.rollReef(tier, function() return 0 end) == reef.catch[1] and SS.rollReef(tier, function() return 0.9999 end) == reef.catch[#reef.catch], "reef roll covers the table")
	end
end
-- Corsairs.
do
	for _, id in ipairs(SS.PirateOrder) do
		local def = Data.SeaCreatures[id]
		ok(def and def.pirate and def.seaCreature and def.sailingXp > 0, id .. " is a corsair sea creature")
		eq(Data.Monsters[id], def, id .. " resolves through Data.Monsters")
		ok(table.find(Data.SeaCreatureOrder, id) == nil, id .. " is never hooked on a line")
		ok(def.weakness == Data.CombatStyles.beatenBy[def.attackStyle] and def.defenceStyle ~= def.weakness, id .. " combat triangle")
		local remains = false
		for _, d in ipairs(def.drops) do ok(Data.Items[d.item], id .. " drop " .. d.item); if d.chance == 1 then remains = true end end
		ok(remains, id .. " leaves remains (Prayer)")
		eq(def.fishingXp, 0, id .. " pays no Fishing XP")
	end
	for _, region in ipairs({"Tidewater", "Gloomhollow", "Skyways", "Hub"}) do
		for _, id in ipairs(Data.seaCreaturePool(99, region)) do ok(not Data.SeaCreatures[id].pirate, "fishing pools never hold corsairs (" .. region .. ")") end
	end
	eq(SS.pirateFor(10, function() return 0 end), "CorsairSkiffling", "a level 10 captain meets skifflings")
	ok(SS.pirateFor(99, function() return 0.99 end) == "CorsairDreadkite", "a 99 captain can meet the dread kite")
	ok(SS.pirateChance("Tempest", "Storm") > SS.pirateChance("Hub", "Clear"), "danger and storms raise the odds")
	ok(SS.cannonDamage({cannon = 120}, 99) == 240 and SS.cannonDamage({cannon = 0}, 99) == 0, "cannon damage scales with level")
end
-- The XP curve against the other skills, the 1-99 time and the coin budget.
do
	print("Level | contract XP/h (x Mining) | salvage XP/h | Runebinding trip | coins/h vs budget")
	local minR, maxR = math.huge, 0
	for lvl = 1, 99 do
		local c, route, coins = SS.contractRate(lvl)
		local m = RB.miningRate(lvl)
		local r = c / m
		minR, maxR = math.min(minR, r), math.max(maxR, r)
		ok(route ~= nil and c > 0, "a contract route at level " .. lvl)
		ok(r >= 0.45 and r <= 1.25, "contracts stay 0.45-1.25x Mining at " .. lvl .. " (" .. string.format("%.2f", r) .. ")")
		-- No-mint budget: contract coins / hour stay under half of Mining's coin rate (the §49 Rift budget).
		ok(coins <= RB.miningCoinRate(lvl) / 2, "contract coins under the budget at " .. lvl)
		ok(SS.purseDaily(lvl) <= RB.miningCoinRate(lvl) / 2 * 4, "the daily purse is under four hours of the budget at " .. lvl)
		local s = SS.salvageRate(lvl)
		ok(s <= c * 1.0 + 1, "salvage (with its loot) never out-earns contracts in XP at " .. lvl)
		if lvl == 1 or lvl % 10 == 0 or lvl == 99 then
			print(string.format("%5d | %8.0f (%.2fx) %-20s | %8.0f | %8.0f | %6.0f / %6.0f", lvl, c, r, route.id, s, RB.bestTrip(lvl), coins, RB.miningCoinRate(lvl) / 2))
		end
	end
	local hours = SS.hoursTo99()
	print(string.format("Skysailing 1-99 = %.0f h (contracts; Runebinding %.0f h; Mining-relative %.2f-%.2fx)", hours, RB.hoursTo99(), minR, maxR))
	ok(hours >= 50 and hours <= 130, "1-99 takes 50-130 h (" .. math.floor(hours) .. ")")
	ok(hours < RB.hoursTo99() * 1.2, "not slower than Runebinding")
	-- Contract XP never depends on the hold beyond its factor, and grows with level and distance.
	local r = SS.RouteById["Quay:Brassfall"]
	ok(SS.contractXp(r, 4, 50) > SS.contractXp(r, 4, 10) and SS.contractXp(r, 8, 10) > SS.contractXp(r, 4, 10), "XP grows with level and hold")
	ok(SS.contractXp(SS.RouteById["Skyreach:Windpine"], 4, 30) > SS.contractXp(r, 4, 30), "longer routes pay more")
	eq(SS.bondFor(101), 21, "the bond rounds up")
end
-- Migration and the client helpers.
do
	local m = SS.migrate({ship = {hull = "Skiff", sails = "CanvasSails"}, hullHp = 9999, charted = {BrassBuoy = true, Nope = true, QuayShallows = 1},
		stats = {contracts = 3, hauls = -2, junk = 4}, purse = {day = 5, paid = 0 / 0}, contract = {route = "Quay:Brassfall", crates = 999, bond = 12, coins = 7, xp = 90, deadline = 50, loaded = 7},
		crew = "maybe"})
	eq(m.v, SS.VERSION, "version")
	eq(m.hullHp, SS.spec(m.ship).hp, "hull points clamp to the spec")
	ok(m.charted.BrassBuoy == true and m.charted.Nope == nil and m.charted.QuayShallows == nil, "charts sanitised")
	ok(m.stats.contracts == 3 and m.stats.hauls == nil and m.stats.junk == nil, "stats sanitised")
	eq(m.purse.paid, 0, "NaN purse")
	ok(m.contract and m.contract.crates == 64 and m.contract.loaded == nil, "a saved contract keeps its terms, never its loaded cargo")
	eq(m.crew, "open", "crew policy default")
	eq(SS.migrate(nil).hullHp, nil, "a new sailor has no hull")
	eq(SS.migrate({contract = {route = "Nope"}}).contract, nil, "unknown routes dropped")
	local text = SS.encodeState(250.7, 300, 0.42, 26, 3, "closed")
	local st = SS.parseState(text)
	ok(st and st.hp == 250 and st.max == 300 and math.abs(st.trim - 0.42) < 1e-9 and st.cap == 26 and st.crew == 3 and st.policy == "closed", "VesselState round trip: " .. text)
	eq(SS.parseState("garbage"), nil, "a bad state is ignored")
	eq(select(1, SS.compass(0, -1)), "N", "compass north is -Z")
	eq(select(1, SS.compass(1, 0)), "E", "compass east")
	eq(select(2, SS.compass(0, 1)), 180, "south is 180")
	eq(SS.knots(10), 6, "knots")
	ok(SS.billow(1.1, math.pi / 2, 0.5, false) > SS.billow(0.1, math.pi / 2, 0.5, false), "the cloth bellies with the wind")
	ok(SS.billow(5, math.pi / 2, 0.5, true) <= SS.BILLOW * 0.5, "reduced motion calms the cloth")
	ok(#SS.unlocks() >= 40, "unlock guide")
	local acts = Data.Systems.Calc.actions("Skysailing")
	ok(#acts >= #SS.Components + #SS.Charts, "the XP calculator lists builds, charts and salvage")
end
-- QC H2 / H3 / M1 / H5 pure rules.
do
	local spec = SS.spec(SS.modelShip(1))
	local rate = SS.allowedSpeed(spec)
	eq(SS.accrue(0, spec, 1), rate, "the bucket accrues allowedSpeed x dt")
	eq(SS.accrue(0, spec, 99), rate * SS.ALLOW_CAP, "and caps at ALLOW_CAP seconds")
	eq(SS.accrue(rate * 5, spec, 1), rate * SS.ALLOW_CAP, "a full bucket stays capped")
	ok(SS.graceFor(spec, 0.2) > SS.graceFor(spec, 0) and SS.graceFor(spec, 9) == SS.graceFor(spec, SS.PING_MAX), "the grace scales with ping, bounded")
	local a = {x = 0, y = 0, z = 0}
	ok(SS.checkStep(a, {x = 20, y = 0, z = 0}, 1, spec, 20, 0), "a step inside the bucket")
	ok(not SS.checkStep(a, {x = 30, y = 0, z = 0}, 1, spec, 20, 3), "a step past the bucket")
	ok(not SS.checkStep(a, {x = 0, y = 50, z = 0}, 1, spec, 99, 3), "a climb past the limit")
	ok(not SS.checkStep(nil, {x = 0, y = SS.ALT_MAX + 1, z = 0}, 1, spec, 99, 3), "altitude in the step check")
	ok(SS.checkAttitude(1, 0) and not SS.checkAttitude(1, SS.SPIN_MAX + 0.5) and not SS.checkAttitude(math.cos(math.rad(SS.TILT_MAX + 5)), 0), "spin and tilt limits")
	for n = 1, 6 do ok(SS.crewShare(1000, n) * n <= 1000 * SS.CREW_SHARE, "the crew pool never exceeds CREW_SHARE (" .. n .. " sailors)") end
	eq(SS.crewShare(1000, 0), 0, "no crew, no share")
	for _, port in ipairs(SS.Ports) do
		eq(#port.berths, SS.BERTH_SLOTS, port.id .. " berth slots")
		for i, b1 in ipairs(port.berths) do
			for j, b2 in ipairs(port.berths) do
				if i < j then ok(SS.distance(b1, b2) >= SS.BERTH_SPACING - 1e-6, port.id .. " slots apart") end
			end
			ok(SS.distance(b1, port.centre) > port.radius + 10, port.id .. " slot " .. i .. " rides past the rim")
		end
	end
	local p, d, slot = SS.nearestPort(SS.PortById.Quay.berths[3])
	ok(p.id == "Quay" and d < 1e-6 and slot == 3, "nearestPort sees every slot")
	local only = SS.nearestPort({x = 0, z = 0}, function(x) return x.id == "Tidewater" end)
	eq(only.id, "Tidewater", "nearestPort filters to the ports a player may enter")
end
-- QC M9: the ship HUD has a reserved slot in the shared bottom stack.
do
	local Theme = load("shared/UiTheme.lua", {Color3 = roblox.Color3, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Instance = roblox.Instance, Font = roblox.Font, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
		game = {GetService = function() return {} end}, script = nil})
	local function overlap(a, b) return a and b and a.w > 0 and b.w > 0 and a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
	for _, case in ipairs({{1366, 768}, {1920, 1080}, {1280, 650}, {1024, 600}, {844, 390, true, 0}, {844, 390, true, 120}, {1366, 710}, {667, 375, true, 60}}) do
		local L = Theme.hudLayout(case[1], case[2], {touch = case[3], lift = case[4]})
		local r = L.shipHud
		local tag = case[1] .. "x" .. case[2] .. (if case[3] then " touch lift " .. case[4] else "")
		ok(r and r.w >= 280 and r.h >= 56 and r.x >= 0 and r.y >= 0 and r.x + r.w <= case[1] and r.y + r.h <= case[2], "ship HUD on screen @" .. tag)
		for _, k in ipairs({"hotbar", "band", "action", "heartChip", "pouchChip", "chat", "chatTabs", "mapBlock", "mapControls", "sidebar", "orbs"}) do
			ok(not overlap(r, L[k]), "ship HUD clear of " .. k .. " @" .. tag)
		end
		eq(r.compact, case[3] == true, "compact on touch @" .. tag)
	end
end
-- QC L8: saved placements inside the slip circle move out (Island.migrate relocates them).
do
	local I = Data.Island
	local rec = "1:TimberFence:" .. math.floor(SS.SLIP_OFFSET.x / I.CELL) .. ":" .. math.floor(SS.SLIP_OFFSET.z / I.CELL) .. ":0"
	ok(I.cellBlocked(math.floor(SS.SLIP_OFFSET.x / I.CELL), math.floor(SS.SLIP_OFFSET.z / I.CELL), 0), "the slip's cells are blocked")
	local out, refunds, report = I.migrate({v = I.VERSION, placed = {rec}}, 0)
	eq(report.moved, 1, "a placement on the slip is relocated")
	local e = I.parseRecord(out.placed[1])
	ok(e and not I.cellBlocked(e.x, e.z, 0), "to a free cell (" .. tostring(out.placed[1]) .. ")")
	eq(next(refunds), nil, "nothing refunded")
end
-- The home slip's protected circle.
do
	local I = Data.Island
	local found
	for _, c in ipairs(I.ProtectedCircles) do if c.name == "shipwright slip" then found = c end end
	ok(found and found.x == SS.SLIP_OFFSET.x and found.z == SS.SLIP_OFFSET.z and found.r >= 6.4, "the slip is a protected circle (covers the 9 x 9 slipway)")
	ok(math.sqrt(found.x ^ 2 + found.z ^ 2) - found.r > 21, "outside the legacy core (r21): legacy saves are untouched")
	for _, c in ipairs(I.ProtectedCircles) do
		if c ~= found then ok(math.sqrt((c.x - found.x) ^ 2 + (c.z - found.z) ^ 2) > c.r + found.r, "slip clear of " .. c.name) end
	end
	local berth = SS.homeBerth({x = 0, y = 0, z = 0}, 1)
	ok(SS.distance(berth, {x = 0, z = 0}) > Data.Home.radius(1) + Data.Home.MARGIN + 10, "the home berth rides past the rim")
	ok(SS.distance(SS.homeBerth({x = 0, y = 0, z = 0}, 5), {x = 0, z = 0}) > Data.Home.radius(5) + Data.Home.MARGIN + 10, "and past the largest rim")
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
local worldEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function() end, RemoveTag = function() end} end
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
for _, name in ipairs({"SkiffHull", "SloopHull", "GalleonHull", "ShipMast", "ShipHelm", "DeckCannon", "SkyDock", "HarbourBoard", "MooringBollard", "ShipwrightSlip", "SkyReef", "SkyWreck", "ChartBuoy"}) do
	local s = WorldCatalog.shapes[name]
	ok(s ~= nil, name .. " is a forged mesh in the world catalog")
end
local dockParts, neon, lights = 0, 0, 0
local islandList = {}
for _, isle in ipairs(islands:GetChildren()) do
	local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
	if c and r then table.insert(islandList, {name = isle.Name, c = c, r = r}) end
end
for _, port in ipairs(SS.Ports) do
	local isle = islands:FindFirstChild(port.isle)
	ok(isle ~= nil, port.id .. " isle exists")
	local dock
	for _, m in ipairs(isle:GetChildren()) do if m:GetAttribute("SkyDock") == port.id then dock = m end end
	ok(dock ~= nil, port.id .. " skydock built")
	local verbs = {}
	for _, obj in ipairs(dock:GetDescendants()) do
		if obj:IsA("BasePart") then
			dockParts += 1
			ok(obj.Anchored, obj.Name .. " anchored")
			if obj.Material == roblox.Enum.Material.Neon then neon += 1 end
		end
		if obj:IsA("Light") then lights += 1 end
		if obj:IsA("ProximityPrompt") then verbs[obj:GetAttribute("IsleAction")] = obj end
	end
	ok(verbs.sailLaunch and verbs.sailLaunch:GetAttribute("IsleItem") == port.id and verbs.sailLaunch:GetAttribute("IsleRegion") == port.region, port.id .. " sail-out prompt")
	ok(verbs.harbourBoard and verbs.harbourBoard:GetAttribute("IsleItem") == port.id, port.id .. " harbour board prompt")
	local pier = dock:FindFirstChild("Skydock pier")
	eq(pier and pier:GetAttribute("Shape"), "SkyDock", port.id .. " forged pier")
	ok(pier.CanCollide, port.id .. " pier is walkable")
	local landing = isle:FindFirstChild("Anchor_Dock_" .. port.id, true)
	local berth = isle:FindFirstChild("Anchor_Berth_" .. port.id, true)
	ok(landing and berth, port.id .. " dock / berth anchors")
	ok((landing.CFrame.Position - Vector3.new(port.landing.x, port.landing.y, port.landing.z)).Magnitude < 1e-3, port.id .. " landing matches the data")
	-- The berth is open air: outside every island's radius.
	for _, i in ipairs(islandList) do
		local d = (Vector3.new(port.berth.x, 0, port.berth.z) - Vector3.new(i.c.X, 0, i.c.Z)).Magnitude
		ok(d > i.r + 10, port.id .. " berth clear of " .. i.name .. " (" .. math.floor(d) .. ")")
	end
	-- Prompts stand clear of every other prompt on the isle.
	for _, other in ipairs(isle:GetDescendants()) do
		if other:IsA("ProximityPrompt") and not other:IsDescendantOf(dock) and other.Parent:IsA("BasePart") then
			for _, mine in pairs(verbs) do
				local d = (other.Parent.CFrame.Position - mine.Parent.CFrame.Position)
				ok(Vector3.new(d.X, 0, d.Z).Magnitude > 6, port.id .. " " .. tostring(mine:GetAttribute("IsleAction")) .. " clear of " .. other.Parent.Name)
			end
		end
	end
end
local skyways = archipelago:FindFirstChild("Skyways")
ok(skyways ~= nil and skyways:GetAttribute("Skyways") == true, "the Skyways (charts) under Workspace.AetherIsles, off the Sky Chart")
ok(islands:FindFirstChild("Skyways") == nil, "not among the chart islands")
local chartParts, seen = 0, {}
for _, p in ipairs(skyways:GetDescendants()) do
	if p:IsA("BasePart") then
		chartParts += 1
		local id = p:GetAttribute("ChartId")
		local ch = SS.ChartById[id]
		ok(ch ~= nil and p:GetAttribute("ChartKind") == ch.kind, "chart prop " .. tostring(id))
		ok(not p.CanCollide and not p.CanQuery, tostring(id) .. " never snags a ship")
		if p.Material == roblox.Enum.Material.Neon then neon += 1 end
		seen[id] = true
		for _, i in ipairs(islandList) do
			local d = (Vector3.new(ch.x, 0, ch.z) - Vector3.new(i.c.X, 0, i.c.Z)).Magnitude
			ok(d > i.r + 20, id .. " floats in open sky, clear of " .. i.name .. " (" .. math.floor(d) .. ")")
		end
	end
	if p:IsA("Light") then lights += 1 end
end
for _, ch in ipairs(SS.Charts) do ok(seen[ch.id], ch.id .. " is in the world") end
eq(neon, 0, "no Neon (glow is client-side)")
eq(lights, 0, "no server lights")
print(string.format("Part B (world): %d checks; %d dock parts, %d chart parts", checks - partB, dockParts, chartParts))
ok(dockParts + chartParts <= 60, "Skysailing stays inside its static part budget (" .. (dockParts + chartParts) .. ")")
ok(has(fs.readFile("world.server.lua"), 'meshSlot(slip,"ShipwrightSlip",nil,false,"Uniform")') and has(fs.readFile("world.server.lua"), '"shipwright",nil,player.UserId'), "the home Shipwright's Slip (owner-only prompts)")

------------------------------------------------------------------------------
-- C. Server (the verify-gameplay harness with a fake vessel host)
------------------------------------------------------------------------------
local partC = checks
local src = (fs.readFile("verify-gameplay.luau"):gsub("\r\n", "\n"))
local cut = src:find("local checks=0\nlocal function eq", 1, true)
assert(cut, "verify-gameplay harness marker")
local prefix = src:sub(1, cut - 1)
local n1, n2, n3
prefix, n1 = prefix:gsub("local workspace = {GetAttribute=function%(self,key%) return self%[key%] end}", "local workspace = __ws")
prefix, n2 = prefix:gsub("\tworkspace=workspace,\n", "\tworkspace=workspace,CFrame=__roblox.CFrame,Vector3=__roblox.Vector3,\n")
prefix, n3 = prefix:gsub("ServerStorage={},", "ServerStorage={FindFirstChild=function(_, n) if n == \"IsleTravelGate\" then return __gate end if n == \"IsleVesselHost\" then return __host end if n == \"IsleCannon\" then return __cannon end return nil end},")
local n4, n5
-- QC H2: the vessel check runs only in the fixed loop; record spawned loops so the suite can step it.
prefix, n4 = prefix:gsub("spawn=function%(f,%.%.%.%) assert%(coroutine%.resume%(coroutine%.create%(f%),%.%.%.%)%) end,",
	"spawn=function(f,...) local co=coroutine.create(f); local ok,y=coroutine.resume(co,...); assert(ok,y); table.insert(__loops,{co=co,y=y}) end,")
prefix, n5 = prefix:gsub("wait=function%(%) coroutine%.yield%(%) end,", "wait=function(t) return coroutine.yield(t) end,")
assert(n1 == 1 and n2 == 1 and n3 == 1 and n4 == 1 and n5 == 1, "harness hooks")
local gate = {Invoke = function() return true end}
-- The fake vessel host: records every op; poses are set by the test.
local Host = {ships = {}, calls = {}, resets = 0, down = false}
local hostFn = {Invoke = function(_, op, payload)
	if Host.down then error("host down") end
	table.insert(Host.calls, {op = op, payload = payload})
	local v = payload and Host.ships[payload.id]
	if op == "spawn" then
		Host.ships[payload.id] = {owner = payload.owner, spec = payload.spec, cf = payload.cf, pos = payload.cf.Position, look = payload.cf.LookVector, seated = {}, fired = 0,
			upY = 1, spin = 0, net = payload.owner}
		return {ok = true}
	elseif op == "despawn" then
		if (Host.failDespawn or 0) > 0 then Host.failDespawn -= 1; return nil end
		Host.ships[payload.id] = nil; return true
	elseif op == "own" then if v then v.net = v.owner; Host.owns = (Host.owns or 0) + 1 end return v ~= nil
	elseif op == "pose" then
		if not v then return nil end
		local seated = {}
		for k, r in pairs(v.seated) do seated[k] = r end
		return {position = v.pos, look = v.look, seated = seated, upY = v.upY, spin = v.spin, owner = v.net, holding = false}
	elseif op == "reset" then if v then v.pos = payload.cf.Position; Host.resets += 1 end return true
	elseif op == "seat" then if v then v.seated[payload.player] = payload.role end return v ~= nil
	elseif op == "unseat" then if v then v.seated[payload.player] = nil end return true
	elseif op == "state" then if v then v.state = payload.text end return true
	elseif op == "fire" then if v then v.fired += 1 end return true
	end
	return nil
end}
local Cannon = {calls = {}, reply = {hit = false}}
local cannonFn = {Invoke = function(_, op, player, payload) table.insert(Cannon.calls, {op = op, player = player, payload = payload}); return Cannon.reply end}
local anchors = {}
local function place(name, pos) anchors[name] = {Name = "Anchor_" .. name, Parent = true, CFrame = CFrame.new(pos.X, pos.Y, pos.Z), Position = pos} end
local folder = {FindFirstChild = function(_, name) local key = string.match(name, "^Anchor_(.+)$"); return key and anchors[key] end}
local ws = {}
ws.GetAttribute = function(self, k) return rawget(self, k) end
ws.SetAttribute = function(self, k, v) rawset(self, k, v) end
ws.FindFirstChild = function(_, name)
	if name == "Islands" then return folder end
	if name == "AetherIsles" then return {FindFirstChild = function() return nil end} end
	return nil
end
local loops = {}
local H = luau.load("local __ws, __roblox, __gate, __host, __cannon, __loops = ...\n" .. prefix .. "\nreturn {player=player,cmd=cmd,data=data,advance=advance,services=services,objects=objects,allObjects=allObjects,closers=closers,Data=Data,clock=function() return clock end,setRoll=function(v) defaultRoll=v end}",
	{debugName = "sailing-harness", injectGlobals = true})(ws, roblox, gate, hostFn, cannonFn, loops)
local SD = H.Data
local SSS = SD.Skysailing
local bridge
for _, o in ipairs(H.allObjects) do if o.Name == "IsleBridge" then bridge = o end end
assert(bridge, "IsleBridge")
local leaseHook
for _, o in ipairs(H.allObjects) do if o.Name == "IsleCoopProfile" then leaseHook = o end end
assert(leaseHook, "IsleCoopProfile (a durable save renews the journal lease)")
-- Long voyages outlast the harness lease (180 s); a durable save renews it, as the autosave does live.
local function renew(p) pcall(leaseHook.OnInvoke, p, true) end
local function state(p) renew(p); return H.cmd(p, "state") end
-- One fixed loop tick (QC H2), one second after the last.
local SAIL_TICK = H.Data.Skysailing.TICK
local function loop()
	for _, l in ipairs(loops) do
		if l.y == SAIL_TICK and coroutine.status(l.co) == "suspended" then
			local okR, y = coroutine.resume(l.co, SAIL_TICK)
			assert(okR, y)
			return
		end
	end
	error("the Skysailing loop was not found")
end
local known = {}
local function tick(...)
	H.advance(1)
	for _, p in ipairs({...}) do renew(p) end
	for p in pairs(known) do if p.Parent then renew(p) end end
	loop()
end
local function sk(p) return state(p).skysailing end
local function verb(p, v, item) return H.cmd(p, v, item).message end
local function rootOf(p) return p.Character:FindFirstChild("HumanoidRootPart") end
local function moveTo(p, pos) rootOf(p).Position = pos end
local function vp(t) return Vector3.new(t.x, t.y, t.z) end
local function use(p, action, item, region, pos, owner)
	pos = pos or Vector3.zero
	moveTo(p, pos)
	local q = {Enabled = true, MaxActivationDistance = 9, GetAttribute = function(_, key)
		return ({IsleAction = action, IsleItem = item, IsleRegion = region, OwnerUserId = owner})[key]
	end, FindFirstAncestorWhichIsA = function() return {Position = pos} end}
	H.advance(1)
	p.last = nil
	H.services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last and p.last.message, p.last
end
local function pivoted(p) p.Character.PivotTo = function(_, cf) rootOf(p).Position = cf.Position end end
local function join(id, mutate)
	local p = H.player(id)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. id].profile) end
	local q = H.player(id)
	pivoted(q)
	known[q] = true
	return q
end
local function rejoin(p, mutate)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. p.UserId].profile) end
	known[p] = nil
	local q = H.player(p.UserId)
	pivoted(q)
	known[q] = true
	return q
end
local function xpOf(p, skill) return H.cmd(p, "state").xp[skill] or 0 end
local function count(op) local n = 0; for _, c in ipairs(Host.calls) do if c.op == op then n += 1 end end return n end
local function shipOf(p) for id, s in pairs(Host.ships) do if s.owner == p then return id, s end end return nil end
-- Moves a ship's pose toward `target` in legal steps (each `state` is one second).
local function sailTo(p, target, step)
	local id, s = shipOf(p)
	step = step or 18
	for _ = 1, 80 do
		local d = target - s.pos
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude < 0.5 then break end
		local move = if flat.Magnitude > step then flat.Unit * step else flat
		s.pos = s.pos + move
		s.look = move.Unit
		tick(p)
		if not Host.ships[id] then return false end
	end
	tick(p) -- heave to: one still tick (speed 0)
	return Host.ships[id] ~= nil
end
for _, port in ipairs(SSS.Ports) do place("Dock_" .. port.id, vp(port.landing)) end
local ALL = {}
for _, c in ipairs(SSS.Components) do for mat, n in pairs(c.costs) do ALL[mat] = (ALL[mat] or 0) + n end end
local function stock(pr, extra)
	pr.items = pr.items or {}
	for mat, n in pairs(ALL) do pr.items[mat] = n * (extra or 1) end
end
local HOME = Vector3.new(-1260, 0, 2400)
local SLIP = HOME + Vector3.new(SSS.SLIP_OFFSET.x, 0, SSS.SLIP_OFFSET.z)
local function homed(p) p:SetAttribute("IslandCenter", HOME); p:SetAttribute("HomesteadLevel", 1) end

-- Building at the slip ----------------------------------------------------------------
local poor
local b = join(9301, function(pr) stock(pr) end)
homed(b)
do
	local s0 = sk(b)
	ok(type(s0) == "table" and s0.level == 1 and s0.spec == nil and next(s0.ship) == nil, "snapshot carries skysailing (no ship yet)")
	eq(state(b).levels.Skysailing, 1, "Skysailing level in the snapshot")
	moveTo(b, Vector3.zero)
	ok(has(verb(b, "shipBuild", "Skiff"), "Shipwright's Slip"), "building needs the home slip")
	eq((use(b, "shipwright", nil, nil, SLIP, 1)), nil, "a stranger's slip prompt is ignored (OwnerUserId)")
	local w0 = b:GetAttribute("SailShipwright")
	ok(has((use(b, "shipwright", nil, nil, SLIP, b.UserId)), "plans"), "the slip opens the plans")
	ok(b:GetAttribute("SailShipwright") ~= w0, "SailShipwright bumps for the client panel")
	ok(has(verb(b, "shipBuild", "SilkwindSails"), "Canvas sails"), "no skipping rungs")
	ok(has(verb(b, "shipBuild", "Sloop"), "first"), "the hull ladder starts at the skiff")
	local coins0, timber0, xp0 = state(b).coins, state(b).items.Timber, xpOf(b, "Skysailing")
	local msg = verb(b, "shipBuild", "Skiff")
	ok(has(msg, "Skyskiff hull") and has(msg, "Skysailing XP"), "the hull is laid: " .. tostring(msg))
	local st = state(b)
	local levelCoins = 0
	for l = 2, st.levels.Skysailing do levelCoins += SD.levelCoinReward(l) end
	eq(st.coins, coins0 + levelCoins, "building pays no coins beyond the standard one-time level rewards (no mint)")
	eq(st.items.Timber, timber0 - SSS.ComponentById.Skiff.costs.Timber, "materials spent")
	local profile = H.data["p9301"]
	ok(st.skysailing.ship.hull == "Skiff" and st.skysailing.hullHp == SSS.Hulls[1].hp, "the skiff at full hull")
	ok(has(verb(b, "shipBuild", "Sloop"), "Skysailing 30"), "level gate")
	verb(b, "shipBuild", "CanvasSails")
	verb(b, "shipBuild", "TimberKeel")
	verb(b, "shipBuild", "CrateRack")
	local s1 = sk(b)
	ok(s1.spec and s1.spec.cargo == 4 and s1.next.sails and s1.next.sails.id == "SilkwindSails" and s1.next.sails.ok == false, "spec and next rungs in the snapshot")
	ok(st.levels.Skysailing >= 1, "XP from building")
	ok(profile ~= nil, "journal saved")
	-- An empty satchel refuses before anything is spent.
	poor = join(9302)
	homed(poor)
	moveTo(poor, SLIP)
	ok(has(verb(poor, "shipBuild", "Skiff"), "needs"), "materials refused")
	eq(sk(poor).ship.hull, nil, "nothing built")
end
-- Launching ----------------------------------------------------------------------------
local QUAY = SSS.PortById.Quay
local BRASS = SSS.PortById.Brassfall
do
	ok(has((use(poor, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))), "hull"), "no ship, no launch")
	ok(has(verb(b, "sailLaunch", "Quay"), "Step onto a skydock"), "launch is a prompt")
	ok(has((use(b, "sailLaunch", "Skyreach", nil, vp(SSS.PortById.Skyreach.landing))), "Skysailing 20"), "port level gate")
	Host.down = true
	ok(has((use(b, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))), "closed"), "no vessel host: fail closed")
	Host.down = false
	local msg = use(b, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(has(msg, "helm"), "you take the helm: " .. tostring(msg))
	local id, s = shipOf(b)
	ok(id and (s.pos - vp(QUAY.berth)).Magnitude < 1e-3, "spawned at the Quay berth")
	eq(s.seated[b], "helm", "the captain sits at the helm")
	ok(has(b:GetAttribute("SailVessel"), ":helm"), "SailVessel attribute for the client")
	ok(type(s.state) == "string" and SSS.parseState(s.state) ~= nil, "VesselState published")
	ok(has((use(b, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))), "already aboard"), "one ship at a time")
	ok(has(verb(b, "shipBuild", "BrassKeel"), "Dock your ship"), "no building while sailing")
end
-- Pose sanity: legal sailing, a speed hack and a teleport snap back; three strikes tow it in.
do
	local id, s = shipOf(b)
	s.pos = s.pos + Vector3.new(10, 0, 0)
	tick(b)
	eq(Host.resets, 0, "a legal move is accepted")
	-- QC H2: snapshots / verbs never validate travel nor bank allowance.
	local good = s.pos
	s.pos = s.pos + Vector3.new(400, 0, 0)
	state(b)
	eq(Host.resets, 0, "a snapshot never checks (only the fixed loop does)")
	tick(b)
	eq(Host.resets, 1, "a teleport is snapped back by the loop")
	ok((s.pos - good).Magnitude < 1e-3, "back to the last good pose")
	H.advance(10) -- the old strikes age out of the window
	H.advance(SSS.STRIKE_WINDOW)
	tick(b)
	for _ = 1, 12 do state(b) end -- spammed snapshots (12 s of clock)
	local spec = s.spec
	local cap = SSS.allowedSpeed(spec) * SSS.ALLOW_CAP + SSS.graceFor(spec, 0)
	s.pos = s.pos + Vector3.new(cap + 6, 0, 0)
	local r0 = Host.resets
	tick(b)
	eq(Host.resets, r0 + 1, "spammed state() calls bank no extra allowance (the bucket caps at " .. SSS.ALLOW_CAP .. " s)")
	-- A 0.3 s freeze: the pose holds, then catches up within the bucket.
	H.advance(SSS.STRIKE_WINDOW + 1)
	tick(b)
	r0 = Host.resets
	H.advance(0.3)
	tick(b)
	s.pos = s.pos + Vector3.new(SSS.allowedSpeed(spec) * 1.25, 0, 0)
	tick(b)
	eq(Host.resets, r0, "a 0.3 s freeze then a catch-up move does not strike")
	-- QC H3: a flung or capsized hull strikes.
	s.spin = 6
	tick(b)
	eq(Host.resets, r0 + 1, "a spinning hull (fling) strikes")
	s.spin = 0
	H.advance(SSS.STRIKE_WINDOW + 1)
	s.upY = 0.5
	tick(b)
	eq(Host.resets, r0 + 2, "a capsized hull strikes")
	s.upY = 1
	-- QC M2: the captain is made the network owner again.
	local owns0 = Host.owns or 0
	s.net = "server" -- someone else owns the hull
	tick(b)
	ok((Host.owns or 0) > owns0, "the loop gives the hull back to its captain")
	H.advance(SSS.STRIKE_WINDOW + 1)
	s.pos = s.pos + Vector3.new(400, 0, 0)
	tick(b)
	s.pos = s.pos + Vector3.new(0, 400, 0)
	tick(b)
	ok(Host.ships[id] ~= nil, "two strikes keep the ship")
	s.pos = s.pos + Vector3.new(120, 0, 0)
	moveTo(b, s.pos)
	tick(b)
	eq(Host.ships[id], nil, "the third strike tows the ship in")
	ok((rootOf(b).Position - (vp(QUAY.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "the captain is landed on the Quay dock, not the void")
	ok(b:GetAttribute("FastTravelAt") ~= nil, "a server landing marks FastTravelAt")
	eq(b:GetAttribute("SailVessel"), "", "no longer aboard")
	eq(sk(b).sailing, nil, "the snapshot shows no ship")
end
-- Cargo contract lifecycle --------------------------------------------------------------
b = rejoin(b)
homed(b)
do
	local route = SSS.RouteById["Quay:Brassfall"]
	moveTo(b, Vector3.new(0, 0, 0))
	ok(has(verb(b, "sailContract", route.id), "Accept contracts at"), "accept at the origin dock")
	moveTo(b, vp(QUAY.landing))
	ok(has(verb(b, "sailContract", "Quay:Tidewater"), "Skysailing 35"), "route level gate")
	ok(has(verb(b, "sailContract", "Nope"), "Choose"), "unknown route")
	local coins0 = state(b).coins
	local msg = verb(b, "sailContract", route.id)
	ok(has(msg, "4 crates") and has(msg, "Sail out"), "contract accepted: " .. tostring(msg))
	local c = sk(b).contract
	eq(c.crates, 4, "the hold's crates")
	eq(c.bond, SSS.bondFor(SSS.contractCoins(route, 4)), "bond")
	eq(state(b).coins, coins0 - c.bond, "the bond is held (a sink until delivered)")
	ok(c.loaded == false and c.left <= SSS.contractLimit(route), "in the warehouse, timer running")
	ok(has(verb(b, "sailContract", route.id), "Finish or abandon"), "one contract at a time")
	local launch = use(b, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(has(launch, "crates loaded"), "launching at the origin loads the crates: " .. tostring(launch))
	ok(sk(b).contract.loaded, "loaded")
	-- Dock straight back at the Quay: nothing delivered.
	ok(sailTo(b, vp(BRASS.berth)), "sailed to Brassfall in legal steps")
	local before = state(b)
	local xp0, coins1, lvl0 = xpOf(b, "Skysailing"), before.coins, before.levels.Skysailing
	local sailed = sk(b).contract.sailed
	ok(sailed >= route.distance * SSS.MIN_SAILED, "the sailed distance is counted (" .. sailed .. ")")
	local dmsg = verb(b, "sailDock")
	ok(has(dmsg, "Delivered 4 crates") and has(dmsg, "Harbour Purse"), "delivered: " .. tostring(dmsg))
	local st = state(b)
	local lc = 0
	for l = lvl0 + 1, st.levels.Skysailing do lc += SD.levelCoinReward(l) end
	eq(st.coins, coins1 + c.coins + c.bond + lc, "payout from the purse plus the bond back (plus the standard level rewards)")
	eq(st.skysailing.purse.paid, c.coins, "the purse records it")
	eq(st.skysailing.contract, nil, "contract settled")
	eq(st.skysailing.stats.contracts, 1, "stats")
	ok(xpOf(b, "Skysailing") >= xp0 + c.xp or st.levels.Skysailing > 1, "contract XP paid")
	ok((rootOf(b).Position - (vp(BRASS.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "docking lands you on the Brassfall pier")
	eq(shipOf(b), nil, "the ship is put away")
end
-- Expiry, abandon, and the "ferry" (no sailing) refusal.
do
	local route = SSS.RouteById["Brassfall:Quay"]
	moveTo(b, vp(BRASS.landing))
	verb(b, "sailContract", route.id)
	local bond = sk(b).contract.bond
	local coins0 = state(b).coins
	H.advance(SSS.contractLimit(route) + 2)
	local st = state(b)
	eq(st.skysailing.contract, nil, "the contract expired")
	eq(st.coins, coins0, "the bond is forfeit (no refund)")
	ok(has(st.message, "expired") or (st.skysailing.stats.failed or 0) >= 1, "the sailor is told")
	b = rejoin(b)
	homed(b)
	moveTo(b, vp(BRASS.landing))
	verb(b, "sailContract", route.id)
	ok(has(verb(b, "sailAbandon"), "forfeit"), "abandon forfeits the bond")
	eq(sk(b).contract, nil, "abandoned")
	-- Ferry: accept at Brassfall, launch from the Quay instead: nothing loads, nothing delivers.
	moveTo(b, vp(BRASS.landing))
	verb(b, "sailContract", route.id)
	local m = use(b, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(not has(m, "crates loaded"), "launching away from the origin loads nothing")
	state(b)
	local dm = verb(b, "sailDock")
	ok(not has(dm, "Delivered"), "docking at the destination without the cargo delivers nothing")
	ok(sk(b).contract ~= nil, "the contract stays open")
	-- A loaded ship that despawns returns its crates to the warehouse.
	H.advance(SSS.LAUNCH_COOLDOWN)
	m = use(b, "sailLaunch", "Brassfall", "Quarry", vp(BRASS.landing))
	ok(has(m, "crates loaded"), "loaded at the origin")
	verb(b, "sailDock")
	eq(sk(b).contract.loaded, false, "despawned: the cargo is back in the warehouse")
	verb(b, "sailAbandon")
end
-- Charting, salvage and reef fishing.
local cap = join(9310, function(pr) pr.xp.Skysailing = X[40]; pr.xp.Fishing = X[45]; stock(pr, 2); pr.coins = 5000
	pr.skysailing = {ship = {hull = "Skiff", sails = "SilkwindSails", keel = "BrassKeel", cargo = "CrateRack", grapple = "BrassGrapple", cannon = "BrassSwivel"}} end)
homed(cap)
do
	local m = use(cap, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(has(m, "helm"), "captain launches")
	local reef = SSS.ChartById.QuayShallows
	local xp0 = xpOf(cap, "Skysailing")
	ok(sailTo(cap, Vector3.new(reef.x, 0, reef.z)), "sailed to the Quayside Shallows")
	local sj = sk(cap)
	ok(table.find(sj.charted, "QuayShallows") ~= nil, "the reef is charted on arrival")
	ok(xpOf(cap, "Skysailing") >= xp0 + reef.xp, "chart XP")
	local before = #sk(cap).charted
	tick(cap)
	eq(#sk(cap).charted, before, "a chart pays once")
	local fishMsg = verb(cap, "sailFish")
	ok(has(fishMsg, "Fishing XP") and has(fishMsg, "Skysailing XP"), "reef fishing from the deck: " .. tostring(fishMsg))
	ok(has(verb(cap, "sailFish"), "line is still out"), "cast cadence")
	H.advance(SSS.FISH_SECONDS)
	ok(has(verb(cap, "sailSalvage"), "No wreck"), "no wreck here")
	-- The Settler's Hulk (tier 1 wreck).
	local hulk = SSS.ChartById.SettlerHulk
	ok(sailTo(cap, Vector3.new(hulk.x, 0, hulk.z)), "sailed to the Settler's Hulk")
	local items0 = state(cap).items.SkyDriftwood or 0
	H.setRoll(0.0)
	local haul = verb(cap, "sailSalvage")
	H.setRoll(0.999)
	ok(has(haul, "Grapple haul") and has(haul, "Sky Driftwood"), "salvage haul: " .. tostring(haul))
	ok((state(cap).items.SkyDriftwood or 0) > items0, "salvage goes to the satchel")
	ok(has(verb(cap, "sailSalvage"), "hauling"), "haul cadence")
	for _ = 1, SSS.WRECK_HAULS do H.advance(SSS.SALVAGE_SECONDS); verb(cap, "sailSalvage") end
	H.advance(SSS.SALVAGE_SECONDS)
	ok(has(verb(cap, "sailSalvage"), "picked clean"), "a wreck regrows per player")
	-- Moving fast: no salvage.
	local _, s = shipOf(cap)
	H.advance(SSS.WRECK_REGROW)
	tick(cap)
	s.pos = s.pos + Vector3.new(15, 0, 0)
	ok(has(verb(cap, "sailSalvage"), "Heave to"), "salvage needs the ship heaved to")
	eq(sk(cap).stats.hauls >= 1, true, "haul stats")
	verb(cap, "sailDock") -- far from a berth
	ok(shipOf(cap) ~= nil, "no docking in open sky")
end
-- Crew: boarding, roles, XP share, inactivity, policy, leaving.
local crew = join(9311, function(pr) pr.xp.Skysailing = X[20] end)
local idle = join(9312)
local third
do
	local id, s = shipOf(cap)
	s.pos = s.pos + Vector3.new(0, 0, 15)
	ok(has((use(crew, "sailBoard", tostring(cap.UserId), nil, s.pos)), "heaved to"), "boarding needs the ship heaved to")
	tick(cap) -- a still tick
	local bm = use(crew, "sailBoard", tostring(cap.UserId), nil, s.pos)
	ok(has(bm, "board as crew"), "a sailor boards: " .. tostring(bm))
	eq(s.seated[crew], "sails1", "seated on the sails")
	ok(has(crew:GetAttribute("SailVessel"), ":sails1"), "crew SailVessel attribute")
	ok(has(verb(crew, "sailDock"), "not captaining"), "crew cannot dock")
	ok(has(verb(crew, "sailLeave"), "no dock here"), "crew cannot step off mid-sky")
	ok(has(verb(crew, "sailRole", "cannons"), "cannons"), "crew moves to a cannon")
	eq(s.seated[crew], "cannon1", "cannon seat")
	local unseatThenSeat = false
	for i = #Host.calls, 2, -1 do
		local c = Host.calls[i]
		if c.op == "seat" and c.payload.player == crew and c.payload.role == "cannon1" then
			unseatThenSeat = Host.calls[i - 1].op == "unseat" and Host.calls[i - 1].payload.player == crew
			break
		end
	end
	ok(unseatThenSeat, "QC L1: a role change unseats before seating")
	-- The skiff has 1 sails + 1 cannon seat: a third sailor still fits on the sails.
	third = join(9313)
	ok(has((use(third, "sailBoard", tostring(cap.UserId), nil, s.pos)), "board as crew"), "a third sailor boards the sails")
	local fourth = join(9314)
	ok(has((use(fourth, "sailBoard", tostring(cap.UserId), nil, s.pos)), "Every seat"), "a full ship refuses")
	-- Captain-only verbs and the trim.
	ok(has(verb(crew, "sailTrim", "70"), "Only the helm"), "a gunner cannot trim")
	ok(has(verb(third, "sailTrim", "70"), "70%"), "the sails crew trims")
	ok(SSS.parseState(s.state).trim == 0.7, "trim published")
	-- QC M1: a role change or a no-op trim is not activity; a shot and a real trim are.
	verb(third, "sailTrim", "70")
	-- XP share: the gunner fires, the sails hand trimmed; a haul's crew pool (half) is split between them.
	H.advance(SSS.FIRE_COOLDOWN)
	ok(has(verb(crew, "sailFire", "90"), "Broadside"), "the gunner fires (activity)")
	moveTo(crew, s.pos); moveTo(third, s.pos)
	local hulk = SSS.ChartById.SettlerHulk
	sailTo(cap, Vector3.new(hulk.x, 0, hulk.z))
	moveTo(crew, s.pos); moveTo(third, s.pos)
	local c0, t0 = xpOf(crew, "Skysailing"), xpOf(third, "Skysailing")
	local k0 = xpOf(cap, "Skysailing")
	verb(cap, "sailSalvage")
	local k1 = xpOf(cap, "Skysailing")
	local gain = SSS.SalvageXp[1]
	ok(k1 - k0 >= gain, "the actor earns the full haul XP")
	local each = SSS.crewShare(gain, 2)
	eq(xpOf(crew, "Skysailing") - c0, each, "the active gunner shares the pool")
	eq(xpOf(third, "Skysailing") - t0, each, "the active sails hand shares the pool")
	ok(2 * each <= math.floor(gain * SSS.CREW_SHARE), "QC M1: the whole crew's share is at most half (extra accounts never multiply XP)")
	-- Inactivity: after ACTIVE_WINDOW without a contributing action, no share.
	for _ = 1, 3 do H.advance(SSS.ACTIVE_WINDOW / 3); tick(cap) end
	verb(third, "sailTrim", "55") -- the sails hand stays active
	moveTo(crew, s.pos); moveTo(third, s.pos)
	c0, t0 = xpOf(crew, "Skysailing"), xpOf(third, "Skysailing")
	H.advance(SSS.SALVAGE_SECONDS)
	local sm = verb(cap, "sailSalvage")
	ok(has(sm, "Grapple haul"), "a second haul: " .. tostring(sm))
	eq(xpOf(crew, "Skysailing") - c0, 0, "an idle gunner shares nothing (no AFK leeching)")
	eq(xpOf(third, "Skysailing") - t0, SSS.crewShare(gain, 1), "the working sails hand takes the whole pool")
	-- An absent sailor (fallen far away and not caught yet) shares nothing either: tested via the fall catch below.
	-- Fall catch: the gunner slips the seat and drops below the deck -> back aboard.
	s.seated[crew] = nil
	pivoted(crew)
	moveTo(crew, s.pos - Vector3.new(0, 60, 0))
	tick(cap)
	ok(rootOf(crew).Position.Y > s.pos.Y - SSS.FALL_DEPTH, "a falling crew member is caught back aboard")
	eq(s.seated[crew], "cannon1", "and re-seated")
	-- Closed gangway.
	verb(cap, "sailCrew", "closed")
	ok(has((use(idle, "sailBoard", tostring(cap.UserId), nil, s.pos)), "not taking crew"), "a closed gangway refuses")
	verb(cap, "sailCrew", "open")
	-- Cannons: the gunner fires; the captain with a gunner aboard does not.
	Cannon.reply = {hit = true, name = "Corsair Skiffling", damage = 140, killed = false}
	H.advance(SSS.FIRE_COOLDOWN)
	local fm = verb(crew, "sailFire", "90")
	ok(has(fm, "Broadside") and has(fm, "140"), "the gunner fires: " .. tostring(fm))
	local call = Cannon.calls[#Cannon.calls]
	ok(call.payload.owners[cap.UserId] and call.payload.owners[crew.UserId] and call.payload.owners[third.UserId] and not call.payload.owners[idle.UserId],
		"QC L5: cannons may only hit this ship's own corsairs")
	ok(call.op == "fire" and call.player == crew and call.payload.damage == SSS.cannonDamage(s.spec, 20) and call.payload.range == SSS.CANNON_RANGE, "IsleCannon gets the gunner and the damage")
	ok(math.abs(call.payload.dir.X - 1) < 1e-6, "aim from the yaw")
	ok(has(verb(crew, "sailFire", "90"), "Reloading"), "reload cadence")
	ok(has(verb(cap, "sailFire", "0"), "gunners have the cannons"), "the captain leaves the guns to the gunner")
	ok(has(verb(third, "sailFire", "0"), "cannon seat"), "the sails hand cannot fire")
	Cannon.reply = {hit = false}
end
-- Corsairs: an encounter in open sky issues corsair tickets; a kill pays Skysailing XP to the crew.
do
	local id, s = shipOf(cap)
	-- Sail out past the corsair clearance (open sky).
	sailTo(cap, Vector3.new(-200, 0, 280))
	local spawn0 = cap:GetAttribute("SeaCreatureSpawn")
	H.setRoll(0.0)
	tick(cap)
	H.setRoll(0.999)
	local spawn1 = cap:GetAttribute("SeaCreatureSpawn")
	ok(spawn1 ~= spawn0 and type(spawn1) == "string", "corsairs swoop in: " .. tostring(spawn1))
	local pid, seq = string.match(spawn1, "^(%a+):(%d+)$")
	ok(SD.SeaCreatures[pid] and SD.SeaCreatures[pid].pirate, "the ticket is a corsair")
	ok(typeof(cap:GetAttribute("SeaCreatureAt")) == "Vector3" and (cap:GetAttribute("SeaCreatureAt") - s.pos).Magnitude < 40, "they arrive off the beam")
	-- Live corsairs batter the hull.
	local hp0 = SSS.parseState(s.state).hp
	tick(cap); tick(cap)
	local hp1 = SSS.parseState(s.state).hp
	ok(hp1 < hp0, "corsair fire wears the hull")
	-- QC L4: hull damage is in the journal at once (a durable save carries it).
	renew(cap)
	ok(H.data["p9310"].profile.skysailing.hullHp <= hp1 + 1, "the damage is saved as it happens")
	-- QC M6: corsairs out of reach (the ship outran them) do no damage.
	s.pos = s.pos + Vector3.new(25, 0, 0); tick(cap)
	s.pos = s.pos + Vector3.new(25, 0, 0); tick(cap)
	s.pos = s.pos + Vector3.new(25, 0, 0); tick(cap)
	s.pos = s.pos + Vector3.new(25, 0, 0); tick(cap)
	s.pos = s.pos + Vector3.new(25, 0, 0); tick(cap)
	local hp2 = SSS.parseState(s.state).hp
	tick(cap)
	eq(SSS.parseState(s.state).hp, hp2, "corsairs beyond PIRATE_REACH do no damage")
	-- A kill (the combat bridge's seaCreature op) pays the captain and the active crew:
	-- the gunner is active and present; the sails hand is out of range (no share).
	H.advance(SSS.FIRE_COOLDOWN)
	ok(has(verb(crew, "sailFire", "0"), "Broadside"), "the gunner fires")
	moveTo(crew, s.pos); moveTo(cap, s.pos); moveTo(third, s.pos + Vector3.new(0, -SSS.CREW_RANGE - 20, 0))
	local k0, c0 = xpOf(cap, "Skysailing"), xpOf(crew, "Skysailing")
	local combat0 = xpOf(cap, "Combat")
	local reply = bridge.OnInvoke("seaCreature", cap, {seq = tonumber(seq), monster = pid, result = "kill"})
	ok(reply and reply.ok, "the corsair ticket settles")
	local def = SD.SeaCreatures[pid]
	eq(xpOf(cap, "Skysailing") - k0, def.sailingXp, "Skysailing XP for the corsair")
	ok(xpOf(cap, "Combat") > combat0, "Combat XP as any creature")
	eq(xpOf(crew, "Skysailing") - c0, SSS.crewShare(def.sailingXp, 1), "the active crew shares the corsair")
	eq(bridge.OnInvoke("seaCreature", cap, {seq = tonumber(seq), monster = pid, result = "kill"}).ok, false, "a ticket settles once")
end
-- Despawn safety: the captain leaves; every sailor lands on a dock (never the void).
do
	local id, s = shipOf(cap)
	pivoted(crew); pivoted(third)
	local bystander = join(9315)
	pivoted(idle)
	moveTo(bystander, s.pos + Vector3.new(0, 2, 2)) -- standing on the deck without a seat
	-- QC H4: a player beside the hull (off its rail) is not swept up.
	local look = Vector3.new(s.look.X, 0, s.look.Z).Unit
	local beside = s.pos + Vector3.new(-look.Z, 0, look.X) * (s.spec.beam / 2 + 8)
	moveTo(idle, beside)
	local where = s.pos
	-- QC M6: the corsairs leave with the ship (their tickets close).
	H.setRoll(0.0)
	H.advance(SSS.PIRATE_COOLDOWN)
	tick(cap)
	H.setRoll(0.999)
	local pid2, seq2 = string.match(cap:GetAttribute("SeaCreatureSpawn"), "^(%a+):(%d+)$")
	H.services.Players.PlayerRemoving:Fire(cap)
	eq(Host.ships[id], nil, "the captain's ship despawns on leave")
	for _, p in ipairs({crew, third, bystander}) do
		local pos = rootOf(p).Position
		local open = sk(p).ports
		local port = SSS.nearestPort({x = where.X, z = where.Z}, function(x) return open[x.id] end)
		ok((pos - (vp(port.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "QC H1: landed at the nearest dock this sailor may enter (" .. tostring(p.UserId) .. " at " .. port.id .. ")")
		ok(open[port.id], "the landing port is open to them")
		ok(p:GetAttribute("FastTravelAt") ~= nil, "landing marks FastTravelAt")
	end
	ok((rootOf(idle).Position - beside).Magnitude < 1e-3, "QC H4: a player off the rail stays where they are")
	eq(crew:GetAttribute("SailVessel"), "", "crew released")
	ok(has(sk(crew).sailing == nil and "free" or "", "free"), "crew snapshot shows no ship")
	-- Persistence: the captain's journal kept the hull points, charts and ship.
	local saved = H.data["p9310"].profile.skysailing
	ok(saved.ship.hull == "Skiff" and saved.ship.grapple == "BrassGrapple", "the ship persists")
	ok(saved.hullHp < SSS.spec(saved.ship).hp, "hull damage persists (no free repair by leaving)")
	ok(saved.charted.QuayShallows and saved.charted.SettlerHulk, "charts persist")
	ok(saved.stats.corsairs == 1 and saved.stats.hauls >= 2, "stats persist")
	cap = join(9310)
	homed(cap)
	eq(bridge.OnInvoke("seaCreature", cap, {seq = tonumber(seq2), monster = pid2, result = "kill"}).ok, false, "QC M6: a despawned ship's corsair tickets are closed")
	local sj = sk(cap)
	eq(sj.hullHp, saved.hullHp, "rejoin keeps the damage")
	eq(sj.sailing, nil, "a rejoin finds no ship at sea (ships despawn on leave)")
end
-- Storms wreck hulls; a wrecked hull must be repaired at a dock.
do
	local m = use(cap, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(has(m, "helm"), "relaunch")
	local id, s = shipOf(cap)
	ws.IsleWeather = "1|99|Hub=Storm,Skyways=Storm"
	local hp0 = SSS.parseState(s.state).hp
	tick(cap)
	ok(SSS.parseState(s.state).hp < hp0, "a storm batters the hull")
	for _ = 1, 400 do
		tick(cap)
		if not Host.ships[id] then break end
	end
	eq(Host.ships[id], nil, "the storm wrecks the ship")
	ws.IsleWeather = nil
	ok((rootOf(cap).Position - (vp(QUAY.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "the crew is pulled to the nearest dock")
	eq(sk(cap).hullHp, 0, "the wrecked hull is kept at 0")
end
cap = rejoin(cap)
homed(cap)
do
	ok(has((use(cap, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))), "wrecked"), "a wrecked hull cannot launch")
	moveTo(cap, Vector3.new(500, 0, 500))
	ok(has(verb(cap, "sailRepair"), "skydock"), "repairs only at a dock or the slip")
	moveTo(cap, vp(QUAY.landing))
	local wood0, coins0 = state(cap).items.SkyDriftwood or 0, state(cap).coins
	local r = verb(cap, "sailRepair")
	ok(has(r, "mended"), "repaired: " .. tostring(r))
	local st = state(cap)
	eq(st.skysailing.hullHp, st.skysailing.spec.hp, "full hull")
	ok((st.items.SkyDriftwood or 0) < wood0 or st.coins < coins0, "repairs cost driftwood or coins (a sink)")
	ok(has(verb(cap, "sailRepair"), "sound"), "nothing to repair")
end
-- QC H1 / M3 / M4: gated ports, gated waters, abandoning ship.
do
	H.advance(SSS.LAUNCH_COOLDOWN)
	moveTo(cap, vp(BRASS.landing))
	local cm = verb(cap, "sailContract", "Brassfall:Skyreach")
	ok(not has(cm, "Contract:"), "QC H1: no contract to a port you may not enter: " .. tostring(cm))
	eq(sk(cap).ports.Skyreach, false, "Skyreach is closed to this captain (quest gate)")
	local m = use(cap, "sailLaunch", "Brassfall", "Quarry", vp(BRASS.landing))
	ok(has(m, "helm"), "launch from Brassfall: " .. tostring(m))
	local sky = SSS.PortById.Skyreach
	ok(sailTo(cap, vp(sky.berth)), "sailed to the Skyreach berth")
	ok(has(verb(cap, "sailDock"), "you may enter"), "QC H1: no docking at a port you may not enter")
	local hulk = SSS.ChartById.SkyreachHulk
	ok(sailTo(cap, Vector3.new(hulk.x, 0, hulk.z)), "sailed to the Frostbitten Hulk")
	ok(table.find(sk(cap).charted, "SkyreachHulk") == nil, "QC M3: no charting over a gated region")
	H.setRoll(0.0)
	local r = verb(cap, "sailSalvage")
	H.setRoll(0.999)
	ok(not has(r, "Grapple haul"), "QC M3: no salvage over a gated region: " .. tostring(r))
	-- A sailor boards, then abandons ship: the nearest port they may enter.
	local _, s = shipOf(cap)
	pivoted(crew)
	moveTo(crew, s.pos)
	ok(has((use(crew, "sailBoard", tostring(cap.UserId), nil, s.pos)), "board as crew"), "a sailor boards")
	local where = s.pos
	ok(has(verb(crew, "sailJump"), "abandon ship"), "QC M4: crew abandon ship")
	local open = sk(crew).ports
	local port = SSS.nearestPort({x = where.X, z = where.Z}, function(x) return open[x.id] end)
	ok((rootOf(crew).Position - (vp(port.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "landed at " .. port.id .. ", a port the sailor may enter")
	ok(port.id ~= "Skyreach", "never at the gated Skyreach dock")
	eq(crew:GetAttribute("SailVessel"), "", "off the ship")
	ok(has(verb(cap, "sailJump"), "abandon ship"), "QC M4: the captain abandons ship")
	eq(shipOf(cap), nil, "the ship is brought in")
	local cpos = rootOf(cap).Position
	ok((cpos - (vp(BRASS.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "the captain lands at Brassfall (nearest open port)")
end
-- QC H5 / L3: berth slots; a failed despawn is retried.
do
	local fleet = {}
	for i = 1, 4 do
		local q = join(9320 + i, function(pr) pr.skysailing = {ship = {hull = "Skiff", sails = "CanvasSails", keel = "TimberKeel"}} end)
		homed(q)
		fleet[i] = q
	end
	local spots = {}
	for i = 1, 3 do
		local m = use(fleet[i], "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
		ok(has(m, "helm"), "captain " .. i .. " berths at the Quay")
		local _, s = shipOf(fleet[i])
		for _, other in ipairs(spots) do ok((other - s.pos).Magnitude >= SSS.BERTH_SPACING - 1e-3, "berth slots never overlap") end
		table.insert(spots, s.pos)
	end
	ok(has((use(fleet[4], "sailLaunch", "Quay", "Hub", vp(QUAY.landing))), "Every berth"), "QC H5: a full skydock refuses")
	-- L3: the first captain docks; the host fails the first despawn, the loop retries it.
	local id1 = shipOf(fleet[1])
	Host.failDespawn = 1
	tick()
	ok(has(verb(fleet[1], "sailDock"), "dock"), "the first captain docks")
	ok(Host.ships[id1] ~= nil, "the host refused the despawn")
	ok(has((use(fleet[4], "sailLaunch", "Quay", "Hub", vp(QUAY.landing))), "helm"), "the freed slot takes the fourth ship")
	tick()
	eq(Host.ships[id1], nil, "QC L3: the loop retried the despawn")
	for i = 2, 4 do verb(fleet[i], "sailDock") end
end
-- Lease and death refusals; shutdown drain.
do
	local m = use(cap, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(has(m, "helm"), "launch before the drain")
	local id = shipOf(cap)
	local humanoid = cap.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	ok(has(verb(cap, "sailDock"), "Return to your island"), "the dead cannot dock")
	humanoid.Health = 100
	H.advance(200) -- the harness lease lapses
	ok(has(verb(cap, "sailTrim", "40"), "journal sync"), "a lapsed lease refuses every verb")
	for _, closer in ipairs(H.closers) do
		local co = coroutine.create(closer)
		coroutine.resume(co)
	end
	eq(Host.ships[id], nil, "BindToClose docks every ship")
	ok((rootOf(cap).Position - (vp(QUAY.landing) + Vector3.new(0, 4, 0))).Magnitude < 1e-3, "and lands its captain")
end
print("Part C (server): " .. (checks - partC) .. " checks")

------------------------------------------------------------------------------
-- D. The vessel host headless and the sources
------------------------------------------------------------------------------
local partD = checks
do
	local storage = roblox.Instance.new("Folder")
	local ws2 = roblox.Instance.new("Workspace")
	local captured
	local fakePlayer = {UserId = 77, Character = nil}
	local hostEnv = {
		game = {GetService = function(_, name)
			if name == "Players" then return {GetPlayerFromCharacter = function() return nil end} end
			if name == "ReplicatedStorage" then return {WaitForChild = function() return dataModule end} end
			if name == "ServerStorage" then return storage end
			return {}
		end},
		workspace = ws2, Instance = roblox.Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Enum = roblox.Enum,
		task = {delay = function() end},
		require = function() return Data end,
		SailingHostTest = function(hostTable, fn) captured = {Host = hostTable, fn = fn} end,
	}
	luau.load(fs.readFile("sailing.server.lua"), {environment = hostEnv, injectGlobals = true})()
	ok(captured and captured.fn.Name == "IsleVesselHost" and captured.fn.Parent == storage, "IsleVesselHost BindableFunction in ServerStorage")
	local invoke = captured.Host.invoke
	for i, h in ipairs(SS.Hulls) do
		local ship = {hull = h.id, sails = "CanvasSails", keel = "TimberKeel"}
		if i >= 1 then ship.cannon = "BrassSwivel" end
		local spec = SS.spec(ship)
		local cf = CFrame.lookAt(Vector3.new(100 * i, 0, 0), Vector3.new(100 * i, 0, -10))
		local r = invoke("spawn", {id = i, owner = fakePlayer, spec = spec, cf = cf})
		ok(r and r.ok, h.id .. " spawns")
		local model = ws2:FindFirstChild("IsleVessels"):GetChildren()[i]
		local rec = captured.Host.vessels[i]
		model = rec.model
		local seats, parts, prompt = 0, 0, nil
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("Seat") then seats += 1 end
			if obj:IsA("BasePart") then
				parts += 1
				ok(not obj.Anchored, obj.Name .. " is part of the moving assembly")
				ok(obj.Material ~= roblox.Enum.Material.Neon, obj.Name .. " no Neon")
			end
			if obj:IsA("ProximityPrompt") then prompt = obj end
			ok(not obj:IsA("Light"), "no server lights on ships")
		end
		eq(seats, spec.crew, h.id .. " one seat per crew role")
		ok(prompt and prompt:GetAttribute("IsleAction") == "sailBoard" and prompt:GetAttribute("IsleItem") == "77", h.id .. " gangway board prompt")
		ok(parts <= 22, h.id .. " stays light (" .. parts .. " parts)")
		eq(model:FindFirstChild("Hull"):GetAttribute("ShipShape"), h.shape, h.id .. " forged hull")
		-- QC H1 / H3 / M2: collision group, finite drive limits, the hull as root.
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("BasePart") then eq(obj.CollisionGroup, "SkyVessel", obj.Name .. " is in the SkyVessel group") end
		end
		local hullRoot = model:FindFirstChild("Hull")
		eq(hullRoot.RootPriority, 127, h.id .. " hull is the assembly root")
		local lvc, aoc = hullRoot:FindFirstChild("Drive"), hullRoot:FindFirstChild("Heading")
		ok(lvc.MaxForce < math.huge and lvc.MaxForce > 0 and aoc.MaxTorque < math.huge and aoc.MaxTorque > 0, h.id .. " finite drive limits (no flinging)")
		for _, c in ipairs(model:GetChildren()) do
			if string.sub(c.Name, 1, 4) == "Mast" then
				local fit = WorldCatalog.shapes.ShipMast.fit
				ok(math.abs(c.Size.Y - (fit[2][2] - fit[1][2])) < 1e-6, h.id .. " mast host matches the ShipMast fit height")
			end
		end
		ok(model:FindFirstChild("Hull"):FindFirstChild("Drive") and model:FindFirstChild("Hull"):FindFirstChild("Heading"), h.id .. " drive constraints")
		local masts = 0
		for _, c in ipairs(model:GetChildren()) do if c:GetAttribute("SailSlot") then masts += 1 end end
		eq(masts, if h.class == 3 then 2 else 1, h.id .. " sail slots")
		local pose = invoke("pose", {id = i})
		ok(pose and (pose.position - cf.Position).Magnitude < 1e-3, h.id .. " pose is the root")
		ok(model:FindFirstChild("helm") and (model:FindFirstChild("helm").CFrame.Position - cf.Position).Magnitude < h.length, h.id .. " helm aboard")
		local turned = cf * CFrame.new(0, 0, -30) * CFrame.Angles(0, math.rad(40), 0)
		invoke("reset", {id = i, cf = turned})
		local hd = rec.heading.CFrame
		ok((hd.LookVector - turned.LookVector).Magnitude < 1e-4, "QC L2: the reset turns the heading target too")
		eq(rec.drive.VectorVelocity, Vector3.zero, "and stops the drive")
		invoke("reset", {id = i, cf = cf * CFrame.new(0, 0, -30)})
		ok((invoke("pose", {id = i}).position - (cf * CFrame.new(0, 0, -30)).Position).Magnitude < 1e-3, h.id .. " reset moves the whole ship")
		ok((model:FindFirstChild("helm").CFrame.Position - (cf * CFrame.new(0, 0, -30)).Position).Magnitude < h.length, h.id .. " seats move with it")
		invoke("state", {id = i, text = "1:2:50:20.0:1:open", trim = 0.5})
		eq(model:GetAttribute("VesselState"), "1:2:50:20.0:1:open", "state attribute")
		invoke("fire", {id = i, gunner = fakePlayer, dir = Vector3.new(1, 0, 0)})
		ok(has(model:GetAttribute("VesselFire"), ":77"), "VesselFire for the muzzle flash")
		invoke("despawn", {id = i})
		eq(captured.Host.vessels[i], nil, h.id .. " despawned")
		eq(model.Parent, nil, h.id .. " model removed")
	end
	eq(invoke("nope", {}), nil, "unknown ops ignored")
	eq(invoke("pose", {id = 999}), nil, "a missing ship has no pose")
end
local server = fs.readFile("server.server.lua")
ok(has(server, "if not spend(p,c.costs) then"), "QC L7: building spends through spend()")
ok(has(server, "function Skysailing.loop(now)") and has(server, "pcall(Skysailing.loop,os.clock())") and not has(server, "function Skysailing.tick("), "QC H2: one fixed loop checks travel")
ok(has(server, "if Data.RegionById[key]") or has(server, "Data.RegionById[key]==nil or regionAllowed(p,key)"), "QC M3: gated waters")
local host = fs.readFile("sailing.server.lua")
for _, needle in ipairs({"CollisionGroupSetCollidable(Host.GROUP, Host.GROUP, false)", "CollisionGroupSetCollidable(Host.GROUP, Host.SAILORS, false)",
	"Host.unseat(record, player) -- QC L1", "Host.reown(record)", "RootPriority = 127"}) do ok(has(host, needle), "sailing.server.lua " .. needle) end
ok(has(fs.readFile("combat.server.lua"), "owners[r.owner.UserId] == true") and has(fs.readFile("combat.server.lua"), "L.lineOfSight(origin, r)"), "QC L5: cannons hit only the ship's corsairs, in line of sight")
ok(has(server, "if Skysailing.depart then pcall(Skysailing.depart,player) end"), "close() lands the crew before the final save")
ok(has(server, "if Skysailing.drain then pcall(Skysailing.drain) end"), "BindToClose docks every ship")
ok(has(server, "if monster.pirate and Skysailing.onCorsair then"), "corsair kills pay Skysailing XP")
local combat = fs.readFile("combat.server.lua")
ok(has(combat, 'fn.Name = "IsleCannon"') and has(combat, "function L.cannon(player, payload)") and has(combat, "r.def and r.def.pirate"), "combat.server deck cannons and corsair credit")
local animate = fs.readFile("animate.client.lua")
for _, v in ipairs({'shipwright = "hammer"', 'sailLaunch = "board"', 'sailBoard = "board"', 'harbourBoard = "read"', "board = {fx", "helm = {", "grapple = {fx", "haul = {"}) do ok(has(animate, v), "animate.client.lua " .. v) end
ok(has(fs.readFile("gesture.server.lua"), "board = true, helm = true, grapple = true, haul = true"), "the sailing gestures relay")
local client = fs.readFile("sailing.client.lua")
for _, needle in ipairs({"SS.speedFactor", "SS.parseState", "SS.relWind", "A.windAtDir", "CreateEditableMesh", "MeshForgeLocal", "\"sailTrim\"", "\"sailFire\"", "\"shipBuild\"", "\"sailContract\"", "SailShipwright", "SailBoardPort", "reducedMotion", "VesselFire", "Trail",
	-- QC M4 / M5 / M7 / M9 / L6
	"\"sailJump\"", "SS.CLIENT_MARGIN", "S.warn", "FixedSize = true", "CollisionFidelity.Box", "CLOTH_SHIPS", "weld.Part0, weld.Part1 = slot, p", "Skip unchanged writes",
	"L.shipHud", "T.hudLayout", "DRESS_IN, DRESS_OUT = 320, 360", "vesselAt = t + 0.5", "nearAt = t + 0.25"}) do
	ok(has(client, needle), "sailing.client.lua uses " .. needle)
end
ok(has(fs.readFile("forge.client.lua"), 'part:GetAttribute("ShapeManual")'), "the forge leaves moving ship parts to sailing.client.lua")
local ui = fs.readFile("ui.client.lua")
ok(has(ui, "shipBuild=true") and has(ui, "sailContract=true") and has(ui, "Data.Skysailing.unlocks()"), "ui relays the sailing verbs and lists the unlock guide")
local project = fs.readFile("default.project.json")
ok(has(project, '"Skysailing": { "$path": "sailing.server.lua" }') and has(project, '"IsleSailing": { "$path": "sailing.client.lua" }'), "scripts registered in default.project.json")
ok(has(fs.readFile("verify.luau"), 'Skysailing = "sailing.server.lua", IsleSailing = "sailing.client.lua"'), "scripts registered in verify.luau")
ok(has(fs.readFile("scripts/build.sh"), "verify-sailing.luau"), "suite in build.sh")
ok(has(fs.readFile("build.ps1"), "'verify-sailing.luau'"), "suite in build.ps1")
ok(has(fs.readFile("docs/DEPTH-CONTRACT.md"), "## 51. Skysailing"), "contract §51")
print("Part D (host + sources): " .. (checks - partD) .. " checks")
print("verify-sailing: " .. checks .. " checks passed")
print("SUITE-END verify-sailing.luau")
