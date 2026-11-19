-- Aether Isles archipelago. Gameplay is attached to prompts by the server.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Tags = game:GetService("CollectionService")
local world = Instance.new("Folder")
world.Name = "AetherIsles"
world.Parent = workspace
local V = Vector3.new
local C = Color3.fromHex
local ink, navy, brass, cream = C("192D3B"), C("294853"), C("DBAD65"), C("F9EDCD")
local teal, mint, rose = C("3C9291"), C("8EE6CB"), C("D67D6A")
local rock, shale, turf, timber = C("485565"), C("687481"), C("80A67C"), C("966B4C")
local SM, WO, ST, NE = Enum.Material.SmoothPlastic, Enum.Material.WoodPlanks, Enum.Material.Slate, Enum.Material.Neon
Lighting.ClockTime, Lighting.Brightness = 15.5, 2.2
Lighting.Ambient, Lighting.OutdoorAmbient = C("8B8E9E"), C("A8BECD")
Lighting.EnvironmentDiffuseScale = 0.76
Lighting.GlobalShadows = true
Lighting.ExposureCompensation = 0.15
local grade=Instance.new("ColorCorrectionEffect")
grade.Name,grade.Brightness,grade.Contrast,grade.Saturation="Aether cinematic grade",0.025,0.12,0.08
grade.TintColor=C("F4F8F5")
grade.Parent=Lighting
local bloom=Instance.new("BloomEffect")
bloom.Name,bloom.Intensity,bloom.Size,bloom.Threshold="Crystal glow",0.18,22,1.35
bloom.Parent=Lighting
local rays=Instance.new("SunRaysEffect")
rays.Intensity,rays.Spread=0.035,0.7
rays.Parent=Lighting
local air = Instance.new("Atmosphere")
air.Density, air.Offset, air.Color, air.Decay = 0.19, 0.15, C("DCE6DF"), C("AABBD1")
air.Parent = Lighting

local function group(name, parent)
	local model = Instance.new("Model")
	model.Name, model.Parent = name, parent or world
	return model
end
local function part(parent, name, size, cf, color, material, solid, shape)
	local p = Instance.new("Part")
	p.Name, p.Anchored = name, true
	p.Size, p.CFrame = size, cf
	p.Color, p.Material = color, material or SM
	p.CanCollide, p.CanTouch = solid == true, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end
local function disk(parent,name,pos,r,h,color,mat,solid)
	return part(parent,name,V(h,2*r,2*r),CFrame.new(pos)*CFrame.Angles(0,0,math.pi/2),color,mat,solid,Enum.PartType.Cylinder)
end
local function block(parent,name,pos,size,color,mat,solid)
	return part(parent,name,size,CFrame.new(pos),color,mat,solid)
end
local function gem(parent,name,pos,size,color,angle)
	return part(parent,name,size,CFrame.new(pos)*CFrame.Angles(0,angle or 0,math.rad(26)),color,Enum.Material.Glass,false)
end
local function beam(parent,name,a,b,width,color,mat)
	return part(parent,name,V(width,width,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),color,mat,false)
end
local function prompt(p, verb, item, action, id, owner)
	local q = Instance.new("ProximityPrompt")
	q.ActionText, q.ObjectText, q.HoldDuration = verb,item,0.36
	q.MaxActivationDistance, q.RequiresLineOfSight = 9,false
	if action then q:SetAttribute("IsleAction",action) end
	if id then q:SetAttribute("IsleItem",id) end
	if owner then q:SetAttribute("OwnerUserId",owner) end
	q.Parent = p
	return q
end
local function hidden(parent,name,pos)
	local p = block(parent,name,pos,V(1,1,1),cream,SM,false)
	p.Transparency = 1
	return p
end
local function sculpture(parent,name,pos,shape,scale,yaw)
	local anchor=hidden(parent,name,pos)
	anchor.CFrame=CFrame.new(pos)*CFrame.Angles(0,math.rad(yaw or 0),0)
	anchor:SetAttribute("Shape",shape)
	anchor:SetAttribute("SculptureScale",scale or 1)
	Tags:AddTag(anchor,"AetherSculpture")
	return anchor
end
local function sign(parent,pos,title,kicker,accent,yaw,width)
	width = width or 12
	local cf = CFrame.new(pos)*CFrame.Angles(0,math.rad(yaw or 0),0)
	for _, s in ipairs({-1,1}) do
		part(parent,"Brass-capped post",V(.28,5,.32),cf*CFrame.new(s*(width/2-.7),2.5,0),brass,Enum.Material.Metal,false)
	end
	local board = part(parent,title,V(width,3.1,.32),cf*CFrame.new(0,4,0),ink,SM,false)
	for _, face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
		local gui = Instance.new("SurfaceGui")
		gui.Face,gui.CanvasSize,gui.LightInfluence,gui.MaxDistance = face,Vector2.new(640,170),0,85
		gui.Parent = board
		local function rect(x,y,w,h,col)
			local frame = Instance.new("Frame")
			frame.BorderSizePixel,frame.BackgroundColor3 = 0,col
			frame.Position,frame.Size = UDim2.fromOffset(x,y),UDim2.fromOffset(w,h)
			frame.Parent = gui
			return frame
		end
		rect(0,0,640,170,ink)
		rect(6,6,628,2,accent) rect(6,162,628,2,accent)
		rect(14,20,5,130,accent)
		local crest = rect(40,62,43,43,accent)
		crest.Rotation = 45
		local hollow = rect(50,72,23,23,ink)
		hollow.Rotation = 45
		local function line(text,y,h,font,color)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency,t.TextXAlignment = 1,Enum.TextXAlignment.Left
			t.Position,t.Size = UDim2.fromOffset(110,y),UDim2.fromOffset(507,h)
			t.Font,t.TextColor3,t.Text,t.TextScaled = font,color,text,true
			t.Parent = gui
		end
		line(kicker,22,35,Enum.Font.GothamBold,accent)
		line(title,65,70,Enum.Font.GothamBold,cream)
	end
end

local function island(name,pos,r,top,stone,stratum,vein,ground)
	local m = group(name)
	stone, stratum = stone or rock, stratum or shale
	disk(m,"Floating foundation",pos-V(0,2.9,0),r,5.8,stone,ST,true)
	disk(m,"Mineral stratum",pos-V(0,6,0),r*.85,2.7,stratum,ST,false)
	disk(m,"Lower basalt",pos-V(0,8.8,0),r*.63,4.5,stone,ST,false)
	disk(m,"Meadow",pos-V(0,.25,0),r+.1,.5,top or turf,ground or Enum.Material.Grass,true)
	local count = r>=30 and 12 or 7
	for i=1,count do
		local a=i*2*math.pi/count
		local radial=V(math.cos(a),0,math.sin(a))
		local offset=pos+radial*(r*.86)-V(0,5+i%3,0)
		part(m,"Fractured cliff",V(r*.24,6+i%4,r*.28),CFrame.new(offset)*CFrame.Angles(.12,a,.18),i%2==0 and stone or stratum,ST,false)
		if i%3==0 then gem(m,"Aether vein",offset-V(0,4,0),V(1.3,5.4,1.3),vein or mint,a) end
	end
	m:SetAttribute("IslandRadius",r)
	return m
end
local function lamp(parent,pos)
	block(parent,"Lamp foot",pos+V(0,.3,0),V(1.4,.6,1.4),ink,ST,false)
	block(parent,"Bronze mast",pos+V(0,2.1,0),V(.25,3.7,.25),brass,SM,false)
	local lightAnchor=sculpture(parent,"Aether lantern",pos+V(0,4,0),"Lantern",0.7)
	local glow=Instance.new("PointLight")
	glow.Color,glow.Brightness,glow.Range,glow.Shadows=mint,0.6,9,false
	glow.Parent=lightAnchor
end
local function bridge(parent,a,b)
	local dir=(b-a).Unit
	local side=V(-dir.Z,0,dir.X)
	local cf=CFrame.lookAt((a+b)/2-V(0,.25,0),b-V(0,.25,0))
	part(parent,"Continuous bridge deck",V(7,.5,(b-a).Magnitude),cf,timber,WO,true)
	local count=math.ceil((b-a).Magnitude/3)
	for i=0,count do
		local p=a+(b-a)*i/count
		part(parent,"Cross tie",V(7.3,.12,.4),CFrame.lookAt(p,p+dir),brass,WO,false)
		if i%3==0 or i==count then
			for _,s in ipairs({-1,1}) do block(parent,"Railing post",p+side*3.7*s+V(0,1.2,0),V(.38,3,.38),ink,WO,false) end
		end
	end
	for _,s in ipairs({-1,1}) do
		beam(parent,"Guide rail",a+side*3.7*s+V(0,2.3,0),b+side*3.7*s+V(0,2.3,0),.27,brass,SM)
		-- Invisible collider behind the rail: the void is only crossed on the deck.
		local guard=part(parent,"Bridge guard",V(.4,5,(b-a).Magnitude),CFrame.lookAt((a+b)/2+side*3.9*s+V(0,2.5,0),b+side*3.9*s+V(0,2.5,0)),cream,SM,true)
		guard.Transparency,guard.CastShadow=1,false
	end
end

local function windpine(parent,pos,scale,owner)
	local m=group("Windpine",parent)
	local trunk=block(m,"Heartwood",pos+V(0,2.6*scale,0),V(1.2,5.2,1.2)*scale,timber,WO,true)
	trunk.Transparency=1
	sculpture(m,"Sculpted windpine",pos+V(0,2.6*scale,0),"WindpineCrown",scale)
	prompt(trunk,"Cut timber","Windpine","gather","Timber",owner)
end
local function ore(parent,pos)
	local base=disk(parent,"Ore seam",pos+V(0,.4,0),2.5,.8,shale,ST,false)
	sculpture(parent,"Faceted copper cluster",pos+V(0,1.4,0),"AetherCrystal",1)
	prompt(base,"Mine ore","Copper lode","gather","Ore")
end
local function herb(parent,pos)
	local bed=disk(parent,"Herb bed",pos+V(0,.15,0),2.3,.3,navy,ST,false)
	for i=1,6 do
		local a=i*1.8
		local p=pos+V(math.cos(a)*1.5,.65,math.sin(a)*1.5)
		sculpture(parent,"Sculpted moonbloom",p,"Moonbloom",.65,i*50)
	end
	prompt(bed,"Gather herbs","Moonleaf patch","gather","Herb")
end
local function marketStall(parent,pos,name,verb,action,item,accent)
	local m=group(name,parent)
	for _, x in ipairs({-3.2,3.2}) do
		for _, z in ipairs({-2,2}) do block(m,"Awning stay",pos+V(x,2.9,z),V(.3,5.8,.3),brass,SM,false) end
	end
	for i=-2,2 do
		part(m,"Striped canvas",V(1.55,.35,5.4),CFrame.new(pos+V(i*1.52,5.7,0))*CFrame.Angles(.09,0,0),i%2==0 and accent or cream,Enum.Material.Fabric,false)
	end
	local counter=block(m,"Counter",pos+V(0,1.4,0),V(6.5,2.8,2),navy,WO,true)
	block(m,"Counter top",pos+V(0,2.9,0),V(7,.25,2.5),brass,WO,false)
	sign(m,pos+V(0,.6,-2.65),name,"COMPASS QUAY   /   SERVICES",accent,0,8)
	prompt(counter,verb,name,action,item)
end
local hub = island("Compass Quay",V(0,0,0),43,C("9DAA85"))
local grove = island("Mosswake Grove",V(-97,0,0),30)
local mine = island("Brassfall Quarry",V(98,0,0),31,C("9C9682"))
local wild = island("Warden Reach",V(0,0,-103),32,C("7C8498"))
hub:SetAttribute("RegionId","Hub") grove:SetAttribute("RegionId","Meadow") mine:SetAttribute("RegionId","Quarry")
bridge(hub,V(-40,0,0),V(-69,0,0))
bridge(hub,V(40,0,0),V(69,0,0))
bridge(hub,V(0,0,-40),V(0,0,-73))
disk(hub,"Compass court",V(0,.05,0),13,.15,navy,ST,true)
for i=1,8 do
	local a=i*math.pi/4
	local d=V(math.cos(a),0,math.sin(a))
	beam(hub,"Compass inlay",d*3+V(0,.18,0),d*(i%2==0 and 12 or 8)+V(0,.18,0),.18,brass,SM)
end
disk(hub,"Brass compass boss",V(0,.18,0),2.1,.3,brass,SM,false)
sign(hub,V(7,0,15),"Compass Quay","01   /   SKY HARBOR",brass)
sign(hub,V(-29,0,6),"Mosswake Grove","WEST   /   TIMBER + HERBS",mint,0,10)
sign(hub,V(29,0,6),"Brassfall Quarry","EAST   /   COPPER ORE",brass,0,10)
sign(hub,V(7,0,-29),"Warden Reach","NORTH   /   HUNTS",rose,0,9)
marketStall(hub,V(-19,0,-12),"Quay Bank","Bank purse","bank",nil,mint)
marketStall(hub,V(18,0,-12),"Trade Counter","Sell goods","sell",nil,brass)
marketStall(hub,V(-19,0,16),"Starforge","Forge pickaxe","craft","Pickaxe",rose)
local rack=block(hub,"Bladesmith rack",V(-26,1.5,16),V(2,3,2),navy,ST,true)
prompt(rack,"Forge blade","Starforge","craft","Blade")
local apothecary=block(hub,"Apothecary vat",V(-12,1,16),V(2.5,2,2.5),teal,SM,true)
prompt(apothecary,"Brew tonic","Starforge","craft","Tonic")
for _,p in ipairs({V(12,0,12),V(-12,0,-6),V(12,0,-6),V(3,0,-39),V(39,0,3),V(-39,0,3)}) do lamp(hub,p) end
for _,p in ipairs({V(-82,0,-10),V(-93,0,-14),V(-109,0,9),V(-114,0,-3),V(-99,0,18)}) do windpine(grove,p,1.4) end
herb(grove,V(-83,0,6)) herb(grove,V(-98,0,1))
local pool=disk(grove,"Fishing pool",V(-103,.15,-12),7,.3,teal,Enum.Material.Glass,false)
for i=1,4 do
	disk(grove,"Ripple",V(-103+(i%2)*3,.32,-12+i*.8),.65,.05,mint,SM,false)
end
local dock=block(grove,"Fishing jetty",V(-98,.5,-8),V(3,1,7),timber,WO,true)
prompt(dock,"Cast line","Moonpool","gather","Fish")
sign(grove,V(-75,0,-6),"Moonpool","MOSSWAKE   /   ANGLING",mint,0,8)
for _,p in ipairs({V(78,0,5),V(88,0,-9),V(101,0,6),V(114,0,-7)}) do ore(mine,p) end
local advanced=group("Aetherite outcrop",mine)
local vein=sculpture(advanced,"Aetherite seam",V(110,1.5,12),"AetherCrystal",1.45,30)
prompt(vein,"Mine Aetherite","Mining 3 required","gather","Aetherite")
sign(advanced,V(117,0,13),"Aetherite","MINING 3 / REFINE AT THE STARFORGE",mint,0,8)
sculpture(hub,"Smith's pickaxe",V(-21,4,16),"Pickaxe",.7,25)
sculpture(hub,"Smith's blade",V(-26,4,16),"Blade",.65,-20)
sculpture(hub,"Alchemist tonic",V(-12,3,16),"Tonic",.7)
sculpture(hub,"Bank lockbox",V(-19,3.7,-12),"VaultChest",.65)
sculpture(hub,"Trader's timber",V(18,3.9,-12),"TimberBundle",.65,20)
for i=1,5 do
	local x=82+6*i
	block(mine,"Hoist support",V(x,2.5,14),V(.7,5,.7),timber,WO,false)
end
beam(mine,"Old crane",V(83,5,14),V(113,5,14),.6,timber,WO)
for _,z in ipairs({-85,-99,-114}) do
	for _,x in ipairs({-12,12}) do
		block(wild,"Waystone",V(x,3,z),V(2.5,6,2.5),rock,ST,true)
		gem(wild,"Signal prism",V(x,6.3,z),V(1,2.3,1),rose,.7)
	end
end
local boss=hidden(wild,"Shellwarden",V(0,2,-104))
boss:SetAttribute("Shape","Shellwarden")
Tags:AddTag(boss,"AetherSculpture")
prompt(boss,"Strike","Shellwarden","fight","Warden")
disk(wild,"Warden dais",V(0,.1,-104),7,.22,shale,ST,true)
sign(wild,V(6,0,-83),"Shellwarden","WARDEN REACH   /   HUNT",rose,0,10)
local gate=block(wild,"ExpeditionGate",V(0,2,-121),V(2,4,2),teal,Enum.Material.Glass,false)
gate.Transparency=1
gate:SetAttribute("Shape","ObservatoryArch")
gate:SetAttribute("SculptureScale",1)
Tags:AddTag(gate,"AetherSculpture")
for _,x in ipairs({-3.2,3.2}) do block(wild,"Vault pier",V(x,3.5,-121),V(2,7,2.4),rock,ST,true) end
block(wild,"Vault lintel",V(0,7.5,-121),V(9,1.4,2.4),brass,SM,false)
sign(wild,V(-8,0,-119),"Vault Gate","EXPEDITION   /   ENTRY",brass,0,7)
local sky=hidden(hub,"Tidewing",V(7,18,-8))
sky.CFrame *= CFrame.Angles(0,math.rad(33),0)
sky:SetAttribute("Shape","Tidewing")
Tags:AddTag(sky,"AetherSculpture")
for i=1,8 do
	local a=i*math.pi/4+.3
	local pos=V(math.cos(a)*215,-16+(i%3)*11,math.sin(a)*185)
	local landmark=group("Drifting spire")
	gem(landmark,"Distant basalt",pos,V(10+i%3*3,26,12),rock,a)
	gem(landmark,"Distant shard",pos+V(4,8,2),V(5,20,5),teal,a+.7)
end

local slots,homes={},{}
local function warp(player,trigger,destination)
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local hum=character and character:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health>0 and (trigger.CFrame.Position-root.Position).Magnitude<=12 then
		character:PivotTo(CFrame.new(destination))
		root.AssemblyLinearVelocity=Vector3.zero
	end
end
-- Skyreach is wide enough that its landing (west rim) sits >= 40 studs from both
-- monster markers (east rim); combat aggro range is 25.
local skyreach = island("Skyreach", V(208,36,52), 30, C("96ACAB"))
local SKYREACH_LANDING = V(184,40,52)
-- Assigned with the regional beacons below: pcall + table check + denial notice.
local regionTravel
skyreach:SetAttribute("RegionId","Skyreach")
local launch = sculpture(mine,"Charter beacon",V(123,2,0),"Lantern",1.2)
sign(mine,V(119,0,-4),"Skyreach passage","GUILD CHARTER REQUIRED",brass,0,9)
local launchPrompt=prompt(launch,"Ascend to Skyreach","Guild charter required")
launchPrompt:SetAttribute("IsleWarpRegion","Skyreach")
launchPrompt.Triggered:Connect(function(player)
	regionTravel(player,launch,"Skyreach",SKYREACH_LANDING)
end)
local descent = sculpture(skyreach,"Quarry beacon",V(190,38,46),"Lantern",1.1)
prompt(descent,"Return to quarry","Brassfall").Triggered:Connect(function(player)
	warp(player,descent,V(118,4,1))
end)
local survey = sculpture(skyreach,"Summit cartographer",V(209,38,40),"Surveyor",1.1,180)
prompt(survey,"Survey the summit","Skyreach","explore","Skyreach"):SetAttribute("IsleRegion","Skyreach")
local rich = sculpture(skyreach,"Rich Aetherite seam",V(218,38,56),"AetherCrystal",1.8)
prompt(rich,"Mine rich seam","Skyreach Aetherite","gather","Aetherite"):SetAttribute("IsleRegion","Skyreach")
sign(skyreach,V(201,36,44),"Skyreach","SURVEY THE SUMMIT / MINE RICH SEAMS",mint,0,10)
local returnPost=block(hub,"Homeward beacon",V(0,2,30),V(2,4,2),mint,Enum.Material.Glass,false)
sign(hub,V(7,0,30),"Homeward","WAYFARER TRANSIT   /   RETURN",mint,0,9)
prompt(returnPost,"Travel home","Homeward beacon").Triggered:Connect(function(player)
	local home=homes[player]
	if home then warp(player,returnPost,home.spawn.Position+V(0,4,0)) end
end)
local function settle(player)
	if homes[player] then return end
	local slot=1
	while slots[slot] do slot+=1 end
	slots[slot]=true
	local center=V((slot-1)%5*65-130,0,320+math.floor((slot-1)/5)*65)
	local m=island("WayfarersRest_"..player.UserId,center,19)
	local spawn=Instance.new("SpawnLocation")
	spawn.Name,spawn.Anchored,spawn.Neutral,spawn.AllowTeamChangeOnTouch="Home Landing",true,true,false
	spawn.Size,spawn.Position,spawn.Transparency=V(4,.45,4),center+V(0,.25,5),1
	spawn.Duration,spawn.Parent=0,m
	player.RespawnLocation=spawn
	homes[player]={model=m,spawn=spawn,slot=slot,decorationConnections={}}
	local function land(character)
		local root=character:WaitForChild("HumanoidRootPart",10)
		if root and homes[player] and player.Character==character then character:PivotTo(CFrame.new(spawn.Position+V(0,3.4,0))) end
	end
	player.CharacterAdded:Connect(land)
	if player.Character then task.spawn(land,player.Character) end
	windpine(m,center+V(-6,0,0),1,player.UserId)
	sign(m,center+V(6,0,-5),"Wayfarer's Rest","HOME   /   CUT WINDPINE TO BEGIN",mint,0,9)
	local gatePost=block(m,"Quay beacon",center+V(0,2,-11),V(2,4,2),mint,Enum.Material.Glass,false)
	for _,x in ipairs({-2.3,2.3}) do gem(m,"Transit fins",center+V(x,2,-11),V(.65,4,.65),brass,0) end
	prompt(gatePost,"Travel to hub","Compass Quay").Triggered:Connect(function(user)
		if user==player then warp(user,gatePost,V(0,4,19)) end
	end)
	local fleetOffsets={V(9,0,4),V(13,0,-1),V(-10,0,-10)}
	for workerSlot,offset in ipairs(fleetOffsets) do
		local station=group("WorkerStation"..workerSlot,m)
		local position=center+offset
		disk(station,"Worker pad",position+V(0,.08,0),2.3,.16,navy,SM,false)
		local engine=block(station,"Surveyor chassis",position+V(0,1.35,0),V(2.8,2.7,2.5),navy,SM,true)
		local lens=block(station,"Eye lens",position+V(0,1.7,-1.35),V(1.55,.38,.18),mint,NE,false)
		engine.Transparency,lens.Transparency=1,1
		sculpture(station,"Sculpted surveyor",position+V(0,1.5,0),"Surveyor",1)
		local interaction=prompt(engine,"Build worker","Surveyor chassis",workerSlot==1 and "worker" or "workerBuild",tostring(workerSlot),player.UserId)
		local badge=Instance.new("BillboardGui")
		badge.Name,badge.Size,badge.StudsOffset,badge.MaxDistance="Worker status",UDim2.fromOffset(160,44),V(0,3,0),12
		badge.Parent=engine
		local text=Instance.new("TextLabel")
		text.Size,text.BackgroundColor3,text.BackgroundTransparency=UDim2.fromScale(1,1),ink,.12
		text.TextColor3,text.TextSize,text.TextWrapped,text.Font=cream,14,true,Enum.Font.GothamBold
		text.Parent=badge
		local cachePrompt
		if workerSlot==1 then
			local cache=block(station,"Surveyor cache",center+V(11,.8,9),V(2.6,1.6,2.1),timber,WO,true)
			cache.Transparency=1
			sculpture(station,"Worker lockbox",center+V(11,1,9),"VaultChest",1)
			cachePrompt=prompt(cache,"Claim output","Surveyor cache","claim",nil,player.UserId)
		end
		local function refreshWorker()
			if not m.Parent then return end
			local tier=player:GetAttribute("Worker"..workerSlot.."Tier") or 0
			local resource=player:GetAttribute("Worker"..workerSlot.."Resource") or "Ore"
			local active=tier>0
			lens.Color=active and mint or shale
			engine.Color=active and teal or navy
			interaction.ActionText=active and "Claim output" or "Build worker"
			interaction.ObjectText="Worker "..workerSlot..(active and (" · "..resource) or (" · "..(5*workerSlot).." timber + "..(3*workerSlot).." ore"))
			interaction:SetAttribute("IsleAction",active and "workerClaim" or (workerSlot==1 and "worker" or "workerBuild"))
			text.Text=active and ("WORKER "..workerSlot.." · TIER "..tier.."\n"..resource.." / manage in Atlas") or ("WORKER "..workerSlot.."\nUnbuilt surveyor chassis")
			if cachePrompt then cachePrompt.Enabled=active end
		end
		for _,suffix in ipairs({"Tier","Resource"}) do
			table.insert(homes[player].decorationConnections,player:GetAttributeChangedSignal("Worker"..workerSlot..suffix):Connect(refreshWorker))
		end
		refreshWorker()
	end
	lamp(m,center+V(-5,0,-9))
	local plans=block(m,"Homestead plans",center+V(-5,1,11),V(4,2,2),navy,WO,true)
	sign(m,center+V(-5,0,14),"Make it yours","HOMESTEAD   /   BUILDING PLANS",brass,0,10)
	local additions={
		{key="Lanterns",label="Lanterns · 5 timber",offset=V(-3,0,0)},
		{key="Garden",label="Garden · 3 herbs + 3 timber",offset=V(0,0,0)},
		{key="Deck",label="Deck · 10 timber + 5 ore",offset=V(3,0,0)},
	}
	local built={}
	local function decorate(key)
		if built[key] or not player:GetAttribute("Home"..key) or not m.Parent then return end
		built[key]=true
		local addition=group(key,m)
		if key=="Lanterns" then
			for _,offset in ipairs({V(-12,0,-8),V(12,0,-7),V(-13,0,6),V(6,0,12)}) do lamp(addition,center+offset) end
		elseif key=="Garden" then
			block(addition,"Raised planter",center+V(-11,.3,1),V(6,.6,7),timber,WO,false)
			block(addition,"Rich soil",center+V(-11,.63,1),V(5.4,.14,6.4),ink,Enum.Material.Ground,false)
			for row=-1,1 do
				for col=-1,1 do
					local flower=center+V(-11+col*1.6,1.2,1+row*1.8)
					block(addition,"Flower stem",flower,V(.14,1,.14),teal,SM,false)
					gem(addition,"Moonbloom",flower+V(0,.65,0),V(.9,.7,.9),row%2==0 and rose or cream,col*.6)
				end
			end
		else
			bridge(addition,center+V(0,0,17),center+V(0,0,25))
			disk(addition,"Lookout deck",center+V(0,-.3,29),7,.6,timber,WO,true)
			for i=1,9 do
				local a=i*math.pi/6
				lamp(addition,center+V(math.cos(a)*6,0,29+math.sin(a)*6))
			end
			block(addition,"Lookout bench",center+V(0,.9,31),V(5,.4,1.7),navy,WO,true)
			block(addition,"Bench back",center+V(0,1.6,31.9),V(5,1.8,.3),brass,WO,false)
		end
	end
	for _,choice in ipairs(additions) do
		local plan=hidden(m,choice.key.." plans",plans.Position+choice.offset+V(0,1,0))
		prompt(plan,"Build",choice.label,"decorate",choice.key,player.UserId)
		table.insert(homes[player].decorationConnections,player:GetAttributeChangedSignal("Home"..choice.key):Connect(function()
			decorate(choice.key)
		end))
		decorate(choice.key)
	end
end
Players.PlayerAdded:Connect(settle)
Players.PlayerRemoving:Connect(function(player)
	local home=homes[player]
	if home then
		for _,connection in ipairs(home.decorationConnections or {}) do connection:Disconnect() end
		homes[player]=nil slots[home.slot]=nil home.model:Destroy()
	end
end)
for _,player in ipairs(Players:GetPlayers()) do settle(player) end

-- Group islands are instantiated once per local crew; their build flags come
-- from the co-op service's persistent group record, never from client intent.
local sharedHomes,sharedPlayers,sharedSlots,sharedConnections={},{},{},{}
local sharedBeacon=block(hub,"Crew beacon",V(22,2,26),V(2,4,2),teal,Enum.Material.Glass,false)
sign(hub,V(29,0,23),"Crew Haven","CO-OP / FORM A CREW IN THE ATLAS",mint,0,9)
prompt(sharedBeacon,"Visit shared island","Crew Haven").Triggered:Connect(function(player)
	local home=sharedHomes[sharedPlayers[player]]
	if home then warp(player,sharedBeacon,home.center+V(0,4,6)) end
end)
local function makeShared(groupKey,groupId,isPreview)
	local slot=1
	while sharedSlots[slot] do slot+=1 end
	sharedSlots[slot]=true
	local center=V(((slot-1)%5)*100-200,0,-420-math.floor((slot-1)/5)*100)
	local model=island("CrewHaven_"..groupKey,center,28)
	model:SetAttribute("CoopId",groupId)
	local home={model=model,center=center,slot=slot,members={},built={}}
	sharedHomes[groupKey]=home
	sign(model,center+V(8,0,8),"Crew Haven","SHARED SUPPLIES / BUILD IN THE ATLAS",mint,0,12)
	local exit=block(model,"Quay return",center+V(0,2,16),V(2,4,2),mint,Enum.Material.Glass,false)
	prompt(exit,"Return to hub","Compass Quay").Triggered:Connect(function(player)
		if sharedPlayers[player]==groupKey then warp(player,exit,V(22,4,22)) end
	end)
	local function supply(name,pos,color)
		local base=block(model,"Shared "..name,center+pos,V(3,2,3),color,WO,true)
		base.Transparency=1
		sculpture(model,name.." supply marker",center+pos+V(0,.4,0),({Timber="TimberBundle",Ore="AetherCrystal",Herb="Moonbloom"})[name],1)
		local interaction=prompt(base,"Gather shared "..name,"Crew stores")
		interaction:SetAttribute("CoopId",groupId)
		interaction:SetAttribute("CoopPreview",isPreview)
		interaction:SetAttribute("IsleCoopResource",name)
	end
	supply("Timber",V(-12,1,-5),timber)
	supply("Ore",V(0,1,-14),shale)
	supply("Herb",V(12,1,-5),teal)
	for _,offset in ipairs({V(-6,0,12),V(6,0,12)}) do lamp(model,center+offset) end
	return home
end
local function sharedDecorate(home,player)
	for _,key in ipairs({"Garden","Lanterns","Deck"}) do
		if not home.built[key] and player:GetAttribute("Coop"..key)==true then
			home.built[key]=true
			local addition=group(key,home.model)
			local center=home.center
			if key=="Garden" then
				block(addition,"Crew planter",center+V(-14,.4,8),V(7,.8,7),timber,WO,true)
				for row=-1,1 do for col=-1,1 do
					gem(addition,"Shared moonbloom",center+V(-14+col*2,1.5,8+row*2),V(.8,1.6,.8),mint,row*.5)
				end end
			elseif key=="Lanterns" then
				for _,offset in ipairs({V(-20,0,-8),V(20,0,-8),V(-18,0,16),V(18,0,16)}) do lamp(addition,center+offset) end
			else
				bridge(addition,center+V(0,0,-24),center+V(0,0,-32))
				disk(addition,"Crew lookout",center+V(0,-.3,-37),7,.6,timber,WO,true)
				lamp(addition,center+V(-5,0,-37)) lamp(addition,center+V(5,0,-37))
			end
		end
	end
end
local function detachShared(player)
	local old=sharedPlayers[player]
	sharedPlayers[player]=nil
	local home=old and sharedHomes[old]
	if home then
		home.members[player]=nil
		if not next(home.members) then
			sharedSlots[home.slot]=nil
			sharedHomes[old]=nil
			home.model:Destroy()
		end
	end
end
local function watchShared(player)
	if sharedConnections[player] then return end
	local function sync()
		local groupId=player:GetAttribute("CoopId")
		local isPreview=player:GetAttribute("CoopPreview")==true
		local groupKey=if type(groupId)=="string" then (if isPreview then "preview_" else "")..groupId else nil
		if groupKey~=sharedPlayers[player] then detachShared(player) end
		if type(groupId)~="string" or groupId=="" then return end
		local home=sharedHomes[groupKey] or makeShared(groupKey,groupId,isPreview)
		sharedPlayers[player]=groupKey
		home.members[player]=true
		sharedDecorate(home,player)
	end
	local connections={}
	sharedConnections[player]=connections
	for _,attribute in ipairs({"CoopId","CoopPreview","CoopGarden","CoopLanterns","CoopDeck"}) do
		table.insert(connections,player:GetAttributeChangedSignal(attribute):Connect(sync))
	end
	sync()
end
Players.PlayerAdded:Connect(watchShared)
Players.PlayerRemoving:Connect(function(player)
	for _,connection in ipairs(sharedConnections[player] or {}) do connection:Disconnect() end
	sharedConnections[player]=nil
	detachShared(player)
end)
for _,player in ipairs(Players:GetPlayers()) do watchShared(player) end

-------------------------------------------------------------------------------
-- Depth update: the Guild Terrace, Meadow Reach, Cinder Shelf and four gated
-- regions. Every resource tier, monster ground and crafting station has a
-- place. All geometry is static and anchored; no per-frame work.
-------------------------------------------------------------------------------
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local dataModule=ReplicatedStorage:WaitForChild("AetherData",30)
if not dataModule then
	warn("Archipelago: AetherData unavailable; depth regions were not built.")
	return
end
local Data=require(dataModule)
local Resource={}
for skill,tiers in pairs(Data.ResourceTiers) do
	for index,def in ipairs(tiers) do Resource[def.id]={def=def,skill=skill,index=index,color=C(def.color)} end
end
local VERB={Mining="Mine",Woodcutting="Chop",Fishing="Fish",Farming="Harvest"}
local GL,MT,SA,GR,LEAF=Enum.Material.Glass,Enum.Material.Metal,Enum.Material.Sand,Enum.Material.Ground,Enum.Material.LeafyGrass
local BALL=Enum.PartType.Ball
local function lighten(c,f) return c:Lerp(cream,f) end
local function darken(c,f) return c:Lerp(ink,f) end
local function light(parent,color,brightness,range)
	local l=Instance.new("PointLight")
	l.Color,l.Brightness,l.Range,l.Shadows=color,brightness,range,false
	l.Parent=parent
	return l
end
local function ball(parent,name,pos,d,color,mat)
	return part(parent,name,V(d,d,d),CFrame.new(pos),color,mat,false,BALL)
end
local function ghost(p)
	p.Transparency,p.CastShadow=1,false
	if not p.CanCollide then p.CanQuery=false end
	return p
end
local function motes(parent,color,rate,speed,size)
	local e=Instance.new("ParticleEmitter")
	e.Name="Ambient motes"
	e.Rate,e.LightEmission=rate,.9
	e.Lifetime,e.Speed=NumberRange.new(3,6),NumberRange.new(speed*.5,speed)
	e.SpreadAngle=Vector2.new(180,180)
	e.Size=NumberSequence.new(size)
	e.Color=ColorSequence.new(color)
	e.Parent=parent
	return e
end
-- Invisible edge guard ring keeps players on an island; gaps open at bridges.
local function rim(parent,pos,r,gaps)
	local n=math.ceil(2*math.pi*r/12)
	for i=0,n-1 do
		local a=(i+.5)*2*math.pi/n
		local open=false
		for _,g in ipairs(gaps or {}) do
			if math.abs(math.atan2(math.sin(a-g),math.cos(a-g)))<5/r+math.pi/n then open=true end
		end
		if not open then
			local radial=V(math.cos(a),0,math.sin(a))
			local spot=pos+radial*(r-.4)+V(0,3.5,0)
			ghost(part(parent,"Edge guard",V(2*r*math.sin(math.pi/n)+.8,7,1),CFrame.lookAt(spot,spot+radial),cream,SM,true))
		end
	end
end
local function regionIsle(id,name,pos,r,top,stone,stratum,vein,ground,gaps)
	local m=island(name,pos,r,top,stone,stratum,vein,ground)
	m:SetAttribute("RegionId",id)
	rim(m,pos,r,gaps)
	return m
end
local function nodeLabel(id) return Resource[id].def.name.." (Lv "..Resource[id].def.level..")" end
-- The original public nodes adopt the tiered "<Name> (Lv N)" labels.
for _,q in ipairs(world:GetDescendants()) do
	local id=q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction")=="gather" and q:GetAttribute("IsleItem")
	if id and Resource[id] and not q:GetAttribute("OwnerUserId") then
		q.ActionText=VERB[Resource[id].skill]
		q.ObjectText=nodeLabel(id)..(if q:GetAttribute("IsleRegion") then " · rich seam" else "")
	end
end
local function gatherPrompt(target,id,region)
	local r=Resource[id]
	assert(r,"unknown resource "..tostring(id))
	local q=prompt(target,VERB[r.skill],nodeLabel(id),"gather",id)
	q.MaxActivationDistance=if r.skill=="Fishing" then 12 else 10
	if region then q:SetAttribute("IsleRegion",region) end
	target:SetAttribute("ResourceId",id)
	return q
end

-- Ore: a slate boulder split by a metal vein, crowned by a crystal cluster.
local function oreNode(parent,pos,id,region,scale)
	local r,s=Resource[id],scale or 1
	local m=group(r.def.name.." vein",parent)
	local base=part(m,"Ore boulder",V(4.4,2.3,3.8)*s,CFrame.new(pos+V(0,1.05*s,0))*CFrame.Angles(0,r.index,.08),darken(shale,.3),ST,false)
	part(m,"Ore vein",V(4.6,.35,.55)*s,CFrame.new(pos+V(0,1.4*s,0))*CFrame.Angles(.35,r.index,.4),r.color,MT,false)
	local glowing=r.index>=5
	for i=1,3 do
		local a=r.index+i*2.1
		local h=(2+i*.8)*s
		local shard=gem(m,"Crystal shard",pos+V(math.cos(a)*1.1*s,1.9*s+h*.3,math.sin(a)*1.1*s),V(.9+i*.2,h,.9+i*.2)*s,i==1 and lighten(r.color,.25) or r.color,a)
		if glowing and i==3 then shard.Material=NE end
	end
	if glowing then light(base,r.color,.9,14) end
	gatherPrompt(base,id,region)
	return m
end

-- Trees: one silhouette per log tier. The prompt sits on the root collar.
local function pagodaPine(parent,pos,color,scale,name)
	local m=group(name or "Towering windpine",parent)
	local s=scale or 1
	disk(m,"Pine trunk",pos+V(0,10*s,0),.9*s,20*s,darken(timber,.25),WO,true)
	local tiers={{9,2.2,8},{7.4,2,11.5},{5.6,1.8,14.8},{3.6,1.6,17.8},{1.6,2,20.2}}
	for i,t in ipairs(tiers) do
		part(m,"Needle tier",V(t[1],t[2],t[1])*s,CFrame.new(pos+V(0,t[3]*s,0))*CFrame.Angles(0,i%2*math.pi/4,0),i%2==0 and lighten(color,.12) or darken(color,.15),LEAF,false)
	end
	return m
end
local function treeNode(parent,pos,id,region)
	local r=Resource[id]
	local col=r.color
	local m,collar
	if id=="WindpineLog" then
		m=pagodaPine(parent,pos,col,1.15,r.def.name.." tree")
		collar=disk(m,"Root collar",pos+V(0,.6,0),1.6,1.2,timber,WO,false)
	elseif id=="EmberoakLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.6,0),2.2,1.2,darken(timber,.2),WO,false)
		disk(m,"Emberoak trunk",pos+V(0,5,0),1.4,10,darken(col,.45),WO,true)
		beam(m,"Bough",pos+V(0,7,0),pos+V(3.5,10,1),.8,darken(col,.45),WO)
		beam(m,"Bough",pos+V(0,6.5,0),pos+V(-3,9.5,-1.5),.8,darken(col,.45),WO)
		ball(m,"Ember canopy",pos+V(0,12,0),9,col,LEAF)
		ball(m,"Ember canopy",pos+V(3.4,10.6,1.2),6.5,lighten(col,.15),LEAF)
		ball(m,"Ember canopy",pos+V(-3,10.3,-1.4),6,darken(col,.1),LEAF)
		local ember=ball(m,"Glowing ember",pos+V(1.5,8.4,-2.6),.8,C("FFB25C"),NE)
		ball(m,"Glowing ember",pos+V(-2.2,9,2.4),.6,C("FFB25C"),NE)
		light(ember,C("FF9A52"),.8,12)
	elseif id=="GlimmerbarkLog" then
		m=group(r.def.name.." tree",parent)
		for i=1,3 do
			local a=i*2*math.pi/3
			beam(m,"Stilt root",pos+V(math.cos(a)*3,0,math.sin(a)*3),pos+V(0,3.5,0),.55,lighten(col,.35),WO)
		end
		collar=disk(m,"Root collar",pos+V(0,.3,0),1.4,.6,lighten(col,.3),WO,false)
		disk(m,"Glimmer trunk",pos+V(0,7.3,0),.75,8,lighten(col,.45),GL,true)
		local crown=disk(m,"Glimmer crown",pos+V(0,11.6,0),4.8,1.3,col,GL,false)
		disk(m,"Glimmer underglow",pos+V(0,10.9,0),3.6,.25,lighten(col,.2),NE,false)
		disk(m,"Glimmer crest",pos+V(0,12.8,0),3,1,lighten(col,.25),GL,false)
		light(crown,col,1,16)
	elseif id=="StarwoodLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.6,0),1.6,1.2,darken(col,.3),WO,false)
		disk(m,"Starwood trunk",pos+V(0,6.5,0),1,13,darken(col,.2),WO,true)
		ball(m,"Night canopy",pos+V(0,13,0),7,col,LEAF)
		ball(m,"Night canopy",pos+V(0,16.5,0),5,lighten(col,.12),LEAF)
		for i=1,4 do
			local a=i*math.pi/2+.4
			part(m,"Star bud",V(.8,.8,.8),CFrame.new(pos+V(math.cos(a)*3.3,13.5+i%2*2,math.sin(a)*3.3))*CFrame.Angles(math.pi/4,a,math.pi/4),i%2==0 and cream or C("CFE3FF"),NE,false)
		end
		light(collar,C("BFD7FF"),.7,12)
	elseif id=="AetherheartLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.7,0),4.4,1.4,darken(col,.55),WO,false)
		disk(m,"Aetherheart trunk",pos+V(0,12,0),3,24,darken(col,.5),WO,true)
		for i=1,4 do
			local a=i*math.pi/2+.3
			part(m,"Root flare",V(1.6,3,6),CFrame.new(pos+V(math.cos(a)*3.6,1,math.sin(a)*3.6))*CFrame.Angles(0,-a+math.pi/2,0)*CFrame.Angles(.35,0,0),darken(col,.5),WO,false)
		end
		ball(m,"Golden canopy",pos+V(0,27,0),16,col,LEAF)
		ball(m,"Golden canopy",pos+V(6,24,3),11,lighten(col,.2),LEAF)
		ball(m,"Golden canopy",pos+V(-6,24.5,-2),12,darken(col,.08),LEAF)
		ball(m,"Golden canopy",pos+V(1,23.5,-6.5),10,lighten(col,.1),LEAF)
		local core=ball(m,"Aetherheart core",pos+V(0,19.5,0),2.2,C("FFF6C8"),NE)
		light(core,C("FFE9A8"),1.2,34)
	else
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.5,0),1.5,1,timber,WO,false)
		local trunk=block(m,"Heartwood",pos+V(0,3.4,0),V(1.6,6.8,1.6),timber,WO,true)
		trunk.Transparency=1
		sculpture(m,"Sculpted windpine",pos+V(0,3.4,0),"WindpineCrown",1.3,r.index*40)
	end
	gatherPrompt(collar,id,region)
	return m
end

-- Fishing: a pool with ripples and a bobber, reached by a short plank pier.
local function fishSpot(parent,pos,id,region,dir,pierLen,poolRadius)
	local r=Resource[id]
	local m=group(r.def.name.." fishing spot",parent)
	if poolRadius then
		local water=disk(m,"Fishing water",pos+V(0,.12,0),poolRadius,.24,teal:Lerp(r.color,.3),GL,false)
		water.Transparency=.08
	end
	for i=1,3 do
		disk(m,"Ripple",pos+V(math.cos(i*2.1)*.9,.27+i*.01,math.sin(i*2.1)*.9),.35+i*.3,.04,lighten(r.color,.35+i*.12),SM,false)
	end
	ball(m,"Bobber",pos+V(.4,.5,.2),.75,r.color,NE)
	ball(m,"Bobber cap",pos+V(.4,.95,.2),.42,cream,SM)
	dir=(dir or V(0,0,1)).Unit
	pierLen=pierLen or 6
	local near,far=pos+dir*1.6,pos+dir*(1.6+pierLen)
	local pier=part(m,"Fishing pier",V(3,.4,pierLen),CFrame.lookAt((near+far)/2+V(0,.55,0),far+V(0,.55,0)),timber,WO,true)
	for _,s in ipairs({-1,1}) do
		local side=V(-dir.Z,0,dir.X)*1.4*s
		block(m,"Pier post",near+side+V(0,.9,0),V(.35,1.8,.35),ink,WO,false)
	end
	gatherPrompt(pier,id,region)
	return m
end

-- Crops: a soil bed with plants shaped for each tier.
local function cropPatch(parent,pos,id,region)
	local r=Resource[id]
	local col=r.color
	local m=group(r.def.name.." patch",parent)
	local wet=id=="AetherLotus"
	local bed=block(m,wet and "Lotus pool" or "Soil bed",pos+V(0,.2,0),V(6.4,.4,5),wet and teal or darken(timber,.55),wet and GL or GR,true)
	block(m,"Bed border",pos+V(0,.25,2.65),V(6.8,.5,.35),timber,WO,false)
	for i=1,6 do
		local x,z=((i-1)%3-1)*1.9,(math.floor((i-1)/3)-.5)*2
		local p=pos+V(x,.4,z)
		if id=="Sunwheat" then
			part(m,"Wheat stalk",V(.45,2.6,.45),CFrame.new(p+V(0,1.3,0))*CFrame.Angles(.08*x,0,.06*z),i%2==0 and lighten(col,.15) or col,Enum.Material.Fabric,false)
		elseif id=="Glowcap" then
			disk(m,"Cap stalk",p+V(0,.45,0),.18,.9,cream,SM,false)
			disk(m,"Glowing cap",p+V(0,1,0),.65,.35,col,NE,false)
		elseif id=="Moonbloom" then
			gem(m,"Moonbloom",p+V(0,.8,0),V(.8,1.2,.8),i%2==0 and lighten(col,.2) or col,i*.6).Material=NE
		elseif id=="Starfruit" then
			ball(m,"Starfruit bush",p+V(0,.7,0),1.5,C("4F7A4A"),LEAF)
			part(m,"Starfruit",V(.55,.55,.55),CFrame.new(p+V(.2,1.45,0))*CFrame.Angles(math.pi/4,i,math.pi/4),col,NE,false)
		elseif wet then
			disk(m,"Lily pad",p+V(0,.05,0),.8,.08,C("5E9C62"),SM,false)
			gem(m,"Lotus bloom",p+V(0,.45,0),V(.6,.7,.6),i%2==0 and lighten(col,.25) or col,i).Material=NE
		else
			ball(m,"Herb tuft",p+V(0,.45,0),.9,i%2==0 and lighten(col,.15) or col,LEAF)
		end
	end
	if r.index>=4 then light(bed,col,.6,10) end
	gatherPrompt(bed,id,region)
	return m
end

-- Monster grounds. Combat owns models, AI and respawn; World only marks ground.
local spawnFolder=workspace:FindFirstChild("MonsterSpawns")
if not spawnFolder then
	spawnFolder=Instance.new("Folder")
	spawnFolder.Name="MonsterSpawns"
	spawnFolder.Parent=workspace
end
local function spawnMarker(monsterId,pos,count,radius)
	local def=Data.Monsters[monsterId]
	assert(def,"unknown monster "..tostring(monsterId))
	local p=ghost(part(spawnFolder,monsterId.." spawn",V(4,1,4),CFrame.new(pos+V(0,3,0)),C(def.color),SM,false))
	p:SetAttribute("MonsterId",monsterId)
	p:SetAttribute("Region",def.region)
	p:SetAttribute("Count",count or 2)
	p:SetAttribute("Radius",radius or 10)
	return p
end

-- Crafting stations: the server answers the prompt with a snapshot, and the
-- player attribute tells the client which crafting tab to open.
local STATION={Forge={"Smith","Smithing"},Hearth={"Cook","Cooking"},Cauldron={"Brew","Alchemy"},Workbench={"Craft","Carpentry"},Slayer={"Speak","Slayer contracts"}}
local function stationPrompt(target,kind,place)
	local spec=STATION[kind]
	local q=prompt(target,spec[1],kind.." · "..spec[2]..(if place then " · "..place else ""),"station",kind)
	q.Triggered:Connect(function(player)
		player:SetAttribute("IsleStation",kind)
		-- A visit counter lets the client reopen the same tab on a repeat visit.
		player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
	end)
	return q
end
local function facing(pos,toward)
	return CFrame.lookAt(pos,V(toward.X,pos.Y,toward.Z))
end
local function at(cf,x,y,z) return cf*CFrame.new(x,y,z) end
local function station(parent,kind,pos,toward,place)
	local m=group(kind,parent)
	local cf=facing(pos,toward)
	local target
	if kind=="Forge" then
		target=part(m,"Forge hearthstone",V(6,3,4),at(cf,0,1.5,0),C("6E4B3A"),Enum.Material.Brick,true)
		local coals=part(m,"Forge coals",V(4.6,.3,2.8),at(cf,0,3.15,0),C("FF8A3D"),NE,false)
		part(m,"Forge hood",V(5.2,1.1,3.6),at(cf,0,6.6,.3),rock,ST,false)
		part(m,"Chimney",V(1.7,6,1.7),at(cf,0,10.1,.6),darken(rock,.2),ST,false)
		for _,s in ipairs({-1,1}) do part(m,"Hood stay",V(.4,3.3,.4),at(cf,s*2.3,4.7,1.4),brass,MT,false) end
		part(m,"Anvil",V(1.8,.9,.9),at(cf,4.3,1.9,-1.2),ink,MT,false)
		part(m,"Anvil foot",V(.9,1.45,.7),at(cf,4.3,.72,-1.2),darken(rock,.3),MT,false)
		light(coals,C("FF9A52"),1.1,14)
	elseif kind=="Hearth" then
		target=disk(m,"Hearth ring",pos+V(0,.4,0),2.7,.8,rock,ST,true)
		local embers=disk(m,"Hearth embers",pos+V(0,.86,0),1.8,.12,C("FF8A3D"),NE,false)
		disk(m,"Stew pot",pos+V(0,2,0),1.15,1.4,ink,MT,false)
		disk(m,"Stew",pos+V(0,2.72,0),.95,.06,C("D9A15B"),SM,false)
		for _,s in ipairs({-1,1}) do part(m,"Spit post",V(.3,3.6,.3),at(cf,s*2.4,1.8,0),timber,WO,false) end
		part(m,"Spit bar",V(5,.25,.25),at(cf,0,3.5,0),brass,MT,false)
		part(m,"Prep table",V(3,1.2,1.6),at(cf,0,.6,-3.6),timber,WO,true)
		light(embers,C("FFB066"),.9,12)
	elseif kind=="Cauldron" then
		for i=1,3 do
			local a=i*2*math.pi/3
			block(m,"Cauldron leg",pos+V(math.cos(a)*1.4,.5,math.sin(a)*1.4),V(.4,1,.4),ink,MT,false)
		end
		target=ball(m,"Cauldron bowl",pos+V(0,2,0),4,darken(navy,.3),MT)
		target.CanCollide=true
		local brew=disk(m,"Bubbling brew",pos+V(0,3.55,0),1.55,.12,mint,NE,false)
		ball(m,"Brew bubble",pos+V(.6,3.75,.3),.5,lighten(mint,.3),NE)
		part(m,"Reagent shelf",V(4,.3,1.2),at(cf,0,2.6,3.2),timber,WO,false)
		for i,colr in ipairs({rose,brass,teal}) do
			disk(m,"Reagent bottle",at(cf,(i-2)*1.2,3.25,3.2).Position,.3,1,colr,GL,false)
		end
		light(brew,mint,.9,12)
	else
		target=part(m,"Workbench top",V(6,.45,3),at(cf,0,2.6,0),timber,WO,true)
		for _,x in ipairs({-2.6,2.6}) do for _,z in ipairs({-1.1,1.1}) do
			part(m,"Bench leg",V(.4,2.4,.4),at(cf,x,1.2,z),darken(timber,.3),WO,false)
		end end
		part(m,"Bench vice",V(.9,.8,.9),at(cf,-2.3,3.2,-.6),ink,MT,false)
		part(m,"Plank stack",V(4,.5,1.2),at(cf,.6,3.1,.4),lighten(timber,.2),WO,false)
		part(m,"Saw",V(1.8,.08,.6),at(cf,1.6,2.9,-.8),shale,MT,false)
		part(m,"Tool board",V(5,2.4,.25),at(cf,0,4.6,1.45),navy,WO,false)
	end
	stationPrompt(target,kind,place)
	return m
end

-- Gated transit: every beacon asks the server's authoritative region check.
local REGION_ACCENT={Windpine=C("9BD18B"),Gloomhollow=C("A58CE0"),Tidewater=C("5EC8D8"),Tempest=C("C6DCFF")}
local function requirementText(region)
	local req=region.requires or {}
	local out={}
	if req.quest then table.insert(out,req.quest.." GUILD CONTRACTS") end
	if req.skills then
		local names={}
		for skill in pairs(req.skills) do table.insert(names,skill) end
		table.sort(names)
		for _,skill in ipairs(names) do table.insert(out,string.upper(skill).." "..req.skills[skill]) end
	end
	return if #out>0 then "REQUIRES "..table.concat(out," · ") else "OPEN TO ALL WAYFARERS"
end
local function beaconProp(parent,pos,accent)
	block(parent,"Beacon plinth",pos+V(0,.4,0),V(3.4,.8,3.4),ink,ST,true)
	local post=block(parent,"Warp beacon",pos+V(0,2.8,0),V(1.6,4,1.6),accent,GL,false)
	for _,x in ipairs({-1.3,1.3}) do gem(parent,"Beacon fin",pos+V(x,2.6,0),V(.5,3.6,.5),brass,0) end
	local cap=part(parent,"Beacon flame",V(.9,.9,.9),CFrame.new(pos+V(0,5.3,0))*CFrame.Angles(math.pi/4,0,math.pi/4),accent,NE,false)
	light(cap,accent,.8,12)
	return post
end
local SKYWAY_LANDING=V(0,4,107)
-- Every gated warp (Skyreach charter beacon included) asks the authoritative
-- region check safely and tells the player why travel was refused.
regionTravel=function(player,post,regionId,destination)
	local region=Data.RegionById[regionId]
	local access=ServerStorage:FindFirstChild("IsleRegionAccess")
	if not region or not access then return end
	local ok,result=pcall(access.Invoke,access,player,regionId)
	if ok and type(result)=="table" and result.allowed then
		warp(player,post,destination)
	else
		local message=if ok and type(result)=="table" and type(result.message)=="string" then result.message else region.name..": "..requirementText(region)
		player:SetAttribute("IsleRegionNotice",message)
		-- The counter lets the client re-show a repeated identical notice.
		player:SetAttribute("IsleRegionNoticeCount",(tonumber(player:GetAttribute("IsleRegionNoticeCount")) or 0)+1)
	end
end
local function regionWarp(parent,pos,regionId,destination)
	local region=Data.RegionById[regionId]
	assert(region,"unknown region "..tostring(regionId))
	local post=beaconProp(parent,pos,REGION_ACCENT[regionId] or mint)
	local q=prompt(post,"Travel to "..region.name,requirementText(region))
	q:SetAttribute("IsleWarpRegion",regionId)
	q.Triggered:Connect(function(player) regionTravel(player,post,regionId,destination) end)
	return post
end
local function returnWarp(parent,pos,label)
	local post=beaconProp(parent,pos,mint)
	local q=prompt(post,"Return to the Skyway",label)
	q:SetAttribute("IsleWarpReturn","Hub")
	q.Triggered:Connect(function(player) warp(player,post,SKYWAY_LANDING) end)
	return post
end

-- Static ledger boards; rows are named so live data can be written later.
local function ledger(parent,name,pos,toward,title,kicker,rows,accent,width,height)
	local cf=facing(pos+V(0,height/2+1.6,0),toward)
	for _,s in ipairs({-1,1}) do part(parent,"Ledger post",V(.35,height+1.6,.35),cf*CFrame.new(s*(width/2+.1),-.8,0),brass,MT,false) end
	local board=part(parent,name,V(width,height,.35),cf,ink,SM,false)
	local canvasH=math.floor(600*height/width)
	local gui=Instance.new("SurfaceGui")
	gui.Face,gui.CanvasSize,gui.LightInfluence,gui.MaxDistance=Enum.NormalId.Front,Vector2.new(600,canvasH),0,70
	gui.Parent=board
	local function text(t,x,y,w,h,font,color,align,label)
		local l=Instance.new("TextLabel")
		l.Name=label or "Text"
		l.BackgroundTransparency,l.TextXAlignment=1,align or Enum.TextXAlignment.Left
		l.Position,l.Size=UDim2.fromOffset(x,y),UDim2.fromOffset(w,h)
		l.Font,l.TextColor3,l.Text,l.TextScaled=font,color,t,true
		l.Parent=gui
		return l
	end
	local bar=Instance.new("Frame")
	bar.BorderSizePixel,bar.BackgroundColor3=0,accent
	bar.Position,bar.Size=UDim2.fromOffset(18,16),UDim2.fromOffset(6,canvasH-32)
	bar.Parent=gui
	text(kicker,40,14,540,26,Enum.Font.GothamBold,accent)
	text(title,40,40,540,46,Enum.Font.GothamBold,cream)
	local rowH=math.min(30,math.floor((canvasH-104)/math.max(1,#rows)))
	for i,row in ipairs(rows) do
		local y=96+(i-1)*rowH
		text(row[1],40,y,300,rowH-4,Enum.Font.GothamMedium,cream,nil,"Row_"..row.key)
		text(row[2],330,y,240,rowH-4,Enum.Font.Gotham,lighten(accent,.3),Enum.TextXAlignment.Right,"Value_"..row.key)
	end
	return board
end

-------------------------------------------------------------------------------
-- Guild Terrace (Hub): crafting stations, the Guild Hall and the Skyway.
-------------------------------------------------------------------------------
local GT=V(0,0,98)
local terrace=regionIsle("Hub","Guild Terrace",GT,32,C("A7B08A"),nil,nil,brass,nil,{-math.pi/2})
bridge(terrace,V(0,0,40),V(0,0,69))
sign(hub,V(-8,0,35),"Guild Terrace","SOUTH   /   CRAFT · SLAYER · SKYWAY",brass,0,9)
disk(terrace,"Guild court",GT+V(0,.05,0),10,.15,navy,ST,true)
disk(terrace,"Guild seal",GT+V(0,.18,0),2.4,.3,brass,SM,false)
for i=1,6 do
	local a=i*math.pi/3
	local d=V(math.cos(a),0,math.sin(a))
	beam(terrace,"Seal inlay",GT+d*3+V(0,.18,0),GT+d*9+V(0,.18,0),.2,brass,SM)
end
sign(terrace,V(10,0,74),"Guild Terrace","COMPASS QUAY   /   GUILDS + SKYWAY",brass,0,11)
for i,deg in ipairs({230,205,180,155}) do
	local a=math.rad(deg)
	station(terrace,({"Forge","Hearth","Cauldron","Workbench"})[i],GT+V(math.cos(a)*21,0,math.sin(a)*21),GT,"Guild Terrace")
end
sign(terrace,V(-14,0,75),"Artisans' Row","SMITH · COOK · BREW · CRAFT",rose,0,8)
-- Guild Hall pavilion (east side).
local hall=group("Guild Hall",terrace)
block(hall,"Hall floor",V(19,.25,98),V(13,.5,24),darken(navy,.1),WO,true)
for _,x in ipairs({13,25}) do for _,z in ipairs({87,109}) do
	block(hall,"Hall column",V(x,6,z),V(1.3,12,1.3),cream,ST,false)
	block(hall,"Column capital",V(x,12.2,z),V(2,.6,2),brass,MT,false)
end end
part(hall,"Hall roof",V(8,.6,26),CFrame.new(V(15.6,14,98))*CFrame.Angles(0,0,math.rad(20)),navy,SM,false)
part(hall,"Hall roof",V(8,.6,26),CFrame.new(V(22.4,14,98))*CFrame.Angles(0,0,math.rad(-20)),navy,SM,false)
block(hall,"Ridge beam",V(19,15.4,98),V(.8,.8,26),brass,MT,false)
local skillRows={}
for _,skill in ipairs(Data.SkillOrder) do table.insert(skillRows,{skill,"Unclaimed  ·  Lv 99",key=skill}) end
ledger(hall,"Skill Leaderboard",V(23,.5,91.5),GT,"Hall of Mastery","GUILD LEDGER   /   FIRST TO LEVEL 99",skillRows,brass,9,8.5)
local monsterIds={}
for id in pairs(Data.Monsters) do table.insert(monsterIds,id) end
table.sort(monsterIds,function(x,y)
	local a,b=Data.Monsters[x],Data.Monsters[y]
	return if a.level==b.level then x<y else a.level<b.level
end)
local beastRows={}
for _,id in ipairs(monsterIds) do
	local m=Data.Monsters[id]
	local where=Data.RegionById[m.region]
	table.insert(beastRows,{"Lv "..m.level.."  "..m.name,where and where.name or m.region,key=id})
end
ledger(hall,"Bestiary",V(23,.5,104.5),GT,"Bestiary","KNOWN CREATURES   /   BY LEVEL",beastRows,rose,9,8.5)
-- Slayer master: a sentinel statue that takes contracts for the three hunts.
local pedestal=block(hall,"Slayer master pedestal",V(16,1.5,98),V(4,2.5,4),rock,ST,true)
block(hall,"Pedestal trim",V(16,2.85,98),V(4.4,.3,4.4),brass,MT,false)
local master=sculpture(hall,"Huntmaster Oriel",V(16,6,98),"ObservatorySentinel",1.5,-90)
light(master,C("FFD9A0"),.6,10)
stationPrompt(pedestal,"Slayer","Huntmaster Oriel")
for i,line in ipairs(Data.SlayerOrder) do
	local def=Data.Slayers[line]
	-- Pennants on the ridge give the hall a silhouette from across the quay.
	local z=90+(i-1)*8
	block(hall,"Pennant pole",V(19,17.4,z),V(.25,3.6,.25),brass,MT,false)
	block(hall,def.name.." pennant",V(19,18.3,z+1.3),V(.15,1.6,2.4),C(def.color),Enum.Material.Fabric,false)
end
sign(hall,V(10,0,91),"Huntmaster Oriel","SLAYER   /   BRAMBLE · GLOOM · TEMPEST",rose,90,8)
-- The Skyway: gated beacons to the four depth regions (built below).
block(terrace,"Skyway dais",V(0,.15,117),V(36,.3,7),navy,ST,true)
for _,p in ipairs({V(-8,0,82),V(8,0,82),V(-11,0,108),V(-2,0,110)}) do lamp(terrace,p) end

-------------------------------------------------------------------------------
-- Meadow Reach (Meadow): open hills south of Mosswake Grove.
-------------------------------------------------------------------------------
local MR=V(-97,0,102)
local meadow=regionIsle("Meadow","Meadow Reach",MR,30,C("8DB86E"),nil,nil,nil,nil,{-math.pi/2})
bridge(meadow,V(-97,0,27),V(-97,0,75))
for _,h in ipairs({{V(-80,-7.6,88),18},{V(-116,-7.2,113),17}}) do
	part(meadow,"Grassy hillock",V(h[2],h[2],h[2]),CFrame.new(h[1]),C("86AE69"),Enum.Material.Grass,true,BALL)
end
sign(meadow,V(-86,0,80),"Meadow Reach","MEADOW   /   BOARS · SUNWHEAT · GLASSFIN",mint,0,11)
cropPatch(meadow,V(-110,0,90),"Sunwheat")
cropPatch(meadow,V(-110,0,98),"Sunwheat")
cropPatch(meadow,V(-118,0,94),"Herb")
treeNode(meadow,V(-78,0,114),"Timber")
fishSpot(meadow,V(-90,0,100),"Fish",nil,V(1,0,.4),5,6)
fishSpot(meadow,V(-93,0,95),"Glassfin",nil,V(-.6,0,-1),5)
for _,p in ipairs({V(-104,0,79),V(-84,0,122)}) do lamp(meadow,p) end
for i=1,5 do
	local a=1.75+i*.3
	local p=MR+V(math.cos(a)*25,1,math.sin(a)*25)
	part(meadow,"Fence rail",V(.3,.3,7.6),CFrame.lookAt(p,p+V(-math.sin(a),0,math.cos(a))),timber,WO,false)
	block(meadow,"Fence post",p-V(0,.4,0),V(.4,2,.4),darken(timber,.3),WO,false)
end
spawnMarker("BramblebackBoar",V(-98,0,117),3,9)
spawnMarker("Thornling",V(-101,0,84),3,7)

-------------------------------------------------------------------------------
-- Cinder Shelf (Quarry): a lower terrace below Brassfall Quarry.
-------------------------------------------------------------------------------
local CS=V(98,-4,-82)
local shelf=regionIsle("Quarry","Cinder Shelf",CS,24,C("8F8676"),darken(rock,.15),nil,C("FF9A52"),GR,{math.pi/2})
bridge(shelf,V(98,0,-28),V(98,-4,-61))
for i=1,4 do
	local a=i*1.6
	local p=CS+V(math.cos(a)*12,.06,math.sin(a)*12)
	local vent=part(shelf,"Cinder vent",V(.5,.12,5),CFrame.new(p)*CFrame.Angles(0,a,0),C("FF7A3D"),NE,false)
	if i==2 then light(vent,C("FF8A3D"),.8,14) motes(vent,C("FFB066"),4,2,.25) end
end
sign(shelf,V(89,-4,-64),"Cinder Shelf","QUARRY   /   BRASSITE · CRAWLERS",brass,0,10)
oreNode(shelf,V(86,-4,-90),"Brassite")
oreNode(shelf,V(110,-4,-88),"Brassite")
oreNode(shelf,V(111,-4,-74),"Ore")
spawnMarker("ShaleCrawler",V(91,-4,-77),3,7)
spawnMarker("CinderMite",V(102,-4,-90),3,6)
-- Brassfall Quarry gains a second copper seam by the old crane.
oreNode(mine,V(84,0,-20),"Ore")
-- Skyreach: a sunsteel outcrop and the summit's guardians.
oreNode(skyreach,V(214,36,64),"SunsteelOre","Skyreach")
-- Markers keep >= 40 studs (flat) from every warp landing; see verify-world.
spawnMarker("BrassGolem",V(228,36,60),2,6)
spawnMarker("StormHarrier",V(226,36,40),2,6)

-------------------------------------------------------------------------------
-- Windpine Grove: towering pines, an emberoak hollow and the Aetherheart.
-------------------------------------------------------------------------------
local WP=V(-270,18,-60)
local grovewild=regionIsle("Windpine","Windpine Grove",WP,36,C("5F8A57"),C("3F4B44"),C("5E6B5C"),C("9BD18B"))
for _,deg in ipairs({150,200,228,270,335,20}) do
	local a=math.rad(deg)
	pagodaPine(grovewild,WP+V(math.cos(a)*30,0,math.sin(a)*30),C("4E7A4A"),1.7+(deg%3)*.15)
end
treeNode(grovewild,WP+V(0,0,-6),"AetherheartLog","Windpine")
treeNode(grovewild,WP+V(-21,0,-13),"WindpineLog","Windpine")
treeNode(grovewild,WP+V(-9,0,-25),"WindpineLog","Windpine")
treeNode(grovewild,WP+V(-25,0,2),"WindpineLog","Windpine")
treeNode(grovewild,WP+V(16,0,-18),"EmberoakLog","Windpine")
treeNode(grovewild,WP+V(25,0,-6),"EmberoakLog","Windpine")
local emberGlow=hidden(grovewild,"Ember hollow glow",WP+V(20,4,-12))
emberGlow.CanQuery,emberGlow.CastShadow=false,false
motes(emberGlow,C("FFB25C"),5,1.5,.2)
cropPatch(grovewild,WP+V(-14,0,23),"Glowcap","Windpine")
for _,b in ipairs({{V(-6,0,8),3},{V(10,0,8),2.4},{V(-28,0,-20),2.8}}) do
	part(grovewild,"Mossy boulder",V(b[2]*1.4,b[2],b[2]*1.2),CFrame.new(WP+b[1]+V(0,b[2]*.35,0))*CFrame.Angles(0,b[2],.1),C("6E7B68"),ST,false)
end
part(grovewild,"Fallen windpine",V(12,1.6,1.6),CFrame.new(WP+V(2,.8,15))*CFrame.Angles(0,.6,0),darken(timber,.3),WO,false).Shape=Enum.PartType.Cylinder
-- Woodcutters' lodge sheltering a workbench.
local lodge=group("Woodcutters' Lodge",grovewild)
local LP=WP+V(18,0,17)
block(lodge,"Lodge floor",LP+V(0,.2,0),V(11,.4,8),timber,WO,true)
block(lodge,"Lodge back wall",LP+V(0,3.5,3.8),V(11,6.6,.5),darken(timber,.2),WO,true)
for _,x in ipairs({-5.3,5.3}) do block(lodge,"Lodge post",LP+V(x,3.3,-3.6),V(.6,6.2,.6),darken(timber,.35),WO,false) end
part(lodge,"Lodge roof",V(12.5,.5,9.4),CFrame.new(LP+V(0,7.2,0))*CFrame.Angles(math.rad(-14),0,0),C("4E6B47"),WO,false)
station(lodge,"Workbench",LP+V(0,.4,0),LP+V(0,0,-10),"Windpine Lodge")
sign(grovewild,WP+V(-8,0,30),"Windpine Grove",requirementText(Data.RegionById.Windpine),REGION_ACCENT.Windpine,0,10)
returnWarp(grovewild,WP+V(5,0,31),"Windpine Grove")
spawnMarker("BarkStalker",WP+V(-15,0,-17),3,8)
spawnMarker("GaleSprite",WP+V(9,0,-24),3,7)

-------------------------------------------------------------------------------
-- Gloomhollow Caverns: a roofed grotto lit only by voidstone and moonbloom.
-------------------------------------------------------------------------------
local GH=V(200,-14,-210)
local void=C("7B5CC4")
local gloom=regionIsle("Gloomhollow","Gloomhollow Caverns",GH,38,C("3A3F52"),C("2B2F3D"),C("424659"),void,ST)
local CAVE_R,CAVE_H=27,22
local cave=group("Grotto",gloom)
local segments=16
for i=0,segments-1 do
	local a=(i+.5)*2*math.pi/segments
	if math.abs(math.atan2(math.sin(a-math.pi/2),math.cos(a-math.pi/2)))>math.rad(25) then
		local radial=V(math.cos(a),0,math.sin(a))
		local h=CAVE_H+(i%3)*1.5
		local p=GH+radial*CAVE_R+V(0,h/2,0)
		part(cave,"Cavern wall",V(2*CAVE_R*math.sin(math.pi/segments)+1,h,3.4),CFrame.lookAt(p,p+radial),i%2==0 and C("2F3342") or C("383D4E"),ST,true)
	end
end
disk(cave,"Cavern roof",GH+V(0,CAVE_H+1.6,0),CAVE_R+2.4,3.2,C("2B2F3D"),ST,true)
for i=1,7 do
	local a=i*.9
	local p=GH+V(math.cos(a)*(8+i*2.2),CAVE_H+4+i%3*2,math.sin(a)*(8+i*2.2))
	part(cave,"Roof crag",V(5+i%3,7+i%4*2.5,5),CFrame.new(p)*CFrame.Angles(.25*(i%2*2-1),a,.2),i%2==0 and C("2F3342") or C("424659"),ST,false)
end
for i=1,4 do
	local a=i*1.57+.5
	part(cave,"Stalactite",V(1.4,5,1.4),CFrame.new(GH+V(math.cos(a)*14,CAVE_H-2.5,math.sin(a)*14)),C("424659"),ST,false)
	if i%2==0 then ball(cave,"Stalactite glow",GH+V(math.cos(a)*14,CAVE_H-5.2,math.sin(a)*14),.9,void,NE) end
end
local heartCrystal=gem(cave,"Grotto heart crystal",GH+V(0,4,-6),V(3,8,3),void,.3)
heartCrystal.Material=NE
light(heartCrystal,void,1.4,26)
gem(cave,"Grotto heart shard",GH+V(2,2.5,-4.5),V(1.6,4.5,1.6),lighten(void,.3),1.2)
motes(heartCrystal,lighten(void,.3),4,.8,.3)
oreNode(cave,GH+V(-15,0,-12),"Voidstone","Gloomhollow")
oreNode(cave,GH+V(13,0,-15),"Voidstone","Gloomhollow")
oreNode(cave,GH+V(0,0,-21),"Voidstone","Gloomhollow")
oreNode(cave,GH+V(19,0,1),"Prismite","Gloomhollow",1.2)
fishSpot(cave,GH+V(-15,0,9),"AbyssKoi","Gloomhollow",V(1,0,.3),4,5.5)
cropPatch(cave,GH+V(13,0,13),"Moonbloom","Gloomhollow")
spawnMarker("GloomfangSpider",GH+V(-8,0,-14),3,7)
spawnMarker("VoidWisp",GH+V(10,0,-12),2,7)
oreNode(gloom,GH+V(-22,0,24),"SunsteelOre","Gloomhollow")
station(gloom,"Forge",GH+V(15,0,31),GH,"Delvers' Forge")
sign(gloom,GH+V(-9,0,33),"Gloomhollow Caverns",requirementText(Data.RegionById.Gloomhollow),REGION_ACCENT.Gloomhollow,0,9)
returnWarp(gloom,GH+V(3,0,34),"Gloomhollow Caverns")
for _,x in ipairs({-8,8}) do
	block(gloom,"Cave torch",GH+V(x,1.8,27.5),V(.5,3.6,.5),timber,WO,false)
	light(ball(gloom,"Torch flame",GH+V(x,3.9,27.5),.7,C("B59CFF"),NE),C("B59CFF"),.8,12)
end

-------------------------------------------------------------------------------
-- Tidewater Shoals: sandbars, two lagoons, piers and a lighthouse.
-------------------------------------------------------------------------------
local TW=V(-250,2,210)
local tide=regionIsle("Tidewater","Tidewater Shoals",TW,40,C("D9C9A0"),C("6F7C86"),C("8D99A2"),C("5EC8D8"),SA)
for _,l in ipairs({{V(-12,0,-6),11},{V(14,0,10),9}}) do
	local w=disk(tide,"Lagoon",TW+l[1]+V(0,.06,0),l[2],.22,C("4FB3BF"),GL,false)
	w.Transparency=.05
	disk(tide,"Lagoon deep",TW+l[1]+V(0,.1,0),l[2]*.55,.2,C("2E7F95"),GL,false)
end
fishSpot(tide,TW+V(-12,0,-9),"Stormeel","Tidewater",V(0,0,-1),9)
fishSpot(tide,TW+V(-17,0,-4),"Lanternray","Tidewater",V(-1,0,0),8)
fishSpot(tide,TW+V(16,0,10),"LeviathanScale","Tidewater",V(1,0,0),9)
fishSpot(tide,TW+V(13,0,15),"Stormeel","Tidewater",V(0,0,1),8)
treeNode(tide,TW+V(-21,0,8),"GlimmerbarkLog","Tidewater")
treeNode(tide,TW+V(1,0,-16),"GlimmerbarkLog","Tidewater")
cropPatch(tide,TW+V(29,0,-4),"AetherLotus","Tidewater")
local galley=group("Shoals Galley",tide)
block(galley,"Galley boardwalk",TW+V(20,.2,-20),V(12,.4,9),timber,WO,true)
for _,x in ipairs({-5.5,5.5}) do for _,z in ipairs({-4,4}) do
	block(galley,"Boardwalk piling",TW+V(20+x,.9,-20+z),V(.6,1.8,.6),darken(timber,.4),WO,false)
end end
station(galley,"Hearth",TW+V(20,.4,-20),TW,"Shoals Galley")
local LH=TW+V(-27,0,22)
local tower=group("Shoals lighthouse",tide)
disk(tower,"Lighthouse footing",LH+V(0,1,0),3.4,2,rock,ST,true)
disk(tower,"Lighthouse tower",LH+V(0,10,0),2.1,16,cream,SM,true)
for _,y in ipairs({6,12}) do disk(tower,"Tower stripe",LH+V(0,y,0),2.15,1.6,rose,SM,false) end
local lantern=disk(tower,"Lantern room",LH+V(0,19.3,0),2.4,2.6,mint,GL,false)
ball(tower,"Lighthouse flame",LH+V(0,19.3,0),1.4,C("FFF1B8"),NE)
disk(tower,"Lantern cap",LH+V(0,21,0),2.7,.7,brass,MT,false)
light(lantern,C("FFF1B8"),1.4,40)
for _,r in ipairs({{V(31,0,14),2.6},{V(-2,0,31),2},{V(-32,0,-10),2.4}}) do
	part(tide,"Reef rock",V(r[2]*1.5,r[2],r[2]*1.2),CFrame.new(TW+r[1]+V(0,r[2]*.3,0))*CFrame.Angles(0,r[2],.12),C("7D8B92"),ST,false)
end
local spray=hidden(tide,"Lagoon spray",TW+V(14,1,10))
spray.CanQuery,spray.CastShadow=false,false
motes(spray,C("CFEFFF"),3,1,.18)
sign(tide,TW+V(-9,0,-34),"Tidewater Shoals",requirementText(Data.RegionById.Tidewater),REGION_ACCENT.Tidewater,0,10)
returnWarp(tide,TW+V(4,0,-35),"Tidewater Shoals")
spawnMarker("ReefLurker",TW+V(-4,0,25),3,9)
spawnMarker("ReefLurker",TW+V(24,0,22),2,5)

-------------------------------------------------------------------------------
-- Tempest Spire: a storm-wracked summit ringed by arcing crystal pylons.
-------------------------------------------------------------------------------
local TS=V(300,70,-120)
local storm=C("BFD7FF")
local tempest=regionIsle("Tempest","Tempest Spire",TS,30,C("4A5266"),C("2E3445"),C("3B4256"),storm,ST)
local spire=group("Storm spire",tempest)
local SP=TS+V(-5,0,-21)
local spireTiers={{V(9,12,8),6,.1},{V(7,12,6.5),17,-.15},{V(5.2,11,5),28,.2},{V(3.8,10,3.6),38,-.1},{V(2.4,9,2.4),47,.18}}
for i,t in ipairs(spireTiers) do
	part(spire,"Spire stone",t[1],CFrame.new(SP+V(i%2*.6,t[2],0))*CFrame.Angles(t[3]*.4,i*.5,t[3]),i%2==0 and C("2E3445") or C("3B4256"),ST,true)
end
local crown=gem(spire,"Storm crown",SP+V(0,54.5,0),V(2,6,2),storm,.4)
crown.Material=NE
light(crown,storm,1.6,40)
motes(crown,storm,6,4,.3)
local arcAnchors={}
for i=1,4 do
	local a=math.rad(45+90*(i-1))
	local p=TS+V(math.cos(a)*17,0,math.sin(a)*17)
	block(tempest,"Pylon footing",p+V(0,.5,0),V(3,1,3),ink,ST,true)
	block(tempest,"Pylon shaft",p+V(0,4.5,0),V(1.2,7,1.2),C("3B4256"),MT,true)
	for _,s in ipairs({-1,1}) do gem(tempest,"Pylon brace",p+V(s*.9,3,0),V(.4,4,.4),brass,0) end
	local top=gem(tempest,"Pylon crystal",p+V(0,9.4,0),V(1.6,3.6,1.6),storm,a)
	top.Material=NE
	light(top,storm,.9,16)
	local att=Instance.new("Attachment")
	att.Name="Arc anchor"
	att.CFrame=CFrame.new(0,.8,0)
	att.Parent=top
	arcAnchors[i]=att
end
for i=1,4 do
	local arc=Instance.new("Beam")
	arc.Name="Crystal arc"
	arc.Attachment0,arc.Attachment1=arcAnchors[i],arcAnchors[i%4+1]
	arc.Color=ColorSequence.new(C("E8F2FF"),C("7B8CDE"))
	arc.Width0,arc.Width1,arc.LightEmission,arc.FaceCamera,arc.Segments=.35,.35,1,true,16
	arc.CurveSize0,arc.CurveSize1=7,-7
	arc.Parent=arcAnchors[i].Parent
end
for i=1,6 do
	local a=i*1.05
	local cloud=ball(tempest,"Storm cloud",TS+V(math.cos(a)*24,34+(i%3)*5,math.sin(a)*24),16+(i%3)*5,C("596274"),SM)
	cloud.Transparency=.3
end
oreNode(tempest,TS+V(-24,0,-6),"StarmetalOre","Tempest")
oreNode(tempest,TS+V(24,0,-4),"StarmetalOre","Tempest")
oreNode(tempest,SP+V(12,0,-1),"Celestium","Tempest",1.25)
treeNode(tempest,TS+V(-22,0,10),"StarwoodLog","Tempest")
cropPatch(tempest,TS+V(19,0,14),"Starfruit","Tempest")
sign(tempest,TS+V(-8,0,25),"Tempest Spire",requirementText(Data.RegionById.Tempest),REGION_ACCENT.Tempest,0,10)
returnWarp(tempest,TS+V(5,0,25),"Tempest Spire")
spawnMarker("TempestWraith",TS+V(15,0,-17),2,6)
spawnMarker("StarbornSentinel",TS+V(-16,0,-16),1,5)

-- Skyway beacons on the Guild Terrace, plus a deep descent from Cinder Shelf.
local destinations={
	Windpine=WP+V(0,4,23),Gloomhollow=GH+V(0,4,29),Tidewater=TW+V(0,4,-28),Tempest=TS+V(0,4,22),
}
for i,id in ipairs({"Windpine","Gloomhollow","Tidewater","Tempest"}) do
	local x=-13.5+(i-1)*9
	regionWarp(terrace,V(x,.3,116),id,destinations[id])
	sign(terrace,V(x,0,120.5),Data.RegionById[id].name,requirementText(Data.RegionById[id]),REGION_ACCENT[id],0,8)
end
regionWarp(shelf,CS+V(0,0,-18),"Gloomhollow",destinations.Gloomhollow)
sign(shelf,CS+V(9,0,-17),"Deep descent","GLOOMHOLLOW   /   "..requirementText(Data.RegionById.Gloomhollow),REGION_ACCENT.Gloomhollow,0,9)
