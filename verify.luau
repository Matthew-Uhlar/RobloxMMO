-- Run from the project directory after building with Rojo.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local place = roblox.deserializePlace(fs.readFile("Aether-Isles.rbxl"))
local bindings = {
	Adventure = "server.server.lua", Archipelago = "world.server.lua",
	Observatory = "expedition.server.lua", Assembly = "festival.server.lua",
	Homesteads = "coop.server.lua",
	FieldGuide = "ui.client.lua", IslandArt = "mesh.client.lua",
	AetherArt = "art/PropCatalog.lua",
}
local count = 0
for _, obj in place:GetDescendants() do
	local file = bindings[obj.Name]
	if not file then continue end
	assert(obj.Source:gsub("\r\n","\n") == fs.readFile(file):gsub("\r\n","\n"), file .. " is stale")
	local client = file:find(".client.", 1, true)
	local shared = obj.Name=="AetherArt"
	assert(obj.ClassName == (if shared then "ModuleScript" elseif client then "LocalScript" else "Script"))
	assert(obj.Parent.Name == (if shared then "ReplicatedStorage" elseif client then "StarterPlayerScripts" else "ServerScriptService"))
	assert(#luau.compile(obj.Source) > 0)
	bindings[obj.Name] = nil
	count += 1
end
assert(next(bindings) == nil, "Missing script")
print("Verified production source, placement, and Luau compilation for " .. count .. " scripts.")
