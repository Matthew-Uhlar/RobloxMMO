-- §52 item icon previews: builds Theme slots (shared/UiTheme.lua) for one item
-- of every icon family, a satchel-sized grid of real items, the rarity ladder
-- and Condensed / Radiant materials against tools/ui-harness.luau's mock, dumps
-- the GUI tree and rasterizes it with tools/rasterize-ui.py (an approximate
-- Roblox layout engine; not a Studio capture).
--   lune run tools/render-icons.luau [outDir]   (default build/icons)
-- Writes <outDir>/icons/{families,satchel,nameplates}.png.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local roblox = require("@lune/roblox")
local H = require("./ui-harness")
local outDir = process.args[1] or "build/icons"
fs.writeDir(outDir)

local env = {Instance = {new = function(class) return H.new(class) end}, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
	Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint}
local T = H.loadTheme(env)
local Items = H.Data.Items
T.useItems(Items)

local function screen(w, h)
	local gui = H.new("ScreenGui", {Name = "Icons", DisplayOrder = 1})
	local back = H.new("Frame", {Name = "Backdrop", Parent = gui, Size = roblox.UDim2.fromScale(1, 1), BackgroundColor3 = roblox.Color3.fromHex("0B1017"), BorderSizePixel = 0})
	return gui, back
end
local function label(parent, text, x, y, w, size, color)
	return T.label(parent, {Text = text, Position = roblox.UDim2.fromOffset(x, y), Size = roblox.UDim2.fromOffset(w, size + 4), TextSize = size,
		Font = roblox.Enum.Font.BuilderSansBold, TextColor3 = color or T.color.dim, TextTruncate = roblox.Enum.TextTruncate.AtEnd})
end

-- 1. One item per family (rarest first, so the halo / gem show where they apply).
local ids = {}
for id in pairs(Items) do table.insert(ids, id) end
table.sort(ids)
local byFamily, order = {}, {}
for _, id in ipairs(ids) do
	local spec = T.iconSpec(Items[id], Items)
	if not spec.modifier then
		local best = byFamily[spec.family]
		if not best then table.insert(order, spec.family) end
		if not best or spec.rank > T.iconSpec(Items[best], Items).rank then byFamily[spec.family] = id end
	end
end
table.sort(order)
local W, CELL, COLS = 1280, 96, 13
local rows = math.ceil(#order / COLS)
local familyGui, familyBack = screen(W, 0)
label(familyBack, "§52 ITEM ICONS — one item per family (" .. #order .. " families)", 16, 10, 900, 16, T.color.gold)
for i, family in ipairs(order) do
	local x, y = 16 + ((i - 1) % COLS) * CELL, 40 + math.floor((i - 1) / COLS) * (CELL + 6)
	local id = byFamily[family]
	local slot = T.slot(familyBack, {size = 64, position = roblox.UDim2.fromOffset(x + 14, y)})
	T.setSlot(slot, {id = id, def = Items[id], count = if Items[id].kind == "material" or Items[id].kind == "resource" then 24 else 1})
	label(familyBack, family, x, y + 66, CELL - 4, 11, T.color.text)
	label(familyBack, Items[id].rarity or "Common", x, y + 80, CELL - 4, 10, T.rarity(Items[id].rarity or "Common").color)
end
local familyH = 40 + rows * (CELL + 6) + 10

-- 2. A satchel page (44 px slots, 7 x 4) of mixed real items, plus the rarity
-- ladder and compressed materials at 56 px.
local satchelGui, satchelBack = screen(W, 0)
label(satchelBack, "Satchel page, 44 px slots (7 × 4)", 16, 10, 340, 14, T.color.gold)
local sample = {"Ore", "SunsteelOre", "Timber", "StarwoodLog", "Fish", "Glassfin", "Sunwheat", "Moonbloom", "BrassIngot", "StarmetalIngot", "CookedFish", "GrousePie",
	"Tonic", "TitanBrew", "EmberRune", "AstralRune", "SparkGlyph", "Skyjade", "SunsteelSword", "EmberoakWand", "SunsteelRod", "BrassHelm", "BrassBoots",
	"DewquartzRing", "EverwakeLantern", "EmberfoxPet", "TrailCasketElite", "SmallPouch"}
for i, id in ipairs(sample) do
	if Items[id] then
		local slot = T.slot(satchelBack, {size = 44, position = roblox.UDim2.fromOffset(16 + ((i - 1) % 7) * 48, 36 + math.floor((i - 1) / 7) * 48)})
		T.setSlot(slot, {id = id, def = Items[id], count = if Items[id].kind == "material" or Items[id].kind == "resource" then 64 else 1, equipped = id == "SunsteelSword"})
	end
end
label(satchelBack, "Rarity ladder (gear gem, halo from Rare)", 380, 10, 500, 14, T.color.gold)
local ladder = {}
for _, rarity in ipairs({"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"}) do
	for _, id in ipairs(ids) do
		local d = Items[id]
		if d.kind == "weapon" and d.rarity == rarity then table.insert(ladder, id); break end
	end
end
for i, id in ipairs(ladder) do
	local slot = T.slot(satchelBack, {size = 56, position = roblox.UDim2.fromOffset(380 + (i - 1) * 64, 36)})
	T.setSlot(slot, {id = id, def = Items[id], count = 1})
	label(satchelBack, Items[id].rarity, 380 + (i - 1) * 64, 94, 60, 10, T.rarity(Items[id].rarity).color)
end
label(satchelBack, "Condensed / Radiant (compressed block, badge, radiance)", 380, 116, 600, 14, T.color.gold)
for i, id in ipairs({"Ore", "CondensedOre", "RadiantOre", "Timber", "CondensedTimber", "RadiantTimber", "Fish", "RadiantFish"}) do
	local slot = T.slot(satchelBack, {size = 56, position = roblox.UDim2.fromOffset(380 + (i - 1) * 64, 140)})
	T.setSlot(slot, {id = id, def = Items[id], count = 12})
end
label(satchelBack, "Locked / undiscovered veil", 380, 206, 400, 14, T.color.gold)
local locked = T.slot(satchelBack, {size = 56, position = roblox.UDim2.fromOffset(380, 230)})
T.setSlot(locked, {id = "Celestium", def = Items.Celestium, count = 3, locked = true})
local satchelH = 300
print(string.format("icon cache: %d builds, %d clones", T.IconCache.builds, T.IconCache.clones))

-- 3. Townsfolk nameplates (§52 polish): the production npc.server.lua builds
-- every rig against the harness; each Nameplate's plate is laid out on a sheet.
local plateGui, plateBack = screen(W, 0)
label(plateBack, "Townsfolk nameplates — region accent bar, trade medallion, contrast >= 4.5:1", 16, 10, 900, 14, T.color.gold)
do
	local Style = luau.load(fs.readFile("shared/NpcStyle.lua"), {debugName = "NpcStyle", injectGlobals = true})()
	local storage = H.new("Folder", {Name = "ServerStorage"})
	local styleMarker, dataMarker = {}, {}
	local function signal() return {Connect = function() return {Disconnect = function() end} end} end
	local world = H.new("Folder", {Name = "Workspace"})
	world.ChildAdded, world.ChildRemoved = signal(), signal()
	luau.load(fs.readFile("npc.server.lua"), {debugName = "npc.server.lua", injectGlobals = true, environment = {
		game = {GetService = function(_, name)
			return ({Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
				ReplicatedStorage = {WaitForChild = function(_, child) return if child == "AetherNpcStyle" then styleMarker else dataMarker end},
				ServerStorage = storage})[name]
		end},
		workspace = world,
		require = function(target) return if target == styleMarker then Style else H.Data end,
		Instance = {new = function(class) return H.new(class) end}, RaycastParams = {new = function() return {} end},
		Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence,
		task = {delay = function() end, spawn = function() end, wait = function() end, defer = function() end},
	}})()
	local folder = storage:FindFirstChild("TownsfolkUnplaced")
	local roles = {"Guide", "Runebinder", "Resonator", "Beaconkeeper", "Forgemaster", "Fisher", "Banker", "CrystalReader", "Lightkeeper", "StormScribe",
		"Shardkeeper", "Astronomer", "SeedSeller", "CalderaWatcher", "CanopyWarden", "Herald"}
	local i = 0
	for _, role in ipairs(roles) do
		for _, model in ipairs(folder:GetChildren()) do
			if model:GetAttribute("TownsfolkRole") == role then
				local plate = model:FindFirstChild("Head", true):FindFirstChild("Nameplate"):FindFirstChild("Plate")
				plate.Parent = plateBack
				plate.AnchorPoint = roblox.Vector2.new(0, 0)
				plate.Position = roblox.UDim2.fromOffset(16 + (i % 4) * 300, 40 + math.floor(i / 4) * 72)
				i += 1
			end
		end
	end
end

local function job(name, gui, h)
	local file = outDir .. "/tree-" .. name .. ".json"
	fs.writeFile(file, serde.encode("json", {screen = {W, h}, label = "icons", shots = {{id = name, guis = {H.dump(gui)}}}}))
	return file
end
local jobs = {job("families", familyGui, familyH), job("satchel", satchelGui, satchelH), job("nameplates", plateGui, 340)}
local art = {palette = H.Catalog.palette, tintIndex = H.Catalog.tintIndex, shapes = {}}
fs.writeFile(outDir .. "/art.json", serde.encode("json", art))
local args = {"-I", "tools/rasterize-ui.py", "--art", outDir .. "/art.json", "--out", outDir}
for _, file in ipairs(jobs) do table.insert(args, file) end
local result = process.exec("python3", args)
stdio.write(result.stdout)
stdio.ewrite(result.stderr)
if not result.ok then error("rasterizer failed") end
