-- Execute production world generation with real Roblox datatypes and instances.
-- Signals and players are deterministic doubles. Physics/rendering need Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local connection = {Connected=true}
			function connection:Disconnect() self.Connected=false end
			table.insert(listeners,{callback,connection})
			return connection
		end,
		Fire = function(_, ...)
			for _, listener in listeners do
				if listener[2].Connected then listener[1](...) end
			end
		end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt]=signal() end
	return promptSignals[prompt]
end)
local players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end}
local tags={}
local services={
	Players=players,
	Lighting=roblox.Instance.new("Lighting"),
	CollectionService={AddTag=function(_,obj,tag)
		tags[tag]=tags[tag] or {}
		table.insert(tags[tag],obj)
	end},
}
local world=roblox.Instance.new("Workspace")
local environment={
	game={GetService=function(_,name) return services[name] end},
	workspace=world,Instance=roblox.Instance,Vector3=roblox.Vector3,
	Vector2=roblox.Vector2,CFrame=roblox.CFrame,Color3=roblox.Color3,
	UDim2=roblox.UDim2,Enum=roblox.Enum,task={spawn=function(fn,...) fn(...) end},
}
local source=fs.readFile("world.server.lua")
-- Lune does not synthesize BasePart.Position from CFrame as the engine does.
source=source:gsub("plans%.Position","plans.CFrame.Position")
luau.load(source,{environment=environment,injectGlobals=true})()
local function player(id,attributes)
	local changed={}
	local p={UserId=id,CharacterAdded=signal(),attributes=attributes or {}}
	function p:GetAttribute(key) return self.attributes[key] end
	function p:GetAttributeChangedSignal(key)
		changed[key]=changed[key] or signal()
		return changed[key]
	end
	function p:SetAttribute(key,value)
		self.attributes[key]=value
		self:GetAttributeChangedSignal(key):Fire()
	end
	players.PlayerAdded:Fire(p)
	return p
end
local checks=0
local function check(condition,label)
	assert(condition,label)
	checks+=1
end
local archipelago=world:FindFirstChild("AetherIsles")
check(archipelago~=nil,"world created")
local a=player(11)
local b=player(22,{HomeGarden=true,HomeDeck=true,Worker1Tier=1,Worker1Resource="Fish",Worker2Tier=3,Worker2Resource="Herb"})
local homeA=archipelago:FindFirstChild("WayfarersRest_11")
local homeB=archipelago:FindFirstChild("WayfarersRest_22")
check(homeA~=nil and homeB~=nil,"separate homes")
check((a.RespawnLocation.Position-b.RespawnLocation.Position).Magnitude>=60,"home spacing")
check(homeA:FindFirstChild("Garden")==nil,"unowned garden absent")
check(homeB:FindFirstChild("Garden")~=nil,"saved garden restored")
check(homeB:FindFirstChild("Deck")~=nil,"saved deck restored")
a:SetAttribute("HomeLanterns",true)
check(homeA:FindFirstChild("Lanterns")~=nil,"purchase changes world")
local size=#homeA:GetDescendants()
a:SetAttribute("HomeLanterns",true)
check(#homeA:GetDescendants()==size,"repeat update cannot duplicate geometry")
for _,obj in homeA:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") then
		check(obj:GetAttribute("OwnerUserId")==11,"private interaction owner")
	end
end
for slot=1,3 do
	local station=homeA:FindFirstChild("WorkerStation"..slot)
	check(station~=nil,"three fixed worker stations exist")
	local chassis=station:FindFirstChild("Surveyor chassis")
	local interaction=chassis:FindFirstChildOfClass("ProximityPrompt")
	check(interaction:GetAttribute("OwnerUserId")==11,"worker interaction owner")
	check(interaction:GetAttribute("IsleItem")==tostring(slot),"worker slot identifier")
	check(interaction:GetAttribute("IsleAction")== (if slot==1 then "worker" else "workerBuild"),"unbuilt chassis builds correct slot")
	local offset=station:FindFirstChild("Worker pad").CFrame.Position-homeA:FindFirstChild("Meadow").CFrame.Position
	check(math.sqrt(offset.X^2+offset.Z^2)+2.3<19,"worker pad stays on home island")
	a:SetAttribute("Worker"..slot.."Tier",2)
	a:SetAttribute("Worker"..slot.."Resource","Timber")
	check(interaction:GetAttribute("IsleAction")=="workerClaim","built worker switches to claim")
	check(interaction.ObjectText:find("Timber",1,true)~=nil,"resource update changes prompt")
	local status=chassis:FindFirstChild("Worker status"):FindFirstChildOfClass("TextLabel")
	check(status.Text:find("TIER 2",1,true)~=nil and status.Text:find("Timber",1,true)~=nil,"worker tier and assignment displayed")
end
local savedWorker=homeB:FindFirstChild("WorkerStation2"):FindFirstChild("Surveyor chassis")
check(savedWorker:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("IsleAction")=="workerClaim","saved worker restored as active")
check(savedWorker:FindFirstChild("Worker status"):FindFirstChildOfClass("TextLabel").Text:find("TIER 3",1,true)~=nil,"saved tier restored")
local cache=homeA:FindFirstChild("WorkerStation1"):FindFirstChild("Surveyor cache"):FindFirstChildOfClass("ProximityPrompt")
check(cache.Enabled and cache:GetAttribute("IsleAction")=="claim","first worker cache keeps legacy claim action")
local parts,prompts,signs=0,0,0
a:SetAttribute("CoopId","11")
b:SetAttribute("CoopId","11")
local shared=archipelago:FindFirstChild("CrewHaven_11")
check(shared~=nil,"crew gets a shared island")
local sharedCount=0
for _,model in archipelago:GetChildren() do if model.Name=="CrewHaven_11" then sharedCount+=1 end end
check(sharedCount==1,"members share one island")
local supplyCount=0
for _,obj in shared:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleCoopResource") then
		supplyCount+=1
		check(obj:GetAttribute("CoopId")=="11","shared supply group binding")
		check(obj:GetAttribute("IsleAction")==nil,"shared supplies never award personal inventory")
	end
end
check(supplyCount==3,"crew has three construction supplies")
b:SetAttribute("CoopGarden",true)
check(shared:FindFirstChild("Garden")~=nil,"crew purchase appears for all members")
local beforeShared=#shared:GetDescendants()
a:SetAttribute("CoopGarden",true)
check(#shared:GetDescendants()==beforeShared,"repeated shared build cannot duplicate geometry")
a:SetAttribute("CoopId",nil)
check(archipelago:FindFirstChild("CrewHaven_11")==shared,"remaining member retains shared island")
b:SetAttribute("CoopId",nil)
check(archipelago:FindFirstChild("CrewHaven_11")==nil,"last member departure cleans shared island")
b:SetAttribute("CoopId","11")
check(archipelago:FindFirstChild("CrewHaven_11"):FindFirstChild("Garden")~=nil,"shared decoration restores from server flags")
a:SetAttribute("CoopPreview",true)
a:SetAttribute("CoopId","11")
check(archipelago:FindFirstChild("CrewHaven_preview_11")~=nil,"preview crew gets separate geometry")
check(archipelago:FindFirstChild("CrewHaven_11")~=nil,"durable crew survives preview join")
for _,obj in archipelago:FindFirstChild("CrewHaven_preview_11"):GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleCoopResource") then
		check(obj:GetAttribute("CoopPreview")==true,"preview supply prompt is environment bound")
	end
end
a:SetAttribute("CoopId",nil)
for _,obj in world:GetDescendants() do
	if obj:IsA("BasePart") then
		parts+=1
		check(obj.Size.X>0 and obj.Size.Y>0 and obj.Size.Z>0,"positive geometry")
	elseif obj:IsA("ProximityPrompt") then
		prompts+=1
		check(obj.Parent:IsA("BasePart"),"prompt has physical target")
	elseif obj:IsA("SurfaceGui") then
		signs+=1
	end
end
check(parts>300 and prompts>=25 and signs>=20,"world landmarks and interactions exist")
check(#tags.AetherSculpture>=30,"custom world sculptures registered")
local observatoryGate=world:FindFirstChild("ExpeditionGate",true)
check(observatoryGate:GetAttribute("Shape")=="ObservatoryArch","expedition entrance uses authored gate arch")
check(observatoryGate.Transparency==1 and not observatoryGate.CanCollide,"gate art preserves open transit collider")
local advancedOre=world:FindFirstChild("Aetherite seam",true)
check(advancedOre~=nil,"advanced mining node exists")
check(advancedOre:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("IsleItem")=="Aetherite","advanced mining routes to validated server action")
local gate=world:FindFirstChild("ExpeditionGate",true)
check(gate~=nil and gate.CFrame.Position.Y>=0,"expedition entrance accessible")
local oldSpawn=a.RespawnLocation.Position
players.PlayerRemoving:Fire(a)
check(archipelago:FindFirstChild("WayfarersRest_11")==nil,"leave cleans island")
local c=player(33)
check(c.RespawnLocation.Position==oldSpawn,"vacated slot reused")
local meshSource=fs.readFile("mesh.client.lua")
check(#luau.compile(meshSource)>0,"complete mesh renderer compiles with bounded fallback")
local meshData=meshSource:match("(local palette = .-)local function wedgeFace")
check(meshData~=nil,"embedded mesh data present")
local shapes,palette=luau.load(meshData.."\nreturn shapes,palette",{
	environment={Color3=roblox.Color3},injectGlobals=true,
})()
local catalog=luau.load(fs.readFile("art/PropCatalog.lua"),{injectGlobals=true})()
local proxySource=meshSource:match("%-%- BEGIN BOUNDED PROXIES(.-)%-%- END BOUNDED PROXIES")
check(proxySource~=nil,"bounded fallback source available")
local makeProxy=luau.load("local palette=...\n"..proxySource.."\nreturn makeProxy",{
	environment={Instance=roblox.Instance,Vector3=roblox.Vector3,CFrame=roblox.CFrame,Enum=roblox.Enum},injectGlobals=true,
})(palette)
local proxyLimits={ObservatoryArch=16,EclipseAstrolabe=18,ObservatorySentinel=18,AetherCrystal=4}
for shape,limit in pairs(proxyLimits) do
	local proxy=makeProxy(shape,1.4)
	check(proxy:GetAttribute("BoundedProxy")==true,shape.." has bounded fallback")
	check(#proxy:GetChildren()==limit,shape.." stays within authored primitive budget")
	for _,part in ipairs(proxy:GetChildren()) do
		check(part:IsA("Part") and not part:IsA("WedgePart"),shape.." avoids per-triangle wedges")
		check(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery,shape.." proxy cannot alter gameplay physics")
	end
	proxy:Destroy()
end
check(makeProxy("Tidewing",1)==nil,"unrelated native/creature meshes remain unchanged")
local festival=luau.load(fs.readFile("festival.server.lua"),{environment={
	game={GetService=function() return players end},workspace=world,Instance=roblox.Instance,
	Vector3=roblox.Vector3,Vector2=roblox.Vector2,CFrame=roblox.CFrame,Color3=roblox.Color3,UDim2=roblox.UDim2,Enum=roblox.Enum,
	task={wait=function() coroutine.yield() end},
},injectGlobals=true})
check(coroutine.resume(coroutine.create(festival)),"festival starts with fixed sign")
local assembly=world:FindFirstChild("Island Assembly")
check(assembly:FindFirstChildOfClass("BillboardGui")==nil,"festival sign cannot float over expedition gate")
local assemblySign=assembly:FindFirstChildOfClass("SurfaceGui")
check(assemblySign~=nil and not assemblySign.AlwaysOnTop and assemblySign.Face==roblox.Enum.NormalId.Back,"assembly uses physical hub-facing sign")
check((assembly.CFrame.Position-gate.CFrame.Position).Magnitude>15,"assembly moved away from gate sightline")
local meshNames={"Tidewing","Shellwarden"}
for name in pairs(catalog.shapes) do table.insert(meshNames,name) end
for _,name in meshNames do
	local vertices,faces={},{}
	local body=fs.readFile("art/"..name..".obj")
	for line in body:gmatch("[^\r\n]+") do
		local x,y,z=line:match("^v ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+)")
		if x then table.insert(vertices,roblox.Vector3.new(tonumber(x),tonumber(y),tonumber(z))) end
		local i,j,k=line:match("^f (%d+) (%d+) (%d+)")
		if i then table.insert(faces,{tonumber(i),tonumber(j),tonumber(k)}) end
	end
	check(#vertices>=12 and #faces>=12,name.." has triangle geometry")
	local embedded=shapes[name]
	check(#embedded.vertices==#vertices and #embedded.faces==#faces,name.." embedded geometry matches master counts")
	for index,vertex in vertices do
		local xyz=embedded.vertices[index]
		check(vertex==roblox.Vector3.new(table.unpack(xyz)),name.." master vertex parity")
	end
	for index,face in faces do
		local v1,v2,v3=vertices[face[1]],vertices[face[2]],vertices[face[3]]
		check(v1~=nil and v2~=nil and v3~=nil,name.." indices in range")
		check((v2-v1):Cross(v3-v1).Magnitude>0.00001,name.." nondegenerate face")
		local renderFace=embedded.faces[index]
		check(renderFace[1]==face[1] and renderFace[2]==face[2] and renderFace[3]==face[3],name.." master triangle parity")
		check(palette[renderFace[4]]~=nil,name.." valid face material")
	end
	print(name..": "..#vertices.." vertices / "..#faces.." triangles")
end
print("World QA passed "..checks.." checks with "..parts.." parts, "..prompts.." prompts and "..signs.." sign surfaces.")
