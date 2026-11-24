-- Events QA: Skyward Calendar math, event windows and effects (pure Data rules),
-- the festival notice board publishing the calendar and running the ballot, the
-- production server consuming that state end to end (yield/XP multipliers, event
-- drops, persisted once-per-vigil gifts, Festival Vendor exchange) and the
-- Journal → Calendar atlas section.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local checks = 0
local function ok(cond, case)
	assert(cond, case)
	checks += 1
end
local function eq(actual, expected, case)
	assert(actual == expected, case .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function loadModule(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, { debugName = path, environment = env or {}, injectGlobals = true })()
end
local Data = loadModule("shared/GameData.lua")
local Progression = loadModule("shared/Progression.lua", { script = nil })
Progression.useData(Data)
local Cal = Data.Calendar

------------------------------------------------------------------------------
-- 1. Calendar constants and deterministic date math.
------------------------------------------------------------------------------
eq(Cal.daysPerYear, 48, "4 seasons x 12 days")
eq(Cal.yearLength, 439200, "year length in seconds")
ok(Cal.yearLength / 86400 > 4.9 and Cal.yearLength / 86400 < 5.2, "an isle year lasts about five real days")
ok(Cal.yearLength % 86400 ~= 0, "years drift across wall-clock hours (events visit every time zone)")
eq(#Cal.seasons, 4, "four seasons")
local seasonNames = { "Bloomtide", "Sunreach", "Emberfall", "Frostveil" }
for i, name in ipairs(seasonNames) do
	eq(Cal.seasons[i].id, name, "season order " .. i)
	ok(Data.Skills[Cal.seasons[i].skill] ~= nil and Data.ResourceTiers[Cal.seasons[i].skill] ~= nil, name .. " boosts a gathering skill")
end
local first = Data.calendarAt(Cal.epoch)
eq(first.year, 1, "epoch is Year 1")
eq(first.season, "Bloomtide", "epoch is Bloomtide")
eq(first.day, 1, "epoch is day 1")
eq(first.dayOfYear, 1, "epoch is day 1 of the year")
local before = Data.calendarAt(Cal.epoch - 1)
eq(before.year, 0, "one second before the epoch is Year 0")
eq(before.season, "Frostveil", "pre-epoch dates stay valid (Frostveil)")
eq(before.day, 12, "pre-epoch last day")
eq(before.dayEnds, Cal.epoch, "pre-epoch day ends at the epoch")
-- Walk two whole years day by day: every dawn and every last second agree.
local base = Data.calendarAt(1800000000).yearStart
eq((base - Cal.epoch) % Cal.yearLength, 0, "year starts align to the epoch grid")
for d = 0, 2 * Cal.daysPerYear - 1 do
	local dawn = base + d * Cal.dayLength
	local c, last = Data.calendarAt(dawn), Data.calendarAt(dawn + Cal.dayLength - 1)
	local dayOfYear = d % Cal.daysPerYear
	assert(c.dayStart == dawn and last.dayStart == dawn, "day start " .. d)
	assert(c.dayOfYear == dayOfYear + 1 and c.day == dayOfYear % 12 + 1, "day numbering " .. d)
	assert(c.season == seasonNames[dayOfYear // 12 + 1] and last.season == c.season, "season " .. d)
	assert(c.year == Data.calendarAt(base).year + d // Cal.daysPerYear, "year " .. d)
	checks += 4
end
-- Year rollover.
local lastSecond = Data.calendarAt(base + Cal.yearLength - 1)
local newYear = Data.calendarAt(base + Cal.yearLength)
eq(lastSecond.season .. lastSecond.day, "Frostveil12", "last second of the year")
eq(newYear.season .. newYear.day, "Bloomtide1", "first second of the next year")
eq(newYear.year, lastSecond.year + 1, "year increments at rollover")
eq(lastSecond.yearEnds, newYear.yearStart, "year end meets next year start")
eq(Data.calendarAt(base + Cal.yearLength * 7 + 5).year, Data.calendarAt(base).year + 7, "years advance one per year length")
-- DST agnostic: UTC seconds only. Across the 2026 US/EU DST changes, an hour later is
-- exactly 3600 calendar seconds later.
for _, t in ipairs({ 1772935200, 1774746000, 1793502000, 1792371600 }) do
	local a, b = Data.calendarAt(t), Data.calendarAt(t + 3600)
	eq((b.dayOfYear - a.dayOfYear) * Cal.dayLength + (t + 3600 - b.dayStart) - (t - a.dayStart) + (b.year - a.year) * Cal.yearLength, 3600, "uniform hour at " .. t)
end
eq(Data.calendarAt(1800000000.9).dayStart, Data.calendarAt(1800000000).dayStart, "fractional seconds floor")
eq(Data.calendarAt("x").year, Data.calendarAt(0).year, "non-numeric time treated as 0")

------------------------------------------------------------------------------
-- 2. Event windows.
------------------------------------------------------------------------------
local windows = Data.eventWindows(base)
eq(#windows, 13, "13 event windows per isle year")
local byId, seen = {}, {}
for i, w in ipairs(windows) do
	local ev = Data.Events[w.id]
	byId[w.id] = byId[w.id] or {}
	table.insert(byId[w.id], w)
	ok(w.ends - w.starts >= 20 * 60 and w.ends - w.starts <= 60 * 60, w.key .. " lasts 20-60 minutes")
	local c = Data.calendarAt(w.starts)
	eq(c.season, ev.season, w.key .. " falls in its season")
	ok(w.ends <= c.dayEnds, w.key .. " fits inside its isle day")
	ok(i == 1 or windows[i - 1].ends <= w.starts, w.key .. " does not overlap the previous window")
	ok(not seen[w.key], w.key .. " key is unique")
	seen[w.key] = true
	eq(c.event, w.id, w.key .. " active at its first second")
	eq(Data.calendarAt(w.ends - 1).eventKey, w.key, w.key .. " active at its last second")
	ok(Data.calendarAt(w.ends).event == nil, w.key .. " over at its end")
	ok(Data.calendarAt(w.starts - 1).event == nil, w.key .. " not yet active a second before")
	eq(Data.calendarAt(w.starts + 1).eventEnds, w.ends, w.key .. " reports its end")
end
for _, id in ipairs(Data.EventOrder) do ok(byId[id] and #byId[id] >= 2, id .. " recurs several times a year") end
eq(#byId.StarfallVigil, 4, "four Starfall vigils each winter")
-- Upcoming events cross the year boundary.
local finalWindow = windows[#windows]
local after = Data.upcomingEvents(finalWindow.ends, 3)
eq(#after, 3, "three upcoming windows")
eq(after[1].starts, Data.eventWindows(base + Cal.yearLength)[1].starts, "next year's first event follows the last")
eq(after[1].id, "BloomtideFair", "the year opens with the Bloomtide Fair")
eq(Data.upcomingEvents(finalWindow.starts + 5, 1)[1].key, finalWindow.key, "the live window is listed first")
eq(Data.calendarAt(windows[1].starts).year, Data.calendarAt(base).year, "windows belong to their year")

------------------------------------------------------------------------------
-- 3. Event state from published attributes.
------------------------------------------------------------------------------
local function source(attrs) return { GetAttribute = function(_, key) return attrs[key] end } end
local fair, surge, glimmer, hollow = byId.BloomtideFair[1], byId.DeepveinSurge[1], byId.GlimmertideFestival[1], byId.HollowNight[1]
local vigil1, vigil2 = byId.StarfallVigil[1], byId.StarfallVigil[2]
local function attrsAt(t, extra)
	local c = Data.calendarAt(t)
	local out = { AetherSeason = c.season, AetherDay = c.day, AetherEvent = c.event, AetherEventEnds = c.eventEnds, AetherEventKey = c.eventKey }
	for k, v in pairs(extra or {}) do out[k] = v end
	return out
end
local s = Data.eventState(source(attrsAt(fair.starts + 9, { FestivalResource = "Herb" })), fair.starts + 9)
eq(s.event, "BloomtideFair", "matching attributes publish the event")
eq(s.season, "Bloomtide", "matching season")
eq(s.featured, "Herb", "ballot choice is the featured crop")
eq(s.key, fair.key, "occurrence key")
eq(s.ends, fair.ends, "occurrence end")
s = Data.eventState(source(attrsAt(fair.starts + 9, { AetherEventKey = "BloomtideFair:" .. (fair.starts + 60) })), fair.starts + 9)
eq(s.event, nil, "a forged/stale end time grants nothing")
s = Data.eventState(source(attrsAt(fair.starts + 9)), fair.ends + 1)
eq(s.event, nil, "attributes left over after the window grant nothing")
eq(Data.eventState(source({}), fair.starts + 9).event, nil, "no publication, no event")
eq(Data.eventState(source({}), fair.starts + 9).season, nil, "no publication, no season")
eq(Data.eventState({}, fair.starts).event, nil, "a source without GetAttribute is tolerated")

------------------------------------------------------------------------------
-- 4. Gathering, kill drops and actions (pure rules).
------------------------------------------------------------------------------
local function rolls(list)
	local i = 0
	return function() i += 1; return list[i] or 0.999 end
end
local none = Data.eventGather("Herb", {}, rolls({}))
eq(none.bonus + none.mult + none.xpMult, 2, "no state: no bonus, x1, x1")
local fairState = { event = "BloomtideFair", season = "Bloomtide", featured = "Herb" }
local g = Data.eventGather("Herb", fairState, rolls({ 0.5 }))
eq(g.bonus, 1, "fair: crop +1, no season proc at 0.5")
eq(g.mult, 2, "fair: featured crop doubles")
g = Data.eventGather("Sunwheat", fairState, rolls({ 0.1 }))
eq(g.bonus, 2, "fair crop +1 and season proc +1")
eq(g.mult, 1, "non-featured crop is not doubled")
g = Data.eventGather("Ore", fairState, rolls({ 0.0 }))
eq(g.bonus + g.mult + g.xpMult, 2, "fair and Bloomtide leave ore alone")
g = Data.eventGather("Ore", { event = "DeepveinSurge", season = "Emberfall" }, rolls({}))
eq(g.xpMult, 2, "surge doubles Mining XP")
eq(g.bonus, 0, "surge adds no yield")
eq(Data.eventGather("Timber", { event = "DeepveinSurge" }, rolls({})).xpMult, 1, "surge is Mining only")
g = Data.eventGather("Fish", { event = "GlimmertideFestival", season = "Sunreach" }, rolls({ 0.9, 0.1 }))
eq(g.bonus, 1, "festival +1 fish")
eq(g.extra.SunscaleCarp, 1, "festival-only fish at roll 0.1")
g = Data.eventGather("Glassfin", { event = "GlimmertideFestival" }, rolls({ 0.3 }))
eq(g.extra.SunscaleCarp, nil, "no carp at roll 0.3")
eq(Data.eventGather("NotAResource", fairState, rolls({})).bonus, 0, "unknown items ignored")
eq(Data.eventGather("Herb", nil, rolls({})).bonus, 0, "nil state ignored")
eq(Data.eventKillDrops("BramblebackBoar", { event = "HollowNight" }, rolls({ 0.2 })).GloamCandyOrb, 1, "Hollow Night candy")
eq(Data.eventKillDrops("StarbornSentinel", { event = "HollowNight" }, rolls({ 0.2 })).GloamCandyOrb, 4, "stronger foes drop more candy")
eq(next(Data.eventKillDrops("BramblebackBoar", { event = "HollowNight" }, rolls({ 0.6 }))), nil, "failed roll drops nothing")
eq(next(Data.eventKillDrops("BramblebackBoar", { event = "StarfallVigil" }, rolls({ 0.0 }))), nil, "candy only on Hollow Night")
eq(next(Data.eventKillDrops("Ghost", { event = "HollowNight" }, rolls({ 0.0 }))), nil, "unknown monster")
-- Items and vendor data.
for _, id in ipairs({ "SunscaleCarp", "GloamCandyOrb", "StarfallShard", "StarfallCocoa", "TidebloomCharm", "GloamlightLantern", "FrostveilLocket" }) do
	ok(Data.Items[id] ~= nil and type(Data.Items[id].description) == "string", id .. " defined")
end
local Catalog = loadModule("art/PropCatalog.lua")
for _, offer in ipairs(Data.EventVendor) do
	eq(Data.EventVendorById[offer.id], offer, offer.id .. " indexed")
	for id, n in pairs(offer.reward) do ok(Data.Items[id] and n > 0, offer.id .. " reward " .. id) ok(Catalog.iconShape(Data.Items[id]) ~= nil, id .. " has an icon shape") end
	for id, n in pairs(offer.costs) do ok(Data.Items[id] and n > 0, offer.id .. " cost " .. id) end
end
for _, id in ipairs(Data.EventOrder) do
	local ev = Data.Events[id]
	ok(Data.SeasonById[ev.season] ~= nil and type(ev.text) == "string" and #ev.days > 0, id .. " well formed")
	ok(ev.at + ev.duration <= Cal.dayLength, id .. " window fits a day")
end
-- Gift and trade rules.
local function profile() return { items = {}, collection = {} } end
local function grant(p, id, n) p.items[id] = (p.items[id] or 0) + n end
local vigilState = { event = "StarfallVigil", key = vigil1.key, ends = vigil1.ends }
local p = profile()
eq(has(Data.eventAction(p, "eventGift", nil, vigilState, vigil1.starts + 5, grant, false), "Starfall gift opened"), true, "gift claim")
eq(p.items.StarfallShard, 3, "gift shards")
eq(p.items.StarfallCocoa, 1, "gift cocoa")
eq(has(Data.eventAction(p, "eventGift", nil, vigilState, vigil1.starts + 6, grant, false), "already"), true, "second claim refused")
eq(p.items.StarfallShard, 3, "no double gift")
eq(has(Data.eventAction(p, "eventGift", nil, vigilState, vigil1.ends, grant, false), "No Starfall gift"), true, "gift refused at the window end")
eq(has(Data.eventAction(p, "eventGift", nil, { event = "HollowNight", key = hollow.key, ends = hollow.ends }, hollow.starts, grant, false), "No Starfall"), true, "other events have no gift")
eq(has(Data.eventAction(p, "eventGift", nil, {}, vigil1.starts, grant, false), "No Starfall"), true, "no event, no gift")
eq(p.eventClaims[vigil1.key], nil, "claims prune once their vigil ended")
eq(has(Data.eventAction(p, "eventGift", nil, { event = "StarfallVigil", key = vigil2.key, ends = vigil2.ends }, vigil2.starts, grant, false), "opened"), true, "next vigil claimable")
eq(p.items.StarfallShard, 6, "second vigil gift")
p.eventClaims.Junk = "x"
Data.eventAction(p, "eventTrade", "Nope", {}, vigil2.starts + 1, grant, true)
eq(p.eventClaims.Junk, nil, "malformed claims pruned")
eq(p.eventClaims[vigil2.key], vigil2.ends, "live claim kept")
eq(has(Data.eventAction(p, "eventTrade", "Nope", {}, 0, grant, true), "does not stock"), true, "unknown offer")
eq(has(Data.eventAction(p, "eventTrade", nil, {}, 0, grant, true), "does not stock"), true, "missing offer")
eq(has(Data.eventAction(p, "eventTrade", "StarfallCocoa", {}, 0, grant, false), "Visit the Festival Vendor"), true, "trading needs a vendor visit")
eq(p.items.StarfallShard, 6, "refused trade spends nothing")
eq(has(Data.eventAction(p, "eventTrade", "StarfallCocoa", {}, 0, grant, true), "Traded"), true, "cocoa trade")
eq(p.items.StarfallShard, 4, "cocoa costs 2 shards")
eq(p.items.StarfallCocoa, 3, "cocoa delivered")
eq(has(Data.eventAction(p, "eventTrade", "FrostveilLocket", {}, 0, grant, true), "You need"), true, "insufficient currencies")
eq(p.items.StarfallShard, 4, "insufficient trade spends nothing")
p.items.GloamCandyOrb, p.items.StarfallShard = 30, 10
eq(has(Data.eventAction(p, "eventTrade", "FrostveilLocket", {}, 0, grant, true), "Traded"), true, "multi-currency trade")
eq(p.items.GloamCandyOrb + p.items.StarfallShard, 0, "both currencies spent exactly")
eq(p.items.FrostveilLocket, 1, "locket delivered")
p.items.GloamCandyOrb, p.items.StarfallShard = 30, 10
eq(has(Data.eventAction(p, "eventTrade", "FrostveilLocket", {}, 0, grant, true), "already own"), true, "unique keepsake once while owned")
eq(p.items.GloamCandyOrb, 30, "unique refusal spends nothing")
eq(has(Data.eventAction(p, "eventGift", nil, nil, 0, grant, false), "No Starfall"), true, "nil state")
eq(has(Data.eventAction(p, "bogus", nil, {}, 0, grant, false), "Unknown"), true, "unknown verb")

------------------------------------------------------------------------------
-- 5. Festival board + production server, end to end on one workspace.
------------------------------------------------------------------------------
local utc, clock = fair.starts + 10, 10
local function signal()
	local listeners = {}
	return { Connect = function(_, f) table.insert(listeners, f) end, Fire = function(_, ...) for _, f in listeners do f(...) end end }
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
local world = roblox.Instance.new("Workspace")
local gate = roblox.Instance.new("Part")
gate.Name = "ExpeditionGate"
gate.CFrame = roblox.CFrame.new(0, 10, 0)
gate.Parent = world
local festivalPlayers = { PlayerRemoving = signal() }
local dataMarker = { Name = "AetherData" }
local festival = coroutine.create(luau.load(fs.readFile("festival.server.lua"), { debugName = "festival.server.lua", environment = {
	game = { GetService = function(_, name)
		if name == "Players" then return festivalPlayers end
		return { WaitForChild = function(_, child) return if child == "AetherData" then dataMarker else nil end }
	end },
	require = function(target) assert(target == dataMarker, "festival requires only AetherData") return Data end,
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, Color3 = roblox.Color3,
	UDim2 = roblox.UDim2, UDim = roblox.UDim, Font = roblox.Font, Enum = roblox.Enum, os = { time = function() return utc end },
	task = { wait = function() coroutine.yield() end },
}, injectGlobals = true }))
local function tick(n)
	for _ = 1, n or 1 do
		local okResume, problem = coroutine.resume(festival)
		assert(okResume, problem)
	end
end
tick()
local board = world:FindFirstChild("Island Assembly")
ok(board ~= nil, "notice board built")
local surface = board:FindFirstChildOfClass("BillboardGui")
-- §28 QC M2: a floating camera-facing notice on an invisible anchor, no post.
ok(surface ~= nil and surface.Name == "NoticeBillboard" and not surface.AlwaysOnTop and surface.Size.X.Scale > 0 and surface.Size.Y.Scale > 0,
	"floating camera-facing notice sized in studs")
ok(board:FindFirstChildOfClass("SurfaceGui") == nil and board.Transparency == 1 and not board.CanCollide, "notice anchor is invisible and never blocks")
ok(world:FindFirstChild("Notice Post") == nil, "the notice post is gone")
for _, d in ipairs(surface:GetDescendants()) do
	if d:IsA("TextLabel") then ok(d.TextScaled and d:FindFirstChildOfClass("UITextSizeConstraint") ~= nil, d.Name .. " scales with the notice") end
end
local function attr(key) return world:GetAttribute(key) end
local cal = Data.calendarAt(utc)
eq(attr("AetherSeason"), "Bloomtide", "season published")
eq(attr("AetherDay"), cal.day, "day published")
eq(attr("AetherYear"), cal.year, "year published")
eq(attr("AetherEvent"), "BloomtideFair", "event published")
ok(math.abs(attr("AetherEventEnds") - fair.ends) <= 128, "event end published (Lune stores attributes as float32)")
eq(attr("AetherEventKey"), fair.key, "event occurrence key published exactly")
eq(attr("AetherNextEvent"), Data.upcomingEvents(utc, 2)[2].id, "next event published")
ok(has(surface:FindFirstChild("Event").Text, "BLOOMTIDE FAIR"), "board shows the live event")
ok(has(surface:FindFirstChild("Event").Text, "left"), "board shows a countdown")
ok(has(surface:FindFirstChild("Date").Text, "Bloomtide " .. cal.day), "board shows the date")
ok(has(surface:FindFirstChild("Ballot").Text, "FEATURED CROP VOTE"), "fair turns the ballot into a crop vote")
local votes = {}
for _, d in ipairs(board:GetDescendants()) do if d:IsA("ProximityPrompt") then table.insert(votes, d) end end
table.sort(votes, function(a, b) return a.Name < b.Name end)
eq(#votes, 2, "two ballot prompts")
eq(votes[1].ActionText, "Vote Meadow Herb", "fair ballot option A is a crop")
eq(votes[2].ActionText, "Vote Sunwheat", "fair ballot option B is a crop")
local stall = world:FindFirstChild("Festival Vendor")
local vendorPrompt = stall and stall:FindFirstChildOfClass("ProximityPrompt")
ok(vendorPrompt ~= nil, "Festival Vendor stall with a prompt")
eq(vendorPrompt:GetAttribute("IsleAction"), "eventVendor", "vendor prompt routes to the server")
ok((stall.CFrame.Position - gate.CFrame.Position).Magnitude > 15, "vendor stall clear of the gate")
-- Two voters pick Sunwheat, one Herb (one ballot each, re-votes replace).
local function voter(x)
	return { Character = { FindFirstChild = function() return { Position = board.CFrame.Position + Vector3.new(x, 0, 0) } end } }
end
local v1, v2, v3, far = voter(1), voter(2), voter(-1), voter(40)
promptSignals[votes[2]]:Fire(v1)
promptSignals[votes[2]]:Fire(v2)
promptSignals[votes[1]]:Fire(v3)
promptSignals[votes[1]]:Fire(far)
promptSignals[votes[1]]:Fire(v1)
promptSignals[votes[2]]:Fire(v1)
utc += 1
tick()
ok(has(surface:FindFirstChild("Ballot").Text, "Sunwheat  2"), "ballot tally counts each voter once and ignores far voters")
utc += 45
tick(45)
eq(attr("FestivalResource"), "Sunwheat", "the ballot chooses the fair's featured crop")
ok(has(surface:FindFirstChild("Ballot").Text, "double yield"), "board announces the featured crop")
eq(votes[1].Enabled, false, "ballot closed during the festival")
-- A place whose ExpeditionGate appears late (or never) still runs the calendar.
do
	local added = {}
	roblox.implementProperty("Workspace", "DescendantAdded", function(w)
		if not added[w] then added[w] = signal() end
		return added[w]
	end)
	local late = roblox.Instance.new("Workspace")
	local lateFestival = coroutine.create(luau.load(fs.readFile("festival.server.lua"), { debugName = "festival.server.lua", environment = {
		game = { GetService = function(_, name)
			if name == "Players" then return festivalPlayers end
			return { WaitForChild = function(_, child) return if child == "AetherData" then dataMarker else nil end }
		end },
		require = function() return Data end,
		workspace = late, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, Color3 = roblox.Color3,
		UDim2 = roblox.UDim2, UDim = roblox.UDim, Font = roblox.Font, Enum = roblox.Enum, os = { time = function() return utc end },
		task = { wait = function() coroutine.yield() end },
	}, injectGlobals = true }))
	assert(coroutine.resume(lateFestival))
	eq(late:GetAttribute("AetherSeason"), Data.calendarAt(utc).season, "calendar published before the gate exists")
	eq(late:GetAttribute("AetherEventKey"), Data.calendarAt(utc).eventKey, "event key published without a board")
	eq(late:FindFirstChild("Island Assembly"), nil, "no board without a gate")
	assert(coroutine.resume(lateFestival))
	local lateGate = roblox.Instance.new("Part")
	lateGate.Name = "ExpeditionGate"
	lateGate.Parent = late
	added[late]:Fire(lateGate)
	ok(late:FindFirstChild("Island Assembly") ~= nil, "board placed once the gate appears")
	assert(coroutine.resume(lateFestival))
	ok(has(late:FindFirstChild("Island Assembly"):FindFirstChildOfClass("BillboardGui"):FindFirstChild("Ballot").Text, "VOTE"), "ballot starts after the late board")
end

-- Production server on the same workspace.
local data = {}
local db = {}
function db:GetAsync(key) return data[key] end
function db:UpdateAsync(key, op)
	local value = op(data[key])
	if value then data[key] = value end
	return data[key]
end
local markers = { AetherData = { Name = "AetherData" }, AetherProgression = { Name = "AetherProgression" } }
local modules = { [markers.AetherData] = Data, [markers.AetherProgression] = Progression }
local queue, defaultRoll = {}, 0.999
local services = {
	Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end },
	ProximityPromptService = { PromptTriggered = signal() },
	ReplicatedStorage = { WaitForChild = function(_, name) return assert(markers[name], name) end }, ServerStorage = {},
	DataStoreService = { GetDataStore = function() return db end },
	HttpService = { GenerateGUID = function() return "festival-test" end },
	RunService = { IsStudio = function() return false end },
}
local objects, allObjects = {}, {}
local function deep(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = deep(v) end
	return out
end
local serverEnv = {
	game = { GetService = function(_, name) return services[name] end, BindToClose = function() end },
	workspace = world,
	Instance = { new = function(class)
		local instance = { Event = signal(), FireClient = function(_, player, state) player.last = state end }
		objects[class] = instance
		table.insert(allObjects, instance)
		return instance
	end },
	os = { clock = function() return clock end, time = function() return utc end },
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = { new = function() return { NextNumber = function() return if #queue > 0 then table.remove(queue, 1) else defaultRoll end } end },
	task = { spawn = function(f, ...) assert(coroutine.resume(coroutine.create(f), ...)) end, defer = function(f, ...) f(...) end,
		wait = function() coroutine.yield() end, delay = function() end },
}
-- Durable saves are deep-copied (DataStore semantics).
local rawUpdate = db.UpdateAsync
function db:UpdateAsync(key, op) return deep(rawUpdate(self, key, function(old) return deep(op(deep(old))) end)) end
luau.load(fs.readFile("server.server.lua"):gsub("^\239\187\191", ""), { debugName = "server.server.lua", environment = serverEnv, injectGlobals = true })()
local function newPlayer(id)
	local humanoid = { Health = 100, MaxHealth = 100, Died = signal(), TakeDamage = function(self, n) self.Health -= n end }
	local root = { Position = Vector3.zero }
	local pl = { GetAttribute = function(self, key) return rawget(self, "attr_" .. key) end, SetAttribute = function(self, key, value) rawset(self, "attr_" .. key, value) end,
		UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end }
	pl.Character = { FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end, WaitForChild = function() return humanoid end }
	services.Players.PlayerAdded:Fire(pl)
	return pl
end
-- §42: mock gather prompts harvest through real `strike` verbs (tools/strike-shim.luau).
require("./tools/strike-shim").install({signal = services.ProximityPromptService.PromptTriggered,
	invoke = function(p, verb, item) return objects.RemoteFunction.OnServerInvoke(p, verb, item) end, advance = function(s) clock += s end})
local function cmd(pl, verb, item)
	clock += 1
	return objects.RemoteFunction.OnServerInvoke(pl, verb, item)
end
local function node(verb, item)
	return { Enabled = true, MaxActivationDistance = 10, GetAttribute = function(_, key) return ({ IsleAction = verb, IsleItem = item })[key] end,
		FindFirstAncestorWhichIsA = function() return { Position = Vector3.zero } end }
end
local nodes = {}
local function gather(pl, item)
	clock += 30 -- every node has regrown
	nodes[item] = nodes[item] or node("gather", item)
	services.ProximityPromptService.PromptTriggered:Fire(nodes[item], pl)
	return pl.last
end
local function rejoin(pl)
	services.Players.PlayerRemoving:Fire(pl)
	return newPlayer(pl.UserId)
end
local function jump(t)
	utc = t
	tick()
	world:SetAttribute("FestivalResource", nil)
end
local a = newPlayer(1)
local function items(pl, id) return cmd(pl, "state").items[id] or 0 end
local function xp(pl, skill) return cmd(pl, "state").xp[skill] end
eq(cmd(a, "state").events ~= nil, true, "snapshot carries Calendar state")
-- Bloomtide Fair: crop +1, legacy ballot +1, featured crop x2 (once), season roll queued.
world:SetAttribute("FestivalResource", "Herb")
queue = { 0.5 }
local state = gather(a, "Herb")
eq(state.items.Herb, 6, "featured Herb: (1 + ballot 1 + fair 1) x2")
eq(state.xp.Farming, 12, "fair leaves XP untouched")
queue = { 0.1 }
eq(gather(a, "Herb").items.Herb, 14, "season proc adds +1 before the x2")
world:SetAttribute("FestivalResource", "Sunwheat")
eq(gather(a, "Herb").items.Herb, 16, "unfeatured crop: fair +1 only")
eq(gather(a, "Timber").items.Timber, 1, "fair ignores logs")
eq(gather(a, "Ore").items.Ore, 1, "fair ignores ore")
world:SetAttribute("AetherEvent", nil)
eq(gather(a, "Herb").items.Herb, 17, "without the published event the fair grants nothing")
tick()
eq(attr("AetherEvent"), "BloomtideFair", "the board republishes every tick")
-- Deepvein Surge: double Mining XP exactly once per harvest.
jump(surge.starts + 5)
a = rejoin(a)
local before = xp(a, "Mining")
state = gather(a, "Ore")
eq(state.xp.Mining - before, 24, "surge doubles Mining XP once (12 -> 24)")
eq(state.items.Ore, 2, "surge adds no ore")
ok(has(state.message, "+24 Mining XP"), "harvest message shows doubled XP")
eq(gather(a, "Timber").xp.Woodcutting, 24, "surge leaves Woodcutting XP alone")
world:SetAttribute("AetherEventKey", "DeepveinSurge:" .. (surge.starts - 999))
before = xp(a, "Mining")
eq(gather(a, "Ore").xp.Mining - before, 12, "forged event end is ignored")
-- Glimmertide Festival: +1 fish and festival-only carp.
jump(glimmer.starts + 5)
a = rejoin(a)
queue = { 0.9, 0.1 }
state = gather(a, "Fish")
eq(state.items.Fish, 2, "festival catch +1")
eq(state.items.SunscaleCarp, 1, "festival-only Sunscale Carp")
eq(state.collection.SunscaleCarp, 1, "carp counts toward collections")
queue = { 0.9, 0.9 }
eq(gather(a, "Fish").items.SunscaleCarp, 1, "no carp on a failed roll")
-- Hollow Night: event-only candy from existing creatures via the combat bridge.
local bridge
for _, o in ipairs(allObjects) do if o.Name == "IsleBridge" then bridge = o end end
ok(bridge ~= nil, "combat bridge published")
jump(hollow.starts + 5)
a = rejoin(a)
-- (two extra rolls: the remains drop, chance 1, and its amount)
queue = { 0.999, 0.999, 0.5, 0.5, 0.1 }
local kill = bridge.OnInvoke("kill", a, { monster = "BramblebackBoar" })
eq(kill.drops.GloamCandyOrb, 1, "Hollow Night candy reported as a drop")
eq(items(a, "GloamCandyOrb"), 1, "candy granted once")
queue = { 0.999, 0.999, 0.999, 0.999, 0.5, 0.5, 0.1 }
bridge.OnInvoke("kill", a, { monster = "StarbornSentinel" })
eq(items(a, "GloamCandyOrb"), 5, "stronger foe drops 4 candy")
queue = { 0.999, 0.999, 0.7 }
bridge.OnInvoke("kill", a, { monster = "BramblebackBoar" })
eq(items(a, "GloamCandyOrb"), 5, "failed candy roll")
jump(hollow.ends + 1)
a = rejoin(a)
queue = { 0.999, 0.999, 0.0 }
bridge.OnInvoke("kill", a, { monster = "BramblebackBoar" })
eq(items(a, "GloamCandyOrb"), 5, "no candy after Hollow Night")
-- Starfall Vigil: once per player per vigil, persisted across rejoin.
jump(vigil1.starts + 5)
a = rejoin(a)
state = cmd(a, "eventGift")
ok(has(state.message, "Starfall gift opened"), "gift opened")
eq(state.items.StarfallShard, 3, "gift shards")
eq(state.events.claims[vigil1.key], vigil1.ends, "claim visible to the Calendar page")
eq(cmd(a, "eventGift").items.StarfallShard, 3, "second claim same session refused")
a = rejoin(a)
eq(data.p1.profile.eventClaims[vigil1.key], vigil1.ends, "claim persisted in the durable save")
state = cmd(a, "eventGift")
ok(has(state.message, "already"), "rejoin cannot reclaim")
eq(state.items.StarfallShard, 3, "rejoin grants nothing")
local b = newPlayer(2)
eq(cmd(b, "eventGift").items.StarfallShard, 3, "each player has their own gift")
jump(vigil1.ends + 30)
a = rejoin(a)
ok(has(cmd(a, "eventGift").message, "No Starfall gift"), "no gift between vigils")
jump(vigil2.starts + 5)
a = rejoin(a)
eq(cmd(a, "eventGift").items.StarfallShard, 6, "the next vigil brings a new gift")
-- Leave, top up candy in the durable save (3 more = 8), rejoin.
services.Players.PlayerRemoving:Fire(a)
local claimCount = 0
for _ in pairs(data.p1.profile.eventClaims) do claimCount += 1 end
eq(claimCount, 1, "old vigil claims pruned (bounded save)")
data.p1.profile.items.GloamCandyOrb += 3
a = newPlayer(1)
-- Festival Vendor: server-verified exchange.
state = cmd(a, "eventTrade", "StarfallCocoa")
ok(has(state.message, "Visit the Festival Vendor"), "remote trade refused before visiting")
eq(state.items.StarfallShard, 6, "refused remote trade spends nothing")
clock += 1
services.ProximityPromptService.PromptTriggered:Fire(node("eventVendor", "Vendor"), a)
ok(has(a.last.message, "Festival Vendor"), "vendor greets")
eq(a:GetAttribute("IsleStation"), "Calendar", "vendor opens the Calendar page")
eq(a:GetAttribute("IsleStationVisit"), 1, "vendor visit counter bumps")
eq(a:GetAttribute("EventVendorUntil"), utc + Data.EVENT_VENDOR_SECONDS, "vendor window recorded server-side")
eq(cmd(a, "state").events.vendorUntil, utc + Data.EVENT_VENDOR_SECONDS, "vendor window in the snapshot")
eq(cmd(a, "eventVendor", "Vendor").items.StarfallCocoa, 2, "vendor verb needs the physical prompt")
state = cmd(a, "eventTrade", "StarfallCocoa")
eq(state.items.StarfallShard, 4, "cocoa costs two shards")
eq(state.items.StarfallCocoa, 3, "cocoa granted")
state = cmd(a, "eventTrade", "ArcaneDustBundle")
eq(state.items.GloamCandyOrb, 0, "candy spent for the dust bundle")
eq(state.items.ArcaneDust, 12, "dust bundle granted")
ok(has(cmd(a, "eventTrade", "ArcaneDustBundle").message, "You need"), "insufficient candy refused")
ok(has(cmd(a, "eventTrade", "TidebloomCharm").message, "You need"), "insufficient carp refused")
ok(has(cmd(a, "eventTrade", string.rep("x", 70)).message, "too long"), "oversized payload refused")
ok(has(cmd(a, "eventTrade", "Nope").message, "does not stock"), "unknown offer refused")
a:SetAttribute("EventVendorUntil", utc) -- the stall window has run out
ok(has(cmd(a, "eventTrade", "StarfallCocoa").message, "Visit the Festival Vendor"), "vendor window expires")
eq(cmd(a, "state").items.StarfallShard, 4, "expired trade spends nothing")
-- Outside every event the hooks change nothing.
jump(vigil2.ends + 60)
a = rejoin(a)
world:SetAttribute("AetherSeason", nil)
local oreBefore, mineBefore = items(a, "Ore"), xp(a, "Mining")
state = gather(a, "Ore")
eq(state.items.Ore - oreBefore, 1, "no event: classic yield")
eq(state.xp.Mining - mineBefore, 12, "no event: classic XP")

-- The board outside the fair: classic ballot options, next-event countdown.
jump(byId.HollowNight[2].ends + 10)
for _ = 1, 260 do
	if has(surface:FindFirstChild("Ballot").Text, "HARVEST BALLOT") then break end
	tick()
end
ok(has(surface:FindFirstChild("Ballot").Text, "HARVEST BALLOT"), "classic ballot outside the fair")
local classic = { ["Vote Meadow Timber"] = true, ["Vote Copperstone Ore"] = true, ["Vote Meadow Herb"] = true, ["Vote Skylake Minnow"] = true }
ok(classic[votes[1].ActionText] and classic[votes[2].ActionText], "classic options outside the fair")
ok(has(surface:FindFirstChild("Event").Text, "NEXT:"), "board counts down to the next event")
eq(attr("AetherEvent"), nil, "no event published between windows")
eq(attr("AetherEventEnds"), nil, "no event end between windows")
eq(attr("AetherEventKey"), nil, "no event key between windows")

------------------------------------------------------------------------------
-- 6. Journal → Calendar section in the atlas (tools/ui-harness.luau).
------------------------------------------------------------------------------
local H = require("./tools/ui-harness")
local fakeNow = vigil1.starts + 60
local meta = getmetatable(H.new("Frame"))
local baseIndex = meta.__index
meta.__index = function(self, key)
	if key == "GetServerTimeNow" then return function() return fakeNow end end
	return baseIndex(self, key)
end
local function calendarUi(size, events)
	local snap = H.snapshot()
	snap.items.StarfallShard, snap.items.GloamCandyOrb = 9, 2
	snap.events = events
	local ui = H.runAtlas(size, { snapshot = snap })
	H.press(H.find(ui.gui, "AtlasButton"))
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui.scroll, "SectionCalendar"))
	return ui
end
for _, size in ipairs({ roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303) }) do
	local ui = calendarUi(size, { claims = {}, vendorUntil = fakeNow + 200 })
	eq(#ui.warnings, 0, "calendar renders without warnings at " .. tostring(size))
	ok(H.find(ui.scroll, "CalendarToday") ~= nil, "date card at " .. tostring(size))
	ok(H.find(ui.scroll, "CalendarLive") ~= nil, "live Starfall card at " .. tostring(size))
	ok(H.find(ui.scroll, "CalendarNext1") ~= nil, "upcoming card at " .. tostring(size))
	ok(H.find(ui.scroll, "VendorOpen") ~= nil, "vendor open card at " .. tostring(size))
	for _, offer in ipairs(Data.EventVendor) do ok(H.find(ui.scroll, "Offer" .. offer.id) ~= nil, offer.id .. " listed at " .. tostring(size)) end
end
local ui = calendarUi(roblox.Vector2.new(1366, 768), { claims = {}, vendorUntil = fakeNow + 200 })
local text = {}
for _, d in ipairs(ui.scroll:GetDescendants()) do if d.ClassName == "TextLabel" then table.insert(text, d.Text) end end
text = table.concat(text, "\n")
ok(has(text, "Frostveil " .. Data.calendarAt(fakeNow).day), "season and day shown")
ok(has(text, "Ends in 59m"), "live countdown shown")
ok(has(text, "Starts in"), "next-event countdown shown")
H.press(H.find(ui.scroll, "CalendarClaim"))
eq(ui.sent[#ui.sent][1], "eventGift", "claim button sends the gift verb")
H.press(H.find(ui.scroll, "TradeStarfallCocoa"))
eq(ui.sent[#ui.sent][1], "eventTrade", "affordable trade sends")
eq(ui.sent[#ui.sent][2], "StarfallCocoa", "trade sends the offer id")
local sent = #ui.sent
H.press(H.find(ui.scroll, "TradeFrostveilLocket"))
eq(#ui.sent, sent, "unaffordable trade stays local")
ui = calendarUi(roblox.Vector2.new(1366, 768), { claims = { [vigil1.key] = vigil1.ends }, vendorUntil = 0 })
ok(H.find(ui.scroll, "VendorClosed") ~= nil, "vendor closed card")
sent = #ui.sent
H.press(H.find(ui.scroll, "CalendarClaim"))
H.press(H.find(ui.scroll, "TradeStarfallCocoa"))
eq(#ui.sent, sent, "claimed gift and closed vendor send nothing")
fakeNow = byId.HollowNight[2].ends + 10
ui = calendarUi(roblox.Vector2.new(844, 390), { claims = "bad", vendorUntil = "soon" })
eq(#ui.warnings, 0, "malformed Calendar state tolerated")
ok(H.find(ui.scroll, "CalendarLive") == nil, "no live card between events")
ui = calendarUi(roblox.Vector2.new(844, 390), nil)
eq(#ui.warnings, 0, "missing Calendar state tolerated")

print(("Festival QA passed %d checks (calendar, %d event windows/year, board, server hooks, atlas)."):format(checks, #windows))

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-festival.luau")
