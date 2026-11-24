-- Lighting director (StarterPlayerScripts.IsleLighting; docs/DEPTH-CONTRACT.md §35).
-- The ONE writer of Lighting properties and Lighting children in the game
-- (verify-lighting.luau greps every other script). It owns:
--   * the day-night cycle: Lighting.ClockTime follows the server-authoritative
--     isle clock (Data.Calendar, the same hour the sidebar shows), smoothly;
--   * per-region and interior profiles (shared/LightingProfiles.lua) blended
--     exponentially when the player's context changes, with a short hold so a
--     bridge between two isles never flickers between profiles;
--   * one Atmosphere, Sky, BloomEffect, SunRaysEffect and ColorCorrectionEffect
--     (any other effect parented to Lighting is removed);
--   * the world light budget: authored lights in the static world roots are
--     culled by distance and capped per graphics tier (nearest first), night
--     lamps (NightLight attribute) burn only after dusk, and a small pool of
--     client glow lights lights lamp / lantern meshes that carry no light;
--   * the graphics tier (player attribute IsleSettingGraphics: High /
--     Balanced / Performance; set from the device on first run, changed in
--     Menu › Settings).
-- It never touches GUI: ViewportFrames (Sky Chart, thumbnails) keep their own
-- Ambient / LightColor, and post effects live under Lighting (3D only).
--
-- Server intent (QC M1): the budget writes Enabled / Shadows on authored
-- lights, so it can never read them back as "what the server wants". The
-- server states intent in attributes this script never writes: LightWanted
-- (bool; set wherever a server script toggles a world light, e.g.
-- world.server.lua light() and homePlacement.relight) and LightHero (bool:
-- an authored shadow caster). A light without them falls back to its
-- Enabled / Shadows at registration (and adopts later server edits by diff).
--
-- Type mode (QC L8): not --!strict. The build has no Luau type checker (the
-- headless suites run under Lune, which ignores the directive), so strict
-- annotations here could not be verified; the module is kept small and its
-- rules live in the pure shared/LightingProfiles.lua, which the suite covers.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local L = require(ReplicatedStorage:WaitForChild("AetherLighting"))
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local player = Players.LocalPlayer

local Director = {key = nil, pendingKey = nil, pendingSince = 0, state = nil, written = {}, tier = nil, clock = 12}
local OWNED = "AetherLightingDirector" -- attribute on the instances this script created
local WANTED, HERO = "LightWanted", "LightHero" -- server-intent attributes (read only here)

local function connect(inst, signalName, fn)
	local ok, signal = pcall(function() return inst[signalName] end)
	if not ok or signal == nil then return nil end
	local ok2, connection = pcall(function() return signal:Connect(fn) end)
	return if ok2 then connection else nil
end
local function now()
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	if ok and type(t) == "number" and t > 1e9 then return t end
	return os.time()
end

------------------------------------------------------------------------------
-- Graphics tier.
------------------------------------------------------------------------------
local function device()
	local d = {}
	pcall(function()
		local input = game:GetService("UserInputService")
		d.touch, d.keyboard, d.gamepad = input.TouchEnabled, input.KeyboardEnabled, input.GamepadEnabled
	end)
	pcall(function() d.viewportX = workspace.CurrentCamera.ViewportSize.X end)
	pcall(function()
		local q = UserSettings().GameSettings.SavedQualityLevel
		if q ~= Enum.SavedQualitySetting.Automatic then d.quality = q.Value end
	end)
	return d
end
local function readTier()
	local v = player:GetAttribute(L.SETTING_ATTR)
	local tier = L.readTier(v, device())
	-- Publish the default once so Settings shows the live choice; the player's
	-- own choice (set by Settings) is never overwritten.
	if v ~= tier then player:SetAttribute(L.SETTING_ATTR, tier) end
	return tier
end

------------------------------------------------------------------------------
-- Owned Lighting children.
------------------------------------------------------------------------------
local FX = {}
local function own(class, name)
	local inst = Instance.new(class)
	inst.Name = name
	inst:SetAttribute(OWNED, true)
	inst.Parent = Lighting
	return inst
end
local function sweepForeign()
	for _, child in ipairs(Lighting:GetChildren()) do
		if (child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds")) and child:GetAttribute(OWNED) ~= true then
			pcall(child.Destroy, child) -- QC L5: a locked / foreign instance must not stop the sweep
		end
	end
end
sweepForeign()
FX.air = own("Atmosphere", "Aether air")
FX.sky = own("Sky", "Aether sky")
FX.sky.StarCount, FX.sky.SunAngularSize, FX.sky.MoonAngularSize = 3000, 12, 9
FX.bloom = own("BloomEffect", "Aether bloom")
FX.rays = own("SunRaysEffect", "Aether sun rays")
FX.grade = own("ColorCorrectionEffect", "Aether grade")
connect(Lighting, "ChildAdded", function(child)
	if child:GetAttribute(OWNED) ~= true and (child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds")) then
		task.defer(function() if child.Parent == Lighting then pcall(child.Destroy, child) end end)
	end
end)

-- Field -> (instance, property).
local TARGETS = {
	Brightness = {Lighting, "Brightness"}, ExposureCompensation = {Lighting, "ExposureCompensation"},
	Ambient = {Lighting, "Ambient"}, OutdoorAmbient = {Lighting, "OutdoorAmbient"},
	ColorShift_Top = {Lighting, "ColorShift_Top"}, ColorShift_Bottom = {Lighting, "ColorShift_Bottom"},
	EnvironmentDiffuseScale = {Lighting, "EnvironmentDiffuseScale"}, EnvironmentSpecularScale = {Lighting, "EnvironmentSpecularScale"},
	ShadowSoftness = {Lighting, "ShadowSoftness"},
	AtmDensity = {FX.air, "Density"}, AtmOffset = {FX.air, "Offset"}, AtmColor = {FX.air, "Color"}, AtmDecay = {FX.air, "Decay"},
	AtmGlare = {FX.air, "Glare"}, AtmHaze = {FX.air, "Haze"},
	BloomIntensity = {FX.bloom, "Intensity"}, BloomSize = {FX.bloom, "Size"}, BloomThreshold = {FX.bloom, "Threshold"},
	RaysIntensity = {FX.rays, "Intensity"}, RaysSpread = {FX.rays, "Spread"},
	GradeBrightness = {FX.grade, "Brightness"}, GradeContrast = {FX.grade, "Contrast"},
	GradeSaturation = {FX.grade, "Saturation"}, GradeTint = {FX.grade, "TintColor"},
}
local function same(a, b)
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return math.abs(a.R - b.R) < 1 / 512 and math.abs(a.G - b.G) < 1 / 512 and math.abs(a.B - b.B) < 1 / 512
	end
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-3
end
local function write(field, value)
	if same(Director.written[field], value) then return end
	local t = TARGETS[field]
	t[1][t[2]] = value
	Director.written[field] = value
end
------------------------------------------------------------------------------
-- Weather (§50): the server's IsleWeather attribute (one string, a
-- deterministic schedule; shared/Ambience.lua writes it, L.parseWeather reads
-- it) names a state per region; it is read when it changes
-- (GetAttributeChangedSignal; a poll only where that signal is missing). Its
-- deltas (L.WEATHER) ease in over L.WEATHER_TAU on top of the region look:
-- rain / storm dim the sun, thicken the haze and raise
-- EnvironmentSpecularScale (wet sheen). Entering or leaving an interior snaps
-- the deltas (QC M5: no storm haze bleeding into a lair). Lightning (QC H2):
-- strikes come from the same deterministic schedule (AetherAmbience
-- A.strikes) on server time, so every client flashes on the same frame with no
-- network latency; the flash obeys the region, reduced motion and the
-- "Flashing effects" setting, and is softer at night (QC L6).
------------------------------------------------------------------------------
local Ambience
do
	local ok, module = pcall(function() return require(ReplicatedStorage:WaitForChild("AetherAmbience")) end)
	if ok and type(module) == "table" then Ambience = module end
end
local Weather = {text = nil, parsed = nil, state = "Clear", delta = {}, flash = 0, interior = nil, flashing = true,
	cursor = Ambience and Ambience.newStrikeCursor() or nil, watched = false}
Director.weather = Weather -- read by the headless suites
local function reducedMotion()
	if player:GetAttribute("IsleSettingReducedMotion") == true then return true end
	local ok, on = pcall(function() return game:GetService("GuiService").ReducedMotionEnabled end)
	return ok and on == true
end
function Weather.readText()
	local text = workspace:GetAttribute(L.WEATHER_ATTR)
	if text ~= Weather.text then
		Weather.text = text
		Weather.parsed = L.parseWeather(text)
	end
end
Weather.watched = pcall(function()
	workspace:GetAttributeChangedSignal(L.WEATHER_ATTR):Connect(Weather.readText)
end)
Weather.readText()
-- 4 Hz: the state for the current context, the flashing permission, M5 snap.
function Weather.resolve()
	if not Weather.watched then Weather.readText() end
	local key = Director.key or L.DEFAULT_KEY
	Weather.state = L.weatherFor(Weather.parsed, key)
	Weather.flashing = L.flashingAllowed(player:GetAttribute(L.FLASHING_ATTR), reducedMotion())
	local interior = L.Profiles[key] ~= nil and L.Profiles[key].interior == true
	if interior ~= Weather.interior then
		if Weather.interior ~= nil then L.blendWeather(Weather.delta, Weather.state, 1) end
		Weather.interior = interior
	end
end
Weather.read = Weather.resolve
local function applyState(state)
	for _, f in ipairs(L.FIELDS) do
		local v = state[f.key]
		if Weather.flash > 0 and f.key == "ExposureCompensation" then v = L.flashExposure(v, Weather.flash, L.dayFactor(Director.clock)) end
		write(f.key, v)
	end
end
-- Per frame, only in a storm: the flash outruns the 15 Hz blend.
function Weather.flashStep()
	if Director.state == nil or not Weather.cursor then return end
	local f = 0
	if Weather.state == "Storm" and Weather.flashing then
		local t = now()
		local at = Ambience.lastStrike(Weather.cursor, t, Director.key or L.DEFAULT_KEY)
		if at then f = L.flashAt(t - at) end
	end
	if f <= 0 and Weather.flash <= 0 then return end
	Weather.flash = f
	write("ExposureCompensation", L.flashExposure(Director.state.ExposureCompensation, f, L.dayFactor(Director.clock)))
end
local function applyTier(tierName)
	local tier = L.Tiers[tierName]
	Lighting.GlobalShadows = tier.globalShadows
	FX.bloom.Enabled, FX.rays.Enabled, FX.grade.Enabled = tier.bloom, tier.rays, tier.grade
end

------------------------------------------------------------------------------
-- Context (which profile) with a hold against flicker on bridges.
------------------------------------------------------------------------------
local HOLD = L.CONTEXT_HOLD or 0.6 -- seconds a new outdoor context must persist before it blends in (shared with §50, QC L4)
local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then return root.CFrame.Position end
	local ok, pos = pcall(function() return workspace.CurrentCamera.Focus.Position end)
	return if ok then pos else nil
end
local function contextNow()
	return L.context({
		LairBoss = player:GetAttribute("LairBoss"), RaidRun = player:GetAttribute("RaidRun"), DungeonInRun = player:GetAttribute("DungeonInRun"),
		MinigameGame = player:GetAttribute("MinigameGame"), IsleRegionHere = player:GetAttribute("IsleRegionHere"),
	}, rootPosition())
end
local function updateContext(t)
	local key = contextNow()
	if key == Director.key then Director.pendingKey = nil return end
	local interior = L.Profiles[key] and L.Profiles[key].interior
	if Director.key == nil or interior or (Director.key and L.Profiles[Director.key].interior) then
		Director.key, Director.pendingKey = key, nil -- teleports into / out of arenas switch at once
		return
	end
	if Director.pendingKey ~= key then Director.pendingKey, Director.pendingSince = key, t return end
	if t - Director.pendingSince >= HOLD then Director.key, Director.pendingKey = key, nil end
end

------------------------------------------------------------------------------
-- Light budget.
------------------------------------------------------------------------------
local ROOT_NAMES = {AetherIsles = true, Islands = true, Townsfolk = true, LairInstances = true, RaidInstances = true, ["The Hollow Observatory"] = true}
pcall(function() ROOT_NAMES[Data.Minigames.ISLAND] = true end)
-- QC L1: entries / recs / selectLights scratch are reused every update.
local Lights = {list = {}, byLight = {}, sites = {}, bySite = {}, pool = {}, poolFolder = nil, connected = false,
	entries = {}, recs = {}, entryPool = {}, scratch = {}, dirty = false}
Director.lights = Lights -- read by the headless suite
-- Position of a light's host, and whether it can be cached (anchored host:
-- the cache is dropped on every 10 s rescan, so a moved prop catches up).
local function lightPos(l)
	local host = l.Parent
	if host and host:IsA("Attachment") and host.Parent and host.Parent:IsA("BasePart") then
		return (host.Parent.CFrame * host.CFrame).Position, host.Parent.Anchored
	end
	if host and host:IsA("BasePart") then return host.CFrame.Position, host.Anchored end
	return nil, false
end
local function boolAttr(inst, name)
	local v = inst:GetAttribute(name)
	return if type(v) == "boolean" then v else nil
end
local function watchAttr(inst, name)
	local ok, connection = pcall(function()
		return inst:GetAttributeChangedSignal(name):Connect(function() Lights.dirty = true end)
	end)
	return if ok then connection else nil
end
local dropSite
local function register(l)
	if Lights.byLight[l] or l:GetAttribute(OWNED) then return end
	local night = l:GetAttribute("NightLight") == true
	local wanted, hero = boolAttr(l, WANTED), boolAttr(l, HERO)
	-- Legacy lights (no LightWanted): a night lamp is wanted (it is created off
	-- and lit after dusk); any other light is wanted if it starts enabled.
	if wanted == nil then wanted = night or l.Enabled end
	if hero == nil then hero = l.Shadows == true end
	local rec = {light = l, night = night, base = wanted, brightness = l.Brightness,
		hero = hero, enabled = l.Enabled, bright = l.Brightness, shadows = l.Shadows,
		conns = {watchAttr(l, WANTED), watchAttr(l, HERO)}}
	Lights.byLight[l] = rec
	table.insert(Lights.list, rec)
	-- QC M2: a glow site registered before its own light arrived (streaming,
	-- a late placement) must stop drawing a pooled light: drop any site that is
	-- the light's host or an ancestor (3 levels), or a part of a small model on
	-- that path (the same rule as hasOwnLight below).
	local anc = l.Parent
	for _ = 1, 3 do
		if not anc then break end
		local site = Lights.bySite[anc]
		if site then dropSite(site) end
		if anc:IsA("Model") and #anc:GetChildren() <= 12 then
			for _, child in ipairs(anc:GetChildren()) do
				local s = Lights.bySite[child]
				if s then dropSite(s) end
			end
		end
		anc = anc.Parent
	end
end
local function hasOwnLight(part)
	if part:FindFirstChildWhichIsA("Light", true) then return true end
	local model = part.Parent
	if model and model:IsA("Model") and #model:GetChildren() <= 12 and model:FindFirstChildWhichIsA("Light", true) then return true end
	return false
end
dropSite = function(site)
	site.dead = true
	if Lights.bySite[site.part] == site then Lights.bySite[site.part] = nil end
	Lights.dirty = true
end
local function registerSite(part)
	if Lights.bySite[part] then return end
	local kind = part:GetAttribute("GlowSite")
	if type(kind) ~= "string" or not L.GLOW_KINDS[kind] then
		local shape = part:GetAttribute("Shape")
		kind = type(shape) == "string" and L.GLOW_SHAPES[shape] or nil
	end
	if not kind or hasOwnLight(part) then return end
	local site = {part = part, kind = kind}
	Lights.bySite[part] = site
	table.insert(Lights.sites, site)
end
-- Lit windows (World Art pass 2, §40): building hosts with WindowGlow pane
-- rects. After dusk the nearest buildings (L.selectWindows: tier range,
-- building and pane caps) show warm Neon panes from a local pool (no lights,
-- shadows or collision); by day, or out of range, the panes go back to the
-- pool. Panes follow the host's CFrame at each update (anchored hosts never
-- move). Allocation: one entry per building, panes pooled and reused.
local Windows = {list = {}, byHost = {}, pool = {}, used = 0, folder = nil, chosen = {}, entries = {}, lastPanes = 0}
Director.windows = Windows -- read by the headless suites
local function registerWindows(part)
	if Windows.byHost[part] then return end
	local panes = L.parseWindows(part:GetAttribute("WindowGlow"))
	if #panes == 0 then return end
	local p = part.CFrame.Position
	local entry = {part = part, panes = panes, count = 0, seed = math.floor(p.X * 7 + p.Z * 13)}
	for i = 1, #panes do if L.windowLit(entry.seed, i) then entry.count += 1 end end
	Windows.byHost[part] = entry
	table.insert(Windows.list, entry)
end
local function windowPane(i)
	local pane = Windows.pool[i]
	if pane then return pane end
	if not Windows.folder then
		Windows.folder = Instance.new("Folder")
		Windows.folder.Name = "IsleWindowGlow"
		Windows.folder.Parent = workspace
	end
	pane = Instance.new("Part")
	pane.Name, pane.Anchored, pane.CanCollide, pane.CanQuery, pane.CanTouch = "Window glow", true, false, false, false
	pane.CastShadow, pane.Material, pane.Color = false, Enum.Material.Neon, Color3.fromHex(L.WINDOW_COLOR)
	pane.Transparency = 1
	pane.Parent = Windows.folder
	Windows.pool[i] = pane
	return pane
end
-- §40 QC M3: on phones the forge meshes building shells only within 120 studs
-- (forge.client.lua BUILDING_RADIUS.shell); beyond it a house is its plaster
-- block, so panes are capped there too.
Windows.mobile = false
pcall(function()
	local input = game:GetService("UserInputService")
	Windows.mobile = input.TouchEnabled == true and input.KeyboardEnabled ~= true
end)
Windows.prev = {}
function Windows.update(tierName, nightness)
	local origin = rootPosition()
	local list, entries = Windows.list, Windows.entries
	table.clear(entries)
	local kept, n = 0, 0
	for i = 1, #list do
		local e = list[i]
		if e.part.Parent and e.part:IsDescendantOf(workspace) then
			kept += 1
			list[kept] = e
			-- Panes are the kit mesh's windows: an unforged host is a plain
			-- plaster block, so its panes would float around it (QC M3).
			if e.part:GetAttribute("ShapeDone") == true then
				n += 1
				e.pos = e.part.CFrame.Position
				entries[n] = e
			end
		else
			Windows.byHost[e.part] = nil
		end
	end
	for i = kept + 1, #list do list[i] = nil end
	local chosen, total = L.selectWindows(entries, origin, tierName, nightness >= 0.5, Windows.chosen,
		if Windows.mobile then L.WINDOW_MOBILE_RANGE else nil)
	-- QC L4: the same hosts as last update -> the panes already stand there.
	local prev, same = Windows.prev, #chosen == #Windows.prev
	if same then
		for k, index in ipairs(chosen) do if prev[k] ~= entries[index] then same = false break end end
	end
	if same then
		Windows.skipped = (Windows.skipped or 0) + 1
		return Windows.lastPanes, total
	end
	table.clear(prev)
	for k, index in ipairs(chosen) do prev[k] = entries[index] end
	local used = 0
	for _, index in ipairs(chosen) do
		local e = entries[index]
		local cf = e.part.CFrame
		for i, v in ipairs(e.panes) do
			if L.windowLit(e.seed, i) then
				used += 1
				local pane = windowPane(used)
				pane.Size = Vector3.new(v[4] * 0.94, v[5] * 0.94, 0.04)
				pane.CFrame = cf * CFrame.new(v[1], v[2], v[3]) * CFrame.Angles(0, v[6], 0) * CFrame.new(0, 0, -0.03)
				if pane.Transparency ~= L.WINDOW_TRANSPARENCY then pane.Transparency = L.WINDOW_TRANSPARENCY end
			end
		end
	end
	for i = used + 1, Windows.used do
		local pane = Windows.pool[i]
		if pane and pane.Transparency ~= 1 then pane.Transparency = 1 end
	end
	Windows.used = math.max(used, 0)
	Windows.lastPanes = used
	return used, total
end
local function consider(inst)
	if inst:IsA("Light") then register(inst)
	elseif inst:IsA("BasePart") and (inst:GetAttribute("Shape") ~= nil or inst:GetAttribute("GlowSite") ~= nil) then
		registerSite(inst)
		if inst:GetAttribute("WindowGlow") ~= nil then registerWindows(inst) end
	end
end
local roots = {}
local function addRoot(root)
	if roots[root] then return end
	roots[root] = true
	for _, inst in ipairs(root:GetDescendants()) do consider(inst) end
	if connect(root, "DescendantAdded", consider) then Lights.connected = true end
end
local function findRoots()
	for _, child in ipairs(workspace:GetChildren()) do
		if ROOT_NAMES[child.Name] or child:GetAttribute("Minigames") == true then addRoot(child) end
	end
end
findRoots()
connect(workspace, "ChildAdded", function(child)
	if ROOT_NAMES[child.Name] or child:GetAttribute("Minigames") == true then addRoot(child) end
end)
local function poolLight(i)
	local entry = Lights.pool[i]
	if entry then return entry end
	if not Lights.poolFolder then
		Lights.poolFolder = Instance.new("Folder")
		Lights.poolFolder.Name = "IsleLightingPool"
		Lights.poolFolder.Parent = workspace
	end
	local host = Instance.new("Part")
	host.Name, host.Anchored, host.CanCollide, host.CanQuery, host.CanTouch = "Glow", true, false, false, false
	host.Transparency, host.CastShadow, host.Size = 1, false, Vector3.new(0.2, 0.2, 0.2)
	host.Parent = Lights.poolFolder
	local light = Instance.new("PointLight")
	light:SetAttribute(OWNED, true)
	light.Shadows, light.Enabled = false, false
	light.Parent = host
	entry = {host = host, light = light}
	Lights.pool[i] = entry
	return entry
end
local function sitePosition(site)
	local part = site.part
	local cf, size = part.CFrame, part.Size
	if site.kind == "lantern" then return cf.Position + Vector3.new(0, size.Y / 2 + 0.4, 0) end
	-- §40 QC L3: a building host's declared mesh box (ShapeBox / ShapeBoxOffset)
	-- is the building; a walk-in hall's host is only its floor plank, so the
	-- spill would otherwise sit at floor level.
	local box, offset = part:GetAttribute("ShapeBox"), part:GetAttribute("ShapeBoxOffset")
	if typeof(box) == "Vector3" then
		cf = cf * CFrame.new(if typeof(offset) == "Vector3" then offset else Vector3.zero)
		size = box
	end
	-- Windows / stalls: spill just in front of the face, a third of the way up.
	return cf.Position + cf.LookVector * (size.Z / 2 + 1) + Vector3.new(0, -size.Y / 6, 0)
end
local function entryAt(n)
	local e = Lights.entryPool[n]
	if not e then e = {}; Lights.entryPool[n] = e end
	Lights.entries[n] = e
	return e
end
local function dropRec(rec)
	Lights.byLight[rec.light] = nil
	for _, c in pairs(rec.conns) do pcall(function() c:Disconnect() end) end
end
function Lights.update(tierName, nightness)
	local origin = rootPosition()
	if not origin then return end
	Lights.dirty = false
	-- Drop lights / sites that left the world (in place, QC L1); read server
	-- intent from LightWanted / LightHero (QC M1), never from Enabled / Shadows.
	local entries, recs = Lights.entries, Lights.recs
	table.clear(entries); table.clear(recs)
	local n, kept = 0, 0
	local list = Lights.list
	for i = 1, #list do
		local rec = list[i]
		local l = rec.light
		if l.Parent and l:IsDescendantOf(workspace) then
			kept += 1
			list[kept] = rec
			local wanted, hero = boolAttr(l, WANTED), boolAttr(l, HERO)
			if wanted ~= nil then rec.base = wanted
			elseif l.Enabled ~= rec.enabled then rec.base, rec.enabled = l.Enabled, l.Enabled end -- legacy: adopt a server edit
			if hero ~= nil then rec.hero = hero
			elseif l.Shadows ~= rec.shadows then rec.hero, rec.shadows = l.Shadows, l.Shadows end
			if math.abs(l.Brightness - rec.bright) > 1e-3 then rec.brightness, rec.bright = l.Brightness, l.Brightness end
			local pos = rec.pos
			if not pos then
				local fixed
				pos, fixed = lightPos(l)
				if fixed then rec.pos = pos end
			end
			if pos then
				n += 1
				local e = entryAt(n)
				e.pos, e.base, e.night, e.hero, e.pooled = pos, rec.base, rec.night, rec.hero, false
				recs[n] = rec
			end
		else
			dropRec(rec)
		end
	end
	for i = kept + 1, #list do list[i] = nil end
	local sites = Lights.sites
	kept = 0
	for i = 1, #sites do
		local site = sites[i]
		if not site.dead and site.part.Parent and site.part:IsDescendantOf(workspace) then
			kept += 1
			sites[kept] = site
			local pos = site.pos
			if not pos then
				pos = sitePosition(site)
				if site.part.Anchored then site.pos = pos end
			end
			n += 1
			local e = entryAt(n)
			e.pos, e.base, e.night, e.hero, e.pooled = pos, true, false, false, true
			recs[n] = site
		elseif Lights.bySite[site.part] == site then
			Lights.bySite[site.part] = nil
		end
	end
	for i = kept + 1, #sites do sites[i] = nil end
	local modes = L.selectLights(entries, origin, tierName, nightness >= 0.5, Lights.scratch)
	local used = 0
	for i = 1, n do
		local rec = recs[i]
		local mode = modes[i]
		if rec.part then
			if mode then
				used += 1
				local entry = poolLight(used)
				local kind = L.GLOW_KINDS[rec.kind]
				entry.host.CFrame = CFrame.new(entries[i].pos)
				entry.light.Color, entry.light.Range = Color3.fromHex(kind.color), kind.range
				entry.light.Brightness = L.lightBrightness(kind.brightness, nightness)
				if not entry.light.Enabled then entry.light.Enabled = true end
				entry.site = rec
			end
		else
			local l = rec.light
			local on = mode ~= nil
			local shadows = mode == "shadow"
			local bright = L.lightBrightness(rec.brightness, nightness)
			if l.Enabled ~= on then l.Enabled = on end
			rec.enabled = on
			if l.Shadows ~= shadows then l.Shadows = shadows end
			rec.shadows = shadows
			if math.abs(l.Brightness - bright) > 1e-3 then l.Brightness = bright end
			rec.bright = l.Brightness
		end
	end
	for i = used + 1, #Lights.pool do
		local entry = Lights.pool[i]
		entry.site = nil
		if entry.light.Enabled then entry.light.Enabled = false end
	end
	Lights.lastCount = used
end
-- Every 10 s: re-check glow sites (a light may have arrived in a sibling
-- part since, QC M2) and drop cached anchored positions (QC L1).
function Lights.rescan()
	for _, site in ipairs(Lights.sites) do
		site.pos = nil
		if not site.dead and hasOwnLight(site.part) then dropSite(site) end
	end
	for _, rec in ipairs(Lights.list) do rec.pos = nil end
end

------------------------------------------------------------------------------
-- Main loop: clock + blend at 15 Hz, context at 4 Hz, lights at 2 Hz.
------------------------------------------------------------------------------
local STEP, CONTEXT_STEP, LIGHT_STEP, RESCAN_STEP = 1 / 15, 0.25, 0.5, 10
local acc, contextAcc, lightAcc, rescanAcc, clockT = 0, CONTEXT_STEP, LIGHT_STEP, 0, 0
Director.tier = readTier()
applyTier(Director.tier)
function Director.step(dt)
	dt = tonumber(dt) or 0
	if dt ~= dt or dt < 0 then dt = 0 end
	clockT += dt
	acc += dt; contextAcc += dt; lightAcc += dt; rescanAcc += dt
	if contextAcc >= CONTEXT_STEP then
		contextAcc = 0
		local tier = readTier()
		if tier ~= Director.tier then Director.tier = tier; applyTier(tier); lightAcc = LIGHT_STEP end
		if Lights.dirty then lightAcc = LIGHT_STEP end -- a LightWanted / LightHero change applies at once
		updateContext(clockT)
		Weather.read()
	end
	Weather.flashStep()
	if acc < STEP then return end
	local frame = acc
	acc = 0
	local clock = L.clockAt(now(), Data.Calendar)
	Director.clock = clock
	local sky = L.skyClockFor(Director.key or L.DEFAULT_KEY, clock) -- interiors hold a fixed sun (QC L3)
	if math.abs((Director.written.ClockTime or -1) - sky) >= 0.002 then
		Lighting.ClockTime = sky
		Director.written.ClockTime = sky
	end
	local target = L.target(Director.key or L.DEFAULT_KEY, clock, Director.tier)
	L.applyWeather(target, L.blendWeather(Weather.delta, Weather.state, L.alphaFor(frame, L.WEATHER_TAU)))
	if Director.state == nil then
		Director.state = target
	else
		Director.state = L.blend(Director.state, target, L.alphaFor(frame, L.REGION_TAU))
		if L.distance(Director.state, target) < L.SNAP_DISTANCE then Director.state = target end
	end
	applyState(Director.state)
	if lightAcc >= LIGHT_STEP then
		lightAcc = 0
		-- Night lamps and the glow pool follow the outdoor clock; interiors keep
		-- their lamps lit (their profile is night-like by design).
		local profile = L.Profiles[Director.key or L.DEFAULT_KEY]
		local nightness = if profile.interior then 1 else 1 - L.dayFactor(clock)
		Lights.update(Director.tier, nightness)
		Windows.update(Director.tier, nightness)
	end
	if rescanAcc >= RESCAN_STEP then
		rescanAcc = 0
		findRoots()
		-- No DescendantAdded (headless harness): rescan the roots instead.
		if not Lights.connected then for root in pairs(roots) do for _, inst in ipairs(root:GetDescendants()) do consider(inst) end end end
		Lights.rescan()
		sweepForeign()
	end
end
connect(RunService, "Heartbeat", Director.step)
Director.step(STEP) -- first frame: no unlit flash before the first Heartbeat
-- The chunk's value is read only by the headless suite (verify-lighting.luau).
return Director
