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

local function island(name,pos,r,top)
	local m = group(name)
	disk(m,"Floating foundation",pos-V(0,2.9,0),r,5.8,rock,ST,true)
	disk(m,"Mineral stratum",pos-V(0,6,0),r*.85,2.7,shale,ST,false)
	disk(m,"Lower basalt",pos-V(0,8.8,0),r*.63,4.5,rock,ST,false)
	disk(m,"Meadow",pos-V(0,.25,0),r+.1,.5,top or turf,Enum.Material.Grass,true)
	local count = r>=30 and 12 or 7
	for i=1,count do
		local a=i*2*math.pi/count
		local radial=V(math.cos(a),0,math.sin(a))
		local offset=pos+radial*(r*.86)-V(0,5+i%3,0)
		part(m,"Fractured cliff",V(r*.24,6+i%4,r*.28),CFrame.new(offset)*CFrame.Angles(.12,a,.18),i%2==0 and rock or shale,ST,false)
		if i%3==0 then gem(m,"Aether vein",offset-V(0,4,0),V(1.3,5.4,1.3),mint,a) end
	end
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
	if root and hum and hum.Health>0 and (trigger.Position-root.Position).Magnitude<=12 then
		character:PivotTo(CFrame.new(destination))
		root.AssemblyLinearVelocity=Vector3.zero
	end
end
local skyreach = island("Skyreach", V(208,36,52), 23, C("96ACAB"))
local launch = sculpture(mine,"Charter beacon",V(123,2,0),"Lantern",1.2)
sign(mine,V(119,0,-4),"Skyreach passage","GUILD CHARTER REQUIRED",brass,0,9)
prompt(launch,"Ascend to Skyreach","Guild charter required").Triggered:Connect(function(player)
	local access = game:GetService("ServerStorage"):FindFirstChild("IsleRegionAccess")
	if access and access:Invoke(player,"Skyreach").allowed then
		warp(player,launch,V(199,40,52))
	end
end)
local descent = sculpture(skyreach,"Quarry beacon",V(193,38,52),"Lantern",1.1)
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
