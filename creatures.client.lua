-- IsleCreatures (client): forged, animated creature visuals (docs/DEPTH-CONTRACT.md §48).
--
-- Every creature is drawn here from authored meshes instead of the server's
-- primitive parts: combat monsters, slayer / lair / raid / world bosses and
-- their adds (tag IsleMonster, combat.server.lua), the Hollow Observatory's
-- Sentinels and umbral wisps, Skybreach Siege creatures, the Shellwarden, the
-- Compass Quay sky-ray and the bond companion (tag IsleCreature on their host
-- part) and summoned pets (pets.client.lua tags its local model).
--
--   * Rigs come from art/CreatureCatalog.lua (ReplicatedStorage.AetherCreatureArt):
--     a core mesh plus limb segments posed about their pivots, tier overlays
--     (pauldrons, horns, crowns, a ground rune ring) and Neon glow accents.
--   * Meshes are forged by the MeshForge (forge.client.lua) creature API, in
--     its own creature template pool (desktop 22 / phones 8, the last 6 / 3
--     reserved for bosses; LRU) and the instance / triangle budgets. When a
--     boss or world boss mesh is refused, the lowest-priority rigs (pets, then
--     ordinary creatures, farthest first) are released and the mesh retried
--     at once (QC H1). A rig missing a leg, arm, wing or claw is never shown:
--     it goes back to its primitives and retries later (QC H3). When the forge
--     refuses, the server's primitive model (or a host's legacy sculpture)
--     simply stays visible.
--   * The server stays authoritative. This script reads only replicated
--     attributes (CreatureRig, CreatureScale, Color, Level, Boss, WorldBoss,
--     Lair, Superior, CreatureTier, CreatureLandmark, Health, AddHealth, Dead,
--     Despawn, AttackAt, TelegraphAt / TelegraphWindup, LairStance,
--     VisualState) and the root's CFrame, hides the primitives locally
--     (LocalTransparencyModifier, crossfaded) and never writes to a replicated
--     instance's properties or attributes.
--   * Animation (shared/CreatureRules.lua R.pose): idle breathing / bob, a
--     distance-driven walk cycle, wing flaps, tail sway, orbiting shards, the
--     telegraph windup over [TelegraphAt - windup, TelegraphAt) and the slam
--     after it (server ticks: +-1 tick), the monster bite over the server's
--     0.25 s lunge, a hit flinch, a crossfade in and out, a death dissolve
--     (a despawn only fades). Reduced motion (Theme.reducedMotion, sampled
--     with the LOD pass) keeps telegraphs and strikes but drops idle motion.
--   * Level of detail (R.lod): full rig every frame near, the full rig at
--     15 Hz further out, the core alone at 8 Hz beyond, nothing past the core
--     range (bosses reach 1.7x, world bosses 2.6x); at most R.cap() rigs (24
--     desktop / 10 phones) by R.priority (bosses, landmarks, creatures, pets)
--     then distance, with hysteresis (R.capDistance). Phones carry fewer overlays.
--   * One BulkMoveTo per frame; no per-frame tables, closures or instances
--     (CFrame / Vector3 math values only).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local function load(name)
	local module = ReplicatedStorage:WaitForChild(name, 20)
	if not module then return nil end
	local ok, result = pcall(require, module)
	return if ok and type(result) == "table" then result else nil
end
local Rules = load("AetherCreatureRules")
local Catalog = load("AetherCreatureArt")
if not Rules or not Catalog or type(Catalog.rigs) ~= "table" then return end

local mobile = false
pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)
local player = Players.LocalPlayer
local Theme
task.spawn(function()
	pcall(function()
		local module = ReplicatedStorage:WaitForChild("AetherUiTheme", 15)
		if module then Theme = require(module) end
	end)
end)

local folder = Instance.new("Folder")
folder.Name = "CreatureVisuals"
folder.Parent = workspace

local forgeApi -- ReplicatedStorage.MeshForgeLocal (forge.client.lua)
local function forgeVisual(shape, tint, boss)
	forgeApi = forgeApi or ReplicatedStorage:FindFirstChild("MeshForgeLocal")
	if not forgeApi then return nil end
	local ok, clone, token, extent, center = pcall(forgeApi.Invoke, forgeApi, "creature", {shape = shape, tint = tint, boss = boss})
	if ok and typeof(clone) == "Instance" and type(token) == "number" then return clone, token, extent, center end
	return nil
end
local function forgeRelease(token)
	if forgeApi and token then pcall(forgeApi.Invoke, forgeApi, "creatureRelease", token) end
end

local function hex(value, fallback)
	if typeof(value) == "Color3" then return value end
	local ok, color = pcall(Color3.fromHex, tostring(value or fallback or "AAAAAA"))
	return if ok then color else Color3.fromRGB(170, 170, 170)
end

local records = {} -- host -> rec
local retrack = {} -- host -> clock: re-track after a pose error (QC L1)
local reduced = false
local Creatures = {records = records, folder = folder, mobile = mobile, bumps = 0}

-- Host attributes -> rec fields (one AttributeChanged connection per host).
local WATCHED = {Health = true, AddHealth = true, Dead = true, Despawn = true, AttackAt = true, TelegraphAt = true, TelegraphWindup = true,
	LairStance = true, VisualState = true, Color = true}
local TIER_ATTRS = {CreatureTier = true, Pet = true, WorldBoss = true, Boss = true, Lair = true, Superior = true, Level = true}
local function readAttrs(rec)
	local host = rec.host
	rec.attackAt = host:GetAttribute("AttackAt")
	rec.telegraphAt = host:GetAttribute("TelegraphAt")
	rec.telegraphWindup = host:GetAttribute("TelegraphWindup")
	rec.stance = host:GetAttribute("LairStance")
	rec.defeated = host:GetAttribute("VisualState") == "Defeated"
	rec.despawn = host:GetAttribute("Despawn") == true
	rec.health = tonumber(host:GetAttribute("Health")) or tonumber(host:GetAttribute("AddHealth"))
	if rec.health and rec.health <= 0 then rec.killed = true end
end
local function tierOf(host)
	return Rules.tier({
		CreatureTier = host:GetAttribute("CreatureTier"), Pet = host:GetAttribute("Pet"), WorldBoss = host:GetAttribute("WorldBoss"),
		Boss = host:GetAttribute("Boss"), Lair = host:GetAttribute("Lair"), Superior = host:GetAttribute("Superior"), Level = host:GetAttribute("Level"),
	})
end
local function rootOf(host)
	if host:IsA("BasePart") then return host end
	if host:IsA("Model") then
		local root = host.PrimaryPart or host:FindFirstChild("Root")
		if root and root:IsA("BasePart") then return root end
	end
	return nil
end
local function isBoss(rec) return rec.tier == "boss" or rec.tier == "world" end

-- Primitives: hidden locally (crossfaded) while the mesh rig is drawn ---------
local function vec(k)
	if type(k) == "table" then return Vector3.new(k[1], k[2], k[3]) end
	local n = tonumber(k) or 1
	return Vector3.new(n, n, n)
end
local function setPrimitives(rec, ltm)
	-- (Called per frame during a crossfade: plain writes, no closures.)
	for _, p in ipairs(rec.hidden) do p.LocalTransparencyModifier = ltm end
	rec.primitiveLtm = ltm
end
local function collectPrimitives(rec)
	local host, list = rec.host, rec.hidden
	table.clear(list)
	if host:IsA("BasePart") then table.insert(list, host) end
	-- A host part's legacy sculpture (QC H2 fallback) or a model's primitives.
	for _, d in ipairs(host:GetDescendants()) do
		if d:IsA("BasePart") and (d ~= rec.root or d.Transparency < 1) then table.insert(list, d) end
	end
	if not rec.addedConnection then
		-- Visuals that arrive later (the legacy sculpture builds asynchronously).
		rec.addedConnection = host.DescendantAdded:Connect(function(d)
			if rec.built and d:IsA("BasePart") then
				table.insert(rec.hidden, d)
				pcall(function() d.LocalTransparencyModifier = rec.primitiveLtm or 0 end)
			end
		end)
		table.insert(rec.connections, rec.addedConnection)
	end
end
local function showPrimitives(rec)
	setPrimitives(rec, 0)
	table.clear(rec.hidden)
end

-- Mesh + glow bookkeeping -------------------------------------------------
local function newGlow(g, rec, scale)
	local p = Instance.new("Part")
	p.Name = "Glow"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Transparency = 1 -- shown by the crossfade once posed
	local color = g.color
	if g.kind == "eye" and Rules.EYE_OVERRIDE[rec.tier] then color = Rules.EYE_OVERRIDE[rec.tier] end
	p.Color = hex(color)
	if g.bar then
		p.Shape = Enum.PartType.Block
		p.Size = (if g.kind == "rune" then Vector3.new(g.bar[1], 0.08, g.bar[2]) else Vector3.new(g.bar[1], g.bar[2], 0.08)) * scale
	else
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * (g.r * 2 * scale)
	end
	p.Parent = folder
	return p
end
local function releaseMeshes(rec, keep)
	for i = #rec.meshes, 1, -1 do
		local m = rec.meshes[i]
		if not keep or not keep[m.kind] then
			forgeRelease(m.token)
			table.remove(rec.meshes, i)
		end
	end
end
local function releaseGlows(rec)
	for _, g in ipairs(rec.glows) do g.part:Destroy() end
	table.clear(rec.glows)
end
local function release(rec)
	rec.built, rec.full, rec.pending, rec.fadeOutAt, rec.fadeAt = false, false, false, nil, nil
	releaseMeshes(rec)
	releaseGlows(rec)
	showPrimitives(rec)
end
-- QC H1: free creature templates for a boss by releasing the lowest-priority
-- built rigs (pets, then ordinary creatures; farthest first). Returns true
-- when something was released.
local function bumpFor(rec)
	local victim, vp, vd
	local mine = Rules.priority(rec.tier, rec.landmark)
	for _, other in pairs(records) do
		if other ~= rec and other.built and not other.pending and not other.dying then
			local p = Rules.priority(other.tier, other.landmark)
			local d = other.distance or 0
			if p < mine and (not victim or p < vp or (p == vp and d > vd)) then victim, vp, vd = other, p, d end
		end
	end
	if not victim then return false end
	release(victim)
	victim.retryAt = os.clock() + 8
	Creatures.bumps += 1
	return true
end
-- One forged mesh: {part, token, offset, kind = "core" | "seg" | "overlay", index}.
local function addMesh(rec, shape, tint, k, kind, index, extra)
	local clone, token, extent, center = forgeVisual(shape, tint, isBoss(rec))
	local tries = 0
	while not clone and isBoss(rec) and tries < Rules.BUMP_MAX and bumpFor(rec) do
		tries += 1
		clone, token, extent, center = forgeVisual(shape, tint, true)
	end
	if not clone then return nil end
	if not rec.alive then forgeRelease(token); return nil end
	local kv = vec(k) * rec.scale
	local m = {part = clone, token = token, kind = kind, index = index}
	pcall(function()
		clone.Size = Vector3.new(extent.X * kv.X, extent.Y * kv.Y, extent.Z * kv.Z)
		clone.CanQuery, clone.CanTouch, clone.CanCollide = false, false, false
		clone.CastShadow = rec.tier ~= "pet" and kind ~= "overlay"
		-- Hidden until posed; limbs added to a settled rig (LOD 1 -> 2) appear at once.
		clone.Transparency = if rec.built and not rec.fadeAt then (rec.alphaWritten or 0) else 1
	end)
	m.offset = CFrame.new(center.X * kv.X, center.Y * kv.Y, center.Z * kv.Z)
	if extra then for key, value in pairs(extra) do m[key] = value end end
	clone.Parent = folder
	table.insert(rec.meshes, m)
	return m
end

-- Build ---------------------------------------------------------------------
local function ringColor(rec)
	return hex((if rec.stance then Rules.STANCE_COLOR[rec.stance] else nil) or Rules.TIER_COLOR[rec.tier], "FF3B3B")
end
local function addRing(rec)
	local rig = rec.rig
	local r = (rig.anchors or {}).ring or 2
	return addMesh(rec, Rules.OVERLAY_SHAPES.ring, ringColor(rec), {r, 1, r}, "overlay", 0, {at = CFrame.new(0, -(rig.hip or 2) + 0.03, 0), ground = true, ring = true})
end
-- Limbs and overlays. Returns false when a structural segment failed (QC H3).
local function buildFull(rec)
	local rig, tint = rec.rig, rec.tint
	for i, seg in ipairs(rig.segs or {}) do
		if not addMesh(rec, seg.shape, tint, seg.k or 1, "seg", i) and Rules.STRUCTURAL[seg.role] then return false end
	end
	for _, overlay in ipairs(Rules.overlays(rec.tier, mobile)) do
		local shape = Rules.OVERLAY_SHAPES[overlay]
		local anchors = rig.anchors or {}
		local s = Rules.overlayScale(overlay, rig)
		local color = hex(Rules.OVERLAY_TINT[overlay] or Rules.TIER_COLOR[rec.tier], "FF3B3B")
		if overlay == "pauldron" and anchors.shoulder then
			local a = anchors.shoulder
			addMesh(rec, shape, color, s, "overlay", 0, {at = CFrame.new(a[1], a[2], a[3])})
			addMesh(rec, shape, color, s, "overlay", 0, {at = CFrame.new(-a[1], a[2], a[3]) * Rules.MIRROR.yaw})
		elseif (overlay == "crown" or overlay == "worldcrown" or overlay == "horns") and anchors.crown then
			local a = anchors.crown
			addMesh(rec, shape, color, s, "overlay", 0, {at = CFrame.new(a[1], a[2], a[3])})
		elseif overlay == "ring" then
			addRing(rec)
		end
	end
	rec.full = true
	return true
end
local function build(rec, full)
	rec.pending = true
	task.spawn(function()
		local ok, complete = pcall(function()
			if not rec.built then
				local core = addMesh(rec, rec.rig.core, rec.tint, 1, "core", 0)
				if not core then return false end
				for _, g in ipairs(rec.rig.glow or {}) do
					table.insert(rec.glows, {part = newGlow(g, rec, rec.scale), def = g})
				end
				collectPrimitives(rec)
				rec.built = true
				rec.fadeAt = os.clock() -- crossfade: the primitives fade out as the mesh fades in
				rec.visual = nil
			end
			if full and not rec.full and rec.alive then return buildFull(rec) end
			return true
		end)
		rec.pending = false
		if not ok or not complete then
			-- No core, or a partial rig: back to the primitives, retry later.
			if rec.built then release(rec) else releaseMeshes(rec) end
			rec.retryAt = os.clock() + 8
		end
		if not rec.alive then release(rec) end
	end)
end

-- Records -------------------------------------------------------------------
local forget
local function startDying(rec)
	if rec.dying then return end
	if not rec.built then forget(rec); return end -- QC L1: nothing drawn, nothing to dissolve
	rec.dying = true
	rec.deathAt = os.clock()
	rec.fadeOutAt = nil
	-- QC L2: a despawn (Despawn, or the host simply going without Dead / a
	-- killing blow: dismissed pets, companions) only fades; a death slumps.
	rec.slump = not rec.despawn and (rec.host:GetAttribute("Dead") == true or rec.killed == true)
	-- The primitives stay hidden: the server destroys the model right after Dead.
end
local function track(host)
	if records[host] then return end
	if not (host:IsA("Model") or host:IsA("BasePart")) then return end
	local kind = host:GetAttribute("CreatureRig")
	local rig = type(kind) == "string" and Catalog.rigs[kind]
	if not rig then rig = Catalog.rigs.blob; kind = "blob" end
	local root = rootOf(host)
	if not rig or not root then return end
	local scale = tonumber(host:GetAttribute("CreatureScale")) or 1
	if scale <= 0 or scale > 20 or scale ~= scale then scale = 1 end
	local rec = {host = host, root = root, rig = rig, kind = kind, scale = scale, tier = tierOf(host), tint = hex(host:GetAttribute("Color")),
		landmark = host:GetAttribute("CreatureLandmark") == true,
		meshes = {}, glows = {}, hidden = {}, connections = {}, alive = true, built = false, full = false, pending = false,
		gait = 0, speed = 0, acc = 0, flinchAt = -10, state = {}, out = {seg = {}}, lod = 0, phaseOffset = math.random() * 10}
	readAttrs(rec)
	if host:IsA("BasePart") then
		local floor = host:GetAttribute("CreatureFloor")
		local offset = if type(floor) == "number" then floor - host.Position.Y else nil
		rec.lift = Rules.hostLift(rig, host.Size.Y / 2, scale, offset)
	else
		rec.lift = 0
	end
	records[host] = rec
	table.insert(rec.connections, host.AttributeChanged:Connect(function(name)
		if TIER_ATTRS[name] then
			local tier = tierOf(host)
			if tier ~= rec.tier then
				rec.tier = tier
				if rec.built and not rec.dying then release(rec) end -- rebuilt with the new tier next pass
			end
			return
		end
		if not WATCHED[name] then return end
		local before, stance = rec.health, rec.stance
		readAttrs(rec)
		if (name == "Health" or name == "AddHealth") and before and rec.health and rec.health < before then rec.flinchAt = os.clock() end
		if name == "Dead" and host:GetAttribute("Dead") == true then startDying(rec) end
		if name == "Color" then
			-- QC M5: a recoloured creature is re-forged in its new colour.
			rec.tint = hex(host:GetAttribute("Color"))
			if rec.built and not rec.dying then release(rec) end
		elseif name == "LairStance" and rec.stance ~= stance and rec.full and not rec.dying then
			-- QC M5: the rune ring takes the new stance colour.
			for i = #rec.meshes, 1, -1 do
				local m = rec.meshes[i]
				if m.ring then forgeRelease(m.token); table.remove(rec.meshes, i) end
			end
			task.spawn(function() pcall(addRing, rec) end)
		end
	end))
	table.insert(rec.connections, host.AncestryChanged:Connect(function()
		if not host:IsDescendantOf(workspace) then startDying(rec) end
	end))
end
forget = function(rec)
	for _, c in ipairs(rec.connections) do c:Disconnect() end
	table.clear(rec.connections)
	rec.alive = false
	release(rec)
	if records[rec.host] == rec then records[rec.host] = nil end
end
local function untrack(host)
	local rec = records[host]
	if rec then startDying(rec) end
end
Creatures.track, Creatures.untrack, Creatures.retrack = track, untrack, retrack

-- LOD assignment (R.ASSIGN_SECONDS) -----------------------------------------
local function focus()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end
local order = {}
local function before(a, b)
	local pa, pb = Rules.priority(a.tier, a.landmark), Rules.priority(b.tier, b.landmark)
	if pa ~= pb then return pa > pb end
	return a.sortDistance < b.sortDistance
end
local function assign()
	local ok, value = pcall(function() return Theme ~= nil and Theme.reducedMotion(player) == true end)
	reduced = ok and value == true
	local now = os.clock()
	for host, at in pairs(retrack) do
		if now >= at then
			retrack[host] = nil
			if host.Parent and host:IsDescendantOf(workspace) then track(host) end
		end
	end
	local eye = focus()
	if not eye then return end
	table.clear(order)
	for host, rec in pairs(records) do
		if rec.dying then continue end
		if not host.Parent or not rec.root.Parent then startDying(rec); continue end
		rec.distance = (rec.root.Position - eye).Magnitude
		rec.sortDistance = Rules.capDistance(rec.distance, rec.built) -- QC M2 hysteresis
		rec.want = Rules.lod(rec.distance, rec.tier, mobile, rec.built)
		if rec.want > 0 then table.insert(order, rec) end
	end
	-- Bosses, then landmarks, creatures and pets; nearest first; R.cap() rigs.
	table.sort(order, before)
	local cap = Rules.cap(mobile)
	for i, rec in ipairs(order) do if i > cap then rec.want = 0 end end
	for _, rec in pairs(records) do
		if rec.dying or rec.pending or not rec.alive then continue end
		local want = rec.want or 0
		if want == 0 then
			-- QC L8: fade back to the primitives before releasing.
			if rec.built and not rec.fadeOutAt then rec.fadeOutAt = now end
		elseif rec.fadeOutAt then
			rec.fadeOutAt = nil -- wanted again: fade back in
			rec.fadeAt = now
		elseif not rec.built then
			if not rec.retryAt or now >= rec.retryAt then build(rec, want >= 2) end
		elseif want >= 2 and not rec.full then
			if not rec.retryAt or now >= rec.retryAt then build(rec, true) end
		elseif want == 1 and rec.full then
			releaseMeshes(rec, {core = true})
			rec.full = false
		end
		rec.lod = want
	end
end

-- Pose ------------------------------------------------------------------------
local parts, frames = {}, {}
local IDLE_SPEED = 0.25 -- studs/s below which a creature counts as standing
-- Rig-space CFrame -> creature scale (positions scale, rotations do not).
local function scaled(cf, scale)
	return CFrame.new(cf.Position * scale) * (cf - cf.Position)
end
local function pose(rec, dt, clock, serverNow)
	local rig, scale, state = rec.rig, rec.scale, rec.state
	local target
	if rec.dying and rec.visual then
		target = rec.visual -- the host is gone or going: dissolve where it fell
	else
		local cf = rec.root.CFrame
		target = if rec.lift ~= 0 then cf * CFrame.new(0, rec.lift, 0) else cf
		if rig.yaw then target *= CFrame.Angles(0, rig.yaw, 0) end
	end
	if not target then return 1 end -- dying before its first pose: nothing to dissolve
	-- Smooth the server's stepped root updates; snap after teleports.
	local visual = rec.visual
	if not visual or (visual.Position - target.Position).Magnitude > 12 * scale then
		visual = target
		rec.lastPos = target.Position
	else
		visual = visual:Lerp(target, 1 - math.exp(-dt * 14))
	end
	rec.visual = visual
	-- Walk speed from the distance the root covered (horizontal).
	local pos = target.Position
	local last = rec.lastPos or pos
	local moved = Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
	rec.lastPos = pos
	local v = if dt > 0 then moved / dt else 0
	local stride = (rig.stride or 2) * scale
	rec.speed += ((if v > IDLE_SPEED then math.clamp(v / (stride * 2.2), 0, 1) else 0) - rec.speed) * math.min(1, dt * 6)
	rec.gait = (rec.gait + moved / stride * math.pi) % (math.pi * 2)
	-- Attack / telegraph windows (server time), flinch, death.
	local windup, strike = 0, 0
	local phase, p = Rules.telegraphPhase(serverNow, rec.telegraphAt, rec.telegraphWindup)
	if phase == "windup" then windup = p elseif phase == "strike" then strike = Rules.pulse(p) end
	if strike == 0 then
		local lunge, q = Rules.lungePhase(serverNow, rec.attackAt)
		if lunge then strike = Rules.pulse(q) * 0.8 end
	end
	state.t = clock + (rec.phaseOffset or 0)
	state.gait, state.speed, state.windup, state.strike = rec.gait, rec.speed, windup, strike
	state.flinch = math.max(0, 1 - (clock - rec.flinchAt) / Rules.TIMING.FLINCH)
	state.reduced, state.defeated = reduced, rec.defeated
	local dissolve = 0
	if rec.dying then
		dissolve = math.clamp((clock - rec.deathAt) / (if reduced or not rec.slump then Rules.TIMING.DISSOLVE_REDUCED else Rules.TIMING.DISSOLVE), 0, 1)
		state.death = if reduced or not rec.slump then 0 else dissolve
	else
		state.death = 0
	end
	local out = Rules.pose(rig, state, rec.out)
	-- Crossfades (build / release) and the dissolve; Transparency only while it changes.
	local fade = 0
	if rec.fadeAt then
		fade = 1 - math.clamp((clock - rec.fadeAt) / Rules.TIMING.SPAWN, 0, 1)
		if fade <= 0 then rec.fadeAt = nil end
	end
	if rec.fadeOutAt then fade = math.max(fade, math.clamp((clock - rec.fadeOutAt) / Rules.TIMING.SPAWN, 0, 1)) end
	local alpha = math.max(fade, Rules.dissolve(dissolve, reduced or not rec.slump))
	local writeAlpha = rec.fadeAt ~= nil or rec.fadeOutAt ~= nil or rec.dying or rec.alphaWritten ~= alpha
	rec.alphaWritten = alpha
	if not rec.dying and (rec.fadeAt or rec.fadeOutAt or rec.primitiveLtm ~= 1) then setPrimitives(rec, 1 - fade) end
	local core = visual * scaled(out.core, scale)
	for _, m in ipairs(rec.meshes) do
		local cf
		if m.kind == "core" then
			cf = core * m.offset
		elseif m.kind == "seg" then
			local s = out.seg[m.index]
			if s then cf = visual * scaled(s, scale) * m.offset end
		elseif m.ground then
			cf = visual * scaled(m.at, scale) * m.offset
		else
			cf = core * scaled(m.at, scale) * m.offset
		end
		if cf then
			table.insert(parts, m.part)
			table.insert(frames, cf)
			if writeAlpha then m.part.Transparency = if m.ring then math.max(alpha, 0.15) else alpha end
		end
	end
	for _, g in ipairs(rec.glows) do
		local at = Rules.glowCFrame(g.def, state, out.core)
		table.insert(parts, g.part)
		table.insert(frames, visual * scaled(at, scale))
		if writeAlpha then g.part.Transparency = alpha end
	end
	if rec.fadeOutAt and fade >= 1 then return -1 end -- faded back to the primitives
	return dissolve
end

local function step(dt)
	table.clear(parts)
	table.clear(frames)
	local clock = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for host, rec in pairs(records) do
		if not rec.built then
			if rec.dying then forget(rec) end
			continue
		end
		rec.acc += dt
		local interval = if rec.dying or rec.lod >= 3 or rec.fadeAt or rec.fadeOutAt then 0 elseif rec.lod == 2 then 1 / Rules.LIMB_HZ else 1 / Rules.CORE_HZ
		if rec.acc >= interval then
			local elapsed = rec.acc
			rec.acc = 0
			local ok, result = pcall(pose, rec, math.min(elapsed, 0.25), clock, serverNow)
			if not ok then
				warn("[IsleCreatures] " .. tostring(result))
				forget(rec)
				retrack[host] = clock + 2 -- QC L1: try again shortly (the error may be transient)
			elseif result == -1 then
				release(rec)
			elseif rec.dying and result >= 1 then
				forget(rec)
			end
		end
	end
	if #parts > 0 then workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged) end
end
Creatures.step, Creatures.assign = step, assign

if CreatureTest then
	CreatureTest.creatures = Creatures
	return
end

for _, tag in ipairs({"IsleMonster", "IsleCreature"}) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(host) task.defer(track, host) end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)
	for _, host in ipairs(CollectionService:GetTagged(tag)) do track(host) end
end
local assignClock = 0
RunService:BindToRenderStep("IsleCreatures", Enum.RenderPriority.Camera.Value + 2, function(dt)
	assignClock += dt
	if assignClock >= Rules.ASSIGN_SECONDS then
		assignClock = 0
		local ok, problem = pcall(assign)
		if not ok then warn("[IsleCreatures] " .. tostring(problem)) end
	end
	step(dt)
end)
script.Destroying:Once(function()
	for _, rec in pairs(records) do forget(rec) end
end)
