-- Systems Depth (docs/DEPTH-CONTRACT.md §33): quest helper, goal board, market
-- price history, per-player daily shop stock and the XP calculator.
-- Part A: pure data (GameData "Systems Depth" section).
-- Part B: server.server.lua with service doubles — helperPin (sidebar attribute,
--   NEW OBJECTIVE on step change, auto-unpin), goals (validation, cap, completion
--   toast, rolling-window ETA, rejoin / tamper safety), daily stock on regional
--   shops / skill vendors / the Roost (UTC roll-forward only), price history
--   (Bazaar fills inside the economy transform; auction sales in their own
--   hist:auction:<cat> key via a queued best-effort flush, deduped by sale id;
--   lost-ack replays counted once; legacy in-key history moved out) and priceCheck.
-- Part C: clients — atlas pages (Journal › Helper / Goals, Hero › Calculator,
--   Ledger › Prices), quest-card guide/pin, the sidebar Objective, stock text,
--   IslePriceCheckLocal, dialogue stock labels.
-- QC regression tests are marked "QC <id>": M1 wash trading (medians, outliers,
-- pair caps, thin market), M2 per-item stock across shops, M3 priceCheck
-- cooldown / own budget / tooltip debounce, L1-L8 and the regional collect text.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local SY = Data.Systems
local HP, GL, PR, ST, CA = SY.Helper, SY.Goals, SY.Prices, SY.Stock, SY.Calc
local RA = Data.RegionArt
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

------------------------------------------------------------------------------
-- Part A: data.
------------------------------------------------------------------------------
-- A1. Every quest, regional quest, diary tier and contract yields a guide; every
-- step has text, and every waypoint spec is a valid Wayfinder target.
local T = Data.Townsfolk
local function validSpecs(specs, where)
	if specs == nil then return end
	ok(type(specs) == "table" and #specs >= 1, where .. ": specs list")
	for _, spec in ipairs(specs) do ok(T.parseTarget(spec) ~= nil, where .. ": spec " .. tostring(spec) .. " parses") end
end
local withSpecs, totalSteps = 0, 0
for _, q in ipairs(Data.Quests) do
	local g = HP.questGuide(q, {requires = {}, objectives = {}}, {})
	ok(#g.steps >= #q.objectives + 1, q.id .. " guide covers requirements, tasks and the hand-in")
	ok(g.current >= 1 and g.current <= #g.steps, q.id .. " has a current step")
	for i, s in ipairs(g.steps) do
		totalSteps += 1
		ok(type(s.text) == "string" and #s.text > 3 and s.text ~= "Unknown task" and s.text ~= "Task", q.id .. " step " .. i .. " text: " .. tostring(s.text))
		validSpecs(s.specs, q.id .. " step " .. i)
		if s.specs then withSpecs += 1 end
	end
	if q.giver then
		local accept
		for _, s in ipairs(g.steps) do if s.phase == "accept" then accept = s end end
		ok(accept and accept.npc == q.giver and accept.specs[1] == "npc:" .. q.giver, q.id .. " regional guide names its giver")
		eq(g.steps[#g.steps].npc, q.giver, q.id .. " hand-in at the giver")
	end
	for _, o in ipairs(q.objectives) do
		if o.kind == "talk" then
			local found = false
			for _, s in ipairs(g.steps) do if s.npc == o.npc and s.phase == "task" then found = true end end
			ok(found, q.id .. " talk step names the NPC")
		end
	end
end
for _, d in ipairs(Data.Diaries) do
	for _, tierName in ipairs(Data.DiaryTiers) do
		local g = HP.diaryGuide(d, tierName, {tasks = {}})
		eq(#g.steps, #d.tiers[tierName].tasks + 1, d.region .. " " .. tierName .. " steps")
		for i, s in ipairs(g.steps) do validSpecs(s.specs, d.region .. tierName .. i); totalSteps += 1; if s.specs then withSpecs += 1 end end
	end
end
for stage = 1, #HP.ContractSpecs do
	local g = HP.contractGuide({title = "C" .. stage, detail = "Do it", stage = stage, total = 8})
	validSpecs(g.steps[1].specs, "contract " .. stage)
	ok(g.steps[1].specs ~= nil, "contract " .. stage .. " has a waypoint")
end
ok(withSpecs / totalSteps > 0.6, string.format("most guide steps carry a waypoint (%d / %d)", withSpecs, totalSteps))
print(string.format("Quest helper: %d steps across %d quests, %d diaries; %d with a waypoint", totalSteps, #Data.Quests, #Data.Diaries, withSpecs))
-- A2. Progress drives the current step.
local q = Data.QuestById.SunwheelTurns
local g0 = HP.questGuide(q, {requires = {{0, 2}}, objectives = {{0, 1}, {0, 30}, {0, 1}}}, {})
eq(g0.status, "locked", "requirements unmet: locked")
eq(g0.current, 1, "locked guide points at the requirement")
local g1 = HP.questGuide(q, {requires = {{2, 2}}, objectives = {{0, 1}, {0, 30}, {0, 1}}}, {})
eq(g1.status, "accept", "requirements met: accept from the giver")
ok(has(g1.steps[g1.current].text, RA.FolkByRole.Millwarden.name), "accept step names Hesper")
local g2 = HP.questGuide(q, {requires = {{2, 2}}, objectives = {{1, 1}, {12, 30}, {0, 1}}}, {accepted = true})
eq(g2.status, "active", "accepted: active")
eq(g2.steps[g2.current].have, 12, "current step has / need")
ok(has(HP.objective(g2), "12/30"), "objective text carries the count: " .. HP.objective(g2))
eq(g2.steps[g2.current].specs[1], "gather:Sunwheat", "collect step guides to the node")
local g3 = HP.questGuide(q, {requires = {{2, 2}}, objectives = {{1, 1}, {30, 30}, {1, 1}}, ready = true}, {accepted = true})
eq(g3.status, "ready", "all tasks done: ready")
eq(g3.steps[g3.current].npc, "Millwarden", "ready: return to the giver")
eq(HP.questGuide(q, {done = true}, {}).status, "done", "done quest")
-- Malformed progress never throws.
ok(HP.questGuide(q, "x", nil).current >= 1, "junk entry is safe")
ok(HP.diaryGuide(Data.DiaryByRegion.Meadow, "Easy", "x").current >= 1, "junk diary tier is safe")
ok(HP.contractGuide(nil).current >= 1, "junk contract state is safe")
-- Pins.
ok(HP.validPin("quest:SunwheelTurns") and HP.validPin("diary:Meadow") and HP.validPin("contract"), "valid pins")
for _, bad in ipairs({"quest:Nope", "diary:Nowhere", "quest:", "quest:Sun:wheel", "", 5, string.rep("a", 80), "goal:1"}) do
	ok(not HP.validPin(bad), "bad pin refused: " .. tostring(bad))
end
eq(HP.diaryTier(0), "Easy", "first tier"); eq(HP.diaryTier(2), "Hard", "third tier"); eq(HP.diaryTier(9), "Elite", "clamped")
-- Item sources: gathering, a station, or a creature drop.
eq(HP.itemSource("Ore")[1], "gather:Ore", "resource source")
ok(HP.itemSource("BeastHide") and string.match(HP.itemSource("BeastHide")[1], "^monster:"), "drop source")
local anyStation = false
for id, d in pairs(Data.Recipes) do if d.station and HP.itemSource(d.output) and string.match(HP.itemSource(d.output)[1], "^station:") then anyStation = true end end
ok(anyStation, "crafted items guide to a station")

-- QC L4: waypoints prefer the lowest-level source the player can reach and
-- skip locked regions; with nowhere reachable the step carries its requirement.
eq(HP.itemSource("ArcaneDust")[1], "monster:BramblebackBoar", "lowest-level source first")
eq(HP.itemSource("ArcaneDust", {access = {Meadow = false}})[1], "monster:ShaleCrawler", "a locked region's source is skipped")
local noSpecs, why = HP.itemSource("Voidstone", {access = {Gloomhollow = false}})
ok(noSpecs == nil and has(why, "Unlocks with") and has(why, "Gloomhollow"), "no reachable source: the requirement instead: " .. tostring(why))
eq(HP.specsFor({kind = "level", skill = "Mining", level = 60}, {level = 50})[1], "gather:Voidstone", "level step: best usable node")
eq(HP.specsFor({kind = "level", skill = "Mining", level = 60}, {level = 50, access = {Gloomhollow = false}})[1], "gather:SunsteelOre", "level step: locked region's node skipped")
local spider = Data.QuestById.SilkAndShadow
local locked = HP.questGuide(spider, {requires = {}, objectives = {}}, {accepted = true, access = {Gloomhollow = false}})
local blockedStep
for _, st in ipairs(locked.steps) do if st.phase == "task" and st.blocked then blockedStep = st end end
ok(blockedStep and blockedStep.specs == nil and has(blockedStep.blocked, "Unlocks with"), "a kill step in a locked region shows its requirement, not a waypoint")
local open = HP.questGuide(spider, {requires = {}, objectives = {}}, {accepted = true, access = {Gloomhollow = true}})
local anyBlocked = false
for _, st in ipairs(open.steps) do if st.blocked then anyBlocked = true end end
ok(not anyBlocked, "an open region has waypoints again")
-- Quirk: regional "collect" steps count since acceptance, not lifetime.
local crane = HP.questGuide(Data.QuestById.CraneRepairs, {requires = {}, objectives = {}}, {accepted = true})
local collectText
for i, o in ipairs(Data.QuestById.CraneRepairs.objectives) do
	if o.kind == "collect" then collectText = crane.steps[#Data.QuestById.CraneRepairs.requires + 1 + i].text end
end
ok(has(collectText, "since accepting") and not has(collectText, "lifetime"), "regional collect step says since accepting: " .. tostring(collectText))
ok(has(Data.describeCheck({kind = "collect", item = "Ore", count = 5}), "(lifetime)"), "Journal quests keep lifetime totals")

-- A3. Goals.
local goodSpecs = {"level:Mining:50", "xp:Fishing:100000", "tier:Ore:3", "item:Ore:500", "quest:SurveyorsOath:1", "kills:BramblebackBoar:100"}
for _, spec in ipairs(goodSpecs) do ok(GL.parse(spec) ~= nil, "goal parses: " .. spec) end
local LR = Data.Lairs
ok(GL.parse("kills:" .. LR.Order[1] .. ":5") ~= nil, "lair boss kill goal")
for _, bad in ipairs({"level:Mining:1", "level:Mining:100", "level:Nope:5", "tier:Ore:99", "tier:Nope:1", "item:Nope:5", "item:Ore:0", "item:Ore:007",
	"quest:Nope:1", "quest:SurveyorsOath:2", "kills:Nope:5", "xp:Mining:200000001", "item:Ore:-1", "nope:Ore:1", "item:Ore", "", "level:Mining:5:5", 7}) do
	eq(GL.parse(bad), nil, "goal refused: " .. tostring(bad))
end
local X = Data.XP_TABLE
local pp = {xp = {Mining = X[20]}, items = {Ore = 40}, collection = {Ore = 120}, questsDone = {SurveyorsOath = true}, bestiary = {BramblebackBoar = 7},
	lairs = {kc = {[LR.Order[1]] = 3}}}
local have, need = GL.measure(pp, GL.parse("level:Mining:50"), P)
ok(have == X[20] and need == X[50], "level goal measures XP")
have, need = GL.measure(pp, GL.parse("tier:Ore:3"), P)
ok(have == 120 and need == P.collectionThreshold("Ore", 3), "tier goal")
eq(select(1, GL.measure(pp, GL.parse("item:Ore:500"), P)), 40, "item goal")
eq(select(1, GL.measure(pp, GL.parse("quest:SurveyorsOath:1"), P)), 1, "quest goal")
eq(select(1, GL.measure(pp, GL.parse("kills:BramblebackBoar:100"), P)), 7, "bestiary kill goal")
eq(select(1, GL.measure(pp, GL.parse("kills:" .. LR.Order[1] .. ":5"), P)), 3, "lair kill goal reads p.lairs.kc")
eq(select(1, GL.measure({}, GL.parse("item:Ore:5"), P)), 0, "empty journal measures 0")
-- Same measure without Progression (client).
eq(select(2, GL.measure(pp, GL.parse("tier:Ore:3"), nil)), P.collectionThreshold("Ore", 3), "client tier threshold matches")
ok(has(GL.label(GL.parse("level:Mining:50")), "Mining level 50"), "label")
-- Rolling rate and ETA.
local samples = {{1000, 0}, {1060, 100}, {1120, 200}, {1180, 300}}
eq(GL.rate(samples, 1180), 300 / 180 * 3600, "rate per hour over the window")
eq(GL.rate({{1000, 0}, {1030, 50}}, 1030), 0, "under a minute of samples: no rate")
eq(GL.rate({{0, 0}, {5000, 100}, {5060, 200}}, 5060), 100 / 60 * 3600, "samples older than the window are ignored")
eq(GL.eta(1000, 0), nil, "no rate: no ETA")
eq(GL.eta(3600, 3600), 3600, "ETA seconds")
eq(GL.etaText(3725), "1h 2m", "ETA text")
eq(GL.etaText(nil), "no recent progress", "ETA without a rate")
eq(GL.etaText(90000), "1d 1h", "ETA days")

-- A4. Price history buckets.
local list = {}
local h0 = 400000
PR.record(list, h0, 20, 5)
PR.record(list, h0, 30, 5)
eq(#list, 1, "same hour shares a bucket")
ok(list[1].n == 10 and list[1].v == 250 and list[1].lo == 20 and list[1].hi == 30, "bucket sums, low and high")
PR.record(list, h0 + 1, 40, 1)
eq(#list, 2, "new hour, new bucket")
PR.record(list, h0, 0, 5); PR.record(list, h0, 5, 0); PR.record(list, h0, -3, 2)
eq(#list, 2, "zero / negative fills ignored")
local s = PR.summary(list, (h0 + 1) * 3600 + 100, "Ore")
-- QC M1: averages weight each hour's median (20, from 5 @ 20 + 5 @ 30) by its units.
ok(s.vol24 == 11 and s.avg24 == math.floor((20 * 10 + 40) / 11 + 0.5) and s.last == 40 and s.lo7 == 20 and s.hi7 == 40, "summary: 24h volume / average / last / range")
eq(#s.spark, PR.SPARK, "sparkline length")
ok(s.spark[PR.SPARK] > 0, "newest sparkline slot filled")
local late = PR.summary(list, (h0 + 30) * 3600, "Ore")
ok(late.vol24 == 0 and late.avg24 == nil and late.avg7 ~= nil, "a day later: 24h empty, 7d kept")
eq(PR.summary(list, (h0 + PR.HOURS + 2) * 3600, "Ore").avg7, nil, "after 7 days nothing remains in the summary")
PR.record(list, h0 + PR.HOURS + 2, 10, 1)
eq(#list, 1, "recording prunes buckets older than 7 days")
local big = {}
for h = 1, 1000 do PR.record(big, h, 10, 1) end
eq(#big, PR.HOURS, "bazaar history bounded to 168 buckets")
ok(has(PR.text(PR.summary(big, 1000 * 3600, "Ore")), "24h avg 10"), "price check text")
eq(PR.text({}), "No trades in the last 7 days", "empty price text")
ok(PR.summary("junk", 0).vol7 == 0 and PR.summary({{h = "x"}, 5}, 0).vol7 == 0, "malformed history is safe")
-- Auction keys: bounded per category.
local hist = {}
local ids = {}
for id in pairs(Data.Items) do if Data.Economy.auctionCategory(id) == "weapon" then table.insert(ids, id) end end
table.sort(ids)
for h = 1, 300 do PR.recordAuction(hist, ids[(h % #ids) + 1], 1000 + h, 100 + h) end
local items, total = 0, 0
for _, l in pairs(hist) do items += 1; total += #l end
ok(items <= PR.AUCTION_ITEMS and total <= PR.AUCTION_BUCKETS, "auction history bounded (" .. items .. " items, " .. total .. " buckets)")
local flood = {}
for h = 1, 160 do for k = 1, math.min(#ids, 40) do PR.recordAuction(flood, ids[k], 5000 + h, 500) end end
total = 0
for _, l in pairs(flood) do total += #l end
eq(total, PR.AUCTION_BUCKETS, "auction flood keeps exactly the bucket cap")
-- Worst-case added key size (QC M1 fields: medians, trader counts, excluded
-- units; the open hour also carries its ladder, trader ids and pair rows).
local function closedBucket(h, big)
	return {h = h, n = big, v = big * 1000000, lo = 1000000, hi = 999999, m = 1000000, c = 999999, t = 8, x = big}
end
local function openBucket(h, caps, big)
	local b = closedBucket(h, big)
	b.m, b.c, b.t = nil, nil, nil
	b.q, b.u, b.pr = {}, {}, {}
	for k = 1, caps.levels do table.insert(b.q, {1000000 - k, big, big}) end
	for k = 1, caps.ids do table.insert(b.u, tostring(9000000000 + k)) end
	for k = 1, caps.pairs do b.pr[tostring(9000000000 + k) .. "|" .. tostring(9100000000 + k)] = caps.pair end
	b.pr["*"] = caps.pair
	return b
end
local worstBazaar = {}
for h = 1, PR.HOURS - 1 do table.insert(worstBazaar, closedBucket(999999 + h, 640000000)) end
table.insert(worstBazaar, openBucket(999999 + PR.HOURS, PR.BazaarCaps, 640000000))
local bazaarBytes = #serde.encode("json", worstBazaar)
local worstAuction = {}
local longest = ids[1]
for _, id in ipairs(ids) do if #id > #longest then longest = id end end
for k = 1, PR.AUCTION_ITEMS do
	local l = {}
	local per = math.floor(PR.AUCTION_BUCKETS / PR.AUCTION_ITEMS)
	for h = 1, per - 1 do table.insert(l, closedBucket(999999 + h, 600)) end
	table.insert(l, openBucket(999999 + per, PR.AuctionCaps, 600))
	worstAuction[longest .. k] = l
end
local auctionBytes = #serde.encode("json", worstAuction)
ok(bazaarBytes < 32 * 1024, "worst-case Bazaar history < 32 KB: " .. bazaarBytes)
ok(auctionBytes < 192 * 1024, "worst-case auction history < 192 KB: " .. auctionBytes)
-- The auction history key: every item's buckets plus PR.SEEN recent ids (the
-- longest id shape: "m" / "s" + a 10-digit revision or listing id).
do
local worstHistKey = {history = worstAuction, seen = {}, version = 1}
for k = 1, PR.SEEN do worstHistKey.seen[k] = "m" .. tostring(9000000000 + k) end
local histKeyBytes = #serde.encode("json", worstHistKey)
ok(histKeyBytes <= 480 * 1024, "worst-case auction history key (hist:auction:<cat>) <= 480 KB: " .. histKeyBytes)
print("Price history worst case: Bazaar " .. bazaarBytes .. " / Auction category " .. auctionBytes .. " / auction history key " .. histKeyBytes .. " JSON bytes.")
end

-- A4e. Auction history key: merge, dedupe by sale id, migration, late sales.
do
	eq(PR.histKey("weapon"), "hist:auction:weapon", "auction history key per category")
	local key, kind, cat = PR.keyFor(ids[1])
	ok(key == "hist:auction:weapon" and kind == "auction" and cat == "weapon", "keyFor points auction items at their history key")
	eq(select(1, PR.keyFor("Ore")), "bazaar_v1_Ore", "Bazaar history stays in the Bazaar key")
	local H = 800000
	local sale = {id = "s1", item = ids[1], h = H, price = 500, seller = "1", buyer = "2"}
	local book, added = PR.mergeAuction(nil, {sale}, H)
	ok(added == 1 and book.history[ids[1]][1].n == 1 and book.seen[1] == "s1" and book.version == 1, "a sale merges into a fresh history key")
	local again
	book, again = PR.mergeAuction(book, {sale, {id = "s1", item = ids[1], h = H, price = 500}}, H)
	ok(again == 0 and book.history[ids[1]][1].n == 1, "a re-sent sale id is skipped (at-least-once flush counts once)")
	book, added = PR.mergeAuction(book, {{id = "s2", item = ids[1], h = H, price = 520, seller = "3", buyer = "4"}, {item = ids[1], price = 9}, "junk"}, H)
	ok(added == 1 and book.history[ids[1]][1].n == 2, "a new id counts; entries without ids are ignored")
	-- Medians, outliers and pair caps still apply (QC M1): the same pair's third sale this hour.
	for k = 3, 5 do PR.mergeAuction(book, {{id = "s" .. k, item = ids[1], h = H, price = 510, seller = "1", buyer = "2"}}, H) end
	ok(book.history[ids[1]][1].n == 3 and book.history[ids[1]][1].x == 2, "pair cap (2 sales per pair per hour) still holds")
	-- Seen ids stay bounded.
	local many = {}
	for k = 1, PR.SEEN + 40 do many[k] = {id = "x" .. k, item = ids[2], h = H, price = 100, seller = tostring(k), buyer = "b" .. k} end
	PR.mergeAuction(book, many, H)
	eq(#book.seen, PR.SEEN, "recent ids bounded to Prices.SEEN")
	eq(book.seen[#book.seen], "x" .. (PR.SEEN + 40), "newest id kept")
	-- A late sale (stamped hours earlier) never prunes a newer server's bucket.
	local late = PR.mergeAuction(nil, {{id = "a", item = ids[1], h = H + 1, price = 100, seller = "1", buyer = "2"}}, H + 1)
	PR.mergeAuction(late, {{id = "b", item = ids[1], h = H - 5, price = 100, seller = "3", buyer = "4"}}, H + 1)
	local hours = {}
	for _, b in ipairs(late.history[ids[1]]) do table.insert(hours, b.h) end
	ok(#hours == 2 and hours[1] == H and hours[2] == H + 1, "a late sale is clamped to the previous hour; the newer bucket stays")
	-- Migration of legacy in-key history: buckets merge by hour, under the caps.
	local legacy = {[ids[1]] = {{h = H + 1, n = 3, v = 300, lo = 100, hi = 100, m = 100, t = 3}}, [ids[3]] = {{h = H, n = 1, v = 50, lo = 50, hi = 50}}}
	local moved, n = PR.mergeAuction(late, {{id = "m7", moved = legacy}}, H + 1)
	ok(n == 1 and moved.history[ids[3]][1].n == 1, "legacy items move into the history key")
	local merged = moved.history[ids[1]]
	ok(#merged == 2 and merged[2].h == H + 1 and merged[2].n == 4, "legacy buckets merge with the same hour")
	local _, twice = PR.mergeAuction(moved, {{id = "m7", moved = legacy}}, H + 1)
	eq(twice, 0, "a migration id merges once")
end

-- A4b. QC M1: wash trading cannot fake the price history.
do
	local H = 500000
	local m = {}
	-- Hour H-1: three real traders at 100.
	PR.record(m, H - 1, 100, 50, "1", "2")
	PR.record(m, H - 1, 100, 50, "3", "1")
	-- Hour H: two alts wash 640 units at 2.5x (pair-capped) and 640 at 10x (outliers).
	PR.record(m, H, 250, 640, "9", "8")
	PR.record(m, H, 1000, 640, "8", "9")
	PR.record(m, H, 100, 20, "1", "3")
	local b = m[#m]
	eq(b.n, PR.BazaarCaps.pair + 20, "outliers and the pair's excess are left out of the averages")
	eq(b.x, 640 + 640 - PR.BazaarCaps.pair, "excluded units counted apart")
	eq(m[1].t, 3, "a closed bucket keeps its distinct-trader count")
	ok(m[1].q == nil and m[1].u == nil and m[1].pr == nil and m[1].m == 100, "a closed bucket folds its ladders into a median")
	local sm = PR.summary(m, H * 3600 + 60, "Ore")
	eq(sm.last, 250, "per-bucket median of the counted fills (160 at 250 vs 20 at 100)")
	ok(sm.hi7 == 250 and sm.lo7 == 100, "range ignores the 10x outlier")
	ok(sm.avg24 < 300, "the 24h average stays far below the wash price: " .. tostring(sm.avg24))
	-- A median, not a mean: one fill at 2.9x barely moves the price.
	local med = {}
	PR.record(med, H, 100, 10, "1", "2")
	PR.record(med, H, 290, 1, "3", "4")
	eq(PR.summary(med, H * 3600, "Ore").last, 100, "volume-weighted median per bucket")
	-- Thin market: fewer than 3 distinct traders in the window.
	local thin = {}
	PR.record(thin, H, 50, 5, "8", "9")
	local ts = PR.summary(thin, H * 3600, "Ore")
	ok(ts.thin and ts.traders24 == 2 and has(PR.text(ts), "thin market"), "two traders: thin market")
	PR.record(thin, H, 50, 5, "7", "9")
	ok(not PR.summary(thin, H * 3600, "Ore").thin, "three traders: not thin")
	-- Legacy buckets (no medians or trader counts) still read.
	local legacy = PR.summary({{h = H, n = 10, v = 200, lo = 20, hi = 20}}, H * 3600, "Ore")
	ok(legacy.avg24 == 20 and not legacy.thin, "legacy buckets keep working")
end
-- A4c. QC L2: prune keeps a bucket an hour ahead and merges by matching hour.
do
	local H = 600000
	local skew = {{h = H + 1, n = 2, v = 20, lo = 10, hi = 10}}
	PR.prune(skew, H)
	eq(#skew, 1, "a bucket one hour ahead (clock skew) is kept")
	PR.record(skew, H, 30, 3, "1", "2")
	ok(#skew == 2 and skew[1].h == H and skew[2].h == H + 1 and skew[2].n == 2, "the behind server's fill merges into its own hour, in order")
	PR.record(skew, H, 30, 1, "1", "3")
	ok(#skew == 2 and skew[1].n == 4, "a second fill finds its hour by h, not by position")
	local dup = {{h = H, n = 2, v = 20, lo = 10, hi = 10}, {h = H, n = 3, v = 30, lo = 10, hi = 10}, {h = H + 5, n = 1, v = 1, lo = 1, hi = 1}}
	PR.prune(dup, H)
	ok(#dup == 1 and dup[1].n == 5, "buckets sharing an hour merge; more than an hour ahead is dropped")
end
-- A4d. QC L7: auction eviction never drops the item just recorded while others can give way.
do
	local full = {}
	for k = 1, PR.AUCTION_ITEMS do full[string.format("b%03d", k)] = {{h = 700000, n = 1, v = 10, lo = 10, hi = 10, m = 10, t = 2}} end
	PR.recordAuction(full, "a000", 700000, 50, "1", "2")
	ok(full.a000 ~= nil and full.a000[1].n == 1, "the newly recorded item survives the item cap")
	eq(full.b001, nil, "the oldest other item gave way")
	local solo = {}
	PR.recordAuction(solo, "a000", 700000, 50, "1", "2")
	ok(#solo.a000 == 1, "a lone item keeps its only bucket")
end
-- A5. Daily stock.
local limited = 0
for _, f in ipairs(RA.Folk) do
	for _, o in ipairs(f.shop or {}) do
		local lim = ST.limit(ST.key("rq", f.role, o.item))
		if string.find(o.item, "^WarpScroll") then eq(lim, nil, f.role .. " warp scrolls are unlimited") end
		if lim then limited += 1; ok(lim >= 8 and lim <= 64, f.role .. " " .. o.item .. " limit in range") end
		-- No coin mint (§4): every offer still sells at ≥ 1.3 × the merchant value.
		ok(o.price / o.amount >= Data.Items[o.item].value * 1.3, f.role .. " " .. o.item .. " price ≥ 1.3 × value")
	end
end
ok(limited >= 12, "selected regional wares carry a daily limit (" .. limited .. ")")
eq(ST.limit(ST.key("sv", "Agility", "GaleDraught")), ST.Limits.GaleDraught, "skill vendor limit")
eq(ST.limit(ST.key("roost", "PetCandy")), ST.Limits.PetCandy, "Roost limit")
eq(ST.limit(ST.key("sv", "Agility", "WindrunnerHood")), nil, "one-of-a-kind wares are not stock-limited")
for _, bad in ipairs({"rq:SeedSeller:Tonic", "it:Ore", "it:Nope", "x", 5, "it:Tonic:1"}) do eq(ST.limit(bad), nil, "unknown key: " .. tostring(bad)) end
-- QC M2: one key per item, whichever shop sells it.
eq(ST.key("rq", "SeedSeller", "Tonic"), ST.key("rq", "Anyone", "Tonic"), "regional shops share an item's key")
eq(ST.key("sv", "Agility", "GaleDraught"), "it:GaleDraught", "skill vendor key is the item")
eq(ST.key("roost", "PetCandy"), "it:PetCandy", "Roost key is the item")
local tonicKey = ST.key("rq", "SeedSeller", "Tonic")
local day = 20000
local rec = ST.roll({day = day, n = {[tonicKey] = 10, junk = 4, ["it:PetCandy"] = 999}}, day * 86400 + 5)
ok(rec.n[tonicKey] == 10 and rec.n.junk == nil and rec.n["it:PetCandy"] == ST.Limits.PetCandy, "same day: counts kept, junk dropped, capped")
-- Legacy per-shop keys (saved before M2) fold into the item's key, summed and capped.
local legacy = ST.roll({day = day, n = {["rq:SeedSeller:Tonic"] = 30, ["rq:Brewer:Tonic"] = 50, ["roost:PetCandy"] = 3}}, day * 86400 + 5)
ok(legacy.n[tonicKey] == ST.Limits.Tonic and legacy.n["it:PetCandy"] == 3 and legacy.n["rq:SeedSeller:Tonic"] == nil, "legacy per-shop counts fold into the item key")
eq(ST.roll(rec, (day + 1) * 86400).n[tonicKey], nil, "next UTC day restocks")
local behind = ST.roll(rec, (day - 1) * 86400 + 10)
ok(behind.day == day and behind.n[tonicKey] == 10, "a clock running behind never restocks early (roll forward only)")
local future = ST.roll({day = day + 50, n = {[tonicKey] = 64}}, day * 86400)
ok(future.day == day + 1 and future.n[tonicKey] == 64, "a tampered far-future day is pulled back to tomorrow")
eq(ST.roll(future, (day + 2) * 86400).n[tonicKey], nil, "and restocks the day after")
eq(select(1, ST.left(rec, tonicKey)), 54, "left today")
eq(ST.text(8, 64), "8/64 left today", "offer text")
-- A6. Calculator.
local mining = CA.actions("Mining")
ok(#mining >= #Data.ResourceTiers.Mining, "Mining actions include every node")
ok(mining[1].level <= mining[#mining].level, "actions sorted by level")
local hasOre = false
for _, a in ipairs(mining) do if a.id == "Ore" and a.kind == "gather" and a.xp == 12 then hasOre = true end end
ok(hasOre, "Copperstone Ore is a 12 XP Mining action")
ok(#CA.actions("Smithing") > 5 and #CA.actions("Crafting") > 5 and #CA.actions("Hunter") > 3, "craft and catch skills have actions")
ok(table.find(CA.skills(), "Mining") and table.find(CA.skills(), "Crafting"), "calculator skills")
local plan = CA.plan(0, 10, 12)
eq(plan.remaining, X[10], "XP to level 10 from 0")
eq(plan.actions, math.ceil(X[10] / 12), "Ore mines to level 10")
eq(CA.plan(X[50], 40, 12).remaining, 0, "already past the target")
eq(CA.plan(0, 10, 0).actions, nil, "no XP per action: no count")
-- A7. Goal toasts ride §31.
local toast = Data.Features.announceText({kind = "goal", title = "Mining level 50"})
ok(toast.head == "GOAL COMPLETE" and toast.body == "Mining level 50", "goal toast text")
eq(Data.Features.announceText({kind = "skill", skill = "Mining", level = 2}).head, "SKILL LEVEL UP", "§31 kinds unchanged")
print("PASS: " .. checks .. " data assertions.")

------------------------------------------------------------------------------
-- Part B: server.
------------------------------------------------------------------------------
local partB = checks
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
local econFailure = nil -- "after": commit, then lose the acknowledgement
local repeatEcon = false -- run economy transforms twice (UpdateAsync retries)
local histFailure = nil -- auction history keys: "before" fails without committing, "after" commits then loses the ack
local histWrites = 0
local onGet = nil -- a hook run during a read (QC L1: the player leaves mid-read)
function db:GetAsync(key) if onGet then local f = onGet; onGet = nil; f(key) end return copy(data[key]) end
function db:UpdateAsync(key, op)
	local econ = key:match("^bazaar") or key:match("^auction")
	local hist = key:match("^hist:auction:")
	if hist then
		histWrites += 1
		if histFailure == "before" then histFailure = nil; error("Injected history outage") end
	end
	if econ and repeatEcon then op(copy(data[key])) end
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	if econ and econFailure == "after" then econFailure = nil; error("Injected lost acknowledgement") end
	if hist and histFailure == "after" then histFailure = nil; error("Injected lost history acknowledgement") end
	return copy(data[key])
end
local npcAt, models = {}, {}
local roles = {"Guide"}
for _, f in ipairs(RA.Folk) do table.insert(roles, f.role) end
for i, role in ipairs(roles) do
	npcAt[role] = Vector3.new(i * 100, 5, 0)
	local root = {Position = npcAt[role]}
	table.insert(models, {GetAttribute = function(_, k) return if k == "TownsfolkRole" then role else nil end,
		FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end})
end
local townsfolk = {GetChildren = function() return models end}
local storage = {AetherTrails = {Name = "AetherTrails"}, IsleTravelGate = {Invoke = function() return true end}}
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua")}
local guid = 0
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) return storage[name] end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() guid += 1; return "systems-test-" .. guid end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local delayed = {} -- task.delay callbacks; runFlush() runs the §33 history flushes
local function runFlush()
	local ran = 0
	for i = #delayed, 1, -1 do
		local d = delayed[i]
		if d[1] == PR.FLUSH then table.remove(delayed, i); d[2](table.unpack(d[3])); ran += 1 end
	end
	return ran
end
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end,
		FindFirstChild = function(_, name) return if name == "Townsfolk" then townsfolk else nil end},
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
		delay = function(t, f, ...) table.insert(delayed, {t, f, {...}}) end,
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
local remote
for _, o in ipairs(serverObjects) do if o.OnServerInvoke then remote = o end end
ok(remote ~= nil, "IsleAction remote found")
local function cmd(p, verb, item) advance(1); return remote.OnServerInvoke(p, verb, item) end
local function at(p, role) p.root.Position = npcAt[role] + Vector3.new(2, 0, 0) end
local function prompt(action, item, pos)
	local base = {CFrame = CFrame.new(pos)}
	local q = {Enabled = true, MaxActivationDistance = 10, attrs = {IsleAction = action, IsleItem = item}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q) advance(30); p.last = nil; services.ProximityPromptService.PromptTriggered:Fire(q, p); return p.last end
local function announced(s, kind, part)
	for _, e in ipairs(s.announce and s.announce.list or {}) do
		if e.kind == kind and (part == nil or has(tostring(e.title), part)) then return true end
	end
	return false
end

-- B1. Quest helper pins.
local hero = seeded(9101, function(pr) pr.questCompleted = 2; pr.coins = 5000 end)
local s = cmd(hero, "state")
ok(type(s.systems) == "table" and s.systems.pin == nil and #s.systems.goals == 0, "fresh systems state: nothing pinned, no goals")
eq(hero.attrs.IsleObjectivePin, "", "no pin: empty sidebar attribute")
for _, bad in ipairs({"quest:Nope", "diary:Nowhere", "x", string.rep("q", 60)}) do
	ok(has(cmd(hero, "helperPin", bad).message, "Choose a quest"), "bad pin refused: " .. bad)
end
local pinned = cmd(hero, "helperPin", "quest:SunwheelTurns")
ok(has(pinned.message, "Pinned to your sidebar") and has(pinned.message, "Hesper"), "pin reply names the step: " .. pinned.message)
ok(pinned.systems.pin and pinned.systems.pin.id == "quest:SunwheelTurns" and pinned.systems.pin.step == 2, "pinned guide in the snapshot")
eq(pinned.systems.pin.specs[1], "npc:Millwarden", "pinned step carries its waypoint")
ok(has(hero.attrs.IsleObjectivePin, "Accept the quest from Hesper"), "sidebar attribute: " .. tostring(hero.attrs.IsleObjectivePin))
ok(not announced(pinned, "objective", "Accept the quest"), "pinning itself raises no NEW OBJECTIVE toast")
at(hero, "Millwarden")
local accepted = cmd(hero, "rqAccept", "SunwheelTurns")
ok(has(accepted.message, "Quest accepted"), "accepted: " .. accepted.message)
ok(has(hero.attrs.IsleObjectivePin, "Survey"), "next step published: " .. hero.attrs.IsleObjectivePin)
ok(announced(accepted, "objective", "Survey"), "NEW OBJECTIVE announced when the pinned step changes")
-- Rejoin keeps the pin (saved on the profile).
hero = player(9101)
s = cmd(hero, "state")
ok(s.systems.pin and s.systems.pin.id == "quest:SunwheelTurns" and has(hero.attrs.IsleObjectivePin, "Survey"), "pin survives a rejoin")
-- A finished quest unpins itself.
hero = seeded(9101, function(pr) pr.questsDone.SunwheelTurns = true end)
local joinMessage = hero.last and hero.last.message or ""
s = cmd(hero, "state")
ok(s.systems.pin == nil and hero.attrs.IsleObjectivePin == "", "completed quest unpinned")
ok(has(s.message, "Unpinned") or has(joinMessage, "Unpinned"), "unpin note")
eq(stored(hero).helperPin, nil, "pin cleared on the profile")
hero = player(9101)
ok(has(cmd(hero, "helperPin", "quest:SunwheelTurns").message, "already complete"), "cannot pin a finished quest")
-- Diaries and the guild contract.
local d = cmd(hero, "helperPin", "diary:Meadow")
ok(has(d.message, "Sunwheel Downs Diary") and d.systems.pin.id == "diary:Meadow", "diary pinned: " .. d.message)
ok(has(hero.attrs.IsleObjectivePin, "Brambleback"), "diary step: " .. hero.attrs.IsleObjectivePin)
local c = cmd(hero, "helperPin", "contract")
ok(c.systems.pin.id == "contract" and hero.attrs.IsleObjectivePin ~= "", "contract pinned: " .. hero.attrs.IsleObjectivePin)
ok(has(cmd(hero, "helperPin", "").message, "Unpinned") and hero.attrs.IsleObjectivePin == "", "unpin")
ok(has(cmd(hero, "helperPin", "").message, "Nothing is pinned"), "nothing to unpin")
-- A count on the current step updates the sidebar silently (no NEW OBJECTIVE per unit).
local crane = seeded(9108, function(pr) pr.questCompleted = 3; pr.items.AlloyIngot = 5 end)
at(crane, "CraneHand")
ok(has(cmd(crane, "rqAccept", "CraneRepairs").message, "Quest accepted"), "Rivets and Hope accepted")
local cp = cmd(crane, "helperPin", "quest:CraneRepairs")
ok(has(crane.attrs.IsleObjectivePin, "Copperstone Ore") and has(crane.attrs.IsleObjectivePin, " 0/60"), "pinned on the ore step: " .. tostring(crane.attrs.IsleObjectivePin))
local seq0 = cp.announce.seq
crane.root.Position = Vector3.new(0, 5000, 0)
local mined = use(crane, prompt("gather", "Ore", Vector3.new(0, 5000, 0)))
ok(mined and string.match(crane.attrs.IsleObjectivePin, " [1-9]%d*/60$") ~= nil, "the count moves: " .. tostring(crane.attrs.IsleObjectivePin))
local toasts = 0
for _, e in ipairs(mined.announce.list) do if e.seq > seq0 and e.kind == "objective" and has(e.title, "/60") then toasts += 1 end end
eq(toasts, 0, "no NEW OBJECTIVE for a count")
-- Tampered pin dropped on load.
hero = seeded(9101, function(pr) pr.helperPin = "quest:Forged" end)
ok(cmd(hero, "state").systems.pin == nil and stored(hero).helperPin == nil, "tampered pin dropped")

-- B2. Goal board.
local g = seeded(9102, function(pr) pr.coins = 100 end)
s = cmd(g, "goalSet", "level:Mining:10")
ok(has(s.message, "Goal set: Mining level 10"), "goal set: " .. s.message)
eq(#s.systems.goals, 1, "one goal on the board")
local goal = s.systems.goals[1]
ok(goal.have == 0 and goal.need == X[10] and goal.done == false and goal.eta == nil, "level goal progress, no ETA yet")
ok(has(cmd(g, "goalSet", "level:Mining:10").message, "already on your board"), "duplicate refused")
ok(has(cmd(g, "goalSet", "level:Mining:1").message, "2 to 99"), "invalid refused")
ok(has(cmd(g, "goalSet", "quest:Nope:1").message, "Choose a quest"), "unknown quest refused")
ok(has(cmd(g, "goalSet", "item:Ore:0").message, "whole target"), "zero refused")
-- Already reached.
g = seeded(9102, function(pr) pr.items.Ore = 50 end)
ok(has(cmd(g, "goalSet", "item:Ore:20").message, "already reached"), "a reached goal is refused")
-- Gathering builds an XP rate and an ETA (rolling window, ≥ 1 minute of samples).
local rock = prompt("gather", "Ore", Vector3.new(0, 5000, 0))
s = cmd(g, "goalSet", "item:Ore:90")
for _ = 1, 4 do use(g, rock); advance(31) end
s = cmd(g, "state")
ok((s.systems.rates.Mining or 0) > 0, "Mining XP/hour from the rolling window: " .. tostring(s.systems.rates.Mining))
local lv, it
for _, row in ipairs(s.systems.goals) do if row.k == "level" then lv = row elseif row.k == "item" then it = row end end
ok(lv and type(lv.eta) == "number" and lv.eta > 0 and lv.rate > 0, "level goal ETA from XP/hour: " .. tostring(lv and lv.eta))
ok(it and it.have > 50, "item goal progresses")
-- Completion: toast through §31, once (a rejoin renews the journal lease the long test above used up).
g = player(9102)
s = cmd(g, "state")
ok(s.message ~= "Waiting for journal sync.", "journal open again")
local targetOre = (s.items.Ore or 0) + 3
s = cmd(g, "goalRemove", tostring(it.id))
s = cmd(g, "goalSet", "item:Ore:" .. targetOre)
ok(has(s.message, "Goal set"), "near item goal: " .. s.message)
local done
for _ = 1, 5 do
	local r = use(g, rock)
	if r and announced(r, "goal", targetOre .. " ") then done = r; break end
end
ok(done ~= nil, "GOAL COMPLETE announced")
local finished
for _, row in ipairs(done.systems.goals) do if row.k == "item" then finished = row end end
ok(finished and finished.done and finished.eta == 0, "goal marked done")
ok(has(done.message, "Goal complete"), "goal note")
local seq = done.announce.seq
s = use(g, rock)
local again = 0
for _, e in ipairs(s.announce.list) do if e.seq > seq and e.kind == "goal" then again += 1 end end
eq(again, 0, "a finished goal is announced once")
-- Rejoin: goals saved; done stays done (no second toast); clear finished.
g = player(9102)
s = cmd(g, "state")
eq(#s.systems.goals, 2, "goals survive a rejoin")
ok(not announced(s, "goal"), "no toast replay after a rejoin")
ok(has(cmd(g, "goalClear").message, "Cleared 1"), "clear finished")
eq(#cmd(g, "state").systems.goals, 1, "unfinished goal kept")
ok(has(cmd(g, "goalRemove", "999").message, "not on your board"), "unknown id")
ok(has(cmd(g, "goalRemove", "x1").message, "not on your board"), "malformed id")
local id = cmd(g, "state").systems.goals[1].id
ok(has(cmd(g, "goalRemove", tostring(id)).message, "Goal removed"), "remove")
-- Cap.
for i = 1, GL.MAX do ok(has(cmd(g, "goalSet", "xp:Fishing:" .. (i * 1000)).message, "Goal set"), "goal " .. i) end
ok(has(cmd(g, "goalSet", "xp:Fishing:999999").message, "board is full"), "12-goal cap")
-- Tampered saves: junk goals dropped, ids unique, ≤ 12, seq above every id.
g = seeded(9102, function(pr)
	local junk = {{id = 3, k = "level", a = "Mining", n = 20}, {id = 3, k = "level", a = "Mining", n = 30}, {id = 0, k = "item", a = "Ore", n = 5},
		{id = 4, k = "nope", a = "x", n = 1}, "junk", {id = 5, k = "item", a = "Ore", n = 1e12}}
	for i = 1, 20 do table.insert(junk, {id = 100 + i, k = "xp", a = "Mining", n = i * 10}) end
	pr.goals, pr.goalSeq = junk, 1
end)
local saved = stored(g)
ok(#saved.goals <= GL.MAX and saved.goals[1].id == 3 and saved.goals[2].id ~= 3, "tampered goals sanitised")
for _, row in ipairs(saved.goals) do ok(row.k ~= "nope" and row.n <= 1e7, "kept goal valid") end
ok(saved.goalSeq >= 100, "goal ids never repeat after a tampered seq")
-- Boss goals: lair kill counts.
local boss = seeded(9103, function(pr) pr.lairs = pr.lairs or {}; pr.lairs.kc = {[LR.Order[1]] = 2} end)
s = cmd(boss, "goalSet", "kills:" .. LR.Order[1] .. ":5")
ok(has(s.message, "Goal set"), "lair boss goal: " .. s.message)
eq(s.systems.goals[1].have, 2, "lair kills counted")
-- QC L3: XP / goal rates are computed when a sample is taken (once a minute)
-- and served from that cache by every snapshot in between.
do
	local rate = GL.rate
	local calls = 0
	GL.rate = function(...) calls += 1; return rate(...) end
	advance(61)
	cmd(boss, "state") -- takes a sample
	ok(calls > 0, "a sample computes the rates")
	calls = 0
	for _ = 1, 5 do cmd(boss, "state") end
	GL.rate = rate
	eq(calls, 0, "snapshots between samples reuse the cached rates")
end
-- QC L6: a GOAL COMPLETE toast does not mark the renown breakdown dirty.
do
	local RN = Data.Renown
	local breakdown = RN.breakdown
	local shopper = seeded(9109, function(pr) pr.coins = 100000 end)
	at(shopper, "SeedSeller")
	ok(has(cmd(shopper, "goalSet", "item:Tonic:2").message, "Goal set"), "Tonic goal set")
	local calls = 0
	RN.breakdown = function(...) calls += 1; return breakdown(...) end
	local r = cmd(shopper, "rqBuy", "SeedSeller:1:2")
	RN.breakdown = breakdown
	ok(announced(r, "goal"), "the purchase completes the goal")
	eq(calls, 0, "the goal toast leaves the cached renown breakdown in place")
end

-- B3. Daily stock.
local buyer = seeded(9104, function(pr) pr.coins = 1000000 end)
local tonic = RA.FolkByRole.SeedSeller.shop[1]
eq(tonic.item, "Tonic", "Tilly sells Tonic first")
local key = ST.key("rq", "SeedSeller", "Tonic")
s = cmd(buyer, "state")
ok(s.systems.stock.left[key][1] == 64 and s.systems.stock.left[key][2] == 64, "64/64 Tonic left today")
ok(s.systems.stock.resetIn > 0 and s.systems.stock.resetIn <= 86400, "resets at the UTC day")
at(buyer, "SeedSeller")
local b = cmd(buyer, "rqBuy", "SeedSeller:1:60")
ok(has(b.message, "Bought 60"), "60 bought: " .. b.message)
eq(b.systems.stock.left[key][1], 4, "4/64 left")
local coins = b.coins
local over = cmd(buyer, "rqBuy", "SeedSeller:1:8")
ok(has(over.message, "Only 4 of today's 64") and over.coins == coins, "over the stock: refused, nothing charged: " .. over.message)
b = cmd(buyer, "rqBuy", "SeedSeller:1:4")
ok(has(b.message, "Bought 4"), "the last 4 bought")
local out = cmd(buyer, "rqBuy", "SeedSeller:1")
ok(has(out.message, "today's 64") and out.coins == b.coins, "sold out: " .. out.message)
-- QC M2: the cap is per item across every shop: Tonic bought from Tilly also
-- counts at the Fishmonger (a second shop selling it).
eq(RA.FolkByRole.Fishmonger.shop[2].item, "Tonic", "the Fishmonger sells Tonic too")
at(buyer, "Fishmonger")
local elsewhere = cmd(buyer, "rqBuy", "Fishmonger:2")
ok(has(elsewhere.message, "today's 64") and elsewhere.coins == out.coins, "a second shop shares the item's daily cap: " .. elsewhere.message)
at(buyer, "SeedSeller")
-- Unlimited offers still sell.
local scrollOffer = cmd(buyer, "rqBuy", "SeedSeller:3")
ok(not has(scrollOffer.message, "today"), "warp scrolls are not stock-limited: " .. scrollOffer.message)
-- Rejoin keeps today's count.
buyer = player(9104)
eq(cmd(buyer, "state").systems.stock.left[key][1], 0, "stock survives a rejoin")
-- Next UTC day restocks; a clock running behind never restocks early.
local dayStart = (math.floor(utc / 86400) + 1) * 86400
advance(dayStart - utc + 5)
buyer = player(9104) -- a fresh session (the long wait outlived the journal lease)
s = cmd(buyer, "state")
eq(s.systems.stock.left[key][1], 64, "new UTC day restocks")
at(buyer, "SeedSeller")
ok(has(cmd(buyer, "rqBuy", "SeedSeller:1:10").message, "Bought 10"), "bought 10 on the new day")
utc -= 86400 * 2 -- a server whose clock is two days behind
buyer = player(9104)
eq(cmd(buyer, "state").systems.stock.left[key][1], 54, "a server whose clock is behind keeps the newer day (roll forward only)")
utc += 86400 * 2
-- Skill vendor and the Roost.
buyer = seeded(9104, function(pr) pr.items.Skymark = 1000 end)
buyer.attrs.SkillVendor, buyer.attrs.SkillVendorUntil = "Agility", utc + 1000
local sv = cmd(buyer, "skillBuy", "Agility:GaleDraught:32")
ok(has(sv.message, "Bought 32"), "32 Gale Draughts: " .. sv.message)
ok(has(cmd(buyer, "skillBuy", "Agility:GaleDraught").message, "today's 32"), "skill vendor stock enforced")
local roost = cmd(buyer, "petShop", "PetCandy:" .. ST.Limits.PetCandy)
ok(has(roost.message, "Bought"), "Roost candy: " .. roost.message)
local refused = cmd(buyer, "petShop", "PetCandy")
ok(has(refused.message, "today's") and refused.coins == roost.coins, "Roost stock enforced")
eq(refused.systems.stock.left[ST.key("roost", "PetCandy")][1], 0, "Roost 0 left")
-- Tampered stock record.
buyer = seeded(9104, function(pr) pr.shopStock = {day = "x", n = {[key] = -5, junk = 9}} end)
local clean = stored(buyer).shopStock
ok(type(clean.day) == "number" and clean.n.junk == nil and clean.n[key] == nil, "tampered stock sanitised")

-- B4. Price history in the shared economy keys, and priceCheck.
local seller = seeded(9105, function(pr) pr.items.Ore = 100; pr.coins = 1000 end)
local taker = seeded(9106, function(pr) pr.coins = 100000 end)
advance(60)
local offer = cmd(seller, "offer", "Ore:10:20")
ok(has(offer.message, "Sell offer"), "offer rests: " .. offer.message)
advance(60)
local fill = cmd(taker, "buyNow", "Ore:4:25")
ok(has(fill.message, "Bought 4"), "taker fills: " .. fill.message)
local book = data["bazaar_v1_Ore"]
ok(book.history and #book.history == 1 and book.history[1].n == 4 and book.history[1].v == 80, "fill recorded in the Bazaar key (maker's price)")
local view = fill.economy and fill.economy.bazaar
ok(view and view.history and view.history.vol24 == 4 and view.history.avg24 == 20, "Bazaar view carries the history summary")
-- Lost acknowledgement: committed once, the replay never counts again.
advance(60)
econFailure = "after"
local lost = cmd(taker, "buyNow", "Ore:2:25")
ok(not has(lost.message, "Bought 2"), "ack lost: order pending (" .. lost.message .. ")")
eq(data["bazaar_v1_Ore"].history[1].n, 6, "the committed fill is in history once")
advance(60)
local recovered = cmd(taker, "bidClaim", "Ore")
ok(has(recovered.message, "Recovered"), "pending order recovered: " .. recovered.message)
eq(data["bazaar_v1_Ore"].history[1].n, 6, "the replay adds nothing to history")
-- Retried transforms (UpdateAsync re-runs) record once.
repeatEcon = true
advance(60)
cmd(taker, "buyNow", "Ore:1:25")
repeatEcon = false
eq(data["bazaar_v1_Ore"].history[1].n, 7, "a retried transform records the fill once")
-- An hour later, a new bucket; priceCheck reads it.
advance(3600)
taker = player(9106)
advance(60)
ok(has(cmd(taker, "buyNow", "Ore:3:25").message, "Bought 3"), "an hour later: 3 more filled")
eq(#data["bazaar_v1_Ore"].history, 2, "a new hourly bucket")
-- QC M1: fills carry maker and taker; a closed hour keeps only its counts.
local closedHour, openHour = data["bazaar_v1_Ore"].history[1], data["bazaar_v1_Ore"].history[2]
ok(closedHour.t == 2 and closedHour.q == nil and closedHour.pr == nil and closedHour.m == 20, "the closed hour folds into a median and 2 distinct traders")
ok(table.find(openHour.u, "9105") and table.find(openHour.u, "9106") and openHour.pr["9105|9106"] == 3, "the open hour tracks its traders and the pair's units")
advance(20)
local pc = cmd(taker, "priceCheck", "Ore")
-- §34: price-check replies are silent (reply text in `reply`, never in the chat-bound `message`).
ok(pc.silent == true and not has(pc.message, "price check"), "price-check replies are silent")
ok(has(pc.reply, "price check") and has(pc.reply, "24h avg 20") and has(pc.reply, "(10 sold)") and has(pc.reply, "thin market"), "priceCheck (2 traders: thin market): " .. tostring(pc.reply))
ok(pc.systems.prices[1].item == "Ore" and pc.systems.prices[1].vol7 == 10, "price check kept for the client")
ok(has(cmd(taker, "priceCheck", "Nope").reply, "Choose an item"), "unknown item refused")
ok(has(cmd(taker, "priceCheck", "Tonic").reply, "not traded"), "untraded item refused")
for i = 1, 12 do advance(2); cmd(taker, "priceCheck", ({"Ore", "Herb", "Timber", "Fish", "Aetherite", "Sunwheat", "Glowcap", "Brassite", "Voidstone", "Glassfin", "Stormeel", "Moonbloom"})[i]) end
ok(#cmd(taker, "state").systems.prices <= PR.CHECKS, "price checks bounded per player")
-- QC M3: priceCheck skips the 0.24 s action cooldown (read throttle only) and
-- spends its own read budget, never the Bazaar / Auction House trading budget.
advance(60)
remote.OnServerInvoke(taker, "goalClear") -- an action starts the cooldown
advance(0.1)
local quick = remote.OnServerInvoke(taker, "priceCheck", "Ore")
ok(quick and not has((quick.reply or quick.message), "One moment"), "priceCheck is not held by the action cooldown: " .. tostring(quick and quick.message))
local commodities = {}
for cid in pairs(Data.Items) do if Data.Economy.isCommodity(cid) and cid ~= "Ore" then table.insert(commodities, cid) end end
table.sort(commodities)
local busy = 0
for i = 1, 14 do
	advance(0.1)
	local r = remote.OnServerInvoke(taker, "priceCheck", commodities[i])
	if r and has(r.reply or r.message, "busy") then busy += 1 end
end
ok(busy > 0, "uncached price checks are bounded by their own budget (" .. busy .. " refused)")
local trade = cmd(taker, "buyNow", "Ore:1:25")
ok(not has(trade.message, "busy"), "trading still has its full budget after a burst of price checks: " .. trade.message)
-- QC L1: a player who leaves while the read is in flight gets no stored result.
advance(60)
local gone = taker
onGet = function() leave(gone) end
remote.OnServerInvoke(gone, "priceCheck", commodities[20])
liveById[gone.UserId] = gone
services.Players.PlayerAdded:Fire(gone) -- the same Player object joins again
local back = cmd(gone, "state")
local leaked = false
for _, row in ipairs(back.systems and back.systems.prices or {}) do if row.item == commodities[20] then leaked = true end end
ok(back.systems and not leaked, "a price check finished after leaving is dropped")
taker = player(9106)
-- Auctions: a completed sale records its price under the item.
local weapon
for _, wid in ipairs(ids) do
	local def = Data.Items[wid]
	if not def.requires and weapon == nil then weapon = wid end
end
weapon = weapon or ids[1]
local lister = seeded(9107, function(pr) pr.items[weapon] = 1; pr.coins = 1000 end)
advance(60)
local listed = cmd(lister, "ahList", weapon .. ":500")
ok(has(listed.message, "Listed"), "listed: " .. listed.message)
local listingId = data["auction_v1_weapon"].nextId
taker = player(9106)
advance(60)
local bought = cmd(taker, "ahBuy", "weapon:" .. listingId .. ":500")
ok(has(bought.message, "Bought"), "auction bought: " .. bought.message)
do
eq(data["auction_v1_weapon"].history, nil, "the auction key itself holds no price history")
eq(data["hist:auction:weapon"], nil, "the history write waits for the server's flush")
eq(runFlush(), 1, "one flush scheduled for the queued sale")
local ah = data["hist:auction:weapon"] and data["hist:auction:weapon"].history
ok(ah and ah[weapon] and ah[weapon][1].n == 1 and ah[weapon][1].v == 500, "auction sale recorded under the item in hist:auction:weapon")
ok(table.find(data["hist:auction:weapon"].seen, "s" .. listingId) ~= nil, "the sale id is remembered for dedupe")
advance(20)
ok(has(cmd(taker, "priceCheck", weapon).reply, "24h avg 500"), "auction price check reads the history key")
-- Sales recorded for the weapon (counted + excluded units, every bucket).
local function sales()
	local total = 0
	for _, b in ipairs(data["hist:auction:weapon"].history[weapon] or {}) do total += (b.n or 0) + (b.x or 0) end
	return total
end
local function sellOne(price)
	local l = seeded(9107, function(pr) pr.items[weapon] = 1; pr.coins = 100000 end)
	advance(60)
	ok(has(cmd(l, "ahList", weapon .. ":" .. price).message, "Listed"), "listed at " .. price)
	local id = data["auction_v1_weapon"].nextId
	local t = player(9106)
	advance(60)
	ok(has(cmd(t, "ahBuy", "weapon:" .. id .. ":" .. price).message, "Bought"), "bought at " .. price)
	return id
end
-- Batched: two sales, one flush, one history write.
local writesBefore = histWrites
sellOne(510); sellOne(490)
eq(runFlush(), 1, "two sales share one scheduled flush")
eq(histWrites - writesBefore, 1, "and one history write")
eq(sales(), 3, "both sales recorded")
-- Flush fails before committing: retried on the next flush, recorded once.
sellOne(500)
histFailure = "before"
eq(runFlush(), 1, "flush attempted")
eq(sales(), 3, "a failed flush wrote nothing")
eq(runFlush(), 1, "the failed batch is rescheduled")
eq(sales(), 4, "the retry records the sale once")
-- Flush commits but loses its acknowledgement: the retry is deduped by sale id.
sellOne(500)
histFailure = "after"
runFlush()
eq(sales(), 5, "committed despite the lost acknowledgement")
eq(runFlush(), 1, "the unacknowledged batch is retried")
eq(sales(), 5, "the re-sent sale id adds nothing (at-least-once, counted once)")
eq(runFlush(), 0, "nothing left to flush")
-- The auction write itself loses its acknowledgement: the replay queues the sale once.
do
	local l = seeded(9107, function(pr) pr.items[weapon] = 1; pr.coins = 100000 end)
	advance(60)
	cmd(l, "ahList", weapon .. ":500")
	local id = data["auction_v1_weapon"].nextId
	local t = player(9106)
	advance(60)
	econFailure = "after"
	local pending = cmd(t, "ahBuy", "weapon:" .. id .. ":500")
	ok(not has(pending.message, "Bought"), "ack lost: purchase pending (" .. pending.message .. ")")
	eq(runFlush(), 0, "nothing queued before the commit is proven")
	advance(60)
	local rec = cmd(t, "ahClaim", "weapon")
	ok(has(rec.message, "Recovered"), "pending purchase recovered: " .. rec.message)
	eq(runFlush(), 1, "the replay queued the stashed sale")
	eq(sales(), 6, "the sale is in history once")
end
-- Legacy history inside the auction key moves out on its next write.
do
	local legacyItem = ids[#ids]
	data["auction_v1_weapon"].history = {[legacyItem] = {{h = PR.hour(utc), n = 2, v = 600, lo = 300, hi = 300, m = 300, t = 3}}}
	local l = seeded(9107, function(pr) pr.items[weapon] = 1; pr.coins = 100000 end)
	advance(60)
	ok(has(cmd(l, "ahList", weapon .. ":700").message, "Listed"), "a write to the legacy key")
	eq(data["auction_v1_weapon"].history, nil, "legacy history removed from the auction key")
	eq(runFlush(), 1, "migration queued")
	local moved = data["hist:auction:weapon"].history[legacyItem]
	ok(moved and moved[1].n == 2 and moved[1].v == 600, "legacy history now in hist:auction:weapon")
	eq(sales(), 6, "existing history untouched by the migration")
	advance(20)
	ok(has(cmd(player(9106), "priceCheck", legacyItem).reply, "24h avg 300"), "migrated history answers price checks")
end
end
-- Ironman journals can read prices too (read-only).
print("PASS: " .. (checks - partB) .. " server assertions.")

------------------------------------------------------------------------------
-- Part C: clients.
------------------------------------------------------------------------------
local partC = checks
do
	local H = require("./tools/ui-harness")
	local snap = H.snapshot()
	snap.systems = {
		pin = {id = "quest:BrassfallEchoes", title = "Echoes under Brassfall", status = "active", step = 3, total = 6, text = "Defeat 15 Shale Crawler 0/15", specs = {"monster:ShaleCrawler"}},
		goals = {{id = 1, k = "level", a = "Mining", n = 40, done = false, have = 5000, need = X[40], label = "Mining level 40", rate = 12000, eta = 9000},
			{id = 2, k = "item", a = "Ore", n = 100, done = true, have = 100, need = 100, label = "100 Copperstone Ore", rate = 0, eta = 0}},
		goalMax = 12, rates = {Mining = 12000}, window = 1800,
		prices = {PR.summary({{h = 100, n = 5, v = 100, lo = 20, hi = 20}}, 100 * 3600 + 5, "Ore")},
		stock = {resetIn = 3600, left = {[ST.key("sv", "Agility", "GaleDraught")] = {8, 32}, [ST.key("roost", "PetCandy")] = {0, 16}}},
	}
	snap.economy.bazaar.history = PR.summary({{h = 100, n = 5, v = 100, lo = 20, hi = 20}}, 100 * 3600 + 5, "Ore")
	local ui = H.runAtlas(roblox.Vector2.new(1366, 768), {snapshot = snap})
	ui.player:SetAttribute("IsleObjectivePin", "Defeat 15 Shale Crawler 0/15")
	ui.update.OnClientEvent:Fire(snap)
	local sidebar = H.find(ui.gui, "Sidebar")
	local goalLine = H.find(sidebar, "Goal")
	ok(goalLine and has(goalLine.Text, "Shale Crawler") and has(goalLine.Text, "step 3/6"), "sidebar Objective shows the pinned step, its position labelled (QC L8): " .. tostring(goalLine and goalLine.Text))
	H.press(H.find(sidebar, "AtlasButton"))
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	-- Journal › Quests: NEXT line, Guide / Pin / Waypoint on an active quest.
	H.press(H.find(ui.scroll, "SectionQuests"))
	local questCard = H.find(ui.scroll, "QuestBrassfallEchoes")
	ok(questCard ~= nil, "quest card drawn")
	ok(H.find(questCard, "GuidequestBrassfallEchoes") and H.find(questCard, "PinquestBrassfallEchoes"), "Guide and Pin on the quest card")
	local nextLine = false
	for _, o in ipairs(questCard:GetDescendants()) do if o.ClassName == "TextLabel" and has(o.Text, "NEXT") then nextLine = true end end
	ok(nextLine, "quest card shows the NEXT step")
	H.press(H.find(questCard, "GuidequestBrassfallEchoes"))
	questCard = H.find(ui.scroll, "QuestBrassfallEchoes")
	local stepsCaption = false
	for _, o in ipairs(questCard:GetDescendants()) do if o.Name == "Caption" and has(o.Text, "STEP BY STEP") then stepsCaption = true end end
	ok(stepsCaption, "Guide expands the step list")
	table.clear(ui.sent)
	H.press(H.find(questCard, "PinquestBrassfallEchoes"))
	ok(ui.sent[1] and ui.sent[1][1] == "helperPin" and ui.sent[1][2] == "", "the pinned quest's button unpins (helperPin '')")
	table.clear(ui.sent)
	local other = H.find(ui.scroll, "PinquestTidewingLullaby")
	if other then
		H.press(other)
		ok(ui.sent[1] and ui.sent[1][1] == "helperPin" and ui.sent[1][2] == "quest:TidewingLullaby", "Pin sends helperPin <quest>")
	end
	-- Journal › Helper.
	H.press(H.find(ui.scroll, "SectionHelper"))
	ok(H.find(ui.scroll, "HelperPinned") ~= nil, "Helper page: the pinned guide")
	ok(H.find(ui.scroll, "Helpercontract") ~= nil and H.find(ui.scroll, "HelperdiaryMeadow") ~= nil, "Helper page: contract and diary cards")
	local fired
	local request = ui.player:FindFirstChild("WayfinderRequest")
	if not request then
		request = H.new("BindableEvent", {Name = "WayfinderRequest"})
		request.Parent = ui.player
	end
	request.Event:Connect(function(specs, label) fired = {specs, label} end)
	local wp = H.find(H.find(ui.scroll, "HelperPinned"), "WaypointquestBrassfallEchoes")
	ok(wp ~= nil, "pinned guide offers a Waypoint")
	H.press(wp)
	ok(fired and fired[1][1] == "monster:ShaleCrawler", "Waypoint fires the Wayfinder with the step's specs")
	H.press(H.find(ui.gui, "AtlasButton"))
	-- Journal › Goals.
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui.scroll, "SectionGoals"))
	ok(H.find(ui.scroll, "GoalSummary") and H.find(ui.scroll, "Goal1") and H.find(ui.scroll, "Goal2"), "goal cards")
	local etaShown = false
	for _, o in ipairs(H.find(ui.scroll, "Goal1"):GetDescendants()) do if o.ClassName == "TextLabel" and has(o.Text, "ETA 2h 30m") then etaShown = true end end
	ok(etaShown, "goal ETA shown")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "GoalClear"))
	ok(ui.sent[1] and ui.sent[1][1] == "goalClear", "Clear finished sends goalClear")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "GoalAddLevel99"))
	ok(ui.sent[1] and ui.sent[1][1] == "goalSet" and ui.sent[1][2] == "level:Mining:99", "add a level goal: " .. tostring(ui.sent[1] and ui.sent[1][2]))
	H.press(H.find(ui.scroll, "GoalKindBoss"))
	ok(H.find(ui.scroll, "GoalAddBoss" .. LR.Order[1]) ~= nil, "boss goal choices")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "GoalRemove1"))
	ok(ui.sent[1] and ui.sent[1][1] == "goalRemove" and ui.sent[1][2] == "1", "Remove sends goalRemove")
	-- Hero › Calculator.
	H.press(ui.tabs:FindFirstChild("HeroButton"))
	H.press(H.find(ui.scroll, "SectionCalculator"))
	local target = H.find(ui.scroll, "CalcTarget")
	local actionCards = 0
	for _, o in ipairs(ui.scroll:GetChildren()) do if string.match(o.Name, "^CalcAction") then actionCards += 1 end end
	ok(target ~= nil and actionCards >= 3, "calculator: target and " .. actionCards .. " action cards")
	H.press(H.find(ui.scroll, "CalcPlus5"))
	local title
	for _, o in ipairs(H.find(ui.scroll, "CalcTarget"):GetDescendants()) do if o.ClassName == "TextLabel" and has(o.Text, "→") then title = o.Text end end
	ok(title ~= nil, "calculator title: " .. tostring(title))
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "CalcGoal"))
	ok(ui.sent[1] and ui.sent[1][1] == "goalSet" and string.match(ui.sent[1][2], "^level:Mining:%d+$"), "calculator sets a goal")
	-- Ledger › Prices, the Bazaar history card, Vendors stock line.
	H.press(ui.tabs:FindFirstChild("LedgerButton"))
	H.press(H.find(ui.scroll, "SectionPrices"))
	ok(H.find(ui.scroll, "PriceLatest") and H.find(H.find(ui.scroll, "PriceLatest"), "Sparkline"), "price page: latest check with a sparkline")
	-- QC L5: big groups page through every item.
	do
		local materials = {}
		for mid, def in pairs(Data.Items) do
			if (def.kind == "resource" or def.kind == "material") and (if def.kind == "resource" then Data.ResourceSkill[mid] or "Materials" else "Materials") == "Materials" then table.insert(materials, mid) end
	end
	ok(#materials > 48, "Materials has more items than one page (" .. #materials .. ")")
	H.press(H.find(ui.scroll, "PriceGroupMaterials"))
	local seen = {}
	local function countTiles()
		for _, mid in ipairs(materials) do if H.find(ui.scroll, "Price" .. mid) then seen[mid] = true end end
	end
	countTiles()
	local pagesWalked = 1
	while H.find(ui.scroll, "PriceNext") and pagesWalked < 10 do
		local nextButton = H.find(ui.scroll, "PriceNext")
		local before = 0
		for _ in pairs(seen) do before += 1 end
		H.press(nextButton)
		countTiles()
		local after = 0
		for _ in pairs(seen) do after += 1 end
		pagesWalked += 1
		if after == before then break end
	end
	local reached = 0
	for _ in pairs(seen) do reached += 1 end
	eq(reached, #materials, "every Materials item is reachable across " .. pagesWalked .. " pages")
	H.press(H.find(ui.scroll, "PriceGroupMining"))
	end
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "PriceOre"))
	ok(ui.sent[1] and ui.sent[1][1] == "priceCheck" and ui.sent[1][2] == "Ore", "tapping an item sends priceCheck")
	H.press(H.find(ui.scroll, "SectionOrders"))
	ok(H.find(ui.scroll, "BookHistory") ~= nil, "Bazaar book shows its price history")
	H.press(H.find(ui.scroll, "SectionVendors"))
	local stockLine = false
	for _, o in ipairs(H.find(ui.scroll, "WareGaleDraught"):GetDescendants()) do if o.ClassName == "TextLabel" and has(o.Text, "8/32 left today") then stockLine = true end end
	ok(stockLine, "skill vendor offer shows today's stock")
	-- Tooltip API.
	local api = ui.replicated:FindFirstChild("IslePriceCheckLocal")
	local answer = api and api.OnInvoke("Ore")
	ok(answer and has(answer.text, "24h avg"), "IslePriceCheckLocal answers from known history: " .. tostring(answer and answer.text))
	eq(api.OnInvoke(5), nil, "IslePriceCheckLocal ignores junk")
	-- QC M3: tooltip refreshes reach the server at most once per item every 10 s.
	do
		table.clear(ui.sent)
		api.OnInvoke("Ore", true); api.OnInvoke("Ore", true); api.OnInvoke("Herb", true); api.OnInvoke("Ore", true)
		local sentOre, sentHerb = 0, 0
		for _, m in ipairs(ui.sent) do
			if m[1] == "priceCheck" and m[2] == "Ore" then sentOre += 1 elseif m[1] == "priceCheck" and m[2] == "Herb" then sentHerb += 1 end
	end
	ok(sentOre == 1 and sentHerb == 1, "refresh debounced per item (Ore " .. sentOre .. ", Herb " .. sentHerb .. ")")
	end
	-- Phone layout renders every new page without warnings.
	local phone = H.runAtlas(roblox.Vector2.new(844, 390), {snapshot = snap, touch = true})
	H.press(H.find(phone.gui, "AtlasButton"))
	for _, page in ipairs({{"JournalButton", "SectionHelper"}, {"JournalButton", "SectionGoals"}, {"HeroButton", "SectionCalculator"}, {"LedgerButton", "SectionPrices"}}) do
		H.press(phone.tabs:FindFirstChild(page[1]))
		local section = H.find(phone.scroll, page[2])
		ok(section ~= nil, "phone section " .. page[2])
		H.press(section)
		ok(#phone.scroll:GetChildren() > 2, "phone page " .. page[2] .. " drawn")
	end
	eq(#phone.warnings, 0, "no client warnings: " .. table.concat(phone.warnings, " | "))
	eq(#ui.warnings, 0, "no desktop warnings: " .. table.concat(ui.warnings, " | "))
	-- Dialogue offers show stock and cap the picker (npc.client.lua).
	local npcSource = fs.readFile("npc.client.lua")
	ok(has(npcSource, "left today") and has(npcSource, "lotsLeft(option)"), "dialogue offers show stock and cap the picker")
	local src = fs.readFile("ui.client.lua")
	for _, verb in ipairs({"helperPin", "goalSet", "goalRemove", "goalClear", "priceCheck"}) do ok(has(src, verb .. "=true"), "atlas relays " .. verb) end
end
print("PASS: " .. (checks - partC) .. " client assertions.")
print("Systems Depth QA passed " .. checks .. " checks.")
print("SUITE-END verify-systems.luau")
