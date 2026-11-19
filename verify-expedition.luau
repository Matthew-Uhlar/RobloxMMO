-- Production expedition logic with deterministic players, signals, and time.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local r=require("@lune/roblox")
local function signal()
	local callbacks={}
	return {
		Connect=function(_,fn) table.insert(callbacks,fn) end,
		Fire=function(_,...) for _,fn in callbacks do fn(...) end end,
	}
end
local signals={}
r.implementProperty("ProximityPrompt","Triggered",function(p)
	signals[p]=signals[p] or signal()
	return signals[p]
end)
r.implementProperty("Workspace","DescendantAdded",function() return signal() end)
local world=r.Instance.new("Workspace")
local gate=r.Instance.new("Part")
gate.Name="ExpeditionGate"
gate.Position=r.Vector3.new(0,2,-121)
gate.CFrame=r.CFrame.new(gate.Position)
gate.Parent=world
local players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end}
local heartbeat=signal()
local rewards={}
local reward={Fire=function(_,p) rewards[p]=(rewards[p] or 0)+1 end}
local services={Players=players,RunService={Heartbeat=heartbeat},
	CollectionService={AddTag=function(part,anchor,tag) anchor:SetAttribute("TestArtTag",tag) end},
	ServerStorage={FindFirstChild=function(_,name) return name=="IsleExpeditionReward" and reward or nil end}}
local now=10
local env={game={GetService=function(_,name) return services[name] end},workspace=world,
	Instance=r.Instance,Vector3=r.Vector3,Vector2=r.Vector2,Color3=r.Color3,CFrame=r.CFrame,
	UDim2=r.UDim2,Enum=r.Enum,os={clock=function() return now end}}
luau.load(fs.readFile("expedition.server.lua"),{environment=env,injectGlobals=true})()
local function player()
	local root={Position=r.Vector3.zero}
	local hum={Health=100,MaxHealth=100}
	function hum:TakeDamage(n) self.Health=math.max(0,self.Health-n) end
	local char={}
	function char:FindFirstChild(name) if name=="HumanoidRootPart" then return root end end
	function char:FindFirstChildOfClass(name) if name=="Humanoid" then return hum end end
	function char:PivotTo(cf) root.Position=cf.Position end
	local p={Character=char,CharacterRemoving=signal(),attributes={}}
	function p:SetAttribute(k,v) self.attributes[k]=v end
	function p:GetAttribute(k) return self.attributes[k] end
	players.PlayerAdded:Fire(p)
	return p,root,hum
end
local checks=0
local function check(condition,label) assert(condition,label) checks+=1 end
local function promptFor(partName,action)
	for _,obj in world:GetDescendants() do
		if obj:IsA("ProximityPrompt") and obj.Parent.Name==partName and obj.ActionText==action then return obj end
	end
	error("Missing prompt "..partName.." / "..action)
end
local function use(p,partName,action,move)
	local prompt=promptFor(partName,action)
	if move~=false then p.Character:FindFirstChild("HumanoidRootPart").Position=prompt.Parent.Position end
	now+=3
	signals[prompt]:Fire(p)
end
local caption=world:FindFirstChild("TextLabel",true)
local artCore=world:FindFirstChild("Eclipse Heart",true)
check(artCore:GetAttribute("Shape")=="EclipseAstrolabe","heart uses original astrolabe mesh")
check(artCore.CanCollide and artCore.Transparency==1,"heart hides placeholder but preserves collision")
check(artCore:GetAttribute("VisualState")=="Shielded","heart art communicates puzzle gate")
for index=1,2 do
	local sentinel=world:FindFirstChild("Sentinel "..index,true)
	check(sentinel:GetAttribute("Shape")=="ObservatorySentinel","sentinel uses custom enemy mesh")
	check(sentinel.CanCollide and sentinel.Transparency==1,"sentinel retains authoritative collider")
end
local a,ar,ah=player()
local b,br,bh=player()
local c,cr,ch=player()
use(a,"Eclipse Heart","Strike core")
check(caption.Text:find("0 / 3",1,true)~=nil,"non-member cannot skip prisms")
use(a,"Mage oath","Choose role")
check(a:GetAttribute("ExpeditionRole")=="Mage","role selection")
use(a,"ExpeditionGate","Enter expedition")
check(ar.Position.Z==1824,"entry transport")
use(b,"Tank oath","Choose role")
use(b,"ExpeditionGate","Enter expedition")
use(c,"ExpeditionGate","Enter expedition")
local pylons={}
for _,obj in world:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj.Parent.Name=="Resonance prism" then table.insert(pylons,obj) end
end
check(#pylons==3,"three objective prisms")
for _,prompt in pylons do
	ar.Position=prompt.Parent.Position
	signals[prompt]:Fire(a)
	signals[prompt]:Fire(a)
end
check(caption.Text:find("SENTINEL HALL",1,true)~=nil,"prisms unlock guardian chamber")
for _,p in pylons do check(p.Parent:GetAttribute("VisualState")=="Tuned","tuned prism art remains visible") end
use(a,"Eclipse Heart","Strike core")
check(caption.Text:find("SENTINEL HALL",1,true)~=nil,"core locked until guardians defeated")
use(a,"Sentinel passage","Enter guardian chamber")
check(ar.Position.Z==1713,"guardian chamber travel")
use(a,"Core passage","Return to core")
check(ar.Position.Z~=1778,"guardian exit remains locked")
for index=1,2 do
	for _=1,6 do use(a,"Sentinel "..index,"Strike guardian") end
end
check(caption.Text:find("12 / 12",1,true)~=nil,"guardians unlock core")
for index=1,2 do check(world:FindFirstChild("Sentinel "..index,true):GetAttribute("VisualState")=="Defeated","defeated sentinel art marked") end
check(artCore:GetAttribute("VisualState")=="Active","heart art reveals damageable phase")
use(a,"Core passage","Return to core")
check(ar.Position.Z==1778,"guardian exit opens")
ah.Health=100
use(b,"Eclipse Heart","Ranged attack")
check(caption.Text:find("12 / 12",1,true)~=nil,"tank cannot use ranged intent")
use(a,"Eclipse Heart","Ranged attack")
check(caption.Text:find("9 / 12",1,true)~=nil,"mage burst damages core")
local core=world:FindFirstChild("Eclipse Heart",true)
ar.Position=core.Position+r.Vector3.new(20,0,0)
br.Position=core.Position
cr.Position=core.Position+r.Vector3.new(25,0,0)
b:SetAttribute("SkillDefense",2)
heartbeat:Fire(3.5)
check(world:FindFirstChild("Pulse radius",true).Transparency==0.25,"pulse warning before damage")
check(artCore:GetAttribute("VisualState")=="Warning","astrolabe reinforces amber pulse telegraph")
heartbeat:Fire(1.5)
check(bh.Health==93,"tank reduction and skill defense")
check(ah.Health==100 and ch.Health==100,"outside pulse remains safe")
use(b,"Eclipse Heart","Strike core")
check(caption.Text:find("8 / 12",1,true)~=nil,"tank melee contribution")
for _=1,3 do use(a,"Eclipse Heart","Ranged attack") end
check(rewards[a]==1 and rewards[b]==1,"contributors rewarded once")
check(rewards[c]==nil,"idle member has no reward")
check(ar.Position.Z==-121 and br.Position.Z==-121,"victory returns party")
check(caption.Text:find("0 / 3",1,true)~=nil,"victory resets encounter")
check(artCore:GetAttribute("VisualState")=="Shielded","heart art resets with encounter")
for index=1,2 do check(world:FindFirstChild("Sentinel "..index,true):GetAttribute("VisualState")=="Active","sentinel art revives on reset") end
for _,p in pylons do check(p.Parent:GetAttribute("VisualState")=="Active","prism art resets") end
use(a,"Eclipse Heart","Strike core")
check(rewards[a]==1,"post-victory replay has no reward")
use(a,"Healer oath","Choose role")
use(a,"ExpeditionGate","Enter expedition")
use(b,"ExpeditionGate","Enter expedition")
for _,prompt in pylons do ar.Position=prompt.Parent.Position signals[prompt]:Fire(a) end
for index=1,2 do
	for _=1,6 do use(a,"Sentinel "..index,"Strike guardian") end
end
bh.Health=70
br.Position=core.Position
use(a,"Eclipse Heart","Strike core")
check(bh.Health==73,"healer restores nearby ally")
local previous=caption.Text
signals[promptFor("Eclipse Heart","Strike core")]:Fire(a)
check(caption.Text==previous,"attack cooldown rejects replay")
players.PlayerRemoving:Fire(a)
players.PlayerRemoving:Fire(b)
check(caption.Text:find("0 / 3",1,true)~=nil,"empty expedition resets")
cr.Position=r.Vector3.zero
use(c,"ExpeditionGate","Enter expedition",false)
check(cr.Position==r.Vector3.zero,"remote entry rejected at distant location")
print("Expedition QA passed "..checks.." behavioral checks.")
