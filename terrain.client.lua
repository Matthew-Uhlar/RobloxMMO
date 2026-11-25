-- IsleTerrain (client): the island environment layer (docs/DEPTH-CONTRACT.md §54).
-- Rules and plans live in shared/TerrainArt.lua (ReplicatedStorage.AetherTerrain);
-- meshes come from the MeshForge (forge.client.lua) through
-- ReplicatedStorage.MeshForgeLocal: "dress" / "dressRelease" for the instanced
-- dressing (grass, flowers, pebbles, stones, shrubs, ferns, reeds, tree species,
-- hero silhouette trees, hanging roots, vine curtains, crystal veins, satellite
-- rocks) and "ground" / "groundRelease" for each island's forged ground top.
--   * Everything is local and decorative: clones live under Workspace.IsleDressing,
--     never under an island, with CanCollide / CanQuery / CanTouch false. The
--     server's Meadow stays the collider; it is hidden only locally
--     (LocalTransparencyModifier) while its forged ground top is shown, and is
--     restored when the ground is released (distance, tier change, failure).
--   * Budgets: shared/TerrainArt.lua T.Budgets per graphics tier (player attribute
--     IsleSettingGraphics, phones use Lite): per-class caps nearest first,
--     per-class radii (far LOD), density share, ground count / range / cell size;
--     the forge adds hard pool ceilings on top.
--   * Sway (§50): swaying shapes get a ShapeMesh link (ObjectValue) in
--     IsleDressing.Sway; ambience.client.lua scans that root and sways the
--     clone (the link has no host part: nothing else moves it).
--   * Plans are computed lazily (one island per step) and recomputed when the
--     meadow is resized (home expansion) or the build radius changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local T = require(ReplicatedStorage:WaitForChild("AetherTerrain"))
local mobile = false
pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)

local Terrain = {islands = {}, placed = {}, grounds = {}, stats = {placed = 0, grounds = 0, refused = 0, plans = 0}, tierKey = nil}
local STEP_SECONDS = 1
local PLACE_PER_STEP = 160 -- new clones per step (spreads the first fill over a few seconds)
local ROOT_NAME = "IsleDressing"

local root, swayRoot
local function folder()
	if root and root.Parent then return root end
	root = Instance.new("Folder")
	root.Name = ROOT_NAME
	swayRoot = Instance.new("Folder")
	swayRoot.Name = "Sway"
	swayRoot.Parent = root
	root.Parent = workspace
	return root
end
local forgeApi
local function api()
	if forgeApi and forgeApi.Parent then return forgeApi end
	forgeApi = ReplicatedStorage:FindFirstChild("MeshForgeLocal")
	return forgeApi
end
local function invoke(method, arg)
	local f = api()
	if not f then return nil end
	local ok, a, b, c, d = pcall(f.Invoke, f, method, arg)
	if not ok then return nil end
	return a, b, c, d
end

-- Islands --------------------------------------------------------------------
local function considerIsland(model)
	if Terrain.islands[model] or not model:IsA("Model") then return end
	if typeof(model:GetAttribute("IslandCenter")) ~= "Vector3" then return end
	local meadow = model:FindFirstChild("Meadow")
	if not meadow or not meadow:IsA("BasePart") then return end
	local state = {model = model, meadow = meadow, desc = nil, dirty = true}
	Terrain.islands[model] = state
	local function invalidate() state.dirty = true end
	pcall(function()
		meadow:GetPropertyChangedSignal("Size"):Connect(invalidate)
		model:GetAttributeChangedSignal("BuildRadius"):Connect(invalidate)
	end)
end
local function scanIslands()
	for _, name in ipairs({"Islands", "AetherIsles"}) do
		local container = workspace:FindFirstChild(name)
		if container then for _, child in ipairs(container:GetChildren()) do considerIsland(child) end end
	end
	for model in pairs(Terrain.islands) do
		if not model.Parent then Terrain.islands[model] = nil end
	end
end
Terrain.scanIslands = scanIslands

local function tierKey()
	local player = Players.LocalPlayer
	local tier = player and player:GetAttribute("IsleSettingGraphics")
	return T.budgetKey(if type(tier) == "string" then tier else nil, mobile)
end
local function focus()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.CFrame.Position end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

-- Placement ------------------------------------------------------------------
local function release(item)
	local rec = Terrain.placed[item]
	if not rec then return end
	Terrain.placed[item] = nil
	Terrain.stats.placed -= 1
	if rec.link then pcall(rec.link.Destroy, rec.link) end
	invoke("dressRelease", rec.token)
end
local function frameFor(item, centre, grounded)
	local s = item.scale
	local y = if grounded then item.y else (item.flatY or item.y)
	local base
	if item.kind == "cliff" then
		local pos = Vector3.new(item.x, item.y, item.z)
		base = CFrame.lookAt(pos, pos + Vector3.new(item.out[1], 0, item.out[2]))
	else
		base = CFrame.new(item.x, y, item.z) * CFrame.Angles(0, item.yaw, 0)
	end
	return base * CFrame.new(centre * s)
end
local function place(item, grounded)
	local clone, token, extent, centre = invoke("dress", {shape = item.shape, tint = Color3.fromHex(item.tint)})
	if not clone then Terrain.stats.refused += 1; return false end
	clone.Size = extent * item.scale
	clone.CFrame = frameFor(item, centre, grounded)
	clone.CanCollide, clone.CanQuery, clone.CanTouch, clone.CastShadow = false, false, false, item.class ~= "clutter"
	clone:SetAttribute("Dressing", item.kind)
	clone.Parent = folder()
	local rec = {token = token, clone = clone, centre = centre, grounded = grounded}
	if item.sway then
		local link = Instance.new("ObjectValue")
		link.Name = "ShapeMesh"
		link.Value = clone
		link.Parent = swayRoot
		rec.link = link
	end
	Terrain.placed[item] = rec
	Terrain.stats.placed += 1
	return true
end

-- Ground tops ----------------------------------------------------------------
local function releaseGround(state)
	local g = Terrain.grounds[state]
	if not g then return end
	Terrain.grounds[state] = nil
	Terrain.stats.grounds -= 1
	pcall(function() state.meadow.LocalTransparencyModifier = 0 end)
	invoke("groundRelease", g.token)
end
local function buildGround(state, b)
	local spec = T.ground(state.desc, b.cell)
	local part, token, centre = invoke("ground", spec)
	if not part then Terrain.stats.refused += 1; return false end
	local c = state.desc.center
	part.CFrame = CFrame.new(c[1] + centre.X, c[2] + centre.Y, c[3] + centre.Z)
	part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	part:SetAttribute("Dressing", "ground")
	part.Parent = folder()
	Terrain.grounds[state] = {token = token, part = part, cell = b.cell}
	Terrain.stats.grounds += 1
	pcall(function() state.meadow.LocalTransparencyModifier = 1 end)
	return true
end

-- Step -----------------------------------------------------------------------
local function rimDistance(state, f)
	local c = state.model:GetAttribute("IslandCenter")
	local r = state.desc and state.desc.radius or (state.meadow.Size.Y / 2)
	return math.max(0, Vector3.new(f.X - c.X, 0, f.Z - c.Z).Magnitude - r), c
end
local function resetAll()
	for item in pairs(Terrain.placed) do release(item) end
	for state in pairs(Terrain.grounds) do releaseGround(state) end
end
Terrain.resetAll = resetAll
function Terrain.step()
	local f = focus()
	if not f then return end
	local key = tierKey()
	if key ~= Terrain.tierKey then
		resetAll()
		Terrain.tierKey = key
	end
	local b = T.Budgets[key]
	-- Plans: one stale island within reach per step (nearest first).
	local candidates = {}
	for _, state in pairs(Terrain.islands) do
		if state.meadow.Parent then
			local d = rimDistance(state, f)
			if d <= b.satelliteRadius then table.insert(candidates, {state, d}) end
		end
	end
	table.sort(candidates, function(a, c) return a[2] < c[2] end)
	for _, entry in ipairs(candidates) do
		local state = entry[1]
		if state.dirty then
			state.dirty = false
			local ok, desc = pcall(T.collect, state.model, Terrain.protected)
			if ok and desc then
				-- A changed island drops its old dressing first.
				if state.desc then
					for item in pairs(Terrain.placed) do if item.island == state then release(item) end end
					releaseGround(state)
				end
				state.desc = desc
				local okPlan, items = pcall(T.plan, desc)
				state.items = if okPlan then items else {}
				for _, item in ipairs(state.items) do
					item.island = state
					item.flatY = desc.top - 0.04
					if item.kind == "cliff" or item.kind == "satellite" then item.flatY = item.y end
				end
				Terrain.stats.plans += 1
			end
			break
		end
	end
	-- Ground tops: the nearest islands within range.
	local wantGround = {}
	local n = 0
	for _, entry in ipairs(candidates) do
		local state = entry[1]
		if state.desc and n < b.grounds and entry[2] <= b.groundRadius then
			n += 1
			wantGround[state] = true
		end
	end
	for state, g in pairs(Terrain.grounds) do
		if not wantGround[state] or g.cell ~= b.cell or not state.meadow.Parent then releaseGround(state) end
	end
	for state in pairs(wantGround) do
		if not Terrain.grounds[state] then buildGround(state, b) end
	end
	-- Dressing: the tier's visible set across the islands in reach.
	local all = {}
	for _, entry in ipairs(candidates) do
		for _, item in ipairs(entry[1].items or {}) do table.insert(all, item) end
	end
	local visible = T.visible(all, key, {f.X, f.Y, f.Z}, false)
	local want = {}
	for _, item in ipairs(visible) do want[item] = true end
	for item, rec in pairs(Terrain.placed) do
		local grounded = Terrain.grounds[item.island] ~= nil
		if not want[item] or not rec.clone.Parent then release(item)
		elseif rec.grounded ~= grounded and item.class ~= "cliff" and item.class ~= "satellite" then
			rec.grounded = grounded
			rec.clone.CFrame = frameFor(item, rec.centre, grounded)
		end
	end
	local budget = PLACE_PER_STEP
	for _, item in ipairs(visible) do
		if budget <= 0 then break end
		if not Terrain.placed[item] then
			budget -= 1
			if not place(item, Terrain.grounds[item.island] ~= nil) then break end
		end
	end
end
Terrain.T = T
Terrain.mobile = function() return mobile end

-- Home islands keep their protected circles out of the dressing too.
pcall(function()
	local Data = require(ReplicatedStorage:WaitForChild("AetherData", 10))
	Terrain.protected = Data and Data.Island and Data.Island.ProtectedCircles
end)
scanIslands()
if IsleTerrainTest then
	IsleTerrainTest.terrain = Terrain
	return Terrain
end
task.spawn(function()
	local scanAt = 0
	while true do
		if os.clock() >= scanAt then scanIslands(); scanAt = os.clock() + 5 end
		local ok, problem = pcall(Terrain.step)
		if not ok then warn("[IsleTerrain] " .. tostring(problem)) end
		task.wait(STEP_SECONDS)
	end
end)
script.Destroying:Once(resetAll)
