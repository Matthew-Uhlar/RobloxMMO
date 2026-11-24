-- Tutorial (docs/DEPTH-CONTRACT.md §43): coach cards over the Wayfarer's Path
-- and the first starter quests.
-- Part A: pure rules (GameData "Tutorial" section): the card sequence follows
--   the Path order, then contracts → Charting the Skyway → Lamps of the Quay →
--   finale; copy for click-to-gather; verb parsing; tips detection; sanitising.
-- Part B: server.server.lua with service doubles: cards advance only on server
--   progress (buttons never move a step card), dismiss / next / skip / replay,
--   once-only tips, tips off, rejoin resume, veterans never see it, no grants.
-- Part C: tutorial.client.lua with the atlas and the satchel layer at six
--   screen sizes: the card stays in its Theme.hudLayout lane (never over the
--   hotbar / action bar), touch targets ≥ 44 px, the chip, pointer targets,
--   world waypoints, tips once, reduced motion, verbs through the atlas relay.
-- Part D: wiring (project, verify.luau, build scripts, relay, Settings).
-- Run from the project directory: lune run verify-tutorial.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local H = require("./tools/ui-harness")
local Vector3, CFrame, Vector2 = roblox.Vector3, roblox.CFrame, roblox.Vector2
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, { debugName = path, environment = env or {}, injectGlobals = true })()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", { script = nil })
P.useData(Data)
local TU, G = Data.Tutorial, Data.Features.Guide
local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(actual, expected, case)
	assert(actual == expected, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f)
			local c = { Connected = true }
			function c:Disconnect() self.Connected = false end
			table.insert(listeners, { f, c })
			return c
		end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end

------------------------------------------------------------------------------
-- Part A: pure rules
------------------------------------------------------------------------------
do
	-- The step cards follow the Wayfarer's Path order exactly (one per step).
	local stepIds = {}
	for _, c in ipairs(TU.Cards) do if c.step then table.insert(stepIds, c.step) end end
	local pathIds = {}
	for _, s in ipairs(G.Steps) do table.insert(pathIds, s.id) end
	eq(table.concat(stepIds, ","), table.concat(pathIds, ","), "step cards follow the Path order")
	eq(TU.Cards[1].id, "welcome", "the welcome card opens the tutorial")
	eq(TU.Cards[#TU.Cards].id, "complete", "the celebration card closes it")
	local quests = {}
	for _, c in ipairs(TU.Cards) do if c.quest then table.insert(quests, c.quest) end end
	eq(table.concat(quests, ","), "contract,SkywayCharter,LampsOfTheQuay", "the starter quest chain after the Path")
	for _, q in ipairs({ "SkywayCharter", "LampsOfTheQuay" }) do
		local def = Data.QuestById[q]
		ok(def ~= nil and def.region == "Hub" and def.giver ~= nil, q .. " is a Compass Quay regional quest with a giver")
	end
	ok(Data.QuestById.SkywayCharter.requires[1].kind == "contracts" and Data.QuestById.SkywayCharter.requires[1].count <= TU.CONTRACTS,
		"Charting the Skyway opens once the tutorial's contracts are done")
	for _, c in ipairs(TU.Cards) do
		ok(type(c.title) == "string" and #c.title >= 4 and #c.title <= 32, c.id .. " has a short title")
		ok(type(c.body) == "string" and #c.body >= 30 and #c.body <= 190, c.id .. " has a short instruction (" .. #c.body .. ")")
		ok(type(c.pointer) == "table", c.id .. " names its pointer targets")
		ok(TU.dots(c.id).total >= 1 and TU.dots(c.id).index >= 1, c.id .. " has a dot position")
	end
	eq(TU.dots("path:chop").index, 2, "chop is dot 2 of the Path chapter (journal mode first)")
	eq(TU.dots("path:chop").total, #G.Steps, "the Path chapter has one dot per step")
	eq(TU.dots("quest:SkywayCharter").index, 2, "second quest dot")
	-- Click-to-gather copy (Gathering team: left-click a tree / ore, no prompt to hold).
	ok(has(TU.CardById["path:chop"].body, "Left-click a tree") and has(TU.CardById["path:chop"].body, "axe"), "chop: left-click a tree with your axe")
	ok(has(TU.CardById["path:ore"].body, "Left-click an ore") and has(TU.CardById["path:ore"].body, "pickaxe"), "ore: left-click an ore rock with your pickaxe")
	for _, c in ipairs(TU.Cards) do ok(not has(c.body, "Hold the prompt") and not has(c.body, "press E"), c.id .. " never says hold a prompt") end
	-- World targets reuse the Path's Wayfinder waypoints.
	for _, s in ipairs(G.Steps) do eq(TU.specsFor("path:" .. s.id), G.Waypoints[s.id], s.id .. " uses the Path waypoint") end
	-- The current card from progress.
	local t = TU.sanitize(nil)
	eq(TU.current({}, t), "welcome", "a fresh journal starts on the welcome card")
	t.seen.welcome = true
	eq(TU.current({}, t), "path:mode", "then the first Path step")
	local guide = { done = {} }
	for i, s in ipairs(G.Steps) do
		eq(TU.current({ guide = guide }, t), "path:" .. s.id, "card " .. i .. " follows the Path step " .. s.id)
		guide.done[s.id] = true
	end
	-- Out of order progress: the first open step (the sidebar Objective) wins.
	eq(TU.current({ guide = { done = { mode = true, ore = true } } }, t), "path:chop", "the first open step wins")
	local pr = { guide = { complete = true }, questCompleted = 0, questsDone = {} }
	eq(TU.current(pr, t), "quest:contract", "after the Path: the guild contracts")
	pr.questCompleted = 1
	eq(TU.current(pr, t), "quest:contract", "both contracts")
	pr.questCompleted = 2
	eq(TU.current(pr, t), "quest:SkywayCharter", "then Charting the Skyway")
	pr.questsDone.SkywayCharter = true
	eq(TU.current(pr, t), "quest:LampsOfTheQuay", "then Lamps of the Quay")
	pr.questsDone.LampsOfTheQuay = true
	eq(TU.current(pr, t), "complete", "then the celebration")
	t.done = true
	eq(TU.current(pr, t), nil, "finished: no card")
	eq(TU.current({}, { seen = {}, skipped = true }), nil, "skipped: no card")
	eq(TU.current({}, { seen = {}, vet = true }), nil, "veteran: no card")
	-- Verb parsing (whitelist).
	local a, b = TU.parse("dismiss:path:chop")
	ok(a == "dismiss" and b == "path:chop", "dismiss a card")
	a, b = TU.parse("next:welcome")
	ok(a == "next" and b == "welcome", "next")
	a, b = TU.parse("tip:fight")
	ok(a == "tip" and b == "fight", "tip")
	a, b = TU.parse("tips:off")
	ok(a == "tips" and b == false, "tips off")
	ok(TU.parse("skip") == "skip" and TU.parse("replay") == "replay", "skip / replay")
	for _, bad in ipairs({ "", "dismiss:nope", "tip:nope", "next:", "skip:1", "tips:maybe", string.rep("x", 60), 5 }) do
		ok(TU.parse(bad) == nil, "refused: " .. tostring(bad))
	end
	-- Sanitising: junk is dropped, known ids kept.
	local s = TU.sanitize({ seen = { welcome = true, bogus = true, ["path:chop"] = "yes" }, tips = { fight = true, x = true }, card = "nope", skipped = 1, off = true })
	ok(s.seen.welcome and not s.seen.bogus and not s.seen["path:chop"], "seen keeps only real cards marked true")
	ok(s.tips.fight and not s.tips.x and s.card == nil and s.skipped == nil and s.off == true and s.v == TU.VERSION, "sanitised state")
	-- Tip detection.
	local function tips(prev, snap, ctx) return table.concat(TU.detectTips(prev, snap, ctx), ",") end
	eq(tips(nil, {}, {}), "", "nothing happened")
	eq(tips(nil, { announce = { list = { { kind = "collection" }, { kind = "skill", skill = "Mining" } } } }, {}), "levelup", "first level-up from the §31 ring")
	local items = {}
	for i = 1, TU.SATCHEL_PAGE do items["Item" .. i] = 1 end
	eq(tips(nil, { items = items }, {}), "satchelFull", "a full first satchel page")
	items.Item1 = 0
	eq(tips(nil, { items = items }, {}), "", "empty stacks do not count")
	eq(tips({ regionQuests = { accepted = {} } }, { regionQuests = { accepted = { SkywayCharter = true } } }, {}), "questAccept", "a quest accepted")
	eq(tips(nil, { regionQuests = { accepted = { SkywayCharter = true } } }, {}), "", "no quest tip on the first snapshot (rejoin)")
	eq(tips(nil, {}, { fight = true, night = true, shop = true }), "fight,night,shop", "server signals")
	-- Finale rewards summary.
	local lines = TU.rewardSummary()
	ok(has(lines[1], tostring(G.MAX_OWED)), "the summary names the Path coins")
	ok(has(table.concat(lines, "|"), "Charting the Skyway: 300 coins"), "and the quest rewards")
end
print("PASS: " .. checks .. " data assertions.")

------------------------------------------------------------------------------
-- Part B: server
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
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	return copy(data[key])
end
local RA = Data.RegionArt
local npcAt, models = {}, {}
local roles = { "Guide" }
for _, f in ipairs(RA.Folk) do table.insert(roles, f.role) end
for i, role in ipairs(roles) do
	npcAt[role] = Vector3.new(i * 100, 5, 0)
	local root = { Position = npcAt[role] }
	table.insert(models, { GetAttribute = function(_, k) return if k == "TownsfolkRole" then role else nil end,
		FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end })
end
local townsfolk = { GetChildren = function() return models end }
local QUAY = Vector3.new(0, 0, 0)
local quay = { GetAttribute = function(_, k) return if k == "IslandCenter" then QUAY elseif k == "IslandRadius" then 120 else nil end }
local islandsDouble = { FindFirstChild = function(_, name) return if name == "Compass Quay" then quay else nil end }
local storage = { AetherTrails = { Name = "AetherTrails" }, IsleTravelGate = { Invoke = function() return true end } }
local markers = { AetherData = { Name = "AetherData" }, AetherProgression = { Name = "AetherProgression" } }
local modules = { [markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua") }
local services = {
	Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end },
	ProximityPromptService = { PromptTriggered = signal() },
	ReplicatedStorage = { WaitForChild = function(_, name) return assert(markers[name], name) end },
	ServerStorage = { FindFirstChild = function(_, name) return storage[name] end },
	DataStoreService = { GetDataStore = function() return db end },
	HttpService = { GenerateGUID = function() return "tutorial-test" end },
	RunService = { IsStudio = function() return false end },
}
local serverObjects = {}
local env = {
	game = { GetService = function(_, name) return services[name] end, BindToClose = function() end },
	workspace = { GetAttribute = function(self, key) return rawget(self, key) end,
		FindFirstChild = function(_, name) return if name == "Islands" then islandsDouble elseif name == "Townsfolk" then townsfolk else nil end },
	Vector3 = Vector3, CFrame = CFrame,
	Instance = { new = function(className)
		local o = { ClassName = className, Event = signal(), FireClient = function(_, player, state) player.last = state end }
		function o:Destroy() self.Parent = nil end
		table.insert(serverObjects, o)
		return o
	end },
	UDim2 = roblox.UDim2, Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum,
	os = { clock = function() return clock end, time = function() return math.floor(utc) end },
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = { new = function() return { NextNumber = function() return 0.999 end, NextInteger = function(_, lo) return lo end } end },
	warn = function() end,
	task = {
		spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, { environment = env, injectGlobals = true })()
local liveById = {}
local function player(id)
	local humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end }
	local root = { Position = Vector3.new(0, 5000, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero }
	local p = { UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {} }
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = { Parent = true, FindFirstChild = function() return p.root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) p.root.Position = cf.Position end }
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

do
	-- B1. A brand-new journal: the welcome card; buttons never move a step card.
	local newbie = player(7001)
	local s = cmd(newbie, "state")
	ok(type(s.tutorial) == "table", "the snapshot carries tutorial state")
	eq(s.tutorial.card, "welcome", "a fresh journal opens on the welcome card")
	ok(s.tutorial.read == nil and s.tutorial.dots.chapter == "WELCOME", "unread, welcome chapter")
	local coins = s.coins
	s = cmd(newbie, "tutorial", "dismiss:path:mode")
	eq(s.tutorial.card, "welcome", "a stale / future card id changes nothing")
	s = cmd(newbie, "tutorial", "next:welcome")
	eq(s.tutorial.card, "path:mode", "Next on the welcome card opens the first Path step")
	eq(s.message, "", "tutorial taps are silent")
	eq(s.tutorial.dots.index, 1, "Path dot 1")
	ok(type(s.tutorial.next) == "table" and s.tutorial.next.specs == G.Waypoints.mode, "the step card carries the Path waypoint")
	s = cmd(newbie, "tutorial", "next:path:mode")
	eq(s.tutorial.card, "path:mode", "Next never advances a step card (only real progress does)")
	s = cmd(newbie, "tutorial", "dismiss:path:mode")
	ok(s.tutorial.card == "path:mode" and s.tutorial.read == true, "Got it marks the card read (collapsed), same card")
	-- Real progress: choosing a journal mode at Pell completes the Path step.
	at(newbie, "Guide")
	s = cmd(newbie, "guideMode", G.MODE_STANDARD)
	eq(s.tutorial.card, "path:chop", "server progress moves the card to Chop a log")
	ok(s.tutorial.read == nil, "the new card is unread (opens expanded)")
	eq(s.guide.id, "chop", "card and sidebar Objective agree")
	-- A log in the journal (however it was gathered: prompt today, left-click
	-- swings after the Gathering change) is server progress: the card moves on.
	eq(cmd(newbie, "state").coins, coins, "the tutorial verb never grants coins")
	leave(newbie)
	data["p7001"].profile.collection.Timber = 1
	newbie = player(7001)
	s = cmd(newbie, "state")
	eq(s.tutorial.card, "path:craft", "a log in the journal moves the card to Craft")
	ok(s.tutorial.read == nil, "Craft opens unread")
	local saved = stored(newbie)
	ok(saved.tutorial.v == TU.VERSION and saved.tutorial.seen.welcome and saved.tutorial.seen["path:mode"], "seen cards are saved")
	ok(type(saved.tutorial.card) == "string", "the current card is saved")
	-- B2. Rejoin resumes: same card, read state kept.
	newbie = player(7001)
	s = cmd(newbie, "state")
	eq(s.tutorial.card, saved.tutorial.card, "rejoin resumes the saved card")
	s = cmd(newbie, "tutorial", "dismiss:" .. s.tutorial.card)
	ok(s.tutorial.read == true, "read")
	saved = stored(newbie)
	newbie = player(7001)
	s = cmd(newbie, "state")
	ok(s.tutorial.read == true, "rejoin resumes a read card collapsed")
	-- B3. Tips once per account; tips off.
	s = cmd(newbie, "tutorial", "tip:fight")
	ok(table.find(s.tutorial.tips, "fight") ~= nil, "a shown tip is recorded")
	s = cmd(newbie, "tutorial", "tip:fight")
	local n = 0
	for _, id in ipairs(s.tutorial.tips) do if id == "fight" then n += 1 end end
	eq(n, 1, "recorded once")
	s = cmd(newbie, "tutorial", "tips:off")
	ok(s.tutorial.off == true and has(s.message, "tips off"), "tips off")
	s = cmd(newbie, "tutorial", "tip:levelup")
	ok(table.find(s.tutorial.tips, "levelup") == nil, "no tip is recorded while tips are off")
	s = cmd(newbie, "tutorial", "tips:on")
	ok(s.tutorial.off == nil, "tips back on")
	-- B4. Skip, persisted; replay brings it back from real progress.
	s = cmd(newbie, "tutorial", "skip")
	ok(s.tutorial.card == nil and s.tutorial.skipped == true and has(s.message, "Settings"), "skipped: no card, Settings named")
	saved = stored(newbie)
	newbie = player(7001)
	s = cmd(newbie, "state")
	ok(s.tutorial.card == nil and s.tutorial.skipped == true, "a skip survives a rejoin")
	s = cmd(newbie, "tutorial", "replay")
	ok(s.tutorial.card == "welcome" and s.tutorial.skipped == nil and #s.tutorial.tips == 0, "replay: welcome again, tips reset")
	s = cmd(newbie, "tutorial", "next:welcome")
	ok(s.tutorial.card ~= "path:mode" and string.sub(s.tutorial.card, 1, 5) == "path:", "replay resumes at the real progress (journal mode already chosen)")
	-- Validation.
	for _, bad in ipairs({ "dismiss:nope", "", "tip:zzz", "skip:now" }) do
		ok(has(cmd(newbie, "tutorial", bad).message, "isn't valid"), "refused: " .. bad)
	end
	leave(newbie)
end
do
	-- Tutorial taps alone never start a journal (Ironman stays possible) or pay anything.
	local fresh = player(7009)
	local c0 = cmd(fresh, "state").coins
	for _, arg in ipairs({ "next:welcome", "dismiss:path:mode", "tip:night", "tips:off", "tips:on", "skip", "replay" }) do cmd(fresh, "tutorial", arg) end
	local st = stored(fresh)
	ok(st.started ~= true and st.coins == c0, "tutorial verbs never set started or move coins")
	-- B5. Veterans (first load skips the Path) never see the tutorial or its tips.
	local vet = seeded(7002, function(pr)
		pr.tutorial, pr.guide, pr.renown = nil, nil, nil
		for _, skill in ipairs({ "Mining", "Woodcutting", "Combat", "Fishing" }) do pr.xp[skill] = Data.XP_TABLE[40] end
	end)
	local s = cmd(vet, "state")
	ok(s.guide.complete == true, "the veteran's Path is complete")
	ok(s.tutorial.card == nil and s.tutorial.vet == true and s.tutorial.off == true, "veteran: no card, no tips")
	s = cmd(vet, "tutorial", "next:welcome")
	eq(s.tutorial.card, nil, "a veteran's Next does nothing")
	-- Replay from Settings is the only way in (cards from real progress).
	s = cmd(vet, "tutorial", "replay")
	eq(s.tutorial.card, "welcome", "a veteran may replay")
	leave(vet)
	-- B6. Starter quests after the Path: contracts, then Charting the Skyway via the quest helper.
	local q = seeded(7003, function(pr)
		pr.tutorial = { v = TU.VERSION, seen = { welcome = true }, tips = {} }
		pr.guide = { done = {}, flags = {}, complete = true, owed = 120 }
		for _, st in ipairs(G.Steps) do pr.guide.done[st.id] = true end
		pr.questCompleted = 0
	end)
	s = cmd(q, "state")
	eq(s.tutorial.card, "quest:contract", "the first guild contracts")
	eq(s.tutorial.dots.chapter, "FIRST QUESTS", "quest chapter")
	ok(has(s.tutorial.next.text, "Ore") and s.tutorial.next.pinned == false, "NEXT reads the contract's helper step, not pinned yet")
	s = cmd(q, "helperPin", "contract")
	ok(s.tutorial.next.pinned == true, "pinning through the §33 helper is reflected")
	leave(q)
	q = seeded(7003, function(pr) pr.questCompleted = 2 end)
	s = cmd(q, "state")
	eq(s.tutorial.card, "quest:SkywayCharter", "two contracts: Charting the Skyway")
	ok(has(s.tutorial.next.text, "Ilsabet") and s.tutorial.next.status == "accept", "NEXT: accept it from Ilsabet")
	ok(type(s.tutorial.next.specs) == "table" and s.tutorial.next.specs[1] == "npc:WarpKeeper", "the helper's waypoint")
	-- Accepting the quest (real progress) moves the NEXT line.
	at(q, "WarpKeeper")
	local acc = cmd(q, "rqAccept", "SkywayCharter")
	if acc.regionQuests and acc.regionQuests.accepted and acc.regionQuests.accepted.SkywayCharter then
		ok(acc.tutorial.next.status == "active" and has(acc.tutorial.next.text, "Lamplighter") or has(acc.tutorial.next.text, "Corwin"), "accepted: NEXT moves on (" .. tostring(acc.tutorial.next.text) .. ")")
	end
	leave(q)
	q = seeded(7003, function(pr) pr.questsDone.SkywayCharter = true; pr.questsDone.LampsOfTheQuay = true end)
	s = cmd(q, "state")
	eq(s.tutorial.card, "complete", "both quests done: the celebration card")
	ok(s.tutorial.owed == 120 and #s.tutorial.rewards >= 3, "rewards summary and owed Path coins")
	s = cmd(q, "tutorial", "dismiss:complete")
	eq(s.tutorial.card, "complete", "Got it on the finale keeps it")
	s = cmd(q, "tutorial", "next:complete")
	ok(s.tutorial.card == nil and s.tutorial.done == true, "Finish ends the tutorial")
	local saved = stored(q)
	ok(saved.tutorial.done == true, "finished is saved")
end
print("PASS: " .. (checks - partB) .. " server assertions.")

------------------------------------------------------------------------------
-- Part C: client (tutorial.client.lua with the atlas and the satchel layer)
------------------------------------------------------------------------------
local partC = checks
local T = H.loadTheme({ Instance = { new = function(c) return H.new(c) end }, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
	Vector2 = Vector2, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint })
local function rect(o)
	local p, s = o.Position, o.Size
	return { x = p.X.Offset, y = p.Y.Offset, w = s.X.Offset, h = s.Y.Offset }
end
local function overlaps(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
local function show(r) return string.format("(%d,%d %dx%d)", r.x, r.y, r.w, r.h) end
local function tutSnap(card, extra)
	local snap = H.snapshot()
	-- Every tip already seen unless a test asks for tips (the harness satchel fills a page).
	local all = {}
	for _, t in ipairs(TU.Tips) do table.insert(all, t.id) end
	snap.tutorial = { card = card, dots = TU.dots(card), tips = all, next = { specs = TU.specsFor(card) } }
	for k, v in pairs(extra or {}) do snap.tutorial[k] = v end
	return snap
end
local function scene(size, touch, opts)
	opts = opts or {}
	local ui = H.runAtlas(size, { touch = touch })
	local layer = H.runHud(size, ui.player, ui.replicated, { touch = touch })
	local waypoints = {}
	local request = H.new("BindableEvent", { Name = "WayfinderRequest" })
	request.Parent = ui.player
	request.Event:Connect(function(specs, label) table.insert(waypoints, { specs = specs, label = label }) end)
	-- A stand-in hotbar (slots named as hotbar.client.lua names them).
	local bar = H.new("ScreenGui", { Name = "IsleHotbar" })
	bar.Parent = ui.playerGui
	local L = T.hudLayout(size.X, size.Y, { touch = touch })
	for i = 1, 9 do
		local slot = H.new("TextButton", { Name = "Slot" .. i, Position = roblox.UDim2.fromOffset(L.hotbar.x + (i - 1) * (L.hotbar.slot + 4), L.hotbar.y),
			Size = roblox.UDim2.fromOffset(L.hotbar.slot, L.hotbar.slot) })
		slot.Parent = bar
	end
	local delays = {}
	local tut = H.runTutorial(size, ui.player, ui.replicated, { touch = touch, delays = delays })
	return { ui = ui, layer = layer, tut = tut, S = tut.state, waypoints = waypoints, delays = delays, L = L }
end
local function sentVerbs(ui, verb)
	local out = {}
	for _, v in ipairs(ui.sent) do if v[1] == verb then table.insert(out, v[2] or "") end end
	return out
end

-- C1. Six screen sizes: lane, no overlap with the persistent HUD, touch targets.
for _, case in ipairs({ { 1366, 768, false }, { 844, 390, true }, { 730, 303, true }, { 1024, 768, true }, { 1366, 710, false }, { 1280, 650, false } }) do
	local size = Vector2.new(case[1], case[2])
	local touch = case[3]
	local tag = size.X .. "x" .. size.Y .. (if touch then " touch" else "")
	local sc = scene(size, touch)
	local S, L = sc.S, sc.L
	sc.ui.update.OnClientEvent:Fire(tutSnap("path:chop"))
	local card = sc.tut.gui:FindFirstChild("CoachCard")
	ok(card.Visible, "the coach card shows at " .. tag)
	eq(S.card, "path:chop", "card from the snapshot at " .. tag)
	ok(S.expanded == true, "a new unread card opens expanded at " .. tag)
	local r = rect(card)
	eq(show(r), show(L.coach), "the card fills its Theme.hudLayout coach lane at " .. tag)
	ok(r.x >= 0 and r.y >= 0 and r.x + r.w <= size.X and r.y + r.h <= size.Y, "card on screen at " .. tag)
	-- Never over the hotbar or the action bar, at any size.
	local hotbar = { x = L.hotbar.x, y = L.hotbar.y, w = L.hotbar.w, h = L.hotbar.h }
	ok(not overlaps(r, hotbar) and not overlaps(r, L.action) and r.y + r.h <= L.band.y, "card clear of the hotbar, its band and the action bar at " .. tag)
	-- The persistent HUD (and, docked, every lane) stays clear.
	local items = { { "sidebar", L.sidebar }, { "minimap block", L.mapBlock }, { "status orbs", L.orbs } }
	if not L.coach.modal then
		for _, extra in ipairs({ { "XP drops", L.xpDrops }, { "skill toast", L.xpToast }, { "pickup feed", L.pickupFeed }, { "level banner", L.levelBanner },
			{ "chat tabs", L.chatTabs }, { "action label", L.actionLabel } }) do table.insert(items, extra) end
		-- the §31 announcement toast (above the band, centred)
		local tw = math.max(200, math.min(360, L.lane.right - L.lane.left, L.w - 20))
		table.insert(items, { "announcement toast", { x = math.floor((L.w - tw) / 2), y = L.band.y - 64 - 54, w = tw, h = 54 } })
		table.insert(items, { "left column", { x = 10, y = L.leftTop, w = L.leftWidth, h = 176 } })
	end
	for _, item in ipairs(items) do
		local b = item[2]
		if b.w > 0 and b.h > 0 then ok(not overlaps(r, b), "card " .. show(r) .. " clear of " .. item[1] .. " " .. show(b) .. " at " .. tag) end
	end
	-- Buttons: 44 px targets inside the card.
	for _, name in ipairs({ "GotIt", "ShowMe", "SkipTutorial", "Collapse" }) do
		local b = H.find(card, name)
		ok(b ~= nil and b.Size.Y.Offset >= 44, name .. " is a 44 px target at " .. tag)
		if b.Visible ~= false and b.Size.X.Scale == 0 then ok(b.Size.X.Offset >= 44, name .. " is 44 px wide at " .. tag) end
	end
	local buttons = H.find(card, "Buttons")
	local width = H.find(card, "SkipTutorial").Size.X.Offset + 6 + H.find(card, "ShowMe").Size.X.Offset + 6 + H.find(card, "GotIt").Size.X.Offset
	ok(width <= r.w - 20, "the button row fits the card at " .. tag .. " (" .. width .. " in " .. (r.w - 20) .. ")")
	ok(buttons.Size.Y.Offset == 44, "button row height")
	-- The body has room for its text (≥ 3 lines).
	ok(H.find(card, "Instruction").Size.Y.Offset >= 3 * 15, "body room at " .. tag .. " (" .. tostring(H.find(card, "Instruction").Size) .. ")")
	-- Collapse: the chip.
	H.press(H.find(card, "Collapse"))
	ok(S.expanded == false, "collapse")
	local chip = rect(card)
	if card.Visible then
		eq(chip.h, 44, "the chip is 44 px tall at " .. tag)
		eq(chip.x .. "," .. chip.y, L.coachChip.x .. "," .. L.coachChip.y, "the chip sits in its lane at " .. tag)
		ok(not overlaps(chip, hotbar) and not overlaps(chip, L.action) and not overlaps(chip, L.sidebar) and not overlaps(chip, L.mapBlock), "chip clear of the persistent HUD at " .. tag)
	end
	-- Phones: the chip yields the left column to the lap / trap trackers.
	if L.short then
		H.agilityHud(sc.ui.player)
		sc.ui.update.OnClientEvent:Fire(tutSnap("path:chop"))
		local tracker = sc.ui.gui:FindFirstChild("CourseTracker")
		if tracker and tracker.Visible ~= false then
			S.render()
			ok(not card.Visible and S.mode == "yield", "the chip steps aside for the lap tracker at " .. tag)
		end
	end
	-- Docked satchel (desktop): the card never covers it.
	if not L.short then
		sc.layer.state.setOpen(true)
		sc.ui.player:SetAttribute("IsleSatchelOpen", true)
		S.expanded = true
		S.render()
		local L2 = T.hudLayout(size.X, size.Y, { touch = touch, satchelOpen = true })
		local cr = rect(card)
		eq(show(cr), show(L2.coach), "the card takes the satchel-open lane at " .. tag)
		if sc.layer.state.docked then
			local panel = sc.layer.state.panel
			local pr = { x = panel.Position.X.Offset, y = panel.Position.Y.Offset, w = panel.Size.X.Offset, h = panel.Size.Y.Offset }
			ok(not overlaps(cr, pr), "card " .. show(cr) .. " clear of the docked satchel " .. show(pr) .. " at " .. tag)
		end
		ok(not overlaps(cr, hotbar) and not overlaps(cr, L2.action), "satchel-open card clear of the hotbar / action bar at " .. tag)
	end
end
print("PASS: lanes at six sizes")

-- C2. Behaviour at 1366x768.
do
	local size = Vector2.new(1366, 768)
	local sc = scene(size, false)
	local S, ui = sc.S, sc.ui
	local card = sc.tut.gui:FindFirstChild("CoachCard")
	-- No tutorial state (older server / skipped): nothing shows.
	ui.update.OnClientEvent:Fire(H.snapshot())
	ok(not card.Visible and S.card == nil, "no tutorial state: no card")
	-- Welcome: Next goes through the atlas relay.
	ui.update.OnClientEvent:Fire(tutSnap("welcome", { next = nil }))
	ok(card.Visible and H.find(card, "GotIt").Text == "Next", "welcome: Next")
	ok(not H.find(card, "ShowMe").Visible, "welcome: no waypoint button")
	eq(S.pointerKey, "objective", "welcome points at the sidebar Objective")
	ok(sc.tut.pointer:FindFirstChild("PointerRing").Visible, "the pointer ring shows")
	H.press(H.find(card, "GotIt"))
	local sent = sentVerbs(ui, "tutorial")
	eq(sent[#sent], "next:welcome", "Next sends tutorial next:welcome through the relay")
	-- A step card: a waypoint is set once when it opens.
	ui.update.OnClientEvent:Fire(tutSnap("path:mode"))
	eq(#sc.waypoints, 1, "a new card lights its world target once")
	eq(table.concat(sc.waypoints[1].specs, ","), table.concat(G.Waypoints.mode, ","), "with the Path waypoint")
	ui.update.OnClientEvent:Fire(tutSnap("path:mode"))
	eq(#sc.waypoints, 1, "the same card does not re-set the waypoint")
	H.press(H.find(card, "ShowMe"))
	eq(#sc.waypoints, 2, "Show me sets it again")
	-- Got it collapses and tells the server; the card stays until progress moves it.
	H.press(H.find(card, "GotIt"))
	sent = sentVerbs(ui, "tutorial")
	eq(sent[#sent], "dismiss:path:mode", "Got it sends dismiss")
	ok(S.expanded == false and card.Visible and card.Size.Y.Offset == 44, "Got it collapses to the chip")
	ui.update.OnClientEvent:Fire(tutSnap("path:mode", { read = true }))
	ok(S.expanded == false and S.card == "path:mode", "the card does not advance on a button")
	-- Server progress: the next card opens.
	ui.update.OnClientEvent:Fire(tutSnap("path:chop"))
	ok(S.expanded and S.card == "path:chop", "server progress opens the next card")
	ok(has(H.find(card, "Instruction").Text, "Left-click a tree"), "click-to-chop copy")
	eq(S.pointerKey, "hotbar:2", "chop points at the context tool slot")
	eq(S.target.Name, "Slot2", "hotbar slot 2")
	-- Rejoin on a read card: collapsed.
	local sc2 = scene(size, false)
	sc2.ui.update.OnClientEvent:Fire(tutSnap("path:ore", { read = true }))
	ok(sc2.S.expanded == false and sc2.tut.gui:FindFirstChild("CoachCard").Visible, "a read card resumes collapsed")
	eq(#sc2.waypoints, 0, "a read card does not reset the waypoint on rejoin")
	-- The atlas covers the card; the pointer walks into it.
	ui.update.OnClientEvent:Fire(tutSnap("path:quest"))
	eq(S.pointerKey, "menu", "quest step: the Menu button while the atlas is closed")
	H.press(H.find(ui.gui, "AtlasButton"))
	ok(ui.atlas.Visible ~= false, "the atlas opened")
	S.render()
	S.placePointer()
	ok(not card.Visible and S.mode == "covered", "the open atlas hides the card")
	ok(S.pointerKey == "MenuQuests" or S.pointerKey == "SectionHelper", "the pointer moves into the atlas (" .. tostring(S.pointerKey) .. ")")
	ui.atlas.Visible = false
	S.render()
	ok(card.Visible, "the card returns when the atlas closes")
	-- Skip needs a confirming second tap.
	local skip = H.find(card, "SkipTutorial")
	local before = #sentVerbs(ui, "tutorial")
	H.press(skip)
	eq(#sentVerbs(ui, "tutorial"), before, "the first Skip tap only arms")
	ok(skip.Text == "Confirm skip", "armed text")
	H.press(skip)
	sent = sentVerbs(ui, "tutorial")
	eq(sent[#sent], "skip", "the second tap skips")
	-- Quest card: Pin it through §33, then Show me with the helper's specs.
	ui.update.OnClientEvent:Fire(tutSnap("quest:SkywayCharter", { next = { text = "Accept the quest from Ilsabet Vanewright", specs = { "npc:WarpKeeper" }, status = "accept", pinned = false } }))
	ok(has(H.find(card, "NextStep").Text, "Accept the quest from Ilsabet") and H.find(card, "NextStep").Visible, "quest card NEXT line")
	eq(H.find(card, "ShowMe").Text, "Pin it", "not pinned: Pin it")
	H.press(H.find(card, "ShowMe"))
	local pins = sentVerbs(ui, "helperPin")
	eq(pins[#pins], "quest:SkywayCharter", "Pin it uses the §33 helperPin verb")
	ui.update.OnClientEvent:Fire(tutSnap("quest:SkywayCharter", { next = { text = "Accept the quest from Ilsabet Vanewright", specs = { "npc:WarpKeeper" }, status = "accept", pinned = true } }))
	eq(H.find(card, "ShowMe").Text, "Show me", "pinned: Show me")
	local n = #sc.waypoints
	H.press(H.find(card, "ShowMe"))
	ok(#sc.waypoints == n + 1 and sc.waypoints[#sc.waypoints].specs[1] == "npc:WarpKeeper", "Show me uses the helper step's waypoint")
	-- Finale: rewards and the claim.
	ui.update.OnClientEvent:Fire(tutSnap("complete", { owed = 250, rewards = TU.rewardSummary(), next = nil }))
	ok(has(H.find(card, "Instruction").Text, "Charting the Skyway") and H.find(card, "GotIt").Text == "Finish", "celebration card with the rewards summary")
	eq(H.find(card, "ShowMe").Text, "Claim 250 coins", "owed coins can be claimed")
	H.press(H.find(card, "ShowMe"))
	ok(#sentVerbs(ui, "guideClaim") >= 1, "claim through guideClaim (" .. tostring((ui.sent[#ui.sent] or {})[1]) .. "/" .. tostring((S.sent[#S.sent] or {})[1]) .. ")")
	ok(not H.find(card, "SkipTutorial").Visible, "no Skip on the finale")
	H.press(H.find(card, "GotIt"))
	sent = sentVerbs(ui, "tutorial")
	eq(sent[#sent], "next:complete", "Finish")
end
-- C3. Tips: once per account, off, veterans; reduced motion.
do
	local size = Vector2.new(1366, 768)
	local sc = scene(size, false)
	local S, ui = sc.S, sc.ui
	local card = sc.tut.gui:FindFirstChild("CoachCard")
	local snap = tutSnap("path:kill", { tips = { "satchelFull" } })
	snap.announce = { seq = 3, list = { { seq = 3, kind = "skill", skill = "Mining", level = 2, coins = 5 } } }
	ui.update.OnClientEvent:Fire(snap)
	eq(S.tip, "levelup", "a first level-up shows its tip")
	ok(card.Visible and H.find(card, "Chapter").Text == "TIP" and H.find(card, "Title").Text == TU.TipById.levelup.title, "the tip borrows the card")
	local tips = sentVerbs(ui, "tutorial")
	eq(tips[#tips], "tip:levelup", "the shown tip is recorded on the server")
	H.press(H.find(card, "GotIt"))
	ok(S.tip == nil and H.find(card, "Title").Text == TU.CardById["path:kill"].title, "Got it returns to the coach card")
	ui.update.OnClientEvent:Fire(snap)
	eq(S.tip, nil, "the same tip never shows twice in a session")
	-- Once per account: a tip the server lists is never shown.
	local sc2 = scene(size, false)
	local snap2 = tutSnap("path:kill", { tips = { "levelup", "satchelFull" } })
	snap2.announce = snap.announce
	sc2.ui.update.OnClientEvent:Fire(snap2)
	eq(sc2.S.tip, nil, "a tip seen on another session never shows again")
	-- First fight from the combat hit signal.
	local fx = H.new("RemoteEvent", { Name = "IsleCombatFx" })
	fx.Parent = sc2.ui.replicated
	local sc3 = scene(size, false)
	local fx3 = H.new("RemoteEvent", { Name = "IsleCombatFx" })
	fx3.Parent = sc3.ui.replicated
	local sc4 = scene(size, false)
	sc4.ui.update.OnClientEvent:Fire(tutSnap("path:kill"))
	local prev = tutSnap("path:kill", { tips = { "satchelFull" } })
	prev.kills = 0
	local nextSnap = tutSnap("path:kill", { tips = { "satchelFull" } })
	nextSnap.kills = 1
	local sc5 = scene(size, false)
	sc5.ui.update.OnClientEvent:Fire(prev)
	sc5.ui.update.OnClientEvent:Fire(nextSnap)
	eq(sc5.S.tip, "fight", "a first kill raises the fight tip (snapshot fallback)")
	-- Tips off / veterans: nothing.
	local sc6 = scene(size, false)
	local off = tutSnap("path:kill", { off = true, tips = {} })
	off.announce = snap.announce
	sc6.ui.update.OnClientEvent:Fire(off)
	eq(sc6.S.tip, nil, "tips off: no tip")
	local sc7 = scene(size, false)
	local vet = H.snapshot()
	vet.tutorial = { tips = {}, vet = true, off = true }
	vet.announce = snap.announce
	sc7.ui.update.OnClientEvent:Fire(vet)
	ok(sc7.S.tip == nil and not sc7.tut.gui:FindFirstChild("CoachCard").Visible, "a veteran sees neither cards nor tips")
	-- Tips off from the tip itself.
	local sc8 = scene(size, false)
	sc8.ui.update.OnClientEvent:Fire(snap)
	H.press(H.find(sc8.tut.gui:FindFirstChild("CoachCard"), "ShowMe"))
	local s8 = sentVerbs(sc8.ui, "tutorial")
	eq(s8[#s8], "tips:off", "Tips off on a tip card")
	-- Reduced motion: the pointer ring does not pulse.
	local sc9 = scene(size, false)
	sc9.ui.player:SetAttribute("IsleSettingReducedMotion", true)
	sc9.ui.update.OnClientEvent:Fire(tutSnap("welcome"))
	local ringStroke = sc9.tut.pointer:FindFirstChild("PointerRing"):FindFirstChild("Pulse")
	ok(sc9.tut.pointer:FindFirstChild("PointerRing").Visible and ringStroke.Transparency == 0.1 and ringStroke.Thickness == 3, "reduced motion: a still ring")
	local sc10 = scene(size, false)
	sc10.ui.update.OnClientEvent:Fire(tutSnap("welcome"))
	local pulse = sc10.tut.pointer:FindFirstChild("PointerRing"):FindFirstChild("Pulse")
	ok(pulse.Transparency ~= 0.1 or pulse.Thickness ~= 3, "otherwise the ring pulses (tween applied)")
end
-- C3b. Night (isle clock from the snapshot's server time), shop (a priced
-- dialogue offer) and the 10 Hz / 1 Hz ticks.
do
	local size = Vector2.new(1366, 768)
	local t = 1700000000
	local function nightAt(x) local c = T.isleClock(x, Data); return c and c.night end
	while not nightAt(t) do t += 300 end
	local sc = scene(size, false)
	local snap = tutSnap("path:sell", { tips = { "satchelFull" } })
	snap.events = { serverTime = t, claims = {} }
	sc.ui.update.OnClientEvent:Fire(snap)
	eq(sc.S.tip, "night", "the first night shows its tip")
	ok(sc.S.pointerKey == "clock", "pointing at the sidebar clock")
	for _ = 1, 12 do sc.tut.run.Heartbeat:Fire(0.1) end
	H.press(H.find(sc.tut.gui:FindFirstChild("CoachCard"), "GotIt"))
	-- A shop: a townsfolk dialogue with a priced offer, seen by the 1 Hz tick.
	local folk = H.new("ScreenGui", { Name = "TownsfolkDialogue" })
	folk.Parent = sc.ui.playerGui
	local box = H.new("Frame", { Name = "Dialogue", Visible = true })
	box.Parent = folk
	local offer = H.new("TextButton", { Name = "Offer", Text = "Tonic x1, 12 coins" })
	offer.Parent = box
	sc.tut.run.Heartbeat:Fire(1.1)
	eq(sc.S.tip, "shop", "a priced dialogue offer shows the shop tip")
	ok(sc.S.mode == "covered" and not sc.tut.gui:FindFirstChild("CoachCard").Visible, "the dialogue hides the card while it is open")
	box.Visible = false
	sc.tut.run.Heartbeat:Fire(0.2)
	ok(sc.tut.gui:FindFirstChild("CoachCard").Visible, "and it returns when the dialogue closes")
	ok(sc.ui.replicated:FindFirstChild("IsleTutorialLocal") ~= nil, "the IsleTutorialLocal channel exists for other scripts")
end
-- C4. Settings › Tutorial: tips toggle and replay through the relay.
do
	local ui = H.runAtlas(Vector2.new(1366, 768), {})
	local snap = H.snapshot()
	snap.tutorial = { card = "path:ore", tips = {}, dots = TU.dots("path:ore") }
	ui.setSnapshot(snap)
	ui.update.OnClientEvent:Fire(snap)
	H.press(H.find(ui.gui, "AtlasButton"))
	H.press(H.find(ui.scroll, "MenuSettings"))
	local tips = H.find(ui.scroll, "TutorialTips")
	ok(tips ~= nil and has(tips.Text, "Turn tips off"), "Settings › Tutorial: tips toggle")
	H.press(tips)
	H.press(H.find(ui.scroll, "TutorialReplay"))
	local verbs = sentVerbs(ui, "tutorial")
	ok(table.find(verbs, "tips:off") and table.find(verbs, "replay"), "tips off and replay sent")
end
print("PASS: " .. (checks - partC) .. " client assertions.")

------------------------------------------------------------------------------
-- Part D: wiring
------------------------------------------------------------------------------
do
	local project = fs.readFile("default.project.json")
	ok(has(project, '"IsleTutorial": { "$path": "tutorial.client.lua" }'), "project registers IsleTutorial")
	ok(has(fs.readFile("verify.luau"), 'IsleTutorial = "tutorial.client.lua"'), "verify.luau binds it")
	ok(has(fs.readFile("scripts/build.sh"), "verify-tutorial.luau"), "build.sh runs this suite")
	ok(has(fs.readFile("build.ps1"), "'verify-tutorial.luau'"), "build.ps1 runs this suite")
	local ui = fs.readFile("ui.client.lua")
	ok(has(ui, "tutorial=true, -- §43"), "the atlas relays the tutorial verb")
	local server = fs.readFile("server.server.lua")
	ok(has(server, "-- >>> Tutorial (§43) >>>") and has(server, "-- <<< END Tutorial <<<"), "server block delimited")
	ok(has(server, "Tutorial.migrate(profile)") and has(server, "Tutorial.refresh(player,p)") and has(server, "tutorial=Tutorial.state"), "server hooks")
	local client = fs.readFile("tutorial.client.lua")
	ok(has(client, "--!strict"), "strict client")
	-- No second onboarding system: the client never decides progress.
	ok(not has(client, "guideTalk") and not has(client, "guideMode"), "the client never drives Path verbs")
end
print("PASS: wiring")
print("Tutorial QA passed " .. checks .. " checks.")
print("SUITE-END verify-tutorial.luau")
