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
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local L = require(ReplicatedStorage:WaitForChild("AetherLighting"))
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local player = Players.LocalPlayer

local Director = {key = nil, pendingKey = nil, pendingSince = 0, state = nil, written = {}, tier = nil, clock = 12}
local OWNED = "AetherLightingDirector" -- attribute on the instances this script created

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
			child:Destroy()
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
		task.defer(function() if child.Parent == Lighting then child:Destroy() end end)
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
local function applyState(state)
	for _, f in ipairs(L.FIELDS) do write(f.key, state[f.key]) end
end
local function applyTier(tierName)
	local tier = L.Tiers[tierName]
	Lighting.GlobalShadows = tier.globalShadows
	FX.bloom.Enabled, FX.rays.Enabled, FX.grade.Enabled = tier.bloom, tier.rays, tier.grade
end

------------------------------------------------------------------------------
-- Context (which profile) with a hold against flicker on bridges.
------------------------------------------------------------------------------
local HOLD = 0.6 -- seconds a new outdoor context must persist before it blends in
local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then return root.CFrame.Position end
	local ok, pos = pcall(function() return workspace.CurrentCamera.Focus.Position end)
	return if ok then pos else nil
end
local function contextNow()
	return L.context({
		LairBoss = player:GetAttribute("LairBoss"), DungeonInRun = player:GetAttribute("DungeonInRun"),
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
local ROOT_NAMES = {AetherIsles = true, Islands = true, Townsfolk = true, LairInstances = true, ["The Hollow Observatory"] = true}
pcall(function() ROOT_NAMES[Data.Minigames.ISLAND] = true end)
local Lights = {list = {}, byLight = {}, sites = {}, bySite = {}, pool = {}, poolFolder = nil, connected = false}
local function lightPos(l)
	local host = l.Parent
	if host and host:IsA("Attachment") and host.Parent and host.Parent:IsA("BasePart") then return (host.Parent.CFrame * host.CFrame).Position end
	if host and host:IsA("BasePart") then return host.CFrame.Position end
	return nil
end
local function register(l)
	if Lights.byLight[l] or l:GetAttribute(OWNED) then return end
	local rec = {light = l, night = l:GetAttribute("NightLight") == true, base = l.Enabled, brightness = l.Brightness,
		hero = l.Shadows == true, enabled = l.Enabled, bright = l.Brightness, shadows = l.Shadows}
	Lights.byLight[l] = rec
	table.insert(Lights.list, rec)
end
local function hasOwnLight(part)
	if part:FindFirstChildWhichIsA("Light", true) then return true end
	local model = part.Parent
	if model and model:IsA("Model") and #model:GetChildren() <= 12 and model:FindFirstChildWhichIsA("Light", true) then return true end
	return false
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
local function consider(inst)
	if inst:IsA("Light") then register(inst)
	elseif inst:IsA("BasePart") and (inst:GetAttribute("Shape") ~= nil or inst:GetAttribute("GlowSite") ~= nil) then registerSite(inst) end
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
	-- Windows / stalls: spill just in front of the face, a third of the way up.
	return cf.Position + cf.LookVector * (size.Z / 2 + 1) + Vector3.new(0, -size.Y / 6, 0)
end
function Lights.update(tierName, nightness)
	local origin = rootPosition()
	if not origin then return end
	-- Drop lights / sites that left the world; adopt server changes (a value
	-- that differs from what this script last wrote came from the server).
	local entries, recs = {}, {}
	local kept = {}
	for _, rec in ipairs(Lights.list) do
		local l = rec.light
		if l.Parent and l:IsDescendantOf(workspace) then
			table.insert(kept, rec)
			if l.Enabled ~= rec.enabled then rec.base, rec.enabled = l.Enabled, l.Enabled end
			if math.abs(l.Brightness - rec.bright) > 1e-3 then rec.brightness, rec.bright = l.Brightness, l.Brightness end
			if l.Shadows ~= rec.shadows then rec.hero, rec.shadows = l.Shadows, l.Shadows end
			local pos = lightPos(l)
			if pos then
				table.insert(entries, {pos = pos, base = rec.base, night = rec.night, hero = rec.hero})
				table.insert(recs, rec)
			end
		else
			Lights.byLight[l] = nil
		end
	end
	Lights.list = kept
	local keptSites = {}
	for _, site in ipairs(Lights.sites) do
		if site.part.Parent and site.part:IsDescendantOf(workspace) then
			table.insert(keptSites, site)
			table.insert(entries, {pos = sitePosition(site), pooled = true})
			table.insert(recs, site)
		else
			Lights.bySite[site.part] = nil
		end
	end
	Lights.sites = keptSites
	local modes = L.selectLights(entries, origin, tierName, nightness >= 0.5)
	local used = 0
	for i, rec in ipairs(recs) do
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
		if Lights.pool[i].light.Enabled then Lights.pool[i].light.Enabled = false end
	end
	Lights.lastCount = used
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
		updateContext(clockT)
	end
	if acc < STEP then return end
	local frame = acc
	acc = 0
	local clock = L.clockAt(now(), Data.Calendar)
	Director.clock = clock
	local sky = L.skyClock(clock)
	if math.abs((Director.written.ClockTime or -1) - sky) >= 0.002 then
		Lighting.ClockTime = sky
		Director.written.ClockTime = sky
	end
	local target = L.target(Director.key or L.DEFAULT_KEY, clock, Director.tier)
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
	end
	if rescanAcc >= RESCAN_STEP then
		rescanAcc = 0
		findRoots()
		-- No DescendantAdded (headless harness): rescan the roots instead.
		if not Lights.connected then for root in pairs(roots) do for _, inst in ipairs(root:GetDescendants()) do consider(inst) end end end
		sweepForeign()
	end
end
connect(RunService, "Heartbeat", Director.step)
Director.step(STEP) -- first frame: no unlit flash before the first Heartbeat
-- The chunk's value is read only by the headless suite (verify-lighting.luau).
return Director
