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
-- Signals share one metatable (no per-signal closures). Every signal an
-- instance hands out is also listed in its state so Destroy can drop the
-- connections, as Roblox does.
local Signal = {}
Signal.__index = Signal
function Signal:Connect(fn)
	table.insert(self.handlers, fn)
	return { Disconnect = function() end }
end
function Signal:Fire(...)
	for _, handler in ipairs(table.clone(self.handlers)) do
		handler(...)
	end
end
local function newSignal()
	return setmetatable({ handlers = {} }, Signal)
end
local events = {
	MouseButton1Down = true, MouseButton1Up = true, MouseLeave = true, SelectionGained = true, Activated = true,
	FocusLost = true, OnClientEvent = true, HealthChanged = true, CharacterAdded = true, InputBegan = true,
	TextBoxFocusReleased = true, InputEnded = true, TouchTapInWorld = true, RenderStepped = true, AncestryChanged = true, InputChanged = true, CharacterRemoving = true,
	MouseEnter = true, SelectionLost = true, Event = true,
}
local guiClasses = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ScrollingFrame = true, ViewportFrame = true, TextBox = true }
local absoluteSize = roblox.Vector2.new(730, 303)
-- Per-instance state lives inside the instance table itself, under a private
-- key. A weak-keyed side table (the old `data`) leaked every instance ever
-- created: Luau has no ephemerons, so a value that references its own key (a
-- child's `parent`, a signal handler closing over its button) keeps the key
-- alive forever. `data[x]` remains as a read-only view for the tests.
-- State: props, children, parent, destroyed, and lazily propSignals, attrs,
-- attrSignals, signals (every signal handed out), fired.
local STATE = newproxy(false)
local data = setmetatable({}, {
	__index = function(_, object)
		return if type(object) == "table" then rawget(object, STATE) else nil
	end,
})
local methods = {}
local meta = {}
local created = 0
local function new(class, props)
	local object = setmetatable({}, meta)
	rawset(object, STATE, { props = { ClassName = class, Name = class }, children = {} })
	created += 1
	if props then
		for key, value in pairs(props) do
			object[key] = value
		end
	end
	return object
end
local function track(d, signal)
	local list = d.signals
	if list then
		table.insert(list, signal)
	else
		d.signals = { signal }
	end
	return signal
end
meta.__index = function(self, key)
	local method = methods[key]
	if method then
		return method
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
		local signal = track(d, newSignal())
		d.props[key] = signal
		d.tableProps = true
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
	local d = rawget(self, STATE)
	if key == "Parent" then
		assert(not d.destroyed, "The Parent property of a destroyed instance is locked")
		local old = d.parent
		if old then
			local siblings = rawget(old, STATE).children
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
	if key == "ClassName" then
		error("ClassName is read-only")
	end
	d.props[key] = value
	if type(value) == "table" then
		local mt = getmetatable(value)
		if mt == nil or mt == Signal then
			d.tableProps = true
		end
	end
	local propSignals = d.propSignals
	if propSignals then
		local signal = propSignals[key]
		if signal then
			signal:Fire()
		end
	end
end
meta.__tostring = function(self)
	return tostring(rawget(self, STATE).props.Name)
end
function methods:FindFirstChild(name)
	for _, child in ipairs(rawget(self, STATE).children) do
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
	for _, child in ipairs(rawget(self, STATE).children) do
		if rawget(child, STATE).props.ClassName == class then
			return child
		end
	end
	return nil
end
function methods:GetChildren()
	return table.clone(rawget(self, STATE).children)
end
local function collect(object, out)
	for _, child in ipairs(rawget(object, STATE).children) do
		table.insert(out, child)
		collect(child, out)
	end
	return out
end
function methods:GetDescendants()
	return collect(self, {})
end
function methods:IsA(class)
	local own = rawget(self, STATE).props.ClassName
	return own == class or class == "Instance" or (class == "GuiObject" and guiClasses[own] == true)
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
-- closures (and the GUI trees they capture) become garbage.
local function release(d)
	d.destroyed = true
	local signals = d.signals
	if signals then
		for _, signal in ipairs(signals) do
			table.clear(signal.handlers)
		end
	end
	local children = d.children
	d.children = {}
	for _, child in ipairs(children) do
		local cd = rawget(child, STATE)
		assert(not cd.destroyed, "The Parent property of a destroyed instance is locked")
		cd.parent = nil -- the whole child list goes at once: no per-child sibling search
		release(cd)
	end
end
function methods:Destroy()
	local d = rawget(self, STATE)
	local children = d.children
	d.children = {}
	for _, child in ipairs(children) do
		local cd = rawget(child, STATE)
		assert(not cd.destroyed, "The Parent property of a destroyed instance is locked")
		cd.parent = nil
		release(cd)
	end
	self.Parent = nil
	release(d)
end
-- Clone copies plain property values (not signals or ad-hoc tables) and the
-- child tree, building state directly instead of through __newindex.
local function cloneOf(object)
	local source = rawget(object, STATE)
	local props = table.clone(source.props)
	if source.tableProps then -- only then can props hold a signal or plain table
		for key, value in pairs(props) do
			if type(value) == "table" and (getmetatable(value) == nil or getmetatable(value) == Signal) then
				props[key] = nil
			end
		end
	end
	local copy = setmetatable({}, meta)
	local children = table.create(#source.children)
	rawset(copy, STATE, { props = props, children = children })
	created += 1
	for index, child in ipairs(source.children) do
		local childCopy = cloneOf(child)
		rawget(childCopy, STATE).parent = copy
		children[index] = childCopy
	end
	return copy
end
function methods:Clone()
	return cloneOf(self)
end
function methods:GetBoundingBox()
	return roblox.CFrame.new(), roblox.Vector3.new(1, 2, 1)
end
function methods:GetPropertyChangedSignal(name)
	local d = rawget(self, STATE)
	local signals = d.propSignals
	if not signals then
		signals = {}
		d.propSignals = signals
	end
	local signal = signals[name]
	if not signal then
		signal = track(d, newSignal())
		signals[name] = signal
	end
	return signal
end
function methods:GetAttribute(name)
	local attrs = rawget(self, STATE).attrs
	return if attrs then attrs[name] else nil
end
function methods:SetAttribute(name, value)
	local d = rawget(self, STATE)
	local attrs = d.attrs
	if not attrs then
		attrs = {}
		d.attrs = attrs
	end
	attrs[name] = value
	local signal = d.attrSignals and d.attrSignals[name]
	if signal then
		signal:Fire()
	end
end
function methods:GetAttributeChangedSignal(name)
	local d = rawget(self, STATE)
	local signals = d.attrSignals
	if not signals then
		signals = {}
		d.attrSignals = signals
	end
	local signal = signals[name]
	if not signal then
		signal = track(d, newSignal())
		signals[name] = signal
	end
	return signal
end
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
		xp = { Combat = 9000, Mining = 22000, Woodcutting = 400, Fishing = 0, Farming = 60, Smithing = 4500, Cooking = 100, Alchemy = 0, Enchanting = 1200, Taming = 0, Dungeoneering = 0, Carpentry = 50,
			Ranged = 4470, Magic = 13363, Fletching = 1200, Glyphcraft = 800, Agility = 3400, Hunter = 2600, Prayer = 47000, Thieving = 13400 },
		items = {
			Ore = 140, Timber = 40, Herb = 70, Fish = 30, Brassite = 12, Pickaxe = 1, Blade = 1, Tonic = 2, ExpeditionRation = 1,
			BrassSword = 1, BrassHelm = 1, BrassChestplate = 1, BrassGreaves = 1, BrassBoots = 1, SunsteelSword = 1, BrassPickaxe = 1,
			CopperHatchet = 1, ArcaneDust = 60, MeadowCharm = 1, QuarryTalisman = 1, EmberfoxPet = 1, CookedFish = 3, MightDraught = 2,
			StormFeather = 3, BrassIngot = 9, LegacyMystery = 2,
			-- Prayer & Thieving: remains, a draught, gloves and a gem.
			BrittleRemains = 24, HeavyRemains = 6, DevotionDraught = 1, LightfingerGloves = 1, SunstoneChip = 2,
			-- Combat styles: bows, staves, arrows (one too heavy for the longbow), glyphs, a tablet.
			WindpineStaff = 1, MeadowWand = 1, MeadowLongbow = 1, CopperArrow = 60, BrassArrow = 143, SunsteelArrow = 15,
			GaleGlyph = 40, StoneGlyph = 12, SparkGlyph = 25, SurgeGlyph = 6, VitaGlyph = 3, BindGlyph = 2, HubwardTablet = 2,
			-- Agility & Hunter: Skymarks, a Windrunner piece, kits and pelts.
			Skymark = 37, WindrunnerHood = 1, SnareKit = 1, SkyNet = 1, DownyPelt = 14, SunwingDust = 6,
			-- Gear depth: reforge stones, essence and tomes.
			EmberheartCinder = 1, WardstoneSeal = 2, WildheartEssence = 60, TemperingTome = 2, MasterworkTome = 1,
			-- Verdant Garden: seeds, compost, salve, Marks, Dust and crops for a visitor.
			MeadowSeeds = 5, SunwheatSeeds = 2, Compost = 3, BlightwardSalve = 1, VerdantMark = 40, BloomDust = 6, Sunwheat = 30,
			-- Workers depth: fuel, an upgrade and a chest to install.
			CharredBriquette = 12, EverflameHeart = 1, WorkerGleamSprinkler = 1, WorkerBrassChest = 1, CondensedOre = 2,
			-- Pets depth: candy, held items and a Tier Boost.
			PetCandy = 2, IronbarkCollar = 1, GlimmerClover = 1, AscendantPrism = 1, StarlitCandy = 1,
		},
		collection = { Ore = 320, Timber = 60, Herb = 70, Fish = 30, Brassite = 40, Shard = 2, StormFeather = 3, BeastHide = 0 },
		equipment = { weapon = "BrassSword", helmet = "BrassHelm", chest = "BrassChestplate", legs = "BrassGreaves", boots = "BrassBoots", ammo = "BrassArrow" },
		enchants = { BrassSword = { Sharpness = 2, Critical = 5 } },
		accessoryBag = { "MeadowCharm", "QuarryTalisman" },
		pets = { { id = "Tidewing", level = 5, xp = 100, rarity = "Epic", item = "WarbandTag", candy = 3 }, { id = "Emberfox", level = 1, xp = 0 }, { id = "Bloomsnail", level = 60, xp = 10, rarity = "Legendary", candy = 10 } },
		activePet = 1,
		buffs = { MightDraught = { expires = 120, stats = { strength = 15 } } },
		bestiary = { BramblebackBoar = 30, Thornling = 1, ShaleCrawler = 1000 },
		slayerXp = { Bramble = 20, Gloom = 0, Tempest = 0 },
		autocast = "GaleLance",
		-- Skill Mastery: a few Mining and Melee nodes, a worn mantle request (Mining < 99: ignored).
		mastery = { trees = { Mining = { SteadyPick = 3, QuarrySense = 1 }, Melee = { IronGrip = 2 } }, respecs = { Mining = 1 }, cooldowns = {}, active = {}, title = "Mining" },
		-- Gear depth: a reforged, starred, tempered sword and a masterwork charm.
		reforges = { BrassSword = "Honed", MeadowCharm = "Gleaming" }, stars = { BrassSword = 2 },
		books = { BrassSword = { tempering = 3 }, MeadowCharm = { masterwork = true } },
	}
end
local function snapshot(options)
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
		xp = p.xp, items = p.items, collection = p.collection, coins = 52000, bank = 10, bankRevision = 3, levels = levels, message = options.message or "",
		consumables = { Tonic = { healing = 40, recovery = 0, action = "Drink", readyIn = 0 }, ExpeditionRation = { healing = 65, recovery = 12, action = "Eat", readyIn = 5 } },
		recipes = { { id = "Pickaxe", costs = { Ore = 3, Timber = 2 }, skill = "Smithing", level = 1, collection = { Ore = 3 }, description = "A pick", repeatable = false, unlocked = true, xp = 24 } },
		regions = { { name = "Skyreach", unlocked = false, requirement = "Complete 6 contracts" } },
		stats = { maxHealth = 120, defense = 5 }, quest = { title = "Contract", detail = "Do it", ready = true },
		slayer = { tier = 1, active = true, progress = 1, target = 2, ready = false, completed = 0, coins = 20, xp = 30 },
		-- Workers depth (server Workers.state / Workers.info): a fuelled, upgraded tier 3 delver,
		-- a full auto-selling feller, a permanent-fuel Shardling Sentry and a fresh tiller.
		workers = {
			{ slot = 1, resource = "Ore", name = "Copperstone Delver", kind = "gather", output = "Ore", tier = 3, maxTier = 7, ready = 82, capacity = 540, interval = 60, speed = 110, perHour = 66,
				full = false, store = { Ore = 80, CondensedOre = 2 }, coins = 0, fuel = { id = "CharredBriquette", speed = 10, remaining = 1500 }, upgrades = { "WorkerBundler", "WorkerStoreAnnex" },
				chest = "WorkerCoffer", press = 1, autoSell = false, upgradeCost = { Timber = 20, Ore = 12, AlloyIngot = 4, AetherIngot = 2 } },
			{ slot = 2, resource = "Timber", name = "Meadow Timber Feller", kind = "gather", output = "Timber", tier = 1, maxTier = 7, ready = 120, capacity = 120, interval = 120, speed = 100, perHour = 30,
				full = true, store = { Timber = 120 }, coins = 720, upgrades = { "WorkerCoinchute", false }, press = 0, autoSell = true, upgradeCost = { Timber = 10, Ore = 6 } },
			{ slot = 3, resource = "ShardlingSentry", name = "Shardling Sentry", kind = "combat", output = "Shard", tier = 7, maxTier = 7, ready = 0, capacity = 1000, interval = 78, speed = 125, perHour = 57.7,
				full = false, store = {}, coins = 0, fuel = { id = "EverflameHeart", speed = 25, permanent = true }, upgrades = { false, false }, press = 0, autoSell = false },
			{ slot = 4, resource = "Herb", name = "Meadow Herb Tiller", kind = "gather", output = "Herb", tier = 1, maxTier = 7, ready = 0, capacity = 120, interval = 120, speed = 100, perHour = 30,
				full = false, store = {}, coins = 0, upgrades = { false, false }, press = 0, autoSell = false, upgradeCost = { Timber = 10, Ore = 6 } },
		},
		workerInfo = { slots = 5, maxSlots = 12, uniques = 14, nextAt = 20, built = 4, buildCost = { Timber = 25, Ore = 15 }, crafted = { Ore = 7, Timber = 1, ShardlingSentry = 127, Herb = 1 } },
		decorations = { Garden = true },
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
	local PD = Data.PetDepth
	for index, pet in ipairs(p.pets) do
		local def = Data.PetById[pet.id]
		local rarity = Progression.petRarity(pet)
		pets[index] = { id = pet.id, level = pet.level, xp = pet.xp, next = Data.petXpToNext(pet.level, rarity), active = p.activePet == index,
			rarity = rarity, item = pet.item, candy = pet.candy or 0, candyMax = PD.CANDY_MAX, abilities = PD.abilityView(def, pet.level, rarity),
			stats = Progression.petStats(p, pet, def), upgrade = PD.upgradeCost(def, rarity) }
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
		pets = pets, petDepth = { upgrade = { id = "Gustling", level = 12, from = "Rare", to = "Epic", ends = 900, remaining = 4000, ready = options.bossReady == true }, taming = { level = 12, xpBonus = 10, statBonus = 2.5 } },
		buffs = { MightDraught = { remaining = 95, stats = { strength = 15 } } }, collections = collections, bestiary = p.bestiary,
		slayer = { lines = lines, quest = if options.noQuest then nil else { line = "Bramble", tier = 1, progress = 40, needed = 150, bossReady = options.bossReady == true } },
		enchants = p.enchants, combat = Progression.combatLoadout(p), gear = { reforges = p.reforges, stars = p.stars, books = p.books },
		regions = { { id = "Hub", name = "Aether Hub", unlocked = true, requirement = "" }, { id = "Gloomhollow", name = "Gloomhollow Caverns", unlocked = false, requirement = "Mining 30, Combat 15" } },
		mastery = Progression.masteryView(p, options.masteryNow or 0),
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
			carpentry = 32, accessorySlots = 1, workerHaste = 0.05,
			island = { count = 3, cap = 120, counts = { TimberFence = 2, StonePath = 1 }, value = 3, tier = 1, tierName = "Bare Rock" } },
	}
	-- Agility & Hunter (server Skills.state): records, a lap underway, traps, an open vendor.
	result.agilityHunter = {
		agility = { laps = { QuayRigging = 31, MosswakeHedgerow = 4 }, best = { QuayRigging = 41.2, MosswakeHedgerow = 63.8 }, lapTiers = 1,
			run = { course = "QuayRigging", next = 3, expiresIn = 22 } },
		hunter = { log = { PuffcapHopper = 27, SunwingMoth = 9 }, logTiers = 2, maxTraps = 2,
			traps = { { creature = "PuffcapHopper", state = "caught", ticks = 6, spot = "PuffcapHopper#1" }, { creature = "PuffcapHopper", state = "set", ticks = 2, spot = "PuffcapHopper#3" } } },
		vendor = { skill = if options.vendorClosed then "" else "Agility", openUntil = if options.vendorClosed then 0 else os.time() + 252 },
	}
	-- Prayer & Thieving (server Prayer.state / Prayer.thievingState): two prayers on, an altar visit open.
	result.prayer = { points = 31.4, max = 50, active = { "StonehideWard", "WardOfFangs" }, quick = { "StonehideWard", "BlazingEdge" }, drain = 18, secondsLeft = 104,
		offered = { BrittleRemains = 40 }, altar = "QuayChapel", altarUntil = os.time() + 40, riteIn = 0 }
	result.thieving = { thefts = { Farmhand = 42, SweetbunStall = 9 }, gloves = "LightfingerGloves", gloveBonus = 0.05, deftness = 12,
		chances = { Farmhand = 0.83, SweetbunStall = 0.79 }, cooldowns = { Farmhand = 2 }, stunIn = 0 }
	-- Verdant Garden (server Garden.state): plot 1 ripe, 2 growing + watered + pest, 3 blighted, 4 empty, 5+ locked.
	do
		local plots = {}
		for i = 1, 12 do plots[i] = { index = i, unlocked = i <= 4, stage = 0, ripe = false, fraction = 0, watered = 0, compost = false, treated = false, sick = false, dead = false } end
		plots[1] = { index = 1, unlocked = true, crop = "Herb", stage = 4, ripe = true, remaining = 0, fraction = 1, watered = 0, compost = true, treated = false, sick = false, dead = false }
		plots[2] = { index = 2, unlocked = true, crop = "Sunwheat", stage = 2, ripe = false, remaining = 340, fraction = .45, watered = 900, compost = false, treated = false, sick = false, dead = false, pest = "Rootgrub" }
		plots[3] = { index = 3, unlocked = true, crop = "Herb", stage = 2, ripe = false, fraction = .4, watered = 0, compost = false, treated = false, sick = true, dead = false, deathIn = 5000 }
		local milestones = {}
		for _, c in ipairs(Data.Garden.Crops) do milestones[c.id] = { count = if c.id == "Herb" then 130 else 0, tier = if c.id == "Herb" then 1 else 0, fortune = 0 } end
		result.garden = {
			level = 3, xp = 260, floor = 180, nextAt = 400, plots = plots, unlocked = 4, maxPlots = 12, nextPlot = "Garden level 5 or Farming 15",
			milestones = milestones, milestoneTiers = 1,
			composter = { unlocked = true, matter = 240, cap = 4000, out = 2, dust = 1, upgrade = 0, interval = 600, nextIn = 120 },
			visitors = {
				{ id = 7, npc = "Pell", wants = { Herb = 12 }, order = { "Herb" }, coins = 48, marks = 2, gxp = 9, xp = 25, items = {} },
				{ id = 8, npc = "Corvel", wants = { Sunwheat = 40, Herb = 10 }, order = { "Herb", "Sunwheat" }, coins = 900, marks = 4, gxp = 20, xp = 300, items = { BloomDust = 1 } },
			},
			visitorCap = 2, nextVisitorIn = nil, served = 3, skin = "Mossbed", skins = { Loam = true, Mossbed = true }, rate = 1.02, setActive = false, serverTime = os.time(),
			owned = { SproutwoodHoe = true }, -- owned through the upgrade chain (no SproutwoodHoe in the satchel)
		}
	end
	if options.malformed then
		result.garden = { level = "three", plots = { 5, { crop = "Ghost", stage = "x" }, { crop = "Herb", remaining = "soon", fraction = 9 } }, milestones = { Herb = 3 },
			composter = { unlocked = true, matter = "lots", upgrade = 99 }, visitors = { 3, { id = "x", npc = "Nobody" }, { id = 4, npc = "Pell", wants = { Ghost = 2, Herb = "many" } } },
			skins = 5, nextPlot = 7 }
		result.agilityHunter = { agility = { laps = { QuayRigging = "many", Nope = 3 }, best = 7, run = "x" }, hunter = { log = 5, traps = { 3, { creature = "Ghost" } }, maxTraps = "two" }, vendor = { skill = 4 } }
		result.prayer = { points = "x", max = {}, active = { 5, "Ghost" }, quick = 3, offered = 7, altar = 4, altarUntil = "soon", drain = "fast", secondsLeft = {} }
		result.thieving = { thefts = 5, chances = { Farmhand = "x" }, cooldowns = 3, gloves = 7, stunIn = "now", deftness = {} }
		result.journal ={ questPoints = "many", quests = { 3, { id = 7 }, { id = "SurveyorsOath", requires = "x", objectives = { 5 } } },
			diaries = { "Meadow", { region = "Meadow", claimed = "two", tiers = { 4, { tier = 9 } } } }, construction = { furniture = { Bench = 3, Portal = "Ghost" }, portalRegions = { 5, "Atlantis" }, carpentry = "x", island = { counts = 5, count = "many", value = "x", cap = {} } } }
		result.depth = {
			skills = "oops", totalLevel = "x", stats = 5, equipment = { weapon = 5, helmet = "NotAnItem" }, tools = { Mining = {} },
			accessoryBag = { 1, "MeadowCharm" }, activeAccessories = 7, accessorySlots = "four", pets = { 1, { id = "Nope" }, { id = "Tidewing", level = "x", rarity = 5, abilities = "x", stats = 4, upgrade = { items = 5, to = 3 }, candy = "many", item = 7 },
				{ id = "Emberfox", abilities = { 3, { name = 4 } }, upgrade = { coins = "x", items = { Nope = "y" } }, candyMax = 900 } },
			petDepth = { upgrade = { id = "Ghost", remaining = "soon", to = 4 }, taming = { level = "x" } },
			buffs = { MightDraught = { remaining = "soon" }, Broken = 3 }, collections = { Ore = 5, Timber = { count = "many" } }, bestiary = { BramblebackBoar = "lots", Ghost = 3 },
			slayer = { lines = { Bramble = 3 }, quest = { line = "Unknown", tier = "II" } }, enchants = { BrassSword = { Mystery = 2 }, Blade = 4 }, regions = { 3, { id = 7 } },
			mastery = { trees = { Mining = 5, Fishing = { nodes = "x", states = { PatientLine = 3, Nope = "owned" }, available = "lots", cooldown = {} } }, tokens = 7, capes = "x", cape = 5, titles = { Mining = 4 } },
			gear = { reforges = { BrassSword = 5, Blade = "Nope", BrassHelm = "Honed" }, stars = { BrassSword = "many", BrassHelm = 99 }, books = { BrassSword = 3, BrassHelm = { tempering = "x", masterwork = "yes" } } },
		}
		result.workers = { { resource = "Ghost", tier = "x", ready = "lots", capacity = 0, store = 7, fuel = "y", upgrades = 3, chest = 5, upgradeCost = "x", maxTier = "many", output = 4 },
			{ resource = "Ore", fuel = { id = 5, remaining = "soon" }, upgrades = { "Nope", 7 }, store = { Ghost = "x" }, upgradeCost = { Ghost = 2 } }, 5 }
		result.workerInfo = { slots = "many", maxSlots = 99, uniques = "x", nextAt = "soon", crafted = 5, buildCost = 3 }
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
	Journal = { "Bearing", "Quests", "Diaries", "Construction", "Regions", "Crew", "Agility" }, Hero = { "Skills", "Mastery", "Gear", "Combat", "Spellbook", "Prayer", "Enchant", "Reforge", "Accessories", "Pets" }, Satchel = { "Items", "Collections" },
	Workshop = { "Forge", "Hearth", "Cauldron", "Workbench", "Workers", "Home", "Garden" }, Hunt = { "Slayer", "Bestiary", "Hunter", "Thieving" }, Ledger = { "Bank", "Market", "Orders", "Auctions", "Merchant", "Vendors" },
}
local tabOrder = { "Journal", "Hero", "Satchel", "Workshop", "Hunt", "Ledger" }
local verbs = {
	equip = function(item) return Data.Items[item] ~= nil and Data.Items[item].slot ~= nil end,
	unequip = function(item) return item == "weapon" or item == "helmet" or item == "chest" or item == "legs" or item == "boots" or item == "ammo" end,
	autocast = function(item) return item == "none" or (Data.Spells[item] ~= nil and Data.Spells[item].autocast == true) end,
	consume = function(item) return Data.Items[item] ~= nil and Data.Items[item].kind == "consumable" end,
	accessory = function(item) return Data.Items[item] ~= nil and Data.Items[item].kind == "accessory" end,
	petSummon = function(item) return type(item) == "string" and item:match("^%d+$") ~= nil end,
	petAdopt = function(item) return Data.Items[item] ~= nil and Data.Items[item].kind == "pet" end,
	-- Pets depth verbs name the pet "index:speciesId" (server checks both).
	petItem = function(item)
		local index, species, id = tostring(item):match("^(%d+):(%w+):(%w*)$")
		return index ~= nil and Data.PetById[species] ~= nil and (id == "" or id == "none" or Data.PetDepth.HeldItems[id] ~= nil)
	end,
	petCandy = function(item)
		local index, species, id = tostring(item):match("^(%d+):(%w+):(%w+)$")
		return index ~= nil and Data.PetById[species] ~= nil and Data.PetDepth.Candies[id] ~= nil
	end,
	petTierBoost = function(item) local index, species = tostring(item):match("^(%d+):(%w+)$") return index ~= nil and Data.PetById[species] ~= nil end,
	petUpgrade = function(item) local index, species = tostring(item):match("^(%d+):(%w+)$") return index ~= nil and Data.PetById[species] ~= nil end,
	petClaim = function(item) return item == nil end,
	petCancel = function(item) return item == nil end,
	petShop = function(item) return Data.PetDepth.ShopByItem[item] ~= nil end,
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
	-- Gear depth verbs.
	reforge = function(item) return Data.Gear.category(Data.Items[item]) ~= nil end,
	reforgeStone = function(item)
		local id, stone = tostring(item):match("^(%w+):(%w+)$")
		return id ~= nil and Data.Items[stone] ~= nil and Data.Items[stone].reforgeStone ~= nil and Data.Gear.reforgeFits(Data.Items[stone].reforgeStone, Data.Items[id])
	end,
	star = function(item) return Data.Gear.canStar(Data.Gear.category(Data.Items[item])) end,
	tome = function(item)
		local id, tome = tostring(item):match("^(%w+):(%w+)$")
		return id ~= nil and Data.Gear.category(Data.Items[id]) ~= nil and Data.Gear.Tomes[tome] == true
	end,
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
	place = function(item)
		local propId, x, z, rot = Data.Island.parseRequest(item)
		return propId ~= nil and Data.Island.Props[propId] ~= nil and rot <= 3 and math.abs(x) <= Data.Island.RANGE and math.abs(z) <= Data.Island.RANGE
	end,
	pickup = function(item) return type(item) == "string" and item:match("^%d+$") ~= nil and tonumber(item) <= Data.Island.MAX_PLACEMENTS end,
	masteryUnlock = function(item)
		local tree, node = tostring(item):match("^(%a+):(%w+)$")
		return tree ~= nil and Data.Mastery.TreeById[tree] ~= nil and Data.Mastery.TreeById[tree].NodeById[node] ~= nil
	end,
	masteryRespec = function(item) return Data.Mastery.TreeById[item] ~= nil end,
	ability = function(item) return Data.Mastery.TreeById[item] ~= nil and Data.Mastery.TreeById[item].capstone ~= nil end,
	masteryWear = function(item)
		local kind, skill = tostring(item):match("^(%a+):(%a*)$")
		return (kind == "cape" or kind == "aura" or kind == "title") and (skill == "" or Data.Skills[skill] ~= nil)
	end,
	-- Verdant Garden verbs.
	plant = function(item)
		local i, seed = tostring(item):match("^(%d+):(%w+)$")
		return i ~= nil and tonumber(i) >= 1 and tonumber(i) <= 12 and Data.Garden.CropBySeed[seed] ~= nil
	end,
	harvestPlot = function(item) return item == "all" or (tonumber(item) ~= nil and tonumber(item) >= 1 and tonumber(item) <= 12) end,
	waterPlot = function(item) return item == "all" or (tonumber(item) ~= nil and tonumber(item) >= 1 and tonumber(item) <= 12) end,
	fertilise = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= 12 end,
	treatPlot = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= 12 end,
	clearPest = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= 12 end,
	clearPlot = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= 12 end,
	compost = function(item) local id, n = tostring(item):match("^(%w+):(%d+)$") return id ~= nil and Data.Garden.organic(id) > 0 and tonumber(n) >= 1 end,
	compostClaim = function(item) return item == nil end,
	composterUpgrade = function(item) return item == nil end,
	visitorAccept = function(item) return tostring(item):match("^%d+$") ~= nil end,
	visitorDecline = function(item) return tostring(item):match("^%d+$") ~= nil end,
	gardenBuy = function(item) return Data.Garden.ShopById[item] ~= nil end,
	gardenSkin = function(item) return Data.Garden.SkinById[item] ~= nil end,
	-- Workers depth verbs.
	workerClaim = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= Data.Workers.MAX_SLOTS end,
	workerClaimAll = function(item) return item == nil end,
	workerBuild = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= Data.Workers.MAX_SLOTS end,
	workerUpgrade = function(item) return tostring(item):match("^%d+$") ~= nil and tonumber(item) <= Data.Workers.MAX_SLOTS end,
	workerFuel = function(item) local slot, id = tostring(item):match("^(%d+):(%w+):?%d*$") return slot ~= nil and Data.Workers.Fuels[id] ~= nil end,
	workerInstall = function(item) local slot, id = tostring(item):match("^(%d+):(%w+)$") return slot ~= nil and (Data.Workers.Upgrades[id] ~= nil or Data.Workers.Chests[id] ~= nil) end,
	workerRemove = function(item) return tostring(item):match("^%d+:[12]$") ~= nil or tostring(item):match("^%d+:chest$") ~= nil end,
	workerAssign = function(item) local slot, id = tostring(item):match("^(%d+):(%w+)$") return slot ~= nil and Data.Workers.TypeById[id] ~= nil end,
	workerBlueprint = function(item) local id, tier = tostring(item):match("^(%w+):(%d)$") return id ~= nil and Data.Workers.TypeById[id] ~= nil and tonumber(tier) >= 1 and tonumber(tier) <= 7 end,
	-- Prayer & Thieving verbs.
	prayer = function(item) return Data.Prayer.PrayerById[item] ~= nil end,
	prayerOff = function(item) return item == nil end,
	prayerQuick = function(item) local slot, id = tostring(item):match("^(%d):(%w*)$") return slot ~= nil and tonumber(slot) <= Data.Prayer.QUICK_SLOTS and (id == "" or Data.Prayer.PrayerById[id] ~= nil) end,
	offerRemains = function(item) return Data.Prayer.RemainsById[item] ~= nil end,
	skillBuy = function(item)
		local skill, id = tostring(item):match("^(%a+):(%w+)$")
		local vendor = skill and Data.SkillVendors[skill]
		if not vendor then return false end
		for _, entry in ipairs(vendor.shop) do if entry.item == id then return true end end
		return false
	end,
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
	-- Entering island build mode closes the atlas; reopen it like a player would.
	if not ui.atlas.Visible then
		press(find(ui.gui, "AtlasButton"))
	end
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
	assert(views > 0 and views <= 14 + 2, "compact layout draws at most 14 item + 2 decorative live thumbnails, drew " .. views)
	-- Item icons have their own budget: decorative title art never pushes the
	-- first item icons back to initials ("SM").
	local function itemArt(root)
		local drawn, initials = 0, 0
		for _, object in ipairs(root:GetDescendants()) do
			if object.Name == "ItemIcon" then
				local hasView = false
				for _, child in ipairs(object:GetChildren()) do if child.ClassName == "ViewportFrame" then hasView = true end end
				if hasView then drawn += 1 elseif drawn < 14 then initials += 1 end
			end
		end
		return drawn, initials
	end
	local drawn, early = itemArt(ui.scroll)
	assert(drawn >= 14 and early == 0, "compact: the first 14 item icons all get art (drew " .. drawn .. ", initials before budget " .. early .. ")")
	visit(ui, "Journal", "Quests")
	visit(ui, "Satchel", "Items")
	drawn, early = itemArt(ui.scroll)
	assert(drawn >= 14 and early == 0, "budget resets per render: item art after revisiting (" .. drawn .. ")")
	local wide = run({ size = roblox.Vector2.new(760, 690) })
	press(find(wide.gui, "AtlasButton"))
	visit(wide, "Satchel", "Items")
	local wideViews = 0
	for _, object in ipairs(wide.scroll:GetDescendants()) do
		if object.ClassName == "ViewportFrame" then wideViews += 1 end
	end
	assert(wideViews > views and wideViews <= 24 + 6, "desktop keeps the larger budget, drew " .. wideViews)
	checks += 4
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
-- 5a. Gear depth: Hero › Reforge, Gear and Satchel item detail.
do
	local ui = run()
	press(find(ui.gui, "AtlasButton"))
	local function textOf(root)
		local out = {}
		for _, object in ipairs(root:GetDescendants()) do
			if object.ClassName == "TextLabel" or object.ClassName == "TextButton" then table.insert(out, tostring(object.Text)) end
		end
		return table.concat(out, " | ")
	end
	local function expect(cond, case) assert(cond, case); checks += 1 end
	visit(ui, "Hero", "Reforge")
	noFailures(ui, "reforge page")
	expect(find(ui.scroll, "ReforgeSummary") ~= nil, "anvil summary drawn")
	press(find(ui.scroll, "ReforgeBrassSword"))
	local item = find(ui.scroll, "ReforgeItem")
	expect(item ~= nil, "selected item card")
	local itemText = textOf(item)
	expect(itemText:find("Honed Brass Sword ★★", 1, true) ~= nil, "reforge + stars in the title: " .. itemText)
	expect(itemText:find("Tempered 3/10", 1, true) ~= nil, "tempering layer listed")
	expect(itemText:find("Upgrade total", 1, true) ~= nil, "upgrade total listed")
	local roll = textOf(find(ui.scroll, "ReforgeRoll"))
	expect(roll:find("500 coins", 1, true) ~= nil, "uncommon anvil cost preview: " .. roll)
	expect(roll:find("Vicious", 1, true) ~= nil and roll:find("Emberwrought", 1, true) == nil, "pool lists anvil reforges only")
	expect(find(ui.scroll, "StoneEmberwrought") ~= nil and find(ui.scroll, "StoneStarbitten") ~= nil, "melee stones listed")
	expect(find(ui.scroll, "StoneGalestrung") == nil, "bow stones hidden for a sword")
	expect(textOf(find(ui.scroll, "StoneEmberwrought")):find("Change:", 1, true) ~= nil, "stone stat diff")
	expect(textOf(find(ui.scroll, "ReforgeStars")):find("Gain:", 1, true) ~= nil, "star gain preview")
	expect(textOf(find(ui.scroll, "TomeMasterwork")):find("Uncommon", 1, true) ~= nil, "masterwork rarity preview")
	press(find(ui.scroll, "ReforgeRollReforge"))
	press(find(ui.scroll, "StoneEmberwroughtApply"))
	press(find(ui.scroll, "ReforgeStarsStar"))
	press(find(ui.scroll, "TomeTemperingTemper"))
	press(find(ui.scroll, "TomeMasterworkBind"))
	-- Stones without a copy are disabled (no verb).
	press(find(ui.scroll, "StoneStarbittenApply"))
	-- Masterwork accessory: rarity colour and Magical Power preview.
	press(find(ui.scroll, "ReforgeMeadowCharm"))
	local charm = textOf(find(ui.scroll, "ReforgeItem"))
	expect(charm:find("Gleaming Meadow Charm", 1, true) ~= nil and charm:find("Uncommon", 1, true) ~= nil, "masterwork charm shows its bumped rarity: " .. charm)
	expect(find(ui.scroll, "ReforgeStars") == nil and find(ui.scroll, "TomeTempering") == nil, "accessories cannot be starred or tempered")
	expect(find(ui.scroll, "StoneResonant") ~= nil, "accessory stones listed")
	-- Gear page: equipped card shows the layered name and opens the anvil.
	visit(ui, "Hero", "Gear")
	press(find(ui.scroll, "Slotweapon"))
	expect(textOf(find(ui.scroll, "Equippedweapon")):find("Honed Brass Sword ★★", 1, true) ~= nil, "equipped card shows reforge and stars")
	press(find(ui.scroll, "EquippedweaponReforge"))
	expect(find(ui.scroll, "ReforgeSummary") ~= nil, "Reforge action opens Hero › Reforge")
	-- Satchel item detail.
	visit(ui, "Satchel", "Items")
	press(find(ui.scroll, "ItemBrassSword"))
	expect(textOf(find(ui.scroll, "ItemDetail")):find("Honed Brass Sword ★★", 1, true) ~= nil, "item detail title")
	expect(textOf(find(ui.scroll, "ItemUpgrades")):find("Tempered", 1, true) ~= nil, "item detail upgrade breakdown")
	press(find(ui.scroll, "ItemUpgradesReforge"))
	expect(find(ui.scroll, "ReforgeItem") ~= nil, "item detail opens the anvil")
	noFailures(ui, "gear flows")
	local log = {}
	for _, entry in ipairs(ui.sent) do table.insert(log, entry[1] .. "=" .. tostring(entry[2])) end
	local joined = table.concat(log, " ")
	for _, expected in ipairs({ "reforge=BrassSword", "reforgeStone=BrassSword:EmberheartCinder", "star=BrassSword", "tome=BrassSword:TemperingTome", "tome=BrassSword:MasterworkTome" }) do
		expect(joined:find(expected, 1, true) ~= nil, "expected " .. expected .. " in " .. joined)
	end
	expect(joined:find("StarbiteShard", 1, true) == nil, "disabled stone sends nothing")
	checkSent(ui)
	-- Malformed gear state still draws the anvil.
	local bad = run({ snapshot = snapshot({ malformed = true }) })
	press(find(bad.gui, "AtlasButton"))
	visit(bad, "Hero", "Reforge")
	press(find(bad.scroll, "ReforgeBrassHelm"))
	noFailures(bad, "malformed gear")
	expect(find(bad.scroll, "ReforgeItem") ~= nil, "malformed gear still draws")
	print("Gear depth UI: checks passed.")
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
	assert(xpLabel.Position.X.Scale >= 0.46 and xpLabel.Position.X.Scale + xpLabel.Size.X.Scale <= 0.7601, "XP popup stays between mana and defense")
	local toast
	for _, object in ipairs(ui.gui:GetChildren()) do
		if object.ClassName == "TextLabel" and object.Text:find("Mined ore", 1, true) then toast = object end
	end
	assert(toast and toast.Visible, "rest of the server message still toasts")
	assert(not toast.Text:find("coins", 1, true), "banner coins are not announced twice: " .. toast.Text)
	noFailures(ui, "level-up")
	checks += 6
end
-- 6b. Combat XP paid on kill (server "combatXp"): a level-up snapshot with an
-- empty message lands just before the kill toast (which no longer names XP).
do
	local ui = run()
	local before = snapshot()
	local nextLevel = Progression.levelForXp(before.xp.Combat) + 1
	local xp = { Combat = Data.XP_TABLE[nextLevel] + 3 }
	ui.update.OnClientEvent:Fire(snapshot({ xp = xp, message = "" }))
	assert(ui.gui:FindFirstChild("LevelBanner").Visible, "combat level-up banner on the XP snapshot")
	local popup = find(ui.gui:FindFirstChild("ActionBar"), "XpPopup")
	assert(popup.Text:find("Combat", 1, true) and find(ui.gui:FindFirstChild("ActionBar"), "XpPill").Visible, "combat XP popup")
	ui.update.OnClientEvent:Fire(snapshot({ xp = xp, message = "Thornling slain • +4 coins" }))
	local toast
	for _, object in ipairs(ui.gui:GetChildren()) do
		if object.ClassName == "TextLabel" and object.Text:find("slain", 1, true) then toast = object end
	end
	assert(toast and toast.Visible and popup.Text:find("Combat", 1, true), "kill toast follows, popup kept")
	-- Without a level-up the kill snapshot itself carries the XP gain.
	local quiet = run()
	quiet.update.OnClientEvent:Fire(snapshot({ xp = { Combat = before.xp.Combat + 40 }, message = "Thornling slain • +4 coins" }))
	assert(find(quiet.gui:FindFirstChild("ActionBar"), "XpPopup").Text:find("+40 Combat", 1, true), "kill snapshot shows the XP popup")
	noFailures(ui, "combat xp on kill")
	checks += 4
	-- Pets depth review fixes (on this run, no extra harness): the Roost Cancel
	-- needs a Confirm and is hidden once ready; one candy button per type;
	-- verbs carry index:speciesId.
	local function last() return ui.sent[#ui.sent] or {} end
	visit(ui, "Hero", "Pets")
	noFailures(ui, "pets page")
	local sentBefore = #ui.sent
	press(find(ui.scroll, "PetCancelButton"))
	assert(#ui.sent == sentBefore and find(ui.scroll, "PetCancelConfirm") ~= nil, "Roost cancel asks for confirmation first")
	press(find(ui.scroll, "PetCancelConfirm"))
	assert(last()[1] == "petCancel", "confirmed cancel sends petCancel")
	press(find(ui.scroll, "PetCandyButton"))
	assert(last()[1] == "petCandy" and last()[2] == "1:Tidewing:PetCandy", "Pet Candy button feeds Pet Candy: " .. tostring(last()[2]))
	press(find(ui.scroll, "StarlitCandyButton"))
	assert(last()[1] == "petCandy" and last()[2] == "1:Tidewing:StarlitCandy", "Starlit button feeds Starlit Candy: " .. tostring(last()[2]))
	local readySnap = snapshot({ message = "" })
	readySnap.depth.petDepth.upgrade.ready, readySnap.depth.petDepth.upgrade.remaining = true, 0
	ui.update.OnClientEvent:Fire(readySnap)
	visit(ui, "Hero", "Pets")
	assert(find(ui.scroll, "PetCancelButton") == nil and find(ui.scroll, "PetCancelConfirm") == nil, "no Cancel once the Roost job is ready")
	assert(find(ui.scroll, "PetClaimButton") ~= nil, "Claim shown when ready")
	noFailures(ui, "pets roost buttons")
	checks += 7
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
		CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberRange = roblox.NumberRange,
		TweenInfo = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end }, RaycastParams = { new = function() return {} end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		require = function(target) assert(target.Name == "AetherData", "unexpected require"); return Data end,
		task = { spawn = function(fn, ...) local co = coroutine.create(fn); assert(coroutine.resume(co, ...)) end,
			delay = function(_, fn) table.insert(delayed, fn) end },
	}
	new("ModuleScript", { Name = "AetherData" }).Parent = replicated
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

-- 10. XP lamps hide the skills their quest excludes (server refuses them too).
do
	local snap = snapshot()
	for _, entry in ipairs(snap.journal.quests) do
		if entry.id == "SurveyorsOath" then entry.done, entry.ready = false, true end
	end
	local ui = run({ snapshot = snap })
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Journal", "Quests")
	press(find(ui.scroll, "QuestSurveyorsOathClaim"))
	assert(find(ui.scroll, "LampPicker") and find(ui.scroll, "LampMining"), "lamp picker offers ordinary skills")
	for _, skill in ipairs(Data.QuestById.SurveyorsOath.rewards.lamp.exclude or {}) do
		assert(find(ui.scroll, "Lamp" .. skill) == nil, "excluded lamp skill hidden: " .. skill)
		checks += 1
	end
	press(find(ui.scroll, "LampMining"))
	assert(ui.sent[#ui.sent][2] == "SurveyorsOath:Mining", "lamp claim payload")
	noFailures(ui, "lamp exclude")
	checks += 2
end

-- 11. Island placement: Construction → Island catalogue, build-mode hand-off and verb relay.
local islandChecks = checks
for _, size in ipairs({ roblox.Vector2.new(730, 303), roblox.Vector2.new(420, 600) }) do
	local ui = run({ size = size })
	local tag = " @" .. size.X
	local function expect(condition, label) assert(condition, label .. tag); checks += 1 end
	local function lastSent() return ui.sent[#ui.sent] end
	local function texts(object)
		local out = {}
		for _, child in ipairs(object:GetDescendants()) do
			if child.ClassName == "TextLabel" or child.ClassName == "TextButton" then table.insert(out, tostring(child.Text)) end
		end
		return table.concat(out, "\n")
	end
	ui.player:SetAttribute("IslandPlacements", "1:TimberFence:0:-8:0;4:TimberFence:1:-8:0;2:StonePath:2:-8:0")
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Journal", "Construction")
	expect(find(ui.scroll, "TerraceSummary") ~= nil and find(ui.scroll, "BuildModeIsland") ~= nil, "construction opens on the terrace with an Island switch")
	press(find(ui.scroll, "BuildModeIsland"))
	noFailures(ui, "island page" .. tag)
	expect(find(ui.scroll, "IslandSummary") ~= nil and find(ui.scroll, "TerraceSummary") == nil, "island page replaces the terrace page")
	expect(texts(find(ui.scroll, "IslandSummary")):find("3 / 120", 1, true) ~= nil, "placed count and cap shown")
	expect(texts(find(ui.scroll, "IslandSummary")):find("Bare Rock", 1, true) ~= nil, "island tier shown")
	expect(texts(find(ui.scroll, "IslandSummary")):find("100%", 1, true) ~= nil, "refund rule explained")
	for _, category in ipairs(Data.Island.Categories) do expect(find(ui.scroll, "PropCategory" .. category) ~= nil, category .. " filter button") end
	expect(find(ui.scroll, "PropTimberFence") ~= nil and find(ui.scroll, "PropBrassRailing") ~= nil, "fence catalogue")
	expect(find(ui.scroll, "PropStonePath") == nil, "catalogue filtered by category")
	expect(texts(find(ui.scroll, "PropTimberFence")):find("2 / 40", 1, true) ~= nil, "placed count per prop")
	expect(texts(find(ui.scroll, "PropTimberFence")):find("1×1 cells", 1, true) ~= nil, "footprint shown")
	-- Quick pick-up sends the newest placement of that prop.
	press(find(ui.scroll, "PropTimberFencePickup"))
	expect(lastSent()[1] == "pickup" and lastSent()[2] == "4", "pick up sends the newest placement id")
	expect(find(ui.scroll, "PropPicketFencePickup") == nil, "no pick-up for unplaced props")
	-- Gated plans do not start build mode.
	press(find(ui.scroll, "PropCategoryStatues"))
	expect(find(ui.scroll, "PropSkywhaleStatue") ~= nil and find(ui.scroll, "PropTimberFence") == nil, "category switch")
	local before = #ui.sent
	press(find(ui.scroll, "PropSkywhaleStatuePlace"))
	expect(ui.player:GetAttribute("IslandBuildRequest") == nil and ui.atlas.Visible and #ui.sent == before, "Carpentry gate keeps build mode closed")
	expect(texts(find(ui.scroll, "PropSkywhaleStatue")):find("✗", 1, true) ~= nil, "unmet level marked")
	-- Place starts build mode and closes the atlas.
	press(find(ui.scroll, "PropCategoryFences"))
	press(find(ui.scroll, "PropTimberFencePlace"))
	expect(not ui.atlas.Visible, "placing closes the atlas")
	expect(ui.player:GetAttribute("IslandBuildMode") == "place" and ui.player:GetAttribute("IslandBuildProp") == "TimberFence" and ui.player:GetAttribute("IslandBuildRequest") == 1, "place mode handed to the builder")
	expect(#ui.sent == before, "starting build mode sends nothing")
	visit(ui, "Journal", "Construction")
	expect(find(ui.scroll, "IslandSummary") ~= nil, "island mode remembered")
	press(find(ui.scroll, "IslandRemoveMode"))
	expect(ui.player:GetAttribute("IslandBuildMode") == "remove" and ui.player:GetAttribute("IslandBuildProp") == "" and ui.player:GetAttribute("IslandBuildRequest") == 2, "pick-up mode handed to the builder")
	-- The builder's requests are relayed as verbs.
	ui.player:SetAttribute("IslandPlaceRequest", "HedgeRow:-2:-3:1")
	ui.player:SetAttribute("IslandPlaceCount", 1)
	expect(lastSent()[1] == "place" and lastSent()[2] == "HedgeRow:-2:-3:1", "place request relayed")
	ui.player:SetAttribute("IslandPickupRequest", "7")
	ui.player:SetAttribute("IslandPickupCount", 1)
	expect(lastSent()[1] == "pickup" and lastSent()[2] == "7", "pickup request relayed")
	before = #ui.sent
	ui.player:SetAttribute("IslandPlaceRequest", ("x"):rep(60))
	ui.player:SetAttribute("IslandPlaceCount", 2)
	ui.player:SetAttribute("IslandPickupRequest", "seven")
	ui.player:SetAttribute("IslandPickupCount", 2)
	ui.player:SetAttribute("IslandPickupRequest", 7)
	ui.player:SetAttribute("IslandPickupCount", 3)
	expect(#ui.sent == before, "malformed builder requests are dropped")
	visit(ui, "Journal", "Construction")
	press(find(ui.scroll, "BuildModeTerrace"))
	expect(find(ui.scroll, "TerraceSummary") ~= nil, "switch back to the terrace")
	checkSent(ui)
	noFailures(ui, "island flow" .. tag)
end
do
	-- Full island and maxed props disable Place; malformed island state still draws.
	local snap = snapshot()
	snap.journal.construction.island = { count = 120, cap = 120, counts = { TimberFence = 40 }, value = 600, tierName = "Legendary Isle" }
	local ui = run({ snapshot = snap })
	press(find(ui.gui, "AtlasButton"))
	visit(ui, "Journal", "Construction")
	press(find(ui.scroll, "BuildModeIsland"))
	press(find(ui.scroll, "PropTimberFencePlace"))
	press(find(ui.scroll, "PropPicketFencePlace"))
	assert(ui.player:GetAttribute("IslandBuildRequest") == nil and ui.atlas.Visible, "maxed prop and full island keep build mode closed")
	local summary = find(ui.scroll, "IslandSummary")
	local joined = {}
	for _, child in ipairs(summary:GetDescendants()) do if child.ClassName == "TextLabel" then table.insert(joined, tostring(child.Text)) end end
	assert(table.concat(joined, " "):find("Highest island tier", 1, true), "top tier progress shown")
	noFailures(ui, "full island")
	local bad = run({ snapshot = snapshot({ malformed = true }) })
	bad.player:SetAttribute("IslandPlacements", "junk;1:Nope:0:0:0;;3")
	press(find(bad.gui, "AtlasButton"))
	visit(bad, "Journal", "Construction")
	press(find(bad.scroll, "BuildModeIsland"))
	assert(find(bad.scroll, "IslandSummary") ~= nil, "malformed island state still draws")
	for _, category in ipairs(Data.Island.Categories) do
		press(find(bad.scroll, "PropCategory" .. category))
		noFailures(bad, "malformed island " .. category)
	end
	local none = run({ snapshot = snapshot({ noJournal = true }) })
	press(find(none.gui, "AtlasButton"))
	visit(none, "Journal", "Construction")
	press(find(none.scroll, "BuildModeIsland"))
	noFailures(none, "island without journal")
	checks += 4 + #Data.Island.Categories
end

-- 12. IslandBuilder (build.client.lua): ghost snapping, tint, rotate, confirm, cancel, gamepad, pick-up.
do
	local I = Data.Island
	local V3 = roblox.Vector3
	local playerGui = new("PlayerGui")
	local player = new("Player", { Name = "Tester", UserId = 1 })
	playerGui.Parent = player
	local replicated = new("ReplicatedStorage")
	local dataModule = new("ModuleScript", { Name = "AetherData" })
	dataModule.Parent = replicated
	local workspace = new("Workspace")
	local camera = new("Camera", { ViewportSize = roblox.Vector2.new(800, 600) })
	camera.Parent = workspace
	workspace.CurrentCamera = camera
	camera.ViewportPointToRay = function(_, x, y) return { Origin = V3.new(x, 50, y), Direction = V3.new(0, -1, 0) } end
	local hit = nil
	workspace.Raycast = function() return hit end
	local bound = {}
	local actions = { BindActionAtPriority = function(_, name, fn, _, _, ...) bound[name] = { fn = fn, keys = { ... } } end,
		UnbindAction = function(_, name) bound[name] = nil end }
	local input = new("UserInputService", { MouseEnabled = true, GamepadEnabled = false, TouchEnabled = false })
	local runService = new("RunService")
	local services = { Players = new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated, UserInputService = input,
		RunService = runService, ContextActionService = actions }
	local game = new("DataModel")
	function game.GetService(_, name) return assert(services[name], name) end
	local env = {
		game = game, workspace = workspace, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, RaycastParams = { new = function() return {} end },
		Instance = { new = function(class) return new(class) end },
		typeof = function(value) return if data[value] then "Instance" else typeof(value) end,
		require = function(target) assert(target == dataModule, "builder requires only AetherData") return Data end,
	}
	luau.load(fs.readFile("build.client.lua"), { debugName = "build.client.lua", environment = env, injectGlobals = true })()
	local function expect(condition, label) assert(condition, label); checks += 1 end
	local gui = playerGui:FindFirstChild("IslandBuilder")
	expect(gui ~= nil and gui.Enabled == false, "builder HUD starts hidden")
	local center = V3.new(-130, 0, 320)
	player:SetAttribute("IslandCenter", center)
	player:SetAttribute("IslandPlacements", "")
	local function aimAt(x, z, prop, rot)
		local ox, oz = I.centerOffset(prop or "StonePath", x, z, rot or 0)
		hit = { Position = center + V3.new(ox + .3, 0, oz - .3), Instance = workspace }
	end
	local function request(mode, prop)
		player:SetAttribute("IslandBuildMode", mode)
		player:SetAttribute("IslandBuildProp", prop or "")
		player:SetAttribute("IslandBuildRequest", (player:GetAttribute("IslandBuildRequest") or 0) + 1)
	end
	local function key(code, processed, inputType, position)
		input.InputBegan:Fire({ KeyCode = code, UserInputType = inputType or roblox.Enum.UserInputType.Keyboard, Position = position or V3.new(0, 0, 0) }, processed == true)
	end
	local function button(name) return find(gui, name) end
	local status = find(gui, "Status")
	local good, bad = roblox.Color3.fromHex("6BE0A8"), roblox.Color3.fromHex("E8806A")
	-- A free 2x1 spot that stays free when turned about the same pointer.
	local fx, fz
	for z = -I.RANGE, I.RANGE do for x = -I.RANGE, I.RANGE do
		local ox, oz = I.centerOffset("HedgeRow", x, z, 0)
		local tx, tz = I.snap("HedgeRow", 1, ox + .3, oz - .3)
		if not fx and I.check({}, "HedgeRow", x, z, 0) and I.check({}, "HedgeRow", tx, tz, 1) then fx, fz = x, z end
	end end
	aimAt(fx, fz, "HedgeRow", 0)
	request("place", "HedgeRow")
	local ghost = workspace:FindFirstChild("IslandGhost")
	expect(gui.Enabled and ghost ~= nil, "place request enters build mode with a ghost")
	expect(find(gui, "PropName").Text:find("Hedge Row", 1, true) ~= nil, "HUD names the prop")
	expect(button("RotateButton") and button("ConfirmButton") and button("CancelButton"), "touch buttons present")
	expect(bound.AetherIslandBuild ~= nil and #bound.AetherIslandBuild.keys == 3, "gamepad A/B/RB bound while building")
	local slab = ghost:FindFirstChild("Footprint")
	expect(slab.Color == good and status.TextColor3 == good, "valid spot tints green")
	for _, p in ipairs(ghost:GetChildren()) do expect(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch, "ghost part is inert: " .. p.Name) end
	local ox, oz = I.centerOffset("HedgeRow", fx, fz, 0)
	expect((slab.CFrame.Position - (center + V3.new(ox, .08, oz))).Magnitude < 1e-3, "ghost snaps to the grid cell")
	expect(slab.Size.X > 3.8 and slab.Size.Z < 2, "ghost matches the footprint")
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPlaceRequest") == "HedgeRow:" .. fx .. ":" .. fz .. ":0" and player:GetAttribute("IslandPlaceCount") == 1, "confirm hands back the placement")
	key(roblox.Enum.KeyCode.R)
	press(button("ConfirmButton"))
	local rx, rz = I.snap("HedgeRow", 1, hit.Position.X - center.X, hit.Position.Z - center.Z)
	expect(player:GetAttribute("IslandPlaceRequest") == "HedgeRow:" .. rx .. ":" .. rz .. ":1", "R rotates the prop around the pointer")
	local rotated = slab.CFrame
	expect(math.abs(rotated.LookVector.X) > .99, "ghost turns with the rotation")
	press(button("RotateButton")); press(button("RotateButton")); press(button("RotateButton"))
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPlaceRequest"):sub(-2) == ":0" and player:GetAttribute("IslandPlaceCount") == 3, "rotation wraps 0-3")
	key(roblox.Enum.KeyCode.R, true)
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPlaceRequest"):sub(-2) == ":0", "keys typed into a textbox are ignored")
	-- Invalid spots tint red and never confirm.
	aimAt(0, 2)
	runService.RenderStepped:Fire()
	expect(slab.Color == bad and status.Text:find("home landing", 1, true) ~= nil, "protected zone tints red with a reason")
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPlaceCount") == 4, "invalid confirm sends nothing")
	aimAt(8, 8)
	runService.RenderStepped:Fire()
	expect(slab.Color == bad, "rim tints red")
	aimAt(fx, fz, "HedgeRow", 0)
	player:SetAttribute("IslandPlacements", "1:StonePath:" .. fx .. ":" .. fz .. ":0")
	expect(slab.Color == bad and status.Text:find("already", 1, true) ~= nil, "occupied cell tints red after replication")
	player:SetAttribute("IslandPlacements", "")
	expect(slab.Color == good, "freed cell tints green again")
	hit = nil
	runService.RenderStepped:Fire()
	expect(status.Text:find("Aim", 1, true) ~= nil and ghost.Parent == nil, "aiming off the island hides the ghost")
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPlaceCount") == 4, "no target, no placement")
	-- Mouse click places at the pointer; clicks on GUI are ignored.
	aimAt(fx, fz, "HedgeRow", 0)
	key(nil, false, roblox.Enum.UserInputType.MouseButton1, V3.new(400, 300, 0))
	expect(player:GetAttribute("IslandPlaceCount") == 5 and ghost.Parent == workspace, "mouse click places")
	key(nil, true, roblox.Enum.UserInputType.MouseButton1, V3.new(400, 300, 0))
	expect(player:GetAttribute("IslandPlaceCount") == 5, "click on the HUD does not place")
	-- Gamepad: RB rotates, A confirms (sunk), B leaves.
	local action = bound.AetherIslandBuild.fn
	local begin = roblox.Enum.UserInputState.Begin
	expect(action("x", begin, { KeyCode = roblox.Enum.KeyCode.ButtonR1 }) == roblox.Enum.ContextActionResult.Sink, "gamepad input is sunk")
	action("x", begin, { KeyCode = roblox.Enum.KeyCode.ButtonA })
	expect(player:GetAttribute("IslandPlaceRequest"):sub(-2) == ":1" and player:GetAttribute("IslandPlaceCount") == 6, "gamepad RB rotates and A places")
	action("x", begin, { KeyCode = roblox.Enum.KeyCode.ButtonB })
	expect(not gui.Enabled and workspace:FindFirstChild("IslandGhost") == nil and bound.AetherIslandBuild == nil, "gamepad B leaves build mode cleanly")
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPlaceCount") == 6, "inactive builder ignores confirm")
	-- Max count from replicated placements.
	local sx, sz
	for z = -I.RANGE, I.RANGE do for x = -I.RANGE, I.RANGE do
		if not sx and I.check({}, "CarpenterStump", x, z, 0) and (x ~= fx or z ~= fz) then sx, sz = x, z end
	end end
	player:SetAttribute("IslandPlacements", "1:CarpenterStump:" .. fx .. ":" .. fz .. ":0")
	aimAt(sx, sz, "CarpenterStump", 0)
	request("place", "CarpenterStump")
	expect(status.Text:find("Most", 1, true) ~= nil and workspace:FindFirstChild("IslandGhost"):FindFirstChild("Footprint").Color == bad, "per-prop max shown before placing")
	key(roblox.Enum.KeyCode.Escape)
	expect(not gui.Enabled and workspace:FindFirstChild("IslandGhost") == nil, "Esc leaves build mode")
	-- Starting a new session replaces the old ghost; unknown props are refused.
	request("place", "Nope")
	expect(not gui.Enabled and workspace:FindFirstChild("IslandGhost") == nil, "unknown prop does not enter build mode")
	request("place", "StonePath")
	request("place", "LanternPost")
	local ghosts = 0
	for _, child in ipairs(workspace:GetChildren()) do if child.Name == "IslandGhost" then ghosts += 1 end end
	expect(ghosts == 1 and find(gui, "PropName").Text:find("Lantern", 1, true) ~= nil, "one ghost per session")
	player.CharacterRemoving:Fire()
	expect(not gui.Enabled and workspace:FindFirstChild("IslandGhost") == nil, "respawning leaves build mode")
	-- Pick-up mode targets only this player's placed props.
	local isles = new("Folder", { Name = "AetherIsles" }); isles.Parent = workspace
	local home = new("Model", { Name = "WayfarersRest_1" }); home.Parent = isles
	local folder = new("Folder", { Name = "Placements" }); folder.Parent = home
	local placed = new("Model", { Name = "Placement_3" }); placed.Parent = folder
	placed:SetAttribute("PlacementId", 3); placed:SetAttribute("PropId", "StonePath")
	local stone = new("Part", { Name = "Flagstone" }); stone.Parent = placed
	local other = new("Model", { Name = "Placement_9" }); other.Parent = new("Folder", { Name = "Placements" })
	other:SetAttribute("PlacementId", 9)
	local otherPart = new("Part"); otherPart.Parent = other
	hit = { Position = center, Instance = stone }
	request("remove")
	expect(gui.Enabled and workspace:FindFirstChild("IslandGhost") == nil and find(gui, "ConfirmButton").Text == "Pick up", "pick-up mode has no ghost")
	expect(placed:FindFirstChild("PickupHighlight") ~= nil and status.Text:find("Stone Path", 1, true) ~= nil, "targeted prop highlighted")
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPickupRequest") == "3" and player:GetAttribute("IslandPickupCount") == 1, "pick-up hands back the placement id")
	hit = { Position = center, Instance = otherPart }
	runService.RenderStepped:Fire()
	expect(placed:FindFirstChild("PickupHighlight") == nil and other:FindFirstChild("PickupHighlight") == nil, "another island's prop cannot be targeted")
	press(button("ConfirmButton"))
	expect(player:GetAttribute("IslandPickupCount") == 1, "no target, no pick-up")
	press(button("CancelButton"))
	expect(not gui.Enabled, "Done leaves pick-up mode")
	request("demolish")
	expect(not gui.Enabled, "unknown mode ignored")
end
print("Island builder UI: " .. (checks - islandChecks) .. " checks.")

-- 12. One HUD, no collisions: every HUD-producing client script (atlas, combat,
-- Wayfinder, townsfolk dialogue/tracker, island builder) loaded together at
-- phone-compact, phone and desktop sizes. Pairwise, nothing overlaps: atlas guild
-- badge, minimap, combat target and boss panels, event banner, tutorial tracker,
-- Wayfinder toast, action bar and Attack button; builder controls while building
-- (Attack hides); the dialogue box while talking (with 3+ options, clamped on
-- screen, the tracker tucked away).
local hudChecks = checks
do
	local H = require("./tools/ui-harness")
	local function signal()
		local handlers = {}
		return {
			Connect = function(_, fn) table.insert(handlers, fn); return { Disconnect = function() end } end,
			Once = function(self, fn) return self:Connect(fn) end,
			Fire = function(_, ...) for _, fn in ipairs(table.clone(handlers)) do fn(...) end end,
		}
	end
	local function baseTask()
		return {
			spawn = function(fn, ...) local co = coroutine.create(fn); local ok, problem = coroutine.resume(co, ...); assert(ok, problem); return co end,
			delay = function() end, defer = function(fn, ...) fn(...) end, wait = function() return coroutine.yield() end,
		}
	end
	-- nav.client.lua / npc.client.lua for an existing player (harness instances).
	local function runClient(path, size, player, extra)
		local replicated = H.new("ReplicatedStorage")
		H.new("ModuleScript", { Name = "AetherData" }).Parent = replicated
		local action = H.new("RemoteFunction", { Name = "IsleAction" })
		action.OnInvoke = function() return H.snapshot() end
		action.Parent = replicated
		H.new("RemoteEvent", { Name = "IsleUpdate" }).Parent = replicated
		local camera = H.new("Camera", { ViewportSize = size })
		local workspace = {
			CurrentCamera = camera, DescendantAdded = signal(), DescendantRemoving = signal(), ChildAdded = signal(), ChildRemoved = signal(),
			GetDescendants = function() return (extra and extra.descendants) or {} end, FindFirstChild = function() return nil end,
			GetAttribute = function() return nil end, GetAttributeChangedSignal = function() return signal() end,
			WaitForChild = function(_, name)
				if name == "Townsfolk" then return { ChildAdded = signal(), ChildRemoved = signal(), GetChildren = function() return {} end } end
				return nil
			end,
		}
		local services = {
			Players = H.new("Players", { LocalPlayer = player }), ReplicatedStorage = replicated, RunService = H.new("RunService"),
			UserInputService = H.new("UserInputService", { TouchEnabled = true }), TweenService = H.new("TweenService"),
			ProximityPromptService = { PromptTriggered = (extra and extra.promptTriggered) or signal() },
		}
		local game = H.new("DataModel")
		function game.GetService(_, name) return assert(services[name], name) end
		local env = {
			game = game, workspace = workspace, Enum = roblox.Enum, UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
			Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			TweenInfo = { new = function() return {} end },
			Instance = { new = function(class)
				local object = H.new(class)
				if class == "BindableEvent" then object.Event = signal() end
				return object
			end },
			require = function() return H.Data end, task = baseTask(),
		}
		local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env, injectGlobals = true })
		local co = coroutine.create(chunk)
		local ok, problem = coroutine.resume(co)
		assert(ok, problem)
	end
	-- Absolute rectangle of a GuiObject (ScreenGuis all keep the topbar inset, so
	-- they share one coordinate space).
	local function rectOf(object, size)
		local chain = {}
		local node = object
		while node and node.ClassName ~= "ScreenGui" do table.insert(chain, 1, node); node = node.Parent end
		local x, y, w, h = 0, 0, size.X, size.Y
		for _, item in ipairs(chain) do
			local s, p, a = item.Size, item.Position, item.AnchorPoint or roblox.Vector2.zero
			local cw, ch = s.X.Scale * w + s.X.Offset, s.Y.Scale * h + s.Y.Offset
			local limit = item:FindFirstChildOfClass("UISizeConstraint")
			if limit then cw, ch = math.min(cw, limit.MaxSize.X), math.min(ch, limit.MaxSize.Y) end
			x, y = x + p.X.Scale * w + p.X.Offset - a.X * cw, y + p.Y.Scale * h + p.Y.Offset - a.Y * ch
			w, h = cw, ch
		end
		return { x = x, y = y, w = w, h = h }
	end
	local function overlaps(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end
	local function show(r) return string.format("(%d,%d %dx%d)", r.x, r.y, r.w, r.h) end
	local function noOverlap(items, tag)
		for i = 1, #items do
			local a = items[i]
			assert(a[2].x >= 0 and a[2].y >= 0 and a[2].x + a[2].w <= tag.size.X + 0.5 and a[2].y + a[2].h <= tag.size.Y + 0.5,
				a[1] .. " stays on screen at " .. tag.name .. " " .. show(a[2]))
			checks += 1
			for j = i + 1, #items do
				local b = items[j]
				assert(not overlaps(a[2], b[2]), a[1] .. " " .. show(a[2]) .. " overlaps " .. b[1] .. " " .. show(b[2]) .. " at " .. tag.name)
				checks += 1
			end
		end
	end
	for _, size in ipairs({ roblox.Vector2.new(730, 303), roblox.Vector2.new(844, 390), roblox.Vector2.new(1366, 768) }) do
		local tag = { size = size, name = size.X .. "x" .. size.Y }
		local ui = H.runAtlas(size)
		local player, playerGui = ui.player, ui.playerGui
		local combat = H.runCombat(size, player, ui.replicated)
		runClient("nav.client.lua", size, player)
		local prompts = signal()
		runClient("npc.client.lua", size, player, { promptTriggered = prompts })
		local builder = H.runBuilder(size, player)
		local atlas = playerGui:FindFirstChild("AetherAtlas")
		local wayfinder = playerGui:FindFirstChild("Wayfinder")
		local townsfolk = playerGui:FindFirstChild("TownsfolkDialogue")
		local hud = combat.hud
		local function rect(object) assert(object, "HUD element exists at " .. tag.name); return rectOf(object, size) end
		local banner
		for _, child in ipairs(hud:GetChildren()) do if child.ClassName == "TextLabel" then banner = child end end
		local panel = hud:FindFirstChild("Target")
		local targetRect = rect(panel)
		-- The boss panel (wider) through the owner scan.
		local monster = combat.monster
		monster:SetAttribute("Health", 50); monster:SetAttribute("MaxHealth", 100)
		monster:SetAttribute("Boss", true); monster:SetAttribute("OwnerUserId", player.UserId)
		table.insert(combat.tagged, monster)
		combat.run.RenderStepped:Fire()
		assert(panel.Visible, "boss panel shows at " .. tag.name)
		local bossRect = rect(panel)
		local tracker = townsfolk:FindFirstChild("TutorialTracker")
		tracker.Visible = true -- measured whether or not this snapshot's tutorial is finished
		-- Agility & Hunter HUD: a lap underway and two traps (one caught) under the tutorial tracker.
		H.agilityHud(player)
		local lapTracker, trapCounter = atlas:FindFirstChild("CourseTracker"), atlas:FindFirstChild("TrapTracker")
		assert(lapTracker.Visible and trapCounter.Visible, "lap tracker and trap counter show at " .. tag.name)
		local attack = hud:FindFirstChild("AttackButton")
		-- Spell bar (style chip + six slots for this magic snapshot) above the action bar.
		local spellBar = hud:FindFirstChild("SpellBar")
		local shownSlots = 0
		for i = 1, 6 do if spellBar:FindFirstChild("Spell" .. i).Visible then shownSlots += 1 end end
		assert(spellBar.Visible and shownSlots == 6, "spell bar shows six slots at " .. tag.name .. " (" .. shownSlots .. ")")
		local spellRect = rect(spellBar)
		assert(spellRect.w >= 40 * 7, "spell bar width holds the chip and slots at " .. tag.name)
		-- Prayer quick bar (combat.client.lua): published points, a protection prayer on.
		player:SetAttribute("PrayerLevel", 45)
		player:SetAttribute("PrayerMax", 55)
		player:SetAttribute("PrayerPoints", 30)
		player:SetAttribute("PrayerQuick", "StonehideWard,BlazingEdge")
		player:SetAttribute("PrayerActive", "WardOfFangs")
		local prayerBar = hud:FindFirstChild("PrayerBar")
		assert(prayerBar and prayerBar.Visible, "prayer quick bar shows at " .. tag.name)
		local prayerRect = rect(prayerBar)
		local shownPrayers = 0
		for i = 1, 5 do if prayerBar:FindFirstChild("Prayer" .. i):FindFirstChild("Glyph").Text ~= "" then shownPrayers += 1 end end
		assert(shownPrayers == 5 and prayerBar:FindFirstChild("Prayer1"):FindFirstChild("On").Visible, "three wards and two favourites, Ward of Fangs lit at " .. tag.name)
		assert(prayerBar:FindFirstChild("Points"):FindFirstChild("Count").Text == "30", "prayer gauge shows the points at " .. tag.name)
		assert(prayerRect.y + prayerRect.h <= spellRect.y and prayerRect.x + prayerRect.w <= spellRect.x + spellRect.w + 0.5, "prayer bar sits above the spell bar at " .. tag.name)
		assert(player:GetAttribute("IsleHudLift") == spellRect.h + 6 + prayerRect.h + 6, "toasts lift above the spell and prayer bars at " .. tag.name)
		checks += 4
		local persistent = {
			{ "atlas badge", rect(atlas:FindFirstChild("GuildBadge")) },
			{ "minimap", rect(wayfinder:FindFirstChild("Minimap")) },
			{ "action bar", rect(atlas:FindFirstChild("ActionBar")) },
		}
		local explore = table.clone(persistent)
		for _, item in ipairs({ { "event banner", rect(banner) }, { "tutorial tracker", rect(tracker) },
			{ "wayfinder toast", rect(wayfinder:FindFirstChild("WayfinderToast")) }, { "attack button", rect(attack) }, { "spell bar", spellRect },
			{ "lap tracker", rect(lapTracker) }, { "trap counter", rect(trapCounter) }, { "prayer bar", prayerRect } }) do
			table.insert(explore, item)
		end
		noOverlap(table.move({ { "target panel", targetRect } }, 1, 1, #explore + 1, table.clone(explore)), tag)
		noOverlap(table.move({ { "boss panel", bossRect } }, 1, 1, #explore + 1, table.clone(explore)), tag)
		-- Building: the builder owns the bottom; Attack steps aside.
		assert(attack.Visible, "Attack shows outside the builder at " .. tag.name)
		builder.enter("place", "StonePath")
		local bar = playerGui:FindFirstChild("IslandBuilder")
		assert(bar.Enabled and not attack.Visible, "Attack hides while the island builder runs at " .. tag.name)
		assert(not spellBar.Visible and player:GetAttribute("IsleHudLift") == 0, "spell bar hides while building at " .. tag.name)
		local building = {}
		for _, item in ipairs(explore) do if item[1] ~= "attack button" and item[1] ~= "spell bar" and item[1] ~= "lap tracker" and item[1] ~= "trap counter" and item[1] ~= "prayer bar" then table.insert(building, item) end end
		assert(not prayerBar.Visible, "prayer bar hides while building at " .. tag.name)
		assert(not lapTracker.Visible and not trapCounter.Visible, "lap tracker and trap counter step aside for the builder at " .. tag.name)
		table.insert(building, { "builder controls", rect(bar:FindFirstChild("BuildBar")) })
		table.insert(building, { "boss panel", bossRect })
		noOverlap(building, tag)
		player:SetAttribute("IslandBuilding", nil)
		assert(attack.Visible and spellBar.Visible and prayerBar.Visible, "Attack, the spell bar and the prayer bar return after building at " .. tag.name)
		assert(lapTracker.Visible and trapCounter.Visible, "lap tracker and trap counter return after building at " .. tag.name)
		-- Talking: Pell's opening node has 4+ options.
		local promptDouble = { GetAttribute = function(_, key) return if key == "TownsfolkRole" then "Guide" else nil end,
			FindFirstAncestorOfClass = function() return nil end }
		prompts:Fire(promptDouble, player)
		local dialogue = townsfolk:FindFirstChild("Dialogue")
		local options = dialogue:FindFirstChild("Options")
		local buttons = 0
		for _, child in ipairs(options:GetChildren()) do if child.ClassName == "TextButton" then buttons += 1 end end
		assert(dialogue.Visible and buttons >= 3, "dialogue open with " .. buttons .. " options at " .. tag.name)
		assert(not tracker.Visible, "tutorial tracker tucks away while talking at " .. tag.name)
		-- The dialogue owns the bottom: the spell bar steps aside on the next HUD scan.
		combat.run.RenderStepped:Fire()
		assert(not spellBar.Visible and not prayerBar.Visible, "spell and prayer bars hide while talking at " .. tag.name)
		local boxRect = rect(dialogue)
		local talking = table.clone(persistent)
		table.insert(talking, { "attack button", rect(attack) })
		table.insert(talking, { "dialogue box", boxRect })
		noOverlap(talking, tag)
		-- Portrait, name and close button inside the box; options scroll in what is left.
		for _, name in ipairs({ "Portrait" }) do
			local r = rect(dialogue:FindFirstChild(name))
			assert(r.y >= boxRect.y and r.y + r.h <= boxRect.y + boxRect.h, name .. " inside the dialogue at " .. tag.name)
		end
		local closeRect
		for _, child in ipairs(dialogue:GetChildren()) do if child.ClassName == "TextButton" and child.Text == "✕" then closeRect = rect(child) end end
		assert(closeRect and closeRect.y >= boxRect.y and closeRect.x + closeRect.w <= boxRect.x + boxRect.w and closeRect.y >= 0, "close button reachable at " .. tag.name)
		local optionsRect = rect(options)
		assert(optionsRect.h >= 36 and optionsRect.y + optionsRect.h <= boxRect.y + boxRect.h + 0.5, "options area holds a row and scrolls at " .. tag.name .. " " .. show(optionsRect))
		assert(options.ClassName == "ScrollingFrame", "options scroll")
		-- Navigate list: clamped above the action bar.
		local navigate = wayfinder:FindFirstChild("Navigate")
		local go
		for _, child in ipairs(wayfinder:FindFirstChild("Minimap"):FindFirstChild("Controls"):GetChildren()) do if child.Text == "Go" then go = child end end
		go.Activated:Fire()
		local listRect = rect(navigate)
		assert(navigate.Visible and listRect.y >= 0 and listRect.y + listRect.h <= size.Y - 40 and listRect.h >= 120,
			"navigate list fits above the action bar at " .. tag.name .. " " .. show(listRect))
		assert(not overlaps(listRect, rect(wayfinder:FindFirstChild("Minimap"))), "navigate list clears the minimap at " .. tag.name)
		-- Endgame World Boss HUD: the boss bar takes the target panel's top-lane
		-- slot and the damage board sits under the minimap (tall screens only);
		-- both clear every exploring HUD element, and the loot card stays on screen.
		combat.fx.OnClientEvent:Fire("worldBoss", { id = "Aurelith", name = "Aurelith, the Shattered Sovereign", level = 120, hp = 1500000, maxHp = 3000000,
			phase = 2, phases = 3, phaseName = "Fractured", enraged = false, enrageIn = 200, departIn = 400, warded = true, fighters = 6,
			top = { { name = "Ysolde", damage = 900000, share = 0.3 }, { name = "Tester", damage = 300000, share = 0.1, you = true },
				{ name = "Wren", damage = 60000, share = 0.02 }, { name = "Orrin", damage = 30000, share = 0.01 }, { name = "Pell", damage = 20000, share = 0.0067 } },
			you = { rank = 2, damage = 300000, share = 0.1, tier = "Vanguard" } })
		combat.run.RenderStepped:Fire()
		local wbBar, wbBoard = hud:FindFirstChild("WorldBossBar"), hud:FindFirstChild("WorldBossBoard")
		assert(wbBar and wbBar.Visible and not panel.Visible, "world boss bar replaces the target panel at " .. tag.name)
		assert(H.find(wbBar, "Title").Text:find("Phase 2/3", 1, true) and H.find(wbBar, "Rank").Text:find("#2", 1, true), "boss bar shows phase and your rank at " .. tag.name)
		assert(H.find(wbBar, "Enrage").Text:find("Enrage", 1, true) and H.find(wbBar, "Health").Text:find("WARDED", 1, true), "boss bar shows enrage timer and ward at " .. tag.name)
		local fighting = { { "world boss bar", rect(wbBar) } }
		for _, item in ipairs(explore) do table.insert(fighting, item) end
		if size.Y >= 520 then
			assert(wbBoard.Visible and H.find(wbBoard, "Row1").Text:find("Ysolde", 1, true), "damage board lists the leader at " .. tag.name)
			table.insert(fighting, { "damage board", rect(wbBoard) })
		else
			assert(not wbBoard.Visible and H.find(wbBar, "Rank").Text:find("Ysolde", 1, true), "compact screens fold the leader into the bar at " .. tag.name)
		end
		noOverlap(fighting, tag)
		combat.fx.OnClientEvent:Fire("worldBossLoot", { id = "Aurelith", name = "Aurelith", eligible = true, rank = 2, share = 0.1, tier = "Vanguard",
			coins = 25000, drops = { SovereignEssence = 8, CrownShard = 22, SovereignCrest = 1 } })
		local lootCard = hud:FindFirstChild("WorldBossLoot")
		local lootRect = rect(lootCard)
		assert(lootCard.Visible and lootRect.x >= 0 and lootRect.y >= 0 and lootRect.x + lootRect.w <= size.X and lootRect.y + lootRect.h <= size.Y,
			"loot summary fits the screen at " .. tag.name .. " " .. show(lootRect))
		assert(H.find(lootCard, "Items").Text:find("Sovereign Crest", 1, true) and H.find(lootCard, "Standing").Text:find("Vanguard", 1, true), "loot summary lists drops and tier at " .. tag.name)
		-- Renders on each payload and a 1 Hz timer, not every frame.
		local title = H.find(wbBar, "Title")
		local function payload(phase)
			combat.fx.OnClientEvent:Fire("worldBoss", { id = "Aurelith", name = "Aurelith, the Shattered Sovereign", level = 120, hp = 1400000, maxHp = 3000000,
				phase = phase, phases = 3, phaseName = "Fractured", enraged = false, enrageIn = 199, departIn = 399, warded = false, fighters = 6, top = {}, you = nil })
		end
		payload(2)
		assert(title.Text:find("Phase 2/3", 1, true), "a payload renders at once at " .. tag.name)
		title.Text = "stale"
		combat.run.RenderStepped:Fire()
		assert(title.Text == "stale", "boss bar does not re-render every frame at " .. tag.name)
		payload(3)
		assert(title.Text:find("Phase 3/3", 1, true), "the next payload renders at once at " .. tag.name)
		-- Another boss falling (both up) leaves this HUD alone; its own fall clears it.
		combat.fx.OnClientEvent:Fire("worldBossAnnounce", { kind = "depart", id = "Nyxwyrm", name = "Nyxwyrm" })
		assert(wbBar.Visible, "another boss's departure keeps the HUD at " .. tag.name)
		combat.fx.OnClientEvent:Fire("worldBossAnnounce", { kind = "win", id = "Aurelith", name = "Aurelith" })
		assert(not wbBar.Visible and not wbBoard.Visible, "boss HUD clears when the boss falls at " .. tag.name)
		checks += 12
		checks += 12
	end
	-- Wayfinder (nav.client.lua) for Agility & Hunter: the running lap's next
	-- obstacle gets a Highlight + billboard and AgilityNextAt; own traps get
	-- caught / collapsed billboards, a toast and HunterTrapsCollapsed.
	do
		local size = roblox.Vector2.new(1366, 768)
		local ui = H.runAtlas(size)
		local player = ui.player
		local function promptAt(attrs, position)
			local host = H.new("BasePart", { Name = "Host", Position = position })
			host.Parent = H.new("Model", { Name = "Ground" })
			local prompt = H.new("ProximityPrompt")
			for k, v in pairs(attrs) do prompt:SetAttribute(k, v) end
			prompt.Parent = host
			return prompt, host
		end
		local obstacle3, host3 = promptAt({ IsleAction = "agility", IsleItem = "QuayRigging:3", AgilityCourse = "QuayRigging", AgilityIndex = 3 }, roblox.Vector3.new(30, 12, 4))
		local obstacle4 = promptAt({ IsleAction = "agility", IsleItem = "QuayRigging:4", AgilityCourse = "QuayRigging", AgilityIndex = 4 }, roblox.Vector3.new(40, 12, 9))
		local snare, snareHost = promptAt({ IsleAction = "trap", IsleItem = "PuffcapHopper", HunterMethod = "snare" }, roblox.Vector3.new(5, 0, 5))
		local other, otherHost = promptAt({ IsleAction = "trap", IsleItem = "PuffcapHopper", HunterMethod = "snare" }, roblox.Vector3.new(8, 0, 5))
		runClient("nav.client.lua", size, player, { descendants = { obstacle3, obstacle4, snare, other } })
		local wayfinder = ui.playerGui:FindFirstChild("Wayfinder")
		local toast = wayfinder:FindFirstChild("WayfinderToast")
		player:SetAttribute("AgilityRunExpires", os.time() + 20)
		player:SetAttribute("AgilityRun", "QuayRigging:3:6")
		local highlight = host3:FindFirstChild("AgilityNext")
		assert(highlight and highlight.ClassName == "Highlight" and highlight.Adornee == host3, "next obstacle highlighted")
		local board = host3:FindFirstChild("AgilityNextBoard")
		assert(board and H.find(board, "Obstacle").Text == "Swing Rigging rope", "next obstacle billboard names the move")
		assert(player:GetAttribute("AgilityNextAt") == host3.Position, "AgilityNextAt feeds the HUD arrow")
		player:SetAttribute("AgilityRun", "QuayRigging:4:6")
		assert(host3:FindFirstChild("AgilityNext") == nil and obstacle4.Parent:FindFirstChild("AgilityNext") ~= nil, "highlight moves on to obstacle 4")
		player:SetAttribute("AgilityRun", "")
		assert(obstacle4.Parent:FindFirstChild("AgilityNext") == nil and player:GetAttribute("AgilityNextAt") == nil, "highlight clears with the lap")
		-- Own trap: set (quiet), caught (ping + toast), collapsed (notice + counter); others' traps ignored.
		snareHost:SetAttribute("TrapState", "set")
		snareHost:SetAttribute("TrapOwner", player.UserId)
		assert(H.find(snareHost:FindFirstChild("TrapPing"), "State").Text == "SET", "set trap marker")
		snareHost:SetAttribute("TrapState", "caught")
		local ping = snareHost:FindFirstChild("TrapPing")
		assert(ping and ping.AlwaysOnTop and H.find(ping, "State").Text == "CAUGHT!", "caught ping shows through the world")
		assert(toast.Visible and toast.Text:find("caught a Puffcap Hopper", 1, true), "caught toast")
		otherHost:SetAttribute("TrapState", "caught")
		otherHost:SetAttribute("TrapOwner", 99)
		assert(otherHost:FindFirstChild("TrapPing") == nil, "another hunter's trap shows no ping")
		snareHost:SetAttribute("TrapState", "collapsed")
		assert(H.find(snareHost:FindFirstChild("TrapPing"), "State").Text == "COLLAPSED" and toast.Text:find("collapsed", 1, true), "collapsed notice")
		assert(player:GetAttribute("HunterTrapsCollapsed") == 1, "collapsed count published for the atlas")
		player:SetAttribute("HunterTraps", "1/2")
		player:SetAttribute("HunterTrapsCaught", 0)
		local counter = ui.gui:FindFirstChild("TrapTracker")
		assert(counter.Visible and H.find(counter, "State").Text:find("collapsed", 1, true), "trap counter shows the collapsed trap")
		snareHost:SetAttribute("TrapState", "")
		snareHost:SetAttribute("TrapOwner", 0)
		assert(snareHost:FindFirstChild("TrapPing") == nil and player:GetAttribute("HunterTrapsCollapsed") == 0, "picked-up trap clears")
		-- Navigate list: the next obstacle is a target while a lap runs.
		player:SetAttribute("AgilityRun", "QuayRigging:3:6")
		local go
		for _, child in ipairs(wayfinder:FindFirstChild("Minimap"):FindFirstChild("Controls"):GetChildren()) do if child.Text == "Go" then go = child end end
		go.Activated:Fire()
		local found = false
		for _, object in ipairs(wayfinder:FindFirstChild("Navigate"):GetDescendants()) do
			if object.ClassName == "TextButton" and tostring(object.Text):find("Next obstacle", 1, true) then found = true end
		end
		assert(found, "Navigate lists the next obstacle")
		checks += 16
	end
end
print("HUD overlap: " .. (checks - hudChecks) .. " checks.")

-- 13. Combat styles client (combat.client.lua + atlas channels): the verb for the
-- wielded style, reach, spell bar slots / keys / greying, denied toasts, autocast
-- through the atlas, triangle damage tags, projectile / snare / heal / teleport FX,
-- gestures, and the Hero › Combat / Spellbook pages and item / bestiary details.
local styleChecks = checks
do
	local H = require("./tools/ui-harness")
	local size = roblox.Vector2.new(1366, 768)
	local function texts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(out, tostring(d.Text)) end
		end
		return table.concat(out, "\n")
	end
	-- Atlas + combat with a character 0 studs from the origin and a monster `distance` away.
	local function setup(weapon, distance)
		local ui = H.runAtlas(size, { snapshot = H.snapshot({ weapon = weapon }) })
		local player = ui.player
		local gestures = {}
		local gesture = H.new("BindableEvent", { Name = "IsleGestureLocal" })
		gesture.Event:Connect(function(name, target, item) table.insert(gestures, { name, target, item }) end)
		gesture.Parent = ui.replicated
		local character = H.new("Model", { Name = "Voyager" })
		H.new("Part", { Name = "HumanoidRootPart", Position = roblox.Vector3.new(0, 3, 0), CFrame = roblox.CFrame.new(0, 3, 0), Size = roblox.Vector3.new(2, 2, 1) }).Parent = character
		H.new("Humanoid", { Name = "Humanoid", Health = 100, MaxHealth = 100 }).Parent = character
		player.Character = character
		player:SetAttribute("Mana", 100)
		player:SetAttribute("MaxMana", 160)
		local c = H.runCombat(size, player, ui.replicated)
		local body = H.new("Part", { Name = "Body", Position = roblox.Vector3.new(0, 3, -(distance + 2)), Size = roblox.Vector3.new(4, 4, 4) })
		body.Parent = c.monster
		c.monster.PrimaryPart = body
		c.monster:SetAttribute("Health", 80)
		c.monster:SetAttribute("MaxHealth", 100)
		table.insert(c.tagged, c.monster)
		c.run.RenderStepped:Fire()
		c.ui, c.player, c.gestures = ui, player, gestures
		c.bar = c.hud:FindFirstChild("SpellBar")
		c.attack = c.hud:FindFirstChild("AttackButton")
		c.press = function() c.attack.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.Touch }) end
		c.key = function(code) c.input.InputBegan:Fire({ KeyCode = code, UserInputType = roblox.Enum.UserInputType.Keyboard }, false) end
		c.toast = function()
			local t = ui.gui:FindFirstChild("Toast")
			return t and t.Visible and t.Text or ""
		end
		return c
	end
	local function lastFired(c) local f = H.fired(c.remote); return f[#f] end
	local function slotIds(c)
		local ids = {}
		for i = 1, 6 do
			local b = c.bar:FindFirstChild("Spell" .. i)
			if b.Visible then table.insert(ids, b:FindFirstChild("Glyph").Text) end
		end
		return ids
	end

	-- Magic (Windpine Staff, Magic 30, autocast Gale Lance): cast at 30 studs.
	local m = setup("WindpineStaff", 30)
	assert(m.attack:FindFirstChild("Caption").Text == "CAST", "staff turns Attack into CAST")
	assert(#slotIds(m) == 6, "magic bar: autocast, two more damage spells, Rootbind, Mend, Hubward")
	assert(m.bar:FindFirstChild("Spell1"):FindFirstChild("Auto").Visible, "slot 1 marks the autocast")
	assert(m.bar:FindFirstChild("Spell1"):FindFirstChild("Key").Text == "1", "slot key hints")
	m.press()
	local f = lastFired(m)
	assert(f and f[1] == "cast" and f[2] == m.monster and f[3] == "GaleLance", "attack casts the autocast spell at the target")
	assert(m.gestures[#m.gestures][1] == "cast" and m.gestures[#m.gestures][3] == "WindpineStaff", "staff casts play the staff gesture tinted by the staff")
	-- Mend (slot 5) needs no target and casts with nil.
	m.key(roblox.Enum.KeyCode.Five)
	f = lastFired(m)
	assert(f[1] == "cast" and f[2] == nil and f[3] == "Mend", "key 5 casts Mend on yourself")
	assert(m.gestures[#m.gestures][1] == "heal", "Mend plays the heal gesture")
	-- Utility cooldown: an immediate second Mend is held back locally.
	local before = #H.fired(m.remote)
	m.key(roblox.Enum.KeyCode.Five)
	assert(#H.fired(m.remote) == before, "Mend's cooldown blocks a repeat")
	m.run.RenderStepped:Fire()
	assert(m.bar:FindFirstChild("Spell5"):FindFirstChild("Sweep").Size.Y.Scale > 0.9, "cooldown sweep covers a fresh Mend")
	-- Out of mana: greyed slot and a toast instead of a send.
	m.fx.OnClientEvent:Fire("denied", { action = "cast", reason = "mana" })
	assert(m.toast():find("Not enough mana", 1, true), "denied mana toasts: " .. m.toast())
	m.player:SetAttribute("Mana", 0)
	m.run.RenderStepped:Fire()
	assert(m.bar:FindFirstChild("Spell2"):FindFirstChild("Veil").Visible, "unaffordable slots grey out")
	before = #H.fired(m.remote)
	m.key(roblox.Enum.KeyCode.Two)
	assert(#H.fired(m.remote) == before, "no cast without mana")
	-- Right-click a damage slot: autocast through the atlas verb.
	m.bar:FindFirstChild("Spell2").InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton2 })
	local sent = m.ui.sent[#m.ui.sent]
	assert(sent[1] == "autocast" and Data.Spells[sent[2]] and Data.Spells[sent[2]].kind == "damage", "right-click sets autocast via IsleAction")
	-- Denied reasons map to short toasts.
	for reason, text in pairs({ ammo = "Out of arrows", sight = "No line of sight", glyphs = "Out of glyphs", combat = "in combat", range = "Out of range", leashing = "retreating" }) do
		m.fx.OnClientEvent:Fire("denied", { action = "ranged", reason = reason })
		assert(m.toast():find(text, 1, true), reason .. " toast: " .. m.toast())
		checks += 1
	end
	-- Atlas toasts float above the spell bar.
	local toast = m.ui.gui:FindFirstChild("Toast")
	assert(toast.Position.Y.Offset <= -50 - m.bar.Size.Y.Offset, "toast lifted above the spell bar")
	-- Hit numbers: WEAK!, resist and miss.
	m.fx.OnClientEvent:Fire("hit", { model = m.monster, position = roblox.Vector3.new(0, 5, -30), amount = 130, tag = "weak", style = "magic", spell = "GaleLance" })
	m.fx.OnClientEvent:Fire("hit", { model = m.monster, position = roblox.Vector3.new(0, 5, -30), amount = 70, tag = "resist", style = "ranged" })
	m.fx.OnClientEvent:Fire("hit", { model = m.monster, position = roblox.Vector3.new(0, 5, -30), amount = 0, miss = true, style = "ranged" })
	local terrainText = texts(m.workspace:FindFirstChild("Terrain"))
	assert(terrainText:find("WEAK!", 1, true) and terrainText:find("resist", 1, true) and terrainText:find("miss", 1, true), "weak / resist / miss numbers: " .. terrainText)
	-- Projectiles, snare, heal and teleport build their effects under the camera.
	local camera = m.workspace.CurrentCamera
	local beforeParts = #camera:GetChildren()
	m.fx.OnClientEvent:Fire("projectile", { from = roblox.Vector3.new(0, 4, 0), to = roblox.Vector3.new(0, 4, -30), style = "magic", spell = "GaleLance", color = "C9F2FF", attacker = 1 })
	m.fx.OnClientEvent:Fire("projectile", { from = roblox.Vector3.new(0, 4, 0), to = roblox.Vector3.new(0, 4, -30), style = "ranged", color = "B87333", attacker = 1 })
	m.fx.OnClientEvent:Fire("snare", { model = m.monster, position = roblox.Vector3.new(0, 5, -30), duration = 5, attacker = 1 })
	m.fx.OnClientEvent:Fire("heal", { spell = "Mend" })
	m.fx.OnClientEvent:Fire("teleport", { spell = "Hubward" })
	local kinds = {}
	for _, object in ipairs(camera:GetDescendants()) do kinds[object.ClassName] = true end
	assert(#camera:GetChildren() > beforeParts + 10, "style FX spawn parts")
	assert(kinds.Trail and kinds.ParticleEmitter and kinds.PointLight, "trails, sparkles and lights on bolts")
	checks += 16

	-- Ranged (Meadow Longbow, 40 stud reach): SHOOT, quiver count, "ranged" verb.
	local r = setup("MeadowLongbow", 30)
	assert(r.attack:FindFirstChild("Caption").Text == "SHOOT", "bow turns Attack into SHOOT")
	r.run.RenderStepped:Fire()
	assert(r.attack:FindFirstChild("Quiver").Visible and r.attack:FindFirstChild("Quiver").Text == "×143", "quiver count on the button")
	assert(r.bar:FindFirstChild("StyleChip"):FindFirstChild("Caption").Text == "×143", "quiver count on the style chip")
	r.press()
	f = lastFired(r)
	assert(f[1] == "ranged" and f[2] == r.monster, "bow fires ranged at 30 studs")
	assert(r.gestures[#r.gestures][1] == "shoot" and r.gestures[#r.gestures][3] == "MeadowLongbow", "bow shot plays the draw-and-release gesture")
	-- Empty quiver (QuiverCount push): a toast, no shot.
	r.player:SetAttribute("QuiverCount", 0)
	r.fx.OnClientEvent:Fire("denied", { action = "ranged", reason = "range" }) -- frees the swing
	before = #H.fired(r.remote)
	r.press()
	assert(#H.fired(r.remote) == before and r.toast():find("Out of arrows", 1, true), "no arrows: toast, no shot")
	-- Ranged bar: utility spells only (no staff).
	for i = 1, 6 do
		local b = r.bar:FindFirstChild("Spell" .. i)
		if b.Visible then assert(b:FindFirstChild("Glyph").Text == "✚" or b:FindFirstChild("Glyph").Text == "⌂", "only Mend / Hubward without a staff") end
	end
	checks += 6

	-- Melee (Brass Sword): 30 studs is out of reach; 10 studs swings "attack".
	local s = setup("BrassSword", 30)
	assert(s.attack:FindFirstChild("Caption").Text == "ATTACK", "sword keeps ATTACK")
	s.press()
	assert(#H.fired(s.remote) == 0, "sword cannot reach 30 studs")
	s.monster.PrimaryPart.Position = roblox.Vector3.new(0, 3, -10)
	s.press()
	f = lastFired(s)
	assert(f and f[1] == "attack" and f[2] == s.monster, "sword swings attack within reach")
	checks += 3

	-- Atlas pages: Combat, Spellbook, item details, bestiary, skills, stations.
	local ui = H.runAtlas(size)
	H.press(H.find(ui.gui, "AtlasButton"))
	H.press(ui.tabs:FindFirstChild("HeroButton"))
	H.press(H.find(ui.scroll, "SectionCombat"))
	local page = texts(ui.scroll)
	assert(page:find("Magic style", 1, true) and page:find("QUIVER", 1, true) and page:find("Brass Arrow", 1, true), "Combat page: style and quiver")
	assert(page:find("COMBAT TRIANGLE", 1, true) and page:find("beats", 1, true) and page:find("RANGED", 1, true), "Combat page: triangle and levels")
	assert(H.find(ui.scroll, "QuiverUnequip"), "quiver unequip button")
	H.press(H.find(ui.scroll, "QuiverUnequip"))
	assert(ui.sent[#ui.sent][1] == "unequip" and ui.sent[#ui.sent][2] == "ammo", "quiver unequips the ammo slot")
	H.press(ui.tabs:FindFirstChild("HeroButton"))
	H.press(H.find(ui.scroll, "SectionCombat"))
	H.press(H.find(ui.scroll, "AmmoCopperArrowEquip"))
	assert(ui.sent[#ui.sent][1] == "equip" and ui.sent[#ui.sent][2] == "CopperArrow", "owned arrows equip into the quiver")
	H.press(H.find(ui.scroll, "SectionSpellbook"))
	page = texts(ui.scroll)
	for _, id in ipairs(Data.SpellOrder) do
		assert(H.find(ui.scroll, "Spell" .. id), "spellbook lists " .. id)
		checks += 1
	end
	assert(page:find("free from staff", 1, true), "staff elements shown as free glyphs")
	assert(page:find("AUTOCAST", 1, true) and page:find("now ≈", 1, true), "autocast badge and damage estimate")
	H.press(H.find(ui.scroll, "SpellGaleDartAutocast"))
	assert(ui.sent[#ui.sent][1] == "autocast" and ui.sent[#ui.sent][2] == "GaleDart", "Autocast button sends the verb")
	H.press(ui.tabs:FindFirstChild("HeroButton"))
	H.press(H.find(ui.scroll, "SectionSpellbook"))
	local locked = H.find(ui.scroll, "SpellEmberCascadeAutocast")
	assert(locked ~= nil, "locked spells keep a disabled Autocast button")
	local sentBefore = #ui.sent
	H.press(locked)
	assert(#ui.sent == sentBefore, "a locked spell sends nothing")
	H.press(ui.tabs:FindFirstChild("HeroButton"))
	H.press(H.find(ui.scroll, "SectionSpellbook"))
	H.press(H.find(ui.scroll, "SpellGaleLanceClear"))
	assert(ui.sent[#ui.sent][1] == "autocast" and ui.sent[#ui.sent][2] == "none", "Clear autocast")
	-- Item details: bow tier/arrows, staff elements, arrow compatibility.
	for id, needle in pairs({ MeadowLongbow = "arrows up to tier 2", WindpineStaff = "Tide", BrassArrow = "Fits Meadow bows" }) do
		H.press(ui.tabs:FindFirstChild("SatchelButton"))
		H.press(H.find(ui.scroll, "SectionItems"))
		H.press(H.find(ui.scroll, "Item" .. id))
		local detail = texts(H.find(ui.scroll, "ItemDetail"))
		assert(detail:find(needle, 1, true), id .. " detail mentions " .. needle .. ": " .. detail)
		checks += 1
	end
	-- Bestiary: weakness / resistance on every creature.
	H.press(ui.tabs:FindFirstChild("HuntButton"))
	H.press(H.find(ui.scroll, "SectionBestiary"))
	page = texts(ui.scroll)
	assert(page:find("Weak to", 1, true) and page:find("Resists", 1, true), "bestiary shows the triangle")
	-- Skills: the four new skills are listed.
	H.press(ui.tabs:FindFirstChild("HeroButton"))
	H.press(H.find(ui.scroll, "SectionSkills"))
	for _, skill in ipairs({ "Ranged", "Magic", "Fletching", "Glyphcraft" }) do
		assert(H.find(ui.scroll, "Skill" .. skill), "skills page lists " .. skill)
		checks += 1
	end
	-- Stations: the new recipe categories render as filters.
	for station, categories in pairs({ Workbench = { "Bows", "Arrows", "Fletching", "Staves" }, Cauldron = { "Glyphs", "Tablets" }, Forge = { "Arrowheads" } }) do
		H.press(ui.tabs:FindFirstChild("WorkshopButton"))
		H.press(H.find(ui.scroll, "Section" .. station))
		for _, category in ipairs(categories) do
			local filter = H.find(ui.scroll, "Category" .. category)
			assert(filter, station .. " shows " .. category)
			H.press(filter)
			assert(#ui.warnings == 0 and H.find(ui.scroll, "Category" .. category), station .. " › " .. category .. " draws")
			checks += 1
		end
	end
	assert(#ui.warnings == 0, "combat pages draw without warnings: " .. table.concat(ui.warnings, "; "))
	checks += 12
end
print("Combat styles client: " .. (checks - styleChecks) .. " checks.")

-- 14. Agility & Hunter client: lap tracker and trap counter, vendor pages
-- (station visits, skillBuy, closed state), Journal › Agility and Hunt ›
-- Hunter (guide requests), new stats on the sheet, skill unlocks.
local ahChecks = checks
do
	local ui = run({ size = roblox.Vector2.new(1366, 768) })
	local player = ui.player
	local tracker, traps = find(ui.gui, "CourseTracker"), find(ui.gui, "TrapTracker")
	assert(not tracker.Visible and not traps.Visible, "no lap, no traps: HUD panels hidden")
	player:SetAttribute("AgilityRunExpires", os.time() + 22)
	player:SetAttribute("AgilityRun", "QuayRigging:3:6")
	assert(tracker.Visible, "lap tracker shows with a run")
	assert(find(tracker, "Step").Text == "3 / 6", "obstacle n/total")
	assert(find(tracker, "Next").Text:find("Rigging rope", 1, true), "next obstacle named")
	assert(find(tracker, "Countdown").Text:match("^0:2%d$"), "step countdown: " .. find(tracker, "Countdown").Text)
	assert(find(tracker, "Lap").Text:find("41.2s", 1, true), "best lap from the snapshot")
	assert(find(tracker, "Step3").BackgroundColor3 == roblox.Color3.fromHex("F3C66E"), "next obstacle pip is gold")
	player:SetAttribute("AgilityRun", "QuayRigging:6:6")
	player:SetAttribute("AgilityRun", "")
	assert(tracker.Visible and find(tracker, "Next").Text:find("LAP COMPLETE", 1, true), "final landing shows the finished lap")
	player:SetAttribute("AgilityRun", "QuayRigging:2:6")
	player:SetAttribute("AgilityMove", "fall:4")
	player:SetAttribute("AgilityRun", "")
	assert(not tracker.Visible, "a fall clears the tracker")
	player:SetAttribute("AgilityRunExpires", os.time() - 30)
	player:SetAttribute("AgilityRun", "QuayRigging:2:6")
	assert(not tracker.Visible, "an expired step window hides a stale lap")
	player:SetAttribute("AgilityRun", "Nowhere:2:6")
	assert(not tracker.Visible, "unknown course ignored")
	player:SetAttribute("HunterTraps", "2/2")
	player:SetAttribute("HunterTrapsCaught", 1)
	assert(traps.Visible and find(traps, "Count").Text:find("2 / 2", 1, true) and find(traps, "State").Text:find("1 caught", 1, true), "trap counter")
	player:SetAttribute("HunterTraps", "0/2")
	player:SetAttribute("HunterTrapsCaught", 0)
	assert(not traps.Visible, "no traps placed: counter hidden")
	-- Skymark Exchange visit → Ledger › Vendors; Buy sends skillBuy.
	local visits = 0
	local function visit(station)
		visits += 1
		player:SetAttribute("IsleStation", station)
		player:SetAttribute("IsleStationVisit", visits)
	end
	player:SetAttribute("SkillVendor", "Agility")
	player:SetAttribute("SkillVendorUntil", os.time() + 200)
	visit("SkymarkExchange")
	assert(ui.atlas.Visible and find(ui.scroll, "WareGaleDraught") and find(ui.scroll, "SetBonusWindrunner"), "Exchange stock and set bonus")
	assert(find(ui.scroll, "VendorStatus") and find(find(ui.scroll, "VendorStatus"), "Countdown"), "open counter counts down")
	table.clear(ui.sent)
	press(find(ui.scroll, "BuyGaleDraught"))
	assert(ui.sent[1] and ui.sent[1][1] == "skillBuy" and ui.sent[1][2] == "Agility:GaleDraught", "Buy sends skillBuy")
	table.clear(ui.sent)
	press(find(ui.scroll, "BuyWindrunnerHood"))
	press(find(ui.scroll, "BuyFeatherstepCharm"))
	assert(#ui.sent == 0, "owned outfit pieces and unaffordable wares do not send")
	-- Trackers' Lodge: the Exchange's window does not open it.
	visit("TrackersLodge")
	assert(find(ui.scroll, "WareBoxTrap") and find(ui.scroll, "SetBonusThicketstalker"), "Lodge stock")
	table.clear(ui.sent)
	press(find(ui.scroll, "BuySkyNet"))
	press(find(ui.scroll, "BuyBirdSnare"))
	assert(#ui.sent == 0, "a closed counter sells nothing")
	player:SetAttribute("SkillVendor", "Hunter")
	player:SetAttribute("SkillVendorUntil", os.time() + 200)
	visit("TrackersLodge")
	press(find(ui.scroll, "BuyBirdSnare"))
	assert(ui.sent[#ui.sent][2] == "Hunter:BirdSnare", "Lodge buy")
	-- Journal › Agility and Hunt › Hunter guide through the Wayfinder.
	local request = new("BindableEvent", { Name = "WayfinderRequest" })
	request.Parent = player
	local guided
	request.Event:Connect(function(specs, label) guided = { specs, label } end)
	visit("SkymarkExchange")
	press(ui.tabs:FindFirstChild("JournalButton"))
	press(find(ui.scroll, "SectionAgility"))
	assert(find(ui.scroll, "CourseTempestStormrun") and find(ui.scroll, "ShortcutTempestGaleLine") and find(ui.scroll, "CompanionGustling"), "courses, shortcuts, lap pet")
	press(find(ui.scroll, "GuideQuayRigging"))
	assert(guided and guided[1][1] == "anchor:Waypoint_Agility_QuayRigging" and not ui.atlas.Visible, "course guide closes the atlas and sets a waypoint")
	press(find(ui.gui, "AtlasButton"))
	press(ui.tabs:FindFirstChild("HuntButton"))
	press(find(ui.scroll, "SectionHunter"))
	assert(find(ui.scroll, "CreatureStormmaneIbex") and find(ui.scroll, "HunterTraps") and find(ui.scroll, "CompanionStormkid"), "hunter log, traps, companions")
	press(find(ui.scroll, "GuidePuffcapHopper"))
	assert(guided[1][1] == "anchor:Waypoint_Hunting_PuffcapHopper", "hunting ground guide")
	-- Stat sheet: the new stats sit with gathering & luck.
	press(find(ui.gui, "AtlasButton"))
	press(ui.tabs:FindFirstChild("HeroButton"))
	press(find(ui.scroll, "SectionGear"))
	local luck = find(ui.scroll, "Stats2")
	assert(luck and find(luck, "Statsurefoot") and find(luck, "StattrapLuck") and find(luck, "StathuntingFortune"), "new stats on the sheet")
	-- Skill detail lists courses and creatures as unlocks.
	press(find(ui.scroll, "SectionSkills"))
	press(find(ui.scroll, "SkillHunter"))
	local unlocks = 0
	for _, object in ipairs(ui.scroll:GetDescendants()) do
		if object.Name:match("^Unlock%d") then unlocks += 1 end
	end
	assert(unlocks >= 3, "Hunter unlocks listed")
	noFailures(ui, "agility & hunter")
	checks += 30
	-- Lap tracker HUD while the dialogue is closed but the tutorial is done: moves up to y 100.
	local view = run({ size = roblox.Vector2.new(730, 303), snapshot = snapshot({ vendorClosed = true }) })
	view.player:SetAttribute("AgilityRun", "QuayRigging:2:6")
	local t = find(view.gui, "CourseTracker")
	assert(t.Visible and t.Position.Y.Offset == 100 and t.Size.X.Offset <= 184, "phone lap tracker: top of the column, narrow")
	press(find(view.gui, "AtlasButton"))
	press(view.tabs:FindFirstChild("LedgerButton"))
	press(find(view.scroll, "SectionVendors"))
	assert(find(view.scroll, "GuideVendor"), "closed vendor offers a guide")
	table.clear(view.sent)
	press(find(view.scroll, "BuyGaleDraught"))
	assert(#view.sent == 0, "closed vendor: Buy disabled")
	noFailures(view, "vendor closed")
	checks += 3
end
print("Agility & Hunter client: " .. (checks - ahChecks) .. " checks.")
-- Skill Mastery client: tree canvas, node detail and unlock, tree switching,
-- respec confirm, capstone button, Skills page milestones and wear actions.
do
	local masteryChecks = checks
	local X = Data.XP_TABLE
	local function check(cond, case) assert(cond, case); checks += 1 end
	local snap = snapshot({ xp = { Mining = X[70], Fishing = X[99] }, masteryNow = 1000 })
	-- Rebuild the mastery view with a capstone path and a running cooldown.
	local p = { xp = { Mining = X[70], Fishing = X[99] }, items = {}, collection = {}, coins = 52000,
		mastery = { trees = { Mining = { SteadyPick = 1, QuarrySense = 1, EmberVein = 1, EchoingSeam = 1, FaultLine = 1, VeinSurge = 1 } }, cape = "Fishing" } }
	snap.depth.mastery = Progression.masteryView(p, 1000)
	local ui = run({ snapshot = snap })
	press(find(ui.gui, "AtlasButton"))
	press(ui.tabs:FindFirstChild("HeroButton"))
	press(find(ui.scroll, "SectionMastery"))
	noFailures(ui, "mastery page")
	check(find(ui.scroll, "MasterySummary") ~= nil, "mastery summary card")
	check(find(ui.scroll, "MasteryCanvas") ~= nil, "tree canvas drawn")
	local nodes, links = 0, 0
	for _, object in ipairs(find(ui.scroll, "MasteryCanvas"):GetChildren()) do
		if object.Name:match("^MasteryNode") then nodes += 1 end
		if object.Name == "Link" then links += 1 end
	end
	check(nodes == #Data.Mastery.TreeById.Mining.nodes, "every Mining node drawn")
	local expectedLinks = 0
	for _, n in ipairs(Data.Mastery.TreeById.Mining.nodes) do expectedLinks += #n.requires end
	check(links == expectedLinks, "every prerequisite line drawn")
	for _, id in ipairs(Data.Mastery.TreeOrder) do check(find(ui.scroll, "MasteryTree" .. id) ~= nil, "tree tab " .. id) end
	-- Node detail with next-level preview, then unlock.
	press(find(ui.scroll, "MasteryNodeSteadyPick"))
	check(find(ui.scroll, "MasteryNodeDetail") ~= nil, "node detail shown")
	table.clear(ui.sent)
	press(find(ui.scroll, "MasteryUnlock"))
	check(#ui.sent == 1 and ui.sent[1][1] == "masteryUnlock" and ui.sent[1][2] == "Mining:SteadyPick", "unlock sends the node")
	-- A locked node: unlock disabled, nothing sent.
	press(find(ui.scroll, "MasteryNodeGeomancer"))
	table.clear(ui.sent)
	press(find(ui.scroll, "MasteryUnlock"))
	check(#ui.sent == 0, "locked node cannot be bought")
	-- Capstone: owned and ready (cooldown 0 in this view).
	table.clear(ui.sent)
	press(find(ui.scroll, "MasteryActivate"))
	check(#ui.sent == 1 and ui.sent[1][1] == "ability" and ui.sent[1][2] == "Mining", "capstone button fires the ability")
	-- Respec needs a confirm.
	table.clear(ui.sent)
	press(find(ui.scroll, "MasteryRespec"))
	check(#ui.sent == 0 and find(ui.scroll, "MasteryRespecConfirm") ~= nil, "respec asks first")
	press(find(ui.scroll, "MasteryRespecConfirm"))
	check(#ui.sent == 1 and ui.sent[1][1] == "masteryRespec" and ui.sent[1][2] == "Mining", "respec confirmed")
	check(find(ui.scroll, "MasteryMantle") ~= nil, "worn mantle card")
	-- Switch trees: every tree draws its own canvas.
	for _, id in ipairs(Data.Mastery.TreeOrder) do
		press(find(ui.scroll, "MasteryTree" .. id))
		noFailures(ui, "mastery tree " .. id)
		local count = 0
		for _, object in ipairs(find(ui.scroll, "MasteryCanvas"):GetChildren()) do
			if object.Name:match("^MasteryNode") then count += 1 end
		end
		check(count == #Data.Mastery.TreeById[id].nodes, id .. " canvas nodes")
		check(find(ui.scroll, "MasteryAbility") ~= nil, id .. " capstone card")
	end
	-- Cooldown view: Activate disabled.
	local cooling = table.clone(snap)
	p.mastery.cooldowns = { Mining = 1200 }
	cooling.depth = table.clone(snap.depth)
	cooling.depth.mastery = Progression.masteryView(p, 1000)
	ui.setSnapshot(cooling)
	ui.update.OnClientEvent:Fire(cooling)
	press(find(ui.scroll, "MasteryTreeMining"))
	table.clear(ui.sent)
	press(find(ui.scroll, "MasteryActivate"))
	check(#ui.sent == 0 or ui.sent[1][1] ~= "ability", "cooling capstone cannot fire")
	-- Skills page: summary line, milestones, mantle marker and wear actions.
	press(find(ui.scroll, "SectionSkills"))
	press(find(ui.scroll, "SkillFishing"))
	check(find(ui.scroll, "SkillMilestones") ~= nil, "milestones card")
	local checklist = find(find(ui.scroll, "SkillMilestones"), "Checklist")
	local rows = 0
	for _, object in ipairs(checklist:GetChildren()) do if object.Name == "Check" then rows += 1 end end
	check(rows == 5, "five milestones listed")
	table.clear(ui.sent)
	press(find(ui.scroll, "SkillCapeFishing"))
	check(#ui.sent == 1 and ui.sent[1][1] == "masteryWear" and ui.sent[1][2] == "cape:", "worn mantle can be removed")
	press(find(ui.scroll, "SkillTitleFishing"))
	check(ui.sent[#ui.sent][1] == "masteryWear" and ui.sent[#ui.sent][2] == "title:Fishing", "title action")
	press(find(ui.scroll, "SkillMasteryFishing"))
	check(find(ui.scroll, "MasteryCanvas") ~= nil and find(ui.scroll, "MasteryNodePatientLine") ~= nil, "skill page links to its tree")
	noFailures(ui, "mastery skills page")
	checkSent(ui)
	-- Phone layout and an older server without mastery data.
	local phone = run({ size = roblox.Vector2.new(420, 600), snapshot = snap })
	press(find(phone.gui, "AtlasButton"))
	press(phone.tabs:FindFirstChild("HeroButton"))
	press(find(phone.scroll, "SectionMastery"))
	noFailures(phone, "phone mastery")
	check(find(phone.scroll, "MasteryCanvas") ~= nil, "phone canvas")
	local old = snapshot()
	old.depth.mastery = nil
	local legacy = run({ snapshot = old })
	press(find(legacy.gui, "AtlasButton"))
	press(legacy.tabs:FindFirstChild("HeroButton"))
	press(find(legacy.scroll, "SectionMastery"))
	noFailures(legacy, "mastery without server data")
	check(find(legacy.scroll, "MasteryCanvas") ~= nil, "tree still drawn while syncing")
	print("Skill Mastery client: " .. (checks - masteryChecks) .. " checks.")
end
-- Verdant Garden client: Workshop › Garden views, plot grid and detail
-- actions, seed picker, visitors, composter, milestones, shop and the ledger
-- station visit; phone layout, a loading garden and malformed data.
do
	local gardenChecks = checks
	local function check(cond, case) assert(cond, case); checks += 1 end
	local ui = run()
	local player = ui.player
	player:SetAttribute("IsleStation", "Garden")
	player:SetAttribute("IsleStationVisit", 1)
	check(ui.atlas.Visible and find(ui.scroll, "GardenSummary") ~= nil, "garden ledger visit opens Workshop › Garden")
	for i = 1, 12 do check(find(ui.scroll, "Plot" .. i) ~= nil, "plot tile " .. i) end
	check(find(find(ui.scroll, "Plot2"), "PlotTimer").Text:find("Ripe in", 1, true) ~= nil, "growing plot counts down")
	check(find(find(ui.scroll, "Plot3"), "PlotTimer").Text:find("Withers in", 1, true) ~= nil, "blighted plot warns")
	table.clear(ui.sent)
	press(find(ui.scroll, "GardenHarvestAll"))
	check(ui.sent[1] and ui.sent[1][1] == "harvestPlot" and ui.sent[1][2] == "all", "Harvest all")
	press(find(ui.scroll, "GardenWaterAll"))
	check(ui.sent[2] and ui.sent[2][1] == "waterPlot" and ui.sent[2][2] == "all", "Water all")
	-- Ripe plot → Harvest.
	press(find(ui.scroll, "Plot1"))
	check(find(ui.scroll, "PlotDetail") ~= nil, "plot detail opens")
	table.clear(ui.sent)
	press(find(ui.scroll, "PlotHarvest"))
	check(ui.sent[1] and ui.sent[1][1] == "harvestPlot" and ui.sent[1][2] == "1", "harvest one plot")
	-- Growing plot with a pest: swat, water disabled (still damp), uproot.
	press(find(ui.scroll, "Plot2"))
	table.clear(ui.sent)
	press(find(ui.scroll, "PlotSwat"))
	check(ui.sent[1] and ui.sent[1][1] == "clearPest" and ui.sent[1][2] == "2", "swat pest")
	press(find(ui.scroll, "PlotWater"))
	check(#ui.sent == 1, "damp plot cannot be watered")
	press(find(ui.scroll, "PlotUproot"))
	check(ui.sent[2] and ui.sent[2][1] == "clearPlot" and ui.sent[2][2] == "2", "uproot")
	-- Blighted plot → Treat.
	press(find(ui.scroll, "Plot3"))
	table.clear(ui.sent)
	press(find(ui.scroll, "PlotTreat"))
	check(ui.sent[1] and ui.sent[1][1] == "treatPlot" and ui.sent[1][2] == "3", "treat blight")
	-- Empty plot → seed picker; locked seeds and missing seeds do not send.
	press(find(ui.scroll, "Plot4"))
	check(find(ui.scroll, "SeedMeadowSeeds") ~= nil and find(ui.scroll, "SeedLotusBud") ~= nil, "seed picker lists every crop")
	table.clear(ui.sent)
	press(find(ui.scroll, "PlantMeadowSeeds"))
	check(ui.sent[1] and ui.sent[1][1] == "plant" and ui.sent[1][2] == "4:MeadowSeeds", "plant sends plot:seed")
	press(find(ui.scroll, "PlantSunwheatSeeds"))
	press(find(ui.scroll, "PlantLotusBud"))
	check(#ui.sent == 1, "seeds above the Farming level do not plant")
	press(find(ui.scroll, "PlotFertilise"))
	check(ui.sent[2] and ui.sent[2][1] == "fertilise" and ui.sent[2][2] == "4", "pre-fertilise an empty plot")
	-- Locked plot.
	press(find(ui.scroll, "Plot9"))
	check(find(ui.scroll, "PlotDetail") ~= nil and find(ui.scroll, "PlantMeadowSeeds") == nil, "locked plot has no seed picker")
	noFailures(ui, "garden plots")
	-- Visitors.
	press(find(ui.scroll, "GardenVisitors"))
	check(find(ui.scroll, "Visitor7") ~= nil and find(ui.scroll, "Visitor8") ~= nil, "visitor queue")
	check(find(find(ui.scroll, "Visitor7"), "Checklist") ~= nil, "request checklist")
	table.clear(ui.sent)
	press(find(ui.scroll, "Accept7"))
	check(ui.sent[1] and ui.sent[1][1] == "visitorAccept" and ui.sent[1][2] == "7", "accept a filled request")
	press(find(ui.scroll, "Accept8"))
	check(#ui.sent == 1, "unfilled request cannot be accepted")
	press(find(ui.scroll, "Decline8"))
	check(ui.sent[2] and ui.sent[2][1] == "visitorDecline" and ui.sent[2][2] == "8", "decline")
	-- Composter.
	press(find(ui.scroll, "GardenComposter"))
	check(find(ui.scroll, "Composter") ~= nil and find(ui.scroll, "CompostCountdown") ~= nil, "composter card and countdown")
	table.clear(ui.sent)
	press(find(ui.scroll, "CompostCollect"))
	check(ui.sent[1] and ui.sent[1][1] == "compostClaim", "collect compost")
	press(find(ui.scroll, "FeedAllHerb"))
	check(ui.sent[2] and ui.sent[2][1] == "compost" and ui.sent[2][2] == "Herb:70", "feed all herbs")
	press(find(ui.scroll, "CompostUpgrade"))
	check(ui.sent[3] and ui.sent[3][1] == "composterUpgrade", "upgrade the composter")
	-- Milestones.
	press(find(ui.scroll, "GardenMilestones"))
	for _, c in ipairs(Data.Garden.Crops) do check(find(ui.scroll, "Milestone" .. c.id) ~= nil, "milestone card " .. c.id) end
	-- Shop.
	press(find(ui.scroll, "GardenShop"))
	table.clear(ui.sent)
	press(find(ui.scroll, "BuySunwheatSeeds"))
	check(ui.sent[1] and ui.sent[1][1] == "gardenBuy" and ui.sent[1][2] == "SunwheatSeeds", "buy seeds")
	press(find(ui.scroll, "BuyLotusBud"))
	press(find(ui.scroll, "BuyGreenwardHoe"))
	press(find(ui.scroll, "BuySproutwoodHoe")) -- affordable and unlocked, but owned through an upgrade
	check(#ui.sent == 1, "gated shop entries do not send")
	do
		local card, words = find(ui.scroll, "ShopSproutwoodHoe"), {}
		for _, d in ipairs(card and card:GetDescendants() or {}) do
			if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then table.insert(words, tostring(d.Text)) end
		end
		check(string.find(table.concat(words, "\n"), "OWNED", 1, true) ~= nil, "a hoe superseded by an owned upgrade shows OWNED, not Buy")
	end
	press(find(ui.scroll, "ApplyLoam"))
	check(ui.sent[2] and ui.sent[2][1] == "gardenSkin" and ui.sent[2][2] == "Loam", "re-apply the free skin")
	check(find(ui.scroll, "ShopSkinMossbed") ~= nil, "owned skin listed")
	noFailures(ui, "garden views")
	checkSent(ui)
	-- Phone layout, no garden yet (syncing) and malformed data.
	local phone = run({ size = roblox.Vector2.new(420, 600) })
	visit(phone, "Workshop", "Garden")
	noFailures(phone, "phone garden")
	check(find(phone.scroll, "Plot12") ~= nil, "phone grid")
	local empty = snapshot()
	empty.garden = nil
	local legacy = run({ snapshot = empty })
	visit(legacy, "Workshop", "Garden")
	noFailures(legacy, "garden without server data")
	check(find(legacy.scroll, "GardenSummary") == nil, "syncing card while the garden loads")
	local broken = run({ snapshot = snapshot({ malformed = true }) })
	visit(broken, "Workshop", "Garden")
	for _, view in ipairs({ "Visitors", "Composter", "Milestones", "Shop", "Plots" }) do
		press(find(broken.scroll, "Garden" .. view))
		noFailures(broken, "malformed garden " .. view)
		checks += 1
	end
	print("Verdant Garden client: " .. (checks - gardenChecks) .. " checks.")
end
-- Workers depth client: Workshop › Workers fleet card, 12-slot grid, the
-- selected worker's actions, parts, the type browser; phone and malformed data.
do
	local workerChecks = checks
	local function check(cond, case) assert(cond, case); checks += 1 end
	local ui = run()
	local function last() return ui.sent[#ui.sent] or {} end
	visit(ui, "Workshop", "Workers")
	noFailures(ui, "workers page")
	check(find(ui.scroll, "WorkerFleet") ~= nil, "fleet summary card")
	for slot = 1, 12 do check(find(ui.scroll, "WorkerSlot" .. slot) ~= nil, "slot tile " .. slot) end
	check(find(find(ui.scroll, "WorkerSlot2"), "Storage") ~= nil, "built tile shows a storage bar")
	check(find(find(ui.scroll, "WorkerSlot6"), "Storage") == nil, "unbuilt tile has no storage bar")
	table.clear(ui.sent)
	press(find(ui.scroll, "WorkersCollectAll"))
	check(last()[1] == "workerClaimAll", "Collect all")
	press(find(ui.scroll, "WorkersBuild"))
	check(last()[1] == "workerBuild" and last()[2] == "5", "Build the next unlocked slot")
	-- Slot 1 detail: collect / refuel with the burning fuel / parts.
	check(find(ui.scroll, "Worker1") ~= nil, "slot 1 selected by default")
	press(find(ui.scroll, "WorkerCollect"))
	check(last()[1] == "workerClaim" and last()[2] == "1", "Collect slot 1")
	press(find(ui.scroll, "WorkerRefuel"))
	check(last()[1] == "workerFuel" and last()[2] == "1:CharredBriquette", "Refuel with the burning fuel")
	press(find(ui.scroll, "WorkerRemove2"))
	check(last()[1] == "workerRemove" and last()[2] == "1:2", "Remove upgrade 2")
	press(find(ui.scroll, "WorkerRemoveChest"))
	check(last()[1] == "workerRemove" and last()[2] == "1:chest", "Remove chest")
	press(find(ui.scroll, "PartWorkerGleamSprinkler"))
	check(last()[1] == "workerInstall" and last()[2] == "1:WorkerGleamSprinkler", "Install an upgrade")
	press(find(ui.scroll, "PartWorkerBrassChest"))
	check(last()[1] == "workerInstall" and last()[2] == "1:WorkerBrassChest", "Install a chest")
	press(find(ui.scroll, "PartCharredBriquetteEight"))
	check(last()[1] == "workerFuel" and last()[2] == "1:CharredBriquette:8", "Add eight briquettes")
	-- Slot 2 (full, auto-selling): change its type to Herb from the Farming group.
	press(find(ui.scroll, "WorkerSlot2"))
	check(find(ui.scroll, "Worker2") ~= nil, "slot 2 detail")
	-- Quick-refuel never spends a permanent fuel (Everflame Heart is held too).
	press(find(ui.scroll, "WorkerRefuel"))
	check(last()[1] == "workerFuel" and last()[2] == "2:CharredBriquette", "quick-refuel skips the permanent Everflame Heart")
	check(find(ui.scroll, "WorkerTypeOre") ~= nil, "Mining types listed first")
	press(find(ui.scroll, "WorkerGroupFarming"))
	check(find(ui.scroll, "WorkerTypeHerb") ~= nil, "Farming types listed")
	press(find(ui.scroll, "AssignHerb"))
	check(last()[1] == "workerAssign" and last()[2] == "2:Herb", "Assign slot 2 to Herb")
	press(find(ui.scroll, "DraftHerb"))
	check(last()[1] == "workerBlueprint" and last()[2] == "Herb:2", "Draft the next Herb tier")
	-- Combat group: a fully crafted Shardling Sentry offers no draft.
	press(find(ui.scroll, "WorkerGroupCombat"))
	check(find(ui.scroll, "WorkerTypeShardlingSentry") ~= nil, "combat workers listed")
	check(find(ui.scroll, "DraftShardlingSentry") == nil, "fully crafted type offers no draft")
	press(find(ui.scroll, "WorkerSlot3"))
	check(find(ui.scroll, "Worker3") ~= nil, "combat worker detail")
	local before = #ui.sent
	press(find(ui.scroll, "WorkerRefuel"))
	check(#ui.sent == before, "permanent fuel: refuel disabled")
	press(find(ui.scroll, "WorkerSlot9"))
	noFailures(ui, "locked slot tile")
	checkSent(ui)
	-- Phone layout, an older server (no worker depth fields) and malformed data.
	local phone = run({ size = roblox.Vector2.new(420, 600) })
	visit(phone, "Workshop", "Workers")
	noFailures(phone, "phone workers")
	check(find(phone.scroll, "WorkerSlot12") ~= nil, "phone grid")
	local old = snapshot()
	old.workers = { { resource = "Ore", tier = 1, ready = 3, interval = 120, capacity = 60 } }
	old.workerInfo = nil
	local legacy = run({ snapshot = old })
	visit(legacy, "Workshop", "Workers")
	noFailures(legacy, "legacy worker snapshot")
	check(find(legacy.scroll, "WorkerSlot1") ~= nil and find(legacy.scroll, "WorkerSlot4") ~= nil, "legacy snapshot renders the grid")
	local broken = run({ snapshot = snapshot({ malformed = true }) })
	visit(broken, "Workshop", "Workers")
	noFailures(broken, "malformed workers")
	for _, name in ipairs({ "WorkerSlot1", "WorkerSlot2", "WorkerGroupCombat", "WorkerCollect", "WorkerRefuel", "WorkersBuild" }) do
		local b = find(broken.scroll, name)
		if b then press(b) end
		noFailures(broken, "malformed workers " .. name)
		checks += 1
	end
	print("Workers depth client: " .. (checks - workerChecks) .. " checks.")
end
print("UI QA passed " .. checks .. " checks (" .. created .. " mock instances).")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-ui.luau")
