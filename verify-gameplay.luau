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
local db = {}
function db:UpdateAsync(key, op)
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
local services = {
	Players = {PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end},
	ProximityPromptService = {PromptTriggered=signal()},
	ReplicatedStorage = {},ServerStorage={},
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
eq(cmd(a,"claim").items.Ore,122,"worker payout")
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
eq(cmd(a,"proceeds","Ore").coins,15,"seller credited exactly once")
eq(cmd(a,"proceeds","Ore").coins,15,"proceeds cannot repeat")
cmd(a,"list","Ore")
eq(cmd(a,"cancel","Ore").items.Ore,119,"cancel restores escrow")
eq(cmd(a,"buy","Ore").coins,15,"empty market reimburses")
local boss=node("fight","Warden")
use(a,boss)
for _=1,5 do use(b,boss) end
eq(cmd(a,"state").items.Shard,1,"cooperative fight credit")
eq(cmd(b,"state").items.Shard,1,"second fighter credit")
use(c,boss)
eq(cmd(c,"state").items.Shard,nil,"Ironman independent encounter")
objects.BindableEvent.Event:Fire(a)
eq(cmd(a,"state").items.Stormglass,1,"expedition reward")
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
eq(cmd(a,"quest").coins,75,"first quest pays once")
eq(cmd(a,"quest").xp.Smithing,44,"second quest XP reward")
eq(cmd(a,"quest").coins,90,"worker contract reward")
eq(cmd(a,"quest").items.Tonic,2,"combat contract reward")
eq(cmd(a,"quest").coins,120,"expedition contract reward")
eq(cmd(a,"quest").coins,120,"completed chain cannot pay again")
services.Players.PlayerRemoving:Fire(a)
a=player(1)
eq(cmd(a,"state").quest.stage,6,"existing contracts stay claimed and reveal new charter on rejoin")
eq(cmd(a,"quest").coins,120,"rejoin cannot reclaim")
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
eq(cmd(a,"state").stats.maxHealth,105,"combat level increases permanent health")
eq(a.Character:FindFirstChildOfClass("Humanoid").MaxHealth,105,"stats applied to spawned humanoid")
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
eq(bonded.stats.maxHealth,115,"bond and combat health bonuses")
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
eq(cmd(fleet,"workerUpgrade","2").workers[2].capacity,240,"tier three capacity")
eq(cmd(fleet,"workerUpgrade","2").workers[2].tier,3,"worker upgrade cap")
eq(cmd(fleet,"state").items.Timber,50,"capped upgrade does not charge")
services.Players.PlayerRemoving:Fire(fleet)
advance(60*300)
fleet=player(50)
eq(cmd(fleet,"state").workers[2].tier,3,"worker tier survives rejoin")
eq(cmd(fleet,"state").workers[1].ready,120,"tier one independent cap")
eq(cmd(fleet,"workerClaim","2").items.Timber,290,"tier three offline capped payout")
eq(cmd(fleet,"workerClaim","2").items.Timber,290,"fleet cannot double claim")
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
eq(cmd(hunter,"slayerClaim").coins,before+20,"first hunt reward")
eq(cmd(hunter,"slayerClaim").coins,before+20,"hunt cannot claim twice")
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
eq(cmd(upgrading,"state").workers[1].capacity,180,"tier two capacity")
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
eq(cmd(smith,"state").levels.Mining,3,"ordinary Ore reaches advanced material gate")
eq(use(smith,aether).items.Aetherite,1,"Mining 3 unlocks Aetherite")
eq(cmd(smith,"state").xp.Mining,186,"Aetherite grants 18 Mining XP")
eq(cmd(smith,"craft","AetherIngot").items.Aetherite,1,"Smithing gate spends no material")
eq(cmd(smith,"state").xp.Smithing,24,"locked refinement awards no XP")
for _=1,20 do use(smith,wood) end
for _=1,9 do cmd(smith,"craft","AlloyIngot") end
eq(cmd(smith,"state").items.AlloyIngot,9,"basic refining is repeatable")
eq(cmd(smith,"state").xp.Smithing,168,"repeatable refining bridges Smithing progression")
eq(cmd(smith,"state").levels.Smithing,3,"refining reaches Smithing 3")
for _=1,13 do use(smith,aether) end
for _=1,7 do cmd(smith,"craft","AetherIngot") end
eq(cmd(smith,"state").items.AetherIngot,7,"advanced refining is repeatable")
eq(cmd(smith,"state").items.Aetherite,0,"advanced refining consumes raw mineral")
eq(cmd(smith,"state").items.AlloyIngot,2,"advanced refining consumes base ingots")
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
data.p90.profile.xp.Mining=159
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
eq(cmd(traveler,"quest").coins,25,"charter pays once")
eq(cmd(traveler,"state").regions[1].unlocked,true,"claimed charter unlocks region snapshot")
eq(traveler:GetAttribute("SkyreachUnlocked"),true,"charter publishes world unlock")
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,true,"charter opens authoritative transit")
eq(regionHook.OnInvoke(traveler,"Unknown").allowed,false,"unknown region rejected")
eq(cmd(traveler,"quest").coins,25,"repeated charter claim does not pay again")
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
eq(cmd(traveler,"state").xp.Mining,189,"rich seam retains controlled experience payout")
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
eq(cmd(traveler,"quest").coins,25,"equipment contract requires armor as well as tool")
services.Players.PlayerRemoving:Fire(traveler)
data.p90.profile.items.Skyplate=1
traveler=player(90)
eq(cmd(traveler,"quest").coins,100,"equipment contract pays final reward")
eq(cmd(traveler,"state").quest.complete,true,"bounded expanded chain can finish")
eq(cmd(traveler,"quest").coins,100,"final reward cannot repeat")
eq(regionHook.OnInvoke(lateOpen,"Skyreach").allowed,false,"expired session cannot use region transit")
traveler.Character:FindFirstChildOfClass("Humanoid").Health=0
eq(regionHook.OnInvoke(traveler,"Skyreach").allowed,false,"dead character cannot use region transit")
print("PASS: "..checks.." production gameplay/market assertions.")






