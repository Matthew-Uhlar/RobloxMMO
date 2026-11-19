-- Production expedition logic with deterministic players, signals, and time.
-- Part 1: the original Observatory encounter (Floor I) behaviour.
-- Part 2: Dungeons rules in shared/GameData.lua (floors, scaling, score, grade, rewards, credit).
-- Part 3: Dungeons behaviour in expedition.server.lua (pad, gating, floor mechanics, credit).
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local r=require("@lune/roblox")
local Data=luau.load(fs.readFile("shared/GameData.lua"),{debugName="GameData"})()
local Progression=luau.load(fs.readFile("shared/Progression.lua"),{debugName="Progression",environment={script=nil},injectGlobals=true})()
Progression.useData(Data)
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
local rewards,payloads={},{}
local reward={Fire=function(_,p,payload) rewards[p]=(rewards[p] or 0)+1 payloads[p]=payload end}
local levels,irons={},{}
local bridge={Invoke=function(_,op,p)
	if op=="dungeon" then return {level=levels[p] or 1,ironman=irons[p]==true} end
	return nil
end}
local services={Players=players,RunService={Heartbeat=heartbeat},
	CollectionService={AddTag=function(part,anchor,tag) anchor:SetAttribute("TestArtTag",tag) end},
	ReplicatedStorage={WaitForChild=function(_,name) return name end},
	ServerStorage={FindFirstChild=function(_,name)
		if name=="IsleExpeditionReward" then return reward elseif name=="IsleBridge" then return bridge end
		return nil
	end}}
local now=10
local env={game={GetService=function(_,name) return services[name] end},workspace=world,
	require=function(name) assert(name=="AetherData","expedition requires shared data") return Data end,
	Instance=r.Instance,Vector3=r.Vector3,Vector2=r.Vector2,Color3=r.Color3,CFrame=r.CFrame,
	UDim2=r.UDim2,Enum=r.Enum,os={clock=function() return now end}}
luau.load(fs.readFile("expedition.server.lua"),{environment=env,injectGlobals=true})()
local hums,roots={},{}
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
	hums[p],roots[p]=hum,root
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
-- Matchmaking: the pad window closes padSeconds after the run is opened.
local function launch()
	now+=Data.Dungeons.padSeconds
	heartbeat:Fire(0)
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
check(caption.Text:find("MATCHMAKING",1,true)~=nil,"entry opens the matchmaking pad")
use(b,"Tank oath","Choose role")
use(b,"ExpeditionGate","Enter expedition")
use(c,"ExpeditionGate","Enter expedition")
launch()
check(ar.Position.Z==1824,"entry transport")
check(br.Position.Z==1824 and cr.Position.Z==1824,"pad party transported together")
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
-- Contribution threshold (design change): the Tank must carry >= 10% of the
-- party's damage + tuning points, so it lands two more blows before the finish.
use(b,"Eclipse Heart","Strike core")
use(b,"Eclipse Heart","Strike core")
for _=1,2 do use(a,"Eclipse Heart","Ranged attack") end
check(rewards[a]==1 and rewards[b]==1,"contributors rewarded once")
check(rewards[c]==nil,"idle member has no reward")
check(c:GetAttribute("ExpeditionNotice"):find("Contribute",1,true)~=nil,"idle member told why there is no chest")
check(ar.Position.Z==-121 and br.Position.Z==-121,"victory returns party")
check(caption.Text:find("0 / 3",1,true)~=nil,"victory resets encounter")
check(artCore:GetAttribute("VisualState")=="Shielded","heart art resets with encounter")
for index=1,2 do check(world:FindFirstChild("Sentinel "..index,true):GetAttribute("VisualState")=="Active","sentinel art revives on reset") end
for _,p in pylons do check(p.Parent:GetAttribute("VisualState")=="Active","prism art resets") end
use(a,"Eclipse Heart","Strike core")
check(rewards[a]==1,"post-victory replay has no reward")
cr.Position=r.Vector3.new(0,0,500) -- c steps off the pad and sits out the next run
use(a,"Healer oath","Choose role")
use(a,"ExpeditionGate","Enter expedition")
use(b,"ExpeditionGate","Enter expedition")
launch()
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
local baseChecks=checks

------------------------------------------------------------------------------
-- Part 2: Dungeons rules (shared/GameData.lua).
------------------------------------------------------------------------------
local floors=Data.DungeonFloors
check(#floors==5,"five Observatory floors")
local expectedLevels={1,5,12,20,30}
for i,f in ipairs(floors) do
	check(f.index==i and f.level==expectedLevels[i],"floor "..i.." Dungeoneering requirement")
	check(f.name=="Observatory Floor "..f.numeral,"floor "..i.." name")
	check(type(f.boss.name)=="string" and type(f.boss.attack)=="string","floor "..i.." boss named with attack")
	check(f.boss.telegraph>0 and f.boss.telegraph<f.boss.interval,"floor "..i.." boss telegraphs before striking")
	check(f.rewards.dungeoneeringXp>0 and f.rewards.coins>0 and #f.chest>0,"floor "..i.." rewards and chest")
	for _,drop in f.chest do check(Data.Items[drop.item]~=nil,"floor "..i.." chest item "..drop.item.." exists") end
	if i>1 then
		local prev=floors[i-1]
		check(f.hpMult>prev.hpMult and f.damageMult>prev.damageMult,"floor "..i.." scales HP and damage")
		check(f.boss.name~=prev.boss.name,"floor "..i.." has a distinct boss")
		check(f.rewards.dungeoneeringXp>prev.rewards.dungeoneeringXp and f.rewards.coins>prev.rewards.coins
			and f.rewards.combatXp>prev.rewards.combatXp,"floor "..i.." pays more than floor "..(i-1))
		local s,ps=Data.dungeonFloorStats(i),Data.dungeonFloorStats(i-1)
		check(s.guardianHp>ps.guardianHp and s.coreHp>ps.coreHp and s.guardianHit>ps.guardianHit,"floor "..i.." encounter numbers scale")
	end
end
local s1,s5=Data.dungeonFloorStats(1),Data.dungeonFloorStats(5)
check(s1.guardianHp==6 and s1.coreHp==12 and s1.guardianHit==6 and s1.addHp==0,"Floor I keeps the original encounter numbers")
check(s5.guardianHp==33 and s5.coreHp==66 and s5.guardianHit==21 and s5.addHp==28,"Floor V scaled numbers")
check(next(floors[1].mechanics)==nil,"Entrance has no extra mechanics")
check(floors[2].mechanics.orderedPrisms==true and floors[2].mechanics.shieldPhases==nil,"Floor II adds ordered prisms")
check(#floors[3].mechanics.shieldPhases==2 and floors[3].mechanics.addWaves==nil,"Floor III adds core shield phases")
check(floors[4].mechanics.addWaves.count==2 and floors[4].mechanics.enrage==nil,"Floor IV adds wisp waves")
check(floors[5].mechanics.enrage.after==240 and floors[5].mechanics.enrage.damageMult==2,"Floor V adds the enrage timer")
check(floors[1].boss.kind=="pulse" and floors[2].boss.kind=="ring" and floors[3].boss.kind=="meteor" and floors[5].boss.kind=="eclipse","boss attack patterns")
-- Gating through the OSRS curve.
for i,f in ipairs(floors) do
	local need=Progression.xpForLevel(f.level)
	check(Data.dungeonFloorUnlocked(i,Progression.levelForXp(need)),"floor "..i.." opens at Dungeoneering "..f.level)
	if f.level>1 then check(not Data.dungeonFloorUnlocked(i,Progression.levelForXp(need-1)),"floor "..i.." closed one XP short") end
end
check(not Data.dungeonFloorUnlocked(6,99),"no floor VI")
-- Score and grade.
local score,parts=Data.dungeonScore(1,100,0,0)
check(score==300 and parts.speed==100 and parts.survival==100 and parts.skill==100,"flawless fast clear scores 300")
check(Data.dungeonScore(1,180,0,0)==300,"clear at par keeps full speed")
check(Data.dungeonScore(1,270,0,0)==250,"half par over costs 50 speed")
check(Data.dungeonScore(1,360,0,0)==200 and Data.dungeonScore(1,9999,0,0)==200,"speed bottoms out at twice par")
check(Data.dungeonScore(1,100,1,0)==280,"each death costs 20")
check(Data.dungeonScore(1,100,0,1)==285,"each puzzle mistake costs 15")
check(Data.dungeonScore(1,100,9,9)==100,"survival and puzzle clamp at zero")
check(Data.dungeonScore(5,420,0,0)==300 and Data.dungeonScore(5,630,0,0)==250,"par scales with floor")
local boundaries={{300,"S+"},{290,"S+"},{289,"S"},{260,"S"},{259,"A"},{220,"A"},{219,"B"},{170,"B"},{169,"C"},{110,"C"},{109,"D"},{0,"D"}}
for _,pair in boundaries do check(Data.dungeonGrade(pair[1])==pair[2],"score "..pair[1].." grades "..pair[2]) end
check(Data.dungeonGrade(Data.dungeonScore(1,100,0,1))=="S","one mistake drops S+ to S")
check(Data.dungeonGrade(Data.dungeonScore(1,100,3,2))=="B","three deaths and two mistakes grade B")
-- Rewards scale with floor and grade.
local b1=Data.dungeonRewards(1,"B")
check(b1.dungeoneeringXp==60 and b1.combatXp==80 and b1.coins==35 and b1.items.Stormglass==1 and b1.items.ObservatoryEssence==1,"Floor I grade B matches the legacy reward")
local top=Data.dungeonRewards(5,"S+")
check(top.dungeoneeringXp==1600 and top.combatXp==1680 and top.coins==1200 and top.items.Stormglass==5 and top.items.ObservatoryEssence==14,"Floor V S+ reward")
check(Data.dungeonRewards(1,"bogus").coins==35,"unknown grade falls back to B")
for i=1,5 do
	local last=nil
	for g=#Data.DungeonGrades,1,-1 do
		local rw=Data.dungeonRewards(i,Data.DungeonGrades[g].grade)
		if last then check(rw.dungeoneeringXp>=last.dungeoneeringXp and rw.coins>last.coins and rw.items.Stormglass>=last.items.Stormglass,"floor "..i.." grade "..Data.DungeonGrades[g].grade.." pays at least the grade below") end
		last=rw
	end
end
check(Data.dungeonRewards(2,"S+").chest[2].chance==floors[2].chest[2].chance*2,"S+ doubles the rare chest roll")
check(Data.dungeonRewards(2,"D").chest[2].chance==floors[2].chest[2].chance*0.5,"D halves the rare chest roll")
for _,d in Data.dungeonRewards(5,"S+").chest do check(d.chance<=1,"chest chance capped at 1") end
-- Magic Find affects the rare chest roll through Progression.rollDrops.
local floorOneChest=Data.dungeonRewards(1,"B").chest
local function fixed(v) return function() return v end end
check(Progression.rollDrops(floorOneChest,0,fixed(0.005)).AstrolabeCharm==nil,"rare charm misses without Magic Find")
check(Progression.rollDrops(floorOneChest,50,fixed(0.005)).AstrolabeCharm==1,"Magic Find lifts the rare charm roll")
check(Progression.rollDrops(floorOneChest,0,fixed(0.2)).ObservatoryEssence==1,"common essence roll ignores Magic Find")
-- Cooldown, Ironman and contribution rules.
check(Data.Dungeons.clearCooldown==90,"90 s clear cooldown")
check(Data.dungeonCooldownReady(nil,0),"first clear is never on cooldown")
check(not Data.dungeonCooldownReady(100,189),"89 s later is still cooling down")
check(Data.dungeonCooldownReady(100,190),"90 s later credits again")
check(Data.dungeonIronmanCredit(false,5,0),"normal journals ignore the Ironman rule")
check(Data.dungeonIronmanCredit(true,1,0),"solo Ironman clear credits")
check(not Data.dungeonIronmanCredit(true,3,0.29),"Ironman below 30% damage is not credited")
check(Data.dungeonIronmanCredit(true,3,0.30),"Ironman at 30% damage is credited")
check(not Data.dungeonContributed(0,100) and not Data.dungeonContributed(9.9,100),"below 10% is not meaningful")
check(Data.dungeonContributed(10,100),"10% of party points is meaningful")
check(not Data.dungeonContributed(5,0),"no party points means no credit")
-- Dungeon gear.
local essence=Data.Items.ObservatoryEssence
check(essence and essence.kind=="material","Observatory Essence material")
check(#Data.Sets.Observatory.pieces==4,"Starwright Regalia has four pieces")
for _,id in ipairs({"LenswrightSaber","EclipseGlaive","AstrarchFang","ObservatoryHelm","ObservatoryVestment","ObservatoryGreaves","ObservatoryTreads","AstrolabeCharm","UmbralOrrery"}) do
	local def=Data.Items[id]
	check(def and def.dungeon==true and def.stats and next(def.stats)~=nil,id.." is dungeon gear with stats")
	check(Data.Recipes[id]==nil,id.." cannot be crafted")
end
check(Data.Items.AstrolabeCharm.kind=="accessory" and Data.Items.UmbralOrrery.kind=="accessory","dungeon-only accessories")
local delver={xp={Combat=Progression.xpForLevel(20),Dungeoneering=Progression.xpForLevel(20)},items={},equipment={}}
for _,id in Data.Sets.Observatory.pieces do delver.items[id]=1 delver.equipment[Data.Items[id].slot]=id end
delver.items.EclipseGlaive=1
delver.equipment.weapon="EclipseGlaive"
check(Progression.meetsRequirements(delver,Data.Items.EclipseGlaive.requires),"Dungeoneering 20 wields the Eclipse Glaive")
check(not Progression.meetsRequirements(delver,Data.Items.AstrarchFang.requires),"Astrarch Fang needs Dungeoneering 30")
local delverStats=Progression.computeStats(delver,0)
check(delverStats.activeSet=="Observatory","full Starwright Regalia activates its set bonus")
check(delverStats.weapon=="EclipseGlaive" and delverStats.damage>=150,"Eclipse Glaive damage applies")
local dataChecks=checks-baseChecks

------------------------------------------------------------------------------
-- Part 3: Dungeons behaviour in the encounter.
------------------------------------------------------------------------------
local function heal(p) hums[p].Health=100 end
local function rootOf(p) return roots[p] end
local function at(p,offset) rootOf(p).Position=core.Position+(offset or r.Vector3.zero) end
local function onPad(p,dx) rootOf(p).Position=gate.Position+r.Vector3.new(dx or 0,0,0) end
local function tune(p,prism) rootOf(p).Position=prism.Parent.Position now+=1 signals[prism]:Fire(p) end
local function ordered()
	local list=table.clone(pylons)
	table.sort(list,function(x,y) return x.Parent:GetAttribute("TuneOrder")<y.Parent:GetAttribute("TuneOrder") end)
	return list
end
local function tuneInOrder(p) for _,prism in ordered() do tune(p,prism) end end
local function strike(p,partName,action)
	heal(p)
	rootOf(p).Position=promptFor(partName,action).Parent.Position
	now+=3
	signals[promptFor(partName,action)]:Fire(p)
end
local function guardiansDown(p)
	for index=1,2 do
		local sentinel=world:FindFirstChild("Sentinel "..index,true)
		for _=1,60 do
			if sentinel:GetAttribute("VisualState")=="Defeated" then break end
			strike(p,"Sentinel "..index,"Strike guardian")
		end
	end
end
local function coreDown(p)
	for _=1,120 do
		if not artCore:GetAttribute("BossHealth") or caption.Text:find("HOLLOW OBSERVATORY",1,true) then break end
		strike(p,"Eclipse Heart","Strike core")
	end
end
local function wisps()
	local list={}
	for _,obj in world:GetDescendants() do if obj.Name=="Umbral wisp" and obj:IsA("BasePart") then table.insert(list,obj) end end
	return list
end
local function noticeOf(p) return p:GetAttribute("ExpeditionNotice") or "" end
-- Everyone steps off the pad (finished delvers are returned onto it).
local function clearPad() for _,root in roots do root.Position=r.Vector3.new(0,0,900) end end

-- Floor selection is gated by Dungeoneering level (via the IsleBridge "dungeon" op).
local d=player()
local e=player()
local f=player()
local g=player()
levels[d],levels[e],levels[f],levels[g]=4,1,5,7
use(d,"Observatory Floor II","Select floor")
check(d:GetAttribute("ExpeditionFloor")==nil,"Dungeoneering 4 cannot select Floor II")
check(noticeOf(d):find("Dungeoneering 5",1,true)~=nil,"floor denial names the requirement")
levels[d]=5
use(d,"Observatory Floor II","Select floor")
check(d:GetAttribute("ExpeditionFloor")==2,"Dungeoneering 5 selects Floor II")
use(d,"Observatory Floor III","Select floor")
check(d:GetAttribute("ExpeditionFloor")==2,"Floor III stays locked at Dungeoneering 5")
local dais=world:FindFirstChild("Observatory Floor V",true)
check(dais and dais:GetAttribute("RequiredLevel")==30,"floor dais advertises its requirement")
-- Matchmaking pad: 10 s window, level filter, off-pad players stay behind.
local pad=world:FindFirstChild("Matchmaking pad",true)
check(pad~=nil,"matchmaking pad built at the gate")
onPad(d) onPad(e,3) onPad(g,-3)
rootOf(f).Position=gate.Position+r.Vector3.new(0,0,30)
signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(d)
check(pad:GetAttribute("LobbyFloor")==2,"pad shows the forming floor")
check(caption.Text:find("OBSERVATORY FLOOR II",1,true)~=nil,"caption announces the forming floor")
now+=5
heartbeat:Fire(0)
check(rootOf(d).Position.Z==-121,"run waits for the pad window")
now+=5
heartbeat:Fire(0)
check(rootOf(d).Position.Z==1824 and rootOf(g).Position.Z==1824,"qualified pad players launch together")
check(rootOf(e).Position.Z~=1824 and noticeOf(e):find("Dungeoneering 5",1,true)~=nil,"under-levelled pad player is turned away")
check(rootOf(f).Position.Z~=1824,"player off the pad is not pulled in")
check(artCore:GetAttribute("Floor")==2 and artCore:GetAttribute("BossName")=="Lens Tyrant","Floor II boss in the arena")
check(caption.Text:find("in order",1,true)~=nil,"Floor II caption asks for ordered tuning")
signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(e)
check(noticeOf(e):find("party is inside",1,true)~=nil,"gate refuses a second run while one is active")
-- Floor II: ordered prisms; a wrong prism is a mistake and resets the sequence.
local order=ordered()
for i,prism in order do check(prism.Parent:GetAttribute("TuneOrder")==i,"prism shows its tuning order "..i) end
tune(d,order[2])
check(caption.Text:find("0 / 3",1,true)~=nil and noticeOf(d):find("Wrong resonance",1,true)~=nil,"out-of-order tuning is rejected")
tune(g,order[1])
tune(d,order[3])
check(caption.Text:find("0 / 3",1,true)~=nil,"second wrong tuning collapses progress")
tune(g,order[1]) tune(g,order[2]) tune(g,order[3])
check(caption.Text:find("SENTINEL HALL",1,true)~=nil,"correct order opens the hall")
-- Scaling: Floor II guardians have 11 HP and hit back for 9.
rootOf(d).Position=world:FindFirstChild("Sentinel 1",true).Position
now+=3
signals[promptFor("Sentinel 1","Strike guardian")]:Fire(d)
check(hums[d].Health==91,"Floor II guardian counter-hit scales to 9")
guardiansDown(d)
check(caption.Text:find("LENS TYRANT  •  21 / 21",1,true)~=nil,"Floor II core HP scales to 21")
-- Refraction Ring: telegraphed, hits the outer floor, safe beside the core.
at(d) at(g,r.Vector3.new(20,0,0)) heal(d) heal(g)
heartbeat:Fire(4)
local warn=world:FindFirstChild("Pulse radius",true)
check(warn.Transparency==0.25 and artCore:GetAttribute("Telegraph")=="Refraction Ring","ring attack is telegraphed")
check(warn:GetAttribute("SafeRadius")==10,"ring telegraph marks the safe inner radius")
check(caption.Text:find("Close in",1,true)~=nil,"caption explains how to dodge the ring")
heartbeat:Fire(2)
check(hums[d].Health==100 and hums[g].Health==76,"ring spares the inside and hits the outside for 24")
check(warn.Transparency==1,"telegraph clears after the strike")
coreDown(d)
at(g,r.Vector3.new(20,0,0))
check(rewards[d]==1 and rewards[g]==1,"Floor II party both credited")
check(payloads[d].floor==2 and payloads[d].mistakes==2 and payloads[d].deaths==0 and payloads[d].partySize==2,"payload reports floor, mistakes, deaths and party")
check(payloads[d].score==270 and payloads[d].grade=="S","two mistakes grade S on a fast clear")
check(payloads[g].damageShare==0 and payloads[d].damageShare==1,"payload damage shares")
check(d:GetAttribute("DungeonResult"):find("Floor II • S",1,true)~=nil,"result summary for the UI")

-- Floor III: core shield phases + Starfall (meteor) telegraph, solo.
local h=player()
levels[h]=12
use(h,"Observatory Floor III","Select floor")
use(h,"ExpeditionGate","Enter expedition")
launch()
tuneInOrder(h)
guardiansDown(h)
check(caption.Text:find("GYRE ORACLE  •  33 / 33",1,true)~=nil,"Floor III core HP 33")
local firstOrder=pylons[1].Parent:GetAttribute("TuneOrder")
for _=1,12 do strike(h,"Eclipse Heart","Strike core") end
check(artCore:GetAttribute("BossHealth")==21 and caption.Text:find("SHIELDED",1,true)~=nil,"shield rises at 66% HP")
check(pylons[1].Parent:GetAttribute("TuneOrder")~=firstOrder,"shield phase reshuffles the prism order")
strike(h,"Eclipse Heart","Strike core")
check(artCore:GetAttribute("BossHealth")==21,"shielded core ignores strikes")
check(artCore:GetAttribute("VisualState")=="Shielded","shielded core art")
tuneInOrder(h)
check(caption.Text:find("SHIELDED",1,true)==nil,"retuning breaks the shield")
for _=1,11 do strike(h,"Eclipse Heart","Strike core") end
check(artCore:GetAttribute("BossHealth")==10 and caption.Text:find("SHIELDED",1,true)~=nil,"second shield at 33% HP")
tuneInOrder(h)
at(h) heal(h)
heartbeat:Fire(4)
check(artCore:GetAttribute("Telegraph")=="Starfall" and warn.Position.X==rootOf(h).Position.X and warn.Position.Z==rootOf(h).Position.Z,"Starfall marks the delver")
at(h,r.Vector3.new(15,0,0))
heartbeat:Fire(2)
check(hums[h].Health==100,"moving off the mark dodges Starfall")
at(h) heal(h)
heartbeat:Fire(6)
check(hums[h].Health==70,"standing on the mark takes 30")
coreDown(h)
check(rewards[h]==1 and payloads[h].floor==3 and payloads[h].partySize==1,"solo Floor III clear credited")

-- Floor IV: wisp waves ward the boss.
local i4=player()
levels[i4]=20
use(i4,"Berserk oath","Choose role")
use(i4,"Observatory Floor IV","Select floor")
use(i4,"ExpeditionGate","Enter expedition")
launch()
tuneInOrder(i4)
guardiansDown(i4)
check(#wisps()==0,"no wisps before the boss phase ticks")
at(i4) heal(i4)
heartbeat:Fire(0.1)
check(#wisps()==2 and wisps()[1]:GetAttribute("AddHealth")==16,"first wave: two 16 HP wisps")
check(caption.Text:find("WARDED",1,true)~=nil,"caption explains the ward")
strike(i4,"Eclipse Heart","Strike core")
check(artCore:GetAttribute("BossHealth")==48,"warded core ignores strikes")
for _=1,40 do
	local list=wisps()
	if #list==0 then break end
	heal(i4)
	rootOf(i4).Position=list[1].Position
	now+=1
	for _,obj in list[1]:GetChildren() do if obj:IsA("ProximityPrompt") then signals[obj]:Fire(i4) end end
end
check(#wisps()==0 and caption.Text:find("WARDED",1,true)==nil,"slaying the wisps lifts the ward")
strike(i4,"Eclipse Heart","Strike core")
check(artCore:GetAttribute("BossHealth")==46,"Berserk strikes the unwarded core")
at(i4) heal(i4)
heartbeat:Fire(20)
check(#wisps()==2,"next wave after 20 s")
check(hums[i4].Health==66,"Eclipse Sweep hits within 20 studs for 34")
players.PlayerRemoving:Fire(i4)
check(#wisps()==0 and caption.Text:find("0 / 3",1,true)~=nil,"abandoned run clears wisps and resets")

-- Floor V: enrage timer and the alternating Total Eclipse.
local k=player()
levels[k]=30
use(k,"Observatory Floor V","Select floor")
use(k,"ExpeditionGate","Enter expedition")
launch()
check(artCore:GetAttribute("BossName")=="Umbral Astrarch","Floor V boss")
tuneInOrder(k)
guardiansDown(k)
check(artCore:GetAttribute("Enraged")==false,"not enraged before the timer")
now+=240
at(k) heal(k)
heartbeat:Fire(0.1)
check(artCore:GetAttribute("Enraged")==true and caption.Text:find("ENRAGED",1,true)~=nil,"enrage after 240 s")
check(#wisps()==3 and wisps()[1]:GetAttribute("AddHealth")==28,"Floor V waves: three 28 HP wisps")
heartbeat:Fire(1)
check(artCore:GetAttribute("Telegraph")=="Total Eclipse" and warn:GetAttribute("SafeRadius")==0,"enraged tempo telegraphs the pulse half")
heartbeat:Fire(1.4)
check(hums[k].Health==20,"enraged pulse deals double damage (80)")
heal(k)
heartbeat:Fire(1)
check(warn:GetAttribute("SafeRadius")==10,"Total Eclipse alternates into the ring")
use(k,"Return arch","Leave expedition")
check(rootOf(k).Position.Z==-116 or rootOf(k).Position.Z==-121,"leaving returns to the gate")
check(caption.Text:find("0 / 3",1,true)~=nil and #wisps()==0,"leaving resets Floor V")

-- Ironman: credited only when solo or >= 30% of party damage.
local iron=player()
local ally=player()
irons[iron]=true
use(ally,"Berserk oath","Choose role")
clearPad() onPad(iron) onPad(ally,2)
signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(iron)
launch()
check(rootOf(iron).Position.Z==1824 and rootOf(ally).Position.Z==1824,"Ironman joins a mixed party")
for _,prism in pylons do tune(iron,prism) end
for _=1,4 do strike(iron,"Sentinel 1","Strike guardian") end
guardiansDown(ally)
at(iron)
coreDown(ally)
at(iron)
check(rewards[ally]==1,"partner credited")
check(rewards[iron]==nil and noticeOf(iron):find("Ironman",1,true)~=nil,"Ironman under 30% damage is not credited")

-- Clear cooldown (Berserk partner re-clears at once): a second credited clear needs 90 s.
clearPad() use(ally,"ExpeditionGate","Enter expedition")
launch()
for _,prism in pylons do tune(ally,prism) end
guardiansDown(ally)
coreDown(ally)
check(rewards[ally]==1 and noticeOf(ally):find("cooldown",1,true)~=nil,"instant re-clear is not credited")
clearPad() use(iron,"ExpeditionGate","Enter expedition")
launch()
for _,prism in pylons do tune(iron,prism) end
guardiansDown(iron)
coreDown(iron)
check(rewards[iron]==1 and payloads[iron].partySize==1 and payloads[iron].damageShare==1,"solo Ironman clear credited")
now+=90
clearPad() use(ally,"ExpeditionGate","Enter expedition")
launch()
for _,prism in pylons do tune(ally,prism) end
hums[ally].Health=0
heartbeat:Fire(0)
heartbeat:Fire(0)
heal(ally)
guardiansDown(ally)
now+=200
coreDown(ally)
check(rewards[ally]==2,"credited again after the cooldown")
check(payloads[ally].deaths==1,"a fall counts once")
check(payloads[ally].seconds>180 and payloads[ally].score<280 and payloads[ally].grade~="S+","slow clear with a death grades lower")

-- Party cap: at most five delvers launch from the pad.
local crowd={}
clearPad()
for n=1,6 do crowd[n]=player() onPad(crowd[n],n-3) end
signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(crowd[1])
launch()
local inside=0
for n=1,6 do if rootOf(crowd[n]).Position.Z==1824 then inside+=1 end end
check(inside==Data.Dungeons.maxParty,"pad admits five delvers")
check(rootOf(crowd[6]).Position.Z~=1824 and noticeOf(crowd[6]):find("full",1,true)~=nil,"sixth delver told the party is full")
for n=1,6 do players.PlayerRemoving:Fire(crowd[n]) end
check(caption.Text:find("0 / 3",1,true)~=nil,"crowd leaving resets the run")
local runChecks=checks-baseChecks-dataChecks
print("Expedition QA passed "..checks.." behavioral checks ("..baseChecks.." encounter, "..dataChecks.." dungeon rules, "..runChecks.." dungeon runs).")
