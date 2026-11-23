-- Lighting & Atmosphere (docs/DEPTH-CONTRACT.md §35).
-- Part A: exactly one writer of Lighting (lighting.client.lua); no other script
--   references the Lighting service. GUI is never touched by the director and
--   the Sky Chart / thumbnail ViewportFrames keep their own lighting.
-- Part B: shared/LightingProfiles.lua: every region and interior has a
--   profile; every composed state at every clock and tier is finite and in
--   range; the isle clock agrees with the sidebar clock; blends converge
--   without overshoot; light budgets per tier; tier defaults per device.
-- Part C: runs lighting.client.lua headlessly (real Lighting / Workspace
--   instances, mocked player and Heartbeat): one of each owned effect, foreign
--   effects removed, tier setting published and honoured, light caps, night
--   lamps and glow pool, region blending.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(a, b, case) assert(a == b, case .. " expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end
local function load(path, env)
	return luau.load(fs.readFile(path), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local L = load("shared/LightingProfiles.lua", {Color3 = Color3})
local Theme = load("shared/UiTheme.lua", {Color3 = Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2,
	ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint})

------------------------------------------------------------------------------
-- Part A: one writer.
------------------------------------------------------------------------------
local sources = {}
for _, dir in {".", "shared", "art"} do
	for _, name in fs.readDir(dir) do
		if string.match(name, "%.lua$") then table.insert(sources, if dir == "." then name else dir .. "/" .. name) end
	end
end
ok(#sources >= 30, "scanned the game scripts (" .. #sources .. ")")
local patterns = {'GetService%(%s*["\']Lighting["\']%s*%)', "game%.Lighting", 'FindFirstChild%(%s*["\']Lighting["\']', 'game%[%s*["\']Lighting["\']%s*%]'}
local writers = {}
for _, path in sources do
	local src = fs.readFile(path)
	for _, pat in patterns do
		if string.find(src, pat) then writers[path] = true end
	end
end
ok(writers["lighting.client.lua"] == true, "the director reaches Lighting")
for path in writers do eq(path, "lighting.client.lua", "only the director references the Lighting service") end
local director = fs.readFile("lighting.client.lua")
local _, refs = string.gsub(director, 'GetService%("Lighting"%)', "")
eq(refs, 1, "the director takes the Lighting service once")
for _, word in {"ViewportFrame", "PlayerGui", "ScreenGui", "SurfaceGui", "BillboardGui", "CurrentCamera.Parent"} do
	ok(not string.find((string.gsub(director, "%-%-[^\n]*", "")), word, 1, true), "the director never touches " .. word)
end
local world = (string.gsub(fs.readFile("world.server.lua"), "%-%-[^\n]*", ""))
ok(not string.find(world, "ClockTime", 1, true) and not string.find(world, "Atmosphere", 1, true), "the old server day-night cycle is gone")
local mapArt = fs.readFile("shared/MapArt.lua")
local _, vpLit = string.gsub(mapArt, 'make%("ViewportFrame"[^\n]*\n[^\n]*Ambient = rgb%(A%.ambient%), LightColor = rgb%(A%.sun%)', "")
ok(vpLit >= 2, "Sky Chart ViewportFrames carry their own Ambient / LightColor (" .. vpLit .. ")")

------------------------------------------------------------------------------
-- Part B: profiles.
------------------------------------------------------------------------------
local keys = {}
for _, k in L.REGION_KEYS do keys[k] = true end
for _, k in L.INTERIOR_KEYS do keys[k] = true end
for _, region in Data.Regions do ok(L.Profiles[region.id] ~= nil and keys[region.id], region.id .. " has a lighting profile") end
for _, island in Theme.WorldMap.islands do ok(L.Profiles[island.region] ~= nil, island.name .. " (" .. island.region .. ") has a profile") end
for _, k in {"Home", "Skyways", "Dungeon", "Lair", "Minigame"} do ok(L.Profiles[k] ~= nil, k .. " has a profile") end
for k, p in L.Profiles do
	ok(keys[k], k .. " is a listed key")
	ok(type(p.label) == "string" and #p.label > 3, k .. " is labelled")
	for field in p do
		ok(L.FieldByKey[field] ~= nil or ({label = 1, interior = 1, fixedDay = 1, dayFloor = 1, golden = 1, night = 1})[field] ~= nil, k .. "." .. field .. " is a known field")
	end
	eq(p.interior == true, table.find(L.INTERIOR_KEYS, k) ~= nil, k .. " interior flag")
end
-- Every state composed at every clock and tier is finite and in range.
local states = 0
for k in L.Profiles do
	local good, why = L.valid(L.dayLook(k)); ok(good, k .. " day look: " .. tostring(why))
	good, why = L.valid(L.nightLook(k)); ok(good, k .. " night look: " .. tostring(why))
	for _, tier in L.TIER_ORDER do
		for step = 0, 24 * 8 do
			local s = L.target(k, step / 8, tier)
			good, why = L.valid(s)
			assert(good, k .. " at " .. step / 8 .. " (" .. tier .. "): " .. tostring(why))
			states += 1
		end
	end
end
checks += 1
ok(states > 5000, "composed states checked (" .. states .. ")")
for _, bad in {0 / 0, math.huge, -math.huge, "x", nil} do
	ok(L.valid(L.target("Hub", bad, "High")), "a bad clock still composes a valid state")
end
ok(L.valid(L.target("Nowhere", 12, "Nope")), "unknown key / tier fall back")
-- Biomes stay distinct: Gloomhollow is darker and violet next to Meadow; night is darker than day.
local meadow, gloom = L.target("Meadow", 12, "High"), L.target("Gloomhollow", 12, "High")
ok(L.luminance(gloom.OutdoorAmbient) < L.luminance(meadow.OutdoorAmbient), "Gloomhollow is darker than Sunwheel Downs")
ok(gloom.AtmColor.B > gloom.AtmColor.G, "Gloomhollow haze is violet")
for _, k in L.REGION_KEYS do
	local day, night = L.target(k, 13, "High"), L.target(k, 1, "High")
	ok(L.luminance(night.OutdoorAmbient) < L.luminance(day.OutdoorAmbient), k .. " night is darker than day")
	ok(L.luminance(night.OutdoorAmbient) >= 0.12, k .. " night stays readable")
end
local dungeonNoon, dungeonMidnight = L.target("Dungeon", 12, "High"), L.target("Dungeon", 0, "High")
ok(L.distance(dungeonNoon, dungeonMidnight) < 1e-6, "interiors ignore the clock")
local dusk = L.target("Hub", 19, "High")
ok(dusk.ColorShift_Top.R - dusk.ColorShift_Top.B > L.target("Hub", 12, "High").ColorShift_Top.R - L.target("Hub", 12, "High").ColorShift_Top.B, "golden hour warms the sun at dusk")
eq(L.target("Hub", 12, "Performance").BloomIntensity, 0, "Performance drops bloom")
-- QC M3: the ambient a surface actually gets (OutdoorAmbient with GlobalShadows,
-- Ambient without) stays readable on every tier; Performance (no GlobalShadows)
-- lifts Ambient toward OutdoorAmbient up to the floor.
for _, tierName in L.TIER_ORDER do
	local worst, worstKey = math.huge, nil
	for k in L.Profiles do
		for step = 0, 24 * 4 do
			local s = L.target(k, step / 4, tierName)
			local eff = L.luminance(L.effectiveAmbient(s, tierName))
			local floor = math.min(L.READABLE_AMBIENT, L.luminance(s.OutdoorAmbient))
			assert(eff >= floor - 1e-4, tierName .. " " .. k .. " at " .. step / 4 .. ": effective ambient " .. eff .. " below " .. floor)
			if eff < worst then worst, worstKey = eff, k end
		end
	end
	checks += 1
	print(string.format("  %s: darkest effective ambient %.3f (%s)", tierName, worst, worstKey))
end
ok(L.luminance(L.target("Hub", 0, "Performance").Ambient) >= L.READABLE_AMBIENT - 1e-4, "Performance Hub midnight Ambient is lifted to the floor")
ok(L.luminance(L.target("Hub", 0, "High").Ambient) < L.READABLE_AMBIENT, "tiers with GlobalShadows keep the authored Ambient (the lift is Performance-only)")
-- QC L2: looks are memoized per key (unknown keys share the default's).
ok(L.dayLook("Hub") == L.dayLook("Hub") and L.nightLook("Meadow") == L.nightLook("Meadow"), "day / night looks are memoized")
ok(L.dayLook("Nowhere") == L.dayLook(L.DEFAULT_KEY), "unknown keys reuse the default look")
-- QC L3: interiors hold a fixed daytime sky.
for _, k in L.INTERIOR_KEYS do
	local c = L.interiorClock(k)
	ok(c and c >= 9 and c <= 15, k .. " holds a daytime ClockTime (" .. tostring(c) .. ")")
	eq(L.skyClockFor(k, 0), c, k .. " ignores midnight")
	eq(L.skyClockFor(k, 20), c, k .. " ignores dusk")
end
eq(L.interiorClock("Hub"), nil, "outdoor regions have no fixed clock")
eq(L.skyClockFor("Hub", 1), L.skyClock(1), "outdoor regions follow the clock")
-- Bloom never catches white UI on billboards (threshold above 1).
for k in L.Profiles do ok(L.target(k, 0, "High").BloomThreshold > 1 and L.target(k, 12, "High").BloomThreshold > 1, k .. " bloom threshold > 1") end

-- Clock: same hour as the sidebar, night exactly when the sidebar says night.
local t0 = 1700000000
for i = 0, 400 do
	local t = t0 + i * 37
	local cal = Theme.isleClock(t, Data)
	local clock = L.clockAt(t, Data.Calendar)
	ok(clock >= 0 and clock < 24, "clock in range")
	local minutes = math.floor((t - Data.calendarAt(t).dayStart) / Data.Calendar.dayLength * 1440) % 1440
	eq(math.floor(clock * 60 + 1e-6) % 1440, minutes, "isle clock minute matches the sidebar")
	eq(L.dayFactor(clock) < 0.5, cal.night, "night matches the sidebar at " .. cal.clock)
end
local prev = L.skyClock(L.DAWN)
for step = 1, 24 * 60 do
	local c = (L.DAWN + step / 60) % 24
	local s = L.skyClock(c)
	ok(s >= 0 and s < 24, "sky clock in range")
	local d = (s - prev) % 24
	ok(d > 0 and d < 0.05, "sky clock rises continuously")
	prev = s
end
ok(math.abs(L.skyClock(19) - 18) < 1e-9 and math.abs(L.skyClock(6) - 6) < 1e-9, "the sun sets at the sidebar's dusk and rises at dawn")
ok(L.dayFactor(12) == 1 and L.dayFactor(0) == 0, "noon is day, midnight is night")

-- Context.
eq(L.context({LairBoss = "Ashmaw", IsleRegionHere = "Hub"}), "Lair", "lair fight wins")
eq(L.context({DungeonInRun = true}), "Dungeon", "dungeon run")
eq(L.context({MinigameGame = "Siege"}), "Minigame", "minigame match")
eq(L.context({IsleRegionHere = "Tidewater"}), "Tidewater", "region")
eq(L.context({IsleRegionHere = "Dungeon"}), "Skyways", "an interior key is never taken from the region attribute")
eq(L.context({IsleRegionHere = "Bogus"}), "Skyways", "unknown region")
eq(L.context(nil), "Skyways", "no attributes")
eq(L.context({IsleRegionHere = "Hub"}, Vector3.new(0, 42, 1790)), "Dungeon", "Observatory lobby")
eq(L.context({IsleRegionHere = "Home"}, Vector3.new(-2400, 90, 100)), "Minigame", "Skybreach Bastion")
eq(L.context({}, Vector3.new(3700, 300, -3600)), "Lair", "lair arenas")
eq(L.context({IsleRegionHere = "Hub"}, Vector3.new(0, 0, 0)), "Hub", "archipelago")
-- QC L4: an interior attribute with the position outside its zone yields to the position.
eq(L.context({LairBoss = "Ashmaw", IsleRegionHere = "Hub"}, Vector3.new(0, 2, 0)), "Hub", "a stale LairBoss on the archipelago")
eq(L.context({LairBoss = "Ashmaw"}, Vector3.new(3700, 300, -3600)), "Lair", "LairBoss inside the lair zone")
eq(L.context({DungeonInRun = true, IsleRegionHere = "Meadow"}, Vector3.new(400, 2, 0)), "Meadow", "a stale DungeonInRun outside the Observatory")
eq(L.context({DungeonInRun = true}, Vector3.new(0, 42, 1800)), "Dungeon", "DungeonInRun inside the Observatory")
eq(L.context({MinigameGame = "Siege", IsleRegionHere = "Hub"}, Vector3.new(0, 2, 0)), "Hub", "a stale MinigameGame outside the Bastion")
eq(L.context({MinigameGame = "Siege", IsleRegionHere = "Hub"}, Vector3.new(0, 42, 1800)), "Dungeon", "position zone beats a mismatched interior attribute")

-- Blends converge, never overshoot.
eq(L.alphaFor(0, 1), 0, "no time, no blend")
eq(L.alphaFor(0 / 0, 1), 0, "NaN dt is ignored")
eq(L.alphaFor(-1, 1), 0, "negative dt is ignored")
eq(L.alphaFor(1, 0), 1, "zero tau snaps")
ok(L.alphaFor(1e9, 1) == 1, "huge dt lands")
for _, pair in {{"Meadow", "Gloomhollow"}, {"Tempest", "Home"}, {"Dungeon", "Hub"}, {"Lair", "Skyways"}} do
	local a, b = L.target(pair[1], 13, "High"), L.target(pair[2], 13, "High")
	local s = a
	local last = L.distance(s, b)
	local steps = 0
	for i = 1, 15 * 8 do
		s = L.blend(s, b, L.alphaFor(1 / 15, L.REGION_TAU))
		local good, why = L.valid(s); assert(good, "mid-blend state: " .. tostring(why))
		local d = L.distance(s, b)
		assert(d <= last + 1e-9, "blend never moves away from the target")
		last = d
		steps = i
		if d < L.SNAP_DISTANCE then break end
	end
	checks += 1
	ok(last < L.SNAP_DISTANCE and steps / 15 <= 8, pair[1] .. " → " .. pair[2] .. " converges in " .. string.format("%.1f", steps / 15) .. " s")
	ok(L.distance(L.blend(a, b, 0.5), a) > 0 and L.distance(L.blend(a, b, 1), b) < 1e-9, pair[1] .. " → " .. pair[2] .. " blend endpoints")
end

-- Light budget per tier.
local list = {}
for i = 1, 600 do
	local angle, r = i * 2.39996, (i % 97) * 4
	table.insert(list, {pos = Vector3.new(math.cos(angle) * r, (i % 7), math.sin(angle) * r), base = i % 11 ~= 0, night = i % 5 == 0,
		hero = i % 50 == 0, pooled = i % 13 == 0})
end
local origin = Vector3.new(0, 0, 0)
for _, tierName in L.TIER_ORDER do
	local tier = L.Tiers[tierName]
	for _, night in {false, true} do
		local modes, n = L.selectLights(list, origin, tierName, night)
		local lit, pooledLit, shadowed, furthestLit = 0, 0, 0, 0
		for i, mode in modes do
			local e = list[i]
			ok(mode == "on" or mode == "shadow", "mode")
			lit += 1
			if e.pooled then pooledLit += 1; ok(night, "glow pool only at night") end
			if e.night then ok(night, "night lamps only at night") end
			if not e.pooled then ok(e.base, "a light the server switched off stays off (night lamps too)") end
			if mode == "shadow" then shadowed += 1; ok(e.hero and tier.shadows == "hero", "only hero lights cast shadows, only on High") end
			ok(e.pos.Magnitude <= tier.cull, "lit lights are within the cull distance")
			if not e.hero and not e.pooled then furthestLit = math.max(furthestLit, e.pos.Magnitude) end
		end
		ok(lit <= tier.lights, tierName .. " caps lights at " .. tier.lights .. " (" .. lit .. ")")
		ok(lit == tier.lights, tierName .. " fills its budget from a dense world")
		ok(pooledLit <= tier.pool, tierName .. " caps the glow pool")
		eq(n.lit + n.pooled, lit, tierName .. " counts")
		if tierName ~= "High" then eq(shadowed, 0, tierName .. " casts no lamp shadows") end
		-- Nearest first: every unlit candidate (wanted, same class) is further than the furthest lit one.
		for i, e in list do
			if not modes[i] and not e.hero and not e.pooled and (if e.night then night and e.base else e.base) and e.pos.Magnitude <= tier.cull then
				assert(e.pos.Magnitude >= furthestLit - 1e-6, "nearest lights win")
			end
		end
		checks += 1
	end
end
ok(L.Tiers.High.lights > L.Tiers.Balanced.lights and L.Tiers.Balanced.lights > L.Tiers.Performance.lights, "tiers step down")
ok(not L.Tiers.Performance.globalShadows and not L.Tiers.Performance.bloom and not L.Tiers.Performance.rays and not L.Tiers.Performance.grade, "Performance: no shadows, no post FX")
ok(L.Tiers.High.globalShadows and L.Tiers.High.bloom and L.Tiers.High.rays and L.Tiers.High.grade, "High: shadows and post FX")
eq(next((L.selectLights({}, origin, "High", true))), nil, "empty world")
-- QC L1: a reused scratch gives the same answer as fresh tables, with no stale modes.
do
	local scratch = {}
	for _, tierName in L.TIER_ORDER do
		for _, night in {false, true} do
			local fresh = L.selectLights(list, origin, tierName, night)
			local reused = L.selectLights(list, origin, tierName, night, scratch)
			for i in list do assert(fresh[i] == reused[i], "scratch reuse matches at " .. i) end
		end
	end
	local nodes = scratch.nodes
	L.selectLights(list, origin, "High", true, scratch)
	ok(scratch.nodes == nodes and #nodes > 0, "scratch nodes are reused, not reallocated")
	eq(next((L.selectLights({}, origin, "High", true, scratch))), nil, "a reused scratch carries no stale modes")
end
eq(L.lightBrightness(1, 0), 1, "day brightness is authored")
ok(math.abs(L.lightBrightness(1, 1) - 1.3) < 1e-9, "night boost")
eq(L.lightBrightness(1.4, 1), 1.5, "night boost is capped")
eq(L.lightBrightness(0 / 0, 1), 0, "NaN brightness is zero")

-- Tier defaults per device.
eq(L.defaultTier({touch = true, keyboard = false}), "Balanced", "phones default to Balanced")
eq(L.defaultTier({touch = false, keyboard = true, viewportX = 1920}), "High", "desktops default to High")
eq(L.defaultTier({keyboard = true, quality = 2}), "Performance", "a low saved quality picks Performance")
eq(L.defaultTier({keyboard = true, quality = 5}), "Balanced", "a middling saved quality picks Balanced")
eq(L.defaultTier({gamepad = true, viewportX = 1920}), "High", "consoles default to High")
eq(L.readTier("Performance", {touch = true}), "Performance", "a chosen tier wins over the device")
eq(L.readTier("Ultra", {touch = true}), "Balanced", "an unknown tier falls back to the device default")
-- QC L6: the saved-settings whitelist (Data.PlayerSettings, used by the server's
-- `setting` verb and the join re-apply) knows every graphics tier and nothing else.
do
	local S = Data.PlayerSettings
	local graphics = S.byAttr[L.SETTING_ATTR]
	ok(graphics ~= nil and graphics.kind == "enum", "the graphics tier is a saved setting")
	eq(#graphics.values, #L.TIER_ORDER, "saved tiers match L.TIER_ORDER")
	for i, id in L.TIER_ORDER do eq(graphics.values[i], id, "saved tier " .. i) end
	for _, id in L.TIER_ORDER do
		local attr, value = S.parse(L.SETTING_ATTR .. "=" .. id)
		ok(attr == L.SETTING_ATTR and value == id, id .. " parses")
	end
	eq(S.parse(L.SETTING_ATTR .. "=Ultra"), nil, "an unknown tier is refused")
	eq(S.parse("LairBoss=Ashmaw"), nil, "a non-setting attribute is refused")
	eq(S.parse("IsleSettingMinimap=1"), nil, "a toggle needs true / false")
	eq(select(2, S.parse("IsleSettingMinimap=false")), false, "toggles parse to booleans")
	eq(S.parse(string.rep("x", 80)), nil, "an oversized item is refused")
	local clean = S.sanitize({IsleSettingGraphics = "Performance", IsleSettingXpDrops = false, Coins = 9, IsleSettingMinimap = "maybe"})
	eq(clean.IsleSettingGraphics, "Performance", "sanitize keeps a valid tier")
	eq(clean.IsleSettingXpDrops, false, "sanitize keeps a valid toggle")
	ok(clean.Coins == nil and clean.IsleSettingMinimap == nil, "sanitize drops unknown keys and invalid values")
	eq(next(S.sanitize("junk")), nil, "a corrupt saved map sanitizes to empty")
end

------------------------------------------------------------------------------
-- Part C: the director, headless.
------------------------------------------------------------------------------
local function signal()
	local listeners = {}
	return {Connect = function(_, f) table.insert(listeners, f) return {Disconnect = function() end} end,
		Fire = function(_, ...) for _, f in listeners do f(...) end end}
end
local Lighting = roblox.Instance.new("Lighting")
-- A stale effect from an old place file: the director removes it.
local stale = roblox.Instance.new("BloomEffect"); stale.Name = "Old bloom"; stale.Parent = Lighting
local stale2 = roblox.Instance.new("Atmosphere"); stale2.Parent = Lighting
local ws = roblox.Instance.new("Workspace")
local isles = roblox.Instance.new("Folder"); isles.Name = "AetherIsles"; isles.Parent = ws
local function part(name, pos, parent)
	local p = roblox.Instance.new("Part")
	p.Name, p.Anchored, p.CFrame, p.Size = name, true, CFrame.new(pos), Vector3.new(1, 1, 1)
	p.Parent = parent or isles
	return p
end
-- 120 authored lights in a line, every 4th a night lamp, a few shadow heroes.
local authored, nightLamps = {}, {}
for i = 1, 120 do
	local host = part("Lamp" .. i, Vector3.new(i * 5, 2, 0))
	local l = roblox.Instance.new(if i % 4 == 0 then "SpotLight" else "PointLight")
	l.Brightness, l.Range, l.Shadows = 1, 14, i % 30 == 1
	if i % 4 == 0 then l.Enabled = false; l:SetAttribute("NightLight", true); table.insert(nightLamps, l) end
	l.Parent = host
	table.insert(authored, l)
end
-- A light the server switched off (placement glow cap) stays off.
authored[3].Enabled = false
-- Lantern meshes without lights (glow sites) and one with its own light.
local sites = {}
for i = 1, 12 do
	local p = part("Lantern site " .. i, Vector3.new(i * 6, 3, 8))
	p:SetAttribute("Shape", "Lantern")
	table.insert(sites, p)
end
-- An unmanaged world (monster glow, characters) is ignored.
local outside = part("Monster", Vector3.new(1, 1, 1), ws)
local monsterGlow = roblox.Instance.new("PointLight"); monsterGlow.Parent = outside
local character = roblox.Instance.new("Model")
local root = part("HumanoidRootPart", Vector3.new(0, 2, 0), character)
character.Parent = ws
local attrs = {IsleRegionHere = "Hub"}
local attrSets = 0
local playerMock = {Character = character, Name = "Tester",
	GetAttribute = function(_, k) return attrs[k] end,
	SetAttribute = function(_, k, v) attrs[k] = v; attrSets += 1 end}
local heartbeat = signal()
local clockNow = Data.Calendar.epoch + 400 * Data.Calendar.dayLength + Data.Calendar.dayLength * 0.5 -- isle noon
local services = {
	Players = {LocalPlayer = playerMock},
	RunService = {Heartbeat = heartbeat},
	Lighting = Lighting,
	ReplicatedStorage = {WaitForChild = function(_, name) return name end},
	UserInputService = {TouchEnabled = true, KeyboardEnabled = false, GamepadEnabled = false},
}
local env = {
	game = {GetService = function(_, name) return services[name] end},
	workspace = ws, Instance = roblox.Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = roblox.Enum,
	typeof = roblox.typeof or typeof,
	require = function(name) if name == "AetherLighting" then return L elseif name == "AetherData" then return Data end error("unexpected require " .. tostring(name)) end,
	os = {time = function() return clockNow end, clock = os.clock},
	task = {defer = function(f) f() end, spawn = function(f) f() end},
}
local D = luau.load(director, {debugName = "lighting.client.lua", environment = env, injectGlobals = true})()
local function run(seconds)
	local n = math.ceil(seconds * 30)
	for _ = 1, n do heartbeat:Fire(1 / 30) end
end
local function count(class)
	local n = 0
	for _, c in Lighting:GetChildren() do if c.ClassName == class then n += 1 end end
	return n
end
eq(attrs.IsleSettingGraphics, "Balanced", "the device default (phone) is published as the setting")
for _, class in {"Atmosphere", "Sky", "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect"} do eq(count(class), 1, "exactly one " .. class) end
ok(stale.Parent == nil and stale2.Parent == nil, "foreign Lighting effects are removed")
for _, c in Lighting:GetChildren() do ok(c:GetAttribute("AetherLightingDirector") == true, c.Name .. " is owned by the director") end
run(4)
local function litCount()
	local n = 0
	for _, l in authored do if l.Enabled then n += 1 end end
	return n
end
-- Noon, Balanced.
ok(math.abs(Lighting.ClockTime - L.skyClock(12)) < 0.01, "ClockTime follows the isle clock (" .. Lighting.ClockTime .. ")")
eq(Lighting.GlobalShadows, true, "Balanced keeps sun shadows")
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
eq(rays.Enabled, false, "Balanced drops sun rays")
ok(litCount() <= L.Tiers.Balanced.lights, "Balanced caps world lights (" .. litCount() .. ")")
for _, l in nightLamps do eq(l.Enabled, false, "night lamps are dark at noon") end
eq(authored[3].Enabled, false, "a light the server switched off stays off")
for _, l in authored do eq(l.Shadows, false, "Balanced: no lamp shadows") end
eq(monsterGlow.Enabled, true, "lights outside the static world are left alone")
ok(L.distance(D.state, L.target("Hub", D.clock, "Balanced")) < 0.01, "Hub look applied")
ok(math.abs(Lighting.Brightness - D.state.Brightness) < 1e-3 and Lighting:FindFirstChildOfClass("Atmosphere").Density == Lighting:FindFirstChildOfClass("Atmosphere").Density, "Lighting reflects the state")
-- Settings: the player picks Performance.
attrs.IsleSettingGraphics = "Performance"
run(1)
eq(Lighting.GlobalShadows, false, "Performance: no shadows")
eq(Lighting:FindFirstChildOfClass("BloomEffect").Enabled, false, "Performance: no bloom")
eq(Lighting:FindFirstChildOfClass("ColorCorrectionEffect").Enabled, false, "Performance: no grade")
ok(litCount() <= L.Tiers.Performance.lights, "Performance caps world lights (" .. litCount() .. ")")
eq(attrs.IsleSettingGraphics, "Performance", "the choice persists on the player")
-- High at midnight: night lamps light near the player, glow pool fills, heroes cast shadows.
attrs.IsleSettingGraphics = "High"
clockNow = Data.Calendar.epoch + 400 * Data.Calendar.dayLength -- isle midnight (dawn is 6:00)
run(1)
eq(Lighting.GlobalShadows, true, "High: shadows")
eq(rays.Enabled, true, "High: sun rays")
ok(litCount() <= L.Tiers.High.lights and litCount() >= 20, "High caps world lights (" .. litCount() .. ")")
local lampsLit = 0
for _, l in nightLamps do if l.Enabled then lampsLit += 1; ok(l.Brightness > 1 and l.Brightness <= 1.5, "night lamps burn brighter, capped") end end
ok(lampsLit >= 5, "night lamps light after dusk (" .. lampsLit .. ")")
local shadowed = 0
for _, l in authored do if l.Shadows then shadowed += 1 end end
ok(shadowed >= 1 and shadowed <= 4, "High keeps the few hero shadows (" .. shadowed .. ")")
local pool = ws:FindFirstChild("IsleLightingPool")
ok(pool ~= nil, "glow pool created")
local glowing = 0
for _, host in pool:GetChildren() do local l = host:FindFirstChildOfClass("PointLight"); if l.Enabled then glowing += 1 end; eq(l.Shadows, false, "pool lights cast no shadows") end
ok(glowing >= 1 and glowing <= L.Tiers.High.pool, "lantern meshes glow, capped (" .. glowing .. ")")
-- Far away, everything culls.
root.CFrame = CFrame.new(Vector3.new(-5000, 2, 5000))
attrs.IsleRegionHere = "Skyways"
run(1)
eq(litCount(), 0, "distant lights are culled")
-- Region change blends smoothly toward Gloomhollow.
root.CFrame = CFrame.new(Vector3.new(0, 2, 0))
attrs.IsleRegionHere = "Gloomhollow"
local before = D.state
run(0.3)
eq(D.key, "Skyways", "a region change waits out the hold (no flicker)")
run(0.7)
eq(D.key, "Gloomhollow", "the new region takes over")
local mid = D.state
run(0.2)
ok(L.distance(mid, L.target("Gloomhollow", D.clock, "High")) > 0.01, "the change blends, not snaps")
run(6)
ok(L.distance(D.state, L.target("Gloomhollow", D.clock, "High")) < 0.01, "the blend converges")
ok(L.valid(D.state), "blended state valid")
ok(L.distance(before, D.state) > 0.05, "Gloomhollow looks different")
-- A stale LairBoss while the player stands on the archipelago keeps the region (QC L4).
attrs.LairBoss = "Ashmaw"
run(0.3)
eq(D.key, "Gloomhollow", "LairBoss outside the lair zone does not switch the look")
-- Teleport into a lair switches at once, and the lair holds a daytime sun (QC L3).
root.CFrame = CFrame.new(Vector3.new(3700, 300, -3600))
run(0.3)
eq(D.key, "Lair", "lair context switches without the hold")
ok(math.abs(Lighting.ClockTime - L.interiorClock("Lair")) < 0.01, "the lair's ClockTime is fixed daytime at isle midnight (" .. Lighting.ClockTime .. ")")
root.CFrame = CFrame.new(Vector3.new(0, 2, 0))
attrs.LairBoss = nil
run(0.3)
ok(math.abs(Lighting.ClockTime - L.skyClock(D.clock)) < 0.01, "leaving the lair restores the isle clock")
-- A foreign effect added later is swept.
local late = roblox.Instance.new("ColorCorrectionEffect"); late.Parent = Lighting
run(11)
eq(late.Parent, nil, "late foreign effects are swept")
eq(count("ColorCorrectionEffect"), 1, "still one grade")
-- Removed lights drop out of the budget.
authored[1].Parent = nil
run(1)
eq(D.lights.byLight[authored[1]], nil, "a removed light drops out of the budget")

-- QC M1: a light the client culled, then the server switched off, stays off
-- when the player comes back (both Enabled values were false: no diff).
do
	local host = part("Intent lamp", Vector3.new(0, 3, 6))
	local l = roblox.Instance.new("PointLight")
	l.Brightness, l.Range = 1, 12
	l:SetAttribute("LightWanted", true)
	l.Parent = host
	run(11) -- rescan registers it (no DescendantAdded headless)
	eq(l.Enabled, true, "an intent lamp near the player is lit")
	root.CFrame = CFrame.new(Vector3.new(-5000, 2, 5000))
	run(1)
	eq(l.Enabled, false, "the client culls it at distance")
	-- The server switches it off (as homePlacement.relight does).
	l.Enabled = false
	l:SetAttribute("LightWanted", false)
	run(1)
	root.CFrame = CFrame.new(Vector3.new(0, 2, 0))
	run(1)
	eq(l.Enabled, false, "a culled light the server switched off stays off when the player returns")
	-- And the server switching it back on while culled lights it on return.
	root.CFrame = CFrame.new(Vector3.new(-5000, 2, 5000))
	run(1)
	l:SetAttribute("LightWanted", true)
	run(1)
	root.CFrame = CFrame.new(Vector3.new(0, 2, 0))
	run(1)
	eq(l.Enabled, true, "a culled light the server switched back on lights on return")
	-- A night lamp the server does not want stays dark at night too.
	local lamp = nightLamps[1]
	lamp:SetAttribute("LightWanted", false)
	run(1)
	eq(lamp.Enabled, false, "a night lamp with LightWanted = false stays dark at night")
	lamp:SetAttribute("LightWanted", true)
	run(1)
end

-- QC M2: a glow site whose own light arrives later stops drawing a pooled light.
do
	local lantern = part("Late lantern", Vector3.new(2, 3, 2))
	lantern:SetAttribute("Shape", "Lantern")
	run(11)
	ok(D.lights.bySite[lantern] ~= nil, "a lantern mesh without a light is a glow site")
	local own = roblox.Instance.new("PointLight")
	own.Brightness, own.Range = 0.8, 10
	own.Parent = lantern
	run(11)
	eq(D.lights.bySite[lantern], nil, "its own light (added after the part) removes the glow site")
	for _, site in D.lights.sites do ok(site.part ~= lantern, "the dropped site left the site list") end
	for _, entry in D.lights.pool do ok(entry.site == nil or entry.site.part ~= lantern, "no pooled light doubles the lantern") end
	ok(D.lights.byLight[own] ~= nil, "the lantern's own light is managed")
	-- Sibling case: the light lands in another part of the same small model (rescan re-check).
	local model = roblox.Instance.new("Model"); model.Name = "Lamp post"; model.Parent = isles
	local head = part("Lamp head", Vector3.new(-2, 3, 2), model)
	head:SetAttribute("Shape", "StreetLamp")
	local pole = part("Lamp pole", Vector3.new(-2, 1, 2), model)
	run(11)
	ok(D.lights.bySite[head] ~= nil, "a lamp post without a light is a glow site")
	local sibling = roblox.Instance.new("PointLight"); sibling.Parent = pole
	run(11)
	eq(D.lights.bySite[head], nil, "a light in a sibling part of the small model removes the glow site")
end

-- QC L1: positions of anchored hosts are cached between rescans.
do
	local rec = D.lights.byLight[authored[2]]
	ok(rec and rec.pos ~= nil, "an anchored light caches its position")
	local entries = D.lights.entries
	run(1)
	ok(D.lights.entries == entries, "the entry list is reused between updates")
end

print("Lighting: " .. checks .. " checks.")
print("SUITE-END verify-lighting.luau")
