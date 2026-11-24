-- Creature visuals (docs/DEPTH-CONTRACT.md §48): pure rules shared by
-- creatures.client.lua (the renderer) and verify-creatures.luau. The rig
-- geometry (core, limbs, pivots, glow accents, anchors) is generated into
-- art/CreatureCatalog.lua (ReplicatedStorage.AetherCreatureArt) from
-- art/creature-shapes.cjs; this module holds what is not geometry: tiers and
-- their overlays, level of detail, animation timings and the per-frame pose.
--
-- Nothing here is authoritative. The server (combat.server.lua and friends)
-- owns position, health, attacks and telegraphs; the renderer only reads the
-- attributes it already publishes:
--   CreatureRig (body kind), CreatureScale, Color, Level, Boss, WorldBoss,
--   Lair, Raid, Superior, Health, Dead, AttackAt (server time of a monster's
--   hit), TelegraphAt / TelegraphWindup / TelegraphKind (boss telegraphs),
--   LairStance, VisualState, AddHealth.
-- Pose functions write into caller-owned tables and allocate no tables per
-- frame (CFrames are value types).
local R = {}

-- Tiers -----------------------------------------------------------------------
-- critter < brute < elite < boss < world. A tier-1 critter and a world boss
-- must read differently at a glance: size (CreatureScale), overlays, eye colour,
-- the ground rune ring and the glow budget all step up with the tier.
R.TIERS = {"critter", "brute", "elite", "boss", "world", "pet"}
R.RANK = {critter = 1, brute = 2, elite = 3, boss = 4, world = 5, pet = 0}
R.BRUTE_LEVEL = 25
R.ELITE_LEVEL = 60
-- attrs: any table or Instance-like getter result with the server attributes.
function R.tier(attrs)
	if type(attrs) ~= "table" then return "critter" end
	if type(attrs.CreatureTier) == "string" and R.RANK[attrs.CreatureTier] then return attrs.CreatureTier end
	if attrs.Pet == true then return "pet" end
	if attrs.WorldBoss == true then return "world" end
	if attrs.Boss == true or (type(attrs.Lair) == "string" and attrs.Lair ~= "") then return "boss" end
	local level = tonumber(attrs.Level) or 0
	if attrs.Superior == true or level >= R.ELITE_LEVEL then return "elite" end
	if level >= R.BRUTE_LEVEL then return "brute" end
	return "critter"
end
-- Overlay sets per tier (phones carry fewer).
R.OVERLAYS = {
	critter = {}, pet = {},
	brute = {"pauldron"},
	elite = {"pauldron", "horns"},
	boss = {"pauldron", "crown", "ring"},
	world = {"pauldron", "worldcrown", "ring"},
}
R.PHONE_OVERLAYS = {critter = {}, pet = {}, brute = {}, elite = {"horns"}, boss = {"crown", "ring"}, world = {"worldcrown", "ring"}}
R.OVERLAY_SHAPES = {pauldron = "OverlayPauldron", horns = "OverlayHorns", crown = "OverlayCrown", worldcrown = "OverlayWorldCrown", ring = "OverlayRuneRing"}
-- Fixed overlay tints (few templates): steel pauldrons, bone horns; crowns and
-- the ring take the tier colour, the ring a lair boss's stance colour.
R.OVERLAY_TINT = {pauldron = "B0B8C4", horns = "EDE2C4"}
R.TIER_COLOR = {boss = "FF3B3B", world = "FFD166"}
R.STANCE_COLOR = {melee = "FF786E", ranged = "96E178", magic = "8CAAFF"}
-- Eyes: bosses glare red, world bosses burn gold; everything else keeps its own.
R.EYE_OVERRIDE = {boss = "FF3B3B", world = "FFD166"}
-- Overlay size from the rig's largest hitbox side (rig units, before scale).
function R.overlayScale(overlay, rig)
	local h = rig.hitbox or {3, 3, 3}
	local size = math.max(h[1], h[2], h[3])
	if overlay == "pauldron" then return 0.5 + size * 0.12 end
	if overlay == "horns" then return 0.6 + size * 0.1 end
	return 0.5 + size * 0.1
end
function R.overlays(tier, mobile)
	local list = (if mobile then R.PHONE_OVERLAYS else R.OVERLAYS)[tier]
	return list or {}
end

-- Level of detail ---------------------------------------------------------------
-- lod 3 full rig every frame, 2 full rig at LIMB_HZ, 1 core only at CORE_HZ,
-- 0 nothing (the server's primitive stays). Bosses reach further; at most CAP
-- creatures hold a rig (nearest first, bosses before others).
R.LOD = {
	desktop = {full = 70, limbs = 150, core = 260, cap = 24},
	phone = {full = 40, limbs = 90, core = 150, cap = 10},
}
R.TIER_RANGE = {critter = 1, pet = 0.8, brute = 1.1, elite = 1.2, boss = 1.7, world = 2.6}
R.LIMB_HZ = 15
R.CORE_HZ = 8
R.ASSIGN_SECONDS = 0.25
R.RELEASE_MARGIN = 1.15 -- hysteresis: an existing rig is kept until this × the range
function R.lod(distance, tier, mobile, built)
	local L = if mobile then R.LOD.phone else R.LOD.desktop
	local k = (R.TIER_RANGE[tier] or 1) * (if built then R.RELEASE_MARGIN else 1)
	if distance <= L.full * k then return 3 end
	if distance <= L.limbs * k then return 2 end
	if distance <= L.core * k then return 1 end
	return 0
end
function R.cap(mobile) return if mobile then R.LOD.phone.cap else R.LOD.desktop.cap end
-- Forge budget for creature templates: the MeshForge keeps creature templates
-- in their own pool (forge.client.lua CREATURE_TEMPLATE_CAP / _TRIANGLE_CAP),
-- beside the world's LIMITS, evicting idle ones least recently used first.
R.TEMPLATE_CAP = {desktop = 22, phone = 8}
-- A full rig's meshes: the core, its limb segments and overlays.
function R.rigMeshes(rig, tier, mobile)
	return 1 + #(rig.segs or {}) + #R.overlays(tier, mobile) + (if table.find(R.overlays(tier, mobile), "pauldron") then 1 else 0)
end

-- Timings -------------------------------------------------------------------
-- LUNGE matches the server's monster lunge (combat.server.lua: r.lungeUntil =
-- now + 0.25): a monster's hit lands at AttackAt and the client plays its bite
-- / swipe over the same window. Boss telegraphs: the windup pose fills exactly
-- [TelegraphAt - windup, TelegraphAt) and the slam starts at TelegraphAt, the
-- moment the server resolves the strike.
R.TIMING = {
	LUNGE = 0.25,
	STRIKE = 0.32,     -- slam after a telegraph resolves
	FLINCH = 0.28,
	DISSOLVE = 0.9,
	DISSOLVE_REDUCED = 0.4,
	MIN_WINDUP = 0.6,  -- shorter telegraphs still read (the windup is the window itself)
	SPAWN = 0.45,      -- fade-in when a rig is built
}
-- Attack phase at server time `now` for a telegraph resolving at `at` after
-- `windup` seconds: "windup" (progress 0..1), "strike" (0..1) or nil.
function R.telegraphPhase(now, at, windup)
	if type(at) ~= "number" or type(windup) ~= "number" or windup <= 0 then return nil, 0 end
	local start = at - windup
	if now >= start and now < at then return "windup", math.clamp((now - start) / windup, 0, 1) end
	if now >= at and now < at + R.TIMING.STRIKE then return "strike", math.clamp((now - at) / R.TIMING.STRIKE, 0, 1) end
	return nil, 0
end
-- A monster's ordinary hit (no telegraph): a quick anticipation then the bite,
-- peaking a third of the way through the server's lunge window.
function R.lungePhase(now, at)
	if type(at) ~= "number" then return nil, 0 end
	if now >= at and now < at + R.TIMING.LUNGE then return "strike", math.clamp((now - at) / R.TIMING.LUNGE, 0, 1) end
	return nil, 0
end
local function ease(x) return x * x * (3 - 2 * x) end
R.ease = ease
-- Strike pulse: rises fast, peaks at 1/3, settles by the end.
function R.pulse(p)
	if p <= 0 or p >= 1 then return 0 end
	if p < 1 / 3 then return ease(p * 3) end
	return ease(1 - (p - 1 / 3) * 1.5)
end

-- Gaits -------------------------------------------------------------------------
-- amp: leg swing (radians at full speed); bob: body bob (fraction of stride).
R.GAIT = {
	quad = {amp = 0.55, bob = 0.035, arm = 0.35},
	biped = {amp = 0.45, bob = 0.03, arm = 0.4, sway = 0.035},
	hex = {amp = 0.35, bob = 0.015, lift = 0.25},
	octo = {amp = 0.3, bob = 0.012, lift = 0.22},
	roots = {amp = 0.35, bob = 0.03},
	hop = {amp = 0, bob = 0.18},
	slither = {amp = 0, bob = 0.01, wave = 0.35},
	fly = {amp = 0, bob = 0},
	glide = {amp = 0, bob = 0},
	float = {amp = 0, bob = 0},
}
R.FLYING = {fly = true, glide = true, float = true}

-- Pose ----------------------------------------------------------------------------
-- state: {t (seconds), gait (radians, advanced by distance walked), speed (0..1),
--   windup (0..1), strike (0..1 pulse), flinch (0..1), death (0..1), defeated
--   (bool), reduced (bool), lod}
-- out: {core = CFrame, seg = {CFrame...}} in rig space (unscaled; the renderer
-- multiplies positions by CreatureScale). A segment's CFrame already contains
-- its rest rotation and mirror; the mesh offset (template centre × k) is the
-- renderer's. Legs follow the core's height but not its pitch, so a rearing
-- boss stays planted; everything else rides the core.
local MIRROR = {roll = CFrame.Angles(0, 0, math.pi), yaw = CFrame.Angles(0, math.pi, 0)}
R.MIRROR = MIRROR
-- Rest CFrame of a segment (no animation): T(at) * R(rot) * mirror.
function R.rest(seg)
	local at, rot = seg.at, seg.rot
	local cf = CFrame.new(at[1], at[2], at[3])
	if rot then cf *= CFrame.fromEulerAnglesYXZ(rot[1], rot[2], rot[3]) end
	if seg.mirror and MIRROR[seg.mirror] then cf *= MIRROR[seg.mirror] end
	return cf
end
-- Rotation-only rest frame of a segment, cached on the (generated) seg table.
function R.restRot(seg)
	local cached = seg.restRot
	if cached then return cached end
	local rest = R.rest(seg)
	cached = rest - rest.Position
	seg.restRot = cached
	return cached
end
local IDENT = CFrame.new()
local LEG = {legA = 0, legB = math.pi}
local ARM = {armA = math.pi, armB = 0, arm = 0}
function R.pose(rig, state, out)
	local gaitDef = R.GAIT[rig.gait] or R.GAIT.quad
	local t, phase, speed = state.t or 0, state.gait or 0, math.clamp(state.speed or 0, 0, 1)
	local reduced = state.reduced == true
	local calm = if reduced then 0 else 1
	local w, s, f, d = ease(math.clamp(state.windup or 0, 0, 1)), math.clamp(state.strike or 0, 0, 1), math.clamp(state.flinch or 0, 0, 1), math.clamp(state.death or 0, 0, 1)
	local stride = rig.stride or 2
	local breath = (rig.breath or 0.05) * calm
	local hip = rig.hip or 2
	-- Core: breathing, gait bob and sway, the telegraph rear-back, the strike
	-- lunge, the hit flinch, and the death slump.
	local y = math.sin(t * 1.7) * breath
	local bob = 0
	if gaitDef.bob > 0 then
		bob = math.abs(math.sin(phase)) * gaitDef.bob * stride * speed
		if rig.gait == "hop" then bob = math.max(0, math.sin(phase)) * gaitDef.bob * stride * math.max(speed, 0.15 * calm) end
	end
	y += bob
	local pitch = -0.32 * w + 0.3 * s - 0.14 * f
	local z = 0.22 * w * stride * 0.3 - 0.38 * s * stride * 0.3 + 0.18 * f
	y += 0.2 * w * hip * 0.25
	local roll = 0
	if gaitDef.sway then roll = math.sin(phase) * gaitDef.sway * speed end
	if rig.gait == "slither" then roll += math.sin(t * 3) * 0.03 * calm end
	if state.defeated then pitch += 0.35; y -= hip * 0.25; roll += 0.12 end
	if d > 0 then pitch += 0.45 * d; roll += 0.25 * d; y -= hip * 0.45 * d end
	local pulse = 0
	if rig.pulse and not reduced then pulse = math.sin(t * 2.4) * 0.04 end
	out.core = CFrame.new(0, y + pulse, z) * CFrame.Angles(pitch, 0, roll)
	out.pulse = 1 + pulse
	out.seg = out.seg or {}
	local legsY = y
	local flap = rig.flap or 4
	for i, seg in ipairs(rig.segs or {}) do
		local rot = R.restRot(seg)
		local at = seg.at
		local side = if at[1] < 0 then -1 else 1
		local role = seg.role
		local segPhase = seg.phase or 0
		local cf
		if LEG[role] then
			local p = phase + LEG[role]
			local gait = rig.gait
			local swing
			if gait == "hex" or gait == "octo" then
				-- Sideways legs sweep fore and aft (yaw) and lift on the return.
				local lift = math.max(0, math.cos(p)) * (gaitDef.lift or 0.2) * speed
				swing = CFrame.Angles(0, math.sin(p) * gaitDef.amp * speed, side * lift)
			else
				swing = CFrame.Angles(math.sin(p) * gaitDef.amp * speed + 0.12 * w, 0, 0)
			end
			cf = CFrame.new(at[1], at[2] + legsY, at[3]) * swing * rot
		elseif role == "tuck" then
			cf = out.core * CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(math.sin(t * 1.3) * 0.08 * calm, 0, 0) * rot
		else
			local anim
			if ARM[role] then
				local swing = -math.sin(phase + ARM[role]) * (gaitDef.arm or 0.3) * speed
				local idle = math.sin(t * 1.3 + side) * 0.05 * calm
				anim = CFrame.Angles(swing + idle - 1.5 * w + 1.9 * s - 0.25 * f, 0, side * 0.08 * w)
			elseif role == "wing" then
				local rate = flap * (1 + 0.35 * speed)
				local amp = if rig.gait == "glide" then 0.32 else 0.55
				if reduced then amp *= 0.3; rate *= 0.5 end
				local a = math.sin(t * rate + segPhase) * amp + 0.6 * w - 0.5 * s
				anim = CFrame.Angles(0, 0, side * a)
			elseif role == "tail" then
				anim = CFrame.Angles(0, math.sin(t * 2.2 + segPhase) * 0.3 * (0.4 + speed) * (if reduced then 0.4 else 1) + 0.25 * w * side, 0)
			elseif role == "tendril" then
				anim = CFrame.Angles(math.sin(t * 1.8 + segPhase) * 0.16 * calm, 0, math.cos(t * 1.5 + segPhase) * 0.16 * calm)
			elseif role == "claw" then
				anim = CFrame.Angles(math.sin(t * 1.5 + side) * 0.06 * calm - 0.7 * w + 0.9 * s, 0, 0)
			elseif role == "coil" then
				local wave = (gaitDef.wave or 0.3) * (0.35 + speed)
				if reduced then wave *= 0.4 end
				local x = math.sin(t * 3 - segPhase * 0.9) * wave
				local ry = math.cos(t * 3 - segPhase * 0.9) * wave * 0.5
				anim = CFrame.new(x, math.sin(t * 2 - segPhase) * 0.06 * calm, 0) * CFrame.Angles(0, ry, 0)
			elseif role == "orbit" then
				local a = if reduced then 0 else t * 1.1
				local spin = if reduced then 0 else t * 2
				-- Orbit about the core's vertical axis: rotate the rest position.
				cf = out.core * CFrame.Angles(0, a + 0.8 * w, 0) * CFrame.new(at[1], at[2] + math.sin(t * 1.7 + segPhase) * 0.15 * calm, at[3]) * CFrame.Angles(0, spin, 0) * rot
			else
				anim = IDENT
			end
			if not cf then cf = out.core * CFrame.new(at[1], at[2], at[3]) * anim * rot end
		end
		out.seg[i] = cf
	end
	return out
end

-- Glow accents: their pose rides the core; orbiting motes circle it.
function R.glowCFrame(g, state, core)
	local at = g.at
	if g.orbit and g.orbit > 0 and not state.reduced then
		return core * CFrame.Angles(0, (state.t or 0) * g.orbit, 0) * CFrame.new(at[1], at[2], at[3])
	end
	return core * CFrame.new(at[1], at[2], at[3])
end

-- Dissolve: transparency for a dying rig at progress p (0..1).
function R.dissolve(p, reduced)
	return math.clamp(if reduced then p else p * p * (3 - 2 * p), 0, 1)
end

-- Ground placement for creature host parts (not combat models): flying rigs
-- centre on the host, ground rigs stand their feet on CreatureFloor or the
-- host's bottom face. Returns the rig origin's height above the host centre.
function R.hostLift(rig, hostHalfHeight, scale, floorOffset)
	if R.FLYING[rig.gait] then return 0 end
	local base = if type(floorOffset) == "number" then floorOffset else -hostHalfHeight
	return base + (rig.hip or 2) * scale
end

-- Pets: Data.PetDepth body forms -> rigs.
R.PET_RIGS = {flyer = "pet_flyer", quad = "pet_quad", shell = "pet_shell", hopper = "pet_hopper", float = "pet_float"}
-- Uniform scale that fits a rig's hitbox into a host box (largest side).
function R.fitScale(rig, box)
	local h = rig.hitbox or {3, 3, 3}
	return math.min(box.X / h[1], box.Y / h[2], box.Z / h[3])
end

return R
