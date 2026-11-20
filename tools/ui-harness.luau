-- Shared headless harness for the atlas (ui.client.lua) and the combat HUD
-- (combat.client.lua): a small mock of the Roblox instance tree, the mid-game
-- snapshot from verify-ui.luau, and a JSON-friendly dump of the resulting GUI.
-- Used by tools/render-ui.luau. Unlike verify-ui.luau's mock, AbsoluteSize is
-- derived from the real ancestor chain (Size + UISizeConstraint) of a screen of
-- the requested resolution, so layout decisions in the scripts match a device.
-- Run from the project directory (paths are relative to it).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local H = {}

local function loadModule(path, env)
	return luau.load(fs.readFile(path), { debugName = path, environment = env or {}, injectGlobals = true })()
end
local Data = loadModule("shared/GameData.lua")
local Progression = loadModule("shared/Progression.lua", { script = nil })
Progression.useData(Data)
local Catalog = loadModule("art/PropCatalog.lua")
H.Data, H.Progression, H.Catalog = Data, Progression, Catalog

------------------------------------------------------------------------------
-- Mock instances
------------------------------------------------------------------------------
local function newSignal()
	local signal = { handlers = {} }
	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function signal:Once(fn)
		return self:Connect(fn)
	end
	function signal:Fire(...)
		for _, handler in ipairs(table.clone(self.handlers)) do
			handler(...)
		end
	end
	return signal
end
local events = {
	MouseButton1Down = true, MouseButton1Up = true, MouseLeave = true, SelectionGained = true, Activated = true,
	FocusLost = true, OnClientEvent = true, HealthChanged = true, CharacterAdded = true, InputBegan = true,
	TextBoxFocusReleased = true, InputEnded = true, TouchTapInWorld = true, RenderStepped = true, AncestryChanged = true,
	MouseEnter = true, SelectionLost = true, Completed = true, Heartbeat = true, InputChanged = true, CharacterRemoving = true,
	Event = true,
}
local guiClasses = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, ViewportFrame = true, TextBox = true, CanvasGroup = true }
H.guiClasses = guiClasses
local screen = roblox.Vector2.new(1366, 768)
local data = setmetatable({}, { __mode = "k" })
local methods = {}
local meta = {}
local function new(class, props)
	local object = setmetatable({}, meta)
	data[object] = { props = { ClassName = class, Name = class }, children = {}, propSignals = {}, attrs = {}, attrSignals = {} }
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	return object
end
H.new = new
local function absoluteSizeOf(object)
	local d = data[object]
	local class = d.props.ClassName
	if not guiClasses[class] or not d.parent then
		return screen
	end
	local parent = absoluteSizeOf(d.parent)
	local size = d.props.Size or roblox.UDim2.new()
	local w = size.X.Scale * parent.X + size.X.Offset
	local h = size.Y.Scale * parent.Y + size.Y.Offset
	for _, child in ipairs(d.children) do
		if child.ClassName == "UISizeConstraint" then
			local max, min = child.MaxSize, child.MinSize
			if max then w, h = math.min(w, max.X), math.min(h, max.Y) end
			if min then w, h = math.max(w, min.X), math.max(h, min.Y) end
		end
	end
	return roblox.Vector2.new(math.max(0, w), math.max(0, h))
end
meta.__index = function(self, key)
	if methods[key] then
		return methods[key]
	end
	local d = data[self]
	if key == "Parent" then
		return d.parent
	end
	local value = d.props[key]
	if value ~= nil then
		return value
	end
	if events[key] then
		local signal = newSignal()
		d.props[key] = signal
		return signal
	end
	if key == "AbsoluteSize" or key == "AbsoluteCanvasSize" or key == "AbsoluteWindowSize" then
		return absoluteSizeOf(self)
	elseif key == "AbsolutePosition" or key == "CanvasPosition" then
		return roblox.Vector2.zero
	elseif key == "ViewportSize" then
		return screen
	end
	return nil
end
meta.__newindex = function(self, key, value)
	local d = data[self]
	if key == "Parent" then
		assert(not d.destroyed, "The Parent property of a destroyed instance is locked")
		if d.parent then
			local siblings = data[d.parent].children
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		d.parent = value
		if value then
			table.insert(data[value].children, self)
		end
		return
	end
	d.props[key] = value
	local signal = d.propSignals[key]
	if signal then
		signal:Fire()
	end
end
meta.__tostring = function(self)
	return tostring(data[self].props.Name)
end
function methods:FindFirstChild(name)
	for _, child in ipairs(data[self].children) do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(data[self].children) do
		if child.ClassName == class then
			return child
		end
	end
	return nil
end
function methods:GetChildren()
	return table.clone(data[self].children)
end
function methods:GetDescendants()
	local out = {}
	local function walk(object)
		for _, child in ipairs(data[object].children) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function methods:IsA(class)
	local own = data[self].props.ClassName
	return own == class or class == "Instance" or (class == "GuiObject" and guiClasses[own] == true)
end
function methods:IsDescendantOf(other)
	local parent = data[self].parent
	while parent do
		if parent == other then
			return true
		end
		parent = data[parent].parent
	end
	return false
end
function methods:FindFirstAncestorWhichIsA(class)
	local parent = data[self].parent
	while parent do
		if parent:IsA(class) then
			return parent
		end
		parent = data[parent].parent
	end
	return nil
end
function methods:Destroy()
	for _, child in ipairs(table.clone(data[self].children)) do
		child:Destroy()
	end
	self.Parent = nil
	data[self].destroyed = true
end
function methods:Clone()
	local copy = new(self.ClassName)
	for key, value in pairs(data[self].props) do
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			if key ~= "ClassName" then
				copy[key] = value
			end
		end
	end
	for _, child in ipairs(data[self].children) do
		child:Clone().Parent = copy
	end
	return copy
end
function methods:GetBoundingBox()
	return roblox.CFrame.new(), roblox.Vector3.new(1, 2, 1)
end
function methods:GetPropertyChangedSignal(name)
	local d = data[self]
	d.propSignals[name] = d.propSignals[name] or newSignal()
	return d.propSignals[name]
end
function methods:GetAttribute(name)
	return data[self].attrs[name]
end
function methods:SetAttribute(name, value)
	local d = data[self]
	d.attrs[name] = value
	if d.attrSignals[name] then
		d.attrSignals[name]:Fire()
	end
end
function methods:GetAttributeChangedSignal(name)
	local d = data[self]
	d.attrSignals[name] = d.attrSignals[name] or newSignal()
	return d.attrSignals[name]
end
-- BindableEvent:Fire relays to .Event (local channels between client scripts).
function methods:Fire(...)
	self.Event:Fire(...)
end
function methods:FireServer(...)
	local d = data[self]
	d.fired = d.fired or {}
	table.insert(d.fired, table.pack(...))
end
function methods:InvokeServer(...)
	return data[self].props.OnInvoke(...)
end
function methods:GetPlayers()
	return { self.LocalPlayer }
end
-- Tweens jump straight to their goals so renders show the settled state
-- (open/close, slide-in and pop-in transitions end where they come to rest).
function methods:Create(object, _, goals)
	return { Play = function()
		if type(goals) == "table" and object ~= nil and data[object] then
			for key, value in pairs(goals) do object[key] = value end
		end
	end, Completed = newSignal() }
end
function methods:GetServerTimeNow()
	return 100
end
function methods:GetFocusedTextBox()
	return nil
end

------------------------------------------------------------------------------
-- Mid-game snapshot (same record verify-ui.luau sweeps)
------------------------------------------------------------------------------
local function profile()
	return {
		xp = { Combat = 9000, Mining = 22000, Woodcutting = 400, Fishing = 0, Farming = 60, Smithing = 4500, Cooking = 100, Alchemy = 0, Enchanting = 1200, Taming = 0, Dungeoneering = 0, Carpentry = 50,
			Ranged = 5200, Magic = 14100, Fletching = 1200, Glyphcraft = 800 },
		items = {
			Ore = 140, Timber = 40, Herb = 70, Fish = 30, Brassite = 12, Pickaxe = 1, Blade = 1, Tonic = 2, ExpeditionRation = 1,
			BrassSword = 1, BrassHelm = 1, BrassChestplate = 1, BrassGreaves = 1, BrassBoots = 1, SunsteelSword = 1, BrassPickaxe = 1,
			CopperHatchet = 1, ArcaneDust = 60, MeadowCharm = 1, QuarryTalisman = 1, EmberfoxPet = 1, CookedFish = 3, MightDraught = 2,
			StormFeather = 3, BrassIngot = 9,
			-- Combat styles: a Tide staff wielded, arrows in the quiver, glyphs and a tablet.
			WindpineStaff = 1, MeadowWand = 1, MeadowLongbow = 1, WindpineShortbow = 1, CopperArrow = 60, BrassArrow = 143,
			GaleGlyph = 40, TideGlyph = 8, StoneGlyph = 12, SparkGlyph = 25, SurgeGlyph = 6, VitaGlyph = 3, BindGlyph = 2, HubwardTablet = 2,
			ArrowShaft = 30, DriftPlume = 20,
		},
		collection = { Ore = 320, Timber = 60, Herb = 70, Fish = 30, Brassite = 40, Shard = 2, StormFeather = 3, BeastHide = 0 },
		equipment = { weapon = "WindpineStaff", helmet = "BrassHelm", chest = "BrassChestplate", legs = "BrassGreaves", boots = "BrassBoots", ammo = "BrassArrow" },
		autocast = "GaleLance",
		enchants = { BrassSword = { Sharpness = 2, Critical = 5 } },
		accessoryBag = { "MeadowCharm", "QuarryTalisman" },
		pets = { { id = "Tidewing", level = 5, xp = 100 }, { id = "Emberfox", level = 1, xp = 0 } },
		activePet = 1,
		buffs = { MightDraught = { expires = 120, stats = { strength = 15 } } },
		bestiary = { BramblebackBoar = 30, Thornling = 1, ShaleCrawler = 1000 },
		slayerXp = { Bramble = 20, Gloom = 0, Tempest = 0 },
	}
end
function H.snapshot(options)
	options = options or {}
	local p = profile()
	if options.weapon ~= nil then
		p.equipment.weapon = options.weapon or nil
	end
	if options.xp then
		for skill, xp in pairs(options.xp) do
			p.xp[skill] = xp
		end
	end
	local levels = {}
	for skill, xp in pairs(p.xp) do
		levels[skill] = Progression.levelForXp(xp)
	end
	local result = {
		xp = p.xp, items = p.items, collection = p.collection, coins = 52000, bank = 12500, bankRevision = 3, levels = levels, message = options.message or "",
		consumables = { Tonic = { healing = 40, recovery = 0, action = "Drink", readyIn = 0 }, ExpeditionRation = { healing = 65, recovery = 12, action = "Eat", readyIn = 5 } },
		recipes = { { id = "Pickaxe", costs = { Ore = 3, Timber = 2 }, skill = "Smithing", level = 1, collection = { Ore = 3 }, description = "A pick", repeatable = false, unlocked = true, xp = 24 } },
		regions = { { name = "Skyreach", unlocked = false, requirement = "Complete 6 contracts" } },
		stats = { maxHealth = 120, defense = 5 }, quest = { title = "Guild contract: Brassfall survey", detail = "Mine 20 ore at Brassfall Quarry and report back to the Quay.", ready = true },
		slayer = { tier = 1, active = true, progress = 1, target = 2, ready = false, completed = 0, coins = 20, xp = 30 },
		workers = { { resource = "Ore", tier = 1, ready = 3, interval = 120, capacity = 60 } }, decorations = { Garden = true },
		started = true, companionBond = 2, enchantRank = 1, worker = true,
		economy = {
			bazaar = { item = "Ore", bids = { { price = 20, qty = 30, orders = 2 }, { price = 18, qty = 5, orders = 1 } }, asks = { { price = 25, qty = 10, orders = 1 }, { price = 27, qty = 44, orders = 3 } },
				bestBid = 20, bestAsk = 25, spread = 5, openOrders = 4, mine = {}, claimUnits = 3, claimCoins = 40, fetchedAt = 0, revision = 3, matchingPolicy = "Highest bid first." },
			auction = { category = "weapon", page = 1, pages = 2, total = 9, proceeds = 50, returns = 1, fetchedAt = 0, revision = 2,
				listings = { { id = 4, item = "SunsteelSword", price = 900, remaining = 3600, own = false }, { id = 5, item = "BrassSword", price = 1000, remaining = 60, own = true } } },
			orders = { { item = "Ore", id = 7, side = "bid", price = 20, qty = 10 }, { item = "Herb", id = 2, side = "ask", price = 4, qty = 5 } },
			listings = { { cat = "weapon", id = 5, item = "BrassSword", price = 1000, expires = 500 }, { cat = "pet", id = 9, item = "EmberfoxPet", price = 150, expires = 50 } },
			pending = false, readyIn = 0, serverTime = 100,
		},
	}
	local skills, total = {}, 0
	for _, skill in ipairs(Data.SkillOrder) do
		local progress = Progression.progress(p.xp[skill] or 0)
		skills[skill] = { level = progress.level, xp = progress.current, floor = progress.floor, ceiling = progress.ceiling, fraction = progress.fraction, maxed = progress.maxed }
		total += progress.level
	end
	local stats = Progression.computeStats(p, 0)
	local collections = {}
	for _, id in ipairs(Data.CollectionItems) do
		local tier = Progression.collectionTier(p, id)
		collections[id] = { count = p.collection[id] or 0, tier = tier, nextAt = Progression.collectionThreshold(id, tier + 1) }
	end
	local pets = {}
	for index, pet in ipairs(p.pets) do
		pets[index] = { id = pet.id, level = pet.level, xp = pet.xp, next = Data.petXpToNext(pet.level, Data.PetById[pet.id].rarity), active = p.activePet == index }
	end
	local tools = {}
	for _, skill in ipairs({ "Mining", "Woodcutting", "Fishing", "Farming" }) do
		tools[skill] = (Progression.bestTool(p, skill))
	end
	local lines = {}
	for _, line in ipairs(Data.SlayerOrder) do
		local level = Progression.slayerLevel(p.slayerXp[line])
		lines[line] = { xp = p.slayerXp[line], level = level, nextAt = Data.SlayerLevels[level + 1] }
	end
	result.depth = {
		skills = skills, totalLevel = total, skillAverage = total / #Data.SkillOrder, stats = stats, equipment = p.equipment, tools = tools,
		accessoryBag = p.accessoryBag, activeAccessories = Progression.activeAccessories(p), accessorySlots = Progression.accessorySlots(p),
		pets = pets, buffs = { MightDraught = { remaining = 95, stats = { strength = 15 } } }, collections = collections, bestiary = p.bestiary,
		slayer = { lines = lines, quest = { line = "Bramble", tier = 1, progress = 40, needed = 150, bossReady = false } },
		enchants = p.enchants, combat = Progression.combatLoadout(p),
		regions = { { id = "Hub", name = "Aether Hub", unlocked = true, requirement = "" }, { id = "Gloomhollow", name = "Gloomhollow Caverns", unlocked = false, requirement = "Mining 30, Combat 15" } },
	}
	local quests = {}
	for i, q in ipairs(Data.Quests) do
		local function pairsFor(list, met)
			local out = {}
			for k, o in ipairs(list) do
				local need = o.count or o.level or o.tier or 1
				out[k] = { if met then need else 0, need }
			end
			return out
		end
		local status = ({ SurveyorsOath = "done", ThornlingGarden = "ready", TidewingLullaby = "ready", BrassfallEchoes = "available" })[q.id]
		quests[i] = { id = q.id, done = status == "done", available = status ~= nil, ready = status == "ready",
			requires = pairsFor(q.requires, status ~= nil), objectives = pairsFor(q.objectives, status == "ready" or status == "done") }
	end
	local diaries = {}
	for i, d in ipairs(Data.Diaries) do
		local tiers = {}
		for t, name in ipairs(Data.DiaryTiers) do
			local tasks = {}
			for k, o in ipairs(d.tiers[name].tasks) do tasks[k] = { t <= 2 and (o.count or o.level or 1) or 0, o.count or o.level or 1 } end
			tiers[t] = { tier = name, tasks = tasks, complete = t <= 2, claimed = t == 1 and d.region == "Meadow", claimable = (t == 1 and d.region ~= "Meadow") or (t == 2 and d.region == "Meadow") }
		end
		diaries[i] = { region = d.region, claimed = d.region == "Meadow" and 1 or 0, tiers = tiers }
	end
	result.journal = {
		questPoints = 12, contracts = 8, quests = quests, diaries = diaries,
		construction = { furniture = { Bench = "SturdyWorkbench", Portal = "PortalFrame" }, portal = "Skyreach", portalRegions = { "Skyreach", "Windpine" },
			carpentry = 32, accessorySlots = 1, workerHaste = 0.05 },
	}
	return result
end

------------------------------------------------------------------------------
-- Environments
------------------------------------------------------------------------------
local function baseTask()
	return {
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			local ok, problem = coroutine.resume(co, ...)
			assert(ok, problem)
			return co
		end,
		delay = function() end,
		defer = function(fn, ...) fn(...) end,
		wait = function() return coroutine.yield() end,
	}
end
-- Loads ui.client.lua for a screen of `size` pixels and returns handles.
function H.runAtlas(size, options)
	options = options or {}
	screen = size
	local warnings, sent = {}, {}
	local current = options.snapshot or H.snapshot()
	local playerGui = new("PlayerGui")
	local player = new("Player", { Name = "Voyager", DisplayName = "Voyager", UserId = 1 })
	playerGui.Parent = player
	local players = new("Players", { LocalPlayer = player })
	local replicated = new("ReplicatedStorage")
	local modules = {}
	local function module(name, value)
		local object = new("ModuleScript", { Name = name })
		object.Parent = replicated
		modules[object] = value
	end
	module("AetherArt", Catalog)
	module("AetherData", Data)
	local action = new("RemoteFunction", { Name = "IsleAction" })
	action.OnInvoke = function(verb, item)
		table.insert(sent, { verb, item })
		return current
	end
	action.Parent = replicated
	local update = new("RemoteEvent", { Name = "IsleUpdate" })
	update.Parent = replicated
	new("RemoteEvent", { Name = "IsleCoopUpdate" }).Parent = replicated
	local coop = new("RemoteFunction", { Name = "IsleCoopAction" })
	coop.OnInvoke = function()
		return options.coop or { members = {}, invites = {}, message = "" }
	end
	coop.Parent = replicated
	local services = {
		Players = players, ReplicatedStorage = replicated, UserInputService = new("UserInputService", { GamepadEnabled = false, TouchEnabled = options.touch == true }),
		GuiService = new("GuiService"), TweenService = new("TweenService"),
	}
	local game = new("DataModel")
	function game.GetService(_, name)
		return assert(services[name], name)
	end
	local env = {
		game = game, workspace = new("Workspace"), Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		TweenInfo = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end },
		require = function(target)
			local value = modules[target]
			assert(value ~= nil, "unexpected require")
			return value
		end,
		warn = function(...)
			table.insert(warnings, table.concat(table.pack(...), " "))
		end,
		print = function() end,
		task = baseTask(),
	}
	local chunk = luau.load(fs.readFile("ui.client.lua"), { debugName = "ui.client.lua", environment = env, injectGlobals = true })
	local main = coroutine.create(chunk)
	local ok, problem = coroutine.resume(main)
	assert(ok, problem)
	local gui = playerGui:FindFirstChild("AetherAtlas")
	local atlas = gui:FindFirstChild("Atlas")
	return {
		gui = gui, atlas = atlas, scroll = atlas:FindFirstChildOfClass("ScrollingFrame"), tabs = atlas:FindFirstChild("Tabs"),
		sent = sent, warnings = warnings, player = player, playerGui = playerGui, update = update, replicated = replicated,
		setSnapshot = function(value) current = value end,
	}
end
-- Loads combat.client.lua into an existing player's PlayerGui. Pass the atlas
-- handle's `replicated` to share its local channels (snapshots, toasts, verbs).
function H.runCombat(size, player, shared)
	screen = size
	local replicated = shared or new("ReplicatedStorage")
	if not replicated:FindFirstChild("AetherData") then new("ModuleScript", { Name = "AetherData" }).Parent = replicated end
	local remote = new("RemoteEvent", { Name = "IsleCombat" })
	remote.Parent = replicated
	local fx = new("RemoteEvent", { Name = "IsleCombatFx" })
	fx.Parent = replicated
	local tagged = {}
	local services = {
		Players = new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated,
		UserInputService = new("UserInputService", { TouchEnabled = true }), RunService = new("RunService"),
		TweenService = new("TweenService"), Workspace = new("Workspace"),
		CollectionService = { GetTagged = function() return tagged end, HasTag = function(_, object) return table.find(tagged, object) ~= nil end },
	}
	local camera = new("Camera")
	camera.Parent = services.Workspace
	services.Workspace.CurrentCamera = camera
	local terrain = new("Terrain", { Name = "Terrain" })
	terrain.Parent = services.Workspace
	services.Workspace.Terrain = terrain
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local env = {
		game = game, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2, Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberRange = roblox.NumberRange,
		TweenInfo = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end }, RaycastParams = { new = function() return {} end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		require = function(target)
			assert(target.Name == "AetherData", "unexpected require")
			return Data
		end,
		task = baseTask(),
	}
	local chunk = luau.load(fs.readFile("combat.client.lua"), { debugName = "combat.client.lua", environment = env, injectGlobals = true })
	chunk()
	local monster = new("Model", { Name = "Golem" })
	monster.Parent = services.Workspace
	return { hud = player:FindFirstChild("PlayerGui"):FindFirstChild("IsleCombatHud"), fx = fx, remote = remote, monster = monster, tagged = tagged,
		run = services.RunService, workspace = services.Workspace, input = services.UserInputService }
end

-- A founded crew (Journal > Crew) for renders.
function H.coopSample()
	return {
		groupId = "1", owner = 1, ironman = false, maxMembers = 4, message = "",
		members = {
			{ userId = 1, name = "Voyager", role = "Leader", points = 420, gathered = 120, deposited = 60, withdrawn = 10, built = 2, worker = 1 },
			{ userId = 2, name = "Marisol", role = "Member", points = 180, gathered = 70, deposited = 20, withdrawn = 0, built = 1, worker = 0 },
		},
		level = { level = 2, xp = 340, floor = 200, nextXp = 600, stats = { health = 4 }, nextStats = { health = 8 }, storage = 200, workerSlots = 1, workerTier = 1,
			nextStorage = 300, nextWorkers = 1 },
		resources = { "Timber", "Ore", "Herb", "Fish" }, supplies = { Timber = 64, Ore = 30, Herb = 12, Fish = 0 },
		workers = { { slot = 1, resource = "Ore", tier = 1, interval = 90, ready = 14, capacity = 40, upgradeCost = { Timber = 20, Ore = 10 } } },
		decorations = { Garden = true }, log = { "Marisol deposited 10 Timber", "Voyager built Garden" },
		outgoing = {}, kickReasons = { { id = "afk", text = "Inactive" } }, invites = {},
	}
end
-- Loads build.client.lua (the island builder HUD) for an existing player.
function H.runBuilder(size, player)
	screen = size
	local replicated = new("ReplicatedStorage")
	local dataModule = new("ModuleScript", { Name = "AetherData" })
	dataModule.Parent = replicated
	local workspace = new("Workspace")
	local camera = new("Camera", { ViewportSize = size })
	camera.Parent = workspace
	workspace.CurrentCamera = camera
	camera.ViewportPointToRay = function(_, x, y) return { Origin = roblox.Vector3.new(x, 50, y), Direction = roblox.Vector3.new(0, -1, 0) } end
	workspace.Raycast = function() return { Position = roblox.Vector3.new(4, 0, 6), Instance = workspace } end
	player:SetAttribute("IslandCenter", roblox.Vector3.new(0, 0, 0))
	player:SetAttribute("IslandPlacements", "")
	local services = { Players = new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated,
		UserInputService = new("UserInputService", { MouseEnabled = true, TouchEnabled = true }), RunService = new("RunService"),
		ContextActionService = { BindActionAtPriority = function() end, UnbindAction = function() end }, TweenService = new("TweenService") }
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local env = {
		game = game, workspace = workspace, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
		TweenInfo = { new = function() return {} end }, RaycastParams = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		require = function() return Data end,
	}
	luau.load(fs.readFile("build.client.lua"), { debugName = "build.client.lua", environment = env, injectGlobals = true })()
	return {
		enter = function(mode, prop)
			player:SetAttribute("IslandBuildMode", mode)
			player:SetAttribute("IslandBuildProp", prop or "")
			player:SetAttribute("IslandBuildRequest", (player:GetAttribute("IslandBuildRequest") or 0) + 1)
		end,
	}
end

-- Calls recorded by a RemoteEvent's FireServer.
function H.fired(remote)
	return data[remote].fired or {}
end
function H.find(root, name)
	for _, object in ipairs(root:GetDescendants()) do
		if object.Name == name then
			return object
		end
	end
	return nil
end
function H.press(object)
	assert(object, "missing button")
	object.Activated:Fire()
end

------------------------------------------------------------------------------
-- Dump: a plain table tree of every GUI object and UI component.
------------------------------------------------------------------------------
local paletteSet = {}
for _, hex in ipairs(Catalog.palette) do
	paletteSet[string.upper(hex)] = true
end
local skipped = { Model = true, Camera = true, WedgePart = true, Part = true, Highlight = true, Attachment = true, BillboardGui = true }
local function encode(value)
	local kind = typeof(value)
	if kind == "number" or kind == "string" or kind == "boolean" then
		return value
	elseif kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif kind == "UDim" then
		return { value.Scale, value.Offset }
	elseif kind == "Vector2" then
		return { value.X, value.Y }
	elseif kind == "Color3" then
		return "#" .. value:ToHex()
	elseif kind == "EnumItem" then
		return value.Name
	elseif kind == "ColorSequence" then
		local out = {}
		for _, k in ipairs(value.Keypoints) do
			table.insert(out, { k.Time, "#" .. k.Value:ToHex() })
		end
		return { seq = out }
	elseif kind == "NumberSequence" then
		local out = {}
		for _, k in ipairs(value.Keypoints) do
			table.insert(out, { k.Time, k.Value })
		end
		return { nseq = out }
	end
	return nil
end
function H.dump(object)
	local d = data[object]
	local props = {}
	for key, value in pairs(d.props) do
		if key ~= "ClassName" then
			local encoded = encode(value)
			if encoded ~= nil then
				props[key] = encoded
			end
		end
	end
	local node = { class = d.props.ClassName, props = props, children = {} }
	if d.props.ClassName == "ViewportFrame" then
		for _, child in ipairs(d.children) do
			if child.ClassName == "Model" then
				node.shape = child.Name
				for _, part in ipairs(child:GetChildren()) do
					local color = part.Color
					if color and not paletteSet[string.upper(color:ToHex())] then
						node.tint = "#" .. color:ToHex()
						break
					end
				end
			end
		end
	end
	for _, child in ipairs(d.children) do
		if not skipped[child.ClassName] then
			table.insert(node.children, H.dump(child))
		end
	end
	return node
end

return H
