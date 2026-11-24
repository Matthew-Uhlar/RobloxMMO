--!nocheck
-- Aether Isles lighting profiles (ReplicatedStorage.AetherLighting).
-- docs/DEPTH-CONTRACT.md §35. Pure rules, no instances and no requires: the
-- one Lighting writer (lighting.client.lua, StarterPlayerScripts.IsleLighting)
-- feeds it the isle clock, the player's context and the graphics tier and
-- writes what it returns. verify-lighting.luau exercises every function here.
--
--   L.FIELDS                 the blended look: Lighting, Atmosphere, Bloom,
--                            SunRays and ColorCorrection values with ranges
--   L.Profiles[key]          day look per region / interior (+ optional night)
--   L.REGION_KEYS            keys a player can stand in (Data.Regions + Home,
--                            Skyways) and L.INTERIOR_KEYS (Dungeon, Lair, Minigame)
--   L.clockAt(t, Calendar)   isle clock 0..24 (same hour as the sidebar clock)
--   L.skyClock(clock)        Lighting.ClockTime (sun sets at the sidebar's dusk)
--   L.skyClockFor(key, clock) the same, but interiors hold a fixed daytime sky
--   L.dayFactor(clock)       0 night .. 1 day (< .5 exactly when the sidebar says night)
--   L.context(attrs, pos)    which profile the player is in
--   L.target(key, clock, tier) -> state   the look to blend toward
--   L.alphaFor(dt, tau), L.blend(a, b, alpha), L.distance(a, b)
--   L.Tiers / L.TIER_ORDER / L.defaultTier(device) / L.readTier(value, device)
--   L.selectLights(list, origin, tier, night, scratch) -> {[i] = mode} light budget
--   L.effectiveAmbient(state, tier) the ambient a surface actually gets on a tier
--   L.valid(state) -> ok, why   finite and in range
local L = {}
L.VERSION = 1
L.SETTING_ATTR = "IsleSettingGraphics" -- player attribute (client-set, like the other IsleSetting* toggles)

local function rgb(hex) return Color3.fromHex(hex) end
-- Relative luminance of a Color3 (gamma values, as the profiles are authored).
local function lum(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
L.luminance = lum

------------------------------------------------------------------------------
-- Fields. kind "number" | "color"; min / max bound every composed and blended
-- value (verify-lighting asserts them). Bloom thresholds stay above 1 so white
-- UI text on BillboardGuis / SurfaceGuis never blooms.
------------------------------------------------------------------------------
L.FIELDS = {
	{key = "Brightness", kind = "number", min = 0.5, max = 3.2},
	{key = "ExposureCompensation", kind = "number", min = -0.5, max = 0.5},
	{key = "Ambient", kind = "color", maxLum = 0.35},
	{key = "OutdoorAmbient", kind = "color", maxLum = 0.6, minLum = 0.12},
	{key = "ColorShift_Top", kind = "color"},
	{key = "ColorShift_Bottom", kind = "color", maxLum = 0.3},
	{key = "EnvironmentDiffuseScale", kind = "number", min = 0, max = 1},
	{key = "EnvironmentSpecularScale", kind = "number", min = 0, max = 1},
	{key = "ShadowSoftness", kind = "number", min = 0, max = 1},
	{key = "AtmDensity", kind = "number", min = 0.1, max = 0.5},
	{key = "AtmOffset", kind = "number", min = 0, max = 1},
	{key = "AtmColor", kind = "color"},
	{key = "AtmDecay", kind = "color"},
	{key = "AtmGlare", kind = "number", min = 0, max = 2},
	{key = "AtmHaze", kind = "number", min = 0, max = 2.5},
	{key = "BloomIntensity", kind = "number", min = 0, max = 0.6},
	{key = "BloomSize", kind = "number", min = 8, max = 32},
	{key = "BloomThreshold", kind = "number", min = 1.05, max = 2.5},
	{key = "RaysIntensity", kind = "number", min = 0, max = 0.12},
	{key = "RaysSpread", kind = "number", min = 0, max = 1},
	{key = "GradeBrightness", kind = "number", min = -0.05, max = 0.05},
	{key = "GradeContrast", kind = "number", min = -0.05, max = 0.2},
	{key = "GradeSaturation", kind = "number", min = -0.2, max = 0.2},
	{key = "GradeTint", kind = "color", minLum = 0.8},
}
L.FieldByKey = {}
for _, f in ipairs(L.FIELDS) do L.FieldByKey[f.key] = f end

------------------------------------------------------------------------------
-- Profiles. Art bible: cool stone, saturated foliage, warm light; distance
-- haze; a sky tint per biome (bright blue isles, violet arcane isles, red-black
-- depths). Missing keys inherit BASE. `night` overrides the derived night look;
-- `dayFloor` keeps a little daylight in sheltered places; interiors use
-- `fixedDay` (the clock does not change them) and skip the golden hour.
------------------------------------------------------------------------------
local BASE = {
	Brightness = 2.6, ExposureCompensation = 0,
	Ambient = "3A4150", OutdoorAmbient = "7D8A9C", ColorShift_Top = "FFE6C4", ColorShift_Bottom = "26303F",
	EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.3, ShadowSoftness = 0.3,
	AtmDensity = 0.24, AtmOffset = 0.1, AtmColor = "C9D8E6", AtmDecay = "7186A6", AtmGlare = 0.3, AtmHaze = 0.7,
	BloomIntensity = 0.3, BloomSize = 20, BloomThreshold = 1.5,
	RaysIntensity = 0.045, RaysSpread = 0.45,
	GradeBrightness = 0, GradeContrast = 0.1, GradeSaturation = 0.08, GradeTint = "FFF6EA",
}
L.BASE = BASE
-- Night: a moonlit blue that keeps paths and caves readable (the old server
-- night dropped OutdoorAmbient to 3E4A66 with no exposure lift: over-dark).
local NIGHT = {
	Brightness = 1.1, ExposureCompensation = 0.12,
	Ambient = "2C3449", OutdoorAmbient = "56648A", ColorShift_Top = "93A9D8", ColorShift_Bottom = "1A2034",
	EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.25,
	AtmColor = "46547A", AtmDecay = "182038", AtmGlare = 0, AtmHaze = 0.9,
	BloomIntensity = 0.45, BloomSize = 24, BloomThreshold = 1.15,
	RaysIntensity = 0,
	GradeBrightness = 0.02, GradeContrast = 0.12, GradeSaturation = -0.08, GradeTint = "D8E2FF",
}
L.NIGHT = NIGHT
local GOLDEN = {ColorShift_Top = "FFB27A", AtmColor = "F2B48A", GradeTint = "FFE2C8"}

L.Profiles = {
	-- Compass Quay: warm market light on cool stone.
	Hub = {label = "Compass Quay"},
	-- Sunwheel Downs: bright foliage, clear air.
	Meadow = {label = "Sunwheel Downs", Brightness = 2.75, Ambient = "3C4450", OutdoorAmbient = "8494A0", ColorShift_Top = "FFEBC0",
		AtmDensity = 0.22, AtmColor = "D3E2EC", AtmDecay = "7A95B0", AtmHaze = 0.6, GradeSaturation = 0.12, GradeTint = "FFF4E0"},
	-- Brassfall Cay: sun-warmed stone and quarry dust.
	Quarry = {label = "Brassfall Cay", Ambient = "44403E", OutdoorAmbient = "8A8478", ColorShift_Top = "FFD9A8",
		AtmDensity = 0.28, AtmColor = "E2D2B8", AtmDecay = "A08A6A", AtmGlare = 0.4, AtmHaze = 1.1,
		GradeContrast = 0.12, GradeSaturation = 0.05, GradeTint = "FFEEDC"},
	-- Skyreach Heights: thin cold air, crisp sun.
	Skyreach = {label = "Skyreach Heights", Brightness = 2.9, ExposureCompensation = 0.05, Ambient = "3A4656", OutdoorAmbient = "7E92A6",
		ColorShift_Top = "F4F2E8", AtmDensity = 0.18, AtmColor = "D8E8F4", AtmDecay = "7C9CC0", AtmGlare = 0.5, AtmHaze = 0.4,
		RaysIntensity = 0.06, GradeSaturation = 0.04, GradeTint = "F2F8FF"},
	-- Windpine Grove: green forest shade, soft haze.
	Windpine = {label = "Windpine Grove", Brightness = 2.4, Ambient = "343E38", OutdoorAmbient = "6E8476", ColorShift_Top = "F6E6BA",
		AtmDensity = 0.3, AtmColor = "BCD3BE", AtmDecay = "5E7E66", AtmHaze = 1.2, GradeSaturation = 0.1, GradeTint = "F4FFE8",
		dayFloor = 0.1},
	-- Gloomhollow Caverns: violet grotto lit by voidstone (arcane biome tint).
	Gloomhollow = {label = "Gloomhollow Caverns", Brightness = 1.6, ExposureCompensation = 0.1, Ambient = "2E2A42", OutdoorAmbient = "4A4466",
		ColorShift_Top = "C8B8F0", ColorShift_Bottom = "3A2C5A", EnvironmentDiffuseScale = 0.4,
		AtmDensity = 0.42, AtmOffset = 0.2, AtmColor = "6E5E9A", AtmDecay = "2A2240", AtmGlare = 0, AtmHaze = 1.6,
		BloomIntensity = 0.5, BloomSize = 24, BloomThreshold = 1.1, RaysIntensity = 0,
		GradeContrast = 0.14, GradeSaturation = 0.02, GradeTint = "E8E0FF",
		dayFloor = 0.35, golden = 0,
		night = {OutdoorAmbient = "3E3A5C", AtmColor = "3C3460", AtmDecay = "16122A", GradeTint = "E0D8FF"}},
	-- Tidewater Shoals: aqua shallows, glittering water.
	Tidewater = {label = "Tidewater Shoals", Brightness = 2.8, Ambient = "3A4A54", OutdoorAmbient = "7E9CAA", ColorShift_Top = "FFF0D0",
		EnvironmentSpecularScale = 0.45, AtmDensity = 0.2, AtmColor = "CBE6EE", AtmDecay = "6AA6BE", AtmGlare = 0.4, AtmHaze = 0.5,
		RaysIntensity = 0.05, GradeSaturation = 0.1, GradeTint = "F2FCFF"},
	-- Tempest Spire: storm-grey, heavy haze, desaturated.
	Tempest = {label = "Tempest Spire", Brightness = 2.0, ExposureCompensation = -0.05, Ambient = "323846", OutdoorAmbient = "66728A",
		ColorShift_Top = "C8D4EA", ColorShift_Bottom = "2A3350", AtmDensity = 0.36, AtmOffset = 0.15, AtmColor = "8C98B0", AtmDecay = "3E4A66",
		AtmGlare = 0, AtmHaze = 1.8, BloomIntensity = 0.4, BloomSize = 22, BloomThreshold = 1.2, RaysIntensity = 0.02,
		GradeContrast = 0.16, GradeSaturation = -0.08, GradeTint = "E6EEFF", golden = 0.4},
	-- The Shattered Crown: arcane gold and violet.
	ShatteredCrown = {label = "The Shattered Crown", Brightness = 2.4, Ambient = "3A3450", OutdoorAmbient = "7A7298", ColorShift_Top = "F2D8A8",
		ColorShift_Bottom = "40305E", AtmDensity = 0.3, AtmColor = "B8A8D8", AtmDecay = "5A4A8A", AtmGlare = 0.6, AtmHaze = 1.2,
		BloomIntensity = 0.45, BloomSize = 24, BloomThreshold = 1.2, RaysIntensity = 0.06,
		GradeContrast = 0.12, GradeSaturation = 0.1, GradeTint = "FFF0FA"},
	-- Your isle (home islands): cosy and warm.
	Home = {label = "Your Isle", Brightness = 2.7, Ambient = "3C4250", OutdoorAmbient = "8090A0", ColorShift_Top = "FFE4BE",
		AtmDensity = 0.22, AtmColor = "D0DEEA", AtmHaze = 0.6, GradeSaturation = 0.1, GradeTint = "FFF4E4"},
	-- Between islands (bridges, open sky): light haze so the isles read.
	Skyways = {label = "The Skyways", AtmDensity = 0.2, AtmHaze = 0.6, AtmGlare = 0.4, RaysIntensity = 0.05},
	-- Interiors.
	-- The Hollow Observatory dungeon: cold starlight, the clock does not reach it.
	Dungeon = {label = "The Hollow Observatory", interior = true, fixedDay = 0.55, Brightness = 1.4, ExposureCompensation = 0.1,
		Ambient = "2E3448", OutdoorAmbient = "4E5A74", ColorShift_Top = "D8E4FF", ColorShift_Bottom = "1E2A40",
		AtmDensity = 0.34, AtmColor = "5A6E8C", AtmDecay = "1E2A40", AtmGlare = 0, AtmHaze = 1.3,
		BloomIntensity = 0.5, BloomSize = 24, BloomThreshold = 1.1, RaysIntensity = 0,
		GradeContrast = 0.14, GradeSaturation = -0.02, GradeTint = "E8F0FF"},
	-- Lair arenas: brazier-lit, red-black depths.
	Lair = {label = "Lair", interior = true, fixedDay = 0.45, Brightness = 1.5, Ambient = "3A2E2E", OutdoorAmbient = "5E4E4A",
		ColorShift_Top = "FFC89A", ColorShift_Bottom = "2A1A16", AtmDensity = 0.36, AtmColor = "6A4E44", AtmDecay = "2A1A16", AtmGlare = 0,
		AtmHaze = 1.4, BloomIntensity = 0.5, BloomSize = 24, BloomThreshold = 1.1, RaysIntensity = 0,
		GradeContrast = 0.16, GradeSaturation = 0, GradeTint = "FFE8DA"},
	-- Skybreach Bastion minigames: a storm-sieged fortress (outdoors, muted clock).
	Minigame = {label = "Skybreach Bastion", interior = true, fixedDay = 0.7, Brightness = 2.2, Ambient = "363C4A", OutdoorAmbient = "6E7A90",
		ColorShift_Top = "E8DCC8", AtmDensity = 0.3, AtmColor = "A0AEC4", AtmDecay = "4A5872", AtmHaze = 1.2,
		BloomIntensity = 0.35, BloomThreshold = 1.3, RaysIntensity = 0.03, GradeContrast = 0.14, GradeSaturation = 0, GradeTint = "F0F4FF"},
	-- Raids (§38): the Undertide Vaults, drowned halls lit by teal braziers
	-- through deep water haze; cool, saturated, never murky.
	Raid = {label = "The Undertide Vaults", interior = true, fixedDay = 0.5, Brightness = 1.6, ExposureCompensation = 0.1,
		Ambient = "24403E", OutdoorAmbient = "4A6E6A", ColorShift_Top = "A8F0E6", ColorShift_Bottom = "0E2A2E",
		AtmDensity = 0.38, AtmColor = "3E7A78", AtmDecay = "0E2A2E", AtmGlare = 0, AtmHaze = 1.4,
		BloomIntensity = 0.55, BloomSize = 26, BloomThreshold = 1.1, RaysIntensity = 0,
		GradeContrast = 0.15, GradeSaturation = 0.06, GradeTint = "E4FFF8"},
}
L.REGION_KEYS = {"Hub", "Meadow", "Quarry", "Skyreach", "Windpine", "Gloomhollow", "Tidewater", "Tempest", "ShatteredCrown", "Home", "Skyways"}
L.INTERIOR_KEYS = {"Dungeon", "Lair", "Minigame", "Raid"}
L.DEFAULT_KEY = "Skyways"

------------------------------------------------------------------------------
-- Isle clock. The sidebar (Theme.isleClock) shows minutes since the isle
-- day's dawn over Data.Calendar.dayLength; the same server time gives the
-- same hour here, so the sky never disagrees with the clock.
------------------------------------------------------------------------------
function L.clockAt(t, Calendar)
	local epoch = (Calendar and tonumber(Calendar.epoch)) or 1577836800
	local dayLength = (Calendar and tonumber(Calendar.dayLength)) or 9150
	t = tonumber(t) or 0
	if t ~= t or dayLength <= 0 then return 12 end
	local into = (t - epoch) % dayLength
	return into / dayLength * 24
end
-- Sidebar night is hour < 6 or >= 19. Roblox's sun rises about 6:00 and sets
-- about 18:00, so the day half [6, 19) is mapped onto [6, 18) and the night
-- half [19, 30) onto [18, 30): continuous, rising, and the sun sets at dusk.
L.DAWN, L.DUSK = 6, 19
function L.skyClock(clock)
	clock = (tonumber(clock) or 12) % 24
	if clock ~= clock then return 12 end
	if clock >= L.DAWN and clock < L.DUSK then
		return L.DAWN + (clock - L.DAWN) * (12 / (L.DUSK - L.DAWN))
	end
	local into = (clock - L.DUSK) % 24 -- 0 .. 11 through the night
	return (18 + into * (12 / (24 - (L.DUSK - L.DAWN)))) % 24
end
-- QC L3: interiors (Observatory, lairs, Skybreach Bastion) are instanced
-- arenas the clock does not reach, so they hold a fixed daytime sun instead
-- of showing the outdoor night sky: ClockTime = 8 + 6 × fixedDay (fixedDay
-- 0.45 → 10.7, 0.55 → 11.3, 0.7 → 12.2: high sun, short shadows).
function L.interiorClock(key)
	local profile = L.Profiles[key]
	if not profile or not profile.interior then return nil end
	return 8 + 6 * math.clamp(tonumber(profile.fixedDay) or 0.5, 0, 1)
end
function L.skyClockFor(key, clock)
	return L.interiorClock(key) or L.skyClock(clock)
end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
L.RAMP = 0.75 -- hours either side of dawn / dusk
function L.dayFactor(clock)
	clock = (tonumber(clock) or 12) % 24
	if clock ~= clock then return 1 end
	local up = smooth((clock - (L.DAWN - L.RAMP)) / (2 * L.RAMP))
	local down = 1 - smooth((clock - (L.DUSK - L.RAMP)) / (2 * L.RAMP))
	return math.min(up, down)
end

------------------------------------------------------------------------------
-- Context. attrs: {LairBoss, RaidRun, DungeonInRun, MinigameGame, IsleRegionHere}
-- (player attributes the servers / nav.client.lua already publish). pos is the
-- player's position (optional): the instanced arenas sit far off the
-- archipelago, so their lobbies light correctly before a run starts.
------------------------------------------------------------------------------
L.ZONES = {
	{key = "Dungeon", x = 0, z = 1800, r = 260}, -- expedition.server.lua origin (0, 42, 1800)
	{key = "Minigame", x = -2400, z = 0, r = 380}, -- minigames.server.lua ORIGIN (-2400, 90, 0)
	{key = "Lair", minX = 3300}, -- lairs.server.lua ORIGIN (3600, 300, -3600) + slots along +X
	{key = "Raid", maxX = -3000, maxZ = -3000}, -- raids.server.lua ORIGIN (-3600, 300, -3600), rooms along -X, slots along -Z
}
local function inZone(zone, pos)
	if zone.maxX then return pos.X <= zone.maxX and pos.Z <= zone.maxZ end
	if zone.minX then return pos.X >= zone.minX end
	local dx, dz = pos.X - zone.x, pos.Z - zone.z
	return dx * dx + dz * dz <= zone.r * zone.r
end
function L.context(attrs, pos)
	attrs = type(attrs) == "table" and attrs or {}
	local hasPos = pos ~= nil and type(pos.X) == "number" and pos.X == pos.X and type(pos.Z) == "number" and pos.Z == pos.Z
	local zoneKey
	if hasPos then
		for _, zone in ipairs(L.ZONES) do
			if inZone(zone, pos) then zoneKey = zone.key break end
		end
	end
	-- QC L4: an interior attribute names the arena the server thinks the
	-- player is in, but the attributes can lag a teleport (or stick after a
	-- crash). When the position is known and outside that arena's zone, the
	-- position wins.
	local claimed
	local lair = attrs.LairBoss
	local raid = attrs.RaidRun
	if type(lair) == "string" and lair ~= "" then claimed = "Lair"
	elseif type(raid) == "string" and raid ~= "" then claimed = "Raid"
	elseif attrs.DungeonInRun == true then claimed = "Dungeon"
	else
		local match = attrs.MinigameGame
		if type(match) == "string" and match ~= "" then claimed = "Minigame" end
	end
	if claimed and (not hasPos or zoneKey == claimed) then return claimed end
	if zoneKey then return zoneKey end
	local here = attrs.IsleRegionHere
	if type(here) == "string" and L.Profiles[here] and not L.Profiles[here].interior then return here end
	return L.DEFAULT_KEY
end

------------------------------------------------------------------------------
-- Composition.
------------------------------------------------------------------------------
local function value(profile, key)
	local v = profile[key]
	if v == nil then v = BASE[key] end
	return v
end
local function resolve(field, v)
	if field.kind == "color" and type(v) == "string" then return rgb(v) end
	return v
end
local function lerp(field, a, b, t)
	if field.kind == "color" then return a:Lerp(b, t) end
	return a + (b - a) * t
end
-- Day / night looks are memoized per profile key (QC L2: L.target runs at
-- 15 Hz). The cached tables are shared: callers must not mutate them.
-- L.clearLookCache() drops the cache after a profile is edited (tests).
local dayCache, nightCache = {}, {}
function L.clearLookCache() table.clear(dayCache); table.clear(nightCache) end
local function profileKey(key) return if L.Profiles[key] then key else L.DEFAULT_KEY end
-- Day look of a profile (fully resolved).
function L.dayLook(key)
	key = profileKey(key)
	local cached = dayCache[key]
	if cached then return cached end
	local profile = L.Profiles[key]
	local out = {}
	for _, f in ipairs(L.FIELDS) do out[f.key] = resolve(f, value(profile, f.key)) end
	dayCache[key] = out
	return out
end
-- Night look: the profile's own night overrides, else the shared moonlit
-- night tinted 25% toward the region's day colours (so biomes stay distinct).
function L.nightLook(key)
	key = profileKey(key)
	local cached = nightCache[key]
	if cached then return cached end
	local profile = L.Profiles[key]
	local day = L.dayLook(key)
	local own = profile.night or {}
	local out = {}
	for _, f in ipairs(L.FIELDS) do
		local v = own[f.key]
		if v ~= nil then
			out[f.key] = resolve(f, v)
		elseif f.key == "AtmDensity" then
			out[f.key] = math.min(day.AtmDensity + 0.04, 0.5)
		elseif NIGHT[f.key] ~= nil then
			local n = resolve(f, NIGHT[f.key])
			out[f.key] = if f.kind == "color" then n:Lerp(day[f.key], 0.25) else n
		else
			out[f.key] = day[f.key]
		end
	end
	nightCache[key] = out
	return out
end
-- Effective daylight for a profile at an isle clock.
function L.daylight(key, clock)
	local profile = L.Profiles[key] or L.Profiles[L.DEFAULT_KEY]
	if profile.interior then return profile.fixedDay or 0.5 end
	local floor = profile.dayFloor or 0
	return floor + (1 - floor) * L.dayFactor(clock)
end
function L.target(key, clock, tierName)
	local profile = L.Profiles[key] or L.Profiles[L.DEFAULT_KEY]
	local d = L.daylight(key, clock)
	local day, night = L.dayLook(key), L.nightLook(key)
	local out = {}
	for _, f in ipairs(L.FIELDS) do out[f.key] = lerp(f, night[f.key], day[f.key], d) end
	if not profile.interior then
		-- Golden hour: warm sun, haze and grade around dawn and dusk.
		local g = 4 * d * (1 - d) * (profile.golden or 1)
		if g > 0 then
			out.ColorShift_Top = out.ColorShift_Top:Lerp(rgb(GOLDEN.ColorShift_Top), 0.5 * g)
			out.AtmColor = out.AtmColor:Lerp(rgb(GOLDEN.AtmColor), 0.35 * g)
			out.GradeTint = out.GradeTint:Lerp(rgb(GOLDEN.GradeTint), 0.4 * g)
			out.RaysIntensity = math.min(out.RaysIntensity + 0.03 * g, 0.12)
		end
	end
	local tier = L.Tiers[tierName] or L.Tiers[L.DEFAULT_TIER]
	out.BloomIntensity *= tier.bloomScale
	if not tier.globalShadows then
		-- QC M3: with GlobalShadows off Roblox lights every surface with Ambient
		-- only (OutdoorAmbient drops out), so Performance went far darker than
		-- the other tiers at night. Lift Ambient toward OutdoorAmbient just far
		-- enough to reach the readability floor (luminance is linear in RGB, so
		-- the lerp fraction is exact), never past OutdoorAmbient itself.
		local a, o = lum(out.Ambient), lum(out.OutdoorAmbient)
		local floor = tier.ambientFloor or L.READABLE_AMBIENT
		if a < floor and o > a then
			out.Ambient = out.Ambient:Lerp(out.OutdoorAmbient, math.clamp((floor - a) / (o - a), 0, 1))
		end
	end
	return out
end
-- The ambient light a surface actually receives on a tier: OutdoorAmbient
-- under open sky with GlobalShadows on, Ambient everywhere with it off.
function L.effectiveAmbient(state, tierName)
	local tier = L.Tiers[tierName] or L.Tiers[L.DEFAULT_TIER]
	return if tier.globalShadows then state.OutdoorAmbient else state.Ambient
end

------------------------------------------------------------------------------
-- Blending: exponential approach toward the target, frame-rate independent,
-- never overshooting (alpha in [0, 1]).
------------------------------------------------------------------------------
L.REGION_TAU = 1.2 -- seconds; 95% of a region change lands in ~3.6 s
L.SNAP_DISTANCE = 0.002 -- below this every field is written as the target
function L.alphaFor(dt, tau)
	dt, tau = tonumber(dt) or 0, tonumber(tau) or L.REGION_TAU
	if dt ~= dt or dt <= 0 then return 0 end
	if tau ~= tau or tau <= 0 then return 1 end
	return math.clamp(1 - math.exp(-dt / tau), 0, 1)
end
function L.blend(a, b, alpha)
	local out = {}
	for _, f in ipairs(L.FIELDS) do
		local x, y = a and a[f.key], b[f.key]
		if x == nil then out[f.key] = y else out[f.key] = lerp(f, x, y, alpha) end
	end
	return out
end
-- Largest per-field gap (colours by channel, numbers relative to their range).
function L.distance(a, b)
	local worst = 0
	for _, f in ipairs(L.FIELDS) do
		local x, y = a[f.key], b[f.key]
		local d
		if f.kind == "color" then
			d = math.max(math.abs(x.R - y.R), math.abs(x.G - y.G), math.abs(x.B - y.B))
		else
			d = math.abs(x - y) / math.max(f.max - f.min, 1e-6)
		end
		if d ~= d then return math.huge end
		if d > worst then worst = d end
	end
	return worst
end

------------------------------------------------------------------------------
-- Graphics tiers (Settings › Graphics). Lighting.Technology cannot change at
-- runtime, so the place ships with Future (default.project.json) and the
-- tiers are emulated with properties: GlobalShadows, light counts and
-- shadows, post effects.
--   lights       hard cap on world lights enabled at once (nearest first)
--   cull         lights further than this (studs) are switched off
--   pool         client glow lights on lamp / lantern meshes without a light (night only)
--   shadows      "hero" keeps the few authored shadow casters within heroShadowRange; "none" drops all
------------------------------------------------------------------------------
L.Tiers = {
	High = {label = "High", detail = "Future lighting with sun and lamp shadows, bloom, sun rays and colour grading.",
		globalShadows = true, bloom = true, rays = true, grade = true, bloomScale = 1,
		lights = 40, cull = 280, pool = 8, shadows = "hero", heroShadowRange = 140},
	Balanced = {label = "Balanced", detail = "Sun shadows and colour grading; lamps cast no shadows and fewer are lit. The phone default.",
		globalShadows = true, bloom = true, rays = false, grade = true, bloomScale = 0.8,
		lights = 22, cull = 200, pool = 4, shadows = "none", heroShadowRange = 0},
	Performance = {label = "Performance", detail = "No shadows or post effects and only the nearest lamps lit. For older devices.",
		globalShadows = false, bloom = false, rays = false, grade = false, bloomScale = 0,
		lights = 10, cull = 130, pool = 0, shadows = "none", heroShadowRange = 0},
}
L.TIER_ORDER = {"High", "Balanced", "Performance"}
-- Readability floor for the ambient a surface receives (L.effectiveAmbient):
-- a tier without GlobalShadows lifts Ambient toward OutdoorAmbient until it
-- reaches this luminance (or OutdoorAmbient itself, if that is darker).
L.READABLE_AMBIENT = 0.3
L.DEFAULT_TIER = "High"
L.MAX_LIGHT_BRIGHTNESS = 1.5 -- verify-world's per-light ceiling
L.NIGHT_BOOST = 0.3 -- lamps and glows burn 30% brighter at full night
-- device: {touch, keyboard, gamepad, viewportX, quality (1..10 or nil = automatic)}
function L.defaultTier(device)
	device = type(device) == "table" and device or {}
	local q = tonumber(device.quality)
	if q and q >= 1 and q <= 3 then return "Performance" end
	local phone = device.touch == true and device.keyboard ~= true
	local small = tonumber(device.viewportX) and device.viewportX < 900
	if phone or (small and device.keyboard ~= true and device.gamepad ~= true) then return "Balanced" end
	if q and q <= 5 then return "Balanced" end
	return "High"
end
function L.readTier(v, device)
	if type(v) == "string" and L.Tiers[v] then return v end
	return L.defaultTier(device)
end

------------------------------------------------------------------------------
-- Light budget. list entries: {pos = Vector3, base = bool (the server wants it
-- on), night = bool (a night lamp: on only after dusk), hero = bool (authored
-- shadow caster), pooled = bool (a client glow site)}. Returns modes per index:
-- nil = off, "on", "shadow" (on with shadows); plus counts.
------------------------------------------------------------------------------
-- QC M1: `base` is the server's intent (the LightWanted attribute), never the
-- light's live Enabled (which this budget itself writes). A night lamp burns
-- only at night AND only while the server wants it; a glow site only at night.
-- scratch (optional, QC L1): a table the caller keeps between calls; its
-- candidate nodes and modes table are reused instead of reallocated. The
-- returned modes table is then scratch.modes (valid until the next call).
local function byRank(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.i < b.i end
function L.selectLights(list, origin, tierName, isNight, scratch)
	local tier = L.Tiers[tierName] or L.Tiers[L.DEFAULT_TIER]
	local wanted, pooled, nodes, modes
	if scratch then
		scratch.wanted, scratch.pooled, scratch.nodes, scratch.modes = scratch.wanted or {}, scratch.pooled or {}, scratch.nodes or {}, scratch.modes or {}
		wanted, pooled, nodes, modes = scratch.wanted, scratch.pooled, scratch.nodes, scratch.modes
		table.clear(wanted); table.clear(pooled); table.clear(modes)
	else
		wanted, pooled, nodes, modes = {}, {}, {}, {}
	end
	local used = 0
	for i, e in ipairs(list) do
		local want = if e.pooled then isNight == true elseif e.night then isNight == true and e.base ~= false else e.base ~= false
		if want and e.pos and origin then
			local d = (e.pos - origin).Magnitude
			if d == d and d <= tier.cull then
				-- Hero lights read from further away: they rank as if 40% nearer.
				used += 1
				local node = nodes[used]
				if not node then node = {}; nodes[used] = node end
				node.i, node.d, node.rank = i, d, if e.hero then d * 0.6 else d
				table.insert(if e.pooled then pooled else wanted, node)
			end
		end
	end
	table.sort(wanted, byRank)
	table.sort(pooled, byRank)
	local lit, shadows = 0, 0
	local poolCap = math.min(tier.pool, tier.lights)
	local glow = 0
	for _, w in ipairs(pooled) do
		if glow >= poolCap then break end
		modes[w.i] = "on"; glow += 1
	end
	for _, w in ipairs(wanted) do
		if lit + glow >= tier.lights then break end
		local e = list[w.i]
		if tier.shadows == "hero" and e.hero and w.d <= tier.heroShadowRange then
			modes[w.i] = "shadow"; shadows += 1
		else
			modes[w.i] = "on"
		end
		lit += 1
	end
	return modes, {lit = lit, pooled = glow, shadows = shadows}
end
-- Brightness a managed light burns at (night boost, ceiling).
function L.lightBrightness(base, nightness)
	base = tonumber(base) or 0
	if base ~= base or base < 0 then base = 0 end
	local n = math.clamp(tonumber(nightness) or 0, 0, 1)
	return math.min(base * (1 + L.NIGHT_BOOST * n), math.max(base, L.MAX_LIGHT_BRIGHTNESS))
end

------------------------------------------------------------------------------
-- Glow sites: lamp / lantern meshes (Shape attribute) that carry no light of
-- their own get one of the tier's pooled client lights at night, nearest
-- first. A part can opt in with the GlowSite attribute ("lantern" | "window" |
-- "stall"), e.g. future lit windows.
------------------------------------------------------------------------------
L.GLOW_SHAPES = {Lantern = "lantern", HangingLantern = "lantern", TwinLantern = "lantern", Torch = "lantern",
	StreetLamp = "lantern", LampPost = "lantern", MarketStall = "stall"}
L.GLOW_KINDS = {
	lantern = {color = "FFD9A0", brightness = 0.9, range = 14},
	window = {color = "FFC98A", brightness = 0.7, range = 12},
	stall = {color = "FFD3A0", brightness = 0.6, range = 12},
}

------------------------------------------------------------------------------
-- Lit windows (World Art pass 2, §40). Every building host carries
-- WindowGlow = "x,y,z,w,h,ry;..." (pane rects in the host frame: centre of the
-- glass's outer face, size, and the yaw that turns -Z outward). After dusk the
-- director shows warm emissive panes (local Neon parts: no light, no shadow,
-- no collision) on the nearest buildings, within the tier's caps; most panes
-- of a house are lit (L.WINDOW_LIT, deterministic per pane), so a street reads
-- as lived in. The building host is also a GlowSite "window" for the pooled
-- spill lights above. Day: no panes.
------------------------------------------------------------------------------
L.WindowTiers = {
	High = {buildings = 40, panes = 300, range = 260},
	Balanced = {buildings = 20, panes = 140, range = 180},
	Performance = {buildings = 10, panes = 70, range = 120},
}
-- Phones forge building shells only within 120 studs (forge.client.lua
-- BUILDING_RADIUS.shell): window panes never reach past it (§40 QC M3).
L.WINDOW_MOBILE_RANGE = 120
L.WINDOW_COLOR = "FFC774"
L.WINDOW_TRANSPARENCY = 0.12
L.WINDOW_LIT = 0.8
-- Pane list from a WindowGlow string (malformed entries are skipped; at most 32).
function L.parseWindows(text)
	local out = {}
	if type(text) ~= "string" then return out end
	for entry in string.gmatch(text, "[^;]+") do
		local v = {}
		for x in string.gmatch(entry, "[^,]+") do v[#v + 1] = tonumber(x) end
		if #v == 6 and v[4] and v[4] > 0 and v[5] and v[5] > 0 then
			local good = true
			for k = 1, 6 do if v[k] ~= v[k] or math.abs(v[k]) > 200 then good = false end end
			if good then out[#out + 1] = v end
		end
		if #out >= 32 then break end
	end
	return out
end
-- Is pane i of a building lit tonight? A fixed hash of the building's seed
-- (its position) and the pane, so a window never flickers between updates.
function L.windowLit(seed, i)
	local h = math.sin((tonumber(seed) or 0) * 12.9898 + i * 78.233) * 43758.5453
	return h - math.floor(h) < L.WINDOW_LIT
end
-- Which buildings show their panes: entries {pos, count}; nearest first
-- within the tier's range (capped by rangeCap when given: phones), until the building or pane cap. Returns the
-- indices chosen (into `out` when given) and the pane total.
function L.selectWindows(list, origin, tierName, isNight, out, rangeCap)
	local tier = L.WindowTiers[tierName] or L.WindowTiers[L.DEFAULT_TIER]
	out = out or {}
	table.clear(out)
	if not isNight or not origin then return out, 0 end
	local range = if type(rangeCap) == "number" then math.min(tier.range, rangeCap) else tier.range
	local cand = {}
	for i, e in ipairs(list) do
		local d = e.pos and (e.pos - origin).Magnitude
		if d and d == d and d <= range then cand[#cand + 1] = {i = i, d = d} end
	end
	table.sort(cand, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
	local panes = 0
	for _, c in ipairs(cand) do
		if #out >= tier.buildings then break end
		local n = list[c.i].count or 0
		if panes + n > tier.panes then break end
		out[#out + 1] = c.i
		panes += n
	end
	return out, panes
end

------------------------------------------------------------------------------
-- Weather (§50 Ambience). The server publishes ONE workspace attribute,
-- IsleWeather (shared/Ambience.lua A.encode: "1|slot|Hub=Clear,...|Region@t"),
-- from a deterministic schedule, so every player sees the same sky. The
-- director reads it, picks the state for its context key and blends a small
-- set of weather deltas (L.WEATHER, tau L.WEATHER_TAU) on top of L.target:
-- rain dims the sun, thickens the haze and raises the specular scale (the
-- "wet sheen" on stone and timber), fog thickens the Atmosphere, snow
-- brightens and desaturates. Lightning is a world event in the same attribute
-- (the region and server time of the last strike); the director adds
-- L.flashAt(seconds since the strike) to the written ExposureCompensation
-- (never to the blended state) unless reduced motion is on.
------------------------------------------------------------------------------
L.WEATHER_ATTR = "IsleWeather"
L.WEATHER_STATES = {"Clear", "Breezy", "Rain", "Storm", "Fog", "Snow"}
-- Delta keys: bright (Brightness ×(1 + v)), exposure (+), density (+), haze
-- (+), grey (AtmColor toward L.WEATHER_GREY), specular (+, wet sheen),
-- saturation (+), contrast (+), soft (+ ShadowSoftness), rays (RaysIntensity ×(1 + v)).
L.WEATHER_KEYS = {"bright", "exposure", "density", "haze", "grey", "specular", "saturation", "contrast", "soft", "rays"}
L.WEATHER = {
	Clear = {},
	Breezy = {haze = -0.1, contrast = 0.01},
	Rain = {bright = -0.22, exposure = -0.06, density = 0.08, haze = 0.7, grey = 0.35, specular = 0.4, saturation = -0.08, soft = 0.25, rays = -0.8},
	Storm = {bright = -0.38, exposure = -0.12, density = 0.14, haze = 1.1, grey = 0.55, specular = 0.5, saturation = -0.14, contrast = 0.04, soft = 0.45, rays = -1},
	Fog = {bright = -0.1, density = 0.18, haze = 1.2, grey = 0.3, saturation = -0.06, soft = 0.3, rays = -0.6},
	Snow = {bright = 0.04, exposure = 0.04, density = 0.1, haze = 0.8, grey = 0.25, specular = 0.1, saturation = -0.1, soft = 0.3, rays = -0.5},
}
L.WEATHER_GREY = "A9B2BC"
L.WEATHER_TAU = 5 -- seconds; weather eases in over ~15 s
L.FLASH_EXPOSURE, L.FLASH_LENGTH, L.FLASH_CEILING = 0.6, 0.7, 1
-- Parse the IsleWeather attribute (malformed -> nil). Only called when the
-- attribute changes (never per frame).
function L.parseWeather(text)
	if type(text) ~= "string" then return nil end
	local version, slot, list, strike = string.match(text, "^(%d+)|(%-?%d+)|([^|]*)|?(.*)$")
	if version ~= "1" then return nil end
	local out = {slot = tonumber(slot), regions = {}}
	for key, state in string.gmatch(list, "(%w+)=(%w+)") do
		if L.WEATHER[state] then out.regions[key] = state end
	end
	local region, at = string.match(strike or "", "^(%w+)@([%d%.]+)$")
	if region then out.strikeRegion, out.strikeAt = region, tonumber(at) end
	return out
end
-- The weather state a context key sees (interiors and unknown keys: Clear).
function L.weatherFor(parsed, key)
	if type(parsed) ~= "table" or not L.Profiles[key] or L.Profiles[key].interior then return "Clear" end
	return parsed.regions and parsed.regions[key] or "Clear"
end
-- Blend a delta vector (numbers keyed by L.WEATHER_KEYS) toward a state's.
function L.blendWeather(cur, state, alpha)
	local goal = L.WEATHER[state] or L.WEATHER.Clear
	for _, k in ipairs(L.WEATHER_KEYS) do
		local a, b = cur[k] or 0, goal[k] or 0
		local v = a + (b - a) * alpha
		cur[k] = if math.abs(v - b) < 1e-3 then b else v
	end
	return cur
end
local function clampField(key, v)
	local f = L.FieldByKey[key]
	return math.clamp(v, f.min, f.max)
end
-- Apply a delta vector to a composed state (mutates and returns `out`; every
-- field stays inside its L.FIELDS range).
function L.applyWeather(out, w)
	if type(w) ~= "table" then return out end
	out.Brightness = clampField("Brightness", out.Brightness * (1 + (w.bright or 0)))
	out.ExposureCompensation = clampField("ExposureCompensation", out.ExposureCompensation + (w.exposure or 0))
	out.AtmDensity = clampField("AtmDensity", out.AtmDensity + (w.density or 0))
	out.AtmHaze = clampField("AtmHaze", out.AtmHaze + (w.haze or 0))
	if (w.grey or 0) > 0 then out.AtmColor = out.AtmColor:Lerp(rgb(L.WEATHER_GREY), math.clamp(w.grey, 0, 1)) end
	out.EnvironmentSpecularScale = clampField("EnvironmentSpecularScale", out.EnvironmentSpecularScale + (w.specular or 0))
	out.GradeSaturation = clampField("GradeSaturation", out.GradeSaturation + (w.saturation or 0))
	out.GradeContrast = clampField("GradeContrast", out.GradeContrast + (w.contrast or 0))
	out.ShadowSoftness = clampField("ShadowSoftness", out.ShadowSoftness + (w.soft or 0))
	out.RaysIntensity = clampField("RaysIntensity", out.RaysIntensity * math.max(0, 1 + (w.rays or 0)))
	return out
end
-- Lightning: a double flicker over L.FLASH_LENGTH seconds (0 outside it).
function L.flashAt(dt)
	if type(dt) ~= "number" or dt ~= dt or dt < 0 or dt > L.FLASH_LENGTH then return 0 end
	if dt < 0.08 then return 1 end
	if dt < 0.18 then return 0.25 end
	if dt < 0.28 then return 0.85 end
	return 0.85 * (1 - (dt - 0.28) / (L.FLASH_LENGTH - 0.28))
end
function L.flashExposure(base, flash)
	return math.min(base + L.FLASH_EXPOSURE * math.clamp(flash, 0, 1), L.FLASH_CEILING)
end

------------------------------------------------------------------------------
-- Validation (every composed / blended state; verify-lighting).
------------------------------------------------------------------------------
function L.valid(state)
	if type(state) ~= "table" then return false, "no state" end
	for _, f in ipairs(L.FIELDS) do
		local v = state[f.key]
		if f.kind == "color" then
			if typeof(v) ~= "Color3" then return false, f.key .. " is not a colour" end
			for _, ch in ipairs({v.R, v.G, v.B}) do
				if ch ~= ch or ch < -1e-6 or ch > 1 + 1e-6 then return false, f.key .. " channel out of range" end
			end
			if f.maxLum and lum(v) > f.maxLum + 1e-6 then return false, f.key .. " too bright" end
			if f.minLum and lum(v) < f.minLum - 1e-6 then return false, f.key .. " too dark" end
		else
			if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return false, f.key .. " is not finite" end
			if v < f.min - 1e-6 or v > f.max + 1e-6 then return false, f.key .. " out of range (" .. v .. ")" end
		end
	end
	return true
end

return L
