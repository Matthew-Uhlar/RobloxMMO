-- Islebound authoritative progression. Only registered world prompts award resources.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local prompts = game:GetService("ProximityPromptService")
local action = Instance.new("RemoteFunction")
action.Name = "IsleAction"
local update = Instance.new("RemoteEvent")
update.Name = "IsleUpdate"
update.Parent = ReplicatedStorage

local exchangeAction, resumeExchange
local marketViews,marketReads={},{}
local profiles, cooldown, lastRead, saving, preview, leaseEnd = {}, {}, {}, {}, {}, {}
local enemies = setmetatable({}, {__mode = "k"})
local uid = HttpService:GenerateGUID(false)
local store
pcall(function()
	store = DataStoreService:GetDataStore("Islebound_RPG_v1")
end)
local resources = {Timber="Woodcutting", Ore="Mining", Herb="Farming", Fish="Fishing"}
local gatheringSkills=table.clone(resources)
gatheringSkills.Aetherite="Mining"
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
local function fresh()
	return {version=1, xp={Mining=0,Woodcutting=0,Farming=0,Fishing=0,Smithing=0,Combat=0,Alchemy=0,Dungeoneering=0,Enchanting=0,Taming=0},
		items={},collection={},decorations={},coins=0,bank=0,worker=false,ironman=false,started=false,lastClaim=0,kills=0}
end
local function workerFleet(p)
	if not p.workers then
		p.workers={}
		if p.worker then p.workers[1]={resource=p.workerResource or "Ore",tier=1,lastClaim=p.lastClaim} end
	end
	return p.workers
end
local function workerReady(w)
	if not w then return 0 end
	return math.clamp(math.floor((os.time()-w.lastClaim)/(150-w.tier*30)),0,60+w.tier*60)
end
local function ready(p) return workerReady(workerFleet(p)[1]) end
local function workerState(p)
	local result={}
	for slot,w in ipairs(workerFleet(p)) do
		result[slot]={slot=slot,resource=w.resource,tier=w.tier,ready=workerReady(w),interval=150-w.tier*30,capacity=60+w.tier*60}
	end
	return result
end
local function level(xp)
	return math.min(99,1+math.floor(math.sqrt(xp/40)))
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
local function applyStats(player,p)
	player:SetAttribute("SkyreachUnlocked",(p.questCompleted or 0)>=6)
	local fleet=workerFleet(p)
	for slot=1,3 do
		local worker=fleet[slot]
		player:SetAttribute("Worker"..slot.."Tier",if worker then worker.tier else 0)
		player:SetAttribute("Worker"..slot.."Resource",if worker then worker.resource else "Ore")
	end
	local health=100+(level(p.xp.Combat)-1)*5+(level(p.xp.Farming)-1)*2+(p.companionBond or 0)*2
	player:SetAttribute("CompanionBond",p.companionBond or 0)
	local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth~=health then
		local increase=math.max(0,health-humanoid.MaxHealth)
		humanoid.MaxHealth=health
		if humanoid.Health>0 then humanoid.Health=math.min(health,humanoid.Health+increase) end
	end
	local armorDefense=if (p.items.Skyplate or 0)>0 then 2 else 0
	local defense=math.min(5,math.floor((level(p.xp.Mining)-1)/3))+armorDefense
	player:SetAttribute("SkillDefense",defense)
	local enchantDamage=(p.enchantRank or 0)*3
	player:SetAttribute("EnchantDamage",enchantDamage)
	return {maxHealth=health,defense=defense,armorDefense=armorDefense,enchantDamage=enchantDamage}
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
local function regionAllowed(p,region)
	return region=="Skyreach" and (p.questCompleted or 0)>=6
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
	return {xp=p.xp,items=p.items,consumables=provisions,collection=p.collection,coins=p.coins,bank=p.bank,bankRevision=p.bankRevision or 0,worker=p.worker,
		ironman=p.ironman,levels=levels,enchantRank=p.enchantRank or 0,workerResource=p.workerResource or "Ore",workerReady=ready(p),workers=workerState(p),message=message or "",kills=p.kills,
		companionBond=p.companionBond or 0,market=marketViews[player],recipes=recipeState(p),regions=regionState(p),stats=applyStats(player,p),quest=questState(p),slayer=slayerState(p),started=p.started,decorations=p.decorations,preview=preview[player]==true}
end
local function collect(p,item,count)
	p.items[item]=(p.items[item] or 0)+count
	p.collection[item]=(p.collection[item] or 0)+count
end
local function spend(p,cost)
	for item,n in pairs(cost) do
		if (p.items[item] or 0)<n then return false end
	end
	for item,n in pairs(cost) do p.items[item]-=n end
	return true
end
local function claimWorker(p,slot)
	slot=slot or 1
	local w=workerFleet(p)[slot]
	if not w then return 0,"Ore" end
	local count=workerReady(w)
	local resource=w.resource
	if count>0 then
		local interval=150-w.tier*30
		w.lastClaim=os.time()-((os.time()-w.lastClaim)%interval)
		collect(p,resource,count)
		p.xp[resources[resource]]+=count*3
	end
	if slot==1 then p.lastClaim=w.lastClaim; p.workerResource=resource end
	return count,resource
end
local function persist(player,release)
	if preview[player] or not profiles[player] then return true end
	while saving[player] do task.wait(0.1) end
	local p=profiles[player]
	if not p then return true end
	saving[player]=true
	local payload=table.clone(p)
	for _,k in ipairs({"items","xp","collection","decorations"}) do payload[k]=table.clone(p[k]) end
	payload.workers={}
	for slot,w in ipairs(workerFleet(p)) do payload.workers[slot]=table.clone(w) end
	local owned=false
	local committed
	local ok=pcall(function()
		committed=store:UpdateAsync("p"..player.UserId,function(old)
			owned=old~=nil and old.owner==uid
			if not owned then return nil end
			return {owner=if release then "" else uid, expires=os.time()+180,profile=payload}
		end)
	end)
	saving[player]=nil
	owned=owned and committed~=nil and committed.owner==(if release then "" else uid)
	if ok and owned then leaseEnd[player]=committed.expires end
	if not release and ok and not owned and player.Parent then player:Kick("Your journal opened in another server. Please rejoin.") end
	return ok and owned and (release or committed.expires>os.time())
end
local function open(player)
	local profile,conflict
	local committed
	local ok=pcall(function()
		committed=store:UpdateAsync("p"..player.UserId,function(old)
			if old and old.owner~="" and old.owner~=uid and old.expires>os.time() then
				conflict=true
				return nil
			end
			profile=old and old.profile or fresh()
			return {owner=uid,expires=os.time()+180,profile=profile}
		end)
	end)
	if ok and (not committed or committed.owner~=uid) then conflict=true end
	if conflict or (not ok and not RunService:IsStudio()) then
		player:Kick("Your journal is busy. Please rejoin in a moment.")
		return
	end
	if not ok then profile=fresh(); preview[player]=true else profile=committed.profile end
	profile.decorations=profile.decorations or {}
	workerFleet(profile)
	for skill in pairs(fresh().xp) do
		if profile.xp[skill]==nil then profile.xp[skill]=0 end
	end
	profiles[player]=profile
	for name in pairs(decorations) do player:SetAttribute("Home"..name,profile.decorations[name]==true) end
	leaseEnd[player]=if preview[player] then os.time()+180 else committed.expires
	if not player.Parent then persist(player,true); profiles[player]=nil; return end
	local function spawnCharacter(character)
		local humanoid=character:WaitForChild("Humanoid",10)
		if not humanoid then return end
		applyStats(player,profile)
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
	if profile.pending or profile.pricedPending then task.defer(function() if resumeExchange then resumeExchange(player) end end) end
	player.CharacterAdded:Connect(spawnCharacter)
	if player.Character then task.spawn(spawnCharacter,player.Character) end
	update:FireClient(player,snapshot(player,if preview[player] then "Studio practice session • saving unavailable" else "Journal opened"))
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
	if region and not regionAllowed(p,region) then return "Claim the Skyreach charter in your journal before entering this region." end
	if verb=="market" or verb=="list" or verb=="buy" or verb=="proceeds" or verb=="cancel" then
		return exchangeAction(player,verb,item or "Ore")
	elseif verb=="gather" and prompt and gatheringSkills[item] then
		local skill=gatheringSkills[item]
		if item=="Aetherite" and level(p.xp.Mining)<3 then return "Aetherite requires Mining 3. Train on Ore in Quarry Cay." end
		local reinforced=(p.items.ReinforcedPickaxe or 0)>0
		local amount=1+(if item~="Aetherite" and level(p.xp[skill])>=3 then 1 else 0)
		if item=="Ore" then amount+=if reinforced then 2 elseif (p.items.Pickaxe or 0)>0 then 1 else 0 end
		if item=="Aetherite" and reinforced then amount+=1 end
		if item=="Aetherite" and region=="Skyreach" then amount+=1 end
		if workspace:GetAttribute("FestivalResource")==item then amount+=1 end
		collect(p,item,amount)
		local experience=if item=="Aetherite" then 18 else 12
		p.xp[skill]+=experience
		p.started=true
		return "+"..amount.." "..item.."   ·   +"..experience.." "..skill.." XP"
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
		p.xp.Combat+=hunt.xp
		return "Hunt complete • +"..hunt.coins.." coins and +"..hunt.xp.." Combat XP."
	elseif verb=="quest" then
		local state=questState(p)
		if not state.ready then return "Complete the current guild contract first." end
		local quest=quests[state.stage]
		p.questCompleted=state.stage
		p.started=true
		p.coins+=quest.coins or 0
		p.xp.Smithing+=quest.xp or 0
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
		p.xp.Taming+=20
		p.started=true
		return "Tidewing bond "..p.companionBond.."/5 • +20 Taming XP and +2 maximum health."
	elseif verb=="enchant" then
		if (p.items.Blade or 0)<1 and (p.items.Stormblade or 0)<1 then return "Craft a Blade before enchanting." end
		if (p.enchantRank or 0)>=3 then return "Your weapon enchantment is at maximum rank." end
		if not spend(p,{Shard=2,Herb=4}) then return "Each enchantment needs 2 Shard and 4 Herb." end
		p.enchantRank=(p.enchantRank or 0)+1
		p.xp.Enchanting+=30
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
		p.xp[skill]+=experience
		p.started=true
		return item.." crafted   ·   +"..experience.." "..skill.." XP"
	elseif verb=="workerResource" or verb=="workerAssign" then
		local slot,resource=1,item
		if verb=="workerAssign" then
			local raw,name=string.match(item or "","^([1-3]):(%a+)$")
			slot,resource=tonumber(raw),name
		end
		local w=slot and workerFleet(p)[slot]
		if not w then return "Build this worker first." end
		if not resources[resource] then return "Choose Ore, Timber, Herb or Fish." end
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
		if w.tier>=3 then return "Worker is at maximum tier." end
		local tier=w.tier+1
		if not spend(p,{Timber=5*tier,Ore=3*tier}) then return "Upgrade needs "..(5*tier).." Timber and "..(3*tier).." Ore." end
		claimWorker(p,slot)
		w.tier=tier
		w.lastClaim=os.time()
		if slot==1 then p.lastClaim=w.lastClaim end
		return "Worker "..slot.." upgraded to tier "..tier..". Completed output collected; new cycle started."
	elseif verb=="claim" or verb=="workerClaim" then
		local slot=if verb=="claim" then 1 else tonumber(item)
		if not slot or not workerFleet(p)[slot] then return "Build this worker first." end
		local n,resource=claimWorker(p,slot)
		if n<1 then return "Next resource is still being gathered." end
		return "Collected "..n.." worker "..resource.." • +"..(n*3).." "..resources[resource].." XP."
	elseif verb=="sell" then
		local total=0
		for raw,price in pairs(prices) do
			if not item or raw==item then total+=(p.items[raw] or 0)*price; p.items[raw]=0 end
		end
		p.coins+=total
		return "Merchant paid "..total.." coins."
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
		item=item or "Tonic"
		local provision=consumables[item]
		if not provision then return "Choose a Tonic or ExpeditionRation." end
		if humanoid.Health>=humanoid.MaxHealth then return "Already at full health." end
		if item=="ExpeditionRation" and os.time()<(p.rationReadyAt or 0) then return "Wait "..(p.rationReadyAt-os.time()).." seconds before another ration." end
		if not spend(p,{[item]=1}) then return "Craft "..item.." in the Forge first." end
		if item=="ExpeditionRation" then p.rationReadyAt=os.time()+provision.recovery end
		humanoid.Health=math.min(humanoid.MaxHealth,humanoid.Health+provision.healing)
		return item.." restored up to "..provision.healing.." health."
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
		boss.hp-=8+level(p.xp.Combat)+(if (p.items.Blade or 0)>0 then 8 else 0)+(if (p.items.Stormblade or 0)>0 then 12 else 0)+(p.enchantRank or 0)*3
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
				q.xp.Combat+=40
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
	if type(verb)~="string" or (item~=nil and type(item)~="string") then return nil end
	if os.clock()<(lastRead[player] or 0) then return nil end
	lastRead[player]=os.clock()+0.08
	if verb=="state" then return snapshot(player) end
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
	while exchangeBusy[player] do task.wait(0.1) end
	for _=1,3 do if persist(player,true) then break end; task.wait(1) end
	profiles[player],cooldown[player],lastRead[player],preview[player],leaseEnd[player]=nil,nil,nil,nil,nil
	marketViews[player],marketReads[player]=nil,nil
	for _,arena in pairs(enemies) do
		arena[player.UserId]=nil
		for _,boss in pairs(arena) do boss.hits[player]=nil end
	end
end
Players.PlayerRemoving:Connect(close)
task.spawn(function()
	while task.wait(55) do for player in pairs(profiles) do task.spawn(persist,player,false) end end
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
expedition.Event:Connect(function(player)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return end
	p.started=true
	p.xp.Combat+=80
	p.xp.Dungeoneering+=60
	p.coins+=35
	collect(p,"Stormglass",1)
	update:FireClient(player,snapshot(player,"Expedition cleared • Stormglass, 35 coins, 80 Combat and 60 Dungeoneering XP"))
end)
expedition.Parent=game:GetService("ServerStorage")

-- World transit uses the same authoritative unlock as region resource prompts.
local regionAccess=Instance.new("BindableFunction")
regionAccess.Name="IsleRegionAccess"
regionAccess.OnInvoke=function(player,region)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return {allowed=false,message="Waiting for journal sync."} end
	local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health<=0 then return {allowed=false,message="Return to your island first."} end
	local allowed=regionAllowed(p,region)
	return {allowed=allowed,message=if allowed then "Skyreach charter accepted." else "Claim the Skyreach charter in your journal: Mining 3 and 3 lifetime Alloy Ingots."}
end
regionAccess.Parent=game:GetService("ServerStorage")

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
coopProfile.Parent=game:GetService("ServerStorage")


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
exchangeAction=function(player,verb,item)
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
	if not p.pending and not p.pricedPending then
		if verb=="list" and not spend(p,{[item]=3}) then return "A market lot needs 3 "..item.."." end
		if verb=="buy" then
			if p.coins<price then return "You need "..price.." purse coins to reserve this buy limit." end
			p.coins-=price
		end
		p.started=true
		p.pricedSeq=(p.pricedSeq or 0)+1
		p.pricedPending={seq=p.pricedSeq,verb=verb,item=item,price=price,protocol=2}
	end
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
		local message=exchangeAction(player,order.verb,order.item)
		if player.Parent then update:FireClient(player,snapshot(player,message)) end
		if (p.pricedPending or p.pending)==order then break end
	end
end






