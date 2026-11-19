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
function methods:GetFocusedTextBox()
	return nil
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
	}
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
	if options.malformed then
		result.depth = {
			skills = "oops", totalLevel = "x", stats = 5, equipment = { weapon = 5, helmet = "NotAnItem" }, tools = { Mining = {} },
			accessoryBag = { 1, "MeadowCharm" }, activeAccessories = 7, accessorySlots = "four", pets = { 1, { id = "Nope" }, { id = "Tidewing", level = "x" } },
			buffs = { MightDraught = { remaining = "soon" }, Broken = 3 }, collections = { Ore = 5, Timber = { count = "many" } }, bestiary = { BramblebackBoar = "lots", Ghost = 3 },
			slayer = { lines = { Bramble = 3 }, quest = { line = "Unknown", tier = "II" } }, enchants = { BrassSword = { Mystery = 2 }, Blade = 4 }, regions = { 3, { id = 7 } },
		}
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
		setSnapshot = function(value) current = value end,
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
	Journal = { "Bearing", "Regions", "Crew" }, Hero = { "Skills", "Gear", "Enchant", "Accessories", "Pets" }, Satchel = { "Items", "Collections" },
	Workshop = { "Forge", "Hearth", "Cauldron", "Workbench", "Workers", "Home" }, Hunt = { "Slayer", "Bestiary" }, Ledger = { "Bank", "Market", "Merchant" },
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

-- 4. Station attribute opens the matching page.
do
	local ui = run()
	ui.player:SetAttribute("IsleStation", "Hearth")
	assert(ui.atlas.Visible and find(ui.scroll, "StationHearth"), "Hearth station opens the Workshop")
	ui.player:SetAttribute("IsleStation", "Slayer")
	assert(find(ui.scroll, "SlayerBramble"), "Slayer board opens the slayer page")
	ui.player:SetAttribute("IsleStation", "Forge:2")
	assert(find(ui.scroll, "StationForge"), "suffixed station value")
	-- Revisit: same IsleStation value, only the visit counter changes.
	press(ui.tabs:FindFirstChild("LedgerButton"))
	assert(not find(ui.scroll, "StationForge"), "left the Workshop")
	ui.player:SetAttribute("IsleStationVisit", 7)
	assert(find(ui.scroll, "StationForge"), "revisiting the same station reopens its tab")
	ui.player:SetAttribute("IsleRegionNotice", "Gloomhollow Caverns requires Mining 30.")
	local toast
	for _, object in ipairs(ui.gui:GetChildren()) do
		if object.ClassName == "TextLabel" and object.Text == "Gloomhollow Caverns requires Mining 30." then
			toast = object
		end
	end
	assert(toast and toast.Visible, "region notice toast")
	noFailures(ui, "stations")
	checks += 5
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
-- 6. XP popup and level-up banner between snapshots.
do
	local ui = run()
	local before = snapshot()
	local nextLevel = Progression.levelForXp(before.xp.Mining) + 1
	local after = snapshot({ xp = { Mining = Data.XP_TABLE[nextLevel] + 5 } })
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
	noFailures(ui, "level-up")
	checks += 3
end

print("UI QA passed " .. checks .. " checks (" .. created .. " mock instances).")
