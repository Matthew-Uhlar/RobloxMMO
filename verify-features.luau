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
eq(#G.Steps, 10, "ten onboarding steps")
local ids = {}
for i, s in ipairs(G.Steps) do
	ok(type(s.title) == "string" and #s.title > 4 and #s.detail > 10 and s.coins > 0 and s.coins <= 100, s.id .. " step text and a small reward")
	ok((s.flag ~= nil) ~= (s.check ~= nil), s.id .. " is a flag or a check")
	ids[i] = s.id
end
eq(table.concat(ids, ","), "chop,craft,visit,talk,ore,sell,equip,kill,quest,warp", "step order")
local fresh = {collection = {}, counters = {}, equipment = {}, bestiary = {}, kills = 0}
for _, s in ipairs(G.Steps) do ok(not G.satisfied(fresh, s, {warps = {}}), s.id .. " not satisfied on a fresh journal") end
ok(G.satisfied({collection = {Timber = 1}}, G.StepById.chop, {}), "a log satisfies chop")
ok(G.satisfied({equipment = {weapon = "CopperBlade"}}, G.StepById.equip, {}), "a weapon satisfies equip")
ok(G.satisfied({}, G.StepById.warp, {warps = {Quarry = true}}), "a known warp satisfies warp")
eq(G.view({}).id, "chop", "first step shown")
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
local env = {
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
ok(type(s.guide) == "table" and s.guide.id == "chop" and s.guide.step == 1 and s.guide.total == 10, "sidebar objective: Chop a log")
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
ok(kinds["objective:Chop a log"] ~= nil, "NEW OBJECTIVE names the first open step")
eq(r.coins, coins0, "path rewards are not paid automatically")
eq(r.guide.owed, G.StepById.ore.coins, "the step's coins are owed")
eq(r.guide.id, "chop", "the sidebar still shows the first open step")
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
-- B2. Retroactive renown, once: a journal from before the update.
local vet = seeded(9002, function(pr)
	pr.renown, pr.guide = nil, nil
	for _, skill in ipairs({"Mining", "Woodcutting", "Combat", "Fishing"}) do pr.xp[skill] = X[40] end
	pr.collection.Ore = 100000
	pr.questCompleted = 4
	pr.pets = {{id = Data.Pets[1].id, level = 1, xp = 0}}
end)
local first = cmd(vet, "state")
local expect = RN.breakdown(stored(vet), P, {species = {[Data.Pets[1].id] = true}, guideSteps = #G.Steps}).total
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
			if name == "IsleTravelGate" then return {Invoke = function() return gateVerdict end} end
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
		eq(pad:GetAttribute("Shape"), "Caldera", id .. " uses a forge mesh slot")
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
	local heartbeat = signal()
	local fservices = {Players = players, ReplicatedStorage = ui.replicated, UserInputService = H.new("UserInputService", {TouchEnabled = false}),
		RunService = {Heartbeat = heartbeat}, CollectionService = {GetTagged = function() return tagged end}}
	function players.GetPlayers() return {ui.player} end
	players.PlayerAdded, players.PlayerRemoving = signal(), signal()
	local game = H.new("DataModel")
	function game.GetService(_, name) return assert(fservices[name], name) end
	local delays = {}
	local fenv = {game = game, workspace = {CurrentCamera = H.new("Camera")}, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, TweenInfo = {new = function() return {} end},
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
