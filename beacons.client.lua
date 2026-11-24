-- Travel beacons (client; docs/DEPTH-CONTRACT.md §44). The server builds every
-- travel beacon as one prompt post carrying a forged dais (TravelBeacon /
-- TravelBeaconBasalt in a declared ShapeBox) and every Skyward Vent as a
-- SkywardVentPad; this script draws what moves, locally and pooled:
--   * a floating aether crystal (TravelBeaconCrystal) inside an armillary
--     (TravelBeaconRings) over the nearest beacons (vents: a wider armillary
--     only). They are client-only Shape hosts, forged by the MeshForge like any
--     other slot; at most POOL sets (desktop 8, phones 4) serve the beacons
--     within RADIUS, re-assigned twice a second; idle sets park far below the
--     world, where the forge releases their meshes. No static part is added.
--   * bob and spin every frame, unless reduced motion (Theme.reducedMotion):
--     then every piece holds a still pose.
--   * per-player state. A beacon whose TravelBeaconRegion the player can
--     neither enter (snapshot regions[].unlocked) nor warp to (snapshot
--     regionQuests.warps), or a crew beacon (TravelBeaconNeeds = "crew") without
--     a CoopId, is "locked": its crystal goes dark and sinks into the socket,
--     the rings stop, no motes rise and its light's Color dims. "open" beacons
--     glow; "learned" ones (warp known) glow and turn fastest. The §35 director
--     keeps owning each light's Enabled / Brightness / Shadows (budget, caps,
--     night boost); this script only ever writes a light's Color.
--   * TravelBeaconFlare (bumped by the server on every successful trip, with
--     TravelBeaconFlareBy): a short flare (an expanding neon shell and a burst of
--     motes) and a whoosh at the beacon, plus a chime for the traveller.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local B = {}
local mobile = false
pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)
B.POOL = if mobile then 4 else 8
B.RADIUS = if mobile then 140 else 220
B.FLARE_RADIUS = 260
B.FLARE_SECONDS = 0.7
B.DORMANT = Color3.fromRGB(52, 58, 72)
B.DIM = 0.78 -- a locked beacon's light colour is lerped this far toward black
B.CRYSTAL = Vector3.new(1.1, 2.4, 1.1) * 0.85
B.RINGS = Vector3.new(2.3, 2.3, 2.3) * 0.95
B.VENT_RINGS = Vector3.new(2.3, 2.3, 2.3) * 1.7
B.SINK = -0.95 -- a locked crystal rests in its socket
B.SPIN = {learned = 1.25, open = 0.8, locked = 0}
B.MOTES = {learned = 7, open = 4, locked = 0}
B.WHOOSH = "rbxasset://sounds/swordlunge.wav"
B.CHIME = "rbxasset://sounds/electronicpingshort.wav"

-- Pure rules ---------------------------------------------------------------
-- beacon = {kind, region, needs}; ctx = {open = set | nil (no snapshot yet),
-- warps = set | nil, crew = bool} -> "locked" | "open" | "learned".
function B.state(beacon, ctx)
	if beacon.needs == "crew" then return if ctx.crew then "open" else "locked" end
	local region = beacon.region
	if type(region) ~= "string" then return "open" end
	if ctx.warps and ctx.warps[region] == true then return "learned" end
	if ctx.open == nil then return "open" end -- before the first snapshot: never flash dark
	return if ctx.open[region] == true then "open" else "locked"
end
-- Folds a snapshot into the context (partial snapshots keep what they lack).
function B.context(snapshot, ctx)
	ctx = ctx or {}
	if type(snapshot) ~= "table" then return ctx end
	if type(snapshot.regions) == "table" then
		local open = {}
		for _, r in ipairs(snapshot.regions) do
			if type(r) == "table" and type(r.id) == "string" and r.unlocked == true then open[r.id] = true end
		end
		ctx.open = open
	end
	local rq = snapshot.regionQuests
	if type(rq) == "table" and type(rq.warps) == "table" then
		local warps = {}
		for region, known in pairs(rq.warps) do if type(region) == "string" and known == true then warps[region] = true end end
		ctx.warps = warps
	end
	return ctx
end
-- Nearest beacons within radius, at most cap: list of {beacon, distance}.
function B.nearest(list, origin, cap, radius)
	local near = {}
	for _, beacon in ipairs(list) do
		local d = (beacon.hover - origin).Magnitude
		if d <= radius then table.insert(near, {beacon, d}) end
	end
	table.sort(near, function(a, b) return a[2] < b[2] end)
	for i = #near, cap + 1, -1 do near[i] = nil end
	return near
end
-- Pose at time t: crystal offset (y), crystal yaw, rings yaw.
function B.pose(t, state, reduced, seed)
	if state == "locked" then return B.SINK, seed, seed * 0.5 end
	if reduced then return 0, seed, seed * 0.5 end
	local spin = B.SPIN[state] or B.SPIN.open
	return math.sin(t * 1.6 + seed) * 0.14, seed + t * spin, seed * 0.5 - t * spin * 0.55
end
-- Flare at time since start: shell scale (studs) and transparency, or nil when done.
function B.flare(elapsed, reduced)
	local k = elapsed / B.FLARE_SECONDS
	if k >= 1 then return nil end
	local size = if reduced then 3 else 1.5 + 7 * (1 - (1 - k) ^ 3)
	return size, 0.15 + 0.85 * k
end
function B.lightColor(base, state)
	return if state == "locked" then base:Lerp(Color3.new(0, 0, 0), B.DIM) else base
end

if BeaconTest then
	BeaconTest.beacons = B
	return
end

-- Runtime ------------------------------------------------------------------
local player = Players.LocalPlayer
local Theme
pcall(function()
	local module = ReplicatedStorage:WaitForChild("AetherUiTheme", 15)
	if module then Theme = require(module) end
end)
local function reducedMotion()
	return Theme ~= nil and type(Theme.reducedMotion) == "function" and Theme.reducedMotion(player) == true
end

local folder = Instance.new("Folder")
folder.Name = "TravelBeaconFx"
folder.Parent = workspace
local PARK = CFrame.new(0, -12000, 0)
local ctx = {crew = player:GetAttribute("CoopId") ~= nil}
local beacons = {} -- part -> record
local list = {}
local sets = {}
local flares = {}
local lightBase = setmetatable({}, {__mode = "k"})

local function hostPart(name, shape, size, transparency)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = name, true, false, false, false, false
	p.Size, p.CFrame, p.Material, p.Transparency = size, PARK, Enum.Material.Glass, transparency
	p:SetAttribute("Shape", shape)
	p.Parent = folder
	return p
end
local function newSet()
	local set = {}
	set.crystal = hostPart("Beacon crystal", "TravelBeaconCrystal", B.CRYSTAL, 0.2)
	set.rings = hostPart("Beacon rings", "TravelBeaconRings", B.RINGS, 1)
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Beacon motes"
	motes.Enabled, motes.Rate, motes.LightEmission, motes.LightInfluence = false, 4, 1, 0
	motes.Lifetime, motes.Speed = NumberRange.new(1.8, 2.8), NumberRange.new(0.6, 1.4)
	motes.SpreadAngle, motes.Acceleration = Vector2.new(25, 25), Vector3.new(0, 1.2, 0)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0)})
	motes.Transparency = NumberSequence.new(0.2, 1)
	motes.Parent = set.crystal
	set.motes = motes
	return set
end

local function beaconLight(part)
	local anchor = part:FindFirstChild("Light anchor")
	return anchor and anchor:FindFirstChildWhichIsA("Light") or nil
end
local function applyState(record)
	local state = B.state(record, ctx)
	if state == record.state then return end
	record.state = state
	local l = beaconLight(record.part)
	if l then
		lightBase[l] = lightBase[l] or l.Color
		local color = B.lightColor(lightBase[l], state)
		if l.Color ~= color then l.Color = color end
	end
	if record.set then record.set.dirty = true end
end
local function refreshStates()
	ctx.crew = player:GetAttribute("CoopId") ~= nil
	for _, record in ipairs(list) do applyState(record) end
end

-- Flares ----------------------------------------------------------------------
local chime = Instance.new("Sound")
chime.Name, chime.SoundId, chime.Volume = "BeaconChime", B.CHIME, 0.3
chime.Parent = folder
local function playFlare(record)
	local part = record.part
	local by = part:GetAttribute("TravelBeaconFlareBy")
	if by == player.UserId then pcall(function() chime:Play() end) end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local origin = (root and root.Position) or (camera and camera.CFrame.Position)
	if not origin or (record.hover - origin).Magnitude > B.FLARE_RADIUS then return end
	local tint = record.tint
	local shell = Instance.new("Part")
	shell.Name, shell.Shape, shell.Material = "Beacon flare", Enum.PartType.Ball, Enum.Material.Neon
	shell.Anchored, shell.CanCollide, shell.CanTouch, shell.CanQuery, shell.CastShadow = true, false, false, false, false
	shell.Color, shell.Size, shell.CFrame, shell.Transparency = tint:Lerp(Color3.new(1, 1, 1), 0.35), Vector3.one * 1.5, CFrame.new(record.hover), 0.15
	shell.Parent = folder
	local burst = Instance.new("ParticleEmitter")
	burst.Enabled, burst.LightEmission, burst.LightInfluence = false, 1, 0
	burst.Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.5), tint)
	burst.Lifetime, burst.Speed, burst.SpreadAngle = NumberRange.new(0.6, 1.1), NumberRange.new(6, 12), Vector2.new(180, 180)
	burst.Acceleration = Vector3.new(0, 6, 0)
	burst.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0)})
	burst.Transparency = NumberSequence.new(0, 1)
	burst.Parent = shell
	local reduced = reducedMotion()
	burst:Emit(if reduced then 10 else 28)
	local whoosh = Instance.new("Sound")
	whoosh.SoundId, whoosh.Volume, whoosh.PlaybackSpeed, whoosh.RollOffMaxDistance = B.WHOOSH, 0.45, 0.55, 90
	whoosh.Parent = shell
	pcall(function() whoosh:Play() end)
	table.insert(flares, {shell = shell, start = os.clock(), reduced = reduced})
	if #flares > 4 then local oldest = table.remove(flares, 1); oldest.shell:Destroy() end
end

-- Registry --------------------------------------------------------------------
local function register(part)
	if beacons[part] or not part:IsA("BasePart") or type(part:GetAttribute("TravelBeacon")) ~= "string" then return end
	local hover = part:GetAttribute("TravelBeaconHover")
	local tint = part:GetAttribute("Tint")
	local record = {
		part = part, kind = part:GetAttribute("TravelBeacon"), region = part:GetAttribute("TravelBeaconRegion"),
		needs = part:GetAttribute("TravelBeaconNeeds"), hover = if typeof(hover) == "Vector3" then hover else part.Position + Vector3.new(0, 1, 0),
		tint = if typeof(tint) == "Color3" then tint else Color3.fromRGB(142, 230, 203), seed = (#list % 7) * 0.9,
	}
	beacons[part] = record
	table.insert(list, record)
	applyState(record)
	record.flareConnection = part:GetAttributeChangedSignal("TravelBeaconFlare"):Connect(function() playFlare(record) end)
end
local function drop(record)
	beacons[record.part] = nil
	if record.flareConnection then record.flareConnection:Disconnect() end
	if record.set then record.set.beacon = nil; record.set.dirty = true; record.set = nil end
end
local function watch(instance)
	if not instance:IsA("BasePart") then return end
	if type(instance:GetAttribute("TravelBeacon")) == "string" then register(instance) end
end
workspace.DescendantAdded:Connect(function(instance) task.defer(watch, instance) end)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end

local function observe(snapshot)
	if type(snapshot) ~= "table" or (snapshot.regions == nil and snapshot.regionQuests == nil) then return end
	B.context(snapshot, ctx)
	for _, record in ipairs(list) do record.state = nil end
	refreshStates()
end
player:GetAttributeChangedSignal("CoopId"):Connect(function()
	for _, record in ipairs(list) do if record.needs then record.state = nil end end
	refreshStates()
end)
task.spawn(function()
	local updates = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if updates then updates.OnClientEvent:Connect(observe) end
	local channel = ReplicatedStorage:WaitForChild("IsleSnapshotLocal", 30)
	if channel and channel:IsA("BindableEvent") then channel.Event:Connect(observe) end
end)

-- Pool assignment (twice a second) ----------------------------------------------
local function focus()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then return root.Position end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end
local function dress(set)
	local record = set.beacon
	set.dirty = false
	if not record then
		set.crystal.CFrame, set.rings.CFrame, set.motes.Enabled = PARK, PARK, false
		return
	end
	local vent = record.kind == "vent"
	local state = record.state or "open"
	local crystalTint = if state == "locked" then B.DORMANT else record.tint
	local ringTint = if state == "locked" then record.tint:Lerp(B.DORMANT, 0.7) else record.tint
	if set.crystal:GetAttribute("Tint") ~= crystalTint then set.crystal:SetAttribute("Tint", crystalTint) end
	if set.rings:GetAttribute("Tint") ~= ringTint then set.rings:SetAttribute("Tint", ringTint) end
	set.crystal.Color = crystalTint
	local ringSize = if vent then B.VENT_RINGS else B.RINGS
	if set.rings.Size ~= ringSize then set.rings.Size = ringSize end
	set.motes.Color = ColorSequence.new(record.tint:Lerp(Color3.new(1, 1, 1), 0.45), record.tint)
	set.motes.Rate = (B.MOTES[state] or 0) * (if mobile then 0.5 else 1)
	set.motes.Enabled = not vent and state ~= "locked"
	set.posed = nil
	if vent then set.crystal.CFrame = PARK end
end
local function assign()
	for i = #list, 1, -1 do
		local record = list[i]
		if not record.part.Parent or not record.part:IsDescendantOf(workspace) then
			drop(record)
			table.remove(list, i)
		end
	end
	local origin = focus()
	if not origin then return end
	local near = B.nearest(list, origin, B.POOL, B.RADIUS)
	local wanted = {}
	for _, item in ipairs(near) do wanted[item[1]] = true end
	for _, set in ipairs(sets) do
		if set.beacon and not wanted[set.beacon] then set.beacon.set = nil; set.beacon = nil; set.dirty = true end
	end
	for _, item in ipairs(near) do
		local record = item[1]
		if not record.set then
			local free
			for _, set in ipairs(sets) do if not set.beacon then free = set; break end end
			if not free and #sets < B.POOL then free = newSet(); table.insert(sets, free) end
			if free then free.beacon, record.set, free.dirty = record, free, true end
		end
	end
	for _, set in ipairs(sets) do if set.dirty then dress(set) end end
end

-- Frame: bob / spin (still under reduced motion) and the flares --------------------
local stillReduced = false
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local reduced = reducedMotion()
	if reduced ~= stillReduced then
		stillReduced = reduced
		for _, set in ipairs(sets) do set.posed = nil end
	end
	for _, set in ipairs(sets) do
		local record = set.beacon
		if record and (not set.posed or (not reduced and record.state ~= "locked")) then
			local lift, yaw, ringYaw = B.pose(t, record.state or "open", reduced, record.seed)
			if record.kind == "vent" then
				set.rings.CFrame = CFrame.new(record.hover + Vector3.new(0, lift * 0.5, 0)) * CFrame.Angles(0, ringYaw, 0)
			else
				local at = record.hover + Vector3.new(0, lift, 0)
				set.crystal.CFrame = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
				set.rings.CFrame = CFrame.new(record.hover) * CFrame.Angles(0, ringYaw, 0)
			end
			set.posed = true
		end
	end
	for i = #flares, 1, -1 do
		local f = flares[i]
		local size, transparency = B.flare(t - f.start, f.reduced)
		if size then
			f.shell.Size, f.shell.Transparency = Vector3.one * size, transparency
		else
			f.shell:Destroy()
			table.remove(flares, i)
		end
	end
end)
task.spawn(function()
	while true do
		assign()
		task.wait(0.5)
	end
end)
