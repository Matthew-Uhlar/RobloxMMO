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
local spawned={}
local environment={
	game={GetService=function(_,name) return services[name] end},
	workspace=world,Instance=roblox.Instance,Vector3=roblox.Vector3,
	Vector2=roblox.Vector2,CFrame=roblox.CFrame,Color3=roblox.Color3,
	UDim2=roblox.UDim2,Font=roblox.Font,Enum=roblox.Enum,task={
		-- Coroutine-backed so the day/night loop parks on task.wait and the
		-- test can step it deterministically (resume with a delta time).
		spawn=function(fn,...)
			local co=coroutine.create(fn)
			local ok,err=coroutine.resume(co,...)
			assert(ok,err)
			table.insert(spawned,co)
			return co
		end,
		wait=function() return coroutine.yield() end,
	},
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
local islandsRoot=world:FindFirstChild("Islands")
check(islandsRoot~=nil and islandsRoot:IsA("Folder"),"Workspace.Islands folder exists")
local function allIsles()
	local list={}
	for _,m in islandsRoot:GetChildren() do table.insert(list,m) end
	for _,m in archipelago:GetChildren() do table.insert(list,m) end
	return list
end
local a=player(11)
local b=player(22,{HomeGarden=true,HomeDeck=true,Worker1Tier=1,Worker1Resource="Fish",Worker2Tier=3,Worker2Resource="Herb"})
local homeA=archipelago:FindFirstChild("WayfarersRest_11")
local homeB=archipelago:FindFirstChild("WayfarersRest_22")
check(homeA~=nil and homeB~=nil,"separate homes")
check((a.RespawnLocation.Position-b.RespawnLocation.Position).Magnitude>=60,"home spacing")
check(homeA:FindFirstChild("Garden")==nil,"unowned garden absent")
check(homeB:FindFirstChild("Garden")~=nil,"saved garden restored")
check(homeB:FindFirstChild("Deck")~=nil,"saved deck restored")
-- Verdant Garden islet (Farming Depth; full coverage in verify-garden.luau).
do
	local gardenA=homeA:FindFirstChild("Verdant Garden")
	check(gardenA~=nil and gardenA:GetAttribute("GardenOwner")==11,"every home gains a Verdant Garden islet")
	local plotPrompts=0
	for _,obj in gardenA:GetDescendants() do
		if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction")=="gardenPlot" then
			plotPrompts+=1
			check(obj:GetAttribute("OwnerUserId")==11,"garden plot prompts belong to the home owner")
		end
	end
	check(plotPrompts==Data.Garden.MAX_PLOTS,"twelve garden plot prompts")
	check(homeA:FindFirstChild("Anchor_Waypoint_VerdantGarden",true)~=nil,"garden waypoint anchor")
end
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
-- Workers depth: twelve stations; 4-12 ring the Worker Yard outside the
-- placement grid, 1-3 stay inside Data.Island's protected worker rectangles.
do
	local before=checks
	local I=Data.Island
	local meadow=homeA:FindFirstChild("Meadow").CFrame.Position
	local yard=homeA:FindFirstChild("Worker Yard")
	check(yard~=nil,"home gains a Worker Yard")
	check(homeA:FindFirstChild("Anchor_Waypoint_WorkerYard",true)~=nil,"worker yard waypoint")
	local pads={}
	for slot=1,Data.Workers.MAX_SLOTS do
		local station=homeA:FindFirstChild("WorkerStation"..slot)
		check(station~=nil,"worker station "..slot.." exists")
		local pad=station:FindFirstChild("Worker pad").CFrame.Position
		local o=pad-meadow
		pads[slot]=o
		check(math.sqrt(o.X^2+o.Z^2)+2.3<=Data.Home.radius(1)-10,"station "..slot.." inside the home footprint (§40: the yard stands out south-east)")
		local chassis=station:FindFirstChild("Surveyor chassis")
		local interaction=chassis:FindFirstChildOfClass("ProximityPrompt")
		check(interaction:GetAttribute("OwnerUserId")==11,"station "..slot.." owner")
		check(interaction:GetAttribute("IsleItem")==tostring(slot),"station "..slot.." slot id")
		check(station:FindFirstChild("Tier ring")~=nil,"station "..slot.." tier ring")
		if slot<=3 then
			local inside=false
			for _,r in ipairs(I.Protected) do
				if r.name=="worker station" and o.X>=r.x1 and o.X<=r.x2 and o.Z>=r.z1 and o.Z<=r.z2 then inside=true end
			end
			check(inside,"station "..slot.." sits in a protected worker rectangle")
		else
			-- §27: the build grid now covers the island; the yard is a protected circle.
			local zone
			for _,c in ipairs(I.ProtectedCircles) do if c.name=="worker yard" then zone=c end end
			check(zone~=nil and math.sqrt((o.X-zone.x)^2+(o.Z-zone.z)^2)+2.6<=zone.r,"yard station "..slot.." is inside the protected worker yard")
			local y=yard:FindFirstChild("Upper meadow").CFrame.Position
			check(math.sqrt((pad.X-y.X)^2+(pad.Z-y.Z)^2)+2.6<=11.55,"yard station "..slot.." on the yard")
			check(math.abs(pad.Y-homeA:GetAttribute("IslandCenter").Y-1.58)<.05,"yard station "..slot.." stands on the yard top")
			local locked=interaction.Enabled==false
			check(locked,"station "..slot.." locked until unique crafts open it")
			check(chassis:FindFirstChild("Worker status"):FindFirstChildOfClass("TextLabel").Text:find("Locked",1,true)~=nil,"locked station explains itself")
		end
	end
	-- Tier rings (cylinders: Size.Y/Z = diameter) never overlap or z-fight.
	local ringRadius={}
	for slot=1,Data.Workers.MAX_SLOTS do
		local ring=homeA:FindFirstChild("WorkerStation"..slot):FindFirstChild("Tier ring")
		ringRadius[slot]=ring.Size.Z/2
		check(ring.Size.Z/2>=2.3,"tier ring "..slot.." frames its pad")
	end
	for i=1,Data.Workers.MAX_SLOTS do
		for j=i+1,Data.Workers.MAX_SLOTS do
			local d=pads[i]-pads[j]
			local dist=math.sqrt(d.X^2+d.Z^2)
			check(dist>=4.7,"stations "..i.." and "..j.." do not overlap")
			check(dist>ringRadius[i]+ringRadius[j],"tier rings "..i.." and "..j.." do not overlap ("..string.format("%.2f",dist).." studs)")
		end
	end
	-- Unlock slot 4 and build a Shardling Sentry there.
	local s4=homeA:FindFirstChild("WorkerStation4")
	local p4=s4:FindFirstChild("Surveyor chassis"):FindFirstChildOfClass("ProximityPrompt")
	a:SetAttribute("WorkerSlots",4)
	check(p4.Enabled and p4:GetAttribute("IsleAction")=="workerBuild","unlocked slot 4 offers a build")
	check(not homeA:FindFirstChild("WorkerStation5"):FindFirstChild("Surveyor chassis"):FindFirstChildOfClass("ProximityPrompt").Enabled,"slot 5 still locked")
	a:SetAttribute("Worker4Resource","ShardlingSentry")
	a:SetAttribute("Worker4Tier",3)
	check(p4:GetAttribute("IsleAction")=="workerClaim","built yard worker claims")
	check(p4.ObjectText:find("Shardling Sentry",1,true)~=nil,"type name on the prompt")
	local emblem=s4:FindFirstChild("Worker emblem")
	check(emblem~=nil and emblem:GetAttribute("Shape")=="AetherCrystal","combat emblem shape")
	check(emblem:GetAttribute("WorkerType")=="ShardlingSentry","emblem tagged with the type")
	local surveyors=0
	for _,child in s4:GetChildren() do if child.Name=="Sculpted surveyor" then surveyors+=1 end end
	check(surveyors==1,"one surveyor sculpture")
	check(s4:FindFirstChild("Sculpted surveyor"):GetAttribute("SculptureScale")>1,"surveyor grows with tier")
	local ring=s4:FindFirstChild("Tier ring")
	local tier3=ring.Color
	a:SetAttribute("Worker4Tier",7)
	check(ring.Color~=tier3,"tier ring recolours by tier")
	a:SetAttribute("Worker4Resource","Timber")
	local timberEmblem=s4:FindFirstChild("Worker emblem")
	check(timberEmblem:GetAttribute("Shape")=="Log","emblem follows the type")
	local emblems,size=0,#s4:GetDescendants()
	for _,child in s4:GetChildren() do if child.Name=="Worker emblem" then emblems+=1 end end
	check(emblems==1,"old emblem removed")
	a:SetAttribute("Worker4Resource","Timber")
	check(#s4:GetDescendants()==size,"repeat attribute does not rebuild")
	for _,id in ipairs({"Ore","Fish","Herb","WispglowLantern","Celestium"}) do
		a:SetAttribute("Worker4Resource",id)
		check(s4:FindFirstChild("Worker emblem"):GetAttribute("Shape")==Data.Workers.TypeById[id].shape,id.." emblem")
	end
	print("Workers depth world: "..(checks-before).." checks.")
end
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
	Vector3=roblox.Vector3,Vector2=roblox.Vector2,CFrame=roblox.CFrame,Color3=roblox.Color3,UDim2=roblox.UDim2,Font=roblox.Font,Enum=roblox.Enum,
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
	while node and node.Parent~=archipelago and node.Parent~=islandsRoot do node=node.Parent end
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
	for _,isle in allIsles() do
		if isle:GetAttribute("RegionId")==regionId and onIsland(isle,pos,margin) then return true end
	end
	return false
end
check(staticParts<4000,"static world stays under the 4000 part budget ("..staticParts..")")
for _,obj in world:GetDescendants() do
	if obj:IsA("BasePart") then check(obj.Anchored,"every world part is anchored") end
end
for _,region in Data.Regions do
	local found=false
	for _,isle in islandsRoot:GetChildren() do if isle:GetAttribute("RegionId")==region.id then found=true end end
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
-- Workers depth: Data.Workers.ResourceRegion names exactly the resources whose
-- every public node sits in one gated region (those worker types need it unlocked).
do
	local derived={}
	for id,nodes in gatherNodes do
		local only=nil
		for i,q in nodes do
			local region=q:GetAttribute("IsleRegion")
			if i==1 then only=region elseif region~=only then only=nil end
			if region==nil then only=nil; break end
		end
		if only and Data.ResourceSkill[id] then derived[id]=only end
	end
	for id,region in derived do check(Data.Workers.ResourceRegion[id]==region,id.." is exclusive to "..region.." in the world and in Workers.ResourceRegion") end
	for id,region in Data.Workers.ResourceRegion do check(derived[id]==region,id.." Workers.ResourceRegion "..region.." matches its world nodes") end
	for _,t in Data.Workers.Types do
		if t.kind=="gather" then check(t.region==derived[t.output],t.id.." worker region gate follows its nodes") end
	end
end
-- Every monster: spawn markers in its region on open ground.
local spawnFolder=world:FindFirstChild("MonsterSpawns")
check(spawnFolder~=nil and spawnFolder:IsA("Folder"),"Workspace.MonsterSpawns folder exists")
local markerCount,markers={},0
local floors={Meadow=true,["Floating foundation"]=true,["Grassy hillock"]=true,["Edge guard"]=true,["Hall floor"]=true,["Guild court"]=true,["Cavern roof"]=true,
	["Upper meadow"]=true,["Tier cliff"]=true}
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
	for _,candidate in islandsRoot:GetChildren() do
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
for _,isle in islandsRoot:GetChildren() do
	local id=isle:GetAttribute("RegionId")
	if not id then continue end
	local bridged=0
	for _,p in bridgeEnds do if onIsland(isle,p+Vec(0,.3,0)) then bridged+=1 end end
	local guards=0
	for _,obj in isle:GetDescendants() do if obj.Name=="Edge guard" then guards+=1 end end
	check(bridged>0 or warpedTo[id],isle.Name.." is reached by bridge or warp")
	check(guards>=8,isle.Name.." has an invisible edge guard ring")
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
-- Island placement: free-form props render from the IslandPlacements attribute.
do
	local beforeChecks=checks
	local I=Data.Island
	local V3=roblox.Vector3
	local function rec(id,prop,x,z,rot) return I.record({id=id,prop=prop,x=x,z=z,rot=rot or 0}) end
	local function spot(propId,rot,occupied)
		for z=-I.RANGE,I.RANGE do for x=-I.RANGE,I.RANGE do
			if I.check(occupied or {},propId,x,z,rot) then return x,z end
		end end
		error("no spot for "..propId)
	end
	-- Saved placements restore at join.
	local fx,fz=spot("TimberFence",0)
	local owner=player(51,{IslandPlacements=rec(1,"TimberFence",fx,fz).. ";"..rec(2,"LanternPost",fx+1,fz)})
	local home=archipelago:FindFirstChild("WayfarersRest_51")
	local folder=home:FindFirstChild("Placements")
	check(folder~=nil and folder:IsA("Folder"),"home island has a Placements folder")
	local center=home:FindFirstChild("Meadow").CFrame.Position+V3.new(0,.25,0)
	check(owner:GetAttribute("IslandCenter")==center,"island centre published for client snapping")
	check(#folder:GetChildren()==2,"saved placements restored at join")
	local fence=folder:FindFirstChild("Placement_1")
	check(fence~=nil and fence:GetAttribute("PropId")=="TimberFence" and fence:GetAttribute("PlacementId")==1,"placement model tagged with its id and prop")
	check(folder:FindFirstChild("Placement_2"):FindFirstChildWhichIsA("PointLight",true)~=nil,"lantern post glows")
	-- Every prop builds inside its footprint, on the meadow, within the part budget.
	local tester=player(52)
	local tFolder=archipelago:FindFirstChild("WayfarersRest_52"):FindFirstChild("Placements")
	local tCenter=archipelago:FindFirstChild("WayfarersRest_52"):FindFirstChild("Meadow").CFrame.Position+V3.new(0,.25,0)
	for index,id in ipairs(I.PropOrder) do
		local def=I.Props[id]
		local rot=index%4
		local x,z=spot(id,rot)
		tester:SetAttribute("IslandPlacements",rec(1,id,x,z,rot))
		local model=tFolder:FindFirstChild("Placement_1")
		check(model~=nil and model:GetAttribute("PropId")==id and #tFolder:GetChildren()==1,id.." renders alone")
		local ox,oz,yaw=I.centerOffset(id,x,z,rot)
		local frame=roblox.CFrame.new(tCenter+V3.new(ox,0,oz))*roblox.CFrame.Angles(0,yaw,0)
		local w,d=I.footprint(def,0)
		local halfW,halfD=w*I.CELL/2+.02,d*I.CELL/2+.02
		local parts,inside,lowest,solid=0,true,math.huge,0
		for _,obj in model:GetDescendants() do
			if obj:IsA("BasePart") then
				parts+=1
				check(obj.Anchored and obj.Size.X>0 and obj.Size.Y>0 and obj.Size.Z>0 and not obj.CanTouch,id.." part anchored, positive and untouchable")
				if obj.CanCollide then solid+=1 end
				local s=obj.Size/2
				for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
					local corner=frame:PointToObjectSpace((obj.CFrame*roblox.CFrame.new(sx*s.X,sy*s.Y,sz*s.Z)).Position)
					if math.abs(corner.X)>halfW or math.abs(corner.Z)>halfD then inside=false end
					lowest=math.min(lowest,corner.Y)
				end end end
			end
		end
		check(parts>=3 and parts<=12,id.." uses 3-12 parts ("..parts..")")
		check(inside,id.." stays inside its "..w.."x"..d.." footprint at rot "..rot)
		check(lowest>=-.05,id.." sits on the meadow")
		check(solid>=1,id.." has a solid part")
		local stations=0
		for _,obj in model:GetDescendants() do
			if obj:IsA("ProximityPrompt") then
				stations+=1
				check(obj:GetAttribute("IsleAction")=="station" and obj:GetAttribute("IsleItem")==(def.effect and def.effect.station) and obj:GetAttribute("OwnerUserId")==52,id.." station prompt is private and matches its effect")
			end
		end
		check(stations==(if def.effect and def.effect.station then 1 else 0),id.." exposes its station prompt only when it has one")
		check((model:FindFirstChildWhichIsA("PointLight",true)~=nil)==(def.effect~=nil and def.effect.light~=nil),id.." glows only when it is a light")
	end
	-- Utility station prompt opens the matching workshop page for the owner only.
	local sx,sz=spot("FieldAnvil",0)
	tester:SetAttribute("IslandPlacements",rec(4,"FieldAnvil",sx,sz))
	local anvilPrompt=tFolder:FindFirstChild("Placement_4"):FindFirstChildWhichIsA("ProximityPrompt",true)
	anvilPrompt.Triggered:Fire(tester)
	check(tester:GetAttribute("IsleStation")=="Forge","field anvil opens the Forge")
	local visits=tester:GetAttribute("IsleStationVisit")
	anvilPrompt.Triggered:Fire(owner)
	check(owner:GetAttribute("IsleStation")==nil and tester:GetAttribute("IsleStationVisit")==visits,"another player cannot use a home station")
	-- Incremental updates: unchanged records keep their models.
	local list={rec(1,"TimberFence",fx,fz),rec(2,"LanternPost",fx+1,fz)}
	local occupied=I.occupancy(I.decode(table.concat(list,";")))
	local px,pz=spot("StonePath",0,occupied)
	table.insert(list,rec(3,"StonePath",px,pz))
	local fenceModel,lanternModel=folder:FindFirstChild("Placement_1"),folder:FindFirstChild("Placement_2")
	owner:SetAttribute("IslandPlacements",table.concat(list,";"))
	check(#folder:GetChildren()==3 and folder:FindFirstChild("Placement_1")==fenceModel and folder:FindFirstChild("Placement_2")==lanternModel,"placing adds one model and keeps the others")
	local size=#folder:GetDescendants()
	owner:SetAttribute("IslandPlacements",table.concat(list,";"))
	check(#folder:GetDescendants()==size,"repeat value cannot duplicate geometry")
	table.remove(list,2)
	owner:SetAttribute("IslandPlacements",table.concat(list,";"))
	check(folder:FindFirstChild("Placement_2")==nil and lanternModel.Parent==nil and folder:FindFirstChild("Placement_1")==fenceModel,"pickup removes only that model")
	list[1]=rec(1,"TimberFence",fx,fz,1)
	owner:SetAttribute("IslandPlacements",table.concat(list,";"))
	local turned=folder:FindFirstChild("Placement_1")
	check(turned~=fenceModel and fenceModel.Parent==nil and turned:GetAttribute("PlacementRecord")==list[1],"a changed record rebuilds its model")
	check(#folder:GetChildren()==2,"one model per placement")
	-- Invalid values never render or stack.
	owner:SetAttribute("IslandPlacements",rec(1,"StonePath",px,pz)..";"..rec(2,"StonePath",px,pz)..";"..rec(3,"StonePath",0,2)..";9:Nope:0:0:0;junk")
	check(#folder:GetChildren()==1 and folder:FindFirstChild("Placement_1")~=nil,"overlapping, protected and unknown records are ignored")
	owner:SetAttribute("IslandPlacements",42)
	check(#folder:GetChildren()==0,"non-string value clears placements")
	owner:SetAttribute("IslandPlacements","")
	check(#folder:GetChildren()==0,"empty value renders nothing")
	check(#tFolder:GetChildren()==1,"another player's island is unaffected")
	-- A full island renders within the part budget.
	local full={}
	for z=-I.RANGE,I.RANGE do for x=-I.RANGE,I.RANGE do
		if #full<I.MAX_PLACEMENTS and I.cellBlocked(x,z)==nil then table.insert(full,rec(#full+1,if #full%2==0 then "StonePath" else "LanternPost",x,z)) end
	end end
	owner:SetAttribute("IslandPlacements",table.concat(full,";"))
	local fullParts=0
	for _,obj in folder:GetDescendants() do if obj:IsA("BasePart") then fullParts+=1 end end
	-- §27 part budget: records render in order until Data.Island.PART_BUDGET parts.
	local expected,budget=0,0
	for _,r in ipairs(full) do
		local e=I.parseRecord(r)
		if budget+I.Props[e.prop].parts>I.PART_BUDGET then break end
		budget+=I.Props[e.prop].parts; expected+=1
	end
	check(expected<I.MAX_PLACEMENTS and #folder:GetChildren()==expected and fullParts==budget and fullParts<=I.PART_BUDGET,
		"full island renders "..expected.." of "..#full.." props within the part budget ("..fullParts.." parts)")
	-- Protected zones cover every fixed object standing on the home island.
	local deco=player(53,{HomeLanterns=true,HomeGarden=true,HomeDeck=true,Worker1Tier=1})
	local dHome=archipelago:FindFirstChild("WayfarersRest_53")
	local dCenter=dHome:FindFirstChild("Meadow").CFrame.Position+V3.new(0,.25,0)
	local covered,standing=true,0
	for _,obj in dHome:GetDescendants() do
		if obj:IsA("BasePart") and obj.Name~="Meadow" and not obj:FindFirstAncestor("Builders Terrace") and not obj:FindFirstAncestor("Placements") then
			local p=obj.CFrame.Position-dCenter
			local top=p.Y+obj.Size.Y/2
			if top>.3 and p.Y>-1 and math.sqrt(p.X^2+p.Z^2)<=I.RADIUS then
				standing+=1
				local cx,cz=math.floor(p.X/I.CELL+.5),math.floor(p.Z/I.CELL+.5)
				if I.cellBlocked(cx,cz)==nil then covered=false; print("uncovered: "..obj.Name.." at "..tostring(p)) end
			end
		end
	end
	check(standing>=20 and covered,"every fixed home object stands in a protected cell ("..standing.." parts)")
	-- Leaving removes the placements with the home.
	players.PlayerRemoving:Fire(owner)
	check(archipelago:FindFirstChild("WayfarersRest_51")==nil and folder.Parent==nil,"leaving removes placed props")
	owner:SetAttribute("IslandPlacements",rec(1,"StonePath",px,pz))
	check(folder.Parent==nil,"updates after leaving are ignored")
	print("Island placement: "..(checks-beforeChecks).." checks.")
end
-- Wave 4: island scale + terrain, Workspace.Islands anchors, mesh slots,
-- lighting look, light caps, day/night, prompt hold durations.
do
	local beforeChecks=checks
	local serde=require("@lune/serde")
	local L=services.Lighting
	-- Lighting (§35): Technology = Future and the day look are place defaults;
	-- the world script never writes Lighting (lighting.client.lua is the one
	-- writer, verify-lighting.luau). The project look matches the Hub day profile.
	local project=serde.decode("json",fs.readFile("default.project.json"))
	local lp=project.tree.Lighting and project.tree.Lighting["$properties"]
	check(lp~=nil and lp.Technology=="Future","Lighting.Technology = Future in default.project.json")
	check(project.tree.Workspace["$properties"].StreamingEnabled==false,"StreamingEnabled stays false")
	local LP=luau.load(fs.readFile("shared/LightingProfiles.lua"),{environment={Color3=roblox.Color3},injectGlobals=true})()
	local hub=LP.dayLook("Hub")
	for _,key in {"Brightness","EnvironmentDiffuseScale","EnvironmentSpecularScale","ExposureCompensation","ShadowSoftness"} do
		check(math.abs(hub[key]-lp[key])<1e-3,key.." in the project matches the Hub day profile")
	end
	for _,key in {"Ambient","OutdoorAmbient"} do
		local c=hub[key]
		check(math.abs(c.R-lp[key][1])<.003 and math.abs(c.G-lp[key][2])<.003 and math.abs(c.B-lp[key][3])<.003,key.." in the project matches the Hub day profile")
	end
	check(lp.GlobalShadows==true,"global shadows on by default")
	local fresh=roblox.Instance.new("Lighting")
	check(#L:GetChildren()==0,"the world script adds no Lighting children")
	for _,key in {"Brightness","ClockTime","GlobalShadows","ExposureCompensation","Ambient","OutdoorAmbient"} do
		local okA,a=pcall(function() return L[key] end)
		local okB,b=pcall(function() return fresh[key] end)
		check(okA==okB and (not okA or a==b),"the world script leaves Lighting."..key.." alone")
	end
	local function lum(c) return .2126*c.R+.7152*c.G+.0722*c.B end

	-- Workspace.Islands: one Model per static island with the contract attributes.
	local oldRadius={["Compass Quay"]=43,["Mosswake Grove"]=30,["Brassfall Quarry"]=31,["Warden Reach"]=32,Skyreach=30,
		["Guild Terrace"]=32,["Meadow Reach"]=30,["Cinder Shelf"]=24,["Windpine Grove"]=36,["Gloomhollow Caverns"]=38,
		["Tidewater Shoals"]=40,["Tempest Spire"]=30,["The Shattered Crown"]=48} -- Endgame region (new in its 2x form)
	local seen,tiers,trees,staticCounts=0,0,0,{}
	for _,isle in islandsRoot:GetChildren() do
		seen+=1
		check(isle:IsA("Model"),isle.Name.." is a Model")
		local center,radius,region=isle:GetAttribute("IslandCenter"),isle:GetAttribute("IslandRadius"),isle:GetAttribute("Region")
		check(typeof(center)=="Vector3" and type(radius)=="number" and radius>0,isle.Name.." has IslandCenter and IslandRadius")
		check(type(region)=="string" and (Data.RegionById[region]~=nil or region=="Home"),isle.Name.." has a valid Region")
		local meadow=isle:FindFirstChild("Meadow")
		check(meadow~=nil and (meadow.CFrame.Position+Vec(0,.25,0)-center).Magnitude<.01,isle.Name.." IslandCenter is its meadow top")
		local old=oldRadius[isle.Name]
		check(old~=nil,isle.Name.." is a known static island")
		local factor=if isle.Name=="Compass Quay" then 2.5 else 2
		check(radius>=old*factor,isle.Name.." grew "..factor.."x or more ("..old.." -> "..radius..")")
		-- Layer stack: the foundation top sits inside the meadow (no shared plane).
		local foundation=isle:FindFirstChild("Floating foundation")
		local fTop=foundation.CFrame.Position.Y+foundation.Size.X/2
		-- The forged cliff rides the foundation's fit box, so the whole hull
		-- (top below the meadow's bottom, lip ring outside its side wall) must
		-- stay clear of the meadow slab or the grass clips into the rock.
		local meadow=isle:FindFirstChild("Meadow")
		local mBottom=meadow.CFrame.Position.Y-meadow.Size.X/2
		local mRadius=meadow.Size.Y/2
		check(fTop<mBottom-.05,isle.Name.." foundation/cliff top sits below the meadow slab")
		check(foundation.Size.Y/2*.99>mRadius+.02,isle.Name.." cliff lip ring starts outside the meadow side wall")
		for _,ledge in isle:GetChildren() do
			if ledge.Name=="Shore ledge" then
				check(ledge.CFrame.Position.Y+ledge.Size.Y/2<mBottom-.05,isle.Name.." shore ledge stays below the meadow slab")
			end
		end
		local parts,shore=0,0
		for _,obj in isle:GetDescendants() do
			if obj:IsA("BasePart") then parts+=1 end
			if obj.Name=="Tier cliff" then tiers+=1 end
			if obj.Name=="Shore boulder" or obj.Name=="Shore ledge" then shore+=1 end
			local shape=obj:IsA("BasePart") and obj:GetAttribute("Shape")
			if shape and string.find(shape,"Tree",1,true) then trees+=1 end
		end
		check(shore>=3,isle.Name.." has shoreline detail")
		staticCounts[isle.Name]=parts
	end
	check(seen==13,"thirteen static islands under Workspace.Islands (Endgame: the Shattered Crown)")
	check(tiers>=14,"elevation tiers across the archipelago ("..tiers..")")
	check(trees>=80,"trees and flora are mesh slots ("..trees..")")
	local hubTiers=0
	for _,obj in islandsRoot:FindFirstChild("Compass Quay"):GetDescendants() do if obj.Name=="Tier cliff" then hubTiers+=1 end end
	check(hubTiers>=3,"hub has raised districts")
	for _,name in {"Compass Plaza","Sky Harbor","Artisans' Rise","Quay Bank","Trade Counter","Mooncrest pond","Orchard terrace","Lookout knoll"} do
		check(islandsRoot:FindFirstChild("Compass Quay"):FindFirstChild(name,true)~=nil,"hub district "..name)
	end
	-- Coplanar upward faces: overlapping flat tops in one island must differ in height.
	local function flatTop(p)
		if p.Transparency>=1 then return nil end
		local cf=p.CFrame
		if p.Shape==roblox.Enum.PartType.Cylinder and math.abs(cf.RightVector.Y)>.999 then
			return cf.Position.Y+p.Size.X/2,"circle",p.Size.Y/2
		elseif p.Shape==roblox.Enum.PartType.Block and math.abs(cf.UpVector.Y)>.999 then
			return cf.Position.Y+p.Size.Y/2,"rect",nil
		end
		return nil
	end
	local function footprint(p,kind,r)
		local c=p.CFrame.Position
		if kind=="circle" then return {c.X-r,c.X+r,c.Z-r,c.Z+r,true,c,r} end
		local cf,s=p.CFrame,p.Size/2
		local ex=math.abs(cf.RightVector.X)*s.X+math.abs(cf.LookVector.X)*s.Z
		local ez=math.abs(cf.RightVector.Z)*s.X+math.abs(cf.LookVector.Z)*s.Z
		local corners={}
		for _,a in {-1,1} do for _,b in {-1,1} do
			local q=c+cf.RightVector*a*s.X+cf.LookVector*b*s.Z
			table.insert(corners,{q.X,q.Z})
		end end
		local axes={{cf.RightVector.X,cf.RightVector.Z},{cf.LookVector.X,cf.LookVector.Z}}
		return {c.X-ex,c.X+ex,c.Z-ez,c.Z+ez,false,c,nil,corners,axes}
	end
	local coplanar=0
	for _,isle in islandsRoot:GetChildren() do
		local flats={}
		for _,obj in isle:GetDescendants() do
			if obj:IsA("BasePart") and not obj.Name:find("^Anchor_") then
				local y,kind,r=flatTop(obj)
				if y then table.insert(flats,{obj,y,footprint(obj,kind,r)}) end
			end
		end
		for i=1,#flats do
			for j=i+1,#flats do
				local a,b=flats[i],flats[j]
				if math.abs(a[2]-b[2])<.004 then
					local fa,fb=a[3],b[3]
					local overlap=fa[1]<fb[2]-.05 and fb[1]<fa[2]-.05 and fa[3]<fb[4]-.05 and fb[3]<fa[4]-.05
					if overlap and fa[5] and fb[5] then overlap=(fa[6]-fb[6]).Magnitude<fa[7]+fb[7]-.05 end
					if overlap and not fa[5] and not fb[5] then
						-- Oriented rectangles: separating-axis test in the XZ plane.
						for _,axis in {fa[9][1],fa[9][2],fb[9][1],fb[9][2]} do
							local function span(corners)
								local lo,hi=math.huge,-math.huge
								for _,q in corners do local d=q[1]*axis[1]+q[2]*axis[2]; lo=math.min(lo,d); hi=math.max(hi,d) end
								return lo,hi
							end
							local alo,ahi=span(fa[8])
							local blo,bhi=span(fb[8])
							if ahi<=blo+.05 or bhi<=alo+.05 then overlap=false break end
						end
					end
					if overlap then
						coplanar+=1
						print("coplanar: "..a[1]:GetFullName().." / "..b[1].Name)
					end
				end
			end
		end
	end
	check(coplanar==0,"no overlapping coplanar top faces (z-fighting)")

	-- Anchors (contract section 10).
	local anchors={}
	for _,obj in islandsRoot:GetDescendants() do
		if obj:IsA("BasePart") and obj.Name:sub(1,7)=="Anchor_" then
			check(anchors[obj.Name]==nil,obj.Name.." is unique")
			anchors[obj.Name]=obj
			check(obj.Anchored and obj.Transparency==1 and not obj.CanCollide and not obj.CanTouch and not obj.CanQuery,obj.Name.." is invisible and inert")
			check(obj.Parent.Parent==islandsRoot,obj.Name.." is a direct child of its island model")
			check(obj:GetAttribute("AnchorPurpose")==obj.Name:sub(8),obj.Name.." names its purpose")
		end
	end
	for _,name in {"NPC_Guide","NPC_Slayer","NPC_Banker","NPC_Merchant","NPC_Forgemaster","NPC_Fisher",
		"NPC_Auctioneer","NPC_Herald","NPC_Registrar","NPC_Joiner","NPC_Grovekeeper","NPC_Deepwarden","Spawn"} do
		check(anchors["Anchor_"..name]~=nil,"Anchor_"..name.." exists")
	end
	check(anchors.Anchor_NPC_Guide.Parent.Name=="Compass Quay","guide stands on the hub")
	local cHome=archipelago:FindFirstChild("WayfarersRest_33")
	local hubPrompt=cHome:FindFirstChild("Quay beacon"):FindFirstChildOfClass("ProximityPrompt")
	standAt(c,hubPrompt.Parent)
	hubPrompt.Triggered:Fire(c)
	check(c.landed~=nil and onRegion("Hub",c.landed,2),"home beacon lands on the hub")
	local guideOffset=anchors.Anchor_NPC_Guide.CFrame.Position-c.landed
	check(Vec(guideOffset.X,0,guideOffset.Z).Magnitude<=12,"guide anchor waits at the hub spawn")
	check(anchors.Anchor_NPC_Slayer.Parent.Name=="Guild Terrace" and anchors.Anchor_NPC_Fisher.Parent.Name=="Compass Quay","slayer and harbour-angler anchors sit by their posts")
	check(anchors.Anchor_NPC_Grovekeeper.Parent:GetAttribute("Region")=="Windpine" and anchors.Anchor_NPC_Deepwarden.Parent:GetAttribute("Region")=="Gloomhollow","regional townsfolk anchors sit in their regions")
	local hubIsles=0
	for _,isle in islandsRoot:GetChildren() do if isle:GetAttribute("Region")=="Hub" then hubIsles+=1; if hubIsles==1 then check(isle.Name=="Compass Quay","the first Region=Hub island is Compass Quay") end end end
	check(cHome:FindFirstChild("Anchor_Waypoint_HomeLanding")~=nil and cHome:GetAttribute("Region")=="Home" and cHome:GetAttribute("IslandRadius")>=38,"homes carry Region=Home, a 2x footprint and a landing anchor")
	local function nearWaypoint(pos,limit)
		for name,a in anchors do
			if name:find("^Anchor_Waypoint_") then
				local d=a.CFrame.Position-pos
				if Vec(d.X,0,d.Z).Magnitude<=limit then return true end
			end
		end
		return false
	end
	local waypointTargets=0
	for _,q in islandsRoot:GetDescendants() do
		if q:IsA("ProximityPrompt") and (q:GetAttribute("IsleAction")=="station" or q:GetAttribute("IsleWarpRegion") or q:GetAttribute("IsleWarpReturn")
			or q:GetAttribute("IsleAction")=="bank" or q:GetAttribute("IsleAction")=="sell" or q:GetAttribute("IsleAction")=="fight") then
			waypointTargets+=1
			check(nearWaypoint(q.Parent.CFrame.Position,16),q.ObjectText.." has a waypoint anchor")
		end
	end
	check(waypointTargets>=20,"stations, warps and services are waypointed ("..waypointTargets..")")
	for _,id in {"Skyreach","Windpine","Gloomhollow","Tidewater","Tempest"} do
		check(anchors["Anchor_Waypoint_Entrance_"..id]~=nil,id.." entrance waypoint")
	end
	for _,name in {"MosswakeGrove","BrassfallQuarry","WardenReach","GuildTerrace","MeadowReach","CinderShelf"} do
		check(anchors["Anchor_Waypoint_Bridge_"..name]~=nil,name.." bridge waypoint")
	end

	-- Mesh slots (contract section 10).
	local shapes,shapeCount={},0
	for _,obj in world:GetDescendants() do
		if obj:IsA("BasePart") and obj:GetAttribute("Shape")~=nil and not obj:GetAttribute("SculptureScale") then
			local shape,scale,tint=obj:GetAttribute("Shape"),obj:GetAttribute("ShapeScale"),obj:GetAttribute("Tint")
			check(type(shape)=="string" and #shape>0,"Shape is a name")
			check(scale==nil or (type(scale)=="number" and scale>0),obj.Name.." ShapeScale is positive")
			check(tint==nil or typeof(tint)=="Color3",obj.Name.." Tint is a Color3")
			shapes[shape]=(shapes[shape] or 0)+1
			shapeCount+=1
		end
	end
	local signShapes={Signboard=true,SignPost=true,Banner=true,SignCarvedBoard=true,SignScrollBoard=true,SignArrowBoard=true,
		SignPlaqueBoard=true,BannerCloth=true,SignNoticeBoard=true}
	local signBoards=0
	for _,gui in world:GetDescendants() do
		if gui:IsA("SurfaceGui") and gui.Parent:IsA("BasePart") and gui:FindFirstAncestor("Islands") then
			signBoards+=1
			check(signShapes[gui.Parent:GetAttribute("Shape")]==true,gui.Parent.Name.." sign carries a sign mesh slot")
		end
	end
	check(signBoards>=40,"signs on the static islands ("..signBoards..")")
	for _,need in {"Lamp","OreVein","CropBed","Rock","CliffRock","RockOutcrop","MeadowTree","PineTree","Forge","Hearth","Cauldron","Workbench","BridgePost","Statue","Signboard","Banner","MarketStall","FishingPier","WarpBeacon"} do
		check((shapes[need] or 0)>=1,need.." mesh slots exist")
	end
	-- Final mesh boxes: run MeshForge's own layout over every tagged part (no
	-- EditableMesh needed) and check what players would see. ShapeScale is a
	-- multiplier on an already-sized host (never an absolute size), cylinder hosts
	-- stand their mesh up, and ShapeOwnsModel boxes cover only a small prop Model.
	do
		local WorldArt=luau.load(fs.readFile("art/WorldCatalog.lua"),{injectGlobals=true})()
		local PropArt=luau.load(fs.readFile("art/PropCatalog.lua"),{injectGlobals=true})()
		local probe={}
		luau.load(fs.readFile("forge.client.lua"),{injectGlobals=true,environment={
			game={GetService=function(_,name)
				if name=="ReplicatedStorage" then return {WaitForChild=function(_,n) return n end} end
				return {}
			end},
			require=function(n) return if n=="AetherWorldArt" then WorldArt elseif n=="AetherArt" then PropArt else error(n) end,
			workspace={GetDescendants=function() return {} end,DescendantAdded={Connect=function() end}},
			Vector3=roblox.Vector3,CFrame=roblox.CFrame,Color3=roblox.Color3,Instance=roblox.Instance,Enum=roblox.Enum,Font=roblox.Font,
			task={spawn=function() end,defer=function() end,wait=function() end},warn=function() end,print=function() end,MeshForgeTest=probe,
		}})()
		local describe=probe.forge.describe
		local UPRIGHT={tree=true,crop=true,ore=true,sign=true,signframe=true,lamp=true,warp=true,stall=true,station=true,statue=true,tower=true,ship=true,plant=true,trap=true}
		local meshed,owners,upright=0,0,0
		local CREATURE_TAGS={Shellwarden=true,Tidewing=true}
		local resolved={}
		for _,obj in world:GetDescendants() do
			if obj:IsA("BasePart") and obj:GetAttribute("Shape")~=nil and not obj:GetAttribute("SculptureScale") then
				local scale=obj:GetAttribute("ShapeScale")
				check(scale==nil or (scale>=.5 and scale<=1.5),obj.Name.." ShapeScale stays a modest multiplier ("..tostring(scale)..")")
				if obj:GetAttribute("ShapeOwnsModel") then
					owners+=1
					local model=obj.Parent
					check(model:IsA("Model") and #model:GetChildren()<=40,obj:GetFullName().." owns only its own small prop Model")
				end
				local d=describe(obj)
				-- Every world prop tag has a catalog mesh; creatures stay with IslandArt.
				check(d~=nil or CREATURE_TAGS[obj:GetAttribute("Shape")]==true,obj:GetFullName().." Shape "..tostring(obj:GetAttribute("Shape")).." resolves to a catalog mesh")
				if d then
					meshed+=1
					resolved[d.shape]=(resolved[d.shape] or 0)+1
					if d.shape=="RopeSwing" or d.shape=="ZipLine" then
						-- Line meshes run along the host's longest axis.
						local own=obj.Size
						local long=math.max(own.X,own.Y,own.Z)
						check(math.abs(math.max(d.size.X,d.size.Y,d.size.Z)-long)<=long*.05+.05,obj:GetFullName().." line mesh follows its span")
					end
					if obj:GetAttribute("Shape")=="CropBed" and obj:FindFirstChildOfClass("ProximityPrompt") then
						check(d.shape==WorldArt.resourceShape(obj:FindFirstChildOfClass("ProximityPrompt"):GetAttribute("IsleItem")),obj:GetFullName().." crop patch shows its own crop")
					end
					local box,size=d.box,d.size
					for _,axis in {"X","Y","Z"} do
						check(size[axis]<=box[axis]*1.5+.6,obj:GetFullName().." mesh "..axis.." "..string.format("%.1f",size[axis]).." stays within 1.5x of its slot "..string.format("%.1f",box[axis]))
					end
					if #d.siblings==0 and obj:GetAttribute("ShapeBox")==nil then
						-- A lone host's slot is its own (upright) box.
						local own=obj.Size
						check(math.abs(box.X*box.Y*box.Z-own.X*own.Y*own.Z)<=1e-3*own.X*own.Y*own.Z+1e-6,obj.Name.." slot is the host's own box")
					end
					if UPRIGHT[d.kind] then
						upright+=1
						check(d.cframe.UpVector.Y>.95,obj:GetFullName().." "..d.shape.." mesh stands upright (up.Y "..string.format("%.2f",d.cframe.UpVector.Y)..")")
						check(size.Y>=.9,obj:GetFullName().." "..d.shape.." mesh is not flattened ("..string.format("%.2f",size.Y)..")")
						local hostTop=d.boxFrame.Position.Y+box.Y/2
						local meshTop=d.cframe.Position.Y+size.Y/2
						check(meshTop<=hostTop+box.Y*.5+.6,obj:GetFullName().." mesh top stays near its slot")
					end
					if d.kind=="tree" then
						check(size.Y>=box.Y*.6 and size.Y>=6,obj:GetFullName().." tree mesh fills its slot height ("..string.format("%.1f/%.1f",size.Y,box.Y)..")")
					end
					if d.kind=="sign" and obj:FindFirstChildOfClass("SurfaceGui") then
						-- The board frame wraps the text panel at its real size.
						check(size.X>=obj.Size.X and size.Y>=obj.Size.Y and size.X<=obj.Size.X*1.2,obj:GetFullName().." sign frame wraps the board")
					end
					if obj.Name=="Keel rock" or obj.Name=="Fractured cliff" then
						local isle=obj.Parent
						while isle and isle:GetAttribute("IslandCenter")==nil do isle=isle.Parent end
						if isle then
							local cf=d.cframe
							local meshTop=cf.Position.Y+math.abs(cf.RightVector.Y)*size.X/2+math.abs(cf.UpVector.Y)*size.Y/2+math.abs(cf.LookVector.Y)*size.Z/2
							check(meshTop<isle:GetAttribute("IslandCenter").Y,obj:GetFullName().." cliff mesh stays under the meadow")
						end
					end
				end
			end
		end
		for _,shape in {"Skyship","Lighthouse","Crane","FishingPier","Spyglass","AgilityPerch","ClimbNet","BalanceBeam","RopeSwing","LedgeWalk","ZipLine","SlideChute",
			"SnareTrap","BirdPerch","SwarmBloom","Waystone","StormPylon","StormSpire","Stalactite","RuinColumn","Column","Torch","CropBed","Bush","RockOutcrop","PalmTree","DeadTree","WindpineTree"} do
			check((resolved[shape] or 0)>=1,shape.." mesh is placed in the generated world")
		end
		check(meshed>=300 and upright>=150 and owners>=60,"mesh boxes checked ("..meshed.." meshed, "..upright.." upright, "..owners.." model owners)")
		print("Mesh boxes: "..meshed.." laid out, "..upright.." upright kinds, "..owners.." ShapeOwnsModel hosts.")
	end
	for _,model in islandsRoot:GetDescendants() do
		if model:IsA("Model") and model.Name=="Lamp post" then
			check(model:FindFirstChild("Bronze mast"):GetAttribute("Shape")=="Lamp","lamp posts are mesh slots")
		end
	end
	for _,q in islandsRoot:GetDescendants() do
		if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction")=="gather" then
			local host=q.Parent
			local tagged=host:GetAttribute("Shape")~=nil
			if not tagged then
				for _,sib in host.Parent:GetDescendants() do
					if sib:IsA("BasePart") and sib:GetAttribute("Shape") and (sib.CFrame.Position-host.CFrame.Position).Magnitude<30 then tagged=true break end
				end
			end
			check(tagged,q.ObjectText.." node has a mesh slot")
		end
	end

	-- Lights: hero shadows only, per-island and per-area caps, never buried.
	local function lightPos(l)
		local host=l.Parent
		if host:IsA("Attachment") then return (host.Parent.CFrame*host.CFrame).Position end
		return host.CFrame.Position
	end
	local lights,shadowed={},0
	for _,isle in islandsRoot:GetChildren() do
		local count=0
		for _,l in isle:GetDescendants() do
			if l:IsA("Light") then
				count+=1
				table.insert(lights,{l,lightPos(l)})
				if l.Shadows then shadowed+=1 end
				check(l.Brightness<=1.5,"light brightness stays modest")
				if l:IsA("PointLight") and l.Parent:IsA("BasePart") then
					check(l.Parent.Material==roblox.Enum.Material.Neon or l.Parent.Transparency>0,l.Parent.Name.." light is not buried in an opaque part")
				end
			end
		end
		check(count<=26,isle.Name.." stays within 26 lights ("..count..")")
	end
	check(shadowed>=3 and shadowed<=6,"shadows only on a few hero lights ("..shadowed..")")
	local worst=0
	for _,a in lights do
		local near=0
		for _,b in lights do if (a[2]-b[2]).Magnitude<=30 then near+=1 end end
		worst=math.max(worst,near)
		check(near<=6,"at most 6 lights within 30 studs (near "..a[1].Parent.Name..")")
	end
	local neon=0
	for _,obj in islandsRoot:GetDescendants() do
		if obj:IsA("BasePart") and obj.Material==roblox.Enum.Material.Neon then
			neon+=1
			check(math.max(obj.Size.X,obj.Size.Y,obj.Size.Z)<=10,obj.Name.." neon stays an accent")
		end
	end
	check(neon<=90,"neon is reserved for glowing accents ("..neon..")")
	-- Night lamps: downward spot lights, created off and tagged for the client
	-- director (§35), which lights them after dusk near the player.
	local lamps={}
	for _,l in world:GetDescendants() do if l:IsA("SpotLight") and l:GetAttribute("NightLight")==true then table.insert(lamps,l) end end
	check(#lamps>=40,"lamps are downward spot lights tagged NightLight ("..#lamps..")")
	for _,l in lamps do check(l.Enabled==false,"night lamps start dark (the director owns them)") end
	check(lum(roblox.Color3.fromHex("7D8A9C"))<.6,"reference ambient stays readable")

	-- Prompt holds: gathers read as swings, fishing as cast-bob-reel, interacts stay snappy.
	local fishing={}
	for _,def in Data.ResourceTiers.Fishing do fishing[def.id]=true end
	local holds={gather=0,fish=0,interact=0}
	for _,isle in allIsles() do for _,q in isle:GetDescendants() do
		if q:IsA("ProximityPrompt") then
			if q:GetAttribute("IsleAction")=="gather" then
				if fishing[q:GetAttribute("IsleItem")] then
					holds.fish+=1
					check(math.abs(q.HoldDuration-1.5)<1e-6,q.ObjectText.." fishing hold is 1.5 s")
				else
					holds.gather+=1
					check(math.abs(q.HoldDuration-1)<1e-6,q.ObjectText.." gather hold is 1.0 s")
				end
			elseif q:GetAttribute("IsleCoopResource") then
				check(math.abs(q.HoldDuration-1)<1e-6,"shared gather hold is 1.0 s")
			else
				holds.interact+=1
				check(math.abs(q.HoldDuration-.36)<1e-6,q.ObjectText.." interact hold stays 0.36 s")
			end
		end
	end end
	check(holds.gather>=30 and holds.fish>=8 and holds.interact>=20,"hold durations cover every prompt kind")

	-- Placement glow cap: a full island of lantern posts lights at most 10, spaced.
	local I=Data.Island
	local lit=player(54)
	local full={}
	for z=-I.RANGE,I.RANGE do for x=-I.RANGE,I.RANGE do
		if #full<60 and I.cellBlocked(x,z)==nil then table.insert(full,I.record({id=#full+1,prop="LanternPost",x=x,z=z,rot=0})) end
	end end
	lit:SetAttribute("IslandPlacements",table.concat(full,";"))
	local glows={}
	for _,l in archipelago:FindFirstChild("WayfarersRest_54"):FindFirstChild("Placements"):GetDescendants() do
		if l:IsA("PointLight") and l.Enabled then table.insert(glows,lightPos(l)) end
	end
	check(#glows>=4 and #glows<=10,"placed lanterns cap their glow ("..#glows.." lit of "..#full..")")
	for i=1,#glows do for j=i+1,#glows do check((glows[i]-glows[j]).Magnitude>=9,"lit lanterns never stack") end end

	local total=0
	local names={}
	for name,n in staticCounts do total+=n table.insert(names,name..": "..n) end
	table.sort(names)
	print("Static parts by island: "..table.concat(names,", ").." (total "..total..")")
	print("Mesh slots: "..shapeCount.." parts; lights "..#lights.." (worst cluster "..worst..", shadowed "..shadowed.."), neon "..neon..".")
	print("Wave 4: "..(checks-beforeChecks).." checks.")
end
-- Endgame: the Shattered Crown (region gating, warp, arenas, altar, nodes).
do
	local before=checks
	local E=Data.Endgame
	local crown=islandsRoot:FindFirstChild("The Shattered Crown")
	check(crown~=nil and crown:GetAttribute("Region")=="ShatteredCrown" and crown:GetAttribute("RegionId")=="ShatteredCrown","Shattered Crown island carries its region")
	check(crown:GetAttribute("IslandRadius")>=90,"Shattered Crown is a large island")
	local center=crown:GetAttribute("IslandCenter")
	local tempest=islandsRoot:FindFirstChild("Tempest Spire"):GetAttribute("IslandCenter")
	check(center.Y>tempest.Y+20,"the Crown floats above the Tempest Spire")
	for _,isle in islandsRoot:GetChildren() do
		if isle~=crown then
			local c,r=isle:GetAttribute("IslandCenter"),isle:GetAttribute("IslandRadius")
			check(Vec(c.X-center.X,0,c.Z-center.Z).Magnitude>r+96+150,"Shattered Crown and its arenas keep clear of "..isle.Name)
		end
	end
	local function flatDist(a,b) return Vec(a.X-b.X,0,a.Z-b.Z).Magnitude end
	-- Gated warp: one beacon on the Tempest Spire, lands on the Crown.
	local beacons=0
	for _,q in world:GetDescendants() do
		if q:IsA("ProximityPrompt") and q:GetAttribute("IsleWarpRegion")=="ShatteredCrown" then
			beacons+=1
			check(islandOf(q).Name=="Tempest Spire","Crown beacon stands on the Tempest Spire")
			check(q.ObjectText:find("COMBAT 60",1,true)~=nil and q.ObjectText:find("CROWN OF THE TEMPEST",1,true)~=nil,"beacon lists Combat 60 and the quest")
		end
	end
	check(beacons==1,"exactly one gated beacon reaches the Crown")
	local landing
	for _,l in landings do if l[1]=="ShatteredCrown landing" then landing=l[2] end end
	check(landing~=nil and onIsland(crown,landing,2),"Crown landing is on the island")
	-- Arenas: nested islets with anchors combat spawns world bosses on.
	local arenas=0
	for _,m in crown:GetChildren() do if m:IsA("Model") and m:GetAttribute("WorldBossArena") then arenas+=1 end end
	check(arenas==2,"two world boss arenas")
	for _,id in E.BossOrder do
		local a=crown:FindFirstChild("Anchor_WorldBoss_"..id)
		check(a~=nil and a.Parent==crown,id.." arena anchor is a direct child of the Crown")
		local pos=a.CFrame.Position
		check(flatDist(pos,landing)>=100,id.." arena is well away from the landing")
		for _,marker in spawnFolder:GetChildren() do
			check(flatDist(marker.CFrame.Position,pos)>=Data.WorldBosses[id].arenaRange+10,marker.Name.." stays outside the "..id.." arena")
		end
		local arena
		for _,m in crown:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("WorldBossArena") and flatDist(m:GetAttribute("IslandCenter"),pos)<1 then arena=m end
		end
		check(arena~=nil,id.." anchor marks an arena centre")
		check(arena:GetAttribute("IslandRadius")>=36,id.." arena is roomy")
		check(math.abs(arena:GetAttribute("IslandCenter").Y-center.Y)<1,id.." arena is level with the Crown")
		local guards=0
		for _,obj in arena:GetDescendants() do if obj.Name=="Edge guard" then guards+=1 end end
		check(guards>=8,id.." arena is guarded")
		-- Every telegraph radius fits inside the arena islet.
		for attackId,attack in Data.WorldBosses[id].attacks do
			check((attack.radius or 0)<=arena:GetAttribute("IslandRadius"),id.." "..attackId.." fits the arena")
		end
	end
	-- Bridges join both arenas to the Crown.
	local decks=0
	for _,obj in crown:GetDescendants() do if obj.Name=="Continuous bridge deck" then decks+=1 end end
	check(decks==2,"two bridges to the arenas")
	-- The Sovereign Altar.
	local altarPrompt
	for _,q in crown:GetDescendants() do if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction")=="bossSigil" then altarPrompt=q end end
	check(altarPrompt~=nil,"Sovereign Altar prompt exists")
	check(altarPrompt:GetAttribute("IsleItem")=="Aurelith" and altarPrompt:GetAttribute("IsleRegion")=="ShatteredCrown","altar names its boss and region gate")
	local aurelith=crown:FindFirstChild("Anchor_WorldBoss_Aurelith").CFrame.Position
	check(flatDist(altarPrompt.Parent.CFrame.Position,aurelith)<=40,"altar stands in the Sovereign's arena")
	local sockets=0
	for _,obj in crown:GetDescendants() do if obj.Name=="Sigil socket" then sockets+=1 end end
	check(sockets==Data.WorldBosses.Aurelith.sigils,"one socket per sigil")
	check(crown:FindFirstChild("Anchor_Waypoint_SovereignAltar")~=nil,"altar waypoint")
	-- Nodes and stations for the new tiers.
	for _,r in E.Resources do
		local found=0
		for _,q in crown:GetDescendants() do
			if q:IsA("ProximityPrompt") and q:GetAttribute("IsleItem")==r.id then
				found+=1
				check(q:GetAttribute("IsleRegion")=="ShatteredCrown",r.id.." node is region-gated")
				check(onIsland(crown,q.Parent.CFrame.Position,1),r.id.." node stands on the Crown")
			end
		end
		check(found>=1,r.id.." has a node on the Crown")
	end
	local stations={}
	for _,q in crown:GetDescendants() do if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction")=="station" then stations[q:GetAttribute("IsleItem")]=true end end
	check(stations.Forge and stations.Cauldron,"Crownforge and sigil cauldron")
	-- Monster grounds: every Crown monster spawns on the Crown.
	for _,id in E.MonsterOrder do
		local found=false
		for _,marker in spawnFolder:GetChildren() do
			if marker:GetAttribute("MonsterId")==id then
				found=true
				check(onIsland(crown,marker.CFrame.Position,marker:GetAttribute("Radius") or 0),id.." ground inside the Crown")
				check(flatDist(marker.CFrame.Position,landing)>=40,id.." ground is >= 40 studs from the landing")
			end
		end
		check(found,id.." has a spawn marker")
	end
	local crownParts=0
	for _,obj in crown:GetDescendants() do if obj:IsA("BasePart") then crownParts+=1 end end
	check(crownParts<=450,"Shattered Crown stays within 450 parts ("..crownParts..")")
	print("Endgame world: "..(checks-before).." checks; Shattered Crown "..crownParts.." parts.")
end
print("Depth world: "..tierCount.." resource tiers / "..nodeCount.." gather nodes, "..markers.." spawn markers, "..warps.." gated warps, "..stationCount.." stations, "..staticParts.." static parts, "..staticLights.." lights.")
print("World QA passed "..checks.." checks with "..parts.." parts, "..prompts.." prompts and "..signs.." sign surfaces.")

-- Completion sentinel: scripts/build.sh fails if a suite stops early without erroring.
print("SUITE-END verify-world.luau")
