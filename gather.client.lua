-- Gathering Feel (§42, docs/DEPTH-CONTRACT.md): depleted nodes, per player.
-- StarterPlayerScripts.IsleGather. Node progress and regrowth are per player
-- on the server, so depletion is drawn only on this client: when a strike
-- breaks a node (or the server answers "regrowing"), combat.client.lua fires
-- ReplicatedStorage.IsleNodeDepleted(node host, seconds) and this script
--   * hides the node's visual Model locally (LocalTransparencyModifier; parts
--     the forge or the sculptor add while depleted are hidden too) and stands a
--     local depleted prop in its place, a forge mesh slot (no server part):
--       trees  -> "TreeStump"  after a short topple (a pooled trunk proxy falls
--                 away from the player, leaves burst),
--       ore    -> "DepletedRock" (a plain grey rock; a pooled debris burst),
--       crops  -> "TilledSoil" (bare tilled soil; a dust burst),
--       fishing spots go calm (ripples and the bobber hidden; no prop);
--   * restores the node when its time is up, with a reverse effect: a sapling
--     grows back into the tree, ore glints back in, crops sprout, the water
--     ripples again.
-- Reduced motion (Theme.reducedMotion) swaps instantly with no topple, tween
-- or particles. Props are pooled per node, effects in a small shared pool.
-- ReplicatedStorage.IsleNodeState (BindableFunction): Invoke(node) -> seconds
-- left (0 = standing); Invoke("state") -> the internal table (tests). The
-- overlay reads it for "Respawns in 12s" and combat for the Attack button.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Theme = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local Data
do
	local module = ReplicatedStorage:WaitForChild("AetherData", 20)
	if module then
		local ok, value = pcall(require, module)
		if ok and type(value) == "table" then Data = value end
	end
end

local G = {depleted = {}, props = {}, fxFree = {}, fxCount = 0, FX_POOL = 6, MAX_GROUP = 60}
G.SHAPE = {Woodcutting = "TreeStump", Mining = "DepletedRock", Farming = "TilledSoil"}
G.TINT = {Woodcutting = Color3.fromRGB(122, 86, 56), Mining = Color3.fromRGB(118, 122, 128), Farming = Color3.fromRGB(92, 66, 44)}
G.FX_COLOR = {Woodcutting = Color3.fromRGB(110, 168, 84), Mining = Color3.fromRGB(150, 150, 156), Farming = Color3.fromRGB(150, 116, 78),
	Fishing = Color3.fromRGB(190, 230, 255)}
G.CALM = {Ripple = true, Bobber = true, ["Bobber cap"] = true}

local holder = Instance.new("Folder")
holder.Name = "IsleNodeLocal"
holder.Parent = Workspace

local function reduced() return Theme.reducedMotion and Theme.reducedMotion(player) == true end
local function skillOf(node)
	local id = node:GetAttribute("GatherNode")
	return Data and type(id) == "string" and Data.ResourceSkill[id] or nil
end
-- The node's visual group: its own Model when it is a small one, else the host alone.
function G.group(node)
	local model = node.Parent
	if model and model:IsA("Model") and #model:GetDescendants() <= G.MAX_GROUP then return model end
	return node
end
-- Ground point and footprint under the node's group.
function G.footing(node, group)
	local cf, size = node.CFrame, node.Size
	if group:IsA("Model") then
		local ok, bcf, bsize = pcall(function() return group:GetBoundingBox() end)
		if ok and bcf then cf, size = bcf, bsize end
	end
	local bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
	return bottom, math.clamp(math.max(size.X, size.Z), 2, 8), size.Y
end

------------------------------------------------------------------------------
-- Pooled particle bursts (debris, leaves, dust, glints, splashes).
------------------------------------------------------------------------------
function G.fx(position, color, count, speed)
	if reduced() then return end
	local e = table.remove(G.fxFree)
	if not e then
		if G.fxCount >= G.FX_POOL then return end
		G.fxCount += 1
		local a = Instance.new("Attachment")
		a.Name = "NodeBurst"
		a.Parent = Workspace.Terrain
		local p = Instance.new("ParticleEmitter")
		p.Enabled, p.Rate, p.LightInfluence = false, 0, 0.6
		p.Lifetime = NumberRange.new(0.45, 0.8)
		p.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05)})
		p.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
		p.SpreadAngle = Vector2.new(70, 70)
		p.Acceleration = Vector3.new(0, -24, 0)
		p.Parent = a
		e = {attachment = a, emitter = p}
	end
	e.attachment.WorldPosition = position
	e.emitter.Color = ColorSequence.new(color)
	e.emitter.Speed = NumberRange.new(speed or 8, (speed or 8) * 1.6)
	e.emitter:Emit(count or 14)
	task.delay(1, function() table.insert(G.fxFree, e) end)
end

------------------------------------------------------------------------------
-- Hide / show the node's visuals locally.
------------------------------------------------------------------------------
local function hidePart(entry, part)
	if not part:IsA("BasePart") or part:IsDescendantOf(holder) or entry.saved[part] ~= nil then return end
	if entry.calm and not G.CALM[part.Name] then return end
	entry.saved[part] = part.LocalTransparencyModifier
	part.LocalTransparencyModifier = 1
end
function G.hide(entry)
	for _, d in ipairs(entry.group:GetDescendants()) do hidePart(entry, d) end
	if entry.group:IsA("BasePart") then hidePart(entry, entry.group) end
	-- Forge clones and sculptures that arrive while depleted are hidden too.
	if entry.group:IsA("Model") then
		pcall(function() entry.watch = entry.group.DescendantAdded:Connect(function(d) task.defer(hidePart, entry, d) end) end)
	end
end
function G.show(entry)
	if entry.watch then entry.watch:Disconnect(); entry.watch = nil end
	for part, value in pairs(entry.saved) do
		-- A forge host keeps its mesh hidden (the mesh, not the primitive, shows).
		if part.Parent then part.LocalTransparencyModifier = if part:FindFirstChild("ShapeMesh") then 1 else value end
	end
	table.clear(entry.saved)
end

------------------------------------------------------------------------------
-- Depleted props: one local forge mesh slot per node, kept for reuse.
------------------------------------------------------------------------------
function G.prop(node, skill, bottom, width)
	local shape = G.SHAPE[skill]
	if not shape then return nil end
	local prop = G.props[node]
	if not prop then
		prop = Instance.new("Part")
		prop.Name = "Depleted " .. tostring(node:GetAttribute("GatherNode"))
		prop.Anchored, prop.CanCollide, prop.CanTouch, prop.CanQuery, prop.CastShadow = true, false, false, false, true
		prop.Material = if skill == "Mining" then Enum.Material.Slate elseif skill == "Farming" then Enum.Material.Ground else Enum.Material.Wood
		prop.Color = G.TINT[skill]
		prop:SetAttribute("Shape", shape) -- the forge swaps in the catalog mesh
		prop:SetAttribute("Tint", G.TINT[skill])
		prop:SetAttribute("ShapeFit", "Uniform")
		G.props[node] = prop
		pcall(function()
			node.Destroying:Connect(function()
				G.props[node] = nil
				prop:Destroy()
			end)
		end)
	end
	local h = if skill == "Woodcutting" then 1.4 elseif skill == "Mining" then width * 0.45 else 0.45
	local w = if skill == "Woodcutting" then math.min(width, 3.2) else width
	prop.Size = Vector3.new(w, h, w)
	prop.CFrame = CFrame.new(bottom + Vector3.new(0, h / 2, 0))
	prop.Parent = holder
	return prop
end

------------------------------------------------------------------------------
-- Effects: the topple, the regrow.
------------------------------------------------------------------------------
local function proxyPart(name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color, p.Material = name, size, color, material
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	if shape then p.Shape = shape end
	return p
end
-- A pooled two-part tree proxy (trunk + crown) for the fall and the regrow.
function G.treeProxy()
	local t = G.tree
	if not t then
		t = {trunk = proxyPart("Falling trunk", Vector3.new(1, 1, 1), G.TINT.Woodcutting, Enum.Material.Wood),
			crown = proxyPart("Falling crown", Vector3.new(1, 1, 1), Color3.fromRGB(96, 150, 78), Enum.Material.LeafyGrass, Enum.PartType.Ball)}
		G.tree = t
	end
	t.token = (t.token or 0) + 1
	return t
end
function G.topple(node, bottom, width, height)
	if reduced() then return end
	local t = G.treeProxy()
	local token = t.token
	local trunkH = math.clamp(height * 0.7, 4, 18)
	local crownD = math.clamp(width * 1.6, 3, 9)
	t.trunk.Size = Vector3.new(math.min(width * 0.35, 1.6), trunkH, math.min(width * 0.35, 1.6))
	t.crown.Size = Vector3.new(crownD, crownD, crownD)
	-- Falls away from the player.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local away = if root then (bottom - root.Position) * Vector3.new(1, 0, 1) else Vector3.new(1, 0, 0)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(1, 0, 0)
	local axis = Vector3.new(0, 1, 0):Cross(away).Unit
	local pivot = CFrame.new(bottom)
	local function place(angle)
		local turn = pivot * CFrame.fromAxisAngle(axis, angle)
		t.trunk.CFrame = turn * CFrame.new(0, trunkH / 2, 0)
		t.crown.CFrame = turn * CFrame.new(0, trunkH + crownD * 0.3, 0)
	end
	place(0)
	for _, p in ipairs({t.trunk, t.crown}) do p.Transparency = 0; p.Parent = holder end
	local value = Instance.new("NumberValue")
	if not pcall(function() value.Changed:Connect(function(a) if t.token == token then place(a) end end) end) then
		value:Destroy(); t.trunk.Parent, t.crown.Parent = nil, nil -- no property signal (headless): no topple
		return
	end
	local fall = TweenService:Create(value, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Value = math.rad(84)})
	fall:Play()
	fall.Completed:Once(function()
		value:Destroy()
		if t.token ~= token then return end
		G.fx(t.crown.Position, G.FX_COLOR.Woodcutting, 22, 10)
		for _, p in ipairs({t.trunk, t.crown}) do
			TweenService:Create(p, TweenInfo.new(0.35), {Transparency = 1}):Play()
		end
		task.delay(0.4, function()
			if t.token == token then t.trunk.Parent, t.crown.Parent = nil, nil end
		end)
	end)
end
function G.sprout(bottom, width, height, done)
	if reduced() then done() return end
	local t = G.treeProxy()
	local token = t.token
	local trunkH = math.clamp(height * 0.7, 4, 18)
	local crownD = math.clamp(width * 1.6, 3, 9)
	local thick = math.min(width * 0.35, 1.6)
	t.trunk.Size, t.crown.Size = Vector3.new(thick, 0.2, thick), Vector3.new(0.4, 0.4, 0.4)
	t.trunk.CFrame, t.crown.CFrame = CFrame.new(bottom + Vector3.new(0, 0.1, 0)), CFrame.new(bottom + Vector3.new(0, 0.5, 0))
	for _, p in ipairs({t.trunk, t.crown}) do p.Transparency = 0; p.Parent = holder end
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(t.trunk, info, {Size = Vector3.new(thick, trunkH, thick), CFrame = CFrame.new(bottom + Vector3.new(0, trunkH / 2, 0))}):Play()
	TweenService:Create(t.crown, info, {Size = Vector3.new(crownD, crownD, crownD), CFrame = CFrame.new(bottom + Vector3.new(0, trunkH + crownD * 0.3, 0))}):Play()
	task.delay(0.65, function()
		if t.token == token then t.trunk.Parent, t.crown.Parent = nil, nil end
		done()
	end)
end

------------------------------------------------------------------------------
-- Deplete / restore.
------------------------------------------------------------------------------
function G.deplete(node, seconds)
	if typeof(node) ~= "Instance" or not node:IsA("BasePart") or not node.Parent then return end
	seconds = math.max(0.5, tonumber(seconds) or 3)
	local entry = G.depleted[node]
	if entry then
		entry.readyAt = os.clock() + seconds
		return
	end
	local skill = skillOf(node)
	if not skill then return end
	local group = G.group(node)
	local bottom, width, height = G.footing(node, group)
	entry = {node = node, skill = skill, group = group, saved = {}, readyAt = os.clock() + seconds, bottom = bottom, width = width, height = height,
		calm = skill == "Fishing"}
	G.depleted[node] = entry
	G.hide(entry)
	entry.prop = G.prop(node, skill, bottom, width)
	if skill == "Woodcutting" then
		G.topple(node, bottom, width, height)
	else
		G.fx(bottom + Vector3.new(0, math.min(height, 3) * 0.6, 0), G.FX_COLOR[skill], if skill == "Mining" then 18 else 12, if skill == "Fishing" then 4 else 9)
	end
end
function G.restore(node)
	local entry = G.depleted[node]
	if not entry then return end
	G.depleted[node] = nil
	local function finish()
		if G.depleted[node] then return end -- depleted again meanwhile
		if entry.prop then entry.prop.Parent = nil end
		G.show(entry)
	end
	if entry.skill == "Woodcutting" then
		if entry.prop then entry.prop.Parent = nil end
		G.sprout(entry.bottom, entry.width, entry.height, finish)
	else
		finish()
		G.fx(entry.bottom + Vector3.new(0, math.min(entry.height, 3) * 0.6, 0), if entry.skill == "Mining" then Color3.fromRGB(255, 236, 170) else G.FX_COLOR[entry.skill], 10, 4)
	end
end
function G.left(node)
	local entry = G.depleted[node]
	return if entry then math.max(0, entry.readyAt - os.clock()) else 0
end
-- Regrowth clock (4 Hz; no work while nothing is depleted). A respawn resets
-- everything (the server's regrowth is session state; a new character keeps it).
local tickAt = 0
RunService.Heartbeat:Connect(function()
	if next(G.depleted) == nil then return end
	local now = os.clock()
	if now - tickAt < 0.25 then return end
	tickAt = now
	for node, entry in pairs(G.depleted) do
		if not node.Parent then
			G.depleted[node] = nil
			G.show(entry)
			if entry.prop then entry.prop.Parent = nil end
		elseif now >= entry.readyAt then
			G.restore(node)
		end
	end
end)

local event = ReplicatedStorage:FindFirstChild("IsleNodeDepleted")
if not event then
	event = Instance.new("BindableEvent")
	event.Name = "IsleNodeDepleted"
	event.Parent = ReplicatedStorage
end
event.Event:Connect(G.deplete)
local api = Instance.new("BindableFunction")
api.Name = "IsleNodeState"
api.OnInvoke = function(node)
	if node == "state" then return G end
	return G.left(node)
end
api.Parent = ReplicatedStorage
