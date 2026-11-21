-- Townsfolk: the isles' NPCs (Data.Townsfolk) and the validated recall charm.
-- Rigs are R15-style blocky figures built from parts (no uploaded assets). Each
-- stands on its Anchor_NPC_<Role> part under Workspace.Islands, or on a ring
-- around its island's IslandCenter until that anchor appears (contract §10).
-- Islands and anchors may arrive late; placement re-runs (debounced) whenever
-- the Islands folder changes. Client scripts animate idles and run dialogue.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = Data.Townsfolk
local V, CF = Vector3.new, CFrame.new

local folder = Instance.new("Folder")
folder.Name = "Townsfolk"
folder.Parent = workspace
local stash = Instance.new("Folder")
stash.Name = "TownsfolkUnplaced"
stash.Parent = ServerStorage

------------------------------------------------------------------------------
-- Rig construction.
------------------------------------------------------------------------------
local SM, WOOD, METAL, NEON, FABRIC, GLASS = Enum.Material.SmoothPlastic, Enum.Material.Wood, Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Fabric, Enum.Material.Glass
local function hex(h) return Color3.fromHex(h) end
local function piece(parent, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cframe, color, material or SM
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false, true
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end
local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
	return w
end
local function motor(name, part0, part1, at)
	local m = Instance.new("Motor6D")
	m.Name, m.Part0, m.Part1 = name, part0, part1
	m.C0, m.C1 = part0.CFrame:Inverse() * at, part1.CFrame:Inverse() * at
	m.Parent = part1
	return m
end
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X → Y

local function hat(head, style, look)
	local top = head.CFrame * CF(0, 0.6, 0)
	local accent, shirt = hex(look.accent), hex(look.shirt)
	local function add(name, size, cf, color, material, shape) weld(head, piece(head.Parent, name, size, cf, color, material, shape)) end
	if style == "wayfarer" then
		add("HatBrim", V(0.14, 2.3, 2.3), top * CF(0, 0.05, 0) * VERTICAL, hex("4A3B2A"), FABRIC, Enum.PartType.Cylinder)
		add("HatCrown", V(1.25, 0.6, 1.25), top * CF(0, 0.35, 0), hex("4A3B2A"), FABRIC)
		add("HatBand", V(1.3, 0.16, 1.3), top * CF(0, 0.16, 0), accent, SM)
	elseif style == "tophat" then
		add("HatBrim", V(0.12, 1.75, 1.75), top * CF(0, 0.05, 0) * VERTICAL, hex("1A1A1A"), FABRIC, Enum.PartType.Cylinder)
		add("HatCrown", V(1.1, 1.05, 1.05), top * CF(0, 0.6, 0) * VERTICAL, hex("1A1A1A"), FABRIC, Enum.PartType.Cylinder)
		add("HatBand", V(0.2, 1.08, 1.08), top * CF(0, 0.2, 0) * VERTICAL, accent, SM, Enum.PartType.Cylinder)
	elseif style == "cap" then
		add("Cap", V(1.3, 0.35, 1.3), top * CF(0, 0.12, 0), shirt, FABRIC)
		add("CapVisor", V(1.0, 0.1, 0.55), top * CF(0, 0, -0.85), shirt:Lerp(Color3.new(0, 0, 0), 0.3), FABRIC)
	elseif style == "goggles" then
		add("GoggleStrap", V(1.26, 0.22, 1.26), head.CFrame * CF(0, 0.3, 0), hex("2B2B2B"), SM)
		for _, x in ipairs({-0.28, 0.28}) do
			add("GoggleLens", V(0.12, 0.38, 0.38), head.CFrame * CF(x, 0.32, -0.64) * CFrame.Angles(0, math.pi / 2, 0), accent, GLASS, Enum.PartType.Cylinder)
		end
	elseif style == "helm" then
		add("Helm", V(1.36, 0.75, 1.36), top * CF(0, 0.05, 0.02), hex("6B6F78"), METAL)
		add("HelmCrest", V(0.18, 0.55, 1.2), top * CF(0, 0.55, 0.1), accent, FABRIC)
		add("HelmGuard", V(0.2, 0.55, 0.12), head.CFrame * CF(0, 0.1, -0.66), hex("6B6F78"), METAL)
	elseif style == "souwester" then
		add("HatBrim", V(0.12, 2.0, 2.0), top * CF(0, 0, 0.1) * CFrame.Angles(0.12, 0, 0) * VERTICAL, shirt, SM, Enum.PartType.Cylinder)
		add("HatCrown", V(1.25, 0.55, 1.3), top * CF(0, 0.25, 0.05), shirt, SM)
	elseif style == "tricorn" then
		add("HatBrim", V(0.14, 2.0, 2.0), top * CF(0, 0.05, 0) * VERTICAL, hex("1F1A2B"), FABRIC, Enum.PartType.Cylinder)
		add("HatCrown", V(1.2, 0.55, 1.2), top * CF(0, 0.32, 0), hex("1F1A2B"), FABRIC)
		for i = 0, 2 do
			add("HatTrim", V(1.3, 0.14, 0.12), top * CFrame.Angles(0, i * 2 * math.pi / 3, 0) * CF(0, 0.16, -0.9), accent, SM)
		end
	elseif style == "feather" then
		add("Cap", V(1.3, 0.4, 1.3), top * CF(0, 0.12, 0), shirt, FABRIC)
		add("Feather", V(0.12, 1.4, 0.3), top * CF(0.55, 0.6, 0.2) * CFrame.Angles(0.2, 0, -0.45), accent, FABRIC)
	elseif style == "hood" then
		local cloak = hex(look.cape or look.shirt)
		add("Hood", V(1.42, 1.0, 1.3), head.CFrame * CF(0, 0.35, 0.12), cloak, FABRIC)
		add("HoodBack", V(1.3, 1.1, 0.25), head.CFrame * CF(0, -0.1, 0.62), cloak, FABRIC)
	elseif style == "minerhelm" then
		add("Helm", V(1.34, 0.6, 1.34), top * CF(0, 0.05, 0), hex("C9A227"), METAL)
		add("HelmBrim", V(0.1, 1.6, 1.6), top * CF(0, -0.2, 0) * VERTICAL, hex("A8861F"), METAL, Enum.PartType.Cylinder)
		local lamp = piece(head.Parent, "HelmLamp", V(0.2, 0.4, 0.4), top * CF(0, 0.05, -0.72) * CFrame.Angles(0, math.pi / 2, 0), accent, NEON, Enum.PartType.Cylinder)
		weld(head, lamp)
		local light = Instance.new("SpotLight")
		light.Color, light.Range, light.Brightness, light.Angle, light.Face = accent, 18, 1.4, 50, Enum.NormalId.Left
		light.Parent = lamp
	end
end

local function held(hand, style, look)
	local base = hand.CFrame * CF(0, -0.25, 0)
	local accent = hex(look.accent)
	local function add(name, size, cf, color, material, shape)
		local p = piece(hand.Parent, name, size, cf, color, material, shape)
		weld(hand, p)
		return p
	end
	if style == "lantern" then
		add("LanternHandle", V(0.1, 0.5, 0.1), base * CF(0, -0.2, 0), hex("3A3A3A"), METAL)
		add("LanternFrame", V(0.6, 0.75, 0.6), base * CF(0, -0.75, 0), hex("3A3A3A"), METAL).Transparency = 0.55
		local core = add("LanternCore", V(0.35, 0.5, 0.35), base * CF(0, -0.75, 0), accent, NEON)
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness, light.Shadows = accent, 10, 0.9, false
		light.Parent = core
	elseif style == "ledger" then
		add("Ledger", V(0.3, 1.0, 0.8), base * CF(0, -0.2, -0.2), hex(look.shirt):Lerp(Color3.new(0, 0, 0), 0.35), FABRIC)
		add("LedgerPages", V(0.32, 0.9, 0.7), base * CF(0, -0.2, -0.22), hex("F2E8D5"), SM)
	elseif style == "crate" then
		add("Crate", V(1.2, 0.9, 0.9), base * CF(-0.7, 0, -0.6), hex("9C6B3E"), WOOD)
		add("CrateApples", V(1.0, 0.25, 0.7), base * CF(-0.7, 0.5, -0.6), hex("C0392B"), SM)
	elseif style == "hammer" then
		add("HammerHandle", V(0.18, 1.5, 0.18), base * CF(0, -0.3, 0), hex("6B4226"), WOOD)
		add("HammerHead", V(0.8, 0.45, 0.45), base * CF(0, -1.05, 0), hex("4A4A4A"), METAL)
	elseif style == "sword" then
		add("SwordHilt", V(0.18, 0.5, 0.18), base * CF(0, 0, 0), hex("3B2A1A"), FABRIC)
		add("SwordGuard", V(0.7, 0.14, 0.22), base * CF(0, -0.3, 0), accent, METAL)
		add("SwordBlade", V(0.12, 2.2, 0.3), base * CF(0, -1.45, 0), hex("D8DEE6"), METAL)
	elseif style == "rod" then
		add("RodPole", V(0.12, 4.2, 0.12), base * CF(0, 1.2, -0.9) * CFrame.Angles(-0.55, 0, 0), hex("8B5A2B"), WOOD)
		add("RodReel", V(0.25, 0.3, 0.3), base * CF(0.18, 0, -0.1) * CFrame.Angles(0, 0, math.pi / 2), accent, METAL, Enum.PartType.Cylinder)
	elseif style == "scroll" then
		add("Scroll", V(1.1, 0.3, 0.3), base * CF(0, -0.1, -0.15), hex("F2E8D5"), SM, Enum.PartType.Cylinder)
		add("ScrollRibbon", V(0.15, 0.32, 0.32), base * CF(0, -0.1, -0.15), accent, FABRIC, Enum.PartType.Cylinder)
	elseif style == "horn" then
		add("HornBody", V(1.2, 0.3, 0.3), base * CF(0, 0, -0.2) * CFrame.Angles(0, math.pi / 2, 0), accent, METAL, Enum.PartType.Cylinder)
		add("HornBell", V(0.25, 0.7, 0.7), base * CF(0, 0, -0.85) * CFrame.Angles(0, math.pi / 2, 0), accent, METAL, Enum.PartType.Cylinder)
	elseif style == "saw" then
		add("SawHandle", V(0.25, 0.45, 0.35), base, hex("6B4226"), WOOD)
		add("SawBlade", V(0.06, 1.6, 0.55), base * CF(0, -1.0, -0.05), hex("BFC5CC"), METAL)
	elseif style == "staff" then
		add("StaffPole", V(0.18, 5.0, 0.18), base * CF(0, 0.8, 0), hex("6B4A2E"), WOOD)
		add("StaffGem", V(0.4, 0.4, 0.4), base * CF(0, 3.45, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), accent, NEON)
	elseif style == "pickaxe" then
		add("PickHandle", V(0.18, 1.8, 0.18), base * CF(0, -0.4, 0), hex("6B4226"), WOOD)
		add("PickHead", V(1.4, 0.22, 0.22), base * CF(0, -1.25, 0) * CFrame.Angles(0, 0, 0.12), hex("5B3F8C"), METAL)
	end
end

local function buildRig(role)
	local def = T.NPCs[role]
	local look = def.look
	local skin, shirt, pants, shoes, accent = hex(look.skin), hex(look.shirt), hex(look.pants), hex(look.shoes), hex(look.accent)
	local model = Instance.new("Model")
	model.Name = def.name
	model:SetAttribute("TownsfolkRole", role)
	model:SetAttribute("Region", def.region)
	local root = piece(model, "HumanoidRootPart", V(2, 2, 1), CF(0, 2.55, 0), skin, SM)
	root.Anchored, root.Transparency, root.CanCollide, root.CanQuery = true, 1, true, true
	root.PivotOffset = CF(0, -2.55, 0)
	model.PrimaryPart = root
	local lowerTorso = piece(model, "LowerTorso", V(2, 0.5, 1), CF(0, 2.55, 0), pants, FABRIC)
	local upperTorso = piece(model, "UpperTorso", V(2, 1.5, 1), CF(0, 3.55, 0), shirt, FABRIC)
	local head = piece(model, "Head", V(1.2, 1.2, 1.2), CF(0, 4.92, 0), skin, SM)
	motor("Root", root, lowerTorso, CF(0, 2.55, 0))
	motor("Waist", lowerTorso, upperTorso, CF(0, 2.8, 0))
	motor("Neck", upperTorso, head, CF(0, 4.3, 0))
	weld(upperTorso, piece(model, "Collar", V(2.04, 0.22, 1.04), CF(0, 4.2, 0), accent, FABRIC))
	weld(lowerTorso, piece(model, "Belt", V(2.04, 0.2, 1.04), CF(0, 2.75, 0), shoes, SM))
	weld(lowerTorso, piece(model, "Buckle", V(0.3, 0.22, 0.06), CF(0, 2.75, -0.53), accent, METAL))
	for _, side in ipairs({-1, 1}) do
		local name = if side < 0 then "Left" else "Right"
		local upperArm = piece(model, name .. "UpperArm", V(0.85, 1.15, 0.85), CF(side * 1.45, 3.68, 0), shirt, FABRIC)
		local lowerArm = piece(model, name .. "LowerArm", V(0.8, 0.95, 0.8), CF(side * 1.45, 2.65, 0), shirt:Lerp(skin, 0.15), FABRIC)
		local hand = piece(model, name .. "Hand", V(0.75, 0.42, 0.75), CF(side * 1.45, 1.97, 0), skin, SM)
		motor(name .. "Shoulder", upperTorso, upperArm, CF(side * 1.25, 4.1, 0))
		motor(name .. "Elbow", upperArm, lowerArm, CF(side * 1.45, 3.1, 0))
		motor(name .. "Wrist", lowerArm, hand, CF(side * 1.45, 2.18, 0))
		weld(upperArm, piece(model, name .. "Cuff", V(0.88, 0.16, 0.88), CF(side * 1.45, 3.15, 0), accent, FABRIC))
		local upperLeg = piece(model, name .. "UpperLeg", V(0.92, 1.05, 0.92), CF(side * 0.5, 1.78, 0), pants, FABRIC)
		local lowerLeg = piece(model, name .. "LowerLeg", V(0.86, 0.95, 0.86), CF(side * 0.5, 0.78, 0), pants, FABRIC)
		local foot = piece(model, name .. "Foot", V(0.9, 0.32, 1.12), CF(side * 0.5, 0.16, -0.08), shoes, SM)
		motor(name .. "Hip", lowerTorso, upperLeg, CF(side * 0.5, 2.3, 0))
		motor(name .. "Knee", upperLeg, lowerLeg, CF(side * 0.5, 1.25, 0))
		motor(name .. "Ankle", lowerLeg, foot, CF(side * 0.5, 0.32, 0))
		-- Face: eyes with a highlight, brows.
		local eye = piece(model, name .. "Eye", V(0.17, 0.24, 0.05), CF(side * 0.26, 5.0, -0.61), hex("1B1B22"), SM)
		weld(head, eye)
		weld(head, piece(model, name .. "EyeGlint", V(0.06, 0.07, 0.02), CF(side * 0.26 + 0.04, 5.06, -0.64), Color3.new(1, 1, 1), NEON))
		weld(head, piece(model, name .. "Brow", V(0.3, 0.07, 0.05), CF(side * 0.26, 5.2, -0.61) * CFrame.Angles(0, 0, side * -0.12), hex(look.hair), SM))
		if look.spectacles then
			weld(head, piece(model, name .. "Lens", V(0.05, 0.36, 0.36), CF(side * 0.26, 5.0, -0.65) * CFrame.Angles(0, math.pi / 2, 0), hex("D8E6F0"), GLASS, Enum.PartType.Cylinder)).Part1.Transparency = 0.5
		end
	end
	weld(head, piece(model, "Mouth", V(0.36, 0.07, 0.05), CF(0, 4.66, -0.61), hex("7A3B2E"), SM))
	weld(head, piece(model, "Nose", V(0.16, 0.2, 0.1), CF(0, 4.84, -0.64), skin:Lerp(Color3.new(0, 0, 0), 0.08), SM))
	if look.hat ~= "hood" and look.hat ~= "helm" and look.hat ~= "minerhelm" then
		weld(head, piece(model, "Hair", V(1.28, 0.35, 1.28), CF(0, 5.45, 0.04), hex(look.hair), FABRIC))
		weld(head, piece(model, "HairBack", V(1.28, 0.9, 0.3), CF(0, 5.05, 0.55), hex(look.hair), FABRIC))
	end
	if look.beard then
		weld(head, piece(model, "Beard", V(1.0, 0.55, 0.3), CF(0, 4.48, -0.5), hex(look.hair), FABRIC))
	end
	if look.cape then
		weld(upperTorso, piece(model, "Cape", V(2.1, 3.3, 0.14), CF(0, 2.75, 0.62) * CFrame.Angles(0.06, 0, 0), hex(look.cape), FABRIC))
	end
	if look.apron then
		weld(lowerTorso, piece(model, "Apron", V(1.6, 2.4, 0.1), CF(0, 2.35, -0.56), hex(look.apron), FABRIC))
	end
	hat(head, look.hat, look)
	held(model.RightHand, look.held, look)
	-- Nameplate.
	local board = Instance.new("BillboardGui")
	board.Name, board.Size, board.StudsOffset = "Nameplate", UDim2.fromOffset(220, 52), V(0, 2.4, 0)
	board.MaxDistance, board.LightInfluence, board.AlwaysOnTop = 70, 0, false
	board.Parent = head
	local plate = Instance.new("Frame")
	plate.AnchorPoint, plate.Position, plate.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(0, 200, 0, 46)
	plate.BackgroundColor3, plate.BackgroundTransparency, plate.BorderSizePixel = hex("091923"), 0.25, 0
	plate.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Transparency, stroke.Thickness = hex("F9CC77"), 0.4, 1
	stroke.Parent = plate
	for i, line in ipairs({{def.name, 17, Enum.Font.GothamBold, hex("F9CC77")}, {def.title, 13, Enum.Font.Gotham, hex("9EE7D2")}}) do
		local text = Instance.new("TextLabel")
		text.Name = if i == 1 then "NpcName" else "NpcTitle"
		text.BackgroundTransparency, text.Size, text.Position = 1, UDim2.new(1, -12, 0, 21), UDim2.fromOffset(6, if i == 1 then 3 else 23)
		text.Text, text.TextSize, text.Font, text.TextColor3 = line[1], line[2], line[3], line[4]
		text.TextScaled = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Parent = plate
	end
	-- "Talk" prompt. It carries no IsleAction, so the Adventure server ignores it;
	-- the Dialogue client opens the conversation locally.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "TalkPrompt", "Talk", def.name
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 11, false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("TownsfolkRole", role)
	prompt.Parent = root
	return model
end

------------------------------------------------------------------------------
-- Placement.
------------------------------------------------------------------------------
local npcs = {}
-- World Art regional folk (T.RegionFolkOrder, §30) stand only on their anchors.
local roster = table.clone(T.Order)
for _, role in ipairs(T.RegionFolkOrder or {}) do table.insert(roster, role) end
for _, role in ipairs(roster) do
	local model = buildRig(role)
	model.Parent = stash
	npcs[role] = model
end
local function ground(position)
	local filter = {folder}
	for _, player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(filter, player.Character) end end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(position + V(0, 60, 0), V(0, -160, 0), params)
	return if hit then hit.Position else position
end
local function flatLook(from, toward)
	local target = V(toward.X, from.Y, toward.Z)
	if (target - from).Magnitude < 0.1 then return CF(from) end
	return CFrame.lookAt(from, target)
end
-- World CFrame for an NPC's feet, or nil while its island does not exist.
local function targetFrame(role, scan)
	local spot = T.placement(role, scan)
	if not spot then return nil end
	if spot.source == "anchor" then
		local part = spot.part
		local feet = part.Position - V(0, part.Size.Y / 2, 0)
		local look = part.CFrame.LookVector
		look = V(look.X, 0, look.Z)
		if look.Magnitude < 0.1 then look = V(0, 0, -1) end
		return CFrame.lookAt(feet, feet + look.Unit), "anchor"
	end
	local center = spot.island.center
	local feet = ground(center + V(spot.x, 0, spot.z))
	return flatLook(feet, center), "fallback"
end
local function placeAll()
	local scan = T.scanIslands(workspace:FindFirstChild("Islands"))
	for role, model in pairs(npcs) do
		local cf, source = targetFrame(role, scan)
		if cf then
			if model.Parent ~= folder or (model:GetPivot().Position - cf.Position).Magnitude > 0.05 or model:GetAttribute("Placement") ~= source then
				model:PivotTo(cf)
				model:SetAttribute("Placement", source)
				model.Parent = folder
			end
		elseif model.Parent ~= stash then
			model.Parent = stash
			model:SetAttribute("Placement", nil)
		end
	end
end
local scheduled = false
local function schedule()
	if scheduled then return end
	scheduled = true
	task.delay(0.4, function()
		scheduled = false
		placeAll()
	end)
end
local watched = setmetatable({}, {__mode = "k"})
local function watchIslands(islands)
	if watched[islands] then return end
	watched[islands] = true
	local function consider(d)
		if d.Parent == islands then
			d.AttributeChanged:Connect(schedule) -- IslandCenter / IslandRadius / Region set late
			schedule()
		elseif string.sub(d.Name, 1, 7) == "Anchor_" and d:IsA("BasePart") then
			d:GetPropertyChangedSignal("CFrame"):Connect(schedule)
			schedule()
		end
	end
	islands.DescendantAdded:Connect(consider)
	islands.DescendantRemoving:Connect(function(d)
		if d.Parent == islands or string.sub(d.Name, 1, 7) == "Anchor_" then schedule() end
	end)
	for _, d in ipairs(islands:GetDescendants()) do
		if d.Parent == islands then d.AttributeChanged:Connect(schedule)
		elseif string.sub(d.Name, 1, 7) == "Anchor_" and d:IsA("BasePart") then d:GetPropertyChangedSignal("CFrame"):Connect(schedule) end
	end
	schedule()
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Islands" then watchIslands(child) end
end)
workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Islands" then schedule() end
end)
local existing = workspace:FindFirstChild("Islands")
if existing then watchIslands(existing) end
placeAll()

------------------------------------------------------------------------------
-- Recall charm: ServerStorage.IsleRecall(player, "Hub"|"Home") → message.
-- Called only from the Adventure server's "recall" verb (alive + lease checked
-- there); here: cooldown, recent-damage gate and a server-chosen destination.
------------------------------------------------------------------------------
local lastRecall, lastHurt = {}, {}
local function watchHealth(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or player.Character ~= character then return end
	local health = humanoid.Health
	humanoid.HealthChanged:Connect(function(value)
		if value < health - 0.01 then lastHurt[player] = os.clock() end
		health = value
	end)
end
local function trackPlayer(player)
	player.CharacterAdded:Connect(function(character) watchHealth(player, character) end)
	if player.Character then task.spawn(watchHealth, player, player.Character) end
end
Players.PlayerAdded:Connect(trackPlayer)
for _, player in ipairs(Players:GetPlayers()) do trackPlayer(player) end
Players.PlayerRemoving:Connect(function(player) lastRecall[player], lastHurt[player] = nil, nil end)

local LANDING_ANCHORS = {"Anchor_Landing", "Anchor_Spawn", "Anchor_Waypoint_Landing", "Anchor_Recall"}
local function hubDestination()
	local scan = T.scanIslands(workspace:FindFirstChild("Islands"))
	local hub = scan.regions.Hub
	if not hub then return nil end
	for _, name in ipairs(LANDING_ANCHORS) do
		for _, part in ipairs(scan.anchors[name] or {}) do
			if part:IsDescendantOf(hub.model) then return part.Position + V(0, part.Size.Y / 2, 0) end
		end
	end
	return ground(hub.center)
end
local function homeDestination(player)
	local spawn = player.RespawnLocation
	if spawn and spawn.Parent then return spawn.Position + V(0, spawn.Size.Y / 2, 0) end
	local center = player:GetAttribute("IslandCenter")
	if typeof(center) == "Vector3" then return ground(center) end
	return nil
end
-- Expedition runs (expedition.server.lua) keep their delvers in the Hollow
-- Observatory: the core around the Eclipse Heart and the sentinel hall 110 studs
-- behind it, with delvers dropped beyond 120 studs. A recall there would pull a
-- delver out without leaving the run (and let them collect the clear from
-- outside), so it is refused anywhere within reach of the heart. The heart is the
-- arena part carrying the BossName attribute; it never moves.
local EXPEDITION_ARENA, EXPEDITION_REACH = "The Hollow Observatory", 240
local expeditionHeart
local function inExpedition(root)
	if not expeditionHeart or not expeditionHeart:IsDescendantOf(workspace) then
		expeditionHeart = nil
		local arena = workspace:FindFirstChild(EXPEDITION_ARENA)
		if not arena then return false end
		for _, part in ipairs(arena:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("BossName") ~= nil then expeditionHeart = part; break end
		end
		if not expeditionHeart then return false end
	end
	return (root.Position - expeditionHeart.Position).Magnitude <= EXPEDITION_REACH
end
local recall = Instance.new("BindableFunction")
recall.Name = "IsleRecall"
recall.OnInvoke = function(player, target)
	local now = os.clock()
	local ok, message = T.recallCheck(target, now, lastRecall[player], lastHurt[player])
	if not ok then return message end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return "Return to your island first." end
	if inExpedition(root) then return "The Observatory holds you. Finish or leave the expedition first." end
	local destination = if target == "Hub" then hubDestination() else homeDestination(player)
	if not destination then return "That isle isn't charted yet. Try a beacon instead." end
	lastRecall[player] = now
	player:SetAttribute("FastTravelAt", os.clock()) -- known fast travel (Aether Mote pickup checks)
	character:PivotTo(CF(destination + V(0, 3.5, 0)) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	return message
end
recall.Parent = ServerStorage

-- Travel gate: ServerStorage.IsleTravelGate(player) → true, or the refusal
-- message. The recall charm's location gates without its cooldown or a move,
-- for other server-side travel (Treasure Trails waystone leaves): alive, not
-- within T.RECALL_HURT_GRACE of taking damage, not inside an expedition.
local travelGate = Instance.new("BindableFunction")
travelGate.Name = "IsleTravelGate"
travelGate.OnInvoke = function(player)
	local hurt = lastHurt[player]
	if hurt and os.clock() - hurt < T.RECALL_HURT_GRACE then return "You can't travel mid-fight. Catch your breath first." end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return "Return to your island first." end
	if inExpedition(root) then return "The Observatory holds you. Finish or leave the expedition first." end
	return true
end
travelGate.Parent = ServerStorage
