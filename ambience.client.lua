-- Ambience layer (StarterPlayerScripts.IsleAmbience; docs/DEPTH-CONTRACT.md §50).
-- Makes the world feel alive around the player, on top of the §35 lighting
-- director and its region profiles. Everything here is local and cosmetic:
-- it creates only client-side parts / emitters (under workspace
-- "IsleAmbienceLocal", or as local children of world parts) and never touches
-- Lighting (the director is the one writer), GUI or gameplay.
--   * Wind and sway: a server-time wind field (shared/Ambience.lua: a slowly
--     veering direction and gust fronts that roll across the isles, so every
--     player sees the same gust) leans forged tree canopies, bushes, flowers
--     and crop rows about their base and flutters banners and hanging
--     lanterns about their top. Only the forge's local MeshPart clones move
--     (found through their host's ShapeMesh link; never a server part, a
--     spinning / unanchored host or a hidden prop). Vertex-free: the clone's CFrame
--     rotates about a pivot (workspace:BulkMoveTo with reused arrays); the
--     nearest A.budget().sway props within swayRadius, restored when culled.
--   * Water: foam surf around island rims and pond / fishing-pool edges
--     (pooled, bobbing), a highlight sheet + lip spray on the World Art
--     waterfalls (and their mist culled by distance), shimmer over fishing
--     spots, and a parallax cloud sea of 1-3 scrolling layers below the isles.
--   * Particles: island / region motes (the island's Ambience attribute, else
--     the region's: pollen, dust, falling leaves, frost, spores, sea spray,
--     void sparks; the only camera ambience emitter since QC M4), fireflies after dusk, embers over forges,
--     hearths and lit Beaconry pyres, spores over glowshrooms, void sparks on
--     crystals (a small pool of source emitters on the nearest sources), and
--     cheap boid flocks around landmarks (birds by day; butterflies on meadow
--     and home isles; they roost at night).
--   * Weather: the server's IsleWeather attribute (weather.server.lua; one
--     string, a deterministic schedule) names each region's state. Rain and
--     storm rain (with ground splashes, never under a roof), snow on cold
--     isles, fog banks, breezy leaves; no rain inside a building's declared
--     box (never a world raycast). Storm strikes come from the shared
--     schedule on server time (A.strikeDue): a visible bolt (unless reduced
--     motion or "Flashing effects" is off) and the "thunder" cue, on the
--     same frame as the director's flash. The wet sheen and the flash are the
--     director's (L.applyWeather / L.flashAt).
--   * Skill VFX: hit sparks / chips per node material on every strike impact
--     (animate.client.lua's IsleImpactLocal), a level-up burst + ring + sound
--     cue, a Hypixel-style rarity pillar on Rare+ pickups (Data.Rarity colours),
--     and XP orbs that trail from the node to the player.
-- Budgets: A.budget(graphics tier, phone) caps emitters, parts, swayers,
-- radii and pools (High / Balanced / Lite (phones) / Performance). Reduced
-- motion (Settings or the device) stops all sway, foam bob, bolts and ring
-- pulses. Per-frame code sits between FRAME-BEGIN / FRAME-END markers and
-- allocates nothing but CFrame / Vector3 values (verify-ambience greps it).
-- Cue hook: ReplicatedStorage.IsleAmbienceCue (BindableEvent) fires
-- ("levelup", skill, level), ("thunder", region, delay), ("raredrop", rarity).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local A = require(ReplicatedStorage:WaitForChild("AetherAmbience"))
local L = require(ReplicatedStorage:WaitForChild("AetherLighting"))
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local player = Players.LocalPlayer

local Amb = {b = nil, budgetKey = nil, tier = nil, mobile = false, reduced = false, key = L.DEFAULT_KEY, region = A.Regions[L.DEFAULT_KEY],
	interior = false, weather = "Clear", weatherText = nil, parsed = nil, strikeSeen = nil, clock = 12, night = false,
	focus = Vector3.new(0, 0, 0), tw = 0, partsMade = 0, emitting = {}, emittingCount = 0, folder = nil, sheltered = false,
	groundY = 0, cues = {}, driftX = 0, driftZ = 0, flashing = true, motes = nil}

------------------------------------------------------------------------------
-- Engine helpers (pcall'd where the headless harness has no engine method).
------------------------------------------------------------------------------
local function connect(inst, signalName, fn)
	local ok, signal = pcall(function() return inst[signalName] end)
	if not ok or signal == nil then return nil end
	local ok2, connection = pcall(function() return signal:Connect(fn) end)
	return if ok2 then connection else nil
end
local function serverTimeRaw() return workspace:GetServerTimeNow() end
local function now()
	local ok, t = pcall(serverTimeRaw)
	if ok and type(t) == "number" and t > 1e9 then return t end
	return os.time()
end
local function setProp(inst, key, value) inst[key] = value end
local function trySet(inst, key, value) pcall(setProp, inst, key, value) end
local function emitRaw(em, n) em:Emit(n) end
local function emit(em, n) if n > 0 then pcall(emitRaw, em, n) end end
local function playRaw(sound) sound:Play() end
local function bulkRaw(parts, cframes) workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
local hasBulk = pcall(function() return workspace.BulkMoveTo end)
-- Move parts[1..n] to cframes[1..n] (arrays are reused; trailing slots cleared).
local function moveAll(parts, cframes, n, last)
	for i = n + 1, last do parts[i] = nil; cframes[i] = nil end
	if n == 0 then return end
	if hasBulk and pcall(bulkRaw, parts, cframes) then return end
	for i = 1, n do parts[i].CFrame = cframes[i] end
end
local function bindable(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local cue = bindable("IsleAmbienceCue")
function Amb.cue(kind, a, b)
	table.insert(Amb.cues, kind) -- read by the headless suite (bounded below)
	if #Amb.cues > 32 then table.remove(Amb.cues, 1) end
	pcall(function() cue:Fire(kind, a, b) end)
end
local function hex(h)
	if typeof(h) == "Color3" then return h end
	local ok, c = pcall(Color3.fromHex, tostring(h or "FFFFFF"))
	return if ok then c else Color3.new(1, 1, 1)
end
local function reducedMotion()
	if player:GetAttribute("IsleSettingReducedMotion") == true then return true end
	local ok, on = pcall(function() return game:GetService("GuiService").ReducedMotionEnabled end)
	return ok and on == true
end
local function isMobile()
	local mobile = false
	pcall(function()
		local input = game:GetService("UserInputService")
		mobile = input.TouchEnabled == true and input.KeyboardEnabled ~= true
	end)
	return mobile
end
local PARK = CFrame.new(0, 4000, 0) -- idle pooled parts wait far above the world, invisible

------------------------------------------------------------------------------
-- Owned instances (rebuilt from scratch when the tier changes).
------------------------------------------------------------------------------
local Pools -- forward
local function folder()
	if Amb.folder and Amb.folder.Parent then return Amb.folder end
	local f = Instance.new("Folder")
	f.Name = "IsleAmbienceLocal"
	f.Parent = workspace
	Amb.folder = f
	return f
end
-- A local, non-colliding, non-queryable, shadowless part (nil past the budget).
local function newPart(name, size, color, material, transparency, shape)
	if not Amb.b or Amb.partsMade >= Amb.b.parts then return nil end
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material, p.Transparency = size, color, material, transparency
	p.CFrame = PARK
	p.Parent = folder()
	Amb.partsMade += 1
	return p
end
local SEQ = {} -- per preset: built once
local function seqFor(name)
	local s = SEQ[name]
	if s then return s end
	local p = A.Presets[name]
	local tr = p.transparency or 0.1
	s = {color = ColorSequence.new(hex(p.colors[1]), hex(p.colors[2])),
		size = NumberSequence.new(p.size, p.size * 0.55),
		trans = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, tr), NumberSequenceKeypoint.new(0.75, tr), NumberSequenceKeypoint.new(1, 1)}),
		life = NumberRange.new(p.life[1], p.life[2]), speed = NumberRange.new(p.speed[1], p.speed[2]),
		rot = NumberRange.new(-(p.spin or 20), p.spin or 20)}
	SEQ[name] = s
	return s
end
local function configure(em, name)
	if em:GetAttribute("Preset") == name then return end
	local p, s = A.Presets[name], seqFor(name)
	em:SetAttribute("Preset", name)
	em.Texture = if p.texture == "smoke" then A.SMOKE else A.SPARKLE
	em.Color, em.Size, em.Transparency, em.Lifetime, em.Speed = s.color, s.size, s.trans, s.life, s.speed
	em.LightEmission, em.LightInfluence = p.light, 1 - p.light
	trySet(em, "RotSpeed", s.rot)
	trySet(em, "Rotation", NumberRange.new(0, 360))
	trySet(em, "Drag", if p.streak then 0 else 0.4)
	trySet(em, "Orientation", if p.streak then Enum.ParticleOrientation.VelocityParallel else Enum.ParticleOrientation.FacingCamera)
	if p.streak then trySet(em, "Squash", NumberSequence.new(-2.5)) end
	em.SpreadAngle = if p.streak then Vector2.new(4, 4) else Vector2.new(180, 180)
end
local function newEmitter(parent, name, preset)
	local em = Instance.new("ParticleEmitter")
	em.Name = name
	em.Enabled, em.Rate = false, 0
	trySet(em, "ShapeStyle", Enum.ParticleEmitterShapeStyle.Volume)
	configure(em, preset)
	em.Parent = parent
	return em
end
-- Continuous emitters count against the tier's emitter cap.
local function setEmitting(em, on, rate)
	if not em then return false end
	if on and (rate or 1) > 0 then
		if not Amb.emitting[em] then
			if Amb.emittingCount >= Amb.b.emitters then return false end
			Amb.emitting[em] = true
			Amb.emittingCount += 1
		end
		if rate and em.Rate ~= rate then em.Rate = rate end
		if not em.Enabled then em.Enabled = true end
		return true
	end
	if Amb.emitting[em] then Amb.emitting[em] = nil; Amb.emittingCount -= 1 end
	if em.Enabled then em.Enabled = false end
	return false
end

------------------------------------------------------------------------------
-- World registry: what the layer decorates (filled by classify()).
-- One weak-keyed "seen" set per role (QC L7): a part can be a node and a
-- landmark, an instance that leaves the world is forgotten, and the
-- time-sliced rescan (below) picks up attributes the server sets late.
------------------------------------------------------------------------------
local function weakSet() return setmetatable({}, {__mode = "k"}) end
local World = {islands = {}, ponds = {}, falls = {}, sources = {}, landmarks = {}, nodes = {}, buildings = {},
	seen = {sway = weakSet(), source = weakSet(), node = weakSet(), pond = weakSet(), landmark = weakSet(), fall = weakSet(),
		island = weakSet(), building = weakSet()}}
Amb.world = World
local Sway = {list = {}, active = {}, prev = {}, parts = {}, cframes = {}, last = 0, epoch = 0, count = 0}
Amb.sway = Sway
local EMBER_SHAPES = {Forge = true, Hearth = true, Caldera = true, Torch = true}
local SPORE_SHAPES = {Glowshroom = true}
local VOID_SHAPES = {AetherCrystal = true, CrystalSpire = true, StormPylon = true}
local function phaseOf(pos) return (pos.X * 0.37 + pos.Z * 0.71) % (2 * math.pi) end
local function hasTagRaw(inst, tag) return inst:HasTag(tag) end
-- Does something else move this host (QC M3)? Spinning sails, unanchored hosts.
local function hostMoves(host)
	if not host or not host:IsA("BasePart") then return false end
	if host.Anchored == false or host:GetAttribute("SpinRate") ~= nil then return true end
	local ok, tagged = pcall(hasTagRaw, host, A.NO_SWAY_TAG)
	return ok and tagged == true
end
-- QC M1: only the forge's local MeshPart clones sway; they are found through
-- the host's ShapeMesh link (so the host can be checked) and never a server part.
local function addSway(link)
	local clone, host = link.Value, link.Parent
	if not clone or World.seen.sway[clone] or not clone:IsA("MeshPart") then return end
	-- §54: island dressing links live in IsleDressing.Sway (no host part).
	if host and not host:IsA("BasePart") then host = nil end
	local def = A.SWAY[clone:GetAttribute("ShapeOf") or ""]
	if not def or hostMoves(host) then return end
	World.seen.sway[clone] = true
	local pos = clone.CFrame.Position
	table.insert(Sway.list, {part = clone, host = host, def = def, base = nil, off = nil, pivot = nil, phase = phaseOf(pos), d2 = 0, epoch = 0, pos = pos})
end
local function addSource(part, kind)
	if World.seen.source[part] then return end
	World.seen.source[part] = true
	table.insert(World.sources, {part = part, kind = kind, d2 = 0})
end
local function once(role, inst, list, entry)
	if World.seen[role][inst] then return end
	World.seen[role][inst] = true
	table.insert(list, entry)
end
local function classify(inst)
	if inst:IsA("ObjectValue") then
		if inst.Name == "ShapeMesh" then addSway(inst) end
	elseif inst:IsA("BasePart") then
		local shape = inst:GetAttribute("Shape")
		if inst:GetAttribute("BeaconFlame") then addSource(inst, "embers")
		elseif shape and EMBER_SHAPES[shape] then addSource(inst, "embers")
		elseif shape and SPORE_SHAPES[shape] then addSource(inst, "spores")
		elseif shape and VOID_SHAPES[shape] then addSource(inst, "void") end
		if inst:GetAttribute("GatherNode") then once("node", inst, World.nodes, inst) end
		if inst:GetAttribute("BuildingType") then once("building", inst, World.buildings, {part = inst}) end
		if inst.Name == "Pond water" or inst.Name == "Fishing water" then
			once("pond", inst, World.ponds, {part = inst, d2 = 0})
			if inst.Name == "Fishing water" then addSource(inst.Parent and inst.Parent:FindFirstChild("Ripple") or inst, "shimmer") end
		elseif inst.Name == "Ripple" and inst.Parent and string.find(inst.Parent.Name, "fishing spot", 1, true) then
			addSource(inst, "shimmer")
		end
		if inst:GetAttribute("Landmark") then once("landmark", inst, World.landmarks, {part = inst, d2 = 0}) end
	elseif inst:IsA("Beam") and inst.Name == "Waterfall" then
		once("fall", inst, World.falls, {beam = inst, d2 = 0})
	elseif inst:IsA("Model") then
		if inst:GetAttribute("IslandCenter") and inst:GetAttribute("IslandRadius") then
			once("island", inst, World.islands, {model = inst, center = inst:GetAttribute("IslandCenter"), radius = inst:GetAttribute("IslandRadius"), d2 = 0})
		end
		if inst:GetAttribute("Landmark") and not World.seen.landmark[inst] then
			local host = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
			if host then World.seen.landmark[inst] = true; table.insert(World.landmarks, {part = host, d2 = 0}) end
		end
	end
end
Amb.classify = classify
-- Roots are scanned once and then watched (DescendantAdded). QC L7: a slow
-- rescan walks the roots in slices of RESCAN_SLICE instances per selection
-- tick, so an attribute the server sets after the part arrived (GatherNode,
-- Landmark, BuildingType, BeaconFlame) is picked up within a cycle.
local ROOTS = {"Islands", "AetherIsles", "IsleDressing"} -- §54: the local island dressing (terrain.client.lua)
local roots = {}
local Rescan = {items = nil, i = 1, SLICE = 400}
Amb.rescan = Rescan
local function scanRoots()
	for _, name in ipairs(ROOTS) do
		local root = workspace:FindFirstChild(name)
		if root and not roots[root] then
			roots[root] = true
			classify(root)
			for _, inst in ipairs(root:GetDescendants()) do classify(inst) end
			connect(root, "DescendantAdded", classify)
		end
	end
end
function Rescan.step()
	if not Rescan.items or Rescan.i > Rescan.n then
		-- A new cycle: one snapshot of every root's descendants.
		local items = {}
		for root in pairs(roots) do
			if root.Parent then for _, inst in ipairs(root:GetDescendants()) do items[#items + 1] = inst end end
		end
		Rescan.items, Rescan.i, Rescan.n = items, 1, #items
		Rescan.cycles = (Rescan.cycles or 0) + 1
	end
	local items, stop = Rescan.items, math.min(Rescan.n, Rescan.i + Rescan.SLICE - 1)
	for i = Rescan.i, stop do
		local inst = items[i]
		items[i] = nil -- drop the reference as we go
		if inst.Parent then classify(inst) end
	end
	Rescan.i = stop + 1
end
-- Drop entries whose instance left the world (in place; no new tables).
local function alive(inst) return inst ~= nil and inst.Parent ~= nil and inst:IsDescendantOf(workspace) end
local function compact(list, field)
	local kept = 0
	for i = 1, #list do
		local e = list[i]
		local inst = if field then e[field] else e
		if alive(inst) then
			kept += 1
			list[kept] = e
		end
	end
	for i = kept + 1, #list do list[i] = nil end
	return kept
end

------------------------------------------------------------------------------
-- Pools (lazily filled up to the tier's budget; dropped on a tier change).
------------------------------------------------------------------------------
Pools = {anchors = {}, emitters = {}, clouds = {}, foam = {}, foamCount = 0, birds = {}, orbs = {}, beams = {}, bolts = {},
	sources = {}, falls = {}, ring = nil, burst = nil, sound = nil}
Amb.pools = Pools
local function anchor(name, size)
	local a = Pools.anchors[name]
	if a and a.Parent then return a end
	a = newPart("Ambience " .. name, size, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
	Pools.anchors[name] = a
	return a
end
local function fixedEmitter(name, anchorName, size, preset)
	local em = Pools.emitters[name]
	if em and em.Parent then return em end
	local host = anchor(anchorName, size)
	if not host then return nil end
	em = newEmitter(host, name, preset)
	Pools.emitters[name] = em
	return em
end
local function dropPools()
	for em in pairs(Amb.emitting) do pcall(function() em.Enabled = false end) end
	table.clear(Amb.emitting)
	Amb.emittingCount = 0
	for _, s in ipairs(Pools.sources) do pcall(s.attachment.Destroy, s.attachment) end
	for _, f in pairs(Pools.falls) do
		pcall(f.sheet.Destroy, f.sheet)
		pcall(f.spray.Destroy, f.spray)
	end
	for _, w in ipairs(World.falls) do
		local mist = w.beam.Parent and w.beam.Parent:FindFirstChild("Waterfall foot")
		local em = mist and mist:FindFirstChild("Waterfall mist")
		if em then pcall(setProp, em, "Enabled", true) end
	end
	if Amb.folder then pcall(Amb.folder.Destroy, Amb.folder) end
	Amb.folder = nil
	Amb.partsMade = 0
	for k, v in pairs(Pools) do
		if type(v) == "table" and k ~= "burst" then table.clear(v) else Pools[k] = nil end
	end
	-- Everything that pointed at a pooled part starts over.
	local fx, foam, flock, sway = Amb.fx, Amb.foam, Amb.flock, Amb.sway
	if fx then
		table.clear(fx.orbs); table.clear(fx.beams)
		fx.ring.part, fx.ring.on = nil, false
		fx.bolt.parts, fx.bolt.on = nil, false
	end
	if foam then table.clear(foam.list); foam.count = 0 end
	if flock then table.clear(flock.birds); flock.count = 0 end
	for _, arrays in ipairs({foam, flock, sway}) do
		if arrays then table.clear(arrays.parts); table.clear(arrays.cframes); arrays.last = 0 end
	end
end

------------------------------------------------------------------------------
-- Context: tier, reduced motion, region, weather, clock (4 Hz).
------------------------------------------------------------------------------
local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end
local function focusNow()
	local root = rootPart()
	if root then return root.CFrame.Position end
	local ok, pos = pcall(function() return workspace.CurrentCamera.Focus.Position end)
	return if ok and pos then pos else Amb.focus
end
local Sky -- forward (cloud sea)
local function restoreAllSway()
	for i = 1, #Sway.active do
		local e = Sway.active[i]
		if e.base and e.part.Parent and e.written then e.part.CFrame = e.base end
		e.epoch, e.written = 0, nil
	end
	table.clear(Sway.active)
	Sway.count = 0
end
function Amb.readTier()
	local tier = L.readTier(player:GetAttribute(L.SETTING_ATTR), {})
	local mobile = isMobile()
	local key = A.budgetKey(tier, mobile)
	if key ~= Amb.budgetKey then
		restoreAllSway()
		if Amb.budgetKey ~= nil then dropPools() end
		Amb.budgetKey, Amb.b, Amb.tier, Amb.mobile = key, A.Budgets[key], tier, mobile
		return true
	end
	return false
end
-- The weather attribute is read when it changes (QC H2:
-- GetAttributeChangedSignal; the 4 Hz context only polls where the signal is
-- missing, e.g. the headless harness).
function Amb.readWeatherText()
	local text = workspace:GetAttribute(L.WEATHER_ATTR)
	if text ~= Amb.weatherText then
		Amb.weatherText = text
		Amb.parsed = L.parseWeather(text)
	end
end
Amb.weatherWatched = pcall(function()
	workspace:GetAttributeChangedSignal(L.WEATHER_ATTR):Connect(Amb.readWeatherText)
end)
function Amb.readWeather()
	if not Amb.weatherWatched then Amb.readWeatherText() end
	Amb.weather = L.weatherFor(Amb.parsed, Amb.key)
end
-- The island under the player (its Ambience attribute picks the motes, QC M4).
local function islandUnder(pos)
	local best, bestD
	for _, isle in ipairs(World.islands) do
		local c, r = isle.center, isle.radius
		local dx, dz = pos.X - c.X, pos.Z - c.Z
		local d = dx * dx + dz * dz
		if d <= (r + 2) * (r + 2) and pos.Y > c.Y - 8 and pos.Y < c.Y + 60 and (not bestD or d < bestD) then best, bestD = isle, d end
	end
	return best
end
function Amb.context()
	Amb.readTier()
	local wasReduced = Amb.reduced
	Amb.reduced = reducedMotion()
	if Amb.reduced and not wasReduced then restoreAllSway() end
	Amb.flashing = L.flashingAllowed(player:GetAttribute(L.FLASHING_ATTR), Amb.reduced)
	Amb.focus = focusNow()
	local key = L.context({
		LairBoss = player:GetAttribute("LairBoss"), RaidRun = player:GetAttribute("RaidRun"), DungeonInRun = player:GetAttribute("DungeonInRun"),
		MinigameGame = player:GetAttribute("MinigameGame"), IsleRegionHere = player:GetAttribute("IsleRegionHere"),
	}, Amb.focus)
	-- QC L4: the director's hold: a new outdoor context must persist
	-- L.CONTEXT_HOLD seconds; arenas switch at once.
	local t = os.clock()
	if key == Amb.key then
		Amb.pendingKey = nil
	elseif (L.Profiles[key] and L.Profiles[key].interior) or (L.Profiles[Amb.key] and L.Profiles[Amb.key].interior) or Amb.keySet ~= true then
		Amb.key, Amb.pendingKey, Amb.keySet = key, nil, true
	elseif Amb.pendingKey ~= key then
		Amb.pendingKey, Amb.pendingSince = key, t
	elseif t - Amb.pendingSince >= L.CONTEXT_HOLD then
		Amb.key, Amb.pendingKey = key, nil
	end
	Amb.interior = L.Profiles[Amb.key] ~= nil and L.Profiles[Amb.key].interior == true
	Amb.region = A.Regions[Amb.key] or A.Regions[L.DEFAULT_KEY]
	local isle = islandUnder(Amb.focus)
	local kind = isle and isle.model:GetAttribute("Ambience")
	Amb.motes = (type(kind) == "string" and A.ISLAND_MOTES[kind]) or Amb.region.motes
	Amb.clock = L.clockAt(now(), Data.Calendar)
	Amb.night = L.dayFactor(Amb.clock) < 0.5
	Amb.readWeather()
end

------------------------------------------------------------------------------
-- Weather and region particles (camera-anchored emitters; 4 Hz).
------------------------------------------------------------------------------
local rayParams
pcall(function()
	rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
end)
local function cast(origin, dir)
	if not rayParams then return nil end
	local ok, hit = pcall(function()
		local exclude = {Amb.folder}
		if player.Character then table.insert(exclude, player.Character) end
		rayParams.FilterDescendantsInstances = exclude
		return workspace:Raycast(origin, dir, rayParams)
	end)
	return if ok then hit else nil
end
-- Shelter (QC H1): inside a building's declared box (the §40 hosts: walk-in
-- halls are their floor plank plus ShapeBox / ShapeBoxOffset), never a world
-- raycast (tree canopies, awnings and invisible slot boxes used to stop the
-- rain, and mesh-only hall roofs did not). The ground height for splashes
-- still comes from a short downward ray (2 Hz).
local function sheltered(pos)
	for _, e in ipairs(World.buildings) do
		local host = e.part
		if host.Parent then
			local size = host:GetAttribute("ShapeBox")
			if typeof(size) ~= "Vector3" then size = host.Size end
			local offset = host:GetAttribute("ShapeBoxOffset")
			local cf = if typeof(offset) == "Vector3" then host.CFrame * CFrame.new(offset) else host.CFrame
			local reach = size.Magnitude / 2 + A.SHELTER_FEET
			if (cf.Position - pos).Magnitude <= reach then
				local l = cf:PointToObjectSpace(pos)
				if A.insideBox(l.X, l.Y, l.Z, size.X, size.Y, size.Z) then return true end
			end
		end
	end
	return false
end
Amb.shelteredAt = sheltered
function Amb.probe()
	compact(World.buildings, "part")
	Amb.sheltered = sheltered(Amb.focus)
	local down = cast(Amb.focus + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0))
	Amb.groundY = if down then down.Position.Y else Amb.focus.Y - 3
end
function Amb.particles()
	local b, f = Amb.b, Amb.focus
	local outdoors = not Amb.interior
	local dx, dz = A.windDir(Amb.tw)
	local wind = A.windAt(Amb.tw, f.X, f.Z, Amb.region.wind, Amb.weather)
	local drift = Vector3.new(dx * wind, 0, dz * wind)
	-- Island / region motes (or nothing indoors). QC M4: this is the only
	-- camera ambience emitter (regions.client.lua's was retired); the island's
	-- Ambience attribute picks the preset, else the region's.
	local kind = Amb.motes or Amb.region.motes
	local motes = fixedEmitter("motes", "air", Vector3.new(90, 36, 90), kind)
	if motes then
		configure(motes, kind)
		motes.Acceleration = drift * A.Presets[kind].drift + Vector3.new(0, A.Presets[kind].rise or 0, 0)
		setEmitting(motes, outdoors, A.rateFor(kind, b))
	end
	-- Fireflies at night where the region has them; falling leaves by day when breezy.
	local glow = fixedEmitter("fireflies", "air", Vector3.new(90, 36, 90), "fireflies")
	local fireflies = outdoors and Amb.night and Amb.region.fireflies == true and Amb.weather ~= "Rain" and Amb.weather ~= "Storm"
	if glow then setEmitting(glow, fireflies, A.rateFor("fireflies", b)) end
	local leaves = fixedEmitter("leaves", "air", Vector3.new(90, 36, 90), "leaves")
	if leaves then
		leaves.Acceleration = drift * 1.2 + Vector3.new(0, -1.5, 0)
		local breezy = outdoors and not fireflies and (Amb.weather == "Breezy" or Amb.weather == "Storm") and kind ~= "leaves"
		setEmitting(leaves, breezy, A.rateFor("leaves", b) * (if Amb.weather == "Storm" then 2 else 1))
	end
	-- Rain / snow, splashes (not under a roof), fog banks.
	local wet = outdoors and (Amb.weather == "Rain" or Amb.weather == "Storm" or Amb.weather == "Snow")
	local snow = Amb.weather == "Snow" or (wet and Amb.region.cold == true)
	local rain = fixedEmitter("rain", "sky", Vector3.new(80, 1, 80), if snow then "snow" else "rain")
	if rain then
		configure(rain, if snow then "snow" else "rain")
		trySet(rain, "EmissionDirection", Enum.NormalId.Bottom)
		rain.Acceleration = drift * (if snow then 2 else 6)
		local rate = b.rain * b.rateScale * (if Amb.weather == "Storm" then 1.6 elseif snow then 0.5 else 1)
		setEmitting(rain, wet and not Amb.sheltered, math.floor(rate + 0.5))
	end
	if b.splashes > 0 then
		local splash = fixedEmitter("splash", "ground", Vector3.new(50, 0.2, 50), "splash")
		if splash then
			trySet(splash, "EmissionDirection", Enum.NormalId.Top)
			setEmitting(splash, wet and not snow and not Amb.sheltered, A.rateFor("splash", b) * (if Amb.weather == "Storm" then 1.5 else 1))
		end
	end
	if b.fog > 0 then
		local fog = fixedEmitter("fog", "fog", Vector3.new(160, 24, 160), "fog")
		if fog then
			fog.Acceleration = drift * 0.5
			local foggy = outdoors and (Amb.weather == "Fog" or Amb.weather == "Storm")
			setEmitting(fog, foggy, b.fog * (if Amb.weather == "Fog" then 1 else 0.5))
		end
	end
	Amb.driftX, Amb.driftZ = drift.X, drift.Z
end
-- FRAME-BEGIN anchors
-- QC L10: the emitter anchors follow the player every frame (4 CFrame writes),
-- so a sprinting or gliding player never outruns the rain box.
function Amb.anchorsFrame()
	local root = rootPart()
	local f = if root then root.CFrame.Position else Amb.focus
	local anchors = Pools.anchors
	local air, sky, ground, fogA = anchors.air, anchors.sky, anchors.ground, anchors.fog
	if air then air.CFrame = CFrame.new(f.X, f.Y + 8, f.Z) end
	if sky then sky.CFrame = CFrame.new(f.X - Amb.driftX * 3, f.Y + 40, f.Z - Amb.driftZ * 3) end
	if ground then ground.CFrame = CFrame.new(f.X, Amb.groundY + 0.15, f.Z) end
	if fogA then fogA.CFrame = CFrame.new(f.X, f.Y + 4, f.Z) end
end
-- FRAME-END anchors

------------------------------------------------------------------------------
-- Cloud sea: 1-3 big textured layers below the isles, snapped to the tile
-- grid around the player (so the texture never slides) and scrolled with the
-- wind at different speeds (parallax). Tint follows day / night and region.
------------------------------------------------------------------------------
Sky = {scrollU = {0, 0, 0}, scrollV = {0, 0, 0}}
Amb.sky = Sky
Sky.LAYERS = {{y = -110, tile = 220, speed = 3.2, trans = 0.3}, {y = -142, tile = 320, speed = 2.1, trans = 0.42}, {y = -180, tile = 460, speed = 1.2, trans = 0.55}}
local function cloudLayer(i)
	local layer = Pools.clouds[i]
	if layer and layer.part.Parent then return layer end
	local part = newPart("Cloud sea " .. i, Vector3.new(2048, 1, 2048), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
	if not part then return nil end
	local tex = Instance.new("Texture")
	tex.Name = "Clouds"
	tex.Face = Enum.NormalId.Top
	tex.Texture = A.SMOKE
	tex.StudsPerTileU, tex.StudsPerTileV = Sky.LAYERS[i].tile, Sky.LAYERS[i].tile
	tex.Transparency = Sky.LAYERS[i].trans
	tex.Parent = part
	layer = {part = part, texture = tex}
	Pools.clouds[i] = layer
	return layer
end
function Sky.update(dt)
	local b, f = Amb.b, Amb.focus
	local day = L.dayFactor(Amb.clock)
	local col = hex(A.CLOUD_NIGHT):Lerp(hex(A.CLOUD_DAY), day)
	local tint = A.CLOUD_TINT[Amb.key]
	if tint then col = col:Lerp(hex(tint), 0.45) end
	if Amb.weather == "Storm" or Amb.weather == "Rain" then col = col:Lerp(hex("6E7684"), if Amb.weather == "Storm" then 0.5 else 0.3) end
	for i = 1, 3 do
		local spec = Sky.LAYERS[i]
		local layer = if i <= b.clouds then cloudLayer(i) else nil
		if layer then
			local sx = math.floor(f.X / spec.tile + 0.5) * spec.tile
			local sz = math.floor(f.Z / spec.tile + 0.5) * spec.tile
			layer.part.CFrame = CFrame.new(sx, spec.y, sz)
			layer.texture.Color3 = col
			layer.texture.Transparency = if Amb.interior then 1 else spec.trans
		end
	end
end

------------------------------------------------------------------------------
-- Selection (2 Hz): which props sway, which sources / water / falls / flocks
-- get pooled effects. Scratch arrays are reused.
------------------------------------------------------------------------------
local Select = {sources = {}, ponds = {}, islands = {}, falls = {}, landmarks = {}}
local function dist2(p, f)
	local dx, dy, dz = p.X - f.X, p.Y - f.Y, p.Z - f.Z
	return dx * dx + dy * dy + dz * dz
end
local function ltmRaw(part) return part.LocalTransparencyModifier end
local function isHidden(part)
	local ok, v = pcall(ltmRaw, part)
	return ok and type(v) == "number" and v >= 1
end
-- Capture a swayer's rest frame and pivot when it (re)activates.
local function arm(e, rest)
	local cf, size = rest or e.part.CFrame, e.part.Size
	if e.host and e.host:IsA("BasePart") then
		e.hostCF = e.host.CFrame
		e.rel = e.hostCF:ToObjectSpace(cf)
	end
	local mode = e.def.mode
	local top = mode == "banner" or mode == "lantern"
	local pp = (cf * CFrame.new(0, if top then size.Y / 2 else -size.Y / 2, 0)).Position
	e.base, e.pivot, e.off, e.sign = cf, pp, cf - pp, if top then -1 else 1
end
function Sway.select()
	local b, f = Amb.b, Amb.focus
	local n = compact(Sway.list, "part")
	for i = 1, n do
		local e = Sway.list[i]
		local part = e.part
		-- QC M3: the host moved (the forge re-places the clone with it): the
		-- rest frame follows the host (read from the host, since our own sway
		-- write may already have replaced the forge's). Any other writer is
		-- caught by comparing the clone with our last write.
		if e.epoch ~= 0 and e.hostCF and e.host.Parent and e.host.CFrame ~= e.hostCF then
			arm(e, e.host.CFrame * e.rel)
			if e.written then part.CFrame = e.base end
			e.written = nil
		elseif e.epoch ~= 0 and e.written then
			local cf = part.CFrame
			if (cf.Position - e.written.Position).Magnitude > 0.01 or cf.UpVector:Dot(e.written.UpVector) < 0.99999 then
				e.epoch, e.written = 0, nil
			end
		end
		if e.epoch == 0 then e.pos = part.CFrame.Position end
		-- QC M2: a hidden prop (a depleted node, gather.client.lua) and a host
		-- that came loose (QC M3) never sway.
		if isHidden(part) or (e.host and e.host.Parent and e.host.Anchored == false) then
			e.d2 = math.huge
		else
			e.d2 = dist2(e.pos, f)
		end
	end
	-- The previous active set becomes `prev`; the new one is chosen into `active`.
	Sway.prev, Sway.active = Sway.active, Sway.prev
	local want = if Amb.reduced or Amb.interior then 0 else b.sway
	local m = A.nearest(Sway.list, n, want, b.swayRadius * b.swayRadius, Sway.active)
	Sway.epoch += 1
	for i = 1, m do
		local e = Sway.active[i]
		if e.epoch == 0 then arm(e) end
		e.epoch = Sway.epoch
	end
	for i = 1, #Sway.prev do
		local e = Sway.prev[i]
		if e.epoch ~= Sway.epoch then
			if e.base and e.part.Parent and e.written then e.part.CFrame = e.base end
			e.epoch, e.written = 0, nil
		end
	end
	table.clear(Sway.prev)
	Sway.count = m
end

-- Pooled source emitters (embers / spores / void / shimmer) on the nearest sources.
local function sourceSlot(i)
	local s = Pools.sources[i]
	-- A source part that left the world took the attachment with it.
	if s and (s.part == nil or s.attachment.Parent ~= nil) then return s end
	if s then setEmitting(s.emitter, false) end
	local att = Instance.new("Attachment")
	att.Name = "IsleAmbienceSource"
	local em = newEmitter(att, "Source", "embers")
	s = {attachment = att, emitter = em, part = nil}
	Pools.sources[i] = s
	return s
end
local function sourceLive(e)
	if e.kind == "embers" and e.part:GetAttribute("BeaconFlame") then return e.part.Transparency < 1 end
	if e.kind == "shimmer" then
		-- A depleted fishing spot goes calm (gather.client.lua hides its ripples).
		local ok, hidden = pcall(function() return e.part.LocalTransparencyModifier >= 1 end)
		return not (ok and hidden)
	end
	return true
end
function Amb.selectSources()
	local b, f = Amb.b, Amb.focus
	local n = compact(World.sources, "part")
	for i = 1, n do
		local e = World.sources[i]
		e.d2 = if sourceLive(e) then dist2(e.part.CFrame.Position, f) else math.huge
	end
	local want = if Amb.interior then 0 else b.sources
	local m = A.nearest(World.sources, n, want, b.sourceRadius * b.sourceRadius, Select.sources)
	for i = 1, b.sources do
		local e = Select.sources[i]
		local s = if i <= m or Pools.sources[i] then sourceSlot(i) else nil
		if s then
			if i <= m and e then
				if s.part ~= e.part then
					s.part = e.part
					s.attachment.Parent = e.part
					s.attachment.Position = Vector3.new(0, e.part.Size.Y * 0.45, 0)
				end
				configure(s.emitter, e.kind)
				setEmitting(s.emitter, true, A.rateFor(e.kind, b))
			else
				setEmitting(s.emitter, false)
			end
		end
	end
end

-- Waterfalls: a faster highlight sheet over the World Art beam and a lip
-- spray on the nearest b.falls; the server's mist is culled past waterRadius.
local function fallExtras(w)
	local f = Pools.falls[w.beam]
	if f then return f end
	local lip = w.beam.Attachment0
	local foot = w.beam.Attachment1
	if not lip or not foot then return nil end
	local sheet = Instance.new("Beam")
	sheet.Name = "Waterfall sheet"
	sheet.Attachment0, sheet.Attachment1 = lip, foot
	sheet.Texture = A.SPARKLE
	sheet.TextureMode, sheet.TextureLength, sheet.TextureSpeed = Enum.TextureMode.Wrap, 3, -3.2
	sheet.Width0, sheet.Width1 = w.beam.Width0 * 0.7, w.beam.Width1 * 0.8
	sheet.FaceCamera, sheet.Segments, sheet.LightEmission, sheet.LightInfluence = false, 6, 0.5, 0.5
	sheet.Color = ColorSequence.new(hex("FFFFFF"), hex("D6F4FF"))
	sheet.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1)})
	sheet.Enabled = false
	sheet.Parent = folder()
	local spray = newEmitter(lip, "Waterfall spray", "mist")
	trySet(spray, "EmissionDirection", Enum.NormalId.Right)
	f = {sheet = sheet, spray = spray}
	Pools.falls[w.beam] = f
	return f
end
function Amb.selectFalls()
	local b, f = Amb.b, Amb.focus
	local n = compact(World.falls, "beam")
	local r2 = b.waterRadius * b.waterRadius
	for i = 1, n do
		local w = World.falls[i]
		local lip = w.beam.Attachment0
		local host = lip and lip.Parent
		w.d2 = if host and host:IsA("BasePart") then dist2((host.CFrame * lip.CFrame).Position, f) else math.huge
		local mistHost = w.beam.Attachment1
		local mist = mistHost and mistHost:FindFirstChild("Waterfall mist")
		if mist then
			local near = w.d2 <= r2 and not Amb.interior
			if mist.Enabled ~= near then mist.Enabled = near end
		end
	end
	local m = A.nearest(World.falls, n, if Amb.interior then 0 else b.falls, r2, Select.falls)
	for beam, x in pairs(Pools.falls) do x.keep = false end
	for i = 1, m do
		local x = fallExtras(Select.falls[i])
		if x then
			x.keep = true
			x.sheet.Enabled = true
			setEmitting(x.spray, true, A.rateFor("mist", b))
		end
	end
	for _, x in pairs(Pools.falls) do
		if not x.keep then
			x.sheet.Enabled = false
			setEmitting(x.spray, false)
		end
	end
end

-- Foam: pooled surf segments around the nearest island rims and pond edges.
local Foam = {list = {}, parts = {}, cframes = {}, count = 0, last = 0}
Amb.foam = Foam
local function foamPart(i, kind)
	local e = Foam.list[i]
	if not e then
		local p = newPart("Foam", Vector3.new(0.35, 2.6, 2.6), hex("F4FBFF"), Enum.Material.SmoothPlastic, 0.45, Enum.PartType.Cylinder)
		if not p then return nil end
		e = {part = p, center = Vector3.new(0, 0, 0), radius = 0, angle = 0, y = 0, kind = kind}
		Foam.list[i] = e
	end
	if e.kind ~= kind then
		e.kind = kind
		e.part.Material = if kind == "pond" then Enum.Material.ForceField else Enum.Material.SmoothPlastic
		e.part.Size = if kind == "pond" then Vector3.new(0.12, 1.1, 1.1) else Vector3.new(0.35, 3.4, 3.4)
	end
	return e
end
-- QC L5: a still frame (reduced motion) is written once per placement.
local function setFoam(e, center, radius, angle, y)
	if e.center ~= center or e.radius ~= radius or e.angle ~= angle or e.y ~= y then
		e.center, e.radius, e.angle, e.y = center, radius, angle, y
		Foam.placed = false
	end
end
function Amb.selectFoam()
	local b, f = Amb.b, Amb.focus
	local used = 0
	if b.foam > 0 and not Amb.interior then
		local r2 = b.waterRadius * b.waterRadius
		-- Ponds first (close, readable), then island rims.
		local np = compact(World.ponds, "part")
		for i = 1, np do local e = World.ponds[i]; e.d2 = dist2(e.part.CFrame.Position, f) end
		local mp = A.nearest(World.ponds, np, 6, math.min(r2, 160 * 160), Select.ponds)
		for i = 1, mp do
			local pond = Select.ponds[i].part
			local r = math.max(pond.Size.Y, pond.Size.Z) / 2
			local k = math.clamp(math.floor(2 * math.pi * r / 1.6), 6, 18)
			if used + k > b.foam then break end
			for j = 1, k do
				local e = foamPart(used + j, "pond")
				if e then
					setFoam(e, pond.CFrame.Position, r + 0.05, (j - 1) * 2 * math.pi / k, pond.CFrame.Position.Y + pond.Size.X / 2 + 0.03)
				end
			end
			used += k
		end
		local ni = compact(World.islands, "model")
		for i = 1, ni do
			local e = World.islands[i]
			local c = e.center
			-- Distance to the rim, not the centre: a big isle's surf is near you.
			local d = math.max(0, math.sqrt(dist2(c, f)) - e.radius)
			e.d2 = d * d
		end
		local mi = A.nearest(World.islands, ni, 3, r2, Select.islands)
		for i = 1, mi do
			local isle = Select.islands[i]
			local k = math.clamp(math.floor(2 * math.pi * isle.radius / 7), 10, 40)
			if used + k > b.foam then k = b.foam - used end
			if k <= 0 then break end
			-- Overlapping puffs: each a little wider than its share of the rim.
			local width = math.clamp(2 * math.pi * isle.radius / k * 1.3, 3, 10)
			for j = 1, k do
				local e = foamPart(used + j, "isle")
				if e then
					setFoam(e, isle.center, isle.radius + 1.6, (j - 1) * 2 * math.pi / k + i, isle.center.Y - 1.1)
					if math.abs(e.part.Size.Y - width) > 0.05 then e.part.Size = Vector3.new(0.35, width, width) end
				end
			end
			used += k
		end
	end
	for i = used + 1, Foam.count do
		local e = Foam.list[i]
		if e then e.part.CFrame = PARK end
	end
	local count = math.min(used, #Foam.list)
	if count ~= Foam.count then Foam.placed = false end
	Foam.count = count
end

-- Flocks: boids around the nearest landmarks (birds; butterflies on meadow
-- and home isles by day; everyone roosts at night or indoors).
local Flock = {birds = {}, parts = {}, cframes = {}, count = 0, last = 0, centers = {}, radius = {}}
Amb.flock = Flock
local function bird(i)
	local e = Flock.birds[i]
	if e then return e end
	local p = newPart("Bird", Vector3.new(1.3, 0.12, 0.55), hex("2E3440"), Enum.Material.SmoothPlastic, 0)
	if not p then return nil end
	e = {part = p, pos = Vector3.new(0, 4000, 0), vel = Vector3.new(0, 0, 0), flock = 1, seed = i * 1.618, kind = "bird"}
	Flock.birds[i] = e
	return e
end
function Amb.selectFlocks()
	local b, f = Amb.b, Amb.focus
	local n = compact(World.landmarks, "part")
	for i = 1, n do local e = World.landmarks[i]; e.d2 = dist2(e.part.CFrame.Position, f) end
	local roost = Amb.night or Amb.interior or Amb.weather == "Storm" or Amb.weather == "Rain"
	local flocks = if roost then 0 else A.nearest(World.landmarks, n, b.flocks, 400 * 400, Select.landmarks)
	local per = if flocks > 0 then math.floor(b.birds / math.max(1, b.flocks)) else 0
	local butterflies = Amb.region.butterflies == true
	local count = 0
	for k = 1, flocks do
		local lm = Select.landmarks[k].part
		local foot = math.max(lm.Size.X, lm.Size.Z) / 2
		local top = lm.CFrame.Position + Vector3.new(0, if butterflies then -lm.Size.Y / 2 else lm.Size.Y / 2 + 14, 0)
		Flock.centers[k] = top
		Flock.radius[k] = foot + (if butterflies then 4 else 10)
		for j = 1, per do
			local e = bird(count + 1)
			if not e then break end
			count += 1
			e.flock = k
			local kind = if butterflies then "butterfly" else "bird"
			if e.kind ~= kind then
				e.kind = kind
				e.part.Size = if butterflies then Vector3.new(0.5, 0.06, 0.4) else Vector3.new(1.3, 0.12, 0.55)
				e.part.Color = if butterflies then hex(if j % 3 == 0 then "FFD166" elseif j % 3 == 1 then "F78FB3" else "8EC9FF") else hex("2E3440")
				e.part.Material = if butterflies then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
			if (e.pos - top).Magnitude > 120 then e.pos = top + Vector3.new(math.cos(e.seed) * 8, 2, math.sin(e.seed) * 8) end
		end
	end
	for i = count + 1, Flock.count do
		local e = Flock.birds[i]
		if e then e.part.CFrame = PARK; e.pos = PARK.Position end
	end
	Flock.count = count
end

------------------------------------------------------------------------------
-- Per-frame updates. FRAME-BEGIN / FRAME-END: no tables, closures,
-- Instance.new, string building or table.insert between the markers.
------------------------------------------------------------------------------
-- FRAME-BEGIN sky
-- Scroll the cloud layers smoothly with the wind (each at its own speed).
function Sky.frame(dt)
	local dx, dz = A.windDir(Amb.tw)
	local layers = Pools.clouds
	for i = 1, #layers do
		local layer, spec = layers[i], Sky.LAYERS[i]
		if layer and spec then
			-- U and V wrap separately at the tile size, so the wrap is seamless.
			local u = (Sky.scrollU[i] + spec.speed * dx * dt) % spec.tile
			local v = (Sky.scrollV[i] + spec.speed * dz * dt) % spec.tile
			Sky.scrollU[i], Sky.scrollV[i] = u, v
			layer.texture.OffsetStudsU, layer.texture.OffsetStudsV = u, v
		end
	end
end
-- FRAME-END sky

-- FRAME-BEGIN sway
function Sway.frame()
	local n, active, parts, cframes = Sway.count or 0, Sway.active, Sway.parts, Sway.cframes
	local t, base, weather = Amb.tw, Amb.region.wind, Amb.weather
	-- QC M6: the wind direction once per frame, not once per prop.
	local dx, dz = A.windDir(t)
	local axis = Vector3.new(dz, 0, -dx)
	local m = 0
	for i = 1, n do
		local e = active[i]
		if e and e.off then
			local p = e.pivot
			local wind = A.windAtDir(t, p.X, p.Z, base, weather, dx, dz)
			local lean, twist = A.swayAngles(e.def, t, wind, e.phase, false)
			local rot = CFrame.fromAxisAngle(axis, lean * e.sign)
			if twist ~= 0 then rot *= CFrame.Angles(0, twist, 0) end -- only banners twist
			local cf = (rot + p) * e.off
			m += 1
			parts[m] = e.part
			cframes[m] = cf
			e.written = cf
		end
	end
	moveAll(parts, cframes, m, Sway.last)
	Sway.last = m
end
-- FRAME-END sway

-- FRAME-BEGIN foam
function Foam.frame()
	local t, still = Amb.tw, Amb.reduced
	if still and Foam.placed then return end
	Foam.writes = (Foam.writes or 0) + 1
	local parts, cframes = Foam.parts, Foam.cframes
	local m = 0
	for i = 1, Foam.count do
		local e = Foam.list[i]
		if e then
			local a = e.angle + (if still then 0 else t * 0.02)
			local breathe = if still then 0 else 0.35 * math.sin(t * 0.9 + i * 1.7)
			local bob = if still then 0 else 0.1 * math.sin(t * 1.3 + i)
			local r = e.radius + breathe
			m += 1
			parts[m] = e.part
			cframes[m] = CFrame.new(e.center.X + math.cos(a) * r, e.y + bob, e.center.Z + math.sin(a) * r) * CFrame.Angles(0, -a, math.pi / 2)
		end
	end
	moveAll(parts, cframes, m, Foam.last)
	Foam.last = m
	Foam.placed = still
end
-- FRAME-END foam

-- FRAME-BEGIN flock
function Flock.frame(dt)
	local t, birds, parts, cframes = Amb.tw, Flock.birds, Flock.parts, Flock.cframes
	local m = 0
	for i = 1, Flock.count do
		local e = birds[i]
		local center = e and Flock.centers[e.flock]
		if center then
			local fly = e.kind == "bird"
			local orbit = Flock.radius[e.flock] or (if fly then 18 else 5)
			local goal = center + Vector3.new(math.cos(t * (if fly then 0.35 else 0.6) + e.seed) * orbit,
				math.sin(t * 0.5 + e.seed * 2) * (if fly then 4 else 1.5) + (if fly then 0 else 3),
				math.sin(t * (if fly then 0.35 else 0.6) + e.seed) * orbit)
			-- Seek the goal, keep apart from the two flock-mates either side.
			local steer = (goal - e.pos) * (if fly then 0.9 else 1.6)
			for k = i - 2, i + 2 do
				local o = birds[k]
				if k ~= i and o and o.flock == e.flock and k <= Flock.count and k >= 1 then
					local away = e.pos - o.pos
					local d = away.Magnitude
					if d > 0.01 and d < 4 then steer += away * ((4 - d) / d) * 2 end
				end
			end
			local vel = e.vel + steer * dt
			local speed = vel.Magnitude
			local maxSpeed = if fly then 16 else 4
			if speed > maxSpeed then vel = vel * (maxSpeed / speed) end
			e.vel = vel
			e.pos += vel * dt
			local flap = math.sin(t * (if fly then 9 else 16) + e.seed * 3) * (if fly then 0.5 else 0.9)
			m += 1
			parts[m] = e.part
			if speed > 0.05 then
				cframes[m] = CFrame.lookAt(e.pos, e.pos + vel) * CFrame.Angles(0, 0, flap)
			else
				cframes[m] = CFrame.new(e.pos) * CFrame.Angles(0, e.seed, flap)
			end
		end
	end
	moveAll(parts, cframes, m, Flock.last)
	Flock.last = m
end
-- FRAME-END flock

------------------------------------------------------------------------------
-- Skill VFX: sparks, level-up, rarity pillars, XP orbs, lightning bolts.
------------------------------------------------------------------------------
local FX = {orbs = {}, beams = {}, bolt = {on = false, until_ = 0}, ring = {on = false}, lastImpact = nil, lastImpactAt = -1e9,
	levels = {}, lastSeq = 0, colours = {}}
Amb.fx = FX
local function colourSeq(h)
	local c = FX.colours[h]
	if not c then c = ColorSequence.new(hex(h)); FX.colours[h] = c end
	return c
end
local function burstHost()
	local host = Pools.burst
	if host and host.part.Parent then return host end
	local part = newPart("Ambience burst", Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
	if not part then return nil end
	local att = Instance.new("Attachment")
	att.Parent = part
	local sparks = newEmitter(att, "Sparks", "embers")
	sparks.Lifetime, sparks.Drag = NumberRange.new(0.25, 0.5), 3
	sparks.Size = NumberSequence.new(0.12, 0)
	sparks.SpreadAngle = Vector2.new(60, 60)
	local chips = newEmitter(att, "Chips", "dust")
	chips.Lifetime = NumberRange.new(0.4, 0.8)
	chips.Acceleration = Vector3.new(0, -40, 0)
	chips.Size = NumberSequence.new(0.22, 0.1)
	chips.LightEmission = 0
	local glitter = newEmitter(att, "Glitter", "shimmer")
	glitter.Lifetime, glitter.Speed = NumberRange.new(0.8, 1.6), NumberRange.new(6, 14)
	glitter.Acceleration = Vector3.new(0, 6, 0)
	host = {part = part, sparks = sparks, chips = chips, glitter = glitter}
	Pools.burst = host
	return host
end
-- The resource colour of the gather node nearest an impact (event-driven).
local TINT = {}
for _, tiers in pairs(Data.ResourceTiers or {}) do
	for _, def in ipairs(tiers) do if def.id and def.color then TINT[def.id] = def.color end end
end
local function nodeTint(pos)
	local best, bestD = nil, 36
	for _, node in ipairs(World.nodes) do
		if node.Parent then
			local d = dist2(node.CFrame.Position, pos)
			if d < bestD then best, bestD = node, d end
		end
	end
	local id = best and best:GetAttribute("GatherNode")
	return id and TINT[id] or nil
end
function Amb.impact(name, fx, position, isLocal)
	if typeof(position) ~= "Vector3" then return end
	local host = burstHost()
	if not host then return end
	local spec, sparks, chips = A.sparkFor(fx, Amb.reduced)
	if (position - Amb.focus).Magnitude > Amb.b.sourceRadius then return end
	host.part.CFrame = CFrame.new(position)
	host.sparks.Color = colourSeq(spec.sparks)
	host.sparks.Speed = NumberRange.new(spec.speed * 0.6, spec.speed)
	host.sparks.SpreadAngle = Vector2.new(spec.spread, spec.spread)
	host.chips.Color = colourSeq(nodeTint(position) or spec.chips)
	if not isLocal then sparks, chips = math.ceil(sparks / 2), math.ceil(chips / 2) end
	emit(host.sparks, sparks)
	emit(host.chips, chips)
	if isLocal then FX.lastImpact, FX.lastImpactAt = position, os.clock() end
end
-- The point a reward rises from: the last strike (if recent and near), else the player.
local function rewardOrigin()
	local root = rootPart()
	local rootPos = if root then root.CFrame.Position else Amb.focus
	if FX.lastImpact and os.clock() - FX.lastImpactAt < 3 and (FX.lastImpact - rootPos).Magnitude < 40 then return FX.lastImpact end
	return nil
end
function Amb.levelUp(skill, level)
	local root = rootPart()
	Amb.cue("levelup", skill, level)
	if not root then return end
	local host = burstHost()
	local skillDef = Data.Skills and Data.Skills[skill]
	local colour = (type(skillDef) == "table" and skillDef.color) or "FFD166"
	if host then
		host.part.CFrame = CFrame.new(root.CFrame.Position)
		host.glitter.Color = colourSeq(colour)
		emit(host.glitter, if Amb.reduced then 16 else A.LEVEL_BURST.sparkles)
	end
	if not Amb.reduced then
		local ring = FX.ring
		if not ring.part or not ring.part.Parent then
			ring.part = newPart("Level ring", Vector3.new(0.2, 1, 1), hex(colour), Enum.Material.Neon, 0.3, Enum.PartType.Cylinder)
		end
		if ring.part then
			ring.part.Color = hex(colour)
			ring.on, ring.t0, ring.root = true, os.clock(), root
		end
	end
	if A.SOUNDS.levelUp ~= "" then
		local sound = Pools.sound
		if not sound or not sound.Parent then
			sound = Instance.new("Sound")
			sound.Name = "Level up"
			sound.SoundId, sound.Volume = A.SOUNDS.levelUp, 0.45
			sound.Parent = folder()
			Pools.sound = sound
		end
		pcall(playRaw, sound)
	end
end
function Amb.rareDrop(rarity)
	local spec = A.beamFor(rarity, Data)
	if not spec then return end
	Amb.cue("raredrop", rarity)
	local root = rootPart()
	local base = rewardOrigin() or (root and (root.CFrame * CFrame.new(0, -2.5, -4)).Position)
	if not base then return end
	-- Reuse the oldest pillar when all are showing.
	local slot, oldest = nil, math.huge
	for i = 1, Amb.b.beams do
		local e = FX.beams[i]
		if not e then
			-- QC L9: a pillar is two parts; never create a lone core past the cap.
			if Amb.partsMade + 2 > Amb.b.parts then break end
			local core = newPart("Rarity pillar", Vector3.new(1, 1, 1), Color3.new(1, 1, 1), Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
			local halo = newPart("Rarity halo", Vector3.new(1, 1, 1), Color3.new(1, 1, 1), Enum.Material.ForceField, 0.2, Enum.PartType.Cylinder)
			e = {core = core, halo = halo, on = false, t0 = 0}
			FX.beams[i] = e
		end
		if not e.on then slot = e break end
		if e.t0 < oldest then slot, oldest = e, e.t0 end
	end
	if not slot then return end
	local colour = hex(spec.color)
	slot.on, slot.t0, slot.spec, slot.base = true, os.clock(), spec, base
	slot.core.Color, slot.halo.Color = colour, colour
	slot.core.Size = Vector3.new(spec.height, spec.width, spec.width)
	slot.halo.Size = Vector3.new(spec.height, spec.width * 3, spec.width * 3)
	local up = CFrame.new(base + Vector3.new(0, spec.height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	slot.core.CFrame, slot.halo.CFrame = up, up
	slot.color = spec.color
	local host = burstHost()
	if host then
		host.part.CFrame = CFrame.new(base)
		host.glitter.Color = colourSeq(spec.color)
		emit(host.glitter, 10 + 4 * spec.rank)
	end
end
function Amb.xp(gains)
	if type(gains) ~= "table" then return end
	local from = rewardOrigin()
	if not from then return end
	for _, g in ipairs(gains) do
		local count = A.orbCount(type(g) == "table" and g.amount, Amb.b)
		for _ = 1, count do
			local slot
			for i = 1, Amb.b.orbs do
				local e = FX.orbs[i]
				if not e then
					local p = newPart("XP orb", Vector3.new(0.45, 0.45, 0.45), Color3.new(1, 1, 1), Enum.Material.Neon, 0, Enum.PartType.Ball)
					if not p then break end
					local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
					a0.Position, a1.Position = Vector3.new(0, 0.18, 0), Vector3.new(0, -0.18, 0)
					a0.Parent, a1.Parent = p, p
					local trail = Instance.new("Trail")
					trail.Attachment0, trail.Attachment1 = a0, a1
					trail.Lifetime, trail.LightEmission, trail.FaceCamera = 0.35, 1, true
					trail.Transparency = NumberSequence.new(0.2, 1)
					trail.Enabled = false
					trail.Parent = p
					e = {part = p, trail = trail, on = false, t0 = 0, from = Vector3.new(0, 0, 0), side = 0}
					FX.orbs[i] = e
				end
				if not e.on then slot = e break end
			end
			if not slot then return end
			local colour = hex(type(g) == "table" and g.color or "FFD166")
			slot.part.Color = colour
			slot.trail.Color = ColorSequence.new(colour)
			slot.on, slot.t0 = true, os.clock() + math.random() * 0.15
			slot.from = from + Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5)
			slot.side = math.random() * 2 - 1
			slot.part.CFrame = CFrame.new(slot.from)
			slot.trail.Enabled = true
		end
	end
end
-- A visible bolt for a strike in the player's region (none under reduced motion).
function Amb.strike(region, at)
	if region ~= Amb.key or Amb.interior then return end
	local delay = 0.8 + 1.6 * A.hash(math.floor(at * 10), 7)
	Amb.cue("thunder", region, delay)
	if not Amb.flashing or Amb.b.bolts <= 0 then return end -- reduced motion / Flashing effects off (QC L6)
	local bolt = FX.bolt
	if not bolt.parts then
		bolt.parts = {}
		for i = 1, A.BOLT_SEGMENTS do
			local p = newPart("Lightning", Vector3.new(0.5, 1, 0.5), hex("E8F0FF"), Enum.Material.Neon, 1)
			if not p then break end
			bolt.parts[i] = p
		end
	end
	local angle = 2 * math.pi * A.hash(math.floor(at * 10), 3)
	local dist = 140 + 120 * A.hash(math.floor(at * 10), 5)
	local x, z = Amb.focus.X + math.cos(angle) * dist, Amb.focus.Z + math.sin(angle) * dist
	local y = Amb.focus.Y + 170
	local prev = Vector3.new(x, y, z)
	for i, p in ipairs(bolt.parts) do
		local nextPoint = Vector3.new(x + (A.hash(i, math.floor(at)) - 0.5) * 30, y - i * 36, z + (A.hash(i + 9, math.floor(at)) - 0.5) * 30)
		local len = (nextPoint - prev).Magnitude
		p.Size = Vector3.new(0.5 + 0.4 * (A.BOLT_SEGMENTS - i) / A.BOLT_SEGMENTS, len, 0.5)
		p.CFrame = CFrame.lookAt((prev + nextPoint) / 2, nextPoint) * CFrame.Angles(math.pi / 2, 0, 0)
		prev = nextPoint
	end
	bolt.on, bolt.at = true, at
end

-- FRAME-BEGIN fx
function FX.frame()
	local clock = os.clock()
	local root = rootPart()
	local target = if root then root.CFrame.Position else Amb.focus
	for i = 1, #FX.orbs do
		local e = FX.orbs[i]
		if e.on then
			local k = math.clamp((clock - e.t0) / A.ORB_TIME, 0, 1)
			local mid = (e.from + target) / 2 + Vector3.new(e.side * 2, 4, 0)
			local a = e.from:Lerp(mid, k)
			local b = mid:Lerp(target, k)
			e.part.CFrame = CFrame.new(a:Lerp(b, k))
			if k >= 1 then
				e.on = false
				e.trail.Enabled = false
				e.part.CFrame = PARK
			end
		end
	end
	for i = 1, #FX.beams do
		local e = FX.beams[i]
		if e.on then
			local age = clock - e.t0
			local life = e.spec.life
			local fade = math.clamp((life - age) / 0.6, 0, 1)
			local pulse = if e.spec.pulse and not Amb.reduced then 0.12 * math.sin(age * 6) else 0
			e.core.Transparency = 1 - (0.75 + pulse) * fade
			e.halo.Transparency = 1 - 0.6 * fade
			if age >= life then
				e.on = false
				e.core.CFrame, e.halo.CFrame = PARK, PARK
			end
		end
	end
	local ring = FX.ring
	if ring.on and ring.part then
		local k = (clock - ring.t0) / A.LEVEL_BURST.time
		if k >= 1 or not ring.root or not ring.root.Parent then
			ring.on = false
			ring.part.CFrame = PARK
		else
			local d = 2 + A.LEVEL_BURST.ring * k
			ring.part.Size = Vector3.new(0.15, d, d)
			ring.part.Transparency = 0.2 + 0.8 * k
			ring.part.CFrame = CFrame.new(ring.root.CFrame.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end
	local bolt = FX.bolt
	if bolt.on and bolt.parts then
		local flash = L.flashAt(now() - bolt.at)
		local show = flash > 0.3 and Amb.flashing
		for i = 1, #bolt.parts do bolt.parts[i].Transparency = if show then 0.05 else 1 end
		if flash <= 0 then bolt.on = false end
	end
end
-- FRAME-END fx

------------------------------------------------------------------------------
-- Inputs: impacts (animate.client.lua), XP gains (ui.client.lua), snapshots
-- (pickups for rarity pillars, levels for level-ups), weather strikes.
------------------------------------------------------------------------------
connect(bindable("IsleImpactLocal"), "Event", function(...) pcall(Amb.impact, ...) end)
connect(bindable("IsleXpLocal"), "Event", function(gains) pcall(Amb.xp, gains) end)
function Amb.snapshot(snap)
	if type(snap) ~= "table" or snap.replay then return end
	if type(snap.seq) == "number" then
		if snap.seq <= FX.lastSeq then return end
		FX.lastSeq = snap.seq
	end
	if type(snap.levels) == "table" then
		for skill, level in pairs(snap.levels) do
			if type(level) == "number" then
				local was = FX.levels[skill]
				FX.levels[skill] = level
				if was and level > was then Amb.levelUp(skill, level) end
			end
		end
	end
	local rarity = A.rarestPickup(snap.pickups, Data)
	if rarity then Amb.rareDrop(rarity) end
end
connect(bindable("IsleSnapshotLocal"), "Event", function(snap) pcall(Amb.snapshot, snap) end)

------------------------------------------------------------------------------
-- Main loop.
------------------------------------------------------------------------------
local CONTEXT_STEP, SELECT_STEP, RESCAN_STEP = 0.25, 0.5, 10
Amb.cursor = A.newStrikeCursor()
Amb.swayFrame = function() Sway.frame() end -- the suite times one update (QC M6)
local acc = {context = CONTEXT_STEP, select = SELECT_STEP, rescan = 0, sway = 0}
Amb.acc = acc
function Amb.step(dt)
	dt = tonumber(dt) or 0
	if dt ~= dt or dt < 0 then dt = 0 end
	if dt > 0.25 then dt = 0.25 end
	local t = now()
	Amb.tw = t - A.EPOCH -- QC L3: no daily wrap (the gust field never jumps)
	acc.context += dt; acc.select += dt; acc.rescan += dt; acc.sway += dt
	if acc.context >= CONTEXT_STEP then
		local frame = acc.context
		acc.context = 0
		Amb.context()
		Amb.particles()
		Sky.update(frame)
	end
	-- QC H2: lightning from the shared schedule on server time, on the frame it
	-- is due (no attribute round trip); the attribute only names the storm.
	if Amb.parsed and not Amb.interior and L.weatherFor(Amb.parsed, Amb.key) == "Storm" then
		local at = A.strikeDue(Amb.cursor, t, Amb.key, A.STRIKE_GRACE)
		if at then Amb.strike(Amb.key, at) end
	end
	if acc.select >= SELECT_STEP then
		acc.select = 0
		Amb.probe()
		Sway.select()
		Amb.selectSources()
		Amb.selectFalls()
		Amb.selectFoam()
		Amb.selectFlocks()
		Rescan.step()
		compact(World.nodes, nil)
	end
	if acc.rescan >= RESCAN_STEP then
		acc.rescan = 0
		scanRoots()
	end
	-- QC M6: sway and foam both run at the tier's sway rate.
	if acc.sway >= 1 / Amb.b.swayHz then
		acc.sway = 0
		if not Amb.reduced then Sway.frame() end
		Foam.frame()
	end
	Amb.anchorsFrame()
	Sky.frame(dt)
	Flock.frame(dt)
	FX.frame()
end
Amb.readTier()
scanRoots()
connect(RunService, "Heartbeat", Amb.step)
Amb.step(CONTEXT_STEP)
-- The chunk's value is read only by the headless suite (verify-ambience.luau).
return Amb
