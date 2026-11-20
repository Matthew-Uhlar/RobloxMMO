-- Aether Isles archipelago. Gameplay is attached to prompts by the server.
-- Wave 4: islands are 2-3x larger with tiers, cliffs, paths, ponds and flora;
-- every island is a Model under Workspace.Islands (IslandCenter / IslandRadius /
-- Region attributes + Anchor_<Purpose> parts, docs/DEPTH-CONTRACT.md section 10);
-- props that should become custom meshes carry Shape / Tint / ShapeScale.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Tags = game:GetService("CollectionService")
local world = Instance.new("Folder")
world.Name = "AetherIsles"
world.Parent = workspace
local islandsFolder = Instance.new("Folder")
islandsFolder.Name = "Islands"
islandsFolder.Parent = workspace
local V = Vector3.new
local C = Color3.fromHex
local ink, navy, brass, cream = C("192D3B"), C("294853"), C("DBAD65"), C("F9EDCD")
local teal, mint, rose = C("3C9291"), C("8EE6CB"), C("D67D6A")
local rock, shale, turf, timber = C("485565"), C("687481"), C("80A67C"), C("966B4C")
local SM, WO, ST, NE = Enum.Material.SmoothPlastic, Enum.Material.WoodPlanks, Enum.Material.Slate, Enum.Material.Neon
local GL,MT,SA,GR,LEAF=Enum.Material.Glass,Enum.Material.Metal,Enum.Material.Sand,Enum.Material.Ground,Enum.Material.LeafyGrass
local BALL=Enum.PartType.Ball
local warm=C("FFD9A0")

-------------------------------------------------------------------------------
-- Lighting. Technology = Future is set in default.project.json (not scriptable);
-- the same look is applied here so a place opened without the project matches.
-- Bugs fixed (wave 4): over-bright OutdoorAmbient/Ambient flattened every
-- island and lit caves; stacked post effects if the place already had some;
-- 0.19 density haze with a near-white colour washed distant islands out.
-------------------------------------------------------------------------------
local LOOK = {
	Brightness=2.6, ClockTime=14.5, GeographicLatitude=38,
	Ambient=C("3A4150"), OutdoorAmbient=C("7D8A9C"),
	EnvironmentDiffuseScale=.5, EnvironmentSpecularScale=.3,
	ExposureCompensation=0, ShadowSoftness=.3, GlobalShadows=true,
}
for key,value in pairs(LOOK) do Lighting[key]=value end
for _,child in ipairs(Lighting:GetChildren()) do
	if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then child:Destroy() end
end
local grade=Instance.new("ColorCorrectionEffect")
grade.Name,grade.Brightness,grade.Contrast,grade.Saturation="Aether grade",0,.1,.08
grade.TintColor=C("FFF6EA")
grade.Parent=Lighting
local bloom=Instance.new("BloomEffect")
bloom.Name,bloom.Intensity,bloom.Size,bloom.Threshold="Aether bloom",.3,20,1.5
bloom.Parent=Lighting
local rays=Instance.new("SunRaysEffect")
rays.Name,rays.Intensity,rays.Spread="Aether sun rays",.045,.45
rays.Parent=Lighting
local air = Instance.new("Atmosphere")
air.Name="Aether air"
air.Density,air.Offset,air.Color,air.Decay,air.Glare,air.Haze=.24,.1,C("C9D8E6"),C("7186A6"),.3,.7
air.Parent = Lighting
local sky=Instance.new("Sky")
sky.Name,sky.StarCount,sky.SunAngularSize,sky.MoonAngularSize="Aether sky",2600,12,9
sky.Parent=Lighting

-- Slow day/night: one server loop, one update every 2 s. Lamps (night lights)
-- switch on at dusk; hero lights stay on. Daylight 15 min, night 5 min.
local DAY_SECONDS,NIGHT_SECONDS=900,300
local NIGHT_OUTDOOR,NIGHT_AIR=C("3E4A66"),C("4A5878")
local nightLights={}
local nightOn=false
local function isNight(clock) return clock<6.2 or clock>17.8 end
local function applyClock(clock)
	Lighting.ClockTime=clock
	local sun=math.clamp(math.min(clock-5.5,18.5-clock)/1.5,0,1)
	Lighting.OutdoorAmbient=NIGHT_OUTDOOR:Lerp(LOOK.OutdoorAmbient,sun)
	air.Color=NIGHT_AIR:Lerp(C("C9D8E6"),sun)
	local night=isNight(clock)
	if night~=nightOn then
		nightOn=night
		-- Lamps of departed homes drop out here, so the list never leaks.
		local kept={}
		for _,l in ipairs(nightLights) do
			if l.Parent then
				l.Enabled=night
				table.insert(kept,l)
			end
		end
		nightLights=kept
	end
end
local function advanceClock(clock,dt)
	local rate=if clock>=6 and clock<18 then 12/DAY_SECONDS else 12/NIGHT_SECONDS
	return (clock+dt*rate)%24
end
if task.wait then
	task.spawn(function()
		local clock=LOOK.ClockTime
		while true do
			local dt=task.wait(2)
			clock=advanceClock(clock,tonumber(dt) or 2)
			applyClock(clock)
		end
	end)
end

-------------------------------------------------------------------------------
-- Primitive helpers.
-------------------------------------------------------------------------------
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
	return part(parent,name,size,CFrame.new(pos)*CFrame.Angles(0,angle or 0,math.rad(26)),color,GL,false)
end
local function beam(parent,name,a,b,width,color,mat)
	return part(parent,name,V(width,width,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),color,mat,false)
end
local function ball(parent,name,pos,d,color,mat)
	return part(parent,name,V(d,d,d),CFrame.new(pos),color,mat,false,BALL)
end
local function lighten(c,f) return c:Lerp(cream,f) end
local function darken(c,f) return c:Lerp(ink,f) end
local function ghost(p)
	p.Transparency,p.CastShadow=1,false
	if not p.CanCollide then p.CanQuery=false end
	return p
end
local GATHER_HOLD,FISH_HOLD,INTERACT_HOLD=1,1.5,.36
local function prompt(p, verb, item, action, id, owner)
	local q = Instance.new("ProximityPrompt")
	-- Gather holds long enough for the swing gesture to read (Animation team);
	-- fishing (cast, bob, reel) is set to FISH_HOLD by its spot; interacts stay snappy.
	q.ActionText, q.ObjectText, q.HoldDuration = verb,item,if action=="gather" then GATHER_HOLD else INTERACT_HOLD
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
-- Mesh slot (contract section 10): the Mesh team renders `Shape` as a custom
-- mesh and keeps this primitive as the collider/fallback. ShapeOwnsModel marks
-- a part whose mesh stands for every other part of its Model (except parts that
-- carry their own Shape), so the fallback siblings can be hidden together.
local function meshSlot(p,shape,tint,scale,ownsModel)
	p:SetAttribute("Shape",shape)
	if tint then p:SetAttribute("Tint",tint) end
	p:SetAttribute("ShapeScale",scale or 1)
	if ownsModel then p:SetAttribute("ShapeOwnsModel",true) end
	return p
end
local function worldHalfY(p)
	local cf,s=p.CFrame,p.Size/2
	return math.abs(cf.RightVector.Y)*s.X+math.abs(cf.UpVector.Y)*s.Y+math.abs(cf.LookVector.Y)*s.Z
end
-- Lights. A PointLight inside an opaque part lights the ground in a hard disc
-- but never its own glowing prop (inside faces), so point lights hang on an
-- Attachment just above the host. Shadows only on a handful of hero lights;
-- lamps are night lights; per-area counts are capped by verify-world.
local function light(parent,color,brightness,range,opts)
	opts=opts or {}
	local kind=opts.kind or "PointLight"
	local host=parent
	if kind=="PointLight" and parent:IsA("BasePart") and opts.lift~=0 then
		local att=Instance.new("Attachment")
		att.Name="Light anchor"
		local lift=opts.lift or (worldHalfY(parent)+.6)
		att.CFrame=parent.CFrame:ToObjectSpace(CFrame.new(parent.CFrame.Position+V(0,lift,0)))
		att.Parent=parent
		host=att
	end
	local l=Instance.new(kind)
	l.Color,l.Brightness,l.Range=color,brightness,range
	l.Shadows=opts.shadows==true
	if opts.face then l.Face=opts.face end
	if opts.angle then l.Angle=opts.angle end
	if opts.night then
		l.Enabled=nightOn
		table.insert(nightLights,l)
	end
	l.Parent=host
	return l
end
local function motes(parent,color,rate,speed,size)
	local e=Instance.new("ParticleEmitter")
	e.Name="Ambient motes"
	e.Rate,e.LightEmission=rate,.6
	e.Lifetime,e.Speed=NumberRange.new(3,6),NumberRange.new(speed*.5,speed)
	e.SpreadAngle=Vector2.new(180,180)
	e.Size=NumberSequence.new(size)
	e.Color=ColorSequence.new(color)
	e.Parent=parent
	return e
end
local function hash(i,k) return (math.sin(i*12.9898+k*78.233)*43758.5453)%1 end
local function facing(pos,toward)
	return CFrame.lookAt(pos,V(toward.X,pos.Y,toward.Z))
end
local function at(cf,x,y,z) return cf*CFrame.new(x,y,z) end

-- Island anchors (contract section 10): invisible, non-colliding points at
-- ground level; the LookVector faces the thing the anchor serves.
local function islandModel(inst)
	local node=inst
	while node and node.Parent~=islandsFolder and node.Parent~=world do node=node.Parent end
	return node or inst
end
local function anchor(parent,purpose,where,toward)
	local host=islandModel(parent)
	local cf=if typeof(where)=="CFrame" then where elseif toward then facing(where,toward) else CFrame.new(where)
	local a=part(host,"Anchor_"..purpose,V(1,1,1),cf,mint,SM,false)
	a.Transparency,a.CastShadow,a.CanQuery=1,false,false
	a:SetAttribute("AnchorPurpose",purpose)
	Tags:AddTag(a,"IslandAnchor")
	return a
end

-- Signs: each is its own Model (board + posts); the board carries the mesh
-- slot and the SurfaceGui text.
local function signAt(parent,cf,title,kicker,accent,width)
	width = width or 12
	local holder=group("Sign "..title,parent)
	for _, s in ipairs({-1,1}) do
		part(holder,"Brass-capped post",V(.28,5,.32),cf*CFrame.new(s*(width/2-.7),2.5,0),brass,MT,false)
	end
	local board = part(holder,title,V(width,3.1,.32),cf*CFrame.new(0,4,0),ink,SM,false)
	meshSlot(board,"Signboard",accent,width/12,true)
	for _, face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back}) do
		local gui = Instance.new("SurfaceGui")
		gui.Face,gui.CanvasSize,gui.LightInfluence,gui.MaxDistance = face,Vector2.new(640,170),0,110
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
	return board
end
local function sign(parent,pos,title,kicker,accent,yaw,width)
	return signAt(parent,CFrame.new(pos)*CFrame.Angles(0,math.rad(yaw or 0),0),title,kicker,accent,width)
end

-------------------------------------------------------------------------------
-- Terrain kit.
-------------------------------------------------------------------------------
-- Invisible edge guard ring hugging the rim; openings exactly as wide as the
-- bridge decks they serve (bridge guards continue the wall along the deck).
local GAP_HALF=4.3
local function rim(parent,pos,r,gaps,height)
	height=height or 12
	local rr=r-.4
	local half=math.asin(math.min(1,GAP_HALF/rr))
	local cuts={}
	for _,g in ipairs(gaps or {}) do table.insert(cuts,g%(2*math.pi)) end
	table.sort(cuts)
	local spans={}
	if #cuts==0 then
		spans={{0,2*math.pi}}
	else
		for i,g in ipairs(cuts) do
			local nextCut=if i==#cuts then cuts[1]+2*math.pi else cuts[i+1]
			table.insert(spans,{g+half,nextCut-half})
		end
	end
	for _,span in ipairs(spans) do
		local width=span[2]-span[1]
		if width>0 then
			local n=math.max(1,math.ceil(width*rr/18))
			for i=0,n-1 do
				local a0,a1=span[1]+width*i/n,span[1]+width*(i+1)/n
				local p0=pos+V(math.cos(a0)*rr,0,math.sin(a0)*rr)
				local p1=pos+V(math.cos(a1)*rr,0,math.sin(a1)*rr)
				local mid=(p0+p1)/2
				local out=V(mid.X-pos.X,0,mid.Z-pos.Z).Unit
				local centre=mid+V(0,height/2,0)
				ghost(part(parent,"Edge guard",V((p1-p0).Magnitude+.9,height,1),CFrame.lookAt(centre,centre+out),cream,SM,true))
			end
		end
	end
end
local function angleNear(a,list,half)
	for _,g in ipairs(list or {}) do
		local ga,gh=g,half
		if type(g)=="table" then ga,gh=g[1],g[2] end
		if math.abs(math.atan2(math.sin(a-ga),math.cos(a-ga)))<gh then return true end
	end
	return false
end

-- A floating island: a grass Meadow (top = pos.Y) over a slate foundation.
-- The foundation top sits 0.3 studs inside the meadow, so no two upward faces
-- share a plane (the old stack z-fought across every island top).
local function island(name,pos,r,opts)
	opts=opts or {}
	local m=Instance.new("Model")
	m.Name=name
	m.Parent=opts.parent or islandsFolder
	local stone,stratum=opts.stone or rock,opts.stratum or shale
	disk(m,"Meadow",pos-V(0,.25,0),r+.1,.5,opts.top or turf,opts.ground or Enum.Material.Grass,true)
	disk(m,"Floating foundation",pos-V(0,3.3,0),r-.4,6,stone,ST,true)
	disk(m,"Mineral stratum",pos-V(0,7.4,0),r*.82,3,stratum,ST,false)
	disk(m,"Lower basalt",pos-V(0,11,0),r*.58,5,stone,ST,false)
	-- Fractured cliff skirt: irregular slabs under the rim break the disc outline.
	local count=math.clamp(math.floor(r/5),8,18)
	for i=1,count do
		local a=(i+hash(i,r)*.6)*2*math.pi/count
		local radial=V(math.cos(a),0,math.sin(a))
		local h=7+hash(i,2)*5
		local size=V(r*.16+5,h,r*.12+3)
		-- Sink by the tilt's rise too, so no corner pokes through the meadow.
		local spot=pos+radial*(r*.95)-V(0,h/2+1.4+size.X*.05+size.Z*.04,0)
		local slab=part(m,"Fractured cliff",size,CFrame.new(spot)*CFrame.Angles(0,-a+math.pi/2,0)*CFrame.Angles(.08*(i%2*2-1),0,.1),i%2==0 and stone or stratum,ST,false)
		if i%4==0 then meshSlot(slab,"CliffRock",nil,r/40) end
		if i%5==0 then gem(m,"Aether vein",spot-V(0,h/2,0),V(1.6,6,1.6),opts.vein or mint,a) end
	end
	-- Keel: rock shards hanging under the island.
	local keel=opts.keel or (if r>=60 then 5 elseif r>=25 then 4 else 3)
	for i=1,keel do
		local a=i*2*math.pi/keel+hash(i,7)
		local d=r*(.15+.25*hash(i,3))
		local h=r*.3+6
		local shard=part(m,"Keel rock",V(r*.22,h,r*.2),CFrame.new(pos+V(math.cos(a)*d,-13.5-h*.35,math.sin(a)*d))*CFrame.Angles(.12,a,.14),i%2==0 and stone or darken(stone,.2),ST,false)
		if i==1 then meshSlot(shard,"CliffRock",nil,r/40) end
	end
	-- Shoreline: weathered ledges beyond the rim (below the meadow top) and a
	-- few boulders just inside it. Openings (bridges, docks) stay clear.
	local clear={}
	for _,g in ipairs(opts.gaps or {}) do table.insert(clear,{g,(GAP_HALF+5)/r}) end
	for _,c in ipairs(opts.clear or {}) do table.insert(clear,c) end
	if opts.shore~=false then
		local ledges=math.clamp(math.floor(r/12),3,9)
		for i=1,ledges do
			local a=(i+hash(i,11)*.5)*2*math.pi/ledges
			if not angleNear(a,clear,0) then
				local radial=V(math.cos(a),0,math.sin(a))
				local w=6+hash(i,5)*6
				part(m,"Shore ledge",V(w,1.2,w*.7),CFrame.new(pos+radial*(r+w*.18)-V(0,.95,0))*CFrame.Angles(0,-a+hash(i,9),0),opts.ledge or lighten(stone,.15),ST,false)
			end
		end
		local stones=math.clamp(math.floor(r/9),3,12)
		for i=1,stones do
			local a=(i+.5+hash(i,13)*.4)*2*math.pi/stones
			if not angleNear(a,clear,0) then
				local radial=V(math.cos(a),0,math.sin(a))
				local s=1.6+hash(i,17)*1.6
				local boulder=part(m,"Shore boulder",V(2*s,1.4*s,1.7*s),CFrame.new(pos+radial*(r-3.2)+V(0,.45*s,0))*CFrame.Angles(.1,a*3,.12),i%3==0 and stratum or lighten(stone,.08),ST,true)
				meshSlot(boulder,"Rock",nil,s/2)
			end
		end
	end
	if opts.rim~=false then rim(m,pos,r,opts.gaps) end
	m:SetAttribute("IslandRadius",opts.footprint or r)
	m:SetAttribute("IslandCenter",pos)
	m:SetAttribute("Region",opts.region or "Home")
	if opts.region and opts.region~="Home" then m:SetAttribute("RegionId",opts.region) end
	return m
end

-- Raised tier: a slate cliff drum under a grass cap (cap inset so a stone lip
-- shows), dressed with leaning cliff rocks. Returns the model and top height.
local function tier(parent,name,base,r,h,opts)
	opts=opts or {}
	local m=group(name,parent)
	local bottom=base.Y-.6
	local cliffTop=base.Y+h-.15
	disk(m,"Tier cliff",V(base.X,(bottom+cliffTop)/2,base.Z),r,cliffTop-bottom,opts.cliff or rock,ST,true)
	disk(m,"Upper meadow",base+V(0,h-.25,0),r-.45,.5,opts.top or turf,opts.ground or Enum.Material.Grass,true)
	local n=math.max(4,math.floor(2*math.pi*r/13))
	for i=1,n do
		local a=(i+hash(i,r)*.5)*2*math.pi/n
		if not angleNear(a,opts.open,(6+r*.1)/r) then
			local radial=V(math.cos(a),0,math.sin(a))
			local rh=h*.7+hash(i,h)*h*.35
			local size=V(4+hash(i,3)*4,rh,3)
			local spot=base+radial*(r+.4)+V(0,(h-.8)-rh/2,0)
			local slab=part(m,"Cliff rock",size,CFrame.new(spot)*CFrame.Angles(0,-a+math.pi/2,0)*CFrame.Angles(-.14,0,.06*(i%2*2-1)),i%2==0 and (opts.cliff or rock) or lighten(opts.cliff or rock,.12),ST,false)
			if i%3==1 then meshSlot(slab,"CliffRock",nil,rh/8) end
		end
	end
	return m,base.Y+h
end
-- Ramp: walkable incline whose top surface runs from `low` to `high`.
local function ramp(parent,low,high,width,color,mat)
	local cf=CFrame.lookAt((low+high)/2,high)*CFrame.new(0,-.3,0)
	return part(parent,"Ramp",V(width,.6,(high-low).Magnitude+1),cf,color or C("8B8574"),mat or ST,true)
end
-- Flat path strip: top at a.Y+lift (vary lift where strips cross).
local function path(parent,a,b,width,color,lift)
	lift=lift or .08
	local flatB=V(b.X,a.Y,b.Z)
	local mid=(a+flatB)/2+V(0,lift-.08,0)
	return part(parent,"Path",V(width,.16,(flatB-a).Magnitude),CFrame.lookAt(mid,flatB+V(0,lift-.08,0)),color or C("B7A98A"),Enum.Material.Cobblestone,false)
end
local function pond(parent,c,r,opts)
	opts=opts or {}
	local m=group(opts.name or "Pond",parent)
	disk(m,"Pond bank",c+V(0,.04,0),r+1.4,.08,opts.bank or C("A39F84"),SA,false)
	disk(m,"Pond bed",c+V(0,.06,0),r,.12,darken(teal,.5),GR,false)
	local water=disk(m,"Pond water",c+V(0,.17,0),r-.15,.1,opts.water or C("5AA9B5"),GL,false)
	water.Transparency=.35
	for i=1,opts.stones or 5 do
		local a=i*2*math.pi/(opts.stones or 5)+hash(i,r)
		local s=1+hash(i,4)*1.2
		local stone=part(m,"Pond stone",V(1.8*s,1*s,1.5*s),CFrame.new(c+V(math.cos(a)*(r+1),.3*s,math.sin(a)*(r+1)))*CFrame.Angles(0,a,.1),lighten(rock,.2),ST,false)
		if i==1 then meshSlot(stone,"Rock",nil,s/2) end
	end
	return m,water
end
local function outcrop(parent,c,s,seed)
	local m=group("Rock outcrop",parent)
	seed=seed or 0
	local main=part(m,"Outcrop rock",V(4.5,3.6,4)*s,CFrame.new(c+V(0,1.2*s,0))*CFrame.Angles(.1,seed,.15),rock,ST,true)
	part(m,"Outcrop rock",V(3,2.4,2.8)*s,CFrame.new(c+V(2.6*s,.7*s,1.4*s))*CFrame.Angles(-.12,seed+1.3,.1),shale,ST,true)
	part(m,"Outcrop rock",V(2.2,1.6,2)*s,CFrame.new(c+V(-2.2*s,.5*s,1.8*s))*CFrame.Angles(.2,seed+2.1,-.1),darken(rock,.15),ST,false)
	meshSlot(main,"RockOutcrop",nil,s,true)
	return m
end
local CANOPY={C("6E9A5E"),C("7FAA62"),C("5E8B57"),C("8DB46C")}
local function decorTree(parent,c,s,kind,tint)
	kind=kind or "Meadow"
	local m=group(kind.." tree",parent)
	local trunk=disk(m,"Trunk",c+V(0,3*s,0),.55*s,6*s,darken(timber,.2),WO,true)
	local shapeName="MeadowTree"
	if kind=="Pine" then
		shapeName="PineTree"
		local col=tint or C("4E7A4A")
		part(m,"Pine boughs",V(5.4,4.2,5.4)*s,CFrame.new(c+V(0,5.8*s,0))*CFrame.Angles(0,.4,0),darken(col,.1),LEAF,false)
		part(m,"Pine crown",V(3.2,3.6,3.2)*s,CFrame.new(c+V(0,8.8*s,0))*CFrame.Angles(0,1.2,0),col,LEAF,false)
	elseif kind=="Palm" then
		shapeName="PalmTree"
		trunk.CFrame=CFrame.new(c+V(.6*s,3*s,0))*CFrame.Angles(0,0,math.pi/2+.18)
		disk(m,"Palm fronds",c+V(1.2*s,6.3*s,0),3.6*s,.5*s,tint or C("6FA05A"),LEAF,false)
	elseif kind=="Dead" then
		shapeName="DeadTree"
		trunk.Color=C("5B5048")
		beam(m,"Bare bough",c+V(0,4.5*s,0),c+V(2.4*s,7*s,.6*s),.45*s,C("5B5048"),WO)
	else
		ball(m,"Canopy",c+V(0,7.2*s,0),6.8*s,tint or CANOPY[math.floor(hash(c.X,c.Z)*#CANOPY)+1],LEAF)
	end
	meshSlot(trunk,shapeName,tint,s,true)
	return m
end
local function bush(parent,c,s,color)
	local b=ball(parent,"Shrub",c+V(0,.9*s,0),2.6*s,color or C("6C9A58"),LEAF)
	meshSlot(b,"Bush",color,s)
	return b
end
local function flowers(parent,c,r,color,lift)
	return disk(parent,"Wildflowers",c+V(0,(lift or .07)-.03,0),r,.06,color or rose,Enum.Material.Fabric,false)
end
local function lamp(parent,pos)
	local m=group("Lamp post",parent)
	block(m,"Lamp foot",pos+V(0,.3,0),V(1.4,.6,1.4),ink,ST,false)
	local mast=block(m,"Bronze mast",pos+V(0,2.1,0),V(.25,3.7,.25),brass,MT,false)
	meshSlot(mast,"Lamp",nil,1,true)
	local lantern=sculpture(m,"Aether lantern",pos+V(0,4,0),"Lantern",0.7)
	light(lantern,warm,1.2,18,{kind="SpotLight",face=Enum.NormalId.Bottom,angle=120,night=true})
	return m
end
local function bridge(parent,a,b)
	local dir=(b-a).Unit
	-- Decks reach 1.5 studs onto each meadow (their top is above it).
	a,b=a-dir*1.5,b+dir*1.5
	local side=V(-dir.Z,0,dir.X)
	-- Deck top 0.08 above both meadows so its ends never share a plane with them.
	local cf=CFrame.lookAt((a+b)/2-V(0,.17,0),b-V(0,.17,0))
	part(parent,"Continuous bridge deck",V(7,.5,(b-a).Magnitude),cf,timber,WO,true)
	local count=math.ceil((b-a).Magnitude/4)
	for i=0,count do
		local p=a+(b-a)*i/count+V(0,.1,0)
		part(parent,"Cross tie",V(7.3,.14,.5),CFrame.lookAt(p,p+dir),brass,WO,false)
		if i%2==0 or i==count then
			for _,s in ipairs({-1,1}) do
				local post=block(parent,"Railing post",p+side*3.7*s+V(0,1.2,0),V(.38,3,.38),ink,WO,false)
				if i%4==0 then meshSlot(post,"BridgePost") end
			end
		end
	end
	for _,s in ipairs({-1,1}) do
		beam(parent,"Guide rail",a+side*3.7*s+V(0,2.3,0),b+side*3.7*s+V(0,2.3,0),.27,brass,SM)
		-- Invisible collider behind the rail: the void is only crossed on the deck.
		local guard=part(parent,"Bridge guard",V(.4,7,(b-a).Magnitude+1),CFrame.lookAt((a+b)/2+side*3.9*s+V(0,3.5,0),b+side*3.9*s+V(0,3.5,0)),cream,SM,true)
		guard.Transparency,guard.CastShadow=1,false
	end
end

-------------------------------------------------------------------------------
-- Legacy gather props and stalls.
-------------------------------------------------------------------------------
local function windpine(parent,pos,scale,owner)
	local m=group("Windpine",parent)
	local trunk=block(m,"Heartwood",pos+V(0,2.6*scale,0),V(1.2,5.2,1.2)*scale,timber,WO,true)
	trunk.Transparency=1
	sculpture(m,"Sculpted windpine",pos+V(0,2.6*scale,0),"WindpineCrown",scale)
	prompt(trunk,"Cut timber","Windpine","gather","Timber",owner)
end
local function ore(parent,pos)
	local base=disk(parent,"Ore seam",pos+V(0,.4,0),2.5,.8,shale,ST,false)
	meshSlot(base,"OreVein",C("C98D4F"),1)
	sculpture(parent,"Faceted copper cluster",pos+V(0,1.4,0),"AetherCrystal",1)
	prompt(base,"Mine ore","Copper lode","gather","Ore")
end
local function herb(parent,pos)
	local bed=disk(parent,"Herb bed",pos+V(0,.15,0),2.3,.3,navy,ST,false)
	meshSlot(bed,"CropBed",mint,1)
	for i=1,6 do
		local a=i*1.8
		local p=pos+V(math.cos(a)*1.5,.65,math.sin(a)*1.5)
		sculpture(parent,"Sculpted moonbloom",p,"Moonbloom",.65,i*50)
	end
	prompt(bed,"Gather herbs","Moonleaf patch","gather","Herb")
end
-- Stall facing `toward`: counter, awning (strips abut, never overlap) and a
-- header sign over the customer side.
local function marketStall(parent,pos,toward,name,verb,action,item,accent,kicker)
	local m=group(name,parent)
	local cf=facing(pos,toward)
	for _, x in ipairs({-3.2,3.2}) do
		for _, z in ipairs({-2,2}) do part(m,"Awning stay",V(.3,5.8,.3),at(cf,x,2.9,z),brass,MT,false) end
	end
	for i=-2,2 do
		part(m,"Striped canvas",V(1.5,.35,5.4),at(cf,i*1.5,5.7,0)*CFrame.Angles(.09,0,0),i%2==0 and accent or cream,Enum.Material.Fabric,false)
	end
	local counter=part(m,"Counter",V(6.5,2.8,2),at(cf,0,1.4,0),navy,WO,true)
	part(m,"Counter top",V(7,.25,2.5),at(cf,0,2.92,0),brass,WO,false)
	meshSlot(counter,"MarketStall",accent,1,true)
	signAt(m,at(cf,0,.6,-2.65),name,kicker or "COMPASS QUAY   /   SERVICES",accent,8)
	if verb then prompt(counter,verb,name,action,item) end
	return m,cf
end

-------------------------------------------------------------------------------
-- Layout. Centres and radii (wave 4):
--   Compass Quay (hub)  (0,0,0)        r115   Guild Terrace (0,0,232)      r75
--   Mosswake Grove      (-230,0,0)     r72    Meadow Reach  (-230,0,185)   r70
--   Brassfall Quarry    (230,0,0)      r74    Cinder Shelf  (230,-6,-185)  r58
--   Warden Reach        (0,0,-230)     r70    Skyreach      (430,40,110)   r66
--   Windpine Grove      (-500,24,-160) r85    Gloomhollow   (440,-16,-440) r82
--   Tidewater Shoals    (-520,2,440)   r92    Tempest Spire (600,80,-220)  r70
--   Homes: core r21 + tiers (footprint r50), 6 per row from (-300,0,600), 120 apart.
--   Crew havens: r46, 5 per row from (-260,0,-620), 130 apart.
-------------------------------------------------------------------------------
local HUB_R=115
local G,GR_R=V(-230,0,0),72
local Q,Q_R=V(230,0,0),74
local W,W_R=V(0,0,-230),70
local SR,SR_R=V(430,40,110),66
local HUB_ARRIVAL=V(50,4,56)
local HALF=math.pi/2

-------------------------------------------------------------------------------
-- Compass Quay: plaza, market row, Artisans' Rise, Sky Harbor, Mooncrest
-- Gardens, Orchard terrace and four avenues to the bridges.
-------------------------------------------------------------------------------
local hub = island("Compass Quay",V(0,0,0),HUB_R,{top=C("9DAA85"),region="Hub",gaps={0,math.pi,-HALF,HALF},
	clear={{math.rad(45),.2}},keel=6})
local harbor=group("Sky Harbor",hub)
do
local plaza=group("Compass Plaza",hub)
disk(plaza,"Plaza ring",V(0,0,0),26,.2,C("C9B994"),ST,true)
disk(plaza,"Compass court",V(0,.02,0),23.5,.26,navy,ST,true)
for i=1,8 do
	local a=i*math.pi/4
	local d=V(math.cos(a),0,math.sin(a))
	beam(plaza,"Compass inlay",d*5+V(0,.2,0),d*(i%2==0 and 21 or 14)+V(0,.2,0),.3,brass,MT)
end
local monument=group("Compass Monument",plaza)
disk(monument,"Monument plinth",V(0,1.2,0),4.2,2.4,C("8F97A3"),ST,true)
local obelisk=block(monument,"Wayfinder obelisk",V(0,8.9,0),V(2.2,13,2.2),C("C9CFD6"),ST,true)
meshSlot(obelisk,"Statue",brass,1.5,true)
disk(monument,"Beacon brazier",V(0,15.8,0),1.7,.8,brass,MT,false)
local heroFlame=ball(monument,"Beacon flame",V(0,16.7,0),1.3,C("FFC77A"),NE)
-- Hero light #1 (shadows): the plaza beacon.
light(heroFlame,C("FFC98A"),1.1,46,{shadows=true,lift=1})
for _,dir in ipairs({V(1,0,0),V(-1,0,0),V(0,0,1),V(0,0,-1)}) do
	path(hub,dir*26,dir*112,10)
end
sign(plaza,V(0,0,-30),"Compass Quay","01   /   SKY HARBOR + GUILDS",brass,0,12)
-- Hub spawn: every arrival from home lands on the Sky Harbor plaza.
disk(harbor,"Harbor plaza",V(56,0,60),17,.24,C("C9B994"),ST,true)
disk(harbor,"Harbor seal",V(56,.06,60),5,.3,navy,ST,false)
sign(harbor,V(56,0,40),"Sky Harbor","ARRIVALS   /   HOMEWARD · CREW HAVEN",mint,0,12)
for i,offset in ipairs({{V(66,0,70),V(78,0,82)},{V(73,0,58),V(87,0,72)}}) do
	local a,b=offset[1],offset[2]
	local dir=(b-a).Unit
	local side=V(-dir.Z,0,dir.X)
	part(harbor,"Pier deck",V(6,.3,(b-a).Magnitude),CFrame.lookAt((a+b)/2+V(0,.15,0),b+V(0,.15,0)),timber,WO,true)
	for _,t in ipairs({.25,.9}) do
		for _,s in ipairs({-1,1}) do
			local post=block(harbor,"Mooring post",a+(b-a)*t+side*3.2*s+V(0,1.1,0),V(.6,2.2,.6),darken(timber,.4),WO,false)
			if t==.9 then meshSlot(post,"BridgePost") end
		end
	end
	if i==1 then lamp(harbor,b-dir*2+side*2.2) end
end
local ship=group("Moored skyship",harbor)
local hull=part(ship,"Skyship hull",V(9,5,30),CFrame.new(V(98,-1.5,98))*CFrame.Angles(0,math.rad(-45),0),C("7A5A40"),WO,false)
meshSlot(hull,"Skyship",nil,1,true)
part(ship,"Skyship deck",V(8,.4,27),CFrame.new(V(98,1.2,98))*CFrame.Angles(0,math.rad(-45),0),C("A57C55"),WO,false)
part(ship,"Skyship mast",V(.8,16,.8),CFrame.new(V(98,9,98)),darken(timber,.3),WO,false)
part(ship,"Skyship sail",V(.3,9,12),CFrame.new(V(98,10,98))*CFrame.Angles(0,math.rad(45),0),cream,Enum.Material.Fabric,false)
ball(ship,"Skyship balloon",V(98,20,98),11,rose,Enum.Material.Fabric)
local HUB_GUIDE=anchor(hub,"NPC_Guide",V(56,0,50),HUB_ARRIVAL)
anchor(hub,"Waypoint_SkyHarbor",V(56,0,60),V(56,0,40))
-- Market Row along the east avenue.
local bank,bankCF=marketStall(hub,V(44,0,-17),V(44,0,0),"Quay Bank","Bank purse","bank",nil,mint,"MARKET ROW   /   BANK")
local trade,tradeCF=marketStall(hub,V(68,0,-17),V(68,0,0),"Trade Counter","Sell goods","sell",nil,brass,"MARKET ROW   /   TRADE")
marketStall(hub,V(50,0,17),V(50,0,0),"Fruit Stall",nil,nil,nil,rose,"MARKET ROW   /   PRODUCE")
marketStall(hub,V(76,0,17),V(76,0,0),"Cloth Stall",nil,nil,nil,teal,"MARKET ROW   /   CLOTH")
anchor(hub,"NPC_Banker",at(bankCF,0,0,2.4))
anchor(hub,"NPC_Merchant",at(tradeCF,0,0,2.4))
anchor(hub,"Waypoint_Bank",at(bankCF,0,0,-5)*CFrame.Angles(0,math.pi,0))
anchor(hub,"Waypoint_Market",at(tradeCF,0,0,-5)*CFrame.Angles(0,math.pi,0))
sculpture(hub,"Bank lockbox",at(bankCF,0,3.7,0).Position,"VaultChest",.65)
sculpture(hub,"Trader's timber",at(tradeCF,0,3.9,0).Position,"TimberBundle",.65,20)
for i,p in ipairs({V(58,0,-23),V(82,0,-21),V(38,0,22),V(90,0,21)}) do
	local crate=block(hub,"Market crate",p+V(0,.9,0),V(2.2,1.8,2.2),i%2==0 and timber or darken(timber,.2),WO,true)
	if i==1 then meshSlot(crate,"Crate") end
end
sign(hub,V(30,0,-12),"Market Row","BANK · TRADE · PRODUCE",brass,90,10)
-- Artisans' Rise: raised guild terrace with the Starforge.
local RISE=V(-52,0,52)
local rise,riseTop=tier(hub,"Artisans' Rise",RISE,26,4,{open={-math.pi/4,.34},top=C("A3AE86")})
ramp(rise,V(-29,0,29),V(-37,riseTop,37),8)
ramp(rise,V(-11,0,66),V(-30,riseTop,60),8)
local forgeStall,forgeCF=marketStall(rise,V(-56,riseTop,42),V(-36,riseTop,30),"Starforge","Forge pickaxe","craft","Pickaxe",rose,"ARTISANS' RISE   /   SMITHING")
anchor(hub,"NPC_Forgemaster",at(forgeCF,0,0,2.4))
anchor(hub,"Waypoint_Starforge",at(forgeCF,0,0,-5)*CFrame.Angles(0,math.pi,0))
local rack=block(rise,"Bladesmith rack",V(-66,riseTop+1.5,52),V(2,3,2),navy,ST,true)
prompt(rack,"Forge blade","Starforge","craft","Blade")
local apothecary=block(rise,"Apothecary vat",V(-46,riseTop+1,58),V(2.5,2,2.5),teal,SM,true)
meshSlot(apothecary,"Cauldron",teal,.7)
prompt(apothecary,"Brew tonic","Starforge","craft","Tonic")
sculpture(rise,"Smith's pickaxe",at(forgeCF,-2,4,0).Position,"Pickaxe",.7,25)
sculpture(rise,"Smith's blade",V(-66,riseTop+4,52),"Blade",.65,-20)
sculpture(rise,"Alchemist tonic",V(-46,riseTop+3,58),"Tonic",.7)
local furnace=block(rise,"Rise furnace",V(-64,riseTop+1.6,40),V(4,3.2,3.4),C("6E4B3A"),Enum.Material.Brick,true)
meshSlot(furnace,"Forge",nil,.7)
local furnaceMouth=block(rise,"Furnace mouth",V(-64,riseTop+1.2,38.25),V(1.8,1.2,.2),C("FF8A3D"),NE,false)
light(furnaceMouth,C("FF9A52"),.8,14,{lift=1.2})
local statue=block(rise,"Founder statue",V(-60,riseTop+4.2,64),V(2.2,5,1.6),C("BFC6CE"),ST,true)
block(rise,"Statue plinth",V(-60,riseTop+.8,64),V(3.6,1.6,3.6),C("8F97A3"),ST,true)
meshSlot(statue,"Statue",nil,1)
for _,p in ipairs({V(-72,riseTop,36),V(-38,riseTop,70),V(-70,riseTop,66)}) do decorTree(rise,p,1.1) end
lamp(rise,V(-44,riseTop,46))
sign(hub,V(-22,0,42),"Artisans' Rise","STARFORGE · BLADES · TONICS",rose,45,10)
-- Mooncrest Gardens (north-west): pond, lookout knoll, groves.
local _,pondWater=pond(hub,V(-42,0,-40),13,{name="Mooncrest pond"})
for i=1,4 do disk(hub,"Lily pad",V(-42,0,-40)+V(math.cos(i*1.7)*7,.25+i*.02,math.sin(i*1.7)*7),.9,.04,C("5E9C62"),SM,false) end
local KNOLL=V(-64,0,-64)
local knoll,knollTop=tier(hub,"Lookout knoll",KNOLL,14,6,{open={-.35}})
ramp(knoll,V(-42,0,-72),V(-54,knollTop,-68),7)
block(knoll,"Lookout bench",V(-66,knollTop+.6,-58),V(5,.4,1.6),navy,WO,true)
local spyglass=block(knoll,"Brass spyglass",V(-60,knollTop+1.8,-72),V(.5,.5,3),brass,MT,false)
meshSlot(spyglass,"Spyglass")
decorTree(knoll,V(-70,knollTop,-68),1,"Pine")
decorTree(knoll,V(-62,knollTop,-54),.9,"Pine")
lamp(knoll,V(-58,knollTop,-62))
sign(hub,V(-24,0,-30),"Mooncrest Gardens","POND · LOOKOUT KNOLL",mint,45,10)
-- Orchard terrace (north-east).
local orchard,orchardTop=tier(hub,"Orchard terrace",V(64,0,-64),16,3,{open={2.41}})
ramp(orchard,V(44,0,-46),V(54,orchardTop,-55),7)
for i,o in ipairs({V(58,0,-70),V(70,0,-60),V(72,0,-72),V(62,0,-56)}) do decorTree(orchard,o+V(0,orchardTop,0),.95,"Meadow",i%2==0 and C("8DB46C") or C("A0B860")) end
-- Avenue lamps (night) and approach signs.
for _,p in ipairs({V(34,0,8),V(64,0,-8),V(96,0,8),V(-34,0,-8),V(-64,0,8),V(-96,0,-8),
	V(8,0,-34),V(-8,0,-64),V(8,0,-96),V(-8,0,34),V(8,0,64),V(-8,0,96),V(46,0,74)}) do lamp(hub,p) end
sign(hub,V(-100,0,-12),"Mosswake Grove","WEST   /   TIMBER + HERBS",mint,90,10)
sign(hub,V(100,0,12),"Brassfall Quarry","EAST   /   COPPER ORE",brass,90,10)
sign(hub,V(12,0,-100),"Warden Reach","NORTH   /   HUNTS",rose,0,9)
sign(hub,V(-12,0,100),"Guild Terrace","SOUTH   /   CRAFT · SLAYER · SKYWAY",brass,0,10)
-- Flora and outcrops.
for i,p in ipairs({V(-92,0,48),V(-30,0,96),V(-56,0,86),V(-20,0,-34),V(-66,0,-26),V(-24,0,-62),V(-84,0,-18),
	V(-52,0,-16),V(30,0,-40),V(96,0,-30),V(36,0,-86),V(22,0,40),V(92,0,26),V(24,0,86),V(-88,0,-60)}) do
	decorTree(hub,p,.9+hash(i,1)*.4,if i%4==0 then "Pine" else "Meadow")
end
for i,p in ipairs({V(-90,0,30),V(92,0,40),V(20,0,-92),V(-30,0,82),V(84,0,-48)}) do outcrop(hub,p,1+hash(i,8)*.5,i) end
for i,p in ipairs({V(-30,0,-50),V(-56,0,-28),V(26,0,30),V(40,0,-34),V(-20,0,22)}) do
	flowers(hub,p,2.5+hash(i,2)*2,({rose,cream,C("C9A0DC")})[i%3+1],.06+i*.012)
end
for _,p in ipairs({V(-34,0,-22),V(-60,0,-46),V(16,0,-22),V(-16,0,30)}) do bush(hub,p,1) end
end
local skyMarker=hidden(hub,"Tidewing",V(14,32,-12))
skyMarker.CFrame *= CFrame.Angles(0,math.rad(33),0)
skyMarker:SetAttribute("Shape","Tidewing")
Tags:AddTag(skyMarker,"AetherSculpture")

-------------------------------------------------------------------------------
-- Mosswake Grove (west), Brassfall Quarry (east), Warden Reach (north).
-------------------------------------------------------------------------------
local grove = island("Mosswake Grove",G,GR_R,{region="Meadow",gaps={0,HALF}})
local mine = island("Brassfall Quarry",Q,Q_R,{top=C("9C9682"),region="Quarry",gaps={math.pi,-HALF},ground=GR})
local wild = island("Warden Reach",W,W_R,{top=C("7C8498"),region="Hub",gaps={HALF}})
bridge(hub,V(-HUB_R,0,0),G+V(GR_R,0,0))
bridge(hub,V(HUB_R,0,0),Q-V(Q_R,0,0))
bridge(hub,V(0,0,-HUB_R),W+V(0,0,W_R))
anchor(hub,"Waypoint_Bridge_MosswakeGrove",V(-HUB_R+6,0,0),G)
anchor(hub,"Waypoint_Bridge_BrassfallQuarry",V(HUB_R-6,0,0),Q)
anchor(hub,"Waypoint_Bridge_WardenReach",V(0,0,-HUB_R+6),W)
do
-- Grove.
path(grove,G+V(GR_R-2,0,0),G,8)
path(grove,G,G+V(0,0,GR_R-2),8,nil,.11)
for _,o in ipairs({V(30,0,-30),V(10,0,-46),V(-48,0,6),V(-6,0,42),V(38,0,30)}) do windpine(grove,G+o,1.4) end
herb(grove,G+V(26,0,10))
local MOSS=G+V(-34,0,22)
local moss,mossTop=tier(grove,"Moss terrace",MOSS,16,3,{open={-.46},top=C("74A06A")})
ramp(moss,G+V(-14,0,12),G+V(-24,mossTop,18),7)
herb(moss,MOSS+V(2,mossTop,2))
local MOONPOOL=G+V(-24,0,-26)
pond(grove,MOONPOOL,13,{name="Moonpool"})
local jettyAt=MOONPOOL+V(9,0,7.2)
local dock=part(grove,"Fishing jetty",V(3,1,9),CFrame.lookAt(jettyAt+V(0,.5,0),MOONPOOL+V(0,.5,0)),timber,WO,true)
meshSlot(dock,"FishingPier",nil,1)
prompt(dock,"Cast line","Moonpool","gather","Fish").HoldDuration=FISH_HOLD
anchor(grove,"NPC_Fisher",jettyAt+(jettyAt-MOONPOOL).Unit*5.5,MOONPOOL)
anchor(grove,"Waypoint_Moonpool",jettyAt+(jettyAt-MOONPOOL).Unit*8,MOONPOOL)
sign(grove,MOONPOOL+V(20,0,-4),"Moonpool","MOSSWAKE   /   ANGLING",mint,90,8)
sign(grove,G+V(58,0,-12),"Mosswake Grove","TIMBER · HERBS · MOONPOOL",mint,90,10)
for _,o in ipairs({V(40,0,8),V(-8,0,40),V(-10,0,-8)}) do lamp(grove,G+o) end
for i=1,11 do
	local a=i*2*math.pi/11+.3
	local d=52+hash(i,3)*8
	local o=V(math.cos(a)*d,0,math.sin(a)*d)
	if not angleNear(a,{0,HALF},.2) then decorTree(grove,G+o,1+hash(i,4)*.4,if i%3==0 then "Pine" else "Meadow") end
end
for i,o in ipairs({V(-50,0,-30),V(44,0,-50),V(-30,0,52)}) do outcrop(grove,G+o,1.2,i) end
for i,o in ipairs({V(16,0,-14),V(-40,0,-6),V(20,0,52)}) do flowers(grove,G+o,3,({C("C9A0DC"),cream,rose})[i],.07+i*.012) end
-- Quarry: a terraced pit face with a bench of ore, the old crane and the charter beacon.
path(mine,Q-V(Q_R-2,0,0),Q,9)
path(mine,Q,Q-V(0,0,Q_R-2),8,nil,.11)
local BENCH=Q+V(26,0,-36)
local bench,benchTop=tier(mine,"Quarry bench",BENCH,18,5,{open={2.356},cliff=C("6F6759"),top=C("9C9682"),ground=GR})
tier(mine,"Quarry face",V(Q.X+32,benchTop,Q.Z-42),9,5,{cliff=C("5E574C"),top=C("8F897A"),ground=GR})
ramp(bench,Q+V(8,0,-18),Q+V(16,benchTop,-27),7)
for _,o in ipairs({V(-38,0,14),V(-18,0,-22),V(8,0,20)}) do ore(mine,Q+o) end
ore(bench,Q+V(14,benchTop,-44))
local advanced=group("Aetherite outcrop",mine)
local vein=sculpture(advanced,"Aetherite seam",Q+V(26,1.5,28),"AetherCrystal",1.45,30)
prompt(vein,"Mine Aetherite","Mining 3 required","gather","Aetherite")
sign(advanced,Q+V(36,0,26),"Aetherite","MINING 3 / REFINE AT THE STARFORGE",mint,0,8)
for i=1,5 do
	local post=block(mine,"Hoist support",Q+V(-32+8*i,2.5,40),V(.7,5,.7),timber,WO,false)
	if i==1 then meshSlot(post,"Crane") end
end
beam(mine,"Old crane",Q+V(-24,5,40),Q+V(8,5,40),.6,timber,WO)
for i,o in ipairs({V(-50,0,-30),V(44,0,-6),V(-30,0,48),V(52,0,34)}) do outcrop(mine,Q+o,1.1+hash(i,2)*.6,i) end
for i,o in ipairs({V(-56,0,24),V(-20,0,58),V(40,0,52)}) do decorTree(mine,Q+o,1,"Pine",C("5E7752")) end
for _,o in ipairs({V(-30,0,6),V(4,0,-50),V(30,0,12)}) do lamp(mine,Q+o) end
sign(mine,Q+V(-60,0,12),"Brassfall Quarry","COPPER · AETHERITE · SKYREACH",brass,90,10)
anchor(mine,"Waypoint_AetheriteSeam",Q+V(20,0,22),Q+V(26,0,28))
-- Warden Reach: waystone avenue, ruined ring around the Shellwarden, vault gate.
path(wild,W+V(0,0,W_R-2),W+V(0,0,-46),10,C("9A9AA6"))
for _,z in ipairs({48,28,-28}) do
	for _,x in ipairs({-16,16}) do
		local stone=block(wild,"Waystone",W+V(x,3,z),V(2.5,6,2.5),rock,ST,true)
		meshSlot(stone,"Waystone",rose,1)
		gem(wild,"Signal prism",W+V(x,6.3,z),V(1,2.3,1),rose,.7)
	end
end
for i,deg in ipairs({0,60,120,180,240,300}) do
	local a=math.rad(deg)
	local h=4+hash(i,6)*6
	local col=block(wild,"Ruined column",W+V(math.cos(a)*20,h/2,math.sin(a)*20),V(2.2,h,2.2),C("A3A6B2"),ST,true)
	if i%2==0 then meshSlot(col,"RuinColumn",nil,h/8) end
end
local boss=hidden(wild,"Shellwarden",W+V(0,2,0))
boss:SetAttribute("Shape","Shellwarden")
Tags:AddTag(boss,"AetherSculpture")
prompt(boss,"Strike","Shellwarden","fight","Warden")
disk(wild,"Warden dais",W+V(0,.1,0),12,.22,shale,ST,true)
anchor(wild,"Waypoint_Shellwarden",W+V(0,0,16),W)
sign(wild,W+V(12,0,40),"Shellwarden","WARDEN REACH   /   HUNT",rose,0,10)
local GATE=W+V(0,0,-50)
local gate=block(wild,"ExpeditionGate",GATE+V(0,2,0),V(2,4,2),teal,GL,false)
gate.Transparency=1
gate:SetAttribute("Shape","ObservatoryArch")
gate:SetAttribute("SculptureScale",1)
Tags:AddTag(gate,"AetherSculpture")
for _,x in ipairs({-3.2,3.2}) do block(wild,"Vault pier",GATE+V(x,3.5,0),V(2,7,2.4),rock,ST,true) end
block(wild,"Vault lintel",GATE+V(0,7.5,0),V(9,1.4,2.4),brass,SM,false)
sign(wild,GATE+V(-10,0,2),"Vault Gate","EXPEDITION   /   ENTRY",brass,0,7)
anchor(wild,"Waypoint_ExpeditionGate",GATE+V(0,0,8),GATE)
for _,x in ipairs({-8,8}) do lamp(wild,GATE+V(x,0,8)) end
tier(wild,"West crag",W+V(-40,0,-6),16,5,{cliff=C("545B6B"),top=C("7C8498")})
tier(wild,"East crag",W+V(40,0,-6),16,7,{cliff=C("4B5262"),top=C("737B8F")})
for i,o in ipairs({V(-30,0,40),V(34,0,36),V(-44,0,-40),V(46,0,-38)}) do decorTree(wild,W+o,1.1,"Dead") end
for i,o in ipairs({V(-26,0,-44),V(28,0,52)}) do outcrop(wild,W+o,1.3,i) end
sign(wild,W+V(-12,0,58),"Warden Reach","SHELLWARDEN · VAULT GATE",rose,0,10)
end
-- Distant drifting spires frame the horizon.
for i=1,8 do
	local a=i*math.pi/4+.3
	local pos=V(math.cos(a)*760,-30+(i%3)*24,math.sin(a)*700)
	local landmark=group("Drifting spire")
	gem(landmark,"Distant basalt",pos,V(22+i%3*6,58,26),rock,a)
	gem(landmark,"Distant shard",pos+V(8,18,4),V(10,44,10),teal,a+.7)
end

local slots,homes={},{}
-- Builder's Terrace furniture (attached at the end of this script, see homeTerrace.attach).
local homeTerrace={}
-- Free-form island placements (attached at the end of this script, see homePlacement.attach).
local homePlacement={}
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
local skyreach = island("Skyreach",SR,SR_R,{top=C("96ACAB"),region="Skyreach"})
local SKYREACH_LANDING = SR+V(-52,4,0)
anchor(skyreach,"Waypoint_Entrance_Skyreach",SKYREACH_LANDING-V(0,4,0),SR)
-- Assigned with the regional beacons below: pcall + table check + denial notice.
local regionTravel
local launch = sculpture(mine,"Charter beacon",Q+V(58,2,6),"Lantern",1.2)
sign(mine,Q+V(54,0,-4),"Skyreach passage","GUILD CHARTER REQUIRED",brass,90,9)
anchor(mine,"Waypoint_SkyreachCharter",Q+V(52,0,8),Q+V(58,0,6))
local launchPrompt=prompt(launch,"Ascend to Skyreach","Guild charter required")
launchPrompt:SetAttribute("IsleWarpRegion","Skyreach")
launchPrompt.Triggered:Connect(function(player)
	regionTravel(player,launch,"Skyreach",SKYREACH_LANDING)
end)
local descent = sculpture(skyreach,"Quarry beacon",SR+V(-46,2,-10),"Lantern",1.1)
prompt(descent,"Return to quarry","Brassfall").Triggered:Connect(function(player)
	warp(player,descent,Q+V(50,4,14))
end)
do
local SUMMIT=SR+V(16,0,-4)
local summit,summitTop=tier(skyreach,"Summit",SUMMIT,18,6,{open={2.747},cliff=C("5F6F74"),top=C("A3B8B4")})
ramp(summit,SR+V(-8,0,6),V(SR.X+2,summitTop,SR.Z+2),7)
local survey = sculpture(summit,"Summit cartographer",V(SUMMIT.X+2,summitTop+2,SUMMIT.Z-4),"Surveyor",1.1,180)
prompt(survey,"Survey the summit","Skyreach","explore","Skyreach"):SetAttribute("IsleRegion","Skyreach")
local rich = sculpture(skyreach,"Rich Aetherite seam",SR+V(-14,2,28),"AetherCrystal",1.8)
prompt(rich,"Mine rich seam","Skyreach Aetherite","gather","Aetherite"):SetAttribute("IsleRegion","Skyreach")
sign(skyreach,SR+V(-38,0,-16),"Skyreach","SURVEY THE SUMMIT / MINE RICH SEAMS",mint,90,10)
for i,o in ipairs({V(-30,0,30),V(-20,0,-40),V(30,0,48),V(50,0,-2),V(-4,0,52)}) do decorTree(skyreach,SR+o,1,"Pine",C("5D8070")) end
for i,o in ipairs({V(-40,0,24),V(24,0,-44)}) do outcrop(skyreach,SR+o,1.2,i) end
for _,o in ipairs({V(-40,0,6),V(-10,0,20)}) do lamp(skyreach,SR+o) end
end
local returnPost=block(harbor,"Homeward beacon",V(66,2,64),V(2,4,2),mint,GL,false)
meshSlot(returnPost,"WarpBeacon",mint,1)
sign(harbor,V(71,0,58),"Homeward","WAYFARER TRANSIT   /   RETURN",mint,90,9)
anchor(hub,"Waypoint_Homeward",V(62,0,60),V(66,0,64))
prompt(returnPost,"Travel home","Homeward beacon").Triggered:Connect(function(player)
	local home=homes[player]
	if home then warp(player,returnPost,home.spawn.Position+V(0,4,0)) end
end)

-------------------------------------------------------------------------------
-- Homes. The core meadow (r21) keeps every fixed object at its legacy offset so
-- Data.Island's grid (RADIUS 18.5) and Protected rectangles stay valid; the
-- extra area is natural terrain: raised lobes with ramps, a pond and groves,
-- all outside the build grid. Footprint radius 50 (was 19).
-------------------------------------------------------------------------------
local HOME_CORE=21
local function homeTerrain(m,center)
	local lobes={
		{name="Orchard rise",o=V(0,0,-33),r=14,h=2.5},
		{name="East overlook",o=V(34,0,4),r=15,h=4},
		{name="Pine dell",o=V(-24,0,-26),r=16,h=1.5},
		{name="Pond garden",o=V(24,0,24),r=14,h=1.2},
	}
	for i,l in ipairs(lobes) do
		local dir=V(l.o.X,0,l.o.Z).Unit
		local a=math.atan2(-dir.Z,-dir.X)
		local lm,top=tier(m,l.name,center+l.o,l.r,l.h,{open={a},top=C("86AD7A")})
		local low=center+dir*(HOME_CORE-1.6)
		local high=center+dir*(HOME_CORE-1.6+l.h*2.4+2)+V(0,l.h,0)
		ramp(lm,low,high,5)
		local c=center+l.o+V(0,l.h,0)
		if i==1 then
			for _,o in ipairs({V(-6,0,-4),V(5,0,-6),V(0,0,4)}) do decorTree(lm,c+o,.85,"Meadow",C("9DBA6A")) end
		elseif i==2 then
			block(lm,"Overlook bench",c+V(4,.6,0),V(1.6,.4,5),navy,WO,true)
			outcrop(lm,c+V(-3,0,-7),.8,i)
			lamp(lm,c+V(2,0,6))
		elseif i==3 then
			for _,o in ipairs({V(-5,0,-4),V(4,0,-7),V(-7,0,6)}) do decorTree(lm,c+o,.9,"Pine") end
		else
			pond(lm,c+V(2,0,2),5,{stones=3})
			bush(lm,c+V(-6,0,-3),.9) bush(lm,c+V(-2,0,8),.8,C("8DB46C"))
		end
	end
end
local function settle(player)
	if homes[player] then return end
	local slot=1
	while slots[slot] do slot+=1 end
	slots[slot]=true
	local center=V((slot-1)%6*120-300,0,600+math.floor((slot-1)/6)*120)
	local m=island("WayfarersRest_"..player.UserId,center,HOME_CORE,{parent=world,rim=false,shore=false,footprint=50})
	homeTerrain(m,center)
	local spawn=Instance.new("SpawnLocation")
	spawn.Name,spawn.Anchored,spawn.Neutral,spawn.AllowTeamChangeOnTouch="Home Landing",true,true,false
	spawn.Size,spawn.Position,spawn.Transparency=V(4,.45,4),center+V(0,.25,5),1
	spawn.Duration,spawn.Parent=0,m
	player.RespawnLocation=spawn
	homes[player]={model=m,spawn=spawn,slot=slot,center=center,decorationConnections={}}
	anchor(m,"Waypoint_HomeLanding",center+V(0,0,5),center)
	local function land(character)
		local root=character:WaitForChild("HumanoidRootPart",10)
		if root and homes[player] and player.Character==character then character:PivotTo(CFrame.new(spawn.Position+V(0,3.4,0))) end
	end
	player.CharacterAdded:Connect(land)
	if player.Character then task.spawn(land,player.Character) end
	windpine(m,center+V(-6,0,0),1,player.UserId)
	sign(m,center+V(6,0,-5),"Wayfarer's Rest","HOME   /   CUT WINDPINE TO BEGIN",mint,0,9)
	local gatePost=block(m,"Quay beacon",center+V(0,2,-11),V(2,4,2),mint,GL,false)
	meshSlot(gatePost,"WarpBeacon",mint,1)
	for _,x in ipairs({-2.3,2.3}) do gem(m,"Transit fins",center+V(x,2,-11),V(.65,4,.65),brass,0) end
	prompt(gatePost,"Travel to hub","Compass Quay").Triggered:Connect(function(user)
		if user==player then warp(user,gatePost,HUB_ARRIVAL) end
	end)
	local fleetOffsets={V(9,0,4),V(13,0,-1),V(-10,0,-10)}
	for workerSlot,offset in ipairs(fleetOffsets) do
		local station=group("WorkerStation"..workerSlot,m)
		local position=center+offset
		disk(station,"Worker pad",position+V(0,.08,0),2.3,.16,navy,SM,false)
		local engine=block(station,"Surveyor chassis",position+V(0,1.35,0),V(2.8,2.7,2.5),navy,SM,true)
		local lens=block(station,"Eye lens",position+V(0,1.7,-1.35),V(1.55,.38,.18),mint,SM,false)
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
			block(addition,"Rich soil",center+V(-11,.67,1),V(5.4,.14,6.4),ink,GR,false)
			for row=-1,1 do
				for col=-1,1 do
					local flower=center+V(-11+col*1.6,1.2,1+row*1.8)
					block(addition,"Flower stem",flower,V(.14,1,.14),teal,SM,false)
					gem(addition,"Moonbloom",flower+V(0,.65,0),V(.9,.7,.9),row%2==0 and rose or cream,col*.6)
				end
			end
		else
			bridge(addition,center+V(0,0,HOME_CORE-.5),center+V(0,0,25))
			disk(addition,"Lookout deck",center+V(0,-.22,29),7,.6,timber,WO,true)
			for i=1,5 do
				local a=i*math.pi/3
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
	if homeTerrace.attach then homeTerrace.attach(player,homes[player]) end
	if homePlacement.attach then homePlacement.attach(player,homes[player]) end
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
local CREW_R=46
local K=1.6 -- crew haven layout scale (wave 4)
local sharedHomes,sharedPlayers,sharedSlots,sharedConnections={},{},{},{}
local sharedBeacon=block(harbor,"Crew beacon",V(44,2,68),V(2,4,2),teal,GL,false)
meshSlot(sharedBeacon,"WarpBeacon",teal,1)
sign(harbor,V(39,0,62),"Crew Haven","CO-OP / FORM A CREW IN THE ATLAS",mint,90,9)
anchor(hub,"Waypoint_CrewHaven",V(48,0,64),V(44,0,68))
prompt(sharedBeacon,"Visit shared island","Crew Haven").Triggered:Connect(function(player)
	local home=sharedHomes[sharedPlayers[player]]
	if home then warp(player,sharedBeacon,home.center+V(0,4,6*K)) end
end)
local function makeShared(groupKey,groupId,isPreview)
	local slot=1
	while sharedSlots[slot] do slot+=1 end
	sharedSlots[slot]=true
	local center=V(((slot-1)%5)*130-260,0,-620-math.floor((slot-1)/5)*130)
	local model=island("CrewHaven_"..groupKey,center,CREW_R,{parent=world,rim=false})
	model:SetAttribute("CoopId",groupId)
	local home={model=model,center=center,slot=slot,members={},built={}}
	sharedHomes[groupKey]=home
	anchor(model,"Waypoint_CrewLanding",center+V(0,0,6*K),center)
	tier(model,"Crew knoll",center+V(-22,0,-24),9,2.5,{top=C("86AD7A")})
	for i,o in ipairs({V(30,0,-20),V(-34,0,10),V(26,0,30),V(-10,0,36)}) do decorTree(model,center+o,1,if i%2==0 then "Pine" else "Meadow") end
	sign(model,center+V(8,0,8)*K,"Crew Haven","SHARED SUPPLIES / BUILD IN THE ATLAS",mint,0,12)
	local exit=block(model,"Quay return",center+V(0,2,16*K),V(2,4,2),mint,GL,false)
	meshSlot(exit,"WarpBeacon",mint,1)
	prompt(exit,"Return to hub","Compass Quay").Triggered:Connect(function(player)
		if sharedPlayers[player]==groupKey then warp(player,exit,HUB_ARRIVAL+V(-6,0,4)) end
	end)
	local function supply(name,pos,color)
		local base=block(model,"Shared "..name,center+pos,V(3,2,3),color,WO,true)
		base.Transparency=1
		sculpture(model,name.." supply marker",center+pos+V(0,.4,0),({Timber="TimberBundle",Ore="AetherCrystal",Herb="Moonbloom"})[name],1)
		local interaction=prompt(base,"Gather shared "..name,"Crew stores")
		interaction.HoldDuration=GATHER_HOLD
		interaction:SetAttribute("CoopId",groupId)
		interaction:SetAttribute("CoopPreview",isPreview)
		interaction:SetAttribute("IsleCoopResource",name)
	end
	supply("Timber",V(-12*K,1,-5*K),timber)
	supply("Ore",V(0,1,-14*K),shale)
	supply("Herb",V(12*K,1,-5*K),teal)
	for _,offset in ipairs({V(-6,0,12),V(6,0,12)}) do lamp(model,center+offset*K) end
	return home
end
local function sharedDecorate(home,player)
	for _,key in ipairs({"Garden","Lanterns","Deck"}) do
		if not home.built[key] and player:GetAttribute("Coop"..key)==true then
			home.built[key]=true
			local addition=group(key,home.model)
			local center=home.center
			if key=="Garden" then
				block(addition,"Crew planter",center+V(-14*K,.4,8*K),V(7,.8,7),timber,WO,true)
				for row=-1,1 do for col=-1,1 do
					gem(addition,"Shared moonbloom",center+V(-14*K+col*2,1.5,8*K+row*2),V(.8,1.6,.8),mint,row*.5)
				end end
			elseif key=="Lanterns" then
				for _,offset in ipairs({V(-20,0,-8),V(20,0,-8),V(-18,0,16),V(18,0,16)}) do lamp(addition,center+offset*K) end
			else
				bridge(addition,center+V(0,0,-CREW_R+.5),center+V(0,0,-CREW_R-8))
				disk(addition,"Crew lookout",center+V(0,-.22,-CREW_R-13),7,.6,timber,WO,true)
				lamp(addition,center+V(-5,0,-CREW_R-13)) lamp(addition,center+V(5,0,-CREW_R-13))
			end
		end
	end
	-- Homestead level pennants and shared worker posts (co-op progression).
	-- Both only grow: crew XP never falls and slots never close.
	local center=home.center
	local level=player:GetAttribute("CoopLevel")
	home.level=home.level or 1
	while type(level)=="number" and home.level<math.min(level,6) do
		home.level+=1
		local x=(-15+(home.level-2)*7.5)*K
		local pennant=group("Pennant"..home.level,home.model)
		block(pennant,"Crew pennant pole",center+V(x,3,20*K),V(.4,6,.4),timber,WO,true)
		local cloth=block(pennant,"Crew pennant",center+V(x+.9,5.2,20*K),V(1.6,1,.12),mint,Enum.Material.Fabric,false)
		meshSlot(cloth,"Banner",mint,.6)
	end
	local workers=player:GetAttribute("CoopWorkers")
	home.workers=home.workers or 0
	while type(workers)=="number" and home.workers<math.min(workers,2) do
		home.workers+=1
		local side=if home.workers==1 then -1 else 1
		local post=group("SharedWorker"..home.workers,home.model)
		block(post,"Shared worker hut",center+V(side*20*K,1.5,-14*K),V(4,3,4),timber,WO,true)
		block(post,"Shared worker roof",center+V(side*20*K,3.4,-14*K),V(5,.6,5),shale,WO,true)
		lamp(post,center+V(side*20*K,0,-11*K))
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
	for _,attribute in ipairs({"CoopId","CoopPreview","CoopGarden","CoopLanterns","CoopDeck","CoopLevel","CoopWorkers"}) do
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
local function regionIsle(id,name,pos,r,opts)
	opts=opts or {}
	opts.region=id
	return island(name,pos,r,opts)
end
local function nodeLabel(id) return Resource[id].def.name.." (Lv "..Resource[id].def.level..")" end
-- The original public nodes adopt the tiered "<Name> (Lv N)" labels.
for _,q in ipairs(islandsFolder:GetDescendants()) do
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
	if r.skill=="Fishing" then q.HoldDuration=FISH_HOLD end
	if region then q:SetAttribute("IsleRegion",region) end
	target:SetAttribute("ResourceId",id)
	return q
end

-- Ore: a slate boulder split by a metal vein, crowned by a crystal cluster.
local function oreNode(parent,pos,id,region,scale)
	local r,s=Resource[id],scale or 1
	local m=group(r.def.name.." vein",parent)
	local base=part(m,"Ore boulder",V(4.4,2.3,3.8)*s,CFrame.new(pos+V(0,1.05*s,0))*CFrame.Angles(0,r.index,.08),darken(shale,.3),ST,false)
	meshSlot(base,"OreVein",r.color,s,true)
	part(m,"Ore vein",V(4.6,.35,.55)*s,CFrame.new(pos+V(0,1.4*s,0))*CFrame.Angles(.35,r.index,.4),r.color,MT,false)
	local glowing=r.index>=5
	local top
	for i=1,3 do
		local a=r.index+i*2.1
		local h=(2+i*.8)*s
		local shard=gem(m,"Crystal shard",pos+V(math.cos(a)*1.1*s,1.9*s+h*.3,math.sin(a)*1.1*s),V(.9+i*.2,h,.9+i*.2)*s,i==1 and lighten(r.color,.25) or r.color,a)
		top=shard
	end
	if glowing then light(top,r.color,.8,14) end
	gatherPrompt(base,id,region)
	return m
end

-- Trees: one silhouette per log tier. The prompt sits on the root collar.
local function pagodaPine(parent,pos,color,scale,name)
	local m=group(name or "Towering windpine",parent)
	local s=scale or 1
	local trunk=disk(m,"Pine trunk",pos+V(0,10*s,0),.9*s,20*s,darken(timber,.25),WO,true)
	meshSlot(trunk,"WindpineTree",color,s,true)
	local tiers={{9,2.2,8},{7.4,2,11.5},{5.6,1.8,14.8},{3.6,1.6,17.8},{1.6,2,20.2}}
	for i,t in ipairs(tiers) do
		part(m,"Needle tier",V(t[1],t[2],t[1])*s,CFrame.new(pos+V(0,t[3]*s,0))*CFrame.Angles(0,i%2*math.pi/4,0),i%2==0 and lighten(color,.12) or darken(color,.15),LEAF,false)
	end
	return m,trunk
end
local function treeNode(parent,pos,id,region)
	local r=Resource[id]
	local col=r.color
	local m,collar
	if id=="WindpineLog" then
		local trunk
		m,trunk=pagodaPine(parent,pos,col,1.15,r.def.name.." tree")
		collar=disk(m,"Root collar",pos+V(0,.6,0),1.6,1.2,timber,WO,false)
	elseif id=="EmberoakLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.6,0),2.2,1.2,darken(timber,.2),WO,false)
		local trunk=disk(m,"Emberoak trunk",pos+V(0,5,0),1.4,10,darken(col,.45),WO,true)
		meshSlot(trunk,"EmberoakTree",col,1,true)
		beam(m,"Bough",pos+V(0,7,0),pos+V(3.5,10,1),.8,darken(col,.45),WO)
		beam(m,"Bough",pos+V(0,6.5,0),pos+V(-3,9.5,-1.5),.8,darken(col,.45),WO)
		ball(m,"Ember canopy",pos+V(0,12,0),9,col,LEAF)
		ball(m,"Ember canopy",pos+V(3.4,10.6,1.2),6.5,lighten(col,.15),LEAF)
		ball(m,"Ember canopy",pos+V(-3,10.3,-1.4),6,darken(col,.1),LEAF)
		local ember=ball(m,"Glowing ember",pos+V(1.5,8.4,-2.6),.8,C("FFB25C"),NE)
		light(ember,C("FF9A52"),.7,12,{lift=1})
	elseif id=="GlimmerbarkLog" then
		m=group(r.def.name.." tree",parent)
		for i=1,3 do
			local a=i*2*math.pi/3
			beam(m,"Stilt root",pos+V(math.cos(a)*3,0,math.sin(a)*3),pos+V(0,3.5,0),.55,lighten(col,.35),WO)
		end
		collar=disk(m,"Root collar",pos+V(0,.3,0),1.4,.6,lighten(col,.3),WO,false)
		local trunk=disk(m,"Glimmer trunk",pos+V(0,7.3,0),.75,8,lighten(col,.45),GL,true)
		meshSlot(trunk,"GlimmerbarkTree",col,1,true)
		local crown=disk(m,"Glimmer crown",pos+V(0,11.6,0),4.8,1.3,col,GL,false)
		disk(m,"Glimmer underglow",pos+V(0,10.85,0),3.6,.25,lighten(col,.2),SM,false)
		disk(m,"Glimmer crest",pos+V(0,12.8,0),3,1,lighten(col,.25),GL,false)
		light(crown,col,.8,16,{lift=-2})
	elseif id=="StarwoodLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.6,0),1.6,1.2,darken(col,.3),WO,false)
		local trunk=disk(m,"Starwood trunk",pos+V(0,6.5,0),1,13,darken(col,.2),WO,true)
		meshSlot(trunk,"StarwoodTree",col,1,true)
		ball(m,"Night canopy",pos+V(0,13,0),7,col,LEAF)
		ball(m,"Night canopy",pos+V(0,16.5,0),5,lighten(col,.12),LEAF)
		for i=1,4 do
			local a=i*math.pi/2+.4
			part(m,"Star bud",V(.8,.8,.8),CFrame.new(pos+V(math.cos(a)*3.3,13.5+i%2*2,math.sin(a)*3.3))*CFrame.Angles(math.pi/4,a,math.pi/4),i%2==0 and cream or C("CFE3FF"),NE,false)
		end
		light(collar,C("BFD7FF"),.6,12,{lift=3})
	elseif id=="AetherheartLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.7,0),4.4,1.4,darken(col,.55),WO,false)
		local trunk=disk(m,"Aetherheart trunk",pos+V(0,12,0),3,24,darken(col,.5),WO,true)
		meshSlot(trunk,"AetherheartTree",col,1,true)
		for i=1,4 do
			local a=i*math.pi/2+.3
			part(m,"Root flare",V(1.6,3,6),CFrame.new(pos+V(math.cos(a)*3.6,1,math.sin(a)*3.6))*CFrame.Angles(0,-a+math.pi/2,0)*CFrame.Angles(.35,0,0),darken(col,.5),WO,false)
		end
		ball(m,"Golden canopy",pos+V(0,27,0),16,col,LEAF)
		ball(m,"Golden canopy",pos+V(6,24,3),11,lighten(col,.2),LEAF)
		ball(m,"Golden canopy",pos+V(-6,24.5,-2),12,darken(col,.08),LEAF)
		ball(m,"Golden canopy",pos+V(1,23.5,-6.5),10,lighten(col,.1),LEAF)
		local core=ball(m,"Aetherheart core",pos+V(3.4,19.5,0),2.2,C("FFF6C8"),NE)
		-- Hero light (shadows): the Aetherheart.
		light(core,C("FFE9A8"),1,34,{shadows=true,lift=0})
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

-- Fishing: a pool and a bobber, reached by a short plank pier. Ripples are
-- separated by 0.04 studs (the old 0.01 steps z-fought at range).
local function fishSpot(parent,pos,id,region,dir,pierLen,poolRadius)
	local r=Resource[id]
	local m=group(r.def.name.." fishing spot",parent)
	if poolRadius then
		disk(m,"Pool bed",pos+V(0,.06,0),poolRadius,.12,darken(teal,.5),GR,false)
		local water=disk(m,"Fishing water",pos+V(0,.17,0),poolRadius-.15,.1,teal:Lerp(r.color,.3),GL,false)
		water.Transparency=.3
	end
	for i=1,2 do
		disk(m,"Ripple",pos+V(math.cos(i*2.1)*.9,.26+i*.04,math.sin(i*2.1)*.9),.4+i*.4,.03,lighten(r.color,.35+i*.12),SM,false)
	end
	ball(m,"Bobber",pos+V(.4,.5,.2),.75,r.color,SM)
	ball(m,"Bobber cap",pos+V(.4,.95,.2),.42,cream,SM)
	dir=(dir or V(0,0,1)).Unit
	pierLen=pierLen or 6
	local near,far=pos+dir*1.6,pos+dir*(1.6+pierLen)
	local pier=part(m,"Fishing pier",V(3,.4,pierLen),CFrame.lookAt((near+far)/2+V(0,.55,0),far+V(0,.55,0)),timber,WO,true)
	meshSlot(pier,"FishingPier",nil,pierLen/6,true)
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
	meshSlot(bed,"CropBed",col,1,true)
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
			gem(m,"Moonbloom",p+V(0,.8,0),V(.8,1.2,.8),i%2==0 and lighten(col,.2) or col,i*.6)
		elseif id=="Starfruit" then
			ball(m,"Starfruit bush",p+V(0,.7,0),1.5,C("4F7A4A"),LEAF)
			part(m,"Starfruit",V(.55,.55,.55),CFrame.new(p+V(.2,1.45,0))*CFrame.Angles(math.pi/4,i,math.pi/4),col,SM,false)
		elseif wet then
			disk(m,"Lily pad",p+V(0,.05,0),.8,.08,C("5E9C62"),SM,false)
			gem(m,"Lotus bloom",p+V(0,.45,0),V(.6,.7,.6),i%2==0 and lighten(col,.25) or col,i)
		else
			ball(m,"Herb tuft",p+V(0,.45,0),.9,i%2==0 and lighten(col,.15) or col,LEAF)
		end
	end
	if r.index>=4 then light(bed,col,.5,10,{lift=2}) end
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
local function station(parent,kind,pos,toward,place,waypoint,hero)
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
		light(coals,C("FF9A52"),.9,16,{shadows=hero==true,lift=1})
	elseif kind=="Hearth" then
		target=disk(m,"Hearth ring",pos+V(0,.4,0),2.7,.8,rock,ST,true)
		local embers=disk(m,"Hearth embers",pos+V(0,.86,0),1.8,.12,C("FF8A3D"),NE,false)
		disk(m,"Stew pot",pos+V(0,2,0),1.15,1.4,ink,MT,false)
		disk(m,"Stew",pos+V(0,2.72,0),.95,.06,C("D9A15B"),SM,false)
		for _,s in ipairs({-1,1}) do part(m,"Spit post",V(.3,3.6,.3),at(cf,s*2.4,1.8,0),timber,WO,false) end
		part(m,"Spit bar",V(5,.25,.25),at(cf,0,3.5,0),brass,MT,false)
		part(m,"Prep table",V(3,1.2,1.6),at(cf,0,.6,-3.6),timber,WO,true)
		light(embers,C("FFB066"),.8,12,{lift=3.6})
	elseif kind=="Cauldron" then
		for i=1,3 do
			local a=i*2*math.pi/3
			block(m,"Cauldron leg",pos+V(math.cos(a)*1.4,.5,math.sin(a)*1.4),V(.4,1,.4),ink,MT,false)
		end
		target=ball(m,"Cauldron bowl",pos+V(0,2,0),4,darken(navy,.3),MT)
		target.CanCollide=true
		local brew=disk(m,"Bubbling brew",pos+V(0,3.55,0),1.55,.12,mint,NE,false)
		ball(m,"Brew bubble",pos+V(.6,3.75,.3),.5,lighten(mint,.3),SM)
		part(m,"Reagent shelf",V(4,.3,1.2),at(cf,0,2.6,3.2),timber,WO,false)
		for i,colr in ipairs({rose,brass,teal}) do
			disk(m,"Reagent bottle",at(cf,(i-2)*1.2,3.25,3.2).Position,.3,1,colr,GL,false)
		end
		light(brew,mint,.7,12,{lift=1.5})
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
	meshSlot(target,kind,nil,1,true)
	stationPrompt(target,kind,place)
	anchor(parent,"Waypoint_"..(waypoint or kind),at(cf,0,0,-6)*CFrame.Angles(0,math.pi,0))
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
local function beaconProp(parent,pos,accent,withLight)
	block(parent,"Beacon plinth",pos+V(0,.4,0),V(3.4,.8,3.4),ink,ST,true)
	local post=block(parent,"Warp beacon",pos+V(0,2.8,0),V(1.6,4,1.6),accent,GL,false)
	meshSlot(post,"WarpBeacon",accent,1)
	for _,x in ipairs({-1.3,1.3}) do gem(parent,"Beacon fin",pos+V(x,2.6,0),V(.5,3.6,.5),brass,0) end
	local cap=part(parent,"Beacon flame",V(.9,.9,.9),CFrame.new(pos+V(0,5.3,0))*CFrame.Angles(math.pi/4,0,math.pi/4),accent,NE,false)
	if withLight~=false then light(cap,accent,.7,12) end
	return post
end
local GT,GT_R=V(0,0,232),75
local SKYWAY_LANDING=GT+V(0,4,30)
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
local function regionWarp(parent,pos,regionId,destination,waypoint,withLight)
	local region=Data.RegionById[regionId]
	assert(region,"unknown region "..tostring(regionId))
	local post=beaconProp(parent,pos,REGION_ACCENT[regionId] or mint,withLight)
	local q=prompt(post,"Travel to "..region.name,requirementText(region))
	q:SetAttribute("IsleWarpRegion",regionId)
	q.Triggered:Connect(function(player) regionTravel(player,post,regionId,destination) end)
	anchor(parent,waypoint or ("Waypoint_Skyway_"..regionId),pos+V(0,0,-5),pos)
	return post
end
local function returnWarp(parent,pos,label,regionId)
	local post=beaconProp(parent,pos,mint)
	local q=prompt(post,"Return to the Skyway",label)
	q:SetAttribute("IsleWarpReturn","Hub")
	q.Triggered:Connect(function(player) warp(player,post,SKYWAY_LANDING) end)
	anchor(parent,"Waypoint_Return_"..regionId,pos+V(0,0,-5),pos)
	return post
end

-- Static ledger boards; rows are named so live data can be written later.
local function ledger(parent,name,pos,toward,title,kicker,rows,accent,width,height)
	local cf=facing(pos+V(0,height/2+1.6,0),toward)
	for _,s in ipairs({-1,1}) do part(parent,"Ledger post",V(.35,height+1.8,.35),cf*CFrame.new(s*(width/2+.1),-.7,0),brass,MT,false) end
	local board=part(parent,name,V(width,height,.35),cf,ink,SM,false)
	meshSlot(board,"Signboard",accent,width/12)
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
local terrace=regionIsle("Hub","Guild Terrace",GT,GT_R,{top=C("A7B08A"),vein=brass,gaps={-HALF}})
bridge(hub,V(0,0,HUB_R),GT-V(0,0,GT_R))
anchor(hub,"Waypoint_Bridge_GuildTerrace",V(0,0,HUB_R-6),GT)
do
path(terrace,GT-V(0,0,GT_R-2),GT-V(0,0,20),10)
disk(terrace,"Guild court",GT+V(0,.02,0),20,.26,navy,ST,true)
disk(terrace,"Guild seal",GT+V(0,.2,0),3,.3,brass,MT,false)
for i=1,6 do
	local a=i*math.pi/3
	local d=V(math.cos(a),0,math.sin(a))
	beam(terrace,"Seal inlay",GT+d*4+V(0,.2,0),GT+d*18+V(0,.2,0),.3,brass,MT)
end
sign(terrace,GT+V(12,0,-62),"Guild Terrace","COMPASS QUAY   /   GUILDS + SKYWAY",brass,0,11)
for i,deg in ipairs({230,205,180,155}) do
	local a=math.rad(deg)
	local kind=({"Forge","Hearth","Cauldron","Workbench"})[i]
	station(terrace,kind,GT+V(math.cos(a)*44,0,math.sin(a)*44),GT,"Guild Terrace",nil,kind=="Forge")
end
sign(terrace,GT+V(-30,0,-48),"Artisans' Row","SMITH · COOK · BREW · CRAFT",rose,-40,8)
-- Guild Hall pavilion (east side).
local hall=group("Guild Hall",terrace)
local HALL=GT+V(40,0,0)
block(hall,"Hall floor",HALL+V(0,.25,0),V(22,.5,50),darken(navy,.1),WO,true)
for _,x in ipairs({-10,10}) do for _,z in ipairs({-22,0,22}) do
	local col=block(hall,"Hall column",HALL+V(x,8,z),V(1.6,16,1.6),cream,ST,false)
	if z==0 then meshSlot(col,"Column",nil,2) end
	block(hall,"Column capital",HALL+V(x,16.3,z),V(2.4,.6,2.4),brass,MT,false)
end end
part(hall,"Hall roof",V(13,.6,52),CFrame.new(HALL+V(-5.6,18.3,0))*CFrame.Angles(0,0,math.rad(20)),navy,SM,false)
part(hall,"Hall roof",V(13,.6,52),CFrame.new(HALL+V(5.6,18.3,0))*CFrame.Angles(0,0,math.rad(-20)),navy,SM,false)
block(hall,"Ridge beam",HALL+V(0,20.5,0),V(.9,.9,52),brass,MT,false)
local skillRows={}
for _,skill in ipairs(Data.SkillOrder) do table.insert(skillRows,{skill,"Unclaimed  ·  Lv 99",key=skill}) end
ledger(hall,"Skill Leaderboard",HALL+V(6,.5,-14),GT,"Hall of Mastery","GUILD LEDGER   /   FIRST TO LEVEL 99",skillRows,brass,9,8.5)
anchor(hall,"Waypoint_HallOfMastery",HALL+V(-2,0,-14),HALL+V(6,0,-14))
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
ledger(hall,"Bestiary",HALL+V(6,.5,14),GT,"Bestiary","KNOWN CREATURES   /   BY LEVEL",beastRows,rose,9,8.5)
-- Slayer master: a sentinel statue that takes contracts for the three hunts.
local pedestal=block(hall,"Slayer master pedestal",HALL+V(-7,1.5,0),V(4,2.5,4),rock,ST,true)
block(hall,"Pedestal trim",HALL+V(-7,2.85,0),V(4.4,.3,4.4),brass,MT,false)
local master=sculpture(hall,"Huntmaster Oriel",HALL+V(-7,6,0),"ObservatorySentinel",1.5,-90)
light(master,C("FFD9A0"),.5,10,{lift=4})
stationPrompt(pedestal,"Slayer","Huntmaster Oriel")
anchor(hall,"NPC_Slayer",HALL+V(-11,.5,-5),GT)
anchor(hall,"Waypoint_SlayerMaster",HALL+V(-15,0,0),HALL+V(-7,0,0))
for i,line in ipairs(Data.SlayerOrder) do
	local def=Data.Slayers[line]
	-- Pennants on the ridge give the hall a silhouette from across the quay.
	local z=-16+(i-1)*16
	block(hall,"Pennant pole",HALL+V(0,23,z),V(.25,4,.25),brass,MT,false)
	local pennant=block(hall,def.name.." pennant",HALL+V(0,23.6,z+1.4),V(.15,2,2.6),C(def.color),Enum.Material.Fabric,false)
	meshSlot(pennant,"Banner",C(def.color),1)
end
sign(hall,HALL+V(-16,0,-10),"Huntmaster Oriel","SLAYER   /   BRAMBLE · GLOOM · TEMPEST",rose,90,8)
-- The Skyway: gated beacons to the four depth regions (built below).
block(terrace,"Skyway dais",GT+V(0,.15,52),V(64,.3,10),navy,ST,true)
for _,o in ipairs({V(-14,0,-56),V(14,0,-40),V(-22,0,30),V(22,0,30),V(56,0,-34),V(56,0,34)}) do lamp(terrace,GT+o) end
for i,o in ipairs({V(-58,0,-20),V(-54,0,30),V(-34,0,58),V(34,0,58),V(60,0,46),V(62,0,-44),V(-40,0,-56),V(30,0,-60)}) do
	decorTree(terrace,GT+o,1+hash(i,5)*.3,if i%3==0 then "Pine" else "Meadow")
end
local herbRise,herbTop=tier(terrace,"Herb garden rise",GT+V(-46,0,-30),8,2,{top=C("8DB86E")})
flowers(herbRise,GT+V(-46,herbTop,-30),4,C("C9A0DC"),.08)
for i,o in ipairs({V(-22,0,-24),V(22,0,-24),V(-10,0,40),V(14,0,-34)}) do flowers(terrace,GT+o,2.6,({rose,cream,C("C9A0DC")})[i%3+1],.06+i*.012) end

end
-------------------------------------------------------------------------------
-- Meadow Reach (Meadow): open hills south of Mosswake Grove.
-------------------------------------------------------------------------------
do
local MR,MR_R=V(-230,0,185),70
local meadow=regionIsle("Meadow","Meadow Reach",MR,MR_R,{top=C("8DB86E"),gaps={-HALF}})
bridge(meadow,G+V(0,0,GR_R),MR-V(0,0,MR_R))
anchor(grove,"Waypoint_Bridge_MeadowReach",G+V(0,0,GR_R-6),MR)
anchor(meadow,"Waypoint_Entrance_Meadow",MR-V(0,0,MR_R-6),MR)
path(meadow,MR-V(0,0,MR_R-2),MR+V(0,0,-10),8)
for _,h in ipairs({{V(38,-12,-32),30},{V(-40,-11,30),28}}) do
	part(meadow,"Grassy hillock",V(h[2],h[2],h[2]),CFrame.new(MR+h[1]),C("86AE69"),Enum.Material.Grass,true,BALL)
end
sign(meadow,MR+V(12,0,-58),"Meadow Reach","MEADOW   /   BOARS · SUNWHEAT · GLASSFIN",mint,0,11)
cropPatch(meadow,MR+V(-30,0,-30),"Sunwheat")
cropPatch(meadow,MR+V(-30,0,-18),"Sunwheat")
cropPatch(meadow,MR+V(-44,0,-24),"Herb")
treeNode(meadow,MR+V(36,0,28),"Timber")
fishSpot(meadow,MR+V(16,0,-4),"Fish",nil,V(1,0,.4),5,10)
fishSpot(meadow,MR+V(12,0,-10),"Glassfin",nil,V(-.6,0,-1),6)
for _,o in ipairs({V(-14,0,-46),V(-16,0,20)}) do lamp(meadow,MR+o) end
for i=1,6 do
	local a=math.rad(150+i*14)
	local p=MR+V(-30,1+i%2*.08,-24)+V(math.cos(a)*22,0,math.sin(a)*22)
	part(meadow,"Fence rail",V(.3,.3,6),CFrame.lookAt(p,p+V(-math.sin(a),0,math.cos(a))),timber,WO,false)
	block(meadow,"Fence post",p-V(0,.4,0),V(.4,2,.4),darken(timber,.3),WO,false)
end
tier(meadow,"Sunny rise",MR+V(52,0,6),10,3,{top=C("93BE72")})
decorTree(meadow,MR+V(53,3,7),1.2,"Meadow",C("A0B860"))
for i,o in ipairs({V(-56,0,-2),V(-12,0,58),V(26,0,54),V(54,0,30),V(-52,0,-40),V(30,0,-52),V(-30,0,48)}) do
	decorTree(meadow,MR+o,1+hash(i,6)*.4)
end
for i,o in ipairs({V(-58,0,12),V(48,0,-50)}) do outcrop(meadow,MR+o,1.1,i) end
for i,o in ipairs({V(-20,0,30),V(20,0,20),V(-50,0,-10),V(40,0,10)}) do flowers(meadow,MR+o,3.2,({rose,cream,C("E8C35A"),C("C9A0DC")})[i],.06+i*.012) end
spawnMarker("BramblebackBoar",MR+V(0,0,36),3,9)
spawnMarker("Thornling",MR+V(4,0,-36),3,7)

end
-------------------------------------------------------------------------------
-- Cinder Shelf (Quarry): a lower terrace below Brassfall Quarry.
-------------------------------------------------------------------------------
local CS,CS_R=V(230,-6,-185),58
local shelf=regionIsle("Quarry","Cinder Shelf",CS,CS_R,{top=C("8F8676"),stone=darken(rock,.15),vein=C("FF9A52"),ground=GR,gaps={HALF}})
bridge(shelf,Q-V(0,0,Q_R),CS+V(0,0,CS_R))
anchor(mine,"Waypoint_Bridge_CinderShelf",Q-V(0,0,Q_R-6),CS)
anchor(shelf,"Waypoint_Entrance_CinderShelf",CS+V(0,0,CS_R-6),CS)
for i=1,4 do
	local a=i*1.6
	local p=CS+V(math.cos(a)*24,.06,math.sin(a)*24)
	local vent=part(shelf,"Cinder vent",V(.5,.12,6),CFrame.new(p)*CFrame.Angles(0,a,0),C("FF7A3D"),NE,false)
	if i==2 then light(vent,C("FF8A3D"),.7,14,{lift=1.5}) motes(vent,C("FFB066"),4,2,.25) end
end
tier(shelf,"Basalt shelf",CS+V(30,0,-34),10,4,{cliff=C("3E3A38"),top=C("7A6F62"),ground=GR})
sign(shelf,CS+V(-14,0,44),"Cinder Shelf","QUARRY   /   BRASSITE · CRAWLERS",brass,0,10)
oreNode(shelf,CS+V(-26,0,-18),"Brassite")
oreNode(shelf,CS+V(26,0,-14),"Brassite")
oreNode(shelf,CS+V(28,0,18),"Ore")
for i,o in ipairs({V(-36,0,20),V(40,0,-2)}) do outcrop(shelf,CS+o,1,i) end
lamp(shelf,CS+V(8,0,40))
spawnMarker("ShaleCrawler",CS+V(-16,0,12),3,7)
spawnMarker("CinderMite",CS+V(8,0,-22),3,6)
-- Brassfall Quarry gains a second copper seam below the bench.
oreNode(mine,Q+V(-34,0,-34),"Ore")
-- Skyreach: a sunsteel outcrop and the summit's guardians.
oreNode(skyreach,SR+V(6,0,40),"SunsteelOre","Skyreach")
-- Markers keep >= 40 studs (flat) from every warp landing; see verify-world.
spawnMarker("BrassGolem",SR+V(38,0,30),2,6)
spawnMarker("StormHarrier",SR+V(40,0,-26),2,6)

-------------------------------------------------------------------------------
local WP,WP_R=V(-500,24,-160),85
local GH,GH_R=V(440,-16,-440),82
local TW,TW_R=V(-520,2,440),92
local TS,TS_R=V(600,80,-220),70
do
-- Windpine Grove: towering pines, an emberoak hollow and the Aetherheart.
-------------------------------------------------------------------------------
local grovewild=regionIsle("Windpine","Windpine Grove",WP,WP_R,{top=C("5F8A57"),stone=C("3F4B44"),stratum=C("5E6B5C"),vein=C("9BD18B")})
for _,deg in ipairs({150,200,228,270,335,20}) do
	local a=math.rad(deg)
	pagodaPine(grovewild,WP+V(math.cos(a)*66,0,math.sin(a)*66),C("4E7A4A"),1.7+(deg%3)*.15)
end
treeNode(grovewild,WP+V(0,0,-12),"AetherheartLog","Windpine")
treeNode(grovewild,WP+V(-46,0,-28),"WindpineLog","Windpine")
treeNode(grovewild,WP+V(-20,0,-56),"WindpineLog","Windpine")
treeNode(grovewild,WP+V(-56,0,4),"WindpineLog","Windpine")
treeNode(grovewild,WP+V(36,0,-40),"EmberoakLog","Windpine")
treeNode(grovewild,WP+V(56,0,-12),"EmberoakLog","Windpine")
local emberGlow=hidden(grovewild,"Ember hollow glow",WP+V(46,4,-26))
emberGlow.CanQuery,emberGlow.CastShadow=false,false
motes(emberGlow,C("FFB25C"),5,1.5,.2)
cropPatch(grovewild,WP+V(-30,0,50),"Glowcap","Windpine")
for _,b in ipairs({{V(-14,0,18),3},{V(22,0,18),2.4},{V(-62,0,-44),2.8}}) do
	local boulder=part(grovewild,"Mossy boulder",V(b[2]*1.4,b[2],b[2]*1.2),CFrame.new(WP+b[1]+V(0,b[2]*.35,0))*CFrame.Angles(0,b[2],.1),C("6E7B68"),ST,false)
	meshSlot(boulder,"Rock",C("6E7B68"),b[2]/2)
end
part(grovewild,"Fallen windpine",V(16,1.8,1.8),CFrame.new(WP+V(4,.9,32))*CFrame.Angles(0,.6,0),darken(timber,.3),WO,false).Shape=Enum.PartType.Cylinder
local mound,moundTop=tier(grovewild,"Root mound",WP+V(30,0,0),10,2.5,{cliff=C("4B4136"),top=C("5F8A57")})
for i=1,4 do
	local p=WP+V(30,0,0)+V(math.cos(i*1.6)*5,moundTop-WP.Y,math.sin(i*1.6)*5)
	disk(mound,"Mushroom stalk",p+V(0,.5,0),.2,1,cream,SM,false)
	disk(mound,"Mushroom cap",p+V(0,1.1,0),.8,.3,C("C9A0DC"),SM,false)
end
-- Woodcutters' lodge sheltering a workbench.
local lodge=group("Woodcutters' Lodge",grovewild)
local LP=WP+V(40,0,38)
block(lodge,"Lodge floor",LP+V(0,.2,0),V(11,.4,8),timber,WO,true)
block(lodge,"Lodge back wall",LP+V(0,3.5,3.8),V(11,6.6,.5),darken(timber,.2),WO,true)
for _,x in ipairs({-5.3,5.3}) do block(lodge,"Lodge post",LP+V(x,3.3,-3.6),V(.6,6.2,.6),darken(timber,.35),WO,false) end
part(lodge,"Lodge roof",V(12.5,.5,9.4),CFrame.new(LP+V(0,7.2,0))*CFrame.Angles(math.rad(-14),0,0),C("4E6B47"),WO,false)
station(lodge,"Workbench",LP+V(0,.4,0),LP+V(0,0,-10),"Windpine Lodge","Workbench_Windpine")
sign(grovewild,WP+V(-18,0,70),"Windpine Grove",requirementText(Data.RegionById.Windpine),REGION_ACCENT.Windpine,0,10)
returnWarp(grovewild,WP+V(10,0,72),"Windpine Grove","Windpine")
anchor(grovewild,"Waypoint_Entrance_Windpine",WP+V(0,0,58),WP)
for i,o in ipairs({V(-10,0,46),V(24,0,56),V(-60,0,30),V(60,0,20)}) do decorTree(grovewild,WP+o,1.2,"Pine",C("4E7A4A")) end
for _,o in ipairs({V(-12,0,60),V(20,0,44)}) do lamp(grovewild,WP+o) end
spawnMarker("BarkStalker",WP+V(-34,0,-40),3,8)
spawnMarker("GaleSprite",WP+V(16,0,-56),3,7)

end
do
-------------------------------------------------------------------------------
-- Gloomhollow Caverns: a roofed grotto lit only by voidstone and moonbloom.
-------------------------------------------------------------------------------
local void=C("7B5CC4")
local gloom=regionIsle("Gloomhollow","Gloomhollow Caverns",GH,GH_R,{top=C("3A3F52"),stone=C("2B2F3D"),stratum=C("424659"),vein=void,ground=ST})
local CAVE_R,CAVE_H=56,28
local cave=group("Grotto",gloom)
local segments=24
for i=0,segments-1 do
	local a=(i+.5)*2*math.pi/segments
	if math.abs(math.atan2(math.sin(a-HALF),math.cos(a-HALF)))>math.rad(25) then
		local radial=V(math.cos(a),0,math.sin(a))
		local h=CAVE_H+(i%3)*1.5
		local p=GH+radial*CAVE_R+V(0,h/2,0)
		local wall=part(cave,"Cavern wall",V(2*CAVE_R*math.sin(math.pi/segments)+1,h,4),CFrame.lookAt(p,p+radial),i%2==0 and C("2F3342") or C("383D4E"),ST,true)
		if i%6==0 then meshSlot(wall,"CliffRock",nil,3) end
	end
end
disk(cave,"Cavern roof",GH+V(0,CAVE_H+1.6,0),CAVE_R+2.4,3.2,C("2B2F3D"),ST,true)
for i=1,8 do
	local a=i*.8
	local p=GH+V(math.cos(a)*(12+i*4.5),CAVE_H+5+i%3*2.5,math.sin(a)*(12+i*4.5))
	part(cave,"Roof crag",V(8+i%3*2,10+i%4*3,8),CFrame.new(p)*CFrame.Angles(.25*(i%2*2-1),a,.2),i%2==0 and C("2F3342") or C("424659"),ST,false)
end
for i=1,6 do
	local a=i*1.05+.5
	local s=part(cave,"Stalactite",V(1.8,7,1.8),CFrame.new(GH+V(math.cos(a)*28,CAVE_H-3.5,math.sin(a)*28)),C("424659"),ST,false)
	if i%3==0 then
		ball(cave,"Stalactite glow",GH+V(math.cos(a)*28,CAVE_H-7.3,math.sin(a)*28),1,void,NE)
		meshSlot(s,"Stalactite")
	end
end
local heartCrystal=gem(cave,"Grotto heart crystal",GH+V(0,5,-14),V(4,10,4),void,.3)
heartCrystal.Material=NE
-- Hero light (shadows): the grotto heart.
light(heartCrystal,void,1.3,40,{shadows=true,lift=6})
meshSlot(heartCrystal,"AetherCrystal",void,2.5)
gem(cave,"Grotto heart shard",GH+V(3,3,-11),V(2,5.5,2),lighten(void,.3),1.2)
motes(heartCrystal,lighten(void,.3),4,.8,.3)
oreNode(cave,GH+V(-32,0,-24),"Voidstone","Gloomhollow")
oreNode(cave,GH+V(28,0,-30),"Voidstone","Gloomhollow")
oreNode(cave,GH+V(0,0,-44),"Voidstone","Gloomhollow")
oreNode(cave,GH+V(40,0,4),"Prismite","Gloomhollow",1.3)
fishSpot(cave,GH+V(-32,0,18),"AbyssKoi","Gloomhollow",V(1,0,.3),6,9)
cropPatch(cave,GH+V(28,0,28),"Moonbloom","Gloomhollow")
for i=1,5 do
	local p=GH+V(math.cos(i*1.25+.3)*44,0,math.sin(i*1.25+.3)*44)
	if p.Z<GH.Z+30 then
		disk(cave,"Glowshroom stalk",p+V(0,.6,0),.25,1.2,cream,SM,false)
		disk(cave,"Glowshroom cap",p+V(0,1.3,0),1,.35,lighten(void,.4),NE,false)
	end
end
spawnMarker("GloomfangSpider",GH+V(-16,0,-30),3,7)
spawnMarker("VoidWisp",GH+V(16,0,-24),2,7)
oreNode(gloom,GH+V(-40,0,62),"SunsteelOre","Gloomhollow")
station(gloom,"Forge",GH+V(32,0,64),GH,"Delvers' Forge","Forge_Gloomhollow")
sign(gloom,GH+V(-16,0,70),"Gloomhollow Caverns",requirementText(Data.RegionById.Gloomhollow),REGION_ACCENT.Gloomhollow,0,9)
returnWarp(gloom,GH+V(8,0,72),"Gloomhollow Caverns","Gloomhollow")
anchor(gloom,"Waypoint_Entrance_Gloomhollow",GH+V(0,0,62),GH)
for _,x in ipairs({-16,16}) do
	local torch=block(gloom,"Cave torch",GH+V(x,1.8,54),V(.5,3.6,.5),timber,WO,false)
	meshSlot(torch,"Torch",C("B59CFF"),1)
	light(ball(gloom,"Torch flame",GH+V(x,3.9,54),.7,C("B59CFF"),NE),C("B59CFF"),.7,14)
end
for i,o in ipairs({V(-56,0,58),V(-26,0,74)}) do outcrop(gloom,GH+o,1.2,i) end
tier(gloom,"Fungal ledge",GH+V(50,0,40),8,3,{cliff=C("2B2F3D"),top=C("3A3F52"),ground=ST})

end
do
-------------------------------------------------------------------------------
-- Tidewater Shoals: sandbars, two lagoons, piers and a lighthouse.
-------------------------------------------------------------------------------
local tide=regionIsle("Tidewater","Tidewater Shoals",TW,TW_R,{top=C("D9C9A0"),stone=C("6F7C86"),stratum=C("8D99A2"),vein=C("5EC8D8"),ground=SA,ledge=C("C9BC94")})
for _,l in ipairs({{V(-26,0,-13),24},{V(31,0,22),20}}) do
	disk(tide,"Lagoon deep",TW+l[1]+V(0,.06,0),l[2]*.6,.12,C("2E7F95"),GL,false)
	local w=disk(tide,"Lagoon",TW+l[1]+V(0,.11,0),l[2],.2,C("4FB3BF"),GL,false)
	w.Transparency=.25
end
fishSpot(tide,TW+V(-26,0,-24),"Stormeel","Tidewater",V(0,0,-1),12)
fishSpot(tide,TW+V(-38,0,-10),"Lanternray","Tidewater",V(-1,0,0),12)
fishSpot(tide,TW+V(36,0,22),"LeviathanScale","Tidewater",V(1,0,0),12)
fishSpot(tide,TW+V(30,0,32),"Stormeel","Tidewater",V(0,0,1),10)
treeNode(tide,TW+V(-50,0,18),"GlimmerbarkLog","Tidewater")
treeNode(tide,TW+V(2,0,-40),"GlimmerbarkLog","Tidewater")
cropPatch(tide,TW+V(64,0,-10),"AetherLotus","Tidewater")
local galley=group("Shoals Galley",tide)
block(galley,"Galley boardwalk",TW+V(46,.2,-46),V(12,.4,9),timber,WO,true)
for _,x in ipairs({-5.5,5.5}) do for _,z in ipairs({-4,4}) do
	block(galley,"Boardwalk piling",TW+V(46+x,.9,-46+z),V(.6,1.8,.6),darken(timber,.4),WO,false)
end end
station(galley,"Hearth",TW+V(46,.4,-46),TW,"Shoals Galley","Hearth_Tidewater")
local LH=TW+V(-60,0,50)
local tower=group("Shoals lighthouse",tide)
disk(tower,"Lighthouse footing",LH+V(0,1,0),3.4,2,rock,ST,true)
local shaft=disk(tower,"Lighthouse tower",LH+V(0,10,0),2.1,16,cream,SM,true)
meshSlot(shaft,"Lighthouse",rose,1,true)
for _,y in ipairs({6,12}) do disk(tower,"Tower stripe",LH+V(0,y,0),2.16,1.6,rose,SM,false) end
disk(tower,"Lantern room",LH+V(0,19.3,0),2.4,2.6,mint,GL,false).Transparency=.4
local lamphead=ball(tower,"Lighthouse flame",LH+V(0,19.3,0),1.4,C("FFF1B8"),NE)
disk(tower,"Lantern cap",LH+V(0,21,0),2.7,.7,brass,MT,false)
-- Hero light (shadows): the lighthouse lamp.
light(lamphead,C("FFF1B8"),1.2,48,{shadows=true,lift=0})
for _,r in ipairs({{V(70,0,30),3.4},{V(-4,0,74),2.6},{V(-72,0,-20),3},{V(14,0,-70),2.4}}) do
	local reef=part(tide,"Reef rock",V(r[2]*1.5,r[2],r[2]*1.2),CFrame.new(TW+r[1]+V(0,r[2]*.3,0))*CFrame.Angles(0,r[2],.12),C("7D8B92"),ST,false)
	meshSlot(reef,"Rock",C("7D8B92"),r[2]/2)
end
tier(tide,"Dune",TW+V(-62,0,-40),16,2.5,{cliff=C("BFAE84"),top=C("E2D3AA"),ground=SA})
for i,o in ipairs({V(-30,0,40),V(10,0,56),V(60,0,-34),V(-70,0,10),V(50,0,62),V(-40,0,-64),V(72,0,8)}) do
	decorTree(tide,TW+o,1.1+hash(i,3)*.3,"Palm")
end
local spray=hidden(tide,"Lagoon spray",TW+V(31,1,22))
spray.CanQuery,spray.CastShadow=false,false
motes(spray,C("CFEFFF"),3,1,.18)
sign(tide,TW+V(-20,0,-76),"Tidewater Shoals",requirementText(Data.RegionById.Tidewater),REGION_ACCENT.Tidewater,0,10)
returnWarp(tide,TW+V(8,0,-78),"Tidewater Shoals","Tidewater")
anchor(tide,"Waypoint_Entrance_Tidewater",TW+V(0,0,-64),TW)
lamp(tide,TW+V(-12,0,-66))
spawnMarker("ReefLurker",TW+V(-8,0,56),3,9)
spawnMarker("ReefLurker",TW+V(52,0,50),2,5)

end
do
-------------------------------------------------------------------------------
-- Tempest Spire: a storm-wracked summit ringed by arcing crystal pylons.
-------------------------------------------------------------------------------
local storm=C("BFD7FF")
local tempest=regionIsle("Tempest","Tempest Spire",TS,TS_R,{top=C("4A5266"),stone=C("2E3445"),stratum=C("3B4256"),vein=storm,ground=ST})
local spire=group("Storm spire",tempest)
local SP=TS+V(-10,0,-44)
local spireTiers={{V(13,18,12),9,.1},{V(10.5,18,9.75),25.5,-.15},{V(7.8,16.5,7.5),42,.2},{V(5.7,15,5.4),57,-.1},{V(3.6,13.5,3.6),70.5,.18}}
for i,t in ipairs(spireTiers) do
	local stone=part(spire,"Spire stone",t[1],CFrame.new(SP+V(i%2*.8,t[2],0))*CFrame.Angles(t[3]*.4,i*.5,t[3]),i%2==0 and C("2E3445") or C("3B4256"),ST,true)
	if i==1 then meshSlot(stone,"StormSpire",storm,1.5,true) end
end
local crown=gem(spire,"Storm crown",SP+V(0,81,0),V(3,9,3),storm,.4)
crown.Material=NE
-- Hero light (shadows): the storm crown.
light(crown,storm,1.3,48,{shadows=true,lift=6})
motes(crown,storm,6,4,.3)
local arcAnchors={}
for i=1,4 do
	local a=math.rad(45+90*(i-1))
	local p=TS+V(math.cos(a)*36,0,math.sin(a)*36)
	block(tempest,"Pylon footing",p+V(0,.5,0),V(3,1,3),ink,ST,true)
	local shaft=block(tempest,"Pylon shaft",p+V(0,4.5,0),V(1.2,7,1.2),C("3B4256"),MT,true)
	meshSlot(shaft,"StormPylon",storm,1)
	for _,s in ipairs({-1,1}) do gem(tempest,"Pylon brace",p+V(s*.9,3,0),V(.4,4,.4),brass,0) end
	local top=gem(tempest,"Pylon crystal",p+V(0,9.4,0),V(1.6,3.6,1.6),storm,a)
	top.Material=NE
	if i%2==1 then light(top,storm,.7,16) end
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
	arc.Width0,arc.Width1,arc.LightEmission,arc.FaceCamera,arc.Segments=.35,.35,.8,true,16
	arc.CurveSize0,arc.CurveSize1=12,-12
	arc.Parent=arcAnchors[i].Parent
end
-- Storm clouds: spaced so the translucent shells never overlap (overlapping
-- transparent spheres popped in sort order).
for i=1,6 do
	local a=i*2*math.pi/6
	local cloud=ball(tempest,"Storm cloud",TS+V(math.cos(a)*52,48+(i%3)*6,math.sin(a)*52),24+(i%3)*4,C("596274"),SM)
	cloud.Transparency,cloud.CastShadow=.2,false
end
oreNode(tempest,TS+V(-52,0,-8),"StarmetalOre","Tempest")
oreNode(tempest,TS+V(52,0,-4),"StarmetalOre","Tempest")
oreNode(tempest,TS+V(14,0,-46),"Celestium","Tempest",1.25)
treeNode(tempest,TS+V(-44,0,22),"StarwoodLog","Tempest")
cropPatch(tempest,TS+V(40,0,28),"Starfruit","Tempest")
for i,o in ipairs({V(-56,0,-36),V(56,0,-40),V(-24,0,52),V(30,0,54)}) do outcrop(tempest,TS+o,1.3,i) end
tier(tempest,"Basalt ledge",TS+V(46,0,-28),8,3,{cliff=C("2E3445"),top=C("4A5266"),ground=ST})
sign(tempest,TS+V(-16,0,54),"Tempest Spire",requirementText(Data.RegionById.Tempest),REGION_ACCENT.Tempest,0,10)
returnWarp(tempest,TS+V(10,0,54),"Tempest Spire","Tempest")
anchor(tempest,"Waypoint_Entrance_Tempest",TS+V(0,0,44),TS)
spawnMarker("TempestWraith",TS+V(30,0,-36),2,6)
spawnMarker("StarbornSentinel",TS+V(-32,0,-34),1,5)

end
-- Skyway beacons on the Guild Terrace, plus a deep descent from Cinder Shelf.
local destinations={
	Windpine=WP+V(0,4,58),Gloomhollow=GH+V(0,4,62),Tidewater=TW+V(0,4,-64),Tempest=TS+V(0,4,44),
}
for i,id in ipairs({"Windpine","Gloomhollow","Tidewater","Tempest"}) do
	local x=-24+(i-1)*16
	-- Only the outer pair carries a light: four glowing beacons in a row stacked.
	regionWarp(terrace,GT+V(x,.3,50),id,destinations[id],nil,i==1 or i==4)
	sign(terrace,GT+V(x,0,58),Data.RegionById[id].name,requirementText(Data.RegionById[id]),REGION_ACCENT[id],0,8)
end
anchor(terrace,"Waypoint_Skyway",SKYWAY_LANDING-V(0,4,0),GT+V(0,0,50))
regionWarp(shelf,CS+V(0,0,-40),"Gloomhollow",destinations.Gloomhollow,"Waypoint_DeepDescent")
sign(shelf,CS+V(12,0,-38),"Deep descent","GLOOMHOLLOW   /   "..requirementText(Data.RegionById.Gloomhollow),REGION_ACCENT.Gloomhollow,0,9)

-------------------------------------------------------------------------------
-- Builder's Terrace (Carpentry construction). Each home gains a small terrace
-- islet west of the landing with fixed hotspots (Data.Hotspots). The server
-- publishes Furniture<Hotspot> = furnitureId ("" when empty) and HomePortal =
-- regionId as player attributes; geometry rebuilds only when a value changes.
-- Furniture is primitive-built (<= 16 parts each) inside a 2.9-stud footprint.
-------------------------------------------------------------------------------
do
	local T=Data.TERRACE_OFFSET
	local PORTAL_LANDING={Skyreach=SKYREACH_LANDING}
	for id,pos in pairs(destinations) do PORTAL_LANDING[id]=pos end
	local function openPlanner(player)
		player:SetAttribute("IsleStation","Construction")
		player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
	end
	-- Builders receive a local frame (facing the terrace centre) and a part helper.
	local builders={}
	local function legs(P,w,d,h,color)
		for _,x in ipairs({-w/2+.2,w/2-.2}) do for _,z in ipairs({-d/2+.2,d/2-.2}) do P("Leg",V(.3,h,.3),x,h/2,z,color,WO) end end
	end
	builders.SturdyWorkbench=function(P,col)
		local top=P("Bench top",V(4,.4,2),0,1.6,0,col,WO,true)
		legs(P,4,2,1.4,darken(col,.3))
		P("Lower shelf",V(3.6,.2,1.6),0,.5,0,darken(col,.15),WO)
		P("Tool rack",V(3.6,1.6,.2),0,2.6,.9,darken(col,.25),WO)
		P("Bench vise",V(.6,.5,.6),1.5,2.05,-.6,shale,MT)
		P("Mallet",V(.9,.25,.25),-.9,1.95,-.2,timber,WO)
		return top
	end
	builders.BrassWorkbench=function(P,col)
		local top=builders.SturdyWorkbench(P,timber)
		P("Brass edging",V(4.1,.15,.15),0,1.85,-1,col,MT)
		P("Brass edging",V(4.1,.15,.15),0,1.85,1,col,MT)
		P("Anvil",V(1,.6,.6),-1.2,2.1,-.4,ink,MT)
		P("Hanging tongs",V(.15,.9,.15),1,2.7,.75,col,MT)
		return top
	end
	builders.StarforgedBench=function(P,col)
		local top=P("Starforged top",V(4,.45,2),0,1.6,0,darken(col,.55),MT,true)
		legs(P,4,2,1.4,ink)
		P("Star inlay",V(3.2,.05,.25),0,1.85,0,col,NE)
		P("Anvil",V(1,.6,.6),-1.2,2.1,-.4,col,MT)
		P("Forge crystal",V(.6,1.1,.6),1.2,2.4,-.3,mint,GL)
		P("Rune panel",V(3.6,1.6,.2),0,2.6,.9,navy,SM)
		P("Rune glow",V(2.8,.12,.05),0,3,.78,col,NE)
		return top
	end
	builders.ClayHearth=function(P,col)
		local base=P("Hearth body",V(3,2,2.2),0,1,0,col,Enum.Material.Brick,true)
		P("Firebox",V(1.8,.9,.2),0,.8,-1.05,C("FF8A3D"),NE)
		P("Mantel",V(3.4,.3,2.4),0,2.15,0,darken(col,.3),ST)
		P("Chimney",V(1.1,2.6,1.1),0,3.6,.4,darken(col,.15),Enum.Material.Brick)
		P("Cookpot",V(1,1,1),.9,2.75,-.4,ink,MT,false,BALL)
		light(base,C("FFB36B"),.7,10)
		return base
	end
	builders.EmberoakRange=function(P,col)
		local base=P("Range body",V(4,1.8,2.2),0,.9,0,darken(col,.35),Enum.Material.Brick,true)
		P("Range top",V(4.2,.25,2.4),0,1.9,0,ink,MT)
		for _,x in ipairs({-1.1,1.1}) do P("Burner",V(.9,.08,.9),x,2.06,-.3,col,NE) end
		P("Oven door",V(1.6,.9,.15),-.9,.9,-1.12,brass,MT)
		P("Chimney",V(1,2.4,1),1.3,3.2,.6,darken(col,.2),Enum.Material.Brick)
		P("Cauldron",V(1.2,1.2,1.2),-1.1,2.6,.3,ink,MT,false,BALL)
		P("Brew glow",V(.9,.1,.9),-1.1,3.1,.3,C("C77DFF"),NE)
		light(base,col,.8,11)
		return base
	end
	builders.TrinketCabinet=function(P,col)
		local body=P("Cabinet body",V(2.8,3.4,1.4),0,1.7,0,col,WO,true)
		for _,x in ipairs({-.68,.68}) do
			P("Cabinet door",V(1.25,2.8,.1),x,1.8,-.72,darken(col,.2),WO)
			P("Brass pull",V(.12,.4,.12),x*.35,1.8,-.8,brass,MT)
		end
		P("Crown moulding",V(3.1,.3,1.6),0,3.55,0,darken(col,.35),WO)
		P("Display glass",V(2.2,.6,.1),0,2.95,-.73,mint,GL)
		return body
	end
	builders.GildedReliquary=function(P,col)
		local chest=P("Reliquary chest",V(2.8,1.4,1.8),0,.7,0,navy,WO,true)
		for _,x in ipairs({-.9,.9}) do P("Gilded band",V(.25,1.5,1.9),x,.75,0,col,MT) end
		P("Lid",V(2.9,.35,1.9),0,1.55,0,darken(navy,.2),WO)
		P("Glass dome",V(1.6,1.6,1.6),0,2.4,0,cream,GL,false,BALL).Transparency=.45
		gem(P.model,"Reliquary gem",P.at(0,2.4,0),V(.5,.9,.5),C("FF55FF"),.4)
		P("Clasp",V(.5,.5,.12),0,1.1,-.95,col,MT)
		return chest
	end
	builders.TrophyStand=function(P,col)
		local plinth=P("Trophy plinth",V(2.4,.6,1.6),0,.3,0,darken(col,.3),WO,true)
		P("Post",V(.35,2.6,.35),0,1.9,.3,timber,WO)
		P("Shield board",V(2,1.6,.2),0,2.8,.1,col,WO)
		P("Hide trophy",V(1.4,1,.25),0,2.8,-.05,C("8D6346"),Enum.Material.Fabric)
		for _,x in ipairs({-.75,.75}) do gem(P.model,"Tusk",P.at(x,3.5,-.15),V(.25,.9,.25),cream,x) end
		return plinth
	end
	builders.GrandTrophyWall=function(P,col)
		local wall=P("Trophy wall",V(4.6,3.6,.4),0,1.8,.8,darken(col,.3),WO,true)
		P("Wall cap",V(4.9,.3,.6),0,3.75,.8,brass,MT)
		for i,x in ipairs({-1.5,0,1.5}) do
			P("Plaque",V(1.1,1.1,.15),x,2.3,.55,navy,WO)
			gem(P.model,"Trophy crystal",P.at(x,2.3,.4),V(.4,.7,.4),({C("D8D8E8"),C("6A4C93"),C("4B6584")})[i],x)
		end
		P("Banner",V(1.2,1.6,.08),0,.95,.55,rose,Enum.Material.Fabric)
		P("Brazier",V(.6,.8,.6),-2,.4,-.2,brass,MT)
		P("Brazier flame",V(.4,.3,.4),-2,.95,-.2,C("FF8A3D"),NE)
		return wall
	end
	builders.HerbPlanter=function(P,col)
		local box=P("Planter box",V(3.6,.8,2.2),0,.4,0,timber,WO,true)
		P("Planter soil",V(3.3,.1,1.9),0,.82,0,ink,GR)
		for i=0,5 do
			local x,z=-1.2+(i%3)*1.2,if i<3 then -.45 else .45
			gem(P.model,"Herb sprout",P.at(x,1.2,z),V(.35,.7,.35),if i%2==0 then col else turf,i)
		end
		return box
	end
	builders.MoonbloomTerrace=function(P,col)
		local lower=P("Lower bed",V(4,.7,2.4),0,.35,0,darken(navy,.2),ST,true)
		P("Upper bed",V(2.6,.7,1.4),0,1.05,.4,navy,ST)
		P("Bed soil",V(3.7,.08,.9),0,.73,-.6,ink,GR)
		P("Upper soil",V(2.3,.08,1.1),0,1.43,.4,ink,GR)
		for i=0,3 do gem(P.model,"Moonbloom",P.at(-1.4+i*.93,1.05,-.6),V(.6,.5,.6),col,i) end
		for i=0,1 do gem(P.model,"Moonbloom",P.at(-.6+i*1.2,1.75,.4),V(.6,.5,.6),cream,i) end
		for _,x in ipairs({-1.9,1.9}) do P("Arch post",V(.2,2.8,.2),x,1.4,.9,brass,MT) end
		P("Arch beam",V(4,.2,.2),0,2.85,.9,brass,MT)
		P("Arch lantern",V(.4,.4,.4),0,2.55,.9,mint,NE)
		return lower
	end
	builders.SurveyorDock=function(P,col)
		local pad=P("Dock platform",V(3.8,.4,3.2),0,.2,0,timber,WO,true)
		P("Crane mast",V(.35,3.6,.35),-1.4,2.2,1,col,MT)
		P("Crane jib",V(2.6,.25,.25),-.2,3.9,1,col,MT)
		P("Crane line",V(.06,1.4,.06),1,3.1,1,ink,SM)
		P("Supply crate",V(1,.9,1),1,1.9,1,timber,WO)
		P("Mooring cleat",V(.6,.3,.3),1.2,.55,-1.2,brass,MT)
		return pad
	end
	builders.ClockworkDock=function(P,col)
		local pad=P("Dock platform",V(3.8,.4,3.2),0,.2,0,navy,MT,true)
		for _,x in ipairs({-1.5,1.5}) do P("Brass pillar",V(.4,2.6,.4),x,1.5,1.2,brass,MT) end
		P("Pillar lintel",V(3.4,.3,.4),0,2.9,1.2,brass,MT)
		local gear=P("Great gear",V(.3,2,2),0,1.7,1,col,MT,false,Enum.PartType.Cylinder)
		gear.CFrame=gear.CFrame*CFrame.Angles(0,math.pi/2,0)
		P("Gear hub",V(.4,.6,.6),0,1.7,.8,ink,MT)
		P("Clockwork core",V(.7,.7,.7),0,.75,-.6,mint,NE,false,BALL)
		P("Core cage",V(1.1,.1,1.1),0,1.15,-.6,brass,MT)
		return pad
	end
	builders.PortalFrame=function(P,col)
		local base=P("Portal dais",V(4.2,.3,2),0,.15,0,ink,ST,true)
		for _,x in ipairs({-1.7,1.7}) do P("Portal pillar",V(.6,4.2,.6),x,2.4,0,timber,WO) end
		P("Portal lintel",V(4.2,.6,.8),0,4.7,0,timber,WO)
		P("Lintel crystal",V(.5,.5,.5),0,5.15,0,col,NE)
		local veil=P("Portal veil",V(2.8,3.9,.12),0,2.3,0,col,NE)
		veil.Transparency=.4
		light(veil,col,.8,10)
		return base,veil
	end
	builders.StormglassGate=function(P,col)
		local base=P("Gate dais",V(4.6,.3,2.2),0,.15,0,navy,ST,true)
		local veil=P("Gate veil",V(.12,3.6,3.6),0,2.4,0,col,NE,false,Enum.PartType.Cylinder)
		veil.CFrame=veil.CFrame*CFrame.Angles(0,math.pi/2,0)
		veil.Transparency=.35
		for i=1,8 do
			local a=i*math.pi/4
			gem(P.model,"Stormglass shard",P.at(math.cos(a)*2.05,2.4+math.sin(a)*2.05,0),V(.4,1.1,.4),if i%2==0 then col else mint,a)
		end
		light(veil,col,.9,12)
		return base,veil
	end
	local function buildFurniture(parent,id,cf)
		local f=Data.Furniture[id]
		local model=group("Furniture_"..f.hotspot,parent)
		model:SetAttribute("FurnitureId",id)
		local P={model=model}
		P.at=function(x,y,z) return (cf*CFrame.new(x,y,z)).Position end
		setmetatable(P,{__call=function(_,name,size,x,y,z,color,mat,solid,shape)
			return part(model,name,size,cf*CFrame.new(x,y,z),color,mat,solid,shape)
		end})
		local main,veil=builders[id](P,C(f.color))
		return model,main,veil
	end
	local function hotspotFrame(center,h)
		local pos=center+V(h.x,0,h.z)
		local focus=center+V(T.x,0,T.z)
		if (pos-focus).Magnitude<.5 then return CFrame.lookAt(pos,pos+V(1,0,0)) end
		return CFrame.lookAt(pos,V(focus.X,pos.Y,focus.Z))
	end
	homeTerrace.builders=builders
	homeTerrace.attach=function(player,home)
		if not home or home.terrace then return end
		local m,center=home.model,home.center
		local tc=center+V(T.x,0,T.z)
		local terrace=island("Builders Terrace",tc,11,{top=C("A7B08A"),parent=m,rim=false,shore=false})
		home.terrace=terrace
		bridge(terrace,center+V(-HOME_CORE+.5,0,0),center+V(-22.4,0,0))
		disk(terrace,"Terrace court",tc+V(0,.05,0),4.2,.12,navy,ST,true)
		disk(terrace,"Court seal",tc+V(0,.13,0),1.4,.1,brass,MT,false)
		sign(terrace,center+V(-15,0,-6),"Builder's Terrace","CARPENTRY   /   PLAN IN YOUR JOURNAL",brass,90,8)
		local built,plinths,portalPrompt={},{},nil
		local function refreshPortal()
			if not portalPrompt then return end
			local region=player:GetAttribute("HomePortal")
			local def=type(region)=="string" and Data.RegionById[region]
			portalPrompt.ObjectText=if def then "Home portal · "..def.name else "Home portal · attune in Journal"
		end
		local function refresh(h)
			local value=player:GetAttribute("Furniture"..h.id)
			local f=type(value)=="string" and Data.Furniture[value]
			if f and f.hotspot~=h.id then f=nil end
			local id=f and value or nil
			if built[h.id] and built[h.id].id==id then return end
			if built[h.id] then built[h.id].model:Destroy() end
			built[h.id]=nil
			if h.id=="Portal" then portalPrompt=nil end
			plinths[h.id].Transparency=if id then 1 else 0
			if not id or not m.Parent then return end
			local model,main,veil=buildFurniture(terrace,id,hotspotFrame(center,h))
			built[h.id]={id=id,model=model}
			for _,kind in ipairs(f.effect.station or {}) do
				local q=prompt(main,STATION[kind][1],kind.." · Home "..STATION[kind][2],"station",kind,player.UserId)
				q.Triggered:Connect(function(user)
					if user~=player then return end
					user:SetAttribute("IsleStation",kind)
					user:SetAttribute("IsleStationVisit",(user:GetAttribute("IsleStationVisit") or 0)+1)
				end)
			end
			if f.effect.portal and veil then
				portalPrompt=prompt(veil,"Step through","Home portal")
				portalPrompt:SetAttribute("OwnerUserId",player.UserId)
				portalPrompt:SetAttribute("IsleHomePortal",true)
				portalPrompt.Triggered:Connect(function(user)
					if user~=player then return end
					local region=user:GetAttribute("HomePortal")
					if type(region)=="string" and PORTAL_LANDING[region] then
						regionTravel(user,veil,region,PORTAL_LANDING[region])
					else
						user:SetAttribute("IsleRegionNotice","Attune your home portal from the Construction page of your Journal.")
						user:SetAttribute("IsleRegionNoticeCount",(tonumber(user:GetAttribute("IsleRegionNoticeCount")) or 0)+1)
					end
				end)
				refreshPortal()
			end
		end
		for _,h in ipairs(Data.Hotspots) do
			local cf=hotspotFrame(center,h)
			local plinth=part(terrace,h.name.." hotspot",V(4.4,.14,3.2),cf*CFrame.new(0,.07,0),cream,ST,false)
			plinth.Transparency=0
			plinth:SetAttribute("HotspotId",h.id)
			plinths[h.id]=plinth
			local q=prompt(plinth,"Plan",h.name)
			q:SetAttribute("OwnerUserId",player.UserId)
			q.Triggered:Connect(function(user) if user==player then openPlanner(user) end end)
			table.insert(home.decorationConnections,player:GetAttributeChangedSignal("Furniture"..h.id):Connect(function() refresh(h) end))
			refresh(h)
		end
		table.insert(home.decorationConnections,player:GetAttributeChangedSignal("HomePortal"):Connect(refreshPortal))
	end
	for player,home in pairs(homes) do homeTerrace.attach(player,home) end
end

-------------------------------------------------------------------------------
-- Island placement (Island Builder team). The server publishes the owner's
-- free-form placements as player attribute IslandPlacements ("id:prop:x:z:rot"
-- records joined by ";", Data.Island grid). Each record becomes an anchored
-- primitive model (<= 12 parts) named Placement_<id> in the home's Placements
-- folder; a change rebuilds only the records that differ. The folder goes with
-- the home model when the player leaves. Player attribute IslandCenter lets the
-- client snap its build-mode ghost to the same grid.
-------------------------------------------------------------------------------
do
	local I=Data.Island
	local CYL=Enum.PartType.Cylinder
	local UPRIGHT=CFrame.Angles(0,0,math.pi/2)
	local FAB,BR,LG=Enum.Material.Fabric,Enum.Material.Brick,Enum.Material.LeafyGrass
	local B={}
	homePlacement.builders=B
	-- P(name,size,x,y,z,color,material,solid,shape,rotation) builds in the prop's
	-- local frame: origin at the footprint centre on the meadow, x along width.
	B.TimberFence=function(P,col)
		for _,x in ipairs({-.75,.75}) do P("Fence post",V(.28,1.7,.28),x,.85,0,darken(col,.2),WO) end
		P("Upper rail",V(1.9,.2,.16),0,1.3,0,col,WO,true)
		return P("Lower rail",V(1.9,.2,.16),0,.6,0,col,WO,true)
	end
	B.PicketFence=function(P,col)
		local rail=P("Picket rail",V(1.9,.16,.1),0,.5,.08,darken(col,.15),WO,true)
		P("Picket rail",V(1.9,.16,.1),0,1,.08,darken(col,.15),WO,true)
		for _,x in ipairs({-.72,-.24,.24,.72}) do P("Picket",V(.3,1.4,.1),x,.7,-.02,col,WO) end
		return rail
	end
	B.BrassRailing=function(P,col)
		for _,x in ipairs({-.8,.8}) do
			P("Windpine post",V(.3,1.5,.3),x,.75,0,C("6B8E5A"),WO)
			P("Brass finial",V(.36,.36,.36),x,1.65,0,col,MT,false,BALL)
		end
		P("Mid rail",V(1.9,.12,.12),0,.75,0,col,MT,true)
		return P("Top rail",V(1.9,.16,.16),0,1.35,0,col,MT,true)
	end
	B.StonePath=function(P,col)
		local base=P("Path bed",V(1.9,.1,1.9),0,.05,0,darken(col,.25),ST,true)
		P("Flagstone",V(.85,.06,.8),-.45,.13,-.4,col,ST)
		P("Flagstone",V(.8,.06,.85),.45,.13,.42,lighten(col,.1),ST)
		return base
	end
	B.Boardwalk=function(P,col)
		local first
		for i,z in ipairs({-.71,-.24,.24,.71}) do
			local plank=P("Plank",V(1.9,.12,.42),0,.18,z,if i%2==0 then col else darken(col,.12),WO,true)
			first=first or plank
		end
		for _,x in ipairs({-.7,.7}) do P("Sleeper",V(.3,.12,1.9),x,.06,0,darken(col,.4),WO) end
		return first
	end
	B.AetherMosaic=function(P,col)
		local base=P("Mosaic bed",V(1.9,.1,1.9),0,.05,0,navy,ST,true)
		for _,o in ipairs({{-.45,-.45},{.45,.45},{-.45,.45},{.45,-.45}}) do
			P("Aether tile",V(.78,.05,.78),o[1],.12,o[2],if o[1]==o[2] then col else cream,if o[1]==o[2] then NE else ST)
		end
		return base
	end
	B.LanternPost=function(P,col)
		P("Lantern foot",V(.7,.4,.7),0,.2,0,ink,ST,true)
		P("Lantern mast",V(.2,2.8,.2),0,1.8,0,brass,MT)
		P("Lantern arm",V(.6,.12,.12),.25,3.1,0,brass,MT)
		P("Lantern cap",V(.5,.12,.5),.5,3.15,0,ink,MT)
		return P("Lantern glass",V(.45,.45,.45),.5,2.85,0,col,NE,false,BALL)
	end
	B.BrassStreetlamp=function(P,col)
		P("Lamp base",V(.9,.5,.9),0,.25,0,ink,ST,true)
		P("Lamp column",V(.28,4,.28),0,2.5,0,brass,MT)
		P("Lamp crossbar",V(1.6,.14,.14),0,4.4,0,brass,MT)
		for _,x in ipairs({-.65,.65}) do P("Lamp globe",V(.5,.5,.5),x,4.1,0,col,NE,false,BALL) end
		return P("Lamp crown",V(.36,.36,.36),0,4.65,0,brass,MT,false,BALL)
	end
	B.CrystalBrazier=function(P,col)
		P("Brazier foot",V(1,.3,1),0,.15,0,ink,ST,true)
		P("Brazier stem",V(.35,1,.35),0,.8,0,darken(brass,.2),MT)
		local bowl=P("Brazier bowl",V(.5,1.4,1.4),0,1.45,0,C("B5482A"),MT,false,CYL,UPRIGHT)
		for i,x in ipairs({-.3,0,.3}) do P("Aether flame",V(.3,.7+(i%2)*.3,.3),x,1.95+(i%2)*.15,(i-2)*.1,col,NE) end
		return bowl
	end
	B.FlowerPlanter=function(P,col)
		local box=P("Planter box",V(1.6,.6,1.6),0,.3,0,timber,WO,true)
		P("Planter soil",V(1.4,.08,1.4),0,.62,0,ink,GR)
		for i,o in ipairs({{-.4,-.4},{.4,.4},{-.4,.4},{.4,-.4}}) do
			P("Bloom",V(.42,.42,.42),o[1],.9,o[2],if i%2==0 then col else cream,SM,false,BALL)
		end
		return box
	end
	B.HedgeRow=function(P,col)
		P("Hedge planter",V(3.8,.4,1.4),0,.2,0,timber,WO,true)
		local hedge=P("Hedge",V(3.6,1.3,1.2),0,1.05,0,col,LG,true)
		for _,x in ipairs({-1.1,1.1}) do P("Hedge crown",V(1,1,1),x,1.7,0,lighten(col,.08),LG,false,BALL) end
		return hedge
	end
	B.YoungWindpine=function(P,col)
		local trunk=P("Sapling trunk",V(.3,2.2,.3),0,1.1,0,timber,WO,true)
		P("Lower boughs",V(1.6,.8,1.6),0,1.6,0,darken(col,.1),LG)
		P("Middle boughs",V(1.1,.8,1.1),0,2.3,0,col,LG)
		P("Crown",V(.6,.7,.6),0,2.95,0,lighten(col,.1),LG)
		return trunk
	end
	B.MoonbloomBed=function(P,col)
		local bed=P("Moonbloom bed",V(3.7,.7,3.7),0,.35,0,darken(navy,.2),ST,true)
		P("Bed soil",V(3.4,.08,3.4),0,.72,0,ink,GR)
		for i=0,5 do
			local x,z=-1.1+(i%3)*1.1,if i<3 then -.8 else .8
			P("Moonbloom",V(.55,.55,.55),x,1.05,z,if i%2==0 then col else cream,NE,false,BALL)
		end
		return bed
	end
	B.GuildBanner=function(P,col)
		P("Banner foot",V(.6,.3,.6),0,.15,0,ink,ST,true)
		local pole=P("Banner pole",V(.18,3.8,.18),0,2.2,0,timber,WO)
		P("Banner crossbar",V(1.4,.12,.12),0,3.9,0,brass,MT)
		P("Banner cloth",V(1.2,1.9,.08),0,2.85,.1,col,FAB)
		P("Banner crest",V(.4,.4,.06),0,2.95,.16,brass,MT)
		return pole
	end
	B.VoyagerPennant=function(P,col)
		P("Pennant foot",V(.6,.3,.6),0,.15,0,ink,ST,true)
		local pole=P("Pennant pole",V(.16,3.6,.16),-.6,2,0,timber,WO)
		P("Pennant upper",V(1.2,.5,.06),0,3.4,0,col,FAB)
		P("Pennant lower",V(.7,.4,.06),-.2,2.95,0,darken(col,.15),FAB)
		P("Pennant finial",V(.26,.26,.26),-.6,3.9,0,brass,MT,false,BALL)
		return pole
	end
	B.StormStandard=function(P,col)
		P("Standard foot",V(.8,.3,.8),0,.15,0,navy,ST,true)
		local pole=P("Starwood pole",V(.2,4.4,.2),0,2.5,0,C("3B4C7A"),WO)
		P("Storm ring",V(.12,1.1,1.1),0,4.2,0,brass,MT,false,CYL)
		P("Stormglass",V(.4,.7,.4),0,4.2,0,col,NE)
		P("Storm banner",V(1.1,1.6,.08),0,2.9,.12,col,FAB)
		return pole
	end
	B.SurveyorStatue=function(P,col)
		local plinth=P("Statue plinth",V(3,.9,3),0,.45,0,darken(col,.2),ST,true)
		P("Plinth step",V(3.6,.25,3.6),0,.12,0,darken(col,.35),ST)
		P("Surveyor body",V(1.1,2,.9),0,1.9,0,col,ST,true)
		P("Surveyor head",V(.8,.8,.8),0,3.3,0,col,ST,false,BALL)
		P("Surveyor hat",V(1.2,.18,1.2),0,3.7,0,darken(col,.15),ST)
		P("Spyglass",V(.2,.2,1.2),.55,2.6,-.5,brass,MT)
		return plinth
	end
	B.SkywhaleStatue=function(P,col)
		local plinth=P("Whale plinth",V(3,.6,3),0,.3,0,navy,ST,true)
		P("Cloud",V(1.4,1.4,1.4),-.7,1,.6,cream,SM,false,BALL)
		P("Cloud",V(1.2,1.2,1.2),.7,.9,-.6,cream,SM,false,BALL)
		P("Whale body",V(1.3,1.2,2.6),0,2.1,0,col,GL,true)
		P("Whale head",V(1.2,1.2,1.2),0,2.2,-1.2,col,GL,false,BALL)
		for _,x in ipairs({-.8,.8}) do P("Whale fin",V(.6,.12,.8),x,1.8,-.2,lighten(col,.2),GL) end
		P("Whale tail",V(1.6,.16,.6),0,2.5,1.4,lighten(col,.2),GL)
		return plinth
	end
	B.AetherObelisk=function(P,col)
		P("Obelisk base",V(1.8,.4,1.8),0,.2,0,ink,ST,true)
		local shaft=P("Obelisk shaft",V(.9,4.6,.9),0,2.7,0,col,MT,true)
		P("Obelisk band",V(1.05,.2,1.05),0,1.5,0,brass,MT)
		P("Obelisk band",V(1.05,.2,1.05),0,3.9,0,brass,MT)
		P("Aether tip",V(.55,.55,.55),0,5.25,0,mint,NE,false,BALL)
		return shaft
	end
	B.PicnicBench=function(P,col)
		local top=P("Table top",V(3.4,.18,1),0,1.1,0,col,WO,true)
		for _,x in ipairs({-1.3,1.3}) do P("Table leg",V(.2,1,.8),x,.5,0,darken(col,.3),WO) end
		for _,z in ipairs({-.75,.75}) do P("Bench seat",V(3.4,.14,.36),0,.6,z,darken(col,.12),WO,true) end
		return top
	end
	B.StoneWell=function(P,col)
		for _,o in ipairs({{0,-1.35,3.2,.5},{0,1.35,3.2,.5},{-1.35,0,.5,2.2},{1.35,0,.5,2.2}}) do
			P("Well wall",V(o[3],1,o[4]),o[1],.5,o[2],col,ST,true)
		end
		local water=P("Well water",V(2.2,.1,2.2),0,.7,0,teal,GL)
		for _,x in ipairs({-1.35,1.35}) do P("Well post",V(.25,2.2,.25),x,2.1,0,timber,WO) end
		P("Well roof",V(3.4,.25,2.2),0,3.3,0,darken(timber,.25),WO)
		P("Well bucket",V(.4,.4,.4),0,1.9,0,brass,MT)
		return water
	end
	B.SupplyShed=function(P,col)
		local body=P("Shed walls",V(3.2,2.4,3.2),0,1.2,0,col,WO,true)
		P("Shed door",V(1,1.8,.08),0,.9,-1.62,darken(col,.35),WO)
		for _,s in ipairs({-1,1}) do
			P("Shed roof",V(1.95,.2,3.5),s*.82,2.8,0,darken(navy,.1),ST,false,nil,CFrame.Angles(0,0,-s*math.rad(25)))
		end
		P("Roof ridge",V(.3,.25,3.5),0,3.25,0,brass,MT)
		P("Supply crate",V(.8,.7,.7),1.1,.35,-1.5,timber,WO)
		return body
	end
	B.GardenGazebo=function(P,col)
		local floor=P("Gazebo floor",V(5.6,.3,5.6),0,.15,0,darken(col,.25),WO,true)
		for _,o in ipairs({{-2.4,-2.4},{2.4,-2.4},{-2.4,2.4},{2.4,2.4}}) do P("Gazebo pillar",V(.35,3.2,.35),o[1],1.9,o[2],col,WO,true) end
		P("Gazebo roof",V(5.8,.3,5.8),0,3.65,0,teal,ST)
		P("Gazebo crown",V(3.2,.5,3.2),0,4.05,0,darken(teal,.2),ST)
		P("Brass finial",V(.6,.6,.6),0,4.6,0,brass,MT,false,BALL)
		P("Gazebo bench",V(2.6,.3,.6),0,.6,1.9,timber,WO,true)
		return floor
	end
	B.CarpenterStump=function(P,col)
		local stump=P("Carpenter's stump",V(1,1.5,1.5),0,.5,0,col,WO,true,CYL,UPRIGHT)
		P("Growth ring",V(.04,1.2,1.2),0,1.01,0,timber,WO,false,CYL,UPRIGHT)
		P("Axe handle",V(.12,.9,.12),.3,1.4,-.2,timber,WO)
		P("Axe head",V(.35,.2,.08),.4,1.8,-.2,shale,MT)
		return stump
	end
	B.CampStove=function(P,col)
		local body=P("Stove body",V(1.4,1,1.2),0,.5,0,col,BR,true)
		P("Stove top",V(1.5,.15,1.3),0,1.07,0,ink,MT)
		P("Firebox",V(.8,.4,.06),0,.45,-.62,C("FF8A3D"),NE)
		P("Stove pipe",V(.3,1.2,.3),.45,1.7,.35,ink,MT)
		P("Cookpot",V(.55,.55,.55),-.25,1.42,-.1,ink,MT,false,BALL)
		return body
	end
	B.FieldAnvil=function(P,col)
		local block=P("Anvil block",V(.9,.7,.9),0,.35,0,timber,WO,true)
		P("Anvil waist",V(.4,.3,.5),0,.85,0,col,MT)
		P("Anvil face",V(1.3,.3,.6),0,1.15,0,col,MT,true)
		P("Anvil horn",V(.4,.2,.3),.8,1.18,0,col,MT)
		P("Hammer",V(.5,.14,.14),-.3,1.37,.1,brass,MT)
		return block
	end
	B.BrewingStand=function(P,col)
		local stand=P("Brewing table",V(1.6,.2,1.2),0,.9,0,timber,WO,true)
		for _,x in ipairs({-.65,.65}) do P("Table leg",V(.16,.8,1),x,.4,0,darken(timber,.3),WO) end
		P("Cauldron",V(.8,.8,.8),-.2,1.4,0,ink,MT,false,BALL)
		P("Brew glow",V(.6,.06,.6),-.2,1.78,0,col,NE)
		P("Potion flask",V(.25,.45,.25),.55,1.23,.2,mint,GL)
		return stand
	end
	homePlacement.build=function(folder,center,e,player)
		local def=I.Props[e.prop]
		local ox,oz,yaw=I.centerOffset(e.prop,e.x,e.z,e.rot)
		local cf=CFrame.new(center+V(ox,0,oz))*CFrame.Angles(0,yaw,0)
		local model=group("Placement_"..e.id,folder)
		model:SetAttribute("PlacementId",e.id)
		model:SetAttribute("PropId",e.prop)
		model:SetAttribute("PlacementRecord",I.record(e))
		local function P(name,size,x,y,z,color,mat,solid,shape,rotation)
			return part(model,name,size,cf*CFrame.new(x,y,z)*(rotation or CFrame.identity),color,mat,solid,shape)
		end
		local main=B[e.prop](P,C(def.color))
		local effect=def.effect or {}
		if effect.light then
			local glow=light(main,C(effect.light.color),.7,effect.light.range)
			glow.Name="Placement glow"
		end
		if effect.station and STATION[effect.station] then
			local kind=effect.station
			local q=prompt(main,STATION[kind][1],kind.." · Home "..STATION[kind][2],"station",kind,player.UserId)
			q.Triggered:Connect(function(user)
				if user~=player then return end
				user:SetAttribute("IsleStation",kind)
				user:SetAttribute("IsleStationVisit",(user:GetAttribute("IsleStationVisit") or 0)+1)
			end)
		end
		return model
	end
	-- Brightness stacking fix: a full island of lantern posts lit 60+ point
	-- lights at once. At most MAX_GLOWS placement lights shine per island and
	-- no two within GLOW_SPACING studs; the rest stay dark (lowest ids win).
	local MAX_GLOWS,GLOW_SPACING=10,9
	homePlacement.MAX_GLOWS=MAX_GLOWS
	homePlacement.relight=function(folder)
		local glows={}
		for _,model in ipairs(folder:GetChildren()) do
			local glow=model:FindFirstChild("Placement glow",true)
			if glow then
				local host=glow.Parent
				local pos=if host:IsA("Attachment") then (host.Parent.CFrame*host.CFrame).Position else host.CFrame.Position
				table.insert(glows,{id=model:GetAttribute("PlacementId") or 0,light=glow,pos=pos})
			end
		end
		table.sort(glows,function(a,b) return a.id<b.id end)
		local lit={}
		for _,g in ipairs(glows) do
			local ok=#lit<MAX_GLOWS
			for _,o in ipairs(lit) do if ok and (o.pos-g.pos).Magnitude<GLOW_SPACING then ok=false end end
			g.light.Enabled=ok
			if ok then table.insert(lit,g) end
		end
	end
	homePlacement.attach=function(player,home)
		if not home or home.placements then return end
		local folder=Instance.new("Folder")
		folder.Name="Placements"
		folder.Parent=home.model
		home.placements=folder
		player:SetAttribute("IslandCenter",home.center)
		local built={}
		local function refresh()
			if not folder.Parent then return end
			-- Re-validate geometry so a bad value can never stack props.
			local want,occupied={},{}
			for _,e in ipairs(I.decode(player:GetAttribute("IslandPlacements"))) do
				if not want[e.id] and I.check(occupied,e.prop,e.x,e.z,e.rot) then
					want[e.id]=e
					for _,c in ipairs(I.cells(e.prop,e.x,e.z,e.rot)) do occupied[I.key(c[1],c[2])]=e.id end
				end
			end
			for id,b in pairs(built) do
				if not want[id] or I.record(want[id])~=b.record then
					b.model:Destroy()
					built[id]=nil
				end
			end
			for id,e in pairs(want) do
				if not built[id] then built[id]={record=I.record(e),model=homePlacement.build(folder,home.center,e,player)} end
			end
			homePlacement.relight(folder)
		end
		table.insert(home.decorationConnections,player:GetAttributeChangedSignal("IslandPlacements"):Connect(refresh))
		refresh()
	end
	for player,home in pairs(homes) do homePlacement.attach(player,home) end
end
