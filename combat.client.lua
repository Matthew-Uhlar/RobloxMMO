-- Combat input, health bars and damage numbers. See docs/DEPTH-CONTRACT.md §5.
-- The server is authoritative: this script only picks a target, sends
-- ("attack", model) on IsleCombat and renders IsleCombatFx feedback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local combat = ReplicatedStorage:WaitForChild("IsleCombat")
local fx = ReplicatedStorage:WaitForChild("IsleCombatFx")

local ATTACK_RANGE = 14
local BASE_COOLDOWN = 0.45
local TARGET_DROP_RANGE = 80

local function rgb(hex)
	hex = tostring(hex or "FFFFFF")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 255, tonumber(hex:sub(3, 4), 16) or 255, tonumber(hex:sub(5, 6), 16) or 255)
end
-- Palette and type match the atlas "Aether Brass" design system (ui.client.lua).
local deep, ivory, gold, mint = rgb("0C1820"), rgb("F7EFDC"), rgb("F3C66E"), rgb("7FE3CC")
local brass, brassDark, track, ember, raised = rgb("C9974A"), rgb("6B4E24"), rgb("060E14"), rgb("EF7D67"), rgb("2A4D5E")
local heavy, display = Enum.Font.BuilderSansExtraBold, Enum.Font.FredokaOne
local bold = heavy
local white = Color3.new(1, 1, 1)

local function make(class, parent, props)
	local object = Instance.new(class)
	for k, v in pairs(props or {}) do object[k] = v end
	object.Parent = parent
	return object
end
-- Rim with a light top edge (Border mode: on a TextLabel the Contextual
-- default would outline the text instead).
local function round(parent, radius, stroke)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius)})
	if stroke then
		local rim = make("UIStroke", parent, {Name = "Rim", Color = stroke, Thickness = 1.5, Transparency = 0.05, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		make("UIGradient", rim, {Rotation = 90, Color = ColorSequence.new(white, Color3.new(0.5, 0.5, 0.5))})
		return rim
	end
	return nil
end
local function sheen(parent, bottom)
	make("UIGradient", parent, {Name = "Sheen", Rotation = 90, Color = ColorSequence.new(white, Color3.new(bottom, bottom, bottom))})
end

------------------------------------------------------------------------------
-- HUD (DisplayOrder below the atlas, which uses 8)
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {
	Name = "IsleCombatHud", ResetOnSpawn = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local PANEL_HEIGHT = 58
-- Target panel: level medallion, name, boss timer chip and a gradient HP meter
-- (gloss + end cap). Bosses switch to ember rims and corner gems.
local panel = make("Frame", gui, {
	Name = "Target", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, PANEL_HEIGHT), BackgroundColor3 = deep, BackgroundTransparency = 0.06, Visible = false,
})
local panelRim = round(panel, 12, brass)
sheen(panel, 0.7)
make("UISizeConstraint", panel, {MaxSize = Vector2.new(420, 70)})
local ornaments = make("Frame", panel, {Name = "Ornaments", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false})
for _, c in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
	local gem = make("Frame", ornaments, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(c[1], if c[1] == 0 then 5 else -5, c[2], if c[2] == 0 then 5 else -5),
		Size = UDim2.fromOffset(6, 6), Rotation = 45, BackgroundColor3 = ember, BorderSizePixel = 0})
	make("UIStroke", gem, {Color = track, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
local medal = make("Frame", panel, {Name = "Level", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = raised, BorderSizePixel = 0})
local medalRim = round(medal, 20, gold)
sheen(medal, 0.5)
local medalText = make("TextLabel", medal, {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = display, TextSize = 16, TextColor3 = ivory,
	TextStrokeTransparency = 0.35, TextStrokeColor3 = deep, Text = ""})
local panelName = make("TextLabel", panel, {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(58, 6), Size = UDim2.new(1, -126, 0, 22),
	Font = heavy, TextSize = 16, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
})
local panelTimer = make("TextLabel", panel, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 7), Size = UDim2.fromOffset(56, 20), BackgroundColor3 = track, BackgroundTransparency = 0.2,
	Font = heavy, TextSize = 13, TextColor3 = gold, Text = "", Visible = false,
})
round(panelTimer, 10, brass)
local barBack = make("Frame", panel, {
	Position = UDim2.fromOffset(58, 31), Size = UDim2.new(1, -70, 0, 17), BackgroundColor3 = track, BorderSizePixel = 0,
})
round(barBack, 8)
-- A visible track: the fill alone disappeared against the deep panel.
make("UIStroke", barBack, {Color = rgb("4C7680"), Thickness = 1, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
local barFill = make("Frame", barBack, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = mint, BorderSizePixel = 0})
round(barFill, 8)
make("UIGradient", barFill, {Color = ColorSequence.new(Color3.new(0.6, 0.6, 0.6), white)})
local gloss = make("Frame", barFill, {BackgroundColor3 = white, BackgroundTransparency = 0.8, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 1), Size = UDim2.new(1, -4, 0.42, 0)})
round(gloss, 6)
local barCap = make("Frame", barFill, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -1, 0.5, 0), Size = UDim2.fromOffset(5, 13), BackgroundColor3 = white, BorderSizePixel = 0})
round(barCap, 3)
local barText = make("TextLabel", barBack, {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = heavy, TextSize = 12,
	TextColor3 = ivory, TextStrokeTransparency = 0.3, TextStrokeColor3 = deep, Text = "", ZIndex = 2,
})
-- Event banner: a ribbon strip with brass end gems.
local banner = make("TextLabel", gui, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), Size = UDim2.fromOffset(460, 34),
	BackgroundColor3 = deep, BackgroundTransparency = 0.06, Font = heavy, TextSize = 16, TextColor3 = gold,
	Text = "", Visible = false,
})
round(banner, 17, brass)
make("UISizeConstraint", banner, {MaxSize = Vector2.new(460, 40)})
for _, x in ipairs({0, 1}) do
	local gem = make("Frame", banner, {Name = "End", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, if x == 0 then 16 else -16, 0.5, 0), Size = UDim2.fromOffset(8, 8),
		Rotation = 45, BackgroundColor3 = gold, BorderSizePixel = 0})
	make("UIStroke", gem, {Color = brassDark, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
-- Layout: the atlas HUD (ui.client.lua, DisplayOrder 8) owns the top-left corner,
-- x 10-315 and y 8-96. On wide screens the target panel and banner sit top-centre
-- as before; on narrow ones (phone landscape 730x303) the panel moves top-right
-- and the banner below the HUD; on very narrow ones both stack below the HUD.
local HUD_RIGHT, HUD_BOTTOM, EDGE = 325, 104, 10
local layoutKey
local function layoutHud(isBoss)
	local view = gui.AbsoluteSize
	local width = if view and view.X > 0 then view.X else 1280
	local key = width .. (if isBoss then "b" else "n")
	if key == layoutKey then return end
	layoutKey = key
	local panelWidth = if isBoss then 380 else 300
	local panelTop
	if width / 2 - panelWidth / 2 >= HUD_RIGHT then
		panel.AnchorPoint, panel.Position, panelTop = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, EDGE), EDGE
	elseif width - EDGE - HUD_RIGHT >= 220 then
		panelWidth = math.min(panelWidth, width - EDGE - HUD_RIGHT)
		panel.AnchorPoint, panel.Position, panelTop = Vector2.new(1, 0), UDim2.new(1, -EDGE, 0, EDGE), EDGE
	else
		panelWidth = math.min(panelWidth, width - 2 * EDGE)
		panel.AnchorPoint, panel.Position, panelTop = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, HUD_BOTTOM), HUD_BOTTOM
	end
	panel.Size = UDim2.fromOffset(panelWidth, PANEL_HEIGHT)
	local bannerWidth = math.min(460, width - 2 * EDGE)
	local bannerTop = panelTop + PANEL_HEIGHT + 8
	if width / 2 - bannerWidth / 2 < HUD_RIGHT then bannerTop = math.max(bannerTop, HUD_BOTTOM) end
	banner.Size = UDim2.fromOffset(bannerWidth, 34)
	banner.Position = UDim2.new(0.5, 0, 0, bannerTop)
end
layoutHud(false)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	layoutKey = nil
	layoutHud(false)
end)
local bannerToken = 0
local function showBanner(text, color)
	bannerToken += 1
	local token = bannerToken
	banner.Text, banner.TextColor3, banner.Visible = text, color or gold, true
	task.delay(4, function() if bannerToken == token then banner.Visible = false end end)
end

local attackButton -- created for touch devices
local function ensureAttackButton()
	if attackButton or not UserInputService.TouchEnabled then return end
	attackButton = make("TextButton", gui, {
		Name = "AttackButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -110, 1, -40),
		Size = UDim2.fromOffset(78, 78), BackgroundColor3 = raised, BackgroundTransparency = 0.05,
		Font = heavy, Text = "⚔", TextSize = 30, TextColor3 = gold, AutoButtonColor = true, TextYAlignment = Enum.TextYAlignment.Top,
	})
	round(attackButton, 39, gold)
	make("UIPadding", attackButton, {PaddingTop = UDim.new(0, 12)})
	-- Inner brass ring and an ATTACK caption under the crossed blades.
	local ring = make("Frame", attackButton, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -6), Size = UDim2.new(1, -10, 1, 2), BackgroundTransparency = 1})
	make("UICorner", ring, {CornerRadius = UDim.new(1, 0)})
	make("UIStroke", ring, {Color = brass, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	make("TextLabel", attackButton, {Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(60, 12),
		BackgroundTransparency = 1, Font = heavy, TextSize = 11, TextColor3 = ivory, Text = "ATTACK"})
end
ensureAttackButton()

------------------------------------------------------------------------------
-- Targeting
------------------------------------------------------------------------------
local target -- Model
local targetHighlight = make("Highlight", nil, {
	FillTransparency = 1, OutlineColor = gold, OutlineTransparency = 0.1, DepthMode = Enum.HighlightDepthMode.Occluded,
})
local function liveMonster(model)
	return model and model.Parent and CollectionService:HasTag(model, "IsleMonster") and not model:GetAttribute("Dead")
		and (model:GetAttribute("Health") or 1) > 0
end
local function canTarget(model)
	if not liveMonster(model) then return false end
	local owner = model:GetAttribute("OwnerUserId")
	return owner == nil or owner == player.UserId
end
local function rootOf()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end
local function distanceTo(model)
	local root = rootOf()
	local body = model and model.PrimaryPart
	if not root or not body then return math.huge end
	local radius = math.min(6, math.max(body.Size.X, body.Size.Z) / 2)
	return (root.Position - body.Position).Magnitude - radius
end
local function setTarget(model)
	if model == target then return end
	target = model
	-- Highlights live under the camera (adorned), so a server-side Destroy of the
	-- monster never takes the reusable highlight with it.
	targetHighlight.Adornee = model
	targetHighlight.Parent = if model then Workspace.CurrentCamera else nil
end
local function monsterFromPart(part)
	local node = part
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "IsleMonster") then return node end
		node = node.Parent
	end
	return nil
end
-- Holding attack calls this every frame; the tag scan is cached for 0.2s.
local SCAN_INTERVAL = 0.2
local scanAt, scanned = -math.huge, nil
local function nearestMonster(fresh)
	if canTarget(target) and distanceTo(target) <= ATTACK_RANGE then return target end
	local now = os.clock()
	if not fresh and now - scanAt < SCAN_INTERVAL and (scanned == nil or canTarget(scanned)) then return scanned end
	scanAt = now
	local best, bestDist = nil, ATTACK_RANGE
	for _, model in ipairs(CollectionService:GetTagged("IsleMonster")) do
		if canTarget(model) then
			local d = distanceTo(model)
			if d <= bestDist then best, bestDist = model, d end
		end
	end
	scanned = best
	return best
end

------------------------------------------------------------------------------
-- Swing feedback
------------------------------------------------------------------------------
local attackSpeed = 0
local nextSwing = 0
local armBusy = false
local function slash()
	local root = rootOf()
	if not root then return end
	local part = make("Part", nil, {
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = ivory, Size = Vector3.new(5.5, 0.18, 0.5), Transparency = 0.15,
	})
	local side = if math.random() < 0.5 then 1 else -1
	local start = root.CFrame * CFrame.new(0, 0.6, -3.2) * CFrame.Angles(0, 0, math.rad(35 * side))
	part.CFrame = start * CFrame.Angles(0, math.rad(-40 * side), 0)
	part.Parent = Workspace.CurrentCamera
	TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = start * CFrame.Angles(0, math.rad(40 * side), 0), Transparency = 1, Size = Vector3.new(6.5, 0.05, 0.3),
	}):Play()
	task.delay(0.25, function() part:Destroy() end)
	-- Arm swing (local only): nudge the shoulder joint and restore it.
	local character = player.Character
	local shoulder = character and (character:FindFirstChild("RightShoulder", true) or character:FindFirstChild("Right Shoulder", true))
	-- [Animation] Route the swing through the shared gesture player (animate.client.lua) when it is running.
	local gesture = ReplicatedStorage:FindFirstChild("IsleGestureLocal")
	if gesture then
		gesture:Fire("attack", target)
	elseif shoulder and shoulder:IsA("Motor6D") and not armBusy then
		armBusy = true
		local rest = shoulder.C0
		local swing = TweenService:Create(shoulder, TweenInfo.new(0.09, Enum.EasingStyle.Quad), {C0 = rest * CFrame.Angles(math.rad(110), 0, 0)})
		swing:Play()
		swing.Completed:Once(function()
			local back = TweenService:Create(shoulder, TweenInfo.new(0.14, Enum.EasingStyle.Quad), {C0 = rest})
			back:Play()
			back.Completed:Once(function() armBusy = false end)
		end)
	end
end
local function cooldown()
	return BASE_COOLDOWN / (1 + math.clamp(attackSpeed, 0, 100) / 100)
end
local function tryAttack(model)
	local _, humanoid = rootOf()
	if not humanoid or humanoid.Health <= 0 then return false end
	if not canTarget(model) then return false end
	setTarget(model)
	if distanceTo(model) > ATTACK_RANGE then return false end
	local now = os.clock()
	if now < nextSwing then return false end
	nextSwing = now + cooldown()
	combat:FireServer("attack", model)
	slash()
	return true
end

------------------------------------------------------------------------------
-- Input: click/tap a monster, touch button or ButtonR2 attack the nearest
------------------------------------------------------------------------------
-- Include-only filter: invisible guard walls, prompt parts and props can never
-- swallow a tap aimed at a monster (the server still validates range).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function pick(screenPosition)
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local monsters = CollectionService:GetTagged("IsleMonster")
	if #monsters == 0 then return nil end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	rayParams.FilterDescendantsInstances = monsters
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, rayParams)
	return hit and monsterFromPart(hit.Instance)
end
local held = nil -- "mouse" | "button" | "pad"
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local model = pick(input.Position)
		if model then
			tryAttack(model)
			held = "mouse"
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		held = "pad"
		local model = nearestMonster(true)
		if model then tryAttack(model) end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and held == "mouse")
		or (input.KeyCode == Enum.KeyCode.ButtonR2 and held == "pad") then
		held = nil
	end
end)
UserInputService.TouchTapInWorld:Connect(function(position, processed)
	if processed then return end
	local model = pick(position)
	if model then tryAttack(model) end
end)
if attackButton then
	attackButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held = "button"
			local model = nearestMonster(true)
			if model then tryAttack(model) end
		end
	end)
	attackButton.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and held == "button" then
			held = nil
		end
	end)
end

-- Attack Speed for the local swing pacing (the server enforces the real cooldown).
task.spawn(function()
	local updates = ReplicatedStorage:WaitForChild("IsleUpdate", 60)
	if updates and updates:IsA("RemoteEvent") then
		updates.OnClientEvent:Connect(function(state)
			local depth = type(state) == "table" and state.depth
			local stats = type(depth) == "table" and depth.stats
			if type(stats) == "table" and tonumber(stats.attackSpeed) then attackSpeed = tonumber(stats.attackSpeed) end
		end)
	end
end)

------------------------------------------------------------------------------
-- Floating numbers, hit flash, death burst
------------------------------------------------------------------------------
local function commas(n)
	local s = tostring(math.floor(n))
	while true do
		local replaced, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = replaced
		if count == 0 then return s end
	end
end
local function floatText(position, text, color, size)
	local anchor = make("Attachment", Workspace.Terrain, {
		WorldPosition = position + Vector3.new((math.random() - 0.5) * 2, math.random() * 0.8, (math.random() - 0.5) * 2),
	})
	local board = make("BillboardGui", anchor, {
		Size = UDim2.fromOffset(160, 44), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 120,
	})
	local label = make("TextLabel", board, {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = bold, TextSize = size,
		TextColor3 = color, TextStrokeTransparency = 0.2, TextStrokeColor3 = deep, Text = text,
	})
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(board, info, {StudsOffsetWorldSpace = Vector3.new(0, 3, 0)}):Play()
	TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.45), {
		TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function() anchor:Destroy() end)
end
-- One reusable flash Highlight per monster (Roblox renders at most 31 at once);
-- it is disabled between hits and destroyed when the monster leaves the world.
local flashes = {} -- [model] = {highlight = Highlight, token = number}
local function dropFlash(model)
	local entry = flashes[model]
	if not entry then return end
	flashes[model] = nil
	if entry.connection then entry.connection:Disconnect() end
	entry.highlight:Destroy()
end
local function flash(model)
	if not model or not model.Parent then return end
	local entry = flashes[model]
	if not entry then
		entry = {token = 0, highlight = make("Highlight", Workspace.CurrentCamera, {
			Adornee = model, FillColor = Color3.new(1, 1, 1), FillTransparency = 1, OutlineTransparency = 1,
			DepthMode = Enum.HighlightDepthMode.Occluded, Enabled = false,
		})}
		flashes[model] = entry
		entry.connection = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then dropFlash(model) end
		end)
	end
	entry.token += 1
	local token = entry.token
	local highlight = entry.highlight
	highlight.Enabled = true
	highlight.FillTransparency = 0.35
	TweenService:Create(highlight, TweenInfo.new(0.18), {FillTransparency = 1}):Play()
	task.delay(0.2, function()
		if flashes[model] ~= entry or entry.token ~= token then return end
		highlight.Enabled = false
		if not model.Parent then dropFlash(model) end
	end)
end
local function burst(position, color, scale)
	local tint = rgb(color)
	for i = 1, 12 do
		local size = (0.35 + math.random() * 0.4) * (scale or 1)
		local bit = make("Part", Workspace.CurrentCamera, {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = if i % 3 == 0 then gold else tint, Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(position),
		})
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		TweenService:Create(bit, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + direction * (4 + math.random() * 3) * (scale or 1)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05),
		}):Play()
		task.delay(0.6, function() bit:Destroy() end)
	end
end

fx.OnClientEvent:Connect(function(kind, payload)
	if type(payload) ~= "table" then return end
	if kind == "hit" and typeof(payload.position) == "Vector3" then
		local amount = tonumber(payload.amount) or 0
		if payload.crit then
			floatText(payload.position, "✧ " .. commas(amount) .. " ✧", gold, 26)
		else
			floatText(payload.position, commas(amount), Color3.new(1, 1, 1), 20)
		end
		if typeof(payload.model) == "Instance" then flash(payload.model) end
	elseif kind == "hurt" then
		local root = rootOf()
		if root then floatText(root.Position + Vector3.new(0, 2.5, 0), "-" .. commas(tonumber(payload.amount) or 0), rgb("FF6B5B"), 18) end
	elseif kind == "death" and typeof(payload.position) == "Vector3" then
		burst(payload.position, payload.color, if payload.boss then 2.2 else 1)
	elseif kind == "bossSpawn" and payload.owner == player.UserId then
		showBanner(tostring(payload.name) .. " has emerged!", rgb("FF7B6E"))
	elseif kind == "bossFail" then
		showBanner(if payload.reason == "timeout" then "The slayer boss slipped away. Time ran out." else "You fell. The slayer boss withdraws.", rgb("FF7B6E"))
	end
end)

------------------------------------------------------------------------------
-- Per-frame: held attacks, target panel
------------------------------------------------------------------------------
local function ownBoss()
	for _, model in ipairs(CollectionService:GetTagged("IsleMonster")) do
		if model:GetAttribute("OwnerUserId") == player.UserId and liveMonster(model) then return model end
	end
	return nil
end
local lastBossScan, boss = 0, nil
RunService.RenderStepped:Connect(function()
	if target and (not liveMonster(target) or distanceTo(target) > TARGET_DROP_RANGE) then setTarget(nil) end
	if held then
		local model = if held == "mouse" then target else nearestMonster()
		if model then tryAttack(model) end
	end
	local now = os.clock()
	if now - lastBossScan > 0.5 then
		lastBossScan = now
		boss = ownBoss()
	end
	local shown = if boss and liveMonster(boss) then boss else target
	if not shown then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local isBoss = shown:GetAttribute("Boss") == true
	local hp, maxHp = shown:GetAttribute("Health") or 0, math.max(1, shown:GetAttribute("MaxHealth") or 1)
	local fraction = math.clamp(hp / maxHp, 0, 1)
	medalText.Text = tostring(shown:GetAttribute("Level") or "?")
	panelName.Text = (if isBoss then "☠ " else "") .. tostring(shown:GetAttribute("DisplayName") or shown.Name)
	panelName.TextColor3 = if isBoss then rgb("FF9C8E") else ivory
	if panelRim then panelRim.Color = if isBoss then ember else brass end
	if medalRim then medalRim.Color = if isBoss then ember else gold end
	medal.BackgroundColor3 = if isBoss then rgb("5A1E1A") else raised
	ornaments.Visible = isBoss
	barFill.Size = UDim2.fromScale(fraction, 1)
	barFill.Visible = fraction > 0
	barCap.Visible = fraction > 0.04 and fraction < 0.995
	barFill.BackgroundColor3 = if isBoss then rgb("DC3C3C") elseif fraction > 0.5 then mint elseif fraction > 0.25 then gold else rgb("E6504A")
	barText.Text = commas(hp) .. " / " .. commas(maxHp)
	layoutHud(isBoss)
	local expires = shown:GetAttribute("ExpiresAt")
	if isBoss and expires then
		local left = math.max(0, math.floor(expires - Workspace:GetServerTimeNow()))
		panelTimer.Text = string.format("%d:%02d", left // 60, left % 60)
		panelTimer.Visible = true
	else
		panelTimer.Text = ""
		panelTimer.Visible = false
	end
end)
