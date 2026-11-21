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
-- Pets depth (held items, candy, Roost upgrades, ability hooks); filled in by the Pets block before perform().
local Pets={verbs={}}
-- Dungeon classes (class choice, Master Mode, class XP); filled in by the Classes block beside the expedition grant.
local Classes={verbs={}}
-- Dungeon endgame (bonus chest, Master stars, Essence Exchange, run log); filled in by the Delve block beside the expedition grant.
local Delve={verbs={}}
-- Treasure Trails (clue scrolls, steps, caskets); filled in by the Trails block after Prayer & Thieving.
local Trails={verbs={trailBegin=true,trailAbandon=true,trailDig=true,trailSearch=true,trailEmote=true,trailSlide=true,trailCheck=true,trailOpen=true,trailTeleport=true,trailLearn=true,trailBanner=true}}
-- Commissions & Logs (commissions, Forgeheart, Collection Log, Museum); filled in by the Logs block after Slayer tasks.
local Logs={verbs={commissionClaim=true,commissionClaimAll=true,forgeBuy=true,logClaim=true,logTitle=true,museumDonate=true,logsBoard=true,logsSync=true}}
-- Crafting (gem cutting, jewellery, leather, glass); filled in by the Crafting block before perform().
local Crafting={verbs={craftStation=true,craftBatch=true,craftStop=true},jobs={},visits={},seq={}}
-- Lairs (instanced lair bosses: altars, fees, kill rewards); filled in by the Lairs block after Endgame.
local Lairs={verbs={lairEnter=true,lairLeave=true}}
-- One-time coins for each newly reached skill level.
local function levelCoins(p,skill,newLevel)
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
-- Every XP grant: OSRS curve with cap, active pet share, one-time level coins.
-- source (optional): "worker" for idle worker claims, which skip every pet
-- hook (the pet's player-XP multiplier, its XP share and Taming, skilling-pet
-- rolls); pets reward the player's own active play only.
local function grantXp(p,skill,amount,source)
	if not Data.Skills[skill] or type(amount)~="number" or amount<=0 then return end
	if source=="worker" then
		local _,newLevel=Progression.addXp(p,skill,amount)
		return levelCoins(p,skill,newLevel)
	end
	-- Pets depth: the summoned pet's XP abilities raise the player's grant; the
	-- pet itself shares the base amount, and its gain trains Taming.
	local _,newLevel=Progression.addXp(p,skill,amount*Progression.petSkillXpMult(p,skill))
	local pet,petDef=Progression.activePet(p)
	local petLevel=pet and pet.level
	-- Taming is earned from pets, so it never feeds them back.
	local petGain=0
	if skill~="Taming" then _,petGain=Progression.addPetXp(p,skill,amount) end
	if pet and pet.level>petLevel then note(p,petDef.name.." pet level "..pet.level.."!") end
	if Pets.tamingShare and (petGain or 0)>0 then Pets.tamingShare(p,petGain) end
	if Pets.skillRoll then Pets.skillRoll(p,skill,amount) end
	levelCoins(p,skill,newLevel)
end
local function collect(p,item,count)
	p.items[item]=(p.items[item] or 0)+count
	p.collection[item]=(p.collection[item] or 0)+count
	if Logs.collect then Logs.collect(p,item,count) end -- Commissions & Logs: Collection Log credit
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
	function Gear.view(p) return {reforges=p.reforges,stars=p.stars,books=p.books,masterStars=p.masterStars} end -- masterStars: Dungeon endgame
end
-- Workers depth (Data.Workers): up to 12 slots unlocked by unique worker crafts,
-- a type per gathering resource tier plus combat workers, fuel, two upgrade
-- slots, a chest, Condensed/Radiant pressing and an auto-seller. Output is
-- settled lazily from server os.time() (Data.Workers.settle), capped by storage
-- and Data.Workers.MAX_ACCRUAL; claims empty the store exactly once.
-- Worker record: {resource=typeId, tier, lastClaim, carry, store={id=n}, made,
-- coins, bonusCarry, fuel={id,expires|permanent}, upgrades={id|false,id|false}, chest}.
local Workers={verbs={}}
do
	local W=Data.Workers
	for _,verb in ipairs({"worker","workerBuild","workerResource","workerAssign","workerUpgrade","claim","workerClaim","workerClaimAll",
		"workerFuel","workerUnfuel","workerInstall","workerRemove","workerBlueprint"}) do Workers.verbs[verb]=true end
	local function int(n,lo,hi)
		n=tonumber(n)
		return n~=nil and n==n and n%1==0 and n>=lo and n<=hi
	end
	local function haste(p) return math.clamp(tonumber(p and p.perkWorkerHaste) or 0,0,Data.MAX_WORKER_HASTE) end
	-- Sanitise one stored record; nil when unusable.
	local function clean(w,now)
		if type(w)~="table" then return nil end
		local out={resource=if W.TypeById[w.resource] then w.resource else "Ore"}
		out.tier=math.clamp(math.floor(tonumber(w.tier) or 1),1,#Data.WorkerTiers)
		local last=tonumber(w.lastClaim)
		out.lastClaim=if last and last==last then math.min(math.floor(last),now) else now
		out.carry=if int(w.carry,0,1e9) then w.carry else 0
		out.made=if int(w.made,0,W.MAX_STORE*W.RATIO) then w.made else 0
		out.coins=if int(w.coins,0,1e12) then w.coins else 0
		out.bonusCarry=if int(w.bonusCarry,0,1000) then w.bonusCarry else 0
		out.collectCarry=if int(w.collectCarry,0,W.COMBAT_COLLECTION_DIV-1) then w.collectCarry else 0
		out.store={}
		local output=W.TypeById[out.resource].output
		local press=W.Press[output]
		local allowed={[output]=true,[press.condensed]=true,[press.radiant]=true}
		for _,u in pairs(W.Upgrades) do if u.bonus then allowed[u.bonus.item]=true end end
		if type(w.store)=="table" then
			for id,n in pairs(w.store) do
				if allowed[id] and int(n,1,W.MAX_STORE) then out.store[id]=n end
			end
		end
		local fuel=type(w.fuel)=="table" and W.Fuels[w.fuel.id]
		if fuel then
			if fuel.permanent then out.fuel={id=fuel.id,permanent=true}
			elseif int(w.fuel.expires,0,now+fuel.duration*W.FUEL_STACK) then out.fuel={id=fuel.id,expires=w.fuel.expires} end
		end
		out.upgrades={false,false}
		local groups={}
		if type(w.upgrades)=="table" then
			for i=1,W.UPGRADE_SLOTS do
				local u=W.Upgrades[w.upgrades[i]]
				if u and not groups[u.group] then groups[u.group]=true; out.upgrades[i]=u.id end
			end
		end
		out.chest=if W.Chests[w.chest] then w.chest else nil
		return out
	end
	-- Fleet with one-time migration of pre-fleet saves and bounded sanitising.
	function Workers.fleet(p)
		if not p.workers then
			p.workers={}
			if p.worker then p.workers[1]={resource=p.workerResource or "Ore",tier=1,lastClaim=p.lastClaim} end
		end
		if not p.workersClean then
			local now=os.time()
			local fleet={}
			if type(p.workers)=="table" then
				for slot=1,W.MAX_SLOTS do
					local w=clean(p.workers[slot],now)
					if not w then break end
					fleet[slot]=w
				end
			end
			p.workers=fleet
			if type(p.workerUniques)~="table" then
				-- First depth load: credit every tier the legacy workers already reached.
				p.workerUniques={}
				for _,w in ipairs(fleet) do for t=1,w.tier do W.addUnique(p.workerUniques,w.resource,t) end end
			else
				local uniques={}
				for typeId,mask in pairs(p.workerUniques) do
					if W.TypeById[typeId] and int(mask,1,2^#Data.WorkerTiers-1) then uniques[typeId]=mask end
				end
				p.workerUniques=uniques
			end
			-- Session-only flag (stripped before saving) so sanitising runs once per load.
			p.workersClean=true
		end
		return p.workers
	end
	function Workers.migrate(p) p.workersClean=nil; Workers.fleet(p) end
	function Workers.slots(p) return W.slotsFor(W.uniqueCount(p.workerUniques)) end
	function Workers.allowed(p,typeId)
		local t=type(typeId)=="string" and W.TypeById[typeId]
		if not t then return false,"Choose a gathering resource such as Ore, Timber, Herb or Fish, or a combat worker." end
		if t.collectionTier<=0 then return true end
		local name=if t.kind=="gather" then Data.Items[t.output].name else t.name
		if level(p.xp[t.skill])<t.level then return false,name.." workers require "..t.skill.." "..t.level.."." end
		if Progression.collectionTier(p,t.output)<t.collectionTier then
			return false,"Reach "..Data.Items[t.output].name.." collection tier "..t.collectionTier.." ("..Progression.collectionThreshold(t.output,t.collectionTier).." lifetime) to assign workers."
		end
		-- Region-exclusive resources: the region must be unlocked (Workers.regionAllowed
		-- is bound to regionAllowed once that local is defined below).
		if t.region and not (Workers.regionAllowed and Workers.regionAllowed(p,t.region)) then
			local region=Data.RegionById[t.region]
			return false,name.." workers require "..(region and region.name or t.region).." to be unlocked."
		end
		return true
	end
	-- Why the worker in `slot` cannot run right now (nil when it works): its type
	-- is no longer allowed, or earlier slots already fill the type/combat cap.
	-- Idle workers keep their stored output but produce nothing.
	function Workers.idle(p,slot)
		local fleet=Workers.fleet(p)
		local w=fleet[slot]
		if not w then return nil end
		local allowed,why=Workers.allowed(p,w.resource)
		if not allowed then return why end
		return W.capReason(fleet,slot,w.resource,false)
	end
	local function settle(p,w)
		local now=os.time()
		local slot=table.find(Workers.fleet(p),w)
		local idle=slot and Workers.idle(p,slot)
		if idle then
			w.store=w.store or {}
			w.lastClaim=now; w.carry=0
			if W.activeFuel(w,now)==nil then w.fuel=nil end
			return 0
		end
		return W.settle(w,now,haste(p))
	end
	function Workers.ready(p)
		local w=Workers.fleet(p)[1]
		if not w then return 0 end
		settle(p,w)
		return W.storeCount(w.store)
	end
	local function costText(cost)
		local parts={}
		for id,n in pairs(cost) do table.insert(parts,n.." "..(Data.Items[id] and Data.Items[id].name or id)) end
		table.sort(parts)
		return table.concat(parts,", ")
	end
	function Workers.state(p)
		local now,h=os.time(),haste(p)
		local result={}
		for slot,w in ipairs(Workers.fleet(p)) do
			settle(p,w)
			local idle=Workers.idle(p,slot)
			local t=W.TypeById[w.resource]
			local fuel=W.activeFuel(w,now)
			local press,sell,bonus=W.effects(w)
			local cap=W.capacity(w)
			local stored=W.storeCount(w.store)
			result[slot]={slot=slot,resource=w.resource,name=t.name,kind=t.kind,output=t.output,tier=w.tier,maxTier=#Data.WorkerTiers,
				ready=stored,capacity=cap,interval=W.interval(w.resource,w.tier,h),speed=W.speedPercent(w,now),
				perHour=if idle then 0 else math.floor(W.perHour(w,now,h)*10+0.5)/10,full=stored>=cap,store=table.clone(w.store),coins=w.coins or 0,
				fuel=fuel and {id=fuel.id,permanent=fuel.permanent,speed=fuel.speed,remaining=if fuel.permanent then nil else w.fuel.expires-now} or nil,
				upgrades={w.upgrades[1] or false,w.upgrades[2] or false},chest=w.chest,press=press,autoSell=sell~=nil,bonus=bonus and bonus.item or nil,
				upgradeCost=if w.tier<#Data.WorkerTiers then W.upgradeCost(w.tier+1,w.resource) else nil,idle=idle}
		end
		return result
	end
	function Workers.info(p)
		local count=W.uniqueCount(p.workerUniques)
		return {slots=Workers.slots(p),maxSlots=W.MAX_SLOTS,uniques=count,nextAt=W.nextSlotAt(count),crafted=table.clone(p.workerUniques or {}),
			built=#Workers.fleet(p),buildCost=if #p.workers<W.MAX_SLOTS then W.buildCost(#p.workers+1) else nil}
	end
	local function record(p,typeId,tier)
		local before=Workers.slots(p)
		if W.addUnique(p.workerUniques,typeId,tier) then
			local after=Workers.slots(p)
			if after>before then note(p,"Unique worker crafts "..W.uniqueCount(p.workerUniques).."! Worker slot "..after.." unlocked.") end
			return true
		end
		return false
	end
	Workers.record=record
	-- Credit stored output to the satchel; Condensed/Radiant forms count their
	-- raw units toward the raw collection. Returns items, resource, xp, coins.
	function Workers.claim(p,slot)
		local w=Workers.fleet(p)[slot or 1]
		if not w then return 0,"Ore",0,0 end
		settle(p,w)
		local t=W.TypeById[w.resource]
		local count=0
		local store=w.store
		w.store={}
		local ids={}
		for id in pairs(store) do table.insert(ids,id) end
		table.sort(ids)
		for _,id in ipairs(ids) do
			local n=store[id]
			count+=n
			local source=W.PressSource[id]
			if t.kind=="combat" then
				-- Combat-worker output credits its collection at 1/COMBAT_COLLECTION_DIV
				-- (25%); the remainder carries to the next claim.
				local raw=if source then source.raw else id
				local units=n*(if source then source.units else 1)
				p.items[id]=(p.items[id] or 0)+n
				if raw==t.output then
					local total=(w.collectCarry or 0)+units
					w.collectCarry=total%W.COMBAT_COLLECTION_DIV
					units=total
				end
				p.collection[raw]=(p.collection[raw] or 0)+units//W.COMBAT_COLLECTION_DIV
				collect(p,raw,0)
			elseif source then
				p.items[id]=(p.items[id] or 0)+n
				p.collection[source.raw]=(p.collection[source.raw] or 0)+n*source.units
				collect(p,source.raw,0)
			else
				collect(p,id,n)
			end
		end
		local xp=(w.made or 0)*t.xp
		w.made=0
		if xp>0 then grantXp(p,t.skill,xp,"worker") end -- Pets depth: no pet hooks on idle XP
		local coins=w.coins or 0
		w.coins=0
		w.sold=nil
		if coins>0 then p.coins+=coins end
		if slot==1 or slot==nil then p.lastClaim=w.lastClaim; p.workerResource=w.resource end
		return count,w.resource,xp,coins
	end
	local function slotOf(p,raw)
		local slot=tonumber(raw)
		if not int(slot,1,W.MAX_SLOTS) then return nil end
		return slot,Workers.fleet(p)[slot]
	end
	local function split(item)
		if not validId(item) then return nil end
		return string.match(item,"^(%d+):(%w+)$")
	end
	local function restart(p,slot,w)
		w.lastClaim=os.time(); w.carry=0
		if slot==1 then p.lastClaim=w.lastClaim end
	end
	function Workers.action(player,p,verb,item)
		local fleet=Workers.fleet(p)
		if verb=="workerResource" or verb=="workerAssign" then
			local slot,typeId=1,item
			if verb=="workerAssign" then
				local raw,name=split(item)
				slot,typeId=tonumber(raw),name
			end
			local w=int(slot,1,W.MAX_SLOTS) and fleet[slot]
			if not w then return "Build this worker first." end
			local allowed,why=Workers.allowed(p,typeId)
			if not allowed then return why end
			if typeId==w.resource then return "Worker already gathering "..typeId.."." end
			local capped=W.capReason(fleet,slot,typeId,true)
			if capped then return capped end
			local count,previous=Workers.claim(p,slot)
			w.resource=typeId
			w.collectCarry=0
			restart(p,slot,w)
			if slot==1 then p.workerResource=typeId end
			return "Worker "..slot.." now "..W.TypeById[typeId].name.." • collected "..count.." "..previous.."."
		elseif verb=="worker" or verb=="workerBuild" then
			local raw,typeId=if verb=="worker" then "1" else item,nil
			if verb=="workerBuild" and validId(item) and string.find(item,":",1,true) then raw,typeId=split(item) end
			local slot=tonumber(raw)
			local unlocked=Workers.slots(p)
			if not int(slot,1,W.MAX_SLOTS) then return "Choose a worker slot from 1 to "..W.MAX_SLOTS.."." end
			if fleet[slot] then return "This worker is already active." end
			if slot~=#fleet+1 then return "Build the previous worker first." end
			if slot>unlocked then
				return "Worker slot "..slot.." unlocks at "..W.SlotUniques[slot-W.BASE_SLOTS].." unique worker crafts (you have "..W.uniqueCount(p.workerUniques)..")."
			end
			typeId=typeId or "Ore"
			local allowed,why=Workers.allowed(p,typeId)
			if not allowed then return why end
			local capped=W.capReason(fleet,slot,typeId,true)
			if capped then return capped end
			local cost=W.buildCost(slot)
			if not spend(p,cost) then return "Worker needs "..cost.Timber.." Timber and "..cost.Ore.." Ore." end
			fleet[slot]={resource=typeId,tier=1,lastClaim=os.time(),carry=0,store={},made=0,coins=0,bonusCarry=0,upgrades={false,false}}
			record(p,typeId,1)
			p.worker=true
			p.started=true
			if slot==1 then p.lastClaim=os.time(); p.workerResource=typeId end
			return "Worker "..slot.." built • "..W.TypeById[typeId].name.." gathers 1 every "..W.interval(typeId,1,haste(p)).." s, including offline."
		elseif verb=="workerUpgrade" then
			local slot,w=slotOf(p,item)
			if not w then return "Build this worker first." end
			if w.tier>=#Data.WorkerTiers then return "Worker is at maximum tier." end
			local tier=w.tier+1
			local cost=W.upgradeCost(tier,w.resource)
			if not spend(p,cost) then return "Upgrade needs "..costText(cost).."." end
			Workers.claim(p,slot)
			w.tier=tier
			restart(p,slot,w)
			record(p,w.resource,tier)
			return "Worker "..slot.." upgraded to tier "..tier..". Completed output collected; new cycle started."
		elseif verb=="claim" or verb=="workerClaim" then
			local slot=if verb=="claim" then 1 else tonumber(item)
			if not int(slot,1,W.MAX_SLOTS) or not fleet[slot] then return "Build this worker first." end
			local n,typeId,xp,coins=Workers.claim(p,slot)
			if n<1 and coins<1 then return "Next resource is still being gathered." end
			local t=W.TypeById[typeId]
			return "Collected "..n.." worker "..t.output..(coins>0 and (" and "..coins.." auto-sold coins") or "").." • +"..xp.." "..t.skill.." XP."
		elseif verb=="workerClaimAll" then
			local items,coins=0,0
			for slot in ipairs(fleet) do
				local n,_,_,c=Workers.claim(p,slot)
				items+=n; coins+=c
			end
			if items<1 and coins<1 then return "Your workers are still gathering." end
			return "Collected "..items.." items"..(coins>0 and (" and "..coins.." coins") or "").." from "..#fleet.." workers."
		elseif verb=="workerFuel" then
			-- "slot:FuelId" or "slot:FuelId:n" (n burns of the same fuel, 1..64).
			local raw,fuelId,amount
			if validId(item) then raw,fuelId,amount=string.match(item,"^(%d+):(%w+):?(%d*)$") end
			local slot,w=slotOf(p,raw)
			if not w then return "Build this worker first." end
			local f=W.Fuels[fuelId]
			if not f then return "Choose a worker fuel." end
			local n=if amount and amount~="" then tonumber(amount) else 1
			if not int(n,1,W.FUEL_STACK) or (f.permanent and n~=1) then return "Add between 1 and "..W.FUEL_STACK.." fuel at a time." end
			if (p.items[fuelId] or 0)<n then return "You need "..n.." "..Data.Items[fuelId].name.."." end
			settle(p,w)
			local now=os.time()
			local active=W.activeFuel(w,now)
			if active and active.id~=fuelId then return "Worker "..slot.." is burning "..Data.Items[active.id].name..". Remove it or let it burn out first." end
			if f.permanent then
				if active then return "Worker "..slot.." already holds "..Data.Items[fuelId].name.."." end
				p.items[fuelId]-=n
				w.fuel={id=fuelId,permanent=true}
				return "Worker "..slot.." fuelled with "..Data.Items[fuelId].name.." • +"..f.speed.."% speed, permanently."
			end
			local from=if active then w.fuel.expires else now
			local expires=from+f.duration*n
			if expires-now>f.duration*W.FUEL_STACK then return "Worker "..slot.." can hold at most "..W.FUEL_STACK.." "..Data.Items[fuelId].name.."." end
			p.items[fuelId]-=n
			w.fuel={id=fuelId,expires=expires}
			return "Worker "..slot.." fuelled • +"..f.speed.."% speed for "..math.floor((expires-now)/60+0.5).." min."
		elseif verb=="workerUnfuel" then
			local slot,w=slotOf(p,item)
			if not w then return "Build this worker first." end
			settle(p,w)
			local f=W.activeFuel(w,os.time())
			if not f then w.fuel=nil; return "Worker "..slot.." has no fuel." end
			w.fuel=nil
			if f.permanent then
				p.items[f.id]=(p.items[f.id] or 0)+1
				return "Removed "..Data.Items[f.id].name.." from worker "..slot.." (returned to your satchel)."
			end
			return "Worker "..slot.." fuel removed. Burnt fuel is not returned."
		elseif verb=="workerInstall" then
			local raw,partId=split(item)
			local slot,w=slotOf(p,raw)
			if not w then return "Build this worker first." end
			local u,chest=W.Upgrades[partId],W.Chests[partId]
			if not u and not chest then return "Choose a worker upgrade or chest." end
			if (p.items[partId] or 0)<1 then return "You need a "..Data.Items[partId].name.."." end
			settle(p,w)
			if chest then
				if w.chest==partId then return "Worker "..slot.." already has a "..Data.Items[partId].name.."." end
				p.items[partId]-=1
				local old=w.chest
				if old then p.items[old]=(p.items[old] or 0)+1 end
				w.chest=partId
				return "Installed "..Data.Items[partId].name.." on worker "..slot.." • storage "..W.capacity(w).."."..(old and (" "..Data.Items[old].name.." returned.") or "")
			end
			local free
			for i=1,W.UPGRADE_SLOTS do
				local current=W.Upgrades[w.upgrades[i]]
				if current and current.group==u.group then return "Worker "..slot.." already has a "..Data.Items[current.id].name.." (one of each kind)." end
				if not current and not free then free=i end
			end
			if not free then return "Worker "..slot.." has no free upgrade slot. Remove an upgrade first." end
			p.items[partId]-=1
			w.upgrades[free]=partId
			return "Installed "..Data.Items[partId].name.." on worker "..slot.."."
		elseif verb=="workerRemove" then
			-- "slot:1" / "slot:2" (upgrade slot) or "slot:chest".
			local raw,which=split(item)
			local slot,w=slotOf(p,raw)
			if not w then return "Build this worker first." end
			settle(p,w)
			local id
			if which=="chest" then id=w.chest; w.chest=nil
			elseif which=="1" or which=="2" then id=w.upgrades[tonumber(which)] or nil; w.upgrades[tonumber(which)]=false
			else return "Choose upgrade slot 1, 2 or the chest." end
			if not id then return "Nothing installed there." end
			p.items[id]=(p.items[id] or 0)+1
			return "Removed "..Data.Items[id].name.." from worker "..slot.." (returned to your satchel)."
		elseif verb=="workerBlueprint" then
			-- "TypeId:tier": draft a unique worker (counts toward slots) without building it.
			local typeId,rawTier
			if validId(item) then typeId,rawTier=string.match(item,"^(%w+):(%d)$") end
			local tier=tonumber(rawTier)
			local t=typeId and W.TypeById[typeId]
			if not t or not int(tier,1,#Data.WorkerTiers) then return "Choose a worker type and tier 1-"..#Data.WorkerTiers.."." end
			local allowed,why=Workers.allowed(p,typeId)
			if not allowed then return why end
			if W.hasUnique(p.workerUniques,typeId,tier) then return t.name.." tier "..tier.." is already crafted." end
			if tier>1 and not W.hasUnique(p.workerUniques,typeId,tier-1) then return "Craft "..t.name.." tier "..(tier-1).." first." end
			local cost=W.blueprintCost(typeId,tier)
			if not spend(p,cost) then return "Blueprint needs "..costText(cost).."." end
			record(p,typeId,tier)
			p.started=true
			return "Crafted unique "..t.name.." tier "..tier.." • "..W.uniqueCount(p.workerUniques).." unique worker crafts."
		end
		return "Unknown worker action."
	end
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
Workers.regionAllowed=regionAllowed -- Workers depth: region-exclusive worker types
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
		player:SetAttribute("FastTravelAt",os.clock()) -- server-driven movement (Aether Mote pickup checks)
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
		Trails.event(p,"catch",creature.id) -- Treasure Trails: scroll drops + trail tasks
		Logs.event(p,"catch",creature.id) -- Commissions & Logs: Hunter commissions
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
------------------------------------------------------------------------------
-- Prayer & Thieving (Prayer & Thieving team). Rules and data: Data.Prayer,
-- Data.Thieving (shared/GameData.lua); world prompts: world.server.lua.
-- Verbs (item <= 64 chars):
--   prayer "<id>"            toggle a prayer (Prayer level, points > 0); prayers
--                            sharing a group with it switch off
--   prayerOff                every prayer off
--   prayerQuick "<slot>:<id>" | "<slot>:"  HUD favourite slot 1-2 (empty clears)
--   offerRemains "<remains>" offer a batch of that remains at the altar visited in
--                            the last PR.ALTAR_SECONDS (atlas Prayer page)
--   consume "<draught>"      Devotion Draught / Choir Tonic restore prayer points
--                            (claimed before the generic consume)
-- Prompts (server-validated, IsleItem + matching prompt attribute):
--   altarOffer  IsleItem altar id (PrayerAltar): offers PR.BATCH of the best remains
--               held (one rite per PR.RITE_SECONDS each); holding none, it prays
--   altarPray   IsleItem altar id (PrayerAltar): restores prayer points to max
--   thieve      IsleItem target id (ThievingTarget): stall, mark or strongbox
-- Drain is time-based (PR.charge, cut by Devotion): p.prayer.since (os.clock)
-- marks the last settle; every tick, toggle, prayerOff, draught and altar prayer
-- first charges the elapsed time for the prayers active during it. Switching a
-- prayer on pays PR.activationCost (one tick of its drain) up front as prepaid
-- credit (p.prayer.credit), so flicking is never free. Every PR.TICK s Mending
-- Hymn heals and Amber Vigil pushes buff expiries back; at 0 points every
-- prayer switches off (snapshot notice). Active prayers are cleared on load;
-- points persist (p.prayer.points).
-- Bridge: "stats" adds prayer = Prayer.combat(p) = {protect, offence={style=fraction},
-- sap, mana (regen multiplier), defence %} | nil; "damage" applies protection
-- (payload.style, payload.worldBoss) before defence and wards (defence x (1+%)).
-- Thieving: success pays coins + loot + XP and starts that target's per-player
-- cooldown (respawn); failure stuns (no thieving, WalkSpeed 0) for target.stun
-- seconds and deals target.damage (never lethal). Cooldowns and the stun are
-- persisted (p.thieving.cooldowns = {[target] = os.time ready}, stunUntil =
-- os.time) so rejoining or hopping servers never resets them; the session
-- tables (os.clock) keep sub-second precision and are seeded from the save.
-- Player attributes: PrayerLevel, PrayerPoints (rounded up), PrayerMax, PrayerDrain
-- (points/min), PrayerActive / PrayerQuick ("Id,Id"), PrayerAltar + PrayerAltarUntil
-- (os.time), ThievingStunUntil (os.time). Snapshot keys: prayer, thieving.
-- All tables strong and player-keyed; Prayer.forget clears them.
------------------------------------------------------------------------------
local Prayer={verbs={prayer=true,prayerOff=true,prayerQuick=true,offerRemains=true,altarOffer=true,altarPray=true,thieve=true},
	riteUntil={},altarSeen={},stunUntil={},stunSeq={},cooldowns={}}
do
	local PR,TH=Data.Prayer,Data.Thieving
	local function whole(v,limit)
		local n=tonumber(v)
		if not n or n~=n or n<=0 then return nil end
		return math.floor(math.min(n,limit or 1e9))
	end
	local function prayerLevel(p) return level(p.xp.Prayer) end
	local function nameOf(id) return Data.Items[id] and Data.Items[id].name or tostring(id) end
	local function lootText(drops)
		local names={}
		for id,n in pairs(drops) do table.insert(names,"+"..n.." "..nameOf(id)) end
		table.sort(names)
		return if #names>0 then ", "..table.concat(names,", ") else ""
	end
	function Prayer.max(p) return PR.maxPoints(prayerLevel(p)) end
	-- Older saves gain empty records; tampered entries are dropped or clamped.
	function Prayer.migrate(p)
		local r=type(p.prayer)=="table" and p.prayer or {}
		local maxPoints=Prayer.max(p)
		local points=tonumber(r.points)
		if not points or points~=points then points=maxPoints end
		local quick={}
		for i=1,PR.QUICK_SLOTS do
			local id=type(r.quick)=="table" and r.quick[i]
			quick[i]=if type(id)=="string" and PR.PrayerById[id] then id else ""
		end
		local offered={}
		if type(r.offered)=="table" then
			for id,n in pairs(r.offered) do if PR.RemainsById[id] then offered[id]=whole(n) end end
		end
		p.prayer={points=math.clamp(points,0,maxPoints),quick=quick,offered=offered,active={},carry=0,credit={}}
		local saved=type(p.thieving)=="table" and p.thieving or {}
		local thefts={}
		if type(saved.thefts)=="table" then
			for id,n in pairs(saved.thefts) do if TH.TargetById[id] then thefts[id]=whole(n) end end
		end
		-- Cooldowns / stun: known targets only, expired entries pruned, never
		-- further out than that respawn / the longest stun (bounded, tamper-proof).
		local now=os.time()
		local cooldowns={}
		if type(saved.cooldowns)=="table" then
			for id,at in pairs(saved.cooldowns) do
				local t=TH.TargetById[id]
				at=tonumber(at)
				if t and at and at==at and at>now then cooldowns[id]=math.min(at,now+t.respawn) end
			end
		end
		local stun=tonumber(saved.stunUntil)
		p.thieving={thefts=thefts,cooldowns=cooldowns,stunUntil=if stun and stun==stun and stun>now then math.min(stun,now+TH.MAX_STUN) else nil}
	end
	-- Quest and diary checks: offerings {count, remains?}, thefts {target, count}.
	local measure=Journal.measure
	function Journal.measure(p,o)
		if type(o)=="table" and o.kind=="offerings" then
			local offered=p.prayer and p.prayer.offered or {}
			if o.remains then return offered[o.remains] or 0,o.count end
			local total=0
			for _,n in pairs(offered) do total+=n end
			return total,o.count
		elseif type(o)=="table" and o.kind=="thefts" then
			return (p.thieving and p.thieving.thefts[o.target]) or 0,o.count
		end
		return measure(p,o)
	end
	-- Favourites for the HUD: configured ids, else the best unlocked ward and the
	-- best unlocked offence prayer for the wielded style.
	function Prayer.quick(p)
		local lvl=prayerLevel(p)
		local style=Progression.weaponStyle(Data.Items[p.equipment and p.equipment.weapon or ""])
		local defaults={"",""}
		for _,def in ipairs(PR.Prayers) do
			if def.level<=lvl then
				if def.defence and not def.offence then defaults[1]=def.id end
				if def.offence and def.offence[style] and not def.defence then defaults[2]=def.id end
			end
		end
		local out={}
		for i=1,PR.QUICK_SLOTS do
			local id=p.prayer.quick[i]
			out[i]=if type(id)=="string" and id~="" then id else defaults[i]
		end
		return out
	end
	local function drainPerMinute(p,stats)
		return PR.drainPerSecond(p.prayer.active,(stats or Progression.computeStats(p,os.time())).devotion)*60
	end
	function Prayer.publish(player,p,stats)
		local r=p.prayer
		player:SetAttribute("PrayerLevel",prayerLevel(p))
		player:SetAttribute("PrayerMax",Prayer.max(p))
		player:SetAttribute("PrayerPoints",math.ceil(r.points-1e-6))
		player:SetAttribute("PrayerActive",table.concat(PR.list(r.active),","))
		player:SetAttribute("PrayerQuick",table.concat(Prayer.quick(p),","))
		player:SetAttribute("PrayerDrain",math.floor(drainPerMinute(p,stats)*10+.5)/10)
	end
	-- Charge the drain for the time since the last settle (prayers active during
	-- it, prepaid credit first) and stretch buffs under Amber Vigil. At 0 points
	-- every prayer switches off with a notice. Returns stats? and whether it emptied.
	function Prayer.settle(player,p,stats)
		local r=p.prayer
		local now=os.clock()
		if not next(r.active) then r.since=nil; r.credit={}; return stats,false end
		local seconds=math.max(0,now-(r.since or now))
		r.since=now
		r.credit=r.credit or {}
		if seconds<=0 then return stats,false end
		stats=stats or Progression.computeStats(p,os.time())
		local effects=PR.effects(r.active)
		local left,empty=PR.charge(r.points,r.active,r.credit,stats.devotion,seconds)
		r.points=left
		if effects.preserve>0 then
			r.carry=(r.carry or 0)+PR.preserveExtend(seconds,effects.preserve)
			local add=math.floor(r.carry)
			if add>=1 then
				r.carry-=add
				local wall=os.time()
				for _,buff in pairs(p.buffs or {}) do
					if type(buff)=="table" and buff.expires and buff.expires>wall then buff.expires+=add end
				end
			end
		end
		if empty then
			r.active,r.credit,r.since={},{},nil
			Prayer.publish(player,p,stats)
			if Prayer.push then Prayer.push(player,"You have run out of prayer points. Your prayers fade.") end
		end
		return stats,empty
	end
	function Prayer.toggle(player,p,id)
		local r=p.prayer
		local stats=Prayer.settle(player,p)
		stats=stats or Progression.computeStats(p,os.time())
		local verdict,active,dropped=PR.toggle(r.active,id,prayerLevel(p),r.points,stats.devotion)
		local def=PR.PrayerById[id]
		if verdict=="unknown" then return "Choose a prayer from your prayer book." end
		if verdict=="level" then return def.name.." requires Prayer "..def.level.."." end
		if verdict=="points" then
			if r.points>0 then return "Not enough prayer points for "..def.name.." (needs "..(math.ceil(PR.activationCost(id,stats.devotion)*100)/100)..")." end
			return "You have no prayer points left. Pray at an altar or drink a Devotion Draught."
		end
		r.credit=r.credit or {}
		for k in pairs(r.credit) do if not active[k] then r.credit[k]=nil end end
		if verdict=="on" then
			-- Activation: one tick of drain up front, held as prepaid credit.
			r.points=math.max(0,r.points-PR.activationCost(id,stats.devotion))
			r.credit[id]=PR.TICK
		end
		r.active=active
		r.since=if next(active) then os.clock() else nil
		Prayer.publish(player,p,stats)
		if verdict=="off" then return def.name.." off." end
		p.started=true
		local names={}
		for _,k in ipairs(dropped) do table.insert(names,PR.PrayerById[k].name) end
		return def.name.." on • draining "..(player:GetAttribute("PrayerDrain") or 0).." points/min"..(if #names>0 then " (replaces "..table.concat(names,", ")..")" else "")
	end
	function Prayer.quickSet(player,p,item)
		local slot,id
		if type(item)=="string" then slot,id=string.match(item,"^(%d):(%w*)$") end
		slot=tonumber(slot)
		if not slot or slot<1 or slot>PR.QUICK_SLOTS or (id~="" and not PR.PrayerById[id]) then return "Choose a quick prayer slot." end
		p.prayer.quick[slot]=id
		Prayer.publish(player,p)
		return if id=="" then "Quick prayer "..slot.." reset." else PR.PrayerById[id].name.." set as quick prayer "..slot.."."
	end
	-- One drain tick for a live profile: settle the elapsed time, then Mending
	-- Hymn heals (only prayers still on at the tick).
	function Prayer.step(player,p)
		local r=p.prayer
		if not r or not next(r.active) then return end
		local stats,empty=Prayer.settle(player,p)
		if empty then return end
		stats=stats or Progression.computeStats(p,os.time())
		local effects=PR.effects(r.active)
		local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if effects.heal>0 and humanoid and humanoid.Health>0 then
			humanoid.Health=math.min(humanoid.MaxHealth,humanoid.Health+humanoid.MaxHealth*effects.heal/100)
		end
		Prayer.publish(player,p,stats)
	end
	function Prayer.isRestore(item)
		local def=validId(item) and Data.Items[item]
		return def~=nil and def~=false and def.prayerRestore~=nil
	end
	function Prayer.drink(player,p,item)
		local def=Data.Items[item]
		if (p.items[item] or 0)<1 then return "You have no "..def.name.."." end
		local r=p.prayer
		local maxPoints=Prayer.max(p)
		Prayer.settle(player,p)
		if r.points>=maxPoints then return "Your prayer points are already full." end
		spend(p,{[item]=1})
		local before=r.points
		r.points=PR.restore(r.points,maxPoints,def)
		Prayer.publish(player,p)
		return def.name.." restored "..math.floor(r.points-before+.5).." prayer points."
	end
	-- Altars ------------------------------------------------------------------
	local function altarAt(item,prompt)
		local altar=validId(item) and PR.AltarById[item]
		if not altar or prompt:GetAttribute("PrayerAltar")~=item then return nil end
		return altar
	end
	local function visit(player,altar)
		local untilAt=os.time()+PR.ALTAR_SECONDS
		Prayer.altarSeen[player]={id=altar.id,untilAt=untilAt}
		player:SetAttribute("PrayerAltar",altar.id)
		player:SetAttribute("PrayerAltarUntil",untilAt)
	end
	function Prayer.pray(player,p,altar)
		local r=p.prayer
		local maxPoints=Prayer.max(p)
		Prayer.settle(player,p)
		if r.points>=maxPoints then return "You pray at the "..altar.name..". Your prayer points are full." end
		r.points=maxPoints
		Prayer.publish(player,p)
		p.started=true
		return "You pray at the "..altar.name..". Prayer points restored ("..maxPoints..")."
	end
	function Prayer.offer(player,p,altar,remainsId)
		local remains=PR.RemainsById[remainsId]
		if not remains then return "Offer remains at an altar." end
		local now=os.clock()
		local busy=Prayer.riteUntil[player]
		if busy and now<busy then return "The rite is still underway ("..math.ceil(busy-now).."s)." end
		local have=p.items[remainsId] or 0
		if have<1 then return "You have no "..remains.name.."." end
		local n=math.min(have,PR.BATCH)
		local xp=PR.offerXp(remainsId,altar.id,n)
		spend(p,{[remainsId]=n})
		grantXp(p,"Prayer",xp)
		p.prayer.offered[remainsId]=(p.prayer.offered[remainsId] or 0)+n
		Prayer.riteUntil[player]=now+n*PR.RITE_SECONDS
		p.started=true
		Prayer.publish(player,p)
		return "Offered "..n.." "..remains.name.." at the "..altar.name.." • +"..xp.." Prayer XP"
	end
	-- Thieving ----------------------------------------------------------------
	-- Session cooldowns / stun (os.clock), seeded once per session from the
	-- persisted wall-clock record so a rejoin or server hop resets nothing.
	local function sessionOf(player,p)
		local cds=Prayer.cooldowns[player]
		if cds then return cds end
		cds={}
		Prayer.cooldowns[player]=cds
		local now,wall=os.clock(),os.time()
		local saved=type(p.thieving)=="table" and p.thieving or {}
		for id,at in pairs(type(saved.cooldowns)=="table" and saved.cooldowns or {}) do
			if tonumber(at) and at>wall then cds[id]=now+(at-wall) end
		end
		if tonumber(saved.stunUntil) and saved.stunUntil>wall and not Prayer.stunUntil[player] then
			Prayer.stunUntil[player]=now+(saved.stunUntil-wall)
		end
		return cds
	end
	-- Persist a cooldown (id) or the stun (id nil) as os.time; expired entries
	-- are dropped on every write (bounded by TH.Targets).
	local function persist(p,id,seconds)
		local wall=os.time()
		local rec=p.thieving
		rec.cooldowns=type(rec.cooldowns)=="table" and rec.cooldowns or {}
		for k,at in pairs(rec.cooldowns) do if not TH.TargetById[k] or not tonumber(at) or at<=wall then rec.cooldowns[k]=nil end end
		if rec.stunUntil and (tonumber(rec.stunUntil) or 0)<=wall then rec.stunUntil=nil end
		if id then rec.cooldowns[id]=wall+seconds else rec.stunUntil=wall+seconds end
	end
	function Prayer.stunned(player) return os.clock()<(Prayer.stunUntil[player] or 0) end
	function Prayer.thieve(player,p,item,prompt,humanoid)
		if not prompt then return "Thieve at market stalls, marks and strongboxes around the isles." end
		local target=validId(item) and TH.TargetById[item]
		if not target or prompt:GetAttribute("ThievingTarget")~=item then return "There is nothing to take here." end
		local kind=TH.Kinds[target.kind]
		local lvl=level(p.xp.Thieving)
		if lvl<target.level then return target.name.." requires Thieving "..target.level.."." end
		if not regionAllowed(p,target.region) then return regionDenied(target.region) end
		local now=os.clock()
		local cds=sessionOf(player,p)
		if Prayer.stunned(player) then return "You are stunned ("..math.ceil(Prayer.stunUntil[player]-now).."s)." end
		if cds[target.id] and now<cds[target.id] then return "The "..target.name.." is "..kind.wait.." ("..math.ceil(cds[target.id]-now).."s)." end
		local stats=Progression.computeStats(p,os.time())
		local _,bonus=TH.gloves(p.items)
		local chance=TH.chance(target,lvl,bonus,stats.deftness)
		p.started=true
		if roll()<chance then
			local coins=TH.coins(target,roll)
			local drops=Progression.rollDrops(target.drops,stats.magicFind,roll,stats.petLuck)
			p.coins+=coins
			for id,n in pairs(drops) do collect(p,id,n) end
			grantXp(p,"Thieving",target.xp)
			p.thieving.thefts[target.id]=(p.thieving.thefts[target.id] or 0)+1
			Trails.event(p,"thieve",target.id) -- Treasure Trails: scroll drops + trail tasks
			cds[target.id]=now+target.respawn
			persist(p,target.id,target.respawn)
			return kind.past.." the "..target.name.." • +"..coins.." coins, +"..target.xp.." Thieving XP"..lootText(drops)
		end
		-- Caught: stunned in place (applyStats keeps WalkSpeed 0) and hurt, never killed.
		local seq=(Prayer.stunSeq[player] or 0)+1
		Prayer.stunSeq[player]=seq
		Prayer.stunUntil[player]=now+target.stun
		persist(p,nil,target.stun)
		player:SetAttribute("ThievingStunUntil",os.time()+math.ceil(target.stun))
		local damage=math.min(target.damage,math.max(0,math.floor(humanoid.Health-1)))
		if damage>0 then humanoid:TakeDamage(damage) end
		humanoid.WalkSpeed=0
		task.delay(target.stun,function()
			if Prayer.stunSeq[player]~=seq then return end
			Prayer.stunUntil[player]=nil
			local live=profiles[player]
			local current=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if live and current==humanoid then humanoid.WalkSpeed=Progression.walkSpeed(Progression.computeStats(live,os.time()).speed) end
		end)
		local who=if target.kind=="pocket" then "The "..target.name.." "..kind.fail else kind.fail
		return who.."! Stunned for "..target.stun.."s"..(if damage>0 then ", -"..damage.." health" else "").."."
	end
	-- Verbs -------------------------------------------------------------------
	function Prayer.claims(verb,item) return Prayer.verbs[verb]==true or (verb=="consume" and Prayer.isRestore(item)) end
	function Prayer.action(player,p,verb,item,prompt,humanoid)
		if verb=="prayer" then return Prayer.toggle(player,p,item)
		elseif verb=="prayerOff" then
			if not next(p.prayer.active) then return "No prayers are active." end
			local _,empty=Prayer.settle(player,p)
			if empty then return "Your prayers have already faded." end
			p.prayer.active,p.prayer.credit,p.prayer.since={},{},nil
			Prayer.publish(player,p)
			return "Every prayer off."
		elseif verb=="prayerQuick" then return Prayer.quickSet(player,p,item)
		elseif verb=="consume" then return Prayer.drink(player,p,item)
		elseif verb=="thieve" then return Prayer.thieve(player,p,item,prompt,humanoid)
		elseif verb=="altarOffer" or verb=="altarPray" then
			if not prompt then return "Visit an altar." end
			local altar=altarAt(item,prompt)
			if not altar then return "This altar is cold." end
			if not regionAllowed(p,altar.region) then return regionDenied(altar.region) end
			visit(player,altar)
			local best=verb=="altarOffer" and PR.bestRemains(p.items)
			if best then return Prayer.offer(player,p,altar,best) end
			return Prayer.pray(player,p,altar)
		elseif verb=="offerRemains" then
			local seen=Prayer.altarSeen[player]
			local altar=seen and os.time()<=seen.untilAt and PR.AltarById[seen.id]
			if not altar then return "Visit an altar to make offerings." end
			if not regionAllowed(p,altar.region) then return regionDenied(altar.region) end
			return Prayer.offer(player,p,altar,validId(item) and item or "")
		end
		return "Unknown action."
	end
	-- Combat view (bridge "stats") and incoming damage (bridge "damage").
	function Prayer.combat(p)
		local r=p.prayer
		if not r or r.points<=0 or not next(r.active) then return nil end
		local e=PR.effects(r.active)
		return {protect=e.protect,offence={melee=e.offence.melee/100,ranged=e.offence.ranged/100,magic=e.offence.magic/100},
			sap=e.sap,mana=1+e.mana,defence=e.defence}
	end
	function Prayer.incoming(p,raw,defense,payload)
		local r=p.prayer
		if not r or r.points<=0 or not next(r.active) then return raw,defense end
		local style=payload.style
		if not Data.CombatStyles.names[style] then style=nil end
		local amount,mult=PR.incoming(raw,style,PR.effects(r.active),payload.worldBoss==true)
		return amount,defense*mult
	end
	-- Snapshot keys.
	function Prayer.state(player,p,stats)
		Prayer.publish(player,p,stats)
		local r=p.prayer
		local seen=Prayer.altarSeen[player]
		local open=seen and os.time()<=seen.untilAt
		local perMinute=drainPerMinute(p,stats)
		local busy=Prayer.riteUntil[player]
		return {points=math.floor(r.points*10+.5)/10,max=Prayer.max(p),active=PR.list(r.active),quick=Prayer.quick(p),
			drain=math.floor(perMinute*10+.5)/10,secondsLeft=if perMinute>0 then math.floor(r.points/perMinute*60) else nil,
			offered=r.offered,altar=if open then seen.id else nil,altarUntil=if open then seen.untilAt else 0,
			riteIn=if busy and busy>os.clock() then math.ceil(busy-os.clock()) else 0}
	end
	function Prayer.thievingState(player,p,stats)
		stats=stats or Progression.computeStats(p,os.time())
		local lvl=level(p.xp.Thieving)
		local gloves,bonus=TH.gloves(p.items)
		local now=os.clock()
		local cds=sessionOf(player,p)
		local chances,cooldowns={},{}
		for _,t in ipairs(TH.Targets) do
			chances[t.id]=math.floor(TH.chance(t,lvl,bonus,stats.deftness)*1000+.5)/1000
			if cds[t.id] and cds[t.id]>now then cooldowns[t.id]=math.ceil(cds[t.id]-now) end
		end
		local stun=Prayer.stunUntil[player]
		return {thefts=p.thieving.thefts,gloves=gloves,gloveBonus=bonus,deftness=stats.deftness,chances=chances,cooldowns=cooldowns,
			stunIn=if stun and stun>now then math.ceil(stun-now) else 0}
	end
	function Prayer.forget(player)
		Prayer.riteUntil[player],Prayer.altarSeen[player],Prayer.stunUntil[player],Prayer.stunSeq[player],Prayer.cooldowns[player]=nil,nil,nil,nil,nil
	end
	task.spawn(function()
		while task.wait(PR.TICK) do
			for player,p in pairs(profiles) do
				if type(p.prayer)=="table" and next(p.prayer.active) then Prayer.step(player,p) end
			end
		end
	end)
end
-- End Prayer & Thieving block.
------------------------------------------------------------------------------
-- Treasure Trails (Treasure Trails team; self-contained block). Shared rules
-- live in Data.Trails (shared/GameData.lua); the step pool, generation, step
-- text and the sanitiser are server-only (trails.lua -> ServerStorage.AetherTrails,
-- so clients never receive an answer). Server-authoritative: the step list,
-- step index, seed, puzzle board and progress are stored in p.trails and only
-- ever advance by a validated action here; clients name a tier or a gesture,
-- never a step. Scroll drops, trail seeds and casket rolls draw from one
-- server-entropy Random.new() (never persisted, never derived from profile
-- state), and a drop that could not be granted (scroll or trail already held)
-- draws nothing. Location steps (dig / riddle / emote) complete only
-- TR.MIN_STEP_SECONDS after the step began and once the reader could have
-- travelled from the trail's previous location step (TR.TRAVEL_SPEED, capped
-- at TR.WARP_SECONDS for legitimate warps).
-- Verbs: trailBegin "<tier>", trailAbandon "<tier>", trailDig ["<tier>"],
-- trailSearch ["<tier>"], trailEmote "<gesture>", trailSlide "<tier>:<UDLR...>",
-- trailCheck, trailOpen "<tier>", trailTeleport "<leaf id>", trailLearn
-- "<emote scroll id>", trailBanner "<banner id>|none".
-- trailTeleport passes the recall gates (ServerStorage.IsleTravelGate from
-- npc.server.lua: not mid-fight, not inside an expedition, alive), has its own
-- cooldown (TR.TELEPORT_COOLDOWN) and zeroes the character's velocity.
-- Hooks: Trails.event(p, kind, id) from the kill bridge, gathering (fishing
-- counts as "fish"), thieving and hunter catches; Trails.migrate in migrate();
-- snapshot key `trails`. Player attribute TrailBanner = banner name or "".
------------------------------------------------------------------------------
do
	-- Server-only step module; absent (e.g. a harness without it) = trails offline.
	local TR
	do
		local okFind,module=pcall(function() return ServerStorage:FindFirstChild("AetherTrails") end)
		if okFind and module then
			local okReq,build=pcall(require,module)
			if okReq and type(build)=="function" then
				local okBuild,lib=pcall(build,Data)
				if okBuild and type(lib)=="table" then TR=lib end
			end
		end
	end
	local Shared=Data.Trails
	Trails.enabled=TR~=nil
	Trails.anchors={} -- name -> {part=BasePart?, retry=os.clock() deadline for a miss}
	Trails.random=Random.new() -- server entropy; never persisted
	Trails.leafAt={} -- UserId -> os.clock() of the last waystone leaf (cleared on leave)
	Players.PlayerRemoving:Connect(function(player) Trails.leafAt[player.UserId]=nil end)
	local function emptyRecord()
		local log={}
		for _,tier in ipairs(Shared.TierOrder) do log[tier]={completed=0,opened=0} end
		return {active={},log=log,uniques={},emotes={},version=Shared.VERSION}
	end
	local function rec(p)
		if type(p.trails)~="table" then p.trails=if TR then (TR.sanitize(nil)) else emptyRecord() end
		return p.trails
	end
	local function tierOf(item) return type(item)=="string" and Shared.Tiers[item] and item or nil end
	local function nameOf(id) return Data.Items[id] and Data.Items[id].name or tostring(id) end
	-- Reader context for step selection: levels and unlocked regions.
	local function readerContext(p)
		local levels,regions={},{}
		for _,skill in ipairs(Data.SkillOrder) do levels[skill]=level((p.xp or {})[skill] or 0) end
		for _,def in ipairs(Data.Regions) do regions[def.id]=regionAllowed(p,def.id)==true end
		return {levels=levels,regions=regions}
	end
	-- Sanitise with the reader's context; a trail that can no longer be drawn
	-- for this reader is dropped and its scroll handed back.
	function Trails.migrate(p)
		if not TR then
			if type(p.trails)~="table" then p.trails=emptyRecord() end
			return
		end
		local clean,lost=TR.sanitize(p.trails,readerContext(p))
		p.trails=clean
		-- A step with no (or a future) start time starts its pacing clock now.
		local now=os.time()
		for _,a in pairs(clean.active) do
			if a.began<=0 or a.began>now then a.began=now end
			if a.lt and a.lt>now then a.lt=now end
		end
		p.items=type(p.items)=="table" and p.items or {}
		for _,tier in ipairs(lost or {}) do
			local scroll=Shared.Tiers[tier].scroll
			if (p.items[scroll] or 0)<1 then p.items[scroll]=1 end
		end
	end
	if __TrailsHarness then __TrailsHarness(Trails) end -- headless tests only (nil in Roblox)
	function Trails.holds(p,tier)
		return (p.items[Shared.Tiers[tier].scroll] or 0)>0 or rec(p).active[tier]~=nil
	end
	-- One scroll or active trail per tier: a second find is simply not made.
	function Trails.grantScroll(p,tier)
		if Trails.holds(p,tier) then return false end
		local id=Shared.Tiers[tier].scroll
		p.items[id]=(p.items[id] or 0)+1
		return true
	end
	-- Set up the step that just became current.
	function Trails.prime(p,tier,a)
		local step=TR.StepById[a.steps[a.step]]
		a.base,a.moves,a.board,a.began=0,0,nil,os.time()
		if step.kind=="skill" and step.action=="craft" then a.base=Journal.counters(p).crafts[step.target] or 0 end
		if step.kind=="puzzle" then a.board=TR.scramble(TR.stepSeed(a.seed,a.step),TR.Tiers[tier].scramble) end
	end
	-- Completes the current step; returns the message.
	function Trails.advance(p,tier,done)
		local t=rec(p)
		local a=t.active[tier]
		if a.step>=#a.steps then
			t.active[tier]=nil
			t.log[tier].completed+=1
			local casket=TR.Tiers[tier].casket
			p.items[casket]=(p.items[casket] or 0)+1
			p.started=true
			return done.."   ·   The "..tier.." trail ends: a "..nameOf(casket).." is yours! Open it from Satchel › Trails."
		end
		a.step+=1
		Trails.prime(p,tier,a)
		return done.."   ·   Your "..tier.." trail continues (step "..a.step..")."
	end
	-- Progress for the current skill step.
	local function skillHave(p,a,step)
		if step.action=="craft" then return math.max(0,(Journal.counters(p).crafts[step.target] or 0)-a.base) end
		return a.base
	end
	-- Craft steps read the craft counters (no craft hook needed).
	function Trails.settle(p)
		local t=rec(p)
		local out={}
		if not TR then return out end
		for _,tier in ipairs(TR.TierOrder) do
			local a=t.active[tier]
			local step=a and TR.StepById[a.steps[a.step]]
			if step and step.kind=="skill" and step.action=="craft" and skillHave(p,a,step)>=step.count then
				table.insert(out,Trails.advance(p,tier,"Crafted "..nameOf(step.target).."."))
			end
		end
		return out
	end
	-- Content hook: kill / gather (fish) / thieve / catch. Rolls scroll drops
	-- and counts skill steps.
	-- A drop is rolled only when it could be granted: holding that tier's scroll
	-- or trail draws nothing, so no player action steers the shared stream.
	function Trails.event(p,kind,id)
		if not TR or type(p)~="table" or type(p.trails)~="table" or type(id)~="string" then return end
		if kind=="gather" and Data.ResourceSkill[id]=="Fishing" then kind="fish" end
		for _,d in ipairs(TR.dropsFor(kind,id)) do
			if not Trails.holds(p,d.tier) and Trails.random:NextNumber()<d.chance and Trails.grantScroll(p,d.tier) then
				note(p,"You found a "..nameOf(TR.Tiers[d.tier].scroll).."! Read it in Satchel › Trails.")
			end
		end
		for _,tier in ipairs(TR.TierOrder) do
			local a=p.trails.active[tier]
			local step=a and TR.StepById[a.steps[a.step]]
			if step and step.kind=="skill" and step.action==kind and step.target==id then
				a.base+=1
				if a.base>=step.count then note(p,Trails.advance(p,tier,"Trail task done.")) end
			end
		end
	end
	-- Positions: anchors under Workspace.Islands (contract §10), found by name.
	-- Hits are kept while parented; misses are cached for TR.ANCHOR_MISS_SECONDS
	-- so a missing anchor never turns every request into a recursive search.
	function Trails.anchor(name)
		local cached=Trails.anchors[name]
		local now=os.clock()
		if cached then
			if cached.part and cached.part.Parent then return cached.part end
			if not cached.part and now<cached.retry then return nil end
		end
		local ok,found=pcall(function()
			local islands=workspace:FindFirstChild("Islands")
			return islands and islands:FindFirstChild("Anchor_"..name,true)
		end)
		found=if ok then found else nil
		Trails.anchors[name]={part=found,retry=now+Shared.ANCHOR_MISS_SECONDS}
		return found
	end
	local function rootPosition(player)
		local character=player.Character
		local root=character and character:FindFirstChild("HumanoidRootPart")
		return root and root.Position
	end
	function Trails.near(player,anchorName,east,north,radius)
		local a=Trails.anchor(anchorName)
		local pos=rootPosition(player)
		if not a or not pos then return false end
		local c=a.CFrame.Position
		local dx,dz=pos.X-(c.X+(east or 0)),pos.Z-(c.Z-(north or 0))
		return dx*dx+dz*dz<=radius*radius and math.abs(pos.Y-c.Y)<=TR.HEIGHT_TOLERANCE
	end
	-- Active trails (optionally one tier) whose current step is `kind`.
	local function current(p,kind,tier)
		local out={}
		for _,id in ipairs(TR.TierOrder) do
			local a=rec(p).active[id]
			local step=a and TR.StepById[a.steps[a.step]]
			if step and step.kind==kind and (tier==nil or tier==id) then table.insert(out,{tier=id,a=a,step=step}) end
		end
		return out
	end
	local function begin(p,tier)
		if not tier then return "Choose a trail tier." end
		local t=rec(p)
		if t.active[tier] then return "You are already following a "..tier.." trail." end
		local scroll=TR.Tiers[tier].scroll
		if (p.items[scroll] or 0)<1 then return "You have no "..nameOf(scroll).."." end
		local seed=Trails.random:NextInteger(1,2147483646) -- server entropy, kept server-side
		local steps=TR.generate(tier,seed,readerContext(p))
		if #steps==0 then return "You cannot make sense of this scroll yet: train further or open more of the isles, then read it again." end
		p.items[scroll]-=1
		local a={seed=seed,steps=steps,step=1}
		t.active[tier]=a
		Trails.prime(p,tier,a)
		p.started=true
		return "You unroll the "..nameOf(scroll)..": "..TR.describe(TR.StepById[steps[1]]).text
	end
	-- Seconds a trail must still wait before its location step may complete:
	-- TR.MIN_STEP_SECONDS since the step began, and the travel time from the
	-- trail's previous location step (distance / TR.TRAVEL_SPEED, at most
	-- TR.WARP_SECONDS). Depends only on time and the reader's own movement, so
	-- the answer is checked only once this is 0 and a wait never leaks it.
	function Trails.wait(player,tier,a)
		local now=os.time()
		local wait=(tonumber(a.began) or 0)+(Shared.MIN_STEP_SECONDS[tier] or 0)-now
		local pos=rootPosition(player)
		if a.lt and a.lx and a.lz and pos then
			local dx,dz=pos.X-a.lx,pos.Z-a.lz
			wait=math.max(wait,a.lt+math.min(math.sqrt(dx*dx+dz*dz)/Shared.TRAVEL_SPEED,Shared.WARP_SECONDS)-now)
		end
		return math.max(0,math.ceil(wait))
	end
	local function located(player,p,kind,tier,radius,fit,success,fail)
		local list=current(p,kind,tier)
		if #list==0 then return nil end
		local waitFor
		for _,c in ipairs(list) do
			local s=c.step
			local w=Trails.wait(player,c.tier,c.a)
			if w>0 then
				waitFor=math.min(waitFor or w,w)
			elseif Trails.near(player,s.anchor,if kind=="dig" then s.east else 0,if kind=="dig" then s.north else 0,radius) and fit(c) then
				if s.region and not regionAllowed(p,s.region) then return regionDenied(s.region) end
				local pos=rootPosition(player)
				if pos then c.a.lt,c.a.lx,c.a.lz=os.time(),pos.X,pos.Z end
				return Trails.advance(p,c.tier,success(c))
			end
		end
		if waitFor then return "The trail is still fresh: study the clue a little longer ("..waitFor.."s)." end
		return fail
	end
	local function openCasket(p,tier)
		if not tier then return "Choose a casket." end
		local id=TR.Tiers[tier].casket
		if (p.items[id] or 0)<1 then return "You have no "..nameOf(id).."." end
		local stats=Progression.computeStats(p,os.time())
		local t=rec(p)
		local loot=TR.openCasket(tier,function() return Trails.random:NextNumber() end,stats.magicFind,stats.petLuck,Progression.rollDrops)
		p.items[id]-=1
		t.log[tier].opened+=1
		p.coins+=loot.coins
		local names={}
		for item,n in pairs(loot.items) do
			p.items[item]=(p.items[item] or 0)+n
			table.insert(names,"+"..n.." "..nameOf(item))
		end
		table.sort(names)
		local text="Opened the "..nameOf(id)..": +"..loot.coins.." coins"..(if #names>0 then ", "..table.concat(names,", ") else "")
		for item,n in pairs(loot.uniques) do
			t.uniques[item]=(t.uniques[item] or 0)+n
			text..="   ·   Clue log: "..nameOf(item).."!"
		end
		if loot.master then
			text..=if Trails.grantScroll(p,"Master") then "   ·   An "..nameOf(TR.Tiers.Master.scroll).." was tucked inside!" else "   ·   A Master scroll crumbles: you already hold one."
		end
		return text
	end
	function Trails.action(player,p,verb,item)
		if not TR then return "The trail-keepers are still charting the isles. Try again shortly." end
		local t=rec(p)
		if verb=="trailBegin" then return begin(p,tierOf(item))
		elseif verb=="trailAbandon" then
			local tier=tierOf(item)
			if not tier or not t.active[tier] then return "No such trail to abandon." end
			t.active[tier]=nil
			return "You let the "..tier.." trail go cold."
		elseif verb=="trailDig" then
			if (p.items[TR.SPADE] or 0)<1 then return "You need a "..nameOf(TR.SPADE).." to dig (forge one at a Forge)." end
			return located(player,p,"dig",tierOf(item),TR.DIG_RADIUS,function() return true end,
				function(c) return "Your spade strikes a buried tin! ("..c.tier.." trail)" end,"You dig, but find only soil and worms.")
				or "None of your trails asks you to dig."
		elseif verb=="trailSearch" then
			return located(player,p,"riddle",tierOf(item),TR.SEARCH_RADIUS,function() return true end,
				function(c)
					local npc=c.step.npc and Data.Townsfolk.NPCs[c.step.npc]
					return (if npc then npc.name.." slips you a folded note." else "Tucked out of sight, you find the next note.").." ("..c.tier.." trail)"
				end,"You search, but find nothing here.") or "None of your trails is a riddle right now."
		elseif verb=="trailEmote" then
			local gesture=type(item)=="string" and TR.Gestures[item] and item
			if not gesture then return "Choose an emote." end
			local missing
			local result=located(player,p,"emote",nil,TR.EMOTE_RADIUS,function(c)
				if c.step.gesture~=gesture then return false end
				for _,id in ipairs(c.step.wear) do
					local def=Data.Items[id]
					if not def or p.equipment[def.slot]~=id then missing=id return false end
				end
				return true
			end,function(c) return "A hooded stranger nods at your "..TR.Gestures[gesture].." and hands you a note. ("..c.tier.." trail)" end,nil)
			if result then return result end
			if missing then return "The stranger frowns: you are not wearing "..nameOf(missing).."." end
			return "You perform the "..TR.Gestures[gesture]..". Nobody seems to notice."
		elseif verb=="trailSlide" then
			local tierText,moves=string.match(type(item)=="string" and item or "","^(%a+):([UDLR]+)$")
			local tier=tierOf(tierText)
			local c=tier and current(p,"puzzle",tier)[1]
			if not c then return "No puzzle box is open." end
			local board,bad=TR.applyMoves(c.a.board,moves)
			if not board then return if bad and bad>0 then "That tile cannot slide (move "..bad..")." else "Too many moves at once." end
			c.a.board=board
			c.a.moves+=#moves
			if board==TR.SOLVED then return Trails.advance(p,tier,"The "..c.step.name.." clicks open after "..c.a.moves.." moves!") end
			return "The tiles slide."
		elseif verb=="trailCheck" then
			local done=Trails.settle(p)
			return if #done>0 then table.concat(done,"   ·   ") else "Your trails are as you left them."
		elseif verb=="trailOpen" then return openCasket(p,tierOf(item))
		elseif verb=="trailTeleport" then
			local tp=type(item)=="string" and TR.TeleportById[item]
			if not tp then return "Choose a waystone leaf." end
			if (p.items[tp.id] or 0)<1 then return "You have no "..nameOf(tp.id).."." end
			if not regionAllowed(p,tp.region) then return regionDenied(tp.region) end
			local last=Trails.leafAt[player.UserId]
			local now=os.clock()
			if last and now-last<Shared.TELEPORT_COOLDOWN then
				return "The Skyway is still settling from your last leaf ("..math.ceil(Shared.TELEPORT_COOLDOWN-(now-last)).."s)."
			end
			-- The recall gates (npc.server.lua): alive, not mid-fight, not in an expedition.
			local gate=ServerStorage:FindFirstChild("IsleTravelGate")
			if not gate then return "The leaf will not carry you right now." end
			local okGate,verdict=pcall(gate.Invoke,gate,player)
			if not okGate or verdict~=true then return if okGate and type(verdict)=="string" then verdict else "The leaf will not carry you right now." end
			local a=Trails.anchor(tp.anchor)
			local character=player.Character
			local root=character and character:FindFirstChild("HumanoidRootPart")
			if not a or not root then return "The leaf will not carry you right now." end
			p.items[tp.id]-=1
			Trails.leafAt[player.UserId]=now
			player:SetAttribute("FastTravelAt",os.clock()) -- known fast travel (Aether Mote pickup checks)
			character:PivotTo(CFrame.new(a.CFrame.Position+Vector3.new(0,4,0)))
			root.AssemblyLinearVelocity=Vector3.zero
			return "The leaf crumbles to light: you step out at "..tp.name.."."
		elseif verb=="trailLearn" then
			local def=type(item)=="string" and Data.Items[item]
			if not def or def.category~="emote" or not TR.Emotes[def.emote] then return "Choose an emote scroll." end
			if (p.items[item] or 0)<1 then return "You have no "..def.name.."." end
			if table.find(t.emotes,def.emote) then return "You already know "..TR.Emotes[def.emote].name.."." end
			p.items[item]-=1
			table.insert(t.emotes,def.emote)
			return "You learned the "..TR.Emotes[def.emote].name.." emote."
		elseif verb=="trailBanner" then
			if item=="none" then t.banner=nil; player:SetAttribute("TrailBanner","") return "Banner lowered." end
			local def=type(item)=="string" and Data.Items[item]
			if not def or def.category~="banner" or (p.items[item] or 0)<1 then return "Choose a banner you own." end
			t.banner=item
			player:SetAttribute("TrailBanner",def.name)
			return "You raise the "..def.name.."."
		end
		return "Unknown action."
	end
	-- Snapshot key `trails` (step text and hints only; never the answers).
	function Trails.state(player,p)
		local t=rec(p)
		if not TR then return {active={},log=t.log,uniques=t.uniques or {},emotes=t.emotes or {},spade=(p.items[Shared.SPADE] or 0)>0,offline=true} end
		for _,text in ipairs(Trails.settle(p)) do note(p,text) end
		local active={}
		for _,tier in ipairs(TR.TierOrder) do
			local a=t.active[tier]
			if a then
				local step=TR.StepById[a.steps[a.step]]
				local d=TR.describe(step)
				local row={tier=tier,step=a.step,kind=step.kind,style=d.style,text=d.text,hint=d.hint,guide=d.guide}
				if step.kind=="emote" then row.gesture=step.gesture; row.wear=table.clone(step.wear) end
				if step.kind=="skill" then row.need=step.count; row.have=skillHave(p,a,step) end
				if step.kind=="puzzle" then row.board=a.board; row.moves=a.moves end
				active[tier]=row
			end
		end
		local banner=t.banner and (p.items[t.banner] or 0)>0 and Data.Items[t.banner].name or ""
		if player.GetAttribute and player:GetAttribute("TrailBanner")~=banner then player:SetAttribute("TrailBanner",banner) end
		return {active=active,log=t.log,uniques=t.uniques,emotes=t.emotes,banner=t.banner,spade=(p.items[TR.SPADE] or 0)>0}
	end
end
-- End Treasure Trails block.
-- Slayer tasks (Slayer team). Rules and data: Data.SlayerTasks (shared/GameData.lua).
-- Verbs (item <= 64 chars):
--   slayerTask "<master>"    take a task from a master (Combat/Slayer gates, no
--                            current task); weighted among reachable, unblocked
--                            families (ST.assign), never the family just finished
--                            when another is possible
--   slayerSkip               pay ST.SKIP_COST points: a new task from the same
--                            master; the streak is kept
--   slayerCancel             drop the task for free; the streak resets to 0
--   slayerBlock "<family>"   pay ST.BLOCK_COST points to stop a family being
--                            assigned (ST.blockSlots); blocking the current task drops it;
--                            refused when an available master would be left with
--                            fewer than ST.MIN_CANDIDATES families (ST.blockAllowed)
--   slayerUnblock "<family>" free a block slot (no refund)
--   slayerBuy "<shop id>"    ST.Shop: unlocks, extensions, consumables, titles, visor crafts
--                            (a craft refuses while a cost item is worn: unequip it first)
--   slayerTitle "<id>|none"  wear an owned title (player attribute SlayerTitle)
-- Credit: bridge "kill" (combat's credit rules: damage dealt, alive, within
-- range, Ironman solo; multishot extras and party members each report their own
-- kill) with task=true (combat: ST.taskEligible, >= ST.TASK_SHARE of max health
-- or top damager) and "seaCreature" kills (owner only) call SlayerTasks.onKill. Only a kill
-- of the assigned family counts; each pays ST.killXp Slayer XP. With Call of the
-- Superior unlocked a land task kill rolls ST.SUPERIOR_CHANCE (none when the
-- monster's level < Combat x ST.SUPERIOR_LEVEL_RATIO): the server issues
-- a ticket {id, expires} under a per-player sequence and returns
-- superior = {id, seq} in the kill reply; Combat spawns it by the dead monster,
-- owned by this player, and settles it once through bridge "slayerSuperior"
-- {seq, monster, result = "kill"|"despawn"} (unique loot, Slayer XP, superior
-- log, +1 task progress). Bridge "stats" adds slayer = {level, family, visor}.
-- Profile p.slayerTasks = {task = {master, family, amount, killed, extended} | nil,
-- streak, completed, points, blocked = {family...}, unlocks = {[id] = true},
-- superiors = {[superiorId] = kills}, title = shop id | "", last = family | nil}.
-- Player attributes: SlayerTask "<family>:<killed>:<amount>" | "", SlayerTitle, SlayerLevel,
-- SlayerVisor (worn visor id | ""; combat drops its stats cache when it or SlayerTask changes).
-- Snapshot key: slayerTasks. Tickets are session-only (SlayerTasks.forget).
------------------------------------------------------------------------------
local SlayerTasks={verbs={slayerTask=true,slayerSkip=true,slayerCancel=true,slayerBlock=true,slayerUnblock=true,slayerBuy=true,slayerTitle=true},
	tickets={},deniedAt={}}
do
	local ST=Data.SlayerTasks
	local function count(v,limit)
		local n=tonumber(v)
		if not n or n~=n or n<0 then return 0 end
		return math.floor(math.min(n,limit or 1e12))
	end
	local function itemName(id) return Data.Items[id] and Data.Items[id].name or tostring(id) end
	local function familyName(id) local f=ST.FamilyById[id]; return f and f.name or tostring(id) end
	-- Older saves gain an empty ledger; tampered entries are dropped or clamped.
	function SlayerTasks.migrate(p)
		local r=type(p.slayerTasks)=="table" and p.slayerTasks or {}
		local out={streak=count(r.streak),completed=count(r.completed),points=count(r.points,1e9),blocked={},unlocks={},superiors={},title="",task=nil,last=nil}
		local t=r.task
		if type(t)=="table" and ST.MasterById[t.master] and ST.FamilyById[t.family] then
			local amount=count(t.amount,ST.MAX_AMOUNT)
			local killed=count(t.killed,amount)
			if amount>=1 and killed<amount then out.task={master=t.master,family=t.family,amount=amount,killed=killed,extended=t.extended==true} end
		end
		local slots=0
		if type(r.unlocks)=="table" then
			for id,v in pairs(r.unlocks) do
				local e=ST.ShopById[id]
				if v==true and e and (e.kind=="unlock" or e.kind=="extend" or e.kind=="title") then out.unlocks[id]=true end
			end
		end
		slots=ST.blockSlots(out.unlocks)
		if type(r.blocked)=="table" then
			for _,id in ipairs(r.blocked) do
				if ST.FamilyById[id] and not table.find(out.blocked,id) and #out.blocked<slots then table.insert(out.blocked,id) end
			end
		end
		if out.task and table.find(out.blocked,out.task.family) then out.task=nil end
		if type(r.superiors)=="table" then
			for id,n in pairs(r.superiors) do if ST.Superiors[id] and count(n)>0 then out.superiors[id]=count(n) end end
		end
		if type(r.title)=="string" and out.unlocks[r.title] and ST.ShopById[r.title].kind=="title" then out.title=r.title end
		if ST.FamilyById[r.last] then out.last=r.last end
		p.slayerTasks=out
	end
	local function ledger(p)
		if type(p.slayerTasks)~="table" then SlayerTasks.migrate(p) end
		return p.slayerTasks
	end
	local function slayerLevel(p) return level(p.xp.Slayer) end
	-- Context for the pure rules: levels and the regions this journal may enter.
	function SlayerTasks.context(p)
		local levels={}
		for _,skill in ipairs(Data.SkillOrder) do levels[skill]=level(p.xp[skill]) end
		local regions={}
		for _,r in ipairs(Data.Regions) do if regionAllowed(p,r.id) then regions[r.id]=true end end
		return {combat=levels.Combat,slayer=levels.Slayer,levels=levels,regions=regions}
	end
	function SlayerTasks.publish(player,p)
		local st=ledger(p)
		local t=st.task
		player:SetAttribute("SlayerTask",if t then t.family..":"..t.killed..":"..t.amount else "")
		local title=st.title~="" and ST.ShopById[st.title]
		player:SetAttribute("SlayerTitle",if title then title.title else "")
		player:SetAttribute("SlayerLevel",slayerLevel(p))
		-- Combat drops its cached "stats" when this (or SlayerTask) changes, so the visor bonus is never stale.
		local helmet=p.equipment and p.equipment.helmet
		player:SetAttribute("SlayerVisor",if ST.visorBonus(helmet) then helmet else "")
	end
	-- Is a shop cost item worn (gear slot or accessory bag)? Crafting refuses rather than consume it.
	local function worn(p,id)
		for _,e in pairs(p.equipment or {}) do if e==id then return true end end
		return type(p.accessoryBag)=="table" and table.find(p.accessoryBag,id)~=nil
	end
	-- Combat view (bridge "stats"): Slayer level, task family, equipped visor bonus.
	function SlayerTasks.combat(p)
		local st=ledger(p)
		return {level=slayerLevel(p),family=st.task and st.task.family or nil,visor=ST.visorBonus(p.equipment and p.equipment.helmet)}
	end
	-- Snapshot (Hunt > Slayer page).
	function SlayerTasks.state(player,p)
		local st=ledger(p)
		SlayerTasks.publish(player,p)
		local ctx=SlayerTasks.context(p)
		local masters,families={},{}
		for _,m in ipairs(ST.Masters) do
			local ok,reason=ST.masterAvailable(m.id,ctx)
			masters[m.id]={ok=ok==true,reason=reason}
		end
		for _,f in ipairs(ST.Families) do
			local ok,reason=ST.familyReachable(f.id,ctx)
			families[f.id]={ok=ok==true,reason=reason}
		end
		local unlocks={}
		for id in pairs(st.unlocks) do table.insert(unlocks,id) end
		table.sort(unlocks)
		local book=SlayerTasks.tickets[player]
		local live=0
		if book then for _ in pairs(book.live) do live+=1 end end
		-- Families a block would refuse (ST.blockAllowed): {[family] = reason}.
		local blockRefusal={}
		for _,f in ipairs(ST.Families) do
			if not table.find(st.blocked,f.id) then
				local ok,reason=ST.blockAllowed(f.id,ctx,st.blocked)
				if not ok then blockRefusal[f.id]=reason end
			end
		end
		return {task=st.task and table.clone(st.task) or nil,streak=st.streak,completed=st.completed,points=st.points,blocked=table.clone(st.blocked),
			blockSlots=ST.blockSlots(st.unlocks),unlocks=unlocks,superiors=table.clone(st.superiors),title=st.title,level=ctx.slayer,
			masters=masters,families=families,superiorsLive=live,nextMult=ST.streakMult(st.streak+1),blockRefusal=blockRefusal}
	end
	local function assign(p,masterId)
		local st=ledger(p)
		local task,reason=ST.assign(masterId,SlayerTasks.context(p),st.blocked,st.unlocks,roll(),roll(),st.last)
		if not task then return nil,reason end
		st.task=task
		return task
	end
	local function taskText(task)
		local m=ST.MasterById[task.master]
		return (m and m.name or task.master).." assigns: slay "..task.amount.." "..familyName(task.family)..(if task.extended then " (extended)" else "").."."
	end
	-- Task completion: points (x streak), bounty, notices.
	local function complete(p)
		local st=ledger(p)
		local task=st.task
		st.task=nil
		st.streak+=1
		st.completed+=1
		st.last=task.family
		local mult=ST.streakMult(st.streak)
		local points=ST.pointsFor(task.master,st.streak)
		st.points+=points
		local bounty=ST.bountyFor(task.master,st.unlocks)
		p.coins+=bounty
		note(p,"Slayer task complete! +"..points.." Slayer points"..(if mult>1 then " (streak "..st.streak.." x"..mult..")" else "").." · +"..bounty.." coins. Return to a master for a new task.")
	end
	-- One credited kill. Returns {id, seq} when a superior rises (land kills only).
	function SlayerTasks.onKill(player,p,monsterId,monster,sea)
		local st=ledger(p)
		local task=st.task
		if not task or not ST.inFamily(task.family,monsterId) then return nil end
		task.killed=math.min(task.amount,task.killed+1)
		grantXp(p,"Slayer",ST.killXp(monster))
		local superior=nil
		if not sea then
			local id=ST.rollSuperior(st.unlocks.SuperiorCalling==true,monsterId,roll,level(p.xp.Combat))
			if id then superior=SlayerTasks.issue(player,id) end
			if superior then note(p,"A "..ST.Superiors[id].name.." emerges! Only you can claim it.") end
		end
		if task.killed>=task.amount then complete(p) end
		SlayerTasks.publish(player,p)
		return superior
	end
	-- Superior tickets ------------------------------------------------------------
	function SlayerTasks.book(player)
		local book=SlayerTasks.tickets[player]
		if not book then book={seq=0,live={}}; SlayerTasks.tickets[player]=book end
		local now=os.clock()
		for seq,ticket in pairs(book.live) do if now>ticket.expires then book.live[seq]=nil end end
		return book
	end
	function SlayerTasks.issue(player,id)
		local book=SlayerTasks.book(player)
		local live=0
		for _ in pairs(book.live) do live+=1 end
		if live>=ST.SUPERIOR_LIVE then return nil end
		book.seq+=1
		book.live[book.seq]={id=id,expires=os.clock()+ST.SUPERIOR_LIFETIME+15}
		return {id=id,seq=book.seq}
	end
	-- Bridge "slayerSuperior" {seq, monster, result}: settles a ticket once.
	function SlayerTasks.superiorReport(player,p,payload)
		local seq,id,result=payload.seq,payload.monster,payload.result
		if type(seq)~="number" or seq%1~=0 or not validId(id) or (result~="kill" and result~="despawn") then return {ok=false,reason="invalid"} end
		local book=SlayerTasks.tickets[player]
		local ticket=book and book.live[seq]
		if not ticket or ticket.id~=id then return {ok=false,reason="ticket"} end
		book.live[seq]=nil
		if result=="despawn" then return {ok=true,message="The superior withdrew."} end
		if os.clock()>ticket.expires then return {ok=false,reason="expired"} end
		local def=ST.Superiors[id]
		local st=ledger(p)
		local stats=Progression.computeStats(p,os.time())
		p.started=true
		local xp=ST.killXp(def)
		grantXp(p,"Slayer",xp)
		p.coins+=def.coins
		local drops=Progression.rollDrops(def.drops,stats.magicFind,roll,stats.petLuck)
		for item,n in pairs(drops) do collect(p,item,n) end
		p.bestiary[def.base]=(p.bestiary[def.base] or 0)+1
		st.superiors[id]=(st.superiors[id] or 0)+1
		local task=st.task
		if task and ST.inFamily(task.family,def.base) then
			task.killed=math.min(task.amount,task.killed+1)
			if task.killed>=task.amount then complete(p) end
		end
		SlayerTasks.publish(player,p)
		local names={}
		for item,n in pairs(drops) do table.insert(names,"+"..n.." "..itemName(item)) end
		table.sort(names)
		return {ok=true,drops=drops,message=def.name.." slain • +"..def.coins.." coins, +"..xp.." Slayer XP"..(if #names>0 then ", "..table.concat(names,", ") else "")}
	end
	-- Bridge "slayerDenied" {monster}: tell the player the Slayer level a monster needs (rate-limited).
	function SlayerTasks.denied(player,p,payload)
		local need=ST.slayerLevelFor(payload.monster)
		if need<=0 or os.clock()<(SlayerTasks.deniedAt[player] or 0) then return nil end
		SlayerTasks.deniedAt[player]=os.clock()+3
		local def=Data.Monsters[payload.monster]
		return "You need Slayer "..need.." to harm the "..def.name.." (you have "..slayerLevel(p)..")."
	end
	function SlayerTasks.forget(player)
		SlayerTasks.tickets[player],SlayerTasks.deniedAt[player]=nil,nil
	end
	-- Verbs ------------------------------------------------------------------------
	function SlayerTasks.action(player,p,verb,item)
		local st=ledger(p)
		local reply
		if verb=="slayerTask" then
			if st.task then return "You already have a task: "..ST.describe(st.task)..". Finish, skip or cancel it first." end
			if not validId(item) or not ST.MasterById[item] then return "Choose a Slayer master." end
			local task,reason=assign(p,item)
			if not task then return ST.MasterById[item].name..": "..tostring(reason).."." end
			reply=taskText(task)
		elseif verb=="slayerSkip" then
			if not st.task then return "You have no task to skip." end
			if st.points<ST.SKIP_COST then return "Skipping costs "..ST.SKIP_COST.." Slayer points." end
			local master=st.task.master
			local skipped=st.task.family
			st.points-=ST.SKIP_COST
			st.task=nil
			local task=assign(p,master)
			if not task then reply="Task skipped (-"..ST.SKIP_COST.." points). "..ST.MasterById[master].name.." has nothing else for you right now."
			else reply="Task skipped (-"..ST.SKIP_COST.." points). "..taskText(task) end
			if task and task.family==skipped then reply..=" (the same family again)" end
		elseif verb=="slayerCancel" then
			if not st.task then return "You have no task to cancel." end
			st.task=nil
			local lost=st.streak
			st.streak=0
			reply="Task cancelled."..(if lost>0 then " Your streak of "..lost.." is broken." else "")
		elseif verb=="slayerBlock" then
			local f=validId(item) and ST.FamilyById[item]
			if not f then return "Choose a monster family to block." end
			if table.find(st.blocked,f.id) then return f.name.." is already blocked." end
			if #st.blocked>=ST.blockSlots(st.unlocks) then return "Every block slot is full. Unblock a family first." end
			if st.points<ST.BLOCK_COST then return "Blocking costs "..ST.BLOCK_COST.." Slayer points." end
			local allowed,why=ST.blockAllowed(f.id,SlayerTasks.context(p),st.blocked)
			if not allowed then return "You cannot block "..f.name..": "..tostring(why).."." end
			st.points-=ST.BLOCK_COST
			table.insert(st.blocked,f.id)
			reply=f.name.." blocked (-"..ST.BLOCK_COST.." points)."
			if st.task and st.task.family==f.id then st.task=nil; reply..=" Your current task was dropped (streak kept)." end
		elseif verb=="slayerUnblock" then
			local index=validId(item) and table.find(st.blocked,item)
			if not index then return "That family is not blocked." end
			table.remove(st.blocked,index)
			reply=familyName(item).." unblocked."
		elseif verb=="slayerBuy" then
			local e=validId(item) and ST.ShopById[item]
			local levels={}
			for _,skill in ipairs(Data.SkillOrder) do levels[skill]=level(p.xp[skill]) end
			local ok,reason=ST.canBuy(item,{points=st.points,unlocks=st.unlocks,levels=levels,items=p.items})
			if not ok then return reason end
			-- A worn cost item (e.g. the Hunter's Visor being imbued) is never consumed: unequip it first.
			for id in pairs(e.costs or {}) do
				if worn(p,id) then return "Unequip "..itemName(id).." before using it to craft." end
			end
			st.points-=e.cost
			for id,n in pairs(e.costs or {}) do p.items[id]=(p.items[id] or 0)-n; if p.items[id]<=0 then p.items[id]=nil end end
			if e.kind=="unlock" or e.kind=="extend" or e.kind=="title" then st.unlocks[e.id]=true end
			if e.kind=="title" then st.title=e.id end
			for id,n in pairs(e.gives or {}) do collect(p,id,n) end
			reply=if e.kind=="craft" then "Assembled: "..itemName(next(e.gives)).."." elseif e.kind=="consumable" then "Bought "..e.name.." (-"..e.cost.." points)."
				else "Unlocked "..e.name.." (-"..e.cost.." points)."
		elseif verb=="slayerTitle" then
			if item=="none" then st.title=""; reply="Title hidden."
			else
				local e=validId(item) and ST.ShopById[item]
				if not e or e.kind~="title" or not st.unlocks[e.id] then return "You have not earned that title." end
				st.title=e.id
				reply="Now wearing the title "..e.title.."."
			end
		else
			return "Unknown slayer action."
		end
		p.started=true
		SlayerTasks.publish(player,p)
		return reply
	end
end
-- End Slayer tasks block.
------------------------------------------------------------------------------
-- Minigames (Minigames team; self-contained block). Skybreach Siege and
-- Tempest Haul run in minigames.server.lua; this block owns the journal side:
--   bridge op "minigame" {action = "info"}   -> {combat, levels, ironman, lumenward, rollRoom}
--                        {action = "spend", item = "Timber", amount}  -> {ok} (barricade repairs)
--                        {action = "settle", game, tier, points, won, partySize, seconds, xp,
--                         forfeit, xpOnly, required, recent}
--       validates and clamps everything (points <= MAX_POINTS_PER_SECOND x seconds;
--       XP only in the game's skills: Siege Carpentry <= REPAIR_XP_LIMIT repairs,
--       Haul XP <= Haul.xpPerSecond x seconds summed over its skills), pays XP,
--       Commendations (Siege: Data.Minigames.Siege.reward with the required points,
--       never below Siege.requiredPoints(seconds), and only with a recent action)
--       or Squall Cache rolls (Haul: Data.Minigames.Haul.rolls, capped by match
--       time), and writes the minigame log. xpOnly = pay XP only (a member who
--       disconnected mid-match; no log, no reward). Rolls past the 500 bank cap
--       are opened on the spot, never dropped.
--   verbs  mgBuy "<shop id>"     Commendation shop (Lumenward armour, XP lamps, cosmetics)
--          mgRoll "1"|"all"      open banked Squall Cache rolls (up to 20 at once)
--          mgTitle "<id>|none"   wear an owned cosmetic title (player attribute MinigameTitle)
-- Lumenward: the four-piece outfit's helm style is applied inside the shared
-- Progression.computeStats (Data.Sets.Lumenward.style), so the client agrees.
-- Profile p.minigames = {commendations, rolls, unlocks = {[id] = true}, title,
-- log = {[game] = {played, won, points, best, paid}}}; snapshot key minigames.
------------------------------------------------------------------------------
local Minigames={verbs={mgBuy=true,mgRoll=true,mgTitle=true}}
do
	local MG=Data.Minigames
	local ROLL_BANK=500
	local function styleOf(p) return MG.lumenwardStyle(p,Progression.equipped) end
	function Minigames.migrate(p) p.minigames=MG.migrate(p.minigames) end
	local function ledger(p)
		if type(p.minigames)~="table" then Minigames.migrate(p) end
		return p.minigames
	end
	local function levels(p)
		local out={}
		for _,skill in ipairs(Data.SkillOrder) do out[skill]=level(p.xp[skill]) end
		return out
	end
	local function int(v,lo,hi)
		v=tonumber(v)
		if not v or v~=v then return lo end
		return math.clamp(math.floor(v),lo,hi)
	end
	function Minigames.publish(player,p)
		local m=ledger(p)
		local e=m.title~="" and MG.ShopById[m.title]
		player:SetAttribute("MinigameTitle",if e then e.title else "")
	end
	function Minigames.state(player,p)
		local m=ledger(p)
		Minigames.publish(player,p)
		local lv=levels(p)
		local lamps={}
		for skill in pairs(MG.LampSkills) do lamps[skill]=MG.lampXp(skill,lv[skill]) end
		local unlocks={}
		for id in pairs(m.unlocks) do table.insert(unlocks,id) end
		table.sort(unlocks)
		local log={}
		for game,l in pairs(m.log) do log[game]=table.clone(l) end
		local style=styleOf(p)
		return {commendations=m.commendations,rolls=m.rolls,unlocks=unlocks,title=m.title,log=log,lamps=lamps,lumenward=style and style.style or nil}
	end
	-- XP a settlement may pay, by skill (only the game's own skills).
	-- Siege: Carpentry from at most REPAIR_XP_LIMIT repairs (and one per cooldown).
	-- Haul: each skill's XP is worth amount / Haul.xpPerSecond(level) seconds of
	-- play; the sum may not exceed the seconds played (plus one action of slack),
	-- else everything scales down: XP/h stays at XP_RATIO x the solo rate.
	local function settleXp(game,lv,seconds,xp)
		local out={}
		if type(xp)~="table" then return out end
		if game=="Siege" then
			local per=MG.Siege.repairXp(lv.Carpentry)
			out.Carpentry=int(xp.Carpentry,0,math.floor(per*math.min(MG.Siege.REPAIR_XP_LIMIT,seconds/MG.ACTION_COOLDOWN+1)))
			return out
		end
		local used=0
		for _,skill in pairs(MG.Haul.ActionSkill) do
			local a=tonumber(xp[skill])
			if out[skill]==nil and a and a==a and a>0 and a<1e9 then
				out[skill]=a
				used+=a/MG.Haul.xpPerSecond(lv[skill])
			end
		end
		local budget=seconds+MG.Haul.Model.catch
		local scale=if used>budget then budget/used else 1
		for skill,a in pairs(out) do out[skill]=math.floor(a*scale) end
		return out
	end
	-- Opens n Squall Caches straight into the journal; returns the loot text.
	local function openCaches(p,n)
		local coins,items=0,{}
		for _=1,n do
			local loot=MG.Haul.rollCache(level(p.xp.Fishing),roll)
			coins+=loot.coins
			for id,k in pairs(loot.items) do items[id]=(items[id] or 0)+k end
		end
		p.coins+=coins
		local names={}
		for id,k in pairs(items) do
			collect(p,id,k)
			local def=Data.Items[id]
			table.insert(names,"+"..k.." "..(def and def.name or id))
		end
		table.sort(names)
		return "+"..coins.." coins"..(if #names>0 then ", "..table.concat(names,", ") else "")
	end
	function Minigames.settle(player,p,payload)
		local game=payload.game
		local rules=(game=="Siege" or game=="Haul") and MG[game]
		if not rules then return {ok=false,reason="invalid"} end
		if game=="Siege" and not MG.Siege.TierById[payload.tier] then return {ok=false,reason="invalid"} end
		local m=ledger(p)
		local lv=levels(p)
		local seconds=int(payload.seconds,1,rules.TIME_LIMIT+120)
		local gained={}
		-- xpSeconds: the part of the match this XP covers (after an earlier xpOnly settlement).
		local xpSeconds=if payload.xpSeconds~=nil then int(payload.xpSeconds,1,seconds) else seconds
		for skill,amount in pairs(settleXp(game,lv,xpSeconds,payload.xp)) do
			if amount>0 then grantXp(p,skill,amount); table.insert(gained,"+"..amount.." "..skill.." XP") end
		end
		table.sort(gained)
		p.started=true
		-- A disconnected member's XP (paid while the journal is still live): no log, no reward.
		if payload.xpOnly==true then return {ok=true,paid=0,points=0,message=table.concat(gained," • ")} end
		local points=int(payload.points,0,MG.MAX_POINTS_PER_SECOND*seconds)
		local won=payload.won==true and payload.forfeit~=true
		local required=rules.MIN_POINTS
		local recent=true
		if game=="Siege" then
			required=math.max(MG.Siege.requiredPoints(seconds,0),int(payload.required,0,MG.MAX_POINTS_PER_SECOND*seconds+1))
			recent=payload.recent~=false
		end
		local log=m.log[game]
		log.played+=1
		log.points+=points
		log.best=math.max(log.best,points)
		if won and recent and points>=required then log.won+=1 end -- a win counts only for members who earned it
		local parts={}
		local paid=0
		if game=="Siege" then
			paid=if recent then MG.Siege.reward(payload.tier,points,won,required) else 0
			m.commendations+=paid
			if paid>0 then table.insert(parts,"+"..paid.." Commendations ("..m.commendations.." banked)")
			elseif won and not recent then table.insert(parts,"No Commendations: no action in the last "..MG.Siege.RECENT_SECONDS.." s")
			elseif won then table.insert(parts,"No Commendations: "..points.." / "..required.." points") end
		else
			paid=MG.Haul.rolls(points,won,payload.partySize,seconds)
			local banked=math.min(paid,math.max(0,ROLL_BANK-m.rolls))
			m.rolls+=banked
			if banked>0 then table.insert(parts,"+"..banked.." Squall Cache roll"..(if banked==1 then "" else "s").." (open them in Hunt › Minigames)")
			elseif won and paid==0 then table.insert(parts,"No reward: "..points.." / "..MG.Haul.MIN_POINTS.." points") end
			if paid>banked then
				-- The bank is full: never drop a roll, open the overflow on the spot.
				table.insert(parts,"Cache bank full ("..ROLL_BANK.."): "..(paid-banked).." opened on the spot: "..openCaches(p,paid-banked))
			end
		end
		log.paid+=paid
		for _,g in ipairs(gained) do table.insert(parts,g) end
		return {ok=true,paid=paid,points=points,required=required,message=table.concat(parts," • ")}
	end
	function Minigames.bridge(player,p,payload)
		local action=payload.action
		if action=="info" then
			local lv=levels(p)
			return {combat=lv.Combat,levels=lv,ironman=p.ironman==true,lumenward=styleOf(p)~=nil,rollRoom=math.max(0,ROLL_BANK-ledger(p).rolls)}
		elseif action=="spend" then
			local n=int(payload.amount,1,5)
			if payload.item~="Timber" or (p.items.Timber or 0)<n then return {ok=false} end
			p.items.Timber-=n
			return {ok=true}
		elseif action=="settle" then
			return Minigames.settle(player,p,payload)
		end
		return nil
	end
	function Minigames.action(player,p,verb,item)
		local m=ledger(p)
		local reply
		if verb=="mgBuy" then
			local lv=levels(p)
			local e,why=MG.canBuy(validId(item) and item or "",m,lv)
			if not e then return why end
			m.commendations-=e.cost
			if e.kind=="armor" then
				collect(p,e.item,1)
				reply="Bought "..Data.Items[e.item].name.." for "..e.cost.." Commendations."
			elseif e.kind=="lamp" then
				local xp=MG.lampXp(e.skill,lv[e.skill])
				grantXp(p,e.skill,xp)
				reply="The Lumen lamp flares: +"..xp.." "..e.skill.." XP (-"..e.cost.." Commendations)."
			else
				m.unlocks[e.id]=true
				m.title=e.id
				reply="Unlocked the "..e.title.." title (-"..e.cost.." Commendations). Wearing it now."
			end
		elseif verb=="mgRoll" then
			if m.rolls<1 then return "You have no Squall Cache rolls. Win a Tempest Haul with "..MG.Haul.MIN_POINTS.."+ points." end
			local n=if item=="all" then math.min(m.rolls,20) else 1
			m.rolls-=n
			reply="Opened "..n.." Squall Cache"..(if n==1 then "" else "s")..": "..openCaches(p,n).."."
		elseif verb=="mgTitle" then
			if item=="none" then m.title=""; reply="Title hidden."
			elseif validId(item) and m.unlocks[item] then m.title=item; reply="Now wearing "..MG.ShopById[item].title.."."
			else return "You do not own that title." end
		end
		p.started=true
		Minigames.publish(player,p)
		return reply
	end
end
-- End Minigames block.
-- Commissions & Logs (Mining & Logs team). Rules and data: Data.CommissionsLogs
-- (shared/GameData.lua, "Commissions & Logs" section).
-- Verbs (item <= 64 chars):
--   commissionClaim "<slot 1-4>"  claim a finished commission (once): skill XP,
--                                 coins and Glimmerdust (milestone boosts apply)
--   commissionClaimAll            claim every finished commission
--   forgeBuy "<perk id>"          buy the next Forgeheart level with Glimmerdust
--   logClaim "<tab>"              claim a completed Collection Log tab (coins + title, once)
--   logTitle "<tab>|Paragon|none" wear an unlocked title (attribute LogTitle)
--   museumDonate "<item id>"      donate one owned copy (consumed): refused when
--                                 already donated, not owned, or when it would take
--                                 the last copy held by gear/bag/upgrades (spares go)
--   logsBoard "<Commissions|Museum|Log>" (world prompt only) greeting text
--   logsSync                      resend the full snapshot.logs (client cache miss)
-- Hooks: Logs.prime before the gather stats (Forgeheart fortune budget),
-- Logs.regrow before Mastery.gather (Steadfast Pick joins the regrowth text),
-- Logs.gather after a harvest (commission progress, gem roll),
-- Logs.event from the kill bridge and Hunter catches, Logs.collect from collect().
-- Log credit: one full retroactive sweep on the first load only (no p.colLog
-- yet); afterwards entries come from collect() (drops, gathering, crafting)
-- plus a narrow sweep of adopted pets and the Treasure Trails clue log.
-- Items that land in p.items without collect() (Auction House, Bazaar, crew
-- withdrawals, refunds) never credit the log.
-- Snapshot: snapshot.logs is the full state (with .rev) when it changed since
-- the last one sent to this player, else {rev, resetIn, compact = true}.
-- Profile: p.commissions = {day, salt, slots = {{id, progress, claimed}}, total,
--   dust, earned, forge = {[perk] = level}}; p.colLog = {counts = {[item] = n},
--   claimed = {[tab] = true}, title = tab | "Paragon" | "", retro = n};
--   p.museum = {donated = {[item] = true}, count, paid}. All sanitised by
--   Logs.migrate (unknown ids dropped, numbers clamped).
-- Perks: p.perkStats["commissions:milestones"], ["forgeheart"], ["museum"].
-- A UTC day change auto-claims finished commissions, then draws a new board.
-- The board only rolls forward: a server clock behind the saved day keeps it.
-- Snapshot key: logs. Player attribute: LogTitle (title text or ""), shown on
-- a small billboard above the character's head (LogTitlePlate).
------------------------------------------------------------------------------
do
	local CL=Data.CommissionsLogs
	local MAX_COUNT=1e9
	if __LogsHarness then __LogsHarness(Logs) end -- headless tests only (nil in Roblox)
	local function whole(v,limit)
		local n=tonumber(v)
		if not n or n~=n or n<0 then return 0 end
		return math.floor(math.min(n,limit or MAX_COUNT))
	end
	local function itemName(id) return Data.Items[id] and Data.Items[id].name or tostring(id) end
	-- Session-only revisions: snapshot.logs is sent in full only when it changed.
	-- Strong tables, emptied when the player leaves (see the end of this block).
	local revOf={} -- [profile] = revision
	local sentRev={} -- [player] = revision last sent in full
	local profileOf={} -- [player] = profile whose revision was sent
	local lastRev=0
	local function bump(p) lastRev+=1; revOf[p]=lastRev end
	Logs.bump=bump
	function Logs.migrate(p)
		local c=type(p.commissions)=="table" and p.commissions or {}
		local out={day=whole(c.day),salt=whole(c.salt,1e6),slots={},total=whole(c.total,CL.MAX_TOTAL),dust=whole(c.dust,CL.MAX_DUST),earned=whole(c.earned,CL.MAX_DUST*10),forge={}}
		if out.salt==0 then out.salt=1+math.floor(roll()*999999) end
		if type(c.slots)=="table" then
			for _,s in ipairs(c.slots) do
				local t=type(s)=="table" and CL.TaskById[s.id]
				if t and #out.slots<CL.SLOTS then table.insert(out.slots,{id=t.id,progress=whole(s.progress,t.amount),claimed=s.claimed==true}) end
			end
		end
		if type(c.forge)=="table" then
			for id,f in pairs(CL.Forge) do
				local lvl=whole(c.forge[id],f.max)
				if lvl>0 then out.forge[id]=lvl end
			end
		end
		p.commissions=out
		local L=CL.log()
		local g=type(p.colLog)=="table" and p.colLog or nil
		local log={counts={},claimed={},title="",retro=0}
		if g then
			if type(g.counts)=="table" then for id,n in pairs(g.counts) do if L.Of[id] and whole(n)>0 then log.counts[id]=whole(n) end end end
			if type(g.claimed)=="table" then for tab,v in pairs(g.claimed) do if v==true and CL.LogTabs[tab] then log.claimed[tab]=true end end end
			if type(g.title)=="string" and (log.claimed[g.title] or (g.title=="Paragon" and CL.milestonePerks(out.total).title)) then log.title=g.title end
			log.retro=whole(g.retro,L.total)
		end
		p.colLog=log
		local m=type(p.museum)=="table" and p.museum or {}
		local museum={donated={},count=0,paid=0}
		if type(m.donated)=="table" then
			for id,v in pairs(m.donated) do if v==true and CL.museumCategory(id) then museum.donated[id]=true; museum.count+=1 end end
		end
		museum.paid=math.min(whole(m.paid,#CL.MuseumMilestones),select(2,CL.museumPerks(museum.count)))
		p.museum=museum
		-- First load of the log only: retroactive credit from what the journal
		-- already holds. Later loads never sweep p.items (bought/borrowed items).
		if not g then log.retro=Logs.sweep(p) else Logs.sweepOngoing(p) end
		Logs.refresh(p)
	end
	-- First-load sweep: raises log counts to what the journal provably obtained
	-- (lifetime collections, held items, worn gear, adopted pets, clue-log
	-- uniques, museum donations). Returns how many entries were newly credited.
	function Logs.sweep(p)
		local L=CL.log()
		local counts=p.colLog.counts
		local owned={}
		for _,pet in ipairs(type(p.pets)=="table" and p.pets or {}) do
			local id=type(pet)=="table" and type(pet.id)=="string" and pet.id.."Pet"
			if id then owned[id]=(owned[id] or 0)+1 end
		end
		for _,id in pairs(type(p.equipment)=="table" and p.equipment or {}) do if type(id)=="string" then owned[id]=math.max(owned[id] or 0,1) end end
		for _,id in ipairs(type(p.accessoryBag)=="table" and p.accessoryBag or {}) do if type(id)=="string" then owned[id]=math.max(owned[id] or 0,1) end end
		local trailUniques=type(p.trails)=="table" and type(p.trails.uniques)=="table" and p.trails.uniques or {}
		local fresh=0
		for id in pairs(L.Of) do
			local n=math.max(whole(p.items and p.items[id]),whole(p.collection and p.collection[id]),owned[id] or 0,whole(trailUniques[id]),if p.museum and p.museum.donated[id] then 1 else 0)
			local had=counts[id] or 0
			if n>had then
				counts[id]=n
				if had==0 then fresh+=1 end
			end
		end
		return fresh
	end
	-- Ongoing sweep (every load and snapshot, cheap): only adopted pets and the
	-- Treasure Trails clue log, which are earned and never traded in. Returns
	-- how many entries were newly credited.
	function Logs.sweepOngoing(p)
		local log=p.colLog
		if not log then return 0 end
		local L=CL.log()
		local counts=log.counts
		local seen={}
		for _,pet in ipairs(type(p.pets)=="table" and p.pets or {}) do
			local id=type(pet)=="table" and type(pet.id)=="string" and pet.id.."Pet"
			if id and L.Of[id] then seen[id]=(seen[id] or 0)+1 end
		end
		local trailUniques=type(p.trails)=="table" and type(p.trails.uniques)=="table" and p.trails.uniques or nil
		if trailUniques then
			for id,n in pairs(trailUniques) do if L.Of[id] then seen[id]=math.max(seen[id] or 0,whole(n)) end end
		end
		local fresh,changed=0,false
		for id,n in pairs(seen) do
			local had=counts[id] or 0
			if n>had then
				counts[id]=n
				changed=true
				if had==0 then fresh+=1 end
			end
		end
		if changed then bump(p) end
		return fresh
	end
	local function board(p) return p.commissions end
	local function context(p) return SlayerTasks.context(p) end
	local function pay(p,t)
		local c=board(p)
		local r=CL.reward(t,c.total)
		grantXp(p,r.skill,r.xp)
		p.coins+=r.coins
		c.dust=math.min(CL.MAX_DUST,c.dust+r.dust)
		c.earned=math.min(CL.MAX_DUST*10,c.earned+r.dust)
		local before=CL.milestonePerks(c.total).reached
		c.total=math.min(CL.MAX_TOTAL,c.total+1)
		local after=CL.milestonePerks(c.total).reached
		if after>before then
			for i=before+1,after do note(p,"Commission milestone: "..CL.Milestones[i].name.."! "..CL.Milestones[i].text) end
		end
		return r
	end
	-- Fortune budget: Forgeheart fills only what Mastery leaves under CL.FORTUNE_BUDGET.
	local function fortuneOf(p) return type(p.perkStats)=="table" and p.perkStats.forgeheart and p.perkStats.forgeheart.miningFortune or 0 end
	function Logs.prime(p)
		if type(p.perkStats)~="table" then p.perkStats={} end
		local c=p.commissions
		if not c then return end
		local mastery=(type(p.mastery)=="table" and Progression.masteryStats(p,os.time()).miningFortune) or 0
		local stats=CL.forgeStats(c.forge,mastery)
		p.perkStats.forgeheart=if next(stats) then stats else nil
	end
	-- True when the board must be drawn: a later UTC day, or an empty board.
	-- A server clock behind the saved day never redraws (forward only).
	local function stale(c,today) return today>c.day or #c.slots==0 end
	-- Full refresh: day roll (forward only), milestone/museum perks, Forgeheart.
	-- Runs on load, on a new day and after verbs, never on every snapshot.
	function Logs.refresh(p)
		local c=board(p)
		local today=CL.dayOf(os.time())
		if stale(c,today) then
			if today>c.day then
				local paid=0
				for _,s in ipairs(c.slots) do
					local t=CL.TaskById[s.id]
					if t and not s.claimed and s.progress>=t.amount then s.claimed=true; pay(p,t); paid+=1 end
				end
				if paid>0 then note(p,"Yesterday's finished commissions were claimed for you ("..paid..").") end
			end
			c.day=math.max(today,c.day)
			c.slots={}
			for _,id in ipairs(CL.draw(c.day,c.salt,context(p))) do table.insert(c.slots,{id=id,progress=0,claimed=false}) end
		end
		if type(p.perkStats)~="table" then p.perkStats={} end
		local perks=CL.milestonePerks(c.total)
		p.perkStats["commissions:milestones"]=if next(perks.stats) then table.clone(perks.stats) else nil
		local stats=CL.museumPerks(p.museum.count)
		p.perkStats.museum=if next(stats) then stats else nil
		Logs.prime(p)
		bump(p)
	end
	-- Cheap per-snapshot upkeep: a day change triggers the full refresh; the
	-- narrow pet/clue sweep and the Forgeheart budget bump the revision only
	-- when they change something.
	function Logs.tick(p)
		local c=p.commissions
		if not c then return end
		if stale(c,CL.dayOf(os.time())) then Logs.refresh(p) end
		Logs.sweepOngoing(p)
		local before=fortuneOf(p)
		Logs.prime(p)
		if fortuneOf(p)~=before then bump(p) end
	end
	-- Commission progress: kind "gather" (resource id), "kill" (monster id), "catch" (Hunter creature id).
	function Logs.event(p,kind,id)
		local c=p.commissions
		if not c or type(id)~="string" then return end
		if CL.dayOf(os.time())>c.day then Logs.refresh(p) end
		for _,s in ipairs(c.slots) do
			local t=CL.TaskById[s.id]
			if t and t.kind==kind and t.target==id and s.progress<t.amount then
				s.progress+=1
				bump(p)
				if s.progress>=t.amount then note(p,"Commission complete: "..t.name.."! Claim it in Journal › Commissions.") end
			end
		end
	end
	-- The only ongoing item credit: collect() (genuine drops, gathering, crafting).
	function Logs.collect(p,item,count)
		local log=p.colLog
		if not log or not CL.log().Of[item] or type(count)~="number" or count<=0 then return end
		local had=log.counts[item] or 0
		log.counts[item]=math.min(MAX_COUNT,had+math.floor(count))
		bump(p)
		if had==0 then note(p,"New Collection Log entry: "..itemName(item).."!") end
	end
	-- Steadfast Pick regrowth, before Mastery.gather so its "quick regrowth"
	-- text reports the combined timer (Mastery + Forgeheart, one cap).
	function Logs.regrow(p,result,resource)
		local c=p.commissions
		if not c or resource.skill~="Mining" then return end
		local skip=CL.forgeSkip(c.forge)
		if skip<=0 then return end
		local base=tonumber(resource.respawn) or 3
		local mastery=Progression.masteryPerks(p,"Mining",os.time()).respawnSkip or 0
		local total=math.max(mastery,math.min(Data.Mastery.PASSIVE_CAPS.respawnSkip,mastery+skip))
		result.regrowth=Progression.regrowthTime(base,total)
		if result.regrowth<base then result.respawnSkip=true end
	end
	-- After a harvest: commission progress and the Gemseeker roll (Mining).
	function Logs.gather(p,item,result,resource)
		Logs.event(p,"gather",item)
		if not p.commissions or resource.skill~="Mining" then return "" end
		local c=p.commissions
		local text=""
		local chance=CL.gemChance(c.forge,c.total)
		if chance>0 and roll()*100<chance then
			local gem=CL.gemFor(resource.index,roll())
			collect(p,gem,1)
			text="   ·   Gemseeker: +1 "..itemName(gem)
		end
		return text
	end
	function Logs.titleText(p)
		local t=p.colLog and p.colLog.title or ""
		if t=="Paragon" then return CL.milestonePerks(p.commissions.total).title or "" end
		local tab=CL.LogTabs[t]
		return tab and tab.title or ""
	end
	-- Title billboard: one small plate per titled character, sized in studs so
	-- it keeps its gap above the name tag at any distance; destroyed when the
	-- title is removed, rebuilt on respawn.
	local plates={} -- [player] = {head, board, label}
	local hooked={} -- [player] = CharacterAdded connection
	local function plate(player,text)
		local held=plates[player]
		if text=="" and not held then return end
		if text~="" and not hooked[player] and player.CharacterAdded then
			hooked[player]=player.CharacterAdded:Connect(function(character)
				task.spawn(function()
					local head=character:WaitForChild("Head",10)
					if head and player.Parent then plates[player]=nil; Logs.plate(player,player:GetAttribute("LogTitle") or "") end
				end)
			end)
		end
		local character=player.Character
		local head=character and character:FindFirstChild("Head")
		if text=="" or not head then
			if held then held.board:Destroy(); plates[player]=nil end
			return
		end
		if held and held.head==head and held.board.Parent then
			if held.label.Text~=text then held.label.Text=text end
			return
		end
		if held then held.board:Destroy() end
		local gui=Instance.new("BillboardGui")
		gui.Name="LogTitlePlate"
		gui.Size=UDim2.new(5,0,0.55,0)
		gui.StudsOffset=Vector3.new(0,3.3,0)
		gui.MaxDistance=60
		gui.LightInfluence=0
		gui.AlwaysOnTop=false
		local label=Instance.new("TextLabel")
		label.Name="Title"
		label.BackgroundTransparency=1
		label.Size=UDim2.fromScale(1,1)
		label.Font=Enum.Font.GothamBold
		label.TextScaled=true
		label.TextColor3=Color3.fromRGB(243,198,110)
		label.TextStrokeTransparency=0.35
		label.Text=text
		label.Parent=gui
		gui.Adornee=head
		gui.Parent=head
		plates[player]={head=head,board=gui,label=label}
	end
	Logs.plate=plate
	function Logs.applyTitle(player,p)
		local text=Logs.titleText(p)
		if player:GetAttribute("LogTitle")~=text then player:SetAttribute("LogTitle",text) end
		plate(player,text)
	end
	local function tabDone(p,tab)
		local list=CL.log().Tabs[tab]
		if not list or #list==0 then return false end
		for _,id in ipairs(list) do if (p.colLog.counts[id] or 0)<=0 then return false end end
		return true
	end
	Logs.tabDone=tabDone
	-- Donation check without changing anything: nil = allowed, else the refusal.
	-- Equipped, bagged and upgraded ids each hold copies back: a donation is
	-- refused only when it would take one of those held copies (a spare goes).
	function Logs.donateCheck(p,id)
		local cat=CL.museumCategory(id)
		if not cat then return "That item cannot be displayed in the Museum." end
		if p.museum.donated[id] then return itemName(id).." is already on display." end
		local have=p.items[id] or 0
		if have<1 then return "You do not own "..itemName(id).."." end
		local worn,bagged=0,0
		for _,eq in pairs(type(p.equipment)=="table" and p.equipment or {}) do if eq==id then worn+=1 end end
		for _,b in ipairs(type(p.accessoryBag)=="table" and p.accessoryBag or {}) do if b==id then bagged+=1 end end
		local upgraded=(type(p.reforges)=="table" and p.reforges[id]~=nil) or (type(p.stars)=="table" and (tonumber(p.stars[id]) or 0)>0)
			or (type(p.books)=="table" and p.books[id]~=nil) or (type(p.enchants)=="table" and type(p.enchants[id])=="table" and next(p.enchants[id])~=nil)
		if have>math.max(worn+bagged,if upgraded then 1 else 0) then return nil end
		if worn>0 then return "Unequip "..itemName(id).." before donating it (or donate a spare copy)." end
		if bagged>0 then return "Take "..itemName(id).." out of your accessory bag first (or donate a spare copy)." end
		return itemName(id).." carries upgrades; donate a spare copy instead."
	end
	function Logs.action(player,p,verb,item,prompt)
		if verb=="logsSync" then sentRev[player]=nil; return "" end
		Logs.tick(p)
		local c=board(p)
		local reply
		if verb=="logsBoard" then
			if not prompt then return "Visit the board in person." end
			if item=="Museum" then return "The Museum curator welcomes you • "..p.museum.count.." items on display." end
			if item=="Log" then local _,_,found=CL.logScore(p.colLog.counts); return "The Collection Log • "..found.." of "..CL.log().total.." entries." end
			return "The Commission Board • "..#c.slots.." commissions today, resets in "..math.ceil(CL.resetIn(os.time())/3600).."h."
		elseif verb=="commissionClaim" or verb=="commissionClaimAll" then
			local slots={}
			if verb=="commissionClaimAll" then
				for i=1,#c.slots do table.insert(slots,i) end
			else
				local i=tonumber(item)
				if not i or i~=math.floor(i) or not c.slots[i] then return "Unknown commission." end
				slots={i}
			end
			local done,dust,coins=0,0,0
			for _,i in ipairs(slots) do
				local s=c.slots[i]
				local t=CL.TaskById[s.id]
				if t and not s.claimed and s.progress>=t.amount then
					s.claimed=true
					local r=pay(p,t)
					done+=1; dust+=r.dust; coins+=r.coins
				end
			end
			if done==0 then return if verb=="commissionClaimAll" then "No finished commissions to claim." else "That commission is not finished (or already claimed)." end
			reply="Commission"..(if done>1 then "s" else "").." claimed • +"..coins.." coins, +"..dust.." Glimmerdust."
		elseif verb=="forgeBuy" then
			local f=CL.Forge[item]
			if not f then return "Unknown Forgeheart perk." end
			local lvl=c.forge[item] or 0
			local cost=CL.forgeCost(item,lvl,CL.milestonePerks(c.total).forgeDiscount)
			if not cost then return f.name.." is already mastered." end
			if c.dust<cost then return f.name.." "..(lvl+1).." needs "..cost.." Glimmerdust (you have "..c.dust..")." end
			c.dust-=cost
			c.forge[item]=lvl+1
			reply=f.name.." "..(lvl+1).."/"..f.max.." forged • -"..cost.." Glimmerdust."
		elseif verb=="logClaim" then
			local tab=CL.LogTabs[item]
			if not tab then return "Unknown log tab." end
			if p.colLog.claimed[item] then return "That tab's reward is already claimed." end
			if not tabDone(p,item) then return "Complete every "..tab.name.." entry first." end
			p.colLog.claimed[item]=true
			p.coins+=tab.coins
			reply=tab.name.." log complete • +"..tab.coins.." coins and the "..tab.title.." title."
		elseif verb=="logTitle" then
			if item=="none" then p.colLog.title=""
			elseif item=="Paragon" and CL.milestonePerks(c.total).title then p.colLog.title="Paragon"
			elseif CL.LogTabs[item] and p.colLog.claimed[item] then p.colLog.title=item
			else return "Title not unlocked." end
			reply=if p.colLog.title=="" then "Title removed." else "Now titled: "..Logs.titleText(p).."."
		elseif verb=="museumDonate" then
			local refusal=Logs.donateCheck(p,item)
			if refusal then return refusal end
			if not spend(p,{[item]=1}) then return "You do not own "..itemName(item).."." end
			local m=p.museum
			m.donated[item]=true
			m.count+=1
			local coins=0
			local _,reached=CL.museumPerks(m.count)
			for i=m.paid+1,reached do coins+=CL.MuseumMilestones[i].coins end
			m.paid=math.max(m.paid,reached)
			p.coins+=coins
			reply=itemName(item).." donated to the Museum ("..m.count.." on display)"..(if coins>0 then " • milestone! +"..coins.." coins" else "").."."
		else
			return "Unknown action."
		end
		p.started=true
		Logs.refresh(p) -- perks, Forgeheart budget and a new revision after every change
		Logs.applyTitle(player,p)
		return reply
	end
	function Logs.state(player,p)
		if not p.commissions then return nil end
		Logs.tick(p)
		Logs.applyTitle(player,p)
		local c=p.commissions
		local now=os.time()
		if not revOf[p] then bump(p) end
		local rev=revOf[p]
		profileOf[player]=p
		if sentRev[player]==rev then return {rev=rev,resetIn=CL.resetIn(now),compact=true} end
		sentRev[player]=rev
		local slots={}
		for i,s in ipairs(c.slots) do
			local t=CL.TaskById[s.id]
			slots[i]={id=s.id,progress=s.progress,claimed=s.claimed,done=s.progress>=t.amount,reward=CL.reward(t,c.total)}
		end
		local perks=CL.milestonePerks(c.total)
		local costs={}
		for id in pairs(CL.Forge) do costs[id]=CL.forgeCost(id,c.forge[id] or 0,perks.forgeDiscount) end
		local score,max,found=CL.logScore(p.colLog.counts)
		local rank=CL.logRank(score,max)
		local complete={}
		for _,tab in ipairs(CL.log().Order) do complete[tab]=tabDone(p,tab) end
		local _,reached=CL.museumPerks(p.museum.count)
		return {
			rev=rev,
			commissions={day=c.day,resetIn=CL.resetIn(now),slots=slots,total=c.total,dust=c.dust,earned=c.earned,milestone=perks.reached,
				forge=table.clone(c.forge),costs=costs,discount=perks.forgeDiscount,gemChance=CL.gemChance(c.forge,c.total),
				fortune=fortuneOf(p),paragon=perks.title},
			log={counts=table.clone(p.colLog.counts),claimed=table.clone(p.colLog.claimed),complete=complete,title=p.colLog.title,titleText=Logs.titleText(p),score=score,max=max,found=found,rank=rank.name,retro=p.colLog.retro},
			museum={donated=table.clone(p.museum.donated),count=p.museum.count,milestone=reached,stats=table.clone(p.perkStats.museum or {})},
		}
	end
	Players.PlayerRemoving:Connect(function(player)
		if profileOf[player] then revOf[profileOf[player]]=nil end
		if hooked[player] then hooked[player]:Disconnect() end
		sentRev[player],profileOf[player],plates[player],hooked[player]=nil,nil,nil,nil
	end)
end
-- End Commissions & Logs block.
------------------------------------------------------------------------------
-- Exploration & Factions (Exploration & Factions team; self-contained block).
-- Rules and data: Data.Exploration / Data.Factions (shared/GameData.lua,
-- "Exploration & Factions" section); contract docs/DEPTH-CONTRACT.md §24.
-- Verbs (item <= 64 chars):
--   moteCollect                 pick up the nearest unfound Aether Mote within
--                               EX.PICKUP_RADIUS of the character (the client's
--                               item is ignored: no client-trusted ids); region
--                               access and the mote's Agility gate are checked.
--                               Anti-teleport: EX.DWELL_SECONDS inside the
--                               mote's island region since arriving, and the
--                               implied travel speed since the last pickup at
--                               most EX.SPEED_FACTOR x WalkSpeed unless a known
--                               fast travel (FastTravelAt attribute: leaf,
--                               recall, ferry; or a respawn) came in between;
--                               refusals do not consume the pickup cooldown.
--                               Perch motes need the root within
--                               EX.PERCH_VERTICAL studs of the mote's height.
--   moteShrine "<region>"       (world prompt only) claim every pending
--                               milestone step and that region's completion bonus
--   moteHint                    buy a Wayglass bearing: the nearest reachable
--                               unfound mote in the island region you stand in
--   factionPledge "<faction>"   first pledge free; a change costs
--                               FA.SWITCH_COST coins, needs FA.SWITCH_COOLDOWN
--                               since the last pledge and forfeits 25% of the
--                               old faction's reputation
--   factionClaim "<faction>:<slot>|all"   claim finished kill/gather tasks
--   factionDeliver "<faction>:<slot>"     hand in a delivery task's items
--   factionBuy "<shop id>[:<skill>]"      rank/pledge-gated shop (lamps name a skill)
--   factionTitle "<shop id>|none"         wear an owned faction title
--   factionBoard "<faction>"    (world prompt only) greeting text
--   exploreSync                 resend the full snapshot.exploration (client cache miss)
-- Hooks: Logs.event is wrapped (kill/gather credits faction tasks too; a
-- failing Explore.event is caught and warned, never breaking the Logs credit).
-- Explore.refresh runs at the top of snapshot() so a day roll's note joins it.
-- Snapshot: snapshot.exploration is the full state (with .rev) when it changed
-- since the last one sent to this player, else {rev, resetIn, switchIn, compact = true}.
-- Profile: p.motes = {found = {[id] = true}, count, steps, regions = {[region] = true},
--   paid = {[region] = true} (completion coins paid once, ever), hints};
--   p.factions = {pledge, pledgedAt, switches, day, salt, rep, sigils, done,
--   boards = {[faction] = {{id, progress, claimed}}}, unlocks = {[shopId] = true}, title}.
--   Both sanitised by Explore.migrate (unknown ids dropped, numbers clamped).
-- Perks: p.perkStats.motes (EX.perkStats). Snapshot key: exploration.
-- Player attributes: MoteHint (mote id or ""), MoteHintUntil (os.time),
--   FactionPledge (faction id or ""), FactionTitle (title text or "").
------------------------------------------------------------------------------
local Explore={verbs={moteCollect=true,moteShrine=true,moteHint=true,factionPledge=true,factionClaim=true,factionDeliver=true,
	factionBuy=true,factionTitle=true,factionBoard=true,exploreSync=true}}
do
	local EX,FA=Data.Exploration,Data.Factions
	if __ExploreHarness then __ExploreHarness(Explore) end -- headless tests only (nil in Roblox)
	-- Session-only revisions: snapshot.exploration is sent in full only when it
	-- changed (Logs pattern). Strong tables, emptied when the player leaves.
	local revOf={} -- [profile] = revision
	local sentRev={} -- [player] = revision last sent in full
	local keyOf={} -- [profile] = context key (Agility level, region access, live bearing)
	local profileOf={} -- [player] = profile whose revision was sent
	local lastRev=0
	local function bump(p) lastRev+=1; revOf[p]=lastRev end
	Explore.bump=bump
	local function whole(v,limit)
		local n=tonumber(v)
		if not n or n~=n or n<0 then return 0 end
		return math.floor(math.min(n,limit or 1e9))
	end
	-- Island centres from the world anchors (Workspace.Islands, contract §10).
	local isles={} -- [isle name] = {center, radius, region}
	local function isleInfo(name)
		local info=isles[name]
		if info then return info end
		local root=workspace:FindFirstChild("Islands")
		local model=root and root:FindFirstChild(name)
		local center=model and model:GetAttribute("IslandCenter")
		if typeof(center)~="Vector3" then return nil end
		info={center=center,radius=tonumber(model:GetAttribute("IslandRadius")) or 0,region=EX.IsleRegion[name]}
		isles[name]=info
		return info
	end
	function Explore.motePosition(mote)
		local info=isleInfo(mote.isle)
		return info and info.center+Vector3.new(mote.at[1],mote.at[2],mote.at[3]) or nil
	end
	local function rootOf(player)
		local character=player.Character
		local root=character and character:FindFirstChild("HumanoidRootPart")
		return root and root.Position or nil
	end
	-- The island region a position stands in (nearest island within its radius +
	-- `reach` studs: 70 for the Wayglass, EX.TRACK_REACH for the pickup dwell, so
	-- the far arenas and bridge ends still count as their island).
	local function regionAt(pos,reach)
		local best,bestGap=nil,reach or 70
		for name,region in pairs(EX.IsleRegion) do
			local info=isleInfo(name)
			if info then
				local gap=Vector3.new(pos.X-info.center.X,0,pos.Z-info.center.Z).Magnitude-info.radius
				if gap<bestGap then best,bestGap=region,gap end
			end
		end
		return best
	end
	local function agility(p) return level(p.xp.Agility) end
	------------------------------------------------------------------------
	-- Migration.
	------------------------------------------------------------------------
	local function context(p)
		local levels={}
		for _,skill in ipairs(Data.SkillOrder) do levels[skill]=level(p.xp[skill]) end
		local regions={}
		for _,r in ipairs(Data.Regions) do if regionAllowed(p,r.id) then regions[r.id]=true end end
		return {levels=levels,regions=regions}
	end
	local function motePerks(p)
		if type(p.perkStats)~="table" then p.perkStats={} end
		local m=p.motes
		local regions=0
		for _ in pairs(m.regions) do regions+=1 end
		local stats=EX.perkStats(m.steps,regions)
		p.perkStats.motes=if next(stats) then stats else nil
	end
	function Explore.migrate(p)
		local m=type(p.motes)=="table" and p.motes or {}
		local motes={found={},count=0,steps=0,regions={},paid={},hints=whole(m.hints,1e6)}
		if type(m.found)=="table" then
			for id,v in pairs(m.found) do if v==true and EX.MoteById[id] then motes.found[id]=true; motes.count+=1 end end
		end
		-- Steps are never clamped down to the motes found (a content update that
		-- moves or removes motes must not let a milestone pay twice): claimable
		-- is max(0, floor(count / STEP) - steps).
		motes.steps=whole(m.steps,EX.STEPS)
		-- Completion coins are paid once per region, ever (paid survives a region
		-- claim dropped because an update added motes to it). Older saves: every
		-- region they had claimed was paid.
		for _,source in ipairs({m.paid,m.regions}) do
			if type(source)=="table" then
				for region,v in pairs(source) do if v==true and EX.RegionTotal[region] then motes.paid[region]=true end end
			end
		end
		if type(m.regions)=="table" then
			for region,v in pairs(m.regions) do
				if v==true and EX.RegionTotal[region] then
					local all=true
					for _,id in ipairs(EX.MotesByRegion[region]) do if not motes.found[id] then all=false end end
					if all then motes.regions[region]=true end
				end
			end
		end
		p.motes=motes
		motePerks(p)
		local f=type(p.factions)=="table" and p.factions or {}
		local out={pledge="",pledgedAt=whole(f.pledgedAt,4e9),switches=whole(f.switches,1e6),day=whole(f.day),salt=whole(f.salt,1e6),
			rep={},sigils={},done={},boards={},unlocks={},title="",total=whole(f.total,1e9)}
		if type(f.pledge)=="string" and FA.Factions[f.pledge] then out.pledge=f.pledge end
		if out.salt==0 then out.salt=1+math.floor(roll()*999999) end
		for _,id in ipairs(FA.Order) do
			out.rep[id]=whole(type(f.rep)=="table" and f.rep[id],FA.REP_CAP)
			out.sigils[id]=whole(type(f.sigils)=="table" and f.sigils[id],FA.SIGIL_CAP)
			out.done[id]=whole(type(f.done)=="table" and f.done[id],1e9)
			local list={}
			local saved=type(f.boards)=="table" and f.boards[id]
			if type(saved)=="table" then
				for _,s in ipairs(saved) do
					local t=type(s)=="table" and FA.TaskById[s.id]
					if t and t.faction==id and #list<FA.TASKS then table.insert(list,{id=t.id,progress=whole(s.progress,t.amount),claimed=s.claimed==true}) end
				end
			end
			out.boards[id]=list
		end
		if type(f.unlocks)=="table" then
			for id,v in pairs(f.unlocks) do
				local e=v==true and FA.ShopById[id]
				if e and e.kind=="title" then out.unlocks[id]=true end
			end
		end
		if type(f.title)=="string" and out.unlocks[f.title] then out.title=f.title end
		p.factions=out
		Explore.refresh(p)
		bump(p)
	end
	------------------------------------------------------------------------
	-- Faction boards: UTC day roll (forward only), auto-claim on a new day.
	------------------------------------------------------------------------
	local function pay(p,t)
		local f=p.factions
		local r=FA.reward(t,f.pledge)
		f.rep[t.faction]=math.min(FA.REP_CAP,f.rep[t.faction]+r.rep)
		f.sigils[t.faction]=math.min(FA.SIGIL_CAP,f.sigils[t.faction]+r.sigils)
		f.done[t.faction]+=1
		f.total=math.min(1e9,f.total+1)
		p.coins+=r.coins
		if r.xp>0 and r.skill then grantXp(p,r.skill,r.xp) end
		return r
	end
	-- Any faction's board short of FA.TASKS (new journal, dropped unknown tasks).
	local function short(f)
		for _,id in ipairs(FA.Order) do if #(f.boards[id] or {})<FA.TASKS then return true end end
		return false
	end
	local function stale(f,today) return today>f.day or short(f) end
	function Explore.refresh(p)
		local f=p.factions
		if not f then return end
		local today=FA.dayOf(os.time())
		if not stale(f,today) then return end
		if today<=f.day then
			-- Same day: top up only the short boards, keeping every saved task
			-- (and its progress); a full board is never redrawn mid-day.
			local ctx,changed=context(p),false
			for _,id in ipairs(FA.Order) do
				local list=f.boards[id] or {}
				f.boards[id]=list
				if #list<FA.TASKS then
					local have={}
					for _,s in ipairs(list) do have[s.id]=true end
					for _,tid in ipairs(FA.draw(id,f.day,f.salt,ctx)) do
						if #list<FA.TASKS and not have[tid] then table.insert(list,{id=tid,progress=0,claimed=false}); have[tid]=true; changed=true end
					end
				end
			end
			if changed then bump(p) end
			return
		end
		bump(p)
		if today>f.day then
			local paid=0
			for _,id in ipairs(FA.Order) do
				for _,s in ipairs(f.boards[id]) do
					local t=FA.TaskById[s.id]
					if t and t.kind~="deliver" and not s.claimed and s.progress>=t.amount then s.claimed=true; pay(p,t); paid+=1 end
				end
			end
			if paid>0 then note(p,"Yesterday's finished faction tasks were claimed for you ("..paid..").") end
		end
		f.day=math.max(today,f.day)
		local ctx=context(p)
		for _,id in ipairs(FA.Order) do
			local list={}
			for _,tid in ipairs(FA.draw(id,f.day,f.salt,ctx)) do table.insert(list,{id=tid,progress=0,claimed=false}) end
			f.boards[id]=list
		end
	end
	-- Task progress: kind "kill" (monster id) or "gather" (resource id).
	function Explore.event(p,kind,id)
		local f=p.factions
		if not f or type(id)~="string" or (kind~="kill" and kind~="gather") then return end
		if FA.dayOf(os.time())>f.day then Explore.refresh(p) end
		for _,fid in ipairs(FA.Order) do
			for _,s in ipairs(f.boards[fid]) do
				local t=FA.TaskById[s.id]
				if t and t.kind==kind and t.target==id and s.progress<t.amount then
					s.progress+=1
					bump(p)
					if s.progress>=t.amount then note(p,FA.Factions[fid].short.." task complete: claim it in Journal › Factions.") end
				end
			end
		end
	end
	-- Every Commissions & Logs progress event (kill bridge, harvests) also
	-- feeds the faction boards: one hook, no new call sites. One event advances
	-- every board holding a matching task (no deduplication; FA.taskSeconds
	-- models the shared work). A faction error never breaks the Logs credit.
	local logsEvent=Logs.event
	Logs.event=function(p,kind,id)
		logsEvent(p,kind,id)
		local okEvent,problem=pcall(Explore.event,p,kind,id)
		if not okEvent then warn("Explore.event failed: "..tostring(problem)) end
	end
	local function titleText(p)
		local e=p.factions and p.factions.title~="" and FA.ShopById[p.factions.title]
		return e and e.title or ""
	end
	local function publish(player,p)
		local pledge=p.factions and p.factions.pledge or ""
		if player:GetAttribute("FactionPledge")~=pledge then player:SetAttribute("FactionPledge",pledge) end
		local title=titleText(p)
		if player:GetAttribute("FactionTitle")~=title then player:SetAttribute("FactionTitle",title) end
	end
	------------------------------------------------------------------------
	-- Motes.
	------------------------------------------------------------------------
	local lastPickup={} -- [player] = os.clock() before which the next pickup is refused
	local lastFind={} -- [player] = {pos, t} of the last credited pickup (os.clock)
	local track={} -- [player] = {root, pos, t, region, since, travel, mark}: server position samples
	local function nearestUnfound(p,pos,radius,filter)
		local best,bestDist=nil,radius
		for _,mote in ipairs(EX.Motes) do
			if not p.motes.found[mote.id] and (not filter or filter(mote)) then
				local at=Explore.motePosition(mote)
				if at then
					local d=(at-pos).Magnitude
					if d<=bestDist then best,bestDist=mote,d end
				end
			end
		end
		return best,bestDist
	end
	local function flat(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
	-- Fastest honest horizontal travel: SPEED_FACTOR x the server's WalkSpeed.
	local function speedLimit(player)
		local character=player.Character
		local humanoid=character and character:FindFirstChildOfClass("Humanoid")
		local walk=humanoid and tonumber(humanoid.WalkSpeed) or EX.BASE_WALK
		return EX.SPEED_FACTOR*math.max(EX.BASE_WALK,walk)
	end
	-- One position sample (slow server tick, and at every pickup). A new
	-- HumanoidRootPart (respawn) or a changed FastTravelAt attribute (set by
	-- the server's own teleports: waystone leaves, recall charms, the ferry,
	-- the teleport spell) records a known fast travel. A jump faster than the
	-- speed limit between samples, or a change of island region, restarts
	-- the dwell clock.
	function Explore.sample(player)
		local character=player.Character
		local root=character and character:FindFirstChild("HumanoidRootPart")
		if not root then track[player]=nil return nil end
		local now=os.clock()
		local pos=root.Position
		local region=regionAt(pos,EX.TRACK_REACH)
		local mark=player:GetAttribute("FastTravelAt")
		local tr=track[player]
		if not tr or tr.root~=root then
			tr={root=root,pos=pos,t=now,region=region,since=now,travel=now,mark=mark}
			track[player]=tr
			return tr
		end
		if mark~=tr.mark then tr.mark=mark; tr.travel=now end
		if flat(pos,tr.pos)>speedLimit(player)*math.max(0,now-tr.t)+EX.SPEED_SLACK then tr.since=now end
		if region~=tr.region then tr.region,tr.since=region,now end
		tr.pos,tr.t=pos,now
		return tr
	end
	function Explore.trackRegion(pos) return regionAt(pos,EX.TRACK_REACH) end
	task.spawn(function()
		while true do
			task.wait(EX.SAMPLE_SECONDS)
			for _,player in ipairs(Players:GetPlayers()) do
				if profiles[player] then pcall(Explore.sample,player) end
			end
		end
	end)
	-- Steps claimed are never clamped down, so a shrunken count claims nothing.
	local function claimable(p) return math.max(0,math.floor(p.motes.count/EX.STEP)-p.motes.steps) end
	local function regionDone(p,region)
		for _,id in ipairs(EX.MotesByRegion[region] or {}) do if not p.motes.found[id] then return false end end
		return (EX.RegionTotal[region] or 0)>0
	end
	local function collectMote(player,p)
		local pos=rootOf(player)
		if not pos then return "Return to your island first." end
		local now=os.clock()
		if now<(lastPickup[player] or 0) then return "One moment…" end
		local tr=Explore.sample(player)
		-- Perch motes need the root at the perch's height (no jumping up to them).
		local mote=nearestUnfound(p,pos,EX.PICKUP_RADIUS,function(mote)
			if mote.agility<=0 then return true end
			local at=Explore.motePosition(mote)
			return at~=nil and math.abs(pos.Y-at.Y)<=EX.PERCH_VERTICAL
		end)
		if not mote then return "No unfound "..EX.MOTE.name.." within reach." end
		-- Anti-teleport (refusals keep the cooldown unspent).
		if not tr or tr.region~=mote.region or now-tr.since<EX.DWELL_SECONDS then
			return "The motes here are still settling around you. Give them a few seconds."
		end
		local last=lastFind[player]
		if last and not (tr.travel>=last.t) and flat(pos,last.pos)>speedLimit(player)*math.max(0,now-last.t)+EX.SPEED_SLACK then
			return "The motes scatter from such a sudden arrival. Travel on foot, by waystone leaf or by recall charm."
		end
		lastPickup[player]=now+EX.PICKUP_COOLDOWN
		if not regionAllowed(p,mote.region) then return regionDenied(mote.region) end
		if not EX.canReach(mote,agility(p)) then return "This mote drifts over an Agility "..mote.agility.." course; train Agility to claim it." end
		local m=p.motes
		lastFind[player]={pos=pos,t=now}
		m.found[mote.id]=true
		m.count+=1
		local text=EX.MOTE.name.." found! ("..m.count.." / "..EX.TOTAL..")"
		if p.motes.count%EX.STEP==0 then text..="   ·   A milestone awaits at any Mote Shrine." end
		if regionDone(p,mote.region) and not m.regions[mote.region] then
			text..="   ·   Every mote of "..((Data.RegionById[mote.region] or {}).name or mote.region).." found: visit its shrine."
		end
		if player:GetAttribute("MoteHint")==mote.id then player:SetAttribute("MoteHint",""); player:SetAttribute("MoteHintUntil",0) end
		return text
	end
	local function shrine(player,p,region)
		if not EX.ShrineIsle[region] then return "Unknown shrine." end
		local m=p.motes
		local parts={}
		local steps=claimable(p)
		if steps>0 then
			local coins=0
			for s=m.steps+1,m.steps+steps do coins+=EX.stepCoins(s) end
			m.steps+=steps
			p.coins+=coins
			table.insert(parts,steps.." milestone"..(if steps==1 then "" else "s").." claimed (+"..coins.." coins)")
		end
		if regionDone(p,region) and not m.regions[region] then
			m.regions[region]=true
			local name=(Data.RegionById[region] or {}).name or region
			if m.paid[region] then
				-- Re-completed after a content update: the Health returns, the coins were paid once already.
				table.insert(parts,name.." complete again! +"..EX.REGION_HEALTH.." Health")
			else
				m.paid[region]=true
				local coins=EX.regionCoins(region)
				p.coins+=coins
				table.insert(parts,name.." complete! +"..coins.." coins, +"..EX.REGION_HEALTH.." Health")
			end
		end
		motePerks(p)
		if #parts==0 then
			local here=0
			for _,id in ipairs(EX.MotesByRegion[region]) do if m.found[id] then here+=1 end end
			return "The Mote Shrine hums • "..m.count.." / "..EX.TOTAL.." found ("..here.." / "..EX.RegionTotal[region].." here). Next milestone at "..((m.steps+1)*EX.STEP).."."
		end
		p.started=true
		return table.concat(parts,"   ·   ").."."
	end
	local function hint(player,p)
		local pos=rootOf(player)
		if not pos then return "Return to your island first." end
		local region=regionAt(pos)
		if not region then return "Stand on an island to take a Wayglass bearing." end
		local lvl=agility(p)
		local mote,dist=nearestUnfound(p,pos,1e6,function(mote) return mote.region==region and EX.canReach(mote,lvl) end)
		if not mote then
			local gated=nearestUnfound(p,pos,1e6,function(mote) return mote.region==region end)
			if gated then return "The motes left here drift over Agility "..gated.agility.." courses." end
			return "Every mote of "..((Data.RegionById[region] or {}).name or region).." is already found."
		end
		local cost=EX.hintCost(p.motes.count)
		if p.coins<cost then return "A Wayglass bearing costs "..cost.." coins." end
		p.coins-=cost
		p.motes.hints=math.min(1e6,p.motes.hints+1)
		player:SetAttribute("MoteHint",mote.id)
		player:SetAttribute("MoteHintUntil",os.time()+EX.HINT_SECONDS)
		return "The Wayglass points "..math.floor(dist).." studs away: "..mote.hint..". (-"..cost.." coins)"
	end
	------------------------------------------------------------------------
	-- Faction verbs.
	------------------------------------------------------------------------
	local function slotOf(f,item)
		local fid,slot=string.match(tostring(item),"^(%a+):(%d+)$")
		local board=fid and f.boards[fid]
		local i=tonumber(slot)
		if not board or not i or not board[i] then return nil end
		return fid,i,board[i],FA.TaskById[board[i].id]
	end
	local function factionAction(player,p,verb,item,prompt)
		Explore.refresh(p)
		local f=p.factions
		if verb=="factionBoard" then
			if not prompt then return "Visit the faction's standard in person." end
			local def=FA.Factions[item]
			if not def then return "Unknown faction." end
			local _,rank=FA.rankOf(f.rep[item])
			return def.name.." • \""..def.motto.."\" • "..rank.name.." ("..f.rep[item].." reputation)."
		elseif verb=="factionPledge" then
			local def=FA.Factions[item]
			if not def then return "Unknown faction." end
			if f.pledge==item then return "You are already pledged to the "..def.name.."." end
			local now=os.time()
			if f.pledge~="" then
				local wait=f.pledgedAt+FA.SWITCH_COOLDOWN-now
				if wait>0 then return "Your pledge to the "..FA.Factions[f.pledge].name.." holds for another "..math.ceil(wait/3600).."h." end
				if p.coins<FA.SWITCH_COST then return "Changing a pledge costs "..FA.SWITCH_COST.." coins." end
				p.coins-=FA.SWITCH_COST
				local old=f.pledge
				local lost=math.floor(f.rep[old]*FA.SWITCH_FORFEIT)
				f.rep[old]-=lost
				f.switches+=1
				f.pledge,f.pledgedAt=item,now
				publish(player,p)
				p.started=true
				return "You renounce the "..FA.Factions[old].name.." (-"..lost.." reputation, -"..FA.SWITCH_COST.." coins) and pledge to the "..def.name.."."
			end
			f.pledge,f.pledgedAt=item,now
			publish(player,p)
			p.started=true
			return "You pledge to the "..def.name..". Its rival, the "..FA.Factions[def.rival].name..", will trust you less."
		elseif verb=="factionClaim" then
			local list={}
			if item=="all" then
				for _,fid in ipairs(FA.Order) do for i=1,#f.boards[fid] do table.insert(list,fid..":"..i) end end
			else
				if not slotOf(f,item) then return "Unknown faction task." end
				list={item}
			end
			local done,rep,coins=0,0,0
			for _,key in ipairs(list) do
				local _,_,s,t=slotOf(f,key)
				if t and t.kind~="deliver" and not s.claimed and s.progress>=t.amount then
					s.claimed=true
					local r=pay(p,t)
					done+=1; rep+=r.rep; coins+=r.coins
				end
			end
			if done==0 then return if item=="all" then "No finished faction tasks to claim." else "That task is not finished (or already claimed)." end
			p.started=true
			return "Faction task"..(if done>1 then "s" else "").." claimed • +"..rep.." reputation, +"..coins.." coins."
		elseif verb=="factionDeliver" then
			local fid,_,s,t=slotOf(f,item)
			if not t then return "Unknown faction task." end
			if t.kind~="deliver" then return "That task is not a delivery." end
			if s.claimed then return "Already delivered today." end
			local name=Data.Items[t.target] and Data.Items[t.target].name or t.target
			if not spend(p,{[t.target]=t.amount}) then return "Deliver "..t.amount.." "..name.." (you have "..(p.items[t.target] or 0)..")." end
			s.progress=t.amount
			s.claimed=true
			local r=pay(p,t)
			p.started=true
			return "Delivered "..t.amount.." "..name.." to the "..FA.Factions[fid].name.." • +"..r.rep.." reputation, +"..r.sigils.." sigils, +"..r.coins.." coins."
		elseif verb=="factionBuy" then
			local id,skill=string.match(tostring(item),"^(%w+):?(%a*)$")
			local e,why=FA.canBuy(id or "",f,p.coins,skill,nil)
			if not e then return why end
			local def=FA.Factions[e.faction]
			if e.kind=="crest" then
				-- Upgrade: needs a spare charm (not bagged, reforged or enchanted).
				local charm=e.consumes
				local held=p.items[charm] or 0
				local bagged=table.find(p.accessoryBag or {},charm)~=nil
				-- Same last-copy rule as a Museum donation: reforges, stars, books, enchants.
				local upgraded=(type(p.reforges)=="table" and p.reforges[charm]~=nil) or (type(p.stars)=="table" and (tonumber(p.stars[charm]) or 0)>0)
					or (type(p.books)=="table" and p.books[charm]~=nil) or (type(p.enchants)=="table" and type(p.enchants[charm])=="table" and next(p.enchants[charm])~=nil)
				if held<1 then return "The "..Data.Items[e.item].name.." is forged from a "..Data.Items[charm].name.."." end
				if held<2 and (bagged or upgraded) then return "Take your "..Data.Items[charm].name.." out of the accessory bag (and off the anvil) first." end
			end
			f.sigils[e.faction]-=e.sigils
			p.coins-=e.coins or 0
			p.started=true
			if e.kind=="title" then
				f.unlocks[e.id]=true
				f.title=e.id
				publish(player,p)
				return "Earned the "..e.title.." title of the "..def.name..". Wearing it now."
			elseif e.kind=="lamp" then
				local xp=FA.lampXp(skill,level(p.xp[skill]))
				grantXp(p,skill,xp)
				return "The "..def.short.." lamp flares: +"..xp.." "..skill.." XP (-"..e.sigils.." sigils)."
			elseif e.kind=="crest" then
				spend(p,{[e.consumes]=1})
				collect(p,e.item,1)
				return "Your "..Data.Items[e.consumes].name.." is reforged into the "..Data.Items[e.item].name.."!"
			end
			collect(p,e.item,1)
			return "Bought the "..Data.Items[e.item].name.." (-"..e.sigils.." sigils, -"..(e.coins or 0).." coins)."
		elseif verb=="factionTitle" then
			if item=="none" then f.title=""
			elseif type(item)=="string" and f.unlocks[item] then f.title=item
			else return "You do not hold that title." end
			publish(player,p)
			return if f.title=="" then "Faction title hidden." else "Now titled: "..titleText(p).."."
		end
		return "Unknown action."
	end
	function Explore.action(player,p,verb,item,prompt)
		if not p.motes or not p.factions then Explore.migrate(p) end
		local reply
		if verb=="moteCollect" then reply=collectMote(player,p)
		elseif verb=="moteShrine" then
			if not prompt then return "Visit a Mote Shrine in person." end
			reply=shrine(player,p,item)
		elseif verb=="moteHint" then reply=hint(player,p)
		elseif verb=="exploreSync" then sentRev[player]=nil; return ""
		else reply=factionAction(player,p,verb,item,prompt) end
		bump(p) -- any verb may change the state: the next snapshot carries it in full
		return reply
	end
	-- What the full state reads from outside p.motes / p.factions: a change
	-- (Agility level, region access, a bearing set or faded) bumps the revision.
	local function contextKey(player,p)
		local parts={tostring(agility(p))}
		for _,region in ipairs(EX.RegionOrder) do table.insert(parts,if regionAllowed(p,region) then "1" else "0") end
		local hintId=player:GetAttribute("MoteHint")
		local hintUntil=tonumber(player:GetAttribute("MoteHintUntil")) or 0
		table.insert(parts,if type(hintId)=="string" and hintId~="" and hintUntil>os.time() then hintId else "")
		return table.concat(parts,":")
	end
	function Explore.state(player,p)
		if not p.motes or not p.factions then return nil end
		publish(player,p)
		local f=p.factions
		local now=os.time()
		local switchIn=if f.pledge~="" then math.max(0,f.pledgedAt+FA.SWITCH_COOLDOWN-now) else 0
		local key=contextKey(player,p)
		if keyOf[p]~=key then keyOf[p]=key; bump(p) end
		if not revOf[p] then bump(p) end
		local rev=revOf[p]
		profileOf[player]=p
		if sentRev[player]==rev then return {rev=rev,resetIn=FA.resetIn(now),switchIn=switchIn,compact=true} end
		sentRev[player]=rev
		local m=p.motes
		local bits=table.create(EX.TOTAL,"0")
		for i,mote in ipairs(EX.Motes) do if m.found[mote.id] then bits[i]="1" end end
		local regions={}
		for _,region in ipairs(EX.RegionOrder) do
			local here=0
			for _,id in ipairs(EX.MotesByRegion[region]) do if m.found[id] then here+=1 end end
			regions[region]={found=here,total=EX.RegionTotal[region],claimed=m.regions[region]==true,allowed=regionAllowed(p,region)}
		end
		local factions={}
		for _,id in ipairs(FA.Order) do
			local index,rank,nextRank=FA.rankOf(f.rep[id])
			local board={}
			-- Derivable fields stay on the client: done = progress >= amount,
			-- reward = FA.reward(task, pledge), items held from snapshot.items.
			for i,s in ipairs(f.boards[id]) do board[i]={id=s.id,progress=s.progress,claimed=s.claimed} end
			factions[id]={rep=f.rep[id],sigils=f.sigils[id],done=f.done[id],rank=index,rankName=rank.name,nextAt=nextRank and nextRank.at or nil,mult=FA.mult(id,f.pledge),board=board}
		end
		local unlocks={}
		for id in pairs(f.unlocks) do table.insert(unlocks,id) end
		table.sort(unlocks)
		local hintId=player:GetAttribute("MoteHint")
		local hintUntil=player:GetAttribute("MoteHintUntil") or 0
		return {
			rev=rev,
			motes={found=table.concat(bits),count=m.count,total=EX.TOTAL,steps=m.steps,claimable=claimable(p),regions=regions,hintCost=EX.hintCost(m.count),
				hint=if type(hintId)=="string" and hintId~="" and hintUntil>now then hintId else nil,hintUntil=hintUntil,stats=table.clone(p.perkStats and p.perkStats.motes or {}),agility=agility(p)},
			factions={pledge=f.pledge,pledgedAt=f.pledgedAt,switchIn=switchIn,
				resetIn=FA.resetIn(now),day=f.day,list=factions,unlocks=unlocks,title=f.title,titleText=titleText(p),total=f.total},
		}
	end
	Players.PlayerRemoving:Connect(function(player)
		if profileOf[player] then revOf[profileOf[player]]=nil; keyOf[profileOf[player]]=nil end
		lastPickup[player],lastFind[player],track[player],sentRev[player],profileOf[player]=nil,nil,nil,nil,nil
	end)
end
-- End Exploration & Factions block.
local function applyStats(player,p,spawned)
	local stats=Progression.computeStats(p,os.time())
	player:SetAttribute("SkyreachUnlocked",(p.questCompleted or 0)>=6)
	for _,region in ipairs(Data.Regions) do player:SetAttribute(region.id.."Unlocked",regionAllowed(p,region.id)) end
	local fleet=Workers.fleet(p)
	player:SetAttribute("WorkerSlots",Workers.slots(p)) -- Workers depth: unlocked slots (world stations)
	for slot=1,Data.Workers.MAX_SLOTS do
		local worker=fleet[slot]
		player:SetAttribute("Worker"..slot.."Tier",if worker then worker.tier else 0)
		player:SetAttribute("Worker"..slot.."Resource",if worker then worker.resource else "Ore")
	end
	local health=stats.health
	player:SetAttribute("CompanionBond",p.companionBond or 0)
	player:SetAttribute("ActivePet",Pets.attribute(p)) -- Pets depth: followers (pets.client.lua)
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
	if Prayer.stunned(player) then walk=0 end -- Thieving: caught and stunned
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
	for index,pet in ipairs(p.pets) do table.insert(pets,Pets.row(p,pet,index,now)) end -- Pets depth rows
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
		pets=pets,petDepth=Pets.view(p,now),buffs=buffs,collections=collections,bestiary=p.bestiary,slayer={lines=lines,quest=p.slayerQuest},enchants=p.enchants,regions=regions,
		gear=Gear.view(p), -- Gear depth: {reforges, stars, books} (Data.Gear helpers read it)
		combat=Progression.combatLoadout(p), -- Combat styles: {style,weapon,ammo,ammoCount,supplies,levels,autocast}
		mastery=Mastery.state and Mastery.state(p)} -- Skill Mastery: points, trees, capstones, milestones, mantles
end
-- Satchel (UI overhaul, docs/DEPTH-CONTRACT.md §29): p.satchel is the player's
-- item order for the satchel panel (a list of item ids, <= Satchel.MAX). It is
-- display order only: counts stay in p.items. Unknown or unowned ids are
-- dropped whenever it is read; owned ids missing from it follow in snapshot order.
local Satchel={MAX=400,sorts={rarity=true,name=true,kind=true,value=true}}
function Satchel.rank(def) local r=Data.Rarity[def.rarity] return r and r.rank or 1 end
function Satchel.clean(p)
	local list,seen={},{}
	for _,id in ipairs(type(p.satchel)=="table" and p.satchel or {}) do
		if type(id)=="string" and not seen[id] and Data.Items[id] and (p.items[id] or 0)>0 and #list<Satchel.MAX then seen[id]=true; table.insert(list,id) end
	end
	-- Owned ids not yet placed keep a stable spot at the end (rarity, then name).
	local rest={}
	for id,n in pairs(p.items) do if not seen[id] and Data.Items[id] and (n or 0)>0 then table.insert(rest,id) end end
	table.sort(rest,function(a,b)
		local ra,rb=Satchel.rank(Data.Items[a]),Satchel.rank(Data.Items[b])
		if ra~=rb then return ra>rb end
		return Data.Items[a].name<Data.Items[b].name
	end)
	for _,id in ipairs(rest) do if #list<Satchel.MAX then table.insert(list,id) end end
	p.satchel=list
	return list
end
-- satchelMove "<itemId>:<index>": move an owned item to a 1-based slot.
function Satchel.move(p,item)
	local id,raw
	if type(item)=="string" then id,raw=string.match(item,"^(%w+):(%d+)$") end
	local index=raw and #raw<=3 and tonumber(raw)
	if not id or not index or index<1 or not Data.Items[id] then return "Choose an item and a satchel slot." end
	if (p.items[id] or 0)<1 then return "You do not have that item." end
	local list=Satchel.clean(p)
	local from=table.find(list,id)
	if not from then return "You do not have that item." end
	table.remove(list,from)
	table.insert(list,math.clamp(index,1,#list+1),id)
	return ""
end
-- satchelSort "<rarity|name|kind|value>": reorders the whole satchel.
function Satchel.sort(p,item)
	if not Satchel.sorts[item] then return "Sort by rarity, name, kind or value." end
	local kindRank={weapon=1,armor=2,tool=3,accessory=4,consumable=5,pet=6,resource=7,material=8}
	local list=Satchel.clean(p)
	table.sort(list,function(a,b)
		local da,db=Data.Items[a],Data.Items[b]
		local ra,rb=Satchel.rank(da),Satchel.rank(db)
		if item=="name" then return da.name<db.name end
		if item=="value" and (da.value or 0)~=(db.value or 0) then return (da.value or 0)>(db.value or 0) end
		if item=="kind" and (kindRank[da.kind] or 9)~=(kindRank[db.kind] or 9) then return (kindRank[da.kind] or 9)<(kindRank[db.kind] or 9) end
		if ra~=rb then return ra>rb end
		return da.name<db.name
	end)
	return "Satchel sorted by "..item.."."
end
local function snapshot(player,message)
	local p=profiles[player]
	if not p then return {loading=true,message="Opening your journal…"} end
	-- Exploration & Factions: roll the faction day first, so its auto-claim note
	-- and the paid rewards land in this same snapshot (notes, applyStats below).
	if p.factions then Explore.refresh(p) end
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
	return {satchel=Satchel.clean(p), -- §29 satchel order
		xp=p.xp,items=p.items,consumables=provisions,collection=p.collection,coins=p.coins,bank=p.bank,bankRevision=p.bankRevision or 0,worker=p.worker,
		ironman=p.ironman,levels=levels,enchantRank=p.enchantRank or 0,workerResource=p.workerResource or "Ore",workerReady=Workers.ready(p),workers=Workers.state(p),workerInfo=Workers.info(p),message=message or "",kills=p.kills,
		companionBond=p.companionBond or 0,market=marketViews[player],economy=Econ.view and Econ.view(player,p),recipes=recipeState(p),regions=regionState(p),stats=legacyStats,quest=questState(p),slayer=slayerState(p),started=p.started,decorations=p.decorations,preview=preview[player]==true,
		depth=depthState(p,stats),journal=Journal.state(p),agilityHunter=Skills.state(player,p), -- Agility & Hunter page state
		events={claims=p.eventClaims or {},vendorUntil=player:GetAttribute("EventVendorUntil") or 0,serverTime=os.time()}, -- Events hook: Calendar page state
		dungeonClasses=Classes.state and Classes.state(p), -- Dungeon classes: Hunt > Dungeon page state
		dungeonEndgame=Delve.state and Delve.state(p), -- Dungeon endgame: bonus chest, run log, weekly bests, gear score
		garden=Garden.state and Garden.state(player,p), -- Verdant Garden page state
		prayer=Prayer.state(player,p,stats),thieving=Prayer.thievingState(player,p,stats), -- Prayer & Thieving page state
		trails=Trails.state(player,p), -- Treasure Trails: Satchel > Trails page state
		slayerTasks=SlayerTasks.state(player,p), -- Slayer tasks: Hunt > Slayer page state
		minigames=Minigames.state(player,p), -- Minigames: Hunt > Minigames page state
		crafting=Crafting.state and Crafting.state(player,p), -- Crafting: Workshop › Crafting page state
		lairs=Lairs.state and Lairs.state(player,p), -- Lairs: Hunt › Bosses (kill counts, personal bests, uniques)
		exploration=Explore.state(player,p), -- Exploration & Factions: Journal > Motes / Factions (full when changed, else {rev, resetIn, switchIn, compact})
		logs=Logs.state(player,p)} -- Commissions & Logs: Journal > Commissions / Collection Log / Museum (full when changed, else {rev, resetIn, compact})
end
-- Prayer & Thieving: drain-loop notices (prayer points ran out).
Prayer.push=function(player,message) if player.Parent then update:FireClient(player,snapshot(player,message)) end end
local function persist(player,release)
	if preview[player] or not profiles[player] then return true end
	while saving[player] do task.wait(0.1) end
	local p=profiles[player]
	if not p then return true end
	saving[player]=true
	local owner=sessionOwner[player]
	Workers.fleet(p)
	-- Deep copy: every nested Depth table (pets, buffs, enchants...) is snapshotted.
	local payload=deepCopy(p)
	payload.workersClean=nil -- Workers depth: session-only sanitise marker
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
	Pets.migrate(profile) -- Pets depth: rarity, held item, candy, Roost job
	-- Combat styles: autocast must name an autocast spell.
	if profile.autocast~=nil and not (type(profile.autocast)=="string" and Data.Spells[profile.autocast] and Data.Spells[profile.autocast].autocast) then profile.autocast=nil end
	local quest=profile.slayerQuest
	if quest~=nil and (type(quest)~="table" or not Data.Slayers[quest.line] or not Data.Slayers[quest.line].tiers[quest.tier]) then profile.slayerQuest=nil end
	profile.version=math.max(tonumber(profile.version) or 1,2)
	Workers.migrate(profile) -- Workers depth: sanitise fleet, seed unique crafts
	Journal.migrate(profile)
	Skills.migrate(profile) -- Agility & Hunter records + milestone perks
	Prayer.migrate(profile) -- Prayer & Thieving: points, favourites, offerings, thefts
	SlayerTasks.migrate(profile) -- Slayer tasks: task, streak, points, blocks, unlocks, superior log
	Gear.migrate(profile) -- Gear depth: reforges, stars, books
	Progression.masteryMigrate(profile) -- Skill Mastery: drop unknown/invalid nodes, reset overspent trees
	if Garden.migrate then Garden.migrate(profile) end -- Verdant Garden: sanitise and bound p.garden
	if Classes.migrate then Classes.migrate(profile) end -- Dungeon classes: sanitise p.dungeonClasses
	if Delve.migrate then Delve.migrate(profile) end -- Dungeon endgame: sanitise p.dungeonEndgame and p.masterStars
	Trails.migrate(profile) -- Treasure Trails: sanitise p.trails (re-draws trails whose steps left the pool)
	Minigames.migrate(profile) -- Minigames: Commendations, cache rolls, titles, minigame log
	Logs.migrate(profile) -- Commissions & Logs: board, Glimmerdust, Forgeheart, log (retroactive on first load), museum
	if Crafting.migrate then Crafting.migrate(profile) end -- Crafting: p.crafting {made, shattered}
	Explore.migrate(profile) -- Exploration & Factions: p.motes, p.factions, p.perkStats.motes
	if Lairs.migrate then Lairs.migrate(profile) end -- Lairs: kill counts, personal bests, uniques
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
	SlayerTasks.onKill(player,p,id,monster,true) -- Slayer tasks: sea creature task credit (owner only)
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
	Prayer.forget(player) -- Prayer rites/altar window, Thieving stuns and cooldowns
	SlayerTasks.forget(player) -- Slayer tasks: superior tickets
	if Crafting.forget then Crafting.forget(player) end -- Crafting: batch job and station visit (session-only)
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
	if Classes.publish then Classes.publish(player,profile) end -- Dungeon classes: DungeonClass / DungeonMasterOn attributes
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
	function Garden.ctx(p) return {level=G.level(rec(p).xp),set=setActive(p),petGrowth=Progression.petEffects(p).garden/100} end -- Pets depth: growth abilities
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

------------------------------------------------------------------------------
-- Pets depth (Data.PetDepth): held items, Pet Candy, Tier Boost, the Roost
-- (timed rarity upgrades), its shop and the ability hooks other systems call.
-- Verbs (item <= 64 chars). A pet is named "index:speciesId" (index = position
-- in p.pets, 1-based); the server checks p.pets[index].id == speciesId so a
-- roster that shifted (Roost, adoption) never hits the wrong pet. A bare index
-- is refused.
--   petItem "index:speciesId:itemId" equip a held item (old one returns to the
--     satchel); "index:speciesId:" or "index:speciesId:none" takes it off
--   petCandy "index:speciesId:PetCandy|StarlitCandy" (+XP, PD.CANDY_MAX uses per pet)
--   petTierBoost "index:speciesId" spends an Ascendant Prism: +1 rarity tier at once
--   petUpgrade "index:speciesId" hands the pet to the Roost: coins + materials, os.time timer
--   petClaim collects it once the timer is done (exactly once; refused while the
--     roster is full); petCancel takes it back early (no refund), and once the
--     timer is done it claims instead (a finished upgrade is never thrown away)
--   petShop "itemId" buys from the Roost keeper (PD.Shop)
-- Profile: pet.rarity/item/candy, p.petUpgrade={pet,from,to,ends}, p.petTamingCarry.
-- Player attribute ActivePet = "speciesId:rarity:level" or "" (pets.client.lua).
------------------------------------------------------------------------------
do
	local PD=Data.PetDepth
	Pets.verbs={petItem=true,petCandy=true,petTierBoost=true,petUpgrade=true,petClaim=true,petCancel=true,petShop=true}
	local function petAt(p,raw,species)
		local index=tonumber(raw)
		if not index or index%1~=0 or tostring(index)~=raw then return nil end
		local pet=p.pets[index]
		if type(pet)~="table" or not Data.PetById[pet.id] or pet.id~=species then return nil end
		return pet,Data.PetById[pet.id],index
	end
	-- Garden growth reads the summoned pet: advance the garden to now before the
	-- summoned pet (or its held item, level, rarity) changes.
	function Pets.gardenSync(p)
		if type(p.garden)=="table" and Garden.refresh then Garden.refresh(p,os.time()) end
	end
	local function petName(pet,def) return Progression.petRarity(pet).." "..def.name end
	-- Remove p.pets[index], keeping the active pointer on the same pet.
	local function takePet(p,index)
		local pet=table.remove(p.pets,index)
		if p.activePet==index then p.activePet=nil
		elseif p.activePet and p.activePet>index then p.activePet-=1 end
		return pet
	end
	local function costText(cost)
		local parts={}
		if cost.coins>0 then table.insert(parts,cost.coins.." coins") end
		for id,n in pairs(cost.items) do table.insert(parts,n.." "..(Data.Items[id] and Data.Items[id].name or id)) end
		table.sort(parts)
		return table.concat(parts,", ")
	end
	local function span(seconds)
		seconds=math.max(0,math.floor(seconds))
		if seconds>=3600 then return math.floor(seconds/3600).."h "..math.floor(seconds%3600/60).."m" end
		if seconds>=60 then return math.floor(seconds/60).."m "..(seconds%60).."s" end
		return seconds.."s"
	end
	Pets.span=span
	function Pets.action(player,p,verb,item)
		if verb=="petShop" then
			local entry=validId(item) and PD.ShopByItem[item]
			if not entry then return "The Roost keeper does not sell that." end
			if p.coins<entry.coins then return "You need "..entry.coins.." coins for "..Data.Items[item].name.."." end
			p.coins-=entry.coins
			collect(p,item,1)
			return "Bought "..Data.Items[item].name.." for "..entry.coins.." coins."
		elseif verb=="petClaim" or (verb=="petCancel" and p.petUpgrade and os.time()>=p.petUpgrade.ends) then
			local job=p.petUpgrade
			if not job then return "No pet is waiting at the Roost." end
			if os.time()<job.ends then return "The Roost needs "..span(job.ends-os.time()).." more." end
			if #p.pets>=MAX_PETS then return "Your pet menu is full ("..MAX_PETS.."). Release a pet, then claim." end
			p.petUpgrade=nil
			local def=Data.PetById[job.pet.id]
			Progression.petSetRarity(job.pet,job.to)
			table.insert(p.pets,job.pet)
			grantXp(p,"Taming",200*PD.rank(job.to))
			return "Your "..def.name.." returns "..job.to.."! (Lv "..job.pet.level..")"
		elseif verb=="petCancel" then
			local job=p.petUpgrade
			if not job then return "No pet is waiting at the Roost." end
			if #p.pets>=MAX_PETS then return "Your pet menu is full." end
			p.petUpgrade=nil
			table.insert(p.pets,job.pet)
			return "You take your "..Data.PetById[job.pet.id].name.." home. The fee is not refunded."
		end
		local raw,species,rest=nil,nil,nil
		if validId(item) then
			raw,species,rest=string.match(item,"^(%d+):(%w+):(.*)$")
			if not raw then raw,species=string.match(item,"^(%d+):(%w+)$"); rest=if raw then "" else nil end
		end
		local pet,def,index=nil,nil,nil
		if raw then pet,def,index=petAt(p,raw,species) end
		if not pet then
			local moved=raw and Data.PetById[species] and type(p.pets[tonumber(raw)])=="table"
			return if moved then "That pet moved in your roster. Choose it again." else "Choose one of your pets."
		end
		local takesArg=verb=="petItem" or verb=="petCandy"
		if takesArg~=(string.find(item,"^%d+:%w+:")~=nil) then return "Choose one of your pets." end
		if p.activePet==index then Pets.gardenSync(p) end
		if verb=="petItem" then
			if rest=="" or rest=="none" then
				if not pet.item then return def.name.." holds nothing." end
				local old=pet.item
				pet.item=nil
				p.items[old]=(p.items[old] or 0)+1
				return def.name.." hands back the "..Data.Items[old].name.."."
			end
			local held=PD.held(rest)
			if not held then return "Choose a pet held item." end
			if pet.item==rest then return def.name.." already holds "..held.name.."." end
			if (p.items[rest] or 0)<1 then return "You do not own "..held.name.."." end
			p.items[rest]-=1
			if pet.item then p.items[pet.item]=(p.items[pet.item] or 0)+1 end
			pet.item=rest
			return def.name.." now holds "..held.name..": "..held.text.."."
		elseif verb=="petCandy" then
			local candy=PD.Candies[rest]
			if not candy then return "Choose a Pet Candy to feed." end
			if (p.items[rest] or 0)<1 then return "You have no "..Data.Items[rest].name.."." end
			if (pet.candy or 0)>=PD.CANDY_MAX then return def.name.." has eaten all "..PD.CANDY_MAX.." candies it ever will." end
			if pet.level>=Data.PET_MAX_LEVEL then return def.name.." is already level "..Data.PET_MAX_LEVEL.."." end
			p.items[rest]-=1
			pet.candy=(pet.candy or 0)+1
			local gained=Progression.addXpToPet(pet,candy.xp)
			return def.name.." enjoys the "..Data.Items[rest].name.."! +"..candy.xp.." pet XP"..(if gained>0 then " · Lv "..pet.level else "").." ("..pet.candy.."/"..PD.CANDY_MAX.." candies)"
		elseif verb=="petTierBoost" then
			local to=PD.nextRarity(Progression.petRarity(pet))
			if not to then return def.name.." is already "..PD.MAX_RARITY.."." end
			if (p.items.AscendantPrism or 0)<1 then return "You need an Ascendant Prism." end
			p.items.AscendantPrism-=1
			Progression.petSetRarity(pet,to)
			return "The prism flares: your "..def.name.." is now "..to.."! (Lv "..pet.level..")"
		elseif verb=="petUpgrade" then
			if p.petUpgrade then return "The Roost is already caring for your "..Data.PetById[p.petUpgrade.pet.id].name.."." end
			local from=Progression.petRarity(pet)
			local cost=PD.upgradeCost(def,from)
			if not cost then return def.name.." is already "..PD.MAX_RARITY.."." end
			if p.coins<cost.coins then return "The Roost asks "..costText(cost).."." end
			for id,n in pairs(cost.items) do
				if (p.items[id] or 0)<n then return "The Roost asks "..costText(cost)..". Missing "..(n-(p.items[id] or 0)).." "..Data.Items[id].name.."." end
			end
			spend(p,cost.items)
			p.coins-=cost.coins
			takePet(p,index)
			p.petUpgrade={pet=pet,from=from,to=cost.to,ends=os.time()+cost.seconds}
			return PD.KEEPER.." takes your "..petName(pet,def)..". It returns "..cost.to.." in "..span(cost.seconds).."."
		end
		return "Unknown pet action."
	end
	-- Ability hooks ---------------------------------------------------------------
	-- % bonus vs a monster's slayer family (coins, slayer progress, Magic Find).
	function Pets.familyBonus(p,monster)
		local line=type(monster)=="table" and monster.slayer
		return line and (Progression.petEffects(p).family[line] or 0) or 0
	end
	-- Doubled harvests roll inside Progression.gatherYieldMult (max with mastery).
	-- Extra craft: only stackable outputs (materials, consumables and pet candy,
	-- which is used up when fed); armour, weapons, accessories, held pet items
	-- and other one-of-a-kind gear never duplicate, even from a repeatable recipe.
	function Pets.craftStackable(recipe)
		local def=type(recipe)=="table" and Data.Items[recipe.output]
		if not def then return false end
		return def.kind=="material" or def.kind=="consumable" or (def.kind=="petitem" and def.petItem=="candy")
	end
	function Pets.craftExtra(p,recipe)
		if not Pets.craftStackable(recipe) then return false end
		local chance=Progression.petEffects(p).craft[recipe.skill] or 0
		return chance>0 and roll()*100<chance
	end
	-- Taming XP share of pet XP earned from skills (fractions carried).
	function Pets.tamingShare(p,petGain)
		local carry=(tonumber(p.petTamingCarry) or 0)+petGain*PD.TAMING_SHARE
		local whole=math.floor(carry)
		p.petTamingCarry=carry-whole
		if whole>0 then grantXp(p,"Taming",whole) end
	end
	-- True when the player already has the species anywhere: an unadopted pet
	-- item, the roster, or the Roost.
	function Pets.ownsSpecies(p,speciesId)
		local def=Data.PetById[speciesId]
		if def and (p.items[def.id.."Pet"] or 0)>0 then return true end
		for _,pet in ipairs(p.pets or {}) do if type(pet)=="table" and pet.id==speciesId then return true end end
		local job=p.petUpgrade
		return type(job)=="table" and type(job.pet)=="table" and job.pet.id==speciesId
	end
	-- Skilling pets: one roll per SKILL_PET_STEP XP banked in a skill that has a pet
	-- (~1 per PD.SKILL_PET_XP XP). Rule: a skilling pet drops only while the player
	-- has none of that species (item, roster or Roost), so each species is one
	-- drop per player unless it was sold or traded away; the banked XP is still
	-- spent while a copy is owned, so owning one never stores up rolls.
	function Pets.skillRoll(p,skill,amount)
		local itemId=PD.SkillPets[skill]
		if not itemId then return end
		p.petSkillXp=type(p.petSkillXp)=="table" and p.petSkillXp or {}
		local banked=(tonumber(p.petSkillXp[skill]) or 0)+amount
		local step=PD.SKILL_PET_STEP
		if banked<step then p.petSkillXp[skill]=banked return end
		local rolls=math.min(10,math.floor(banked/step))
		p.petSkillXp[skill]=banked-rolls*step
		if Pets.ownsSpecies(p,Data.Items[itemId].pet) then return end
		local luck=Progression.computeStats(p,os.time()).petLuck
		for _=1,rolls do
			if roll()<PD.skillPetChance(step,luck) then
				p.items[itemId]=(p.items[itemId] or 0)+1
				note(p,"A "..Data.Items[itemId].name.." follows you home from your "..skill.." work!")
				return
			end
		end
	end
	-- Snapshot rows ---------------------------------------------------------------
	function Pets.row(p,pet,index,now)
		local def=Data.PetById[pet.id]
		local lvl=Progression.petLevel(pet)
		local rarity=Progression.petRarity(pet)
		local cost=PD.upgradeCost(def,rarity)
		return {id=pet.id,level=lvl,xp=pet.xp or 0,next=if lvl<Data.PET_MAX_LEVEL then Data.petXpToNext(lvl,rarity) else nil,active=index~=nil and p.activePet==index,
			rarity=rarity,item=pet.item,candy=pet.candy or 0,candyMax=PD.CANDY_MAX,abilities=PD.abilityView(def,lvl,rarity),
			stats=Progression.petStats(p,pet,def),totalXp=PD.totalXp(lvl,pet.xp,rarity),upgrade=cost}
	end
	function Pets.view(p,now)
		local job=p.petUpgrade
		local tl=Progression.tamingLevel(p)
		return {upgrade=job and {id=job.pet.id,level=job.pet.level,from=job.from,to=job.to,ends=job.ends,remaining=math.max(0,job.ends-now),ready=now>=job.ends} or nil,
			taming={level=tl,xpBonus=math.floor(PD.tamingXpBonus(tl)*100+0.5),statBonus=PD.tamingStatBonus(tl)*100}}
	end
	function Pets.attribute(p)
		local pet,def=Progression.activePet(p)
		return if pet then PD.attribute(def.id,Progression.petRarity(pet),pet.level) else ""
	end
	-- Migration: explicit rarity for older pets, integer level/xp/candy, valid held
	-- items (unknown ones dropped), a sane Roost job (bad timer: pet returned,
	-- even past MAX_PETS).
	local function cleanPet(pet)
		local def=Data.PetById[pet.id]
		if not PD.validRarity(pet.rarity) then pet.rarity=def.rarity end
		pet.level=PD.clampLevel(pet.level)
		local xp=tonumber(pet.xp) or 0
		if xp~=xp or xp<0 then xp=0 end
		local need=Data.petXpToNext(pet.level,pet.rarity)
		pet.xp=if pet.level>=Data.PET_MAX_LEVEL then 0 else math.min(xp,need-1)
		if pet.item~=nil and not PD.held(pet.item) then pet.item=nil end
		local candy=tonumber(pet.candy)
		pet.candy=if candy and candy==candy then math.clamp(math.floor(candy),0,PD.CANDY_MAX) else nil
		if pet.candy==0 then pet.candy=nil end
	end
	function Pets.migrate(profile)
		for _,pet in ipairs(profile.pets) do cleanPet(pet) end
		local job=profile.petUpgrade
		if job~=nil then
			local valid=type(job)=="table" and type(job.pet)=="table" and type(job.pet.id)=="string" and Data.PetById[job.pet.id]~=nil
			if not valid then profile.petUpgrade=nil
			else
				cleanPet(job.pet)
				local ends=tonumber(job.ends)
				if PD.validRarity(job.to) and PD.rank(job.to)==PD.rank(job.pet.rarity)+1 and ends and ends==ends then
					job.from,job.ends=job.pet.rarity,math.floor(ends)
				else
					-- Never delete a pet: it returns even past MAX_PETS (adoption and
					-- claims stay refused until the roster is back under the cap).
					profile.petUpgrade=nil
					table.insert(profile.pets,job.pet)
				end
			end
		end
		local carry=tonumber(profile.petTamingCarry)
		profile.petTamingCarry=if carry and carry==carry and carry>0 and carry<1 then carry else nil
		if profile.petSkillXp~=nil then
			local clean={}
			if type(profile.petSkillXp)=="table" then
				for skill,n in pairs(profile.petSkillXp) do
					if PD.SkillPets[skill] and type(n)=="number" and n==n and n>0 then clean[skill]=math.min(n,PD.SKILL_PET_STEP) end
				end
			end
			profile.petSkillXp=clean
		end
	end
end
-- End Pets depth block.

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
------------------------------------------------------------------------------
-- Lairs (Bossing team). Rules and data: Data.Lairs (shared/GameData.lua);
-- instances: lairs.server.lua (ServerStorage.IsleLairs); creatures:
-- combat.server.lua Lairs section. docs/DEPTH-CONTRACT.md §25.
--   lairEnter "<boss>" (altar prompt only, IsleRegion gate): Combat level,
--     region, coins (the entry fee), not busy in a dungeon run / minigame /
--     another lair; IsleLairs "enter" opens an instance (or joins a crewmate's
--     during its warmup) synchronously, then the fee is spent. Lairs.entered
--     [userId] = {fight, boss, fee, at} is the only key a reward can match.
--   lairLeave (arena exit prompt): forfeits the fight (IsleLairs "leave").
--   bridge "lair" {action = "kill", boss, fight, seconds, party, share}: once
--     per fight per journal: coin roll + LR.Loot via Progression.rollDrops
--     (Magic Find / Pet Luck) through collect() (Collection Log: tab Lairs),
--     kill count, personal best and uniques (LR.record). Not live -> "sync"
--     (lairs.server.lua resends). {action = "end", result} closes the entry
--     (a "died" result counts a death); {action = "refund"} returns the fee
--     when the arena or boss could not be built (never after a reward).
-- Profile p.lairs (LR.migrate); snapshot key lairs = {kc, pb, pbParty, got,
-- deaths, log, active}.
------------------------------------------------------------------------------
do
	local LR=Data.Lairs
	Lairs.entered={} -- [userId]={fight,boss,fee,at,paid,refunded}
	Lairs.ENTRY_TTL=7200
	local TEXT={level="Your Combat level is too low for this lair.",region="You cannot reach this lair's region yet.",
		coins="You cannot afford the lair's entry fee.",busy="Finish your current dungeon run, minigame or lair first.",
		boss="This altar is silent.",capacity="Every lair on this server is in use. Try again in a minute.",
		full="That lair is full.",active="You are already inside a lair.",invalid="The altar flickers. Try again shortly."}
	function Lairs.migrate(p) p.lairs=LR.migrate(p.lairs) end
	function Lairs.of(p)
		local s=p.lairs
		if type(s)~="table" or type(s.kc)~="table" or type(s.pb)~="table" or type(s.got)~="table" or type(s.log)~="table" then Lairs.migrate(p) end
		return p.lairs
	end
	local function invoke(op,player,arg)
		local fn=ServerStorage:FindFirstChild("IsleLairs")
		if not fn then return nil end
		local ok,reply=pcall(fn.Invoke,fn,op,player,arg)
		if not ok or type(reply)~="table" then return nil end
		return reply
	end
	local function busy(player)
		local game=player:GetAttribute("MinigameGame")
		local lair=player:GetAttribute("LairBoss")
		return player:GetAttribute("DungeonInRun")==true or (type(game)=="string" and game~="") or (type(lair)=="string" and lair~="")
	end
	function Lairs.action(player,p,verb,item,prompt)
		if verb=="lairLeave" then
			local reply=invoke("leave",player)
			if not reply then return "The way out is sealed for a moment." end
			return if reply.ok then "You leave the lair. The boss keeps its hoard." else "You are not inside a lair."
		end
		if verb~="lairEnter" then return "Unknown lair action." end
		if not prompt then return "Summon a lair boss at its altar." end
		local def=LR.boss(item)
		if not def then return TEXT.boss end
		local ok,reason=LR.canEnter(item,{combat=level(p.xp.Combat),region=regionAllowed(p,def.region),coins=p.coins,busy=busy(player)})
		if not ok then
			if reason=="level" then return def.short.."'s lair needs Combat "..def.combat.."." end
			if reason=="coins" then return def.short.."'s lair costs "..def.fee.." coins to enter." end
			return TEXT[reason] or TEXT.invalid
		end
		local reply=invoke("enter",player,item)
		if not reply then return TEXT.invalid end
		if not reply.ok then return TEXT[reply.reason] or TEXT.invalid end
		p.coins-=def.fee
		local now=os.time()
		for uid,e in pairs(Lairs.entered) do if now-e.at>Lairs.ENTRY_TTL then Lairs.entered[uid]=nil end end
		Lairs.entered[player.UserId]={fight=reply.fight,boss=item,fee=def.fee,at=now}
		p.started=true
		if reply.mode=="join" then return "You join the hunt in "..def.lairName.." • -"..def.fee.." coins." end
		return "The altar flares: "..def.lairName.." opens • -"..def.fee.." coins. "..def.short.." rises in "..LR.WARMUP.."s."
	end
	-- Bridge op "lair" (lairs.server.lua only).
	function Lairs.bridge(player,p,payload)
		local def=LR.boss(payload.boss)
		local e=Lairs.entered[player.UserId]
		if not def or type(payload.fight)~="string" then return {ok=false,reason="invalid"} end
		if not e or e.fight~=payload.fight or e.boss~=payload.boss then return {ok=false,reason="entry"} end
		local action=payload.action
		if action=="refund" then
			if e.paid or e.refunded then return {ok=false,reason="paid"} end
			e.refunded=true
			p.coins+=e.fee
			Lairs.entered[player.UserId]=nil
			return {ok=true,coins=e.fee,message="The altar returns your "..e.fee.."-coin offering."}
		elseif action=="end" then
			Lairs.entered[player.UserId]=nil
			if payload.result=="died" then
				local s=Lairs.of(p)
				s.deaths[payload.boss]=math.min(LR.MAX_KC,(s.deaths[payload.boss] or 0)+1)
			end
			return {ok=true}
		elseif action~="kill" then
			return {ok=false,reason="invalid"}
		end
		if e.paid then return {ok=false,reason="paid"} end
		e.paid=true
		local seconds=math.clamp(math.floor(tonumber(payload.seconds) or def.duration),1,def.duration)
		local party=math.clamp(math.floor(tonumber(payload.party) or 1),1,LR.MAX_PARTY)
		local stats=Progression.computeStats(p,os.time())
		local drops=Progression.rollDrops(LR.Loot[payload.boss],stats.magicFind,roll,stats.petLuck)
		local coins=LR.coinRoll(payload.boss,roll())
		p.coins+=coins
		for id,n in pairs(drops) do collect(p,id,n) end
		local rec=LR.record(Lairs.of(p),payload.boss,seconds,party,drops,os.time())
		Logs.event(p,"kill",payload.boss) -- Commissions & Logs (and faction boards) see the kill
		p.started=true
		local extra=""
		for _,id in ipairs(rec.uniques) do
			local d=Data.Items[id]
			extra..="   ·   "..(if d.kind=="pet" then "PET DROP! " else "RARE DROP! ")..d.name
		end
		return {ok=true,drops=drops,coins=coins,kc=rec.kc,pb=rec.pb,uniques=rec.uniques,
			message=def.short.." slain in "..LR.formatTime(seconds)..(if rec.pb then " (personal best!)" else "").." • KC "..rec.kc.." • +"..coins.." coins"..dropText(drops)..extra}
	end
	function Lairs.state(player,p)
		local s=Lairs.of(p)
		local lair=player:GetAttribute("LairBoss")
		return {kc=s.kc,pb=s.pb,pbParty=s.pbParty,got=s.got,deaths=s.deaths,log=s.log,active=if type(lair)=="string" then lair else ""}
	end
end
------------------------------------------------------------------------------
-- Crafting (Crafting team). Rules and data: Data.Crafting (shared/GameData.lua);
-- stations: world.server.lua (prompt IsleAction "craftStation", IsleItem
-- Jeweller | Tannery | Glassworks on the Guild Terrace).
--   craftStation (prompt only) records a station visit (CR.VISIT_SECONDS) at
--     the prompt's part and opens Workshop › Crafting (IsleStation).
--   craftBatch "recipe:count" (1..CR.MAX_BATCH) starts a batch at the visited
--     station; a newer batch replaces the old one. The server performs ONE
--     action every CR.Branches[b].seconds (the first after a full cadence, no
--     catch-up bursts): it re-checks the station range, level, tool, collection
--     gate and materials (CR.check), spends, rolls a shatter for gem cutting
--     (Gem Grit, CR.SHATTER_XP of the XP), grants the output through collect()
--     (collections, Collection Log), counts crafts (quests) and "craft"
--     commissions, pays XP (recipe.skill: Crafting, or Enchanting for amulets)
--     and pushes a snapshot. Quantities are never taken from the client.
--   craftStop ends the batch.
-- Mining harvests roll a rough gem (CR.gemChance / CR.roughFor) after every
-- other harvest hook. Player attributes: CraftingGesture "<gesture>:<seq>"
-- (animate.client.lua plays it each action), CraftingJob "<recipe>:<done>:<total>"
-- or "". Profile p.crafting = {made={[recipe]=n}, shattered=n}; snapshot key
-- `crafting`. Jobs and visits are session-only (strong tables, cleared by forget).
------------------------------------------------------------------------------
do
	local CR=Data.Crafting
	local function levelsOf(p) return function(skill) return level(p.xp[skill]) end end
	local function tiersOf(p) return function(id) return Progression.collectionTier(p,id) end end
	local function nameOf(id) return Data.Items[id] and Data.Items[id].name or id end
	function Crafting.migrate(p)
		local c=type(p.crafting)=="table" and p.crafting or {}
		local made={}
		if type(c.made)=="table" then
			for id,n in pairs(c.made) do
				n=tonumber(n)
				if type(id)=="string" and CR.Recipes[id] and n and n==n and n>0 then made[id]=math.min(math.floor(n),CR.MAX_MADE) end
			end
		end
		local shattered=tonumber(c.shattered)
		if not shattered or shattered~=shattered then shattered=0 end
		p.crafting={made=made,shattered=math.clamp(math.floor(shattered),0,CR.MAX_MADE)}
	end
	local function near(player,visit)
		local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return root~=nil and visit~=nil and (root.Position-visit.pos).Magnitude<=CR.STATION_RANGE
	end
	local function alive(player)
		local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return humanoid~=nil and humanoid.Health>0
	end
	-- A cost item that is worn (gear slot) or bagged keeps those copies back:
	-- a batch never consumes them (Slayer review rule). CR.check counts only
	-- CR.spare copies, so the UI (same rule) and the server agree.
	local function publish(player,job)
		player:SetAttribute("CraftingJob",if job then job.recipe..":"..job.done..":"..job.total else "")
	end
	local function push(player,message)
		if player.Parent then update:FireClient(player,snapshot(player,message)) end
	end
	function Crafting.visit(player,item,prompt)
		local station=type(item)=="string" and CR.Stations[item]
		local base=prompt and prompt:FindFirstAncestorWhichIsA("BasePart")
		if not station or not base then return "This bench is not ready." end
		Crafting.visits[player]={station=item,pos=base.Position,untilAt=os.clock()+CR.VISIT_SECONDS}
		player:SetAttribute("IsleStation",item)
		player:SetAttribute("IsleStationVisit",(player:GetAttribute("IsleStationVisit") or 0)+1)
		return station.name.." • choose a pattern in Workshop › Crafting."
	end
	function Crafting.start(player,p,item)
		local id,n=CR.parseBatch(item)
		if not id then return "Choose a Crafting pattern (and how many, up to "..CR.MAX_BATCH..")." end
		local rec=CR.Recipes[id]
		local station=CR.Stations[rec.station]
		local visit=Crafting.visits[player]
		if not visit or visit.station~=rec.station or os.clock()>visit.untilAt then
			return "Use the "..station.name.." on the Guild Terrace to craft "..nameOf(rec.output).."."
		end
		if not near(player,visit) then return "Stand at the "..station.name.." to craft." end
		local ok,why=CR.check(p,id,levelsOf(p),tiersOf(p))
		if not ok then return why end
		local replaced=Crafting.jobs[player]~=nil
		Crafting.jobs[player]={recipe=id,total=n,done=0,made=0,shattered=0,xp=0,visit=visit,nextAt=os.clock()+rec.seconds}
		publish(player,Crafting.jobs[player])
		p.started=true
		return (if replaced then "Switched to " else "Crafting ")..n.."× "..nameOf(rec.output).." • "..rec.seconds.."s each."
	end
	function Crafting.stop(player)
		local job=Crafting.jobs[player]
		if not job then return "You are not crafting anything." end
		Crafting.jobs[player]=nil
		publish(player,nil)
		return "Crafting stopped after "..job.done.."/"..job.total.."."
	end
	local function summary(job)
		local rec=CR.Recipes[job.recipe]
		local text=nameOf(rec.output).." "..job.done.."/"..job.total.." • +"..job.made.." made"
		if job.shattered>0 then text..=", "..job.shattered.." shattered" end
		return text.." • +"..job.xp.." "..rec.skill.." XP"
	end
	-- Run a grant hook; a throw is logged, never propagated (the action's
	-- materials are already spent, so the rest of the grant must still happen).
	local function safely(what,f,...)
		local ok,err=pcall(f,...)
		if not ok then (warn or print)("Crafting "..what.." failed: "..tostring(err)) end
		return ok
	end
	-- Grant `amount` of `item`; if collect() throws before the item lands, the
	-- spent costs come back (materials are never lost). Returns true if granted.
	local function grantOutput(p,rec,item,amount)
		local before=p.items[item] or 0
		if safely("grant",collect,p,item,amount) then return true end
		if (p.items[item] or 0)>=before+amount then return true end -- landed; a later hook threw
		for id,n in pairs(rec.costs) do p.items[id]=(p.items[id] or 0)+n end
		return false
	end
	-- One action of a live job. Returns nothing; pushes its own snapshot.
	function Crafting.step(player,job)
		local p=live(player)
		if not p or not player.Parent then
			-- Journal lease lost (or the player left): drop the job and clear its attribute.
			Crafting.jobs[player]=nil
			safely("publish",publish,player,nil)
			return
		end
		local rec=CR.Recipes[job.recipe]
		local station=CR.Stations[rec.station]
		local function finish(text)
			Crafting.jobs[player]=nil
			publish(player,nil)
			push(player,text)
		end
		if not alive(player) then return finish("Crafting stopped.") end
		if not near(player,job.visit) then return finish("You stepped away from the "..station.name..". "..summary(job)) end
		local ok,why=CR.check(p,job.recipe,levelsOf(p),tiersOf(p))
		if not ok then return finish(summary(job).." • "..why) end
		local shatter=CR.cutFailChance(rec,level(p.xp.Crafting))
		local shattered=shatter>0 and roll()<shatter
		local amount=rec.amount
		-- Pets depth: an extra-craft ability may add one more batch of a stackable output (no XP).
		if not shattered and Pets.craftExtra and Pets.craftExtra(p,rec) then amount+=rec.amount end
		if not spend(p,rec.costs) then return finish(summary(job).." • Materials missing.") end
		-- From here the costs are spent: every grant is protected. If the output
		-- cannot be granted the costs are refunded; a failing hook (journal,
		-- commissions, XP) is logged and the rest still happens.
		local xp=rec.xp
		local text
		if shattered then
			if not grantOutput(p,rec,"GemGrit",1) then return finish(summary(job).." • Something went wrong; your materials were returned.") end
			xp=math.max(1,math.floor(rec.xp*CR.SHATTER_XP))
			job.shattered+=1
			p.crafting.shattered=math.min(CR.MAX_MADE,p.crafting.shattered+1)
			text="The "..nameOf(next(rec.costs)).." shattered into Gem Grit"
		else
			if not grantOutput(p,rec,rec.output,amount) then return finish(summary(job).." • Something went wrong; your materials were returned.") end
			safely("journal",Journal.count,p,"crafts",rec.output,amount)
			safely("commission",Logs.event,p,"craft",rec.output) -- Commissions & Logs: "craft" commissions
			job.made+=amount
			p.crafting.made[rec.id]=math.min(CR.MAX_MADE,(p.crafting.made[rec.id] or 0)+1)
			text="+"..amount.." "..nameOf(rec.output)..(if amount>rec.amount then " (pet ×2)" else "")
		end
		safely("xp",grantXp,p,rec.skill,xp)
		job.xp+=xp
		job.done+=1
		p.started=true
		Crafting.seq[player]=(Crafting.seq[player] or 0)+1
		player:SetAttribute("CraftingGesture",CR.Branches[rec.branch].gesture..":"..Crafting.seq[player])
		if job.done>=job.total then return finish(text.."   ·   Batch done • "..summary(job)) end
		job.nextAt=os.clock()+rec.seconds
		publish(player,job)
		push(player,text.."   ·   +"..xp.." "..rec.skill.." XP   ·   "..job.done.."/"..job.total)
	end
	-- Every live job whose cadence has elapsed takes exactly one action.
	function Crafting.tick(now)
		local due={}
		for player,job in pairs(Crafting.jobs) do if now>=job.nextAt then table.insert(due,player) end end
		for _,player in ipairs(due) do
			local job=Crafting.jobs[player]
			if job then
				local ok,err=pcall(Crafting.step,player,job)
				if not ok then Crafting.jobs[player]=nil; (warn or print)("Crafting step failed: "..tostring(err)) end
			end
		end
	end
	-- Mining harvests: a rare rough gem, gated by the ore tier.
	function Crafting.gather(p,resource)
		if resource.skill~="Mining" or roll()>=CR.gemChance(resource.index) then return "" end
		local rough=CR.roughFor(resource.index,roll())
		if not rough then return "" end
		collect(p,rough,1)
		return "   ·   Rough gem! +1 "..nameOf(rough)
	end
	function Crafting.action(player,p,verb,item,prompt)
		if verb=="craftStation" then
			if not prompt then return "Visit a Crafting station on the Guild Terrace." end
			return Crafting.visit(player,item,prompt)
		elseif verb=="craftBatch" then return Crafting.start(player,p,item)
		elseif verb=="craftStop" then return Crafting.stop(player) end
		return "Unknown action."
	end
	function Crafting.state(player,p)
		local job=Crafting.jobs[player]
		local visit=Crafting.visits[player]
		local now=os.clock()
		return {
			job=job and {recipe=job.recipe,done=job.done,total=job.total,made=job.made,shattered=job.shattered,xp=job.xp,nextIn=math.max(0,job.nextAt-now)} or nil,
			station=if visit and now<=visit.untilAt then visit.station else "",
			stationIn=if visit then math.max(0,math.floor(visit.untilAt-now)) else 0,
			near=visit~=nil and near(player,visit),
			made=p.crafting and p.crafting.made or {},shattered=p.crafting and p.crafting.shattered or 0,
		}
	end
	function Crafting.forget(player)
		Crafting.jobs[player],Crafting.visits[player],Crafting.seq[player]=nil,nil,nil
	end
	task.spawn(function()
		while task.wait(CR.TICK) do Crafting.tick(os.clock()) end
	end)
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
	elseif Prayer.claims(verb,item) then
		return Prayer.action(player,p,verb,item,prompt,humanoid) -- Prayer & Thieving
	elseif SlayerTasks.verbs[verb] then
		return SlayerTasks.action(player,p,verb,item) -- Slayer tasks
	elseif Minigames.verbs[verb] then
		return Minigames.action(player,p,verb,item) -- Minigames: Commendation shop, cache rolls, titles
	elseif Logs.verbs[verb] then
		return Logs.action(player,p,verb,item,prompt) -- Commissions & Logs
	elseif Explore.verbs[verb] then
		return Explore.action(player,p,verb,item,prompt) -- Exploration & Factions: motes, shrines, Wayglass, factions
	elseif Crafting.verbs[verb] then
		return Crafting.action(player,p,verb,item,prompt) -- Crafting: stations, batches
	elseif Mastery.verbs[verb] then
		return Mastery.action(player,p,verb,item) -- Skill Mastery
	elseif Garden.verbs[verb] then
		return Garden.action(player,p,verb,item,prompt) -- Verdant Garden
	elseif Workers.verbs[verb] then
		return Workers.action(player,p,verb,item) -- Workers depth
	elseif Pets.verbs[verb] then
		return Pets.action(player,p,verb,item) -- Pets depth
	elseif Classes.verbs[verb] then
		return Classes.action(player,p,verb,item) -- Dungeon classes
	elseif Delve.verbs[verb] then
		return Delve.action(player,p,verb,item) -- Dungeon endgame
	elseif Trails.verbs[verb] then
		return Trails.action(player,p,verb,item) -- Treasure Trails
	elseif Lairs.verbs[verb] then
		return Lairs.action(player,p,verb,item,prompt) -- Lairs: altars and the arena exit
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
		Logs.prime(p) -- Commissions & Logs: Forgeheart fortune within the budget Mastery leaves
		local stats=Progression.computeStats(p,os.time())
		local ok,result=Progression.harvest(p,item,stats,roll,bonus,os.time())
		if not ok then
			if item=="Aetherite" then return result.." Train on Ore in Quarry Cay." end
			return result
		end
		-- Events hook: festival yield/XP multipliers apply exactly once, after fortune; festival-only catches.
		result.amount*=event.mult; result.xp=math.floor(result.xp*event.xpMult)
		for id,n in pairs(event.extra) do collect(p,id,n); note(p,"Festival catch • +"..n.." "..Data.Items[id].name) end
		-- Pets depth: the doubled-harvest ability is one more yield candidate inside
		-- Progression.gatherYieldMult (never stacks with mastery procs/surges).
		local petDouble=result.petDouble==true
		collect(p,item,result.amount)
		grantXp(p,skill,result.xp)
		if skill=="Farming" and Garden.fieldSeed then Garden.fieldSeed(p,item) end -- Verdant Garden seed pouch
		Trails.event(p,"gather",item) -- Treasure Trails: scroll drops + trail tasks (Fishing counts as "fish")
		Logs.regrow(p,result,resource) -- Commissions & Logs: Steadfast Pick joins the Mastery regrowth text
		local mastered=Mastery.gather(p,result) -- Skill Mastery: bonus ingots, coins, regrowth skip
		mastered..=Logs.gather(p,item,result,resource) -- Commissions & Logs: commission progress, Gemseeker
		mastered..=Crafting.gather(p,resource) -- Crafting: rare rough gem roll on Mining harvests
		if region then Journal.count(p,"gathers",region,1) end
		p.started=true
		if not regrowth then regrowth={}; nodeRegrowth[prompt]=regrowth; watchPrompt(prompt) end
		-- Skill Mastery: Quick regrowth shortens the timer down to a floor (Progression.regrowthTime), never to zero.
		regrowth[player]=os.clock()+(tonumber(result.regrowth) or tonumber(resource.respawn) or 3)
		local hooked=if skill=="Fishing" then Sea.cast(player,p,stats,result.tool,region,prompt) else ""
		return "+"..result.amount.." "..resource.name..(if petDouble then " (pet ×2)" else "").."   ·   +"..result.xp.." "..skill.." XP"..mastered..hooked
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
		-- Pets depth: an extra-craft ability may add one more batch of a stackable
		-- output (no extra XP; gear and other one-of-a-kind outputs never roll).
		local bonus=if Pets.craftExtra(p,recipe) then recipe.amount else 0
		if bonus>0 then collect(p,recipe.output,bonus) end
		return Data.Items[recipe.output].name.." crafted"..(if bonus>0 then " (+"..bonus.." from your pet)" else "").."   ·   +"..recipe.xp.." "..recipe.skill.." XP"
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
			Pets.gardenSync(p) -- Pets depth: growth so far used the dismissed pet
			p.activePet=nil
			return "Pet dismissed."
		end
		local pet=p.pets[index]
		local petDef=type(pet)=="table" and Data.PetById[pet.id]
		if not petDef then return "Choose a pet you have adopted." end
		if p.activePet==index then return "That pet is already summoned." end
		Pets.gardenSync(p) -- Pets depth: growth so far used the previous pet
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
	elseif verb=="satchelMove" then
		return Satchel.move(p,item) -- §29: display order only
	elseif verb=="satchelSort" then
		return Satchel.sort(p,item)
	elseif verb=="drop" then
		-- §29: destroy a whole stack (the satchel asks twice first). Equipped,
		-- bagged, summoned-pet and quiver items must be taken off first.
		local def=validId(item) and Data.Items[item]
		if not def then return "Choose an item to drop." end
		local count=p.items[item] or 0
		if count<1 then return "You have no "..def.name.." to drop." end
		if isEquipped(p,item) then return "Unequip "..def.name.." before dropping it." end
		if table.find(p.accessoryBag,item) then return "Take "..def.name.." out of your accessory bag first." end
		p.items[item]=0
		return "Dropped "..count.." "..def.name.."."
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
	-- Minigames: settle in-match XP before the final save (see minigames.server.lua).
	pcall(function() local mgLeave=ServerStorage:FindFirstChild("IsleMinigameLeave"); if mgLeave then mgLeave:Invoke(player) end end)
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
-- Dungeon classes (Dungeon Classes team): p.dungeonClasses (Data.DungeonClasses.migrate),
-- verbs dungeonClass "<classId>|none" and dungeonMaster "on|off" (refused while
-- the player is inside a run: attribute DungeonInRun), snapshot field dungeonClasses,
-- attributes DungeonClass / DungeonMasterOn / DungeonClassLevel. grantExpedition
-- below pays class XP, secrets and Master Mode rolls and records best scores.
do
	local DC=Data.DungeonClasses
	for _,verb in ipairs({"dungeonClass","dungeonMaster"}) do Classes.verbs[verb]=true end
	function Classes.migrate(p) p.dungeonClasses=DC.migrate(p.dungeonClasses) end
	function Classes.of(p)
		if type(p.dungeonClasses)~="table" or type(p.dungeonClasses.xp)~="table" or type(p.dungeonClasses.secrets)~="table" then Classes.migrate(p) end
		return p.dungeonClasses
	end
	function Classes.publish(player,p)
		local c=Classes.of(p)
		player:SetAttribute("DungeonClass",c.selected or "")
		player:SetAttribute("DungeonMasterOn",c.master==true)
		player:SetAttribute("DungeonClassLevel",if c.selected then DC.levelForXp(c.xp[c.selected]) else 0)
	end
	-- Normal-mode best score per floor index (p.dungeons.best is keyed by "floor").
	function Classes.best(p)
		local out={}
		local best=type(p.dungeons)=="table" and type(p.dungeons.best)=="table" and p.dungeons.best or {}
		for i=1,#Data.DungeonFloors do out[i]=tonumber(best[tostring(i)]) or 0 end
		return out
	end
	function Classes.state(p)
		local c=Classes.of(p)
		local best=Classes.best(p)
		local clears=type(p.dungeons)=="table" and type(p.dungeons.clears)=="table" and p.dungeons.clears or {}
		local classes={}
		for _,id in ipairs(DC.order) do
			local row=DC.progress(c.xp[id])
			row.milestones=DC.milestoneState(row.level)
			row.bonus=DC.levelBonus(id,row.level)
			row.cooldown=DC.cooldown(id,row.level)
			classes[id]=row
		end
		local floors={}
		for i=1,#Data.DungeonFloors do
			local key=tostring(i)
			floors[i]={secrets=c.secrets[key] or 0,secretsTotal=DC.secretCount(i),best=best[i],clears=tonumber(clears[key]) or 0,
				master=i<=DC.MASTER_FLOORS,masterUnlocked=DC.masterUnlocked(i,best[i]),masterBest=c.masterBest[key] or 0,masterClears=c.masterClears[key] or 0}
		end
		return {selected=c.selected,master=c.master==true,classes=classes,floors=floors}
	end
	-- Returns nil on success or a refusal message.
	function Classes.choose(player,p,class)
		local c=Classes.of(p)
		if player:GetAttribute("DungeonInRun")==true then return "Your class is locked until this Observatory run ends." end
		if class=="none" then c.selected=nil
		elseif DC.valid(class) then c.selected=class
		else return "Choose Aegis, Mender, Riftblade, Starshot or Arcanist." end
		Classes.publish(player,p)
		return nil
	end
	function Classes.action(player,p,verb,item)
		local c=Classes.of(p)
		if verb=="dungeonClass" then
			local refused=Classes.choose(player,p,item)
			if refused then return refused end
			if not c.selected then return "Class cleared • you delve unclassed." end
			local def=DC.defs[c.selected]
			return def.name.." ("..def.role..") chosen • class level "..DC.levelForXp(c.xp[c.selected]).."."
		elseif verb=="dungeonMaster" then
			if player:GetAttribute("DungeonInRun")==true then return "Master Mode is locked until this Observatory run ends." end
			if item~="on" and item~="off" then return "Choose on or off." end
			if item=="on" then
				local any=false
				for i,score in ipairs(Classes.best(p)) do if DC.masterUnlocked(i,score) then any=true end end
				if not any then return "Master Mode unlocks after a grade S clear of an Observatory floor (I-VII)." end
			end
			c.master=item=="on"
			Classes.publish(player,p)
			return "Master Mode "..item.." for the runs you open."
		end
		return "Unknown dungeon class action."
	end
end
-- Dungeon endgame (Dungeon Depth team): p.dungeonEndgame (Data.DungeonEndgame.migrate)
-- and p.masterStars. grantExpedition (below) refuses a repeated run id and a gear
-- score under the floor's gate, then Delve.afterClear records the run log, weekly
-- best, personal best and weekly bounty, and rolls the bonus chest once (contents
-- saved in the journal, so rejoining or leaving never rerolls it). Verbs:
--   dungeonChest "open" (coins) | "key" (one Lodestar Key) | "skip"
--   masterStar "<itemId>" (Master star ✪ k+1: essence + Eclipsed Starcores + coins)
--   essenceBuy "<exchangeId>" (Essence Exchange: Lodestar Key)
-- Snapshot field dungeonEndgame = {gearScore, gates, chest, log, week, pb, keys, cores, essence, masterStars}.
do
	local EG=Data.DungeonEndgame
	for _,verb in ipairs({"dungeonChest","masterStar","essenceBuy"}) do Delve.verbs[verb]=true end
	function Delve.migrate(p)
		p.dungeonEndgame=EG.migrate(p.dungeonEndgame,os.time())
		if type(p.masterStars)~="table" then p.masterStars={} end
		for id,n in pairs(p.masterStars) do
			local v=tonumber(n)
			if type(id)~="string" or not EG.canMasterStar(Data.Items[id]) or not v or v~=v or v<1 then p.masterStars[id]=nil
			else p.masterStars[id]=math.clamp(math.floor(v),1,EG.MASTER_STAR_MAX) end
		end
	end
	function Delve.of(p)
		local d=p.dungeonEndgame
		if type(d)~="table" or type(d.log)~="table" or type(d.week)~="table" or type(d.pb)~="table" or type(d.runs)~="table" then Delve.migrate(p) d=p.dungeonEndgame end
		if type(p.masterStars)~="table" then p.masterStars={} end
		-- Weekly rollover (forward only: a server whose clock is behind keeps the newer
		-- saved week, so it can never re-grant a claimed bounty) and chest expiry on read.
		local now=os.time()
		EG.rollWeek(d,now)
		if d.chest and (tonumber(d.chest.expires) or 0)<=now then d.chest=nil end
		return d
	end
	function Delve.state(p)
		local d=Delve.of(p)
		local now=os.time()
		local gates={}
		for i=1,#Data.DungeonFloors do gates[i]={normal=EG.gearGate(i,false),master=EG.gearGate(i,true)} end
		local chest=nil
		if d.chest then
			chest={floor=d.chest.floor,master=d.chest.master,grade=d.chest.grade,items=table.clone(d.chest.items),cost=d.chest.cost,expiresIn=math.max(0,d.chest.expires-now)}
		end
		local log={}
		for i,e in ipairs(d.log) do log[i]=table.clone(e) end
		local pb={}
		for k,v in pairs(d.pb) do pb[k]=table.clone(v) end
		return {gearScore=EG.gearScore(p),gates=gates,chest=chest,log=log,
			week={id=d.week.id,best=table.clone(d.week.best),bounty=table.clone(d.week.bounty),resetIn=math.max(0,(d.week.id+1)*EG.WEEK-now)},
			pb=pb,keys=p.items.LodestarKey or 0,cores=p.items.EclipsedStarcore or 0,essence=p.items.ObservatoryEssence or 0,masterStars=table.clone(p.masterStars)}
	end
	local function chestText(items)
		local t=string.gsub(dropText(items)," • ","",1)
		return if t~="" then t else "nothing"
	end
	-- After a credited clear: log, bests, weekly bounty, bonus chest. Returns message text.
	function Delve.afterClear(player,p,c)
		local d=Delve.of(p)
		local seconds=math.max(1,math.floor(tonumber(c.seconds) or 0))
		local deaths=math.clamp(math.floor(tonumber(c.deaths) or 0),0,99)
		local rec=EG.record(d,c.floor,c.master,c.grade,c.score,seconds,deaths,c.now)
		local text=""
		if rec.bounty>0 then
			collect(p,"ObservatoryEssence",rec.bounty)
			text..=" • weekly first clear: +"..rec.bounty.." Observatory Essence"
		end
		if rec.pb then text..=" • new personal best" end
		local plan=EG.bonusPlan(c.floor,c.grade,c.master)
		local items=Progression.rollDrops(plan.drops,c.stats.magicFind,roll,c.stats.petLuck)
		-- The fee is priced on the contents the player will see (EG.chestFee), not blind EV.
		local fresh={floor=c.floor,master=c.master==true,grade=c.grade,items=items,cost=EG.chestFee(c.floor,c.master,items),expires=c.now+EG.CHEST_SECONDS}
		if d.chest and EG.keepOldChest(d.chest,fresh) then
			-- Never silently overwrite an unopened chest holding a Master-only item or a unique.
			text..=" • your unopened bonus chest ("..chestText(d.chest.items)..") was kept; this clear's chest ("..chestText(items)..") was left behind"
			return text
		end
		if d.chest then text..=" • the unopened bonus chest ("..chestText(d.chest.items)..") was left behind" end
		d.chest=fresh
		text..=" • bonus chest waiting ("..fresh.cost.." coins or a Lodestar Key)"
		return text
	end
	function Delve.action(player,p,verb,item)
		local d=Delve.of(p)
		if verb=="dungeonChest" then
			local chest=d.chest
			if not chest then return "No Observatory bonus chest is waiting. Clear a floor to earn one." end
			if item=="skip" then
				d.chest=nil
				return "Bonus chest left sealed."
			elseif item~="open" and item~="key" then
				return "Open the bonus chest with coins or a key, or skip it."
			end
			if item=="key" then
				if (p.items.LodestarKey or 0)<1 then return "You have no Lodestar Key." end
				spend(p,{LodestarKey=1})
			else
				if p.coins<chest.cost then return "The bonus chest costs "..chest.cost.." coins." end
				p.coins-=chest.cost
			end
			d.chest=nil
			for id,n in pairs(chest.items) do collect(p,id,n) end
			p.started=true
			return "Bonus chest opened"..(if item=="key" then " with a Lodestar Key" else " • -"..chest.cost.." coins")..dropText(chest.items)
		elseif verb=="masterStar" then
			if not validId(item) or not Data.Items[item] then return "Choose a dungeon weapon or armor piece." end
			local def=Data.Items[item]
			if (p.items[item] or 0)<1 then return "You do not own "..def.name.."." end
			local ok,why=EG.masterStarCheck(p,item)
			if not ok then return why end
			local k=EG.masterStarsOf(p,item)+1
			local cost=EG.masterStarCost(def,k)
			if (p.items.ObservatoryEssence or 0)<cost.amount then return "Master star "..k.." needs "..cost.amount.." Observatory Essence." end
			if (p.items.EclipsedStarcore or 0)<cost.cores then return "Master star "..k.." needs "..cost.cores.." Eclipsed Starcore"..(if cost.cores>1 then "s" else "").." (Master Mode chests)." end
			if p.coins<cost.coins then return "Master star "..k.." costs "..cost.coins.." coins." end
			spend(p,{ObservatoryEssence=cost.amount,EclipsedStarcore=cost.cores})
			p.coins-=cost.coins
			p.masterStars[item]=k
			p.started=true
			return def.name.." gains Master star "..string.rep("✪",k).." • -"..cost.amount.." essence, -"..cost.cores.." Starcore, -"..cost.coins.." coins."
		elseif verb=="essenceBuy" then
			local e=type(item)=="string" and EG.ExchangeById[item]
			if not e then return "Choose an Essence Exchange item." end
			if (p.items.ObservatoryEssence or 0)<e.essence then return Data.Items[e.id].name.." costs "..e.essence.." Observatory Essence." end
			if p.coins<e.coins then return Data.Items[e.id].name.." costs "..e.coins.." coins." end
			spend(p,{ObservatoryEssence=e.essence})
			p.coins-=e.coins
			collect(p,e.id,1)
			return "Exchanged "..e.essence.." Observatory Essence for a "..Data.Items[e.id].name.."."
		end
		return "Unknown Observatory action."
	end
end
local expedition = Instance.new("BindableEvent")
expedition.Name = "IsleExpeditionReward"
-- Dungeons: result {floor, grade, score, partySize, damageShare} from expedition.server.lua
-- (+ Dungeon classes: class, master, secrets, teamMult; a bare Fire(player) is a
-- legacy Floor I, grade B clear). The profile re-checks the floor's Dungeoneering
-- gate, the Master Mode unlock, the 90 s clear cooldown and the Ironman rule.
-- grantExpedition returns {ok=true} or {ok=false,reason}; the IsleExpeditionGrant
-- BindableFunction exposes it so the Observatory only announces accepted chests.
local function grantExpedition(player,result)
	local p=profiles[player]
	if not p or (not preview[player] and os.time()>=(leaseEnd[player] or 0)) then return {ok=false,reason="Your journal is syncing, so the Observatory chest could not be credited."} end
	result=if type(result)=="table" then result else {}
	local DC=Data.DungeonClasses
	local floorIndex=if type(result.floor)=="number" and Data.DungeonFloors[result.floor] then result.floor else 1
	local floor=Data.DungeonFloors[floorIndex]
	local grade=if type(result.grade)=="string" and Data.DungeonGradeById[result.grade] then result.grade else "B"
	local score=if type(result.score)=="number" and result.score==result.score then math.clamp(math.floor(result.score),0,300) else 0
	local partySize=if type(result.partySize)=="number" then result.partySize else 1
	local share=if type(result.damageShare)=="number" and result.damageShare==result.damageShare then result.damageShare else 1
	local master=result.master==true and floorIndex<=DC.MASTER_FLOORS
	local class=if DC.valid(result.class) then result.class else nil
	local secrets=if type(result.secrets)=="number" and result.secrets==result.secrets then math.clamp(math.floor(result.secrets),0,DC.secretCount(floorIndex)) else 0
	local teamMult=if type(result.teamMult)=="number" and result.teamMult==result.teamMult then result.teamMult else 1
	local now=os.time()
	local dungeons=type(p.dungeons)=="table" and p.dungeons or {lastClear=0,clears={},best={}}
	p.dungeons=dungeons
	dungeons.clears=dungeons.clears or {}
	dungeons.best=dungeons.best or {}
	local c=Classes.of(p)
	if level(p.xp.Dungeoneering)<floor.level then return {ok=false,reason=floor.name.." requires Dungeoneering "..floor.level.."."} end
	if master and not DC.masterUnlocked(floorIndex,Classes.best(p)[floorIndex]) then
		return {ok=false,reason="Master Mode "..floor.name.." needs a grade S clear of the floor first."}
	end
	-- Dungeon endgame: gear-score gate (recomputed from the journal) and one credit per run id.
	local EG=Data.DungeonEndgame
	local gearScore=EG.gearScore(p)
	if gearScore<EG.gearGate(floorIndex,master) then
		return {ok=false,reason=EG.accessText(floorIndex,master,"gear").." Yours is "..gearScore.."."}
	end
	local delve=Delve.of(p)
	local runId=if type(result.runId)=="string" and #result.runId<=64 then result.runId else nil
	if runId and table.find(delve.runs,runId) then return {ok=false,reason="This Observatory run was already credited to your journal."} end
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
	if runId then EG.rememberRun(delve,runId) end
	local key=tostring(floorIndex)
	if master then
		c.masterClears[key]=(c.masterClears[key] or 0)+1
		if score>(c.masterBest[key] or 0) then c.masterBest[key]=score end
	else
		dungeons.clears[key]=(dungeons.clears[key] or 0)+1
		if score>(dungeons.best[key] or 0) then dungeons.best[key]=score end
	end
	if secrets>(c.secrets[key] or 0) then c.secrets[key]=secrets end
	local reward=DC.runRewards(floorIndex,grade,{master=master,secrets=secrets,class=class,teamMult=teamMult})
	p.started=true
	grantXp(p,"Combat",reward.combatXp)
	grantXp(p,"Dungeoneering",reward.dungeoneeringXp)
	p.coins+=reward.coins
	for item,n in pairs(reward.items) do collect(p,item,n) end
	local classText=""
	if class and reward.classXp>0 then
		local before=DC.levelForXp(c.xp[class])
		c.xp[class]=math.min(DC.MAX_XP,(c.xp[class] or 0)+reward.classXp)
		local after=DC.levelForXp(c.xp[class])
		classText=", +"..reward.classXp.." "..DC.defs[class].name.." XP"
		if after>before then note(p,DC.defs[class].name.." class level "..after.."!") end
		Classes.publish(player,p)
	end
	local stats=Progression.computeStats(p,now)
	local drops={}
	for _=1,reward.rolls do
		for item,n in pairs(Progression.rollDrops(reward.chest,stats.magicFind,roll,stats.petLuck)) do drops[item]=(drops[item] or 0)+n end
	end
	for item,n in pairs(drops) do collect(p,item,n) end
	local endText=Delve.afterClear(player,p,{floor=floorIndex,master=master,grade=grade,score=score,deaths=result.deaths,seconds=result.seconds,stats=stats,now=now})
	update:FireClient(player,snapshot(player,(if master then "Master " else "")..floor.name.." cleared • Grade "..grade.." • +"..reward.coins.." coins, +"..reward.combatXp.." Combat and +"
		..reward.dungeoneeringXp.." Dungeoneering XP"..classText..", "..reward.items.Stormglass.." Stormglass"..(if secrets>0 then " • "..secrets.." secrets found" else "")..dropText(drops)..endText))
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
		if p and type(p.prayer)=="table" then raw,defense=Prayer.incoming(p,raw,defense,payload) end -- Prayer: protection + wards
		local amount=Progression.damageTaken(math.min(raw,1e9),defense)
		humanoid:TakeDamage(amount)
		return amount
	end
	local p=live(player)
	if not p then
		-- Combat re-arms the boss / resends the sea creature kill (ticket kept)
		-- when its report could not be applied; Endgame: combat resends world boss rewards.
		return if op=="slayerBoss" or op=="seaCreature" or op=="worldBoss" or op=="slayerSuperior" or op=="lair" then {ok=false,reason="sync"} else nil
	end
	if op=="stats" then
		return {stats=Progression.computeStats(p,os.time()),combatLevel=level(p.xp.Combat),ironman=p.ironman==true,
			loadout=Progression.combatLoadout(p), -- Combat styles: weapon style, quiver, supplies, autocast
			mastery=Progression.masteryCombat(p,os.time()), -- Skill Mastery perks combat applies (see Mastery block)
			prayer=Prayer.combat(p), -- Prayer: protection / offence / sap / mana (see Prayer & Thieving block)
			slayer=SlayerTasks.combat(p)} -- Slayer tasks: Slayer level, task family, visor bonus
	elseif op=="consume" then
		return CombatStyles.consume(p,payload)
	elseif op=="refund" then
		return CombatStyles.refund(p,payload)
	elseif op=="combatXp" then
		local reply=CombatStyles.xp(p,payload)
		if reply.levelled then notify(player,"") end
		return reply
	elseif op=="dungeon" then
		-- Dungeons: floor gate + Ironman flag for expedition.server.lua;
		-- Dungeon classes: selected class, class XP, normal-mode best scores, Master Mode preference.
		local c=Classes.of(p)
		return {level=level(p.xp.Dungeoneering),ironman=p.ironman==true,class=c.selected,classXp=table.clone(c.xp),best=Classes.best(p),master=c.master==true,
			gearScore=Data.DungeonEndgame.gearScore(p)} -- Dungeon endgame: gear-score gate
	elseif op=="dungeonClass" then
		-- Dungeon classes: the pad pedestals persist the chosen class.
		return {ok=Classes.choose(player,p,payload.class)==nil}
	elseif op=="kill" then
		local monsterId=payload.monster
		local monster=validId(monsterId) and Data.Monsters[monsterId]
		-- Sea creatures pay only through their owner's ticket (op "seaCreature").
		if not monster or monster.seaCreature or monster.worldBoss or monster.superior or monster.lair then return nil end -- Lairs: paid only through op "lair"
		local stats=Progression.computeStats(p,os.time())
		p.started=true
		-- Pets depth: family abilities add % coins, Magic Find and slayer progress vs that line.
		local family=Pets.familyBonus(p,monster)
		local coins=monster.coins+math.floor(monster.coins*family/100+0.5)
		-- No flat Combat XP here: the damage XP accrued on the monster is paid
		-- through "combatXp" when it dies (monster.xp in total for melee).
		p.coins+=coins
		local drops=Progression.rollDrops(monster.drops,stats.magicFind+family,roll,stats.petLuck)
		for item,n in pairs(drops) do collect(p,item,n) end
		-- Events hook: Hollow Night event-only drops (Data.eventKillDrops).
		for item,n in pairs(Data.eventKillDrops(monsterId,Data.eventState(workspace,os.time()),roll)) do drops[item]=(drops[item] or 0)+n; collect(p,item,n) end
		p.bestiary[monsterId]=(p.bestiary[monsterId] or 0)+1
		Trails.event(p,"kill",monsterId) -- Treasure Trails: scroll drops + trail tasks
		Logs.event(p,"kill",monsterId) -- Commissions & Logs: kill commissions
		local quest=p.slayerQuest
		if quest and not quest.bossReady and monster.slayer==quest.line then
			quest.progress=math.min(quest.needed,quest.progress+math.floor(monster.xp*(1+family/100)))
			if quest.progress>=quest.needed then
				quest.bossReady=true
				note(p,"The "..Data.Slayers[quest.line].name.." stirs! Defeat it to finish your slayer quest.")
			end
		end
		-- Slayer tasks: task credit, Slayer XP, superior roll. Combat sets task=true only for a killer
		-- with a real damage share (Data.SlayerTasks.taskEligible); tag-alongs keep normal kill rewards.
		local superior=if payload.task==true then SlayerTasks.onKill(player,p,monsterId,monster) else nil
		notify(player,monster.name.." slain • +"..coins.." coins"..dropText(drops))
		return {drops=drops,bossReady=quest~=nil and quest.bossReady==true,superior=superior}
	elseif op=="lair" then
		-- Lairs: kill rewards, entry closes and fee refunds from lairs.server.lua.
		local reply=Lairs.bridge(player,p,payload)
		if reply.message then notify(player,reply.message); reply.message=nil end
		return reply
	elseif op=="worldBoss" then
		local reply=Endgame.reward(player,p,payload)
		if reply.message then notify(player,reply.message); reply.message=nil end
		return reply
	elseif op=="seaCreature" then
		local reply=Sea.report(player,p,payload)
		if reply.message then notify(player,reply.message..dropText(reply.drops)); reply.message=nil end
		return reply
	elseif op=="slayerSuperior" or op=="slayerDenied" then
		-- Slayer tasks: superior settlement (owner ticket) and slayer-level refusals.
		if op=="slayerDenied" then local text=SlayerTasks.denied(player,p,payload); if text then notify(player,text) end return nil end
		local reply=SlayerTasks.superiorReport(player,p,payload)
		if reply.message then notify(player,reply.message); reply.message=nil end
		return reply
	elseif op=="minigame" then
		-- Minigames: lobby info, barricade Timber, match settlement (see the Minigames block).
		local reply=Minigames.bridge(player,p,payload)
		if type(reply)=="table" and reply.message then notify(player,reply.message); reply.message=nil end
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
		local skillXp=Data.SlayerTasks.bossXp(quest.line,quest.tier) -- Slayer tasks: boss lines also train the Slayer skill
		grantXp(p,"Slayer",skillXp)
		local drops=Progression.rollDrops(tier.drops,stats.magicFind,roll,stats.petLuck)
		for item,n in pairs(drops) do collect(p,item,n) end
		notify(player,line.name.." defeated • +"..tier.xp.." "..quest.line.." Slayer XP, +"..skillXp.." Slayer skill XP"..dropText(drops))
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
