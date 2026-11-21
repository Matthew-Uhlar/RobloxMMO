-- Screenshot renderer for the atlas (ui.client.lua) and the HUDs (ui.client.lua +
-- combat.client.lua). Runs the LocalScripts headlessly against tools/ui-harness.luau
-- with realistic snapshots, opens every tab/section, dumps the GUI tree and hands
-- it to tools/rasterize-ui.py (an approximate Roblox layout engine + Pillow
-- rasterizer) which writes PNGs.
--
-- Usage (from the project directory):
--   lune run tools/render-ui.luau [outDir] [filter] [--full] [--issues]
--        [--sizes=1366x768,730x303] [--profiles=early,mid,endgame]
--     outDir     default build/screenshots
--     filter     substring of "<Tab>-<Section>" or "hud" (default: everything)
--     --full     also write *-full.png with the whole scrolled page unrolled
--     --issues   print findings (small text, truncation, overflow, touch targets)
--     --profiles snapshot stages (tools/ui-profiles.luau; the real server builds
--                each snapshot). Default "mid". "harness" = the fixed record in
--                tools/ui-harness.luau. Output: <outDir>/<profile>/<size>/<shot>.png
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local roblox = require("@lune/roblox")
local H = require("./ui-harness")

local outDir, filter, full, issues = "build/screenshots", nil, false, false
local sizes = { { 1366, 768, "desktop" }, { 844, 390, "phone" }, { 730, 303, "compact" } }
local profiles = { "mid" }
local positional = {}
for _, arg in ipairs(process.args) do
	if arg == "--full" then
		full = true
	elseif arg == "--issues" then
		issues = true
	elseif arg:sub(1, 8) == "--sizes=" then
		sizes = {}
		for w, h in arg:sub(9):gmatch("(%d+)x(%d+)") do
			local name = ({ ["1366x768"] = "desktop", ["844x390"] = "phone", ["730x303"] = "compact" })[w .. "x" .. h] or (w .. "x" .. h)
			table.insert(sizes, { tonumber(w), tonumber(h), name })
		end
	elseif arg:sub(1, 11) == "--profiles=" then
		profiles = {}
		for name in arg:sub(12):gmatch("[^,]+") do table.insert(profiles, name) end
	else
		table.insert(positional, arg)
	end
end
outDir = positional[1] or outDir
filter = positional[2]
local Profiles = nil
for _, name in ipairs(profiles) do
	if name ~= "harness" then Profiles = require("./ui-profiles") end
end
local function snapshotFor(profile, overrides)
	local snap = if profile == "harness" then H.snapshot(overrides) else Profiles.snapshot(profile)
	if profile ~= "harness" and overrides and overrides.message then snap.message = overrides.message end
	return snap
end

-- Sections other teams own right now (rendered and reviewed by them).
local skip = { ["Hunt-Bosses"] = true }
local tabs = { "Journal", "Hero", "Satchel", "Workshop", "Hunt", "Ledger" }
local function wanted(id)
	return filter == nil or id:lower():find(filter:lower(), 1, true) ~= nil
end
-- The section names the atlas itself shows for a tab (its section bar).
local function sectionsOf(ui, tab)
	H.press(ui.tabs:FindFirstChild(tab .. "Button"))
	local bar = H.find(ui.scroll, "Sections")
	local out = {}
	if not bar then return out end
	local buttons = {}
	for _, child in ipairs(bar:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Name:sub(1, 7) == "Section" then table.insert(buttons, child) end
	end
	for _, b in ipairs(buttons) do table.insert(out, { name = b.Name:sub(8), text = b.Text }) end
	return out
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
-- A HUD scene: atlas closed, combat HUD, optional extras.
local function hudScene(size, profile, message)
	local hudUi = H.runAtlas(size, { touch = true, snapshot = snapshotFor(profile) })
	hudUi.player:SetAttribute("Mana", 118)
	hudUi.player:SetAttribute("MaxMana", 160)
	local combat = H.runCombat(size, hudUi.player, hudUi.replicated)
	if message then hudUi.update.OnClientEvent:Fire(snapshotFor(profile, { message = message })) end
	return hudUi, combat
end

fs.writeDir(outDir)
local jobs = {}
for _, profile in ipairs(profiles) do
	for _, spec in ipairs(sizes) do
		local size = roblox.Vector2.new(spec[1], spec[2])
		local shots = {}
		-- Atlas pages
		local ui = H.runAtlas(size, { coop = H.coopSample(), snapshot = snapshotFor(profile) })
		H.press(H.find(ui.gui, "AtlasButton"))
		for _, tab in ipairs(tabs) do
			for _, section in ipairs(sectionsOf(ui, tab)) do
				local id = tab .. "-" .. section.name
				if wanted(id) and not skip[id] then
					H.press(ui.tabs:FindFirstChild(tab .. "Button"))
					local sectionButton = H.find(ui.scroll, "Section" .. section.name)
					if sectionButton then H.press(sectionButton) end
					for _, message in ipairs(ui.warnings) do print("warning " .. id .. ": " .. message) end
					table.clear(ui.warnings)
					table.insert(shots, { id = id, guis = screenTree(ui.playerGui) })
				end
			end
		end
		-- Extra states worth a look: skill detail, item detail.
		if wanted("Hero-SkillDetail") then
			H.press(ui.tabs:FindFirstChild("HeroButton"))
			H.press(H.find(ui.scroll, "SectionSkills"))
			local skill = H.find(ui.scroll, "SkillMining")
			if skill then
				H.press(skill)
				table.insert(shots, { id = "Hero-SkillDetail", guis = screenTree(ui.playerGui) })
				H.press(skill)
			end
		end
		if wanted("Satchel-ItemDetail") then
			H.press(ui.tabs:FindFirstChild("SatchelButton"))
			H.press(H.find(ui.scroll, "SectionItems"))
			local item = H.find(ui.scroll, "ItemSunsteelSword") or H.find(ui.scroll, "ItemBrassBoots") or H.find(ui.scroll, "ItemBlade")
			if item then
				H.press(item)
				table.insert(shots, { id = "Satchel-ItemDetail", guis = screenTree(ui.playerGui) })
			end
		end
		-- HUD: level-up banner + XP popup + toast, combat boss panel.
		if wanted("hud") then
			local hudUi, combat = hudScene(size, profile)
			local before = snapshotFor(profile)
			local mining = before.xp.Mining or 0
			local nextLevel = math.min(H.Progression.levelForXp(mining) + 1, H.Data.MAX_LEVEL or 99)
			local after = snapshotFor(profile, { message = "Mined Brassite ore   ·   Mining level " .. nextLevel .. "! +" .. H.Data.levelCoinReward(nextLevel) .. " coins" })
			after.xp.Mining = H.Data.XP_TABLE[nextLevel] + 5
			hudUi.update.OnClientEvent:Fire(after)
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
		-- Agility & Hunter HUD: a lap underway (lap tracker) and a caught trap (trap counter).
		if wanted("hud-agility") then
			local hudUi = hudScene(size, profile, "Mooring spar • +6 Agility XP")
			H.agilityHud(hudUi.player)
			table.insert(shots, { id = "HUD-Agility", guis = screenTree(hudUi.playerGui) })
		end
		-- Minigame HUDs: Skybreach Siege and Tempest Haul mid-match (minigames.server.lua hudFor format).
		for _, match in ipairs({
			{ "HUD-Minigame-Siege", "Siege", "game=Siege;points=34;min=50;time=412;players=10;tier=Veteran;keeper=1800/2400;portals=Cinder:0:900:0,Gale:450:900:0,Rime:900:900:1,Gloam:900:900:1;barricades=400/400,100/400,0/400,400/400;wave=7;creatures=12" },
			{ "HUD-Minigame-Haul", "Haul", "game=Haul;points=260;min=150;time=300;players=4;phase=energy;energy=64;essence=100;hull=71;fires=3;masts=1,0;raw=2;cooked=3" },
		}) do
			if wanted(match[1]) then
				local hudUi = hudScene(size, profile, "+12 points")
				hudUi.player:SetAttribute("MinigameHud", match[3])
				hudUi.player:SetAttribute("MinigameGame", match[2])
				table.insert(shots, { id = match[1], guis = screenTree(hudUi.playerGui) })
			end
		end
		-- Observatory party HUD: five delvers, this one an Aegis with Q cooling down.
		if wanted("HUD-Dungeon") then
			local hudUi = hudScene(size, profile, "Room cleared   ·   +40 Dungeoneering XP")
			hudUi.player:SetAttribute("DungeonClass", "Aegis")
			hudUi.player:SetAttribute("DungeonAbilityReady", 12)
			hudUi.player:SetAttribute("DungeonUltimates", 2)
			hudUi.player:SetAttribute("DungeonParty", "Voyager|Aegis|31;Bo|Mender|4;Cy||1;Di|Starshot|2;Ed|Arcanist|9")
			table.insert(shots, { id = "HUD-Dungeon", guis = screenTree(hudUi.playerGui) })
		end
		-- Island builder controls (build.client.lua) in place mode over the HUD.
		if wanted("builder") then
			local hudUi = H.runAtlas(size, { touch = true, snapshot = snapshotFor(profile) })
			local builder = H.runBuilder(size, hudUi.player)
			builder.enter("place", "LanternPost")
			table.insert(shots, { id = "Builder", guis = screenTree(hudUi.playerGui) })
		end
		local file = outDir .. "/tree-" .. profile .. "-" .. spec[3] .. ".json"
		fs.writeFile(file, serde.encode("json", { screen = { spec[1], spec[2] }, label = profile .. "/" .. spec[3], shots = shots }))
		table.insert(jobs, file)
	end
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
