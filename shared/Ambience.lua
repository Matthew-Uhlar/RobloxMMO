--!nocheck
-- Aether Isles ambience rules (ReplicatedStorage.AetherAmbience).
-- docs/DEPTH-CONTRACT.md §50. Pure rules, no instances and no requires: the
-- client ambience layer (ambience.client.lua, StarterPlayerScripts.IsleAmbience)
-- and the weather clock (weather.server.lua, ServerScriptService.Weather) feed it
-- the time, the player's context key (shared/LightingProfiles.lua L.context)
-- and the graphics tier; verify-ambience.luau exercises every function here.
--
--   A.Budgets[key] / A.budgetKey(tier, mobile) / A.budget(tier, mobile)
--                              per-tier caps (emitters, parts, sway, radii, ...)
--   A.partPlan(b) / A.emitterPlan(b)   what the layer may create on a tier
--   A.Regions[key]             motes, wind, cold, fireflies, weather weights
--   A.windDir(t) / A.gust(t, x, z) / A.windAt(t, x, z, base, weather)
--                              the wind field: a slowly veering direction and
--                              gust fronts that travel across the archipelago
--   A.SWAY[shape]              which forged props sway, and how
--   A.slotAt(t) / A.weatherAt(slot, key) / A.schedule(slot) / A.strikes(slot, key)
--                              the deterministic weather schedule
--   A.encode(slot, strikeRegion, strikeAt)   the IsleWeather attribute
--   A.SPARKS[fx] / A.sparkFor(fx, tint)      hit sparks per node material
--   A.beamFor(rarity, Data)    rare-drop pillar (Data.Rarity colours)
--   A.orbCount(amount, b)      XP orbs per gain
local A = {}
A.VERSION = 1

------------------------------------------------------------------------------
-- Budgets. Keys: the §35 graphics tiers plus "Lite", the phone set (a touch
-- device on High or Balanced). Every numeric cap is monotonic
-- High >= Balanced >= Lite >= Performance (verify-ambience).
--   emitters      ParticleEmitters the layer may have enabled at once
--   rateScale     multiplier on every preset's Rate
--   parts         local parts the layer may create (pools are sized from it)
--   sway / swayHz / swayRadius   swayed meshes, update rate, cull radius
--   sourceRadius  embers / spores / sparks / fishing shimmer sources
--   sources       pooled source emitters
--   waterRadius   foam rings and waterfall extras
--   foam          foam segments (island surf + pond rims)
--   falls         waterfalls given a sheet + spray
--   clouds        under-island cloud-sea layers
--   birds / flocks   boid critters around landmarks (birds by day, butterflies)
--   orbs / beams  XP orbs and rare-drop pillars
--   rain          rain / snow particles per second (before rateScale)
--   splashes      ground splash emitter under rain
--   fog           fog-bank puffs per second
--   bolts         visible lightning bolts (flash is the director's)
------------------------------------------------------------------------------
A.TIER_ORDER = {"High", "Balanced", "Lite", "Performance"}
A.Budgets = {
	High = {emitters = 24, rateScale = 1, parts = 220, sway = 160, swayHz = 30, swayRadius = 220, sourceRadius = 160, sources = 8,
		waterRadius = 420, foam = 96, falls = 6, clouds = 3, birds = 24, flocks = 3, orbs = 8, beams = 3, rain = 420, splashes = 1, fog = 4, bolts = 1},
	Balanced = {emitters = 14, rateScale = 0.6, parts = 140, sway = 90, swayHz = 20, swayRadius = 160, sourceRadius = 120, sources = 5,
		waterRadius = 300, foam = 56, falls = 4, clouds = 2, birds = 12, flocks = 2, orbs = 6, beams = 2, rain = 260, splashes = 1, fog = 3, bolts = 1},
	Lite = {emitters = 9, rateScale = 0.4, parts = 80, sway = 40, swayHz = 15, swayRadius = 110, sourceRadius = 80, sources = 3,
		waterRadius = 180, foam = 28, falls = 2, clouds = 1, birds = 6, flocks = 1, orbs = 4, beams = 2, rain = 160, splashes = 0, fog = 2, bolts = 0},
	Performance = {emitters = 5, rateScale = 0.25, parts = 40, sway = 16, swayHz = 10, swayRadius = 70, sourceRadius = 60, sources = 1,
		waterRadius = 120, foam = 0, falls = 1, clouds = 1, birds = 0, flocks = 0, orbs = 3, beams = 1, rain = 90, splashes = 0, fog = 0, bolts = 0},
}
function A.budgetKey(tier, mobile)
	if tier == "Performance" then return "Performance" end
	if mobile then return "Lite" end
	return if A.Budgets[tier] then tier else "High"
end
function A.budget(tier, mobile) return A.Budgets[A.budgetKey(tier, mobile)] end
-- Fixed emitters the layer owns (camera-anchored), before pooled sources.
A.FIXED_EMITTERS = {"motes", "fireflies", "rain", "splash", "fog", "leaves"}
-- Parts the layer creates on a budget (anchors: air, sky, ground, fog; the
-- burst host; the level-up ring; cloud layers; foam; birds; orbs; beams (2
-- parts each: core + halo); bolts (6 segments each)). Source emitters ride on
-- Attachments under the world parts they decorate (no part of their own).
A.BOLT_SEGMENTS = 6
function A.partPlan(b)
	local plan = {anchors = 4, burst = 1, ring = 1, clouds = b.clouds, foam = b.foam, birds = b.birds, orbs = b.orbs, beams = b.beams * 2,
		bolts = b.bolts * A.BOLT_SEGMENTS}
	local total = 0
	for _, n in pairs(plan) do total += n end
	return plan, total
end
-- Continuous emitters that can be enabled at once: the fixed set (only those
-- the tier uses), one per pooled source and one spray per waterfall extra.
-- Burst emitters (sparks, chips, glitter) stay disabled and only :Emit().
function A.emitterPlan(b)
	local fixed = 2 -- motes + leaves (fireflies replace leaves at night)
	fixed += 1 -- rain or snow
	if b.splashes > 0 then fixed += 1 end
	if b.fog > 0 then fixed += 1 end
	local plan = {fixed = fixed, sources = b.sources, falls = b.falls}
	local total = 0
	for _, n in pairs(plan) do total += n end
	return plan, total
end

------------------------------------------------------------------------------
-- Particle presets (colours as hex; the client builds ColorSequences once).
------------------------------------------------------------------------------
A.SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
A.SMOKE = "rbxasset://textures/particles/smoke_main.dds"
A.Presets = {
	pollen = {colors = {"FFF3B0", "FFE08A"}, size = 0.16, life = {6, 10}, speed = {0.2, 0.6}, rate = 14, light = 0.4, drift = 0.6, texture = "sparkle"},
	dust = {colors = {"F2D7A6", "D9B27A"}, size = 0.14, life = {5, 9}, speed = {0.2, 0.5}, rate = 12, light = 0.2, drift = 0.5, texture = "sparkle"},
	leaves = {colors = {"8DB46C", "C9A548"}, size = 0.32, life = {5, 8}, speed = {1, 2}, rate = 4, light = 0, drift = 1.2, texture = "smoke", spin = 120},
	frost = {colors = {"EAF6FF", "BFE3FF"}, size = 0.12, life = {6, 10}, speed = {0.2, 0.5}, rate = 16, light = 0.6, drift = 0.5, texture = "sparkle"},
	spores = {colors = {"B79CFF", "7FE6C8"}, size = 0.22, life = {7, 12}, speed = {0.1, 0.35}, rate = 12, light = 0.8, drift = 0.3, texture = "sparkle", rise = 0.25},
	spray = {colors = {"E6FAFF", "9FE3F0"}, size = 0.14, life = {4, 7}, speed = {0.3, 0.7}, rate = 12, light = 0.5, drift = 0.7, texture = "sparkle"},
	void = {colors = {"C08CFF", "6FE0FF"}, size = 0.16, life = {2, 4}, speed = {0.6, 1.4}, rate = 10, light = 1, drift = 0.8, texture = "sparkle"},
	embers = {colors = {"FFB347", "FF6A2A"}, size = 0.14, life = {1.2, 2.4}, speed = {2, 4}, rate = 10, light = 1, drift = 0.4, texture = "sparkle", rise = 2.5},
	shimmer = {colors = {"FFFFFF", "B8F2FF"}, size = 0.3, life = {0.6, 1.2}, speed = {0, 0.2}, rate = 6, light = 1, drift = 0, texture = "sparkle"},
	fireflies = {colors = {"E8FF8A", "B8FF6A"}, size = 0.2, life = {4, 7}, speed = {0.2, 0.6}, rate = 8, light = 1, drift = 0.3, texture = "sparkle"},
	rain = {colors = {"C8DCF0", "A8C4E0"}, size = 0.1, life = {0.7, 0.9}, speed = {70, 80}, rate = 1, light = 0, drift = 0, texture = "sparkle", streak = true},
	snow = {colors = {"FFFFFF", "E4F0FF"}, size = 0.22, life = {5, 7}, speed = {5, 7}, rate = 0.5, light = 0.3, drift = 1.4, texture = "sparkle", spin = 90},
	splash = {colors = {"D8E8F8", "B0CCE8"}, size = 0.18, life = {0.15, 0.3}, speed = {2, 4}, rate = 60, light = 0, drift = 0, texture = "sparkle"},
	fog = {colors = {"DDE4EC", "C4CED8"}, size = 26, life = {14, 20}, speed = {0.5, 1.2}, rate = 1, light = 0, drift = 0.6, texture = "smoke", transparency = 0.86},
	motes = {colors = {"FFE9B0", "FFF6D8"}, size = 0.16, life = {5, 9}, speed = {0.2, 0.6}, rate = 10, light = 0.5, drift = 0.5, texture = "sparkle"},
	wind = {colors = {"E6F4FF", "FFFFFF"}, size = 0.1, life = {1.2, 2}, speed = {4, 7}, rate = 8, light = 0.3, drift = 2.5, texture = "sparkle", streak = true},
	glints = {colors = {"F2D27A", "FFF1B8"}, size = 0.16, life = {3, 6}, speed = {0.2, 0.8}, rate = 8, light = 1, drift = 0.4, texture = "sparkle", rise = 0.4},
	mist = {colors = {"EAF8FF", "CFEFFF"}, size = 3, life = {1.5, 2.5}, speed = {2, 5}, rate = 6, light = 0.2, drift = 0.5, texture = "smoke", transparency = 0.7},
}
-- A preset's rate on a budget (0 when the tier cannot afford the emitter).
function A.rateFor(name, b, base)
	local p = A.Presets[name]
	if not p then return 0 end
	return (base or p.rate) * b.rateScale
end

------------------------------------------------------------------------------
-- Regions (keys of L.Profiles). weather: relative weights of the states this
-- region can roll (A.weatherAt); cold regions roll Snow instead of Rain.
------------------------------------------------------------------------------
A.Regions = {
	Hub = {motes = "pollen", wind = 0.6, fireflies = true, weather = {Clear = 6, Breezy = 3, Rain = 2, Fog = 1}},
	Meadow = {motes = "pollen", wind = 0.8, fireflies = true, butterflies = true, weather = {Clear = 5, Breezy = 3, Rain = 2, Storm = 0.5, Fog = 1}},
	Quarry = {motes = "dust", wind = 0.7, weather = {Clear = 6, Breezy = 3, Rain = 1, Fog = 1}},
	Skyreach = {motes = "frost", wind = 1.2, cold = true, weather = {Clear = 4, Breezy = 3, Snow = 3, Fog = 1}},
	Windpine = {motes = "leaves", wind = 1.1, fireflies = true, weather = {Clear = 4, Breezy = 4, Rain = 2, Fog = 2}},
	Gloomhollow = {motes = "spores", wind = 0.3, weather = {Clear = 3, Fog = 4, Rain = 1}},
	Tidewater = {motes = "spray", wind = 1, fireflies = true, weather = {Clear = 4, Breezy = 3, Rain = 3, Storm = 1, Fog = 2}},
	Tempest = {motes = "void", wind = 1.5, weather = {Storm = 6, Rain = 2, Breezy = 2}},
	ShatteredCrown = {motes = "void", wind = 0.9, weather = {Clear = 3, Fog = 3, Storm = 2}},
	Home = {motes = "pollen", wind = 0.7, fireflies = true, butterflies = true, weather = {Clear = 6, Breezy = 3, Rain = 2, Fog = 1}},
	Skyways = {motes = "pollen", wind = 1, weather = {Clear = 5, Breezy = 4, Rain = 1}},
}
A.WEATHER_KEYS = {"Hub", "Meadow", "Quarry", "Skyreach", "Windpine", "Gloomhollow", "Tidewater", "Tempest", "ShatteredCrown", "Home", "Skyways"}
A.CLOUD_TINT = {Gloomhollow = "8C7CB8", Tempest = "8E98A8", ShatteredCrown = "B8A8D8", Quarry = "E8DCC8"}
A.CLOUD_DAY, A.CLOUD_NIGHT = "F4F8FF", "3A4466"

------------------------------------------------------------------------------
-- Wind. Direction veers slowly; gust fronts are travelling waves along it
-- (speed A.GUST_SPEED studs/s, spacing A.GUST_LENGTH), so a gust visibly rolls
-- across an island, then the next one. Pure numbers: no tables per call.
------------------------------------------------------------------------------
A.GUST_SPEED, A.GUST_LENGTH, A.GUST_SHARPNESS = 26, 240, 6
A.WEATHER_WIND = {Clear = 1, Breezy = 1.8, Rain = 1.4, Storm = 2.4, Fog = 0.6, Snow = 1.2}
function A.windDir(t)
	local a = 0.6 + 0.45 * math.sin(t / 97) + 0.2 * math.sin(t / 41)
	return math.cos(a), math.sin(a)
end
-- dx, dz: A.windDir(t), computed once per frame by the caller (QC M6).
function A.gustDir(t, x, z, dx, dz)
	local along = x * dx + z * dz
	local p1 = math.sin(2 * math.pi * (along - A.GUST_SPEED * t) / A.GUST_LENGTH)
	local p2 = math.sin(2 * math.pi * (along * 0.61 - A.GUST_SPEED * 0.8 * t) / (A.GUST_LENGTH * 1.7) + 1.3)
	local g1 = if p1 > 0 then p1 ^ A.GUST_SHARPNESS else 0
	local g2 = if p2 > 0 then p2 ^ A.GUST_SHARPNESS else 0
	return math.min(1, g1 + 0.6 * g2)
end
function A.gust(t, x, z)
	local dx, dz = A.windDir(t)
	return A.gustDir(t, x, z, dx, dz)
end
-- Wind strength at a point: region base x weather, plus up to +80% in a gust.
function A.windAtDir(t, x, z, base, weather, dx, dz)
	return (base or 1) * (A.WEATHER_WIND[weather] or 1) * (0.55 + 0.8 * A.gustDir(t, x, z, dx, dz))
end
function A.windAt(t, x, z, base, weather)
	local dx, dz = A.windDir(t)
	return A.windAtDir(t, x, z, base, weather, dx, dz)
end

------------------------------------------------------------------------------
-- Sway (vertex-free: the forged clone's CFrame rotates about a pivot).
-- mode tree / bush / crop: pivot at the base, lean with the wind plus a small
-- sway; banner: pivot at the top, flutter; lantern: pendulum from the top.
-- amp in radians at wind 1; freq in Hz. Spinning sails (RegionSpin) and
-- anything the server moves are excluded.
------------------------------------------------------------------------------
A.SWAY = {
	MeadowTree = {mode = "tree", amp = 0.022, freq = 0.35}, CanopyTree = {mode = "tree", amp = 0.018, freq = 0.3},
	PalmTree = {mode = "tree", amp = 0.035, freq = 0.4}, WindpineTree = {mode = "tree", amp = 0.02, freq = 0.32},
	PineTree = {mode = "tree", amp = 0.02, freq = 0.32}, WindpineCrown = {mode = "tree", amp = 0.025, freq = 0.34},
	EmberoakTree = {mode = "tree", amp = 0.016, freq = 0.28}, GlimmerbarkTree = {mode = "tree", amp = 0.02, freq = 0.33},
	StarwoodTree = {mode = "tree", amp = 0.018, freq = 0.3}, AetherheartTree = {mode = "tree", amp = 0.01, freq = 0.22},
	Bush = {mode = "bush", amp = 0.045, freq = 0.7}, FlowerPatch = {mode = "bush", amp = 0.06, freq = 0.9},
	SwarmBloom = {mode = "bush", amp = 0.05, freq = 0.8}, Moonbloom = {mode = "bush", amp = 0.05, freq = 0.75},
	CoralFan = {mode = "bush", amp = 0.035, freq = 0.5},
	CropWheat = {mode = "crop", amp = 0.09, freq = 1.1}, CropSheaf = {mode = "crop", amp = 0.07, freq = 1}, CropBush = {mode = "crop", amp = 0.05, freq = 0.9},
	CropBloom = {mode = "crop", amp = 0.07, freq = 1}, CropGlowcap = {mode = "crop", amp = 0.03, freq = 0.6},
	CropBed = {mode = "crop", amp = 0.05, freq = 0.9}, -- a crop slot whose resource has no shape of its own
	Banner = {mode = "banner", amp = 0.11, freq = 1.6},
	HangingLantern = {mode = "lantern", amp = 0.05, freq = 0.55},
}
-- Only the forge's local MeshPart clones sway (QC M1): server parts (herb
-- tufts, colliders) are never moved. A host tagged NO_SWAY_TAG, carrying
-- SpinRate, or unanchored (something else moves it) never sways (QC M3).
A.NO_SWAY_TAG = "RegionSpin"
-- Angles (radians) for one swayer: lean (about the axis across the wind) and
-- twist (about the up axis, banners only). `phase` is per prop.
function A.swayAngles(def, t, wind, phase, reduced)
	if reduced or not def then return 0, 0 end
	local amp, w = def.amp, 2 * math.pi * def.freq
	if def.mode == "banner" then
		local flutter = math.sin(w * t + phase) + 0.35 * math.sin(2.7 * w * t + phase * 1.7)
		return amp * (0.4 + 0.6 * wind) * flutter * 0.6 + amp * 0.5 * wind, amp * 0.4 * wind * math.sin(1.3 * w * t + phase)
	elseif def.mode == "lantern" then
		return amp * wind * math.sin(w * t + phase), 0
	end
	-- tree / bush / crop / grass: a lean with the wind plus a sway around it.
	return amp * (0.55 * wind + 0.45 * wind * math.sin(w * t + phase)), 0
end

------------------------------------------------------------------------------
-- Weather schedule. A slot is A.SLOT seconds of server time; every region
-- rolls its state from (slot, region index) with a fixed integer hash, so the
-- server and every client agree with no randomness. The server publishes the
-- slot's table and each lightning strike in ONE workspace attribute.
------------------------------------------------------------------------------
A.SLOT = 480
A.EPOCH = 1577836800 -- Data.Calendar.epoch
A.STATE_ORDER = {"Clear", "Breezy", "Rain", "Storm", "Fog", "Snow"}
function A.hash(a, b)
	local h = bit32.bxor(bit32.band(a * 374761393, 0xFFFFFFFF), bit32.band(b * 668265263, 0xFFFFFFFF))
	h = bit32.band(bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177, 0xFFFFFFFF)
	return bit32.bxor(h, bit32.rshift(h, 16)) / 0xFFFFFFFF
end
-- Three-key hash (QC L2: no (slot, i) pair of one region repeats another's).
function A.hash3(a, b, c)
	return A.hash(a, math.floor(A.hash(b * 2654435761 % 4294967296, c + 1) * 2147483647))
end
function A.slotAt(t)
	t = tonumber(t) or 0
	if t ~= t then t = 0 end
	return math.floor((t - A.EPOCH) / A.SLOT)
end
local function regionIndex(key)
	for i, k in ipairs(A.WEATHER_KEYS) do if k == key then return i end end
	return 0
end
function A.weatherAt(slot, key)
	local region = A.Regions[key]
	if not region then return "Clear" end
	local total = 0
	for _, s in ipairs(A.STATE_ORDER) do total += region.weather[s] or 0 end
	local roll = A.hash(slot, regionIndex(key) * 7919 + 17) * total
	for _, s in ipairs(A.STATE_ORDER) do
		local w = region.weather[s] or 0
		if roll < w then return s end
		roll -= w
	end
	return "Clear"
end
function A.schedule(slot)
	local out = {}
	for _, key in ipairs(A.WEATHER_KEYS) do out[key] = A.weatherAt(slot, key) end
	return out
end
-- Lightning strike times (seconds into the slot) in a storming region:
-- one every 9-24 s, never in the first 10 s (the storm is still rolling in).
function A.strikes(slot, key)
	local out = {}
	if A.weatherAt(slot, key) ~= "Storm" then return out end
	local at, i = 10, 0
	while true do
		i += 1
		at += 9 + 15 * A.hash3(slot, regionIndex(key), i)
		if at >= A.SLOT then break end
		table.insert(out, at)
	end
	return out
end
-- Strikes are computed on every client from this schedule (QC H2: no
-- network latency): A.strikeCursor keeps a per-(slot, key) list and hands
-- out each strike once, at its server time.
A.STRIKE_GRACE = 0.5 -- a strike seen later than this (a late join, a late table) is skipped, never shown out of sync
function A.newStrikeCursor() return {slot = nil, key = nil, list = nil, start = 0, i = 1} end
-- Advance the cursor to time t in context key; returns the server time of a
-- strike that is due now (at <= t < at + grace) or nil. Allocates only when
-- the slot or key changes.
function A.strikeDue(cursor, t, key, grace)
	local slot = A.slotAt(t)
	if slot ~= cursor.slot or key ~= cursor.key then
		cursor.slot, cursor.key, cursor.list = slot, key, A.strikes(slot, key)
		cursor.start, cursor.i = A.EPOCH + slot * A.SLOT, 1
		while cursor.list[cursor.i] and cursor.start + cursor.list[cursor.i] < t - grace do cursor.i += 1 end
	end
	local off = cursor.list[cursor.i]
	if not off then return nil end
	local at = cursor.start + off
	if t < at then return nil end
	cursor.i += 1
	if t - at <= grace then return at end
	return nil
end
-- The latest strike at or before t in key's current slot (nil if none).
function A.lastStrike(cursor, t, key)
	while A.strikeDue(cursor, t, key, math.huge) do end
	local i = cursor.i - 1
	local off = cursor.list[i]
	return if off then cursor.start + off else nil
end
-- The IsleWeather attribute (parsed by L.parseWeather). Since QC H2 the
-- server publishes only the slot's states; strikes come from A.strikes.
function A.encode(slot, strikeRegion, strikeAt)
	local parts = {}
	local sched = A.schedule(slot)
	for _, key in ipairs(A.WEATHER_KEYS) do table.insert(parts, key .. "=" .. sched[key]) end
	local text = "1|" .. slot .. "|" .. table.concat(parts, ",")
	if strikeRegion and strikeAt then text ..= "|" .. strikeRegion .. "@" .. string.format("%.2f", strikeAt) end
	return text
end
------------------------------------------------------------------------------
-- Shelter (QC H1): a point is under a roof when it is inside a building's
-- declared box (ShapeBox / ShapeBoxOffset of the §40 hosts, attribute
-- BuildingType), in that box's frame (lx, ly, lz) with size (sx, sy, sz).
-- Feet may be up to A.SHELTER_FEET below the box (a hall host is its floor).
-- Tree canopies, awnings and open sky never count.
------------------------------------------------------------------------------
A.SHELTER_FEET = 4
function A.insideBox(lx, ly, lz, sx, sy, sz)
	return math.abs(lx) <= sx / 2 and math.abs(lz) <= sz / 2 and ly >= -sy / 2 - A.SHELTER_FEET and ly <= sy / 2
end
-- Island particle kinds (Data.RegionArt ambience.particles, the island's
-- Ambience attribute) -> presets (QC M4: one palette; regions.client.lua no
-- longer runs its own emitter).
A.ISLAND_MOTES = {motes = "motes", pollen = "pollen", embers = "embers", wind = "wind", leaves = "leaves", spores = "spores",
	spray = "spray", sparks = "void", glints = "glints"}

------------------------------------------------------------------------------
-- Skill VFX.
------------------------------------------------------------------------------
-- Hit sparks / chips per strike fx (animate.client.lua's IsleImpactLocal):
-- sparks are hot and bright, chips take the node's resource colour.
A.SPARKS = {
	chips = {sparks = "FFC46A", chips = "8E8A86", sparkCount = 7, chipCount = 5, speed = 14, spread = 55},
	wood = {sparks = "FFE2A8", chips = "B07A4A", sparkCount = 0, chipCount = 7, speed = 10, spread = 60},
	dust = {sparks = "E8F0B0", chips = "7FAF55", sparkCount = 0, chipCount = 6, speed = 7, spread = 70},
	splash = {sparks = "E6FAFF", chips = "8ED4F0", sparkCount = 4, chipCount = 6, speed = 9, spread = 35},
	sparks = {sparks = "FFD27A", chips = "FF8A3A", sparkCount = 10, chipCount = 0, speed = 16, spread = 70},
	slash = {sparks = "FFFFFF", chips = "BFE8FF", sparkCount = 6, chipCount = 0, speed = 12, spread = 80},
}
A.SPARK_DEFAULT = "slash"
function A.sparkFor(fx, reduced)
	local s = A.SPARKS[fx] or A.SPARKS[A.SPARK_DEFAULT]
	local scale = if reduced then 0.5 else 1
	return s, math.floor(s.sparkCount * scale + 0.5), math.floor(s.chipCount * scale + 0.5)
end
-- Rare-drop pillar: Data.Rarity colour, taller and longer for rarer drops.
A.BEAM_MIN_RANK = 3 -- Rare and above
function A.beamFor(rarity, Data)
	local r = Data and Data.Rarity and Data.Rarity[rarity]
	if not r or r.rank < A.BEAM_MIN_RANK then return nil end
	return {color = r.color, height = 16 + 8 * r.rank, width = 0.5 + 0.12 * r.rank, life = 2.5 + 0.75 * r.rank, rank = r.rank,
		pulse = r.rank >= 5}
end
-- The rarest pickup in a snapshot's list ({{id, n}}), or nil.
function A.rarestPickup(list, Data)
	if type(list) ~= "table" or not Data or not Data.Items then return nil end
	local best, bestRank
	for _, e in ipairs(list) do
		local def = type(e) == "table" and Data.Items[e.id]
		local r = def and Data.Rarity[def.rarity or "Common"]
		if r and (not bestRank or r.rank > bestRank) then best, bestRank = def.rarity, r.rank end
	end
	return best
end
-- XP orbs: one per order of magnitude of the gain, capped by the tier.
function A.orbCount(amount, b)
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0 end
	return math.clamp(1 + math.floor(math.log10(amount + 1)), 1, math.min(4, b.orbs))
end
A.ORB_TIME = 0.75 -- seconds from the node to the player
A.LEVEL_BURST = {sparkles = 40, ring = 14, time = 1.1}
A.SOUNDS = {levelUp = "rbxasset://sounds/electronicpingshort.wav", thunder = ""} -- thunder: audio team fills (cue still fires)

------------------------------------------------------------------------------
-- Selection helpers (allocation-free: write into the caller's scratch).
------------------------------------------------------------------------------
-- Insertion-select the n nearest entries (entry.d2 precomputed) into out.
function A.nearest(list, count, n, radius2, out)
	local m = 0
	if n <= 0 then count = 0 end
	for i = 1, count do
		local e = list[i]
		local d = e.d2
		if d <= radius2 then
			if m < n then
				m += 1
				out[m] = e
			elseif d < out[m].d2 then
				out[m] = e
			else
				continue
			end
			local j = m
			while j > 1 and out[j - 1].d2 > out[j].d2 do
				out[j - 1], out[j] = out[j], out[j - 1]
				j -= 1
			end
		end
	end
	for i = m + 1, #out do out[i] = nil end
	return m
end

return A
