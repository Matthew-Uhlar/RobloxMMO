-- Aether Isles archipelago. Gameplay is attached to prompts by the server.
-- Wave 4: islands are 2-3x larger with tiers, cliffs, paths, ponds and flora;
-- every island is a Model under Workspace.Islands (IslandCenter / IslandRadius /
-- Region attributes + Anchor_<Purpose> parts, docs/DEPTH-CONTRACT.md section 10);
-- props that should become custom meshes carry Shape / Tint / ShapeScale.
local Players = game:GetService("Players")
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
-- Lighting (§35): this script writes NO Lighting property and adds no Lighting
-- child. lighting.client.lua (StarterPlayerScripts.IsleLighting) is the one
-- writer: day-night from the isle clock, region profiles, post effects, the
-- graphics tier and the world light budget. Technology = Future and the day
-- look are the place defaults in default.project.json. The old server cycle
-- here (its own 20-minute clock that disagreed with the sidebar, ClockTime
-- stepped every 2 s so shadows jittered, and Lighting children rebuilt on the
-- server) was removed. Night lamps are created off and tagged NightLight; the
-- director lights them after dusk near the player.
-------------------------------------------------------------------------------
-- BEGIN GENERATED BUILDINGS (art/generate-props.cjs from art/building-shapes.cjs; do not edit)
local BUILDING_KIT={TimberHouse={kind="facade",w=12,d=10,h=10,windows={{1.5,3.2,-5.17,1.7,1.9,0},{4.1,3.2,-5.17,1.7,1.9,0},{-3.95,8.15,-5.77,1.5,1.9,0},{0,8.15,-5.77,1.5,1.9,0},{3.95,8.15,-5.77,1.5,1.9,0},{6.17,3.2,-1.2,1.5,1.8,-1.571},{-6.17,3.2,1.2,1.5,1.8,1.571},{6.32,8,2.3,1.4,1.8,-1.571},{-6.32,8,-2.9,1.4,1.8,1.571},{-2.5,3.2,5.17,1.5,1.8,3.142},{3,8,5.17,1.4,1.8,3.142},{-3,8,5.17,1.4,1.8,3.142},{6.32,11.32,-0.3,1,1.3,-1.571},{-2.6,14,-3.12,1.2,1.26,0}},door={x=-2.6,z=-5,w=2.2,h=3.9,ry=0},fit={{-7.04,0,-6.556},{7.04,19.02,5.956}},tint="B5523B"},TimberTownhouse={kind="facade",w=8,d=10,h=14,windows={{1.8,3.1,-5.17,2.1,2,0},{0,7.6,-5.67,1.6,2.2,0},{-2,12,-6.17,1.4,1.9,0},{2,12,-6.17,1.4,1.9,0},{4.17,3.1,1.5,1.4,1.7,-1.571},{-4.17,3.1,-1.5,1.4,1.7,1.571},{4.27,7.4,-1.75,1.4,1.8,-1.571},{-4.27,7.4,1.25,1.4,1.8,1.571},{4.37,11.8,1.3,1.3,1.7,-1.571},{-4.37,11.8,-2.3,1.3,1.7,1.571},{0,7.4,5.17,1.5,1.8,3.142},{0,16.6,-6.17,1.3,1.6,0}},door={x=-2.1,z=-5,w=2,h=3.8,ry=0},fit={{-5.061,0,-7.09},{5.061,22.42,6.09}},tint="2F6F8F"},TimberShopfront={kind="facade",w=12,d=10,h=10,windows={{1.8,3.55,-5.17,6.6,2.4,0},{0,7.7,-6.47,2.4,2.2,0},{-4.2,7.9,-5.77,1.5,1.9,0},{4.2,7.9,-5.77,1.5,1.9,0},{6.17,3.2,0,1.5,1.8,-1.571},{-6.17,3.2,0,1.5,1.8,1.571},{6.27,7.9,0.9,1.4,1.8,-1.571},{-6.27,7.9,-1.5,1.4,1.8,1.571},{0,7.9,5.17,1.5,1.8,3.142},{-6.27,11.28,-0.3,1,1.3,1.571},{2.8,13.9,-3.12,1.2,1.26,0}},door={x=-4,z=-5,w=2,h=3.8,ry=0},fit={{-6.99,0,-6.947},{6.99,18.72,5.955}},tint="D9A441"},StoneCottage={kind="facade",w=11,d=9,h=7,windows={{2.3,3,-4.67,1.8,1.9,0},{5.67,3,0,1.5,1.7,-1.571},{-5.67,3,0,1.5,1.7,1.571},{2,3,4.67,1.5,1.7,3.142},{-5.67,8.16,0,0.9,1.2,1.571},{2.3,10.55,-2.42,1.1,1.2,0}},door={x=-2.4,z=-4.5,w=2.1,h=3.9,ry=0},fit={{-6.19,0,-5.4},{6.19,14.82,5.357}},tint="56677A"},ThatchCottage={kind="facade",w=11,d=9,h=6,windows={{-3.5,3.3,-4.67,1.6,1.7,0},{3.5,3.3,-4.67,1.6,1.7,0},{5.67,3.3,1.4,1.4,1.6,-1.571},{-5.67,3.3,-1.4,1.4,1.6,1.571},{0,3.3,4.67,1.5,1.6,3.142}},door={x=0,z=-4.5,w=2,h=3.8,ry=0},fit={{-6.4,0,-5.804},{6.4,13.62,5.804}},tint="3C8C7E"},LogLodge={kind="facade",w=12,d=10,h=7.6,windows={{-3.8,3.4,-5.17,1.7,1.8,0},{3.8,3.4,-5.17,1.7,1.8,0},{6.17,3.4,-1.5,1.5,1.7,-1.571},{-6.17,3.4,1.5,1.5,1.7,1.571},{-2,3.4,5.17,1.5,1.7,3.142},{-5.97,9.04,0,1.1,1.4,1.571},{5.97,9.04,0,1.1,1.4,-1.571}},door={x=0,z=-5,w=2.2,h=4,ry=0},fit={{-6.99,0,-7.737},{6.99,17.02,6.06}},tint="4E7A48"},ShopHall={kind="walkin",w=16,d=13,h=9.6,windows={{-5,4.3,-6.13,3.2,3.4,0},{5,4.3,-6.13,3.2,3.4,0},{4.3,4.5,6.13,2.6,3,3.142},{-4.3,4.5,6.13,2.6,3,3.142},{7.63,4.5,0,2.4,3,-1.571},{-7.63,4.5,0,2.4,3,1.571},{-8.17,10.96,0,1.4,1.6,1.571},{8.17,10.96,0,1.4,1.6,-1.571},{-4.2,13.65,-3.42,1.1,1.2,0},{4.2,13.65,-3.42,1.1,1.2,0}},door={x=0,z=-6.5,w=4.4,h=7.2,ry=0},t=0.8,floor=0.34,opening={u=0,w=4.4,h=7.2},fit={{-8.89,0,-7.45},{8.89,18.62,7.45}},tint="9C3F3A"},TavernHall={kind="walkin",w=18,d=13,h=10.4,windows={{-6,7.9,-6.67,1.8,2.2,0},{6,7.9,-6.67,1.8,2.2,0},{9.17,8,0,1.6,2,-1.571},{-9.17,8,0,1.6,2,1.571},{-6,3.8,-6.13,3.2,2.8,0},{6,3.8,-6.13,3.2,2.8,0},{4,4.2,6.13,2,2.4,3.142},{-4,4.2,6.13,2,2.4,3.142},{8.63,4.2,-2.6,2,2.4,-1.571},{-8.63,4.2,2.6,2,2.4,1.571},{9.17,11.88,0,1.6,1.8,-1.571}},door={x=0,z=-6.5,w=4,h=7,ry=0},t=0.8,floor=0.34,opening={u=0,w=4,h=7},fit={{-10.75,0,-8.85},{9.89,19.82,7.453}},tint="7A3E2E"},BankInterior={kind="interior",w=16,d=13,h=9.6,windows={},counter={c={0,1.74,0.5},s={6.5,2.8,2}},fit={{-7.1,0.34,-5.4},{7.1,10,5.68}},tint="C9A24E"},ShopInterior={kind="interior",w=16,d=13,h=9.6,windows={},counter={c={0,1.74,0.5},s={6.5,2.8,2}},fit={{-6.15,0.34,-5.5},{7.1,9.8,5.6}},tint="9DF3D7"},TavernInterior={kind="interior",w=18,d=13,h=10.4,windows={},counter={c={5.6,1.6400000000000001,1},s={2,2.6,8}},fit={{-8.2,0.14,-4.557},{8.05,10.6,5}},tint="C15557"},HallFurnishings={kind="interior",w=8,d=18,h=7,windows={},fit={{-3.55,0,-9},{4.95,7,9}},tint="3F6FB5"}}
-- END GENERATED BUILDINGS
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
local INTERACT_HOLD=.36 -- §42: nothing gathers by holding a prompt (the 1 s gather hold is retired)
local function prompt(p, verb, item, action, id, owner)
	assert(action~="gather","§42: gathering nodes are struck, never prompted (Node.gather)")
	local q = Instance.new("ProximityPrompt")
	q.ActionText, q.ObjectText, q.HoldDuration = verb,item,INTERACT_HOLD
	q.MaxActivationDistance, q.RequiresLineOfSight = 9,false
	if action then q:SetAttribute("IsleAction",action) end
	if id then q:SetAttribute("IsleItem",id) end
	if owner then q:SetAttribute("OwnerUserId",owner) end
	-- §44: a travel beacon's prompt hangs on its "Beacon prompt" attachment
	-- (in front of the dais, waist height), not inside the crystal cage.
	local seat=p:FindFirstChild("Beacon prompt")
	q.Parent = if seat and seat:IsA("Attachment") then seat else p
	return q
end
-- §42 Gathering Feel: nodes are struck with the held tool, never prompted. The
-- host part (the click target) carries GatherNode=<resource id> (+ IsleRegion,
-- OwnerUserId; NodeMaxHp and NodeLabel once AetherData loads) and the
-- AetherNode tag; its Model is the node's visual group (the client depletes it
-- per player). server.server.lua's `strike` verb validates every hit.
local Node={pending={}} -- Node.stamp once AetherData loads; nodes built before that wait in Node.pending
function Node.gather(host,id,region,owner)
	host:SetAttribute("GatherNode",id)
	if region then host:SetAttribute("IsleRegion",region) end
	if owner then host:SetAttribute("OwnerUserId",owner) end
	host.CanQuery=true
	Tags:AddTag(host,"AetherNode")
	if Node.stamp then Node.stamp(host) else table.insert(Node.pending,host) end
	return host
end
-- §42 (owner decision): special strike nodes. `kind` routes the break on the
-- server (StrikeKind "crew": the Crew Haven stores credit the crew through
-- coop.server.lua; "garden": a ripe Verdant Garden plot harvests through the
-- Garden verbs). `name` overrides the hover / bar name.
function Node.special(host,id,kind,name,owner)
	Node.gather(host,id,nil,owner)
	host:SetAttribute("StrikeKind",kind)
	host:SetAttribute("NodeName",name)
	return host
end
-- A plot that stops being ripe is no longer a node.
function Node.ungather(host)
	if host:GetAttribute("GatherNode")==nil then return end
	for _,key in ipairs({"GatherNode","StrikeKind","NodeName","NodeMaxHp","NodeLabel","ResourceId","OwnerUserId","GardenHarvest"}) do host:SetAttribute(key,nil) end
	Tags:RemoveTag(host,"AetherNode")
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
-- mesh and keeps this primitive as the collider/fallback. The mesh fills the
-- host's own box (a cylinder host stands the mesh up along its axis), so hosts
-- are sized here and ShapeScale (a multiplier on that box) is left at 1.
-- ShapeOwnsModel marks a part whose mesh stands for every other part of its own
-- small Model (except parts with their own Shape, and Neon accents): the slot
-- box grows to cover them and the forge hides them locally. fit="Uniform" keeps
-- the authored proportions, standing on the slot floor.
local function meshSlot(p,shape,tint,ownsModel,fit)
	p:SetAttribute("Shape",shape)
	if tint then p:SetAttribute("Tint",tint) end
	if ownsModel then p:SetAttribute("ShapeOwnsModel",true) end
	if fit then p:SetAttribute("ShapeFit",fit) end
	return p
end
-- Invisible slot box for props whose collider/prompt part is a flat base: the
-- base stays visible as the fallback and the mesh stands in this box.
local function slotBox(parent,name,pos,size,shape,tint)
	local p=part(parent,name,size,CFrame.new(pos+V(0,size.Y/2,0)),cream,SM,false)
	p.Transparency,p.CastShadow,p.CanQuery=1,false,false
	return meshSlot(p,shape,tint)
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
		l.Enabled=false -- the client director (§35) lights it after dusk
		l:SetAttribute("NightLight",true)
	end
	-- §35 QC M1: server intent rides in attributes the client director never
	-- writes (it culls Enabled / Shadows). Any later server toggle of this
	-- light sets LightWanted too (see homePlacement.relight).
	l:SetAttribute("LightWanted",true)
	l:SetAttribute("LightHero",l.Shadows)
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

-------------------------------------------------------------------------------
-- Signs v2 (docs/DEPTH-CONTRACT.md §28): every sign is a floating, camera-
-- facing plaque. Signs.build(parent, cf, spec) -> anchor, model. cf is the
-- sign's ground point (its yaw no longer matters: the plaque always faces the
-- viewer). spec:
--   title, kicker, accent (Color3), width (studs, the old board width),
--   kind = hanging | shop | post | banner | plaque (default from
--   Signs.STYLE[title], else hanging), icon (shop: catalog shape of the trade,
--   drawn as a 2D glyph), arrows = {{label, to = Vector3}, ...} (post: rows
--   whose arrows point at real places in screen space), plate = false (post:
--   arrows only), theme (default: the island's theme).
-- Each sign is a Model "Sign <title>" (attributes SignArchetype, SignTitle,
-- SignTheme, SignVersion = 2; tag AetherSign) holding ONE invisible,
-- non-colliding anchor part (named after the title, SignAnchor = true, chest
-- height so prompts parented to it sit where players reach) and a BillboardGui
-- "SignBillboard" on it. No posts, brackets, plinths or meshes.
-- The billboard is laid out in fixed design pixels (text fitted exactly with
-- Signs.fit) in two forms: full (kicker ribbon in a "Detail" layer) and
-- compact (title plaque; banners a short "Compact" pennant). The client
-- (signs.client.lua + shared/SignView.lua) scales it as REF / distance
-- clamped per archetype and device, picks the form, declutters overlapping
-- plaques, fades it near MaxDistance, bobs it (not with reduced motion),
-- caps how many are visible (nearest N), turns post arrows toward their
-- destinations and brightens the aether crystal at night. Signs.settle steps
-- island signs clear of walls once the world is built.
-- Distinct from NPC nameplates (a dark rounded Gotham strip, "Nameplate"): a
-- metal-framed region-themed panel with a crest, a caps kicker ribbon and a
-- Merriweather / Fondamento title, a crystal and a drop shadow.
-------------------------------------------------------------------------------
local Signs={LIGHT=.15,BRIGHTNESS=1.25,MAX_DISTANCE=120,LANDMARK_DISTANCE=160,LINE=1.3,VERSION=2,ANCHOR_Y=2.5,PAD=16}
Signs.FONT={title="rbxasset://fonts/families/Merriweather.json",body="rbxasset://fonts/families/BuilderSans.json",
	banner="rbxasset://fonts/families/Fondamento.json"}
-- Region identities: panel (painted field), text, trim (inlay rule, divider),
-- metal (frame, corner caps, crest ring), stone (landmark plaques), crystal
-- (the aether crystal and its night glow), crest (painted region crest glyph).
Signs.THEMES={
	Quay={panel=C("1B2A44"),text=C("F6EBD0"),trim=C("D9B65C"),metal=C("C9A24E"),stone=C("D6D2C4"),crystal=C("8FE8FF"),crest="🧭"}, -- brass & navy
	Sunwheel={panel=C("5A3B22"),text=C("FFF1D0"),trim=C("E9C46A"),metal=C("D9A84A"),stone=C("E3D6B4"),crystal=C("FFE7A0"),crest="🌾"}, -- warm oak & wheat gold
	Brassfall={panel=C("2A2422"),text=C("F6E3C6"),trim=C("E0925A"),metal=C("B8733F"),stone=C("C9BDAE"),crystal=C("FFB27A"),crest="⚙️"}, -- copper & soot
	Mosswake={panel=C("2C3A24"),text=C("F1EED8"),trim=C("A9D98F"),metal=C("7FA86A"),stone=C("BFC6AE"),crystal=C("B8FF9E"),crest="🌿"}, -- living wood & moss
	Gloom={panel=C("241A38"),text=C("F0E6FF"),trim=C("B9A2EE"),metal=C("8E7BC0"),stone=C("B4ACC4"),crystal=C("D2B8FF"),crest="🔮"}, -- violet crystal
	Tide={panel=C("4F4B42"),text=C("F4F0E6"),trim=C("D8C9A3"),metal=C("7FC9C9"),stone=C("D4D8CF"),crystal=C("9FF0FF"),crest="🐚"}, -- driftwood & rope
	Tempest={panel=C("2B3240"),text=C("EEF3FF"),trim=C("8FB4FF"),metal=C("A8B6CC"),stone=C("BCC2CE"),crystal=C("BFD8FF"),crest="⚡"}, -- slate & storm-blue
	Cinder={panel=C("221E1E"),text=C("FFE8D6"),trim=C("FF8A3D"),metal=C("C0603A"),stone=C("3B3634"),crystal=C("FFB070"),crest="🔥"}, -- basalt & ember
	Crown={panel=C("ECE6DA"),text=C("2B2433"),trim=C("C9A042"),metal=C("E0B44E"),stone=C("EFEBE2"),crystal=C("FFE9A8"),crest="👑"}, -- marble & gold
	Warden={panel=C("2E2228"),text=C("F4E6E0"),trim=C("E08C78"),metal=C("AFA8A0"),stone=C("C4C0C8"),crystal=C("FFC2B0"),crest="🛡️"}, -- iron & crimson
	Skyreach={panel=C("1C3A44"),text=C("EAF8F6"),trim=C("8EE6CB"),metal=C("B8C6CF"),stone=C("D2DEE0"),crystal=C("B0FFF0"),crest="🦅"}, -- silver & sky
	Home={panel=C("3A2C22"),text=C("FBF0DA"),trim=C("E6C07A"),metal=C("C9A24E"),stone=C("D2CBBB"),crystal=C("9FF3D7"),crest="🏡"}, -- hearth oak
}
Signs.ISLAND_THEME={["Compass Quay"]="Quay",["Guild Terrace"]="Quay",["Mosswake Grove"]="Mosswake",["Meadow Reach"]="Sunwheel",
	["Windpine Grove"]="Mosswake",["Brassfall Quarry"]="Brassfall",["Cinder Shelf"]="Cinder",["Warden Reach"]="Warden",Skyreach="Skyreach",
	["Gloomhollow Caverns"]="Gloom",["Tidewater Shoals"]="Tide",["Tempest Spire"]="Tempest",["The Shattered Crown"]="Crown"}
-- Archetype per fixed sign title (call sites may override with spec fields).
Signs.STYLE={
	["Compass Quay"]={kind="plaque"},["Mooncrest Gardens"]={kind="plaque"},["Aether Museum"]={kind="plaque"},
	["Mosswake Grove"]={kind="plaque"},["Brassfall Quarry"]={kind="plaque"},["Warden Reach"]={kind="plaque"},
	["Guild Terrace"]={kind="plaque"},["Meadow Reach"]={kind="plaque"},["Cinder Shelf"]={kind="plaque"},Skyreach={kind="plaque"},
	["Windpine Grove"]={kind="plaque"},["Gloomhollow Caverns"]={kind="plaque"},["Tidewater Shoals"]={kind="plaque"},
	["Tempest Spire"]={kind="plaque"},["The Shattered Crown"]={kind="plaque"},
	["Market Row"]={kind="shop",icon="Seal"},["Artisans' Rise"]={kind="shop",icon="Anvil"},Moonpool={kind="shop",icon="Fish"},
	Aetherite={kind="shop",icon="AetherCrystal"},["Verdant Garden"]={kind="shop",icon="CropSheaf"},
	["Artificers' Row"]={kind="shop",icon="AetherCrystal"},["Make it yours"]={kind="shop",icon="Hatchet"},
	Shellwarden={kind="banner"},["Vault Gate"]={kind="banner"},["Crew Haven"]={kind="banner"},["Huntmaster Oriel"]={kind="banner"},
	["Sovereign's Dais"]={kind="banner"},["Eclipse Roost"]={kind="banner"},["Skybreach Ferry"]={kind="banner"},
	["Sky Harbor"]={kind="post"},["Skyreach passage"]={kind="post"},["Deep descent"]={kind="post"},
	Homeward={kind="hanging"},["Wayfarer's Rest"]={kind="plaque"},["Artisans' Row"]={kind="hanging"},
	["Builder's Terrace"]={kind="hanging"},["Commission Board"]={kind="hanging"},
}
-- Studs between a wall and a banner beside it (the quad turns with the camera).
Signs.WALL_GAP=4.2
Signs.KINDS={hanging=true,shop=true,post=true,banner=true,plaque=true,ledger=true}
-- Trade glyphs for shop plaques (the old 3D icon shapes, now painted).
Signs.ICON={Seal="🪙",Anvil="⚒️",Fish="🐟",AetherCrystal="💎",CropSheaf="🌾",Hatchet="🪓",Feather="🏹",Feast="🍲",Ingot="🧱",
	HideRoll="🧶",Boots="🥾",Charm="🔮"}
-- Design sizes in pixels at UIScale 1 (the client scales them with distance).
Signs.SIZE={wideMin=230,wideMax=400,bodyH=72,bannerW=204,postW=340,postRow=40}
-- Text sizes (px at scale 1). Titles, post titles, destinations and compact
-- banner titles draw at every scale: >= 23 px, so >= 10 px at the phone
-- floor (0.45). Kickers and full-banner titles draw only at scale >= 0.7.
Signs.TEXT={title={max=32,min=23},post={max=28,min=23},dest={max=25,min=23},kicker={max=16,min=15},
	bannerTitle={max=28,min=18},compactTitle={max=26,min=23}}
Signs.LIFT={hanging=3.4,shop=3.4,plaque=2.4,banner=4.6,post=3.0,shopAwning=4.9} -- studs above the anchor (billboard centre)
function Signs.theme(parent)
	local node=parent
	while node and node~=world and node~=islandsFolder and node~=workspace do
		local name=Signs.ISLAND_THEME[node.Name]
		if name then return name end
		if node:IsA("Model") and node:GetAttribute("Region")=="Home" then return "Home" end
		node=node.Parent
	end
	return "Quay"
end

-- Text fitting. Conservative em widths (wide serif caps); verify-signs re-runs
-- the same wrap with its own table, so a label is never sized past its box.
Signs.GLYPH={W=1.0,M=.96,m=.88,w=.8,[" "]=.3,i=.34,l=.34,j=.34,I=.44,t=.42,f=.42,r=.46,["."]=.32,[","]=.32,
	["'"]=.28,["•"]=.5,["/"]=.44,["-"]=.44,["+"]=.64,["·"]=.36}
function Signs.textWidth(text,size)
	local em=0
	for _,code in utf8.codes(text) do
		local ch=utf8.char(code)
		local w=Signs.GLYPH[ch]
		if not w then
			w=if string.match(ch,"^%u$") then .76 elseif string.match(ch,"^%l$") then .6 elseif string.match(ch,"^%d$") then .66 else .56
		end
		em+=w
	end
	return em*size
end
-- Greedy word wrap at `size`: line count and widest line.
function Signs.wrap(text,size,width)
	local lines,line,widest=1,"",0
	for word,gap in string.gmatch(text,"(%S+)(%s*)") do
		local trimmed=string.gsub(line,"%s+$","")
		if trimmed~="" and Signs.textWidth(trimmed.." "..word,size)>width*.94 then
			widest=math.max(widest,Signs.textWidth(trimmed,size))
			lines+=1
			line=word..gap
		else
			line..=word..gap
		end
	end
	widest=math.max(widest,Signs.textWidth((string.gsub(line,"%s+$","")),size))
	return lines,widest
end
-- Largest size (px) at which text fits w x h in at most maxLines lines.
function Signs.fit(text,w,h,maxLines,maxSize,minSize)
	for size=math.floor(maxSize),math.ceil(minSize),-1 do
		local lines,widest=Signs.wrap(text,size,w)
		-- 6% slack: Merriweather Bold runs close to the conservative em table.
		if lines<=maxLines and widest<=w*.94 and lines*size*Signs.LINE<=h then return size,lines,false end
	end
	return math.ceil(minSize),(Signs.wrap(text,math.ceil(minSize),w)),true
end
-- Separator "   /   " in kickers becomes a centred bullet; kickers are caps.
function Signs.kickerText(kicker) return string.upper((string.gsub(kicker or "","%s*/%s*","  •  "))) end

-- Painting ---------------------------------------------------------------
-- Every billboard has two forms the client switches between (shared/SignView):
--   full    (scale >= View.DETAIL): the plaque plus its "Detail" layer, a
--           kicker ribbon with a divider rule;
--   compact (scale < View.DETAIL, always on phones): the title plaque alone;
--           banners swap to a short pennant root "Compact".
-- Text sizes (Signs.TEXT) keep every label >= View.MIN_TEXT (10) rendered px
-- at the smallest scale of the form it is drawn in (verify-signs).
-- Gui attributes for the client's declutter: SignFull / SignCompact (visible
-- box at scale 1, Vector2) and SignCompactY (its centre offset, px).
do
local BLACK=C("05070A")
local function luminance(c) return .2126*c.R+.7152*c.G+.0722*c.B end
local function frame(parent,name,x,y,w,h,color,transparency,z,radius)
	local f=Instance.new("Frame")
	f.Name,f.BorderSizePixel,f.BackgroundColor3=name,0,color
	f.BackgroundTransparency=transparency or 0
	f.Position,f.Size=UDim2.fromOffset(math.floor(x+.5),math.floor(y+.5)),UDim2.fromOffset(math.floor(w+.5),math.floor(h+.5))
	f.ZIndex=z or 1
	if radius then
		local c=Instance.new("UICorner")
		c.CornerRadius=if radius<0 then UDim2.new(1,0,0,0).X else UDim2.new(0,radius,0,0).X -- (UDim via UDim2: no extra globals)
		c.Parent=f
	end
	f.Parent=parent
	return f
end
local function stroke(obj,color,thickness,transparency)
	local s=Instance.new("UIStroke")
	s.Color,s.Thickness,s.Transparency=color,thickness,transparency or 0
	s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	s.Parent=obj
	return s
end
-- UIGradient multiplies the background colour, so a graded frame is white and
-- its gradient carries the true colours (top -> bottom).
local function gradient(obj,top,bottom)
	obj.BackgroundColor3=Color3.new(1,1,1)
	local g=Instance.new("UIGradient")
	g.Color=ColorSequence.new(top,bottom)
	g.Rotation=90
	g.Parent=obj
	return g
end
local function diamond(parent,name,cx,cy,size,color,z,edge)
	local d=frame(parent,name,cx-size/2,cy-size/2,size,size,color,0,z)
	d.Rotation=45
	if edge then stroke(d,edge,1,.2) end
	return d
end
-- Metal: a brushed gradient (light lip, mid, dark foot).
local function metal(obj,m) gradient(obj,m:Lerp(cream,.4),m:Lerp(BLACK,.35)) end
-- Text styles per archetype (exactly one outline per label: a UIStroke, or
-- the offset highlight label "<name>Shadow" on engraved / inked faces).
--   painted     theme text, ink UIStroke (outlined display)
--   inked       dark ink on parchment, cream highlight below
--   engraved    dark cut letters on stone, light highlight below
--   embroidered gold thread on cloth, dark UIStroke
-- o.on names the frame the label is read against (verify-signs contrast).
local function label(root,name,text,x,y,w,h,o)
	w,h=math.floor(w),math.floor(h) -- fit the box the label really gets
	local size,lines,overflow=Signs.fit(text,w,h,o.lines or 1,o.max,o.min)
	local function make(labelName,dx,dy,color,transparency,z)
		local t=Instance.new("TextLabel")
		t.Name,t.BackgroundTransparency,t.Text=labelName,1,text
		t.TextColor3,t.TextTransparency,t.TextSize=color,transparency,size
		t.TextScaled,t.TextWrapped,t.RichText=false,true,false
		t.TextXAlignment=o.align or Enum.TextXAlignment.Center
		t.TextYAlignment=Enum.TextYAlignment.Center
		t.Position,t.Size=UDim2.fromOffset(math.floor(x+dx+.5),math.floor(y+dy+.5)),UDim2.fromOffset(w,h)
		t.ZIndex=z
		t.FontFace=Font.new(o.font,Enum.FontWeight.Bold)
		t.Parent=root
		return t
	end
	if o.shadow then make(name.."Shadow",0,math.max(1,math.floor(size*.07+.5)),o.shadow,o.shadowTransparency or .3,8) end
	local main=make(name,0,0,o.color,0,9)
	if not o.shadow then stroke(main,o.strokeColor or BLACK,o.thick or math.max(1,math.floor(size*.07+.5)),o.strokeTransparency or .15).ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual end
	main:SetAttribute("SignFitLines",lines)
	main:SetAttribute("SignPlain",text)
	main:SetAttribute("SignOn",o.on or "Panel")
	if overflow then main:SetAttribute("SignOverflow",true) end
	return main,size,lines
end
-- Fitted size and line count for a text that prefers one line (up to maxLines
-- at the floor size): returns size, lines and the box height it needs.
local function fitText(text,w,t,maxLines)
	local size,lines,overflow=Signs.fit(text,w,1e4,1,t.max,t.min)
	if overflow then size,lines=Signs.fit(text,w,1e4,maxLines or 2,t.min+2,t.min) end
	return size,lines,math.ceil(lines*size*Signs.LINE)+2
end
-- WCAG contrast; legible() walks a colour toward ink or cream until it reads
-- on its panel (titles 4.5:1, kickers 3:1; verify-signs re-measures).
local function relLum(c)
	local function ch(v) return if v<=.03928 then v/12.92 else ((v+.055)/1.055)^2.4 end
	return .2126*ch(c.R)+.7152*ch(c.G)+.0722*ch(c.B)
end
local function ratio(a,b)
	local la,lb=relLum(a),relLum(b)
	return (math.max(la,lb)+.05)/(math.min(la,lb)+.05)
end
-- A graded field spans field+12% cream (top) to field+35% ink (bottom): a
-- colour must read on both ends.
local function legible(color,panel,need)
	local top,bottom=panel:Lerp(cream,.12),panel:Lerp(BLACK,.35)
	local target=if relLum(panel)>.18 then BLACK else cream
	for k=0,1,.05 do
		local c=color:Lerp(target,k)
		if math.min(ratio(c,top),ratio(c,bottom))>=need+.15 then return c end
	end
	return target
end
local function textStyle(style,theme,accent,panel)
	local light=luminance(panel)>.45
	local ts
	if (style=="inked" or style=="engraved") and light then
		local ink2=if style=="engraved" then panel:Lerp(BLACK,.78) else C("2A2018")
		ts={color=ink2,shadow=panel:Lerp(cream,.7),shadowTransparency=.15}
	elseif light then
		ts={color=theme.text,shadow=panel:Lerp(cream,.7),shadowTransparency=.15}
	elseif style=="embroidered" then
		ts={color=C("F7DC8A"),strokeColor=BLACK,kick=accent:Lerp(cream,.62)}
	else
		-- Painted (or engraved on dark stone such as basalt): light letters, ink outline.
		ts={color=theme.text,strokeColor=BLACK}
	end
	ts.color=legible(ts.color,panel,4.5)
	if ts.kick then ts.kick=legible(ts.kick,panel,4.5) end
	return ts
end
-- Billboard shell: GW x GH visible content inside PAD padding (shadow, glow).
local function shell(anchorPart,GW,GH,lift,distance,kind)
	local P=Signs.PAD
	local gui=Instance.new("BillboardGui")
	gui.Name="SignBillboard"
	gui.Size=UDim2.fromOffset(GW+2*P,GH+2*P)
	gui.StudsOffsetWorldSpace=V(0,lift,0)
	gui.MaxDistance,gui.LightInfluence,gui.Brightness=distance,Signs.LIGHT,Signs.BRIGHTNESS
	gui.AlwaysOnTop,gui.ClipsDescendants=false,false
	gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("SignStyled",true)
	gui:SetAttribute("SignLift",lift)
	gui:SetAttribute("SignKind",kind)
	gui:SetAttribute("SignFull",Vector2.new(GW,GH))
	gui:SetAttribute("SignCompact",Vector2.new(GW,GH))
	gui:SetAttribute("SignCompactY",0)
	gui.Parent=anchorPart
	local function group(name)
		local root=Instance.new("CanvasGroup")
		root.Name,root.BackgroundTransparency,root.BorderSizePixel=name,1,0
		root.AnchorPoint,root.Position,root.Size=Vector2.new(.5,.5),UDim2.fromScale(.5,.5),UDim2.fromOffset(GW+2*P,GH+2*P)
		root.Parent=gui
		local scale=Instance.new("UIScale")
		scale.Name="Scale"
		scale.Parent=root
		return root
	end
	return gui,group("Sign"),P,group
end
-- The layer hidden in compact form (kicker ribbon, divider): full size, so
-- its children share the root's coordinates; drawn above the plaque.
local function detailLayer(root)
	local d=Instance.new("Frame")
	d.Name,d.BackgroundTransparency,d.BorderSizePixel="Detail",1,0
	d.Size,d.ZIndex=root.Size,10
	d.Parent=root
	return d
end
local function crystal(root,cx,cy,theme)
	-- Aether crystal set into the frame, with its glow (the client brightens it at night).
	local glow=frame(root,"Crystal glow",cx-14,cy-14,28,28,theme.crystal,.7,7,-1)
	glow:SetAttribute("DayTransparency",.7)
	glow:SetAttribute("NightTransparency",.35)
	diamond(root,"Crystal setting",cx,cy,15,theme.metal:Lerp(BLACK,.2),8)
	diamond(root,"Crystal",cx,cy,10,theme.crystal,9,cream)
end
-- Plaque body at (x, y), W x H: drop shadow, graded metal frame, field,
-- bevel, inlay, style dressing, corner caps and the crystal pendant.
local function dressing(root,x,y,W,H,theme,panel,style)
	frame(root,"Shadow soft",x-2,y+5,W+4,H+6,BLACK,.82,1,14)
	frame(root,"Shadow",x+3,y+6,W-2,H,BLACK,.62,1,10)
	local f=frame(root,"Frame",x,y,W,H,theme.metal,0,3,8)
	metal(f,theme.metal)
	stroke(f,theme.metal:Lerp(BLACK,.65),1.5,.1)
	local field=frame(root,"Panel",x+5,y+5,W-10,H-10,panel,0,4,5)
	gradient(field,panel:Lerp(cream,.12),panel:Lerp(BLACK,.3))
	if style=="painted" then
		-- Hardwood grain: faint darker streaks across the field.
		for i,k in ipairs({.3,.58,.81}) do frame(root,"Grain",x+9,y+5+(H-10)*k,W-18,i==2 and 2 or 1,panel:Lerp(BLACK,.5),.72,5) end
	elseif style=="inked" then
		-- Parchment: darker, burnt edges toward the rolls.
		for _,bx in ipairs({x+5,x+W-19}) do frame(root,"Burn",bx,y+5,14,H-10,C("8A6240"),.6,5) end
	elseif style=="engraved" then
		-- Stone: a carved recess (shadowed top edge, lit bottom lip).
		frame(root,"Recess shade",x+10,y+10,W-20,2,panel:Lerp(BLACK,.45),.3,5)
		frame(root,"Recess lip",x+10,y+H-12,W-20,2,panel:Lerp(cream,.6),.2,5)
	end
	-- Bevel: a lit top lip and a shaded foot inside the frame (carved depth).
	frame(root,"Bevel light",x+7,y+5,W-14,2,cream,.55,5)
	frame(root,"Bevel shade",x+7,y+H-7,W-14,2,BLACK,.45,5)
	local inlay=frame(root,"Inlay",x+9,y+9,W-18,H-18,panel,1,6,3)
	stroke(inlay,theme.trim,1.5,.2)
	for _,c in ipairs({{x+3,y+3},{x+W-3,y+3},{x+3,y+H-3},{x+W-3,y+H-3}}) do
		diamond(root,"Corner cap",c[1],c[2],11,theme.metal:Lerp(cream,.3),7,theme.metal:Lerp(BLACK,.6))
	end
	crystal(root,x+W/2,y+H-1,theme)
end
-- Painted crest medallion: metal ring, accent field, the region crest (or the
-- shop's trade glyph).
local function crest(root,cx,cy,d,theme,accent,glyph)
	local ring=frame(root,"Crest",cx-d/2,cy-d/2,d,d,theme.metal,0,7,-1)
	metal(ring,theme.metal)
	stroke(ring,theme.metal:Lerp(BLACK,.6),1.5,.1)
	local f=frame(root,"Crest field",cx-d*.39,cy-d*.39,d*.78,d*.78,accent:Lerp(BLACK,.45),0,8,-1)
	gradient(f,accent:Lerp(BLACK,.2),accent:Lerp(BLACK,.65))
	local t=Instance.new("TextLabel")
	t.Name,t.BackgroundTransparency,t.Text="Crest glyph",1,glyph
	t.TextSize,t.TextScaled,t.TextWrapped=math.floor(d*.46),false,false
	t.TextColor3=cream
	t.Position,t.Size=UDim2.fromOffset(math.floor(cx-d/2),math.floor(cy-d/2)),UDim2.fromOffset(math.floor(d),math.floor(d))
	t.ZIndex=9
	t.FontFace=Font.new(Signs.FONT.body,Enum.FontWeight.Bold)
	t.Parent=root
end
local function divider(parent,x,y,w,accent)
	frame(parent,"Divider",x,y,w,2,accent,0,7)
	diamond(parent,"Divider stud",x,y+1,6,accent,8)
	diamond(parent,"Divider stud",x+w,y+1,6,accent,8)
end
-- Kicker ribbon (Detail layer): a dark metal tab over the plaque's top edge,
-- caps kicker, a divider rule with studs along its foot.
local function ribbon(detail,x,y,w,h,kicker,lines,theme,accent)
	local back=theme.panel:Lerp(BLACK,.55)
	local r=frame(detail,"Ribbon",x,y,w,h,back,0,2,5)
	gradient(r,back:Lerp(cream,.08),back:Lerp(BLACK,.3))
	stroke(r,theme.trim,1.5,.25)
	divider(detail,x+10,y+h-4,w-20,accent)
	local T=Signs.TEXT.kicker
	label(detail,"Kicker",kicker,x+12,y+3,w-24,h-8,{lines=lines,max=T.max,min=T.min,font=Signs.FONT.body,
		color=legible(accent:Lerp(cream,.55),back,4.5),thick=1,strokeTransparency=.35,on="Ribbon"})
end
-- Kicker ribbon height for a text area width (one or two lines).
local function ribbonFit(kicker,w)
	local T=Signs.TEXT.kicker
	local lines=if select(3,Signs.fit(kicker,w,1e4,1,T.max,T.min)) then 2 else 1
	return math.ceil(lines*T.max*Signs.LINE)+12,lines
end

-- Wide plaque (hanging, shop, landmark, ledger title): crest left, title; the
-- kicker ribbon above.
local function paintWide(anchorPart,spec,theme,lift,distance,kindName)
	local kind=spec.kind
	local S,T=Signs.SIZE,Signs.TEXT
	local W=math.floor(math.clamp((spec.width or 9)*(if kind=="plaque" then 36 else 32),S.wideMin,S.wideMax))
	local d=50
	local function textW(width) return width-42-d end
	local kick=Signs.kickerText(spec.kicker)
	local hasKicker=kick~=""
	-- Grow (up to wideMax) until the title reads on one line and the kicker on one.
	while W<S.wideMax and (select(3,Signs.fit(spec.title,textW(W),1e4,1,T.title.max,T.title.min))
		or (hasKicker and select(3,Signs.fit(kick,W-52,1e4,1,T.kicker.max,T.kicker.min)))) do
		W=math.min(S.wideMax,W+10)
	end
	local _,_,th=fitText(spec.title,textW(W),T.title,2)
	local BH=math.max(S.bodyH,th+26)
	local RH,kl=ribbonFit(kick,W-52)
	local top=if hasKicker then RH-6 else 0 -- the ribbon overlaps the plaque's top edge
	local GH=top+BH
	local style=if kind=="shop" then "inked" elseif kind=="plaque" then "engraved" else "painted"
	local panel=if kind=="shop" then C("EADDBA") elseif kind=="plaque" then theme.stone else theme.panel
	local gui,root,P=shell(anchorPart,W,GH,lift or spec.lift or Signs.LIFT[kind],distance or (if kind=="plaque" then Signs.LANDMARK_DISTANCE else Signs.MAX_DISTANCE),kindName or kind)
	gui:SetAttribute("SignCompact",Vector2.new(W,BH))
	gui:SetAttribute("SignCompactY",top/2)
	local x,y=P,P+top
	dressing(root,x,y,W,BH,theme,panel,style)
	if kind=="shop" then
		-- Scroll rolls over both ends of the frame.
		for _,rx in ipairs({x-5,x+W-9}) do
			local roll=frame(root,"Roll",rx,y-4,14,BH+8,C("D9C79C"),0,7,7)
			gradient(roll,C("F4E8C8"),C("A88B5E"))
			stroke(roll,C("6E4A30"),1,.3)
		end
	end
	local ts=textStyle(style,theme,spec.accent,panel)
	local glyph=if kind=="shop" then (Signs.ICON[spec.icon or ""] or "✦") else theme.crest
	crest(root,x+14+d/2,y+BH/2,d,theme,spec.accent,glyph)
	local x0=x+14+d+12
	local w=x+W-16-x0
	local size,lines=fitText(spec.title,w,T.title,2)
	label(root,"Title",spec.title,x0,y+(BH-th)/2,w,th,{lines=lines,max=size,min=size,font=Signs.FONT.title,align=Enum.TextXAlignment.Left,
		color=ts.color,shadow=ts.shadow,shadowTransparency=ts.shadowTransparency,strokeColor=ts.strokeColor})
	if hasKicker then ribbon(detailLayer(root),x+14,P,W-28,RH,kick,kl,theme,spec.accent) end
	return gui
end
-- Banner (guild, boss, dungeon, minigame, crew, faction): a portrait cloth on
-- a crossbar with an embroidered border, swallowtail, tassels and a crest;
-- its compact form is a short title pennant (root "Compact").
local function tails(root,P,W,y,cloth,theme)
	local tw=W/2/1.414
	for _,x in ipairs({P+W/4,P+3*W/4}) do
		diamond(root,"Tail braid",x,y,tw+6,theme.metal,2)
		diamond(root,"Tail",x,y,tw,cloth,4)
		local tassel=frame(root,"Tassel",x-5,y+tw*.71-2,10,14,theme.metal:Lerp(cream,.25),0,5,-1)
		metal(tassel,theme.metal)
	end
end
local function crossbar(root,P,W,theme)
	local bar=frame(root,"Crossbar",P-10,P+4,W+20,9,theme.metal,0,7,4)
	metal(bar,theme.metal)
	for _,x in ipairs({P-12,P+W+12}) do diamond(root,"Finial",x,P+8,12,theme.metal:Lerp(cream,.35),8,theme.metal:Lerp(BLACK,.6)) end
	crystal(root,P+W/2,P+8,theme)
end
local function cloth(root,P,W,top,h,clothColor,theme)
	frame(root,"Shadow",P+4,top+6,W-4,h,BLACK,.62,1,8)
	local f=frame(root,"Frame",P,top,W,h,theme.metal,0,3,4)
	metal(f,theme.metal)
	local field=frame(root,"Panel",P+5,top+4,W-10,h-6,clothColor,0,5,3)
	gradient(field,clothColor:Lerp(cream,.1),clothColor:Lerp(BLACK,.35))
	local stitch=frame(root,"Inlay",P+10,top+9,W-20,h-16,clothColor,1,6,2)
	stroke(stitch,theme.trim,2,.1)
	local inner=frame(root,"Stitch",P+15,top+14,W-30,h-26,clothColor,1,6,2)
	stroke(inner,C("F7DC8A"),1,.55)
end
local function paintBanner(anchorPart,spec,theme)
	local S,T=Signs.SIZE,Signs.TEXT
	local W=S.bannerW
	local clothColor=spec.accent:Lerp(C("0C0A12"),.7)
	local ts=textStyle("embroidered",theme,spec.accent,clothColor)
	local w=W-40
	-- Full form: crest, title (<= 3 lines), divider, kicker (<= 5 lines).
	local tsize,tlines,th=fitText(spec.title,w,T.bannerTitle,3)
	local kick=Signs.kickerText(spec.kicker)
	local ksize,klines=Signs.fit(kick,w,1e4,5,T.kicker.max,T.kicker.min)
	local kh=math.ceil(klines*ksize*Signs.LINE)+2
	local d=52
	local clothH=22+d+8+th+14+kh+16
	local GH=12+clothH+26
	-- Compact form: title only (<= 3 lines at the phone floor).
	local csize,clines,ch=fitText(spec.title,w,T.compactTitle,3)
	local cClothH=ch+30
	local cGH=12+cClothH+18
	local gui,root,P,group=shell(anchorPart,W,GH,Signs.LIFT.banner,Signs.MAX_DISTANCE,"banner")
	gui:SetAttribute("SignCompact",Vector2.new(W,cGH))
	gui:SetAttribute("SignCompactY",(cGH-GH)/2)
	local top=P+12 -- cloth starts under the crossbar
	tails(root,P,W,top+clothH,clothColor,theme)
	cloth(root,P,W,top,clothH,clothColor,theme)
	crossbar(root,P,W,theme)
	crest(root,P+W/2,top+22+d/2,d,theme,spec.accent,theme.crest)
	local x0=P+20
	local ty=top+22+d+8
	label(root,"Title",spec.title,x0,ty,w,th,{lines=tlines,max=tsize,min=tsize,font=Signs.FONT.banner,color=ts.color,strokeColor=ts.strokeColor})
	local detail=detailLayer(root)
	divider(detail,x0+w*.2,ty+th+6,w*.6,spec.accent)
	label(detail,"Kicker",kick,x0,ty+th+14,w,kh,{lines=klines,max=ksize,min=ksize,font=Signs.FONT.body,
		color=ts.kick,thick=1,strokeTransparency=.4})
	-- The short pennant.
	local compact=group("Compact")
	compact.Visible=false
	tails(compact,P,W,top+cClothH-4,clothColor,theme)
	cloth(compact,P,W,top,cClothH,clothColor,theme)
	crossbar(compact,P,W,theme)
	label(compact,"Title",spec.title,x0,top+14,w,ch,{lines=clines,max=csize,min=csize,font=Signs.FONT.banner,color=ts.color,strokeColor=ts.strokeColor})
	return gui
end
-- Direction post (no post): a floating panel with a title head and one row
-- per destination; each row's "Arrow" (attribute SignArrowTo) is turned by
-- the client toward its destination relative to the camera. The kicker rides
-- a ribbon above (Detail).
local function paintPost(anchorPart,spec,theme)
	local S,T=Signs.SIZE,Signs.TEXT
	local arrows=spec.arrows or {}
	local W=S.postW
	local plate=spec.plate~=false
	local d=44
	local hw=W-16-(14+d+10)
	local tsize,tlines,th=fitText(spec.title,hw,T.post,2)
	local head=if plate then math.max(d+20,th+20) else 10
	local rows={}
	local H=head
	for i,arrow in ipairs(arrows) do
		local size,lines,rh=fitText(arrow.label,W-80,T.dest,2)
		rows[i]={y=H,h=math.max(S.postRow,rh+10),size=size,lines=lines,th=rh}
		H+=rows[i].h
	end
	H+=10
	local kick=Signs.kickerText(spec.kicker)
	local hasKicker=plate and kick~=""
	local RH,kl=ribbonFit(kick,W-52)
	local top=if hasKicker then RH-6 else 0
	local GH=top+H
	local gui,root,P=shell(anchorPart,W,GH,Signs.LIFT.post+(#arrows-1)*.35,Signs.MAX_DISTANCE,"post")
	gui:SetAttribute("SignCompact",Vector2.new(W,H))
	gui:SetAttribute("SignCompactY",top/2)
	local x,y=P,P+top
	dressing(root,x,y,W,H,theme,theme.panel,"painted")
	local ts=textStyle("painted",theme,spec.accent,theme.panel)
	if plate then
		crest(root,x+14+d/2,y+head/2,d,theme,spec.accent,theme.crest)
		local x0=x+14+d+10
		label(root,"Title",spec.title,x0,y+(head-th)/2,hw,th,{lines=tlines,max=tsize,min=tsize,font=Signs.FONT.title,color=ts.color,
			strokeColor=ts.strokeColor,align=Enum.TextXAlignment.Left})
	end
	for i,arrow in ipairs(arrows) do
		local r=rows[i]
		local ry=y+r.y
		local row=frame(root,"Row plate",x+12,ry+3,W-24,r.h-6,theme.panel:Lerp(cream,.08),0,6,4)
		stroke(row,theme.trim,1,.55)
		-- Arrow glyph: a rotating holder (0 = pointing right) with a shaft and head.
		local holder=frame(root,"Arrow",x+18,ry+r.h/2-14,28,28,theme.panel,1,8)
		holder:SetAttribute("SignArrowTo",arrow.to)
		frame(holder,"Shaft",2,12,21,4,spec.accent,0,9)
		frame(holder,"Head",13.5,7.5,12,4,spec.accent,0,9).Rotation=45
		frame(holder,"Head lower",13.5,16.5,12,4,spec.accent,0,9).Rotation=-45
		label(root,"Destination",arrow.label,x+54,ry+(r.h-r.th)/2,W-80,r.th,{lines=r.lines,max=r.size,min=r.size,font=Signs.FONT.title,
			color=ts.color,strokeColor=ts.strokeColor,align=Enum.TextXAlignment.Left})
	end
	if hasKicker then ribbon(detailLayer(root),x+14,P,W-28,RH,kick,kl,theme,spec.accent) end
	return gui
end

local placedBillboards={}
local PAINT={hanging=paintWide,shop=paintWide,plaque=paintWide,banner=paintBanner,post=paintPost}
-- A title billboard on a ledger board (normal wide shell, SignKind "ledger").
function Signs.ledgerTitle(board,spec,theme,lift)
	spec.kind="hanging"
	return paintWide(board,spec,theme,lift,Signs.MAX_DISTANCE,"ledger")
end
function Signs.build(parent,cf,spec)
	local style=Signs.STYLE[spec.title] or {}
	spec.kind=spec.kind or style.kind or "hanging"
	if not PAINT[spec.kind] then spec.kind="hanging" end
	spec.icon=spec.icon or style.icon
	spec.accent=spec.accent or brass
	spec.kicker=spec.kicker or ""
	-- A sign named after a region wears that region's colours wherever it
	-- stands (Guild Terrace gate plaques, avenue posts); others take their island's.
	local themeName=spec.theme or Signs.ISLAND_THEME[spec.title] or Signs.theme(parent)
	if not Signs.THEMES[themeName] then themeName="Quay" end
	local theme=Signs.THEMES[themeName]
	local holder=group("Sign "..spec.title,parent)
	holder:SetAttribute("SignArchetype",spec.kind)
	holder:SetAttribute("SignTitle",spec.title)
	holder:SetAttribute("SignTheme",themeName)
	holder:SetAttribute("SignVersion",Signs.VERSION)
	-- Streams in as one unit, so the client never sees a billboard without its anchor.
	pcall(function() holder.ModelStreamingMode=Enum.ModelStreamingMode.Atomic end)
	Tags:AddTag(holder,"AetherSign")
	-- The only part: an invisible, non-colliding anchor at chest height.
	local anchorPart=part(holder,spec.title,V(1,1,1),CFrame.new(cf.Position+V(0,Signs.ANCHOR_Y,0)),theme.metal,SM,false)
	anchorPart.Transparency,anchorPart.CastShadow,anchorPart.CanQuery=1,false,false
	anchorPart:SetAttribute("SignAnchor",true)
	local gui=PAINT[spec.kind](anchorPart,spec,theme)
	-- Two plaques that would float into each other: the later one stacks
	-- clear above the earlier one (its full height plus a margin).
	local here=anchorPart.CFrame.Position
	for i=#placedBillboards,1,-1 do
		local other=placedBillboards[i]
		if not other.Parent or not other.Parent.Parent then table.remove(placedBillboards,i) continue end
		local o=other.Parent.CFrame.Position+other.StudsOffsetWorldSpace
		local c=here+gui.StudsOffsetWorldSpace
		if V(o.X-c.X,0,o.Z-c.Z).Magnitude<=3.5 and math.abs(o.Y-c.Y)<=3 then
			local lift=o.Y-here.Y+3.4
			gui.StudsOffsetWorldSpace=V(0,lift,0)
			gui:SetAttribute("SignLift",lift)
		end
	end
	table.insert(placedBillboards,gui)
	-- QC L6: a destroyed sign (home or crew island torn down) leaves the list.
	pcall(function()
		holder.Destroying:Connect(function()
			local i=table.find(placedBillboards,gui)
			if i then table.remove(placedBillboards,i) end
		end)
	end)
	Signs.placed=placedBillboards
	return anchorPart,holder
end
end
-- QC M4: after the static world is built, nudge every island sign whose
-- billboard floats too close (horizontally) to a wall,
-- roof, awning or stall box out into the open: the camera-facing quad turns
-- with the view and would otherwise swing into it. Prompts on the anchor ride along.
Signs.WALLISH={"wall","lintel","roof","awning","canvas","facade","gable","eave","door","window","stall"}
-- The gap grows with the plaque: half its compact width as a phone draws it
-- 18 studs away (0.55 scale, 70° FOV, 390 px tall), the widest it gets in world terms nearby.
function Signs.settle(root)
	for _,gui in ipairs(Signs.placed or {}) do
		local box=gui:GetAttribute("SignCompact")
		local need=math.max(Signs.WALL_GAP+.8,(if typeof(box)=="Vector2" then box.X else 300)*.55*18*1.4/390/2+.3)
		local halfH=(if typeof(box)=="Vector2" then box.Y else 100)*.55*18*1.4/390/2+.2
		local start=gui.Parent and gui.Parent:IsA("BasePart") and gui.Parent.CFrame.Position
		local anchorPart=gui.Parent
		local island=anchorPart and anchorPart.Parent and anchorPart:IsDescendantOf(root) and anchorPart
		while island and island.Parent~=root do island=island.Parent end
		if island then
			local boxes={}
			for _,p in ipairs(island:GetDescendants()) do
				if p:IsA("BasePart") and p.Transparency<.9 and not p:IsDescendantOf(anchorPart.Parent) then
					local n=string.lower(p.Name)
					for _,w in ipairs(Signs.WALLISH) do
						if string.find(n,w,1,true) then table.insert(boxes,p) break end
					end
				end
			end
			for _=1,4 do
				local moved=false
				for _,b in ipairs(boxes) do
					local c=anchorPart.CFrame.Position+gui.StudsOffsetWorldSpace
					local o=b.CFrame:PointToObjectSpace(c)
					local h=b.Size/2
					-- Boxes the plaque floats clear above (stall awnings) or below are left alone.
					if o.Y-h.Y<halfH and h.Y+o.Y>-halfH then
						local q=b.CFrame:PointToWorldSpace(V(math.clamp(o.X,-h.X,h.X),math.clamp(o.Y,-h.Y,h.Y),math.clamp(o.Z,-h.Z,h.Z)))
						local away=V(c.X-q.X,0,c.Z-q.Z)
						local dist=away.Magnitude
						if dist<need then
							if dist<1e-3 then away=V(c.X-b.CFrame.Position.X,0,c.Z-b.CFrame.Position.Z) end
							if away.Magnitude<1e-3 then away=V(1,0,0) end
							local to=anchorPart.CFrame.Position+away.Unit*(need-dist+.05)
							-- Never wander more than 6 studs from where the sign was placed.
							if start and (to-start).Magnitude<=6 then
								anchorPart.CFrame=anchorPart.CFrame+away.Unit*(need-dist+.05)
								moved=true
							end
						end
					end
				end
				if not moved then break end
			end
		end
	end
end
-- Legacy entry points (every call site goes through Signs.build).
local function signAt(parent,cf,title,kicker,accent,width,opts)
	local spec=opts or {}
	spec.title,spec.kicker,spec.accent,spec.width=title,kicker,accent,width
	return (Signs.build(parent,cf,spec))
end
local function sign(parent,pos,title,kicker,accent,yaw,width,opts)
	return signAt(parent,CFrame.new(pos)*CFrame.Angles(0,math.rad(yaw or 0),0),title,kicker,accent,width,opts)
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
-- World Art (§30): the hull is two forged meshes instead of ~20 primitive
-- slabs: the foundation carries the cliff wall (strata, grass lip, vines) and
-- one "Island underside" cylinder carries the keel (tapered strata, hanging
-- spires, roots / crystals / ember seams). Both stay visible as the fallback.
local HULL_KEEL={["Gloomhollow Caverns"]="IslandKeelCrystal",["Tempest Spire"]="IslandKeelCrystal",["The Shattered Crown"]="IslandKeelCrystal",
	["Cinder Shelf"]="IslandKeelEmber",["Brassfall Quarry"]="IslandKeelEmber"}
local function island(name,pos,r,opts)
	opts=opts or {}
	local m=Instance.new("Model")
	m.Name=name
	m.Parent=opts.parent or islandsFolder
	local stone,stratum=opts.stone or rock,opts.stratum or shale
	disk(m,"Meadow",pos-V(0,.25,0),r+.1,.5,opts.top or turf,opts.ground or Enum.Material.Grass,true)
	local grassy=(opts.ground or Enum.Material.Grass)==Enum.Material.Grass or opts.ground==LEAF
	-- The forged cliff (fit box = this cylinder, top at its top) must never
	-- reach into the meadow slab (top 0, bottom -0.5): its strata, cap and the
	-- grass lip (up to +0.52 above the fit top) otherwise clip through the grass.
	-- So the foundation top sits below the meadow bottom (grass lip: -0.6, the
	-- bare cliff's rubble crown: -0.9) and its radius puts the lip's inner edge
	-- (0.99 x radius) just outside the meadow's side wall.
	local drop=if grassy then .6 else .9
	local foundation=disk(m,"Floating foundation",pos-V(0,drop+3,0),(r+.15)/.99,6,stone,ST,true)
	meshSlot(foundation,opts.cliff or (if grassy then "IslandCliff" else "IslandCliffBare"),stone)
	-- Keel depth grows with the island (deep spires under the big isles).
	local depth=math.clamp(r*.55+6,10,62)
	local keel=disk(m,"Island underside",pos-V(0,6.2+depth/2,0),(r-.4)*.92,depth,darken(stone,.1),ST,false)
	meshSlot(keel,opts.keelShape or HULL_KEEL[name] or "IslandKeel",stone)
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
				part(m,"Shore ledge",V(w,1.2,w*.7),CFrame.new(pos+radial*(r+w*.18)-V(0,1.25,0))*CFrame.Angles(0,-a+hash(i,9),0),opts.ledge or lighten(stone,.15),ST,false)
			end
		end
		local stones=math.clamp(math.floor(r/9),3,12)
		for i=1,stones do
			local a=(i+.5+hash(i,13)*.4)*2*math.pi/stones
			if not angleNear(a,clear,0) then
				local radial=V(math.cos(a),0,math.sin(a))
				local s=1.6+hash(i,17)*1.6
				local boulder=part(m,"Shore boulder",V(2*s,1.4*s,1.7*s),CFrame.new(pos+radial*(r-3.2)+V(0,.45*s,0))*CFrame.Angles(.1,a*3,.12),i%3==0 and stratum or lighten(stone,.08),ST,true)
				meshSlot(boulder,"Rock")
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
			if i%3==1 then meshSlot(slab,"CliffRock") end
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
		if i==1 then meshSlot(stone,"Rock") end
	end
	return m,water
end
local function outcrop(parent,c,s,seed)
	local m=group("Rock outcrop",parent)
	seed=seed or 0
	local main=part(m,"Outcrop rock",V(4.5,3.6,4)*s,CFrame.new(c+V(0,1.2*s,0))*CFrame.Angles(.1,seed,.15),rock,ST,true)
	part(m,"Outcrop rock",V(3,2.4,2.8)*s,CFrame.new(c+V(2.6*s,.7*s,1.4*s))*CFrame.Angles(-.12,seed+1.3,.1),shale,ST,true)
	part(m,"Outcrop rock",V(2.2,1.6,2)*s,CFrame.new(c+V(-2.2*s,.5*s,1.8*s))*CFrame.Angles(.2,seed+2.1,-.1),darken(rock,.15),ST,false)
	meshSlot(main,"RockOutcrop",nil,true)
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
	meshSlot(trunk,shapeName,tint,true,"Uniform")
	return m
end
local function bush(parent,c,s,color)
	local b=ball(parent,"Shrub",c+V(0,.9*s,0),2.6*s,color or C("6C9A58"),LEAF)
	meshSlot(b,"Bush",color)
	return b
end
local function flowers(parent,c,r,color,lift)
	return disk(parent,"Wildflowers",c+V(0,(lift or .07)-.03,0),r,.06,color or rose,Enum.Material.Fabric,false)
end
local function lamp(parent,pos)
	local m=group("Lamp post",parent)
	block(m,"Lamp foot",pos+V(0,.3,0),V(1.4,.6,1.4),ink,ST,false)
	local mast=block(m,"Bronze mast",pos+V(0,2.1,0),V(.25,3.7,.25),brass,MT,false)
	meshSlot(mast,"Lamp",nil,true,"Uniform")
	local lantern=sculpture(m,"Aether lantern",pos+V(0,4,0),"Lantern",0.7)
	light(lantern,warm,1.2,18,{kind="SpotLight",face=Enum.NormalId.Bottom,angle=120,night=true})
	return m
end
-- Bridges (World Art §30): the collider deck, two invisible guards and one
-- invisible slot box carrying the span mesh: "RopeBridge" (rope-and-plank with
-- sagging handrails), "StoneArchBridge" (paved arch with balustrades) or
-- "CrystalBridge" (glass light-bridge; Tint = the region's crystal colour).
-- The deck stays visible (dark) under the planks as the fallback and shadow gap.
local BRIDGE_STYLE={RopeBridge={top=3.6,low=1},StoneArchBridge={top=3.4,low=3.4},CrystalBridge={top=3.8,low=1.6}}
local function bridge(parent,a,b,style,tint)
	style=if BRIDGE_STYLE[style] then style else "RopeBridge"
	local dir=(b-a).Unit
	-- Decks reach 1.5 studs onto each meadow (their top is above it).
	a,b=a-dir*1.5,b+dir*1.5
	local side=V(-dir.Z,0,dir.X)
	local length=(b-a).Magnitude
	-- Deck top 0.08 above both meadows so its ends never share a plane with them.
	local cf=CFrame.lookAt((a+b)/2-V(0,.17,0),b-V(0,.17,0))
	local deck=part(parent,"Continuous bridge deck",V(7,.5,length),cf,if style=="StoneArchBridge" then C("6F6A62") else darken(timber,.45),if style=="StoneArchBridge" then ST else WO,true)
	deck:SetAttribute("BridgeStyle",style)
	for _,s in ipairs({-1,1}) do
		-- Invisible collider behind the rail: the void is only crossed on the deck.
		local guard=part(parent,"Bridge guard",V(.4,7,length+1),CFrame.lookAt((a+b)/2+side*3.9*s+V(0,3.5,0),b+side*3.9*s+V(0,3.5,0)),cream,SM,true)
		guard.Transparency,guard.CastShadow=1,false
	end
	local dims=BRIDGE_STYLE[style]
	-- The span rides the deck's own pitch (sloped bridges, e.g. Brassfall ->
	-- Cinder Shelf): centred on the deck's top face, offset along its up vector.
	local span=part(parent,"Bridge span",V(8.4,dims.top+dims.low,length),cf*CFrame.new(0,.25+(dims.top-dims.low)/2,0),cream,SM,false)
	span.Transparency,span.CastShadow,span.CanQuery=1,false,false
	meshSlot(span,style,tint)
	return deck,span
end

-------------------------------------------------------------------------------
-- Legacy gather props and stalls.
-------------------------------------------------------------------------------
local function windpine(parent,pos,scale,owner)
	local m=group("Windpine",parent)
	local trunk=block(m,"Heartwood",pos+V(0,2.6*scale,0),V(1.2,5.2,1.2)*scale,timber,WO,true)
	trunk.Transparency=1
	sculpture(m,"Sculpted windpine",pos+V(0,2.6*scale,0),"WindpineCrown",scale)
	Node.gather(trunk,"Timber",nil,owner)
end
local function ore(parent,pos)
	local m=group("Copperstone vein",parent)
	local base=disk(m,"Ore seam",pos+V(0,.4,0),2.5,.8,shale,ST,false)
	slotBox(m,"Ore seam mesh",pos,V(5,2.4,4.4),"OreVein",C("C98D4F"))
	sculpture(m,"Faceted copper cluster",pos+V(0,1.4,0),"AetherCrystal",1)
	Node.gather(base,"Ore")
end
local function herb(parent,pos)
	local m=group("Meadow Herb patch",parent)
	local bed=disk(m,"Herb bed",pos+V(0,.15,0),2.3,.3,navy,ST,false)
	slotBox(m,"Herb bed mesh",pos,V(4.6,1.6,4.6),"CropBed",mint)
	for i=1,6 do
		local a=i*1.8
		local p=pos+V(math.cos(a)*1.5,.65,math.sin(a)*1.5)
		sculpture(m,"Sculpted moonbloom",p,"Moonbloom",.65,i*50)
	end
	Node.gather(bed,"Herb")
end
-- Stall facing `toward`: counter, awning (strips abut, never overlap) and a
-- header sign over the customer side.
local function marketStall(parent,pos,toward,name,verb,action,item,accent,kicker,icon)
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
	meshSlot(counter,"MarketStall",accent,true)
	-- Shop sign (§28) floating over the awning's front edge, clear above the
	-- canvas (QC M4: the camera-facing quad never dips into the awning).
	signAt(m,at(cf,0,.6,-3.3),name,kicker or "COMPASS QUAY   /   SERVICES",accent,8,{kind="shop",icon=icon or "Seal",lift=Signs.LIFT.shopAwning})
	if verb then prompt(counter,verb,name,action,item) end
	return m,cf
end

-------------------------------------------------------------------------------
-- Building kit (World Art pass 2, docs/DEPTH-CONTRACT.md §40). Every house is
-- one forged mesh from BUILDING_KIT (generated from art/building-shapes.cjs):
--   facade   one solid collider block (w x h x d, plaster: the primitive
--            fallback) named "Roofed house" (the minimap draws it as a roof);
--   walkin   a hollow hall: "Roofed hall floor" (the mesh host, ShapeOwnsModel)
--            plus "Hall wall" / "Hall lintel" colliders that leave the mesh's
--            door opening free, a furnished interior (its counter collider
--            hosts the interior mesh) and, where the light caps allow, one
--            warm night light inside;
--   interior a furnishing set hosted by its counter collider ("Counter").
-- Host ShapeBox / ShapeBoxOffset = the mesh's fit box, so the forge maps the
-- authored building 1:1 onto the colliders. Every building host carries
-- BuildingType, GlowSite = "window" (§35 pooled spill light at night) and
-- WindowGlow ("x,y,z,w,h,ry;..." pane rects in the host frame; the lighting
-- director lights the panes after dusk, §40) and the tag AetherBuilding.
-------------------------------------------------------------------------------
local Buildings={PLASTER=C("E6DCC6"),FLOOR=C("8A6240"),LIGHT=C("FFC27A"),hosts={}}
-- Clearance box of a part: its declared mesh box (ShapeBox / ShapeBoxOffset:
-- sign frames, buildings) when it has one, else the part itself. Every
-- placement search after the settlements uses it (§40 QC L2), like the
-- settlement index, so nothing lands inside a house's roof / porch overhang.
function Buildings.box(obj)
	local cf,sz=obj.CFrame,obj.Size
	local declared=obj:GetAttribute("ShapeBox")
	if typeof(declared)=="Vector3" then
		local offset=obj:GetAttribute("ShapeBoxOffset")
		cf=cf*CFrame.new(if typeof(offset)=="Vector3" then offset else V(0,0,0))
		sz=declared
	end
	return cf,sz
end
do
	local B=Buildings
	function B.fitOf(def)
		local lo=V(def.fit[1][1],def.fit[1][2],def.fit[1][3])
		local hi=V(def.fit[2][1],def.fit[2][2],def.fit[2][3])
		return (lo+hi)/2,hi-lo,lo,hi
	end
	-- Mesh slot on a host whose centre sits at `hostAt` in the building frame.
	local function slot(host,name,def,hostAt,tint)
		local centre,size=B.fitOf(def)
		host:SetAttribute("Shape",name)
		host:SetAttribute("ShapeBox",size)
		host:SetAttribute("ShapeBoxOffset",centre-hostAt)
		if tint then host:SetAttribute("Tint",tint) end
	end
	local function glow(host,def,hostAt)
		local panes={}
		for _,w in ipairs(def.windows) do
			table.insert(panes,string.format("%.3f,%.3f,%.3f,%.3f,%.3f,%.3f",w[1]-hostAt.X,w[2]-hostAt.Y,w[3]-hostAt.Z,w[4],w[5],w[6]))
		end
		host:SetAttribute("WindowGlow",table.concat(panes,";"))
		host:SetAttribute("GlowSite","window")
	end
	-- Door-step heights (the kit's plinth P: art/building-shapes.cjs; the
	-- StoneCottage door has no step, the LogLodge has its porch deck).
	B.STOOP={TimberHouse=.8,TimberTownhouse=.7,TimberShopfront=.6,ThatchCottage=.6}
	-- Invisible collider for mesh furniture / porches (§40 QC L6).
	function B.collider(parent,name,size,cf)
		local p=part(parent,name,size,cf,B.FLOOR,WO,true)
		p.Transparency,p.CastShadow=1,false
		p:SetAttribute("FurnitureCollider",true)
		return p
	end
	-- Furniture colliders per interior mesh, in the hall ground frame (kit
	-- coordinates): {cx, cy, cz, sx, sy, sz}.
	B.FURNITURE={
		TavernInterior={{-3.5,1.59,-2.5,2.2,2.5,2.2},{-3.5,1.59,2.8,2.2,2.5,2.2},{1.2,1.59,.2,2.2,2.5,2.2}, -- table tops (stools stay walk-through)
			{-7.6,2.94,0,1.2,5.2,4.2}}, -- hearth
		HallFurnishings={{2.9,1.2,-4.5,4.1,2.4,6},{2.9,1.2,4.5,4.1,2.4,6},{-3.2,.34,0,.7,.68,12}}, -- trestles + benches, wall bench
	}
	function B.furniture(parent,name,cf)
		for _,f in ipairs(B.FURNITURE[name] or {}) do
			B.collider(parent,"Furniture collider",V(f[4],f[5],f[6]),cf*CFrame.new(f[1],f[2],f[3]))
		end
	end
	-- cf: the ground point at the footprint centre; its LookVector is the
	-- street (door) side. Returns the model and its host part.
	function B.place(parent,name,cf,opts)
		opts=opts or {}
		local def=BUILDING_KIT[name]
		assert(def and def.kind~="interior","unknown building "..tostring(name))
		local m=group(opts.title or name,parent)
		m:SetAttribute("Building",name)
		local host
		if def.kind=="facade" then
			local at=V(0,def.h/2,0)
			host=part(m,"Roofed house",V(def.w,def.h,def.d),cf*CFrame.new(at),opts.color or B.PLASTER,SM,true)
			slot(host,name,def,at,opts.tint)
			glow(host,def,at)
			-- §40 QC L6: the mesh's porch deck (LogLodge) / door step stands
			-- outside the plaster block: an invisible collider so nobody wades
			-- through it.
			if name=="LogLodge" then
				B.collider(m,"Porch collider",V(def.w-1,.7,2.4),cf*CFrame.new(0,.35,-def.d/2-1.2))
			elseif B.STOOP[name] and def.door then
				local h=B.STOOP[name]
				B.collider(m,"Stoop collider",V(def.door.w+.9,h,.9),cf*CFrame.new(def.door.x,h/2,def.door.z-.45))
			end
		else
			local t,H,o=def.t,def.h,def.opening
			local at=V(0,def.floor-.25,0)
			host=part(m,"Roofed hall floor",V(def.w-2*t,.5,def.d-2*t),cf*CFrame.new(at),B.FLOOR,WO,true)
			slot(host,name,def,at,opts.tint)
			host:SetAttribute("ShapeOwnsModel",true)
			glow(host,def,at)
			local wall=opts.color or B.PLASTER
			local function w(nm,size,x,y,z) return part(m,nm,size,cf*CFrame.new(x,y,z),wall,SM,true) end
			w("Hall wall",V(def.w,H,t),0,H/2,def.d/2-t/2)
			for _,s in ipairs({-1,1}) do w("Hall wall",V(t,H,def.d-2*t),s*(def.w/2-t/2),H/2,0) end
			local side=(def.w-o.w)/2
			for _,s in ipairs({-1,1}) do w("Hall wall",V(side,H,t),s*(o.w/2+side/2),H/2,-def.d/2+t/2) end
			w("Hall lintel",V(o.w,H-o.h,t),0,o.h+(H-o.h)/2,-def.d/2+t/2)
		end
		host:SetAttribute("BuildingType",name)
		Tags:AddTag(host,"AetherBuilding")
		table.insert(B.hosts,host)
		return m,host
	end
	-- Interior furnishing set in a hall's ground frame `cf`; the counter
	-- collider is its host (created here unless given).
	function B.furnish(model,name,cf)
		local def=BUILDING_KIT[name]
		local c=V(def.counter.c[1],def.counter.c[2],def.counter.c[3])
		local counter=part(model,"Counter",V(def.counter.s[1],def.counter.s[2],def.counter.s[3]),cf*CFrame.new(c),C("5A4030"),WO,true)
		slot(counter,name,def,c)
		counter:SetAttribute("Interior",name)
		B.furniture(model,name,cf)
		return counter
	end
	-- A walk-in hall around a service counter at `pos` facing `toward` (the
	-- old market-stall frame, so every anchor keeps its offset): the counter
	-- carries the prompt and the hall's door faces the street.
	function B.hall(parent,pos,toward,o)
		local cf=facing(pos,toward)
		local c=BUILDING_KIT[o.interior].counter.c
		local hallCF=cf*CFrame.new(-c[1],0,-c[3])
		local m,floor=B.place(parent,o.shell,hallCF,{title=o.title,tint=o.tint})
		local counter=B.furnish(m,o.interior,hallCF)
		if o.verb then prompt(counter,o.verb,o.title,o.action,o.item) end
		if o.sign then
			-- A banner standard at the hall's front corner, beside the door.
			local _,size,lo,hi=Buildings.fitOf(BUILDING_KIT[o.shell])
			-- QC M4: 4.2 studs out from the side wall, so the camera-facing quad never swings into it.
			signAt(m,hallCF*CFrame.new(o.sign*(hi.X+Signs.WALL_GAP),0,lo.Z+1.4),o.title,o.kicker,o.accent,4,{kind="banner"})
		end
		return m,cf,hallCF,counter,floor
	end
	-- Warm interior night light (counts against verify-world's light caps).
	function B.interiorLight(floor,def)
		local l=light(floor,B.LIGHT,.9,20,{night=true,lift=def.h-2.8-def.floor})
		l.Parent.Name="Hall light"
		return l
	end
end

-------------------------------------------------------------------------------
-- Layout. Centres and radii (wave 4):
--   Compass Quay (hub)  (0,0,0)        r115   Guild Terrace (0,0,232)      r75
--   Mosswake Grove      (-230,0,0)     r72    Meadow Reach  (-230,0,185)   r70
--   Brassfall Quarry    (230,0,0)      r74    Cinder Shelf  (230,-6,-185)  r58
--   Warden Reach        (0,0,-230)     r70    Skyreach      (430,40,110)   r66
--   Windpine Grove      (-500,24,-160) r85    Gloomhollow   (440,-16,-440) r82
--   Tidewater Shoals    (-520,2,440)   r92    Tempest Spire (600,80,-220)  r70
--   Homes (§27): build r90-148 + edge band (footprint <= r164), 8 per row from (-1260,0,2400), 360 apart.
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
meshSlot(obelisk,"Statue",brass,true,"Uniform")
disk(monument,"Beacon brazier",V(0,15.8,0),1.7,.8,brass,MT,false)
local heroFlame=ball(monument,"Beacon flame",V(0,16.7,0),1.3,C("FFC77A"),NE)
-- Hero light #1 (shadows): the plaza beacon.
light(heroFlame,C("FFC98A"),1.1,46,{shadows=true,lift=1})
for _,dir in ipairs({V(1,0,0),V(-1,0,0),V(0,0,1),V(0,0,-1)}) do
	path(hub,dir*26,dir*112,10)
end
sign(plaza,V(-11.5,0,-30),"Compass Quay","01   /   SKY HARBOR + GUILDS",brass,0,12)
-- Hub spawn: every arrival from home lands on the Sky Harbor plaza.
disk(harbor,"Harbor plaza",V(56,0,60),17,.24,C("C9B994"),ST,true)
disk(harbor,"Harbor seal",V(56,.06,60),5,.3,navy,ST,false)
sign(harbor,V(56,0,40),"Sky Harbor","ARRIVALS   /   HOMEWARD · CREW HAVEN",mint,0,12,{kind="post",
	arrows={{label="Homeward",to=V(71,0,58)},{label="Crew Haven",to=V(39,0,62)},{label="Compass Plaza",to=V(0,0,0)}}})
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
	-- The Harbour Angler fishes off the second pier's end.
	if i==2 then anchor(hub,"NPC_Fisher",b-dir*2.5+V(0,.3,0),b+dir*10) end
end
local ship=group("Moored skyship",harbor)
local hull=part(ship,"Skyship hull",V(9,5,30),CFrame.new(V(98,-1.5,98))*CFrame.Angles(0,math.rad(-45),0),C("7A5A40"),WO,false)
meshSlot(hull,"Skyship",nil,true)
part(ship,"Skyship deck",V(8,.4,27),CFrame.new(V(98,1.2,98))*CFrame.Angles(0,math.rad(-45),0),C("A57C55"),WO,false)
part(ship,"Skyship mast",V(.8,16,.8),CFrame.new(V(98,9,98)),darken(timber,.3),WO,false)
part(ship,"Skyship sail",V(.3,9,12),CFrame.new(V(98,10,98))*CFrame.Angles(0,math.rad(45),0),cream,Enum.Material.Fabric,false)
ball(ship,"Skyship balloon",V(98,20,98),11,rose,Enum.Material.Fabric)
local HUB_GUIDE=anchor(hub,"NPC_Guide",V(56,0,50),HUB_ARRIVAL)
anchor(hub,"Spawn",HUB_ARRIVAL-V(0,4,0),V(56,0,40))
anchor(hub,"NPC_Herald",V(-8,0,-29),V(0,0,0))
anchor(hub,"Waypoint_SkyHarbor",V(56,0,60),V(56,0,40))
-- Market Row along the east avenue.
-- §40: the bank and the trade counter are walk-in halls (ShopHall shell, bank
-- and shop interiors) built around their old counters, so the counter prompt,
-- the banker / merchant behind it and the waypoint inside the door keep their
-- offsets (raised onto the hall floor).
local QUAY_FLOOR=BUILDING_KIT.ShopHall.floor
local bank,bankCF,_,bankCounter,bankFloor=Buildings.hall(hub,V(44,0,-17),V(44,0,0),{title="Quay Bank",shell="ShopHall",interior="BankInterior",
	verb="Bank purse",action="bank",tint=C("9C3F3A"),sign=-1,accent=mint,kicker="MARKET ROW   /   BANK"})
local trade,tradeCF,_,tradeCounter,tradeFloor=Buildings.hall(hub,V(68,0,-17),V(68,0,0),{title="Trade Counter",shell="ShopHall",interior="ShopInterior",
	verb="Sell goods",action="sell",tint=C("9C3F3A"),sign=-1,accent=brass,kicker="MARKET ROW   /   TRADE"})
Buildings.interiorLight(bankFloor,BUILDING_KIT.ShopHall)
Buildings.interiorLight(tradeFloor,BUILDING_KIT.ShopHall)
marketStall(hub,V(50,0,17),V(50,0,0),"Fruit Stall",nil,nil,nil,rose,"MARKET ROW   /   PRODUCE","Feast")
marketStall(hub,V(76,0,17),V(76,0,0),"Cloth Stall",nil,nil,nil,teal,"MARKET ROW   /   CLOTH","HideRoll")
anchor(hub,"NPC_Banker",at(bankCF,0,QUAY_FLOOR,2.4))
anchor(hub,"NPC_Merchant",at(tradeCF,0,QUAY_FLOOR,2.4))
anchor(hub,"NPC_Auctioneer",V(86,0,-8),V(86,0,0))
anchor(hub,"Waypoint_Bank",at(bankCF,0,QUAY_FLOOR,-5)*CFrame.Angles(0,math.pi,0))
anchor(hub,"Waypoint_Market",at(tradeCF,0,QUAY_FLOOR,-5)*CFrame.Angles(0,math.pi,0))
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
local forgeStall,forgeCF=marketStall(rise,V(-56,riseTop,42),V(-36,riseTop,30),"Starforge","Forge pickaxe","craft","Pickaxe",rose,"ARTISANS' RISE   /   SMITHING","Anvil")
anchor(hub,"NPC_Forgemaster",at(forgeCF,0,0,2.4))
anchor(hub,"NPC_Joiner",V(-40,riseTop,50),V(-46,riseTop,58))
anchor(hub,"Waypoint_Starforge",at(forgeCF,0,0,-5)*CFrame.Angles(0,math.pi,0))
local rack=block(rise,"Bladesmith rack",V(-66,riseTop+1.5,52),V(2,3,2),navy,ST,true)
prompt(rack,"Forge blade","Starforge","craft","Blade")
local apothecary=block(rise,"Apothecary vat",V(-46,riseTop+1,58),V(2.5,2,2.5),teal,SM,true)
meshSlot(apothecary,"Cauldron",teal)
prompt(apothecary,"Brew tonic","Starforge","craft","Tonic")
sculpture(rise,"Smith's pickaxe",at(forgeCF,-2,4,0).Position,"Pickaxe",.7,25)
sculpture(rise,"Smith's blade",V(-66,riseTop+4,52),"Blade",.65,-20)
sculpture(rise,"Alchemist tonic",V(-46,riseTop+3,58),"Tonic",.7)
local furnace=block(rise,"Rise furnace",V(-64,riseTop+1.6,40),V(4,3.2,3.4),C("6E4B3A"),Enum.Material.Brick,true)
meshSlot(furnace,"Forge")
local furnaceMouth=block(rise,"Furnace mouth",V(-64,riseTop+1.2,38.25),V(1.8,1.2,.2),C("FF8A3D"),NE,false)
light(furnaceMouth,C("FF9A52"),.8,14,{lift=1.2})
local statue=block(rise,"Founder statue",V(-60,riseTop+4.2,64),V(2.2,5,1.6),C("BFC6CE"),ST,true)
block(rise,"Statue plinth",V(-60,riseTop+.8,64),V(3.6,1.6,3.6),C("8F97A3"),ST,true)
meshSlot(statue,"Statue")
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
-- Avenue signposts (§28): arrows point at the island they name and back to the plaza.
local PLAZA=V(0,0,0)
sign(hub,V(-100,0,-12),"Mosswake Grove","WEST   /   TIMBER + HERBS",mint,90,10,{kind="post",arrows={{label="Mosswake Grove",to=G},{label="Compass Plaza",to=PLAZA}}})
sign(hub,V(100,0,12),"Brassfall Quarry","EAST   /   COPPER ORE",brass,90,10,{kind="post",arrows={{label="Brassfall Quarry",to=Q},{label="Compass Plaza",to=PLAZA}}})
sign(hub,V(12,0,-100),"Warden Reach","NORTH   /   HUNTS",rose,0,9,{kind="post",arrows={{label="Warden Reach",to=W},{label="Compass Plaza",to=PLAZA}}})
sign(hub,V(-12,0,100),"Guild Terrace","SOUTH   /   CRAFT · SLAYER · SKYWAY",brass,0,10,{kind="post",arrows={{label="Guild Terrace",to=V(0,0,232)},{label="Compass Plaza",to=PLAZA}}})
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
bridge(hub,V(HUB_R,0,0),Q-V(Q_R,0,0),"StoneArchBridge")
bridge(hub,V(0,0,-HUB_R),W+V(0,0,W_R),"StoneArchBridge")
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
local spot=group("Moonpool fishing spot",grove)
local dock=part(spot,"Fishing jetty",V(3,1,9),CFrame.lookAt(jettyAt+V(0,.5,0),MOONPOOL+V(0,.5,0)),timber,WO,true)
meshSlot(dock,"FishingPier")
-- §42 QC L11: ripples and a bobber off the jetty's end, so the spot visibly goes calm when fished out.
local bob=jettyAt+(MOONPOOL-jettyAt).Unit*7
for i=1,2 do disk(spot,"Ripple",bob+V(math.cos(i*2.1)*.9,.26+i*.04,math.sin(i*2.1)*.9),.4+i*.4,.03,lighten(C("5AA9B5"),.35+i*.12),SM,false) end
ball(spot,"Bobber",bob+V(.4,.5,.2),.75,C("E2574C"),SM)
ball(spot,"Bobber cap",bob+V(.4,.95,.2),.42,cream,SM)
Node.gather(dock,"Fish")
anchor(grove,"Waypoint_MoonpoolJetty",jettyAt+(jettyAt-MOONPOOL).Unit*5.5,MOONPOOL)
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
local vein=sculpture(group("Aetherite seam",advanced),"Aetherite seam",Q+V(26,1.5,28),"AetherCrystal",1.45,30)
vein.Size=V(3,3,3) -- §42: the anchor is the click target (still invisible; the sculpture scales by SculptureScale)
Node.gather(vein,"Aetherite")
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
		meshSlot(stone,"Waystone",rose)
		gem(wild,"Signal prism",W+V(x,6.3,z),V(1,2.3,1),rose,.7)
	end
end
for i,deg in ipairs({0,60,120,180,240,300}) do
	local a=math.rad(deg)
	local h=4+hash(i,6)*6
	local col=block(wild,"Ruined column",W+V(math.cos(a)*20,h/2,math.sin(a)*20),V(2.2,h,2.2),C("A3A6B2"),ST,true)
	if i%2==0 then meshSlot(col,"RuinColumn") end
end
local boss=hidden(wild,"Shellwarden",W+V(0,2,0))
boss:SetAttribute("Shape","Shellwarden")
Tags:AddTag(boss,"AetherSculpture")
prompt(boss,"Strike","Shellwarden","fight","Warden")
disk(wild,"Warden dais",W+V(0,.1,0),12,.22,shale,ST,true)
anchor(wild,"Waypoint_Shellwarden",W+V(0,0,16),W)
sign(wild,W+V(12,0,30),"Shellwarden","WARDEN REACH   /   HUNT",rose,0,10)
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
-------------------------------------------------------------------------------
-- Travel beacons (docs/DEPTH-CONTRACT.md §44). Every beacon a player uses to
-- travel keeps its prompt post (name, size, place, prompt and anchors as
-- before) and becomes a forged dais: travelBeacon() gives the post the
-- TravelBeacon / TravelBeaconBasalt mesh in a declared ShapeBox (5 x 5.6 x 5
-- from the ground up) that covers the post and its plinth; the forge hides the
-- post locally once the mesh exists. The floating aether crystal, armillary
-- rings, rising motes, locked / lit state and the activation flare are drawn
-- by beacons.client.lua from these attributes (no extra static parts):
--   TravelBeacon (string)        kind: region | return | home | crew | ferry | vent
--   TravelBeaconHover (Vector3)  world point the crystal / rings float at
--   TravelBeaconRegion (string)  destination region: dark until the player can
--                                go there (region open or warp learned)
--   TravelBeaconNeeds (string)   "crew": dark until the player is in a crew
--   TravelBeaconFlare (number)   bumped on every successful use (with
--                                TravelBeaconFlareBy = UserId): the flare + whoosh
-- Basalt daises stand on the dark isles; the dais channels take the Tint.
-- Colliders (invisible, under the mesh): the stepped base is a 4.9-wide,
-- 0.95-tall cylinder "Beacon plinth" (a step a character walks onto) and the
-- four pylons are thin "Beacon pylon" posts; the prompt hangs on the post's
-- "Beacon prompt" attachment in front of the dais (opts.face, default -Z) at
-- ground + 1.5.
-------------------------------------------------------------------------------
local BEACON_BOX=V(5,5.6,5)
local BEACON_PLINTH_R,BEACON_PLINTH_H=2.45,.95
local BEACON_PYLON=V(.6,2.9,.6) -- from the plinth top to the arms, 1.55 out on the diagonals
local BEACON_PROMPT_REACH,BEACON_PROMPT_HEIGHT=3.2,1.5
local BASALT_ISLES={["Brassfall Quarry"]=true,["Cinder Shelf"]=true,["Gloomhollow Caverns"]=true,["Tempest Spire"]=true,["The Shattered Crown"]=true}
local function travelBeacon(post,ground,accent,kind,opts)
	opts=opts or {}
	local basalt=BASALT_ISLES[islandModel(post).Name]==true
	meshSlot(post,if basalt then "TravelBeaconBasalt" else "TravelBeacon",accent)
	local at=post.CFrame.Position
	local base=disk(post.Parent,"Beacon plinth",V(at.X,ground+BEACON_PLINTH_H/2,at.Z),BEACON_PLINTH_R,BEACON_PLINTH_H,ink,ST,true)
	base.Transparency,base.CastShadow=1,false
	for k=0,3 do
		local a=math.pi/4+k*math.pi/2
		local pylon=part(post.Parent,"Beacon pylon",BEACON_PYLON,CFrame.new(at.X+math.cos(a)*1.55,ground+BEACON_PLINTH_H+BEACON_PYLON.Y/2,at.Z+math.sin(a)*1.55)*CFrame.Angles(0,-a,0),ink,ST,true)
		pylon.Transparency,pylon.CastShadow=1,false
	end
	local face=if typeof(opts.face)=="Vector3" then V(opts.face.X,0,opts.face.Z) else V(0,0,-1)
	face=if face.Magnitude>1e-3 then face.Unit else V(0,0,-1)
	local seat=Instance.new("Attachment")
	seat.Name="Beacon prompt"
	seat.CFrame=post.CFrame:ToObjectSpace(CFrame.new(V(at.X,ground+BEACON_PROMPT_HEIGHT,at.Z)+face*BEACON_PROMPT_REACH))
	seat.Parent=post
	post:SetAttribute("ShapeBox",BEACON_BOX)
	post:SetAttribute("ShapeBoxOffset",post.CFrame:ToObjectSpace(CFrame.new(at.X,ground+BEACON_BOX.Y/2,at.Z)).Position)
	post:SetAttribute("TravelBeacon",kind)
	post:SetAttribute("TravelBeaconHover",V(at.X,ground+3,at.Z))
	if opts.region then post:SetAttribute("TravelBeaconRegion",opts.region) end
	if opts.needs then post:SetAttribute("TravelBeaconNeeds",opts.needs) end
	Tags:AddTag(post,"TravelBeacon")
	return post
end
-- A beacon's prompt post standing on `ground` (its old part, kept as the fallback).
local function beaconPost(parent,name,ground,center,size,accent,kind,opts)
	local post=block(parent,name,center,size,accent,GL,false)
	return travelBeacon(post,ground,accent,kind,opts)
end
-- A successful beacon trip is known fast travel (Aether Mote pickup checks)
-- and flares the beacon for every client nearby.
local function flare(trigger,player)
	if trigger:GetAttribute("TravelBeacon")==nil then return end
	trigger:SetAttribute("TravelBeaconFlareBy",player.UserId)
	trigger:SetAttribute("TravelBeaconFlare",(tonumber(trigger:GetAttribute("TravelBeaconFlare")) or 0)+1)
end
local function warp(player,trigger,destination)
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local hum=character and character:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health>0 and (trigger.CFrame.Position-root.Position).Magnitude<=12 then
		player:SetAttribute("FastTravelAt",os.clock()) -- known fast travel (Aether Mote pickup checks)
		flare(trigger,player)
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
local launch = beaconPost(mine,"Charter beacon",Q.Y,Q+V(58,2.8,6),V(1.6,4,1.6),brass,"region",{region="Skyreach",face=V(-6,0,2)})
sign(mine,Q+V(54,0,-4),"Skyreach passage","GUILD CHARTER REQUIRED",brass,90,9,{arrows={{label="Skyreach",to=SR},{label="Brassfall Quarry",to=Q}}})
anchor(mine,"Waypoint_SkyreachCharter",Q+V(52,0,8),Q+V(58,0,6))
local launchPrompt=prompt(launch,"Ascend to Skyreach","Guild charter required")
launchPrompt:SetAttribute("IsleWarpRegion","Skyreach")
launchPrompt.Triggered:Connect(function(player)
	regionTravel(player,launch,"Skyreach",SKYREACH_LANDING)
end)
local descent = beaconPost(skyreach,"Quarry beacon",SR.Y,SR+V(-46,2.8,-10),V(1.6,4,1.6),mint,"return",{face=V(46,0,10)})
prompt(descent,"Return to quarry","Brassfall").Triggered:Connect(function(player)
	warp(player,descent,Q+V(50,4,14))
end)
do
local SUMMIT=SR+V(16,0,-4)
local summit,summitTop=tier(skyreach,"Summit",SUMMIT,18,6,{open={2.747},cliff=C("5F6F74"),top=C("A3B8B4")})
ramp(summit,SR+V(-8,0,6),V(SR.X+2,summitTop,SR.Z+2),7)
local survey = sculpture(summit,"Summit cartographer",V(SUMMIT.X+2,summitTop+2,SUMMIT.Z-4),"Surveyor",1.1,180)
prompt(survey,"Survey the summit","Skyreach","explore","Skyreach"):SetAttribute("IsleRegion","Skyreach")
local rich = sculpture(group("Rich Aetherite seam",skyreach),"Rich Aetherite seam",SR+V(-14,2,28),"AetherCrystal",1.8)
rich.Size=V(3.5,3.5,3.5) -- §42: click target (invisible)
Node.gather(rich,"Aetherite","Skyreach")
sign(skyreach,SR+V(-38,0,-16),"Skyreach","SURVEY THE SUMMIT / MINE RICH SEAMS",mint,90,10)
for i,o in ipairs({V(-30,0,30),V(-20,0,-40),V(30,0,48),V(50,0,-2),V(-4,0,52)}) do decorTree(skyreach,SR+o,1,"Pine",C("5D8070")) end
for i,o in ipairs({V(-40,0,24),V(24,0,-44)}) do outcrop(skyreach,SR+o,1.2,i) end
for _,o in ipairs({V(-40,0,6),V(-10,0,20)}) do lamp(skyreach,SR+o) end
end
local returnPost=beaconPost(harbor,"Homeward beacon",0,V(66,2,64),V(2,4,2),mint,"home",{face=V(-4,0,-4)})
sign(harbor,V(71,0,58),"Homeward","WAYFARER TRANSIT   /   RETURN",mint,90,9)
anchor(hub,"Waypoint_Homeward",V(62,0,60),V(66,0,64))
prompt(returnPost,"Travel home","Homeward beacon").Triggered:Connect(function(player)
	local home=homes[player]
	if home then warp(player,returnPost,home.spawn.Position+V(0,4,0)) end
end)

-------------------------------------------------------------------------------
-- Home islands (Home Islands team; contract §27, rules in Data.Home).
-- WayfarersRest_<UserId> is a SkyBlock-style private island: a flat build disc
-- of Data.Home.Stages[level].radius studs (level 1: r90) inside a MARGIN-wide
-- natural edge band (a sand beach, three cliff crags, a pond, three windpines
-- and three ore rocks the owner gathers, three trees). When the server
-- publishes a new HomesteadLevel (1..5, bought ring by ring) the shell is
-- resized and the edge band moves out; the part count is the same at every
-- level. The legacy core (r21) keeps every fixed object at its old offset, so
-- Data.Island records and Protected zones stay valid; the Worker Yard, the
-- Builder's Terrace, the Verdant Garden and the lookout deck stand on the
-- island (plazas, no bridges). Homes sit on Data.Home.slotCenter's grid
-- (PITCH 360, far north of the hub) so the largest island never meets a
-- neighbour. Budgets (verify-home.luau): <= Data.Home.PART_BUDGET parts of
-- fixed geometry with every addition built; no lights beyond the legacy lamps.
-------------------------------------------------------------------------------
local HOME_CORE=21
local HomeKit={}
do
	local okData,D=pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData",30)) end)
	local H=if okData and type(D)=="table" and type(D.Home)=="table" then D.Home else nil
	HomeKit.Home=H
	function HomeKit.level(value) return if H then H.level(value) else 1 end
	function HomeKit.radius(level) return if H then H.radius(level) else 90 end
	function HomeKit.meadow(level) return HomeKit.radius(level)+(if H then H.MARGIN else 10) end
	function HomeKit.center(slot)
		if H then
			local x,z=H.slotCenter(slot)
			return V(x,0,z)
		end
		return V(((slot-1)%8)*360-1260,0,2400+((slot-1)//8)*360)
	end
	HomeKit.costText=function(level) return if H then H.costText(level) else "" end
	HomeKit.EDGE=if H then H.Edge else {}
	local sand,cliffStone=C("D8C79A"),C("5F6B78")
	-- Shell: the Meadow (resized in place, so references stay valid) and an
	-- "Island shell" model rebuilt per level: foundation, stratum, basalt,
	-- 12 fractured skirt slabs and 3 keel shards.
	function HomeKit.shell(home,level)
		local m,center=home.model,home.center
		local r=HomeKit.meadow(level)
		if not home.meadowPart then
			home.meadowPart=disk(m,"Meadow",center-V(0,.25,0),r+.1,.5,turf,Enum.Material.Grass,true)
		end
		home.meadowPart.Size=V(.5,2*(r+.1),2*(r+.1))
		if home.shell then home.shell:Destroy() end
		local s=group("Island shell",m)
		home.shell=s
		disk(s,"Floating foundation",center-V(0,3.3,0),r-.4,6,rock,ST,true)
		disk(s,"Mineral stratum",center-V(0,7.4,0),r*.82,3,shale,ST,false)
		disk(s,"Lower basalt",center-V(0,11,0),r*.58,5,rock,ST,false)
		for i=1,12 do
			local a=(i+hash(i,7)*.6)*2*math.pi/12
			local radial=V(math.cos(a),0,math.sin(a))
			local h=8+hash(i,2)*6
			local size=V(r*.24+4,h,r*.1+4)
			local spot=center+radial*(r*.95)-V(0,h/2+1.4+size.X*.05+size.Z*.04,0)
			local slab=part(s,"Fractured cliff",size,CFrame.new(spot)*CFrame.Angles(0,-a+math.pi/2,0)*CFrame.Angles(.08*(i%2*2-1),0,.1),i%2==0 and rock or shale,ST,false)
			if i%3==0 then meshSlot(slab,"CliffRock") end
		end
		for i=1,3 do
			local a=i*2*math.pi/3+hash(i,7)
			local d=r*(.15+.25*hash(i,3))
			local h=r*.25+6
			local shard=part(s,"Keel rock",V(r*.2,h,r*.18),CFrame.new(center+V(math.cos(a)*d,-13.5-h*.35,math.sin(a)*d))*CFrame.Angles(.12,a,.14),i%2==0 and rock or darken(rock,.2),ST,false)
			if i==1 then meshSlot(shard,"CliffRock") end
		end
		m:SetAttribute("IslandRadius",r)
		m:SetAttribute("BuildRadius",HomeKit.radius(level))
	end
	-- Owner-only gather nodes on the edge band.
	local function homeOre(parent,pos,owner)
		local m=group("Home ore rock",parent)
		local base=disk(m,"Ore seam",pos+V(0,.4,0),2.5,.8,shale,ST,false)
		slotBox(m,"Ore seam mesh",pos,V(5,2.4,4.4),"OreVein",C("C98D4F"))
		sculpture(m,"Faceted copper cluster",pos+V(0,1.4,0),"AetherCrystal",1)
		Node.gather(base,"Ore",nil,owner)
	end
	-- Edge band: every feature sits between the build radius and the meadow rim
	-- (Data.Home.Edge angles), rebuilt one ring further out per level.
	function HomeKit.edge(home,level,owner)
		local m,center=home.model,home.center
		local R,RM=HomeKit.radius(level),HomeKit.meadow(level)
		local band=(R+RM)/2
		if home.edge then home.edge:Destroy() end
		local e=group("Island edge",m)
		home.edge=e
		for i,f in ipairs(HomeKit.EDGE) do
			local dir=V(math.cos(f.a),0,math.sin(f.a))
			local side=V(-dir.Z,0,dir.X)
			local at=center+dir*band
			if f.kind=="beach" then
				local beach=group("Sand beach",e)
				disk(beach,"Beach shelf",center+dir*(RM-2)-V(0,1.85,0),16,3,sand,SA,true)
				for _,s in ipairs({-1,1}) do decorTree(beach,center+dir*(RM+6)+side*6*s-V(0,.35,0),1,"Palm") end
				meshSlot(part(beach,"Beach boulder",V(3.4,2.2,2.8),CFrame.new(center+dir*(RM+9)+V(0,.5,0))*CFrame.Angles(.1,f.a,.12),lighten(rock,.1),ST,true),"Rock")
				-- Anchors live on the island model root (contract §10): replace, never stack.
				if home.shoreAnchor then home.shoreAnchor:Destroy() end
				home.shoreAnchor=anchor(e,"Waypoint_HomeShore",center+dir*(RM+4)-V(0,.35,0),center)
			elseif f.kind=="cliff" then
				local h=11+hash(i,5)*5
				local crag=part(e,"Cliff crag",V(9,h,6),CFrame.new(center+dir*(R+6)+V(0,h/2-1.2,0))*CFrame.Angles(0,-f.a+math.pi/2,0)*CFrame.Angles(-.12,0,.06*(i%2*2-1)),i%2==0 and cliffStone or lighten(cliffStone,.12),ST,true)
				meshSlot(crag,"CliffRock")
			elseif f.kind=="pond" then
				pond(e,at,3.2,{stones=3,name="Home pond"})
			elseif f.kind=="windpine" then
				windpine(e,at,1,owner)
			elseif f.kind=="ore" then
				homeOre(e,at,owner)
			elseif f.kind=="pine" then
				decorTree(e,at,1.1,"Pine")
			else
				decorTree(e,at,1,"Meadow")
			end
		end
	end
	-- Plaza: one paving disc whose top sits 0.04 above the meadow (no shared
	-- plane), with the island attributes the add-ons' tests and NPCs read.
	function HomeKit.plaza(parent,name,pos,r,color,material)
		local model=group(name,parent)
		disk(model,"Meadow",pos-V(0,.11,0),r,.3,color,material or ST,true) -- named Meadow like an islet top
		model:SetAttribute("IslandCenter",pos)
		model:SetAttribute("IslandRadius",r)
		model:SetAttribute("Region","Home")
		return model
	end
	-- Lazy homes (§27 performance): placements and terrace furniture exist
	-- only while someone stands within LIVE_RANGE studs (flat) of the home's
	-- centre, and are torn down LIVE_LINGER seconds after the last one leaves.
	-- Builders register a hook in home.liveHooks; HomeKit.setLive runs them.
	-- An owner without a character yet counts as present (they spawn at home).
	HomeKit.LIVE_RANGE=if H then H.LIVE_RANGE else 250
	HomeKit.LIVE_LINGER=if H then H.LIVE_LINGER else 30
	HomeKit.LIVE_TICK=if H then H.LIVE_TICK else 1
	local function rootPosition(player)
		local ok,pos=pcall(function()
			local character=player.Character
			local root=character and character:FindFirstChild("HumanoidRootPart")
			return root and root.Position
		end)
		return if ok and typeof(pos)=="Vector3" then pos else nil
	end
	local function within(home,pos)
		local dx,dz=pos.X-home.center.X,pos.Z-home.center.Z
		return dx*dx+dz*dz<=HomeKit.LIVE_RANGE*HomeKit.LIVE_RANGE
	end
	function HomeKit.occupied(home,owner)
		local pos=rootPosition(owner)
		if not pos or within(home,pos) then return true end
		for _,visitor in ipairs(Players:GetPlayers()) do
			if visitor~=owner then
				local at=rootPosition(visitor)
				if at and within(home,at) then return true end
			end
		end
		return false
	end
	function HomeKit.setLive(home,live)
		if home.live==live then return end
		home.live=live
		home.model:SetAttribute("HomeLive",live)
		for _,hook in ipairs(home.liveHooks) do hook() end
	end
	-- One presence pass at clock `now` (seconds, accumulated by the loop below settle).
	function HomeKit.step(now)
		for owner,home in pairs(homes) do
			if HomeKit.occupied(home,owner) then
				home.seen=now
				HomeKit.setLive(home,true)
			elseif home.live and now-(home.seen or now)>=HomeKit.LIVE_LINGER then
				HomeKit.setLive(home,false)
			elseif home.seen==nil then
				home.seen=now
			end
		end
	end
end
local function settle(player)
	if homes[player] then return end
	local slot=1
	while slots[slot] do slot+=1 end
	slots[slot]=true
	local center=HomeKit.center(slot)
	local m=Instance.new("Model")
	m.Name="WayfarersRest_"..player.UserId
	m:SetAttribute("IslandCenter",center)
	m:SetAttribute("Region","Home")
	m:SetAttribute("HomeSlot",slot)
	local home={model=m,center=center,slot=slot,liveHooks={}}
	home.live=HomeKit.occupied(home,player)
	m:SetAttribute("HomeLive",home.live)
	local level=HomeKit.level(player:GetAttribute("HomesteadLevel"))
	home.level=level
	HomeKit.shell(home,level)
	HomeKit.edge(home,level,player.UserId)
	m:SetAttribute("HomesteadLevel",level)
	m.Parent=world
	local spawn=Instance.new("SpawnLocation")
	spawn.Name,spawn.Anchored,spawn.Neutral,spawn.AllowTeamChangeOnTouch="Home Landing",true,true,false
	spawn.Size,spawn.Position,spawn.Transparency=V(4,.45,4),center+V(0,.25,5),1
	spawn.Duration,spawn.Parent=0,m
	player.RespawnLocation=spawn
	home.spawn,home.decorationConnections=spawn,{}
	homes[player]=home
	-- Expansion rings: the server publishes HomesteadLevel after a validated
	-- purchase (or on load); the shell and edge band follow, placements re-check.
	local stake=block(m,"Survey stake",center+V(10,1.5,-21),V(.5,3,.5),timber,WO,true)
	block(m,"Survey pennant",center+V(10.6,2.6,-21),V(1.2,.8,.1),mint,Enum.Material.Fabric,false)
	local survey=prompt(stake,"Expand island","Homestead","homeExpand","ring",player.UserId)
	local function refreshSurvey()
		survey.ObjectText="Homestead level "..home.level.." · "..HomeKit.costText(home.level)
		survey.Enabled=HomeKit.Home==nil or home.level<HomeKit.Home.MAX_LEVEL
	end
	refreshSurvey()
	table.insert(home.decorationConnections,player:GetAttributeChangedSignal("HomesteadLevel"):Connect(function()
		local now=HomeKit.level(player:GetAttribute("HomesteadLevel"))
		if now==home.level or not m.Parent then return end
		home.level=now
		HomeKit.shell(home,now)
		HomeKit.edge(home,now,player.UserId)
		m:SetAttribute("HomesteadLevel",now)
		refreshSurvey()
		if home.refreshPlacements then home.refreshPlacements() end
	end))
	anchor(m,"Waypoint_HomeLanding",center+V(0,0,5),center)
	local function land(character)
		local root=character:WaitForChild("HumanoidRootPart",10)
		-- Lairs: lairs.server.lua owns a rejoin respawn (LairRejoin) and returns the member to their arena.
		-- Raids (§38): raids.server.lua owns a raider's death / rejoin respawn (RaidRejoin) the same way.
		if root and homes[player] and player.Character==character and not player:GetAttribute("LairRejoin") and not player:GetAttribute("RaidRejoin") then character:PivotTo(CFrame.new(spawn.Position+V(0,3.4,0))) end
	end
	player.CharacterAdded:Connect(land)
	if player.Character then task.spawn(land,player.Character) end
	windpine(m,center+V(-6,0,0),1,player.UserId)
	sign(m,center+V(6,0,-5),"Wayfarer's Rest","HOME   /   CUT WINDPINE TO BEGIN",mint,0,9)
	local gatePost=beaconPost(m,"Quay beacon",center.Y,center+V(0,2,-11),V(2,4,2),mint,"return",{face=V(0,0,1)})
	prompt(gatePost,"Travel to hub","Compass Quay").Triggered:Connect(function(user)
		if user==player then warp(user,gatePost,HUB_ARRIVAL) end
	end)
	-- Worker stations (Workers depth): slots 1-3 keep their legacy offsets inside
	-- Data.Island's protected "worker station" rectangles; slots 4-12 stand in a
	-- ring on the Worker Yard, a raised lobe north-east of the meadow and outside
	-- the placement grid (RADIUS 18.5), so no placement cell is taken. Per slot:
	-- pad + tier ring (colour by tier), invisible chassis collider with the
	-- prompt, a Surveyor sculpture (scale grows with tier) and an emblem sculpture
	-- of the worker type's catalog shape tinted with its colour (rebuilt only when
	-- the type/tier changes). Attributes: Worker<n>Tier, Worker<n>Resource,
	-- WorkerSlots (unlocked slots; locked stations show their unlock note).
	-- §40: the yard stands out in the south-east district (Data.Island
	-- ProtectedCircles "worker yard"), reached by a path and its ramp.
	local YARD_OFFSET=V(40,0,-38)
	local yardCenter=center+YARD_OFFSET
	local YARD_R,YARD_H=12,1.5
	do
		local dir=(-YARD_OFFSET).Unit
		local yard=tier(m,"Worker Yard",yardCenter,YARD_R,YARD_H,{open={math.atan2(dir.Z,dir.X)},top=C("8FB27F")})
		local out=YARD_OFFSET.Unit
		local foot=yardCenter-out*(YARD_R+5.4)
		path(yard,center+out*(HOME_CORE-1),foot+out*.6,5)
		ramp(yard,foot,yardCenter-out*(YARD_R-2.2)+V(0,YARD_H,0),5)
		sculpture(yard,"Worker Yard lockbox",yardCenter+V(0,YARD_H+.9,0),"VaultChest",.9)
		anchor(m,"Waypoint_WorkerYard",yardCenter+V(-6,YARD_H,6),yardCenter+V(0,YARD_H,0))
	end
	local fleetOffsets={V(9,0,4),V(13,0,-1),V(-10,0,-10)}
	do
		-- Nine yard slots on a ring (radius 8), skipping the ramp side.
		local entry=math.atan2(-YARD_OFFSET.Z,-YARD_OFFSET.X)
		for i=1,9 do
			local a=entry+(i)*2*math.pi/10
			table.insert(fleetOffsets,V(YARD_OFFSET.X+math.cos(a)*8,YARD_H,YARD_OFFSET.Z+math.sin(a)*8))
		end
	end
	local TIER_COLORS={C("9AA5B1"),C("6BBF59"),C("3F7CAC"),C("8E5CC4"),C("E0A040"),C("E86FB8"),C("FFF3B0")}
	homes[player].workerRefresh={}
	for workerSlot,offset in ipairs(fleetOffsets) do
		local station=group("WorkerStation"..workerSlot,m)
		local position=center+offset
		local facing=if workerSlot>3 then CFrame.lookAt(position,V(yardCenter.X,position.Y,yardCenter.Z)) else CFrame.new(position)
		local yaw=if workerSlot>3 then math.deg(math.atan2(-facing.LookVector.X,-facing.LookVector.Z)) else 0
		disk(station,"Worker pad",position+V(0,.08,0),2.3,.16,navy,SM,false)
		local ring=disk(station,"Tier ring",position+V(0,.05,0),2.4,.1,shale,SM,false) -- 2.4: neighbouring yard rings (8-stud ring, 10 steps) never overlap
		local engine=block(station,"Surveyor chassis",position+V(0,1.35,0),V(2.8,2.7,2.5),navy,SM,true)
		-- §27 part budget: the invisible eye-lens part is gone (the sculpted
		-- surveyor shows the eye); the chassis stays as the prompt collider.
		engine.Transparency=1
		local interaction=prompt(engine,"Build worker","Surveyor chassis",workerSlot==1 and "worker" or "workerBuild",tostring(workerSlot),player.UserId)
		local badge=Instance.new("BillboardGui")
		badge.Name,badge.Size,badge.StudsOffset,badge.MaxDistance="Worker status",UDim2.fromOffset(170,44),V(0,3,0),12
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
		local shown,surveyor,emblem={},nil,nil
		local function refreshWorker()
			if not m.Parent then return end
			local tierNow=player:GetAttribute("Worker"..workerSlot.."Tier") or 0
			local resource=player:GetAttribute("Worker"..workerSlot.."Resource") or "Ore"
			local unlocked=player:GetAttribute("WorkerSlots")
			unlocked=if type(unlocked)=="number" then unlocked else 3
			local active=tierNow>0
			local art=homeTerrace.workerArt and homeTerrace.workerArt(resource)
			local name=art and art.name or resource
			local locked=not active and workerSlot>unlocked
			engine.Color=active and teal or navy
			ring.Color=if active then TIER_COLORS[math.clamp(tierNow,1,#TIER_COLORS)] else shale
			interaction.Enabled=not locked
			interaction.ActionText=active and "Claim output" or "Build worker"
			interaction.ObjectText="Worker "..workerSlot..(if active then " · "..name else if locked then " · locked" else " · "..(5*workerSlot).." timber + "..(3*workerSlot).." ore")
			interaction:SetAttribute("IsleAction",active and "workerClaim" or (workerSlot==1 and "worker" or "workerBuild"))
			text.Text=if active then ("WORKER "..workerSlot.." · TIER "..tierNow.."\n"..name.." / manage in Atlas")
				elseif locked then ("WORKER "..workerSlot.."\nLocked · craft unique workers")
				else ("WORKER "..workerSlot.."\nUnbuilt surveyor chassis")
			if cachePrompt then cachePrompt.Enabled=active end
			-- Sculptures: rebuilt only when what they show changes.
			local key=tostring(active and tierNow or 0)
			if shown.surveyor~=key then
				shown.surveyor=key
				if surveyor then surveyor:Destroy() end
				surveyor=sculpture(station,"Sculpted surveyor",position+V(0,1.5,0),"Surveyor",1+(active and (tierNow-1)*.05 or 0),yaw)
			end
			local emblemKey=active and resource or ""
			if shown.emblem~=emblemKey then
				shown.emblem=emblemKey
				if emblem then emblem:Destroy(); emblem=nil end
				if active then
					emblem=block(station,"Worker emblem",position+V(0,3.5,0),V(1.1,1.1,1.1),art and art.color or brass,SM,false)
					emblem.CFrame=CFrame.new(emblem.CFrame.Position)*CFrame.Angles(0,math.rad(yaw),0)
					emblem.CastShadow=false
					meshSlot(emblem,art and art.shape or "OreChunk",art and art.color or brass,false,"Uniform")
					emblem:SetAttribute("WorkerType",resource)
				end
			end
		end
		for _,suffix in ipairs({"Tier","Resource"}) do
			table.insert(homes[player].decorationConnections,player:GetAttributeChangedSignal("Worker"..workerSlot..suffix):Connect(refreshWorker))
		end
		table.insert(homes[player].decorationConnections,player:GetAttributeChangedSignal("WorkerSlots"):Connect(refreshWorker))
		table.insert(homes[player].workerRefresh,refreshWorker)
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
					-- §27 part budget: blooms rest on the soil (no stem parts).
					local flower=center+V(-11+col*1.6,1.1,1+row*1.8)
					gem(addition,"Moonbloom",flower,V(.9,.7,.9),row%2==0 and rose or cream,col*.6)
				end
			end
		else
			-- §27: the deck stands on the big island; a boardwalk replaces the bridge.
			-- §40: the lookout deck stands out north (z 46, Data.Island "lookout deck").
			path(addition,center+V(0,0,16),center+V(0,0,39.5),5,timber,.1).Material=WO
			disk(addition,"Lookout deck",center+V(0,-.22,46),7,.6,timber,WO,true)
			for i=1,5 do
				local a=i*math.pi/3
				lamp(addition,center+V(math.cos(a)*6,0,46+math.sin(a)*6))
			end
			block(addition,"Lookout bench",center+V(0,.9,48),V(5,.4,1.7),navy,WO,true)
			block(addition,"Bench back",center+V(0,1.6,48.9),V(5,1.8,.3),brass,WO,false)
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
	if homeTerrace.garden then homeTerrace.garden(player,homes[player]) end -- Verdant Garden islet (Garden section)
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
-- Lazy homes: presence pass every LIVE_TICK seconds (task.wait returns the elapsed time).
if task.wait then
	task.spawn(function()
		local now=0
		while true do
			local dt=task.wait(HomeKit.LIVE_TICK)
			now+=(if type(dt)=="number" then dt else HomeKit.LIVE_TICK)
			HomeKit.step(now)
		end
	end)
end

-- Group islands are instantiated once per local crew; their build flags come
-- from the co-op service's persistent group record, never from client intent.
local CREW_R=46
local K=1.6 -- crew haven layout scale (wave 4)
local sharedHomes,sharedPlayers,sharedSlots,sharedConnections={},{},{},{}
local sharedBeacon=beaconPost(harbor,"Crew beacon",0,V(44,2,68),V(2,4,2),teal,"crew",{needs="crew",face=V(4,0,-4)})
sign(harbor,V(39,0,62),"Crew Haven","CO-OP / FORM A CREW IN THE ATLAS",mint,90,9)
anchor(hub,"Waypoint_CrewHaven",V(48,0,64),V(44,0,68))
anchor(hub,"NPC_Registrar",V(40,0,72),V(48,0,64))
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
	local exit=beaconPost(model,"Quay return",center.Y,center+V(0,2,16*K),V(2,4,2),mint,"return",{face=V(0,0,-1)})
	prompt(exit,"Return to hub","Compass Quay").Triggered:Connect(function(player)
		if sharedPlayers[player]==groupKey then warp(player,exit,HUB_ARRIVAL+V(-6,0,4)) end
	end)
	-- §42 (owner decision, overrides QC L9): the crew stores are struck like any
	-- node (no hold prompt); the break credits the crew store through
	-- coop.server.lua's IsleCoopStrike (same yields, caps and regrowth).
	local function supply(name,pos,color)
		local store=group("Shared "..name.." store",model)
		local base=block(store,"Shared "..name,center+pos,V(3,2,3),color,WO,true)
		base.Transparency=1
		sculpture(store,name.." supply marker",center+pos+V(0,.4,0),({Timber="TimberBundle",Ore="AetherCrystal",Herb="Moonbloom"})[name],1)
		Node.special(base,name,"crew","Shared "..name)
		base:SetAttribute("CoopId",groupId)
		base:SetAttribute("CoopPreview",isPreview)
		base:SetAttribute("IsleCoopResource",name)
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
		meshSlot(cloth,"Banner",mint,true)
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
-- Workers depth: worker type art for home stations (name, emblem shape, tint).
homeTerrace.workerArt=function(typeId)
	local t=Data.Workers and Data.Workers.TypeById[typeId]
	if not t then return nil end
	local ok,color=pcall(C,t.color)
	return {name=t.name,shape=t.shape,color=if ok then color else brass}
end
for _,home in pairs(homes) do for _,refresh in ipairs(home.workerRefresh or {}) do refresh() end end
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
-- §42: every node carries its tier HP (Data.Strike.maxHp) and the OSRS label
-- ("Mine Copperstone Vein (Mining 1)"); nodes built before AetherData loaded
-- (and home nodes built later) get them here.
function Node.stampHost(host)
	local id=host:GetAttribute("GatherNode")
	local r=Resource[id]
	if not r or not Data.Strike then return end
	host:SetAttribute("NodeMaxHp",Data.Strike.maxHp(r.def))
	host:SetAttribute("NodeLabel",Data.Strike.label(r.def))
	host:SetAttribute("ResourceId",id)
end
Node.stamp=Node.stampHost
for _,host in ipairs(Node.pending) do Node.stamp(host) end
table.clear(Node.pending)
local function gatherPrompt(target,id,region)
	local r=Resource[id]
	assert(r,"unknown resource "..tostring(id))
	return Node.gather(target,id,region)
end

-- Ore: a slate boulder split by a metal vein, crowned by a crystal cluster.
local function oreNode(parent,pos,id,region,scale)
	local r,s=Resource[id],scale or 1
	local m=group(r.def.name.." vein",parent)
	local base=part(m,"Ore boulder",V(4.4,2.3,3.8)*s,CFrame.new(pos+V(0,1.05*s,0))*CFrame.Angles(0,r.index,.08),darken(shale,.3),ST,false)
	meshSlot(base,"OreVein",r.color,true,"Uniform")
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
	meshSlot(trunk,"WindpineTree",color,true,"Uniform")
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
		meshSlot(trunk,"EmberoakTree",col,true,"Uniform")
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
		meshSlot(trunk,"GlimmerbarkTree",col,true,"Uniform")
		local crown=disk(m,"Glimmer crown",pos+V(0,11.6,0),4.8,1.3,col,GL,false)
		disk(m,"Glimmer underglow",pos+V(0,10.85,0),3.6,.25,lighten(col,.2),SM,false)
		disk(m,"Glimmer crest",pos+V(0,12.8,0),3,1,lighten(col,.25),GL,false)
		light(crown,col,.8,16,{lift=-2})
	elseif id=="StarwoodLog" then
		m=group(r.def.name.." tree",parent)
		collar=disk(m,"Root collar",pos+V(0,.6,0),1.6,1.2,darken(col,.3),WO,false)
		local trunk=disk(m,"Starwood trunk",pos+V(0,6.5,0),1,13,darken(col,.2),WO,true)
		meshSlot(trunk,"StarwoodTree",col,true,"Uniform")
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
		meshSlot(trunk,"AetherheartTree",col,true,"Uniform")
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
	meshSlot(pier,"FishingPier")
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
	meshSlot(bed,"CropBed",col,true)
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
	meshSlot(target,kind,nil,true)
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
	-- Endgame: quest-gated regions list the quest after the skills.
	local quests={}
	for _,id in ipairs(req.questsDone or {}) do
		local q=Data.QuestById[id]
		table.insert(quests,"QUEST: "..string.upper(q and q.title or id))
	end
	if req.skills then
		local names={}
		for skill in pairs(req.skills) do table.insert(names,skill) end
		table.sort(names)
		for _,skill in ipairs(names) do table.insert(out,string.upper(skill).." "..req.skills[skill]) end
	end
	for _,text in ipairs(quests) do table.insert(out,text) end
	return if #out>0 then "REQUIRES "..table.concat(out," · ") else "OPEN TO ALL WAYFARERS"
end
-- Gated and return beacons (§44): travelBeacon() adds the dais colliders, the
-- post stays the prompt host; one light at crystal height where the area allows it.
local function beaconProp(parent,pos,accent,withLight,kind,opts)
	local post=beaconPost(parent,"Warp beacon",pos.Y,pos+V(0,2.8,0),V(1.6,4,1.6),accent,kind,opts)
	if withLight~=false then light(post,accent,.7,12,{lift=.8}) end
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
	local post=beaconProp(parent,pos,REGION_ACCENT[regionId] or mint,withLight,"region",{region=regionId})
	local q=prompt(post,"Travel to "..region.name,requirementText(region))
	q:SetAttribute("IsleWarpRegion",regionId)
	q.Triggered:Connect(function(player) regionTravel(player,post,regionId,destination) end)
	anchor(parent,waypoint or ("Waypoint_Skyway_"..regionId),pos+V(0,0,-5),pos)
	return post
end
local function returnWarp(parent,pos,label,regionId)
	local post=beaconProp(parent,pos,mint,nil,"return")
	local q=prompt(post,"Return to the Skyway",label)
	q:SetAttribute("IsleWarpReturn","Hub")
	q.Triggered:Connect(function(player) warp(player,post,SKYWAY_LANDING) end)
	anchor(parent,"Waypoint_Return_"..regionId,pos+V(0,0,-5),pos)
	return post
end

-- Static ledger boards (§28 "ledger" archetype): a physical notice board (no
-- posts in v2); rows are named so live data can be written later.
local function ledger(parent,name,pos,toward,title,kicker,rows,accent,width,height)
	local ground=facing(pos,toward)
	local holder=group("Sign "..title,parent)
	holder:SetAttribute("SignArchetype","ledger")
	holder:SetAttribute("SignTitle",title)
	local themeName=Signs.theme(parent)
	local theme=Signs.THEMES[themeName]
	holder:SetAttribute("SignTheme",themeName)
	holder:SetAttribute("SignVersion",Signs.VERSION)
	pcall(function() holder.ModelStreamingMode=Enum.ModelStreamingMode.Atomic end)
	Tags:AddTag(holder,"AetherSign")
	-- v2: no notice posts; the board hangs on its own (live rows need a fixed face).
	local board=part(holder,name,V(width,height,.35),ground*CFrame.new(0,height/2+1.6,0),ink,WO,false)
	meshSlot(board,"SignNoticeBoard",theme.metal)
	board:SetAttribute("SignBoard",true)
	local pps=600/width
	local canvasH=math.floor(pps*height)
	local gui=Instance.new("SurfaceGui")
	gui.Name="Sign face Front"
	gui.Face,gui.SizingMode,gui.PixelsPerStud=Enum.NormalId.Front,Enum.SurfaceGuiSizingMode.PixelsPerStud,pps
	gui.LightInfluence,gui.Brightness,gui.MaxDistance=Signs.LIGHT,Signs.BRIGHTNESS,90
	gui:SetAttribute("SignStyled",true)
	gui.Parent=board
	local bg=Instance.new("Frame")
	bg.Name,bg.BorderSizePixel,bg.BackgroundColor3,bg.Size="Panel",0,theme.panel,UDim2.fromScale(1,1)
	bg.Parent=gui
	local grad=Instance.new("UIGradient")
	grad.Color,grad.Rotation=ColorSequence.new(theme.panel:Lerp(cream,.08),theme.panel:Lerp(C("05080C"),.3)),90
	grad.Parent=bg
	local rule=Instance.new("Frame")
	rule.Name,rule.BackgroundTransparency="Rule",1
	rule.Position,rule.Size=UDim2.fromOffset(10,10),UDim2.fromOffset(580,canvasH-20)
	rule.Parent=gui
	local stroke=Instance.new("UIStroke")
	stroke.Color,stroke.Thickness=theme.trim,3
	stroke.Parent=rule
	local function text(t,x,y,w,h,family,color,align,label,maxSize)
		local size=Signs.fit(t,w,h,1,maxSize or h/Signs.LINE,math.min(14,h/Signs.LINE))
		local l=Instance.new("TextLabel")
		l.Name=label or "Text"
		l.BackgroundTransparency,l.TextXAlignment=1,align or Enum.TextXAlignment.Left
		l.Position,l.Size=UDim2.fromOffset(x,y),UDim2.fromOffset(w,h)
		l.TextColor3,l.Text,l.TextScaled,l.TextWrapped,l.TextSize=color,t,false,true,size
		l.FontFace=Font.new(family,Enum.FontWeight.Bold)
		local s2=Instance.new("UIStroke")
		s2.Color,s2.Thickness,s2.Transparency=ink,1.5,.3
		s2.Parent=l
		l.Parent=gui
		return l
	end
	local bar=Instance.new("Frame")
	bar.BorderSizePixel,bar.BackgroundColor3=0,accent
	bar.Position,bar.Size=UDim2.fromOffset(22,22),UDim2.fromOffset(6,canvasH-44)
	bar.Parent=gui
	text((string.gsub(kicker,"%s*/%s*","  •  ")),40,20,540,28,Signs.FONT.body,accent:Lerp(cream,.35),nil,"Kicker")
	text(title,40,48,540,50,Signs.FONT.title,theme.text,nil,"Title")
	local rowH=math.min(30,math.floor((canvasH-114)/math.max(1,#rows)))
	for i,row in ipairs(rows) do
		local y=104+(i-1)*rowH
		text(row[1],40,y,300,rowH-4,Signs.FONT.body,theme.text,nil,"Row_"..row.key,20)
		text(row[2],330,y,240,rowH-4,Signs.FONT.body,accent:Lerp(cream,.3),Enum.TextXAlignment.Right,"Value_"..row.key,20)
	end
	-- QC M3: the same face on the back (readable from both sides of the hall)
	-- and a camera-facing title plaque floating above the board.
	local back=gui:Clone()
	back.Name,back.Face="Sign face Back",Enum.NormalId.Back
	back.Parent=board
	Signs.ledgerTitle(board,{title=title,kicker=kicker,accent=accent,width=width},theme,height/2+2.6)
	return board
end

-------------------------------------------------------------------------------
-- Guild Terrace (Hub): crafting stations, the Guild Hall and the Skyway.
-------------------------------------------------------------------------------
local terrace=regionIsle("Hub","Guild Terrace",GT,GT_R,{top=C("A7B08A"),vein=brass,gaps={-HALF}})
bridge(hub,V(0,0,HUB_R),GT-V(0,0,GT_R),"StoneArchBridge")
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
	if z==0 then meshSlot(col,"Column") end
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
	-- Cloth faces the hall's long sides (thin along its local Z, as the Banner mesh is).
	local pennant=part(hall,def.name.." pennant",V(2.6,2,.15),CFrame.new(HALL+V(0,23.6,z+1.4))*CFrame.Angles(0,math.pi/2,0),C(def.color),Enum.Material.Fabric,false)
	meshSlot(pennant,"Banner",C(def.color))
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
	meshSlot(boulder,"Rock",C("6E7B68"))
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
anchor(grovewild,"NPC_Grovekeeper",WP+V(-8,0,50),WP+V(0,0,58))
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
		if i%6==0 then meshSlot(wall,"CliffRock") end
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
meshSlot(heartCrystal,"AetherCrystal",void)
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
anchor(gloom,"NPC_Deepwarden",GH+V(-10,0,52),GH+V(0,0,62))
for _,x in ipairs({-16,16}) do
	local torch=block(gloom,"Cave torch",GH+V(x,1.8,54),V(.5,3.6,.5),timber,WO,false)
	meshSlot(torch,"Torch",C("B59CFF"))
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
meshSlot(shaft,"Lighthouse",rose,true)
for _,y in ipairs({6,12}) do disk(tower,"Tower stripe",LH+V(0,y,0),2.16,1.6,rose,SM,false) end
disk(tower,"Lantern room",LH+V(0,19.3,0),2.4,2.6,mint,GL,false).Transparency=.4
local lamphead=ball(tower,"Lighthouse flame",LH+V(0,19.3,0),1.4,C("FFF1B8"),NE)
disk(tower,"Lantern cap",LH+V(0,21,0),2.7,.7,brass,MT,false)
-- Hero light (shadows): the lighthouse lamp.
light(lamphead,C("FFF1B8"),1.2,48,{shadows=true,lift=0})
for _,r in ipairs({{V(70,0,30),3.4},{V(-4,0,74),2.6},{V(-72,0,-20),3},{V(14,0,-70),2.4}}) do
	local reef=part(tide,"Reef rock",V(r[2]*1.5,r[2],r[2]*1.2),CFrame.new(TW+r[1]+V(0,r[2]*.3,0))*CFrame.Angles(0,r[2],.12),C("7D8B92"),ST,false)
	meshSlot(reef,"Rock",C("7D8B92"))
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
	if i==1 then meshSlot(stone,"StormSpire",storm,true) end
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
	meshSlot(shaft,"StormPylon",storm)
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
sign(shelf,CS+V(12,0,-38),"Deep descent","GLOOMHOLLOW   /   "..requirementText(Data.RegionById.Gloomhollow),REGION_ACCENT.Gloomhollow,0,9,
	{arrows={{label="Gloomhollow Caverns",to=GH}}})

-------------------------------------------------------------------------------
-- Endgame (Endgame team; self-contained section): the Shattered Crown.
-- A gated archipelago high above the Tempest Spire (Combat 60 + the quest
-- Crown of the Tempest; region "ShatteredCrown"): the main isle (r 96) with the
-- broken crown on its dais, level 90+ gather nodes, two crafting stations and
-- four monster grounds, plus two bridged arena islets nested in its Model:
--   Sovereign's Dais (east): the Sovereign Altar (prompt IsleAction "bossSigil",
--     IsleItem "Aurelith", IsleRegion gate) and Anchor_WorldBoss_Aurelith.
--   Eclipse Roost (west): Anchor_WorldBoss_Nyxwyrm (calendar-scheduled boss).
-- combat.server.lua spawns world bosses on those anchors. The altar's four
-- sockets glow from workspace attribute WorldBossSigils_Aurelith ("n/4").
-- Reached by a gated beacon on the Tempest Spire; every marker sits >= 40 studs
-- from the landing.
-------------------------------------------------------------------------------
do
local E=Data.Endgame
local SC,SC_R=V(820,120,-600),96
local ARENA_R=40
local EAST,WEST=SC+V(160,0,0),SC+V(-160,0,0)
local gold,violet,glass=C("F2D27A"),C("8E6BD8"),C("BFF4FF")
local crownStone,crownStrata=C("3C3352"),C("54496E")
REGION_ACCENT.ShatteredCrown=gold
local crown=regionIsle("ShatteredCrown","The Shattered Crown",SC,SC_R,{top=C("6E6A8C"),stone=crownStone,stratum=crownStrata,vein=gold,ground=ST,gaps={0,math.pi}})
crown:SetAttribute("Endgame",true)
-- The broken crown: a raised dais ringed by eight leaning gold spires, with
-- fragments of the crown circlet hanging in the air above.
local DAIS=SC+V(0,0,-14)
local dais,daisTop=tier(crown,"Crown dais",DAIS,22,4,{cliff=crownStone,top=C("7C7698"),ground=ST,open={math.pi/2}})
ramp(crown,DAIS+V(0,0,26),DAIS+V(0,daisTop-DAIS.Y,20),7,crownStrata,ST)
local spires=group("Shattered crown",dais)
for i=1,8 do
	local a=i*2*math.pi/8+.2
	local h=14+(i%3)*6
	local base=DAIS+V(math.cos(a)*15,daisTop-DAIS.Y,math.sin(a)*15)
	local spire=part(spires,"Crown spire",V(2.6,h,2.6),CFrame.new(base+V(0,h/2-1,0))*CFrame.Angles(0,-a,0)*CFrame.Angles(0,0,math.rad(if i%2==0 then 14 else -9)),
		if i%2==0 then gold else lighten(gold,.25),GL,false)
	if i%4==1 then meshSlot(spire,"Obelisk",gold) end
	if i%2==1 then
		local tip=part(spires,"Spire gem",V(1.2,2.4,1.2),CFrame.new(base+V(0,h+.6,0))*CFrame.Angles(0,a,math.pi/4),violet,NE,false)
		if i%4==1 then light(tip,violet,.8,18) end
	end
end
local heart=ball(spires,"Crown heart",DAIS+V(0,daisTop-DAIS.Y+9,0),3.4,gold,NE)
light(heart,gold,1.1,40,{lift=0})
motes(heart,gold,5,3,.35)
for i=1,6 do
	local a=i*2*math.pi/6
	local frag=part(spires,"Circlet fragment",V(9,1.6,2.2),CFrame.new(DAIS+V(math.cos(a)*19,34+(i%2)*5,math.sin(a)*19))*CFrame.Angles(0,-a+math.pi/2,math.rad((i%3-1)*18)),gold,MT,false)
	frag.CastShadow=false
end
-- Drifting shards and broken islets around the rim (pure scenery).
for i=1,8 do
	local a=(i+.3)*2*math.pi/8
	local d=SC_R+18+(i%3)*10
	local s=4+(i%4)*2
	local isle=part(crown,"Drifting shard",V(s*2,s*1.4,s*1.6),CFrame.new(SC+V(math.cos(a)*d,-6+(i%3)*7,math.sin(a)*d))*CFrame.Angles(.3,a,.2),i%2==0 and crownStone or crownStrata,ST,false)
	if i%2==0 then meshSlot(isle,"CliffRock") end
	gem(crown,"Shard crystal",isle.CFrame.Position+V(0,s*.9,0),V(1.2,s*.9,1.2),i%2==0 and gold or violet,a)
end
for i,o in ipairs({V(-82,0,-34),V(82,0,-38),V(-34,0,-78),V(36,0,-80)}) do outcrop(crown,SC+o,1.4,i+20) end
-- Landing, return beacon and sign (south rim).
local LANDING=SC+V(0,4,74)
returnWarp(crown,SC+V(14,0,80),"The Shattered Crown","ShatteredCrown")
sign(crown,SC+V(-16,0,82),"The Shattered Crown",requirementText(Data.RegionById.ShatteredCrown),gold,0,12)
anchor(crown,"Waypoint_Entrance_ShatteredCrown",SC+V(0,0,66),SC)
for _,x in ipairs({-9,9}) do lamp(crown,SC+V(x,0,60)) end
-- Crafting: the Crownforge (Sovereign plate, Crownsteel) and a glyph cauldron (Crown Sigils).
station(crown,"Forge",SC+V(-30,0,46),SC+V(0,0,64),"Crownforge","CrownForge")
station(crown,"Cauldron",SC+V(30,0,46),SC+V(0,0,64),"Sigil cauldron","CrownCauldron")
-- Level 90+ gather nodes.
oreNode(crown,SC+V(-72,0,-12),"Crownstone","ShatteredCrown",1.3)
oreNode(crown,SC+V(70,0,-14),"Crownstone","ShatteredCrown",1.3)
local function shatterbark(pos)
	local r=Resource.ShatterbarkLog
	local m=group(r.def.name.." tree",crown)
	local collar=disk(m,"Root collar",pos+V(0,.6,0),2,1.2,darken(r.color,.5),WO,false)
	local trunk=disk(m,"Shatterbark trunk",pos+V(0,8,0),1.3,16,darken(r.color,.35),WO,true)
	meshSlot(trunk,"StarwoodTree",r.color,true,"Uniform")
	for i=1,3 do
		local a=i*2*math.pi/3
		gem(m,"Bark shard",pos+V(math.cos(a)*1.6,5+i*2.5,math.sin(a)*1.6),V(.8,3.2,.8),lighten(r.color,.2),a)
	end
	ball(m,"Crystal canopy",pos+V(0,17,0),9,r.color,GL).Transparency=.15
	ball(m,"Crystal canopy",pos+V(2.6,19.5,1),5.5,lighten(r.color,.2),GL).Transparency=.15
	gatherPrompt(collar,"ShatterbarkLog","ShatteredCrown")
	return m
end
shatterbark(SC+V(-58,0,40))
shatterbark(SC+V(60,0,38))
local _,riftPool=pond(crown,SC+V(-4,0,40),7,{name="Riftfin pool",water=C("6E5BD8"),bank=crownStrata})
riftPool.Material=GL
fishSpot(crown,SC+V(-4,0,40),"Riftfin","ShatteredCrown",V(1,0,0),5)
-- Monster grounds (each >= 40 studs from the landing; open ground).
spawnMarker("RiftmawStalker",SC+V(-52,0,6),3,8)
spawnMarker("ShardglassSeer",SC+V(50,0,8),2,8)
spawnMarker("CrownforgedColossus",SC+V(-42,0,-56),2,8)
spawnMarker("VoidcrownDrake",SC+V(42,0,-58),2,8)

-- Arena islets (nested island Models: the crown Model is the region island).
local function arena(name,center,gapAngle,top,accent)
	local m=island(name,center,ARENA_R,{parent=crown,region="ShatteredCrown",top=top,stone=crownStone,stratum=crownStrata,vein=accent,ground=ST,gaps={gapAngle},shore=false})
	m:SetAttribute("WorldBossArena",true)
	disk(m,"Arena floor",center+V(0,.04,0),ARENA_R-8,.08,darken(top,.15),Enum.Material.Slate,false)
	disk(m,"Arena sigil ring",center+V(0,.1,0),ARENA_R-9.5,.04,accent,Enum.Material.Fabric,false).Transparency=.4
	for i=1,6 do
		local a=i*2*math.pi/6+math.pi/6
		local col=block(m,"Arena column",center+V(math.cos(a)*(ARENA_R-4),5,math.sin(a)*(ARENA_R-4)),V(2.4,10,2.4),lighten(crownStrata,.2),Enum.Material.Marble,true)
		if i%2==1 then meshSlot(col,"RuinColumn") end
		local cap=part(m,"Column flame",V(1,1,1),CFrame.new(col.CFrame.Position+V(0,5.8,0))*CFrame.Angles(math.pi/4,a,math.pi/4),accent,NE,false)
		if i%3==1 then light(cap,accent,.7,16) end
	end
	return m
end
local east=arena("Sovereign's Dais",EAST,math.pi,C("8A7E58"),gold)
local west=arena("Eclipse Roost",WEST,0,C("4C4166"),violet)
bridge(crown,SC+V(SC_R,0,0),EAST-V(ARENA_R,0,0),"CrystalBridge",gold)
bridge(crown,SC-V(SC_R,0,0),WEST+V(ARENA_R,0,0),"CrystalBridge",C("B59CFF"))
anchor(crown,"WorldBoss_Aurelith",EAST,SC)
anchor(crown,"WorldBoss_Nyxwyrm",WEST,SC)
anchor(crown,"Waypoint_Bridge_SovereignsDais",SC+V(SC_R-6,0,0),EAST)
anchor(crown,"Waypoint_Bridge_EclipseRoost",SC-V(SC_R-6,0,0),WEST)
sign(east,EAST+V(-ARENA_R+10,0,14),"Sovereign's Dais","WORLD BOSS   /   AURELITH · PLACE 4 CROWN SIGILS",gold,90,11)
sign(west,WEST+V(ARENA_R-10,0,14),"Eclipse Roost","WORLD BOSS   /   NYXWYRM RIDES AT EVERY ISLE DUSK",violet,-90,11)
-- The Sovereign Altar: four sigil sockets on a plinth at the dais edge.
do
	local ALTAR=EAST+V(-ARENA_R+12,0,-10)
	local altar=group("Sovereign Altar",east)
	block(altar,"Altar step",ALTAR+V(0,.3,0),V(7,.6,7),crownStrata,ST,true)
	local plinth=block(altar,"Altar plinth",ALTAR+V(0,1.9,0),V(4,2.6,4),lighten(crownStrata,.25),Enum.Material.Marble,true)
	meshSlot(plinth,"Waystone",gold)
	local sockets={}
	for i=1,E and Data.WorldBosses.Aurelith.sigils or 4 do
		local a=i*math.pi/2+math.pi/4
		sockets[i]=ball(altar,"Sigil socket",ALTAR+V(math.cos(a)*1.4,3.45,math.sin(a)*1.4),.8,ink,GL)
	end
	local flame=part(altar,"Altar flame",V(1.2,1.2,1.2),CFrame.new(ALTAR+V(0,4.4,0))*CFrame.Angles(math.pi/4,0,math.pi/4),gold,NE,false)
	light(flame,gold,.9,16)
	local q=prompt(plinth,"Place Crown Sigil","Sovereign Altar · Aurelith","bossSigil","Aurelith")
	q:SetAttribute("IsleRegion","ShatteredCrown")
	q.MaxActivationDistance=10
	anchor(crown,"Waypoint_SovereignAltar",ALTAR+V(6,0,0),ALTAR)
	local function refresh()
		local value=workspace:GetAttribute("WorldBossSigils_Aurelith")
		local placed=tonumber(type(value)=="string" and value:match("^(%d+)/") or 0) or 0
		for i,socket in ipairs(sockets) do
			socket.Color=if i<=placed then gold else ink
			socket.Material=if i<=placed then NE else GL
		end
	end
	pcall(function() workspace:GetAttributeChangedSignal("WorldBossSigils_Aurelith"):Connect(refresh) end)
	refresh()
end
-- The Eclipse Roost perch: a dark obelisk the Tyrant lands beside.
do
	local perch=block(west,"Roost obelisk",WEST+V(0,7,-ARENA_R+10),V(3,14,3),C("2B2440"),ST,true)
	meshSlot(perch,"Obelisk",violet)
	local eye=part(west,"Roost eye",V(1.4,1.4,1.4),CFrame.new(perch.CFrame.Position+V(0,8,0))*CFrame.Angles(math.pi/4,0,math.pi/4),violet,NE,false)
	light(eye,violet,.8,18)
end
-- Gated beacon on the Tempest Spire (the storm's heart opens the way up).
local tempestIsle=islandsFolder:FindFirstChild("Tempest Spire")
if tempestIsle then
	regionWarp(tempestIsle,TS+V(-34,0,34),"ShatteredCrown",LANDING,"Waypoint_Skyway_ShatteredCrown")
	sign(tempestIsle,TS+V(-34,0,44),"The Shattered Crown",requirementText(Data.RegionById.ShatteredCrown),gold,0,10,
		{kind="post",arrows={{label="The Shattered Crown",to=SC}}})
end
end
-- End Endgame section.

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
		-- §27: a paved plaza on the big island (was a bridged islet); same offsets.
		local terrace=HomeKit.plaza(m,"Builders Terrace",tc,11,C("A7B08A"))
		home.terrace=terrace
		-- §40: the terrace stands out west (Data.TERRACE_OFFSET); the walk reaches its plaza.
		path(terrace,center+V(-16,0,0),center+V(T.x+11,0,0),5)
		disk(terrace,"Terrace court",tc+V(0,.05,0),4.2,.12,navy,ST,true)
		disk(terrace,"Court seal",tc+V(0,.13,0),1.4,.1,brass,MT,false)
		-- §40 QC: the sign stands at the terrace, beside the walk (Data.Island "terrace sign").
		sign(terrace,center+V(T.x+14,0,-9),"Builder's Terrace","CARPENTRY   /   PLAN IN YOUR JOURNAL",brass,90,8)
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
			plinths[h.id].Transparency=if id then 1 else 0
			-- §27 lazy homes: furniture is built only while the home is live.
			local want=if home.live and m.Parent then id else nil
			if built[h.id] and built[h.id].id==want then return end
			if built[h.id] then built[h.id].model:Destroy() end
			built[h.id]=nil
			if h.id=="Portal" then portalPrompt=nil end
			if not want then return end
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
		table.insert(home.liveHooks,function() for _,h in ipairs(Data.Hotspots) do refresh(h) end end)
	end
	for player,home in pairs(homes) do homeTerrace.attach(player,home) end
end

-------------------------------------------------------------------------------
-- Island placement (Island Builder team). The server publishes the owner's
-- free-form placements as player attribute IslandPlacements ("id:prop:x:z:rot"
-- records joined by ";", Data.Island grid). Each record becomes an anchored
-- primitive model (<= 12 parts, Data.Island.Props[prop].parts) named
-- Placement_<id> in the home's Placements folder; a change rebuilds only the
-- records that differ, and at most Data.Island.PART_BUDGET parts are built.
-- §27 lazy homes: the folder stays, its models exist only while the home is
-- live (HomeKit.setLive). The folder goes with the home model when the player leaves. Player attribute IslandCenter lets the
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
			g.light:SetAttribute("LightWanted",ok) -- §35 QC M1: the director reads intent, not Enabled
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
			-- §27 lazy homes: nothing is built while the home is dormant.
			local want,occupied,parts={},{},0
			local stage=(home.level or 1)-1 -- §27: the grid grows with the Homestead level
			for _,e in ipairs(if home.live then I.decode(player:GetAttribute("IslandPlacements")) else {}) do
				local cost=I.Props[e.prop].parts
				if not want[e.id] and parts+cost<=I.PART_BUDGET and I.check(occupied,e.prop,e.x,e.z,e.rot,stage) then
					want[e.id]=e
					parts+=cost
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
		home.refreshPlacements=refresh
		table.insert(home.liveHooks,refresh)
		refresh()
	end
	for player,home in pairs(homes) do homePlacement.attach(player,home) end
end


-------------------------------------------------------------------------------
-- Agility & Hunter (New Skills team; self-contained section). Agility courses
-- (a loop of floating perches beside a region island), shortcuts between
-- islands, hunting grounds and the two skill vendors. Data lives in
-- Data.Agility / Data.Hunter; server.server.lua (Skills block) validates every
-- prompt. Each built Model carries attribute SkillContent ("Agility"|"Hunter")
-- and sits inside its island Model (Workspace.Islands keeps twelve islands).
-- Prompt attributes (all interact holds, server-validated):
--   agility     IsleItem "<course>:<index>", AgilityCourse, AgilityIndex, AgilityKind,
--               AgilityEnd (landing Vector3), AgilityFall (fall landing Vector3), IsleRegion
--   shortcut    IsleItem "<id>:A|B", ShortcutTo (landing Vector3), AgilityKind, IsleRegion,
--               ShortcutRegion (this end's destination region, "" = ungated)
--   trap / net  IsleItem creature id, HunterMethod, HunterSpot "<creature>#<n>", IsleRegion;
--               the server writes TrapState / TrapOwner on the prompt's host part
--   skillVendor IsleItem "Agility" | "Hunter"
-- Obstacle, shortcut and trap props are mesh slots: new shape names
-- (ClimbNet, BalanceBeam, RopeSwing, LedgeWalk, ZipLine, SlideChute,
-- SnareTrap, BirdPerch, SwarmBloom, AgilityPerch) render as primitives until the Mesh team adds them.
-------------------------------------------------------------------------------
local function buildSkillContent()
	local AG,HU=Data.Agility,Data.Hunter
	if not AG or not HU then return end
	local GATED={}
	for _,r in ipairs(Data.Regions) do if next(r.requires) then GATED[r.id]=true end end
	local function isle(name)
		local m=islandsFolder:FindFirstChild(name)
		assert(m,"skills: unknown island "..name)
		return m,m:GetAttribute("IslandCenter"),m:GetAttribute("IslandRadius")
	end
	local function flat(v) return V(v.X,0,v.Z) end
	local function content(parent,name,skill)
		local m=group(name,parent)
		m:SetAttribute("SkillContent",skill)
		return m
	end
	local function region(q,id) if id and GATED[id] then q:SetAttribute("IsleRegion",id) end end
	-- A connector from a to b (top surface centre line), width w, thickness t.
	-- First candidate spot (ground level) with no existing prop within `radius`
	-- studs (XZ) and 7 studs above; island floors and our own content are ignored.
	local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
		["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Path=true,Wildflowers=true}
	local function freeSpot(host,candidates,radius)
		for _,pos in ipairs(candidates) do
			local clear=true
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local node,ours=obj.Parent,false
					while node and node~=host do if node:GetAttribute("SkillContent") then ours=true break end node=node.Parent end
					if not ours then
						local cf,sz=obj.CFrame,obj.Size
						local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
						local c=cf.Position
						local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
						local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
						local ey=ext("Y")
						if dx*dx+dz*dz<radius*radius and c.Y+ey>pos.Y+.3 and c.Y-ey<pos.Y+7 then clear=false break end
					end
				end
			end
			if clear then return pos,true end
		end
		return candidates[1],false
	end
	local function span(m,name,a,b,w,t,color,mat,solid)
		return part(m,name,V(w,t,(b-a).Magnitude),CFrame.lookAt((a+b)/2-V(0,t/2,0),b-V(0,t/2,0)),color,mat,solid==true)
	end

	-- Course sites: island, outward angle (degrees), ring radius, palette.
	local SITES={
		QuayRigging={isle="Compass Quay",angle=245,ring=26,perch=C("C9B994"),rock=rock,wood=timber,mat=WO},
		MosswakeHedgerow={isle="Mosswake Grove",angle=270,ring=26,perch=C("86AE69"),rock=C("6E7B68"),wood=C("7A5A40"),mat=Enum.Material.Grass},
		BrassfallScaffold={isle="Brassfall Quarry",angle=90,ring=26,perch=C("9C9682"),rock=shale,wood=C("7A5A40"),mat=GR},
		WindpineCanopy={isle="Windpine Grove",angle=290,ring=30,perch=C("5F8A57"),rock=C("3F4B44"),wood=darken(timber,.25),mat=LEAF},
		SkyreachUpdraft={isle="Skyreach",angle=80,ring=30,perch=C("A3B8B4"),rock=C("5F6F74"),wood=brass,mat=ST},
		TidewaterMastwalk={isle="Tidewater Shoals",angle=80,ring=30,perch=C("D9C9A0"),rock=C("7D8B92"),wood=C("A57C55"),mat=SA},
		GloomhollowChasm={isle="Gloomhollow Caverns",angle=270,ring=32,perch=C("3A3F52"),rock=C("2B2F3D"),wood=C("5A4E7A"),mat=ST},
		TempestStormrun={isle="Tempest Spire",angle=270,ring=32,perch=C("4A5266"),rock=C("2E3445"),wood=C("3B4256"),mat=ST},
	}
	local PERCH_R=4.5
	-- Height change across an obstacle (studs); jitter keeps every top distinct.
	local RISE={climb=3,beam=.6,swing=-1.2,ledge=1.4,gap=-.8,vault=.9,zip=-2.5,drop=-2}
	local function perch(m,top,style,k)
		local p=disk(m,"Agility perch",top-V(0,.6,0),PERCH_R,1.2,style.perch,style.mat,true)
		meshSlot(p,"AgilityPerch",style.perch)
		local keel=part(m,"Perch keel",V(5.4,6,5),CFrame.new(top-V(0,4.4,0))*CFrame.Angles(.12,k*1.7,.1),style.rock,ST,false)
		meshSlot(keel,"CliffRock")
		for i=0,3 do
			local d=V(math.cos(i*HALF),0,math.sin(i*HALF))
			local c=top+d*(PERCH_R+.4)+V(0,4.5,0)
			local guard=part(m,"Perch guard",V(.6,9,2*PERCH_R+1.6),CFrame.lookAt(c,c+V(-d.Z,0,d.X)),cream,SM,true)
			guard.Transparency,guard.CastShadow=1,false
		end
		return p
	end
	-- Obstacle props between perch tops a and b (both perches PERCH_R wide).
	local function obstacleProps(m,kind,a,b,style)
		local dir=flat(b-a).Unit
		local side=V(-dir.Z,0,dir.X)
		local aE,bE=a+dir*(PERCH_R-.6),b-dir*(PERCH_R-.6)
		if kind=="climb" then
			meshSlot(span(m,"Climbing net",aE+V(0,.3,0),bE+V(0,.3,0),3,.3,C("C9B994"),Enum.Material.Fabric),"ClimbNet",style.wood)
			for _,s in ipairs({-1.6,1.6}) do span(m,"Net rail",aE+side*s+V(0,.5,0),bE+side*s+V(0,.5,0),.3,.3,style.wood,WO) end
		elseif kind=="beam" then
			meshSlot(span(m,"Balance beam",aE+V(0,.35,0),bE+V(0,.35,0),.9,.55,style.wood,WO),"BalanceBeam",style.wood)
		elseif kind=="swing" then
			local mid=(aE+bE)/2
			span(m,"Swing cable",aE+V(0,12.2,0),bE+V(0,12.2,0),.22,.22,ink,MT)
			for _,e in ipairs({aE,bE}) do block(m,"Swing mast",e+V(0,6.1,0),V(.5,12.2,.5),style.wood,WO,false) end
			meshSlot(block(m,"Swing rope",mid+V(0,7.6,0),V(.3,9.2,.3),C("C9B994"),Enum.Material.Fabric,false),"RopeSwing",style.wood)
		elseif kind=="ledge" then
			meshSlot(span(m,"Ledge walk",aE+side*1.4+V(0,.25,0),bE+side*1.4+V(0,.25,0),1.3,.5,style.rock,ST),"LedgeWalk",style.rock)
			local wall=span(m,"Ledge wall",aE+side*2.6+V(0,5.2,0),bE+side*2.6+V(0,5.2,0),.9,5.6,style.rock,ST)
			meshSlot(wall,"CliffRock")
		elseif kind=="gap" then
			for i,t in ipairs({.36,.66}) do
				local p=aE:Lerp(bE,t)-V(0,.4+i*.21,0)
				meshSlot(part(m,"Stepping stone",V(2.6,1.2,2.4),CFrame.new(p)*CFrame.Angles(0,i*1.3,.06),style.rock,ST,false),"Rock",style.rock)
			end
		elseif kind=="vault" then
			span(m,"Vault plank",aE+V(0,.2,0),bE+V(0,.2,0),2.2,.4,style.wood,WO)
			local mid=(aE+bE)/2
			meshSlot(part(m,"Vault crate",V(2.6,1.8,1.6),CFrame.lookAt(mid+V(0,1.3,0),mid+V(0,1.3,0)+side),C("8C6A4A"),WO,false),"Crate")
		elseif kind=="zip" then
			block(m,"Zip tower",aE+V(0,4.2,0),V(.6,8.4,.6),style.wood,WO,false)
			meshSlot(span(m,"Zip cable",aE+V(0,8.1,0),bE+V(0,3.1,0),.18,.18,ink,MT),"ZipLine",ink)
		elseif kind=="drop" then
			meshSlot(span(m,"Slide chute",aE+V(0,.25,0),bE+V(0,.25,0),2.6,.4,style.wood,WO),"SlideChute",style.wood)
			for _,s in ipairs({-1.4,1.4}) do span(m,"Chute rail",aE+side*s+V(0,.6,0),bE+side*s+V(0,.6,0),.25,.4,brass,MT) end
		end
	end

	local courseCount=0
	for _,course in ipairs(AG.Courses) do
		local site=SITES[course.id]
		local host,IC,R=isle(site.isle)
		local m=content(host,"Agility course "..course.name,"Agility")
		m:SetAttribute("AgilityCourse",course.id)
		local a=math.rad(site.angle)
		local dir=V(math.cos(a),0,math.sin(a))
		local tangent=V(-dir.Z,0,dir.X)
		local startDist=R-9
		local n=#course.obstacles
		local O=IC+dir*(startDist+site.ring)
		-- Perch tops: k=1 is the start plinth on the island, the rest float.
		local tops={}
		local h=10
		for k=1,n do
			if k==1 then
				tops[1]=IC+dir*startDist+V(0,.55,0)
			else
				local phi=a+math.pi+(k-1)*2*math.pi/n
				tops[k]=O+V(math.cos(phi),0,math.sin(phi))*site.ring+V(0,h+.13*k,0)
				h=math.clamp(h+RISE[course.obstacles[k].kind],7,16)
			end
		end
		local plinth=disk(m,"Course start",tops[1]-V(0,.3,0),5,.6,site.perch,site.mat,true)
		meshSlot(plinth,"AgilityPerch",site.perch)
		for k=2,n do perch(m,tops[k],site,k) end
		local fall=IC+dir*(startDist-9)+V(0,3.5,0)
		for i,o in ipairs(course.obstacles) do
			local from,to=tops[i],tops[i%n+1]
			obstacleProps(m,o.kind,from,to,site)
			local d=flat(to-from).Unit
			local marker=block(m,"Obstacle marker",from+d*(PERCH_R-1.2)+V(0,1.6,0),V(.7,3.2,.7),C(course.color),MT,false)
			meshSlot(marker,"BridgePost",C(course.color))
			marker:SetAttribute("AgilityIndex",i)
			local kind=AG.Kinds[o.kind]
			local q=prompt(marker,kind.verb,o.name.." · "..course.name.." (Lv "..course.level..")","agility",course.id..":"..i)
			q:SetAttribute("AgilityCourse",course.id)
			q:SetAttribute("AgilityIndex",i)
			q:SetAttribute("AgilityKind",o.kind)
			q:SetAttribute("AgilityEnd",to+V(0,3,0))
			q:SetAttribute("AgilityFall",fall)
			region(q,course.region)
		end
		local ground=tops[1]-V(0,.55,0)
		local signPos=freeSpot(host,{ground-dir*7+tangent*8,ground-dir*7-tangent*8,ground-dir*13+tangent*5,ground-dir*13-tangent*5,ground-dir*16},5)
		signAt(m,CFrame.lookAt(signPos,signPos-dir),course.name,"AGILITY "..course.level.."   /   "..n.." OBSTACLES",C(course.color),9)
		-- QC L5: no course banner pole (posts are gone); the floating sign names the course.
		anchor(m,"Waypoint_Agility_"..course.id,tops[1]-dir*7-V(0,.55,0),tops[1])
		courseCount+=1
	end

	-- Shortcuts: two islands, end plinths on the facing rims, a path of props.
	local SHORTCUT_SITES={
		CinderSlide={a="Brassfall Quarry",b="Cinder Shelf",shiftA=V(28,0,0),shiftB=V(28,0,0)},
		MosswakeRopeBridge={a="Mosswake Grove",b="Windpine Grove"},
		SkyreachUpdraft={a="Brassfall Quarry",b="Skyreach"},
		TidewaterSteps={a="Meadow Reach",b="Tidewater Shoals",shiftA=V(7,0,8)},
		GloomRappel={a="Cinder Shelf",b="Gloomhollow Caverns",shiftA=V(-4,0,14)},
		TempestGaleLine={a="Skyreach",b="Tempest Spire"},
	}
	for _,sc in ipairs(AG.Shortcuts) do
		local site=SHORTCUT_SITES[sc.id]
		local hostA,CA,RA=isle(site.a)
		local hostB,CB,RB=isle(site.b)
		local dir=flat(CB-CA).Unit
		local side=V(-dir.Z,0,dir.X)
		local function endSpot(host,pos,inward)
			return (freeSpot(host,{pos,pos+side*6,pos-side*6,pos+inward*6,pos+side*12,pos-side*12,pos+inward*6+side*8,pos+inward*6-side*8,pos+inward*12},4.2))
		end
		local endA=endSpot(hostA,CA+dir*(RA-10)+(site.shiftA or V(0,0,0)),-dir)
		local endB=endSpot(hostB,CB-dir*(RB-10)+(site.shiftB or V(0,0,0)),dir)
		local landA,landB=endA-dir*5+V(0,3.5,0),endB+dir*5+V(0,3.5,0)
		for _,e in ipairs({{"A",hostA,endA,landB,endB,hostB},{"B",hostB,endB,landA,endA,hostA}}) do
			local tag,host,pos,landing,other,destHost=e[1],e[2],e[3],e[4],e[5],e[6]
			local m=content(host,"Shortcut "..sc.name.." "..tag,"Agility")
			m:SetAttribute("AgilityShortcut",sc.id)
			local toward=flat(other-pos).Unit
			disk(m,"Shortcut plinth",pos+V(0,.2,0),3,.5,C("8B8574"),ST,true)
			local post=block(m,"Shortcut post",pos+toward*1.6+V(0,2.45,0),V(.8,4,.8),C(Data.Skills.Agility.color),MT,false)
			meshSlot(post,"BridgePost",C(Data.Skills.Agility.color))
			local kind=AG.Kinds[sc.kind]
			local q=prompt(post,kind.verb.." shortcut",sc.name.." (Agility "..sc.level..")","shortcut",sc.id..":"..tag)
			q:SetAttribute("ShortcutTo",landing)
			-- Per-end destination region ("" = ungated): the server gates on where this end lands.
			local destRegion=destHost:GetAttribute("Region")
			q:SetAttribute("ShortcutRegion",if destRegion and GATED[destRegion] then destRegion else "")
			q:SetAttribute("AgilityKind",sc.kind)
			region(q,sc.region)
			local side=V(-toward.Z,0,toward.X)
			local signPos=freeSpot(host,{pos-toward*3+side*5,pos-toward*3-side*5,pos+side*6,pos-side*6,pos-toward*8,pos-toward*6+side*7,pos-toward*6-side*7},4.5)
			signAt(m,CFrame.lookAt(signPos,signPos-toward),sc.name,"AGILITY "..sc.level.." SHORTCUT",C(Data.Skills.Agility.color),8,
				{kind="post",arrows={{label=kind.verb.." here",to=pos}}})
			anchor(m,"Waypoint_Shortcut_"..sc.id.."_"..tag,pos-toward*5,pos)
		end
		-- Path props hang from island A's model (non-colliding: only the shortcut moves you).
		local path=content(hostA,"Shortcut path "..sc.name,"Agility")
		local from,to=endA+dir*3+V(0,.6,0),endB-dir*3+V(0,.6,0)
		local segments=if (to-from).Magnitude<60 then 2 else 7
		local function along(t,sag)
			return from:Lerp(to,t)-V(0,(sag or 0)*4*t*(1-t),0)
		end
		for i=1,segments do
			local p0,p1=along((i-1)/segments,if sc.kind=="beam" then 6 else 0),along(i/segments,if sc.kind=="beam" then 6 else 0)
			if sc.kind=="beam" then
				span(path,"Rope bridge deck",p0,p1,3,.3,timber,WO)
				span(path,"Rope bridge rope",p0+V(0,2.2,0)+V(-dir.Z,0,dir.X)*1.6,p1+V(0,2.2,0)+V(-dir.Z,0,dir.X)*1.6,.15,.15,C("C9B994"),Enum.Material.Fabric)
			elseif sc.kind=="zip" or (sc.kind=="drop" and segments>2) then
				meshSlot(span(path,if sc.kind=="zip" then "Gale line" else "Rappel line",p0+V(0,6,0),p1+V(0,6,0),.2,.2,ink,MT),if sc.kind=="zip" then "ZipLine" else "RopeSwing",ink)
			elseif sc.kind=="drop" then
				meshSlot(span(path,"Slide chute",p0,p1,3,.4,C("7A5A40"),WO),"SlideChute",C("7A5A40"))
			else
				local p=along((i-.5)/segments,0)-V(0,.5,0)
				meshSlot(part(path,if sc.kind=="climb" then "Updraft hold" else "Drifting stone",V(3.2,1.4,2.8),CFrame.new(p)*CFrame.Angles(.1,i*.9,.08),C("7D8B92"),ST,false),"Rock",C("7D8B92"))
			end
		end
	end

	-- Hunting grounds: spots ringed around a centre (offset from the island centre).
	local GROUNDS={
		PuffcapHopper={isle="Meadow Reach",at=V(-14,0,4),name="Hopper Warren"},
		SunwingMoth={isle="Mosswake Grove",at=V(-6,0,-51),name="Sunwing Glade"},
		PinecrestGrouse={isle="Windpine Grove",at=V(-25,0,5),name="Grouse Perches"},
		CinderFerret={isle="Cinder Shelf",at=V(-40,0,-6),name="Ferret Dens"},
		GlintwingDragonfly={isle="Tidewater Shoals",at=V(22,0,-26),name="Glintwing Shallows"},
		GaleKestrel={isle="Skyreach",at=V(-18,0,-18),name="Kestrel Roost"},
		GloomLynx={isle="Gloomhollow Caverns",at=V(-10,0,20),name="Lynx Dens"},
		StormmaneIbex={isle="Tempest Spire",at=V(-16,0,4),name="Ibex Trail"},
	}
	for _,creature in ipairs(HU.Creatures) do
		local g=GROUNDS[creature.id]
		local host,IC=isle(g.isle)
		local m=content(host,"Hunting ground "..g.name,"Hunter")
		m:SetAttribute("HunterCreature",creature.id)
		local center=IC+g.at
		local method=HU.Methods[creature.method]
		local spots=if method.trap then 4 else 3
		local tint=C(creature.color)
		for i=1,spots do
			local ang=i*2*math.pi/spots+.4
			local p=center+V(math.cos(ang),0,math.sin(ang))*5
			local hostPart
			if creature.method=="snare" then
				hostPart=disk(m,"Snare patch",p+V(0,.09,0),1.4,.12,darken(turf,.25),GR,false)
				meshSlot(block(m,"Snare stake",p+V(0,.7,0),V(.25,1.2,.25),timber,WO,false),"SnareTrap",timber)
			elseif creature.method=="box" then
				hostPart=block(m,"Box trap",p+V(0,.6,0),V(1.8,1.2,1.4),C("8C6A4A"),WO,false)
				meshSlot(hostPart,"Crate")
			elseif creature.method=="bird" then
				hostPart=block(m,"Bird perch",p+V(0,1.5,0),V(.3,3,.3),timber,WO,false)
				meshSlot(hostPart,"BirdPerch",timber)
				block(m,"Perch crossbar",p+V(0,2.62,0),V(1.6,.2,.2),darken(timber,.2),WO,false)
			else
				flowers(m,p,2,tint,.07+i*.013)
				hostPart=ghost(block(m,"Swarm",p+V(0,1.8,0),V(1.5,1.5,1.5),tint,SM,false))
				meshSlot(hostPart,"SwarmBloom",tint)
				motes(hostPart,tint,3,1.2,.18)
			end
			hostPart:SetAttribute("HunterSpot",creature.id.."#"..i)
			hostPart:SetAttribute("TrapState","")
			local q=prompt(hostPart,method.verb,creature.name.." (Hunter "..creature.level..")",if method.trap then "trap" else "net",creature.id)
			q:SetAttribute("HunterMethod",creature.method)
			q:SetAttribute("HunterSpot",creature.id.."#"..i)
			region(q,creature.region)
		end
		local toCenter=flat(IC-center)
		local face=if toCenter.Magnitude>1 then toCenter.Unit else V(0,0,1)
		local side=V(-face.Z,0,face.X)
		local signPos=freeSpot(host,{center+face*9,center+face*9+side*6,center+face*9-side*6,center-face*9,center+side*9,center-side*9},5)
		signAt(m,CFrame.lookAt(signPos,signPos+face),g.name,"HUNTER "..creature.level.."   /   "..string.upper(method.name).." · "..string.upper(creature.name),C(Data.Skills.Hunter.color),9,{kind="shop",icon="Feather"})
		anchor(m,"Waypoint_Hunting_"..creature.id,center+face*6,center)
	end

	-- Skill vendors: the Skymark Exchange beside the Quay Rigging Run and the
	-- Trackers' Lodge by the Hopper Warren.
	local function vendor(isleName,offset,towardOffset,skill,npc,waypoint)
		local host,IC=isle(isleName)
		local m=content(host,Data.SkillVendors[skill].name,skill)
		local pos,toward=IC+offset,IC+towardOffset
		local stall,cf=marketStall(m,pos,toward,Data.SkillVendors[skill].name,nil,nil,nil,C(Data.Skills[skill].color),string.upper(skill).."   /   "..(if skill=="Agility" then "SKYMARKS" else "KITS · OUTFITS"),
			({Agility="Boots",Hunter="Feather"})[skill] or "Charm")
		local counter=stall:FindFirstChild("Counter")
		prompt(counter,"Trade",Data.SkillVendors[skill].name,"skillVendor",skill)
		anchor(m,"NPC_"..npc,at(cf,0,0,2.4))
		anchor(m,"Waypoint_"..waypoint,at(cf,0,0,-5)*CFrame.Angles(0,math.pi,0))
		return m
	end
	do
		local _,_,R=isle("Compass Quay")
		local a=math.rad(SITES.QuayRigging.angle)
		local dir=V(math.cos(a),0,math.sin(a))
		local tangent=V(-dir.Z,0,dir.X)
		local spot=dir*(R-12)+tangent*21 -- §28 QC H1: its shop sign reads beside the course sign, not over it
		vendor("Compass Quay",spot,spot-dir*10,"Agility","Skymaster","SkymarkExchange")
	end
	vendor("Meadow Reach",V(23,0,40),V(23,0,30),"Hunter","Trapper","TrackersLodge")
	return courseCount
end
buildSkillContent()

-------------------------------------------------------------------------------
-- Verdant Garden (Farming Depth team; self-contained section). Every home gains
-- a garden islet (r14) 40 studs south-west of its centre, joined by a short
-- bridge: twelve plot beds in a 4 x 3 grid, a composter, the garden ledger sign
-- and up to five visitor figures. Rules: Data.Garden; the server (Garden block)
-- publishes player attributes and this section re-renders only what changed:
--   GardenPlots (unlocked count), GardenSkin (frame/soil colours),
--   GardenPlot<i> = "" | "<crop>:<stage>:<flags>" (w watered, c compost,
--     t treated, s sick, x dead, r ripe, p<n> pest), GardenVisitors ("npc,npc"),
--   GardenComposter ("locked"|"idle"|"working"|"ready").
-- Crops are mesh slots (contract §10): Shape = the crop's catalog mesh
-- (CropWheat / CropGlowcap / CropBloom / CropBush), Tint = crop colour (blight
-- browns it, death greys it), ShapeScale = Data.Garden.STAGE_SCALE[stage]; the
-- host primitive is sized to the stage so the fallback grows too.
-- Prompts (owner only): plot soil IsleAction "gardenPlot" IsleItem "<i>"
-- (contextual: plant best seed / water / harvest / treat / swat pest / clear);
-- composter, ledger and visitors IsleAction "gardenOpen" and open Workshop ›
-- Garden through IsleStation = "Garden". Anchors: Anchor_Waypoint_VerdantGarden,
-- Anchor_Garden_Composter, Anchor_NPC_GardenVisitor.
-------------------------------------------------------------------------------
do
	local G=Data.Garden
	local GARDEN_OFFSET,GARDEN_R=V(-40,0,40),14 -- §40: out in the north-west district (Data.Island.ProtectedCircles)
	local PLOT_X,PLOT_Z={-6.6,-2.2,2.2,6.6},{.5,-3.9,-8.3}
	local VISITOR_SPOTS={{-10,4.5},{-7.5,7.5},{-4.5,10},{-11.5,1},{-12,-3}}
	local leaf=C("5FBF77")
	local function hex(s,fallback) local ok,c=pcall(C,s) return if ok then c else fallback end
	homeTerrace.garden=function(player,home)
		if not G or not home or home.garden then return end
		local m,center=home.model,home.center
		local gc=center+GARDEN_OFFSET
		-- §27: a garden lawn on the big island (was a bridged islet); same offset.
		local isle=HomeKit.plaza(m,"Verdant Garden",gc,GARDEN_R,C("7FA86A"),Enum.Material.Grass)
		isle:SetAttribute("GardenOwner",player.UserId)
		home.garden=isle
		local dir=(center-gc).Unit
		-- §40: a garden walk from the core to the lawn.
		path(isle,center-dir*20,gc+dir*(GARDEN_R-.5),5)
		local frame=CFrame.lookAt(gc,gc+dir)
		local function F(x,zf,y) return frame*CFrame.new(x,y or 0,-zf) end
		local function L(x,zf,y) return F(x,zf,y).Position end
		local function openLedger(q)
			q:SetAttribute("OwnerUserId",player.UserId)
			q.Triggered:Connect(function(user)
				if user~=player then return end
				user:SetAttribute("IsleStation","Garden")
				user:SetAttribute("IsleStationVisit",(user:GetAttribute("IsleStationVisit") or 0)+1)
			end)
			return q
		end
		-- Ledger sign and composter at the entrance.
		local signPos=L(5.5,8.5)
		local board=signAt(isle,CFrame.lookAt(signPos,signPos+dir),"Verdant Garden","GARDEN   /   PLOTS · VISITORS · SHOP",leaf,7)
		openLedger(prompt(board,"Open ledger","Verdant Garden","gardenOpen","ledger"))
		local bin=group("Composter",isle)
		local barrel=part(bin,"Composter barrel",V(3,3.2,3),F(8.5,5,1.6),timber,WO,true)
		meshSlot(barrel,"Barrel",C("6B4F33"),nil,"Uniform")
		local lid=part(bin,"Composter lid",V(.3,3.2,3.2),F(8.5,5,3.35)*CFrame.Angles(0,0,math.pi/2),shale,SM,false,Enum.PartType.Cylinder)
		local binPrompt=openLedger(prompt(barrel,"Open composter","Composter","gardenOpen","composter"))
		anchor(isle,"Waypoint_VerdantGarden",L(0,10),gc)
		anchor(isle,"Garden_Composter",L(8.5,8),L(8.5,5))
		anchor(isle,"NPC_GardenVisitor",L(-7,6),gc)
		-- Plot beds.
		local plots={}
		local function skin()
			local s=G.SkinById[player:GetAttribute("GardenSkin")] or G.Skins[1]
			return hex(s.frame,timber),hex(s.soil,ink)
		end
		local function parse(code)
			if type(code)~="string" or code=="" then return nil end
			local crop,stage,flags=string.match(code,"^(%w*):(%d):(%w*)$")
			if not stage then return nil end
			return {crop=G.CropById[crop],stage=tonumber(stage),flags=flags,pest=tonumber(string.match(flags,"p(%d)"))}
		end
		local function has(flags,f) return string.find(flags,f,1,true)~=nil end
		local function refreshPlot(i)
			local b=plots[i]
			if not b or not isle.Parent then return end
			local unlocked=i<=(tonumber(player:GetAttribute("GardenPlots")) or G.BASE_PLOTS)
			local frameColor,soilColor=skin()
			local s=if unlocked then parse(player:GetAttribute("GardenPlot"..i)) else nil
			local flags=if s then s.flags else ""
			local crop=s and s.crop
			local ripe,sick,dead=has(flags,"r"),has(flags,"s"),has(flags,"x")
			b.frame.Color=if unlocked then frameColor else shale
			b.soil.Color=if has(flags,"w") then darken(soilColor,.35) else soilColor
			b.soil.Material=if has(flags,"c") then Enum.Material.Mud else GR
			b.soil.Transparency=if unlocked then 0 else .55
			-- §42 (owner decision): a ripe, healthy plot is harvested by striking it
			-- with the hoe (StrikeKind "garden"), never with the prompt.
			local strike=unlocked and ripe and not dead and not sick and not (s and s.pest)
			b.prompt.Enabled=unlocked and not strike
			if strike then
				local cropName=Data.Items[crop.id] and Data.Items[crop.id].name or crop.id
				Node.special(b.soil,"Herb","garden","Plot "..i.." · "..cropName,player.UserId)
				b.soil:SetAttribute("GardenHarvest",i)
			else Node.ungather(b.soil) end
			b.prompt.ActionText=if not unlocked then "Locked" elseif s and s.pest then "Swat pest" elseif dead then "Clear"
				elseif sick then "Treat" elseif ripe then "Ripe" elseif crop then "Water" else "Plant"
			b.prompt.ObjectText="Plot "..i..(if crop then " · "..(Data.Items[crop.id] and Data.Items[crop.id].name or crop.id).." · "..(G.STAGE_NAMES[s.stage] or "") else "")
			-- Crop mesh slot: rebuilt when the crop or stage changes, re-tinted in place.
			local key=if crop and s.stage>0 then crop.id..":"..s.stage else nil
			if b.key~=key then
				if b.crop then b.crop:Destroy() b.crop=nil end
				b.key=key
				if key then
					local scale=G.STAGE_SCALE[s.stage] or 1
					local h=2.6*scale
					local w=2.8*math.max(scale,.5)
					b.crop=part(b.model,"Crop",V(w,h,w),F(b.x,b.z,.46+h/2),hex(crop.tint,turf),LEAF,false)
					meshSlot(b.crop,crop.shape,hex(crop.tint,turf),nil,"Uniform")
					b.crop:SetAttribute("ShapeScale",scale)
					b.crop:SetAttribute("GardenStage",s.stage)
				end
			end
			if b.crop then
				local tint=if dead then C("6E6A62") elseif sick then C("8A6B3A") else hex(crop.tint,turf)
				b.crop.Color=tint
				b.crop:SetAttribute("Tint",tint)
				b.crop:SetAttribute("GardenStatus",if dead then "dead" elseif sick then "sick" elseif ripe then "ripe" else "growing")
			end
			local pest=s and s.pest and G.Pests[s.pest]
			local pestId=if pest then pest.id else nil
			if b.pestId~=pestId then
				if b.pest then b.pest:Destroy() b.pest=nil end
				b.pestId=pestId
				if pest then
					b.pest=ball(b.model,"Pest",L(b.x+1.1,b.z+1.1,1),.7,hex(pest.color,rose),SM)
					b.pest:SetAttribute("PestId",pest.id)
				end
			end
			local glint=ripe and not dead and b.crop~=nil
			if glint and not b.glint then
				b.glint=gem(b.model,"Ripe glint",L(b.x,b.z,3.5),V(.45,.7,.45),C("FFE9A6"),0)
			elseif not glint and b.glint then
				b.glint:Destroy() b.glint=nil
			end
		end
		for i=1,G.MAX_PLOTS do
			local row,col=(i-1)//4+1,(i-1)%4+1
			local x,z=PLOT_X[col],PLOT_Z[row]
			local model=group("Plot"..i,isle)
			model:SetAttribute("GardenPlot",i)
			local frameColor,soilColor=skin()
			local bed=part(model,"Plot frame",V(4,.36,4),F(x,z,.18),frameColor,WO,false)
			local soil=part(model,"Plot soil",V(3.4,.12,3.4),F(x,z,.4),soilColor,GR,false)
			local q=prompt(soil,"Plant","Plot "..i,"gardenPlot",tostring(i),player.UserId)
			plots[i]={model=model,frame=bed,soil=soil,prompt=q,x=x,z=z}
			table.insert(home.decorationConnections,player:GetAttributeChangedSignal("GardenPlot"..i):Connect(function() refreshPlot(i) end))
		end
		local function refreshAll() for i=1,G.MAX_PLOTS do refreshPlot(i) end end
		for _,key in ipairs({"GardenPlots","GardenSkin"}) do
			table.insert(home.decorationConnections,player:GetAttributeChangedSignal(key):Connect(refreshAll))
		end
		refreshAll()
		-- Composter lid shows its state.
		local function refreshComposter()
			local state=player:GetAttribute("GardenComposter")
			lid.Color=if state=="ready" then C("F7B2D9") elseif state=="working" then leaf elseif state=="locked" then ink else shale
			binPrompt.ActionText=if state=="locked" then "Composter (garden level "..G.COMPOSTER_LEVEL..")" elseif state=="ready" then "Collect compost" else "Open composter"
		end
		table.insert(home.decorationConnections,player:GetAttributeChangedSignal("GardenComposter"):Connect(refreshComposter))
		refreshComposter()
		-- Visitors waiting at the entrance (one figure per queued visitor).
		local crowd={}
		local function refreshVisitors()
			if not isle.Parent then return end
			local want={}
			local value=player:GetAttribute("GardenVisitors")
			if type(value)=="string" then
				for id in string.gmatch(value,"[^,]+") do
					if G.VisitorById[id] and #want<#VISITOR_SPOTS then table.insert(want,id) end
				end
			end
			for slot=1,#VISITOR_SPOTS do
				local id=want[slot]
				local v=crowd[slot]
				if v and v.id~=id then v.model:Destroy() crowd[slot]=nil v=nil end
				if id and not v then
					local def=G.VisitorById[id]
					local spot=VISITOR_SPOTS[slot]
					local fig=group("Visitor_"..id,isle)
					fig:SetAttribute("GardenVisitor",id)
					local coat=part(fig,"Visitor coat",V(1.4,2.4,1),F(spot[1],spot[2],1.2),hex(def.color,teal),Enum.Material.Fabric,true)
					ball(fig,"Visitor head",L(spot[1],spot[2],2.95),1.1,C("F2D3B1"),SM)
					openLedger(prompt(coat,"Talk",def.name,"gardenOpen","visitor"))
					crowd[slot]={id=id,model=fig}
				end
			end
		end
		table.insert(home.decorationConnections,player:GetAttributeChangedSignal("GardenVisitors"):Connect(refreshVisitors))
		refreshVisitors()
	end
	for player,home in pairs(homes) do homeTerrace.garden(player,home) end
end
-- End Verdant Garden section.

-------------------------------------------------------------------------------
-- Prayer & Thieving (Prayer & Thieving team; self-contained section). Altars
-- (Data.Prayer.Altars), market stalls, pickpocket marks and strongboxes
-- (Data.Thieving.Targets) on their region islands; server.server.lua (Prayer &
-- Thieving block) validates every prompt. Each built Model carries attribute
-- IsleContent ("Prayer"|"Thieving") and sits directly inside its island Model.
-- Prompts (interact holds):
--   altarOffer / altarPray  IsleItem altar id, PrayerAltar = id, IsleRegion (gated)
--   thieve                  IsleItem target id, ThievingTarget = id, ThievingKind, IsleRegion
-- Anchors: Waypoint_Altar_<id>, Waypoint_Thieving_<id>, NPC_Thieving_<id> (marks).
-- Spots are searched on rings around each island centre and keep clear of
-- every existing prop; about 8 parts per object, no extra lights.
-------------------------------------------------------------------------------
do
	local PR,TH=Data.Prayer,Data.Thieving
	local ISLE={Hub="Compass Quay",Meadow="Meadow Reach",Quarry="Brassfall Quarry",Windpine="Windpine Grove",Skyreach="Skyreach",
		Tidewater="Tidewater Shoals",Gloomhollow="Gloomhollow Caverns",Tempest="Tempest Spire",ShatteredCrown="The Shattered Crown"}
	-- Per-object overrides (the Noble walks the Guild Terrace; preferred bearings in degrees).
	local SITE={Noble={isle="Guild Terrace",angle=200},QuayChapel={angle=110},SweetbunStall={angle=20},Dockhand={angle=320},
		Farmhand={angle=60},HerbalistStall={angle=120},Watchman={angle=210},GemStall={angle=150},SilkStall={angle=30},MossrootShrine={angle=220},
		Merchant={angle=200},CuriosStall={angle=250},Strongbox={angle=200},Scholar={angle=40},VaultChest={angle=110},ThunderChoirAltar={angle=130},
		CrownReliquary={angle=60},SovereignCoffer={angle=300}}
	local GATED={}
	for _,r in ipairs(Data.Regions) do if next(r.requires) then GATED[r.id]=true end end
	local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
		["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Path=true,Wildflowers=true}
	local taken={}
	local function blocked(host,pos,radius)
		for _,q in ipairs(taken) do if V(pos.X-q.X,0,pos.Z-q.Z).Magnitude<radius+5 then return true end end
		for _,obj in ipairs(host:GetDescendants()) do
			if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
				local cf,sz=obj.CFrame,obj.Size
				local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
				local c=cf.Position
				local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
				local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
				local ey=ext("Y")
				if dx*dx+dz*dz<radius*radius and c.Y+ey>pos.Y+.3 and c.Y-ey<pos.Y+7 then return true end
			end
		end
		return false
	end
	-- First clear ground spot on rings around the island centre, from `angle`.
	local function spot(host,angle,radius)
		local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
		local first
		for _,f in ipairs({.5,.62,.38,.72,.28}) do
			for k=0,23 do
				local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
				local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
				first=first or pos
				if not blocked(host,pos,radius) then table.insert(taken,pos) return pos,true end
			end
		end
		table.insert(taken,first)
		return first,false
	end
	local function content(host,name,kind)
		local m=group(name,host)
		m:SetAttribute("IsleContent",kind)
		return m
	end
	local function hostFor(id,region)
		local name=(SITE[id] and SITE[id].isle) or ISLE[region]
		return name and islandsFolder:FindFirstChild(name)
	end
	local function frame(host,id,radius)
		local pos=spot(host,(SITE[id] and SITE[id].angle) or 0,radius)
		local IC=host:GetAttribute("IslandCenter")
		local toward=V(IC.X,pos.Y,IC.Z)
		if (toward-pos).Magnitude<1 then toward=pos+V(0,0,1) end
		return facing(pos,toward),pos
	end
	local function gate(q,region) if GATED[region] then q:SetAttribute("IsleRegion",region) end end
	local placed=0
	-- Altars: stone plinth, glowing offering slab, two candles, a kneeler and a sign.
	for _,altar in ipairs(PR.Altars) do
		local host=hostFor(altar.id,altar.region)
		if host then
			local cf,pos=frame(host,altar.id,7)
			local m=content(host,altar.name,"Prayer")
			m:SetAttribute("PrayerAltar",altar.id)
			local tint=C(altar.color)
			part(m,"Altar plinth",V(5,2.4,3),at(cf,0,1.2,0),C("8B8574"),ST,true)
			local slab=part(m,"Offering slab",V(5.6,.4,3.6),at(cf,0,2.6,0),lighten(C("8B8574"),.35),ST,false)
			part(m,"Altar glow",V(3.2,.12,1.6),at(cf,0,2.86,0),tint,NE,false)
			for _,s in ipairs({-2.2,2.2}) do part(m,"Altar candle",V(.35,1,.35),at(cf,s,3.3,.9),cream,SM,false) end
			local kneeler=part(m,"Kneeler",V(3,.5,1.2),at(cf,0,.25,-3),darken(tint,.35),Enum.Material.Fabric,false)
			local q=prompt(slab,"Offer remains",altar.name.." (x"..altar.mult.." XP)","altarOffer",altar.id)
			q:SetAttribute("PrayerAltar",altar.id)
			gate(q,altar.region)
			local pray=prompt(kneeler,"Pray",altar.name,"altarPray",altar.id)
			pray:SetAttribute("PrayerAltar",altar.id)
			gate(pray,altar.region)
			signAt(m,at(cf,7.2,0,0),altar.name,"PRAYER   /   OFFERINGS x"..altar.mult,tint,8,{kind="plaque"})
			anchor(m,"Waypoint_Altar_"..altar.id,at(cf,0,0,-6),pos)
			placed+=1
		end
	end
	-- Thieving targets: a guarded market stall, a figure with a purse, a strongbox.
	local function stall(m,cf,tint)
		local counter=part(m,"Counter",V(6.5,2.8,2),at(cf,0,1.4,0),navy,WO,true)
		meshSlot(counter,"MarketStall",tint,true)
		part(m,"Counter top",V(7,.25,2.5),at(cf,0,2.92,0),brass,WO,false)
		for _,x in ipairs({-3.2,3.2}) do part(m,"Awning post",V(.3,5.8,.3),at(cf,x,2.9,-1.6),brass,MT,false) end
		part(m,"Awning",V(7.2,.35,4.4),at(cf,0,5.8,-.4)*CFrame.Angles(.12,0,0),tint,Enum.Material.Fabric,false)
		part(m,"Wares",V(4.6,.6,1.2),at(cf,0,3.35,.2),lighten(tint,.3),SM,false)
		part(m,"Guard coat",V(1.3,2.6,.9),at(cf,4.6,1.3,-1.4),C("3B4A5C"),Enum.Material.Fabric,true)
		ball(m,"Guard head",at(cf,4.6,3.1,-1.4).Position,1.05,C("E8C9A6"),SM)
		return counter
	end
	local function figure(m,cf,tint)
		part(m,"Legs",V(1.1,1.4,.7),at(cf,0,.7,0),darken(tint,.55),Enum.Material.Fabric,false)
		local coat=part(m,"Coat",V(1.5,2.2,1),at(cf,0,2.5,0),tint,Enum.Material.Fabric,true)
		ball(m,"Head",at(cf,0,4.15,0).Position,1.1,C("F2D3B1"),SM)
		part(m,"Hat",V(1.4,.35,1.4),at(cf,0,4.75,0),darken(tint,.3),Enum.Material.Fabric,false)
		part(m,"Purse",V(.5,.6,.3),at(cf,.85,2.1,.55),brass,Enum.Material.Fabric,false)
		return coat
	end
	local function strongbox(m,cf,tint)
		local box=part(m,"Strongbox",V(3.4,2.2,2.4),at(cf,0,1.1,0),C("4A4F5A"),MT,true)
		meshSlot(box,"Crate",tint)
		part(m,"Strongbox lid",V(3.6,.5,2.6),at(cf,0,2.45,0),darken(tint,.25),MT,false)
		for _,x in ipairs({-1.1,1.1}) do part(m,"Iron band",V(.25,2.56,2.7),at(cf,x,1.3,0),brass,MT,false) end
		part(m,"Lock plate",V(.8,.9,.2),at(cf,0,1.5,1.25),tint,NE,false)
		return box
	end
	local BUILD={stall=stall,pocket=figure,safe=strongbox}
	for _,t in ipairs(TH.Targets) do
		local host=hostFor(t.id,t.region)
		if host then
			local cf,pos=frame(host,t.id,if t.kind=="stall" then 6 else 4)
			local m=content(host,t.name,"Thieving")
			m:SetAttribute("ThievingTarget",t.id)
			local kind=TH.Kinds[t.kind]
			local hostPart=BUILD[t.kind](m,cf,C(t.color))
			local q=prompt(hostPart,kind.verb,t.name.." (Thieving "..t.level..")","thieve",t.id)
			q:SetAttribute("ThievingTarget",t.id)
			q:SetAttribute("ThievingKind",t.kind)
			gate(q,t.region)
			anchor(m,"Waypoint_Thieving_"..t.id,at(cf,0,0,if t.kind=="stall" then 4.5 else 3.5),pos)
			if t.kind=="pocket" then anchor(m,"NPC_Thieving_"..t.id,cf) end
			placed+=1
		end
	end
	workspace:SetAttribute("PrayerThievingSites",placed)
end
-- End Prayer & Thieving section.

-------------------------------------------------------------------------------
-- Slayer tasks (Slayer team; self-contained section). Spawn markers for the
-- slayer-only monsters (Data.SlayerTasks.SlayerOnlyOrder: damage needs a Slayer
-- level, enforced by combat.server.lua) on their region islands, each >= 40
-- studs from every warp landing and on open ground, and NPC anchors for the
-- three regional Slayer masters (Data.Townsfolk roles SlayerCorvane,
-- SlayerMaelis, SlayerVesper; Ysolde keeps Anchor_NPC_Slayer on the terrace).
-------------------------------------------------------------------------------
do
	-- Positions are offsets from each island's IslandCenter attribute.
	local function isle(name) return islandsFolder:FindFirstChild(name) end
	local function centre(name) return isle(name):GetAttribute("IslandCenter") end
	for _,m in ipairs({{"HollowcapShrieker","Gloomhollow Caverns",V(-40,0,-10),2,6},{"MirrorscaleBasilisk","Tidewater Shoals",V(-6,0,28),2,6},
		{"ThundercragGargant","Tempest Spire",V(2,0,-52),1,5},{"UmbralDreadmaw","The Shattered Crown",V(0,0,-72),2,6}}) do
		spawnMarker(m[1],centre(m[2])+m[3],m[4],m[5])
	end
	for _,a in ipairs({{"SlayerCorvane","Windpine Grove",V(12,0,50)},{"SlayerMaelis","Gloomhollow Caverns",V(10,0,52)},{"SlayerVesper","Tempest Spire",V(-14,0,40)}}) do
		local c=centre(a[2])
		anchor(isle(a[2]),"NPC_"..a[1],c+a[3],c+V(0,0,a[3].Z+10))
	end
end
-- End Slayer tasks section.

-------------------------------------------------------------------------------
-- Minigames (Minigames team; self-contained section). The Skybreach ferry: a
-- beacon on the Guild Terrace (south-west lawn) to the Skybreach Bastion,
-- whose arena minigames.server.lua builds. The warp is gated like the region
-- beacons: ServerStorage.IsleMinigameAccess:Invoke(player) -> {allowed,
-- message, landing}; a denial sets IsleRegionNotice and bumps
-- IsleRegionNoticeCount (the client toast). Anchor_Waypoint_SkybreachFerry is
-- the bastion's return point. Unlit (terrace light budget) and ~10 parts.
-------------------------------------------------------------------------------
do
	local FERRY=GT+V(-28,0,-42)
	local accent=C("7FE3CC")
	local post=beaconProp(terrace,FERRY,accent,false,"ferry",{face=V(4,0,5)})
	sign(terrace,FERRY+V(-7,0,6),"Skybreach Ferry","SIEGE · HAUL   /   COMBAT 20 OR FISHING 20",accent,-30,9)
	anchor(terrace,"Waypoint_SkybreachFerry",FERRY+V(4,0,5),FERRY)
	local q=prompt(post,"Board the Skybreach ferry","Skybreach Bastion")
	q:SetAttribute("IsleMinigameFerry",true)
	q.Triggered:Connect(function(player)
		local access=ServerStorage:FindFirstChild("IsleMinigameAccess")
		local ok,result=false,nil
		if access then ok,result=pcall(access.Invoke,access,player) end
		if ok and type(result)=="table" and result.allowed and typeof(result.landing)=="Vector3" then
			warp(player,post,result.landing)
		else
			local message=if ok and type(result)=="table" and type(result.message)=="string" then result.message else "The Skybreach ferry is not sailing right now."
			player:SetAttribute("IsleRegionNotice",message)
			player:SetAttribute("IsleRegionNoticeCount",(tonumber(player:GetAttribute("IsleRegionNoticeCount")) or 0)+1)
		end
	end)
end
-- End Minigames section.
-- Commissions & Logs (Mining & Logs team; self-contained section). The
-- Commission Board and Forgeheart anvil stand on Brassfall Quarry; the Aether
-- Museum pavilion (display case + Collection Log lectern) stands on Compass
-- Quay. Prompts use IsleAction "logsBoard" with IsleItem "Commissions" |
-- "Museum" | "Log" (server: Logs block); triggering also sets the player's
-- IsleStation ("Commissions" | "Museum" | "CollectionLog") and bumps
-- IsleStationVisit so the client opens Journal on that page. Models carry
-- LogsContent = true (not IsleContent, which the Prayer & Thieving QA reserves). Anchors: Waypoint_CommissionBoard, Waypoint_Museum.
-- Spots are searched on rings around the island centre and keep clear of every
-- existing prop (same rule as the Prayer & Thieving section). No extra lights.
-------------------------------------------------------------------------------
do
	local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
		["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Path=true,Wildflowers=true}
	local taken={}
	local function blocked(host,pos,radius)
		for _,q in ipairs(taken) do if V(pos.X-q.X,0,pos.Z-q.Z).Magnitude<radius+6 then return true end end
		for _,obj in ipairs(host:GetDescendants()) do
			if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
				local cf,sz=obj.CFrame,obj.Size
				local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
				local c=cf.Position
				local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
				local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
				local ey=ext("Y")
				if dx*dx+dz*dz<radius*radius and c.Y+ey>pos.Y+.3 and c.Y-ey<pos.Y+9 then return true end
			end
		end
		return false
	end
	local function spot(host,angle,radius)
		local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
		local first
		for _,f in ipairs({.55,.45,.65,.35,.72}) do
			for k=0,23 do
				local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
				local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
				first=first or pos
				if not blocked(host,pos,radius) then table.insert(taken,pos) return pos end
			end
		end
		table.insert(taken,first)
		return first
	end
	local function frame(host,angle,radius)
		local pos=spot(host,angle,radius)
		local IC=host:GetAttribute("IslandCenter")
		local toward=V(IC.X,pos.Y,IC.Z)
		if (toward-pos).Magnitude<1 then toward=pos+V(0,0,1) end
		return facing(pos,toward),pos
	end
	local OPEN={Commissions="Commissions",Museum="Museum",Log="CollectionLog"}
	local function board(target,verb,label,item)
		local q=prompt(target,verb,label,"logsBoard",item)
		q.Triggered:Connect(function(player)
			player:SetAttribute("IsleStation",OPEN[item])
			player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
		end)
		return q
	end
	local dust=C("B9A7FF")
	-- Commission Board: a floating §28 sign (its anchor carries the board's
	-- prompt; QC M1: no posts or Signboard ledger), the Forgeheart anvil and
	-- an ore cluster.
	local quarry=islandsFolder:FindFirstChild("Brassfall Quarry")
	if quarry then
		local cf,pos=frame(quarry,200,7)
		local m=group("Commission Board",quarry)
		m:SetAttribute("LogsContent",true)
		local ledger=signAt(m,cf,"Commission Board","QUARRY GUILD   /   DAILY COMMISSIONS",dust,9)
		board(ledger,"Read commissions","Commission Board","Commissions")
		local anvil=part(m,"Forgeheart anvil",V(2.6,1.8,1.4),at(cf,5,.9,-1.5),C("4A4F5A"),MT,true)
		meshSlot(anvil,"Anvil",dust)
		part(m,"Forgeheart ember",V(1,.25,.6),at(cf,5,1.93,-1.5),dust,NE,false)
		board(anvil,"Forgeheart","Glimmerdust perks","Commissions")
		local cluster=hidden(m,"Glimmer cluster",at(cf,-5,1.2,-1.2).Position)
		meshSlot(cluster,"OreCluster",dust)
		anchor(m,"Waypoint_CommissionBoard",at(cf,0,0,-4),pos)
	end
	-- Aether Museum: a columned dais with a central statue, a display case and the log lectern.
	local hub=islandsFolder:FindFirstChild("Compass Quay")
	if hub then
		local cf,pos=frame(hub,150,11)
		local m=group("Aether Museum",hub)
		m:SetAttribute("LogsContent",true)
		part(m,"Museum dais",V(16,.57,12),at(cf,0,.285,0),C("C9CFD6"),ST,true)
		for _,x in ipairs({-7,7}) do
			for _,z in ipairs({-5,5}) do
				local col=part(m,"Museum column",V(1.2,8,1.2),at(cf,x,4.57,z),cream,ST,true)
				meshSlot(col,"Column")
			end
		end
		part(m,"Museum lintel",V(16.4,.9,12.4),at(cf,0,9.02,0),C("C9CFD6"),ST,false)
		local statue=hidden(m,"Curator's statue",at(cf,0,3.07,2).Position)
		meshSlot(statue,"Statue",brass)
		local case=part(m,"Display case",V(3.4,2.4,2.2),at(cf,-3.6,1.77,-2),C("4A4F5A"),MT,true)
		meshSlot(case,"VaultChest",C("C77DFF"))
		part(m,"Display glass",V(3.2,.18,2),at(cf,-3.6,3.06,-2),C("CFEFFF"),GL,false).Transparency=.4
		board(case,"Browse museum","Aether Museum","Museum")
		local lectern=part(m,"Log lectern",V(1.6,2.2,1.2),at(cf,3.6,1.67,-2),timber,WO,true)
		meshSlot(lectern,"Workbench",brass)
		board(lectern,"Read the log","Collection Log","Log")
		signAt(m,at(cf,0,0,-8.5),"Aether Museum","COMPASS QUAY   /   MUSEUM · COLLECTION LOG",C("C77DFF"),11)
		anchor(m,"Waypoint_Museum",at(cf,0,0,-10),pos)
	end
end
-- End Commissions & Logs section.

-------------------------------------------------------------------------------
-- Crafting (Crafting team; self-contained section). Artificers' Row on the
-- Guild Terrace: the Jeweller's Bench, the Tanning Rack and the Glass Furnace.
-- Prompts use IsleAction "craftStation", IsleItem Jeweller | Tannery |
-- Glassworks (server: Crafting block records the visit, sets IsleStation and
-- bumps IsleStationVisit so the client opens Workshop › Crafting). Models carry
-- CraftingContent = true; anchors Waypoint_Jeweller / _Tannery / _Glassworks.
-- Built from mesh slots that already exist (Workbench, OreCluster, Barrel,
-- Forge) plus a §28 shop sign: 18 station parts, a 1-part floating sign (§28 v2) and 3 invisible waypoint
-- anchors (22 parts), no extra lights (terrace budget).
-------------------------------------------------------------------------------
do
	local host=islandsFolder:FindFirstChild("Guild Terrace")
	local CR=Data.Crafting
	if host and CR then
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Path=true,Wildflowers=true}
		local taken={}
		local function blocked(pos,radius)
			for _,q in ipairs(taken) do if V(pos.X-q.X,0,pos.Z-q.Z).Magnitude<radius+7 then return true end end
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>pos.Y+.3 and c.Y-ey<pos.Y+9 then return true end
				end
			end
			return false
		end
		local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
		local function spot(angle,radius)
			local first
			for _,f in ipairs({.6,.5,.7,.42}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*8)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					first=first or pos
					if not blocked(pos,radius) then table.insert(taken,pos) return pos end
				end
			end
			table.insert(taken,first)
			return first
		end
		local function frame(angle,radius)
			local pos=spot(angle,radius)
			return facing(pos,V(IC.X,pos.Y,IC.Z)),pos
		end
		local function stationPromptAt(target,id)
			local st=CR.Stations[id]
			return prompt(target,st.verb,st.name.." · Crafting","craftStation",id)
		end
		local gemTint,hideTint,glassTint=C("E86FB8"),C("9C6B46"),C("5EC8D8")
		-- Jeweller's Bench: a bench (Workbench mesh), a gem tray, a loupe lamp and a gem cluster.
		do
			local cf,pos=frame(112,6)
			local m=group("Jeweller's Bench",host)
			m:SetAttribute("CraftingContent",true)
			local top=part(m,"Jeweller's bench top",V(5,.4,2.6),at(cf,0,2.6,0),timber,WO,true)
			for _,x in ipairs({-2.1,2.1}) do part(m,"Bench leg",V(.4,2.4,2.2),at(cf,x,1.2,0),darken(timber,.3),WO,false) end
			part(m,"Gem tray",V(1.6,.15,1),at(cf,1.2,2.88,-.4),navy,SM,false)
			part(m,"Loupe lamp",V(.3,1.4,.3),at(cf,-1.8,3.5,.6),brass,MT,false)
			meshSlot(top,"Workbench",gemTint,true)
			local cluster=hidden(m,"Rough gem cluster",at(cf,3.6,.6,.4).Position)
			meshSlot(cluster,"OreCluster",gemTint)
			stationPromptAt(top,"Jeweller")
			anchor(m,"Waypoint_Jeweller",at(cf,0,0,-5),pos)
		end
		-- Tanning Rack: two posts and a bar with a stretched hide, plus an oil barrel.
		do
			local cf,pos=frame(132,6)
			local m=group("Tanning Rack",host)
			m:SetAttribute("CraftingContent",true)
			for _,x in ipairs({-2.4,2.4}) do part(m,"Rack post",V(.45,5,.45),at(cf,x,2.5,0),darken(timber,.25),WO,true) end
			part(m,"Rack bar",V(5.4,.35,.35),at(cf,0,4.85,0),timber,WO,false)
			local hide=part(m,"Stretched hide",V(3.8,3.2,.15),at(cf,0,3,0),hideTint,Enum.Material.Fabric,false)
			local barrel=part(m,"Tanning oil barrel",V(1.6,2,1.6),at(cf,3.8,1,-1),C("6B4A2E"),WO,true)
			meshSlot(barrel,"Barrel",C("C9A25A"))
			stationPromptAt(hide,"Tannery")
			anchor(m,"Waypoint_Tannery",at(cf,0,0,-5),pos)
		end
		-- Glass Furnace: a kiln (Forge mesh, tinted glass-teal) with a cooling shelf.
		do
			local cf,pos=frame(152,7)
			local m=group("Glass Furnace",host)
			m:SetAttribute("CraftingContent",true)
			local kiln=part(m,"Glass kiln",V(5,3.4,3.6),at(cf,0,1.7,0),C("5A5F6B"),Enum.Material.Brick,true)
			part(m,"Kiln mouth",V(2,1,.2),at(cf,0,1.6,-1.85),C("FFB066"),SM,false)
			part(m,"Kiln flue",V(1.2,3.6,1.2),at(cf,0,5.2,.6),darken(C("5A5F6B"),.2),ST,false)
			meshSlot(kiln,"Forge",glassTint,true)
			part(m,"Cooling shelf",V(3,.3,1.1),at(cf,4,2.2,0),timber,WO,true)
			for i=-1,1 do part(m,"Cooling glass",V(.45,.8,.45),at(cf,4+i*.9,2.8,0),lighten(glassTint,.3),GL,false) end
			stationPromptAt(kiln,"Glassworks")
			anchor(m,"Waypoint_Glassworks",at(cf,0,0,-5.5),pos)
		end
		local cf=frame(132,4)
		signAt(host,cf*CFrame.Angles(0,math.pi,0),"Artificers' Row","CRAFTING   /   GEMS · LEATHER · GLASS",gemTint,11)
	end
end
-- End Crafting section.

-------------------------------------------------------------------------------
-- Settlements (World Art pass 2, docs/DEPTH-CONTRACT.md §40). Every static
-- island gets a street-front settlement from the building kit: houses line
-- its paths on both sides, fronts (doors) to the path, a setback apron
-- (SETBACK studs) between the facade and the path edge and at least ALLEY
-- studs between neighbours, so every path, prompt and anchor stays reachable.
-- Lots are tested against a clearance index (one per island, the §30 grid):
-- blockers are every visible or colliding part except the meadow, every
-- Path / Ramp, prompt hosts (+PROMPT_CLEAR), sculptures, every Anchor_*
-- (+ANCHOR_CLEAR: NPCs, waypoints and the spawn stay outside and clear),
-- monster spawn markers (+8), Aether Motes and the festival board site.
-- A lot is a building's whole fit box (roof, awning, porch) plus the apron,
-- inside the island rim (RIM studs) on its main meadow. Compass Quay is
-- settled here, after every fixed-coordinate section (its Compass Spire site
-- reserved); the other islands after World Art & Regions and the Skyward Vents
-- (part 2, below). Later sections search their spots around the houses.
-- Walk-in halls first (a
-- tavern or shop per settlement, furnished), then
-- facades in the island's style. Every host is a mesh slot: one part a house.
-------------------------------------------------------------------------------
-- Buildings.settle(only): settle the islands named in `only` (a set). Called
-- twice: Compass Quay right after the Crafting section (its town core is laid
-- out before the World Art props and folk search their spots), every other
-- island after the Skyward Vents (below).
function Buildings.settle(only)
	local B=Buildings
	local started=os.clock()
	local SETBACK,ALLEY,RIM,PROMPT_CLEAR,ANCHOR_CLEAR=2.2,2.6,5,3.5,3.5
	local LANES,LANE_W,LANE_LIFT,SPAWN_CLEAR=2,6,.09,8
	B.SETBACK,B.ALLEY=SETBACK,ALLEY
	local FACADE_COLOR={StoneCottage=C("8C8A84"),LogLodge=C("6B4A33")}
	-- Island styles: house types (tried in a deterministic rotation), roof
	-- tints per type (at most two: the forge's desktop variant cap), quota and
	-- the settlement's walk-in halls.
	local STYLE={
		["Compass Quay"]={core=true,reserve={{V(-53,0,13),13}},types={"TimberTownhouse","TimberHouse","TimberShopfront","TimberTownhouse"},quota=34,lanes=4,
			tints={TimberHouse={"B5523B"},TimberTownhouse={"2F6F8F"},TimberShopfront={"D9A441"}},
			halls={{shell="TavernHall",interior="TavernInterior",title="The Gilded Compass Inn",kicker="COMPASS QUAY   /   INN · HEARTH · ALE",accent="D9A441",tint="7A3E2E"},
				{shell="ShopHall",interior="ShopInterior",title="Quay Outfitters",kicker="COMPASS QUAY   /   GOODS · SUPPLIES",accent="3C9291",tint="9C3F3A",banner=true}}},
		["Guild Terrace"]={types={"TimberTownhouse","StoneCottage"},quota=10,tints={TimberTownhouse={"7A3E2E"},StoneCottage={"56677A"}}},
		["Mosswake Grove"]={types={"ThatchCottage","LogLodge"},quota=10,tints={ThatchCottage={"3C8C7E"},LogLodge={"4E7A48"}},
			halls={{shell="ShopHall",interior="ShopInterior",title="Mosswake Herbalist",kicker="MOSSWAKE GROVE   /   HERBS · TONICS",accent="6BAF5A",tint="4E7A48",banner=true}}},
		["Meadow Reach"]={types={"ThatchCottage","TimberHouse"},quota=8,tints={ThatchCottage={"C15557"},TimberHouse={"C9572F"}},
			halls={{shell="TavernHall",interior="TavernInterior",title="The Sunwheel Tap",kicker="MEADOW REACH   /   ALE · BREAD · REST",accent="E9C46A",tint="9C5B2E"}}},
		["Brassfall Quarry"]={types={"StoneCottage","TimberShopfront"},quota=10,tints={StoneCottage={"6E4A30"},TimberShopfront={"C98D4F"}},
			halls={{shell="ShopHall",interior="ShopInterior",title="Brassfall Assay House",kicker="BRASSFALL CAY   /   ASSAY · TOOLS",accent="C9A24E",tint="6E4A30",banner=true}}},
		["Cinder Shelf"]={types={"StoneCottage"},quota=5,tints={StoneCottage={"3A4048"}}},
		["Warden Reach"]={types={"StoneCottage","TimberHouse"},quota=7,tints={StoneCottage={"56677A"},TimberHouse={"6E4A6A"}}},
		["Skyreach"]={types={"StoneCottage","TimberTownhouse"},quota=8,tints={StoneCottage={"7A90B0"},TimberTownhouse={"5A7FA8"}},
			halls={{shell="ShopHall",interior="ShopInterior",title="Skyreach Outfitters",kicker="SKYREACH   /   ROPES · LANTERNS",accent="9DF3D7",tint="5A7FA8",banner=true}}},
		["Windpine Grove"]={types={"LogLodge"},quota=10,tints={LogLodge={"4E7A48","2F5F4A"}},
			halls={{shell="TavernHall",interior="TavernInterior",title="The Pinewarden Lodge",kicker="WINDPINE GROVE   /   HEARTH · STEW",accent="6BAF5A",tint="3F5A3A"}}},
		["Gloomhollow Caverns"]={types={"StoneCottage"},quota=4,tints={StoneCottage={"5B4A8C"}}},
		["Tidewater Shoals"]={types={"ThatchCottage","TimberTownhouse"},quota=14,tints={ThatchCottage={"2F6F8F"},TimberTownhouse={"3C9291"}},
			halls={{shell="TavernHall",interior="TavernInterior",title="The Lantern & Gull",kicker="TIDEWATER SHOALS   /   CHOWDER · CHARTS",accent="39898E",tint="2F5F7A"}}},
		["Tempest Spire"]={types={"StoneCottage"},quota=6,tints={StoneCottage={"4A5468"}}},
	}
	B.STYLE=STYLE
	-- Fixed keep-outs: monster spawn markers, Aether Motes, the festival board.
	local keepOut={}
	local spawns=workspace:FindFirstChild("MonsterSpawns")
	for _,m in ipairs(spawns and spawns:GetChildren() or {}) do
		if m:IsA("BasePart") then table.insert(keepOut,{m.CFrame.Position,(m:GetAttribute("Radius") or 0)+SPAWN_CLEAR}) end
	end
	local EX=Data.Exploration
	for _,mote in ipairs(EX and EX.Motes or {}) do
		local isle=islandsFolder:FindFirstChild(mote.isle)
		local c=isle and isle:GetAttribute("IslandCenter")
		if c and type(mote.at)=="table" then table.insert(keepOut,{c+V(mote.at[1],mote.at[2],mote.at[3]),4}) end
	end
	local gate=world:FindFirstChild("ExpeditionGate",true)
	if gate then table.insert(keepOut,{gate.CFrame.Position+V(20,0,8),12}) end
	-- Reserved sites (the Compass Spire landmark, its survey stone and the Town
	-- Crier beside the west avenue, which World Art & Regions places later).
	for _,st in pairs(STYLE) do for _,r in ipairs(st.reserve or {}) do table.insert(keepOut,{r[1],r[2]}) end end
	B.keepOut=keepOut
	local FLOOR={Meadow=true,["Floating foundation"]=true,["Island underside"]=true,["Edge guard"]=true,["Shore ledge"]=true,Wildflowers=true}
	local CELL=16
	local function classify(obj)
		if not obj:IsA("BasePart") then return nil end
		local name=obj.Name
		if string.find(name,"^Anchor_") then return "anchor" end
		if obj:GetAttribute("SculptureScale")~=nil then return "sculpture" end
		if FLOOR[name] then return nil end
		if obj:FindFirstChildOfClass("ProximityPrompt") then return "prompt" end
		if obj.Transparency<1 or obj.CanCollide then return "solid" end
		return nil
	end
	local function box(index,c,hx,hy,hz)
		local e={c.X-hx,c.X+hx,c.Z-hz,c.Z+hz,c.Y-hy,c.Y+hy}
		for ix=math.floor(e[1]/CELL),math.floor(e[2]/CELL) do
			for iz=math.floor(e[3]/CELL),math.floor(e[4]/CELL) do
				local key=ix..","..iz
				index[key]=index[key] or {}
				table.insert(index[key],e)
			end
		end
	end
	local function insert(index,obj)
		local kind=classify(obj)
		if not kind then return end
		local c=obj.CFrame.Position
		if kind=="anchor" then box(index,c+V(0,3,0),ANCHOR_CLEAR,3.5,ANCHOR_CLEAR) return end
		if kind=="sculpture" then local r=math.max(1,2*(tonumber(obj:GetAttribute("SculptureScale")) or 1)) box(index,c,r,r,r) return end
		-- A declared mesh box (sign frames, buildings) blocks with its whole box.
		local cf,sz=Buildings.box(obj)
		c=cf.Position
		local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
		local pad=if kind=="prompt" then PROMPT_CLEAR else 0
		box(index,c,ext("X")+pad,ext("Y")+(if kind=="prompt" then 2 else 0),ext("Z")+pad)
	end
	-- Oriented lot (centre c, unit axes r / l, half sizes hx / hz, ground y,
	-- height h) against the index: separating axes r and l (the index boxes
	-- are axis-aligned, so X and Z are covered by the bounding test).
	local function blocked(index,c,r,l,hx,hz,y,h)
		for _,k in ipairs(keepOut) do
			local d=V(k[1].X-c.X,0,k[1].Z-c.Z)
			if math.abs(d:Dot(r))<hx+k[2] and math.abs(d:Dot(l))<hz+k[2] then return true end
		end
		local ex=math.abs(r.X)*hx+math.abs(l.X)*hz
		local ez=math.abs(r.Z)*hx+math.abs(l.Z)*hz
		local seen={}
		for ix=math.floor((c.X-ex)/CELL),math.floor((c.X+ex)/CELL) do
			for iz=math.floor((c.Z-ez)/CELL),math.floor((c.Z+ez)/CELL) do
				for _,e in ipairs(index[ix..","..iz] or {}) do
					if not seen[e] then
						seen[e]=true
						if e[6]>y-.4 and e[5]<y+h and e[1]<c.X+ex and e[2]>c.X-ex and e[3]<c.Z+ez and e[4]>c.Z-ez then
							local ec=V((e[1]+e[2])/2-c.X,0,(e[3]+e[4])/2-c.Z)
							local eh=V((e[2]-e[1])/2,0,(e[4]-e[3])/2)
							local function sep(axis,half) return math.abs(ec:Dot(axis))>=half+math.abs(axis.X)*eh.X+math.abs(axis.Z)*eh.Z end
							if not sep(r,hx) and not sep(l,hz) then return true end
						end
					end
				end
			end
		end
		return false
	end
	-- The lot of a building at ground frame cf: its fit box widened by half an
	-- alley each side (plus extraX for a banner), deepened by the apron.
	local function lotFor(name,cf,extraX)
		local _,size,lo,hi=B.fitOf(BUILDING_KIT[name])
		local x0,x1=lo.X-ALLEY/2-(extraX or 0),hi.X+ALLEY/2
		local z0,z1=lo.Z-SETBACK,hi.Z+ALLEY/2
		local c=cf*V((x0+x1)/2,0,(z0+z1)/2)
		local r,l=cf.RightVector,-cf.LookVector
		return c,V(r.X,0,r.Z).Unit,V(l.X,0,l.Z).Unit,(x1-x0)/2,(z1-z0)/2,size.Y
	end
	B.lotFor=lotFor
	-- A building on `side` of a path strip, centred `t` studs along it.
	local function fits(isle,index,name,path,side,t,extraX)
		local _,_,lo=B.fitOf(BUILDING_KIT[name])
		local pcf=path.CFrame
		local along,across=pcf.LookVector,pcf.RightVector
		local IC,R=isle:GetAttribute("IslandCenter"),isle:GetAttribute("IslandRadius")
		if math.abs(pcf.Position.Y-IC.Y)>.3 then return nil end
		local base=pcf.Position+along*(t-path.Size.Z/2)
		local origin=base+across*side*(path.Size.X/2+SETBACK-lo.Z)
		origin=V(origin.X,IC.Y,origin.Z)
		local cf=CFrame.lookAt(origin,origin-across*side)
		local c,r,l,hx,hz,h=lotFor(name,cf,extraX)
		for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
			local corner=c+r*hx*sx+l*hz*sz
			if V(corner.X-IC.X,0,corner.Z-IC.Z).Magnitude>R-RIM then return nil end
		end end
		if blocked(index,c,r,l,hx,hz,IC.Y,h) then return nil end
		return cf,{c,r,l,hx,hz,h}
	end
	local function claim(index,lot,y)
		local c,r,l,hx,hz,h=table.unpack(lot)
		box(index,V(c.X,y+h/2,c.Z),math.abs(r.X)*hx+math.abs(l.X)*hz,h/2,math.abs(r.Z)*hx+math.abs(l.Z)*hz)
	end
	-- Room for one more interior light here (verify-world: <= 6 lights within
	-- 30 studs of any light, <= 26 per island).
	local function lightRoom(isle,pos)
		local near,total=0,0
		for _,l in ipairs(isle:GetDescendants()) do
			if l:IsA("Light") then
				total+=1
				local host=l.Parent
				local p=if host:IsA("Attachment") and host.Parent:IsA("BasePart") then (host.Parent.CFrame*host.CFrame).Position elseif host:IsA("BasePart") then host.CFrame.Position else nil
				if p and (p-pos).Magnitude<=34 then near+=1 end
			end
		end
		return near<=4 and total<=23
	end
	local placed={}
	B.settled=placed
	local order={}
	for name in pairs(STYLE) do table.insert(order,name) end
	table.sort(order)
	for isleIndex,isleName in ipairs(order) do
		if only[isleName] then
		local isle=islandsFolder:FindFirstChild(isleName)
		local style=STYLE[isleName]
		if isle then
			local index={}
			for _,obj in ipairs(isle:GetDescendants()) do insert(index,obj) end
			local IC=isle:GetAttribute("IslandCenter")
			local paths={}
			for _,obj in ipairs(isle:GetDescendants()) do
				if obj:IsA("BasePart") and obj.Name=="Path" and obj.Size.Z>=14 then table.insert(paths,obj) end
			end
			-- Longest streets first, so the main avenues fill before side lanes.
			table.sort(paths,function(a,b)
				if math.abs(a.Size.Z-b.Size.Z)>.01 then return a.Size.Z>b.Size.Z end
				local pa,pb=a.CFrame.Position,b.CFrame.Position
				return if pa.X~=pb.X then pa.X<pb.X else pa.Z<pb.Z
			end)
			-- Walk-in halls: the lot nearest the island centre that fits.
			for _,hall in ipairs(style.halls or {}) do
				local best
				for _,p in ipairs(paths) do
					for _,side in ipairs({1,-1}) do
						for t=6,p.Size.Z-6,2 do
							local cf,lot=fits(isle,index,hall.shell,p,side,t,4)
							if cf then
								-- The town core for the hub; elsewhere the village edge (about half
								-- the radius out: .62), so the island centre keeps room for its content.
								local d=V(lot[1].X-IC.X,0,lot[1].Z-IC.Z).Magnitude
								if not style.core then d=math.abs(d-.62*isle:GetAttribute("IslandRadius")) end
								if not best or d<best.d-.01 then best={d=d,cf=cf,lot=lot} end
							end
						end
					end
				end
				-- No street frontage: the first open-meadow lot on rings around the
				-- centre, its door turned to the centre (the village green).
				local IR=isle:GetAttribute("IslandRadius")
				for _,f in ipairs(if style.core then {.25,.35,.45,.15,.55,.65} else {.62,.56,.68,.5,.45,.4}) do
					if best then break end
					for k=0,71 do
						local a=math.rad(k*5+isleIndex*11)
						local pos=IC+V(math.cos(a),0,math.sin(a))*IR*f
						local cf=CFrame.lookAt(pos,V(IC.X,pos.Y,IC.Z))
						local c,r,l,hx,hz,h=lotFor(hall.shell,cf,4)
						local inRim=true
						for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
							local corner=c+r*hx*sx+l*hz*sz
							if V(corner.X-IC.X,0,corner.Z-IC.Z).Magnitude>IR-RIM then inRim=false end
						end end
						if inRim and not blocked(index,c,r,l,hx,hz,IC.Y,h) then best={cf=cf,lot={c,r,l,hx,hz,h}} break end
					end
				end
				if best then
					local def=BUILDING_KIT[hall.shell]
					local m,floor=B.place(isle,hall.shell,best.cf,{title=hall.title,tint=C(hall.tint)})
					B.furnish(m,hall.interior,best.cf)
					-- §40 QC L5: the walk-in shops (hall.banner) carry their name on a
					-- shared Signs.build sign (Signs v2: a floating camera-facing
					-- plaque; one invisible anchor part) on the lot's reserved -X side
					-- (lotFor extraX), beside the front corner. The taverns (no
					-- banner) keep their name in STYLE / the model.
					if hall.banner then
						local at=best.cf*CFrame.new(-(def.w/2+Signs.WALL_GAP),0,-def.d/2+1) -- QC M4: clear of the side wall
						signAt(m,at,hall.title,hall.kicker,C(hall.accent),4,{kind="banner"})
					end
					if lightRoom(isle,floor.CFrame.Position) then B.interiorLight(floor,def) end
					m:SetAttribute("Settlement",isleName)
					claim(index,best.lot,IC.Y)
					table.insert(placed,{model=m,host=floor,isle=isleName,name=hall.shell,lot=best.lot,hall=true})
				end
			end
			-- Facades along a street, both sides, up to the quota (dry: count only).
			local count,slotIndex=0,isleIndex
			local function fillStreet(p,dry)
				local n=0
				for _,side in ipairs({-1,1}) do
					local t=4
					while t<p.Size.Z-4 and count+n<style.quota do
						local done=false
						for k=0,#style.types-1 do
							local name=style.types[(slotIndex+n+k)%#style.types+1]
							local _,size=B.fitOf(BUILDING_KIT[name])
							local cf,lot=fits(isle,index,name,p,side,t+size.X/2)
							if cf then
								if not dry then
									local tints=style.tints[name] or {}
									local tint=tints[slotIndex%math.max(1,#tints)+1]
									local m,host=B.place(isle,name,cf,{tint=tint and C(tint),color=FACADE_COLOR[name]})
									m:SetAttribute("Settlement",isleName)
									claim(index,lot,IC.Y)
									table.insert(placed,{model=m,host=host,isle=isleName,name=name,lot=lot})
									count+=1
									slotIndex+=1
								else
									n+=1
								end
								t+=size.X+(if dry then ALLEY else math.floor(hash(slotIndex,isleIndex)*3))
								done=true
								break
							end
						end
						if not done then t+=1 end
					end
				end
				return n
			end
			for _,p in ipairs(paths) do fillStreet(p) end
			-- Village lanes: where the island's own paths leave the quota short,
			-- lay a cobbled lane (one Path strip) through open meadow and line it.
			-- Candidates: chords at several radii and bearings; the clear lane
			-- whose two sides take the most houses wins (ties: nearer the centre).
			local R=isle:GetAttribute("IslandRadius")
			for _=1,style.lanes or LANES do
				if count>=style.quota then break end
				local best
				for _,f in ipairs({.12,.24,.36,.48,.6}) do
					-- Lanes run on the compass axes (a street grid; sign and path
					-- footings are checked on their axis-aligned boxes).
					for k=0,11 do
						local a=math.rad((k%4)*90)
						local lateral=({0,-.25,.25})[k//4+1]*R
						local dir=V(math.cos(a),0,math.sin(a))
						for _,radial in ipairs({false,true}) do
							local along=if radial then dir else V(-dir.Z,0,dir.X)
							for _,L in ipairs({52,40,30,22}) do
								local mid=IC+dir*R*f+V(-dir.Z,0,dir.X)*lateral
								local lo,hi=mid-along*L/2,mid+along*L/2
								local inRim=V(lo.X-IC.X,0,lo.Z-IC.Z).Magnitude<R-RIM-8 and V(hi.X-IC.X,0,hi.Z-IC.Z).Magnitude<R-RIM-8
								if inRim and not blocked(index,mid,V(-along.Z,0,along.X),along,LANE_W/2+1,L/2+1,IC.Y,2) then
									local probe=Instance.new("Part")
									probe.Size,probe.CFrame=V(LANE_W,.16,L),CFrame.lookAt(mid,hi)
									local score=fillStreet(probe,true)
									probe:Destroy()
									local key=score*1000-f*R
									if score>=2 and (not best or key>best.key) then best={key=key,lo=lo,hi=hi} end
									break
								end
							end
						end
					end
				end
				if not best then break end
				local lane=path(isle,best.lo,best.hi,LANE_W,C("B7A98A"),LANE_LIFT)
				lane:SetAttribute("SettlementLane",isleName)
				insert(index,lane)
				fillStreet(lane)
			end
			-- Hamlet fill: the rest of the quota on open meadow, each house
			-- turned to face the nearest street (its door on that side), else
			-- the island centre, with the same lot rules (apron, alleys, rim).
			local streets={}
			for _,obj in ipairs(isle:GetDescendants()) do
				if obj:IsA("BasePart") and obj.Name=="Path" then table.insert(streets,obj) end
			end
			local function facingFor(pos)
				local bestD,toward=math.huge,nil
				for _,p in ipairs(streets) do
					local q=p.CFrame:PointToObjectSpace(pos)
					local along=math.clamp(q.Z,-p.Size.Z/2,p.Size.Z/2)
					local foot=p.CFrame*V(0,0,along)
					local d=V(foot.X-pos.X,0,foot.Z-pos.Z).Magnitude
					if d<bestD and d<36 then bestD,toward=d,V(foot.X,pos.Y,foot.Z) end
				end
				if not toward or bestD<1 then toward=V(IC.X,pos.Y,IC.Z) end
				if V(toward.X-pos.X,0,toward.Z-pos.Z).Magnitude<1 then toward=pos+V(0,0,-1) end
				return toward
			end
			for _,f in ipairs({.3,.38,.46,.54,.62,.22,.7,.14}) do
				for k=0,71 do
					if count>=style.quota then break end
					local a=math.rad(k*5+isleIndex*13+f*90)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					local toward=facingFor(pos)
					for j=0,#style.types-1 do
						local name=style.types[(slotIndex+j)%#style.types+1]
						local cf=CFrame.lookAt(pos,toward)
						local c,r,l,hx,hz,h=lotFor(name,cf)
						local inRim=true
						for _,sx in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
							local corner=c+r*hx*sx+l*hz*sz
							if V(corner.X-IC.X,0,corner.Z-IC.Z).Magnitude>R-RIM then inRim=false end
						end end
						if inRim and not blocked(index,c,r,l,hx,hz,IC.Y,h) then
							local tints=style.tints[name] or {}
							local tint=tints[slotIndex%math.max(1,#tints)+1]
							local m,host=B.place(isle,name,cf,{tint=tint and C(tint),color=FACADE_COLOR[name]})
							m:SetAttribute("Settlement",isleName)
							local lot={c,r,l,hx,hz,h}
							claim(index,lot,IC.Y)
							table.insert(placed,{model=m,host=host,isle=isleName,name=name,lot=lot})
							count+=1
							slotIndex+=1
							break
						end
					end
				end
			end
		end
		end
	end
	B.settleSeconds=(B.settleSeconds or 0)+os.clock()-started
end
Buildings.settle({["Compass Quay"]=true})
-- End Settlements, part 1.

-------------------------------------------------------------------------------
-- World Art & Regions (World Art & Regions team; self-contained section).
-- docs/DEPTH-CONTRACT.md §30. Data: Data.RegionArt.
--   * Identity: every static island Model carries IsleTitle / IsleEpithet /
--     RegionTitle / RegionEpithet / RegionAccent / Ambience / AmbientSound
--     (regions.client.lua shows the entry banner and the local ambience).
--   * Landmarks: one per region. New centrepieces are forged meshes on one
--     collider host each (Compass Spire, Sunwheel Mill + spinning sails, Ember
--     Caldera, Sunken Observatory, Voidglass Spire); existing centrepieces
--     (Aetherheart, Shoal Light, Storm Crown, Broken Crown) are adopted. Each
--     gets a "Survey stone" (prompt IsleAction "landmark", IsleItem <id>,
--     IsleRegion for gated regions) and Anchor_Waypoint_Landmark_<id>.
--     Landmark hosts carry Landmark = <id>.
--   * Regional folk: Anchor_NPC_<Role> for every Data.Townsfolk.RegionFolkOrder role.
--   * Prop kit dressing (fences, hay carts, flowers, canopy trees, banners,
--     lanterns, cargo, glowshrooms, coral) and waterfalls (Beam + mist on the
--     cliff; no parts). Spots are searched clear of every existing part,
--     spawn marker and Aether Mote, so later sections still find room.
-------------------------------------------------------------------------------
-- (A function body, not a do-block: the script's top level is near Luau's 200-register limit.)
;(function()
	local RA=Data.RegionArt
	if RA then
		local sectionStarted=os.clock()
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Island underside"]=true,["Edge guard"]=true,["Shore ledge"]=true,Path=true,Wildflowers=true,
			["Plaza ring"]=true,["Compass court"]=true,["Harbor plaza"]=true,["Harbor seal"]=true,["Pond bank"]=true}
		local taken={}
		-- Fixed things this section must keep clear of: spawn markers and motes.
		local keepOut={}
		local spawns=workspace:FindFirstChild("MonsterSpawns")
		for _,m in ipairs(spawns and spawns:GetChildren() or {}) do
			if m:IsA("BasePart") then table.insert(keepOut,{m.CFrame.Position,(m:GetAttribute("Radius") or 0)+12}) end
		end
		local EX=Data.Exploration
		for _,mote in ipairs(EX and EX.Motes or {}) do
			local isle=islandsFolder:FindFirstChild(mote.isle)
			local c=isle and isle:GetAttribute("IslandCenter")
			if c and type(mote.at)=="table" then table.insert(keepOut,{c+V(mote.at[1],mote.at[2],mote.at[3]),4}) end
		end
		-- Clearance index (one per island, built once): every blocker's world
		-- AABB bucketed on a CELL-stud XZ grid, so a candidate spot only tests
		-- the few boxes around it instead of walking the island's descendants.
		-- Blockers: visible or colliding parts (FLOOR names excepted), prompt
		-- hosts, AetherSculpture hosts (box from SculptureScale) and NPC anchors
		-- (Anchor_NPC_*, NPC_CLEAR studs). Paths ("path" kind) only block solid
		-- props. Parts this section places are added as they go (track).
		local CELL,NPC_CLEAR=16,3
		local indexes={}
		local function classify(obj)
			if not obj:IsA("BasePart") then return nil end
			local name=obj.Name
			if string.find(name,"^Anchor_NPC_") then return "npc" end
			if string.find(name,"^Anchor_") then return nil end
			if obj:GetAttribute("SculptureScale")~=nil then return "sculpture" end
			if name=="Path" then return "path" end
			if FLOOR[name] then return nil end
			if obj:FindFirstChildOfClass("ProximityPrompt") or obj.Transparency<1 or obj.CanCollide then return "solid" end
			return nil
		end
		local function insert(index,obj)
			local kind=classify(obj)
			if not kind then return end
			local c=obj.CFrame.Position
			local hx,hy,hz
			if kind=="npc" then
				hx,hz=NPC_CLEAR,NPC_CLEAR
				hy=3.5
				c=c+V(0,3,0)
			elseif kind=="sculpture" then
				local r=math.max(1,2*(tonumber(obj:GetAttribute("SculptureScale")) or 1))
				hx,hy,hz=r,r,r
			else
				local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
				c=cf.Position
				local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
				hx,hy,hz=ext("X"),ext("Y"),ext("Z")
			end
			local e={c.X-hx,c.X+hx,c.Z-hz,c.Z+hz,c.Y-hy,c.Y+hy,kind}
			for ix=math.floor(e[1]/CELL),math.floor(e[2]/CELL) do
				for iz=math.floor(e[3]/CELL),math.floor(e[4]/CELL) do
					local key=ix..","..iz
					local cell=index[key]
					if not cell then cell={} index[key]=cell end
					table.insert(cell,e)
				end
			end
		end
		local function indexOf(host)
			local index=indexes[host]
			if not index then
				index={}
				indexes[host]=index
				for _,obj in ipairs(host:GetDescendants()) do insert(index,obj) end
			end
			return index
		end
		local function track(host,inst)
			local index=indexes[host]
			if not index then return end -- indexed lazily later, inst included
			insert(index,inst)
			for _,obj in ipairs(inst:GetDescendants()) do insert(index,obj) end
		end
		local function blocked(host,pos,radius,solid)
			for _,q in ipairs(taken) do if V(pos.X-q[1].X,0,pos.Z-q[1].Z).Magnitude<radius+q[2] then return true end end
			for _,k in ipairs(keepOut) do if V(pos.X-k[1].X,0,pos.Z-k[1].Z).Magnitude<radius+k[2] then return true end end
			local index=indexOf(host)
			for ix=math.floor((pos.X-radius)/CELL),math.floor((pos.X+radius)/CELL) do
				for iz=math.floor((pos.Z-radius)/CELL),math.floor((pos.Z+radius)/CELL) do
					for _,e in ipairs(index[ix..","..iz] or {}) do
						if e[7]~="path" or solid then
							local dx=math.max(0,e[1]-pos.X,pos.X-e[2])
							local dz=math.max(0,e[3]-pos.Z,pos.Z-e[4])
							local low=if e[7]=="path" then pos.Y-1 else pos.Y+.3
							if dx*dx+dz*dz<radius*radius and e[6]>low and e[5]<pos.Y+14 then return true end
						end
					end
				end
			end
			return false
		end
		-- First clear ground spot on `host` near `angle` (degrees), searching
		-- outward rings; nil when the island has no room (the caller skips).
		local function spot(host,angle,radius,fractions,solid)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			for _,f in ipairs(fractions or {.5,.4,.6,.3,.68,.2,.75}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local pos=IC+V(math.cos(a),0,math.sin(a))*math.min(R*f,R-radius-6)
					if not blocked(host,pos,radius,solid) then table.insert(taken,{pos,radius}) return pos end
				end
			end
			return nil
		end
		-- A spot near a world point (rings around it), on its island.
		local function near(host,target,radius,from,to,solid)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			for d=from or 6,to or 30,4 do
				for k=0,15 do
					local a=k*math.pi/8+d*.37
					local pos=V(target.X+math.cos(a)*d,IC.Y,target.Z+math.sin(a)*d)
					if V(pos.X-IC.X,0,pos.Z-IC.Z).Magnitude<R-radius-6 and not blocked(host,pos,radius,solid) then table.insert(taken,{pos,radius}) return pos end
				end
			end
			return nil
		end
		local function isle(name) return islandsFolder:FindFirstChild(name) end
		local function art(model) local m=group("Region art",model); m:SetAttribute("RegionArt",true); return m end
		local hex=C

		-- Identity attributes on every static island.
		for _,model in ipairs(islandsFolder:GetChildren()) do
			local region=model:GetAttribute("RegionId")
			local ra=region and RA.Regions[region]
			if ra then
				model:SetAttribute("IsleTitle",model.Name)
				model:SetAttribute("IsleEpithet",RA.Isles[model.Name] or ra.epithet)
				model:SetAttribute("RegionTitle",ra.title)
				model:SetAttribute("RegionEpithet",ra.epithet)
				model:SetAttribute("RegionAccent",hex(ra.palette[2]))
				model:SetAttribute("Ambience",ra.ambience.particles)
				model:SetAttribute("AmbientSound",ra.ambience.sound or "")
			end
		end

		-- Landmarks.
		local function survey(model,l,pos,toward)
			local stone=block(model,"Survey stone",pos+V(0,.6,0),V(2.2,1.2,1.8),lighten(rock,.15),ST,true)
			stone.CFrame=facing(stone.CFrame.Position,toward)
			meshSlot(stone,"Rock")
			local q=prompt(stone,"Survey",l.name,"landmark",l.id)
			q.MaxActivationDistance=10
			local def=Data.RegionById[l.region]
			if def and next(def.requires) then q:SetAttribute("IsleRegion",l.region) end
			anchor(model,"Waypoint_Landmark_"..l.id,pos+(toward-pos).Unit*-3*V(1,0,1),toward)
			track(islandModel(model),stone)
			return stone
		end
		-- Landmark colliders: the mesh host is display-only (CanCollide off) so
		-- nobody walks on an invisible box lid or corner; these invisible parts
		-- follow the silhouette instead. Units are the mesh's own (art/region-
		-- shapes.cjs), scaled by the host's uniform fit (k = host / mesh extent),
		-- y measured from the mesh floor `y0`. cyl {r,y0,y1}; box {sx,sz,y0,y1};
		-- ring {r,thick,y0,y1,n,door} (door: segments facing -Z, the front, stay open).
		local COLLIDE={
			CompassSpire={w=7.8,h=27.8,floor=0,{"box",7,7,0,2},{"box",5.6,5.6,2,17.2},{"cyl",3.2,17.2,20.5},{"cyl",1.8,20.5,24.5}},
			Sunwheel={w=10.4,h=20.4,floor=0,{"cyl",5.1,0,3.5},{"cyl",4.1,3.5,9},{"cyl",3.6,9,15},{"cyl",4.2,15,17.8}},
			EmberCaldera={w=20.8,h=6.6,floor=-.3,{"ring",7.2,3.6,-.3,3.6,12}},
			SunkenObservatory={w=13.8,h=10.8,floor=-1.5,{"ring",6.55,.8,-1.5,3.2,14,true},{"ring",5.4,.6,3.2,6.6,12,true}},
			VoidglassSpire={w=9.6,h=23,floor=-.24,{"cyl",3.8,-.24,1.6},{"cyl",1.4,1.6,18}},
		}
		local function colliders(model,body,id)
			local spec=COLLIDE[id]
			if not spec then return end
			body.CanCollide=false
			local k=math.min(body.Size.X/spec.w,body.Size.Y/spec.h)
			local function local_(x,y,z) return body.CFrame*CFrame.new(x*k,(y-spec.floor)*k-body.Size.Y/2,z*k) end
			local function solidPart(size,cf,shape)
				local c=part(model,"Landmark collider",size,cf,cream,SM,true,shape)
				c.Transparency,c.CastShadow=1,false
				c:SetAttribute("LandmarkCollider",id)
				return c
			end
			for _,c in ipairs(spec) do
				if c[1]=="box" then
					solidPart(V(c[2]*k,(c[5]-c[4])*k,c[3]*k),local_(0,(c[4]+c[5])/2,0))
				elseif c[1]=="cyl" then
					solidPart(V((c[4]-c[3])*k,2*c[2]*k,2*c[2]*k),local_(0,(c[3]+c[4])/2,0)*CFrame.Angles(0,0,math.pi/2),Enum.PartType.Cylinder)
				elseif c[1]=="ring" then
					local r,thick,y0,y1,n,door=c[2],c[3],c[4],c[5],c[6],c[7]
					for i=0,n-1 do
						local a=(i+.5)*2*math.pi/n
						local x,z=math.cos(a)*r,math.sin(a)*r
						-- Front door: the mesh front faces -Z; leave that segment open.
						if not (door and -z/r>math.cos(math.pi/n*1.2)) then
							local seg=2*(r+thick/2)*math.tan(math.pi/n)+.2
							local centre=local_(x,(y0+y1)/2,z)
							local out=(local_(x*2,(y0+y1)/2,z*2).Position-centre.Position)
							solidPart(V(seg*k,(y1-y0)*k,thick*k),CFrame.lookAt(centre.Position,centre.Position+out,body.CFrame.UpVector))
						end
					end
				end
			end
		end
		local LANDMARK_BUILD={
			-- shape host: footprint radius, host size (studs), solid, angle hint
			CompassSpire={radius=6,size=V(7,28,7),angle=150},
			Sunwheel={radius=10,size=V(14.5,28.5,14.5),angle=90},
			EmberCaldera={radius=11,size=V(19.6,6.6,19.6),angle=0},
			SunkenObservatory={radius=9,size=V(13.8,10.8,13.8),angle=200,sink=1.5},
			VoidglassSpire={radius=6,size=V(9.6,23,9.6),angle=300},
		}
		local ADOPT={AetherheartTree="AetherheartTree",ShoalLight="Lighthouse",StormCrown="StormSpire",BrokenCrown="Obelisk"}
		local built={}
		for _,region in ipairs(RA.Order) do
			local ra=RA.Regions[region]
			local l=ra.landmark
			local host=isle(l.isle)
			if host then
				local model=art(host)
				model.Name="Landmark "..l.name
				local spec=LANDMARK_BUILD[l.id]
				local accent=hex(ra.palette[2])
				local centre
				if spec then
					local pos=spot(host,spec.angle,spec.radius,nil,true)
					if pos then
						local body=part(model,l.name,spec.size,CFrame.new(pos+V(0,spec.size.Y/2-(spec.sink or 0),0))*CFrame.Angles(0,math.rad(spec.angle+90),0),lighten(rock,.1),ST,true)
						meshSlot(body,l.shape,accent,false,"Uniform")
						body:SetAttribute("Landmark",l.id)
						colliders(model,body,l.id)
						track(host,model)
						centre=pos
						built[l.id]=body
						if l.id=="Sunwheel" then
							-- Sails: an invisible host the client spins locally (tag RegionSpin).
							local hub=body.CFrame*CFrame.new(0,15.4*1.4-spec.size.Y/2,-6.6)
							local sails=part(model,"Sunwheel sails",V(35,35,2.4),hub,cream,SM,false)
							sails.Transparency,sails.CastShadow,sails.CanQuery=1,false,false
							meshSlot(sails,"WindmillSails",hex("E9DFC7"),false,"Uniform")
							sails:SetAttribute("SpinRate",.35)
							Tags:AddTag(sails,"RegionSpin")
						elseif l.id=="EmberCaldera" then
							local smoke=Instance.new("ParticleEmitter")
							smoke.Name="Caldera smoke"
							smoke.Rate,smoke.LightEmission=3,.1
							smoke.Lifetime,smoke.Speed=NumberRange.new(6,9),NumberRange.new(3,5)
							smoke.SpreadAngle=Vector2.new(12,12)
							smoke.Size=NumberSequence.new(3,9)
							smoke.Color=ColorSequence.new(hex("6B5E57"))
							smoke.Parent=body
							light(body,hex("FF8A3D"),1.2,26)
						elseif l.id=="VoidglassSpire" then
							light(body,hex("B59CFF"),1,24)
						end
					end
				else
					-- Adopt an existing centrepiece on this island (by mesh slot).
					local want=ADOPT[l.id]
					for _,obj in ipairs(host:GetDescendants()) do
						if obj:IsA("BasePart") and want and obj:GetAttribute("Shape")==want then
							obj:SetAttribute("Landmark",l.id)
							centre=V(obj.CFrame.Position.X,host:GetAttribute("IslandCenter").Y,obj.CFrame.Position.Z)
							built[l.id]=obj
							break
						end
					end
					centre=centre or host:GetAttribute("IslandCenter")
				end
				if centre then
					local at=near(host,centre,2.5,if spec then spec.radius+3 else 8,44,true) or near(host,centre,2.5,46,70,true) or spot(host,90,2.5,nil,true)
					if at then survey(model,l,at,centre) end
				end
			end
		end

		-- Regional folk anchors: near their region's landmark when it has room,
		-- else around the island centre.
		local FOLK_ISLE={Hub="Compass Quay",Meadow="Meadow Reach",Quarry="Brassfall Quarry",Skyreach="Skyreach",Windpine="Windpine Grove",
			Gloomhollow="Gloomhollow Caverns",Tidewater="Tidewater Shoals",Tempest="Tempest Spire",ShatteredCrown="The Shattered Crown"}
		local FOLK_ISLE_ROLE={CalderaWatcher="Cinder Shelf",WarpKeeper="Compass Quay"}
		for i,f in ipairs(RA.Folk) do
			local host=isle(FOLK_ISLE_ROLE[f.role] or FOLK_ISLE[f.region])
			if host then
				local l=RA.Regions[f.region].landmark
				local target=built[l.id] and built[l.id].CFrame.Position
				local pos
				if f.role=="WarpKeeper" then pos=near(host,V(56,0,60),NPC_CLEAR,22,60) end
				if not pos and target and host:IsAncestorOf(built[l.id]) then pos=near(host,target,NPC_CLEAR,14,46) end
				pos=pos or spot(host,i*47,NPC_CLEAR,{.35,.45,.25,.55,.6})
				if pos then track(host,anchor(host,"NPC_"..f.role,pos,host:GetAttribute("IslandCenter")+V(0,0,.01))) end
			end
		end

		-- Prop kit dressing per island: {shape, count, size, solid, tint}.
		local DRESS={
			["Meadow Reach"]={{"FenceRun",6,V(.6,1.9,8),true,"8A6240"},{"HayCart",3,V(2.8,2.9,5.2),true},{"FlowerPatch",4,V(3.8,1.3,3.8),false,"E9C46A"},{"BannerPole",2,V(2.2,8.1,1),true,"E9C46A"}},
			["Mosswake Grove"]={{"FlowerPatch",3,V(3.8,1.3,3.8),false,"C9A0DC"},{"FenceRun",3,V(.6,1.9,8),true,"7A5636"}},
			["Compass Quay"]={{"BannerPole",4,V(2.2,8.1,1),true,"DBAD65"},{"CargoStack",3,V(4.2,2.8,3),true},{"TwinLantern",3,V(2.8,5.3,.9),true,"FFE08A"}},
			["Guild Terrace"]={{"BannerPole",3,V(2.2,8.1,1),true,"C15557"}},
			["Brassfall Quarry"]={{"CargoStack",3,V(4.2,2.8,3),true},{"BannerPole",2,V(2.2,8.1,1),true,"FF8A3D"}},
			["Cinder Shelf"]={{"CargoStack",2,V(4.2,2.8,3),true}},
			["Skyreach"]={{"BannerPole",3,V(2.2,8.1,1),true,"39898E"},{"TwinLantern",2,V(2.8,5.3,.9),true,"BFF4FF"}},
			["Windpine Grove"]={{"CanopyTree",5,V(7.6,9.6,7.6),true,"5E9C4E"},{"FlowerPatch",3,V(3.8,1.3,3.8),false,"E8D98E"}},
			["Gloomhollow Caverns"]={{"Glowshroom",6,V(3.6,3.7,3.2),false,"7FD3C4"}},
			["Tidewater Shoals"]={{"CoralFan",5,V(3,3.4,2.4),false,"E76F7B"},{"CargoStack",2,V(4.2,2.8,3),true}},
			["Tempest Spire"]={{"BannerPole",2,V(2.2,8.1,1),true,"BFD7FF"}},
			["The Shattered Crown"]={{"BannerPole",2,V(2.2,8.1,1),true,"F2D27A"}},
		}
		local dressed=0
		for name,list in pairs(DRESS) do
			local host=isle(name)
			if host then
				local model=art(host)
				model.Name="Prop kit"
				for li,entry in ipairs(list) do
					local shape,count,size,solid,tint=entry[1],entry[2],entry[3],entry[4],entry[5]
					for k=1,count do
						local pos=spot(host,(li*97+k*61)%360,math.max(size.X,size.Z)/2+1,{.62,.5,.72,.4,.3},solid)
						if pos then
							local p=part(model,shape,size,CFrame.new(pos+V(0,size.Y/2,0))*CFrame.Angles(0,hash(k,li)*math.pi*2,0),if solid then darken(timber,.2) else C("6C9A58"),WO,solid)
							meshSlot(p,shape,tint and hex(tint),false,"Uniform")
							track(host,p)
							dressed+=1
						end
					end
				end
			end
		end

		-- Waterfalls spilling off the cliffs: a scrolling Beam and a mist puff
		-- (no parts; Beam textures animate on the client by themselves).
		local FALLS={{"Meadow Reach",200},{"Mosswake Grove",160},{"Windpine Grove",250},{"Tidewater Shoals",60},{"Compass Quay",205},{"Compass Quay",320}}
		for _,fall in ipairs(FALLS) do
			local host=isle(fall[1])
			local foundation=host and host:FindFirstChild("Floating foundation")
			if foundation then
				local r=host:GetAttribute("IslandRadius")
				local a=math.rad(fall[2])
				local out=V(math.cos(a),0,math.sin(a))
				-- The lip starts on the cliff's outer face: the foundation's own radius
				-- (it sits just outside the meadow, see island()) plus 0.3. Both
				-- attachments face outward (X axis = out, Y up) and the Beam keeps a
				-- fixed orientation (FaceCamera off) so the sheet hangs flat on the cliff.
				local cliffR=foundation.Size.Y/2
				local function facingOut(p) return foundation.CFrame:ToObjectSpace(CFrame.fromMatrix(p,out,V(0,1,0))) end
				local top=Instance.new("Attachment")
				top.Name="Waterfall lip"
				top.CFrame=facingOut(host:GetAttribute("IslandCenter")+out*(cliffR+.3)-V(0,.1,0))
				top.Parent=foundation
				local foot=Instance.new("Attachment")
				foot.Name="Waterfall foot"
				foot.CFrame=facingOut(host:GetAttribute("IslandCenter")+out*(cliffR+5)-V(0,math.clamp(r*.9,40,90),0))
				foot.Parent=foundation
				local water=Instance.new("Beam")
				water.Name="Waterfall"
				water.Attachment0,water.Attachment1=top,foot
				water.Texture="rbxasset://textures/particles/smoke_main.dds"
				water.TextureMode,water.TextureLength,water.TextureSpeed=Enum.TextureMode.Wrap,6,-1.6
				water.Width0,water.Width1=6,10
				water.FaceCamera,water.Segments,water.LightEmission,water.LightInfluence=false,6,.2,.6
				water.Color=ColorSequence.new(hex("BFEFFF"),hex("6FC3DF"))
				water.Transparency=NumberSequence.new(.15,.7)
				water.Parent=foundation
				local mist=Instance.new("ParticleEmitter")
				mist.Name="Waterfall mist"
				mist.Rate,mist.LightEmission=4,.2
				mist.Lifetime,mist.Speed=NumberRange.new(3,5),NumberRange.new(2,4)
				mist.SpreadAngle=Vector2.new(60,60)
				mist.Size=NumberSequence.new(4,10)
				mist.Transparency=NumberSequence.new(.6,1)
				mist.Color=ColorSequence.new(hex("E6F7FF"))
				mist.Parent=foot
			end
		end
		islandsFolder:SetAttribute("RegionArtProps",dressed)
		islandsFolder:SetAttribute("RegionArtBuildSeconds",os.clock()-sectionStarted) -- placement cost (verify-regions reports it)
	end
end)()
-- End World Art & Regions section.

-------------------------------------------------------------------------------
-- Skyward Vents (MMO Features, docs/DEPTH-CONTRACT.md §31; Data.Vents).
-- (§40: built right after World Art & Regions, before the Settlements, so the
-- houses never take a vent site.)
-- One collider pad per vent (6 static parts, `Caldera` mesh slot + an updraft
-- emitter, tag SkywardVent, attributes VentId / VentLanding). Its prompt
-- (IsleVent = id) asks IsleRegionAccess for the destination region and the
-- IsleTravelGate when present (an erroring gate refuses), applies a per-rider
-- cooldown, sets FastTravelAt, publishes VentFlight = "<id>:<seq>" (the rider's
-- client plays the arc), then lands the rider server-side after
-- Data.Vents.FLIGHT seconds (FastTravelAt again) only if the rider is still this
-- flight's rider, the same living character, and the travel gate still passes
-- (hurt grace, expeditions); else the landing is abandoned and the rider stays
-- where they are. Landings sit beside the paired vent on the far isle, on clear
-- ground and >= 42 studs from every monster spawn marker.
-------------------------------------------------------------------------------
do
	local VD=Data.Vents
	if VD then
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Path=true,Wildflowers=true}
		local markers={}
		local spawns=workspace:FindFirstChild("MonsterSpawns")
		if spawns then for _,m in ipairs(spawns:GetChildren()) do if m:IsA("BasePart") then table.insert(markers,m.CFrame.Position) end end end
		local function blocked(host,pos,radius,clear)
			for _,m in ipairs(markers) do if V(pos.X-m.X,0,pos.Z-m.Z).Magnitude<clear then return true end end
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>pos.Y+.3 and c.Y-ey<pos.Y+9 then return true end
				end
			end
			return false
		end
		local function spot(host,angle,radius,clear)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			for _,f in ipairs({.6,.5,.7,.4,.75,.3}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					if not blocked(host,pos,radius,clear) then return pos end
				end
			end
			return nil
		end
		local vents,byIsle={},{}
		for i,def in ipairs(VD.List) do
			local host=islandsFolder:FindFirstChild(def.isle)
			local target=Data.RegionById[def.to]
			local pos=host and target and (spot(host,20+i*61,9,42) or spot(host,20+i*61,9,26))
			if pos then
				local tint=C(def.color)
				local pad=disk(host,"Skyward vent",pos+V(0,.5,0),4,1,darken(tint,.35),ST,true)
				-- §44: the vent pad dais; beacons.client.lua floats the rings above it,
				-- 6.5 studs over the pad (riders launch clear underneath).
				meshSlot(pad,"SkywardVentPad",tint,nil,"Uniform")
				pad:SetAttribute("TravelBeacon","vent")
				pad:SetAttribute("TravelBeaconHover",pos+V(0,7,0))
				pad:SetAttribute("TravelBeaconRegion",def.to)
				Tags:AddTag(pad,"TravelBeacon")
				pad:SetAttribute("VentId",def.id)
				Tags:AddTag(pad,"SkywardVent")
				local draft=Instance.new("ParticleEmitter")
				draft.Name="Updraft"
				draft.EmissionDirection=Enum.NormalId.Right -- the disk's axis points up
				draft.Rate,draft.LightEmission=14,.6
				draft.Speed,draft.Lifetime=NumberRange.new(14,20),NumberRange.new(.9,1.3)
				draft.Size=NumberSequence.new(1.2,0)
				draft.Transparency=NumberSequence.new(.35,1)
				draft.Color=ColorSequence.new(lighten(tint,.5),tint)
				draft.Parent=pad
				local q=prompt(pad,"Ride the "..def.name,"To "..target.name)
				q:SetAttribute("IsleVent",def.id)
				vents[def.id]={def=def,pad=pad,pos=pos,host=host,prompt=q}
				byIsle[def.isle]=def.id
			end
		end
		-- Landings: beside the vent on the far isle that leads back (open ground,
		-- >= 42 studs from monster markers), else that isle's own clear spot.
		for _,v in pairs(vents) do
			local host=islandsFolder:FindFirstChild(v.def.land)
			local back=byIsle[v.def.land] and vents[byIsle[v.def.land]]
			local land
			if back then
				local IC=host:GetAttribute("IslandCenter")
				local inward=V(IC.X-back.pos.X,0,IC.Z-back.pos.Z)
				inward=if inward.Magnitude>1e-3 then inward.Unit else V(1,0,0)
				land=back.pos+inward*8
				-- Beside a vent that had to stand nearer a spawn: land on the isle's clearest ground instead.
				if blocked(host,land,0,42) then land=spot(host,200,6,42) end
			elseif host then
				land=spot(host,200,6,42)
			end
			if land then
				v.landing=land+V(0,4,0)
				v.pad:SetAttribute("VentLanding",v.landing)
				anchor(host,"Waypoint_Vent_"..v.def.id,land,v.pos)
			end
		end
		local riding,ready,seq={},{},0
		local function notice(player,message)
			player:SetAttribute("IsleRegionNotice",message)
			player:SetAttribute("IsleRegionNoticeCount",(tonumber(player:GetAttribute("IsleRegionNoticeCount")) or 0)+1)
		end
		-- IsleTravelGate: true, or the refusal message. Fails closed when the gate errors.
		local function gatePasses(player)
			local gate=ServerStorage:FindFirstChild("IsleTravelGate")
			if not gate then return true end
			local okGate,verdict=pcall(gate.Invoke,gate,player)
			if okGate and verdict==true then return true end
			return if okGate and type(verdict)=="string" then verdict else "The vent will not lift you right now."
		end
		local function launch(player,v)
			local character=player.Character
			local root=character and character:FindFirstChild("HumanoidRootPart")
			local hum=character and character:FindFirstChildOfClass("Humanoid")
			if not v.landing or not root or not hum or hum.Health<=0 then return end
			if (v.pad.CFrame.Position-root.Position).Magnitude>VD.RANGE+3 then return end
			local now=os.clock()
			if riding[player] then return end
			if (ready[player] or 0)>now then notice(player,v.def.name.." is gathering its breath ("..math.ceil(ready[player]-now).."s).") return end
			local region=Data.RegionById[v.def.to]
			local access=ServerStorage:FindFirstChild("IsleRegionAccess")
			if not access then return end
			local ok,result=pcall(access.Invoke,access,player,v.def.to)
			if not (ok and type(result)=="table" and result.allowed) then
				notice(player,if ok and type(result)=="table" and type(result.message)=="string" then result.message else region.name..": "..requirementText(region))
				return
			end
			local gated=gatePasses(player)
			if gated~=true then notice(player,gated) return end
			seq+=1
			local mine=seq
			riding[player]=mine
			ready[player]=now+VD.COOLDOWN
			player:SetAttribute("FastTravelAt",os.clock()) -- known fast travel (Aether Mote pickup checks)
			flare(v.pad,player)
			player:SetAttribute("VentFlight",v.def.id..":"..mine)
			task.spawn(function()
				task.wait(VD.FLIGHT)
				if riding[player]~=mine then return end
				riding[player]=nil
				local now2=player.Character
				local r=now2 and now2:FindFirstChild("HumanoidRootPart")
				local h=now2 and now2:FindFirstChildOfClass("Humanoid")
				if not (now2==character and r and h and h.Health>0) then return end
				-- Re-check the gate just before landing (hurt mid-flight, pulled into an expedition, gate error).
				local gated2=gatePasses(player)
				if gated2~=true then notice(player,gated2) return end
				player:SetAttribute("FastTravelAt",os.clock())
				now2:PivotTo(CFrame.new(v.landing))
				r.AssemblyLinearVelocity=Vector3.zero
			end)
		end
		for _,v in pairs(vents) do v.prompt.Triggered:Connect(function(player) launch(player,v) end) end
		Players.PlayerRemoving:Connect(function(player) riding[player]=nil; ready[player]=nil end)
	end
end
-- End Skyward Vents.

-- Settlements, part 2 (§40): every island but Compass Quay (settled before
-- World Art & Regions), after the Skyward Vents so no house takes a vent site.
local others={}
for name in pairs(Buildings.STYLE) do if name~="Compass Quay" then others[name]=true end end
Buildings.settle(others)
-- End Settlements section.

-------------------------------------------------------------------------------
-- Exploration & Factions (Exploration & Factions team; self-contained section).
-- Mote Shrines: one Waystone per region (Data.Exploration.ShrineIsle); prompt
-- IsleAction "moteShrine", IsleItem <region>, IsleRegion <region> (the server
-- claims milestone steps and the region bonus); triggering also sets the
-- player's IsleStation "Motes" and bumps IsleStationVisit (Journal › Motes).
-- Faction standards: one Banner per faction on its home island; prompt
-- IsleAction "factionBoard", IsleItem <faction>, IsleRegion <its island's region>,
-- IsleStation "Factions". Both kinds set IsleStation only after the region
-- gate passes (player attribute <Region>Unlocked == true).
-- The 78 Aether Motes themselves are never built here: motes.client.lua draws
-- them locally from Data.Exploration (no server parts). Parts: 9 shrine
-- stones + 3 banner standards (§28: pole + cloth, 6) + 4 waypoint anchors (Waypoint_MoteShrine on Compass
-- Quay, Waypoint_Faction_<id>) = 19. Models carry ExploreContent = true.
-------------------------------------------------------------------------------
do
	local EX,FA=Data.Exploration,Data.Factions
	if EX and FA then
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Wildflowers=true} -- §40: paths (village lanes) block; see below
		local taken={}
		local function blocked(host,pos,radius)
			for _,q in ipairs(taken) do if V(pos.X-q.X,0,pos.Z-q.Z).Magnitude<radius+6 then return true end end
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>(if obj.Name=="Path" then pos.Y-1 else pos.Y+.3) and c.Y-ey<pos.Y+9 then return true end
				end
			end
			return false
		end
		local function spot(host,angle,radius)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			local first
			for _,f in ipairs({.5,.4,.6,.3,.68}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					first=first or pos
					if not blocked(host,pos,radius) then table.insert(taken,pos) return pos end
				end
			end
			table.insert(taken,first)
			return first
		end
		-- The journal page opens only once the region gate passes (the server's
		-- <Region>Unlocked attribute), matching the server's IsleRegion check.
		local function opens(q,page,region)
			q.Triggered:Connect(function(player)
				if region and player:GetAttribute(region.."Unlocked")~=true then return end
				player:SetAttribute("IsleStation",page)
				player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
			end)
		end
		local moteTint=C(EX.MOTE.color)
		for i,region in ipairs(EX.RegionOrder) do
			local host=islandsFolder:FindFirstChild(EX.ShrineIsle[region])
			if host then
				local pos=spot(host,35+i*40,4)
				local m=group("Mote Shrine",host)
				m:SetAttribute("ExploreContent",true)
				m:SetAttribute("MoteShrine",region)
				local stone=block(m,"Mote shrine stone",pos+V(0,2.5,0),V(2.4,5,2.4),lighten(rock,.2),ST,true)
				meshSlot(stone,"Waystone",moteTint)
				local q=prompt(stone,"Commune","Mote Shrine · "..(Data.RegionById[region] and Data.RegionById[region].name or region),"moteShrine",region)
				q:SetAttribute("IsleRegion",region)
				opens(q,"Motes",region)
				if region=="Hub" then anchor(m,"Waypoint_MoteShrine",pos+V(0,0,-5),pos) end
			end
		end
		for i,id in ipairs(FA.Order) do
			local def=FA.Factions[id]
			local host=islandsFolder:FindFirstChild(def.isle)
			if host then
				local pos=spot(host,300+i*25,4)
				local m=group("Faction standard "..def.short,host)
				m:SetAttribute("ExploreContent",true)
				m:SetAttribute("Faction",id)
				-- Banner standard (§28): the faction's cloth carries its name and the prompt.
				local IC=host:GetAttribute("IslandCenter")
				local standard=signAt(m,facing(pos,V(IC.X,pos.Y,IC.Z)),def.name,"FACTION   /   HAIL THE STANDARD",C(def.color),9,{kind="banner"})
				local q=prompt(standard,"Hail",def.name,"factionBoard",id)
				local home=EX.IsleRegion[def.isle]
				q:SetAttribute("IsleRegion",home)
				opens(q,"Factions",home)
				anchor(m,"Waypoint_Faction_"..id,pos+V(0,0,-5),pos)
			end
		end
	end
end
-- End Exploration & Factions section.

-------------------------------------------------------------------------------
-- Lairs (Bossing team; self-contained section). One lair altar per boss
-- (Data.Lairs.Order) on its island: a dais, the altar stone (mesh slot
-- "Obelisk", tinted the boss colour) carrying the prompt IsleAction
-- "lairEnter", IsleItem <boss>, IsleRegion <the island's region> (gate),
-- two torches (mesh slot "Torch") and the anchor Waypoint_Lair_<boss> where
-- lairs.server.lua returns fighters. Parts: 4 x (dais + stone + 2 torches +
-- anchor) = 20, no lights. The arenas themselves are built on demand by
-- lairs.server.lua (off-map, destroyed after each fight). Models carry
-- LairContent = true and LairAltar = <boss>.
-------------------------------------------------------------------------------
do
	local LR=Data.Lairs
	if LR then
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Wildflowers=true} -- §40: paths (village lanes) block; see below
		local function blocked(host,pos,radius)
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>(if obj.Name=="Path" then pos.Y-1 else pos.Y+.3) and c.Y-ey<pos.Y+9 then return true end
				end
			end
			return false
		end
		local function spot(host,angle,radius)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			local first
			for _,f in ipairs({.55,.45,.65,.35,.7}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					first=first or pos
					if not blocked(host,pos,radius) then return pos end
				end
			end
			return first
		end
		for i,id in ipairs(LR.Order) do
			local def=LR.Bosses[id]
			local host=islandsFolder:FindFirstChild(def.isle)
			if host then
				local pos=spot(host,200+i*37,6)
				local tint=C(def.color)
				local m=group("Lair altar "..def.short,host)
				m:SetAttribute("LairContent",true)
				m:SetAttribute("LairAltar",id)
				block(m,"Lair altar dais",pos+V(0,.4,0),V(6,.8,6),darken(C(def.arenaColor),.2),ST,true)
				local stone=block(m,"Lair altar",pos+V(0,2.8,0),V(2.6,4,2.6),lighten(rock,.1),ST,true)
				meshSlot(stone,"Obelisk",tint)
				local q=prompt(stone,"Summon ("..def.fee.." coins)",def.lairName.." · "..def.short.." (Combat "..def.combat..")","lairEnter",id)
				q:SetAttribute("IsleRegion",def.region)
				for side=-1,1,2 do
					local torch=block(m,"Lair torch",pos+V(2.3*side,2.3,-1.6),V(.6,3,.6),timber,WO,false)
					meshSlot(torch,"Torch",tint)
				end
				anchor(m,"Waypoint_Lair_"..id,pos+V(0,0,-5),pos)
			end
		end
	end
end
-- End Lairs section.

-------------------------------------------------------------------------------
-- Raids (Raid team; self-contained section, docs/DEPTH-CONTRACT.md §38). The
-- Undertide portal on Tidewater Shoals (Data.Raids.ISLE): a tiered dais, the
-- portal arch (mesh slot "ObservatoryArch", tinted tide-teal) whose shimmer
-- pane carries the prompt IsleAction "raidPortal", IsleRegion
-- Data.Raids.REGION (gate), two braziers (mesh slot "Torch", one light), two
-- coral fans and the anchor Waypoint_RaidPortal (the return point and the
-- party board's range centre; quest helper / Wayfinder target
-- "anchor:Waypoint_RaidPortal"). Parts: dais 2 + arch 1 + pane 1 + braziers 2
-- + coral 2 + anchor 1 = 9. The vault complexes are built on demand by
-- raids.server.lua (off-map, destroyed after each run). Model attribute
-- RaidContent = true.
-------------------------------------------------------------------------------
do
	local RD=Data.Raids
	local host=RD and islandsFolder:FindFirstChild(RD.ISLE)
	if host then
		local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Wildflowers=true} -- §40: paths (village lanes) block; see below
		local function blocked(pos,radius)
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>(if obj.Name=="Path" then pos.Y-1 else pos.Y+.3) and c.Y-ey<pos.Y+12 then return true end
				end
			end
			return false
		end
		local pos
		if typeof(IC)=="Vector3" and type(R)=="number" then
			for _,f in ipairs({.5,.4,.6,.3,.68}) do
				for k=0,23 do
					local a=math.rad(310+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local p=IC+V(math.cos(a),0,math.sin(a))*R*f
					pos=pos or p
					if not blocked(p,7) then pos=p break end
				end
				if pos and not blocked(pos,7) then break end
			end
		end
		if pos then
			local tide,teal=C("1E5A63"),C("3FB8AF")
			local m=group("Undertide portal",host)
			m:SetAttribute("RaidContent",true)
			local face=CFrame.lookAt(pos,V(IC.X,pos.Y,IC.Z))
			block(m,"Raid portal dais",pos+V(0,.3,0),V(13,.6,13),darken(tide,.15),ST,true)
			block(m,"Raid portal step",pos+V(0,.8,0),V(9,.4,9),lighten(tide,.12),ST,true)
			local arch=part(m,"Raid portal arch",V(9,11,2),face+V(0,6.5,0),lighten(rock,.1),ST,false)
			meshSlot(arch,"ObservatoryArch",teal,nil,"Uniform")
			local pane=part(m,"Raid portal shimmer",V(5.6,8,.4),face+V(0,5.2,0),teal,Enum.Material.Neon,false)
			pane.Transparency=.35
			local q=prompt(pane,"Raid board","The Undertide Vaults · Combat "..RD.COMBAT.." · "..RD.MIN_PARTY.."–"..RD.MAX_PARTY.." raiders","raidPortal",RD.ID)
			q:SetAttribute("IsleRegion",RD.REGION)
			q.HoldDuration=.36
			for side=-1,1,2 do
				local brazier=part(m,"Raid portal brazier",V(1.4,3.4,1.4),face*CFrame.new(side*5.6,2.5,-1.5),timber,WO,false)
				meshSlot(brazier,"Torch",teal)
				if side==-1 then light(brazier,teal,1.1,22) end
				local coral=part(m,"Raid portal coral",V(2.6,3,2.6),face*CFrame.new(side*4.8,2.1,2.5),C("E58FB0"),SM,false)
				meshSlot(coral,"CoralFan",C("E58FB0"),nil,"Uniform")
			end
			anchor(m,"Waypoint_RaidPortal",(face*CFrame.new(0,0,-6)).Position,pos)
		end
	end
end
-- End Raids section.

-------------------------------------------------------------------------------
-- Isle Council Hall (Isle Council team; docs/DEPTH-CONTRACT.md §36). A
-- columned hall on Compass Quay: a raised dais with six columns (Column mesh
-- slots), a pediment, two council banners, the speaker's statue, five
-- councillor seats, the ballot chest (VaultChest slot, prompt IsleAction
-- "councilView") and two lanterns. Triggering the chest sets IsleStation =
-- "Council" and bumps IsleStationVisit (the client opens Journal › Council).
-- The Clerk's World Art anchor (Anchor_NPC_CouncilClerk) moves to the hall's
-- steps, >= 7 studs from every other NPC anchor. Anchor: Waypoint_CouncilHall.
-- The model carries CouncilContent = true. No extra lights.
-- (A function body, not a do-block: the script's top level is near Luau's register limit.)
-------------------------------------------------------------------------------
;(function()
	local hub=islandsFolder:FindFirstChild("Compass Quay")
	local CD=Data.Council
	if not hub or not CD then return end
	local FLOOR={Meadow=true,["Floating foundation"]=true,["Island underside"]=true,["Edge guard"]=true,["Shore ledge"]=true,Wildflowers=true,
		["Plaza ring"]=true,["Compass court"]=true,["Harbor plaza"]=true,["Harbor seal"]=true,["Pond bank"]=true}
	local clerkName="Anchor_NPC_"..CD.CLERK
	local npcAnchors,boxes={},{}
	for _,obj in ipairs(hub:GetDescendants()) do
		if obj:IsA("BasePart") then
			local npc=string.find(obj.Name,"^Anchor_NPC_")~=nil
			if npc and obj.Name~=clerkName then table.insert(npcAnchors,obj) end
			if obj.Name~=clerkName and not FLOOR[obj.Name] and (not string.find(obj.Name,"^Anchor_") or npc)
				and (npc or obj.Transparency<1 or obj.CanCollide or obj:FindFirstChildOfClass("ProximityPrompt")~=nil) then
				local cf,sz=Buildings.box(obj) -- §40 QC L2
				local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
				table.insert(boxes,{c=cf.Position,x=ext("X"),y=ext("Y"),z=ext("Z"),flat=obj.Name=="Path"})
			end
		end
	end
	local function blocked(pos,radius)
		for _,b in ipairs(boxes) do
			local dx=math.max(0,math.abs(pos.X-b.c.X)-b.x)
			local dz=math.max(0,math.abs(pos.Z-b.c.Z)-b.z)
			if dx*dx+dz*dz<radius*radius and (b.flat or (b.c.Y+b.y>pos.Y+.3 and b.c.Y-b.y<pos.Y+12)) then return true end
		end
		return false
	end
	local IC,R=hub:GetAttribute("IslandCenter"),hub:GetAttribute("IslandRadius")
	if not IC or not R then return end
	local pos
	-- The hall (16 x 12 studs plus steps, lanterns and sign) needs an 11-stud clear circle.
	for _,f in ipairs({.75,.8,.85,.7,.65,.9,.6,.55}) do
		for k=0,119 do
			local a=math.rad(255+(if k%2==0 then 1 else -1)*math.ceil(k/2)*3)
			local p=IC+V(math.cos(a),0,math.sin(a))*R*f
			if not blocked(p,11) then pos=p break end
		end
		if pos then break end
	end
	if not pos then return end
	-- cf looks AWAY from the plaza: the hall's open front (and its step) is -Z, toward the centre.
	local away=pos+(pos-V(IC.X,pos.Y,IC.Z))
	local cf=facing(pos,away)
	local gold,plum,stone=C(CD.COLOR),C("6A4C93"),C("D8D2C4")
	local m=group("Council Hall",hub)
	m:SetAttribute("CouncilContent",true)
	-- Dais, carpet and the front step.
	part(m,"Council dais",V(16,.8,12),at(cf,0,.4,.5),stone,ST,true)
	part(m,"Council step",V(12,.4,1.4),at(cf,0,.2,-6.2),lighten(stone,.2),ST,true)
	part(m,"Council carpet",V(3.4,.06,10.4),at(cf,0,.83,0),plum,SM,false)
	-- Columns: four across the front, two at the back corners.
	for _,c in ipairs({{-7,-4.6},{-3.4,-4.6},{3.4,-4.6},{7,-4.6},{-7,5.8},{7,5.8}}) do
		local col=part(m,"Council column",V(1.2,9,1.2),at(cf,c[1],5.3,c[2]),cream,ST,true)
		meshSlot(col,"Column")
	end
	part(m,"Council lintel",V(16.4,1,12.4),at(cf,0,10.3,.5),lighten(stone,.1),ST,false)
	part(m,"Council pediment",V(16.8,.5,12.8),at(cf,0,11.05,.5),gold,MT,false)
	part(m,"Council frieze",V(13,.7,.2),at(cf,0,10.3,-5.75),plum,SM,false)
	part(m,"Council back wall",V(13,8.6,.8),at(cf,0,5.1,6.2),lighten(stone,.05),ST,true)
	-- Banners either side of the speaker's statue.
	for _,x in ipairs({-4.2,4.2}) do
		local b=part(m,"Council banner",V(2.2,5.6,.3),at(cf,x,5.6,5.65),plum,SM,false)
		meshSlot(b,"Banner",gold)
	end
	local statue=hidden(m,"Speaker's statue",at(cf,0,3.6,4.4).Position)
	statue.Size=V(2.2,5.4,2.2)
	statue.CFrame=at(cf,0,3.5,4.4)
	meshSlot(statue,"Statue",gold,nil,"Uniform")
	-- Five councillor seats in an arc (one per slate place), cushions in council gold.
	for i=1,CD.SLATE do
		local a=math.rad(-60+(i-1)*30)
		local seat=part(m,"Councillor seat",V(1.6,1.6,1.5),at(cf,math.sin(a)*5.6,1.6,2.4-math.cos(a)*1.8)*CFrame.Angles(0,-a,0),darken(timber,.2),WO,true)
		part(m,"Seat cushion",V(1.4,.2,1.3),seat.CFrame*CFrame.new(0,.9,0),gold,SM,false)
	end
	-- The ballot chest and its glowing slot.
	local chest=part(m,"Ballot chest",V(3,2.2,2),at(cf,0,1.9,-2),C("4A3B2A"),WO,true)
	meshSlot(chest,"VaultChest",gold)
	part(m,"Ballot slot",V(1.6,.12,.3),at(cf,0,3.06,-2),gold,NE,false)
	local q=prompt(chest,"Read the ballot",CD.NAME,"councilView","Ballot")
	q.Triggered:Connect(function(player)
		player:SetAttribute("IsleStation","Council")
		player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
	end)
	-- Lanterns at the step.
	for _,x in ipairs({-7.6,7.6}) do
		local lamp=part(m,"Council lantern",V(1.1,5.3,.9),at(cf,x,2.65,-6.6),darken(brass,.2),MT,true)
		meshSlot(lamp,"TwinLantern",C("FFE08A"),nil,"Uniform")
	end
	signAt(m,at(cf,0,0,-9)*CFrame.Angles(0,math.pi,0),"Council Hall","COMPASS QUAY   /   ISLE COUNCIL · BALLOT",gold,10,{kind="banner"})
	anchor(m,"Waypoint_CouncilHall",at(cf,0,0,-11),pos)
	-- The Clerk stands in front of the step, clear of every other NPC anchor.
	local clerk
	for _,obj in ipairs(hub:GetDescendants()) do if obj.Name==clerkName then clerk=obj end end
	local spot
	for _,x in ipairs({-4,4,-6,6,-2.5,2.5}) do
		local p=at(cf,x,0,-8).Position
		local clear=true
		for _,other in ipairs(npcAnchors) do
			if V(p.X-other.CFrame.Position.X,0,p.Z-other.CFrame.Position.Z).Magnitude<7 then clear=false end
		end
		if clear then spot=p break end
	end
	spot=spot or at(cf,-4,0,-8).Position
	local face=at(cf,0,0,-30).Position
	if clerk then clerk.CFrame=facing(V(spot.X,clerk.CFrame.Position.Y,spot.Z),face)
	else anchor(hub,"NPC_"..CD.CLERK,spot,face) end
end)()
-- End Isle Council Hall.
-- >>> BEGIN Beaconry (Beaconry team; docs/DEPTH-CONTRACT.md §37; Data.Beaconry) >>>
-- One beacon pyre per region on the region's Mote Shrine island
-- (Data.Exploration.ShrineIsle): a stone plinth (Column mesh), an iron brazier
-- (Cauldron mesh, carries the prompt IsleAction "beaconLight", IsleItem
-- <beacon>, IsleRegion <region>), a stack of kindling (TimberBundle mesh) and
-- a flame volume (invisible until lit) holding a night PointLight created OFF
-- with LightWanted = false, a Fire and an ember ParticleEmitter (both off).
-- beaconry.server.lua lights them from the BeaconryBeacons attribute the
-- server publishes (flame visible + Neon, LightWanted = true, so the §35
-- director lights it after dusk). Models carry BeaconContent = true and
-- BeaconId; anchors Waypoint_Beacon_<id>. Parts: 4 per pyre + 1 invisible
-- anchor = 5 x 9 = 45 static parts, 9 night lights (off), no Neon at build.
-------------------------------------------------------------------------------
do
	local B,EX=Data.Beaconry,Data.Exploration
	if B and EX and EX.ShrineIsle then
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Wildflowers=true} -- §40: paths (village lanes) block; see below
		local taken={}
		local function blocked(host,pos,radius)
			for _,q in ipairs(taken) do if V(pos.X-q.X,0,pos.Z-q.Z).Magnitude<radius+8 then return true end end
			-- Clear of creature spawn markers and their roam (no fights in the warmth).
			for _,marker in ipairs(spawnFolder:GetChildren()) do
				if marker:IsA("BasePart") then
					local c=marker.CFrame.Position
					if V(pos.X-c.X,0,pos.Z-c.Z).Magnitude<radius+10+(tonumber(marker:GetAttribute("Radius")) or 0) then return true end
				end
			end
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj) -- §40 QC L2: declared mesh boxes block whole
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>(if obj.Name=="Path" then pos.Y-1 else pos.Y+.3) and c.Y-ey<pos.Y+12 then return true end
				end
				-- Keep clear of every prompt on the isle (stations, nodes, shrines).
				if obj:IsA("ProximityPrompt") and obj.Parent and obj.Parent:IsA("BasePart") then
					local c=obj.Parent.CFrame.Position
					if V(pos.X-c.X,0,pos.Z-c.Z).Magnitude<radius+8 then return true end
				end
			end
			return false
		end
		local function spot(host,angle,radius)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			local first
			-- Watch-fires stand out toward the rim (and clear of the busy centre).
			for _,f in ipairs({.7,.62,.76,.55,.48}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					first=first or pos
					if not blocked(host,pos,radius) then table.insert(taken,pos) return pos end
				end
			end
			table.insert(taken,first)
			return first
		end
		local iron,stone=C("3D3732"),C("8D8A84")
		for i,id in ipairs(B.BeaconOrder) do
			local b=B.Beacons[id]
			local host=islandsFolder:FindFirstChild(EX.ShrineIsle[b.region] or "")
			if host then
				local pos=spot(host,200+i*23,6)
				local IC=host:GetAttribute("IslandCenter")
				local cf=facing(pos,V(IC.X,pos.Y,IC.Z))
				local glow=C(b.color)
				local m=group("Beacon "..b.name,host)
				m:SetAttribute("BeaconContent",true)
				m:SetAttribute("BeaconId",id)
				local plinth=part(m,"Beacon plinth",V(4.6,3.2,4.6),at(cf,0,1.6,0),stone,ST,true)
				meshSlot(plinth,"Column",lighten(stone,.1))
				local brazier=part(m,"Beacon brazier",V(5.2,1.8,5.2),at(cf,0,4.1,0),iron,MT,true)
				meshSlot(brazier,"Cauldron",darken(glow,.55))
				local kindling=part(m,"Beacon kindling",V(3.4,1.6,3.4),at(cf,0,5.4,0),timber,WO,false)
				meshSlot(kindling,"TimberBundle",timber)
				local flame=part(m,"Beacon flame",V(2.8,4,2.8),at(cf,0,7.6,0),glow,SM,false)
				flame.Transparency,flame.CastShadow,flame.CanQuery=1,false,false
				flame:SetAttribute("BeaconFlame",true)
				local l=light(flame,glow,1.4,36,{night=true,lift=0})
				l:SetAttribute("LightWanted",false) -- §35: wanted only while the beacon burns (beaconry.server.lua)
				l.Name="Beacon light"
				local fire=Instance.new("Fire")
				fire.Name="Beacon fire"
				fire.Color,fire.SecondaryColor=glow,C("FFF1C2")
				fire.Size,fire.Heat,fire.Enabled=7,12,false
				fire.Parent=flame
				local embers=Instance.new("ParticleEmitter")
				embers.Name="Beacon embers"
				embers.Rate,embers.Enabled,embers.LightEmission=14,false,.9
				embers.Lifetime,embers.Speed=NumberRange.new(1.2,2.4),NumberRange.new(4,8)
				embers.SpreadAngle=Vector2.new(18,18)
				embers.Size=NumberSequence.new(.35,0)
				embers.Color=ColorSequence.new(glow,C("FFE3A3"))
				embers.Parent=flame
				local q=prompt(brazier,"Light",b.name.." · Beaconry","beaconLight",id)
				q:SetAttribute("IsleRegion",b.region)
				anchor(m,"Waypoint_Beacon_"..id,at(cf,0,0,-6).Position,pos)
				-- QC: the Beaconkeeper (Kindling Lessons) stands beside the Quayfire,
				-- 7+ studs from every other townsfolk anchor and outside the pyre prompt's reach.
				if B.KEEPER and id=="Hub" then
					local keeperName="Anchor_NPC_"..B.KEEPER
					local keeper,others=nil,{}
					for _,obj in ipairs(host:GetDescendants()) do
						if obj.Name==keeperName then keeper=obj
						elseif obj:IsA("BasePart") and string.find(obj.Name,"^Anchor_NPC_") then table.insert(others,obj.CFrame.Position) end
					end
					local stand
					for _,o in ipairs({{-8,-7},{8,-7},{-10,-2},{10,-2},{-6,-11},{6,-11}}) do
						local p=at(cf,o[1],0,o[2]).Position
						local clear=true
						for _,q in ipairs(others) do if V(p.X-q.X,0,p.Z-q.Z).Magnitude<7 then clear=false end end
						if clear then stand=p break end
					end
					stand=stand or at(cf,-8,0,-7).Position
					if keeper then keeper.CFrame=facing(V(stand.X,keeper.CFrame.Position.Y,stand.Z),pos)
					else anchor(host,"NPC_"..B.KEEPER,stand,pos) end
				end
			end
		end
	end
end
-- <<< END Beaconry <<<

-------------------------------------------------------------------------------
-- >>> QoL Depth (§41) >>> The Lumen Lectern: one station prop on the front of
-- the Aether Museum dais (Compass Quay), between the display case and the log
-- lectern, in its own Model "Lumen Lectern" (LecternContent = true). Prompt IsleAction "lecternVisit" (server: QoL block opens the
-- 10-minute trial window and Hero › Lectern). 1 mesh-slot part + the invisible
-- Anchor_Waypoint_Lectern = 2 static parts; no lights, no Neon.
-------------------------------------------------------------------------------
do
	local hub=islandsFolder:FindFirstChild("Compass Quay")
	local museum=hub and hub:FindFirstChild("Aether Museum",true)
	local dais=museum and museum:FindFirstChild("Museum dais")
	if dais then
		local cf=dais.CFrame*CFrame.new(0,-.285,0)
		-- Its own model beside the museum's (the museum's prompts all route to logsBoard).
		local m=group("Lumen Lectern",hub)
		m:SetAttribute("LecternContent",true)
		local stand=part(m,"Lumen Lectern",V(2.4,2.2,1.4),at(cf,0,1.67,-4.4),C("3A2E5C"),WO,true)
		meshSlot(stand,"Workbench",C("B9A7FF"))
		prompt(stand,"Study","Lumen Lectern · Enchanting trials","lecternVisit")
		anchor(m,"Waypoint_Lectern",at(cf,0,0,-6.4),cf.Position)
	end
end
-- <<< END QoL Depth <<<
-- Hall furnishings (World Art pass 2, §40): the Guild Hall pavilion gains a
-- rug runner, two trestle tables with benches and candles, a wall bench and an
-- iron chandelier (one HallFurnishings mesh on an invisible host), placed last
-- and only if its whole box is clear of every part, prompt and anchor there.
do
	local terrace=islandsFolder:FindFirstChild("Guild Terrace")
	local hall=terrace and terrace:FindFirstChild("Guild Hall",true)
	local floor=hall and hall:FindFirstChild("Hall floor")
	if floor then
		local centre,size=Buildings.fitOf(BUILDING_KIT.HallFurnishings)
		-- The floor's own frame (its yaw), 3.6 studs along its X, on its top.
		local ground=floor.CFrame*CFrame.new(3.6,floor.Size.Y/2,0)
		local hostCF=ground*CFrame.new(centre)
		local r,u,l=hostCF.RightVector,hostCF.UpVector,hostCF.LookVector
		local ext=V(math.abs(r.X)*size.X+math.abs(u.X)*size.Y+math.abs(l.X)*size.Z,math.abs(r.Y)*size.X+math.abs(u.Y)*size.Y+math.abs(l.Y)*size.Z,
			math.abs(r.Z)*size.X+math.abs(u.Z)*size.Y+math.abs(l.Z)*size.Z)/2
		local lo,hi=hostCF.Position-ext,hostCF.Position+ext
		local clear=true
		for _,obj in ipairs(terrace:GetDescendants()) do
			if obj:IsA("BasePart") and obj~=floor and obj.Name~="Meadow" and (obj.Transparency<1 or obj.CanCollide
				or obj:FindFirstChildOfClass("ProximityPrompt") or string.find(obj.Name,"^Anchor_")) then
				local c,s,cf=obj.CFrame.Position,obj.Size/2,obj.CFrame
				local e=V(math.abs(cf.RightVector.X)*s.X+math.abs(cf.UpVector.X)*s.Y+math.abs(cf.LookVector.X)*s.Z,
					math.abs(cf.RightVector.Y)*s.X+math.abs(cf.UpVector.Y)*s.Y+math.abs(cf.LookVector.Y)*s.Z,
					math.abs(cf.RightVector.Z)*s.X+math.abs(cf.UpVector.Z)*s.Y+math.abs(cf.LookVector.Z)*s.Z)
				if c.X-e.X<hi.X and c.X+e.X>lo.X and c.Y-e.Y<hi.Y and c.Y+e.Y>lo.Y and c.Z-e.Z<hi.Z and c.Z+e.Z>lo.Z then clear=false break end
			end
		end
		if clear then
			local host=part(hall,"Hall furnishings",size,hostCF,cream,SM,false)
			host.Transparency,host.CastShadow,host.CanQuery=1,false,false
			meshSlot(host,"HallFurnishings",C("3F6FB5"))
			host:SetAttribute("Interior","HallFurnishings")
			Buildings.furniture(hall,"HallFurnishings",ground) -- §40 QC L6: tables and benches collide
		end
	end
end
-------------------------------------------------------------------------------
-- >>> BEGIN Runebinding (Runebinding team; docs/DEPTH-CONTRACT.md §49; Data.Runebinding) >>>
-- * The Shardgate (Compass Quay): a forged basalt dais (prompt IsleAction
--   "rbGate") beside the Runebinder (Anchor_NPC_Runebinder is moved next to it)
--   and Anchor_Waypoint_Shardgate (the return landing).
-- * The Shardhollow: a pocket isle under Workspace.AetherIsles (off the chart,
--   like the crew havens): 8 Aether and 4 Lucent shard outcrops (§42 special
--   struck nodes, StrikeKind "shard", ShardKind <id>), the Waygate dais (prompt
--   "rbWaygate": the altar picker), the Quay return dais ("rbTravel" Quay), and
--   the Glyph Rift at its heart: the Rift Guardian monolith (RiftMonolith
--   mesh), the entry plinth ("riftJoin"), the workbench ("riftShape"), two
--   fragment heaps (StrikeKind "riftFragment") and eight guardian portals
--   (GuardianPortal meshes, "riftCharge" <altar id>, attribute RiftPortal).
-- * Eleven Binding Altars (BindingAltar mesh tinted the rune's colour, tag
--   "RuneAltar", attribute AltarId) on their isles (Data.Runebinding.Altars),
--   each with a glass keystone (runes.client.lua spins and lights it; the
--   "Return" prompt to the Shardhollow) and Anchor_Waypoint_Altar_<id>.
-- No server lights and no Neon here (the islands' neon / light budgets are
-- untouched); every glow is client-side (runes.client.lua).
-------------------------------------------------------------------------------
do
	local RB=Data.Runebinding
	if RB then
		local FLOOR={Meadow=true,["Floating foundation"]=true,["Mineral stratum"]=true,["Lower basalt"]=true,["Fractured cliff"]=true,
			["Keel rock"]=true,["Edge guard"]=true,["Aether vein"]=true,["Shore ledge"]=true,Wildflowers=true}
		local taken={}
		local function blocked(host,pos,radius)
			for _,q in ipairs(taken) do if V(pos.X-q.X,0,pos.Z-q.Z).Magnitude<radius+8 then return true end end
			for _,marker in ipairs(spawnFolder:GetChildren()) do
				if marker:IsA("BasePart") then
					local c=marker.CFrame.Position
					if V(pos.X-c.X,0,pos.Z-c.Z).Magnitude<radius+10+(tonumber(marker:GetAttribute("Radius")) or 0) then return true end
				end
			end
			for _,obj in ipairs(host:GetDescendants()) do
				if obj:IsA("BasePart") and not FLOOR[obj.Name] and not string.find(obj.Name,"^Anchor_") and (obj.Transparency<1 or obj.CanCollide) then
					local cf,sz=Buildings.box(obj)
					local function ext(axis) return math.abs(cf.RightVector[axis])*sz.X/2+math.abs(cf.UpVector[axis])*sz.Y/2+math.abs(cf.LookVector[axis])*sz.Z/2 end
					local c=cf.Position
					local dx=math.max(0,math.abs(pos.X-c.X)-ext("X"))
					local dz=math.max(0,math.abs(pos.Z-c.Z)-ext("Z"))
					local ey=ext("Y")
					if dx*dx+dz*dz<radius*radius and c.Y+ey>(if obj.Name=="Path" then pos.Y-1 else pos.Y+.3) and c.Y-ey<pos.Y+12 then return true end
				end
				if obj:IsA("ProximityPrompt") and obj.Parent and obj.Parent:IsA("BasePart") then
					local c=obj.Parent.CFrame.Position
					if V(pos.X-c.X,0,pos.Z-c.Z).Magnitude<radius+8 then return true end
				end
				if obj:IsA("BasePart") and string.find(obj.Name,"^Anchor_NPC_") then
					local c=obj.CFrame.Position
					if V(pos.X-c.X,0,pos.Z-c.Z).Magnitude<radius+5 then return true end
				end
			end
			return false
		end
		-- The prop and its landing anchor (`ahead` studs toward the isle's centre) must both stand clear.
		local function spot(host,angle,radius,ahead)
			local IC,R=host:GetAttribute("IslandCenter"),host:GetAttribute("IslandRadius")
			local first
			for _,f in ipairs({.58,.66,.5,.72,.44,.78,.36}) do
				for k=0,23 do
					local a=math.rad(angle+(if k%2==0 then 1 else -1)*math.ceil(k/2)*15)
					local pos=IC+V(math.cos(a),0,math.sin(a))*R*f
					first=first or pos
					local toward=V(IC.X-pos.X,0,IC.Z-pos.Z)
					local landing=pos+(if toward.Magnitude>0 then toward.Unit else V(0,0,1))*(ahead or 0)
					if not blocked(host,pos,radius) and not blocked(host,landing,2.5) then table.insert(taken,pos) return pos end
				end
			end
			table.insert(taken,first)
			return first
		end
		local basalt,violet,slate=C("2E2A44"),C("C38BFF"),C("3D3658")

		-- Binding Altars --------------------------------------------------------------
		for i,id in ipairs(RB.AltarOrder) do
			local a=RB.AltarById[id]
			local host=islandsFolder:FindFirstChild(a.isle)
			if host then
				local pos=spot(host,35+i*41,5,6.5)
				local IC=host:GetAttribute("IslandCenter")
				local cf=facing(pos,V(IC.X,pos.Y,IC.Z))
				local glow=C(a.color)
				local m=group(a.name,host)
				m:SetAttribute("RuneAltarContent",true)
				local base=part(m,"Binding altar",V(5,4.2,5),at(cf,0,2.1,0),darken(glow,.55),ST,true)
				meshSlot(base,"BindingAltar",glow)
				base:SetAttribute("AltarId",id)
				Tags:AddTag(base,"RuneAltar")
				local q=prompt(base,"Bind",a.name.." · Runebinding "..a.level,"runeAltar",id)
				q:SetAttribute("IsleRegion",a.region)
				local stone=part(m,"Altar keystone",V(1.3,1.9,1.3),at(cf,0,5.9,0),glow,GL,false)
				stone.Transparency,stone.CastShadow=.15,false
				stone:SetAttribute("AltarKeystone",id)
				local back=prompt(stone,"Return","Shardhollow","rbTravel","Field")
				back.KeyboardKeyCode=Enum.KeyCode.R
				back.UIOffset=Vector2.new(0,-42)
				anchor(m,"Waypoint_Altar_"..id,at(cf,0,0,-6.5).Position,pos)
			end
		end

		-- The Shardgate and the Runebinder (Compass Quay) -----------------------------------
		local quay=islandsFolder:FindFirstChild("Compass Quay")
		if quay then
			local pos=spot(quay,312,5,7)
			local IC=quay:GetAttribute("IslandCenter")
			local cf=facing(pos,V(IC.X,pos.Y,IC.Z))
			local m=group("The Shardgate",quay)
			local dais=part(m,"Shardgate dais",V(5,5.6,5),at(cf,0,2.8,0),basalt,ST,true)
			meshSlot(dais,"TravelBeaconBasalt",violet)
			prompt(dais,"Travel","The Shardhollow · Runebinding","rbGate")
			anchor(m,"Waypoint_Shardgate",at(cf,0,0,-7).Position,pos)
			local keeperName="Anchor_NPC_"..RB.MENTOR
			local keeper,others=nil,{}
			for _,obj in ipairs(quay:GetDescendants()) do
				if obj.Name==keeperName then keeper=obj
				elseif obj:IsA("BasePart") and string.find(obj.Name,"^Anchor_NPC_") then table.insert(others,obj.CFrame.Position) end
			end
			local stand
			for _,o in ipairs({{-8,-6},{8,-6},{-10,-1},{10,-1},{-6,-10},{6,-10}}) do
				local p=at(cf,o[1],0,o[2]).Position
				local clear=true
				for _,q in ipairs(others) do if V(p.X-q.X,0,p.Z-q.Z).Magnitude<7 then clear=false end end
				if clear then stand=p break end
			end
			stand=stand or at(cf,-8,0,-6).Position
			if keeper then keeper.CFrame=facing(V(stand.X,keeper.CFrame.Position.Y,stand.Z),pos)
			else anchor(quay,"NPC_"..RB.MENTOR,stand,pos) end
		end

		-- The Shardhollow (a pocket isle off the chart) ----------------------------------------
		local FIELD,FR=V(1500,200,1500),64
		local field=island(RB.FIELD,FIELD,FR,{parent=world,rim=false,top=C("4A4266"),stone=basalt,stratum=slate,ground=ST,keelShape="IslandKeelCrystal"})
		field:SetAttribute("RuneField",true)
		local function onField(x,z) return FIELD+V(x,0,z) end
		local arrive=onField(0,-50)
		anchor(field,"Waypoint_Shardhollow",arrive,FIELD)
		sign(field,onField(-9,-44),"The Shardhollow","Runebinding  /  Glyph Rift",violet,0,12)
		-- Return to the Quay and the Waygate (the altar picker), either side of the landing.
		local quayDais=part(field,"Quaygate dais",V(5,5.6,5),facing(onField(14,-44)+V(0,2.8,0),FIELD+V(0,2.8,0)),basalt,ST,true)
		meshSlot(quayDais,"TravelBeaconBasalt",C("8EE6CB"))
		prompt(quayDais,"Return","Compass Quay","rbTravel","Quay")
		local waygate=part(field,"Waygate dais",V(5,5.6,5),facing(onField(0,-36)+V(0,2.8,0),FIELD+V(0,2.8,0)),basalt,ST,true)
		meshSlot(waygate,"TravelBeaconBasalt",violet)
		prompt(waygate,"Choose altar","Shardhollow Waygate","rbWaygate")
		anchor(field,"Waypoint_Waygate",onField(0,-30),FIELD)
		-- Shard outcrops: Aether around the rim, Lucent on the far side (Mining 30).
		local function outcrop(pos,shardId,index)
			local s=RB.Shards[shardId]
			local tint=C(s.color)
			local m=group(s.name.." outcrop",field)
			local host=part(m,"Shard outcrop",V(4.4,2.3,3.8),CFrame.new(pos+V(0,1.05,0))*CFrame.Angles(0,index*1.3,.08),darken(tint,.55),ST,false)
			meshSlot(host,"OreVein",tint,true,"Uniform")
			for k=1,2 do
				local a=index+k*2.4
				gem(m,"Shard crystal",pos+V(math.cos(a)*1.1,2.2+k*.5,math.sin(a)*1.1),V(.9+k*.25,2.2+k*.9,.9+k*.25),if k==1 then lighten(tint,.3) else tint,a)
			end
			Node.special(host,s.entry,"shard",s.name.." Outcrop")
			host:SetAttribute("ShardKind",shardId)
			return m
		end
		local n=0
		for k=0,7 do
			local ang=math.rad(-50+k*(280/7)+90)
			n+=1
			outcrop(FIELD+V(math.cos(ang),0,math.sin(ang))*50,"AetherShard",n)
		end
		for k=0,3 do
			local ang=math.rad(60+k*20)
			n+=1
			outcrop(FIELD+V(math.cos(ang),0,math.sin(ang))*38,"LucentShard",n)
		end

		-- The Glyph Rift --------------------------------------------------------------------
		local rift=group("The Glyph Rift",field)
		local monolith=part(rift,"Rift Guardian",V(6,14,6),CFrame.new(FIELD+V(0,7,4)),slate,ST,true)
		meshSlot(monolith,"RiftMonolith",violet)
		monolith:SetAttribute("RiftGuardian",true)
		anchor(field,"Waypoint_Rift",FIELD+V(0,0,4),FIELD)
		local plinth=part(rift,"Rift entry plinth",V(3,1.6,3),CFrame.new(FIELD+V(0,.8,-12)),basalt,ST,true)
		meshSlot(plinth,"Column",slate)
		prompt(plinth,"Enter","The Glyph Rift · Runebinding "..RB.Rift.LEVEL,"riftJoin")
		local bench=part(rift,"Rift workbench",V(4.6,2.6,3),facing(FIELD+V(13,1.3,-6),FIELD+V(0,1.3,4)),slate,ST,true)
		meshSlot(bench,"Anvil",violet)
		prompt(bench,"Shape","Charged essence","riftShape")
		for k,x in ipairs({-13,13}) do
			local heap=part(rift,"Fragment heap",V(4.2,2,4.2),CFrame.new(FIELD+V(x,1,20))*CFrame.Angles(0,k,0),darken(violet,.45),ST,false)
			meshSlot(heap,"OreVein",violet,false,"Uniform")
			Node.special(heap,"Ore","riftFragment","Rift Fragment Heap")
		end
		for k,id in ipairs(RB.Rift.PORTALS) do
			local a=RB.AltarById[id]
			local ang=math.rad(-90+(k-.5)*(360/#RB.Rift.PORTALS))
			local pos=FIELD+V(0,0,4)+V(math.cos(ang),0,math.sin(ang))*24
			local portal=part(rift,a.id.." portal",V(4.22,6.96,1.6),facing(pos+V(0,3.48,0),FIELD+V(0,3.48,4)),C(a.color),ST,true)
			meshSlot(portal,"GuardianPortal",C(a.color))
			portal:SetAttribute("RiftPortal",id)
			Tags:AddTag(portal,"RiftPortal")
			prompt(portal,"Charge",a.id.." portal · Runebinding "..a.level,"riftCharge",id)
		end
	end
end
-- <<< END Runebinding <<<
-- §28 QC M4: static signs step clear of walls once the world is built.
Signs.settle(islandsFolder)
