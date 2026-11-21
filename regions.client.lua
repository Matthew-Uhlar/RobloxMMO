-- Regions (client, World Art & Regions team; docs/DEPTH-CONTRACT.md §30).
-- * Entry banner: when the player's feet enter another island of
--   Workspace.Islands (IslandCenter / IslandRadius), a title card fades in
--   with the island name (IsleTitle), its epithet and the region line
--   (RegionTitle · RegionEpithet) in the region's accent colour.
-- * Ambience: one local emitter that follows the camera, styled by the
--   island's Ambience attribute (pollen, embers, spores...), plus an optional
--   looped Sound when AmbientSound names an asset (hook; empty by default).
-- * Spin: parts tagged RegionSpin (the Sunwheel sails) turn locally about
--   their look axis at SpinRate rad/s within 600 studs; the forge's mesh
--   follows its host's CFrame. Nothing here touches the server or lighting.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Tags = game:GetService("CollectionService")
local player = Players.LocalPlayer

local AMBIENCE = {
	motes = {color = "FFE9B0", rate = 6, speed = 1, size = .18, drift = Vector3.new(0, .4, 0)},
	pollen = {color = "FFF3A0", rate = 10, speed = 1.2, size = .14, drift = Vector3.new(.6, .2, 0)},
	embers = {color = "FF8A3D", rate = 12, speed = 2.4, size = .16, drift = Vector3.new(0, 1.6, 0), glow = 1},
	wind = {color = "E6F4FF", rate = 8, speed = 6, size = .1, drift = Vector3.new(5, 0, 1)},
	leaves = {color = "9BD18B", rate = 7, speed = 1.6, size = .3, drift = Vector3.new(1, -.8, .4)},
	spores = {color = "B59CFF", rate = 10, speed = .8, size = .2, drift = Vector3.new(0, .5, 0), glow = 1},
	spray = {color = "DFF8FF", rate = 9, speed = 1.5, size = .22, drift = Vector3.new(.8, .3, 0)},
	sparks = {color = "BFD7FF", rate = 9, speed = 4, size = .12, drift = Vector3.new(0, -.5, 3), glow = 1},
	glints = {color = "F2D27A", rate = 7, speed = 1, size = .16, drift = Vector3.new(0, .6, 0), glow = 1},
}

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
-- Ambience (one local emitter at the camera).
------------------------------------------------------------------------------
local anchorPart = Instance.new("Part")
anchorPart.Name, anchorPart.Anchored, anchorPart.CanCollide, anchorPart.CanQuery, anchorPart.CanTouch = "RegionAmbience", true, false, false, false
anchorPart.Transparency, anchorPart.Size = 1, Vector3.new(60, 24, 60)
local emitter = Instance.new("ParticleEmitter")
emitter.Name, emitter.Enabled, emitter.Shape, emitter.ShapeStyle = "Ambience", false, Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
emitter.Lifetime, emitter.Transparency = NumberRange.new(4, 7), NumberSequence.new(.2, 1)
emitter.Parent = anchorPart
local sound = Instance.new("Sound")
sound.Name, sound.Looped, sound.Volume = "Ambience", true, .35
sound.Parent = anchorPart
anchorPart.Parent = workspace.CurrentCamera or workspace
local function ambience(model)
	local kind = model and model:GetAttribute("Ambience")
	local style = type(kind) == "string" and AMBIENCE[kind]
	if not style then emitter.Enabled = false; sound:Stop(); return end
	emitter.Color = ColorSequence.new(Color3.fromHex(style.color))
	emitter.Rate, emitter.Speed = style.rate, NumberRange.new(style.speed * .5, style.speed)
	emitter.Size, emitter.LightEmission = NumberSequence.new(style.size), style.glow or .3
	emitter.Acceleration, emitter.SpreadAngle = style.drift, Vector2.new(180, 180)
	emitter.Enabled = true
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
		elseif (base.Position - camera.CFrame.Position).Magnitude < 600 then
			local rate = p:GetAttribute("SpinRate")
			p.CFrame = base * CFrame.Angles(0, 0, angle * (if type(rate) == "number" then rate else .3))
		end
	end
end)
