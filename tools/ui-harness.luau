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
-- The shared theme builds instances, so each client script gets a copy loaded
-- in its own environment (its Instance.new is the mock's).
function H.loadTheme(env)
	return luau.load(fs.readFile("shared/UiTheme.lua"), { debugName = "shared/UiTheme.lua", environment = env, injectGlobals = true })()
end
-- Map Art (shared/MapArt.lua, §32) in a script's environment (its Instance.new is the mock's).
function H.loadMapArt(env)
	return luau.load(fs.readFile("shared/MapArt.lua"), { debugName = "shared/MapArt.lua", environment = env, injectGlobals = true })()
end
H.Data, H.Progression, H.Catalog = Data, Progression, Catalog
-- HUD depth rules (shared/HudDepth.lua, §34): pure, no instances.
H.HudDepth = loadModule("shared/HudDepth.lua")

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
	Event = true, MouseButton2Click = true, AttributeChanged = true, TouchPinch = true, Destroying = true,
	Triggered = true, PromptButtonHoldEnded = true,
	TouchLongPress = true, PlayerAdded = true, PlayerRemoving = true,
}
local guiClasses = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, ViewportFrame = true, TextBox = true, CanvasGroup = true }
H.guiClasses = guiClasses
local screen = roblox.Vector2.new(1366, 768)
-- Per-instance state lives inside the instance table itself, under a private
-- key. A weak-keyed side table would leak every instance: Luau has no
-- ephemerons, so a value that references its own key (a child's `parent`, a
-- signal handler closing over its button) keeps the key alive forever.
local STATE = newproxy(false)
local data = setmetatable({}, {
	__index = function(_, object)
		return if type(object) == "table" then rawget(object, STATE) else nil
	end,
	__newindex = function(_, object, value)
		rawset(object, STATE, value)
	end,
})
local methods = {}
local meta = {}
local function new(class, props)
	local object = setmetatable({}, meta)
	rawset(object, STATE, { props = { ClassName = class, Name = class }, children = {}, propSignals = {}, attrs = {}, attrSignals = {} })
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	return object
end
H.new = new
local function absoluteSizeOf(object)
	local d = rawget(object, STATE)
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
	local d = rawget(self, STATE)
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
	local d = rawget(self, STATE)
	if key == "Parent" then
		assert(not d.destroyed, "The Parent property of a destroyed instance is locked")
		if d.parent then
			local siblings = rawget(d.parent, STATE).children
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		d.parent = value
		if value then
			table.insert(rawget(value, STATE).children, self)
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
	return tostring(rawget(self, STATE).props.Name)
end
function methods:FindFirstChild(name, recursive)
	for _, child in ipairs(rawget(self, STATE).children) do
		if child.Name == name then
			return child
		end
	end
	-- FindFirstChild(name, true): depth-first like Roblox (§43 tutorial pointer).
	if recursive then
		for _, child in ipairs(rawget(self, STATE).children) do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(rawget(self, STATE).children) do
		if child.ClassName == class then
			return child
		end
	end
	return nil
end
function methods:GetChildren()
	return table.clone(rawget(self, STATE).children)
end
function methods:GetDescendants()
	local out = {}
	local function walk(object)
		for _, child in ipairs(rawget(object, STATE).children) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function methods:IsA(class)
	local own = rawget(self, STATE).props.ClassName
	return own == class or class == "Instance" or (class == "GuiObject" and guiClasses[own] == true)
		or (class == "BasePart" and (own == "Part" or own == "MeshPart" or own == "WedgePart" or own == "TrussPart"))
end
function methods:IsDescendantOf(other)
	local parent = rawget(self, STATE).parent
	while parent do
		if parent == other then
			return true
		end
		parent = rawget(parent, STATE).parent
	end
	return false
end
function methods:FindFirstAncestorWhichIsA(class)
	local parent = rawget(self, STATE).parent
	while parent do
		if parent:IsA(class) then
			return parent
		end
		parent = rawget(parent, STATE).parent
	end
	return nil
end
-- Destroy releases what Roblox releases: descendants are destroyed, the
-- instance leaves its parent and every connection on it is dropped, so the
-- closures (and the trees they capture) can be collected.
local function isSignal(value)
	return type(value) == "table" and getmetatable(value) == nil and type(rawget(value, "handlers")) == "table" and rawget(value, "Connect") ~= nil
end
function methods:Destroy()
	local d = rawget(self, STATE)
	local children = d.children
	d.children = {}
	for _, child in ipairs(children) do
		rawget(child, STATE).parent = nil -- already detached: skip the O(n) sibling search
		child:Destroy()
	end
	self.Parent = nil
	d.destroyed = true
	for _, value in pairs(d.props) do
		if isSignal(value) then
			table.clear(value.handlers)
		end
	end
	for _, signal in pairs(d.propSignals) do
		table.clear(signal.handlers)
	end
	for _, signal in pairs(d.attrSignals) do
		table.clear(signal.handlers)
	end
end
function methods:Clone()
	local copy = new(self.ClassName)
	for key, value in pairs(rawget(self, STATE).props) do
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			if key ~= "ClassName" then
				copy[key] = value
			end
		end
	end
	for _, child in ipairs(rawget(self, STATE).children) do
		child:Clone().Parent = copy
	end
	return copy
end
function methods:GetBoundingBox()
	return roblox.CFrame.new(), roblox.Vector3.new(1, 2, 1)
end
function methods:GetPropertyChangedSignal(name)
	local d = rawget(self, STATE)
	d.propSignals[name] = d.propSignals[name] or newSignal()
	return d.propSignals[name]
end
function methods:GetAttribute(name)
	return rawget(self, STATE).attrs[name]
end
function methods:SetAttribute(name, value)
	local d = rawget(self, STATE)
	d.attrs[name] = value
	if d.attrSignals[name] then
		d.attrSignals[name]:Fire()
	end
end
function methods:GetAttributeChangedSignal(name)
	local d = rawget(self, STATE)
	d.attrSignals[name] = d.attrSignals[name] or newSignal()
	return d.attrSignals[name]
end
-- BindableEvent:Fire relays to .Event (local channels between client scripts).
function methods:Fire(...)
	self.Event:Fire(...)
end
function methods:FireServer(...)
	local d = rawget(self, STATE)
	d.fired = d.fired or {}
	table.insert(d.fired, table.pack(...))
end
function methods:InvokeServer(...)
	return rawget(self, STATE).props.OnInvoke(...)
end
function methods:GetPlayers()
	return { self.LocalPlayer }
end
-- Tweens jump straight to their goals so renders show the settled state
-- (open/close, slide-in and pop-in transitions end where they come to rest).
-- Play / Pause / Cancel record `playing` so tests can see which loops run.
function methods:Create(object, _, goals)
	local tween = { Completed = newSignal(), playing = false }
	function tween.Play()
		tween.playing = true
		if type(goals) == "table" and object ~= nil and data[object] then
			for key, value in pairs(goals) do object[key] = value end
		end
	end
	function tween.Pause() tween.playing = false end
	function tween.Cancel() tween.playing = false end
	return tween
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
			Ranged = 5200, Magic = 14100, Fletching = 1200, Glyphcraft = 800, Agility = 3400, Hunter = 2600 },
		items = {
			Ore = 140, Timber = 40, Herb = 70, Fish = 30, Brassite = 12, Pickaxe = 1, Blade = 1, Tonic = 2, ExpeditionRation = 1,
			BrassSword = 1, BrassHelm = 1, BrassChestplate = 1, BrassGreaves = 1, BrassBoots = 1, SunsteelSword = 1, BrassPickaxe = 1,
			CopperHatchet = 1, ArcaneDust = 60, MeadowCharm = 1, QuarryTalisman = 1, EmberfoxPet = 1, CookedFish = 3, MightDraught = 2,
			StormFeather = 3, BrassIngot = 9,
			-- Combat styles: a Tide staff wielded, arrows in the quiver, glyphs and a tablet.
			WindpineStaff = 1, MeadowWand = 1, MeadowLongbow = 1, WindpineShortbow = 1, CopperArrow = 60, BrassArrow = 143,
			GaleGlyph = 40, TideGlyph = 8, StoneGlyph = 12, SparkGlyph = 25, SurgeGlyph = 6, VitaGlyph = 3, BindGlyph = 2, HubwardTablet = 2,
			ArrowShaft = 30, DriftPlume = 20,
			-- Agility & Hunter: Skymarks, a Windrunner piece, kits and pelts.
			Skymark = 37, WindrunnerHood = 1, SnareKit = 1, SkyNet = 1, DownyPelt = 14, SunwingDust = 6,
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
		regions = { { id = "Hub", name = "Compass Quay", unlocked = true, requirement = "" }, { id = "Gloomhollow", name = "Gloomhollow Caverns", unlocked = false, requirement = "Mining 30, Combat 15" } },
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
	-- Agility & Hunter (server Skills.state): records, traps and the Skymark Exchange open.
	result.agilityHunter = {
		agility = { laps = { QuayRigging = 31, MosswakeHedgerow = 4 }, best = { QuayRigging = 41.2, MosswakeHedgerow = 63.8 }, lapTiers = 1,
			run = { course = "QuayRigging", next = 3, expiresIn = 22 } },
		hunter = { log = { PuffcapHopper = 27, SunwingMoth = 9 }, logTiers = 2, maxTraps = 2,
			traps = { { creature = "PuffcapHopper", state = "caught", ticks = 6, spot = "PuffcapHopper#1" }, { creature = "PuffcapHopper", state = "set", ticks = 2, spot = "PuffcapHopper#3" } } },
		vendor = { skill = "Agility", openUntil = os.time() + 252 },
	}
	return result
end
-- Live attributes for a lap underway (obstacle 3 of 6) and two traps, one caught.
function H.agilityHud(player)
	player:SetAttribute("AgilityRun", "QuayRigging:3:6")
	player:SetAttribute("AgilityRunExpires", os.time() + 22)
	player:SetAttribute("HunterTraps", "2/2")
	player:SetAttribute("HunterTrapsCaught", 1)
	player:SetAttribute("SkillVendor", "Agility")
	player:SetAttribute("SkillVendorUntil", os.time() + 252)
end

------------------------------------------------------------------------------
-- Environments
------------------------------------------------------------------------------
-- delays: optional list that records task.delay calls ({seconds, fn, args}) so a
-- test can run them on demand; otherwise delayed callbacks never run.
local function baseTask(delays)
	return {
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			local ok, problem = coroutine.resume(co, ...)
			assert(ok, problem)
			return co
		end,
		delay = function(seconds, fn, ...)
			if delays and type(fn) == "function" then table.insert(delays, { seconds = seconds, fn = fn, args = table.pack(...) }) end
		end,
		defer = function(fn, ...) fn(...) end,
		wait = function() return coroutine.yield() end,
	}
end
-- Loads ui.client.lua for a screen of `size` pixels and returns handles.
function H.runAtlas(size, options)
	options = options or {}
	screen = size
	local warnings, sent, delays = {}, {}, {}
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
	if options.lighting then module("AetherLighting", options.lighting) end -- §35 Settings › Graphics quality reads L.Tiers
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
		task = baseTask(delays),
	}
	local themeObject = new("ModuleScript", { Name = "AetherUiTheme" })
	themeObject.Parent = replicated
	modules[themeObject] = H.loadTheme(env)
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
		delays = delays,
		-- Runs (and clears) every recorded task.delay callback of at most `upTo` seconds.
		runDelays = function(upTo)
			local due = {}
			for i = #delays, 1, -1 do
				if delays[i].seconds == nil or delays[i].seconds <= (upTo or math.huge) then table.insert(due, 1, table.remove(delays, i)) end
			end
			for _, d in ipairs(due) do d.fn(table.unpack(d.args, 1, d.args.n)) end
			return #due
		end,
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
		task = baseTask(),
	}
	local theme = H.loadTheme(env)
	env.require = function(target)
		if target.Name == "AetherUiTheme" then return theme end
		if target.Name == "AetherHudDepth" then return H.HudDepth end
		assert(target.Name == "AetherData", "unexpected require")
		return Data
	end
	if not replicated:FindFirstChild("AetherUiTheme") then new("ModuleScript", { Name = "AetherUiTheme" }).Parent = replicated end
	if not replicated:FindFirstChild("AetherHudDepth") then new("ModuleScript", { Name = "AetherHudDepth" }).Parent = replicated end
	local chunk = luau.load(fs.readFile("combat.client.lua"), { debugName = "combat.client.lua", environment = env, injectGlobals = true })
	chunk()
	local monster = new("Model", { Name = "Golem" })
	monster.Parent = services.Workspace
	local api = player:FindFirstChild("IsleCombatApi")
	return { hud = player:FindFirstChild("PlayerGui"):FindFirstChild("IsleCombatHud"), fx = fx, remote = remote, monster = monster, tagged = tagged,
		state = api and api.OnInvoke("state"),
		run = services.RunService, workspace = services.Workspace, input = services.UserInputService }
end

-- Loads hud.client.lua (satchel, paperdoll, XP drops, Sky Chart) into an
-- existing player's PlayerGui; pass the atlas handle's `replicated` so the
-- local channels (snapshots, verbs, XP, HUD commands) are shared.
function H.runHud(size, player, shared, options)
	options = options or {}
	screen = size
	local replicated = shared or new("ReplicatedStorage")
	-- StarterGui records SetCoreGuiEnabled calls (hud.client.lua turns the player list off).
	local coreGui = {}
	local services = {
		Players = new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated,
		UserInputService = new("UserInputService", { TouchEnabled = options.touch == true }), TweenService = new("TweenService"),
		StarterGui = { SetCoreGuiEnabled = function(_, kind, enabled) coreGui[kind.Name] = enabled end },
		ProximityPromptService = { PromptShown = newSignal(), PromptHidden = newSignal() },
	}
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local camera = new("Camera")
	-- options.workspace: a table standing in for Workspace (e.g. the real Islands /
	-- AetherIsles folders built by world.server.lua, for the Sky Chart miniature).
	local space = options.workspace or { CurrentCamera = camera }
	local env = {
		game = game, workspace = space, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2, Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, TweenInfo = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		task = baseTask(options.delays),
	}
	local theme = H.loadTheme(env)
	local mapArt = H.loadMapArt(env)
	env.require = function(target)
		if target.Name == "AetherUiTheme" then return theme end
		if target.Name == "AetherMapArt" then return mapArt end
		return Data
	end
	if not replicated:FindFirstChild("AetherUiTheme") then new("ModuleScript", { Name = "AetherUiTheme" }).Parent = replicated end
	if not replicated:FindFirstChild("AetherData") then new("ModuleScript", { Name = "AetherData" }).Parent = replicated end
	if options.mapArt ~= false and not replicated:FindFirstChild("AetherMapArt") then new("ModuleScript", { Name = "AetherMapArt" }).Parent = replicated end
	luau.load(fs.readFile("hud.client.lua"), { debugName = "hud.client.lua", environment = env, injectGlobals = true })()
	local api = player:FindFirstChild("IsleHudApi")
	return { gui = player:FindFirstChild("PlayerGui"):FindFirstChild("IsleHud"), state = api.OnInvoke("state"), api = api, theme = theme, input = services.UserInputService,
		coreGui = coreGui, prompts = services.ProximityPromptService, mapArt = mapArt }
end

-- Loads nav.client.lua (the Wayfinder minimap) with the world's island layout
-- (Theme.WorldMap), a few townsfolk and the player standing at `at` (studs),
-- then runs one minimap tick.
function H.runNav(size, player, shared, options)
	options = options or {}
	screen = size
	local replicated = shared or new("ReplicatedStorage")
	local function signal() return newSignal() end
	local islands = new("Folder", { Name = "Islands" })
	-- options.islands: a real Workspace.Islands (tools/world-harness.luau) for
	-- scans and the minimap plates; the mock folder still carries the signals.
	local realIslands = options.islands
	local env0 = { Instance = { new = function(class) return new(class) end }, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint }
	local theme = H.loadTheme(env0)
	for _, isle in ipairs(theme.WorldMap.islands) do
		local m = new("Model", { Name = isle.name })
		m:SetAttribute("IslandCenter", roblox.Vector3.new(isle.x, 0, isle.z))
		m:SetAttribute("IslandRadius", isle.r)
		m:SetAttribute("Region", isle.region)
		m.Parent = islands
	end
	local folk = new("Folder", { Name = "Townsfolk" })
	for i, role in ipairs({ "Guide", "Banker", "Smith" }) do
		local npc = new("Model", { Name = role })
		npc:SetAttribute("TownsfolkRole", role)
		local root = new("Part", { Name = "HumanoidRootPart", Position = roblox.Vector3.new(20 * i - 30, 0, 18 * (i % 2) - 6) })
		root.Parent = npc
		npc.Parent = folk
	end
	local at = options.at or roblox.Vector3.new(12, 4, 20)
	local character = new("Model", { Name = "Character" })
	local root = new("Part", { Name = "HumanoidRootPart", Position = at, CFrame = roblox.CFrame.new(at, at + roblox.Vector3.new(0.6, 0, -1)) })
	root.Parent = character
	player.Character = character
	local camera = new("Camera", { ViewportSize = size })
	local workspace = {
		CurrentCamera = camera, DescendantAdded = signal(), DescendantRemoving = signal(), ChildAdded = signal(), ChildRemoved = signal(),
		Islands = islands, GetDescendants = function() return {} end,
		FindFirstChild = function(_, name) if name == "Islands" then return realIslands or islands elseif name == "Townsfolk" then return folk end return nil end,
		GetAttribute = function() return nil end, GetAttributeChangedSignal = function() return signal() end,
		WaitForChild = function(_, name) if name == "Townsfolk" then return folk end return nil end,
	}
	islands.DescendantAdded, islands.DescendantRemoving = signal(), signal()
	local run = new("RunService")
	local services = {
		Players = new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated, RunService = run,
		UserInputService = new("UserInputService", { TouchEnabled = options.touch == true }), TweenService = new("TweenService"),
	}
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local env = {
		game = game, workspace = workspace, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		TweenInfo = { new = function() return {} end }, Instance = { new = function(class) return new(class) end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		task = baseTask(),
	}
	local navTheme = H.loadTheme(env)
	local navArt = H.loadMapArt(env)
	env.require = function(target)
		if target and target.Name == "AetherUiTheme" then return navTheme end
		if target and target.Name == "AetherMapArt" then return navArt end
		return Data
	end
	if options.mapArt ~= false and not replicated:FindFirstChild("AetherMapArt") then new("ModuleScript", { Name = "AetherMapArt" }).Parent = replicated end
	if not replicated:FindFirstChild("AetherUiTheme") then new("ModuleScript", { Name = "AetherUiTheme" }).Parent = replicated end
	if not replicated:FindFirstChild("AetherData") then new("ModuleScript", { Name = "AetherData" }).Parent = replicated end
	if not replicated:FindFirstChild("IsleAction") then
		local action = new("RemoteFunction", { Name = "IsleAction" })
		action.OnInvoke = function() return H.snapshot() end
		action.Parent = replicated
	end
	luau.load(fs.readFile("nav.client.lua"), { debugName = "nav.client.lua", environment = env, injectGlobals = true })()
	run.Heartbeat:Fire(1)
	return { gui = player:FindFirstChild("PlayerGui"):FindFirstChild("Wayfinder"), run = run, root = root, input = services.UserInputService }
end

-- Render-only stand-in for hotbar.client.lua (the Held Items team's 9-slot
-- bar): Theme slots where the real bar sits, filled from the snapshot.
function H.hotbarPreview(playerGui, size, theme, snap)
	local L = theme.hudLayout(size.X, size.Y, { touch = size.Y < 500 })
	local gui = new("ScreenGui", { Name = "HotbarPreview", DisplayOrder = 6 })
	gui.Parent = playerGui
	local equipment = (snap.depth or {}).equipment or {}
	local ids = { equipment.weapon, "BrassPickaxe", "CopperHatchet", "MeadowLongbow", "CookedFish", "Tonic", "BrassArrow", "HubwardTablet", "MightDraught" }
	for i = 1, 9 do
		local b = theme.slot(gui, { name = "Hotbar" .. i, size = L.hotbar.slot, key = i })
		b.Position = roblox.UDim2.fromOffset(L.hotbar.x + (i - 1) * (L.hotbar.slot + 4), L.hotbar.y)
		local id = ids[i]
		theme.setSlot(b, { id = id, def = id and Data.Items[id], count = id and (snap.items or {})[id] or 0, selected = i == 1 })
		if i == 1 then
			b:FindFirstChild("Rarity").Thickness = 3
			b:FindFirstChild("Rarity").Color = theme.color.gold
		end
	end
	return gui
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

-- Loads overlay.client.lua (§34: action label, world menu, status orbs, chat
-- tabs and router, pickup feed) into an existing player's PlayerGui; pass the
-- atlas handle's `replicated` to share its local channels. options: touch,
-- raycast(origin, direction) -> {Instance, Position} | nil (the world under the
-- cursor), tagged (CollectionService "IsleMonster" list), players (other Player
-- mocks), delays (records task.delay calls), clock (os.clock stand-in).
function H.runOverlay(size, player, shared, options)
	options = options or {}
	screen = size
	local replicated = shared or new("ReplicatedStorage")
	local tagged = options.tagged or {}
	local others = options.players or {}
	local chat = {}
	options.ground = options.ground or function() return true end
	local channels = new("Folder", { Name = "TextChannels" })
	local general = new("TextChannel", { Name = "RBXGeneral" })
	general.Parent = channels
	general.DisplaySystemMessage = function(_, text, metadata) table.insert(chat, { text = text, metadata = metadata }) end
	local textChat = new("TextChatService")
	channels.Parent = textChat
	local camera = new("Camera", { ViewportSize = size })
	camera.ScreenPointToRay = function(_, x, y) return { Origin = roblox.Vector3.new(x, 100, y), Direction = roblox.Vector3.new(0, -1, 0) } end
	local space = {
		CurrentCamera = camera,
		-- Short downward rays are the overlay's ground checks: ground(origin) decides
		-- (default: ground everywhere, 3 studs below the origin).
		Raycast = function(_, origin, direction)
			if direction.Magnitude < 50 and direction.Y < 0 then
				return if options.ground(origin) then { Instance = camera, Position = origin - roblox.Vector3.new(0, 3, 0) } else nil
			end
			return if options.raycast then options.raycast(origin, direction) else nil
		end,
		FindFirstChild = function() return nil end,
	}
	local playersService = new("Players", { LocalPlayer = player })
	function playersService.GetPlayers() local out = { player }; for _, o in ipairs(others) do table.insert(out, o) end; return out end
	function playersService.GetPlayerFromCharacter(_, model)
		for _, o in ipairs(others) do if o.Character == model then return o end end
		return if player.Character == model then player else nil
	end
	function playersService.GetPlayerByUserId(_, id)
		for _, o in ipairs(others) do if o.UserId == id then return o end end
		return nil
	end
	local run = new("RunService")
	-- PathfindingService: options.path(from, to) returns waypoint positions (nil:
	-- no path); the default is the straight line. Each route is recorded.
	local routes = {}
	local pathfinding = {
		CreatePath = function()
			local path = { Status = roblox.Enum.PathStatus.NoPath, points = {} }
			function path.ComputeAsync(_, from, to)
				table.insert(routes, { from = from, to = to })
				local points = if options.path then options.path(from, to) else { from, to }
				path.points = points or {}
				path.Status = if points then roblox.Enum.PathStatus.Success else roblox.Enum.PathStatus.NoPath
			end
			function path.GetWaypoints()
				local out = {}
				for _, position in ipairs(path.points) do table.insert(out, { Position = position, Action = roblox.Enum.PathWaypointAction.Walk }) end
				return out
			end
			return path
		end,
	}
	local services = {
		Players = playersService, ReplicatedStorage = replicated, RunService = run, TextChatService = textChat, PathfindingService = pathfinding,
		UserInputService = new("UserInputService", { TouchEnabled = options.touch == true }), TweenService = new("TweenService"),
		CollectionService = { GetTagged = function() return tagged end, HasTag = function(_, object, tag) return tag == "IsleMonster" and table.find(tagged, object) ~= nil end },
	}
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local base = baseTask(options.delays)
	local env = {
		game = game, workspace = space, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2, Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, TweenInfo = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end }, RaycastParams = { new = function() return {} end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		-- The 1 Hz orb tick and walk loops yield forever here (task.wait never resumes).
		task = { spawn = base.spawn, delay = base.delay, defer = base.defer, wait = function() return coroutine.yield() end },
		os = { clock = options.clock or os.clock, time = os.time },
	}
	local theme = H.loadTheme(env)
	env.require = function(target)
		if target.Name == "AetherUiTheme" then return theme end
		if target.Name == "AetherHudDepth" then return H.HudDepth end
		return Data
	end
	for _, name in ipairs({ "AetherUiTheme", "AetherHudDepth", "AetherData" }) do
		if not replicated:FindFirstChild(name) then new("ModuleScript", { Name = name }).Parent = replicated end
	end
	luau.load(fs.readFile("overlay.client.lua"), { debugName = "overlay.client.lua", environment = env, injectGlobals = true })()
	local api = player:FindFirstChild("IsleOverlayApi")
	return { gui = player:FindFirstChild("PlayerGui"):FindFirstChild("IsleOverlay"), state = api.OnInvoke("state"), api = api, input = services.UserInputService,
		run = run, chat = chat, textChat = textChat, theme = theme, camera = camera, routes = routes,
		setPath = function(fn) options.path = fn end,
		setGround = function(fn) local old = options.ground; options.ground = fn or function() return true end; return old end }
end

-- Loads tutorial.client.lua (§43 coach cards, pointer ring, tips) into an
-- existing player's PlayerGui; pass the atlas handle's `replicated` so the local
-- channels (snapshots in, verbs out through IsleActionLocal) are shared.
-- options: touch, delays (records task.delay), clock (os.clock stand-in).
function H.runTutorial(size, player, shared, options)
	options = options or {}
	screen = size
	local replicated = shared or new("ReplicatedStorage")
	local run = new("RunService")
	local services = {
		Players = new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated, RunService = run,
		UserInputService = new("UserInputService", { TouchEnabled = options.touch == true }), TweenService = new("TweenService"),
	}
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local camera = new("Camera", { ViewportSize = size })
	local base = baseTask(options.delays)
	local env = {
		game = game, workspace = { CurrentCamera = camera }, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		TweenInfo = { new = function() return {} end }, Instance = { new = function(class) return new(class) end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		task = { spawn = base.spawn, delay = base.delay, defer = base.defer, wait = function() return coroutine.yield() end },
		os = { clock = options.clock or os.clock, time = os.time },
	}
	local theme = H.loadTheme(env)
	env.require = function(target)
		if target.Name == "AetherUiTheme" then return theme end
		return Data
	end
	for _, name in ipairs({ "AetherUiTheme", "AetherData" }) do
		if not replicated:FindFirstChild(name) then new("ModuleScript", { Name = name }).Parent = replicated end
	end
	luau.load(fs.readFile("tutorial.client.lua"), { debugName = "tutorial.client.lua", environment = env, injectGlobals = true })()
	local api = player:FindFirstChild("IsleTutorialApi")
	local playerGui = player:FindFirstChild("PlayerGui")
	return { gui = playerGui:FindFirstChild("IsleTutorial"), pointer = playerGui:FindFirstChild("IsleTutorialPointer"), state = api.OnInvoke("state"),
		api = api, run = run, input = services.UserInputService, theme = theme }
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
-- Changes the emulated screen size (a resized window / rotated device); GUI
-- AbsoluteSize reads follow it. Fire the size signals yourself.
function H.setScreen(size)
	screen = size
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
	if d.props.ClassName == "ViewportFrame" and d.attrs.MapArtScene and d.props.CurrentCamera and d.props.CurrentCamera.CFrame then
		-- A 3D scene (the Sky Chart miniature, §32): camera, light and every part,
		-- for the rasterizer's z-buffered approximation.
		local camera = d.props.CurrentCamera
		local scene = { camera = { camera.CFrame:GetComponents() }, fov = camera.FieldOfView or 70, parts = {},
			ambient = encode(d.props.Ambient), light = encode(d.props.LightColor),
			lightDirection = d.props.LightDirection and { d.props.LightDirection.X, d.props.LightDirection.Y, d.props.LightDirection.Z } or nil }
		for _, child in ipairs(d.children) do
			if child.ClassName == "Model" then
				for _, part in ipairs(child:GetDescendants()) do
					local props = data[part].props
					if props.Size and props.CFrame and (props.Transparency or 0) < 0.95 then
						table.insert(scene.parts, { class = props.ClassName, shape = props.Shape and props.Shape.Name or nil,
							size = { props.Size.X, props.Size.Y, props.Size.Z }, cf = { props.CFrame:GetComponents() },
							color = encode(props.Color or roblox.Color3.new(0.6, 0.6, 0.6)), alpha = props.Transparency or 0,
							material = props.Material and props.Material.Name or nil })
					end
				end
			end
		end
		node.scene = scene
	elseif d.props.ClassName == "ViewportFrame" then
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
