-- Workers depth suite (Data.Workers + server worker verbs). Reuses the
-- verify-gameplay.luau harness: the production server script runs against
-- deterministic Roblox doubles; os.time() is the controllable utc clock.
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
local closers = {} -- game:BindToClose callbacks (Endgame: the shutdown sigil drain test runs them last)
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
	game={GetService=function(_,name) return services[name] end, BindToClose=function(_,f) table.insert(closers,f) end},
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
local function ok(cond,case) assert(cond,case); checks+=1 end
local function has(text,part) return type(text)=="string" and string.find(text,part,1,true)~=nil end
local function st(p) return cmd(p,"state") end
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
-- Leave, let time pass, rejoin (leases lapse after 180 s without autosaves).
local function away(p,seconds)
	services.Players.PlayerRemoving:Fire(p)
	advance(seconds)
	return player(p.UserId)
end
local W=Data.Workers

------------------------------------------------------------------------------
-- 1. Data: worker types, condensed forms, parts, recipes.
------------------------------------------------------------------------------
do
	local gather,combat=0,0
	for skill,tiers in pairs(Data.ResourceTiers) do
		for _,r in ipairs(tiers) do
			local t=W.TypeById[r.id]
			ok(t~=nil and t.kind=="gather" and t.output==r.id and t.skill==skill,r.id.." has a gathering worker type")
			eq(t.collectionTier,W.gatherCollectionTier(r),r.id.." worker collection gate")
			if r.level>=60 then ok(t.collectionTier>=4 and t.collectionTier<=5,r.id.." high-tier worker needs collection tier 4-5") end
			eq(t.region,W.ResourceRegion[r.id],r.id.." worker region gate")
			eq(t.level,if r.index==1 then 1 else r.level,r.id.." worker level gate")
			gather+=1
		end
	end
	for _,t in ipairs(W.Types) do
		ok(W.TypeById[t.id]==t and W.Types[t.index]==t,t.id.." indexed")
		ok(Data.Items[t.output]~=nil,t.id.." output is an item")
		ok(type(t.name)=="string" and #t.name>0 and type(t.shape)=="string" and type(t.color)=="string" and #t.color==6,t.id.." art metadata")
		ok(t.speed>=1 and t.xp>=3,t.id.." pace and XP")
		ok(Data.Skills[t.skill]~=nil,t.id.." skill exists")
		if t.kind=="combat" then
			combat+=1
			ok(t.speed>1,t.id.." combat workers are slower")
			eq(t.collectionTier,3,t.id.." combat worker needs the drop collection tier 3")
			ok(Data.Monsters and t.output~=nil,t.id.." produces a monster drop")
		end
		local press=W.Press[t.output]
		ok(press~=nil,t.id.." output can be pressed")
		local cd,rd=Data.Items[press.condensed],Data.Items[press.radiant]
		ok(cd and cd.kind=="material" and rd and rd.kind=="material",t.output.." condensed forms are materials")
		eq(cd.value,Data.Items[t.output].value*160,t.output.." condensed value is 160x")
		eq(rd.value,cd.value*160,t.output.." radiant value is 160x condensed")
		ok(Data.Economy.isCommodity(press.condensed) and Data.Economy.isCommodity(press.radiant),t.output.." condensed forms trade on the Bazaar")
		eq(Data.Economy.bazaarGroup(press.condensed),"Materials",t.output.." condensed Bazaar group")
		local rc,rr=Data.Recipes[press.condensed],Data.Recipes[press.radiant]
		ok(rc and rc.costs[t.output]==160 and rc.station=="Workbench" and rc.repeatable,t.output.." condensed recipe 160 -> 1")
		ok(rr and rr.costs[press.condensed]==160 and rr.collectionTier[t.output]==6,t.output.." radiant recipe 160 -> 1")
		eq(W.PressSource[press.condensed].units,160,t.output.." condensed counts 160 raw")
		eq(W.PressSource[press.radiant].units,25600,t.output.." radiant counts 25600 raw")
	end
	eq(gather,29,"every gathering resource tier has a worker type")
	ok(combat>=5,"several combat workers")
	eq(#W.Types,gather+combat,"type list complete")
	ok(W.TypeById.ShardlingSentry and W.TypeById.ShardlingSentry.output=="Shard","Shardling Sentry produces Warden Shards")
	ok(W.TypeById.Shard==nil,"raw drop ids are not worker types")
	-- Parts.
	for _,id in ipairs(W.FuelOrder) do
		local f,def,rec=W.Fuels[id],Data.Items[id],Data.Recipes[id]
		ok(def and def.kind=="material" and def.workerFuel and rec and rec.station=="Workbench" and rec.skill=="Carpentry",id.." fuel crafted at the Workbench")
		ok(f.speed>0 and (f.permanent or f.duration>0),id.." fuel effect")
	end
	ok(W.Fuels.EverflameHeart.permanent and not W.Fuels.CharredBriquette.permanent,"one rare permanent fuel")
	eq(Data.Recipes.CharredBriquette.costs.Timber,24,"briquettes burn logs")
	for _,id in ipairs(W.UpgradeOrder) do
		ok(Data.Items[id].workerUpgrade==W.Upgrades[id].group and Data.Recipes[id]~=nil,id.." upgrade item and recipe")
	end
	for _,id in ipairs(W.ChestOrder) do ok(Data.Items[id].workerChest==W.Chests[id].capacity and Data.Recipes[id]~=nil,id.." chest item and recipe") end
	eq(#W.UpgradeOrder,5,"five upgrade kinds")
	eq(W.Upgrades.WorkerBundler.press,1,"compactor packs condensed")
	eq(W.Upgrades.WorkerAetherPress.press,2,"super-compactor packs radiant")
	eq(W.Upgrades.WorkerCoinchute.sell,0.5,"auto-seller pays 50%")
	-- Higher recipes that consume condensed forms.
	local users=0
	for id,rec in pairs(Data.Recipes) do
		if rec.category~="Compacting" then
			for cost in pairs(rec.costs) do if W.PressSource[cost] then users+=1 break end end
		end
	end
	ok(users>=4 and users<=8,"4-8 higher recipes use condensed forms ("..users..")")
	ok(Data.Recipes.WorkerAetherPress.costs.CondensedAetherite==2,"Aether Press needs Condensed Aetherite")
	ok(Data.Recipes.WorkerVaultChest.costs.CondensedStarwoodLog==1,"Vaultwork Chest needs Condensed Starwood")
	-- Ids stay short enough for DataStore keys and Bazaar receipts.
	for id in pairs(W.PressSource) do ok(#id<=24,id.." id length") end
end

------------------------------------------------------------------------------
-- 2. Pure rules: slots, intervals, storage, pressing, settling.
------------------------------------------------------------------------------
do
	eq(W.slotsFor(0),3,"three base slots")
	eq(W.slotsFor(4),3,"4 uniques: still 3")
	eq(W.slotsFor(5),4,"5 uniques: slot 4")
	eq(W.slotsFor(110),12,"110 uniques: all 12")
	eq(W.slotsFor(10000),12,"slot cap 12")
	eq(W.nextSlotAt(0),5,"next slot at 5")
	eq(W.nextSlotAt(56),72,"next slot after 56")
	eq(W.nextSlotAt(110),nil,"no slot after 12")
	local prev=0
	for i,need in ipairs(W.SlotUniques) do ok(need>prev,"slot thresholds rise "..i); prev=need end
	eq(#W.SlotUniques,W.MAX_SLOTS-W.BASE_SLOTS,"one threshold per extra slot")
	ok(W.SlotUniques[#W.SlotUniques]<=#W.Types*#Data.WorkerTiers,"12 slots reachable")
	-- Intervals: tier ladder x type speed x haste.
	eq(W.interval("Ore",1,0),120,"tier 1 interval")
	eq(W.interval("Ore",7,0),26,"tier 7 interval")
	eq(W.interval("Celestium",4,0),48*8,"high tiers share the ladder, paced by respawn (x8)")
	eq(W.interval("Ore",1,0.3),84,"30% haste")
	eq(W.interval("Ore",1,0.9),84,"haste capped by MAX_WORKER_HASTE")
	eq(W.interval("ShardlingSentry",1,0),600,"Shardling Sentry 5x slower")
	eq(W.interval("WispglowLantern",7,0),182,"Wispglow Lantern 7x tier 7")
	eq(W.interval("HidetanSnare",2,0.1),324,"4x with 10% haste")
	eq(W.interval("Brassite",1,0.3),202,"2.4x with 30% haste rounds")
	-- Storage: tier + annex + chest.
	eq(W.capacity({tier=1,upgrades={false,false}}),120,"tier 1 storage")
	eq(W.capacity({tier=1,upgrades={"WorkerStoreAnnex",false}}),180,"annex +50%")
	eq(W.capacity({tier=1,upgrades={false,false},chest="WorkerCoffer"}),240,"coffer +120")
	eq(W.capacity({tier=7,upgrades={false,"WorkerStoreAnnex"},chest="WorkerVaultChest"}),2460,"tier 7 annex vault")
	eq(W.capacity({tier=99,upgrades={}}),Data.WorkerTiers[#Data.WorkerTiers].capacity,"tier clamp")
	-- Pressing.
	local s={}
	eq(W.produce(s,200,120,0,"Ore"),120,"no press fills storage")
	eq(s.Ore,120,"raw stored")
	s={}
	eq(W.produce(s,1000,120,1,"Ore"),120,"press needs 160 storage to condense")
	eq(s.CondensedOre,nil,"tier 1 storage never condenses")
	s={}
	eq(W.produce(s,1000,200,1,"Ore"),1000,"press frees storage")
	eq(s.CondensedOre,6,"1000 -> 6 condensed")
	eq(s.Ore,40,"remainder raw")
	s={}
	eq(W.produce(s,160*160+5,1000,2,"Ore"),25605,"aether press")
	eq(s.RadiantOre,1,"25600 -> 1 radiant")
	eq(s.CondensedOre,nil,"condensed folded")
	eq(s.Ore,5,"raw remainder")
	s={Ore=300}
	eq(W.produce(s,0,1000,1,"Ore"),0,"zero work")
	eq(W.produce(s,1,1000,1,"Ore"),1,"late press condenses stock")
	eq(s.CondensedOre,1,"stock condensed")
	eq(s.Ore,141,"stock remainder")
	s={ArcaneDust=100}
	eq(W.produce(s,100,120,0,"Ore"),20,"other items share storage")
	s={CondensedOre=40,Ore=0}
	eq(W.produce(s,10000,200,1,"Ore"),319,"one more block, then raw fills the rest")
	eq(s.CondensedOre,41,"one more block")
	eq(s.Ore,159,"raw stops one short of the next block")
	eq(W.storeCount(s),200,"store full")
	eq(W.storeValue({Ore=2,CondensedOre=1}),8+640,"store value")
	-- Settling.
	local w={resource="Ore",tier=1,lastClaim=0,upgrades={false,false}}
	eq(W.settle(w,1200,0),10,"10 items in 1200 s")
	eq(w.store.Ore,10,"settled into store")
	eq(w.made,10,"pending XP units")
	eq(w.carry,0,"no partial work")
	eq(W.settle(w,1259,0),0,"partial cycle")
	eq(w.carry,5900,"partial carried")
	eq(W.settle(w,1320,0),1,"carry completes a cycle")
	eq(W.settle(w,1320,0),0,"same second settles nothing")
	eq(W.settle(w,1000,0),0,"clock skew settles nothing")
	eq(w.lastClaim,1000,"skew pulls lastClaim back")
	w={resource="Ore",tier=1,lastClaim=0,fuel={id="StormcellCanister",expires=100000},upgrades={false,false}}
	eq(W.settle(w,1200,0),11,"+12% fuel")
	eq(w.carry,2400,"fuel carry")
	ok(w.fuel~=nil,"fuel still burning")
	w={resource="Ore",tier=1,lastClaim=0,fuel={id="StormcellCanister",expires=600},upgrades={false,false}}
	eq(W.settle(w,1200,0),10,"fuel counts only while burning")
	eq(w.fuel,nil,"burnt fuel cleared")
	w={resource="Ore",tier=1,lastClaim=0,fuel={id="EverflameHeart",permanent=true},upgrades={false,false}}
	eq(W.settle(w,1200,0),11,"permanent +10%")
	ok(w.fuel and w.fuel.permanent,"permanent fuel stays")
	eq(W.speedPercent(w,1200),110,"speed percent")
	eq(W.perHour(w,1200,0),33,"output per hour")
	w={resource="Ore",tier=1,lastClaim=0,upgrades={false,false}}
	eq(W.settle(w,1200,0.3),14,"haste in settle")
	-- Storage cap and auto-seller.
	w={resource="Ore",tier=1,lastClaim=0,upgrades={false,false}}
	eq(W.settle(w,120*500,0),120,"offline output capped by storage")
	eq(w.carry,0,"full storage drops partial work")
	w={resource="Ore",tier=1,lastClaim=0,upgrades={"WorkerCoinchute",false}}
	eq(W.settle(w,120*1440,0),1440,"auto-seller keeps working")
	eq(w.coins,11*120*4//2,"auto-seller pays 50% per full store")
	eq(w.store.Ore,120,"last fill stays stored")
	eq(w.sold,11*120,"sold count")
	w={resource="Ore",tier=1,lastClaim=0,upgrades={"WorkerCoinchute",false}}
	eq(W.settle(w,86400*30,0),W.MAX_ACCRUAL//120,"accrual capped at 48 h even with auto-sell")
	w={resource="Ore",tier=1,lastClaim=0,upgrades={false,"WorkerGleamSprinkler"},chest="WorkerCoffer"}
	eq(W.settle(w,120*100,0),100,"sprinkler worker output")
	eq(w.store.ArcaneDust,10,"1 Arcane Dust per 10")
	eq(W.storeCount(w.store),110,"bonus uses storage")
	w={resource="Ore",tier=1,lastClaim=0,upgrades={false,"WorkerGleamSprinkler"}}
	W.settle(w,120*125,0)
	eq(W.storeCount(w.store),120,"bonus never overflows storage")
	w={resource="Ore",tier=2,lastClaim=0,upgrades={"WorkerBundler","WorkerCoinchute"},chest="WorkerCoffer"}
	W.settle(w,90*1000,0)
	eq(w.store.CondensedOre,6,"compactor + seller")
	eq(w.coins or 0,0,"no sale before full")
	-- Unique crafts bitmask.
	local u={}
	ok(W.addUnique(u,"Ore",1),"first unique")
	ok(not W.addUnique(u,"Ore",1),"duplicate unique ignored")
	ok(W.addUnique(u,"Ore",7),"tier 7 unique")
	ok(not W.addUnique(u,"Bogus",1),"unknown type ignored")
	ok(not W.addUnique(u,"Ore",8),"tier 8 ignored")
	ok(not W.addUnique(u,"Ore",0),"tier 0 ignored")
	eq(u.Ore,65,"bitmask tiers 1 and 7")
	ok(W.hasUnique(u,"Ore",7) and not W.hasUnique(u,"Ore",2),"hasUnique")
	eq(W.uniqueCount(u),2,"unique count")
	eq(W.uniqueCount({Ore=127,Timber=1,Bogus=127}),8,"unknown keys ignored in count")
	eq(W.blueprintCost("Ore",1).Ore,32,"blueprint tier 1")
	eq(W.blueprintCost("Ore",3).Ore,128,"blueprint tier 3")
	eq(W.blueprintCost("Ore",4).CondensedOre,1,"blueprint tier 4 condensed")
	eq(W.blueprintCost("ShardlingSentry",7).CondensedShard,8,"combat blueprint tier 7")
	eq(W.blueprintCost("Ore",8),nil,"no tier 8 blueprint")
	eq(W.upgradeCost(4).AlloyIngot,4,"upgrade ladder unchanged")
	eq(W.upgradeCost(3,"Celestium").CondensedCelestium,nil,"tiers 1-3 stay cheap")
	eq(W.upgradeCost(4,"Celestium").CondensedCelestium,1,"tier 4 upgrade spends own Condensed output")
	eq(W.upgradeCost(7,"ShardlingSentry").CondensedShard,W.blueprintCost("ShardlingSentry",7).CondensedShard,"upgrade Condensed cost equals the blueprint")
	eq(W.upgradeCost(7,"Ore").AlloyIngot,16,"upgrade keeps the ingot ladder")
	eq(W.buildCost(12).Timber,60,"slot 12 build cost")
end

------------------------------------------------------------------------------
-- 3. Server verbs: build, slots, blueprints, claims.
------------------------------------------------------------------------------
local function items(p,list) for id,n in pairs(list) do p.items[id]=n end end
do
	local p=seeded(9001,function(pr) items(pr,{Timber=1000,Ore=1000,AlloyIngot=100,AetherIngot=100}) end)
	local s=cmd(p,"worker")
	eq(#s.workers,1,"first worker built")
	eq(s.workers[1].resource,"Ore","starts on Copperstone")
	eq(s.workers[1].name,"Copperstone Delver","type name")
	eq(s.workerInfo.uniques,1,"building records a unique craft")
	eq(s.workerInfo.slots,3,"three slots")
	eq(s.workerInfo.nextAt,5,"next slot at 5 uniques")
	eq(s.workerInfo.buildCost.Timber,10,"next build cost")
	eq(p:GetAttribute("WorkerSlots"),3,"world sees unlocked slots")
	eq(cmd(p,"workerBuild","2").workers[2].tier,1,"second worker")
	eq(cmd(p,"workerBuild","3:Timber").workers[3].resource,"Timber","build with a type")
	local locked=cmd(p,"workerBuild","4")
	eq(#locked.workers,3,"slot 4 locked")
	ok(has(locked.message,"unlocks at 5"),"locked slot explains the unlock")
	eq(locked.items.Timber,1000-5-10-15,"locked build is free")
	for _,bad in ipairs({"0","13","1.5","x","-1","4:Bogus","",string.rep("9",70)}) do
		eq(#cmd(p,"workerBuild",bad).workers,3,"bad build '"..bad.."' rejected")
	end
	eq(cmd(p,"workerBuild","3").message,"This worker is already active.","duplicate build")
	-- Blueprints toward slot 4: Ore 1 and Timber 1 already crafted.
	local b=cmd(p,"workerBlueprint","Ore:1")
	ok(has(b.message,"already crafted"),"blueprint duplicate refused")
	ok(has(cmd(p,"workerBlueprint","Ore:3").message,"tier 2 first"),"blueprints are sequential")
	ok(has(cmd(p,"workerBlueprint","Brassite:1").message,"Mining 15"),"blueprint follows type gate")
	ok(has(cmd(p,"workerBlueprint","Shard:1").message,"Choose a worker type"),"drop id is not a type")
	ok(has(cmd(p,"workerBlueprint","Ore:9").message,"Choose a worker type"),"tier 9 refused")
	b=cmd(p,"workerBlueprint","Ore:2")
	eq(b.items.Ore,1000-3-6-9-64,"blueprint tier 2 costs 64 ore")
	eq(b.workerInfo.uniques,3,"blueprint counts")
	cmd(p,"workerBlueprint","Ore:3")
	b=cmd(p,"workerBlueprint","Herb:1")
	ok(has(b.message,"Herb") or has(b.message,"Needs"),"herb blueprint needs herbs")
	eq(b.workerInfo.uniques,4,"herb blueprint unaffordable")
	p=rejoin(p,function(pr) pr.items.Herb=40 end)
	b=cmd(p,"workerBlueprint","Herb:1")
	eq(b.workerInfo.uniques,5,"fifth unique")
	eq(b.workerInfo.slots,4,"slot 4 unlocked")
	ok(has(b.message,"Worker slot 4 unlocked"),"slot unlock announced")
	eq(p:GetAttribute("WorkerSlots"),4,"world sees slot 4")
	eq(b.items.Herb,8,"herb blueprint cost 32")
	eq(cmd(p,"workerBuild","4:Fish").workers[4].resource,"Fish","slot 4 built")
	eq(p:GetAttribute("Worker4Resource"),"Fish","slot 4 published")
	eq(p:GetAttribute("Worker4Tier"),1,"slot 4 tier published")
	eq(p:GetAttribute("Worker12Tier"),0,"slot 12 empty")
	eq(cmd(p,"state").workerInfo.uniques,6,"fish build counts")
	-- Upgrades record uniques and keep the legacy ladder.
	local u=cmd(p,"workerUpgrade","4")
	eq(u.workers[4].tier,2,"slot 4 upgraded")
	eq(u.workerInfo.uniques,7,"upgrade records Fish 2")
	ok(W.hasUnique(u.workerInfo.crafted,"Fish",2),"crafted map exposed")
	for _,bad in ipairs({"5","13","0","x"}) do ok(has(cmd(p,"workerUpgrade",bad).message,"Build this worker first"),"upgrade bad slot "..bad) end
	-- Claims: exact output, claim once, claim all.
	p=away(p,240)
	local before=st(p)
	ok(before.workers[1].ready>=2,"slot 1 accrued")
	local n1,ore0=before.workers[1].ready,before.items.Ore
	local c=cmd(p,"workerClaim","1")
	eq(c.items.Ore,ore0+n1,"claim moves stored ore")
	eq(c.workers[1].ready,0,"claimed store empty")
	eq(cmd(p,"workerClaim","1").items.Ore,c.items.Ore,"claim once")
	ok(has(cmd(p,"workerClaim","1").message,"still being gathered"),"empty claim message")
	p=away(p,240)
	local all=cmd(p,"workerClaimAll")
	ok(has(all.message,"from 4 workers"),"claim all")
	for slot=1,4 do eq(all.workers[slot].ready,0,"claim all empties slot "..slot) end
	ok(has(cmd(p,"workerClaimAll").message,"still gathering"),"claim all twice")
	for _,bad in ipairs({"0","5","13","1.5","x"}) do ok(has(cmd(p,"workerClaim",bad).message,"Build this worker first"),"claim bad slot "..bad) end
	-- Assign: change type claims first; locked types refused.
	p=away(p,130)
	local pre=st(p).workers[2].ready
	local a=cmd(p,"workerAssign","2:Herb")
	eq(a.workers[2].resource,"Herb","type changed")
	eq(a.workers[2].ready,0,"change type restarts")
	ok(pre>=1,"pending output before assign")
	eq(cmd(p,"workerAssign","2:ShardlingSentry").workers[2].resource,"Herb","combat type gated")
	eq(cmd(p,"workerAssign","2:Shard").workers[2].resource,"Herb","drop id refused")
	eq(cmd(p,"workerAssign","9:Ore").workers[9],nil,"unbuilt slot")
	ok(has(cmd(p,"workerAssign","13:Ore").message,"Build this worker first"),"slot 13 refused")
	eq(cmd(p,"workerAssign","2:Herb").message,"Worker already gathering Herb.","same type no-op")
	eq(st(p).workerInfo.uniques,7,"assign records no unique")
end

------------------------------------------------------------------------------
-- 4. Fuel: timed, stacking caps, mixing, permanent.
------------------------------------------------------------------------------
do
	local p=seeded(9002,function(pr)
		items(pr,{Timber=100,Ore=100,CharredBriquette=200,StormcellCanister=3,EverflameHeart=2})
		pr.worker=true
		pr.workers={{resource="Ore",tier=1,lastClaim=utc}}
	end)
	ok(has(cmd(p,"workerFuel","1:EmberwoodBrick").message,"You need"),"fuel must be held")
	ok(has(cmd(p,"workerFuel","1:Timber").message,"Choose a worker fuel"),"non-fuel refused")
	ok(has(cmd(p,"workerFuel","2:CharredBriquette").message,"Build this worker first"),"fuel needs a worker")
	local f=cmd(p,"workerFuel","1:CharredBriquette")
	eq(f.items.CharredBriquette,199,"one briquette burnt")
	eq(f.workers[1].fuel.id,"CharredBriquette","fuel active")
	eq(f.workers[1].speed,105,"+5% speed")
	eq(f.workers[1].fuel.remaining,1800,"30 minute burn")
	f=cmd(p,"workerFuel","1:CharredBriquette:4")
	eq(f.items.CharredBriquette,195,"stacked four more")
	eq(f.workers[1].fuel.remaining,1800*5-1,"same fuel stacks duration")
	ok(has(cmd(p,"workerFuel","1:CharredBriquette:64").message,"at most 64"),"stack cap")
	eq(st(p).items.CharredBriquette,195,"refused stack is free")
	ok(has(cmd(p,"workerFuel","1:CharredBriquette:65").message,"between 1 and 64"),"over-64 batch refused")
	ok(has(cmd(p,"workerFuel","1:CharredBriquette:0").message,"between 1 and 64"),"zero batch refused")
	ok(not has(cmd(p,"workerFuel","1:CharredBriquette:-3").message,"fuelled"),"negative batch refused")
	eq(st(p).items.CharredBriquette,195,"bad batches spend nothing")
	ok(has(cmd(p,"workerFuel","1:StormcellCanister").message,"is burning"),"fuels do not mix")
	ok(has(cmd(p,"workerFuel","1:EverflameHeart").message,"is burning"),"permanent waits for timed fuel")
	eq(st(p).items.StormcellCanister,3,"mixing refused for free")
	-- Production under fuel: 1200 s at +10% = 11 items.
	cmd(p,"workerClaim","1")
	p=rejoin(p,function(pr) pr.workers[1].lastClaim=utc-1199; pr.workers[1].carry=0; pr.workers[1].store={} end)
	eq(st(p).workers[1].ready,10,"fuelled production (+5%)")
	local un=cmd(p,"workerUnfuel","1")
	ok(has(un.message,"not returned"),"timed fuel is consumed")
	eq(un.items.CharredBriquette,195,"burnt fuel not refunded")
	eq(un.workers[1].fuel,nil,"fuel removed")
	ok(has(cmd(p,"workerUnfuel","1").message,"no fuel"),"unfuel empty")
	local perm=cmd(p,"workerFuel","1:EverflameHeart")
	eq(perm.items.EverflameHeart,1,"permanent fuel placed")
	ok(perm.workers[1].fuel.permanent,"permanent flag")
	eq(perm.workers[1].speed,110,"permanent +10%")
	ok(has(cmd(p,"workerFuel","1:EverflameHeart").message,"already holds"),"permanent fuel cannot stack")
	ok(has(cmd(p,"workerFuel","1:EverflameHeart:2").message,"between 1 and"),"permanent batch refused")
	ok(has(cmd(p,"workerFuel","1:CharredBriquette").message,"is burning"),"timed fuel cannot join a permanent")
	p=rejoin(p)
	ok(st(p).workers[1].fuel.permanent,"permanent fuel persists")
	un=cmd(p,"workerUnfuel","1")
	eq(un.items.EverflameHeart,2,"permanent fuel returned")
	-- Timed fuel persists and burns out offline.
	cmd(p,"workerFuel","1:StormcellCanister")
	p=rejoin(p)
	eq(st(p).workers[1].fuel.id,"StormcellCanister","timed fuel persists")
	p=away(p,43200)
	eq(st(p).workers[1].fuel,nil,"timed fuel burns out")
	-- Abusive saves: a far-future fuel is dropped on load.
	p=rejoin(p,function(pr) pr.workers[1].fuel={id="SunforgeCatalyst",expires=utc+86400*999} end)
	eq(st(p).workers[1].fuel,nil,"impossible fuel expiry discarded")
	p=rejoin(p,function(pr) pr.workers[1].fuel={id="Timber",expires=utc+60} end)
	eq(st(p).workers[1].fuel,nil,"unknown fuel discarded")
end

------------------------------------------------------------------------------
-- 5. Upgrades, chests, pressing, auto-sell end to end.
------------------------------------------------------------------------------
do
	local p=seeded(9003,function(pr)
		items(pr,{WorkerBundler=1,WorkerAetherPress=1,WorkerCoinchute=1,WorkerStoreAnnex=1,WorkerGleamSprinkler=1,WorkerCoffer=1,WorkerBrassChest=1})
		pr.worker=true
		pr.workers={{resource="Ore",tier=2,lastClaim=utc},{resource="Timber",tier=1,lastClaim=utc}}
	end)
	ok(has(cmd(p,"workerInstall","1:Timber").message,"Choose a worker upgrade"),"non-part refused")
	ok(has(cmd(p,"workerInstall","3:WorkerBundler").message,"Build this worker first"),"install needs a worker")
	local i=cmd(p,"workerInstall","1:WorkerBundler")
	eq(i.workers[1].upgrades[1],"WorkerBundler","bundler installed")
	eq(i.items.WorkerBundler,0,"bundler consumed")
	eq(i.workers[1].press,1,"press 1 active")
	ok(has(cmd(p,"workerInstall","1:WorkerAetherPress").message,"one of each kind"),"two presses refused")
	ok(has(cmd(p,"workerInstall","1:WorkerBundler").message,"You need"),"part must be held")
	i=cmd(p,"workerInstall","1:WorkerStoreAnnex")
	eq(i.workers[1].upgrades[2],"WorkerStoreAnnex","annex in slot 2")
	eq(i.workers[1].capacity,360,"tier 2 + annex storage")
	ok(has(cmd(p,"workerInstall","1:WorkerCoinchute").message,"no free upgrade slot"),"two upgrade slots only")
	eq(st(p).items.WorkerCoinchute,1,"refused install is free")
	i=cmd(p,"workerInstall","1:WorkerCoffer")
	eq(i.workers[1].chest,"WorkerCoffer","coffer installed")
	eq(i.workers[1].capacity,480,"coffer storage")
	i=cmd(p,"workerInstall","1:WorkerBrassChest")
	eq(i.workers[1].chest,"WorkerBrassChest","chest swapped")
	eq(i.items.WorkerCoffer,1,"old chest returned")
	eq(i.workers[1].capacity,720,"brass chest storage")
	ok(has(cmd(p,"workerInstall","1:WorkerCoffer").message,"Installed"),"swap back")
	cmd(p,"workerInstall","1:WorkerBrassChest")
	ok(has(cmd(p,"workerInstall","1:WorkerBrassChest").message,"You need"),"installed chest is no longer held")
	p=rejoin(p,function(pr) pr.items.WorkerBrassChest=1 end)
	ok(has(cmd(p,"workerInstall","1:WorkerBrassChest").message,"already has"),"same chest refused")
	eq(st(p).items.WorkerBrassChest,1,"refused chest kept")
	-- Remove and reinstall.
	local r=cmd(p,"workerRemove","1:2")
	eq(r.items.WorkerStoreAnnex,1,"annex returned")
	eq(r.workers[1].upgrades[2],false,"slot 2 empty")
	ok(has(cmd(p,"workerRemove","1:2").message,"Nothing installed"),"remove empty slot")
	ok(has(cmd(p,"workerRemove","1:3").message,"Choose upgrade slot"),"slot 3 does not exist")
	ok(has(cmd(p,"workerRemove","4:1").message,"Build this worker first"),"remove needs a worker")
	cmd(p,"workerInstall","1:WorkerStoreAnnex")
	-- Pressing end to end: tier 2 (90 s) for 400 cycles -> 2 condensed + 80 ore.
	local ore=st(p).items.Ore or 0
	local coll=st(p).collection.Ore or 0
	p=rejoin(p,function(pr) pr.workers[1].lastClaim=utc-90*400; pr.workers[1].carry=0 end)
	local s=st(p)
	eq(s.workers[1].store.CondensedOre,2,"condensed in storage")
	eq(s.workers[1].store.Ore,80,"raw remainder in storage")
	eq(s.workers[1].ready,82,"storage counts condensed as one")
	local c=cmd(p,"workerClaim","1")
	eq(c.items.CondensedOre,2,"condensed claimed")
	eq(c.items.Ore,ore+80,"raw claimed")
	eq(c.collection.Ore,coll+400,"condensed output counts toward the raw collection")
	eq(c.workers[1].ready,0,"claimed")
	eq(cmd(p,"workerClaim","1").items.CondensedOre,2,"condensed claim once")
	-- Auto-seller on worker 2 (tier 1, 120 storage, timber value 3).
	cmd(p,"workerInstall","2:WorkerCoinchute")
	local coins=st(p).coins
	p=rejoin(p,function(pr) pr.workers[2].lastClaim=utc-120*600; pr.workers[2].carry=0 end)
	s=st(p)
	eq(s.workers[2].coins,4*120*3//2,"four full stores sold at 50%")
	eq(s.workers[2].ready,120,"fifth store kept")
	ok(s.workers[2].autoSell,"auto-sell flag")
	c=cmd(p,"workerClaim","2")
	ok(c.coins>=coins+720,"auto-sold coins paid on claim")
	ok(has(c.message,"auto-sold coins"),"claim message mentions coins")
	eq(cmd(p,"workerClaim","2").workers[2].coins,0,"coins claim once")
	-- 30 days offline with a seller: capped at 48 h of work.
	p=rejoin(p,function(pr) pr.workers[2].lastClaim=utc-86400*30; pr.workers[2].carry=0 end)
	s=st(p)
	local fills=(W.MAX_ACCRUAL//120)//120
	eq(s.workers[2].coins,(fills-1)*120*3//2,"offline seller capped by MAX_ACCRUAL")
	-- Sprinkler.
	cmd(p,"workerRemove","2:1")
	cmd(p,"workerInstall","2:WorkerGleamSprinkler")
	cmd(p,"workerClaim","2")
	p=rejoin(p,function(pr) pr.workers[2].lastClaim=utc-120*50; pr.workers[2].carry=0; pr.workers[2].bonusCarry=0 end)
	s=st(p)
	eq(s.workers[2].store.ArcaneDust,5,"sprinkler bonus dust")
	local dust=s.items.ArcaneDust or 0
	eq(cmd(p,"workerClaim","2").items.ArcaneDust,dust+5,"bonus dust claimed")
	-- Persisted parts survive rejoin.
	p=rejoin(p)
	s=st(p)
	eq(s.workers[1].upgrades[1],"WorkerBundler","upgrade persisted")
	eq(s.workers[1].chest,"WorkerBrassChest","chest persisted")
	eq(s.workers[2].upgrades[1],"WorkerGleamSprinkler","sprinkler persisted")
	eq(data.p9003.profile.workersClean,nil,"session marker never saved")
	-- Changing type keeps parts; pressing follows the new output.
	p=rejoin(p,function(pr) pr.collection.Timber=500; pr.xp.Woodcutting=0 end)
	eq(cmd(p,"workerAssign","1:Timber").workers[1].upgrades[1],"WorkerBundler","parts stay on type change")
end

------------------------------------------------------------------------------
-- 6. Combat workers and collection/level gates.
------------------------------------------------------------------------------
do
	local X=Data.XP_TABLE
	local p=seeded(9004,function(pr)
		items(pr,{Timber=100,Ore=100,Shard=200})
		pr.worker=true
		pr.workers={{resource="Ore",tier=1,lastClaim=utc}}
		pr.xp.Combat=X[10]
	end)
	ok(has(cmd(p,"workerAssign","1:ShardlingSentry").message,"collection tier 3"),"combat worker needs the drop collection tier 3")
	p=rejoin(p,function(pr) pr.collection.Shard=24 end)
	ok(has(cmd(p,"workerAssign","1:ShardlingSentry").message,"collection tier 3"),"24 shard collection is tier 2")
	p=rejoin(p,function(pr) pr.collection.Shard=25 end)
	local a=cmd(p,"workerAssign","1:ShardlingSentry")
	eq(a.workers[1].resource,"ShardlingSentry","Shardling Sentry assigned")
	eq(a.workers[1].output,"Shard","produces Warden Shards")
	eq(a.workers[1].kind,"combat","combat kind")
	eq(a.workers[1].interval,600,"5x slower")
	ok(has(cmd(p,"workerAssign","1:WispglowLantern").message,"Combat 30"),"combat level gate")
	local xp=st(p).xp.Combat
	p=rejoin(p,function(pr) pr.workers[1].lastClaim=utc-600*4-10; pr.workers[1].carry=0 end)
	local c=cmd(p,"workerClaim","1")
	eq(c.items.Shard,200+4,"shards produced")
	eq(c.xp.Combat,xp+4*5,"combat XP per shard")
	eq(c.collection.Shard,25+1,"combat output credits the collection at 25%")
	-- 3 more shards: 3 carried units, then 1 more makes another collection point.
	p=rejoin(p,function(pr) pr.workers[1].lastClaim=utc-600*3-10; pr.workers[1].carry=0 end)
	c=cmd(p,"workerClaim","1")
	eq(c.items.Shard,204+3,"three more shards")
	eq(c.collection.Shard,26,"remainder carried, not credited")
	p=rejoin(p,function(pr) eq(pr.workers[1].collectCarry,3,"collection carry persisted"); pr.workers[1].lastClaim=utc-600-10; pr.workers[1].carry=0 end)
	c=cmd(p,"workerClaim","1")
	eq(c.collection.Shard,27,"carry completes a collection point")
	-- Shard blueprint path.
	ok(has(cmd(p,"workerBlueprint","ShardlingSentry:2").message,"tier 1 first"),"assigning a type is not a unique craft")
	local b=cmd(p,"workerBlueprint","ShardlingSentry:1")
	ok(has(b.message,"Crafted unique"),"combat blueprint tier 1")
	b=cmd(p,"workerBlueprint","ShardlingSentry:2")
	ok(has(b.message,"Crafted unique"),"combat blueprint tier 2")
	eq(b.items.Shard,208-32-64,"blueprints spend shards")
end

------------------------------------------------------------------------------
-- 7. Migration of legacy 3-slot / 7-tier saves and hostile saves.
------------------------------------------------------------------------------
do
	local p=seeded(9005,function(pr)
		pr.worker=true
		pr.workerResource="Fish"
		pr.workers={
			{resource="Ore",tier=7,lastClaim=utc-26*10-5},
			{resource="Timber",tier=3,lastClaim=utc-60*5-5},
			{resource="Fish",tier=1,lastClaim=utc-120*2-5},
		}
		pr.workerUniques=nil
	end)
	local s=st(p)
	eq(#s.workers,3,"three legacy workers kept")
	eq(s.workers[1].tier,7,"legacy tier 7 kept")
	eq(s.workers[1].ready,10,"legacy tier 7 accrual kept")
	eq(s.workers[2].ready,5,"legacy tier 3 accrual kept")
	eq(s.workers[3].ready,2,"legacy tier 1 accrual kept")
	eq(s.workerInfo.uniques,7+3+1,"legacy tiers seed unique crafts")
	eq(s.workerInfo.slots,4,"11 uniques open slot 4")
	eq(s.workers[1].upgrades[1],false,"legacy workers have empty upgrade slots")
	eq(s.workers[1].chest,nil,"no chest")
	p=rejoin(p)
	eq(st(p).workerInfo.uniques,11,"seeding happens once")
	-- Pre-fleet save (single p.worker).
	local legacy=seeded(9006,function(pr)
		pr.worker=true; pr.workers=nil; pr.workerUniques=nil
		pr.workerResource="Herb"; pr.lastClaim=utc-120*3-5
	end)
	s=st(legacy)
	eq(s.workers[1].resource,"Herb","pre-fleet worker migrated")
	eq(s.workers[1].ready,3,"pre-fleet accrual migrated")
	eq(s.workerInfo.uniques,1,"pre-fleet unique seeded")
	eq(s.workerReady,3,"legacy workerReady field")
	-- Hostile save: junk entries, out-of-range values, too many workers.
	local hostile=seeded(9007,function(pr)
		pr.worker=true
		local list={}
		for i=1,15 do list[i]={resource="Ore",tier=1,lastClaim=utc} end
		list[1]={resource="Bogus",tier=99,lastClaim=utc+99999,carry=-5,made=1.5,coins=-100,
			store={Ore=50,Timber=999,CondensedOre=2.5,ArcaneDust=3,Shard=-1},fuel={id="EverflameHeart",permanent=true},
			upgrades={"WorkerBundler","WorkerAetherPress","WorkerCoinchute"},chest="Timber"}
		list[2]={resource="Timber",tier=0.5,lastClaim="soon",upgrades="x",store="y"}
		pr.workers=list
		pr.workerUniques={Ore=255,Timber=-1,Bogus=3,Herb=1.5,Fish=7}
	end)
	s=st(hostile)
	eq(#s.workers,12,"fleet trimmed to 12")
	eq(s.workers[1].resource,"Ore","unknown type reset")
	eq(s.workers[1].tier,7,"tier clamped")
	eq(s.workers[1].store.Timber,nil,"foreign stored items dropped")
	eq(s.workers[1].store.CondensedOre,nil,"fractional stored items dropped")
	eq(s.workers[1].store.Ore,50,"valid stored output kept")
	eq(s.workers[1].store.ArcaneDust,3,"bonus dust kept")
	eq(s.workers[1].coins,0,"negative coins dropped")
	eq(s.workers[1].upgrades[1],"WorkerBundler","first press kept")
	eq(s.workers[1].upgrades[2],false,"duplicate press group dropped")
	eq(s.workers[1].chest,nil,"bogus chest dropped")
	ok(s.workers[1].fuel and s.workers[1].fuel.permanent,"valid permanent fuel kept")
	eq(s.workers[2].tier,1,"fractional tier floored to 1")
	eq(s.workers[2].upgrades[1],false,"bad upgrade list reset")
	eq(s.workerInfo.crafted.Ore,nil,"out-of-range mask dropped")
	eq(s.workerInfo.crafted.Fish,7,"valid mask kept")
	eq(s.workerInfo.crafted.Bogus,nil,"unknown type mask dropped")
	eq(s.workerInfo.uniques,3,"unique count from clean masks")
	eq(hostile:GetAttribute("Worker12Tier"),1,"12 workers published")
	local claimed=cmd(hostile,"workerClaim","1")
	eq(claimed.items.Ore,50,"future lastClaim cannot mint output")
	eq(cmd(hostile,"workerClaim","1").items.Ore,50,"hostile claim once")
	local holes=seeded(9008,function(pr)
		pr.worker=true
		pr.workers={{resource="Ore",tier=1,lastClaim=utc},"broken",{resource="Herb",tier=1,lastClaim=utc}}
	end)
	eq(#st(holes).workers,1,"fleet stops at the first broken record")
	-- Save size stays bounded with 12 fully kitted workers.
	local big=seeded(9009,function(pr)
		pr.worker=true
		local list={}
		for i=1,12 do
			list[i]={resource="CondensedLeviathanScale",tier=7,lastClaim=utc,carry=999999,made=999999,coins=999999999,bonusCarry=9,
				store={LeviathanScale=159,CondensedLeviathanScale=999,RadiantLeviathanScale=9,ArcaneDust=999},
				fuel={id="SunforgeCatalyst",expires=utc+86400},upgrades={"WorkerAetherPress","WorkerGleamSprinkler"},chest="WorkerVaultChest"}
			list[i].resource="LeviathanScale"
		end
		pr.workers=list
		local u={}
		for _,t in ipairs(W.Types) do u[t.id]=127 end
		pr.workerUniques=u
	end)
	eq(st(big).workerInfo.slots,12,"all uniques open 12 slots")
	eq(st(big).workerInfo.uniques,#W.Types*7,"every unique counted")
	services.Players.PlayerRemoving:Fire(big)
	local serde=require("@lune/serde")
	local bytes=#serde.encode("json",{workers=data.p9009.profile.workers,workerUniques=data.p9009.profile.workerUniques})
	ok(bytes<8192,"12 kitted workers + every unique < 8 KB ("..bytes..")")
	print("Worker save worst case: "..bytes.." JSON bytes.")
end

------------------------------------------------------------------------------
-- 8. Abuse: rapid claims, spoofed payloads, verbs before building.
------------------------------------------------------------------------------
do
	local p=player(9010)
	for _,verb in ipairs({"workerClaim","workerUpgrade","workerFuel","workerUnfuel","workerInstall","workerRemove","workerAssign"}) do
		ok(has(cmd(p,verb,"1:Ore").message,"") ,verb.." before building answers")
		eq(#st(p).workers,0,verb.." cannot conjure a worker")
	end
	for _,payload in ipairs({{},"1:Ore:Ore",string.rep("1",65),"1;Ore","1 :Ore"}) do
		local ok2,err=pcall(cmd,p,"workerAssign",payload)
		ok(ok2,"odd payload handled: "..tostring(err))
	end
	p=seeded(9011,function(pr)
		pr.worker=true
		pr.workers={{resource="Ore",tier=1,lastClaim=utc-120*10-5}}
		pr.items={CharredBriquette=10}
	end)
	local first=cmd(p,"workerClaim","1")
	eq(first.items.Ore,10,"first claim pays")
	for _=1,5 do eq(cmd(p,"workerClaim","1").items.Ore,10,"rapid re-claims pay nothing") end
	eq(cmd(p,"workerClaimAll").items.Ore,10,"claim all after claim pays nothing")
	-- Rejoin replay: the claim was saved; the old store cannot be re-read.
	p=rejoin(p)
	eq(st(p).items.Ore,10,"claim persisted once")
	eq(st(p).workers[1].ready,0,"no output reappears after rejoin")
	-- Upgrade claims first at the old tier (no retroactive speed-up).
	p=rejoin(p,function(pr) pr.items.Timber=100; pr.items.Ore=100; pr.workers[1].lastClaim=utc-120*3-5 end)
	local up=cmd(p,"workerUpgrade","1")
	eq(up.items.Ore,100-6+3,"upgrade claimed old-tier output")
	eq(up.workers[1].ready,0,"upgrade restarts the cycle")
	eq(up.workers[1].interval,90,"tier 2 pace")
end

------------------------------------------------------------------------------
-- 9. Crafting condensed forms and worker parts through the craft verb.
------------------------------------------------------------------------------
do
	local p=seeded(9012,function(pr)
		pr.items={Ore=400,Timber=200,AlloyIngot=20}
		pr.collection={Ore=50}
	end)
	ok(has(cmd(p,"craft","CondensedOre").message,"collection tier 2"),"condensed recipe gated by collection")
	p=rejoin(p,function(pr) pr.collection.Ore=100 end)
	local c=cmd(p,"craft","CondensedOre")
	eq(c.items.CondensedOre,1,"crafted a condensed form")
	eq(c.items.Ore,240,"160 ore consumed")
	c=cmd(p,"craft","CharredBriquette")
	eq(c.items.CharredBriquette,2,"briquettes craft in pairs")
	c=cmd(p,"craft","WorkerBundler")
	ok(has(c.message,"Carpentry 10") or (c.items.WorkerBundler or 0)==0,"bundler needs Carpentry 10")
end

------------------------------------------------------------------------------
-- 10. Passive vs active balance (pure data model).
-- Active gathering uses the verify-skills.luau Hunter/mastery model: one
-- harvest per node respawn at best (a gather is a 1 s hold + 0.65 s prompt
-- cooldown). Active combat: one kill per monster respawn (combat.server
-- L.respawnDelay = 8 + 0.15 x level s), the Warden one per 8 s reform + one
-- swing; drop/h = kills/h x chance x mean amount, best source.
-- Max fleet: 12 workers at tier 7, best fuel, max haste, best legal
-- composition (<= MAX_PER_TYPE per type, <= MAX_COMBAT combat workers).
------------------------------------------------------------------------------
do
	local ACTION,GATHER=0.36+0.65,1+0.65
	local HASTE=Data.MAX_WORKER_HASTE
	local TOP=#Data.WorkerTiers
	local bestFuel=0
	for _,id in ipairs(W.FuelOrder) do bestFuel=math.max(bestFuel,W.Fuels[id].speed) end
	eq(bestFuel,W.Fuels.SunforgeCatalyst.speed,"Sunforge is the best fuel")
	ok(W.Fuels.EverflameHeart.speed<=bestFuel,"permanent fuel never beats the best timed fuel")
	local function perWorker(typeId) return 3600*(100+bestFuel)/100/W.interval(typeId,TOP,HASTE) end
	-- The model matches W.settle: a 48 h settle of a maxed worker (Sunforge, Coinchute, Vault).
	for _,id in ipairs({"Ore","Crownstone","ShardlingSentry"}) do
		local w={resource=id,tier=TOP,lastClaim=0,fuel={id="SunforgeCatalyst",expires=W.MAX_ACCRUAL},upgrades={"WorkerCoinchute",false},chest="WorkerVaultChest"}
		local made=W.settle(w,W.MAX_ACCRUAL,HASTE)
		local model=perWorker(id)*W.MAX_ACCRUAL/3600
		ok(math.abs(made-model)<=1,id.." 48 h settle "..made.." matches the rate model "..string.format("%.1f",model))
	end
	local rows={}
	for _,skill in ipairs({"Mining","Woodcutting","Fishing","Farming"}) do
		local activeXp,activeItems=0,{}
		for _,r in ipairs(Data.ResourceTiers[skill]) do
			activeXp=math.max(activeXp,3600*r.xp/math.max(r.respawn,GATHER))
			activeItems[r.id]=3600/math.max(r.respawn,GATHER)
		end
		-- Best legal XP composition: the highest-XP types, MAX_PER_TYPE each, 12 workers.
		local types={}
		for _,t in ipairs(W.Types) do if t.kind=="gather" and t.skill==skill then table.insert(types,t) end end
		table.sort(types,function(a,b) return perWorker(a.id)*a.xp>perWorker(b.id)*b.xp end)
		local fleetXp,left=0,W.MAX_SLOTS
		for _,t in ipairs(types) do
			local n=math.min(W.MAX_PER_TYPE,left)
			fleetXp+=n*perWorker(t.id)*t.xp
			left-=n
			if left==0 then break end
		end
		eq(left,0,skill.." has enough types for a 12-worker fleet")
		ok(fleetXp<=0.35*activeXp,string.format("%s max fleet %.0f XP/h <= 35%% of top active %.0f XP/h (%.1f%%)",skill,fleetXp,activeXp,100*fleetXp/activeXp))
		ok(fleetXp*W.MAX_ACCRUAL/3600<=24*activeXp,skill.." 48 h offline fleet XP <= 24 h of top active play")
		local worstShare,worstId=0,""
		for _,t in ipairs(types) do
			local items=W.MAX_PER_TYPE*perWorker(t.id)
			local share=items/activeItems[t.output]
			ok(share<=0.6,string.format("%s: %d maxed workers %.0f items/h <= 60%% of active %.0f/h (%.1f%%)",t.id,W.MAX_PER_TYPE,items,activeItems[t.output],100*share))
			if share>worstShare then worstShare,worstId=share,t.id end
		end
		table.insert(rows,string.format("%s fleet %.0f XP/h vs active %.0f (%.1f%%), 48 h offline %.0f XP vs 24 h active %.0f; worst items %s %.1f%%",
			skill,fleetXp,activeXp,100*fleetXp/activeXp,fleetXp*W.MAX_ACCRUAL/3600,24*activeXp,worstId,100*worstShare))
	end
	-- Worker XP per item is a tenth of a manual harvest (starters keep 3).
	for _,t in ipairs(W.Types) do
		if t.kind=="gather" and t.collectionTier>0 then
			local xp=0
			for _,x in ipairs(Data.ResourceTiers[t.skill]) do if x.id==t.output then xp=x.xp end end
			ok(t.xp<=math.max(3,xp//10),t.id.." worker XP per item <= a tenth of a harvest")
		end
	end
	-- Combat workers vs active farming of the same drop.
	local active={Shard=3600/(8+ACTION)}
	for _,m in pairs(Data.Monsters) do
		local kills=3600/(8+(m.level or 1)*0.15)
		for _,d in ipairs(m.drops or {}) do
			active[d.item]=math.max(active[d.item] or 0,kills*d.chance*(d.min+d.max)/2)
		end
	end
	local combatTypes=0
	for _,t in ipairs(W.Types) do
		if t.kind=="combat" then
			combatTypes+=1
			local bonus=if t.output=="ArcaneDust" then 1+1/W.Upgrades.WorkerGleamSprinkler.bonus.every else 1
			local items=W.MAX_COMBAT*perWorker(t.id)*bonus
			ok(active[t.output]~=nil,t.output.." has an active source")
			local share=items/active[t.output]
			ok(share<=0.3,string.format("%s: %d maxed combat workers %.0f/h <= 30%% of active %.0f/h (%.1f%%)",t.id,W.MAX_COMBAT,items,active[t.output],100*share))
			local scale=Data.CollectionScale[t.output] or 1
			local top=Data.CollectionTiers[#Data.CollectionTiers]*scale
			local hours=top/(items/W.COMBAT_COLLECTION_DIV)
			ok(hours>=24,string.format("%s top %s collection from workers alone takes %.0f h",t.id,t.output,hours))
			table.insert(rows,string.format("%s %.0f/h vs active %.0f (%.1f%%), top collection %.0f h",t.id,items,active[t.output],100*share,hours))
		end
	end
	ok(combatTypes>=5,"combat types modelled")
	-- Slot pace: builds and tier 1-3 upgrades alone (no blueprints, no
	-- Condensed) give at most 3 uniques per built worker.
	local slots=W.BASE_SLOTS
	for _=1,20 do
		local nextSlots=W.slotsFor(3*slots)
		if nextSlots==slots then break end
		slots=nextSlots
	end
	ok(slots<9,"cheap builds and tier 1-3 upgrades stop at slot "..slots.." (< 9)")
	ok(W.SlotUniques[9-W.BASE_SLOTS]>3*8,"slot 9 needs more than cheap crafts on 8 workers")
	-- No merchant mints: worker parts, fuels, chests and pressed forms are worth at most their inputs.
	for id,rec in pairs(Data.Recipes) do
		if W.Fuels[id] or W.Upgrades[id] or W.Chests[id] or W.PressSource[id] then
			local input=0
			for cost,n in pairs(rec.costs) do input+=(Data.Items[cost] and Data.Items[cost].value or 0)*n end
			ok(Data.Items[id].value*(rec.amount or 1)<=input,string.format("%s value %d x%d <= inputs %d",id,Data.Items[id].value,rec.amount or 1,input))
		end
	end
	print("Passive vs active: "..table.concat(rows,"; "))
end

------------------------------------------------------------------------------
-- 11. Fleet caps, region gates, idling legacy workers, tier 4 Condensed.
------------------------------------------------------------------------------
do
	local X=Data.XP_TABLE
	local p=seeded(9013,function(pr)
		items(pr,{Timber=1000,Ore=1000})
		pr.worker=true
		pr.workers={{resource="Ore",tier=1,lastClaim=utc},{resource="Ore",tier=1,lastClaim=utc},{resource="Ore",tier=1,lastClaim=utc}}
		pr.workerUniques={Ore=127,Timber=127,Fish=127}
		pr.xp.Mining=X[99]
		pr.collection.Crownstone=1000
		pr.collection.Celestium=999
	end)
	eq(st(p).workerInfo.slots,6,"21 uniques open six slots")
	local b=cmd(p,"workerBuild","4:Ore")
	eq(#b.workers,3,"fourth Copperstone worker refused")
	ok(has(b.message,"At most 3"),"type cap explained")
	eq(cmd(p,"workerBuild","4:Timber").workers[4].resource,"Timber","another type builds")
	ok(has(cmd(p,"workerAssign","4:Ore").message,"At most 3"),"assign respects the type cap")
	local crown=cmd(p,"workerAssign","4:Crownstone")
	eq(crown.workers[4].resource,"Timber","Crownstone needs its region")
	ok(has(crown.message,"Shattered Crown"),"region gate explained")
	ok(has(cmd(p,"workerBlueprint","Crownstone:1").message,"Shattered Crown"),"blueprints follow the region gate")
	p=rejoin(p,function(pr) pr.xp.Combat=X[60]; pr.questsDone={CrownOfTempest=true} end)
	eq(cmd(p,"workerAssign","4:Crownstone").workers[4].resource,"Crownstone","region unlocked: Crownstone worker")
	ok(has(cmd(p,"workerAssign","1:Celestium").message,"collection tier 5"),"Celestium worker needs collection tier 5")
	-- Crownstone pace and XP: one per 1200 s at tier 1, 42 Mining XP each.
	p=rejoin(p,function(pr) pr.workers[4].lastClaim=utc-1200*2-5; pr.workers[4].carry=0 end)
	local mxp=st(p).xp.Mining
	local c=cmd(p,"workerClaim","4")
	eq(c.items.Crownstone,2,"Crownstone worker pace")
	eq(c.xp.Mining,mxp+2*42,"a tenth of a harvest's XP per item")
	-- Combat cap: two combat workers at most.
	p=rejoin(p,function(pr) pr.collection.Shard=25; pr.collection.BeastHide=125; pr.collection.StormFeather=75 end)
	eq(cmd(p,"workerBuild","5:ShardlingSentry").workers[5].resource,"ShardlingSentry","first combat worker")
	eq(cmd(p,"workerBuild","6:HidetanSnare").workers[6].resource,"HidetanSnare","second combat worker")
	local g=cmd(p,"workerAssign","4:GalecatchPerch")
	eq(g.workers[4].resource,"Crownstone","third combat worker refused")
	ok(has(g.message,"At most 2 combat"),"combat cap explained")
	eq(cmd(p,"workerAssign","6:GalecatchPerch").workers[6].resource,"GalecatchPerch","a combat worker may switch combat type")
	-- Tier 4+ upgrades spend the type's Condensed output.
	p=rejoin(p,function(pr) pr.items.AlloyIngot=50; pr.items.AetherIngot=50; pr.workers[1].tier=3 end)
	local u=cmd(p,"workerUpgrade","1")
	eq(u.workers[1].tier,3,"tier 4 needs Condensed Copperstone")
	ok(has(u.message,"Condensed Copperstone Ore"),"upgrade cost names the Condensed form")
	p=rejoin(p,function(pr) pr.items.CondensedOre=1 end)
	u=cmd(p,"workerUpgrade","1")
	eq(u.workers[1].tier,4,"tier 4 with Condensed output")
	eq(u.items.CondensedOre or 0,0,"Condensed output spent")
	eq(u.workers[1].upgradeCost.CondensedOre,2,"tier 5 asks for 2 Condensed")
	-- Legacy fleets over the caps (or past new gates) idle instead of producing.
	local legacy=seeded(9014,function(pr)
		pr.worker=true
		pr.workers={
			{resource="Ore",tier=1,lastClaim=utc-1205},{resource="Ore",tier=1,lastClaim=utc-1205},{resource="Ore",tier=1,lastClaim=utc-1205},
			{resource="Ore",tier=1,lastClaim=utc-1205,store={Ore=5}},
			{resource="Celestium",tier=7,lastClaim=utc-1205,store={Celestium=7}},
		}
		pr.workerUniques={Ore=1}
	end)
	local s=st(legacy)
	eq(s.workers[3].ready,10,"third Copperstone worker produces")
	eq(s.workers[3].idle,nil,"within the cap: not idle")
	ok(has(s.workers[4].idle,"At most 3"),"fourth Copperstone worker idles")
	eq(s.workers[4].ready,5,"idle worker keeps its stored output")
	ok(has(s.workers[5].idle,"Mining 85"),"no-longer-allowed worker idles")
	eq(s.workers[5].ready,7,"idle Celestium worker keeps its store")
	legacy=away(legacy,1200)
	s=st(legacy)
	eq(s.workers[4].ready,5,"idle worker produced nothing offline")
	eq(s.workers[1].ready,20,"working worker produced offline")
	local claim=cmd(legacy,"workerClaim","4")
	eq(claim.items.Ore,5,"idle worker's store is claimable")
	eq(cmd(legacy,"workerAssign","4:Timber").workers[4].idle,nil,"reassigning an idle worker resumes work")
	eq(cmd(legacy,"workerClaim","5").items.Celestium,7,"idle Celestium store claimed once")
end

print("PASS: "..checks.." worker depth assertions.")
print("SUITE-END verify-workers.luau")
