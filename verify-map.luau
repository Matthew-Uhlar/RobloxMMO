-- Map Art (§32): the Sky Chart's 3D miniature archipelago and the minimap's
-- island plates (shared/MapArt.lua), run against the REAL world: world.server.lua
-- builds Workspace.Islands with real Roblox datatypes (as verify-world.luau does),
-- then the miniature is built from it, and hud.client.lua runs through the UI
-- harness with that world. ViewportFrame rendering itself needs Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local checks = 0
local function check(condition, label)
	assert(condition, label)
	checks += 1
end

-- The world (tools/world-harness.luau: same doubles as verify-world.luau, a
-- home for player 1 and a crew haven for CoopId "crew-1").
local WH = require("./tools/world-harness")
local built = WH.build()
local world, Data = built.world, built.Data
local islandsFolder, archipelago = built.islands, built.archipelago
check(islandsFolder and archipelago and archipelago:FindFirstChild("WayfarersRest_1") and archipelago:FindFirstChild("CrewHaven_test"), "world, islands, home and crew haven built")

------------------------------------------------------------------------------
-- Pure module loads (real instances).
------------------------------------------------------------------------------
local pureEnv = { Instance = roblox.Instance, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2,
	Vector3 = Vector3, CFrame = CFrame, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint }
local T = luau.load(fs.readFile("shared/UiTheme.lua"), { environment = pureEnv, injectGlobals = true })()
local MapArt = luau.load(fs.readFile("shared/MapArt.lua"), { environment = pureEnv, injectGlobals = true })()
local RA = Data.RegionArt
check(T.MapArt and T.MapArt.labelFont == T.font.display and T.WorldMap and T.mapPoint, "theme map-art tokens added, existing tokens kept")

-- 1. Every island and every region on the chart.
local entries = MapArt.islands(islandsFolder)
check(#entries == #islandsFolder:GetChildren() and #entries >= 13, "every island model is an entry (" .. #entries .. ")")
local matched = MapArt.matchTiles(T.WorldMap, entries)
for _, tile in ipairs(T.WorldMap.islands) do
	local e = matched[tile.id]
	check(e ~= nil and e.region == tile.region, "chart tile " .. tile.id .. " has its island")
	check(math.abs(e.center.X - tile.x) < 1 and math.abs(e.center.Z - tile.z) < 1, "tile " .. tile.id .. " layout matches the world")
end
for _, region in ipairs(Data.Regions) do
	local found = false
	for _, tile in ipairs(T.WorldMap.islands) do if tile.region == region.id and matched[tile.id] then found = true end end
	check(found, "region " .. region.id .. " appears on the chart")
end

-- 2. True relative positions: the miniature copies keep world CFrames, and the
-- oblique camera keeps east right / south down.
local desktop, phone = MapArt.BUDGET.desktop, MapArt.BUDGET.phone
local landmarkShapes = MapArt.landmarks(Data)
local scene = MapArt.buildScene(entries, desktop, { landmarks = landmarkShapes })
for i, isle in ipairs(scene.islands) do
	local meadow = isle.entry.model:FindFirstChild("Meadow")
	local copy = isle.model:FindFirstChild("Meadow")
	check(meadow and copy and (copy.CFrame.Position - meadow.CFrame.Position).Magnitude < 1e-3, "island " .. isle.entry.name .. " keeps its meadow at its world position")
	check(#isle.parts > 0 and isle.index == i, "island " .. isle.entry.name .. " has parts")
end
local W, Hh = 1366 - 36, 768 - 96
local focus, distance = MapArt.fitView(MapArt.samples(entries), W, Hh, MapArt.VIEW)
local cf = MapArt.cameraCFrame(focus, distance, MapArt.VIEW.pitch)
local screen = {}
for _, e in ipairs(entries) do
	local x, y = MapArt.project(cf, MapArt.VIEW.fov, W, Hh, e.center)
	check(x and x >= 0 and x <= W and y >= 0 and y <= Hh, e.name .. " is on the chart at fit zoom")
	screen[e] = { x, y }
end
for _, a in ipairs(entries) do
	for _, b in ipairs(entries) do
		if a ~= b and math.abs(a.center.Y - b.center.Y) < 30 then
			if b.center.X - a.center.X > 120 then check(screen[b][1] > screen[a][1], b.name .. " is east (right) of " .. a.name) end
			if b.center.Z - a.center.Z > 120 then check(screen[b][2] > screen[a][2], b.name .. " is south (lower) of " .. a.name) end
		end
	end
end

-- 3. Warp markers match the waypoints (Data.RegionArt.Warps anchors).
for _, warp in ipairs(RA.Warps) do
	local anchor = islandsFolder:FindFirstChild("Anchor_" .. warp.anchor, true)
	check(anchor ~= nil, "warp anchor " .. warp.anchor .. " exists")
	local hit = false
	for _, tile in ipairs(T.WorldMap.islands) do
		local e = matched[tile.id]
		if tile.region == warp.region and anchor:IsDescendantOf(e.model) then
			local pos, from = MapArt.warpPoint(tile, e, Data)
			check(from == "Anchor_" .. warp.anchor and (pos - anchor.CFrame.Position).Magnitude < 1e-3, "warp marker of " .. tile.id .. " is the " .. warp.anchor .. " waypoint")
			hit = true
		end
	end
	check(hit, "region " .. warp.region .. " shows its warp marker")
end
for _, tile in ipairs(T.WorldMap.islands) do
	local e = matched[tile.id]
	local pos = MapArt.warpPoint(tile, e, Data)
	local flat = Vector3.new(pos.X - e.center.X, 0, pos.Z - e.center.Z).Magnitude
	check(flat <= e.radius * 1.15, "warp marker of " .. tile.id .. " stands on its island")
end

-- 4. Budgets per device, what is dropped, forge upgrades.
local phoneScene = MapArt.buildScene(entries, phone, { landmarks = landmarkShapes })
for label, pair in pairs({ desktop = { scene, desktop }, phone = { phoneScene, phone } }) do
	local s, b = pair[1], pair[2]
	local parts, tris = 0, 0
	for _, isle in ipairs(s.islands) do
		for _, p in ipairs(isle.parts) do
			parts += 1
			tris += MapArt.triangles(p)
			check(#p:GetChildren() == 0 and p.Name:sub(1, 7) ~= "Anchor_" and not p.CanCollide and not p.CastShadow, label .. ": copies are bare, anchored-only parts")
		end
	end
	check(parts == s.stats.parts and parts <= b.parts, label .. " part budget: " .. parts .. " <= " .. b.parts)
	check(tris <= b.triangles and s.stats.triangles <= b.triangles, label .. " triangle budget: " .. tris .. " <= " .. b.triangles)
	for _, d in ipairs(s.root:GetDescendants()) do
		check(d:IsA("Model") or d:IsA("BasePart"), label .. ": nothing but models and parts in the miniature (" .. d.ClassName .. ")")
	end
	print(string.format("Sky Chart miniature (%s): %d parts, %d triangles over %d islands; %d forge requests queued.", label, parts, tris, #s.islands, #s.queue))
end
check(phoneScene.stats.parts < scene.stats.parts, "phones copy fewer parts")
local totalWorld = 0
for _, e in ipairs(entries) do for _, d in ipairs(e.model:GetDescendants()) do if d:IsA("BasePart") then totalWorld += 1 end end end
check(scene.stats.parts < totalWorld, "the miniature is simplified (" .. scene.stats.parts .. " of " .. totalWorld .. " world parts)")
-- Every island keeps its foundation and keel host (the hull) on both devices.
for _, s in ipairs({ scene, phoneScene }) do
	for _, isle in ipairs(s.islands) do
		check(isle.model:FindFirstChild("Floating foundation") ~= nil, isle.entry.name .. " keeps its hull")
	end
end
-- Pure planner: priority first, quotas, budgets.
local function rec(priority, extent, tris) return { priority = priority, extent = extent, tris = tris } end
local chosen, used = MapArt.plan({ { rec(0, 50, 48), rec(2, 9, 12), rec(2, 3, 12), rec(2, 6, 12) }, { rec(2, 4, 12), rec(2, 20, 12) } },
	{ parts = 4, triangles = 1000, floor = 1 })
check(used.parts == 4 and chosen[1][1].extent == 50 and chosen[1][2].extent == 9 and chosen[2][1].extent == 20, "planner keeps the hull, then the largest props per island")
local _, tight = MapArt.plan({ { rec(0, 50, 900), rec(2, 9, 200) } }, { parts = 10, triangles = 1000, floor = 1 })
check(tight.triangles <= 1000 and tight.parts == 1, "planner respects the triangle budget")
-- A MeshForge stand-in modelling what the real forge (forge.client.lua) does to
-- the chart: templates per shape with pins, LRU eviction of unpinned templates
-- (every mesh cloned from an evicted template goes blank: it carries the
-- template's StubTemplate id), revocation (ShapeRevoked) and yields (a request
-- can suspend mid-build, as CreateMeshPartAsync does).
local function forgeStub(tris)
	local F = { templates = {}, tokens = {}, nextToken = 0, nextTemplate = 0, calls = 0, accepted = 0, released = 0, hold = false, waiting = {}, hosts = {} }
	local function tpl(shape)
		local t = F.templates[shape]
		if not t then F.nextTemplate += 1; t = { id = F.nextTemplate, pins = 0 }; F.templates[shape] = t end
		return t
	end
	-- The world's own forged mesh beside its host, which the forge hides locally.
	function F.world(host)
		local m = roblox.Instance.new("MeshPart")
		m.Name, m.Size, m.CFrame = host.Name .. " Mesh", host.Size, host.CFrame
		m:SetAttribute("ShapeOf", host:GetAttribute("Shape"))
		m:SetAttribute("ShapeTriangles", 900)
		m:SetAttribute("StubTemplate", tpl(host:GetAttribute("Shape")).id)
		m.Parent = host.Parent
		host.LocalTransparencyModifier = 1
		return m
	end
	-- LRU eviction of every template nothing pins.
	function F.evictIdle()
		for shape, t in pairs(F.templates) do if t.pins == 0 then F.templates[shape] = nil end end
	end
	function F.alive(id)
		for _, t in pairs(F.templates) do if t.id == id then return true end end
		return false
	end
	function F.revoke(token)
		local k = F.tokens[token]
		F.tokens[token] = nil
		if k.accepted then k.t.pins -= 1 end
		k.mesh:SetAttribute("ShapeRevoked", true)
	end
	F.fn = function(method, arg)
		if method == "ready" then return true end
		if method == "visual" then
			F.calls += 1
			F.hosts[arg] = (F.hosts[arg] or 0) + 1
			if F.hold then table.insert(F.waiting, coroutine.running()); coroutine.yield() end
			local t = tpl(arg:GetAttribute("Shape"))
			local m = roblox.Instance.new("MeshPart")
			m.Size, m.CFrame, m.Color = arg.Size, arg.CFrame, arg.Color
			m:SetAttribute("StubTemplate", t.id)
			F.nextToken += 1
			F.tokens[F.nextToken] = { t = t, mesh = m }
			return m, tris or 1800, F.nextToken
		elseif method == "accept" then
			local k = F.tokens[arg]
			if not k then return false end
			k.accepted, k.t.pins = true, k.t.pins + 1
			F.accepted += 1
			return true
		elseif method == "release" then
			local k = F.tokens[arg]
			F.tokens[arg] = nil
			if k and k.accepted then k.t.pins -= 1 end
			F.released += 1
			return true
		end
		return nil
	end
	return F
end
local function blankParts(s0, F)
	local n = 0
	for _, isle in ipairs(s0.islands) do
		for _, p in ipairs(isle.parts) do
			local id = p:GetAttribute("StubTemplate")
			if id and not F.alive(id) then n += 1 end
		end
	end
	return n
end
-- Forge upgrades: hosts swap for meshes, within the forge and triangle budgets.
local queued = #scene.queue
local before = scene.stats.parts
local stub = forgeStub()
local added = MapArt.upgrade(scene, stub.fn)
check(queued > 0 and added > 0 and added <= desktop.forge and scene.stats.forged == added, "forged hull / landmark meshes replace their hosts (" .. added .. ")")
check(scene.stats.triangles <= desktop.triangles and scene.stats.parts <= desktop.parts and scene.stats.parts >= before, "forge upgrades stay in budget")
check(#scene.queue == 0, "the forge queue is spent once")
check(stub.accepted == added and stub.released == stub.calls - added, "accepted meshes pin; rejected ones are released at once")

-- QC H1: the forge's own world meshes are never copied (their template can be
-- evicted); hidden hull / landmark hosts stand in and queue for a pinned chart
-- mesh; other hidden hosts are dropped. After LRU eviction nothing goes blank.
do
	local F = forgeStub()
	local majors, props, worldMeshes = {}, {}, {}
	for _, e in ipairs(entries) do
		for _, d in ipairs(e.model:GetDescendants()) do
			local shp = d:GetAttribute("Shape")
			if d:IsA("BasePart") and not d:IsA("MeshPart") and type(shp) == "string" and d.Transparency < 0.9 then
				local size = math.max(d.Size.X, d.Size.Y, d.Size.Z)
				if (MapArt.HULL[shp] or landmarkShapes[shp]) and #majors < 10 then table.insert(majors, d)
				elseif not MapArt.HULL[shp] and not landmarkShapes[shp] and size >= desktop.minExtent * 2 and #props < 40 then table.insert(props, d) end
			end
		end
	end
	check(#majors > 0 and #props > 0, "the world has visible landmark hosts and prop hosts (" .. #majors .. ", " .. #props .. ")")
	for _, h in ipairs(majors) do table.insert(worldMeshes, F.world(h)) end
	for _, h in ipairs(props) do table.insert(worldMeshes, F.world(h)) end
	local s1 = MapArt.buildScene(entries, desktop, { landmarks = landmarkShapes })
	local queuedHosts, copiedAt = {}, {}
	for _, job in ipairs(s1.queue) do queuedHosts[job.host] = job end
	for _, isle in ipairs(s1.islands) do
		for _, p in ipairs(isle.parts) do
			check(p:GetAttribute("ShapeOf") == nil, "no forged world mesh is copied (" .. p.Name .. ")")
			copiedAt[p.Name .. "@" .. tostring(p.CFrame.Position)] = true
		end
	end
	for _, h in ipairs(majors) do
		local job = queuedHosts[h]
		check(job and job.stand and copiedAt[h.Name .. "@" .. tostring(h.CFrame.Position)], "hidden landmark host " .. h.Name .. " stands in and is queued")
	end
	for _, h in ipairs(props) do
		check(not copiedAt[h.Name .. "@" .. tostring(h.CFrame.Position)] and not queuedHosts[h], "hidden prop host " .. h.Name .. " is dropped")
	end
	MapArt.upgrade(s1, F.fn)
	check(s1.stats.forged > 0, "the stand-ins are upgraded through the chart's pinned meshes")
	F.evictIdle()
	check(blankParts(s1, F) == 0, "after LRU eviction no chart part is blank (every chart mesh is pinned)")
	-- H2 (chart side): a revoked mesh gives its slot back to the stand-in.
	local job = s1.forged[1]
	local isle1, mesh1, stand1 = job.isle, job.mesh, job.stand
	local tris0, forged0 = s1.stats.triangles, s1.stats.forged
	F.revoke(job.token)
	check(MapArt.checkRevoked(s1) == 1 and stand1 and stand1.Parent == isle1.model and table.find(isle1.parts, stand1) and not table.find(isle1.parts, mesh1),
		"a revoked mesh swaps back to its primitive stand-in")
	check(s1.stats.forged == forged0 - 1 and s1.stats.triangles == tris0 - job.net, "the revert gives back its triangles")
	-- The chart is destroyed: every accepted pin is released.
	local pinsBefore = F.accepted
	MapArt.releaseAll(s1, F.fn)
	local pinned = 0
	for _, t in pairs(F.templates) do pinned += t.pins end
	check(pinsBefore > 0 and pinned == 0, "destroying the chart releases its pins")
	s1.root:Destroy()
	for _, m in ipairs(worldMeshes) do m:Destroy() end
	for _, h in ipairs(majors) do h.LocalTransparencyModifier = 0 end
	for _, h in ipairs(props) do h.LocalTransparencyModifier = 0 end
end
-- QC H3 (chart side): the forge yields mid-request. A second upgrade call never
-- repeats a host, and a scene destroyed meanwhile releases what comes back.
do
	local F = forgeStub()
	local s2 = MapArt.buildScene(entries, phone, { landmarks = landmarkShapes })
	F.hold = true
	local co = coroutine.create(MapArt.upgrade)
	assert(coroutine.resume(co, s2, F.fn))
	check(coroutine.status(co) == "suspended" and F.calls == 1, "the first request is in flight")
	check(MapArt.upgrade(s2, F.fn) == 0 and F.calls == 1, "a concurrent upgrade waits its turn (no repeated request)")
	F.hold = false
	assert(coroutine.resume(table.remove(F.waiting, 1)))
	check(coroutine.status(co) == "dead" and s2.stats.forged > 0, "the upgrade finishes after the yield")
	local repeated = 0
	for _, n in pairs(F.hosts) do if n > 1 then repeated += 1 end end
	check(repeated == 0, "every host is requested once")
	local s3 = MapArt.buildScene(entries, phone, { landmarks = landmarkShapes })
	local G = forgeStub()
	G.hold = true
	local co3 = coroutine.create(MapArt.upgrade)
	assert(coroutine.resume(co3, s3, G.fn))
	MapArt.releaseAll(s3, G.fn)
	G.hold = false
	assert(coroutine.resume(table.remove(G.waiting, 1)))
	check(G.accepted == 0 and G.released == 1 and s3.stats.forged == 0, "a mesh arriving after the chart is destroyed is released, never pinned")
	s2.root:Destroy()
	s3.root:Destroy()
end
-- QC L1: locked forged MeshParts take Theme.MapArt.lockWash (their palette is in vertex colours).
do
	local wash = roblox.Color3.fromHex(T.MapArt.lockWash)
	local s4 = MapArt.buildScene({ entries[1] }, desktop, { landmarks = landmarkShapes, wash = wash })
	MapArt.upgrade(s4, forgeStub().fn)
	local isle4 = s4.islands[1]
	MapArt.setLocked(isle4, true)
	local meshes, washed, tinted = 0, 0, 0
	for i, p in ipairs(isle4.parts) do
		if p:IsA("MeshPart") then meshes += 1; if p.Color == wash then washed += 1 end
		elseif p.Color ~= isle4.colors[i] then tinted += 1 end
	end
	check(meshes > 0 and washed == meshes and tinted > 0, "locked meshes take the lock wash, primitives the grey tint")
	MapArt.setLocked(isle4, false)
	s4.root:Destroy()
end
-- QC M6: the idle pre-build yields every MapArt.CHUNK copied parts; per-chunk cost.
do
	local times, last = {}, os.clock()
	local timed = MapArt.buildScene(entries, desktop, { landmarks = landmarkShapes, pause = function()
		local now = os.clock()
		table.insert(times, now - last)
		last = now
	end })
	table.insert(times, os.clock() - last)
	local worst, total = 0, 0
	for _, t in ipairs(times) do worst = math.max(worst, t); total += t end
	check(timed.stats.chunks >= math.floor(timed.stats.parts / MapArt.CHUNK) and #times == timed.stats.chunks + 1, "the build yields every " .. MapArt.CHUNK .. " parts (" .. timed.stats.chunks .. " chunks)")
	print(string.format("Sky Chart pre-build (desktop): %d parts in %d chunks; measured here %.1f ms/chunk mean, %.1f ms worst (Lune; one chunk runs per frame, so the first open no longer waits on the whole copy).",
		timed.stats.parts, #times, total / #times * 1000, worst * 1000))
	timed.root:Destroy()
end

-- 5. Lock wash and hover raise are exact and reversible.
local isle = scene.islands[1]
local c0, p0 = isle.parts[1].Color, isle.parts[1].CFrame
check(MapArt.setLocked(isle, true) and isle.parts[1].Color ~= c0, "locked island is washed grey")
local lockedColor = isle.parts[1].Color
check(math.abs(lockedColor.R - lockedColor.G) < math.abs(c0.R - c0.G) + 0.02, "lock wash lowers saturation")
check(not MapArt.setLocked(isle, true), "no recolour without a change")
MapArt.setLocked(isle, false)
check(isle.parts[1].Color == c0, "unlock restores the palette")
MapArt.setLift(isle, 6)
check(math.abs(isle.parts[1].CFrame.Position.Y - p0.Position.Y - 6) < 1e-4, "hover raises the island")
MapArt.setLift(isle, 0)
check((isle.parts[1].CFrame.Position - p0.Position).Magnitude < 1e-4, "hover end lowers it back")

-- 6. Minimap plates from the real islands.
local landmarkIsles = {}
for _, art in pairs(RA.Regions) do landmarkIsles[art.landmark.isle] = art.landmark end
local sawWater, sawPath, sawBeacon = false, false, false
for _, e in ipairs(entries) do
	for _, label in ipairs({ "desktop", "phone" }) do
		local cap = MapArt.BUDGET[label].plate
		local spec = MapArt.plateSpec(e, Data, T, cap)
		check(#spec <= cap and #spec >= 3, e.name .. " plate within its " .. label .. " cap")
		local stars = 0
		for _, s in ipairs(spec) do
			if s.glyph == "★" then stars += 1 end
			if s.glyph == "✦" then sawBeacon = true end
			if s.z == 5 then sawWater = true end
			if s.z == 6 then sawPath = true end
			check(s.u > -0.6 and s.u < 1.6 and s.v > -0.6 and s.v < 1.6, e.name .. " plate shape near its island")
		end
		local lm = landmarkIsles[e.name]
		local hasLandmarkPart = false
		if lm then for _, d in ipairs(e.model:GetDescendants()) do if d:GetAttribute("Shape") == lm.shape then hasLandmarkPart = true end end end
		check(stars == (if hasLandmarkPart then 1 else 0) or stars >= 1 and hasLandmarkPart, e.name .. " landmark star (" .. label .. ")")
	end
end
check(sawWater and sawPath and sawBeacon, "plates draw water, paths and warp beacons")

------------------------------------------------------------------------------
-- 7. hud.client.lua with the real world through the UI harness.
------------------------------------------------------------------------------
local H = require("./tools/ui-harness")
local function space()
	return {
		CurrentCamera = H.new("Camera"),
		FindFirstChild = function(_, name) return world:FindFirstChild(name) end,
	}
end
for _, size in ipairs({ roblox.Vector2.new(1366, 768), roblox.Vector2.new(844, 390) }) do
	local touch = size.Y < 500
	local tag = size.X .. "x" .. size.Y
	local ui = H.runAtlas(size, { touch = touch })
	ui.player:SetAttribute("CoopId", "crew-1")
	ui.player:SetAttribute("IsleRegionHere", "Hub")
	local character = H.new("Model", { Name = "Character" })
	local root = H.new("Part", { Name = "HumanoidRootPart", CFrame = CFrame.new(12, 4, 20) })
	root.Parent = character
	ui.player.Character = character
	local delays = {}
	local layer = H.runHud(size, ui.player, ui.replicated, { touch = touch, workspace = space(), delays = delays })
	local S = layer.state
	local art = S.art
	check(art ~= nil, "Sky Chart mounts the map art at " .. tag)
	check(art.builds == 0 and art.scene == nil, "nothing is built before the chart opens at " .. tag)
	-- QC L7: the looping drifts are paused while the chart is closed.
	for _, tw in ipairs(art.tweens) do check(not tw.playing, "chart tweens wait while closed at " .. tag) end
	if not touch then
		-- QC M6: desktop pre-builds in idle chunks after load (no first-open hitch).
		for _, d in ipairs(delays) do if d.seconds == MapArt.PREBUILD_DELAY then d.fn(table.unpack(d.args, 1, d.args.n)) end end
		local co, chunks = art.prebuildThread, 0
		check(co ~= nil and art.building, "the pre-build starts after load and yields at " .. tag)
		while coroutine.status(co) == "suspended" do chunks += 1; assert(coroutine.resume(co)) end
		check(art.builds == 1 and art.scene ~= nil and chunks >= 5 and not S.chart.Visible, "pre-built in " .. chunks .. " idle chunks before the first open at " .. tag)
	end
	layer.api.OnInvoke("chart")
	check(S.chart.Visible and art.builds == 1 and art.scene ~= nil, "first open shows the miniature at " .. tag)
	for _, tw in ipairs(art.tweens) do check(tw.playing, "chart tweens play while open at " .. tag) end
	local viewport = H.find(S.chart, "Miniature")
	check(viewport and viewport.ClassName == "ViewportFrame" and viewport.CurrentCamera and art.scene.root.Parent == viewport, "miniature lives in a ViewportFrame at " .. tag)
	local b = MapArt.budget(touch)
	check(art.scene.stats.parts <= b.parts and art.scene.stats.triangles <= b.triangles, "device budget at " .. tag .. " (" .. art.scene.stats.parts .. " parts)")
	check(art.budget.parts == b.parts and art.budget.triangles == b.triangles, (if touch then "phone" else "desktop") .. " profile at " .. tag)
	-- Cached: reopening and refreshing never rebuilds.
	local rootModel = art.scene.root
	for _ = 1, 3 do
		S.setChart(false)
		layer.api.OnInvoke("chart")
		art.refresh()
	end
	check(art.builds == 1 and art.scene.root == rootModel, "cache built once at " .. tag)
	-- Overlay: every tile sits on its projected warp point.
	local w, h = art.w, art.h
	for _, tile in ipairs(T.WorldMap.islands) do
		local link = art.links[tile.id]
		local t = S.tiles[tile.id]
		check(link and t, "tile " .. tile.id .. " linked at " .. tag)
		local x, y = MapArt.project(art.cf, art.view.fov, w, h, link.warp)
		check(math.abs(t.frame.Position.X.Offset - x) <= 1 and math.abs(t.frame.Position.Y.Offset - (y - 8)) <= 1, "tile " .. tile.id .. " on its warp point at " .. tag)
		check(t.frame:GetAttribute("MapArt") and not t.frame:FindFirstChild("Top").Visible and t.name.Font == T.MapArt.labelFont, "tile " .. tile.id .. " restyled at " .. tag)
		-- Locked state matches region access (the HUD's padlock).
		check(link.isle.locked == t.lock.Visible, "lock wash matches the padlock for " .. tile.id .. " at " .. tag)
	end
	check(art.links.Gloomhollow.isle.locked and not art.links.Hub.isle.locked, "Gloomhollow locked, Hub open at " .. tag)
	-- Home and crew insets.
	check(H.find(S.chart, "HomeInset").Visible and H.find(S.chart, "CrewInset").Visible, "home and crew haven insets at " .. tag)
	check(H.find(S.chart, "YouMarker").Visible, "player marker shown at " .. tag)
	-- Click actions keep their verbs.
	local travel = H.find(S.chart, "TravelButton")
	table.clear(ui.sent)
	H.press(H.find(H.find(S.chart, "Isle_Hub"), "Warp"))
	H.press(travel)
	check(ui.sent[1] and ui.sent[1][1] == "recall" and ui.sent[1][2] == "Hub", "Hub warp recalls at " .. tag)
	layer.api.OnInvoke("chart")
	local guided
	local request = H.new("BindableEvent", { Name = "WayfinderRequest" })
	request.Event:Connect(function(specs, label) guided = { specs, label } end)
	request.Parent = ui.player
	local quarry = art.links.Quarry
	local picked = art.click(quarry.sx, quarry.sy)
	check(picked == "Quarry" and S.warpPick and S.warpPick.id == "Quarry", "clicking the Quarry island picks its warp at " .. tag)
	check(H.find(S.chart, "WarpInfo").Visible, "info card beside the island at " .. tag)
	H.press(travel)
	check(guided and guided[2] == "Brassfall Quarry" and guided[1][1] == "region:Quarry" and guided[1][2] == "warp:Quarry", "region warps still guide through the Wayfinder at " .. tag)
	layer.api.OnInvoke("chart")
	-- The HUD's whole-tile button (locked isles are clickable) still picks.
	H.press(H.find(H.find(S.chart, "Isle_Gloomhollow"), "TileButton"))
	check(S.warpPick and S.warpPick.id == "Gloomhollow", "a locked isle's tile button picks it at " .. tag)
	check(S.tiles.Gloomhollow.button.Size.X.Offset <= 150, "tile button shrinks to the gem and name at " .. tag)
	check(travel.Text == "Locked" and H.find(S.chart, "Detail").Text:find("Mining 30", 1, true), "locked isle names its requirement at " .. tag)
	art.setHover("Gloomhollow")
	check(H.find(S.chart, "Halo").Visible and H.find(S.chart, "HoverCaption").Text:find("Mining 30", 1, true), "hover halo and requirement at " .. tag)
	check(art.links.Gloomhollow.isle.lift > 0, "hovered island raised at " .. tag)
	art.setHover(nil)
	check(art.links.Gloomhollow.isle.lift == 0, "hover end lowers it at " .. tag)
	guided = nil
	H.press(H.find(H.find(S.chart, "CrewInset"), "Warp"))
	H.press(travel)
	check(guided and guided[1][1] == "anchor:Waypoint_CrewHaven", "crew haven guides to its beacon at " .. tag)
	layer.api.OnInvoke("chart")
	table.clear(ui.sent)
	H.press(H.find(H.find(S.chart, "Isle_Home"), "Warp"))
	H.press(travel)
	check(ui.sent[1] and ui.sent[1][1] == "recall" and ui.sent[1][2] == "Home", "home recalls at " .. tag)
	-- Zoom and pan only move the camera (and never rebuild).
	layer.api.OnInvoke("chart")
	local cf0 = art.cf
	art.zoom(0.7)
	check(art.view.zoom < 1 and art.cf ~= cf0 and art.builds == 1, "zoom moves the camera at " .. tag)
	art.zoom(0.01)
	check(art.view.zoom == MapArt.VIEW.minZoom, "zoom is clamped at " .. tag)
	art.zoom(100)
	check(art.view.zoom == 1 and art.view.pan == Vector3.zero, "zooming out recentres at " .. tag)
	if touch then
		for _, t in pairs(S.tiles) do if t.warp.Visible then check(t.warp.Size.X.Offset >= 44, "warp gem is a 44 px target at " .. tag) end end
	end
	-- QC L4: no two island names overlap (at fit zoom and zoomed in).
	local function labelsClear(label)
		local rects = {}
		for _, t in pairs(S.tiles) do
			if t.frame.Visible and t.name.Visible and t.frame:GetAttribute("MapArt") and t ~= S.tiles.Home then
				local half = #t.name.Text * t.name.TextSize / 2
				local cx = t.frame.Position.X.Offset + t.name.Position.X.Offset
				local top = t.frame.Position.Y.Offset - 40 + 0.36 * 80 + t.name.Position.Y.Offset
				table.insert(rects, { x = cx - half, y = top, w = half * 2, h = MapArt.LABEL_H, id = t.island.id })
			end
		end
		for i = 1, #rects do
			for j = i + 1, #rects do
				local a, b = rects[i], rects[j]
				check(not (a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h), a.id .. " and " .. b.id .. " names clear " .. label .. " at " .. tag)
			end
		end
	end
	labelsClear("at fit zoom")
	art.zoom(0.5)
	labelsClear("zoomed in")
	art.zoom(100)
	-- QC L2: warp tiles above the halo and insets; the Home tile above its inset.
	check(S.tiles.Hub.frame.ZIndex > H.find(S.chart, "Halo").ZIndex and S.tiles.Hub.frame.ZIndex > H.find(S.chart, "CrewInset").ZIndex, "tiles over the halo and insets at " .. tag)
	check(S.tiles.Home.frame.ZIndex > H.find(S.chart, "HomeInset").ZIndex, "Home tile over its inset at " .. tag)
	-- QC M3: the tile button is the gem's own hit area.
	check(S.tiles.Quarry.button.Size.X.Offset <= 44 and S.tiles.Quarry.button.Size.Y.Offset <= 44, "tile button is gem-sized at " .. tag)
	-- QC M4: hover follows UserInputService positions (the same space as clicks).
	local quarry2 = art.links.Quarry
	layer.input.InputChanged:Fire({ UserInputType = roblox.Enum.UserInputType.MouseMovement, Position = Vector3.new(quarry2.sx, quarry2.sy, 0) })
	check(art.hover == "Quarry", "mouse hover picks the island under the cursor at " .. tag)
	layer.input.InputChanged:Fire({ UserInputType = roblox.Enum.UserInputType.MouseMovement, Position = Vector3.new(-50, -50, 0) })
	check(art.hover == nil, "leaving the sky clears the hover at " .. tag)
	-- QC M1: a second finger never pans the press; a pinch turns it into a non-click.
	local dragLayer = H.find(S.chart, "ChartDrag")
	local UIT = roblox.Enum.UserInputType
	local f1 = { UserInputType = UIT.Touch, Position = Vector3.new(200, 200, 0) }
	local f2 = { UserInputType = UIT.Touch, Position = Vector3.new(400, 260, 0) }
	dragLayer.InputBegan:Fire(f1)
	dragLayer.InputBegan:Fire(f2)
	local pan0 = art.view.pan
	f2.Position = Vector3.new(480, 300, 0)
	layer.input.InputChanged:Fire(f2)
	check(art.view.pan == pan0, "a second finger does not pan at " .. tag)
	layer.input.TouchPinch:Fire({}, 1.2, 0, roblox.Enum.UserInputState.Begin)
	S.warpPick = nil
	layer.input.InputEnded:Fire(f1)
	check(S.warpPick == nil, "a pinch never ends in a click at " .. tag)
	layer.input.TouchPinch:Fire({}, 1, 0, roblox.Enum.UserInputState.End)
	art.zoom(100)
	f1.Position = Vector3.new(200, 200, 0)
	dragLayer.InputBegan:Fire(f1)
	f1.Position = Vector3.new(260, 230, 0)
	layer.input.InputChanged:Fire(f1)
	check(art.view.pan ~= Vector3.zero, "the first finger pans at " .. tag)
	layer.input.InputEnded:Fire(f1)
	art.zoom(100)
	-- QC L5: gamepad: left stick pans, right stick zooms, A picks the hovered isle.
	layer.input.InputChanged:Fire({ UserInputType = UIT.Gamepad1, KeyCode = roblox.Enum.KeyCode.Thumbstick1, Position = Vector3.new(0.9, 0, 0) })
	check(art.view.pan ~= Vector3.zero, "the left stick pans at " .. tag)
	layer.input.InputChanged:Fire({ UserInputType = UIT.Gamepad1, KeyCode = roblox.Enum.KeyCode.Thumbstick2, Position = Vector3.new(0, 1, 0) })
	check(art.view.zoom < 1, "the right stick zooms at " .. tag)
	art.zoom(100)
	art.setHover("Quarry")
	S.warpPick = nil
	layer.input.InputBegan:Fire({ UserInputType = UIT.Gamepad1, KeyCode = roblox.Enum.KeyCode.ButtonA }, false)
	check(S.warpPick and S.warpPick.id == "Quarry", "A picks the hovered isle at " .. tag)
	art.setHover(nil)
	-- QC M2: the sky resizing while open lays the chart out again.
	local skyFrame = H.find(S.chart, "Sky")
	local w0 = art.w
	skyFrame.Size = roblox.UDim2.new(1, -140, 1, -36)
	skyFrame:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	check(art.w ~= w0 and art.w > 0, "a resized sky relays out at " .. tag)
	skyFrame.Size = roblox.UDim2.new(1, -20, 1, -36)
	skyFrame:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	-- QC M5 / L8: the home inset rebuilds when the home changes, on the next open only.
	local homeModel = archipelago:FindFirstChild("WayfarersRest_1")
	local homeScene = art.insets.home.scene
	local level0 = homeModel:GetAttribute("HomesteadLevel")
	homeModel:SetAttribute("HomesteadLevel", (tonumber(level0) or 1) + 1)
	art.refresh()
	check(art.insets.home.scene == homeScene, "no inset rebuild while the chart stays open at " .. tag)
	S.setChart(false)
	layer.api.OnInvoke("chart")
	check(art.insets.home.scene ~= homeScene and art.insets.home.scene ~= nil, "an expanded home rebuilds its inset on the next open at " .. tag)
	homeModel:SetAttribute("HomesteadLevel", level0)
	-- QC L3: insets fill from the right with no gap (crew alone takes slot 0).
	homeModel.Parent = nil
	S.setChart(false)
	layer.api.OnInvoke("chart")
	check(not H.find(S.chart, "HomeInset").Visible and H.find(S.chart, "CrewInset").Visible and H.find(S.chart, "CrewInset").Position.X.Offset == -8, "the crew inset takes the first slot without a home at " .. tag)
	homeModel.Parent = archipelago
	S.setChart(false)
	layer.api.OnInvoke("chart")
	-- QC L9: no MeshForge yet: the queue waits; once MeshForgeLocal appears, a refresh upgrades.
	check(#art.scene.queue > 0 and art.scene.stats.forged == 0, "forge requests wait for MeshForge at " .. tag)
	local api = H.new("BindableFunction", { Name = "MeshForgeLocal" })
	local hudStub = forgeStub()
	local inner = hudStub.fn
	api.Invoke = function(_, method, arg)
		if method == "visual" then
			local m, tris, token = inner(method, arg)
			local copy = H.new("MeshPart", { Name = "Forged", Size = m.Size, CFrame = m.CFrame, Color = m.Color })
			return copy, tris, token
		end
		return inner(method, arg)
	end
	api.Parent = ui.replicated
	art.refresh()
	check(art.scene.stats.forged > 0 and hudStub.accepted == art.scene.stats.forged, "MeshForge appearing later still upgrades the chart at " .. tag)
	S.setChart(false)
	for _, tw in ipairs(art.tweens) do check(not tw.playing, "chart tweens pause when closed at " .. tag) end
end

------------------------------------------------------------------------------
-- 8. Minimap art through nav.client.lua (harness) and on the real islands.
------------------------------------------------------------------------------
do
	local size = roblox.Vector2.new(1366, 768)
	local ui = H.runAtlas(size, {})
	local nav = H.runNav(size, ui.player, ui.replicated, {})
	local holder = H.find(nav.gui, "IslandArt")
	check(holder ~= nil, "minimap draws island plates")
	local function countPlates()
		local plates = 0
		for _, c in ipairs(holder:GetChildren()) do if c.Name:sub(1, 6) == "Plate_" then plates += 1 end end
		return plates
	end
	-- QC L6: plates are built lazily, at most MapArt.PLATES_PER_TICK per tick.
	check(countPlates() <= MapArt.PLATES_PER_TICK, "the first tick builds at most " .. MapArt.PLATES_PER_TICK .. " plates (" .. countPlates() .. ")")
	for _ = 1, 20 do nav.run.Heartbeat:Fire(1) end
	local plates = countPlates()
	check(plates == #T.WorldMap.islands, "one plate per island after a few ticks (" .. plates .. ")")
	-- Real islands: plates are cached; a zoom only resizes them.
	local env = { Instance = { new = function(class) return H.new(class) end }, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		Vector2 = roblox.Vector2, Vector3 = Vector3, CFrame = CFrame, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, typeof = typeof }
	local MA = H.loadMapArt(env)
	local TM = H.loadTheme(env)
	local map = H.new("Frame")
	local layerFrame = H.new("Frame")
	layerFrame.Parent = map
	local art = MA.mountMinimap({ layer = layerFrame, Theme = TM, Data = Data, touch = false })
	local list = Data.Townsfolk.scanIslands(islandsFolder).list
	local ticks = 0
	repeat
		art.draw(Vector3.new(0, 0, 0), 0.32, 78, list)
		ticks += 1
	until art.built >= #list or ticks > 50
	local built = art.built
	check(built == #list and ticks == math.ceil(#list / MA.PLATES_PER_TICK), "a plate per island on the real world, " .. MA.PLATES_PER_TICK .. " per tick (" .. built .. " in " .. ticks .. ")")
	art.draw(Vector3.new(40, 0, 10), 0.8, 78, list)
	art.draw(Vector3.new(-200, 0, 30), 0.12, 78, list)
	check(art.built == built, "plates are built once and re-placed")
	-- Keyed on model, centre and radius: an expanded island rebuilds its plate.
	local grown = table.clone(list[1])
	grown.radius += 20
	local changed = table.clone(list)
	changed[1] = grown
	local plate0 = art.plates[grown.model]
	art.draw(Vector3.new(0, 0, 0), 0.32, 78, changed)
	check(art.built == built + 1 and art.plates[grown.model] ~= plate0 and art.plates[grown.model].radius == grown.radius, "an island's new radius rebuilds its plate")
	for _, plate in pairs(art.plates) do
		check(#plate.frame:GetChildren() <= MA.BUDGET.desktop.plate * 3, "plate " .. plate.frame.Name .. " within its budget")
	end
	-- Marker styling: quest givers get a "!".
	local f = H.new("Frame")
	H.new("UICorner").Parent = f
	local npc = roblox.Instance.new("Model")
	local giver
	for _, q in ipairs(Data.Quests) do if q.giver then giver = q.giver break end end
	npc:SetAttribute("TownsfolkRole", giver)
	art.styleMarker(f, "npc", npc)
	check(f:FindFirstChild("Quest") and f:FindFirstChild("Quest").Text == "!", "quest givers are marked on the minimap")
end

------------------------------------------------------------------------------
-- 9. Hook points stay small; no per-frame work in the module.
------------------------------------------------------------------------------
local mapSource = fs.readFile("shared/MapArt.lua")
for _, word in ipairs({ "RenderStepped", "Heartbeat", "BindToRenderStep", "Stepped" }) do
	check(not mapSource:find(word, 1, true), "MapArt has no per-frame loop (" .. word .. ")")
end
local hud, nav = fs.readFile("hud.client.lua"), fs.readFile("nav.client.lua")
check(hud:find("MapArt.mountChart", 1, true) and hud:find("S.art.refresh()", 1, true), "hud.client.lua hooks the chart")
check(nav:find("mapArt.draw(", 1, true) and nav:find("mapArt.dress(", 1, true) and nav:find("mapArt.styleMarker(", 1, true), "nav.client.lua hooks the minimap")
local forge = fs.readFile("forge.client.lua")
check(forge:find("MeshForgeLocal", 1, true) and forge:find("ShapeTriangles", 1, true), "MeshForge serves chart meshes with their triangle counts")
local project = fs.readFile("default.project.json")
check(project:find('"AetherMapArt": { "$path": "shared/MapArt.lua" }', 1, true), "AetherMapArt is in ReplicatedStorage")

print("Map art (§32): " .. checks .. " checks.")
print("SUITE-END verify-map.luau")
