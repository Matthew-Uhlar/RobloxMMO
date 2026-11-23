-- Beaconry world renderer (ServerScriptService.Beaconry; docs/DEPTH-CONTRACT.md §37).
-- The Adventure script (server.server.lua) owns every Beaconry rule and keeps
-- the campfires and lit beacons in memory; it publishes them as workspace
-- attributes. This script only draws them, so nothing here grants anything:
--   BeaconryFires   "id:x:y:z:tier:until;..."  campfires (until = os.time())
--   BeaconryBeacons "id:until;..."             lit beacon pyres
-- Campfires are small Models under Workspace.AetherIsles.Campfires (a §35
-- light root): a stone ring (RockCluster mesh), two crossed logs (Log mesh,
-- tinted by the wood tier), glowing coals and a flame volume with a Fire,
-- ember and smoke emitters and one night PointLight (LightWanted = true; the
-- client director lights it after dusk inside its budget). 5 parts each, at
-- most Data.Beaconry.MAX_FIRES (40) campfires = 200 parts. A campfire in its
-- last DWINDLE seconds shrinks. Beacon pyres are static (world.server.lua);
-- here a lit pyre shows its flame (Neon), Fire and embers and sets its light's
-- LightWanted / Enabled; the prompt reads "Bask" while it burns.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local B = Data.Beaconry
local V, C = Vector3.new, Color3.fromHex

local Pyre = {fires = {}, beacons = {}, DWINDLE = 10, PARTS = 5}

-- "id:x:y:z:tier:until;..." -> {[id] = {pos, tier, untilAt}} (malformed entries skipped, capped).
function Pyre.parseFires(text)
	local out, n = {}, 0
	if type(text) ~= "string" then return out end
	for entry in string.gmatch(text, "[^;]+") do
		local id, x, y, z, tier, untilAt = string.match(entry, "^(%d+):(%-?[%d%.]+):(%-?[%d%.]+):(%-?[%d%.]+):(%d+):(%d+)$")
		if id and n < B.MAX_FIRES then
			n += 1
			out[tonumber(id)] = {pos = V(tonumber(x), tonumber(y), tonumber(z)), tier = math.clamp(tonumber(tier), 1, #B.Logs), untilAt = tonumber(untilAt)}
		end
	end
	return out
end
-- "id:until;..." -> {[beaconId] = untilAt}
function Pyre.parseBeacons(text)
	local out = {}
	if type(text) ~= "string" then return out end
	for entry in string.gmatch(text, "[^;]+") do
		local id, untilAt = string.match(entry, "^(%w+):(%d+)$")
		if id and B.Beacons[id] then out[id] = tonumber(untilAt) end
	end
	return out
end

local function folder()
	local root = workspace:FindFirstChild("AetherIsles")
	if not root then return nil end
	local f = root:FindFirstChild("Campfires")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Campfires"
		f.Parent = root
	end
	return f
end
local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = name, true, false, false, false
	p.Size, p.CFrame, p.Color, p.Material = size, cf, color, material
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function slot(p, shape, tint)
	p:SetAttribute("Shape", shape)
	p:SetAttribute("Tint", tint)
	return p
end
-- One campfire model at `pos` (ground point) for a log tier.
function Pyre.buildFire(id, entry, parent)
	local log = B.Logs[entry.tier] or B.Logs[1]
	local wood = C(log.color)
	local heat = C("FF8A3D"):Lerp(wood, 0.25)
	local m = Instance.new("Model")
	m.Name = "Campfire " .. id
	m:SetAttribute("CampfireId", id)
	m:SetAttribute("LogTier", entry.tier)
	local base = CFrame.new(entry.pos) * CFrame.Angles(0, math.rad((id * 47) % 360), 0)
	slot(part(m, "Fire ring", V(3.4, 0.6, 3.4), base * CFrame.new(0, 0.3, 0), C("6E6A66"), Enum.Material.Slate), "RockCluster", C("7A746D"))
	for i, yaw in ipairs({35, -35}) do
		local logPart = part(m, "Campfire log", V(0.7, 0.7, 2.8), base * CFrame.new(0, 0.55 + i * 0.12, 0) * CFrame.Angles(math.rad(12), math.rad(yaw), 0), wood, Enum.Material.Wood)
		slot(logPart, "Log", wood)
	end
	local coals = part(m, "Campfire coals", V(1.5, 0.25, 1.5), base * CFrame.new(0, 0.5, 0), C("FF6A2B"), Enum.Material.Neon)
	coals.Shape = Enum.PartType.Cylinder
	coals.CFrame = base * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2)
	coals.Size = V(0.25, 1.5, 1.5)
	local flame = part(m, "Campfire flame", V(1.6, 2.4, 1.6), base * CFrame.new(0, 1.8, 0), heat, Enum.Material.SmoothPlastic)
	flame.Transparency, flame.CastShadow = 1, false
	local fire = Instance.new("Fire")
	fire.Name = "Flame"
	fire.Color, fire.SecondaryColor = heat, C("FFE7A8")
	fire.Size, fire.Heat = 3 + entry.tier * 0.4, 7 + entry.tier
	fire.Parent = flame
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Rate, embers.LightEmission = 6 + entry.tier, 0.9
	embers.Lifetime, embers.Speed = NumberRange.new(0.8, 1.6), NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Size = NumberSequence.new(0.18, 0)
	embers.Color = ColorSequence.new(heat, C("FFD38A"))
	embers.Parent = flame
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Rate, smoke.LightEmission = 3, 0
	smoke.Lifetime, smoke.Speed = NumberRange.new(2.5, 4), NumberRange.new(1.5, 3)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Size = NumberSequence.new(0.8, 2.6)
	smoke.Transparency = NumberSequence.new(0.55, 1)
	smoke.Color = ColorSequence.new(C("5E5650"))
	smoke.Parent = flame
	local light = Instance.new("PointLight")
	light.Name = "Campfire light"
	light.Color, light.Brightness, light.Range, light.Shadows = heat, 1.3, 14 + entry.tier, false
	light.Enabled = false -- the §35 director lights it after dusk
	light:SetAttribute("NightLight", true)
	light:SetAttribute("LightWanted", true)
	light:SetAttribute("LightHero", false)
	light.Parent = flame
	m.Parent = parent
	return m
end
-- Last seconds: the flame dwindles.
function Pyre.dwindle(model, left)
	local flame = model:FindFirstChild("Campfire flame")
	local fire = flame and flame:FindFirstChild("Flame")
	if not fire then return end
	local tier = model:GetAttribute("LogTier") or 1
	local full = 3 + tier * 0.4
	fire.Size = if left < Pyre.DWINDLE then math.max(1, full * left / Pyre.DWINDLE) else full
end

-- Diff the published campfires against what is drawn.
function Pyre.syncFires(text, now)
	local parent = folder()
	if not parent then return end
	local want = Pyre.parseFires(text)
	for id, model in pairs(Pyre.fires) do
		if not want[id] then
			Pyre.fires[id] = nil
			model:Destroy()
		end
	end
	for id, entry in pairs(want) do
		local model = Pyre.fires[id]
		if not model then
			model = Pyre.buildFire(id, entry, parent)
			Pyre.fires[id] = model
		end
		Pyre.dwindle(model, entry.untilAt - (now or os.time()))
	end
end

-- Beacon pyres built by world.server.lua (models with BeaconId under Workspace.Islands).
function Pyre.scanBeacons()
	local islands = workspace:FindFirstChild("Islands")
	if not islands then return end
	for _, obj in ipairs(islands:GetDescendants()) do
		local id = obj:IsA("Model") and obj:GetAttribute("BeaconId")
		if id and B.Beacons[id] and not Pyre.beacons[id] then
			local flame
			for _, d in ipairs(obj:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("BeaconFlame") then flame = d end end
			local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
			if flame then Pyre.beacons[id] = {model = obj, flame = flame, prompt = prompt, lit = nil} end
		end
	end
end
function Pyre.setBeacon(entry, lit)
	if entry.lit == lit then return end
	entry.lit = lit
	local flame = entry.flame
	flame.Transparency = if lit then 0.35 else 1
	flame.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, d in ipairs(flame:GetDescendants()) do
		if d:IsA("Fire") or d:IsA("ParticleEmitter") then d.Enabled = lit
		elseif d:IsA("Light") then
			d:SetAttribute("LightWanted", lit) -- §35: server intent first, then Enabled
			d.Enabled = lit
		end
	end
	if entry.prompt then entry.prompt.ActionText = if lit then "Bask" else "Light" end
end
function Pyre.syncBeacons(text, now)
	if next(Pyre.beacons) == nil then Pyre.scanBeacons() end
	local lit = Pyre.parseBeacons(text)
	now = now or os.time()
	for id, entry in pairs(Pyre.beacons) do
		if entry.model.Parent then Pyre.setBeacon(entry, (lit[id] or 0) > now) else Pyre.beacons[id] = nil end
	end
end

function Pyre.sync(now)
	Pyre.syncFires(workspace:GetAttribute("BeaconryFires"), now)
	Pyre.syncBeacons(workspace:GetAttribute("BeaconryBeacons"), now)
end

pcall(function()
	workspace:GetAttributeChangedSignal("BeaconryFires"):Connect(function() Pyre.syncFires(workspace:GetAttribute("BeaconryFires")) end)
	workspace:GetAttributeChangedSignal("BeaconryBeacons"):Connect(function() Pyre.syncBeacons(workspace:GetAttribute("BeaconryBeacons")) end)
end)
task.spawn(function()
	-- Dwindling flames and a safety resync (a missed signal heals within a second).
	while task.wait(1) do pcall(Pyre.sync) end
end)
return Pyre
