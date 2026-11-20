-- Run from the project directory after building with Rojo.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local place = roblox.deserializePlace(fs.readFile("Aether-Isles.rbxl"))
local bindings = {
	Adventure = "server.server.lua", Archipelago = "world.server.lua",
	Observatory = "expedition.server.lua", Assembly = "festival.server.lua",
	Homesteads = "coop.server.lua", Combat = "combat.server.lua",
	FieldGuide = "ui.client.lua", IslandArt = "mesh.client.lua", CombatInput = "combat.client.lua", IslandBuilder = "build.client.lua",
	AetherArt = "art/PropCatalog.lua",
	MaterialArt = "art/MaterialArt.lua",
	AetherData = "shared/GameData.lua", AetherProgression = "shared/Progression.lua",
}
local count = 0
for _, obj in place:GetDescendants() do
	local file = bindings[obj.Name]
	if not file then continue end
	assert(obj.Source:gsub("\r\n","\n") == fs.readFile(file):gsub("\r\n","\n"), file .. " is stale")
	local client = file:find(".client.", 1, true)
	local shared = obj.Name=="AetherArt" or obj.Name=="MaterialArt" or obj.Name=="AetherData" or obj.Name=="AetherProgression"
	assert(obj.ClassName == (if shared then "ModuleScript" elseif client then "LocalScript" else "Script"))
	assert(obj.Parent.Name == (if shared then "ReplicatedStorage" elseif client then "StarterPlayerScripts" else "ServerScriptService"))
	assert(#luau.compile(obj.Source) > 0)
	bindings[obj.Name] = nil
	count += 1
end
assert(next(bindings) == nil, "Missing script")
-- The procedural cloth is allocated lazily once and fails without breaking UI.
local materialSource=fs.readFile("art/MaterialArt.lua")
local creations,writes,destroys=0,0,0
local captured
local editable={WritePixelsBuffer=function(_,_,size,pixels)
	assert(size.X==128 and size.Y==128 and buffer.len(pixels)==128*128*4)
	captured=pixels; writes+=1
end,Destroy=function() destroys+=1 end}
local function materialEnvironment(create,content)
	return {game={GetService=function() return {CreateEditableImage=create} end},
		Vector2=roblox.Vector2,Content={fromObject=content}}
end
local cloth=luau.load(materialSource,{environment=materialEnvironment(function()
	creations+=1; return editable
end,function(image) assert(image==editable); return "test-content" end),injectGlobals=true})()
assert(creations==0,"cloth must be lazy")
assert(cloth.getGuiContent()=="test-content" and cloth.getGuiContent()=="test-content")
assert(creations==1 and writes==1 and destroys==0,"all GUI uses share one retained image")
assert(buffer.readu8(captured,0)==223 and buffer.readu8(captured,4)==213,"loom formula matches original tile samples")
for offset=3,buffer.len(captured)-1,4 do assert(buffer.readu8(captured,offset)==255,"opaque cloth pixels") end
local failures=0
local unavailable=luau.load(materialSource,{environment=materialEnvironment(function()
	failures+=1; error("image budget unavailable")
end,function() error("unexpected content") end),injectGlobals=true})()
assert(unavailable.getGuiContent()==nil and unavailable.getGuiContent()==nil and failures==1,"failed allocation is bounded and safe")
local invalidContent=luau.load(materialSource,{environment=materialEnvironment(function() return editable end,
	function() error("content unavailable") end),injectGlobals=true})()
assert(invalidContent.getGuiContent()==nil and destroys==1,"partial failure releases image")
print("Verified production source, placement, and Luau compilation for " .. count .. " scripts.")
print("Verified lazy shared procedural cloth and bounded allocation failures.")
