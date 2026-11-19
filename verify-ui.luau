-- Headless smoke test for ui.client.lua (the atlas). Loads the LocalScript in a
-- small mock of the Roblox instance tree, feeds it snapshots (full Depth record,
-- none, malformed, missing shared data), renders every tab/section at three
-- atlas sizes, presses every button and checks the verbs it sends.
-- Run from the project directory: lune run verify-ui.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local source = fs.readFile("ui.client.lua")
local function loadModule(path, env)
	return luau.load(fs.readFile(path), { debugName = path, environment = env or {}, injectGlobals = true })()
end
local Data = loadModule("shared/GameData.lua")
local Progression = loadModule("shared/Progression.lua", { script = nil })
Progression.useData(Data)
local Catalog = loadModule("art/PropCatalog.lua")

------------------------------------------------------------------------------
-- Mock instances
------------------------------------------------------------------------------
local function newSignal()
	local signal = { handlers = {} }
	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
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
}
local guiClasses = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ScrollingFrame = true, ViewportFrame = true, TextBox = true }
local absoluteSize = roblox.Vector2.new(730, 303)
local data = setmetatable({}, { __mode = "k" })
local methods = {}
local meta = {}
local created = 0
local function new(class, props)
	local object = setmetatable({}, meta)
	data[object] = { props = { ClassName = class, Name = class }, children = {}, propSignals = {}, attrs = {}, attrSignals = {} }
	created += 1
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	return object
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
	if key == "AbsoluteSize" or key == "AbsoluteCanvasSize" then
		return absoluteSize
	elseif key == "AbsolutePosition" or key == "CanvasPosition" then
		return roblox.Vector2.zero
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
	if key == "ClassName" then
		error("ClassName is read-only")
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
function methods:InvokeServer(...)
	return data[self].props.OnInvoke(...)
end
function methods:GetPlayers()
	return { self.LocalPlayer }
end
function methods:Create()
	return { Play = function() end }
end
function methods:GetServerTimeNow()
	return os.clock()
end
local focusedTextBox = nil -- tests set this to simulate typing
function methods:GetFocusedTextBox()
	return focusedTextBox
end

------------------------------------------------------------------------------
-- Snapshots
------------------------------------------------------------------------------
local function profile()
	return {
		xp = { Combat = 9000, Mining = 22000, Woodcutting = 400, Fishing = 0, Farming = 60, Smithing = 4500, Cooking = 100, Alchemy = 0, Enchanting = 1200, Taming = 0, Dungeoneering = 0, Carpentry = 50 },
		items = {
			Ore = 140, Timber = 40, Herb = 70, Fish = 30, Brassite = 12, Pickaxe = 1, Blade = 1, Tonic = 2, ExpeditionRation = 1,
			BrassSword = 1, BrassHelm = 1, BrassChestplate = 1, BrassGreaves = 1, BrassBoots = 1, SunsteelSword = 1, BrassPickaxe = 1,
			CopperHatchet = 1, ArcaneDust = 60, MeadowCharm = 1, QuarryTalisman = 1, EmberfoxPet = 1, CookedFish = 3, MightDraught = 2,
			StormFeather = 3, BrassIngot = 9, LegacyMystery = 2,
		},
		collection = { Ore = 320, Timber = 60, Herb = 70, Fish = 30, Brassite = 40, Shard = 2, StormFeather = 3, BeastHide = 0 },
		equipment = { weapon = "BrassSword", helmet = "BrassHelm", chest = "BrassChestplate", legs = "BrassGreaves", boots = "BrassBoots" },
		enchants = { BrassSword = { Sharpness = 2, Critical = 5 } },
		accessoryBag = { "MeadowCharm", "QuarryTalisman" },
		pets = { { id = "Tidewing", level = 5, xp = 100 }, { id = "Emberfox", level = 1, xp = 0 } },
		activePet = 1,
		buffs = { MightDraught = { expires = 120, stats = { strength = 15 } } },
		bestiary = { BramblebackBoar = 30, Thornling = 1, ShaleCrawler = 1000 },
		slayerXp = { Bramble = 20, Gloom = 0, Tempest = 0 },
	}
end
local function snapshot(options)
	options = options or {}
	local p = profile()
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
		xp = p.xp, items = p.items, collection = p.collection, coins = 52000, bank = 10, bankRevision = 3, levels = levels, message = options.message or "",
		consumables = { Tonic = { healing = 40, recovery = 0, action = "Drink", readyIn = 0 }, ExpeditionRation = { healing = 65, recovery = 12, action = "Eat", readyIn = 5 } },
		recipes = { { id = "Pickaxe", costs = { Ore = 3, Timber = 2 }, skill = "Smithing", level = 1, collection = { Ore = 3 }, description = "A pick", repeatable = false, unlocked = true, xp = 24 } },
		regions = { { name = "Skyreach", unlocked = false, requirement = "Complete 6 contracts" } },
		stats = { maxHealth = 120, defense = 5 }, quest = { title = "Contract", detail = "Do it", ready = true },
		slayer = { tier = 1, active = true, progress = 1, target = 2, ready = false, completed = 0, coins = 20, xp = 30 },
		workers = { { resource = "Ore", tier = 1, ready = 3, interval = 120, capacity = 60 } }, decorations = { Garden = true },
		started = true, companionBond = 2, enchantRank = 1,
		economy = {
			bazaar = { item = "Ore", bids = { { price = 20, qty = 30, orders = 2 }, { price = 18, qty = 5, orders = 1 } }, asks = { { price = 25, qty = 10, orders = 1 } },
				bestBid = 20, bestAsk = 25, spread = 5, openOrders = 4, mine = {}, claimUnits = 3, claimCoins = 40, fetchedAt = 0, revision = 3, matchingPolicy = "Highest bid first." },
			auction = { category = "weapon", page = 1, pages = 2, total = 9, proceeds = 50, returns = 1, fetchedAt = 0, revision = 2,
				listings = { { id = 4, item = "SunsteelSword", price = 900, remaining = 3600, own = false }, { id = 5, item = "BrassSword", price = 1000, remaining = 60, own = true } } },
			orders = { { item = "Ore", id = 7, side = "bid", price = 20, qty = 10 }, { item = "Herb", id = 2, side = "ask", price = 4, qty = 5 } },
			listings = { { cat = "weapon", id = 5, item = "BrassSword", price = 1000, expires = 500 }, { cat = "pet", id = 9, item = "EmberfoxPet", price = 150, expires = 50 } },
			pending = options.econPending == true, readyIn = 0, serverTime = 100,
		},
	}
	if options.ironman then
		result.ironman = true
	end
	if options.depth == false then
		return result
	end
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
		slayer = { lines = lines, quest = if options.noQuest then nil else { line = "Bramble", tier = 1, progress = 40, needed = 150, bossReady = options.bossReady == true } },
		enchants = p.enchants,
		regions = { { id = "Hub", name = "Aether Hub", unlocked = true, requirement = "" }, { id = "Gloomhollow", name = "Gloomhollow Caverns", unlocked = false, requirement = "Mining 30, Combat 15" } },
	}
	-- Quest journal: every status (done, ready with and without a lamp, active, locked).
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
	result.journal = options.noJournal and nil or {
		questPoints = 12, contracts = 8, quests = quests, diaries = diaries,
		construction = { furniture = { Bench = "SturdyWorkbench", Portal = "PortalFrame" }, portal = "Skyreach", portalRegions = { "Skyreach", "Windpine" },
			carpentry = 32, accessorySlots = 1, workerHaste = 0.05 },
	}
	if options.malformed then
		result.journal = { questPoints = "many", quests = { 3, { id = 7 }, { id = "SurveyorsOath", requires = "x", objectives = { 5 } } },
			diaries = { "Meadow", { region = "Meadow", claimed = "two", tiers = { 4, { tier = 9 } } } }, construction = { furniture = { Bench = 3, Portal = "Ghost" }, portalRegions = { 5, "Atlantis" }, carpentry = "x" } }
		result.depth = {
			skills = "oops", totalLevel = "x", stats = 5, equipment = { weapon = 5, helmet = "NotAnItem" }, tools = { Mining = {} },
			accessoryBag = { 1, "MeadowCharm" }, activeAccessories = 7, accessorySlots = "four", pets = { 1, { id = "Nope" }, { id = "Tidewing", level = "x" } },
			buffs = { MightDraught = { remaining = "soon" }, Broken = 3 }, collections = { Ore = 5, Timber = { count = "many" } }, bestiary = { BramblebackBoar = "lots", Ghost = 3 },
			slayer = { lines = { Bramble = 3 }, quest = { line = "Unknown", tier = "II" } }, enchants = { BrassSword = { Mystery = 2 }, Blade = 4 }, regions = { 3, { id = 7 } },
		}
		result.economy = { bazaar = 5, auction = { category = "weapon", listings = { 7, { id = "x" }, { id = 3, item = 4 } }, pages = "two" },
			orders = { 1, "x", { id = "no" }, { id = 3, item = "Nope", side = "bid" } }, listings = { { cat = 3 }, { id = 2, item = "BrassSword", cat = "weapon", expires = "soon" } }, serverTime = "now" }
	end
	return result
end

------------------------------------------------------------------------------
-- Environment
------------------------------------------------------------------------------
local function run(options)
	options = options or {}
	absoluteSize = options.size or roblox.Vector2.new(730, 303)
	local warnings, sent = {}, {}
	local current = options.snapshot or snapshot()
	local playerGui = new("PlayerGui")
	local player = new("Player", { Name = "Tester", DisplayName = "Tester", UserId = 1 })
	playerGui.Parent = player
	local players = new("Players", { LocalPlayer = player })
	local replicated = new("ReplicatedStorage")
	local modules = {}
	local function module(name, value)
		local object = new("ModuleScript", { Name = name })
		object.Parent = replicated
		modules[object] = value
	end
	if options.art ~= false then
		local art = Catalog
		if options.artExports then
			art = table.clone(Catalog)
			art.tintIndex = 5
			art.iconShape = function(def)
				return def.kind == "weapon" and "Blade" or nil
			end
		end
		module("AetherArt", art)
	end
	if options.data ~= false then
		module("AetherData", Data)
	end
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
		return { members = {}, invites = {}, message = "" }
	end
	coop.Parent = replicated
	local services = {
		Players = players, ReplicatedStorage = replicated, UserInputService = new("UserInputService", { GamepadEnabled = false }),
		GuiService = new("GuiService"), TweenService = new("TweenService"),
	}
	local game = new("DataModel")
	function game.GetService(_, name)
		return assert(services[name], name)
	end
	local env = {
		game = game, workspace = new("Workspace"), Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence,
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
		task = {
			spawn = function(fn, ...)
				local co = coroutine.create(fn)
				local ok, problem = coroutine.resume(co, ...)
				assert(ok, problem)
				return co
			end,
			delay = function() end,
			defer = function(fn, ...) fn(...) end,
			wait = function() return coroutine.yield() end,
		},
	}
	local chunk = luau.load(source, { debugName = "ui.client.lua", environment = env, injectGlobals = true })
	local main = coroutine.create(chunk)
	local ok, problem = coroutine.resume(main)
	assert(ok, problem)
	assert(coroutine.status(main) == "dead", "ui.client.lua should finish its sync loop")
	local gui = playerGui:FindFirstChild("AetherAtlas")
	assert(gui, "ScreenGui")
	local atlas = gui:FindFirstChild("Atlas")
	local scroll = atlas:FindFirstChildOfClass("ScrollingFrame")
	local tabs = atlas:FindFirstChild("Tabs")
	return {
		gui = gui, atlas = atlas, scroll = scroll, tabs = tabs, sent = sent, warnings = warnings, player = player, update = update,
		setSnapshot = function(value) current = value end, input = services.UserInputService, guiService = services.GuiService,
	}
end
local function find(root, name)
	for _, object in ipairs(root:GetDescendants()) do
		if object.Name == name then
			return object
		end
	end
	return nil
end
local function press(object)
	assert(object, "missing button")
	object.Activated:Fire()
end
local function noFailures(ui, context)
	for _, message in ipairs(ui.warnings) do
		error(context .. ": " .. message)
	end
end

------------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------------
local checks = 0
local pages = {
	Journal = { "Bearing", "Quests", "Diaries", "Construction", "Regions", "Crew" }, Hero = { "Skills", "Gear", "Enchant", "Accessories", "Pets" }, Satchel = { "Items", "Collections" },
	Workshop = { "Forge", "Hearth", "Cauldron", "Workbench", "Workers", "Home" }, Hunt = { "Slayer", "Bestiary" }, Ledger = { "Bank", "Market", "Orders", "Auctions", "Merchant" },
}
local tabOrder = { "Journal", "Hero", "Satchel", "Workshop", "Hunt", "Ledger" }
local verbs = {
	equip = function(item) return Data.Items[item] ~= nil and Data.Items[item].slot ~= nil end,
	unequip = function(item) return item == "weapon" or item == "helmet" or item == "chest" or item == "legs" or item == "boots" end,
	consume = function(item) return Data.Items[item] ~= nil and Data.Items[item].kind == "consumable" end,
	accessory = function(item) return Data.Items[item] ~= nil and Data.Items[item].kind == "accessory" end,
	petSummon = function(item) return type(item) == "string" and item:match("^%d+$") ~= nil end,
	petAdopt = function(item) return Data.Items[item] ~= nil and Data.Items[item].kind == "pet" end,
	enchantItem = function(item)
		local id, enchant = tostring(item):match("^(%w+):(%w+)$")
		return id ~= nil and Data.Items[id] ~= nil and Data.Enchants[enchant] ~= nil
	end,
	sell = function(item) return item == nil or type(item) == "string" end,
	slayerBegin = function(item)
		local line, tier = tostring(item):match("^(%a+):(%d)$")
		return line ~= nil and Data.Slayers[line] ~= nil and Data.Slayers[line].tiers[tonumber(tier)] ~= nil
	end,
	slayerAbandon = function(item) return item == nil end,
	craft = function(item) return type(item) == "string" and #item <= 64 end,
	bazaar = function(item) return Data.Economy.isCommodity(item) end,
	bid = function(item) local id, q, pr = tostring(item):match("^(%w+):(%d+):(%d+)$") return id ~= nil and Data.Economy.isCommodity(id) and tonumber(q) >= 1 and tonumber(pr) >= 1 end,
	offer = function(item) local id = tostring(item):match("^(%w+):%d+:%d+$") return id ~= nil and Data.Economy.isCommodity(id) end,
	buyNow = function(item) local id = tostring(item):match("^(%w+):%d+:%d+$") return id ~= nil and Data.Economy.isCommodity(id) end,
	sellToBid = function(item) local id = tostring(item):match("^(%w+):%d+$") or tostring(item):match("^(%w+):%d+:%d+$") return id ~= nil and Data.Economy.isCommodity(id) end,
	bidCancel = function(item) local id = tostring(item):match("^(%w+):%d+$") return id ~= nil and Data.Economy.isCommodity(id) end,
	bidClaim = function(item) return Data.Economy.isCommodity(item) end,
	ahBrowse = function(item) local cat = tostring(item):match("^(%a+):%d+$") return cat ~= nil and Data.Economy.categoryNames[cat] ~= nil end,
	ahList = function(item) local id, pr = tostring(item):match("^(%w+):(%d+)$") return id ~= nil and Data.Economy.auctionCategory(id) ~= nil and tonumber(pr) >= 1 end,
	ahBuy = function(item) local cat = tostring(item):match("^(%a+):%d+:%d+$") return cat ~= nil and Data.Economy.categoryNames[cat] ~= nil end,
	ahCancel = function(item) local cat = tostring(item):match("^(%a+):%d+$") return cat ~= nil and Data.Economy.categoryNames[cat] ~= nil end,
	ahClaim = function(item) return Data.Economy.categoryNames[item] ~= nil end,
	quest = function(item)
		if item == nil then return true end
		local id, skill = tostring(item):match("^(%w+):(%w+)$")
		if id then return Data.QuestById[id] ~= nil and Data.QuestById[id].rewards.lamp ~= nil and Data.Skills[skill] ~= nil end
		return Data.QuestById[item] ~= nil and Data.QuestById[item].rewards.lamp == nil
	end,
	diary = function(item)
		local region, tier = tostring(item):match("^(%a+):(%a+)$")
		return region ~= nil and Data.DiaryByRegion[region] ~= nil and Data.DiaryByRegion[region].tiers[tier] ~= nil
	end,
	build = function(item)
		local hotspot, id = tostring(item):match("^(%a+):(%w+)$")
		return hotspot ~= nil and Data.Furniture[id] ~= nil and Data.Furniture[id].hotspot == hotspot
	end,
	remove = function(item) return Data.HotspotById[item] ~= nil end,
	portal = function(item) return table.find(Data.PortalRegions, item) ~= nil end,
}
local function checkSent(ui)
	for _, entry in ipairs(ui.sent) do
		local verb, item = entry[1], entry[2]
		if item ~= nil then
			assert(type(item) == "string" and #item <= 64, verb .. " item must be a short string")
		end
		local rule = verbs[verb]
		if rule then
			assert(rule(item), "bad payload for " .. verb .. ": " .. tostring(item))
			checks += 1
		end
	end
end
local function visit(ui, tab, section)
	press(ui.tabs:FindFirstChild(tab .. "Button"))
	if section then
		press(find(ui.scroll, "Section" .. section))
	end
end
local function sweep(ui, label, clickEverything)
	if not ui.atlas.Visible then
		press(find(ui.gui, "AtlasButton"))
	end
	for _, tab in ipairs(tabOrder) do
		for _, section in ipairs(pages[tab]) do
			visit(ui, tab, section)
			noFailures(ui, label .. " " .. tab .. "/" .. section)
			assert(#ui.scroll:GetChildren() > 2, label .. " " .. tab .. "/" .. section .. " drew nothing")
			checks += 1
			if clickEverything then
				local count = 0
				for _, object in ipairs(ui.scroll:GetDescendants()) do
					if object.ClassName == "TextButton" then
						count += 1
					end
				end
				for index = 1, math.min(count, 45) do
					visit(ui, tab, section)
					local seen = 0
					for _, object in ipairs(ui.scroll:GetDescendants()) do
						if object.ClassName == "TextButton" then
							seen += 1
							if seen == index then
								press(object)
								break
							end
						end
					end
					noFailures(ui, label .. " " .. tab .. "/" .. section .. " button " .. index)
					checks += 1
				end
			end
		end
	end
	checkSent(ui)
end

-- 1. Full Depth record across the three atlas layouts; press every button.
for _, size in ipairs({ roblox.Vector2.new(730, 303), roblox.Vector2.new(420, 600), roblox.Vector2.new(760, 690) }) do
	local ui = run({ size = size })
	sweep(ui, "full@" .. size.X .. "x" .. size.Y, size.X == 730)
end
-- 2. Older server (no depth), malformed depth, boss-ready contract, no quest.
sweep(run({ snapshot = snapshot({ depth = false }) }), "no-depth", true)
sweep(run({ snapshot = snapshot({ malformed = true }) }), "malformed", true)
sweep(run({ snapshot = snapshot({ bossReady = true }) }), "boss-ready", false)
sweep(run({ snapshot = snapshot({ noQuest = true }) }), "no-quest", true)
-- 3. Shared data or art unavailable; art team exports present.
sweep(run({ data = false }), "no-data", false)
sweep(run({ art = false }), "no-art", false)
sweep(run({ artExports = true }), "art-exports", false)

-- 4. Station visits open the matching page exactly once per visit (World sets
-- IsleStation and then bumps IsleStationVisit).
do
	local ui = run()
	local visits = 0
	local function stationVisit(value)
		visits += 1
		ui.player:SetAttribute("IsleStation", value)
		ui.player:SetAttribute("IsleStationVisit", visits)
	end
	local function stateRequests()
		local n = 0
		for _, entry in ipairs(ui.sent) do
			if entry[1] == "state" then n += 1 end
		end
		return n
	end
	local beforeOpen = stateRequests()
	stationVisit("Hearth")
	assert(ui.atlas.Visible and find(ui.scroll, "StationHearth"), "Hearth station opens the Workshop")
	assert(stateRequests() == beforeOpen + 1, "one station visit opens the atlas once")
	stationVisit("Slayer")
	assert(find(ui.scroll, "SlayerBramble"), "Slayer board opens the slayer page")
	stationVisit("Forge:2")
	assert(find(ui.scroll, "StationForge"), "suffixed station value")
	-- Revisit: same IsleStation value, only the visit counter changes.
	press(ui.tabs:FindFirstChild("LedgerButton"))
	assert(not find(ui.scroll, "StationForge"), "left the Workshop")
	local beforeRevisit = stateRequests()
	stationVisit("Forge:2")
	assert(find(ui.scroll, "StationForge"), "revisiting the same station reopens its tab")
	assert(stateRequests() == beforeRevisit + 1, "a revisit opens the atlas once")
	-- Region notices: the counter re-shows an identical repeated message.
	local function toast()
		for _, object in ipairs(ui.gui:GetChildren()) do
			if object.ClassName == "TextLabel" and object.Text == "Gloomhollow Caverns requires Mining 30." then
				return object
			end
		end
		return nil
	end
	ui.player:SetAttribute("IsleRegionNotice", "Gloomhollow Caverns requires Mining 30.")
	ui.player:SetAttribute("IsleRegionNoticeCount", 1)
	local shown = toast()
	assert(shown and shown.Visible, "region notice toast")
	shown.Visible = false
	ui.player:SetAttribute("IsleRegionNotice", "Gloomhollow Caverns requires Mining 30.")
	ui.player:SetAttribute("IsleRegionNoticeCount", 2)
	assert(shown.Visible, "repeated identical region notice shows again")
	-- Compact (730x303) toasts are capped well below the touch controls.
	local limit = shown:FindFirstChild("NoticeLimit")
	assert(limit and limit.MaxSize.Y <= 60, "compact toast height is capped")
	assert(shown.TextTruncate == roblox.Enum.TextTruncate.AtEnd, "compact toast truncates instead of growing")
	noFailures(ui, "stations")
	checks += 10
end
-- 4b. Closing the atlas clears gamepad UI selection.
do
	local ui = run()
	ui.input.GamepadEnabled = true
	press(find(ui.gui, "AtlasButton"))
	assert(ui.guiService.SelectedObject ~= nil, "opening with a gamepad selects a tab")
	press(find(ui.atlas, "CloseButton"))
	assert(not ui.atlas.Visible and ui.guiService.SelectedObject == nil, "closing the atlas clears SelectedObject")
	noFailures(ui, "gamepad close")
	checks += 2
end
-- 4c. A pushed snapshot while typing in the Bank keeps the TextBox; redraws on release.
do
	local ui = run()
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Ledger", "Bank")
	local box = find(ui.scroll, "BankAmount")
	assert(box, "bank amount TextBox")
	focusedTextBox = box
	ui.update.OnClientEvent:Fire(snapshot({ message = "Market moved" }))
	assert(box.Parent ~= nil and find(ui.scroll, "BankAmount") == box, "typing TextBox survives a pushed snapshot")
	focusedTextBox = nil
	ui.input.TextBoxFocusReleased:Fire(box)
	local redrawn = find(ui.scroll, "BankAmount")
	assert(redrawn and redrawn ~= box, "deferred snapshot redraws once focus is released")
	noFailures(ui, "typing")
	checks += 3
end
-- 4d. Phone layout keeps the thumbnail budget small.
do
	local ui = run()
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Satchel", "Items")
	local views = 0
	for _, object in ipairs(ui.scroll:GetDescendants()) do
		if object.ClassName == "ViewportFrame" then views += 1 end
	end
	assert(views > 0 and views <= 10, "compact layout draws at most 10 live thumbnails, drew " .. views)
	local wide = run({ size = roblox.Vector2.new(760, 690) })
	press(find(wide.gui, "AtlasButton"))
	visit(wide, "Satchel", "Items")
	local wideViews = 0
	for _, object in ipairs(wide.scroll:GetDescendants()) do
		if object.ClassName == "ViewportFrame" then wideViews += 1 end
	end
	assert(wideViews > views and wideViews <= 24, "desktop keeps the larger budget, drew " .. wideViews)
	checks += 2
end
-- 5. Targeted flows: equip, enchant, sell confirmation, slayer begin/abandon.
do
	local ui = run({ snapshot = snapshot({ noQuest = true }) })
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Hero", "Gear")
	press(find(ui.scroll, "Slotweapon"))
	press(find(ui.scroll, "EquipSunsteelSwordEquip"))
	press(find(ui.scroll, "EquippedweaponUnequip"))
	visit(ui, "Hero", "Enchant")
	press(find(ui.scroll, "EnchantBrassHelm"))
	press(find(ui.scroll, "EnchProtectionEnchant"))
	visit(ui, "Satchel", "Items")
	press(find(ui.scroll, "ItemBrassBoots"))
	assert(find(ui.scroll, "ItemDetail"), "item detail opens")
	press(find(ui.scroll, "ItemDetailSell"))
	press(find(ui.scroll, "ItemDetailConfirm"))
	visit(ui, "Hunt", "Slayer")
	press(find(ui.scroll, "SlayerTierBrambleBegin"))
	noFailures(ui, "flows")
	local log = {}
	for _, entry in ipairs(ui.sent) do
		table.insert(log, entry[1] .. "=" .. tostring(entry[2]))
	end
	local joined = table.concat(log, " ")
	for _, expected in ipairs({ "equip=SunsteelSword", "unequip=weapon", "enchantItem=BrassHelm:Protection", "sell=BrassBoots", "slayerBegin=Bramble:1" }) do
		assert(joined:find(expected, 1, true), "expected " .. expected .. " in " .. joined)
		checks += 1
	end
	checkSent(ui)
end
-- 5b. Ledger → Orders and Auctions: review/confirm flows send validated verbs.
do
	local ui = run()
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Ledger", "Orders")
	assert(find(ui.scroll, "CommodityOre") and find(ui.scroll, "Book"), "Orders draws the commodity grid and order book")
	local bookText = {}
	for _, object in ipairs(find(ui.scroll, "Book"):GetDescendants()) do
		if object.ClassName == "TextLabel" then table.insert(bookText, object.Text) end
	end
	local joinedBook = table.concat(bookText, " | ")
	assert(joinedBook:find("spread 5", 1, true) and joinedBook:find("ASK  25", 1, true) and joinedBook:find("BID  20", 1, true), "depth and spread shown: " .. joinedBook)
	press(find(ui.scroll, "SectionOrders"))
	press(find(ui.scroll, "GroupMaterials"))
	press(find(ui.scroll, "CommodityBeastHide"))
	press(find(ui.scroll, "GroupMining"))
	press(find(ui.scroll, "CommodityOre"))
	find(ui.scroll, "BazaarQuantity").Text = "12"
	find(ui.scroll, "BazaarPrice").Text = "21"
	press(find(ui.scroll, "PlaceBuyorder"))
	assert(find(ui.scroll, "ConfirmButton"), "buy order asks for review")
	press(find(ui.scroll, "CancelButton"))
	assert(not find(ui.scroll, "ConfirmButton"), "review can be cancelled")
	press(find(ui.scroll, "PlaceBuyorder"))
	press(find(ui.scroll, "ConfirmButton"))
	press(find(ui.scroll, "PlaceSelloffer"))
	press(find(ui.scroll, "ConfirmButton"))
	press(find(ui.scroll, "InstantBuynow"))
	press(find(ui.scroll, "ConfirmButton"))
	find(ui.scroll, "BazaarPrice").Text = ""
	press(find(ui.scroll, "InstantInstantsell"))
	press(find(ui.scroll, "ConfirmButton"))
	find(ui.scroll, "BazaarQuantity").Text = "641"
	local before = #ui.sent
	press(find(ui.scroll, "PlaceBuyorder"))
	assert(#ui.sent == before and not find(ui.scroll, "ConfirmButton"), "out-of-range quantity is refused locally")
	press(find(ui.scroll, "Order7Cancel"))
	press(find(ui.scroll, "Order2Claim"))
	press(find(ui.scroll, "ClaimButton"))
	visit(ui, "Ledger", "Auctions")
	assert(find(ui.scroll, "Listing4") and find(ui.scroll, "Mine5"), "Auctions draws listings and your listings")
	assert(find(ui.scroll, "Listing5Yours"), "own listing cannot be bought")
	press(find(ui.scroll, "Listing4Buy"))
	press(find(ui.scroll, "ConfirmButton"))
	press(find(ui.scroll, "PagerNext"))
	press(find(ui.scroll, "AuctionPets"))
	press(find(ui.scroll, "AuctionWeapons"))
	assert(not find(ui.scroll, "ListableBrassSword"), "equipped gear is not offered for listing")
	assert(not find(ui.scroll, "ListableMeadowCharm"), "bagged accessories are not offered for listing")
	press(find(ui.scroll, "ListableSunsteelSword"))
	find(ui.scroll, "AuctionPrice").Text = "1250"
	visit(ui, "Ledger", "Auctions")
	local fee = {}
	for _, object in ipairs(find(ui.scroll, "ListPreview"):GetDescendants()) do
		if object.ClassName == "TextLabel" then table.insert(fee, object.Text) end
	end
	assert(table.concat(fee, " "):find("Fee 13 coins", 1, true), "fee preview shows 1% rounded up: " .. table.concat(fee, " | "))
	press(find(ui.scroll, "ListPreviewReviewlisting"))
	press(find(ui.scroll, "ConfirmButton"))
	press(find(ui.scroll, "Mine5Cancel"))
	press(find(ui.scroll, "Mine9Claim"))
	press(find(ui.scroll, "Mine9Cancel"))
	noFailures(ui, "economy flows")
	local log = {}
	for _, entry in ipairs(ui.sent) do
		table.insert(log, entry[1] .. "=" .. tostring(entry[2]))
	end
	local joined = table.concat(log, " ")
	for _, expected in ipairs({ "bazaar=Ore", "bazaar=BeastHide", "bid=Ore:12:21", "offer=Ore:12:21", "buyNow=Ore:12:21", "sellToBid=Ore:12 ",
		"bidCancel=Ore:7", "bidClaim=Herb", "bidClaim=Ore", "ahBrowse=weapon:1", "ahBuy=weapon:4:900", "ahBrowse=weapon:2", "ahBrowse=pet:1",
		"ahList=SunsteelSword:1250", "ahCancel=weapon:5", "ahClaim=pet" }) do
		assert((joined .. " "):find(expected, 1, true), "expected " .. expected .. " in " .. joined)
		checks += 1
	end
	assert(not joined:find("ahCancel=pet", 1, true), "expired listing cannot be cancelled")
	checkSent(ui)
	checks += 7
	-- Ironman and recovering orders.
	local iron = run({ snapshot = snapshot({ ironman = true }) })
	press(find(iron.gui, "AtlasButton"))
	visit(iron, "Ledger", "Orders")
	assert(not find(iron.scroll, "PlaceBuyorder"), "Ironman sees no Bazaar controls")
	visit(iron, "Ledger", "Auctions")
	assert(not find(iron.scroll, "AuctionWeapons"), "Ironman sees no Auction House controls")
	for _, entry in ipairs(iron.sent) do
		assert(entry[1] ~= "bazaar" and entry[1] ~= "ahBrowse", "Ironman never queries the markets")
	end
	local recovering = run({ snapshot = snapshot({ econPending = true }) })
	press(find(recovering.gui, "AtlasButton"))
	visit(recovering, "Ledger", "Orders")
	local recoveringText = {}
	for _, object in ipairs(recovering.scroll:GetDescendants()) do
		if object.ClassName == "TextLabel" then table.insert(recoveringText, object.Text) end
	end
	assert(table.concat(recoveringText, " "):find("Order recovering", 1, true), "pending order is explained")
	noFailures(recovering, "pending")
	checks += 3
end
-- 6. XP popup and level-up banner between snapshots.
do
	local ui = run()
	local before = snapshot()
	local nextLevel = Progression.levelForXp(before.xp.Mining) + 1
	local after = snapshot({ xp = { Mining = Data.XP_TABLE[nextLevel] + 5, Woodcutting = 900 },
		message = "Mined ore   ·   Mining level " .. nextLevel .. "! +" .. Data.levelCoinReward(nextLevel) .. " coins" })
	ui.update.OnClientEvent:Fire(after)
	local banner = ui.gui:FindFirstChild("LevelBanner")
	assert(banner.Visible, "level-up banner shows")
	local texts = {}
	for _, object in ipairs(banner:GetDescendants()) do
		if object.ClassName == "TextLabel" then
			table.insert(texts, object.Text)
		end
	end
	local joined = table.concat(texts, " | ")
	assert(joined:find("Mining", 1, true) and joined:find(tostring(nextLevel), 1, true), joined)
	assert(joined:find(tostring(Data.levelCoinReward(nextLevel)), 1, true) or joined:find("coins", 1, true), "coin reward shown: " .. joined)
	local bar = ui.gui:FindFirstChild("ActionBar")
	local xpLabel
	for _, object in ipairs(bar:GetChildren()) do
		if object.ClassName == "TextLabel" and object.Text:find("Mining", 1, true) then
			xpLabel = object
		end
	end
	assert(xpLabel and xpLabel.Text:find("+", 1, true), "XP popup shows")
	assert(not xpLabel.Text:find("Woodcutting", 1, true), "compact XP popup shows one entry")
	assert(xpLabel.Position.X.Scale >= 0.3 and xpLabel.Position.X.Scale + xpLabel.Size.X.Scale <= 0.7001, "XP popup stays between health and defense")
	local toast
	for _, object in ipairs(ui.gui:GetChildren()) do
		if object.ClassName == "TextLabel" and object.Text:find("Mined ore", 1, true) then toast = object end
	end
	assert(toast and toast.Visible, "rest of the server message still toasts")
	assert(not toast.Text:find("coins", 1, true), "banner coins are not announced twice: " .. toast.Text)
	noFailures(ui, "level-up")
	checks += 6
end

-- 7. Combat HUD (combat.client.lua) never collides with the atlas HUD, which owns
-- the top-left corner (x 10-315, y 8-96), at phone or desktop sizes.
local function combatHud(size)
	absoluteSize = size
	local playerGui = new("PlayerGui")
	local player = new("Player", { Name = "Tester", UserId = 1 })
	playerGui.Parent = player
	local replicated = new("ReplicatedStorage")
	new("RemoteEvent", { Name = "IsleCombat" }).Parent = replicated
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
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local delayed = {}
	local env = {
		game = game, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2, Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame, Color3 = roblox.Color3, TweenInfo = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end }, RaycastParams = { new = function() return {} end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		task = { spawn = function(fn, ...) local co = coroutine.create(fn); assert(coroutine.resume(co, ...)) end,
			delay = function(_, fn) table.insert(delayed, fn) end },
	}
	local chunk = luau.load(fs.readFile("combat.client.lua"), { debugName = "combat.client.lua", environment = env, injectGlobals = true })
	chunk()
	local hud = playerGui:FindFirstChild("IsleCombatHud")
	local monster = new("Model", { Name = "Golem" })
	monster.Parent = services.Workspace
	monster:SetAttribute("Health", 10)
	monster:SetAttribute("MaxHealth", 20)
	return { hud = hud, fx = fx, monster = monster, tagged = tagged, run = services.RunService, workspace = services.Workspace, delayed = delayed }
end
local function box(object, width, height)
	local size = object.Size
	local w, h = size.X.Offset, size.Y.Offset
	local x = object.Position.X.Scale * width + object.Position.X.Offset - object.AnchorPoint.X * w
	local y = object.Position.Y.Scale * height + object.Position.Y.Offset - object.AnchorPoint.Y * h
	return x, y, w, h
end
local function clearOfAtlasHud(x, y, w, h)
	return x >= 325 or y >= 104 or x + w <= 0 or y + h <= 0
end
for _, size in ipairs({ roblox.Vector2.new(730, 303), roblox.Vector2.new(560, 320), roblox.Vector2.new(1366, 768) }) do
	for _, boss in ipairs({ false, true }) do
		local c = combatHud(size)
		table.insert(c.tagged, c.monster)
		if boss then
			c.monster:SetAttribute("Boss", true)
			c.monster:SetAttribute("OwnerUserId", 1)
		end
		-- A boss panel appears via the owner scan; a regular target via a hit marker.
		c.fx.OnClientEvent:Fire("bossSpawn", { owner = 1, name = "Golem" })
		c.run.RenderStepped:Fire()
		local panel, banner
		for _, child in ipairs(c.hud:GetChildren()) do
			if child.Name == "Target" then panel = child elseif child.ClassName == "TextLabel" then banner = child end
		end
		local tag = size.X .. "x" .. size.Y .. (boss and " boss" or "")
		local px, py, pw, ph = box(panel, size.X, size.Y)
		local bx, by, bw, bh = box(banner, size.X, size.Y)
		assert(clearOfAtlasHud(px, py, pw, ph), "target panel clears the atlas HUD at " .. tag)
		assert(clearOfAtlasHud(bx, by, bw, bh), "combat banner clears the atlas HUD at " .. tag)
		assert(px >= 0 and px + pw <= size.X and bx >= 0 and bx + bw <= size.X, "combat HUD stays on screen at " .. tag)
		assert(by >= py + ph or bx >= px + pw or bx + bw <= px, "banner does not cover the target panel at " .. tag)
		if boss then assert(panel.Visible and pw >= 220, "boss panel shows at " .. tag) end
		checks += 5
	end
end
-- 8. Hit flashes reuse one Highlight per monster.
do
	local c = combatHud(roblox.Vector2.new(730, 303))
	table.insert(c.tagged, c.monster)
	for _ = 1, 40 do
		c.fx.OnClientEvent:Fire("hit", { model = c.monster, position = roblox.Vector3.new(), amount = 5 })
	end
	local highlights = 0
	for _, object in ipairs(c.workspace:GetDescendants()) do
		if object.ClassName == "Highlight" then highlights += 1 end
	end
	assert(highlights >= 1, "hit flash highlight created")
	assert(highlights <= 2, "40 hits on one monster keep at most one flash highlight (+ target ring), found " .. highlights)
	checks += 1
end

-- 9. Journal: quest log, lamp picker, diaries and the Builder's Terrace.
sweep(run({ snapshot = snapshot({ noJournal = true }) }), "no-journal", true)
for _, size in ipairs({ roblox.Vector2.new(730, 303), roblox.Vector2.new(420, 600) }) do
	local ui = run({ size = size })
	local tag = " @" .. size.X
	press(find(ui.gui, "AtlasButton"))
	local function lastSent() return ui.sent[#ui.sent] end
	local function texts(object)
		local out = {}
		for _, child in ipairs(object:GetDescendants()) do
			if child.ClassName == "TextLabel" or child.ClassName == "TextButton" then table.insert(out, tostring(child.Text)) end
		end
		return table.concat(out, "\n")
	end
	local function expect(condition, label) assert(condition, label .. tag); checks += 1 end
	visit(ui, "Journal", "Quests")
	noFailures(ui, "quests" .. tag)
	expect(find(ui.scroll, "QuestSurveyorsOath") ~= nil, "main quest card drawn")
	expect(texts(find(ui.scroll, "QuestSurveyorsOath")):find("DONE", 1, true) ~= nil, "completed quest badge")
	expect(texts(find(ui.scroll, "QuestBrassfallEchoes")):find("ACTIVE", 1, true) ~= nil, "available quest badge")
	expect(texts(find(ui.scroll, "QuestHollowLantern")):find("LOCKED", 1, true) ~= nil, "locked quest badge")
	expect(texts(find(ui.scroll, "QuestHollowLantern")):find("✗", 1, true) ~= nil, "unmet requirement marked")
	expect(texts(find(ui.scroll, "QuestBrassfallEchoes")):find("✓", 1, true) ~= nil, "met requirement marked")
	expect(texts(find(ui.scroll, "QuestBrassfallEchoes")):find("Quest Points", 1, true) ~= nil, "rewards listed")
	expect(find(ui.scroll, "QuestThornlingGarden") == nil, "side quests hidden on the main filter")
	expect(find(ui.scroll, "QuestHollowLanternClaim") == nil, "locked quest has no claim")
	press(find(ui.scroll, "QuestLineSide"))
	expect(find(ui.scroll, "QuestThornlingGarden") ~= nil and find(ui.scroll, "QuestSurveyorsOath") == nil, "side filter")
	local before = #ui.sent
	press(find(ui.scroll, "QuestThornlingGardenClaim"))
	expect(#ui.sent == before, "lamp quest opens the picker instead of sending")
	expect(find(ui.scroll, "LampPicker") ~= nil, "lamp picker shown")
	expect(find(ui.scroll, "LampFarming") ~= nil and find(ui.scroll, "LampWoodcutting") ~= nil, "lamp picker lists allowed skills")
	expect(find(ui.scroll, "LampMining") == nil, "lamp picker hides other skills")
	press(find(ui.scroll, "LampFarming"))
	expect(lastSent()[1] == "quest" and lastSent()[2] == "ThornlingGarden:Farming", "lamp claim sends quest:skill")
	press(find(ui.scroll, "QuestThornlingGardenClaim"))
	press(find(ui.scroll, "QuestThornlingGardenCancel"))
	expect(find(ui.scroll, "LampPicker") == nil, "cancel closes the lamp picker")
	press(find(ui.scroll, "QuestTidewingLullabyClaim"))
	expect(lastSent()[1] == "quest" and lastSent()[2] == "TidewingLullaby", "plain quest claim sends the quest id")
	visit(ui, "Journal", "Diaries")
	noFailures(ui, "diaries" .. tag)
	expect(find(ui.scroll, "DiarySummary") ~= nil, "diary summary card")
	expect(find(ui.scroll, "DiaryMeadowEasy") ~= nil and find(ui.scroll, "DiaryMeadowElite") ~= nil, "four tier cards")
	expect(texts(find(ui.scroll, "DiaryMeadowEasy")):find("CLAIMED", 1, true) ~= nil, "claimed tier badge")
	expect(find(ui.scroll, "DiaryMeadowEasyClaim") == nil, "claimed tier has no claim")
	expect(texts(find(ui.scroll, "DiaryMeadowHard")):find("Perk", 1, true) ~= nil, "tier perk shown")
	expect(texts(find(ui.scroll, "DiaryMeadowElite")):find("LOCKED", 1, true) ~= nil, "later tier locked")
	press(find(ui.scroll, "DiaryMeadowMediumClaim"))
	expect(lastSent()[1] == "diary" and lastSent()[2] == "Meadow:Medium", "diary claim payload")
	press(find(ui.scroll, "DiaryTempest"))
	expect(find(ui.scroll, "DiaryTempestEasy") ~= nil and find(ui.scroll, "DiaryMeadowEasy") == nil, "region switcher")
	press(find(ui.scroll, "DiaryTempestEasyClaim"))
	expect(lastSent()[2] == "Tempest:Easy", "region diary claim payload")
	visit(ui, "Journal", "Construction")
	noFailures(ui, "construction" .. tag)
	expect(find(ui.scroll, "TerraceSummary") ~= nil, "terrace summary card")
	expect(texts(find(ui.scroll, "TerraceSummary")):find("Skyreach", 1, true) ~= nil, "portal attunement shown")
	expect(texts(find(ui.scroll, "HotspotBenchCurrent")):find("Sturdy Workbench", 1, true) ~= nil, "built furniture named")
	expect(find(ui.scroll, "PlanSturdyWorkbench") ~= nil and find(ui.scroll, "PlanBrassWorkbench") ~= nil, "hotspot catalogue")
	expect(find(ui.scroll, "PlanHerbPlanter") == nil, "catalogue filtered to the hotspot")
	before = #ui.sent
	press(find(ui.scroll, "PlanBrassWorkbenchBuild"))
	expect(#ui.sent == before, "occupied hotspot build disabled")
	press(find(ui.scroll, "HotspotBenchCurrentRemove"))
	expect(#ui.sent == before and find(ui.scroll, "HotspotBenchCurrentDismantle") ~= nil, "removal asks for confirmation")
	press(find(ui.scroll, "HotspotBenchCurrentDismantle"))
	expect(lastSent()[1] == "remove" and lastSent()[2] == "Bench", "remove payload")
	press(find(ui.scroll, "HotspotGarden"))
	expect(find(ui.scroll, "PlanHerbPlanter") ~= nil, "hotspot switcher")
	press(find(ui.scroll, "PlanHerbPlanterBuild"))
	expect(lastSent()[1] == "build" and lastSent()[2] == "Garden:HerbPlanter", "build payload")
	before = #ui.sent
	press(find(ui.scroll, "PlanMoonbloomTerraceBuild"))
	expect(#ui.sent == before, "Carpentry level gate disables build")
	expect(texts(find(ui.scroll, "PlanMoonbloomTerrace")):find("✗", 1, true) ~= nil, "unmet level and costs marked")
	press(find(ui.scroll, "HotspotPortal"))
	expect(find(ui.scroll, "PortalPicker") ~= nil, "portal attunement picker")
	expect(find(ui.scroll, "PortalGloomhollow") == nil, "only attunable regions offered")
	press(find(ui.scroll, "PortalWindpine"))
	expect(lastSent()[1] == "portal" and lastSent()[2] == "Windpine", "portal payload")
	-- The terrace planner prompt opens this page.
	press(ui.tabs:FindFirstChild("LedgerButton"))
	ui.player:SetAttribute("IsleStation", "Construction")
	ui.player:SetAttribute("IsleStationVisit", 1)
	expect(find(ui.scroll, "TerraceSummary") ~= nil, "planner prompt opens the Construction page")
	checkSent(ui)
	noFailures(ui, "journal flow" .. tag)
end

print("UI QA passed " .. checks .. " checks (" .. created .. " mock instances).")
