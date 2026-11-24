-- Regions (client, World Art & Regions team; docs/DEPTH-CONTRACT.md §30).
-- * Entry banner: when the player's feet enter another island of
--   Workspace.Islands (IslandCenter / IslandRadius), a title card fades in
--   with the island name (IsleTitle), its epithet and the region line
--   (RegionTitle · RegionEpithet) in the region's accent colour.
-- * Ambience: an optional looped Sound when the island's AmbientSound names
--   an asset (hook; empty by default). The island's particles (its Ambience
--   attribute: pollen, embers, spores...) are drawn by the §50 ambience layer
--   (ambience.client.lua, one palette in shared/Ambience.lua, counted in its
--   emitter cap); this script no longer runs a second camera emitter.
-- * Spin: parts tagged RegionSpin (the Sunwheel sails) turn locally about
--   their look axis at SpinRate rad/s within SPIN_RANGE studs (the forge's
--   landmark distance: 1,200 desktop / 900 phone, so a forged sail never
--   hangs frozen in view); the forge's mesh
--   follows its host's CFrame. Nothing here touches the server or lighting.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Tags = game:GetService("CollectionService")
local player = Players.LocalPlayer

------------------------------------------------------------------------------
-- Banner.
------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.IgnoreGuiInset = "RegionBanner", false, 4, true
gui.Parent = player:WaitForChild("PlayerGui")
local card = Instance.new("CanvasGroup")
card.Name, card.AnchorPoint, card.Position, card.Size = "Card", Vector2.new(.5, 0), UDim2.new(.5, 0, 0, 96), UDim2.fromOffset(460, 92)
card.BackgroundTransparency, card.GroupTransparency, card.Visible = 1, 1, false
card.Parent = gui
local size = Instance.new("UISizeConstraint")
size.MaxSize = Vector2.new(460, 92)
size.Parent = card
local function label(name, y, h, text, font, color)
	local t = Instance.new("TextLabel")
	t.Name, t.BackgroundTransparency, t.Position, t.Size = name, 1, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, h)
	t.Font, t.TextColor3, t.TextScaled, t.Text = font, color, true, text
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.Transparency = Color3.fromRGB(12, 18, 26), 2, .2
	stroke.Parent = t
	t.Parent = card
	return t
end
local kicker = label("Region", 0, 18, "", Enum.Font.GothamBold, Color3.fromHex("9EE7D2"))
local title = label("Title", 20, 44, "", Enum.Font.Antique, Color3.fromHex("FFF4D9"))
local rule = Instance.new("Frame")
rule.Name, rule.AnchorPoint, rule.Position, rule.Size, rule.BorderSizePixel = "Rule", Vector2.new(.5, 0), UDim2.new(.5, 0, 0, 66), UDim2.fromOffset(220, 2), 0
rule.Parent = card
local epithet = label("Epithet", 70, 20, "", Enum.Font.Gotham, Color3.fromHex("E8E2D0"))
local showToken = 0
local function show(model)
	showToken += 1
	local token = showToken
	local accent = model:GetAttribute("RegionAccent")
	accent = if typeof(accent) == "Color3" then accent else Color3.fromHex("F9CC77")
	kicker.Text = string.upper((model:GetAttribute("RegionTitle") or "") .. "  ·  " .. (model:GetAttribute("RegionEpithet") or ""))
	kicker.TextColor3, rule.BackgroundColor3 = accent, accent
	title.Text = model:GetAttribute("IsleTitle") or model.Name
	epithet.Text = model:GetAttribute("IsleEpithet") or ""
	card.Visible = true
	card.Position = UDim2.new(.5, 0, 0, 84)
	TweenService:Create(card, TweenInfo.new(.6, Enum.EasingStyle.Quad), {GroupTransparency = 0, Position = UDim2.new(.5, 0, 0, 96)}):Play()
	task.delay(4.2, function()
		if token ~= showToken then return end
		TweenService:Create(card, TweenInfo.new(1.2), {GroupTransparency = 1}):Play()
		task.delay(1.3, function() if token == showToken then card.Visible = false end end)
	end)
end

------------------------------------------------------------------------------
-- Ambience sound (the particles are §50's, ambience.client.lua).
------------------------------------------------------------------------------
local anchorPart = Instance.new("Part")
anchorPart.Name, anchorPart.Anchored, anchorPart.CanCollide, anchorPart.CanQuery, anchorPart.CanTouch = "RegionAmbience", true, false, false, false
anchorPart.Transparency, anchorPart.Size = 1, Vector3.new(1, 1, 1)
local sound = Instance.new("Sound")
sound.Name, sound.Looped, sound.Volume = "Ambience", true, .35
sound.Parent = anchorPart
anchorPart.Parent = workspace.CurrentCamera or workspace
local function ambience(model)
	if not model then sound:Stop(); return end
	local id = model:GetAttribute("AmbientSound")
	if type(id) == "string" and id ~= "" then
		if sound.SoundId ~= id then sound.SoundId = id end
		if not sound.IsPlaying then sound:Play() end
	else
		sound:Stop()
	end
end

------------------------------------------------------------------------------
-- Which island are we on? (checked a few times a second, not every frame)
------------------------------------------------------------------------------
local current
local function islandAt(pos)
	local folder = workspace:FindFirstChild("Islands")
	if not folder then return nil end
	local best, bestDist
	for _, model in ipairs(folder:GetChildren()) do
		local c, r = model:GetAttribute("IslandCenter"), model:GetAttribute("IslandRadius")
		if typeof(c) == "Vector3" and type(r) == "number" and model:GetAttribute("IsleTitle") then
			local flat = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude
			if flat <= r + 2 and pos.Y > c.Y - 8 and pos.Y < c.Y + 60 and (not bestDist or flat < bestDist) then best, bestDist = model, flat end
		end
	end
	return best
end
task.spawn(function()
	while true do
		task.wait(.5)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local model = islandAt(root.Position)
			if model and model ~= current then
				current = model
				show(model)
				ambience(model)
			elseif not model and current then
				current = nil
				ambience(nil)
			end
		end
	end
end)

------------------------------------------------------------------------------
-- Local spin (windmill sails) and the ambience box following the camera.
------------------------------------------------------------------------------
-- Same distance the forge builds the sails at (catalog range 1200, phones capped at 900).
local mobile = false
pcall(function()
	local UserInputService = game:GetService("UserInputService")
	mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true
end)
local SPIN_RANGE = if mobile then 900 else 1200
local spinning = {}
local function addSpin(p) if p:IsA("BasePart") then spinning[p] = p.CFrame end end
Tags:GetInstanceAddedSignal("RegionSpin"):Connect(addSpin)
Tags:GetInstanceRemovedSignal("RegionSpin"):Connect(function(p) spinning[p] = nil end)
for _, p in ipairs(Tags:GetTagged("RegionSpin")) do addSpin(p) end
local angle = 0
RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	anchorPart.CFrame = CFrame.new(camera.CFrame.Position)
	angle += dt
	for p, base in pairs(spinning) do
		if not p.Parent then spinning[p] = nil
		elseif (base.Position - camera.CFrame.Position).Magnitude < SPIN_RANGE then
			local rate = p:GetAttribute("SpinRate")
			p.CFrame = base * CFrame.Angles(0, 0, angle * (if type(rate) == "number" then rate else .3))
		end
	end
end)
