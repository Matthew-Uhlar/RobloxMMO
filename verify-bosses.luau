-- Lairs (Bossing team): four instanced lair bosses. docs/DEPTH-CONTRACT.md §25.
-- Part A checks shared/GameData.lua (Data.Lairs): bosses, mechanics, the
--   triangle, uniques vs their crafted/dungeon rivals (stat by stat, higher
--   requirement), pets, loot and drop tiers, the Collection Log tab, tile
--   lattices, stances, credit, entry, migration and records, original names.
-- Part B drives combat.server.lua's Lairs section through the harness hook:
--   membership, stances and the prayer check, brood wards, ordered sigils,
--   tile lattices and telegraphs (styleless), phases and weakness turns,
--   enrage, timeout, per-UserId credit kept across a rejoin, damage XP, and
--   never a bridge "kill" for lair creatures.
-- Part C runs server.server.lua: altar verb gates (level, region, coins,
--   busy), the fee, bridge "lair" (kill once per fight and entry, refund,
--   end/deaths), loot through collect() (Collection Log tab Lairs), kill
--   counts, personal bests, the snapshot, migration and persistence.
-- Part D runs lairs.server.lua with real instances, wired to Part C's bridge
--   and a combat double built from the real combat logic: open, warmup, crew
--   join, rise, HUD, kill and reward, exit and teardown (parts, connections,
--   creatures), FastTravelAt on every move, death, away, disconnect and
--   rejoin, abandoned fights, instance cap, build failure refunds.
-- Part E builds world.server.lua: four altars, prompts, anchors and the part
--   budget. Part F renders Hunt › Bosses and the in-fight HUD.
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
local LR = Data.Lairs
local CS = Data.CombatStyles
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
ok(type(LR) == "table", "Data.Lairs present")
eq(#LR.Order, 4, "four lair bosses")
local levels = {30, 50, 70, 90}
local kinds = {}
for i, id in ipairs(LR.Order) do
	local def = LR.Bosses[id]
	eq(def.id, id, id .. " id")
	eq(def.index, i, id .. " index")
	eq(def.level, levels[i], id .. " level")
	ok(def.combat <= def.level and def.combat >= def.level - 10, id .. " Combat gate near its level")
	ok(type(def.lairName) == "string" and #def.lairName > 6 and type(def.blurb) == "string", id .. " lair text")
	ok(#def.color == 6 and #def.arenaColor == 6, id .. " colours")
	ok(Data.RegionById[def.region] ~= nil and Data.Exploration.IsleRegion[def.isle] == def.region, id .. " altar island in its region")
	ok(CS.names[def.weakness] and CS.names[def.defenceStyle] and def.weakness ~= def.defenceStyle, id .. " triangle")
	eq(CS.beats[CS.beats[def.weakness]], def.defenceStyle, id .. " resisted style follows the triangle")
	ok(#def.phases >= 2 and def.phases[1].at == 1, id .. " phases")
	for p = 2, #def.phases do ok(def.phases[p].at < def.phases[p - 1].at, id .. " phase thresholds descend") end
	ok(def.enrage < def.duration and def.enrage >= 120, id .. " enrage before the time limit")
	ok(#def.mechanics >= 3, id .. " documents its mechanics")
	for _, phase in ipairs(def.phases) do
		for _, a in ipairs(phase.rotation) do
			local attack = def.attacks[a]
			ok(attack ~= nil, id .. " attack " .. a)
			kinds[id .. attack.kind] = true
			if attack.kind == "adds" or attack.kind == "sigils" then
				ok(LR.Adds[attack.add] ~= nil and attack.count <= LR.MAX_ADDS, id .. " adds exist within the cap")
			elseif attack.kind == "tiles" then
				ok(def.tiles == true and attack.count <= LR.GRID * LR.GRID - LR.MIN_SAFE, id .. " lattice leaves safe cells")
			else
				ok(attack.radius > 0 and attack.windup >= 1.5 and attack.mult >= 1.5, id .. " telegraph " .. a .. " is fair")
			end
		end
	end
	if i > 1 then
		local prev = LR.Bosses[LR.Order[i - 1]]
		ok(def.hp > prev.hp and def.damage > prev.damage and def.fee > prev.fee and def.coins > prev.coins and def.defense > prev.defense, id .. " scales above " .. prev.id)
	end
end
-- Distinct mechanic sets.
ok(kinds.Bramblemawadds and not kinds.Bramblemawtiles and #LR.Bosses.Bramblemaw.stances == 1, "Bramblemaw: brood ward, no stance switch")
ok(kinds.Aeriscatiles and kinds.Aeriscasafe and #LR.Bosses.Aerisca.stances == 2, "Aerisca: lattice and two stances")
ok(kinds.Pyrewardensigils and #LR.Bosses.Pyrewarden.stances == 2, "Pyrewarden: ordered sigils and two stances")
ok(kinds.Nihlvarsigils and kinds.Nihlvartiles and #LR.Bosses.Nihlvar.stances == 3, "Nihlvar: every mechanic and all three stances")
do
	local seen = {}
	for _, id in ipairs(LR.Order) do
		local w = {}
		for p = 1, #LR.Bosses[id].phases do w[LR.weaknessAt(LR.Bosses[id], p)] = true end
		for k in pairs(w) do seen[id .. k] = true end
	end
	ok(seen.Nihlvarmagic and seen.Nihlvarranged and seen.Nihlvarmelee, "Nihlvar's weakness turns through all three styles")
end
-- Monster lookups: reachable by id, never iterated.
for _, id in ipairs(LR.Order) do
	eq(Data.Monsters[id], LR.Bosses[id], id .. " reachable through Data.Monsters")
	eq(rawget(Data.Monsters, id), nil, id .. " not iterated")
	ok(Data.Monsters[id].lair == true, id .. " flagged lair")
end
for id, def in pairs(LR.Adds) do
	eq(Data.Monsters[id], def, id .. " add reachable")
	ok(def.lairAdd and def.xp > 0 and def.hp > 0, id .. " add stats")
end
eq(Data.Monsters.Aurelith, Data.WorldBosses.Aurelith, "world bosses still resolve")
eq(Data.Monsters.ShellsnapCrab, Data.SeaCreatures.ShellsnapCrab, "sea creatures still resolve")
for id in pairs(Data.Monsters) do ok(not LR.Bosses[id] and not LR.Adds[id], id .. " iteration has no lair creature") end
-- Original names only.
local BANNED = {"Zulrah","Vorkath","Cerberus","Hydra","Kraken","Jad","Zuk","Nex","Muspah","Sire","Nightmare","Gauntlet","Sepulchre","Corrupted","Grotesque",
	"Revenant","Sven","Tarantula","Voidgloom","Inferno","Blaze","Necron","Scion","Yama","Araxxor","Vardorvis","Leviathan","Duke","Whisperer","Sarachnis","Vet'ion","Callisto","Venenatis",
	"Kalphite","Dagannoth","Bandos","Armadyl","Zamorak","Saradomin","Thermonuclear","Kuudra","Bonzo","Livid","Sadan","Goldor","Maxor"}
local function names()
	local list = {}
	for _, id in ipairs(LR.Order) do
		local def = LR.Bosses[id]
		for _, n in ipairs({def.name, def.short, def.lairName}) do table.insert(list, n) end
		for _, item in pairs(LR.Uniques[id]) do table.insert(list, Data.Items[item].name) end
		for _, a in pairs(def.attacks) do table.insert(list, a.name) end
	end
	for _, def in pairs(LR.Adds) do table.insert(list, def.name) end
	return list
end
for _, n in ipairs(names()) do
	for _, b in ipairs(BANNED) do ok(not string.find(string.lower(n), "%f[%a]" .. string.lower(b):gsub("'", "") .. "%f[%A]"), n .. " is original (" .. b .. ")") end
end
-- Uniques: gear model, rivals, pets.
local G = Data.Gear
for _, id in ipairs(LR.Order) do
	local u = LR.Uniques[id]
	local weapon, acc, pet = Data.Items[u.weapon], Data.Items[u.accessory], Data.Items[u.pet]
	ok(weapon and weapon.kind == "weapon" and weapon.slot == "weapon" and weapon.lairBoss == id and weapon.logUnique == "Lairs", id .. " weapon unique")
	ok(acc and acc.kind == "accessory" and acc.lairBoss == id and acc.logUnique == "Lairs", id .. " accessory unique")
	ok(pet and pet.kind == "pet" and Data.PetById[pet.pet] ~= nil and pet.lairBoss == id, id .. " pet unique")
	ok(G.category(weapon) ~= nil and G.canStar(G.category(weapon)), id .. " weapon takes stars")
	ok(Data.Rarity[weapon.rarity] and Data.Rarity[acc.rarity] and weapon.value > 0, id .. " rarities")
	local species = Data.PetById[pet.pet]
	ok(Data.PetDepth.Abilities[species.id] ~= nil and #Data.PetDepth.Abilities[species.id] == 3 and Data.PetDepth.Looks[species.id] ~= nil, id .. " pet abilities and look")
	for _, a in ipairs(Data.PetDepth.Abilities[species.id]) do ok(a.index ~= nil and type(a.id) == "string", id .. " pet ability " .. a.name .. " indexed") end
	ok(type(Data.PetDepth.bodyPlan(species.id, species.rarity)) == "table", id .. " pet body plan")
end
local function req(def)
	local best = 0
	for _, v in pairs(def.requires or {}) do best = math.max(best, v) end
	return best
end
for item, rivalId in pairs(LR.Rivals) do
	local def, rival = Data.Items[item], Data.Items[rivalId]
	ok(def and rival and def.lairBoss ~= nil and not rival.lairBoss, item .. " has rival " .. rivalId)
	eq(def.kind, rival.kind, item .. " rival kind")
	if def.kind == "weapon" then
		eq(G.category(def), G.category(rival), item .. " rival style")
		ok(req(rival) > req(def), rivalId .. " needs more than " .. item .. " (" .. req(rival) .. " > " .. req(def) .. ")")
		for skill in pairs(def.requires) do ok(rival.requires[skill] ~= nil, item .. " requirement skill matches the rival") end
		if def.ranged then
			ok(def.ranged.power <= rival.ranged.power * LR.UNIQUE_MAX + 1e-9 and def.ranged.maxAmmoTier <= rival.ranged.maxAmmoTier and def.ranged.speed >= rival.ranged.speed, item .. " bow power <= 85% of " .. rivalId)
		end
		if def.magic then ok(def.magic.power <= rival.magic.power * LR.UNIQUE_MAX + 1e-9 and #def.magic.elements <= #rival.magic.elements, item .. " staff power <= 85% of " .. rivalId) end
	end
	-- Lead decision: every main stat <= 85% of the higher-requirement rival's.
	for stat, v in pairs(def.stats) do
		ok(rival.stats[stat] ~= nil, item .. " " .. stat .. " is a stat the rival has")
		ok(v <= (rival.stats[stat] or 0) * LR.UNIQUE_MAX + 1e-9, item .. " " .. stat .. " " .. v .. " <= 85% of " .. rivalId .. " " .. tostring(rival.stats[stat]))
	end
	-- Five regular stars on both: the same +% keeps the order.
	local mine = G.breakdown({stars = {[item] = 5}}, item).total
	local theirs = G.breakdown({stars = {[rivalId] = 5}}, rivalId).total
	for stat, v in pairs(def.stats) do ok(v + (mine[stat] or 0) < rival.stats[stat] + (theirs[stat] or 0), item .. " 5★ " .. stat .. " stays below " .. rivalId .. " 5★") end
end
-- Uniques also beat (or match) the open crafted item of their own tier: a real reward.
ok(Data.Items.ThornmawCleaver.stats.damage > Data.Items.StarmetalSword.stats.damage, "Thornmaw Cleaver above the Combat-30 craft")
ok(Data.Items.GalesongLongbow.ranged.power > Data.Items.StarwoodLongbow.ranged.power, "Galesong above the Ranged-40 longbow")
-- (At 85% of Crownbreaker, Hollowcrown sits below the Combat-60 Sovereign Greatblade; it still beats the Combat-40 Prismatic Sword.)
ok(Data.Items.HollowcrownEdge.stats.damage > Data.Items.PrismaticSword.stats.damage, "Hollowcrown above the Combat-40 craft")
-- Polish: Hollow Sunder gives the Hollowcrown Edge a niche (bosses) without lifting it on general content.
-- Expected melee hit (SkyBlock formula, crits averaged) with the weapon's stats plus a gear profile.
do
	local function expected(id, gear)
		local st = Data.Items[id].stats
		local str = st.strength + gear.strength
		local cc = math.min(100, st.critChance + gear.critChance)
		local cd = st.critDamage + gear.critDamage
		return (5 + st.damage) * (1 + str / 100) * (1 + cc / 100 * cd / 100)
	end
	local sp = Data.Items.HollowcrownEdge.special
	ok(type(sp) == "table" and sp.id == "HollowSunder" and sp.boss > 0 and sp.warded >= sp.boss, "Hollowcrown carries Hollow Sunder")
	ok(has(Data.Items.HollowcrownEdge.description, "Hollow Sunder"), "the tooltip names Hollow Sunder")
	eq(LR.sunderMult("HollowcrownEdge", {boss = false}), 1, "no Sunder on ordinary monsters")
	eq(LR.sunderMult("HollowcrownEdge", {boss = true}), 1 + sp.boss, "Sunder on bosses")
	eq(LR.sunderMult("HollowcrownEdge", {boss = true, warded = true}), 1 + sp.warded, "stronger Sunder on shielded bosses")
	eq(LR.sunderMult("SovereignGreatblade", {boss = true}), 1, "other weapons have no Sunder")
	eq(LR.sunderMult("Crownbreaker", {boss = true, warded = true}), 1, "the rival has no Sunder")
	for _, profile in ipairs({
		{name = "weapon only", strength = 0, critChance = 0, critDamage = 0},
		{name = "Combat-65 kit", strength = 100, critChance = 20, critDamage = 100},
		{name = "endgame kit", strength = 220, critChance = 45, critDamage = 220},
	}) do
		local hc, sg, cb = expected("HollowcrownEdge", profile), expected("SovereignGreatblade", profile), expected("Crownbreaker", profile)
		local boss, warded = hc * LR.sunderMult("HollowcrownEdge", {boss = true}), hc * LR.sunderMult("HollowcrownEdge", {boss = true, warded = true})
		print(string.format("  Hollow Sunder (%s): general %.0f vs Greatblade %.0f / Crownbreaker %.0f; bosses %.0f (%.2fx Greatblade, %.2fx Crownbreaker); warded %.0f",
			profile.name, hc, sg, cb, boss, boss / sg, boss / cb, warded))
		ok(hc < sg and hc < cb, "general content: Hollowcrown stays below its rivals (" .. profile.name .. ")")
		ok(boss > sg, "bosses: Hollowcrown beats the easier Sovereign Greatblade (" .. profile.name .. ")")
		ok(boss < cb, "bosses: Hollowcrown stays below the Crownbreaker (" .. profile.name .. ")")
	end
end
-- Loot: only the uniques are rare; pets ~40 h of kills.
for _, id in ipairs(LR.Order) do
	local loot, unique = LR.Loot[id], 0
	for _, d in ipairs(loot) do
		ok(Data.Items[d.item] ~= nil and d.min >= 1 and d.max >= d.min and d.chance > 0 and d.chance <= 1, id .. " loot row " .. d.item)
		if LR.isUnique(d.item) then
			unique += 1
			ok(d.chance < Data.CommissionsLogs.RARE_CHANCE, d.item .. " is a rare row")
		else
			ok(d.chance >= Data.CommissionsLogs.RARE_CHANCE, d.item .. " stays out of the Collection Log")
			ok(Data.Items[d.item].kind ~= "pet" and not LR.isUnique(d.item), d.item .. " ordinary")
		end
	end
	eq(unique, 3, id .. " has three uniques")
	eq(LR.Bosses[id].drops, loot, id .. " drops shown")
	within(LR.PetChance[id], 1 / 3000, 1 / 400, id .. " pet chance (OSRS-like, scaled)")
end
eq(LR.dropTier(1).id, "Guaranteed", "tier guaranteed")
eq(LR.dropTier(0.4).id, "Frequent", "tier frequent")
eq(LR.dropTier(0.08).id, "Occasional", "tier occasional")
eq(LR.dropTier(1 / 90).id, "Rare", "tier rare")
eq(LR.dropTier(1 / 200).id, "Elusive", "tier elusive")
eq(LR.dropTier(1 / 900).id, "Fabled", "tier fabled")
eq(LR.dropTier(nil).id, "Fabled", "tier of garbage")
do
	local def = LR.Bosses.Bramblemaw
	eq(LR.coinRoll("Bramblemaw", 0), def.coinRange.min, "coin roll floor")
	eq(LR.coinRoll("Bramblemaw", 0.9999999), def.coinRange.max, "coin roll ceiling")
	eq(LR.coinRoll("Nope", 0.5), 0, "unknown boss pays nothing")
end
-- Collection Log: tab Lairs holds the eight weapon/accessory uniques; pets join the Pets tab.
do
	local CL = Data.CommissionsLogs
	local L = CL.log(true)
	ok(CL.LogTabs.Lairs ~= nil and CL.LogTabs.Lairs.coins > 0 and #CL.LogTabs.Lairs.title > 3, "Lairs tab and reward")
	eq(table.find(CL.LogTabOrder, "Lairs"), table.find(CL.LogTabOrder, "Bosses") + 1, "Lairs tab after World Bosses")
	ok(table.find(L.Order, "Lairs") ~= nil, "Lairs tab shown")
	eq(#L.Tabs.Lairs, 8, "eight lair uniques in the tab")
	for _, id in ipairs(LR.Order) do
		local u = LR.Uniques[id]
		eq(L.Of[u.weapon], "Lairs", u.weapon .. " in Lairs")
		eq(L.Of[u.accessory], "Lairs", u.accessory .. " in Lairs")
		eq(L.Of[u.pet], "Pets", u.pet .. " in Pets")
	end
	for _, item in ipairs(L.Tabs.Lairs) do ok(LR.isUnique(item), item .. " in the Lairs tab is a lair unique") end
end
-- Fight rules.
eq(LR.partyHp(LR.Bosses.Aerisca, 1), LR.Bosses.Aerisca.hp, "solo health")
eq(LR.partyHp(LR.Bosses.Aerisca, 3), math.floor(LR.Bosses.Aerisca.hp * (1 + 2 * LR.PARTY_HP)), "party of three")
eq(LR.partyHp(LR.Bosses.Aerisca, 9), LR.partyHp(LR.Bosses.Aerisca, LR.MAX_PARTY), "party capped")
eq(LR.phaseAt(LR.Bosses.Pyrewarden, 1), 1, "phase 1 at full")
eq(LR.phaseAt(LR.Bosses.Pyrewarden, 0.66), 2, "phase 2 at 66%")
eq(LR.phaseAt(LR.Bosses.Pyrewarden, 0.1), 3, "phase 3 low")
eq(LR.stanceAt(LR.Bosses.Aerisca, 1, 1), "melee", "Aerisca opens melee")
eq(LR.stanceAt(LR.Bosses.Aerisca, 1, 4), "melee", "fourth swing still melee")
eq(LR.stanceAt(LR.Bosses.Aerisca, 1, 5), "ranged", "fifth swing ranged")
eq(LR.stanceAt(LR.Bosses.Aerisca, 1, 9), "melee", "ninth swing melee again")
eq(LR.stanceAt(LR.Bosses.Nihlvar, 1, 7), "magic", "Nihlvar's third stance")
eq(LR.stanceAt(LR.Bosses.Bramblemaw, 1, 500), "melee", "Bramblemaw never switches")
eq(LR.prayerMult("ranged", "ranged"), LR.PRAYED, "prayed stance")
eq(LR.prayerMult("ranged", "melee"), 1, "wrong prayer")
eq(LR.prayerMult(nil, "melee"), 1, "styleless")
ok(LR.struck({kind = "disc", radius = 5}, 0, 0, 3, 3), "inside a disc")
ok(not LR.struck({kind = "ring", radius = 5}, 0, 0, 6, 0), "outside a ring")
ok(LR.struck({kind = "safe", radius = 5}, 0, 0, 6, 0) and not LR.struck({kind = "safe", radius = 5}, 0, 0, 1, 0), "safe zone")
for index = 1, LR.GRID * LR.GRID do
	local dx, dz = LR.cellOffset(index)
	eq(LR.cellAt(dx, dz), index, "cell " .. index .. " round trip")
end
eq(LR.cellAt(LR.GRID * LR.CELL, 0), nil, "off the lattice")
for step = 1, 20 do
	local cells = LR.tilePattern(4242, step, 13)
	eq(#cells, 13, "13 charged cells")
	local seen = {}
	for _, c in ipairs(cells) do ok(c >= 1 and c <= LR.GRID * LR.GRID and not seen[c], "distinct valid cell") seen[c] = true end
end
eq(table.concat(LR.tilePattern(7, 3, 10), ","), table.concat(LR.tilePattern(7, 3, 10), ","), "lattice deterministic")
ok(table.concat(LR.tilePattern(7, 3, 10), ",") ~= table.concat(LR.tilePattern(7, 4, 10), ","), "lattice changes per step")
eq(#LR.tilePattern(1, 1, 99), LR.GRID * LR.GRID - LR.MIN_SAFE, "lattice leaves safe cells")
local base = {member = true, party = 1, share = 0.01, alive = true, inside = true, lastHit = 100, now = 120}
ok(LR.credit(base), "solo credit with any damage")
local function credit(fields) local c = table.clone(base) for k, v in pairs(fields) do c[k] = v end return LR.credit(c) end
eq(select(2, credit({member = false})), "member", "not a member")
eq(select(2, credit({share = 0})), "share", "no damage")
eq(select(2, credit({alive = false})), "dead", "dead")
eq(select(2, credit({inside = false})), "away", "away")
eq(select(2, credit({lastHit = 50})), "idle", "idle")
eq(select(2, credit({party = 3, share = 0.12})), "share", "party leech under 40% of a fair share")
ok(credit({party = 3, share = 0.14}), "party member with a fair contribution")
eq(select(2, credit({party = 2, share = 0.25, ironman = true})), "ironman", "Ironman needs 30% in a party")
ok(credit({party = 1, share = 0.01, ironman = true}), "solo Ironman")
ok(LR.canEnter("Aerisca", {combat = 50, region = true, coins = 5000}), "can enter")
eq(select(2, LR.canEnter("Aerisca", {combat = 49, region = true, coins = 5000})), "level", "Combat gate")
eq(select(2, LR.canEnter("Aerisca", {combat = 50, region = false, coins = 5000})), "region", "region gate")
eq(select(2, LR.canEnter("Aerisca", {combat = 50, region = true, coins = 10})), "coins", "fee")
eq(select(2, LR.canEnter("Aerisca", {combat = 50, region = true, coins = 5000, busy = true})), "busy", "busy")
eq(select(2, LR.canEnter("Nope", {})), "boss", "unknown boss")
-- Migration and records.
do
	local m = LR.migrate({kc = {Aerisca = 3, Nope = 5, Bramblemaw = -2, Pyrewarden = 0 / 0}, pb = {Aerisca = 95.6, Nihlvar = 0, Nope = 3}, pbParty = {Aerisca = 7},
		got = {GalesongLongbow = 1, Blade = 4, ThornmawCleaver = "x"}, deaths = {Nihlvar = 2}, log = {{b = "Aerisca", s = 60, t = 5, n = 2, u = "Blade"}, "junk", {b = "Nope"}}})
	eq(m.kc.Aerisca, 3, "kc kept")
	eq(m.kc.Nope, nil, "unknown boss dropped")
	eq(m.kc.Bramblemaw, nil, "negative dropped")
	eq(m.kc.Pyrewarden, nil, "NaN dropped")
	eq(m.pb.Aerisca, 95, "pb floored")
	eq(m.pbParty.Aerisca, LR.MAX_PARTY, "pb party clamped")
	eq(m.pb.Nihlvar, nil, "zero pb dropped")
	eq(m.got.GalesongLongbow, 1, "unique kept")
	eq(m.got.Blade, nil, "non-unique dropped")
	eq(m.got.ThornmawCleaver, nil, "garbage count dropped")
	eq(m.deaths.Nihlvar, 2, "deaths kept")
	eq(#m.log, 1, "log sanitised")
	eq(m.log[1].u, nil, "log unique must be a lair unique")
	local fresh = LR.migrate(nil)
	ok(next(fresh.kc) == nil and #fresh.log == 0, "fresh state")
	local r1 = LR.record(fresh, "Aerisca", 120.4, 1, {StormFeather = 6}, 1000)
	eq(r1.kc, 1, "first kill")
	ok(r1.pb, "first kill is a best")
	eq(fresh.pb.Aerisca, 120, "best time")
	local r2 = LR.record(fresh, "Aerisca", 140, 2, {GalesongLongbow = 1, SirenletPet = 1}, 1100)
	eq(r2.kc, 2, "second kill")
	ok(not r2.pb, "slower is not a best")
	eq(#r2.uniques, 2, "two uniques recorded")
	eq(fresh.got.GalesongLongbow, 1, "unique counted")
	eq(fresh.log[1].u, "GalesongLongbow", "log shows the unique")
	local r3 = LR.record(fresh, "Aerisca", 90, 3, {}, 1200)
	ok(r3.pb and fresh.pbParty.Aerisca == 3, "faster party best")
	for i = 1, 20 do LR.record(fresh, "Bramblemaw", 60 + i, 1, {}, 2000 + i) end
	eq(#fresh.log, LR.KEEP_LOG, "log capped")
	eq(LR.migrate(fresh).kc.Bramblemaw, 20, "round trip")
	eq(LR.formatTime(83), "1:23", "time format")
end
print("PASS: " .. (checks - partA) .. " lair data/rule assertions.")

------------------------------------------------------------------------------
-- Part B: combat.server.lua Lairs section (pure logic through the harness).
------------------------------------------------------------------------------
local partB = checks
local Combat
load("combat.server.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, __CombatTestHarness = function(exports) Combat = exports end})
ok(Combat ~= nil, "combat harness")
local function world()
	local w = {clock = 100, rolls = {}, calls = {}, positions = {}, alive = {}, stats = {}, list = {}}
	function w.rng() if #w.rolls > 0 then return table.remove(w.rolls, 1) end return 0.5 end
	function w.player(id, pos, opts)
		opts = opts or {}
		local p = {Name = "P" .. id, UserId = id}
		w.positions[p] = pos
		w.alive[p] = true
		w.stats[p] = {stats = opts.stats or {damage = 400, strength = 100, critChance = 0, critDamage = 50, attackSpeed = 0},
			combatLevel = opts.combatLevel or 60, ironman = opts.ironman == true, prayer = opts.prayer, loadout = {style = "melee", levels = {}, supplies = {}}}
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
local center = Vector3.new(0, 0, 0)
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
local function swing(w, p, r)
	w.clock += 1
	return w.logic.attack(p, "attack", r.model)
end
do
	-- Membership, stances and the prayer check (Aerisca).
	local w = world()
	local L = w.logic
	local hero = w.player(101, Vector3.new(0, 0, 4), {prayer = {protect = "melee", offence = {}}})
	local stranger = w.player(202, Vector3.new(2, 0, 4))
	local r = L.lrRegister("F1", "Aerisca", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {101}, seed = 9, center = center, ground = 0})
	ok(r ~= nil and r.lair and r.maxHp == LR.Bosses.Aerisca.hp, "boss registered at solo health")
	eq(L.lrRegister("F1", "Aerisca", {Name = "again"}, center, {members = {101}}), nil, "one boss per fight")
	eq(L.lrRegister("F2", "Aerisca", {Name = "x"}, center, {members = {}}), nil, "a fight needs members")
	eq(Data.Monsters[r.id].xp, LR.Bosses.Aerisca.xp, "XP rate from the boss definition")
	local res, why = swing(w, stranger, r)
	eq(res, nil, "non-member refused")
	eq(why, "lair", "refusal reason")
	local hit = swing(w, hero, r)
	ok(hit and hit.damage > 0, "member strikes")
	eq(L.lrRecord("F1").dmg[101].damage, hit.damage, "damage kept per UserId")
	-- Basic attacks: melee stance into Ward of Fangs takes the prayer check.
	w.calls = {}
	r.nextHit = 0
	tickLogic(w, 0.25)
	local dmg = w.calls_of("damage", hero)
	eq(#dmg, 1, "a stance swing")
	eq(dmg[1].payload.style, "melee", "swing carries the stance")
	eq(dmg[1].payload.amount, math.floor(r.damage * LR.PRAYED), "prayed melee swing scaled")
	for _ = 1, 3 do r.nextHit = 0; tickLogic(w, 0.25) end
	eq(r.attackStyle, "ranged", "stance switched after four swings")
	local status = L.lrStatus("F1")
	eq(status.style, "ranged", "status style")
	eq(status.switchIn, 4, "four swings to the next switch")
	eq(status.nextStyle, "melee", "next stance")
	w.calls = {}
	r.nextHit = 0
	w.positions[hero] = Vector3.new(0, 0, 25) -- ranged stance strikes at range
	tickLogic(w, 0.25)
	dmg = w.calls_of("damage", hero)
	eq(#dmg, 1, "ranged swing at range")
	eq(dmg[1].payload.amount, r.damage, "unprayed ranged swing full")
	-- Lattice: the charged cell strikes, a safe cell does not, no style.
	r.nextSpecial = w.clock
	r.step = 0 -- squall first
	w.calls = {}
	local events = tickLogic(w, 0.25)
	local tg
	for _, e in ipairs(events) do if e.kind == "telegraph" then tg = e.telegraph end end
	ok(tg and tg.kind == "tiles" and #tg.cells == LR.Bosses.Aerisca.attacks.squall.count, "lattice telegraph")
	local charged, safe = tg.cells[1], nil
	for c = 1, LR.GRID * LR.GRID do if not tg.charged[c] then safe = c break end end
	local cx, cz = LR.cellOffset(charged)
	w.positions[hero] = Vector3.new(cx, 0, cz)
	local other = w.player(303, Vector3.new(0, 0, 0))
	r.members[303] = true
	local sx, sz = LR.cellOffset(safe)
	w.positions[other] = Vector3.new(sx, 0, sz)
	w.calls = {}
	r.nextHit = w.clock + 100
	tickLogic(w, tg.windup + 0.25)
	local tileHits = w.calls_of("damage", hero)
	ok(#tileHits >= 1 and tileHits[1].payload.style == nil, "charged cell struck, styleless")
	eq(tileHits[1].payload.amount, math.floor(r.damage * LR.Bosses.Aerisca.attacks.squall.mult), "lattice damage")
	eq(#w.calls_of("damage", other), 0, "safe cell spared")
	-- Phase 2 at 60%, enrage, timeout.
	r.hp = math.floor(r.maxHp * 0.55)
	events = tickLogic(w, 0.25)
	eq(r.phase, 2, "phase advanced")
	r.hp = r.maxHp
	tickLogic(w, 0.25)
	eq(r.phase, 2, "phases never go back")
	w.clock = r.enrageAt
	events = tickLogic(w, 0.25)
	ok(r.enraged and r.damage == math.floor(LR.Bosses.Aerisca.damage * LR.ENRAGE_DAMAGE), "enraged")
	w.clock = r.expires
	events = tickLogic(w, 0.25)
	local timeout = false
	for _, e in ipairs(events) do if e.kind == "timeout" then timeout = true end end
	ok(timeout and L.lrRecord("F1") == nil, "time limit ends the fight")
	eq(L.lrStatus("F1").result, "timeout", "timeout result")
	eq(#w.calls_of("kill"), 0, "no kill bridge")
	L.lrForget("F1")
	eq(L.lrStatus("F1").result, nil, "forgotten")
end
do
	-- Brood ward (Bramblemaw) and kill credit with a rejoin.
	local w = world()
	local L = w.logic
	local a = w.player(11, Vector3.new(0, 0, 4))
	local b = w.player(22, Vector3.new(0, 0, -4))
	local r = L.lrRegister("F3", "Bramblemaw", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {11, 22}, seed = 1, center = center})
	eq(r.party, 2, "party of two")
	eq(r.maxHp, LR.partyHp(LR.Bosses.Bramblemaw, 2), "party health")
	r.nextSpecial = w.clock
	local events = tickLogic(w, 0.25)
	local addEvent
	for _, e in ipairs(events) do if e.kind == "adds" then addEvent = e end end
	ok(addEvent and addEvent.add == "Thornspawn" and not addEvent.ordered and addEvent.count == 3, "brood call")
	local spawns = {}
	for i = 1, addEvent.count do spawns[i] = L.lrRegisterAdd(r, "Thornspawn", {Name = "add" .. i}, Vector3.new(i * 3, 2, 0), {}) end
	eq(L.lrRegisterAdd(r, "Thornspawn", {Name = "x"}, center, {}) ~= nil, true, "a fourth add fits the cap")
	eq(L.lrRegisterAdd(r, "Thornspawn", {Name = "y"}, center, {}), nil, "the add cap holds")
	ok(L.lrWarded(r), "warded")
	local raw = 1000
	local dealt = L.mitigate(r, raw, "magic", a)
	local plain = P.damageTaken(math.floor(raw * (1 + CS.weaknessBonus)), r.defense)
	eq(dealt, math.floor(plain * LR.WARD), "brood ward cuts boss damage")
	-- No more waves while the brood lives.
	r.nextSpecial = w.clock
	r.step = 0
	events = tickLogic(w, 0.25)
	for _, e in ipairs(events) do ok(e.kind ~= "adds", "waves never stack") end
	for _, add in ipairs(L.records()) do if add.lairAdd then add.hp = 1; w.positions[a] = add.position; w.clock += 1; L.attack(a, "attack", add.model) end end
	ok(not L.lrWarded(r), "brood slain, ward lifted")
	eq(#w.calls_of("kill"), 0, "adds never pay a kill")
	-- Damage by UserId survives a disconnect; the rejoined Player is credited.
	w.positions[a], w.positions[b] = Vector3.new(0, 0, 4), Vector3.new(0, 0, -4)
	swing(w, a, r)
	swing(w, b, r)
	local before = r.dmg[22].damage
	L.playerRemoving(b)
	local i = table.find(w.list, b)
	table.remove(w.list, i)
	local b2 = w.player(22, Vector3.new(0, 0, -4))
	eq(r.dmg[22].damage, before, "share kept across the rejoin")
	r.dmg[22].damage += r.maxHp * 0.3 -- both carried their weight
	r.dmg[11].damage += r.maxHp * 0.3
	r.hp = 5
	w.calls = {}
	local hit = swing(w, a, r)
	ok(hit.killed, "killed")
	local result = L.lrResult("F3")
	ok(result and result.result == "win" and result.credit[11].ok and result.credit[22].ok, "both credited")
	eq(result.party, 2, "party recorded")
	local xpFor = {}
	for _, c in ipairs(w.calls_of("combatXp")) do xpFor[c.player] = (xpFor[c.player] or 0) + 1; eq(c.payload.monster, "Bramblemaw", "boss XP names the boss") end
	ok(xpFor[a] and xpFor[b2], "damage XP to both (the rejoined player too)")
	eq(#w.calls_of("kill"), 0, "a lair boss never pays a kill")
	eq(L.lrRecord("F3"), nil, "fight cleared")
	ok(#L.records() == 0, "boss and adds unregistered")
	eq(L.liveCount(), 0, "marker count untouched")
end
do
	-- Leech and death credit.
	local w = world()
	local L = w.logic
	local a = w.player(1, Vector3.new(0, 0, 4))
	local leech = w.player(2, Vector3.new(0, 0, 6))
	local dead = w.player(3, Vector3.new(0, 0, 8))
	local r = L.lrRegister("F4", "Bramblemaw", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {1, 2, 3}, center = center})
	r.dmg[2] = {damage = r.maxHp * 0.05, lastHit = w.clock, xp = {melee = 10}}
	r.dmg[3] = {damage = r.maxHp * 0.3, lastHit = w.clock, xp = {melee = 10}}
	w.alive[dead] = false
	r.hp = 3
	r.dmg[1] = {damage = r.maxHp * 0.6, lastHit = w.clock, xp = {melee = r.maxHp * 0.6}}
	swing(w, a, r)
	local result = L.lrResult("F4")
	ok(result.credit[1].ok, "carrier credited")
	eq(result.credit[2].reason, "share", "leech refused")
	eq(result.credit[3].reason, "dead", "fallen refused")
end
do
	-- Ordered sigils (Pyrewarden): immune boss, order refusals.
	local w = world()
	local L = w.logic
	local a = w.player(7, Vector3.new(0, 0, 4))
	local r = L.lrRegister("F5", "Pyrewarden", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {7}, center = center})
	eq(r.attackStyle, "magic", "Pyrewarden opens with magic")
	r.nextSpecial = w.clock
	local events = tickLogic(w, 0.25)
	local addEvent
	for _, e in ipairs(events) do if e.kind == "adds" then addEvent = e end end
	ok(addEvent and addEvent.ordered and addEvent.add == "ForgeSigil", "sigils called")
	local sigils = {}
	for i = 1, addEvent.count do sigils[i] = L.lrRegisterAdd(r, "ForgeSigil", {Name = "s" .. i}, Vector3.new(i * 2, 2, 0), {order = i}) end
	ok(L.lrSealed(r) and L.lrNextOrder(r) == 1, "sealed, sigil I next")
	w.positions[a] = Vector3.new(0, 0, 4)
	local res, why = swing(w, a, r)
	ok(res == nil and why == "sealed", "boss immune while sealed")
	w.positions[a] = sigils[2].position
	res, why = swing(w, a, sigils[2])
	ok(res == nil and why == "order", "sigil II refused first")
	eq(#L.multishotTargets(a, sigils[1], sigils[1].position, 40, 2), 0, "multishot never strikes a sigil out of order or the sealed boss")
	for i = 1, 3 do
		sigils[i].hp = 1
		w.positions[a] = sigils[i].position
		res = swing(w, a, sigils[i])
		ok(res and res.killed, "sigil " .. i .. " broken in order")
	end
	ok(not L.lrSealed(r), "seal broken")
	ok(L.lrStatus("F5").order == nil, "no sigil left")
	ok(L.think(sigils[1]).kind == "dead", "a dead sigil stays dead")
	w.positions[a] = Vector3.new(0, 0, 4)
	ok(swing(w, a, r) ~= nil, "boss can be struck again")
	-- Disc telegraphs on a member, ring around the boss; styleless.
	r.step = 1 -- next: slag (disc)
	r.nextSpecial = w.clock
	local evs = tickLogic(w, 0.25)
	local disc
	for _, e in ipairs(evs) do if e.kind == "telegraph" then disc = e.telegraph end end
	ok(disc and disc.kind == "disc" and disc.victim == a, "disc on the member")
	w.positions[a] = Vector3.new(30, 0, 30) -- dodge out of the disc
	w.calls = {}
	r.nextHit = w.clock + 100
	tickLogic(w, disc.windup + 0.25)
	eq(#w.calls_of("damage", a), 0, "a dodged telegraph misses")
	-- Despawn removes everything silently.
	L.lrDespawn("F5")
	eq(#L.records(), 0, "despawned")
	eq(L.lrStatus("F5").alive, false, "no fight")
end
do
	-- Nihlvar: weakness turns by phase, all three stances, a paused fight holds.
	local w = world()
	local L = w.logic
	local a = w.player(9, Vector3.new(0, 0, 4))
	local r = L.lrRegister("F6", "Nihlvar", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {9}, center = center})
	eq(r.weakness, "magic", "phase 1 weakness")
	r.hp = math.floor(r.maxHp * 0.5)
	tickLogic(w, 0.25)
	eq(r.weakness, "ranged", "phase 2 weakness")
	local m1 = P.styleModifier("ranged", r)
	ok(m1 > 1, "ranged now deals bonus damage")
	r.hp = math.floor(r.maxHp * 0.2)
	tickLogic(w, 0.25)
	eq(r.weakness, "melee", "phase 3 weakness")
	-- Nobody inside: specials hold.
	w.positions[a] = Vector3.new(500, 0, 500)
	r.nextSpecial = w.clock
	local evs = tickLogic(w, 3)
	for _, e in ipairs(evs) do ok(e.kind ~= "telegraph" and e.kind ~= "adds", "a paused fight holds its rotation") end
	ok(L.lrStatus("F6").inside == 0, "nobody inside")
	-- Instance cap.
	for i = 1, LR.MAX_INSTANCES - 1 do ok(L.lrRegister("C" .. i, "Bramblemaw", {Name = "b" .. i}, Vector3.new(i * 400, 3, 0), {members = {1000 + i}}) ~= nil, "instance " .. i) end
	eq(L.lrRegister("C9", "Bramblemaw", {Name = "over"}, center, {members = {77}}), nil, "instance cap holds")
	ok(L.lrCount() <= LR.MAX_INSTANCES * (1 + LR.MAX_ADDS), "creature cap")
end
do
	-- Polish: Hollow Sunder in combat: bosses only, stronger while warded, never on adds.
	local w = world()
	local L = w.logic
	local edge = w.player(31, Vector3.new(0, 0, 4))
	local plainHero = w.player(32, Vector3.new(0, 0, -4))
	w.stats[edge].loadout.weapon = "HollowcrownEdge"
	local r = L.lrRegister("S1", "Bramblemaw", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {31, 32}, seed = 1, center = center})
	local raw = P.meleeDamage(w.stats[edge].stats, function() return 0.5 end)
	local sp = Data.Items.HollowcrownEdge.special
	local hit = swing(w, edge, r)
	eq(hit.damage, (L.mitigate(r, math.floor(raw * (1 + sp.boss)), "melee", edge)), "Sunder adds its boss bonus")
	ok(hit.sunder == true, "the hit is flagged Sunder")
	local base = swing(w, plainHero, r)
	eq(base.damage, (L.mitigate(r, raw, "melee", plainHero)), "no Sunder without the Edge")
	ok(hit.damage > base.damage and not base.sunder, "the Edge out-hits the same stats on a boss")
	local add = L.lrRegisterAdd(r, "Thornspawn", {Name = "add1"}, Vector3.new(3, 2, 0), {})
	ok(L.lrWarded(r), "brood ward up")
	local warded = swing(w, edge, r)
	eq(warded.damage, (L.mitigate(r, math.floor(raw * (1 + sp.warded)), "melee", edge)), "Sunder cuts harder through a ward")
	add.hp = add.maxHp
	local onAdd = swing(w, edge, add)
	local addPlain = swing(w, plainHero, add)
	eq(onAdd.damage, addPlain.damage, "no Sunder on adds")
	ok(not onAdd.sunder, "an add hit is not flagged")
	eq(L.sunderMult("HollowcrownEdge", {worldBoss = true, adds = {}}), 1 + sp.boss, "world bosses count")
	eq(L.sunderMult("HollowcrownEdge", {worldBoss = true, adds = {[{}] = true}}), 1 + sp.warded, "a world boss add wave counts as a ward")
	eq(L.sunderMult("HollowcrownEdge", {boss = true}), 1 + sp.boss, "slayer bosses count")
	eq(L.sunderMult("HollowcrownEdge", {id = "BramblebackBoar"}), 1, "ordinary monsters do not")
end
print("PASS: " .. (checks - partB) .. " lair combat assertions.")

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
local storage = {} -- ServerStorage children by name (the lair doubles, then the real lairs script)
local livePlayers = {}
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return livePlayers end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) if name == "AetherTrails" then return markers.AetherTrails end return storage[name] end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "lairs-test" end},
	RunService = {IsStudio = function() return false end, Heartbeat = signal()},
}
local serverObjects = {}
local journalClosers = {} -- the journal's BindToClose (Part D fires it last)
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
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 10, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Name = "Hero" .. id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
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
local function altarPrompt(boss, at)
	local def = LR.Bosses[boss]
	local base = {CFrame = CFrame.new(at or Vector3.new(0, 10, 0))}
	local q = {Enabled = true, MaxActivationDistance = 9, attrs = {IsleAction = "lairEnter", IsleItem = boss, IsleRegion = def.region}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q)
	advance(2)
	p.last = nil
	p.root.Position = q:FindFirstAncestorWhichIsA().CFrame.Position
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
local function op(p, payload) advance(0.1) return bridge.OnInvoke("lair", p, payload) end
-- A scripted IsleLairs (Part D runs the real one).
local lairCalls = {}
local lairReply = {ok = true, fight = "T1", mode = "open"}
storage.IsleLairs = {Invoke = function(_, opName, who, arg)
	if opName == "depart" or opName == "holds" then return nil end -- the journal's close()/load hooks (Part D runs the real ones)
	table.insert(lairCalls, {op = opName, player = who, arg = arg})
	if opName == "enter" then return lairReply end
	if opName == "leave" then return {ok = true} end
	return nil
end}
local function fighter(id, mutate)
	return seeded(id, function(p)
		p.xp.Combat = X[35]; p.xp.Woodcutting = X[12]; p.coins = 5000
		if mutate then mutate(p) end
	end)
end
local rookie = player(9201)
local s0 = cmd(rookie, "state")
ok(type(s0.lairs) == "table" and next(s0.lairs.kc) == nil and s0.lairs.active == "", "fresh snapshot lairs")
ok(has(use(rookie, altarPrompt("Pyrewarden")).message, "Combat 70"), "Combat gate")
ok(has(use(rookie, altarPrompt("Bramblemaw")).message, "Woodcutting"), "region gate (prompt IsleRegion)")
ok(has(cmd(rookie, "lairEnter", "Bramblemaw").message, "altar"), "the verb needs the altar prompt")
local hunter = fighter(9202, function(p) p.coins = 100 end)
ok(has(use(hunter, altarPrompt("Bramblemaw")).message, "costs 300"), "fee gate")
eq(#lairCalls, 0, "no instance asked for while refused")
hunter = fighter(9202)
hunter.attrs.MinigameGame = "Siege"
ok(has(use(hunter, altarPrompt("Bramblemaw")).message, "Finish"), "busy in a minigame")
hunter.attrs.MinigameGame = ""
lairReply = {ok = false, reason = "capacity"}
local full = use(hunter, altarPrompt("Bramblemaw"))
ok(has(full.message, "in use"), "instance cap message")
eq(full.coins, 5000, "no fee when refused")
lairReply = {ok = true, fight = "T1", mode = "open"}
local entered = use(hunter, altarPrompt("Bramblemaw"))
ok(has(entered.message, "Thornroot Hollow") and has(entered.message, "-300"), "altar opens the lair: " .. tostring(entered.message))
eq(entered.coins, 4700, "fee paid")
eq(lairCalls[#lairCalls].op, "enter", "IsleLairs enter")
eq(lairCalls[#lairCalls].arg, "Bramblemaw", "boss passed")
-- Rewards.
eq(op(hunter, {action = "kill", boss = "Bramblemaw", fight = "WRONG", seconds = 80}).reason, "entry", "a fight never entered pays nothing")
eq(op(hunter, {action = "kill", boss = "Aerisca", fight = "T1", seconds = 80}).reason, "entry", "boss must match the entry")
eq(op(hunter, {action = "refund", boss = "Bramblemaw", fight = "T1"}).ok, true, "refund before a reward")
eq(cmd(hunter, "state").coins, 5000, "fee refunded")
eq(op(hunter, {action = "refund", boss = "Bramblemaw", fight = "T1"}).reason, "entry", "refund once")
use(hunter, altarPrompt("Bramblemaw"))
defaultRoll = 0 -- every loot row hits at its minimum
local paid = op(hunter, {action = "kill", boss = "Bramblemaw", fight = "T1", seconds = 83.6, party = 1})
defaultRoll = 0.999
ok(paid.ok and paid.kc == 1 and paid.pb == true, "kill paid")
eq(paid.coins, LR.Bosses.Bramblemaw.coinRange.min, "coin roll")
eq(paid.drops.ThornmawCleaver, 1, "weapon unique rolled")
eq(paid.drops.BramblingPet, 1, "pet rolled")
eq(#paid.uniques, 3, "three uniques recorded")
eq(op(hunter, {action = "kill", boss = "Bramblemaw", fight = "T1", seconds = 80}).reason, "paid", "paid once per fight")
eq(op(hunter, {action = "refund", boss = "Bramblemaw", fight = "T1"}).reason, "paid", "never refunded after a reward")
local s1 = cmd(hunter, "state")
eq(s1.lairs.kc.Bramblemaw, 1, "kill count")
eq(s1.lairs.pb.Bramblemaw, 83, "personal best")
eq(s1.lairs.got.ThornmawCleaver, 1, "unique log")
eq(s1.items.ThornmawCleaver, 1, "weapon in the satchel")
eq(s1.items.BeastHide, LR.Loot.Bramblemaw[1].min, "resources granted")
eq(s1.coins, 4700 + LR.Bosses.Bramblemaw.coinRange.min, "coins granted")
-- Bridge "kill" refuses lair creatures (they pay only through op "lair").
eq(bridge.OnInvoke("kill", hunter, {monster = "Bramblemaw"}), nil, "kill op refuses a lair boss")
eq(bridge.OnInvoke("kill", hunter, {monster = "Thornspawn"}), nil, "kill op refuses a lair add")
-- Death closes the entry and counts.
use(hunter, altarPrompt("Bramblemaw"))
eq(op(hunter, {action = "end", boss = "Bramblemaw", fight = "T1", result = "died"}).ok, true, "end")
eq(cmd(hunter, "state").lairs.deaths.Bramblemaw, 1, "death counted")
eq(op(hunter, {action = "kill", boss = "Bramblemaw", fight = "T1"}).reason, "entry", "an ended entry pays nothing")
-- The arena exit verb.
local before = #lairCalls
cmd(hunter, "lairLeave")
eq(lairCalls[before + 1].op, "leave", "lairLeave asks IsleLairs")
-- Collection Log credit through collect(); persistence and migration.
leave(hunter)
local saved = data["p9202"].profile
eq(saved.lairs.kc.Bramblemaw, 1, "kill count saved")
eq(saved.colLog.counts.ThornmawCleaver, 1, "Collection Log credits the weapon")
eq(saved.colLog.counts.ThornheartLocket, 1, "Collection Log credits the accessory")
eq(saved.colLog.counts.BramblingPet, 1, "Collection Log credits the pet")
saved.lairs.kc.Nope = 4
saved.lairs.got.Blade = 2
hunter = player(9202)
local back = cmd(hunter, "state")
eq(back.lairs.kc.Bramblemaw, 1, "kill count survives a rejoin")
eq(back.lairs.kc.Nope, nil, "unknown boss sanitised")
eq(back.lairs.got.Blade, nil, "non-unique sanitised")
local old = seeded(9203, function(p) p.lairs = "corrupt" end)
ok(next(cmd(old, "state").lairs.kc) == nil, "old saves migrate")
-- Not live: "sync" so lairs.server.lua resends.
eq(bridge.OnInvoke("lair", {UserId = 1, Parent = true, GetAttribute = function() return nil end}, {action = "kill"}).reason, "sync", "an unopened journal answers sync")
-- QC fixes, journal side.
-- (#4) Damage XP on a party-scaled lair boss caps at the fight's real health (combat sends maxHp).
do
	local nih = LR.Bosses.Nihlvar
	local function gain(payload)
		local before = cmd(hunter, "state").xp.Combat
		payload.style, payload.monster = "melee", "Nihlvar"
		bridge.OnInvoke("combatXp", hunter, payload)
		return cmd(hunter, "state").xp.Combat - before
	end
	within(gain({damage = nih.hp * 1.5}), nih.xp - 1, nih.xp + 1, "without maxHp the cap is the base health")
	within(gain({damage = nih.hp * 1.5, maxHp = LR.partyHp(nih, 3)}), nih.xp * 1.5 - 1, nih.xp * 1.5 + 1, "a party carry is paid past the base health")
	within(gain({damage = nih.hp * 9, maxHp = 1e12}), nih.xp * LR.partyHp(nih, 3) / nih.hp - 1, nih.xp * LR.partyHp(nih, 3) / nih.hp + 1, "maxHp clamps to a party of three")
end
-- (#2) The open entry is saved on the profile (owed) and cleared when it settles.
lairReply = {ok = true, fight = "T7", mode = "open"}
use(hunter, altarPrompt("Bramblemaw"))
leave(hunter)
local owedSaved = data["p9202"].profile.lairs.owed
ok(owedSaved ~= nil and owedSaved.fight == "T7" and owedSaved.fee == LR.Bosses.Bramblemaw.fee, "the open entry is saved as owed")
local coinsAway = data["p9202"].profile.coins
hunter = player(9202)
eq(cmd(hunter, "state").coins, coinsAway + LR.Bosses.Bramblemaw.fee, "an owed entry no fight holds is refunded at load")
leave(hunter)
eq(data["p9202"].profile.lairs.owed, nil, "owed cleared once refunded")
hunter = player(9202)
eq(cmd(hunter, "state").coins, coinsAway + LR.Bosses.Bramblemaw.fee, "the owed refund is applied once (idempotent)")
local seededOwed = seeded(9204, function(prof) prof.coins = 10; prof.lairs = {owed = {fight = "Elsewhere", boss = "Aerisca", fee = 999999}} end)
eq(cmd(seededOwed, "state").coins, 10 + LR.Bosses.Aerisca.fee, "a forged owed fee is clamped to the boss's fee")
-- (#12) A member removed while offline closes the entry by UserId; a forfeit is not refunded at load.
lairReply = {ok = true, fight = "T8", mode = "open"}
use(hunter, altarPrompt("Bramblemaw"))
leave(hunter)
local coinsForfeit = data["p9202"].profile.coins
eq(bridge.OnInvoke("lair", 9202, {action = "end", boss = "Bramblemaw", fight = "T8", result = "left"}).ok, true, "offline end by UserId")
hunter = player(9202)
eq(cmd(hunter, "state").coins, coinsForfeit, "a forfeited entry is not refunded at load")
eq(op(hunter, {action = "kill", boss = "Bramblemaw", fight = "T8"}).reason, "entry", "the offline close cleared the entry")
-- (#3) A disconnect that dodges a death pays the purse-coin death penalty and counts the death.
lairReply = {ok = true, fight = "T9", mode = "open"}
use(hunter, altarPrompt("Bramblemaw"))
local purse = cmd(hunter, "state").coins
local deaths0 = cmd(hunter, "state").lairs.deaths.Bramblemaw or 0
local fled = op(hunter, {action = "end", boss = "Bramblemaw", fight = "T9", result = "died", penalty = true})
eq(fled.lost, math.floor(purse * 0.10), "10% purse-coin death penalty")
local afterFlee = cmd(hunter, "state")
eq(afterFlee.coins, purse - math.floor(purse * 0.10), "penalty applied")
eq(afterFlee.lairs.deaths.Bramblemaw, deaths0 + 1, "the dodged death is counted")
print("PASS: " .. (checks - partC) .. " lair server assertions.")

------------------------------------------------------------------------------
-- Part D: lairs.server.lua (instances) on Part C's real bridge, with a combat
-- double built from the real combat logic (IsleLairCombat ops).
------------------------------------------------------------------------------
local partD = checks
local wsp = roblox.Instance.new("Workspace")
local islands = roblox.Instance.new("Folder")
islands.Name = "Islands"
islands.Parent = wsp
local altarAt = {}
for i, id in ipairs(LR.Order) do
	local a = roblox.Instance.new("Part")
	a.Name = "Anchor_Waypoint_Lair_" .. id
	altarAt[id] = Vector3.new(i * 100, 10, 50)
	a.CFrame = CFrame.new(altarAt[id])
	a.Parent = islands
end
-- Combat double: the real Lairs logic, damage/stats/XP through the real bridge.
local fightClock = 0
local spawnFails = false
local registerThenFail = false -- combat registers the boss, then its view fails (QC #8)
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
local spawned = {}
storage.IsleLairCombat = {Invoke = function(_, opName, payload)
	if opName == "spawn" then
		if spawnFails then return {ok = false, reason = "build"} end
		local r = combatLogic.lrRegister(payload.fight, payload.boss, {Name = payload.boss}, payload.center + Vector3.new(0, 3, 11),
			{members = payload.members, party = payload.party, seed = payload.seed, center = payload.center, ground = payload.center.Y})
		if not r then return {ok = false, reason = "register"} end
		if registerThenFail then error("view failed after registration") end
		spawned[payload.fight] = {record = r, tiles = payload.tiles}
		return {ok = true}
	elseif opName == "status" then
		return combatLogic.lrStatus(payload.fight)
	elseif opName == "despawn" then
		combatLogic.lrDespawn(payload.fight)
		return {ok = true}
	end
	return nil
end}
storage.IsleLairs = nil
local closers = {}
local lrEnv = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function(_, f) table.insert(closers, f) end},
	workspace = wsp,
	require = function(target) assert(target == markers.AetherData, "lairs require shared data only") return Data end,
	Instance = {new = function(class)
		if class == "BindableFunction" then
			return setmetatable({ClassName = class}, {__newindex = function(t, k, v) rawset(t, k, v); if k == "Parent" then storage[t.Name] = t end end})
		end
		return roblox.Instance.new(class)
	end},
	Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum,
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	Random = {new = function() return {NextNumber = function() return 0.25 end} end},
	warn = function() end,
}
local Lair
lrEnv.__LairsHarness = function(api) Lair = api end
load("lairs.server.lua", lrEnv)
ok(Lair ~= nil and storage.IsleLairs ~= nil and type(storage.IsleLairs.OnInvoke) == "function", "IsleLairs published")
storage.IsleLairs.Invoke = function(self, ...) return self.OnInvoke(...) end
local instances = wsp:FindFirstChild("LairInstances")
ok(instances ~= nil, "instance folder")
eq(wsp:GetAttribute("LairInstances"), "0/" .. LR.MAX_INSTANCES, "instance gauge")
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
	for pair in tostring(p.attrs.LairHud or ""):gmatch("[^;]+") do local k, v = pair:match("^(%w+)=(.*)$"); if k then out[k] = v end end
	return out
end
local function partsIn(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	return n
end
local function bossOf(p)
	for fight, s in pairs(spawned) do
		local r = combatLogic.lrRecord(fight)
		if r and r.members[p.UserId] then return r, fight end
	end
	return nil
end
local function finish(p, r)
	-- Every member carried a fair share; the killing blow lands from beside the boss.
	for uid in pairs(r.members) do
		r.dmg[uid] = r.dmg[uid] or {damage = 0, xp = {}}
		r.dmg[uid].damage += r.maxHp * 0.45
		r.dmg[uid].lastHit = clock
	end
	r.hp = 1
	p.root.Position = r.position + Vector3.new(0, 0, 4)
	advance(1)
	local res, why = combatLogic.attack(p, "attack", r.model)
	assert(res and res.killed, "killing blow: " .. tostring(why) .. " hp " .. tostring(p.humanoid.Health))
end
local function solo(id, boss, mutate)
	local p = fighter(id, function(prof)
		prof.xp.Combat = X[90]; prof.xp.Woodcutting = X[20]; prof.coins = 50000
		prof.questsDone = {CrownOfTempest = true}; prof.questCompleted = 10
		if mutate then mutate(prof) end
	end)
	p.humanoid.TakeDamage = function(self, n) self.taken = (self.taken or 0) + n end -- hits are recorded; only the death test fells a fighter
	return p
end

-- 1. Open, warmup, rise, kill, reward, exit, teardown.
local hero = solo(9301, "Bramblemaw")
local coins0 = cmd(hero, "state").coins
local opened = use(hero, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
ok(has(opened.message, "Thornroot Hollow"), "altar opens a real instance: " .. tostring(opened.message))
eq(opened.coins, coins0 - LR.Bosses.Bramblemaw.fee, "fee paid")
local arena = instances:GetChildren()[1]
ok(arena ~= nil and arena:GetAttribute("LairBoss") == "Bramblemaw", "arena built on demand")
eq(partsIn(arena), 14, "Bramblemaw arena: 14 parts (floor, 4 walls, 4 pillars, 4 braziers, exit)")
local exitPrompt = arena:FindFirstChild("Lair exit"):FindFirstChildOfClass("ProximityPrompt")
ok(exitPrompt ~= nil and exitPrompt:GetAttribute("IsleAction") == "lairLeave", "exit prompt")
eq(wsp:GetAttribute("LairInstances"), "1/" .. LR.MAX_INSTANCES, "gauge counts the instance")
local before = hero.attrs.FastTravelAt
tick(0.25)
ok(hero.attrs.FastTravelAt ~= nil and hero.attrs.FastTravelAt ~= before, "teleport in sets FastTravelAt")
eq(hero.attrs.LairBoss, "Bramblemaw", "LairBoss attribute")
local arenaCenter = Vector3.new(3600, 300, -3600)
ok((hero.root.Position - arenaCenter).Magnitude < 40, "inside the arena")
eq(hud(hero).state, "warmup", "HUD warmup")
ok(tonumber(hud(hero).rise) > 0, "HUD countdown")
ok(has(cmd(hero, "state").message, "") and cmd(hero, "state").lairs.active == "Bramblemaw", "snapshot shows the active lair")
ok(has(use(hero, altarPrompt("Bramblemaw", altarAt.Bramblemaw)).message, "Finish"), "cannot open a second lair")
hero.root.Position = arenaCenter + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
local r, fight = bossOf(hero)
ok(r ~= nil, "the boss rises")
eq(hud(hero).state, "fight", "HUD fight")
ok(hud(hero).hp ~= nil and hud(hero).phase == "1/2", "HUD health and phase")
ok(has(hero.attrs.LairNotice, "rises"), "rise notice")
hero.root.Position = r.position + Vector3.new(0, 0, 4)
tick(3)
ok((hero.humanoid.taken or 0) > 0, "the boss strikes through the real bridge")
finish(hero, r)
tick(0.5)
eq(hud(hero).state, "won", "HUD won")
local won = cmd(hero, "state")
eq(won.lairs.kc.Bramblemaw, 1, "kill count through the real bridge")
ok(won.lairs.pb.Bramblemaw ~= nil, "personal best recorded")
ok(has(hero.attrs.LairNotice, "slain"), "kill notice")
local mid = hero.attrs.FastTravelAt
tick(LR.EXIT_SECONDS + 0.5)
ok(hero.attrs.FastTravelAt ~= mid, "teleport out sets FastTravelAt")
ok((hero.root.Position - altarAt.Bramblemaw).Magnitude < 6, "returned to the altar")
eq(hero.attrs.LairBoss, "", "LairBoss cleared")
eq(hero.attrs.LairHud, "", "HUD cleared")
eq(#instances:GetChildren(), 0, "arena destroyed")
eq(arena.Parent, nil, "arena model gone")
eq(#combatLogic.records(), 0, "creatures cleaned up")
eq(wsp:GetAttribute("LairInstances"), "0/" .. LR.MAX_INSTANCES, "slot freed")
eq(op(hero, {action = "kill", boss = "Bramblemaw", fight = fight}).reason, "paid", "the reward was paid once")

-- 2. Death inside: out of the fight, home safe, death counted; the instance closes.
use(hero, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tick(0.25)
hero.root.Position = arenaCenter + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
ok(bossOf(hero) ~= nil, "second fight")
hero.humanoid.Health = 0
tick(0.5)
eq(hero.attrs.LairBoss, "", "a fallen member leaves the fight")
ok(has(hero.attrs.LairNotice, "fell") or has(hero.attrs.LairNotice, "victorious"), "fall notice")
eq(cmd(hero, "state").lairs.deaths.Bramblemaw, 1, "death counted")
eq(#instances:GetChildren(), 0, "an emptied fight closes")
eq(#combatLogic.records(), 0, "its creatures go")
hero.humanoid.Health = 100

-- 3. Disconnect and rejoin within the window keeps the fight and the share.
use(hero, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tick(0.25)
hero.root.Position = arenaCenter + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
r, fight = bossOf(hero)
r.dmg[9301] = {damage = r.maxHp * 0.5, lastHit = clock, xp = {melee = 100}}
leave(hero)
tick(LR.REJOIN_SECONDS - 20)
ok(combatLogic.lrRecord(fight) ~= nil, "the fight waits for the rejoin")
eq(#instances:GetChildren(), 1, "arena kept while away")
local hero2 = player(9301)
hero2.humanoid.TakeDamage = function() end
tick(0.5)
ok((hero2.root.Position - arenaCenter).Magnitude < 40, "rejoined into the arena")
eq(hero2.attrs.LairBoss, "Bramblemaw", "rejoined LairBoss")
ok(has(hero2.attrs.LairNotice, "kept"), "rejoin notice")
eq(combatLogic.lrRecord(fight).dmg[9301].damage, r.maxHp * 0.5, "share kept")
finish(hero2, combatLogic.lrRecord(fight))
tick(0.5)
eq(cmd(hero2, "state").lairs.kc.Bramblemaw, 2, "the rejoined member is paid")
tick(LR.EXIT_SECONDS + 0.5)
eq(#instances:GetChildren(), 0, "closed after the kill")

-- 4. Disconnect without returning: the fight ends cleanly after the window.
use(hero2, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tick(0.25)
hero2.root.Position = arenaCenter + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
leave(hero2)
tick(LR.REJOIN_SECONDS + 2)
eq(#instances:GetChildren(), 0, "an abandoned fight is torn down")
eq(#combatLogic.records(), 0, "its creatures go")
local hero3 = player(9301)
hero3.humanoid.TakeDamage = function() end
tick(0.5)
ok(hero3.attrs.LairBoss ~= "Bramblemaw", "a late rejoin stays outside")

-- 5. Walking (teleporting) away ends a member's fight.
use(hero3, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tick(0.25)
hero3.root.Position = arenaCenter + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
hero3.root.Position = Vector3.new(0, 10, 0)
tick(LR.AWAY_SECONDS + 1)
eq(hero3.attrs.LairBoss, "", "away too long: left")
eq(#instances:GetChildren(), 0, "closed")

-- 6. The exit prompt (lairLeave) forfeits and returns to the altar.
use(hero3, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tick(0.25)
hero3.root.Position = arenaCenter + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
local left = cmd(hero3, "lairLeave")
ok(has(left.message, "leave the lair"), "lairLeave message")
ok((hero3.root.Position - altarAt.Bramblemaw).Magnitude < 6, "leave returns to the altar")
tick(0.5)
eq(#instances:GetChildren(), 0, "a forfeited solo fight closes")

-- 7. Crew join during the warmup; party health; tile lattice parts (Aerisca).
local hostP = solo(9311, "Aerisca", function(prof) prof.questCompleted = 10 end)
local mate = solo(9312, "Aerisca")
local stranger = solo(9313, "Aerisca")
hostP.attrs.CoopId, mate.attrs.CoopId, stranger.attrs.CoopId = "crew-1", "crew-1", "crew-2"
ok(has(use(hostP, altarPrompt("Aerisca", altarAt.Aerisca)).message, "Squallglass Eyrie"), "host opens Aerisca")
ok(has(use(mate, altarPrompt("Aerisca", altarAt.Aerisca)).message, "join"), "crewmate joins")
ok(has(use(stranger, altarPrompt("Aerisca", altarAt.Aerisca)).message, "opens"), "a stranger gets their own instance")
eq(#instances:GetChildren(), 2, "two instances")
local eyrie
for _, m in ipairs(instances:GetChildren()) do if m:GetAttribute("LairBoss") == "Aerisca" and partsIn(m) == 38 then eyrie = m end end
ok(eyrie ~= nil, "Aerisca arena: 38 parts (25 lattice tiles)")
tick(0.25)
local hostArena = Lair.byUser[9311]
ok(Lair.byUser[9312] == hostArena and Lair.byUser[9313] ~= hostArena, "crew share an instance")
for _, p in ipairs({hostP, mate}) do p.root.Position = hostArena.center + Vector3.new(0, 3, -20) end
stranger.root.Position = Lair.byUser[9313].center + Vector3.new(0, 3, -20)
tick(LR.WARMUP)
local rr = bossOf(hostP)
ok(rr ~= nil and rr.party == 2 and rr.maxHp == LR.partyHp(LR.Bosses.Aerisca, 2), "party health at the rise")
ok(spawned[rr.fight].tiles ~= nil and #spawned[rr.fight].tiles == LR.GRID * LR.GRID, "tile parts handed to combat")
finish(hostP, rr)
tick(0.5)
eq(cmd(hostP, "state").lairs.kc.Aerisca, 1, "host paid")
eq(cmd(mate, "state").lairs.kc.Aerisca, 1, "crewmate paid")
tick(LR.EXIT_SECONDS + 0.5)
eq(#instances:GetChildren(), 1, "the stranger's instance remains")
cmd(stranger, "lairLeave")
tick(0.5)
eq(#instances:GetChildren(), 0, "all closed")

-- 8. Instance cap; a boss that cannot rise refunds every fee.
local crowd = {}
for i = 1, LR.MAX_INSTANCES do
	crowd[i] = solo(9400 + i, "Bramblemaw")
	use(crowd[i], altarPrompt("Bramblemaw", altarAt.Bramblemaw))
end
eq(#instances:GetChildren(), LR.MAX_INSTANCES, "instances up to the cap")
local late = solo(9499, "Bramblemaw")
local refused = use(late, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
ok(has(refused.message, "in use"), "the cap refuses")
eq(refused.coins, 50000, "no fee when refused")
tick(0.25)
for i = 1, LR.MAX_INSTANCES do crowd[i].root.Position = Lair.byUser[crowd[i].UserId].center + Vector3.new(0, 3, -20) end
spawnFails = true
tick(LR.WARMUP)
spawnFails = false
eq(#instances:GetChildren(), 0, "failed rises close their instances")
eq(cmd(crowd[1], "state").coins, 50000, "fee refunded when the boss cannot rise")
ok(has(crowd[1].attrs.LairNotice, "returned"), "refund notice")

-- 9. Shutdown refunds unfinished fights.
use(late, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tick(0.25)
eq(cmd(late, "state").coins, 50000 - LR.Bosses.Bramblemaw.fee, "fee taken")
for _, f in ipairs(closers) do f() end
eq(cmd(late, "state").coins, 50000, "shutdown refund")
eq(#instances:GetChildren(), 0, "shutdown tears down")
-- QC fixes, instance side.
local function arenaOf(p) return Lair.byUser[p.UserId] or Lair.stash[p.UserId] end
local function enterInside(p, boss)
	use(p, altarPrompt(boss, altarAt[boss]))
	tick(0.25)
	local f = arenaOf(p)
	p.root.Position = f.center + Vector3.new(0, 3, -20)
	return f
end
local realBridgeInvoke = storage.IsleBridge.Invoke
local function failLair(action) -- the journal answers "sync" to this lair action
	storage.IsleBridge.Invoke = function(self, opName, who, payload)
		if opName == "lair" and type(payload) == "table" and payload.action == action then return {ok = false, reason = "sync"} end
		return realBridgeInvoke(self, opName, who, payload)
	end
end
local function healBridge() storage.IsleBridge.Invoke = realBridgeInvoke end

-- 10. (#1) A rejoin owns the respawn: LairRejoin makes the home landing stand
-- aside, and a racing move is undone during the re-check; the member stays in.
local rj = solo(9501, "Bramblemaw")
local fRj = enterInside(rj, "Bramblemaw")
tick(LR.WARMUP)
ok(bossOf(rj) ~= nil, "rejoin fight rises")
leave(rj)
tick(1)
local rj2 = player(9501)
rj2.humanoid.TakeDamage = function() end
eq(rj2.attrs.LairRejoin, true, "LairRejoin set while lairs owns the respawn")
rj2.root.Position = Vector3.new(0, 10, 0) -- the home landing wins the race
tick(0.5)
ok((rj2.root.Position - fRj.center).Magnitude < 40, "re-checked back into the arena")
tick(LR.REJOIN_VERIFY + LR.AWAY_SECONDS)
eq(rj2.attrs.LairRejoin, nil, "LairRejoin released after the re-check")
ok(Lair.byUser[9501] == fRj and rj2.attrs.LairBoss == "Bramblemaw", "still a member (never removed as left)")
ok(has(fs.readFile("world.server.lua"), 'player.Character==character and not player:GetAttribute("LairRejoin")'), "world home landing skips a lair rejoin")

-- 11. (#3) Health survives a disconnect; a disconnect dodging a death is a death.
rj2.humanoid.Health = 30
tick(5) -- the hit is older than LR.FLEE_SECONDS
leave(rj2)
local rj3 = player(9501)
rj3.humanoid.TakeDamage = function() end
tick(0.5)
ok(rj3.humanoid.Health <= 30, "rejoined at the health of the disconnect (" .. rj3.humanoid.Health .. ")")
tick(LR.REJOIN_VERIFY + 0.5)
ok(rj3.humanoid.Health <= 30, "the respawn heal is undone during the re-check")
local purse = cmd(rj3, "state").coins
local deaths0 = cmd(rj3, "state").lairs.deaths.Bramblemaw or 0
rj3.humanoid.Health = 20
tick(0.25) -- hit just now, below 25%
leave(rj3)
eq(Lair.stash[9501], nil, "a fleeing member is not held for a rejoin")
eq(data["p9501"].profile.lairs.deaths.Bramblemaw, deaths0 + 1, "the dodged death is counted")
eq(data["p9501"].profile.coins, purse - math.floor(purse * 0.10), "the purse-coin death penalty applies")
tick(0.5)
eq(#instances:GetChildren(), 0, "the emptied fight closes")

-- 12. (#5) A failed teleport in is retried until the rise; never brought in -> refunded, not "left".
local tp = solo(9502, "Bramblemaw")
local tpCoins = cmd(tp, "state").coins
local tpChar = tp.Character
use(tp, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tp.Character = nil
tick(2)
ok(not arenaOf(tp).members[9502].broughtIn, "no character: not brought in yet")
tp.Character = tpChar
tick(0.25)
ok(arenaOf(tp).members[9502].broughtIn and (tp.root.Position - arenaOf(tp).center).Magnitude < 40, "the teleport is retried")
cmd(tp, "lairLeave")
tick(0.5)
tpCoins = cmd(tp, "state").coins
use(tp, altarPrompt("Bramblemaw", altarAt.Bramblemaw))
tp.Character = nil
tick(LR.WARMUP + 0.5)
tp.Character = tpChar
eq(cmd(tp, "state").coins, tpCoins, "never brought in: the fee is refunded")
ok(has(tp.attrs.LairNotice, "never reached"), "refund notice")
eq(#instances:GetChildren(), 0, "closed")

-- 13. (#6) A kill reward is resent by UserId (to the rejoined Player) and an
-- unpaid won entry blocks a new enter until it is paid.
local rw = solo(9503, "Bramblemaw")
enterInside(rw, "Bramblemaw")
tick(LR.WARMUP)
failLair("kill")
finish(rw, (bossOf(rw)))
tick(0.5)
eq(cmd(rw, "state").lairs.kc.Bramblemaw, nil, "the journal is syncing: not paid yet")
leave(rw)
local rw2 = player(9503)
rw2.humanoid.TakeDamage = function() end
tick(LR.EXIT_SECONDS + 0.5)
ok(has(use(rw2, altarPrompt("Bramblemaw", altarAt.Bramblemaw)).message, "still being counted"), "a new enter waits for the unpaid reward")
healBridge()
tick(LR.REWARD_RETRY + 0.5)
eq(cmd(rw2, "state").lairs.kc.Bramblemaw, 1, "the resend reaches the rejoined Player by UserId")

-- 14. (#8) A boss whose spawn fails after registration is despawned (no orphan).
local orphan = solo(9504, "Bramblemaw")
local orphanCoins = cmd(orphan, "state").coins
local fOrphan = enterInside(orphan, "Bramblemaw")
registerThenFail = true
tick(LR.WARMUP)
registerThenFail = false
eq(combatLogic.lrRecord(fOrphan.id), nil, "the registered boss is despawned")
eq(#combatLogic.records(), 0, "no orphaned creatures")
eq(cmd(orphan, "state").coins, orphanCoins, "fee refunded")

-- 15. (#9) A member offline in the warmup stays a member at the rise, not counted for party health.
local h9 = solo(9511, "Aerisca")
local m9 = solo(9512, "Aerisca")
h9.attrs.CoopId, m9.attrs.CoopId = "crew-9", "crew-9"
use(h9, altarPrompt("Aerisca", altarAt.Aerisca))
use(m9, altarPrompt("Aerisca", altarAt.Aerisca))
tick(0.25)
local f9 = arenaOf(h9)
h9.root.Position = f9.center + Vector3.new(0, 3, -20)
leave(m9)
tick(LR.WARMUP)
local r9 = bossOf(h9)
ok(r9 ~= nil and r9.members[9512] == true, "the offline member is kept at the rise")
eq(r9.maxHp, LR.partyHp(LR.Bosses.Aerisca, 1), "party health counts only members inside")
local m9b = player(9512)
m9b.humanoid.TakeDamage = function() end
tick(0.5)
ok(Lair.byUser[9512] == f9 and (m9b.root.Position - f9.center).Magnitude < 40, "the warmup dropout rejoins the fight")
finish(h9, r9)
tick(0.5)
eq(cmd(m9b, "state").lairs.kc.Aerisca, 1, "and is paid")
tick(LR.EXIT_SECONDS + LR.REWARD_RETRY)

-- 16. (#10) A death during the warmup is recorded as died, not left.
local wd = solo(9505, "Bramblemaw")
enterInside(wd, "Bramblemaw")
tick(4)
wd.humanoid.Health = 0
tick(0.5)
eq(cmd(wd, "state").lairs.deaths.Bramblemaw, 1, "warmup death counted")
wd.humanoid.Health = 100
tick(0.5)
eq(#instances:GetChildren(), 0, "closed")

-- 17. (#11) A refund the journal cannot take yet ("sync") is resent.
local rs = solo(9506, "Bramblemaw")
local rsCoins = cmd(rs, "state").coins
enterInside(rs, "Bramblemaw")
failLair("refund")
spawnFails = true
tick(LR.WARMUP)
spawnFails = false
eq(cmd(rs, "state").coins, rsCoins - LR.Bosses.Bramblemaw.fee, "refund pending while the journal syncs")
healBridge()
tick(LR.REWARD_RETRY + 0.5)
eq(cmd(rs, "state").coins, rsCoins, "the refund is resent")

-- 18. (#13) The dead "cancel" op is gone.
eq(storage.IsleLairs.OnInvoke("cancel", rs), nil, "no cancel op")

-- 19. (#2) Shutdown: the journal's BindToClose drains lairs before the journals
-- save (online members refunded at once); an offline member's owed fee is
-- refunded at their next load.
local sdOn = solo(9507, "Bramblemaw")
local sdOff = solo(9508, "Bramblemaw")
local onCoins, offCoins = cmd(sdOn, "state").coins, cmd(sdOff, "state").coins
enterInside(sdOn, "Bramblemaw")
enterInside(sdOff, "Bramblemaw")
tick(LR.WARMUP)
leave(sdOff)
local closing = coroutine.create(journalClosers[1])
local okClose, closeErr = coroutine.resume(closing)
ok(okClose and coroutine.status(closing) == "dead", "journal BindToClose ran: " .. tostring(closeErr))
eq(#instances:GetChildren(), 0, "drained")
eq(data["p9507"].profile.coins, onCoins, "online member refunded before the save")
eq(data["p9507"].profile.lairs.owed, nil, "and nothing left owed")
ok(data["p9508"].profile.lairs.owed ~= nil, "the offline member's fee is saved as owed")
local sdBack = player(9508)
eq(cmd(sdBack, "state").coins, offCoins, "owed fee refunded at the next load")
print("PASS: " .. (checks - partD) .. " lair instance assertions.")

------------------------------------------------------------------------------
-- Part E: world.server.lua (altars, anchors, part budget).
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
	local parts, altarParts, lights = 0, 0, 0
	for _, obj in w:GetDescendants() do if obj:IsA("BasePart") then parts += 1 end end
	local islandsRoot = w:FindFirstChild("Islands")
	for i, id in ipairs(LR.Order) do
		local def = LR.Bosses[id]
		local isle = islandsRoot:FindFirstChild(def.isle)
		ok(isle ~= nil, id .. " altar island exists")
		local altar
		for _, m in ipairs(isle:GetChildren()) do if m:GetAttribute("LairAltar") == id then altar = m end end
		ok(altar ~= nil and altar:GetAttribute("LairContent") == true, id .. " altar model")
		local count = 0
		for _, d in ipairs(altar:GetDescendants()) do
			if d:IsA("BasePart") then count += 1 end
			if d:IsA("Light") then lights += 1 end
		end
		eq(count, 4, id .. " altar: dais, stone, two torches")
		altarParts += count
		local stone = altar:FindFirstChild("Lair altar")
		eq(stone:GetAttribute("Shape"), "Obelisk", id .. " altar stone mesh slot")
		eq(altar:FindFirstChild("Lair torch"):GetAttribute("Shape"), "Torch", id .. " torch mesh slot")
		local q = stone:FindFirstChildOfClass("ProximityPrompt")
		ok(q ~= nil and q:GetAttribute("IsleAction") == "lairEnter" and q:GetAttribute("IsleItem") == id, id .. " altar prompt")
		eq(q:GetAttribute("IsleRegion"), def.region, id .. " prompt region gate")
		ok(has(q.ActionText, tostring(def.fee)), id .. " prompt shows the fee")
		local anchor = isle:FindFirstChild("Anchor_Waypoint_Lair_" .. id, true)
		ok(anchor ~= nil and anchor.Transparency == 1 and not anchor.CanCollide, id .. " return anchor")
		altarParts += 1
		local c, r = isle:GetAttribute("IslandCenter"), isle:GetAttribute("IslandRadius")
		local sp = stone.CFrame.Position
		local flat = Vector3.new(sp.X - c.X, 0, sp.Z - c.Z).Magnitude
		ok(flat < r, id .. " altar stands on its island (" .. math.floor(flat) .. " < " .. r .. ")")
	end
	eq(altarParts, 20, "twenty static altar parts")
	eq(lights, 0, "altars add no lights")
	ok(parts < 4000, "static world under the 4000 part budget (" .. parts .. ")")
	print("World: " .. parts .. " static parts (" .. altarParts .. " for lair altars).")
end
print("PASS: " .. (checks - partE) .. " lair world assertions.")

------------------------------------------------------------------------------
-- Part F: Hunt › Bosses and the in-fight HUD.
------------------------------------------------------------------------------
local partF = checks
local UH = require("./tools/ui-harness")
local function ledger()
	return {kc = {Bramblemaw = 41, Aerisca = 3}, pb = {Bramblemaw = 74, Aerisca = 131}, pbParty = {Bramblemaw = 1, Aerisca = 2},
		got = {ThornheartLocket = 1, BramblingPet = 1}, deaths = {Aerisca = 2},
		log = {{b = "Aerisca", s = 131, t = 5, n = 2}, {b = "Bramblemaw", s = 74, t = 4, n = 1, u = "ThornheartLocket"}}, active = ""}
end
local function atlas(size, mutate)
	local snap = UH.snapshot({xp = {Combat = X[55]}})
	snap.lairs = ledger()
	if mutate then mutate(snap) end
	local ui = UH.runAtlas(size, {snapshot = snap})
	UH.press(UH.find(ui.gui, "AtlasButton"))
	return ui
end
local function open(ui)
	UH.press(ui.tabs:FindFirstChild("HuntButton"))
	UH.press(UH.find(ui.scroll, "SectionBosses"))
end
local function viewOf(ui, name) UH.press(UH.find(ui.scroll, "LairView" .. name)) end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui)
	eq(#ui.warnings, 0, "Bosses page renders" .. tag)
	ok(UH.find(ui.scroll, "LairsSummary") ~= nil, "summary card" .. tag)
	for _, id in ipairs(LR.Order) do ok(UH.find(ui.scroll, "Lair" .. id) ~= nil, id .. " card" .. tag) end
	viewOf(ui, "Uniques")
	eq(#ui.warnings, 0, "uniques view" .. tag)
	for _, id in ipairs(LR.Order) do
		for _, d in ipairs(LR.Loot[id]) do ok(UH.find(ui.scroll, "LairDrop" .. id .. d.item) ~= nil, id .. " " .. d.item .. " row" .. tag) end
	end
	viewOf(ui, "Log")
	eq(#ui.warnings, 0, "log view" .. tag)
	ok(UH.find(ui.scroll, "LairLog1") ~= nil and UH.find(ui.scroll, "LairLog2") ~= nil, "log rows" .. tag)
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	open(ui)
	local text = texts(ui.scroll)
	ok(has(text, "Bramblemaw, the Thorn Matriarch") and has(text, "Nihlvar, the Hollow Archon"), "bosses named")
	ok(has(text, "KC 41"), "kill count shown")
	ok(has(text, "1:14"), "personal best shown")
	ok(has(text, "2 players"), "party best noted")
	ok(has(text, "Requires Combat 70"), "locked boss flagged")
	viewOf(ui, "Uniques")
	text = texts(ui.scroll)
	ok(has(text, "1/3 UNIQUES") or has(text, "2/3 UNIQUES"), "unique tally")
	ok(has(text, "FABLED") and has(text, "GUARANTEED") and has(text, "ELUSIVE"), "drop rarity labels")
	ok(has(text, "1 in 900"), "pet odds")
	viewOf(ui, "Log")
	text = texts(ui.scroll)
	ok(has(text, "Thornheart Locket"), "unique in the log")
	-- Missing and malformed ledgers.
	for _, bad in ipairs({false, {kc = "x", pb = 4, got = {}, log = {{b = "Nope"}, 7}, deaths = "y"}}) do
		local u2 = atlas(roblox.Vector2.new(730, 303), function(snap) snap.lairs = if bad then bad else nil end)
		open(u2)
		eq(#u2.warnings, 0, "odd ledger tolerated")
		for _, v in ipairs({"Uniques", "Log", "Lairs"}) do viewOf(u2, v); eq(#u2.warnings, 0, "odd ledger on " .. v) end
	end
end
do
	for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(730, 303)}) do
		local ui = atlas(size)
		local p = ui.player
		local frame = ui.gui:FindFirstChild("LairHud")
		ok(frame ~= nil and not frame.Visible, "HUD hidden outside a lair")
		p:SetAttribute("LairHud", "boss=Aerisca;state=warmup;party=2;rise=9")
		p:SetAttribute("LairBoss", "Aerisca")
		ok(frame.Visible and has(frame:FindFirstChild("Lines").Text, "9s"), "warmup countdown")
		p:SetAttribute("LairHud", "boss=Aerisca;state=fight;party=1;hp=39000/78000;phase=2/2;pname=Maelstrom;style=ranged;next=melee;in=2;weak=ranged;enrage=45;ends=200;t=63;ward=0;seal=0;adds=0")
		local lines = frame:FindFirstChild("Lines").Text
		ok(has(lines, "50%"), "health shown")
		ok(has(lines, "RANGED"), "stance shown")
		if size.Y >= 520 then
			ok(has(lines, "Ward of Quills"), "prayer hint")
			ok(has(frame:FindFirstChild("Title").Text, "MAELSTROM"), "phase in the title")
		end
		p:SetAttribute("LairHud", "boss=Aerisca;state=fight;party=1;hp=9000/78000;phase=2/2;pname=Maelstrom;style=melee;weak=ranged;enr=1;ends=20;t=200;ward=0;seal=2;adds=2")
		lines = frame:FindFirstChild("Lines").Text
		if size.Y >= 520 then ok(has(lines, "ENRAGED") and has(lines, "sigil 2"), "enrage and seal shown") end
		p:SetAttribute("LairHud", "boss=Aerisca;state=won;party=1;t=93;exit=6")
		ok(has(frame:FindFirstChild("Lines").Text, "6"), "return countdown")
		p:SetAttribute("LairBoss", "")
		ok(not frame.Visible, "HUD hides outside")
		p:SetAttribute("LairNotice", "Aerisca turns RANGED — Ward of Quills!")
		p:SetAttribute("LairNoticeCount", 1)
		ok(has(texts(ui.gui), "Ward of Quills"), "lair toast")
	end
end
print("PASS: " .. (checks - partF) .. " lair atlas assertions.")

------------------------------------------------------------------------------
-- Part G: balance (coins/XP per hour vs Slayer and Master dungeons).
------------------------------------------------------------------------------
local partG = checks
local EG = Data.DungeonEndgame
local MASTER_FLOOR = {Bramblemaw = 2, Aerisca = 4, Pyrewarden = 6, Nihlvar = 7}
print(string.format("%-11s %4s %6s %6s %9s %9s %6s %9s %9s %6s %7s %9s %6s %9s", "boss", "lvl", "fight", "kph", "xp/h", "ref xp", "ratio", "coins/h", "slayer", "ratio", "pet h", "master", "ratio", "uniques/h"))
local prevCoins, prevXp = 0, 0
for _, id in ipairs(LR.Order) do
	local def = LR.Bosses[id]
	local m = LR.model(id, 1)
	local m3 = LR.model(id, LR.MAX_PARTY)
	local ref = LR.slayerReference(def.level)
	local master = EG.model(MASTER_FLOOR[id], true, "S")
	local masterValue = master.coins + master.chestValue
	print(string.format("%-11s %4d %5.0fs %6.1f %9.0f %9.0f %5.2fx %9.0f %9.0f %5.2fx %6.0fh %9.0f %5.2fx %9.0f", id, def.level, m.fight, m.kph, m.xp, ref.xp, m.xp / ref.xp,
		m.coins, ref.coins, m.coins / ref.coins, m.petHours, masterValue, m.coins / masterValue, m.uniques))
	-- Uniques' merchant value is reported, not counted in coins/h (lead decision).
	ok(m.uniques > 0 and math.abs(m.lootValue + m.uniqueValue - LR.expectedValue(LR.Loot[id])) < 1e-6, id .. " unique value split out of coins/h")
	-- Party XP model = the real damage-XP rule with the fight's scaled health as the cap:
	-- a member's equal share of a party-of-three boss pays in full (Progression.styleXp).
	local hp3 = LR.partyHp(def, LR.MAX_PARTY)
	local real = P.styleXp("melee", hp3 / LR.MAX_PARTY, def.xp * hp3 / def.hp, hp3).Combat
	local share = def.xp * (hp3 / LR.MAX_PARTY) / def.hp -- the model's boss XP per member per kill
	within(math.abs(real / Data.CombatStyles.damageXpRate - share), 0, 1e-6, id .. " party XP model matches styleXp at the scaled health")
	ok(m3.xp / m3.kph >= share, id .. " party model pays at least the boss share per member")
	local carry = P.styleXp("melee", def.hp * 1.5, def.xp * hp3 / def.hp, hp3).Combat
	within(carry / P.styleXp("melee", def.hp, def.xp, def.hp).Combat, 1.5 - 1e-6, 1.5 + 1e-6, id .. " a party carry is paid past the base health")
	within(m.fight, 60, 240, id .. " fight length (s)")
	within(m.xp / ref.xp, 0.6, 1.25, id .. " Combat XP/h vs solo grinding at its level")
	within(m.coins / ref.coins, 0.6, 1.25, id .. " coins/h (net of the fee, drops at merchant value) vs Slayer")
	within(m3.coins / ref.coins, 0.6, 1.25, id .. " party-of-three coins/h per member vs Slayer")
	within(m3.xp / ref.xp, 0.6, 1.25, id .. " party-of-three XP/h per member")
	within(m.petHours, 25, 60, id .. " hours to its pet")
	ok(m.coinsKill > 0, id .. " a kill pays more than its fee on average")
	ok(def.fee >= def.coinsAvg * 0.4, id .. " the fee is a real cost (>= 40% of the coin roll)")
	ok(m.coins > prevCoins and m.xp > prevXp, id .. " pays more per hour than the boss before")
	prevCoins, prevXp = m.coins, m.xp
	local uniqueHours = 1 / (LR.Loot[id][#LR.Loot[id] - 1].chance * m.kph)
	within(uniqueHours, 3, 20, id .. " hours to its weapon")
end
print("PASS: " .. (checks - partG) .. " lair balance assertions.")
print("Lairs QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-bosses.luau")
