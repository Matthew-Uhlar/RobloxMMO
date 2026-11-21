-- Exploration & Factions: Aether Motes, Mote Shrines, the Wayglass and factions.
-- Part A checks shared/GameData.lua (Data.Exploration / Data.Factions): mote
-- ids, regions, milestone maths, task pool, deterministic boards, gates,
-- reward multipliers and the shop.
-- Part B builds world.server.lua: every mote sits on a real standing surface
-- of its island (not embedded, spaced apart), shrines and standards exist and
-- the static part budget holds.
-- Part C runs server.server.lua: distance-validated pickups (once per
-- profile, client ids ignored, region / Agility gates, rate limit), shrine
-- milestones and region bonuses into p.perkStats, the Wayglass, migration,
-- rejoin safety, faction boards (UTC roll-forward, auto-claim), progress from
-- kills and harvests, deliveries, pledges and switches, shop and titles.
-- Part D renders the client mote layer (motes.client.lua) with doubles.
-- Part E renders Journal › Motes / Factions at three sizes.
-- Part F prints and bounds the balance model.
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
local EX, FA = Data.Exploration, Data.Factions
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

------------------------------------------------------------------------------
-- Part A: data and rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(EX) == "table" and type(FA) == "table", "Data.Exploration and Data.Factions exist")
ok(EX.TOTAL >= 60 and EX.TOTAL <= 80, "60-80 motes (" .. EX.TOTAL .. ")")
local ids, perRegion, gated = {}, {}, 0
for i, m in ipairs(EX.Motes) do
	ok(not ids[m.id], m.id .. " unique")
	ids[m.id] = true
	eq(m.index, i, m.id .. " indexed")
	eq(EX.MoteById[m.id], m, m.id .. " by id")
	ok(type(m.isle) == "string" and EX.IsleRegion[m.isle] ~= nil, m.id .. " on a known island")
	eq(m.region, EX.IsleRegion[m.isle], m.id .. " region from its island")
	ok(Data.RegionById[m.region] ~= nil, m.id .. " region is a Data region")
	ok(type(m.at) == "table" and #m.at == 3, m.id .. " offset")
	ok(type(m.hint) == "string" and #m.hint >= 8 and #m.hint <= 60, m.id .. " hint text")
	ok(m.agility >= 0 and m.agility <= 99, m.id .. " agility gate")
	if m.agility > 0 then
		gated += 1
		local course
		for _, c in ipairs(Data.Agility.Courses) do if c.level == m.agility then course = c end end
		ok(course ~= nil, m.id .. " gate matches a course level")
		ok(EX.IsleRegion[m.isle] == course.region, m.id .. " gate course runs on its island's region")
	end
	perRegion[m.region] = (perRegion[m.region] or 0) + 1
end
ok(gated >= 12, "Agility-gated perch motes (" .. gated .. ")")
for _, r in ipairs(EX.RegionOrder) do
	ok((perRegion[r] or 0) >= 4, r .. " has motes (" .. tostring(perRegion[r]) .. ")")
	eq(EX.RegionTotal[r], perRegion[r], r .. " total")
	ok(EX.ShrineIsle[r] ~= nil and EX.IsleRegion[EX.ShrineIsle[r]] == r, r .. " shrine on its own island")
end
for _, r in ipairs(Data.Regions) do ok(EX.RegionTotal[r.id] ~= nil, r.id .. " is an explored region") end
-- Milestones and perks.
eq(EX.STEPS, math.floor(EX.TOTAL / 5), "a milestone every five motes")
eq(next(EX.perkStats(0, 0)), nil, "no perks at zero")
eq(EX.perkStats(1, 0).health, 2, "first step +2 Health")
eq(EX.perkStats(1, 0).defense, nil, "first step no Defense")
eq(EX.perkStats(2, 0).defense, 1, "second step +1 Defense")
eq(EX.perkStats(2, 0).speed, 1, "second step +1 Speed")
eq(EX.perkStats(0, 3).health, 3 * EX.REGION_HEALTH, "region bonuses")
eq(EX.perkStats(999, 999).health, 2 * EX.STEPS + EX.REGION_HEALTH * #EX.RegionOrder, "clamped maximum")
local full = EX.perkStats(EX.STEPS, #EX.RegionOrder)
for stat in pairs(full) do ok(Data.Stats[stat] ~= nil and stat ~= "miningFortune", stat .. " is a real, yield-neutral stat") end
ok(full.health <= 60 and full.defense <= 10 and full.speed <= 10, "full mote perks stay modest (" .. full.health .. "/" .. full.defense .. "/" .. full.speed .. ")")
ok(EX.hintCost(0) < EX.hintCost(40) and EX.hintCost(-5) == EX.hintCost(0) and EX.hintCost(1e9) == EX.hintCost(EX.TOTAL), "hint cost rises and clamps")
ok(EX.canReach({agility = 30}, 30) and not EX.canReach({agility = 30}, 29), "agility gate")
-- Factions.
eq(#FA.Order, 3, "three factions")
local rivals = {}
for _, id in ipairs(FA.Order) do
	local f = FA.Factions[id]
	ok(f and f.id == id and #f.name > 5, id .. " defined")
	ok(FA.Factions[f.rival] ~= nil and f.rival ~= id, id .. " has a rival")
	rivals[f.rival] = (rivals[f.rival] or 0) + 1
	ok(EX.IsleRegion[f.isle] ~= nil, id .. " standard on a world island")
	for _, r in ipairs(f.regions) do ok(Data.RegionById[r] ~= nil, id .. " region " .. r) end
	for _, s in ipairs(f.lampSkills) do ok(Data.Skills[s] ~= nil and s ~= "Dungeoneering" and s ~= "Carpentry", id .. " lamp skill " .. s) end
end
for _, id in ipairs(FA.Order) do eq(rivals[id], 1, id .. " is exactly one faction's rival") end
eq(FA.mult("Concord", "Concord"), 1, "pledged x1")
eq(FA.mult("Circle", "Concord"), 0.25, "rival x0.25")
eq(FA.mult("Corsairs", "Concord"), 0.6, "third x0.6")
eq(FA.mult("Concord", ""), 0.6, "unpledged x0.6")
eq(FA.mult("Concord", "Nope"), 0.6, "unknown pledge = none")
eq(FA.rankOf(0), 1, "outsider")
eq(FA.rankOf(499), 1, "still outsider")
eq(FA.rankOf(500), 2, "kindred")
eq(FA.rankOf(1e9), #FA.Ranks, "top rank")
eq(FA.dayOf(86400 * 3 + 5), 3, "UTC day")
eq(FA.resetIn(86400 * 3 + 5), 86395, "reset countdown")
local kinds = {}
for _, t in ipairs(FA.Tasks) do
	eq(FA.TaskById[t.id], t, t.id .. " indexed")
	ok(FA.Factions[t.faction] ~= nil, t.id .. " faction")
	ok(t.amount >= 1 and t.amount <= 40, t.id .. " amount")
	ok(t.rep > 0 and t.sigils > 0 and t.coins > 0, t.id .. " pays")
	kinds[t.faction .. t.kind] = (kinds[t.faction .. t.kind] or 0) + 1
	if t.kind == "kill" then
		ok(rawget(Data.Monsters, t.target) ~= nil, t.id .. " iterated monster")
		ok(t.xp > 0 and t.skill == "Combat", t.id .. " combat XP")
	elseif t.kind == "gather" then
		ok(Data.ResourceSkill[t.target] ~= nil, t.id .. " resource")
		local r = P.resource(t.target)
		ok((t.levels[r.skill] or 0) >= r.level, t.id .. " gated at the resource level")
	else
		eq(t.kind, "deliver", t.id .. " kind")
		ok(Data.Items[t.target] ~= nil, t.id .. " item")
		eq(t.coins, math.ceil(Data.Items[t.target].value * t.amount * 1.3), t.id .. " pays 1.3x value")
		eq(t.xp, nil, t.id .. " pays no XP")
	end
	for skill, lvl in pairs(t.levels) do ok(Data.Skills[skill] ~= nil and lvl >= 1 and lvl <= 99, t.id .. " gate " .. skill) end
	if t.region then ok(Data.RegionById[t.region] ~= nil, t.id .. " region") end
end
for _, id in ipairs(FA.Order) do
	for _, k in ipairs(FA.KindOrder) do ok((kinds[id .. k] or 0) >= 4, id .. " has " .. k .. " tasks") end
end
local fresh = {levels = {}, regions = {}}
local maxed = {levels = {}, regions = {}}
for s in pairs(Data.Skills) do maxed.levels[s] = 99 end
for _, r in ipairs(Data.Regions) do maxed.regions[r.id] = true end
local seen = {}
for day = 20000, 20060 do
	for _, salt in ipairs({1, 4242, 999999}) do
		for _, id in ipairs(FA.Order) do
			local a, b = FA.draw(id, day, salt, fresh), FA.draw(id, day, salt, fresh)
			eq(table.concat(a, ","), table.concat(b, ","), "draw deterministic " .. id)
			eq(#a, FA.TASKS, id .. " fresh journal gets three tasks")
			local set = {}
			for _, tid in ipairs(a) do
				ok(not set[tid], "distinct tasks")
				set[tid] = true
				local t = FA.TaskById[tid]
				eq(t.faction, id, tid .. " belongs to " .. id)
				ok(FA.eligible(t, fresh), tid .. " eligible for a fresh journal")
			end
			local v = FA.draw(id, day, salt, maxed)
			eq(FA.TaskById[v[1]].kind, "kill", "veteran slot 1 is a kill task")
			eq(FA.TaskById[v[2]].kind, "gather", "veteran slot 2 is a gather task")
			eq(FA.TaskById[v[3]].kind, "deliver", "veteran slot 3 is a delivery")
			for _, tid in ipairs(v) do seen[tid] = true end
		end
	end
end
local seenCount = 0
for _ in pairs(seen) do seenCount += 1 end
ok(seenCount >= #FA.Tasks * 0.8, "veterans see most of the pool (" .. seenCount .. "/" .. #FA.Tasks .. ")")
ok(table.concat(FA.draw("Concord", 20001, 5, maxed), ",") ~= table.concat(FA.draw("Concord", 20002, 5, maxed), ",")
	or table.concat(FA.draw("Concord", 20003, 5, maxed), ",") ~= table.concat(FA.draw("Concord", 20002, 5, maxed), ","), "boards change between days")
ok(not FA.eligible(FA.TaskById.ConcordGatherVoidstone, {levels = {Mining = 99}, regions = {}}), "gated region refused")
ok(FA.eligible(FA.TaskById.ConcordGatherVoidstone, {levels = {Mining = 99}, regions = {Gloomhollow = true}}), "gated region allowed")
do
	local t = FA.TaskById.ConcordKillShaleCrawler
	eq(FA.reward(t, "Concord").rep, 120, "pledged rep")
	eq(FA.reward(t, "Corsairs").rep, 30, "rival rep (the Corsairs distrust the Concord)")
	eq(FA.reward(t, "Circle").rep, 72, "neutral rep")
	eq(FA.reward(t, "").sigils, 7, "unpledged sigils")
	eq(FA.reward(t, "Circle").coins, t.coins, "coins do not scale with the pledge")
end
-- Shop.
for _, e in ipairs(FA.Shop) do
	eq(FA.ShopById[e.id], e, e.id .. " indexed")
	ok(FA.Ranks[e.rank] ~= nil and e.sigils > 0, e.id .. " rank and price")
	if e.item then
		local def = Data.Items[e.item]
		ok(def ~= nil and def.kind == "accessory" and def.faction == e.faction, e.id .. " accessory")
		ok(P.accessoryFamily(e.item) == nil, e.id .. " own family")
		for stat in pairs(def.stats) do ok(Data.Stats[stat] ~= nil and not string.find(stat, "Fortune"), e.id .. " stat " .. stat) end
	end
	if e.kind == "crest" then ok(Data.Items[e.consumes] ~= nil and e.rank == #FA.Ranks, e.id .. " upgrades the charm at the top rank") end
end
do
	local rec = {rep = {Concord = 600}, sigils = {Concord = 45}, pledge = "", unlocks = {}}
	ok(FA.canBuy("ConcordTitle1", rec, 0) ~= nil, "Kindred title open without a pledge")
	local e, why = FA.canBuy("ConcordLamp", rec, 0, "Mining")
	ok(e == nil and has(why, "Sworn"), "rank gate")
	rec.rep.Concord = 2500
	rec.sigils.Concord = 500
	e, why = FA.canBuy("ConcordLamp", rec, 0, "Mining")
	ok(e == nil and has(why, "Pledge"), "pledge gate above Kindred")
	rec.pledge = "Concord"
	ok(FA.canBuy("ConcordLamp", rec, 0, "Mining") ~= nil, "pledged lamp")
	e, why = FA.canBuy("ConcordLamp", rec, 0, "Fishing")
	ok(e == nil and has(why, "Choose a skill"), "lamp skill must be the faction's")
	e, why = FA.canBuy("ConcordCharm", rec, 9999)
	ok(e == nil and has(why, "coins"), "coin price")
	ok(FA.canBuy("ConcordCharm", rec, 10000) ~= nil, "charm affordable")
	rec.unlocks.ConcordTitle1 = true
	e, why = FA.canBuy("ConcordTitle1", rec, 0)
	ok(e == nil and has(why, "already"), "title once")
	ok(FA.canBuy("Nope", rec, 0) == nil, "unknown entry")
	ok(FA.lampXp("Mining", 50) > FA.lampXp("Mining", 10), "lamp scales with level")
end
print("PASS: " .. (checks - partA) .. " Exploration & Factions data assertions.")

------------------------------------------------------------------------------
-- Part B: world.
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
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local worldEnv = {
	game = {GetService = function(_, name)
		if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function() end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
	UDim2 = roblox.UDim2, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
luau.load(fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position"), {environment = worldEnv, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
ok(islands ~= nil, "islands built")
local parts, solids = 0, {}
for _, o in world:GetDescendants() do
	if o:IsA("BasePart") then
		parts += 1
		if o.CanCollide then table.insert(solids, o) end
	end
end
ok(parts < 4000, "static world under the 4000 part budget (" .. parts .. ")")
local ours = 0
for _, o in world:GetDescendants() do
	if o:IsA("Model") and o:GetAttribute("ExploreContent") then
		for _, d in o:GetDescendants() do if d:IsA("BasePart") then ours += 1 end end
	end
end
ok(ours <= 20, "Exploration & Factions adds at most 20 static parts (" .. ours .. ")")
local function inside(o, pt, pad)
	pad = pad or 0
	local lp = o.CFrame:PointToObjectSpace(pt)
	local s = o.Size / 2
	local shape = o:IsA("Part") and o.Shape or nil
	if shape == roblox.Enum.PartType.Cylinder then
		local r = math.min(s.Y, s.Z) + pad
		return math.abs(lp.X) <= s.X + pad and (lp.Y * lp.Y + lp.Z * lp.Z) <= r * r
	elseif shape == roblox.Enum.PartType.Ball then
		return lp.Magnitude <= s.X + pad
	end
	return math.abs(lp.X) <= s.X + pad and math.abs(lp.Y) <= s.Y + pad and math.abs(lp.Z) <= s.Z + pad
end
local function solidAt(pt, pad)
	for _, o in solids do if inside(o, pt, pad) then return o end end
	return nil
end
local worldPos = {}
for _, m in ipairs(EX.Motes) do
	local isle = islands:FindFirstChild(m.isle)
	ok(isle ~= nil, m.id .. " island exists")
	eq(isle:GetAttribute("Region"), m.region, m.id .. " region matches the island's Region attribute")
	local pos = isle:GetAttribute("IslandCenter") + Vector3.new(m.at[1], m.at[2], m.at[3])
	worldPos[m.id] = pos
	ok(solidAt(pos, 0.3) == nil, m.id .. " is not embedded in a solid part")
	-- A standing surface 1.5-4 studs below (the player's feet), headroom above it.
	local surface
	for d = 1.5, 4, 0.25 do if solidAt(pos - Vector3.new(0, d, 0)) then surface = d break end end
	ok(surface ~= nil, m.id .. " hovers over a standing surface")
	if surface then
		local feet = pos - Vector3.new(0, surface - 0.3, 0)
		for h = 0, 4.5, 0.5 do ok(solidAt(feet + Vector3.new(0, h, 0)) == nil, m.id .. " has headroom at +" .. h) end
	end
	ok(m.at[2] > -2 and m.at[2] < 40, m.id .. " height on its island")
end
for i, a in ipairs(EX.Motes) do
	for j = i + 1, #EX.Motes do
		local b = EX.Motes[j]
		ok((worldPos[a.id] - worldPos[b.id]).Magnitude >= 10, a.id .. " and " .. b.id .. " spaced apart")
	end
end
local shrines, standards = {}, {}
for _, d in world:GetDescendants() do
	if d:IsA("ProximityPrompt") and d:GetAttribute("IsleAction") == "moteShrine" then
		local region = d:GetAttribute("IsleItem")
		shrines[region] = d
		eq(d:GetAttribute("IsleRegion"), region, region .. " shrine is region-gated")
		local host = d.Parent
		while host and host.Parent ~= islands do host = host.Parent end
		eq(host and host.Name, EX.ShrineIsle[region], region .. " shrine stands on its island")
		ok(d.Parent:GetAttribute("Shape") == "Waystone", region .. " shrine uses the Waystone mesh")
	elseif d:IsA("ProximityPrompt") and d:GetAttribute("IsleAction") == "factionBoard" then
		standards[d:GetAttribute("IsleItem")] = d
	end
end
for _, r in ipairs(EX.RegionOrder) do ok(shrines[r] ~= nil, r .. " has a shrine") end
for _, id in ipairs(FA.Order) do
	ok(standards[id] ~= nil, id .. " has a standard")
	ok(islands:FindFirstChild("Anchor_Waypoint_Faction_" .. id, true) ~= nil, id .. " waypoint anchor")
end
ok(islands:FindFirstChild("Anchor_Waypoint_MoteShrine", true) ~= nil, "hub shrine waypoint")
do
	local visitor = {attrs = {}}
	function visitor:SetAttribute(k, v) self.attrs[k] = v end
	function visitor:GetAttribute(k) return self.attrs[k] end
	shrines.Hub.Triggered:Fire(visitor)
	eq(visitor.attrs.IsleStation, "Motes", "shrine opens Journal › Motes")
	eq(visitor.attrs.IsleStationVisit, 1, "shrine bumps the visit counter")
	standards.Concord.Triggered:Fire(visitor)
	eq(visitor.attrs.IsleStation, "Factions", "standard opens Journal › Factions")
	eq(visitor.attrs.IsleStationVisit, 2, "standard bumps the visit counter")
end
-- Shrines and standards keep clear of every mote.
for _, q in pairs(shrines) do for id, pos in pairs(worldPos) do ok((q.Parent.CFrame.Position - pos).Magnitude > 4, id .. " clear of a shrine") end end
print("PASS: " .. (checks - partB) .. " Exploration & Factions world assertions (" .. parts .. " static parts, " .. ours .. " ours).")

------------------------------------------------------------------------------
-- Part C: server behaviour.
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
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) if name == "AetherTrails" then return markers.AetherTrails end return nil end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "explore-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local exploreApi
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end, FindFirstChild = function(_, name) if name == "Islands" then return islands end return nil end},
	Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function(className)
		local o = {ClassName = className, Event = signal(), FireClient = function(_, player, state) player.last = state end}
		function o:Destroy() self.Parent = nil; self.destroyed = true end
		table.insert(serverObjects, o)
		return o
	end},
	UDim2 = roblox.UDim2, Color3 = roblox.Color3, Enum = roblox.Enum,
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return 0.999 end, NextInteger = function(_, lo) return lo end} end},
	__ExploreHarness = function(api) exploreApi = api end,
	task = {
		spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
ok(exploreApi ~= nil and type(exploreApi.migrate) == "function", "Explore block loaded")
local liveById = {}
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 5000, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
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
local remote, bridge
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
end
ok(remote ~= nil and bridge ~= nil, "IsleAction and IsleBridge found")
local function cmd(p, verb, item) advance(1); return remote.OnServerInvoke(p, verb, item) end
local function standAt(p, pos) p.root.Position = pos end
local function prompt(action, item, at)
	local base = {CFrame = CFrame.new(at)}
	local q = {Enabled = true, MaxActivationDistance = 9, attrs = {IsleAction = action, IsleItem = item}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q) advance(30); p.last = nil; services.ProximityPromptService.PromptTriggered:Fire(q, p); return p.last end
local function motesOf(s) return s.exploration.motes end
local function hp(s) return s.depth.stats.health end
local X = Data.XP_TABLE

-- Fresh journal.
local finder = player(9101)
local s0 = cmd(finder, "state")
ok(type(s0.exploration) == "table", "snapshot carries exploration")
eq(motesOf(s0).count, 0, "nothing found")
eq(motesOf(s0).found, string.rep("0", EX.TOTAL), "empty bitmap")
eq(motesOf(s0).total, EX.TOTAL, "total shared")
eq(motesOf(s0).claimable, 0, "nothing to claim")
eq(s0.exploration.factions.pledge, "", "unpledged")
for _, id in ipairs(FA.Order) do eq(#s0.exploration.factions.list[id].board, FA.TASKS, id .. " board drawn") end
-- Far from every mote: nothing to pick up.
ok(has(cmd(finder, "moteCollect").message, "within reach"), "no mote in the void")
-- A hub mote: picked up by distance; the client's id is ignored.
local hubMotes = {}
for _, m in ipairs(EX.Motes) do if m.region == "Hub" and m.agility == 0 then table.insert(hubMotes, m) end end
ok(#hubMotes >= 10, "hub ground motes for the test (" .. #hubMotes .. ")")
local first = hubMotes[1]
standAt(finder, worldPos[first.id] + Vector3.new(0, 0.6, 0))
local s1 = cmd(finder, "moteCollect", "Crown01")
ok(has(s1.message, "found"), "mote picked up: " .. tostring(s1.message))
eq(motesOf(s1).count, 1, "count 1")
eq(string.sub(motesOf(s1).found, first.index, first.index), "1", "bitmap marks the mote")
local crown = EX.MoteById.Crown01
eq(string.sub(motesOf(s1).found, crown.index, crown.index), "0", "client-named id not credited")
advance(2)
ok(has(cmd(finder, "moteCollect").message, "within reach"), "the same mote is never picked twice")
eq(motesOf(cmd(finder, "state")).count, 1, "still one")
-- Just outside the radius.
local second = hubMotes[2]
standAt(finder, worldPos[second.id] + Vector3.new(EX.PICKUP_RADIUS + 0.5, 0, 0))
advance(2)
ok(has(cmd(finder, "moteCollect").message, "within reach"), "beyond the pickup radius refused")
-- Rate limit: a second pickup inside the cooldown is refused.
standAt(finder, worldPos[second.id])
advance(2)
ok(has(cmd(finder, "moteCollect").message, "found"), "second mote")
standAt(finder, worldPos[hubMotes[3].id])
advance(0.3)
local fast = remote.OnServerInvoke(finder, "moteCollect")
ok(has(fast.message, "One moment"), "pickup cooldown")
-- Rejoin keeps progress (saved once per profile).
local prof = stored(finder)
eq(prof.motes.count, 2, "count saved")
ok(prof.motes.found[first.id] and prof.motes.found[second.id], "found ids saved")
finder = player(9101)
eq(motesOf(cmd(finder, "state")).count, 2, "rejoin keeps motes")
standAt(finder, worldPos[first.id])
advance(2)
ok(has(cmd(finder, "moteCollect").message, "within reach"), "no re-pickup after a rejoin")
-- Three more: five found, a milestone awaits.
for i = 3, 5 do
	standAt(finder, worldPos[hubMotes[i].id])
	advance(2)
	local s = cmd(finder, "moteCollect")
	ok(has(s.message, "found"), "hub mote " .. i)
	if i == 5 then ok(has(s.message, "milestone"), "milestone notice at five") end
end
local s5 = cmd(finder, "state")
eq(motesOf(s5).claimable, 1, "one milestone ready")
-- The shrine is prompt-only.
ok(has(cmd(finder, "moteShrine", "Hub").message, "in person"), "shrine verb needs the prompt")
local hpBefore, coinsBefore = hp(s5), s5.coins
local shrineAt = Vector3.new(0, 0, 0)
standAt(finder, shrineAt)
local claim = use(finder, prompt("moteShrine", "Hub", shrineAt))
ok(claim ~= nil and has(claim.message, "milestone"), "shrine claims the milestone")
eq(claim.coins, coinsBefore + EX.stepCoins(1), "milestone coins")
eq(hp(claim), hpBefore + 2, "+2 Health from the first milestone")
eq(motesOf(claim).steps, 1, "one step claimed")
eq(motesOf(claim).stats.health, 2, "perk stats published")
local again = use(finder, prompt("moteShrine", "Hub", shrineAt))
ok(has(again.message, "hums"), "nothing more to claim")
eq(again.coins, claim.coins, "no double pay")
ok(has(use(finder, prompt("moteShrine", "Nowhere", shrineAt)).message, "Unknown shrine"), "unknown shrine")
eq(stored(finder).perkStats.motes.health, 2, "mote perk saved")
finder = player(9101)
eq(hp(cmd(finder, "state")), hp(claim), "perk survives a rejoin")
-- Region gate: a Skyreach mote needs region access.
local sky
for _, m in ipairs(EX.Motes) do if m.region == "Skyreach" and m.agility == 0 then sky = m break end end
standAt(finder, worldPos[sky.id])
advance(2)
local denied = cmd(finder, "moteCollect")
ok(has(denied.message, "Skyreach") or has(denied.message, "charter"), "region-gated mote refused: " .. tostring(denied.message))
eq(motesOf(denied).count, 5, "refusal credits nothing")
-- Agility gate: a perch mote needs its course level.
local perch
for _, m in ipairs(EX.Motes) do if m.region == "Meadow" and m.agility > 1 then perch = m break end end
standAt(finder, worldPos[perch.id])
advance(2)
ok(has(cmd(finder, "moteCollect").message, "Agility"), "agility-gated mote refused")
local nimble = seeded(9102, function(pr) pr.xp.Agility = X[perch.agility] end)
standAt(nimble, worldPos[perch.id])
advance(2)
ok(has(cmd(nimble, "moteCollect").message, "found"), "agility-gated mote at its level")
-- Wayglass bearing.
local seeker = seeded(9103, function(pr) pr.coins = 100 end)
standAt(seeker, worldPos[hubMotes[1].id] + Vector3.new(0, 0, 20))
local poor = cmd(seeker, "moteHint")
ok(has(poor.message, "costs"), "hint needs coins")
eq(seeker.attrs.MoteHint, nil, "no bearing without paying")
leave(seeker)
data["p9103"].profile.coins = 5000
seeker = player(9103)
standAt(seeker, worldPos[hubMotes[1].id] + Vector3.new(0, 0, 20))
local h = cmd(seeker, "moteHint")
ok(has(h.message, "Wayglass"), "bearing bought: " .. tostring(h.message))
eq(h.coins, 5000 - EX.hintCost(0), "hint cost paid")
local target = EX.MoteById[seeker.attrs.MoteHint]
ok(target ~= nil and target.region == "Hub" and target.agility <= 1, "bearing names a reachable hub mote")
ok(seeker.attrs.MoteHintUntil > utc, "bearing expires later")
eq(motesOf(h).hint, target.id, "snapshot shows the bearing")
-- Nearest: no other reachable hub mote is closer.
local here = worldPos[hubMotes[1].id] + Vector3.new(0, 0, 20)
for _, m in ipairs(EX.Motes) do
	if m.region == "Hub" and m.agility <= 1 then ok((worldPos[m.id] - here).Magnitude >= (worldPos[target.id] - here).Magnitude - 0.01, "bearing is the nearest (" .. m.id .. ")") end
end
standAt(seeker, worldPos[target.id])
advance(2)
ok(has(cmd(seeker, "moteCollect").message, "found"), "bearing target collected")
eq(seeker.attrs.MoteHint, "", "bearing clears on pickup")
standAt(seeker, Vector3.new(0, 0, 4000))
ok(has(cmd(seeker, "moteHint").message, "Stand on an island"), "no bearing in the void")
-- Region completion bonus at that region's shrine (Quarry), with migration.
local quarry = seeded(9104, function(pr)
	pr.motes = {found = {}, steps = 99, regions = {Hub = true, Nope = true}, hints = -4}
	for _, id in ipairs(EX.MotesByRegion.Quarry) do pr.motes.found[id] = true end
	pr.motes.found.FakeMote = true
	pr.motes.found[EX.MotesByRegion.Hub[1]] = "yes"
end)
local q0 = cmd(quarry, "state")
eq(motesOf(q0).count, EX.RegionTotal.Quarry, "migration counts only real found ids")
eq(motesOf(q0).steps, math.floor(EX.RegionTotal.Quarry / EX.STEP), "claimed steps never exceed the motes found")
eq(motesOf(q0).regions.Quarry.claimed, false, "complete but unclaimed region")
eq(motesOf(q0).regions.Hub.claimed, false, "incomplete region claim dropped")
local hp0 = hp(q0)
standAt(quarry, shrineAt)
local qc = use(quarry, prompt("moteShrine", "Quarry", shrineAt))
ok(has(qc.message, "complete"), "region bonus at its own shrine")
eq(motesOf(qc).regions.Quarry.claimed, true, "region claimed")
eq(motesOf(qc).steps, math.floor(EX.RegionTotal.Quarry / EX.STEP), "no extra steps")
eq(hp(qc), hp0 + EX.REGION_HEALTH, "region bonus Health")
eq(qc.coins, q0.coins + EX.regionCoins("Quarry"), "region bonus coins")
local qcoins = qc.coins
local qa = use(quarry, prompt("moteShrine", "Quarry", shrineAt))
eq(qa.coins, qcoins, "region bonus once")
ok(has(use(quarry, prompt("moteShrine", "Hub", shrineAt)).message, "hums"), "other shrines do not pay another region")

-- Factions.
local today = FA.dayOf(utc)
local function setBoards(pr, boards)
	pr.factions.day = FA.dayOf(utc)
	for id, list in pairs(boards) do
		pr.factions.boards[id] = {}
		for i, tid in ipairs(list) do table.insert(pr.factions.boards[id], {id = tid[1], progress = tid[2] or 0, claimed = false}) end
	end
end
local faction = player(9201)
local f0 = cmd(faction, "state").exploration.factions
eq(f0.day, today, "boards for today")
local firstBoard = {}
for _, id in ipairs(FA.Order) do firstBoard[id] = f0.list[id].board[1].id end
local fprof = stored(faction)
ok(fprof.factions.salt >= 1, "salt stored")
faction = player(9201)
local f1 = cmd(faction, "state").exploration.factions
for _, id in ipairs(FA.Order) do eq(f1.list[id].board[1].id, firstBoard[id], id .. " board kept on rejoin") end
do
	local ctx = {levels = {}, regions = {}}
	for _, s in ipairs(Data.SkillOrder) do ctx.levels[s] = 1 end
	for _, id in ipairs(FA.Order) do eq(FA.draw(id, today, fprof.factions.salt, ctx)[1], firstBoard[id], id .. " board reproduces from the salt") end
end
-- Progress: harvests and kills feed the boards through Logs.event.
local worker = seeded(9202, function(pr)
	setBoards(pr, {Concord = {{"ConcordKillShaleCrawler", FA.TaskById.ConcordKillShaleCrawler.amount - 1}, {"ConcordGatherOre", FA.TaskById.ConcordGatherOre.amount - 1}, {"ConcordDeliverOre"}},
		Circle = {{"CircleKillThornling"}, {"CircleGatherHerb"}, {"CircleDeliverHerb"}}, Corsairs = {{"CorsairsGatherFish"}, {"CorsairsGatherGlassfin"}, {"CorsairsDeliverFish"}}})
	pr.xp.Combat = X[20]
end)
local w0 = cmd(worker, "state").exploration.factions
eq(w0.list.Concord.board[1].id, "ConcordKillShaleCrawler", "seeded board kept")
bridge.OnInvoke("kill", worker, {monster = "CinderMite"})
eq(cmd(worker, "state").exploration.factions.list.Concord.board[1].progress, FA.TaskById.ConcordKillShaleCrawler.amount - 1, "other monsters do not count")
bridge.OnInvoke("kill", worker, {monster = "ShaleCrawler"})
local w1 = cmd(worker, "state").exploration.factions.list.Concord.board[1]
ok(w1.done, "kill task finished")
local gatherNode = prompt("gather", "Ore", Vector3.new(0, 0, 0))
standAt(worker, Vector3.new(0, 0, 0))
use(worker, gatherNode)
ok(cmd(worker, "state").exploration.factions.list.Concord.board[2].done, "gather task finished by a harvest")
-- Claims (unpledged: x0.6 reputation).
local c0 = cmd(worker, "state")
local combat0 = c0.xp.Combat
local claimOne = cmd(worker, "factionClaim", "Concord:1")
local r1 = FA.reward(FA.TaskById.ConcordKillShaleCrawler, "")
ok(has(claimOne.message, "claimed"), "task claimed")
eq(claimOne.exploration.factions.list.Concord.rep, r1.rep, "unpledged reputation")
eq(claimOne.exploration.factions.list.Concord.sigils, r1.sigils, "unpledged sigils")
ok(claimOne.coins >= c0.coins + r1.coins, "coins paid")
ok(claimOne.xp.Combat >= combat0 + r1.xp, "Combat XP paid")
ok(has(cmd(worker, "factionClaim", "Concord:1").message, "not finished"), "claim once")
ok(has(cmd(worker, "factionClaim", "Concord:3").message, "not finished"), "deliveries are not claimed")
ok(has(cmd(worker, "factionClaim", "Concord:9").message, "Unknown"), "bad slot")
ok(has(cmd(worker, "factionClaim", "Nope:1").message, "Unknown"), "bad faction")
-- Pledge, then claim all at x1.
local pl = cmd(worker, "factionPledge", "Concord")
ok(has(pl.message, "pledge"), "pledged")
eq(pl.exploration.factions.pledge, "Concord", "pledge in snapshot")
eq(worker.attrs.FactionPledge, "Concord", "pledge attribute")
local repBefore = pl.exploration.factions.list.Concord.rep
local all = cmd(worker, "factionClaim", "all")
eq(all.exploration.factions.list.Concord.rep, repBefore + FA.reward(FA.TaskById.ConcordGatherOre, "Concord").rep, "pledged reputation x1")
ok(has(cmd(worker, "factionClaim", "all").message, "No finished"), "claim all once")
-- Delivery: consumes the items, pays once.
leave(worker)
data["p9202"].profile.items.Ore = 5
worker = player(9202)
ok(has(cmd(worker, "factionDeliver", "Concord:3").message, "you have 5"), "delivery needs the items")
leave(worker)
data["p9202"].profile.items.Ore = 45
worker = player(9202)
local d0 = cmd(worker, "state")
local dcoins0 = d0.coins
local dl = cmd(worker, "factionDeliver", "Concord:3")
ok(has(dl.message, "Delivered"), "delivered")
eq(dl.items.Ore, 45 - FA.TaskById.ConcordDeliverOre.amount, "items consumed")
eq(dl.coins, dcoins0 + FA.TaskById.ConcordDeliverOre.coins, "delivery coins")
ok(has(cmd(worker, "factionDeliver", "Concord:3").message, "Already"), "deliver once")
eq(cmd(worker, "state").items.Ore, 45 - FA.TaskById.ConcordDeliverOre.amount, "no double consume")
ok(has(cmd(worker, "factionDeliver", "Concord:1").message, "not a delivery"), "kill slot is not a delivery")
-- Rival penalty after the pledge: the Circle (Concord's rival) earns x0.25.
bridge.OnInvoke("kill", worker, {monster = "Thornling"})
for _ = 2, FA.TaskById.CircleKillThornling.amount do bridge.OnInvoke("kill", worker, {monster = "Thornling"}) end
local rv = cmd(worker, "factionClaim", "Circle:1")
eq(rv.exploration.factions.list.Circle.rep, FA.reward(FA.TaskById.CircleKillThornling, "Concord").rep, "rival reputation x0.25")
eq(rv.exploration.factions.list.Circle.mult, 0.25, "rival multiplier shown")
-- Day roll: finished-unclaimed tasks are paid once, new boards drawn; never backwards.
local roller = seeded(9203, function(pr)
	setBoards(pr, {Concord = {{"ConcordGatherOre", FA.TaskById.ConcordGatherOre.amount}, {"ConcordGatherAetherite", 3}, {"ConcordDeliverOre"}}})
end)
local before = cmd(roller, "state").exploration.factions
advance(86400)
local after = cmd(roller, "state").exploration.factions
eq(after.day, before.day + 1, "new UTC day")
eq(after.list.Concord.rep, FA.reward(FA.TaskById.ConcordGatherOre, "").rep, "finished task auto-claimed at the reset")
for _, s in ipairs(after.list.Concord.board) do eq(s.progress, 0, "fresh task"); eq(s.claimed, false, "unclaimed") end
advance(86400)
eq(cmd(roller, "state").exploration.factions.list.Concord.rep, after.list.Concord.rep, "unfinished tasks are not paid")
local back = seeded(9204, function(pr) pr.factions.day = FA.dayOf(utc) + 5 end)
eq(cmd(back, "state").exploration.factions.day, FA.dayOf(utc) + 5, "a clock behind the saved day never redraws")
-- Switching: cooldown, cost, forfeit.
worker = player(9202)
ok(has(cmd(worker, "factionPledge", "Concord").message, "already"), "same pledge")
ok(has(cmd(worker, "factionPledge", "Corsairs").message, "holds"), "switch cooldown")
advance(FA.SWITCH_COOLDOWN)
leave(worker)
data["p9202"].profile.coins = 100
worker = player(9202)
ok(has(cmd(worker, "factionPledge", "Corsairs").message, "costs"), "switch needs coins")
leave(worker)
data["p9202"].profile.coins = FA.SWITCH_COST + 10
data["p9202"].profile.factions.rep.Concord = 1000
worker = player(9202)
local sw = cmd(worker, "factionPledge", "Corsairs")
ok(has(sw.message, "renounce"), "switched")
eq(sw.coins, 10, "switch cost paid")
eq(sw.exploration.factions.list.Concord.rep, 750, "a quarter of the old reputation forfeited")
eq(sw.exploration.factions.pledge, "Corsairs", "new pledge")
ok(has(cmd(worker, "factionPledge", "Concord").message, "holds"), "new cooldown")
ok(has(cmd(worker, "factionPledge", "Nope").message, "Unknown"), "unknown faction")
-- Shop.
local shopper = seeded(9205, function(pr)
	pr.factions.rep.Concord = 12000
	pr.factions.sigils.Concord = 2000
	pr.factions.pledge = "Concord"
	pr.factions.pledgedAt = utc
	pr.coins = 100000
	pr.xp.Mining = X[50]
end)
local sp = cmd(shopper, "factionBuy", "ConcordTitle1")
ok(has(sp.message, "title"), "title earned")
eq(shopper.attrs.FactionTitle, "Concord Journeyman", "title attribute")
eq(sp.exploration.factions.list.Concord.sigils, 2000 - FA.ShopById.ConcordTitle1.sigils, "title sigils spent")
ok(has(cmd(shopper, "factionBuy", "ConcordTitle1").message, "already"), "title once")
local lampXp = FA.lampXp("Mining", 50)
local l0 = cmd(shopper, "state")
local mining0 = l0.xp.Mining
local lamp = cmd(shopper, "factionBuy", "ConcordLamp:Mining")
ok(has(lamp.message, "lamp"), "lamp used")
ok(lamp.xp.Mining >= mining0 + lampXp, "lamp XP")
ok(has(cmd(shopper, "factionBuy", "ConcordLamp:Fishing").message, "Choose a skill"), "lamp skill gate")
ok(has(cmd(shopper, "factionBuy", "ConcordLamp").message, "Choose a skill"), "lamp needs a skill")
ok(has(cmd(shopper, "factionBuy", "ConcordCrest").message, "forged from"), "crest needs the charm")
local charm = cmd(shopper, "factionBuy", "ConcordCharm")
eq(charm.items.EmberwrightCharm, 1, "charm bought")
ok(charm.collection.EmberwrightCharm == 1, "charm credited through collect()")
cmd(shopper, "accessory", "EmberwrightCharm")
ok(has(cmd(shopper, "factionBuy", "ConcordCrest").message, "accessory bag"), "bagged charm protected")
cmd(shopper, "accessory", "EmberwrightCharm")
local sig = cmd(shopper, "state").exploration.factions.list.Concord.sigils
local crest = cmd(shopper, "factionBuy", "ConcordCrest")
ok(has(crest.message, "reforged"), "crest forged")
eq(crest.items.EmberwrightCharm, 0, "charm consumed")
eq(crest.items.EmberwrightCrest, 1, "crest granted")
eq(crest.exploration.factions.list.Concord.sigils, sig - FA.ShopById.ConcordCrest.sigils, "crest sigils")
ok(has(cmd(shopper, "factionBuy", "CircleLamp:Farming").message, "standing"), "other faction's rank gate")
ok(has(cmd(shopper, "factionTitle", "CircleTitle1").message, "do not hold"), "unowned title refused")
eq(cmd(shopper, "factionTitle", "none").exploration.factions.title, "", "title hidden")
eq(shopper.attrs.FactionTitle, "", "attribute cleared")
eq(cmd(shopper, "factionTitle", "ConcordTitle1").exploration.factions.titleText, "Concord Journeyman", "title worn again")
ok(has(cmd(shopper, "factionBoard", "Concord").message, "in person"), "board greeting is prompt-only")
standAt(shopper, Vector3.new(0, 0, 0))
ok(has(use(shopper, prompt("factionBoard", "Concord", Vector3.new(0, 0, 0))).message, "Luminary"), "board greeting shows the rank")
-- Migration bounds.
local tamper = seeded(9206, function(pr)
	pr.factions = {pledge = "Nope", rep = {Concord = 1e12, Circle = -5, Bogus = 9}, sigils = {Concord = "x"}, boards = {Concord = {{id = "Nope"}, {id = "CircleGatherHerb"}}},
		unlocks = {ConcordLamp = true, ConcordTitle2 = true, Fake = true}, title = "ConcordLamp", salt = 0}
end)
local t0 = cmd(tamper, "state").exploration.factions
eq(t0.pledge, "", "unknown pledge dropped")
eq(t0.list.Concord.rep, FA.REP_CAP, "reputation capped")
eq(t0.list.Circle.rep, 0, "negative reputation zeroed")
eq(t0.list.Concord.sigils, 0, "bad sigils zeroed")
eq(#t0.list.Concord.board, FA.TASKS, "foreign/unknown tasks dropped and the board redrawn")
for _, s in ipairs(t0.list.Concord.board) do eq(FA.TaskById[s.id].faction, "Concord", "board task belongs to its faction") end
eq(#t0.unlocks, 1, "only title unlocks survive")
eq(t0.title, "", "a non-title title dropped")
-- Bounded save size.
local big = seeded(9207, function(pr)
	pr.motes = {found = {}, steps = 0, regions = {}}
	for _, m in ipairs(EX.Motes) do pr.motes.found[m.id] = true end
end)
cmd(big, "state")
local saved = stored(big)
local function size(v)
	if type(v) == "table" then local n = 2 for k, x in pairs(v) do n += size(k) + size(x) + 2 end return n end
	return #tostring(v)
end
local bytes = size(saved.motes) + size(saved.factions)
ok(bytes < 4000, "worst-case Exploration & Factions save is small (" .. bytes .. " bytes)")
print("Worst-case Exploration & Factions save: ~" .. bytes .. " bytes")
-- Leave cleans the session table (no leaks): a fresh session may pick up at once.
big = player(9207)
eq(motesOf(cmd(big, "state")).count, EX.TOTAL, "every mote kept")
print("PASS: " .. (checks - partC) .. " Exploration & Factions server assertions.")

------------------------------------------------------------------------------
-- Part D: client mote layer.
------------------------------------------------------------------------------
local partD = checks
do
	roblox.implementMethod("Workspace", "WaitForChild", function(self, name) return self:FindFirstChild(name) end)
	local snapChannel, actionChannel = signal(), signal()
	snapChannel.Event, actionChannel.Event = snapChannel, actionChannel
	local fired = {}
	actionChannel.Fire = function(_, verb) table.insert(fired, verb) end
	local attrs = {}
	local root = {Position = Vector3.new(0, 5000, 0)}
	local localPlayer = {Character = {FindFirstChild = function() return root end}}
	function localPlayer:GetAttribute(k) return attrs[k] end
	local loops, render = {}, signal()
	local cenv = {
		game = {GetService = function(_, name)
			if name == "Players" then return {LocalPlayer = localPlayer} end
			if name == "ReplicatedStorage" then
				return {WaitForChild = function(_, n) return dataModule end,
					FindFirstChild = function(_, n) return if n == "IsleSnapshotLocal" then snapChannel elseif n == "IsleActionLocal" then actionChannel else nil end}
			end
			if name == "RunService" then return {RenderStepped = render} end
			return {}
		end},
		workspace = world, Instance = roblox.Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, UDim2 = roblox.UDim2, Enum = roblox.Enum,
		os = {clock = function() return clock end, time = function() return math.floor(utc) end},
		require = function() return Data end,
		task = {spawn = function(f) table.insert(loops, coroutine.create(f)) end, wait = function() coroutine.yield() end},
	}
	luau.load(fs.readFile("motes.client.lua"), {environment = cenv, injectGlobals = true})()
	eq(fired[1], "snapshot", "client asks for the latest snapshot")
	local folder = world:FindFirstChild("AetherMotesLocal")
	ok(folder ~= nil, "local mote folder")
	local function step() for _, co in ipairs(loops) do coroutine.resume(co) end render:Fire() end
	step()
	eq(#folder:GetChildren(), 0, "nothing drawn before the first snapshot")
	local bits = string.rep("0", EX.TOTAL)
	snapChannel:Fire({exploration = {motes = {found = bits}}})
	step()
	eq(#folder:GetChildren(), 0, "nothing drawn in the void")
	local m1 = hubMotes[1]
	root.Position = worldPos[m1.id] + Vector3.new(0, 1, 0)
	step()
	local drawn = #folder:GetChildren()
	ok(drawn >= 1 and drawn <= 20, "nearby motes drawn (" .. drawn .. ")")
	for _, part in ipairs(folder:GetChildren()) do
		ok(part:IsA("Part") and part.Anchored and not part.CanCollide and not part.CanQuery, "mote part is inert")
		local q = part:FindFirstChildOfClass("ProximityPrompt")
		ok(q ~= nil and q:GetAttribute("IsleAction") == "moteCollect", "mote prompt routes to moteCollect")
		local near = false
		for _, m in ipairs(EX.Motes) do if (worldPos[m.id] - part.CFrame.Position).Magnitude < 1 then near = (worldPos[m.id] - root.Position).Magnitude <= EX.RENDER_RADIUS end end
		ok(near, "only motes within the render radius")
	end
	-- Trigger: asks the field guide to send moteCollect and hides the mote at once.
	local closest, best = nil, 1e9
	for _, part in ipairs(folder:GetChildren()) do
		local d = (part.CFrame.Position - root.Position).Magnitude
		if d < best then closest, best = part, d end
	end
	closest:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(localPlayer)
	eq(fired[#fired], "moteCollect", "trigger sends moteCollect")
	step()
	eq(#folder:GetChildren(), drawn - 1, "picked mote hidden while the server answers")
	-- A found bitmap hides it for good.
	local found = string.sub(bits, 1, m1.index - 1) .. "1" .. string.sub(bits, m1.index + 1)
	snapChannel:Fire({exploration = {motes = {found = found}}})
	advance(5)
	step()
	for _, part in ipairs(folder:GetChildren()) do ok((part.CFrame.Position - worldPos[m1.id]).Magnitude > 1, "found mote never drawn") end
	-- Wayglass: the bearing target is drawn from any distance with a beacon.
	local far = EX.MoteById.Crown01
	attrs.MoteHint, attrs.MoteHintUntil = far.id, utc + 60
	step()
	local beacon
	for _, part in ipairs(folder:GetChildren()) do
		if (part.CFrame.Position - worldPos[far.id]).Magnitude < 1 then beacon = part:FindFirstChild("Bearing") end
	end
	ok(beacon ~= nil and beacon.Enabled and beacon.AlwaysOnTop, "bearing target drawn with a beacon")
	attrs.MoteHintUntil = utc - 1
	step()
	local still = false
	for _, part in ipairs(folder:GetChildren()) do if (part.CFrame.Position - worldPos[far.id]).Magnitude < 1 then still = true end end
	ok(not still, "expired bearing no longer drawn")
	-- Walking away releases every drawn mote (pooled, bounded).
	root.Position = Vector3.new(0, 5000, 0)
	step()
	eq(#folder:GetChildren(), 0, "all motes released")
end
print("PASS: " .. (checks - partD) .. " Exploration & Factions client assertions.")

------------------------------------------------------------------------------
-- Part E: Journal pages.
------------------------------------------------------------------------------
local partE = checks
local H = require("./tools/ui-harness")
local function sample()
	local snap = H.snapshot({xp = {Mining = X[20]}})
	snap.coins = 20000
	local bits = string.rep("0", EX.TOTAL)
	bits = "11111" .. string.sub(bits, 6)
	local regions = {}
	for _, r in ipairs(EX.RegionOrder) do regions[r] = {found = r == "Hub" and 5 or 0, total = EX.RegionTotal[r], claimed = false, allowed = r ~= "Skyreach"} end
	local list = {}
	for i, id in ipairs(FA.Order) do
		local board = {}
		local fixed = {Concord = {"ConcordGatherOre", "ConcordGatherAetherite", "ConcordDeliverOre"}, Circle = {"CircleKillThornling", "CircleGatherHerb", "CircleDeliverHerb"},
			Corsairs = {"CorsairsGatherFish", "CorsairsGatherGlassfin", "CorsairsDeliverFish"}}
		for j, tid in ipairs(fixed[id]) do
			local t = FA.TaskById[tid]
			board[j] = {id = tid, progress = j == 1 and t.amount or 0, claimed = false, done = j == 1, have = t.kind == "deliver" and 3 or nil, reward = FA.reward(t, "Concord")}
		end
		list[id] = {rep = i == 1 and 2400 or 100, sigils = i == 1 and 300 or 10, done = 4, rank = i == 1 and 3 or 1, rankName = i == 1 and "Sworn" or "Outsider", mult = FA.mult(id, "Concord"), board = board}
	end
	snap.exploration = {
		motes = {found = bits, count = 5, total = EX.TOTAL, steps = 0, claimable = 1, regions = regions, hintCost = EX.hintCost(5), hint = "Quay07", hintUntil = 0, stats = {}, agility = 1},
		factions = {pledge = "Concord", pledgedAt = 0, switchIn = 3600, resetIn = 3725, day = 20000, list = list, unlocks = {"ConcordTitle1"}, title = "ConcordTitle1", titleText = "Concord Journeyman", total = 12},
	}
	return snap
end
local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end end
	return table.concat(out, "\n")
end
local function atlas(size, mutate)
	local snap = sample()
	if mutate then mutate(snap) end
	local ui = H.runAtlas(size, {snapshot = snap})
	H.press(H.find(ui.gui, "AtlasButton"))
	return ui
end
local function open(ui, section)
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui.scroll, "Section" .. section:gsub("[^%w]", "")))
end
for _, size in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
	local tag = " at " .. size.X .. "x" .. size.Y
	local ui = atlas(size)
	open(ui, "Motes")
	eq(#ui.warnings, 0, "Motes renders without warnings" .. tag)
	ok(H.find(ui.scroll, "MotesSummary") ~= nil, "motes summary" .. tag)
	ok(H.find(ui.scroll, "MoteBearing") ~= nil, "bearing card" .. tag)
	ok(H.find(ui.scroll, "MoteMilestones") ~= nil, "milestones card" .. tag)
	for _, r in ipairs(EX.RegionOrder) do ok(H.find(ui.scroll, "MoteRegion" .. r) ~= nil, r .. " region card" .. tag) end
	open(ui, "Factions")
	eq(#ui.warnings, 0, "Factions renders without warnings" .. tag)
	ok(H.find(ui.scroll, "FactionsSummary") ~= nil, "factions summary" .. tag)
	for _, id in ipairs(FA.Order) do
		ok(H.find(ui.scroll, "Faction" .. id) ~= nil, id .. " card" .. tag)
		for i = 1, FA.TASKS do ok(H.find(ui.scroll, "FactionTask" .. id .. i) ~= nil, id .. " task " .. i .. tag) end
	end
	for _, e in ipairs(FA.Shop) do ok(H.find(ui.scroll, "FactionShop" .. e.id) ~= nil, e.id .. " shop row" .. tag) end
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768))
	local function pressSends(section, name, verb, item)
		open(ui, section)
		local before = #ui.sent
		local b = H.find(ui.scroll, name)
		ok(b ~= nil, name .. " exists")
		H.press(b)
		ok(#ui.sent > before, name .. " sends")
		eq(ui.sent[#ui.sent][1], verb, name .. " verb")
		eq(ui.sent[#ui.sent][2], item, name .. " payload")
	end
	pressSends("Motes", "MoteHint", "moteHint", nil)
	pressSends("Factions", "FactionClaimConcord1", "factionClaim", "Concord:1")
	pressSends("Factions", "FactionClaimAll", "factionClaim", "all")
	open(ui, "Factions")
	local held = #ui.sent
	H.press(H.find(ui.scroll, "FactionPledgeCircle"))
	eq(#ui.sent, held, "a switch inside the cooldown is not sent")
	pressSends("Factions", "FactionBuyConcordLampMining", "factionBuy", "ConcordLamp:Mining")
	pressSends("Factions", "FactionBuyConcordCharm", "factionBuy", "ConcordCharm")
	pressSends("Factions", "FactionTitleOffConcordTitle1", "factionTitle", "none")
	open(ui, "Factions")
	local text = texts(ui.scroll)
	ok(has(text, "Emberwright Concord") and has(text, "Thornveil Circle") and has(text, "Galewake Corsairs"), "faction names shown")
	ok(has(text, "PLEDGED") and has(text, "RIVAL"), "pledge and rival badges")
	ok(has(text, "1h 02m"), "reset timer")
	-- Locked rows stay local.
	local before = #ui.sent
	H.press(H.find(ui.scroll, "FactionBuyConcordCrest"))
	eq(#ui.sent, before, "locked crest not sent")
	open(ui, "Motes")
	text = texts(ui.scroll)
	ok(has(text, "5 / " .. EX.TOTAL), "found counter")
	ok(has(text, EX.MoteById.Quay07.hint), "bearing hint shown")
	ok(has(text, "LOCKED"), "locked region badge")
end
do
	local ui = atlas(roblox.Vector2.new(1366, 768), function(snap) snap.exploration.factions.pledge = "" end)
	open(ui, "Factions")
	local b = H.find(ui.scroll, "FactionPledgeCircle")
	ok(b ~= nil and H.find(ui.scroll, "FactionPledgeConcord") ~= nil, "unpledged: every faction offers a pledge")
	H.press(b)
	eq(ui.sent[#ui.sent][1], "factionPledge", "pledge verb")
	eq(ui.sent[#ui.sent][2], "Circle", "pledge payload")
end
do
	-- Unsynced snapshot: both pages render a syncing state without warnings.
	local ui = atlas(roblox.Vector2.new(844, 390), function(snap) snap.exploration = nil end)
	open(ui, "Motes")
	eq(#ui.warnings, 0, "Motes renders unsynced")
	open(ui, "Factions")
	eq(#ui.warnings, 0, "Factions renders unsynced")
end
print("PASS: " .. (checks - partE) .. " Exploration & Factions page assertions.")

------------------------------------------------------------------------------
-- Part F: balance model.
------------------------------------------------------------------------------
local partF = checks
do
	local CL = Data.CommissionsLogs
	local MG = Data.Minigames
	-- Commission time on the same model (kills / harvests + travel).
	local function seconds(kind, target, amount)
		if kind == "kill" then return FA.MODEL_TRAVEL + amount * 3600 / MG.SOLO.killsPerHour end
		local r = P.resource(target)
		return FA.MODEL_TRAVEL + amount * ((r and r.respawn or 3) + MG.SOLO.gatherOverhead)
	end
	local function rates(list, timeOf)
		local xp, coins, time = 0, 0, 0
		for _, t in ipairs(list) do xp += t.xp or 0; coins += t.coins or 0; time += timeOf(t) end
		return xp * 3600 / time, coins * 3600 / time, time
	end
	local cl = {}
	for _, t in ipairs(CL.Tasks) do if t.kind == "kill" or t.kind == "gather" then table.insert(cl, t) end end
	local fl = {}
	for _, t in ipairs(FA.Tasks) do if t.kind ~= "deliver" then table.insert(fl, t) end end
	local cxp, ccoins = rates(cl, function(t) return seconds(t.kind, t.target, t.amount) end)
	local fxp, fcoins = rates(fl, FA.taskSeconds)
	print(string.format("Bonus pay per hour of task time: commissions %.0f XP / %.0f coins; faction tasks %.0f XP / %.0f coins", cxp, ccoins, fxp, fcoins))
	ok(fxp <= cxp, "faction bonus XP/h below commissions")
	ok(fcoins <= ccoins, "faction bonus coins/h below commissions")
	-- A pledged day: three pledged + three neutral + three rival tasks.
	local repDay = 0
	for _, kind in ipairs(FA.KindOrder) do
		local base = ({kill = 120, gather = 100, deliver = 150})[kind]
		repDay += math.floor(base * 1) + math.floor(base * 0.6) + math.floor(base * 0.25)
	end
	local pledgedDay = 120 + 100 + 150
	local sigilDay = 12 + 10 + 15
	local daysTop = FA.Ranks[#FA.Ranks].at / pledgedDay
	local shopSigils = 0
	for _, e in ipairs(FA.Shop) do if e.faction == "Concord" and e.kind ~= "lamp" then shopSigils += e.sigils end end
	print(string.format("Pledged faction: %d rep/day -> Luminary in %.1f days; %d sigils/day -> every non-lamp reward in %.1f days; all factions %d rep/day",
		pledgedDay, daysTop, sigilDay, shopSigils / sigilDay, repDay))
	ok(daysTop >= 20 and daysTop <= 45, "Luminary takes three to six weeks of dailies")
	ok(shopSigils / sigilDay >= 15, "the shop is a multi-week goal")
	local avg = 0
	for _, t in ipairs(FA.Tasks) do avg += FA.taskSeconds(t) end
	avg /= #FA.Tasks
	print(string.format("Average faction task: %.1f minutes; nine a day = %.0f minutes", avg / 60, avg * 9 / 60))
	ok(avg * 9 / 60 <= 120, "a full faction day fits in two hours")
	-- Lamp vs Minigames lamp per hour of play.
	for _, lvl in ipairs({20, 50, 80}) do
		local lamp = FA.lampXp("Mining", lvl)
		print(string.format("  Faction lamp at %d: %d XP (Minigames lamp %d)", lvl, lamp, MG.lampXp("Combat", lvl)))
		ok(lamp < MG.lampXp("Combat", lvl), "faction lamp smaller than a Commendation lamp at " .. lvl)
	end
	-- Motes: total coins and stats against the Museum.
	local coins = 0
	for s = 1, EX.STEPS do coins += EX.stepCoins(s) end
	for _, r in ipairs(EX.RegionOrder) do coins += EX.regionCoins(r) end
	local museumHealth = 0
	for _, m in ipairs(CL.MuseumMilestones) do museumHealth += (m.stats.health or 0) end
	local stats = EX.perkStats(EX.STEPS, #EX.RegionOrder)
	print(string.format("All %d motes: %d coins total; +%d Health, +%d Defense, +%d Speed (Museum: +%d Health)", EX.TOTAL, coins, stats.health, stats.defense, stats.speed, museumHealth))
	ok(coins <= 100000, "mote coins are a one-off, under 100k")
	ok(stats.health <= museumHealth * 1.5, "mote Health within 1.5x the Museum's")
	local hints = 0
	for n = 0, EX.TOTAL - 1 do hints += EX.hintCost(n) end
	print(string.format("A Wayglass for every mote: %d coins (worst case)", hints))
	ok(hints < coins, "buying every bearing costs less than the motes pay")
end
print("PASS: " .. (checks - partF) .. " Exploration & Factions balance assertions.")
print("PASS: " .. checks .. " Exploration & Factions assertions in total.")
print("SUITE-END verify-exploration.luau")
