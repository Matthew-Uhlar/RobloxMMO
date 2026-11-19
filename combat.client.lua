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
local deep, ink, ivory, gold, mint = rgb("091923"), rgb("102733"), rgb("FFF4D9"), rgb("F9CC77"), rgb("9EE7D2")
local bold = Enum.Font.GothamBold

local function make(class, parent, props)
	local object = Instance.new(class)
	for k, v in pairs(props or {}) do object[k] = v end
	object.Parent = parent
	return object
end
local function round(parent, radius, stroke)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius)})
	if stroke then make("UIStroke", parent, {Color = stroke, Thickness = 1.5, Transparency = 0.15}) end
end

------------------------------------------------------------------------------
-- HUD (DisplayOrder below the atlas, which uses 8)
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {
	Name = "IsleCombatHud", ResetOnSpawn = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local panel = make("Frame", gui, {
	Name = "Target", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, 56), BackgroundColor3 = deep, BackgroundTransparency = 0.12, Visible = false,
})
round(panel, 10, gold)
make("UISizeConstraint", panel, {MaxSize = Vector2.new(420, 70)})
local panelName = make("TextLabel", panel, {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 22),
	Font = bold, TextSize = 16, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
})
local panelTimer = make("TextLabel", panel, {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 22),
	Font = bold, TextSize = 14, TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
})
local barBack = make("Frame", panel, {
	Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 16), BackgroundColor3 = ink, BorderSizePixel = 0,
})
round(barBack, 8)
local barFill = make("Frame", barBack, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = mint, BorderSizePixel = 0})
round(barFill, 8)
local barText = make("TextLabel", barBack, {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = bold, TextSize = 12,
	TextColor3 = ivory, TextStrokeTransparency = 0.4, Text = "", ZIndex = 2,
})
local banner = make("TextLabel", gui, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.fromOffset(460, 34),
	BackgroundColor3 = deep, BackgroundTransparency = 0.15, Font = bold, TextSize = 16, TextColor3 = gold,
	Text = "", Visible = false,
})
round(banner, 10, gold)
make("UISizeConstraint", banner, {MaxSize = Vector2.new(460, 40)})
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
		Size = UDim2.fromOffset(78, 78), BackgroundColor3 = deep, BackgroundTransparency = 0.1,
		Font = bold, Text = "⚔", TextSize = 34, TextColor3 = gold, AutoButtonColor = true,
	})
	round(attackButton, 39, gold)
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
local function nearestMonster()
	local best, bestDist = nil, ATTACK_RANGE
	if canTarget(target) and distanceTo(target) <= ATTACK_RANGE then return target end
	for _, model in ipairs(CollectionService:GetTagged("IsleMonster")) do
		if canTarget(model) then
			local d = distanceTo(model)
			if d <= bestDist then best, bestDist = model, d end
		end
	end
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
	if shoulder and shoulder:IsA("Motor6D") and not armBusy then
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
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function pick(screenPosition)
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	rayParams.FilterDescendantsInstances = {player.Character, camera}
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
		local model = nearestMonster()
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
			local model = nearestMonster()
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
local function flash(model)
	if not model or not model.Parent then return end
	local highlight = make("Highlight", Workspace.CurrentCamera, {
		Adornee = model, FillColor = Color3.new(1, 1, 1), FillTransparency = 0.35, OutlineTransparency = 1, DepthMode = Enum.HighlightDepthMode.Occluded,
	})
	TweenService:Create(highlight, TweenInfo.new(0.18), {FillTransparency = 1}):Play()
	task.delay(0.2, function() highlight:Destroy() end)
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
	panelName.Text = "[Lv " .. tostring(shown:GetAttribute("Level") or "?") .. "] " .. tostring(shown:GetAttribute("DisplayName") or shown.Name)
	panelName.TextColor3 = if isBoss then rgb("FF7B6E") else ivory
	barFill.Size = UDim2.fromScale(fraction, 1)
	barFill.BackgroundColor3 = if isBoss then rgb("DC3C3C") elseif fraction > 0.5 then mint elseif fraction > 0.25 then gold else rgb("E6504A")
	barText.Text = commas(hp) .. " / " .. commas(maxHp)
	panel.Size = if isBoss then UDim2.fromOffset(380, 56) else UDim2.fromOffset(300, 56)
	local expires = shown:GetAttribute("ExpiresAt")
	if isBoss and expires then
		local left = math.max(0, math.floor(expires - Workspace:GetServerTimeNow()))
		panelTimer.Text = string.format("%d:%02d", left // 60, left % 60)
	else
		panelTimer.Text = ""
	end
end)
