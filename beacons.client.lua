-- Travel beacons (client; docs/DEPTH-CONTRACT.md §44). The server builds every
-- travel beacon as one prompt post carrying a forged dais (TravelBeacon /
-- TravelBeaconBasalt in a declared ShapeBox) and every Skyward Vent as a
-- SkywardVentPad; this script draws what moves, locally and pooled:
--   * a floating aether crystal (TravelBeaconCrystal, or the cloudy, cracked
--     TravelBeaconCrystalDormant on a locked beacon) inside an armillary
--     (TravelBeaconRings) over the nearest beacons (vents: a wider armillary
--     only, high over the updraft). They are client-only, invisible Shape hosts
--     forged by the MeshForge like any other slot; at most POOL sets (desktop 8,
--     phones 4) serve the beacons within RADIUS, re-assigned twice a second;
--     idle sets park far below the world, where the forge releases their meshes.
--     A set is posed at its beacon before any Shape / Tint write, so the forge
--     re-forges it where it is drawn. Tints snap to a small fixed palette (and
--     constant dormant tints) so the forge's exact-tint templates stay few.
--     No static part is added.
--   * bob and spin every frame, unless reduced motion (Theme.reducedMotion,
--     sampled twice a second): then every piece holds a still pose.
--   * per-player state. A beacon whose TravelBeaconRegion the player cannot
--     enter (snapshot.depth.regions[].unlocked merged with snapshot.regions;
--     regions with no requirement are always open), or a crew beacon
--     (TravelBeaconNeeds = "crew") without a CoopId, is "locked": the dormant
--     crystal sinks into the socket, the rings stop in a constant dormant tint,
--     no motes rise and its light's Color dims. "open" beacons glow; "learned"
--     ones (open and the warp known, snapshot.regionQuests.warps) glow in a
--     brighter tint and turn fastest. The §35 director keeps owning each light's
--     Enabled / Brightness / Shadows (budget, caps, night boost); this script
--     only ever writes a light's Color.
--   * TravelBeaconFlare (bumped by the server on every successful trip, with
--     TravelBeaconFlareBy): a short flare (an expanding neon shell and a burst of
--     motes) and a whoosh at the beacon, plus a chime for the traveller.
-- Beacons are found by the CollectionService tag TravelBeacon.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local B = {}
local mobile = false
pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)
B.mobile = mobile
B.POOL = if mobile then 4 else 8
B.RADIUS = if mobile then 140 else 220
B.FLARE_RADIUS = 260
B.FLARE_SECONDS = 0.7
B.FLARE_CAP = 4
B.MOTION_SECONDS = 0.5 -- reduced motion is sampled this often, not every frame
B.DIM = 0.78 -- a locked beacon's light colour is lerped this far toward black
-- Host sizes are the shapes' fit boxes (= their mesh bounds) times one scale,
-- so the lit and dormant crystals read the same size.
B.CRYSTAL = Vector3.new(1.358, 2.4, 1.358) * 0.85
B.CRYSTAL_DORMANT = Vector3.new(1.64, 2.4, 1.64) * 0.85
B.RINGS = Vector3.new(2.38, 2.178, 2.38) * 0.95
B.VENT_SCALE = 1.7 / 0.95 -- vents: ShapeScale on the same rings host (re-forges on change)
B.SHAPE = {lit = "TravelBeaconCrystal", dormant = "TravelBeaconCrystalDormant", rings = "TravelBeaconRings"}
-- Beacon tints (world mint / brass / teal, the bastion teal, the Skyway region
-- accents, the vent colours): every crystal / ring tint snaps to one of these.
B.PALETTE = {}
for _, hex in ipairs({"8EE6CB", "DBAD65", "3C9291", "7FE3CC", "9BD18B", "A58CE0", "5EC8D8", "C6DCFF", "FF8A3D"}) do
	table.insert(B.PALETTE, Color3.fromHex(hex))
end
B.LEARNED_LIFT = 0.3 -- learned beacons: the palette tint lerped this far toward white
B.DORMANT = Color3.fromRGB(52, 58, 72) -- the dormant crystal (its shape has no tint slots)
B.DORMANT_RING = Color3.fromRGB(74, 82, 98) -- every locked armillary, whatever its region
B.SINK = -0.95 -- a locked crystal rests in its socket
B.SPIN = {learned = 1.25, open = 0.8, locked = 0}
B.MOTES = {learned = 7, open = 4, locked = 0}
B.WHOOSH = "rbxasset://sounds/swordlunge.wav"
B.CHIME = "rbxasset://sounds/electronicpingshort.wav"

-- Pure rules ---------------------------------------------------------------
-- Regions with no requirement (Hub, Meadow, Quarry, ...) are always open.
function B.freeRegions(defs)
	local free = {}
	for _, def in ipairs(if type(defs) == "table" then defs else {}) do
		if type(def) == "table" and type(def.id) == "string" and (def.requires == nil or (type(def.requires) == "table" and next(def.requires) == nil)) then
			free[def.id] = true
		end
	end
	return free
end
-- beacon = {kind, region, needs}; ctx = {open = set | nil (no full snapshot yet),
-- warps = set | nil, free = set | nil, crew = bool} -> "locked" | "open" | "learned".
-- Learned needs both: the region open and its warp known.
function B.state(beacon, ctx)
	if beacon.needs == "crew" then return if ctx.crew then "open" else "locked" end
	local region = beacon.region
	if type(region) ~= "string" then return "open" end
	if not (ctx.free ~= nil and ctx.free[region] == true) then
		if ctx.open == nil then return "open" end -- before the first full snapshot: never flash dark
		if ctx.open[region] ~= true then return "locked" end
	end
	return if ctx.warps ~= nil and ctx.warps[region] == true then "learned" else "open"
end
-- Folds a snapshot into the context. A full snapshot (snapshotFor: depth.regions
-- lists every region, top-level regions the Skyreach charter) rebuilds the open
-- set from both; a partial one (no depth) keeps what is known.
function B.context(snapshot, ctx)
	ctx = ctx or {}
	if type(snapshot) ~= "table" then return ctx end
	local depth = snapshot.depth
	if type(depth) == "table" and type(depth.regions) == "table" then
		local open = {}
		for _, list in ipairs({depth.regions, snapshot.regions}) do
			if type(list) == "table" then
				for _, r in ipairs(list) do
					if type(r) == "table" and type(r.id) == "string" and r.unlocked == true then open[r.id] = true end
				end
			end
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
-- Nearest palette tint (beacon tints arrive as the world's Color3 attributes).
function B.snap(color)
	if typeof(color) ~= "Color3" then return B.PALETTE[1] end
	local best, bestDistance = B.PALETTE[1], math.huge
	for _, c in ipairs(B.PALETTE) do
		local dr, dg, db = c.R - color.R, c.G - color.G, c.B - color.B
		local d = 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
		if d < bestDistance then best, bestDistance = c, d end
	end
	return best
end
function B.bright(color) return color:Lerp(Color3.new(1, 1, 1), B.LEARNED_LIFT) end
-- The look of a state: crystal shape, crystal tint, ring tint (tint = a palette colour).
function B.look(tint, state)
	if state == "locked" then return B.SHAPE.dormant, B.DORMANT, B.DORMANT_RING end
	local base = B.snap(tint)
	if state == "learned" then base = B.bright(base) end
	return B.SHAPE.lit, base, base
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

-- Headless tests read the rules; BeaconTest.runtime = true also builds the
-- runtime below (with mocked services) and hands its pieces back unstarted.
if BeaconTest then
	BeaconTest.beacons = B
	if BeaconTest.runtime ~= true then return end
end

-- Runtime ------------------------------------------------------------------
local Tags = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local Theme
task.spawn(function()
	pcall(function()
		local module = ReplicatedStorage:WaitForChild("AetherUiTheme", 15)
		if module then Theme = require(module) end
	end)
end)
local reduced = false -- sampled every MOTION_SECONDS (assign)
local function sampleMotion()
	local ok, value = pcall(function()
		return Theme ~= nil and type(Theme.reducedMotion) == "function" and Theme.reducedMotion(player) == true
	end)
	reduced = ok and value == true
	return reduced
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
local writes = {count = 0} -- Shape / Tint / ShapeScale writes (each one re-forges a host)

-- Attribute write that skips unchanged values (an unchanged write still re-forges).
local function put(part, key, value)
	if part:GetAttribute(key) == value then return end
	part:SetAttribute(key, value)
	writes.count += 1
	table.insert(writes, {part = part, key = key, value = value, at = part.CFrame.Position})
	if #writes > 64 then table.remove(writes, 1) end
end
local function hostPart(name, shape, size)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = name, true, false, false, false, false
	-- Invisible host: only the forged mesh shows (never a glass block).
	p.Size, p.CFrame, p.Material, p.Transparency = size, PARK, Enum.Material.Glass, 1
	p:SetAttribute("Shape", shape)
	p.Parent = folder
	return p
end
local function newSet()
	local set = {}
	set.crystal = hostPart("Beacon crystal", B.SHAPE.lit, B.CRYSTAL)
	set.rings = hostPart("Beacon rings", B.SHAPE.rings, B.RINGS)
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
local function focus()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then return root.Position end
	local ok, camera = pcall(function() return workspace.CurrentCamera end)
	return if ok and camera then camera.CFrame.Position else nil
end
local function playFlare(record)
	local part = record.part
	local by = part:GetAttribute("TravelBeaconFlareBy")
	if by == player.UserId then pcall(function() chime:Play() end) end
	local origin = focus()
	if not origin then return end
	local distance = (record.hover - origin).Magnitude
	if distance > B.FLARE_RADIUS then return end
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
	pcall(function() burst:Emit(if reduced then 10 else 28) end)
	-- The whoosh outlives the 0.7 s shell: it lives in the folder, fades with
	-- distance, and is removed when it ends (Debris as the backstop).
	local whoosh = Instance.new("Sound")
	whoosh.Name, whoosh.SoundId, whoosh.PlaybackSpeed = "Beacon whoosh", B.WHOOSH, 0.55
	whoosh.Volume = 0.45 * math.clamp(1 - distance / B.FLARE_RADIUS, 0.15, 1)
	whoosh.Parent = folder
	pcall(function() whoosh.Ended:Connect(function() whoosh:Destroy() end) end)
	pcall(function() Debris:AddItem(whoosh, 4) end)
	pcall(function() whoosh:Play() end)
	table.insert(flares, {shell = shell, start = os.clock(), reduced = reduced})
	while #flares > B.FLARE_CAP do local oldest = table.remove(flares, 1); oldest.shell:Destroy() end
end

-- Registry (CollectionService tag TravelBeacon) ---------------------------------
local function register(part)
	if beacons[part] or not part:IsA("BasePart") or type(part:GetAttribute("TravelBeacon")) ~= "string" then return end
	local hover = part:GetAttribute("TravelBeaconHover")
	local record = {
		part = part, kind = part:GetAttribute("TravelBeacon"), region = part:GetAttribute("TravelBeaconRegion"),
		needs = part:GetAttribute("TravelBeaconNeeds"), hover = if typeof(hover) == "Vector3" then hover else part.Position + Vector3.new(0, 1, 0),
		tint = B.snap(part:GetAttribute("Tint")), seed = (#list % 7) * 0.9,
	}
	beacons[part] = record
	table.insert(list, record)
	applyState(record)
	pcall(function()
		record.flareConnection = part:GetAttributeChangedSignal("TravelBeaconFlare"):Connect(function() playFlare(record) end)
	end)
	return record
end
local function drop(record)
	if beacons[record.part] == record then beacons[record.part] = nil end
	if record.flareConnection then record.flareConnection:Disconnect(); record.flareConnection = nil end
	if record.set then record.set.beacon = nil; record.set.dirty = true; record.set = nil end
	local i = table.find(list, record)
	if i then table.remove(list, i) end
end
local function unregister(part)
	local record = beacons[part]
	if record then drop(record) end
end

local function observe(snapshot)
	if type(snapshot) ~= "table" or (snapshot.depth == nil and snapshot.regionQuests == nil) then return end
	B.context(snapshot, ctx)
	for _, record in ipairs(list) do record.state = nil end
	refreshStates()
end
local function setFree(defs)
	ctx.free = B.freeRegions(defs)
	for _, record in ipairs(list) do record.state = nil end
	refreshStates()
end

-- Pool assignment (twice a second) ----------------------------------------------
local function place(set, record, lift, yaw, ringYaw)
	if record.kind == "vent" then
		set.rings.CFrame = CFrame.new(record.hover + Vector3.new(0, lift * 0.5, 0)) * CFrame.Angles(0, ringYaw, 0)
	else
		set.crystal.CFrame = CFrame.new(record.hover + Vector3.new(0, lift, 0)) * CFrame.Angles(0, yaw, 0)
		set.rings.CFrame = CFrame.new(record.hover) * CFrame.Angles(0, ringYaw, 0)
	end
end
local function dress(set)
	local record = set.beacon
	set.dirty = false
	set.posed = nil
	if not record then
		set.crystal.CFrame, set.rings.CFrame, set.motes.Enabled = PARK, PARK, false
		return
	end
	local vent = record.kind == "vent"
	local state = record.state or "open"
	-- Pose first: a Shape / Tint write re-forges the host where it stands.
	place(set, record, B.pose(os.clock(), state, reduced, record.seed))
	set.posed = true
	local shape, crystalTint, ringTint = B.look(record.tint, state)
	if vent then
		set.crystal.CFrame = PARK
	else
		local size = if shape == B.SHAPE.dormant then B.CRYSTAL_DORMANT else B.CRYSTAL
		if set.crystal.Size ~= size then set.crystal.Size = size end -- before the Shape write that re-forges it
		put(set.crystal, "Shape", shape)
		put(set.crystal, "Tint", crystalTint)
	end
	put(set.rings, "ShapeScale", if vent then B.VENT_SCALE else nil)
	put(set.rings, "Tint", ringTint)
	set.motes.Color = ColorSequence.new(crystalTint:Lerp(Color3.new(1, 1, 1), 0.45), crystalTint)
	set.motes.Rate = (B.MOTES[state] or 0) * (if mobile then 0.5 else 1)
	set.motes.Enabled = not vent and state ~= "locked"
end
local function assign()
	sampleMotion()
	for i = #list, 1, -1 do
		local record = list[i]
		if not record.part.Parent or not record.part:IsDescendantOf(workspace) then drop(record) end
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
local function frame(t)
	if reduced ~= stillReduced then
		stillReduced = reduced
		for _, set in ipairs(sets) do set.posed = nil end
	end
	for _, set in ipairs(sets) do
		local record = set.beacon
		if record and (not set.posed or (not reduced and record.state ~= "locked")) then
			place(set, record, B.pose(t, record.state or "open", reduced, record.seed))
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
end

if BeaconTest then
	BeaconTest.R = {register = register, drop = drop, unregister = unregister, assign = assign, dress = dress, frame = frame,
		playFlare = playFlare, observe = observe, setFree = setFree, sampleMotion = sampleMotion,
		sets = sets, list = list, flares = flares, folder = folder, ctx = ctx, writes = writes, PARK = PARK}
	return
end

Tags:GetInstanceAddedSignal("TravelBeacon"):Connect(function(instance) task.defer(register, instance) end)
Tags:GetInstanceRemovedSignal("TravelBeacon"):Connect(unregister)
for _, instance in ipairs(Tags:GetTagged("TravelBeacon")) do register(instance) end

player:GetAttributeChangedSignal("CoopId"):Connect(function()
	for _, record in ipairs(list) do if record.needs then record.state = nil end end
	refreshStates()
end)
task.spawn(function()
	local data = ReplicatedStorage:WaitForChild("AetherData", 30)
	if data then
		local ok, Data = pcall(require, data)
		if ok and type(Data) == "table" then setFree(Data.Regions) end
	end
end)
task.spawn(function()
	local updates = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if updates then updates.OnClientEvent:Connect(observe) end
	local channel = ReplicatedStorage:WaitForChild("IsleSnapshotLocal", 30)
	if channel and channel:IsA("BindableEvent") then channel.Event:Connect(observe) end
end)
RunService.Heartbeat:Connect(function() frame(os.clock()) end)
task.spawn(function()
	while true do
		assign()
		task.wait(B.MOTION_SECONDS)
	end
end)
