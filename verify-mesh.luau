-- Mesh team verification: catalog integrity and the client MeshForge (forge.client.lua)
-- against a mocked AssetService. Run from the project root: lune run verify-mesh.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Instance = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Instance

local checks = 0
local function check(condition, message)
	checks += 1
	if not condition then error("FAILED: " .. message, 2) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
local function nearV(a, b, eps) return near(a.X, b.X, eps) and near(a.Y, b.Y, eps) and near(a.Z, b.Z, eps) end

local World = luau.load(fs.readFile("art/WorldCatalog.lua"), {injectGlobals = true})()
local Props = luau.load(fs.readFile("art/PropCatalog.lua"), {injectGlobals = true})()

------------------------------------------------------------------------------
-- Catalog integrity
------------------------------------------------------------------------------
check(#World.palette == #Props.palette, "world and UI catalogs share one palette")
for i, hex in ipairs(World.palette) do check(Props.palette[i] == hex and #hex == 6, "palette entry " .. i) end
check(World.tintIndex == Props.tintIndex and World.tintDarkIndex and World.tintLightIndex, "tint slots declared")
for name in pairs(World.shapes) do check(Props.shapes[name] == nil, name .. " has a unique name across catalogs") end

local function pointsOf(data)
	local points = {}
	for i, xyz in ipairs(data.vertices) do
		check(#xyz == 3 and xyz[1] == xyz[1] and xyz[2] == xyz[2] and xyz[3] == xyz[3], "finite vertex")
		points[i] = Vector3.new(xyz[1], xyz[2], xyz[3])
	end
	return points
end
-- Signed volume per connected component (union-find on shared vertices).
local function componentVolumes(data, points)
	local parent = {}
	for i in ipairs(points) do parent[i] = i end
	local function find(i)
		while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
		return i
	end
	for _, f in ipairs(data.faces) do parent[find(f[2])] = find(f[1]); parent[find(f[3])] = find(f[1]) end
	local groups = {}
	for _, f in ipairs(data.faces) do
		local root = find(f[1])
		groups[root] = groups[root] or {}
		table.insert(groups[root], f)
	end
	local volumes = {}
	for _, list in pairs(groups) do
		local seen, centre, count = {}, Vector3.new(0, 0, 0), 0
		for _, f in ipairs(list) do for k = 1, 3 do if not seen[f[k]] then seen[f[k]] = true; centre += points[f[k]]; count += 1 end end end
		centre /= count
		local vol = 0
		for _, f in ipairs(list) do
			local a, b, c = points[f[1]] - centre, points[f[2]] - centre, points[f[3]] - centre
			vol += a:Dot(b:Cross(c)) / 6
		end
		table.insert(volumes, vol)
	end
	return volumes
end
local function validate(name, data, minTris, maxTris)
	local points = pointsOf(data)
	check(#data.faces >= minTris and #data.faces <= maxTris, name .. " triangle budget " .. #data.faces .. " within " .. minTris .. "-" .. maxTris)
	for _, f in ipairs(data.faces) do
		check(#f == 4, name .. " face shape")
		for k = 1, 3 do check(math.floor(f[k]) == f[k] and f[k] >= 1 and f[k] <= #points, name .. " valid vertex index") end
		check(World.palette[f[4]] ~= nil, name .. " valid palette index")
		check((points[f[2]] - points[f[1]]):Cross(points[f[3]] - points[f[1]]).Magnitude > 1e-6, name .. " nondegenerate triangle")
	end
	return points
end

local SIGNS = {Signboard = true, SignboardPosted = true, SignPost = true, Banner = true}
local required = {"WindpineTree", "EmberoakTree", "GlimmerbarkTree", "StarwoodTree", "AetherheartTree", "MeadowTree",
	"Boulder", "RockCluster", "CliffPiece", "OreVein1", "OreVein2", "OreVein3", "OreVein4", "CropWheat", "CropGlowcap",
	"CropBloom", "CropBush", "FishingBuoy", "StreetLamp", "LampPost", "HangingLantern", "Forge", "Hearth", "Cauldron",
	"Workbench", "BridgePost", "BridgeRail", "Statue", "WarpBeacon", "MarketStall", "Signboard", "SignPost", "Banner",
	-- Landmarks, Agility/Hunter props and dedicated shapes that replaced aliases.
	"Skyship", "Lighthouse", "Crane", "FishingPier", "Spyglass", "AgilityPerch", "ClimbNet", "BalanceBeam", "RopeSwing",
	"LedgeWalk", "ZipLine", "SlideChute", "SnareTrap", "BirdPerch", "SwarmBloom", "Waystone", "StormPylon", "StormSpire",
	"Stalactite", "RuinColumn", "Column", "Torch", "CropBed", "Bush", "RockOutcrop", "PalmTree", "DeadTree"}
for _, name in ipairs(required) do check(World.shapes[name] ~= nil, name .. " is authored") end
-- Every client downloads the world catalog: packed geometry keeps it small.
local catalogBytes = #fs.readFile("art/WorldCatalog.lua")
-- §40: the building kit (12 whole-building and interior meshes) raised the cap from 900 KB.
check(catalogBytes <= 1150 * 1024, "world catalog download stays under 1150 KB (" .. catalogBytes .. " bytes)")
-- Packed geometry decodes to exactly the OBJ masters' vertices and faces.
for _, name in ipairs({"Skyship", "ZipLine", "SnareTrap", "StormSpire", "WindpineTree"}) do
	local data, vi, fi = World.shapes[name], 0, 0
	for line in string.gmatch(fs.readFile("art/" .. name .. ".obj"), "[^\n]+") do
		local x, y, z = string.match(line, "^v (%S+) (%S+) (%S+)")
		if x then
			vi += 1
			local v = data.vertices[vi]
			check(v ~= nil and v[1] == tonumber(x) and v[2] == tonumber(y) and v[3] == tonumber(z), name .. " vertex " .. vi .. " matches its OBJ")
		end
		local shade = string.match(line, "^usemtl Shade(%d+)")
		if shade then fi += 1; check(data.faces[fi] and data.faces[fi][4] == tonumber(shade), name .. " face shade matches its OBJ") end
		local a, b, c = string.match(line, "^f (%d+) (%d+) (%d+)")
		if a then check(data.faces[fi][1] == tonumber(a) and data.faces[fi][2] == tonumber(b) and data.faces[fi][3] == tonumber(c), name .. " face matches its OBJ") end
	end
	check(vi == #data.vertices and fi == #data.faces, name .. " packed counts match its OBJ")
end
-- Fit boxes and line axes declared for slot-sized props.
for _, name in ipairs({"Crane", "FishingPier", "RopeSwing", "LedgeWalk", "ZipLine", "SlideChute", "SnareTrap", "BirdPerch", "SwarmBloom", "Waystone", "StormPylon", "Torch"}) do
	check(World.shapes[name].fit ~= nil, name .. " fits its host slot box")
end
check(World.shapes.RopeSwing.along == "Y", "rope swing declares its line axis")

local MeshForgeSource = fs.readFile("forge.client.lua")
-- A throwaway forge instance exposes the production normal smoother for the checks below.
local function baseEnv(overrides)
	local env = {
		game = {GetService = function() return {WaitForChild = function() return nil end, SetAttribute = function() end} end},
		workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
		Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = Instance, Enum = roblox.Enum, Font = roblox.Font,
		task = {spawn = function(f, ...) f(...) end, defer = function(f, ...) f(...) end, wait = function() end},
		warn = function() end, print = function() end,
	}
	for k, v in pairs(overrides or {}) do env[k] = v end
	return env
end
local probe = {}
luau.load(MeshForgeSource, {environment = baseEnv({MeshForgeTest = probe}), injectGlobals = true})()
local cornerNormals = probe.forge.cornerNormals

local worldTriangles, worldCount = 0, 0
for name, data in pairs(World.shapes) do
	worldCount += 1
	worldTriangles += #data.faces
	local points = validate(name, data, 200, if data.kind == "building" then 2400 else 1500)
	check(type(data.smooth) == "number" and data.smooth >= 0 and data.smooth < 90, name .. " smoothing crease")
	check(type(data.kind) == "string", name .. " kind")
	if data.tint then check(pcall(Color3.fromHex, data.tint), name .. " default tint") end
	for _, vol in ipairs(componentVolumes(data, points)) do check(vol > -1e-4, name .. " components are wound outward") end
	-- Corner normals are unit length and stay inside the crease around their face.
	local normals = cornerNormals(data)
	local limit = math.cos(math.rad(data.smooth)) - 1e-3
	for f, face in ipairs(data.faces) do
		local n = (points[face[2]] - points[face[1]]):Cross(points[face[3]] - points[face[1]]).Unit
		for k = 1, 3 do
			check(near(normals[f][k].Magnitude, 1), name .. " unit corner normal")
			check(normals[f][k]:Dot(n) >= (if data.smooth > 0 then limit else 1 - 1e-3), name .. " corner normal within crease")
		end
	end
	if data.fit then
		local lo, hi = Vector3.new(table.unpack(data.fit[1])), Vector3.new(table.unpack(data.fit[2]))
		check(hi.X > lo.X and hi.Y > lo.Y and hi.Z > lo.Z, name .. " fit box is valid")
	end
	if SIGNS[name] then check(data.kind == "sign", name .. " is a sign") end
end
check(World.shapes.Signboard.fit ~= nil and World.shapes.SignboardPosted.fit ~= nil, "signboards fit their text board")
for id, shape in pairs(World.resourceShapes) do check(World.shapes[shape] ~= nil and World.resourceShape(id) == shape, id .. " maps to a world shape") end
check(World.resourceShape("Celestium") == "OreVein4" and World.resourceShape(nil) == nil, "resource lookup")
-- UI icons are drawn as two WedgeParts per triangle: refreshed shapes stay in budget.
for _, name in ipairs({"AetherCrystal", "Fish", "Tonic", "Pickaxe", "Blade", "AlloyIngot", "AetherIngot", "Sword", "Potion", "OreChunk"}) do
	validate(name, Props.shapes[name], 12, 120)
end

------------------------------------------------------------------------------
-- Forge harness: mocked AssetService, ReplicatedStorage, Players (player focus), workspace.
------------------------------------------------------------------------------
local function service(attrs, catalogToken)
	return {
		WaitForChild = function(_, name) return catalogToken[name] end,
		SetAttribute = function(_, k, v) attrs[k] = v end,
		GetAttribute = function(_, k) return attrs[k] end,
	}
end
local function editableAsset(calls, behaviour)
	behaviour = behaviour or {}
	local asset = {}
	function asset.CreateEditableMesh(_self)
		calls.meshes += 1
		if behaviour.meshError then error(behaviour.meshError) end
		local mesh = {vertices = 0, faces = 0}
		function mesh.AddVertex(self, v) assert(typeof(v) == "Vector3"); self.vertices += 1; return self.vertices end
		function mesh.AddColor(_, c, alpha) assert(typeof(c) == "Color3" and alpha == 1); table.insert(calls.colors, c); return #calls.colors end
		function mesh.AddTriangle(self, a, b, c)
			assert(a >= 1 and b >= 1 and c >= 1 and a <= self.vertices and b <= self.vertices and c <= self.vertices)
			self.faces += 1; calls.triangles += 1; return self.faces
		end
		function mesh.SetFaceColors(_, _face, ids) assert(#ids == 3) end
		function mesh.AddNormal(_, n) assert(near(n.Magnitude, 1)); calls.normals += 1; return calls.normals end
		function mesh.SetFaceNormals(_, _face, ids) assert(#ids == 3); calls.faceNormals += 1 end
		function mesh.Destroy() calls.destroyed += 1 end
		return mesh
	end
	function asset.CreateMeshPartAsync(_self, content, _options)
		assert(content and content.object, "content from EditableMesh")
		calls.parts += 1
		if behaviour.partError then error(behaviour.partError) end
		return Instance.new("MeshPart")
	end
	return asset
end
local function loadForge(setup, asset, preset)
	local root = Instance.new("Folder")
	root.Name = "Workspace"
	local focus = {CFrame = CFrame.new(0, 0, 0)}
	if setup then setup(root) end
	local calls = {meshes = 0, parts = 0, colors = {}, triangles = 0, normals = 0, faceNormals = 0, destroyed = 0}
	local attrs, added, deferred = {}, nil, {}
	local tokens = {AetherWorldArt = "world", AetherArt = "props"}
	local services = {
		AssetService = asset or editableAsset(calls),
		ReplicatedStorage = service(attrs, tokens),
		Players = {LocalPlayer = {Character = {FindFirstChild = function() return focus end}}},
	}
	local test = {}
	local env = baseEnv({
		game = {GetService = function(_, name) return services[name] end},
		workspace = {
			GetDescendants = function() return root:GetDescendants() end,
			DescendantAdded = {Connect = function(_, fn) added = fn end},
		},
		require = function(token) return if token == "world" then World elseif token == "props" then Props else error("unknown module") end,
		Content = {fromObject = function(object) return {object = object} end},
		MeshForgeTest = test,
		-- task.spawn resumes a waiting thread too (template waiters, §32 QC H3).
		task = {spawn = function(f, ...) if type(f) == "thread" then assert(coroutine.resume(f, ...)) else f(...) end end,
			defer = function(f, ...) table.insert(deferred, table.pack(f, ...)) end, wait = function() end},
	})
	if preset then preset(env) end
	luau.load(MeshForgeSource, {environment = env, injectGlobals = true})()
	local function flush()
		while #deferred > 0 do
			local job = table.remove(deferred, 1)
			job[1](table.unpack(job, 2, job.n))
		end
	end
	flush()
	return {forge = test.forge, root = root, calls = calls, attrs = attrs, flush = flush, focus = focus,
		moveTo = function(position) focus.CFrame = CFrame.new(position); test.forge.step() end,
		add = function(instance) instance.Parent = root; added(instance); flush() end}
end
local function part(parent, name, size, cf, attributes)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Anchored, p.CanCollide = name, size, cf or CFrame.new(), true, true
	for k, v in pairs(attributes or {}) do p:SetAttribute(k, v) end
	p.Parent = parent
	return p
end
local function ltm(p)
	local ok, value = pcall(function() return p.LocalTransparencyModifier end)
	return if ok then value else 0
end
local function meshOf(p)
	local link = p:FindFirstChild("ShapeMesh")
	return link and link.Value
end
local function signBoard(parent)
	local board = part(parent, "Vault Gate", Vector3.new(12, 3.1, .32), CFrame.new(0, 4, 0), {Shape = "Signboard"})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Parent = board
	local function label(text, height, color)
		local t = Instance.new("TextLabel")
		t.Text, t.TextScaled, t.TextColor3 = text, true, color
		t.Size = roblox.UDim2.fromOffset(500, height)
		t.Parent = gui
		return t
	end
	return board, gui, label("EXPEDITION / ENTRY", 35, Color3.fromRGB(40, 50, 60)), label("Vault Gate", 70, Color3.fromRGB(240, 230, 210))
end

-- Success path ---------------------------------------------------------------
local tree1, tree2, ore, lantern, sign, gui, kicker, title, creature
local ok = loadForge(function(root)
	tree1 = part(root, "Meadow tree", Vector3.new(6, 9, 6), CFrame.new(10, 4.5, 0), {Shape = "MeadowTree"})
	tree2 = part(root, "Meadow tree 2", Vector3.new(4, 6, 4), CFrame.new(20, 3, 0) * CFrame.Angles(0, 1, 0), {Shape = "MeadowTree", ShapeScale = 1.5})
	ore = part(root, "Copper vein", Vector3.new(4, 2, 4), CFrame.new(0, 1, 30), {Shape = "OreVein2", Tint = Color3.fromRGB(255, 0, 0)})
	lantern = part(root, "Aether lantern", Vector3.new(1, 1, 1), CFrame.new(5, 4, 5), {Shape = "Lantern", SculptureScale = 0.7})
	lantern.Transparency = 1
	sign, gui, kicker, title = signBoard(root)
	creature = part(root, "Shellwarden", Vector3.new(1, 1, 1), CFrame.new(), {Shape = "Shellwarden"})
end)
local forge, calls = ok.forge, ok.calls
check(forge.stats.templates == 3 and calls.meshes == 3, "one template per (shape, tint), shared by both meadow trees: " .. forge.stats.templates)
check(forge.stats.instances == 4, "every contract-tagged shape placed once")
check(calls.faceNormals == calls.triangles and calls.normals > 0, "every triangle gets smoothed normals")
local expectedTris = #World.shapes.MeadowTree.faces + #World.shapes.OreVein2.faces + #World.shapes.Signboard.faces
check(forge.stats.templateTriangles == expectedTris, "template triangles counted")
check(calls.destroyed == 0, "live templates keep their EditableMesh")
for _, p in ipairs({tree1, tree2, ore, sign}) do
	local mesh = meshOf(p)
	check(p:GetAttribute("ShapeDone") == true and mesh ~= nil and mesh:IsA("MeshPart"), p.Name .. " meshed")
	check(mesh.Parent == p.Parent, p.Name .. " mesh sits beside its collider")
	check(mesh.Anchored and not mesh.CanCollide and not mesh.CanQuery and not mesh.CanTouch, p.Name .. " mesh is display-only")
	check(ltm(p) == 1 and p.Transparency == 0 and p.CanCollide, p.Name .. " original hidden locally only and still collides")
end
check(nearV(meshOf(tree1).Size, tree1.Size) and nearV(meshOf(tree1).CFrame.Position, tree1.CFrame.Position), "mesh fills the tagged part's bounds")
check(nearV(meshOf(tree2).Size, tree2.Size * 1.5), "ShapeScale multiplies the bounding size")
check(meshOf(tree2).CFrame.LookVector:FuzzyEq(tree2.CFrame.LookVector, 1e-4), "mesh keeps the part's rotation")
-- Tinted ore: the tint, its dark and light shades are in the colour set.
local function hasColor(target)
	for _, c in ipairs(calls.colors) do if near(c.R, target.R, 2e-3) and near(c.G, target.G, 2e-3) and near(c.B, target.B, 2e-3) then return true end end
	return false
end
check(hasColor(Color3.fromRGB(255, 0, 0)) and hasColor(Color3.new(.62, 0, 0)) and hasColor(Color3.new(1, .4, .4)), "tint slots recoloured")
check(hasColor(Color3.fromHex(World.shapes.MeadowTree.tint)), "untinted parts use the shape's default tint")
-- Legacy AetherSculpture anchors stay with mesh.client.lua (no duplicate mesh).
check(lantern:GetAttribute("ShapeSkipped") == "legacy sculpture" and meshOf(lantern) == nil and ltm(lantern) == 0, "legacy sculptures left to IslandArt")
-- Signs: the board keeps its SurfaceGui and becomes the flush text surface; text restyled.
check(gui.Parent == sign and kicker.Text == "EXPEDITION / ENTRY" and title.Text == "Vault Gate", "sign SurfaceGui and text preserved")
check(gui:GetAttribute("SignStyled") == true, "sign styled once")
check(title:FindFirstChildOfClass("UIStroke") ~= nil and kicker:FindFirstChildOfClass("UIStroke") ~= nil, "text outlined for contrast")
check(title:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize == 56, "title size capped for breathing room")
check(kicker.TextColor3.R > 40 / 255 + .2, "dark text brightened against the ink board")
do
	local mesh, fit = meshOf(sign), World.shapes.Signboard.fit
	check(mesh.Size.X > sign.Size.X and mesh.Size.Y > sign.Size.Y and mesh.Size.Z > sign.Size.Z, "frame wraps the board")
	-- The board (fit box) lands exactly on the original part: its face stays flush with the frame's panel.
	local offset = sign.CFrame:PointToObjectSpace(mesh.CFrame.Position)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, xyz in ipairs(World.shapes.Signboard.vertices) do local v = Vector3.new(xyz[1], xyz[2], xyz[3]); lo, hi = lo:Min(v), hi:Max(v) end
	local fitCentre = (Vector3.new(table.unpack(fit[1])) + Vector3.new(table.unpack(fit[2]))) / 2
	check(nearV(offset, (lo + hi) / 2 - fitCentre), "board fit box maps onto the sign part")
end
check(creature:GetAttribute("ShapeSkipped") == "unknown shape" and creature:GetAttribute("ShapeDone") == nil, "client-only creatures are left to the client")
check(ok.forge.stopReason() == nil and next(ok.attrs) == nil, "forge is client-local: nothing written to replicated services")
for _, d in ipairs(ok.root:GetDescendants()) do check(not d:IsA("WedgePart"), "no per-triangle wedge fallback") end

-- Late-tagged parts: added later (deferred attribute) and tagged after creation.
local late = part(nil, "Late boulder", Vector3.new(3, 2, 3), CFrame.new(0, 1, -20))
ok.add(late)
check(late:GetAttribute("ShapeDone") == nil, "untagged part ignored")
late:SetAttribute("Shape", "Boulder")
ok.forge.rescan(); ok.flush()
check(late:GetAttribute("ShapeDone") == true and meshOf(late) ~= nil, "part tagged after creation is meshed by rescan")
local lateTagged = part(nil, "Late lamp", Vector3.new(1, 7, 1), CFrame.new(3, 3.5, 3), {Shape = "StreetLamp"})
ok.add(lateTagged)
check(lateTagged:GetAttribute("ShapeDone") == true, "part added under Workspace later is meshed")
local templatesBefore = ok.forge.stats.templates
local again = part(nil, "Second lamp", Vector3.new(1, 7, 1), CFrame.new(6, 3.5, 3), {Shape = "StreetLamp"})
ok.add(again)
check(ok.forge.stats.templates == templatesBefore, "cached template reused for repeat shapes")
ok.forge.rescan(); ok.flush()
check(#ok.root:GetChildren() == 6 + 4 + 2 * 3, "rescan never duplicates meshes")

-- Failure paths ----------------------------------------------------------------
do
	local failCalls = {meshes = 0, parts = 0, colors = {}, triangles = 0, normals = 0, faceNormals = 0, destroyed = 0}
	local parts = {}
	local failed = loadForge(function(root)
		for i = 1, 5 do parts[i] = part(root, "Rock " .. i, Vector3.new(3, 2, 3), CFrame.new(i * 5, 1, 0), {Shape = ({"Boulder", "RockCluster", "CliffPiece", "Boulder", "MeadowTree"})[i]}) end
	end, editableAsset(failCalls, {meshError = "EditableMesh memory budget exceeded"}))
	for _, p in ipairs(parts) do
		check(ltm(p) == 0 and p:GetAttribute("ShapeDone") == nil and p:GetAttribute("ShapeSkipped") ~= nil, p.Name .. " primitive stays visible on failure")
	end
	check(failCalls.meshes == 1, "a memory-budget failure stops new allocations at once")
	check(#failed.root:GetChildren() == 5, "no mesh or proxy parts created on failure")
end
do
	local failCalls = {meshes = 0, parts = 0, colors = {}, triangles = 0, normals = 0, faceNormals = 0, destroyed = 0}
	local parts = {}
	local failed = loadForge(function(root)
		for i, shape in ipairs({"Boulder", "RockCluster", "CliffPiece", "MeadowTree", "Forge"}) do parts[i] = part(root, shape, Vector3.new(3, 3, 3), CFrame.new(i * 5, 1, 0), {Shape = shape}) end
	end, editableAsset(failCalls, {partError = "CreateMeshPartAsync failed"}))
	check(failCalls.meshes == 3 and failCalls.destroyed == 3, "failed builds release their EditableMesh; forge stops after 3 failures")
	check(failed.forge.stopReason() == "unavailable", "forge stops as unavailable")
	for _, p in ipairs(parts) do check(ltm(p) == 0 and p:GetAttribute("ShapeSkipped") ~= nil, p.Name .. " left as primitive") end
end
do
	local missing = loadForge(function(root) part(root, "Tree", Vector3.new(4, 8, 4), CFrame.new(), {Shape = "MeadowTree"}) end, {})
	local tree = missing.root:FindFirstChild("Tree")
	check(tree:GetAttribute("ShapeSkipped") == "unavailable" and ltm(tree) == 0, "missing EditableMesh API leaves primitives")
	local noContent = loadForge(function(root) part(root, "Tree", Vector3.new(4, 8, 4), CFrame.new(), {Shape = "MeadowTree"}) end, nil, function(env) env.Content = nil end)
	check(noContent.root:FindFirstChild("Tree"):GetAttribute("ShapeSkipped") == "unavailable", "missing Content.fromObject leaves primitives")
end
do
	-- A sign still gets its text restyle when meshing is unavailable.
	local board, signGui
	loadForge(function(root) board, signGui = signBoard(root) end, {})
	check(ltm(board) == 0 and signGui:GetAttribute("SignStyled") == true, "sign text restyled even without a mesh")
end

-- Budget caps -------------------------------------------------------------------
do
	local capped = loadForge()
	capped.forge.limits.templates = 2
	capped.forge.limits.instances = 5
	local a = part(nil, "A", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); capped.add(a)
	local b = part(nil, "B", Vector3.new(3, 3, 3), CFrame.new(5, 0, 0), {Shape = "Barrel"}); capped.add(b)
	local c = part(nil, "C", Vector3.new(3, 3, 3), CFrame.new(10, 0, 0), {Shape = "Crate"}); capped.add(c)
	check(a:GetAttribute("ShapeDone") and b:GetAttribute("ShapeDone"), "templates within the cap are built")
	check(c:GetAttribute("ShapeSkipped") == "budget" and ltm(c) == 0, "template cap leaves the primitive")
	check(capped.forge.stats.templates == 2, "template cap respected")
	local tinted = part(nil, "Tinted barrel", Vector3.new(3, 3, 3), CFrame.new(15, 0, 0), {Shape = "Barrel", Tint = Color3.new(0, 0, 1)}); capped.add(tinted)
	check(tinted:GetAttribute("ShapeDone") == true and capped.forge.stats.templates == 2, "over-cap tint variant reuses the shape's default template")
	for i = 1, 3 do capped.add(part(nil, "Extra " .. i, Vector3.new(3, 3, 3), CFrame.new(0, 0, i * 5), {Shape = "Boulder"})) end
	check(capped.forge.stats.instances == 5, "instance cap respected")
	check(capped.root:FindFirstChild("Extra 3"):GetAttribute("ShapeSkipped") == "budget", "instance cap leaves the primitive")
	local triCapped = loadForge()
	triCapped.forge.limits.templateTriangles = #World.shapes.Boulder.faces + 10
	local d = part(nil, "D", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); triCapped.add(d)
	local e = part(nil, "E", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Barrel"}); triCapped.add(e)
	check(d:GetAttribute("ShapeDone") and e:GetAttribute("ShapeSkipped") == "budget", "template triangle cap respected")
	triCapped.forge.limits.placedTriangles = triCapped.forge.stats.placedTriangles + 5
	local f = part(nil, "F", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); triCapped.add(f)
	check(f:GetAttribute("ShapeSkipped") == "budget", "placed triangle cap respected")
end

-- Uniform fit keeps proportions inside the part.
do
	local uniform = loadForge()
	local p = part(nil, "Wide tree", Vector3.new(20, 10, 20), CFrame.new(), {Shape = "WindpineTree", ShapeFit = "Uniform"}); uniform.add(p)
	local size = meshOf(p).Size
	check(size.X <= 20 + 1e-3 and size.Y <= 10 + 1e-3 and size.Z <= 20 + 1e-3 and (near(size.Y, 10) or near(size.X, 20) or near(size.Z, 20)), "uniform fit stays inside the part")
end

-- Line shapes turn onto the host's longest axis; resource slots follow their prompt.
do
	local lines = loadForge()
	local hanging = part(nil, "Swing rope", Vector3.new(.3, 9.2, .3), CFrame.new(0, 5, 0), {Shape = "RopeSwing"}); lines.add(hanging)
	local span = part(nil, "Rappel line", Vector3.new(.2, .2, 30), CFrame.new(5, 5, 0), {Shape = "RopeSwing"}); lines.add(span)
	local hangMesh, spanMesh = meshOf(hanging), meshOf(span)
	check(hangMesh.CFrame.UpVector:FuzzyEq(Vector3.new(0, 1, 0), 1e-4) and near(hangMesh.Size.Y, 9.2, .5), "hanging rope stays vertical")
	check(math.abs(spanMesh.CFrame.UpVector.Z) > .99 and spanMesh.Size.Y > 25 and spanMesh.Size.X < .9 and spanMesh.Size.Z < .9, "rappel line rope lies along its span")
	local resources = loadForge()
	local bed = part(nil, "Soil bed", Vector3.new(6.4, .4, 5), CFrame.new(0, .2, 0), {Shape = "CropBed"})
	local prompt = Instance.new("ProximityPrompt")
	prompt:SetAttribute("IsleItem", "Glowcap")
	prompt.Parent = bed
	resources.add(bed)
	local herbs = part(nil, "Herb bed mesh", Vector3.new(4.6, 1.6, 4.6), CFrame.new(20, .8, 0), {Shape = "CropBed"}); resources.add(herbs)
	check(meshOf(bed):GetAttribute("ShapeOf") == "CropGlowcap", "crop patch uses its resource's crop mesh")
	check(meshOf(herbs):GetAttribute("ShapeOf") == "CropBed", "a plain herb bed uses the dedicated bed mesh")
	local pine = part(nil, "Pine", Vector3.new(4, 9, 4), CFrame.new(40, 4.5, 0), {Shape = "PineTree"}); resources.add(pine)
	check(meshOf(pine):GetAttribute("ShapeOf") == "WindpineTree", "pine trees borrow the windpine mesh")
end

-- Cylinder hosts (world disk(): rolled 90 degrees about Z) stand the mesh up along
-- their axis; ShapeOwnsModel covers and hides the prop's primitive siblings.
do
	local owned = loadForge()
	local model = Instance.new("Model")
	model.Name = "Meadow tree"
	local trunk = part(model, "Trunk", Vector3.new(6, 1.1, 1.1), CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.pi / 2), {Shape = "MeadowTree", ShapeOwnsModel = true, ShapeFit = "Uniform"})
	trunk.Shape = roblox.Enum.PartType.Cylinder
	local canopy = part(model, "Canopy", Vector3.new(6.8, 6.8, 6.8), CFrame.new(0, 7.2, 0))
	local flame = part(model, "Glow", Vector3.new(.5, .5, .5), CFrame.new(1, 5, 0))
	flame.Material = roblox.Enum.Material.Neon
	local lantern = part(model, "Lantern anchor", Vector3.new(1, 1, 1), CFrame.new(0, 4, 0), {Shape = "Lantern", SculptureScale = .7})
	lantern.Transparency = 1
	local decal = Instance.new("Decal"); decal.Parent = canopy
	owned.add(model); owned.forge.rescan(); owned.flush()
	local mesh = meshOf(trunk)
	check(mesh ~= nil and mesh.CFrame.UpVector:FuzzyEq(Vector3.new(0, 1, 0), 1e-4), "cylinder host: tree mesh stands upright")
	-- Slot box = trunk + canopy (0..10.6 tall, 6.8 wide); uniform keeps the tree's proportions on the floor.
	local bottom = mesh.CFrame.Position.Y - mesh.Size.Y / 2
	check(mesh.Size.Y > 8 and mesh.Size.Y <= 10.6 + 1e-3 and mesh.Size.X <= 6.8 + 1e-3, "owned slot covers trunk and canopy: " .. tostring(mesh.Size))
	local data = World.shapes.MeadowTree
	local lo = math.huge
	for _, v in ipairs(data.vertices) do lo = math.min(lo, v[2]) end
	check(near(bottom, 0, .05), "uniform fit stands on the slot floor (" .. bottom .. ")")
	check(ltm(canopy) == 1 and ltm(decal) == 1, "owned sibling (and its decal) hidden locally")
	check(ltm(flame) == 0, "neon accents stay visible over the mesh")
	check(ltm(lantern) == 0 and lantern:GetAttribute("ShapeSkipped") == "legacy sculpture", "siblings with their own Shape are left alone")
	check(canopy.Transparency == 0, "siblings hidden only locally")
	owned.moveTo(Vector3.new(5000, 0, 0))
	check(meshOf(trunk) == nil and ltm(canopy) == 0 and ltm(decal) == 0 and ltm(trunk) == 0, "release restores the owned siblings")
	-- Without ShapeOwnsModel the mesh fills the host alone (and siblings stay).
	local lone = loadForge()
	local disk = part(nil, "Ore seam", Vector3.new(.8, 5, 5), CFrame.new(0, .4, 0) * CFrame.Angles(0, 0, math.pi / 2), {Shape = "OreVein2"})
	disk.Shape = roblox.Enum.PartType.Cylinder
	lone.add(disk)
	check(nearV(meshOf(disk).Size, Vector3.new(5, .8, 5)) and meshOf(disk).CFrame.UpVector.Y > .999, "cylinder slot is (diameter, length, diameter), upright")
	-- Owning a big model (an island) is refused: only small prop Models are covered.
	local big = loadForge()
	local isle = Instance.new("Model")
	for i = 1, 45 do part(isle, "Filler " .. i, Vector3.new(1, 1, 1), CFrame.new(i, 0, 0)) end
	local host = part(isle, "Host", Vector3.new(2, 2, 2), CFrame.new(), {Shape = "Boulder", ShapeOwnsModel = true})
	big.add(isle); big.forge.rescan(); big.flush()
	check(nearV(meshOf(host).Size, Vector3.new(2, 2, 2)) and ltm(isle:FindFirstChild("Filler 1")) == 0, "large Models are never hidden by an owner")
end

-- Budget skips back off exponentially; a release lets them retry at once.
do
	local clock = 0
	local backed = loadForge(nil, nil, function(env)
		env.os = {clock = function() return clock end}
	end)
	backed.forge.limits.instances = 1
	local a = part(nil, "A", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); backed.add(a)
	local b = part(nil, "B", Vector3.new(3, 3, 3), CFrame.new(5, 0, 0), {Shape = "Boulder"}); backed.add(b)
	check(b:GetAttribute("ShapeSkipped") == "budget" and backed.forge.backoff[b].delay == 2, "first budget skip waits 2 s")
	clock = 1; backed.forge.step()
	check(backed.forge.backoff[b].delay == 2, "no retry while backing off")
	clock = 3; backed.forge.step()
	check(backed.forge.backoff[b].delay == 4, "retry doubles the wait")
	clock = 8; backed.forge.step(); clock = 17; backed.forge.step()
	check(backed.forge.backoff[b].delay == 16, "backoff keeps doubling: " .. backed.forge.backoff[b].delay)
	a.Parent = nil; backed.forge.step()
	check(b:GetAttribute("ShapeDone") == true and backed.forge.backoff[b] == nil, "freed budget retries backed-off parts at once")
end

-- Phones: smaller limits and radius; discovery is signal-driven (no periodic rescan).
do
	local phone = loadForge(nil, nil, function(env)
		local services = env.game
		env.game = {GetService = function(self, name)
			if name == "UserInputService" then return {TouchEnabled = true, KeyboardEnabled = false} end
			return services.GetService(self, name)
		end}
	end)
	check(phone.forge.mobile and phone.forge.limits.placedTriangles <= 150000 and phone.forge.radii.build <= 250 and phone.forge.limits.templates <= 24, "touch devices get mobile forge limits")
	check(not ok.forge.mobile and ok.forge.radii.build == 400, "desktop keeps full limits")
	check(not MeshForgeSource:find("rescan%(%)%s*end") and not MeshForgeSource:find("elapsed >= 20", 1, true), "no periodic GetDescendants rescan")
end

-- Distance streaming: build near the player, release (and restore the primitive) far away.
do
	local streamed = loadForge()
	local far = part(nil, "Far boulder", Vector3.new(3, 2, 3), CFrame.new(1000, 1, 0), {Shape = "Boulder"})
	streamed.add(far)
	check(meshOf(far) == nil and ltm(far) == 0 and streamed.forge.stats.instances == 0, "parts beyond the build radius stay primitive")
	streamed.moveTo(Vector3.new(900, 0, 0))
	local mesh = meshOf(far)
	check(mesh ~= nil and ltm(far) == 1 and streamed.forge.stats.instances == 1, "approaching a part builds its mesh")
	streamed.moveTo(Vector3.new(1000 - streamed.forge.radii.unload + 30, 0, 0))
	check(meshOf(far) ~= nil, "hysteresis keeps meshes between the build and unload radii")
	streamed.moveTo(Vector3.new(0, 0, 0))
	check(meshOf(far) == nil and mesh.Parent == nil and ltm(far) == 0 and far:GetAttribute("ShapeDone") == nil, "leaving releases the mesh and restores the primitive")
	check(streamed.forge.stats.instances == 0 and streamed.forge.stats.placedTriangles == 0 and streamed.forge.stats.templates == 1, "release frees the instance budget, template stays cached")
	streamed.moveTo(Vector3.new(1000, 0, 0))
	check(meshOf(far) ~= nil and streamed.calls.meshes == 1, "returning reuses the cached template")
	far.Parent = nil
	streamed.forge.step()
	check(streamed.forge.stats.instances == 0, "removed parts release their mesh")
end

-- Sign kit tints (§28 M2/M3): only the eleven kit shapes are quantised; legacy
-- sign shapes (pennants, agility cloth, crew pennant, ledger) keep their Tint
-- on phones too; BannerCloth snaps to a small palette everywhere.
do
	local function phoneForge()
		return loadForge(nil, nil, function(env)
			local services = env.game
			env.game = {GetService = function(self, name)
				if name == "UserInputService" then return {TouchEnabled = true, KeyboardEnabled = false} end
				return services.GetService(self, name)
			end}
		end)
	end
	local phone, desk = phoneForge(), ok
	local red, teal = Color3.fromRGB(200, 40, 40), Color3.fromHex("6FA38A")
	local kit = {"SignHangingFrame", "SignpostFrame", "BannerStandardFrame", "SignPlinthFrame", "SignLedgerFrame", "SignCarvedBoard",
		"SignScrollBoard", "SignArrowBoard", "SignPlaqueBoard", "SignNoticeBoard", "BannerCloth"}
	local kitSet = {}
	for _, name in kit do kitSet[name] = true end
	local n = 0
	for name in pairs(phone.forge.kitShapes) do n += 1; check(kitSet[name] == true, name .. " is a kit shape") end
	check(n == 11, "exactly the eleven kit shapes are shared (" .. n .. ")")
	for _, legacy in {"Banner", "Signboard", "SignboardPosted", "SignPost"} do
		check(World.shapes[legacy].kind == "sign", legacy .. " is a sign-kind shape")
		check(phone.forge.templateTint(legacy, World.shapes[legacy], red) == red, legacy .. " keeps its Tint on phones")
		check(desk.forge.templateTint(legacy, World.shapes[legacy], red) == red, legacy .. " keeps its Tint on desktop")
	end
	local themeMetals = {"C9A24E", "6FA38A", "B8733F", "AFA8A0", "B8C6CF", "8E7BC0", "7FC9C9", "A8B6CC", "E0B44E"}
	for _, name in kit do
		local data = World.shapes[name]
		local seen, distinct = {}, 0
		for _, hex in themeMetals do
			local phoneTint = phone.forge.templateTint(name, data, Color3.fromHex(hex))
			local deskTint = desk.forge.templateTint(name, data, Color3.fromHex(hex))
			if name == "BannerCloth" then
				check(table.find(phone.forge.clothPalette, phoneTint) ~= nil and phoneTint == deskTint, "BannerCloth tint snaps to the cloth palette on every device")
			else
				check(phoneTint:ToHex() == data.tint or phoneTint:ToHex():upper() == data.tint, name .. " shares its default tint on phones")
				check(table.find(desk.forge.kitMetals, deskTint) ~= nil, name .. " tint snaps to a kit metal on desktop")
				if not seen[deskTint:ToHex()] then seen[deskTint:ToHex()] = true; distinct += 1 end
			end
		end
		if name ~= "BannerCloth" then check(distinct <= 3, name .. ": ten themes use <= 3 metal templates (" .. distinct .. ")") end
	end
	check(#phone.forge.clothPalette <= 8, "cloth palette is small")
	-- A legacy pennant (Banner) keeps its colour on a phone: its template carries the tint.
	local pennant = part(nil, "Pennant", Vector3.new(1, 2, .1), CFrame.new(), {Shape = "Banner", Tint = red}); phone.add(pennant)
	check(phone.forge.templates["Banner#" .. red:ToHex()] ~= nil, "phone pennant template keeps its tint")
	local plate = part(nil, "Plate", Vector3.new(4, 1.5, .3), CFrame.new(5, 0, 0), {Shape = "SignCarvedBoard", Tint = teal}); phone.add(plate)
	check(phone.forge.templates["SignCarvedBoard#" .. World.shapes.SignCarvedBoard.tint] ~= nil
		or phone.forge.templates["SignCarvedBoard#" .. string.lower(World.shapes.SignCarvedBoard.tint)] ~= nil, "phone kit board uses the shared template")
end

-- L5: BannerCloth lining stays behind the host's faces inside the text area
-- (|x| < 1.8, |y| < 2.2 of the 3.8 x 5 x .14 reference; the gold hem band is below): no vertex crosses z = +-.07.
do
	local data, worst = World.shapes.BannerCloth, 0
	for _, v in ipairs(data.vertices) do
		if math.abs(v[1]) < 1.8 and math.abs(v[2]) < 2.2 then worst = math.max(worst, math.abs(v[3])) end
	end
	check(worst <= .07 + 1e-4, "BannerCloth text area stays behind its faces (max |z| " .. worst .. ")")
end

-- LRU eviction: a new template evicts the least recently used idle template.
do
	local function tpl(f, shape)
		for key, entry in pairs(f.templates) do if string.sub(key, 1, #shape + 1) == shape .. "#" then return entry end end
		return nil
	end
	local lru = loadForge()
	lru.forge.limits.templates = 2
	local a = part(nil, "A", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); lru.add(a)
	local b = part(nil, "B", Vector3.new(3, 3, 3), CFrame.new(5, 0, 0), {Shape = "Barrel"}); lru.add(b)
	local c = part(nil, "C", Vector3.new(3, 3, 3), CFrame.new(10, 0, 0), {Shape = "Crate"}); lru.add(c)
	check(c:GetAttribute("ShapeSkipped") == "budget" and lru.forge.stats.evicted == 0, "templates with live clones are never evicted")
	a.Parent = nil; lru.forge.step()
	-- The release frees a slot: the waiting crate retries at once and evicts the idle boulder template.
	check(c:GetAttribute("ShapeDone") == true and lru.forge.stats.evicted == 1 and tpl(lru.forge, "Boulder") == nil, "idle template evicted for a waiting shape")
	check(lru.forge.stats.templates == 2 and lru.calls.destroyed == 1, "eviction destroys the EditableMesh and keeps the count")
	check(tpl(lru.forge, "Barrel").users == 1 and tpl(lru.forge, "Crate").users == 1, "in-use templates kept and counted")
	local d = part(nil, "D", Vector3.new(3, 3, 3), CFrame.new(15, 0, 0), {Shape = "Crate"}); lru.add(d)
	check(d:GetAttribute("ShapeDone") == true and tpl(lru.forge, "Crate").users == 2 and lru.forge.stats.evicted == 1, "clones share the template")
	-- Least recently used goes first.
	local lru2 = loadForge()
	lru2.forge.limits.templates = 3
	local p1 = part(nil, "P1", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); lru2.add(p1)
	local p2 = part(nil, "P2", Vector3.new(3, 3, 3), CFrame.new(5, 0, 0), {Shape = "Barrel"}); lru2.add(p2)
	local p3 = part(nil, "P3", Vector3.new(3, 3, 3), CFrame.new(10, 0, 0), {Shape = "Crate"}); lru2.add(p3)
	p2.Parent = nil; lru2.forge.step()
	p1.Parent = nil; lru2.forge.step()
	local p4 = part(nil, "P4", Vector3.new(3, 3, 3), CFrame.new(15, 0, 0), {Shape = "Anvil"}); lru2.add(p4)
	check(tpl(lru2.forge, "Barrel") == nil and tpl(lru2.forge, "Boulder") ~= nil, "the least recently used idle template is evicted first")
end

-- Sky Chart requests (§32 QC H2 / H3): served from existing templates, a new
-- template only while 8 slots stay free, pinned only on accept (released on
-- reject), at most 16 chart pins, chart-only pins yield to a starved world, and
-- concurrent builds of one template share a single EditableMesh.
do
	local function tpl(f, shape)
		for key, entry in pairs(f.templates) do if string.sub(key, 1, #shape + 1) == shape .. "#" and entry then return entry end end
		return nil
	end
	local function host(name, shape, x) return part(nil, name, Vector3.new(3, 3, 3), CFrame.new(x or 0, 0, 0), {Shape = shape}) end
	local f = loadForge()
	local C = f.forge.chart
	f.forge.limits.templates = 9
	local mesh1, tris1, tok1 = C.visual(host("H1", "Boulder"))
	check(mesh1 ~= nil and tris1 > 0 and tok1 ~= nil and mesh1:GetAttribute("ShapeTriangles") == tris1, "a free forge serves the chart a mesh, its triangles and a token")
	check(tpl(f.forge, "Boulder").users == 0, "nothing is pinned before the chart accepts")
	check(C.visual(host("H2", "Barrel")) == nil and f.forge.stats.templates == 1, "a new chart template needs 8 free slots (the world's reserve)")
	local mesh3, _, tok3 = C.visual(host("H3", "Boulder"))
	check(mesh3 ~= nil, "an existing template still serves the chart")
	check(C.accept(tok1) and tpl(f.forge, "Boulder").users == 1 and f.forge.stats.chartPins == 1, "accept pins the template once")
	check(C.accept(tok3) and tpl(f.forge, "Boulder").users == 1 and f.forge.stats.chartPins == 1, "a second accepted mesh shares the pin")
	C.release(tok1)
	check(tpl(f.forge, "Boulder").users == 1, "one mesh still accepted keeps the pin")
	C.release(tok3)
	check(tpl(f.forge, "Boulder").users == 0 and f.forge.stats.chartPins == 0, "releasing every mesh unpins the template")
	local _, _, tok4 = C.visual(host("H4", "Boulder"))
	C.release(tok4)
	check(tpl(f.forge, "Boulder").users == 0 and not C.accept(tok4), "a rejected (released) mesh never pins")
	-- Pin cap: 16 chart-pinned templates on desktop.
	local caps = loadForge()
	local names = {}
	for name, data in pairs(World.shapes) do if data.kind ~= "sign" and #data.faces < 800 then table.insert(names, name) end end
	table.sort(names)
	local pinned = 0
	for i = 1, caps.forge.chart.pinCap + 1 do
		local _, _, token = caps.forge.chart.visual(host("Cap" .. i, names[i], i * 6))
		if token and caps.forge.chart.accept(token) then pinned += 1 end
	end
	check(caps.forge.chart.pinCap == 16 and pinned == 16 and caps.forge.stats.chartPins == 16 and caps.forge.stats.chartRefused >= 1, "at most 16 chart pins on desktop")
	-- A starved world takes back a template only the chart holds; the chart's
	-- mesh is marked ShapeRevoked (the chart swaps its stand-in back).
	local starve = loadForge()
	starve.forge.limits.templates = 2
	local a = part(nil, "A", Vector3.new(3, 3, 3), CFrame.new(), {Shape = "Boulder"}); starve.add(a)
	local b = part(nil, "B", Vector3.new(3, 3, 3), CFrame.new(5, 0, 0), {Shape = "Barrel"}); starve.add(b)
	local ma, _, ta = starve.forge.chart.visual(host("FarA", "Boulder", 900))
	local mb, _, tb = starve.forge.chart.visual(host("FarB", "Barrel", 905))
	check(ma and mb and starve.forge.chart.accept(ta) and starve.forge.chart.accept(tb), "the chart pins the world's own templates")
	a.Parent = nil; b.Parent = nil; starve.forge.step()
	local c = part(nil, "C", Vector3.new(3, 3, 3), CFrame.new(10, 0, 0), {Shape = "Crate"}); starve.add(c)
	check(c:GetAttribute("ShapeDone") == true and starve.forge.stats.chartRevoked == 1, "a chart-only pin yields to the starved world")
	check((ma:GetAttribute("ShapeRevoked") == true) ~= (mb:GetAttribute("ShapeRevoked") == true), "the yielded mesh is marked for its stand-in")
	-- H3: a template build yields (CreateMeshPartAsync); a second request for it waits.
	local myCalls = {meshes = 0, parts = 0, colors = {}, triangles = 0, normals = 0, faceNormals = 0, destroyed = 0}
	local base = editableAsset(myCalls)
	local gate = {hold = false}
	local asset = {CreateEditableMesh = base.CreateEditableMesh, CreateMeshPartAsync = function(self, content, options)
		if gate.hold then gate.waiting = coroutine.running(); coroutine.yield() end
		return base.CreateMeshPartAsync(self, content, options)
	end}
	local y = loadForge(nil, asset)
	gate.hold = true
	local results = {}
	local co1 = coroutine.create(function() results[1] = table.pack(y.forge.chart.visual(host("Y1", "Boulder"))) end)
	assert(coroutine.resume(co1))
	check(coroutine.status(co1) == "suspended" and y.forge.stats.templates == 1 and myCalls.meshes == 1, "the build in flight holds its template slot")
	local co2 = coroutine.create(function() results[2] = table.pack(y.forge.chart.visual(host("Y2", "Boulder"))) end)
	assert(coroutine.resume(co2))
	check(coroutine.status(co2) == "suspended" and myCalls.meshes == 1, "a concurrent request waits instead of building a second EditableMesh")
	gate.hold = false
	assert(coroutine.resume(gate.waiting))
	check(results[1] and results[1][1] and results[2] and results[2][1], "both requests are served when the build lands")
	check(myCalls.meshes == 1 and y.forge.stats.templates == 1 and myCalls.destroyed == 0 and tpl(y.forge, "Boulder").pending == nil, "one template, no leaked mesh or slot")
end

-- Template budget tour (§28 M3, §30): the real world, hub then every region, on
-- desktop and phone limits. No part may be left primitive for want of a
-- template slot while idle templates could be evicted, and sign kit pieces fit.
do
	local Data = luau.load(fs.readFile("shared/GameData.lua"), {injectGlobals = true})()
	local function sig()
		local listeners = {}
		return {Connect = function(_, f) table.insert(listeners, f) return {Disconnect = function() end} end,
			Fire = function(_, ...) for _, f in listeners do f(...) end end}
	end
	roblox.implementProperty("ProximityPrompt", "Triggered", function() return sig() end)
	local players = {PlayerAdded = sig(), PlayerRemoving = sig(), GetPlayers = function() return {} end}
	local dataModule = {Name = "AetherData"}
	local function buildWorld()
		local wsp = Instance.new("Workspace")
		local env = {
			game = {GetService = function(_, name)
				if name == "Players" then return players end
				if name == "Lighting" then return Instance.new("Lighting") end
				if name == "CollectionService" then return {AddTag = function() end} end
				if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
				if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
				return {}
			end},
			workspace = wsp, Instance = Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = Color3,
			UDim2 = roblox.UDim2, UDim = roblox.UDim, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange,
			NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
			task = {spawn = function() end, wait = function() end, defer = function() end, delay = function() end},
			require = function() return Data end,
		}
		luau.load(fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position"), {environment = env, injectGlobals = true})()
		return wsp
	end
	-- Tour: Compass Quay first, then every static region island (IslandCenter of each Islands model).
	local STOPS = {}
	do
		local wsp = buildWorld()
		for _, isle in wsp:FindFirstChild("Islands"):GetChildren() do
			local c = isle:GetAttribute("IslandCenter")
			if c then table.insert(STOPS, {isle.Name, c + Vector3.new(0, 4, 0)}) end
		end
		table.sort(STOPS, function(a, b) return a[2].Magnitude < b[2].Magnitude end)
	end
	check(#STOPS >= 12, "tour visits the hub and every region island (" .. #STOPS .. ")")
	local function tour(device)
		local wsp = buildWorld()
		local clock = 0
		local run = loadForge(function(root)
			for _, child in wsp:GetChildren() do if child:IsA("Folder") then child.Parent = root end end
		end, nil, function(env)
			env.os = {clock = function() return clock end}
			if device == "phone" then
				local services = env.game
				env.game = {GetService = function(self, name)
					if name == "UserInputService" then return {TouchEnabled = true, KeyboardEnabled = false} end
					return services.GetService(self, name)
				end}
			end
		end)
		-- Hold every instance strongly: the forge's registry is weak-keyed and Lune's
		-- Instance userdata would otherwise be collected between steps (in Roblox the
		-- DataModel keeps them alive).
		local keep = run.root:GetDescendants()
		local report, peak = {}, 0
		for _, stop in STOPS do
			local skipsBefore = run.forge.stats.templateSkips
			-- Arrive, then let every backed-off part retry (several steps, minutes apart).
			for _ = 1, 4 do clock += 100; run.moveTo(stop[2]) end
			local near = if device == "phone" then 40 else 150
			local nearPrimitive, kitPrimitive, permanent = 0, 0, 0
			for _, p in run.root:GetDescendants() do
				if p:IsA("BasePart") then
					local why = p:GetAttribute("ShapeSkipped")
					if why == "failed" or why == "unavailable" or why == "clone failed" or why == "error" then permanent += 1 end
					if why == "budget" and (p.CFrame.Position - stop[2]).Magnitude <= near then
						nearPrimitive += 1
						if run.forge.kitShapes[p:GetAttribute("Shape")] then kitPrimitive += 1 end
					end
				end
			end
			peak = math.max(peak, run.forge.stats.templates)
			check(run.forge.stats.templates <= run.forge.limits.templates and run.forge.stats.templateTriangles <= run.forge.limits.templateTriangles,
				device .. " " .. stop[1] .. ": template caps hold (" .. run.forge.stats.templates .. ")")
			check(permanent == 0, device .. " " .. stop[1] .. ": no permanent primitive fallback")
			check(nearPrimitive == 0, device .. " " .. stop[1] .. ": every shape within " .. near .. " studs meshed (" .. nearPrimitive .. " left primitive)")
			table.insert(report, string.format("%s %d tpl/%dk tris, %d evicted so far, %d tpl-budget skips", stop[1],
				run.forge.stats.templates, run.forge.stats.templateTriangles // 1000, run.forge.stats.evicted, run.forge.stats.templateSkips - skipsBefore))
		end
		print("Template tour (" .. device .. "): " .. table.concat(report, "; ") .. "; peak " .. peak .. ", " .. run.forge.stats.reclaimed .. " reclaimed, " .. #keep .. " instances.")
		return run
	end
	local desk, phone = tour("desktop"), tour("phone")
	-- §40 building kit: every building and interior host maps its mesh 1:1 onto
	-- its declared ShapeBox (fit box = mesh bounds), standing on the host's
	-- ground; houses forge nearer on phones and interiors only up close.
	local buildingHosts = 0
	for _, p in desk.root:GetDescendants() do
		if p:IsA("BasePart") and type(p:GetAttribute("Shape")) == "string" and World.shapes[p:GetAttribute("Shape")] and World.shapes[p:GetAttribute("Shape")].kind == "building" then
			buildingHosts += 1
			local d = desk.forge.describe(p)
			local box, offset = p:GetAttribute("ShapeBox") or p.Size, p:GetAttribute("ShapeBoxOffset") or Vector3.new()
			check(d ~= nil and d.kind == "building" and nearV(d.size, box, 1e-3), p:GetFullName() .. " mesh fills its ShapeBox 1:1")
			check(nearV(d.cframe.Position, (p.CFrame * CFrame.new(offset)).Position, 1e-3), p:GetFullName() .. " mesh centred on its declared box")
			check(math.abs(d.cframe.UpVector.Y - 1) < 1e-4, p:GetFullName() .. " mesh upright")
			local interior = World.shapes[p:GetAttribute("Shape")].interior == true
			check(desk.forge.buildRadius(p) == (if interior then 120 else desk.forge.radii.build), p.Name .. " desktop building radius")
			check(phone.forge.buildRadius(p) == (if interior then 14 else 120), p.Name .. " phone building radius")
		end
	end
	-- §40 QC M2: phone building templates are released just past their build
	-- radius (shell 120 * 1.2, interior 14 + 10), not held to UNLOAD_RADIUS.
	do
		local interiorHost
		for _, p in phone.root:GetDescendants() do
			if p:IsA("BasePart") and type(p:GetAttribute("Shape")) == "string" and World.shapes[p:GetAttribute("Shape")]
				and World.shapes[p:GetAttribute("Shape")].interior == true then interiorHost = p break end
		end
		check(interiorHost ~= nil, "an interior host to walk away from")
		check(phone.forge.releaseRadius(interiorHost) == 24 and desk.forge.releaseRadius(interiorHost) == 144, "interior release radius (phone 24, desktop 144)")
		local at = interiorHost.CFrame.Position
		for _ = 1, 3 do phone.moveTo(at + Vector3.new(0, 2, 4)) end
		check(phone.forge.placed[interiorHost] ~= nil, "the phone forges the interior up close (" .. tostring(interiorHost:GetAttribute("ShapeSkipped")) .. ")")
		phone.moveTo(at + Vector3.new(30, 2, 0))
		check(phone.forge.placed[interiorHost] == nil, "walking 30 studs away releases the phone interior")
		local shell = interiorHost.Parent and interiorHost.Parent:FindFirstChild("Roofed hall floor", true)
		if shell and phone.forge.placed[shell] then
			phone.moveTo(at + Vector3.new(160, 2, 0))
			check(phone.forge.placed[shell] == nil, "a phone hall shell is released past 144 studs")
		end
	end
	check(buildingHosts >= 55, "building hosts on the tour (" .. buildingHosts .. "; meshed everywhere the per-stop checks above require)")
	check(desk.forge.stats.evicted > 0 and phone.forge.stats.evicted > 0, "LRU eviction recycles idle templates during the tour")
end

-- Client roles: IslandArt keeps legacy sculptures and creatures; nothing runs on the server.
local client = fs.readFile("mesh.client.lua")
check(client:find('GetAttribute("ShapeScale")', 1, true) ~= nil and client:find("CREATURES", 1, true) ~= nil, "IslandArt leaves contract-sized Shape parts to MeshForge")
check(not fs.isFile("mesh.server.lua"), "no server-side forge: the server never hides parts")
check(not MeshForgeSource:find("%.Transparency%s*=%s*1"), "forge only hides parts locally")

print(string.format("Mesh QA passed %d checks: %d world shapes / %d triangles; forge success, failure, budget, late-tag and sign paths.", checks, worldCount, worldTriangles))

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-mesh.luau")
