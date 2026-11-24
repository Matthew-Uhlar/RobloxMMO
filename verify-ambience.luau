-- Ambience layer (docs/DEPTH-CONTRACT.md §50).
-- Part A: shared/Ambience.lua budgets: every tier's caps, monotonic
--   High >= Balanced >= Lite (phones) >= Performance, what each tier may
--   create (parts / emitters) inside its caps, culling radii inside the
--   forge's build radii, sway shapes that exist in the catalogs.
-- Part B: weather: the schedule is deterministic (two loads, two "servers"
--   agree), weights / cold regions, encode <-> L.parseWeather, lightning
--   strikes, the weather script is cosmetic (one attribute), and the lighting
--   deltas keep every composed state valid; the director honours the
--   attribute, the flash and reduced motion.
-- Part C: skill VFX rules: rarity pillar colours = Data.Rarity, sparks for
--   every strike fx, XP orb counts.
-- Part D: source checks: no allocation between FRAME-BEGIN / FRAME-END, one
--   Heartbeat, no Lighting / GUI writes, reduced-motion guards.
-- Part E: ambience.client.lua headless: tier budgets at runtime (High, Lite
--   phone, Performance), culling radii, sway pivots, weather emitters,
--   strikes, reduced motion, rarity pillars, level-up, XP orbs, interiors.
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
local A = load("shared/Ambience.lua")

------------------------------------------------------------------------------
-- Part A: budgets.
------------------------------------------------------------------------------
local FIELDS = {"emitters", "rateScale", "parts", "sway", "swayHz", "swayRadius", "sourceRadius", "sources", "waterRadius", "foam", "falls",
	"clouds", "birds", "flocks", "orbs", "beams", "rain", "splashes", "fog", "bolts"}
eq(#A.TIER_ORDER, 4, "four budget sets")
for _, key in A.TIER_ORDER do
	local b = A.Budgets[key]
	ok(b ~= nil, key .. " has a budget")
	for _, f in FIELDS do ok(type(b[f]) == "number" and b[f] >= 0, key .. "." .. f .. " is a number") end
	for f in b do ok(table.find(FIELDS, f) ~= nil, key .. "." .. f .. " is a known budget field") end
	local plan, parts = A.partPlan(b)
	ok(parts <= b.parts, key .. ": planned parts " .. parts .. " <= " .. b.parts)
	local eplan, emitters = A.emitterPlan(b)
	ok(emitters <= b.emitters, key .. ": planned emitters " .. emitters .. " <= " .. b.emitters)
	ok(b.swayHz >= 10 and b.swayHz <= 30, key .. " sway rate 10-30 Hz")
	ok(b.rateScale > 0 and b.rateScale <= 1, key .. " rate scale")
	ok(b.clouds >= 1 and b.clouds <= 3, key .. " cloud layers 1-3")
	ok(b.birds == 0 or b.flocks > 0, key .. " birds need flocks")
	ok(plan.anchors == 4 and eplan.fixed >= 3, key .. " plan shapes")
end
for i = 2, #A.TIER_ORDER do
	local hi, lo = A.Budgets[A.TIER_ORDER[i - 1]], A.Budgets[A.TIER_ORDER[i]]
	for _, f in FIELDS do ok(hi[f] >= lo[f], A.TIER_ORDER[i - 1] .. "." .. f .. " >= " .. A.TIER_ORDER[i] .. "." .. f) end
end
eq(A.budgetKey("High", false), "High", "desktop High")
eq(A.budgetKey("Balanced", false), "Balanced", "desktop Balanced")
eq(A.budgetKey("High", true), "Lite", "a phone on High gets the lite set")
eq(A.budgetKey("Balanced", true), "Lite", "a phone on Balanced gets the lite set")
eq(A.budgetKey("Performance", true), "Performance", "Performance stays Performance on phones")
eq(A.budgetKey("Performance", false), "Performance", "Performance on desktop")
eq(A.budgetKey("Bogus", false), "High", "unknown tier falls back")
for _, tier in L.TIER_ORDER do ok(A.Budgets[A.budgetKey(tier, false)] ~= nil and A.Budgets[A.budgetKey(tier, true)] ~= nil, tier .. " maps to a budget") end
eq(A.Budgets.Performance.foam + A.Budgets.Performance.birds + A.Budgets.Performance.bolts, 0, "Performance draws no foam, birds or bolts")
eq(A.Budgets.Lite.bolts + A.Budgets.Lite.splashes, 0, "phones draw no bolts or splashes")
-- Culling radii inside the forge's build radii (a swayed prop must be a forged mesh).
local forge = fs.readFile("forge.client.lua")
local mobileBuild, desktopBuild = string.match(forge, "local BUILD_RADIUS, UNLOAD_RADIUS = if mobile then (%d+) else (%d+)")
mobileBuild, desktopBuild = tonumber(mobileBuild), tonumber(desktopBuild)
ok(mobileBuild and desktopBuild, "forge build radii found")
for _, key in {"High", "Balanced"} do ok(A.Budgets[key].swayRadius <= desktopBuild, key .. " sway radius inside the forge radius") end
for _, key in {"Lite", "Performance"} do ok(A.Budgets[key].swayRadius <= mobileBuild, key .. " sway radius inside the phone forge radius") end
for _, key in A.TIER_ORDER do
	local b = A.Budgets[key]
	ok(b.sourceRadius <= b.swayRadius and b.swayRadius <= b.waterRadius, key .. " radii: sources <= sway <= water")
end
-- Sway shapes exist (catalog shapes or forge aliases).
local catalogs = fs.readFile("art/WorldCatalog.lua") .. fs.readFile("art/PropCatalog.lua")
for name, def in A.SWAY do
	ok(string.find(catalogs, "shapes." .. name .. "=", 1, true) ~= nil or string.find(forge, name .. " = \"", 1, true) ~= nil, name .. " is a catalog shape or alias")
	ok(({tree = 1, bush = 1, crop = 1, banner = 1, lantern = 1, grass = 1})[def.mode] ~= nil, name .. " sway mode")
	ok(def.amp > 0 and def.amp <= 0.12 and def.freq > 0 and def.freq <= 2, name .. " sway amplitude / frequency are gentle")
end
ok(A.SWAY.WindmillSails == nil, "spinning sails (RegionSpin) never sway")
for _, name in {"MeadowTree", "Banner", "CropWheat", "HangingLantern", "Bush"} do ok(A.SWAY[name] ~= nil, name .. " sways") end
-- Sway angles: bounded, zero under reduced motion.
for name, def in A.SWAY do
	for step = 0, 40 do
		local lean, twist = A.swayAngles(def, step * 0.37, 2.4 * 1.35, step, false)
		ok(math.abs(lean) <= def.amp * 3.5 and math.abs(twist) <= def.amp * 3.5, name .. " angle bounded")
		local l2, t2 = A.swayAngles(def, step * 0.37, 2, step, true)
		assert(l2 == 0 and t2 == 0, name .. " reduced motion")
	end
end
checks += 1
-- Wind: gusts travel (the peak moves along the wind direction over time).
local dx, dz = A.windDir(100)
ok(math.abs(dx * dx + dz * dz - 1) < 1e-6, "wind direction is a unit vector")
local function peakAlong(t)
	local best, at = -1, 0
	for s = 0, 600, 2 do
		local g = A.gust(t, dx * s, dz * s)
		if g > best then best, at = g, s end
	end
	return at, best
end
local p0, g0 = peakAlong(100)
local p1 = peakAlong(101.5)
ok(g0 > 0.5, "a gust front exists (" .. g0 .. ")")
ok(p1 ~= p0, "the gust front moves across the isles (" .. p0 .. " -> " .. p1 .. ")")
for i = 0, 200 do
	local w = A.windAt(i * 1.7, i * 13, -i * 7, 1.5, "Storm")
	assert(w > 0 and w <= 1.5 * 2.4 * 1.35 + 1e-9, "wind bounded")
end
checks += 1
-- Presets.
for name, p in A.Presets do
	ok(#p.colors == 2 and p.size > 0 and p.life[1] <= p.life[2] and p.speed[1] <= p.speed[2] and p.rate > 0, name .. " preset is well formed")
	ok(p.texture == "sparkle" or p.texture == "smoke", name .. " texture")
end
for key, r in A.Regions do ok(A.Presets[r.motes] ~= nil, key .. " motes preset") end
ok(A.Presets.embers and A.Presets.spores and A.Presets.void and A.Presets.fireflies and A.Presets.pollen and A.Presets.frost, "themed motes exist")

------------------------------------------------------------------------------
-- Part B: weather.
------------------------------------------------------------------------------
local keySet = {}
for _, k in L.REGION_KEYS do keySet[k] = true end
for k in A.Regions do ok(keySet[k], k .. " is a lighting region key") end
for _, k in L.REGION_KEYS do ok(A.Regions[k] ~= nil and table.find(A.WEATHER_KEYS, k) ~= nil, k .. " has ambience + weather") end
eq(#A.WEATHER_KEYS, #L.REGION_KEYS, "weather keys = outdoor lighting keys")
eq(table.concat(A.STATE_ORDER, ","), table.concat(L.WEATHER_STATES, ","), "one list of weather states")
for _, s in A.STATE_ORDER do ok(L.WEATHER[s] ~= nil and A.WEATHER_WIND[s] ~= nil, s .. " has a look and a wind") end
for key, r in A.Regions do
	local total = 0
	for s, w in r.weather do ok(L.WEATHER[s] ~= nil and w > 0, key .. " weighs a known state " .. s); total += w end
	ok(total > 0, key .. " has weather")
	if r.cold then ok(r.weather.Rain == nil and r.weather.Snow ~= nil, key .. " is cold: snow, not rain")
	else ok(r.weather.Snow == nil, key .. " is not cold: no snow") end
end
-- Determinism: a second load (another server / client) agrees on every slot.
local A2 = load("shared/Ambience.lua")
local base = A.slotAt(1.8e9)
local counts = {}
for i = 0, 3999 do
	local slot = base + i
	local s1, s2 = A.schedule(slot), A2.schedule(slot)
	for _, key in A.WEATHER_KEYS do
		assert(s1[key] == s2[key], "schedule differs at " .. slot .. " " .. key)
		counts[key] = counts[key] or {}
		counts[key][s1[key]] = (counts[key][s1[key]] or 0) + 1
	end
	assert(A.encode(slot) == A2.encode(slot), "encode differs")
end
checks += 1
for key, r in A.Regions do
	local total = 0
	for _, w in r.weather do total += w end
	for s, w in r.weather do
		local share = (counts[key][s] or 0) / 4000
		ok(math.abs(share - w / total) < 0.05, key .. " rolls " .. s .. " about its weight (" .. string.format("%.3f vs %.3f", share, w / total) .. ")")
	end
	for s in counts[key] do ok(r.weather[s] ~= nil, key .. " never rolls an unweighted " .. s) end
end
ok((counts.Tempest.Storm or 0) > (counts.Meadow.Storm or 0) * 4, "Tempest Spire storms far more than the meadows")
-- Slots.
for _, t in {1.7e9, 1.7e9 + 479.9, 1.7e9 + 480, 1.8e9 + 0.5} do
	local slot = A.slotAt(t)
	local start = A.EPOCH + slot * A.SLOT
	ok(t >= start and t < start + A.SLOT, "slotAt brackets " .. t)
end
-- Encode <-> parse.
for i = 0, 40 do
	local slot = base + i * 7
	local parsed = L.parseWeather(A.encode(slot))
	ok(parsed and parsed.slot == slot, "round trip slot " .. slot)
	for _, key in A.WEATHER_KEYS do assert(parsed.regions[key] == A.weatherAt(slot, key), "round trip " .. key) end
	ok(parsed.strikeRegion == nil, "no strike without one")
end
local withStrike = L.parseWeather(A.encode(base, "Tempest", 1800000123.25))
ok(withStrike.strikeRegion == "Tempest" and math.abs(withStrike.strikeAt - 1800000123.25) < 1e-6, "strike round trip")
for _, bad in {nil, 5, "", "2|3|Hub=Rain", "1|x|Hub=Rain", "garbage"} do ok(L.parseWeather(bad) == nil, "malformed weather is ignored: " .. tostring(bad)) end
local odd = L.parseWeather("1|4|Hub=Lava,Meadow=Rain")
ok(odd.regions.Hub == nil and odd.regions.Meadow == "Rain", "unknown states are dropped")
for _, k in L.INTERIOR_KEYS do eq(L.weatherFor(L.parseWeather("1|4|" .. k .. "=Storm"), k), "Clear", k .. " has no weather") end
eq(L.weatherFor(nil, "Hub"), "Clear", "no attribute: clear")
-- Lightning strikes.
local stormSlot
for i = 0, 400 do if A.weatherAt(base + i, "Tempest") == "Storm" then stormSlot = base + i break end end
ok(stormSlot ~= nil, "Tempest storms within 400 slots")
local strikes = A.strikes(stormSlot, "Tempest")
ok(#strikes >= 10, "a storm slot strikes repeatedly (" .. #strikes .. ")")
for i, at in strikes do
	ok(at >= 19 and at < A.SLOT, "strike inside the slot after the roll-in")
	if i > 1 then ok(at - strikes[i - 1] >= 9 and at - strikes[i - 1] <= 24, "strikes 9-24 s apart") end
end
for i = 0, 60 do
	for _, key in A.WEATHER_KEYS do
		if A.weatherAt(base + i, key) ~= "Storm" then assert(#A.strikes(base + i, key) == 0, "no strikes outside a storm") end
	end
end
checks += 1
local start = A.EPOCH + stormSlot * A.SLOT
-- QC H2: the local strike clock. strikeDue hands out each strike once, on
-- the frame it is due, never early, and skips strikes older than the grace.
do
	local cursor = A.newStrikeCursor()
	local fired = {}
	local t = start
	while t < start + A.SLOT - 0.01 do
		local at = A.strikeDue(cursor, t, "Tempest", 0.5)
		if at then
			table.insert(fired, at)
			assert(t >= at and t - at < 1 / 30 + 1e-9, "a strike fires on the frame it is due")
		end
		t += 1 / 30
	end
	eq(#fired, #strikes, "every scheduled strike fires exactly once")
	for i, at in fired do assert(math.abs(at - (start + strikes[i])) < 1e-6, "strike " .. i .. " at its scheduled time") end
	checks += 1
	-- A client joining mid-storm never replays old strikes.
	local late = A.newStrikeCursor()
	ok(A.strikeDue(late, start + strikes[3] + 2, "Tempest", 0.5) == nil, "a late joiner does not replay a past strike")
	ok(A.strikeDue(late, start + strikes[4] + 0.01, "Tempest", 0.5) ~= nil, "and still gets the next one")
	-- lastStrike (the director's flash clock).
	local last = A.newStrikeCursor()
	eq(A.lastStrike(last, start + strikes[2] + 0.2, "Tempest"), start + strikes[2], "lastStrike: the latest strike at or before t")
	eq(A.lastStrike(A.newStrikeCursor(), start + 1, "Tempest"), nil, "no strike yet in a fresh slot")
	local calm
	for _, k in A.WEATHER_KEYS do if A.weatherAt(stormSlot, k) ~= "Storm" then calm = k break end end
	eq(A.lastStrike(A.newStrikeCursor(), start + strikes[5], calm), nil, "a region without a storm never strikes")
end
-- QC L2: strike sequences never repeat between neighbouring slots or regions.
do
	local seen, repeats, storms = {}, 0, 0
	for i = 0, 3000 do
		for _, key in A.WEATHER_KEYS do
			local list = A.strikes(base + i, key)
			if #list > 0 then
				storms += 1
				local sig = table.concat(list, ",")
				if seen[sig] then repeats += 1 end
				seen[sig] = true
			end
		end
	end
	ok(storms > 500, "plenty of storm slots sampled (" .. storms .. ")")
	eq(repeats, 0, "no two storm slots share a strike sequence")
end
-- The weather script: one attribute, the same on every server, no gameplay.
local function weatherServer(t)
	local ws = roblox.Instance.new("Workspace")
	local env = {
		game = {GetService = function(_, name) return {WaitForChild = function(_, n) return n end} end},
		workspace = ws, require = function(name) assert(name == "AetherAmbience", "weather requires only AetherAmbience"); return A end,
		os = {time = function() return t end}, task = {spawn = function() end, wait = function() end}, warn = warn,
	}
	local W = luau.load(fs.readFile("weather.server.lua"), {debugName = "weather.server.lua", environment = env, injectGlobals = true})()
	return W, ws
end
local tA = start + strikes[2] + 0.1
local W1, ws1 = weatherServer(tA)
local _, ws2 = weatherServer(tA)
ok(type(ws1:GetAttribute("IsleWeather")) == "string", "the server publishes IsleWeather")
eq(ws1:GetAttribute("IsleWeather"), ws2:GetAttribute("IsleWeather"), "two servers at the same time publish the same weather")
local live = L.parseWeather(ws1:GetAttribute("IsleWeather"))
ok(live and live.slot == stormSlot and live.regions.Tempest == "Storm", "the published slot table parses")
ok(live.strikeRegion == nil, "QC H2: the attribute carries only the weather state, never a strike")
local _, ws3 = weatherServer(tA + 20)
eq(ws3:GetAttribute("IsleWeather"), ws1:GetAttribute("IsleWeather"), "the attribute is constant within a slot (no strike churn)")
ok(string.find(fs.readFile("weather.server.lua"), "local ok, err = pcall(Weather.step)\n\tif not ok then warn", 1, true) ~= nil, "QC L8: the first step is pcall'd")
eq(W1.textAt(tA), ws1:GetAttribute("IsleWeather"), "textAt matches the attribute")
local wsrc = (string.gsub(fs.readFile("weather.server.lua"), "%-%-[^\n]*", ""))
local _, setAttrs = string.gsub(wsrc, "SetAttribute%(", "")
eq(setAttrs, 1, "the weather script writes one attribute")
for _, word in {"Instance.new", "RemoteEvent", "RemoteFunction", ".items", "collect(", "Humanoid", "Health", "Players", "DataStore", "IsleAction"} do
	ok(not string.find(wsrc, word, 1, true), "the weather script never touches " .. word)
end
-- Lighting deltas: every composed state stays valid under every weather.
local composed = 0
for key in L.Profiles do
	for _, state in A.STATE_ORDER do
		local w = L.blendWeather({}, state, 1)
		for _, tier in L.TIER_ORDER do
			for hour = 0, 24, 2 do
				local s = L.applyWeather(L.target(key, hour, tier), w)
				local good, why = L.valid(s)
				assert(good, key .. " " .. state .. " " .. hour .. " " .. tier .. ": " .. tostring(why))
				composed += 1
			end
		end
	end
end
ok(composed > 2000, "weather looks validated (" .. composed .. ")")
local clear = L.target("Meadow", 12, "High")
local rainy = L.applyWeather(L.target("Meadow", 12, "High"), L.blendWeather({}, "Rain", 1))
local stormy = L.applyWeather(L.target("Meadow", 12, "High"), L.blendWeather({}, "Storm", 1))
local foggy = L.applyWeather(L.target("Meadow", 12, "High"), L.blendWeather({}, "Fog", 1))
ok(rainy.EnvironmentSpecularScale > clear.EnvironmentSpecularScale + 0.2, "rain adds a wet sheen (specular)")
ok(stormy.Brightness < rainy.Brightness and rainy.Brightness < clear.Brightness, "storm is darker than rain, rain than clear")
ok(foggy.AtmDensity > clear.AtmDensity + 0.1 and foggy.AtmHaze > clear.AtmHaze, "fog thickens the air")
ok(stormy.RaysIntensity == 0, "no sun rays in a storm")
-- Blending: converges, never overshoots.
local cur, prev = {}, 0
for _ = 1, 15 * 40 do
	L.blendWeather(cur, "Storm", L.alphaFor(1 / 15, L.WEATHER_TAU))
	assert((cur.haze or 0) >= prev - 1e-12 and (cur.haze or 0) <= L.WEATHER.Storm.haze + 1e-12, "weather blend is monotonic")
	prev = cur.haze or 0
end
eq(cur.haze, L.WEATHER.Storm.haze, "the storm settles in 40 s")
-- Flash.
eq(L.flashAt(-0.1), 0, "no flash before the strike")
eq(L.flashAt(0.01), 1, "full flash at the strike")
ok(L.flashAt(0.12) < L.flashAt(0.22), "a double flicker")
eq(L.flashAt(L.FLASH_LENGTH + 0.01), 0, "the flash ends")
for _, e in {-0.5, 0, 0.3, 0.5} do ok(L.flashExposure(e, 1) <= L.FLASH_CEILING and L.flashExposure(e, 0) == math.min(e, L.FLASH_CEILING), "flash exposure ceiling") end

-- The director honours IsleWeather (headless, as verify-lighting runs it).
do
	local function signal()
		local listeners = {}
		return {Connect = function(_, f) table.insert(listeners, f) return {Disconnect = function() end} end,
			Fire = function(_, ...) for _, f in listeners do f(...) end end}
	end
	local Lighting = roblox.Instance.new("Lighting")
	local ws = roblox.Instance.new("Workspace")
	local character = roblox.Instance.new("Model")
	local root = roblox.Instance.new("Part"); root.Name = "HumanoidRootPart"; root.CFrame = CFrame.new(0, 2, 0); root.Parent = character
	character.Parent = ws
	local attrs = {IsleRegionHere = "Meadow", IsleSettingGraphics = "High"}
	local playerMock = {Character = character, GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end}
	local heartbeat = signal()
	local serverT = Data.Calendar.epoch + 400 * Data.Calendar.dayLength + Data.Calendar.dayLength * 0.5
	local env = {
		game = {GetService = function(_, name)
			return ({Players = {LocalPlayer = playerMock}, RunService = {Heartbeat = heartbeat}, Lighting = Lighting,
				ReplicatedStorage = {WaitForChild = function(_, n) return n end}, UserInputService = {TouchEnabled = false, KeyboardEnabled = true}})[name]
		end},
		workspace = ws, Instance = roblox.Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = roblox.Enum,
		typeof = roblox.typeof or typeof,
			require = function(name)
			if name == "AetherLighting" then return L elseif name == "AetherData" then return Data elseif name == "AetherAmbience" then return A end
			error("unexpected require " .. tostring(name))
		end,
		os = {time = function() return serverT end, clock = os.clock},
		task = {defer = function(f) f() end, spawn = function(f) f() end},
	}
	local D = luau.load(fs.readFile("lighting.client.lua"), {debugName = "lighting.client.lua", environment = env, injectGlobals = true})()
	local function run(seconds) for _ = 1, math.ceil(seconds * 30) do serverT += 1 / 30; heartbeat:Fire(1 / 30) end end
	run(6)
	eq(D.weather.state, "Clear", "no attribute: clear")
	local dry = Lighting.EnvironmentSpecularScale
	local dryBright = Lighting.Brightness
	ws:SetAttribute("IsleWeather", "1|5|Meadow=Rain,Hub=Clear")
	run(1)
	eq(D.weather.state, "Rain", "the director reads the region's weather")
	run(30)
	ok(Lighting.EnvironmentSpecularScale > dry + 0.2, "rain raises the specular scale (wet sheen) " .. dry .. " -> " .. Lighting.EnvironmentSpecularScale)
	ok(Lighting.Brightness < dryBright - 0.2, "rain dims the sun")
	local good, why = L.valid(D.state)
	ok(good, "the blended rainy state is valid: " .. tostring(why))
	attrs.IsleRegionHere = "Hub"
	run(2)
	eq(D.weather.state, "Clear", "another region keeps its own weather")
	-- QC H2: strikes come from the schedule on server time; the attribute
	-- only names the storm. Find the next Tempest storm slot.
	attrs.IsleRegionHere = "Tempest"
	local s0 = A.slotAt(serverT)
	local sl
	for i = 1, 400 do if A.weatherAt(s0 + i, "Tempest") == "Storm" then sl = s0 + i break end end
	local st = A.EPOCH + sl * A.SLOT
	local list = A.strikes(sl, "Tempest")
	serverT = st - 1
	ws:SetAttribute("IsleWeather", A.encode(sl - 1))
	run(1)
	-- The new slot's attribute arrives 0.3 s late: irrelevant, the first
	-- strike is >= 19 s into the slot.
	run(0.3)
	ws:SetAttribute("IsleWeather", A.encode(sl))
	run(0.5)
	eq(D.weather.state, "Storm", "the director sees the storm")
	local at1 = st + list[1]
	serverT = at1 - 0.5
	run(0.4)
	eq(D.weather.flash, 0, "no flash before the scheduled strike")
	local peak = 0
	for _ = 1, 6 do
		serverT += 1 / 30; heartbeat:Fire(1 / 30)
		if serverT >= at1 and serverT - at1 < 1 / 30 then eq(D.weather.flash, 1, "the flash lands on the strike's frame") end
		peak = math.max(peak, D.weather.flash)
	end
	eq(peak, 1, "full flash at the strike")
	ok(Lighting.ExposureCompensation <= L.FLASH_CEILING + 1e-6, "flash ceiling")
	ok(D.state.ExposureCompensation <= 0.5 + 1e-6, "the flash never enters the blended state")
	run(1)
	eq(D.weather.flash, 0, "the flash ends")
	ok(math.abs(Lighting.ExposureCompensation - D.state.ExposureCompensation) < 2e-3, "exposure returns to the look")
	-- Late weather delivery (0.3 / 0.6 s after a strike): the flash joins in
	-- phase with the schedule, never restarted from the delivery.
	for k, lateBy in {0.3, 0.6} do
		local at = st + list[1 + k]
		ws:SetAttribute("IsleWeather", "1|" .. sl .. "|Tempest=Clear") -- a stale (pre-storm) table
		serverT = at - 1
		run(0.5)
		eq(D.weather.state, "Clear", "stale table: no storm yet")
		serverT = at + lateBy - 0.5
		run(0.5)
		ws:SetAttribute("IsleWeather", A.encode(sl))
		local seen = false
		for _ = 1, 9 do
			serverT += 1 / 30; heartbeat:Fire(1 / 30)
			if D.weather.state == "Storm" then
				local expect = L.flashAt(serverT - at)
				assert(math.abs(D.weather.flash - expect) < 1e-9, "late delivery: the flash follows the schedule's phase")
				seen = true
			end
		end
		ok(seen, "late delivery " .. lateBy .. " s: storm applied")
		ok(D.weather.flash < 1, "late delivery " .. lateBy .. " s: the flash is not restarted")
	end
	-- QC L6: night flashes are softer; "Flashing effects" off and reduced motion: none.
	eq(L.flashExposure(0, 1, 1), L.FLASH_EXPOSURE, "day flash")
	eq(L.flashExposure(0, 1, 0), L.FLASH_EXPOSURE_NIGHT, "night flash")
	ok(L.FLASH_EXPOSURE_NIGHT < L.FLASH_EXPOSURE, "night flash is lower")
	for _, setting in {{attr = "IsleSettingFlashing", value = false, why = "Flashing effects off"}, {attr = "IsleSettingReducedMotion", value = true, why = "reduced motion"}} do
		attrs[setting.attr] = setting.value
		local at = st + list[5]
		serverT = at - 0.5
		run(0.4)
		local most = 0
		for _ = 1, 12 do serverT += 1 / 30; heartbeat:Fire(1 / 30); most = math.max(most, D.weather.flash) end
		eq(most, 0, setting.why .. ": no flash")
		attrs[setting.attr] = nil
		list = A.strikes(sl, "Tempest")
		table.remove(list, 5) -- use the next strike for the next case
	end
	-- Another region in the same slot (not storming) never flashes.
	local calmKey
	for _, k in A.WEATHER_KEYS do if A.weatherAt(sl, k) ~= "Storm" and A.Regions[k] and k ~= "Home" and k ~= "Skyways" then calmKey = k break end end
	attrs.IsleRegionHere = calmKey
	run(1)
	local most = 0
	serverT = st + list[6] - 0.2
	for _ = 1, 20 do serverT += 1 / 30; heartbeat:Fire(1 / 30); most = math.max(most, D.weather.flash) end
	eq(most, 0, "a strike in another region does not flash here")
	-- QC M5: entering an interior snaps the storm deltas away (no haze in a lair).
	attrs.IsleRegionHere = "Tempest"
	run(20)
	ok((D.weather.delta.haze or 0) > 0.5, "storm haze settled")
	attrs.LairBoss = "Test"
	root.CFrame = CFrame.new(3600, 300, -3600)
	run(0.3)
	eq(D.weather.delta.haze, 0, "entering a lair snaps the weather away")
	attrs.LairBoss = nil
	root.CFrame = CFrame.new(0, 2, 0)
	run(0.3)
	eq(D.weather.delta.haze, L.WEATHER.Storm.haze, "leaving snaps the storm back")
end
ok(string.find(fs.readFile("lighting.client.lua"), "local HOLD = L.CONTEXT_HOLD", 1, true) ~= nil, "QC L4: one context hold for the director and the ambience layer")

------------------------------------------------------------------------------
-- Part C: skill VFX rules.
------------------------------------------------------------------------------
local lastHeight = 0
for _, r in Data.RarityOrder do
	local spec = A.beamFor(r, Data)
	if Data.Rarity[r].rank < A.BEAM_MIN_RANK then
		ok(spec == nil, r .. " drops raise no pillar")
	else
		ok(spec ~= nil, r .. " drops raise a pillar")
		eq(spec.color, Data.Rarity[r].color, r .. " pillar colour is the item rarity colour")
		ok(spec.height > lastHeight, r .. " pillar is taller than the one below")
		lastHeight = spec.height
		ok(spec.life > 0 and spec.width > 0, r .. " pillar shape")
	end
end
ok(A.beamFor("Legendary", Data).pulse and A.beamFor("Mythic", Data).pulse and not A.beamFor("Rare", Data).pulse, "legendary+ pillars pulse")
eq(A.beamFor("Nope", Data), nil, "unknown rarity: no pillar")
-- The rarest pickup of a list (real items of each rarity).
local byRarity = {}
for id, def in Data.Items do if def.rarity and not byRarity[def.rarity] then byRarity[def.rarity] = id end end
for i, r in Data.RarityOrder do
	if byRarity[r] then
		local list = {{id = "coins", n = 4}}
		for j = 1, i do if byRarity[Data.RarityOrder[j]] then table.insert(list, 1, {id = byRarity[Data.RarityOrder[j]], n = 1}) end end
		eq(A.rarestPickup(list, Data), r, "the rarest of the first " .. i .. " rarities")
	end
end
eq(A.rarestPickup({}, Data), nil, "no pickups: nothing")
eq(A.rarestPickup(nil, Data), nil, "nil pickups: nothing")
-- Sparks for every strike fx animate.client.lua fires.
local animate = fs.readFile("animate.client.lua")
local fxSeen = {}
for skill, fx in string.gmatch(animate, 'skill = "(%a+)", fx = "(%a+)"') do fxSeen[fx] = skill end
for _, fx in {"chips", "wood", "dust", "splash"} do ok(fxSeen[fx] ~= nil, fx .. " is a strike fx in animate.client.lua") end
for fx in fxSeen do ok(A.SPARKS[fx] ~= nil, fx .. " has hit sparks") end
ok(A.SPARKS.sparks and A.SPARKS[A.SPARK_DEFAULT], "anvil sparks and a default")
for fx, s in A.SPARKS do
	ok(s.sparkCount + s.chipCount > 0, fx .. " throws something")
	local _, sc, cc = A.sparkFor(fx, true)
	ok(sc <= s.sparkCount and cc <= s.chipCount, fx .. " fewer under reduced motion")
end
ok(string.find(animate, 'impactHook:Fire(state.name, def.fx, position, state.isLocal)', 1, true) ~= nil, "animate.client.lua fires IsleImpactLocal(name, fx, position, isLocal)")
for _, key in A.TIER_ORDER do
	local b = A.Budgets[key]
	eq(A.orbCount(0, b), 0, key .. " no orbs for no XP")
	eq(A.orbCount(5, b), 1, key .. " one orb for a small gain")
	ok(A.orbCount(1e6, b) <= math.min(4, b.orbs) and A.orbCount(1e6, b) >= 1, key .. " orbs capped")
end

------------------------------------------------------------------------------
-- Part D: source checks.
------------------------------------------------------------------------------
local src = fs.readFile("ambience.client.lua")
local code = (string.gsub(src, "%-%-[^\n]*", ""))
local blocks = {}
for name, body in string.gmatch(src, "%-%- FRAME%-BEGIN (%a+)\n(.-)%-%- FRAME%-END %1") do blocks[name] = (string.gsub(body, "%-%-[^\n]*", "")) end
for _, name in {"anchors", "sky", "sway", "foam", "flock", "fx"} do ok(blocks[name] ~= nil and #blocks[name] > 200, "per-frame block " .. name) end
local FORBIDDEN = {"{", "function(", "Instance.new", "..", "table.insert", "table.create", "ColorSequence", "NumberSequence", "NumberRange", ":Clone", "string.", "setmetatable", "pairs("}
for name, body in blocks do
	ok(select(2, string.gsub(body, "function ", "")) == 1, name .. " block is one function")
	for _, word in FORBIDDEN do
		ok(not string.find(body, word, 1, true), name .. " frame block allocates nothing: " .. word)
	end
end
for _, call in {"Amb.anchorsFrame()", "Sky.frame(dt)", "Sway.frame()", "Foam.frame()", "Flock.frame(dt)", "FX.frame()"} do ok(string.find(code, call, 1, true) ~= nil, call .. " runs from the step") end
local _, beats = string.gsub(code, '"Heartbeat"', "")
eq(beats, 1, "one Heartbeat connection")
ok(string.find(code, "if not Amb.reduced then Sway.frame() end", 1, true) ~= nil, "reduced motion: no sway")
ok(string.find(code, "if not Amb.flashing or Amb.b.bolts <= 0 then return end", 1, true) ~= nil, "reduced motion / Flashing effects off: no bolt")
ok(string.find(code, "Amb.flashing = L.flashingAllowed(player:GetAttribute(L.FLASHING_ATTR), Amb.reduced)", 1, true) ~= nil, "the bolt follows the Flashing effects setting")
ok(not string.find(code, "% 86400", 1, true) and string.find(code, "Amb.tw = t - A.EPOCH", 1, true) ~= nil, "QC L3: the wind clock never wraps")
ok(not string.find(code, "Vector3.new(0, 40, 0))", 1, true), "QC H1: no upward world raycast for shelter")
ok(string.find(code, "GetAttributeChangedSignal(L.WEATHER_ATTR)", 1, true) ~= nil, "QC H2: the weather attribute is watched, not polled")
ok(not string.find(code, "strikeAt", 1, true), "QC H2: no strike from the attribute")
ok(string.find(code, "A.windAtDir(t, p.X, p.Z, base, weather, dx, dz)", 1, true) ~= nil, "QC M6: one wind direction per frame")
ok(string.find(code, "if twist ~= 0 then rot *= CFrame.Angles(0, twist, 0) end", 1, true) ~= nil, "QC M6: no twist CFrame for props that never twist")
local regionsSrc = (string.gsub(fs.readFile("regions.client.lua"), "%-%-[^\n]*", ""))
ok(not string.find(regionsSrc, "ParticleEmitter", 1, true), "QC M4: regions.client.lua runs no second ambience emitter")
for kind, preset in A.ISLAND_MOTES do ok(A.Presets[preset] ~= nil, "island ambience " .. kind .. " has a preset in the one palette") end
for _, region in Data.RegionArt.Regions do
	local kind = region.ambience and region.ambience.particles
	if kind then ok(A.ISLAND_MOTES[kind] ~= nil, "Data.RegionArt ambience " .. kind .. " maps to a preset") end
end
eq(Data.PlayerSettings.byAttr[L.FLASHING_ATTR] and Data.PlayerSettings.byAttr[L.FLASHING_ATTR].kind, "bool", "QC L6: Flashing effects is a saved setting")
ok(string.find(fs.readFile("ui.client.lua"), '{attr="IsleSettingFlashing",title="Flashing effects"', 1, true) ~= nil, "QC L6: the Settings page offers Flashing effects")
eq(L.flashingAllowed(nil, false), true, "flashing defaults on")
eq(L.flashingAllowed(true, true), false, "reduced motion turns flashing off")
eq(L.flashingAllowed(false, false), false, "the setting turns flashing off")
for _, word in {'GetService("Lighting")', "game.Lighting", "PlayerGui", "ScreenGui", "BillboardGui", "SurfaceGui", "IsleAction", "FireServer", "InvokeServer", "creatures"} do
	ok(not string.find(code, word, 1, true), "the ambience layer never touches " .. word)
end
ok(string.find(code, "workspace:BulkMoveTo", 1, true) ~= nil, "sway moves with BulkMoveTo")
local director = fs.readFile("lighting.client.lua")
ok(string.find(director, "L.applyWeather(target, L.blendWeather(Weather.delta, Weather.state", 1, true) ~= nil, "the director blends the weather deltas")
ok(string.find(director, 'if Weather.state == "Storm" and Weather.flashing then', 1, true) ~= nil, "the director's flash needs the region's storm and the flashing permission")
ok(string.find(director, "Ambience.lastStrike(Weather.cursor, t, Director.key or L.DEFAULT_KEY)", 1, true) ~= nil, "QC H2: the director's flash runs on the shared strike schedule")
ok(string.find(director, "workspace:GetAttributeChangedSignal(L.WEATHER_ATTR):Connect(Weather.readText)", 1, true) ~= nil, "QC H2: the director watches the attribute")
local project = fs.readFile("default.project.json")
for _, entry in {'"AetherAmbience": { "$path": "shared/Ambience.lua" }', '"Weather": { "$path": "weather.server.lua" }', '"IsleAmbience": { "$path": "ambience.client.lua" }'} do
	ok(string.find(project, entry, 1, true) ~= nil, "project maps " .. entry)
end
for _, file in {"scripts/build.sh", "build.ps1"} do ok(string.find(fs.readFile(file), "verify-ambience.luau", 1, true) ~= nil, file .. " runs this suite") end

------------------------------------------------------------------------------
-- Part E: the client, headless.
------------------------------------------------------------------------------
local function signal()
	local listeners = {}
	return {Connect = function(_, f) table.insert(listeners, f) return {Disconnect = function() end} end,
		Fire = function(_, ...) for _, f in listeners do f(...) end end}
end
local function newPart(class, name, pos, size, parent)
	local p = roblox.Instance.new(class)
	p.Name, p.Anchored, p.Size, p.CFrame = name, true, size or Vector3.new(1, 1, 1), CFrame.new(pos)
	p.Parent = parent
	return p
end
local function boot(opts)
	opts = opts or {}
	local ws = roblox.Instance.new("Workspace")
	local islands = roblox.Instance.new("Folder"); islands.Name = "Islands"; islands.Parent = ws
	local isle = roblox.Instance.new("Model"); isle.Name = "Test Isle"
	isle:SetAttribute("IslandCenter", Vector3.new(0, 0, 0)); isle:SetAttribute("IslandRadius", 60); isle:SetAttribute("Region", "Meadow")
	isle.Parent = islands
	local far = roblox.Instance.new("Model"); far.Name = "Far Isle"
	far:SetAttribute("IslandCenter", Vector3.new(4000, 0, 0)); far:SetAttribute("IslandRadius", 50); far.Parent = islands
	-- The forge's output: an anchored server host with a ShapeMesh link to a
	-- local MeshPart clone (ShapeOf) in the same parent (forge.client.lua).
	local function forged(shape, pos, size, hostOpts)
		local host = newPart("Part", shape .. " host", pos, size, isle)
		host:SetAttribute("Shape", shape)
		if hostOpts and hostOpts.spin then host:SetAttribute("SpinRate", 0.35) end
		if hostOpts and hostOpts.loose then host.Anchored = false end
		local clone = newPart("MeshPart", shape .. " Mesh", pos, size, isle)
		clone:SetAttribute("ShapeOf", shape)
		local link = roblox.Instance.new("ObjectValue"); link.Name = "ShapeMesh"; link.Value = clone; link.Parent = host
		return clone, host
	end
	-- 240 forged trees on a grid out to ~170 studs, plus a few far ones.
	local trees = {}
	for i = 0, 239 do
		local x, z = (i % 16 - 7.5) * 20, (math.floor(i / 16) - 7) * 22
		local t = forged("MeadowTree", Vector3.new(x, 6, z), Vector3.new(8, 12, 8))
		table.insert(trees, {part = t, base = t.CFrame})
	end
	local farTrees = {}
	for i = 1, 5 do
		local t = forged("PalmTree", Vector3.new(600 + i * 30, 6, 0), Vector3.new(8, 12, 8))
		table.insert(farTrees, {part = t, base = t.CFrame})
	end
	local banner = forged("Banner", Vector3.new(6, 8, 0), Vector3.new(0.3, 6, 3))
	local sails = forged("WindmillSails", Vector3.new(0, 30, 10), Vector3.new(30, 30, 2), {spin = true})
	local spunBanner = forged("Banner", Vector3.new(-6, 8, 0), Vector3.new(0.3, 6, 3), {spin = true})
	local looseBanner = forged("Banner", Vector3.new(-6, 8, 4), Vector3.new(0.3, 6, 3), {loose = true})
	local crop = forged("CropBed", Vector3.new(4, 1, -3), Vector3.new(4, 2, 4))
	local hiddenTree = forged("MeadowTree", Vector3.new(2, 6, 6), Vector3.new(8, 12, 8))
	hiddenTree.LocalTransparencyModifier = 1 -- a depleted node (gather.client.lua)
	-- A bare server part with a sway shape but no forge link never moves (QC M1).
	local bare = newPart("MeshPart", "Server mesh", Vector3.new(-3, 6, -3), Vector3.new(8, 12, 8), isle)
	bare:SetAttribute("ShapeOf", "MeadowTree")
	local tuft = newPart("Part", "Herb tuft", Vector3.new(3, 0.5, 3), Vector3.new(0.9, 0.9, 0.9), isle)
	-- Water: a pond and a fishing spot.
	local pondModel = roblox.Instance.new("Model"); pondModel.Name = "Pond"; pondModel.Parent = isle
	local pond = newPart("Part", "Pond water", Vector3.new(20, 0.17, 20), Vector3.new(0.1, 9.7, 9.7), pondModel)
	pond.Shape = roblox.Enum.PartType.Cylinder
	pond.CFrame = CFrame.new(20, 0.17, 20) * CFrame.Angles(0, 0, math.pi / 2)
	local spot = roblox.Instance.new("Model"); spot.Name = "Minnow fishing spot"; spot.Parent = isle
	newPart("Part", "Ripple", Vector3.new(-20, 0.3, 10), Vector3.new(0.03, 1, 1), spot)
	-- Sources: a forge (near), a forge (far), a glowshroom.
	local forgeNear = newPart("Part", "Forge", Vector3.new(10, 2, -6), Vector3.new(4, 4, 4), isle); forgeNear:SetAttribute("Shape", "Forge")
	local forgeFar = newPart("Part", "Forge", Vector3.new(900, 2, 0), Vector3.new(4, 4, 4), isle); forgeFar:SetAttribute("Shape", "Forge")
	local shroom = newPart("Part", "Shroom", Vector3.new(-12, 1, -12), Vector3.new(2, 2, 2), isle); shroom:SetAttribute("Shape", "Glowshroom")
	-- A gather node (chip tint) and a landmark.
	local ore = newPart("Part", "Ore", Vector3.new(2, 1, 2), Vector3.new(3, 3, 3), isle); ore:SetAttribute("GatherNode", Data.ResourceTiers.Mining[1].id)
	local landmark = newPart("Part", "Compass Spire", Vector3.new(0, 20, -40), Vector3.new(10, 40, 10), isle); landmark:SetAttribute("Landmark", "Spire")
	-- A World Art waterfall: foundation + lip / foot attachments + beam + mist.
	local foundation = newPart("Part", "Floating foundation", Vector3.new(0, -3.6, 0), Vector3.new(6, 122, 122), isle)
	local lip = roblox.Instance.new("Attachment"); lip.Name = "Waterfall lip"; lip.CFrame = CFrame.new(0, 3, 61); lip.Parent = foundation
	local foot = roblox.Instance.new("Attachment"); foot.Name = "Waterfall foot"; foot.CFrame = CFrame.new(0, -50, 66); foot.Parent = foundation
	local beam = roblox.Instance.new("Beam"); beam.Name = "Waterfall"; beam.Attachment0, beam.Attachment1 = lip, foot
	beam.Width0, beam.Width1 = 6, 10; beam.Parent = foundation
	local mist = roblox.Instance.new("ParticleEmitter"); mist.Name = "Waterfall mist"; mist.Enabled = true; mist.Parent = foot
	-- The player.
	local character = roblox.Instance.new("Model")
	local root = newPart("Part", "HumanoidRootPart", Vector3.new(0, 3, 0), Vector3.new(2, 2, 1), character)
	character.Parent = ws
	local attrs = {IsleRegionHere = "Meadow", IsleSettingGraphics = opts.tier or "High"}
	local playerMock = {Character = character, Name = "Tester", GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end}
	local heartbeat = signal()
	local cues = {}
	local function bindableMock(name)
		local ev = signal()
		return {Name = name, Event = ev, Fire = function(_, ...) if name == "IsleAmbienceCue" then table.insert(cues, {...}) end ev:Fire(...) end}
	end
	local bindables = {}
	for _, n in {"IsleAmbienceCue", "IsleImpactLocal", "IsleXpLocal", "IsleSnapshotLocal"} do bindables[n] = bindableMock(n) end
	local clockT = 1000
	local serverT = Data.Calendar.epoch + 400 * Data.Calendar.dayLength + Data.Calendar.dayLength * 0.5 -- isle noon
	local services = {
		Players = {LocalPlayer = playerMock},
		RunService = {Heartbeat = heartbeat},
		ReplicatedStorage = {WaitForChild = function(_, n) return n end, FindFirstChild = function(_, n) return bindables[n] end},
		UserInputService = {TouchEnabled = opts.phone == true, KeyboardEnabled = opts.phone ~= true},
	}
	local env = {
		game = {GetService = function(_, name) return services[name] end},
		workspace = ws, Instance = roblox.Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = roblox.Enum,
		ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange, Vector2 = roblox.Vector2, typeof = roblox.typeof or typeof,
		require = function(name)
			if name == "AetherAmbience" then return A elseif name == "AetherLighting" then return L elseif name == "AetherData" then return Data end
			error("unexpected require " .. tostring(name))
		end,
		os = {time = function() return serverT end, clock = function() return clockT end},
	}
	local Amb = luau.load(src, {debugName = "ambience.client.lua", environment = env, injectGlobals = true})()
	local ctx = {Amb = Amb, ws = ws, attrs = attrs, root = root, trees = trees, farTrees = farTrees, banner = banner, sails = sails, tuft = tuft,
		spunBanner = spunBanner, looseBanner = looseBanner, crop = crop, hiddenTree = hiddenTree, bare = bare,
		forgeNear = forgeNear, forgeFar = forgeFar, shroom = shroom, beam = beam, mist = mist, cues = cues, bindables = bindables, isle = isle, ore = ore}
	function ctx.run(seconds)
		local n = math.ceil(seconds * 30)
		for _ = 1, n do
			clockT += 1 / 30
			serverT += 1 / 30
			heartbeat:Fire(1 / 30)
		end
	end
	function ctx.serverTime() return serverT end
	function ctx.setServer(t) serverT = t end
	function ctx.folder() return ws:FindFirstChild("IsleAmbienceLocal") end
	function ctx.parts()
		local f, n = ctx.folder(), 0
		for _, d in (f and f:GetDescendants() or {}) do if d:IsA("BasePart") then n += 1 end end
		return n
	end
	function ctx.enabledEmitters()
		local n = 0
		for _, d in ws:GetDescendants() do
			if d:IsA("ParticleEmitter") and d.Enabled and d.Name ~= "Waterfall mist" then n += 1 end
		end
		return n
	end
	function ctx.cueCount(kind)
		local n = 0
		for _, c in cues do if c[1] == kind then n += 1 end end
		return n
	end
	return ctx
end
local function moved(e) return e.part.CFrame ~= e.base end
local function bottom(cf, size) return (cf * CFrame.new(0, -size.Y / 2, 0)).Position end

-- High (desktop).
local H = boot({tier = "High"})
local hb = A.Budgets.High
H.run(3)
eq(H.Amb.budgetKey, "High", "desktop High uses the High set")
ok(H.parts() <= hb.parts, "High: parts " .. H.parts() .. " <= " .. hb.parts)
ok(H.Amb.emittingCount <= hb.emitters, "High: emitters " .. H.Amb.emittingCount .. " <= " .. hb.emitters)
eq(H.enabledEmitters(), H.Amb.emittingCount, "every enabled ambience emitter is counted")
eq(H.Amb.sway.count, hb.sway, "High sways exactly its cap of the nearest props")
local swayed, nearSwayed, beyond = 0, 0, 0
for _, e in H.trees do
	local d = (e.base.Position - H.root.CFrame.Position).Magnitude
	if moved(e) then
		swayed += 1
		assert(d <= hb.swayRadius, "a swayed tree is inside the sway radius")
		-- The pivot (trunk base) stays planted; the lean is gentle.
		assert((bottom(e.part.CFrame, e.part.Size) - bottom(e.base, e.part.Size)).Magnitude < 1e-3, "sway pivots about the trunk base")
		assert(e.part.CFrame.UpVector:Dot(e.base.UpVector) > math.cos(0.12), "sway is gentle")
		if d < 60 then nearSwayed += 1 end
	elseif d > hb.swayRadius then beyond += 1 end
end
ok(swayed > 0 and swayed <= hb.sway, "trees sway within the cap (" .. swayed .. ")")
ok(nearSwayed > 0, "the nearest trees sway")
for _, e in H.farTrees do ok(not moved(e), "trees past the sway radius are untouched") end
ok(H.banner.CFrame ~= CFrame.new(6, 8, 0), "the banner flutters")
local bannerTop = (H.banner.CFrame * CFrame.new(0, 3, 0)).Position
ok((bannerTop - Vector3.new(6, 11, 0)).Magnitude < 1e-3, "the banner hangs from its top")
eq(H.sails.CFrame, CFrame.new(0, 30, 10), "spinning sails are left to regions.client.lua")
-- QC M1: only forge clones sway; server parts never move.
eq(H.tuft.CFrame, CFrame.new(3, 0.5, 3), "QC M1: herb tufts (server parts) never move")
eq(H.bare.CFrame, CFrame.new(-3, 6, -3), "QC M1: a server MeshPart without a forge link never moves")
ok(H.crop.CFrame ~= CFrame.new(4, 1, -3), "QC M1: CropBed clones sway")
-- QC M3: hosts that something else moves never sway.
eq(H.spunBanner.CFrame, CFrame.new(-6, 8, 0), "QC M3: a SpinRate / RegionSpin host is left alone")
eq(H.looseBanner.CFrame, CFrame.new(-6, 8, 4), "QC M3: an unanchored host is left alone")
-- QC M2: a hidden (depleted) prop is not swayed.
eq(H.hiddenTree.CFrame, CFrame.new(2, 6, 6), "QC M2: a hidden prop is skipped")
for i = 1, H.Amb.sway.count do assert(H.Amb.sway.active[i].part ~= H.hiddenTree, "hidden prop not in the active set") end
checks += 1
-- QC M3: the forge re-places a clone (its host moved): the rest frame re-arms.
do
	local e = H.trees[1]
	for _, x in H.trees do if x.base.Position.Magnitude < e.base.Position.Magnitude then e = x end end
	local entry
	for _, x in H.Amb.sway.list do if x.part == e.part then entry = x end end
	ok(entry and entry.epoch ~= 0, "the first tree sways")
	local newRest = e.base + Vector3.new(0, 0, 1.5)
	-- What the forge does: the host moves, its listener moves the clone; our
	-- next sway frame may overwrite the clone before the 2 Hz check runs.
	local host = e.part.Parent:FindFirstChild("MeadowTree host")
	for _, h in e.part.Parent:GetChildren() do
		local link = h:FindFirstChild("ShapeMesh")
		if link and link.Value == e.part then host = h end
	end
	host.CFrame = host.CFrame + Vector3.new(0, 0, 1.5)
	e.part.CFrame = newRest
	H.run(1 / 30)
	H.run(0.6)
	ok(entry.base and (entry.base.Position - newRest.Position).Magnitude < 1e-3, "QC M3: a moved clone re-arms its rest frame")
	ok((bottom(e.part.CFrame, e.part.Size) - bottom(newRest, e.part.Size)).Magnitude < 1e-3, "QC M3: and sways about its new base")
	e.base = newRest
end
-- QC M6: the per-frame sway cost at the High cap stays small.
do
	local t0 = os.clock()
	for _ = 1, 100 do H.Amb.swayFrame() end
	local ms = (os.clock() - t0) * 10
	print(string.format("  sway frame: %d props, %.3f ms per update (Lune harness)", H.Amb.sway.count, ms))
	ok(ms < 2, "QC M6: a High sway update (160 props) costs under 2 ms in the harness (" .. string.format("%.3f", ms) .. ")")
end
-- Pools.
local pools = H.Amb.pools
ok(pools.emitters.motes and pools.emitters.motes.Enabled, "region motes on outdoors")
eq(pools.emitters.motes:GetAttribute("Preset"), "pollen", "Sunwheel Downs motes are pollen")
-- QC M4: the island's Ambience attribute picks the motes (one palette).
H.isle:SetAttribute("Ambience", "embers")
H.run(0.5)
eq(pools.emitters.motes:GetAttribute("Preset"), "embers", "QC M4: the island's Ambience attribute picks the motes")
H.isle:SetAttribute("Ambience", nil)
H.run(0.5)
eq(pools.emitters.motes:GetAttribute("Preset"), "pollen", "no island ambience: the region's motes")
-- QC L4: a new outdoor context holds L.CONTEXT_HOLD before it applies.
H.attrs.IsleRegionHere = "Quarry"
H.run(0.3)
eq(H.Amb.key, "Meadow", "QC L4: a region change waits for the hold")
H.run(0.8)
eq(H.Amb.key, "Quarry", "QC L4: and applies after it")
H.attrs.IsleRegionHere = "Meadow"
H.run(1)
-- QC L10: anchors follow the player every frame.
do
	local air = pools.anchors.air
	H.root.CFrame = CFrame.new(12, 3, -7)
	H.run(1 / 30)
	ok((air.CFrame.Position - Vector3.new(12, 11, -7)).Magnitude < 1e-3, "QC L10: the motes box follows on the next frame")
	H.root.CFrame = CFrame.new(0, 3, 0)
	H.run(1)
end
local sourceOn = {}
for _, s in pools.sources do if s.emitter.Enabled then sourceOn[s.part] = s.emitter:GetAttribute("Preset") end end
eq(sourceOn[H.forgeNear], "embers", "embers over the near forge")
eq(sourceOn[H.shroom], "spores", "spores over the glowshroom")
ok(sourceOn[H.forgeFar] == nil, "a forge past the source radius gets nothing")
local shimmer = false
for _, kind in sourceOn do if kind == "shimmer" then shimmer = true end end
ok(shimmer, "the fishing spot shimmers")
ok(H.Amb.foam.count > 0 and H.Amb.foam.count <= hb.foam, "foam within its cap (" .. H.Amb.foam.count .. ")")
local fall = pools.falls[H.beam]
ok(fall and fall.sheet.Enabled and fall.spray.Enabled, "the near waterfall gets a sheet and spray")
eq(H.mist.Enabled, true, "near waterfall mist stays on")
ok(H.Amb.flock.count > 0 and H.Amb.flock.count <= hb.birds, "a flock circles the landmark (" .. H.Amb.flock.count .. ")")
local cloudCount = 0
for _, layer in pools.clouds do if layer.texture.Transparency < 1 then cloudCount += 1 end end
eq(cloudCount, hb.clouds, "High shows every cloud layer")
-- Clouds scroll (parallax: different speeds per layer), seamlessly wrapped.
local function offsets(i) return pools.clouds[i].texture.OffsetStudsU, pools.clouds[i].texture.OffsetStudsV end
local function moved1s(i, u0, v0)
	local tile = H.Amb.sky.LAYERS[i].tile
	local u, v = offsets(i)
	local du, dv = (u - u0) % tile, (v - v0) % tile
	if du > tile / 2 then du -= tile end
	if dv > tile / 2 then dv -= tile end
	ok(u >= 0 and u < tile and v >= 0 and v < tile, "cloud offsets stay inside one tile")
	return math.sqrt(du * du + dv * dv)
end
local u1, v1 = offsets(1)
local u3, v3 = offsets(3)
H.run(1)
local d1, d3 = moved1s(1, u1, v1), moved1s(3, u3, v3)
ok(d1 > d3 and d3 > 0, "cloud layers scroll at different speeds (" .. d1 .. " > " .. d3 .. ")")
ok(math.abs(d1 - H.Amb.sky.LAYERS[1].speed) < 0.3, "the top layer scrolls at its speed per second")

-- Weather.
local rain = pools.emitters.rain
ok(rain == nil or not rain.Enabled, "no rain without weather")
H.ws:SetAttribute("IsleWeather", "1|5|Meadow=Rain")
H.run(1)
rain = pools.emitters.rain
ok(rain and rain.Enabled and rain.Rate > 0, "rain falls in the region's rain")
eq(rain:GetAttribute("Preset"), "rain", "rain preset")
ok(pools.emitters.splash and pools.emitters.splash.Enabled, "High splashes under rain")
ok(H.Amb.emittingCount <= hb.emitters, "rain stays inside the emitter cap")
H.attrs.IsleRegionHere = "Skyreach"
H.ws:SetAttribute("IsleWeather", "1|5|Meadow=Rain,Skyreach=Snow")
H.run(1)
eq(rain:GetAttribute("Preset"), "snow", "cold Skyreach snows")
eq(pools.emitters.motes:GetAttribute("Preset"), "frost", "Skyreach motes are frost")
ok(not pools.emitters.splash.Enabled, "snow does not splash")
H.ws:SetAttribute("IsleWeather", "1|5|Skyreach=Fog")
H.run(1)
ok(not rain.Enabled, "rain stops when the weather clears")
ok(pools.emitters.fog and pools.emitters.fog.Enabled, "fog banks roll in")
-- QC H1: shelter is a building's declared box, never a raycast: a walk-in
-- hall with a mesh-only roof shelters, a tree canopy does not.
H.attrs.IsleRegionHere = "Meadow"
H.ws:SetAttribute("IsleWeather", "1|5|Meadow=Rain")
H.run(1.5)
ok(rain.Enabled, "rain in the open")
do
	local hall = roblox.Instance.new("Part")
	hall.Name, hall.Anchored, hall.Size, hall.CFrame = "Roofed hall floor", true, Vector3.new(16, 0.5, 13), CFrame.new(40, 0.25, -40) * CFrame.Angles(0, 0.6, 0)
	hall:SetAttribute("BuildingType", "ShopHall")
	hall:SetAttribute("ShapeBox", Vector3.new(17, 14, 14))
	hall:SetAttribute("ShapeBoxOffset", Vector3.new(0, 6.75, 0))
	hall.Parent = H.isle
	H.Amb.classify(hall) -- (DescendantAdded in the game)
	ok(H.Amb.shelteredAt(Vector3.new(40, 3, -40)), "QC H1: inside a hall (mesh-only roof) is sheltered")
	ok(not H.Amb.shelteredAt(Vector3.new(40, 3, -52)), "QC H1: beside the hall is not")
	ok(not H.Amb.shelteredAt(Vector3.new(40, 30, -40)), "QC H1: above the roof is not")
	H.root.CFrame = CFrame.new(40, 3, -40)
	H.run(1)
	ok(not rain.Enabled and not pools.emitters.splash.Enabled, "QC H1: no rain or splashes inside the hall")
	-- A canopy right overhead (a forged tree) does not stop the rain.
	H.root.CFrame = CFrame.new(10, 3, 11)
	local canopy = roblox.Instance.new("MeshPart")
	canopy.Name, canopy.Anchored, canopy.Size, canopy.CFrame = "Canopy", true, Vector3.new(14, 8, 14), CFrame.new(10, 12, 11)
	canopy.Parent = H.isle
	H.run(1)
	ok(not H.Amb.shelteredAt(Vector3.new(10, 3, 11)), "QC H1: under a tree canopy is not sheltered")
	ok(rain.Enabled, "QC H1: rain falls under trees")
	H.root.CFrame = CFrame.new(0, 3, 0)
	H.run(1)
end

-- QC H2: lightning from the shared schedule on server time. The attribute
-- names only the storm; every strike fires on the frame it is due.
local function nextStorm(key, from)
	local s0 = A.slotAt(from)
	for i = 1, 4000 do if A.weatherAt(s0 + i, key) == "Storm" then return s0 + i end end
	error("no storm for " .. key)
end
local function boltShowing(ctx)
	local parts = ctx.Amb.fx.bolt.parts
	return parts ~= nil and parts[1] ~= nil and parts[1].Transparency < 1
end
-- Run frames around strike `at`; returns the frame the cue fired (server time) or nil.
local function watchStrike(ctx, at, frames)
	local before = ctx.cueCount("thunder")
	local firedAt, bolt
	for _ = 1, frames do
		ctx.run(1 / 30)
		if not firedAt and ctx.cueCount("thunder") > before then firedAt = ctx.serverTime() end
		if boltShowing(ctx) then bolt = true end
	end
	return firedAt, bolt, ctx.cueCount("thunder") - before
end
local slotH = nextStorm("Meadow", H.serverTime())
local startH = A.EPOCH + slotH * A.SLOT
local strikesH = A.strikes(slotH, "Meadow")
H.setServer(startH - 0.5)
H.ws:SetAttribute("IsleWeather", A.encode(slotH - 1))
H.run(0.4)
-- The new slot's table arrives 0.3 s late; the first strike is >= 19 s away.
H.setServer(startH + 0.3)
H.ws:SetAttribute("IsleWeather", A.encode(slotH))
H.run(0.5)
eq(H.Amb.weather, "Storm", "the storm is on")
H.setServer(startH + strikesH[1] - 0.3)
local firedAt, bolt, cues = watchStrike(H, startH + strikesH[1], 30)
ok(firedAt ~= nil and firedAt >= startH + strikesH[1] and firedAt - (startH + strikesH[1]) <= 1 / 30 + 1e-6, "QC H2: the strike fires on its scheduled frame")
ok(bolt, "a storm strike shows a bolt")
eq(cues, 1, "the strike fires one thunder cue")
eq(#H.Amb.fx.bolt.parts, A.BOLT_SEGMENTS, "the bolt has its segments")
H.run(1)
ok(not boltShowing(H), "the bolt fades")
-- Weather delivered late relative to a strike: 0.3 s late still strikes (in
-- the schedule's phase); 0.6 s late is stale and skipped (no out-of-sync bolt).
for k, lateBy in {0.3, 0.6} do
	local at = startH + strikesH[1 + k]
	H.ws:SetAttribute("IsleWeather", "1|" .. slotH .. "|Meadow=Clear")
	H.setServer(at - 1)
	H.run(0.5)
	H.setServer(at + lateBy)
	H.ws:SetAttribute("IsleWeather", A.encode(slotH))
	H.Amb.readWeatherText() -- what GetAttributeChangedSignal does in the game
	local fired, _, n = watchStrike(H, at, 12)
	if lateBy < 0.5 then
		eq(n, 1, "QC H2: 0.3 s late delivery still strikes once")
		ok(fired ~= nil and fired - at <= lateBy + 1 / 30 + 1e-6, "QC H2: on the first frame after the delivery")
	else
		eq(n, 0, "QC H2: 0.6 s late delivery skips the stale strike")
	end
end
-- QC L6: Flashing effects off: no bolt, the cue still fires.
H.attrs.IsleSettingFlashing = false
H.run(0.5)
do
	local at = startH + strikesH[4]
	H.setServer(at - 0.3)
	local _, sawBolt, n = watchStrike(H, at, 20)
	ok(not sawBolt, "QC L6: Flashing effects off: no bolt")
	eq(n, 1, "QC L6: the thunder cue still fires")
end
H.attrs.IsleSettingFlashing = nil
H.ws:SetAttribute("IsleWeather", "1|" .. slotH .. "|Meadow=Clear")
H.run(0.5)
ok(H.parts() <= hb.parts, "High after weather + bolt: parts " .. H.parts())

-- Skill VFX.
local impactPos = H.root.CFrame.Position + Vector3.new(2, 0, 2)
H.bindables.IsleImpactLocal:Fire("mine", "chips", impactPos, true)
ok(H.Amb.fx.lastImpact == impactPos, "a local strike is remembered as the reward origin")
ok(pools.burst and pools.burst.part.CFrame.Position == impactPos, "sparks burst at the impact")
local chipColour = pools.burst.chips.Color.Keypoints[1].Value
local oreHex = Data.ResourceTiers.Mining[1].color
ok(chipColour:ToHex() == Color3.fromHex(oreHex):ToHex(), "chips take the struck ore's colour")
H.bindables.IsleXpLocal:Fire({{skill = "Mining", amount = 450, level = 5, color = "FFD166"}})
local orbsOn = 0
for _, o in H.Amb.fx.orbs do if o.on then orbsOn += 1 end end
eq(orbsOn, A.orbCount(450, hb), "XP orbs fly per the gain")
H.run(1.2)
orbsOn = 0
for _, o in H.Amb.fx.orbs do if o.on then orbsOn += 1 end end
eq(orbsOn, 0, "the orbs reach the player")
-- Level-up from snapshot levels (first snapshot seeds, the next one rises).
H.bindables.IsleSnapshotLocal:Fire({seq = 10, levels = {Mining = 5}})
eq(H.cueCount("levelup"), 0, "the first snapshot only seeds levels")
H.bindables.IsleSnapshotLocal:Fire({seq = 11, levels = {Mining = 6}})
eq(H.cueCount("levelup"), 1, "a level rise bursts and fires the levelup cue")
ok(H.Amb.fx.ring.on, "the level-up ring expands")
H.bindables.IsleSnapshotLocal:Fire({seq = 11, levels = {Mining = 7}})
eq(H.cueCount("levelup"), 1, "a replayed seq is ignored")
H.bindables.IsleSnapshotLocal:Fire({seq = 12, levels = {Mining = 7}, replay = true})
eq(H.cueCount("levelup"), 1, "an atlas replay is ignored")
-- Rarity pillars: colour = Data.Rarity of the item.
local seq = 20
for _, r in Data.RarityOrder do
	local id = byRarity[r]
	if id then
		seq += 1
		local before = H.cueCount("raredrop")
		H.run(0.1)
		H.bindables.IsleSnapshotLocal:Fire({seq = seq, pickups = {{id = id, n = 1}}})
		if Data.Rarity[r].rank >= A.BEAM_MIN_RANK then
			eq(H.cueCount("raredrop"), before + 1, r .. " drop raises a pillar")
			local newest
			for _, e in H.Amb.fx.beams do if e.on and (not newest or e.t0 >= newest.t0) then newest = e end end
			ok(newest ~= nil, r .. " pillar showing")
			eq(newest.core.Color:ToHex(), Color3.fromHex(Data.Rarity[r].color):ToHex(), r .. " pillar colour matches Data.Rarity")
			ok(#H.Amb.fx.beams <= hb.beams, "pillars within the cap")
		else
			eq(H.cueCount("raredrop"), before, r .. " drop raises no pillar")
		end
	end
end
H.run(8)
local beamsOn = 0
for _, e in H.Amb.fx.beams do if e.on then beamsOn += 1 end end
eq(beamsOn, 0, "pillars fade out")
ok(H.parts() <= hb.parts, "High after VFX: parts " .. H.parts() .. " <= " .. hb.parts)

-- Reduced motion: every swayed prop returns exactly to rest; no bolt; no ring.
H.attrs.IsleSettingReducedMotion = true
H.run(1)
eq(H.Amb.sway.count, 0, "reduced motion sways nothing")
for _, e in H.trees do assert(e.part.CFrame == e.base, "reduced motion restores every tree") end
checks += 1
eq(H.banner.CFrame, CFrame.new(6, 8, 0), "reduced motion restores the banner")
do
	H.ws:SetAttribute("IsleWeather", A.encode(slotH))
	local at = startH + strikesH[5]
	H.setServer(at - 0.4)
	local _, boltShown, n = watchStrike(H, at, 20)
	ok(not boltShown, "reduced motion: no bolt")
	eq(n, 1, "reduced motion still hears the thunder cue")
	-- QC L5: with reduced motion the foam is written once, then left alone.
	local writes = H.Amb.foam.writes
	H.run(1)
	eq(H.Amb.foam.writes, writes, "QC L5: still foam is not rewritten every frame")
	H.ws:SetAttribute("IsleWeather", "1|" .. slotH .. "|Meadow=Clear")
end
H.bindables.IsleSnapshotLocal:Fire({seq = 99, levels = {Mining = 8}})
ok(not H.Amb.fx.ring.on, "reduced motion: no level-up ring")
H.attrs.IsleSettingReducedMotion = nil
H.run(1)
ok(H.Amb.sway.count > 0, "sway resumes after reduced motion")

-- Culling by distance: walk far away.
H.root.CFrame = CFrame.new(3000, 3, 3000)
H.run(1.5)
eq(H.Amb.sway.count, 0, "nothing in range sways")
local restored = true
for _, e in H.trees do if e.part.CFrame ~= e.base then restored = false end end
ok(restored, "culled props return to rest")
ok(not pools.falls[H.beam].sheet.Enabled, "a far waterfall loses its sheet")
eq(H.mist.Enabled, false, "a far waterfall's mist is culled")
eq(H.Amb.flock.count, 0, "no flock without a landmark in range")
-- Interiors: no motes, weather or clouds.
H.root.CFrame = CFrame.new(3600, 300, -3600)
H.attrs.LairBoss = "Test"
H.ws:SetAttribute("IsleWeather", "1|6|Meadow=Rain")
H.run(1)
eq(H.Amb.key, "Lair", "inside a lair")
ok(not pools.emitters.motes.Enabled and not pools.emitters.rain.Enabled, "no motes or rain indoors")
for _, layer in pools.clouds do eq(layer.texture.Transparency, 1, "no cloud sea indoors") end

-- QC L7: an attribute the server sets after the part arrived is picked up by
-- the sliced rescan; a removed node is compacted away.
do
	H.root.CFrame = CFrame.new(0, 3, 0)
	H.attrs.LairBoss = nil
	H.run(1)
	local late = roblox.Instance.new("Part")
	late.Name, late.Anchored, late.CFrame = "Late node", true, CFrame.new(5, 1, 5)
	late.Parent = H.isle
	H.Amb.classify(late) -- arrives without GatherNode
	late:SetAttribute("GatherNode", Data.ResourceTiers.Mining[2].id)
	local found = false
	for _ = 1, 40 do
		H.run(0.5)
		for _, n in H.Amb.world.nodes do if n == late then found = true end end
		if found then break end
	end
	ok(found, "QC L7: a late GatherNode attribute is registered by the rescan")
	late.Parent = nil
	H.run(0.6)
	local still = false
	for _, n in H.Amb.world.nodes do if n == late then still = true end end
	ok(not still, "QC L7: a removed node is compacted")
end
-- QC L9: a pillar is never half-built at the part cap.
do
	local made = H.Amb.partsMade
	local beamsBefore = #H.Amb.fx.beams
	H.Amb.partsMade = H.Amb.b.parts - 1
	local partsBefore = H.parts()
	H.Amb.b = table.clone(H.Amb.b); H.Amb.b.beams += 2
	for _, e in H.Amb.fx.beams do e.on = true end -- every pillar busy: the next one must be new
	H.bindables.IsleSnapshotLocal:Fire({seq = 500, pickups = {{id = byRarity.Legendary, n = 1}}})
	eq(H.parts(), partsBefore, "QC L9: no lone pillar part past the cap")
	eq(#H.Amb.fx.beams, beamsBefore, "QC L9: no half pillar recorded")
	H.Amb.b = A.Budgets.High
	H.Amb.partsMade = made
end

-- Tier switch: Performance rebuilds inside its smaller caps.
H.attrs.LairBoss = nil
H.root.CFrame = CFrame.new(0, 3, 0)
H.attrs.IsleSettingGraphics = "Performance"
H.ws:SetAttribute("IsleWeather", A.encode(slotH))
H.run(2)
local pb = A.Budgets.Performance
eq(H.Amb.budgetKey, "Performance", "the tier switch is live")
ok(H.parts() <= pb.parts, "Performance: parts " .. H.parts() .. " <= " .. pb.parts)
ok(H.Amb.emittingCount <= pb.emitters, "Performance: emitters " .. H.Amb.emittingCount .. " <= " .. pb.emitters)
eq(H.enabledEmitters(), H.Amb.emittingCount, "Performance: no orphaned emitters after the rebuild")
ok(H.Amb.sway.count <= pb.sway, "Performance sways at most " .. pb.sway)
eq(H.Amb.foam.count, 0, "Performance draws no foam")
eq(H.Amb.flock.count, 0, "Performance draws no birds")
ok(pools.emitters.rain and pools.emitters.rain.Enabled, "Performance still rains")
for _, e in H.trees do
	if e.part.CFrame ~= e.base then assert((e.base.Position - H.root.CFrame.Position).Magnitude <= pb.swayRadius, "Performance culls sway at its radius") end
end
checks += 1

-- Phones: the lite set.
local P = boot({tier = "High", phone = true})
local slotP = nextStorm("Meadow", P.serverTime())
local startP, strikesP = A.EPOCH + slotP * A.SLOT, A.strikes(slotP, "Meadow")
P.setServer(startP + 1)
P.ws:SetAttribute("IsleWeather", A.encode(slotP))
P.run(3)
local lb = A.Budgets.Lite
eq(P.Amb.budgetKey, "Lite", "a phone on High runs the lite set")
ok(P.parts() <= lb.parts, "Lite: parts " .. P.parts() .. " <= " .. lb.parts)
ok(P.Amb.emittingCount <= lb.emitters, "Lite: emitters " .. P.Amb.emittingCount .. " <= " .. lb.emitters)
ok(P.Amb.sway.count <= lb.sway, "Lite sway cap")
ok(P.Amb.foam.count <= lb.foam, "Lite foam cap")
ok(P.Amb.flock.count == 0, "storms ground the flocks")
ok(P.Amb.pools.emitters.splash == nil, "phones draw no splashes")
P.setServer(startP + strikesP[1] - 0.3)
local _, phoneBolt, phoneCues = watchStrike(P, startP + strikesP[1], 20)
ok(not phoneBolt and P.Amb.fx.bolt.parts == nil, "phones draw no bolt")
eq(phoneCues, 1, "phones still get the thunder cue")
for _, e in P.trees do
	if e.part.CFrame ~= e.base then assert((e.base.Position - P.root.CFrame.Position).Magnitude <= lb.swayRadius, "Lite culls sway at its radius") end
end
checks += 1

print("PASS: " .. checks .. " ambience checks.")
print("SUITE-END verify-ambience.luau")
