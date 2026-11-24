-- Raids (Raid team): The Undertide Vaults, a 2-8 player party raid.
-- docs/DEPTH-CONTRACT.md §38.
-- Part A checks shared/GameData.lua (Data.Raids): encounters and their
--   mechanics, the room pool and seeded sequences, puzzles, resource rooms,
--   points, credit, the purple roll, loot, uniques vs their rivals, the pet,
--   the Collection Log tab, the goal board and announcement hooks, migration
--   and records, original names.
-- Part B drives combat.server.lua's Raids section through the harness hook:
--   party / Challenge scaling, members only, stances and the prayer check,
--   raid adds and sigils through the Lairs machinery, per-UserId damage, the
--   kill (every damaging member paid XP), the raid cap and the lair cap.
-- Part C runs server.server.lua: verb gates (Combat, region, busy, portal
--   prompt), bridge "raid" (paid once per run id, clamps, unique and kit
--   through collect(), XP skills only, end records), the Raid Log snapshot,
--   titles, the ward and the death purse exemption, migration, persistence.
-- Part D runs raids.server.lua with real instances, wired to Part C's bridge
--   and a combat double built from the real combat logic: lobbies (portal
--   range, ready, Challenge Mode, capacity), a full run through every room
--   kind, points, the purple roll and its recipient, rewards, exit and
--   teardown (parts, connections, creatures), FastTravelAt on every move,
--   deaths (points, respawn back in), disconnect and rejoin within 90 s,
--   idle and away removal, abandoned raids, the raid cap, build failures.
-- Part E builds world.server.lua: the portal, its prompt, anchor and the part
--   budget. Part F renders raid.client.lua (board, HUD, Raid Log).
-- Part G prints and bounds the balance model.
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
local RD = Data.Raids
local LR = Data.Lairs
local X = Data.XP_TABLE
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function within(x, lo, hi, case) assert(x >= lo and x <= hi, case .. " (" .. string.format("%.3f", x) .. " not in " .. lo .. ".." .. hi .. ")"); checks += 1 end
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

------------------------------------------------------------------------------
-- Part A: data and rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(RD) == "table" and RD.ID == "UndertideVaults", "Data.Raids")
eq(RD.MIN_PARTY, 2, "two raiders minimum")
eq(RD.MAX_PARTY, 8, "eight raiders maximum")
ok(RD.MAX_RAIDS >= 1 and RD.MAX_RAIDS <= 4, "concurrent raids capped")
eq(RD.REJOIN_SECONDS, 90, "rejoin within 90 s (minigames / dungeons)")
-- Room pool sizes.
ok(#RD.CombatOrder >= 6, "at least six combat rooms")
ok(#RD.PuzzleOrder >= 3, "at least three puzzle rooms")
ok(#RD.ResourceOrder >= 2, "at least two resource rooms")
do
	local mechanics = {}
	local Combat
	load("combat.server.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, __CombatTestHarness = function(exports) Combat = exports end})
	for _, id in ipairs(RD.CombatOrder) do
		local def = RD.Encounters[id]
		ok(def and def.id == id and def.lair == true and def.raid == RD.ID, id .. " encounter defined")
		ok(type(def.mechanic) == "string" and not mechanics[def.mechanic], id .. " has its own mechanic (" .. tostring(def.mechanic) .. ")")
		mechanics[def.mechanic] = true
		ok(#def.phases >= 2 and #def.mechanics >= 2 and #def.blurb > 20 and def.roomName, id .. " phases, mechanics text and room")
		for _, phase in ipairs(def.phases) do
			for _, a in ipairs(phase.rotation) do ok(def.attacks[a] ~= nil, id .. " rotation " .. a .. " defined") end
		end
		for _, a in pairs(def.attacks) do
			if a.kind == "adds" or a.kind == "sigils" then ok(RD.Adds[a.add] ~= nil and LR.Adds[a.add] ~= nil, id .. " add " .. a.add .. " resolves through LR.Adds") end
		end
		ok(Data.Monsters[id] == def, id .. " reachable by id (damage XP)")
		ok(type(Combat.blueprint(def.body, def.color, true)) == "table", id .. " body " .. def.body .. " builds")
	end
	-- The distinct mechanics cover the kinds the Lairs machinery offers.
	local kinds = {}
	for _, id in ipairs(RD.CombatOrder) do
		for _, a in pairs(RD.Encounters[id].attacks) do kinds[a.kind] = true end
		if #RD.Encounters[id].stances > 1 then kinds.stances = true end
	end
	for _, k in ipairs({"disc", "ring", "safe", "tiles", "adds", "sigils", "stances"}) do ok(kinds[k], "combat pool uses " .. k) end
	local boss = RD.Encounters[RD.BOSS]
	ok(boss and boss.boss == true and #boss.phases == 3, "final boss with three phases")
	eq(#boss.stances, 3, "the Regent cycles all three styles (prayer switching)")
	local bossKinds = {}
	for _, a in pairs(boss.attacks) do bossKinds[a.kind] = true end
	ok(bossKinds.sigils and bossKinds.adds and bossKinds.tiles and bossKinds.safe, "the Regent: anchors, thralls, lattice and safe zone")
	ok(boss.phases[2].weakness ~= boss.phases[1].weakness and boss.phases[3].weakness ~= boss.phases[2].weakness, "the weakness turns by phase")
	ok(type(Combat.blueprint(boss.body, boss.color, true)) == "table", "the Regent's body builds")
	for id, a in pairs(RD.Adds) do
		ok(a.lair and a.lairAdd and a.raid == RD.ID and type(Combat.blueprint(a.body, a.color, false)) == "table", id .. " add defined and builds")
		ok(Data.Monsters[id] == a, id .. " reachable by id")
	end
	-- pairs() over the lair and monster tables never sees raid creatures.
	for id in pairs(LR.Adds) do ok(RD.Adds[id] == nil, "LR.Adds iterates lair adds only (" .. id .. ")") end
	for id in pairs(Data.Monsters) do ok(RD.Encounters[id] == nil and RD.Adds[id] == nil, "Data.Monsters iterates markers only (" .. id .. ")") end
end
-- Scaling.
do
	local def = RD.Encounters.Gloomfang
	eq(RD.partyHp(def, 1), def.hp, "solo-equivalent health")
	eq(RD.partyHp(def, 4), math.floor(def.hp * (1 + RD.PARTY_HP * 3)), "health scales with the party")
	eq(RD.partyHp(def, 99), RD.partyHp(def, 8), "party clamps to eight")
	ok(RD.partyHp(def, 4, true) > RD.partyHp(def, 4), "Challenge Mode is tougher")
	ok(RD.partyDamage(def, 8) > RD.partyDamage(def, 2) and RD.partyDamage(def, 2) > def.damage, "damage scales with the party")
	ok(RD.partyDamage(def, 4, true) > RD.partyDamage(def, 4), "Challenge Mode hits harder")
	local copy = RD.scaledDef("Gloomfang", 4, true)
	eq(copy.damage, RD.partyDamage(def, 4, true), "per-fight def carries the scaled damage")
	eq(def.damage, RD.Encounters.Gloomfang.damage, "the base def is untouched")
	eq(RD.scaledDef("Nope", 2), nil, "unknown encounter")
end
-- Sequences: two distinct combat rooms, one puzzle, one resource room, then the Regent; runs vary.
do
	local seenCombat, seenPuzzle, seenResource, orders = {}, {}, {}, {}
	for seed = 1, 400 do
		local seq = RD.sequence(seed * 7919)
		eq(#seq, 5, "five rooms")
		eq(seq[5].kind, "boss", "the Regent is last")
		local combats, puzzles, resources = {}, 0, 0
		local sig = {}
		for i = 1, 4 do
			local r = seq[i]
			table.insert(sig, r.kind:sub(1, 1))
			if r.kind == "combat" then table.insert(combats, r.id); seenCombat[r.id] = true; ok(RD.Encounters[r.id] ~= nil, "combat room known")
			elseif r.kind == "puzzle" then puzzles += 1; seenPuzzle[r.id] = true
			elseif r.kind == "resource" then resources += 1; seenResource[r.id] = true end
		end
		ok(#combats == 2 and combats[1] ~= combats[2] and puzzles == 1 and resources == 1, "room mix")
		orders[table.concat(sig)] = true
		local again = RD.sequence(seed * 7919)
		for i = 1, 5 do ok(again[i].id == seq[i].id and again[i].kind == seq[i].kind, "sequence is deterministic per seed") end
	end
	for _, id in ipairs(RD.CombatOrder) do ok(seenCombat[id], id .. " drawn") end
	for _, id in ipairs(RD.PuzzleOrder) do ok(seenPuzzle[id], id .. " drawn") end
	for _, id in ipairs(RD.ResourceOrder) do ok(seenResource[id], id .. " drawn") end
	local n = 0
	for _ in pairs(orders) do n += 1 end
	ok(n >= 8, "room orders vary (" .. n .. " orders)")
end
-- Puzzles.
for seed = 1, 60 do
	local seq = RD.glyphSequence(seed, 6)
	eq(#seq, 6, "glyph sequence length")
	for i = 1, 6 do
		ok(seq[i] >= 1 and seq[i] <= #RD.GLYPHS, "glyph index valid")
		if i > 1 then ok(seq[i] ~= seq[i - 1], "no glyph twice in a row") end
	end
	local plates = RD.sealPattern(seed, 2, 4)
	eq(#plates, 4, "seal round lights k plates")
	for i = 2, #plates do ok(plates[i] > plates[i - 1], "distinct sorted plates") end
	local valves = RD.valveStart(seed)
	ok(RD.valvesOpen(valves) < RD.VALVES, "valves never start solved")
	local solution = RD.valveSolution(valves)
	ok(solution ~= nil and #solution >= 1 and #solution <= RD.VALVES, "valves always solvable")
	for _, i in ipairs(solution) do RD.valveToggle(valves, i) end
	eq(RD.valvesOpen(valves), RD.VALVES, "the solution opens every valve")
end
eq(RD.glyphLength(2), 4, "glyphs for a small party")
eq(RD.glyphLength(6, true), 6, "longer for a big Challenge party")
eq(RD.sealNeed(2), 2, "two raiders, two seals")
eq(RD.sealNeed(8), 4, "at most four seals at once")
-- Resource rooms make supplies that matter later.
for _, id in ipairs(RD.ResourceOrder) do
	local res = RD.Resources[id]
	ok(#res.nodes == 2 and #res.stations == 2 and res.supplies.food and res.supplies.potion, id .. " nodes, stations and supplies")
	local makes = {}
	for _, node in ipairs(res.nodes) do ok(Data.Skills[node.skill] ~= nil and node.xp > 0, id .. " node skill " .. node.skill); makes[node.makes] = true end
	for _, st in ipairs(res.stations) do ok(Data.Skills[st.skill] ~= nil and makes[st.makes], id .. " station " .. st.id .. " has a raw source") end
end
ok(RD.Supplies.food.heal > 0 and RD.Supplies.potion.ward > 0 and RD.WARD_MULT < 1, "food heals, draughts ward")
ok(RD.quota(8) > RD.quota(2), "the quota grows with the party")
-- Points.
eq(RD.damagePoints("combat", 0.5, 4), RD.Points.combat * 2, "half of a combat pool")
eq(RD.damagePoints("boss", 1, 2), RD.Points.boss * 2, "the whole Regent pool")
eq(RD.damagePoints("boss", 1, 2, true), math.floor(RD.Points.boss * 2 * RD.Points.challenge), "Challenge points")
eq(RD.damagePoints("combat", 0 / 0, 4), 0, "NaN share pays nothing")
eq(RD.deathLoss(10000), 2500, "a death costs a quarter")
within(RD.uniqueChance(RD.POINTS_PER_PERCENT * 10), 0.0999, 0.1001, "10% at ten times the points per percent")
eq(RD.uniqueChance(1e12), RD.UNIQUE_CAP, "purple chance caps")
eq(RD.uniqueChance(-5), 0, "no negative chance")
ok(RD.maxPersonal(8, true) > RD.maxPersonal(2), "personal points bound")
-- Credit (contribution floor, recent action, presence, removal).
do
	local base = {points = 5000, team = 20000, party = 4, present = true, lastAction = 100, now = 150}
	local function with(k, v) local c = table.clone(base); c[k] = v; return c end
	eq(RD.credit(base), true, "credited")
	eq(select(2, RD.credit(with("points", 1000))), "share", "below 25% of an equal share")
	eq(select(2, RD.credit(with("now", 100 + RD.RECENT_SECONDS + 1))), "idle", "no recent action")
	eq(select(2, RD.credit(with("present", false))), "away", "not in the vault")
	eq(select(2, RD.credit(with("removed", true))), "removed", "removed members")
	eq(select(2, RD.credit(with("points", 0))), "points", "no points")
	eq(RD.credit({points = 10, team = 10, party = 1, present = true, lastAction = 1, now = 2}), true, "a lone survivor is not held to a share")
	-- QC M3: the floor reads contribution (damage, puzzle, resource points; no flat room clears).
	eq(select(2, RD.credit({points = 2680, contribution = 180, teamContribution = 40000, party = 3, present = true, lastAction = 100, now = 150})), "share",
		"room clears plus one hit do not pass the floor")
	eq(RD.credit({points = 9000, contribution = 6500, teamContribution = 40000, party = 3, present = true, lastAction = 100, now = 150}), true, "a real contributor does")
end
-- Purple recipient by personal points; the unique table.
do
	local entries = {{uid = 1, points = 1000}, {uid = 2, points = 3000}}
	eq(RD.pickRecipient(entries, 0), 1, "low roll -> first")
	eq(RD.pickRecipient(entries, 0.2), 1, "inside the first share")
	eq(RD.pickRecipient(entries, 0.3), 2, "past the first share")
	eq(RD.pickRecipient(entries, 0.9999), 2, "top roll")
	eq(RD.pickRecipient({{uid = 3, points = 0}}, 0.5), nil, "nobody with points")
	local total, seen = 0, {}
	for _, id in ipairs(RD.UniqueOrder) do total += RD.UniqueWeights[id] end
	eq(total, 100, "unique weights sum to 100")
	for i = 0, 999 do seen[RD.pickUnique(i / 1000)] = (seen[RD.pickUnique(i / 1000)] or 0) + 1 end
	for _, id in ipairs(RD.UniqueOrder) do within(seen[id] / 1000, RD.UniqueWeights[id] / 100 - 0.002, RD.UniqueWeights[id] / 100 + 0.002, id .. " weight") end
	within(#RD.UniqueOrder, 6, 8, "six to eight uniques")
end
-- Uniques: rivals of a strictly higher requirement, every stat <= 85%, still below at 5★.
do
	local G = Data.Gear
	local function req(def)
		local best = 0
		for _, v in pairs(def.requires or {}) do best = math.max(best, v) end
		return best
	end
	local kinds = {}
	for _, id in ipairs(RD.UniqueOrder) do
		local def = Data.Items[id]
		ok(def and def.raidUnique == RD.ID and def.logUnique == "Raids", id .. " flagged raid unique")
		kinds[def.slot or def.kind] = true
	end
	ok(kinds.weapon and kinds.helmet and kinds.chest and kinds.accessory and kinds.pet, "weapons, armour, an accessory and a pet")
	for item, rivalId in pairs(RD.Rivals) do
		local def, rival = Data.Items[item], Data.Items[rivalId]
		ok(def and rival and not rival.raidUnique, item .. " has rival " .. rivalId)
		eq(def.kind, rival.kind, item .. " rival kind")
		if def.kind ~= "accessory" then
			ok(req(rival) > req(def), rivalId .. " needs more than " .. item .. " (" .. req(rival) .. " > " .. req(def) .. ")")
			for skill in pairs(def.requires) do ok(rival.requires[skill] ~= nil, item .. " requirement skill matches the rival") end
			eq(def.slot, rival.slot, item .. " rival slot")
		end
		if def.kind == "weapon" then eq(G.category(def), G.category(rival), item .. " rival style") end
		if def.ranged then
			ok(def.ranged.power <= rival.ranged.power * RD.UNIQUE_MAX + 1e-9 and def.ranged.maxAmmoTier <= rival.ranged.maxAmmoTier and def.ranged.speed >= rival.ranged.speed, item .. " bow <= 85% of " .. rivalId)
		end
		if def.magic then ok(def.magic.power <= rival.magic.power * RD.UNIQUE_MAX + 1e-9 and #def.magic.elements <= #rival.magic.elements, item .. " staff <= 85% of " .. rivalId) end
		for stat, v in pairs(def.stats) do
			ok(rival.stats[stat] ~= nil, item .. " " .. stat .. " is a stat the rival has")
			ok(v <= rival.stats[stat] * RD.UNIQUE_MAX + 1e-9, item .. " " .. stat .. " " .. v .. " <= 85% of " .. rivalId .. " " .. rival.stats[stat])
		end
		if G.category(def) and G.canStar(G.category(def)) then
			local mine = G.breakdown({stars = {[item] = 5}}, item).total
			local theirs = G.breakdown({stars = {[rivalId] = 5}}, rivalId).total
			for stat, v in pairs(def.stats) do ok(v + (mine[stat] or 0) < rival.stats[stat] + (theirs[stat] or 0), item .. " 5★ " .. stat .. " stays below " .. rivalId .. " 5★") end
		end
	end
	for _, id in ipairs(RD.UniqueOrder) do
		if Data.Items[id].kind ~= "pet" then ok(RD.Rivals[id] ~= nil, id .. " has a rival") end
	end
	-- Still a real reward: above the open crafts of their own tier.
	ok(Data.Items.RegentsTidecleaver.stats.damage > Data.Items.PrismaticSword.stats.damage, "Tidecleaver above the Combat-40 craft")
	local pet = Data.Items.TidewhelpPet
	local species = Data.PetById[pet.pet]
	ok(species and Data.PetDepth.Abilities.Tidewhelp and #Data.PetDepth.Abilities.Tidewhelp == 3 and Data.PetDepth.Looks.Tidewhelp, "raid pet species, abilities and look")
	ok(type(Data.PetDepth.bodyPlan(species.id, species.rarity)) == "table", "raid pet body plan")
	local kit = Data.Items.GildedTideKit
	ok(kit.cosmetic == true and kit.stats == nil and kit.value <= 1 and kit.logUnique == "Raids", "Challenge kit is cosmetic (no stats, no coin value)")
end
-- Lead decision (QC): each raid weapon carries an original special (RD.tideMult) that gives it a
-- niche without lifting it on general content. Modelled like Hollow Sunder (verify-bosses): expected
-- damage per second (crits averaged; Celestial-tier arrows; a Magic-70 Cascade) for three gear
-- profiles. General content: below its rival. Niche: above the open Combat-60 craft (Greatblade /
-- Eclipse Longbow) or, for the Scepter whose rival is that craft, above the lair staff, and still
-- below the rival.
do
	local tc, wb, sc = Data.Items.RegentsTidecleaver, Data.Items.UndertowWarbow, Data.Items.DrownlightScepter
	ok(tc.special and tc.special.id == "Riptide" and tc.special.adds > 0 and has(tc.description, "Riptide"), "the Tidecleaver carries Riptide")
	ok(wb.special and wb.special.id == "Undertow" and wb.special.raid > 0 and has(wb.description, "Undertow"), "the Warbow carries Undertow")
	ok(sc.special and sc.special.id == "Drownlight" and sc.special.warded > 0 and has(sc.description, "Drownlight"), "the Scepter carries Drownlight")
	eq(RD.tideMult("RegentsTidecleaver", {}), 1, "no Riptide on ordinary monsters")
	eq(RD.tideMult("RegentsTidecleaver", {boss = true, raid = true, warded = true}), 1, "Riptide never on the boss itself")
	eq(RD.tideMult("RegentsTidecleaver", {add = true}), 1 + tc.special.adds, "Riptide on a boss's adds")
	eq(RD.tideMult("UndertowWarbow", {boss = true, raid = true}), 1 + wb.special.raid, "Undertow on raid encounters")
	eq(RD.tideMult("UndertowWarbow", {boss = true, warded = true}), 1, "no Undertow outside the vaults")
	eq(RD.tideMult("UndertowWarbow", {add = true}), 1, "no Undertow on adds")
	eq(RD.tideMult("DrownlightScepter", {boss = true, warded = true}), 1 + sc.special.warded, "Drownlight on a shielded boss")
	eq(RD.tideMult("DrownlightScepter", {boss = true, raid = true}), 1, "no Drownlight on an unshielded boss")
	eq(RD.tideMult("DrownlightScepter", {warded = true}), 1, "no Drownlight on ordinary monsters")
	for _, id in ipairs({"Crownbreaker", "Duskpiercer", "RiftcrownStaff", "HollowcrownEdge", "SovereignGreatblade"}) do
		eq(RD.tideMult(id, {add = true, boss = true, raid = true, warded = true}), 1, id .. " has no raid special")
	end
	eq(LR.sunderMult("RegentsTidecleaver", {boss = true, warded = true}), 1, "the raid specials never trigger Hollow Sunder")
	local arrow
	for _, d in pairs(Data.Items) do if type(d.ammo) == "table" and d.ammo.tier == 7 then arrow = d end end
	local cascade = Data.Spells.TideCascade
	local function melee(id, g)
		local st = Data.Items[id].stats
		local cc = math.min(100, st.critChance + g.critChance)
		return (5 + st.damage) * (1 + (st.strength + g.strength) / 100) * (1 + cc / 100 * (st.critDamage + g.critDamage) / 100)
	end
	local function ranged(id, g)
		local b = Data.Items[id]
		local raw = (5 + b.ranged.power + arrow.ammo.power) * (1 + ((b.stats.rangedStrength or 0) + g.rangedStrength) / 100) * (1 + 4 * 69 / 100)
		return raw * (1 + math.min(100, g.critChance) / 100 * ((b.stats.critDamage or 0) + g.critDamage) / 100) / b.ranged.speed
	end
	local function magic(id, g)
		local w = Data.Items[id]
		return P.spellDamage({intelligence = w.stats.intelligence + g.intelligence, abilityDamage = w.stats.abilityDamage + g.abilityDamage}, cascade, w, 70) / w.magic.speed
	end
	for _, g in ipairs({
		{name = "weapon only", strength = 0, critChance = 0, critDamage = 0, rangedStrength = 0, intelligence = 0, abilityDamage = 0},
		{name = "Combat-65 kit", strength = 100, critChance = 20, critDamage = 100, rangedStrength = 40, intelligence = 150, abilityDamage = 10},
		{name = "endgame kit", strength = 220, critChance = 45, critDamage = 220, rangedStrength = 80, intelligence = 350, abilityDamage = 25},
	}) do
		local t, cb, sg = melee("RegentsTidecleaver", g), melee("Crownbreaker", g), melee("SovereignGreatblade", g)
		local adds = t * RD.tideMult("RegentsTidecleaver", {add = true})
		local u, dp, ec = ranged("UndertowWarbow", g), ranged("Duskpiercer", g), ranged("EclipseLongbow", g)
		local vault = u * RD.tideMult("UndertowWarbow", {boss = true, raid = true})
		local d, rs, ps = magic("DrownlightScepter", g), magic("RiftcrownStaff", g), magic("PyreheartStaff", g)
		local shielded = d * RD.tideMult("DrownlightScepter", {boss = true, warded = true})
		print(string.format("  Raid specials (%s): Riptide %.0f (general %.0f; Greatblade %.0f, Crownbreaker %.0f) · Undertow %.0f (general %.0f; Eclipse %.0f, Duskpiercer %.0f) · Drownlight %.0f (general %.0f; Pyreheart %.0f, Riftcrown %.0f)",
			g.name, adds, t, sg, cb, vault, u, ec, dp, shielded, d, ps, rs))
		ok(t < sg and t < cb, "general content: the Tidecleaver stays below its rivals (" .. g.name .. ")")
		ok(adds > sg and adds < cb, "adds: Riptide beats the Greatblade, stays below the Crownbreaker (" .. g.name .. ")")
		ok(u < ec and u < dp, "general content: the Warbow stays below the Eclipse Longbow and Duskpiercer (" .. g.name .. ")")
		ok(vault > ec and vault < dp, "the vaults: Undertow beats the Eclipse Longbow, stays below Duskpiercer (" .. g.name .. ")")
		ok(d < ps and d < rs, "general content: the Scepter stays below the Pyreheart and Riftcrown staves (" .. g.name .. ")")
		ok(shielded > ps and shielded < rs, "shielded bosses: Drownlight beats the Pyreheart, stays below the Riftcrown (" .. g.name .. ")")
	end
end
-- Regular loot: deterministic rolls from points; never a unique.
do
	eq(RD.rolls(0), 0, "no points, no rolls")
	eq(RD.rolls(RD.LOOT_POINTS * 3 + 5), 3, "one roll per loot points")
	eq(RD.rolls(1e9), RD.MAX_ROLLS, "rolls cap")
	local i = 0
	local seq = {0.1, 0.5, 0.95, 0.0, 0.99, 0.3}
	local drops = RD.regularLoot(RD.LOOT_POINTS * 3, function() i += 1 return seq[(i - 1) % #seq + 1] end)
	local n = 0
	for id, k in pairs(drops) do ok(Data.Items[id] ~= nil and not RD.isUnique(id) and k >= 1, "loot " .. id); n += k end
	ok(n >= 3, "three rolls dropped items")
	for _, row in ipairs(RD.Loot) do ok(Data.Items[row.item] ~= nil and row.weight > 0 and row.min >= 1 and row.max >= row.min, "loot row " .. row.item) end
end
-- Collection Log: the Raids tab after Lairs holds the gear, accessory and kit; the pet files under Pets.
do
	local CL = Data.CommissionsLogs
	ok(CL.LogTabs.Raids ~= nil and CL.LogTabs.Raids.coins > 0 and #CL.LogTabs.Raids.title > 3, "Raids tab and reward")
	eq(table.find(CL.LogTabOrder, "Raids"), table.find(CL.LogTabOrder, "Lairs") + 1, "Raids tab after Lairs")
	local L = CL.log(true)
	local raidTab = L.Tabs.Raids or {}
	local inTab = {}
	for _, e in ipairs(raidTab) do inTab[type(e) == "table" and e.id or e] = true end
	for _, id in ipairs({"RegentsTidecleaver", "UndertowWarbow", "DrownlightScepter", "TidewardenVisage", "TidewardenCuirass", "RegentsPearl", "GildedTideKit"}) do
		ok(inTab[id], id .. " in the Raids tab")
	end
end
-- Goal board and announcements.
do
	local GL = Data.Systems.Goals
	local g = GL.parse("kills:" .. RD.ID .. ":25")
	ok(g and g.k == "kills" and g.a == RD.ID and g.n == 25, "raid clear goals parse")
	ok(GL.parse("kills:" .. RD.ID .. ":0") == nil and GL.parse("kills:" .. RD.ID .. ":0010") == nil, "bad targets refused")
	ok(GL.parse("kills:Bramblemaw:3") ~= nil, "lair goals still parse")
	local have, need = GL.measure({raids = {kc = 7}}, g)
	ok(have == 7 and need == 25, "raid goals measure p.raids.kc")
	ok(has(GL.label(g), "clears"), "raid goal label: " .. GL.label(g))
	eq(GL.bosses()[1], RD.ID, "the raid heads the goal board's boss list")
	ok(GL.measure({lairs = {kc = {Bramblemaw = 2}}}, {k = "kills", a = "Bramblemaw", n = 5}) == 2, "lair goals still measure")
	local F = Data.Features
	local t = F.announceText({kind = "raidUnique", item = "RegentsPearl"})
	ok(t.head == "RAID UNIQUE" and has(t.body, "Regent's Pearl"), "purple toast")
	ok(F.announceText({kind = "raidTitle", title = "Vaultdiver"}).head == "RAID TITLE", "title toast")
	ok(F.announceText({kind = "goal", title = "x"}).head == "GOAL COMPLETE", "goal toast still works")
	ok(F.announceText({kind = "skill", skill = "Combat", level = 2}).head == "SKILL LEVEL UP", "older toasts still work")
end
-- Migration and records.
do
	local s = RD.migrate(nil)
	ok(s.kc == 0 and next(s.pb) == nil and next(s.got) == nil and s.title == "", "fresh Raid Log")
	local r1 = RD.record(s, {id = "R:1", seconds = 700, party = 4, points = 15000, team = 60000, unique = "RegentsPearl", now = 10})
	ok(r1.kc == 1 and r1.pb == true and table.find(r1.newTitles, "Vaultdiver"), "first clear: KC, PB, title")
	eq(s.pb["4"], 700, "PB per party size")
	eq(s.got.RegentsPearl, 1, "unique counted")
	local r2 = RD.record(s, {id = "R:2", seconds = 800, party = 4, points = 9000, team = 30000, now = 11})
	ok(r2.pb == false and s.pb["4"] == 700 and s.best.points == 15000 and s.best.team == 60000, "slower clears keep the PB and records")
	local r3 = RD.record(s, {id = "R:3", seconds = 600, party = 3, points = 20000, team = 70000, challenge = true, underPar = true, kit = true, now = 12})
	ok(s.cm == 1 and s.pbCm["3"] == 600 and s.got.GildedTideKit == 1 and table.find(r3.newTitles, "RegentsBane") and table.find(r3.newTitles, "UndertideChampion"), "Challenge clear under par")
	ok(RD.seen(s, "R:2") and not RD.seen(s, "R:9"), "run ids remembered")
	eq(s.log[1].u, nil, "log newest first")
	eq(s.log[3].u, "RegentsPearl", "log keeps the unique")
	for i = 1, RD.RUN_MEMORY + 5 do RD.record(s, {id = "M" .. i, seconds = 900, party = 2, points = 1, team = 2, now = 20 + i}) end
	eq(#s.runs, RD.RUN_MEMORY, "run memory bounded")
	eq(#s.log, RD.KEEP_LOG, "log bounded")
	s.title = "RegentsBane"
	local back = RD.migrate(s)
	ok(back.kc == s.kc and back.title == "RegentsBane" and back.got.RegentsPearl == 1 and #back.runs == RD.RUN_MEMORY, "round trip")
	local bad = RD.migrate({kc = -4, pb = {["1"] = 50, ["9"] = 3, ["x"] = 2, ["3"] = 0 / 0}, got = {Nope = 3, RegentsPearl = "x"}, titles = {Fake = true, Vaultdiver = 1},
		title = "Fake", log = {"junk", {s = 5, n = 99, u = "Nope"}}, runs = {"ok", 5, string.rep("x", 99)}})
	ok(bad.kc == 0 and next(bad.pb) == nil and next(bad.got) == nil and next(bad.titles) == nil and bad.title == "" and #bad.log == 1 and bad.log[1].n == RD.MAX_PARTY
		and bad.log[1].u == nil and #bad.runs == 1, "corrupt saves sanitised")
end
-- Original names only.
do
	local banned = {"xeric", "olm", "olmlet", "tekton", "vasa", "vespula", "muttadile", "vanguard", "twisted", "kodai", "ancestral", "dinh", "elder maul", "chambers", "great olm", "tightrope", "scavenger", "theatre", "verzik", "tombs"}
	local names = {RD.NAME}
	for _, d in pairs(RD.Encounters) do table.insert(names, d.name); table.insert(names, d.roomName) end
	for _, d in pairs(RD.Adds) do table.insert(names, d.name) end
	for _, d in pairs(RD.Puzzles) do table.insert(names, d.name) end
	for _, d in pairs(RD.Resources) do table.insert(names, d.name); table.insert(names, d.supplies.food); table.insert(names, d.supplies.potion) end
	for _, id in ipairs(RD.UniqueOrder) do table.insert(names, Data.Items[id].name) end
	for _, t in ipairs(RD.Titles) do table.insert(names, t.text) end
	for _, name in ipairs(names) do
		local low = string.lower(name)
		for _, word in ipairs(banned) do ok(not string.find(low, "%f[%a]" .. word .. "%f[%A]"), name .. " avoids '" .. word .. "'") end
	end
end
print("PASS: " .. (checks - partA) .. " raid data assertions.")

------------------------------------------------------------------------------
-- Part B: combat.server.lua Raids section (pure logic through the harness).
------------------------------------------------------------------------------
local partB = checks
local Combat
load("combat.server.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, __CombatTestHarness = function(exports) Combat = exports end})
local function world()
	local w = {clock = 100, rolls = {}, calls = {}, positions = {}, alive = {}, stats = {}, list = {}}
	function w.rng() if #w.rolls > 0 then return table.remove(w.rolls, 1) end return 0.5 end
	function w.player(id, pos, opts)
		opts = opts or {}
		local p = {Name = "P" .. id, UserId = id}
		w.positions[p] = pos
		w.alive[p] = true
		w.stats[p] = {stats = opts.stats or {damage = 400, strength = 100, critChance = 0, critDamage = 50, attackSpeed = 0},
			combatLevel = 75, ironman = opts.ironman == true, prayer = opts.prayer, loadout = {style = "melee", levels = {}, supplies = {}}}
		table.insert(w.list, p)
		return p
	end
	function w.calls_of(op, player)
		local out = {}
		for _, c in ipairs(w.calls) do if c.op == op and (player == nil or c.player == player) then table.insert(out, c) end end
		return out
	end
	w.logic = Combat.createLogic({
		Data = Data, Progression = P,
		now = function() return w.clock end, time = function() return 5000 end, rng = w.rng,
		players = function() return w.list end,
		alive = function(p) return w.alive[p] == true end,
		position = function(p) return w.positions[p] end,
		heal = function() end,
		bridge = function(op, player, payload, done)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			if done then done(nil) end
			return nil
		end,
		lineOfSight = function() return true end,
	})
	return w
end
local function tickLogic(w, seconds, step)
	step = step or 0.25
	local t, events = 0, {}
	while t < seconds - 1e-9 do
		w.clock += step
		t += step
		w.logic.beginTick()
		for _, e in ipairs(w.logic.lrTick()) do table.insert(events, e) end
		for _, r in ipairs(w.logic.records()) do w.logic.think(r) end
		w.logic.endTick()
	end
	return events
end
do
	local w = world()
	local center = Vector3.new(0, 0, 0)
	local members = {}
	for i = 1, 4 do members[i] = w.player(500 + i, center + Vector3.new(i * 3 - 6, 0, -8)) end
	local outsider = w.player(599, center + Vector3.new(0, 0, -6))
	local uids = {}
	for i, p in ipairs(members) do uids[i] = p.UserId end
	local r = w.logic.rdRegister("RUN:1", "Gloomfang", {Name = "Gloomfang"}, center + Vector3.new(0, 3, 11), {members = uids, party = 4, seed = 3, center = center, ground = 0})
	ok(r ~= nil and r.raid and r.lair, "raid encounter registered as a lair-shaped record")
	eq(r.maxHp, RD.partyHp(RD.Encounters.Gloomfang, 4), "party-scaled health")
	eq(r.damage, RD.partyDamage(RD.Encounters.Gloomfang, 4), "party-scaled damage")
	eq(w.logic.rdRegister("RUN:1", "Gloomfang", {}, center, {members = uids}), nil, "one record per fight")
	-- Eight members fit (the lair cap of three does not apply).
	local eight = {}
	for i = 1, 9 do eight[i] = 700 + i end
	local big = w.logic.rdRegister("RUN:2", "Siltmother", {Name = "Silt"}, center + Vector3.new(500, 3, 0), {members = eight, party = 8, center = center + Vector3.new(500, 0, 0)})
	local n = 0
	for _ in pairs(big.members) do n += 1 end
	eq(n, RD.MAX_PARTY, "up to eight members")
	eq(big.maxHp, RD.partyHp(RD.Encounters.Siltmother, 8), "eight-member health")
	local cm = w.logic.rdRegister("RUN:3", "Coralglass", {Name = "Coral"}, center + Vector3.new(1000, 3, 0), {members = {1}, party = 2, challenge = true, center = center + Vector3.new(1000, 0, 0)})
	eq(cm.maxHp, RD.partyHp(RD.Encounters.Coralglass, 1, true), "Challenge health (party clamps to the members)")
	eq(cm.def.damage, RD.partyDamage(RD.Encounters.Coralglass, 1, true), "Challenge damage on the per-fight def")
	-- The raid cap; lair fights are not crowded out by raid encounters.
	eq(w.logic.rdRegister("RUN:4", "Undine", {}, center, {members = {1}}), nil, "raid encounter cap (" .. RD.MAX_RAIDS .. ")")
	local lair = w.logic.lrRegister("L:1", "Bramblemaw", {Name = "B"}, center + Vector3.new(3000, 3, 0), {members = {1}, center = center + Vector3.new(3000, 0, 0)})
	ok(lair ~= nil, "a lair fight still registers while raids are live")
	for i = 2, LR.MAX_INSTANCES do w.logic.lrRegister("L:" .. i, "Bramblemaw", {Name = "B"}, center + Vector3.new(3000 + i * 400, 3, 0), {members = {1}, center = center + Vector3.new(3000 + i * 400, 0, 0)}) end
	eq(w.logic.lrRegister("L:99", "Bramblemaw", {Name = "B"}, center, {members = {1}}), nil, "the lair cap still counts lair fights")
	w.logic.lrDespawn("RUN:2"); w.logic.lrDespawn("RUN:3")
	for i = 1, LR.MAX_INSTANCES do w.logic.lrDespawn("L:" .. i) end
	-- Members only.
	w.positions[outsider] = r.position + Vector3.new(0, 0, 4)
	w.clock += 1
	local res, why = w.logic.attack(outsider, "attack", r.model)
	ok(res == nil and why == "lair", "outsiders cannot strike a raid encounter (" .. tostring(why) .. ")")
	w.positions[members[1]] = r.position + Vector3.new(0, 0, 4)
	w.clock += 1
	local hit = w.logic.attack(members[1], "attack", r.model)
	ok(hit and (hit.damage or 0) > 0, "a member strikes")
	local dmg = w.logic.rdDamage("RUN:1")
	ok(dmg[members[1].UserId] and dmg[members[1].UserId].damage > 0 and dmg[members[1].UserId].lastHit == w.clock, "per-UserId damage and last hit")
	-- Stances: Gloomfang trades fang and glyph every 2 swings; the prayer check applies.
	w.stats[members[1]].prayer = {protect = "melee"}
	local styles = {}
	for _ = 1, 40 do
		tickLogic(w, 0.5)
		if r.lastSwing and styles[#styles] ~= r.lastSwing.style then table.insert(styles, r.lastSwing.style) end
	end
	ok(table.find(styles, "melee") and table.find(styles, "magic"), "stance switching (" .. table.concat(styles, ",") .. ")")
	local prayed, raw = 0, 0
	for _, c in ipairs(w.calls_of("damage", members[1])) do
		if c.payload.style == "melee" then prayed += 1 elseif c.payload.style == "magic" then raw += 1 end
	end
	ok(prayed > 0 and raw > 0, "both stances landed on the praying member")
	-- The kill: every damaging member is paid; points come from per-UserId damage.
	for i, p in ipairs(members) do
		r.dmg[p.UserId] = r.dmg[p.UserId] or {damage = 0, xp = {}}
		if i <= 3 then r.dmg[p.UserId].damage += r.maxHp * 0.3; r.dmg[p.UserId].xp.melee = r.maxHp * 0.3; r.dmg[p.UserId].lastHit = w.clock end
	end
	r.hp = 1
	w.positions[members[1]] = r.position + Vector3.new(0, 0, 4)
	w.clock += 1
	local before = #w.calls_of("combatXp")
	local killed = w.logic.attack(members[1], "attack", r.model)
	ok(killed and killed.killed, "the encounter falls")
	local status = w.logic.lrStatus("RUN:1")
	ok(not status.alive and status.result == "win", "status reports the win")
	local credit = status.outcome.credit
	ok(credit[members[2].UserId].ok and credit[members[2].UserId].damage > 0 and credit[members[4].UserId].ok == false, "credit by damage share")
	ok(#w.calls_of("combatXp") - before >= 3, "damage XP paid to damaging members")
	eq(#w.calls_of("kill"), 0, "never a bridge kill for raid encounters")
	-- Raid adds and sigils run through the Lairs machinery.
	local rb = w.logic.rdRegister("RUN:5", "Runebound", {Name = "Rune"}, center + Vector3.new(0, 3, 11), {members = uids, party = 4, seed = 9, center = center, ground = 0})
	for i, p in ipairs(members) do w.positions[p] = center + Vector3.new(i * 3 - 6, 0, -8) end
	local sawSeals = false
	for _, e in ipairs(tickLogic(w, 12)) do if e.kind == "adds" and e.add == "TideSeal" and e.ordered then sawSeals = true; for k = 1, e.count do w.logic.lrRegisterAdd(rb, e.add, {Name = "Seal" .. k}, center + Vector3.new(k * 4, 0, 0), {order = k}) end end end
	ok(sawSeals, "Tide Seals rise (ordered)")
	ok(w.logic.lrSealed(rb), "the colossus is sealed")
	w.positions[members[1]] = rb.position + Vector3.new(0, 0, 4)
	w.clock += 1
	local _, sealedWhy = w.logic.attack(members[1], "attack", rb.model)
	eq(sealedWhy, "sealed", "immune while sealed")
	w.logic.lrDespawn("RUN:5")
	w.logic.lrDespawn("RUN:1")
end
do
	-- Lead decision (QC): the raid weapons' specials in the combat paths (L.tideMult).
	local w = world()
	local center = Vector3.new(0, 0, 0)
	local cleaver = w.player(801, center + Vector3.new(0, 0, -8))
	local plainHero = w.player(802, center + Vector3.new(0, 0, -8))
	w.stats[cleaver].loadout.weapon = "RegentsTidecleaver"
	local r = w.logic.rdRegister("TIDE:1", "Siltmother", {Name = "Silt"}, center + Vector3.new(0, 3, 11), {members = {801, 802}, party = 2, seed = 1, center = center, ground = 0})
	local add = w.logic.lrRegisterAdd(r, "Siltling", {Name = "Siltling"}, center + Vector3.new(4, 2, 0), {})
	ok(add ~= nil and w.logic.lrWarded(r), "a raid add shields the encounter")
	local function swing(p, target)
		w.positions[p] = target.position + Vector3.new(0, 0, 3)
		w.clock += 2
		target.hp = target.maxHp
		return w.logic.attack(p, "attack", target.model)
	end
	local sp = Data.Items
	local onAdd, plainAdd = swing(cleaver, add), swing(plainHero, add)
	ok(onAdd and plainAdd and onAdd.tide == true and not plainAdd.tide, "Riptide flags the Tidecleaver's hit on an add")
	ok(onAdd.damage > plainAdd.damage, "Riptide out-hits the same stats on an add (" .. onAdd.damage .. " > " .. plainAdd.damage .. ")")
	local onBoss, plainBoss = swing(cleaver, r), swing(plainHero, r)
	ok(onBoss and plainBoss and onBoss.damage == plainBoss.damage and not onBoss.tide, "no Riptide on the encounter itself")
	eq(w.logic.tideMult("RegentsTidecleaver", add), 1 + sp.RegentsTidecleaver.special.adds, "raid adds count for Riptide")
	eq(w.logic.tideMult("UndertowWarbow", r), 1 + sp.UndertowWarbow.special.raid, "Undertow on a raid encounter")
	eq(w.logic.tideMult("UndertowWarbow", add), 1, "no Undertow on raid adds")
	eq(w.logic.tideMult("DrownlightScepter", r), 1 + sp.DrownlightScepter.special.warded, "Drownlight while the brood shields her")
	local lair = w.logic.lrRegister("TIDE:L", "Bramblemaw", {Name = "B"}, center + Vector3.new(900, 3, 0), {members = {801}, center = center + Vector3.new(900, 0, 0)})
	eq(w.logic.tideMult("UndertowWarbow", lair), 1, "no Undertow on a lair boss")
	eq(w.logic.tideMult("DrownlightScepter", lair), 1, "no Drownlight on an unshielded lair boss")
	eq(w.logic.tideMult("DrownlightScepter", {worldBoss = true, adds = {[{}] = true}}), 1 + sp.DrownlightScepter.special.warded, "a world boss add wave shields")
	eq(w.logic.tideMult("RegentsTidecleaver", {add = true, parent = {worldBoss = true}}), 1 + sp.RegentsTidecleaver.special.adds, "world boss adds count")
	eq(w.logic.tideMult("RegentsTidecleaver", {add = true, superior = true}), 1, "a slayer superior is not a boss's add")
	eq(w.logic.tideMult("RegentsTidecleaver", {id = "BramblebackBoar"}), 1, "ordinary monsters do not")
	w.logic.lrDespawn("TIDE:1"); w.logic.lrDespawn("TIDE:L")
	-- QC M1: a finished lair-shaped fight drops its tile map (runtime LairRT.finish).
	local src = fs.readFile("combat.server.lua")
	local finish = src:match("function LairRT%.finish%(r%)(.-)\nend")
	ok(finish ~= nil and has(finish, "LairRT.tiles[r.fight] = nil"), "LairRT.finish clears the fight's tile map")
end
print("PASS: " .. (checks - partB) .. " raid combat assertions.")

------------------------------------------------------------------------------
-- Part C: server.server.lua (journal side).
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
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [markers.AetherTrails] = load("trails.lua")}
local rolls, defaultRoll = {}, 0.999
local function nextRoll() if #rolls > 0 then return table.remove(rolls, 1) end return defaultRoll end
local storage = {}
local livePlayers = {}
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return livePlayers end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) if name == "AetherTrails" then return markers.AetherTrails end return storage[name] end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "raid-test" end},
	RunService = {IsStudio = function() return false end, Heartbeat = signal()},
}
local serverObjects = {}
local journalClosers = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function(_, f) table.insert(journalClosers, f) end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end, FindFirstChild = function() return nil end},
	Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function(className)
		local o = {ClassName = className, Event = signal(), FireClient = function(_, player, state) player.last = state end}
		function o:Destroy() self.Parent = nil end
		table.insert(serverObjects, o)
		return o
	end},
	UDim2 = roblox.UDim2, Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum,
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return nextRoll() end, NextInteger = function(_, lo) return lo end} end},
	warn = function() end,
	task = {
		spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.taken = (self.taken or 0) + n end}
	local root = {Position = Vector3.new(0, 10, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Name = "Raider" .. id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true,
		FindFirstChild = function(_, name) if name == nil or name == "HumanoidRootPart" then return root end return nil end,
		FindFirstChildOfClass = function(_, name) if name == nil or name == "Humanoid" then return humanoid end return nil end,
		WaitForChild = function(_, name) if name == "HumanoidRootPart" then return root end return humanoid end,
		PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	for _, other in ipairs(table.clone(livePlayers)) do
		if other.UserId == id then
			table.remove(livePlayers, table.find(livePlayers, other))
			services.Players.PlayerRemoving:Fire(other)
		end
	end
	table.insert(livePlayers, p)
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p)
	local i = table.find(livePlayers, p)
	if i then table.remove(livePlayers, i) end
	p.Parent = nil
	services.Players.PlayerRemoving:Fire(p)
end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	mutate(data["p" .. id].profile)
	return player(id)
end
local remote, bridge, coopProfile
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
	if o.Name == "IsleCoopProfile" then coopProfile = o end
end
ok(remote ~= nil and bridge ~= nil and coopProfile ~= nil, "IsleAction, IsleBridge and IsleCoopProfile found")
storage.IsleBridge = {Invoke = function(_, opName, who, payload) return bridge.OnInvoke(opName, who, payload) end}
local function renew() for _, p in ipairs(livePlayers) do if p.Parent then coopProfile.OnInvoke(p, true) end end end
local function cmd(p, verb, item) advance(1); return remote.OnServerInvoke(p, verb, item) end
local function portalPrompt(at)
	local base = {CFrame = CFrame.new(at or Vector3.new(0, 10, 0))}
	local q = {Enabled = true, MaxActivationDistance = 9, attrs = {IsleAction = "raidPortal", IsleItem = RD.ID, IsleRegion = RD.REGION}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q)
	advance(2)
	p.last = nil
	p.root.Position = q:FindFirstAncestorWhichIsA("BasePart").CFrame.Position
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
local function op(p, payload) advance(0.1) return bridge.OnInvoke("raid", p, payload) end
local function raider(id, mutate)
	return seeded(id, function(prof)
		prof.xp.Combat = X[75]; prof.xp.Fishing = X[30]; prof.xp.Woodcutting = X[20]; prof.coins = 1000
		if mutate then mutate(prof) end
		-- Level coins already paid for the seeded levels (only raid pay moves the purse).
		prof.levelRewards = {}
		for skill, xp in pairs(prof.xp) do prof.levelRewards[skill] = P.levelForXp(xp) end
	end)
end
-- A scripted IsleRaids (Part D runs the real one).
local raidCalls = {}
local raidReply = {ok = true, lobby = "P1", members = 1}
storage.IsleRaids = {Invoke = function(_, opName, who, arg)
	if opName == "depart" or opName == "drain" then return nil end
	table.insert(raidCalls, {op = opName, player = who, arg = arg})
	return raidReply
end}
local rookie = player(9301)
local s0 = cmd(rookie, "state")
ok(type(s0.raids) == "table" and s0.raids.kc == 0 and s0.raids.active == "" and s0.raids.combat == RD.COMBAT, "fresh snapshot raids")
ok(has(cmd(rookie, "raidHost", "normal").message, "Combat " .. RD.COMBAT), "Combat gate")
ok(has(cmd(rookie, "raidPortal").message, "portal"), "the portal verb needs the prompt")
local low = use(rookie, portalPrompt())
ok(has(low.message, "Fishing") or has(low.message, "reach"), "region gate on the portal prompt: " .. tostring(low.message))
eq(#raidCalls, 0, "no lobby asked for while refused")
local hero = raider(9302)
local visit = use(hero, portalPrompt())
ok(has(visit.message, RD.NAME) and hero.attrs.RaidPortalUntil == math.floor(utc) + RD.PORTAL_SECONDS, "portal opens the board")
hero.attrs.LairBoss = "Bramblemaw"
ok(has(cmd(hero, "raidHost", "normal").message, "Finish"), "busy in a lair")
hero.attrs.LairBoss = ""
ok(has(cmd(hero, "raidHost", "challenge").message, "Challenge Mode"), "host relays")
eq(raidCalls[#raidCalls].op, "host", "IsleRaids host")
eq(raidCalls[#raidCalls].arg, true, "Challenge flag passed")
raidReply = {ok = false, reason = "portal"}
ok(has(cmd(hero, "raidJoin", "P1").message, "portal"), "refusals explained")
raidReply = {ok = true, members = 3}
ok(has(cmd(hero, "raidJoin", "P1").message, "3 raiders"), "join relays")
eq(raidCalls[#raidCalls].arg, "P1", "lobby id passed")
for _, verb in ipairs({"raidReady", "raidChallenge", "raidStart", "raidLeave", "raidUse"}) do
	local before = #raidCalls
	cmd(hero, verb, if verb == "raidUse" then "food" else "on")
	ok(#raidCalls == before + 1, verb .. " reaches IsleRaids")
end
ok(has(cmd(hero, "raidAct", "glyph:1").message, "fixtures"), "raidAct needs a room prompt")
-- Lairs see a raider as busy.
hero.attrs.RaidRun = "R:x"
ok(has(use(hero, (function()
	local base = {CFrame = CFrame.new(Vector3.new(0, 10, 0))}
	local q = {Enabled = true, MaxActivationDistance = 9, attrs = {IsleAction = "lairEnter", IsleItem = "Bramblemaw", IsleRegion = "Windpine"}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end)()).message, "Finish"), "lairs treat raiders as busy")
hero.attrs.RaidRun = ""
-- Rewards.
local function clear(id, extra)
	local payload = {action = "complete", run = id, seconds = 700, party = 4, points = 16000, team = 64000, challenge = false, deaths = 1,
		xp = {Fishing = 500, Cooking = 300, Combat = 99999, Magic = 50}}
	for k, v in pairs(extra or {}) do payload[k] = v end
	return op(hero, payload)
end
local coins0 = cmd(hero, "state").coins
local fishing0 = cmd(hero, "state").xp.Fishing
local combat0 = cmd(hero, "state").xp.Combat
defaultRoll = 0
local paid = clear("R:A:1", {unique = "UndertowWarbow"})
defaultRoll = 0.999
ok(paid.ok and paid.kc == 1 and paid.pb == true and paid.unique == "UndertowWarbow", "clear paid with the purple")
eq(paid.coins, RD.coins(16000), "coins from points")
local s1 = cmd(hero, "state")
ok(s1.coins >= coins0 + RD.coins(16000), "coins granted (plus level / collection coins)")
eq(s1.items.UndertowWarbow, 1, "the unique reaches the satchel")
ok(s1.xp.Fishing > fishing0, "resource XP paid")
eq(s1.xp.Combat, combat0, "only resource-room skills take raid XP (combat XP comes from damage)")
local looted = 0
for _, row in ipairs(RD.Loot) do looted += s1.items[row.item] or 0 end
ok(looted >= RD.rolls(16000), "regular loot from points")
eq(s1.raids.kc, 1, "Raid Log KC")
eq(s1.raids.pb["4"], 700, "PB per party size")
eq(s1.raids.got.UndertowWarbow, 1, "unique logged")
eq(s1.raids.deaths, 1, "deaths logged")
ok(s1.raids.titles.Vaultdiver == true, "first-clear title")
eq(op(hero, {action = "complete", run = "R:A:1", seconds = 600, party = 4, points = 16000, team = 64000}).reason, "paid", "paid once per run id")
-- Clamps: forged points / team / party / unique.
local coins1 = cmd(hero, "state").coins
local forged = clear("R:A:2", {points = 1e12, team = 5, party = 99, unique = "Crownbreaker", seconds = -5})
eq(forged.coins, RD.coins(RD.maxPersonal(8, false)), "points clamp to the run's bound")
eq(forged.unique, nil, "a non-raid item is never granted as a purple")
ok(cmd(hero, "state").coins >= coins1 + forged.coins, "clamped coins")
local kitNot = clear("R:A:3", {unique = "GildedTideKit", underPar = true})
eq(kitNot.unique, nil, "the kit is never a purple")
eq(cmd(hero, "state").items.GildedTideKit, nil, "no kit outside Challenge Mode")
local cmClear = clear("R:A:4", {challenge = true, underPar = true, seconds = 650})
ok(cmClear.ok, "Challenge clear")
local s2 = cmd(hero, "state")
eq(s2.items.GildedTideKit, 1, "under par: the cosmetic kit")
ok(s2.raids.titles.UndertideChampion and s2.raids.titles.RegentsBane and s2.raids.cm == 1, "Challenge titles")
eq(s2.raids.pbCm["4"], 650, "Challenge PB")
-- Ends.
eq(op(hero, {action = "end", run = "R:A:5", result = "timeout", deaths = 3}).ok, true, "a failed run closes")
eq(op(hero, {action = "end", run = "R:A:6", result = "nocredit", deaths = 0}).ok, true, "an uncredited run closes")
local s3 = cmd(hero, "state")
eq(s3.raids.fails, 1, "fails counted (no-credit runs are not failures)")
eq(s3.raids.deaths, 7, "deaths summed (four clears with one death, a failure with three)")
eq(op(hero, {action = "complete", run = string.rep("x", 80)}).reason, "invalid", "run id validated")
eq(op(hero, {action = "dance", run = "R:A:7"}).reason, "invalid", "unknown action")
-- Titles.
ok(has(cmd(hero, "raidTitle", "RegentsBane").message, "Regent's Bane") and hero.attrs.RaidTitle == "Regent's Bane", "wear a raid title")
ok(has(cmd(rookie, "raidTitle", "RegentsBane").message, "not earned"), "unearned titles refused")
ok(has(cmd(hero, "raidTitle", "Fake").message, "Choose"), "unknown titles refused")
cmd(hero, "raidTitle", "none")
eq(hero.attrs.RaidTitle, "", "title hidden")
cmd(hero, "raidTitle", "Vaultdiver")
-- Ward (damage taken) and the death purse exemption.
do
	local before = hero.humanoid.taken or 0
	bridge.OnInvoke("damage", hero, {amount = 1000})
	local plain = hero.humanoid.taken - before
	hero.attrs.RaidRun = "R:live"
	hero.attrs.RaidWardUntil = math.floor(utc) + 20
	before = hero.humanoid.taken
	bridge.OnInvoke("damage", hero, {amount = 1000})
	local warded = hero.humanoid.taken - before
	within(warded / plain, RD.WARD_MULT - 0.02, RD.WARD_MULT + 0.02, "a brewed ward cuts damage")
	hero.attrs.RaidWardUntil = math.floor(utc) - 1
	before = hero.humanoid.taken
	bridge.OnInvoke("damage", hero, {amount = 1000})
	eq(hero.humanoid.taken - before, plain, "an expired ward does nothing")
	local purse = cmd(hero, "state").coins
	hero.humanoid.Died:Fire()
	eq(cmd(hero, "state").coins, purse, "a raid death keeps the purse")
	hero.attrs.RaidRun = ""
	hero.humanoid.Died:Fire()
	eq(cmd(hero, "state").coins, purse - math.floor(purse * 0.10), "outside a raid the usual death loss applies")
end
-- Persistence, migration, goals.
leave(hero)
local saved = data["p9302"].profile
eq(saved.raids.kc, 4, "Raid Log saved")
eq(saved.colLog.counts.UndertowWarbow, 1, "Collection Log credits the purple")
eq(saved.colLog.counts.GildedTideKit, 1, "Collection Log credits the kit")
saved.raids.got.Nope = 3
hero = player(9302)
local back = cmd(hero, "state")
ok(back.raids.kc == 4 and back.raids.got.Nope == nil and back.raids.title == "Vaultdiver", "Raid Log survives a rejoin, sanitised")
eq(hero.attrs.RaidTitle, "Vaultdiver", "worn title re-published at load")
ok(has(cmd(hero, "goalSet", "kills:" .. RD.ID .. ":10").message or "", "") , "goal set")
local goals = cmd(hero, "state").systems.goals
local raidGoal
for _, g in ipairs(goals) do if g.a == RD.ID then raidGoal = g end end
ok(raidGoal and raidGoal.have == 4 and raidGoal.need == 10, "the goal board counts raid clears")
local old = seeded(9303, function(prof) prof.raids = "corrupt" end)
eq(cmd(old, "state").raids.kc, 0, "old saves migrate")
eq(bridge.OnInvoke("raid", {UserId = 1, Parent = true, GetAttribute = function() return nil end}, {action = "complete", run = "x"}).reason, "sync", "an unopened journal answers sync")
do
	-- QC L1: a clear that errors while its grants are built is resent and pays once.
	local payer = raider(9304)
	local coinsBefore = cmd(payer, "state").coins
	local realLoot = RD.regularLoot
	RD.regularLoot = function() RD.regularLoot = realLoot; error("loot table offline") end
	pcall(op, payer, {action = "complete", run = "R:L1", seconds = 700, party = 4, points = 8000, team = 32000})
	RD.regularLoot = realLoot
	local again = op(payer, {action = "complete", run = "R:L1", seconds = 700, party = 4, points = 8000, team = 32000})
	ok(again and again.ok, "the resend is paid")
	local gained = cmd(payer, "state").coins - coinsBefore
	ok(gained >= RD.coins(8000) and gained < 2 * RD.coins(8000), "a retried clear pays its coins once (" .. gained .. ", collection coins aside)")
	eq(op(payer, {action = "complete", run = "R:L1", seconds = 700, party = 4, points = 8000, team = 32000}).reason, "paid", "then the run id is spent")
	-- QC L2: a shutdown close is not a failure.
	local fails = cmd(payer, "state").raids.fails
	eq(op(payer, {action = "end", run = "R:L2", result = "shutdown", deaths = 0}).ok, true, "a shutdown closes the entry")
	eq(cmd(payer, "state").raids.fails, fails, "a shutdown does not count as a failed run")
end
print("PASS: " .. (checks - partC) .. " raid server assertions.")

------------------------------------------------------------------------------
-- Part D: raids.server.lua (instances) on Part C's real bridge, with a combat
-- double built from the real combat logic (IsleRaidCombat ops).
------------------------------------------------------------------------------
local partD = checks
local wsp = roblox.Instance.new("Workspace")
local islands = roblox.Instance.new("Folder")
islands.Name = "Islands"
islands.Parent = wsp
local portalAt = Vector3.new(400, 10, 300)
do
	local a = roblox.Instance.new("Part")
	a.Name = "Anchor_Waypoint_RaidPortal"
	a.CFrame = CFrame.new(portalAt)
	a.Parent = islands
end
local combatLogic = Combat.createLogic({
	Data = Data, Progression = P,
	now = function() return clock end, time = function() return utc end, rng = function() return 0.5 end,
	players = function() return livePlayers end,
	alive = function(p) return p.Parent ~= nil and p.humanoid.Health > 0 end,
	position = function(p) return p.root.Position end,
	heal = function() end,
	bridge = function(opName, who, payload, done)
		local reply = bridge.OnInvoke(opName, who, payload)
		if done then done(reply) end
		return reply
	end,
	lineOfSight = function() return true end,
})
local spawnFails = false
local spawned = {}
local tileMaps = {} -- QC M1: what the runtime would hold in LairRT.tiles
local function lingering()
	local n = 0
	for fight in pairs(spawned) do if combatLogic.lrResult(fight) ~= nil or tileMaps[fight] ~= nil then n += 1 end end
	return n
end
storage.IsleRaidCombat = {Invoke = function(_, opName, payload)
	if opName == "spawn" then
		if spawnFails then return {ok = false, reason = "build"} end
		local r = combatLogic.rdRegister(payload.fight, payload.encounter, {Name = payload.encounter}, payload.center + Vector3.new(0, 3, 11),
			{members = payload.members, party = payload.party, seed = payload.seed, center = payload.center, ground = payload.center.Y, challenge = payload.challenge})
		if not r then return {ok = false, reason = "register"} end
		spawned[payload.fight] = {record = r, tiles = payload.tiles, party = payload.party, members = payload.members}
		tileMaps[payload.fight] = payload.tiles
		return {ok = true, hp = r.maxHp}
	elseif opName == "status" then
		local status = combatLogic.lrStatus(payload.fight)
		if type(status) == "table" then status.dmg = combatLogic.rdDamage(payload.fight) end
		return status
	elseif opName == "despawn" then
		combatLogic.lrDespawn(payload.fight)
		tileMaps[payload.fight] = nil
		return {ok = true}
	end
	return nil
end}
storage.IsleRaids = nil
local closers = {}
local rdEnv = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function(_, f) table.insert(closers, f) end, JobId = "test-job-0001"},
	workspace = wsp,
	require = function(target) assert(target == markers.AetherData, "raids require shared data only") return Data end,
	Instance = {new = function(class)
		if class == "BindableFunction" then
			return setmetatable({ClassName = class}, {__newindex = function(t, k, v) rawset(t, k, v); if k == "Parent" then storage[t.Name] = t end end})
		end
		return roblox.Instance.new(class)
	end},
	Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Enum = roblox.Enum,
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	Random = {new = function() return {NextNumber = function() return nextRoll() end} end},
	warn = function() end,
}
local Raid
rdEnv.__RaidsHarness = function(api) Raid = api end
load("raids.server.lua", rdEnv)
ok(Raid ~= nil and storage.IsleRaids ~= nil and type(storage.IsleRaids.OnInvoke) == "function", "IsleRaids published")
storage.IsleRaids.Invoke = function(self, ...) return self.OnInvoke(...) end
local instances = wsp:FindFirstChild("RaidInstances")
ok(instances ~= nil, "instance folder")
eq(wsp:GetAttribute("RaidInstances"), "0/" .. RD.MAX_RAIDS, "instance gauge")
local heartbeat = services.RunService.Heartbeat
local renewedAt = clock
local function tick(seconds, step)
	step = step or 0.25
	local t = 0
	while t < seconds - 1e-9 do
		advance(step)
		t += step
		if clock - renewedAt > 60 then renewedAt = clock; renew() end
		combatLogic.beginTick()
		combatLogic.lrTick()
		for _, r in ipairs(combatLogic.records()) do combatLogic.think(r) end
		combatLogic.endTick()
		heartbeat:Fire(step)
	end
end
local function hud(p)
	local out = {}
	for pair in tostring(p.attrs.RaidHud or ""):gmatch("[^;]+") do local k, v = pair:match("^(%w+)=(.*)$"); if k then out[k] = v end end
	return out
end
local function partsIn(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return n
end
local moves = {}
local function party(ids)
	local list = {}
	for i, id in ipairs(ids) do
		local p = raider(id, function(prof) prof.xp.Combat = X[80]; prof.coins = 5000 end)
		p.root.Position = portalAt + Vector3.new(i * 2, 0, 0)
		local set = p.SetAttribute
		p.SetAttribute = function(self, key, value)
			if key == "FastTravelAt" then moves[self.UserId] = (moves[self.UserId] or 0) + 1 end
			return set(self, key, value)
		end
		table.insert(list, p)
	end
	return list
end
local function runOf(p) return Raid.runOf[p.UserId] end
local function roomOf(p) local run = runOf(p); return run and run.rooms[run.index] end
local function waitActive(p)
	for _ = 1, 200 do
		local room = roomOf(p)
		if room and room.state == "active" then tick(0.25) return room end -- one more step publishes the room's HUD
		tick(0.5)
	end
	error("room never became active")
end
local function promptFor(room, key)
	local part = room.parts[key]
	return part and part:FindFirstChildOfClass("ProximityPrompt")
end
local function press(p, room, key)
	-- §42 (owner decision): resource nodes are struck through the real Strike path.
	local part = room.parts[key]
	if part and part:GetAttribute("StrikeKind") == "raid" then
		ok(part:FindFirstChildOfClass("ProximityPrompt") == nil and part:GetAttribute("GatherNode") ~= nil, "§42: raid node " .. key .. " is a strike node, never a prompt")
		p.last = nil
		local at = part.CFrame.Position
		p.root.Position = Vector3.new(at.X, room.center.Y + 3, at.Z) + Vector3.new(0, 0, 2)
		for _ = 1, 30 do
			local r = remote.OnServerInvoke(p, "strike", part)
			if r == nil then advance(0.25)
			elseif r.broken then break
			elseif r.cast then advance(2.05)
			elseif r.ok == false and r.reason == "cadence" then advance(math.max(0.02, tonumber(r.wait) or 0.1))
			elseif r.ok == false then break
			else advance(0.7) end
		end
		return p.last
	end
	local q = promptFor(room, key)
	assert(q, "no prompt " .. key)
	advance(1)
	p.last = nil
	local at = q.Parent.CFrame.Position
	p.root.Position = Vector3.new(at.X, room.center.Y + 3, at.Z) + Vector3.new(0, 0, 2)
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
-- Kills the current encounter: every member carries a share; the last hit is recent.
local function slay(members, shares)
	local room = roomOf(members[1])
	local s = spawned[room.fight]
	local r = s.record
	for i, p in ipairs(members) do
		r.dmg[p.UserId] = r.dmg[p.UserId] or {damage = 0, xp = {}}
		r.dmg[p.UserId].damage += r.maxHp * (shares and shares[i] or 1 / #members)
		r.dmg[p.UserId].lastHit = clock
	end
	combatLogic.kill(r)
	tick(0.5)
	return r
end
local function solve(members, room)
	if room.id == "Glyphs" then
		for _, g in ipairs(room.puzzle.seq) do press(members[1], room, "glyph" .. g) end
	elseif room.id == "Valves" then
		for _, i in ipairs(RD.valveSolution(room.puzzle.state)) do press(members[1], room, "valve" .. i) end
	elseif room.id == "Seals" then
		for _ = 1, RD.SEAL_ROUNDS do
			for k, plateIndex in ipairs(room.puzzle.plates) do
				local at = room.parts["seal" .. plateIndex].CFrame.Position
				members[k].root.Position = Vector3.new(at.X, room.center.Y + 3, at.Z)
			end
			tick(RD.SEAL_HOLD + 0.75)
		end
	end
end
local function supply(members, room)
	local res = room.def
	local i = 0
	while room.state == "active" do
		for k, node in ipairs(res.nodes) do
			for j = 1, RD.NODES_PER_KIND do
				if room.state ~= "active" then break end
				i += 1
				local p = members[(i - 1) % #members + 1]
				press(p, room, "node" .. k .. ":" .. j)
				tick(RD.GATHER_COOLDOWN)
			end
		end
		for _, st in ipairs(res.stations) do
			while room.state == "active" and (room.resource.stock[(function() for _, n in ipairs(res.nodes) do if n.makes == st.makes then return n.id end end end)()] or 0) >= RD.RAW_PER_SUPPLY do
				press(members[1], room, "station" .. st.id)
			end
		end
	end
end
local function clearRoom(members)
	local room = waitActive(members[1])
	if room.kind == "combat" or room.kind == "boss" then slay(members)
	elseif room.kind == "puzzle" then solve(members, room)
	elseif room.kind == "resource" then supply(members, room) end
	return room
end
local function settle(members)
	-- Every member stays active (moving) between rooms.
	for _, p in ipairs(members) do p.root.Position = p.root.Position + Vector3.new(0.01, 0, 0) end
end

-- 1. Lobbies: portal range, host, join, ready, Challenge Mode, start.
local A = party({9401, 9402, 9403})
for _, p in ipairs(A) do use(p, portalPrompt(portalAt)) end
local far = A[3]
far.root.Position = portalAt + Vector3.new(200, 0, 0)
ok(has(cmd(far, "raidHost", "normal").message, "portal"), "hosting needs the portal in reach")
far.root.Position = portalAt + Vector3.new(4, 0, 0)
ok(has(cmd(A[1], "raidHost", "normal").message, "lead"), "host a party")
local lobbyId = Raid.lobbyOf[A[1].UserId].id
ok(has(wsp:GetAttribute("RaidLobbies"), lobbyId .. "|Raider9401|1|0"), "lobby board lists the party")
ok(has(A[1].attrs.RaidLobby, "hostMe=1"), "host card")
ok(has(cmd(A[1], "raidStart").message, "at least"), "a raid needs two raiders")
ok(has(cmd(A[2], "raidJoin", lobbyId).message, "2 raiders"), "join")
ok(has(cmd(A[3], "raidJoin", lobbyId).message, "3 raiders"), "join again")
ok(has(cmd(A[2], "raidChallenge", "on").message, "leader"), "only the leader toggles Challenge Mode")
ok(has(cmd(A[1], "raidStart").message, "ready"), "everyone must be ready")
cmd(A[2], "raidReady"); cmd(A[3], "raidReady")
ok(has(A[2].attrs.RaidLobby, "ready=1") and has(A[1].attrs.RaidLobby, "Raider9402*"), "ready marks")
ok(has(cmd(A[2], "raidHost", "normal").message, "already"), "a lobby member cannot host another party")
local startMoves = {}
for _, p in ipairs(A) do startMoves[p.UserId] = moves[p.UserId] or 0 end
local started = cmd(A[1], "raidStart")
ok(has(started.message, "portal opens"), "the raid begins: " .. tostring(started.message))
local run = runOf(A[1])
ok(run ~= nil and run.party == 3 and #run.rooms == 5, "run with five rooms")
eq(wsp:GetAttribute("RaidInstances"), "1/" .. RD.MAX_RAIDS, "instance gauge")
eq(wsp:GetAttribute("RaidLobbies"), "", "the lobby closes when the raid starts")
for _, p in ipairs(A) do
	ok(p.attrs.RaidRun == run.id and p.attrs.RaidLobby == "", "RaidRun set, lobby cleared")
	ok(moves[p.UserId] > startMoves[p.UserId], "FastTravelAt set on the move in")
	local d = p.root.Position - run.rooms[1].center
	ok(Vector3.new(d.X, 0, d.Z).Magnitude < RD.ARENA_RANGE, "moved into room 1")
end
local before = partsIn(instances)
ok(before > 5 * 14 and before < 400, "complex built on demand (" .. before .. " parts)")
for i, room in ipairs(run.rooms) do
	ok(room.model and room.model.Parent ~= nil and room.model:FindFirstChild("Raid exit"), "room " .. i .. " built with an exit")
	local q = room.model:FindFirstChild("Raid exit"):FindFirstChildOfClass("ProximityPrompt")
	eq(q:GetAttribute("IsleAction"), "raidLeave", "exit prompt")
end
-- 2. A full run.
local roomKinds = {}
local damageShares = {}
local hpByRoom = {}
for index = 1, 5 do
	local room = waitActive(A[1])
	eq(room.index, index, "room " .. index .. " active in order")
	table.insert(roomKinds, room.kind)
	local h = hud(A[1])
	ok(h.room == index .. "/5" and h.kind == room.kind and h.name == RD.roomName(room), "HUD names the room")
	if room.kind == "combat" or room.kind == "boss" then
		ok(h.hp ~= nil and h.style ~= nil and h.phase ~= nil, "combat HUD: health, stance, phase")
		local s = spawned[room.fight]
		eq(s.party, 3, "the encounter scales to the three inside")
		hpByRoom[index] = s.record.maxHp
		eq(s.record.maxHp, RD.partyHp(RD.Encounters[room.id], 3), "scaled health")
		slay(A, {0.5, 0.3, 0.2})
	elseif room.kind == "puzzle" then
		if room.id == "Glyphs" then
			ok(h.seq ~= nil and h.step == "0", "glyph HUD")
			-- A wrong glyph costs points and restarts.
			local wrong = room.puzzle.seq[1] % #RD.GLYPHS + 1
			local pts = run.members[A[2].UserId].points
			local reply = press(A[2], room, "glyph" .. wrong)
			ok(has(reply.message, "Wrong"), "wrong glyph")
			eq(run.members[A[2].UserId].points, math.max(0, pts - RD.Points.puzzleMistake), "a mistake costs points")
		elseif room.id == "Valves" then ok(h.valves ~= nil, "valve HUD")
		elseif room.id == "Seals" then ok(h.round == "1/" .. RD.SEAL_ROUNDS, "seal HUD") end
		local pts = run.members[A[1].UserId].points
		solve(A, room)
		ok(room.state == "cleared", "puzzle solved")
		ok(run.members[A[1].UserId].points > pts, "puzzle steps pay points")
	elseif room.kind == "resource" then
		ok(h.made ~= nil and h.stock ~= nil, "resource HUD")
		supply(A, room)
		ok(room.state == "cleared" and run.supplies.food + run.supplies.potion >= RD.quota(3), "supplies made to quota")
		ok(run.members[A[2].UserId].resource > 0, "resource work pays points")
		ok(next(run.members[A[2].UserId].xp) ~= nil, "resource XP tracked")
	end
	if index < 5 then
		ok(room.state == "cleared", "room " .. index .. " cleared")
		settle(A)
		tick(RD.ADVANCE_SECONDS + 0.5)
	end
end
ok(table.find(roomKinds, "puzzle") and table.find(roomKinds, "resource") and roomKinds[5] == "boss", "every room kind ran")
-- Supplies: shared pool, food heals, draughts ward.
-- (Checked before the end: the run is "won" now; use the journal's use path in a second run.)
ok(run.state == "won" and run.result ~= nil, "the Regent falls: the raid is won")
local result = run.result
eq(#result.credited, 3, "all three raiders credited")
local hero1 = data["p9401"]
local s9401 = cmd(A[1], "state")
eq(s9401.raids.kc, 1, "member 1 paid (Raid Log KC)")
eq(cmd(A[3], "state").raids.kc, 1, "member 3 paid")
ok(s9401.coins > 5000, "coins paid")
ok(has(A[1].attrs.RaidHud, "state=won") and has(A[1].attrs.RaidHud, "exit="), "won HUD with the exit countdown")
-- The purple: with roll 0.999 the run had no purple; the recipient rule is checked in run 2.
eq(result.unique, nil, "no purple on a high roll")
tick(RD.EXIT_SECONDS + 1)
eq(Raid.runs[run.id], nil, "the raid closes after the exit window")
eq(partsIn(instances), 0, "every part destroyed")
eq(#instances:GetChildren(), 0, "the complex folder is gone")
for _, p in ipairs(A) do
	eq(p.attrs.RaidRun, "", "RaidRun cleared")
	local d = p.root.Position - portalAt
	ok(d.Magnitude < 6, "returned to the portal")
end
eq(#combatLogic.records(), 0, "no creatures left")
eq(lingering(), 0, "QC M1: every won encounter is despawned (no result records or tile maps linger)")
eq(wsp:GetAttribute("RaidInstances"), "0/" .. RD.MAX_RAIDS, "slot freed")

-- 3. Second run: the purple roll and recipient, Challenge Mode, deaths, supplies, disconnect and rejoin.
local function lobby(members, challenge)
	for _, p in ipairs(members) do p.root.Position = portalAt + Vector3.new(2, 0, 0) end
	cmd(members[1], "raidHost", if challenge then "challenge" else "normal")
	local id = Raid.lobbyOf[members[1].UserId].id
	for i = 2, #members do cmd(members[i], "raidJoin", id); cmd(members[i], "raidReady") end
	local reply = cmd(members[1], "raidStart")
	assert(has(reply.message, "portal opens"), tostring(reply.message))
	return runOf(members[1])
end
local B = party({9411, 9412})
local run2 = lobby(B, true)
ok(run2.challenge == true, "Challenge Mode run")
local room = waitActive(B[1])
ok(has(B[1].attrs.RaidHud, "cm=1") and has(B[1].attrs.RaidHud, "par="), "Challenge HUD shows par")
if room.kind == "combat" then eq(spawned[room.fight].record.maxHp, RD.partyHp(RD.Encounters[room.id], 2, true), "Challenge health") end
-- A death: points take the loss, the member respawns and is returned.
run2.members[B[2].UserId].points = 4000
B[2].humanoid.Health = 0
tick(0.5)
eq(run2.members[B[2].UserId].points, 3000, "a death costs a quarter of the points")
eq(run2.members[B[2].UserId].deaths, 1, "death counted")
eq(B[2].attrs.RaidRejoin, true, "the raid owns the respawn")
B[2].root.Position = Vector3.new(0, 10, 0) -- respawned at home
B[2].humanoid.Health = 100
B[2].CharacterAdded:Fire(B[2].Character)
tick(0.5)
local d2 = B[2].root.Position - room.center
ok(Vector3.new(d2.X, 0, d2.Z).Magnitude < RD.ARENA_RANGE, "returned to the current room after respawning")
tick(RD.REJOIN_VERIFY + 0.5)
eq(B[2].attrs.RaidRejoin, nil, "respawn handed back")
-- Disconnect and rejoin within the window keeps the points.
run2.members[B[1].UserId].points = 7000
local m1 = run2.members[B[1].UserId]
leave(B[1])
tick(1)
ok(m1.offlineAt ~= nil and Raid.stash[9411] == run2, "held for a rejoin")
tick(20)
B[1] = raider(9411, function(prof) prof.xp.Combat = X[80] end)
eq(B[1].attrs.RaidRejoin, true, "rejoin claims the respawn")
tick(0.5)
ok(run2.members[9411] ~= nil and run2.members[9411].points == 7000 and run2.members[9411].player == B[1], "rejoined with the points kept")
local d1 = B[1].root.Position - run2.rooms[run2.index].center
ok(Vector3.new(d1.X, 0, d1.Z).Magnitude < RD.ARENA_RANGE, "back in the room")
tick(RD.REJOIN_VERIFY + 0.5)
-- Finish the run with a purple: roll 0 hits, the recipient goes by points.
for i = run2.index, 5 do
	local r = clearRoom(B)
	if i < 5 then settle(B); tick(RD.ADVANCE_SECONDS + 0.5) end
	if r.kind == "resource" then
		-- Supplies: the pool heals and wards.
		B[1].humanoid.Health = 40
		local food = run2.supplies.food
		ok(has(cmd(B[1], "raidUse", "food").message, "healed"), "eat from the pool")
		ok(B[1].humanoid.Health > 40 and run2.supplies.food == food - 1, "food heals and leaves the pool")
		ok(has(cmd(B[1], "raidUse", "food").message, "moment"), "supply cooldown")
		tick(RD.SUPPLY_COOLDOWN + 0.5)
		cmd(B[1], "raidUse", "potion")
		ok((B[1].attrs.RaidWardUntil or 0) > utc, "a draught raises the ward")
	end
	if i == 4 then rolls = {0, 0.99, 0.5} end -- before the Regent: hit, recipient at the top of the range (member 2 holds more points?), unique
end
ok(run2.state == "won", "second run won")
local res2 = run2.result
ok(res2.unique ~= nil and res2.recipient ~= nil, "a purple dropped")
local recipient = res2.recipient
local other = if recipient == 9411 then 9412 else 9411
tick(0.5)
local recP = if recipient == 9411 then B[1] else B[2]
eq(cmd(recP, "state").raids.got[res2.unique], 1, "the recipient logs the purple")
eq(cmd(if other == 9411 then B[1] else B[2], "state").raids.got[res2.unique], nil, "nobody else receives it")
ok(cmd(recP, "state").raids.cm == 1, "Challenge clear recorded")
tick(RD.EXIT_SECONDS + 1)
eq(Raid.runs[run2.id], nil, "second raid closed")

-- 4. Ironman: raids with others, loot only to themselves (the drawn recipient is the only one paid the purple).
local I = party({9421, 9422})
data["p9421"].profile.ironman = true
leave(I[1]); I[1] = raider(9421, function(prof) prof.ironman = true; prof.xp.Combat = X[80] end)
I[1].root.Position = portalAt
local run3 = lobby(I, false)
ok(run3 ~= nil and run3.members[9421] ~= nil, "an Ironman raids with others")
-- 5. Idle and away removal; abandoned raid.
local roomI = waitActive(I[1])
local idleMember = run3.members[9422]
idleMember.activeAt, idleMember.actionAt = clock - RD.IDLE_SECONDS - 1, clock - RD.IDLE_SECONDS - 1
I[2].root.Position = I[2].root.Position -- standing still
tick(0.5)
eq(run3.members[9422], nil, "an idle raider is removed")
eq(I[2].attrs.RaidRun, "", "the idle raider leaves the vault")
eq(cmd(I[2], "state").raids.fails, 1, "removal closes the journal entry")
I[1].root.Position = Vector3.new(0, 10, 0) -- teleported away
tick(RD.AWAY_SECONDS + 1)
eq(run3.members[9421], nil, "away too long: removed")
eq(Raid.runs[run3.id], nil, "a raid with no members ends")
eq(#combatLogic.records(), 0, "its encounter despawned")

-- 6. The exit prompt forfeits; the raid cap; build failures; shutdown.
local E = party({9431, 9432})
local run4 = lobby(E, false)
local exitQ = run4.rooms[1].model:FindFirstChild("Raid exit"):FindFirstChildOfClass("ProximityPrompt")
advance(2)
E[2].root.Position = exitQ.Parent.CFrame.Position + Vector3.new(0, 0, 2)
services.ProximityPromptService.PromptTriggered:Fire(exitQ, E[2])
eq(run4.members[9432], nil, "the exit prompt forfeits")
ok((E[2].root.Position - portalAt).Magnitude < 6, "and returns to the portal")
local F = party({9441, 9442})
local run5 = lobby(F, false)
local G = party({9451, 9452})
local run6 = lobby(G, false)
local H = party({9461, 9462})
for _, p in ipairs(H) do p.root.Position = portalAt end
cmd(H[1], "raidHost", "normal")
cmd(H[2], "raidJoin", Raid.lobbyOf[H[1].UserId].id); cmd(H[2], "raidReady")
ok(has(cmd(H[1], "raidStart").message, "in use"), "raid cap (" .. RD.MAX_RAIDS .. ")")
eq(wsp:GetAttribute("RaidInstances"), RD.MAX_RAIDS .. "/" .. RD.MAX_RAIDS, "gauge full")
-- A raid whose members all leave ends; the freed slot starts the waiting party.
cmd(F[1], "raidLeave"); cmd(F[2], "raidLeave")
eq(Raid.runs[run5.id], nil, "a raid whose members all leave ends")
ok(has(cmd(H[1], "raidStart").message, "portal opens"), "a freed slot starts the waiting party")
-- An encounter that cannot rise tears its raid down (seed chosen so room 1 is a combat room).
cmd(G[1], "raidLeave"); cmd(G[2], "raidLeave")
local J = party({9471, 9472})
local seed
for s0 = 1, 100000 do if RD.sequence(s0)[1].kind == "combat" then seed = s0 break end end
rolls = {seed / 1e6 + 1e-9}
spawnFails = true
local run7 = lobby(J, false)
eq(run7.seed, seed, "seeded run")
tick(RD.ROOM_GAP + 1)
spawnFails = false
eq(Raid.runs[run7.id], nil, "an encounter that cannot rise ends the raid")
eq(J[1].attrs.RaidRun, "", "its raiders are released")
-- QC L2: a shutdown drain is not a failed run for anyone inside.
do
	local inside = {}
	for _, liveRun in pairs(Raid.runs) do
		for _, m in pairs(liveRun.members) do if m.player and m.player.Parent then table.insert(inside, {p = m.player, fails = cmd(m.player, "state").raids.fails}) end end
	end
	ok(#inside > 0, "raiders are inside when the server closes")
	storage.IsleRaids:Invoke("drain")
	eq(next(Raid.runs), nil, "the drain tears every raid down")
	for _, e in ipairs(inside) do
		eq(cmd(e.p, "state").raids.fails, e.fails, "a shutdown is not a failure (" .. e.p.UserId .. ")")
		ok(has(e.p.attrs.RaidNotice, "shutting down"), "the shutdown is explained")
	end
end
local function seedWhere(pred)
	for s0 = 1, 999999 do if pred(RD.sequence(s0)) then return s0 end end
	error("no seed")
end
local function seeded(seed) rolls = {seed / 1e6 + 1e-9} end
-- QC H1: health scales with the members not offline (the dead count): seven deliberate deaths
-- during the countdown never lower the encounter.
do
	local seedCombat = seedWhere(function(q) return q[1].kind == "combat" end)
	local K = party({9501, 9502, 9503, 9504, 9505, 9506, 9507, 9508})
	seeded(seedCombat)
	local runK = lobby(K, false)
	eq(runK.party, 8, "eight raiders set out")
	for i = 2, 8 do K[i].humanoid.Health = 0 end
	tick(RD.ROOM_GAP + 0.5)
	local roomK = runK.rooms[1]
	ok(roomK.state == "active" and spawned[roomK.fight] ~= nil, "the encounter rises")
	eq(roomK.party, 8, "the room's party counts the dead")
	eq(spawned[roomK.fight].record.maxHp, RD.partyHp(RD.Encounters[roomK.id], 8), "seven resets during the countdown leave eight-member health")
	for _, p in ipairs(K) do p.humanoid.Health = 100; cmd(p, "raidLeave") end
	eq(Raid.runs[runK.id], nil, "the eight leave")
end
-- QC H1 / M2 / M3: an alt leaves after the start (the pool shrinks to the live party); a leech
-- with room clears and one hit is not credited; team points sum credited members; the PB bracket
-- and the journal's clamps use the starting party.
do
	local seedA = seedWhere(function(q)
		if q[1].kind ~= "combat" then return false end
		for _, r in ipairs(q) do if r.kind == "puzzle" and r.id == "Seals" then return false end end
		return true
	end)
	local X = party({9511, 9512, 9513, 9514})
	seeded(seedA)
	local runX = lobby(X, false)
	eq(runX.party, 4, "four set out")
	cmd(X[4], "raidLeave") -- an alt leaves after the start
	local workers, leech = {X[1], X[2]}, X[3]
	for index = 1, 5 do
		local room = waitActive(X[1])
		if index == 1 then
			eq(room.party, 3, "the encounter scales to the live party")
			eq(spawned[room.fight].record.maxHp, RD.partyHp(RD.Encounters[room.id], 3), "three-member health")
			local before = runX.members[X[1].UserId].points
			slay(workers, {0.5, 0.5})
			eq(runX.members[X[1].UserId].points - before, RD.damagePoints("combat", 0.5, 3) + RD.Points.clear, "the damage pool shrinks to the live party")
		elseif room.kind == "boss" then slay({X[1], X[2], leech}, {0.5, 0.49, 0.01})
		elseif room.kind == "combat" then slay(workers)
		elseif room.kind == "puzzle" then solve(workers, room)
		elseif room.kind == "resource" then
			-- §42: struck nodes take a few swings each, so the supply room runs past the
			-- idle limit; the leech shuffles about (movement, no points) to stay in.
			leech.root.Position += Vector3.new(RD.MOVE_STUDS + 1, 0, 0)
			tick(0.25)
			supply(workers, room)
		end
		if index < 5 then settle(X); tick(RD.ADVANCE_SECONDS + 0.5) end
	end
	ok(runX.state == "won" and runX.result ~= nil, "the three clear the vault")
	local resX = runX.result
	ok(table.find(resX.credited, X[1].UserId) and table.find(resX.credited, X[2].UserId), "the workers are credited")
	ok(not table.find(resX.credited, leech.UserId), "a leech with room clears and one hit is not credited")
	eq(runX.members[leech.UserId].creditReason, "share", "the leech falls below the contribution floor")
	local sum = 0
	for _, uid in ipairs(resX.credited) do sum += runX.members[uid].points end
	eq(resX.team, sum, "team points for the purple sum credited members only")
	eq(resX.chance, RD.uniqueChance(sum), "the purple chance reads that sum")
	tick(0.5)
	local log = cmd(X[1], "state").raids
	ok(log.pb["4"] ~= nil and log.pb["3"] == nil, "the PB bracket is the starting party")
	tick(RD.EXIT_SECONDS + 1)
	eq(Raid.runs[runX.id], nil, "closed")
end
-- QC M4: puzzles and the resource quota re-size to the live party.
do
	local seedS = seedWhere(function(q) return q[1].kind == "puzzle" and q[1].id == "Seals" end)
	local S = party({9521, 9522, 9523, 9524})
	seeded(seedS)
	local runS = lobby(S, false)
	local roomS = waitActive(S[1])
	eq(roomS.puzzle.need, 4, "four lit seals for four raiders")
	cmd(S[3], "raidLeave"); cmd(S[4], "raidLeave")
	tick(0.5)
	eq(roomS.puzzle.need, 2, "two leave: the round re-sizes")
	eq(#roomS.puzzle.plates, 2, "two seals lit")
	solve({S[1], S[2]}, roomS)
	ok(roomS.state == "cleared", "the shrunken party solves the seals")
	cmd(S[1], "raidLeave"); cmd(S[2], "raidLeave")
	eq(Raid.runs[runS.id], nil, "closed")
	local seedR = seedWhere(function(q) return q[1].kind == "resource" end)
	local R = party({9525, 9526, 9527, 9528})
	seeded(seedR)
	local runR = lobby(R, false)
	local roomR = waitActive(R[1])
	eq(roomR.resource.quota, RD.quota(4), "the quota for four")
	cmd(R[3], "raidLeave"); cmd(R[4], "raidLeave")
	tick(0.5)
	eq(roomR.resource.quota, RD.quota(2), "two leave: the quota shrinks")
	cmd(R[1], "raidLeave"); cmd(R[2], "raidLeave")
	eq(Raid.runs[runR.id], nil, "closed")
end
-- QC L3 / L4: throttled mistake notices, no wasted supplies, a missing character counts as away.
do
	local seedG = seedWhere(function(q) return q[1].kind == "puzzle" and q[1].id == "Glyphs" end)
	local Q = party({9531, 9532, 9533})
	seeded(seedG)
	local runQ = lobby(Q, false)
	local roomQ = waitActive(Q[1])
	local wrong = roomQ.puzzle.seq[1] % #RD.GLYPHS + 1
	local seen = Q[2].attrs.RaidNoticeCount or 0
	press(Q[1], roomQ, "glyph" .. wrong)
	press(Q[1], roomQ, "glyph" .. wrong)
	eq(runQ.mistakes, 2, "both mistakes count")
	eq((Q[2].attrs.RaidNoticeCount or 0) - seen, 1, "one member's repeated mistakes notify the party once")
	runQ.supplies.food, runQ.supplies.potion = 2, 2
	Q[1].humanoid.Health = Q[1].humanoid.MaxHealth
	ok(has(cmd(Q[1], "raidUse", "food").message, "full health"), "food is refused at full health")
	eq(runQ.supplies.food, 2, "and stays in the pool")
	ok(has(cmd(Q[1], "raidUse", "potion").message, "draught"), "a draught raises the ward")
	tick(RD.SUPPLY_COOLDOWN + 0.5)
	ok(has(cmd(Q[1], "raidUse", "potion").message, "ward is still up"), "a second draught is refused while the ward holds")
	eq(runQ.supplies.potion, 1, "the pool keeps it")
	tick(RD.Supplies.potion.ward - RD.WARD_REFRESH)
	ok(has(cmd(Q[1], "raidUse", "potion").message, "draught"), "the ward can be refreshed as it ends")
	Q[3].Character = nil -- no character root
	tick(RD.AWAY_SECONDS + 1)
	eq(runQ.members[9533], nil, "a member with no character counts as away")
	eq(Q[3].attrs.RaidRun, "", "and leaves the raid")
	cmd(Q[1], "raidLeave"); cmd(Q[2], "raidLeave")
	eq(Raid.runs[runQ.id], nil, "closed")
end
eq(lingering(), 0, "QC M1: no encounter results or tile maps grow over the runs")
for _, f in ipairs(journalClosers) do f() end
for _, f in ipairs(closers) do f() end
eq(next(Raid.runs), nil, "shutdown tears every raid down")
eq(partsIn(instances), 0, "nothing left behind")
print("PASS: " .. (checks - partD) .. " raid instance assertions.")

------------------------------------------------------------------------------
-- Part E: world.server.lua (portal, anchor, part budget).
------------------------------------------------------------------------------
local partE = checks
do
	local promptSignals = {}
	roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
		promptSignals[prompt] = promptSignals[prompt] or signal()
		return promptSignals[prompt]
	end)
	local wPlayers = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
	local dataModule = {Name = "AetherData"}
	local wServices = {
		Players = wPlayers, Lighting = roblox.Instance.new("Lighting"),
		CollectionService = {AddTag = function() end},
		ReplicatedStorage = {WaitForChild = function(_, name) return if name == "AetherData" then dataModule else nil end},
		ServerStorage = {FindFirstChild = function() return nil end},
	}
	local w = roblox.Instance.new("Workspace")
	local wEnv = {
		game = {GetService = function(_, name) return wServices[name] end}, workspace = w,
		Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, Color3 = roblox.Color3,
		UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
		task = {spawn = function(fn, ...) local co = coroutine.create(fn); assert(coroutine.resume(co, ...)); return co end, wait = function() return coroutine.yield() end},
		require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
	}
	local source = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
	luau.load(source, {environment = wEnv, injectGlobals = true})()
	local parts = 0
	for _, obj in w:GetDescendants() do if obj:IsA("BasePart") then parts += 1 end end
	local isle = w:FindFirstChild("Islands"):FindFirstChild(RD.ISLE)
	ok(isle ~= nil, "portal island exists")
	local portal
	for _, m in ipairs(isle:GetChildren()) do if m:GetAttribute("RaidContent") == true then portal = m end end
	ok(portal ~= nil, "portal model")
	local count, lights = 0, 0
	for _, d in ipairs(portal:GetDescendants()) do
		if d:IsA("BasePart") then count += 1; ok(d.Anchored, d.Name .. " anchored") end
		if d:IsA("Light") then lights += 1; eq(d:GetAttribute("LightWanted"), true, "portal light states intent (§35)") end
	end
	eq(count, 8, "portal: dais, step, arch, shimmer, two braziers, two coral fans")
	eq(lights, 1, "one portal light")
	eq(portal:FindFirstChild("Raid portal arch"):GetAttribute("Shape"), "ObservatoryArch", "arch mesh slot")
	local q = portal:FindFirstChild("Raid portal shimmer"):FindFirstChildOfClass("ProximityPrompt")
	ok(q and q:GetAttribute("IsleAction") == "raidPortal" and q:GetAttribute("IsleRegion") == RD.REGION, "portal prompt and region gate")
	ok(has(q.ObjectText, "Combat " .. RD.COMBAT), "the prompt names the requirement")
	local anchor = isle:FindFirstChild("Anchor_Waypoint_RaidPortal", true)
	ok(anchor ~= nil and anchor.Transparency == 1 and not anchor.CanCollide, "return anchor (quest helper target anchor:Waypoint_RaidPortal)")
	local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
	local sp = portal:FindFirstChild("Raid portal dais").CFrame.Position
	ok(Vector3.new(sp.X - c.X, 0, sp.Z - c.Z).Magnitude < r, "portal stands on its island")
	ok(parts < 4000, "static world under the 4000 part budget (" .. parts .. ")")
	print("World: " .. parts .. " static parts (" .. (count + 1) .. " for the raid portal).")
end
ok(has(fs.readFile("world.server.lua"), 'not player:GetAttribute("RaidRejoin")'), "world home landing skips a raid respawn")
-- Lighting: the raid interior profile and its context.
do
	local L = luau.load(fs.readFile("shared/LightingProfiles.lua"), {environment = {Color3 = roblox.Color3}, injectGlobals = true})()
	ok(L.Profiles.Raid and L.Profiles.Raid.interior and table.find(L.INTERIOR_KEYS, "Raid"), "Raid interior profile")
	eq(L.context({RaidRun = "R:1"}), "Raid", "RaidRun claims the raid look")
	eq(L.context({}, Vector3.new(-3700, 300, -3700)), "Raid", "the vault zone")
	eq(L.context({RaidRun = "R:1"}, Vector3.new(0, 10, 0)), L.DEFAULT_KEY, "a stale RaidRun outside the zone is ignored")
	eq(L.context({}, Vector3.new(-2400, 90, 0)), "Minigame", "minigames unchanged")
	eq(L.context({}, Vector3.new(3700, 300, -3600)), "Lair", "lairs unchanged")
	ok(has(fs.readFile("lighting.client.lua"), 'RaidRun = player:GetAttribute("RaidRun")') and has(fs.readFile("lighting.client.lua"), "RaidInstances = true"), "director reads RaidRun and budgets vault lights")
end
print("PASS: " .. (checks - partE) .. " raid world assertions.")

------------------------------------------------------------------------------
-- Part F: raid.client.lua (party board, raid HUD, Raid Log).
------------------------------------------------------------------------------
local partF = checks
do
	local UH = require("./tools/ui-harness")
	for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390)}) do
		local tag = " at " .. size.X .. "x" .. size.Y
		local snap = UH.snapshot({xp = {Combat = X[75]}})
		snap.raids = {kc = 3, cm = 1, fails = 1, deaths = 2, pb = {["4"] = 640}, pbCm = {["4"] = 700}, best = {points = 18000, team = 70000},
			got = {RegentsPearl = 1, GildedTideKit = 1}, log = {{t = 1, s = 640, n = 4, cm = false, pts = 15000, team = 60000, u = "RegentsPearl"}},
			titles = {Vaultdiver = true}, title = "", active = "", portalIn = 100, combat = RD.COMBAT}
		local ui = UH.runAtlas(size, {snapshot = snap})
		local wattrs, wsignals = {}, {}
		local space = {CurrentCamera = UH.new("Camera", {ViewportSize = size}),
			GetAttribute = function(_, k) return wattrs[k] end,
			GetAttributeChangedSignal = function(_, k) wsignals[k] = wsignals[k] or signal(); return wsignals[k] end,
			GetServerTimeNow = function() return 1000 end}
		local players = UH.new("Players", {LocalPlayer = ui.player})
		local fservices = {Players = players, ReplicatedStorage = ui.replicated, UserInputService = UH.new("UserInputService", {TouchEnabled = size.X < 900})}
		local game = UH.new("DataModel")
		function game.GetService(_, name) return assert(fservices[name], name) end
		local cenv = {game = game, workspace = space, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
			Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, TweenInfo = {new = function() return {} end},
			Instance = {new = function(class) return UH.new(class) end},
			task = {spawn = function() end, delay = function() end, wait = function() return 0 end, defer = function(f, ...) f(...) end},
			typeof = function(v) return typeof(v) end, print = function() end, warn = function(...) table.insert(ui.warnings, table.concat({...}, " ")) end}
		local theme = UH.loadTheme(cenv)
		cenv.require = function(target) if target.Name == "AetherUiTheme" then return theme end return Data end
		luau.load(fs.readFile("raid.client.lua"), {debugName = "raid.client.lua", environment = cenv, injectGlobals = true})()
		local gui = ui.player:FindFirstChild("PlayerGui"):FindFirstChild("IsleRaid")
		ok(gui ~= nil, "raid client loaded" .. tag)
		local board = gui:FindFirstChild("RaidBoard")
		ok(board and not board.Visible, "board hidden away from the portal" .. tag)
		-- At the portal: the open parties and Host buttons.
		wattrs.RaidLobbies = "P3|Wren|2|1;P4|Ash|5|0"
		ui.player:SetAttribute("RaidPortalUntil", 1100)
		ok(board.Visible, "board opens at the portal" .. tag)
		local function texts(root)
			local out = {}
			for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
			return table.concat(out, "\n")
		end
		ok(has(texts(board), "Wren's party") and has(texts(board), "CM") and has(texts(board), "Ash's party"), "open parties listed" .. tag)
		local sentBefore = #ui.sent
		local function sentVerb(verb, item)
			for i = sentBefore + 1, #ui.sent do if ui.sent[i][1] == verb and (item == nil or ui.sent[i][2] == item) then return true end end
			return false
		end
		local hostButton
		for _, d in ipairs(board:GetDescendants()) do if d.ClassName == "TextButton" and d.Text == "Host CM" then hostButton = d end end
		UH.press(hostButton)
		ok(sentVerb("raidHost", "challenge"), "Host CM sends raidHost challenge" .. tag)
		local joinButton
		for _, d in ipairs(board:GetDescendants()) do if d.ClassName == "TextButton" and d.Text == "Join" then joinButton = d; break end end
		UH.press(joinButton)
		ok(sentVerb("raidJoin", "P3"), "Join sends the lobby id" .. tag)
		-- In a lobby (leader).
		ui.player:SetAttribute("RaidLobby", "id=P3;host=Voyager;n=3;cm=1;hostMe=1;ready=1;members=Voyager*,Wren*,Ash;min=2;max=8")
		local t = texts(board)
		ok(has(t, "CHALLENGE MODE") and has(t, "Wren") and has(t, "Begin") and has(t, "CM: on"), "lobby card" .. tag)
		local begin
		for _, d in ipairs(board:GetDescendants()) do if d.ClassName == "TextButton" and d.Text == "Begin" then begin = d end end
		UH.press(begin)
		ok(sentVerb("raidStart"), "Begin sends raidStart" .. tag)
		-- In a run: the board hides, the HUD shows.
		ui.player:SetAttribute("RaidRun", "R:1")
		ui.player:SetAttribute("RaidHud", "run=R:1;room=5/5;kind=boss;name=Drowned Throne;state=active;cm=1;t=420;team=40000;me=12000;deaths=1;food=3;potion=2;foodName=Glowfin Broth;potionName=Reedroot Tonic;par=819;hp=200000/600000;phase=2/3;pname=Undertow;style=ranged;next=magic;sin=2;weak=ranged;enrage=60;ends=180;ward=0;seal=2;adds=3")
		ok(not board.Visible, "board hidden in a run" .. tag)
		local hudFrame = gui:FindFirstChild("RaidHud")
		ok(hudFrame.Visible, "raid HUD" .. tag)
		local ht = texts(hudFrame)
		ok(has(ht, "Drowned Throne") and has(ht, "Undertow") and has(ht, "Ward of Quills") and has(ht, "MAGIC in 2") and has(ht, "seal 2") and has(ht, "par"), "boss HUD: " .. ht)
		ok(has(ht, "Glowfin Broth (3)") and has(ht, "Reedroot Tonic (2)"), "supply buttons" .. tag)
		local food = UH.find(hudFrame, "RaidFood")
		UH.press(food)
		ok(sentVerb("raidUse", "food"), "Eat sends raidUse food" .. tag)
		ui.player:SetAttribute("RaidHud", "run=R:1;room=2/5;kind=puzzle;name=Glyph Concord;state=active;cm=0;t=100;team=9000;me=3000;deaths=0;food=0;potion=0;ends=200;seq=Tide,Pearl,Gale,Moon;step=2")
		ok(has(texts(hudFrame), "Chant") and has(texts(hudFrame), "Gale"), "glyph HUD" .. tag)
		ui.player:SetAttribute("RaidHud", "run=R:1;room=3/5;kind=resource;name=Moonmoss Grotto;state=active;cm=0;t=100;team=9000;me=3000;deaths=0;food=1;potion=2;ends=150;made=3/9;stock=Moonmoss:2,Gloomcap:1")
		ok(has(texts(hudFrame), "3/9") and has(texts(hudFrame), "Moonmoss:2"), "resource HUD" .. tag)
		ui.player:SetAttribute("RaidRun", "")
		ok(not hudFrame.Visible, "HUD hidden after the run" .. tag)
		-- Raid Log from the snapshot.
		ui.update.OnClientEvent:Fire(snap)
		local logButton = gui:FindFirstChild("RaidLogButton")
		ok(logButton and logButton.Visible, "Raid Log button" .. tag)
		UH.press(logButton)
		local logFrame = gui:FindFirstChild("RaidLog")
		ok(logFrame.Visible, "Raid Log opens" .. tag)
		local lt = texts(logFrame)
		ok(has(lt, "Clears 3") and has(lt, "Challenge 1") and has(lt, "4 raiders") and has(lt, "10:40") and has(lt, "Regent's Pearl") and has(lt, "Gilded Tide Kit")
			and has(lt, "Vaultdiver") and has(lt, "18,000"), "Raid Log content" .. tag)
		local wear
		for _, d in ipairs(logFrame:GetDescendants()) do if d.ClassName == "TextButton" and d.Text == "Wear" then wear = d end end
		UH.press(wear)
		ok(sentVerb("raidTitle", "Vaultdiver"), "Wear sends raidTitle" .. tag)
		eq(#ui.warnings, 0, "no warnings" .. tag)
	end
end
print("PASS: " .. (checks - partF) .. " raid client assertions.")

------------------------------------------------------------------------------
-- Part G: balance model.
------------------------------------------------------------------------------
local partG = checks
do
	local ref = LR.slayerReference(RD.COMBAT)
	local xpRef = Data.Minigames.soloCombatXpPerHour(RD.COMBAT)
	local EG = Data.DungeonEndgame
	local master7 = EG.model(7, true)
	local pyre, nih = LR.model("Pyrewarden", 1), LR.model("Nihlvar", 1)
	print(string.format("References at Combat %d: Slayer %.1fk coins/h, solo %.1fk Combat XP/h; Master VII %.1fk coins/h (+%.1fk chest), Pyrewarden %.1fk, Nihlvar %.1fk",
		RD.COMBAT, ref.coins / 1000, xpRef / 1000, master7.coins / 1000, master7.chestValue / 1000, pyre.coins / 1000, nih.coins / 1000))
	for _, cm in ipairs({false, true}) do
		for _, n in ipairs({2, 3, 4, 6, 8}) do
			local m = RD.model(n, {challenge = cm})
			print(string.format("  %s n=%d: run %s (fights %.0fs, boss %.0fs) %.2f runs/h, %d pts (team %d), coins+loot %.1fk/h (%.2fx Slayer, %.2fx Master VII, %.2fx Pyrewarden), Combat XP %.1fk/h (%.2fx), purple %.1f%%/run -> %.3f/h per member (1 per %.1f h), unique value %.1fk/h, pet %.0f h, weapon %.0f h",
				if cm then "CM" else "  ", n, RD.formatTime(m.run), m.fights, m.boss, m.runs, m.points, m.team, m.coins / 1000, m.coins / ref.coins, m.coins / master7.coins, m.coins / pyre.coins,
				m.xp / 1000, m.xp / xpRef, m.uniqueChance * 100, m.uniquesPerHour, 1 / m.uniquesPerHour, m.uniqueValue / 1000, m.petHours, m.perItemHours.RegentsTidecleaver))
			within(m.coins / ref.coins, 0.6, 1.25, "coins/h vs Slayer (n=" .. n .. (if cm then ", CM" else "") .. ")")
			within(m.coins / master7.coins, 0.6, 1.25, "coins/h vs Master VII (n=" .. n .. ")")
			within(m.xp / xpRef, 0.5, 1.0, "Combat XP/h below solo grinding (n=" .. n .. ")")
			within(m.run, 420, 1200, "a run takes 7-20 minutes (n=" .. n .. ")")
			within(1 / m.uniquesPerHour, 3, 15, "a purple every 3-15 hours per member (n=" .. n .. ")")
			within(m.petHours, 50, 200, "pet 50-200 h (n=" .. n .. ")")
			within(m.perItemHours.RegentsTidecleaver, 15, 100, "a given weapon 15-100 h (n=" .. n .. ")")
			ok(m.uniqueChance <= RD.UNIQUE_CAP, "purple chance under the cap")
		end
	end
	-- Party size barely moves per-member pay (points are per member, HP scales 0.85).
	local two, eight = RD.model(2), RD.model(8)
	within(eight.coins / two.coins, 0.9, 1.2, "per-member coins flat across party sizes")
	within(eight.uniquesPerHour / two.uniquesPerHour, 0.9, 1.2, "per-member purples flat across party sizes")
	-- Challenge Mode: no better coins/h (cosmetic rewards), par is the modelled clear.
	ok(RD.model(4, {challenge = true}).coins <= RD.model(4).coins * 1.05, "Challenge Mode pays no more coins per hour")
	eq(RD.par(4), math.floor(RD.model(4, {challenge = true}).run), "par = the modelled Challenge clear")
	-- No coin mint: the kit is worth 1 coin, every loot row is an existing material.
	for _, row in ipairs(RD.Loot) do ok(Data.Items[row.item].kind == "material", row.item .. " is a material") end
end
print("PASS: " .. (checks - partG) .. " raid balance assertions.")
print("Raids: " .. checks .. " checks.")
print("SUITE-END verify-raid.luau")
