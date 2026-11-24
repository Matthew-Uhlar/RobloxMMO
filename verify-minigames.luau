-- Minigames: Skybreach Siege (wave defence) and Tempest Haul (skilling boss).
-- Part A checks shared/GameData.lua (Data.Minigames): tiers, portals,
-- creatures, scaling, rewards, the Squall Cache, the Commendation shop,
-- Lumenward, migration and the balance targets (XP/h and currency/h against
-- the solo equivalents, shop prices in hours, AFK earns nothing).
-- Part B runs server.server.lua (deterministic clock, rolls, DataStore
-- doubles): the "minigame" bridge op, settlement validation, the shop verbs,
-- cache rolls, titles, persistence and the Lumenward stat hook.
-- Part C runs minigames.server.lua wired to Part B's real bridge: lobbies and
-- countdowns, tier gating, Siege shields/waves/portals/barricades, AFK and away
-- removal, rejoin, the Haul loop, solo rewards, losses and the ferry gate.
-- Part D renders Hunt › Minigames and the in-game HUD.
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
local MG = Data.Minigames
local S, H = MG.Siege, MG.Haul
local X = Data.XP_TABLE
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function within(x, lo, hi, case) assert(x >= lo and x <= hi, case .. " (" .. string.format("%.3f", x) .. " not in " .. lo .. ".." .. hi .. ")"); checks += 1 end
local function seq(list) local i = 0; return function() i += 1; return list[(i - 1) % #list + 1] end end

------------------------------------------------------------------------------
-- Part A: data, rules and balance.
------------------------------------------------------------------------------
local partA = checks
ok(type(MG) == "table", "Data.Minigames present")
eq(#MG.Order, 2, "two minigames")
eq(MG.Order[1], "Siege", "Siege listed first")
eq(MG.Order[2], "Haul", "Haul listed second")
for _, g in ipairs(MG.Order) do
	local def = MG[g]
	ok(type(def.name) == "string" and #def.name > 0 and #def.color == 6 and type(def.rules) == "string", g .. " metadata")
	ok(def.MIN_PLAYERS >= 1 and def.MAX_PLAYERS == 10 and def.MIN_PLAYERS <= def.MAX_PLAYERS, g .. " party bounds")
	ok(def.PAD_SECONDS >= 10 and def.PAD_RADIUS > 0 and def.TIME_LIMIT >= 300, g .. " lobby and limit")
	ok(def.MIN_POINTS > 0, g .. " has a minimum contribution")
end
eq(S.MIN_PLAYERS, 3, "Siege needs three players")
eq(H.MIN_PLAYERS, 1, "Haul allows solo")
ok(H.SOLO_REWARD < 1 and H.SOLO_REWARD > 0.5, "solo hauls pay reduced rewards")
ok(MG.IDLE_SECONDS >= 30 and MG.REJOIN_SECONDS >= 30 and MG.ACTION_COOLDOWN >= 1, "AFK, rejoin and cooldown windows")
-- Original names only: nothing borrowed from other games.
for _, name in ipairs({S.name, S.keeper, H.name, H.boss, MG.ISLAND}) do
	for _, banned in ipairs({"Pest", "Void Knight", "Tempoross", "Wintertodt", "Barbarian", "Squire"}) do ok(not has(name, banned), name .. " is original (" .. banned .. ")") end
end
-- Tiers.
eq(#S.Tiers, 3, "three landings")
for i, t in ipairs(S.Tiers) do
	eq(S.TierById[t.id], t, t.id .. " indexed")
	eq(t.index, i, t.id .. " index")
	ok(#t.color == 6 and t.hpMult >= 1 and t.damageMult >= 1 and t.commendations >= 1, t.id .. " values")
	if i > 1 then
		local prev = S.Tiers[i - 1]
		ok(t.combat > prev.combat and t.hpMult > prev.hpMult and t.damageMult > prev.damageMult and t.commendations > prev.commendations, t.id .. " scales above " .. prev.id)
	end
end
eq(S.Tiers[1].id, "Novice", "novice first")
eq(S.Tiers[3].id, "Elite", "elite last")
eq(S.tierFor(1), nil, "Combat 1 has no landing")
eq(S.tierFor(20).id, "Novice", "Combat 20 novice")
eq(S.tierFor(49).id, "Novice", "Combat 49 novice")
eq(S.tierFor(50).id, "Veteran", "Combat 50 veteran")
eq(S.tierFor(99).id, "Elite", "Combat 99 elite")
ok(S.canEnter("Novice", 20), "novice at 20")
ok(not S.canEnter("Novice", 19), "novice refused at 19")
ok(has(select(2, S.canEnter("Veteran", 30)), "Combat 50"), "veteran refusal names its level")
ok(not S.canEnter("Elite", 74) and S.canEnter("Elite", 75), "elite edge")
ok(not S.canEnter("Mythic", 99), "unknown landing refused")
ok(has(select(2, S.canEnter(nil, 99)), "Choose"), "nil landing refused")
-- Portals and creatures.
eq(#S.Portals, 4, "four rift portals")
do
	local angles, ids = {}, {}
	for i, p in ipairs(S.Portals) do
		eq(S.PortalById[p.id], p, p.id .. " indexed")
		eq(p.index, i, p.id .. " index")
		ok(not angles[p.angle] and not ids[p.id] and #p.color == 6, p.id .. " distinct")
		angles[p.angle], ids[p.id] = true, true
	end
end
eq(#S.Creatures, 4, "four rift creatures")
for i, c in ipairs(S.Creatures) do
	eq(S.CreatureById[c.id], c, c.id .. " indexed")
	eq(c.index, i, c.id .. " index")
	ok(c.hp > 0 and c.damage > 0 and c.speed > 0 and c.weight > 0 and (c.target == "lane" or c.target == "flyer"), c.id .. " values")
	eq(Data.Monsters[c.id], nil, c.id .. " is minigame-only (not a world monster)")
	ok(S.creatureHp(c.id, "Elite") > S.creatureHp(c.id, "Novice"), c.id .. " tougher at Elite")
	ok(S.creatureDamage(c.id, "Elite") > S.creatureDamage(c.id, "Novice"), c.id .. " hits harder at Elite")
end
ok(S.CreatureById.Hexwing.target == "flyer", "Hexwings fly over barricades")
ok(S.CreatureById.Shardback.breaker > 1, "Shardbacks break barricades faster")
ok(S.CreatureById.Voidleech.keeperMult > 1, "Voidleeches drain the Keeper")
eq(S.pickCreature(0), "Riftling", "roll 0 picks a Riftling")
eq(S.pickCreature(0.9999), "Voidleech", "top roll picks a Voidleech")
eq(S.pickCreature(-5), "Riftling", "garbage roll clamps low")
eq(S.pickCreature("x"), "Riftling", "non-number roll")
do
	local seen = {}
	for i = 0, 99 do local id = S.pickCreature(i / 100); seen[id] = (seen[id] or 0) + 1 end
	for _, c in ipairs(S.Creatures) do eq(seen[c.id], c.weight * 10, c.id .. " weighted share") end
end
-- Shields: a permutation each time.
for seed = 1, 25 do
	local x = seed * 0.0371
	local order = S.shieldOrder(function() x = (x * 7.13 + 0.17) % 1; return x end)
	local set = {}
	for _, id in ipairs(order) do set[id] = true end
	eq(#order, 4, "shield order covers four portals (seed " .. seed .. ")")
	ok(set.Cinder and set.Gale and set.Rime and set.Gloam, "shield order is a permutation (seed " .. seed .. ")")
end
do
	local a = table.concat(S.shieldOrder(function() return 0 end), ",")
	local b = table.concat(S.shieldOrder(function() return 0.99 end), ",")
	ok(a ~= b, "different rolls give different shield orders")
end
-- Scaling.
eq(MG.partyScale(3), 1, "three players scale x1")
ok(MG.partyScale(10) > MG.partyScale(3) and MG.partyScale(1) < 1, "party scale grows with players")
eq(MG.partyScale(50), MG.partyScale(10), "party scale caps at ten")
eq(MG.partyScale("x"), MG.partyScale(1), "garbage party size")
do
	local n3, n10, e3 = S.scaled("Novice", 3), S.scaled("Novice", 10), S.scaled("Elite", 3)
	eq(n3.keeper, S.KEEPER_HP, "novice trio keeper")
	eq(n3.portal, S.PORTAL_HP, "novice trio portal")
	ok(n10.keeper > n3.keeper and n10.portal > n3.portal, "bigger party, bigger pools")
	ok(e3.keeper > n3.keeper and e3.portal > n3.portal and e3.barricade > n3.barricade, "elite pools")
	eq(e3.barricade, S.BARRICADE_HP * 5, "elite barricades")
	ok(n3.repair > 0 and e3.repair > n3.repair, "repairs scale with tier")
end
ok(S.strikeDamage(60, "Novice") > S.strikeDamage(30, "Novice"), "strike damage grows with Combat")
ok(S.strikeDamage(60, "Elite") > S.strikeDamage(60, "Novice"), "strikes scale with the landing")
ok(S.strikeDamage(40, "Novice", true) > S.strikeDamage(40, "Novice"), "Lumenward sharpens strikes")
eq(S.strikeDamage(999, "Novice"), S.strikeDamage(99, "Novice"), "Combat clamps at 99")
eq(S.waveSize("Novice", 1), 1, "solo-sized novice wave")
eq(S.waveSize("Elite", 10), 4, "elite full wave capped at 4")
ok(S.waveSize("Veteran", 4) > S.waveSize("Novice", 4), "veteran waves are bigger")
ok(S.repairXp(50) > S.repairXp(1) and S.repairXp(500) == S.repairXp(99), "repair XP scales and clamps")
-- Siege rewards.
for _, t in ipairs(S.Tiers) do
	eq(S.reward(t.id, S.MIN_POINTS, true), t.commendations, t.id .. " pays its Commendations at the minimum")
	eq(S.reward(t.id, S.MIN_POINTS - 1, true), 0, t.id .. " below minimum pays nothing")
	eq(S.reward(t.id, 500, false), 0, t.id .. " loss pays nothing")
	eq(S.reward(t.id, 0, true), 0, t.id .. " AFK (0 points) earns nothing")
end
eq(S.reward("Nope", 500, true), 0, "unknown tier pays nothing")
-- Haul rules.
for action, skill in pairs(H.ActionSkill) do
	local low, high = H.actionXp(action, {Fishing = 20, Cooking = 20, Carpentry = 20}), H.actionXp(action, {Fishing = 80, Cooking = 80, Carpentry = 80})
	ok((low[skill] or 0) >= 1, action .. " pays " .. skill .. " XP")
	ok(high[skill] > low[skill], action .. " XP grows with level")
end
eq(next(H.actionXp("nope", {})), nil, "unknown action pays nothing")
ok(H.actionXp("cook", {Cooking = 60}).Cooking > 0 and H.actionXp("cook", {Cooking = 60}).Fishing == nil, "cooking trains Cooking only")
ok(H.actionXp("repair", {Carpentry = 60}).Carpentry ~= nil, "repairs train Carpentry")
ok(H.energyHit(true, 3) > H.energyHit(false, 3), "cooked fish hit harder")
ok(H.energyHit(true, 10) < H.energyHit(true, 3), "bigger crews need more fish")
ok(H.essenceHit(1) > H.essenceHit(10), "harpoons scale with the crew")
eq(H.rolls(H.MIN_POINTS - 1, true, 4), 0, "below the minimum: no roll")
eq(H.rolls(5000, false, 4), 0, "a lost haul pays no roll")
eq(H.rolls(0, true, 4), 0, "AFK (0 points) earns no roll")
eq(H.rolls(H.MIN_POINTS, true, 4), 1, "the minimum earns one roll")
eq(H.rolls(H.ROLL_POINTS * 3, true, 4), 3, "a roll per ROLL_POINTS")
eq(H.rolls(1e6, true, 4), H.MAX_ROLLS, "rolls cap")
ok(H.rolls(H.ROLL_POINTS * 4, true, 1) < H.rolls(H.ROLL_POINTS * 4, true, 4), "solo pays fewer rolls")
-- Squall Cache.
do
	local zero = H.rollCache(30, function() return 0 end)
	ok(zero.coins >= 1 and next(zero.items) ~= nil, "a roll pays coins and an item")
	for _, u in ipairs(H.Cache.uniques) do eq(zero.items[u.item], 1, u.item .. " rolls on a 0 roll") end
	local high = H.rollCache(30, function() return 0.999 end)
	for _, u in ipairs(H.Cache.uniques) do eq(high.items[u.item], nil, u.item .. " misses on a high roll") end
	for _, u in ipairs(H.Cache.uniques) do ok(Data.Items[u.item] ~= nil and u.chance > 0 and u.chance < 0.02, u.item .. " is a rare unique") end
	for _, e in ipairs(H.Cache.entries) do ok(Data.Items[e.item] ~= nil and e.min >= 1 and e.max >= e.min and e.weight > 0, e.item .. " cache entry") end
	local x = 0.123
	for i = 1, 40 do
		local lvl = 20 + (i % 8) * 10
		local r = H.rollCache(lvl, function() x = (x * 9.7 + 0.31) % 1; return x end)
		local v = H.rollValue(lvl)
		ok(r.coins >= math.floor(H.Cache.coins[1] * v) and r.coins <= math.floor(H.Cache.coins[2] * v), "roll " .. i .. " coins in range")
		for id, n in pairs(r.items) do ok(Data.Items[id] ~= nil and n >= 1, "roll " .. i .. " item " .. id) end
	end
	local pool20 = H.cachePool(20)
	for _, e in ipairs(pool20) do ok((e.level or 1) <= 20, e.item .. " available at Fishing 20") end
	ok(H.expectedRoll(80) > H.expectedRoll(20), "rolls are worth more at higher Fishing")
end
-- Items: outfits, rod, pet.
eq(#Data.Sets.Lumenward.pieces, 4, "Lumenward lists four pieces")
eq(#Data.Sets.Lumenward.helms, 3, "three Lumenward helms (one per style)")
for id, style in pairs(MG.LumenwardStyle) do
	local def = Data.Items[id]
	ok(def and def.kind == "armor" and def.slot == "helmet" and def.set == "Lumenward", id .. " is a Lumenward helm")
	ok(style.style == "melee" or style.style == "ranged" or style.style == "magic", id .. " style")
	for stat in pairs(style.stats) do ok(Data.Stats[stat] ~= nil, id .. " style stat " .. stat) end
end
for _, id in ipairs({"LumenwardHauberk","LumenwardGreaves","LumenwardTreads"}) do
	local def = Data.Items[id]
	ok(def and def.kind == "armor" and def.set == "Lumenward" and def.requires.Combat == 30, id .. " shared Lumenward piece")
end
eq(#Data.Sets.Stormcaller.pieces, 4, "Stormcaller outfit has four pieces")
for _, id in ipairs(Data.Sets.Stormcaller.pieces) do ok(Data.Items[id].set == "Stormcaller" and (Data.Items[id].stats.fishingFortune or 0) > 0, id .. " fishing outfit piece") end
ok(Data.Items.TidebreakerRod.toolKind == "Rod" and Data.Items.TidebreakerRod.requires.Fishing == 50, "Tidebreaker Rod is a rod")
ok(Data.Items.SquallpupPet.kind == "pet" and Data.PetById.Squallpup ~= nil, "Squallpup pet species")
ok(Data.PetDepth.Abilities.Squallpup ~= nil and #Data.PetDepth.Abilities.Squallpup == 3, "Squallpup abilities")
do
	local found = false
	for _, d in ipairs(Data.SeaCreatures.StormcoilSerpent.drops) do if d.item == "SquallpupPet" then found = true end end
	ok(found, "Squallpup also swims with Stormcoil Serpents")
end
-- Shop.
ok(#MG.Shop >= 14, "shop lists " .. #MG.Shop .. " rewards")
do
	local kinds = {}
	for i, e in ipairs(MG.Shop) do
		eq(MG.ShopById[e.id], e, e.id .. " indexed")
		eq(e.index, i, e.id .. " index")
		ok(e.cost > 0, e.id .. " cost")
		kinds[e.kind] = (kinds[e.kind] or 0) + 1
		if e.kind == "armor" then ok(Data.Items[e.item] ~= nil, e.id .. " sells an item") end
		if e.kind == "lamp" then ok(Data.Skills[e.skill] ~= nil and MG.LampSkills[e.skill] ~= nil, e.id .. " lamp skill") end
		if e.kind == "cosmetic" then ok(type(e.title) == "string", e.id .. " title") end
	end
	eq(kinds.armor, 6, "six armour pieces")
	eq(kinds.lamp, 5, "five combat lamps")
	eq(kinds.cosmetic, 3, "three cosmetics")
end
for _, skill in ipairs({"Combat","Ranged","Magic","Prayer","Slayer"}) do
	ok(MG.lampXp(skill, 60) > MG.lampXp(skill, 20), skill .. " lamp grows with level")
end
eq(MG.lampXp("Fishing", 50), 0, "no fishing lamp")
ok(MG.lampXp("Prayer", 50) < MG.lampXp("Combat", 50), "Prayer lamps are smaller")
do
	local e, why = MG.canBuy("LampCombat", {commendations = 29}, {})
	ok(e == nil and has(why, "30"), "lamp needs 30 Commendations")
	ok(MG.canBuy("LampCombat", {commendations = 30}, {}) ~= nil, "lamp affordable at 30")
	local _, low = MG.canBuy("LumenwardHauberk", {commendations = 999}, {Combat = 29})
	ok(has(low, "Combat 30"), "armour level gate")
	ok(MG.canBuy("LumenwardHauberk", {commendations = 250}, {Combat = 30}) ~= nil, "armour affordable")
	local _, owned = MG.canBuy("TitleKeeperward", {commendations = 999, unlocks = {TitleKeeperward = true}}, {})
	ok(has(owned, "already"), "cosmetic once")
	ok(has(select(2, MG.canBuy("Nope", {}, {})), "Choose"), "unknown reward")
	ok(has(select(2, MG.canBuy(nil, nil, nil)), "Choose"), "nil reward")
end
-- Lumenward style bonus.
do
	local function profile(helm, extra)
		local p = {xp = {Combat = X[40]}, items = {}, equipment = {helmet = helm, chest = "LumenwardHauberk", legs = "LumenwardGreaves", boots = "LumenwardTreads"}}
		for _, id in pairs(p.equipment) do p.items[id] = 1 end
		if extra then extra(p) end
		return p
	end
	-- Client-side Progression.computeStats (the shared module, no server wrapper)
	-- carries the style bonus through the Data.Sets set-style hook.
	local styleHook = Data.Sets.Lumenward.style
	for helm, style in pairs(MG.LumenwardStyle) do
		local p = profile(helm)
		eq(MG.lumenwardStyle(p, P.equipped), style, helm .. " sets the style")
		local s = P.computeStats(p, 0)
		eq(s.activeSet, "Lumenward", helm .. " completes the set")
		Data.Sets.Lumenward.style = nil
		local base = P.computeStats(p, 0)
		Data.Sets.Lumenward.style = styleHook
		for stat, v in pairs(style.stats) do
			local def = Data.Stats[stat]
			eq(s[stat], math.min(def.cap or math.huge, (base[stat] or 0) + v), helm .. " adds " .. stat .. " in the shared computeStats")
		end
		eq(s.setStyle, style.style, helm .. " style tag")
		eq(s.effectiveHealth, math.floor(s.health * (1 + s.defense / 100)), helm .. " effective health")
	end
	eq(MG.lumenwardStyle(profile("LumenwardWarhelm", function(p) p.equipment.boots = nil end), P.equipped), nil, "three pieces: no style")
	eq(MG.lumenwardStyle(profile("LumenwardWarhelm", function(p) p.items.LumenwardTreads = 0 end), P.equipped), nil, "unowned piece: no style")
	eq(MG.lumenwardStyle(profile("StormcallerHood"), P.equipped), nil, "foreign helm: no style")
	eq(MG.lumenwardStyle(nil, P.equipped), nil, "nil profile")
	-- LOW 3: pieces must be validly equipped (Progression.equipped: requirements), not just listed.
	local weakWearer = profile("LumenwardWarhelm", function(p) p.xp.Combat = X[20] end)
	eq(MG.lumenwardStyle(weakWearer, P.equipped), nil, "Combat 20 wearer: not validly equipped, no style")
	eq(P.computeStats(weakWearer, 0).setStyle, nil, "no style stats below the requirement")
	local plain = {xp = {}, items = {}, equipment = {}}
	eq(P.computeStats(plain, 0).setStyle, nil, "no outfit, no style")
	ok(not has(fs.readFile("server.server.lua"), "minigamesStatsHook"), "the server-only computeStats wrapper is gone")
end
-- Migration.
do
	local fresh = MG.migrate(nil)
	eq(fresh.commendations, 0, "fresh commendations")
	eq(fresh.rolls, 0, "fresh rolls")
	eq(fresh.title, "", "fresh title")
	for _, g in ipairs(MG.Order) do eq(fresh.log[g].played, 0, g .. " fresh log") end
	local dirty = MG.migrate({commendations = -5, rolls = 1e9, unlocks = {TitleKeeperward = true, LampCombat = true, Nope = true, TitleRiftsealer = "yes"},
		title = "TitleRiftsealer", log = {Siege = {played = "x", won = 3, points = 0 / 0}, Bogus = {}}})
	eq(dirty.commendations, 0, "negative commendations clamp")
	eq(dirty.rolls, 500, "rolls cap")
	ok(dirty.unlocks.TitleKeeperward and not dirty.unlocks.LampCombat and not dirty.unlocks.Nope and not dirty.unlocks.TitleRiftsealer, "only owned cosmetics survive")
	eq(dirty.title, "", "an unowned title is dropped")
	eq(dirty.log.Siege.played, 0, "garbage log count")
	eq(dirty.log.Siege.won, 3, "log kept")
	eq(dirty.log.Siege.points, 0, "NaN points")
	eq(dirty.log.Bogus, nil, "unknown game dropped")
	eq(MG.migrate({unlocks = {TitleKeeperward = true}, title = "TitleKeeperward"}).title, "TitleKeeperward", "owned title kept")
end
-- Balance: XP/h and currency/h against the solo equivalents.
local balanceLines = {}
for _, t in ipairs(S.Tiers) do
	local cph = S.commendationsPerHour(t.id)
	within(cph, 20, 50, t.id .. " Commendations per hour")
	for _, lvl in ipairs({t.combat, t.combat + 10, 99}) do
		local lampsPerHour = cph / MG.LAMP_COST
		for skill, factor in pairs(MG.LampSkills) do
			local ratio = lampsPerHour * MG.lampXp(skill, lvl) / (factor * MG.soloCombatXpPerHour(lvl))
			within(ratio, 0.8, 1.2, t.id .. " " .. skill .. " lamp XP/h vs solo at " .. lvl)
			ok(ratio <= MG.SOCIAL_BONUS * 1.05, t.id .. " " .. skill .. " social bonus respected at " .. lvl)
		end
	end
	-- Shop pricing vs time.
	local set = (MG.ShopById.LumenwardHauberk.cost + MG.ShopById.LumenwardGreaves.cost + MG.ShopById.LumenwardTreads.cost + MG.ShopById.LumenwardWarhelm.cost) / cph
	within(set, 15, 40, t.id .. " hours for a full Lumenward outfit")
	within(MG.LAMP_COST / cph, 0.5, 1.5, t.id .. " hours per lamp")
	within(MG.ShopById.TitleRiftsealer.cost / cph, 15, 50, t.id .. " hours for the top title")
	table.insert(balanceLines, string.format("%s %.1f C/h, outfit %.1f h", t.id, cph, set))
end
ok(S.commendationsPerHour("Elite") > S.commendationsPerHour("Novice"), "harder landings pay a little more per hour")
for _, lvl in ipairs({20, 30, 45, 60, 75, 90, 99}) do
	local xp = H.modelXpPerHour(lvl) / MG.soloFishCookXpPerHour(lvl)
	within(xp, 0.8, 1.2, "Haul XP/h vs solo fish+cook at " .. lvl)
	ok(xp <= MG.SOCIAL_BONUS * 1.05, "Haul XP social bonus at " .. lvl)
	local group = H.rollsPerHour(false) * H.expectedRoll(lvl) / MG.soloFishCoinsPerHour(lvl)
	within(group, 0.8, 1.2, "Haul coins/h (crew) vs solo fishing at " .. lvl)
	local solo = H.rollsPerHour(true) * H.expectedRoll(lvl) / MG.soloFishCoinsPerHour(lvl)
	within(solo, 0.55, 0.95, "Haul coins/h (solo, reduced) at " .. lvl)
	ok(solo < group, "solo hauls pay less than crews at " .. lvl)
	table.insert(balanceLines, string.format("Haul L%d XP %.2fx, coins %.2fx (solo %.2fx)", lvl, xp, group, solo))
end
within(1 / (H.Cache.uniques[1].chance * H.rollsPerHour(false)), 3, 40, "hours to a Squallpup")
within(1 / (H.Cache.uniques[2].chance * H.rollsPerHour(false)), 2, 30, "hours to a Tidebreaker Rod")
ok(H.modelPointsPerHour() > 0 and H.rollsPerHour(false) > H.rollsPerHour(true), "model sanity")
for _, line in ipairs(balanceLines) do print("  " .. line) end
print("PASS: " .. (checks - partA) .. " minigame data/rule/balance assertions.")

------------------------------------------------------------------------------
-- Part B: server.server.lua (journal side).
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
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "minigames-test" end},
	RunService = {IsStudio = function() return false end},
}
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
			assert(coroutine.resume(co, ...))
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
-- Player doubles shared by the journal (Part B) and the minigames (Part C).
local mgPlayers = {}
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 10, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true,
		FindFirstChild = function(_, name) if name == nil or name == "HumanoidRootPart" then return root end return nil end,
		FindFirstChildOfClass = function(_, name) if name == nil or name == "Humanoid" then return humanoid end return nil end,
		WaitForChild = function(_, name) if name == "HumanoidRootPart" then return root end return humanoid end,
		PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) services.Players.PlayerRemoving:Fire(p) end
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
-- The autosave loop never resumes in this harness: a sealed save renews a journal's lease.
local function renew(list) for _, p in ipairs(list) do if p.Parent then coopProfile.OnInvoke(p, true) end end end
ok(remote ~= nil and bridge ~= nil, "IsleAction and IsleBridge found")
local function cmd(p, verb, item)
	advance(1)
	return remote.OnServerInvoke(p, verb, item)
end
local function op(p, payload) advance(0.1) return bridge.OnInvoke("minigame", p, payload) end

local rookie = player(9101)
local s0 = cmd(rookie, "state")
ok(type(s0.minigames) == "table", "snapshot carries minigames")
eq(s0.minigames.commendations, 0, "fresh commendations")
eq(s0.minigames.rolls, 0, "fresh rolls")
eq(s0.minigames.title, "", "no title")
eq(#s0.minigames.unlocks, 0, "no unlocks")
eq(s0.minigames.log.Siege.played, 0, "empty siege log")
eq(s0.minigames.log.Haul.played, 0, "empty haul log")
ok(s0.minigames.lamps.Combat > 0 and s0.minigames.lamps.Prayer > 0, "lamp previews")
eq(s0.minigames.lumenward, nil, "no Lumenward")
eq(rookie.attrs.MinigameTitle, "", "title attribute")
ok(has(cmd(rookie, "mgBuy", "LampCombat").message, "30 Commendations"), "cannot afford a lamp")
ok(has(cmd(rookie, "mgBuy", "Nope").message, "Choose"), "unknown reward")
ok(has(cmd(rookie, "mgBuy", nil).message, "Choose"), "nil reward")
ok(has(cmd(rookie, "mgRoll", "1").message, "no Squall Cache rolls"), "no rolls to open")
ok(has(cmd(rookie, "mgTitle", "TitleKeeperward").message, "do not own"), "unowned title")
-- Bridge: info and Timber.
local info0 = op(rookie, {action = "info"})
eq(info0.combat, 1, "info combat level")
eq(info0.levels.Fishing, 1, "info fishing level")
eq(info0.lumenward, false, "info lumenward flag")
eq(op(rookie, {action = "spend", item = "Timber", amount = 1}).ok, false, "no Timber to spend")
eq(op(rookie, {action = "bogus"}), nil, "unknown action")
-- Settlement validation.
eq(op(rookie, {action = "settle", game = "Nope"}).ok, false, "unknown game refused")
eq(op(rookie, {action = "settle", game = "Siege", tier = "Mythic"}).ok, false, "unknown tier refused")

local veteran = seeded(9102, function(p) p.xp.Combat = X[55]; p.xp.Carpentry = X[30]; p.xp.Fishing = X[40]; p.items.Timber = 3 end)
local inf = op(veteran, {action = "info"})
eq(inf.combat, 55, "info reads Combat")
eq(inf.levels.Carpentry, 30, "info reads Carpentry")
eq(op(veteran, {action = "spend", item = "Ore", amount = 1}).ok, false, "only Timber is spent")
eq(op(veteran, {action = "spend", item = "Timber", amount = 1}).ok, true, "Timber spent")
eq(cmd(veteran, "state").items.Timber, 2, "one Timber gone")
eq(op(veteran, {action = "spend", item = "Timber", amount = 99}).ok, false, "amount clamps to 5 and must be owned")
local carp0 = cmd(veteran, "state").xp.Carpentry
local won = op(veteran, {action = "settle", game = "Siege", tier = "Veteran", points = 120, won = true, partySize = 5, seconds = 300, xp = {Carpentry = 500, Mining = 10, Nope = 4}})
ok(won.ok and won.paid == 5, "veteran win pays 5 Commendations")
eq(won.points, 120, "points echoed")
local sv = cmd(veteran, "state")
eq(sv.minigames.commendations, 5, "Commendations banked")
eq(sv.minigames.log.Siege.played, 1, "siege played")
eq(sv.minigames.log.Siege.won, 1, "siege won")
eq(sv.minigames.log.Siege.points, 120, "siege points logged")
eq(sv.minigames.log.Siege.best, 120, "best match")
eq(sv.minigames.log.Siege.paid, 5, "paid logged")
eq(sv.xp.Carpentry - carp0, math.min(500, S.repairXp(30) * S.REPAIR_XP_LIMIT), "Carpentry XP paid (capped at the per-match repair budget)")
eq(sv.xp.Mining, 0, "XP outside the game's skills refused")
ok(has(veteran.last.message, "+5 Commendations"), "settlement notice")
-- Clamps.
local clamp = op(veteran, {action = "settle", game = "Siege", tier = "Veteran", points = 1e9, won = true, partySize = 5, seconds = 10, xp = {Carpentry = 1e9}})
eq(clamp.points, MG.MAX_POINTS_PER_SECOND * 10, "points clamp to the per-second cap")
local sv2 = cmd(veteran, "state")
ok(sv2.xp.Carpentry - sv.xp.Carpentry <= S.repairXp(30) * (10 / MG.ACTION_COOLDOWN + 1), "XP clamps to the action rate")
eq(sv2.minigames.commendations, 10, "a capped win still pays")
eq(sv2.minigames.log.Siege.best, 120, "best keeps the larger match")
-- Losses, leeches, forfeits.
eq(op(veteran, {action = "settle", game = "Siege", tier = "Veteran", points = 300, won = false, partySize = 5, seconds = 300}).paid, 0, "a loss pays nothing")
eq(op(veteran, {action = "settle", game = "Siege", tier = "Veteran", points = 49, won = true, partySize = 5, seconds = 300}).paid, 0, "a leech below 50 points is unpaid")
eq(op(veteran, {action = "settle", game = "Siege", tier = "Veteran", points = 0, won = true, partySize = 5, seconds = 300}).paid, 0, "AFK earns nothing")
eq(op(veteran, {action = "settle", game = "Siege", tier = "Veteran", points = 300, won = true, partySize = 5, seconds = 300, forfeit = true}).paid, 0, "a removed member is unpaid")
local sv3 = cmd(veteran, "state")
eq(sv3.minigames.log.Siege.played, 6, "every match is logged")
eq(sv3.minigames.log.Siege.won, 2, "only credited wins count (leeches and AFK excluded)")
eq(sv3.minigames.commendations, 10, "no Commendations from losses")
-- Haul settlement.
local haul = op(veteran, {action = "settle", game = "Haul", points = H.ROLL_POINTS * 3, won = true, partySize = 4, seconds = 400, xp = {Fishing = 300, Cooking = 200, Carpentry = 50}})
eq(haul.paid, 3, "crew haul pays 3 rolls")
local soloHaul = op(veteran, {action = "settle", game = "Haul", points = H.ROLL_POINTS * 3, won = true, partySize = 1, seconds = 400})
eq(soloHaul.paid, 2, "solo haul pays 75%")
eq(op(veteran, {action = "settle", game = "Haul", points = 100, won = true, partySize = 1, seconds = 400}).paid, 0, "below 150 points: no roll")
local sh = cmd(veteran, "state")
eq(sh.minigames.rolls, 5, "rolls banked")
eq(sh.minigames.log.Haul.played, 3, "haul log")
eq(sh.minigames.log.Haul.paid, 5, "haul paid log")
ok(sh.xp.Cooking >= 200, "Cooking XP from the haul")
-- Opening caches.
local coinsBefore = sh.coins
rolls = {0.5, 0.5, 0.0}
local opened = cmd(veteran, "mgRoll", "1")
ok(has(opened.message, "Opened 1 Squall Cache"), "open one cache")
eq(opened.minigames.rolls, 4, "a roll spent")
ok(opened.coins > coinsBefore, "cache coins paid")
rolls = {}
local all = cmd(veteran, "mgRoll", "all")
ok(has(all.message, "Opened 4 Squall Caches"), "open all")
eq(all.minigames.rolls, 0, "rolls emptied")
-- The shop.
local buyLamp = cmd(veteran, "mgBuy", "LampCombat")
ok(has(buyLamp.message, "Needs 30"), "a lamp needs 30 Commendations")
eq(buyLamp.minigames.commendations, 10, "a refused purchase costs nothing")
local rich = seeded(9103, function(p)
	p.xp.Combat = X[40]
	p.minigames = {commendations = 2000, rolls = 0, unlocks = {}, title = "", log = {}}
end)
local xp0 = cmd(rich, "state").xp.Combat
local lampReply = cmd(rich, "mgBuy", "LampCombat")
eq(lampReply.minigames.commendations, 2000 - MG.LAMP_COST, "lamp costs 30")
eq(lampReply.xp.Combat - xp0, MG.lampXp("Combat", 40), "lamp XP at level 40")
local helm = cmd(rich, "mgBuy", "LumenwardWarhelm")
eq(helm.items.LumenwardWarhelm, 1, "helm bought")
for _, id in ipairs({"LumenwardHauberk","LumenwardGreaves","LumenwardTreads","LumenwardSightcowl"}) do cmd(rich, "mgBuy", id) end
local bought = cmd(rich, "state")
eq(bought.minigames.commendations, 2000 - 30 - 200 - 250 - 250 - 150 - 200, "outfit prices")
local title = cmd(rich, "mgBuy", "TitleKeeperward")
eq(title.minigames.title, "TitleKeeperward", "title worn on purchase")
eq(rich.attrs.MinigameTitle, "Keeperward", "title attribute")
ok(has(cmd(rich, "mgBuy", "TitleKeeperward").message, "already"), "a title once")
eq(cmd(rich, "mgTitle", "none").minigames.title, "", "hide title")
eq(rich.attrs.MinigameTitle, "", "attribute cleared")
eq(cmd(rich, "mgTitle", "TitleKeeperward").minigames.title, "TitleKeeperward", "wear again")
-- Lumenward stats through the server (computeStats hook) and the bridge.
local plainStats = bridge.OnInvoke("stats", rich, {}).stats
for _, slot in ipairs({"LumenwardWarhelm","LumenwardHauberk","LumenwardGreaves","LumenwardTreads"}) do cmd(rich, "equip", slot) end
local worn = cmd(rich, "state")
eq(worn.depth.equipment.helmet, "LumenwardWarhelm", "helm equipped")
eq(worn.minigames.lumenward, "melee", "snapshot reports the melee style")
local meleeStats = bridge.OnInvoke("stats", rich, {}).stats
eq(meleeStats.activeSet, "Lumenward", "set active")
eq(meleeStats.setStyle, "melee", "bridge stats carry the style")
ok(meleeStats.strength >= plainStats.strength + 25, "melee helm adds Strength")
eq(op(rich, {action = "info"}).lumenward, true, "info reports Lumenward")
cmd(rich, "equip", "LumenwardSightcowl")
local rangedStats = bridge.OnInvoke("stats", rich, {}).stats
eq(rangedStats.setStyle, "ranged", "ranged helm swaps the style")
ok((rangedStats.rangedAccuracy or 0) >= 30 and rangedStats.strength < meleeStats.strength, "ranged bonus replaces melee")
cmd(rich, "unequip", "boots")
eq(bridge.OnInvoke("stats", rich, {}).stats.setStyle, nil, "three pieces: no style bonus")
-- Persistence and migration.
leave(rich)
local saved = data["p9103"].profile.minigames
eq(saved.unlocks.TitleKeeperward, true, "unlock saved")
eq(saved.commendations, bought.minigames.commendations - 400, "commendations saved")
data["p9103"].profile.minigames.rolls = -4
data["p9103"].profile.minigames.unlocks.LampMagic = true
rich = player(9103)
local back = cmd(rich, "state")
eq(back.minigames.rolls, 0, "negative rolls sanitised")
eq(back.minigames.title, "TitleKeeperward", "title survives a rejoin")
eq(table.find(back.minigames.unlocks, "LampMagic"), nil, "lamps are never unlocks")
eq(rich.attrs.MinigameTitle, "Keeperward", "attribute restored")
local old = seeded(9104, function(p) p.minigames = nil end)
eq(cmd(old, "state").minigames.commendations, 0, "old saves migrate")
print("PASS: " .. (checks - partB) .. " minigame server assertions.")

------------------------------------------------------------------------------
-- Part C: minigames.server.lua (lobbies, matches, credit) on the real bridge.
------------------------------------------------------------------------------
local partC = checks
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(p)
	promptSignals[p] = promptSignals[p] or signal()
	return promptSignals[p]
end)
local world = roblox.Instance.new("Workspace")
local mgObjects = {}
local bridgeCalls = {}
local bridgeDown = false -- Part E: the journal is unreachable (the bridge answers nil)
local bridgeProxy = {Invoke = function(_, opName, who, payload)
	table.insert(bridgeCalls, {op = opName, player = who, payload = payload})
	if bridgeDown then return nil end
	return bridge.OnInvoke(opName, who, payload)
end}
local mgServices = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return mgPlayers end},
	RunService = {Heartbeat = signal()},
	CollectionService = {tagged = {}, AddTag = function(self, instance, tag) self.tagged[tag] = self.tagged[tag] or {}; table.insert(self.tagged[tag], instance) end},
	ServerStorage = {FindFirstChild = function(_, name) if name == "IsleBridge" then return bridgeProxy end return mgObjects[name] end},
	ReplicatedStorage = {WaitForChild = function(_, name) return name end},
}
local mgRolls = {}
local mgEnv = {
	game = {GetService = function(_, name) return assert(mgServices[name], name) end}, workspace = world,
	require = function(name) assert(name == "AetherData", "minigames require shared data only") return Data end,
	Instance = {new = function(class)
		if class == "BindableFunction" then
			return setmetatable({ClassName = class}, {__newindex = function(t, k, v) rawset(t, k, v); if k == "Parent" then mgObjects[t.Name] = t end end})
		end
		return roblox.Instance.new(class)
	end},
	Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum,
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	Random = {new = function() return {NextNumber = function() if #mgRolls > 0 then return table.remove(mgRolls, 1) end return 0 end} end},
}
load("minigames.server.lua", mgEnv)
local heartbeat = mgServices.RunService.Heartbeat
local access = mgObjects.IsleMinigameAccess
ok(access ~= nil and type(access.OnInvoke) == "function", "IsleMinigameAccess published")
local bastion = world:FindFirstChild(MG.ISLAND)
ok(bastion ~= nil and bastion:GetAttribute("Minigames") == true, "bastion model built")
local partCount = 0
for _, d in ipairs(bastion:GetDescendants()) do if d:IsA("BasePart") then partCount += 1 end end
within(partCount, 30, 80, "static bastion part budget")
local function find(name) return bastion:FindFirstChild(name, true) end
local function promptOn(part, action)
	-- §44: a travel beacon's prompt hangs on its "Beacon prompt" attachment.
	for _, c in ipairs(part:GetDescendants()) do if c:IsA("ProximityPrompt") and c.ActionText == action then return c end end
	error("missing prompt " .. part.Name .. " / " .. action)
end
for _, name in ipairs({"SiegeNovice pad","SiegeVeteran pad","SiegeElite pad","Haul pad","Lumen Keeper","Cinder Rift","Gale Rift","Rime Rift","Gloam Rift",
	"Mast 1","Mast 2","Cannon 1","Cannon 2","Storm brazier","Harpoon mount","Return ferry beacon","Anchor_Waypoint_SkybreachLanding"}) do
	ok(find(name) ~= nil, name .. " built")
end
for _, def in ipairs(S.Portals) do
	ok(promptOn(find(def.name), "Strike portal") ~= nil, def.id .. " strike prompt")
	ok(promptOn(find(def.name .. " barricade"), "Repair (1 Timber)") ~= nil, def.id .. " repair prompt")
end
local function join(p)
	table.insert(mgPlayers, p)
	mgServices.Players.PlayerAdded:Fire(p)
end
local function drop(p)
	local i = table.find(mgPlayers, p)
	if i then table.remove(mgPlayers, i) end
	mgServices.Players.PlayerRemoving:Fire(p)
end
local renewedAt = clock
local function use(p, part, action)
	advance(1.2)
	if clock - renewedAt > 60 then renewedAt = clock; renew(mgPlayers) end
	p.root.Position = part.Position
	promptSignals[promptOn(part, action)]:Fire(p)
end
local movers = {}
local function tick(seconds, step)
	step = step or 0.5
	local t = 0
	while t < seconds - 1e-9 do
		advance(step)
		t += step
		for p in pairs(movers) do p.root.Position += Vector3.new(0, 0, if math.floor(clock * 2) % 2 == 0 then 1.5 else -1.5) end
		if clock - renewedAt > 60 then renewedAt = clock; renew(mgPlayers) end
		heartbeat:Fire(step)
	end
end
local function hud(p)
	local out = {}
	for pair in tostring(p.attrs.MinigameHud or ""):gmatch("[^;]+") do local k, v = pair:match("^(%w+)=(.*)$"); out[k] = v end
	return out
end
local function lobbies()
	local out = {}
	for pair in tostring(world:GetAttribute("MinigameLobbies") or ""):gmatch("[^;]+") do local k, v = pair:match("^(%w+)=(.*)$"); out[k] = v end
	return out
end
local function onPad(p, pad) p.root.Position = find(pad).Position + Vector3.new(0, 2, 0) end
local function points(p) return tonumber(hud(p).points) or 0 end

-- Ferry gate.
local weak = player(9201)
join(weak)
local denied = access.OnInvoke(weak)
ok(denied.allowed == false and has(denied.message, "Combat 20") and has(denied.message, "Fishing 20"), "ferry refuses low levels and says why")
local angler = seeded(9202, function(p) p.xp.Fishing = X[30]; p.xp.Cooking = X[30]; p.xp.Carpentry = X[20] end)
join(angler)
local allowed = access.OnInvoke(angler)
ok(allowed.allowed == true and typeof(allowed.landing) == "Vector3", "Fishing 30 boards the ferry")
ok((allowed.landing - bastion:GetAttribute("IslandCenter")).Magnitude < 60, "landing on the bastion")
local fighters = {}
for i = 1, 4 do
	fighters[i] = seeded(9210 + i, function(p) p.xp.Combat = X[30]; p.xp.Carpentry = X[25]; p.items.Timber = 4 end)
	join(fighters[i])
end
ok(access.OnInvoke(fighters[1]).allowed, "Combat 30 boards the ferry")
local A, B, Cc, D = fighters[1], fighters[2], fighters[3], fighters[4]
-- Defenders keep the creatures off the Keeper while time passes.
local function defend(seconds)
	local t = 0
	while t < seconds do
		tick(0.5)
		t += 0.5
		for _, p in ipairs({A, B}) do
			if p.attrs.MinigameGame == "Siege" then
				for _, d in ipairs(bastion:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("Creature") then use(p, d, "Strike"); t += 1.2; break end
				end
			end
		end
	end
end
-- Lobby: countdown starts at three, cancels below three.
heartbeat:Fire(0.1)
eq(lobbies().SiegeNovice, "idle,0,0", "empty novice pad")
onPad(A, "SiegeNovice pad"); onPad(B, "SiegeNovice pad")
tick(1)
eq(lobbies().SiegeNovice, "idle,2,0", "two players wait")
onPad(Cc, "SiegeNovice pad")
tick(0.5)
ok(has(lobbies().SiegeNovice, "counting,3,"), "three players start the countdown")
ok(has(A.attrs.MinigameNotice, "launches in"), "countdown notice")
Cc.root.Position = Vector3.new(0, 10, 0)
tick(0.5)
ok(has(lobbies().SiegeNovice, "idle,2"), "countdown cancelled below three")
ok(has(A.attrs.MinigameNotice, "cancelled"), "cancel notice")
onPad(Cc, "SiegeNovice pad"); onPad(D, "SiegeNovice pad"); onPad(weak, "SiegeNovice pad")
tick(0.5)
ok(has(lobbies().SiegeNovice, "counting,5,"), "five on the pad count down")
tick(S.PAD_SECONDS)
eq(A.attrs.MinigameGame, "Siege", "A in the siege")
eq(D.attrs.MinigameGame, "Siege", "D in the siege")
ok(weak.attrs.MinigameGame ~= "Siege", "Combat 1 refused at launch")
ok(has(weak.attrs.MinigameNotice, "Combat 20"), "refusal says why")
ok(has(lobbies().SiegeNovice, "running"), "lobby shows the running match")
ok(has(world:GetAttribute("MinigameMatches"), "Siege=4,"), "match roster published")
local keeper = find("Lumen Keeper")
ok((A.root.Position - keeper.Position).Magnitude < 30, "members ferried into the ring")
local h0 = hud(A)
eq(h0.tier, "Novice", "HUD tier")
local full = S.scaled("Novice", 4).keeper
eq(h0.keeper, full .. "/" .. full, "HUD Keeper at full, scaled for four")
ok(full > S.KEEPER_HP, "four defenders face a bigger Keeper pool")
for entry in h0.portals:gmatch("[^,]+") do ok(entry:sub(-1) == "1", "every shield up at the start: " .. entry) end
eq(h0.min, tostring(S.MIN_POINTS), "HUD minimum")
eq(points(A), 0, "no points yet")
-- Shielded portals refuse strikes.
use(A, find("Cinder Rift"), "Strike portal")
eq(points(A), 0, "a shielded portal gives no points")
ok(has(A.attrs.MinigameNotice, "shielded"), "shield notice")
-- D goes AFK: no movement, no actions.
movers[A], movers[B], movers[Cc] = true, true, true
-- The first wave arrives; strikes on creatures earn points.
tick(5)
local creatures = {}
for _, d in ipairs(bastion:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Creature") then table.insert(creatures, d) end end
ok(#creatures >= 4, "first wave spawned (" .. #creatures .. ")")
ok(tonumber(hud(A).wave) >= 1, "HUD wave count")
local victim = creatures[1]
use(A, victim, "Strike")
eq(points(A), S.Points.strike + S.Points.kill, "a Riftling falls to one strike (+kill bonus)")
ok(victim.Parent == nil, "slain creature removed")
use(Cc, creatures[2], "Strike")
eq(points(Cc), 3, "C lands a kill")
-- Cooldown: a second strike inside ACTION_COOLDOWN is ignored.
do
	local before = points(A)
	A.root.Position = creatures[3].Position
	promptSignals[promptOn(creatures[3], "Strike")]:Fire(A)
	local mid = points(A)
	promptSignals[promptOn(creatures[4], "Strike")]:Fire(A)
	eq(points(A), mid, "strikes inside the cooldown earn nothing")
	ok(mid > before, "the first strike lands")
end
-- Barricades: creatures chip at them, repairs need Timber.
tick(6)
local h1 = hud(A)
local damaged = false
for bar in h1.barricades:gmatch("[^,]+") do local a, b = bar:match("(%d+)/(%d+)"); if tonumber(a) < tonumber(b) then damaged = true end end
ok(damaged, "creatures batter a barricade")
local function hurtBarricade(missing)
	local list = {}
	for bar in hud(A).barricades:gmatch("[^,]+") do table.insert(list, bar) end
	for i, bar in ipairs(list) do local a, b = bar:match("(%d+)/(%d+)"); if tonumber(b) - tonumber(a) >= (missing or 1) then return S.Portals[i] end end
	return nil
end
local repairAmount = S.scaled("Novice", 4).repair
-- HIGH 1: a scratched barricade (less than one repair missing) refuses the repair and keeps the Timber.
do
	local scratched = hurtBarricade(1)
	ok(scratched ~= nil and hurtBarricade(repairAmount) == nil, "a barricade is only scratched so far")
	local bp0 = points(B)
	use(B, find(scratched.name .. " barricade"), "Repair (1 Timber)")
	ok(has(B.attrs.MinigameNotice, "scratches"), "scratch repair refused: " .. tostring(B.attrs.MinigameNotice))
	eq(points(B), bp0, "a refused repair earns nothing")
	eq(cmd(B, "state").items.Timber, 4, "a refused repair keeps the Timber")
end
for _ = 1, 120 do if hurtBarricade(repairAmount) then break end tick(0.5) end
local hurt = hurtBarricade(repairAmount)
ok(hurt ~= nil, "a barricade takes a full repair's worth of damage")
local carp = cmd(B, "state").xp.Carpentry
local bp = points(B)
use(B, find(hurt.name .. " barricade"), "Repair (1 Timber)")
eq(points(B), bp + S.Points.repair, "a repair earns points")
eq(cmd(B, "state").items.Timber, 3, "the repair cost 1 Timber")
-- A sound barricade refuses.
local sound
for i, bar in ipairs((function() local l = {} for b in hud(A).barricades:gmatch("[^,]+") do table.insert(l, b) end return l end)()) do
	local a, b = bar:match("(%d+)/(%d+)")
	if a == b then sound = S.Portals[i] end
end
if sound then
	use(B, find(sound.name .. " barricade"), "Repair (1 Timber)")
	ok(has(B.attrs.MinigameNotice, "already sound"), "sound barricade needs no repair")
end
-- Shields drop: strike the open portals down.
defend(S.FIRST_DROP)
local function openPortal()
	for entry in hud(A).portals:gmatch("[^,]+") do
		local id, hp, _, sh = entry:match("^(%a+):(%d+):(%d+):(%d)$")
		if sh == "0" and tonumber(hp) > 0 then return S.PortalById[id] end
	end
	return nil
end
local first = openPortal()
ok(first ~= nil, "a shield dropped after " .. S.FIRST_DROP .. "s")
-- D was idle for the whole time: removed with no reward.
for _ = 1, 90 do if D.attrs.MinigameGame ~= "Siege" then break end defend(1) end
eq(D.attrs.MinigameGame, "", "the AFK member was removed")
ok(has(D.attrs.MinigameNotice, "inactivity"), "AFK removal notice")
local logD = cmd(D, "state").minigames.log.Siege
eq(logD.played, 1, "the AFK match is logged")
eq(cmd(D, "state").minigames.commendations, 0, "AFK earns nothing")
-- Rejoin: B drops and returns with their points.
local bPoints = points(B)
drop(B)
leave(B)
defend(2)
local B2 = player(B.UserId)
join(B2)
eq(B2.attrs.MinigameGame, "Siege", "B rejoined the match")
eq(points(B2), bPoints, "B kept their points")
ok(has(B2.attrs.MinigameNotice, "Welcome back"), "rejoin notice")
B = B2
movers[B] = true
-- Away rule: C wanders off the ring.
movers[Cc] = nil
Cc.root.Position = keeper.Position + Vector3.new(400, 0, 0)
defend(MG.AWAY_GRACE + 1)
eq(Cc.attrs.MinigameGame, "", "C removed for leaving the ring")
ok(has(Cc.attrs.MinigameNotice, "left"), "away notice: " .. tostring(Cc.attrs.MinigameNotice) .. " t=" .. clock)
-- A and B seal all four portals.
ok(A.attrs.MinigameGame == "Siege", "A still defending: " .. tostring(A.attrs.MinigameNotice))
local strikes = 0
while true do
	if A.attrs.MinigameGame ~= "Siege" then break end
	local target = openPortal()
	if not target then break end
	use(A, find(target.name), "Strike portal")
	use(B, find(target.name), "Strike portal")
	strikes += 2
	-- keep the creatures off the Keeper and the members active
	for _, d in ipairs(bastion:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Creature") then use(A, d, "Strike") break end
	end
	heartbeat:Fire(0.1)
	if strikes > 400 then break end
end
ok(strikes < 400, "portals fall to steady strikes (" .. strikes .. ")")
eq(A.attrs.MinigameGame, "", "the match ended")
ok(has(A.attrs.MinigameNotice, "rifts are sealed"), "victory notice")
local sa = cmd(A, "state").minigames
eq(sa.commendations, S.Tiers[1].commendations, "A paid the novice Commendations")
eq(sa.log.Siege.won, 1, "A's win logged")
ok(sa.log.Siege.points >= S.MIN_POINTS, "A's points logged")
local sb = cmd(B, "state")
eq(sb.minigames.commendations, S.Tiers[1].commendations, "B (rejoined) paid")
ok(sb.xp.Carpentry > carp, "B's repair paid Carpentry XP")
local sc = cmd(Cc, "state").minigames
eq(sc.commendations, 0, "C (removed) unpaid")
eq(sc.log.Siege.played, 1, "C's match logged")
ok(has(lobbies().SiegeNovice, "idle"), "lobby idle again")
ok(not has(world:GetAttribute("MinigameMatches"), "Siege=4"), "match roster cleared")
local left = 0
for _, d in ipairs(bastion:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Creature") then left += 1 end end
eq(left, 0, "creatures cleared after the match")
eq(A.attrs.MinigameHud, "", "HUD cleared")
-- Tier gating: three Combat 30 players cannot start a Veteran match.
movers = {}
for _, p in ipairs({A, B, Cc}) do onPad(p, "SiegeVeteran pad") end
tick(0.5)
ok(has(lobbies().SiegeVeteran, "counting"), "veteran countdown")
tick(S.PAD_SECONDS + 0.5)
ok(A.attrs.MinigameGame ~= "Siege", "Combat 30 cannot launch a Veteran landing")
ok(has(A.attrs.MinigameNotice, "Combat 50"), "veteran refusal")
for _, p in ipairs({A, B, Cc}) do p.root.Position = Vector3.new(0, 10, 0) end
tick(1)
-- Siege loss: every member leaves and nobody returns.
for _, p in ipairs({A, B, Cc}) do onPad(p, "SiegeNovice pad") end
tick(S.PAD_SECONDS + 1)
eq(A.attrs.MinigameGame, "Siege", "second siege started " .. tostring(world:GetAttribute("MinigameLobbies")) .. " / " .. tostring(A.attrs.MinigameNotice))
for _, p in ipairs({A, B, Cc}) do drop(p) end
tick(MG.REJOIN_SECONDS + 2, 1)
ok(not has(world:GetAttribute("MinigameMatches"), "Siege=0,1") , "abandoned match ended")
ok(has(lobbies().SiegeNovice, "idle"), "lobby free after an abandoned match")
for _, p in ipairs({A, B, Cc}) do join(p) end

-- Tempest Haul: a Fishing 10 player is turned away, the angler hauls solo.
local minnow = seeded(9230, function(p) p.xp.Fishing = X[10] end)
join(minnow)
onPad(minnow, "Haul pad")
onPad(angler, "Haul pad")
tick(0.5)
ok(has(lobbies().Haul, "counting,2,"), "haul countdown with two")
tick(H.PAD_SECONDS + 0.5)
eq(angler.attrs.MinigameGame, "Haul", "angler aboard")
ok(minnow.attrs.MinigameGame ~= "Haul" and has(minnow.attrs.MinigameNotice, "Fishing 20"), "Fishing 10 refused")
minnow.root.Position = Vector3.new(0, 10, 0)
local hh = hud(angler)
eq(hh.phase, "energy", "energy phase")
eq(hh.energy, "100", "full energy")
eq(hh.hull, "100", "sound hull")
eq(hh.masts, "1,1", "masts sound")
local spray = find("Stormfish spray")
local brazier, harpoonPart = find("Storm brazier"), find("Harpoon mount")
-- Guards.
use(angler, brazier, "Cook stormfish")
ok(has(angler.attrs.MinigameNotice, "Catch a raw stormfish"), "nothing to cook")
use(angler, find("Cannon 1"), "Load cannon")
ok(has(angler.attrs.MinigameNotice, "Bring stormfish"), "nothing to load")
use(angler, harpoonPart, "Harpoon the Leviathan")
ok(has(angler.attrs.MinigameNotice, "out of reach"), "harpoon waits for the surfacing")
eq(points(angler), 0, "refused actions earn nothing")
for _ = 1, H.CARRY do use(angler, spray, "Catch stormfish") end
eq(hud(angler).raw, tostring(H.CARRY), "arms full of stormfish")
use(angler, spray, "Catch stormfish")
ok(has(angler.attrs.MinigameNotice, "arms are full"), "carry cap")
eq(points(angler), H.CARRY * H.Points.catch, "catch points")
use(angler, brazier, "Cook stormfish")
eq(hud(angler).cooked, "1", "a cooked stormfish")
local e0 = tonumber(hud(angler).energy)
use(angler, find("Cannon 1"), "Load cannon")
ok(tonumber(hud(angler).energy) < e0, "a loaded cannon drains energy")
eq(points(angler), H.CARRY * 10 + 10 + H.Points.loadCooked, "cooked load points")
use(angler, find("Cannon 2"), "Load cannon")
eq(points(angler), H.CARRY * 10 + 10 + 20 + H.Points.loadRaw, "raw loads pay less")
-- Loop until the Leviathan surfaces, tending masts and fires.
local loops = 0
local function tend()
	local h = hud(angler)
	local m1, m2 = h.masts:match("(%d),(%d)")
	if m1 == "0" then use(angler, find("Mast 1"), "Repair mast") end
	if m2 == "0" then use(angler, find("Mast 2"), "Repair mast") end
	if tonumber(h.fires) > 0 then
		for i = 1, H.FIRE_CAP do use(angler, find("Deck fire " .. i), "Douse fire") end
	end
end
local repaired, doused = false, false
while hud(angler).phase == "energy" and loops < 200 do
	loops += 1
	use(angler, spray, "Catch stormfish")
	use(angler, brazier, "Cook stormfish")
	heartbeat:Fire(0.1)
	local before = hud(angler)
	local mastsBefore, firesBefore = before.masts, tonumber(before.fires)
	tend()
	if mastsBefore ~= "1,1" then repaired = true end
	if firesBefore > 0 then doused = true end
	use(angler, find(if hud(angler).masts:sub(1, 1) == "1" then "Cannon 1" else "Cannon 2"), "Load cannon")
end
ok(loops < 200, "the cannons drain the Leviathan (" .. loops .. " loops)")
eq(hud(angler).phase, "vulnerable", "the Leviathan surfaces")
ok(repaired, "a squall surge cracked a mast that was repaired")
ok(doused, "a lightning fire was doused")
use(angler, find("Cannon 1"), "Load cannon")
ok(has(angler.attrs.MinigameNotice, "harpoon"), "cannons stand down while it surfaces")
local hauls = 0
while angler.attrs.MinigameGame == "Haul" and hauls < 50 do
	hauls += 1
	use(angler, harpoonPart, "Harpoon the Leviathan")
end
ok(hauls <= math.ceil(H.ESSENCE / H.essenceHit(1)) + 1, "harpoons drain the essence (" .. hauls .. ")")
eq(angler.attrs.MinigameGame, "", "haul over")
ok(has(angler.attrs.MinigameNotice, "driven off"), "haul victory notice")
local ah = cmd(angler, "state")
eq(ah.minigames.log.Haul.won, 1, "haul win logged")
ok(ah.minigames.rolls >= 1, "solo haul banks a roll (" .. ah.minigames.rolls .. ")")
ok(ah.minigames.log.Haul.points >= H.MIN_POINTS, "haul points logged")
ok(ah.xp.Fishing > X[30] and ah.xp.Cooking > X[30] and ah.xp.Carpentry > X[20], "Fishing, Cooking and Carpentry XP paid")
do
	local last
	for i = #bridgeCalls, 1, -1 do
		local c = bridgeCalls[i]
		if c.op == "minigame" and c.payload.action == "settle" and c.player == angler then last = c.payload break end
	end
	ok(last and last.game == "Haul" and last.won == true and last.partySize == 1, "solo settlement payload")
	eq(H.rolls(last.points, true, 1), ah.minigames.rolls, "solo rolls follow the reduced rule")
end
-- Haul loss: the hull burns while the angler only mends masts.
onPad(angler, "Haul pad")
tick(H.PAD_SECONDS + 1)
eq(angler.attrs.MinigameGame, "Haul", "second haul")
movers[angler] = true
local lost = false
for _ = 1, 400 do
	tick(1, 1)
	if angler.attrs.MinigameGame ~= "Haul" then lost = true break end
	local h = hud(angler)
	if h.masts and h.masts ~= "1,1" then
		use(angler, find(if h.masts:sub(1, 1) == "0" then "Mast 1" else "Mast 2"), "Repair mast")
	end
end
ok(lost, "the burning hull sinks the haul")
ok(has(angler.attrs.MinigameNotice, "haul is lost"), "loss notice")
local al = cmd(angler, "state").minigames
eq(al.log.Haul.played, 2, "loss logged")
eq(al.log.Haul.won, 1, "losses are not wins")
eq(al.rolls, ah.minigames.rolls, "a lost haul pays no roll")
movers = {}
-- Source sanity: world ferry, project wiring, bridge hooks.
do
	local worldSource = fs.readFile("world.server.lua")
	ok(has(worldSource, 'ServerStorage:FindFirstChild("IsleMinigameAccess")'), "world ferry asks the minigame gate")
	ok(has(worldSource, '"Waypoint_SkybreachFerry"'), "ferry waypoint anchor")
	ok(has(worldSource, "-- End Minigames section."), "world section delimited")
	local project = fs.readFile("default.project.json")
	ok(has(project, '"Minigames": { "$path": "minigames.server.lua" }'), "Minigames script registered")
	ok(has(fs.readFile("verify.luau"), 'Minigames = "minigames.server.lua"'), "packaging check knows the script")
	ok(has(fs.readFile("scripts/build.sh"), "verify-minigames.luau") and has(fs.readFile("build.ps1"), "verify-minigames.luau"), "both build scripts run this suite")
	local server = fs.readFile("server.server.lua")
	ok(has(server, 'elseif op=="minigame" then'), "bridge op wired")
	ok(has(server, "minigames=Minigames.state(player,p)"), "snapshot key wired")
end
print("PASS: " .. (checks - partC) .. " minigame lifecycle assertions.")

------------------------------------------------------------------------------
-- Part E: QC regressions, driven through minigames.server.lua and the live
-- journal at the real action cadence (use() = 1.2 s per action).
------------------------------------------------------------------------------
local partE = checks
local CL = Data.CommissionsLogs
local function step(p, part, action) use(p, part, action); heartbeat:Fire(1.2) end
local function lastSettle(p, filter)
	for i = #bridgeCalls, 1, -1 do
		local c = bridgeCalls[i]
		if c.player == p and c.op == "minigame" and c.payload.action == "settle" and (not filter or filter(c.payload)) then return c.payload end
	end
	return nil
end
local function xpOf(p, skills)
	local xp = cmd(p, "state").xp
	local n = 0
	for _, s in ipairs(skills) do n += xp[s] or 0 end
	return n
end
local function barricadeHpOf(p, i)
	local list = {}
	for bar in tostring(hud(p).barricades):gmatch("[^,]+") do table.insert(list, bar) end
	local a, b = list[i]:match("(%d+)/(%d+)")
	return tonumber(a), tonumber(b)
end
local HAUL_SKILLS ={"Fishing", "Cooking", "Carpentry"}
local qcLines = {}
-- One haul member's play at the real cadence: tend fires/masts, catch, cook,
-- load; harpoon once the Leviathan surfaces after stallUntil seconds.
local function playHaul(p, stallUntil, limit)
	local t0 = clock
	local spray, brazierPart, harpoonPart = find("Stormfish spray"), find("Storm brazier"), find("Harpoon mount")
	while p.attrs.MinigameGame == "Haul" and clock - t0 < (limit or 1e9) do
		local h = hud(p)
		local m1, m2 = h.masts:match("(%d),(%d)")
		local fire
		if tonumber(h.fires) > 0 then for i = 1, H.FIRE_CAP do if not fire and find("Deck fire " .. i).Transparency < 1 then fire = i end end end
		if fire then step(p, find("Deck fire " .. fire), "Douse fire")
		elseif m1 == "0" then step(p, find("Mast 1"), "Repair mast")
		elseif m2 == "0" then step(p, find("Mast 2"), "Repair mast")
		elseif h.phase == "vulnerable" and clock - t0 > stallUntil then step(p, harpoonPart, "Harpoon the Leviathan")
		elseif h.phase == "vulnerable" then
			if tonumber(h.raw) + tonumber(h.cooked) < H.CARRY then step(p, spray, "Catch stormfish")
			elseif tonumber(h.raw) > 0 then step(p, brazierPart, "Cook stormfish")
			else tick(1.2, 1.2) end
		elseif tonumber(h.cooked) == 0 and tonumber(h.raw) < H.CARRY then step(p, spray, "Catch stormfish")
		elseif tonumber(h.raw) > 0 then step(p, brazierPart, "Cook stormfish")
		else step(p, find("Cannon 1"), "Load cannon") end
	end
	return clock - t0
end
local function startHaulWith(list)
	for _, p in ipairs(list) do onPad(p, "Haul pad") end
	tick(H.PAD_SECONDS + 1)
	for _, p in ipairs(list) do p.root.Position = p.root.Position + Vector3.new(0, 0, 0) end
end

-- HIGH 1: barricade repair farm. Riftlings are left on one barricade and a
-- member repairs it at the real cadence for a whole match.
do
	for lvl = 1, 99 do
		ok(S.repairXp(lvl) <= math.max(1, MG.soloCarpentryXpPerTimber(lvl) * S.REPAIR_TIMBER * MG.SOCIAL_BONUS) + 0.5, "repair XP never beats solo Carpentry per Timber at " .. lvl)
	end
	ok(S.REPAIR_POINT_CAP < S.MIN_POINTS, "repairs alone cannot reach the point minimum")
	ok(not S.canRepair(399, 400, 120) and S.canRepair(280, 400, 120), "repairs need a full repair's worth of damage")
	local farmers = {}
	for i = 1, 3 do
		farmers[i] = seeded(9500 + i, function(p) p.xp.Combat = X[30]; p.xp.Carpentry = X[30]; p.items.Timber = 5000 end)
		join(farmers[i])
		onPad(farmers[i], "SiegeNovice pad")
	end
	tick(S.PAD_SECONDS + 1)
	local F = farmers[1]
	eq(F.attrs.MinigameGame, "Siege", "repair-farm siege started")
	local carp0 = cmd(F, "state").xp.Carpentry
	local timber0 = cmd(F, "state").items.Timber
	local t0 = clock
	movers[farmers[2]], movers[farmers[3]] = true, true
	local farmed = find(S.Portals[4].name .. " barricade")
	local maxPoints = 0
	while F.attrs.MinigameGame == "Siege" and clock - t0 < 800 do
		local hp, max = barricadeHpOf(F, 4)
		if hp < max then step(F, farmed, "Repair (1 Timber)") else tick(1.2, 1.2) end
		maxPoints = math.max(maxPoints, points(F))
		for k = 2, 3 do
			for _, d in ipairs(bastion:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("Creature") and (d.Position - farmed.Position).Magnitude > 12 then use(farmers[k], d, "Strike"); heartbeat:Fire(1.2) break end
			end
		end
	end
	local elapsed = clock - t0
	eq(F.attrs.MinigameGame, "", "the farmed match ended")
	local s = cmd(F, "state")
	local gained = s.xp.Carpentry - carp0
	local spent = timber0 - s.items.Timber
	ok(spent >= 1, "the farmer did repair (" .. spent .. " Timber)")
	ok(gained <= S.repairXp(30) * S.REPAIR_XP_LIMIT, "Carpentry XP capped by the per-match repair budget (" .. gained .. ")")
	ok(gained <= spent * MG.soloCarpentryXpPerTimber(30) * MG.SOCIAL_BONUS + 1, "repairs never pay more Carpentry XP per Timber than solo building")
	ok(maxPoints <= S.REPAIR_POINT_CAP, "repair-only points stop at the repair cap (" .. maxPoints .. ")")
	ok(maxPoints < S.MIN_POINTS, "repairs alone never reach the minimum")
	table.insert(qcLines, string.format("Siege repair farm (Carpentry 30, %.0f s): %d Timber -> %d Carpentry XP = %.0f XP/h (was ~142,700 XP/h)", elapsed, spent, gained, gained * 3600 / elapsed))
	for _, p in ipairs(farmers) do p.root.Position = Vector3.new(0, 10, 0); movers[p] = nil end
end

-- HIGH 2: Tempest Haul XP is paid on measured time; rolls are capped by match time.
do
	-- Pure rules.
	local L30 = {Fishing = 30, Cooking = 30, Carpentry = 30}
	eq(H.actionXp("catch", L30, 1.1).Fishing, H.xpPerSecond(30) * 1.1, "a 1.1 s catch pays 1.1 s of XP")
	eq(H.actionXp("catch", L30, 99).Fishing, H.xpPerSecond(30) * H.Model.catch, "a slow catch is capped at its model seconds")
	eq(H.actionXp("cook", L30, -4).Cooking, 0, "negative time pays nothing")
	eq(H.maxRolls(900, false), H.maxRolls(H.Model.gameSeconds, false), "stalling past the model game adds no rolls")
	ok(H.maxRolls(120, false) < H.maxRolls(H.Model.gameSeconds, false), "short games cap fewer rolls")
	ok(H.maxRolls(900, true) < H.maxRolls(900, false), "solo cap is reduced")
	eq(H.rolls(1e6, true, 4, 900), H.maxRolls(900, false), "huge points still capped by time")
	-- Server clamp: the XP of a settlement fits XP_RATIO x solo per second played.
	local clampP = seeded(9610, function(p) p.xp.Fishing = X[30]; p.xp.Cooking = X[30]; p.xp.Carpentry = X[30] end)
	local before = xpOf(clampP, HAUL_SKILLS)
	op(clampP, {action = "settle", game = "Haul", points = 0, won = false, partySize = 1, seconds = 100, xp = {Fishing = 1e6, Cooking = 1e6, Carpentry = 1e6}})
	local paid = xpOf(clampP, HAUL_SKILLS) - before
	ok(paid <= H.xpPerSecond(30) * (100 + H.Model.catch) + 3, "server caps Haul XP at the intended rate (" .. paid .. ")")
	ok(paid >= H.xpPerSecond(30) * 100 * 0.95, "the full rate is still paid")
	-- Real cadence, normal play (harpoon as soon as it surfaces).
	local L = 30
	local solo = MG.soloFishCookXpPerHour(L)
	local fast = seeded(9600, function(p) p.xp.Fishing = X[L]; p.xp.Cooking = X[L]; p.xp.Carpentry = X[L] end)
	join(fast)
	startHaulWith({fast})
	eq(fast.attrs.MinigameGame, "Haul", "cadence haul started")
	local x0 = xpOf(fast, HAUL_SKILLS)
	local secs = playHaul(fast, 0)
	local rate = (xpOf(fast, HAUL_SKILLS) - x0) * 3600 / secs
	within(rate / solo, 0.5, MG.SOCIAL_BONUS * 1.1, "Haul XP/h at the 1.2 s cadence vs solo fish+cook")
	table.insert(qcLines, string.format("Haul real cadence (L%d, %.0f s): %.0f XP/h = %.2fx solo (was 2.12x)", L, secs, rate, rate / solo))
	fast.root.Position = Vector3.new(0, 10, 0)
	-- Real cadence, stalling the Leviathan to the end of the clock for points.
	local staller = seeded(9601, function(p) p.xp.Fishing = X[L]; p.xp.Cooking = X[L]; p.xp.Carpentry = X[L] end)
	join(staller)
	startHaulWith({staller})
	local r0 = cmd(staller, "state").minigames.rolls
	x0 = xpOf(staller, HAUL_SKILLS)
	secs = playHaul(staller, H.TIME_LIMIT - 120)
	local st = cmd(staller, "state")
	eq(st.minigames.log.Haul.won, 1, "the staller still won")
	local rolls = st.minigames.rolls - r0
	ok(rolls <= H.maxRolls(secs, true), "stalled haul rolls capped by time (" .. rolls .. ")")
	local stallPerHour = rolls * 3600 / (secs + H.Model.lobbySeconds)
	ok(stallPerHour <= H.rollsPerHour(true), "stalling earns no more rolls/h than the solo model (" .. string.format("%.1f", stallPerHour) .. ")")
	rate = (xpOf(staller, HAUL_SKILLS) - x0) * 3600 / secs
	ok(rate / solo <= MG.SOCIAL_BONUS * 1.1, "stalling does not raise XP/h")
	local payload = lastSettle(staller, function(pl) return pl.won == true end)
	ok(payload and payload.seconds >= H.TIME_LIMIT - 130, "settlement reports the stalled match length")
	table.insert(qcLines, string.format("Haul staller (solo, %.0f s): %d rolls = %.1f rolls/h incl. lobby (was 47.2; solo model %.1f), %.2fx solo XP", secs, rolls, stallPerHour, H.rollsPerHour(true), rate / solo))
	staller.root.Position = Vector3.new(0, 10, 0)
end

-- MEDIUM 1: a disconnecting member's XP is paid when they leave (XP only);
-- a failed call keeps it for later; a rejoin keeps the points.
do
	local crew = seeded(9620, function(p) p.xp.Fishing = X[30]; p.xp.Cooking = X[30] end)
	local mate = seeded(9621, function(p) p.xp.Fishing = X[30] end)
	join(crew); join(mate)
	startHaulWith({crew, mate})
	movers[mate] = true
	eq(crew.attrs.MinigameGame, "Haul", "crew aboard")
	local spray = find("Stormfish spray")
	for _ = 1, 3 do step(crew, spray, "Catch stormfish") end
	local pts = points(crew)
	local x0 = xpOf(crew, HAUL_SKILLS)
	local played0 = cmd(crew, "state").minigames.log.Haul.played
	drop(crew)
	local x1 = xpOf(crew, HAUL_SKILLS)
	ok(x1 > x0, "XP paid as the member leaves (" .. (x1 - x0) .. ")")
	local xpCall = lastSettle(crew)
	ok(xpCall and xpCall.xpOnly == true, "departure settlement is XP-only")
	eq(cmd(crew, "state").minigames.log.Haul.played, played0, "an XP-only settlement writes no log entry")
	-- Rejoin: points kept, XP not paid twice.
	leave(crew)
	local crew2 = player(crew.UserId)
	join(crew2)
	eq(crew2.attrs.MinigameGame, "Haul", "crew rejoined")
	eq(points(crew2), pts, "points kept across the rejoin")
	-- Journal unreachable on the next departure: the XP stays on the record.
	for _ = 1, 2 do step(crew2, spray, "Catch stormfish") end
	local x2 = xpOf(crew2, HAUL_SKILLS)
	ok(x2 == x1, "no XP paid twice on rejoin")
	bridgeDown = true
	drop(crew2)
	bridgeDown = false
	eq(xpOf(crew2, HAUL_SKILLS), x2, "a failed settlement pays nothing")
	leave(crew2)
	local crew3 = player(crew.UserId)
	join(crew3)
	eq(crew3.attrs.MinigameGame, "Haul", "crew rejoined again")
	drop(crew3)
	local x3 = xpOf(crew3, HAUL_SKILLS)
	ok(x3 > x2, "the XP kept after the failed call is paid on the next settlement (" .. (x3 - x2) .. ")")
	leave(crew3)
	local back = player(crew.UserId)
	join(back)
	-- Clean up: the mate leaves too; the match ends once nobody can return.
	movers[mate] = nil
	drop(mate)
	drop(back)
	tick(MG.REJOIN_SECONDS + 2, 1)
	ok(not has(lobbies().Haul, "running"), "haul over after everyone left")
	join(mate); join(back)
end

-- MEDIUM 2: an alt that idles out does not lift the solo penalty.
do
	local main = seeded(9630, function(p) p.xp.Fishing = X[30]; p.xp.Cooking = X[30]; p.xp.Carpentry = X[30] end)
	local alt = seeded(9631, function(p) p.xp.Fishing = X[20] end)
	join(main); join(alt)
	startHaulWith({main, alt})
	eq(alt.attrs.MinigameGame, "Haul", "alt aboard")
	playHaul(main, 0)
	ok(alt.attrs.MinigameGame ~= "Haul", "the idle alt was removed")
	local payload = lastSettle(main, function(pl) return pl.won == true end)
	ok(payload ~= nil, "main won the haul")
	eq(payload.partySize, 1, "settle-time party counts members still present with the minimum")
	local paidRolls = cmd(main, "state").minigames.rolls
	eq(paidRolls, H.rolls(payload.points, true, 1, payload.seconds), "solo penalty applied")
	main.root.Position = Vector3.new(0, 10, 0)
	alt.root.Position = Vector3.new(0, 10, 0)
end

-- MEDIUM 3: Siege rewards scale with time and the party, and need a recent action.
do
	eq(S.requiredPoints(30, 0), S.MIN_POINTS, "short stay: the floor")
	eq(S.requiredPoints(720, 0), math.floor(S.MIN_POINTS_PER_MINUTE * 12), "a full match needs points per minute")
	eq(S.requiredPoints(60, 800), math.floor(S.MEDIAN_SHARE * 800), "a share of the median member")
	eq(MG.median({1, 9, 3}), 3, "median odd")
	eq(MG.median({1, 9, 3, 5}), 4, "median even")
	eq(S.reward("Novice", 60, true, 70), 0, "below the required points: nothing")
	eq(S.reward("Novice", 70, true, 70), S.Tiers[1].commendations, "at the required points: paid")
	local vet = seeded(9640, function(p) p.xp.Combat = X[40] end)
	local base = {action = "settle", game = "Siege", tier = "Novice", won = true, partySize = 5}
	local function settleWith(extra) local t = table.clone(base); for k, v in pairs(extra) do t[k] = v end; return op(vet, t) end
	eq(settleWith({points = 55, seconds = 700}).paid, 0, "55 points over 700 s is not enough")
	ok(has(vet.last.message, "/ " .. S.requiredPoints(700, 0)), "refusal names the required points")
	eq(settleWith({points = 80, seconds = 300, required = 120}).paid, 0, "the party's median raises the bar")
	eq(settleWith({points = 200, seconds = 300, recent = false}).paid, 0, "no recent action: no reward")
	ok(has(vet.last.message, "no action"), "recent-action refusal explained")
	eq(settleWith({points = 200, seconds = 300, required = 120, recent = true}).paid, S.Tiers[1].commendations, "a real contributor is paid")
	-- The real match in Part C sent the scaled requirement and the recent flag.
	local aWin = lastSettle(A, function(pl) return pl.game == "Siege" and pl.won == true end)
	ok(aWin and aWin.required >= S.MIN_POINTS and aWin.recent == true, "live siege settlement carries the required points and recent flag")
end

-- LOW 1 + LOW 2: a rejoin keeps the idle clock (short grace only) and waits for the body.
do
	local idler = seeded(9650, function(p) p.xp.Fishing = X[30] end)
	join(idler)
	startHaulWith({idler})
	eq(idler.attrs.MinigameGame, "Haul", "idler aboard")
	step(idler, find("Stormfish spray"), "Catch stormfish")
	tick(40, 1)
	drop(idler)
	leave(idler)
	tick(22, 1)
	local again = player(idler.UserId)
	local body = again.Character
	local pivoted = false
	again.Character = {Parent = true, FindFirstChild = function() return nil end, FindFirstChildOfClass = function() return nil end,
		WaitForChild = function() return nil end, PivotTo = function() pivoted = true end}
	join(again)
	ok(again.attrs.MinigameGame ~= "Haul" and not pivoted, "no rejoin while the character has no root part")
	again.Character = body
	again.CharacterAdded:Fire(body)
	eq(again.attrs.MinigameGame, "Haul", "rejoined once the root part exists")
	ok((again.root.Position - find("Storm brazier").Position).Magnitude < 60, "moved onto the deck")
	tick(MG.REJOIN_GRACE - 2, 1)
	eq(again.attrs.MinigameGame, "Haul", "inside the rejoin grace")
	tick(4, 1)
	eq(again.attrs.MinigameGame, "", "the old idle clock applies after the grace")
	ok(has(again.attrs.MinigameNotice, "inactivity"), "idle removal after a rejoin")
	again.root.Position = Vector3.new(0, 10, 0)
end

-- LOW 5: a full Squall Cache bank never drops a roll.
do
	local hoarder = seeded(9660, function(p) p.xp.Fishing = X[40]; p.minigames = {commendations = 0, rolls = 498, unlocks = {}, title = "", log = {}} end)
	eq(op(hoarder, {action = "info"}).rollRoom, 2, "info reports the bank room")
	local coins0 = cmd(hoarder, "state").coins
	local r = op(hoarder, {action = "settle", game = "Haul", points = 5000, won = true, partySize = 4, seconds = H.Model.gameSeconds})
	ok(r.paid > 2, "the haul paid more rolls than the bank holds (" .. r.paid .. ")")
	local s = cmd(hoarder, "state")
	eq(s.minigames.rolls, 500, "bank filled to 500")
	ok(s.coins > coins0, "overflow rolls opened on the spot")
	ok(has(hoarder.last.message, "opened on the spot"), "overflow explained")
	-- A nearly full bank is turned away at the pad.
	join(hoarder)
	onPad(hoarder, "Haul pad")
	tick(H.PAD_SECONDS + 1)
	ok(hoarder.attrs.MinigameGame ~= "Haul" and has(hoarder.attrs.MinigameNotice, "bank is nearly full"), "full bank refused at launch")
	hoarder.root.Position = Vector3.new(0, 10, 0)
	tick(1)
end

-- §44 QC L4 / M5 / L1: the return ferry is a tagged travel beacon (the client
-- finds beacons by CollectionService tag) with the dais colliders and the
-- prompt on an attachment in front of the dais.
do
	local beacon = find("Return ferry beacon")
	local tagged = mgServices.CollectionService.tagged.TravelBeacon or {}
	ok(#tagged == 1 and tagged[1] == beacon and beacon:GetAttribute("TravelBeacon") == "ferry", "the return ferry carries the TravelBeacon tag")
	local plinth, pylons = nil, 0
	for _, d in ipairs(bastion:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Beacon plinth" then plinth = d end
		if d:IsA("BasePart") and d.Name == "Beacon pylon" and d.CanCollide and d.Transparency == 1 then pylons += 1 end
	end
	ok(plinth ~= nil and plinth.Shape == roblox.Enum.PartType.Cylinder and plinth.CanCollide and plinth.Transparency == 1
		and math.abs(plinth.Size.Y - 4.9) < 1e-3 and math.abs(plinth.Size.X - 0.95) < 1e-3, "the ferry dais has its 4.9 x 0.95 cylinder base collider")
	ok(plinth ~= nil and math.abs(plinth.Position.Y - plinth.Size.X / 2 - (beacon.Position.Y - 3 + 0.5)) < 1e-3, "the base collider stands on the plaza")
	eq(pylons, 4, "the ferry dais has four pylon colliders")
	local q = promptOn(beacon, "Return to the Guild Terrace")
	ok(q.Parent:IsA("Attachment") and q.Parent.Name == "Beacon prompt", "the ferry prompt hangs on its attachment")
	local at = (beacon.CFrame * q.Parent.CFrame).Position
	ok(math.abs(at.Y - (beacon.Position.Y - 2.5 + 1.5)) < 1e-3 and Vector3.new(at.X - beacon.Position.X, 0, at.Z - beacon.Position.Z).Magnitude > 2.95, "the ferry prompt sits in front of the dais at waist height")
end

-- LOW 6: the return ferry passes the travel gate and zeroes velocity.
do
	local rider = fighters[1]
	local beacon = find("Return ferry beacon")
	mgObjects.IsleTravelGate = nil
	rider.root.AssemblyLinearVelocity = Vector3.new(0, -80, 0)
	use(rider, beacon, "Return to the Guild Terrace")
	ok((rider.root.Position - beacon.Position).Magnitude < 15 and has(rider.attrs.MinigameNotice, "cannot carry"), "no gate: the ferry refuses")
	mgObjects.IsleTravelGate = {Invoke = function() return "You can't travel mid-fight. Catch your breath first." end}
	use(rider, beacon, "Return to the Guild Terrace")
	ok((rider.root.Position - beacon.Position).Magnitude < 15 and has(rider.attrs.MinigameNotice, "mid-fight"), "the gate's refusal is shown")
	mgObjects.IsleTravelGate = {Invoke = function() return true end}
	use(rider, beacon, "Return to the Guild Terrace")
	ok((rider.root.Position - beacon.Position).Magnitude > 100, "the ferry carries the rider home")
	eq(rider.root.AssemblyLinearVelocity.Magnitude, 0, "velocity zeroed after the ferry")
	mgObjects.IsleTravelGate = nil
end

-- Collection Log: minigame uniques granted after the first load credit the
-- Minigames tab through collect() (shop purchase and Squall Cache roll).
do
	local L = CL.log()
	for _, id in ipairs({"LumenwardHauberk", "LumenwardWarhelm", "TidebreakerRod", "StormcallerHood"}) do eq(L.Of[id], "Minigames", id .. " is a Minigames log entry") end
	ok(L.Of.SquallpupPet ~= nil, "the Squallpup is a log entry")
	local fan = seeded(9670, function(p) p.xp.Combat = X[40]; p.xp.Fishing = X[40]; p.minigames = {commendations = 1000, rolls = 1, unlocks = {}, title = "", log = {}} end)
	cmd(fan, "mgBuy", "LumenwardHauberk")
	rolls = {0.5, 0.5, 0.5, 0, 0, 0, 0, 0, 0}
	ok(has(cmd(fan, "mgRoll", "1").message, "Tidebreaker"), "a 0 roll pays the uniques")
	rolls = {}
	leave(fan)
	local counts = data["p" .. fan.UserId].profile.colLog.counts
	eq(counts.LumenwardHauberk, 1, "a bought Lumenward piece credits the log")
	eq(counts.TidebreakerRod, 1, "a rolled Tidebreaker Rod credits the log")
	eq(counts.StormcallerHood, 1, "a rolled Stormcaller piece credits the log")
	eq(counts.SquallpupPet, 1, "a rolled Squallpup credits the log")
end
for _, line in ipairs(qcLines) do print("  " .. line) end
print("PASS: " .. (checks - partE) .. " minigame QC regression assertions.")

------------------------------------------------------------------------------
-- Part D: Hunt › Minigames and the in-game HUD.
------------------------------------------------------------------------------
local partD = checks
local UH = require("./tools/ui-harness")
local function ledger(extra)
	local m = {commendations = 260, rolls = 3, unlocks = {"TitleKeeperward"}, title = "TitleKeeperward",
		log = {Siege = {played = 12, won = 9, points = 1400, best = 210, paid = 41}, Haul = {played = 5, won = 5, points = 4100, best = 1100, paid = 14}},
		lamps = {Combat = 23370, Ranged = 23370, Magic = 23370, Prayer = 9348, Slayer = 11685}}
	for k, v in pairs(extra or {}) do m[k] = v end
	return m
end
local function atlas(size, mutate)
	local snap = UH.snapshot({xp = {Combat = X[40], Fishing = X[30]}})
	snap.minigames = ledger()
	if mutate then mutate(snap) end
	local ui = UH.runAtlas(size, {snapshot = snap})
	UH.press(UH.find(ui.gui, "AtlasButton"))
	return ui
end
local function open(ui)
	UH.press(ui.tabs:FindFirstChild("HuntButton"))
	UH.press(UH.find(ui.scroll, "SectionMinigames"))
end
local function viewOf(ui, name) UH.press(UH.find(ui.scroll, "MinigameView" .. name)) end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui)
	eq(#ui.warnings, 0, "Minigames page renders" .. tag)
	for _, v in ipairs({"Lobbies", "Shop", "Caches", "Log"}) do ok(UH.find(ui.scroll, "MinigameView" .. v) ~= nil, v .. " view button" .. tag) end
	ok(UH.find(ui.scroll, "MinigamesSummary") ~= nil, "summary card" .. tag)
	ok(UH.find(ui.scroll, "MinigameSiege") ~= nil and UH.find(ui.scroll, "MinigameHaul") ~= nil, "game cards" .. tag)
	viewOf(ui, "Shop")
	eq(#ui.warnings, 0, "shop view" .. tag)
	for _, e in ipairs(MG.Shop) do ok(UH.find(ui.scroll, "MinigameShop" .. e.id) ~= nil, e.id .. " card" .. tag) end
	viewOf(ui, "Caches")
	eq(#ui.warnings, 0, "caches view" .. tag)
	ok(UH.find(ui.scroll, "MinigameCache") ~= nil, "cache card" .. tag)
	for _, u in ipairs(H.Cache.uniques) do ok(UH.find(ui.scroll, "MinigameUnique" .. u.item) ~= nil, u.item .. " unique" .. tag) end
	viewOf(ui, "Log")
	eq(#ui.warnings, 0, "log view" .. tag)
	for _, g in ipairs(MG.Order) do ok(UH.find(ui.scroll, "MinigameLog" .. g) ~= nil, g .. " log card" .. tag) end
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	open(ui)
	local text = texts(ui.scroll)
	ok(has(text, "Skybreach Siege") and has(text, "Tempest Haul"), "both games listed")
	ok(has(text, "260 Commendations"), "commendations shown")
	ok(has(text, "Novice Landing") and has(text, "Elite Landing"), "landings listed")
	ok(has(text, "Squall Leviathan") and has(text, "Lumen Keeper"), "bosses named")
	viewOf(ui, "Shop")
	UH.press(UH.find(ui.scroll, "MinigameBuyLumenwardHauberk"))
	eq(ui.sent[#ui.sent][1], "mgBuy", "buy verb")
	eq(ui.sent[#ui.sent][2], "LumenwardHauberk", "buy names the piece")
	UH.press(UH.find(ui.scroll, "MinigameBuyLampCombat"))
	eq(ui.sent[#ui.sent][2], "LampCombat", "lamp purchase")
	ok(has(texts(ui.scroll), "23,370"), "lamp XP preview shown")
	local sent = #ui.sent
	UH.press(UH.find(ui.scroll, "MinigameBuyTitleRiftsealer"))
	eq(#ui.sent, sent, "an unaffordable title stays local")
	UH.press(UH.find(ui.scroll, "MinigameWearTitleKeeperward"))
	eq(ui.sent[#ui.sent][1], "mgTitle", "title verb")
	eq(ui.sent[#ui.sent][2], "none", "the worn title hides")
	viewOf(ui, "Caches")
	UH.press(UH.find(ui.scroll, "MinigameRollOne"))
	eq(ui.sent[#ui.sent][1], "mgRoll", "roll verb")
	eq(ui.sent[#ui.sent][2], "1", "open one")
	UH.press(UH.find(ui.scroll, "MinigameRollAll"))
	eq(ui.sent[#ui.sent][2], "all", "open all")
	viewOf(ui, "Log")
	local logText = texts(ui.scroll)
	ok(has(logText, "12 played") and has(logText, "9 won"), "siege log")
	ok(has(logText, "41"), "commendations earned logged")
end
do
	-- Empty / malformed ledgers.
	local ui = atlas(roblox.Vector2.new(844, 390), function(snap) snap.minigames = ledger({rolls = 0, commendations = 0}) end)
	open(ui)
	viewOf(ui, "Caches")
	local sent = #ui.sent
	UH.press(UH.find(ui.scroll, "MinigameRollOne"))
	eq(#ui.sent, sent, "no rolls: nothing sent")
	viewOf(ui, "Shop")
	UH.press(UH.find(ui.scroll, "MinigameBuyLampCombat"))
	eq(#ui.sent, sent, "no Commendations: nothing sent")
	ui = atlas(roblox.Vector2.new(730, 303), function(snap) snap.minigames = nil end)
	open(ui)
	eq(#ui.warnings, 0, "missing ledger tolerated")
	for _, v in ipairs({"Shop", "Caches", "Log", "Lobbies"}) do viewOf(ui, v); eq(#ui.warnings, 0, "missing ledger on " .. v) end
	ui = atlas(roblox.Vector2.new(730, 303), function(snap)
		snap.minigames = {commendations = "lots", rolls = {}, unlocks = 4, title = 7, log = "x", lamps = 3}
	end)
	open(ui)
	eq(#ui.warnings, 0, "malformed ledger tolerated")
	for _, v in ipairs({"Shop", "Caches", "Log", "Lobbies"}) do viewOf(ui, v); eq(#ui.warnings, 0, "malformed ledger on " .. v) end
end
do
	-- In-game HUD.
	for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(730, 303)}) do
		local ui = atlas(size)
		local p = ui.player
		local hudFrame = ui.gui:FindFirstChild("MinigameHud")
		ok(hudFrame ~= nil and not hudFrame.Visible, "HUD hidden outside a match")
		p:SetAttribute("MinigameHud", "game=Siege;points=34;min=50;time=412;players=6;tier=Veteran;keeper=1800/2400;portals=Cinder:0:900:0,Gale:450:900:0,Rime:900:900:1,Gloam:900:900:1;barricades=400/400,100/400,0/400,400/400;wave=7;creatures=12")
		p:SetAttribute("MinigameGame", "Siege")
		ok(hudFrame.Visible, "Siege HUD shows")
		local lines = hudFrame:FindFirstChild("Lines").Text
		ok(has(lines, "75%"), "Keeper health shown")
		ok(has(lines, "34"), "points shown")
		if size.Y >= 520 then
			ok(has(lines, "Gale 50%") and has(lines, "Wave 7"), "open portal and wave shown")
			ok(has(hudFrame:FindFirstChild("Title").Text, "VETERAN"), "tier in the title")
		end
		p:SetAttribute("MinigameHud", "game=Haul;points=260;min=150;time=300;players=4;phase=vulnerable;energy=0;essence=44;hull=71;fires=3;masts=1,0;raw=2;cooked=3")
		p:SetAttribute("MinigameGame", "Haul")
		lines = hudFrame:FindFirstChild("Lines").Text
		ok(hudFrame.Visible and has(lines, "44%"), "Haul essence shown")
		if size.Y >= 520 then ok(has(lines, "fires 3") and has(lines, "cracked masts 1") and has(lines, "3 cooked"), "haul chores shown") end
		p:SetAttribute("MinigameGame", "")
		ok(not hudFrame.Visible, "HUD hides after the match")
		p:SetAttribute("MinigameNotice", "The rifts are sealed!")
		p:SetAttribute("MinigameNoticeCount", 1)
		ok(has(texts(ui.gui), "The rifts are sealed!"), "minigame toast")
	end
end
print("PASS: " .. (checks - partD) .. " minigame atlas assertions.")
print("Minigames QA passed " .. checks .. " checks.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-minigames.luau")
