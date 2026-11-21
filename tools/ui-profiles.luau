-- Realistic snapshots for the screenshot renderer (tools/render-ui.luau).
-- Runs the production server.server.lua headlessly (the same doubles the
-- verify-* suites use), seeds a stored profile for each stage and returns the
-- snapshot the server itself sends, so every page sees real server state:
--   early    a fresh voyager an hour in (Meadow only, a few levels, no pledge)
--   mid      the long-standing mid-game record (tools/ui-harness profile) plus
--            commissions, a log, a pledge, motes, minigame points, a dungeon run
--   endgame  levels 80-99, Master Mode clears, a full bonus chest, a deep log
-- Usage: local Profiles = require("./ui-profiles"); Profiles.snapshot("mid")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, { debugName = path, environment = env or {}, injectGlobals = true })()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", { script = nil })
P.useData(Data)

local function signal()
	local listeners = {}
	return {
		Connect = function(_, f) table.insert(listeners, f) return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, f in listeners do f(...) end end,
	}
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end

local clock, utc = 10, 1700000000
local data = {}
local db = {}
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	return copy(data[key])
end
local markers = { AetherData = { Name = "AetherData" }, AetherProgression = { Name = "AetherProgression" }, AetherTrails = { Name = "AetherTrails" } }
local modules = { [markers.AetherData] = Data, [markers.AetherProgression] = P, [markers.AetherTrails] = load("trails.lua") }
local services = {
	Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end },
	ProximityPromptService = { PromptTriggered = signal() },
	ReplicatedStorage = { WaitForChild = function(_, name) return assert(markers[name], name) end },
	ServerStorage = { FindFirstChild = function(_, name) if name == "AetherTrails" then return markers.AetherTrails end return nil end },
	DataStoreService = { GetDataStore = function() return db end },
	HttpService = { GenerateGUID = function() return "render-profiles" end },
	RunService = { IsStudio = function() return false end },
}
local serverObjects = {}
local env = {
	game = { GetService = function(_, name) return services[name] end, BindToClose = function() end },
	workspace = { GetAttribute = function(self, key) return rawget(self, key) end, FindFirstChild = function() return nil end },
	Vector3 = Vector3, CFrame = CFrame, UDim2 = roblox.UDim2, Color3 = roblox.Color3, Enum = roblox.Enum,
	Instance = { new = function(className)
		local o = { ClassName = className, Event = signal(), FireClient = function(_, player, state) player.last = state end }
		function o:Destroy() self.Parent = nil end
		table.insert(serverObjects, o)
		return o
	end },
	os = { clock = function() return clock end, time = function() return math.floor(utc) end, date = os.date },
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = { new = function() return { NextNumber = function() return 0.5 end, NextInteger = function(_, lo) return lo end } end },
	warn = function() end,
	print = function() end,
	task = {
		spawn = function(f, ...) local co = coroutine.create(f); local okRun, err = coroutine.resume(co, ...); assert(okRun, err); return co end,
		defer = function(f, ...) f(...) end,
		wait = function(t) return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, { debugName = "server.server.lua", environment = env, injectGlobals = true })()
local remote
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
end
assert(remote, "IsleAction not found")

local live = {}
local function join(id)
	local humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end }
	local root = { Position = Vector3.new(0, 5000, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero }
	local p = { UserId = id, Name = "Voyager", DisplayName = "Voyager", Parent = true, CharacterAdded = signal(), Kick = function() end, attrs = {} }
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	function p:GetAttributeChangedSignal() return signal() end
	p.Character = { Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function() end }
	if live[id] then services.Players.PlayerRemoving:Fire(live[id]) end
	live[id] = p
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function leave(p)
	if live[p.UserId] == p then live[p.UserId] = nil end
	services.Players.PlayerRemoving:Fire(p)
end
local function cmd(p, verb, item)
	clock += 1; utc += 1
	return remote.OnServerInvoke(p, verb, item)
end

local X = Data.XP_TABLE
local function xpFor(levels)
	local out = {}
	for skill, lv in pairs(levels) do out[skill] = (X[lv] or 0) + (lv > 1 and 37 or 0) end
	return out
end
local function merge(into, from)
	for k, v in pairs(from) do into[k] = v end
	return into
end
local function fill(levelAll, overrides)
	local t = {}
	for _, skill in ipairs(Data.SkillOrder) do t[skill] = levelAll end
	return merge(t, overrides or {})
end

-- Stored-profile edits per stage. Server migrations sanitise everything, so
-- these stay faithful to what a real save of that stage would carry.
local depth -- defined below the stages
local stages = {}
stages.early = function(prof)
	prof.started = true
	merge(prof.xp, xpFor({ Mining = 6, Woodcutting = 4, Fishing = 3, Combat = 5, Smithing = 3, Cooking = 2 }))
	merge(prof.items, { Ore = 18, Timber = 9, Fish = 4, Herb = 2, Tonic = 1, Pickaxe = 1, Blade = 1 })
	merge(prof.collection, { Ore = 40, Timber = 12, Fish = 4 })
	prof.coins = 340
	prof.equipment = { weapon = "Blade" }
end
stages.mid = function(prof)
	prof.started = true
	merge(prof.xp, { Combat = 9000, Mining = 22000, Woodcutting = 400, Fishing = 1800, Farming = 60, Smithing = 4500, Cooking = 900, Alchemy = 300, Enchanting = 1200,
		Taming = 400, Dungeoneering = 2400, Carpentry = 50, Ranged = 5200, Magic = 14100, Fletching = 1200, Glyphcraft = 800, Agility = 3400, Hunter = 2600,
		Prayer = 4700, Thieving = 3400, Crafting = 2600 })
	merge(prof.items, {
		Ore = 140, Timber = 40, Herb = 70, Fish = 30, Brassite = 12, Pickaxe = 1, Blade = 1, Tonic = 2, ExpeditionRation = 1,
		BrassSword = 1, BrassHelm = 1, BrassChestplate = 1, BrassGreaves = 1, BrassBoots = 1, SunsteelSword = 1, BrassPickaxe = 1,
		CopperHatchet = 1, ArcaneDust = 60, MeadowCharm = 1, QuarryTalisman = 1, CookedFish = 3, MightDraught = 2,
		StormFeather = 3, BrassIngot = 9, WindpineStaff = 1, MeadowWand = 1, MeadowLongbow = 1, CopperArrow = 60, BrassArrow = 143,
		GaleGlyph = 40, StoneGlyph = 12, SparkGlyph = 25, Skymark = 37, SnareKit = 1, DownyPelt = 14, SunstoneChip = 6, Dewquartz = 3,
		BrittleRemains = 24, Glimmerdust = 40, ObservatoryEssence = 120,
	})
	merge(prof.collection, { Ore = 320, Timber = 60, Herb = 70, Fish = 30, Brassite = 40, Shard = 2, StormFeather = 3 })
	prof.coins, prof.bank = 52000, 12500
	prof.equipment = { weapon = "WindpineStaff", helmet = "BrassHelm", chest = "BrassChestplate", legs = "BrassGreaves", boots = "BrassBoots", ammo = "BrassArrow" }
	prof.accessoryBag = { "MeadowCharm", "QuarryTalisman" }
	prof.bestiary = { BramblebackBoar = 30, Thornling = 1, ShaleCrawler = 100 }
	prof.slayerXp = { Bramble = 20, Gloom = 0, Tempest = 0 }
	prof.pets = { { id = "Tidewing", level = 5, xp = 100 }, { id = "Emberfox", level = 1, xp = 0 } }
	prof.activePet = 1
	depth(prof, 0.35, false)
end
stages.endgame = function(prof)
	prof.started = true
	merge(prof.xp, xpFor(fill(85, { Mining = 99, Combat = 99, Smithing = 92, Dungeoneering = 72, Magic = 96, Ranged = 90, Agility = 80, Crafting = 88, Prayer = 77 })))
	local items = {}
	for id, def in pairs(Data.Items) do
		if def.kind == "material" or def.kind == "resource" then items[id] = 250 end
	end
	merge(prof.items, items)
	merge(prof.items, { SunsteelSword = 1, BrassSword = 1, WindpineStaff = 1, MeadowLongbow = 1, ObservatoryEssence = 2400, EclipsedStarcore = 6, LodestarKey = 2,
		Glimmerdust = 900, Skymark = 420, BrassArrow = 900, GaleGlyph = 400, MeadowCharm = 1, QuarryTalisman = 1 })
	merge(prof.collection, { Ore = 25000, Timber = 12000, Herb = 8000, Fish = 9000, Brassite = 4000, Shard = 600, StormFeather = 300, BeastHide = 900 })
	prof.coins, prof.bank = 4820000, 1250000
	prof.equipment = { weapon = "SunsteelSword", ammo = "BrassArrow" }
	prof.accessoryBag = { "MeadowCharm", "QuarryTalisman" }
	prof.bestiary = { BramblebackBoar = 3000, Thornling = 900, ShaleCrawler = 5000 }
	prof.slayerXp = { Bramble = 90000, Gloom = 40000, Tempest = 12000 }
	prof.pets = { { id = "Tidewing", level = 60, xp = 100 }, { id = "Emberfox", level = 40, xp = 0 } }
	prof.activePet = 1
	prof.questCompleted = 6
	depth(prof, 0.9, true)
end

-- Depth shared by mid and endgame: motes per region, a log share, museum
-- donations, a pledge, minigame points and dungeon records. `share` is 0-1.
local CL, EX, FA, DC = Data.CommissionsLogs, Data.Exploration, Data.Factions, Data.DungeonClasses
local function sorted(map)
	local out = {}
	for k in pairs(map) do table.insert(out, k) end
	table.sort(out)
	return out
end
function depth(prof, share, late)
	-- Motes: a share of each region's motes (endgame: every region but the last two).
	prof.motes = { found = {}, steps = math.floor(share * 6), paid = {}, regions = {} }
	for r, region in ipairs(EX.RegionOrder) do
		local list = EX.MotesByRegion[region] or {}
		local n = math.floor(#list * (if late and r <= #EX.RegionOrder - 2 then 1 else share * (1 - r / 12)))
		for i = 1, n do
			local m = list[i]
			prof.motes.found[if type(m) == "table" then m.id else m] = true
		end
		if n == #list and n > 0 then prof.motes.regions[region] = true; prof.motes.paid[region] = true end
	end
	prof.factions = { pledge = "Concord", pledgedAt = utc - 86400 * 9, rep = { Concord = math.floor(FA.REP_CAP * share), Circle = math.floor(1200 * share), Corsairs = 0 },
		sigils = { Concord = math.floor(900 * share), Circle = 40, Corsairs = 0 }, done = { Concord = math.floor(60 * share), Circle = 4, Corsairs = 0 }, total = math.floor(64 * share) }
	-- Commissions: lifetime completions, Glimmerdust and a Forgeheart perk or two.
	local forge = sorted(CL.Forge)
	prof.commissions = { total = if late then 160 else 12, dust = if late then 900 else 140, earned = if late then 6400 else 300,
		forge = if late then { [forge[1]] = 4, [forge[2]] = 2 } else { [forge[1]] = 1 } }
	-- Collection log: every n-th loggable item, a tab claimed late.
	local logIds = sorted(CL.log().Of)
	local counts = {}
	for i = 1, #logIds, if late then 2 else 9 do counts[logIds[i]] = if late then 3 else 1 end
	prof.colLog = { counts = counts, claimed = {}, title = "", retro = #logIds }
	-- Museum: a share of the curated items, plus a few held to donate.
	local museumIds = {}
	for id in pairs(Data.Items) do if CL.museumCategory(id) then table.insert(museumIds, id) end end
	table.sort(museumIds)
	prof.museum = { donated = {}, paid = 0 }
	for i = 1, math.floor(#museumIds * share) do prof.museum.donated[museumIds[i]] = true end
	for i = #museumIds - 2, #museumIds do prof.items[museumIds[i]] = 1 end
	-- Minigames: commendations and a log for both games.
	prof.minigames = { commendations = if late then 2400 else 180, rolls = if late then 3 else 1, log = {
		Siege = { played = if late then 140 else 9, won = if late then 101 else 5, points = if late then 41000 else 1900, best = if late then 640 else 310, paid = 0 },
		Haul = { played = if late then 60 else 2, won = if late then 38 else 1, points = if late then 15000 else 400, best = if late then 520 else 230, paid = 0 } } }
	-- Crafting: things made.
	local made = {}
	local recipes = sorted(Data.Crafting.Recipes)
	for i = 1, #recipes, if late then 1 else 6 do made[recipes[i]] = if late then 40 else 3 end
	prof.crafting = { made = made, shattered = if late then 12 else 1 }
	-- Dungeons: floor bests and clears, class XP, run log, weekly bests, a bonus chest.
	local floors = #Data.DungeonFloors
	local reached = if late then floors else 3
	prof.dungeons = { best = {}, clears = {} }
	for i = 1, reached do
		prof.dungeons.best[tostring(i)] = if late then 290 else 240 - i * 10
		prof.dungeons.clears[tostring(i)] = if late then 30 else 4 - i
	end
	local classXp = {}
	for i, id in ipairs(DC.order) do classXp[id] = math.floor((if late then 400000 else 2000) / i) end
	prof.dungeonClasses = { selected = DC.order[1], xp = classXp, secrets = { ["1"] = 2 },
		masterBest = if late then { ["1"] = 280, ["5"] = 271 } else {}, masterClears = if late then { ["1"] = 9, ["5"] = 3 } else {} }
	local log = {}
	for i = 1, if late then 8 else 3 do
		table.insert(log, { t = utc - i * 3600, f = if late then floors - (i % 3) else 1 + (i % 3), m = late and i % 2 == 1,
			g = ({ "S", "A", "B" })[1 + i % 3], s = 300 - i * 9, sec = 600 + i * 47, d = i % 3 })
	end
	prof.dungeonEndgame = { log = log, week = { id = 0, best = {}, bounty = {} },
		pb = if late then { ["7m"] = { score = 271, seconds = 1210 }, ["6"] = { score = 288, seconds = 830 } } else { ["2"] = { score = 220, seconds = 640 } },
		chest = if late then { floor = floors, master = true, grade = "S", items = { ObservatoryEssence = 20, EclipsedStarcore = 1 }, cost = 9000, expires = utc + 600 } else nil,
		runs = {} }
end

local Profiles = { order = { "early", "mid", "endgame" }, Data = Data, Progression = P }
local cache = {}
local nextId = 7001
-- Returns the server's own full snapshot for a stage (cached per run).
function Profiles.snapshot(stage)
	if cache[stage] then return copy(cache[stage]) end
	local edit = assert(stages[stage], "unknown stage " .. tostring(stage))
	nextId += 1
	local id = nextId
	local p = join(id)
	leave(p)
	edit(data["p" .. id].profile)
	p = join(id)
	-- Logs and exploration are sent in full only after a sync verb (else compact).
	local logs = cmd(p, "logsSync").logs
	local snap = cmd(p, "exploreSync")
	snap.logs = logs
	assert(type(snap) == "table" and snap.depth, "no snapshot for " .. stage)
	cache[stage] = snap
	return copy(snap)
end
return Profiles
