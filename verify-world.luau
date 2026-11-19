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
-- Shared data is the real module; region access is a recording double.
local Data=luau.load(fs.readFile("shared/GameData.lua"))()
local dataModule={Name="AetherData"}
local accessCalls,allowRegion={},{}
local regionAccess={Invoke=function(_,who,regionId)
	table.insert(accessCalls,{who,regionId})
	return {allowed=allowRegion[regionId]==true,message="Locked: "..tostring(regionId)}
end}
local services={
	Players=players,
	Lighting=roblox.Instance.new("Lighting"),
	CollectionService={AddTag=function(_,obj,tag)
		tags[tag]=tags[tag] or {}
		table.insert(tags[tag],obj)
	end},
	ReplicatedStorage={WaitForChild=function(_,name) return if name=="AetherData" then dataModule else nil end},
	ServerStorage={FindFirstChild=function(_,name) return if name=="IsleRegionAccess" then regionAccess else nil end},
}
local world=roblox.Instance.new("Workspace")
local environment={
	game={GetService=function(_,name) return services[name] end},
	workspace=world,Instance=roblox.Instance,Vector3=roblox.Vector3,
	Vector2=roblox.Vector2,CFrame=roblox.CFrame,Color3=roblox.Color3,
	UDim2=roblox.UDim2,Enum=roblox.Enum,task={spawn=function(fn,...) fn(...) end},
	NumberRange=roblox.NumberRange,NumberSequence=roblox.NumberSequence,ColorSequence=roblox.ColorSequence,
	require=function(module) assert(module==dataModule,"world requires only AetherData") return Data end,
}
local source=fs.readFile("world.server.lua")
-- Lune does not synthesize BasePart.Position from CFrame as the engine does.
source=source:gsub("plans%.Position","plans.CFrame.Position")
luau.load(source,{environment=environment,injectGlobals=true})()
local staticParts,staticLights=0,0
for _,obj in world:GetDescendants() do
	if obj:IsA("BasePart") then staticParts+=1 elseif obj:IsA("Light") then staticLights+=1 end
end
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
local proxyLimits={ObservatoryArch=16,EclipseAstrolabe=18,ObservatorySentinel=18,AetherCrystal=4,
	Lantern=8,WindpineCrown=4,Moonbloom=7,Pickaxe=3,Blade=4,Tonic=3,VaultChest=5,TimberBundle=5,
	Surveyor=5,Shellwarden=8,Tidewing=7}
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
check(makeProxy("Sword",1)==nil,"inventory-only meshes get no world proxy")
check(not meshSource:find('Instance.new%("WedgePart"%)'),"world props never fall back to per-triangle wedges")
check(meshSource:find("if visual then visual.Name")~=nil,"no mesh and no proxy leaves only the anchor geometry")
for _,anchor in ipairs(tags.AetherSculpture) do
	local ok,shape=pcall(anchor.GetAttribute,anchor,"Shape")
	if ok then check(proxyLimits[shape]~=nil,"world sculpture "..tostring(shape).." has a bounded proxy") end
end
check(proxyLimits.Tidewing~=nil,"companion Tidewing has a bounded proxy")
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

-- Depth update: regions, tiered nodes, monster grounds, stations, transit.
local Vec=roblox.Vector3.new
local VERB={Mining="Mine",Woodcutting="Chop",Fishing="Fish",Farming="Harvest"}
local function islandOf(obj)
	local node=obj
	while node and node.Parent~=archipelago do node=node.Parent end
	return node
end
local function onIsland(isle,pos,margin)
	local ground=isle and isle:FindFirstChild("Meadow")
	local radius=isle and isle:GetAttribute("IslandRadius")
	if not ground or not radius then return false end
	local c=ground.CFrame.Position
	return Vec(pos.X-c.X,0,pos.Z-c.Z).Magnitude<=radius-(margin or 0) and pos.Y>=c.Y-1 and pos.Y<=c.Y+12
end
local function onRegion(regionId,pos,margin)
	for _,isle in archipelago:GetChildren() do
		if isle:GetAttribute("RegionId")==regionId and onIsland(isle,pos,margin) then return true end
	end
	return false
end
check(staticParts<2500,"static world stays under the 2500 part budget ("..staticParts..")")
for _,obj in world:GetDescendants() do
	if obj:IsA("BasePart") then check(obj.Anchored,"every world part is anchored") end
end
for _,region in Data.Regions do
	local found=false
	for _,isle in archipelago:GetChildren() do if isle:GetAttribute("RegionId")==region.id then found=true end end
	check(found,region.id.." has a built island")
end
-- Every resource tier: at least one correctly attributed gather node.
local gatherNodes={}
for _,obj in world:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction")=="gather" and not obj:GetAttribute("OwnerUserId") then
		local id=obj:GetAttribute("IsleItem")
		gatherNodes[id]=gatherNodes[id] or {}
		table.insert(gatherNodes[id],obj)
	end
end
local tierCount,nodeCount=0,0
for skill,tiers in Data.ResourceTiers do
	for _,def in tiers do
		tierCount+=1
		local nodes=gatherNodes[def.id]
		check(nodes~=nil and #nodes>=1,def.id.." has a gather node")
		local formatted,ungated=false,false
		for _,q in nodes do
			nodeCount+=1
			local target=q.Parent:GetAttribute("ResourceId")
			check(target==nil or target==def.id,def.id.." node target matches")
			if q.ObjectText==def.name.." (Lv "..def.level..")" and q.ActionText==VERB[skill] then formatted=true end
			local isle=islandOf(q)
			local host=isle and isle:GetAttribute("RegionId")
			check(host~=nil,def.id.." node sits on a region island")
			local region=q:GetAttribute("IsleRegion")
			if region then
				check(Data.RegionById[region]~=nil,def.id.." node names a valid region")
				check(region==host,def.id.." node region matches its island")
			else
				ungated=true
			end
			if next(Data.RegionById[host].requires) then check(region==host,def.id.." node on a gated island carries IsleRegion") end
			check(onIsland(isle,q.Parent.CFrame.Position,1),def.id.." node stands on its island")
		end
		check(formatted,def.id.." has a '"..VERB[skill].."' prompt labelled with name and level")
		if def.level<=3 then check(ungated,def.id.." is available near home without a gate") end
		if def.level>=30 then check(not ungated,def.id.." lives in a gated region") end
	end
end
-- Every monster: spawn markers in its region on open ground.
local spawnFolder=world:FindFirstChild("MonsterSpawns")
check(spawnFolder~=nil and spawnFolder:IsA("Folder"),"Workspace.MonsterSpawns folder exists")
local markerCount,markers={},0
local floors={Meadow=true,["Floating foundation"]=true,["Grassy hillock"]=true,["Edge guard"]=true,["Hall floor"]=true,["Guild court"]=true,["Cavern roof"]=true}
for _,marker in spawnFolder:GetChildren() do
	markers+=1
	check(marker:IsA("BasePart") and marker.Anchored and not marker.CanCollide and not marker.CanTouch and marker.Transparency==1,"spawn marker is invisible, anchored and non-colliding")
	local id=marker:GetAttribute("MonsterId")
	local def=Data.Monsters[id]
	check(def~=nil,"spawn marker names a known monster")
	check(marker:GetAttribute("Region")==def.region,id.." marker region matches data")
	local count=marker:GetAttribute("Count")
	check(type(count)=="number" and count>=1 and count<=4,id.." marker has a sane count")
	local pos=marker.CFrame.Position
	check(onRegion(def.region,pos,marker:GetAttribute("Radius") or 0),id.." marker and its roam radius sit inside "..def.region)
	local isle
	for _,candidate in archipelago:GetChildren() do
		if candidate:GetAttribute("RegionId")==def.region and onIsland(candidate,pos) then isle=candidate end
	end
	for _,obj in isle:GetDescendants() do
		if obj:IsA("BasePart") and obj.CanCollide and not floors[obj.Name] then
			local d=obj.CFrame.Position-pos
			check(Vec(d.X,0,d.Z).Magnitude>=4.5,id.." spawns on open ground (clear of "..obj.Name..")")
		end
	end
	markerCount[id]=(markerCount[id] or 0)+1
end
for id in Data.Monsters do check(markerCount[id]~=nil,id.." has a spawn marker") end
-- Warps: every beacon asks the authoritative region check with a valid id.
local function traveller()
	local t={attributes={}}
	function t:GetAttribute(key) return self.attributes[key] end
	function t:SetAttribute(key,value) self.attributes[key]=value end
	return t
end
local function standAt(t,trigger)
	local root={Position=trigger.CFrame.Position}
	local hum={Health=100}
	t.landed=nil
	t.Character={
		FindFirstChild=function(_,name) return if name=="HumanoidRootPart" then root else nil end,
		FindFirstChildOfClass=function(_,class) return if class=="Humanoid" then hum else nil end,
		PivotTo=function(_,cf) t.landed=cf.Position end,
	}
end
local warpedTo,returns,warps,landings={},0,0,{}
for _,q in world:GetDescendants() do
	if not q:IsA("ProximityPrompt") then continue end
	local id=q:GetAttribute("IsleWarpRegion")
	if id then
		warps+=1
		check(Data.RegionById[id]~=nil,"warp names a valid region id")
		local t=traveller()
		standAt(t,q.Parent)
		allowRegion[id]=false
		local before=#accessCalls
		q.Triggered:Fire(t)
		check(#accessCalls==before+1 and accessCalls[#accessCalls][1]==t and accessCalls[#accessCalls][2]==id,id.." warp calls IsleRegionAccess with its region id")
		check(t.landed==nil,id.." locked warp does not move the player")
		check(t.attributes.IsleRegionNotice=="Locked: "..id,id.." locked warp relays the server message")
		check(t.attributes.IsleRegionNoticeCount==1,id.." locked warp bumps the notice counter")
		q.Triggered:Fire(t)
		check(t.attributes.IsleRegionNoticeCount==2 and t.landed==nil,id.." repeated identical denial is still observable")
		allowRegion[id]=true
		q.Triggered:Fire(t)
		check(t.landed~=nil and onRegion(id,t.landed,2),id.." unlocked warp lands on its region island")
		if t.landed then table.insert(landings,{id.." landing",t.landed}) end
		local far=traveller()
		standAt(far,{CFrame=q.Parent.CFrame+Vec(30,0,0)})
		q.Triggered:Fire(far)
		check(far.landed==nil,id.." warp requires standing at the beacon")
		warpedTo[id]=true
	elseif q:GetAttribute("IsleWarpReturn") then
		returns+=1
		local t=traveller()
		standAt(t,q.Parent)
		q.Triggered:Fire(t)
		check(t.landed~=nil and onRegion("Hub",t.landed,2),"return beacon lands on the Guild Terrace")
		if t.landed then table.insert(landings,{"Skyway return landing",t.landed}) end
	elseif not q:GetAttribute("IsleAction") then
		-- Any other prompt that moves the player (quarry descent, quay/crew beacons).
		local t=traveller()
		standAt(t,q.Parent)
		pcall(function() q.Triggered:Fire(t) end)
		if t.landed then table.insert(landings,{q.ObjectText.." landing",t.landed}) end
	end
end
-- Warp landings must sit outside monster aggro (25): every marker >= 40 studs flat.
for _,obj in world:GetDescendants() do
	if obj:IsA("SpawnLocation") then table.insert(landings,{obj.Name,obj.Position}) end
end
check(#landings>=8,"warp landing points collected for the aggro rule")
for _,marker in spawnFolder:GetChildren() do
	local m=marker.CFrame.Position
	for _,landing in landings do
		local d=landing[2]-m
		check(Vec(d.X,0,d.Z).Magnitude>=40,marker.Name.." is >= 40 studs from "..landing[1])
	end
end
for _,region in Data.Regions do
	if next(region.requires) then check(warpedTo[region.id],region.id.." is reachable by a gated warp") end
end
check(returns>=4,"every depth region has a return beacon")
-- Void safety: every region island is bridged or a warp destination; depth isles are guarded.
local bridgeEnds={}
for _,deck in world:GetDescendants() do
	if deck:IsA("BasePart") and deck.Name=="Continuous bridge deck" then
		local half=deck.CFrame.LookVector*deck.Size.Z/2
		table.insert(bridgeEnds,deck.CFrame.Position+half)
		table.insert(bridgeEnds,deck.CFrame.Position-half)
	end
end
local legacyIsles={["Compass Quay"]=true,["Mosswake Grove"]=true,["Brassfall Quarry"]=true,Skyreach=true}
for _,isle in archipelago:GetChildren() do
	local id=isle:GetAttribute("RegionId")
	if not id then continue end
	local bridged=0
	for _,p in bridgeEnds do if onIsland(isle,p+Vec(0,.3,0)) then bridged+=1 end end
	local guards=0
	for _,obj in isle:GetDescendants() do if obj.Name=="Edge guard" then guards+=1 end end
	check(bridged>0 or warpedTo[id],isle.Name.." is reached by bridge or warp")
	if not legacyIsles[isle.Name] then check(guards>=8,isle.Name.." has an invisible edge guard ring") end
end
-- Crafting stations and the Guild Hall.
local stationSpots,stationCount={},0
for _,q in world:GetDescendants() do
	if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction")=="station" then
		stationCount+=1
		local kind=q:GetAttribute("IsleItem")
		local t=traveller()
		q.Triggered:Fire(t)
		check(t.attributes.IsleStation==kind,kind.." station sets the IsleStation attribute")
		q.Triggered:Fire(t)
		check(t.attributes.IsleStationVisit==2,kind.." repeat visits are observable")
		local region=islandOf(q):GetAttribute("RegionId")
		stationSpots[kind]=stationSpots[kind] or {}
		table.insert(stationSpots[kind],region)
	end
end
local regional=0
for _,kind in {"Forge","Hearth","Cauldron","Workbench","Slayer"} do
	local spots=stationSpots[kind]
	check(spots~=nil,kind.." station exists")
	check(table.find(spots,"Hub")~=nil,kind.." station stands in the hub")
	for _,r in spots do if r~="Hub" then regional+=1 end end
end
check(regional>=2,"regions host extra crafting stations")
local leaderboard=world:FindFirstChild("Skill Leaderboard",true)
check(leaderboard~=nil and leaderboard:FindFirstChildOfClass("SurfaceGui")~=nil,"guild hall skill leaderboard")
for _,skill in Data.SkillOrder do
	check(leaderboard:FindFirstChild("Row_"..skill,true)~=nil,skill.." row on the leaderboard")
end
local bestiary=world:FindFirstChild("Bestiary",true)
check(bestiary~=nil and bestiary:IsA("BasePart"),"guild hall bestiary board")
for id,def in Data.Monsters do
	local row=bestiary:FindFirstChild("Row_"..id,true)
	check(row~=nil and row.Text:find(def.name,1,true)~=nil,def.name.." listed in the bestiary")
end
check(islandOf(leaderboard):GetAttribute("RegionId")=="Hub" and islandOf(bestiary):GetAttribute("RegionId")=="Hub","guild hall boards stand in the hub")
-- Builder's Terrace: Carpentry hotspots render furniture from server attributes.
do
	local beforeChecks=checks
	local builder=player(41,{FurnitureGarden="HerbPlanter",FurniturePortal="PortalFrame",HomePortal="Windpine"})
	local home=archipelago:FindFirstChild("WayfarersRest_41")
	local terrace=home:FindFirstChild("Builders Terrace")
	check(terrace~=nil,"home gains a Builder's Terrace")
	local homeCenter=home:FindFirstChild("Meadow").CFrame.Position
	local terraceCenter=terrace:FindFirstChild("Meadow").CFrame.Position
	check(math.abs(terraceCenter.X-homeCenter.X-Data.TERRACE_OFFSET.x)<.01,"terrace sits at the data offset")
	local function flat(a,b) return math.sqrt((a.X-b.X)^2+(a.Z-b.Z)^2) end
	check(flat(terraceCenter,homeCenter)-11>19,"terrace does not overlap the home island")
	local hotspots=0
	for _,h in ipairs(Data.Hotspots) do
		local plinth=terrace:FindFirstChild(h.name.." hotspot")
		check(plinth~=nil and plinth:GetAttribute("HotspotId")==h.id,h.id.." hotspot plinth exists")
		local spot=plinth.CFrame.Position
		check(math.abs(spot.X-homeCenter.X-h.x)<.01 and math.abs(spot.Z-homeCenter.Z-h.z)<.01,h.id.." hotspot at its data offset")
		check(flat(spot,terraceCenter)+2.9<=11,h.id.." hotspot footprint stays on the terrace")
		local q=plinth:FindFirstChildOfClass("ProximityPrompt")
		check(q~=nil and q:GetAttribute("OwnerUserId")==41 and q:GetAttribute("IsleAction")==nil,h.id.." planner prompt is private and awards nothing")
		hotspots+=1
	end
	check(hotspots==#Data.Hotspots,"every hotspot rendered")
	for i,h in ipairs(Data.Hotspots) do
		for j=i+1,#Data.Hotspots do
			local o=Data.Hotspots[j]
			check(math.sqrt((h.x-o.x)^2+(h.z-o.z)^2)>=5.8,h.id.." and "..o.id.." footprints never overlap")
		end
	end
	-- Saved furniture restores on join.
	local garden=terrace:FindFirstChild("Furniture_Garden")
	check(garden~=nil and garden:GetAttribute("FurnitureId")=="HerbPlanter","saved furniture restored at join")
	check(terrace:FindFirstChild("Garden Plot hotspot").Transparency==1,"occupied hotspot plinth hidden")
	check(terrace:FindFirstChild("Furniture_Bench")==nil,"empty hotspot has no furniture")
	-- Every furniture piece builds on its hotspot inside its footprint and budget.
	local tester=player(42)
	local testTerrace=archipelago:FindFirstChild("WayfarersRest_42"):FindFirstChild("Builders Terrace")
	local testCenter=archipelago:FindFirstChild("WayfarersRest_42"):FindFirstChild("Meadow").CFrame.Position
	for _,id in ipairs(Data.FurnitureOrder) do
		local f=Data.Furniture[id]
		local h=Data.HotspotById[f.hotspot]
		tester:SetAttribute("Furniture"..h.id,id)
		local model=testTerrace:FindFirstChild("Furniture_"..h.id)
		check(model~=nil and model:GetAttribute("FurnitureId")==id,id.." renders")
		local parts,maxReach,lowest=0,0,math.huge
		local spot=testCenter+roblox.Vector3.new(h.x,0,h.z)
		for _,obj in model:GetDescendants() do
			if obj:IsA("BasePart") then
				parts+=1
				check(obj.Anchored and obj.Size.X>0 and obj.Size.Y>0 and obj.Size.Z>0,id.." part anchored with positive size")
				local p=obj.CFrame.Position
				maxReach=math.max(maxReach,flat(p,spot)+math.min(obj.Size.X,obj.Size.Z)/2)
				lowest=math.min(lowest,p.Y-obj.Size.Y/2)
			end
		end
		check(parts>=5 and parts<=20,id.." uses a bounded primitive count ("..parts..")")
		check(maxReach<=2.95,id.." stays within its hotspot footprint ("..string.format("%.2f",maxReach)..")")
		check(lowest>=testCenter.Y-.2,id.." sits on the terrace floor")
		local stations=0
		for _,obj in model:GetDescendants() do
			if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction")=="station" then
				stations+=1
				check(obj:GetAttribute("OwnerUserId")==42,id.." station prompt is private")
				check(table.find(f.effect.station,obj:GetAttribute("IsleItem"))~=nil,id.." station prompt matches its effect")
			end
		end
		check(stations==#(f.effect.station or {}),id.." exposes one prompt per home station")
		local size=#testTerrace:GetDescendants()
		tester:SetAttribute("Furniture"..h.id,id)
		check(#testTerrace:GetDescendants()==size,id.." repeat attribute cannot duplicate geometry")
	end
	-- Swapping, clearing and invalid values.
	tester:SetAttribute("FurnitureBench","SturdyWorkbench")
	check(testTerrace:FindFirstChild("Furniture_Bench"):GetAttribute("FurnitureId")=="SturdyWorkbench","replacement swaps the model")
	local benchCount=0
	for _,child in testTerrace:GetChildren() do if child.Name=="Furniture_Bench" then benchCount+=1 end end
	check(benchCount==1,"one model per hotspot")
	tester:SetAttribute("FurnitureBench","")
	check(testTerrace:FindFirstChild("Furniture_Bench")==nil,"cleared hotspot removes the model")
	check(testTerrace:FindFirstChild("Workshop Bench hotspot").Transparency==0,"cleared hotspot shows its plinth")
	tester:SetAttribute("FurnitureBench","PortalFrame")
	check(testTerrace:FindFirstChild("Furniture_Bench")==nil,"furniture for another hotspot is ignored")
	tester:SetAttribute("FurnitureBench","Ghost")
	check(testTerrace:FindFirstChild("Furniture_Bench")==nil,"unknown furniture is ignored")
	tester:SetAttribute("FurnitureBench",7)
	check(testTerrace:FindFirstChild("Furniture_Bench")==nil,"non-string furniture is ignored")
	-- Planner prompt opens the Construction page for the owner only.
	local plan=testTerrace:FindFirstChild("Workshop Bench hotspot"):FindFirstChildOfClass("ProximityPrompt")
	plan.Triggered:Fire(tester)
	check(tester:GetAttribute("IsleStation")=="Construction" and tester:GetAttribute("IsleStationVisit")==1,"planner opens the Construction page")
	plan.Triggered:Fire(builder)
	check(builder:GetAttribute("IsleStationVisit")==nil,"another player cannot use the planner")
	-- Home station prompt opens the matching workshop tab for the owner.
	tester:SetAttribute("FurnitureHearth","EmberoakRange")
	local range=testTerrace:FindFirstChild("Furniture_Hearth")
	for _,obj in range:GetDescendants() do
		if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleItem")=="Cauldron" then obj.Triggered:Fire(tester) end
	end
	check(tester:GetAttribute("IsleStation")=="Cauldron","home Cauldron opens its station")
	-- Home portal: travels through the authoritative region check.
	local portal=terrace:FindFirstChild("Furniture_Portal")
	local veilPrompt
	for _,obj in portal:GetDescendants() do
		if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleHomePortal") then veilPrompt=obj end
	end
	check(veilPrompt~=nil and veilPrompt:GetAttribute("OwnerUserId")==41,"portal prompt is private")
	check(veilPrompt.ObjectText:find("Windpine",1,true)~=nil,"portal shows its attuned region")
	standAt(builder,veilPrompt.Parent)
	allowRegion.Windpine=false
	local callsBefore=#accessCalls
	veilPrompt.Triggered:Fire(builder)
	check(#accessCalls==callsBefore+1 and accessCalls[#accessCalls][2]=="Windpine","portal asks IsleRegionAccess")
	check(builder.landed==nil,"denied portal does not move the player")
	allowRegion.Windpine=true
	veilPrompt.Triggered:Fire(builder)
	check(builder.landed~=nil and onRegion("Windpine",builder.landed,2),"attuned portal lands in its region")
	local stranger=traveller()
	standAt(stranger,veilPrompt.Parent)
	veilPrompt.Triggered:Fire(stranger)
	check(stranger.landed==nil and #accessCalls==callsBefore+2,"strangers cannot use a home portal")
	builder:SetAttribute("HomePortal","")
	check(veilPrompt.ObjectText:find("attune",1,true)~=nil,"unattuned portal explains itself")
	standAt(builder,veilPrompt.Parent)
	veilPrompt.Triggered:Fire(builder)
	check(builder.landed==nil and type(builder:GetAttribute("IsleRegionNotice"))=="string","unattuned portal shows a notice")
	builder:SetAttribute("HomePortal","Skyreach")
	allowRegion.Skyreach=true
	veilPrompt.Triggered:Fire(builder)
	check(builder.landed~=nil and onRegion("Skyreach",builder.landed,2),"portal reaches Skyreach")
	-- Leaving cleans the terrace with the home.
	players.PlayerRemoving:Fire(builder)
	check(archipelago:FindFirstChild("WayfarersRest_41")==nil,"leaving removes the terrace")
	builder:SetAttribute("FurnitureBench","SturdyWorkbench")
	print("Builder's Terrace: "..(checks-beforeChecks).." checks.")
end
print("Depth world: "..tierCount.." resource tiers / "..nodeCount.." gather nodes, "..markers.." spawn markers, "..warps.." gated warps, "..stationCount.." stations, "..staticParts.." static parts, "..staticLights.." lights.")
print("World QA passed "..checks.." checks with "..parts.." parts, "..prompts.." prompts and "..signs.." sign surfaces.")
