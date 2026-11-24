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
local key, at = A.latestStrike(start + strikes[1] + 0.5, 3)
ok(at ~= nil and math.abs(at - (start + strikes[1])) < 1e-6 and A.weatherAt(stormSlot, key) == "Storm", "latestStrike finds the fresh strike")
ok(A.latestStrike(start + strikes[1] - 0.01, 3) == nil or select(2, A.latestStrike(start + strikes[1] - 0.01, 3)) < start + strikes[1], "never a strike from the future")
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
local tA = start + strikes[2] + 0.4
local W1, ws1 = weatherServer(tA)
local _, ws2 = weatherServer(tA)
ok(type(ws1:GetAttribute("IsleWeather")) == "string", "the server publishes IsleWeather")
eq(ws1:GetAttribute("IsleWeather"), ws2:GetAttribute("IsleWeather"), "two servers at the same time publish the same weather")
local live = L.parseWeather(ws1:GetAttribute("IsleWeather"))
ok(live and live.slot == stormSlot and live.regions.Tempest == "Storm", "the published slot table parses")
ok(live.strikeRegion ~= nil and math.abs(live.strikeAt - (start + strikes[2])) < 0.01, "the strike rides the attribute as a world event")
local _, ws3 = weatherServer(tA + 3.5)
local later = L.parseWeather(ws3:GetAttribute("IsleWeather"))
ok(later.strikeRegion == nil or later.strikeAt ~= live.strikeAt, "an old strike is not replayed to late joiners")
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
		require = function(name) if name == "AetherLighting" then return L elseif name == "AetherData" then return Data end error("unexpected require " .. tostring(name)) end,
		os = {time = function() return serverT end, clock = os.clock},
		task = {defer = function(f) f() end, spawn = function(f) f() end},
	}
	local D = luau.load(fs.readFile("lighting.client.lua"), {debugName = "lighting.client.lua", environment = env, injectGlobals = true})()
	local function run(seconds) for _ = 1, math.ceil(seconds * 30) do heartbeat:Fire(1 / 30) end end
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
	-- A strike in the player's region flashes; elsewhere or under reduced motion it does not.
	attrs.IsleRegionHere = "Meadow"
	run(2)
	local before = Lighting.ExposureCompensation
	ws:SetAttribute("IsleWeather", "1|5|Meadow=Storm|Meadow@" .. string.format("%.2f", serverT - 0.02))
	run(0.1)
	ok(Lighting.ExposureCompensation > before + 0.3, "lightning flashes the exposure (" .. before .. " -> " .. Lighting.ExposureCompensation .. ")")
	ok(Lighting.ExposureCompensation <= L.FLASH_CEILING + 1e-6, "flash ceiling")
	ok(D.state.ExposureCompensation <= 0.5 + 1e-6, "the flash never enters the blended state")
	serverT += 5
	run(1)
	ok(math.abs(Lighting.ExposureCompensation - D.state.ExposureCompensation) < 2e-3, "the flash ends")
	attrs.IsleSettingReducedMotion = true
	local calm = Lighting.ExposureCompensation
	ws:SetAttribute("IsleWeather", "1|5|Meadow=Storm|Meadow@" .. string.format("%.2f", serverT - 0.02))
	run(0.1)
	ok(math.abs(Lighting.ExposureCompensation - calm) < 0.05, "reduced motion: no flash")
	attrs.IsleSettingReducedMotion = nil
	serverT += 2
	run(0.5)
	calm = Lighting.ExposureCompensation
	ws:SetAttribute("IsleWeather", "1|5|Meadow=Storm|Hub@" .. string.format("%.2f", serverT))
	run(0.1)
	ok(math.abs(Lighting.ExposureCompensation - calm) < 0.05, "a strike in another region does not flash here")
end

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
for _, name in {"sky", "sway", "foam", "flock", "fx"} do ok(blocks[name] ~= nil and #blocks[name] > 200, "per-frame block " .. name) end
local FORBIDDEN = {"{", "function(", "Instance.new", "..", "table.insert", "table.create", "ColorSequence", "NumberSequence", "NumberRange", ":Clone", "string.", "setmetatable", "pairs("}
for name, body in blocks do
	ok(select(2, string.gsub(body, "function ", "")) == 1, name .. " block is one function")
	for _, word in FORBIDDEN do
		ok(not string.find(body, word, 1, true), name .. " frame block allocates nothing: " .. word)
	end
end
for _, call in {"Sky.frame(dt)", "Sway.frame()", "Foam.frame()", "Flock.frame(dt)", "FX.frame()"} do ok(string.find(code, call, 1, true) ~= nil, call .. " runs from the step") end
local _, beats = string.gsub(code, '"Heartbeat"', "")
eq(beats, 1, "one Heartbeat connection")
ok(string.find(code, "if not Amb.reduced then Sway.frame() end", 1, true) ~= nil, "reduced motion: no sway")
ok(string.find(code, "if Amb.reduced or Amb.b.bolts <= 0 then return end", 1, true) ~= nil, "reduced motion: no bolt")
for _, word in {'GetService("Lighting")', "game.Lighting", "PlayerGui", "ScreenGui", "BillboardGui", "SurfaceGui", "IsleAction", "FireServer", "InvokeServer", "creatures"} do
	ok(not string.find(code, word, 1, true), "the ambience layer never touches " .. word)
end
ok(string.find(code, "workspace:BulkMoveTo", 1, true) ~= nil, "sway moves with BulkMoveTo")
local director = fs.readFile("lighting.client.lua")
ok(string.find(director, "L.applyWeather(target, L.blendWeather(Weather.delta, Weather.state", 1, true) ~= nil, "the director blends the weather deltas")
ok(string.find(director, "Weather.strikeRegion == Director.key and not reducedMotion()", 1, true) ~= nil, "the director's flash honours region and reduced motion")
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
	-- 240 forged trees on a grid out to ~170 studs, plus a few far ones.
	local trees = {}
	for i = 0, 239 do
		local x, z = (i % 16 - 7.5) * 20, (math.floor(i / 16) - 7) * 22
		local t = newPart("MeshPart", "Meadow tree Mesh", Vector3.new(x, 6, z), Vector3.new(8, 12, 8), isle)
		t:SetAttribute("ShapeOf", "MeadowTree")
		table.insert(trees, {part = t, base = t.CFrame})
	end
	local farTrees = {}
	for i = 1, 5 do
		local t = newPart("MeshPart", "Far tree Mesh", Vector3.new(600 + i * 30, 6, 0), Vector3.new(8, 12, 8), isle)
		t:SetAttribute("ShapeOf", "PalmTree")
		table.insert(farTrees, {part = t, base = t.CFrame})
	end
	local banner = newPart("MeshPart", "Banner Mesh", Vector3.new(6, 8, 0), Vector3.new(0.3, 6, 3), isle)
	banner:SetAttribute("ShapeOf", "Banner")
	local sails = newPart("MeshPart", "Sails Mesh", Vector3.new(0, 30, 10), Vector3.new(30, 30, 2), isle)
	sails:SetAttribute("ShapeOf", "WindmillSails")
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
		os = {time = function() return math.floor(serverT) end, clock = function() return clockT end},
	}
	local Amb = luau.load(src, {debugName = "ambience.client.lua", environment = env, injectGlobals = true})()
	local ctx = {Amb = Amb, ws = ws, attrs = attrs, root = root, trees = trees, farTrees = farTrees, banner = banner, sails = sails, tuft = tuft,
		forgeNear = forgeNear, forgeFar = forgeFar, shroom = shroom, beam = beam, mist = mist, cues = cues, bindables = bindables, isle = isle, ore = ore}
	function ctx.run(seconds)
		local n = math.ceil(seconds * 30)
		for _ = 1, n do
			clockT += 1 / 30
			serverT += 1 / 30
			heartbeat:Fire(1 / 30)
		end
	end
	function ctx.serverTime() return math.floor(serverT) + (clockT % 1) end
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
ok(H.tuft.CFrame ~= CFrame.new(3, 0.5, 3), "herb tufts sway")
-- Pools.
local pools = H.Amb.pools
ok(pools.emitters.motes and pools.emitters.motes.Enabled, "region motes on outdoors")
eq(pools.emitters.motes:GetAttribute("Preset"), "pollen", "Sunwheel Downs motes are pollen")
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
-- Lightning: a strike in this region shows a bolt and fires the thunder cue.
H.attrs.IsleRegionHere = "Meadow"
H.run(0.5)
H.ws:SetAttribute("IsleWeather", "1|5|Meadow=Storm|Meadow@" .. string.format("%.2f", H.serverTime()))
local boltSeen = false
for _ = 1, 12 do
	H.run(1 / 30)
	local parts = H.Amb.fx.bolt.parts
	if parts and parts[1] and parts[1].Transparency < 1 then boltSeen = true end
end
ok(boltSeen, "a storm strike shows a bolt")
eq(H.cueCount("thunder"), 1, "the strike fires one thunder cue")
eq(#H.Amb.fx.bolt.parts, A.BOLT_SEGMENTS, "the bolt has its segments")
H.run(1)
ok(H.Amb.fx.bolt.parts[1].Transparency == 1, "the bolt fades")
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
local thunder = H.cueCount("thunder")
H.ws:SetAttribute("IsleWeather", "1|6|Meadow=Storm|Meadow@" .. string.format("%.2f", H.serverTime()))
local boltShown = false
for _ = 1, 12 do
	H.run(1 / 30)
	if H.Amb.fx.bolt.parts[1].Transparency < 1 then boltShown = true end
end
ok(not boltShown, "reduced motion: no bolt")
eq(H.cueCount("thunder"), thunder + 1, "reduced motion still hears the thunder cue")
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

-- Tier switch: Performance rebuilds inside its smaller caps.
H.attrs.LairBoss = nil
H.root.CFrame = CFrame.new(0, 3, 0)
H.attrs.IsleSettingGraphics = "Performance"
H.ws:SetAttribute("IsleWeather", "1|7|Meadow=Storm")
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
P.ws:SetAttribute("IsleWeather", "1|5|Meadow=Storm")
P.run(3)
local lb = A.Budgets.Lite
eq(P.Amb.budgetKey, "Lite", "a phone on High runs the lite set")
ok(P.parts() <= lb.parts, "Lite: parts " .. P.parts() .. " <= " .. lb.parts)
ok(P.Amb.emittingCount <= lb.emitters, "Lite: emitters " .. P.Amb.emittingCount .. " <= " .. lb.emitters)
ok(P.Amb.sway.count <= lb.sway, "Lite sway cap")
ok(P.Amb.foam.count <= lb.foam, "Lite foam cap")
ok(P.Amb.flock.count == 0, "storms ground the flocks")
ok(P.Amb.pools.emitters.splash == nil, "phones draw no splashes")
P.ws:SetAttribute("IsleWeather", "1|5|Meadow=Storm|Meadow@" .. string.format("%.2f", P.serverTime()))
P.run(0.5)
ok(P.Amb.fx.bolt.parts == nil, "phones draw no bolt")
eq(P.cueCount("thunder"), 1, "phones still get the thunder cue")
for _, e in P.trees do
	if e.part.CFrame ~= e.base then assert((e.base.Position - P.root.CFrame.Position).Magnitude <= lb.swayRadius, "Lite culls sway at its radius") end
end
checks += 1

print("PASS: " .. checks .. " ambience checks.")
print("SUITE-END verify-ambience.luau")
