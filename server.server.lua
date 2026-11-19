-- Islebound authoritative progression. Only registered world prompts award resources.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local prompts = game:GetService("ProximityPromptService")
-- Shared Depth rules (docs/DEPTH-CONTRACT.md). Pure data + pure functions.
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local Progression = require(ReplicatedStorage:WaitForChild("AetherProgression"))
Progression.useData(Data)
local action = Instance.new("RemoteFunction")
action.Name = "IsleAction"
local update = Instance.new("RemoteEvent")
update.Name = "IsleUpdate"
update.Parent = ReplicatedStorage

local exchangeAction, resumeExchange
local marketViews,marketReads={},{}
-- Economy (Bazaar orders + Auction House); defined with the market at the end of this file.
local Econ={views={},reads={}}
local profiles, cooldown, lastRead, saving, preview, leaseEnd = {}, {}, {}, {}, {}, {}
local stateRead, exchangeReady, sessionOwner, opening = {}, {}, {}, {}
-- Unfinished sessions per UserId on this server (opening, live or closing).
local userSessions = {}
local enemies = setmetatable({}, {__mode = "k"})
-- Per-player resource node depletion: [prompt] = {[player] = os.clock() ready time}.
local nodeRegrowth = setmetatable({}, {__mode = "k"})
local uid = HttpService:GenerateGUID(false)
local sessionSeq = 0
local STATE_INTERVAL, EXCHANGE_COOLDOWN, REJOIN_WAIT = 0.5, 6, 15
local store
pcall(function()
	store = DataStoreService:GetDataStore("Islebound_RPG_v1")
end)
-- One seeded generator for every server roll (fortune, crits, drops).
local rng = Random.new(os.time())
local function roll() return rng:NextNumber() end
local prices = {Timber=3, Ore=4, Herb=2, Fish=5}
local recipes = {Pickaxe={Ore=3,Timber=2}, Blade={Ore=4,Timber=3}, Tonic={Herb=2},Stormblade={Stormglass=1,Shard=3,Ore=6}}
local recipeGates={Pickaxe={Ore=3},Blade={Ore=6},Tonic={Herb=2},Stormblade={Ore=30}}
recipes.AlloyIngot={Ore=2,Timber=1}
recipes.AetherIngot={Aetherite=2,AlloyIngot=1}
recipes.ReinforcedPickaxe={AetherIngot=3,Timber=5,Pickaxe=1}
recipes.Skyplate={AetherIngot=4,Herb=4}
recipes.ExpeditionRation={Fish=2,Herb=1}
recipeGates.ExpeditionRation={Fish=5}
recipeGates.AlloyIngot={}
recipeGates.AetherIngot={}
recipeGates.ReinforcedPickaxe={Aetherite=6}
recipeGates.Skyplate={Aetherite=8}
local recipeLevels={AetherIngot=3,ReinforcedPickaxe=3,Skyplate=3}
local repeatableRecipes={Tonic=true,ExpeditionRation=true,AlloyIngot=true,AetherIngot=true}
local consumables={Tonic={healing=40,recovery=0,action="Drink"},ExpeditionRation={healing=65,recovery=12,action="Eat"}}
local recipeDescriptions={Pickaxe="+1 Ore per harvest",Blade="+8 Warden strike damage",Tonic="Restore up to 40 health",
	Stormblade="+12 Warden strike damage",AlloyIngot="Repeatable refining trains Smithing; used in Aether Ingots",
	AetherIngot="Refined material for reinforced equipment",ReinforcedPickaxe="Replaces Pickaxe: +2 Ore and +1 Aetherite per harvest",
	Skyplate="Automatically equipped: +2 defense",ExpeditionRation="Restore up to 65 health; wait 12 seconds between rations"}
local decorations={Lanterns={Timber=5},Garden={Herb=3,Timber=3},Deck={Timber=10,Ore=5}}
-- Depth constants.
local gearSlots={weapon=true,helmet=true,chest=true,legs=true,boots=true}
local collectionSet={}
for _,id in ipairs(Data.CollectionItems) do collectionSet[id]=true end
local MAX_PETS=64
local function validId(value) return type(value)=="string" and #value>0 and #value<=64 end
local function deepCopy(value)
	if type(value)~="table" then return value end
	local out={}
	for k,v in pairs(value) do out[k]=deepCopy(v) end
	return out
end
local function fresh()
	local xp={}
	for _,skill in ipairs(Data.SkillOrder) do xp[skill]=0 end
	local slayerXp={}
	for _,line in ipairs(Data.SlayerOrder) do slayerXp[line]=0 end
	return {version=2, xp=xp,items={},collection={},decorations={},coins=0,bank=0,worker=false,ironman=false,started=false,lastClaim=0,kills=0,
		equipment={},enchants={},accessoryBag={},pets={},buffs={},bestiary={},slayerXp=slayerXp,levelRewards={},collectionRewards={}}
end
local function level(xp)
	return Progression.levelForXp(xp or 0)
end
-- Player-facing notices raised by shared helpers (level-ups, collection tiers);
-- appended to the next snapshot message for that profile.
local notes=setmetatable({},{__mode="k"})
local function note(p,text)
	local list=notes[p] or {}
	notes[p]=list
	table.insert(list,text)
end
-- Every XP grant: OSRS curve with cap, active pet share, one-time level coins.
local function grantXp(p,skill,amount)
	if not Data.Skills[skill] or type(amount)~="number" or amount<=0 then return end
	local _,newLevel=Progression.addXp(p,skill,amount)
	local pet,petDef=Progression.activePet(p)
	local petLevel=pet and pet.level
	Progression.addPetXp(p,skill,amount)
	if pet and pet.level>petLevel then note(p,petDef.name.." pet level "..pet.level.."!") end
	p.levelRewards=p.levelRewards or {}
	local rewarded=p.levelRewards[skill] or 1
	if newLevel>rewarded then
		local coins=0
		for lvl=rewarded+1,newLevel do coins+=Data.levelCoinReward(lvl) end
		p.levelRewards[skill]=newLevel
		p.coins+=coins
		note(p,skill.." level "..newLevel.."! +"..coins.." coins")
	end
end
local function collect(p,item,count)
	p.items[item]=(p.items[item] or 0)+count
	p.collection[item]=(p.collection[item] or 0)+count
	if not collectionSet[item] then return end
	p.collectionRewards=p.collectionRewards or {}
	local tier=Progression.collectionTier(p,item)
	local claimed=p.collectionRewards[item] or 0
	if tier>claimed then
		local coins=0
		for t=claimed+1,tier do coins+=Data.collectionTierReward(t).coins end
		p.collectionRewards[item]=tier
		p.coins+=coins
		note(p,Data.Items[item].name.." collection tier "..tier.."! +"..coins.." coins")
	end
end
local function spend(p,cost)
	for item,n in pairs(cost) do
		if (p.items[item] or 0)<n then return false end
	end
	for item,n in pairs(cost) do p.items[item]-=n end
	return true
end
-- Workers follow Data.WorkerTiers (SkyBlock minion tiers 1-7).
local function workerFleet(p)
	if not p.workers then
		p.workers={}
		if p.worker then p.workers[1]={resource=p.workerResource or "Ore",tier=1,lastClaim=p.lastClaim} end
	end
	return p.workers
end
local function workerConfig(w)
	return Data.WorkerTiers[math.clamp(math.floor(tonumber(w.tier) or 1),1,#Data.WorkerTiers)]
end
local function workerReady(w)
	if not w then return 0 end
	local config=workerConfig(w)
	return math.clamp(math.floor((os.time()-w.lastClaim)/config.interval),0,config.capacity)
end
local function workerCost(tier)
	local cost={Timber=5*tier,Ore=3*tier}
	if tier>=4 then cost.AlloyIngot=4*(tier-3); cost.AetherIngot=2*(tier-3) end
	return cost
end
local function workerXp(resource)
	local r=Progression.resource(resource)
	if not r then return nil,0 end
	return r.skill,if r.index==1 then 3 else math.max(3,r.xp//4)
end
local function workerAllowed(p,resource)
	local r=type(resource)=="string" and Progression.resource(resource)
	if not r then return false,"Choose a gathering resource such as Ore, Timber, Herb or Fish." end
	if r.index==1 then return true end
	if level(p.xp[r.skill])<r.level then return false,r.name.." workers require "..r.skill.." "..r.level.."." end
	if Progression.collectionTier(p,resource)<1 then
		return false,"Reach "..r.name.." collection tier 1 ("..Progression.collectionThreshold(resource,1).." lifetime) to assign workers."
	end
	return true
end
local function ready(p) return workerReady(workerFleet(p)[1]) end
local function workerState(p)
	local result={}
	for slot,w in ipairs(workerFleet(p)) do
		local config=workerConfig(w)
		result[slot]={slot=slot,resource=w.resource,tier=w.tier,ready=workerReady(w),interval=config.interval,capacity=config.capacity,maxTier=#Data.WorkerTiers}
	end
	return result
end
local function recipeState(p)
	local result={}
	for _,item in ipairs({"Pickaxe","Blade","Tonic","AlloyIngot","AetherIngot","ReinforcedPickaxe","Skyplate","Stormblade","ExpeditionRation"}) do
		local skill=if consumables[item] then "Alchemy" else "Smithing"
		local required=recipeLevels[item] or 1
		local unlocked=level(p.xp[skill])>=required
		for material,amount in pairs(recipeGates[item]) do if (p.collection[material] or 0)<amount then unlocked=false end end
		table.insert(result,{id=item,costs=table.clone(recipes[item]),skill=skill,level=required,collection=table.clone(recipeGates[item]),
			description=recipeDescriptions[item],repeatable=repeatableRecipes[item]==true,unlocked=unlocked,xp=if item=="AlloyIngot" then 16 else 24})
	end
	return result
end
-- Regions: Data.Regions requirements (quest = completed guild contracts).
local function regionAllowed(p,region)
	local def=type(region)=="string" and Data.RegionById[region]
	if not def then return false end
	local requires=def.requires or {}
	if requires.quest and (p.questCompleted or 0)<requires.quest then return false end
	for skill,lvl in pairs(requires.skills or {}) do
		if level(p.xp[skill])<lvl then return false end
	end
	return true
end
local function regionRequirement(def)
	local parts={}
	local requires=def.requires or {}
	if requires.quest then table.insert(parts,"Complete "..requires.quest.." guild contracts") end
	local skills={}
	for skill in pairs(requires.skills or {}) do table.insert(skills,skill) end
	table.sort(skills)
	for _,skill in ipairs(skills) do table.insert(parts,skill.." "..requires.skills[skill]) end
	return table.concat(parts,", ")
end
local function regionDenied(region)
	if region=="Skyreach" then return "Claim the Skyreach charter in your journal before entering this region." end
	local def=type(region)=="string" and Data.RegionById[region]
	if not def then return "That region is not on the guild charts." end
	return def.name.." requires "..regionRequirement(def).."."
end
local function applyStats(player,p,spawned)
	local stats=Progression.computeStats(p,os.time())
	player:SetAttribute("SkyreachUnlocked",(p.questCompleted or 0)>=6)
	for _,region in ipairs(Data.Regions) do player:SetAttribute(region.id.."Unlocked",regionAllowed(p,region.id)) end
	local fleet=workerFleet(p)
	for slot=1,3 do
		local worker=fleet[slot]
		player:SetAttribute("Worker"..slot.."Tier",if worker then worker.tier else 0)
		player:SetAttribute("Worker"..slot.."Resource",if worker then worker.resource else "Ore")
	end
	local health=stats.health
	player:SetAttribute("CompanionBond",p.companionBond or 0)
	player:SetAttribute("CombatLevel",level(p.xp.Combat))
	local quest=p.slayerQuest
	player:SetAttribute("SlayerBossReady",if quest and quest.bossReady then quest.line..":"..quest.tier else "")
	local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth~=health then
		local oldMax,current=humanoid.MaxHealth,humanoid.Health
		humanoid.MaxHealth=health
		if current>0 then
			-- A fresh character receives its full sheet; later stat changes (gear,
			-- accessories, pets, buffs) keep the health fraction so toggling never heals.
			humanoid.Health=if spawned then math.min(health,current+math.max(0,health-oldMax))
				else math.clamp(current/math.max(oldMax,1)*health,0,health)
		end
	end
	local walk=Progression.walkSpeed(stats.speed)
	if humanoid and humanoid.WalkSpeed~=walk then humanoid.WalkSpeed=walk end
	-- Legacy small-number defense (0-7) used by the Warden and the Observatory.
	local armorDefense=if (p.items.Skyplate or 0)>0 then 2 else 0
	local defense=math.min(5,math.floor((level(p.xp.Mining)-1)/3))+armorDefense
	player:SetAttribute("SkillDefense",defense)
	local enchantDamage=(p.enchantRank or 0)*3
	player:SetAttribute("EnchantDamage",enchantDamage)
	return {maxHealth=health,defense=defense,armorDefense=armorDefense,enchantDamage=enchantDamage},stats
end
local quests={
	{title="First sparks",detail="Gather 3 Ore. Reward 10 coins.",ready=function(p) return (p.collection.Ore or 0)>=3 end,coins=10},
	{title="Tools of the trade",detail="Craft a Pickaxe. Reward 20 Smithing XP.",ready=function(p) return (p.items.Pickaxe or 0)>0 or (p.items.ReinforcedPickaxe or 0)>0 end,xp=20},
	{title="A helping hand",detail="Build your worker. Reward 15 coins.",ready=function(p) return p.worker end,coins=15},
	{title="Stand against the Warden",detail="Defeat a Warden. Reward 2 Tonics.",ready=function(p) return p.kills>0 end,tonics=2},
	{title="Beyond the storm",detail="Clear the Observatory expedition. Reward 30 coins.",ready=function(p) return (p.collection.Stormglass or 0)>0 end,coins=30},
	{title="Skyreach charter",detail="Reach Mining 3 and refine 3 Alloy Ingots. Claim to unlock Skyreach Heights and earn 25 coins.",ready=function(p) return level(p.xp.Mining)>=3 and (p.collection.AlloyIngot or 0)>=3 end,coins=25},
	{title="Chart the heights",detail="Take the Brassfall Quarry transit to Skyreach Heights and survey its cartographer beacon. Reward 50 Smithing XP.",ready=function(p) return p.skyreachVisited==true end,xp=50},
	{title="Armored wayfarer",detail="Craft a Reinforced Pickaxe and Skyplate. Reward 75 coins.",ready=function(p) return (p.items.ReinforcedPickaxe or 0)>0 and (p.items.Skyplate or 0)>0 end,coins=75},
}
local function regionState(p)
	return {{id="Skyreach",name="Skyreach Heights",unlocked=(p.questCompleted or 0)>=6,visited=p.skyreachVisited==true,
		requirement="Claim the Skyreach charter: Mining 3 and 3 lifetime Alloy Ingots.",benefit="Rich Aetherite seams yield one extra mineral per harvest."}}
end
local function questState(p)
	local stage=(p.questCompleted or 0)+1
	local quest=quests[stage]
	if not quest then return {title="Guild contracts complete",detail="Your next goal is the Stormblade.",ready=false,stage=#quests,total=#quests,complete=true} end
	return {title=quest.title,detail=quest.detail,ready=quest.ready(p),stage=stage,total=#quests}
end
local huntTiers={{target=2,coins=20,xp=30},{target=4,coins=45,xp=60},{target=6,coins=80,xp=100}}
local function slayerState(p)
	local tier=math.min(3,(p.huntsCompleted or 0)+1)
	local config=huntTiers[tier]
	local progress=math.min(config.target,p.huntProgress or 0)
	return {tier=tier,active=p.huntActive==true,progress=progress,target=config.target,
		ready=p.huntActive==true and progress>=config.target,completed=p.huntsCompleted or 0,coins=config.coins,xp=config.xp}
end
-- snapshot.depth, exactly as docs/DEPTH-CONTRACT.md §3.
local function depthState(p,stats)
	local now=os.time()
	local skills={}
	for _,skill in ipairs(Data.SkillOrder) do
		local xp=p.xp[skill] or 0
		local progress=Progression.progress(xp)
		skills[skill]={level=progress.level,xp=xp,floor=progress.floor,ceiling=progress.ceiling,fraction=progress.fraction,maxed=progress.maxed}
	end
	local total,average=Progression.totals(p)
	local equipment={}
	for slot,id in pairs(p.equipment) do equipment[slot]=id end
	local tools={}
	for skill in pairs(Data.ToolKind) do tools[skill]=(Progression.bestTool(p,skill)) end
	local pets={}
	for index,pet in ipairs(p.pets) do
		local def=Data.PetById[pet.id]
		local lvl=Progression.petLevel(pet)
		table.insert(pets,{id=pet.id,level=lvl,xp=pet.xp or 0,next=if def and lvl<Data.PET_MAX_LEVEL then Data.petXpToNext(lvl,def.rarity) else nil,active=p.activePet==index})
	end
	local buffs={}
	for id,buff in pairs(p.buffs) do
		if buff.expires and buff.expires>now then buffs[id]={remaining=buff.expires-now,stats=buff.stats} end
	end
	local collections={}
	for _,id in ipairs(Data.CollectionItems) do
		local tier=Progression.collectionTier(p,id)
		collections[id]={count=p.collection[id] or 0,tier=tier,nextAt=Progression.collectionThreshold(id,tier+1)}
	end
	local lines={}
	for _,line in ipairs(Data.SlayerOrder) do
		local xp=p.slayerXp[line] or 0
		local lvl=Progression.slayerLevel(xp)
		lines[line]={xp=xp,level=lvl,nextAt=Data.SlayerLevels[lvl+1]}
	end
	local regions={}
	for _,def in ipairs(Data.Regions) do
		table.insert(regions,{id=def.id,name=def.name,unlocked=regionAllowed(p,def.id),requirement=regionRequirement(def)})
	end
	return {skills=skills,totalLevel=total,skillAverage=average,stats=stats,equipment=equipment,tools=tools,
		accessoryBag=table.clone(p.accessoryBag),activeAccessories=Progression.activeAccessories(p),accessorySlots=Progression.accessorySlots(p),
		pets=pets,buffs=buffs,collections=collections,bestiary=p.bestiary,slayer={lines=lines,quest=p.slayerQuest},enchants=p.enchants,regions=regions}
end
local function snapshot(player,message)
	local p=profiles[player]
	if not p then return {loading=true,message="Opening your journal…"} end
	local levels={}
	local provisions={}
	for item,config in pairs(consumables) do
		provisions[item]={healing=config.healing,recovery=config.recovery,action=config.action,
			readyIn=if item=="ExpeditionRation" then math.max(0,(p.rationReadyAt or 0)-os.time()) else 0}
	end
	for skill,xp in pairs(p.xp) do levels[skill]=level(xp) end
	if notes[p] then
		local extra=table.concat(notes[p],"   ·   ")
		notes[p]=nil
		message=if message and message~="" then message.."   ·   "..extra else extra
	end
	local legacyStats,stats=applyStats(player,p)
	return {xp=p.xp,items=p.items,consumables=provisions,collection=p.collection,coins=p.coins,bank=p.bank,bankRevision=p.bankRevision or 0,worker=p.worker,
		ironman=p.ironman,levels=levels,enchantRank=p.enchantRank or 0,workerResource=p.workerResource or "Ore",workerReady=ready(p),workers=workerState(p),message=message or "",kills=p.kills,
		companionBond=p.companionBond or 0,market=marketViews[player],economy=Econ.view and Econ.view(player,p),recipes=recipeState(p),regions=regionState(p),stats=legacyStats,quest=questState(p),slayer=slayerState(p),started=p.started,decorations=p.decorations,preview=preview[player]==true,
		depth=depthState(p,stats)}
end
local function claimWorker(p,slot)
	slot=slot or 1
	local w=workerFleet(p)[slot]
	if not w then return 0,"Ore",0 end
	local count=workerReady(w)
	local resource=w.resource
	local xp=0
	if count>0 then
		local interval=workerConfig(w).interval
		w.lastClaim=os.time()-((os.time()-w.lastClaim)%interval)
		collect(p,resource,count)
		local skill,each=workerXp(resource)
		xp=count*each
		if skill then grantXp(p,skill,xp) end
	end
	if slot==1 then p.lastClaim=w.lastClaim; p.workerResource=resource end
	return count,resource,xp
end
local function persist(player,release)
	if preview[player] or not profiles[player] then return true end
	while saving[player] do task.wait(0.1) end
	local p=profiles[player]
	if not p then return true end
	saving[player]=true
	local owner=sessionOwner[player]
	workerFleet(p)
	-- Deep copy: every nested Depth table (pets, buffs, enchants...) is snapshotted.
	local payload=deepCopy(p)
	local owned=false
	local committed
	local ok=pcall(function()
		committed=store:UpdateAsync("p"..player.UserId,function(old)
			owned=old~=nil and old.owner==owner
			if not owned then return nil end
			return {owner=if release then "" else owner, expires=os.time()+180,profile=payload}
		end)
	end)
	saving[player]=nil
	owned=owned and committed~=nil and committed.owner==(if release then "" else owner)
	if ok and owned then leaseEnd[player]=committed.expires end
	if not release and ok and not owned and player.Parent then player:Kick("Your journal opened in another server. Please rejoin.") end
	return ok and owned and (release or committed.expires>os.time())
end
-- Older saves gain Depth defaults. Level and collection rewards baseline at the
-- save's current standing so migration never pays a retroactive windfall.
local function migrate(profile)
	profile.decorations=profile.decorations or {}
	profile.items=profile.items or {}
	profile.collection=profile.collection or {}
	profile.xp=profile.xp or {}
	for _,skill in ipairs(Data.SkillOrder) do
		if type(profile.xp[skill])~="number" then profile.xp[skill]=0 end
	end
	for _,key in ipairs({"equipment","enchants","accessoryBag","pets","buffs","bestiary"}) do
		if type(profile[key])~="table" then profile[key]={} end
	end
	if type(profile.slayerXp)~="table" then profile.slayerXp={} end
	for _,line in ipairs(Data.SlayerOrder) do profile.slayerXp[line]=tonumber(profile.slayerXp[line]) or 0 end
	if type(profile.levelRewards)~="table" then
		profile.levelRewards={}
		for _,skill in ipairs(Data.SkillOrder) do profile.levelRewards[skill]=level(profile.xp[skill]) end
	end
	if type(profile.collectionRewards)~="table" then
		profile.collectionRewards={}
		for _,id in ipairs(Data.CollectionItems) do
			local tier=Progression.collectionTier(profile,id)
			if tier>0 then profile.collectionRewards[id]=tier end
		end
	end
	-- Drop unknown or malformed pets, keeping the active pet pointed at the same entry.
	local pets,active={},nil
	for index,pet in ipairs(profile.pets) do
		if type(pet)=="table" and type(pet.id)=="string" and Data.PetById[pet.id] and type(pet.level)=="number" and pet.level==pet.level then
			table.insert(pets,pet)
			if profile.activePet==index then active=#pets end
		end
	end
	profile.pets=pets
	profile.activePet=active
	local quest=profile.slayerQuest
	if quest~=nil and (type(quest)~="table" or not Data.Slayers[quest.line] or not Data.Slayers[quest.line].tiers[quest.tier]) then profile.slayerQuest=nil end
	profile.version=math.max(tonumber(profile.version) or 1,2)
	workerFleet(profile)
end
-- Clears every per-player table and ends this player's session slot.
local function forget(player)
	profiles[player],cooldown[player],lastRead[player],preview[player],leaseEnd[player]=nil,nil,nil,nil,nil
	marketViews[player],marketReads[player],stateRead[player],exchangeReady[player]=nil,nil,nil,nil
	Econ.views[player],Econ.reads[player]=nil,nil
	sessionOwner[player],opening[player]=nil,nil
	local set=userSessions[player.UserId]
	if set then
		set[player]=nil
		if not next(set) then userSessions[player.UserId]=nil end
	end
end
-- Leases written by any session of this server ("<uid>" legacy or "<uid>#<n>").
local function ownedByThisServer(owner)
	return owner==uid or (type(owner)=="string" and string.sub(owner,1,#uid+1)==uid.."#")
end
local function open(player)
	-- A rejoin on this server waits until the previous session (still loading or
	-- saving) has finished, so it never loads a stale autosave.
	local deadline=os.clock()+REJOIN_WAIT
	while userSessions[player.UserId] and os.clock()<deadline do task.wait(0.1) end
	if not player.Parent then return end
	if userSessions[player.UserId] then
		player:Kick("Your journal is still saving. Please rejoin in a moment.")
		return
	end
	userSessions[player.UserId]={[player]=true}
	opening[player]=true
	sessionSeq+=1
	local owner=uid.."#"..sessionSeq
	sessionOwner[player]=owner
	local profile,conflict
	local committed
	local ok=pcall(function()
		committed=store:UpdateAsync("p"..player.UserId,function(old)
			-- Every earlier session of this server has finished (above), so its lease may be taken over.
			if old and old.owner~="" and not ownedByThisServer(old.owner) and old.expires>os.time() then
				conflict=true
				return nil
			end
			profile=old and old.profile or fresh()
			return {owner=owner,expires=os.time()+180,profile=profile}
		end)
	end)
	if ok and (not committed or committed.owner~=owner) then conflict=true end
	if conflict or (not ok and not RunService:IsStudio()) then
		forget(player)
		player:Kick("Your journal is busy. Please rejoin in a moment.")
		return
	end
	if not ok then profile=fresh(); preview[player]=true else profile=committed.profile end
	-- Never strand the session slot (and block same-server rejoins) on a bad save.
	if not pcall(migrate,profile) then
		forget(player)
		player:Kick("Your journal could not be opened. Please rejoin in a moment.")
		return
	end
	profiles[player]=profile
	for name in pairs(decorations) do player:SetAttribute("Home"..name,profile.decorations[name]==true) end
	leaseEnd[player]=if preview[player] then os.time()+180 else committed.expires
	opening[player]=nil
	-- Abandoned open (the player left while loading): release and clear everything.
	if not player.Parent then persist(player,true); forget(player); return end
	local function spawnCharacter(character)
		local humanoid=character:WaitForChild("Humanoid",10)
		if not humanoid then return end
		applyStats(player,profile,true)
		humanoid.Died:Connect(function()
			local p=profiles[player]
			if p then
				local lost=math.floor(p.coins*0.10)
				p.coins-=lost
				p.bankRevision=(p.bankRevision or 0)+1
				update:FireClient(player,snapshot(player,"You lost "..lost.." purse coins. Banked coins are safe."))
			end
		end)
	end
	if profile.pending or profile.pricedPending or profile.econPending then task.defer(function() if resumeExchange then resumeExchange(player) end end) end
	player.CharacterAdded:Connect(spawnCharacter)
	if player.Character then task.spawn(spawnCharacter,player.Character) end
	update:FireClient(player,snapshot(player,if preview[player] then "Studio practice session • saving unavailable" else "Journal opened"))
end
local function live(player)
	local p=profiles[player]
	if p and (preview[player] or os.time()<(leaseEnd[player] or 0)) then return p end
	return nil
end
-- Legacy provisions (Tonic, ExpeditionRation) keep their recovery rules.
local function provision(p,humanoid,item)
	local config=consumables[item]
	if not config then return "Choose a Tonic or ExpeditionRation." end
	if humanoid.Health>=humanoid.MaxHealth then return "Already at full health." end
	if item=="ExpeditionRation" and os.time()<(p.rationReadyAt or 0) then return "Wait "..(p.rationReadyAt-os.time()).." seconds before another ration." end
	if not spend(p,{[item]=1}) then return "Craft "..item.." in the Forge first." end
	if item=="ExpeditionRation" then p.rationReadyAt=os.time()+config.recovery end
	humanoid.Health=math.min(humanoid.MaxHealth,humanoid.Health+config.healing)
	return item.." restored up to "..config.healing.." health."
end
local function isEquipped(p,item)
	for _,id in pairs(p.equipment) do if id==item then return true end end
	return table.find(p.accessoryBag,item)~=nil
end
local function dropText(drops)
	local names={}
	for item,n in pairs(drops) do table.insert(names,"+"..n.." "..(Data.Items[item] and Data.Items[item].name or item)) end
	table.sort(names)
	return if #names>0 then " • "..table.concat(names,", ") else ""
end

local exchangeBusy={}
local function perform(player,verb,item,prompt)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return "Waiting for journal sync." end
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health<=0 then return "Return to your island first." end
	if os.clock()<(cooldown[player] or 0) then return "One moment…" end
	cooldown[player]=os.clock()+(if prompt then 0.65 else 0.24)
	local region=prompt and prompt:GetAttribute("IsleRegion")
	if region and not regionAllowed(p,region) then return regionDenied(region) end
	if Econ.verbs and Econ.verbs[verb] then
		return Econ.action(player,verb,item or "")
	elseif verb=="market" or verb=="list" or verb=="buy" or verb=="proceeds" or verb=="cancel" then
		return exchangeAction(player,verb,item or "Ore")
	elseif verb=="station" and prompt then
		local stations={Forge="Forge open • smelt ingots and forge gear.",Hearth="Hearth lit • cook meals and feasts.",
			Cauldron="Cauldron bubbling • brew potions.",Workbench="Workbench ready • craft accessories.",Slayer="The Slayer master awaits your contract."}
		return stations[item] or "Station ready."
	elseif verb=="gather" and prompt and type(item)=="string" and Data.ResourceSkill[item] then
		local resource=Progression.resource(item)
		local skill=resource.skill
		local regrowth=nodeRegrowth[prompt]
		local readyAt=regrowth and regrowth[player]
		if readyAt and os.clock()<readyAt then return "This node is regrowing ("..math.ceil(readyAt-os.clock()).."s)." end
		-- Legacy bonuses stack into the harvest base before fortune.
		local bonus=0
		if resource.index==1 and level(p.xp[skill])>=3 then bonus+=1 end
		local reinforced=(p.items.ReinforcedPickaxe or 0)>0
		if item=="Ore" then bonus+=if reinforced then 2 elseif (p.items.Pickaxe or 0)>0 then 1 else 0 end
		if item=="Aetherite" and reinforced then bonus+=1 end
		if region=="Skyreach" then bonus+=1 end
		if workspace:GetAttribute("FestivalResource")==item then bonus+=1 end
		local ok,result=Progression.harvest(p,item,Progression.computeStats(p,os.time()),roll,bonus)
		if not ok then
			if item=="Aetherite" then return result.." Train on Ore in Quarry Cay." end
			return result
		end
		collect(p,item,result.amount)
		grantXp(p,skill,result.xp)
		p.started=true
		if not regrowth then regrowth=setmetatable({},{__mode="k"}); nodeRegrowth[prompt]=regrowth end
		regrowth[player]=os.clock()+(tonumber(resource.respawn) or 3)
		return "+"..result.amount.." "..resource.name.."   ·   +"..result.xp.." "..skill.." XP"
	elseif verb=="explore" and prompt and item=="Skyreach" and region=="Skyreach" then
		if p.skyreachVisited then return "Skyreach is already charted. Gather rich Aetherite or continue your guild contracts." end
		p.skyreachVisited=true
		p.started=true
		return "Skyreach charted. Claim your survey reward in the journal."
	elseif verb=="slayerStart" then
		if p.huntActive then return "Finish your current Warden hunt first." end
		p.huntActive=true
		p.huntProgress=0
		p.started=true
		return "Warden hunt accepted. Defeat "..slayerState(p).target.." Wardens, then claim your reward."
	elseif verb=="slayerClaim" then
		local hunt=slayerState(p)
		if not hunt.ready then return "Complete your active Warden hunt first." end
		p.huntActive=false
		p.huntProgress=0
		p.huntsCompleted=(p.huntsCompleted or 0)+1
		p.coins+=hunt.coins
		grantXp(p,"Combat",hunt.xp)
		return "Hunt complete • +"..hunt.coins.." coins and +"..hunt.xp.." Combat XP."
	elseif verb=="quest" then
		local state=questState(p)
		if not state.ready then return "Complete the current guild contract first." end
		local quest=quests[state.stage]
		p.questCompleted=state.stage
		p.started=true
		p.coins+=quest.coins or 0
		grantXp(p,"Smithing",quest.xp or 0)
		if quest.tonics then collect(p,"Tonic",quest.tonics) end
		return "Contract complete • "..quest.title
	elseif verb=="decorate" and decorations[item] then
		if p.decorations[item] then return "Already built on your island." end
		if not spend(p,decorations[item]) then return "Gather the supplies shown on your island sign." end
		p.decorations[item]=true
		p.started=true
		player:SetAttribute("Home"..item,true)
		return item.." added to your home."
	elseif verb=="feed" then
		if (p.companionBond or 0)>=5 then return "Your Tidewing companion is fully bonded." end
		if not spend(p,{Fish=2}) then return "Feed your Tidewing 2 Fish to build its bond." end
		p.companionBond=(p.companionBond or 0)+1
		grantXp(p,"Taming",20)
		p.started=true
		return "Tidewing bond "..p.companionBond.."/5 • +20 Taming XP and +2 maximum health."
	elseif verb=="enchant" then
		if (p.items.Blade or 0)<1 and (p.items.Stormblade or 0)<1 then return "Craft a Blade before enchanting." end
		if (p.enchantRank or 0)>=3 then return "Your weapon enchantment is at maximum rank." end
		if not spend(p,{Shard=2,Herb=4}) then return "Each enchantment needs 2 Shard and 4 Herb." end
		p.enchantRank=(p.enchantRank or 0)+1
		grantXp(p,"Enchanting",30)
		return "Weapon enchantment rank "..p.enchantRank.." • +30 Enchanting XP."
	elseif verb=="craft" and recipes[item] then
		local skill=if consumables[item] then "Alchemy" else "Smithing"
		if level(p.xp[skill])<(recipeLevels[item] or 1) then return item.." requires "..skill.." "..recipeLevels[item]..". Refine Alloy Ingots to train Smithing." end
		for material,required in pairs(recipeGates[item]) do
			if (p.collection[material] or 0)<required then return "Recipe unlocks at "..required.." lifetime "..material.."." end
		end
		if not repeatableRecipes[item] and ((p.items[item] or 0)>0 or (item=="Pickaxe" and (p.items.ReinforcedPickaxe or 0)>0)) then return "Already equipped." end
		if not spend(p,recipes[item]) then return "Gather the ingredients in your recipe journal." end
		collect(p,item,1)
		local experience=if item=="AlloyIngot" then 16 else 24
		grantXp(p,skill,experience)
		p.started=true
		return item.." crafted   ·   +"..experience.." "..skill.." XP"
	elseif verb=="craft" and validId(item) and Data.Recipes[item] then
		local recipe=Data.Recipes[item]
		local ok,why=Progression.canCraft(p,item)
		if not ok then return why end
		if not spend(p,recipe.costs) then return "Gather the ingredients in your recipe journal." end
		collect(p,recipe.output,recipe.amount)
		grantXp(p,recipe.skill,recipe.xp)
		p.started=true
		return Data.Items[recipe.output].name.." crafted   ·   +"..recipe.xp.." "..recipe.skill.." XP"
	elseif verb=="equip" then
		local def=validId(item) and Data.Items[item]
		if not def or not gearSlots[def.slot] then return "Choose a weapon or armor piece to equip. Tools are used automatically." end
		if (p.items[item] or 0)<1 then return "You do not own "..def.name.."." end
		local allowed,missing=Progression.meetsRequirements(p,def.requires)
		if not allowed then return def.name.." requires "..missing.."." end
		if p.equipment[def.slot]==item then return def.name.." is already equipped." end
		p.equipment[def.slot]=item
		return "Equipped "..def.name.."."
	elseif verb=="unequip" then
		if type(item)~="string" or not gearSlots[item] then return "Choose weapon, helmet, chest, legs or boots." end
		local id=p.equipment[item]
		if not id then return "Nothing is equipped in that slot." end
		p.equipment[item]=nil
		return "Unequipped "..(Data.Items[id] and Data.Items[id].name or id).."."
	elseif verb=="consume" then
		local def=validId(item) and Data.Items[item]
		if not def or def.kind~="consumable" then return "Choose food, a potion or a feast." end
		if consumables[item] then return provision(p,humanoid,item) end
		if (p.items[item] or 0)<1 then return "You have no "..def.name.."." end
		if def.buff then
			spend(p,{[item]=1})
			p.buffs[item]={expires=os.time()+def.buff.duration,stats=table.clone(def.buff.stats)}
			return def.name.." active for "..(def.buff.duration//60).." minutes."
		end
		if not def.heal then return "Nothing happens." end
		if humanoid.Health>=humanoid.MaxHealth then return "Already at full health." end
		if os.time()<(p.mealReadyAt or 0) then return "Wait "..(p.mealReadyAt-os.time()).." seconds before eating again." end
		spend(p,{[item]=1})
		if def.recovery then p.mealReadyAt=os.time()+def.recovery end
		humanoid.Health=math.min(humanoid.MaxHealth,humanoid.Health+def.heal)
		return def.name.." restored up to "..def.heal.." health."
	elseif verb=="accessory" then
		local def=validId(item) and Data.Items[item]
		if not def or def.kind~="accessory" then return "Choose an accessory." end
		local index=table.find(p.accessoryBag,item)
		if index then
			table.remove(p.accessoryBag,index)
			return def.name.." removed from your accessory bag."
		end
		if (p.items[item] or 0)<1 then return "You do not own "..def.name.."." end
		local slots=Progression.accessorySlots(p)
		if #p.accessoryBag>=slots then return "Accessory bag full ("..slots.." slots). Raise Combat to unlock more." end
		table.insert(p.accessoryBag,item)
		return def.name.." added to your accessory bag."
	elseif verb=="petSummon" then
		local index=type(item)=="string" and #item<=3 and string.match(item,"^%d+$") and tonumber(item)
		if not index then return "Choose a pet to summon." end
		if index==0 then
			if not p.activePet then return "No pet is summoned." end
			p.activePet=nil
			return "Pet dismissed."
		end
		local pet=p.pets[index]
		local petDef=type(pet)=="table" and Data.PetById[pet.id]
		if not petDef then return "Choose a pet you have adopted." end
		if p.activePet==index then return "That pet is already summoned." end
		p.activePet=index
		return petDef.name.." summoned."
	elseif verb=="petAdopt" then
		local def=validId(item) and Data.Items[item]
		local petDef=def and def.kind=="pet" and Data.PetById[def.pet]
		if not petDef then return "Choose a pet item to adopt." end
		if (p.items[item] or 0)<1 then return "You do not own "..def.name.."." end
		if #p.pets>=MAX_PETS then return "Your pet menu is full." end
		spend(p,{[item]=1})
		table.insert(p.pets,{id=petDef.id,level=1,xp=0})
		grantXp(p,"Taming",25*Data.Rarity[petDef.rarity].rank)
		p.started=true
		return petDef.name.." adopted. Summon it from your pet menu."
	elseif verb=="enchantItem" then
		local target,enchantId
		if validId(item) then target,enchantId=string.match(item,"^(%w+):(%w+)$") end
		local def=target and Data.Items[target]
		local enchant=enchantId and Data.Enchants[enchantId]
		if not def or not enchant then return "Choose an item and an enchantment." end
		if (p.items[target] or 0)<1 then return "You do not own "..def.name.."." end
		if enchant.appliesTo~=def.kind then return enchant.name.." cannot be applied to "..def.name.."." end
		local current=p.enchants[target] and p.enchants[target][enchantId] or 0
		local nextLevel=current+1
		if nextLevel>enchant.maxLevel then return enchant.name.." is already at maximum level." end
		local need=Data.enchantSkillLevel(enchant,nextLevel)
		if level(p.xp.Enchanting)<need then return enchant.name.." "..nextLevel.." requires Enchanting "..need.."." end
		local cost=Data.enchantCost(nextLevel)
		local materials={}
		for material,n in pairs(cost) do if material~="coins" then materials[material]=n end end
		if p.coins<(cost.coins or 0) then return enchant.name.." "..nextLevel.." costs "..(cost.coins or 0).." coins." end
		if not spend(p,materials) then return enchant.name.." "..nextLevel.." needs "..(cost.ArcaneDust or 0).." Arcane Dust." end
		p.coins-=cost.coins or 0
		p.enchants[target]=p.enchants[target] or {}
		p.enchants[target][enchantId]=nextLevel
		local xp=Data.enchantXp(nextLevel)
		grantXp(p,"Enchanting",xp)
		p.started=true
		return def.name.." enchanted with "..enchant.name.." "..nextLevel.." • +"..xp.." Enchanting XP."
	elseif verb=="slayerBegin" then
		local lineId,raw
		if validId(item) then lineId,raw=string.match(item,"^(%a+):(%d)$") end
		local line=lineId and Data.Slayers[lineId]
		local tierIndex=raw and tonumber(raw)
		local tier=line and tierIndex and line.tiers[tierIndex]
		if not tier then return "Choose a slayer line and tier." end
		if p.slayerQuest then return "Finish or abandon your current slayer quest first." end
		local need=math.max(line.requires.Combat or 1,tier.combatLevel)
		if level(p.xp.Combat)<need then return line.name.." tier "..tierIndex.." requires Combat "..need.."." end
		if p.coins<tier.cost then return "Starting this quest costs "..tier.cost.." coins." end
		p.coins-=tier.cost
		p.slayerQuest={line=lineId,tier=tierIndex,progress=0,needed=tier.spawnXp,bossReady=false}
		p.started=true
		return "Slayer quest started: slay "..tier.spawnXp.." XP of "..line.line.." creatures to summon the "..line.name.."."
	elseif verb=="slayerAbandon" then
		if not p.slayerQuest then return "You have no slayer quest." end
		p.slayerQuest=nil
		return "Slayer quest abandoned. The fee is not refunded."
	elseif verb=="workerResource" or verb=="workerAssign" then
		local slot,resource=1,item
		if verb=="workerAssign" then
			local raw,name=string.match(item or "","^([1-3]):(%a+)$")
			slot,resource=tonumber(raw),name
		end
		local w=slot and workerFleet(p)[slot]
		if not w then return "Build this worker first." end
		local allowed,why=workerAllowed(p,resource)
		if not allowed then return why end
		if resource==w.resource then return "Worker already gathering "..resource.."." end
		local count,previous=claimWorker(p,slot)
		w.resource=resource
		w.lastClaim=os.time()
		if slot==1 then p.workerResource=resource; p.lastClaim=w.lastClaim end
		return "Worker "..slot.." gathering "..resource.." • collected "..count.." "..previous.."."
	elseif verb=="worker" or verb=="workerBuild" then
		local slot=if verb=="worker" then 1 else tonumber(item)
		local fleet=workerFleet(p)
		if not slot or slot%1~=0 or slot<1 or slot>3 then return "Choose worker slot 1, 2 or 3." end
		if fleet[slot] then return "This worker is already active." end
		if slot~=#fleet+1 then return "Build the previous worker first." end
		if not spend(p,{Timber=5*slot,Ore=3*slot}) then return "Worker needs "..(5*slot).." Timber and "..(3*slot).." Ore." end
		fleet[slot]={resource="Ore",tier=1,lastClaim=os.time()}
		p.worker=true
		p.started=true
		if slot==1 then p.lastClaim=os.time(); p.workerResource="Ore" end
		return "Worker "..slot.." built • 1 resource per 2 minutes, including offline."
	elseif verb=="workerUpgrade" then
		local slot=tonumber(item)
		local w=slot and workerFleet(p)[slot]
		if not w then return "Build this worker first." end
		if w.tier>=#Data.WorkerTiers then return "Worker is at maximum tier." end
		local tier=w.tier+1
		local cost=workerCost(tier)
		if not spend(p,cost) then
			local parts={}
			for material,n in pairs(cost) do table.insert(parts,n.." "..material) end
			table.sort(parts)
			return "Upgrade needs "..table.concat(parts,", ").."."
		end
		claimWorker(p,slot)
		w.tier=tier
		w.lastClaim=os.time()
		if slot==1 then p.lastClaim=w.lastClaim end
		return "Worker "..slot.." upgraded to tier "..tier..". Completed output collected; new cycle started."
	elseif verb=="claim" or verb=="workerClaim" then
		local slot=if verb=="claim" then 1 else tonumber(item)
		if not slot or not workerFleet(p)[slot] then return "Build this worker first." end
		local n,resource,xp=claimWorker(p,slot)
		if n<1 then return "Next resource is still being gathered." end
		local skill=workerXp(resource)
		return "Collected "..n.." worker "..resource.." • +"..xp.." "..(skill or "").." XP."
	elseif verb=="sell" then
		if item==nil or prices[item] then
			local total=0
			for raw,price in pairs(prices) do
				if not item or raw==item then total+=(p.items[raw] or 0)*price; p.items[raw]=0 end
			end
			p.coins+=total
			return "Merchant paid "..total.." coins."
		end
		local def=validId(item) and Data.Items[item]
		if not def then return "The merchant does not buy that." end
		local count=p.items[item] or 0
		if count<1 then return "You have no "..def.name.." to sell." end
		if isEquipped(p,item) then return "Unequip "..def.name.." before selling it." end
		local total=count*(def.value or 1)
		p.items[item]=0
		p.coins+=total
		return "Merchant paid "..total.." coins for "..count.." "..def.name.."."
	elseif verb=="deposit" or verb=="bank" or verb=="withdraw" then
		local source=if verb=="withdraw" then "bank" else "coins"
		local destination=if source=="bank" then "coins" else "bank"
		local mode="all"
		if item~=nil then
			if #item>32 then return "Choose all, half, or a whole coin amount up to 1000000000." end
			local revision
			mode,revision=item:match("^([%a%d]+):(%d+)$")
			if not mode or #revision>16 or tonumber(revision)~=(p.bankRevision or 0) then return "Ledger changed. Refresh and choose the amount again." end
		end
		local amount
		if mode=="all" then amount=p[source]
		elseif mode=="half" then amount=math.floor(p[source]/2)
		elseif mode:match("^[1-9]%d*$") and #mode<=10 then amount=tonumber(mode)
		end
		if not amount or (mode~="all" and mode~="half" and amount>1000000000) then return "Choose all, half, or a whole coin amount up to 1000000000." end
		if amount<1 then return "No coins to transfer with that amount." end
		if amount>p[source] then return "Not enough coins in the "..(if source=="bank" then "vault." else "purse.") end
		p[source]-=amount
		p[destination]+=amount
		p.bankRevision=(p.bankRevision or 0)+1
		return (if source=="bank" then "Withdrew " else "Deposited ")..amount.." coins."
	elseif verb=="ironman" then
		if p.started then return "Choose Ironman before starting progression, construction, hunts or trading." end
		p.ironman=true
		return "Ironman journal sealed. Your Warden hunts are solo."
	elseif verb=="heal" then
		return provision(p,humanoid,item or "Tonic")
	elseif verb=="fight" and prompt then
		p.started=true
		local now=os.clock()
		local arena=enemies[prompt] or {}
		enemies[prompt]=arena
		local key=if p.ironman then player.UserId else "party"
		local boss=arena[key]
		if not boss or now-boss.last>30 then boss={hp=50,hits={},last=now}; arena[key]=boss end
		if boss.hp<=0 then return "The Warden is reforming." end
		boss.last=now
		-- Depth damage formula, scaled to the 50-health starter Warden.
		local melee=Progression.meleeDamage(Progression.computeStats(p,os.time()),roll)
		boss.hp-=8+level(p.xp.Combat)+math.floor(melee/4)
		boss.hits[player]=true
		if boss.hp>0 then
			humanoid:TakeDamage(math.max(1,9-(player:GetAttribute("SkillDefense") or 0)))
			return "Warden • "..boss.hp.."/50 health • strike again"
		end
		for ally in pairs(boss.hits) do
			local q=profiles[ally]
			local allyHumanoid=ally.Character and ally.Character:FindFirstChildOfClass("Humanoid")
			local allyRoot=ally.Character and ally.Character:FindFirstChild("HumanoidRootPart")
			local arenaPart=prompt:FindFirstAncestorWhichIsA("BasePart")
			if q and (preview[ally] or os.time()<(leaseEnd[ally] or 0)) and allyHumanoid and allyHumanoid.Health>0
				and allyRoot and arenaPart and (allyRoot.Position-arenaPart.Position).Magnitude<=40 then
				grantXp(q,"Combat",40)
				q.coins+=15
				q.kills+=1
				if q.huntActive then q.huntProgress=math.min(slayerState(q).target,(q.huntProgress or 0)+1) end
				collect(q,"Shard",1)
				update:FireClient(ally,snapshot(ally,"Warden defeated • +1 Shard, +15 coins, +40 Combat XP"))
			end
		end
		task.delay(8,function() if arena[key]==boss then arena[key]=nil end end)
		return "Warden defeated • +1 Shard, +15 coins, +40 Combat XP"
	end
	return "Unknown action."
end
action.OnServerInvoke=function(player,verb,item)
	if type(verb)~="string" or #verb>32 or (item~=nil and type(item)~="string") then return nil end
	if os.clock()<(lastRead[player] or 0) then return nil end
	lastRead[player]=os.clock()+0.08
	if verb=="state" then
		-- Full snapshots are expensive (stats + every builder); poll at most twice a second.
		if os.clock()<(stateRead[player] or 0) then return nil end
		stateRead[player]=os.clock()+STATE_INTERVAL
		return snapshot(player)
	end
	if item~=nil and #item>64 then return snapshot(player,"That request is too long.") end
	return snapshot(player,perform(player,verb,item,nil))
end
action.Parent=ReplicatedStorage
prompts.PromptTriggered:Connect(function(prompt,player)
	local verb=prompt:GetAttribute("IsleAction")
	if not verb or not prompt.Enabled then return end
	local owner=prompt:GetAttribute("OwnerUserId")
	if owner and owner~=player.UserId then return end
	local base=prompt:FindFirstAncestorWhichIsA("BasePart")
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not base or not root or (root.Position-base.Position).Magnitude>prompt.MaxActivationDistance+3 then return end
	update:FireClient(player,snapshot(player,perform(player,verb,prompt:GetAttribute("IsleItem"),prompt)))
end)
Players.PlayerAdded:Connect(open)
for _,player in ipairs(Players:GetPlayers()) do task.spawn(open,player) end
local function close(player)
	-- Still loading: open() notices the departure, releases the lease and forgets.
	if opening[player] then return end
	while exchangeBusy[player] do task.wait(0.1) end
	for _=1,3 do if persist(player,true) then break end; task.wait(1) end
	forget(player)
	for _,arena in pairs(enemies) do
		arena[player.UserId]=nil
		for _,boss in pairs(arena) do boss.hits[player]=nil end
	end
end
Players.PlayerRemoving:Connect(close)
task.spawn(function()
	while task.wait(55) do for player in pairs(profiles) do task.spawn(persist,player,false) end end
end)
-- Timed buffs: drop expired entries and re-apply stats so Health/Speed settle.
task.spawn(function()
	while task.wait(5) do
		local now=os.time()
		for player,p in pairs(profiles) do
			local expired={}
			for id,buff in pairs(p.buffs or {}) do
				if not buff.expires or buff.expires<=now then table.insert(expired,id) end
			end
			if #expired>0 then
				for _,id in ipairs(expired) do p.buffs[id]=nil end
				local names={}
				for _,id in ipairs(expired) do table.insert(names,Data.Items[id] and Data.Items[id].name or id) end
				update:FireClient(player,snapshot(player,table.concat(names,", ").." wore off."))
			end
		end
	end
end)
game:BindToClose(function()
	local pending=0
	for player in pairs(profiles) do
		pending+=1
		task.spawn(function() close(player); pending-=1 end)
	end
	while pending>0 do task.wait(0.1) end
end)
local expedition = Instance.new("BindableEvent")
expedition.Name = "IsleExpeditionReward"
-- Dungeons: result {floor, grade, score, partySize, damageShare} from expedition.server.lua
-- (a bare Fire(player) is a legacy Floor I, grade B clear). The profile re-checks
-- the floor's Dungeoneering gate, the 90 s clear cooldown and the Ironman rule.
expedition.Event:Connect(function(player,result)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return end
	result=if type(result)=="table" then result else {}
	local floorIndex=if type(result.floor)=="number" and Data.DungeonFloors[result.floor] then result.floor else 1
	local floor=Data.DungeonFloors[floorIndex]
	local grade=if type(result.grade)=="string" and Data.DungeonGradeById[result.grade] then result.grade else "B"
	local score=if type(result.score)=="number" and result.score==result.score then math.clamp(math.floor(result.score),0,300) else 0
	local partySize=if type(result.partySize)=="number" then result.partySize else 1
	local share=if type(result.damageShare)=="number" and result.damageShare==result.damageShare then result.damageShare else 1
	local now=os.time()
	local dungeons=type(p.dungeons)=="table" and p.dungeons or {lastClear=0,clears={},best={}}
	p.dungeons=dungeons
	dungeons.clears=dungeons.clears or {}
	dungeons.best=dungeons.best or {}
	if level(p.xp.Dungeoneering)<floor.level then return end
	if not Data.dungeonCooldownReady(dungeons.lastClear,now) then
		update:FireClient(player,snapshot(player,"Observatory chest cooling down • wait "..(Data.Dungeons.clearCooldown-(now-dungeons.lastClear)).."s between credited clears."))
		return
	end
	if not Data.dungeonIronmanCredit(p.ironman==true,partySize,share) then
		update:FireClient(player,snapshot(player,"Ironman journals need a solo clear or 30% of the party's damage for Observatory credit."))
		return
	end
	dungeons.lastClear=now
	local key=tostring(floorIndex)
	dungeons.clears[key]=(dungeons.clears[key] or 0)+1
	if score>(dungeons.best[key] or 0) then dungeons.best[key]=score end
	local reward=Data.dungeonRewards(floorIndex,grade)
	p.started=true
	grantXp(p,"Combat",reward.combatXp)
	grantXp(p,"Dungeoneering",reward.dungeoneeringXp)
	p.coins+=reward.coins
	for item,n in pairs(reward.items) do collect(p,item,n) end
	local stats=Progression.computeStats(p,now)
	local drops=Progression.rollDrops(reward.chest,stats.magicFind,roll,stats.petLuck)
	for item,n in pairs(drops) do collect(p,item,n) end
	update:FireClient(player,snapshot(player,floor.name.." cleared • Grade "..grade.." • +"..reward.coins.." coins, +"..reward.combatXp.." Combat and +"
		..reward.dungeoneeringXp.." Dungeoneering XP, "..reward.items.Stormglass.." Stormglass"..dropText(drops)))
end)
expedition.Parent=ServerStorage

-- World transit uses the same authoritative unlock as region resource prompts.
local regionAccess=Instance.new("BindableFunction")
regionAccess.Name="IsleRegionAccess"
regionAccess.OnInvoke=function(player,region)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return {allowed=false,message="Waiting for journal sync."} end
	local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health<=0 then return {allowed=false,message="Return to your island first."} end
	local allowed=regionAllowed(p,region)
	if region=="Skyreach" then
		return {allowed=allowed,message=if allowed then "Skyreach charter accepted." else "Claim the Skyreach charter in your journal: Mining 3 and 3 lifetime Alloy Ingots."}
	end
	if not allowed then return {allowed=false,message=regionDenied(region)} end
	return {allowed=true,message="Welcome to "..Data.RegionById[region].name.."."}
end
regionAccess.Parent=ServerStorage

-- Server-to-server bridge consumed by Combat (docs/DEPTH-CONTRACT.md §4).
local bridge=Instance.new("BindableFunction")
bridge.Name="IsleBridge"
local function notify(player,message)
	if player.Parent then update:FireClient(player,snapshot(player,message)) end
end
bridge.OnInvoke=function(op,player,payload)
	if type(op)~="string" or player==nil then return nil end
	if type(payload)~="table" then payload={} end
	if op=="damage" then
		local raw=payload.amount
		if type(raw)~="number" or raw~=raw or raw<=0 then return 0 end
		local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health<=0 then return 0 end
		local p=profiles[player]
		local defense=if p then Progression.computeStats(p,os.time()).defense else 0
		local amount=Progression.damageTaken(math.min(raw,1e9),defense)
		humanoid:TakeDamage(amount)
		return amount
	end
	local p=live(player)
	if not p then
		-- Combat re-arms the boss when its report could not be applied.
		return if op=="slayerBoss" then {ok=false,reason="sync"} else nil
	end
	if op=="stats" then
		return {stats=Progression.computeStats(p,os.time()),combatLevel=level(p.xp.Combat),ironman=p.ironman==true}
	elseif op=="dungeon" then
		-- Dungeons: floor gate + Ironman flag for expedition.server.lua.
		return {level=level(p.xp.Dungeoneering),ironman=p.ironman==true}
	elseif op=="kill" then
		local monsterId=payload.monster
		local monster=validId(monsterId) and Data.Monsters[monsterId]
		if not monster then return nil end
		local stats=Progression.computeStats(p,os.time())
		p.started=true
		grantXp(p,"Combat",monster.xp)
		p.coins+=monster.coins
		local drops=Progression.rollDrops(monster.drops,stats.magicFind,roll,stats.petLuck)
		for item,n in pairs(drops) do collect(p,item,n) end
		p.bestiary[monsterId]=(p.bestiary[monsterId] or 0)+1
		local quest=p.slayerQuest
		if quest and not quest.bossReady and monster.slayer==quest.line then
			quest.progress=math.min(quest.needed,quest.progress+monster.xp)
			if quest.progress>=quest.needed then
				quest.bossReady=true
				note(p,"The "..Data.Slayers[quest.line].name.." stirs! Defeat it to finish your slayer quest.")
			end
		end
		notify(player,monster.name.." slain • +"..monster.coins.." coins, +"..monster.xp.." Combat XP"..dropText(drops))
		return {drops=drops,bossReady=quest~=nil and quest.bossReady==true}
	elseif op=="slayerBoss" then
		local quest=p.slayerQuest
		local result=payload.result
		if not quest or not quest.bossReady or (result~="win" and result~="fail") then return {ok=false,reason="invalid"} end
		p.slayerQuest=nil
		local line=Data.Slayers[quest.line]
		if result=="fail" then
			notify(player,"The "..line.name.." escaped. Your slayer quest failed.")
			return {ok=true}
		end
		local tier=line.tiers[quest.tier]
		local stats=Progression.computeStats(p,os.time())
		p.slayerXp[quest.line]=(p.slayerXp[quest.line] or 0)+tier.xp
		local drops=Progression.rollDrops(tier.drops,stats.magicFind,roll,stats.petLuck)
		for item,n in pairs(drops) do collect(p,item,n) end
		notify(player,line.name.." defeated • +"..tier.xp.." "..quest.line.." Slayer XP"..dropText(drops))
		return {ok=true,drops=drops}
	end
	return nil
end
bridge.Parent=ServerStorage

-- Only server co-op code can seal mode selection; personal inventory stays private.
local coopProfile=Instance.new("BindableFunction")
coopProfile.Name="IsleCoopProfile"
coopProfile.OnInvoke=function(player,seal)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return {ready=false} end
	if seal then
		p.started=true
		if not persist(player,false) then return {ready=false} end
	end
	return {ready=true,ironman=p.ironman==true,preview=preview[player]==true}
end
coopProfile.Parent=ServerStorage



-- The player journal reserves the payment before the market is touched. A receipt
-- keyed by sequence makes replay safe if a server crashes between the two writes.
local marketPrices={Ore=15,Timber=12,Herb=9,Fish=18}
local previewBooks={}
local function normalizeBook(book,item)
	book=book or {orders={},proceeds={},receipts={},accounts=0}
	book.pricedOrders=book.pricedOrders or {}
	book.pricedReceipts=book.pricedReceipts or {}
	book.pricedAccounts=book.pricedAccounts or 0
	book.nextPricedOrder=book.nextPricedOrder or 0
	book.revision=book.revision or 0
	book.version=2
	return book
end
local function quote(book,item,trader)
	book=normalizeBook(book,item)
	local best,own=nil,0
	for _,seller in ipairs(book.orders) do
		if seller==trader then own+=1 elseif not best or marketPrices[item]<best then best=marketPrices[item] end
	end
	for _,lot in ipairs(book.pricedOrders) do
		if lot.seller==trader then own+=1 elseif not best or lot.price<best then best=lot.price end
	end
	return {item=item,bestAsk=best,ownLots=own,openLots=#book.orders+#book.pricedOrders,proceeds=book.proceeds[trader] or 0,
		lotSize=3,minPrice=1,maxPrice=10000,defaultPrice=marketPrices[item],fetchedAt=os.time(),revision=book.revision,
		matchingPolicy="Lowest ask; legacy lots first on equal price, then oldest within each queue."}
end
local function trade(book,trader,order)
	book=normalizeBook(book,order.item)
	local priced=order.protocol==2
	local receipts=if priced then book.pricedReceipts else book.receipts
	local receipt=receipts[trader]
	if receipt and receipt.seq>=order.seq then return book end
	-- Reserve membership in the legacy account registry too. Old servers see a
	-- harmless sequence-zero receipt, so both versions enforce one 4000-user cap.
	-- Existing legacy sellers can always acquire a priced receipt and recover funds.
	if not book.receipts[trader] then
		if book.accounts>=4000 then return nil end
		book.accounts+=1
		if priced then book.receipts[trader]={seq=0,coins=0,units=0,text=""} end
	end
	if priced and not receipt then book.pricedAccounts+=1 end
	local price=order.price or marketPrices[order.item]
	local result={seq=order.seq,coins=0,units=0,text=""}
	local verb=order.verb
	if verb=="list" then
		if #book.orders+#book.pricedOrders>=300 then
			result.units=3
			result.text="Order board full. Your goods were returned."
		else
			if priced then
				book.nextPricedOrder+=1
				table.insert(book.pricedOrders,{seller=trader,price=price,sequence=book.nextPricedOrder})
			else table.insert(book.orders,trader) end
			result.text="Listed 3 "..order.item.." for "..price.." coins."
		end
	elseif verb=="buy" or verb=="cancel" then
		local index,legacyIndex,bestPrice
		for i,seller in ipairs(book.orders) do
			if (verb=="cancel" and seller==trader) or (verb=="buy" and seller~=trader and marketPrices[order.item]<=price) then
				legacyIndex=i;bestPrice=marketPrices[order.item];break
			end
		end
		for i,lot in ipairs(book.pricedOrders) do
			if verb=="cancel" and lot.seller==trader then
				if not legacyIndex and (not index or lot.sequence<book.pricedOrders[index].sequence) then index=i end
			elseif verb=="buy" and lot.seller~=trader and lot.price<=price then
				local best=index and book.pricedOrders[index]
				if not bestPrice or lot.price<bestPrice or (not legacyIndex and best and lot.price==bestPrice and lot.sequence<best.sequence) then
					index=i;legacyIndex=nil;bestPrice=lot.price
				end
			end
		end
		if index or legacyIndex then
			local lot=if legacyIndex then {seller=table.remove(book.orders,legacyIndex),price=marketPrices[order.item]} else table.remove(book.pricedOrders,index)
			if verb=="buy" then
				book.proceeds[lot.seller]=(book.proceeds[lot.seller] or 0)+lot.price
				result.coins=price-lot.price
			end
			result.units=3
			result.text=if verb=="buy" then "Bought 3 "..order.item.." for "..lot.price.." coins; "..result.coins.." reserved coins returned." else "Listing cancelled. Goods returned; legacy lots are cancelled before priced lots."
		else
			result.coins=if verb=="buy" then price else 0
			result.text=if verb=="buy" then "No other player's lot is at or below your limit. Reserved coins returned." else "You have no open listing here."
		end
	else
		result.coins=book.proceeds[trader] or 0
		book.proceeds[trader]=nil
		result.text="Collected "..result.coins.." coins from "..order.item.." sales."
	end
	receipts[trader]=result
	book.revision+=1
	return book
end
local function settle(player)
	local p=profiles[player]
	local order=p.pricedPending or p.pending
	if not persist(player,false) then return "Market waiting for a journal save. Try again." end
	local trader=tostring(player.UserId)
	local result,committed
	local function apply(old)
		local nextBook=trade(old,trader,order)
		return nextBook
	end
	local key="market_v1_"..order.item
	local ok=pcall(function()
		if preview[player] then committed=apply(previewBooks[key]);previewBooks[key]=committed or previewBooks[key]
		else committed=store:UpdateAsync(key,apply) end
	end)
	if not ok then return "Order pending. The exchange will retry safely." end
	result=committed and (if order.protocol==2 then committed.pricedReceipts[trader] else committed.receipts[trader]) or nil
	if committed then marketViews[player]=quote(committed,order.item,trader) end
	if not result then
		result={units=if order.verb=="list" then 3 else 0,coins=if order.verb=="buy" then (order.price or marketPrices[order.item]) else 0,
			text="This exchange is at capacity. Your reservation was returned."}
	end
	p.items[order.item]=(p.items[order.item] or 0)+result.units
	p.coins+=result.coins
	if order.protocol==2 then p.pricedPending=nil else p.pending=nil end
	return result.text
end
exchangeAction=function(player,verb,item,resume)
	local p=profiles[player]
	local price
	if verb=="list" or verb=="buy" then
		local commodity,raw=string.match(item,"^(%a+):(%d+)$")
		if commodity then
			price=tonumber(raw)
			if #raw>5 or not price or price<1 or price>10000 or price%1~=0 then return "Use a whole lot price from 1 to 10000 coins." end
			item=commodity
		elseif string.find(item,":",1,true) then return "Use a whole lot price from 1 to 10000 coins." end
	end
	if not marketPrices[item] then return "Choose a market commodity." end
	if p.ironman then return "Ironman journals cannot use the player exchange." end
	if exchangeBusy[player] then return "An order is already being processed." end
	if verb=="market" then
		if os.clock()<(marketReads[player] or 0) then return "Quote refreshed recently. Prices can change; purchases use your limit." end
		marketReads[player]=os.clock()+3
		local ok,book=pcall(function() return if preview[player] then previewBooks["market_v1_"..item] else store:GetAsync("market_v1_"..item) end)
		if not ok then return "Market quote unavailable. Your previous quote may be stale." end
		marketViews[player]=quote(book,item,tostring(player.UserId))
		return "Market quote refreshed. Three units per lot; buy uses your maximum total price."
	end
	price=price or marketPrices[item]
	local idle=not p.pending and not p.pricedPending
	-- The cached view is exact for own lots: they only grow through this session's
	-- own listings, each of which refreshes the view when it commits. Proceeds grow
	-- through other players' purchases, so collecting them always reads the DataStore.
	local view=marketViews[player]
	if idle and verb=="cancel" and view and view.item==item and view.ownLots==0 then return "You have no open listing here." end
	-- Every writing verb touches the player key and the shared market key; pace them.
	if not resume and os.clock()<(exchangeReady[player] or 0) then
		return "The exchange is still recording your last order. Try again in "..math.ceil(exchangeReady[player]-os.clock()).."s."
	end
	if idle then
		if verb=="list" and not spend(p,{[item]=3}) then return "A market lot needs 3 "..item.."." end
		if verb=="buy" then
			if p.coins<price then return "You need "..price.." purse coins to reserve this buy limit." end
			p.coins-=price
		end
		p.started=true
		p.pricedSeq=(p.pricedSeq or 0)+1
		p.pricedPending={seq=p.pricedSeq,verb=verb,item=item,price=price,protocol=2}
	end
	exchangeReady[player]=os.clock()+EXCHANGE_COOLDOWN
	exchangeBusy[player]=true
	local ok,message=pcall(settle,player)
	exchangeBusy[player]=nil
	return if ok then message else "Exchange delayed. Retry to recover your order."
end
resumeExchange=function(player)
	local p=profiles[player]
	for _=1,2 do
		if not p or not (p.pending or p.pricedPending) then break end
		local order=p.pricedPending or p.pending
		local message=exchangeAction(player,order.verb,order.item,true)
		if player.Parent then update:FireClient(player,snapshot(player,message)) end
		if (p.pricedPending or p.pending)==order then break end
	end
	if Econ.resume then Econ.resume(player) end
end

------------------------------------------------------------------------------
-- Economy: Bazaar standing orders (commodities) and the Auction House (gear).
-- Same durability pattern as the exchange above: escrow is taken into the
-- profile (p.econPending) and saved before the shared key is written; each
-- shared key keeps one receipt per trader, so a replayed order applies exactly
-- once and recovery on rejoin is idempotent. Keys: bazaar_v1_<item>, auction_v1_<kind>.
------------------------------------------------------------------------------
do
local Rules=Data.Economy
local previewEcon={}
local READ_INTERVAL=2
local categorySet={}
for _,kind in ipairs(Rules.auctionCategories) do categorySet[kind]=true end
local bazaarVerbs={bid=true,offer=true,buyNow=true,sellToBid=true,bidCancel=true,bidClaim=true}
Econ.verbs={bazaar=true,ahBrowse=true,ahList=true,ahBuy=true,ahCancel=true,ahClaim=true}
for verb in pairs(bazaarVerbs) do Econ.verbs[verb]=true end
local function whole(raw,digits,low,high)
	if type(raw)~="string" or not string.match(raw,"^%d+$") or #raw>digits then return nil end
	local n=tonumber(raw)
	if not n or n<low or n>high or n%1~=0 then return nil end
	return n
end
local function itemName(id) return Data.Items[id] and Data.Items[id].name or id end
local function mirror(p)
	if type(p.econOrders)~="table" then p.econOrders={} end
	if type(p.econListings)~="table" then p.econListings={} end
	return p.econOrders,p.econListings
end
local function normalizeBazaar(book)
	book=book or {}
	book.bids=book.bids or {}
	book.asks=book.asks or {}
	book.claims=book.claims or {}
	book.receipts=book.receipts or {}
	book.accounts=book.accounts or 0
	book.nextId=book.nextId or 0
	book.revision=book.revision or 0
	book.version=1
	return book
end
local function normalizeAuction(book)
	book=book or {}
	book.listings=book.listings or {}
	book.proceeds=book.proceeds or {}
	book.returns=book.returns or {}
	book.receipts=book.receipts or {}
	book.accounts=book.accounts or 0
	book.nextId=book.nextId or 0
	book.revision=book.revision or 0
	book.version=1
	return book
end
-- Bids are kept highest price first, asks lowest first; equal prices keep
-- arrival order (FIFO), so the head of each list is always next to fill.
local function insertOrder(list,order,descending)
	local at=#list+1
	for i,o in ipairs(list) do
		if (descending and order.price>o.price) or (not descending and order.price<o.price) then at=i;break end
	end
	table.insert(list,at,order)
end
-- A taker crosses the opposite side at each maker's price, skipping its own orders.
local function take(book,uid,side,qty,limit)
	local orders=if side=="buy" then book.asks else book.bids
	local filled,value,i=0,0,1
	while qty>0 and i<=#orders do
		local o=orders[i]
		if (side=="buy" and o.price>limit) or (side=="sell" and o.price<limit) then break end
		if o.owner==uid then
			i+=1
		else
			local n=math.min(qty,o.qty)
			o.qty-=n
			qty-=n
			filled+=n
			value+=n*o.price
			local claim=book.claims[o.owner] or {units=0,coins=0}
			book.claims[o.owner]=claim
			if side=="buy" then claim.coins+=n*o.price else claim.units+=n end
			if o.qty==0 then table.remove(orders,i) else i+=1 end
		end
	end
	return filled,value
end
-- Receipts store open orders compactly ({id,price,qty,1=bid|2=ask}) to keep
-- the worst-case book (accountCap receipts) well inside the DataStore limit.
local function ownOrders(book,uid,compact)
	local open={}
	for _,side in ipairs({"bids","asks"}) do
		for _,o in ipairs(book[side]) do
			if o.owner==uid then
				table.insert(open,if compact then {o.id,o.price,o.qty,if side=="bids" then 1 else 2} else {id=o.id,side=if side=="bids" then "bid" else "ask",price=o.price,qty=o.qty})
			end
		end
	end
	return open
end
local function joined(text,more) return if text~="" then text.." "..more else more end
local function bazaarTrade(book,uid,order)
	book=normalizeBazaar(book)
	local receipt=book.receipts[uid]
	if receipt and receipt.seq>=order.seq then return book end
	if not receipt then
		if book.accounts>=Rules.accountCap then return nil end
		book.accounts+=1
	end
	local verb,qty,price,name=order.verb,order.qty or 0,order.price or 0,itemName(order.item)
	local coins,units,text=0,0,""
	local room=#book.bids+#book.asks<Rules.bookCap
	if verb=="bid" or verb=="buyNow" then
		local filled,cost=take(book,uid,"buy",qty,price)
		units=filled
		coins=filled*price-cost
		local rest=qty-filled
		if filled>0 then text="Bought "..filled.." "..name.." for "..cost.." coins." end
		if rest>0 and verb=="bid" and room then
			book.nextId+=1
			insertOrder(book.bids,{id=book.nextId,owner=uid,price=price,qty=rest},true)
			text=joined(text,"Buy order #"..book.nextId..": "..rest.." "..name.." at "..price.." each, coins escrowed.")
		elseif rest>0 then
			coins+=rest*price
			text=joined(text,(if verb=="bid" then "The order book is full; " else "No sell offer at or below "..price.."; ")..rest.." unfilled, coins returned.")
		end
	elseif verb=="offer" or verb=="sellToBid" then
		local filled,value=take(book,uid,"sell",qty,price)
		coins=value
		local rest=qty-filled
		if filled>0 then text="Sold "..filled.." "..name.." for "..value.." coins." end
		if rest>0 and verb=="offer" and room then
			book.nextId+=1
			insertOrder(book.asks,{id=book.nextId,owner=uid,price=price,qty=rest},false)
			text=joined(text,"Sell offer #"..book.nextId..": "..rest.." "..name.." at "..price.." each, goods escrowed.")
		elseif rest>0 then
			units+=rest
			text=joined(text,(if verb=="offer" then "The order book is full; " else "No buy order at or above "..price.."; ")..rest.." unsold returned.")
		end
	elseif verb=="bidCancel" then
		local found,side
		for _,list in ipairs({"bids","asks"}) do
			for i,o in ipairs(book[list]) do
				if o.id==order.id and o.owner==uid then found=table.remove(book[list],i);side=list;break end
			end
			if found then break end
		end
		if found and side=="bids" then
			coins+=found.qty*found.price
			text="Buy order #"..found.id.." cancelled; "..found.qty*found.price.." escrowed coins refunded."
		elseif found then
			units+=found.qty
			text="Sell offer #"..found.id.." cancelled; "..found.qty.." "..name.." returned."
		else
			text="Order #"..order.id.." is no longer open; it may have filled."
		end
	end
	-- Every write also collects this trader's filled goods and sale coins.
	local claim=book.claims[uid]
	book.claims[uid]=nil
	if claim and (claim.units>0 or claim.coins>0) then
		units+=claim.units
		coins+=claim.coins
		text=joined(text,"Collected "..claim.units.." "..name.." and "..claim.coins.." coins from filled orders.")
	elseif verb=="bidClaim" then
		text="Nothing to collect yet."
	end
	book.receipts[uid]={seq=order.seq,coins=coins,items=if units>0 then {[order.item]=units} else {},text=text,open=ownOrders(book,uid,true)}
	book.revision+=1
	return book
end
-- Expired listings leave the board; the item waits for its seller's claim.
local function purgeExpired(book,now)
	local i=1
	while i<=#book.listings do
		local l=book.listings[i]
		if l.expires<=now then
			local back=book.returns[l.seller] or {}
			back[l.item]=(back[l.item] or 0)+1
			book.returns[l.seller]=back
			table.remove(book.listings,i)
		else
			i+=1
		end
	end
end
local function ownListings(book,uid)
	local open={}
	for _,l in ipairs(book.listings) do
		if l.seller==uid then table.insert(open,{l.id,l.item,l.price,l.expires}) end
	end
	return open
end
local function auctionTrade(book,uid,order,now)
	book=normalizeAuction(book)
	local receipt=book.receipts[uid]
	if receipt and receipt.seq>=order.seq then return book end
	if not receipt then
		if book.accounts>=Rules.accountCap then return nil end
		book.accounts+=1
	end
	purgeExpired(book,now)
	local coins,items,text=0,{},""
	local function give(id,n) items[id]=(items[id] or 0)+n end
	local verb=order.verb
	local index
	for i,l in ipairs(book.listings) do if l.id==order.id then index=i;break end end
	local listing=index and book.listings[index]
	if verb=="ahList" then
		if #book.listings>=Rules.auctionCap then
			give(order.item,1)
			coins+=order.fee
			text="The Auction House is full. Your item and listing fee were returned."
		else
			book.nextId+=1
			table.insert(book.listings,{id=book.nextId,seller=uid,item=order.item,price=order.price,expires=now+Rules.auctionDuration})
			text="Listed "..itemName(order.item).." for "..order.price.." coins (listing #"..book.nextId..", fee "..order.fee.." coins). It expires in 24 hours."
		end
	elseif verb=="ahBuy" then
		if not listing then
			coins+=order.price
			text="That listing is gone (sold, cancelled or expired). Your coins were returned."
		elseif listing.seller==uid then
			coins+=order.price
			text="You cannot buy your own listing. Your coins were returned."
		elseif listing.price>order.price then
			coins+=order.price
			text="That listing costs more than you offered. Your coins were returned."
		else
			table.remove(book.listings,index)
			book.proceeds[listing.seller]=(book.proceeds[listing.seller] or 0)+listing.price
			give(listing.item,1)
			coins+=order.price-listing.price
			text="Bought "..itemName(listing.item).." for "..listing.price.." coins."
		end
	elseif verb=="ahCancel" then
		if listing and listing.seller==uid then
			table.remove(book.listings,index)
			give(listing.item,1)
			text="Listing #"..listing.id.." cancelled; "..itemName(listing.item).." returned. The listing fee is not refunded."
		else
			text="That listing is no longer open; it may have sold or expired."
		end
	end
	-- Every write also collects this seller's proceeds and expired items.
	local proceeds=book.proceeds[uid] or 0
	local back=book.returns[uid]
	book.proceeds[uid],book.returns[uid]=nil,nil
	local returned=0
	for id,n in pairs(back or {}) do give(id,n);returned+=n end
	if proceeds>0 or returned>0 then
		coins+=proceeds
		text=joined(text,"Collected "..proceeds.." coins of sales and "..returned.." expired item"..(if returned==1 then "" else "s")..".")
	elseif verb=="ahClaim" then
		text="Nothing to collect in this category yet."
	end
	book.receipts[uid]={seq=order.seq,coins=coins,items=items,text=text,open=ownListings(book,uid)}
	book.revision+=1
	return book
end
local function depthOf(list)
	local levels={}
	for _,o in ipairs(list) do
		local last=levels[#levels]
		if last and last.price==o.price then
			last.qty+=o.qty
			last.orders+=1
		elseif #levels<Rules.depth then
			table.insert(levels,{price=o.price,qty=o.qty,orders=1})
		else
			break
		end
	end
	return levels
end
local function bestOther(list,uid)
	for _,o in ipairs(list) do if o.owner~=uid then return o.price end end
	return nil
end
local function bazaarView(book,item,uid,now)
	book=normalizeBazaar(book)
	local bestBid,bestAsk=bestOther(book.bids,uid),bestOther(book.asks,uid)
	local claim=book.claims[uid]
	return {item=item,bids=depthOf(book.bids),asks=depthOf(book.asks),bestBid=bestBid,bestAsk=bestAsk,
		spread=if bestBid and bestAsk then bestAsk-bestBid else nil,openOrders=#book.bids+#book.asks,mine=ownOrders(book,uid),
		claimUnits=claim and claim.units or 0,claimCoins=claim and claim.coins or 0,fetchedAt=now,revision=book.revision,
		matchingPolicy="Highest bid and lowest offer fill first; equal prices fill oldest first. Your own orders never match each other."}
end
local function auctionView(book,cat,uid,page,now)
	book=normalizeAuction(book)
	local active,expired={},0
	for _,l in ipairs(book.listings) do
		if l.expires>now then table.insert(active,l) elseif l.seller==uid then expired+=1 end
	end
	table.sort(active,function(a,b) if a.price~=b.price then return a.price<b.price end return a.id<b.id end)
	local pages=math.max(1,math.ceil(#active/Rules.pageSize))
	page=math.clamp(page,1,pages)
	local rows={}
	for i=(page-1)*Rules.pageSize+1,math.min(#active,page*Rules.pageSize) do
		local l=active[i]
		table.insert(rows,{id=l.id,item=l.item,price=l.price,remaining=l.expires-now,own=l.seller==uid})
	end
	for _,n in pairs(book.returns[uid] or {}) do expired+=n end
	return {category=cat,page=page,pages=pages,total=#active,listings=rows,proceeds=book.proceeds[uid] or 0,returns=expired,fetchedAt=now,revision=book.revision}
end
-- Validates a request without changing the profile. Returns the order or a message.
local function prepare(p,verb,item)
	local orders,listings=mirror(p)
	if bazaarVerbs[verb] then
		local id,a,b
		if verb=="bidClaim" then id=string.match(item,"^(%w+)$")
		elseif verb=="bidCancel" then id,a=string.match(item,"^(%w+):(%d+)$")
		else
			id,a,b=string.match(item,"^(%w+):(%d+):(%d+)$")
			if not id and verb=="sellToBid" then id,a=string.match(item,"^(%w+):(%d+)$") end
		end
		if not id or not Rules.isCommodity(id) then return nil,"Choose a Bazaar commodity (a resource or material) and a valid order." end
		local order={kind="bazaar",verb=verb,item=id,key="bazaar_v1_"..id,coins=0,units=0}
		if verb=="bidCancel" then
			order.id=whole(a,9,1,999999999)
			if not order.id then return nil,"Choose one of your order numbers." end
		elseif verb~="bidClaim" then
			order.qty=whole(a,3,1,Rules.maxQuantity)
			if not order.qty then return nil,"Choose a whole quantity from 1 to "..Rules.maxQuantity.."." end
			order.price=if verb=="sellToBid" and b==nil then Rules.minPrice else whole(b,7,Rules.minPrice,Rules.maxPrice)
			if not order.price then return nil,"Use a whole unit price from 1 to 1,000,000 coins." end
			if (verb=="bid" or verb=="offer") and #orders>=Rules.orderCap then return nil,"You already have "..Rules.orderCap.." open Bazaar orders. Claim or cancel one first." end
			if verb=="bid" or verb=="buyNow" then
				order.coins=order.qty*order.price
				if p.coins<order.coins then return nil,"You need "..order.coins.." purse coins to escrow this order." end
			else
				order.units=order.qty
				if (p.items[id] or 0)<order.qty then return nil,"You need "..order.qty.." "..itemName(id).." in your satchel." end
			end
		end
		return order
	end
	if verb=="ahList" then
		local id,raw=string.match(item,"^(%w+):(%d+)$")
		local cat=id and Rules.auctionCategory(id)
		if not cat then return nil,"Choose a weapon, armor piece, tool, accessory or pet item to auction." end
		local price=whole(raw,7,Rules.minPrice,Rules.maxPrice)
		if not price then return nil,"Use a whole buy-it-now price from 1 to 1,000,000 coins." end
		if (p.items[id] or 0)<1 then return nil,"You do not have "..itemName(id).."." end
		if isEquipped(p,id) then return nil,"Unequip "..itemName(id).." (or take it out of your accessory bag) before listing it." end
		if type(p.enchants[id])=="table" and next(p.enchants[id]) then return nil,"Enchanted gear cannot be auctioned: enchants stay bound to your journal." end
		if #listings>=Rules.listingCap then return nil,"You already have "..Rules.listingCap.." auction listings. Claim or cancel one first." end
		local fee=Rules.auctionFee(price)
		if p.coins<fee then return nil,"The listing fee is "..fee.." purse coins." end
		return {kind="auction",verb=verb,cat=cat,key="auction_v1_"..cat,item=id,price=price,fee=fee,coins=fee,units=1}
	end
	local cat,a,b
	if verb=="ahBuy" then cat,a,b=string.match(item,"^(%a+):(%d+):(%d+)$")
	elseif verb=="ahCancel" then cat,a=string.match(item,"^(%a+):(%d+)$")
	else cat=string.match(item,"^(%a+)$") end
	if not cat or not categorySet[cat] then return nil,"Choose an auction category and listing." end
	local order={kind="auction",verb=verb,cat=cat,key="auction_v1_"..cat,coins=0,units=0}
	if verb~="ahClaim" then
		order.id=whole(a,9,1,999999999)
		if not order.id then return nil,"Choose a listing." end
	end
	if verb=="ahBuy" then
		order.price=whole(b,7,Rules.minPrice,Rules.maxPrice)
		if not order.price then return nil,"Use the listing's whole coin price." end
		if p.coins<order.price then return nil,"You need "..order.price.." purse coins to buy this listing." end
		order.coins=order.price
	end
	return order
end
local function refund(p,order)
	p.coins+=order.coins
	if order.units>0 then p.items[order.item]=(p.items[order.item] or 0)+order.units end
end
local function remember(player,order,committed,uid,now)
	local views=Econ.views[player] or {}
	Econ.views[player]=views
	if order.kind=="bazaar" then
		views.bazaar=bazaarView(committed,order.item,uid,now)
	else
		local page=if views.auction and views.auction.category==order.cat then views.auction.page else 1
		views.auction=auctionView(committed,order.cat,uid,page,now)
	end
end
local function settle(player)
	local p=profiles[player]
	local order=p.econPending
	if not persist(player,false) then return "Market waiting for a journal save. Try again." end
	local uid=tostring(player.UserId)
	local now=os.time()
	local function apply(old)
		if order.kind=="bazaar" then return bazaarTrade(old,uid,order) end
		return auctionTrade(old,uid,order,now)
	end
	local committed
	local ok=pcall(function()
		if preview[player] then
			committed=apply(deepCopy(previewEcon[order.key]))
			if committed then previewEcon[order.key]=deepCopy(committed) end
		else
			committed=store:UpdateAsync(order.key,apply)
		end
	end)
	if not ok then return "Order pending. The exchange will retry safely." end
	local receipt=type(committed)=="table" and type(committed.receipts)=="table" and committed.receipts[uid] or nil
	if not receipt or receipt.seq~=order.seq then
		refund(p,order)
		p.econPending=nil
		return "This market is at capacity. Your escrow was returned."
	end
	p.coins+=receipt.coins
	for id,n in pairs(receipt.items or {}) do
		if Data.Items[id] and n>0 then p.items[id]=(p.items[id] or 0)+n end
	end
	local orders,listings=mirror(p)
	local kept={}
	if order.kind=="bazaar" then
		for _,o in ipairs(orders) do if o.item~=order.item then table.insert(kept,o) end end
		for _,o in ipairs(receipt.open or {}) do table.insert(kept,{item=order.item,id=o[1],price=o[2],qty=o[3],side=if o[4]==1 then "bid" else "ask"}) end
		p.econOrders=kept
	else
		for _,l in ipairs(listings) do if l.cat~=order.cat then table.insert(kept,l) end end
		for _,l in ipairs(receipt.open or {}) do table.insert(kept,{cat=order.cat,id=l[1],item=l[2],price=l[3],expires=l[4]}) end
		p.econListings=kept
	end
	p.econPending=nil
	remember(player,order,committed,uid,now)
	return receipt.text
end
local function read(player,verb,item)
	if os.clock()<(Econ.reads[player] or 0) then return "Prices were refreshed moments ago. Try again shortly." end
	local key,id,cat,page
	if verb=="bazaar" then
		id=string.match(item,"^(%w+)$")
		if not id or not Rules.isCommodity(id) then return "Choose a Bazaar commodity (a resource or material)." end
		key="bazaar_v1_"..id
	else
		local raw
		cat,raw=string.match(item,"^(%a+):(%d+)$")
		if not cat then cat=string.match(item,"^(%a+)$") end
		page=if raw then whole(raw,2,1,Rules.maxPage) else 1
		if not cat or not categorySet[cat] or not page then return "Choose an auction category and page." end
		key="auction_v1_"..cat
	end
	Econ.reads[player]=os.clock()+READ_INTERVAL
	local ok,book=pcall(function()
		if preview[player] then return deepCopy(previewEcon[key]) end
		return store:GetAsync(key)
	end)
	if not ok then return "The ledger could not be read. Your previous view may be stale." end
	local views=Econ.views[player] or {}
	Econ.views[player]=views
	local uid=tostring(player.UserId)
	if verb=="bazaar" then
		views.bazaar=bazaarView(book,id,uid,os.time())
		return itemName(id).." order book refreshed. Prices are per unit."
	end
	views.auction=auctionView(book,cat,uid,page,os.time())
	return Rules.categoryNames[cat].." auctions refreshed (page "..views.auction.page.." of "..views.auction.pages..")."
end
Econ.action=function(player,verb,item,resume)
	local p=profiles[player]
	if p.ironman then return "Ironman journals cannot use the Bazaar or Auction House." end
	if exchangeBusy[player] then return "An order is already being processed." end
	if type(item)~="string" then item="" end
	if verb=="bazaar" or verb=="ahBrowse" then return read(player,verb,item) end
	local pending=p.econPending
	local order
	if not pending then
		local problem
		order,problem=prepare(p,verb,item)
		if not order then return problem end
	end
	-- Every writing verb touches the player key and a shared key; pace them.
	if not resume and os.clock()<(exchangeReady[player] or 0) then
		return "The exchange is still recording your last order. Try again in "..math.ceil(exchangeReady[player]-os.clock()).."s."
	end
	if not pending then
		p.coins-=order.coins
		if order.units>0 then p.items[order.item]-=order.units end
		p.started=true
		p.econSeq=(tonumber(p.econSeq) or 0)+1
		order.seq=p.econSeq
		p.econPending=order
	end
	exchangeReady[player]=os.clock()+EXCHANGE_COOLDOWN
	exchangeBusy[player]=true
	local ok,message=pcall(settle,player)
	exchangeBusy[player]=nil
	if not ok then return "Exchange delayed. Retry to recover your order." end
	if pending and not resume and not p.econPending then message="Recovered your earlier order first: "..message end
	return message
end
Econ.resume=function(player)
	local p=profiles[player]
	if not p or not p.econPending or p.ironman then return end
	local message=Econ.action(player,p.econPending.verb,"",true)
	if player.Parent then update:FireClient(player,snapshot(player,message)) end
end
-- Snapshot data (Ledger → Orders / Auctions). Mirrors list this journal's
-- open orders and listings as of its last write; views are the last read.
Econ.view=function(player,p)
	local views=Econ.views[player] or {}
	return {bazaar=views.bazaar,auction=views.auction,
		orders=if type(p.econOrders)=="table" then deepCopy(p.econOrders) else {},
		listings=if type(p.econListings)=="table" then deepCopy(p.econListings) else {},
		pending=p.econPending~=nil,readyIn=math.max(0,math.ceil((exchangeReady[player] or 0)-os.clock())),serverTime=os.time()}
end
end
