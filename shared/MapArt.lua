--!nocheck
-- Map Art (ReplicatedStorage.AetherMapArt, docs/DEPTH-CONTRACT.md §32): the Sky
-- Chart's 3D miniature archipelago and the minimap's island plates.
--
-- Sky Chart (MapArt.mountChart, hooked from hud.client.lua): one ViewportFrame
-- looking at a copy of the real Workspace.Islands models, simplified (no
-- prompts, scripts, GUIs, lights, anchors or small props) and built ONCE, on
-- the first open, then cached. The copy keeps world coordinates, so every
-- island sits at its true relative position; the camera (oblique 3/4 view from
-- the south, narrow FOV) frames the whole archipelago, which is what makes it
-- a miniature on screen. Pan (drag), zoom (wheel / pinch) and hover only move
-- the camera or re-place the 2D overlay; nothing is rebuilt. The overlay is the
-- HUD's own warp tiles (S.tiles: Warp / Lock / Name / Here), re-placed on each
-- island's warp anchor (Data.RegionArt.Warps) and restyled as glowing gems
-- with bold outlined names. Locked isles are washed grey in the miniature.
-- Home and crew haven isles are instanced far from the archipelago, so they
-- get their own small viewport insets. Clouds drift with looping tweens: no
-- per-frame Lua, no per-frame allocation.
--
-- Budgets (MapArt.BUDGET; verify-map.luau checks them against the real world):
--   desktop  2400 copied parts, 260k triangles, props under 2.2 studs dropped,
--            up to 40 forged hull/landmark meshes requested, 9 clouds,
--            260 parts per inset, 56 shapes per minimap plate
--   phone     720 copied parts,  70k triangles, props under 5 studs dropped,
--            up to 16 forged meshes, 5 clouds, 110 parts per inset, 26 shapes
-- Parts are chosen per island in proportion to its size (every island keeps its
-- hull, meadow and tiers first, then its largest props). Triangles: primitives
-- by MapArt.TRIS, forged meshes by their ShapeTriangles attribute.
--
-- Minimap (MapArt.mountMinimap, hooked from nav.client.lua): per island, a
-- cached plate of frames drawn top-down from the island's own parts (cliff
-- shadow, stone rim, meadow tinted by the region palette, raised tiers, water,
-- paths and bridges, roofs, canopy dots, the landmark star and warp beacons),
-- in scale units so a zoom only re-sizes the plate. Marker styling for
-- townsfolk (quest givers get a "!"), warps and stations.
--
-- No requires: callers pass Theme and Data, so this loads the same way in
-- Studio, the UI harness (tools/ui-harness.luau) and verify-map.luau.
local MapArt = {}
MapArt.VERSION = 1

MapArt.BUDGET = {
	desktop = {parts = 2400, triangles = 260000, minExtent = 2.2, floor = 40, forge = 40, clouds = 9, insetParts = 260, plate = 56},
	phone = {parts = 720, triangles = 70000, minExtent = 5, floor = 18, forge = 16, clouds = 5, insetParts = 110, plate = 26},
}
-- Triangle cost of a copied primitive (Roblox's own part meshes, approximate).
MapArt.TRIS = {Block = 12, Wedge = 10, CornerWedge = 8, Cylinder = 48, Ball = 180, Truss = 72, Mesh = 400}
-- Hull meshes (world.server.lua island(): forged cliff wall and keel).
MapArt.HULL = {IslandCliff = true, IslandCliffBare = true, IslandKeel = true, IslandKeelCrystal = true, IslandKeelEmber = true}
-- Island-shaping primitives kept before any prop.
MapArt.CORE = {Meadow = true, ["Upper meadow"] = true, ["Tier cliff"] = true, ["Floating foundation"] = true, ["Island underside"] = true,
	["Continuous bridge deck"] = true}
MapArt.VIEW = {pitch = 38, fov = 24, minZoom = 0.36, maxZoom = 1, margin = 0.035, zoomStep = 0.88, phoneZoom = 0.62}
-- Instanced isles shown as insets (not at a place in the archipelago).
MapArt.CREW = {id = "Crew", u = 0.3, v = 0.86, size = 80, name = "Crew Haven", region = "Hub", travel = "guide", specs = {"anchor:Waypoint_CrewHaven"}}

local function rgb(hex) return Color3.fromHex(hex) end
local function posOf(part) return part.CFrame.Position end
function MapArt.budget(touch) return if touch then MapArt.BUDGET.phone else MapArt.BUDGET.desktop end

------------------------------------------------------------------------------
-- World reading (pure apart from instance reads).
------------------------------------------------------------------------------
-- Islands: every Model under the folder with IslandCenter / IslandRadius.
function MapArt.islands(folder)
	local out = {}
	if not folder then return out end
	local ok, children = pcall(function() return folder:GetChildren() end)
	if not ok then return out end
	for _, model in ipairs(children) do
		local center, radius = model:GetAttribute("IslandCenter"), model:GetAttribute("IslandRadius")
		if typeof(center) == "Vector3" and type(radius) == "number" then
			table.insert(out, {model = model, name = model.Name, center = center, radius = radius, region = model:GetAttribute("Region")})
		end
	end
	return out
end
-- Theme.WorldMap tile id → island entry: by name, else the nearest island of
-- the tile's region ("Skyreach Heights" is the model "Skyreach").
function MapArt.matchTiles(worldMap, entries)
	local out, taken = {}, {}
	for _, tile in ipairs(worldMap.islands) do
		for _, e in ipairs(entries) do
			if e.name == tile.name and not taken[e] then out[tile.id], taken[e] = e, true break end
		end
	end
	for _, tile in ipairs(worldMap.islands) do
		if not out[tile.id] then
			local best, bestD
			for _, e in ipairs(entries) do
				if not taken[e] and e.region == tile.region then
					local d = (e.center.X - (tile.x or 0)) ^ 2 + (e.center.Z - (tile.z or 0)) ^ 2
					if not bestD or d < bestD then best, bestD = e, d end
				end
			end
			if best then out[tile.id], taken[best] = best, true end
		end
	end
	return out
end
-- Landmark shapes by island name (Data.RegionArt.Regions[*].landmark).
function MapArt.landmarks(Data)
	local byShape, byIsle = {}, {}
	local RA = Data and Data.RegionArt
	for region, art in pairs(RA and RA.Regions or {}) do
		local l = art.landmark
		if l then byShape[l.shape] = region; byIsle[l.isle] = l end
	end
	return byShape, byIsle
end
-- Warp point of a chart tile: its region's warp anchor (Data.RegionArt.Warps,
-- the Warp Keeper's arrival) when that anchor is on this island, else the
-- tile's own Wayfinder anchor, else the island's centre. Returns pos, source.
function MapArt.warpPoint(tile, entry, Data)
	local names = {}
	local RA = Data and Data.RegionArt
	local warp = RA and RA.WarpByRegion and RA.WarpByRegion[tile.region]
	if warp then table.insert(names, "Anchor_" .. warp.anchor) end
	for _, spec in ipairs(tile.specs or {}) do
		local a = string.match(spec, "^anchor:(.+)$")
		if a then table.insert(names, "Anchor_" .. a) end
	end
	for _, name in ipairs(names) do
		local found = entry.model:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then return posOf(found), name end
	end
	return entry.center, "center"
end

------------------------------------------------------------------------------
-- Selection: which parts of an island the miniature copies.
------------------------------------------------------------------------------
local function triangles(part)
	if part:IsA("MeshPart") then return tonumber(part:GetAttribute("ShapeTriangles")) or MapArt.TRIS.Mesh end
	local class = part.ClassName
	if class == "WedgePart" then return MapArt.TRIS.Wedge
	elseif class == "CornerWedgePart" then return MapArt.TRIS.CornerWedge
	elseif class == "TrussPart" then return MapArt.TRIS.Truss end
	local ok, shape = pcall(function() return part.Shape end)
	if ok and shape == Enum.PartType.Cylinder then return MapArt.TRIS.Cylinder end
	if ok and shape == Enum.PartType.Ball then return MapArt.TRIS.Ball end
	return MapArt.TRIS.Block
end
MapArt.triangles = triangles
-- A candidate record, or nil when the part is dropped. priority 0 = hull,
-- meadow, tiers, landmarks (always first); 2 = props, largest first.
-- forge = a slot host whose forged mesh is worth asking MeshForge for.
function MapArt.classify(part, budget, landmarkShapes)
	if not part:IsA("BasePart") then return nil end
	local name = part.Name
	if string.sub(name, 1, 7) == "Anchor_" then return nil end
	-- What the player sees: the forge hides a host locally once its mesh exists
	-- (the mesh, a MeshPart with ShapeOf, is copied instead).
	local hidden = false
	pcall(function() hidden = part.LocalTransparencyModifier >= 0.99 end)
	if hidden then return nil end
	local shape = part:GetAttribute("Shape")
	local shapeOf = part:GetAttribute("ShapeOf")
	local major = (type(shape) == "string" and (MapArt.HULL[shape] or (landmarkShapes and landmarkShapes[shape] ~= nil)))
		or (type(shapeOf) == "string" and (MapArt.HULL[shapeOf] or (landmarkShapes and landmarkShapes[shapeOf] ~= nil)))
	local size = part.Size
	local extent = math.max(size.X, size.Y, size.Z)
	local forge = major and type(shape) == "string" and not part:IsA("MeshPart")
	if part.Transparency >= 0.9 then
		-- An invisible slot box shows nothing unless its forged mesh is fetched.
		if forge then return {part = part, priority = 0, extent = extent, tris = 0, forge = true, forgeOnly = true} end
		return nil
	end
	local priority = 2
	if major or MapArt.CORE[name] then priority = 0
	elseif extent < budget.minExtent then return nil end
	return {part = part, priority = priority, extent = extent, tris = triangles(part), forge = forge}
end
-- groups: {{records}} per island. Pass 1 keeps every priority-0 record; pass 2
-- gives each island a quota of the remaining parts in proportion to its
-- candidates (at least budget.floor), largest props first. Pure.
function MapArt.plan(groups, budget)
	local chosen, used, tris, rest = {}, 0, 0, 0
	for i, g in ipairs(groups) do
		table.sort(g, function(a, b)
			if a.priority ~= b.priority then return a.priority < b.priority end
			return a.extent > b.extent
		end)
		chosen[i] = {}
	end
	local cursor = {}
	for i, g in ipairs(groups) do
		local k = 1
		while g[k] and g[k].priority == 0 do
			local r = g[k]
			if used + (if r.forgeOnly then 0 else 1) <= budget.parts and tris + r.tris <= budget.triangles then
				table.insert(chosen[i], r)
				if not r.forgeOnly then used += 1 end
				tris += r.tris
			end
			k += 1
		end
		cursor[i] = k
		rest += #g - k + 1
	end
	local left = budget.parts - used
	for i, g in ipairs(groups) do
		local n = #g - cursor[i] + 1
		local quota = if rest > 0 then math.max(budget.floor, math.floor(left * n / rest)) else 0
		local k = cursor[i]
		while g[k] and quota > 0 and used < budget.parts do
			local r = g[k]
			if tris + r.tris <= budget.triangles then
				table.insert(chosen[i], r)
				used += 1
				tris += r.tris
				quota -= 1
			end
			k += 1
		end
		cursor[i] = k
	end
	-- Pass 3: parts left over from rounding go to the largest remaining props.
	while used < budget.parts do
		local bestI
		for i, g in ipairs(groups) do
			local r = g[cursor[i]]
			while r and tris + r.tris > budget.triangles do cursor[i] += 1; r = g[cursor[i]] end
			if r and (not bestI or r.extent > groups[bestI][cursor[bestI]].extent) then bestI = i end
		end
		if not bestI then break end
		local r = groups[bestI][cursor[bestI]]
		table.insert(chosen[bestI], r)
		used += 1
		tris += r.tris
		cursor[bestI] += 1
	end
	return chosen, {parts = used, triangles = tris}
end

------------------------------------------------------------------------------
-- The miniature (built once per chart; cached in the controller).
------------------------------------------------------------------------------
local function copyPart(src)
	local ok, c = pcall(function()
		if src:IsA("MeshPart") then
			local m = src:Clone()
			m:ClearAllChildren()
			return m
		end
		local p = Instance.new(src.ClassName)
		p.Size, p.CFrame, p.Color, p.Material = src.Size, src.CFrame, src.Color, src.Material
		p.Transparency, p.Reflectance = src.Transparency, src.Reflectance
		if src.ClassName == "Part" then p.Shape = src.Shape end
		return p
	end)
	if not ok or not c then return nil end
	c.Name = src.Name
	c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
	return c
end
MapArt.copyPart = copyPart
local function addPart(isle, c, tris)
	table.insert(isle.parts, c)
	table.insert(isle.base, c.CFrame)
	table.insert(isle.colors, c.Color)
	isle.triangles += tris
end
-- entries: island entries (MapArt.islands). Returns the scene: root Model,
-- islands[i] = {entry, model, parts, base, colors, triangles, locked, lift},
-- stats {parts, triangles, islands, builds}, forge queue.
function MapArt.buildScene(entries, budget, opts)
	opts = opts or {}
	local root = Instance.new("Model")
	root.Name = opts.name or "Miniature"
	local groups = {}
	for i, entry in ipairs(entries) do
		local records = {}
		for _, d in ipairs(entry.model:GetDescendants()) do
			local r = MapArt.classify(d, budget, opts.landmarks)
			if r then table.insert(records, r) end
		end
		groups[i] = records
	end
	local chosen = MapArt.plan(groups, budget)
	local scene = {root = root, islands = {}, queue = {}, budget = budget, stats = {parts = 0, triangles = 0, islands = #entries, forged = 0}}
	for i, entry in ipairs(entries) do
		local m = Instance.new("Model")
		m.Name = entry.name
		m.Parent = root
		local isle = {entry = entry, model = m, parts = {}, base = {}, colors = {}, triangles = 0, locked = false, lift = 0, index = i}
		for _, r in ipairs(chosen[i]) do
			if r.forgeOnly then
				table.insert(scene.queue, {isle = isle, host = r.part})
			else
				local c = copyPart(r.part)
				if c then
					c.Parent = m
					addPart(isle, c, r.tris)
					scene.stats.parts += 1
					scene.stats.triangles += r.tris
					if r.forge then table.insert(scene.queue, {isle = isle, host = r.part, stand = c, standTris = r.tris}) end
				end
			end
		end
		scene.islands[i] = isle
	end
	return scene
end
-- Swaps queued hosts for forged meshes. forge(host) -> MeshPart (unparented,
-- sized and placed like the world's) and its triangle count, or nil. Stops at
-- budget.forge requests or the triangle budget. Returns meshes added.
function MapArt.upgrade(scene, forge)
	local added = 0
	for _, job in ipairs(scene.queue) do
		if added >= scene.budget.forge then break end
		local ok, mesh, tris = pcall(forge, job.host)
		if ok and mesh then
			tris = tonumber(tris) or MapArt.TRIS.Mesh
			local isle = job.isle
			local net = tris - (job.standTris or 0)
			if scene.stats.triangles + net <= scene.budget.triangles and (job.stand or scene.stats.parts < scene.budget.parts) then
				mesh.Anchored, mesh.CanCollide, mesh.CanQuery, mesh.CanTouch, mesh.CastShadow = true, false, false, false, false
				mesh:SetAttribute("ShapeTriangles", tris)
				if job.stand then
					local at = table.find(isle.parts, job.stand)
					job.stand:Destroy()
					if at then
						isle.parts[at], isle.base[at], isle.colors[at] = mesh, mesh.CFrame, mesh.Color
						isle.triangles += net
					end
				else
					addPart(isle, mesh, tris)
					scene.stats.parts += 1
				end
				if isle.locked then mesh.Color = MapArt.lockTint(mesh.Color) end
				if isle.lift ~= 0 then mesh.CFrame += Vector3.new(0, isle.lift, 0) end
				mesh.Parent = isle.model
				scene.stats.triangles += net
				scene.stats.forged += 1
				added += 1
			else
				pcall(mesh.Destroy, mesh)
			end
		end
	end
	table.clear(scene.queue)
	return added
end
-- Locked wash: towards a cool grey of the same lightness, a touch darker.
function MapArt.lockTint(color)
	local l = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return color:Lerp(Color3.new(l * 0.78 + 0.04, l * 0.8 + 0.05, l * 0.86 + 0.08), 0.82)
end
function MapArt.setLocked(isle, locked)
	if isle.locked == locked then return false end
	isle.locked = locked
	for i, p in ipairs(isle.parts) do p.Color = if locked then MapArt.lockTint(isle.colors[i]) else isle.colors[i] end
	return true
end
-- Hover raise: the whole island lifts (studs); only on a hover change.
function MapArt.setLift(isle, lift)
	if isle.lift == lift then return false end
	isle.lift = lift
	local up = Vector3.new(0, lift, 0)
	for i, p in ipairs(isle.parts) do p.CFrame = isle.base[i] + up end
	return true
end

------------------------------------------------------------------------------
-- Camera and projection (pure). The ViewportFrame camera's FieldOfView is
-- vertical, as here.
------------------------------------------------------------------------------
function MapArt.cameraCFrame(focus, distance, pitch)
	local p = math.rad(pitch or MapArt.VIEW.pitch)
	local eye = focus + Vector3.new(0, math.sin(p), math.cos(p)) * distance
	return CFrame.lookAt(eye, focus)
end
-- World point → screen px in a w x h viewport, and depth (nil behind the camera).
function MapArt.project(cf, fov, w, h, pos)
	local rel = cf:PointToObjectSpace(pos)
	local depth = -rel.Z
	if depth <= 0.01 then return nil end
	local k = (h / 2) / math.tan(math.rad(fov) / 2)
	return w / 2 + rel.X / depth * k, h / 2 - rel.Y / depth * k, depth
end
-- Sample points that bound an island: rim at the meadow and the keel tip.
function MapArt.samples(entries)
	local pts = {}
	for _, e in ipairs(entries) do
		local c, r = e.center, e.radius
		for _, d in ipairs({Vector3.new(r, 0, 0), Vector3.new(-r, 0, 0), Vector3.new(0, 0, r), Vector3.new(0, 0, -r), Vector3.new(0, 18, 0)}) do
			table.insert(pts, c + d)
		end
		table.insert(pts, c - Vector3.new(0, math.clamp(r * 0.55 + 6, 10, 62) + 6, 0))
	end
	return pts
end
-- Focus and distance that fit every sample inside the frame (with a margin).
function MapArt.fitView(points, w, h, view)
	view = view or MapArt.VIEW
	if #points == 0 or w <= 0 or h <= 0 then return Vector3.zero, 1000 end
	local lo3, hi3 = points[1], points[1]
	for _, p in ipairs(points) do lo3, hi3 = lo3:Min(p), hi3:Max(p) end
	local focus = (lo3 + hi3) / 2
	local m = view.margin
	local function extents(f, d)
		local cf = MapArt.cameraCFrame(f, d, view.pitch)
		local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(points) do
			local x, y = MapArt.project(cf, view.fov, w, h, p)
			if not x then return nil end
			x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
		end
		return x0, x1, y0, y1, cf
	end
	local distance = 1000
	for _ = 1, 3 do
		local lo, hi = 20, 40000
		for _ = 1, 32 do
			local mid = (lo + hi) / 2
			local x0, x1, y0, y1 = extents(focus, mid)
			if x0 and x0 >= w * m and x1 <= w * (1 - m) and y0 >= h * m and y1 <= h * (1 - m) then hi = mid else lo = mid end
		end
		distance = hi
		local x0, x1, y0, y1, cf = extents(focus, distance)
		if not x0 then break end
		local wpp = 2 * distance * math.tan(math.rad(view.fov) / 2) / h
		focus += cf.RightVector * (((x0 + x1) / 2 - w / 2) * wpp) - cf.UpVector * (((y0 + y1) / 2 - h / 2) * wpp)
	end
	return focus, distance
end
-- Ellipse hit test: the island under (px, py) among laid-out links, or nil.
function MapArt.hitTest(links, px, py)
	local best, bestD
	for id, link in pairs(links) do
		if link.sx and link.sr and link.sr > 0 then
			local dx, dy = (px - link.sx) / link.sr, (py - link.sy) / (link.sr * 0.8)
			local d = dx * dx + dy * dy
			if d <= 1 and (not bestD or d < bestD) then best, bestD = id, d end
		end
	end
	return best
end

------------------------------------------------------------------------------
-- Sky Chart controller.
-- opts: sky (Frame), chart (the WarpMap frame), info (WarpInfo card), hint,
-- state (the HUD's S: tiles, pickWarp), regionState(region) -> unlocked, req,
-- Theme, Data, touch, workspace, player, Input, TweenService, forge (optional
-- function(host) -> MeshPart, tris).
------------------------------------------------------------------------------
local function make(class, parent, props)
	local o = Instance.new(class)
	if class == "UIStroke" then o.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end
local function circle(o) make("UICorner", o, {CornerRadius = UDim.new(0.5, 0)}) return o end
-- A cumulus puff: three overlapping soft circles and a flat shaded base.
local function cloud(parent, name, x, y, w, alpha, A)
	local holder = make("Frame", parent, {Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, w * 0.42),
		BackgroundTransparency = 1, ZIndex = 1})
	for i, p in ipairs({{0.3, 0.6, 0.5}, {0.55, 0.45, 0.62}, {0.78, 0.62, 0.44}}) do
		local f = circle(make("Frame", holder, {Name = "Puff" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(p[1], p[2]),
			Size = UDim2.fromScale(p[3], p[3] * 2.2), BackgroundColor3 = rgb(A.cloud), BackgroundTransparency = alpha, BorderSizePixel = 0, ZIndex = 1}))
		make("UIGradient", f, {Rotation = 90, Color = ColorSequence.new(rgb(A.cloud), rgb(A.cloudShade))})
	end
	local base = make("Frame", holder, {Name = "Base", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.54, 0.74), Size = UDim2.fromScale(0.86, 0.42),
		BackgroundColor3 = rgb(A.cloudShade), BackgroundTransparency = alpha, BorderSizePixel = 0, ZIndex = 1})
	make("UICorner", base, {CornerRadius = UDim.new(0.5, 0)})
	return holder
end

function MapArt.mountChart(opts)
	local Theme, Data = opts.Theme, opts.Data
	local A = Theme.MapArt
	local sky, S = opts.sky, opts.state
	local budget = MapArt.budget(opts.touch)
	local view = {pitch = MapArt.VIEW.pitch, fov = MapArt.VIEW.fov, margin = MapArt.VIEW.margin, zoom = 1, pan = Vector3.zero}
	local ctl = {sky = sky, view = view, budget = budget, links = {}, builds = 0, hover = nil, scene = nil}
	local tween = opts.TweenService
	local function loop(object, goal, seconds)
		if not tween then return end
		pcall(function()
			tween:Create(object, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), goal):Play()
		end)
	end

	-- Backdrop: a bright day sky (the old flat clouds are replaced).
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = sky:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, rgb(A.skyTop)), ColorSequenceKeypoint.new(0.55, rgb(A.skyMid)), ColorSequenceKeypoint.new(1, rgb(A.skyLow))})
	end
	for _, child in ipairs(sky:GetChildren()) do
		if string.sub(child.Name, 1, 5) == "Cloud" then child.Visible = false end
	end
	-- Scene (ZIndex 1, under the warp tiles): back clouds, the miniature, front haze.
	local scene = make("Frame", sky, {Name = "Scene", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1})
	local back = make("Frame", scene, {Name = "CloudsBack", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1})
	local BACK = {{0.12, 0.14, 0.26}, {0.84, 0.1, 0.22}, {0.5, 0.06, 0.18}, {0.95, 0.42, 0.2}, {0.04, 0.5, 0.2}, {0.32, 0.92, 0.3}, {0.72, 0.9, 0.28}, {0.6, 0.32, 0.14}, {0.2, 0.7, 0.16}}
	for i = 1, math.min(budget.clouds, #BACK) do
		local c = BACK[i]
		local puff = cloud(back, "Cloud" .. i, c[1], c[2], c[3], 0.18 + (i % 3) * 0.12, A)
		loop(puff, {Position = UDim2.fromScale(c[1] + (if i % 2 == 0 then 0.05 else -0.05), c[2])}, 38 + i * 7)
	end
	local viewport = make("ViewportFrame", scene, {Name = "Miniature", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2,
		Ambient = rgb(A.ambient), LightColor = rgb(A.sun), LightDirection = Vector3.new(A.sunDirection[1], A.sunDirection[2], A.sunDirection[3])})
	local camera = make("Camera", viewport, {Name = "ChartCamera", FieldOfView = view.fov})
	viewport.CurrentCamera = camera
	viewport:SetAttribute("MapArtScene", true)
	local front = make("Frame", scene, {Name = "CloudsFront", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3})
	local haze = make("Frame", front, {Name = "Haze", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.22),
		BackgroundColor3 = rgb(A.haze), BorderSizePixel = 0, ZIndex = 3})
	make("UIGradient", haze, {Rotation = 90, Transparency = NumberSequence.new(1, 0.55)})
	for i, c in ipairs({{0.08, 0.97, 0.34}, {0.9, 0.95, 0.3}, {0.5, 1.02, 0.4}}) do
		if i <= math.ceil(budget.clouds / 3) then
			local puff = cloud(front, "Wisp" .. i, c[1], c[2], c[3], 0.5, A)
			loop(puff, {Position = UDim2.fromScale(c[1] + 0.04, c[2])}, 52 + i * 9)
		end
	end
	-- Hover halo (an ellipse ring under the hovered island's overlay).
	local halo = circle(make("Frame", sky, {Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = rgb(A.halo), BackgroundTransparency = 0.86,
		BorderSizePixel = 0, Visible = false, ZIndex = 2}))
	make("UIStroke", halo, {Color = rgb(A.halo), Thickness = 2, Transparency = 0.15})
	-- Input layer: drag to pan, wheel / pinch to zoom, click / tap an island.
	local drag = make("TextButton", sky, {Name = "ChartDrag", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ZIndex = 1, Selectable = false})
	-- Hover caption (requirement / travel hint).
	local caption = make("TextLabel", sky, {Name = "HoverCaption", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Theme.color.void, BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(200, 20), Font = Theme.font.label, TextSize = 12, TextColor3 = Theme.color.text, RichText = true, Visible = false, ZIndex = 9})
	make("UICorner", caption, {CornerRadius = UDim.new(0, 4)})
	-- The player's marker: a mint ring with a pointer and "YOU".
	local you = make("Frame", sky, {Name = "YouMarker", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = rgb(A.you),
		BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false, ZIndex = 8})
	circle(you)
	make("UIStroke", you, {Color = rgb(A.youInk), Thickness = 2})
	make("TextLabel", you, {Name = "Tag", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(40, 12), BackgroundTransparency = 1,
		Text = "YOU", Font = Theme.font.display, TextSize = 8, TextColor3 = rgb(A.you), TextStrokeTransparency = 0, TextStrokeColor3 = rgb(A.youInk), ZIndex = 8})
	loop(you, {Size = UDim2.fromOffset(22, 22)}, 0.9)

	-- Insets for the instanced isles.
	local function inset(name, title, slot)
		local f = make("Frame", sky, {Name = name, AnchorPoint = Vector2.new(1, 1), BackgroundColor3 = rgb(A.insetBack), BackgroundTransparency = 0.35,
			BorderSizePixel = 0, Visible = false, ZIndex = 2})
		make("UICorner", f, {CornerRadius = UDim.new(0, 8)})
		make("UIStroke", f, {Color = rgb(A.insetFrame), Thickness = 1.5, Transparency = 0.3})
		local vp = make("ViewportFrame", f, {Name = "Miniature", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2,
			Ambient = rgb(A.ambient), LightColor = rgb(A.sun), LightDirection = Vector3.new(A.sunDirection[1], A.sunDirection[2], A.sunDirection[3])})
		local cam = make("Camera", vp, {Name = "InsetCamera", FieldOfView = view.fov})
		vp.CurrentCamera = cam
		vp:SetAttribute("MapArtScene", true)
		local label = make("TextLabel", f, {Name = "Title", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -6, 0, 16),
			BackgroundTransparency = 1, Text = title, Font = A.labelFont, TextSize = A.labelSizeCompact, TextColor3 = rgb(A.labelInk),
			TextStrokeTransparency = 0, TextStrokeColor3 = rgb(A.labelOutline), ZIndex = 6})
		return {frame = f, viewport = vp, camera = cam, label = label, slot = slot}
	end
	local insets = {home = inset("HomeInset", "YOUR ISLE", 0), crew = inset("CrewInset", "CREW HAVEN", 1)}
	local crewWarp = make("TextButton", insets.crew.frame, {Name = "Warp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(if opts.touch then 44 else 30, if opts.touch then 44 else 30), BackgroundColor3 = rgb(A.warp), Text = "✦", Font = Theme.font.heading,
		TextSize = 15, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true, ZIndex = 6})
	circle(crewWarp)
	make("UIStroke", crewWarp, {Color = rgb(A.warpHi), Thickness = 2})
	crewWarp.Activated:Connect(function() S.pickWarp(MapArt.CREW, insets.crew.frame) end)

	-- Restyle a HUD tile once: drawn island art hidden, a glowing gem with a
	-- light pillar and ground pad, a bold outlined name.
	local function style(t)
		if t.frame:GetAttribute("MapArt") then return end
		t.frame:SetAttribute("MapArt", true)
		for _, child in ipairs(t.frame:GetChildren()) do
			local n = child.Name
			if n == "Rock" or n == "Top" or string.sub(n, 1, 5) == "Spike" or string.sub(n, 1, 4) == "Tuft" then child.Visible = false end
		end
		t.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		t.frame.BackgroundTransparency = 1
		local glow = {}
		for i, g in ipairs({{2.4, 0.82}, {1.6, 0.6}}) do
			glow[i] = circle(make("Frame", t.frame, {Name = "Glow" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36),
				Size = UDim2.fromOffset(32 * g[1], 32 * g[1]), BackgroundColor3 = rgb(A.warpGlow), BackgroundTransparency = g[2], BorderSizePixel = 0, ZIndex = 4}))
		end
		loop(glow[1], {BackgroundTransparency = 0.92}, 1.4)
		local pillar = make("Frame", t.frame, {Name = "Pillar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(3, 22),
			BackgroundColor3 = rgb(A.warpPad), BorderSizePixel = 0, ZIndex = 4})
		make("UIGradient", pillar, {Rotation = 90, Transparency = NumberSequence.new(0.1, 0.85)})
		local pad = circle(make("Frame", t.frame, {Name = "Pad", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 22), Size = UDim2.fromOffset(22, 8),
			BackgroundColor3 = rgb(A.warpPad), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4}))
		t.glow, t.pillar, t.pad = glow, pillar, pad
		t.warp.Position = UDim2.fromScale(0.5, 0.36)
		t.warp.BackgroundColor3 = rgb(A.warp)
		local g = t.warp:FindFirstChildOfClass("UIGradient")
		if g then g.Color = ColorSequence.new(rgb(A.warpHi), rgb(A.warp)) end
		t.lock.Position = UDim2.fromScale(0.5, 0.36)
		t.name.AnchorPoint, t.name.Position, t.name.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.36, 28), UDim2.fromOffset(240, 20)
		t.name.Font = A.labelFont
		t.name.TextColor3, t.name.TextStrokeColor3, t.name.TextStrokeTransparency = rgb(A.labelInk), rgb(A.labelOutline), 0
		make("UIStroke", t.name, {Name = "Outline", ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Color = rgb(A.labelOutline), Thickness = 2})
		t.here.Position = UDim2.new(0.5, 0, 0.36, -22)
		-- Hover from the gem itself (desktop).
		pcall(function()
			t.warp.MouseEnter:Connect(function() ctl.setHover(t.island.id) end)
			t.warp.MouseLeave:Connect(function() ctl.setHover(nil) end)
		end)
	end

	-- Builds the miniature once (first refresh with islands in the world).
	local function islandsFolder()
		local ok, folder = pcall(function() return opts.workspace:FindFirstChild("Islands") end)
		return if ok then folder else nil
	end
	local function archipelago()
		local ok, folder = pcall(function() return opts.workspace:FindFirstChild("AetherIsles") end)
		return if ok then folder else nil
	end
	local landmarkShapes = MapArt.landmarks(Data)
	function ctl.build()
		if ctl.scene then return ctl.scene end
		local entries = MapArt.islands(islandsFolder())
		if #entries == 0 then return nil end
		local matched = MapArt.matchTiles(Theme.WorldMap, entries)
		local built = MapArt.buildScene(entries, budget, {landmarks = landmarkShapes})
		built.root.Parent = viewport
		ctl.builds += 1
		ctl.scene, ctl.entries, ctl.samples = built, entries, MapArt.samples(entries)
		local isleOf = {}
		for _, isle in ipairs(built.islands) do isleOf[isle.entry] = isle end
		for _, tile in ipairs(Theme.WorldMap.islands) do
			local e = matched[tile.id]
			if e then
				local warp, source = MapArt.warpPoint(tile, e, Data)
				ctl.links[tile.id] = {tile = tile, entry = e, isle = isleOf[e], warp = warp, source = source}
			end
		end
		if opts.forge then
			task.spawn(function() MapArt.upgrade(built, opts.forge) end)
		end
		return built
	end
	-- An inset's island: the home (WayfarersRest_<UserId>) or the crew haven
	-- (CrewHaven_* with the player's CoopId). Built once per model.
	local function insetModel(kind)
		local folder = archipelago()
		if not folder or not opts.player then return nil end
		if kind == "home" then return folder:FindFirstChild("WayfarersRest_" .. tostring(opts.player.UserId)) end
		local id = opts.player:GetAttribute("CoopId")
		if id == nil then return nil end
		for _, m in ipairs(folder:GetChildren()) do
			if string.sub(m.Name, 1, 10) == "CrewHaven_" and m:GetAttribute("CoopId") == id then return m end
		end
		return nil
	end
	local insetBudget = {parts = budget.insetParts, triangles = math.floor(budget.triangles / 6), minExtent = budget.minExtent, floor = budget.insetParts, forge = 0}
	local function buildInset(kind)
		local box = insets[kind]
		local model = insetModel(kind)
		if model == box.model then return box.scene ~= nil end
		if box.scene then box.scene.root:Destroy() box.scene = nil end
		box.model = model
		if not model then return false end
		local center = model:GetAttribute("IslandCenter")
		local entry = {model = model, name = model.Name, center = if typeof(center) == "Vector3" then center else model:GetPivot().Position,
			radius = tonumber(model:GetAttribute("IslandRadius")) or 60}
		box.scene = MapArt.buildScene({entry}, insetBudget, {name = "Inset"})
		box.scene.root.Parent = box.viewport
		box.samples = MapArt.samples({entry})
		box.fitKey = nil
		return true
	end

	local function setVisible(o, v) if o.Visible ~= v then o.Visible = v end end
	-- Lays out camera and overlay for the current view (on refresh, pan, zoom).
	function ctl.layout()
		local size = sky.AbsoluteSize
		local w, h = size.X, size.Y
		if not ctl.scene or w <= 0 or h <= 0 then return end
		local key = w .. "x" .. h
		if ctl.fitKey ~= key then
			ctl.fitKey = key
			ctl.fitFocus, ctl.fitDistance = MapArt.fitView(ctl.samples, w, h, view)
			-- Phones open closer, on the hub (the whole sky is a pinch away).
			if opts.touch and not ctl.framed and ctl.links.Hub then
				ctl.framed = true
				view.zoom = MapArt.VIEW.phoneZoom
				local fitCf = MapArt.cameraCFrame(ctl.fitFocus, ctl.fitDistance, view.pitch)
				local d = ctl.links.Hub.entry.center - ctl.fitFocus
				view.pan = fitCf.RightVector * d:Dot(fitCf.RightVector) + fitCf.UpVector * d:Dot(fitCf.UpVector)
			end
		end
		local focus = ctl.fitFocus + view.pan
		local cf = MapArt.cameraCFrame(focus, ctl.fitDistance * view.zoom, view.pitch)
		camera.CFrame, camera.FieldOfView = cf, view.fov
		ctl.cf, ctl.w, ctl.h = cf, w, h
		local touch = opts.touch
		for id, t in pairs(S.tiles) do
			local link = ctl.links[id]
			if link then
				style(t)
				local lift = if link.isle then link.isle.lift else 0
				-- The gem stays put while its island lifts (no hover flicker under the cursor).
				local x, y = MapArt.project(cf, view.fov, w, h, link.warp)
				local cx, cy = MapArt.project(cf, view.fov, w, h, link.entry.center + Vector3.new(0, lift, 0))
				if x and cx then
					local ex = MapArt.project(cf, view.fov, w, h, link.entry.center + cf.RightVector * link.entry.radius)
					link.sx, link.sy, link.sr = cx, cy, if ex then math.abs(ex - cx) else 0
					link.x, link.y = x, y
					t.frame.Size = UDim2.fromOffset(240, 80)
					t.frame.Position = UDim2.fromOffset(x, y - 8)
					setVisible(t.frame, x > -60 and x < w + 60 and y > -60 and y < h + 60)
					t.name.TextSize = if touch then A.labelSizeCompact else A.labelSize
					-- Names near the chart's edge slide inwards (pixel face ≈ 1 em per glyph).
					local half = #t.name.Text * t.name.TextSize / 2
					local shift = math.clamp(0, 6 + half - x, math.max(6 + half - x, w - 6 - half - x))
					t.name.Position = UDim2.new(0.5, math.floor(shift), 0.36, 28)
					setVisible(t.here, false) -- the YOU marker replaces the text tag
					local shown = t.warp.Visible
					for _, g in ipairs(t.glow) do setVisible(g, shown) end
					setVisible(t.pillar, shown)
					setVisible(t.pad, shown)
				end
			end
		end
		-- Instanced isles: insets bottom-left, the HUD's Home tile over its inset.
		local insetH = math.floor(math.clamp(h * 0.22, 58, 118))
		local insetW = math.floor(insetH * 1.42)
		local slot = 0
		for kind, box in pairs({home = insets.home, crew = insets.crew}) do
			local has = buildInset(kind)
			setVisible(box.frame, has)
			if has then
				local index = if kind == "home" then 0 else 1
				slot += 1
				box.frame.Size = UDim2.fromOffset(insetW, insetH)
				box.label.Text = if insetW >= 130 then (if kind == "home" then "YOUR ISLE" else "CREW HAVEN") else (if kind == "home" then "HOME" else "CREW")
				box.frame.Position = UDim2.new(1, -8 - index * (insetW + 8), 1, -8)
				if box.fitKey ~= key .. insetW then
					box.fitKey = key .. insetW
					local f, d = MapArt.fitView(box.samples, insetW, insetH - 14, {pitch = view.pitch, fov = view.fov, margin = 0.1})
					box.camera.CFrame = MapArt.cameraCFrame(f, d, view.pitch)
				end
			end
		end
		local home = S.tiles.Home
		if home then
			if insets.home.frame.Visible then
				style(home)
				home.frame.Size = UDim2.fromOffset(insetW + 40, 80)
				home.frame.Position = UDim2.new(1, -8 - insetW / 2, 1, -8 - insetH * 0.55)
				home.name.Visible = false
			end
		end
		ctl.placeYou()
		ctl.placeHalo()
	end
	-- The player's marker (archipelago, or the home inset while at home).
	function ctl.placeYou()
		local root = opts.player and opts.player.Character and opts.player.Character:FindFirstChild("HumanoidRootPart")
		local region = opts.player and opts.player:GetAttribute("IsleRegionHere")
		if region == "Home" and insets.home.frame.Visible then
			you.Position = UDim2.new(1, insets.home.frame.Position.X.Offset - insets.home.frame.Size.X.Offset / 2, 1, -8 - insets.home.frame.Size.Y.Offset * 0.3)
			setVisible(you, true)
			return
		end
		if not root or not ctl.cf then setVisible(you, false) return end
		local x, y = MapArt.project(ctl.cf, view.fov, ctl.w, ctl.h, root.CFrame.Position)
		setVisible(you, x ~= nil and x >= 0 and x <= ctl.w and y >= 0 and y <= ctl.h)
		if x then you.Position = UDim2.fromOffset(x, y) end
	end
	function ctl.placeHalo()
		local link = ctl.hover and ctl.links[ctl.hover]
		if not link or not link.sx then setVisible(halo, false) setVisible(caption, false) return end
		halo.Position = UDim2.fromOffset(link.sx, link.sy)
		halo.Size = UDim2.fromOffset(link.sr * 2.1, link.sr * 1.3)
		setVisible(halo, true)
		local unlocked, requirement = opts.regionState(link.tile.region)
		caption.Text = if unlocked then (if link.tile.travel == "recall" then "Click to travel" else "Click for a guided route")
			else "<font color=\"#" .. A.lockChip .. "\">🔒 Locked</font> · " .. Theme.escape(if requirement ~= "" then requirement else "Not charted yet")
		caption.Position = UDim2.fromOffset(link.x or link.sx, (link.y or link.sy) + 44)
		setVisible(caption, true)
	end
	function ctl.setHover(id)
		if ctl.hover == id then return end
		local old = ctl.hover and ctl.links[ctl.hover]
		if old and old.isle then MapArt.setLift(old.isle, 0) end
		ctl.hover = id
		local link = id and ctl.links[id]
		if link and link.isle then MapArt.setLift(link.isle, math.clamp(link.entry.radius * 0.07, 3, 8)) end
		ctl.layout()
	end
	-- Lock wash follows the HUD's region state (only on a change).
	function ctl.applyLocks()
		for _, link in pairs(ctl.links) do
			if link.isle then MapArt.setLocked(link.isle, not (opts.regionState(link.tile.region))) end
		end
	end
	-- Called at the end of the HUD's refreshChart (open, snapshot, resize).
	function ctl.refresh()
		if not ctl.build() then return false end
		if opts.hint then opts.hint.Text = if opts.touch then "Drag to pan · pinch to zoom · tap a warp point" else "Drag to pan · scroll to zoom · click a warp point to travel" end
		ctl.applyLocks()
		ctl.layout()
		return true
	end
	-- The info card sits beside the picked island's warp point.
	function ctl.placeInfo(island)
		local info = opts.info
		if not info or not ctl.w then return end
		local x, y
		if island == MapArt.CREW or island.id == "Home" then
			local box = if island.id == "Home" then insets.home else insets.crew
			if not box.frame.Visible then return end
			x, y = ctl.w + box.frame.Position.X.Offset - box.frame.Size.X.Offset + 22, ctl.h - box.frame.Size.Y.Offset / 2
		else
			local link = ctl.links[island.id]
			if not link or not link.x then return end
			x, y = link.x, link.y
		end
		local right = x > ctl.w * 0.6
		local offset = sky.Position
		info.AnchorPoint = Vector2.new(if right then 1 else 0, 0.5)
		info.Position = UDim2.fromOffset(offset.X.Offset + x + (if right then -26 else 26), offset.Y.Offset + math.clamp(y, 50, ctl.h - 50))
	end
	local basePick = S.pickWarp
	S.pickWarp = function(island, frame)
		basePick(island, frame)
		if ctl.scene then ctl.placeInfo(island) end
	end

	-- Input: pan, zoom, click / tap.
	local Input = opts.Input
	local press
	local function pan(dx, dy)
		if not ctl.cf then return end
		local wpp = 2 * ctl.fitDistance * view.zoom * math.tan(math.rad(view.fov) / 2) / ctl.h
		local p = view.pan - ctl.cf.RightVector * (dx * wpp) + ctl.cf.UpVector * (dy * wpp)
		local limit = ctl.fitDistance * 0.35
		view.pan = Vector3.new(math.clamp(p.X, -limit, limit), math.clamp(p.Y, -limit, limit), math.clamp(p.Z, -limit, limit))
		ctl.layout()
	end
	function ctl.zoom(factor)
		local z = math.clamp(view.zoom * factor, MapArt.VIEW.minZoom, MapArt.VIEW.maxZoom)
		if z == view.zoom then return end
		view.zoom = z
		if z >= MapArt.VIEW.maxZoom then view.pan = Vector3.zero end
		ctl.layout()
	end
	function ctl.click(px, py)
		local id = MapArt.hitTest(ctl.links, px, py)
		if not id then return nil end
		local link = ctl.links[id]
		local t = S.tiles[id]
		S.pickWarp(link.tile, t and t.frame)
		return id
	end
	drag.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			press = {x = input.Position.X, y = input.Position.Y, moved = 0}
		end
	end)
	drag.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then ctl.zoom(if input.Position.Z > 0 then MapArt.VIEW.zoomStep else 1 / MapArt.VIEW.zoomStep) end
	end)
	pcall(function()
		drag.MouseMoved:Connect(function(x, y)
			if press or not ctl.scene then return end
			local origin = sky.AbsolutePosition
			ctl.setHover(MapArt.hitTest(ctl.links, x - origin.X, y - origin.Y))
		end)
		drag.MouseLeave:Connect(function() if not press then ctl.setHover(nil) end end)
	end)
	if Input then
		Input.InputChanged:Connect(function(input)
			if not press then return end
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
				local dx, dy = input.Position.X - press.x, input.Position.Y - press.y
				press.x, press.y = input.Position.X, input.Position.Y
				press.moved += math.abs(dx) + math.abs(dy)
				if press.moved > 6 then pan(dx, dy) end
			end
		end)
		Input.InputEnded:Connect(function(input)
			local kind = input.UserInputType
			if press and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
				local was = press
				press = nil
				if was.moved <= 6 then
					local origin = sky.AbsolutePosition
					ctl.click(input.Position.X - origin.X, input.Position.Y - origin.Y)
				end
			end
		end)
		pcall(function()
			local start
			Input.TouchPinch:Connect(function(_, scale, _, state)
				if not opts.chart.Visible then return end
				if state == Enum.UserInputState.Begin then start = view.zoom
				elseif start and scale > 0 then ctl.zoom((start / scale) / view.zoom) end
			end)
		end)
	end
	-- While the chart is open the player marker follows at 2 Hz.
	local ticking = false
	local function tick()
		if not opts.chart.Visible then ticking = false return end
		ctl.placeYou()
		task.delay(0.5, tick)
	end
	pcall(function()
		opts.chart:GetPropertyChangedSignal("Visible"):Connect(function()
			if opts.chart.Visible and not ticking then ticking = true task.delay(0.5, tick) end
			if not opts.chart.Visible then press = nil ctl.setHover(nil) end
		end)
	end)
	return ctl
end

------------------------------------------------------------------------------
-- Minimap plates (top-down island art) and marker styling.
------------------------------------------------------------------------------
local WATER_WORDS = {"water", "lagoon", "pool", "skylake", "spring"}
local CANOPY = {Canopy = true, ["Pine crown"] = true, ["Pine boughs"] = true, ["Palm fronds"] = true}
local function isWater(part)
	if part.Material == Enum.Material.Water then return true end
	local n = string.lower(part.Name)
	if string.find(n, "bank", 1, true) or string.find(n, "bed", 1, true) then return false end
	for _, w in ipairs(WATER_WORDS) do if string.find(n, w, 1, true) then return true end end
	return false
end
local function cylinderish(part)
	local ok, shape = pcall(function() return part.Shape end)
	return ok and shape == Enum.PartType.Cylinder
end
-- Plate spec for one island (pure apart from reads): a list of shapes in plate
-- units (0..1 of a square of side 2R centred on the island, R = radius * 1.3).
-- kind "disc" | "rect" | "icon"; u, v centre; w, h; rot; color; z; alpha; stroke.
function MapArt.plateSpec(entry, Data, Theme, cap)
	local A = Theme.MapArt
	local R = entry.radius * 1.3
	local c = entry.center
	local function uv(p) return 0.5 + (p.X - c.X) / (2 * R), 0.5 + (p.Z - c.Z) / (2 * R) end
	local RA = Data and Data.RegionArt
	local art = RA and RA.Regions and RA.Regions[entry.region or ""]
	local ground = art and rgb(art.palette[1])
	local accent = art and rgb(art.palette[2])
	local landmark = art and art.landmark
	local meadow, foundation
	local tiers, water, paths, roofs, icons, canopy = {}, {}, {}, {}, {}, {}
	for _, d in ipairs(entry.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 or (d:IsA("BasePart") and d:GetAttribute("Shape") ~= nil) then
			local name = d.Name
			if name == "Meadow" and not meadow then meadow = d
			elseif name == "Floating foundation" and not foundation then foundation = d
			elseif name == "Upper meadow" then table.insert(tiers, d)
			elseif isWater(d) then table.insert(water, d)
			elseif name == "Path" or name == "Ramp" or name == "Continuous bridge deck" then table.insert(paths, d)
			elseif string.find(string.lower(name), "roof", 1, true) then table.insert(roofs, d)
			elseif CANOPY[name] then table.insert(canopy, d)
			elseif name == "Warp beacon" then table.insert(icons, {part = d, glyph = "✦", color = rgb(A.beacon)})
			elseif landmark and landmark.isle == entry.model.Name and d:GetAttribute("Shape") == landmark.shape then
				table.insert(icons, 1, {part = d, glyph = "★", color = rgb(A.landmark)})
			end
		end
	end
	local spec = {}
	local function add(s) if #spec < cap then table.insert(spec, s) end end
	local mr = if meadow then math.max(meadow.Size.Y, meadow.Size.Z) / 2 else entry.radius
	local top = if meadow then meadow.Color else (ground or rgb("8DB86E"))
	if ground then top = top:Lerp(ground, 0.35) end
	local stone = if foundation then foundation.Color else rgb(A.rim)
	add({kind = "disc", u = 0.52, v = 0.55, w = mr / R, h = mr / R, color = rgb(A.shadow), alpha = 0.45, z = 1})
	add({kind = "disc", u = 0.5, v = 0.5, w = (mr + 1.2) / R, h = (mr + 1.2) / R, color = stone, alpha = 0, z = 2, stroke = Theme.darken(stone, 0.5)})
	add({kind = "disc", u = 0.5, v = 0.5, w = mr / R, h = mr / R, color = top, alpha = 0, z = 3, gradient = true})
	-- Icons first (they must survive the cap), then terrain detail by size.
	for _, icon in ipairs(icons) do
		local u, v = uv(posOf(icon.part))
		add({kind = "icon", u = u, v = v, glyph = icon.glyph, color = icon.color, z = 9})
	end
	table.sort(tiers, function(a, b) return posOf(a).Y < posOf(b).Y end)
	for _, t in ipairs(tiers) do
		local u, v = uv(posOf(t))
		local r = math.max(t.Size.Y, t.Size.Z) / 2 / R
		add({kind = "disc", u = u, v = v, w = r, h = r, color = Theme.lighten(t.Color:Lerp(ground or t.Color, 0.3), 0.12), alpha = 0, z = 4, stroke = Theme.darken(t.Color, 0.45)})
	end
	for _, wpart in ipairs(water) do
		local u, v = uv(posOf(wpart))
		local col = rgb(A.water):Lerp(wpart.Color, 0.25)
		if cylinderish(wpart) then
			local r = math.max(wpart.Size.Y, wpart.Size.Z) / 2 / R
			add({kind = "disc", u = u, v = v, w = r, h = r, color = col, alpha = 0, z = 5, stroke = rgb(A.waterDeep)})
		else
			local rv = wpart.CFrame.RightVector
			add({kind = "rect", u = u, v = v, w = wpart.Size.X / (2 * R), h = wpart.Size.Z / (2 * R), rot = math.deg(math.atan2(rv.Z, rv.X)), color = col, alpha = 0, z = 5})
		end
	end
	for _, p in ipairs(paths) do
		local u, v = uv(posOf(p))
		local rv = p.CFrame.RightVector
		local col = if p.Name == "Continuous bridge deck" then rgb(A.bridge) else rgb(A.path):Lerp(p.Color, 0.35)
		add({kind = "rect", u = u, v = v, w = p.Size.X / (2 * R), h = p.Size.Z / (2 * R), rot = math.deg(math.atan2(rv.Z, rv.X)), color = col, alpha = 0, z = 6})
	end
	for _, r in ipairs(roofs) do
		local u, v = uv(posOf(r))
		local rv = r.CFrame.RightVector
		add({kind = "rect", u = u, v = v, w = r.Size.X / (2 * R), h = r.Size.Z / (2 * R), rot = math.deg(math.atan2(rv.Z, rv.X)), color = r.Color, alpha = 0, z = 7})
	end
	for _, leaf in ipairs(canopy) do
		local u, v = uv(posOf(leaf))
		local r = math.max(leaf.Size.X, leaf.Size.Z) * 0.45 / R
		add({kind = "disc", u = u, v = v, w = r, h = r, color = Theme.darken(leaf.Color, 0.12), alpha = 0.05, z = 8})
	end
	return spec, {accent = accent, ground = ground}
end
function MapArt.mountMinimap(opts)
	local Theme, Data = opts.Theme, opts.Data
	local A = Theme.MapArt
	local budget = MapArt.budget(opts.touch)
	local art = {plates = {}, budget = budget, built = 0}
	local holder = make("Frame", opts.layer, {Name = "IslandArt", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1})
	local map = opts.layer.Parent
	if map then
		map.BackgroundColor3 = rgb(A.sea)
		local g = map:FindFirstChildOfClass("UIGradient")
		if g then g.Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(A.seaLow):Lerp(Color3.new(1, 1, 1), 0.55)) end
	end
	local quest = {}
	for _, q in ipairs(Data and Data.Quests or {}) do if type(q) == "table" and q.giver then quest[q.giver] = true end end
	quest.Guide = true
	art.questGivers = quest
	local function build(entry)
		local plate = make("Frame", holder, {Name = "Plate_" .. entry.model.Name, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 1})
		local spec = MapArt.plateSpec(entry, Data, Theme, budget.plate)
		for i, s in ipairs(spec) do
			local f
			if s.kind == "icon" then
				f = make("TextLabel", plate, {Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(s.u, s.v), Size = UDim2.fromOffset(12, 12),
					BackgroundTransparency = 1, Text = s.glyph, Font = Enum.Font.BuilderSansBold, TextSize = 12, TextColor3 = s.color, TextStrokeTransparency = 0.2,
					TextStrokeColor3 = rgb(A.shadow), ZIndex = s.z})
			else
				f = make("Frame", plate, {Name = if s.kind == "disc" then "Disc" .. i else "Strip" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(s.u, s.v),
					Size = UDim2.fromScale(s.w, s.h), Rotation = s.rot or 0,
					BackgroundColor3 = s.color, BackgroundTransparency = s.alpha or 0, BorderSizePixel = 0, ZIndex = s.z})
				if s.kind == "disc" then circle(f) else make("UICorner", f, {CornerRadius = UDim.new(0, 1)}) end
				if s.stroke then make("UIStroke", f, {Color = s.stroke, Thickness = 1, Transparency = 0.25}) end
				if s.gradient then make("UIGradient", f, {Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.78, 0.8, 0.78))}) end
			end
		end
		art.built += 1
		return {frame = plate, entry = entry, shapes = #spec, gen = 0}
	end
	local gen = 0
	-- Each minimap tick (≤ 10 Hz): place the cached plates; build unseen ones.
	function art.draw(me, scale, half, list)
		gen += 1
		for _, entry in ipairs(list) do
			local plate = art.plates[entry.model]
			if not plate then plate = build(entry) art.plates[entry.model] = plate end
			plate.gen = gen
			local x, y = (entry.center.X - me.X) * scale, (entry.center.Z - me.Z) * scale
			local r = entry.radius * 1.3 * scale
			local show = math.abs(x) <= half + r and math.abs(y) <= half + r
			if plate.frame.Visible ~= show then plate.frame.Visible = show end
			if show then
				plate.frame.Position = UDim2.fromOffset(half + x, half + y)
				plate.frame.Size = UDim2.fromOffset(r * 2, r * 2)
			end
		end
		for model, plate in pairs(art.plates) do
			if plate.gen ~= gen then plate.frame:Destroy() art.plates[model] = nil end
		end
	end
	-- The Wayfinder's island marker keeps only its label over the plate.
	function art.dress(f)
		if f:GetAttribute("MapArt") then return end
		f:SetAttribute("MapArt", true)
		f.BackgroundTransparency = 1
		local stroke = f:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 1 end
		local label = f:FindFirstChild("Label")
		if label then label.TextStrokeTransparency, label.TextStrokeColor3 = 0, rgb(A.labelOutline) end
	end
	-- Marker styling at creation: townsfolk pins (quest givers "!"), warp gems, station tiles.
	function art.styleMarker(f, kind, key)
		if kind == "npc" then
			f.Size = UDim2.fromOffset(9, 9)
			f.BackgroundColor3 = rgb(A.npc)
			local role = typeof(key) == "Instance" and key:GetAttribute("TownsfolkRole")
			if role and quest[role] then
				f.Size = UDim2.fromOffset(12, 12)
				f.BackgroundColor3 = rgb(A.quest)
				make("TextLabel", f, {Name = "Quest", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "!", Font = Enum.Font.BuilderSansExtraBold,
					TextSize = 11, TextColor3 = rgb(A.shadow), ZIndex = f.ZIndex})
			end
		elseif kind == "warp" then
			f.Size = UDim2.fromOffset(9, 9)
			f.Rotation = 45
			f.BackgroundColor3 = rgb(A.beacon)
			local corner = f:FindFirstChildOfClass("UICorner")
			if corner then corner.CornerRadius = UDim.new(0, 2) end
			make("UIStroke", f, {Name = "Glow", Color = rgb(A.warpHi), Thickness = 1.5, Transparency = 0.2})
		elseif kind == "station" then
			f.Size = UDim2.fromOffset(8, 8)
			f.BackgroundColor3 = rgb(A.station)
			local corner = f:FindFirstChildOfClass("UICorner")
			if corner then corner.CornerRadius = UDim.new(0, 2) end
		end
	end
	return art
end

return MapArt
