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
-- The production world (built once, lazily): the Sky Chart miniature and the
-- minimap plates draw the real Workspace.Islands (Map Art §32).
local WH = require("./world-harness")

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
local tabs = { "Menu", "Journal", "Hero", "Satchel", "Workshop", "Hunt", "Ledger" }
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
-- A HUD scene: atlas closed, combat HUD, Wayfinder minimap, the satchel / XP
-- layer (hud.client.lua) and a stand-in for the 9-slot hotbar (hotbar.client.lua
-- is another team's; the preview draws Theme slots where it sits).
local function hudScene(size, profile, message)
	local touch = size.Y < 500
	local hudUi = H.runAtlas(size, { touch = touch, snapshot = snapshotFor(profile) })
	hudUi.player:SetAttribute("Mana", 118)
	hudUi.player:SetAttribute("MaxMana", 160)
	local combat = H.runCombat(size, hudUi.player, hudUi.replicated)
	-- The player stands on Compass Quay (the chart's YOU marker, the minimap).
	local character = H.new("Model", { Name = "Character" })
	local root = H.new("Part", { Name = "HumanoidRootPart", CFrame = roblox.CFrame.new(12, 4, 20) })
	root.Parent = character
	hudUi.player.Character = character
	hudUi.player:SetAttribute("CoopId", "crew-1")
	local layer = H.runHud(size, hudUi.player, hudUi.replicated, { touch = touch, workspace = WH.workspace(H.new) })
	H.runNav(size, hudUi.player, hudUi.replicated, { touch = touch, islands = WH.build().islands })
	H.hotbarPreview(hudUi.playerGui, size, layer.theme, snapshotFor(profile))
	hudUi.update.OnClientEvent:Fire(snapshotFor(profile, { message = message or "" }))
	hudUi.hud = layer
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
			-- depth.skills is what the HUD reads: a level-up in Mining and a Combat gain.
			local skills = after.depth and after.depth.skills
			if skills then
				skills = table.clone(skills)
				after.depth = table.clone(after.depth)
				after.depth.skills = skills
				local m = table.clone(skills.Mining or {})
				m.xp, m.level, m.fraction, m.maxed = after.xp.Mining, nextLevel, 0.06, false
				skills.Mining = m
				local c = table.clone(skills.Combat or { level = 1, xp = 0, fraction = 0 })
				c.xp, c.fraction = (c.xp or 0) + 48, math.min(0.98, (c.fraction or 0) + 0.04)
				skills.Combat = c
			end
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
			-- Tweens settle instantly here, so freeze the XP drops mid-flight.
			for i = 1, 5 do
				local drop = H.find(hudUi.hud.gui, "Drop" .. i)
				if drop and drop.Text ~= "" then
					drop.Visible, drop.TextTransparency, drop.TextStrokeTransparency = true, 0, 0.2
					drop.Position = roblox.UDim2.fromOffset(170, (i - 1) * 20)
				end
			end
			table.insert(shots, { id = "HUD", guis = screenTree(hudUi.playerGui) })
		end
		-- Satchel side panel, its context menu and lore tooltip, the paperdoll, the Sky Chart.
		for _, extra in ipairs({ "HUD-Satchel", "HUD-ContextMenu", "HUD-Gear", "WarpMap", "WarpMap-Hover" }) do
			if wanted(extra) then
				local hudUi = hudScene(size, profile)
				local layer = hudUi.hud
				local S = layer.state
				if extra == "WarpMap-Hover" then
					-- Map Art (§32): the miniature with a locked isle hovered (halo, raise, requirement).
					layer.api.OnInvoke("chart")
					if S.art then S.art.setHover("Gloomhollow") end
				elseif extra == "WarpMap" then
					layer.api.OnInvoke("chart")
					for _, isle in ipairs(layer.theme.WorldMap.islands) do
						if isle.id == "Skyreach" then S.pickWarp(isle, H.find(S.chart, "Isle_Skyreach")) end
					end
				else
					S.setOpen(true)
					if extra == "HUD-Gear" then S.view = "Gear"; S.refresh() end
					if extra == "HUD-Satchel" then
						local slot = S.slots[2]
						local id = (S.pageIds or {})[2]
						if id then
							local ctx, def = S.ctx(id)
							layer.theme.showTooltip(S.tooltip, layer.theme.lore(def, ctx), roblox.Vector2.new(S.panel.Position.X.Offset - 262, S.panel.Position.Y.Offset + 60), size)
						end
						S.selected = id
						S.refresh()
					elseif extra == "HUD-ContextMenu" then
						S.openMenu("SunsteelSword", roblox.Vector2.new(S.panel.Position.X.Offset - 180, S.panel.Position.Y.Offset + 120))
					end
				end
				table.insert(shots, { id = extra, guis = screenTree(hudUi.playerGui) })
			end
		end
		-- HUD depth (§34): action label over a creature, status orbs, pickup feed,
		-- chat tabs; the world context menu on a vein; hitsplat / overhead bar preview.
		for _, extra in ipairs({ "HUD-Depth", "HUD-WorldMenu", "HUD-Hitsplats" }) do
			if wanted(extra) then
				local touch = size.Y < 500
				local hudUi, combat = hudScene(size, profile, "Mined Copperstone Ore")
				local char = hudUi.player.Character
				local humanoid = H.new("Humanoid", { Name = "Humanoid", Health = 212, MaxHealth = 264 })
				humanoid.Parent = char
				hudUi.player:SetAttribute("PrayerMax", 43)
				hudUi.player:SetAttribute("PrayerPoints", 31)
				hudUi.player:SetAttribute("PrayerLevel", 12)
				hudUi.player:SetAttribute("PrayerQuick", "BarkhideWard,KindledEdge")
				hudUi.player:SetAttribute("PrayerActive", "BarkhideWard")
				-- The world under the cursor: a Copperstone vein and a Cinder Mite.
				local vein = H.new("Part", { Name = "Vein", Position = roblox.Vector3.new(14, 4, 22) })
				local prompt = H.new("ProximityPrompt", { Name = "Gather", ActionText = "Mine", ObjectText = "Copperstone Ore (Lv 1)", Enabled = true, HoldDuration = 1 })
				prompt:SetAttribute("IsleItem", "Ore")
				prompt.Parent = vein
				local mite = H.new("Model", { Name = "CinderMite" })
				for k, v in pairs({ DisplayName = "Cinder Mite", Level = 12, MonsterId = "CinderMite", Health = 500, MaxHealth = 500 }) do mite:SetAttribute(k, v) end
				local body = H.new("Part", { Name = "Body", Position = roblox.Vector3.new(20, 4, 22), Size = roblox.Vector3.new(3, 3, 3) })
				body.Parent = mite
				table.insert(combat.tagged, mite)
				local hit = { Instance = if extra == "HUD-WorldMenu" then vein else body, Position = roblox.Vector3.new(20, 4, 22) }
				local ov = H.runOverlay(size, hudUi.player, hudUi.replicated, { touch = touch, raycast = function() return hit end, tagged = combat.tagged })
				local S = ov.state
				-- A few pickups merged in the feed.
				local snap = snapshotFor(profile)
				local gained = table.clone(snap)
				gained.items = table.clone(snap.items or {})
				for id, n in pairs({ Ore = 3, Brassite = 2, ArcaneDust = 4, GolemCore = 1 }) do gained.items[id] = (gained.items[id] or 0) + n end
				gained.coins = (snap.coins or 0) + 120
				hudUi.update.OnClientEvent:Fire(gained)
				if extra == "HUD-WorldMenu" then
					if touch then
						ov.input.TouchLongPress:Fire({ roblox.Vector2.new(math.floor(size.X * 0.55), math.floor(size.Y * 0.45)) }, roblox.Enum.UserInputState.Begin, false)
					else
						local at = roblox.Vector3.new(math.floor(size.X * 0.55), math.floor(size.Y * 0.45), 0)
						ov.input.InputChanged:Fire({ UserInputType = roblox.Enum.UserInputType.MouseMovement, Position = at })
						ov.input.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton2, Position = at }, false)
						ov.input.InputEnded:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton2, Position = at }, false)
					end
				else
					ov.input.InputChanged:Fire({ UserInputType = roblox.Enum.UserInputType.MouseMovement, Position = roblox.Vector3.new(700, 400, 0) })
					S.hoverAt = -1
					ov.run.Heartbeat:Fire(0.1)
				end
				if extra == "HUD-Hitsplats" then
					-- Billboards do not rasterize: lay the pooled splats and an overhead bar
					-- out on a preview strip in the middle of the screen.
					local preview = H.new("ScreenGui", { Name = "SplatPreview", DisplayOrder = 20 })
					preview.Parent = hudUi.playerGui
					local strip = H.new("Frame", { Name = "Strip", BackgroundColor3 = roblox.Color3.fromHex("3A5A6E"), BackgroundTransparency = 0.2,
						Position = roblox.UDim2.fromOffset(math.floor(size.X / 2) - 300, math.floor(size.Y * 0.42)), Size = roblox.UDim2.fromOffset(600, 96) })
					strip.Parent = preview
					local payloads = { { amount = 37 }, { amount = 1284, crit = true }, { amount = 0, miss = true }, { amount = 130, tag = "weak" },
						{ amount = 70, tag = "resist" }, { heal = true, amount = 40 } }
					local monster = combat.monster
					monster:SetAttribute("Health", 330)
					monster:SetAttribute("MaxHealth", 1000)
					monster:SetAttribute("Level", 30)
					local mbody = H.new("Part", { Name = "Body", Position = roblox.Vector3.new(0, 4, 0), Size = roblox.Vector3.new(4, 6, 4) })
					mbody.Parent = monster
					monster.PrimaryPart = mbody
					for i, p in ipairs(payloads) do
						p.model, p.position = monster, roblox.Vector3.new(i * 3, 5, 0)
						if p.heal then combat.fx.OnClientEvent:Fire("heal", {}) else combat.fx.OnClientEvent:Fire("hit", p) end
					end
					local boards = {}
					for _, a in ipairs(combat.workspace:FindFirstChild("Terrain"):GetChildren()) do
						if a.Name == "Hitsplat" then table.insert(boards, a:FindFirstChild("Splat")) end
					end
					for i, board in ipairs(boards) do
						local cell = H.new("Frame", { Name = "Cell" .. i, BackgroundTransparency = 1, Position = roblox.UDim2.fromOffset((i - 1) * 100 - 10, 4),
							Size = roblox.UDim2.fromOffset(120, 64) })
						cell.Parent = strip
						for _, child in ipairs(board:GetChildren()) do
							local copy = child:Clone()
							copy.Parent = cell
							-- The harness settles tweens at once (faded out): show the first frame.
							if copy.Name == "Badge" then copy.BackgroundTransparency = 0.04 end
							if copy.Name == "Burst" then copy.BackgroundTransparency = 0.15 end
							if copy.Name == "Value" or copy.Name == "Tag" then copy.TextTransparency, copy.TextStrokeTransparency = 0, 0.05 end
							local edge = copy:FindFirstChild("Edge")
							if edge then edge.Transparency = 0 end
						end
					end
					for _, child in ipairs(hudUi.playerGui:GetChildren()) do
						if child.Name == "OverheadBar" then
							local cell = H.new("Frame", { Name = "Bar", BackgroundTransparency = 1, Position = roblox.UDim2.fromOffset(261, 72), Size = roblox.UDim2.fromOffset(78, 18) })
							cell.Parent = strip
							for _, c in ipairs(child:GetChildren()) do c:Clone().Parent = cell end
						end
					end
				end
				table.insert(shots, { id = extra, guis = screenTree(hudUi.playerGui) })
			end
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
