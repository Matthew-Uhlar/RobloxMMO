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
print("PASS: "..checks.." production gameplay/market assertions.")
