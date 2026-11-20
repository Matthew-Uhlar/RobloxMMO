-- Mesh team verification: catalog integrity and the server MeshForge (mesh.server.lua)
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
	"Workbench", "BridgePost", "BridgeRail", "Statue", "WarpBeacon", "MarketStall", "Signboard", "SignPost", "Banner"}
for _, name in ipairs(required) do check(World.shapes[name] ~= nil, name .. " is authored") end

local MeshForgeSource = fs.readFile("mesh.server.lua")
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
	local points = validate(name, data, 200, 1500)
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
-- Forge harness: mocked AssetService, ReplicatedStorage/ServerStorage, workspace.
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
	if setup then setup(root) end
	local calls = {meshes = 0, parts = 0, colors = {}, triangles = 0, normals = 0, faceNormals = 0, destroyed = 0}
	local attrs, added, deferred = {}, nil, {}
	local tokens = {AetherWorldArt = "world", AetherArt = "props"}
	local services = {
		AssetService = asset or editableAsset(calls),
		ReplicatedStorage = service(attrs, tokens),
		ServerStorage = service(attrs, tokens),
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
		task = {spawn = function(f, ...) f(...) end, defer = function(f, ...) table.insert(deferred, table.pack(f, ...)) end, wait = function() end},
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
	return {forge = test.forge, root = root, calls = calls, attrs = attrs, flush = flush,
		add = function(instance) instance.Parent = root; added(instance); flush() end}
end
local function part(parent, name, size, cf, attributes)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Anchored, p.CanCollide = name, size, cf or CFrame.new(), true, true
	for k, v in pairs(attributes or {}) do p:SetAttribute(k, v) end
	p.Parent = parent
	return p
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
check(forge.stats.templates == 4 and calls.meshes == 4, "one template per (shape, tint), shared by both meadow trees: " .. forge.stats.templates)
check(forge.stats.instances == 5, "every known shape placed once")
check(calls.faceNormals == calls.triangles and calls.normals > 0, "every triangle gets smoothed normals")
local expectedTris = #World.shapes.MeadowTree.faces + #World.shapes.OreVein2.faces + #Props.shapes.Lantern.faces + #World.shapes.Signboard.faces
check(forge.stats.templateTriangles == expectedTris, "template triangles counted")
check(calls.destroyed == 0, "live templates keep their EditableMesh")
for _, p in ipairs({tree1, tree2, ore, lantern, sign}) do
	local mesh = meshOf(p)
	check(p:GetAttribute("ShapeDone") == true and mesh ~= nil and mesh:IsA("MeshPart"), p.Name .. " meshed")
	check(mesh.Parent == p.Parent, p.Name .. " mesh sits beside its collider")
	check(mesh.Anchored and not mesh.CanCollide and not mesh.CanQuery and not mesh.CanTouch, p.Name .. " mesh is display-only")
	check(p.Transparency == 1 and p.CanCollide, p.Name .. " original hidden but still collides")
end
check(tree1:GetAttribute("ShapeOriginalTransparency") == 0, "original transparency recorded")
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
-- Legacy anchors keep authored size × SculptureScale with the authored origin at the anchor.
do
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, xyz in ipairs(Props.shapes.Lantern.vertices) do local v = Vector3.new(xyz[1], xyz[2], xyz[3]); lo, hi = lo:Min(v), hi:Max(v) end
	local mesh = meshOf(lantern)
	check(nearV(mesh.Size, (hi - lo) * .7), "legacy sculpture size")
	check(nearV(mesh.CFrame.Position, lantern.CFrame.Position + (lo + hi) / 2 * .7), "legacy sculpture origin")
end
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
check(ok.attrs.MeshForgeStatus == "ready" and ok.attrs.MeshForgeInstances == 5, "forge status replicated")
for _, d in ipairs(ok.root:GetDescendants()) do check(not d:IsA("WedgePart"), "no per-triangle wedge fallback") end

-- Late-tagged parts: added later (deferred attribute) and tagged after creation.
local late = part(nil, "Late boulder", Vector3.new(3, 2, 3), CFrame.new(0, 1, -20))
ok.add(late)
check(late:GetAttribute("ShapeDone") == nil, "untagged part ignored")
late:SetAttribute("Shape", "Boulder")
ok.forge.rescan()
check(late:GetAttribute("ShapeDone") == true and meshOf(late) ~= nil, "part tagged after creation is meshed by rescan")
local lateTagged = part(nil, "Late lamp", Vector3.new(1, 7, 1), CFrame.new(3, 3.5, 3), {Shape = "StreetLamp"})
ok.add(lateTagged)
check(lateTagged:GetAttribute("ShapeDone") == true, "part added under Workspace later is meshed")
local templatesBefore = ok.forge.stats.templates
local again = part(nil, "Second lamp", Vector3.new(1, 7, 1), CFrame.new(6, 3.5, 3), {Shape = "StreetLamp"})
ok.add(again)
check(ok.forge.stats.templates == templatesBefore, "cached template reused for repeat shapes")
ok.forge.rescan()
check(#ok.root:GetChildren() == 6 + 5 + 2 * 3, "rescan never duplicates meshes")

-- Failure paths ----------------------------------------------------------------
do
	local failCalls = {meshes = 0, parts = 0, colors = {}, triangles = 0, normals = 0, faceNormals = 0, destroyed = 0}
	local parts = {}
	local failed = loadForge(function(root)
		for i = 1, 5 do parts[i] = part(root, "Rock " .. i, Vector3.new(3, 2, 3), CFrame.new(i * 5, 1, 0), {Shape = ({"Boulder", "RockCluster", "CliffPiece", "Boulder", "MeadowTree"})[i]}) end
	end, editableAsset(failCalls, {meshError = "EditableMesh memory budget exceeded"}))
	for _, p in ipairs(parts) do
		check(p.Transparency == 0 and p:GetAttribute("ShapeDone") == nil and p:GetAttribute("ShapeSkipped") ~= nil, p.Name .. " primitive stays visible on failure")
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
	check(failed.forge.stopReason() == "unavailable" and failed.attrs.MeshForgeStatus == "unavailable", "forge reports unavailable")
	for _, p in ipairs(parts) do check(p.Transparency == 0 and p:GetAttribute("ShapeSkipped") ~= nil, p.Name .. " left as primitive") end
end
do
	local missing = loadForge(function(root) part(root, "Tree", Vector3.new(4, 8, 4), CFrame.new(), {Shape = "MeadowTree"}) end, {})
	local tree = missing.root:FindFirstChild("Tree")
	check(tree:GetAttribute("ShapeSkipped") == "unavailable" and tree.Transparency == 0, "missing EditableMesh API leaves primitives")
	check(missing.attrs.MeshForgeStatus == "unavailable", "clients learn the forge is unavailable")
	local noContent = loadForge(function(root) part(root, "Tree", Vector3.new(4, 8, 4), CFrame.new(), {Shape = "MeadowTree"}) end, nil, function(env) env.Content = nil end)
	check(noContent.root:FindFirstChild("Tree"):GetAttribute("ShapeSkipped") == "unavailable", "missing Content.fromObject leaves primitives")
end
do
	-- A sign still gets its text restyle when meshing is unavailable.
	local board, signGui
	loadForge(function(root) board, signGui = signBoard(root) end, {})
	check(board.Transparency == 0 and signGui:GetAttribute("SignStyled") == true, "sign text restyled even without a mesh")
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
	check(c:GetAttribute("ShapeSkipped") == "budget" and c.Transparency == 0, "template cap leaves the primitive")
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

-- Client: skips duplicate work for server-meshed parts and keeps local effects.
local client = fs.readFile("mesh.client.lua")
check(client:find('GetAttribute("ShapeDone")', 1, true) ~= nil and client:find("ShapeMesh", 1, true) ~= nil, "client reuses server meshes")
check(client:find("MeshForgeStatus", 1, true) ~= nil and client:find("ShapeSkipped", 1, true) ~= nil, "client builds only what the server skipped")

print(string.format("Mesh QA passed %d checks: %d world shapes / %d triangles; forge success, failure, budget, late-tag and sign paths.", checks, worldCount, worldTriangles))
