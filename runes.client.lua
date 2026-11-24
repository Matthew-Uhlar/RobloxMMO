-- Runebinding client (StarterPlayerScripts.IsleRunes; docs/DEPTH-CONTRACT.md §49).
--   * Pouch indicator: a chip at the action bar's left end ("◆ satchel shards /
--     28   ◇ pouch shards / capacity", worn pouches flagged) whenever you carry
--     shards or stand in the Shardhollow (snapshot `runebinding`, relayed on
--     IsleSnapshotLocal).
--   * Rift HUD (top centre): the Glyph Rift phase and timer, the Guardian's power
--     bar, the two open portals in their colours, your fragments / essence /
--     contribution (player attribute RiftState) and a Leave button
--     (IsleActionLocal "riftLeave"). From workspace GlyphRift.
--   * Waygate picker: when the server accepts the Waygate prompt it bumps the
--     player attribute RuneWaygate; the panel lists the eleven altars (locked
--     ones greyed with their level) and sends `rbTravel <altar>`.
--   * Altars: keystones within KEYSTONE_RANGE bob, spin and glow locally (Neon +
--     a PointLight, client-side only); a bind (player attribute RuneBind
--     "seq:altar:runes", every player) bursts rune sparks and an expanding glyph
--     ring at that altar. Open guardian portals shimmer; the Rift Guardian's
--     light follows its power. Reduced motion keeps the colour, drops the
--     tweens and most particles.
-- Nothing here grants anything: the server checks every verb.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Tags = game:GetService("CollectionService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local make = T.make
local RB = Data.Runebinding

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots = channel("IsleActionLocal"), channel("IsleSnapshotLocal")
local function tbl(v) return if type(v) == "table" then v else {} end

local S = {state = nil, keystones = {}, portals = {}, seen = {}, watched = {}, lastWaygate = player:GetAttribute("RuneWaygate")}
S.KEYSTONE_RANGE = 160
S.FX_RANGE = 140
local function reduced() return T.reducedMotion and T.reducedMotion(player) or false end
local function rootPos()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end
local function inField()
	local pos = rootPos()
	if not pos then return false end
	return (pos - Vector3.new(1500, 200, 1500)).Magnitude < 140
end

------------------------------------------------------------------------------
-- HUD: pouch indicator + Rift panel + waygate picker
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleRunes", ResetOnSpawn = false, DisplayOrder = 9,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local chip = make("Frame", gui, {Name = "PouchChip", Visible = false, BorderSizePixel = 0, Size = UDim2.fromOffset(220, 26),
	BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.1})
make("UICorner", chip, {CornerRadius = UDim.new(0, 8)})
make("UIStroke", chip, {Color = Color3.fromHex("C38BFF"), Thickness = 1.5})
local chipText = T.label(chip, {Name = "Carry", Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(8, 0), Text = "", TextSize = 13})

local rift = make("Frame", gui, {Name = "RiftHud", Visible = false, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(330, 96), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.08})
make("UICorner", rift, {CornerRadius = UDim.new(0, 10)})
make("UIStroke", rift, {Color = Color3.fromHex("C38BFF"), Thickness = 2})
local riftTitle = T.label(rift, {Name = "Title", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -90, 0, 20), Text = "GLYPH RIFT",
	Font = T.font.display, TextSize = 15})
local riftTimer = T.label(rift, {Name = "Timer", Position = UDim2.new(1, -80, 0, 6), Size = UDim2.fromOffset(68, 20), Text = "",
	TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right})
local barBack = make("Frame", rift, {Name = "Power", Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 12), BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromHex("231B33")})
make("UICorner", barBack, {CornerRadius = UDim.new(0, 6)})
local barFill = make("Frame", barBack, {Name = "Fill", Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("C38BFF")})
make("UICorner", barFill, {CornerRadius = UDim.new(0, 6)})
local barText = T.label(barBack, {Name = "Pct", Size = UDim2.fromScale(1, 1), Text = "", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3})
local portalText = T.label(rift, {Name = "Portals", Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 18), Text = "", TextSize = 13, RichText = true})
local mineText = T.label(rift, {Name = "Mine", Position = UDim2.fromOffset(12, 68), Size = UDim2.new(1, -96, 0, 20), Text = "", TextSize = 13})
local leave = make("TextButton", rift, {Name = "Leave", Text = "Leave", AutoButtonColor = true, Position = UDim2.new(1, -80, 0, 66),
	Size = UDim2.fromOffset(68, 22), BackgroundColor3 = Color3.fromHex("5A2E3F"), TextColor3 = Color3.new(1, 1, 1), Font = T.font.display, TextSize = 13})
make("UICorner", leave, {CornerRadius = UDim.new(0, 6)})
leave.Activated:Connect(function() actions:Fire("riftLeave") end)

local picker = make("Frame", gui, {Name = "WaygatePicker", Visible = false, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 420), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.04})
make("UICorner", picker, {CornerRadius = UDim.new(0, 12)})
make("UIStroke", picker, {Color = Color3.fromHex("C38BFF"), Thickness = 2})
T.label(picker, {Name = "Title", Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -60, 0, 26), Text = "SHARDHOLLOW WAYGATE", Font = T.font.display, TextSize = 17})
local close = make("TextButton", picker, {Name = "Close", Text = "✕", Position = UDim2.new(1, -38, 0, 8), Size = UDim2.fromOffset(28, 26),
	BackgroundColor3 = Color3.fromHex("3B2A5C"), TextColor3 = Color3.new(1, 1, 1), TextSize = 16})
make("UICorner", close, {CornerRadius = UDim.new(0, 6)})
local list = make("ScrollingFrame", picker, {Name = "Altars", Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 1, -50), BorderSizePixel = 0,
	BackgroundTransparency = 1, ScrollBarThickness = 6, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y})
make("UIListLayout", list, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
close.Activated:Connect(function() picker.Visible = false end)
S.chip, S.rift, S.picker = chip, rift, picker

function S.layout()
	local size = gui.AbsoluteSize
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then local cam = workspace.CurrentCamera; local v = cam and cam.ViewportSize or Vector2.new(1366, 768); w, h = v.X, v.Y end
	local L = T.hudLayout(w, h, {touch = Input.TouchEnabled, lift = player:GetAttribute("IsleHudLift")})
	local cw = math.min(220, L.action.w)
	-- Desktop: above the action bar's left end (the heart chip owns the right side);
	-- touch: above its right end (the heart chip sits over the band's left edge).
	local x = if L.touch then L.action.x + L.action.w - cw else L.action.x
	chip.Size = UDim2.fromOffset(cw, 26)
	chip.Position = UDim2.fromOffset(x, L.action.y - 6 - 26)
	rift.Position = UDim2.new(0.5, 0, 0, if L.touch then 8 else 64)
	picker.Size = UDim2.fromOffset(math.min(360, w - 32), math.min(420, h - 60))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(S.layout)
player:GetAttributeChangedSignal("IsleHudLift"):Connect(S.layout)
S.layout()

function S.drawChip()
	local st = S.state
	local show = st ~= nil and (tonumber(st.carried) or 0) + (tonumber(st.pouchHeld) or 0) > 0 or (st ~= nil and inField())
	chip.Visible = show == true
	if show then chipText.Text = RB.carryText(st) end
end
local PHASE = {lobby = "GATHERING", active = "ROUND", rest = "RESTING", idle = "QUIET"}
function S.drawRift()
	local r = RB.parseRift(workspace:GetAttribute("GlyphRift"))
	local frags, essence, contrib = RB.parseRiftState(player:GetAttribute("RiftState"))
	local member = player:GetAttribute("RiftState") ~= nil and player:GetAttribute("RiftState") ~= ""
	local show = r ~= nil and r.phase ~= "idle" and (member or inField())
	rift.Visible = show
	S.drawPortals(r)
	if not show then return end
	riftTitle.Text = "GLYPH RIFT · " .. (PHASE[r.phase] or string.upper(r.phase)) .. (if r.round > 0 then " " .. r.round else "")
	riftTimer.Text = string.format("%d:%02d", r.left // 60, r.left % 60)
	local frac = math.clamp(r.power / r.goal, 0, 1)
	barFill.Size = UDim2.fromScale(frac, 1)
	barText.Text = "Guardian " .. math.floor(frac * 100 + 0.5) .. "%   ·   " .. r.members .. " binder" .. (if r.members == 1 then "" else "s")
	local function chipFor(id)
		local a = id and RB.AltarById[id]
		return if a then '<font color="#' .. a.color .. '">◈ ' .. a.id .. "</font> (" .. a.level .. ")" else "—"
	end
	portalText.Text = if r.phase == "active" then "Open portals: " .. chipFor(r.low) .. "   " .. chipFor(r.high) else "Portals dark · next round soon"
	mineText.Text = if member then "Fragments " .. frags .. "   Essence " .. essence .. "/" .. RB.Rift.ESSENCE_CAP .. "   Given " .. contrib else "Enter at the Rift plinth"
	leave.Visible = member
end
function S.openPicker()
	for _, child in ipairs(list:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
	local level = tonumber(tbl(S.state).level) or 1
	for i, row in ipairs(RB.pickerRows(level)) do
		local b = make("TextButton", list, {Name = row.id, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 32), AutoButtonColor = row.open,
			BackgroundColor3 = if row.open then Color3.fromHex("2E2546") else Color3.fromHex("1E1A28"), TextXAlignment = Enum.TextXAlignment.Left,
			Text = "   " .. row.name .. "  ·  " .. row.isle .. (if row.open then "" else "   (Runebinding " .. row.level .. ")"),
			TextColor3 = if row.open then Color3.fromHex(row.color) else Color3.fromHex("7C7591"), Font = T.font.body or Enum.Font.Gotham, TextSize = 14})
		make("UICorner", b, {CornerRadius = UDim.new(0, 6)})
		if row.open then
			b.Activated:Connect(function()
				picker.Visible = false
				actions:Fire("rbTravel", row.id)
			end)
		end
	end
	picker.Visible = true
	S.pickerAt = os.clock()
end
player:GetAttributeChangedSignal("RuneWaygate"):Connect(function()
	local v = player:GetAttribute("RuneWaygate")
	if v ~= nil and v ~= S.lastWaygate then S.lastWaygate = v; S.openPicker() end
end)

function S.accept(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.runebinding) ~= "table" then return end
	S.state = snapshot.runebinding
	S.drawChip()
end
snapshots.Event:Connect(S.accept)
actions:Fire("snapshot")

------------------------------------------------------------------------------
-- World: keystones, bind bursts, portals, the Guardian
------------------------------------------------------------------------------
local function altarBase(id)
	for _, base in ipairs(Tags:GetTagged("RuneAltar")) do
		if base:GetAttribute("AltarId") == id then return base end
	end
	return nil
end
local function keystoneOf(base)
	local model = base and base.Parent
	if not model then return nil end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("AltarKeystone") ~= nil then return child end
	end
	return nil
end
-- One-time local glow on a keystone (client-side Neon + light; the server keeps glass).
function S.dress(stone)
	if S.keystones[stone] then return S.keystones[stone] end
	local rec = {home = stone.CFrame, phase = (#Tags:GetTagged("RuneAltar") % 7) * 0.9 + math.random() * 2}
	pcall(function()
		stone.Material = Enum.Material.Neon
		stone.Transparency = 0.05
		local l = Instance.new("PointLight")
		l.Name = "Keystone glow"
		l.Color, l.Brightness, l.Range, l.Shadows = stone.Color, 0.9, 12, false
		l.Parent = stone
		rec.light = l
		local e = Instance.new("ParticleEmitter")
		e.Name = "Keystone motes"
		e.Rate, e.LightEmission, e.Enabled = 3, 0.8, true
		e.Lifetime, e.Speed = NumberRange.new(1.2, 2), NumberRange.new(0.6, 1.4)
		e.Size = NumberSequence.new(0.18, 0)
		e.Color = ColorSequence.new(stone.Color)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = stone
		rec.motes = e
	end)
	S.keystones[stone] = rec
	return rec
end
function S.burst(altarId, runes)
	local base = altarBase(altarId)
	local pos = rootPos()
	if not base or not pos or (base.Position - pos).Magnitude > S.FX_RANGE then return end
	local stone = keystoneOf(base)
	local a = RB.AltarById[altarId]
	local color = Color3.fromHex(a and a.color or "C38BFF")
	local calm = reduced()
	pcall(function()
		local e = base:FindFirstChild("Bind sparks")
		if not e then
			e = Instance.new("ParticleEmitter")
			e.Name = "Bind sparks"
			e.Enabled, e.LightEmission = false, 1
			e.Lifetime, e.Speed = NumberRange.new(0.8, 1.6), NumberRange.new(6, 12)
			e.Size = NumberSequence.new(0.3, 0)
			e.SpreadAngle = Vector2.new(25, 25)
			e.EmissionDirection = Enum.NormalId.Top
			e.Acceleration = Vector3.new(0, -4, 0)
			e.Parent = base
		end
		e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		e:Emit(if calm then 6 else math.clamp(10 + (tonumber(runes) or 0), 12, 48))
	end)
	if stone then
		local rec = S.dress(stone)
		if rec.light then
			rec.light.Brightness = 1.5
			if not calm then TweenService:Create(rec.light, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {Brightness = 0.9}):Play()
			else task.delay(0.6, function() if rec.light then rec.light.Brightness = 0.9 end end) end
		end
	end
	if not calm then
		-- An expanding glyph ring on the plinth.
		pcall(function()
			local ring = Instance.new("Part")
			ring.Name = "Bind ring"
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
			ring.Material = Enum.Material.Neon
			ring.Color = color
			ring.Transparency = 0.25
			ring.Size = Vector3.new(0.08, 3, 3)
			ring.CFrame = CFrame.new(base.Position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Parent = workspace
			TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(0.08, 11, 11), Transparency = 1}):Play()
			task.delay(0.9, function() ring:Destroy() end)
		end)
	end
end
local function watch(other)
	if S.watched[other] then return end
	S.watched[other] = other:GetAttributeChangedSignal("RuneBind"):Connect(function()
		local v = other:GetAttribute("RuneBind")
		local seq, altar, runes = string.match(type(v) == "string" and v or "", "^(%d+):(%a+):(%d+)$")
		if not seq then return end
		local key = other.UserId .. ":" .. seq
		if S.seen[key] then return end
		S.seen[key] = true
		S.burst(altar, tonumber(runes))
	end)
end
for _, other in ipairs(Players:GetPlayers()) do watch(other) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(other)
	local c = S.watched[other]
	if c then c:Disconnect() end
	S.watched[other] = nil
end)

function S.drawPortals(r)
	local open = {}
	if r and r.phase == "active" then
		if r.low then open[r.low] = true end
		if r.high then open[r.high] = true end
	end
	for _, portal in ipairs(Tags:GetTagged("RiftPortal")) do
		local id = portal:GetAttribute("RiftPortal")
		local rec = S.portals[portal]
		if not rec then
			rec = {}
			pcall(function()
				local a = RB.AltarById[id]
				local color = Color3.fromHex(a and a.color or "C38BFF")
				local e = Instance.new("ParticleEmitter")
				e.Name = "Portal shimmer"
				e.Enabled, e.Rate, e.LightEmission = false, 14, 1
				e.Lifetime, e.Speed = NumberRange.new(0.8, 1.4), NumberRange.new(0.5, 2)
				e.Size = NumberSequence.new(0.35, 0)
				e.Color = ColorSequence.new(color)
				e.Parent = portal
				local l = Instance.new("PointLight")
				l.Name = "Portal glow"
				l.Color, l.Brightness, l.Range, l.Enabled = color, 1.2, 14, false
				l.Parent = portal
				rec.emitter, rec.light = e, l
			end)
			S.portals[portal] = rec
		end
		local on = open[id] == true
		if rec.emitter then rec.emitter.Enabled = on and not reduced() end
		if rec.light then rec.light.Enabled = on end
	end
	-- The Guardian's light follows its power.
	local guardian = S.guardian
	if not guardian or not guardian.Parent then
		guardian = nil
		local root = workspace:FindFirstChild("AetherIsles")
		local field = root and root:FindFirstChild(RB.FIELD)
		if field then
			for _, d in ipairs(field:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("RiftGuardian") then guardian = d break end end
		end
		S.guardian = guardian
		if guardian and not guardian:FindFirstChild("Guardian glow") then
			pcall(function()
				local l = Instance.new("PointLight")
				l.Name = "Guardian glow"
				l.Color, l.Range, l.Brightness = Color3.fromHex("C38BFF"), 28, 0.4
				l.Parent = guardian
			end)
		end
	end
	local glow = guardian and guardian:FindFirstChild("Guardian glow")
	if glow then glow.Brightness = 0.4 + 1.4 * (if r and r.phase == "active" then math.clamp(r.power / r.goal, 0, 1) else 0) end
end

-- Keystones bob and spin (nearby altars only, a reused list each frame).
local near, nearAt = {}, 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local pos = rootPos()
	if now - nearAt > 1 then
		nearAt = now
		table.clear(near)
		if pos then
			for _, base in ipairs(Tags:GetTagged("RuneAltar")) do
				if (base.Position - pos).Magnitude <= S.KEYSTONE_RANGE then
					local stone = keystoneOf(base)
					if stone then table.insert(near, stone) end
				end
			end
		end
		S.drawRift()
		S.drawChip()
		if picker.Visible and S.pickerAt and now - S.pickerAt > 30 then picker.Visible = false end
	end
	if reduced() then return end
	for _, stone in ipairs(near) do
		local rec = S.dress(stone)
		local t = now + rec.phase
		pcall(function() stone.CFrame = rec.home * CFrame.new(0, math.sin(t * 1.6) * 0.25, 0) * CFrame.Angles(0, t * 0.8, 0) end)
	end
end)
workspace:GetAttributeChangedSignal("GlyphRift"):Connect(S.drawRift)
player:GetAttributeChangedSignal("RiftState"):Connect(S.drawRift)
S.drawRift()
