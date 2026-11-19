-- From the repository root: lune run art/import/prepare-templates.luau RawImport.rbxm Templates.rbxm
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local args = require("@lune/process").args

local input, output = args[1], args[2]
assert(input and output and input:lower() ~= output:lower(), "Supply separate input and output model paths")
assert(output:lower():match("%.rbxm$"), "Use .rbxm for the output")

local roots = roblox.deserializeModel(fs.readFile(input))
assert(#roots == 1, "Export the imported library as one model")
local library = roots[1]
local glb = buffer.fromstring(fs.readFile("art/import/Aether-Isles-Originals.glb"))
local jsonLength = buffer.readu32(glb, 12)
local gltf = serde.decode("json", buffer.readstring(glb, 20, jsonLength))
local templates = roblox.Instance.new("Folder")
templates.Name = "AetherMeshTemplates"
local count = 0

local function vector(values)
	return roblox.Vector3.new(values[1], values[2], values[3])
end

for _, node in gltf.nodes do
	local imported = library:FindFirstChild(node.name)
	assert(imported and imported:IsA("Model"), "Missing imported shape " .. node.name)
	local mesh = gltf.meshes[node.mesh + 1]
	assert(#imported:GetChildren() == #mesh.primitives, "Unexpected part count in " .. node.name)
	local template = roblox.Instance.new("Model")
	template.Name = node.name
	for index, primitive in mesh.primitives do
		local name = mesh.name .. (if index == 1 then "" else tostring(index))
		local part = imported:FindFirstChild(name)
		assert(part and part:IsA("MeshPart") and #part:GetChildren() == 0, "Unexpected mesh or children at " .. name)
		local bounds = gltf.accessors[primitive.attributes.POSITION + 1]
		local low = vector(bounds.min) / node.extras.metersPerStud
		local high = vector(bounds.max) / node.extras.metersPerStud
		assert((part.Size - (high - low)).Magnitude < 0.001, "Unexpected import scale or primitive order at " .. name)
		local rotation = part.CFrame - part.CFrame.Position
		assert(rotation == roblox.CFrame.identity, "Unexpected import rotation at " .. name)
		local material = gltf.materials[primitive.material + 1]
		local surface = part:Clone()
		surface.CFrame = roblox.CFrame.new((low + high) / 2)
		surface.Color = roblox.Color3.new(table.unpack(material.extras.sourceSrgb))
		surface:SetAttribute("OriginalMaterial", material.name)
		surface.Anchored = true
		surface.CanCollide = false
		surface.CanTouch = false
		surface.CanQuery = false
		surface.Parent = template
		count += 1
	end
	template.WorldPivotData = roblox.CFrame.identity
	template.Parent = templates
end

local bytes = roblox.serializeModel({ templates })
local checked = roblox.deserializeModel(bytes)[1]
assert(#checked:GetChildren() == #gltf.nodes and #checked:GetDescendants() == #gltf.nodes + count)
fs.writeFile(output, bytes)
print(string.format("Prepared %d original templates and %d colored mesh parts in %s", #gltf.nodes, count, output))
