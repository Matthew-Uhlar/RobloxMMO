-- Behavioral tests against the production script. Lune supplies the Luau VM;
-- Roblox services are replaced with deterministic, failure-injectable doubles.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f) table.insert(listeners, f) end,
		Fire = function(_, ...) for _, f in listeners do f(...) end end,
	}
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local clock, utc = 10, 1500000000
local function advance(seconds) clock += seconds; utc += seconds end
local data, injectedFailure = {}, false
local delayedProfileAck = nil
local repeatMarketTransform=false
local db = {}
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	if repeatMarketTransform and key:match("^market") then op(copy(data[key])) end
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	if injectedFailure and key:match("^market") then
		injectedFailure=false
		error("Injected lost acknowledgement after durable commit")
	end
	if delayedProfileAck and key==delayedProfileAck then
		delayedProfileAck=nil
		advance(181)
	end
	return copy(data[key])
end
-- Shared Depth modules load exactly as in Roblox: ReplicatedStorage markers resolve
-- through an environment require. Progression's own script-relative require is nil here.
local function loadModule(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = loadModule("shared/GameData.lua")
local Progression = loadModule("shared/Progression.lua", {script = nil})
Progression.useData(Data)
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = Progression}
-- Deterministic rolls: queued values first, then a high default (no crits,
-- no fortune procs, only guaranteed drops) so legacy expectations stay exact.
local rolls, defaultRoll = {}, 0.999
local function nextRoll()
	if #rolls > 0 then return table.remove(rolls, 1) end
	return defaultRoll
end
local seeds = {}
local services = {
	Players = {PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end},
	ProximityPromptService = {PromptTriggered=signal()},
	ReplicatedStorage = {WaitForChild=function(_, name) return assert(markers[name], name) end},ServerStorage={},
	DataStoreService = {GetDataStore=function() return db end},
	HttpService = {GenerateGUID=function() return "test-instance" end},
	RunService = {IsStudio=function() return false end},
}
local objects,allObjects = {},{}
local workspace = {GetAttribute=function(self,key) return self[key] end}
local env = {
	game={GetService=function(_,name) return services[name] end, BindToClose=function() end},
	workspace=workspace,
	Instance={new=function(class)
		local instance={Event=signal(),FireClient=function(_,player,state) player.last=state end}
		objects[class]=instance
		table.insert(allObjects,instance)
		return instance
	end},
	os={clock=function() return clock end,time=function() return math.floor(utc) end},
	require=function(target) return assert(modules[target], "unexpected require") end,
	Random={new=function(seed)
		table.insert(seeds, seed)
		return {NextNumber=function() return nextRoll() end}
	end},
	task={
		spawn=function(f,...) assert(coroutine.resume(coroutine.create(f),...)) end,
		defer=function(f,...) f(...) end,
		wait=function() coroutine.yield() end,delay=function() end,
	},
}
local source=fs.readFile("server.server.lua"):gsub("^\239\187\191","")
luau.load(source,{environment=env,injectGlobals=true})()
local function player(id)
	local humanoid={Health=100,MaxHealth=100,Died=signal(),TakeDamage=function(self,n) self.Health-=n end}
	local root={Position=Vector3.zero}
	local p={GetAttribute=function(self,key) return self[key] end,SetAttribute=function(self,key,value) self[key]=value end,UserId=id,Parent=true,CharacterAdded=signal(),Kick=function(self,why) self.kicked=why end}
	p.Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end,
		WaitForChild=function() return humanoid end}
	services.Players.PlayerAdded:Fire(p)
	return p
end
local function cmd(p,verb,item)
	advance(1)
	return objects.RemoteFunction.OnServerInvoke(p,verb,item)
end
local function node(verb,item,distance,owner,region)
	return {Enabled=true,MaxActivationDistance=10,GetAttribute=function(_,key)
		return ({IsleAction=verb,IsleItem=item,OwnerUserId=owner,IsleRegion=region})[key]
	end,FindFirstAncestorWhichIsA=function() return {Position=Vector3.new(distance or 0,0,0)} end}
end
local function use(p,n)
	advance(1)
	services.ProximityPromptService.PromptTriggered:Fire(n,p)
	return p.last
end
local checks=0
local function eq(actual,expected,case)
	assert(actual==expected,case.." expected "..tostring(expected)..", got "..tostring(actual))
	checks+=1
end
local a,b,c=player(1),player(2),player(3)
local ore,wood=node("gather","Ore"),node("gather","Timber")
eq(cmd(a,"state").levels.Mining,1,"initial skill")
eq(cmd(a,"gather","Ore").items.Ore,nil,"remote harvest denied")
use(a,node("gather","Ore",50))
use(a,node("gather","Ore",0,99))
eq(cmd(a,"state").items.Ore,nil,"distance and owner validation")
for _=1,3 do use(a,ore) end
for _=1,2 do use(a,wood) end
eq(cmd(a,"craft","Pickaxe").items.Pickaxe,1,"craft recipe")
eq(cmd(a,"state").collection.Ore,3,"collection survives crafting")
eq(use(a,ore).items.Ore,2,"pickaxe yield")
workspace.FestivalResource="Ore"
eq(use(a,ore).items.Ore,5,"festival yield")
workspace.FestivalResource=nil
eq(cmd(a,"ironman").ironman,false,"late Ironman denied")
for _=1,5 do use(a,wood) end
eq(cmd(a,"worker").worker,true,"worker construction")
advance(120*130)
-- Model a server autosave/heartbeat interval by leaving before our simulated jump.
-- A cold profile with the same earned goods exercises real rejoin accounting.
services.Players.PlayerRemoving:Fire(a)
a=player(1)
services.Players.PlayerRemoving:Fire(b)
services.Players.PlayerRemoving:Fire(c)
b=player(2)
c=player(3)
eq(cmd(a,"state").workerReady,120,"offline worker cap")
local payout=cmd(a,"claim")
eq(payout.items.Ore,122,"worker payout")
-- Depth rewards: Woodcutting 2 (+50), Mining 2-5 (+350), Ore collection tiers 1-2 (+250).
eq(payout.coins,650,"worker payout crosses level and collection reward thresholds")
eq(payout.levels.Mining,5,"worker XP levels Mining on the OSRS curve")
eq(payout.depth.collections.Ore.tier,2,"worker output advances collection tier")
local aBonus=payout.coins
eq(cmd(a,"claim").items.Ore,122,"no double claim")
eq(cmd(c,"ironman").ironman,true,"early Ironman allowed")
eq(cmd(c,"buy","Ore").message,"Ironman journals cannot use the player exchange.","Ironman exclusion")
for _=1,4 do use(b,ore) end
eq(cmd(b,"sell","Ore").coins,16,"merchant payout")
eq(cmd(b,"deposit").bank,16,"deposit")
b.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
eq(cmd(b,"withdraw").coins,16,"bank survives death")
eq(cmd(a,"list","Ore").items.Ore,119,"listing reserves bundle")
injectedFailure=true
eq(cmd(b,"buy","Ore").coins,1,"purchase reservation on lost acknowledgement")
services.Players.PlayerRemoving:Fire(b)
b=player(2)
eq(cmd(b,"state").items.Ore,3,"replayed purchase delivered once")
eq(cmd(b,"state").coins,1,"replayed purchase charged once")
eq(cmd(a,"proceeds","Ore").coins,aBonus+15,"seller credited exactly once")
eq(cmd(a,"proceeds","Ore").coins,aBonus+15,"proceeds cannot repeat")
cmd(a,"list","Ore")
eq(cmd(a,"cancel","Ore").items.Ore,119,"cancel restores escrow")
eq(cmd(a,"buy","Ore").coins,aBonus+15,"empty market reimburses")
local boss=node("fight","Warden")
use(a,boss)
for _=1,5 do use(b,boss) end
eq(cmd(a,"state").items.Shard,1,"cooperative fight credit")
eq(cmd(b,"state").items.Shard,1,"second fighter credit")
use(c,boss)
eq(cmd(c,"state").items.Shard,nil,"Ironman independent encounter")
objects.BindableEvent.Event:Fire(a)
local cleared=cmd(a,"state")
eq(cleared.items.Stormglass,1,"expedition reward")
eq(cleared.levels.Combat,2,"Warden and expedition XP reach Combat 2 (83 XP)")
eq(cleared.coins,aBonus+15+15+35+50,"Combat 2 pays its one-time level reward")
aBonus+=50
local leaseCopy=copy(data.p1)
data.p1.owner="other-server"
data.p1.expires=utc+200
local duplicate=player(1)
eq(duplicate.kicked~=nil,true,"foreign lease rejects duplicate session")
data.p1=leaseCopy
local builder=player(20)
eq(cmd(builder,"decorate","Lanterns").decorations.Lanterns,nil,"unfunded decoration denied")
for _=1,5 do use(builder,wood) end
eq(cmd(builder,"decorate","Lanterns").decorations.Lanterns,true,"lantern construction")
eq(cmd(builder,"state").items.Timber,0,"decoration charges materials")
for _=1,5 do use(builder,wood) end
cmd(builder,"decorate","Lanterns")
eq(cmd(builder,"state").items.Timber,5,"duplicate decoration does not charge")
services.Players.PlayerRemoving:Fire(builder)
builder=player(20)
eq(cmd(builder,"state").decorations.Lanterns,true,"decoration survives rejoin")
local novice=player(21)
eq(cmd(novice,"craft","Blade").items.Blade,nil,"collection recipe locked")
for _=1,6 do use(novice,ore) end
for _=1,3 do use(novice,wood) end
eq(cmd(novice,"craft","Blade").items.Blade,1,"collection recipe unlock")
eq(cmd(novice,"state").collection.Ore,6,"recipe consumption preserves lifetime milestone")
eq(cmd(builder,"quest").quest.stage,1,"incomplete quest cannot advance")
eq(cmd(a,"quest").coins,aBonus+75,"first quest pays once")
eq(cmd(a,"quest").xp.Smithing,44,"second quest XP reward")
eq(cmd(a,"quest").coins,aBonus+90,"worker contract reward")
eq(cmd(a,"quest").items.Tonic,2,"combat contract reward")
eq(cmd(a,"quest").coins,aBonus+120,"expedition contract reward")
eq(cmd(a,"quest").coins,aBonus+120,"completed chain cannot pay again")
services.Players.PlayerRemoving:Fire(a)
a=player(1)
eq(cmd(a,"state").quest.stage,6,"existing contracts stay claimed and reveal new charter on rejoin")
eq(cmd(a,"quest").coins,aBonus+120,"rejoin cannot reclaim")
eq(cmd(novice,"craft","Stormblade").items.Stormblade,nil,"Stormblade milestone blocks craft")
-- Exercise older version-one profiles where decoration and quest fields were absent.
services.Players.PlayerRemoving:Fire(novice)
data.p21.profile.decorations=nil
data.p21.profile.questCompleted=nil
novice=player(21)
eq(cmd(novice,"state").quest.stage,1,"old save receives quest defaults")
eq(type(cmd(novice,"state").decorations),"table","old save receives decoration defaults")
-- Seed a realistic earned-material save to exercise the late recipe without
-- duplicating dozens of combat cycles in this service regression.
services.Players.PlayerRemoving:Fire(a)
data.p1.profile.items.Shard=3
a=player(1)
eq(cmd(a,"craft","Stormblade").items.Stormblade,1,"Stormblade crafted after milestones")
eq(cmd(a,"state").items.Stormglass,0,"Stormblade consumes expedition resource")
-- Depth stat sheet: Combat grants Strength/Crit (not Health); health is shared computeStats.
local armed=cmd(a,"state")
eq(armed.stats.maxHealth,armed.depth.stats.health,"legacy maxHealth mirrors shared stat sheet")
eq(armed.stats.maxHealth,100,"Combat levels raise strength rather than health")
eq(armed.depth.stats.strength,2,"Combat 2 and Woodcutting 2 each grant one strength")
eq(armed.depth.stats.weapon,nil,"legacy Stormblade fallback is gated by Combat 5")
eq(a.Character:FindFirstChildOfClass("Humanoid").MaxHealth,100,"stats applied to spawned humanoid")
local worker=player(30)
for _=1,5 do use(worker,wood) end
for _=1,3 do use(worker,ore) end
cmd(worker,"worker")
services.Players.PlayerRemoving:Fire(worker)
advance(301)
worker=player(30)
local switched=cmd(worker,"workerResource","Timber")
eq(switched.items.Ore,2,"switch claims old resource before change")
eq(switched.xp.Mining,42,"old-resource claim grants mining XP")
eq(switched.workerResource,"Timber","worker assignment changes")
eq(switched.workerReady,0,"switch starts new cycle")
eq(cmd(worker,"claim").items.Timber,0,"switch does not duplicate accrued output")
advance(60)
cmd(worker,"workerResource","Timber")
advance(60)
local timber=cmd(worker,"claim")
eq(timber.items.Timber,1,"same selection preserves progress")
eq(timber.xp.Woodcutting,63,"timber worker XP")
eq(cmd(worker,"workerResource","Shard").workerResource,"Timber","invalid selection denied")
cmd(worker,"workerResource","Herb")
services.Players.PlayerRemoving:Fire(worker)
advance(121)
worker=player(30)
eq(cmd(worker,"claim").items.Herb,1,"assignment and output survive rejoin")
eq(cmd(worker,"state").xp.Farming,3,"herb worker XP")
cmd(worker,"workerResource","Fish")
services.Players.PlayerRemoving:Fire(worker)
advance(120*130)
worker=player(30)
local fish=cmd(worker,"claim")
eq(fish.items.Fish,120,"selected resource offline capacity")
eq(fish.xp.Fishing,360,"selected resource capped XP")
eq(cmd(worker,"claim").items.Fish,120,"selected resource cannot double claim")
local scholar=player(40)
eq(cmd(scholar,"enchant").enchantRank,0,"enchantment requires weapon")
eq(cmd(scholar,"feed").companionBond,0,"feeding requires fish")
services.Players.PlayerRemoving:Fire(scholar)
data.p40.profile.items={Blade=1,Herb=16,Shard=6,Fish=12}
data.p40.profile.collection={Herb=16}
data.p40.profile.xp.Alchemy=nil
data.p40.profile.xp.Enchanting=nil
data.p40.profile.xp.Dungeoneering=nil
data.p40.profile.xp.Taming=nil
scholar=player(40)
eq(cmd(scholar,"state").xp.Taming,0,"old save migrates taming")
eq(cmd(scholar,"state").xp.Enchanting,0,"old save migrates enchanting")
eq(cmd(scholar,"craft","Tonic").xp.Alchemy,24,"tonic trains alchemy")
eq(cmd(scholar,"state").xp.Smithing,0,"tonic does not train smithing")
objects.BindableEvent.Event:Fire(scholar)
eq(cmd(scholar,"state").xp.Dungeoneering,60,"expedition trains dungeoneering")
for _=1,3 do cmd(scholar,"enchant") end
local enchanted=cmd(scholar,"enchant")
eq(enchanted.enchantRank,3,"enchant rank capped")
eq(enchanted.items.Shard,0,"enchant material charged")
eq(enchanted.xp.Enchanting,90,"enchant XP capped with rank")
eq(enchanted.stats.enchantDamage,9,"enchant damage bonus")
for _=1,5 do cmd(scholar,"feed") end
local bonded=cmd(scholar,"feed")
eq(bonded.companionBond,5,"bond capped")
eq(bonded.items.Fish,2,"capped feeding does not consume")
eq(bonded.xp.Taming,100,"feeding XP")
eq(bonded.stats.maxHealth,110,"bond health bonus on the Depth stat sheet")
services.Players.PlayerRemoving:Fire(scholar)
scholar=player(40)
eq(cmd(scholar,"state").companionBond,5,"bond survives rejoin")
eq(cmd(scholar,"state").enchantRank,3,"enchantment survives rejoin")
-- Migrate a pre-fleet worker without discarding its offline production.
local fleet=player(50)
services.Players.PlayerRemoving:Fire(fleet)
data.p50.profile.worker=true
data.p50.profile.workers=nil
data.p50.profile.workerResource="Fish"
data.p50.profile.lastClaim=utc-240
data.p50.profile.items={Timber=100,Ore=100}
fleet=player(50)
eq(cmd(fleet,"state").workers[1].resource,"Fish","legacy worker migrates assignment")
eq(cmd(fleet,"workerClaim","1").items.Fish,2,"legacy worker migrates accrued production")
eq(#cmd(fleet,"workerBuild","3").workers,1,"worker slots must be sequential")
eq(#cmd(fleet,"workerBuild","2.5").workers,1,"fractional worker rejected")
eq(#cmd(fleet,"workerBuild","4").workers,1,"worker capacity enforced")
eq(cmd(fleet,"workerBuild","2").items.Timber,90,"second worker cost")
eq(cmd(fleet,"workerBuild","2").items.Timber,90,"duplicate worker cannot charge")
eq(cmd(fleet,"workerBuild","3").items.Ore,85,"third worker cost")
eq(cmd(fleet,"workerAssign","2:Timber").workers[2].resource,"Timber","second worker assignment")
eq(cmd(fleet,"workerAssign","3:Herb").workers[3].resource,"Herb","third worker assignment")
eq(cmd(fleet,"workerAssign","2:Shard").workers[2].resource,"Timber","invalid resource rejected")
eq(cmd(fleet,"workerUpgrade","2").workers[2].interval,90,"tier two interval")
eq(cmd(fleet,"workerUpgrade","2").workers[2].capacity,360,"tier three capacity follows Data.WorkerTiers")
eq(cmd(fleet,"workerUpgrade","2").workers[2].tier,3,"tier four upgrade requires refined ingots")
eq(cmd(fleet,"state").items.Timber,50,"unaffordable upgrade does not charge")
services.Players.PlayerRemoving:Fire(fleet)
advance(60*300)
fleet=player(50)
eq(cmd(fleet,"state").workers[2].tier,3,"worker tier survives rejoin")
eq(cmd(fleet,"state").workers[1].ready,120,"tier one independent cap")
eq(cmd(fleet,"workerClaim","2").items.Timber,350,"tier three offline payout at 60 second interval")
eq(cmd(fleet,"workerClaim","2").items.Timber,350,"fleet cannot double claim")
eq(cmd(fleet,"workerClaim","3").items.Herb,120,"third worker independent resource")
eq(cmd(fleet,"state").workers[1].ready,120,"other worker claim preserves pending output")
eq(cmd(fleet,"workerAssign","1:Ore").items.Fish,122,"reassignment claims previous resource")
eq(cmd(fleet,"state").workers[1].ready,0,"reassignment starts new cycle")
advance(61)
cmd(fleet,"workerAssign","1:Ore")
advance(60)
eq(cmd(fleet,"workerClaim","1").items.Ore,71,"same assignment preserves partial cycle")
-- Hunt rewards require an accepted contract and eligible living participants.
local hunter=player(60)
services.Players.PlayerRemoving:Fire(hunter)
data.p60.profile.kills=10
hunter=player(60)
eq(cmd(hunter,"slayerClaim").slayer.completed,0,"inactive hunt cannot claim")
eq(cmd(hunter,"slayerStart").slayer.target,2,"first hunt target")
eq(cmd(hunter,"state").slayer.progress,0,"historical kills do not fill new hunt")
local function kill(p)
	local encounter=node("fight","Warden")
	p.Character:FindFirstChildOfClass("Humanoid").Health=100
	for _=1,6 do use(p,encounter) end
end
kill(hunter)
eq(cmd(hunter,"slayerStart").slayer.progress,1,"repeated start preserves hunt progress")
eq(cmd(hunter,"slayerClaim").slayer.completed,0,"unfinished hunt cannot claim")
services.Players.PlayerRemoving:Fire(hunter)
hunter=player(60)
eq(cmd(hunter,"state").slayer.progress,1,"hunt progress survives rejoin")
kill(hunter)
eq(cmd(hunter,"state").slayer.ready,true,"hunt completion ready")
local before=cmd(hunter,"state").coins
eq(cmd(hunter,"slayerClaim").coins,before+20+50,"first hunt reward plus Combat 2 level reward")
eq(cmd(hunter,"slayerClaim").coins,before+20+50,"hunt cannot claim twice")
eq(cmd(hunter,"slayerStart").slayer.target,4,"second hunt target")
for _=1,4 do kill(hunter) end
eq(cmd(hunter,"slayerClaim").slayer.tier,3,"third hunt unlocked")
cmd(hunter,"slayerStart")
for _=1,6 do kill(hunter) end
eq(cmd(hunter,"slayerClaim").slayer.completed,3,"third hunt complete")
eq(cmd(hunter,"slayerStart").slayer.target,6,"top hunt repeatable")
local absent,finisher=player(61),player(62)
cmd(absent,"slayerStart")
local shared=node("fight","Warden")
use(absent,shared)
absent.Character:FindFirstChildOfClass("Humanoid").Health=0
for _=1,6 do use(finisher,shared) end
eq(cmd(absent,"state").kills,0,"dead contributor excluded from Warden rewards")
eq(cmd(absent,"state").slayer.progress,0,"dead contributor excluded from hunt progress")
absent.Character:FindFirstChildOfClass("Humanoid").Health=100
finisher.Character:FindFirstChildOfClass("Humanoid").Health=100
shared=node("fight","Warden")
use(absent,shared)
absent.Character:FindFirstChild("HumanoidRootPart").Position=Vector3.new(100,0,0)
for _=1,6 do use(finisher,shared) end
eq(cmd(absent,"state").kills,0,"distant contributor excluded from Warden rewards")
eq(cmd(absent,"state").slayer.progress,0,"distant contributor excluded from hunt progress")
local upgrading=player(63)
services.Players.PlayerRemoving:Fire(upgrading)
data.p63.profile.worker=true
data.p63.profile.workers={{resource="Fish",tier=1,lastClaim=utc-240}}
data.p63.profile.items={Timber=30,Ore=30}
upgrading=player(63)
eq(cmd(upgrading,"workerUpgrade","1").items.Fish,2,"upgrade collects earned old-tier output")
eq(cmd(upgrading,"state").workers[1].ready,0,"upgrade cannot retroactively accelerate output")
eq(cmd(upgrading,"state").workers[1].capacity,240,"tier two capacity")
-- Delayed acknowledgements must not extend the durable session lease.
delayedProfileAck="p70"
local lateOpen=player(70)
eq(cmd(lateOpen,"slayerStart").message,"Waiting for journal sync.","delayed open does not invent fresh lease")
eq(use(lateOpen,ore).items.Ore,nil,"expired opened lease cannot harvest")
local lateSave=player(71)
for _=1,4 do use(lateSave,ore) end
cmd(lateSave,"sell","Ore")
delayedProfileAck="p71"
local stalled=cmd(lateSave,"buy","Ore")
eq(stalled.message,"Market waiting for a journal save. Try again.","expired reservation save blocks market")
eq(data.market_v1_Ore.receipts["71"],nil,"expired reservation never reaches market")
eq(cmd(lateSave,"slayerStart").message,"Waiting for journal sync.","delayed save preserves durable lease deadline")
services.Players.PlayerRemoving:Fire(lateSave)
lateSave=player(71)
eq(cmd(lateSave,"state").coins,16,"expired reservation recovered without losing coins")
local cooperator=player(72)
eq(objects.BindableFunction.OnInvoke(cooperator,false).ready,true,"co-op eligibility requires loaded journal")
eq(objects.BindableFunction.OnInvoke(cooperator,true).ready,true,"co-op charter seals with durable save")
eq(cmd(cooperator,"ironman").ironman,false,"co-op participation seals normal mode")
eq(objects.BindableFunction.OnInvoke(lateOpen,false).ready,false,"co-op rejects expired personal lease")
eq(fleet:GetAttribute("Worker2Tier"),3,"worker tier published to world")
eq(fleet:GetAttribute("Worker3Resource"),"Herb","worker assignment published to world")
-- Rank 1: exercise the entire new material/production/equipment chain from a
-- fresh journal, rather than seeding the successful progression path.
local smith=player(80)
local aether=node("gather","Aetherite")
eq(use(smith,aether).items.Aetherite,nil,"Aetherite locked before Mining 3")
eq(cmd(smith,"state").xp.Mining,0,"locked node awards no XP")
eq(cmd(smith,"gather","Aetherite").items.Aetherite,nil,"remote Aetherite harvest denied")
for _=1,3 do use(smith,ore) end
for _=1,2 do use(smith,wood) end
cmd(smith,"craft","Pickaxe")
for _=1,11 do use(smith,ore) end
-- OSRS curve: Mining 3 needs 174 XP (the retired curve needed 160).
eq(cmd(smith,"state").levels.Mining,2,"168 XP is still Mining 2 on the OSRS curve")
eq(use(smith,aether).items.Aetherite,nil,"Aetherite stays locked one harvest short of 174 XP")
use(smith,ore)
eq(cmd(smith,"state").levels.Mining,3,"ordinary Ore reaches advanced material gate")
eq(use(smith,aether).items.Aetherite,1,"Mining 3 unlocks Aetherite")
eq(cmd(smith,"state").xp.Mining,198,"Aetherite grants 18 Mining XP")
eq(cmd(smith,"craft","AetherIngot").items.Aetherite,1,"Smithing gate spends no material")
eq(cmd(smith,"state").xp.Smithing,24,"locked refinement awards no XP")
for _=1,20 do use(smith,wood) end
for _=1,9 do cmd(smith,"craft","AlloyIngot") end
eq(cmd(smith,"state").levels.Smithing,2,"nine refinements (168 XP) remain Smithing 2")
cmd(smith,"craft","AlloyIngot")
eq(cmd(smith,"state").items.AlloyIngot,10,"basic refining is repeatable")
eq(cmd(smith,"state").xp.Smithing,184,"repeatable refining bridges Smithing progression")
eq(cmd(smith,"state").levels.Smithing,3,"refining reaches Smithing 3")
for _=1,13 do use(smith,aether) end
for _=1,7 do cmd(smith,"craft","AetherIngot") end
eq(cmd(smith,"state").items.AetherIngot,7,"advanced refining is repeatable")
eq(cmd(smith,"state").items.Aetherite,0,"advanced refining consumes raw mineral")
eq(cmd(smith,"state").items.AlloyIngot,3,"advanced refining consumes base ingots")
eq(cmd(smith,"state").collection.Aetherite,14,"refining preserves lifetime collection")
eq(cmd(smith,"craft","ReinforcedPickaxe").items.ReinforcedPickaxe,1,"reinforced tool crafted from progression")
eq(cmd(smith,"state").items.Pickaxe,0,"reinforced tool consumes basic tool")
eq(cmd(smith,"state").items.AetherIngot,4,"reinforced tool cost")
eq(cmd(smith,"craft","ReinforcedPickaxe").items.AetherIngot,4,"duplicate tool does not charge")
eq(cmd(smith,"craft","Pickaxe").items.Pickaxe,0,"stronger tool prevents redundant downgrade craft")
local priorOre=cmd(smith,"state").items.Ore
eq(use(smith,ore).items.Ore,priorOre+4,"reinforced tool applies mutually exclusive Ore bonus")
eq(use(smith,aether).items.Aetherite,2,"reinforced tool improves Aetherite yield")
-- Upgrading before claiming the original tool contract must not strand it.
cmd(smith,"quest")
eq(cmd(smith,"state").quest.ready,true,"upgraded pickaxe satisfies original tool contract")
for _=1,4 do use(smith,node("gather","Herb")) end
local plated=cmd(smith,"craft","Skyplate")
eq(plated.items.Skyplate,1,"armor crafted from progression")
eq(plated.items.AetherIngot,0,"armor consumes four refined ingots")
eq(plated.stats.armorDefense,2,"armor grants actual defense")
eq(smith:GetAttribute("SkillDefense"),plated.stats.defense,"armor defense publishes to combat consumers")
local humanoid=smith.Character:FindFirstChildOfClass("Humanoid")
local hp=humanoid.Health
use(smith,node("fight","Warden"))
eq(humanoid.Health,hp-math.max(1,9-plated.stats.defense),"armor reduces Warden damage")
services.Players.PlayerRemoving:Fire(smith)
smith=player(80)
eq(cmd(smith,"state").items.ReinforcedPickaxe,1,"upgraded tool persists")
eq(cmd(smith,"state").stats.armorDefense,2,"armor bonus persists and reapplies")
local recipeList=cmd(smith,"state").recipes
eq(recipeList[4].id,"AlloyIngot","server exposes ordered recipe IDs")
eq(recipeList[4].repeatable,true,"server exposes repeatable refining")
eq(recipeList[5].level,3,"server exposes authoritative skill gate")
eq(recipeList[6].costs.Pickaxe,1,"server exposes tool replacement cost")
eq(recipeList[7].collection.Aetherite,8,"server exposes armor collection gate")
local gated=player(81)
services.Players.PlayerRemoving:Fire(gated)
data.p81.profile.xp.Smithing=160
data.p81.profile.items={AetherIngot=10,Timber=10,Pickaxe=1,Herb=4,Ore=3}
gated=player(81)
eq(cmd(gated,"craft","ReinforcedPickaxe").items.AetherIngot,10,"collection lock cannot spend seeded ingredients")
eq(cmd(gated,"craft","Skyplate").items.Skyplate,nil,"armor also requires lifetime collection")
eq(cmd(gated,"state").xp.Smithing,160,"collection rejection awards no crafting XP")
eq(cmd(gated,"state").recipes[6].unlocked,false,"recipe metadata reflects collection lock")
eq(cmd(gated,"worker").worker,true,"advanced-material restriction tested on active worker")
eq(cmd(gated,"workerResource","Aetherite").workerResource,"Ore","workers cannot bypass advanced gathering")
-- Rank 2 bounded slice: old five-contract journals gain a charter, and only
-- the charter unlocks rich resources and the server-owned survey interaction.
local regionHook
for _,object in ipairs(allObjects) do if object.Name=="IsleRegionAccess" then regionHook=object end end
assert(regionHook,"region transit hook exists")
local traveler=player(90)
services.Players.PlayerRemoving:Fire(traveler)
data.p90.profile.questCompleted=5
data.p90.profile.xp.Mining=162 -- one Ore harvest short of Mining 3 (174 XP)
data.p90.profile.collection.AlloyIngot=2
data.p90.profile.items={Ore=2,Timber=1}
traveler=player(90)
local rich=node("gather","Aetherite",0,nil,"Skyreach")
local survey=node("explore","Skyreach",0,nil,"Skyreach")
eq(cmd(traveler,"state").quest.stage,6,"old five-contract journal migrates to charter")
eq(cmd(traveler,"state").quest.total,8,"expanded contract count exposed")
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,false,"transit denies unclaimed charter")
eq(use(traveler,rich).items.Aetherite,nil,"bypassing travel cannot harvest locked region")
eq(use(traveler,survey).regions[1].visited,false,"locked region cannot be surveyed")
eq(cmd(traveler,"quest").quest.stage,6,"charter rejects missing requirements")
cmd(traveler,"craft","AlloyIngot")
eq(cmd(traveler,"quest").quest.stage,6,"charter independently requires Mining 3")
use(traveler,ore)
eq(cmd(traveler,"state").quest.ready,true,"charter ready after both requirements")
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,false,"readiness alone does not unlock transit")
eq(cmd(traveler,"quest").coins,25+125,"charter pays once (plus Mining 2-3 level rewards)")
eq(cmd(traveler,"state").regions[1].unlocked,true,"claimed charter unlocks region snapshot")
eq(traveler:GetAttribute("SkyreachUnlocked"),true,"charter publishes world unlock")
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,true,"charter opens authoritative transit")
eq(regionHook.OnInvoke(traveler,"Unknown").allowed,false,"unknown region rejected")
eq(cmd(traveler,"quest").coins,150,"repeated charter claim does not pay again")
eq(cmd(traveler,"explore","Skyreach").regions[1].visited,false,"remote survey forgery denied")
use(traveler,node("explore","Skyreach",50,nil,"Skyreach"))
eq(cmd(traveler,"state").regions[1].visited,false,"survey requires proximity")
use(traveler,node("explore","Skyreach"))
eq(cmd(traveler,"state").regions[1].visited,false,"survey requires correct registered region")
eq(use(traveler,survey).regions[1].visited,true,"valid beacon records survey")
eq(cmd(traveler,"state").quest.ready,true,"survey completes next contract")
eq(cmd(traveler,"quest").xp.Smithing,66,"survey rewards 50 Smithing XP")
eq(cmd(traveler,"quest").xp.Smithing,66,"survey reward cannot repeat")
eq(use(traveler,rich).items.Aetherite,2,"unlocked rich seam provides useful regional benefit")
eq(cmd(traveler,"state").xp.Mining,192,"rich seam retains controlled experience payout")
services.Players.PlayerRemoving:Fire(traveler)
traveler=player(90)
eq(cmd(traveler,"state").regions[1].visited,true,"survey persists on rejoin")
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,true,"charter persists on rejoin")
eq(cmd(traveler,"state").quest.stage,8,"survey reward remains claimed after rejoin")
-- Item possession alone cannot bypass the charter, and both armor pieces are
-- needed for the final contract. Seed earned equipment for reward idempotency.
services.Players.PlayerRemoving:Fire(traveler)
data.p90.profile.items.ReinforcedPickaxe=1
traveler=player(90)
eq(cmd(traveler,"quest").coins,150,"equipment contract requires armor as well as tool")
services.Players.PlayerRemoving:Fire(traveler)
data.p90.profile.items.Skyplate=1
traveler=player(90)
eq(cmd(traveler,"quest").coins,225,"equipment contract pays final reward")
eq(cmd(traveler,"state").quest.complete,true,"bounded expanded chain can finish")
eq(cmd(traveler,"quest").coins,225,"final reward cannot repeat")
eq(regionHook.OnInvoke(lateOpen,"Skyreach").allowed,false,"expired session cannot use region transit")
traveler.Character:FindFirstChildOfClass("Humanoid").Health=0
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,false,"dead character cannot use region transit")
-- Rank 3 provisions: earned recipe, alternative healing, bounded consumption,
-- and recovery survives a session change rather than resetting on reconnect.
local cook=player(95)
eq(cmd(cook,"craft","ExpeditionRation").items.ExpeditionRation,nil,"ration collection gate rejects novice")
local fishNode=node("gather","Fish")
for _=1,5 do use(cook,fishNode) end
eq(cmd(cook,"craft","ExpeditionRation").items.Fish,5,"missing herb does not consume fish")
for _=1,4 do use(cook,node("gather","Herb")) end
local ration=cmd(cook,"craft","ExpeditionRation")
eq(ration.items.ExpeditionRation,1,"fish collection unlocks ration recipe")
eq(ration.items.Fish,3,"ration consumes two fish")
eq(ration.items.Herb,3,"ration consumes one herb")
eq(ration.xp.Alchemy,24,"ration preparation trains alchemy")
eq(cmd(cook,"craft","ExpeditionRation").items.ExpeditionRation,2,"ration is repeatable")
eq(cmd(cook,"heal","ExpeditionRation").items.ExpeditionRation,2,"full health does not waste ration")
local cookHum=cook.Character:FindFirstChildOfClass("Humanoid")
cookHum.Health=10
eq(cmd(cook,"heal","Ore").items.ExpeditionRation,2,"unknown provision cannot consume ration")
eq(cookHum.Health,10,"unknown provision cannot heal")
local eaten=cmd(cook,"heal","ExpeditionRation")
eq(cookHum.Health,75,"ration restores sixty-five actual health")
eq(eaten.items.ExpeditionRation,1,"ration consumption is single unit")
eq(eaten.consumables.ExpeditionRation.readyIn,12,"snapshot exposes ration recovery")
eq(cmd(cook,"heal","ExpeditionRation").items.ExpeditionRation,1,"early ration cannot consume")
eq(cookHum.Health,75,"early ration cannot heal")
services.Players.PlayerRemoving:Fire(cook)
cook=player(95)
cookHum=cook.Character:FindFirstChildOfClass("Humanoid")
cookHum.Health=20
eq(cmd(cook,"heal","ExpeditionRation").items.ExpeditionRation,1,"ration recovery persists across rejoin")
cmd(cook,"craft","Tonic")
cmd(cook,"heal")
eq(cookHum.Health,60,"legacy tonic intent remains forty-health alternative")
advance(12)
eq(cmd(cook,"heal","ExpeditionRation").items.ExpeditionRation,0,"ration usable after recovery")
eq(cookHum.Health,cookHum.MaxHealth,"ration healing clamps to maximum health")
cookHum.Health=20
advance(12)
cmd(cook,"heal","ExpeditionRation")
eq(cookHum.Health,20,"empty ration inventory cannot heal")
eq(cmd(cook,"state").items.ExpeditionRation,0,"empty ration inventory cannot go negative")
use(cook,fishNode)
use(cook,node("gather","Herb"))
cmd(cook,"craft","ExpeditionRation")
cookHum.Health=0
eq(cmd(cook,"heal","ExpeditionRation").items.ExpeditionRation,1,"dead character cannot eat or consume")
-- Rank 4: partial bank transfers are conserved and stale intents cannot repeat.
local banker=player(96)
services.Players.PlayerRemoving:Fire(banker)
data.p96.profile.coins=201
data.p96.profile.bank=99
banker=player(96)
eq(cmd(banker,"state").bankRevision,0,"older profile receives bank revision default")
local partial=cmd(banker,"deposit","half:0")
eq(partial.coins,101,"half deposit rounds down")
eq(partial.bank,199,"half deposit reaches own vault")
eq(partial.bankRevision,1,"successful transfer increments revision")
eq(cmd(banker,"deposit","half:0").bank,199,"replayed half deposit cannot repeat")
local fixed=cmd(banker,"withdraw","25:1")
eq(fixed.coins,126,"fixed withdrawal credits purse")
eq(fixed.bank,174,"fixed withdrawal debits vault")
eq(fixed.coins+fixed.bank,300,"partial transfers conserve coins")
for _,invalid in ipairs({"0:2","-1:2","1.5:2","1e3:2","NaN:2","inf:2","1000000001:2","all","all:99","25:2:96",string.rep("9",64)}) do
	local rejected=cmd(banker,"withdraw",invalid)
	eq(rejected.bank,174,"invalid bank amount rejected: "..invalid)
	eq(rejected.bankRevision,2,"invalid transfer preserves revision")
end
eq(cmd(banker,"withdraw","175:2").bank,174,"unfunded fixed withdrawal is not silently clamped")
eq(cmd(banker,"deposit","127:2").coins,126,"unfunded deposit leaves purse intact")
advance(1)
eq(objects.RemoteFunction.OnServerInvoke(banker,"deposit",25),nil,"numeric transfer payload rejected at gateway")
local outsider=player(97)
eq(cmd(outsider,"withdraw","25:2").coins,0,"another player cannot use foreign ledger revision")
eq(cmd(banker,"state").bank,174,"other player action cannot touch owner vault")
banker.Character:FindFirstChildOfClass("Humanoid").Health=0
eq(cmd(banker,"withdraw","25:2").bank,174,"dead character cannot withdraw")
banker.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
eq(cmd(banker,"state").coins,114,"death applies ten percent to remaining purse only")
eq(cmd(banker,"state").bank,174,"partial savings protected on death")
eq(cmd(banker,"state").bankRevision,3,"death invalidates prior transfer intents")
services.Players.PlayerRemoving:Fire(banker)
banker=player(96)
eq(cmd(banker,"state").coins,114,"post-death purse persists on rejoin")
eq(cmd(banker,"state").bank,174,"partial savings persist on rejoin")
eq(cmd(banker,"withdraw","25:2").bank,174,"rejoin does not revive stale transfer")
local all=cmd(banker,"withdraw","all:3")
eq(all.coins,288,"explicit all withdraw moves exact balance")
eq(all.bank,0,"all withdrawal empties vault")
eq(cmd(banker,"withdraw","all:4").bankRevision,4,"empty transfer does not change revision")
eq(cmd(banker,"deposit","287:4").coins,1,"arbitrary fixed integer supported")
eq(cmd(banker,"deposit","half:5").coins,1,"half of single coin does not create fractional money")
use(banker,node("bank",nil,0,97))
eq(cmd(banker,"state").bank,287,"foreign owner bank prompt rejected")
use(banker,node("bank",nil,50,96))
eq(cmd(banker,"state").bank,287,"distant bank prompt rejected")
eq(use(banker,node("bank",nil,0,96)).bank,288,"legacy owner bank prompt deposits all")
eq(cmd(banker,"withdraw").coins,288,"legacy nil withdrawal remains compatible")
eq(cmd(lateOpen,"deposit","all:0").message,"Waiting for journal sync.","expired session cannot bank")
-- Priced asks retain reservation/receipt recovery and migrate fixed lots in place.
local function marketPlayer(id,coins,items)
	local p=player(id)
	services.Players.PlayerRemoving:Fire(p)
	data["p"..id].profile.coins=coins
	data["p"..id].profile.items=items or {}
	return player(id)
end
local highSeller=marketPlayer(100,0,{Fish=12})
local olderSeller=marketPlayer(101,0,{Fish=12})
local newerSeller=marketPlayer(102,0,{Fish=12})
local bidder=marketPlayer(103,100,{Fish=12})
repeatMarketTransform=true
eq(cmd(highSeller,"list","Fish:30").items.Fish,9,"custom ask reserves exactly one lot")
cmd(olderSeller,"list","Fish:12")
cmd(newerSeller,"list","Fish:12")
cmd(bidder,"list","Fish:5")
eq(#data.market_v1_Fish.pricedOrders,4,"repeated transforms do not duplicate listings")
eq(data.market_v1_Fish.nextPricedOrder,4,"order sequence deterministic under transform retry")
local fishQuote=cmd(bidder,"market","Fish").market
eq(fishQuote.bestAsk,12,"quote excludes buyer's cheaper own listing")
eq(fishQuote.openLots,4,"quote shows lot count")
eq(fishQuote.ownLots,1,"quote shows own lots")
eq(fishQuote.lotSize,3,"quote states three-unit quantity")
eq(fishQuote.maxPrice,10000,"quote advertises price limit")
eq(cmd(bidder,"buy","Fish:20").coins,88,"best ask fills with price-improvement refund")
eq(data.market_v1_Fish.proceeds["101"],12,"oldest equal-price seller fills first")
eq(data.market_v1_Fish.proceeds["102"],nil,"newer equal-price ask waits")
eq(data.market_v1_Fish.proceeds["100"],nil,"expensive oldest ask does not jump price priority")
eq(cmd(bidder,"buy","Fish:12").coins,76,"second equal-price ask fills next")
eq(data.market_v1_Fish.proceeds["102"],12,"second seller credited actual ask")
eq(cmd(bidder,"buy","Fish:10").coins,76,"limit below market reimburses reservation")
eq(cmd(bidder,"state").items.Fish,15,"no-match does not deliver goods")
eq(cmd(bidder,"cancel","Fish").items.Fish,18,"cancel returns own priced goods")
eq(cmd(olderSeller,"proceeds","Fish").coins,12,"seller collects actual ask proceeds")
eq(cmd(olderSeller,"proceeds","Fish").coins,12,"priced proceeds cannot replay")
for _,bad in ipairs({"Fish:0","Fish:10001","Fish:-1","Fish:1.5","Fish:1e3","Fish:nan","Fish: 12","Fish:12:2"}) do
	local invalid=cmd(newerSeller,"list",bad)
	eq(invalid.items.Fish,9,"invalid ask cannot reserve goods: "..bad)
end
eq(cmd(newerSeller,"list","Aetherite:5").items.Fish,9,"unsupported commodity rejected")
eq(cmd(bidder,"buy","Fish:10000").coins,76,"unfunded buy limit rejected without debit")
local recoveryBuyer=marketPlayer(104,200,{})
injectedFailure=true
eq(cmd(recoveryBuyer,"buy","Fish:50").coins,150,"ambiguous purchase retains full durable reservation")
services.Players.PlayerRemoving:Fire(recoveryBuyer)
eq(data.p104.profile.pricedPending.price,50,"pending purchase persists custom limit")
recoveryBuyer=player(104)
eq(cmd(recoveryBuyer,"state").coins,170,"rejoin returns exact price-improvement once")
eq(cmd(recoveryBuyer,"state").items.Fish,3,"rejoin delivers priced purchase once")
eq(cmd(highSeller,"proceeds","Fish").coins,30,"lost acknowledgement credits seller exactly once")
eq(cmd(highSeller,"proceeds","Fish").coins,30,"seller cannot recollect recovered sale")
-- Migration keeps the existing market key, seller balances, receipts and FIFO.
local legacySeller=marketPlayer(110,0,{})
services.Players.PlayerRemoving:Fire(legacySeller)
data.p110.profile.marketSeq=1
legacySeller=player(110)
data.market_v1_Herb={orders={"110"},proceeds={},receipts={['110']={seq=1,coins=0,units=0,text="legacy listing"}},accounts=1}
local legacyBuyer=marketPlayer(111,100,{})
eq(cmd(legacyBuyer,"market","Herb").market.bestAsk,9,"legacy lot quotes original fixed price")
eq(cmd(legacyBuyer,"buy","Herb:20").coins,91,"legacy lot fills at original price")
eq(data.market_v1_Herb.version,2,"legacy book migrates in place")
eq(cmd(legacySeller,"proceeds","Herb").coins,9,"migrated seller proceeds preserved")
local oldPending=marketPlayer(112,91,{})
services.Players.PlayerRemoving:Fire(oldPending)
data.p112.profile.marketSeq=1
data.p112.profile.pending={seq=1,verb="buy",item="Herb"}
data.market_v1_Herb.orders={"113"}
oldPending=player(112)
eq(cmd(oldPending,"state").coins,91,"legacy pending buy uses historical reserved amount")
eq(cmd(oldPending,"state").items.Herb,3,"legacy pending buy still delivers")
eq(data.market_v1_Herb.proceeds['113'],9,"legacy pending seller paid historical price")
eq(cmd(c,"list","Fish:10").message,"Waiting for journal sync.","expired journal cannot open priced asks")
local ironTrader=marketPlayer(114,100,{Fish=3})
cmd(ironTrader,"ironman")
eq(cmd(ironTrader,"buy","Fish:10").coins,100,"Ironman priced buy cannot reserve coins")
eq(cmd(ironTrader,"market","Fish").market,nil,"Ironman cannot query player market")
local replaySeller=marketPlayer(115,0,{Timber=6})
injectedFailure=true
eq(cmd(replaySeller,"list","Timber:37").items.Timber,3,"ambiguous priced listing holds goods in escrow")
services.Players.PlayerRemoving:Fire(replaySeller)
replaySeller=player(115)
eq(cmd(replaySeller,"state").items.Timber,3,"listing recovery cannot duplicate reserved goods")
eq(#data.market_v1_Timber.pricedOrders,1,"listing recovery creates only one order")
eq(data.market_v1_Timber.pricedOrders[1].price,37,"listing recovery retains chosen ask")
injectedFailure=true
cmd(replaySeller,"cancel","Timber")
services.Players.PlayerRemoving:Fire(replaySeller)
replaySeller=player(115)
eq(cmd(replaySeller,"state").items.Timber,6,"cancellation recovery returns escrow once")
eq(#data.market_v1_Timber.pricedOrders,0,"recovered cancellation removes order once")
cmd(replaySeller,"list","Timber:23")
local replayBuyer=marketPlayer(116,40,{})
cmd(replayBuyer,"buy","Timber:30")
injectedFailure=true
eq(cmd(replaySeller,"proceeds","Timber").coins,0,"ambiguous proceeds wait for receipt recovery")
services.Players.PlayerRemoving:Fire(replaySeller)
replaySeller=player(115)
eq(cmd(replaySeller,"state").coins,23,"proceeds recovery grants actual ask once")
eq(cmd(replaySeller,"proceeds","Timber").coins,23,"recovered proceeds cannot repeat")
-- Two distinct old fixed-price lots retain their FIFO order when both migrate.
data.market_v1_Ore.orders={"117","118"}
data.market_v1_Ore.nextOrder=nil
local migrationBuyer=marketPlayer(119,50,{})
cmd(migrationBuyer,"buy","Ore:20")
eq(data.market_v1_Ore.proceeds['117'],15,"legacy migration preserves oldest lot priority")
eq(data.market_v1_Ore.orders[1],'118',"legacy migration preserves remaining seller")
eq(type(data.market_v1_Ore.orders[1]),"string","legacy queue retains old server serialization format")
-- Exact legacy trade behavior from deployed commit d8e1874 (before priced lots).
-- Run it against books modified by production v2, in both operation orders.
local function legacyTrade(book,trader,order)
	local fixed={Ore=15,Timber=12,Herb=9,Fish=18}
	book=book or {orders={},proceeds={},receipts={},accounts=0}
	local receipt=book.receipts[trader]
	if receipt and receipt.seq>=order.seq then return book end
	if not receipt and book.accounts>=4000 then return nil end
	if not receipt then book.accounts+=1 end
	local price=fixed[order.item]
	local result={seq=order.seq,coins=0,units=0,text=""}
	if order.verb=="list" then
		if #book.orders>=300 then result.units=3 else table.insert(book.orders,trader) end
	elseif order.verb=="buy" or order.verb=="cancel" then
		local index=table.find(book.orders,trader)
		if order.verb=="buy" then index=nil;for i,seller in ipairs(book.orders) do if seller~=trader then index=i;break end end end
		if index then
			local seller=table.remove(book.orders,index)
			if order.verb=="buy" then book.proceeds[seller]=(book.proceeds[seller] or 0)+price end
			result.units=3
		else result.coins=if order.verb=="buy" then price else 0 end
	else result.coins=book.proceeds[trader] or 0;book.proceeds[trader]=nil end
	book.receipts[trader]=result
	return book
end
local function oldMarket(trader,verb,item,seq)
	return db:UpdateAsync("market_v1_"..item,function(old) return legacyTrade(old,trader,{verb=verb,item=item,seq=seq}) end)
end
data.market_v1_Fish=nil
local mixedSeller=marketPlayer(120,0,{Fish=6})
cmd(mixedSeller,"list","Fish:9")
eq(data.market_v1_Fish.receipts['120'].seq,0,"priced user registers harmless legacy receipt")
eq(data.market_v1_Fish.accounts,1,"priced user counts toward shared legacy account limit")
oldMarket('121','list','Fish',1)
eq(data.market_v1_Fish.orders[1],'121',"old listing after new write retains string seller")
eq(#data.market_v1_Fish.pricedOrders,1,"old listing preserves separately priced lots")
oldMarket('122','buy','Fish',1)
eq(data.market_v1_Fish.proceeds['121'],18,"old buyer after new writer pays fixed lot price")
eq(#data.market_v1_Fish.pricedOrders,1,"old buyer cannot misprice new custom lot")
local mixedBuyer=marketPlayer(123,100,{})
eq(cmd(mixedBuyer,"buy","Fish:20").coins,91,"new buyer after old writer matches custom ask")
oldMarket('120','proceeds','Fish',1)
eq(data.market_v1_Fish.receipts['120'].coins,9,"old server can collect shared priced proceeds")
eq(data.market_v1_Fish.accounts,4,"old action reuses priced user's account registration")
eq(data.market_v1_Fish.pricedReceipts['120'].units,0,"old receipt cannot overwrite new receipt stream")
oldMarket('124','list','Fish',1)
cmd(mixedSeller,"list","Fish:18")
cmd(mixedBuyer,"buy","Fish:20")
eq(data.market_v1_Fish.proceeds['124'],18,"equal-price mixed queues prioritize legacy lot")
eq(#data.market_v1_Fish.pricedOrders,1,"mixed queue tie leaves priced lot intact")
cmd(mixedBuyer,"buy","Fish:20")
eq(#data.market_v1_Fish.pricedOrders,0,"new buyer can consume remaining priced lot")
-- Actual baseline open reuses old.profile, and persist table.clone's the whole
-- profile then clones known nested maps/workers. Unknown additive fields survive.
local hopper=marketPlayer(130,200,{})
local hopSeller=marketPlayer(131,0,{Fish=3})
cmd(hopSeller,"list","Fish:23")
injectedFailure=true
eq(cmd(hopper,"buy","Fish:40").coins,160,"hop fixture retains priced reservation")
services.Players.PlayerRemoving:Fire(hopper)
eq(data.p130.profile.pending,nil,"new reservation is invisible to legacy pending recovery")
local baselineProfile=data.p130.profile -- baseline open: profile=old and old.profile or fresh()
eq(baselineProfile.pricedPending.price,40,"legacy load preserves unknown priced reservation")
oldMarket('132','list','Fish',1)
baselineProfile.coins-=18
baselineProfile.marketSeq=1
local oldResult=oldMarket('130','buy','Fish',1).receipts['130']
baselineProfile.items.Fish=(baselineProfile.items.Fish or 0)+oldResult.units
baselineProfile.coins+=oldResult.coins
local baselinePayload=table.clone(baselineProfile) -- baseline persist, unchanged statements
for _,k in ipairs({'items','xp','collection','decorations'}) do baselinePayload[k]=table.clone(baselineProfile[k]) end
baselinePayload.workers={}
for slot,w in ipairs(baselineProfile.workers) do baselinePayload.workers[slot]=table.clone(w) end
data.p130={owner='',expires=utc+180,profile=copy(baselinePayload)}
eq(data.p130.profile.pricedPending.price,40,"legacy save preserves unknown priced reservation")
hopper=player(130)
eq(cmd(hopper,"state").coins,159,"new rejoin reconciles both legacy spend and priced refund")
eq(cmd(hopper,"state").items.Fish,6,"cross-version hop delivers each purchase exactly once")
eq(data.market_v1_Fish.receipts['130'].coins,0,"legacy receipt remains unchanged after priced recovery")
eq(data.market_v1_Fish.pricedReceipts['130'].coins,17,"priced refund remains in separate receipt")
-- Both versions share a 4000-user registry (priced users get a harmless legacy
-- sequence-zero receipt). At most two receipts per registered user are retained.
local serde=require('@lune/serde')
local capacity={orders={},pricedOrders={},proceeds={},receipts={},pricedReceipts={},accounts=4000,pricedAccounts=2000}
for i=1,4000 do
	capacity.receipts[tostring(i)]={seq=1,coins=10000,units=3,text=string.rep('x',180)}
	if i<=2000 then capacity.pricedReceipts[tostring(i)]={seq=1,coins=10000,units=3,text=string.rep('x',180)} end
end
data.market_v1_Timber=capacity
local capped=marketPlayer(9000,100,{Timber=3})
eq(cmd(capped,"list","Timber:100").items.Timber,3,"combined receipt budget returns unallocated escrow")
eq(data.market_v1_Timber.pricedAccounts,2000,"new writer cannot exceed shared account budget")
data.market_v1_Timber.proceeds['3000']=57
local existingSeller=marketPlayer(3000,0,{})
eq(cmd(existingSeller,"proceeds","Timber").coins,57,"existing legacy seller can collect at full shared capacity")
for i=2001,4000 do capacity.pricedReceipts[tostring(i)]={seq=1,coins=10000,units=3,text=string.rep('x',180)} end
capacity.accounts=4000;capacity.pricedAccounts=4000
for i=1,300 do capacity.orders[i]=tostring(i);capacity.pricedOrders[i]={seller=tostring(i+300),price=10000,sequence=i} end
for i=1,4000 do capacity.proceeds[tostring(i)]=1000000000 end
local encoded=serde.encode('json',capacity)
eq(#encoded<4*1024*1024,true,"worst rolling-version receipt/lot bounds fit 4 MiB JSON budget")
eq(type(serde.decode('json',encoded).orders[1]),'string',"mixed book remains JSON-serializable for legacy readers")
print("Rolling-version maximum-shape fixture: "..#encoded.." JSON bytes (4000 users / 8000 receipts / 600 lots).")
repeatMarketTransform=false
local legacyChecks=checks
-- Depth suite runs in its own function: the legacy chunk is near the 200-local limit.
;(function()
------------------------------------------------------------------------------
-- Depth update (docs/DEPTH-CONTRACT.md): shared rules wired into the server.
------------------------------------------------------------------------------
local X=Data.XP_TABLE
local function ok(cond,case) assert(cond,case); checks+=1 end
local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
local function hum(p) return p.Character:FindFirstChildOfClass("Humanoid") end
local function st(p) return cmd(p,"state") end
local function hook(name) for _,o in ipairs(allObjects) do if o.Name==name then return o end end return nil end
-- Create a journal, leave, edit the durable save, rejoin.
local function seeded(id,mutate)
	local p=player(id)
	services.Players.PlayerRemoving:Fire(p)
	mutate(data["p"..id].profile)
	return player(id)
end
local function rejoin(p,mutate)
	services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(data["p"..p.UserId].profile) end
	return player(p.UserId)
end
local bridge=hook("IsleBridge")
ok(bridge~=nil,"IsleBridge BindableFunction exists")
eq(bridge.Parent,services.ServerStorage,"IsleBridge parented to ServerStorage")
eq(hook("IsleCoopProfile").Parent,services.ServerStorage,"co-op hook still parented")
ok(#seeds>=1,"server creates a seeded Random")

-- Fresh snapshot exposes the full depth block.
local novice2=player(200)
local s0=st(novice2)
local d0=s0.depth
for _,skill in ipairs(Data.SkillOrder) do
	eq(d0.skills[skill].level,1,"fresh "..skill.." level 1")
	eq(s0.levels[skill],1,"fresh legacy levels include "..skill)
end
eq(s0.xp.Cooking,0,"fresh Cooking xp")
eq(s0.xp.Carpentry,0,"fresh Carpentry xp")
eq(d0.totalLevel,#Data.SkillOrder,"fresh total level")
eq(d0.skillAverage,1,"fresh skill average")
eq(d0.skills.Mining.ceiling,83,"Mining 2 at 83 XP")
eq(d0.skills.Mining.maxed,false,"fresh skill not maxed")
eq(d0.stats.health,100,"base health")
eq(d0.stats.speed,100,"base speed")
eq(hum(novice2).WalkSpeed,16,"100 Speed maps to default walk speed")
eq(d0.accessorySlots,3,"three base accessory slots")
eq(#d0.regions,#Data.Regions,"every region listed")
eq(d0.collections.Ore.tier,0,"fresh collection tier")
eq(d0.collections.Ore.nextAt,50,"first collection threshold")
eq(d0.slayer.lines.Bramble.nextAt,5,"first slayer level threshold")
eq(d0.slayer.quest,nil,"no slayer quest")
eq(#d0.pets,0,"no pets")
eq(d0.tools.Mining,nil,"no tools")
eq(novice2.SlayerBossReady,"","boss attribute cleared")
eq(novice2.MeadowUnlocked,true,"open region attribute")
eq(novice2.WindpineUnlocked,false,"gated region attribute")
eq(novice2.CombatLevel,1,"combat level attribute")

-- OSRS curve and one-time level coins.
local miner=player(201)
for _=1,6 do use(miner,ore) end
eq(st(miner).levels.Mining,1,"72 XP is Mining 1")
local levelled=use(miner,ore)
eq(levelled.levels.Mining,2,"84 XP reaches Mining 2")
eq(levelled.coins,50,"Mining 2 pays its coin reward")
ok(has(levelled.message,"Mining level 2! +50 coins"),"level-up message")
eq(levelled.depth.skills.Mining.floor,83,"progress floor")
eq(levelled.depth.skills.Mining.ceiling,174,"Mining 3 at 174 XP")
miner=rejoin(miner)
eq(data.p201.profile.levelRewards.Mining,2,"level reward persisted")
eq(use(miner,ore).coins,50,"level reward never repeats after rejoin")
local veteran=seeded(202,function(p) p.xp.Mining=X[15]-12; p.levelRewards.Mining=14 end)
local fifteen=use(veteran,ore)
eq(fifteen.levels.Mining,15,"Mining 15 reached")
eq(fifteen.coins,1500,"Mining 15 pays 1500 coins")
ok(has(fifteen.message,"Mining level 15! +1500 coins"),"level 15 message")
local capped=seeded(204,function(p) p.xp.Mining=Data.MAX_XP-5; p.levelRewards.Mining=99 end)
local maxed=use(capped,ore)
eq(maxed.xp.Mining,Data.MAX_XP,"XP capped at 200M")
eq(maxed.depth.skills.Mining.maxed,true,"level 99 reports maxed")
eq(maxed.depth.skills.Mining.level,99,"level 99")

-- Monster kills: multi-level jump pays every level once.
local brawler=player(203)
local killed=bridge.OnInvoke("kill",brawler,{monster="StarbornSentinel"})
eq(next(killed.drops),nil,"high rolls drop nothing")
eq(killed.bossReady,false,"no quest means no boss")
ok(has(brawler.last.message,"Starborn Sentinel slain"),"kill pushes a snapshot message")
ok(has(brawler.last.message,"Combat level 6! +500 coins"),"multi-level reward message")
local fought=st(brawler)
eq(fought.levels.Combat,6,"520 Combat XP is level 6")
eq(fought.coins,120+500,"monster coins plus levels 2-6 rewards")
eq(fought.depth.bestiary.StarbornSentinel,1,"bestiary counts kills")
eq(fought.depth.stats.strength,5,"Combat levels grant strength")
eq(fought.depth.stats.combatBonus,20,"Combat bonus 4% per level")
eq(brawler.CombatLevel,6,"combat level attribute updates")

-- Migration of an older save (no Depth tables, missing new skills).
local legacySave=seeded(210,function(p)
	p.version=1
	p.xp={Mining=500,Woodcutting=0,Farming=0,Fishing=0,Smithing=0,Combat=0,Alchemy=0,Dungeoneering=0,Enchanting=0,Taming=0}
	p.collection={Ore=120}
	p.items={}
	for _,k in ipairs({"equipment","enchants","accessoryBag","pets","buffs","bestiary","slayerXp","levelRewards","collectionRewards"}) do p[k]=nil end
	p.activePet=3
	p.slayerQuest={line="Nope",tier=1}
end)
local migrated=st(legacySave)
eq(migrated.xp.Cooking,0,"migration adds Cooking")
eq(migrated.xp.Carpentry,0,"migration adds Carpentry")
eq(migrated.levels.Mining,5,"500 XP is Mining 5")
eq(type(migrated.depth.equipment),"table","migration adds equipment")
eq(#migrated.depth.pets,0,"migration adds pets")
eq(migrated.depth.slayer.lines.Gloom.xp,0,"migration adds slayer xp")
eq(migrated.depth.slayer.quest,nil,"invalid slayer quest dropped")
eq(migrated.coins,0,"migration pays no retroactive rewards")
local migratedGather=use(legacySave,ore)
eq(migratedGather.levels.Mining,6,"512 XP reaches Mining 6")
eq(migratedGather.coins,150,"only the newly reached level pays")
eq(migratedGather.items.Ore,2,"Mining 3+ legacy bonus survives migration")
legacySave=rejoin(legacySave)
eq(data.p210.profile.version,2,"migrated save version")
eq(data.p210.profile.activePet,nil,"dangling active pet cleared")
eq(data.p210.profile.collectionRewards.Ore,2,"collection baseline persisted")
eq(data.p210.profile.levelRewards.Mining,6,"level baseline persisted")

-- Gathering through Progression.harvest: level gate, tool gate, fortune.
local brassNode=node("gather","Brassite")
local prospector=player(220)
eq(use(prospector,brassNode).items.Brassite,nil,"Brassite requires Mining 15")
ok(has(prospector.last.message,"requires Mining 15"),"level gate message")
eq(cmd(prospector,"gather","Brassite").items.Brassite,nil,"remote Brassite denied")
prospector=rejoin(prospector,function(p) p.xp.Mining=X[15]; p.levelRewards.Mining=15 end)
eq(use(prospector,brassNode).items.Brassite,nil,"tier 1 pickaxe required")
ok(has(prospector.last.message,"tier 1 pickaxe"),"tool gate message")
eq(st(prospector).xp.Mining,X[15],"tool gate awards no XP")
prospector=rejoin(prospector,function(p) p.items.Pickaxe=1 end)
local harvested=use(prospector,brassNode)
eq(harvested.items.Brassite,1,"Brassite harvested")
eq(harvested.xp.Mining,X[15]+35,"Brassite XP")
eq(harvested.collection.Brassite,1,"Brassite collection")
eq(harvested.depth.tools.Mining,"Pickaxe","best tool reported")
rolls={0}
eq(use(prospector,brassNode).items.Brassite,3,"fortune proc doubles harvest")
workspace.FestivalResource="Brassite"
eq(use(prospector,brassNode).items.Brassite,5,"festival bonus applies to new resources")
workspace.FestivalResource=nil
eq(use(prospector,ore).items.Ore,3,"legacy pickaxe and mastery bonus on Ore")
local aetherHint=use(player(221),node("gather","Aetherite"))
ok(has(aetherHint.message,"Train on Ore"),"Aetherite gate keeps its hint")
local lumber=player(222)
local windpineLog=node("gather","WindpineLog",0,nil,"Windpine")
eq(use(lumber,windpineLog).items.WindpineLog,nil,"Windpine region gated")
eq(lumber.last.message,"Windpine Grove requires Woodcutting 10.","region denial message")
lumber=rejoin(lumber,function(p) p.xp.Woodcutting=X[15]; p.levelRewards.Woodcutting=15 end)
eq(use(lumber,windpineLog).items.WindpineLog,nil,"hatchet required")
ok(has(lumber.last.message,"tier 1 hatchet"),"hatchet message")
lumber=rejoin(lumber,function(p) p.items.CopperHatchet=1 end)
eq(use(lumber,windpineLog).items.WindpineLog,1,"Windpine log harvested in region")
eq(use(lumber,node("gather","Shard")).items.Shard,nil,"non-resource gather rejected")
eq(lumber.last.message,"Unknown action.","non-resource gather message")
eq(use(lumber,node("gather","Ore",0,nil,"Atlantis")).items.Ore,nil,"unknown region prompt rejected")
eq(lumber.last.message,"That region is not on the guild charts.","unknown region message")

-- Collection tier rewards: once per tier, multi-tier crossings sum.
local collector=seeded(223,function(p) p.collection={Ore=49,Herb=99}; p.collectionRewards={Herb=1} end)
local tier1=use(collector,ore)
eq(tier1.coins,50,"collection tier 1 pays 50")
ok(has(tier1.message,"Copperstone Ore collection tier 1! +50 coins"),"collection message")
eq(tier1.depth.collections.Ore.tier,1,"collection tier reported")
eq(tier1.depth.collections.Ore.nextAt,100,"next collection threshold")
eq(use(collector,node("gather","Herb")).coins,250,"Herb tier 2 pays 200")
collector=rejoin(collector)
eq(use(collector,ore).coins,250,"collection reward cannot repeat after rejoin")
eq(data.p223.profile.collectionRewards.Ore,1,"collection rewards persisted")

-- Data.Recipes crafting via Progression.canCraft.
local crafter=seeded(230,function(p)
	p.items={AlloyIngot=4,Timber=10,Herb=5,Fish=3}
	p.xp.Smithing=X[14]; p.levelRewards.Smithing=14
end)
local hatchet=cmd(crafter,"craft","CopperHatchet")
eq(hatchet.items.CopperHatchet,1,"Data recipe crafted")
eq(hatchet.items.AlloyIngot,2,"Data recipe spends ingots")
eq(hatchet.items.Timber,7,"Data recipe spends timber")
eq(hatchet.xp.Smithing,X[14]+20,"Data recipe XP to recipe.skill")
local again=cmd(crafter,"craft","CopperHatchet")
eq(again.items.AlloyIngot,2,"non-repeatable recipe cannot charge twice")
eq(again.message,"You already own Copper Hatchet.","duplicate craft message")
local brassLocked=cmd(crafter,"craft","BrassIngot")
eq(brassLocked.message,"Brass Ingot requires Smithing 15.","level-gated recipe message")
local cooked=cmd(crafter,"craft","CookedFish")
eq(cooked.items.CookedFish,1,"meal cooked")
eq(cooked.xp.Cooking,20,"cooking XP")
eq(cooked.items.Fish,2,"meal spends fish")
eq(cooked.items.Herb,4,"meal spends herb")
eq(cmd(crafter,"craft","CookedFish").items.CookedFish,2,"meals repeatable")
eq(cmd(crafter,"craft","CookedGlassfin").items.CookedGlassfin,nil,"Cooking 15 gate")
eq(cmd(crafter,"craft","MightDraught").items.MightDraught,nil,"Alchemy 5 gate")
eq(cmd(crafter,"craft","Nope").message,"Unknown action.","unknown recipe")
eq(cmd(crafter,"craft",string.rep("A",65)).message,"That request is too long.","long item rejected at gateway")
advance(1)
eq(objects.RemoteFunction.OnServerInvoke(crafter,"craft",5),nil,"numeric recipe rejected at gateway")
advance(1)
eq(objects.RemoteFunction.OnServerInvoke(crafter,string.rep("v",33),nil),nil,"long verb rejected at gateway")
local forger=seeded(231,function(p)
	p.items={Brassite=6,WindpineLog=4}
	p.collection={Brassite=10}
	p.xp.Smithing=X[15]; p.levelRewards.Smithing=15
end)
local ingot=cmd(forger,"craft","BrassIngot")
eq(ingot.items.BrassIngot,1,"ingot smelted")
eq(ingot.items.Brassite,3,"ingot spends ore")
eq(ingot.xp.Smithing,X[15]+34,"ingot XP")
eq(cmd(forger,"craft","BrassIngot").items.BrassIngot,2,"ingots repeatable")
local lockedPick=cmd(forger,"craft","BrassPickaxe")
eq(lockedPick.items.BrassPickaxe,nil,"collection-gated tool locked")
ok(has(lockedPick.message,"collection tier 1"),"collection gate message")
eq(lockedPick.items.BrassIngot,2,"locked recipe spends nothing")
forger=rejoin(forger,function(p) p.collection.Brassite=50; p.items.BrassIngot=3; p.items.WindpineLog=2 end)
local pick=cmd(forger,"craft","BrassPickaxe")
eq(pick.items.BrassPickaxe,1,"collection unlock crafts tool")
eq(pick.depth.tools.Mining,nil,"tool requirements gate best tool")
local carpenter=seeded(232,function(p) p.items={Herb=64}; p.collection={Herb=100}; p.collectionRewards={Herb=2} end)
local charm=cmd(carpenter,"craft","MeadowCharm")
eq(charm.items.MeadowCharm,1,"accessory crafted")
eq(charm.xp.Carpentry,40,"Carpentry XP")
eq(charm.items.Herb,0,"accessory cost")

-- Equipment.
local knight=seeded(240,function(p)
	p.xp.Combat=X[5]; p.levelRewards.Combat=5
	p.items={BrassSword=1,BrassHelm=1,BrassChestplate=1,BrassGreaves=1,BrassBoots=1,BrassPickaxe=1,SunsteelSword=1,Ore=5}
end)
eq(cmd(knight,"equip","Nope").depth.equipment.weapon,nil,"unknown item cannot equip")
eq(cmd(knight,"equip","BrassPickaxe").depth.equipment.pickaxe,nil,"tools are not equipped")
eq(cmd(knight,"equip","Ore").depth.equipment.weapon,nil,"resources cannot equip")
local tooWeak=cmd(knight,"equip","SunsteelSword")
eq(tooWeak.depth.equipment.weapon,nil,"Combat requirement enforced")
eq(tooWeak.message,"Sunsteel Sword requires Combat 12.","requirement message")
eq(cmd(knight,"equip","StarmetalSword").depth.equipment.weapon,nil,"unowned weapon cannot equip")
local armedKnight=cmd(knight,"equip","BrassSword")
eq(armedKnight.depth.equipment.weapon,"BrassSword","weapon equipped")
eq(armedKnight.depth.stats.weapon,"BrassSword","stats use equipped weapon")
eq(armedKnight.depth.stats.damage,40,"weapon damage")
eq(armedKnight.depth.stats.strength,14,"weapon strength plus Combat")
ok(has(cmd(knight,"equip","BrassSword").message,"already equipped"),"duplicate equip message")
for _,piece in ipairs({"BrassHelm","BrassChestplate","BrassGreaves","BrassBoots"}) do cmd(knight,"equip",piece) end
local plate=st(knight)
eq(plate.depth.stats.activeSet,"Brass","full set bonus active")
eq(plate.depth.stats.defense,148,"armor plus set defense")
eq(plate.depth.stats.health,159,"armor health")
eq(hum(knight).MaxHealth,159,"humanoid MaxHealth follows stats")
eq(plate.stats.maxHealth,159,"legacy maxHealth follows stats")
local bareFeet=cmd(knight,"unequip","boots")
eq(bareFeet.depth.equipment.boots,nil,"unequip clears slot")
eq(bareFeet.depth.stats.activeSet,nil,"set bonus needs four pieces")
eq(bareFeet.depth.stats.defense,98,"unequip removes defense")
eq(cmd(knight,"unequip","boots").message,"Nothing is equipped in that slot.","empty slot unequip")
ok(has(cmd(knight,"unequip","pickaxe").message,"Choose weapon"),"invalid slot rejected")
eq(cmd(knight,"sell","BrassSword").items.BrassSword,1,"equipped item cannot be sold")
cmd(knight,"unequip","weapon")
local soldSword=cmd(knight,"sell","BrassSword")
eq(soldSword.items.BrassSword,0,"unequipped item sold")
eq(soldSword.coins,Data.Items.BrassSword.value,"sold at Data value")
knight=rejoin(knight)
eq(data.p240.profile.equipment.helmet,"BrassHelm","equipment persisted")
eq(st(knight).depth.equipment.chest,"BrassChestplate","equipment restored on rejoin")
knight=rejoin(knight,function(p) p.xp.Combat=0 end)
eq(st(knight).depth.stats.defense,0,"equipment ignored when requirements no longer met")

-- Consumables: food recovery, potion/feast buffs.
local eater=seeded(250,function(p)
	p.items={CookedFish=3,MightDraught=2,HuntersFeast=1,Ore=3,ProspectorsBrew=1,SwiftwindElixir=1,Tonic=1,Pickaxe=1}
	p.xp.Mining=X[15]; p.levelRewards.Mining=15
end)
local eaterHum=hum(eater)
eq(cmd(eater,"consume","Ore").items.Ore,3,"resources are not consumable")
ok(has(cmd(eater,"consume","StarlitBanquet").message,"You have no"),"unowned consumable rejected")
eq(cmd(eater,"consume","CookedFish").items.CookedFish,3,"full health does not waste food")
eaterHum.Health=20
local ate=cmd(eater,"consume","CookedFish")
eq(eaterHum.Health,95,"meal heals")
eq(ate.items.CookedFish,2,"meal consumed")
eq(cmd(eater,"consume","CookedFish").items.CookedFish,2,"meal recovery blocks immediate reuse")
eq(eaterHum.Health,95,"blocked meal does not heal")
advance(4)
cmd(eater,"consume","CookedFish")
eq(eaterHum.Health,eaterHum.MaxHealth,"meal heal clamps to max")
local drank=cmd(eater,"consume","MightDraught")
eq(drank.items.MightDraught,1,"potion consumed")
eq(drank.depth.buffs.MightDraught.remaining,300,"potion buff duration")
eq(drank.depth.stats.strength,15,"potion strength")
advance(100)
eq(cmd(eater,"consume","MightDraught").depth.buffs.MightDraught.remaining,300,"repeat potion refreshes duration")
local feast=cmd(eater,"consume","HuntersFeast")
eq(feast.depth.stats.health,160,"feast health")
eq(eaterHum.MaxHealth,160,"feast raises MaxHealth")
eq(feast.depth.stats.strength,45,"buffs stack across consumables")
eq(cmd(eater,"consume","SwiftwindElixir").depth.stats.speed,140,"speed potion")
eq(eaterHum.WalkSpeed,16*1.4,"walk speed follows Speed stat")
cmd(eater,"consume","ProspectorsBrew")
eq(use(eater,brassNode).items.Brassite,2,"100+ fortune guarantees an extra drop")
eater=rejoin(eater)
eq(data.p250.profile.buffs.HuntersFeast.stats.strength,30,"buffs persisted")
eq(st(eater).depth.buffs.HuntersFeast~=nil,true,"buffs restored on rejoin")
advance(301)
eater=rejoin(eater) -- the 180 s lease lapses without the autosave loop in tests
local faded=st(eater)
eq(faded.depth.buffs.MightDraught,nil,"expired buff hidden")
eq(faded.depth.stats.strength,30,"expired buff stats removed")
eaterHum=hum(eater)
eaterHum.Health=10
cmd(eater,"consume","Tonic")
eq(eaterHum.Health,50,"consume routes legacy Tonic")

-- Accessory bag.
local jeweler=seeded(260,function(p) p.items={MeadowCharm=1,QuarryTalisman=1,TimberRing=1,AnglerBead=1,Ore=1} end)
ok(has(cmd(jeweler,"accessory","Ore").message,"Choose an accessory"),"non-accessory rejected")
ok(has(cmd(jeweler,"accessory","HideBracer").message,"do not own"),"unowned accessory rejected")
local charmed=cmd(jeweler,"accessory","MeadowCharm")
eq(#charmed.depth.accessoryBag,1,"accessory added")
eq(charmed.depth.activeAccessories[1],"MeadowCharm","accessory active")
eq(charmed.depth.stats.magicalPower,3,"common magical power")
eq(charmed.depth.stats.health,113,"accessory and power health")
cmd(jeweler,"accessory","QuarryTalisman")
cmd(jeweler,"accessory","TimberRing")
local full=cmd(jeweler,"accessory","AnglerBead")
eq(#full.depth.accessoryBag,3,"bag capacity enforced")
ok(has(full.message,"bag full"),"bag full message")
eq(#cmd(jeweler,"accessory","MeadowCharm").depth.accessoryBag,2,"toggle removes accessory")
eq(#cmd(jeweler,"accessory","AnglerBead").depth.accessoryBag,3,"freed slot reusable")
eq(cmd(jeweler,"sell","QuarryTalisman").items.QuarryTalisman,1,"bagged accessory cannot be sold")
jeweler=rejoin(jeweler,function(p) p.xp.Combat=X[5]; p.levelRewards.Combat=5 end)
eq(#data.p260.profile.accessoryBag,3,"accessory bag persisted")
eq(st(jeweler).depth.accessorySlots,4,"Combat 5 unlocks a slot")

-- Pets.
local tamer=seeded(270,function(p) p.items={EmberfoxPet=1,Ore=2} end)
ok(has(cmd(tamer,"petAdopt","Ore").message,"Choose a pet"),"non-pet adopt rejected")
ok(has(cmd(tamer,"petAdopt","TidewingPet").message,"do not own"),"unowned pet rejected")
ok(has(cmd(tamer,"petAdopt","Emberfox").message,"Choose a pet"),"pet id is not an item")
local adopted=cmd(tamer,"petAdopt","EmberfoxPet")
eq(#adopted.depth.pets,1,"pet adopted")
eq(adopted.items.EmberfoxPet,0,"pet item consumed")
eq(adopted.xp.Taming,100,"adoption trains Taming")
eq(adopted.coins,50,"Taming 2 reward")
eq(#cmd(tamer,"petAdopt","EmberfoxPet").depth.pets,1,"pet item cannot be adopted twice")
local summoned=cmd(tamer,"petSummon","1")
eq(summoned.depth.pets[1].active,true,"pet summoned")
eq(summoned.depth.stats.strength,0.4,"pet stats apply")
eq(summoned.depth.pets[1].next,Data.petXpToNext(1,"Epic"),"pet next-level XP")
for _,bad in ipairs({"2","-1","1.5","x","0001",""}) do
	eq(cmd(tamer,"petSummon",bad).depth.pets[1].active,true,"invalid summon ignored: "..bad)
end
bridge.OnInvoke("kill",tamer,{monster="BramblebackBoar"})
eq(st(tamer).depth.pets[1].xp,12,"pet earns full XP of its skill")
use(tamer,ore)
eq(st(tamer).depth.pets[1].xp,15,"pet earns 25% of other skills")
bridge.OnInvoke("kill",tamer,{monster="StarbornSentinel"})
ok(has(tamer.last.message,"Emberfox pet level 2!"),"pet level message")
local grown=st(tamer)
eq(grown.depth.pets[1].level,2,"pet levels up")
eq(grown.depth.pets[1].xp,535-Data.petXpToNext(1,"Epic"),"pet XP carries over")
eq(cmd(tamer,"petSummon","0").depth.pets[1].active,false,"pet dismissed")
ok(has(cmd(tamer,"petSummon","0").message,"No pet"),"double dismiss message")
bridge.OnInvoke("kill",tamer,{monster="BramblebackBoar"})
eq(st(tamer).depth.pets[1].xp,535-Data.petXpToNext(1,"Epic"),"dismissed pet earns nothing")
cmd(tamer,"petSummon","1")
tamer=rejoin(tamer)
eq(data.p270.profile.pets[1].level,2,"pets persisted")
eq(st(tamer).depth.pets[1].active,true,"active pet restored")

-- Enchanting table.
local runesmith=seeded(280,function(p)
	p.items={BrassSword=1,BrassPickaxe=1,ArcaneDust=1000}
	p.coins=10000
	p.xp.Combat=X[5]; p.levelRewards.Combat=5
	p.equipment={weapon="BrassSword"}
end)
for _,bad in ipairs({"BrassSword","BrassSword:",":Sharpness","BrassSword:Nope","Nope:Sharpness","BrassSword:Sharpness:1","Brass Sword:Sharpness"}) do
	local rejected=cmd(runesmith,"enchantItem",bad)
	eq(rejected.depth.enchants.BrassSword,nil,"malformed enchant rejected: "..bad)
	eq(rejected.coins,10000,"malformed enchant free: "..bad)
end
ok(has(cmd(runesmith,"enchantItem","StarmetalSword:Sharpness").message,"do not own"),"unowned enchant target")
ok(has(cmd(runesmith,"enchantItem","BrassSword:Protection").message,"cannot be applied"),"enchant kind enforced")
local sharp=cmd(runesmith,"enchantItem","BrassSword:Sharpness")
eq(sharp.depth.enchants.BrassSword.Sharpness,1,"enchant applied")
eq(sharp.items.ArcaneDust,996,"enchant dust cost")
eq(sharp.coins,9900,"enchant coin cost")
eq(sharp.xp.Enchanting,30,"enchant XP")
eq(sharp.depth.stats.damagePercent,5,"enchant stat applies to equipped weapon")
local gated=cmd(runesmith,"enchantItem","BrassSword:Sharpness")
eq(gated.depth.enchants.BrassSword.Sharpness,1,"enchant level gate")
eq(gated.message,"Sharpness 2 requires Enchanting 13.","enchant gate message")
eq(gated.items.ArcaneDust,996,"gated enchant spends nothing")
eq(cmd(runesmith,"enchantItem","BrassSword:Critical").depth.enchants.BrassSword.Critical,nil,"Critical requires Enchanting 10")
runesmith=rejoin(runesmith,function(p) p.xp.Enchanting=X[99]; p.levelRewards.Enchanting=99 end)
for _=2,5 do cmd(runesmith,"enchantItem","BrassSword:Sharpness") end
local maxedSword=st(runesmith)
eq(maxedSword.depth.enchants.BrassSword.Sharpness,5,"enchant to max level")
eq(maxedSword.items.ArcaneDust,996-16-36-64-100,"escalating dust cost")
eq(maxedSword.coins,9900-400-900-1600-2500,"escalating coin cost")
ok(has(cmd(runesmith,"enchantItem","BrassSword:Sharpness").message,"maximum level"),"enchant max level")
local fortuneTool=cmd(runesmith,"enchantItem","BrassPickaxe:Fortune")
eq(fortuneTool.depth.enchants.BrassPickaxe.Fortune,1,"tool enchant applied")
runesmith=rejoin(runesmith,function(p) p.coins=50 end)
local broke=cmd(runesmith,"enchantItem","BrassSword:Critical")
eq(broke.depth.enchants.BrassSword.Critical,nil,"enchant needs coins")
eq(broke.items.ArcaneDust,996-216-4,"unaffordable enchant spends no dust")
eq(data.p280.profile.enchants.BrassSword.Sharpness,5,"enchants persisted")

-- Merchant sells any item at Data value; nil keeps legacy behaviour.
local merchant=seeded(290,function(p) p.items={BrassIngot=5,Ore=4,StarFragment=1} end)
local ingots=cmd(merchant,"sell","BrassIngot")
eq(ingots.coins,5*Data.Items.BrassIngot.value,"stack sold at Data value")
eq(ingots.items.BrassIngot,0,"stack removed")
ok(has(cmd(merchant,"sell","BrassIngot").message,"You have no"),"empty stack message")
eq(cmd(merchant,"sell","Nope").coins,220,"unknown item cannot be sold")
local legacySale=cmd(merchant,"sell")
eq(legacySale.coins,236,"nil sell keeps legacy four resources")
eq(legacySale.items.StarFragment,1,"nil sell ignores other items")
eq(cmd(merchant,"sell","StarFragment").coins,416,"rare item sold by id")

-- Slayer quests.
local slayer=seeded(300,function(p) p.xp.Combat=X[5]; p.levelRewards.Combat=5; p.coins=1000 end)
for _,bad in ipairs({"Bramble","Bramble:9","Bramble:0","Nope:1","Bramble:1:2","bramble:1","Bramble:10"}) do
	local rejected=cmd(slayer,"slayerBegin",bad)
	eq(rejected.depth.slayer.quest,nil,"malformed slayer quest rejected: "..bad)
	eq(rejected.coins,1000,"malformed slayer quest free: "..bad)
end
eq(cmd(slayer,"slayerBegin","Bramble:2").message,"Brambleback Matriarch tier 2 requires Combat 12.","slayer tier Combat gate")
eq(cmd(slayer,"slayerBegin","Gloom:1").depth.slayer.quest,nil,"slayer line Combat gate")
local poorSlayer=seeded(301,function(p) p.xp.Combat=X[5]; p.coins=100 end)
local poor=cmd(poorSlayer,"slayerBegin","Bramble:1")
eq(poor.depth.slayer.quest,nil,"slayer fee required")
eq(poor.coins,100,"unaffordable fee not charged")
local begun=cmd(slayer,"slayerBegin","Bramble:1")
eq(begun.coins,800,"slayer fee charged")
eq(begun.depth.slayer.quest.line,"Bramble","quest line")
eq(begun.depth.slayer.quest.tier,1,"quest tier")
eq(begun.depth.slayer.quest.needed,150,"quest XP needed")
eq(begun.depth.slayer.quest.bossReady,false,"boss not ready")
eq(cmd(slayer,"slayerBegin","Bramble:1").coins,800,"second quest cannot start")
bridge.OnInvoke("kill",slayer,{monster="ShaleCrawler"})
eq(st(slayer).depth.slayer.quest.progress,0,"off-line monsters do not count")
bridge.OnInvoke("kill",slayer,{monster="BramblebackBoar"})
eq(st(slayer).depth.slayer.quest.progress,12,"slayer progress from monster XP")
bridge.OnInvoke("kill",slayer,{monster="GloomfangSpider"})
eq(st(slayer).depth.slayer.quest.progress,12,"other slayer line does not count")
slayer=rejoin(slayer)
eq(st(slayer).depth.slayer.quest.progress,12,"slayer quest persisted")
eq(bridge.OnInvoke("slayerBoss",slayer,{result="win"}).drops,nil,"boss cannot be won before ready")
eq(st(slayer).depth.slayer.quest~=nil,true,"premature win keeps quest")
bridge.OnInvoke("kill",slayer,{monster="BarkStalker"})
bridge.OnInvoke("kill",slayer,{monster="BarkStalker"})
local readyKill=bridge.OnInvoke("kill",slayer,{monster="BarkStalker"})
eq(readyKill.bossReady,true,"kill reports boss ready")
ok(has(slayer.last.message,"stirs"),"boss ready message")
eq(slayer.SlayerBossReady,"Bramble:1","boss attribute published")
eq(st(slayer).depth.slayer.quest.progress,150,"progress capped at needed")
bridge.OnInvoke("kill",slayer,{monster="BramblebackBoar"})
eq(st(slayer).depth.slayer.quest.progress,150,"ready quest stops counting")
eq(next(bridge.OnInvoke("slayerBoss",slayer,{result="maybe"})),nil,"invalid boss result ignored")
eq(next(bridge.OnInvoke("slayerBoss",slayer,nil)),nil,"missing boss payload ignored")
eq(st(slayer).depth.slayer.quest.bossReady,true,"invalid result keeps quest")
local victory=bridge.OnInvoke("slayerBoss",slayer,{result="win"})
eq(victory.drops.BeastHide,10,"boss tier drops rolled")
eq(victory.drops.SlayerToken,1,"boss guaranteed token")
local afterBoss=st(slayer)
eq(afterBoss.depth.slayer.quest,nil,"win clears quest")
eq(afterBoss.depth.slayer.lines.Bramble.xp,5,"slayer XP granted")
eq(afterBoss.depth.slayer.lines.Bramble.level,1,"slayer level 1")
eq(afterBoss.items.SlayerToken,1,"boss drops collected")
eq(slayer.SlayerBossReady,"","boss attribute cleared")
eq(next(bridge.OnInvoke("slayerBoss",slayer,{result="win"})),nil,"boss reward cannot repeat")
eq(cmd(slayer,"slayerAbandon").message,"You have no slayer quest.","abandon without quest")
cmd(slayer,"slayerBegin","Bramble:1")
local abandoned=cmd(slayer,"slayerAbandon")
eq(abandoned.depth.slayer.quest,nil,"abandon clears quest")
eq(abandoned.coins,afterBoss.coins-200,"abandon does not refund")
cmd(slayer,"slayerBegin","Bramble:1")
for _=1,3 do bridge.OnInvoke("kill",slayer,{monster="BarkStalker"}) end
eq(next(bridge.OnInvoke("slayerBoss",slayer,{result="fail"})),nil,"failed boss returns nothing")
local failed=st(slayer)
eq(failed.depth.slayer.quest,nil,"fail clears quest")
eq(failed.depth.slayer.lines.Bramble.xp,5,"fail grants no slayer XP")
eq(data.p300.profile.slayerXp.Bramble,0,"durable copy waits for save")
slayer=rejoin(slayer)
eq(data.p300.profile.slayerXp.Bramble,5,"slayer XP persisted")

-- Bridge ops: stats, kill drops, bestiary, damage, lease checks.
local fighter=seeded(310,function(p) p.bestiary={BramblebackBoar=9} end)
local sheet=bridge.OnInvoke("stats",fighter)
eq(sheet.stats.health,100,"bridge stats health")
eq(sheet.combatLevel,1,"bridge combat level")
eq(sheet.ironman,false,"bridge ironman flag")
eq(bridge.OnInvoke("stats",lateOpen),nil,"bridge refuses expired lease")
eq(bridge.OnInvoke("stats",{}),nil,"bridge refuses unknown player")
eq(bridge.OnInvoke("explode",fighter,{}),nil,"unknown bridge op")
eq(bridge.OnInvoke("kill",fighter,{monster="Dragon"}),nil,"unknown monster")
eq(bridge.OnInvoke("kill",fighter,"BramblebackBoar"),nil,"non-table payload")
eq(bridge.OnInvoke("kill",fighter,{monster=42}),nil,"non-string monster")
eq(bridge.OnInvoke("kill",lateOpen,{monster="BramblebackBoar"}),nil,"expired lease cannot earn kills")
rolls={0.1,0.5,0.1,0}
local loot=bridge.OnInvoke("kill",fighter,{monster="BramblebackBoar"})
eq(loot.drops.BeastHide,2,"seeded drop quantity")
eq(loot.drops.ArcaneDust,1,"seeded rare-ish drop")
local looted=st(fighter)
eq(looted.items.BeastHide,2,"drops added to inventory")
eq(looted.collection.ArcaneDust,1,"drops count toward collections")
eq(looted.coins,4,"monster coins")
eq(looted.xp.Combat,12,"monster XP")
eq(looted.depth.bestiary.BramblebackBoar,10,"bestiary incremented")
eq(looted.depth.stats.bestiaryTiers,1,"bestiary milestone reached")
eq(looted.depth.stats.health,101,"bestiary milestone health")
local fighterHum=hum(fighter)
eq(bridge.OnInvoke("damage",fighter,{amount=30}),30,"raw damage at zero defense")
eq(fighterHum.Health,71,"damage applied to humanoid")
for _,bad in ipairs({"10",-5,0,0/0}) do
	eq(bridge.OnInvoke("damage",fighter,{amount=bad}),0,"invalid damage ignored: "..tostring(bad))
end
eq(bridge.OnInvoke("damage",fighter,nil),0,"missing damage payload")
eq(fighterHum.Health,71,"invalid damage leaves health")
local guard=seeded(311,function(p)
	p.xp.Combat=X[5]
	p.items={BrassHelm=1,BrassChestplate=1,BrassGreaves=1,BrassBoots=1}
	p.equipment={helmet="BrassHelm",chest="BrassChestplate",legs="BrassGreaves",boots="BrassBoots"}
end)
local guardDefense=bridge.OnInvoke("stats",guard).stats.defense
eq(guardDefense,148,"bridge stats include armor")
eq(bridge.OnInvoke("damage",guard,{amount=100}),Progression.damageTaken(100,148),"defense reduces bridge damage")
ok(Progression.damageTaken(100,148)<100,"defense reduction is real")
fighterHum.Health=0
eq(bridge.OnInvoke("damage",fighter,{amount=10}),0,"dead humanoid takes no damage")

-- Regions generalised over Data.Regions.
local regionHook2=hook("IsleRegionAccess")
local scout=player(320)
eq(regionHook2.OnInvoke(scout,"Windpine").allowed,false,"Windpine locked")
eq(regionHook2.OnInvoke(scout,"Windpine").message,"Windpine Grove requires Woodcutting 10.","Windpine message")
eq(regionHook2.OnInvoke(scout,"Hub").allowed,true,"Hub open")
eq(regionHook2.OnInvoke(scout,"Meadow").message,"Welcome to Meadow Reach.","open region message")
eq(regionHook2.OnInvoke(scout,"Quarry").allowed,true,"Quarry open")
eq(regionHook2.OnInvoke(scout,"Skyreach").message,"Claim the Skyreach charter in your journal: Mining 3 and 3 lifetime Alloy Ingots.","Skyreach message compatible")
eq(regionHook2.OnInvoke(scout,"Tempest").allowed,false,"Tempest locked")
eq(regionHook2.OnInvoke(scout,"Atlantis").allowed,false,"unknown region")
eq(regionHook2.OnInvoke(scout,42).allowed,false,"non-string region")
scout=rejoin(scout,function(p) p.xp.Mining=X[30] end)
eq(regionHook2.OnInvoke(scout,"Gloomhollow").allowed,false,"Gloomhollow needs both skills")
eq(regionHook2.OnInvoke(scout,"Gloomhollow").message,"Gloomhollow Caverns requires Combat 15, Mining 30.","multi-skill message")
scout=rejoin(scout,function(p) p.xp.Combat=X[40]; p.xp.Woodcutting=X[10]; p.xp.Fishing=X[30] end)
for _,id in ipairs({"Windpine","Gloomhollow","Tidewater","Tempest"}) do
	eq(regionHook2.OnInvoke(scout,id).allowed,true,id.." unlocked by skills")
	eq(scout[id.."Unlocked"],true,id.." attribute published")
end
eq(regionHook2.OnInvoke(scout,"Skyreach").allowed,false,"Skyreach still needs the charter")
local regionList=st(scout).depth.regions
local skyreachRow
for _,row in ipairs(regionList) do if row.id=="Skyreach" then skyreachRow=row end end
eq(skyreachRow.requirement,"Complete 6 guild contracts","quest requirement text")
eq(skyreachRow.unlocked,false,"depth region lock state")
scout=rejoin(scout,function(p) p.questCompleted=6 end)
eq(regionHook2.OnInvoke(scout,"Skyreach").allowed,true,"quest count unlocks Skyreach")

-- Workers across Data.WorkerTiers and every gathering resource.
local foreman=seeded(330,function(p)
	p.items={Timber=200,Ore=200,AlloyIngot=40,AetherIngot=20}
	p.xp.Mining=X[15]; p.levelRewards.Mining=15
	p.collection={Brassite=50}; p.collectionRewards={Brassite=1}
end)
cmd(foreman,"worker")
ok(has(cmd(foreman,"workerAssign","1:SunsteelOre").message,"Mining 30"),"worker resource level gate")
eq(cmd(foreman,"workerAssign","1:Glassfin").workers[1].resource,"Ore","worker skill gate")
eq(cmd(foreman,"workerAssign","1:Brassite").workers[1].resource,"Brassite","worker assigned unlocked resource")
advance(241)
foreman=rejoin(foreman)
local brassClaim=cmd(foreman,"claim")
eq(brassClaim.items.Brassite,2,"worker gathers new resource")
eq(brassClaim.xp.Mining,X[15]+16,"worker XP scales with resource")
for _=2,4 do cmd(foreman,"workerUpgrade","1") end
local tier4=st(foreman)
eq(tier4.workers[1].tier,4,"worker reaches tier 4")
eq(tier4.workers[1].interval,48,"tier 4 interval")
eq(tier4.workers[1].capacity,480,"tier 4 capacity")
eq(tier4.items.AlloyIngot,36,"tier 4 consumes refined ingots")
for _=5,7 do cmd(foreman,"workerUpgrade","1") end
local tier7=st(foreman)
eq(tier7.workers[1].tier,7,"worker reaches tier 7")
eq(tier7.workers[1].interval,26,"tier 7 interval")
eq(tier7.workers[1].maxTier,7,"max tier exposed")
eq(tier7.items.AlloyIngot,0,"upgrade ladder cost")
eq(cmd(foreman,"workerUpgrade","1").message,"Worker is at maximum tier.","tier cap")
foreman=rejoin(foreman)
eq(st(foreman).workers[1].tier,7,"worker tier persisted")

-- Ironman, cross-verb abuse.
local loner=player(340)
cmd(loner,"ironman")
eq(bridge.OnInvoke("stats",loner).ironman,true,"bridge reports ironman")
eq(cmd(loner,"buy","Ore").message,"Ironman journals cannot use the player exchange.","Ironman still excluded")
eq(cmd(loner,"equip",string.rep("x",64)).depth.equipment.weapon,nil,"64-char unknown item handled")
eq(cmd(loner,"sell",string.rep("x",65)).message,"That request is too long.","65-char item rejected")
hum(loner).Health=0
eq(cmd(loner,"consume","CookedFish").message,"Return to your island first.","dead player cannot use Depth verbs")
print("Depth assertions: "..(checks-legacyChecks))
end)()
print("PASS: "..checks.." production gameplay/market/depth assertions.")
do
	local visitor=player(990)
	local msg=use(visitor,node("station","Forge")).message
	assert(msg:find("Forge open"),"station prompt answered: "..tostring(msg))
	assert(cmd(visitor,"station","Forge").message=="Unknown action.","station requires a world prompt")
	print("PASS: station prompt checks.")
end
