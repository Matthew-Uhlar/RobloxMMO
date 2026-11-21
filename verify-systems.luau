-- Systems Depth (docs/DEPTH-CONTRACT.md §33): quest helper, goal board, market
-- price history, per-player daily shop stock and the XP calculator.
-- Part A: pure data (GameData "Systems Depth" section).
-- Part B: server.server.lua with service doubles — helperPin (sidebar attribute,
--   NEW OBJECTIVE on step change, auto-unpin), goals (validation, cap, completion
--   toast, rolling-window ETA, rejoin / tamper safety), daily stock on regional
--   shops / skill vendors / the Roost (UTC roll-forward only), price history
--   written inside the economy transform (Bazaar fills, auction sales, lost-ack
--   replay counted once) and priceCheck.
-- Part C: clients — atlas pages (Journal › Helper / Goals, Hero › Calculator,
--   Ledger › Prices), quest-card guide/pin, the sidebar Objective, stock text,
--   IslePriceCheckLocal, dialogue stock labels.
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
ok(s.vol24 == 11 and s.avg24 == math.floor(290 / 11 + 0.5) and s.last == 40 and s.lo7 == 20 and s.hi7 == 40, "summary: 24h volume / average / last / range")
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
-- Worst-case added key size.
local worstBazaar = {}
for h = 1, PR.HOURS do table.insert(worstBazaar, {h = 999999 + h, n = 640000000, v = 640000000000000, lo = 1000000, hi = 1000000}) end
local bazaarBytes = #serde.encode("json", worstBazaar)
local worstAuction = {}
local longest = ids[1]
for _, id in ipairs(ids) do if #id > #longest then longest = id end end
for k = 1, PR.AUCTION_ITEMS do
	local l = {}
	for h = 1, math.floor(PR.AUCTION_BUCKETS / PR.AUCTION_ITEMS) do table.insert(l, {h = 999999 + h, n = 600, v = 600000000, lo = 1000000, hi = 1000000}) end
	worstAuction[longest .. k] = l
end
local auctionBytes = #serde.encode("json", worstAuction)
ok(bazaarBytes < 16 * 1024, "worst-case Bazaar history < 16 KB: " .. bazaarBytes)
ok(auctionBytes < 96 * 1024, "worst-case auction history < 96 KB: " .. auctionBytes)
print("Price history worst case: Bazaar " .. bazaarBytes .. " / Auction category " .. auctionBytes .. " JSON bytes (economy keys stay < 512 KB).")

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
eq(ST.limit(ST.key("sv", "Agility", "GaleDraught")), ST.Vendor.GaleDraught, "skill vendor limit")
eq(ST.limit(ST.key("roost", "PetCandy")), ST.Roost.PetCandy, "Roost limit")
eq(ST.limit(ST.key("rq", "SeedSeller", "Shard")), nil, "not sold there: no limit")
eq(ST.limit(ST.key("sv", "Agility", "WindrunnerHood")), nil, "one-of-a-kind wares are not stock-limited")
for _, bad in ipairs({"rq:Nobody:Tonic", "roost:Ore", "x", 5, "rq:SeedSeller:Tonic:1"}) do eq(ST.limit(bad), nil, "unknown key: " .. tostring(bad)) end
local day = 20000
local rec = ST.roll({day = day, n = {["rq:SeedSeller:Tonic"] = 10, junk = 4, ["roost:PetCandy"] = 999}}, day * 86400 + 5)
ok(rec.n["rq:SeedSeller:Tonic"] == 10 and rec.n.junk == nil and rec.n["roost:PetCandy"] == ST.Roost.PetCandy, "same day: counts kept, junk dropped, capped")
eq(ST.roll(rec, (day + 1) * 86400).n["rq:SeedSeller:Tonic"], nil, "next UTC day restocks")
local behind = ST.roll(rec, (day - 1) * 86400 + 10)
ok(behind.day == day and behind.n["rq:SeedSeller:Tonic"] == 10, "a clock running behind never restocks early (roll forward only)")
local future = ST.roll({day = day + 50, n = {["rq:SeedSeller:Tonic"] = 64}}, day * 86400)
ok(future.day == day + 1 and future.n["rq:SeedSeller:Tonic"] == 64, "a tampered far-future day is pulled back to tomorrow")
eq(ST.roll(future, (day + 2) * 86400).n["rq:SeedSeller:Tonic"], nil, "and restocks the day after")
eq(select(1, ST.left(rec, "rq:SeedSeller:Tonic")), 54, "left today")
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
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	local econ = key:match("^bazaar") or key:match("^auction")
	if econ and repeatEcon then op(copy(data[key])) end
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	if econ and econFailure == "after" then econFailure = nil; error("Injected lost acknowledgement") end
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
local roost = cmd(buyer, "petShop", "PetCandy:" .. ST.Roost.PetCandy)
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
advance(20)
local pc = cmd(taker, "priceCheck", "Ore")
-- §34: price-check replies are silent (reply text in `reply`, never in the chat-bound `message`).
ok(pc.silent == true and not has(pc.message, "price check"), "price-check replies are silent")
ok(has(pc.reply, "price check") and has(pc.reply, "24h avg 20") and has(pc.reply, "(10 sold)"), "priceCheck: " .. pc.reply)
ok(pc.systems.prices[1].item == "Ore" and pc.systems.prices[1].vol7 == 10, "price check kept for the client")
ok(has(cmd(taker, "priceCheck", "Nope").reply, "Choose an item"), "unknown item refused")
ok(has(cmd(taker, "priceCheck", "Tonic").reply, "not traded"), "untraded item refused")
for i = 1, 12 do advance(2); cmd(taker, "priceCheck", ({"Ore", "Herb", "Timber", "Fish", "Aetherite", "Sunwheat", "Glowcap", "Brassite", "Voidstone", "Glassfin", "Stormeel", "Moonbloom"})[i]) end
ok(#cmd(taker, "state").systems.prices <= PR.CHECKS, "price checks bounded per player")
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
local ah = data["auction_v1_weapon"].history
ok(ah and ah[weapon] and ah[weapon][1].n == 1 and ah[weapon][1].v == 500, "auction sale recorded under the item")
advance(20)
ok(has(cmd(taker, "priceCheck", weapon).reply, "24h avg 500"), "auction price check")
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
	ok(goalLine and has(goalLine.Text, "Shale Crawler") and has(goalLine.Text, "3/6"), "sidebar Objective shows the pinned step: " .. tostring(goalLine and goalLine.Text))
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
