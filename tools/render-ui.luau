-- Screenshot renderer for the atlas (ui.client.lua) and the HUDs (ui.client.lua +
-- combat.client.lua). Runs the LocalScripts headlessly against tools/ui-harness.luau
-- with a realistic mid-game snapshot, opens every tab/section, dumps the GUI tree
-- and hands it to tools/rasterize-ui.py (an approximate Roblox layout engine +
-- Pillow rasterizer) which writes PNGs.
--
-- Usage (from the project directory):
--   lune run tools/render-ui.luau [outDir] [filter] [--full] [--sizes=1366x768,730x303]
--     outDir   default build/screenshots
--     filter   substring of "<Tab>-<Section>" or "hud" (default: everything)
--     --full   also write *-full.png with the whole scrolled page unrolled
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local roblox = require("@lune/roblox")
local H = require("./ui-harness")

local outDir, filter, full, issues = "build/screenshots", nil, false, false
local sizes = { { 1366, 768, "desktop" }, { 844, 390, "phone" }, { 730, 303, "compact" } }
local positional = {}
for _, arg in ipairs(process.args) do
	if arg == "--full" then
		full = true
	elseif arg == "--issues" then
		issues = true
	elseif arg:sub(1, 8) == "--sizes=" then
		sizes = {}
		for w, h in arg:sub(9):gmatch("(%d+)x(%d+)") do
			table.insert(sizes, { tonumber(w), tonumber(h), w .. "x" .. h })
		end
	else
		table.insert(positional, arg)
	end
end
outDir = positional[1] or outDir
filter = positional[2]

local pages = {
	{ "Journal", { "Bearing", "Quests", "Diaries", "Construction", "Regions", "Crew", "Calendar" } },
	{ "Hero", { "Skills", "Gear", "Combat", "Spellbook", "Enchant", "Accessories", "Pets" } },
	{ "Satchel", { "Items", "Collections" } },
	{ "Workshop", { "Forge", "Hearth", "Cauldron", "Workbench", "Workers", "Home" } },
	{ "Hunt", { "Slayer", "Bestiary", "Dungeon" } },
	{ "Ledger", { "Bank", "Market", "Orders", "Auctions", "Merchant" } },
}
local function wanted(id)
	return filter == nil or id:lower():find(filter:lower(), 1, true) ~= nil
end

local function screenTree(playerGui)
	local guis = {}
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.ClassName == "ScreenGui" then
			table.insert(guis, H.dump(child))
		end
	end
	table.sort(guis, function(a, b) return (a.props.DisplayOrder or 0) < (b.props.DisplayOrder or 0) end)
	return guis
end

fs.writeDir(outDir)
local jobs = {}
for _, spec in ipairs(sizes) do
	local size = roblox.Vector2.new(spec[1], spec[2])
	local shots = {}
	-- Atlas pages
	local ui = H.runAtlas(size, { coop = H.coopSample() })
	H.press(H.find(ui.gui, "AtlasButton"))
	for _, page in ipairs(pages) do
		local tab = page[1]
		for _, section in ipairs(page[2]) do
			local id = tab .. "-" .. section
			if wanted(id) then
				H.press(ui.tabs:FindFirstChild(tab .. "Button"))
				local sectionButton = H.find(ui.scroll, "Section" .. section)
				if sectionButton then
					H.press(sectionButton)
				end
				for _, message in ipairs(ui.warnings) do
					print("warning " .. id .. ": " .. message)
				end
				table.clear(ui.warnings)
				table.insert(shots, { id = id, guis = screenTree(ui.playerGui) })
			end
		end
	end
	-- Extra states worth a look: skill detail, item detail.
	if wanted("Hero-SkillDetail") then
		H.press(ui.tabs:FindFirstChild("HeroButton"))
		H.press(H.find(ui.scroll, "SectionSkills"))
		H.press(H.find(ui.scroll, "SkillMining"))
		table.insert(shots, { id = "Hero-SkillDetail", guis = screenTree(ui.playerGui) })
		H.press(H.find(ui.scroll, "SkillMining"))
	end
	if wanted("Satchel-ItemDetail") then
		H.press(ui.tabs:FindFirstChild("SatchelButton"))
		H.press(H.find(ui.scroll, "SectionItems"))
		local item = H.find(ui.scroll, "ItemSunsteelSword") or H.find(ui.scroll, "ItemBrassBoots")
		if item then
			H.press(item)
			table.insert(shots, { id = "Satchel-ItemDetail", guis = screenTree(ui.playerGui) })
		end
	end
	-- HUD: atlas closed, level-up banner + XP popup + toast, combat boss panel.
	if wanted("hud") then
		local hudUi = H.runAtlas(size, { touch = true })
		hudUi.player:SetAttribute("Mana", 118)
		hudUi.player:SetAttribute("MaxMana", 160)
		local combat = H.runCombat(size, hudUi.player, hudUi.replicated)
		local Data = H.Data
		local before = H.snapshot()
		local nextLevel = H.Progression.levelForXp(before.xp.Mining) + 1
		hudUi.update.OnClientEvent:Fire(H.snapshot({ xp = { Mining = Data.XP_TABLE[nextLevel] + 5 },
			message = "Mined Brassite ore   ·   Mining level " .. nextLevel .. "! +" .. Data.levelCoinReward(nextLevel) .. " coins" }))
		table.insert(combat.tagged, combat.monster)
		combat.monster:SetAttribute("Health", 640)
		combat.monster:SetAttribute("MaxHealth", 1000)
		combat.monster:SetAttribute("Boss", true)
		combat.monster:SetAttribute("Level", 30)
		combat.monster:SetAttribute("OwnerUserId", 1)
		combat.monster:SetAttribute("DisplayName", "Brassfall Golem")
		combat.fx.OnClientEvent:Fire("bossSpawn", { owner = 1, name = "Brassfall Golem" })
		combat.run.RenderStepped:Fire()
		table.insert(shots, { id = "HUD", guis = screenTree(hudUi.playerGui) })
	end
	-- Island builder controls (build.client.lua) in place mode over the HUD.
	if wanted("builder") then
		local hudUi = H.runAtlas(size, { touch = true })
		local builder = H.runBuilder(size, hudUi.player)
		builder.enter("place", "LanternPost")
		table.insert(shots, { id = "Builder", guis = screenTree(hudUi.playerGui) })
	end
	local file = outDir .. "/tree-" .. spec[3] .. ".json"
	fs.writeFile(file, serde.encode("json", { screen = { spec[1], spec[2] }, label = spec[3], shots = shots }))
	table.insert(jobs, file)
end

-- Art geometry for ViewportFrame thumbnails (flat projection in the rasterizer).
local art = { palette = H.Catalog.palette, tintIndex = H.Catalog.tintIndex, shapes = {} }
for name, shape in pairs(H.Catalog.shapes) do
	art.shapes[name] = { vertices = shape.vertices, faces = shape.faces }
end
fs.writeFile(outDir .. "/art.json", serde.encode("json", art))

local args = { "-I", "tools/rasterize-ui.py", "--art", outDir .. "/art.json", "--out", outDir }
if full then table.insert(args, "--full") end
if issues then table.insert(args, "--issues") end
for _, file in ipairs(jobs) do table.insert(args, file) end
local result = process.exec("python3", args)
stdio.write(result.stdout)
stdio.ewrite(result.stderr)
if not result.ok then
	error("rasterizer failed")
end
