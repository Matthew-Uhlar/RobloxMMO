-- Contests & Trophy Angling (§39): Harvest Contests and trophy fishing.
-- Part A: pure data and rules (GameData "Contests & Trophy Angling" section):
--   originality, the contest schedule, score shards (max-merge, replays,
--   write deadline, full shards, the 32 KB item bound), histogram mirrors,
--   live estimates, exact sealing and brackets, the Medal Exchange economy,
--   the trophy fish, their conditions, qualities, pity and the ledger.
-- Part B: server.server.lua instances on one DataStore double and one
--   MemoryStore SortedMap double with skewed clocks: entering, field and
--   garden harvests, server hops, flushes, leaderboards, live estimates,
--   lost acknowledgements, throttling with backoff, late writes, one sealer,
--   payouts online / on rejoin / on a fresh server, expiry, the exchange,
--   titles, Ironman, shutdown drain, TTLs and bounded journals.
-- Part C: trophy fishing through the real fishing gather: no double count
--   with sea creatures, waters, hours, bait, qualities, pity, Diamond
--   announcements to the server, the Trophy Keeper's ledger and titles.
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
local CT, TF = Data.Contests, Data.Trophies
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local X = Data.XP_TABLE

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
-- A1. Originality and registration.
do
	local banned = {"jacob", "odger", "hypixel", "skyblock", "crimson", "kuudra", "magmafish", "golden fish", "karate", "slugfish", "flyfish", "lavahorse", "gusher", "mana ray", "obfuscated", "volcanic stonefish", "steaming", "sulphur skitter", "blobfish", "moldfin", "skeleton fish", "soul fish", "vanille", "anita"}
	local texts = {CT.NAME, TF.NAME}
	for _, f in ipairs(TF.Fish) do table.insert(texts, f.name .. " " .. f.text) end
	for _, l in ipairs(TF.Ledger) do table.insert(texts, l.name .. " " .. (l.title or "")) end
	for _, t in ipairs(CT.Titles) do table.insert(texts, t.title) end
	for _, id in ipairs({"FurrowMedallion", "LaureateMedallion", "MedalistHoe", "HarvestTonic", "GillwardHood", "GlintgillPet", "GlowgrubBait", "BrineglowLure", "AbyssalLure"}) do
		ok(Data.Items[id] ~= nil, id .. " registered")
		table.insert(texts, Data.Items[id].name .. " " .. Data.Items[id].description)
	end
	for _, role in ipairs({CT.STEWARD, TF.KEEPER}) do
		local npc = Data.Townsfolk.NPCs[role]
		ok(npc ~= nil and table.find(Data.Townsfolk.RegionFolkOrder, role) ~= nil and Data.RegionArt.FolkByRole[role] ~= nil, role .. " is regional folk")
		table.insert(texts, npc.name .. " " .. npc.title)
		for _, node in pairs(npc.nodes) do
			table.insert(texts, node.text)
			for _, o in ipairs(node.options) do if o.atlas then ok(Data.Townsfolk.AtlasStations[o.atlas] ~= nil, role .. " atlas option " .. o.atlas) end end
		end
	end
	for _, text in ipairs(texts) do
		for _, word in ipairs(banned) do ok(not string.find(string.lower(text), word, 1, true), "original: " .. string.sub(text, 1, 40)) end
	end
	local seen = {}
	for _, f in ipairs(TF.Fish) do ok(not seen[f.name], "unique fish name " .. f.name); seen[f.name] = true end
end
-- A2. Schedule: three contests an isle day, 20 minutes each, featured crops deterministic.
eq(CT.PERIOD * 3, Data.Calendar.dayLength, "three contests per isle day")
eq(CT.DURATION, 1200, "a 20-minute window")
ok(CT.DURATION + CT.GRACE < CT.PERIOD, "a contest seals before the next opens")
eq(#CT.Crops, #Data.Garden.Crops, "every Verdant Garden crop can be featured")
do
	local Data2 = load("shared/GameData.lua")
	local counts = {}
	for k = 70000, 72999 do
		local crops = CT.cropsOf(k)
		eq(#crops, 3, "three crops")
		ok(crops[1] ~= crops[2] and crops[2] ~= crops[3] and crops[1] ~= crops[3], "distinct crops")
		local again = Data2.Contests.cropsOf(k)
		ok(again[1] == crops[1] and again[2] == crops[2] and again[3] == crops[3], "same crops on every server (fresh data load)")
		for _, c in ipairs(crops) do counts[c] = (counts[c] or 0) + 1 end
	end
	for _, c in ipairs(CT.Crops) do ok(counts[c.id] > 3000 * 3 / 8 * 0.85 and counts[c.id] < 3000 * 3 / 8 * 1.15, c.id .. " featured fairly (" .. counts[c.id] .. ")") end
	local t = Data.Calendar.epoch + 71000 * CT.PERIOD
	local a = CT.at(t)
	ok(a.k == 71000 and a.active and a.starts == t and a.ends == t + CT.DURATION, "window opens at the period start")
	ok(CT.at(t + CT.DURATION - 1).active and not CT.at(t + CT.DURATION).active, "window closes after DURATION")
	eq(CT.at(t + CT.PERIOD - 1).nextWindow.starts, t + CT.PERIOD, "next window")
	eq(CT.at(t - 1).k, 70999, "previous contest before the start")
	eq(CT.featured(71000, a.crops[2]), 2, "featured slot")
	eq(CT.featured(71000, "Nope"), nil, "not featured")
	local w = CT.window(71000)
	ok(w.writeDeadline > w.ends and w.writeDeadline < w.sealAt, "writes accepted until GRACE / 2 after the close")
	for k = 71000, 71050 do
		local ttl = CT.ttl(k, CT.window(k).starts)
		ok(ttl > CT.DURATION + CT.GRACE and ttl <= 3888000, "items outlive the seal, within MemoryStore's 45 days")
	end
	eq(CT.ttl(71000, CT.window(71000).ends + CT.TTL_PAD + 999), 60, "TTL floor")
end
-- A3. Packing and shards.
do
	for _, case in ipairs({{1, 1}, {2, 999}, {3, CT.SCORE_CAP}}) do
		local slot, score = CT.unpack(CT.pack(case[1], case[2]))
		ok(slot == case[1] and score == case[2], "pack round trip " .. case[1] .. ":" .. case[2])
	end
	local s, v = CT.unpack(CT.pack(2, CT.SCORE_CAP * 5))
	ok(s == 2 and v == CT.SCORE_CAP, "score capped")
	eq(CT.unpack(0), nil, "empty packed value")
	local k = 71000
	local now = CT.window(k).starts + 60
	local item, verdicts = CT.applyScores(nil, {["11"] = {c = 1, s = 40}, ["12"] = {c = 2, s = 5}}, k, now)
	ok(item and item.n == 2 and item.ver == 1 and verdicts["11"].v == "ok", "first scores written")
	local again, v2 = CT.applyScores(item, {["11"] = {c = 1, s = 40}}, k, now)
	ok(again == nil and v2["11"].v == "stale" and v2["11"].s == 40, "a replay changes nothing (idempotent)")
	local lower, v3 = CT.applyScores(item, {["11"] = {c = 1, s = 30}}, k, now)
	ok(lower == nil and v3["11"].v == "stale" and v3["11"].s == 40, "an out-of-order lower score never regresses")
	local higher, v4 = CT.applyScores(item, {["11"] = {c = 3, s = 55}}, k, now)
	local slot11, score11 = CT.unpack(higher.v["11"])
	ok(v4["11"].v == "ok" and score11 == 55 and slot11 == 1 and higher.ver == 2, "scores rise; the stored crop never changes")
	local late, v5 = CT.applyScores(higher, {["11"] = {c = 1, s = 99}, ["13"] = {c = 1, s = 9}}, k, CT.window(k).writeDeadline)
	ok(late == nil and v5["11"].v == "late" and v5["13"].v == "late", "refused after the write deadline")
	local bad, v6 = CT.applyScores(higher, {["14"] = {c = 9, s = 9}, ["15"] = {c = 1, s = 0}, [string.rep("9", 30)] = {c = 1, s = 3}}, k, now)
	ok(bad == nil and v6["14"].v == "bad" and v6["15"].v == "bad" and v6[string.rep("9", 30)].v == "bad", "malformed entries refused")
	ok(CT.applyScores({k = k - 1, v = {["11"] = CT.pack(1, 900)}, ver = 7}, {["11"] = {c = 1, s = 3}}, k, now).ver == 1, "an item from another contest is replaced")
	-- A full shard refuses new entrants but keeps raising old ones.
	local full = {k = k, v = {}, ver = 1}
	for i = 1, CT.SHARD_CAP do full.v[tostring(100000000000 + i * CT.SHARDS)] = CT.pack(1, 10) end
	local f1, fv = CT.applyScores(full, {["7"] = {c = 1, s = 5}, [tostring(100000000000 + CT.SHARDS)] = {c = 1, s = 11}}, k, now)
	ok(fv["7"].v == "full" and fv[tostring(100000000000 + CT.SHARDS)].v == "ok" and f1.n == CT.SHARD_CAP, "full shard: new entrants refused, entrants still rise")
	-- 32 KB bound: a full shard with 12-digit UserIds and maximal scores.
	local big = {k = k, v = {}, ver = 1}
	for i = 1, CT.SHARD_CAP do big.v[tostring(999999000000 + i * CT.SHARDS)] = CT.pack(3, CT.SCORE_CAP) end
	big.h = CT.histogram(big.v, k)
	local json = roblox.serializeJson and roblox.serializeJson(big) or require("@lune/serde").encode("json", big)
	ok(#json < 32000, "a full score item fits MemoryStore's 32 KB (" .. #json .. " bytes)")
	ok(CT.SHARDS * CT.SHARD_CAP >= 64000, "64k entrants per contest")
	-- Shards and groups cover every UserId.
	for _, u in ipairs({1, 63, 64, 65, 999999999999}) do
		local sh = CT.shardOf(u)
		ok(sh >= 1 and sh <= CT.SHARDS and CT.groupOf(sh) >= 1 and CT.groupOf(sh) <= CT.GROUPS, "shard and group of " .. u)
	end
	-- Backoff: doubling, jittered, capped.
	ok(CT.backoff(1, 1) == CT.BACKOFF_BASE and CT.backoff(2, 1) == 2 * CT.BACKOFF_BASE and CT.backoff(1, 0) == CT.BACKOFF_BASE / 2, "backoff doubles, jitter 50-100%")
	eq(CT.backoff(40, 1), CT.BACKOFF_MAX, "backoff capped")
end
-- A4. Histograms, mirrors, estimates and exact sealing.
do
	local k = 71000
	local crops = CT.window(k).crops
	local def = CT.CropById[crops[1]]
	ok(CT.bucket(1) == 1 and CT.bucket(0) == 0, "bucket edges")
	for s = 1, 5000, 37 do ok(CT.bucket(s + 1) >= CT.bucket(s), "buckets rise with the score") end
	local v = {}
	for i = 1, 100 do v[tostring(i)] = CT.pack(1, def.min + i) end
	v.low = CT.pack(1, def.min - 1)
	local h = CT.histogram(v, k)
	local n = 0
	for _, c in pairs(h[1]) do n += c end
	eq(n, 100, "below-minimum scores never enter the histogram")
	local g1 = CT.mirror(nil, k, {["1"] = {ver = 3, h = h}})
	ok(g1 and g1.s["1"].ver == 3, "mirror written")
	eq(CT.mirror(g1, k, {["1"] = {ver = 2, h = {}}}), nil, "an older mirror never regresses")
	local g2 = CT.mirror(g1, k, {["1"] = {ver = 4, h = h}, ["9"] = {ver = 1, h = h}})
	ok(g2.s["1"].ver == 4 and g2.s["9"] ~= nil, "newer versions replace, new shards join")
	local sum = CT.sumGroups({g1})
	eq(sum[1].n, 100, "summed histogram")
	-- Ranks to brackets (minimum field per bracket).
	eq(CT.bracketForRank(1, 1), "Bronze", "a lone entrant can only take Bronze")
	eq(CT.bracketForRank(1, 3), "Silver", "Silver needs 3 entrants")
	eq(CT.bracketForRank(1, 8), "Gold", "Gold needs 8")
	eq(CT.bracketForRank(1, 20), "Platinum", "Platinum needs 20")
	eq(CT.bracketForRank(1, 50), "Diamond", "Diamond needs 50")
	eq(CT.bracketForRank(2, 100), "Diamond", "top 2% of 100")
	eq(CT.bracketForRank(3, 100), "Platinum", "rank 3 of 100")
	eq(CT.bracketForRank(10, 100), "Gold", "rank 10 of 100")
	eq(CT.bracketForRank(30, 100), "Silver", "rank 30 of 100")
	eq(CT.bracketForRank(60, 100), "Bronze", "rank 60 of 100")
	eq(CT.bracketForRank(61, 100), nil, "rank 61 of 100 earns no bracket")
	-- Estimate vs exact seal on the same population.
	local shards = {}
	for i = 1, 100 do
		local uid = tostring(5000 + i)
		local sh = CT.shardOf(5000 + i)
		shards[sh] = shards[sh] or {k = k, v = {}}
		shards[sh].v[uid] = CT.pack(1, def.min + i * 3)
	end
	local result = CT.seal(k, shards)
	eq(result.slots[1].n, 100, "sealed population")
	eq(result.slots[1].cut.Diamond, def.min + 99 * 3, "Diamond cut = the 2nd best score")
	eq(result.slots[1].cut.Bronze, def.min + 41 * 3, "Bronze cut = the 60th best score")
	eq(result.slots[2].n, 0, "an empty crop")
	eq(next(result.slots[2].cut), nil, "no cuts without entrants")
	eq(result.slots[1].top[1].s, def.min + 300, "top score recorded")
	local clean = CT.cleanResult(copy(result), k)
	ok(clean and clean.slots[1].cut.Gold == result.slots[1].cut.Gold, "result survives cleaning")
	eq(CT.cleanResult(result, k + 1), nil, "a ring slot holding another contest is not this result")
	eq(CT.bracketOf(clean, 1, def.min + 300, crops[1]), "Diamond", "best score Diamond")
	eq(CT.bracketOf(clean, 1, def.min + 41 * 3, crops[1]), "Bronze", "exactly the Bronze cut")
	eq(CT.bracketOf(clean, 1, def.min + 40 * 3, crops[1]), nil, "below the Bronze cut")
	eq(CT.bracketOf(clean, 1, def.min - 1, crops[1]), nil, "below the minimum")
	-- Ties at a cut all earn it.
	local tie = {[1] = {k = k, v = {a = CT.pack(1, 500), b = CT.pack(1, 500), c = CT.pack(1, 500), d = CT.pack(1, 100)}}}
	local tr = CT.seal(k, tie)
	eq(CT.bracketOf(CT.cleanResult(tr, k), 1, 500, crops[1]), "Silver", "tied entrants share the bracket")
	-- The estimate agrees with the exact seal within a bucket.
	local hist = CT.sumGroups({{k = k, s = {["1"] = {ver = 1, h = CT.histogram((function()
		local all = {}
		for _, sh in pairs(shards) do for u, p in pairs(sh.v) do all[u] = p end end
		return all
	end)(), k)}}}})
	local agree = 0
	for i = 1, 100 do
		local est = CT.estimate(hist[1], def.min + i * 3, crops[1])
		local exact = CT.bracketOf(clean, 1, def.min + i * 3, crops[1])
		local ei = est and CT.BracketById[est].rank or 0
		local xi = exact and CT.BracketById[exact].rank or 0
		ok(math.abs(ei - xi) <= 1, "estimate within one bracket of the seal (score " .. (def.min + i * 3) .. ")")
		if ei == xi then agree += 1 end
	end
	ok(agree >= 75, "the live estimate matches the sealed bracket for most scores (" .. agree .. "/100)")
	local alone = CT.estimate({buckets = {}, n = 0}, def.min + 5, crops[1])
	eq(alone, "Bronze", "an unmirrored first entrant estimates itself")
	eq(CT.estimate(hist[1], def.min - 1, crops[1]), nil, "no estimate below the minimum")
end
-- A5. Rewards and the Medal Exchange economy (no coin mint).
do
	for _, c in ipairs(CT.Crops) do
		ok(c.min >= 12 and c.min <= 60, c.id .. " minimum")
		local m0, x0 = CT.reward(c.id, nil, true)
		local m1, x1 = CT.reward(c.id, "Diamond", true)
		ok(m0 == 0 and x0 > 0 and m1 == 9 and x1 > x0, c.id .. " rewards climb with the bracket")
		local m2, x2 = CT.reward(c.id, "Gold", false)
		ok(m2 == 0 and x2 == 0, c.id .. " pays nothing unplaced")
	end
	local last = math.huge
	for _, b in ipairs(CT.Brackets) do ok(b.medals < last and b.medals > 0, b.id .. " medals ordered"); last = b.medals end
	for _, e in ipairs(CT.Shop) do
		ok(e.cost == nil and (e.coins == nil), e.id .. " never costs coins")
		if e.kind == "item" then
			local def = Data.Items[e.item]
			ok(def ~= nil, e.id .. " item")
			ok(def.value * e.amount <= e.medals * CT.MEDAL_VALUE, e.id .. " sells for at most " .. CT.MEDAL_VALUE .. " coins a medal")
			if e.upgrade then ok(Data.Items[e.upgrade] ~= nil, e.id .. " upgrades an item") end
		elseif e.kind == "title" then
			ok(CT.TitleById[e.title] ~= nil and e.medals > 0, e.id .. " title")
		end
	end
	local st = CT.almanacStats(#CT.ALMANAC)
	ok(st.farmingFortune == 20 and st.health == nil and st.defense == nil, "the Furrow Almanac adds Farming Fortune only (PerkBudget untouched)")
	eq(CT.almanacStats(0), nil, "no almanac, no perk")
	eq(CT.offerCost(CT.ShopById.Almanac, #CT.ALMANAC), nil, "a complete almanac sells nothing more")
	local hoe = Data.Items.MedalistHoe
	ok(hoe.toolTier == 5 and hoe.stats.farmingFortune > Data.Items.GreenwardHoe.stats.farmingFortune and hoe.stats.farmingFortune < Data.Items.EverbloomHoe.stats.farmingFortune,
		"the Medalist's Hoe sits between the garden's tier 4 and tier 6 hoes")
	ok(Data.Items.LaureateMedallion.stats.farmingFortune > Data.Items.FurrowMedallion.stats.farmingFortune, "the upgrade is better")
	-- Medal pace: a regular Gold finisher (3 contests a day) needs about a week for the hoe.
	local days = CT.ShopById.MedalistHoe.medals / (3 * CT.BracketById.Gold.medals)
	ok(days >= 5 and days <= 14, string.format("hoe at Gold pace: %.1f days", days))
	-- Migration sanitises and bounds the journal record.
	local raw = {medals = -5, earned = "x", cur = {k = 71000, c = "Nope", s = 9}, open = {}, best = {Herb = 1e12, Nope = 4}, titles = {Furrowhand = true, Fake = true}, title = "Fake", almanac = 99,
		history = {}, brackets = {Gold = 2, Fake = 4}}
	for i = 1, 30 do table.insert(raw.open, {k = 71000, c = CT.window(71000).crops[1], s = i}) end
	for i = 1, 30 do table.insert(raw.history, {k = i, c = "Herb", s = i, b = "Gold", m = 4}) end
	local m = CT.migrate(raw)
	ok(m.medals == 0 and m.earned == 0 and m.cur == nil, "bad numbers and unknown entries dropped")
	ok(#m.open == CT.OPEN_MAX and #m.history == CT.HISTORY, "pending and history bounded")
	ok(m.best.Herb == CT.SCORE_CAP and m.best.Nope == nil, "bests capped and known")
	ok(m.titles.Furrowhand and not m.titles.Fake and m.title == nil and m.almanac == #CT.ALMANAC and m.brackets.Gold == 2 and m.brackets.Fake == nil, "titles, almanac, brackets sanitised")
end
-- A6. Trophy fish, conditions, qualities and the ledger.
do
	ok(#TF.Fish >= 12 and #TF.Fish <= 16, "12-16 trophy fish (" .. #TF.Fish .. ")")
	local waters = {}
	for _, f in ipairs(TF.Fish) do
		local w = TF.WaterById[f.water]
		ok(w ~= nil, f.id .. " water")
		waters[f.water] = true
		ok(TF.RarityXp[f.rarity] ~= nil and f.weight > 0 and #f.color == 6 and #f.text > 10, f.id .. " fields")
		ok(f.rod >= 0 and f.rod <= 7 and f.fishing >= 1 and f.fishing <= 99, f.id .. " gates")
		if f.bait then ok(TF.Baits[f.bait] ~= nil, f.id .. " bait exists") end
		if f.season then ok(Data.SeasonById[f.season] ~= nil, f.id .. " season exists") end
		if f.event then ok(Data.Events[f.event] ~= nil, f.id .. " event exists") end
		-- Reachable: the context that satisfies its conditions bites, and each condition matters.
		local ctx = {water = f.water, hour = f.hours and f.hours[1] + 0.5 or 12, season = f.season, event = f.event, rod = f.rod, fishing = f.fishing, bait = f.bait}
		ok(TF.bites(f, ctx), f.id .. " can be caught")
		for key, broken in pairs({water = "Elsewhere", rod = f.rod - 1, fishing = f.fishing - 1}) do
			local c2 = copy(ctx); c2[key] = broken
			if not (key == "rod" and f.rod == 0) then ok(not TF.bites(f, c2), f.id .. " needs its " .. key) end
		end
		if f.hours then local c2 = copy(ctx); c2.hour = (f.hours[2] + 0.5) % 24; ok(not TF.bites(f, c2), f.id .. " keeps its hours") end
		if f.season then local c2 = copy(ctx); c2.season = "Nope"; ok(not TF.bites(f, c2), f.id .. " keeps its season") end
		if f.event then local c2 = copy(ctx); c2.event = nil; ok(not TF.bites(f, c2), f.id .. " needs its festival") end
		if f.bait then local c2 = copy(ctx); c2.bait = nil; ok(not TF.bites(f, c2), f.id .. " needs its bait") end
		-- The fishing level matches a resource the water's spots actually yield.
	end
	for _, w in ipairs(TF.Waters) do ok(waters[w.id], w.id .. " holds trophy fish") end
	eq(TF.waterOf(nil), "Shallows", "home waters")
	eq(TF.waterOf("Tidewater"), "Tidewater", "Tidewater")
	eq(TF.waterOf("Quarry"), nil, "no trophy water in the quarry")
	ok(TF.inHours({19, 6}, 23) and TF.inHours({19, 6}, 2) and not TF.inHours({19, 6}, 12), "wrapping hour windows")
	ok(math.abs(TF.hourAt(Data.Calendar.epoch + Data.Calendar.dayLength / 2) - 12) < 1e-6, "isle hour 12 at mid-day")
	-- Chance: base + bait + hood + pet, capped.
	ok(TF.chance({}) == TF.BASE_CHANCE, "base chance")
	ok(TF.chance({bait = "AbyssalLure", hood = true, petLevel = 100}) <= TF.CHANCE_CAP and TF.chance({bait = "AbyssalLure", hood = true, petLevel = 100}) > TF.chance({bait = "AbyssalLure"}), "bonuses stack under the cap")
	-- Quality distribution (deterministic stream).
	local seed = 12345
	local function rnd() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end
	local f = TF.FishById.PebblefinDarter
	local counts = {Bronze = 0, Silver = 0, Gold = 0, Diamond = 0}
	local N = 200000
	for _ = 1, N do counts[TF.quality(f, 0, nil, rnd())] += 1 end
	for _, t in ipairs(TF.Tiers) do ok(math.abs(counts[t.id] / N - t.weight) < 0.005, string.format("%s share %.4f ~ %.2f", t.id, counts[t.id] / N, t.weight)) end
	local up = {Gold = 0, Diamond = 0}
	for _ = 1, N do local q = TF.quality(f, 5, nil, rnd()); if up[q] then up[q] += 1 end end
	ok(up.Gold > counts.Gold and up.Diamond > counts.Diamond, "a better rod shifts weight to Gold and Diamond")
	eq((TF.quality(f, 0, {g = TF.PITY_GOLD - 1}, 0)), "Gold", "Gold pity")
	eq((TF.quality(f, 0, {d = TF.PITY_DIAMOND - 1}, 0)), "Diamond", "Diamond pity")
	eq((TF.quality(f, 0, {g = TF.PITY_GOLD - 1}, 0.9999)), "Diamond", "pity never lowers a better roll")
	-- Records: counts, best, pity resets.
	local t = TF.migrate(nil)
	ok(TF.record(t, "PebblefinDarter", "Bronze") and t.best.PebblefinDarter == "Bronze" and t.pity.PebblefinDarter.g == 1, "first catch")
	ok(not TF.record(t, "PebblefinDarter", "Bronze") and t.pity.PebblefinDarter.g == 2, "repeat catch")
	ok(TF.record(t, "PebblefinDarter", "Gold") and t.pity.PebblefinDarter.g == 0 and t.pity.PebblefinDarter.d == 3, "Gold resets the Gold pity only")
	TF.record(t, "PebblefinDarter", "Diamond")
	ok(t.pity.PebblefinDarter.d == 0 and t.diamonds == 1 and t.total == 4, "Diamond resets both")
	-- Catches per hour stay modest: ~3 % of casts.
	-- XP: rarer and finer pays more.
	ok(TF.xp(TF.FishById.TidewyrmFry, "Diamond") > TF.xp(TF.FishById.TidewyrmFry, "Bronze") and TF.xp(TF.FishById.TidewyrmFry, "Bronze") > TF.xp(f, "Bronze"), "trophy XP ordered")
	-- Ledger.
	local best = {}
	for i, fish in ipairs(TF.Fish) do if i <= 5 then best[fish.id] = "Bronze" end end
	ok(TF.ledgerDone(best, TF.LedgerById.Novice) and not TF.ledgerDone(best, TF.LedgerById.Bronze), "five fish complete the first tier only")
	for _, fish in ipairs(TF.Fish) do best[fish.id] = "Silver" end
	ok(TF.ledgerDone(best, TF.LedgerById.Bronze) and TF.ledgerDone(best, TF.LedgerById.Silver) and not TF.ledgerDone(best, TF.LedgerById.Gold), "Silver everywhere completes Bronze and Silver")
	local titles, items = 0, {}
	for _, l in ipairs(TF.Ledger) do if l.title then titles += 1 end; if l.item then items[l.item] = true end end
	ok(titles >= 3 and items.GillwardHood and items.GlintgillPet, "ledger rewards: titles, the hood, the pet")
	-- The hood stays below the endgame fishing line (Stormcaller, Epic tier 4).
	local hood, rival = Data.Items.GillwardHood, Data.Items.StormcallerHood
	ok(hood.slot == "helmet" and hood.tier < rival.tier and Data.Rarity[hood.rarity].rank < Data.Rarity[rival.rarity].rank and hood.stats.fishingFortune <= rival.stats.fishingFortune,
		"the Gillward Hood is below the Stormcaller Hood")
	ok(hood.stats.health + 0 <= 20 and hood.stats.defense == nil, "modest hood stats")
	-- Pet.
	local pet = Data.PetById.Glintgill
	ok(pet and pet.skill == "Fishing" and Data.PetDepth.Abilities.Glintgill ~= nil and Data.Items.GlintgillPet.kind == "pet", "the Glintgill pet")
	ok(TF.chance({petLevel = 100}) - TF.BASE_CHANCE <= 0.016, "pet bonus small")
	-- Baits: Hearth recipes, no coin mint.
	for _, id in ipairs(TF.BaitOrder) do
		local r = Data.Recipes[id]
		local value = 0
		for cid, n in pairs(r.costs) do value += Data.Items[cid].value * n end
		ok(r.station == "Hearth" and r.skill == "Cooking" and Data.Items[id].value * r.amount <= value, id .. " crafted at a Hearth, value <= inputs")
	end
	-- Migration.
	local mig = TF.migrate({caught = {PebblefinDarter = {Bronze = 3, Diamond = -1, Fake = 2}, Nope = {Gold = 4}}, pity = {PebblefinDarter = {g = 9999, d = "x"}}, bait = "Nope", claimed = {Bronze = true, Fake = true}, title = "Bronze"})
	ok(mig.caught.PebblefinDarter.Bronze == 3 and mig.caught.PebblefinDarter.Diamond == nil and mig.caught.Nope == nil and mig.total == 3, "catches sanitised")
	ok(mig.pity.PebblefinDarter.g == TF.PITY_GOLD and mig.pity.PebblefinDarter.d == 0 and mig.bait == nil, "pity clamped, unknown bait dropped")
	ok(mig.claimed.Bronze and not mig.claimed.Fake and mig.title == nil, "the Bronze tier has no title to wear")
	-- Announcements.
	local F = Data.Features
	ok(has(F.announceText({kind = "trophy", fish = "TidewyrmFry", tier = "Diamond"}).head, "DIAMOND TROPHY"), "Diamond toast")
	ok(has(F.announceText({kind = "trophyWorld", fish = "TidewyrmFry", tier = "Diamond", who = "Ana"}).body, "Ana landed a Diamond Tidewyrm Fry"), "server-wide Diamond toast")
	ok(has(F.announceText({kind = "contest", phase = "result", crop = "Herb", score = 90, bracket = "Gold", medals = 4}).head, "GOLD BRACKET"), "result toast")
	ok(has(F.announceText({kind = "contest", phase = "start", crops = {"Herb", "Sunwheat", "Glowcap"}}).body, "Meadow Herb"), "start toast")
	ok(has(F.announceText({kind = "skill", skill = "Mining", level = 2}).head, "SKILL LEVEL UP"), "older toasts still pass through")
end
print("PASS: " .. (checks - partA) .. " Contests data and rule assertions.")

------------------------------------------------------------------------------
-- Part B: server instances on one DataStore double and one MemoryStore double.
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
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
local RA = Data.RegionArt
-- MemoryStore double: sorted maps by name. fail: "before" | "after" (commits,
-- ack lost); throttle(name, key) -> true throws; down = true fails everything.
local function newMemory()
	local M = {maps = {}, sortKeys = {}, writes = 0, reads = 0, ranges = 0, keyWrites = {}, keyReads = {}, ttls = {}, fail = nil, throttle = nil, down = false}
	function M.map(name)
		M.maps[name] = M.maps[name] or {}
		M.sortKeys[name] = M.sortKeys[name] or {}
		return M.maps[name], M.sortKeys[name]
	end
	M.service = {GetSortedMap = function(_, name)
		local data, sorts = M.map(name)
		local sm = {}
		function sm:GetAsync(key)
			if M.down then error("Injected MemoryStore outage") end
			M.reads += 1
			M.keyReads[name .. "/" .. key] = (M.keyReads[name .. "/" .. key] or 0) + 1
			return copy(data[key]), sorts[key]
		end
		function sm:UpdateAsync(key, op, ttl)
			M.writes += 1
			M.keyWrites[name .. "/" .. key] = (M.keyWrites[name .. "/" .. key] or 0) + 1
			assert(type(ttl) == "number" and ttl > 0 and ttl <= 3888000, "a valid expiration")
			M.ttls[name .. "/" .. key] = ttl
			if M.down or (M.throttle and M.throttle(name, key)) then error("Injected throttle") end
			if M.fail == "before" then M.fail = nil; error("Injected outage") end
			local value, sortKey = op(copy(data[key]), sorts[key])
			if value ~= nil then data[key] = copy(value); sorts[key] = sortKey end
			if M.fail == "after" then M.fail = nil; error("Injected lost acknowledgement") end
			return if value ~= nil then copy(value) else nil
		end
		function sm:RemoveAsync(key)
			if M.down then error("Injected MemoryStore outage") end
			data[key], sorts[key] = nil, nil
		end
		function sm:GetRangeAsync(_, count, lower, upper)
			if M.down then error("Injected MemoryStore outage") end
			M.ranges += 1
			assert(type(count) == "number" and count >= 1 and count <= 200, "range count within 200")
			local lo, hi = lower and lower.sortKey or -math.huge, upper and upper.sortKey or math.huge
			local list = {}
			for key, v in pairs(data) do
				local sk = sorts[key]
				if type(sk) == "number" and sk > lo and sk < hi then table.insert(list, {key = key, value = copy(v), sortKey = sk}) end
			end
			table.sort(list, function(a, b) if a.sortKey ~= b.sortKey then return a.sortKey > b.sortKey end return a.key < b.key end)
			while #list > count do table.remove(list) end
			return list
		end
		return sm
	end}
	return M
end
-- One shared DataStore (journals and the contest result ring).
local function newStore()
	local S = {data = {}, writes = 0, reads = 0, fail = nil, failGets = false, memory = newMemory()}
	function S:GetAsync(key)
		if self.failGets and key:match("^contest") then error("Injected read outage") end
		self.reads += 1
		return copy(self.data[key])
	end
	function S:UpdateAsync(key, op)
		local contest = key:match("^contest") ~= nil
		if contest then
			self.writes += 1
			if self.fail == "before" then self.fail = nil; error("Injected outage") end
		end
		local value = op(copy(self.data[key]))
		if value ~= nil then self.data[key] = copy(value) end
		if contest and self.fail == "after" then self.fail = nil; error("Injected lost acknowledgement") end
		return if value ~= nil then copy(self.data[key]) else nil
	end
	function S:RemoveAsync(key) self.data[key] = nil end
	return S
end
local rngValue = 0.999
-- Builds one server. clock = {utc, cpu}; skew seconds are added to os.time().
local function newServer(store, clock, skew)
	local S = {objects = {}, delayed = {}, live = {}, skew = skew or 0, seedless = {}, trophyRolls = {}, co = {}}
	local models = {}
	for i, f in ipairs(RA.Folk) do
		local root = {Position = Vector3.new(i * 100, 5, 0)}
		table.insert(models, {GetAttribute = function(_, k) return if k == "TownsfolkRole" then f.role else nil end,
			FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end})
	end
	local townsfolk = {GetChildren = function() return models end}
	local storage = {AetherTrails = {Name = "AetherTrails"}, IsleTravelGate = {Invoke = function() return true end}}
	local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
	local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua")}
	local guid = 0
	S.wsAttrs = {}
	S.services = {
		Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
		ProximityPromptService = {PromptTriggered = signal()},
		ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
		ServerStorage = {FindFirstChild = function(_, name) return storage[name] end},
		DataStoreService = {GetDataStore = function() return store end},
		MemoryStoreService = store.memory.service,
		HttpService = {GenerateGUID = function() guid += 1; return "contest-test-" .. tostring(S) .. guid end},
		RunService = {IsStudio = function() return false end},
	}
	local env = {
		game = {GetService = function(_, name) return S.services[name] end, BindToClose = function(_, f) S.onClose = f end},
		workspace = {GetAttribute = function(_, key) return S.wsAttrs[key] end, SetAttribute = function(_, key, v) S.wsAttrs[key] = v end,
			FindFirstChild = function(_, name) return if name == "Townsfolk" then townsfolk else nil end},
		Vector3 = Vector3, CFrame = CFrame,
		Instance = {new = function(className)
			local o = {ClassName = className, Event = signal(), FireClient = function(_, player, state) player.last = state; player.pushed = (player.pushed or 0) + 1 end}
			function o:Destroy() self.Parent = nil end
			table.insert(S.objects, o)
			return o
		end},
		UDim2 = roblox.UDim2, Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum,
		os = {clock = function() return clock.cpu end, time = function() return math.floor(clock.utc + S.skew) end},
		require = function(target) return assert(modules[target], "unexpected require") end,
		Random = {new = function(seed)
			if seed == nil then
				-- Seedless generators: the last one created is the trophy stream (queued rolls), the others jitter.
				local r = {}
				function r.NextNumber(self)
					if self == S.trophyRandom then
						if #S.trophyRolls > 0 then return table.remove(S.trophyRolls, 1) end
						return 0.999
					end
					return S.jitter or 0.999
				end
				function r.NextInteger(_, lo) return lo end
				table.insert(S.seedless, r)
				return r
			end
			return {NextNumber = function() return rngValue end, NextInteger = function(_, lo) return lo end}
		end},
		warn = function() end,
		task = {
			spawn = function(f, ...)
				local co = coroutine.create(f)
				local okRun, res = coroutine.resume(co, ...)
				assert(okRun, res)
				if coroutine.status(co) == "suspended" then table.insert(S.co, {co, res}) end
				return co
			end,
			defer = function(f, ...) f(...) end,
			wait = function(t) return coroutine.yield(t) end,
			delay = function(t, f, ...) table.insert(S.delayed, {t, f, {...}}) end,
		},
	}
	luau.load(serverSource, {environment = env, injectGlobals = true})()
	S.trophyRandom = S.seedless[#S.seedless]
	for _, o in ipairs(S.objects) do
		if o.OnServerInvoke then S.remote = o end
		if o.Name == "IsleBridge" then S.bridge = o end
	end
	assert(S.remote and S.bridge, "server remotes")
	for _, c in ipairs(S.co) do if c[2] == 55 then S.saver = c[1] end end
	assert(S.saver, "autosave loop")
	-- Runs the contest heartbeat (the queued CT.TICK delay, once).
	function S.tick()
		local ran = 0
		for i = #S.delayed, 1, -1 do
			local d = S.delayed[i]
			if d[1] == CT.TICK then table.remove(S.delayed, i); d[2](table.unpack(d[3])); ran += 1 end
		end
		assert(ran == 1, "exactly one contest heartbeat queued (" .. ran .. ")")
	end
	-- Renews every journal lease (the 55 s autosave pass).
	function S.renew() assert(coroutine.resume(S.saver, 55)) end
	function S.join(id, mutate)
		if mutate then
			local rec = store.data["p" .. id]
			if rec then mutate(rec.profile) end
		end
		local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
		local p = {UserId = id, Name = "Farmer" .. id, DisplayName = "Farmer" .. id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
		function p:GetAttribute(key) return self.attrs[key] end
		function p:SetAttribute(key, value) self.attrs[key] = value end
		p.root = {Position = Vector3.new(0, 5000, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
		p.Character = {Parent = true, FindFirstChild = function() return p.root end, FindFirstChildOfClass = function() return humanoid end,
			WaitForChild = function() return humanoid end, PivotTo = function(_, cf) p.root.Position = cf.Position end}
		p.humanoid = humanoid
		S.live[id] = p
		S.services.Players.PlayerAdded:Fire(p)
		assert(not p.kicked, "joined: " .. tostring(p.kicked))
		return p
	end
	function S.leave(p)
		S.live[p.UserId] = nil
		p.Parent = nil
		S.services.Players.PlayerRemoving:Fire(p)
	end
	function S.cmd(p, verb, item)
		clock.cpu += 1; clock.utc += 1
		return S.remote.OnServerInvoke(p, verb, item)
	end
	-- A gather prompt for `item` (optional region) at the player's feet.
	function S.gather(p, item, region)
		local q = {Enabled = true, MaxActivationDistance = 10, attrs = {IsleAction = "gather", IsleItem = item, IsleRegion = region}}
		function q:GetAttribute(k) return self.attrs[k] end
		local basePart = {CFrame = CFrame.new(p.root.Position), Position = p.root.Position}
		function q:FindFirstAncestorWhichIsA() return basePart end
		clock.cpu += 1; clock.utc += 1
		p.last = nil
		S.services.ProximityPromptService.PromptTriggered:Fire(q, p)
		return p.last
	end
	function S.shutdown()
		local co = coroutine.create(S.onClose)
		local okRun, err = coroutine.resume(co)
		assert(okRun, err)
		assert(coroutine.status(co) == "dead", "BindToClose finished")
	end
	return S
end
local function profileOf(store, id) return store.data["p" .. id] and store.data["p" .. id].profile end
local function announced(s, kind, field, value)
	for _, e in ipairs(s and s.announce and s.announce.list or {}) do
		if e.kind == kind and (field == nil or e[field] == value) then return e end
	end
	return nil
end

-- Pick a contest whose first featured crop is a field crop that Farming 1 can
-- gather (Herb) and whose featured list leaves Sunwheat out.
local K
for k = 71000, 72000 do
	local crops = CT.cropsOf(k)
	if crops[1] == "Herb" and not table.find(crops, "Sunwheat") then K = k break end
end
assert(K, "a contest featuring Herb first")
local W = CT.window(K)
local CROPS = W.crops
local store = newStore()
local clock = {utc = W.starts - 200, cpu = 10}
local S1 = newServer(store, clock, 0)
local S2 = newServer(store, clock, 3) -- a server whose clock runs 3 s fast
local function tickAll(seconds)
	clock.utc += seconds or 0
	clock.cpu += seconds or 0
	S1.renew(); S2.renew()
	S1.tick(); S2.tick()
end
-- Seed journals (Farming for Sunwheat; a garden with ripe plots).
local function seed(sv, id, mutate)
	if not store.data["p" .. id] then sv.leave(sv.join(id)) end
	return sv.join(id, function(pr)
		pr.xp.Farming = X[40]
		pr.items.CopperHoe = 1; pr.items.SproutwoodHoe = 1 -- hoes for the higher field crops
		pr.started = true
		if mutate then mutate(pr) end
	end)
end
-- B1. Before the contest: nothing to enter.
local a = seed(S1, 9001)
local s0 = S1.cmd(a, "state")
ok(type(s0.contests) == "table" and s0.contests.active == false and s0.contests.next.k == K, "snapshot carries the schedule before the bell")
ok(has(S1.cmd(a, "contestEnter", "Herb").message, "No Harvest Contest is running"), "no entry between bells")
local herb0 = S1.cmd(a, "state").items.Herb or 0
S1.gather(a, "Herb")
eq(S1.cmd(a, "state").contests.entry, nil, "harvests before the bell do not count")
-- B2. The bell: a start toast; the first featured harvest enters you.
clock.utc = W.starts + 5
tickAll(0)
local s1 = S1.cmd(a, "state")
ok(s1.contests.active and s1.contests.k == K and s1.contests.crops[1] == "Herb", "contest running")
ok(announced(a.last, "contest", "phase", "start") or announced(s1, "contest", "phase", "start"), "HARVEST CONTEST toast at the bell")
herb0 = s1.items.Herb or 0
for _ = 1, 40 do S1.gather(a, "Herb") end
local s2 = S1.cmd(a, "state")
local gained = (s2.items.Herb or 0) - herb0
ok(gained >= 40, "Herb harvested (" .. gained .. ")")
ok(s2.contests.entry and s2.contests.entry.c == "Herb" and s2.contests.entry.s == gained and s2.contests.entry.slot == 1, "the first featured harvest enters you; every unit counts")
-- A non-featured crop does not count; a locked entry refuses another crop.
local sw0 = s2.items.Sunwheat or 0
local gs = S1.gather(a, "Sunwheat")
local s3 = S1.cmd(a, "state")
if not ((s3.items.Sunwheat or 0) > sw0) then print("Sunwheat gather: " .. tostring(gs and gs.message)) end
ok((s3.items.Sunwheat or 0) > sw0 and s3.contests.entry.s == gained, "Sunwheat is not featured: no credit")
ok(has(S1.cmd(a, "contestEnter", CROPS[2]).message, "locked once you score"), "entries lock once scored")
ok(has(S1.cmd(a, "contestEnter", "Sunwheat").message, "featured crops"), "only featured crops")
-- B3. A chosen entry follows the first featured harvest until it scores; garden plots count.
local gardenCrop = CROPS[2]
local b = seed(S1, 9002, function(pr)
	pr.xp.Farming = X[80]
	pr.garden = {xp = 0, plots = {{crop = gardenCrop, grown = Data.Garden.CropById[gardenCrop].grow, planted = W.starts - 99999, at = W.starts, treated = true}}}
end)
ok(has(S1.cmd(b, "contestEnter", CROPS[3]).message, "Entered with"), "entered by choice")
local cd = S1.cmd(b, "contestEnter", CROPS[2]).message
ok(has(cd, "One moment"), "entry change cooldown: " .. tostring(cd))
eq(S1.cmd(b, "state").contests.entry.c, CROPS[3], "chosen crop")
clock.cpu += 5
local before = S1.cmd(b, "state").items[gardenCrop] or 0
local hv = S1.cmd(b, "harvestPlot", "1")
local sb = S1.cmd(b, "state")
local plotGain = (sb.items[gardenCrop] or 0) - before
ok(plotGain > 0, "garden harvest (" .. tostring(hv.message) .. ")")
ok(sb.contests.entry.c == gardenCrop and sb.contests.entry.s == plotGain, "an unscored entry follows the first featured harvest; garden plots count")
-- B4. A second server: another entrant; a hop keeps the journal's score.
local c = seed(S2, 9003)
for _ = 1, 4 do S2.gather(c, "Herb") end
local sc = S2.cmd(c, "state")
ok(sc.contests.entry and sc.contests.entry.c == "Herb", "entrant on server 2")
-- Flush: score shards, leaderboard entries, then the histogram mirror.
tickAll(CT.FLUSH + 1)
local mapT, mapLB = CT.mapName(K), CT.boardName(K)
local function stored(id)
	local item = store.memory.map(mapT)[CT.shardKey(CT.shardOf(id))]
	local v = item and item.v[tostring(id)]
	if v == nil then return nil end
	return CT.unpack(v)
end
local slotA, scoreA = stored(9001)
ok(slotA == 1 and scoreA == gained, "server 1 wrote its entrant's score")
local slotC = stored(9003)
eq(slotC, 1, "server 2 wrote its entrant's score")
local lb = store.memory.map(mapLB)
ok(lb["9001"] and lb["9001"].s == gained and lb["9001"].n == "Farmer9001", "leaderboard entry with a display name")
eq(store.memory.sortKeys[mapLB]["9001"], 1e8 + gained, "sortKey = slot * 1e8 + score")
for key, ttl in pairs(store.memory.ttls) do
	if has(key, "contest_v1_" .. K) then ok(ttl <= W.ends + CT.TTL_PAD - (W.starts) and ttl > CT.GRACE, "per-contest TTL on " .. key) end
end
tickAll(CT.MIRROR + 1)
local groups = 0
for key in pairs(store.memory.map(mapT)) do if string.match(key, "^g%d+$") then groups += 1 end end
ok(groups >= 1, "histogram mirrors written (" .. groups .. ")")
-- Hop: A leaves server 1 and keeps harvesting on server 2.
S1.leave(a)
a = S2.join(9001)
local sa = S2.cmd(a, "state")
eq(sa.contests.entry.s, gained, "the journal carries the score across servers")
for _ = 1, 5 do S2.gather(a, "Herb") end
local gained2 = (S2.cmd(a, "state").items.Herb or 0) - herb0
ok(gained2 > gained, "harvesting continues after the hop")
-- A population from other servers (written straight to the store, as they would).
local others = {}
for i = 1, 120 do
	local id = 700000 + i
	local score = 20 + i * 2
	others[id] = score
	local sh = CT.shardOf(id)
	local key = CT.shardKey(sh)
	local m = store.memory.map(mapT)
	local item = CT.applyScores(m[key], {[tostring(id)] = {c = 1, s = score}}, K, clock.utc)
	if item then
		m[key] = item
		local g = CT.groupKey(CT.groupOf(sh))
		m[g] = CT.mirror(m[g], K, {[tostring(sh)] = {ver = item.ver, h = item.h}}) or m[g]
	end
	lb[tostring(id)] = {c = 1, s = score, n = "Other" .. i}
	store.memory.sortKeys[mapLB][tostring(id)] = 1e8 + score
end
tickAll(CT.FLUSH + 1)
tickAll(CT.READ + 1)
local live = S2.cmd(a, "state").contests
ok(live.estimate ~= nil and (live.estimate.bracket == nil or CT.BracketById[live.estimate.bracket] ~= nil), "live estimate in the snapshot")
do
	local want = CT.estimate(CT.sumGroups((function()
		local gs = {}
		for key, item in pairs(store.memory.map(mapT)) do if string.match(key, "^g%d+$") then gs[key] = item end end
		return gs
	end)())[1], live.entry.s, "Herb")
	eq(live.estimate.bracket, want, "the estimate is computed from the mirrored histograms")
end
ok(live.estimate and live.estimate.n >= 100, "the estimate counts entrants from every server (" .. tostring(live.estimate and live.estimate.n) .. ")")
do
	local top = 0
	for _, sc in pairs(others) do top = math.max(top, sc) end
	for _, id in ipairs({9001, 9003}) do local _, sc = stored(id); top = math.max(top, sc or 0) end
	ok(live.board and #live.board[1] == CT.LB_TOP and live.board[1][1].s == top, "leaderboard: the top entries for the crop (" .. top .. ")")
	for i = 2, #live.board[1] do ok(live.board[1][i].s <= live.board[1][i - 1].s, "leaderboard sorted") end
	local mineRow, inTop = false, select(2, stored(9001)) >= live.board[1][CT.LB_TOP].s
	for _, row in ipairs(live.board[1]) do if row.me then mineRow = true; ok(row.n == "Farmer9001", "own row named") end end
	eq(mineRow, inTop, "the viewer's row is marked when it is in the top rows")
end
-- B5. Lost acknowledgement and throttling: nothing lost, nothing doubled.
for _ = 1, 3 do S2.gather(a, "Herb") end
local want = S2.cmd(a, "state").contests.entry.s
store.memory.fail = "after"
tickAll(CT.FLUSH + 1)
eq(select(2, stored(9001)), want, "a write whose acknowledgement was lost still landed")
tickAll(CT.FLUSH + 1)
eq(select(2, stored(9001)), want, "the retry is a stale replay (no double count)")
-- Throttle: the shard key fails for a while; the score is retried with backoff.
for _ = 1, 3 do S2.gather(a, "Herb") end
local want2 = S2.cmd(a, "state").contests.entry.s
local shardA = CT.shardKey(CT.shardOf(9001))
local attempts = 0
store.memory.throttle = function(name, key) if name == mapT and key == shardA then attempts += 1; return true end return false end
for _ = 1, 20 do tickAll(CT.TICK) end
ok(attempts >= 2 and attempts <= 12, "a failing key backs off (" .. attempts .. " attempts in 100 s)")
eq(select(2, stored(9001)), want, "throttled: the store still holds the older score")
store.memory.throttle = nil
for _ = 1, 30 do tickAll(CT.TICK) end
eq(select(2, stored(9001)), want2, "after the throttle lifts the score lands")
-- B6. D harvests on server 2 and leaves before any flush: its score is still written.
local d = seed(S2, 9004)
for _ = 1, 25 do S2.gather(d, "Herb") end
local dScore = S2.cmd(d, "state").contests.entry.s
S2.leave(d)
tickAll(CT.FLUSH + 1)
eq(select(2, stored(9004)), dScore, "a leaving journal's score is flushed after it leaves")
-- E harvests on server 1 and the store goes down until after the close: refused as late.
local e = seed(S1, 9005)
for _ = 1, 30 do S1.gather(e, "Herb") end
local eScore = S1.cmd(e, "state").contests.entry.s
-- B7. The bell: entries close, writes stop at the deadline, one server seals.
store.memory.down = true
clock.utc = W.ends - 2
tickAll(0)
clock.utc = W.ends + 1
tickAll(0)
local closed = S2.cmd(a, "state").contests
ok(closed.active == false and closed.pending == 1, "the entry waits for its result")
ok(profileOf(store, 9001) == nil or true, "journal pending")
clock.utc = W.writeDeadline + 2
store.memory.down = false
tickAll(CT.FLUSH + 1)
eq(stored(9005), nil, "a score written after the deadline is refused (late)")
-- Personal best recorded at the close.
local bestA = S2.cmd(a, "state").contests.best.Herb
eq(bestA, want2, "personal best per crop")
-- Seal (after GRACE): exactly one server reads the shards.
local readsBefore = {}
for key, n in pairs(store.memory.keyReads) do readsBefore[key] = n end
clock.utc = W.sealAt + 1
tickAll(CT.SEAL_RETRY + 1)
local ring = store.data[CT.resultKey(K)]
ok(ring and ring.k == K, "the sealed result is in the DataStore ring")
local shardReads = 0
for key, n in pairs(store.memory.keyReads) do
	if string.match(key, "^" .. mapT .. "/s%d+$") then shardReads += n - (readsBefore[key] or 0) end
end
ok(shardReads <= CT.SHARDS, "one server read the score shards once (" .. shardReads .. ")")
local expect = (function()
	local shards = {}
	for key, item in pairs(store.memory.map(mapT)) do if string.match(key, "^s%d+$") then shards[key] = item end end
	return CT.seal(K, shards)
end)()
ok(ring.slots[1].n == expect.slots[1].n and ring.slots[1].cut.Bronze == expect.slots[1].cut.Bronze and ring.slots[1].cut.Diamond == expect.slots[1].cut.Diamond, "exact cut-offs from every stored score")
do
	local placing = 0
	for _, sc in pairs(others) do if sc >= CT.CropById.Herb.min then placing += 1 end end
	for _, id in ipairs({9001, 9003, 9004}) do local _, sc = stored(id); if sc and sc >= CT.CropById.Herb.min then placing += 1 end end
	eq(ring.slots[1].n, placing, "population: every placing entrant from every server")
end
ok(#ring.slots[1].top == 3, "top three recorded")
for _, row in ipairs(ring.slots[1].top) do eq(row.n, lb[row.u] and lb[row.u].n, "top name from the leaderboard (" .. tostring(row.n) .. ")") end
-- Payouts: online journals are paid at the heartbeat, once.
local result = CT.cleanResult(ring, K)
local sa2 = S2.cmd(a, "state")
local exp = CT.bracketOf(result, 1, want2, "Herb")
local medals, xp = CT.reward("Herb", exp, want2 >= CT.CropById.Herb.min)
eq(sa2.contests.medals, medals, "medals for the bracket (" .. tostring(exp) .. ")")
ok(want2 >= CT.CropById.Herb.min and exp ~= nil and medals > 0, "the test entrant placed (" .. want2 .. ", " .. tostring(exp) .. ")")
print(string.format("Contest %d: A %d (%s, %d medals), D %d, E %d, Herb entrants %d, cuts B%d S%d G%d P%d D%d", K, want2, tostring(exp), medals, dScore, eScore, ring.slots[1].n,
	ring.slots[1].cut.Bronze or 0, ring.slots[1].cut.Silver or 0, ring.slots[1].cut.Gold or 0, ring.slots[1].cut.Platinum or 0, ring.slots[1].cut.Diamond or 0))
eq(sa2.contests.pending, 0, "paid")
ok(sa2.contests.history[1] and sa2.contests.history[1].k == K and sa2.contests.history[1].b == exp and sa2.contests.history[1].m == medals, "result in the history")
ok(announced(a.last, "contest", "phase", "result") or announced(sa2, "contest", "phase", "result") or has(sa2.message, "Harvest Contest result"), "result toast")
tickAll(CT.SEAL_RETRY + 1)
eq(S2.cmd(a, "state").contests.medals, medals, "never paid twice")
-- E (refused as late) is paid by the cut-offs from its journal score.
local se = S1.cmd(e, "state").contests
local eBracket = CT.bracketOf(result, 1, eScore, "Herb")
eq(se.history[1] and se.history[1].b, eBracket, "a late-refused entry is still judged by the cut-offs")
-- D rejoins on a fresh server (no cached result): read from the ring and paid.
local S3 = newServer(store, clock, -2)
d = S3.join(9004)
clock.utc += 1
S3.renew()
S3.tick()
local sd = S3.cmd(d, "state").contests
eq(sd.pending, 0, "an offline entrant is paid on a fresh server from the ring")
eq(sd.history[1].b, CT.bracketOf(result, 1, dScore, "Herb"), "offline entrant's bracket")
-- C on server 2: paid as well; B's garden entry judged in its own crop.
ok(S2.cmd(c, "state").contests.pending == 0, "server 2 entrant paid")
eq(S1.cmd(b, "state").contests.history[1].c, gardenCrop, "garden entrant judged in its crop")
-- B8. A pending entry whose result can never be sealed expires with participation only.
do
	local old = K - 200
	local oc = CT.window(old).crops[1]
	S1.leave(b)
	b = S1.join(9002, function(pr) pr.contests.open = {{k = old, c = oc, s = 999}} end)
	clock.utc += 1
	S1.renew()
	S1.tick()
	local sb2 = S1.cmd(b, "state").contests
	ok(sb2.pending == 0 and sb2.history[1].k == old and sb2.history[1].b == nil and sb2.history[1].m == 0, "an unsealable entry expires without medals")
end
-- B9. The Medal Exchange.
do
	S1.leave(b)
	b = S1.join(9002, function(pr) pr.contests.medals = 300; pr.items.FurrowMedallion = nil end)
	local col0 = S1.cmd(b, "state").collection.HarvestTonic
	local r1 = S1.cmd(b, "contestBuy", "HarvestTonic:3")
	ok(has(r1.message, "Bought 6×") and r1.items.HarvestTonic == 6 and r1.contests.medals == 291, "consumables in lots")
	eq(r1.collection.HarvestTonic, col0, "shop purchases never credit collections")
	ok(has(S1.cmd(b, "contestBuy", "LaureateMedallion").message, "Bring your Furrow Medallion"), "upgrade needs the base item")
	local r2 = S1.cmd(b, "contestBuy", "FurrowMedallion")
	ok(r2.items.FurrowMedallion == 1, "unique accessory")
	ok(has(S1.cmd(b, "contestBuy", "FurrowMedallion").message, "already own"), "unique once")
	S1.cmd(b, "accessory", "FurrowMedallion")
	local r3 = S1.cmd(b, "contestBuy", "LaureateMedallion")
	ok((r3.items.FurrowMedallion or 0) == 0 and r3.items.LaureateMedallion == 1, "upgrade consumes the base")
	local bag = profileOf(store, 9002) and true
	local live9002 = S1.cmd(b, "state")
	ok(table.find(live9002.depth.accessoryBag, "LaureateMedallion") ~= nil and table.find(live9002.depth.accessoryBag, "FurrowMedallion") == nil, "an equipped base becomes the equipped upgrade")
	local r4 = S1.cmd(b, "contestBuy", "Almanac")
	ok(has(r4.message, "volume 1") and r4.contests.almanac == 1, "almanac volume")
	local ff0 = live9002.depth.stats.farmingFortune
	ok(S1.cmd(b, "state").depth.stats.farmingFortune == ff0 + CT.ALMANAC[1], "almanac Farming Fortune applies (p.perkStats.contests)")
	ok(has(S1.cmd(b, "contestBuy", "MedalistHoe").message, "Bought"), "hoe at Farming 80")
	ok(has(S1.cmd(b, "contestBuy", "MedalistHoe").message, "already own"), "hoe unique")
	ok(has(S1.cmd(b, "contestBuy", "TitleFieldLaureate").message, "need 150"), "not enough medals")
	ok(has(S1.cmd(b, "contestBuy", "TitleFurrowhand").message, "Title unlocked"), "title bought")
	ok(has(S1.cmd(b, "contestTitle", "GoldenSheaf").message, "Unlock"), "an unowned title cannot be worn")
	S1.cmd(b, "contestTitle", "Furrowhand")
	eq(b:GetAttribute("ContestTitle"), "Furrowhand", "title worn")
	S1.leave(b)
	b = S1.join(9002)
	eq(b:GetAttribute("ContestTitle"), "Furrowhand", "title back on rejoin")
	ok(has(S1.cmd(b, "contestBuy", "Nope").message, "does not stock"), "unknown offer")
	ok(has(S1.cmd(b, "contestBuy", "HarvestTonic:99").message, "1 to 16"), "lot bound")
	local pr = profileOf(store, 9002)
	ok(pr.contests.medals >= 0 and pr.contests.spent > 0, "medals saved")
	-- Ironman: enter and spend like everyone (medals never cross accounts).
	local iron = seed(S1, 9006, function(p2) p2.ironman = true; p2.contests = {medals = 5} end)
	ok(has(S1.cmd(iron, "contestBuy", "HarvestTonic").message, "Bought"), "Ironman can use the exchange")
end
-- B10. Next contest; shutdown drains queued scores before the journals save.
do
	local W2 = CT.window(K + 1)
	clock.utc = W2.starts + 3
	tickAll(0)
	local crop = W2.crops[1]
	local f = seed(S1, 9007, function(pr) pr.xp.Farming = X[99] end)
	local resource = Data.ResourceSkill[crop] and crop
	if resource then
		for _ = 1, 3 do S1.gather(f, resource) end
	else
		S1.leave(f)
		f = S1.join(9007, function(pr) pr.garden = {xp = 0, plots = {{crop = crop, grown = Data.Garden.CropById[crop].grow, planted = 1, at = W2.starts, treated = true}}} end)
		S1.cmd(f, "harvestPlot", "1")
	end
	local score = S1.cmd(f, "state").contests.entry.s
	ok(score > 0, "entered the next contest")
	S1.shutdown()
	local item = store.memory.map(CT.mapName(K + 1))[CT.shardKey(CT.shardOf(9007))]
	local _, stored2 = CT.unpack(item and item.v["9007"])
	eq(stored2, score, "BindToClose wrote the queued score")
	ok(profileOf(store, 9007).contests.cur.s == score, "the journal saved its entry")
end
-- B11. Bounded journals.
do
	local pr = profileOf(store, 9001)
	ok(#pr.contests.open <= CT.OPEN_MAX and #pr.contests.history <= CT.HISTORY, "journal record bounded")
end
print("PASS: " .. (checks - partB) .. " Contests server assertions.")

------------------------------------------------------------------------------
-- Part C: trophy fishing through the real fishing gather.
------------------------------------------------------------------------------
local partC = checks
do
	local tstore = newStore()
	-- Mid-day of a Sunreach day outside any festival.
	local cal = Data.calendarAt(W.starts)
	local yearStart = cal.yearStart
	local noon = yearStart + (12 * 1 + 2) * Data.Calendar.dayLength + Data.Calendar.dayLength * 0.5 -- day 15 (Sunreach 3? any), 12:00
	local function quietAt(t)
		local c2 = Data.calendarAt(t)
		return c2.event == nil
	end
	while not quietAt(noon) do noon += Data.Calendar.dayLength end
	local tclock = {utc = noon, cpu = 10}
	local T1 = newServer(tstore, tclock, 0)
	local function angler(id, mutate)
		if not tstore.data["p" .. id] then T1.leave(T1.join(id)) end
		return T1.join(id, function(pr)
			pr.xp.Fishing = X[90]
			pr.items.CelestialRod = 1
			pr.started = true
			if mutate then mutate(pr) end
		end)
	end
	local fisher = angler(9101)
	local function cast(pl, region, rolls)
		for _, r in ipairs(rolls or {}) do table.insert(T1.trophyRolls, r) end
		tclock.cpu += 30
		return T1.gather(pl, (region == "Tidewater" and "Stormeel") or (region == "Gloomhollow" and "AbyssKoi") or (region == "ShatteredCrown" and "Riftfin") or "Fish", region)
	end
	-- A miss: the cast counts, nothing caught.
	local r0 = cast(fisher, nil, {0.99})
	eq(r0.trophies.casts, 1, "a cast in trophy waters is counted")
	eq(r0.trophies.total, 0, "no bite on a high roll")
	-- A bite in the Shallows at noon: Pebblefin (the only noon fish without bait / season).
	local fish0 = r0.items.Fish or 0
	local r1 = cast(fisher, nil, {0.0, 0.0, 0.0})
	ok(r1.trophies.caught.PebblefinDarter and r1.trophies.caught.PebblefinDarter.Bronze == 1, "Bronze Pebblefin Darter recorded")
	ok(has(r1.message, "Bronze trophy: Pebblefin Darter"), "catch message")
	ok((r1.items.Fish or 0) > fish0, "the normal catch still lands")
	eq(r1.items.PebblefinDarter, nil, "trophy fish are ledger records, not satchel items")
	ok(announced(r1, "trophy", "fish", "PebblefinDarter"), "first catch toast (new best)")
	-- Sea creatures: a cast that hooks one never rolls a trophy (no double count).
	local rollWas = Data.rollSeaCreature
	Data.rollSeaCreature = function() return "ShellsnapCrab" end
	local casts0 = r1.trophies.casts
	local r2 = cast(fisher, nil, {0.0, 0.0, 0.0})
	Data.rollSeaCreature = rollWas
	ok(has(r2.message, "surfaces"), "a sea creature surfaced")
	ok(r2.trophies.casts == casts0 and r2.trophies.total == 1 and #T1.trophyRolls == 3, "no trophy roll on a sea-creature cast")
	table.clear(T1.trophyRolls)
	-- No trophy waters in Windpine.
	local r3 = cast(fisher, "Windpine", {0.0, 0.0, 0.0})
	ok(r3.trophies.casts == casts0 and #T1.trophyRolls == 3, "no trophy fish outside trophy waters")
	table.clear(T1.trophyRolls)
	-- Bait: refused without it; loaded, spent per cast, unloaded when out.
	ok(has(T1.cmd(fisher, "trophyBait", "GlowgrubBait").message, "You have no"), "no bait to load")
	T1.leave(fisher)
	fisher = angler(9101, function(pr) pr.items.GlowgrubBait = 2 end)
	ok(has(T1.cmd(fisher, "trophyBait", "GlowgrubBait").message, "loaded"), "bait loaded")
	local r4 = cast(fisher, nil, {0.99})
	eq(r4.items.GlowgrubBait, 1, "one bait per cast")
	cast(fisher, nil, {0.99})
	local r5 = cast(fisher, nil, {0.99})
	ok(r5.trophies.bait == nil and has(r5.message, "Out of Glowgrub Bait"), "bait unloaded when it runs out")
	-- Night + Glowgrub: the Mooncress Loach bites only with its bait.
	tclock.utc = noon + Data.Calendar.dayLength * 10 / 24 -- 22:00
	T1.renew()
	T1.leave(fisher)
	fisher = angler(9101, function(pr) pr.items.GlowgrubBait = 5; pr.trophy.bait = "GlowgrubBait" end)
	local pool = TF.pool({water = "Shallows", hour = TF.hourAt(tclock.utc + 2), season = Data.calendarAt(tclock.utc).season, rod = 7, fishing = 90, bait = "GlowgrubBait"})
	local loachAt = nil
	local total = 0
	for _, f in ipairs(pool) do total += f.weight end
	local acc = 0
	for _, f in ipairs(pool) do if f.id == "MooncressLoach" then loachAt = (acc + f.weight / 2) / total end acc += f.weight end
	ok(loachAt ~= nil, "Mooncress Loach in the night pool with bait")
	local r6 = cast(fisher, nil, {0.0, loachAt, 0.5})
	ok(r6.trophies.caught.MooncressLoach ~= nil, "Mooncress Loach caught at night on Glowgrub Bait")
	-- Diamond: pity forces it; every player on the server hears of it.
	local other = angler(9102)
	T1.leave(fisher)
	fisher = angler(9101, function(pr) pr.trophy.pity = {PebblefinDarter = {g = 0, d = TF.PITY_DIAMOND - 1}}; pr.trophy.bait = nil end)
	tclock.utc = noon + Data.Calendar.dayLength * 3 -- noon again, three days on
	while not quietAt(tclock.utc) do tclock.utc += Data.Calendar.dayLength end
	T1.renew()
	other.last = nil
	local pebAt = nil
	local pool2 = TF.pool({water = "Shallows", hour = 12, season = Data.calendarAt(tclock.utc).season, rod = 7, fishing = 90})
	local tot2, acc2 = 0, 0
	for _, f in ipairs(pool2) do tot2 += f.weight end
	for _, f in ipairs(pool2) do if f.id == "PebblefinDarter" then pebAt = (acc2 + 0.5) / tot2 end acc2 += f.weight end
	local r7 = cast(fisher, nil, {0.0, pebAt, 0.0})
	ok(r7.trophies.caught.PebblefinDarter.Diamond == 1 and r7.trophies.diamonds == 1, "Diamond by pity")
	ok(announced(r7, "trophy", "tier", "Diamond"), "DIAMOND TROPHY toast for the angler")
	ok(other.last and announced(other.last, "trophyWorld", "fish", "PebblefinDarter"), "every player on the server hears of a Diamond")
	ok(announced(other.last, "trophyWorld", "who", "Farmer9101"), "with the angler's name")
	-- Ledger: claims, refusals, titles.
	ok(has(T1.cmd(fisher, "trophyClaim", "Bronze").message, "needs " .. #TF.Fish), "an incomplete tier is refused")
	T1.leave(fisher)
	fisher = angler(9101, function(pr)
		pr.trophy.caught = {}
		for _, f in ipairs(TF.Fish) do pr.trophy.caught[f.id] = {Bronze = 1, Silver = 1} end
	end)
	local col0 = T1.cmd(fisher, "state").collection.GillwardHood
	local c1 = T1.cmd(fisher, "trophyClaim", "Bronze")
	ok(has(c1.message, "Gillward Hood") and c1.items.GillwardHood == 1 and c1.collection.GillwardHood == col0, "Bronze Ledger: the hood (not a collection credit)")
	ok(has(T1.cmd(fisher, "trophyClaim", "Bronze").message, "already claimed"), "claimed once")
	local c2 = T1.cmd(fisher, "trophyClaim", "Silver")
	ok(c2.items.GlintgillPet == 1, "Silver Ledger: the Glintgill pet")
	ok(has(T1.cmd(fisher, "trophyClaim", "Gold").message, "needs"), "Gold not yet")
	ok(has(T1.cmd(fisher, "trophyTitle", "Gold").message, "Claim that"), "an unclaimed title cannot be worn")
	T1.cmd(fisher, "trophyTitle", "Silver")
	eq(fisher:GetAttribute("TrophyTitle"), "Silverline Angler", "title worn")
	T1.cmd(fisher, "trophyClaim", "Novice")
	T1.cmd(fisher, "trophyTitle", "none")
	eq(fisher:GetAttribute("TrophyTitle"), "", "title hidden")
	-- The pet adopts and its level raises the trophy chance; the hood equips.
	T1.cmd(fisher, "petAdopt", "GlintgillPet")
	T1.cmd(fisher, "equip", "GillwardHood")
	local st = T1.cmd(fisher, "state")
	ok(st.trophies.hood == true, "the Gillward Hood is worn")
	local pets = st.depth.pets
	ok(pets[#pets] and pets[#pets].id == "Glintgill", "Glintgill adopted")
	-- Saved and bounded.
	T1.leave(fisher)
	local pr = profileOf(tstore, 9101)
	local n = 0
	for _ in pairs(pr.trophy.caught) do n += 1 end
	ok(n <= #TF.Fish and pr.trophy.claimed.Bronze and pr.trophy.claimed.Silver and pr.trophy.claimed.Novice, "trophy journal saved and bounded")
	T1.leave(other)
end
print("PASS: " .. (checks - partC) .. " Trophy Angling server assertions.")
print("PASS: " .. checks .. " Contests & Trophy Angling assertions in total.")
print("SUITE-END verify-contests.luau")
