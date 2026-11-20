-- MeshForge (client): custom meshes for parts tagged with the Shape attribute
-- (docs/DEPTH-CONTRACT.md §10). EditableMesh data is local to the machine that
-- creates it, so every client forges its own meshes: one EditableMesh-backed
-- MeshPart template per (shape, tint), cloned for tagged parts within BUILD_RADIUS
-- of the player and released beyond UNLOAD_RADIUS. The original part is hidden
-- only locally (LocalTransparencyModifier) once its mesh exists, stays the
-- collider/SurfaceGui surface, and is restored when the mesh is released. If the
-- API is unavailable, fails, or a budget is reached, the primitive stays visible
-- (no per-triangle fallback). The server never hides anything.
--
-- Attributes read on a tagged part:
--   Shape (string)       catalog shape name (art/WorldCatalog.lua or art/PropCatalog.lua)
--   Tint (Color3)        colour for the shape's tint slots (default: the shape's own tint)
--   ShapeScale (number)  multiplies the part's size (default 1)
--   ShapeFit (string)    "Uniform" keeps proportions (fits inside the part); default stretches
-- Legacy AetherSculpture anchors (SculptureScale without ShapeScale) and creatures
-- stay with mesh.client.lua. Local-only markers: ShapeDone / ShapeSkipped attributes
-- and an ObjectValue "ShapeMesh" under the part (never replicated).
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LIMITS = {
	templates = 48, -- distinct (shape, tint) EditableMeshes kept alive
	templateTriangles = 45000, -- triangles across all cached EditableMeshes
	instances = 900, -- placed MeshPart clones near the player
	placedTriangles = 600000, -- triangles across all placed clones
	failures = 3, -- template build failures before the forge stops trying
}
local BUILD_RADIUS, UNLOAD_RADIUS = 400, 480
local STEP_SECONDS = 1

local function loadCatalog(name)
	local module = ReplicatedStorage:WaitForChild(name, 15)
	if not module then return nil end
	local ok, catalog = pcall(require, module)
	if ok and type(catalog) == "table" and type(catalog.shapes) == "table" then return catalog end
	return nil
end
local catalogs = {}
for _, name in ipairs({"AetherWorldArt", "AetherArt"}) do
	local catalog = loadCatalog(name)
	if catalog then table.insert(catalogs, catalog) end
end
local function lookup(shapeName)
	for _, catalog in ipairs(catalogs) do
		local data = catalog.shapes[shapeName]
		if type(data) == "table" and type(data.vertices) == "table" and type(data.faces) == "table" then return data, catalog end
	end
	return nil
end

local stats = {templates = 0, templateTriangles = 0, instances = 0, placedTriangles = 0, failures = 0, skipped = 0}
-- Indexing a missing member errors on an Instance, so probe the API under pcall.
local available = pcall(function()
	assert(typeof(AssetService.CreateEditableMesh) == "function" and typeof(AssetService.CreateMeshPartAsync) == "function")
	assert(Content ~= nil and Content.fromObject ~= nil)
end)
local stopReason = if available then nil else "unavailable"
local newTemplatesBlocked = false
local templates = {} -- key -> {part, mesh, extent, center, triangles} | false (failed)

-- Colours ------------------------------------------------------------------
local function paletteColor(catalog, index, tint)
	local tintIndex = catalog.tintIndex or 11
	if tint then
		if index == tintIndex then return tint end
		if catalog.tintDarkIndex and index == catalog.tintDarkIndex then
			local k = catalog.tintDark or 0.62
			return Color3.new(tint.R * k, tint.G * k, tint.B * k)
		end
		if catalog.tintLightIndex and index == catalog.tintLightIndex then
			return tint:Lerp(Color3.new(1, 1, 1), catalog.tintLight or 0.4)
		end
	end
	local hex = catalog.palette[index]
	local ok, color = pcall(Color3.fromHex, hex)
	return if ok then color else Color3.new(0.6, 0.6, 0.6)
end
local function defaultTint(data)
	if type(data.tint) == "string" then
		local ok, color = pcall(Color3.fromHex, data.tint)
		if ok then return color end
	end
	return nil
end

-- Geometry -----------------------------------------------------------------
local function bounds(data)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, xyz in ipairs(data.vertices) do
		local v = Vector3.new(xyz[1], xyz[2], xyz[3])
		lo, hi = lo:Min(v), hi:Max(v)
	end
	return lo, hi
end
-- Per-corner normals: area-weighted face normals averaged within the crease angle.
local function cornerNormals(data)
	local crease = tonumber(data.smooth) or 0
	local points = {}
	for i, xyz in ipairs(data.vertices) do points[i] = Vector3.new(xyz[1], xyz[2], xyz[3]) end
	local faceNormal, faceWeight, around = {}, {}, {}
	for f, face in ipairs(data.faces) do
		local raw = (points[face[2]] - points[face[1]]):Cross(points[face[3]] - points[face[1]])
		faceWeight[f] = raw.Magnitude
		faceNormal[f] = if raw.Magnitude > 0 then raw.Unit else Vector3.yAxis
		for k = 1, 3 do
			local list = around[face[k]]
			if not list then list = {}; around[face[k]] = list end
			table.insert(list, f)
		end
	end
	local limit = math.cos(math.rad(crease))
	local result = {}
	for f, face in ipairs(data.faces) do
		local n = faceNormal[f]
		if crease <= 0 then
			result[f] = {n, n, n}
		else
			local corners = {}
			for k = 1, 3 do
				local sum = Vector3.zero
				for _, other in ipairs(around[face[k]]) do
					if faceNormal[other]:Dot(n) >= limit then sum += faceNormal[other] * faceWeight[other] end
				end
				corners[k] = if sum.Magnitude > 0 then sum.Unit else n
			end
			result[f] = corners
		end
	end
	return result
end

local function buildTemplate(shapeName, data, catalog, tint)
	local mesh
	local ok, result = pcall(function()
		mesh = AssetService:CreateEditableMesh()
		assert(mesh, "CreateEditableMesh returned nil")
		local ids = {}
		for i, xyz in ipairs(data.vertices) do ids[i] = mesh:AddVertex(Vector3.new(xyz[1], xyz[2], xyz[3])) end
		local colorIds, normalIds = {}, {}
		local normals = cornerNormals(data)
		for f, face in ipairs(data.faces) do
			local shade = face[4]
			local colorId = colorIds[shade]
			if not colorId then
				colorId = mesh:AddColor(paletteColor(catalog, shade, tint), 1)
				colorIds[shade] = colorId
			end
			local triangle = mesh:AddTriangle(ids[face[1]], ids[face[2]], ids[face[3]])
			mesh:SetFaceColors(triangle, {colorId, colorId, colorId})
			local corner = {}
			for k, n in ipairs(normals[f]) do
				local key = string.format("%.3f,%.3f,%.3f", n.X, n.Y, n.Z)
				local id = normalIds[key]
				if not id then id = mesh:AddNormal(n); normalIds[key] = id end
				corner[k] = id
			end
			mesh:SetFaceNormals(triangle, corner)
		end
		local content = Content.fromObject(mesh)
		local okOptions, part = pcall(AssetService.CreateMeshPartAsync, AssetService, content, {CollisionFidelity = Enum.CollisionFidelity.Box})
		if not okOptions or not part then part = AssetService:CreateMeshPartAsync(content) end
		assert(part and part:IsA("MeshPart"), "CreateMeshPartAsync returned no MeshPart")
		part.Name = shapeName
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.new(1, 1, 1)
		return part
	end)
	if ok then return result, mesh end
	if mesh then pcall(mesh.Destroy, mesh) end
	return nil, nil, tostring(result)
end

local function template(shapeName, data, catalog, tint)
	local key = shapeName .. "#" .. (if tint then tint:ToHex() else "")
	local cached = templates[key]
	if cached ~= nil then return cached or nil end
	local triangles = #data.faces
	if stopReason or newTemplatesBlocked or stats.templates >= LIMITS.templates or stats.templateTriangles + triangles > LIMITS.templateTriangles then
		return nil, "budget"
	end
	local part, mesh, problem = buildTemplate(shapeName, data, catalog, tint)
	if not part then
		templates[key] = false
		stats.failures += 1
		local message = string.lower(problem or "")
		if message:find("budget", 1, true) or message:find("memory", 1, true) or message:find("limit", 1, true) then newTemplatesBlocked = true end
		if stats.failures >= LIMITS.failures then stopReason = "unavailable" end
		warn("[MeshForge] " .. shapeName .. " could not be meshed: " .. tostring(problem))
		return nil, "failed"
	end
	local lo, hi = bounds(data)
	local entry = {part = part, mesh = mesh, extent = (hi - lo):Max(Vector3.one * 0.01), center = (lo + hi) / 2, triangles = triangles}
	part.Size = entry.extent
	templates[key] = entry
	stats.templates += 1
	stats.templateTriangles += triangles
	return entry
end

-- Signs: the original board keeps its SurfaceGui (the meshed frame wraps it);
-- text gets one consistent, higher-contrast style.
local SIGN_KINDS = {sign = true}
local fonts
local function signFonts()
	if fonts == nil then
		fonts = false
		pcall(function()
			fonts = {
				title = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
				body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
			}
		end)
	end
	return fonts or nil
end
local INK = Color3.fromRGB(12, 18, 26)
local function luminance(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
local function styleSign(part)
	for _, gui in ipairs(part:GetDescendants()) do
		if gui:IsA("SurfaceGui") and not gui:GetAttribute("SignStyled") then
			gui:SetAttribute("SignStyled", true)
			pcall(function() gui.LightInfluence = 0 end)
			for _, label in ipairs(gui:GetDescendants()) do
				if label:IsA("TextLabel") or label:IsA("TextButton") then
					local height = label.Size.Y.Offset
					local title = height >= 44 or (not label.TextScaled and label.TextSize >= 30)
					local chosen = signFonts()
					if chosen then pcall(function() label.FontFace = if title then chosen.title else chosen.body end) end
					if luminance(label.TextColor3) < 0.45 then label.TextColor3 = label.TextColor3:Lerp(Color3.new(1, 1, 1), 0.55) end
					if label.TextScaled and height > 0 and not label:FindFirstChildOfClass("UITextSizeConstraint") then
						local limit = Instance.new("UITextSizeConstraint")
						limit.MaxTextSize = math.max(12, math.floor(height * 0.8))
						limit.Parent = label
					end
					if not label:FindFirstChildOfClass("UIStroke") then
						local stroke = Instance.new("UIStroke")
						stroke.Color = INK
						stroke.Thickness = if title then 2 else 1.25
						stroke.Transparency = 0.35
						stroke.Parent = label
					end
				end
			end
		end
	end
end

-- Placement ----------------------------------------------------------------
local registry = setmetatable({}, {__mode = "k"}) -- tagged parts this client knows
local placed = setmetatable({}, {__mode = "k"}) -- part -> {visual, triangles, connections, decals}
local final = setmetatable({}, {__mode = "k"}) -- permanently skipped parts
local function skip(part, reason, permanent)
	if permanent then final[part] = true end
	if part:GetAttribute("ShapeSkipped") ~= reason then
		stats.skipped += 1
		pcall(part.SetAttribute, part, "ShapeSkipped", reason)
	end
end
local function placement(part, data, entry)
	local shapeScale = part:GetAttribute("ShapeScale")
	shapeScale = if type(shapeScale) == "number" and shapeScale > 0 and shapeScale <= 100 then shapeScale else 1
	local lo, hi
	if type(data.fit) == "table" and type(data.fit[1]) == "table" and type(data.fit[2]) == "table" then
		lo, hi = Vector3.new(table.unpack(data.fit[1])), Vector3.new(table.unpack(data.fit[2]))
	else
		lo, hi = entry.center - entry.extent / 2, entry.center + entry.extent / 2
	end
	local fitSize = (hi - lo):Max(Vector3.one * 0.01)
	local target = (part.Size * shapeScale):Max(Vector3.one * 0.05)
	local k = target / fitSize
	if part:GetAttribute("ShapeFit") == "Uniform" then
		local m = math.min(k.X, k.Y, k.Z)
		k = Vector3.new(m, m, m)
	end
	return entry.extent * k, CFrame.new((entry.center - (lo + hi) / 2) * k)
end

-- Release a placed mesh and give the primitive back (removal, distance, shutdown).
local function release(part)
	local record = placed[part]
	if not record then return end
	placed[part] = nil
	stats.instances -= 1
	stats.placedTriangles -= record.triangles
	for _, connection in ipairs(record.connections) do connection:Disconnect() end
	pcall(function() part.LocalTransparencyModifier = 0 end)
	for _, decal in ipairs(record.decals) do pcall(function() decal.LocalTransparencyModifier = 0 end) end
	local link = part:FindFirstChild("ShapeMesh")
	if link then link:Destroy() end
	pcall(part.SetAttribute, part, "ShapeDone", nil)
	pcall(record.visual.Destroy, record.visual)
end

local function forge(part)
	if placed[part] or final[part] or not part.Parent then return end
	local shapeName = part:GetAttribute("Shape")
	if type(shapeName) ~= "string" then return end
	if part:GetAttribute("SculptureScale") ~= nil and part:GetAttribute("ShapeScale") == nil then skip(part, "legacy sculpture", true); return end
	local data, catalog = lookup(shapeName)
	if not data then skip(part, "unknown shape", true); return end
	if stopReason then skip(part, stopReason, true); return end
	if stats.instances >= LIMITS.instances or stats.placedTriangles + #data.faces > LIMITS.placedTriangles then skip(part, "budget"); return end
	local tint = part:GetAttribute("Tint")
	if typeof(tint) ~= "Color3" then tint = defaultTint(data) end
	local entry, problem = template(shapeName, data, catalog, tint)
	if not entry and problem == "budget" then
		-- Reuse the shape's default-tint template rather than leaving a primitive.
		local fallback = defaultTint(data)
		local cached = templates[shapeName .. "#" .. (if fallback then fallback:ToHex() else "")]
		if cached then entry = cached end
	end
	if not entry then skip(part, problem or stopReason or "failed", problem ~= "budget"); return end
	if not part.Parent then return end
	local size, offset = placement(part, data, entry)
	local ok, visual = pcall(function()
		local clone = entry.part:Clone()
		clone.Name = part.Name .. " Mesh"
		clone.Size = size
		clone.CFrame = part.CFrame * offset
		clone:SetAttribute("ShapeOf", shapeName)
		clone.Parent = part.Parent
		return clone
	end)
	if not ok or not visual then skip(part, "clone failed", true); return end
	local record = {visual = visual, triangles = entry.triangles, connections = {}, decals = {}}
	placed[part] = record
	stats.instances += 1
	stats.placedTriangles += entry.triangles
	-- Hide the primitive for this client only, now that its mesh exists.
	pcall(function() part.LocalTransparencyModifier = 1 end)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") then
			table.insert(record.decals, child)
			pcall(function() child.LocalTransparencyModifier = 1 end)
		end
	end
	local link = Instance.new("ObjectValue")
	link.Name = "ShapeMesh"
	link.Value = visual
	link.Parent = part
	part:SetAttribute("ShapeSkipped", nil)
	part:SetAttribute("ShapeDone", true)
	pcall(function()
		table.insert(record.connections, part:GetPropertyChangedSignal("CFrame"):Connect(function() visual.CFrame = part.CFrame * offset end))
		table.insert(record.connections, part.AncestryChanged:Connect(function() if not part:IsDescendantOf(workspace) then release(part) end end))
	end)
end

-- Distance streaming --------------------------------------------------------
local function focus()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then return root.CFrame.Position end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end
local stepping = false
local function step()
	if stepping then return end
	stepping = true
	local origin = focus()
	if origin then
		local near = {}
		for part in pairs(registry) do
			if not part.Parent then
				registry[part] = nil
				release(part)
			else
				local distance = (part.CFrame.Position - origin).Magnitude
				if placed[part] then
					if distance > UNLOAD_RADIUS then release(part) end
				elseif not final[part] and distance <= BUILD_RADIUS then
					table.insert(near, {part, distance})
				end
			end
		end
		-- Nearest first, so budgets are spent on what the player sees.
		table.sort(near, function(a, b) return a[2] < b[2] end)
		for _, item in ipairs(near) do
			local ok, problem = pcall(forge, item[1])
			if not ok then warn("[MeshForge] " .. tostring(problem)); skip(item[1], "error", true) end
		end
	end
	stepping = false
end
local function consider(part)
	if registry[part] or typeof(part) ~= "Instance" or not part:IsA("BasePart") or type(part:GetAttribute("Shape")) ~= "string" then return end
	registry[part] = true
	local data = lookup(part:GetAttribute("Shape"))
	if data and SIGN_KINDS[data.kind] then pcall(styleSign, part) end
	task.defer(step)
end
local function watch(instance)
	if not instance:IsA("BasePart") or registry[instance] then return end
	if instance:GetAttribute("Shape") ~= nil then consider(instance); return end
	pcall(function()
		instance:GetAttributeChangedSignal("Shape"):Once(function() consider(instance) end)
	end)
end
local function rescan()
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and not registry[instance] and instance:GetAttribute("Shape") ~= nil then consider(instance) end
	end
end

workspace.DescendantAdded:Connect(function(instance) task.defer(watch, instance) end)
for _, instance in ipairs(workspace:GetDescendants()) do watch(instance) end
step()
if MeshForgeTest then
	MeshForgeTest.forge = {stats = stats, limits = LIMITS, templates = templates, rescan = rescan, consider = consider, step = step,
		cornerNormals = cornerNormals, styleSign = styleSign, stopReason = function() return stopReason end,
		radii = {build = BUILD_RADIUS, unload = UNLOAD_RADIUS}}
	return
end
print(string.format("[MeshForge] %s: %d templates (%d tris cached), %d meshes placed (%d tris), %d skipped",
	if stopReason then stopReason else "ready", stats.templates, stats.templateTriangles, stats.instances, stats.placedTriangles, stats.skipped))
task.spawn(function()
	local elapsed = 0
	while true do
		task.wait(STEP_SECONDS)
		elapsed += STEP_SECONDS
		if elapsed >= 20 then elapsed = 0; rescan() end -- safety net for missed attribute changes
		step()
	end
end)
script.Destroying:Once(function()
	for part in pairs(placed) do release(part) end
	for _, entry in pairs(templates) do
		if entry then
			pcall(entry.part.Destroy, entry.part)
			if entry.mesh then pcall(entry.mesh.Destroy, entry.mesh) end
		end
	end
end)
