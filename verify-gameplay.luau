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
-- Economy keys (bazaar_v1_*, auction_v1_*): "before" fails without committing,
-- "after" commits and then loses the acknowledgement; repeatEcon retries transforms.
local econFailure, repeatEcon, econReadFailure = nil, false, false
local db = {}
function db:GetAsync(key)
	db.reads=(db.reads or 0)+1
	if econReadFailure and (key:match("^bazaar") or key:match("^auction")) then econReadFailure=false; error("Injected read outage") end
	return copy(data[key])
end
function db:UpdateAsync(key, op)
	db.writes=(db.writes or 0)+1
	if db.onUpdate and key:match("^p%d") then local hook=db.onUpdate; db.onUpdate=nil; hook(key) end
	local econKey = key:match("^bazaar") or key:match("^auction")
	if econKey and econFailure=="before" then econFailure=nil; error("Injected outage before commit") end
	if repeatMarketTransform and key:match("^market") then op(copy(data[key])) end
	if repeatEcon and econKey then op(copy(data[key])) end
	local value = op(copy(data[key]))
	if value then data[key] = copy(value) end
	if econKey and value then db.econWrites=(db.econWrites or 0)+1 end
	if econKey and econFailure=="after" then econFailure=nil; error("Injected lost acknowledgement after durable commit") end
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
local guidCount = 0
local services = {
	Players = {PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end},
	ProximityPromptService = {PromptTriggered=signal()},
	ReplicatedStorage = {WaitForChild=function(_, name) return assert(markers[name], name) end},ServerStorage={},
	DataStoreService = {GetDataStore=function() return db end},
	HttpService = {GenerateGUID=function() guidCount+=1; return if guidCount==1 then "test-instance" else "test-guid-"..guidCount end},
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
local function player(id,deferred)
	local humanoid={Health=100,MaxHealth=100,Died=signal(),TakeDamage=function(self,n) self.Health-=n end}
	local root={Position=Vector3.zero}
	local p={GetAttribute=function(self,key) return self[key] end,SetAttribute=function(self,key,value) self[key]=value end,UserId=id,Parent=true,CharacterAdded=signal(),Kick=function(self,why) self.kicked=why end}
	p.Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end,
		WaitForChild=function() return humanoid end}
	if not deferred then services.Players.PlayerAdded:Fire(p) end
	return p
end
local function cmd(p,verb,item)
	advance(1)
	return objects.RemoteFunction.OnServerInvoke(p,verb,item)
end
-- Writing market verbs share a per-player exchange cooldown (6 s). Each order
-- also spends two tokens of the per-player market DataStore budget (0.1/s), so
-- the server clock moves on 20 s per trade (game time only 6 s).
local function trade(p,verb,item)
	advance(6)
	clock+=14
	return cmd(p,verb,item)
end
local function node(verb,item,distance,owner,region)
	return {Enabled=true,MaxActivationDistance=10,GetAttribute=function(_,key)
		return ({IsleAction=verb,IsleItem=item,OwnerUserId=owner,IsleRegion=region})[key]
	end,FindFirstAncestorWhichIsA=function() return {Position=Vector3.new(distance or 0,0,0)} end}
end
-- Resource nodes deplete per player per prompt for Data.ResourceTiers respawn
-- seconds; `use` waits out a node's regrowth (as a player would) before gathering.
local harvestedAt=setmetatable({},{__mode="k"})
local function rawUse(p,n)
	services.ProximityPromptService.PromptTriggered:Fire(n,p)
	return p.last
end
local function use(p,n)
	advance(1)
	local item=n:GetAttribute("IsleItem")
	local resource=n:GetAttribute("IsleAction")=="gather" and type(item)=="string" and Progression.resource(item)
	local last=resource and harvestedAt[n] and harvestedAt[n][p]
	if last and clock-last<resource.respawn then advance(resource.respawn-(clock-last)) end
	local state=rawUse(p,n)
	if resource and state and type(state.message)=="string" and state.message:sub(1,1)=="+" then
		harvestedAt[n]=harvestedAt[n] or setmetatable({},{__mode="k"})
		harvestedAt[n][p]=clock
	end
	return state
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
eq(trade(c,"buy","Ore").message,"Ironman journals cannot use the player exchange.","Ironman exclusion")
for _=1,4 do use(b,ore) end
eq(cmd(b,"sell","Ore").coins,16,"merchant payout")
eq(cmd(b,"deposit").bank,16,"deposit")
b.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
eq(cmd(b,"withdraw").coins,16,"bank survives death")
eq(trade(a,"list","Ore").items.Ore,119,"listing reserves bundle")
injectedFailure=true
eq(trade(b,"buy","Ore").coins,1,"purchase reservation on lost acknowledgement")
services.Players.PlayerRemoving:Fire(b)
b=player(2)
eq(cmd(b,"state").items.Ore,3,"replayed purchase delivered once")
eq(cmd(b,"state").coins,1,"replayed purchase charged once")
eq(trade(a,"proceeds","Ore").coins,aBonus+15,"seller credited exactly once")
eq(trade(a,"proceeds","Ore").coins,aBonus+15,"proceeds cannot repeat")
trade(a,"list","Ore")
eq(trade(a,"cancel","Ore").items.Ore,119,"cancel restores escrow")
eq(trade(a,"buy","Ore").coins,aBonus+15,"empty market reimburses")
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
-- A journal leased by another server is refused. (Same-server rejoins wait for
-- the previous session instead; see the rejoin regression block at the end.)
data.p4={owner="other-server",expires=utc+200,profile=copy(data.p1.profile)}
local duplicate=player(4)
eq(duplicate.kicked~=nil,true,"foreign lease rejects duplicate session")
data.p4=nil
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
local stalled=trade(lateSave,"buy","Ore")
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
-- Node regrowth makes these harvests take real time; rejoin to renew the 180 s lease
-- (tests have no autosave loop).
services.Players.PlayerRemoving:Fire(smith)
smith=player(80)
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
eq(trade(highSeller,"list","Fish:30").items.Fish,9,"custom ask reserves exactly one lot")
trade(olderSeller,"list","Fish:12")
trade(newerSeller,"list","Fish:12")
trade(bidder,"list","Fish:5")
eq(#data.market_v1_Fish.pricedOrders,4,"repeated transforms do not duplicate listings")
eq(data.market_v1_Fish.nextPricedOrder,4,"order sequence deterministic under transform retry")
local fishQuote=cmd(bidder,"market","Fish").market
eq(fishQuote.bestAsk,12,"quote excludes buyer's cheaper own listing")
eq(fishQuote.openLots,4,"quote shows lot count")
eq(fishQuote.ownLots,1,"quote shows own lots")
eq(fishQuote.lotSize,3,"quote states three-unit quantity")
eq(fishQuote.maxPrice,10000,"quote advertises price limit")
eq(trade(bidder,"buy","Fish:20").coins,88,"best ask fills with price-improvement refund")
eq(data.market_v1_Fish.proceeds["101"],12,"oldest equal-price seller fills first")
eq(data.market_v1_Fish.proceeds["102"],nil,"newer equal-price ask waits")
eq(data.market_v1_Fish.proceeds["100"],nil,"expensive oldest ask does not jump price priority")
eq(trade(bidder,"buy","Fish:12").coins,76,"second equal-price ask fills next")
eq(data.market_v1_Fish.proceeds["102"],12,"second seller credited actual ask")
eq(trade(bidder,"buy","Fish:10").coins,76,"limit below market reimburses reservation")
eq(cmd(bidder,"state").items.Fish,15,"no-match does not deliver goods")
eq(trade(bidder,"cancel","Fish").items.Fish,18,"cancel returns own priced goods")
eq(trade(olderSeller,"proceeds","Fish").coins,12,"seller collects actual ask proceeds")
eq(trade(olderSeller,"proceeds","Fish").coins,12,"priced proceeds cannot replay")
for _,bad in ipairs({"Fish:0","Fish:10001","Fish:-1","Fish:1.5","Fish:1e3","Fish:nan","Fish: 12","Fish:12:2"}) do
	local invalid=trade(newerSeller,"list",bad)
	eq(invalid.items.Fish,9,"invalid ask cannot reserve goods: "..bad)
end
eq(trade(newerSeller,"list","Aetherite:5").items.Fish,9,"unsupported commodity rejected")
eq(trade(bidder,"buy","Fish:10000").coins,76,"unfunded buy limit rejected without debit")
local recoveryBuyer=marketPlayer(104,200,{})
injectedFailure=true
eq(trade(recoveryBuyer,"buy","Fish:50").coins,150,"ambiguous purchase retains full durable reservation")
services.Players.PlayerRemoving:Fire(recoveryBuyer)
eq(data.p104.profile.pricedPending.price,50,"pending purchase persists custom limit")
recoveryBuyer=player(104)
eq(cmd(recoveryBuyer,"state").coins,170,"rejoin returns exact price-improvement once")
eq(cmd(recoveryBuyer,"state").items.Fish,3,"rejoin delivers priced purchase once")
eq(trade(highSeller,"proceeds","Fish").coins,30,"lost acknowledgement credits seller exactly once")
eq(trade(highSeller,"proceeds","Fish").coins,30,"seller cannot recollect recovered sale")
-- Migration keeps the existing market key, seller balances, receipts and FIFO.
local legacySeller=marketPlayer(110,0,{})
services.Players.PlayerRemoving:Fire(legacySeller)
data.p110.profile.marketSeq=1
legacySeller=player(110)
data.market_v1_Herb={orders={"110"},proceeds={},receipts={['110']={seq=1,coins=0,units=0,text="legacy listing"}},accounts=1}
local legacyBuyer=marketPlayer(111,100,{})
eq(cmd(legacyBuyer,"market","Herb").market.bestAsk,9,"legacy lot quotes original fixed price")
eq(trade(legacyBuyer,"buy","Herb:20").coins,91,"legacy lot fills at original price")
eq(data.market_v1_Herb.version,2,"legacy book migrates in place")
eq(trade(legacySeller,"proceeds","Herb").coins,9,"migrated seller proceeds preserved")
local oldPending=marketPlayer(112,91,{})
services.Players.PlayerRemoving:Fire(oldPending)
data.p112.profile.marketSeq=1
data.p112.profile.pending={seq=1,verb="buy",item="Herb"}
data.market_v1_Herb.orders={"113"}
oldPending=player(112)
eq(cmd(oldPending,"state").coins,91,"legacy pending buy uses historical reserved amount")
eq(cmd(oldPending,"state").items.Herb,3,"legacy pending buy still delivers")
eq(data.market_v1_Herb.proceeds['113'],9,"legacy pending seller paid historical price")
eq(trade(c,"list","Fish:10").message,"Waiting for journal sync.","expired journal cannot open priced asks")
local ironTrader=marketPlayer(114,100,{Fish=3})
cmd(ironTrader,"ironman")
eq(trade(ironTrader,"buy","Fish:10").coins,100,"Ironman priced buy cannot reserve coins")
eq(cmd(ironTrader,"market","Fish").market,nil,"Ironman cannot query player market")
local replaySeller=marketPlayer(115,0,{Timber=6})
injectedFailure=true
eq(trade(replaySeller,"list","Timber:37").items.Timber,3,"ambiguous priced listing holds goods in escrow")
services.Players.PlayerRemoving:Fire(replaySeller)
replaySeller=player(115)
eq(cmd(replaySeller,"state").items.Timber,3,"listing recovery cannot duplicate reserved goods")
eq(#data.market_v1_Timber.pricedOrders,1,"listing recovery creates only one order")
eq(data.market_v1_Timber.pricedOrders[1].price,37,"listing recovery retains chosen ask")
injectedFailure=true
trade(replaySeller,"cancel","Timber")
services.Players.PlayerRemoving:Fire(replaySeller)
replaySeller=player(115)
eq(cmd(replaySeller,"state").items.Timber,6,"cancellation recovery returns escrow once")
eq(#data.market_v1_Timber.pricedOrders,0,"recovered cancellation removes order once")
trade(replaySeller,"list","Timber:23")
local replayBuyer=marketPlayer(116,40,{})
trade(replayBuyer,"buy","Timber:30")
injectedFailure=true
eq(trade(replaySeller,"proceeds","Timber").coins,0,"ambiguous proceeds wait for receipt recovery")
services.Players.PlayerRemoving:Fire(replaySeller)
replaySeller=player(115)
eq(cmd(replaySeller,"state").coins,23,"proceeds recovery grants actual ask once")
eq(trade(replaySeller,"proceeds","Timber").coins,23,"recovered proceeds cannot repeat")
-- Two distinct old fixed-price lots retain their FIFO order when both migrate.
data.market_v1_Ore.orders={"117","118"}
data.market_v1_Ore.nextOrder=nil
local migrationBuyer=marketPlayer(119,50,{})
trade(migrationBuyer,"buy","Ore:20")
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
trade(mixedSeller,"list","Fish:9")
eq(data.market_v1_Fish.receipts['120'].seq,0,"priced user registers harmless legacy receipt")
eq(data.market_v1_Fish.accounts,1,"priced user counts toward shared legacy account limit")
oldMarket('121','list','Fish',1)
eq(data.market_v1_Fish.orders[1],'121',"old listing after new write retains string seller")
eq(#data.market_v1_Fish.pricedOrders,1,"old listing preserves separately priced lots")
oldMarket('122','buy','Fish',1)
eq(data.market_v1_Fish.proceeds['121'],18,"old buyer after new writer pays fixed lot price")
eq(#data.market_v1_Fish.pricedOrders,1,"old buyer cannot misprice new custom lot")
local mixedBuyer=marketPlayer(123,100,{})
eq(trade(mixedBuyer,"buy","Fish:20").coins,91,"new buyer after old writer matches custom ask")
oldMarket('120','proceeds','Fish',1)
eq(data.market_v1_Fish.receipts['120'].coins,9,"old server can collect shared priced proceeds")
eq(data.market_v1_Fish.accounts,4,"old action reuses priced user's account registration")
eq(data.market_v1_Fish.pricedReceipts['120'].units,0,"old receipt cannot overwrite new receipt stream")
oldMarket('124','list','Fish',1)
trade(mixedSeller,"list","Fish:18")
trade(mixedBuyer,"buy","Fish:20")
eq(data.market_v1_Fish.proceeds['124'],18,"equal-price mixed queues prioritize legacy lot")
eq(#data.market_v1_Fish.pricedOrders,1,"mixed queue tie leaves priced lot intact")
trade(mixedBuyer,"buy","Fish:20")
eq(#data.market_v1_Fish.pricedOrders,0,"new buyer can consume remaining priced lot")
-- Actual baseline open reuses old.profile, and persist table.clone's the whole
-- profile then clones known nested maps/workers. Unknown additive fields survive.
local hopper=marketPlayer(130,200,{})
local hopSeller=marketPlayer(131,0,{Fish=3})
trade(hopSeller,"list","Fish:23")
injectedFailure=true
eq(trade(hopper,"buy","Fish:40").coins,160,"hop fixture retains priced reservation")
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
eq(trade(capped,"list","Timber:100").items.Timber,3,"combined receipt budget returns unallocated escrow")
eq(data.market_v1_Timber.pricedAccounts,2000,"new writer cannot exceed shared account budget")
data.market_v1_Timber.proceeds['3000']=57
local existingSeller=marketPlayer(3000,0,{})
eq(trade(existingSeller,"proceeds","Timber").coins,57,"existing legacy seller can collect at full shared capacity")
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
-- L6: the Observatory grant reports whether the profile accepted the chest.
do
	local grant=hook("IsleExpeditionGrant")
	eq(grant~=nil and grant.Parent==services.ServerStorage,true,"expedition grant function published")
	local delver=player(4400)
	local gated=grant.OnInvoke(delver,{floor=2,grade="B",score=200,partySize=1,damageShare=1})
	eq(gated.ok,false,"floor gate refuses the grant")
	eq(gated.reason:find("Dungeoneering",1,true)~=nil,true,"floor gate reason returned")
	eq(cmd(delver,"state").items.Stormglass,nil,"refused grant pays nothing")
	eq(grant.OnInvoke(delver,{floor=1,grade="B",score=200,partySize=1,damageShare=1}).ok,true,"eligible clear accepted")
	eq(cmd(delver,"state").items.Stormglass,1,"accepted grant pays the chest")
	local cooling=grant.OnInvoke(delver,{floor=1,grade="B",score=200,partySize=1,damageShare=1})
	eq(cooling.ok==false and cooling.reason:find("cooling down",1,true)~=nil,true,"profile cooldown refusal reported")
	eq(grant.OnInvoke({UserId=4401},{floor=1}).ok,false,"no live journal refuses")
end
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
-- Combat pays the kill's melee damage XP through "combatXp", then reports the kill.
local paid=bridge.OnInvoke("combatXp",brawler,{style="melee",monster="StarbornSentinel",damage=Data.Monsters.StarbornSentinel.hp})
eq(paid.xp.Combat,Data.Monsters.StarbornSentinel.xp,"a whole melee kill pays monster.xp Combat XP")
ok(has(brawler.last.message,"Combat level 6! +500 coins"),"multi-level reward message")
local killed=bridge.OnInvoke("kill",brawler,{monster="StarbornSentinel"})
eq(next(killed.drops),nil,"high rolls drop nothing")
eq(killed.bossReady,false,"no quest means no boss")
ok(has(brawler.last.message,"Starborn Sentinel slain"),"kill pushes a snapshot message")
ok(not has(brawler.last.message,"Combat XP"),"the kill itself pays no flat Combat XP")
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
bridge.OnInvoke("combatXp",tamer,{style="melee",monster="BramblebackBoar",damage=Data.Monsters.BramblebackBoar.hp}); bridge.OnInvoke("kill",tamer,{monster="BramblebackBoar"})
eq(st(tamer).depth.pets[1].xp,12,"pet earns full XP of its skill")
use(tamer,ore)
eq(st(tamer).depth.pets[1].xp,15,"pet earns 25% of other skills")
tamer.last=nil
bridge.OnInvoke("combatXp",tamer,{style="melee",monster="StarbornSentinel",damage=Data.Monsters.StarbornSentinel.hp})
local petMessage=tamer.last and tamer.last.message
bridge.OnInvoke("kill",tamer,{monster="StarbornSentinel"})
ok(has(petMessage,"Emberfox pet level 2!") or has(tamer.last.message,"Emberfox pet level 2!"),"pet level message")
local grown=st(tamer)
eq(grown.depth.pets[1].level,2,"pet levels up")
eq(grown.depth.pets[1].xp,535-Data.petXpToNext(1,"Epic"),"pet XP carries over")
eq(cmd(tamer,"petSummon","0").depth.pets[1].active,false,"pet dismissed")
ok(has(cmd(tamer,"petSummon","0").message,"No pet"),"double dismiss message")
bridge.OnInvoke("combatXp",tamer,{style="melee",monster="BramblebackBoar",damage=Data.Monsters.BramblebackBoar.hp}); bridge.OnInvoke("kill",tamer,{monster="BramblebackBoar"})
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
eq(bridge.OnInvoke("slayerBoss",slayer,{result="maybe"}).ok,false,"invalid boss result ignored")
eq(bridge.OnInvoke("slayerBoss",slayer,nil).ok,false,"missing boss payload ignored")
eq(st(slayer).depth.slayer.quest.bossReady,true,"invalid result keeps quest")
local victory=bridge.OnInvoke("slayerBoss",slayer,{result="win"})
eq(victory.ok,true,"boss win report accepted")
eq(victory.drops.BeastHide,10,"boss tier drops rolled")
eq(victory.drops.SlayerToken,1,"boss guaranteed token")
local afterBoss=st(slayer)
eq(afterBoss.depth.slayer.quest,nil,"win clears quest")
eq(afterBoss.depth.slayer.lines.Bramble.xp,5,"slayer XP granted")
eq(afterBoss.depth.slayer.lines.Bramble.level,1,"slayer level 1")
eq(afterBoss.items.SlayerToken,1,"boss drops collected")
eq(slayer.SlayerBossReady,"","boss attribute cleared")
eq(bridge.OnInvoke("slayerBoss",slayer,{result="win"}).ok,false,"boss reward cannot repeat")
eq(cmd(slayer,"slayerAbandon").message,"You have no slayer quest.","abandon without quest")
cmd(slayer,"slayerBegin","Bramble:1")
local abandoned=cmd(slayer,"slayerAbandon")
eq(abandoned.depth.slayer.quest,nil,"abandon clears quest")
eq(abandoned.coins,afterBoss.coins-200,"abandon does not refund")
cmd(slayer,"slayerBegin","Bramble:1")
for _=1,3 do bridge.OnInvoke("kill",slayer,{monster="BarkStalker"}) end
local failReport=bridge.OnInvoke("slayerBoss",slayer,{result="fail"})
eq(failReport.ok,true,"failed boss report accepted")
eq(failReport.drops,nil,"failed boss returns no drops")
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
eq(looted.xp.Combat,0,"the kill op pays no flat Combat XP (damage XP arrives via combatXp)")
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
eq(trade(loner,"buy","Ore").message,"Ironman journals cannot use the player exchange.","Ironman still excluded")
eq(cmd(loner,"equip",string.rep("x",64)).depth.equipment.weapon,nil,"64-char unknown item handled")
eq(cmd(loner,"sell",string.rep("x",65)).message,"That request is too long.","65-char item rejected")
hum(loner).Health=0
eq(cmd(loner,"consume","CookedFish").message,"Return to your island first.","dead player cannot use Depth verbs")
print("Depth assertions: "..(checks-legacyChecks))
end)()
------------------------------------------------------------------------------
-- Review regressions (H1, H2, M3, L1-L4, node regrowth).
------------------------------------------------------------------------------
do
	local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
	local function hum(p) return p.Character:FindFirstChildOfClass("Humanoid") end
	local function seeded(id,mutate)
		local p=player(id)
		services.Players.PlayerRemoving:Fire(p)
		mutate(data["p"..id].profile)
		return player(id)
	end
	local function close(actual,expected,case) eq(math.abs(actual-expected)<1e-6,true,case.." ("..tostring(actual)..")") end
	local bridge
	for _,o in ipairs(allObjects) do if o.Name=="IsleBridge" then bridge=o end end

	-- H1: MaxHealth changes keep the health fraction; toggling gear never heals.
	local toggler=seeded(600,function(p)
		p.items={MeadowCharm=1,BrassHelm=1}
		p.xp.Combat=Data.XP_TABLE[5]; p.levelRewards.Combat=5
	end)
	local h=hum(toggler)
	h.Health=50
	local on=cmd(toggler,"accessory","MeadowCharm")
	eq(h.MaxHealth,on.depth.stats.health,"accessory raises MaxHealth")
	close(h.Health,50/100*h.MaxHealth,"accessory keeps the health fraction instead of adding the increase")
	for _=1,5 do cmd(toggler,"accessory","MeadowCharm") end
	eq(h.MaxHealth,100,"accessory removed after an even number of toggles")
	close(h.Health,50,"accessory toggling heals nothing")
	for _=1,3 do cmd(toggler,"equip","BrassHelm"); cmd(toggler,"unequip","helmet") end
	close(h.Health,50,"equip/unequip toggling heals nothing")
	local worn=cmd(toggler,"accessory","MeadowCharm").depth.stats.health
	h.Health=0
	eq(cmd(toggler,"state").depth.stats.health,worn,"stat sheet unchanged while dead")
	-- A freshly spawned character still receives its full sheet.
	local spawned={Health=100,MaxHealth=100,Died=signal(),TakeDamage=function(self,n) self.Health-=n end}
	local root={Position=Vector3.zero}
	toggler.Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return spawned end,WaitForChild=function() return spawned end}
	toggler.CharacterAdded:Fire(toggler.Character)
	eq(spawned.MaxHealth,worn,"spawn applies the stat sheet")
	eq(spawned.Health,worn,"spawn grants the raw increase")

	-- H2: writing market verbs are paced; empty cancels skip the DataStore.
	local spammer=seeded(601,function(p) p.items={Fish=6}; p.coins=50 end)
	eq(trade(spammer,"list","Fish:20").items.Fish,3,"first listing settles")
	local writes=db.writes
	local spam=cmd(spammer,"proceeds","Fish")
	eq(has(spam.message,"still recording"),true,"proceeds inside the exchange cooldown refused")
	eq(cmd(spammer,"list","Fish:20").items.Fish,3,"listing inside the cooldown reserves nothing")
	eq(cmd(spammer,"buy","Fish:20").coins,50,"buy inside the cooldown reserves nothing")
	eq(db.writes,writes,"cooldown spam performs no DataStore writes")
	advance(6)
	eq(cmd(spammer,"cancel","Fish").items.Fish,6,"cancel after the cooldown settles")
	eq(cmd(spammer,"state").market.ownLots,0,"view tracks own lots")
	writes=db.writes
	advance(6)
	eq(cmd(spammer,"cancel","Fish").message,"You have no open listing here.","cached view answers an empty cancel")
	eq(db.writes,writes,"empty cancel skips the DataStore round-trip")
	eq(has(cmd(spammer,"list","Fish:20").message,"Listed 3"),true,"empty cancel does not start the cooldown")
	writes=db.writes
	eq(has(cmd(spammer,"cancel","Fish").message,"still recording"),true,"own lot cancel waits for the cooldown")
	eq(db.writes,writes,"refused cancel does not write")
	local other=seeded(602,function(p) p.coins=50 end)
	cmd(other,"market","Fish")
	advance(6)
	eq(cmd(other,"cancel","Fish").message,"You have no open listing here.","another trader's lots are not own lots")

	-- M3: a same-server rejoin waits for the previous session to finish saving.
	local first=player(603)
	use(first,ore)
	local second=player(603,true)
	local joining=coroutine.create(function() services.Players.PlayerAdded:Fire(second) end)
	assert(coroutine.resume(joining))
	eq(coroutine.status(joining),"suspended","rejoin waits while the old session is live")
	eq(cmd(second,"state").loading,true,"waiting session has no journal yet")
	services.Players.PlayerRemoving:Fire(first)
	assert(coroutine.resume(joining))
	eq(coroutine.status(joining),"dead","rejoin proceeds once the old session closed")
	eq(cmd(second,"state").items.Ore,1,"rejoin loads the final save, not a stale autosave")
	eq(string.match(data.p603.owner,"^test%-instance#%d+$")~=nil,true,"lease owner carries a session token")
	local stuck=player(604)
	local late=player(604,true)
	local blocked=coroutine.create(function() services.Players.PlayerAdded:Fire(late) end)
	assert(coroutine.resume(blocked))
	advance(16)
	assert(coroutine.resume(blocked))
	eq(has(late.kicked,"still saving"),true,"rejoin gives up after the bounded wait")
	eq(cmd(stuck,"state").items~=nil,true,"timed-out rejoin leaves the live session intact")
	services.Players.PlayerRemoving:Fire(stuck)

	-- L1: a player who leaves while the journal loads leaves nothing behind.
	local leaver=player(605,true)
	db.onUpdate=function() leaver.Parent=nil end
	services.Players.PlayerAdded:Fire(leaver)
	eq(data.p605.owner,"","abandoned open releases the lease")
	eq(cmd(leaver,"state").loading,true,"abandoned open keeps no profile")
	eq(bridge.OnInvoke("stats",leaver),nil,"abandoned open keeps no live lease")
	services.Players.PlayerRemoving:Fire(leaver)
	local returning=player(605)
	eq(returning.kicked,nil,"abandoned open does not block the next session")
	eq(cmd(returning,"state").loading,nil,"next session opens immediately")

	-- L2: an unapplied boss report tells Combat so it can re-arm.
	eq(bridge.OnInvoke("slayerBoss",lateOpen,{result="win"}).ok,false,"lapsed lease reports boss failure")

	-- L3: migration drops unknown or malformed pets and keeps the active pointer.
	local keeper=seeded(606,function(p)
		p.pets={{id="Nope",level=1,xp=0},{id="Emberfox",level=2,xp=5},{id="Emberfox",xp=0},"junk"}
		p.activePet=2
	end)
	local pets=cmd(keeper,"state").depth.pets
	eq(#pets,1,"invalid pets dropped on migration")
	eq(pets[1].level,2,"valid pet kept")
	eq(pets[1].active,true,"active pet index remapped")
	eq(has(cmd(keeper,"petSummon","2").message,"Choose a pet you have adopted"),true,"summoning a missing pet is refused")

	-- L4: full state snapshots are throttled to twice a second.
	local poller=player(607)
	advance(1)
	eq(objects.RemoteFunction.OnServerInvoke(poller,"state")~=nil,true,"first state poll answered")
	advance(0.1)
	eq(objects.RemoteFunction.OnServerInvoke(poller,"state"),nil,"rapid state poll throttled")
	advance(0.5)
	eq(objects.RemoteFunction.OnServerInvoke(poller,"state")~=nil,true,"state poll answered after the interval")

	-- Node regrowth: per player, per prompt, for Data.ResourceTiers respawn seconds.
	local nodeA,nodeB=node("gather","Ore"),node("gather","Ore")
	local picker,neighbour=player(608),player(609)
	advance(1)
	eq(rawUse(picker,nodeA).items.Ore,1,"first harvest")
	advance(1)
	local regrowing=rawUse(picker,nodeA)
	eq(regrowing.message,"This node is regrowing (2s).","depleted node refuses the same player")
	eq(regrowing.items.Ore,1,"depleted node pays nothing")
	eq(rawUse(neighbour,nodeA).items.Ore,1,"another player can harvest the same node")
	advance(1)
	eq(rawUse(picker,nodeB).items.Ore,2,"a different node is unaffected")
	advance(1)
	eq(rawUse(picker,nodeA).items.Ore,3,"node regrows after its respawn time")
	print("PASS: review regression checks.")
end
;(function()
------------------------------------------------------------------------------
-- Economy: Bazaar standing orders and the Auction House (Data.Economy).
------------------------------------------------------------------------------
local before=checks
local Rules=Data.Economy
-- Requests here advance only os.clock (cooldowns); journal leases follow os.time,
-- which moves only where a test needs listings to expire.
local function cmd(p,verb,item)
	clock+=1
	return objects.RemoteFunction.OnServerInvoke(p,verb,item)
end
-- Orders also spend two tokens of the per-player market budget (0.1/s): 20 s each.
local function trade(p,verb,item)
	clock+=20
	return cmd(p,verb,item)
end
local function ok(cond,case) assert(cond,case); checks+=1 end
local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
local function econPlayer(id,coins,items,mutate)
	local p=player(id)
	services.Players.PlayerRemoving:Fire(p)
	local profile=data["p"..id].profile
	profile.coins=coins
	profile.items=items or {}
	if mutate then mutate(profile) end
	return player(id)
end
local function rejoin(p)
	services.Players.PlayerRemoving:Fire(p)
	return player(p.UserId)
end
local function st(p) return cmd(p,"state") end
local function econ(p) return st(p).economy end
local function bazaar(item) return data["bazaar_v1_"..item] end
local function auction(cat) return data["auction_v1_"..cat] end
local function orderId(p,item,side)
	for _,o in ipairs(econ(p).orders) do if o.item==item and (side==nil or o.side==side) then return o.id end end
	return nil
end
local function listingId(p,item)
	for _,l in ipairs(econ(p).listings) do if l.item==item then return l.id,l.cat end end
	return nil
end

-- Shared data contract.
eq(Rules.auctionFee(1000),10,"listing fee is 1%")
eq(Rules.auctionFee(150),2,"listing fee rounds up")
eq(Rules.auctionFee(5),1,"listing fee is at least one coin")
eq(Rules.isCommodity("Brassite"),true,"resources are Bazaar commodities")
eq(Rules.isCommodity("BeastHide"),true,"materials are Bazaar commodities")
eq(Rules.isCommodity("BrassSword"),false,"gear is not a commodity")
eq(Rules.auctionCategory("BrassSword"),"weapon","weapons auction under weapon")
eq(Rules.auctionCategory("EmberfoxPet"),"pet","pet items auction under pet")
eq(Rules.auctionCategory("Ore"),nil,"commodities are not auctionable")

-- Bad input never escrows anything.
local probe=econPlayer(2000,500,{Brassite=50,BrassSword=1})
for _,bad in ipairs({"Brassite:0:5","Brassite:641:5","Brassite:5:0","Brassite:5:1000001","Brassite:5:-1","Brassite:5:1.5",
	"Brassite:5:1e3","Brassite: 5:5","Brassite:5:5:5","BrassSword:1:5","Nope:1:1","","Brassite","Brassite:0005:5","Brassite:5:00000005"}) do
	local s=trade(probe,"bid",bad)
	eq(s.coins,500,"invalid bid escrows nothing: "..bad)
end
for _,bad in ipairs({"Brassite:0","Brassite:641","Brassite:5:0","BrassSword:1","Brassite:-3"}) do
	eq(trade(probe,"sellToBid",bad).items.Brassite,50,"invalid instant sell escrows nothing: "..bad)
end
eq(trade(probe,"offer","Brassite:51:5").items.Brassite,50,"offer cannot exceed satchel")
eq(has(trade(probe,"bid","Brassite:100:6").message,"You need 600 purse coins"),true,"unfunded bid refused")
for _,bad in ipairs({"BrassSword:0","BrassSword:1000001","Brassite:5","BrassSword","BrassSword:5:5","Nope:5","BrassSword:1.5"}) do
	local s=trade(probe,"ahList",bad)
	eq(s.items.BrassSword==1 and s.coins==500,true,"invalid listing escrows nothing: "..bad)
end
for _,bad in ipairs({"weapon:1","weapon:x:5","nope:1:5","weapon:1:0","weapon:0:5","weapon:1:5:5"}) do
	eq(trade(probe,"ahBuy",bad).coins,500,"invalid purchase escrows nothing: "..bad)
end
eq(has(trade(probe,"ahBuy","weapon:1:600").message,"You need 600 purse coins"),true,"unfunded purchase refused")
eq(has(trade(probe,"ahCancel","nope:1").message,"auction category"),true,"bad cancel category refused")
eq(has(trade(probe,"ahClaim","weapon:1").message,"auction category"),true,"bad claim refused")
eq(has(trade(probe,"bidCancel","Brassite:x").message,"Bazaar commodity"),true,"bad order number refused")
eq(has(cmd(probe,"bazaar","BrassSword").message,"Bazaar commodity"),true,"gear has no order book")
clock+=3
eq(has(cmd(probe,"ahBrowse","nope").message,"auction category"),true,"unknown auction category")
clock+=3
eq(has(cmd(probe,"ahBrowse","weapon:0").message,"auction category"),true,"page zero refused")
clock+=3
eq(cmd(probe,"ahBrowse","weapon:50").economy.auction.page,1,"page past the end clamps to the last page")
eq(probe.kicked,nil,"bad input never disturbs the session")
eq(bazaar("Nope"),nil,"bad input never creates a book")

-- Bazaar matching: highest bid first, FIFO at equal price, maker's price.
local seller=econPlayer(2001,0,{Brassite=100})
local b1=econPlayer(2002,10000,{})
local b2=econPlayer(2003,10000,{})
local b3=econPlayer(2004,10000,{})
repeatEcon=true
local placed=trade(b1,"bid","Brassite:10:20")
eq(placed.coins,9800,"bid escrows quantity x price")
eq(has(placed.message,"Buy order #1"),true,"bid confirms its order number")
eq(#placed.economy.orders,1,"snapshot lists the open order")
eq(placed.economy.orders[1].side,"bid","mirror records the side")
eq(placed.economy.bazaar.bids[1].price,20,"write refreshes the order book view")
eq(trade(b2,"bid","Brassite:10:25").coins,9750,"higher bid escrows")
eq(trade(b3,"bid","Brassite:10:20").coins,9800,"equal later bid escrows")
repeatEcon=false
eq(#bazaar("Brassite").bids,3,"transform retries do not duplicate bids")
eq(bazaar("Brassite").nextId,3,"order ids deterministic under transform retry")
eq(bazaar("Brassite").bids[1].owner,"2003","highest bid at the head")
eq(bazaar("Brassite").bids[2].owner,"2002","older equal bid before newer")
eq(bazaar("Brassite").bids[3].owner,"2004","newer equal bid last")
local view=cmd(seller,"bazaar","Brassite").economy.bazaar
eq(view.bestBid,25,"quote shows best bid")
eq(view.bestAsk,nil,"no asks yet")
eq(view.spread,nil,"no spread without both sides")
eq(view.bids[2].qty,20,"depth aggregates equal prices")
eq(view.bids[2].orders,2,"depth counts orders per level")
local sold=trade(seller,"sellToBid","Brassite:15")
eq(sold.coins,350,"instant sell fills best bid then next at each bid's price")
eq(sold.items.Brassite,85,"instant sell spends exactly the filled units")
eq(has(sold.message,"Sold 15"),true,"instant sell reports the fill")
eq(bazaar("Brassite").bids[1].owner,"2002","filled bid leaves the book")
eq(bazaar("Brassite").bids[1].qty,5,"partial fill keeps the remainder")
eq(bazaar("Brassite").bids[2].qty,10,"FIFO: newer equal bid untouched")
eq(bazaar("Brassite").claims["2003"].units,10,"filled units wait for the buyer")
eq(bazaar("Brassite").claims["2002"].units,5,"partial fill claimable")
local claimed=trade(b1,"bidClaim","Brassite")
eq(claimed.items.Brassite,5,"buyer claims filled goods")
eq(claimed.coins,9800,"claim does not touch escrow")
eq(claimed.economy.orders[1].qty,5,"mirror shows the remaining quantity")
local claimWrites=db.writes
eq(trade(b1,"bidClaim","Brassite").message,"Nothing to collect yet.","claim cannot repeat")
eq(db.writes,claimWrites,"H1: a claim with nothing to collect performs no UpdateAsync")
eq(trade(b1,"state").items.Brassite,5,"repeat claim pays nothing")
local floor=trade(seller,"sellToBid","Brassite:10:21")
eq(floor.items.Brassite,85,"instant sell respects a minimum price")
eq(has(floor.message,"No buy order"),true,"unmatched instant sell explains itself")
eq(trade(seller,"offer","Brassite:5:30").items.Brassite,80,"sell offer escrows goods")
local spread=cmd(b1,"bazaar","Brassite").economy.bazaar
eq(spread.bestAsk,30,"best ask from resting offers")
eq(spread.bestBid,20,"best bid excludes the viewer's own order")
eq(spread.spread,10,"spread is best ask minus best bid")
eq(spread.asks[1].qty,5,"ask depth")
local crossed=trade(b1,"bid","Brassite:3:35")
eq(crossed.items.Brassite,8,"crossing bid fills immediately")
eq(crossed.coins,9710,"crossing bid pays the ask and refunds the improvement")
eq(#crossed.economy.orders,1,"fully filled bid does not rest")
local now=trade(b1,"buyNow","Brassite:5:40")
eq(now.items.Brassite,10,"buy now fills what is offered")
eq(now.coins,9650,"buy now refunds the unfilled remainder")
eq(bazaar("Brassite").asks[1],nil,"filled offer leaves the book")
local proceeds=trade(seller,"bidClaim","Brassite")
eq(proceeds.coins,500,"offer seller collects sale coins at the ask price")
-- Cancel and refund.
local b3Order=orderId(b3,"Brassite")
local cancelled=trade(b3,"bidCancel","Brassite:"..b3Order)
eq(cancelled.coins,10000,"cancel refunds the remainder")
eq(#cancelled.economy.orders,0,"cancel clears the mirror")
eq(has(trade(b3,"bidCancel","Brassite:"..b3Order).message,"no longer open"),true,"cancel cannot repeat")
eq(trade(b3,"state").coins,10000,"repeat cancel refunds nothing")
eq(trade(b1,"bidCancel","Brassite:"..orderId(b1,"Brassite")).coins,9750,"partially filled bid refunds only the remainder")
eq(trade(b2,"bidClaim","Brassite").items.Brassite,10,"fully filled buyer claims later")
-- Self-trade prevention.
trade(seller,"bid","Brassite:1:100")
local selfSell=trade(seller,"sellToBid","Brassite:1")
eq(selfSell.items.Brassite,80,"own bid never buys your own sale")
eq(cmd(seller,"bazaar","Brassite").economy.bazaar.bestBid,nil,"own bid hidden from your best bid")
local sellerBid=orderId(seller,"Brassite","bid")
eq(trade(seller,"bidCancel","Brassite:"..sellerBid).coins,500,"cancel refunds own bid escrow")
-- Coin and goods conservation across every trade.
local coins,units=0,0
for _,p in ipairs({seller,b1,b2,b3}) do
	local s=st(p)
	coins+=s.coins
	units+=s.items.Brassite or 0
end
eq(coins,30000,"Bazaar conserves coins (no fee)")
eq(units,100,"Bazaar conserves goods")
eq(#bazaar("Brassite").bids+#bazaar("Brassite").asks,0,"book empty after settlement")
eq(next(bazaar("Brassite").claims),nil,"no unclaimed fills remain")

-- Order cap (10 across commodities), quantity cap, book capacity.
local capper=econPlayer(2010,10000,{BeastHide=5})
for i=1,9 do trade(capper,"bid","Herb:1:"..i) end
eq(#trade(capper,"offer","BeastHide:1:50").economy.orders,10,"ten orders across commodities")
local refused=trade(capper,"bid","Herb:1:20")
eq(has(refused.message,"10 open Bazaar orders"),true,"eleventh order refused")
eq(refused.coins,10000-45,"refused order escrows nothing")
eq(trade(capper,"buyNow","Herb:1:1").coins,10000-45,"instant orders need no slot and refund unfilled")
local firstHerb
for _,o in ipairs(econ(capper).orders) do if o.item=="Herb" then firstHerb=o;break end end
eq(trade(capper,"bidCancel","Herb:"..firstHerb.id).coins,10000-45+firstHerb.price,"cancel frees a slot and refunds its price")
eq(#trade(capper,"bid","Herb:640:1").economy.orders,10,"640 units allowed")
eq(trade(capper,"state").coins,10000-45+firstHerb.price-640,"maximum quantity escrows exactly")
local saved=Rules.bookCap
Rules.bookCap=#bazaar("Herb").bids+#bazaar("Herb").asks
local full=trade(capper,"sellToBid","BeastHide:1")
eq(full.items.BeastHide,4,"instant sell into an empty side returns goods")
trade(capper,"bidCancel","BeastHide:"..orderId(capper,"BeastHide"))
local herbFull=econPlayer(2011,100,{})
local fullBid=trade(herbFull,"bid","Herb:2:7")
eq(fullBid.coins,100,"full book refunds a resting bid")
eq(has(fullBid.message,"order book is full"),true,"full book explains itself")
Rules.bookCap=saved
local savedAccounts=Rules.accountCap
Rules.accountCap=bazaar("Herb").accounts
local stranger=econPlayer(2012,100,{})
local capacity=trade(stranger,"bid","Herb:2:7")
eq(capacity.coins,100,"account capacity refunds escrow")
eq(has(capacity.message,"at capacity"),true,"account capacity explains itself")
eq(capacity.economy.pending,false,"refused order leaves nothing pending")
Rules.accountCap=savedAccounts

-- Injected failures: lost acknowledgement replays exactly once on rejoin.
local ghost=econPlayer(2020,1000,{})
econFailure="after"
local lost=trade(ghost,"bid","Glowcap:10:30")
eq(lost.coins,700,"ambiguous bid keeps its escrow")
eq(lost.economy.pending,true,"ambiguous bid stays pending")
eq(has(lost.message,"retry safely"),true,"ambiguous bid explains the retry")
services.Players.PlayerRemoving:Fire(ghost)
eq(data.p2020.profile.econPending.verb,"bid","pending order persists in the journal")
eq(data.p2020.profile.econPending.coins,300,"pending escrow persists")
ghost=player(2020)
local replayed=st(ghost)
eq(replayed.coins,700,"replayed bid charged once")
eq(replayed.economy.pending,false,"rejoin settles the pending order")
eq(#replayed.economy.orders,1,"replayed bid mirrored once")
eq(#bazaar("Glowcap").bids,1,"replayed bid placed once")
ghost=rejoin(ghost)
eq(st(ghost).coins,700,"second rejoin changes nothing")
eq(#bazaar("Glowcap").bids,1,"second rejoin places nothing")
-- A seller's lost acknowledgement after filling the bid.
local farmer=econPlayer(2021,0,{Glowcap=10})
econFailure="after"
local lostSale=trade(farmer,"sellToBid","Glowcap:4")
eq(lostSale.items.Glowcap,6,"ambiguous sale keeps goods in escrow")
eq(lostSale.coins,0,"ambiguous sale pays nothing yet")
eq(bazaar("Glowcap").bids[1].qty,6,"sale committed durably")
farmer=rejoin(farmer)
eq(st(farmer).coins,120,"replayed sale pays once")
eq(st(farmer).items.Glowcap,6,"replayed sale returns nothing extra")
farmer=rejoin(farmer)
eq(st(farmer).coins,120,"sale replay cannot repeat")
-- Outage before commit: the next request finishes the pending order first.
econFailure="before"
local outage=trade(farmer,"sellToBid","Glowcap:2")
eq(outage.items.Glowcap,4,"outage holds escrow")
eq(outage.economy.pending,true,"outage leaves the order pending")
eq(bazaar("Glowcap").bids[1].qty,6,"outage committed nothing")
local recovered=trade(farmer,"bidClaim","Glowcap")
eq(has(recovered.message,"Recovered your earlier order first"),true,"next request recovers first")
eq(recovered.coins,180,"recovered sale pays once")
eq(recovered.items.Glowcap,4,"recovered sale spends goods once")
eq(bazaar("Glowcap").bids[1].qty,4,"recovered sale filled once")
local ghostClaim=trade(ghost,"bidClaim","Glowcap")
eq(ghostClaim.items.Glowcap,6,"buyer claims fills made while it was away")
eq(ghostClaim.coins,700,"claim leaves escrow for the remainder")
eq(trade(ghost,"bidCancel","Glowcap:"..orderId(ghost,"Glowcap")).coins,820,"cancel refunds the unfilled four")
eq(st(ghost).coins+st(farmer).coins,1000,"coins conserved through failures")
eq(st(ghost).items.Glowcap+st(farmer).items.Glowcap,10,"goods conserved through failures")
-- Cancellation with a lost acknowledgement.
local hesitant=econPlayer(2022,0,{Moonbloom=8})
trade(hesitant,"offer","Moonbloom:8:9")
econFailure="after"
eq(trade(hesitant,"bidCancel","Moonbloom:"..orderId(hesitant,"Moonbloom")).items.Moonbloom,0,"ambiguous cancel waits for its receipt")
hesitant=rejoin(hesitant)
eq(st(hesitant).items.Moonbloom,8,"cancel replay returns goods once")
eq(#bazaar("Moonbloom").asks,0,"cancel replay removes the offer once")
hesitant=rejoin(hesitant)
eq(st(hesitant).items.Moonbloom,8,"cancel replay cannot repeat")
-- Read failures keep the previous view (once the shared 10 s read cache has aged out).
econReadFailure=true
clock+=11
eq(has(cmd(hesitant,"bazaar","Moonbloom").message,"could not be read"),true,"quote outage is reported")
-- Shared cooldown with the legacy exchange.
local busy=econPlayer(2023,100,{Fish=3})
trade(busy,"list","Fish:12")
eq(has(cmd(busy,"bid","Fish:1:5").message,"still recording"),true,"Bazaar shares the exchange cooldown")
eq(st(busy).coins,100,"cooldown refusal escrows nothing")
eq(trade(busy,"bid","Fish:1:5").coins,95,"after the cooldown the bid is accepted")

-- Auction House.
local merchant=econPlayer(2101,1000,{BrassSword=2,BrassHelm=1,Blade=1,MeadowCharm=1,EmberfoxPet=1},function(p)
	p.equipment={helmet="BrassHelm"}
	p.accessoryBag={"MeadowCharm"}
	p.enchants={Blade={Sharpness=1}}
end)
local collector=econPlayer(2102,5000,{})
local equipped=trade(merchant,"ahList","BrassHelm:500")
eq(has(equipped.message,"Unequip"),true,"equipped gear cannot be listed")
eq(equipped.items.BrassHelm,1,"equipped refusal keeps the item")
eq(has(trade(merchant,"ahList","MeadowCharm:100").message,"accessory bag"),true,"bagged accessory cannot be listed")
local enchanted=trade(merchant,"ahList","Blade:100")
eq(has(enchanted.message,"Enchanted gear cannot be auctioned"),true,"enchanted gear refused")
eq(enchanted.coins,1000,"refusals charge no fee")
eq(has(trade(merchant,"ahList","StormBlade:100").message,"weapon, armor"),true,"unknown gear refused")
eq(has(trade(merchant,"ahList","Stormblade:100").message,"You do not have"),true,"unowned gear refused")
local listed=trade(merchant,"ahList","BrassSword:1000")
eq(listed.coins,990,"listing charges a 1% fee")
eq(listed.items.BrassSword,1,"listing escrows one item")
eq(listed.economy.listings[1].cat,"weapon","mirror records the category")
eq(listed.economy.listings[1].price,1000,"mirror records the price")
eq(auction("weapon").listings[1].expires,math.floor(utc)+86400,"listing expires in 24 hours")
eq(trade(merchant,"ahList","EmberfoxPet:150").coins,988,"fee rounds up")
clock+=3
local browse=cmd(collector,"ahBrowse","weapon").economy.auction
eq(browse.total,1,"browse lists active listings")
eq(browse.listings[1].item,"BrassSword","browse shows the item")
eq(browse.listings[1].own,false,"browse marks other sellers")
local swordId=browse.listings[1].id
local bought=trade(collector,"ahBuy","weapon:"..swordId..":1000")
eq(bought.coins,4000,"purchase pays the price")
eq(bought.items.BrassSword,1,"purchase delivers the item")
local again=trade(collector,"ahBuy","weapon:"..swordId..":1000")
eq(again.coins,4000,"a sold listing cannot sell twice")
eq(has(again.message,"listing is gone"),true,"sold listing explains itself")
local petId=listingId(merchant,"EmberfoxPet")
local own=trade(merchant,"ahBuy","pet:"..petId..":150")
eq(own.coins,988,"own listing purchase refunded")
eq(has(own.message,"own listing"),true,"own purchase explains itself")
eq(has(trade(collector,"ahBuy","pet:"..petId..":149").message,"costs more"),true,"underpaying is refused")
eq(st(collector).coins,4000,"underpayment refunded")
local claim=trade(merchant,"ahClaim","weapon")
eq(claim.coins,1988,"seller claims proceeds")
eq(#claim.economy.listings,1,"sold listing leaves the mirror")
eq(trade(merchant,"ahClaim","weapon").message,"Nothing to collect in this category yet.","proceeds cannot repeat")
eq(st(merchant).coins+st(collector).coins,6000-12,"coins conserved minus listing fees")
-- Expiry returns the item; the fee is a sink.
advance(86401)
merchant,collector=rejoin(merchant),rejoin(collector)
clock+=3
eq(cmd(collector,"ahBrowse","pet").economy.auction.total,0,"expired listings leave the board")
local writesBefore=db.econWrites
local goneBuy=trade(collector,"ahBuy","pet:"..petId..":150")
eq(has(goneBuy.message,"listing is gone"),true,"expired listing cannot be bought")
eq(goneBuy.coins,4000,"failed purchase refunds the escrow locally")
eq(db.econWrites,writesBefore,"H2: a purchase that changes nothing writes nothing (no receipt)")
eq(auction("pet").receipts["2102"],nil,"no-op purchases never create a receipt")
clock+=3
eq(cmd(merchant,"ahBrowse","pet").economy.auction.returns,1,"seller sees the waiting return")
local back=trade(merchant,"ahClaim","pet")
eq(back.items.EmberfoxPet,1,"expired item returned")
eq(back.coins,1988,"expiry refunds no fee")
eq(#back.economy.listings,0,"expired listing leaves the mirror")
eq(trade(merchant,"ahClaim","pet").items.EmberfoxPet,1,"expiry return cannot repeat")
-- Expiry claimed directly by its seller (no intervening writes).
trade(merchant,"ahList","EmberfoxPet:40")
advance(86401)
merchant,collector=rejoin(merchant),rejoin(collector)
local direct=trade(merchant,"ahClaim","pet")
eq(direct.items.EmberfoxPet,1,"seller's own claim returns an expired listing")
eq(direct.coins,1987,"second listing fee was spent")
-- Cancel returns the item but keeps the fee.
local cancelItem=trade(collector,"ahList","BrassSword:50")
eq(cancelItem.coins,3999,"cheap listing fee is one coin")
local cancelAh=trade(collector,"ahCancel","weapon:"..listingId(collector,"BrassSword"))
eq(cancelAh.items.BrassSword,1,"cancel returns the item")
eq(cancelAh.coins,3999,"cancel keeps the fee")
eq(has(cancelAh.message,"not refunded"),true,"cancel explains the fee")
eq(has(trade(collector,"ahCancel","weapon:"..swordId).message,"no longer open"),true,"cannot cancel another's or a closed listing")
-- Lost acknowledgements on list and buy replay once.
econFailure="after"
local lostList=trade(merchant,"ahList","BrassSword:300")
eq(lostList.items.BrassSword,0,"ambiguous listing keeps the item in escrow")
eq(lostList.coins,1984,"ambiguous listing holds the fee")
merchant=rejoin(merchant)
eq(st(merchant).coins,1984,"replayed listing charges the fee once")
eq(st(merchant).items.BrassSword,0,"replayed listing escrows once")
eq(#auction("weapon").listings,1,"replayed listing created once")
eq(#st(merchant).economy.listings,1,"replayed listing mirrored once")
local relisted=auction("weapon").listings[1].id
econFailure="after"
local lostBuy=trade(collector,"ahBuy","weapon:"..relisted..":300")
eq(lostBuy.coins,3699,"ambiguous purchase holds the price")
eq(lostBuy.items.BrassSword,1,"ambiguous purchase delivers nothing yet")
collector=rejoin(collector)
eq(st(collector).items.BrassSword,2,"replayed purchase delivers once")
eq(st(collector).coins,3699,"replayed purchase charges once")
eq(auction("weapon").proceeds["2101"],300,"seller credited once")
collector=rejoin(collector)
eq(st(collector).items.BrassSword,2,"purchase replay cannot repeat")
eq(trade(merchant,"ahClaim","weapon").coins,2284,"seller collects replayed sale once")
eq(st(merchant).coins+st(collector).coins,6000-17,"AH conserves coins minus five listing fees")
-- Listing cap.
local hoarder=econPlayer(2103,1000,{CopperHoe=11})
for i=1,10 do trade(hoarder,"ahList","CopperHoe:"..(100+i)) end
local capped=trade(hoarder,"ahList","CopperHoe:5")
eq(has(capped.message,"10 auction listings"),true,"eleventh listing refused")
eq(capped.items.CopperHoe,1,"refused listing keeps the item")
eq(capped.coins,1000-20,"ten listing fees of two coins each")
clock+=3
local page=cmd(collector,"ahBrowse","tool:2").economy.auction
eq(page.total,10,"browse counts every active listing")
eq(page.pages,2,"browse pages by eight")
eq(#page.listings,2,"second page holds the rest")
eq(page.listings[1].price,109,"listings sorted by price")
local savedAh=Rules.auctionCap
Rules.auctionCap=10
local overflow=econPlayer(2104,100,{CopperHoe=1})
local fullAh=trade(overflow,"ahList","CopperHoe:500")
eq(fullAh.items.CopperHoe,1,"full Auction House returns the item")
eq(fullAh.coins,100,"full Auction House refunds the fee")
Rules.auctionCap=savedAh

-- Ironman journals cannot use either market.
local iron=econPlayer(2105,1000,{Brassite=10,BrassSword=1})
cmd(iron,"ironman")
for _,attempt in ipairs({{"bid","Brassite:1:5"},{"offer","Brassite:1:5"},{"sellToBid","Brassite:1"},{"buyNow","Brassite:1:5"},
	{"bidClaim","Brassite"},{"ahList","BrassSword:100"},{"ahBuy","weapon:1:1"},{"ahClaim","weapon"},{"bazaar","Brassite"},{"ahBrowse","weapon"}}) do
	local s=trade(iron,attempt[1],attempt[2])
	eq(s.message,"Ironman journals cannot use the Bazaar or Auction House.","Ironman refused: "..attempt[1])
end
eq(st(iron).coins,1000,"Ironman coins untouched")
eq(st(iron).items.BrassSword,1,"Ironman gear untouched")
eq(st(iron).economy.bazaar,nil,"Ironman receives no market view")
-- L7: a rolled-back journal (econSeq restarts) never settles against an older receipt.
local roller=econPlayer(2200,0,{Glowcap=4})
local rollBuyer=econPlayer(2201,1000,{})
trade(rollBuyer,"bid","Glowcap:4:50")
local sale=trade(roller,"sellToBid","Glowcap:4:50")
eq(sale.coins,200,"sale before the rollback")
eq(bazaar("Glowcap").receipts["2200"].n~=nil,true,"receipts carry the order nonce")
roller=rejoin(roller)
services.Players.PlayerRemoving:Fire(roller)
data.p2200.profile.econSeq=0 -- rollback: the sequence restarts, coins/items as saved
roller=player(2200)
local fresh=trade(roller,"bid","Glowcap:1:5")
eq(fresh.coins,195,"post-rollback order with a reused seq is applied, not matched to the old receipt")
eq(has(fresh.message,"Buy order #"),true,"post-rollback bid rests in the book")
eq(orderId(roller,"Glowcap","bid")~=nil,true,"post-rollback bid mirrored")
trade(roller,"bidCancel","Glowcap:"..orderId(roller,"Glowcap","bid"))
trade(rollBuyer,"bidClaim","Glowcap")

-- M3: one per-player DataStore budget across every market call, and a shared read cache.
local spam=econPlayer(2210,1000,{Brassite=50})
clock+=60
local reads=db.reads
cmd(spam,"bazaar","Brassite")
clock+=3
local watcher=econPlayer(2211,0,{})
cmd(watcher,"bazaar","Brassite")
eq(db.reads,reads+1,"two players browsing one book within 10 s share one GetAsync")
clock+=11
local busyMsg
local calls=db.reads+db.writes
for i=1,12 do
	clock+=6 -- a scripted client firing as soon as the 6 s exchange cooldown allows
	local r=cmd(spam,"offer","Brassite:1:"..(100+i))
	if has(r.message,"Market busy") then busyMsg=r.message break end
end
ok(busyMsg~=nil and string.match(busyMsg,"^Market busy — try again in %d+s%.$")~=nil,"budget exhausted answers Market busy: "..tostring(busyMsg))
local spent=db.reads+db.writes-calls
ok(spent<=12,"burst bounded before the budget refuses ("..spent.." DataStore calls)")
local after,started=db.reads+db.writes,clock
for _=1,30 do clock+=2 cmd(spam,"bazaar","Brassite") end
local elapsed=clock-started
ok(db.reads+db.writes-after<=math.ceil(elapsed/10)+1,"browse spam bounded by the shared 10 s cache ("..(db.reads+db.writes-after).." reads in "..elapsed.." s)")
eq(st(spam).items.Brassite+#econ(spam).orders,50,"budget refusals escrow nothing")
for _,o in ipairs(econ(spam).orders) do clock+=20 trade(spam,"bidCancel","Brassite:"..o.id) end

-- H2: 5000 distinct sequential traders can each place and complete a trade.
-- Inert receipts give their slot to newcomers, so a key never locks up.
local maker=econPlayer(2300,0,{Moonbloom=640*9})
trade(maker,"offer","Moonbloom:640:2")
local done,peak=0,0
local liveCap=math.min(Rules.accountCap,1500)
for n=1,5000 do
	utc+=3
	if n%600==0 then
		maker=rejoin(maker)
		trade(maker,"offer","Moonbloom:640:2")
	end
	local buyer=econPlayer(100000+n,10,{})
	local r=trade(buyer,"buyNow","Moonbloom:1:2")
	if r.items.Moonbloom==1 and r.coins==8 then done+=1 end
	peak=math.max(peak,bazaar("Moonbloom").accounts)
	services.Players.PlayerRemoving:Fire(buyer)
end
eq(done,5000,"every one of 5000 sequential traders completed a trade")
eq(peak,liveCap,"live receipts reach but never exceed the per-key cap (slots were recycled)")
local live=0
for _ in pairs(bazaar("Moonbloom").receipts) do live+=1 end
eq(live,bazaar("Moonbloom").accounts,"accounts counts live receipts")
local textCount=0
for _,r in pairs(bazaar("Moonbloom").receipts) do if r.text then textCount+=1 end end
eq(textCount,1,"only the newest receipt keeps its text")
-- Inert receipts expire after the TTL; the maker (open offer + claims) keeps its receipt.
utc+=15*86400
maker=rejoin(maker)
trade(maker,"bidClaim","Moonbloom")
live=0
for _ in pairs(bazaar("Moonbloom").receipts) do live+=1 end
ok(live<=2,"inert receipts pruned after the TTL ("..live.." left)")
eq(bazaar("Moonbloom").receipts["2300"]~=nil,true,"active trader keeps its receipt")

-- H1: worst-case shared keys after pruning stay small (per-key throughput budget).
local serde=require("@lune/serde")
local longestCommodity,auctionIds="",{}
for id,def in pairs(Data.Items) do
	if Rules.isCommodity(id) and #id>#longestCommodity then longestCommodity=id end
	if Rules.auctionCategory(id) then table.insert(auctionIds,id) end
end
table.sort(auctionIds,function(a,b) return #a>#b end)
local function nonce(u) return string.format("%016x",u) end
local text=string.rep("x",260)
local bazaarCap,auctionCap=math.min(Rules.accountCap,1500),math.min(Rules.accountCap,600)
local worstBazaar={bids={},asks={},claims={},receipts={},accounts=bazaarCap,nextId=999999999,revision=999999999,version=1}
for i=1,Rules.bookCap do table.insert(worstBazaar.bids,{id=999999000+i,owner=tostring(9000000000+i),price=Rules.maxPrice,qty=Rules.maxQuantity}) end
for u=1,bazaarCap do
	local uid=tostring(9000000000+u)
	worstBazaar.receipts[uid]={seq=9999999,n=nonce(u),coins=640000000,items={[longestCommodity]=6400},at=1999999999,text=if u==1 then text else nil}
	worstBazaar.claims[uid]={units=6400,coins=6400000000}
end
local bazaarBytes=#serde.encode("json",worstBazaar)
ok(bazaarBytes<512*1024,"worst-case Bazaar key after pruning < 512 KB: "..bazaarBytes)
local worstAuction={listings={},proceeds={},returns={},receipts={},accounts=auctionCap,nextId=999999999,revision=999999999,version=1}
for i=1,Rules.auctionCap do table.insert(worstAuction.listings,{id=999999000+i,seller=tostring(9000000000+i),item=auctionIds[1],price=Rules.maxPrice,expires=1999999999}) end
for u=1,auctionCap do
	local uid=tostring(9000000000+u)
	local items,back={},{}
	for k=1,Rules.listingCap+1 do items[auctionIds[k]]=10 end
	for k=1,Rules.listingCap do back[auctionIds[k]]=10 end
	worstAuction.receipts[uid]={seq=9999999,n=nonce(u),coins=1000000000,items=items,at=1999999999,text=if u==1 then text else nil}
	worstAuction.proceeds[uid]=10000000000
	worstAuction.returns[uid]=back
end
local auctionBytes=#serde.encode("json",worstAuction)
ok(auctionBytes<512*1024,"worst-case Auction House key after pruning < 512 KB: "..auctionBytes)
print("Economy maximum-shape fixtures after pruning: Bazaar "..bazaarBytes.." / Auction "..auctionBytes.." JSON bytes.")
print("PASS: "..(checks-before).." economy (Bazaar / Auction House) assertions.")
end)()
print("PASS: "..checks.." production gameplay/market/depth assertions.")
do
	local visitor=player(990)
	local msg=use(visitor,node("station","Forge")).message
	assert(msg:find("Forge open"),"station prompt answered: "..tostring(msg))
	assert(cmd(visitor,"station","Forge").message=="Unknown action.","station requires a world prompt")
	print("PASS: station prompt checks.")
end

------------------------------------------------------------------------------
-- Quests & Achievements: quest line, diaries, Carpentry construction.
------------------------------------------------------------------------------
do
	local before=checks
	local function rejoin(pl)
		services.Players.PlayerRemoving:Fire(pl)
		return player(pl.UserId)
	end
	-- Seed a saved profile directly (as a long-lived player would have it), then join.
	local function seeded(id,edit)
		local pl=player(id)
		cmd(pl,"state")
		services.Players.PlayerRemoving:Fire(pl)
		edit(data["p"..id].profile)
		return player(id)
	end
	local function setLevel(prof,skill,lvl)
		prof.xp[skill]=Progression.xpForLevel(lvl)
		prof.levelRewards[skill]=lvl
	end
	local function setCollection(prof,item,n)
		prof.collection[item]=n
		prof.collectionRewards[item]=Progression.collectionTier(prof,item)
	end
	local function questEntry(s,id) return s.journal.quests[Data.QuestById[id].index] end
	local function diaryEntry(s,region)
		for _,d in ipairs(s.journal.diaries) do if d.region==region then return d end end
	end

	-- Data integrity.
	local ids={}
	for _,q in ipairs(Data.Quests) do
		eq(ids[q.id],nil,"unique quest id "..q.id)
		ids[q.id]=true
		eq(#q.objectives>0 and q.rewards.points~=nil,true,"quest has objectives and Quest Points: "..q.id)
	end
	eq(#Data.Quests>=10,true,"ten or more new quests")
	local lines={main=0,side=0}
	for _,q in ipairs(Data.Quests) do lines[q.line]+=1 end
	eq(lines.main>=4 and lines.side>=4,true,"main and side quests both exist")
	eq(#Data.Diaries,7,"seven regional diaries")
	for _,d in ipairs(Data.Diaries) do
		for _,tier in ipairs(Data.DiaryTiers) do
			local n=#d.tiers[tier].tasks
			eq(n>=3 and n<=5,true,d.region.." "..tier.." has 3-5 tasks")
		end
	end
	local furnitureCount=#Data.FurnitureOrder
	eq(furnitureCount>=10 and furnitureCount<=15,true,"10-15 furniture pieces")
	for _,id in ipairs(Data.FurnitureOrder) do
		local f=Data.Furniture[id]
		eq(Data.HotspotById[f.hotspot]~=nil and f.level>=1 and f.level<=99 and f.xp>0,true,"furniture "..id.." hotspot, level and XP")
	end

	-- Quest gating and claims.
	local fresh=player(3001)
	local s0=cmd(fresh,"state")
	eq(s0.journal.questPoints,0,"fresh journal has no Quest Points")
	eq(questEntry(s0,"SurveyorsOath").available,false,"main quest locked behind guild contracts")
	eq(cmd(fresh,"quest","SurveyorsOath").message:find("requires",1,true)~=nil,true,"locked quest refuses claim")
	eq(cmd(fresh,"quest","BrassfallEchoes").message:find("Surveyor's Oath",1,true)~=nil,true,"prior quest requirement named")
	local hero=seeded(3002,function(prof)
		prof.questCompleted=8
		prof.bestiary.BramblebackBoar=10
		setCollection(prof,"Herb",100)
		prof.coins=0
	end)
	local s1=cmd(hero,"state")
	eq(s1.journal.questPoints,8,"guild contracts count as Quest Points")
	eq(questEntry(s1,"SurveyorsOath").available,true,"contracts unlock the main line")
	eq(questEntry(s1,"SurveyorsOath").ready,true,"objectives evaluated from profile state")
	eq(questEntry(s1,"SurveyorsOath").objectives[1][1],10,"kill objective progress")
	local noSkill=cmd(hero,"quest","SurveyorsOath")
	eq(noSkill.message:find("Choose a skill",1,true)~=nil,true,"lamp quest needs a skill choice")
	eq(questEntry(noSkill,"SurveyorsOath").done,false,"lamp refusal claims nothing")
	eq(noSkill.coins,0,"lamp refusal pays nothing")
	eq(cmd(hero,"quest","SurveyorsOath:Nope").coins,0,"unknown lamp skill rejected")
	eq(cmd(hero,"quest","SurveyorsOath:mining").coins,0,"lamp skill is case-sensitive")
	-- L8: open lamps never feed gated skills (data rule + server enforcement).
	for _,q in ipairs(Data.Quests) do
		local lamp=q.rewards.lamp
		if lamp and not lamp.skills then
			eq(lamp.exclude~=nil and table.find(lamp.exclude,"Dungeoneering")~=nil and table.find(lamp.exclude,"Carpentry")~=nil,true,q.id.." lamp excludes gated skills")
		end
	end
	for _,gated in ipairs({"Dungeoneering","Carpentry"}) do
		local refused=cmd(hero,"quest","SurveyorsOath:"..gated)
		eq(refused.message:find("cannot train",1,true)~=nil,true,"open lamp refuses "..gated)
		eq(refused.xp[gated],0,"open lamp grants no "..gated.." XP")
		eq(questEntry(refused,"SurveyorsOath").done,false,"gated lamp refusal claims nothing")
	end
	local claimed=cmd(hero,"quest","SurveyorsOath:Mining")
	eq(questEntry(claimed,"SurveyorsOath").done,true,"quest claimed")
	eq(claimed.xp.Mining,600,"lamp XP to chosen skill")
	eq(claimed.journal.questPoints,9,"Quest Points awarded")
	local coinsAfter=claimed.coins
	eq(coinsAfter>=400,true,"quest coins paid")
	eq(cmd(hero,"quest","SurveyorsOath:Mining").coins,coinsAfter,"quest cannot be claimed twice")
	eq(cmd(hero,"quest","SurveyorsOath:Combat").xp.Combat,0,"second claim cannot redirect the lamp")
	hero=rejoin(hero)
	local s2=cmd(hero,"state")
	eq(questEntry(s2,"SurveyorsOath").done,true,"claimed quest survives rejoin")
	eq(s2.journal.questPoints,9,"Quest Points survive rejoin")
	eq(cmd(hero,"quest","SurveyorsOath:Mining").coins,coinsAfter,"rejoin cannot reclaim quest")
	eq(cmd(hero,"quest").coins,coinsAfter,"finished guild chain still pays nothing")
	eq(questEntry(s2,"BrassfallEchoes").available,false,"next main quest still gated by Mining 15")
	-- Legacy contract chain is unaffected and keeps its own verb.
	eq(cmd(fresh,"quest").quest.stage,1,"legacy contract verb still gated")

	-- Lamp restricted to listed skills; perk reward reaches the stat sheet.
	local gardener=seeded(3003,function(prof)
		prof.questCompleted=2
		prof.bestiary.Thornling=15
		setCollection(prof,"Sunwheat",50)
	end)
	local g0=cmd(gardener,"state")
	local baseFortune=g0.depth.stats.farmingFortune
	eq(cmd(gardener,"quest","ThornlingGarden:Mining").xp.Mining,0,"lamp outside its skill list rejected")
	local g1=cmd(gardener,"quest","ThornlingGarden:Farming")
	eq(g1.xp.Farming,800,"restricted lamp accepted for listed skill")
	local expected=baseFortune+5+4*(g1.levels.Farming-1)
	eq(g1.depth.stats.farmingFortune,expected,"quest perk flows through computeStats")
	gardener=rejoin(gardener)
	eq(data.p3003.profile.perkStats["quest:ThornlingGarden"].farmingFortune,5,"quest perk stored in p.perkStats")
	eq(cmd(gardener,"state").depth.stats.farmingFortune,expected,"quest perk persists")

	-- Hand-in objectives and non-lamp quests.
	local angler=seeded(3004,function(prof)
		prof.questCompleted=4
		setLevel(prof,"Fishing",10)
		prof.items.Fish=25
	end)
	eq(cmd(angler,"quest","TidewingLullaby:Fishing").items.Fish,25,"skill suffix rejected for a quest without a lamp")
	local a1=cmd(angler,"quest","TidewingLullaby")
	eq(a1.items.Fish,5,"hand-in consumes exactly the objective amount")
	eq(a1.items.CookedFish,5,"item reward")
	eq(a1.xp.Taming,400,"fixed XP reward")
	local tinker=seeded(3005,function(prof)
		prof.questCompleted=6
		setLevel(prof,"Smithing",20)
		prof.bestiary.BrassGolem=10
	end)
	local t0=cmd(tinker,"state")
	local slots0=t0.depth.accessorySlots
	local t1=cmd(tinker,"quest","GolemHeartbeat")
	eq(t1.message:find("Golem Core",1,true)~=nil,true,"missing hand-in item named")
	eq(questEntry(t1,"GolemHeartbeat").ready,false,"hand-in item required")
	services.Players.PlayerRemoving:Fire(tinker)
	data.p3005.profile.items.GolemCore=1
	tinker=player(3005)
	local t2=cmd(tinker,"quest","GolemHeartbeat")
	eq(questEntry(t2,"GolemHeartbeat").done,true,"hand-in quest completes")
	eq(t2.items.GolemCore,0,"hand-in item consumed")
	eq(t2.items.SunsteelIngot,5,"ingot reward")
	eq(t2.depth.accessorySlots,slots0+1,"quest unlocks an accessory slot")
	tinker=rejoin(tinker)
	eq(cmd(tinker,"state").depth.accessorySlots,slots0+1,"accessory slot unlock persists")
	eq(questEntry(cmd(tinker,"state"),"FeathersAloft").available,false,"follow-up side quest gated by Combat 25")

	-- Quest Point requirement.
	local veteran=seeded(3006,function(prof)
		prof.questCompleted=8
		prof.questsDone={HollowLantern=true}
		setLevel(prof,"Combat",40)
	end)
	local v0=cmd(veteran,"state")
	eq(v0.journal.questPoints,8+3,"Quest Points sum contracts and quests")
	eq(questEntry(v0,"CrownOfTempest").available,false,"Quest Point requirement gates the finale")
	eq(questEntry(v0,"CrownOfTempest").requires[3][1],11,"Quest Point requirement progress")
	eq(questEntry(v0,"CrownOfTempest").requires[3][2],14,"Quest Point requirement")

	-- Malformed or hostile quest requests.
	for _,bad in ipairs({"","Nope","a:b:c","SurveyorsOath:","SurveyorsOath::Mining",":Mining","Surveyors Oath",string.rep("Q",64)}) do
		local r=cmd(hero,"quest",bad)
		eq(r.coins,coinsAfter,"malformed quest request pays nothing: "..bad)
	end
	eq(cmd(hero,"quest",string.rep("Q",65)).message,"That request is too long.","long quest id rejected")

	-- Counters: crafts and region gathers.
	local smith=seeded(3007,function(prof)
		prof.items.Ore=20 prof.items.Timber=20
		prof.questCompleted=6
	end)
	for _=1,3 do cmd(smith,"craft","AlloyIngot") end
	local sm=cmd(smith,"state")
	eq(diaryEntry(sm,"Quarry").tiers[1].tasks[3][1],3,"legacy crafts counted for diaries")
	local rich=node("gather","Aetherite",0,nil,"Skyreach")
	-- Aetherite needs Mining 3.
	services.Players.PlayerRemoving:Fire(smith)
	setLevel(data.p3007.profile,"Mining",5)
	smith=player(3007)
	use(smith,rich)
	use(smith,rich)
	use(smith,node("gather","Aetherite"))
	local sm2=cmd(smith,"state")
	eq(diaryEntry(sm2,"Skyreach").tiers[1].tasks[2][1],2,"only region-tagged gathers count for that region")
	smith=rejoin(smith)
	eq(diaryEntry(cmd(smith,"state"),"Skyreach").tiers[1].tasks[2][1],2,"gather counter persists")
	eq(diaryEntry(cmd(smith,"state"),"Quarry").tiers[1].tasks[3][1],3,"craft counter persists")
	-- Region gathers on a locked region do not count.
	local outsider=seeded(3008,function(prof) setLevel(prof,"Mining",5) end)
	use(outsider,rich)
	eq(diaryEntry(cmd(outsider,"state"),"Skyreach").tiers[1].tasks[2][1],0,"locked region gather neither pays nor counts")

	-- Achievement diaries.
	local diarist=seeded(3009,function(prof)
		prof.bestiary.BramblebackBoar=5
		setCollection(prof,"Herb",50)
		setCollection(prof,"Timber",49)
		setLevel(prof,"Farming",5)
		prof.coins=0
	end)
	local d0=cmd(diarist,"state")
	local health0=d0.depth.stats.health
	eq(diaryEntry(d0,"Meadow").tiers[1].complete,false,"incomplete diary tier")
	local d1=cmd(diarist,"diary","Meadow:Easy")
	eq(d1.message:find("Timber",1,true)~=nil,true,"diary names the missing task")
	eq(d1.coins,0,"incomplete diary pays nothing")
	eq(cmd(diarist,"diary","Meadow:Medium").message:find("Easy",1,true)~=nil,true,"diary tiers claimed in order")
	services.Players.PlayerRemoving:Fire(diarist)
	setCollection(data.p3009.profile,"Timber",50)
	diarist=player(3009)
	local d2=cmd(diarist,"state")
	eq(diaryEntry(d2,"Meadow").tiers[1].claimable,true,"complete tier claimable")
	local d3=cmd(diarist,"diary","Meadow:Easy")
	eq(d3.coins,Data.DiaryCoins.Easy,"diary tier coins")
	eq(diaryEntry(d3,"Meadow").claimed,1,"diary tier recorded")
	eq(d3.depth.stats.health,health0+10,"diary perk adds health")
	eq(cmd(diarist,"diary","Meadow:Easy").coins,Data.DiaryCoins.Easy,"diary tier cannot be claimed twice")
	for _,bad in ipairs({"Meadow","Meadow:Legendary","Atlantis:Easy","meadow:easy","Meadow:Easy:Again",""}) do
		eq(cmd(diarist,"diary",bad).coins,Data.DiaryCoins.Easy,"malformed diary request pays nothing: "..bad)
	end
	eq(cmd(diarist,"diary").coins,Data.DiaryCoins.Easy,"missing diary payload pays nothing")
	diarist=rejoin(diarist)
	local d4=cmd(diarist,"state")
	eq(diaryEntry(d4,"Meadow").claimed,1,"diary claim persists")
	eq(d4.depth.stats.health,health0+10,"diary perk persists")
	eq(type(data.p3009.profile.perkStats["diary:Meadow:Easy"]),"table","diary perk stored in p.perkStats")
	eq(diaryEntry(d4,"Meadow").tiers[2].claimable,false,"next tier needs its own tasks")

	-- Tampered save fields are sanitized on open; other teams' perk keys survive.
	local tamper=seeded(3010,function(prof)
		prof.diaries={Meadow=-3,Quarry="2.7",Atlantis=2,Tempest=0/0}
		prof.questsDone={Fake=true,SurveyorsOath="yes",ThornlingGarden=true}
		prof.furniture={Bench="PortalFrame",Garden="Nope",Portal="PortalFrame",Hearth=7}
		prof.perkStats={["diary:Meadow:Elite"]={health=9999},["lead:test"]={strength=1}}
		prof.counters={gathers={Skyreach="lots",Windpine=-4,Tidewater=7},crafts=5}
		prof.homePortal="Tempest"
	end)
	local tm=cmd(tamper,"state")
	eq(diaryEntry(tm,"Meadow").claimed,0,"negative diary tier dropped")
	eq(diaryEntry(tm,"Quarry").claimed,2,"fractional diary tier floored")
	eq(diaryEntry(tm,"Tempest").claimed,0,"NaN diary tier dropped")
	eq(questEntry(tm,"SurveyorsOath").done,false,"non-boolean quest record dropped")
	eq(questEntry(tm,"ThornlingGarden").done,true,"valid quest record kept")
	eq(tm.journal.construction.furniture.Bench,nil,"furniture on the wrong hotspot dropped")
	eq(tm.journal.construction.furniture.Garden,nil,"unknown furniture dropped")
	eq(tm.journal.construction.furniture.Portal,"PortalFrame","valid furniture kept")
	eq(tm.journal.construction.portal,nil,"unattunable home portal cleared")
	eq(tm.depth.stats.health<1000,true,"forged diary perk has no effect")
	tamper=rejoin(tamper)
	eq(data.p3010.profile.perkStats["diary:Meadow:Elite"],nil,"forged diary perk removed")
	eq(data.p3010.profile.perkStats["lead:test"].strength,1,"other perk sources untouched")
	eq(diaryEntry(tm,"Skyreach").tiers[1].tasks[2][1],0,"non-numeric counter dropped")
	eq(diaryEntry(tm,"Windpine").tiers[1].tasks[1][1],0,"negative counter dropped")
	eq(diaryEntry(tm,"Tidewater").tiers[1].tasks[1][1],7,"valid counter kept")

	-- Carpentry construction.
	local mason=seeded(3011,function(prof) prof.coins=0 end)
	local m0=cmd(mason,"build","Bench:SturdyWorkbench")
	eq(m0.message:find("needs",1,true)~=nil,true,"unfunded furniture refused")
	eq(m0.journal.construction.furniture.Bench,nil,"unfunded furniture not placed")
	eq(cmd(mason,"build","Bench:BrassWorkbench").message:find("Carpentry 25",1,true)~=nil,true,"Carpentry level gate")
	eq(cmd(mason,"build","Garden:SturdyWorkbench").message:find("does not fit",1,true)~=nil,true,"furniture bound to its hotspot")
	services.Players.PlayerRemoving:Fire(mason)
	data.p3011.profile.items.Timber=100
	data.p3011.profile.items.Ore=100
	data.p3011.profile.items.Herb=40
	mason=player(3011)
	local m1=cmd(mason,"build","Bench:SturdyWorkbench")
	eq(m1.items.Timber,80,"furniture charges Timber")
	eq(m1.items.Ore,90,"furniture charges Ore")
	eq(m1.xp.Carpentry,60,"furniture grants Carpentry XP")
	eq(m1.journal.construction.furniture.Bench,"SturdyWorkbench","furniture placed")
	eq(mason.FurnitureBench,"SturdyWorkbench","world attribute set for the hotspot")
	eq(mason.FurnitureGarden,"","empty hotspots publish an empty attribute")
	local m2=cmd(mason,"build","Bench:SturdyWorkbench")
	eq(m2.message:find("Remove",1,true)~=nil,true,"occupied hotspot refuses a second piece")
	eq(m2.items.Timber,80,"occupied hotspot charges nothing")
	local m3=cmd(mason,"remove","Bench")
	eq(m3.items.Timber,90,"removal refunds half the Timber")
	eq(m3.items.Ore,95,"removal refunds half the Ore")
	eq(m3.xp.Carpentry,60,"removal keeps earned XP")
	eq(mason.FurnitureBench,"","removal clears the world attribute")
	eq(cmd(mason,"remove","Bench").items.Timber,90,"empty hotspot refunds nothing")
	for _,bad in ipairs({"Bench","Bench:",":SturdyWorkbench","Bench:Sturdy Workbench","Moon:SturdyWorkbench","Bench:Ghost","Bench:SturdyWorkbench:x"}) do
		eq(cmd(mason,"build",bad).items.Timber,90,"malformed build pays and places nothing: "..bad)
	end
	eq(cmd(mason,"remove","Nowhere").items.Timber,90,"unknown hotspot removal refused")
	eq(cmd(mason,"remove").items.Timber,90,"missing hotspot removal refused")
	local m4=cmd(mason,"build","Bench:SturdyWorkbench")
	eq(m4.xp.Carpentry,120,"rebuilding trains Carpentry again")
	eq(cmd(mason,"build","Garden:HerbPlanter").journal.construction.furniture.Garden,nil,"Herb Planter needs Carpentry 5")
	services.Players.PlayerRemoving:Fire(mason)
	setLevel(data.p3011.profile,"Carpentry",5)
	local carpentryBase=data.p3011.profile.xp.Carpentry
	mason=player(3011)
	eq(cmd(mason,"build","Garden:HerbPlanter").journal.construction.furniture.Garden,"HerbPlanter","Herb Planter built at Carpentry 5")
	local m5=cmd(mason,"build","Hearth:ClayHearth")
	eq(m5.journal.construction.furniture.Hearth,nil,"Clay Hearth needs Carpentry 10")
	local farm0=cmd(mason,"state").depth.stats.farmingFortune
	mason=rejoin(mason)
	local m6=cmd(mason,"state")
	eq(m6.journal.construction.furniture.Bench,"SturdyWorkbench","furniture persists across rejoin")
	eq(m6.journal.construction.furniture.Garden,"HerbPlanter","second furniture persists")
	eq(mason.FurnitureGarden,"HerbPlanter","rejoin restores world attributes")
	eq(m6.depth.stats.farmingFortune,farm0,"furniture perk persists")
	eq(type(data.p3011.profile.perkStats["furniture:Garden"]),"table","furniture perk stored in p.perkStats")
	local m7=cmd(mason,"remove","Garden")
	eq(m7.depth.stats.farmingFortune,farm0-8,"removing furniture removes its perk")
	eq(cmd(mason,"ironman").ironman,false,"construction starts progression (no late Ironman)")
	-- Builder's Charter: a build objective (ever built, so later removal keeps it).
	services.Players.PlayerRemoving:Fire(mason)
	data.p3011.profile.questCompleted=3
	mason=player(3011)
	eq(data.p3011.profile.perkStats["furniture:Garden"],nil,"furniture perk record cleared")
	cmd(mason,"remove","Bench")
	local m8=cmd(mason,"quest","BuildersCharter")
	eq(questEntry(m8,"BuildersCharter").done,true,"build objective counts furniture ever built")
	eq(m8.xp.Carpentry,carpentryBase+120+800,"charter XP reward")

	-- Storage, dock and portal effects.
	local architect=seeded(3012,function(prof)
		setLevel(prof,"Carpentry",65)
		prof.questCompleted=6
		for id,n in pairs({WindpineLog=200,BrassIngot=40,EmberoakLog=100,SunsteelIngot=20,Aetherite=100,StarwoodLog=100,StarmetalIngot=30,Stormglass=5,GolemCore=5,GlimmerbarkLog=100,VoidforgedIngot=20}) do
			prof.items[id]=n
		end
		prof.workers={{resource="Ore",tier=1,lastClaim=0}}
		prof.worker=true
	end)
	local r0=cmd(architect,"state")
	local slotsBase=r0.depth.accessorySlots
	eq(r0.workers[1].interval,120,"base worker interval")
	eq(cmd(architect,"build","Storage:TrinketCabinet").depth.accessorySlots,slotsBase+1,"Trinket Cabinet adds a slot")
	cmd(architect,"remove","Storage")
	eq(cmd(architect,"build","Storage:GildedReliquary").depth.accessorySlots,slotsBase+2,"Gilded Reliquary adds two slots")
	eq(cmd(architect,"build","Dock:SurveyorDock").workers[1].interval,114,"Surveyor Dock speeds workers 5%")
	cmd(architect,"remove","Dock")
	eq(cmd(architect,"build","Dock:ClockworkDock").workers[1].interval,108,"Clockwork Dock speeds workers 10%")
	eq(cmd(architect,"portal","Skyreach").message:find("Portal Frame",1,true)~=nil,true,"portal attunement needs a frame")
	local r1=cmd(architect,"build","Portal:PortalFrame")
	eq(r1.journal.construction.furniture.Portal,"PortalFrame","portal frame built")
	eq(table.concat(r1.journal.construction.portalRegions,","),"Skyreach,Windpine","base portal destinations")
	local r2=cmd(architect,"portal","Skyreach")
	eq(r2.journal.construction.portal,"Skyreach","portal attuned")
	eq(architect.HomePortal,"Skyreach","portal attribute for the world")
	eq(cmd(architect,"portal","Windpine").journal.construction.portal,"Skyreach","locked region cannot be attuned")
	eq(cmd(architect,"portal","Gloomhollow").journal.construction.portal,"Skyreach","unattuned isle refused")
	eq(cmd(architect,"portal","Hub").journal.construction.portal,"Skyreach","non-portal region refused")
	eq(cmd(architect,"portal","Atlantis").journal.construction.portal,"Skyreach","unknown region refused")
	architect=rejoin(architect)
	eq(cmd(architect,"state").journal.construction.portal,"Skyreach","portal attunement persists")
	eq(architect.HomePortal,"Skyreach","portal attribute restored on rejoin")
	local r3=cmd(architect,"remove","Portal")
	eq(r3.journal.construction.portal,nil,"removing the frame clears the attunement")
	eq(architect.HomePortal,"","portal attribute cleared")
	local r4=cmd(architect,"build","Portal:StormglassGate")
	eq(table.concat(r4.journal.construction.portalRegions,","),"Skyreach,Windpine,Gloomhollow,Tidewater","gate reaches four regions")
	eq(r4.items.Stormglass,2,"gate charges Stormglass")
	-- Quest shortcut unlocks a portal destination.
	services.Players.PlayerRemoving:Fire(architect)
	data.p3012.profile.questsDone={LeyLines=true}
	architect=player(3012)
	eq(table.find(cmd(architect,"state").journal.construction.portalRegions,"Tempest")~=nil,true,"Ley Lines shortcut attunes Tempest")
	eq(cmd(architect,"portal","Tempest").journal.construction.portal,nil,"shortcut still respects the Combat 40 region gate")
	-- Perk caps: non-stat perks never exceed their bounds.
	eq(data.p3012.profile.perkAccessorySlots<=Data.MAX_PERK_SLOTS,true,"accessory perk slots capped")
	eq(data.p3012.profile.perkWorkerHaste<=Data.MAX_WORKER_HASTE,true,"worker haste capped")
	print("PASS: "..(checks-before).." quest/diary/construction assertions.")
end

-- Sea creatures: roll math, Fishing gather hook, owner tickets and bridge grants.
do
	local before=checks
	local function ok(cond,case) assert(cond,case); checks+=1 end
	local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
	local X=Data.XP_TABLE
	local function st(p) return cmd(p,"state") end
	local function seeded(id,mutate)
		local p=player(id)
		services.Players.PlayerRemoving:Fire(p)
		mutate(data["p"..id].profile)
		return player(id)
	end
	local function rejoin(p)
		services.Players.PlayerRemoving:Fire(p)
		return player(p.UserId)
	end
	local bridge
	for _,o in ipairs(allObjects) do if o.Name=="IsleBridge" then bridge=o end end
	local SC=Data.SeaCreatures
	-- Table shape.
	local count,names,pets,accessories,tideOnly=0,{},0,0,0
	for _,id in ipairs(Data.SeaCreatureOrder) do
		local sc=SC[id]
		count+=1
		ok(sc~=nil and sc.id==id and sc.seaCreature==true,id.." defined")
		ok(not names[sc.name],id.." has a unique name")
		names[sc.name]=true
		ok(sc.hp>0 and sc.damage>0 and sc.defense>=0 and sc.xp>0 and sc.fishingXp>0 and sc.coins>0 and sc.weight>0,id.." has combat and reward numbers")
		ok(Data.Monsters[id]==sc,id.." resolves through Data.Monsters")
		for _,d in ipairs(sc.drops) do
			ok(Data.Items[d.item]~=nil and d.chance>0 and d.min>=1 and d.max>=d.min,id.." drop "..d.item)
			if Data.Items[d.item].kind=="pet" then pets+=1 end
			if Data.Items[d.item].kind=="accessory" then accessories+=1 end
		end
		if sc.waters and #sc.waters==1 and sc.waters[1]=="Tidewater" then tideOnly+=1 end
		for _,w in ipairs(sc.waters or {}) do ok(Data.RegionById[w]~=nil,id.." water "..w.." is a region") end
	end
	ok(count>=8 and count<=10,"eight to ten sea creatures")
	ok(pets>=1 and accessories>=1,"rare pet and accessory drops exist")
	ok(tideOnly>=2,"some creatures live only in Tidewater Shoals")
	for i=2,#Data.SeaCreatureOrder do
		ok(SC[Data.SeaCreatureOrder[i]].fishing>=SC[Data.SeaCreatureOrder[i-1]].fishing,"creatures ordered by Fishing level "..i)
	end
	for id in pairs(Data.Monsters) do ok(SC[id]==nil,"marker list excludes sea creature "..id) end
	ok(Data.PetById.Pearlwhisker~=nil and Data.Items.PearlwhiskerPet.kind=="pet","Pearlwhisker pet item")
	ok(Data.Items.TidecallerPearl.kind=="accessory" and Data.Items.TidecallerPearl.stats.seaCreatureChance>0,"Tidecaller Pearl accessory")
	ok(Data.Recipes.BrineCharm~=nil and Data.Items.BrineShell.kind=="material","Brine Charm crafts from sea materials")

	-- Chance: stats + rod + rod enchants, clamped to [0, 100].
	eq(Data.seaCreatureChance({seaCreatureChance=5}),5,"base chance")
	eq(Data.seaCreatureChance({seaCreatureChance=5},Data.Items.BrassRod.stats),6,"rod adds its chance")
	eq(Data.seaCreatureChance({seaCreatureChance=5},Data.Items.CelestialRod.stats,{seaCreatureChance=2}),13,"rod enchants add too")
	eq(Data.seaCreatureChance({seaCreatureChance=500}),100,"chance capped at 100")
	eq(Data.seaCreatureChance({seaCreatureChance=-40}),0,"negative chance floors at 0")
	eq(Data.seaCreatureChance({seaCreatureChance=0/0}),0,"NaN chance is 0")
	eq(Data.seaCreatureChance(nil,"rod"),0,"garbage inputs are 0")
	local brewer={xp={},items={},collection={},equipment={},buffs={AnglersInfusion={expires=utc+600,stats=Data.Items.AnglersInfusion.buff.stats}},pets={},bestiary={}}
	for _,skill in ipairs(Data.SkillOrder) do brewer.xp[skill]=0 end
	eq(Progression.computeStats(brewer,utc).seaCreatureChance,15,"Angler's Infusion raises computed chance")
	brewer.pets={{id="Pearlwhisker",level=50,xp=0}}; brewer.activePet=1
	ok(Progression.computeStats(brewer,utc).seaCreatureChance>15,"Pearlwhisker pet raises computed chance")

	-- Pools: Fishing level and water gates.
	local function inPool(list,id) return table.find(list,id)~=nil end
	eq(#Data.seaCreaturePool(1,nil),0,"Fishing 1 hooks nothing")
	eq(#Data.seaCreaturePool(4,"Tidewater"),0,"Fishing 4 hooks nothing anywhere")
	local p5=Data.seaCreaturePool(5,nil)
	eq(#p5,1,"Fishing 5 unlocks one creature")
	eq(p5[1],"ShellsnapCrab","the first creature")
	ok(not inPool(Data.seaCreaturePool(99,nil),"CoralbackBruiser"),"Tidewater-only creature absent from home waters")
	ok(not inPool(Data.seaCreaturePool(99,"Gloomhollow"),"TidewyrmMatriarch"),"Tidewater-only creature absent from Gloomhollow")
	ok(inPool(Data.seaCreaturePool(99,"Gloomhollow"),"DuskfinManta"),"cavern creature in Gloomhollow")
	eq(#Data.seaCreaturePool(99,"Tidewater"),#Data.SeaCreatureOrder,"every creature swims in Tidewater")
	ok(not inPool(Data.seaCreaturePool(74,"Tidewater"),"TidewyrmMatriarch"),"Matriarch needs Fishing 75")
	ok(inPool(Data.seaCreaturePool(75,"Tidewater"),"TidewyrmMatriarch"),"Fishing 75 hooks the Matriarch")
	ok(not inPool(Data.seaCreaturePool(99,"Atlantis"),"InkveilDrifter"),"unknown water only has any-water creatures")

	-- Rolls: one chance roll, then a weighted pick.
	local function seq(...) local q={...}; return function() return table.remove(q,1) or 0.999 end end
	eq(Data.rollSeaCreature(99,nil,0,seq(0,0)),nil,"0% never hooks")
	eq(Data.rollSeaCreature(99,nil,5,seq(0.0499,0)),"ShellsnapCrab","roll under the chance hooks")
	eq(Data.rollSeaCreature(99,nil,5,seq(0.05,0)),nil,"roll at the chance misses")
	eq(Data.rollSeaCreature(99,nil,100,seq(0.999,0)),"ShellsnapCrab","100% always hooks")
	eq(Data.rollSeaCreature(1,"Tidewater",100,seq(0,0)),nil,"empty pool hooks nothing")
	-- Fishing 15 home waters: weights crab 100, jelly 80, eel 70 (total 250).
	eq(Data.rollSeaCreature(15,nil,100,seq(0,0.399)),"ShellsnapCrab","weight bucket 1 upper edge")
	eq(Data.rollSeaCreature(15,nil,100,seq(0,0.4)),"DriftbellJelly","weight bucket 2 lower edge")
	eq(Data.rollSeaCreature(15,nil,100,seq(0,0.719)),"DriftbellJelly","weight bucket 2 upper edge")
	eq(Data.rollSeaCreature(15,nil,100,seq(0,0.72)),"ReedfinEel","weight bucket 3 lower edge")
	eq(Data.rollSeaCreature(15,nil,100,seq(0,0.9999)),"ReedfinEel","weight bucket 3 upper edge")
	eq(Data.rollSeaCreature(99,"Tidewater",100,seq(0,0.9999)),"TidewyrmMatriarch","rarest creature at the top of the roll")
	local state=12345
	local function lcg() state=(state*1103515245+12345)%2147483648; return state/2147483648 end
	local hooks,tally,n=0,{},20000
	for _=1,n do
		local id=Data.rollSeaCreature(99,"Tidewater",20,lcg)
		if id then hooks+=1; tally[id]=(tally[id] or 0)+1 end
	end
	ok(math.abs(hooks/n-0.2)<0.015,"hook rate tracks Sea Creature Chance ("..hooks..")")
	ok((tally.ShellsnapCrab or 0)>(tally.CoralbackBruiser or 0) and (tally.CoralbackBruiser or 0)>(tally.TidewyrmMatriarch or 0),"common creatures outnumber rare ones")
	ok((tally.TidewyrmMatriarch or 0)<hooks*0.03,"the Matriarch stays rare")

	-- Server: a successful Fishing gather hooks a creature beside the node.
	local function angler(id,fishing,mutate)
		return seeded(id,function(p)
			p.xp.Fishing=X[fishing]; p.xp.Combat=0
			p.levelRewards.Fishing=99; p.levelRewards.Combat=99
			if mutate then mutate(p) end
		end)
	end
	local saved=defaultRoll
	local novice=player(7700)
	defaultRoll=0
	local s0=use(novice,node("gather","Fish",3))
	ok(has(s0.message,"Skylake Minnow") and not has(s0.message,"surfaces"),"Fishing 1 cannot hook a sea creature")
	eq(novice.SeaCreatureSpawn,nil,"no spawn attribute for novices")
	local fisher=angler(7701,10)
	local pond=node("gather","Fish",4)
	local s1=use(fisher,pond)
	ok(has(s1.message,"Shellsnap Crab surfaces!"),"hook announced in the gather message")
	eq(fisher.SeaCreatureSpawn,"ShellsnapCrab:1","spawn attribute names creature and ticket")
	eq(fisher.SeaCreatureAt,Vector3.new(4,0,0),"spawn position is the fishing node")
	eq(s1.items.Fish~=nil and s1.items.Fish>=1,true,"the fish is still caught")
	local miner=angler(7702,10)
	use(miner,node("gather","Ore"))
	eq(miner.SeaCreatureSpawn,nil,"mining never hooks sea creatures")
	defaultRoll=0.999
	local miss=use(fisher,pond)
	ok(not has(miss.message,"surfaces"),"a high roll hooks nothing")
	eq(fisher.SeaCreatureSpawn,"ShellsnapCrab:1","attribute unchanged on a miss")
	defaultRoll=0
	use(fisher,pond); use(fisher,pond)
	eq(fisher.SeaCreatureSpawn,"ShellsnapCrab:3","three live tickets")
	local capped=use(fisher,pond)
	ok(has(capped.message,"Skylake Minnow") and not has(capped.message,"surfaces"),"fourth creature refused at the cap")
	eq(fisher.SeaCreatureSpawn,"ShellsnapCrab:3","cap holds the attribute")
	defaultRoll=saved

	-- Bridge grants: only the owner's live ticket pays, once.
	local function seaOp(p,payload) return bridge.OnInvoke("seaCreature",p,payload) end
	local snap=st(fisher)
	local beforeState={xp={Fishing=snap.xp.Fishing,Combat=snap.xp.Combat},coins=snap.coins,items={BrineShell=snap.items.BrineShell}}
	defaultRoll=0
	local paid=seaOp(fisher,{seq=1,monster="ShellsnapCrab",result="kill"})
	defaultRoll=saved
	eq(paid.ok,true,"owner kill accepted")
	ok(paid.drops.BrineShell~=nil and paid.drops.BrineShell>=1,"kill rolls the creature's drops")
	ok(has(fisher.last.message,"Shellsnap Crab slain"),"kill pushes a snapshot message")
	local after=st(fisher)
	eq(after.xp.Fishing-beforeState.xp.Fishing,SC.ShellsnapCrab.fishingXp,"kill grants Fishing XP")
	eq(after.xp.Combat-beforeState.xp.Combat,SC.ShellsnapCrab.xp,"kill grants Combat XP")
	eq(after.coins-beforeState.coins,SC.ShellsnapCrab.coins,"kill grants coins")
	eq(after.depth.bestiary.ShellsnapCrab,1,"kill records a bestiary entry")
	local afterFishing=after.xp.Fishing
	eq((after.items.BrineShell or 0)-(beforeState.items.BrineShell or 0),paid.drops.BrineShell,"drops land in the satchel")
	eq(seaOp(fisher,{seq=1,monster="ShellsnapCrab",result="kill"}).ok,false,"a ticket pays once")
	eq(st(fisher).xp.Fishing,afterFishing,"replayed kill grants nothing")
	eq(seaOp(fisher,{seq=2,monster="TidewyrmMatriarch",result="kill"}).reason,"ticket","a ticket cannot be claimed as another creature")
	local other=angler(7703,10)
	eq(seaOp(other,{seq=2,monster="ShellsnapCrab",result="kill"}).ok,false,"other players cannot claim someone else's ticket")
	eq(bridge.OnInvoke("kill",fisher,{monster="ShellsnapCrab"}),nil,"the marker kill op refuses sea creatures")
	eq(st(fisher).xp.Fishing,afterFishing,"refused claims grant nothing")
	for _,bad in ipairs({{seq="2",monster="ShellsnapCrab",result="kill"},{seq=2.5,monster="ShellsnapCrab",result="kill"},
		{seq=2,monster="ShellsnapCrab",result="win"},{seq=2,result="kill"},{seq=2,monster=42,result="kill"}}) do
		eq(seaOp(fisher,bad).reason,"invalid","malformed sea report rejected")
	end
	eq(seaOp(fisher,nil).ok,false,"missing payload rejected")
	eq(seaOp(fisher,{seq=2,monster="ShellsnapCrab",result="despawn"}).ok,true,"despawn frees a ticket")
	eq(seaOp(fisher,{seq=2,monster="ShellsnapCrab",result="kill"}).ok,false,"a despawned creature cannot be claimed")
	eq(st(fisher).depth.bestiary.ShellsnapCrab,1,"despawn adds no bestiary kill")
	-- Tickets expire with the creature's lifetime (plus grace) and free their slot.
	advance(Data.SeaCreatureLifetime+20)
	eq(seaOp(fisher,{seq=3,monster="ShellsnapCrab",result="kill"}).ok,false,"expired ticket pays nothing")
	defaultRoll=0
	use(fisher,pond)
	eq(fisher.SeaCreatureSpawn,"ShellsnapCrab:4","expired slots free up and the sequence keeps rising")
	defaultRoll=saved
	-- Session rules.
	local back=rejoin(fisher)
	eq(seaOp(back,{seq=4,monster="ShellsnapCrab",result="kill"}).ok,false,"tickets do not survive a rejoin")
	local unsynced=seaOp({UserId=7799},{seq=1,monster="ShellsnapCrab",result="kill"})
	ok(unsynced.ok==false and unsynced.reason=="sync","no live journal, no grant (combat resends while the ticket lasts)")
	-- Bestiary milestones count sea creature kills.
	local hunter=seeded(7704,function(p) p.bestiary.ShellsnapCrab=10 end)
	eq(st(hunter).depth.stats.bestiaryTiers,1,"sea creature kills reach bestiary milestones")
	-- Water gating through the server: a 100% chance buff, pick roll at the top of the pool.
	local surge={expires=utc+3600,stats={seaCreatureChance=100}}
	local reef=angler(7705,40,function(p) p.buffs.Surge=surge end)
	use(reef,node("gather","Fish",2,nil,"Tidewater"))
	local pool=Data.seaCreaturePool(40,"Tidewater")
	eq(reef.SeaCreatureSpawn,pool[#pool]..":1","Tidewater waters hook Tidewater-only creatures")
	eq(pool[#pool],"CoralbackBruiser","Fishing 40 Tidewater pool tops out at the Bruiser")
	local shore=angler(7706,40,function(p) p.buffs.Surge=surge end)
	use(shore,node("gather","Fish",2))
	local homePool=Data.seaCreaturePool(40,nil)
	eq(shore.SeaCreatureSpawn,homePool[#homePool]..":1","home waters never hook Tidewater-only creatures")
	ok(SC[homePool[#homePool]].waters==nil,"home catch is an any-water creature")
	print("PASS: "..(checks-before).." sea creature roll/ticket/grant assertions.")
end

------------------------------------------------------------------------------
-- Island placement (Island Builder team): grid rules, verbs, persistence.
------------------------------------------------------------------------------
do
	local before=checks
	local I=Data.Island
	local serde=require("@lune/serde")
	local function ok(cond,case) assert(cond,case); checks+=1 end
	local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
	-- Requests move only os.clock (cooldowns, rate limit) so leases never lapse.
	local function act(p,verb,item,step)
		clock+=step or 1
		return objects.RemoteFunction.OnServerInvoke(p,verb,item)
	end
	local function seeded(id,edit)
		local pl=player(id)
		act(pl,"state")
		services.Players.PlayerRemoving:Fire(pl)
		edit(data["p"..id].profile)
		return player(id)
	end
	local function rejoin(pl,edit)
		services.Players.PlayerRemoving:Fire(pl)
		if edit then edit(data["p"..pl.UserId].profile) end
		return player(pl.UserId)
	end
	local function setLevel(prof,lvl)
		prof.xp.Carpentry=Progression.xpForLevel(lvl)
		prof.levelRewards.Carpentry=lvl
	end
	local function isle(s) return s.journal.construction.island end
	-- First free anchor (scan order z, x) for a prop given current records.
	local function spot(propId,rot,list)
		local occupied=I.occupancy(list or {})
		for z=-I.RANGE,I.RANGE do
			for x=-I.RANGE,I.RANGE do
				if I.check(occupied,propId,x,z,rot or 0) then return x,z end
			end
		end
		error("no free spot for "..propId)
	end
	local function req(propId,x,z,rot) return propId..":"..x..":"..z..":"..(rot or 0) end

	-- Catalogue integrity.
	ok(#I.PropOrder>=20,"20+ placeable props")
	local perCategory={}
	for _,id in ipairs(I.PropOrder) do
		local def=I.Props[id]
		local costsOk=next(def.costs)~=nil
		for material,n in pairs(def.costs) do costsOk=costsOk and Data.Items[material]~=nil and n>=1 and n==math.floor(n) end
		ok(type(def.name)=="string" and I.CategoryOf[def.category]~=nil and def.level>=1 and def.level<=99 and def.xp>0
			and costsOk and #def.size==2 and def.size[1]>=1 and def.size[1]<=3 and def.size[2]>=1 and def.size[2]<=3
			and def.max>=1 and def.value>=0 and #id<=16 and id:match("^%w+$")~=nil and type(def.text)=="string","prop "..id.." is well formed")
		perCategory[def.category]=(perCategory[def.category] or 0)+1
		if def.effect and def.effect.station then ok(table.find({"Forge","Hearth","Cauldron","Workbench"},def.effect.station)~=nil,id.." station is a known kind") end
	end
	for _,c in ipairs(I.Categories) do ok((perCategory[c] or 0)>=1,"category "..c.." has props") end
	local utility=0
	for _,id in ipairs(I.PropOrder) do if I.Props[id].effect then utility+=1 end end
	ok(utility>=4,"utility props reuse light/station effects")
	ok(I.Props[I.PropOrder[1]].category=="Fences" and I.Props[I.PropOrder[#I.PropOrder]].category=="Utility","catalogue ordered by category")

	-- Grid rules.
	local free=0
	local cornersOk=true
	for z=-I.RANGE,I.RANGE do
		for x=-I.RANGE,I.RANGE do
			if I.cellBlocked(x,z)==nil then
				free+=1
				local fx,fz=math.abs(x*I.CELL)+I.CELL/2,math.abs(z*I.CELL)+I.CELL/2
				cornersOk=cornersOk and fx*fx+fz*fz<=I.RADIUS*I.RADIUS
			end
		end
	end
	ok(free>=I.MAX_PLACEMENTS,"grid holds the placement cap ("..free.." free cells)")
	ok(cornersOk,"every free cell lies fully within the island radius")
	ok(I.RADIUS<19,"buildable radius stays inside the 19-stud meadow")
	ok(I.cellBlocked(0,2)=="home landing","spawn landing protected")
	ok(I.cellBlocked(-3,0)=="windpine","windpine gather node protected")
	ok(I.cellBlocked(4,2)=="worker station","worker station protected")
	ok(I.cellBlocked(-5,0)=="garden plot","legacy garden plot protected")
	ok(I.cellBlocked(-8,0)=="terrace bridge","terrace bridge approach protected")
	ok(I.cellBlocked(0,8)=="lookout bridge","lookout bridge protected")
	ok(I.cellBlocked(8,8)=="edge" and I.cellBlocked(9,0)=="edge" and I.cellBlocked(0,-9)=="edge","cells beyond the rim are out of bounds")
	ok(I.cellBlocked(0.5,0)=="edge" and I.cellBlocked(0/0,0)=="edge" and I.cellBlocked(math.huge,0)=="edge","non-integer cells refused")
	for _,r in ipairs(I.Protected) do ok(r.x1<r.x2 and r.z1<r.z2 and type(r.name)=="string","protected zone "..r.name.." is a valid rectangle") end
	-- Footprints and rotation.
	local h0=I.cells("HedgeRow",1,2,0)
	ok(#h0==2 and h0[2][1]==2 and h0[2][2]==2,"2x1 footprint runs along x at rot 0")
	local h1=I.cells("HedgeRow",1,2,1)
	ok(#h1==2 and h1[2][1]==1 and h1[2][2]==3,"2x1 footprint runs along z at rot 1")
	ok(#I.cells("GardenGazebo",0,0,3)==9,"3x3 footprint covers nine cells")
	ok(I.cells("HedgeRow",0,0,4)==nil and I.cells("HedgeRow",0,0,-1)==nil and I.cells("Nope",0,0,0)==nil and I.cells("HedgeRow",0.5,0,0)==nil,"malformed footprints refused")
	local snapOk=true
	for _,id in ipairs(I.PropOrder) do
		for rot=0,3 do
			local ox,oz=I.centerOffset(id,3,-2,rot)
			local sx,sz=I.snap(id,rot,ox+0.4,oz-0.4)
			snapOk=snapOk and sx==3 and sz==-2
		end
	end
	ok(snapOk,"snapping a prop centre returns its anchor cell for every prop and rotation")
	local gx,gz,yaw=I.centerOffset("HedgeRow",1,2,1)
	ok(gx==2 and gz==5 and math.abs(yaw-math.pi/2)<1e-9,"rotated prop centre and yaw")
	-- Parsing and encoding.
	ok(select(1,I.parseRequest("StonePath:-3:4:1"))=="StonePath","request parses")
	for _,bad in ipairs({"StonePath:3:4","StonePath:a:4:0","StonePath:3:4:12","Stone Path:1:1:0","StonePath:1.5:1:0",("x"):rep(50),""}) do
		ok(I.parseRequest(bad)==nil,"malformed request rejected: "..bad:sub(1,20))
	end
	local roundTrip=I.decode(I.encode({{id=3,prop="HedgeRow",x=-2,z=5,rot=1},{id=7,prop="StonePath",x=0,z=-8,rot=0}}))
	ok(#roundTrip==2 and roundTrip[1].prop=="HedgeRow" and roundTrip[1].z==5 and roundTrip[2].id==7,"records round-trip")
	ok(#I.decode("1:Nope:0:0:0;x;2:StonePath:0:-8:9;0:StonePath:0:-8:0;3:StonePath:0:-8:0")==1,"decode skips malformed records")
	ok(#I.decode(7)==0,"decode tolerates non-strings")
	local tierIndex,tierDef=I.tier(0)
	ok(tierIndex==1 and tierDef.name=="Bare Rock" and select(1,I.tier(10000))==#I.ValueTiers,"value tiers")

	-- Server: fresh island.
	local builder=seeded(4101,function(prof) prof.items={} end)
	local s0=act(builder,"state")
	ok(isle(s0).count==0 and isle(s0).cap==I.MAX_PLACEMENTS and isle(s0).value==0 and isle(s0).tierName=="Bare Rock","fresh island state")
	ok(builder.IslandPlacements=="","empty placement attribute published")
	local fx,fz=spot("TimberFence")
	local m0=act(builder,"place",req("TimberFence",fx,fz))
	ok(has(m0.message,"needs") and isle(m0).count==0,"unfunded prop refused")
	ok(has(act(builder,"place",req("BrassRailing",fx,fz)).message,"Carpentry 25"),"Carpentry level gate")
	builder=rejoin(builder,function(prof)
		prof.items={Timber=200,Ore=200,Herb=200,BrassIngot=10,WindpineLog=40,Aetherite=50,Brassite=20}
		setLevel(prof,25)
	end)
	local xp0=act(builder,"state").xp.Carpentry
	local m1=act(builder,"place",req("TimberFence",fx,fz))
	ok(isle(m1).count==1,"fence placed")
	ok(m1.items.Timber==196,"placement charges materials")
	ok(m1.xp.Carpentry==xp0+I.Props.TimberFence.xp,"placement grants Carpentry XP")
	ok(has(m1.message,"Carpentry XP"),"placement message names the XP")
	ok(builder.IslandPlacements=="1:TimberFence:"..fx..":"..fz..":0","placement replicated as a record")
	ok(isle(m1).value==I.Props.TimberFence.value and isle(m1).counts.TimberFence==1,"island value and counts")
	-- Overlap, protected zones, bounds.
	local m2=act(builder,"place",req("StonePath",fx,fz))
	ok(has(m2.message,"already stands") and isle(m2).count==1 and m2.items.Ore==200,"overlap refused without charge")
	local m3=act(builder,"place",req("StonePath",0,3))
	ok(has(m3.message,"home landing") and isle(m3).count==1,"protected landing refused")
	ok(has(act(builder,"place",req("StonePath",4,2)).message,"worker station"),"worker station zone refused")
	ok(has(act(builder,"place",req("StonePath",8,8)).message,"fully on your island"),"rim cell refused")
	ok(has(act(builder,"place",req("StonePath",40,0)).message,"fully on your island"),"far cell refused")
	local ex,ez
	for x=0,I.RANGE do if I.cellBlocked(x,0)==nil and I.cellBlocked(x+1,0)=="edge" then ex,ez=x,0 end end
	ok(ex~=nil and has(act(builder,"place",req("HedgeRow",ex,ez,0)).message,"fully on your island"),"footprint hanging off the rim refused")
	ok(I.check({},"HedgeRow",ex,ez,1)==(I.cellBlocked(ex,ez+1)==nil),"rotation changes the covered cells")
	-- Overlap across a multi-cell footprint.
	local hx,hz=spot("HedgeRow",0,I.decode(builder.IslandPlacements))
	local m4=act(builder,"place",req("HedgeRow",hx,hz,0))
	ok(isle(m4).count==2,"two-cell hedge placed")
	ok(has(act(builder,"place",req("FlowerPlanter",hx+1,hz,0)).message,"already stands"),"second hedge cell is occupied")
	ok(has(act(builder,"place",req("HedgeRow",hx-1,hz,0)).message,"already stands") or I.cellBlocked(hx-1,hz)~=nil,"overlapping footprint refused")
	for _,bad in ipairs({"HedgeRow:1:1:4","HedgeRow:1:1","Nope:0:-8:0","StonePath:0:-8:-1","StonePath:x:y:0","StonePath:0:-8:0:0",""}) do
		local r=act(builder,"place",bad)
		ok(isle(r).count==2 and r.items.Ore==200,"malformed place request changes nothing: "..bad)
	end
	ok(isle(act(builder,"place")).count==2,"missing place payload changes nothing")
	-- Max count per prop.
	local sx,sz=spot("CarpenterStump",0,I.decode(builder.IslandPlacements))
	local m5=act(builder,"place",req("CarpenterStump",sx,sz))
	ok(isle(m5).counts.CarpenterStump==1,"utility stump placed")
	local s2x,s2z=spot("CarpenterStump",0,I.decode(builder.IslandPlacements))
	local m6=act(builder,"place",req("CarpenterStump",s2x,s2z))
	ok(has(m6.message,"most") and isle(m6).counts.CarpenterStump==1 and m6.items.Timber==m5.items.Timber,"max count enforced")
	-- Pickup: full refund, no XP farming, id reuse.
	local timberBefore,xpBefore=m6.items.Timber,m6.xp.Carpentry
	local p1=act(builder,"pickup","1")
	ok(isle(p1).count==2 and p1.items.Timber==timberBefore+4,"pickup refunds the full material cost")
	ok(not has(builder.IslandPlacements,"TimberFence"),"pickup updates the replicated records")
	ok(p1.xp.Carpentry==xpBefore,"pickup does not touch XP")
	local p2=act(builder,"place",req("TimberFence",fx,fz))
	ok(p2.xp.Carpentry==xpBefore,"re-placing a picked-up copy pays no XP again")
	ok(isle(p2).paid.TimberFence==1,"paid high-water mark kept")
	ok(has(builder.IslandPlacements,"1:TimberFence:"),"smallest free id reused")
	local f2x,f2z=spot("TimberFence",0,I.decode(builder.IslandPlacements))
	local p3=act(builder,"place",req("TimberFence",f2x,f2z))
	ok(p3.xp.Carpentry==xpBefore+I.Props.TimberFence.xp and isle(p3).paid.TimberFence==2,"a second copy pays XP")
	ok(has(act(builder,"pickup","99").message,"no longer"),"unknown placement id refused")
	for _,bad in ipairs({"x","-1","1.5","",("9"):rep(60)}) do
		local r=act(builder,"pickup",bad)
		ok(isle(r).count==isle(p3).count,"malformed pickup changes nothing: "..bad:sub(1,10))
	end
	ok(isle(act(builder,"pickup")).count==isle(p3).count,"missing pickup payload changes nothing")
	-- Persistence.
	local recordsBefore=builder.IslandPlacements
	builder=rejoin(builder)
	local r1=act(builder,"state")
	ok(builder.IslandPlacements==recordsBefore,"placements restored on join")
	ok(isle(r1).count==isle(p3).count and isle(r1).paid.TimberFence==2,"placements and XP marks persist")
	ok(type(data.p4101.profile.island.placed[1])=="string","profile stores compact record strings")
	-- Rate limit: a burst of rapid verbs is throttled.
	local throttled,accepted=0,0
	for _=1,30 do
		local r=act(builder,"pickup","98",0.25)
		if has(r.message,"too quickly") then throttled+=1 elseif has(r.message,"no longer") then accepted+=1 end
	end
	ok(throttled>0,"rapid placement verbs are rate limited")
	ok(accepted<=I.BURST+math.ceil(30*0.25*I.RATE),"rate limit bounds accepted verbs")
	clock+=10

	-- Tampered saves are sanitized on open.
	local tamper=seeded(4102,function(prof)
		local x,z=spot("StonePath")
		prof.island={placed={
			"1:StonePath:"..x..":"..z..":0",
			"2:StonePath:"..x..":"..z..":0",          -- overlaps record 1
			"1:Boardwalk:0:-8:0",                      -- duplicate id
			"3:StonePath:0:3:0",                       -- protected landing
			"4:StonePath:8:8:0",                       -- off the rim
			"5:Nope:0:-8:0",7,{},"6:CarpenterStump:-6:-3:0","7:CarpenterStump:-4:-3:0", -- second stump over max
			"8:StonePath:0:-8:9",("1"):rep(80),
		},paid={StonePath=999,Nope=3,Boardwalk="x",TimberFence=-2}}
	end)
	local t1=act(tamper,"state")
	ok(isle(t1).count==2,"only valid, non-overlapping records survive ("..isle(t1).count..")")
	ok(isle(t1).counts.CarpenterStump==1,"per-prop max enforced on load")
	ok(isle(t1).paid.StonePath==I.Props.StonePath.max and isle(t1).paid.Nope==nil and isle(t1).paid.Boardwalk==nil and isle(t1).paid.TimberFence==nil,"paid marks clamped and cleaned")
	local garbage=seeded(4103,function(prof) prof.island="lots" end)
	ok(isle(act(garbage,"state")).count==0,"non-table island record reset")

	-- Placement cap and worst-case save size.
	local full=seeded(4104,function(prof)
		local list={}
		for z=-I.RANGE,I.RANGE do
			for x=-I.RANGE,I.RANGE do
				if #list<I.MAX_PLACEMENTS and I.cellBlocked(x,z)==nil then
					local prop=if #list<60 then "StonePath" else "Boardwalk"
					table.insert(list,{id=#list+1,prop=prop,x=x,z=z,rot=0})
				end
			end
		end
		local placed={}
		for i,e in ipairs(list) do placed[i]=I.record(e) end
		prof.island={placed=placed,paid={}}
		prof.items={Timber=100,Ore=100}
		setLevel(prof,10)
	end)
	local c1=act(full,"state")
	ok(isle(c1).count==I.MAX_PLACEMENTS,"a full island loads")
	local lastX,lastZ
	local fullOccupied=I.occupancy(I.decode(full.IslandPlacements))
	for z=-I.RANGE,I.RANGE do for x=-I.RANGE,I.RANGE do
		if I.check(fullOccupied,"TimberFence",x,z,0) then lastX,lastZ=x,z end
	end end
	ok(lastX~=nil,"a free cell remains on the full island")
	local c2=act(full,"place",req("TimberFence",lastX,lastZ))
	ok(has(c2.message,"at most") and isle(c2).count==I.MAX_PLACEMENTS and c2.items.Timber==100,"total placement cap enforced")
	ok(isle(c2).value==I.MAX_PLACEMENTS and isle(c2).tierName=="Charming Cottage","island value sums placed props")
	local fullBytes=#serde.encode("json",data.p4104.profile.island)
	-- Worst case: every record with the longest prop id, a 3-digit id and
	-- two-character coordinates, plus every paid mark at its maximum.
	local longest=""
	for _,id in ipairs(I.PropOrder) do if #id>#longest then longest=id end end
	local worst={placed={},paid={}}
	for i=1,I.MAX_PLACEMENTS do worst.placed[i]=I.record({id=100+i%20,prop=longest,x=-8,z=-8,rot=3}) end
	for _,id in ipairs(I.PropOrder) do worst.paid[id]=I.Props[id].max end
	local worstBytes=#serde.encode("json",worst)
	ok(worstBytes<=6000,"worst-case island save stays bounded ("..worstBytes.." bytes)")
	ok(fullBytes<=worstBytes,"a real full island is below the worst case ("..fullBytes.." bytes)")
	ok(#full.IslandPlacements<=I.MAX_PLACEMENTS*31,"replicated attribute stays bounded")
	print("Island save sizes: full "..fullBytes.." / worst-case "..worstBytes.." JSON bytes.")
	print("PASS: "..(checks-before).." island placement assertions.")
end

-- Combat styles: new skills, Fletching/Glyphcraft crafting, the Quiver slot,
-- autocast verb, bridge ops "consume" and "combatXp", stats loadout, persistence.
;(function()
	local before=checks
	local function hook(name) for _,o in ipairs(allObjects) do if o.Name==name then return o end end return nil end
	local bridge=hook("IsleBridge")
	local function cmd(p,verb,item) advance(1); return objects.RemoteFunction.OnServerInvoke(p,verb,item) end
	local function st(p) return cmd(p,"state") end
	local function ok(cond,case) assert(cond,case); checks+=1 end
	local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
	local function seeded(id,mutate)
		local p=player(id)
		services.Players.PlayerRemoving:Fire(p)
		mutate(data["p"..id].profile)
		return player(id)
	end
	local function rejoin(p) services.Players.PlayerRemoving:Fire(p); return player(p.UserId) end
	local recruit=player(9100)
	local s=st(recruit)
	for _,skill in ipairs({"Ranged","Magic","Fletching","Glyphcraft"}) do
		eq(s.depth.skills[skill].level,1,"fresh "..skill.." level")
		eq(s.xp[skill],0,"fresh "..skill.." xp")
	end
	eq(s.depth.combat.style,"melee","fresh journals fight in melee")
	eq(s.depth.combat.ammoCount,0,"fresh quiver empty")
	eq(s.depth.combat.autocast,nil,"no autocast")
	eq(s.depth.stats.rangedStrength,0,"ranged strength on the sheet")
	-- Fletching from raw materials to a loaded quiver.
	local archer=seeded(9101,function(p) p.items={Timber=20,BeastHide=3,Herb=40,AlloyIngot=2} end)
	local shafts=cmd(archer,"craft","ArrowShaft")
	ok(has(shafts.message,"Arrow Shaft crafted"),"shafts fletched")
	eq(shafts.items.ArrowShaft,15,"fifteen shafts per timber")
	eq(shafts.xp.Fletching,Data.Recipes.ArrowShaft.xp,"Fletching XP")
	eq(cmd(archer,"craft","Bowstring").items.Bowstring,2,"two strings per hide")
	local bow=cmd(archer,"craft","MeadowShortbow")
	eq(bow.items.MeadowShortbow,1,"meadow shortbow fletched")
	eq(cmd(archer,"craft","CopperHeads").items.CopperHeads,15,"copper arrowheads forged")
	for _=1,3 do cmd(archer,"craft","DriftPlume") end
	eq(st(archer).items.DriftPlume,18,"plumes fletched from leaves")
	local arrows=cmd(archer,"craft","CopperArrow")
	eq(arrows.items.CopperArrow,15,"fifteen arrows")
	eq(arrows.items.ArrowShaft,0,"shafts consumed"); eq(arrows.items.CopperHeads,0,"heads consumed")
	eq(cmd(archer,"craft","WindpineShortbow").message:find("Fletching 15",1,true)~=nil,true,"higher bows gated by Fletching")
	ok(has(cmd(archer,"equip","MeadowShortbow").message,"Equipped"),"bow equipped in the weapon slot")
	ok(has(cmd(archer,"equip","CopperArrow").message,"Equipped"),"arrows equipped in the quiver")
	local loaded=st(archer)
	eq(loaded.depth.equipment.ammo,"CopperArrow","ammo slot in the snapshot")
	eq(loaded.depth.combat.style,"ranged","bow makes the style ranged")
	eq(loaded.depth.combat.ammo,"CopperArrow","quivered arrow")
	eq(loaded.depth.combat.ammoCount,15,"quiver count")
	eq(loaded.depth.stats.critChance,Data.Stats.critChance.base+Data.Items.MeadowShortbow.stats.critChance,"bow stats on the sheet")
	local sheet=bridge.OnInvoke("stats",archer)
	eq(sheet.loadout.style,"ranged","bridge stats carry the loadout")
	eq(sheet.loadout.weapon,"MeadowShortbow","loadout weapon")
	eq(sheet.loadout.supplies.CopperArrow,15,"loadout supplies")
	-- consume: atomic, combat items only.
	local paid=bridge.OnInvoke("consume",archer,{items={CopperArrow=1}})
	eq(paid.ok,true,"arrow paid"); eq(paid.remaining.CopperArrow,14,"remaining arrows")
	eq(bridge.OnInvoke("consume",archer,{items={Timber=1}}).reason,"invalid","non-combat items cannot be consumed")
	eq(bridge.OnInvoke("consume",archer,{items={CopperArrow=0}}).reason,"invalid","zero refused")
	eq(bridge.OnInvoke("consume",archer,{items={CopperArrow=1.5}}).reason,"invalid","fractions refused")
	eq(bridge.OnInvoke("consume",archer,{items={CopperArrow=51}}).reason,"invalid","more than 50 refused")
	eq(bridge.OnInvoke("consume",archer,{items={}}).reason,"invalid","empty payment refused")
	eq(bridge.OnInvoke("consume",archer,{}).reason,"invalid","missing items refused")
	local short=bridge.OnInvoke("consume",archer,{items={CopperArrow=5,GaleGlyph=1}})
	eq(short.ok,false,"partial payment refused"); eq(short.reason,"missing","missing reason")
	eq(st(archer).items.CopperArrow,14,"a refused payment takes nothing")
	eq(bridge.OnInvoke("consume",lateOpen,{items={CopperArrow=1}}),nil,"expired lease cannot pay")
	-- refund: returns what a failed Hubward paid; same validation as consume.
	eq(bridge.OnInvoke("refund",archer,{items={CopperArrow=1}}).ok,true,"refund accepted")
	eq(st(archer).items.CopperArrow,15,"refund returns the item")
	eq(bridge.OnInvoke("refund",archer,{items={Timber=1}}).reason,"invalid","non-combat items cannot be refunded")
	eq(bridge.OnInvoke("refund",archer,{items={CopperArrow=51}}).reason,"invalid","refund bounded like consume")
	eq(bridge.OnInvoke("refund",archer,{}).reason,"invalid","missing refund items refused")
	eq(bridge.OnInvoke("refund",lateOpen,{items={CopperArrow=1}}),nil,"expired lease cannot be refunded")
	eq(bridge.OnInvoke("consume",archer,{items={CopperArrow=1}}).remaining.CopperArrow,14,"back to 14 arrows")
	-- combatXp: style routing, Combat share, fractions carried.
	local xp0=table.clone(st(archer).xp)
	local reply=bridge.OnInvoke("combatXp",archer,{style="ranged",monster="BramblebackBoar",damage=60})
	eq(reply.ok,true,"xp accepted")
	eq(reply.xp.Ranged,6,"ranged damage trains Ranged"); eq(reply.xp.Combat,2,"a third into Combat")
	local xp1=table.clone(st(archer).xp)
	eq(xp1.Ranged-xp0.Ranged,6,"Ranged XP granted"); eq(xp1.Combat-xp0.Combat,2,"Combat share granted")
	bridge.OnInvoke("combatXp",archer,{style="ranged",monster="BramblebackBoar",damage=5})
	eq(st(archer).xp.Ranged,xp1.Ranged,"half an XP point carried")
	bridge.OnInvoke("combatXp",archer,{style="ranged",monster="BramblebackBoar",damage=5})
	eq(st(archer).xp.Ranged,xp1.Ranged+1,"carried fractions add up")
	local melee=bridge.OnInvoke("combatXp",archer,{style="melee",monster="ShaleCrawler",damage=350})
	eq(melee.xp.Combat,Data.Monsters.ShaleCrawler.xp,"melee damage trains Combat only")
	eq(melee.xp.Ranged,nil,"melee trains no Ranged")
	local spell=bridge.OnInvoke("combatXp",archer,{style="magic",spell="GaleDart"})
	eq(spell.xp.Magic,Data.Spells.GaleDart.xp,"spell cast XP")
	eq(next(bridge.OnInvoke("combatXp",archer,{style="ranged",spell="GaleDart"}).xp),nil,"cast XP only for magic")
	eq(bridge.OnInvoke("combatXp",archer,{style="sneaky",monster="BramblebackBoar",damage=60}).ok,false,"unknown style refused")
	eq(next(bridge.OnInvoke("combatXp",archer,{style="ranged",monster="Dragon",damage=60}).xp),nil,"unknown monster grants nothing")
	eq(next(bridge.OnInvoke("combatXp",archer,{style="ranged",monster="BramblebackBoar",damage=0/0}).xp),nil,"NaN damage grants nothing")
	local capped=bridge.OnInvoke("combatXp",archer,{style="magic",monster="BramblebackBoar",damage=1e9})
	eq(capped.xp.Magic,Data.Monsters.BramblebackBoar.xp,"damage XP capped at the monster's health")
	local boss=bridge.OnInvoke("combatXp",archer,{style="melee",monster="Boss:Bramble",tier=1,damage=Data.Slayers.Bramble.tiers[1].hp})
	eq(boss.xp.Combat,math.floor(Data.Slayers.Bramble.tiers[1].spawnXp*Data.CombatStyles.bossXpShare),"slayer boss damage XP")
	eq(next(bridge.OnInvoke("combatXp",archer,{style="melee",monster="Boss:Bramble",tier=9,damage=100}).xp),nil,"unknown boss tier")
	local sea=bridge.OnInvoke("combatXp",archer,{style="ranged",monster="ShellsnapCrab",damage=Data.SeaCreatures.ShellsnapCrab.hp})
	eq(sea.xp.Ranged,Data.SeaCreatures.ShellsnapCrab.xp,"sea creature damage XP")
	local big=bridge.OnInvoke("combatXp",archer,{style="ranged",monster="StarbornSentinel",damage=20000})
	eq(big.levelled,true,"a level-up is flagged")
	ok(has(archer.last.message,"Ranged level"),"level-up pushes a snapshot message")
	eq(bridge.OnInvoke("combatXp",lateOpen,{style="ranged",monster="BramblebackBoar",damage=60}),nil,"expired lease earns nothing")
	-- autocast verb.
	ok(has(cmd(archer,"autocast","GaleLance").message,"Magic 30"),"autocast respects the Magic level")
	ok(has(cmd(archer,"autocast","Mend").message,"combat spell"),"utility spells cannot autocast")
	ok(has(cmd(archer,"autocast","Fireball").message,"combat spell"),"unknown spells refused")
	ok(has(cmd(archer,"autocast","GaleDart").message,"Autocasting Gale Dart"),"autocast set")
	eq(st(archer).depth.combat.autocast,"GaleDart","autocast in the snapshot")
	eq(bridge.OnInvoke("stats",archer).loadout.autocast,"GaleDart","autocast reaches Combat")
	-- Persistence across a rejoin.
	archer=rejoin(archer)
	local saved=data.p9101.profile
	eq(saved.autocast,"GaleDart","autocast persisted")
	eq(saved.equipment.ammo,"CopperArrow","quiver persisted")
	eq(saved.equipment.weapon,"MeadowShortbow","bow persisted")
	ok(saved.xp.Ranged>0 and saved.xp.Fletching>0 and saved.xp.Magic>0,"new skill XP persisted")
	local back=st(archer)
	eq(back.depth.combat.ammoCount,14,"quiver count survives the rejoin")
	ok(has(cmd(archer,"autocast","none").message,"cleared"),"autocast cleared")
	eq(st(archer).depth.combat.autocast,nil,"no autocast after clearing")
	ok(has(cmd(archer,"unequip","ammo").message,"Unequipped"),"quiver emptied")
	eq(st(archer).depth.combat.ammo,nil,"no ammo after unequip")
	-- Equip gates: arrows need their Ranged level.
	local novice=seeded(9102,function(p) p.items={BrassArrow=15,MeadowStaff=1} end)
	ok(has(cmd(novice,"equip","BrassArrow").message,"Ranged 5"),"brass arrows need Ranged 5")
	ok(has(cmd(novice,"equip","MeadowStaff").message,"Equipped"),"staff equipped")
	local mage=st(novice)
	eq(mage.depth.combat.style,"magic","staff makes the style magic")
	eq(mage.depth.stats.intelligence,100+Data.Items.MeadowStaff.stats.intelligence,"staff intelligence")
	-- Migration drops invalid autocasts and backfills the new skills.
	local legacy=seeded(9103,function(p) p.autocast="Fireball"; p.xp.Ranged=nil; p.xp.Glyphcraft="x" end)
	local migrated=st(legacy)
	eq(migrated.depth.combat.autocast,nil,"invalid autocast ignored")
	legacy=rejoin(legacy)
	eq(data.p9103.profile.autocast,nil,"invalid autocast dropped on load")
	eq(migrated.xp.Ranged,0,"missing new skill backfilled")
	eq(migrated.xp.Glyphcraft,0,"malformed new skill reset")
	local utility=seeded(9104,function(p) p.autocast="Mend" end)
	st(utility)
	utility=rejoin(utility)
	eq(data.p9104.profile.autocast,nil,"utility autocast dropped on load")
	-- Glyphcraft: glyphs and the hub tablet.
	local scribe=seeded(9105,function(p) p.items={Aetherite=10,ArcaneDust=4} end)
	eq(cmd(scribe,"craft","GaleGlyph").items.GaleGlyph,5,"five gale glyphs per aetherite")
	eq(cmd(scribe,"craft","SparkGlyph").items.SparkGlyph,3,"three spark glyphs")
	ok(has(cmd(scribe,"craft","HubwardTablet").message,"Glyphcraft 15"),"tablets need Glyphcraft 15")
	eq(st(scribe).xp.Glyphcraft,Data.Recipes.GaleGlyph.xp+Data.Recipes.SparkGlyph.xp,"Glyphcraft XP")
	print("PASS: "..(checks-before).." combat style server assertions.")
end)()
