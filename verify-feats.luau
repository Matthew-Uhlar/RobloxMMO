-- Combat Feats (docs/DEPTH-CONTRACT.md §45): tiered boss tasks for every slayer
-- boss, world boss, lair boss, the Undertide Vaults and the seven Observatory
-- floors; points, tier thresholds, rewards and feat teleports.
-- Part A: pure data and rules (GameData "Combat Feats" section): coverage,
--   thresholds, every task type through FT.record, shared kc counters, no
--   double credit, migration / retro seeding, teleport charges, reward budget,
--   announcements and the Isle Renown source.
-- Part B: combat.server.lua fight records through the logic harness (lair
--   telegraph hits, stance swings into Wards, styles, armour, adds; raid
--   encounters; slayer boss timing and hits).
-- Part C: server.server.lua with service doubles: every reward path credits
--   feats (lair kill, raid clear, Observatory grant, world boss, slayer boss),
--   resends never double-credit, persistence across rejoin, retro seeding on
--   an old journal, featClaim once with no coins, featTeleport charges.
-- Part D: the atlas (Menu › Combat Feats tile, tier tabs, boss filter, claim).
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
local FT, LR, RD, E, RN, F = Data.Feats, Data.Lairs, Data.Raids, Data.Endgame, Data.Renown, Data.Features
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
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
local function count(map) local n = 0 for _ in pairs(map) do n += 1 end return n end

------------------------------------------------------------------------------
-- Part A: data and rules.
------------------------------------------------------------------------------
local partA = checks
-- Coverage: every boss the game has gets a group with tasks.
do
	local want = {}
	for _, line in ipairs(Data.SlayerOrder) do want["slayer:" .. line] = true end
	for _, id in ipairs(E.BossOrder) do want["world:" .. id] = true end
	for _, id in ipairs(LR.Order) do want["lair:" .. id] = true end
	want["raid:" .. RD.ID] = true
	for i in ipairs(Data.DungeonFloors) do want["floor:" .. i] = true end
	eq(#FT.Groups, count(want), "one feat group per slayer boss, world boss, lair boss, raid and Observatory floor")
	for id in pairs(want) do ok(FT.GroupById[id] ~= nil, id .. " has a feat group") end
	local per, kinds = {}, {}
	for _, t in ipairs(FT.Tasks) do
		per[t.group] = (per[t.group] or 0) + 1
		kinds[t.group] = kinds[t.group] or {}
		kinds[t.group][t.type] = true
	end
	for _, g in ipairs(FT.Groups) do
		ok((per[g.id] or 0) >= 5, g.id .. " has at least five tasks (" .. tostring(per[g.id]) .. ")")
		ok(kinds[g.id].kc and kinds[g.id].speed and kinds[g.id].perfection or (g.source == "world" and kinds[g.id].kc and kinds[g.id].speed and kinds[g.id].mechanical),
			g.id .. " mixes kill count, speed and perfection / mechanical tasks")
	end
	local types = {}
	for _, t in ipairs(FT.Tasks) do types[t.type] = true end
	for _, ty in ipairs(FT.Types) do ok(types[ty.id], "task type " .. ty.id .. " is used") end
	-- Every tier is populated; points per tier 1..6; thresholds strictly rise and end within the total.
	local prev = 0
	for i, t in ipairs(FT.Tiers) do
		eq(t.points, i, t.id .. " is worth " .. i .. " points per task")
		ok(FT.TierCounts[t.id] >= 5, t.id .. " has tasks (" .. FT.TierCounts[t.id] .. ")")
		ok(FT.Thresholds[i] > prev, t.id .. " threshold rises (" .. FT.Thresholds[i] .. ")")
		prev = FT.Thresholds[i]
	end
	ok(FT.Thresholds[#FT.Tiers] <= FT.TOTAL_POINTS and FT.Thresholds[#FT.Tiers] >= 0.9 * FT.TOTAL_POINTS, "Grandmaster needs nearly every point")
	local rows = {}
	for _, t in ipairs(FT.Tiers) do table.insert(rows, string.format("%s %d tasks (%d pts, unlock %d)", t.id, FT.TierCounts[t.id], FT.TierTotals[t.id], FT.Thresholds[t.index])) end
	print("Combat Feats: " .. #FT.Tasks .. " tasks, " .. FT.TOTAL_POINTS .. " points — " .. table.concat(rows, ", "))
	-- Contract §45 numbers.
	eq(#FT.Tasks, 156, "156 tasks (contract §45)")
	eq(FT.TOTAL_POINTS, 573, "573 points (contract §45)")
	local byType = {}
	for _, t in ipairs(FT.Tasks) do byType[t.type] = (byType[t.type] or 0) + 1 end
	eq(string.format("%d/%d/%d/%d/%d", byType.kc, byType.perfection, byType.speed, byType.restriction, byType.mechanical), "49/36/27/13/31", "task types (contract §45)")
	-- Ids unique and stable-looking; rule keys known; texts present.
	local known = {kc = true, minTier = true, master = true, challenge = true, maxSeconds = true, solo = true, maxParty = true, noDeaths = true,
		noMistakes = true, minGrade = true, allSecrets = true, maxRank = true, minShare = true, noHits = true, noMech = true, avoid = true,
		perfectWards = true, noWard = true, onlyStyle = true, noArmor = true, minAdds = true, underPar = true}
	for _, t in ipairs(FT.Tasks) do
		ok(FT.TaskById[t.id] == t and has(t.id, t.group .. "."), t.id .. " indexed under its group")
		ok(#t.name >= 4 and #t.text >= 10, t.id .. " has a name and text")
		for k in pairs(t.rule) do ok(known[k], t.id .. " rule key " .. k .. " is known") end
		if t.rule.kc then ok(type(t.counter) == "string" and has(t.counter, t.group .. "|"), t.id .. " counts in its group") end
	end
end
-- Speed thresholds fit the fight limits and stay plausible; avoided attacks exist.
do
	local C = 240 -- combat C.BOSS_DURATION (slayer bosses)
	for _, t in ipairs(FT.Tasks) do
		local g = FT.GroupById[t.group]
		local s = t.rule.maxSeconds
		if s then
			if g.source == "slayer" then ok(s < C and s >= 60, t.id .. " fits the 4-minute slayer boss limit")
			elseif g.source == "lair" then
				local d = LR.boss(g.key)
				ok(s < d.duration and s >= 0.5 * LR.model(g.key).fight, t.id .. " fits " .. g.key .. "'s limit and the modelled fight (" .. s .. " s)")
			elseif g.source == "dungeon" then ok(s < 2 * Data.DungeonFloors[g.key].par * 2.8, t.id .. " below the floor's fail time")
			elseif g.source == "raid" then ok(s >= 300 and s <= 900, t.id .. " a plausible raid clear")
			elseif g.source == "world" then ok(s < (E.boss(g.key).duration or 600), t.id .. " inside the world boss's stay") end
		end
		if t.rule.avoid then
			if g.source == "lair" then ok(LR.boss(g.key).attacks[t.rule.avoid] ~= nil, t.id .. " avoids a real attack")
			else
				local enc, atk = t.rule.avoid:match("^(%w+):(%w+)$")
				ok(enc and RD.encounter(enc) and RD.encounter(enc).attacks[atk] ~= nil, t.id .. " avoids a real raid attack")
			end
		end
	end
end
-- Reward budget: hilts are value-1 cosmetics with no stats; perks never grant coins / Health / Defense.
do
	for _, t in ipairs(FT.Tiers) do
		local r = FT.Rewards[t.id]
		local h = Data.Items[r.hilt]
		ok(h ~= nil and h.cosmetic == true and h.value <= 1 and h.stats == nil and h.featHilt == t.id, t.id .. " hilt is a value-1 cosmetic without stats")
		ok(r.coins == nil and r.health == nil and r.defense == nil, t.id .. " reward grants no coins, Health or Defense")
		ok(r.bossMagicFind <= FT.MAX_BOSS_MAGIC_FIND and r.slayerXp <= FT.MAX_SLAYER_XP, t.id .. " perks within the caps")
		ok(has(FT.rewardText(t.id), h.name), t.id .. " reward text names the hilt")
	end
	local prevTp, prevMf = -1, -1
	for _, t in ipairs(FT.Tiers) do
		local r = FT.Rewards[t.id]
		ok(r.teleports >= prevTp and r.bossMagicFind >= prevMf, t.id .. " perks never shrink")
		prevTp, prevMf = r.teleports, r.bossMagicFind
	end
	eq(FT.perks(FT.TOTAL_POINTS).bossMagicFind, FT.MAX_BOSS_MAGIC_FIND, "boss Magic Find caps at the top tier")
	ok(FT.MAX_BOSS_MAGIC_FIND <= 5 and FT.MAX_SLAYER_XP <= 0.05, "boss-loot / slayer perks stay slight")
	eq(FT.perks(0).teleports, 0, "no tier, no perks")
	-- Perks are not perkStats: Data.PerkBudget untouched, nothing in the server writes p.perkStats.feats.
	ok(not has(fs.readFile("server.server.lua"), "perkStats.feats") and not has(fs.readFile("server.server.lua"), 'perkStats["feats"]'), "feats never write perkStats")
	eq(Data.PerkBudget.health, 300, "perk budget Health unchanged")
	eq(Data.PerkBudget.defense, 125, "perk budget Defense unchanged")
	-- Teleport destinations name real anchors written by world.server.lua.
	local world = fs.readFile("world.server.lua")
	for _, d in ipairs(FT.Teleports) do
		local prefix = d.anchor:match("^(Waypoint_Lair_)") or d.anchor
		ok(has(world, '"' .. prefix), d.id .. " anchor " .. d.anchor .. " exists in the world")
		ok(d.region == nil or Data.RegionById[d.region] ~= nil, d.id .. " region is real")
	end
	-- The Collection Log never picks feat data up (no rare-chance rows).
	local L = Data.CommissionsLogs.log(true)
	for _, t in ipairs(FT.Tiers) do eq(L.Of[FT.Rewards[t.id].hilt], nil, t.id .. " hilt is not a Collection Log entry") end
end
-- Rules: each task type through FT.record.
local function fresh() return FT.new() end
local function doneSet(res) local s = {} for _, id in ipairs(res.done) do s[id] = true end return s end
local NOW = 1700000000
do
	-- Kill count: shared counters count once per event; kc1 and kc25 share "lair:X|".
	local s = fresh()
	local r = FT.record(s, {source = "lair", boss = "Bramblemaw", id = "f1", seconds = 200, party = 2}, NOW)
	local d = doneSet(r)
	ok(d["lair:Bramblemaw.first"], "first kill credited")
	eq(s.kc["lair:Bramblemaw|"], 1, "one kill counted once (shared counter)")
	for i = 2, 24 do FT.record(s, {source = "lair", boss = "Bramblemaw", id = "f" .. i, seconds = 200, party = 2}, NOW) end
	ok(not s.done["lair:Bramblemaw.kc25"], "24 kills: not yet 25")
	d = doneSet(FT.record(s, {source = "lair", boss = "Bramblemaw", id = "f25", seconds = 200, party = 2}, NOW))
	ok(d["lair:Bramblemaw.kc25"], "25th kill completes the kill-count task")
	-- No double credit: the same fight id is refused.
	local again = FT.record(s, {source = "lair", boss = "Bramblemaw", id = "f25", seconds = 30, party = 1}, NOW)
	eq(again.refused, "seen", "a repeated fight id is refused")
	eq(s.kc["lair:Bramblemaw|"], 25, "and counts nothing")
	eq(#again.done, 0, "and completes nothing (even a faster time)")
	-- The ring forgets old ids only after SEEN_MAX newer ones.
	eq(#s.seen, math.min(25, FT.SEEN_MAX), "seen ring bounded")
	-- Speed: server-timed, boundaries.
	s = fresh()
	ok(not doneSet(FT.record(s, {source = "lair", boss = "Bramblemaw", id = "a", seconds = 76, party = 1}, NOW))["lair:Bramblemaw.speed"], "76 s misses the 1:15 speed task")
	ok(doneSet(FT.record(s, {source = "lair", boss = "Bramblemaw", id = "b", seconds = 75, party = 1}, NOW))["lair:Bramblemaw.speed"], "75 s meets it")
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "c", party = 1}, NOW))["lair:Bramblemaw.speed"], "no server time, no speed credit")
	-- Perfection: avoid needs the attack to have resolved and no hit from it.
	local feat = {mech = 1, cast = 5, swings = 4, prayed = 4, ward = 4, adds = 3, styles = {magic = true}, hitBy = {lash = 1}, seen = {lash = 2, thornburst = 2}, armor = 3}
	d = doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "p", seconds = 100, party = 1, feat = feat}, NOW))
	ok(d["lair:Bramblemaw.thornburst"], "never struck by Thornburst (it resolved twice): perfection")
	ok(not d["lair:Bramblemaw.flawless"], "struck by Bramble Lash: no flawless")
	ok(d["lair:Bramblemaw.brood"], "three adds struck: mechanical")
	ok(d["lair:Bramblemaw.magic"], "magic only: restriction")
	feat.seen.thornburst = 0
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "q", party = 1, feat = feat}, NOW))["lair:Bramblemaw.thornburst"], "an attack that never resolved proves nothing")
	feat.hitBy.lash, feat.mech, feat.seen.thornburst = 0, 0, 2
	ok(doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "r", party = 1, feat = feat}, NOW))["lair:Bramblemaw.flawless"], "solo, no telegraph hits, 5 resolved: flawless")
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "r2", party = 2, feat = feat}, NOW))["lair:Bramblemaw.flawless"], "flawless needs a solo fight")
	feat.cast = 2
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "r3", party = 1, feat = feat}, NOW))["lair:Bramblemaw.flawless"], "too few telegraphs resolved: no flawless")
	-- Restriction: styles and armour.
	feat.styles = {magic = true, melee = true}
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "s", party = 1, feat = feat}, NOW))["lair:Bramblemaw.magic"], "a melee hit breaks magic-only")
	local pyre = {mech = 0, cast = 3, swings = 2, prayed = 0, ward = 0, adds = 3, styles = {melee = true}, hitBy = {}, seen = {nova = 1}, armor = 0}
	d = doneSet(FT.record(fresh(), {source = "lair", boss = "Pyrewarden", id = "t", seconds = 150, party = 1, feat = pyre}, NOW))
	ok(d["lair:Pyrewarden.unarmored"] and d["lair:Pyrewarden.melee"] and d["lair:Pyrewarden.nova"] and d["lair:Pyrewarden.sigils"] and d["lair:Pyrewarden.speed"], "Pyrewarden: armourless, melee, nova, sigils, speed")
	pyre.armor = 1
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Pyrewarden", id = "u", party = 1, feat = pyre}, NOW))["lair:Pyrewarden.unarmored"], "one armour piece breaks the restriction")
	pyre.armor = nil
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Pyrewarden", id = "v", party = 1, feat = pyre}, NOW))["lair:Pyrewarden.unarmored"], "unknown armour never passes")
	-- Mechanical: wards.
	local wards = {mech = 0, cast = 1, swings = 8, prayed = 8, ward = 8, adds = 0, styles = {ranged = true}, hitBy = {}, seen = {}}
	ok(doneSet(FT.record(fresh(), {source = "lair", boss = "Aerisca", id = "w", party = 1, feat = wards}, NOW))["lair:Aerisca.wards"], "8 swings, all prayed: Ward Weaver")
	wards.prayed = 7
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Aerisca", id = "w2", party = 1, feat = wards}, NOW))["lair:Aerisca.wards"], "one unprayed swing breaks it")
	local faithless = {mech = 0, cast = 1, swings = 6, prayed = 0, ward = 0, adds = 0, styles = {melee = true}, hitBy = {}, seen = {}}
	ok(doneSet(FT.record(fresh(), {source = "lair", boss = "Nihlvar", id = "x", party = 1, feat = faithless}, NOW))["lair:Nihlvar.noWard"], "six swings without a Ward: Faithless")
	faithless.ward = 1
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Nihlvar", id = "x2", party = 1, feat = faithless}, NOW))["lair:Nihlvar.noWard"], "a Ward up once breaks Faithless")
	-- Lair / raid perfection without a fight record never passes.
	ok(not doneSet(FT.record(fresh(), {source = "lair", boss = "Bramblemaw", id = "y", seconds = 50, party = 1}, NOW))["lair:Bramblemaw.thornburst"], "no fight record, no perfection")
end
do
	-- Observatory: grades, flawless, secrets, solo, Master and the Master speed.
	local s = fresh()
	local d = doneSet(FT.record(s, {source = "dungeon", boss = 1, id = "d1", grade = "S+", seconds = 100, deaths = 0, mistakes = 0, party = 1, secrets = 2, secretsTotal = 2}, NOW))
	for _, k in ipairs({"clear", "gradeA", "deathless", "gradeS", "flawless", "speed", "secrets", "solo"}) do ok(d["floor:1." .. k], "Floor I " .. k) end
	ok(not d["floor:1.master"], "a normal clear is not a Master clear")
	d = doneSet(FT.record(s, {source = "dungeon", boss = 1, id = "d2", master = true, grade = "B", seconds = 1000, deaths = 1, mistakes = 0, party = 3, secrets = 0, secretsTotal = 2}, NOW))
	ok(d["floor:1.master"] and not d["floor:1.masterFlawless"] and not d["floor:1.masterSpeed"], "Master clear counted; a death spoils Master flawless")
	eq(s.kc["floor:1|"], 2, "both clears count toward the floor's plain counter")
	eq(s.kc["floor:1|master=true"], 1, "only the Master clear counts toward the Master counter")
	ok(not doneSet(FT.record(fresh(), {source = "dungeon", boss = 2, id = "d3", grade = "B", deaths = 0, party = 2, secrets = 1, secretsTotal = 2}, NOW))["floor:2.secrets"], "one secret short: no Stargazer")
	ok(not doneSet(FT.record(fresh(), {source = "dungeon", boss = 2, id = "d4", grade = "B", party = 1}, NOW))["floor:2.solo"], "solo needs grade A")
	ok(not doneSet(FT.record(fresh(), {source = "dungeon", boss = 3, id = "d5", grade = "S", party = 1}, NOW))["floor:3.deathless"], "deaths unknown: no deathless")
	-- Raid: personal deaths, Challenge Mode, par, party size and raid attack keys.
	local raidFeat = {mech = 0, cast = 12, swings = 9, prayed = 9, ward = 9, adds = 7, styles = {melee = true}, hitBy = {}, seen = {["Thalvorn:maelstrom"] = 2}}
	d = doneSet(FT.record(fresh(), {source = "raid", boss = RD.ID, id = "r1", seconds = 590, party = 3, challenge = true, underPar = true, deaths = 0, feat = raidFeat}, NOW))
	for _, k in ipairs({"first", "deathless", "cm", "maelstrom", "speed", "anchors", "trio", "underPar", "flawless"}) do ok(d["raid:" .. RD.ID .. "." .. k], "raid " .. k) end
	raidFeat.hitBy["Thalvorn:maelstrom"] = 1
	d = doneSet(FT.record(fresh(), {source = "raid", boss = RD.ID, id = "r2", seconds = 700, party = 4, deaths = 1, feat = raidFeat}, NOW))
	ok(d["raid:" .. RD.ID .. ".first"] and not d["raid:" .. RD.ID .. ".maelstrom"] and not d["raid:" .. RD.ID .. ".deathless"] and not d["raid:" .. RD.ID .. ".trio"] and not d["raid:" .. RD.ID .. ".cm"],
		"a normal four-raider clear with a death and a Maelstrom hit: only the clear")
	-- World bosses: rank, share, speed.
	d = doneSet(FT.record(fresh(), {source = "world", boss = "Aurelith", id = "w1", rank = 1, share = 0.12, seconds = 60}, NOW))
	ok(d["world:Aurelith.first"] and d["world:Aurelith.share"] and d["world:Aurelith.top"] and d["world:Aurelith.speed"], "world boss: first, 10% share, top, speed")
	d = doneSet(FT.record(fresh(), {source = "world", boss = "Nyxwyrm", id = "w2", rank = 4, share = 0.02, seconds = 9999}, NOW))
	ok(d["world:Nyxwyrm.first"] and not d["world:Nyxwyrm.top"] and not d["world:Nyxwyrm.share"] and not d["world:Nyxwyrm.speed"], "a small share earns only the kill")
	-- Slayer bosses: tiers, hits, timing.
	d = doneSet(FT.record(fresh(), {source = "slayer", boss = "Bramble", tier = 3, seconds = 80, hits = 0}, NOW))
	for _, k in ipairs({"first", "tier2", "tier3", "brisk", "untouched"}) do ok(d["slayer:Bramble." .. k], "slayer " .. k) end
	d = doneSet(FT.record(fresh(), {source = "slayer", boss = "Bramble", tier = 1, seconds = 30, hits = 2}, NOW))
	ok(d["slayer:Bramble.first"] and not d["slayer:Bramble.brisk"] and not d["slayer:Bramble.untouched"], "tier I is too low for brisk; hits break untouched")
	ok(not doneSet(FT.record(fresh(), {source = "slayer", boss = "Bramble", tier = 3}, NOW))["slayer:Bramble.untouched"], "hits unknown: no perfection")
	-- Junk events never throw and never credit.
	for _, junk in ipairs({nil, 5, {}, {source = "lair"}, {source = "lair", boss = "Nobody"}, {source = "dungeon", boss = 99}, {source = "hack", boss = "Bramblemaw"},
		{source = "lair", boss = "Bramblemaw", feat = {mech = -5, styles = "x", hitBy = {[1] = 3}}}}) do
		local r = FT.record(fresh(), junk, NOW)
		ok(type(r) == "table" and (r.refused ~= nil or #r.done >= 0), "junk event handled")
	end
	eq(FT.record(fresh(), {source = "lair", boss = "Nobody"}, NOW).refused, "invalid", "unknown boss refused")
	local hostile = FT.normalize({source = "lair", boss = "Bramblemaw", feat = {mech = -5, cast = 1 / 0, styles = {melee = "yes"}, hitBy = {[1] = 3}}})
	ok(hostile.feat.mech == 0 and hostile.feat.cast == 0 and hostile.feat.styles.melee == nil and next(hostile.feat.hitBy) == nil, "fight records are sanitised")
end
do
	-- Tiers and points.
	local s = fresh()
	eq(FT.points(s), 0, "no points")
	eq(FT.tierFor(0), 0, "no tier")
	for _, t in ipairs(FT.Tasks) do if t.tier == "Easy" then s.done[t.id] = 1 end end
	eq(FT.points(s), FT.TierTotals.Easy, "Easy points summed")
	eq(FT.tierFor(FT.points(s)), 1, "all Easy tasks reach the Easy tier")
	s.done["nonsense.task"] = 1
	eq(FT.points(s), FT.TierTotals.Easy, "unknown task ids are worth nothing")
	eq(#FT.claimable(s, FT.points(s)), 1, "one tier claimable")
	s.claimed.Easy = true
	eq(#FT.claimable(s, FT.points(s)), 0, "claimed tiers are not offered again")
	-- A record that crosses a threshold reports the tier.
	local s2 = fresh()
	local got
	for i = 1, 8 do
		got = FT.record(s2, {source = "dungeon", boss = 1, id = "t" .. i, grade = "S+", seconds = 100, deaths = 0, mistakes = 0, party = 1, secrets = 2, secretsTotal = 2}, NOW)
		if #got.tiers > 0 then break end
	end
	ok(#got.tiers >= 1 and got.tiers[1] == "Easy", "crossing the Easy threshold reports the tier")
	-- Migration: sanitise a saved state.
	local saved = {v = 1, done = {["lair:Bramblemaw.first"] = 5, ["bogus"] = 3}, kc = {["lair:Bramblemaw|"] = -4, [5] = 2}, claimed = {Easy = true, Fake = true, Medium = "yes"},
		tele = {day = "x", used = 3}, seen = {"a", 7, "b"}}
	local m = FT.migrate(saved, {}, NOW)
	ok(m.done["lair:Bramblemaw.first"] == 5 and m.done.bogus == nil, "unknown done ids dropped")
	eq(m.kc["lair:Bramblemaw|"], 0, "negative counters clamp to 0")
	ok(m.claimed.Easy and m.claimed.Fake == nil and m.claimed.Medium == nil, "claims sanitised")
	eq(m.tele.day, 0, "bad teleport day reset")
	eq(#m.seen, 2, "seen ring keeps strings only")
	-- Retro seeding from an old journal's kill records (silent, once).
	local old = {lairs = {kc = {Bramblemaw = 30, Aerisca = 1}}, raids = {kc = 2, cm = 1}, dungeons = {clears = {["1"] = 4}}, dungeonClasses = {masterClears = {["1"] = 2}},
		bestiary = {Aurelith = 12}}
	local seeded, retro = FT.migrate(nil, old, NOW)
	local rs = {}
	for _, id in ipairs(retro) do rs[id] = true end
	ok(rs["lair:Bramblemaw.first"] and rs["lair:Bramblemaw.kc25"] and rs["lair:Aerisca.first"], "lair kill counts seed the kc tasks")
	ok(rs["raid:" .. RD.ID .. ".first"] and rs["raid:" .. RD.ID .. ".cm"], "raid clears and Challenge clears seed")
	ok(rs["floor:1.clear"] and rs["floor:1.master"], "Observatory clears (normal + Master) seed")
	eq(seeded.kc["floor:1|"], 6, "normal + Master clears in the plain counter")
	ok(rs["world:Aurelith.first"] and rs["world:Aurelith.kc10"], "world boss bestiary seeds")
	ok(not rs["lair:Bramblemaw.speed"] and not rs["floor:1.flawless"], "retro never credits speed / perfection")
	eq(seeded.retro, true, "retro marked")
	local again = FT.migrate(seeded, old, NOW)
	eq(count(again.done), count(seeded.done), "a second load changes nothing")
	-- Teleport charges roll forward only.
	local pts = FT.Thresholds[2]
	local st = FT.new()
	local day = FT.dayOf(NOW)
	local tp = FT.teleportState(st, pts, NOW)
	eq(tp.max, FT.Rewards.Medium.teleports, "Medium grants daily teleports")
	eq(tp.left, tp.max, "full charges on a fresh day")
	st.tele = {day = day, used = tp.max}
	eq(FT.teleportState(st, pts, NOW).left, 0, "spent today")
	eq(FT.teleportState(st, pts, NOW + FT.DAY_SECONDS).left, tp.max, "refilled tomorrow")
	st.tele = {day = day + 1, used = tp.max}
	eq(FT.teleportState(st, pts, NOW).left, 0, "a clock behind the saved day never refills")
	eq(FT.teleportState(FT.new(), 0, NOW).max, 0, "no teleports below Medium")
	-- Announcements (completion toasts through §31).
	local a = F.announceText({kind = "feat", task = "lair:Bramblemaw.first"})
	ok(has(a.head, "COMBAT FEAT") and has(a.head, "EASY") and has(a.body, "Thornroot Trespasser") and a.color == FT.TierById.Easy.color, "feat toast text")
	local b = F.announceText({kind = "featTier", tier = "Hard"})
	ok(b.head == "FEAT TIER UNLOCKED" and has(b.body, "Hard") and has(b.body, "Gildbound"), "tier toast text")
	ok(F.ANNOUNCE_PRIORITY.featTier == true, "tier unlocks survive a full toast ring")
	eq(F.announceText({kind = "feat", task = 5}).head, "COMBAT FEAT  ·  ?", "malformed feat toast is safe")
	-- Isle Renown source.
	ok(RN.SourceById.feats ~= nil, "renown source registered")
	local full = {done = {}}
	for _, t in ipairs(FT.Tasks) do full.done[t.id] = 1 end
	local bd = RN.breakdown({feats = full}, P, {})
	eq(bd.sources.feats.xp, FT.TOTAL_POINTS * FT.RENOWN_PER_POINT, "renown = 2 per feat point")
	eq(bd.sources.feats.count, #FT.Tasks, "renown counts tasks")
	eq(RN.breakdown({feats = {done = {bogus = 1}}}, P, {}).sources.feats.xp, 0, "bogus tasks earn no renown")
end
print("PASS: " .. (checks - partA) .. " Combat Feats data / rule assertions.")

------------------------------------------------------------------------------
-- Part B: combat.server.lua fight records (logic harness).
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
			combatLevel = 90, ironman = false, prayer = opts.prayer, armor = opts.armor, loadout = {style = opts.style or "melee", levels = {}, supplies = {}}}
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
local function tickLogic(w, seconds)
	local t, events = 0, {}
	while t < seconds - 1e-9 do
		w.clock += 0.25
		t += 0.25
		w.logic.beginTick()
		for _, e in ipairs(w.logic.lrTick()) do table.insert(events, e) end
		for _, r in ipairs(w.logic.records()) do w.logic.think(r) end
		w.logic.endTick()
	end
	return events
end
do
	-- Aerisca: a prayed stance swing, an unprayed one, a lattice hit, landed style and armour.
	local w = world()
	local L = w.logic
	local hero = w.player(101, Vector3.new(0, 0, 4), {prayer = {protect = "melee", offence = {}}, armor = 2})
	local mate = w.player(102, Vector3.new(0, 0, -4), {armor = 0})
	local r = L.lrRegister("FA", "Aerisca", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {101, 102}, seed = 9, center = center, ground = 0})
	w.positions[mate] = Vector3.new(30, 0, 30)
	w.clock += 1
	local hit = L.attack(hero, "attack", r.model)
	ok(hit and hit.damage > 0, "hero lands a hit")
	r.nextHit = 0
	tickLogic(w, 0.25)
	local f = r.feat[101]
	eq(f.swings, 1, "a stance swing taken is counted")
	eq(f.prayed, 1, "it went into the matching Ward")
	eq(f.ward, 1, "a Ward was up")
	ok(f.styles.melee == true, "landed style recorded")
	eq(f.armor, 2, "armour pieces from bridge stats")
	-- Lattice: hero on a charged cell, mate safe.
	r.nextSpecial = w.clock
	r.step = 0
	r.nextHit = w.clock + 100
	local events = tickLogic(w, 0.25)
	local tg
	for _, e in ipairs(events) do if e.kind == "telegraph" then tg = e.telegraph end end
	ok(tg and tg.kind == "tiles", "lattice telegraph")
	local cx, cz = LR.cellOffset(tg.cells[1])
	w.positions[hero] = Vector3.new(cx, 0, cz)
	local safe
	for c = 1, LR.GRID * LR.GRID do if not tg.charged[c] then safe = c break end end
	local sx, sz = LR.cellOffset(safe)
	w.positions[mate] = Vector3.new(sx, 0, sz)
	tickLogic(w, tg.windup + 0.25)
	eq(r.feat[101].mech, 1, "hero struck by the lattice")
	eq(r.feat[101].hitBy.squall, 1, "hit keyed by the attack id")
	eq(r.feat[102].mech, 0, "mate on a safe cell")
	eq(r.feat[102].seen.squall, 1, "but the lattice resolved for every member")
	eq(r.feat[101].cast, r.feat[102].cast, "resolved telegraphs counted for each member")
	-- Kill: the credit entry carries each member's record.
	L.kill(r)
	local res = L.lrResult("FA")
	ok(res and res.credit[101].feat and res.credit[101].feat.hitBy.squall == 1 and res.credit[101].feat.armor == 2, "kill credit carries the hero's record")
	ok(res.credit[102].feat and res.credit[102].feat.mech == 0 and res.credit[102].feat.seen.squall == 1, "and the mate's")
	ok(res.credit[101].feat.addSeen == nil, "no instance keys leak into the record")
	-- The relayed record passes the journal's sanitiser.
	local clean = FT.cleanFeat(res.credit[102].feat)
	ok(clean.mech == 0 and clean.seen.squall == 1, "sanitised record keeps the data")
end
do
	-- Bramblemaw brood: adds struck count once each.
	local w = world()
	local L = w.logic
	local hero = w.player(11, Vector3.new(0, 0, 4), {style = "melee"})
	local r = L.lrRegister("FB", "Bramblemaw", {Name = "boss"}, Vector3.new(0, 3, 0), {members = {11}, seed = 1, center = center})
	local adds = {}
	for i = 1, 3 do adds[i] = L.lrRegisterAdd(r, "Thornspawn", {Name = "add" .. i}, Vector3.new(i * 2, 2, 2), {}) end
	for _, a in ipairs(adds) do
		w.clock += 1
		L.attack(hero, "attack", a.model)
		w.clock += 1
		if a.alive then L.attack(hero, "attack", a.model) end
	end
	eq(r.feat[11].adds, 3, "three distinct adds struck (repeats count once)")
end
do
	-- Raid encounter: rdKill attaches the record too.
	local w = world()
	local L = w.logic
	local a = w.player(21, Vector3.new(0, 0, 4))
	local r = L.rdRegister("RX", "Gloomfang", {Name = "enc"}, Vector3.new(0, 3, 0), {members = {21}, party = 1, seed = 2, center = center})
	ok(r ~= nil and r.raid, "raid encounter registered")
	w.clock += 1
	L.attack(a, "attack", r.model)
	L.kill(r)
	local res = L.lrResult("RX")
	ok(res and res.credit[21].feat and res.credit[21].feat.styles.melee, "raid encounter credit carries the fight record")
end
do
	-- Slayer boss: hits on the owner and the server-timed fight length reach bridge "slayerBoss".
	local w = world()
	local L = w.logic
	local owner = w.player(31, Vector3.new(0, 0, 4))
	local kind, spec = L.bossAttribute(owner, "Bramble:3")
	eq(kind, "spawn", "boss spawn request")
	local r = L.registerBoss(owner, spec, {Name = "boss"}, Vector3.new(0, 3, 0), {})
	ok(r and r.boss, "slayer boss registered")
	L.strike(r, owner)
	L.strike(r, owner)
	w.clock += 70
	L.kill(r)
	local calls = w.calls_of("slayerBoss", owner)
	eq(#calls, 1, "one slayer boss report")
	eq(calls[1].payload.result, "win", "a win")
	eq(calls[1].payload.hits, 2, "two hits taken reported")
	eq(calls[1].payload.seconds, 70, "server-timed fight length")
end
do
	-- World boss reward payloads carry the server-timed fight length.
	local src = fs.readFile("combat.server.lua")
	ok(has(src, "seconds = math.max(1, math.floor(now - r.spawnedAt + 0.5))} -- §45"), "world boss payload timed from the rise")
	ok(has(fs.readFile("lairs.server.lua"), "feat = c.feat}})"), "lairs relay the member's record")
	ok(has(fs.readFile("raids.server.lua"), "feat = m.feat}})"), "raids relay the run's summed record")
end
do
	-- raids.server.lua sums records per member with encounter-prefixed keys.
	local src = fs.readFile("raids.server.lua")
	local fnSrc = src:match("(function Raid%.featAdd.-\nend)\n")
	ok(fnSrc ~= nil, "Raid.featAdd found")
	local Raid = {}
	luau.load("local Raid = ...\n" .. fnSrc, {debugName = "featAdd", injectGlobals = true})(Raid)
	local m = {}
	Raid.featAdd(m, "Thalvorn", {mech = 1, cast = 3, swings = 2, prayed = 2, ward = 2, adds = 3, armor = 1, styles = {melee = true}, hitBy = {maelstrom = 1}, seen = {maelstrom = 2}})
	Raid.featAdd(m, "Gloomfang", {mech = 0, cast = 2, swings = 4, prayed = 3, ward = 4, adds = 0, armor = 3, styles = {ranged = true}, hitBy = {}, seen = {fang = 1}})
	Raid.featAdd(m, "Siltmother", nil)
	ok(m.feat.mech == 1 and m.feat.cast == 5 and m.feat.swings == 6 and m.feat.prayed == 5 and m.feat.adds == 3 and m.feat.armor == 3, "run totals summed")
	ok(m.feat.hitBy["Thalvorn:maelstrom"] == 1 and m.feat.seen["Gloomfang:fang"] == 1 and m.feat.styles.melee and m.feat.styles.ranged, "attack keys prefixed by encounter")
end
print("PASS: " .. (checks - partB) .. " combat fight-record assertions.")

------------------------------------------------------------------------------
-- Part C: server.server.lua (every reward path, persistence, rejoin, claims).
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
local anchors = {}
local islandsDouble = {FindFirstChild = function(_, name, recursive)
	local id = type(name) == "string" and name:match("^Anchor_(.+)$")
	if id and recursive then
		anchors[id] = anchors[id] or {Parent = true, CFrame = CFrame.new(Vector3.new(500, 50, -500)), Name = name}
		return anchors[id]
	end
	return nil
end}
local lairCalls = {}
local fightSeq = 0
local storage = {AetherTrails = {Name = "AetherTrails"}, IsleTravelGate = {Invoke = function() return true end},
	IsleLairs = {Invoke = function(_, op, player, arg)
		table.insert(lairCalls, {op = op, arg = arg})
		if op == "enter" then fightSeq += 1; return {ok = true, fight = "LF" .. fightSeq, mode = "open"} end
		if op == "holds" then return {held = false} end
		return {ok = true}
	end}}
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua")}
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) return storage[name] end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "feats-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end,
		FindFirstChild = function(_, name) return if name == "Islands" then islandsDouble else nil end},
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
	Random = {new = function() return {NextNumber = function() return 0.999 end, NextInteger = function(_, lo) return lo end} end},
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
local liveById = {}
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 5000, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return p.root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) p.root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	if liveById[id] then services.Players.PlayerRemoving:Fire(liveById[id]) end
	liveById[id] = p
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p) if liveById[p.UserId] == p then liveById[p.UserId] = nil end services.Players.PlayerRemoving:Fire(p) end
local function stored(p) leave(p); return data["p" .. p.UserId].profile end
local function seeded(id, mutate)
	local p = player(id)
	leave(p)
	mutate(data["p" .. id].profile)
	return player(id)
end
local remote, bridge, grant
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
	if o.Name == "IsleExpeditionGrant" then grant = o end
end
ok(remote ~= nil and bridge ~= nil and grant ~= nil, "IsleAction, IsleBridge and IsleExpeditionGrant found")
local function cmd(p, verb, item) advance(1); return remote.OnServerInvoke(p, verb, item) end
local function invoke(op, p, payload) return bridge.OnInvoke(op, p, payload) end
local function prompt(action, item, pos, region)
	local base = {CFrame = CFrame.new(pos)}
	local q = {Enabled = true, MaxActivationDistance = 10, attrs = {IsleAction = action, IsleItem = item, IsleRegion = region}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q) advance(2); p.last = nil; services.ProximityPromptService.PromptTriggered:Fire(q, p); return p.last end
local function kinds(snap)
	local out = {}
	for _, e in ipairs(snap and snap.announce and snap.announce.list or {}) do out[e.kind .. ":" .. tostring(e.task or e.tier)] = true end
	return out
end
local function veteran(prof)
	for _, skill in ipairs(Data.SkillOrder) do prof.xp[skill] = 2e8 end
	prof.coins = 1000000
	prof.questCompleted = 99
	prof.questsDone = {}
	for id in pairs(Data.QuestById) do prof.questsDone[id] = true end
	prof.started = true
end

-- C1. A new journal: empty feats, the snapshot key, no retro note.
local hero = player(7001)
local s = cmd(hero, "state")
ok(type(s.feats) == "table" and s.feats.points == 0 and s.feats.tier == 0 and s.feats.total == FT.TOTAL_POINTS, "snapshot carries feats")
eq(count(s.feats.done), 0, "nothing done")
eq(s.feats.teleports.max, 0, "no teleports yet")
ok(not has(s.message, "Combat Feats"), "a fresh journal gets no retro note")
-- C2. A veteran journal (kill records, no feats) is seeded once on load.
hero = seeded(7001, function(prof)
	veteran(prof)
	prof.feats = nil
	prof.lairs = {kc = {Bramblemaw = 26}, pb = {}, got = {}, log = {}, deaths = {}}
end)
s = cmd(hero, "state")
ok(s.feats.done["lair:Bramblemaw.first"] ~= nil and s.feats.done["lair:Bramblemaw.kc25"] ~= nil, "existing lair kill counts credited on load")
local retroPoints = s.feats.points
ok(retroPoints == FT.TierById.Easy.points + FT.TierById.Medium.points, "retro points: Easy + Medium kc tasks")
eq(s.feats.kc["lair:Bramblemaw|"], 26, "the counter starts at the saved kill count")
s = cmd(hero, "state")
eq(s.feats.points, retroPoints, "seeding happens once")
local coins0 = s.coins

-- C3. Lair kill through the real altar entry and bridge "lair".
hero.root.Position = Vector3.new(0, 5000, 0)
local altar = prompt("lairEnter", "Bramblemaw", hero.root.Position, LR.boss("Bramblemaw").region)
local entered = use(hero, altar)
ok(entered and has(entered.message, "Thornroot Hollow"), "entered the lair: " .. tostring(entered and entered.message))
local fight = "LF" .. fightSeq
local fee = LR.boss("Bramblemaw").fee
local feat = {mech = 0, cast = 5, swings = 3, prayed = 3, ward = 3, adds = 3, styles = {magic = true}, hitBy = {}, seen = {thornburst = 2, lash = 2}, armor = 4}
hero.last = nil
local reply = invoke("lair", hero, {action = "kill", boss = "Bramblemaw", fight = fight, seconds = 60, party = 1, share = 1, feat = feat})
ok(reply and reply.ok, "lair kill paid")
local snap = hero.last
local got = kinds(snap)
for _, k in ipairs({"thornburst", "brood", "speed", "magic", "flawless"}) do ok(snap.feats.done["lair:Bramblemaw." .. k] ~= nil, "lair feat " .. k .. " credited") end
ok(got["feat:lair:Bramblemaw.flawless"] and got["feat:lair:Bramblemaw.magic"], "completion toasts through the announcement system")
eq(snap.feats.kc["lair:Bramblemaw|"], 27, "kill counted")
ok(has(snap.message, "Combat Feat: Unscathed Hollow"), "the reward message names the feat")
local afterLair = snap.feats.points
eq(afterLair, retroPoints + 2 + 2 + 3 + 3 + 4, "points: thornburst 2, brood 2, speed 3, magic 3, flawless 4")
-- Resend of the same kill (lairs.server.lua retry): refused, no double credit.
local again = invoke("lair", hero, {action = "kill", boss = "Bramblemaw", fight = fight, seconds = 60, party = 1, share = 1, feat = feat})
ok(again and again.ok == false and again.reason == "paid", "a resend is refused as paid")
eq(cmd(hero, "state").feats.kc["lair:Bramblemaw|"], 27, "no double kill count")
-- A forged fight id (no entry) credits nothing.
local forged = invoke("lair", hero, {action = "kill", boss = "Nihlvar", fight = "LF999", seconds = 30, party = 1, share = 1, feat = feat})
ok(forged and forged.ok == false and forged.reason == "entry", "a kill without an altar entry is refused")
eq(cmd(hero, "state").feats.done["lair:Nihlvar.first"], nil, "and no feat")

-- C4. Persistence and rejoin.
local saved = stored(hero)
ok(type(saved.feats) == "table" and saved.feats.done["lair:Bramblemaw.flawless"] ~= nil and saved.feats.kc["lair:Bramblemaw|"] == 27, "feats saved with the journal")
hero = player(7001)
s = cmd(hero, "state")
eq(s.feats.points, afterLair, "points survive a rejoin")
local fresh2 = kinds(s)
ok(not fresh2["feat:lair:Bramblemaw.flawless"], "no toast replays after a rejoin")
ok(not has(s.message, "credited from your existing"), "no second retro note")

-- C5. Raid clear (bridge "raid" complete) and its resend.
hero.last = nil
local raidFeat = {mech = 0, cast = 12, swings = 9, prayed = 9, ward = 9, adds = 7, styles = {melee = true}, hitBy = {}, seen = {["Thalvorn:maelstrom"] = 2}}
reply = invoke("raid", hero, {action = "complete", run = "RUN1", seconds = 590, party = 3, points = 3000, team = 9000, challenge = true, underPar = true, deaths = 0, xp = {}, feat = raidFeat})
ok(reply and reply.ok, "raid clear paid")
snap = hero.last
for _, k in ipairs({"first", "deathless", "cm", "maelstrom", "speed", "anchors", "trio", "underPar", "flawless"}) do ok(snap.feats.done["raid:" .. RD.ID .. "." .. k] ~= nil, "raid feat " .. k) end
local afterRaid = snap.feats.points
reply = invoke("raid", hero, {action = "complete", run = "RUN1", seconds = 300, party = 1, points = 3000, team = 3000, challenge = true, underPar = true, deaths = 0, xp = {}, feat = raidFeat})
ok(reply and reply.ok == false, "a raid resend is refused")
eq(cmd(hero, "state").feats.kc["raid:" .. RD.ID .. "|"], 1, "raid counted once")
-- A failed run ("end") credits nothing.
invoke("raid", hero, {action = "end", run = "RUN2", result = "timeout", deaths = 2})
eq(cmd(hero, "state").feats.points, afterRaid, "a failed raid earns no feats")

-- C6. Observatory grant (server-timed run result).
local r1 = grant.OnInvoke(hero, {floor = 1, grade = "S+", score = 295, seconds = 100, deaths = 0, mistakes = 0, partySize = 1, damageShare = 1, secrets = 2, secretsTotal = 2, runId = "OBS1"})
ok(r1 and r1.ok, "Floor I clear granted")
s = cmd(hero, "state")
for _, k in ipairs({"clear", "gradeA", "deathless", "gradeS", "flawless", "speed", "secrets", "solo"}) do ok(s.feats.done["floor:1." .. k] ~= nil, "Floor I feat " .. k) end
advance(95)
hero = player(7001) -- refresh the lease after the clear cooldown
local r2 = grant.OnInvoke(hero, {floor = 1, grade = "S+", score = 295, seconds = 100, deaths = 0, mistakes = 0, partySize = 1, damageShare = 1, secrets = 2, secretsTotal = 2, runId = "OBS1"})
ok(r2 and r2.ok == false, "the same run id is refused")
local r3 = grant.OnInvoke(hero, {floor = 1, grade = "S", score = 270, seconds = 150, deaths = 0, mistakes = 0, partySize = 1, damageShare = 1, secrets = 2, secretsTotal = 2, master = true, runId = "OBS2"})
ok(r3 and r3.ok, "Master Floor I granted (unlocked by the S+ clear)")
s = cmd(hero, "state")
ok(s.feats.done["floor:1.master"] ~= nil and s.feats.done["floor:1.masterFlawless"] ~= nil and s.feats.done["floor:1.masterSpeed"] ~= nil, "Master feats credited")
eq(s.feats.kc["floor:1|"], 2, "two credited clears")
-- A refused grant (cooldown) credits nothing.
local r4 = grant.OnInvoke(hero, {floor = 2, grade = "S+", score = 295, seconds = 60, deaths = 0, mistakes = 0, partySize = 1, damageShare = 1, secrets = 2, secretsTotal = 2, runId = "OBS3"})
ok(r4 and r4.ok == false, "cooldown refuses the next clear")
eq(cmd(hero, "state").feats.done["floor:2.clear"], nil, "a refused grant earns no feat")

-- C7. World boss reward.
hero.last = nil
reply = invoke("worldBoss", hero, {boss = "Aurelith", tier = "Champion", rank = 1, share = 0.2, damage = 600000, sigils = 0, fight = 4, seconds = 120})
ok(reply and reply.ok, "world boss paid")
s = cmd(hero, "state")
ok(s.feats.done["world:Aurelith.first"] and s.feats.done["world:Aurelith.top"] and s.feats.done["world:Aurelith.share"] and s.feats.done["world:Aurelith.speed"], "world boss feats")
reply = invoke("worldBoss", hero, {boss = "Aurelith", tier = "Champion", rank = 1, share = 0.2, damage = 600000, sigils = 0, fight = 4, seconds = 120})
ok(reply and reply.ok == false and reply.reason == "paid", "world boss resend refused")
eq(cmd(hero, "state").feats.kc["world:Aurelith|"], 1, "world boss counted once")

-- C8. Slayer boss (quest boss win with the server-timed fight and hits).
hero = seeded(7001, function(prof)
	prof.slayerQuest = {line = "Bramble", tier = 3, progress = 100, needed = 100, bossReady = true}
end)
local slayerBefore = cmd(hero, "state").feats.points
reply = invoke("slayerBoss", hero, {result = "win", seconds = 80, hits = 0})
ok(reply and reply.ok, "slayer boss win settled")
s = cmd(hero, "state")
for _, k in ipairs({"first", "tier2", "tier3", "brisk", "untouched"}) do ok(s.feats.done["slayer:Bramble." .. k] ~= nil, "slayer feat " .. k) end
ok(s.feats.points > slayerBefore, "slayer feats add points")
reply = invoke("slayerBoss", hero, {result = "win", seconds = 10, hits = 0})
ok(reply and reply.ok == false, "no quest, no second slayer win")

-- C9. Tier rewards: claim once, no coins, hilt only.
s = cmd(hero, "state")
local tierNow = s.feats.tier
ok(tierNow >= 2, "enough points for Medium (" .. s.feats.points .. " points, tier " .. tierNow .. ")")
local coinsBefore = s.coins
local itemsBefore = copy(s.items)
for i = 1, tierNow do
	local id = FT.Tiers[i].id
	local c = cmd(hero, "featClaim", id)
	ok(has(c.message, "claimed"), id .. " claimed: " .. tostring(c.message))
	eq(c.items[FT.Rewards[id].hilt], (itemsBefore[FT.Rewards[id].hilt] or 0) + 1, id .. " hilt granted once")
	ok(has(cmd(hero, "featClaim", id).message, "already claimed"), id .. " cannot be claimed twice")
end
s = cmd(hero, "state")
eq(s.coins, coinsBefore, "tier claims grant no coins")
if tierNow < #FT.Tiers then
	ok(has(cmd(hero, "featClaim", FT.Tiers[tierNow + 1].id).message, "needs"), "an unreached tier is refused")
end
ok(has(cmd(hero, "featClaim", "Bogus").message, "Choose"), "a bogus tier is refused")
eq(count(s.feats.claimable), 0, "nothing left to claim")
saved = stored(hero)
ok(saved.feats.claimed.Easy == true, "claims saved")
hero = player(7001)
ok(has(cmd(hero, "featClaim", "Easy").message, "already claimed"), "claims survive a rejoin")
-- Selling a hilt pays its 1-coin value at most once per claim (no mint loop).
local sold = cmd(hero, "sell", FT.Rewards.Easy.hilt)
s = cmd(hero, "state")
ok(s.coins - coinsBefore <= 1, "a hilt is worth at most a coin")
ok(has(cmd(hero, "featClaim", "Easy").message, "already claimed"), "a sold hilt is not re-claimable")

-- C10. Feat teleports: daily charges, busy gate, region gate, FastTravelAt.
s = cmd(hero, "state")
local max = s.feats.teleports.max
ok(max >= 1, "teleports unlocked at Medium (" .. max .. ")")
hero.attrs.LairBoss = "Bramblemaw"
ok(has(cmd(hero, "featTeleport", "lairBramblemaw").message, "Finish your"), "no teleport out of a lair")
hero.attrs.LairBoss = ""
local before = hero.attrs.FastTravelAt
local t1 = cmd(hero, "featTeleport", "lairBramblemaw")
ok(has(t1.message, "Feat teleport"), "teleported: " .. tostring(t1.message))
ok(hero.root.Position.X == 500 and hero.attrs.FastTravelAt ~= before, "moved to the anchor with FastTravelAt")
eq(t1.feats.teleports.left, max - 1, "a charge spent")
ok(has(cmd(hero, "featTeleport", "raid").message, if max > 1 then "settling" else "No feat teleports left"), "cooldown between teleports / charges spent")
for _ = 2, max do advance(FT.TELEPORT_COOLDOWN + 1); hero = player(7001); cmd(hero, "featTeleport", "observatory") end
advance(FT.TELEPORT_COOLDOWN + 1)
hero = player(7001)
ok(has(cmd(hero, "featTeleport", "observatory").message, "No feat teleports left"), "charges run out for the day")
ok(has(cmd(hero, "featTeleport", "nowhere").message, "Choose"), "unknown destination refused")
-- A new day refills (rolls forward only).
advance(FT.DAY_SECONDS)
hero = player(7001)
eq(cmd(hero, "state").feats.teleports.left, max, "refilled the next day")
-- Region gate: a journal without the Shattered Crown quest cannot port to the altar.
local rookie = seeded(7002, function(prof)
	prof.feats = {v = 1, done = {}, kc = {}, claimed = {}, tele = {day = 0, used = 0}, seen = {}}
	for _, t in ipairs(FT.Tasks) do if t.tier == "Easy" or t.tier == "Medium" then prof.feats.done[t.id] = 1 end end
end)
ok(not has(cmd(rookie, "featTeleport", "altar").message, "Feat teleport"), "region gate holds for feat teleports")
-- Hooks: boss loot rolls read the boss Magic Find perk; slayer boss XP reads the perk.
do
	local src = fs.readFile("server.server.lua")
	ok(has(src, "LR.Loot[payload.boss],stats.magicFind+(if Feats.bossMagicFind"), "lair loot rolls add the boss Magic Find perk")
	ok(has(src, "plan.drops,stats.magicFind+(if Feats.bossMagicFind"), "world boss loot rolls add it")
	ok(has(src, "tier.drops,stats.magicFind+perks.bossMagicFind"), "slayer boss loot rolls add it")
	ok(has(src, "tier.xp*(1+perks.slayerXp)"), "slayer boss XP perk")
end
print("PASS: " .. (checks - partC) .. " server assertions.")

------------------------------------------------------------------------------
-- Part D: the atlas (Menu › Combat Feats).
------------------------------------------------------------------------------
local partD = checks
do
	local H = require("./tools/ui-harness")
	local snap = H.snapshot()
	local done = {["lair:Bramblemaw.first"] = 1, ["floor:1.clear"] = 1}
	snap.feats = {points = FT.Thresholds[1], total = FT.TOTAL_POINTS, tier = 1, done = done, kc = {["lair:Bramblemaw|"] = 7}, claimed = {}, claimable = {"Easy"},
		perks = FT.perks(FT.Thresholds[1]), teleports = {left = 0, max = 0, resetIn = 100, readyIn = 0}}
	snap.announce = {seq = 0, list = {}}
	local ui = H.runAtlas(roblox.Vector2.new(1366, 768), {snapshot = snap})
	local sidebar = H.find(ui.gui, "Sidebar")
	H.press(H.find(sidebar, "AtlasButton"))
	local tileButton = H.find(ui.scroll, "MenuFeats")
	ok(tileButton ~= nil, "Menu grid has the Combat Feats tile")
	H.press(tileButton)
	ok(H.find(ui.scroll, "FeatsSummary") ~= nil, "Feats page summary card")
	local claim = H.find(ui.scroll, "FeatClaimEasy")
	ok(claim ~= nil, "a reached tier offers Claim")
	local n0 = #ui.sent
	H.press(claim)
	local sentClaim = false
	for i = n0 + 1, #ui.sent do if ui.sent[i][1] == "featClaim" and ui.sent[i][2] == "Easy" then sentClaim = true end end
	ok(sentClaim, "Claim sends featClaim Easy")
	ok(H.find(ui.scroll, "Feat_lair_Bramblemaw_first") ~= nil and H.find(ui.scroll, "Feat_floor_7_masterSpeed") ~= nil, "all tiers list every task")
	-- Tier tab: Grandmaster only.
	local tabButton = H.find(ui.scroll, "FeatTierGrandmaster")
	ok(tabButton ~= nil, "tier tabs")
	H.press(tabButton)
	ok(H.find(ui.scroll, "Feat_floor_7_masterSpeed") ~= nil and H.find(ui.scroll, "Feat_lair_Bramblemaw_first") == nil, "the Grandmaster tab filters")
	-- Boss filter: Bramblemaw, all tiers.
	H.press(H.find(ui.scroll, "FeatTierAll"))
	local bossButton = H.find(ui.scroll, "FeatBossBramblemaw")
	ok(bossButton ~= nil, "boss filter")
	H.press(bossButton)
	ok(H.find(ui.scroll, "Feat_lair_Bramblemaw_kc25") ~= nil and H.find(ui.scroll, "Feat_floor_1_clear") == nil, "the boss filter shows one boss")
	local kcCard = H.find(ui.scroll, "Feat_lair_Bramblemaw_kc25")
	ok(H.find(kcCard, "Progress") ~= nil, "kill-count tasks show a progress bar")
	ok(H.find(H.find(ui.scroll, "Feat_lair_Bramblemaw_first"), "Badge") ~= nil, "done tasks carry a DONE badge")
	-- Phone layout renders too.
	local phone = H.runAtlas(roblox.Vector2.new(844, 390), {snapshot = snap})
	H.press(H.find(H.find(phone.gui, "Sidebar"), "AtlasButton"))
	H.press(H.find(phone.scroll, "MenuFeats"))
	ok(H.find(phone.scroll, "FeatsSummary") ~= nil, "phone: Feats page")
end
print("PASS: " .. (checks - partD) .. " atlas assertions.")
print("Combat Feats QA passed " .. checks .. " checks.")
print("SUITE-END verify-feats.luau")
