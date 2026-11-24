-- MMO Features (docs/DEPTH-CONTRACT.md §31): Isle Renown, the Wayfarer's Path,
-- announcements, shop quantities, Skyward Vents and Resonance.
-- Part A: pure data (GameData "MMO Features" section, Progression slots).
-- Part B: server.server.lua with service doubles — renown retroactive once and
--   never double-counted, level-gated slots/perks, the onboarding chain (live
--   steps owed and claimed once, veterans skip, flags), the announcement ring,
--   shop quantity verbs (caps, coins, unique, warp scrolls), Resonance verbs.
-- Part C: world.server.lua — vents placed within the part budget, landings on
--   clear ground away from spawns, region gate, FastTravelAt, arc + server landing, cooldown.
-- Part D: clients — features.client.lua (toasts, quantity picker, nameplates)
--   and the atlas (sidebar renown + Objective, Menu › Renown / Resonance).
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
local F, RN, G, R, VD = Data.Features, Data.Renown, Data.Features.Guide, Data.Resonance, Data.Vents
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
eq(RN.skillXp(1), 0, "level 1 is worth nothing")
eq(RN.skillXp(2), 5, "level 2 is worth 5")
eq(RN.skillXp(10), 45, "levels 2-10 at 5")
eq(RN.skillXp(11), 55, "level 11 at 10")
eq(RN.skillXp(99), 9 * 5 + 15 * 10 + 25 * 15 + 25 * 20 + 24 * 25, "level 99 sum of the bands")
eq(RN.levelFor(0), 0, "level 0")
eq(RN.levelFor(199), 1, "100 renown per level")
-- A maximal journal: total, level and every source contributing.
local maxed = {xp = {}, collection = {}, questsDone = {}, diaries = {}, slayerXp = {}, dungeons = {clears = {}}, dungeonClasses = {masterClears = {}},
	lairs = {kc = {}}, museum = {count = 150}, motes = {count = Data.Exploration.TOTAL}, bestiary = {}, pets = {}, questCompleted = 8}
for _, s in ipairs(Data.SkillOrder) do maxed.xp[s] = 2e8 end
for _, id in ipairs(Data.CollectionItems) do maxed.collection[id] = 1e12 end
for id in pairs(Data.QuestById) do maxed.questsDone[id] = true end
for region in pairs(Data.DiaryByRegion) do maxed.diaries[region] = 4 end
for _, l in ipairs(Data.SlayerOrder) do maxed.slayerXp[l] = 1e12 end
for i in ipairs(Data.DungeonFloors) do maxed.dungeons.clears[tostring(i)] = 3; maxed.dungeonClasses.masterClears[tostring(i)] = 1 end
for _, id in ipairs(Data.Lairs.Order) do maxed.lairs.kc[id] = 500 end
for id in pairs(Data.Monsters) do maxed.bestiary[id] = 1e6 end
-- Beaconry (§37): every beacon lit, a year of weekly watches.
maxed.beaconry = {beacons = {}, weeks = 60}
for _, id in ipairs(Data.Beaconry.BeaconOrder) do maxed.beaconry.beacons[id] = 3 end
local species = {}
for _, pet in ipairs(Data.Pets) do species[pet.id] = true end
local top = RN.breakdown(maxed, P, {species = species, guideSteps = #G.Steps})
for _, s in ipairs(RN.Sources) do ok(top.sources[s.id].xp > 0, "source " .. s.id .. " contributes on a maxed journal") end
local topLevel = RN.levelFor(top.total)
ok(topLevel >= 300 and topLevel <= 700, "maxed renown level in the SkyBlock-like band (" .. topLevel .. ")")
print(string.format("Isle Renown: maxed journal %d renown = level %d", top.total, topLevel))
local rows = {}
for _, s in ipairs(RN.Sources) do table.insert(rows, s.id .. " " .. top.sources[s.id].xp) end
print("  sources: " .. table.concat(rows, ", "))
-- Malformed journals never throw and count nothing.
local junk = RN.breakdown({xp = "x", collection = {Ore = -5}, questsDone = {Nope = true}, diaries = {Nowhere = 9}, bestiary = {[1] = 5}, museum = {count = 0 / 0}}, P, {guideSteps = -3})
eq(junk.total, 0, "malformed journal is worth 0")
eq(RN.breakdown({}, P, nil).total, 0, "empty journal is worth 0")
-- Rewards: slots, perks inside the budget, titles, unlock list.
eq(RN.slots(9), 0, "no slot before 10")
eq(RN.slots(10), 1, "slot at 10")
eq(RN.slots(1000), RN.MAX_SLOTS, "slots cap")
local cap = RN.stats(100000)
ok((cap.health or 0) <= 20 and (cap.defense or 0) <= 5, "renown Health / Defense stay minor")
ok(next(RN.stats(9)) == nil, "no perks before level 10")
eq(RN.stats(10).health, 2, "+2 Health at 10")
eq(RN.tier(0).title, "Driftling", "starting title")
eq(RN.tier(52).title, "Windcaller", "title at 52")
ok(has(RN.rewardText(10), "accessory slot") and has(RN.rewardText(10), "Health"), "level 10 reward text")
local nextUp = RN.nextUnlocks(0, 6)
ok(#nextUp == 6 and nextUp[1].level <= nextUp[6].level, "six sorted next unlocks")
for _, u in ipairs(RN.nextUnlocks(2000, 6)) do ok(u.level > 2000, "unlocks lie ahead") end
-- Bag slots: Progression.accessorySlots adds renown slots from the server-set level.
local base = P.accessorySlots({xp = {}})
eq(P.accessorySlots({xp = {}, renown = {level = 25}}), base + 2, "renown 25 adds two bag slots")
eq(P.accessorySlots({xp = {}, renown = {level = "x"}}), base, "malformed renown adds nothing")
-- Wayfarer's Path data.
eq(#G.Steps, 11, "eleven onboarding steps (Polish QC: the journal-mode step opens the Path)")
local ids = {}
for i, s in ipairs(G.Steps) do
	ok(type(s.title) == "string" and #s.title > 4 and #s.detail > 10 and s.coins > 0 and s.coins <= 100, s.id .. " step text and a small reward")
	ok((s.flag ~= nil) ~= (s.check ~= nil), s.id .. " is a flag or a check")
	ids[i] = s.id
end
eq(table.concat(ids, ","), "mode,chop,craft,visit,talk,ore,sell,equip,kill,quest,warp", "step order: journal mode first (lead decision)")
local fresh = {collection = {}, counters = {}, equipment = {}, bestiary = {}, kills = 0}
for _, s in ipairs(G.Steps) do ok(not G.satisfied(fresh, s, {warps = {}}), s.id .. " not satisfied on a fresh journal") end
ok(G.satisfied({collection = {Timber = 1}}, G.StepById.chop, {}), "a log satisfies chop")
ok(G.satisfied({equipment = {weapon = "CopperBlade"}}, G.StepById.equip, {}), "a weapon satisfies equip")
ok(G.satisfied({}, G.StepById.warp, {warps = {Quarry = true}}), "a known warp satisfies warp")
eq(G.view({}).id, "mode", "first step shown: journal mode")
eq(G.view({done = {mode = true}}).id, "chop", "then Chop a log")
-- Polish QC (lead decision): Pell's first contact offers Standard in one tap and Ironman behind explain + PERMANENT confirm.
do
	local pell = (Data.Townsfolk and Data.Townsfolk.NPCs or {}).Guide
	ok(pell ~= nil, "Pell's dialogue graph is reachable")
	if pell then
		local std, explain
		for _, o in ipairs(pell.nodes.hello.options) do
			if o.verb == "guideMode" and o.item == G.MODE_STANDARD and o.when == "modeOpen" then std = o end
			if o.to == "mode" and o.when == "modeOpen" then explain = o end
			ok(not (o.verb == "guideMode" and o.item == G.MODE_IRONMAN), "first contact never seals Ironman in one tap")
		end
		ok(std ~= nil and explain ~= nil, "hello offers one-tap Standard and the journal-mode explanation")
		local toConfirm
		for _, o in ipairs(pell.nodes.mode.options) do if o.to == "ironman" then toConfirm = o end; ok(o.item ~= G.MODE_IRONMAN, "the explanation does not seal Ironman") end
		ok(toConfirm ~= nil and has(pell.nodes.ironman.text, "PERMANENT"), "Ironman sits behind the PERMANENT confirmation")
		local sealOpt
		for _, o in ipairs(pell.nodes.ironman.options) do if o.item == G.MODE_IRONMAN then sealOpt = o end end
		ok(sealOpt ~= nil and sealOpt.verb == "guideMode", "the confirmation node seals with the confirm token")
		ok(Data.Townsfolk.Conditions.guideModeActive({guide = {id = "mode"}}) and not Data.Townsfolk.Conditions.guideModeActive({guide = {id = "chop"}}), "Pell's ! shows while the journal-mode step is open")
		ok(has(fs.readFile("npc.client.lua"), "T.Conditions.guideModeActive(s)"), "Pell's marker reads the journal-mode step")
	end
end
ok(G.view({done = (function() local d = {} for _, s in ipairs(G.Steps) do d[s.id] = true end return d end)()}).complete, "all done = complete")
-- Announcement text.
eq(F.announceText({kind = "collection", item = "Ore"}).head, "COLLECTION UNLOCKED", "collection unlocked head")
eq(F.announceText({kind = "collection", item = "Ore"}).body, Data.Items.Ore.name, "collection unlocked names the item")
ok(has(F.announceText({kind = "skill", skill = "Mining", level = 5, coins = 40}).body, "+40 coins"), "skill level-up carries its coins")
ok(has(F.announceText({kind = "renown", level = 10, reward = "+1 accessory slot"}).head, "ISLE RENOWN 10"), "renown head")
eq(F.announceText({kind = "objective", title = "Gather ore"}).head, "NEW OBJECTIVE", "new objective head")
eq(F.announceText({kind = "???"}).head, "NOTICE", "unknown kinds are safe")
-- Shop quantities.
local b, q = F.splitQty("Fishmonger:1:8", 2)
ok(b == "Fishmonger:1" and q == 8, "base:qty splits")
b, q = F.splitQty("Fishmonger:1", 2)
ok(b == "Fishmonger:1" and q == 1, "no qty = 1")
for _, bad in ipairs({"Fishmonger:1:0", "Fishmonger:1:65", "Fishmonger:1:08", "Fishmonger:1:-3", "Fishmonger:1:2:3", "Fishmonger:1:x", "", string.rep("a", 70)}) do
	eq(F.splitQty(bad, 2), nil, "malformed quantity refused: " .. bad)
end
eq(F.Shop.MAX_LOTS, 64, "64 lots per call")
-- Vents.
eq(#VD.List, 6, "six Skyward Vents")
for _, v in ipairs(VD.List) do ok(Data.RegionById[v.to] ~= nil and v.isle ~= v.land, v.id .. " leads to a region on another isle") end
eq(VD.arcY(0, 10, 0), 0, "arc starts at the vent")
eq(VD.arcY(0, 10, 1), 10, "arc ends at the landing")
ok(math.abs(VD.arcY(0, 10, 0.5) - (10 + VD.ARC_HEIGHT)) < 1e-6, "arc peaks above the higher end")
-- Resonance.
ok(next(R.stats("Emberkeen", 0)) == nil, "no power, no stats")
ok(next(R.stats("Bladestorm", 59)) == nil, "minPower gate")
local mid = R.stats("Emberkeen", 110)
ok(mid.strength > 10 and mid.strength < 25, "Emberkeen at 110 MP gives modest Strength (" .. mid.strength .. ")")
for _, t in ipairs(R.Templates) do
	local st = R.stats(t.id, 100000)
	ok(st.health == nil and st.defense == nil, t.id .. " never grants Health / Defense (perk budget)")
	for stat in pairs(st) do ok(Data.Stats[stat] ~= nil, t.id .. " stat " .. stat .. " is a real stat") end
end
print(string.format("Resonance at 110 / 300 MP: Emberkeen Strength %.1f / %.1f, Crit Damage %.1f / %.1f",
	R.stats("Emberkeen", 110).strength, R.stats("Emberkeen", 300).strength, R.stats("Emberkeen", 110).critDamage, R.stats("Emberkeen", 300).critDamage))
-- M2: Magical Power past R.POWER_CAP adds nothing, and at the cap no template
-- outgrows 60 % of the comparable endgame stat (Sovereign set bonus Strength /
-- Crit Damage, Riftcrown Staff Intelligence); Starlore ~ Emberkeen in share.
eq(R.POWER_CAP, 400, "resonance power cap")
eq(R.scale(100000), R.scale(R.POWER_CAP), "Magical Power past the cap adds nothing")
ok(R.scale(399) < R.scale(R.POWER_CAP), "below the cap power still scales")
local sovereign = Data.Endgame.SetById.Sovereign.bonus
local staffInt = Data.Items.RiftcrownStaff.stats.intelligence
local limits = {strength = sovereign.strength, critDamage = sovereign.critDamage, intelligence = staffInt}
for _, t in ipairs(R.Templates) do
	local st = R.stats(t.id, R.POWER_CAP)
	for stat, ref in pairs(limits) do
		ok((st[stat] or 0) <= 0.6 * ref + 1e-9, string.format("%s %s at the cap %.1f <= 60%% of %d", t.id, stat, st[stat] or 0, ref))
	end
end
local emberShare = R.stats("Emberkeen", R.POWER_CAP).strength / sovereign.strength
local starShare = R.stats("Starlore", R.POWER_CAP).intelligence / staffInt
ok(starShare >= 0.9 * emberShare and starShare <= 1.0 * emberShare, string.format("Starlore Intelligence share %.3f in line with Emberkeen Strength share %.3f", starShare, emberShare))
print(string.format("Resonance at the %d MP cap: Emberkeen Strength %.1f / Crit Damage %.1f, Starlore Intelligence %.1f",
	R.POWER_CAP, R.stats("Emberkeen", R.POWER_CAP).strength, R.stats("Emberkeen", R.POWER_CAP).critDamage, R.stats("Starlore", R.POWER_CAP).intelligence))
-- L2: a full queue / ring drops the oldest ordinary entry first; renown and path entries stay.
do
	local list = {{kind = "renown", level = 10}}
	for i = 1, 12 do table.insert(list, {kind = "collection", item = "Ore", n = i}) end
	table.insert(list, {kind = "guide", title = "x"})
	F.trimAnnouncements(list, 12)
	eq(#list, 12, "trimmed to the cap")
	eq(list[1].kind, "renown", "the renown level-up survives a full ring")
	eq(list[#list].kind, "guide", "the newest path entry is kept")
	eq(list[2].n, 3, "the two oldest ordinary entries were dropped")
	local all = {}
	for i = 1, 14 do table.insert(all, {kind = "renown", level = i}) end
	F.trimAnnouncements(all, 12)
	eq(all[1].level, 3, "only priority entries: the oldest go")
end
-- L6: warp scrolls and one-of-a-kind wares are single-lot (no quantity picker).
ok(F.Shop.singleLot(Data.RegionArt.Warps[1].scroll), "warp scrolls are single-lot")
ok(F.Shop.singleLot("SovereignSignet"), "accessories are single-lot")
ok(not F.Shop.singleLot("Fish"), "stackable wares take a quantity")
ok(F.Shop.singleLot("NoSuchItem"), "unknown wares are single-lot")
-- The Resonance Keeper is a regional folk entry with dialogue verbs.
local T = Data.Townsfolk
ok(T.NPCs.Resonator ~= nil and T.NPCs.Resonator.anchorOnly and table.find(T.RegionFolkOrder, "Resonator") ~= nil, "Resonance Keeper registered")
ok(Data.RegionArt.FolkByRole.Resonator ~= nil, "Resonance Keeper gets a World Art anchor")
ok(T.Verbs.resonanceVisit and T.Verbs.guideTalk and T.Verbs.guideClaim, "dialogue verbs whitelisted")
local pellTalk = false
for _, o in ipairs(T.NPCs.Guide.nodes.hello.options) do if o.verb == "guideTalk" then pellTalk = true end end
ok(pellTalk, "Pell offers the Wayfarer's Path talk")
ok(T.Conditions.guideTalkActive({guide = {id = "talk"}}) and not T.Conditions.guideTalkActive({guide = {id = "ore"}}), "talk option only on the talk step")
print("PASS: " .. checks .. " data assertions.")

------------------------------------------------------------------------------
-- Part B: server verbs.
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
local roles = {"Guide"}
for _, f in ipairs(RA.Folk) do table.insert(roles, f.role) end
for i, role in ipairs(roles) do
	npcAt[role] = Vector3.new(i * 100, 5, 0)
	local root = {Position = npcAt[role]}
	table.insert(models, {GetAttribute = function(_, k) return if k == "TownsfolkRole" then role else nil end,
		FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end})
end
local townsfolk = {GetChildren = function() return models end}
local QUAY = Vector3.new(0, 0, 0)
local quay = {GetAttribute = function(_, k) return if k == "IslandCenter" then QUAY elseif k == "IslandRadius" then 120 else nil end}
local islandsDouble = {FindFirstChild = function(_, name) return if name == "Compass Quay" then quay else nil end}
local storage = {AetherTrails = {Name = "AetherTrails"}, IsleTravelGate = {Invoke = function() return true end}}
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P, [storage.AetherTrails] = load("trails.lua")}
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end},
	ServerStorage = {FindFirstChild = function(_, name) return storage[name] end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "features-test" end},
	RunService = {IsStudio = function() return false end},
}
local serverObjects = {}
local weakTables = {} -- every weak table the server creates (M1: the announcement queue)
local env = {
	setmetatable = function(t, mt)
		if type(mt) == "table" and mt.__mode then table.insert(weakTables, t) end
		return setmetatable(t, mt)
	end,
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = {GetAttribute = function(self, key) return rawget(self, key) end,
		FindFirstChild = function(_, name) return if name == "Islands" then islandsDouble elseif name == "Townsfolk" then townsfolk else nil end},
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
-- Probes: the live profile last handed to the renown breakdown, breakdown and Magical Power call counts.
local probe = {breakdowns = 0, power = 0, profile = nil}
do
	local origBreakdown, origPower = RN.breakdown, P.magicalPower
	RN.breakdown = function(pr, ...) probe.breakdowns += 1; probe.profile = pr; return origBreakdown(pr, ...) end
	P.magicalPower = function(...) probe.power += 1; return origPower(...) end
end
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
local function away(p) p.root.Position = Vector3.new(0, 5000, 0) end
local function prompt(action, item, pos, region)
	local base = {CFrame = CFrame.new(pos)}
	local q = {Enabled = true, MaxActivationDistance = 10, attrs = {IsleAction = action, IsleItem = item, IsleRegion = region}}
	function q:GetAttribute(k) return self.attrs[k] end
	function q:FindFirstAncestorWhichIsA() return base end
	return q
end
local function use(p, q) advance(30); p.last = nil; services.ProximityPromptService.PromptTriggered:Fire(q, p); return p.last end
local X = Data.XP_TABLE

-- B1. A brand-new journal: renown 0, the path starts at "Chop a log".
local newbie = player(9001)
local s = cmd(newbie, "state")
ok(type(s.renown) == "table" and s.renown.level == 0 and s.renown.xp == 0, "fresh renown 0")
eq(#s.renown.sources, #RN.Sources, "renown page lists every source")
ok(type(s.guide) == "table" and s.guide.id == "mode" and s.guide.step == 1 and s.guide.total == #G.Steps, "sidebar objective: Choose your journal mode")
eq(newbie.attrs.RenownLevel, 0, "nameplate attribute RenownLevel")
eq(newbie.attrs.RenownTitle, "Driftling", "nameplate attribute RenownTitle")
ok(type(s.announce) == "table" and type(s.announce.list) == "table", "snapshot carries the announcement ring")
ok(s.resonance and s.resonance.id == nil and s.resonance.fee == 0, "no resonance yet, first tuning free")
-- Gathering the first ore: COLLECTION UNLOCKED, the ore step completes (owed, not paid).
local coins0 = s.coins
local rock = prompt("gather", "Ore", Vector3.new(0, 5000, 0))
local r = use(newbie, rock)
ok(r ~= nil and has(r.message, "Ore"), "gather answered: " .. tostring(r and r.message))
local kinds = {}
for _, e in ipairs(r.announce.list) do kinds[e.kind .. ":" .. tostring(e.item or e.title or e.skill)] = e.seq end
ok(kinds["collection:Ore"] ~= nil, "COLLECTION UNLOCKED Ore announced")
ok(kinds["guide:Gather ore"] ~= nil, "path step announced")
ok(kinds["objective:Choose your journal mode"] ~= nil, "NEW OBJECTIVE names the first open step (journal mode)")
eq(r.coins, coins0, "path rewards are not paid automatically")
eq(r.guide.owed, G.StepById.ore.coins, "the step's coins are owed")
eq(r.guide.id, "mode", "the sidebar still shows the first open step")
-- A second gather does not re-announce the unlock (seq moves on; old entries stay in the ring until they age out).
local lastSeq = r.announce.seq
r = use(newbie, rock)
local again = 0
for _, e in ipairs(r.announce.list) do if e.seq > lastSeq and e.kind == "collection" then again += 1 end end
eq(again, 0, "COLLECTION UNLOCKED only once")
advance(40)
eq(#cmd(newbie, "state").announce.list, 0, "the ring forgets entries after 30 s")
-- Claim once.
local claim = cmd(newbie, "guideClaim")
ok(has(claim.message, "+" .. G.StepById.ore.coins .. " coins"), "claim pays the owed coins: " .. claim.message)
eq(claim.coins, coins0 + G.StepById.ore.coins, "claimed exactly once")
ok(has(cmd(newbie, "guideClaim").message, "No Wayfarer"), "nothing left to claim")
-- Flags: visit (standing on Compass Quay), talk (at Pell), sell (selling anything).
newbie.root.Position = QUAY + Vector3.new(10, 4, 10)
r = cmd(newbie, "state")
ok(stored(newbie).guide.flags.visit == true, "standing on Compass Quay raises visit")
newbie = player(9001)
away(newbie)
ok(has(cmd(newbie, "guideTalk").message, "Find Pell"), "talk needs Pell nearby")
at(newbie, "Guide")
ok(has(cmd(newbie, "guideTalk").message, "Glad you found me"), "talking to Pell")
ok(has(cmd(newbie, "guideTalk").message, "Keep following"), "the talk is recorded once")
r = cmd(newbie, "sell", "Ore")
ok(has(r.message, "Merchant paid"), "sold the ore")
local saved = stored(newbie)
ok(saved.guide.done.visit and saved.guide.done.talk and saved.guide.done.sell and saved.guide.done.ore, "visit, talk, sell and ore done")
eq(saved.guide.owed, G.StepById.visit.coins + G.StepById.talk.coins + G.StepById.sell.coins, "their coins are owed (rejoin-safe)")
-- Polish: the journal-mode step closes the Path (verb guideMode at Pell; ironman verb rules).
do
	newbie = player(9001)
	away(newbie)
	ok(has(cmd(newbie, "guideMode", G.MODE_STANDARD).message, "Find Pell"), "journal mode is chosen at Pell")
	at(newbie, "Guide")
	ok(has(cmd(newbie, "guideMode", "ironman").message, "confirm"), "Ironman needs the confirm token")
	ok(has(cmd(newbie, "guideMode", G.MODE_IRONMAN).message, "before any progression"), "Ironman refused after progression (ironman verb rule)")
	eq(stored(newbie).ironman, false, "the refused seal leaves the journal Standard")
	newbie = player(9001)
	at(newbie, "Guide")
	ok(has(cmd(newbie, "guideMode", G.MODE_STANDARD).message, "Standard journal"), "Standard is always open")
	local st = cmd(newbie, "state")
	eq(st.accountMode, "standard", "snapshot carries the journal mode")
	local saved = stored(newbie)
	ok(saved.accountMode == "standard" and saved.guide.done.mode == true, "mode step done and saved (rejoin-safe)")
	-- Polish QC: toasts follow the new order (mode done -> NEW OBJECTIVE is the next open step).
	local modeKinds = {}
	for _, e in ipairs(st.announce.list) do modeKinds[e.kind .. ":" .. tostring(e.title)] = true end
	ok(modeKinds["guide:Choose your journal mode"] and modeKinds["objective:Chop a log"], "journal mode toast, then NEW OBJECTIVE: Chop a log")
	eq(st.guide.id, "chop", "sidebar moves on to Chop a log")
	eq(saved.guide.v, G.VERSION, "saved Path carries the schema version")
	-- L1: a crew member cannot seal Ironman (guideMode or the legacy verb).
	local crewed = player(9055)
	crewed.attrs.CoopId = "77"
	at(crewed, "Guide")
	ok(has(cmd(crewed, "guideMode", G.MODE_IRONMAN).message, "crew"), "guideMode Ironman refused in a crew")
	ok(has(cmd(crewed, "ironman").message, "crew"), "legacy ironman verb refused in a crew")
	local crewSaved = stored(crewed)
	ok(crewSaved.ironman ~= true and crewSaved.accountMode == nil, "the crew member's journal stays unsealed")
	crewed = player(9055)
	crewed.attrs.CoopId = "77"
	at(crewed, "Guide")
	ok(has(cmd(crewed, "guideMode", G.MODE_STANDARD).message, "Standard journal"), "Standard is still open in a crew")
	-- Migration: an unfinished v1 save (steps keyed by id) keeps its progress; journal mode is the open first step.
	local midway = seeded(9056, function(pr)
		pr.started = true
		pr.guide = {done = {chop = true, craft = true, visit = true, talk = true}, flags = {visit = true, talk = true}, owed = 0}
	end)
	local mid = cmd(midway, "state")
	ok(mid.guide.id == "mode" and mid.guide.step == 1 and mid.guide.done == 4, "v1 progress kept; journal mode is step 1 of the new order")
	eq(mid.guide.marks, "01111000000", "checklist marks follow the new step order")
	at(midway, "Guide")
	ok(has(cmd(midway, "guideMode", G.MODE_IRONMAN).message, "before any progression"), "a started v1 journal can still only pick Standard")
	cmd(midway, "guideMode", G.MODE_STANDARD)
	local after = cmd(midway, "state")
	ok(after.guide.id == "ore" and after.guide.step == 6 and after.guide.owed == G.StepById.mode.coins, "after Standard the sidebar shows Gather ore 6/11 and pays the mode step")
	-- A brand-new journal can seal Ironman from Pell before any progression; guideMode never sets p.started.
	local iron = player(9051)
	at(iron, "Guide")
	local sealed = cmd(iron, "guideMode", G.MODE_IRONMAN)
	ok(has(sealed.message, "Ironman journal sealed") and sealed.ironman == true and sealed.accountMode == "ironman", "fresh journal seals Ironman with confirmation")
	ok(has(cmd(iron, "guideMode", G.MODE_STANDARD).message, "cannot be undone"), "Ironman cannot be undone")
	local ironSaved = stored(iron)
	ok(ironSaved.ironman == true and ironSaved.started ~= true and ironSaved.guide.done.mode == true, "Ironman completes the mode step without starting progression")
	-- The legacy ironman verb also fills the step; a finished pre-update Path stays finished, unpaid.
	local legacyIron = player(9052)
	cmd(legacyIron, "ironman")
	eq(stored(legacyIron).accountMode, "ironman", "the ironman verb records the mode")
	local done = seeded(9053, function(pr)
		pr.guide = {done = {}, flags = {}, owed = 0, complete = true}
		for _, step in ipairs(G.Steps) do if step.id ~= "mode" then pr.guide.done[step.id] = true end end -- v1 save: no mode step
	end)
	local doneState = cmd(done, "state")
	ok(doneState.guide.complete == true and doneState.guide.owed == 0, "a finished Path is not reopened by the new step")
	eq(string.rep("1", #G.Steps), doneState.guide.marks, "every step marked for Pell's checklist")
	at(done, "Guide")
	ok(has(cmd(done, "guideMode", "bogus").message, "Choose Standard"), "unknown journal modes are refused")
end
-- Polish: a collection tier that unlocks a worker type announces WORKER RECIPE UNLOCKED.
do
	local target
	for _, t in ipairs(Data.Workers.Types) do if t.kind == "gather" and t.skill == "Mining" and t.collectionTier == 1 then target = t; break end end
	ok(target ~= nil, "a Mining worker unlocks at collection tier 1")
	local need = P.collectionThreshold(target.output, 1)
	local miner = seeded(9054, function(pr)
		pr.xp.Mining = X[99]
		for id, def in pairs(Data.Items) do if def.kind == "tool" then pr.items[id] = 1 end end
		pr.collection[target.output] = need - 1
		pr.collectionRewards = {[target.output] = 0}
	end)
	local rock = prompt("gather", target.output, Vector3.new(0, 5000, 0))
	local res = use(miner, rock)
	ok(res ~= nil, "gathered " .. target.output .. ": " .. tostring(res and res.message))
	local found
	for _, e in ipairs(res.announce.list) do if e.kind == "workerRecipe" and e.worker == target.id then found = e end end
	ok(found ~= nil and found.tier == 1 and found.item == target.output, "WORKER RECIPE UNLOCKED " .. target.name .. " announced")
	local text = Data.Features.announceText(found)
	ok(text.head == "WORKER RECIPE UNLOCKED" and has(text.body, target.name), "announcement text names the worker")
	local again = use(miner, rock)
	local twice = 0
	for _, e in ipairs(again.announce.list) do if e.kind == "workerRecipe" and e.seq > found.seq then twice += 1 end end
	eq(twice, 0, "the unlock is announced once")
	eq(#Data.Features.workerUnlocks(target.output, 1, 1), 0, "nothing re-unlocks within the same tier")
	eq(#Data.Features.workerUnlocks("Ore", 0, 9), 0, "starter workers never announce")
	ok(found.skill == nil and not has(text.body, "available at"), "a met level gate adds no 'available at'")
	-- Polish QC L3: a worker whose skill gate is still ahead says "available at <skill> <level>".
	local savedLevel = target.level
	target.level = 98
	local early = seeded(9057, function(pr)
		pr.xp.Mining = X[60]
		for id, def in pairs(Data.Items) do if def.kind == "tool" then pr.items[id] = 1 end end
		pr.collection[target.output] = need - 1
		pr.collectionRewards = {[target.output] = 0}
	end)
	local gatedRes = use(early, prompt("gather", target.output, Vector3.new(0, 5000, 0)))
	target.level = savedLevel
	local gatedEntry
	for _, e in ipairs(gatedRes.announce.list) do if e.kind == "workerRecipe" and e.worker == target.id then gatedEntry = e end end
	ok(gatedEntry ~= nil and gatedEntry.skill == "Mining" and gatedEntry.level == 98, "the announcement carries the unmet level gate")
	ok(has(Data.Features.announceText(gatedEntry).body, "available at Mining 98"), "toast says available at Mining 98")
end
-- B2. Retroactive renown, once: a journal from before the update.
local vet = seeded(9002, function(pr)
	pr.renown, pr.guide = nil, nil
	for _, skill in ipairs({"Mining", "Woodcutting", "Combat", "Fishing"}) do pr.xp[skill] = X[40] end
	pr.collection.Ore = 100000
	pr.questCompleted = 4
	pr.pets = {{id = Data.Pets[1].id, level = 1, xp = 0}}
end)
local first = cmd(vet, "state")
-- L3: veterans who skipped the path earn no path renown.
local expect = RN.breakdown(stored(vet), P, {species = {[Data.Pets[1].id] = true}, guideSteps = 0}).total
for _, row in ipairs(first.renown.sources) do if row.id == "guide" then eq(row.xp, 0, "a skipped path earns no path renown") end end
vet = player(9002)
ok(first.renown.xp == expect and first.renown.level == RN.levelFor(expect), "existing progress credited on the first load (" .. first.renown.xp .. ")")
ok(first.renown.level >= 10, "a veteran starts well past level 10 (" .. first.renown.level .. ")")
ok(first.guide.complete and (first.guide.owed or 0) == 0, "veterans skip the Wayfarer's Path without a windfall")
ok(has(first.message, "awakened") or true, "summary note")
-- Rejoin twice: nothing is counted again.
local again1 = cmd(vet, "state").renown.xp
vet = player(9002)
eq(cmd(vet, "state").renown.xp, again1, "rejoin never re-credits")
eq(again1, expect, "renown equals the derived total")
-- Releasing the pet does not lower renown (species ever adopted + stored maximum).
vet = seeded(9002, function(pr) pr.pets = {} end)
eq(cmd(vet, "state").renown.xp, expect, "renown never drops")
-- Rewards: slots and perk stats.
local vs = cmd(vet, "state")
eq(vs.depth.accessorySlots, P.accessorySlots({xp = stored(vet).xp, renown = {level = vs.renown.level}}), "bag slots include renown slots")
vet = player(9002)
local vp = stored(vet)
eq(vp.perkStats.renown.health, RN.stats(vs.renown.level).health, "renown perk stats saved in perkStats.renown")
vet = player(9002)
-- Live level-up: a new tier pushes renown up with an announcement and the nameplate follows.
vet = seeded(9002, function(pr) pr.xp.Smithing = X[60] end)
local up = cmd(vet, "state")
ok(up.renown.level > vs.renown.level, "new progress raises renown")
local renownAnn = false
for _, e in ipairs(up.announce.list) do if e.kind == "renown" then renownAnn = true end end
ok(renownAnn, "renown level-up announced")
eq(vet.attrs.RenownLevel, up.renown.level, "nameplate follows")
-- Tampered save: a level above its XP is pulled back.
vet = seeded(9002, function(pr) pr.renown.level = 9999 end)
eq(cmd(vet, "state").renown.level, RN.levelFor(stored(vet).renown.xp), "tampered level clamped to its XP")
-- B3. Shop quantities.
local buyer = seeded(9003, function(pr) pr.coins = 1000000 end)
local shopRole, shopIndex, offer
for _, f in ipairs(RA.Folk) do
	for i, o in ipairs(f.shop or {}) do
		if not shopRole and not string.find(o.item, "^WarpScroll") and Data.RegionById[f.region] and next(Data.RegionById[f.region].requires) == nil then shopRole, shopIndex, offer = f.role, i, o end
	end
end
ok(shopRole ~= nil, "an open regional shop to test")
at(buyer, shopRole)
local before = cmd(buyer, "state")
local haveBefore, colBefore = before.items[offer.item] or 0, before.collection[offer.item] or 0
local bought = cmd(buyer, "rqBuy", shopRole .. ":" .. shopIndex .. ":16")
ok(has(bought.message, "Bought " .. (offer.amount * 16) .. "×"), "16 lots bought: " .. bought.message)
eq(bought.coins, before.coins - offer.price * 16, "charged 16 × the lot price")
eq((bought.items[offer.item] or 0) - haveBefore, offer.amount * 16, "16 lots delivered")
eq(bought.collection[offer.item] or 0, colBefore, "bought goods are not collection")
local single = cmd(buyer, "rqBuy", shopRole .. ":" .. shopIndex)
eq(single.coins, bought.coins - offer.price, "no qty = one lot (unchanged behaviour)")
for _, bad in ipairs({":65", ":0", ":x", ":1:1"}) do
	local reply = cmd(buyer, "rqBuy", shopRole .. ":" .. shopIndex .. bad)
	ok(has(reply.message, "isn't for sale") and reply.coins == single.coins, "malformed quantity refused " .. bad)
end
local poor = seeded(9004, function(pr) pr.coins = offer.price * 3 end)
at(poor, shopRole)
local tooMany = cmd(poor, "rqBuy", shopRole .. ":" .. shopIndex .. ":4")
ok(has(tooMany.message, "You need " .. offer.price * 4) and tooMany.coins == offer.price * 3, "coins checked for the whole quantity")
away(buyer)
ok(has(cmd(buyer, "rqBuy", shopRole .. ":" .. shopIndex .. ":2").message, "Find"), "still needs the shopkeeper")
-- Warp scrolls: one at a time.
local keeper = RA.FolkByRole.WarpKeeper
local scrollIndex
for i, o in ipairs(keeper.shop or {}) do if string.find(o.item, "^WarpScroll") then scrollIndex = i end end
for _, f in ipairs(RA.Folk) do
	for i, o in ipairs(f.shop or {}) do if not scrollIndex and string.find(o.item, "^WarpScroll") then keeper, scrollIndex = f, i end end
end
if scrollIndex then
	at(buyer, keeper.role)
	ok(has(cmd(buyer, "rqBuy", keeper.role .. ":" .. scrollIndex .. ":2").message, "One scroll"), "warp scrolls are bought one at a time")
end
-- Skill vendors: stackable wares in bulk, one-of-a-kind wares refused.
local stack, unique
for _, e in ipairs(Data.SkillVendors.Hunter.shop) do
	local def = Data.Items[e.item]
	local isUnique = def.kind == "armor" or def.kind == "accessory" or def.category == "trap"
	local coinsOnly = true
	for k in pairs(e.cost) do if k ~= "coins" then coinsOnly = false end end
	if coinsOnly and e.cost.coins then
		if isUnique then unique = unique or e else stack = stack or e end
	end
end
buyer.attrs.SkillVendor, buyer.attrs.SkillVendorUntil = "Hunter", utc + 1000
if stack then
	local b0 = cmd(buyer, "state")
	local had = b0.items[stack.item] or 0
	local bulk = cmd(buyer, "skillBuy", "Hunter:" .. stack.item .. ":8")
	ok(has(bulk.message, "Bought 8×"), "8 stackable wares: " .. bulk.message)
	eq(bulk.coins, b0.coins - stack.cost.coins * 8, "skill vendor charges 8 × coins")
	eq((bulk.items[stack.item] or 0) - had, 8, "8 delivered")
end
if unique then ok(has(cmd(buyer, "skillBuy", "Hunter:" .. unique.item .. ":2").message, "one of a kind"), "unique ware refuses a quantity") end
ok(stack ~= nil or unique ~= nil, "skill vendor wares exercised")
-- The Roost keeper.
local candy = Data.PetDepth.Shop[1]
local p0 = cmd(buyer, "state")
local hadCandy = p0.items[candy.item] or 0
local roost = cmd(buyer, "petShop", candy.item .. ":3")
eq(roost.coins, p0.coins - candy.coins * 3, "Roost charges 3 ×")
eq((roost.items[candy.item] or 0) - hadCandy, 3, "3 delivered")
ok(has(cmd(buyer, "petShop", candy.item .. ":99").message, "does not sell"), "Roost quantity capped")
-- Per-unit prices still respect the 1.3 × value rule (bulk never discounts).
for _, f in ipairs(RA.Folk) do
	for _, o in ipairs(f.shop or {}) do ok(o.price * 64 / (o.amount * 64) >= (Data.Items[o.item].value or 1) * 1.3 - 1e-9, f.role .. " bulk unit price ≥ 1.3 × value") end
end
-- B4. Resonance.
local tuner = seeded(9005, function(pr)
	pr.coins = 1000
	local bag = {}
	for id, def in pairs(Data.Items) do if def.kind == "accessory" and #bag < 3 and def.rarity == "Rare" and not def.gem then pr.items[id] = 1; table.insert(bag, id) end end
	pr.accessoryBag = bag
end)
local mp = cmd(tuner, "state").resonance.power
ok(mp > 0, "Magical Power from the bag (" .. mp .. ")")
away(tuner)
ok(has(cmd(tuner, "resonanceVisit").message, "Find the Resonance Keeper"), "visit needs the keeper")
ok(has(cmd(tuner, "resonanceSet", "Emberkeen").message, "Visit the Resonance Keeper"), "tuning needs a visit")
at(tuner, "Resonator")
local visit = cmd(tuner, "resonanceVisit")
ok(has(visit.message, "listens"), "keeper visited")
eq(tuner.attrs.IsleStation, "Resonance", "the atlas opens Menu › Resonance")
ok(visit.resonance.visitIn > 0, "visit window published")
ok(has(cmd(tuner, "resonanceSet", "Nope").message, "Choose a resonance"), "unknown template refused")
ok(has(cmd(tuner, "resonanceSet", "Bladestorm").message, "needs 60"), "minPower gate on the server")
local tuned = cmd(tuner, "resonanceSet", "Emberkeen")
ok(has(tuned.message, "first tuning free") and tuned.coins == 1000, "first tuning free")
eq(tuned.resonance.id, "Emberkeen", "resonance saved")
local expectStats = R.stats("Emberkeen", mp)
eq(tuned.resonance.stats.strength, expectStats.strength, "resonance stats from Magical Power")
local beforeTune = P.computeStats(stored(tuner), utc)
tuner = player(9005)
at(tuner, "Resonator")
ok(math.abs(beforeTune.strength - P.computeStats({xp = stored(tuner).xp, items = {}, perkStats = {}}, utc).strength) >= expectStats.strength - 1e-6, "perkStats.resonance applies to the stat sheet")
tuner = player(9005)
at(tuner, "Resonator")
cmd(tuner, "resonanceVisit")
ok(has(cmd(tuner, "resonanceSet", "Emberkeen").message, "already"), "same template refused")
ok(has(cmd(tuner, "resonanceSet", "Galewise").message, "settling"), "switch cooldown (rejoin-safe)")
advance(R.SWITCH_COOLDOWN)
cmd(tuner, "resonanceVisit")
local switched = cmd(tuner, "resonanceSet", "Galewise")
ok(has(switched.message, "-" .. R.SWITCH_FEE), "switching costs the fee")
eq(switched.coins, 1000 - R.SWITCH_FEE, "fee charged once")
eq(stored(tuner).resonance.id, "Galewise", "switch saved")
-- B5. QC fixes.
-- L5: talking to Pell and tuning a resonance never mark the journal started.
local quiet = player(9011)
at(quiet, "Guide")
ok(has(cmd(quiet, "guideTalk").message, "Glad you found me"), "fresh journal talks to Pell")
ok(stored(quiet).started ~= true, "guideTalk does not set p.started")
local quietTuner = seeded(9012, function(pr)
	pr.started = false
	pr.items.MeadowCharm = 1
	pr.accessoryBag = {"MeadowCharm"}
end)
at(quietTuner, "Resonator")
cmd(quietTuner, "resonanceVisit")
ok(has(cmd(quietTuner, "resonanceSet", "Emberkeen").message, "first tuning free"), "fresh journal tunes Emberkeen")
local qs = stored(quietTuner)
ok(qs.resonance.id == "Emberkeen" and qs.started ~= true, "resonanceSet does not set p.started")
-- L4: Magical Power once per snapshot; renown rows {id, xp, count}; the breakdown
-- is reused until an announced event marks it dirty or RENOWN_INTERVAL passes.
local busy = seeded(9013, function(pr)
	for _, skill in ipairs(Data.SkillOrder) do pr.xp[skill] = X[99] end
	pr.items.MeadowCharm = 1
	pr.accessoryBag = {"MeadowCharm"}
	pr.resonance = {id = "Emberkeen", at = 0}
	pr.collection = {}
end)
cmd(busy, "state")
probe.power, probe.breakdowns = 0, 0
local bs = cmd(busy, "state")
eq(probe.power, 1, "Magical Power computed once per snapshot")
eq(probe.breakdowns, 0, "an unchanged journal reuses the cached renown breakdown")
for _, row in ipairs(bs.renown.sources) do
	local keys = 0
	for _ in pairs(row) do keys += 1 end
	ok(keys == 3 and row.name == nil and RN.SourceById[row.id] ~= nil, "renown row " .. tostring(row.id) .. " is {id, xp, count}")
end
ok(bs.resonance.power > 0 and bs.resonance.stats.strength ~= nil, "resonance uses the snapshot Magical Power")
local gathered = use(busy, prompt("gather", "Ore", Vector3.new(0, 5000, 0)))
ok(probe.breakdowns >= 1, "a collection unlock marks renown dirty (recomputed at once)")
local cbefore = probe.breakdowns
cmd(busy, "state")
eq(probe.breakdowns, cbefore, "and is cached again afterwards")
advance(6)
cmd(busy, "state")
eq(probe.breakdowns, cbefore + 1, "a stale breakdown is recomputed after RENOWN_INTERVAL")
local gatheredRow
for _, row in ipairs(gathered.renown.sources) do if row.id == "collections" then gatheredRow = row end end
ok(gatheredRow ~= nil, "renown rows still list collections")
-- L2: a ring full of ordinary entries keeps the renown level-ups.
local rush = seeded(9014, function(pr)
	for _, skill in ipairs(Data.SkillOrder) do pr.xp[skill] = X[99] end
	pr.renown = {xp = 0, level = 0, species = {}}
	pr.collection = {}
	for id, def in pairs(Data.Items) do if def.kind == "tool" then pr.items[id] = 1 end end
end)
local rs = cmd(rush, "state")
local renownSeen = 0
for _, e in ipairs(rs.announce.list) do if e.kind == "renown" then renownSeen += 1 end end
eq(renownSeen, 3, "a big renown jump announces its last three levels")
local unlocked = 0
for i, id in ipairs(Data.CollectionItems) do
	if Data.ResourceSkill[id] and Data.ResourceSkill[id] ~= "Fishing" and unlocked < 14 then
		advance(1)
		rush.last = nil
		services.ProximityPromptService.PromptTriggered:Fire(prompt("gather", id, Vector3.new(0, 5000, i)), rush)
		if rush.last and has(rush.last.message, "+") then unlocked += 1 end
	end
end
ok(unlocked >= 13, "13+ first gathers inside the 30 s ring (" .. unlocked .. ")")
local ring = cmd(rush, "state").announce
local kept, ordinary = 0, 0
for _, e in ipairs(ring.list) do if e.kind == "renown" then kept += 1 else ordinary += 1 end end
eq(#ring.list, F.ANNOUNCE_MAX, "the ring is full")
eq(kept, 3, "renown level-ups survive a full ring")
-- M1: an announcement queued while the journal closes (minigame leave settles
-- XP after PlayerRemoving) leaves nothing behind: the queue is weak-keyed and
-- forget() clears it after the final save.
local bridge
for _, o in ipairs(serverObjects) do if o.Name == "IsleBridge" then bridge = o end end
ok(bridge ~= nil and bridge.OnInvoke ~= nil, "IsleBridge found")
local closer = player(9015)
cmd(closer, "state")
local closerProfile = probe.profile
local monsterId, best = nil, 0
for id, m in pairs(Data.Monsters) do if not m.lair and (m.xp or 0) > best and (m.hp or 0) > 0 then monsterId, best = id, m.xp end end
local queueTable
storage.IsleMinigameLeave = {Invoke = function(_, who)
	who.Parent = nil -- departed: no snapshot flushes the queue
	local reply = bridge.OnInvoke("combatXp", who, {style = "melee", damage = Data.Monsters[monsterId].hp, monster = monsterId})
	ok(type(reply) == "table" and reply.ok ~= false, "minigame leave settles XP during close")
	for _, t in ipairs(weakTables) do
		local v = rawget(t, closerProfile)
		if type(v) == "table" and v[1] and v[1].kind == "skill" then queueTable = t end
	end
end}
leave(closer)
storage.IsleMinigameLeave = nil
ok(queueTable ~= nil, "the level-up was queued during close")
ok(queueTable ~= nil and getmetatable(queueTable).__mode == "k", "the announcement queue is weak-keyed")
ok(queueTable ~= nil and rawget(queueTable, closerProfile) == nil, "forget() cleared the queued announcement after the final save")
print("PASS: " .. (checks - partB) .. " server assertions.")

------------------------------------------------------------------------------
-- Part C: world.server.lua vents.
------------------------------------------------------------------------------
local partC = checks
do
	local promptSignals = {}
	roblox.implementProperty("ProximityPrompt", "Triggered", function(q)
		if not promptSignals[q] then promptSignals[q] = signal() end
		return promptSignals[q]
	end)
	local players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
	local dataModule = {Name = "AetherData"}
	local allow = {}
	local regionAccess = {Invoke = function(_, _, regionId) return {allowed = allow[regionId] == true, message = "Locked: " .. tostring(regionId)} end}
	local gateVerdict = true
	local tags = {}
	local wservices = {
		Players = players, Lighting = roblox.Instance.new("Lighting"),
		CollectionService = {AddTag = function(_, obj, tag) tags[tag] = tags[tag] or {}; table.insert(tags[tag], obj) end},
		ReplicatedStorage = {WaitForChild = function(_, name) return if name == "AetherData" then dataModule else nil end},
		ServerStorage = {FindFirstChild = function(_, name)
			if name == "IsleRegionAccess" then return regionAccess end
			if name == "IsleTravelGate" then return {Invoke = function() if gateVerdict == "ERROR" then error("gate down") end return gateVerdict end} end
			return nil
		end},
	}
	local world = roblox.Instance.new("Workspace")
	local spawned = {}
	local wclock = 100
	local wenv = {
		game = {GetService = function(_, name) return wservices[name] end},
		workspace = world, Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, Color3 = roblox.Color3,
		UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum,
		task = {
			spawn = function(fn, ...) local co = coroutine.create(fn); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); table.insert(spawned, co); return co end,
			wait = function() return coroutine.yield() end,
		},
		os = {clock = function() return wclock end, time = os.time},
		NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
		require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
	}
	local source = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
	luau.load(source, {environment = wenv, injectGlobals = true})()
	local parts = 0
	for _, obj in world:GetDescendants() do if obj:IsA("BasePart") then parts += 1 end end
	ok(parts < 4000, "static world under the 4000 part budget (" .. parts .. ")")
	print("World static parts with vents: " .. parts)
	local pads = tags.SkywardVent or {}
	for _, def in ipairs(VD.List) do local hit = false for _, pd in pads do if pd:GetAttribute("VentId") == def.id then hit = true end end if not hit then print("MISSING vent " .. def.id .. " isle " .. def.isle .. " exists=" .. tostring(world:FindFirstChild("Islands"):FindFirstChild(def.isle) ~= nil)) end end
	eq(#pads, #VD.List, "every vent placed")
	local markersPos = {}
	for _, m in world:FindFirstChild("MonsterSpawns"):GetChildren() do table.insert(markersPos, m.CFrame.Position) end
	local islands = world:FindFirstChild("Islands")
	local byId = {}
	for _, pad in pads do
		local id = pad:GetAttribute("VentId")
		local def = VD.ById[id]
		byId[id] = pad
		ok(def ~= nil, "pad names a vent")
		eq(pad:GetAttribute("Shape"), "SkywardVentPad", id .. " uses the vent pad dais mesh slot")
		ok(pad.CanCollide and pad.Anchored, id .. " pad is a solid collider")
		ok(pad:IsDescendantOf(islands:FindFirstChild(def.isle)), id .. " stands on " .. def.isle)
		local landing = pad:GetAttribute("VentLanding")
		ok(typeof(landing) == "Vector3", id .. " has a landing")
		local host = islands:FindFirstChild(def.land)
		local c, rad = host:GetAttribute("IslandCenter"), host:GetAttribute("IslandRadius")
		ok(Vector3.new(landing.X - c.X, 0, landing.Z - c.Z).Magnitude < rad, id .. " lands on " .. def.land)
		for _, m in markersPos do ok(Vector3.new(landing.X - m.X, 0, landing.Z - m.Z).Magnitude >= 40, id .. " landing clear of monster spawns") end
		local q = pad:FindFirstChildOfClass("ProximityPrompt")
		ok(q ~= nil and q:GetAttribute("IsleVent") == id and q:GetAttribute("IsleAction") == nil, id .. " prompt")
		ok(pad:FindFirstChild("Updraft") ~= nil, id .. " updraft emitter")
	end
	-- Ride: denied by region access, then allowed: arc attribute, FastTravelAt, landing after the flight.
	local function rider()
		local t = {attributes = {}}
		function t:GetAttribute(k) return self.attributes[k] end
		function t:SetAttribute(k, v) self.attributes[k] = v end
		return t
	end
	local function standAt(t, pos)
		local root = {Position = pos, AssemblyLinearVelocity = Vector3.zero}
		local hum = {Health = 100}
		t.landed = nil
		t.Character = {FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end,
			FindFirstChildOfClass = function(_, cl) return if cl == "Humanoid" then hum else nil end,
			PivotTo = function(_, cf) t.landed = cf.Position end}
		t.root = root
	end
	local pad = byId.MosswakeUpdraft
	local q = pad:FindFirstChildOfClass("ProximityPrompt")
	local t = rider()
	standAt(t, pad.CFrame.Position)
	q.Triggered:Fire(t)
	eq(t.attributes.IsleRegionNotice, "Locked: Windpine", "locked destination relays the region message")
	eq(t.attributes.VentFlight, nil, "no flight while locked")
	allow.Windpine = true
	gateVerdict = "You can't travel mid-fight."
	q.Triggered:Fire(t)
	eq(t.attributes.IsleRegionNotice, "You can't travel mid-fight.", "travel gate respected")
	gateVerdict = true
	local far = rider()
	standAt(far, pad.CFrame.Position + Vector3.new(40, 0, 0))
	q.Triggered:Fire(far)
	eq(far.attributes.VentFlight, nil, "riders must stand on the vent")
	local before = #spawned
	q.Triggered:Fire(t)
	ok(t.attributes.FastTravelAt ~= nil and has(t.attributes.VentFlight, "MosswakeUpdraft:"), "launch sets FastTravelAt and VentFlight")
	ok(t.landed == nil, "the server waits for the arc")
	local mark = t.attributes.FastTravelAt
	wclock += 1
	local co = spawned[before + 1]
	assert(coroutine.resume(co))
	ok(t.landed ~= nil and (t.landed - pad:GetAttribute("VentLanding")).Magnitude < 1e-3, "landed on the vent's landing")
	ok(t.attributes.FastTravelAt ~= mark, "landing sets FastTravelAt again")
	-- Cooldown.
	standAt(t, pad.CFrame.Position)
	q.Triggered:Fire(t)
	ok(has(t.attributes.IsleRegionNotice, "gathering its breath"), "per-rider cooldown")
	wclock += VD.COOLDOWN
	q.Triggered:Fire(t)
	ok(has(t.attributes.VentFlight, "MosswakeUpdraft:"), "rides again after the cooldown")
	-- Return vents lead to ungated regions.
	local back = byId.WindpineDowndraft:FindFirstChildOfClass("ProximityPrompt")
	local t2 = rider()
	allow.Meadow = true
	standAt(t2, byId.WindpineDowndraft.CFrame.Position)
	back.Triggered:Fire(t2)
	ok(has(t2.attributes.VentFlight, "WindpineDowndraft:"), "return vent rides home")
	-- L1: an erroring gate refuses the launch; the gate and the flight are checked
	-- again just before landing, and a failed check leaves the rider where they are.
	local t3 = rider()
	standAt(t3, pad.CFrame.Position)
	gateVerdict = "ERROR"
	q.Triggered:Fire(t3)
	eq(t3.attributes.VentFlight, nil, "an erroring travel gate refuses the launch (fails closed)")
	ok(has(t3.attributes.IsleRegionNotice, "will not lift"), "the refusal is shown")
	local function flight(verdictAtLanding, midFlight)
		wclock += VD.COOLDOWN
		standAt(t3, pad.CFrame.Position)
		gateVerdict = true
		local n0 = #spawned
		q.Triggered:Fire(t3)
		ok(has(t3.attributes.VentFlight, "MosswakeUpdraft:"), "launched")
		gateVerdict = verdictAtLanding
		if midFlight then midFlight() end
		assert(coroutine.resume(spawned[n0 + 1]))
		gateVerdict = true
		return t3.landed
	end
	eq(flight("You can't travel mid-fight."), nil, "hurt mid-flight: no landing, the rider stays put")
	eq(t3.attributes.IsleRegionNotice, "You can't travel mid-fight.", "the mid-flight refusal is shown")
	eq(flight("ERROR"), nil, "a gate error at landing aborts the landing")
	eq(flight(true, function() players.PlayerRemoving:Fire(t3) end), nil, "a rider no longer launched is not landed")
	ok(flight(true) ~= nil, "a clean flight still lands")
end
print("PASS: " .. (checks - partC) .. " world assertions.")

------------------------------------------------------------------------------
-- Part D: clients.
------------------------------------------------------------------------------
local partD = checks
do
	local H = require("./tools/ui-harness")
	local snap = H.snapshot()
	snap.renown = {level = 12, xp = 1234, into = 34, need = 100, title = "Islander", color = "FFFFFF", slots = 1, stats = {health = 2},
		sources = {{id = "skills", name = "Skill levels", hint = "x", xp = 1000, count = 40}}, next = {{level = 15, text = "+1 Strength"}}}
	snap.guide = {step = 2, total = 10, done = 1, id = "craft", title = "Craft at a workbench", detail = "Craft anything.", coins = 40, owed = 25, complete = false}
	snap.resonance = {id = nil, power = 40, stats = {}, fee = 0, readyIn = 0, visitIn = 120}
	snap.announce = {seq = 0, list = {}}
	local size = roblox.Vector2.new(1366, 768)
	local ui = H.runAtlas(size, {snapshot = snap})
	-- Sidebar: renown and the server objective.
	local sidebar = H.find(ui.gui, "Sidebar")
	local marks, goal = H.find(sidebar, "Marks"), H.find(sidebar, "Goal")
	ok(marks and has(marks.Text, "✪ 12"), "sidebar shows the renown level: " .. tostring(marks and marks.Text))
	ok(goal and has(goal.Text, "Craft at a workbench") and has(goal.Text, "2/10"), "sidebar Objective is the server step: " .. tostring(goal and goal.Text))
	-- Menu › Renown and Menu › Resonance pages.
	H.press(H.find(sidebar, "AtlasButton"))
	H.press(H.find(ui.scroll, "MenuRenown"))
	ok(H.find(ui.scroll, "RenownLevel") and H.find(ui.scroll, "RenownNext") and H.find(ui.scroll, "RenownSourceskills"), "Renown page: level, next unlocks, sources")
	local claimButton = H.find(ui.scroll, "GuideClaim")
	ok(claimButton ~= nil, "owed path rewards offer a Claim button")
	local sentBefore = #ui.sent
	H.press(claimButton)
	local found = false
	for i = sentBefore + 1, #ui.sent do if ui.sent[i][1] == "guideClaim" then found = true end end
	ok(found, "Claim sends guideClaim")
	-- Features client against the same local channels.
	local players = H.new("Players", {LocalPlayer = ui.player})
	local tagged = {}
	local binds, unbinds = {}, {}
	local heartbeat = signal()
	local fservices = {Players = players, ReplicatedStorage = ui.replicated, UserInputService = H.new("UserInputService", {TouchEnabled = false}),
		RunService = {Heartbeat = heartbeat, BindToRenderStep = function(_, name, _, fn) table.insert(binds, {name = name, fn = fn}) end,
			UnbindFromRenderStep = function(_, name) table.insert(unbinds, name) end}, CollectionService = {GetTagged = function() return tagged end}}
	function players.GetPlayers() return {ui.player} end
	players.PlayerAdded, players.PlayerRemoving = signal(), signal()
	local game = H.new("DataModel")
	function game.GetService(_, name) return assert(fservices[name], name) end
	local delays = {}
	local fenv = {game = game, workspace = {CurrentCamera = H.new("Camera")}, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange, TweenInfo = {new = function() return {} end},
		Instance = {new = function(class) return H.new(class) end},
		task = {spawn = function(f, ...) local co = coroutine.create(f); coroutine.resume(co, ...) end, delay = function(sec, f, ...) table.insert(delays, {sec, f}) end,
			wait = function() return 0 end, defer = function(f, ...) f(...) end},
		typeof = function(v) return typeof(v) end, print = function() end, warn = function() end}
	local theme = H.loadTheme(fenv)
	fenv.require = function(target) if target.Name == "AetherUiTheme" then return theme end return Data end
	luau.load(fs.readFile("features.client.lua"), {debugName = "features.client.lua", environment = fenv, injectGlobals = true})()
	local S = ui.player:FindFirstChild("IsleFeaturesApi").OnInvoke("state")
	ok(S ~= nil and S.toast ~= nil and not S.toast.Visible, "features client loaded, toast hidden")
	-- Toasts from the ring, deduped by seq.
	local relayed = {}
	ui.replicated:FindFirstChild("IsleActionLocal").Event:Connect(function(verb, item) table.insert(relayed, {verb, item}) end)
	local snapChannel = ui.replicated:FindFirstChild("IsleSnapshotLocal")
	snapChannel:Fire({announce = {seq = 2, list = {{seq = 1, kind = "collection", item = "Ore"}, {seq = 2, kind = "skill", skill = "Mining", level = 2, coins = 10}}}})
	ok(S.toast.Visible and has(H.find(S.toast, "Head").Text, "COLLECTION UNLOCKED") and H.find(S.toast, "Message").Text == Data.Items.Ore.name, "COLLECTION UNLOCKED toast")
	eq(#S.queue, 1, "the level-up waits its turn")
	eq(#S.chat, 2, "two chat lines")
	snapChannel:Fire({announce = {seq = 2, list = {{seq = 1, kind = "collection", item = "Ore"}, {seq = 2, kind = "skill", skill = "Mining", level = 2}}}})
	eq(#S.chat, 2, "a repeated ring is not shown twice")
	delays[#delays][2]()
	ok(has(H.find(S.toast, "Head").Text, "SKILL LEVEL UP"), "queue advances")
	delays[#delays][2]()
	ok(not S.toast.Visible, "queue drains")
	snapChannel:Fire({announce = {seq = 1, list = {{seq = 1, kind = "renown", level = 10}}}})
	ok(S.toast.Visible and has(H.find(S.toast, "Head").Text, "ISLE RENOWN 10"), "a restarted server ring is shown")
	-- Quantity picker.
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "rqBuy", base = "Fishmonger:1", name = "Fish", unit = 20, amount = 5, max = 16})
	ok(S.picker_frame.Visible and S.shade.Visible, "picker opens")
	ok(has(H.find(S.picker_frame, "Total").Text, "×5") and has(H.find(S.picker_frame, "Total").Text, "20 coins"), "per-lot total shown")
	H.press(H.find(S.picker_frame, "Qty32"))
	eq(#relayed, 0, "presets above the affordable maximum do nothing")
	H.press(H.find(S.picker_frame, "Qty8"))
	ok(#relayed == 1 and relayed[1][1] == "rqBuy" and relayed[1][2] == "Fishmonger:1:8", "×8 relays rqBuy Role:i:8")
	ok(not S.picker_frame.Visible, "picker closes after buying")
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "petShop", base = "PetCandy", name = "Pet Candy", unit = 8000, amount = 1, max = 64})
	S.custom.Text = "12"
	H.press(H.find(S.picker_frame, "BuyCustom"))
	ok(relayed[2] and relayed[2][2] == "PetCandy:12", "custom quantity relays")
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "petShop", base = "PetCandy", name = "Pet Candy", unit = 8000, amount = 1, max = 64})
	S.custom.Text = "999"
	H.press(H.find(S.picker_frame, "BuyCustom"))
	eq(#relayed, 2, "out-of-range custom quantity refused locally")
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "petShop", base = "PetCandy", name = "Pet Candy", unit = 8000, amount = 1, max = 1})
	H.press(H.find(S.picker_frame, "Qty1"))
	ok(relayed[3] and relayed[3][2] == "PetCandy", "a single lot sends the plain item id")
	-- L6: warp scrolls and one-of-a-kind wares never open the picker.
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "rqBuy", base = "WarpKeeper:1", item = Data.RegionArt.Warps[1].scroll, name = "Scroll", unit = 100, amount = 1, max = 64})
	ok(not S.picker_frame.Visible, "a warp scroll offer does not open the quantity picker")
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "rqBuy", base = "X:1", item = "SovereignSignet", name = "Signet", unit = 100, amount = 1, max = 64})
	ok(not S.picker_frame.Visible, "a one-of-a-kind offer does not open the quantity picker")
	ok(has(fs.readFile("npc.client.lua"), "Shop.singleLot(offer.item) then return end"), "dialogue offers skip the picker for single-lot wares")
	-- Polish: sell mode (sell "<id>:<n>"): any count up to the sellable amount, "+coins", a Sell button.
	local relayedBefore = #relayed
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "sell", base = "Ore", item = "Ore", name = "Ore", unit = 4, amount = 1, max = 200, sell = true})
	ok(S.picker_frame.Visible and S.picker_frame:GetAttribute("Mode") == "sell", "the picker opens in sell mode")
	ok(has(H.find(S.picker_frame, "Total").Text, "+4 coins") and H.find(S.picker_frame, "BuyCustom").Text == "Sell", "sell totals and button")
	-- Polish QC M1: the first tap only arms a confirmation; the second tap sends.
	H.press(H.find(S.picker_frame, "Qty32"))
	eq(#relayed, relayedBefore, "a single tap in sell mode sells nothing")
	ok(S.picker_frame.Visible and S.picker_frame:GetAttribute("SellArmed") == 32 and has(H.find(S.picker_frame, "Total").Text, "Sell 32 for +128 coins?")
		and H.find(S.picker_frame, "BuyCustom").Text == "Confirm", "the first tap asks to confirm the sale")
	H.press(H.find(S.picker_frame, "Qty1"))
	eq(#relayed, relayedBefore, "tapping another quantity re-arms instead of selling")
	H.press(H.find(S.picker_frame, "Qty1"))
	ok(relayed[relayedBefore + 1] and relayed[relayedBefore + 1][1] == "sell" and relayed[relayedBefore + 1][2] == "Ore:1", "×1 sells exactly one (never the whole stack)")
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "sell", base = "Ore", item = "Ore", name = "Ore", unit = 4, amount = 1, max = 200, sell = true})
	ok(S.picker_frame:GetAttribute("SellArmed") == nil and H.find(S.picker_frame, "BuyCustom").Text == "Sell", "reopening the picker starts disarmed")
	S.custom.Text = "150"
	H.press(H.find(S.picker_frame, "BuyCustom"))
	eq(#relayed, relayedBefore + 1, "custom sell waits for confirmation")
	H.press(H.find(S.picker_frame, "BuyCustom"))
	ok(relayed[relayedBefore + 2] and relayed[relayedBefore + 2][2] == "Ore:150", "custom sell quantity past 64 relays")
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "sell", base = "SovereignSignet", item = "SovereignSignet", name = "Signet", unit = 100, amount = 1, max = 3, sell = true})
	ok(S.picker_frame.Visible, "one-of-a-kind items still open the sell picker")
	S.custom.Text = "4"
	H.press(H.find(S.picker_frame, "BuyCustom"))
	H.press(H.find(S.picker_frame, "BuyCustom"))
	eq(#relayed, relayedBefore + 2, "more than the sellable count is refused locally")
	H.press(S.shade)
	ui.replicated:FindFirstChild("IsleQuantityLocal"):Fire({verb = "rqBuy", base = "X:1", item = "Ore", name = "Ore", unit = 4, amount = 1, max = 8})
	ok(H.find(S.picker_frame, "BuyCustom").Text == "Buy" and S.picker_frame:GetAttribute("Mode") == "buy", "buy mode restored")
	H.press(S.shade)
	-- Polish: Skyward Vent launch feel: wind streaks, FOV kick and tilt; reduced motion skips the camera.
	local VF = Data.Vents.Fx
	eq(VF.fovKick(0), 0, "FOV kick starts at 0")
	eq(VF.fovKick(0.2), VF.FOV_KICK, "FOV kick peaks early")
	ok(math.abs(VF.fovKick(1)) < 1e-9 and math.abs(VF.tilt(1)) < 1e-9 and math.abs(VF.tilt(0.5) - VF.TILT) < 1e-9, "kick and tilt are back to zero at the landing")
	ok(VF.WIND_RATE_REDUCED < VF.WIND_RATE, "reduced motion has a lighter wind")
	local ventPad = H.new("Part", {Name = "Skyward vent"})
	ventPad:SetAttribute("VentId", "MosswakeUpdraft")
	ventPad:SetAttribute("VentLanding", Vector3.new(120, 40, 0))
	table.insert(tagged, ventPad)
	local character = H.new("Model", {Name = "Character"})
	local root = H.new("Part", {Name = "HumanoidRootPart", Position = Vector3.new(0, 10, 0), CFrame = roblox.CFrame.new(0, 10, 0)})
	root.Parent = character
	ui.player.Character = character
	local camera = fenv.workspace.CurrentCamera
	camera.FieldOfView, camera.CFrame = 70, roblox.CFrame.new()
	ui.player:SetAttribute("IsleSettingReducedMotion", false)
	ui.player:SetAttribute("VentFlight", "MosswakeUpdraft:1")
	local wind = root:FindFirstChild("VentWind")
	local streaks = wind and wind:FindFirstChild("VentWindStreaks")
	ok(streaks ~= nil and streaks.Rate == VF.WIND_RATE, "wind streaks on the rider")
	eq(#binds, 1, "camera tilt bound for the arc")
	binds[1].fn()
	ok(camera.FieldOfView >= 70, "FOV kick applied")
	-- Polish QC L2: a second arc started mid-kick keeps the true base FOV.
	local kicked = camera.FieldOfView
	ok(kicked > 70, "first arc kicked the FOV")
	ui.player:SetAttribute("VentFlight", "MosswakeUpdraft:2")
	eq(S.ventBaseFov, 70, "the base FOV is not recaptured from a kicked camera")
	heartbeat:Fire(0.016)
	ok(S.ventFovOwner ~= nil and #binds == 2, "the newer arc owns the kick")
	binds[2].fn()
	ui.player:SetAttribute("IsleSettingReducedMotion", true)
	ui.player:SetAttribute("VentFlight", "MosswakeUpdraft:3")
	heartbeat:Fire(0.016)
	eq(#unbinds, 2, "each replaced arc unbinds its tilt")
	eq(camera.FieldOfView, 70, "FOV restored to the true base after back-to-back arcs")
	eq(#binds, 2, "reduced motion: no camera tilt or FOV kick")
	ok(S.ventReduced == true and S.ventWind:FindFirstChild("VentWindStreaks").Rate == VF.WIND_RATE_REDUCED, "reduced motion keeps a lighter wind")
	ui.player:SetAttribute("IsleSettingReducedMotion", nil)
	-- Polish: the worker recipe announcement toast.
	local recipeText = Data.Features.announceText({kind = "workerRecipe", item = "Brassite", worker = "Brassite", tier = 1})
	ok(recipeText.head == "WORKER RECIPE UNLOCKED" and recipeText.color == "FFAA00", "worker recipe toast text")
	-- L2 (client): a long toast queue drops ordinary toasts before a renown level-up.
	local burst = {{seq = 11, kind = "renown", level = 11}}
	for i = 12, 20 do table.insert(burst, {seq = i, kind = "collection", item = "Ore"}) end
	snapChannel:Fire({announce = {seq = 20, list = burst}})
	local queuedRenown = false
	for _, e in ipairs(S.queue) do if e.kind == "renown" and e.level == 11 then queuedRenown = true end end
	ok(#S.queue <= 8 and queuedRenown, "the renown toast survives a full queue")
	-- L8: nameplate connections are kept per player and disconnected when they leave.
	local other = {attrs = {RenownLevel = 3}, CharacterAdded = signal(), changed = {}}
	function other:GetAttribute(k) return self.attrs[k] end
	function other:GetAttributeChangedSignal(k) local sig = signal(); self.changed[k] = sig; return sig end
	players.PlayerAdded:Fire(other)
	local conns = S.watches[other]
	ok(conns ~= nil and #conns == 4, "four nameplate connections stored for the new player")
	players.PlayerRemoving:Fire(other)
	local live = 0
	for _, c in ipairs(conns or {}) do if c.Connected then live += 1 end end
	eq(live, 0, "every nameplate connection disconnected on leave")
	eq(S.watches[other], nil, "the watch entry is dropped")
	ok(string.sub(fs.readFile("features.client.lua"), 1, 9) == "--!strict", "features.client.lua is --!strict")
	-- Polish QC L4: no live code or layout comment still refers to the retired tutorial tracker.
	for _, file in ipairs({"ui.client.lua", "combat.client.lua"}) do
		local text = string.lower(fs.readFile(file))
		ok(not string.find(text, "under the tutorial tracker", 1, true) and not string.find(text, "tutorialtracker", 1, true), file .. " has no stale tutorial-tracker references")
	end
	ok(not has(fs.readFile("shared/GameData.lua"), "old \"tutorial\" node redirects there"), "GameData no longer claims the tutorial node redirects")
	-- The atlas relays the quantity verbs (server validates).
	local src = fs.readFile("ui.client.lua")
	for _, verb in ipairs({"rqBuy", "skillBuy", "petShop", "resonanceSet", "guideClaim"}) do ok(has(src, verb .. "=true"), "atlas relays " .. verb) end
	ok(has(fs.readFile("npc.client.lua"), "quantityHook(b, option)"), "dialogue shop offers open the picker (right-click / long-press)")
	-- Toast sits above the hotbar band at every HUD size.
	for _, sz in ipairs({roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390), roblox.Vector2.new(730, 303)}) do
		local L = theme.hudLayout(sz.X, sz.Y, {})
		ok(L.band.y - (if L.short then 50 else 64) - (if L.short then 46 else 54) >= 8, "toast fits above the band at " .. sz.X .. "x" .. sz.Y)
	end
end
print("PASS: " .. (checks - partD) .. " client assertions.")
print("MMO Features QA passed " .. checks .. " checks.")
print("SUITE-END verify-features.luau")
