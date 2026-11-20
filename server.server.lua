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
local applySigilRefund -- Endgame: unspent altar sigils owed to a journal (defined in the Endgame block)
local marketViews,marketReads={},{}
-- Economy (Bazaar orders + Auction House); defined with the market at the end of this file.
local Econ={views={},reads={}}
local profiles, cooldown, lastRead, saving, preview, leaseEnd = {}, {}, {}, {}, {}, {}
local stateRead, exchangeReady, sessionOwner, opening = {}, {}, {}, {}
-- Unfinished sessions per UserId on this server (opening, live or closing).
local userSessions = {}
-- Instance-keyed state tables are STRONG: Roblox may collect an Instance's Lua
-- wrapper while the Instance lives, which silently empties weak-keyed entries
-- (lost traps, skipped regrowth). Prompt-keyed entries are cleared by
-- watchPrompt when the prompt is destroyed or leaves the DataModel; player-keyed
-- entries are cleared by forget()/close() when the player leaves.
local enemies = {}
-- Per-player resource node depletion: [prompt] = {[player] = os.clock() ready time}.
local nodeRegrowth = {}
local promptGoneHooks, watchedPrompts = {}, {}
local function promptGone(prompt)
	local conns=watchedPrompts[prompt]
	if not conns then return end
	watchedPrompts[prompt]=nil
	for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	nodeRegrowth[prompt],enemies[prompt]=nil,nil
	for _,hook in ipairs(promptGoneHooks) do hook(prompt) end
end
local function watchPrompt(prompt)
	if watchedPrompts[prompt] or typeof(prompt)~="Instance" then return end
	local conns={}
	watchedPrompts[prompt]=conns
	pcall(function()
		table.insert(conns,prompt.Destroying:Connect(function() promptGone(prompt) end))
		table.insert(conns,prompt.AncestryChanged:Connect(function()
			if not prompt:IsDescendantOf(game) then promptGone(prompt) end
		end))
	end)
end
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
local gearSlots={weapon=true,helmet=true,chest=true,legs=true,boots=true,ammo=true} -- ammo: the Quiver (Combat styles)
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
-- One DataStore request budget per player for every market/economy call (quotes,
-- browses, claim checks and order writes, legacy exchange included): MARKET_RATE
-- tokens per second (6 requests/min sustained) with a small burst. An order costs
-- two requests (journal save + shared key), a read one. Keyed by UserId so a
-- rejoin cannot refill it. Reads go through a per-server cache shared by every
-- player (BROWSE_TTL seconds), refreshed by this server's own committed writes.
local MARKET_RATE, MARKET_BURST, BROWSE_TTL = 0.1, 6, 10
local marketBudget, browseCache = {}, {}
local function spendMarketBudget(player, cost)
	if preview[player] then return true end
	local now = os.clock()
	local bucket = marketBudget[player.UserId]
	if not bucket then bucket = {tokens = MARKET_BURST, at = now}; marketBudget[player.UserId] = bucket end
	bucket.tokens = math.min(MARKET_BURST, bucket.tokens + (now - bucket.at) * MARKET_RATE)
	bucket.at = now
	if bucket.tokens < cost then return false, math.max(1, math.ceil((cost - bucket.tokens) / MARKET_RATE)) end
	bucket.tokens -= cost
	return true
end
local function marketBusy(wait) return "Market busy — try again in "..wait.."s." end
-- Returns ok, book | ok=false, message. Fresh cache entries cost nothing.
local function cachedBook(player, key)
	local entry = browseCache[key]
	if entry and os.clock() - entry.at < BROWSE_TTL then return true, deepCopy(entry.book) end
	local allowed, wait = spendMarketBudget(player, 1)
	if not allowed then return false, marketBusy(wait) end
	local ok, book = pcall(function() return store:GetAsync(key) end)
	if not ok then return false, nil end
	browseCache[key] = {book = deepCopy(book), at = os.clock()}
	return true, book
end
local function rememberBook(key, book)
	browseCache[key] = {book = deepCopy(book), at = os.clock()}
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
-- Skill Mastery (perk trees, capstones, mantles); filled in by the Mastery block before perform().
local Mastery={verbs={}}
-- Verdant Garden (plots, composter, visitors); filled in by the Garden block before perform().
local Garden={verbs={}}
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
		if Mastery.tokenNote then Mastery.tokenNote(p,claimed,tier) end
	end
end
local function spend(p,cost)
	for item,n in pairs(cost) do
		if (p.items[item] or 0)<n then return false end
	end
	for item,n in pairs(cost) do p.items[item]-=n end
	return true
end
-- Gear depth (Data.Gear): Reforge Anvil, reforge stones, essence stars and tomes.
-- Items are stackable counts per id, so upgrades are bound to the item id like
-- enchants: p.reforges[id]=reforgeId, p.stars[id]=1..5, p.books[id]={tempering,masterwork}.
-- Equipped and bagged items may be upgraded; Ironman journals use every verb.
local Gear={verbs={}}
do
	local G=Data.Gear
	local function owned(p,item)
		local def=validId(item) and Data.Items[item]
		local category=def and G.category(def)
		if not category then return nil,"Choose a weapon, armor piece, tool or accessory to upgrade." end
		if (p.items[item] or 0)<1 then return nil,"You do not own "..def.name.."." end
		return def,category
	end
	local function split(item)
		if not validId(item) then return nil end
		return string.match(item,"^(%w+):(%w+)$")
	end
	-- reforge "itemId": random reforge for coins (never the current one).
	function Gear.verbs.reforge(p,item)
		local def,category=owned(p,item)
		if not def then return category end
		local cost=G.reforgeCost(p,item)
		if p.coins<cost then return "Reforging "..def.name.." costs "..cost.." coins." end
		local before=G.reforgeOf(p,item)
		local after=G.rollReforge(def,before,roll())
		if not after then return def.name.." cannot be reforged." end
		p.coins-=cost
		p.reforges[item]=after
		p.started=true
		return "Reforged "..def.name..": "..(if before then G.Reforges[before].name.." → " else "")..G.Reforges[after].name.." • -"..cost.." coins."
	end
	-- reforgeStone "itemId:stoneId": a specific reforge, consuming the stone plus the anvil fee.
	function Gear.verbs.reforgeStone(p,item)
		local target,stoneId=split(item)
		if not target then return "Choose an item and a reforge stone." end
		local def,category=owned(p,target)
		if not def then return category end
		local stone=Data.Items[stoneId]
		local reforgeId=stone and stone.reforgeStone
		if not reforgeId then return "Choose a reforge stone." end
		local reforge=G.Reforges[reforgeId]
		if (p.items[stoneId] or 0)<1 then return "You have no "..stone.name.."." end
		if not G.reforgeFits(reforgeId,def) then return reforge.name.." cannot be applied to "..def.name.."." end
		if G.reforgeOf(p,target)==reforgeId then return def.name.." is already "..reforge.name.."." end
		local cost=G.reforgeCost(p,target)
		if p.coins<cost then return "Applying "..stone.name.." costs "..cost.." coins." end
		spend(p,{[stoneId]=1})
		p.coins-=cost
		p.reforges[target]=reforgeId
		p.started=true
		return def.name.." reforged "..reforge.name.." with "..stone.name.." • -"..cost.." coins."
	end
	-- star "itemId": next star for essence + coins (weapons, armor and tools).
	function Gear.verbs.star(p,item)
		local def,category=owned(p,item)
		if not def then return category end
		if not G.canStar(category) then return "Accessories cannot be starred." end
		local stars=G.starsOf(p,item)
		if stars>=G.STAR_MAX then return def.name.." already has "..G.STAR_MAX.." stars." end
		local cost=G.starCost(def,stars+1)
		local essence=Data.Items[cost.essence]
		if (p.items[cost.essence] or 0)<cost.amount then return "Star "..(stars+1).." needs "..cost.amount.." "..essence.name.."." end
		if p.coins<cost.coins then return "Star "..(stars+1).." costs "..cost.coins.." coins." end
		spend(p,{[cost.essence]=cost.amount})
		p.coins-=cost.coins
		p.stars[item]=stars+1
		p.started=true
		return def.name.." starred "..string.rep("★",stars+1).." • -"..cost.amount.." "..essence.name..", -"..cost.coins.." coins."
	end
	-- tome "itemId:tomeId": Tempering (stacking, weapons/armor) or Masterwork (rarity +1, once).
	function Gear.verbs.tome(p,item)
		local target,tomeId=split(item)
		if not target then return "Choose an item and a tome." end
		local def,category=owned(p,target)
		if not def then return category end
		if not G.Tomes[tomeId] then return "Choose a Tempering Tome or a Masterwork Tome." end
		if (p.items[tomeId] or 0)<1 then return "You have no "..Data.Items[tomeId].name.."." end
		local book=G.bookOf(p,target)
		local message
		if tomeId=="TemperingTome" then
			if not G.canTemper(category) then return "Tempering Tomes apply to weapons and armor." end
			if book.tempering>=G.TEMPERING_MAX then return def.name.." already holds "..G.TEMPERING_MAX.." Tempering Tomes." end
			book.tempering+=1
			message=def.name.." tempered ("..book.tempering.."/"..G.TEMPERING_MAX..")."
		else
			if book.masterwork then return def.name.." is already a masterwork." end
			if def.rarity==Data.RarityOrder[#Data.RarityOrder] then return def.name.." is already "..def.rarity.."." end
			book.masterwork=true
			message=def.name.." is now a "..G.bumpRarity(def.rarity).." masterwork."
		end
		spend(p,{[tomeId]=1})
		p.books[target]={tempering=book.tempering,masterwork=book.masterwork or nil}
		p.started=true
		return message
	end
	-- Older saves gain empty tables; unknown items, reforges that no longer fit,
	-- and out-of-range counts are dropped or clamped.
	function Gear.migrate(profile)
		for _,key in ipairs({"reforges","stars","books"}) do
			if type(profile[key])~="table" then profile[key]={} end
		end
		for id,r in pairs(profile.reforges) do
			if not (type(id)=="string" and Data.Items[id] and type(r)=="string" and G.reforgeFits(r,Data.Items[id])) then profile.reforges[id]=nil end
		end
		for id,n in pairs(profile.stars) do
			local def=type(id)=="string" and Data.Items[id]
			local v=tonumber(n)
			if not def or not G.canStar(G.category(def)) or not v or v~=v or v<1 then profile.stars[id]=nil
			else profile.stars[id]=math.clamp(math.floor(v),1,G.STAR_MAX) end
		end
		for id,b in pairs(profile.books) do
			local def=type(id)=="string" and Data.Items[id]
			if not def or not G.category(def) or type(b)~="table" then profile.books[id]=nil
			else
				local book=G.bookOf(profile,id)
				if not G.canTemper(G.category(def)) then book.tempering=0 end
				if book.tempering==0 and not book.masterwork then profile.books[id]=nil
				else profile.books[id]={tempering=book.tempering,masterwork=book.masterwork or nil} end
			end
		end
	end
	function Gear.view(p) return {reforges=p.reforges,stars=p.stars,books=p.books} end
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
-- Construction and quest perks (p.perkWorkerHaste) shorten every worker cycle.
local function workerInterval(p,w)
	local haste=math.clamp(tonumber(p and p.perkWorkerHaste) or 0,0,Data.MAX_WORKER_HASTE)
	return math.max(1,math.floor(workerConfig(w).interval*(1-haste)+0.5))
end
local function workerReady(w,p)
	if not w then return 0 end
	local config=workerConfig(w)
	return math.clamp(math.floor((os.time()-w.lastClaim)/workerInterval(p,w)),0,config.capacity)
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
local function ready(p) return workerReady(workerFleet(p)[1],p) end
local function workerState(p)
	local result={}
	for slot,w in ipairs(workerFleet(p)) do
		local config=workerConfig(w)
		result[slot]={slot=slot,resource=w.resource,tier=w.tier,ready=workerReady(w,p),interval=workerInterval(p,w),capacity=config.capacity,maxTier=#Data.WorkerTiers}
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
	-- Endgame: quest-gated regions (the Shattered Crown needs Crown of the Tempest).
	for _,id in ipairs(requires.questsDone or {}) do
		if not (type(p.questsDone)=="table" and p.questsDone[id]) then return false end
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
	for _,id in ipairs(requires.questsDone or {}) do
		local q=Data.QuestById[id]
		table.insert(parts,"the quest "..(q and q.title or id))
	end
	return table.concat(parts,", ")
end
local function regionDenied(region)
	if region=="Skyreach" then return "Claim the Skyreach charter in your journal before entering this region." end
	local def=type(region)=="string" and Data.RegionById[region]
	if not def then return "That region is not on the guild charts." end
	return def.name.." requires "..regionRequirement(def).."."
end
------------------------------------------------------------------------------
-- Quests, achievement diaries and Carpentry construction (Quests team).
-- Every check reads profile state server-side (Data.describeCheck kinds).
-- Stat perks go to p.perkStats under "quest:", "diary:" and "furniture:" keys
-- (Progression.computeStats adds them); non-stat perks are p.perkAccessorySlots
-- and p.perkWorkerHaste. All three are rebuilt from the source records by
-- Journal.refresh, so they can never drift from what the player has earned.
------------------------------------------------------------------------------
local Journal={}
do
	local tierIndex={}
	for i,name in ipairs(Data.DiaryTiers) do tierIndex[name]=i end
	local perkPrefixes={"quest:","diary:","furniture:"}
	-- Accessory slots from perks: until Progression.accessorySlots reads
	-- p.perkAccessorySlots itself (lead sets Progression.perkSlotsIntegrated),
	-- the server extends it here so the bag verb and active accessories agree.
	if not Progression.perkSlotsIntegrated then
		local baseSlots=Progression.accessorySlots
		Progression.perkSlotsIntegrated=true
		Progression.accessorySlots=function(p)
			local bonus=math.clamp(math.floor(tonumber(p and p.perkAccessorySlots) or 0),0,Data.MAX_PERK_SLOTS)
			return math.min(Data.AccessoryBag.maxSlots+Data.MAX_PERK_SLOTS,baseSlots(p)+bonus)
		end
	end
	function Journal.counters(p)
		local c=p.counters
		if type(c)~="table" then c={} p.counters=c end
		for _,key in ipairs({"gathers","crafts","built"}) do
			if type(c[key])~="table" then c[key]={} end
		end
		return c
	end
	function Journal.count(p,bucket,key,n)
		local list=Journal.counters(p)[bucket]
		list[key]=(list[key] or 0)+n
	end
	function Journal.questPoints(p)
		local total=(p.questCompleted or 0)*Data.CONTRACT_QUEST_POINTS
		for id in pairs(p.questsDone or {}) do
			local q=Data.QuestById[id]
			if q then total+=q.rewards.points or 0 end
		end
		return total
	end
	-- Returns have, need for one check.
	function Journal.measure(p,o)
		local kind=o.kind
		if kind=="contracts" then return p.questCompleted or 0,o.count
		elseif kind=="quest" then return if p.questsDone[o.quest] then 1 else 0,1
		elseif kind=="questPoints" then return Journal.questPoints(p),o.count
		elseif kind=="level" then return level(p.xp[o.skill]),o.level
		elseif kind=="collect" then return p.collection[o.item] or 0,o.count
		elseif kind=="collectionTier" then return Progression.collectionTier(p,o.item),o.tier
		elseif kind=="have" then return p.items[o.item] or 0,o.count
		elseif kind=="kills" then return p.bestiary[o.monster] or 0,o.count
		elseif kind=="craft" then return Journal.counters(p).crafts[o.item] or 0,o.count
		elseif kind=="gather" then return Journal.counters(p).gathers[o.region] or 0,o.count
		elseif kind=="build" then return if (Journal.counters(p).built[o.furniture] or 0)>0 then 1 else 0,1
		elseif kind=="slayer" then return Progression.slayerLevel(p.slayerXp[o.line] or 0),o.level
		elseif kind=="flag" then return if p[o.flag]==true then 1 else 0,1
		end
		return 0,1
	end
	function Journal.met(p,list)
		for _,o in ipairs(list) do
			local have,need=Journal.measure(p,o)
			if have<need then return false,o end
		end
		return true
	end
	function Journal.progress(p,list)
		local out={}
		for i,o in ipairs(list) do
			local have,need=Journal.measure(p,o)
			out[i]={math.min(have,need),need}
		end
		return out
	end
	function Journal.shortcuts(p)
		local out={}
		for id in pairs(p.questsDone) do
			local q=Data.QuestById[id]
			local region=q and q.rewards.unlock and q.rewards.unlock.shortcut
			if region then out[region]=true end
		end
		return out
	end
	-- Regions the home portal can be attuned to (needs portal furniture).
	function Journal.portalRegions(p)
		local f=Data.Furniture[p.furniture.Portal or ""]
		if not f then return {} end
		local shortcuts=Journal.shortcuts(p)
		local out={}
		for _,region in ipairs(Data.PortalRegions) do
			if shortcuts[region] or table.find(f.effect.portal,region) then table.insert(out,region) end
		end
		return out
	end
	function Journal.refresh(p)
		local perks=if type(p.perkStats)=="table" then p.perkStats else {}
		p.perkStats=perks
		for key in pairs(perks) do
			for _,prefix in ipairs(perkPrefixes) do
				if type(key)=="string" and string.sub(key,1,#prefix)==prefix then perks[key]=nil end
			end
		end
		local slots,haste=0,0
		for id in pairs(p.questsDone) do
			local q=Data.QuestById[id]
			if q.rewards.perk then perks["quest:"..id]=table.clone(q.rewards.perk) end
			local unlock=q.rewards.unlock
			if unlock then slots+=unlock.accessorySlots or 0; haste+=unlock.workerHaste or 0 end
		end
		for region,claimed in pairs(p.diaries) do
			local diary=Data.DiaryByRegion[region]
			for i=1,claimed do
				local tier=Data.DiaryTiers[i]
				perks["diary:"..region..":"..tier]=table.clone(diary.tiers[tier].perk)
			end
		end
		for hotspot,id in pairs(p.furniture) do
			local effect=Data.Furniture[id].effect
			if effect.perk then perks["furniture:"..hotspot]=table.clone(effect.perk) end
			slots+=effect.accessorySlots or 0
			haste+=effect.workerHaste or 0
		end
		p.perkAccessorySlots=math.min(Data.MAX_PERK_SLOTS,slots)
		p.perkWorkerHaste=math.min(Data.MAX_WORKER_HASTE,haste)
	end
	-- Older saves and tampered records: keep only known quests, tiers, furniture.
	function Journal.migrate(p)
		local done={}
		if type(p.questsDone)=="table" then
			for id,v in pairs(p.questsDone) do if v==true and Data.QuestById[id] then done[id]=true end end
		end
		p.questsDone=done
		local diaries={}
		if type(p.diaries)=="table" then
			for region,v in pairs(p.diaries) do
				local n=tonumber(v)
				if Data.DiaryByRegion[region] and n and n==n then
					n=math.clamp(math.floor(n),0,#Data.DiaryTiers)
					if n>0 then diaries[region]=n end
				end
			end
		end
		p.diaries=diaries
		local furniture={}
		if type(p.furniture)=="table" then
			for hotspot,id in pairs(p.furniture) do
				local f=type(id)=="string" and Data.Furniture[id]
				if f and f.hotspot==hotspot then furniture[hotspot]=id end
			end
		end
		p.furniture=furniture
		local counters=Journal.counters(p)
		for _,bucket in pairs({counters.gathers,counters.crafts,counters.built}) do
			for key,v in pairs(bucket) do
				local n=tonumber(v)
				bucket[key]=if type(key)=="string" and n and n==n and n>0 then math.floor(math.min(n,1e9)) else nil
			end
		end
		if p.homePortal~=nil and not table.find(Journal.portalRegions(p),p.homePortal) then p.homePortal=nil end
		Journal.refresh(p)
		Journal.isle.migrate(p)
	end
	-- World reads these attributes to render furniture and the home portal.
	function Journal.apply(player,p)
		for _,h in ipairs(Data.Hotspots) do player:SetAttribute("Furniture"..h.id,p.furniture[h.id] or "") end
		player:SetAttribute("HomePortal",p.homePortal or "")
		Journal.isle.apply(player,p)
	end
	local function addItems(p,items)
		for id,n in pairs(items or {}) do p.items[id]=(p.items[id] or 0)+n end
	end
	function Journal.claimQuest(p,item)
		local id,skill=string.match(item,"^(%w+):(%w+)$")
		id=id or string.match(item,"^%w+$")
		local q=id and Data.QuestById[id]
		if not q then return "That quest is not in your journal." end
		if p.questsDone[id] then return q.title.." is already complete." end
		local ok,missing=Journal.met(p,q.requires)
		if not ok then return q.title.." requires: "..Data.describeCheck(missing).."." end
		ok,missing=Journal.met(p,q.objectives)
		if not ok then return q.title.." • still to do: "..Data.describeCheck(missing).."." end
		local lamp=q.rewards.lamp
		if lamp then
			if not skill then return "Choose a skill for the "..lamp.xp.." XP lamp." end
			if not Data.Skills[skill] or (lamp.skills and not table.find(lamp.skills,skill)) then return "This lamp cannot train "..skill.."." end
			-- Gated skills (floor clears, hotspot builds) never take open-ended lamp XP,
			-- whatever the data says, unless a lamp lists them explicitly.
			if not lamp.skills and (skill=="Dungeoneering" or skill=="Carpentry" or (lamp.exclude and table.find(lamp.exclude,skill))) then
				return "This lamp cannot train "..skill..": earn it through its own activity."
			end
		elseif skill then
			return q.title.." has no XP lamp to rub."
		end
		local handIn={}
		for _,o in ipairs(q.objectives) do
			if o.kind=="have" and o.consume then handIn[o.item]=(handIn[o.item] or 0)+o.count end
		end
		if not spend(p,handIn) then return "Bring the items listed in "..q.title.."." end
		local r=q.rewards
		p.questsDone[id]=true
		p.started=true
		p.coins+=r.coins or 0
		addItems(p,r.items)
		for xpSkill,amount in pairs(r.xp or {}) do grantXp(p,xpSkill,amount) end
		if lamp then grantXp(p,skill,lamp.xp) end
		Journal.refresh(p)
		local parts={"Quest complete • "..q.title,"+"..(r.points or 0).." Quest Points"}
		if r.coins then table.insert(parts,"+"..r.coins.." coins") end
		if lamp then table.insert(parts,"+"..lamp.xp.." "..skill.." XP") end
		if r.unlock and r.unlock.shortcut then table.insert(parts,"portal attunement: "..Data.RegionById[r.unlock.shortcut].name) end
		return table.concat(parts,"   ·   ")
	end
	function Journal.claimDiary(p,item)
		local region,tier=string.match(item or "","^(%a+):(%a+)$")
		local diary=region and Data.DiaryByRegion[region]
		local index=tier and tierIndex[tier]
		if not diary or not index then return "Choose a diary region and tier." end
		local claimed=p.diaries[region] or 0
		if index<=claimed then return diary.name.." "..tier.." is already claimed." end
		if index>claimed+1 then return "Claim the "..Data.DiaryTiers[claimed+1].." tier of the "..diary.name.." first." end
		local ok,missing=Journal.met(p,diary.tiers[tier].tasks)
		if not ok then return diary.name.." "..tier.." • still to do: "..Data.describeCheck(missing).."." end
		p.diaries[region]=index
		p.started=true
		local coins=Data.DiaryCoins[tier]
		p.coins+=coins
		Journal.refresh(p)
		return diary.name.." "..tier.." complete • +"..coins.." coins and a permanent perk."
	end
	function Journal.build(player,p,item)
		local hotspot,id=string.match(item or "","^(%a+):(%w+)$")
		local h=hotspot and Data.HotspotById[hotspot]
		local f=id and Data.Furniture[id]
		if not h or not f then return "Choose a hotspot and a furniture plan." end
		if f.hotspot~=hotspot then return f.name.." does not fit the "..h.name.."." end
		local current=p.furniture[hotspot]
		if current then return "Remove the "..Data.Furniture[current].name.." from the "..h.name.." first." end
		local need=f.level
		if level(p.xp.Carpentry)<need then return f.name.." requires Carpentry "..need.."." end
		for material,n in pairs(f.costs) do
			if (p.items[material] or 0)<n then return f.name.." needs "..n.." "..Data.Items[material].name.."." end
		end
		spend(p,f.costs)
		p.furniture[hotspot]=id
		Journal.count(p,"built",id,1)
		grantXp(p,"Carpentry",f.xp)
		p.started=true
		Journal.refresh(p)
		Journal.apply(player,p)
		return f.name.." built on your terrace   ·   +"..f.xp.." Carpentry XP"
	end
	function Journal.remove(player,p,hotspot)
		local h=type(hotspot)=="string" and Data.HotspotById[hotspot]
		if not h then return "Choose a hotspot." end
		local id=p.furniture[hotspot]
		if not id then return "Nothing is built on the "..h.name.."." end
		local f=Data.Furniture[id]
		local refund={}
		for material,n in pairs(f.costs) do refund[material]=math.floor(n*Data.FurnitureRefund) end
		addItems(p,refund)
		p.furniture[hotspot]=nil
		if hotspot=="Portal" then p.homePortal=nil end
		Journal.refresh(p)
		Journal.apply(player,p)
		return f.name.." dismantled • half of its materials returned."
	end
	function Journal.attune(player,p,region)
		local def=type(region)=="string" and Data.RegionById[region]
		if not def or not table.find(Data.PortalRegions,region) then return "Choose a region for your home portal." end
		if not p.furniture.Portal then return "Build a Portal Frame on your terrace first." end
		if not table.find(Journal.portalRegions(p),region) then return "Your portal cannot reach "..def.name.." yet. Quests attune more isles." end
		if not regionAllowed(p,region) then return regionDenied(region) end
		if p.homePortal==region then return "Your portal already opens to "..def.name.."." end
		p.homePortal=region
		Journal.apply(player,p)
		return "Home portal attuned to "..def.name.."."
	end
	function Journal.state(p)
		local quests={}
		for i,q in ipairs(Data.Quests) do
			local done=p.questsDone[q.id]==true
			local available=done or Journal.met(p,q.requires)
			quests[i]={id=q.id,done=done,available=available==true,ready=not done and available==true and Journal.met(p,q.objectives)==true,
				requires=Journal.progress(p,q.requires),objectives=Journal.progress(p,q.objectives)}
		end
		local diaries={}
		for i,d in ipairs(Data.Diaries) do
			local claimed=p.diaries[d.region] or 0
			local tiers={}
			for t,name in ipairs(Data.DiaryTiers) do
				local tasks=d.tiers[name].tasks
				local complete=Journal.met(p,tasks)==true
				tiers[t]={tier=name,tasks=Journal.progress(p,tasks),complete=complete,claimed=t<=claimed,claimable=complete and t==claimed+1}
			end
			diaries[i]={region=d.region,claimed=claimed,tiers=tiers}
		end
		return {questPoints=Journal.questPoints(p),contracts=p.questCompleted or 0,quests=quests,diaries=diaries,
			construction={furniture=table.clone(p.furniture),portal=p.homePortal,portalRegions=Journal.portalRegions(p),
				carpentry=level(p.xp.Carpentry),accessorySlots=p.perkAccessorySlots or 0,workerHaste=p.perkWorkerHaste or 0,
				island=Journal.isle.state(p)}}
	end
end
------------------------------------------------------------------------------
-- Island placement (Island Builder team): free-form decor on the caller's own
-- home island (Data.Island grid rules). Every verb edits only the caller's
-- profile, so ownership is implicit; the world renders the replicated records
-- on that player's island only. p.island = {placed={"id:prop:x:z:rot"...},
-- paid={[propId]=copies already paid Carpentry XP}}. Pickup refunds 100% of
-- materials; XP is paid once per copy (paid is a high-water mark <= max).
------------------------------------------------------------------------------
do
	local I=Data.Island
	local Isle={budget={}} -- [player]; cleared in forget()
	Journal.isle=Isle
	function Isle.list(p)
		local out={}
		for _,record in ipairs(p.island.placed) do
			local e=I.parseRecord(record)
			if e then table.insert(out,e) end
		end
		return out
	end
	-- Keeps only well-formed, in-bounds, non-overlapping records within the caps.
	function Isle.migrate(p)
		local raw=if type(p.island)=="table" then p.island else {}
		local placed,paid,used,counts,occupied={},{},{},{},{}
		if type(raw.placed)=="table" then
			for _,record in ipairs(raw.placed) do
				if #placed>=I.MAX_PLACEMENTS then break end
				local e=I.parseRecord(record)
				if e and not used[e.id] and (counts[e.prop] or 0)<I.Props[e.prop].max and I.check(occupied,e.prop,e.x,e.z,e.rot) then
					used[e.id]=true
					counts[e.prop]=(counts[e.prop] or 0)+1
					for _,c in ipairs(I.cells(e.prop,e.x,e.z,e.rot)) do occupied[I.key(c[1],c[2])]=e.id end
					table.insert(placed,I.record(e))
				end
			end
		end
		if type(raw.paid)=="table" then
			for id,n in pairs(raw.paid) do
				local def=type(id)=="string" and I.Props[id]
				n=tonumber(n)
				if def and n and n==n and n>=1 then paid[id]=math.min(math.floor(n),def.max) end
			end
		end
		for id,n in pairs(counts) do paid[id]=math.max(paid[id] or 0,n) end
		p.island={placed=placed,paid=paid}
	end
	function Isle.apply(player,p)
		player:SetAttribute("IslandPlacements",table.concat(p.island.placed,";"))
	end
	-- Token bucket (Data.Island.RATE per second, BURST) on top of the verb cooldown.
	function Isle.allow(player)
		local now=os.clock()
		local b=Isle.budget[player]
		if not b then b={tokens=I.BURST,at=now}; Isle.budget[player]=b end
		b.tokens=math.min(I.BURST,b.tokens+(now-b.at)*I.RATE)
		b.at=now
		if b.tokens<1 then return false end
		b.tokens-=1
		return true
	end
	function Isle.place(player,p,item)
		if not Isle.allow(player) then return "Building too quickly. One moment…" end
		local propId,x,z,rot=I.parseRequest(item)
		local def=propId and I.Props[propId]
		if not def then return "Choose a prop and a spot on your island." end
		if level(p.xp.Carpentry)<def.level then return def.name.." requires Carpentry "..def.level.."." end
		local list=Isle.list(p)
		if #list>=I.MAX_PLACEMENTS then return "Your island holds at most "..I.MAX_PLACEMENTS.." placed props. Pick some up first." end
		local count=0
		local used={}
		for _,e in ipairs(list) do
			used[e.id]=true
			if e.prop==propId then count+=1 end
		end
		if count>=def.max then return "You have placed the most "..def.name.." pieces allowed ("..def.max..")." end
		local ok,why=I.check(I.occupancy(list),propId,x,z,rot)
		if not ok then return why end
		for material,n in pairs(def.costs) do
			if (p.items[material] or 0)<n then return def.name.." needs "..n.." "..Data.Items[material].name.."." end
		end
		spend(p,def.costs)
		local id=1
		while used[id] do id+=1 end
		table.insert(p.island.placed,I.record({id=id,prop=propId,x=x,z=z,rot=rot}))
		count+=1
		local text=def.name.." placed on your island"
		if count>(p.island.paid[propId] or 0) then
			p.island.paid[propId]=count
			grantXp(p,"Carpentry",def.xp)
			text..="   ·   +"..def.xp.." Carpentry XP"
		end
		p.started=true
		Isle.apply(player,p)
		return text
	end
	function Isle.pickup(player,p,item)
		if not Isle.allow(player) then return "Building too quickly. One moment…" end
		local id=type(item)=="string" and string.match(item,"^%d+$") and tonumber(item)
		if not id then return "Choose a placed prop to pick up." end
		for index,record in ipairs(p.island.placed) do
			local e=I.parseRecord(record)
			if e and e.id==id then
				local def=I.Props[e.prop]
				table.remove(p.island.placed,index)
				for material,n in pairs(def.costs) do
					local back=math.floor(n*I.REFUND)
					if back>0 then p.items[material]=(p.items[material] or 0)+back end
				end
				Isle.apply(player,p)
				return def.name.." picked up   ·   materials returned"
			end
		end
		return "That prop is no longer on your island."
	end
	function Isle.state(p)
		local list=Isle.list(p)
		local counts={}
		for _,e in ipairs(list) do counts[e.prop]=(counts[e.prop] or 0)+1 end
		local value=I.value(list)
		local tier,def=I.tier(value)
		-- Records themselves replicate through the IslandPlacements attribute.
		return {count=#list,cap=I.MAX_PLACEMENTS,counts=counts,
			paid=table.clone(p.island.paid),value=value,tier=tier,tierName=def.name}
	end
end
------------------------------------------------------------------------------
-- Agility & Hunter (New Skills team). Rules and data: Data.Agility,
-- Data.Hunter (shared/GameData.lua); world prompts: world.server.lua.
-- Agility: obstacle prompts (IsleAction "agility", IsleItem "<course>:<index>")
-- run in order (Data.Agility.step: order, a STEP_WINDOW after each landing,
-- no new obstacle while moving), the player must stand at the obstacle, and a
-- failure roll (risk fading with level, cut by Surefoot) drops them back to
-- the course start with damage. Success moves the character to AgilityEnd
-- (stepped PivotTo, root anchored) and pays obstacle XP; the last obstacle
-- pays the lap bonus, counts the lap, rolls a Skymark and the Gustling pet.
-- Shortcuts (IsleAction "shortcut", IsleItem "<id>:A|B") check Agility level
-- and the destination region, then move the player to ShortcutTo.
-- Hunter: trap prompts (IsleAction "trap") place one of the player's traps
-- (Data.Hunter.maxTraps by level, kit owned); traps roll every TICK seconds
-- (sweep loop, and lazily on use) and collapse after MAX_TICKS. Using your trap
-- collects a catch, reports progress, or (twice within DISMANTLE_WINDOW) picks
-- it up. Nets (IsleAction "net") roll immediately. Trap state is session-only.
-- Player attributes for clients: AgilityMove "<anim>:<seq>" ("" when done),
-- AgilityMoveTo (Vector3), AgilityMoveDuration (s), AgilityRun
-- "<course>:<next>:<total>" or "", AgilityRunExpires (os.time), HunterTraps
-- "<placed>/<max>", HunterTrapsCaught (n), SkillVendor + SkillVendorUntil.
-- Trap host parts get TrapState ("" | set | caught | collapsed) and TrapOwner (UserId, 0 = none).
------------------------------------------------------------------------------
-- All tables strong (see watchPrompt): player keys cleared by Skills.forget,
-- prompt keys by Skills.forgetPrompt. netReady = per-player miss cooldowns,
-- swarmReady = the shared post-catch swarm cooldown of each net spot.
local Skills={
	runs={},busyUntil={},moveSeq={},
	traps={},owned={},netReady={},swarmReady={},
	verbs={agility=true,shortcut=true,trap=true,net=true,skillVendor=true,skillBuy=true},
}
do
	local AG,HU=Data.Agility,Data.Hunter
	local function clean(map,valid,limit)
		local out={}
		if type(map)=="table" then
			for id,v in pairs(map) do
				local n=tonumber(v)
				if type(id)=="string" and valid[id] and n and n==n and n>0 then out[id]=math.min(n,limit) end
			end
		end
		return out
	end
	function Skills.refreshPerks(p)
		if type(p.perkStats)~="table" then p.perkStats={} end
		p.perkStats["agility:laps"]=(AG.lapPerk(p.agility and p.agility.laps))
		p.perkStats["hunter:log"]=(HU.logPerk(p.hunterLog))
	end
	-- Older saves gain empty records; tampered entries are dropped or clamped.
	function Skills.migrate(p)
		local ag=type(p.agility)=="table" and p.agility or {}
		local laps=clean(ag.laps,AG.CourseById,1e9)
		for id,n in pairs(laps) do laps[id]=math.floor(n) end
		local best=clean(ag.best,AG.CourseById,AG.MAX_LAP_SECONDS)
		for id,t in pairs(best) do if t>=AG.MAX_LAP_SECONDS then best[id]=nil end end
		p.agility={laps=laps,best=best}
		local log=clean(p.hunterLog,HU.CreatureById,1e9)
		for id,n in pairs(log) do log[id]=math.floor(n) end
		p.hunterLog=log
		Skills.refreshPerks(p)
	end
	-- Quest and diary checks: laps {course,count}, catches {creature,count}.
	local measure=Journal.measure
	function Journal.measure(p,o)
		if type(o)=="table" and o.kind=="laps" then return (p.agility and p.agility.laps[o.course]) or 0,o.count
		elseif type(o)=="table" and o.kind=="catches" then return (p.hunterLog and p.hunterLog[o.creature]) or 0,o.count end
		return measure(p,o)
	end
	local function itemsText(drops)
		local names={}
		for id,n in pairs(drops) do table.insert(names,"+"..n.." "..(Data.Items[id] and Data.Items[id].name or id)) end
		table.sort(names)
		return if #names>0 then " • "..table.concat(names,", ") else ""
	end
	local function costText(cost)
		local parts={}
		for id,n in pairs(cost) do table.insert(parts,if id=="coins" then n.." coins" else n.." "..Data.Items[id].name) end
		table.sort(parts)
		return table.concat(parts," + ")
	end
	local function rootOf(player)
		local character=player.Character
		return character and character:FindFirstChild("HumanoidRootPart"),character
	end

	-- Server-driven movement: stepped PivotTo from the current root to `to`
	-- (arc from Data.Agility.Kinds). A newer move cancels an older one.
	function Skills.move(player,to,duration,kind)
		local root,character=rootOf(player)
		if not root or typeof(to)~="Vector3" then return end
		local seq=(Skills.moveSeq[player] or 0)+1
		Skills.moveSeq[player]=seq
		local spec=AG.Kinds[kind]
		player:SetAttribute("AgilityMoveTo",to)
		player:SetAttribute("AgilityMoveDuration",duration)
		player:SetAttribute("AgilityMove",(if spec then spec.anim else kind)..":"..seq)
		local from=root.Position
		task.spawn(function()
			local steps=math.max(4,math.floor(duration/.1))
			local heading=Vector3.new(to.X-from.X,0,to.Z-from.Z)
			local look=if heading.Magnitude>.01 then heading.Unit else Vector3.new(0,0,-1)
			pcall(function() root.Anchored=true end)
			for i=1,steps do
				task.wait(duration/steps)
				if Skills.moveSeq[player]~=seq or not character.Parent then return end
				local t=i/steps
				local pos=from:Lerp(to,t)+Vector3.new(0,(spec and spec.arc or 0)*4*t*(1-t),0)
				character:PivotTo(CFrame.lookAt(pos,pos+look))
			end
			pcall(function() root.Anchored=false; root.AssemblyLinearVelocity=Vector3.zero end)
			player:SetAttribute("AgilityMove","")
		end)
	end
	function Skills.publishRun(player,run)
		local course=run and run.next>1 and AG.CourseById[run.course]
		if course then
			player:SetAttribute("AgilityRun",run.course..":"..run.next..":"..#course.obstacles)
			player:SetAttribute("AgilityRunExpires",os.time()+math.max(0,math.ceil(run.deadline-os.clock())))
		else
			player:SetAttribute("AgilityRun","")
			player:SetAttribute("AgilityRunExpires",0)
		end
	end
	function Skills.lap(p,course,lvl,seconds)
		grantXp(p,"Agility",course.lapXp)
		local laps=p.agility.laps
		laps[course.id]=(laps[course.id] or 0)+1
		local parts={"Lap "..laps[course.id].." of the "..course.name.." • +"..course.lapXp.." bonus XP"}
		local secs=math.floor(seconds*10+.5)/10
		local best=p.agility.best[course.id]
		if secs>0 and secs<AG.MAX_LAP_SECONDS and (not best or secs<best) then
			p.agility.best[course.id]=secs
			parts[1]..=" (best lap "..secs.."s)"
		end
		if roll()<AG.markChance(course,lvl) then
			collect(p,AG.MARK_ITEM,course.lapMarks)
			table.insert(parts,"+"..course.lapMarks.." Skymark")
		end
		local stats=Progression.computeStats(p,os.time())
		local drops=Progression.rollDrops(AG.LapDrops,stats.magicFind,roll,stats.petLuck)
		for id,n in pairs(drops) do collect(p,id,n); table.insert(parts,"+"..n.." "..Data.Items[id].name.."!") end
		Skills.refreshPerks(p)
		return table.concat(parts,"   ·   ")
	end
	function Skills.agility(player,p,item,prompt,humanoid)
		if not prompt then return "Run agility courses at their obstacles." end
		local courseId,raw
		if validId(item) then courseId,raw=string.match(item,"^(%w+):(%d+)$") end
		local course=courseId and AG.CourseById[courseId]
		local index=raw and tonumber(raw)
		local obstacle=course and index and course.obstacles[index]
		if not obstacle or prompt:GetAttribute("AgilityCourse")~=courseId or prompt:GetAttribute("AgilityIndex")~=index then return "That obstacle is not part of a course." end
		local lvl=level(p.xp.Agility)
		if lvl<course.level then return course.name.." requires Agility "..course.level.."." end
		if not regionAllowed(p,course.region) then return regionDenied(course.region) end
		local now=os.clock()
		if now<(Skills.busyUntil[player] or 0) then return "Still moving…" end
		-- Position: the runner must stand at this obstacle (it starts where the previous one landed).
		local root=rootOf(player)
		local base=prompt:FindFirstAncestorWhichIsA("BasePart")
		if not root or not base or (root.Position-base.Position).Magnitude>12 then return "Stand at the "..obstacle.name.." to attempt it." end
		local verdict,run=AG.step(Skills.runs[player],courseId,index,now)
		if verdict=="busy" then return "Still moving…" end
		if verdict=="expired" then
			Skills.runs[player]=nil
			Skills.publishRun(player,nil)
			return "Too slow: the lap is broken. Start again at the "..course.obstacles[1].name.."."
		end
		if verdict=="order" then
			local current=Skills.runs[player]
			local nextIndex=if current and current.course==courseId and current.next>1 then current.next else 1
			return "Obstacles run in order: "..(if nextIndex==1 then "start at the " else "next is the ")..course.obstacles[nextIndex].name.."."
		end
		local landing=prompt:GetAttribute("AgilityEnd")
		if typeof(landing)~="Vector3" then return "This obstacle is being repaired." end
		p.started=true
		local stats=Progression.computeStats(p,os.time())
		local fail=AG.failChance(course,obstacle,lvl,stats.surefoot)
		if fail>0 and roll()<fail then
			Skills.runs[player]=nil
			Skills.publishRun(player,nil)
			local damage=math.max(1,math.floor((humanoid.MaxHealth or 100)*.06)+course.level)
			damage=math.min(damage,math.max(0,math.floor(humanoid.Health-1)))
			if damage>0 then humanoid:TakeDamage(damage) end
			local fall=prompt:GetAttribute("AgilityFall")
			Skills.busyUntil[player]=now+.8
			if typeof(fall)=="Vector3" then Skills.move(player,fall,.8,"fall") end
			return "You slip on the "..obstacle.name.." and fall! -"..damage.." health. Start the lap again."
		end
		Skills.runs[player]=run
		Skills.busyUntil[player]=run.readyAt
		Skills.move(player,landing,obstacle.duration,obstacle.kind)
		grantXp(p,"Agility",obstacle.xp)
		local message=obstacle.name.." • +"..obstacle.xp.." Agility XP"
		if verdict=="lap" then message..="   ·   "..Skills.lap(p,course,lvl,run.readyAt-run.startedAt) end
		Skills.publishRun(player,run)
		return message
	end
	function Skills.shortcut(player,p,item,prompt)
		if not prompt then return "Use shortcuts at their posts." end
		local id
		if validId(item) then id=string.match(item,"^(%w+):[AB]$") end
		local sc=id and AG.ShortcutById[id]
		if not sc then return "That shortcut is not charted." end
		if level(p.xp.Agility)<sc.level then return sc.name.." requires Agility "..sc.level.."." end
		-- Each end carries its own destination region (ShortcutRegion, "" = open),
		-- so B->A checks where you land, not where you stand.
		local dest=prompt:GetAttribute("ShortcutRegion")
		if type(dest)~="string" then return "This shortcut is being repaired." end
		if dest~="" and not regionAllowed(p,dest) then return regionDenied(dest) end
		local now=os.clock()
		if now<(Skills.busyUntil[player] or 0) then return "Still moving…" end
		local to=prompt:GetAttribute("ShortcutTo")
		if typeof(to)~="Vector3" then return "This shortcut is being repaired." end
		Skills.runs[player]=nil
		Skills.publishRun(player,nil)
		Skills.busyUntil[player]=now+sc.duration
		Skills.move(player,to,sc.duration,sc.kind)
		grantXp(p,"Agility",sc.xp)
		p.started=true
		return sc.name.." • +"..sc.xp.." Agility XP"
	end

	-- Hunter ------------------------------------------------------------------
	local function kitFor(p,method)
		for _,id in ipairs(HU.Kits[method] or {}) do if (p.items[id] or 0)>0 then return id end end
		return nil
	end
	function Skills.count(player)
		local n=0
		for _ in pairs(Skills.owned[player] or {}) do n+=1 end
		return n
	end
	function Skills.mark(prompt)
		local trap=Skills.traps[prompt]
		local host=prompt and prompt.Parent
		if type(host)~="table" and typeof(host)~="Instance" then return end
		pcall(function()
			host:SetAttribute("TrapState",if trap then trap.state else "")
			host:SetAttribute("TrapOwner",if trap then trap.owner.UserId else 0)
		end)
	end
	function Skills.publishTraps(player)
		local p=profiles[player]
		local caught=0
		for prompt in pairs(Skills.owned[player] or {}) do
			local trap=Skills.traps[prompt]
			if trap and trap.state=="caught" then caught+=1 end
		end
		player:SetAttribute("HunterTraps",Skills.count(player).."/"..HU.maxTraps(if p then level(p.xp.Hunter) else 1))
		player:SetAttribute("HunterTrapsCaught",caught)
	end
	-- Rolls every whole tick that has elapsed (deterministic for a given roll stream).
	function Skills.advance(trap,now)
		while trap.state=="set" and now>=trap.nextTick do
			trap.ticks+=1
			trap.nextTick+=trap.tick or HU.TICK
			if roll()<trap.chance then trap.state="caught"
			elseif trap.ticks>=HU.MAX_TICKS then trap.state="collapsed" end
		end
	end
	function Skills.release(prompt)
		local trap=Skills.traps[prompt]
		if not trap then return end
		Skills.traps[prompt]=nil
		local owned=Skills.owned[trap.owner]
		if owned then owned[prompt]=nil end
		Skills.mark(prompt)
		Skills.publishTraps(trap.owner)
	end
	function Skills.sweep(now)
		for prompt,trap in pairs(Skills.traps) do
			local before=trap.state
			Skills.advance(trap,now)
			if trap.state~=before then
				Skills.mark(prompt)
				Skills.publishTraps(trap.owner)
			end
		end
	end
	function Skills.catch(p,creature)
		local stats=Progression.computeStats(p,os.time())
		local hunt=Progression.masteryPerks(p,"Hunter",os.time()) -- Skill Mastery: Keen Nose, Twin Snare, Trail Lore
		local drops=Progression.rollDrops(creature.drops,stats.magicFind+math.min(Data.Mastery.PERK_CAPS.rareFind,hunt.rareFind or 0),roll,stats.petLuck)
		local primary=creature.drops[1].item
		if drops[primary] then drops[primary]=Progression.fortuneRoll(drops[primary],stats.huntingFortune,roll) end
		local xp,doubled=creature.xp,false
		drops,xp,doubled=Progression.applyHuntMastery(p,drops,xp,roll,os.time())
		for id,n in pairs(drops) do collect(p,id,n) end
		grantXp(p,"Hunter",xp)
		local _,before=HU.logPerk(p.hunterLog)
		p.hunterLog[creature.id]=(p.hunterLog[creature.id] or 0)+1
		Skills.refreshPerks(p)
		local _,after=HU.logPerk(p.hunterLog)
		p.started=true
		local text="Caught a "..creature.name.." • +"..xp.." Hunter XP"..itemsText(drops)..(if doubled then " (twin catch)" else "")
		if after>before then text..="   ·   Hunter log milestone: permanent Trap Luck and Hunting Fortune." end
		return text
	end
	local function creatureAt(item,prompt,trap)
		local creature=validId(item) and HU.CreatureById[item]
		local method=creature and HU.Methods[creature.method]
		if not method or method.trap~=trap or prompt:GetAttribute("HunterMethod")~=creature.method then return nil end
		return creature,method
	end
	function Skills.trap(player,p,item,prompt)
		if not prompt then return "Set traps at a hunting ground." end
		local creature,method=creatureAt(item,prompt,true)
		if not creature then return "Nothing to trap here." end
		local what=string.lower(method.name)
		local now=os.clock()
		local trap=Skills.traps[prompt]
		if trap then
			if trap.owner~=player then return "Another hunter's "..what.." is set here." end
			Skills.advance(trap,now)
			if trap.state=="caught" then
				Skills.release(prompt)
				return Skills.catch(p,creature)
			elseif trap.state=="collapsed" then
				Skills.release(prompt)
				return "Your "..what.." collapsed empty. Set it again."
			end
			if now-trap.touched<=HU.DISMANTLE_WINDOW then
				Skills.release(prompt)
				return "You pick up your "..what.."."
			end
			trap.touched=now
			Skills.mark(prompt)
			return "Your "..what.." is set ("..trap.ticks.."/"..HU.MAX_TICKS.." checks). Use it again within "..HU.DISMANTLE_WINDOW.."s to pick it up."
		end
		local lvl=level(p.xp.Hunter)
		if lvl<creature.level then return creature.name.." requires Hunter "..creature.level.."." end
		if not kitFor(p,creature.method) then return "You need a "..Data.Items[method.kit].name.." (Trackers' Lodge)." end
		local cap=HU.maxTraps(lvl)
		local placed=Skills.count(player)
		if placed>=cap then return "You can tend "..cap.." trap"..(if cap==1 then "" else "s").." at Hunter "..lvl..". Collect one first." end
		local stats=Progression.computeStats(p,os.time())
		-- Skill Mastery: Spring Tension / Hair Trigger shorten the trap check interval (at most 60%).
		local tick=HU.TICK*(1-math.min(60,Progression.masteryPerks(p,"Hunter",os.time()).trapTick or 0)/100)
		Skills.traps[prompt]={owner=player,creature=creature.id,state="set",placed=now,nextTick=now+tick,tick=tick,ticks=0,touched=-math.huge,
			chance=HU.catchChance(creature,lvl,stats.trapLuck)}
		Skills.owned[player]=Skills.owned[player] or {}
		Skills.owned[player][prompt]=true
		watchPrompt(prompt)
		Skills.mark(prompt)
		Skills.publishTraps(player)
		p.started=true
		return method.name.." set for a "..creature.name..". Traps "..(placed+1).."/"..cap.."."
	end
	function Skills.net(player,p,item,prompt)
		if not prompt then return "Swing your net at a swarm." end
		local creature=creatureAt(item,prompt,false)
		if not creature then return "Nothing to net here." end
		local lvl=level(p.xp.Hunter)
		if lvl<creature.level then return creature.name.." requires Hunter "..creature.level.."." end
		local kit=kitFor(p,"net")
		if not kit then return "You need a "..Data.Items[HU.Methods.net.kit].name.." (Trackers' Lodge)." end
		local now=os.clock()
		local swarm=Skills.swarmReady[prompt]
		if swarm and now<swarm then return "The swarm has scattered ("..math.ceil(swarm-now).."s)." end
		local ready=Skills.netReady[prompt]
		if not ready then ready={}; Skills.netReady[prompt]=ready; watchPrompt(prompt) end
		if ready[player] and now<ready[player] then return "The swarm has scattered ("..math.ceil(ready[player]-now).."s)." end
		local stats=Progression.computeStats(p,os.time())
		local chance=math.min(.95,HU.catchChance(creature,lvl,stats.trapLuck)+(Data.Items[kit].netBonus or 0))
		p.started=true
		if roll()<chance then
			-- A catch scatters the swarm for everyone at this spot.
			Skills.swarmReady[prompt]=now+(creature.respawn or 5)
			return Skills.catch(p,creature)
		end
		ready[player]=now+HU.NET_MISS_COOLDOWN
		return "The "..creature.name.." slips through your net."
	end

	-- Skill vendors ------------------------------------------------------------
	function Skills.vendor(player,item,prompt)
		local vendor=prompt and type(item)=="string" and Data.SkillVendors[item]
		if not vendor then return "Nobody is trading here." end
		player:SetAttribute("SkillVendor",item)
		player:SetAttribute("SkillVendorUntil",os.time()+Data.SKILL_VENDOR_SECONDS)
		player:SetAttribute("IsleStation",if item=="Agility" then "SkymarkExchange" else "TrackersLodge")
		player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
		return vendor.name.." • browse the stock in your atlas."
	end
	function Skills.buy(player,p,item)
		local skill,id
		if validId(item) then skill,id=string.match(item,"^(%a+):(%w+)$") end
		local vendor=skill and Data.SkillVendors[skill]
		if not vendor then return "Choose an item from a skill vendor." end
		if player:GetAttribute("SkillVendor")~=skill or (player:GetAttribute("SkillVendorUntil") or 0)<os.time() then return "Visit the "..vendor.name.." to trade." end
		local entry
		for _,e in ipairs(vendor.shop) do if e.item==id then entry=e end end
		if not entry then return vendor.name.." does not stock that." end
		local def=Data.Items[id]
		if (def.kind=="armor" or def.kind=="accessory" or def.category=="trap") and (p.items[id] or 0)>0 then return "You already own "..def.name.."." end
		local coins=entry.cost.coins or 0
		local materials={}
		for k,n in pairs(entry.cost) do if k~="coins" then materials[k]=n end end
		if p.coins<coins then return def.name.." costs "..costText(entry.cost).."." end
		for k,n in pairs(materials) do if (p.items[k] or 0)<n then return def.name.." costs "..costText(entry.cost).."." end end
		spend(p,materials)
		p.coins-=coins
		collect(p,id,1)
		p.started=true
		return "Bought "..def.name.." for "..costText(entry.cost).."."
	end
	function Skills.action(player,p,verb,item,prompt,humanoid)
		if verb=="agility" then return Skills.agility(player,p,item,prompt,humanoid)
		elseif verb=="shortcut" then return Skills.shortcut(player,p,item,prompt)
		elseif verb=="trap" then return Skills.trap(player,p,item,prompt)
		elseif verb=="net" then return Skills.net(player,p,item,prompt)
		elseif verb=="skillVendor" then return Skills.vendor(player,item,prompt)
		elseif verb=="skillBuy" then return Skills.buy(player,p,item) end
		return "Unknown action."
	end
	-- Snapshot key `agilityHunter` (see docs in the report for the client team).
	function Skills.state(player,p)
		local run=Skills.runs[player]
		local traps={}
		for prompt in pairs(Skills.owned[player] or {}) do
			local trap=Skills.traps[prompt]
			if trap then table.insert(traps,{creature=trap.creature,state=trap.state,ticks=trap.ticks,spot=prompt:GetAttribute("HunterSpot")}) end
		end
		table.sort(traps,function(a,b) return tostring(a.spot)<tostring(b.spot) end)
		local hunterLevel=level(p.xp.Hunter)
		local _,lapTiers=AG.lapPerk(p.agility.laps)
		local _,logTiers=HU.logPerk(p.hunterLog)
		return {
			agility={laps=p.agility.laps,best=p.agility.best,lapTiers=lapTiers,
				run=if run and run.next>1 then {course=run.course,next=run.next,expiresIn=math.max(0,math.ceil(run.deadline-os.clock()))} else nil},
			hunter={log=p.hunterLog,logTiers=logTiers,traps=traps,maxTraps=HU.maxTraps(hunterLevel)},
			vendor={skill=player:GetAttribute("SkillVendor") or "",openUntil=player:GetAttribute("SkillVendorUntil") or 0},
		}
	end
	function Skills.forget(player)
		for prompt in pairs(Skills.owned[player] or {}) do
			Skills.traps[prompt]=nil
			Skills.mark(prompt)
		end
		Skills.owned[player],Skills.runs[player],Skills.busyUntil[player],Skills.moveSeq[player]=nil,nil,nil,nil
		for prompt,ready in pairs(Skills.netReady) do
			ready[player]=nil
			if not next(ready) then Skills.netReady[prompt]=nil end
		end
	end
	-- A prompt left the world: drop its trap (freeing the owner's slot) and cooldowns.
	function Skills.forgetPrompt(prompt)
		if Skills.traps[prompt] then Skills.release(prompt) end
		Skills.netReady[prompt],Skills.swarmReady[prompt]=nil,nil
	end
	table.insert(promptGoneHooks,Skills.forgetPrompt)
	task.spawn(function()
		while task.wait(HU.TICK) do Skills.sweep(os.clock()) end
	end)
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
	Journal.apply(player,p)
	if Mastery.apply then Mastery.apply(player,p) end
	if Garden.apply then Garden.apply(player,p) end -- Verdant Garden world attributes
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
		pets=pets,buffs=buffs,collections=collections,bestiary=p.bestiary,slayer={lines=lines,quest=p.slayerQuest},enchants=p.enchants,regions=regions,
		gear=Gear.view(p), -- Gear depth: {reforges, stars, books} (Data.Gear helpers read it)
		combat=Progression.combatLoadout(p), -- Combat styles: {style,weapon,ammo,ammoCount,supplies,levels,autocast}
		mastery=Mastery.state and Mastery.state(p)} -- Skill Mastery: points, trees, capstones, milestones, mantles
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
		depth=depthState(p,stats),journal=Journal.state(p),agilityHunter=Skills.state(player,p), -- Agility & Hunter page state
		events={claims=p.eventClaims or {},vendorUntil=player:GetAttribute("EventVendorUntil") or 0,serverTime=os.time()}, -- Events hook: Calendar page state
		garden=Garden.state and Garden.state(player,p)} -- Verdant Garden page state
end
local function claimWorker(p,slot)
	slot=slot or 1
	local w=workerFleet(p)[slot]
	if not w then return 0,"Ore",0 end
	local count=workerReady(w,p)
	local resource=w.resource
	local xp=0
	if count>0 then
		local interval=workerInterval(p,w)
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
	-- Combat styles: autocast must name an autocast spell.
	if profile.autocast~=nil and not (type(profile.autocast)=="string" and Data.Spells[profile.autocast] and Data.Spells[profile.autocast].autocast) then profile.autocast=nil end
	local quest=profile.slayerQuest
	if quest~=nil and (type(quest)~="table" or not Data.Slayers[quest.line] or not Data.Slayers[quest.line].tiers[quest.tier]) then profile.slayerQuest=nil end
	profile.version=math.max(tonumber(profile.version) or 1,2)
	workerFleet(profile)
	Journal.migrate(profile)
	Skills.migrate(profile) -- Agility & Hunter records + milestone perks
	Gear.migrate(profile) -- Gear depth: reforges, stars, books
	Progression.masteryMigrate(profile) -- Skill Mastery: drop unknown/invalid nodes, reset overspent trees
	if Garden.migrate then Garden.migrate(profile) end -- Verdant Garden: sanitise and bound p.garden
end
-- Clears every per-player table and ends this player's session slot.
-- Sea creatures: a successful Fishing gather may hook one (Data.rollSeaCreature).
-- The server issues a ticket {id, expires} under a per-player sequence number and
-- sets SeaCreatureAt (node position) then SeaCreatureSpawn = "<id>:<seq>"; Combat
-- spawns it and reports back through bridge op "seaCreature". Only the ticket's
-- owner is ever credited, once; despawns free the slot without a reward.
local Sea={tickets={},GRACE=15} -- tickets[player]; cleared in forget()
function Sea.book(player)
	local book=Sea.tickets[player]
	if not book then book={seq=0,live={}}; Sea.tickets[player]=book end
	local now=os.clock()
	for seq,ticket in pairs(book.live) do if now>ticket.expires then book.live[seq]=nil end end
	return book
end
function Sea.count(book)
	local n=0
	for _ in pairs(book.live) do n+=1 end
	return n
end
function Sea.cast(player,p,stats,toolId,region,prompt)
	local book=Sea.book(player)
	if Sea.count(book)>=Data.SeaCreatureCap then return "" end
	local rod=toolId and Data.Items[toolId]
	local chance=Data.seaCreatureChance(stats,rod and rod.stats,toolId and Progression.enchantStats(p,toolId,"tool","Fishing"))
	local id=Data.rollSeaCreature(level(p.xp.Fishing),region,chance,roll)
	if not id then return "" end
	book.seq+=1
	book.live[book.seq]={id=id,expires=os.clock()+Data.SeaCreatureLifetime+Sea.GRACE}
	local base=prompt and prompt:FindFirstAncestorWhichIsA("BasePart")
	if base then player:SetAttribute("SeaCreatureAt",base.Position) end
	player:SetAttribute("SeaCreatureSpawn",id..":"..book.seq)
	return "   ·   A "..Data.SeaCreatures[id].name.." surfaces!"
end
-- Bridge op "seaCreature" {seq, monster, result = "kill"|"despawn"} for the owner.
function Sea.report(player,p,payload)
	local seq,id,result=payload.seq,payload.monster,payload.result
	if type(seq)~="number" or seq%1~=0 or not validId(id) or (result~="kill" and result~="despawn") then return {ok=false,reason="invalid"} end
	local book=Sea.tickets[player]
	local ticket=book and book.live[seq]
	if not ticket or ticket.id~=id then return {ok=false,reason="ticket"} end
	book.live[seq]=nil
	if result=="despawn" then return {ok=true} end
	if os.clock()>ticket.expires then return {ok=false,reason="expired"} end
	local monster=Data.SeaCreatures[id]
	local stats=Progression.computeStats(p,os.time())
	p.started=true
	grantXp(p,"Fishing",monster.fishingXp)
	grantXp(p,"Combat",monster.xp)
	p.coins+=monster.coins
	local drops=Progression.rollDrops(monster.drops,stats.magicFind,roll,stats.petLuck)
	for item,n in pairs(drops) do collect(p,item,n) end
	p.bestiary[id]=(p.bestiary[id] or 0)+1
	return {ok=true,drops=drops,message=monster.name.." slain • +"..monster.coins.." coins, +"..monster.fishingXp.." Fishing XP, +"..monster.xp.." Combat XP"}
end
local function forget(player)
	profiles[player],cooldown[player],lastRead[player],preview[player],leaseEnd[player]=nil,nil,nil,nil,nil
	marketViews[player],marketReads[player],stateRead[player],exchangeReady[player]=nil,nil,nil,nil
	Econ.views[player],Econ.reads[player]=nil,nil
	sessionOwner[player],opening[player]=nil,nil
	Sea.tickets[player]=nil
	Journal.isle.budget[player]=nil
	for prompt,regrowth in pairs(nodeRegrowth) do
		regrowth[player]=nil
		if not next(regrowth) then nodeRegrowth[prompt]=nil end
	end
	Skills.forget(player) -- Agility runs, Hunter traps (session-only)
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
	local refundNote=applySigilRefund and applySigilRefund(player,profile) -- Endgame: altar refunds owed while away
	update:FireClient(player,snapshot(player,(if preview[player] then "Studio practice session • saving unavailable" else "Journal opened")..(if refundNote then " • "..refundNote else "")))
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

------------------------------------------------------------------------------
-- Skill Mastery (Data.Mastery; rules in Progression.mastery*).
-- Verbs: masteryUnlock "Tree:Node" (one level), masteryRespec "Tree" (coins,
-- scaling cost), ability "Tree" (capstone, server cooldown, persisted),
-- masteryWear "cape:Skill" | "aura:Skill" | "title:Skill" | "cape:" (clear).
-- Hooks: gather (Mastery.gather), Hunter catches/traps (Skills.catch/trap),
-- bridge "consume" (Mastery.thrift: arrow/glyph save), "combatXp" (style XP
-- boost), "stats" → result.mastery = Progression.masteryCombat(p, now):
--   melee  = {firstStrike %, execute %, xpBoost %}
--   ranged = {firstStrike %, execute %, arrowSave %, multishot n (1 = off), xpBoost %}
--   magic  = {manaThrift %, glyphSave %, xpBoost %}
--   active = {[tree] = expires (os.time)} while a combat capstone runs.
-- Combat applies firstStrike (force a crit on the first hit against a monster
-- at full health), execute (+% damage below 30% health), manaThrift (spell
-- mana x (1 - %/100)) and multishot (extra targets per shot); stat effects
-- (Warcry, Volley strength, Glyphstorm ability damage) already arrive in stats.
-- Player attributes: MasteryCape, MasteryAura (skill or ""), MasteryTitle
-- (title text), MasteryAbility ("Tree:expires" of the last capstone fired).
------------------------------------------------------------------------------
do
	local MA=Data.Mastery
	Mastery.verbs={masteryUnlock=true,masteryRespec=true,ability=true,masteryWear=true}
	function Mastery.tokenNote(p,claimed,tier)
		for _,t in ipairs(MA.TOKEN_TIERS) do
			if claimed<t and tier>=t then note(p,"+1 Mastery Token (spend it in any mastery tree)") end
		end
	end
	-- Bonus ingots and coins from a harvest; returns the message suffix.
	function Mastery.gather(p,result)
		local parts={}
		for id,n in pairs(result.bonus or {}) do
			collect(p,id,n)
			table.insert(parts,"+"..n.." "..Data.Items[id].name)
		end
		if result.coins then p.coins+=result.coins; table.insert(parts,"+"..result.coins.." coins") end
		if result.multiplied then table.insert(parts,"x"..result.multiplied.." yield") end
		if result.surge then table.insert(parts,"surge") end
		if result.respawnSkip then table.insert(parts,"quick regrowth ("..(math.floor(result.regrowth*10+0.5)/10).."s)") end
		return if #parts>0 then "   ·   "..table.concat(parts,", ") else ""
	end
	-- Arrow/glyph save: removes saved supplies from cost, returns {id=n} saved.
	function Mastery.thrift(p,cost)
		local saved={}
		if type(p.mastery)~="table" then return saved end
		local perks=Progression.masteryCombat(p,os.time())
		for id,n in pairs(table.clone(cost)) do
			local def=Data.Items[id]
			local chance=if def.category=="ammo" then perks.ranged.arrowSave elseif def.category=="glyph" then perks.magic.glyphSave else 0
			if chance>=100 or (chance>0 and roll()<chance/100) then
				saved[id]=n
				cost[id]=nil
			end
		end
		return saved
	end
	function Mastery.apply(player,p)
		local m=type(p.mastery)=="table" and p.mastery or {}
		player:SetAttribute("MasteryCape",Progression.masteryCape(p) or "")
		local aura=m.aura
		player:SetAttribute("MasteryAura",if type(aura)=="string" and level(p.xp[aura])>=50 then aura else "")
		local title=type(m.title)=="string" and MA.title(m.title,level(p.xp[m.title]))
		player:SetAttribute("MasteryTitle",title or "")
	end
	-- Snapshot depth.mastery (Progression.masteryView): points, node levels/states, capstones, mantles.
	function Mastery.state(p) return Progression.masteryView(p,os.time()) end
	local function unlock(p,item)
		local treeId,nodeId
		if validId(item) then treeId,nodeId=string.match(item,"^(%a+):(%w+)$") end
		local tree=treeId and MA.TreeById[treeId]
		if not tree then return "Choose a mastery node." end
		local ok,why=Progression.masteryUnlock(p,treeId,nodeId)
		if not ok then return why end
		local node=tree.NodeById[nodeId]
		p.started=true
		local left=Progression.masteryPoints(p).trees[treeId].available
		return node.name.." "..(if node.max>1 then why.." / "..node.max else "unlocked").."   ·   "..left.." "..tree.name.." point"..(if left==1 then "" else "s").." left"
	end
	local function respec(p,item)
		local tree=validId(item) and MA.TreeById[item]
		if not tree then return "Choose a mastery tree to reset." end
		local ok,why=Progression.masteryRespec(p,tree.id)
		if not ok then return why end
		p.bankRevision=(p.bankRevision or 0)+1
		return tree.name.." reset for "..why.." coins. Every point is yours to spend again."
	end
	local function ability(player,p,item)
		local tree=validId(item) and MA.TreeById[item]
		if not tree then return "Choose a mastery capstone." end
		local now=os.time()
		local ok,result=Progression.masteryActivate(p,tree.id,now)
		if not ok then return result end
		local node=tree.NodeById[tree.capstone]
		player:SetAttribute("MasteryAbility",tree.id..":"..(now+result.duration))
		return node.name.."! "..result.text.." Recharges in "..result.cooldown.."s."
	end
	local function wear(p,item)
		local kind,skill
		if type(item)=="string" and #item<=64 then kind,skill=string.match(item,"^(%a+):(%a*)$") end
		if kind~="cape" and kind~="aura" and kind~="title" then return "Choose a mantle, aura or title." end
		local m=Progression.ensureMastery(p)
		if skill=="" then m[kind]=nil return "Removed your "..kind.."." end
		if not Data.Skills[skill] then return "Choose a skill." end
		local need=if kind=="cape" then Data.MAX_LEVEL elseif kind=="aura" then 50 else MA.MilestoneLevels[1]
		if level(p.xp[skill])<need then return "Reach "..skill.." "..need.." first." end
		m[kind]=skill
		if kind=="cape" then
			local def=Data.Skills[skill]
			return "You don the Mantle of the "..(def.title or skill).."."
		elseif kind=="aura" then return "Your "..skill.." aura shimmers." end
		return "Title set: "..MA.title(skill,level(p.xp[skill]))
	end
	function Mastery.action(player,p,verb,item)
		if verb=="masteryUnlock" then return unlock(p,item)
		elseif verb=="masteryRespec" then return respec(p,item)
		elseif verb=="ability" then return ability(player,p,item)
		elseif verb=="masteryWear" then return wear(p,item) end
		return "Unknown action."
	end
end

------------------------------------------------------------------------------
-- Verdant Garden (Farming Depth team). Rules: Data.Garden (shared/GameData.lua);
-- world: the garden islet beside each home (world.server.lua, Garden section).
-- Every timer is server os.time(); growth, composting and visitor arrivals are
-- integrated lazily (Garden.refresh) on every garden verb, snapshot and the
-- G.TICK loop, so they continue offline. The record is p.garden (G.sanitize
-- on load bounds it). Verbs (item ≤ 64 chars):
--   plant "plot:seed"  (seed id or crop id)       harvestPlot "plot"|"all"
--   waterPlot "plot"|"all"   fertilise "plot" (Rich Compost)   treatPlot "plot" (Blightward Salve)
--   clearPest "plot"   clearPlot "plot" (uproot)   gardenPlot "plot" (world prompt: contextual)
--   compost "item[:count]"   compostClaim   composterUpgrade
--   visitorAccept "id"   visitorDecline "id"   gardenBuy "shopId"   gardenSkin "skin"   gardenOpen
-- Snapshot key `garden` (Garden.state). Player attributes for the world:
--   GardenLevel, GardenPlots (unlocked count), GardenSkin, GardenComposter
--   ("locked"|"idle"|"working"|"ready"), GardenVisitors ("npc,npc"), and
--   GardenPlot1..12 = "" (empty) or "<crop>:<stage 0-4>:<flags>" with flags
--   w watered, c composted, t treated, s sick, x dead, r ripe, p<n> pest n.
-- Milestone fortune lives in p.perkStats["garden:milestones"]. Refresh runs at
-- most once per second per garden (so a snapshot's applyStats + state pair
-- refreshes once); its events (ripe, visitors, pests, withering) queue per
-- garden and are told once: in the next garden verb's message, or by the
-- G.TICK loop, which fires only while news is pending.
------------------------------------------------------------------------------
do
	local G=Data.Garden
	for _,verb in ipairs({"plant","harvestPlot","waterPlot","fertilise","treatPlot","clearPest","clearPlot","gardenPlot","gardenOpen",
		"compost","compostClaim","composterUpgrade","visitorAccept","visitorDecline","gardenBuy","gardenSkin"}) do Garden.verbs[verb]=true end
	local function rec(p)
		if type(p.garden)~="table" or type(p.garden.plots)~="table" then p.garden=G.sanitize(p.garden,os.time()) end
		return p.garden
	end
	local function farming(p) return level(p.xp.Farming) end
	local function name(id) return Data.Items[id] and Data.Items[id].name or tostring(id) end
	local function span(seconds)
		seconds=math.max(0,math.floor(seconds or 0))
		if seconds>=3600 then return (seconds//3600).."h "..string.format("%02d",(seconds%3600)//60).."m" end
		if seconds>=60 then return (seconds//60).."m "..string.format("%02d",seconds%60).."s" end
		return seconds.."s"
	end
	local function setActive(p)
		local n=0
		for _,slot in ipairs(Data.ArmorSlots) do
			local _,def=Progression.equipped(p,slot)
			if def and def.set==G.SET then n+=1 end
		end
		return n>=4
	end
	function Garden.ctx(p) return {level=G.level(rec(p).xp),set=setActive(p)} end
	function Garden.refreshPerk(p)
		if type(p.perkStats)~="table" then p.perkStats={} end
		p.perkStats["garden:milestones"]=(G.milestonePerk(rec(p).harvested))
	end
	function Garden.migrate(p)
		p.garden=G.sanitize(p.garden,os.time())
		-- Milestones baseline at the save's standing (no retroactive windfall).
		for id,n in pairs(p.garden.harvested) do
			p.garden.milestones[id]=math.max(p.garden.milestones[id] or 0,G.milestoneTier(id,n))
		end
		Garden.refreshPerk(p)
	end
	function Garden.addXp(p,g,amount)
		local before=G.level(g.xp)
		g.xp=math.min(1e9,g.xp+math.max(0,math.floor(amount)))
		local after=G.level(g.xp)
		if after>before then
			local fl=farming(p)
			local was,now=G.plotCount(before,fl),G.plotCount(after,fl)
			note(p,"Garden level "..after.."!"..(if now>was then " New plot unlocked ("..now.."/"..G.MAX_PLOTS..")." else "")
				..(if before<G.COMPOSTER_LEVEL and after>=G.COMPOSTER_LEVEL then " The composter is ready." else ""))
		end
	end
	-- Events found by refresh wait here (per garden record) until a snapshot
	-- or the G.TICK loop announces them, so no refresh can swallow them.
	-- Strong tables keyed by the garden record; the G.TICK loop drops records
	-- that no live profile holds (players who left, replaced records).
	local pending,refreshedAt={},{}
	-- Advance every timer to now (at most once per second per garden). Returns
	-- g, ctx, events {ripe, pests, visitors, dead}; events also queue as pending.
	function Garden.refresh(p,now)
		local g=rec(p)
		local ctx=Garden.ctx(p)
		local events={ripe=0,pests=0,visitors=0,dead=0}
		if refreshedAt[g]==now then return g,ctx,events end
		refreshedAt[g]=now
		for i=1,G.MAX_PLOTS do
			local plot=g.plots[i]
			if plot.crop then
				local wasRipe,wasDead=G.ripe(plot),plot.dead
				G.advance(plot,now,ctx)
				if G.ripe(plot) and not wasRipe then events.ripe+=1 end
				if plot.dead and not wasDead then events.dead+=1 end
				if G.pestRoll(plot,now,roll) then events.pests+=1 end
			end
		end
		if ctx.level>=G.COMPOSTER_LEVEL then G.composterAdvance(g.composter,now) else g.composter.at=now end
		local n,nextAt=G.visitorsDue(g.nextVisitor,now,#g.visitors,G.visitorCap(ctx.level))
		for _=1,n do
			g.seq+=1
			table.insert(g.visitors,G.makeVisitor(g.seq,ctx.level,farming(p),roll))
		end
		g.nextVisitor=nextAt
		events.visitors=n
		if events.ripe+events.pests+events.visitors+events.dead>0 then
			local q=pending[g] or {ripe=0,pests=0,visitors=0,dead=0}
			for k,v in pairs(events) do q[k]+=v end
			pending[g]=q
		end
		return g,ctx,events
	end
	-- Pending news as text (capped by what is still true now), then cleared.
	function Garden.takeNews(p)
		local g=rec(p)
		local q=pending[g]
		if not q then return "" end
		pending[g]=nil
		local ripe,pests,dead=0,0,0
		for i=1,G.MAX_PLOTS do
			local plot=g.plots[i]
			if G.ripe(plot) then ripe+=1 end
			if plot.pest then pests+=1 end
			if plot.dead then dead+=1 end
		end
		return Garden.eventText({ripe=math.min(q.ripe,ripe),pests=math.min(q.pests,pests),visitors=math.min(q.visitors,#g.visitors),dead=math.min(q.dead,dead)})
	end

	function Garden.plotCode(plot,now)
		local c=G.CropById[plot.crop]
		local flags=(if c and (plot.water or 0)>now then "w" else "")..(if plot.compost then "c" else "")..(if plot.treated then "t" else "")
			..(if plot.sick and not plot.dead then "s" else "")..(if plot.dead then "x" else "")..(if G.ripe(plot) then "r" else "")
			..(if plot.pest then "p"..plot.pest else "")
		if not c and flags=="" then return "" end
		return (plot.crop or "")..":"..G.stage(plot)..":"..flags
	end
	-- World attributes (refreshes first). Returns the refresh events.
	function Garden.apply(player,p)
		local now=os.time()
		local g,ctx,events=Garden.refresh(p,now)
		player:SetAttribute("GardenLevel",ctx.level)
		player:SetAttribute("GardenPlots",G.plotCount(ctx.level,farming(p)))
		player:SetAttribute("GardenSkin",g.skin)
		for i=1,G.MAX_PLOTS do player:SetAttribute("GardenPlot"..i,Garden.plotCode(g.plots[i],now)) end
		local ids={}
		for _,v in ipairs(g.visitors) do table.insert(ids,v.npc) end
		player:SetAttribute("GardenVisitors",table.concat(ids,","))
		local c=g.composter
		player:SetAttribute("GardenComposter",if ctx.level<G.COMPOSTER_LEVEL then "locked" elseif c.out>0 or c.dust>0 then "ready"
			elseif c.matter>=G.COMPOST_MATTER then "working" else "idle")
		return events
	end
	function Garden.eventText(ev)
		local parts={}
		if ev.ripe>0 then table.insert(parts,ev.ripe.." garden crop"..(if ev.ripe==1 then " is" else "s are").." ripe") end
		if ev.visitors>0 then table.insert(parts,(if ev.visitors==1 then "A visitor is" else ev.visitors.." visitors are").." waiting in your garden") end
		if ev.pests>0 then table.insert(parts,"Pests are nibbling your crops") end
		if ev.dead>0 then table.insert(parts,"A blighted crop withered") end
		return table.concat(parts,"   ·   ")
	end
	-- Field Farming gathers: every FIELD_SEED_EVERY-th harvest of a crop bundles a seed.
	function Garden.fieldSeed(p,item)
		local c=G.CropById[item]
		if not c then return end
		local g=rec(p)
		local n=(g.fieldSeeds[item] or 0)+1
		g.fieldSeeds[item]=n
		if n%G.FIELD_SEED_EVERY==0 then
			collect(p,c.seed,1)
			note(p,"Seed pouch • +1 "..name(c.seed))
		end
	end
	local function plotOf(p,g,item)
		local i=tonumber(item)
		if not i or i~=math.floor(i) or i<1 or i>G.MAX_PLOTS then return nil,"Choose a garden plot." end
		local unlocked=G.plotCount(G.level(g.xp),farming(p))
		if i>unlocked then return nil,"Plot "..i.." is locked. Next plot: "..(G.nextPlotUnlock(G.level(g.xp),farming(p)) or "—").."." end
		return i,g.plots[i]
	end
	local function milestones(p,g,cropId)
		local tier=G.milestoneTier(cropId,g.harvested[cropId] or 0)
		local paid=g.milestones[cropId] or 0
		if tier<=paid then return end
		local coins,gxp=0,0
		for t=paid+1,tier do
			local r=G.milestoneReward(cropId,t)
			coins+=r.coins; gxp+=r.gxp
		end
		g.milestones[cropId]=tier
		p.coins+=coins
		note(p,name(cropId).." milestone "..tier.."! +"..coins.." coins, +"..(G.MILESTONE_CROP_FORTUNE*tier).." "..name(cropId).." fortune")
		Garden.addXp(p,g,gxp)
		Garden.refreshPerk(p)
	end
	local function fortuneFor(p,g,c,stats)
		local fortune=stats.farmingFortune or 0
		local toolId,tool=Progression.bestTool(p,"Farming")
		if tool then
			fortune+=(tool.stats and tool.stats.farmingFortune) or 0
			fortune+=Progression.enchantStats(p,toolId,"tool","Farming").farmingFortune or 0
		end
		return fortune+G.milestoneTier(c.id,g.harvested[c.id] or 0)*G.MILESTONE_CROP_FORTUNE
	end
	local function harvest(p,g,i,stats,now)
		local plot=g.plots[i]
		local c=G.CropById[plot.crop]
		local pest=plot.pest~=nil
		local result={xp=c.xp,skill="Farming",resource={id=c.id,skill="Farming",value=Data.Items[c.id].value}}
		-- Mastery Twin/Bountiful procs and surges join the base before fortune (as field gathering).
		local mult,perks=1,nil
		if type(p.mastery)=="table" then mult,perks=Progression.gatherYieldMult(p,result,roll,now) end
		result.amount=G.yieldFor(c.id,fortuneFor(p,g,c,stats),pest,roll,mult)
		if perks then Progression.applyGatherMastery(p,result,roll,now,perks) end
		result.respawnSkip=nil
		collect(p,c.id,result.amount)
		local mastered=Mastery.gather(p,result)
		grantXp(p,"Farming",result.xp)
		local seeds=G.seedReturn(c,roll)
		if seeds>0 then collect(p,c.seed,seeds) end
		g.harvested[c.id]=math.min(1e9,(g.harvested[c.id] or 0)+result.amount)
		g.plots[i]={}
		Garden.addXp(p,g,c.gxp)
		milestones(p,g,c.id)
		p.started=true
		return result.amount,result.xp,seeds,mastered..(if pest then "   ·   pests cut the yield" else "")
	end
	local function plant(p,g,i,plot,id,now,chosen)
		local c=G.CropBySeed[id] or G.CropById[id]
		if not c then return "Choose a seed to plant." end
		if plot.crop then return "Plot "..i.." is already planted." end
		if farming(p)<c.level then return name(c.id).." needs Farming "..c.level.."." end
		if (p.items[c.seed] or 0)<1 then return "You have no "..name(c.seed)..". Buy seeds in the garden ledger." end
		p.items[c.seed]-=1
		if chosen then g.lastSeed=c.seed end -- the world prompt replants the player's own pick
		G.plant(plot,c.id,now,roll)
		p.started=true
		return "Planted "..name(c.id).." in plot "..i.."   ·   ripe in about "..span(G.timeLeft(plot,now,Garden.ctx(p)))
	end
	local function water(g,i,plot,now)
		local c=G.CropById[plot.crop]
		if not c then return "Plot "..i.." has nothing to water." end
		if plot.dead then return "Plot "..i.."'s crop has withered." end
		if G.ripe(plot) then return "Plot "..i.." is ripe — harvest it." end
		if plot.sick then return "Plot "..i.." is blighted; treat it first." end
		if (plot.water or 0)>now then return "Plot "..i.." is still damp ("..span(plot.water-now)..")." end
		plot.water=now+G.WATER_SECONDS
		return nil
	end
	local function harvestAll(p,g,now,list)
		local stats=Progression.computeStats(p,now)
		local xp,seeds,crops,extra=0,0,{},""
		for _,i in ipairs(list) do
			local id=g.plots[i].crop
			local n,x,s,more=harvest(p,g,i,stats,now)
			xp+=x; seeds+=s
			crops[id]=(crops[id] or 0)+n
			extra..=more
		end
		local parts={}
		for id,n in pairs(crops) do table.insert(parts,"+"..n.." "..name(id)) end
		table.sort(parts)
		return table.concat(parts,", ").."   ·   +"..xp.." Farming XP   ·   "..(if seeds>0 then "+"..seeds.." seed"..(if seeds==1 then "" else "s") else "no seed saved")..extra
	end
	local function clearPest(p,g,i,plot)
		local pest=plot.pest and G.Pests[plot.pest]
		if not pest then return "Plot "..i.." has no pests." end
		local c=G.CropById[plot.crop]
		plot.pest=nil
		local cxp,fxp=pest.combatXp+2*c.index,8*c.index
		grantXp(p,"Combat",cxp)
		grantXp(p,"Farming",fxp)
		collect(p,G.CHITIN,1)
		Garden.addXp(p,g,2)
		local seed=""
		if roll()<G.PEST_SEED_CHANCE then collect(p,c.seed,1); seed=", +1 "..name(c.seed) end
		return "Swatted the "..pest.name.."!   ·   +"..cxp.." Combat XP, +"..fxp.." Farming XP, +1 "..name(G.CHITIN)..seed
	end
	local function treat(p,i,plot,now)
		if plot.dead then return "Plot "..i.."'s crop is beyond saving. Clear it." end
		if plot.treated then return "Plot "..i.." is already treated." end
		if (p.items[G.SALVE] or 0)<1 then return "You need a "..name(G.SALVE).." (Alchemy 12 or the garden shop)." end
		p.items[G.SALVE]-=1
		local cured=plot.sick~=nil
		plot.treated,plot.blight,plot.sick=true,nil,nil
		if plot.crop then plot.at=now end
		return if cured then "Plot "..i.." cured; it grows again and stays immune." elseif plot.crop then "Plot "..i.." treated: immune to blight until harvest."
			else "Plot "..i.." treated: the next crop is immune to blight."
	end
	local function fertilise(p,i,plot)
		if plot.compost then return "Plot "..i.." is already fertilised." end
		if plot.dead then return "Plot "..i.."'s crop has withered." end
		if G.ripe(plot) then return "Plot "..i.." is ripe — harvest it first." end
		if (p.items[G.COMPOST] or 0)<1 then return "You need "..name(G.COMPOST).." from the composter." end
		p.items[G.COMPOST]-=1
		plot.compost=true
		if plot.crop and plot.blight and not plot.sick and roll()<G.COMPOST_CLEANSE then plot.blight=nil end
		return if plot.crop then "Plot "..i.." fertilised: +"..math.floor(G.COMPOST_BOOST*100).."% growth." else "Plot "..i.." fertilised for the next crop."
	end
	local function shopOwned(p,item)
		if (p.items[item] or 0)>0 then return true end
		for _,e in ipairs(G.Shop) do
			if e.upgrade==item and shopOwned(p,e.item) then return true end
		end
		return false
	end
	local function costText(cost)
		local parts={}
		if cost.coins then table.insert(parts,cost.coins.." coins") end
		for id,n in pairs(cost) do if id~="coins" then table.insert(parts,n.." "..name(id)) end end
		table.sort(parts)
		return table.concat(parts,", ")
	end
	local function buy(p,g,item)
		local e=validId(item) and G.ShopById[item]
		if not e then return "The garden shop does not stock that." end
		local gl=G.level(g.xp)
		if gl<e.level then return "Reach garden level "..e.level.." to buy that." end
		if e.kind=="skin" then
			if g.skins[e.skin] then return "You already own the "..G.SkinById[e.skin].name.." skin." end
		else
			if e.unique and shopOwned(p,e.item) then return "You already own "..name(e.item).."." end
			if e.upgrade and (p.items[e.upgrade] or 0)<1 then return name(e.item).." upgrades your "..name(e.upgrade)..". Buy that first." end
		end
		if p.coins<(e.cost.coins or 0) then return "That costs "..costText(e.cost).."." end
		for id,n in pairs(e.cost) do if id~="coins" and (p.items[id] or 0)<n then return "That costs "..costText(e.cost).."." end end
		for id,n in pairs(e.cost) do if id~="coins" then p.items[id]-=n end end
		p.coins-=e.cost.coins or 0
		p.started=true
		if e.kind=="skin" then
			g.skins[e.skin]=true
			g.skin=e.skin
			return "Plot skin "..G.SkinById[e.skin].name.." unlocked and applied."
		end
		if e.upgrade then p.items[e.upgrade]-=1 end
		collect(p,e.item,e.amount)
		return "Bought "..(if e.amount>1 then e.amount.." " else "")..name(e.item).." for "..costText(e.cost).."."
	end
	local function visitorOf(g,item)
		local id=tonumber(item)
		for index,v in ipairs(g.visitors) do if v.id==id then return index,v end end
		return nil
	end
	local function accept(p,g,item)
		local index,v=visitorOf(g,item)
		if not v then return "That visitor has already left." end
		for id,n in pairs(v.wants) do
			if (p.items[id] or 0)<n then return G.VisitorById[v.npc].name.." wants "..n.." "..name(id).." (you have "..(p.items[id] or 0)..")." end
		end
		for id,n in pairs(v.wants) do p.items[id]-=n end
		table.remove(g.visitors,index)
		p.coins+=v.coins
		collect(p,G.MARK,v.marks)
		for id,n in pairs(v.items) do collect(p,id,n) end
		grantXp(p,"Farming",v.xp)
		Garden.addXp(p,g,v.gxp)
		g.served+=1
		p.started=true
		local extra={}
		for id,n in pairs(v.items) do table.insert(extra,"+"..n.." "..name(id)) end
		table.sort(extra)
		return G.VisitorById[v.npc].name.." is delighted!   ·   +"..v.coins.." coins, +"..v.marks.." Verdant Marks, +"..v.gxp.." garden XP"
			..(if #extra>0 then ", "..table.concat(extra,", ") else "")
	end
	local function feed(p,g,item)
		if G.level(g.xp)<G.COMPOSTER_LEVEL then return "The composter opens at garden level "..G.COMPOSTER_LEVEL.."." end
		local id,count
		if validId(item) then id,count=string.match(item,"^(%w+):(%d+)$") end
		if not id then id=item end
		local value=validId(id) and G.organic(id) or 0
		if value<=0 then return "The composter only takes crops and organic matter." end
		if count and (tonumber(count) or 0)<1 then return "Choose at least 1 "..name(id).." to compost." end
		local c=g.composter
		local room=math.floor((G.matterCap(c.upgrade)-c.matter)/value)
		local n=math.min(tonumber(count) or math.huge,p.items[id] or 0,room)
		if (p.items[id] or 0)<1 then return "You have no "..name(id).."." end
		if n<1 then return "The composter is full." end
		if c.matter<G.COMPOST_MATTER then c.at=os.time() end
		p.items[id]-=n
		c.matter+=n*value
		return "Composted "..n.." "..name(id).."   ·   +"..(n*value).." matter ("..c.matter.."/"..G.matterCap(c.upgrade)..")"
	end
	local function claim(p,g)
		local c=g.composter
		if c.out<1 and c.dust<1 then return "Nothing in the composter yet." end
		local out,dust=c.out,c.dust
		if out>0 then collect(p,G.COMPOST,out) end
		if dust>0 then collect(p,G.DUST,dust) end
		c.out,c.dust=0,0
		return "Collected "..out.." "..name(G.COMPOST)..(if dust>0 then " and "..dust.." "..name(G.DUST) else "").."."
	end
	local function upgrade(p,g)
		if G.level(g.xp)<G.COMPOSTER_LEVEL then return "The composter opens at garden level "..G.COMPOSTER_LEVEL.."." end
		local c=g.composter
		local up=G.ComposterUpgrades[c.upgrade+1]
		if not up then return "The composter is fully upgraded." end
		if (p.items[G.DUST] or 0)<up.dust or (p.items[G.MARK] or 0)<up.marks then
			return "Upgrade "..(c.upgrade+1).." costs "..up.dust.." "..name(G.DUST).." and "..up.marks.." "..name(G.MARK).."."
		end
		p.items[G.DUST]-=up.dust
		p.items[G.MARK]-=up.marks
		c.upgrade+=1
		return "Composter upgraded to tier "..c.upgrade.."   ·   a Compost every "..span(G.composterInterval(c.upgrade))
	end
	local act
	-- Garden verbs (and world prompts) carry any pending news in their message;
	-- otherwise the G.TICK loop tells it. Other snapshots leave it pending.
	function Garden.action(player,p,verb,item,prompt)
		local message=act(player,p,verb,item,prompt)
		local news=Garden.takeNews(p)
		if news~="" then message=(if message and message~="" then message.."   ·   " else "")..news end
		return message
	end
	function act(player,p,verb,item,prompt)
		local now=os.time()
		local g=Garden.refresh(p,now)
		if verb=="gardenOpen" then
			local ripe=0
			for _,plot in ipairs(g.plots) do if G.ripe(plot) then ripe+=1 end end
			return "Verdant Garden   ·   level "..G.level(g.xp).."   ·   "..ripe.." ripe   ·   "..#g.visitors.." visitor"..(if #g.visitors==1 then "" else "s")
		elseif verb=="compost" then return feed(p,g,item)
		elseif verb=="compostClaim" then return claim(p,g)
		elseif verb=="composterUpgrade" then return upgrade(p,g)
		elseif verb=="visitorAccept" then return accept(p,g,item)
		elseif verb=="visitorDecline" then
			local index,v=visitorOf(g,item)
			if not v then return "That visitor has already left." end
			table.remove(g.visitors,index)
			return G.VisitorById[v.npc].name.." wanders off."
		elseif verb=="gardenBuy" then return buy(p,g,item)
		elseif verb=="gardenSkin" then
			if not (validId(item) and g.skins[item]) then return "Unlock that skin in the garden shop first." end
			g.skin=item
			return "Plot skin set to "..G.SkinById[item].name.."."
		end
		local unlocked=G.plotCount(G.level(g.xp),farming(p))
		if (verb=="harvestPlot" or verb=="waterPlot") and item=="all" then
			local list,count={},0
			for i=1,unlocked do
				local plot=g.plots[i]
				if verb=="harvestPlot" and G.ripe(plot) then table.insert(list,i)
				elseif verb=="waterPlot" and plot.crop and water(g,i,plot,now)==nil then count+=1 end
			end
			if verb=="waterPlot" then return if count>0 then "Watered "..count.." plot"..(if count==1 then "" else "s").."   ·   +"..math.floor(G.WATER_BOOST*100).."% growth for "..span(G.WATER_SECONDS) else "Nothing needs water right now." end
			if #list==0 then return "Nothing is ripe yet." end
			return harvestAll(p,g,now,list)
		end
		local id,seed
		if verb=="plant" then
			if validId(item) then id,seed=string.match(item,"^(%d+):(%w+)$") end
			if not id then return "Choose a plot and a seed." end
		else id=item end
		local i,plot=plotOf(p,g,id)
		if not i then return plot end
		if verb=="plant" then return plant(p,g,i,plot,seed,now,true)
		elseif verb=="harvestPlot" then
			if plot.dead then return "Plot "..i.."'s crop withered. Clear it to replant." end
			if not G.ripe(plot) then return if plot.crop then "Plot "..i.." is not ripe yet." else "Plot "..i.." is empty." end
			return harvestAll(p,g,now,{i})
		elseif verb=="waterPlot" then
			return water(g,i,plot,now) or ("Watered plot "..i.."   ·   +"..math.floor(G.WATER_BOOST*100).."% growth for "..span(G.WATER_SECONDS))
		elseif verb=="fertilise" then return fertilise(p,i,plot)
		elseif verb=="treatPlot" then return treat(p,i,plot,now)
		elseif verb=="clearPest" then return clearPest(p,g,i,plot)
		elseif verb=="clearPlot" then
			if not plot.crop then return "Plot "..i.." is already clear." end
			local what=if plot.dead then "withered "..name(plot.crop) else name(plot.crop)
			g.plots[i]={}
			return "Cleared the "..what.." from plot "..i.."."
		elseif verb=="gardenPlot" then
			-- One world prompt per plot: the most useful action for its state.
			if plot.pest then return clearPest(p,g,i,plot) end
			if plot.dead then g.plots[i]={} return "Cleared the withered crop from plot "..i.."." end
			if plot.sick then return treat(p,i,plot,now) end
			if G.ripe(plot) then return harvestAll(p,g,now,{i}) end
			if not plot.crop then
				local c=G.autoSeed(p.items,farming(p),g.lastSeed)
				if not c then
					for seed in pairs(G.MarkSeeds) do
						if (p.items[seed] or 0)>0 then return "Choose a seed in the garden ledger first: seeds bought with Verdant Marks are only planted when you pick them." end
					end
					return "No seeds to plant. Open the garden ledger to buy some."
				end
				return plant(p,g,i,plot,c.seed,now)
			end
			local wet=water(g,i,plot,now)
			if wet==nil then return "Watered plot "..i.."   ·   +"..math.floor(G.WATER_BOOST*100).."% growth for "..span(G.WATER_SECONDS) end
			return name(plot.crop).." · "..G.STAGE_NAMES[G.stage(plot)].."   ·   ripe in "..span(G.timeLeft(plot,now,Garden.ctx(p)))
		end
		return "Unknown action."
	end
	-- Snapshot key `garden`.
	function Garden.state(player,p)
		local now=os.time()
		local g,ctx=Garden.refresh(p,now)
		local fl=farming(p)
		local unlocked=G.plotCount(ctx.level,fl)
		local plots={}
		for i=1,G.MAX_PLOTS do
			local plot=g.plots[i]
			local c=G.CropById[plot.crop]
			plots[i]={index=i,unlocked=i<=unlocked,crop=plot.crop,stage=G.stage(plot),ripe=G.ripe(plot),remaining=G.timeLeft(plot,now,ctx),
				fraction=if c then math.min(1,(plot.grown or 0)/c.grow) else 0,watered=math.max(0,(plot.water or 0)-now),
				compost=plot.compost==true,treated=plot.treated==true,sick=plot.sick~=nil and not plot.dead,dead=plot.dead==true,
				pest=if plot.pest then G.Pests[plot.pest].id else nil,
				deathIn=if plot.sick and not plot.dead then math.max(0,plot.sick+G.DEATH_SECONDS-now) else nil}
		end
		local milestones={}
		for _,c in ipairs(G.Crops) do
			local n=g.harvested[c.id] or 0
			local tier=G.milestoneTier(c.id,n)
			milestones[c.id]={count=n,tier=tier,nextAt=G.milestoneThreshold(c.id,tier+1),fortune=tier*G.MILESTONE_CROP_FORTUNE}
		end
		local cmp=g.composter
		local interval=G.composterInterval(cmp.upgrade)
		local working=ctx.level>=G.COMPOSTER_LEVEL and cmp.matter>=G.COMPOST_MATTER and cmp.out<G.COMPOST_OUT_CAP
		local visitors={}
		for _,v in ipairs(g.visitors) do
			table.insert(visitors,{id=v.id,npc=v.npc,wants=table.clone(v.wants),order=table.clone(v.order),coins=v.coins,marks=v.marks,gxp=v.gxp,xp=v.xp,items=table.clone(v.items)})
		end
		local owned={}
		for _,e in ipairs(G.Shop) do
			if e.kind=="item" and e.unique and shopOwned(p,e.item) then owned[e.id]=true end
		end
		local lvl,floor,ceiling=G.progress(g.xp)
		local _,tiers=G.milestonePerk(g.harvested)
		return {level=lvl,xp=g.xp,floor=floor,nextAt=ceiling,plots=plots,unlocked=unlocked,maxPlots=G.MAX_PLOTS,nextPlot=G.nextPlotUnlock(lvl,fl),
			milestones=milestones,milestoneTiers=tiers,
			composter={unlocked=ctx.level>=G.COMPOSTER_LEVEL,matter=cmp.matter,cap=G.matterCap(cmp.upgrade),out=cmp.out,dust=cmp.dust,upgrade=cmp.upgrade,
				interval=interval,nextIn=if working then math.max(0,cmp.at+interval-now) else nil},
			visitors=visitors,visitorCap=G.visitorCap(lvl),nextVisitorIn=if #g.visitors<G.visitorCap(lvl) then math.max(0,g.nextVisitor-now) else nil,
			served=g.served,skin=g.skin,skins=table.clone(g.skins),owned=owned,lastSeed=g.lastSeed,rate=G.rate({},ctx,false),setActive=ctx.set,serverTime=now}
	end
	task.spawn(function()
		while task.wait(G.TICK) do
			local live={}
			for _,p in pairs(profiles) do if type(p.garden)=="table" then live[p.garden]=true end end
			for g in pairs(refreshedAt) do if not live[g] then refreshedAt[g]=nil; pending[g]=nil end end
			for g in pairs(pending) do if not live[g] then pending[g]=nil end end
			for player,p in pairs(profiles) do
				if player.Parent then
					local ok,news=pcall(function() Garden.apply(player,p) return Garden.takeNews(p) end)
					if ok and news~="" then update:FireClient(player,snapshot(player,news)) end
				end
			end
		end
	end)
end
-- End Verdant Garden block.

local exchangeBusy={}
------------------------------------------------------------------------------
-- Endgame (Endgame team): the Sovereign Altar verb and world boss rewards.
--   bossSigil (prompt IsleAction, IsleItem = boss id, IsleRegion gate): needs a
--     Crown Sigil; combat.server.lua's ServerStorage.IsleWorldBoss accepts the
--     placement first ({ok, reason, count, needed}), then the sigil is spent.
--   bridge "worldBoss" {boss, tier, rank, share, damage, sigils, fight}: pays a
--     credited contributor once per fight (journal in the region's gate, else
--     reason "region"; not live: reason "sync" and combat resends): coins and
--     Sovereign Essence scaled by share, then Data.Endgame.bossRewards drops
--     rolled with Magic Find / Pet Luck (Progression.rollDrops), bestiary +1.
--   bridge "worldBossRefund" / shutdown drain: unspent altar sigils (below).
------------------------------------------------------------------------------
local Endgame={verbs={bossSigil=true},paid={},paidCount=0} -- paid["boss:fight:userId"]=os.time()
do
	local E=Data.Endgame
	local SIGIL_TEXT={full="The altar already holds every sigil.",mine="You have placed all the sigils one wayfarer may.",
		active="The Sovereign is already awake.",boss="This altar is silent."}
	function Endgame.action(player,p,verb,item)
		if verb~="bossSigil" then return "Unknown action." end
		local def=E.boss(item)
		if not def or def.summon~="altar" then return "This altar is silent." end
		local sigil="CrownSigil"
		if (p.items[sigil] or 0)<1 then return "You need a Crown Sigil (Glyphcraft 85) to place in the altar." end
		local fn=ServerStorage:FindFirstChild("IsleWorldBoss")
		if not fn then return "The altar stirs, but nothing answers yet." end
		local ok,reply=pcall(fn.Invoke,fn,"sigil",player,item)
		if not ok or type(reply)~="table" then return "The altar flickers. Try again shortly." end
		if not reply.ok then return SIGIL_TEXT[reply.reason] or "The altar refuses the sigil." end
		spend(p,{[sigil]=1})
		p.started=true
		if reply.reason=="ready" then return "The last sigil blazes! "..def.name.." awakens!" end
		return "Sigil placed ("..tostring(reply.count).."/"..tostring(reply.needed)..")."
	end
	function Endgame.reward(player,p,payload)
		local def=E.boss(payload.boss)
		local tier=type(payload.tier)=="string" and E.TierById[payload.tier]
		local rank=tonumber(payload.rank)
		if not def or not tier or not rank or rank<1 or rank%1~=0 then return {ok=false,reason="invalid"} end
		-- Credit needs the region gate too (no noclip alts below Combat 60 / the quest).
		if not regionAllowed(p,def.region or E.REGION) then return {ok=false,reason="region"} end
		-- Once per fight per journal (keys pruned after an hour).
		local key=payload.boss..":"..tostring(payload.fight)..":"..tostring(player.UserId)
		if Endgame.paid[key] then return {ok=false,reason="paid"} end
		local now=os.time()
		if Endgame.paidCount>=500 then
			Endgame.paidCount=0
			for k,at in pairs(Endgame.paid) do if now-at>3600 then Endgame.paid[k]=nil else Endgame.paidCount+=1 end end
		end
		Endgame.paid[key]=now
		Endgame.paidCount+=1
		local plan=E.bossRewards(payload.boss,tier.id,rank,math.clamp(math.floor(tonumber(payload.sigils) or 0),0,E.ALTAR_PER_PLAYER),payload.share)
		local stats=Progression.computeStats(p,os.time())
		local drops=Progression.rollDrops(plan.drops,stats.magicFind,roll,stats.petLuck)
		for id,n in pairs(plan.items) do drops[id]=(drops[id] or 0)+n end
		for id,n in pairs(drops) do collect(p,id,n) end
		p.coins+=plan.coins
		p.bestiary[payload.boss]=(p.bestiary[payload.boss] or 0)+1
		p.started=true
		local share=math.floor(plan.share*1000+0.5)/10
		return {ok=true,drops=drops,coins=plan.coins,tier=tier.id,
			message=def.short.." felled • #"..rank.." · "..share.."% · "..tier.name.." • +"..plan.coins.." coins"..dropText(drops)}
	end
	-- Unspent altar sigils: combat bridge "worldBossRefund" {boss, userId,
	-- sigils, reason} (failed summon, departure before anyone struck the boss)
	-- and the shutdown drain. A live journal on this server gets them at once;
	-- one still syncing keeps them as profile.sigilRefund; an offline journal
	-- has sigilRefund written into its save once no server holds its lease
	-- (retried for OFFLINE_WINDOW s). sigilRefund is applied on the next join,
	-- bounded by Data.Endgame.REFUND_CAP.
	local SIGIL="CrownSigil"
	Endgame.offline={} -- [userId]={n, deadline} refunds still to write
	Endgame.OFFLINE_RETRY,Endgame.OFFLINE_WINDOW=30,900
	local function journalOf(uid)
		for player,p in pairs(profiles) do if player.UserId==uid then return player,p end end
		return nil,nil
	end
	local function plural(n) return n.." unspent Crown Sigil"..(if n==1 then "" else "s") end
	function Endgame.credit(uid,n)
		local player,p=journalOf(uid)
		if not p then return nil end
		if live(player) then
			p.items[SIGIL]=(p.items[SIGIL] or 0)+n
			if player.Parent then update:FireClient(player,snapshot(player,"The Sovereign Altar returns "..plural(n)..".")) end
			return "items"
		end
		p.sigilRefund=math.min(E.REFUND_CAP,math.max(0,math.floor(tonumber(p.sigilRefund) or 0))+n)
		return "profile"
	end
	-- One write into a saved journal nobody holds. true = settled (written, or no journal).
	function Endgame.writeOffline(uid,n)
		if not store then return true end
		local done=false
		local ok=pcall(function()
			store:UpdateAsync("p"..uid,function(old)
				done=false
				if type(old)~="table" or type(old.profile)~="table" then done=true; return nil end
				if old.owner~="" and (tonumber(old.expires) or 0)>os.time() then return nil end
				old.profile.sigilRefund=math.min(E.REFUND_CAP,math.max(0,math.floor(tonumber(old.profile.sigilRefund) or 0))+n)
				done=true
				return old
			end)
		end)
		return ok and done
	end
	function Endgame.queueOffline(uid,n)
		local job=Endgame.offline[uid]
		if job then job.n=math.min(E.REFUND_CAP,job.n+n); return end
		job={n=n,deadline=os.time()+Endgame.OFFLINE_WINDOW}
		Endgame.offline[uid]=job
		task.spawn(function()
			while Endgame.offline[uid]==job do
				local n2=job.n
				local settled=Endgame.credit(uid,n2)~=nil or Endgame.writeOffline(uid,n2)
				if settled then
					job.n-=n2
					if job.n<=0 then Endgame.offline[uid]=nil; break end
				elseif os.time()>job.deadline then
					Endgame.offline[uid]=nil
					break
				end
				task.wait(Endgame.OFFLINE_RETRY)
			end
		end)
	end
	function Endgame.refund(payload,shutdown)
		local uid=tonumber(payload.userId)
		local n=math.floor(tonumber(payload.sigils) or 0)
		if not uid or uid%1~=0 or uid<=0 or n<1 then return {ok=false,reason="invalid"} end
		n=math.min(n,E.ALTAR_PER_PLAYER)
		local mode=Endgame.credit(uid,n)
		if mode then return {ok=true,mode=mode} end
		if shutdown then
			for _=1,2 do if Endgame.writeOffline(uid,n) then return {ok=true,mode="saved"} end end
			return {ok=false,reason="busy"}
		end
		Endgame.queueOffline(uid,n)
		return {ok=true,mode="pending"}
	end
	-- Shutdown: combat empties its altars (IsleWorldBoss "drain") and every
	-- placer is refunded before the journals save.
	function Endgame.drain()
		local fn=ServerStorage:FindFirstChild("IsleWorldBoss")
		if not fn then return 0 end
		local ok,list=pcall(fn.Invoke,fn,"drain")
		if not ok or type(list)~="table" then return 0 end
		local n=0
		for _,e in ipairs(list) do
			if type(e)=="table" and Endgame.refund(e,true).ok then n+=1 end
		end
		return n
	end
	applySigilRefund=function(_,p)
		local n=math.floor(tonumber(p.sigilRefund) or 0)
		p.sigilRefund=nil
		if n<=0 then return nil end
		n=math.min(n,E.REFUND_CAP)
		p.items[SIGIL]=(p.items[SIGIL] or 0)+n
		return "The Sovereign Altar returned "..plural(n).."."
	end
end
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
	if Skills.verbs[verb] then
		return Skills.action(player,p,verb,item,prompt,humanoid) -- Agility & Hunter
	elseif Mastery.verbs[verb] then
		return Mastery.action(player,p,verb,item) -- Skill Mastery
	elseif Garden.verbs[verb] then
		return Garden.action(player,p,verb,item,prompt) -- Verdant Garden
	elseif Endgame.verbs[verb] and prompt then
		return Endgame.action(player,p,verb,item) -- Endgame: Sovereign Altar
	elseif Econ.verbs and Econ.verbs[verb] then
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
		-- Events hook: Skyward Calendar season/event effects (state published by festival.server.lua).
		local event=Data.eventGather(item,Data.eventState(workspace,os.time()),roll)
		bonus+=event.bonus
		local stats=Progression.computeStats(p,os.time())
		local ok,result=Progression.harvest(p,item,stats,roll,bonus,os.time())
		if not ok then
			if item=="Aetherite" then return result.." Train on Ore in Quarry Cay." end
			return result
		end
		-- Events hook: festival yield/XP multipliers apply exactly once, after fortune; festival-only catches.
		result.amount*=event.mult; result.xp=math.floor(result.xp*event.xpMult)
		for id,n in pairs(event.extra) do collect(p,id,n); note(p,"Festival catch • +"..n.." "..Data.Items[id].name) end
		collect(p,item,result.amount)
		grantXp(p,skill,result.xp)
		if skill=="Farming" and Garden.fieldSeed then Garden.fieldSeed(p,item) end -- Verdant Garden seed pouch
		local mastered=Mastery.gather(p,result) -- Skill Mastery: bonus ingots, coins, regrowth skip
		if region then Journal.count(p,"gathers",region,1) end
		p.started=true
		if not regrowth then regrowth={}; nodeRegrowth[prompt]=regrowth; watchPrompt(prompt) end
		-- Skill Mastery: Quick regrowth shortens the timer down to a floor (Progression.regrowthTime), never to zero.
		regrowth[player]=os.clock()+(tonumber(result.regrowth) or tonumber(resource.respawn) or 3)
		local hooked=if skill=="Fishing" then Sea.cast(player,p,stats,result.tool,region,prompt) else ""
		return "+"..result.amount.." "..resource.name.."   ·   +"..result.xp.." "..skill.." XP"..mastered..hooked
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
	elseif verb=="quest" and item~=nil then
		return Journal.claimQuest(p,item)
	elseif verb=="diary" then
		return Journal.claimDiary(p,item)
	elseif verb=="build" then
		return Journal.build(player,p,item)
	elseif verb=="remove" then
		return Journal.remove(player,p,item)
	elseif verb=="portal" then
		return Journal.attune(player,p,item)
	elseif verb=="place" then
		return Journal.isle.place(player,p,item)
	elseif verb=="pickup" then
		return Journal.isle.pickup(player,p,item)
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
		Journal.count(p,"crafts",item,1)
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
		Journal.count(p,"crafts",recipe.output,recipe.amount)
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
		if type(item)~="string" or not gearSlots[item] then return "Choose weapon, helmet, chest, legs, boots or ammo." end
		local id=p.equipment[item]
		if not id then return "Nothing is equipped in that slot." end
		p.equipment[item]=nil
		return "Unequipped "..(Data.Items[id] and Data.Items[id].name or id).."."
	elseif verb=="autocast" then
		-- Combat styles: choose the spell ("cast" with no spell id) or clear it with "" / "none".
		if item==nil or item=="" or item=="none" then p.autocast=nil; return "Autocast cleared." end
		local spell=validId(item) and Data.Spells[item]
		if not spell or not spell.autocast then return "Choose a combat spell to autocast." end
		if level(p.xp.Magic)<spell.level then return spell.name.." requires Magic "..spell.level.."." end
		p.autocast=item
		return "Autocasting "..spell.name.."."
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
	elseif Gear.verbs[verb] then
		return Gear.verbs[verb](p,item) -- Gear depth: reforge, reforgeStone, star, tome
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
	elseif verb=="eventGift" or verb=="eventTrade" then
		-- Events hook: Starfall gift / Festival Vendor trade; rules and persisted claims in Data.eventAction.
		return Data.eventAction(p,verb,item,Data.eventState(workspace,os.time()),os.time(),collect,(player:GetAttribute("EventVendorUntil") or 0)>os.time())
	elseif verb=="eventVendor" and prompt then
		-- Events hook: the hub Festival Vendor opens trading for a few minutes and the Calendar page.
		player:SetAttribute("EventVendorUntil",os.time()+Data.EVENT_VENDOR_SECONDS)
		player:SetAttribute("IsleStation","Calendar"); player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
		return "The Festival Vendor spreads out this season's wares."
	elseif verb=="recall" then
		-- Townsfolk hook (npc.server.lua): recall charm to "Hub"/"Home". IsleRecall validates the
		-- target, enforces its cooldown and recent-damage gate, and picks the destination server-side.
		local recall=ServerStorage:FindFirstChild("IsleRecall")
		if not recall then return "The recall charm is still being charted. Use a beacon for now." end
		local ok,message=pcall(recall.Invoke,recall,player,item)
		return if ok and type(message)=="string" then message else "The recall charm flickers. Try again shortly."
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
		if not enemies[prompt] then enemies[prompt]=arena; watchPrompt(prompt) end
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
	Endgame.drain() -- Endgame: refund unspent altar sigils before the journals save
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
-- grantExpedition returns {ok=true} or {ok=false,reason}; the IsleExpeditionGrant
-- BindableFunction exposes it so the Observatory only announces accepted chests.
local function grantExpedition(player,result)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return {ok=false,reason="Your journal is syncing, so the Observatory chest could not be credited."} end
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
	if level(p.xp.Dungeoneering)<floor.level then return {ok=false,reason=floor.name.." requires Dungeoneering "..floor.level.."."} end
	if not Data.dungeonCooldownReady(dungeons.lastClear,now) then
		local message="Observatory chest cooling down • wait "..(Data.Dungeons.clearCooldown-(now-dungeons.lastClear)).."s between credited clears."
		update:FireClient(player,snapshot(player,message))
		return {ok=false,reason=message}
	end
	if not Data.dungeonIronmanCredit(p.ironman==true,partySize,share) then
		local message="Ironman journals need a solo clear or 30% of the party's damage for Observatory credit."
		update:FireClient(player,snapshot(player,message))
		return {ok=false,reason=message}
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
	return {ok=true}
end
expedition.Event:Connect(function(player,result) grantExpedition(player,result) end)
expedition.Parent=ServerStorage
local expeditionGrant=Instance.new("BindableFunction")
expeditionGrant.Name="IsleExpeditionGrant"
expeditionGrant.OnInvoke=grantExpedition
expeditionGrant.Parent=ServerStorage

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

-- Combat styles bridge helpers (combat.server.lua). "consume" pays arrows,
-- glyphs and tablets atomically: every listed id must be a combatUse item,
-- 1..50 each, all owned, else nothing is taken. "combatXp" routes style XP:
-- damage XP from Progression.styleXp (fractions carried per session) plus a
-- spell's cast XP (Data.Spells[id].xp) for magic.
local CombatStyles={carry=setmetatable({},{__mode="k"})}
function CombatStyles.consume(p,payload)
	local items=payload.items
	if type(items)~="table" then return {ok=false,reason="invalid"} end
	local cost,count={},0
	for id,n in pairs(items) do
		local def=validId(id) and Data.Items[id]
		if not def or not def.combatUse or type(n)~="number" or n%1~=0 or n<1 or n>50 then return {ok=false,reason="invalid"} end
		cost[id]=n
		count+=1
		if count>8 then return {ok=false,reason="invalid"} end
	end
	if count==0 then return {ok=false,reason="invalid"} end
	for id,n in pairs(cost) do if (p.items[id] or 0)<n then return {ok=false,reason="missing"} end end
	local saved=Mastery.thrift(p,cost) -- Skill Mastery: Quiver/Ink Thrift keep some supplies
	if not spend(p,cost) then return {ok=false,reason="missing"} end
	local remaining={}
	for id in pairs(cost) do remaining[id]=p.items[id] end
	for id in pairs(saved) do remaining[id]=p.items[id] end
	return {ok=true,remaining=remaining,saved=if next(saved) then saved else nil}
end
-- "refund" returns supplies a cast paid for but could not use (a Hubward
-- tablet that failed to teleport). Same validation as "consume". The caller
-- refunds only what was actually spent (costs minus "saved"); supplies go
-- straight back to the satchel and never count toward collections/tokens.
function CombatStyles.refund(p,payload)
	local items=payload.items
	if type(items)~="table" then return {ok=false,reason="invalid"} end
	local back,count={},0
	for id,n in pairs(items) do
		local def=validId(id) and Data.Items[id]
		if not def or not def.combatUse or type(n)~="number" or n%1~=0 or n<1 or n>50 then return {ok=false,reason="invalid"} end
		back[id]=n
		count+=1
		if count>8 then return {ok=false,reason="invalid"} end
	end
	if count==0 then return {ok=false,reason="invalid"} end
	for id,n in pairs(back) do p.items[id]=(p.items[id] or 0)+n end
	return {ok=true}
end
function CombatStyles.xpRate(monsterId,tier)
	if type(monsterId)~="string" then return nil end
	local line=string.match(monsterId,"^Boss:(%a+)$")
	if line then
		local t=Data.Slayers[line] and Data.Slayers[line].tiers[tonumber(tier) or 0]
		if not t then return nil end
		return t.spawnXp*Data.CombatStyles.bossXpShare,t.hp
	end
	local monster=validId(monsterId) and Data.Monsters[monsterId]
	if not monster then return nil end
	return monster.xp,monster.hp
end
function CombatStyles.xp(p,payload)
	local style=payload.style
	if style~="melee" and style~="ranged" and style~="magic" then return {ok=false,reason="invalid"} end
	local gains={}
	local damage=payload.damage
	if type(damage)=="number" and damage==damage and damage>0 then
		local xp,hp=CombatStyles.xpRate(payload.monster,payload.tier)
		if xp then gains=Progression.styleXp(style,damage,xp,hp) end
	end
	local spell=style=="magic" and validId(payload.spell) and Data.Spells[payload.spell]
	if spell and spell.xp then gains.Magic=(gains.Magic or 0)+spell.xp end
	-- Skill Mastery: Weapon Lore / Longwatch / Studious raise that style's XP.
	local lore=type(p.mastery)=="table" and Progression.masteryCombat(p,os.time())[style].xpBoost or 0
	if lore>0 then for skill,amount in pairs(gains) do gains[skill]=amount*(1+lore/100) end end
	local carry=CombatStyles.carry[p] or {}
	CombatStyles.carry[p]=carry
	local granted,levelled={},false
	for skill,amount in pairs(gains) do
		local total=amount+(carry[skill] or 0)
		local whole=math.floor(total)
		carry[skill]=total-whole
		if whole>0 then
			local before=level(p.xp[skill])
			grantXp(p,skill,whole)
			granted[skill]=whole
			if level(p.xp[skill])>before then levelled=true end
		end
	end
	if next(granted) then p.started=true end
	return {ok=true,xp=granted,levelled=levelled}
end

-- Server-to-server bridge consumed by Combat (docs/DEPTH-CONTRACT.md §4).
local bridge=Instance.new("BindableFunction")
bridge.Name="IsleBridge"
local function notify(player,message)
	if player.Parent then update:FireClient(player,snapshot(player,message)) end
end
bridge.OnInvoke=function(op,player,payload)
	if type(op)~="string" or player==nil then return nil end
	if type(payload)~="table" then payload={} end
	if op=="worldBossRefund" then
		-- Endgame: unspent altar sigils; the placer may be offline (player = UserId).
		return Endgame.refund(payload)
	end
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
		-- Combat re-arms the boss / resends the sea creature kill (ticket kept)
		-- when its report could not be applied; Endgame: combat resends world boss rewards.
		return if op=="slayerBoss" or op=="seaCreature" or op=="worldBoss" then {ok=false,reason="sync"} else nil
	end
	if op=="stats" then
		return {stats=Progression.computeStats(p,os.time()),combatLevel=level(p.xp.Combat),ironman=p.ironman==true,
			loadout=Progression.combatLoadout(p), -- Combat styles: weapon style, quiver, supplies, autocast
			mastery=Progression.masteryCombat(p,os.time())} -- Skill Mastery perks combat applies (see Mastery block)
	elseif op=="consume" then
		return CombatStyles.consume(p,payload)
	elseif op=="refund" then
		return CombatStyles.refund(p,payload)
	elseif op=="combatXp" then
		local reply=CombatStyles.xp(p,payload)
		if reply.levelled then notify(player,"") end
		return reply
	elseif op=="dungeon" then
		-- Dungeons: floor gate + Ironman flag for expedition.server.lua.
		return {level=level(p.xp.Dungeoneering),ironman=p.ironman==true}
	elseif op=="kill" then
		local monsterId=payload.monster
		local monster=validId(monsterId) and Data.Monsters[monsterId]
		-- Sea creatures pay only through their owner's ticket (op "seaCreature").
		if not monster or monster.seaCreature or monster.worldBoss then return nil end
		local stats=Progression.computeStats(p,os.time())
		p.started=true
		-- No flat Combat XP here: the damage XP accrued on the monster is paid
		-- through "combatXp" when it dies (monster.xp in total for melee).
		p.coins+=monster.coins
		local drops=Progression.rollDrops(monster.drops,stats.magicFind,roll,stats.petLuck)
		for item,n in pairs(drops) do collect(p,item,n) end
		-- Events hook: Hollow Night event-only drops (Data.eventKillDrops).
		for item,n in pairs(Data.eventKillDrops(monsterId,Data.eventState(workspace,os.time()),roll)) do drops[item]=(drops[item] or 0)+n; collect(p,item,n) end
		p.bestiary[monsterId]=(p.bestiary[monsterId] or 0)+1
		local quest=p.slayerQuest
		if quest and not quest.bossReady and monster.slayer==quest.line then
			quest.progress=math.min(quest.needed,quest.progress+monster.xp)
			if quest.progress>=quest.needed then
				quest.bossReady=true
				note(p,"The "..Data.Slayers[quest.line].name.." stirs! Defeat it to finish your slayer quest.")
			end
		end
		notify(player,monster.name.." slain • +"..monster.coins.." coins"..dropText(drops))
		return {drops=drops,bossReady=quest~=nil and quest.bossReady==true}
	elseif op=="worldBoss" then
		local reply=Endgame.reward(player,p,payload)
		if reply.message then notify(player,reply.message); reply.message=nil end
		return reply
	elseif op=="seaCreature" then
		local reply=Sea.report(player,p,payload)
		if reply.message then notify(player,reply.message..dropText(reply.drops)); reply.message=nil end
		return reply
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
-- request (coop.server.lua only): perk = crew stat perk table or false (stored
-- in p.perkStats.coop); deposit/settle = journal outbox of satchel->crew moves
-- (sequence numbered, debited and saved before the crew is credited); credit =
-- crew->satchel delivery, idempotent by token. See coop.server.lua header.
coopProfile.OnInvoke=function(player,seal,request)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return {ready=false} end
	if seal then
		p.started=true
		if not persist(player,false) then return {ready=false} end
	end
	local box=if type(p.coopBox)=="table" then p.coopBox else {seq=0,pending={},delivered={}}
	p.coopBox=box
	local result
	if type(request)=="table" then
		if request.perk~=nil then
			p.perkStats=if type(p.perkStats)=="table" then p.perkStats else {}
			p.perkStats.coop=if type(request.perk)=="table" then table.clone(request.perk) else nil
		end
		local d,s,c=request.deposit,request.settle,request.credit
		if type(d)=="table" and type(d.resource)=="string" and type(d.amount)=="number" and d.amount>=1 then
			if (p.items[d.resource] or 0)<d.amount then result={ok=false} else
				box.seq+=1
				local key=tostring(box.seq)
				p.items[d.resource]-=d.amount
				box.pending[key]={seq=box.seq,resource=d.resource,amount=d.amount,groupId=d.groupId}
				if persist(player,false) then result={ok=true,seq=box.seq} else
					p.items[d.resource]=(p.items[d.resource] or 0)+d.amount
					box.pending[key]=nil
					result={ok=false}
				end
			end
		elseif type(s)=="table" then
			local entry=box.pending[tostring(s.seq)]
			if entry and s.refund then p.items[entry.resource]=(p.items[entry.resource] or 0)+entry.amount end
			box.pending[tostring(s.seq)]=nil
			result={ok=true}
		elseif type(c)=="table" and type(c.token)=="string" and type(c.resource)=="string" and type(c.amount)=="number" then
			if table.find(box.delivered,c.token) then result={ok=true} else
				p.items[c.resource]=(p.items[c.resource] or 0)+c.amount
				table.insert(box.delivered,c.token)
				if #box.delivered>32 then table.remove(box.delivered,1) end
				if persist(player,false) then result={ok=true} else
					p.items[c.resource]-=c.amount
					table.remove(box.delivered,table.find(box.delivered,c.token))
					result={ok=false}
				end
			end
		end
		if result and result.ok and (d or c or (s and s.refund)) and player.Parent then update:FireClient(player,snapshot(player,"")) end
	end
	local outbox={}
	for _,entry in pairs(box.pending) do table.insert(outbox,table.clone(entry)) end
	return {ready=true,ironman=p.ironman==true,preview=preview[player]==true,coopOutbox=outbox,result=result}
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
	if committed then
		marketViews[player]=quote(committed,order.item,trader)
		if not preview[player] then rememberBook(key,committed) end
	end
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
		local ok,book
		if preview[player] then ok,book=true,previewBooks["market_v1_"..item] else ok,book=cachedBook(player,"market_v1_"..item) end
		if not ok then return book or "Market quote unavailable. Your previous quote may be stale." end
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
	if idle and verb=="list" and (p.items[item] or 0)<3 then return "A market lot needs 3 "..item.."." end
	if idle and verb=="buy" and p.coins<price then return "You need "..price.." purse coins to reserve this buy limit." end
	if not resume then
		local allowed,wait=spendMarketBudget(player,2)
		if not allowed then return marketBusy(wait) end
	end
	if idle then
		if verb=="list" and not spend(p,{[item]=3}) then return "A market lot needs 3 "..item.."." end
		if verb=="buy" then p.coins-=price end
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
-- profile (p.econPending, with a random nonce) and saved before the shared key
-- is written. Keys: bazaar_v1_<item>, auction_v1_<kind>.
--
-- Receipts (one per trader, {seq, n=nonce, coins, items, at, text}) make a
-- replayed order apply exactly once: an order applies only when its nonce differs
-- from the trader's receipt, and settles only against the receipt with its nonce.
-- Keys stay small and bounded:
--   * zero-effect orders (nothing filled, rested, cancelled or collected) never
--     write: the transform cancels and the server refunds the escrow locally;
--     claims with nothing to collect are answered from a read, without any write;
--   * only the newest receipt keeps its text; a trader's receipt is replaced by
--     their next order (which proves the old one was applied);
--   * receipts of traders with no open orders/listings and nothing to collect
--     ("inert") expire after RECEIPT_TTL; at capacity the oldest inert receipt
--     older than RECEIPT_EVICT_AGE gives up its slot to a newcomer;
--   * capacity counts live receipts (traders with state), never lifetime traders.
------------------------------------------------------------------------------
do
local Rules=Data.Economy
local previewEcon={}
local READ_INTERVAL=2
local RECEIPT_TTL=14*86400
local RECEIPT_EVICT_AGE=3600
-- Live trader slots per key, so the worst-case value stays far below the
-- DataStore per-key throughput budget (see the size fixture in verify-gameplay).
local LIVE_CAP={bazaar=1500,auction=600}
local categorySet={}
for _,kind in ipairs(Rules.auctionCategories) do categorySet[kind]=true end
local bazaarVerbs={bid=true,offer=true,buyNow=true,sellToBid=true,bidCancel=true,bidClaim=true}
Econ.verbs={bazaar=true,ahBrowse=true,ahList=true,ahBuy=true,ahCancel=true,ahClaim=true}
for verb in pairs(bazaarVerbs) do Econ.verbs[verb]=true end
Econ.limits={receiptTtl=RECEIPT_TTL,evictAge=RECEIPT_EVICT_AGE,liveCap=LIVE_CAP}
local function liveCap(kind) return math.min(Rules.accountCap,LIVE_CAP[kind]) end
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
-- Traders that still hold state in a book (open orders/listings or something to collect).
local function busyTraders(book,kind)
	local busy={}
	if kind=="bazaar" then
		for _,side in ipairs({"bids","asks"}) do for _,o in ipairs(book[side]) do busy[o.owner]=true end end
		for id,c in pairs(book.claims) do
			if type(c)=="table" and ((c.units or 0)>0 or (c.coins or 0)>0) then busy[id]=true else book.claims[id]=nil end
		end
	else
		for _,l in ipairs(book.listings) do busy[l.seller]=true end
		for id,n in pairs(book.proceeds) do if (tonumber(n) or 0)>0 then busy[id]=true else book.proceeds[id]=nil end end
		for id,back in pairs(book.returns) do if type(back)=="table" and next(back) then busy[id]=true else book.returns[id]=nil end end
	end
	return busy
end
-- The receipt proves this exact order was applied. Orders written before nonces
-- existed fall back to the sequence number (legacy receipts have no nonce).
local function receiptMatches(receipt,order)
	if type(receipt)~="table" then return false end
	if order.nonce then return receipt.n==order.nonce end
	return receipt.n==nil and receipt.seq==order.seq
end
local function alreadyApplied(receipt,order)
	if type(receipt)~="table" then return false end
	if order.nonce then return receipt.n==order.nonce end
	return receipt.n==nil and (tonumber(receipt.seq) or 0)>=order.seq
end
-- Can uid hold a receipt? Returns admitted, and the inert receipt to evict (if any).
local function admission(book,kind,uid,now,busy)
	if book.receipts[uid] then return true,nil end
	local live=0
	for _ in pairs(book.receipts) do live+=1 end
	if live<liveCap(kind) then return true,nil end
	local oldest,oldestAt
	for id,r in pairs(book.receipts) do
		local at=tonumber(type(r)=="table" and r.at) or now
		if not busy[id] and now-at>=RECEIPT_EVICT_AGE and (not oldestAt or at<oldestAt) then oldest,oldestAt=id,at end
	end
	return oldest~=nil,oldest
end
-- Runs on every write: strips old receipt text, stamps legacy receipts and
-- expires inert receipts past their TTL. Keeps book.accounts = live receipts.
local function prune(book,kind,uid,now,busy)
	local live=0
	for id,r in pairs(book.receipts) do
		if type(r)~="table" then
			book.receipts[id]=nil
		else
			r.at=tonumber(r.at) or now
			if id~=uid then r.text=nil;r.open=nil end
			if id~=uid and not busy[id] and now-r.at>RECEIPT_TTL then book.receipts[id]=nil else live+=1 end
		end
	end
	book.accounts=live
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
-- Applies one order to a normalized book. Returns {coins, items, text, changed};
-- changed=false means the book is untouched and the result is a pure refund.
local function bazaarTrade(book,uid,order)
	local verb,qty,price,name=order.verb,order.qty or 0,order.price or 0,itemName(order.item)
	local coins,units,text,changed=0,0,"",false
	local room=#book.bids+#book.asks<Rules.bookCap
	if verb=="bid" or verb=="buyNow" then
		local filled,cost=take(book,uid,"buy",qty,price)
		units=filled
		coins=filled*price-cost
		local rest=qty-filled
		if filled>0 then changed=true;text="Bought "..filled.." "..name.." for "..cost.." coins." end
		if rest>0 and verb=="bid" and room then
			book.nextId+=1
			insertOrder(book.bids,{id=book.nextId,owner=uid,price=price,qty=rest},true)
			changed=true
			text=joined(text,"Buy order #"..book.nextId..": "..rest.." "..name.." at "..price.." each, coins escrowed.")
		elseif rest>0 then
			coins+=rest*price
			text=joined(text,(if verb=="bid" then "The order book is full; " else "No sell offer at or below "..price.."; ")..rest.." unfilled, coins returned.")
		end
	elseif verb=="offer" or verb=="sellToBid" then
		local filled,value=take(book,uid,"sell",qty,price)
		coins=value
		local rest=qty-filled
		if filled>0 then changed=true;text="Sold "..filled.." "..name.." for "..value.." coins." end
		if rest>0 and verb=="offer" and room then
			book.nextId+=1
			insertOrder(book.asks,{id=book.nextId,owner=uid,price=price,qty=rest},false)
			changed=true
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
		if found then changed=true end
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
		changed=true
		units+=claim.units
		coins+=claim.coins
		text=joined(text,"Collected "..claim.units.." "..name.." and "..claim.coins.." coins from filled orders.")
	elseif verb=="bidClaim" then
		text="Nothing to collect yet."
	end
	return {coins=coins,items=if units>0 then {[order.item]=units} else {},text=text,changed=changed}
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
	purgeExpired(book,now)
	local coins,items,text,changed=0,{},"",false
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
			changed=true
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
			changed=true
			text="Bought "..itemName(listing.item).." for "..listing.price.." coins."
		end
	elseif verb=="ahCancel" then
		if listing and listing.seller==uid then
			table.remove(book.listings,index)
			give(listing.item,1)
			changed=true
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
		changed=true
		coins+=proceeds
		text=joined(text,"Collected "..proceeds.." coins of sales and "..returned.." expired item"..(if returned==1 then "" else "s")..".")
	elseif verb=="ahClaim" then
		text="Nothing to collect in this category yet."
	end
	return {coins=coins,items=items,text=text,changed=changed}
end
-- Has uid anything to collect in this book right now?
local function collectable(book,kind,uid,now)
	if kind=="bazaar" then
		local claim=book.claims[uid]
		return claim~=nil and ((claim.units or 0)>0 or (claim.coins or 0)>0)
	end
	if (book.proceeds[uid] or 0)>0 then return true end
	if type(book.returns[uid])=="table" and next(book.returns[uid]) then return true end
	for _,l in ipairs(book.listings) do if l.seller==uid and l.expires<=now then return true end end
	return false
end
-- One write transform for both books. outcome.kind: "applied" (receipt written),
-- "replay" (this order's receipt already exists), "noop" (no effect: refund locally),
-- "full" (no slot for a new trader) or "stale" (a legacy order superseded by its receipt).
local function transact(old,kind,uid,order,now)
	local book=if kind=="bazaar" then normalizeBazaar(old) else normalizeAuction(old)
	local receipt=book.receipts[uid]
	if alreadyApplied(receipt,order) then
		return nil,{kind=if receiptMatches(receipt,order) then "replay" else "stale",book=book,receipt=receipt}
	end
	local busy=busyTraders(book,kind)
	local admitted,evict=admission(book,kind,uid,now,busy)
	local result=if kind=="bazaar" then bazaarTrade(book,uid,order) else auctionTrade(book,uid,order,now)
	if not result.changed then return nil,{kind="noop",book=book,text=result.text} end
	if not admitted then return nil,{kind="full",book=book} end
	if evict then book.receipts[evict]=nil end
	receipt={seq=order.seq,n=order.nonce,coins=result.coins,items=result.items,at=now,text=result.text}
	book.receipts[uid]=receipt
	prune(book,kind,uid,now,busyTraders(book,kind))
	book.revision+=1
	return book,{kind="applied",book=book,receipt=receipt}
end
Econ.transact=transact
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
		if Progression.isUpgraded(p,id) then return nil,"Upgraded gear cannot be auctioned: reforges, stars and tomes stay bound to your journal." end
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
local function remember(player,order,book,uid,now)
	local views=Econ.views[player] or {}
	Econ.views[player]=views
	if order.kind=="bazaar" then
		views.bazaar=bazaarView(book,order.item,uid,now)
	else
		local page=if views.auction and views.auction.category==order.cat then views.auction.page else 1
		views.auction=auctionView(book,order.cat,uid,page,now)
	end
end
-- Rebuilds this journal's mirror of its open orders/listings in one book.
local function remirror(p,order,book,uid)
	local orders,listings=mirror(p)
	local kept={}
	if order.kind=="bazaar" then
		for _,o in ipairs(orders) do if o.item~=order.item then table.insert(kept,o) end end
		for _,o in ipairs(ownOrders(book,uid,true)) do table.insert(kept,{item=order.item,id=o[1],price=o[2],qty=o[3],side=if o[4]==1 then "bid" else "ask"}) end
		p.econOrders=kept
	else
		for _,l in ipairs(listings) do if l.cat~=order.cat then table.insert(kept,l) end end
		for _,l in ipairs(ownListings(book,uid)) do table.insert(kept,{cat=order.cat,id=l[1],item=l[2],price=l[3],expires=l[4]}) end
		p.econListings=kept
	end
end
local function settle(player)
	local p=profiles[player]
	local order=p.econPending
	if not persist(player,false) then return "Market waiting for a journal save. Try again." end
	local uid=tostring(player.UserId)
	local now=os.time()
	local outcome
	local function apply(old)
		outcome=nil
		local book,result=transact(old,order.kind,uid,order,now)
		outcome=result
		return book
	end
	local ok=pcall(function()
		if preview[player] then
			local committed=apply(deepCopy(previewEcon[order.key]))
			if committed then previewEcon[order.key]=deepCopy(committed) end
		else
			store:UpdateAsync(order.key,apply)
		end
	end)
	if not ok or not outcome then return "Order pending. The exchange will retry safely." end
	if not preview[player] then rememberBook(order.key,outcome.book) end
	if outcome.kind=="noop" then
		refund(p,order)
		p.econPending=nil
		remirror(p,order,outcome.book,uid)
		remember(player,order,outcome.book,uid,now)
		return outcome.text
	elseif outcome.kind~="applied" and outcome.kind~="replay" then
		refund(p,order)
		p.econPending=nil
		return "This market is at capacity. Your escrow was returned."
	end
	local receipt=outcome.receipt
	p.coins+=tonumber(receipt.coins) or 0
	for id,n in pairs(receipt.items or {}) do
		if Data.Items[id] and n>0 then p.items[id]=(p.items[id] or 0)+n end
	end
	remirror(p,order,outcome.book,uid)
	p.econPending=nil
	remember(player,order,outcome.book,uid,now)
	return receipt.text or "Recovered order settled."
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
	local ok,book
	if preview[player] then ok,book=true,deepCopy(previewEcon[key]) else ok,book=cachedBook(player,key) end
	if not ok then return book or "The ledger could not be read. Your previous view may be stale." end
	Econ.reads[player]=os.clock()+READ_INTERVAL
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
-- Orders carry a random nonce so a rolled-back journal (whose econSeq restarts)
-- can never settle against, or be skipped because of, an older receipt.
local function newNonce()
	local guid=string.gsub(HttpService:GenerateGUID(false),"[^%w]","")
	return string.sub(guid,1,16)
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
	-- A claim with nothing to collect never writes: answer it from the shared
	-- read cache (or one GetAsync), and refresh the trader's view.
	if not pending and (verb=="bidClaim" or verb=="ahClaim") then
		local ok,book
		if preview[player] then ok,book=true,deepCopy(previewEcon[order.key]) else ok,book=cachedBook(player,order.key) end
		if not ok then return book or "The ledger could not be read. Try again shortly." end
		local now=os.time()
		local kind=order.kind
		book=if kind=="bazaar" then normalizeBazaar(book) else normalizeAuction(book)
		if not collectable(book,kind,tostring(player.UserId),now) then
			remember(player,order,book,tostring(player.UserId),now)
			return if kind=="bazaar" then "Nothing to collect yet." else "Nothing to collect in this category yet."
		end
	end
	if not resume then
		local allowed,wait=spendMarketBudget(player,2)
		if not allowed then return marketBusy(wait) end
	end
	if not pending then
		p.coins-=order.coins
		if order.units>0 then p.items[order.item]-=order.units end
		p.started=true
		p.econSeq=(tonumber(p.econSeq) or 0)+1
		order.seq=p.econSeq
		order.nonce=newNonce()
		order.at=os.time()
		p.econPending=order
	end
	exchangeReady[player]=os.clock()+EXCHANGE_COOLDOWN
	exchangeBusy[player]=true
	local ok,message=pcall(settle,player)
	exchangeBusy[player]=nil
	if not ok then message="Exchange delayed. Retry to recover your order." end
	if p.econPending and not preview[player] then
		-- Retry an ambiguous order soon, so its receipt is consumed while it is fresh.
		local stuck=p.econPending
		task.delay(30,function()
			if player.Parent and profiles[player]==p and p.econPending==stuck and Econ.resume then Econ.resume(player) end
		end)
	end
	if ok and pending and not resume and not p.econPending then message="Recovered your earlier order first: "..message end
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
