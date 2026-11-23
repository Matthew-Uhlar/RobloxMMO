-- Isle Council (docs/DEPTH-CONTRACT.md §36): elected council on the Skyward Calendar.
-- Part A: pure data (GameData "Isle Council" section) — originality, deterministic
--   slates, the election calendar (every clock agrees; nothing rolls back), ballot
--   books (one ballot per account, idempotent sequence numbers, closed / full /
--   bad refusals), tallies under concurrent writes (randomised interleavings,
--   UpdateAsync retries, lost acknowledgements), sealing, minister perks, perk
--   effects and caps (no coin mints, no Health / Defense), announcements, clerk.
-- Part B: server.server.lua, two or three server instances sharing one DataStore
--   double with skewed clocks — vote / change / cooldown / change cap, Ironman,
--   flush + acknowledgement, lost-ack replay, rejoin on another server
--   (re-queue), cross-server tallies, the close, sealing agreement (late and
--   lagging servers adopt the stored result), roll-forward, §31 toasts, and perk
--   application through the real hooks (XP, worker output, Magic Find, stats).
-- Part C: world (Council Hall, ballot chest prompt, clerk anchor, part budget),
--   Journal › Council (term, ballot, candidates, live share, vote buttons,
--   history), the Clerk's dialogue and station routing.
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
local C = Data.Council
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

------------------------------------------------------------------------------
-- Part A: data.
------------------------------------------------------------------------------
-- A1. Pool, perks, originality.
eq(#C.Candidates, 10, "ten candidates in the pool")
local perkCount = 0
for _ in pairs(C.Perks) do perkCount += 1 end
ok(perkCount >= 12, "perk pool (" .. perkCount .. ")")
local banned = {"diana", "paul", "marina", "cole", "aatrox", "foxy", "derpy", "jerry", "scorpius", "finnegan", "diaz", "barry", "hypixel", "skyblock", "mayor"}
local usedPerk = {}
for _, c in ipairs(C.Candidates) do
	eq(#c.perks, 4, c.id .. " runs on four perks")
	ok(type(c.name) == "string" and type(c.title) == "string" and type(c.pitch) == "string" and type(c.portrait) == "string", c.id .. " has name, title, pitch, portrait")
	ok(Data.Rarity and #c.color == 6, c.id .. " colour")
	local seen = {}
	for _, id in ipairs(c.perks) do
		ok(C.Perks[id] ~= nil, c.id .. " perk " .. id .. " exists")
		ok(not seen[id], c.id .. " perks are distinct")
		seen[id], usedPerk[id] = true, true
	end
	for _, word in ipairs(banned) do
		ok(not string.find(string.lower(c.name .. c.title .. c.pitch), word, 1, true), c.id .. " is original (no '" .. word .. "')")
	end
end
for id, p in pairs(C.Perks) do
	ok(usedPerk[id], id .. " is offered by some candidate")
	ok(type(p.name) == "string" and type(p.text) == "string" and #p.color == 6, id .. " has name, text, colour")
	for _, word in ipairs(banned) do ok(not string.find(string.lower(p.name .. p.text), word, 1, true), id .. " is original") end
	ok(p.kind ~= "coins" and p.coins == nil, id .. " never mints coins")
	if p.kind == "xp" then ok(Data.Skills.Mining and ({gathering = true, combat = true, production = true, support = true})[p.category], id .. " category") end
	if p.kind == "magicFind" then ok(Data.RegionById[p.region] ~= nil, id .. " region exists") end
	if p.kind == "stats" then
		for stat in pairs(p.stats) do
			ok(stat ~= "health" and stat ~= "defense", id .. " never adds Health or Defense (Data.PerkBudget)")
			ok(Data.Stats[stat] ~= nil and C.CAPS.stats[stat] ~= nil, id .. " stat " .. stat .. " is known and capped")
		end
	end
end
ok(C.CAPS.stats.health == nil and C.CAPS.stats.defense == nil, "council stats leave the Health / Defense budget untouched")
-- Every region with a magic-find perk has a creature with a rare (< 5%) drop or at least creatures.
for _, p in pairs(C.Perks) do
	if p.kind == "magicFind" then
		local n = 0
		for _, m in pairs(Data.Monsters) do if m.region == p.region then n += 1 end end
		ok(n > 0, p.id .. ": " .. p.region .. " has creatures")
	end
end

-- A2. Deterministic slates.
local appear, twos, threes = {}, 0, 0
for e = 1, 400 do
	local s1, s2 = C.slate(e), C.slate(e)
	ok(s1 == s2, "slate is cached / stable")
	eq(#s1, C.SLATE, "five candidates for year " .. e)
	local ids = {}
	for i, entry in ipairs(s1) do
		local cand = C.CandidateById[entry.id]
		ok(cand ~= nil and not ids[entry.id], "slate entries are distinct pool candidates")
		ids[entry.id] = true
		appear[entry.id] = (appear[entry.id] or 0) + 1
		ok(#entry.perks == 2 or #entry.perks == 3, "2-3 perks")
		if #entry.perks == 2 then twos += 1 else threes += 1 end
		local last = 0
		for _, id in ipairs(entry.perks) do
			local at = table.find(cand.perks, id)
			ok(at ~= nil and at > last, "perks drawn from the candidate's own four, in order")
			last = at
		end
		eq(C.slotOf(e, entry.id), i, "slotOf")
	end
end
for _, c in ipairs(C.Candidates) do ok((appear[c.id] or 0) >= 120, c.id .. " stands regularly (" .. tostring(appear[c.id]) .. "/400)") end
ok(twos > 400 and threes > 400, "both 2- and 3-perk platforms occur (" .. twos .. "/" .. threes .. ")")
-- A fresh copy of the data (another server / client) draws the same slates.
local Data2 = load("shared/GameData.lua")
for e = 480, 520 do
	local a, b = C.slate(e), Data2.Council.slate(e)
	for i = 1, C.SLATE do
		eq(a[i].id, b[i].id, "same slate on every server (year " .. e .. ")")
		eq(table.concat(a[i].perks, ","), table.concat(b[i].perks, ","), "same perks on every server")
	end
end
eq(C.slotOf(500, "Nobody"), nil, "unknown candidate has no slot")

-- A3. Election calendar.
local Cal = Data.Calendar
local now0 = 1800000000
local el = C.election(now0)
local cal = Data.calendarAt(now0)
eq(el.e, cal.year + 1, "the ballot elects next year's council")
eq(el.termYear, cal.year, "the ruling term is the calendar year")
eq(el.closes, cal.yearEnds, "the ballot closes at the year's end")
eq(el.opens, cal.yearStart + (C.OPEN_DAY - 1) * Cal.dayLength, "opens on day " .. C.OPEN_DAY)
eq(Data.calendarAt(el.opens).season, "Emberfall", "opens with Emberfall")
eq(Data.calendarAt(el.opens).day, 1, "on Emberfall 1")
local voting = (el.closes - el.opens) / 86400
ok(voting > 2 and voting < 3, string.format("about 2.5 real days of voting (%.2f)", voting))
local termDays = Cal.yearLength / 86400
ok(termDays > 5 and termDays < 5.2, string.format("a term is one isle year (%.2f days)", termDays))
local w = C.termWindow(el.e)
eq(w.starts, el.closes, "term e starts when its ballot closes")
eq(w.opens, el.opens, "termWindow(e).opens = the ballot's opening")
eq(w.sealAt, el.closes + C.GRACE, "sealed GRACE after the close")
eq(w.ends - w.starts, Cal.yearLength, "term lasts a year")
ok(not C.election(el.opens - 1).open and C.election(el.opens).open, "opens exactly on time")
ok(C.election(el.closes - 1).open and not C.election(el.closes).open, "closes exactly on time")
eq(C.election(el.closes).e, el.e + 1, "the next ballot is for the following year")
eq(C.election(el.closes).termYear, el.e, "the elected term begins at the close")
-- Clocks on different servers: inside a phase every skew agrees on the election.
for _, skew in ipairs({-90, -5, 0, 7, 120}) do
	local t = el.opens + 3600
	eq(C.election(t + skew).e, el.e, "skewed clocks agree mid-ballot (" .. skew .. "s)")
	eq(C.termWindow(C.election(t + skew).e).starts, el.closes, "and on the close")
end

-- A4. Ballot books.
local E = el.e
local closes = el.closes
local t = el.opens + 100
local book, res, changed = C.applyBallots(nil, {{u = "11", c = 1, s = 1}, {u = "12", c = 2, s = 1}}, E, closes, t)
ok(changed and res["11"] == "ok" and res["12"] == "ok", "first ballots counted")
eq(book.n[1] + book.n[2], 2, "two votes")
eq(book.size, 2, "two voters")
local again
again, res, changed = C.applyBallots(copy(book), {{u = "11", c = 1, s = 1}}, E, closes, t)
ok(not changed and res["11"] == "stale", "a replayed ballot changes nothing")
eq(again.n[1], 1, "replay is not counted twice")
book, res = C.applyBallots(book, {{u = "11", c = 3, s = 2}}, E, closes, t)
ok(res["11"] == "ok" and book.n[1] == 0 and book.n[3] == 1 and book.size == 2, "a vote change moves the ballot")
book, res = C.applyBallots(book, {{u = "11", c = 4, s = 1}}, E, closes, t)
ok(res["11"] == "stale" and book.n[3] == 1 and book.n[4] == 0, "an older ballot arriving late is ignored")
book, res = C.applyBallots(book, {{u = "13", c = 5, s = 1}}, E, closes, closes)
ok(res["13"] == "closed" and book.n[5] == 0, "ballots after the close are refused")
book, res = C.applyBallots(book, {{u = "14", c = 9, s = 1}, {u = "15", c = 1, s = 0}, {u = string.rep("9", 30), c = 1, s = 1}, "junk", {c = 1, s = 1}}, E, closes, t)
ok(res["14"] == "bad" and res["15"] == "bad" and book.size == 2, "malformed ballots are refused")
local cap = C.SHARD_CAP
C.SHARD_CAP = 2
book, res = C.applyBallots(book, {{u = "16", c = 1, s = 1}, {u = "11", c = 2, s = 3}}, E, closes, t)
ok(res["16"] == "full" and res["11"] == "ok", "a full shard refuses new voters but still takes changes")
C.SHARD_CAP = cap
local n, size = C.recount(book)
for i = 1, C.SLATE do eq(book.n[i], n[i], "incremental counts match a recount (" .. i .. ")") end
eq(book.size, size, "size matches")
local other = C.cleanBook({e = E - 1, v = {["1"] = {1, 1}}, n = {1, 0, 0, 0, 0}, size = 1}, E)
eq(other.size, 0, "a book from another election starts fresh")
eq(C.cleanBook("x", E).size, 0, "a junk book starts fresh")
eq(C.shardOf(17), 17 % C.SHARDS + 1, "shard by UserId")
ok(C.key(E, 3) ~= C.key(E, 4) and C.key(E, 3) ~= C.key(E + 1, 3) and has(C.resultKey(E), "result"), "distinct keys")
-- Shard book size bound: worst case JSON for a full shard stays under 4 MB.
local fat = {e = E, v = {}, n = {0, 0, 0, 0, 0}, size = 0}
for i = 1, 2000 do fat.v[tostring(9000000000 + i)] = {5, C.MAX_CHANGES} end
local serde = require("@lune/serde")
local per = #serde.encode("json", fat.v) / 2000
ok(per * C.SHARD_CAP < 4000000, string.format("a full shard stays under the 4 MB key limit (~%.1f MB)", per * C.SHARD_CAP / 1e6))

-- A5. Concurrent writes: randomised voters, servers and flush orders. Each
-- "server" keeps its own queue (latest ballot per account); flushes run in a
-- random order, UpdateAsync retries re-run the transform, and some
-- acknowledgements are lost (the op stays queued and is replayed).
local rng = {state = 36}
function rng:NextNumber()
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function rng:NextInteger(lo, hi) return lo + math.floor(self:NextNumber() * (hi - lo + 1)) end
for trial = 1, 40 do
	local store = {}
	local truth = {} -- u -> {c, s}
	local queues = {{}, {}, {}}
	local journal = {} -- u -> {c, s} (what the account's journal says)
	local ops = 0
	for step = 1, 300 do
		local action = rng:NextInteger(1, 10)
		if action <= 6 then
			local u = tostring(rng:NextInteger(1, 60))
			local j = journal[u] or {0, 0}
			local c = rng:NextInteger(1, C.SLATE)
			j = {c, j[2] + 1}
			journal[u] = j
			truth[u] = j
			local server = rng:NextInteger(1, 3) -- the account may hop servers between ballots
			queues[server][u] = {u = u, c = c, s = j[2]}
			ops += 1
		else
			local server = rng:NextInteger(1, 3)
			local q = queues[server]
			local byShard = {}
			for u, op in pairs(q) do
				local sh = C.shardOf(u)
				byShard[sh] = byShard[sh] or {}
				table.insert(byShard[sh], op)
			end
			for sh, batch in pairs(byShard) do
				local key = C.key(E, sh)
				local verdicts
				local tries = rng:NextInteger(1, 3)
				for _ = 1, tries do -- UpdateAsync may run the transform more than once
					local b, r = C.applyBallots(copy(store[key]), copy(batch), E, closes, t)
					verdicts = r
					if _ == tries then store[key] = b end
				end
				local lost = rng:NextNumber() < 0.2
				if not lost then
					for _, op in ipairs(batch) do
						if (verdicts[op.u] == "ok" or verdicts[op.u] == "stale") and q[op.u] and q[op.u].s == op.s then q[op.u] = nil end
					end
				end
			end
		end
	end
	-- Drain: every server flushes until empty (rejoins re-queue unacknowledged journals).
	for u, j in pairs(journal) do queues[1][u] = {u = u, c = j[1], s = j[2]} end
	for _, q in ipairs(queues) do
		local batch = {}
		for _, op in pairs(q) do table.insert(batch, op) end
		for _, op in ipairs(batch) do
			local key = C.key(E, C.shardOf(op.u))
			store[key] = (C.applyBallots(store[key], {op}, E, closes, t))
		end
	end
	local shards = {}
	for sh = 1, C.SHARDS do
		local b = C.cleanBook(store[C.key(E, sh)], E)
		local rn = C.recount(b)
		for i = 1, C.SLATE do assert(rn[i] == b.n[i], "trial " .. trial .. ": counts match a recount") end
		shards[sh] = b.n
	end
	local counts, total = C.sum(shards)
	local expect, voters = {0, 0, 0, 0, 0}, 0
	for _, j in pairs(truth) do expect[j[1]] += 1; voters += 1 end
	for i = 1, C.SLATE do assert(counts[i] == expect[i], "trial " .. trial .. ": slot " .. i .. " has every account's latest vote once") end
	assert(total == voters, "one vote per account")
	checks += C.SLATE + 1
end
print("Concurrent tally: 40 randomised trials (3 servers, retries, lost acks, server hops) match one-latest-vote-per-account.")

-- A6. Sealing and minister perks.
local s500 = C.slate(500)
local r = C.decide(500, {3, 9, 9, 1, 0})
eq(r.winner, s500[2].id, "most votes wins; a tie goes to the earlier slate place")
eq(r.minister, s500[3].id, "runner-up becomes minister")
eq(r.total, 22, "total")
r = C.decide(500, {})
eq(r.winner, s500[1].id, "an empty ballot seats the first slate place")
eq(r.total, 0, "no votes")
for e = 480, 560 do
	local s = C.slate(e)
	for a = 1, C.SLATE do
		for b = 1, C.SLATE do
			if a ~= b then
				local mp = C.ministerPerk(s[a].perks, s[b].perks)
				if mp then
					ok(table.find(s[b].perks, mp) ~= nil, "minister perk is the runner-up's own")
					local slot = C.perkSlot(C.Perks[mp])
					for _, id in ipairs(s[a].perks) do ok(C.perkSlot(C.Perks[id]) ~= slot, "minister perk never overlaps the winner's") end
				end
			end
		end
	end
end
local res500 = C.decide(500, {1, 5, 2, 0, 0})
local clean = C.cleanResult(copy(res500), 500)
ok(clean and clean.winner == res500.winner and clean.ministerPerk == res500.ministerPerk, "a stored result round-trips")
eq(C.cleanResult({e = 500, winner = "Nobody"}, 500), nil, "an unknown winner is refused")
eq(C.cleanResult(res500, 501), nil, "a result for another year is refused")
local forged = copy(res500); forged.ministerPerk = "OpenLedgerX"
eq(C.cleanResult(forged, 500).ministerPerk, nil, "a forged minister perk is dropped")
local perks500 = C.termPerks(res500)
eq(#perks500, #s500[C.slotOf(500, res500.winner)].perks + (if res500.ministerPerk then 1 else 0), "term perks = winner's + minister's")
local hist = C.mergeHistory(nil, res500)
eq(#hist, 1, "history gains the term")
local hist2, added = C.mergeHistory(hist, res500)
ok(#hist2 == 1 and not added, "history never duplicates a term")
for e = 501, 520 do hist = C.mergeHistory(hist, C.decide(e, {e % 3, 1, 0, 0, 0})) end
eq(#hist, C.HISTORY, "history is bounded")
eq(hist[1].e, 520, "newest first")

-- A7. Effects and caps.
local all = {}
for id in pairs(C.Perks) do table.insert(all, id) end
for _, id in ipairs(table.clone(all)) do table.insert(all, id) end -- every perk twice
local fx = C.effects(all)
for cat, v in pairs(fx.xp) do ok(v <= C.CAPS.xp + 1e-9, "XP cap (" .. cat .. ")") end
ok(fx.auctionFee <= C.CAPS.auctionFee and fx.workers <= C.CAPS.workers and fx.dungeonRolls <= C.CAPS.dungeonRolls and fx.factionRep <= C.CAPS.factionRep + 1e-9, "flat caps")
for region, v in pairs(fx.magicFind) do ok(v <= C.CAPS.magicFind, "Magic Find cap (" .. region .. ")") end
for stat, v in pairs(fx.stats) do ok(v <= C.CAPS.stats[stat], "stat cap (" .. stat .. ")") end
local st = C.stats(fx)
ok(st.health == nil and st.defense == nil, "no Health / Defense from the council")
eq(C.xpMult(fx, "Mining"), 1 + C.CAPS.xp, "gathering XP multiplier capped")
eq(C.xpMult(nil, "Mining"), 1, "no term: no XP bonus")
eq(C.xpMult(fx, "NotASkill"), 1, "unknown skill")
local one = C.effects({"BountifulToil"})
eq(C.xpMult(one, "Fishing"), 1.1, "+10% gathering")
eq(C.xpMult(one, "Combat"), 1, "other categories untouched")
for _, price in ipairs({1, 5, 150, 1000, 12345, 1000000}) do
	local base = Data.Economy.auctionFee(price)
	local cut = C.auctionFee(C.effects({"OpenLedger"}), price)
	ok(cut >= 1 and cut <= base, "listing fee only falls, never below 1 (" .. price .. ")")
	eq(C.auctionFee(nil, price), base, "no term: base fee")
end
eq(C.auctionFee(C.effects({"OpenLedger"}), 1000), 5, "Open Ledger halves the 1% fee")
eq(C.magicFind(C.effects({"GloomGleaning"}), Data.Monsters.GloomfangSpider), 20, "Magic Find in the perk's region")
eq(C.magicFind(C.effects({"GloomGleaning"}), Data.Monsters.BramblebackBoar), 0, "not elsewhere")
eq(C.workerWork(C.effects({"TirelessHands"}), 3600), 36000, "10% of an hour's 360,000 work units")
eq(C.workerWork(nil, 3600), 0, "no term: no worker bonus")
eq(C.dungeonRolls(C.effects({"StarlitCoffers", "StarlitCoffers"})), 1, "one extra chest roll at most")
eq(C.factionRep(C.effects({"BannerSworn"}), 100), 120, "+20% faction rep")
eq(C.factionRep(nil, 100), 100, "no term: base rep")
-- Balance: the strongest possible term (winner with three perks + minister) per kind.
local best = {xp = 0, mf = 0}
for e = 1, 400 do
	local s = C.slate(e)
	for a = 1, C.SLATE do
		for b = 1, C.SLATE do
			if a ~= b then
				local f = C.effects(C.termPerks({e = e, winner = s[a].id, ministerPerk = C.ministerPerk(s[a].perks, s[b].perks)}))
				for _, v in pairs(f.xp) do best.xp = math.max(best.xp, v) end
				for _, v in pairs(f.magicFind) do best.mf = math.max(best.mf, v) end
			end
		end
	end
end
ok(best.xp <= 0.15 and best.mf <= 25, string.format("strongest term within caps (XP +%d%%, MF +%d)", best.xp * 100, best.mf))
print(string.format("Balance: best term XP +%d%% (cap %d%%), Magic Find +%d (cap %d), workers +%d%%, one chest roll, rep +%d%%, fee -%d%%.",
	best.xp * 100, C.CAPS.xp * 100, best.mf, C.CAPS.magicFind, C.CAPS.workers, C.CAPS.factionRep * 100, C.CAPS.auctionFee * 100))

-- A8. Announcements and the Clerk.
local F = Data.Features
local a1 = F.announceText({kind = "council", phase = "open", e = 501})
ok(a1.head == "COUNCIL ELECTION OPEN" and has(a1.body, "Year 501"), "open toast")
eq(F.announceText({kind = "council", phase = "closed", e = 501}).head, "BALLOT CLOSED", "closed toast")
local a3 = F.announceText({kind = "council", phase = "term", e = 501, winner = "Velka", minister = "Pim"})
ok(a3.head == "NEW COUNCIL TERM" and has(a3.body, "Velka Starhollow") and has(a3.body, "Minister Pim Quickbarrow"), "term toast: " .. a3.body)
eq(F.announceText({kind = "skill", skill = "Mining", level = 5}).head, "SKILL LEVEL UP", "other toasts unchanged")
ok(F.ANNOUNCE_PRIORITY.council, "council toasts survive a full queue")
local T = Data.Townsfolk
local clerkNpc = T.NPCs[C.CLERK]
ok(clerkNpc and clerkNpc.anchorOnly and table.find(T.RegionFolkOrder, C.CLERK), "the Clerk is a regional NPC on an anchor")
ok(Data.RegionArt.FolkByRole[C.CLERK].region == "Hub", "the Clerk stands in Compass Quay")
ok(T.Verbs.councilVisit ~= nil, "councilVisit is a dialogue verb")
local visit = false
for _, o in ipairs(clerkNpc.nodes.hello.options) do if o.verb == "councilVisit" then visit = true end end
ok(visit, "the Clerk shows the ballot")
local partA = checks
print("Part A (data): " .. partA .. " checks.")

------------------------------------------------------------------------------
-- Part B: server instances on one DataStore double.
------------------------------------------------------------------------------
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
-- One shared store. fail: "before" (throws, nothing written) | "after" (commits, ack lost).
local function newStore()
	local S = {data = {}, writes = 0, reads = 0, fail = nil, repeatCouncil = false, failGets = false}
	function S:GetAsync(key)
		if self.failGets and key:match("^council") then error("Injected read outage") end
		self.reads += 1
		return copy(self.data[key])
	end
	function S:UpdateAsync(key, op)
		local council = key:match("^council") ~= nil
		if council then
			self.writes += 1
			if self.fail == "before" then self.fail = nil; error("Injected outage") end
			if self.repeatCouncil then op(copy(self.data[key])) end
		end
		local value = op(copy(self.data[key]))
		if value ~= nil then self.data[key] = copy(value) end
		if council and self.fail == "after" then self.fail = nil; error("Injected lost acknowledgement") end
		return if value ~= nil then copy(self.data[key]) else nil
	end
	return S
end
local rngValue = 0.999
-- Builds one server. clock = {utc}; skew seconds are added to os.time().
local function newServer(store, clock, skew)
	local S = {objects = {}, delayed = {}, live = {}, skew = skew or 0}
	local npcAt, models = {}, {}
	for i, f in ipairs(RA.Folk) do
		npcAt[f.role] = Vector3.new(i * 100, 5, 0)
		local root = {Position = npcAt[f.role]}
		table.insert(models, {GetAttribute = function(_, k) return if k == "TownsfolkRole" then f.role else nil end,
			FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end})
	end
	S.npcAt = npcAt
	local townsfolk = {GetChildren = function() return models end}
	local storage = {AetherTrails = {Name = "AetherTrails"}, IsleTravelGate = {Invoke = function() return true end}}
	local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
	local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua")}
	local guid = 0
	S.services = {
		Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
		ProximityPromptService = {PromptTriggered = signal()},
		ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
		ServerStorage = {FindFirstChild = function(_, name) return storage[name] end},
		DataStoreService = {GetDataStore = function() return store end},
		HttpService = {GenerateGUID = function() guid += 1; return "council-test-" .. tostring(S) .. guid end},
		RunService = {IsStudio = function() return false end},
	}
	local env = {
		game = {GetService = function(_, name) return S.services[name] end, BindToClose = function() end},
		workspace = {GetAttribute = function(self, key) return rawget(self, key) end,
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
		Random = {new = function() return {NextNumber = function() return rngValue end, NextInteger = function(_, lo) return lo end} end},
		warn = function() end,
		task = {
			spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
			defer = function(f, ...) f(...) end,
			wait = function(t) return coroutine.yield(t) end,
			delay = function(t, f, ...) table.insert(S.delayed, {t, f, {...}}) end,
		},
	}
	luau.load(serverSource, {environment = env, injectGlobals = true})()
	for _, o in ipairs(S.objects) do
		if o.OnServerInvoke then S.remote = o end
		if o.Name == "IsleBridge" then S.bridge = o end
	end
	assert(S.remote and S.bridge, "server remotes")
	-- Runs the council heartbeat (every queued C.TICK delay, once).
	function S.tick()
		local ran = 0
		for i = #S.delayed, 1, -1 do
			local d = S.delayed[i]
			if d[1] == C.TICK then table.remove(S.delayed, i); d[2](table.unpack(d[3])); ran += 1 end
		end
		assert(ran == 1, "exactly one council heartbeat queued (" .. ran .. ")")
	end
	function S.join(id, mutate)
		if mutate then
			local rec = store.data["p" .. id]
			if rec then mutate(rec.profile) end
		end
		local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
		local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
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
	-- Leave and rejoin (a fresh journal lease after a long clock jump; the
	-- harness has no autosave loop to renew it).
	function S.relog(p)
		S.leave(p)
		return S.join(p.UserId)
	end
	function S.cmd(p, verb, item)
		clock.cpu += 1; clock.utc += 1
		return S.remote.OnServerInvoke(p, verb, item)
	end
	return S
end
local function newClock(utc) return {utc = utc, cpu = 10} end
local function profileOf(store, id) return store.data["p" .. id] and store.data["p" .. id].profile end
local function councilOf(s) return s and s.council or {} end
local function announced(s, phase)
	for _, e in ipairs(s and s.announce and s.announce.list or {}) do
		if e.kind == "council" and e.phase == phase then return e end
	end
	return nil
end
local partB = checks

-- B1. Before the ballot opens.
local store = newStore()
local clock = newClock(el.opens - 7200)
local A = newServer(store, clock, 0)
local B = newServer(store, clock, -45) -- B's clock runs 45 s behind
local slate = C.slate(E)
local alice = A.join(5001)
local s = A.cmd(alice, "state")
eq(councilOf(s).e, E, "snapshot names the election")
ok(councilOf(s).open == false and councilOf(s).vote == nil, "not open yet, no vote")
ok(has(A.cmd(alice, "councilVote", slate[1].id).message, "opens in"), "voting before the open is refused")
A.tick()
s = A.cmd(alice, "state")
ok(announced(s, "open") == nil, "no open toast before the open")

-- B2. Open: vote, confirm, change, cooldown.
clock.utc = el.opens + 600
local pushed0 = alice.pushed or 0
A.tick()
ok((alice.pushed or 0) > pushed0, "the heartbeat pushes a snapshot carrying the toast")
ok(announced(alice.last, "open") ~= nil and announced(alice.last, "open").e == E, "COUNCIL ELECTION OPEN toast once the ballot opens")
alice = A.relog(alice)
s = A.cmd(alice, "state")
ok(announced(s, "open") == nil, "a rejoin does not repeat it")
local nob = A.cmd(alice, "councilVote", "Nobody").message
ok(has(nob, "Choose one of this election"), "unknown candidate refused: " .. tostring(nob))
ok(has(A.cmd(alice, "councilVote", string.rep("x", 60)).message, "Choose"), "junk refused")
s = A.cmd(alice, "councilVote", slate[1].id)
ok(has(s.message, "Vote cast for " .. C.candidateName(slate[1].id)), "vote cast: " .. s.message)
ok(councilOf(s).vote == slate[1].id and councilOf(s).confirmed == false, "vote recorded, not yet counted")
ok(has(A.cmd(alice, "councilVote", slate[1].id).message, "already with"), "same vote is a no-op")
ok(has(A.cmd(alice, "councilVote", slate[2].id).message, "inking"), "vote changes are rate-limited")
local writes0 = store.writes
clock.cpu += 20
A.tick()
eq(store.writes, writes0 + 1, "one UpdateAsync for the pending shard")
s = A.cmd(alice, "state")
ok(councilOf(s).confirmed == true, "acknowledged ballot shows as counted")
local key = C.key(E, C.shardOf(5001))
local stored = store.data[key]
ok(stored and stored.v["5001"][1] == 1 and stored.v["5001"][2] == 1 and stored.n[1] == 1, "the shard holds one ballot")
ok(councilOf(s).counts and councilOf(s).counts[1] == 1 and councilOf(s).total == 1, "the cached tally includes the committed ballot")
s = A.cmd(alice, "councilVote", slate[2].id)
ok(has(s.message, "Vote changed to " .. C.candidateName(slate[2].id)), "vote change: " .. s.message)
clock.cpu += 20
A.tick()
stored = store.data[key]
ok(stored.n[1] == 0 and stored.n[2] == 1 and stored.size == 1, "a change moves the single ballot")
-- Lost acknowledgement: the write commits, the reply is lost; the replay is stale and counts nothing.
clock.cpu += 10
A.cmd(alice, "councilVote", slate[3].id)
store.fail = "after"
clock.cpu += 20
A.tick()
s = A.cmd(alice, "state")
ok(councilOf(s).confirmed == false, "lost ack: still counting")
ok(store.data[key].n[3] == 1 and store.data[key].n[2] == 0, "but the ballot committed")
store.repeatCouncil = true -- UpdateAsync retries re-run the transform
clock.cpu += 20
A.tick()
store.repeatCouncil = false
s = A.cmd(alice, "state")
ok(councilOf(s).confirmed == true and store.data[key].n[3] == 1 and store.data[key].size == 1, "replay acknowledged, counted once")
-- An outage keeps the ballot queued and retries.
clock.cpu += 10
A.cmd(alice, "councilVote", slate[4].id)
store.fail = "before"
clock.cpu += 20
A.tick()
eq(store.data[key].n[4], 0, "outage: nothing written")
clock.cpu += 20
A.tick()
ok(store.data[key].n[4] == 1 and store.data[key].n[3] == 0, "retried after the outage")
-- Change cap.
local bob = A.join(5002)
for i = 1, C.MAX_CHANGES do
	clock.cpu += 10
	local reply = A.cmd(bob, "councilVote", slate[(i % 2) + 1].id)
	ok(has(reply.message, "Vote"), "ballot " .. i .. " accepted")
end
clock.cpu += 10
local capped = A.cmd(bob, "councilVote", slate[5].id)
ok(has(capped.message, "changed your vote") and councilOf(capped).changesLeft == 0, "change cap: " .. capped.message)
-- Ironman journals vote too.
local iron = A.join(5003, nil)
A.leave(iron)
iron = A.join(5003, function(pr) pr.ironman = true end)
ok(A.cmd(iron, "state").ironman == true, "an Ironman journal")
clock.cpu += 10
ok(has(A.cmd(iron, "councilVote", slate[5].id).message, "Vote cast"), "Ironman can vote")
clock.cpu += 20
A.tick()

-- B3. Rejoin on another server before the flush: the journal re-queues.
local carol = A.join(5010)
clock.cpu += 10
ok(has(A.cmd(carol, "councilVote", slate[3].id).message, "Vote cast"), "carol votes on A")
A.leave(carol) -- saved with s = 1, ok = 0; A's queue still holds the ballot
local pc = profileOf(store, 5010)
ok(pc.council.c == slate[3].id and pc.council.s == 1 and pc.council.ok == 0, "the journal saved the unacknowledged ballot")
carol = B.join(5010)
B.cmd(carol, "state")
clock.cpu += 20
B.tick() -- B flushes the re-queued ballot
A.tick() -- A flushes its copy: stale, nothing doubles
local ckey = C.key(E, C.shardOf(5010))
eq(store.data[ckey].v["5010"][1], 3, "carol's ballot stored once")
local n3 = C.recount(store.data[ckey])
eq(n3[3], store.data[ckey].n[3], "counts agree after the double flush")
s = B.cmd(carol, "state")
ok(councilOf(s).confirmed == true and councilOf(s).vote == slate[3].id, "carol's vote is counted on B")
-- Carol changes her vote on B; A still holds nothing newer.
clock.cpu += 10
B.cmd(carol, "councilVote", slate[4].id)
clock.cpu += 20
B.tick()
eq(store.data[ckey].v["5010"][1], 4, "a change on another server wins (higher sequence)")

-- B4. Many voters on both servers; both servers' cached tallies agree with the truth.
local truth = {0, 0, 0, 0, 0}
for id = 6000, 6059 do
	local server = if id % 2 == 0 then A else B
	local pl = server.join(id)
	clock.cpu += 10
	local pick = (id * 7) % C.SLATE + 1
	server.cmd(pl, "councilVote", slate[pick].id)
	if id % 5 == 0 then
		clock.cpu += 10
		pick = (pick % C.SLATE) + 1
		server.cmd(pl, "councilVote", slate[pick].id)
	end
	truth[pick] += 1
end
store.repeatCouncil = true
clock.cpu += 200
A.tick(); B.tick()
store.repeatCouncil = false
-- Everyone counted so far (alice slot 4, bob, iron slot 5, carol slot 4).
local shards = {}
for sh = 1, C.SHARDS do shards[sh] = C.cleanBook(store.data[C.key(E, sh)], E).n end
local counts, total = C.sum(shards)
local bobPick = profileOf(store, 5002) and nil
local pb = A.cmd(bob, "state")
local bobSlot = C.slotOf(E, councilOf(pb).vote)
truth[4] += 2; truth[5] += 1; truth[bobSlot] += 1
for i = 1, C.SLATE do eq(counts[i], truth[i], "store tally slot " .. i) end
eq(total, 64, "64 accounts, 64 votes")
clock.cpu += C.READ + 1
A.tick(); B.tick()
local sa, sb = councilOf(A.cmd(alice, "state")), councilOf(B.cmd(carol, "state"))
for i = 1, C.SLATE do
	eq(sa.counts[i], truth[i], "server A's cached share, slot " .. i)
	eq(sb.counts[i], truth[i], "server B's cached share, slot " .. i)
end
eq(sa.total, 64, "server A total")
-- councilView asks for an early read at most every 30 s.
local readsBefore = store.reads
A.cmd(alice, "councilView")
A.tick()
ok(store.reads >= readsBefore + C.SHARDS, "councilView forces a tally read")
readsBefore = store.reads
A.cmd(alice, "councilView")
A.tick()
eq(store.reads, readsBefore, "a second refresh inside 30 s reads nothing")

-- B5. The close, sealing, agreement and late writes.
local expected = C.decide(E, truth)
-- Straddling the close: A's clock is at the close, B's runs 45 s behind.
clock.utc = el.closes + 5
clock.cpu += 30
alice, carol = A.relog(alice), B.relog(carol)
local late = B.join(7001)
s = A.cmd(alice, "councilVote", slate[1].id)
ok(has(s.message, "closed"), "A refuses votes after its close: " .. s.message)
ok(councilOf(s).open == false, "A shows the ballot closed")
ok(has(B.cmd(late, "councilVote", slate[5].id).message, "Vote cast"), "B (clock behind) still takes a ballot")
truth[5] += 1
expected = C.decide(E, truth)
clock.cpu += 20
B.tick() -- B's flush lands before anyone seals (its transform sees B's own clock)
A.tick()
s = A.cmd(alice, "state")
ok(announced(s, "closed") ~= nil, "BALLOT CLOSED toast while the count is sealed")
ok(councilOf(s).term.sealed == false and councilOf(s).term.y == E, "term " .. E .. " is waiting for its seal")
-- Sealing: A (first past sealAt) writes the result; B adopts it later.
clock.utc = el.closes + C.GRACE + 1
clock.cpu += 40
A.tick()
local resultStored = store.data[C.resultKey(E)]
ok(resultStored ~= nil and resultStored.winner == expected.winner, "A sealed the expected winner (" .. tostring(resultStored and resultStored.winner) .. ")")
eq(resultStored.total, 65, "the straggler that landed before the seal counts")
eq(resultStored.minister, expected.minister, "minister sealed")
s = A.cmd(alice, "state")
ok(councilOf(s).term.sealed and councilOf(s).term.winner == expected.winner, "A rules with the sealed term")
local toast = announced(s, "term")
ok(toast and toast.winner == expected.winner and toast.e == E, "NEW COUNCIL TERM toast")
-- (The term ruling when the test began, E - 1, was sealed with no ballots: its first slate place.)
eq(#councilOf(s).history, 2, "history lists the sealed terms")
eq(councilOf(s).history[1].e, E, "newest first")
eq(councilOf(s).history[2].winner, C.slate(E - 1)[1].id, "a term nobody voted in seats its first slate place")
s = B.cmd(carol, "state")
ok(councilOf(s).term.sealed == false, "B's clock is still inside the grace window")
-- A straggler written after the seal (a far-behind server) never changes the result.
local lkey = C.key(E, C.shardOf(7777))
store.data[lkey] = (C.applyBallots(store.data[lkey], {{u = "7777", c = 1, s = 1}}, E, el.closes, el.closes - 1))
clock.utc = el.closes + C.GRACE + 60
clock.cpu += 40
B.tick()
carol = B.relog(carol)
s = B.cmd(carol, "state")
ok(councilOf(s).term.sealed and councilOf(s).term.winner == expected.winner and councilOf(s).term.total == 65, "B adopts the stored result, unchanged by the late ballot")
-- A third server that starts later agrees too.
local Cs = newServer(store, clock, 300)
Cs.tick()
local dave = Cs.join(7100)
s = Cs.cmd(dave, "state")
ok(councilOf(s).term.winner == expected.winner and councilOf(s).term.minister == expected.minister, "a new server agrees on the term")
eq(store.data[C.resultKey(E)].at, resultStored.at, "the result was written once")
-- Roll forward: B's clock steps back before the close; the sealed term holds and the ballot stays shut.
B.skew = -900
clock.cpu += 40
B.tick()
s = B.cmd(carol, "state")
ok(councilOf(s).term.y == E and councilOf(s).term.sealed, "the term never rolls back")
ok(councilOf(s).open == false and councilOf(s).e == E + 1, "the sealed ballot never reopens on a lagging clock")
ok(has(B.cmd(carol, "councilVote", slate[1].id).message, "opens in"), "voting on the old ballot is refused")
B.skew = -45
-- Rejoin: no duplicate toasts for a term already announced on this journal.
A.leave(alice)
alice = B.join(5001)
s = B.cmd(alice, "state")
ok(announced(s, "term") == nil and announced(s, "open") == nil, "toasts are once per journal per election")
-- A ballot from the previous election is replaced by the next election's first vote.
local nextEl = C.election(C.termWindow(E).starts + 1)
clock.utc = nextEl.opens + 60
clock.cpu += 40
B.tick()
ok(announced(alice.last, "open") ~= nil and announced(alice.last, "open").e == E + 1, "the next election announces itself")
alice = B.relog(alice)
s = B.cmd(alice, "state")
ok(councilOf(s).open and councilOf(s).vote == nil and councilOf(s).changesLeft == C.MAX_CHANGES, "a new election starts with a fresh ballot")
clock.cpu += 10
s = B.cmd(alice, "councilVote", C.slate(E + 1)[2].id)
ok(has(s.message, "Vote cast"), "voting in the next election")
eq(B.cmd(alice, "state").council.vote, C.slate(E + 1)[2].id, "the new ballot")
print("Part B1-B5 (ballots, tallies, sealing): " .. (checks - partB) .. " checks.")

-- B6. Perks through the real hooks. Each scenario seals a chosen winner for a
-- term in a fresh store; the baseline server is inside the grace window (no term).
local function yearWith(perkId)
	for y = 600, 4000 do
		for _, entry in ipairs(C.slate(y)) do
			if table.find(entry.perks, perkId) then return y, entry end
		end
	end
	error("no year offers " .. perkId)
end
local function termServer(perkId)
	local y, entry = yearWith(perkId)
	local st = newStore()
	st.data[C.resultKey(y)] = {e = y, winner = entry.id, counts = {0, 0, 0, 0, 0}, total = 0, at = 1}
	local ck = newClock(C.termWindow(y).starts + 4000)
	local server = newServer(st, ck, 0)
	server.tick() -- seals by reading the stored result
	local bst, bck = newStore(), newClock(C.termWindow(y).starts + 30)
	local base = newServer(bst, bck, 0)
	base.tick()
	return {server = server, store = st, clock = ck}, {server = base, store = bst, clock = bck}, y, entry
end
-- XP: +10% in gathering skills (Bountiful Toil).
do
	local T1, T0, _, entry = termServer("BountifulToil")
	local function mine(env)
		local sv = env.server
		local pl = sv.join(8001)
		local before = (sv.cmd(pl, "state").xp or {}).Mining or 0
		local q = {Enabled = true, MaxActivationDistance = 10, attrs = {IsleAction = "gather", IsleItem = "Ore"}}
		function q:GetAttribute(k) return self.attrs[k] end
		local basePart = {CFrame = CFrame.new(pl.root.Position)}
		function q:FindFirstAncestorWhichIsA() return basePart end
		env.clock.cpu += 30
		sv.services.ProximityPromptService.PromptTriggered:Fire(q, pl)
		local snap = sv.cmd(pl, "state")
		return ((snap.xp or {}).Mining or 0) - before, snap
	end
	local withPerk, snap = mine(T1)
	local without = mine(T0)
	ok(without > 0, "baseline mining XP (" .. without .. ")")
	ok(withPerk == math.floor(without * 1.1) or withPerk == math.ceil(without * 1.1), string.format("Bountiful Toil: +10%% Mining XP (%.2f vs %.2f)", withPerk, without))
	ok(table.find(councilOf(snap).term.perks, "BountifulToil") ~= nil and councilOf(snap).term.winner == entry.id, "the snapshot lists the active perks")
end
-- Workers: Tireless Hands (+10% work since the later of the last claim and the term start).
do
	local T1, T0 = termServer("TirelessHands")
	local function aged(env)
		local sv = env.server
		local pl = sv.join(8004)
		sv.leave(pl)
		local rec = env.store.data["p8004"].profile
		rec.workers = {{resource = "Ore", tier = 1, lastClaim = math.floor(env.clock.utc) - 1800}}
		rec.workersClean = nil
		pl = sv.join(8004)
		local snap = sv.cmd(pl, "state")
		return snap.workers[1].ready, snap.workers[1].capacity
	end
	local withPerk, capacity = aged(T1)
	local without = aged(T0)
	ok(without > 0 and withPerk < capacity, "worker produced within capacity (" .. without .. " / " .. capacity .. ")")
	ok(withPerk > without and withPerk >= math.floor(without * 1.1) - 1 and withPerk <= math.ceil(without * 1.1) + 1,
		string.format("Tireless Hands: ~10%% more worker output (%d vs %d)", withPerk, without))
	-- A worker idle since before the term only gains for the term's own span.
	local sv = T1.server
	local pl = sv.join(8007)
	sv.leave(pl)
	local termStart = C.termWindow(C.election(T1.clock.utc).termYear).starts
	local rec = T1.store.data["p8007"].profile
	rec.workers = {{resource = "Ore", tier = 1, lastClaim = termStart - 1800}}
	rec.workersClean = nil
	local w = {lastClaim = termStart - 1800, carry = 0}
	eq(Data.Council.workerWork(Data.Council.effects({"TirelessHands"}), T1.clock.utc - termStart), math.floor((T1.clock.utc - termStart) * 10), "bonus span starts at the term")
	local _ = w
end
-- Magic Find against one region's creatures (rare drops only).
do
	local perkId, target, rare
	local ids = {}
	for id in pairs(C.Perks) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local p = C.Perks[id]
		if p.kind == "magicFind" and not target then
			local mids = {}
			for mid in pairs(Data.Monsters) do table.insert(mids, mid) end
			table.sort(mids)
			for _, mid in ipairs(mids) do
				local m = Data.Monsters[mid]
				if m.region == p.region and not m.seaCreature and not m.worldBoss and not m.superior and not m.lair then
					for _, d in ipairs(m.drops or {}) do
						if d.chance < 0.05 and not target then perkId, target, rare = id, mid, d end
					end
				end
			end
		end
	end
	ok(target ~= nil, "a regional creature with a rare drop (" .. tostring(target) .. ")")
	local T1, T0 = termServer(perkId)
	local function kill(env)
		local sv = env.server
		local pl = sv.join(8005)
		sv.cmd(pl, "state")
		rngValue = rare.chance * 1.1 -- between the base chance and chance x (1 + MF / 100)
		local reply = sv.bridge.OnInvoke("kill", pl, {monster = target})
		rngValue = 0.999
		return reply and reply.drops or {}
	end
	local withPerk = kill(T1)
	local without = kill(T0)
	ok((withPerk[rare.item] or 0) > 0, C.Perks[perkId].name .. ": the rare " .. rare.item .. " drops")
	ok((without[rare.item] or 0) == 0, "without the council it does not")
end
-- Stats perk: p.perkStats.council follows the ruling term (never Health / Defense).
do
	local T1, T0 = termServer("Tidecaller")
	local pl = T1.server.join(8006)
	local snap = T1.server.cmd(pl, "state")
	local bpl = T0.server.join(8006)
	local bsnap = T0.server.cmd(bpl, "state")
	local with, without = snap.depth.stats.seaCreatureChance or 0, bsnap.depth.stats.seaCreatureChance or 0
	eq(with - without, 3, "Tidecaller's Hymn: +3 Sea Creature Chance")
	T1.server.leave(pl)
	local saved = T1.store.data["p8006"].profile.perkStats.council
	ok(saved and saved.seaCreatureChance == 3 and saved.health == nil and saved.defense == nil, "saved as p.perkStats.council")
	T0.server.leave(bpl)
	eq(T0.store.data["p8006"].profile.perkStats.council, nil, "no term: no council stats")
end
-- The remaining hooks are wired at their call sites (rules tested in A7).
local src = fs.readFile("server.server.lua")
ok(has(src, "local mult=Council.xpMult(skill)"), "grantXp applies the council XP multiplier")
ok(has(src, "Council.workerWork(w,now,W.MAX_ACCRUAL)"), "worker settle applies council work")
ok(has(src, "stats.magicFind+family+council"), "kill drops add council Magic Find")
ok(has(src, "reward.rolls+(if Council.dungeonRolls then Council.dungeonRolls() else 0)"), "Observatory chests add the council roll")
ok(has(src, "r.rep=Council.factionRep(r.rep)"), "faction boards add council reputation")
ok(has(src, "Council.auctionFee(price) else Rules.auctionFee(price)"), "auction listings use the council fee")
local blockStart = string.find(src, "-- Isle Council (Isle Council team", 1, true)
local blockEnd = string.find(src, "local function perform(player,verb,item,prompt)", 1, true)
local _, coinHits = string.gsub(string.sub(src, blockStart, blockEnd), "coins%s*[%+%-]=", "")
eq(coinHits, 0, "the council block never changes coins")
print("Part B (server): " .. (checks - partB) .. " checks.")

------------------------------------------------------------------------------
-- Part C: world, Journal › Council, dialogue.
------------------------------------------------------------------------------
local partC = checks
do
	local WH = require("./tools/world-harness")
	local built = WH.build()
	local hub = built.islands:FindFirstChild("Compass Quay")
	local hall = hub and hub:FindFirstChild("Council Hall")
	ok(hall ~= nil and hall:GetAttribute("CouncilContent") == true, "the Council Hall stands on Compass Quay")
	local parts, columns, prompts, slots = 0, 0, {}, 0
	for _, d in hall:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 end
		if d:IsA("BasePart") and d:GetAttribute("Shape") then slots += 1 end
		if d:IsA("BasePart") and d:GetAttribute("Shape") == "Column" then columns += 1 end
		if d:IsA("ProximityPrompt") then table.insert(prompts, d) end
	end
	eq(columns, 6, "six forged columns")
	ok(slots >= 12, "detailed: " .. slots .. " forged mesh slots")
	ok(parts <= 45, "a small static part budget (" .. parts .. ")")
	local static = 0
	for _, d in built.world:GetDescendants() do if d:IsA("BasePart") then static += 1 end end
	ok(static < 4000, "the static world stays under 4000 parts (" .. static .. ")")
	print("Council Hall: " .. parts .. " parts (" .. slots .. " mesh slots); static world " .. static .. " / 4000.")
	local chest
	for _, q in ipairs(prompts) do if q:GetAttribute("IsleAction") == "councilView" then chest = q end end
	ok(chest ~= nil, "the ballot chest prompt")
	local sign
	for _, d in hall:GetDescendants() do if d:GetAttribute("SignTitle") == "Council Hall" then sign = d end end
	ok(sign ~= nil, "the hall's sign (§28 sign system)")
	ok(hub:FindFirstChild("Anchor_Waypoint_CouncilHall", true) ~= nil, "Waypoint_CouncilHall anchor")
	local clerks = {}
	for _, d in built.world:GetDescendants() do if d.Name == "Anchor_NPC_" .. C.CLERK then table.insert(clerks, d) end end
	eq(#clerks, 1, "one clerk anchor")
	local clerk = clerks[1]
	local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
	ok(flat(clerk.CFrame.Position, chest.Parent.CFrame.Position) < 14, "the clerk stands at the hall (" .. flat(clerk.CFrame.Position, chest.Parent.CFrame.Position) .. ")")
	ok(hub:IsAncestorOf(clerk), "on Compass Quay")
	for _, d in built.world:GetDescendants() do
		if d:IsA("BasePart") and string.find(d.Name, "^Anchor_NPC_") and d ~= clerk and math.abs(d.CFrame.Position.Y - clerk.CFrame.Position.Y) < 6 then
			ok(flat(d.CFrame.Position, clerk.CFrame.Position) >= 6, "clerk >= 6 studs from " .. d.Name)
		end
	end
	-- The chest opens Journal › Council.
	local pl = {attributes = {}}
	function pl:GetAttribute(k) return self.attributes[k] end
	function pl:SetAttribute(k, v) self.attributes[k] = v end
	chest.Triggered:Fire(pl)
	ok(pl.attributes.IsleStation == "Council" and pl.attributes.IsleStationVisit == 1, "the chest opens the Council page")
	-- Nothing solid overlaps a path or another prompt host.
	local function ext(o, axis)
		local cf, sz = o.CFrame, o.Size
		return math.abs(cf.RightVector[axis]) * sz.X / 2 + math.abs(cf.UpVector[axis]) * sz.Y / 2 + math.abs(cf.LookVector[axis]) * sz.Z / 2
	end
	local hallBoxes = {}
	for _, d in hall:GetDescendants() do if d:IsA("BasePart") and d.CanCollide then table.insert(hallBoxes, d) end end
	for _, d in hub:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Path" or (d:FindFirstChildOfClass("ProximityPrompt") and not hall:IsAncestorOf(d))) then
			for _, h in ipairs(hallBoxes) do
				local a, b = h.CFrame.Position, d.CFrame.Position
				local overlap = math.abs(a.X - b.X) < ext(h, "X") + ext(d, "X") and math.abs(a.Z - b.Z) < ext(h, "Z") + ext(d, "Z")
					and math.abs(a.Y - b.Y) < ext(h, "Y") + ext(d, "Y")
				ok(not overlap, h.Name .. " clear of " .. d.Name)
			end
		end
	end
end
-- Journal › Council.
do
	local H = require("./tools/ui-harness")
	local snap = H.snapshot()
	local y = 640
	local elx = C.election(C.termWindow(y + 1).opens + 3600) -- ballot for y + 1 open, term y ruling
	local sl = C.slate(elx.e)
	local term = C.decide(y, {4, 9, 1, 0, 2})
	snap.council = {e = elx.e, opens = elx.opens, closes = elx.closes, open = true, now = elx.opens + 3600,
		vote = sl[2].id, confirmed = true, changesLeft = 9, readyIn = 0, counts = {10, 30, 5, 5, 0}, total = 50, tallyAt = elx.opens + 3500,
		term = {y = y, ends = C.termWindow(y).ends, sealed = true, winner = term.winner, minister = term.minister, ministerPerk = term.ministerPerk,
			perks = C.termPerks(term), counts = term.counts, total = term.total},
		history = {{e = y, winner = term.winner, minister = term.minister, ministerPerk = term.ministerPerk, total = 16, votes = 9}}}
	local ui = H.runAtlas(roblox.Vector2.new(1366, 768), {snapshot = snap})
	ui.update.OnClientEvent:Fire(snap)
	H.press(H.find(ui.gui, "AtlasButton"))
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	local section = H.find(ui.scroll, "SectionCouncil") or H.find(ui.atlas, "SectionCouncil")
	ok(section ~= nil, "Journal has a Council section")
	H.press(section)
	local function text(root)
		local out = {}
		for _, d in root:GetDescendants() do if d:IsA("TextLabel") or d:IsA("TextButton") then table.insert(out, d.Text) end end
		return table.concat(out, " | ")
	end
	local termCard = H.find(ui.scroll, "CouncilTerm")
	ok(termCard ~= nil, "term card")
	local tt = text(termCard)
	ok(has(tt, C.candidateName(term.winner)) and has(tt, "IN OFFICE"), "term card names the winner: " .. tt)
	for _, id in ipairs(C.termPerks(term)) do ok(has(tt, C.Perks[id].name), "term card lists " .. id) end
	if term.minister then ok(has(tt, "Minister"), "term card names the minister") end
	ok(has(tt, "Term ends in"), "term countdown")
	local ballot = text(H.find(ui.scroll, "CouncilBallot"))
	ok(has(ballot, "OPEN") and has(ballot, "Ballot closes in") and has(ballot, "counted"), "ballot card: open, countdown, your counted vote: " .. ballot)
	for i, entry in ipairs(sl) do
		local c = H.find(ui.scroll, "CouncilCandidate" .. entry.id)
		ok(c ~= nil, "candidate card " .. entry.id)
		local ct = text(c)
		ok(has(ct, C.candidateName(entry.id)), "candidate name")
		for _, id in ipairs(entry.perks) do ok(has(ct, C.Perks[id].name), entry.id .. " perk " .. id) end
		ok(has(ct, string.format("%.1f%%", snap.council.counts[i] / 50 * 100)), "live share on " .. entry.id .. ": " .. ct)
	end
	ok(has(text(H.find(ui.scroll, "CouncilCandidate" .. sl[2].id)), "YOUR VOTE"), "your vote is marked")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "CouncilVote" .. sl[4].id))
	ok(ui.sent[1] and ui.sent[1][1] == "councilVote" and ui.sent[1][2] == sl[4].id, "Change vote sends councilVote <id>")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "CouncilVote" .. sl[2].id))
	eq(#ui.sent, 0, "voting for your current choice sends nothing")
	ok(H.find(ui.scroll, "CouncilTally") ~= nil, "live tally card")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "CouncilRefresh"))
	ok(ui.sent[1] and ui.sent[1][1] == "councilView", "Refresh sends councilView")
	ok(H.find(ui.scroll, "CouncilHistory" .. y) ~= nil, "history card")
	-- Phone landscape: the page still draws.
	-- Closed ballot, unsealed term.
	local closedSnap = H.snapshot()
	local cl = C.election(C.termWindow(y).starts + 30)
	closedSnap.council = {e = cl.e, opens = cl.opens, closes = cl.closes, open = false, now = C.termWindow(y).starts + 30, changesLeft = C.MAX_CHANGES, readyIn = 0,
		term = {y = y, sealed = false, perks = {}}, history = {}}
	ui.setSnapshot(closedSnap)
	ui.update.OnClientEvent:Fire(closedSnap)
	H.press(H.find(ui.scroll, "SectionCouncil") or H.find(ui.atlas, "SectionCouncil"))
	ok(has(text(H.find(ui.scroll, "CouncilTerm")), "Counting"), "an unsealed term reads 'Counting the ballot'")
	ok(has(text(H.find(ui.scroll, "CouncilBallot")), "Ballot opens in"), "a closed ballot counts down to the next opening")
	table.clear(ui.sent)
	H.press(H.find(ui.scroll, "CouncilVote" .. C.slate(cl.e)[1].id))
	eq(#ui.sent, 0, "no voting while the ballot is shut")
	ok(H.find(ui.scroll, "CouncilHistoryEmpty") ~= nil, "empty history card")
	local uiSource = fs.readFile("ui.client.lua")
	ok(has(uiSource, 'Council="Journal"} -- §36'), "IsleStation Council routes to the Journal")
	ok(has(uiSource, 'station=="Council" then "Council"'), "... and to its Council page")
	ok(has(uiSource, "council.auctionFee(council.effects("), "the Auction House fee preview honours Open Ledger")
	print("Journal › Council: " .. #sl .. " candidates, term, history, vote / refresh buttons.")
end
print("Part C (world, UI): " .. (checks - partC) .. " checks.")
print("Isle Council QA passed " .. checks .. " checks.")
print("SUITE-END verify-council.luau")
