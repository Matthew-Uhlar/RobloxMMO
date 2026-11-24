-- Gathering Feel (§42, docs/DEPTH-CONTRACT.md): depleted nodes, per player.
-- StarterPlayerScripts.IsleGather. Node progress and regrowth are per player
-- on the server, so depletion is drawn only on this client: when a strike
-- breaks a node (or the server answers "regrowing"), combat.client.lua fires
-- ReplicatedStorage.IsleNodeDepleted(node host, seconds) and this script
--   * hides the node's visual Model locally (LocalTransparencyModifier, and
--     CanQuery = false on every hidden part but the host, so invisible canopies
--     never catch clicks; parts the forge or the sculptor add while depleted
--     are hidden too, and a part the forge releases meanwhile is hidden again)
--     and stands a local depleted prop in its place, a forge mesh slot (no
--     server part):
--       trees  -> "TreeStump"  after a short topple (a pooled trunk proxy, one
--                 per falling tree from a small pool, falls away from the
--                 player, leaves burst),
--       ore    -> "DepletedRock" (a plain grey rock; a pooled debris burst),
--       crops  -> "TilledSoil" (bare tilled soil; a dust burst); the Aether
--                 Lotus grows in water, so only its blooms go (lily pads stay),
--       fishing spots go calm (ripples and the bobber hidden; no prop);
--   * shows a small world countdown (a bar and "12s") over the node, for touch
--     and gamepad players who have no hover label;
--   * restores the node when its time is up, with a reverse effect: a sapling
--     grows back into the tree, ore glints back in, crops sprout, the water
--     ripples again. The entry stays in G.depleted (restoring) until the
--     effect finishes; a re-break meanwhile cancels the restore first.
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

local G = {depleted = {}, props = {}, boards = {}, fxFree = {}, fxCount = 0, FX_POOL = 6, MAX_GROUP = 60, treeFree = {}, treeCount = 0, TREE_POOL = 4}
G.SHAPE = {Woodcutting = "TreeStump", Mining = "DepletedRock", Farming = "TilledSoil"}
G.TINT = {Woodcutting = Color3.fromRGB(122, 86, 56), Mining = Color3.fromRGB(118, 122, 128), Farming = Color3.fromRGB(92, 66, 44)}
G.FX_COLOR = {Woodcutting = Color3.fromRGB(110, 168, 84), Mining = Color3.fromRGB(150, 150, 156), Farming = Color3.fromRGB(150, 116, 78),
	Fishing = Color3.fromRGB(190, 230, 255)}
G.CALM = {Ripple = true, Bobber = true, ["Bobber cap"] = true}
-- Water crops: only these parts go (no TilledSoil in a pool; QC L11).
G.BARE = {AetherLotus = {["Lotus bloom"] = true}}

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
-- (A G field so the suite can run a deferred hide after the node is shown.)
function G.hidePart(entry, part)
	if not part:IsA("BasePart") or part:IsDescendantOf(holder) or entry.saved[part] ~= nil then return end
	-- QC L11: a deferred hide that arrives after the node was shown (or replaced) does nothing.
	if entry.shown or G.depleted[entry.node] ~= entry then return end
	if entry.only and not entry.only[part.Name] then return end
	entry.saved[part] = part.LocalTransparencyModifier
	part.LocalTransparencyModifier = 1
	-- QC L10: an invisible part never catches a click or a hover ray (the host
	-- stays queryable: hovering it reads "Respawns in Ns").
	if part ~= entry.node then
		local ok, was = pcall(function() return part.CanQuery end)
		if ok and was then
			entry.query[part] = was
			pcall(function() part.CanQuery = false end)
		end
	end
end
function G.hide(entry)
	if entry.watch then entry.watch:Disconnect(); entry.watch = nil end -- QC M1: never two watches
	for _, d in ipairs(entry.group:GetDescendants()) do G.hidePart(entry, d) end
	if entry.group:IsA("BasePart") then G.hidePart(entry, entry.group) end
	-- Forge clones and sculptures that arrive while depleted are hidden too.
	if entry.group:IsA("Model") then
		pcall(function() entry.watch = entry.group.DescendantAdded:Connect(function(d) task.defer(G.hidePart, entry, d) end) end)
	end
end
function G.show(entry)
	entry.shown = true
	if entry.watch then entry.watch:Disconnect(); entry.watch = nil end
	for part, value in pairs(entry.saved) do
		-- A forge host keeps its mesh hidden (the mesh, not the primitive, shows).
		if part.Parent then part.LocalTransparencyModifier = if part:FindFirstChild("ShapeMesh") then 1 else value end
	end
	for part, value in pairs(entry.query) do pcall(function() part.CanQuery = value end) end
	table.clear(entry.saved)
	table.clear(entry.query)
end
-- QC L11: the forge releasing a mesh (or anything else) can set a hidden part
-- visible again while the node is depleted: hide it again, keeping the new
-- value for the restore.
function G.rehide(entry)
	for part in pairs(entry.saved) do
		if part.Parent and part.LocalTransparencyModifier ~= 1 then
			entry.saved[part] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
		end
	end
end

------------------------------------------------------------------------------
-- Depleted props: one local forge mesh slot per node, kept for reuse.
------------------------------------------------------------------------------
local function onGone(node, f) pcall(function() node.Destroying:Connect(f) end) end
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
		onGone(node, function()
			G.props[node] = nil
			prop:Destroy()
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
-- World countdown (QC L12): a small bar and "12s" over a depleted node, one
-- pooled BillboardGui per node (touch and gamepad players have no hover label).
------------------------------------------------------------------------------
function G.board(entry)
	local node = entry.node
	local b = G.boards[node]
	if not b then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NodeRespawn"
		gui.Size = UDim2.fromOffset(64, 18)
		gui.LightInfluence, gui.AlwaysOnTop, gui.MaxDistance, gui.ResetOnSpawn = 0, false, 60, false
		local back = Instance.new("Frame")
		back.Name = "Back"
		back.Size, back.Position = UDim2.new(1, 0, 0, 4), UDim2.new(0, 0, 1, -4)
		back.BackgroundColor3, back.BackgroundTransparency, back.BorderSizePixel = Color3.fromRGB(11, 16, 23), 0.2, 0
		back.Parent = gui
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3, fill.BorderSizePixel = Color3.fromRGB(133, 146, 160), 0
		fill.Parent = back
		local label = Instance.new("TextLabel")
		label.Name = "Left"
		label.Size = UDim2.new(1, 0, 1, -5)
		label.BackgroundTransparency, label.TextScaled = 1, true
		label.Font, label.TextColor3, label.TextStrokeTransparency = Enum.Font.GothamBold, Color3.fromRGB(225, 230, 236), 0.4
		label.Text = ""
		label.Parent = gui
		b = {gui = gui, fill = fill, label = label}
		G.boards[node] = b
		onGone(node, function()
			G.boards[node] = nil
			gui:Destroy()
		end)
	end
	b.gui.Adornee = node
	b.gui.StudsOffsetWorldSpace = (entry.bottom - node.CFrame.Position) + Vector3.new(0, math.clamp(entry.height, 2, 6) + 1, 0)
	local parent = holder
	pcall(function() parent = player:FindFirstChildOfClass("PlayerGui") or holder end)
	b.gui.Parent = parent
	b.gui.Enabled = true
	G.tickBoard(entry, os.clock())
	return b
end
function G.tickBoard(entry, now)
	local b = G.boards[entry.node]
	if not b then return end
	local left = math.max(0, entry.readyAt - now)
	local text = math.ceil(left) .. "s"
	if b.label.Text ~= text then b.label.Text = text end
	b.fill.Size = UDim2.fromScale(math.clamp(1 - left / math.max(0.5, entry.total), 0, 1), 1)
end
function G.unboard(node)
	local b = G.boards[node]
	if b then b.gui.Enabled = false end
end

------------------------------------------------------------------------------
-- Effects: the topple, the regrow. Tree proxies come from a small pool, one
-- per falling / regrowing tree (QC L11); with none free the effect is skipped.
------------------------------------------------------------------------------
local function proxyPart(name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color, p.Material = name, size, color, material
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	if shape then p.Shape = shape end
	return p
end
-- A pooled two-part tree proxy (trunk + crown) for the fall and the regrow. Returns proxy, token.
function G.treeProxy()
	local t = table.remove(G.treeFree)
	if not t then
		if G.treeCount >= G.TREE_POOL then return nil end
		G.treeCount += 1
		t = {token = 0, trunk = proxyPart("Falling trunk", Vector3.new(1, 1, 1), G.TINT.Woodcutting, Enum.Material.Wood),
			crown = proxyPart("Falling crown", Vector3.new(1, 1, 1), Color3.fromRGB(96, 150, 78), Enum.Material.LeafyGrass, Enum.PartType.Ball)}
	end
	t.token += 1
	return t, t.token
end
function G.releaseTree(t, token)
	if not t or t.token ~= token then return end
	t.token += 1
	t.trunk.Parent, t.crown.Parent = nil, nil
	table.insert(G.treeFree, t)
end
function G.topple(node, bottom, width, height)
	if reduced() then return end
	local t, token = G.treeProxy()
	if not t then return end
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
		value:Destroy(); G.releaseTree(t, token) -- no property signal (headless): no topple
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
		task.delay(0.4, function() G.releaseTree(t, token) end)
	end)
end
function G.sprout(entry, done)
	if reduced() then done() return end
	local t, token = G.treeProxy()
	if not t then done() return end
	entry.proxy, entry.proxyToken = t, token
	local bottom, width, height = entry.bottom, entry.width, entry.height
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
		G.releaseTree(t, token)
		done()
	end)
end

------------------------------------------------------------------------------
-- Deplete / restore.
------------------------------------------------------------------------------
-- Drops an entry at once: its saved values come back, its prop, board and
-- regrow proxy go (a node destroyed, or a re-break during the restore).
function G.drop(entry)
	if G.depleted[entry.node] == entry then G.depleted[entry.node] = nil end
	entry.restoring = false
	G.show(entry)
	if entry.prop then entry.prop.Parent = nil end
	G.unboard(entry.node)
	if entry.proxy then G.releaseTree(entry.proxy, entry.proxyToken) end
end
function G.deplete(node, seconds)
	if typeof(node) ~= "Instance" or not node:IsA("BasePart") or not node.Parent then return end
	seconds = math.max(0.5, tonumber(seconds) or 3)
	local entry = G.depleted[node]
	if entry and not entry.restoring then
		entry.readyAt = os.clock() + seconds
		entry.total = math.max(entry.total, seconds)
		G.tickBoard(entry, os.clock())
		return
	end
	-- QC M1: broken again while the regrow plays: cancel that restore (its saved
	-- values come back first) and deplete afresh.
	if entry then G.drop(entry) end
	local skill = skillOf(node)
	if not skill then return end
	local group = G.group(node)
	local bottom, width, height = G.footing(node, group)
	local only = if skill == "Fishing" then G.CALM else G.BARE[node:GetAttribute("GatherNode")]
	entry = {node = node, skill = skill, group = group, saved = {}, query = {}, readyAt = os.clock() + seconds, total = seconds, bottom = bottom,
		width = width, height = height, only = only, calm = skill == "Fishing",
		-- A Crew Haven store (§42 StrikeKind "crew") just empties: no stump, no topple.
		plain = node:GetAttribute("StrikeKind") == "crew"}
	G.depleted[node] = entry
	G.hide(entry)
	entry.prop = if only or entry.plain then nil else G.prop(node, skill, bottom, width)
	G.board(entry)
	if skill == "Woodcutting" and not entry.plain then
		G.topple(node, bottom, width, height)
	else
		G.fx(bottom + Vector3.new(0, math.min(height, 3) * 0.6, 0), G.FX_COLOR[skill], if skill == "Mining" then 18 else 12, if skill == "Fishing" or only then 4 else 9)
	end
end
function G.restore(node)
	local entry = G.depleted[node]
	if not entry or entry.restoring then return end
	-- The entry stays depleted (restoring) until the regrow effect finishes.
	entry.restoring = true
	G.unboard(node)
	local function finish()
		if G.depleted[node] ~= entry or not entry.restoring then return end -- cancelled by a re-break
		G.depleted[node] = nil
		entry.restoring = false
		if entry.prop then entry.prop.Parent = nil end
		G.show(entry)
	end
	if entry.skill == "Woodcutting" and not entry.plain then
		if entry.prop then entry.prop.Parent = nil end
		G.sprout(entry, finish)
	else
		finish()
		G.fx(entry.bottom + Vector3.new(0, math.min(entry.height, 3) * 0.6, 0), if entry.skill == "Mining" then Color3.fromRGB(255, 236, 170) else G.FX_COLOR[entry.skill], 10, 4)
	end
end
function G.left(node)
	local entry = G.depleted[node]
	return if entry and not entry.restoring then math.max(0, entry.readyAt - os.clock()) else 0
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
			G.drop(entry)
		elseif entry.restoring then
			continue
		elseif now >= entry.readyAt then
			G.restore(node)
		else
			G.rehide(entry)
			G.tickBoard(entry, now)
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
