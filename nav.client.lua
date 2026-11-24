-- Wayfinder: compact minimap/compass (top-left with the region name and the
-- player's coordinates; the Map button on it folds the map away and Settings ›
-- Minimap hides the whole block; M is the Sky Chart's key; §29 HUD lanes),
-- island labels, NPC/station/beacon markers read from Workspace.Islands anchors
-- and the world's own prompts, a Navigate list, recall charms, and waypoints: a
-- glowing beam + beacon to the target that clears itself on arrival.
-- Other scripts request a waypoint by firing the local BindableEvent
-- LocalPlayer.WayfinderRequest(specs, label[, quiet]) with Data.Townsfolk target
-- specs; LocalPlayer.WayfinderActive (attribute, read-only for them) holds the
-- active waypoint's label.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = Data.Townsfolk
-- Colours, fonts and HUD lanes from the shared theme (§29).
local Theme = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))

local function rgb(h) return Color3.fromHex(h) end
local ink, deep, slate = Theme.color.panel, Theme.color.inset, Theme.color.raised
local ivory, muted, mint, gold, violet = Theme.color.text, Theme.color.dim, Theme.color.mint, Theme.color.gold, rgb("B8A6FF")
local bold, regular = Enum.Font.BuilderSansBold, Enum.Font.BuilderSansMedium
local function make(class, parent, props)
	local o = Instance.new(class)
	if class == "UIStroke" then o.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r, edge)
	make("UICorner", o, {CornerRadius = if r == "circle" then UDim.new(0.5, 0) else UDim.new(0, r)})
	if edge then make("UIStroke", o, {Color = edge, Transparency = 0.35, Thickness = 1}) end
	return o
end

------------------------------------------------------------------------------
-- World index: islands + anchors (scan), NPCs, prompts, monster spawns.
------------------------------------------------------------------------------
local scan = T.scanIslands(workspace:FindFirstChild("Islands")) -- rescanned (debounced) as islands build
local prompts = {station = {}, gather = {}, warp = {}, warpReturn = {}} -- [kind][prompt] = key
-- Agility & Hunter prompts (world.server.lua): course obstacles keyed
-- "<course>:<index>" and hunting spots whose host part carries TrapState /
-- TrapOwner (written by the server). Only the local player's traps are shown.
-- Spots seen before the trap watcher below is defined wait in `pending`.
local Skill = {obstacles = {}, shortcutEnds = {}, traps = {}, levels = {}, next = {}, pending = {}}
local function promptPosition(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then return parent.Position end
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	return nil
end
local function classify(prompt)
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner and owner ~= player.UserId then return end
	local verb, item = prompt:GetAttribute("IsleAction"), prompt:GetAttribute("IsleItem")
	if verb == "station" and type(item) == "string" then prompts.station[prompt] = item
	elseif verb == "gather" and type(item) == "string" then prompts.gather[prompt] = item end
	local region = prompt:GetAttribute("IsleWarpRegion")
	if type(region) == "string" then prompts.warp[prompt] = region end
	if prompt:GetAttribute("IsleWarpReturn") ~= nil or prompt.ActionText == "Travel home" then prompts.warpReturn[prompt] = "Homeward" end
	if verb == "agility" then
		local course, index = prompt:GetAttribute("AgilityCourse"), prompt:GetAttribute("AgilityIndex")
		if type(course) == "string" and type(index) == "number" then Skill.obstacles[prompt] = course .. ":" .. index end
	elseif verb == "shortcut" and type(item) == "string" then
		-- Each end gates on where it lands (ShortcutRegion, "" = ungated).
		local id, tag = string.match(item, "^(%w+):([AB])$")
		if id then Skill.shortcutEnds[prompt] = {id = id, tag = tag} end
	elseif (verb == "trap" or verb == "net") and type(item) == "string" then
		if Skill.watchTrap then Skill.watchTrap(prompt, item) else table.insert(Skill.pending, {prompt, item}) end
	end
end
local function unclassify(prompt)
	for _, set in pairs(prompts) do set[prompt] = nil end
	Skill.obstacles[prompt] = nil
	Skill.shortcutEnds[prompt] = nil
	for host, entry in pairs(Skill.traps) do
		if entry.prompt == prompt then
			if entry.board then entry.board:Destroy() end
			Skill.traps[host] = nil
		end
	end
end
workspace.DescendantAdded:Connect(function(d) if d:IsA("ProximityPrompt") then classify(d) end end)
workspace.DescendantRemoving:Connect(function(d) if d:IsA("ProximityPrompt") then unclassify(d) end end)
task.spawn(function()
	for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("ProximityPrompt") then classify(d) end end
end)
-- Islands may be built (or rebuilt) after we start: rescan, debounced.
local rescanQueued = false
local function rescan()
	if rescanQueued then return end
	rescanQueued = true
	task.delay(0.5, function()
		rescanQueued = false
		scan = T.scanIslands(workspace:FindFirstChild("Islands"))
	end)
end
local function watchIslands(islands)
	islands.DescendantAdded:Connect(function(d)
		if d.Parent == islands then d.AttributeChanged:Connect(rescan); rescan()
		elseif string.sub(d.Name, 1, 7) == "Anchor_" then rescan() end
	end)
	islands.DescendantRemoving:Connect(function(d) if d.Parent == islands or string.sub(d.Name, 1, 7) == "Anchor_" then rescan() end end)
	for _, m in ipairs(islands:GetChildren()) do m.AttributeChanged:Connect(rescan) end
	rescan()
end
workspace.ChildAdded:Connect(function(c) if c.Name == "Islands" then watchIslands(c) end end)
workspace.ChildRemoved:Connect(function(c) if c.Name == "Islands" then rescan() end end)
if workspace:FindFirstChild("Islands") then watchIslands(workspace.Islands) end

local function npcPositions()
	local out = {}
	local folder = workspace:FindFirstChild("Townsfolk")
	if not folder then return out end
	for _, model in ipairs(folder:GetChildren()) do
		local role, root = model:GetAttribute("TownsfolkRole"), model:FindFirstChild("HumanoidRootPart")
		if type(role) == "string" and root then out[role] = root.Position end
	end
	return out
end
-- Builds the plain index Data.Townsfolk.resolveTarget reads.
local function buildIndex()
	local index = {anchors = {}, npcs = npcPositions(), islands = {}, station = {}, gather = {}, monster = {}, warp = {}, warpReturn = {}}
	for name, parts in pairs(scan.anchors) do
		local list = {}
		for _, part in ipairs(parts) do if part.Parent then table.insert(list, part.Position) end end
		index.anchors[name] = list
	end
	for region, entry in pairs(scan.regions) do index.islands[region] = entry.center end
	for kind, set in pairs(prompts) do
		for prompt, key in pairs(set) do
			local pos = promptPosition(prompt)
			if pos then
				if kind == "warpReturn" then table.insert(index.warpReturn, pos)
				else index[kind][key] = index[kind][key] or {}; table.insert(index[kind][key], pos) end
			end
		end
	end
	local spawns = workspace:FindFirstChild("MonsterSpawns")
	if spawns then
		for _, marker in ipairs(spawns:GetChildren()) do
			local id = marker:GetAttribute("MonsterId")
			if type(id) == "string" and marker:IsA("BasePart") then
				index.monster[id] = index.monster[id] or {}
				table.insert(index.monster[id], marker.Position)
			end
		end
	end
	local home = player:GetAttribute("IslandCenter")
	if typeof(home) == "Vector3" then index.home = home end
	-- The next obstacle of the running lap ("anchor:AgilityNext").
	if Skill.next.host and Skill.next.host.Parent then index.anchors.Anchor_AgilityNext = {Skill.next.host.Position} end
	return index
end

------------------------------------------------------------------------------
-- HUD.
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "Wayfinder", ResetOnSpawn = false, DisplayOrder = 6,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local camera = workspace.CurrentCamera
local function lanes()
	local view = gui.AbsoluteSize
	if not view or view.X <= 0 or view.Y <= 0 then view = if camera then camera.ViewportSize else Vector2.new(1280, 720) end
	return Theme.hudLayout(view.X, view.Y, {touch = Input.TouchEnabled})
end
local L0 = lanes()
local SIZE = L0.map.size
local holder = make("Frame", gui, {Name = "Minimap", Position = UDim2.fromOffset(L0.mapBlock.x, L0.mapBlock.y),
	Size = UDim2.fromOffset(L0.mapBlock.w, L0.mapBlock.h), BackgroundTransparency = 1})
local map = make("Frame", holder, {Name = "Map", Size = UDim2.fromOffset(SIZE, SIZE), BackgroundColor3 = rgb("0E1A22"), BackgroundTransparency = 0.05,
	ClipsDescendants = true, BorderSizePixel = 0})
round(map, 6)
Theme.rim(map, 2)
make("UIGradient", map, {Rotation = 90, Color = ColorSequence.new(rgb("C9D6E0"), rgb("8C99A6"))})
local layer = make("Frame", map, {Name = "Layer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1})
-- Map Art (§32, shared/MapArt.lua): cached top-down island plates under the
-- markers (region tint, tiers, water, paths, roofs, canopy, landmark, beacons).
local mapArt = nil
do
	local module = ReplicatedStorage:FindFirstChild("AetherMapArt")
	local ok, MapArt = pcall(function() return module and require(module) end)
	if ok and type(MapArt) == "table" and MapArt.mountMinimap then
		mapArt = MapArt.mountMinimap({layer = layer, Theme = Theme, Data = Data, touch = Input.TouchEnabled})
	end
end
-- Region name + coordinates: under the map on desktop, inside its foot on phones.
local info = make("Frame", holder, {Name = "Info", BackgroundColor3 = Theme.color.void, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 8})
round(info, 4)
make("UIStroke", info, {Color = Theme.color.frame, Thickness = 1, Transparency = 0.3})
local regionLabel = make("TextLabel", info, {Name = "Region", BackgroundTransparency = 1, Font = bold, TextSize = 12, TextColor3 = gold, ZIndex = 9,
	TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = "The Skyways"})
local coordsLabel = make("TextLabel", info, {Name = "Coords", BackgroundTransparency = 1, Font = Theme.font.number, TextSize = 8, TextColor3 = muted, ZIndex = 9,
	TextXAlignment = Enum.TextXAlignment.Center, Text = "0, 0, 0"})
-- Compass rose letters stay on the rim (north-up map).
for _, mark in ipairs({{"N", 0.5, 0.06, gold}, {"S", 0.5, 0.94, muted}, {"E", 0.94, 0.5, muted}, {"W", 0.06, 0.5, muted}}) do
	make("TextLabel", map, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(mark[2], mark[3]), Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1, Text = mark[1], Font = bold, TextSize = 11, TextColor3 = mark[4], ZIndex = 6})
end
local arrow = make("TextLabel", map, {Name = "PlayerArrow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Text = "▲", Font = bold, TextSize = 16, TextColor3 = mint, ZIndex = 7})
make("UIStroke", arrow, {Color = deep, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual})
local bar = make("Frame", holder, {Name = "Controls", Position = UDim2.fromOffset(0, SIZE + 4), Size = UDim2.fromOffset(SIZE, 30), BackgroundTransparency = 1})
local barLayout = make("UIListLayout", bar, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right})
local controls = {}
local function smallButton(text, width, onClick)
	local b = Theme.button(bar, text, {name = "Map" .. (({["−"] = "ZoomOut", ["+"] = "ZoomIn"})[text] or text), size = UDim2.fromOffset(width, 30), textSize = 13})
	b.AutoButtonColor = true
	b.Activated:Connect(onClick)
	table.insert(controls, b)
	return b
end
local ZOOMS = {0.12, 0.2, 0.32, 0.5, 0.8, 1.3}
local zoom = 3
local mapOpen = true
local navigatePanel
local function setMapOpen(open)
	mapOpen = open
	map.Visible = open
	if info then info.Visible = open end
end
local zoomOut = smallButton("−", 30, function() zoom = math.max(1, zoom - 1) end)
local zoomIn = smallButton("+", 30, function() zoom = math.min(#ZOOMS, zoom + 1) end)
smallButton("Go", 34, function() navigatePanel() end)
smallButton("Map", 40, function() setMapOpen(not mapOpen) end)
-- Phones: tap the map to cycle the zoom (the − / + buttons fold away).
local zoomTap = make("TextButton", map, {Name = "ZoomTap", BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 9, Visible = false})
zoomTap.Activated:Connect(function() zoom = zoom % #ZOOMS + 1 end)
-- Lays the minimap block out for the current screen (desktop: info strip and a
-- controls row under the map; touch: info inside the map, a 44 px column).
local function layoutMinimap()
	local L = lanes()
	SIZE = L.map.size
	holder.Position, holder.Size = UDim2.fromOffset(L.mapBlock.x, L.mapBlock.y), UDim2.fromOffset(L.mapBlock.w, L.mapBlock.h)
	map.Size = UDim2.fromOffset(SIZE, SIZE)
	info.Position = UDim2.fromOffset(L.mapInfo.x - L.mapBlock.x, L.mapInfo.y - L.mapBlock.y)
	info.Size = UDim2.fromOffset(L.mapInfo.w, L.mapInfo.h)
	local inside = L.mapInfo.inside == true
	regionLabel.Position, regionLabel.Size = UDim2.fromOffset(2, 1), UDim2.new(1, -4, 0, if inside then 11 else 14)
	regionLabel.TextSize = if inside then 10 else 12
	coordsLabel.Position, coordsLabel.Size = UDim2.fromOffset(2, if inside then 12 else 15), UDim2.new(1, -4, 0, 9)
	coordsLabel.TextSize = 8 -- the pixel face's floor (§29: captions ≥ 8 px)
	zoomOut.Visible, zoomIn.Visible, zoomTap.Visible = not L.touch, not L.touch, L.touch
	if L.mapControls.column then
		bar.Position, bar.Size = UDim2.fromOffset(L.mapControls.x - L.mapBlock.x, 0), UDim2.fromOffset(44, L.mapControls.h)
		barLayout.FillDirection = Enum.FillDirection.Vertical
		barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		for _, b in ipairs(controls) do b.Size = UDim2.fromOffset(44, 44) end
	else
		bar.Position, bar.Size = UDim2.fromOffset(0, L.mapControls.y - L.mapBlock.y), UDim2.fromOffset(L.mapControls.w, 30)
		barLayout.FillDirection = Enum.FillDirection.Horizontal
		barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		for _, b in ipairs(controls) do b.Size = UDim2.fromOffset(if b.Text == "Map" then 40 elseif b.Text == "Go" then 34 else 30, 30) end
	end
end
layoutMinimap()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutMinimap)
-- Settings › Minimap off hides the whole block (map, region / coordinates strip
-- and its controls); M opens the Sky Chart (hud.client.lua), not this.
local function applyMinimapSetting() holder.Visible = player:GetAttribute("IsleSettingMinimap") ~= false end
applyMinimapSetting()
player:GetAttributeChangedSignal("IsleSettingMinimap"):Connect(applyMinimapSetting)

-- The toast takes the third row of the top lane between the atlas badge and the
-- minimap (shared HUD map in combat.client.lua): y 118-158, x 325..W-SIZE-20.
local function screenSize()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end
local TOAST_WIDTH, TOAST_TOP, TOAST_HEIGHT = 380, 118, 40
local toast = make("TextLabel", gui, {Name = "WayfinderToast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TOAST_TOP),
	Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT), BackgroundColor3 = deep, BackgroundTransparency = 0.1, TextColor3 = gold, Font = bold, TextSize = 14,
	TextWrapped = true, Visible = false, Text = ""})
round(toast, 9, gold)
make("UIPadding", toast, {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)})
local function placeToast()
	local L = lanes()
	local width = L.w
	-- Short phones: a slimmer toast just under the event-banner slot.
	TOAST_TOP, TOAST_HEIGHT = if L.tiny then 111 else 118, if L.tiny then 28 else 40
	local left, right = L.lane.left, L.lane.right
	if TOAST_TOP + TOAST_HEIGHT > L.leftTop then left = math.max(left, 10 + L.leftWidth + 6) end
	if width / 2 - TOAST_WIDTH / 2 >= left and width / 2 + TOAST_WIDTH / 2 <= right then
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Position, toast.Size = UDim2.new(0.5, 0, 0, TOAST_TOP), UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT)
	else
		local w = math.max(200, math.min(TOAST_WIDTH, right - left))
		toast.AnchorPoint = Vector2.new(0, 0)
		toast.Position, toast.Size = UDim2.new(0, left + math.floor((right - left - w) / 2), 0, TOAST_TOP), UDim2.fromOffset(w, TOAST_HEIGHT)
	end
end
placeToast()
local toastSeq = 0
local function notify(text)
	toastSeq += 1
	local mine = toastSeq
	placeToast()
	toast.Text, toast.Visible = text, true
	task.delay(3.5, function() if toastSeq == mine then toast.Visible = false end end)
end

------------------------------------------------------------------------------
-- Waypoint visuals: beam from the player to a glowing beacon at the target.
------------------------------------------------------------------------------
local waypoint = nil -- Data.Townsfolk waypoint + visuals
local visuals = {}
local function destroyVisuals()
	for _, v in pairs(visuals) do if typeof(v) == "Instance" then v:Destroy() end end
	visuals = {}
end
local function attachPlayer()
	if not visuals.beam then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if visuals.playerAttachment then visuals.playerAttachment:Destroy(); visuals.playerAttachment = nil end
	if root then
		visuals.playerAttachment = make("Attachment", root, {Name = "WayfinderAttachment", Position = Vector3.new(0, -1.5, 0)})
		visuals.beam.Attachment0 = visuals.playerAttachment
	end
end
local function buildVisuals(label)
	destroyVisuals()
	local beacon = make("Part", nil, {Name = "WayfinderBeacon", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Size = Vector3.new(1.2, 60, 1.2), Material = Enum.Material.Neon, Color = gold, Transparency = 0.55})
	local ring = make("Part", beacon, {Name = "WayfinderRing", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, T.ARRIVE_RADIUS * 2, T.ARRIVE_RADIUS * 2), Material = Enum.Material.Neon, Color = mint, Transparency = 0.7})
	local targetAttachment = make("Attachment", beacon, {Name = "BeamTarget", Position = Vector3.new(0, -27, 0)})
	make("PointLight", beacon, {Color = gold, Range = 16, Brightness = 1.2, Shadows = false})
	local beam = make("Beam", beacon, {Attachment1 = targetAttachment, FaceCamera = true, LightEmission = 1, LightInfluence = 0, Segments = 24,
		Width0 = 0.7, Width1 = 0.7, Color = ColorSequence.new(mint, gold), Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.15, 0.35), NumberSequenceKeypoint.new(1, 0.15)})})
	local board = make("BillboardGui", beacon, {Size = UDim2.fromOffset(200, 44), StudsOffset = Vector3.new(0, -22, 0), AlwaysOnTop = true, LightInfluence = 0})
	local plate = make("Frame", board, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = deep, BackgroundTransparency = 0.2})
	round(plate, 8, gold)
	local title = make("TextLabel", plate, {Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 2), BackgroundTransparency = 1, Font = bold, TextSize = 14,
		TextColor3 = gold, Text = label, TextTruncate = Enum.TextTruncate.AtEnd})
	local distance = make("TextLabel", plate, {Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 23), BackgroundTransparency = 1, Font = regular,
		TextSize = 12, TextColor3 = mint, Text = ""})
	beacon.Parent = workspace
	visuals = {beacon = beacon, ring = ring, beam = beam, title = title, distance = distance}
	attachPlayer()
end
-- §43 QC M6: the active waypoint's label is published as the read-only local
-- attribute LocalPlayer.WayfinderActive (nil when none), so other scripts (the
-- tutorial's coach cards) never replace a waypoint the player chose.
local function publishActive()
	local value = if waypoint then waypoint.label else nil
	if player:GetAttribute("WayfinderActive") ~= value then player:SetAttribute("WayfinderActive", value) end
end
local function clearWaypoint(message)
	waypoint = nil
	publishActive()
	destroyVisuals()
	if message then notify(message) end
end
local function placeVisuals(target)
	if not visuals.beacon then return end
	visuals.beacon.CFrame = CFrame.new(target + Vector3.new(0, 27, 0))
	visuals.ring.CFrame = CFrame.new(target + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end
-- quiet (3rd argument): an automatic request (the tutorial) fails without a toast.
local function setWaypoint(specs, label, quiet)
	if type(specs) == "string" then specs = {specs} end
	if type(specs) ~= "table" or #specs == 0 then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local from = root and root.Position
	local target, spec = T.resolveFirst(specs, buildIndex(), from)
	if not target then
		if quiet ~= true then notify("I can't find that on the charts yet. Try again once the isle has loaded.") end
		return
	end
	label = if type(label) == "string" and label ~= "" then label else T.targetLabel(spec)
	waypoint = T.newWaypoint(specs, label, os.clock())
	waypoint.target = target
	publishActive()
	buildVisuals(label)
	placeVisuals(target)
	notify("Waypoint set: " .. label)
end
local request = make("BindableEvent", player, {Name = "WayfinderRequest"})
request.Event:Connect(setWaypoint)
player.CharacterAdded:Connect(function(character)
	character:WaitForChild("HumanoidRootPart", 10)
	attachPlayer()
end)

------------------------------------------------------------------------------
-- Agility & Hunter: the running lap's next obstacle (Highlight + billboard +
-- minimap diamond + "anchor:AgilityNext" waypoint; its position goes to the
-- atlas HUD arrow as the local attribute AgilityNextAt), billboards and toasts
-- for the local player's traps (caught / collapsed; HunterTrapsCollapsed is
-- published for the atlas trap counter), minimap glyphs and Navigate entries
-- for course starts, shortcuts and hunting grounds. Levels for the Navigate
-- list come from snapshots (IsleUpdate and the atlas's IsleSnapshotLocal).
------------------------------------------------------------------------------
local AG, HU = Data.Agility or {}, Data.Hunter or {}
Skill.markerColor = {agility = rgb("62C2B0"), shortcut = rgb("9EE7D2"), hunting = rgb("D9A35E"), trap = mint, next = gold}
Skill.stateColor = {set = rgb("D9C9A0"), caught = mint, collapsed = rgb("EF7D67")}
function Skill.anchorKind(name)
	if string.sub(name, 1, 24) == "Anchor_Waypoint_Agility_" then return "agility" end
	if string.sub(name, 1, 25) == "Anchor_Waypoint_Shortcut_" then return "shortcut" end
	if string.sub(name, 1, 24) == "Anchor_Waypoint_Hunting_" then return "hunting" end
	return nil
end
function Skill.acceptSnapshot(snapshot)
	if type(snapshot) ~= "table" then return end
	local levels = snapshot.levels
	local skills = type(snapshot.depth) == "table" and snapshot.depth.skills
	for _, skill in ipairs({"Agility", "Hunter"}) do
		local entry = type(skills) == "table" and skills[skill]
		local level = (type(entry) == "table" and entry.level) or (type(levels) == "table" and levels[skill])
		if type(level) == "number" then Skill.levels[skill] = level end
	end
end
task.spawn(function()
	local updates = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if updates then updates.OnClientEvent:Connect(Skill.acceptSnapshot) end
	local channel = ReplicatedStorage:WaitForChild("IsleSnapshotLocal", 30)
	if channel then
		channel.Event:Connect(Skill.acceptSnapshot)
		local ask = ReplicatedStorage:FindFirstChild("IsleActionLocal")
		if ask then ask:Fire("snapshot") end
	end
end)

-- Own traps ------------------------------------------------------------------
local function creatureOf(id) return HU.CreatureById and HU.CreatureById[id] end
function Skill.board(host, entry)
	if entry.board then entry.board:Destroy(); entry.board = nil end
	local state = entry.shown
	if not state then return end
	local creature = creatureOf(entry.creature)
	local loud = state == "caught" or state == "collapsed"
	local color = Skill.stateColor[state]
	local board = make("BillboardGui", host, {Name = "TrapPing", Size = UDim2.fromOffset(if loud then 132 else 104, 34), StudsOffset = Vector3.new(0, 3.2, 0),
		AlwaysOnTop = loud, LightInfluence = 0, MaxDistance = if loud then 240 else 60})
	local plate = make("Frame", board, {Name = "Plate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = deep, BackgroundTransparency = 0.12})
	round(plate, 10, color)
	local icon = make("TextLabel", plate, {Name = "Icon", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = if creature then rgb(creature.color) else slate, Text = if state == "caught" then "✦" elseif state == "collapsed" then "✕" else "⌖",
		Font = bold, TextSize = 15, TextColor3 = ivory, TextStrokeTransparency = 0.35, TextStrokeColor3 = deep})
	round(icon, "circle", color)
	make("TextLabel", plate, {Name = "State", Position = UDim2.fromOffset(34, 3), Size = UDim2.new(1, -38, 0, 15), BackgroundTransparency = 1, Font = bold,
		TextSize = 13, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left,
		Text = if state == "caught" then "CAUGHT!" elseif state == "collapsed" then "COLLAPSED" else "SET"})
	make("TextLabel", plate, {Name = "Creature", Position = UDim2.fromOffset(34, 18), Size = UDim2.new(1, -38, 0, 13), BackgroundTransparency = 1, Font = regular,
		TextSize = 11, TextColor3 = muted, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = if creature then creature.name else ""})
	entry.board = board
end
function Skill.publishTraps()
	local collapsed = 0
	for _, entry in pairs(Skill.traps) do if entry.shown == "collapsed" then collapsed += 1 end end
	if player:GetAttribute("HunterTrapsCollapsed") ~= collapsed then player:SetAttribute("HunterTrapsCollapsed", collapsed) end
end
function Skill.updateTrap(host)
	local entry = Skill.traps[host]
	if not entry then return end
	local state = host:GetAttribute("TrapState")
	local mine = host:GetAttribute("TrapOwner") == player.UserId
	local shown = if mine and (state == "set" or state == "caught" or state == "collapsed") then state else nil
	if shown == entry.shown then return end
	entry.shown = shown
	Skill.board(host, entry)
	local creature = creatureOf(entry.creature)
	local method = creature and HU.Methods[creature.method]
	local what = if method then string.lower(method.name) else "trap"
	local name = if creature then creature.name else "creature"
	if shown == "caught" then notify("✦ Your " .. what .. " caught a " .. name .. "! Collect it.")
	elseif shown == "collapsed" then notify("Your " .. what .. " for the " .. name .. " collapsed empty. Set it again.") end
	Skill.publishTraps()
end
function Skill.watchTrap(prompt, creature)
	local host = prompt.Parent
	if not host or not host:IsA("BasePart") or Skill.traps[host] then return end
	Skill.traps[host] = {prompt = prompt, creature = creature}
	host:GetAttributeChangedSignal("TrapState"):Connect(function() Skill.updateTrap(host) end)
	host:GetAttributeChangedSignal("TrapOwner"):Connect(function() Skill.updateTrap(host) end)
	Skill.updateTrap(host)
end
for _, pair in ipairs(Skill.pending) do Skill.watchTrap(pair[1], pair[2]) end
Skill.pending = {}

-- Next obstacle ----------------------------------------------------------------
function Skill.clearNext()
	if Skill.next.highlight then Skill.next.highlight:Destroy() end
	if Skill.next.board then Skill.next.board:Destroy() end
	Skill.next = {}
	if player:GetAttribute("AgilityNextAt") ~= nil then player:SetAttribute("AgilityNextAt", nil) end
end
function Skill.refreshNext()
	local run = player:GetAttribute("AgilityRun")
	local course, index, total
	if type(run) == "string" then course, index, total = string.match(run, "^(%w+):(%d+):(%d+)$") end
	local key = if course then course .. ":" .. index else nil
	-- A lap the server has not cleared yet but whose step window has passed.
	local expires = player:GetAttribute("AgilityRunExpires")
	if key and type(expires) == "number" and expires > 0 and os.time() > expires + 1 then key = nil end
	if key == Skill.next.key and (key == nil or (Skill.next.host and Skill.next.host.Parent)) then return end
	Skill.clearNext()
	if not key then return end
	local prompt
	for p, k in pairs(Skill.obstacles) do if k == key and p.Parent then prompt = p; break end end
	local host = prompt and prompt.Parent
	if not host or not host:IsA("BasePart") then return end -- not streamed in yet: retried every tick
	local def = AG.CourseById and AG.CourseById[course]
	local obstacle = def and def.obstacles[tonumber(index)]
	local kind = obstacle and AG.Kinds[obstacle.kind]
	local color = if def then rgb(def.color) else gold
	Skill.next = {key = key, host = host}
	Skill.next.highlight = make("Highlight", host, {Name = "AgilityNext", Adornee = host, FillColor = color, FillTransparency = 0.45, OutlineColor = gold,
		OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop})
	local board = make("BillboardGui", host, {Name = "AgilityNextBoard", Size = UDim2.fromOffset(176, 40), StudsOffset = Vector3.new(0, 4.6, 0),
		AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 400})
	local plate = make("Frame", board, {Name = "Plate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = deep, BackgroundTransparency = 0.12})
	round(plate, 10, gold)
	make("TextLabel", plate, {Name = "Step", Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 14), BackgroundTransparency = 1, Font = bold,
		TextSize = 11, TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Left, Text = "NEXT  ·  " .. index .. " / " .. total})
	make("TextLabel", plate, {Name = "Obstacle", Position = UDim2.fromOffset(8, 18), Size = UDim2.new(1, -16, 0, 18), BackgroundTransparency = 1, Font = bold,
		TextSize = 14, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = (if kind then kind.verb .. " " else "") .. (if obstacle then obstacle.name else "obstacle")})
	Skill.next.board = board
	player:SetAttribute("AgilityNextAt", host.Position)
end
player:GetAttributeChangedSignal("AgilityRun"):Connect(Skill.refreshNext)
-- Gentle pulse on caught pings and the next-obstacle board (≤ 10 Hz, from the map loop).
function Skill.pulse(now)
	local s = 1 + 0.07 * math.sin(now * 6)
	for _, entry in pairs(Skill.traps) do
		if entry.board and entry.shown == "caught" then entry.board.Size = UDim2.fromOffset(math.floor(132 * s), math.floor(34 * s)) end
	end
	if Skill.next.board then Skill.next.board.StudsOffset = Vector3.new(0, 4.6 + 0.3 * math.sin(now * 3), 0) end
end

-- A shortcut end is locked when the region it lands in is (ShortcutRegion on
-- its prompt; the nearest end's anchor spec "anchor:Waypoint_Shortcut_<id>_<A|B>").
function Skill.shortcutLocked(id, spec)
	local tag = type(spec) == "string" and string.match(spec, "_([AB])$")
	for prompt, info in pairs(Skill.shortcutEnds) do
		if info.id == id and (tag == nil or info.tag == tag) then
			local region = prompt:GetAttribute("ShortcutRegion")
			if type(region) == "string" and region ~= "" and player:GetAttribute(region .. "Unlocked") == false then return true end
		end
	end
	return false
end

-- Navigate entries ---------------------------------------------------------------
function Skill.navigate(index, heading, entry, nextOrder)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local from = root and root.Position
	local function level(skill) return Skill.levels[skill] or 1 end
	-- Nearest end first, so the waypoint picks the closer side of a shortcut.
	local function nearestFirst(specs)
		local scored = {}
		for _, spec in ipairs(specs) do
			local pos = T.resolveTarget(spec, index, from)
			if pos then table.insert(scored, {spec, if from then (pos - from).Magnitude else 0}) end
		end
		table.sort(scored, function(a, b) return a[2] < b[2] end)
		local out = {}
		for _, s in ipairs(scored) do table.insert(out, s[1]) end
		return out
	end
	if Skill.next.host and Skill.next.host.Parent then
		heading("AGILITY LAP", nextOrder())
		entry("› Next obstacle", nextOrder(), function() setWaypoint({"anchor:AgilityNext"}, "Next obstacle") end)
	end
	local function section(title, list)
		if #list == 0 then return end
		heading(title, nextOrder())
		for _, item in ipairs(list) do
			entry(item.text .. (if item.locked then "  🔒" else ""), nextOrder(), function() setWaypoint(item.specs, item.label) end, item.locked)
		end
	end
	local courses, shortcuts, grounds = {}, {}, {}
	for _, course in ipairs(AG.Courses or {}) do
		local specs = {"anchor:Waypoint_Agility_" .. course.id}
		if T.resolveFirst(specs, index) then
			table.insert(courses, {text = course.name .. " · Lv " .. course.level, label = course.name, specs = specs, locked = level("Agility") < course.level})
		end
	end
	for _, sc in ipairs(AG.Shortcuts or {}) do
		local specs = nearestFirst({"anchor:Waypoint_Shortcut_" .. sc.id .. "_A", "anchor:Waypoint_Shortcut_" .. sc.id .. "_B"})
		if #specs > 0 then
			table.insert(shortcuts, {text = sc.name .. " · Lv " .. sc.level, label = sc.name, specs = specs,
				locked = level("Agility") < sc.level or Skill.shortcutLocked(sc.id, specs[1])})
		end
	end
	for _, creature in ipairs(HU.Creatures or {}) do
		local specs = {"anchor:Waypoint_Hunting_" .. creature.id}
		if T.resolveFirst(specs, index) then
			table.insert(grounds, {text = creature.name .. " · Lv " .. creature.level, label = creature.name, specs = specs, locked = level("Hunter") < creature.level})
		end
	end
	section("AGILITY COURSES", courses)
	section("SHORTCUTS", shortcuts)
	section("HUNTING GROUNDS", grounds)
end

------------------------------------------------------------------------------
-- Navigate list (stations, regions, townsfolk, recall).
------------------------------------------------------------------------------
local list = make("Frame", gui, {Name = "Navigate", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, SIZE + 46),
	Size = UDim2.fromOffset(240, 300), BackgroundColor3 = ink, Visible = false, BorderSizePixel = 0})
-- Below the minimap when there is room; on short screens (phone landscape) it
-- opens beside the minimap from the top instead. Never past the action bar.
local LIST_FLOOR = 48 -- the atlas action bar (bottom 40) plus a gap
local function placeList()
	local L = lanes()
	local height = L.h
	local below = L.leftTop
	local floor = height - L.action.y + 6
	list.AnchorPoint = Vector2.new(0, 0)
	if height - below - floor >= 200 then
		list.Position = UDim2.fromOffset(10, below)
		list.Size = UDim2.fromOffset(240, math.min(300, height - below - floor))
	else
		list.Position = UDim2.fromOffset(L.lane.left, 8) -- right of the status orbs (§34)
		list.Size = UDim2.fromOffset(240, math.max(120, math.min(300, height - 8 - floor)))
	end
end
make("UISizeConstraint", list, {MaxSize = Vector2.new(260, 380)})
round(list, 12, gold)
make("TextLabel", list, {Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -50, 0, 24), BackgroundTransparency = 1, Text = "NAVIGATE", Font = bold,
	TextSize = 13, TextColor3 = mint, TextXAlignment = Enum.TextXAlignment.Left})
local listClose = make("TextButton", list, {Position = UDim2.new(1, -34, 0, 6), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Text = "✕",
	Font = bold, TextSize = 15, TextColor3 = muted})
local scroll = make("ScrollingFrame", list, {Position = UDim2.fromOffset(8, 34), Size = UDim2.new(1, -16, 1, -42), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = gold, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y})
make("UIListLayout", scroll, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
listClose.Activated:Connect(function() list.Visible = false end)
local action = ReplicatedStorage:WaitForChild("IsleAction", 30)
local function recall(target)
	if not action then return end
	local ok, result = pcall(action.InvokeServer, action, "recall", target)
	if ok and type(result) == "table" and type(result.message) == "string" then
		notify(result.message)
		if string.sub(result.message, 1, 8) == "Recalled" then list.Visible = false end
	elseif ok and result == nil then notify("One moment…")
	end
end
local function heading(text, order)
	make("TextLabel", scroll, {LayoutOrder = order, Size = UDim2.new(1, -6, 0, 18), BackgroundTransparency = 1, Text = text, Font = bold, TextSize = 11,
		TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Left})
end
local function entry(text, order, onClick, dim)
	local b = make("TextButton", scroll, {LayoutOrder = order, Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = deep, Text = "  " .. text, Font = bold,
		TextSize = 13, TextColor3 = if dim then muted else ivory, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = true})
	round(b, 7, slate)
	b.Activated:Connect(function() list.Visible = false; onClick() end)
end
navigatePanel = function()
	if list.Visible then list.Visible = false; return end
	placeList()
	for _, c in ipairs(scroll:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	local index = buildIndex()
	local order = 0
	local function nextOrder() order += 1; return order end
	if waypoint then entry("✕ Clear waypoint (" .. waypoint.label .. ")", nextOrder(), function() clearWaypoint("Waypoint cleared.") end) end
	heading("RECALL CHARM", nextOrder())
	entry("Return Home", nextOrder(), function() recall("Home") end)
	entry("Return to Compass Quay", nextOrder(), function() recall("Hub") end)
	if #index.warpReturn > 0 then entry("Nearest homeward beacon", nextOrder(), function() setWaypoint({"warpReturn"}) end) end
	heading("TOWNSFOLK", nextOrder())
	for _, role in ipairs(T.Order) do
		if index.npcs[role] then
			local def = T.NPCs[role]
			entry(def.name .. " · " .. def.title, nextOrder(), function() setWaypoint({"npc:" .. role}) end)
		end
	end
	heading("STATIONS", nextOrder())
	for _, station in ipairs({"Forge", "Hearth", "Cauldron", "Workbench", "Slayer"}) do
		local specs = {"station:" .. station, "anchor:Waypoint_" .. station}
		if T.resolveFirst(specs, index) then entry(station, nextOrder(), function() setWaypoint(specs, station) end) end
	end
	for _, vendor in ipairs({{"SkymarkExchange", "Skymark Exchange"}, {"TrackersLodge", "Trackers' Lodge"},
		{"Jeweller", "Jeweller's Bench"}, {"Tannery", "Tanning Rack"}, {"Glassworks", "Glass Furnace"}}) do -- Crafting stations
		local specs = {"anchor:Waypoint_" .. vendor[1]}
		if T.resolveFirst(specs, index) then entry(vendor[2], nextOrder(), function() setWaypoint(specs, vendor[2]) end) end
	end
	-- Beaconry (§37): the regional beacon pyres (anchors Waypoint_Beacon_<id>).
	local BC = Data.Beaconry
	for _, id in ipairs(BC and BC.BeaconOrder or {}) do
		local name = BC.Beacons[id].name
		local specs = {"anchor:Waypoint_Beacon_" .. id}
		if T.resolveFirst(specs, index) then entry(name, nextOrder(), function() setWaypoint(specs, name) end) end
	end
	-- Exploration & Factions: the hub Mote Shrine and the three faction standards
	-- (world anchors Waypoint_MoteShrine / Waypoint_Faction_<id>); a locked
	-- region's entry is dimmed with a padlock, like the region list below.
	local EX, FA = Data.Exploration, Data.Factions
	if type(EX) == "table" and type(FA) == "table" then
		local sites = {}
		if T.resolveFirst({"anchor:Waypoint_MoteShrine"}, index) then
			table.insert(sites, {text = "Mote Shrine", label = "Mote Shrine", specs = {"anchor:Waypoint_MoteShrine"}, region = EX.IsleRegion[EX.ShrineIsle.Hub]})
		end
		for _, id in ipairs(FA.Order) do
			local def = FA.Factions[id]
			local specs = {"anchor:Waypoint_Faction_" .. id}
			if def and T.resolveFirst(specs, index) then
				table.insert(sites, {text = def.name .. " standard", label = def.name, specs = specs, region = EX.IsleRegion[def.isle]})
			end
		end
		if #sites > 0 then
			heading("EXPLORATION", nextOrder())
			for _, site in ipairs(sites) do
				local locked = site.region ~= nil and player:GetAttribute(site.region .. "Unlocked") == false
				entry(site.text .. (if locked then "  🔒" else ""), nextOrder(), function() setWaypoint(site.specs, site.label) end, locked)
			end
		end
	end
	Skill.navigate(index, heading, entry, nextOrder)
	heading("REGIONS", nextOrder())
	for _, region in ipairs(Data.Regions) do
		local specs = {"warp:" .. region.id, "region:" .. region.id}
		if T.resolveFirst(specs, index) then
			local locked = player:GetAttribute(region.id .. "Unlocked") == false
			entry(region.name .. (if locked then "  🔒" else ""), nextOrder(), function() setWaypoint({"region:" .. region.id, "warp:" .. region.id}, region.name) end, locked)
		end
	end
	list.Visible = true
end

-- Region under the player (nearest island whose footprint holds them): the
-- minimap strip and the IsleRegionHere attribute the sidebar reads.
local Here = {region = nil, coords = "", tint = {}}
for _, isle in ipairs(Theme.WorldMap.islands) do Here.tint[isle.region] = Here.tint[isle.region] or Theme.darken(rgb(isle.top), 0.35) end
function Here.update(pos)
	local best, bestD = nil, math.huge
	for _, island in ipairs(scan.list) do
		local dx, dz = pos.X - island.center.X, pos.Z - island.center.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= island.radius * 1.2 and d < bestD then best, bestD = island, d end
	end
	local region = if best then (best.region or "Home") else "Skyways"
	if region ~= Here.region then
		Here.region = region
		local def = Data.RegionById[region]
		regionLabel.Text = if def then def.name elseif region == "Home" then "Your Isle" else "The Skyways"
		if player:GetAttribute("IsleRegionHere") ~= region then player:SetAttribute("IsleRegionHere", region) end
	end
	local coords = math.floor(pos.X + 0.5) .. ", " .. math.floor(pos.Y + 0.5) .. ", " .. math.floor(pos.Z + 0.5)
	if coords ~= Here.coords then Here.coords = coords; coordsLabel.Text = coords end
end
------------------------------------------------------------------------------
-- Minimap drawing (≤ 10 Hz) with pooled markers.
------------------------------------------------------------------------------
local pool = {} -- [key] = frame
local seen = {}
local function marker(key, kind)
	local f = pool[key]
	if f then
		seen[key] = true
		if f.Visible == false then f.Visible = true end
		return f
	end
	if kind == "island" then
		f = make("Frame", layer, {AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = slate, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 2})
		round(f, "circle", rgb("2E5E6E"))
		make("TextLabel", f, {Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(110, 14),
			BackgroundTransparency = 1, Font = bold, TextSize = 10, TextColor3 = ivory, TextStrokeTransparency = 0.4, ZIndex = 4})
	elseif kind == "agility" or kind == "shortcut" or kind == "hunting" or kind == "trap" or kind == "next" then
		-- Skill sites: a small glyph (course start, shortcut, hunting ground, own trap, next obstacle).
		local glyph = ({agility = "◆", shortcut = "»", hunting = "⌖", trap = "●", next = "◆"})[kind]
		local size = if kind == "next" then 14 else 12
		f = make("TextLabel", layer, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Text = glyph,
			Font = bold, TextSize = size, TextColor3 = Skill.markerColor[kind] or mint, TextStrokeTransparency = 0.3, TextStrokeColor3 = deep,
			ZIndex = if kind == "next" then 8 else 5})
	elseif kind == "waypoint" then
		f = make("Frame", layer, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(11, 11), Rotation = 45, BackgroundColor3 = gold, BorderSizePixel = 0, ZIndex = 8})
		make("UIStroke", f, {Color = deep, Thickness = 1.5})
	else
		local color = if kind == "npc" then gold elseif kind == "warp" then violet else mint
		f = make("Frame", layer, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 5})
		round(f, "circle", deep)
	end
	if mapArt then mapArt.styleMarker(f, kind, key) end -- Map Art (§32)
	pool[key] = f
	seen[key] = true
	return f
end
local function drawMap(me, facing)
	table.clear(seen)
	local scale = ZOOMS[zoom]
	local half = SIZE / 2
	local function project(pos)
		return (pos.X - me.X) * scale, (pos.Z - me.Z) * scale
	end
	local function visible(x, y, pad) return math.abs(x) <= half + pad and math.abs(y) <= half + pad end
	if mapArt then mapArt.draw(me, scale, half, scan.list) end -- Map Art (§32): island plates
	for _, island in ipairs(scan.list) do
		local x, y = project(island.center)
		local r = island.radius * scale
		if visible(x, y, r) then
			local f = marker(island.model, "island")
			if mapArt then mapArt.dress(f) end
			f.Position = UDim2.fromOffset(half + x, half + y)
			f.Size = UDim2.fromOffset(r * 2, r * 2)
			local region = Data.RegionById[island.region or ""]
			local label = f:FindFirstChild("Label")
			local tint = Here.tint[island.region or ""]
			if tint and f.BackgroundColor3 ~= tint then f.BackgroundColor3 = tint end
			label.Text = if island.region == "Home" or not region and island.region == nil then "Home" else island.model.Name
			label.Visible = r > 24
		end
	end
	local folder = workspace:FindFirstChild("Townsfolk")
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local x, y = project(root.Position)
				if visible(x, y, 0) then marker(model, "npc").Position = UDim2.fromOffset(half + x, half + y) end
			end
		end
	end
	for kind, set in pairs(prompts) do
		if kind ~= "gather" then
			for prompt in pairs(set) do
				local pos = promptPosition(prompt)
				if pos then
					local x, y = project(pos)
					if visible(x, y, 0) then marker(prompt, if kind == "station" then "station" else "warp").Position = UDim2.fromOffset(half + x, half + y) end
				end
			end
		end
	end
	-- Skill sites from the island anchors (course starts, shortcut ends, hunting grounds).
	for name, parts in pairs(scan.anchors) do
		local kind = Skill.anchorKind(name)
		if kind then
			for i, part in ipairs(parts) do
				if part.Parent then
					local x, y = project(part.Position)
					if visible(x, y, 0) then marker(name .. "#" .. i, kind).Position = UDim2.fromOffset(half + x, half + y) end
				end
			end
		end
	end
	for host, entry in pairs(Skill.traps) do
		if entry.shown and host.Parent then
			local x, y = project(host.Position)
			if visible(x, y, 0) then
				local f = marker(host, "trap")
				f.Position = UDim2.fromOffset(half + x, half + y)
				f.TextColor3 = Skill.stateColor[entry.shown] or mint
			end
		end
	end
	local nextAt = Skill.next.host and Skill.next.host.Parent and Skill.next.host.Position
	if nextAt then
		local x, y = project(nextAt)
		local edge = half - 7
		local m = math.max(math.abs(x), math.abs(y))
		if m > edge then x, y = x / m * edge, y / m * edge end
		marker("agilityNext", "next").Position = UDim2.fromOffset(half + x, half + y)
	end
	if waypoint and waypoint.target then
		local x, y = project(waypoint.target)
		local edge = half - 7
		local m = math.max(math.abs(x), math.abs(y))
		if m > edge then x, y = x / m * edge, y / m * edge end -- clamp to the rim
		local f = marker("waypoint", "waypoint")
		f.Position = UDim2.fromOffset(half + x, half + y)
		f.BackgroundTransparency = if m > edge then 0.25 else 0
	end
	-- Off-map markers hide (pooled, shown again when back in view); a marker is
	-- destroyed only when the instance it tracks has left the world.
	for key, f in pairs(pool) do
		if not seen[key] then
			if typeof(key) == "Instance" and key.Parent == nil then f:Destroy(); pool[key] = nil
			elseif f.Visible ~= false then f.Visible = false end
		end
	end
	arrow.Rotation = math.deg(math.atan2(facing.X, -facing.Z))
end

local mapClock, resolveClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	mapClock += dt
	if mapClock < T.MINIMAP_INTERVAL then return end
	mapClock = 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	if waypoint then
		-- Re-resolve once a second (NPCs can move when late anchors appear).
		local target = waypoint.target
		if now - resolveClock >= 1 then
			resolveClock = now
			target = T.resolveFirst(waypoint.specs, buildIndex(), root and root.Position)
			if target then placeVisuals(target) end
		end
		local status = T.stepWaypoint(waypoint, root and root.Position, target, now)
		if status == "arrived" then clearWaypoint("Arrived: " .. waypoint.label)
		elseif status == "expired" then clearWaypoint("Waypoint expired.")
		elseif status == "lost" then clearWaypoint("Lost the trail to " .. waypoint.label .. ".")
		elseif visuals.distance and waypoint.distance then
			visuals.distance.Text = math.floor(waypoint.distance) .. " studs"
			if visuals.beam and not visuals.beam.Attachment0 then attachPlayer() end
		end
	end
	Skill.refreshNext()
	Skill.pulse(now)
	if root then Here.update(root.Position) end
	if mapOpen and root and player:GetAttribute("IsleSettingMinimap") ~= false then
		local look = root.CFrame.LookVector
		drawMap(root.Position, look)
	end
end)
