-- IsleTerrain (client): the island environment layer (docs/DEPTH-CONTRACT.md §54).
-- Rules and plans live in shared/TerrainArt.lua (ReplicatedStorage.AetherTerrain);
-- meshes come from the MeshForge (forge.client.lua) through
-- ReplicatedStorage.MeshForgeLocal: "dress" / "dressRelease" for the instanced
-- dressing (grass, flowers, stones, shrubs, tree species at a near and a far LOD,
-- hero trees, hanging roots, vine curtains, crystal veins, satellite rocks) and
-- "ground" / "groundRelease" for each near island's forged ground top and cliff
-- wall (flat arrays, M6).
--   * Everything is local and decorative: clones live under Workspace.IsleDressing,
--     never under an island, with CanCollide / CanQuery / CanTouch false. The
--     server's Meadow (and the foundation behind the forged wall) stay the
--     colliders; they are hidden only locally while their forged replacement
--     shows (re-asserted every cycle, H4) and restored when it goes.
--   * Budgets: shared/TerrainArt.lua T.Budgets per graphics tier (player
--     attribute IsleSettingGraphics, phones use Lite); the forge adds pool ceilings.
--   * H1: far-seen classes are placed first; a refused shape backs off on its own
--     (2 s doubling to 64 s) while the rest keep placing.
--   * H2: a refused ground / wall backs off per island; a failed one is never
--     retried for that island and cell; backoffs clear on a tier change.
--   * H3: parts added to an island block the dressing around them after the
--     island has been quiet for QUIET seconds; removals re-plan the island; the
--     first plan waits for a quiet model too. L2: signals drop with the island.
--   * M3: a re-seated swaying clone publishes its new rest frame (SwayRest).
--   * M6: work runs in slices of SLICE_SECONDS per frame (Heartbeat), a full
--     cycle at most every STEP_SECONDS.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local T = require(ReplicatedStorage:WaitForChild("AetherTerrain"))
local mobile = false
pcall(function() mobile = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true end)

local Terrain = {islands = {}, placed = {}, grounds = {}, backoff = {}, stats = {placed = 0, grounds = 0, refused = 0, plans = 0, cycles = 0}, tierKey = nil}
local STEP_SECONDS = 1
local SLICE_SECONDS = 0.002
local QUIET = 1
local PLACE_PER_STEP = 160
local BACKOFF_FIRST, BACKOFF_MAX = 2, 64
local ROOT_NAME = "IsleDressing"
Terrain.QUIET, Terrain.SLICE_SECONDS = QUIET, SLICE_SECONDS
-- Clock (tests replace it).
local now = os.clock
function Terrain.setClock(fn) now = fn end

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
local function invoke(method, arg)
	local f = ReplicatedStorage:FindFirstChild("MeshForgeLocal")
	if not f then return nil end
	local ok, a, b, c, d = pcall(f.Invoke, f, method, arg)
	if not ok then return nil end
	return a, b, c, d
end

-- Slicing (M6) -------------------------------------------------------------
local sliceStart = 0
local worker -- the cycle coroutine (only it ever yields)
local function pause()
	if worker and coroutine.running() == worker and now() - sliceStart > SLICE_SECONDS then coroutine.yield() end
end
function Terrain.setWorker(co) worker = co end
Terrain.pause = pause

-- Islands ------------------------------------------------------------------
local function considerIsland(model)
	if Terrain.islands[model] or not model:IsA("Model") then return end
	if typeof(model:GetAttribute("IslandCenter")) ~= "Vector3" then return end -- L5
	local meadow = model:FindFirstChild("Meadow")
	if not meadow or not meadow:IsA("BasePart") then return end
	local state = {model = model, meadow = meadow, desc = nil, needPlan = true, changedAt = now() - QUIET, added = {}, conns = {}}
	Terrain.islands[model] = state
	local function changed(replan) state.changedAt = now(); if replan then state.needPlan = true end end
	local function connect(signal, fn) local ok, c = pcall(signal.Connect, signal, fn); if ok then table.insert(state.conns, c) end end
	pcall(function()
		connect(meadow:GetPropertyChangedSignal("Size"), function() changed(true) end)
		connect(model:GetAttributeChangedSignal("BuildRadius"), function() changed(true) end)
		connect(model.DescendantAdded, function(inst)
			if inst:IsA("BasePart") and inst ~= meadow then table.insert(state.added, inst); changed(false) end
		end)
		connect(model.DescendantRemoving, function(inst)
			if inst:IsA("BasePart") and state.desc and not state.desc.self[inst] then changed(true) end
		end)
	end)
end
local function dropIsland(model, state)
	for _, c in ipairs(state.conns) do pcall(c.Disconnect, c) end -- L2
	table.clear(state.conns)
	for item, rec in pairs(Terrain.placed) do if item.island == state then Terrain.release(item) end end
	Terrain.releaseGround(state)
	Terrain.islands[model] = nil
end
local function scanIslands()
	for _, name in ipairs({"Islands", "AetherIsles"}) do
		local container = workspace:FindFirstChild(name)
		if container then for _, child in ipairs(container:GetChildren()) do considerIsland(child) end end
	end
	for model, state in pairs(Terrain.islands) do
		if not model.Parent then dropIsland(model, state) end
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

-- Placement ----------------------------------------------------------------
function Terrain.release(item)
	local rec = Terrain.placed[item]
	if not rec then return end
	Terrain.placed[item] = nil
	Terrain.stats.placed -= 1
	if rec.link then pcall(rec.link.Destroy, rec.link) end
	invoke("dressRelease", rec.token)
end
local function frameFor(item, centre, mode)
	local s = item.scale
	local base
	if item.class == "cliff" then
		local x, y, z = T.cliffPosition(item, mode == "hull")
		local pos = Vector3.new(x, y, z)
		base = CFrame.lookAt(pos, pos + Vector3.new(item.out[1], 0, item.out[2]))
	else
		local y = if mode == "ground" then item.y else item.flatY
		base = CFrame.new(item.x, y, item.z) * CFrame.Angles(0, item.yaw, 0)
	end
	return base * CFrame.new(centre * s)
end
Terrain.frameFor = frameFor
-- Seat mode: clutter / trees follow the forged ground top, cliff pieces the forged wall.
local function modeOf(item)
	local g = Terrain.grounds[item.island]
	if item.class == "cliff" then return if g and g.hullPart then "hull" else "flat" end
	if item.class == "satellite" then return "flat" end
	return if g and g.groundPart then "ground" else "flat"
end
local function backedOff(shape)
	local b = Terrain.backoff[shape]
	return b ~= nil and now() < b.at
end
local function refuse(shape)
	local b = Terrain.backoff[shape]
	local delay = if b then math.min(BACKOFF_MAX, b.delay * 2) else BACKOFF_FIRST
	Terrain.backoff[shape] = {at = now() + delay, delay = delay}
	Terrain.stats.refused += 1
end
Terrain.refuse = refuse
local function place(entry)
	local item, shape = entry.item, entry.shape
	if backedOff(shape) then return false end
	local clone, token, extent, centre = invoke("dress", {shape = shape, tint = Color3.fromHex(item.tint)})
	if not clone then refuse(shape); return false end -- H1: carry on with the next entry
	Terrain.backoff[shape] = nil
	local mode = modeOf(item)
	clone.Size = extent * item.scale
	clone.CFrame = frameFor(item, centre, mode)
	clone.CanCollide, clone.CanQuery, clone.CanTouch = false, false, false
	clone.CastShadow = item.class ~= "clutter"
	clone:SetAttribute("Dressing", item.kind)
	clone.Parent = folder()
	local rec = {token = token, clone = clone, centre = centre, mode = mode, shape = shape}
	if T.SWAYS[shape] then
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

-- Ground tops and cliff walls ---------------------------------------------------
local function hideParts(state)
	local list = {}
	local foundation = state.model:FindFirstChild("Floating foundation")
	local shell = state.model:FindFirstChild("Island shell")
	if not foundation and shell then foundation = shell:FindFirstChild("Floating foundation") end
	if foundation then
		table.insert(list, foundation)
		local link = foundation:FindFirstChild("ShapeMesh")
		if link and link.Value then table.insert(list, link.Value) end
	end
	if shell then for _, p in ipairs(shell:GetChildren()) do if p:IsA("BasePart") and p.Name == "Fractured cliff" then table.insert(list, p) end end end
	return list
end
local function setHidden(part, value) pcall(function() part.LocalTransparencyModifier = value end) end
Terrain.setHidden = setHidden
function Terrain.releaseGround(state)
	local g = Terrain.grounds[state]
	if not g then return end
	Terrain.grounds[state] = nil
	Terrain.stats.grounds -= 1
	setHidden(state.meadow, 0)
	if g.hullPart then
		for _, p in ipairs(hideParts(state)) do
			-- The forge keeps its own primitive hidden under its mesh.
			if not (p.Name == "Floating foundation" and p:GetAttribute("ShapeDone")) then setHidden(p, 0) end
		end
	end
	if g.groundToken then invoke("groundRelease", g.groundToken) end
	if g.hullToken then invoke("groundRelease", g.hullToken) end
end
local function groundBlocked(state, key)
	local b = state.groundBackoff
	if not b then return false end
	if b.failed[key] then return true end
	return now() < (b.at[key] or 0)
end
local function groundRefused(state, key, reason)
	local b = state.groundBackoff
	if not b then b = {at = {}, delay = {}, failed = {}}; state.groundBackoff = b end
	if reason == "failed" then b.failed[key] = true; return end
	local delay = math.min(BACKOFF_MAX, (b.delay[key] or BACKOFF_FIRST / 2) * 2)
	b.delay[key], b.at[key] = delay, now() + delay
end
Terrain.groundRefused = groundRefused
local function buildGround(state, b)
	local g = Terrain.grounds[state] or {cell = b.cell, hullKey = b.hullSeg * 1000 + b.hullLevels}
	local c = state.desc.center
	local gkey, hkey = "ground" .. b.cell, "hull" .. g.hullKey
	if not g.groundPart and not groundBlocked(state, gkey) then
		local spec = T.ground(state.desc, b.cell, pause)
		local part, token, centre = invoke("ground", spec)
		if part then
			part.CFrame = CFrame.new(c[1] + centre.X, c[2] + centre.Y, c[3] + centre.Z)
			part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
			part:SetAttribute("Dressing", "ground")
			part.Parent = folder()
			g.groundPart, g.groundToken = part, token
		else
			groundRefused(state, gkey, if token == "failed" then "failed" else "budget")
		end
	end
	if not g.hullPart and not groundBlocked(state, hkey) then
		local spec = T.hull(state.desc, b.hullSeg, b.hullLevels, pause)
		local part, token, centre = invoke("ground", spec)
		if part then
			part.CFrame = CFrame.new(c[1] + centre.X, c[2] + centre.Y, c[3] + centre.Z)
			part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
			part:SetAttribute("Dressing", "hull")
			part.Parent = folder()
			g.hullPart, g.hullToken = part, token
		else
			groundRefused(state, hkey, if token == "failed" then "failed" else "budget")
		end
	end
	if (g.groundPart or g.hullPart) and not Terrain.grounds[state] then
		Terrain.grounds[state] = g
		Terrain.stats.grounds += 1
	end
end

-- Plans (H3) ----------------------------------------------------------------
local function plan(state)
	local ok, desc = pcall(T.collect, state.model, Terrain.protected)
	if not ok or not desc then return end
	for item in pairs(Terrain.placed) do if item.island == state then Terrain.release(item) end end
	Terrain.releaseGround(state)
	state.desc = desc
	local okPlan, items = pcall(T.plan, desc)
	state.items = if okPlan then items else {}
	for _, item in ipairs(state.items) do item.island = state end
	state.needPlan, state.added = false, {}
	Terrain.stats.plans += 1
end
-- Parts added since the plan: block the dressing around them (no full re-plan).
local function absorb(state)
	local desc = state.desc
	for _, part in ipairs(state.added) do
		if part.Parent then
			local o = T.addObstacle(desc, part)
			if o then
				local kept = {}
				for _, item in ipairs(state.items) do
					local near = math.abs(item.x - o.cx) < 30 and math.abs(item.z - o.cz) < 30
					local foot = if item.class == "tree" then T.FOOT.foliage elseif item.class == "rock" then T.FOOT.rock else T.FOOT.clutter
					if near and (item.class == "clutter" or item.class == "rock" or item.class == "tree") and not T.free(desc, item.x, item.z, foot, item.class == "tree") then
						Terrain.release(item)
					else
						table.insert(kept, item)
					end
				end
				state.items = kept
			end
		end
	end
	state.added = {}
	desc._ground, desc._hull = nil, nil -- heights follow the new footprint next build
end

-- One cycle ------------------------------------------------------------------
local function resetAll()
	for item in pairs(Terrain.placed) do Terrain.release(item) end
	for state in pairs(Terrain.grounds) do Terrain.releaseGround(state) end
	for _, state in pairs(Terrain.islands) do state.groundBackoff = nil end
	table.clear(Terrain.backoff)
end
Terrain.resetAll = resetAll
function Terrain.step()
	local f = focus()
	if not f then return end
	Terrain.stats.cycles += 1
	local key = tierKey()
	if key ~= Terrain.tierKey then
		resetAll() -- H2: blocked grounds and backed-off shapes clear on a tier change
		Terrain.tierKey = key
	end
	local b = T.Budgets[key]
	local reach = math.max(b.satelliteRadius, b.farRadius * 1.8, b.groundRadius)
	local candidates = {}
	for model, state in pairs(Terrain.islands) do
		if not model.Parent or not state.meadow.Parent then
			dropIsland(model, state)
		else
			local c = model:GetAttribute("IslandCenter")
			if typeof(c) == "Vector3" then
				local r = state.desc and state.desc.radius or state.meadow.Size.Y / 2
				local d = math.max(0, Vector3.new(f.X - c.X, 0, f.Z - c.Z).Magnitude - r)
				if d <= reach then table.insert(candidates, {state, d}) end
			end
		end
	end
	table.sort(candidates, function(a, c) return a[2] < c[2] end)
	-- Plans: one island per cycle, only once its model has been quiet (H3).
	for _, entry in ipairs(candidates) do
		local state = entry[1]
		if now() - state.changedAt >= QUIET then
			if state.needPlan or not state.desc then plan(state); pause(); break
			elseif #state.added > 0 then absorb(state); pause() end
		end
	end
	-- Ground tops and walls: the nearest islands within range.
	local want, n = {}, 0
	for _, entry in ipairs(candidates) do
		local state = entry[1]
		if state.desc and n < b.grounds and entry[2] <= b.groundRadius then n += 1; want[state] = true end
	end
	for state, g in pairs(Terrain.grounds) do
		local lost = (g.groundPart and not g.groundPart.Parent) or (g.hullPart and not g.hullPart.Parent)
		if lost then
			-- H4: a ground / wall part that vanished releases the record and backs off.
			Terrain.releaseGround(state)
			groundRefused(state, "ground" .. g.cell, "budget")
		elseif not want[state] or g.cell ~= b.cell then
			Terrain.releaseGround(state)
		end
	end
	for state in pairs(want) do
		buildGround(state, b)
		pause()
		local g = Terrain.grounds[state]
		if g then
			-- H4: re-assert the local hides every cycle (the forge or a respawn may undo them).
			if g.groundPart then setHidden(state.meadow, 1) end
			if g.hullPart then for _, p in ipairs(hideParts(state)) do setHidden(p, 1) end end
		end
	end
	-- Dressing: the tier's visible set across the islands in reach.
	local all = {}
	for _, entry in ipairs(candidates) do
		for _, item in ipairs(entry[1].items or {}) do table.insert(all, item) end
	end
	local visible = T.visible(all, key, {f.X, f.Y, f.Z}, false)
	local want2 = {}
	for _, e in ipairs(visible) do want2[e.item] = e.shape end
	for item, rec in pairs(Terrain.placed) do
		local shape = want2[item]
		if not shape or shape ~= rec.shape or not rec.clone.Parent then
			Terrain.release(item)
		else
			local mode = modeOf(item)
			if mode ~= rec.mode then
				rec.mode = mode
				local cf = frameFor(item, rec.centre, mode)
				rec.clone.CFrame = cf
				rec.clone:SetAttribute("SwayRest", cf) -- M3: the sway layer re-arms on the new rest frame
			end
		end
	end
	pause()
	local budget = PLACE_PER_STEP
	for _, e in ipairs(visible) do
		if budget <= 0 then break end
		if not Terrain.placed[e.item] then
			budget -= 1
			place(e)
			pause()
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
-- The worker: a cycle (scan, plans, grounds, placement) in 2 ms slices per frame.
local lastCycle, scanAt = -math.huge, 0
local connection = RunService.Heartbeat:Connect(function()
	sliceStart = now()
	if not worker then
		if sliceStart - lastCycle < STEP_SECONDS then return end
		lastCycle = sliceStart
		worker = coroutine.create(function()
			if now() >= scanAt then scanIslands(); scanAt = now() + 5 end
			Terrain.step()
		end)
	end
	local ok, problem = coroutine.resume(worker)
	if not ok then warn("[IsleTerrain] " .. tostring(problem)) end
	if coroutine.status(worker) == "dead" then worker = nil end
end)
script.Destroying:Once(function()
	connection:Disconnect()
	resetAll()
end)
