-- Shared homesteads (crews of up to four, SkyBlock co-op / OSRS Group Ironman).
--
-- Storage: "group_<id>" holds the crew record and "member_<userId>" is each
-- player's unique index (pending reservation, joined, or {empty, cooldown}).
-- Every mutation is a DataStore UpdateAsync transform that is pure in the old
-- value, so Roblox retries and replays after a lost acknowledgement are safe.
-- Group writes always happen first; the member index follows, and any server
-- heals a stale "joined" index whose group no longer lists that member.
--
-- Lifecycle rules:
--   * leave: the member is removed; supplies they contributed stay with the
--     crew (contributions are gifts, not loans). A leaving leader passes
--     leadership to the longest-standing member. The last member to leave
--     disbands the crew (the record is kept, marked disbanded; the founder's
--     key can be reused by a later crew).
--   * kick: leader only, needs a listed reason. Personal progression,
--     satchel and the kicked player's own island are never touched; only the
--     crew perk (p.perkStats.coop) disappears.
--   * transfer: leader only, to a current member.
--   * invitations expire after Data.Coop.InviteSeconds and the leader can
--     revoke them; a revoked/expired token can never complete a join.
--   * leaving or being removed starts Data.Coop.RejoinCooldown (24 h) before
--     the player may join or found any crew, so crews cannot be hopped.
--
-- Group Ironman: Ironman journals already cannot use the exchange, Bazaar or
-- Auction House (server.server.lua). Ironman crews accept only Ironman
-- journals, so the shared stores (deposit / withdraw) are the one and only
-- way Ironman players move items to anyone: within their own crew.
--
-- Satchel transfers cross two keys. Deposits use a per-player outbox kept in
-- the journal (sequence numbers; the crew ledger remembers the last applied
-- sequence), withdrawals use a crew outbox keyed by token (the journal
-- remembers delivered tokens). Either side can crash at any point and the
-- next action from that player settles the transfer exactly once. A delivered
-- withdrawal token is pruned from the crew outbox lazily (by the next write to
-- that crew, or the 30 s flush), so a withdrawal costs one crew write; the
-- journal's delivered-token list keeps a replay in between idempotent.
--
-- Shared supplies (the crew-haven Timber/Ore/Herb nodes; struck nodes since §42,
-- credited through ServerStorage.IsleCoopStrike, see below) are building
-- material, not loot:
--   * each (node, member) regrows after PROMPT_REGROW seconds, like personal
--     nodes, and each member may add at most PROMPT_HOURLY units per UTC hour
--     (checked durably in the ledger when the batch is flushed);
--   * prompt units are "bound": they fund builds and worker upgrades (which
--     spend bound units first) and earn Homestead XP, but can never be
--     withdrawn to a satchel (withdrawable stock = supplies - bound);
--   * gathers are batched in server memory and flushed every FLUSH_EVERY
--     seconds (or merged into the next write to that crew). A server crash
--     loses at most one unflushed batch of free prompt units; that is accepted.
-- Withdrawal rule: a member may withdraw at most
--   (own deposits - own withdrawals) + floor(credit)
-- where credit is an equal share (1 / crew size at the time) of every unit of
-- shared-worker output claimed and of every other member's deposit. Combined
-- with the bound rule, items only leave the stores as real goods that entered
-- them (deposits) or worker output, so prompts cannot mint satchel items.
--
-- DataStore budget: mutating verbs are gated to one per MUTATE_GATE seconds
-- per player; state requests, prompt checks and the refresh loop read through
-- a per-key cache (CACHE_TTL); when GetRequestBudgetForRequestType reports a
-- low GetAsync budget, optional reads serve stale cache and the refresh loop
-- skips its pass.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local DataStoreService=game:GetService("DataStoreService")
local ProximityPromptService=game:GetService("ProximityPromptService")
local HttpService=game:GetService("HttpService")
local Data=require(ReplicatedStorage:WaitForChild("AetherData"))
local Coop=Data.Coop
local store
pcall(function() store=DataStoreService:GetDataStore("Aether_Coop_v1") end)
local action=Instance.new("RemoteFunction")
action.Name="IsleCoopAction"
local changed=Instance.new("RemoteEvent")
changed.Name="IsleCoopUpdate"
changed.Parent=ReplicatedStorage
local busy,lastRequest,invitations,cachedGroup,perkSig={},{},{},{},{}
local MUTATE_GATE,READ_GATE,CACHE_TTL,FLUSH_EVERY=6,0.6,8,30
local PROMPT_REGROW,PROMPT_HOURLY,DEPARTED_KEEP,BUDGET_FLOOR=5,120,4,20
local lastMutate,lastPrompt,regrow,hourly,retryAt={},{},{},{},{}
-- cache[ck] = {value, at}; pending[ck] = prompt gather batch; acked[ck] =
-- delivered withdrawal tokens awaiting removal from that crew's outbox.
local cache,pending,acked,meta={},{},{},{}
-- clean[player]: index healed and crew outboxes replayed this session. Cleared
-- by any failed action, failed delivery or a stale index seen on refresh, so
-- the extra recovery reads happen only when something may be half-done.
local clean={}
local previewData={}
local costs={Garden={Herb=3,Timber=3},Lanterns={Timber=5},Deck={Timber=10,Ore=5}}
local resources={Timber=true,Ore=true,Herb=true}
local supplyKinds={}
for _,name in ipairs(Coop.Resources) do supplyKinds[name]=true end
local kickReasons={}
for _,reason in ipairs(Coop.KickReasons) do kickReasons[reason.id]=reason.text end
local function clone(value)
	if type(value)~="table" then return value end
	local out={}; for k,v in pairs(value) do out[k]=clone(v) end; return out
end
local function invoke(player,seal,request)
	local hook=ServerStorage:FindFirstChild("IsleCoopProfile")
	if not hook then return nil end
	local ok,profile=pcall(function() return hook:Invoke(player,seal==true,request) end)
	if not ok or type(profile)~="table" or not profile.ready then return nil end
	return profile
end
local function eligibility(player,seal) return invoke(player,seal,nil) end
local function cacheKey(key,preview) return (preview and "p|" or "")..key end
local function remember(key,preview,value) cache[cacheKey(key,preview)]={value=clone(value),at=os.clock()} end
-- True unless the engine reports a low GetAsync budget (absent API = fine).
local function budget()
	local ok,n=pcall(function() return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) end)
	return not ok or type(n)~="number" or n>=BUDGET_FLOOR
end
local function readRaw(key,preview)
	if preview then return clone(previewData[key]) end
	if not store then error("Co-op saving unavailable") end
	local value=store:GetAsync(key)
	remember(key,preview,value)
	return value
end
-- Optional reads (state, refresh, prompts): cached, stale when budget is low.
local function readCached(key,preview)
	if preview then return readRaw(key,true) end
	local hit=cache[cacheKey(key,preview)]
	if hit and (os.clock()-hit.at<CACHE_TTL or not budget()) then return clone(hit.value) end
	return readRaw(key,preview)
end
local function read(key,preview)
	local value=readRaw(key,preview)
	return value and not value.empty and value or nil
end
local function write(key,preview,transform)
	if preview then
		local value=transform(clone(previewData[key]))
		if value~=nil then previewData[key]=clone(value) end
		return clone(value)
	end
	if not store then error("Co-op saving unavailable") end
	local ok,value=pcall(function() return store:UpdateAsync(key,transform) end)
	if not ok or value==nil then cache[cacheKey(key,preview)]=nil end
	if not ok then error(value,0) end
	if value~=nil then remember(key,preview,value) end
	return value
end
-- Departed-crew history kept on the member index (newest first, <= DEPARTED_KEEP)
-- so undelivered withdrawals from any recent crew are still recovered.
local function history(old,add)
	local out={}
	local function push(groupId)
		if type(groupId)=="string" and not table.find(out,groupId) and #out<DEPARTED_KEEP then table.insert(out,groupId) end
	end
	push(add)
	if old then
		for _,groupId in ipairs(type(old.gone)=="table" and old.gone or {}) do push(groupId) end
		push(old.left)
	end
	return out
end
-- Group ids: the founder's user id, or "<userId>-<n>" for that founder's later crews.
local function id(value)
	if type(value)~="string" or #value>24 then return nil end
	local head,gen=value:match("^(%d+)%-(%d+)$")
	head=head or value:match("^%d+$") and value
	if not head or #head>16 then return nil end
	local n=tonumber(head)
	if not n or n<=0 or n%1~=0 then return nil end
	if gen then
		local g=tonumber(gen)
		if not g or g<2 or g>99 or tostring(g)~=gen then return nil end
		return tostring(n).."-"..g
	end
	return tostring(n)
end
local function founded(groupId,userId) return groupId==userId or groupId:match("^(%d+)%-")==userId end
local function span(seconds)
	seconds=math.max(0,math.floor(seconds))
	if seconds>=3600 then return math.floor(seconds/3600).."h "..math.floor(seconds%3600/60).."m" end
	return math.max(1,math.ceil(seconds/60)).."m"
end
local function count(map) local n=0; for _ in pairs(map) do n+=1 end; return n end
-- Fills fields added after the first co-op release and prunes expired state.
local function normalize(g)
	g.members=g.members or {}; g.invites=g.invites or {}; g.supplies=g.supplies or {}; g.decorations=g.decorations or {}
	g.joined=g.joined or {}; g.ledger=g.ledger or {}; g.workers=g.workers or {}; g.departed=g.departed or {}
	g.outbox=g.outbox or {}; g.log=g.log or {}; g.xp=tonumber(g.xp) or 0; g.bound=g.bound or {}
	for resource,n in pairs(g.bound) do g.bound[resource]=math.clamp(n,0,g.supplies[resource] or 0) end
	local t=os.time()
	for userId in pairs(g.members) do g.joined[userId]=g.joined[userId] or 0 end
	for userId,invite in pairs(g.invites) do if type(invite)~="table" or invite.expires<=t then g.invites[userId]=nil end end
	for userId,gone in pairs(g.departed) do if gone.at+Coop.RejoinCooldown*2<t then g.departed[userId]=nil end end
	return g
end
local function ledgerOf(g,userId)
	local l=g.ledger[userId]
	if not l then l={gathered=0,deposited=0,withdrawn=0,built=0,worker=0,peak=0,seq=0,points=0}; g.ledger[userId]=l end
	l.credit=l.credit or 0
	return l
end
-- Gives every current member except `except` an equal share of `amount`.
local function share(g,amount,except)
	local n=0
	for _ in pairs(g.members) do n+=1 end
	if n==0 or amount<=0 then return end
	for memberId in pairs(g.members) do
		if memberId~=except then local l=ledgerOf(g,memberId); l.credit+=amount/n end
	end
end
local function allowance(g,userId)
	local l=ledgerOf(g,userId)
	return math.max(0,l.deposited+math.floor(l.credit+1e-9)-l.withdrawn)
end
-- Spends shared supplies, bound (prompt) units first.
local function spend(g,resource,amount)
	g.supplies[resource]=(g.supplies[resource] or 0)-amount
	g.bound[resource]=math.clamp((g.bound[resource] or 0)-amount,0,g.supplies[resource])
end
local function addXp(g,userId,amount)
	if amount<=0 then return end
	g.xp+=amount
	local l=ledgerOf(g,userId); l.points+=amount
end
local function note(g,text)
	table.insert(g.log,1,{at=os.time(),text=text})
	while #g.log>Coop.LogSize do table.remove(g.log) end
end
local function levelOf(g) return Data.coopLevel(g.xp) end
local function nameOf(g,userId) return g.members[userId] or (g.ledger[userId] and g.ledger[userId].name) or ("Voyager "..userId) end
-- Longest-standing remaining member (ties by user id) inherits leadership.
local function successor(g)
	local best,bestAt
	for userId in pairs(g.members) do
		local at=g.joined[userId] or 0
		if not best or at<bestAt or (at==bestAt and tonumber(userId)<tonumber(best)) then best,bestAt=userId,at end
	end
	return best
end
-- Removes one member; disbands on the last. Pure in g (used inside transforms).
local function depart(g,userId,kicked,reason,by)
	local t=os.time()
	local l=ledgerOf(g,userId); l.name=g.members[userId]
	g.members[userId]=nil
	g.joined[userId]=nil
	g.departed[userId]={at=t,kicked=kicked==true,reason=reason,by=by}
	if tostring(g.owner)==userId then
		local heir=successor(g)
		g.owner=heir and tonumber(heir) or g.owner
		if heir then note(g,nameOf(g,heir).." now leads the crew.") end
	end
	if not next(g.members) then
		g.disbanded=true; g.disbandedAt=t
		g.invites={}; g.workers={}; g.supplies={}; g.bound={}
		note(g,"The crew disbanded.")
	end
end
local function workerReady(w,t)
	local tier=Data.WorkerTiers[w.tier]
	return math.clamp(math.floor(((t or os.time())-w.lastClaim)/tier.interval),0,tier.capacity),tier
end
-- Claims one worker into the shared stores inside a transform. Returns units.
local function claimWorker(g,w,userId)
	local t=os.time()
	local ready,tier=workerReady(w,t)
	local _,def=levelOf(g)
	local room=math.max(0,def.storage-(g.supplies[w.resource] or 0))
	local amount=math.min(ready,room)
	if ready>=tier.capacity then w.lastClaim=t-(tier.capacity-amount)*tier.interval
	else w.lastClaim+=amount*tier.interval end
	if amount>0 then
		g.supplies[w.resource]=(g.supplies[w.resource] or 0)+amount
		if userId then local l=ledgerOf(g,userId); l.worker+=amount end
		share(g,amount,nil)
	end
	return amount
end
-- Applies one prompt gather batch (pure in g). Members only, same mode,
-- capped by the member's hourly prompt allowance and the storage cap.
local function applyGathers(g,batch,t)
	if not g or g.disbanded then return false end
	normalize(g)
	local _,def=levelOf(g)
	local hour=math.floor(t/3600)
	local any=false
	for userId,entry in pairs(batch.users) do
		if g.members[userId] and g.ironman==entry.ironman then
			local l=ledgerOf(g,userId)
			if l.promptHour~=hour then l.promptHour=hour; l.promptCount=0 end
			for resource,n in pairs(entry.res) do
				local take=math.min(n,PROMPT_HOURLY-l.promptCount,def.storage-(g.supplies[resource] or 0))
				if take>0 then
					g.supplies[resource]=(g.supplies[resource] or 0)+take
					g.bound[resource]=(g.bound[resource] or 0)+take
					l.promptCount+=take; l.gathered+=take
					addXp(g,userId,take)
					any=true
				end
			end
		end
	end
	return any
end
-- Every crew write goes through here: it folds in this server's pending
-- prompt batch and prunes delivered withdrawal tokens in the same UpdateAsync.
-- The caller's transform keeps its own nil = "denied" meaning; housekeeping is
-- still committed in that case. On failure the batch and acks are restored.
local function writeGroup(groupId,preview,transform)
	local ck=cacheKey("group_"..groupId,preview)
	local batch,acks=pending[ck],acked[ck]
	pending[ck],acked[ck]=nil,nil
	local t=os.time()
	local result
	local ok,err=pcall(write,"group_"..groupId,preview,function(old)
		result=nil
		local house=false
		if old and acks and old.outbox then
			for token in pairs(acks) do if old.outbox[token] then old.outbox[token]=nil; house=true end end
		end
		if old and batch and applyGathers(old,batch,t) then house=true end
		local saved=house and clone(old) or nil
		result=transform(old)
		if result~=nil then return result end
		return saved
	end)
	if not ok then
		if batch then
			local now=pending[ck]
			if now then
				for userId,entry in pairs(batch.users) do
					local into=now.users[userId] or {ironman=entry.ironman,res={}}
					now.users[userId]=into
					for resource,n in pairs(entry.res) do into.res[resource]=(into.res[resource] or 0)+n end
				end
				now.since=math.min(now.since,batch.since)
			else pending[ck]=batch end
		end
		if acks then
			acked[ck]=acked[ck] or {}
			for token in pairs(acks) do acked[ck][token]=true end
		end
		error(err,0)
	end
	return clone(result)
end
-- Commits this server's pending housekeeping for one crew (1 write).
local function flush(ck)
	local m=meta[ck]
	if not m or not (pending[ck] or acked[ck]) then return true end
	return (pcall(writeGroup,m.groupId,m.preview,function() return nil end))
end
local function flushDue(force)
	local now=os.clock()
	local keys={}
	for ck in pairs(meta) do table.insert(keys,ck) end
	for _,ck in ipairs(keys) do
		local batch=pending[ck]
		if force or acked[ck] or (batch and now-batch.since>=FLUSH_EVERY) then flush(ck) end
		if not pending[ck] and not acked[ck] then meta[ck]=nil end
	end
end
local function perkFor(g)
	local _,def=levelOf(g)
	return def.stats
end
local function signature(stats)
	if not stats then return "" end
	local keys={}
	for k in pairs(stats) do table.insert(keys,k) end
	table.sort(keys)
	local parts={}
	for _,k in ipairs(keys) do table.insert(parts,k.."="..tostring(stats[k])) end
	return table.concat(parts,";")
end
local function publish(player,group,groupId,profile)
	local member=group and group.members[tostring(player.UserId)]
	if not member then group=nil; groupId=nil end
	cachedGroup[player]=groupId
	player:SetAttribute("CoopPreview",profile.preview==true)
	player:SetAttribute("CoopId",groupId)
	player:SetAttribute("CoopOwner",group and group.owner or nil)
	player:SetAttribute("CoopLevel",group and (levelOf(group)) or nil)
	local workers=0
	if group then for _,w in pairs(group.workers) do if w then workers+=1 end end end
	player:SetAttribute("CoopWorkers",group and workers or nil)
	for name in pairs(costs) do player:SetAttribute("Coop"..name,group and group.decorations[name]==true or false) end
	-- Group stat perk lives in the personal journal's perkStats.coop slot.
	local stats=group and perkFor(group) or nil
	if stats and not next(stats) then stats=nil end
	local sig=signature(stats)
	if perkSig[player]~=sig then
		local applied=invoke(player,false,{perk=stats and clone(stats) or false})
		if applied then perkSig[player]=sig end
	end
end
local function snapshot(player,profile,message)
	local userId=tostring(player.UserId)
	local raw=readCached("member_"..userId,profile.preview)
	local index=raw and not raw.empty and raw or nil
	local group=index and readCached("group_"..index.groupId,profile.preview)
	group=group and not group.empty and group or nil
	if group then normalize(group) end
	local member=group and group.members[userId]
	publish(player,member and group or nil,member and index.groupId or nil,profile)
	local t=os.time()
	local cooldown=raw and raw.empty and raw.cooldownUntil or nil
	local removal=raw and raw.empty and raw.kicked and {reason=kickReasons[raw.reason] or raw.reason} or nil
	if index and (index.kind~="joined")==(member~=nil) then clean[player]=nil end
	if index and index.kind=="joined" and not member then
		local gone=group and group.departed[userId]
		cooldown=gone and gone.at+Coop.RejoinCooldown or nil
		removal=gone and gone.kicked and {reason=kickReasons[gone.reason] or gone.reason} or nil
	end
	if cooldown and cooldown<=t then cooldown=nil end
	if not cooldown then removal=nil end
	local state={groupId=member and index.groupId or nil,pendingGroup=index and not member and index.kind~="joined" and index.groupId or nil,
		owner=member and group.owner or nil,members={},ironman=member and group.ironman or profile.ironman,
		supplies=member and clone(group.supplies) or {},decorations=member and clone(group.decorations) or {},
		invites={},outgoing={},workers={},log={},preview=profile.preview==true,message=message or "",
		cooldownUntil=cooldown,cooldownText=cooldown and span(cooldown-t) or nil,removal=removal,
		kickReasons=clone(Coop.KickReasons),resources=clone(Coop.Resources),transferMax=Coop.TransferMax,maxMembers=Coop.MaxMembers}
	if member then
		for memberId,name in pairs(group.members) do
			local l=group.ledger[memberId] or {}
			table.insert(state.members,{userId=tonumber(memberId),name=name,role=tostring(group.owner)==memberId and "Leader" or "Member",
				joined=group.joined[memberId] or 0,points=l.points or 0,gathered=l.gathered or 0,deposited=l.deposited or 0,
				withdrawn=l.withdrawn or 0,built=l.built or 0,worker=l.worker or 0})
		end
		table.sort(state.members,function(a,b) return a.userId<b.userId end)
		for inviteeId,invite in pairs(group.invites) do table.insert(state.outgoing,{userId=tonumber(inviteeId),name=invite.name,expiresIn=invite.expires-t}) end
		table.sort(state.outgoing,function(a,b) return a.userId<b.userId end)
		local n,def=levelOf(group)
		local nextDef=Coop.Levels[n+1]
		state.level={level=n,maxLevel=#Coop.Levels,xp=group.xp,floor=def.xp,nextXp=nextDef and nextDef.xp or nil,storage=def.storage,
			workerSlots=def.workers,workerTier=def.workerTier,stats=clone(def.stats),nextStats=nextDef and clone(nextDef.stats) or nil,
			nextStorage=nextDef and nextDef.storage or nil,nextWorkers=nextDef and nextDef.workers or nil}
		for slot=1,def.workers do
			local w=group.workers[slot]
			if w then
				local ready,tier=workerReady(w,t)
				local cost={}
				for resource,amount in pairs(Coop.WorkerUpgradeCost) do cost[resource]=amount*w.tier end
				table.insert(state.workers,{slot=slot,resource=w.resource,tier=w.tier,ready=ready,interval=tier.interval,
					capacity=tier.capacity,maxTier=def.workerTier,upgradeCost=w.tier<def.workerTier and cost or nil})
			else table.insert(state.workers,{slot=slot}) end
		end
		for _,entry in ipairs(group.log) do table.insert(state.log,entry.text) end
	end
	-- Prompt gathers still waiting in this server's batch (flushed <= 30 s).
	local batch=member and pending[cacheKey("group_"..index.groupId,profile.preview)]
	if batch then
		for _,entry in pairs(batch.users) do
			for resource,n in pairs(entry.res) do state.supplies[resource]=(state.supplies[resource] or 0)+n end
		end
	end
	if member then state.withdrawable=allowance(group,userId) end
	for groupId,invite in pairs(invitations[player] or {}) do
		if invite.expires>t then table.insert(state.invites,{groupId=groupId,owner=invite.owner,name=invite.name,ironman=invite.ironman}) end
	end
	table.sort(state.invites,function(a,b) return a.owner<b.owner end)
	return state
end
local function refreshGroup(groupId,preview,except)
	for _,player in ipairs(Players:GetPlayers()) do
		if cachedGroup[player]==groupId and player~=except then
			local profile=eligibility(player,false)
			if profile and (profile.preview==true)==(preview==true) then
				local ok,state=pcall(snapshot,player,profile)
				if ok then changed:FireClient(player,state) end
			end
		end
	end
end
------------------------------------------------------------------------------
-- Satchel transfers (two keys, settled exactly once).
------------------------------------------------------------------------------
-- Applies one journal outbox deposit to its crew, or refunds it if the crew
-- never received it and the player is no longer a member.
local function settleDeposit(player,profile,entry)
	local userId=tostring(player.UserId)
	local outcome="refund"
	writeGroup(entry.groupId,profile.preview,function(old)
		outcome="refund"
		if not old then return nil end
		normalize(old)
		local l=old.ledger[userId]
		if l and l.seq>=entry.seq then outcome="applied"; return nil end
		if not old.members[userId] or old.ironman~=(profile.ironman==true) then return nil end
		l=ledgerOf(old,userId)
		l.seq=entry.seq
		old.supplies[entry.resource]=(old.supplies[entry.resource] or 0)+entry.amount
		l.deposited+=entry.amount
		share(old,entry.amount,userId)
		-- Only net-new deposits earn homestead XP, so cycling earns nothing.
		local net=l.deposited-l.withdrawn
		if net>l.peak then addXp(old,userId,net-l.peak); l.peak=net end
		outcome="applied"
		return old
	end)
	local done=invoke(player,false,{settle={seq=entry.seq,refund=outcome=="refund"}})
	return done and outcome or "pending"
end
local function deliver(player,profile,groupId,token,entry)
	local delivered=invoke(player,false,{credit={token=token,resource=entry.resource,amount=entry.amount}})
	if not delivered or not delivered.result or not delivered.result.ok then clean[player]=nil; return false end
	-- Removed from the crew outbox by the next write to the crew (or the flush).
	local ck=cacheKey("group_"..groupId,profile.preview)
	acked[ck]=acked[ck] or {}
	acked[ck][token]=true
	meta[ck]={groupId=groupId,preview=profile.preview}
	return true
end
local function replayWithdrawals(player,profile,groupId)
	local userId=tostring(player.UserId)
	local group=read("group_"..groupId,profile.preview)
	if not group or not group.outbox then return true end
	local tokens={}
	local ck=cacheKey("group_"..groupId,profile.preview)
	for token,entry in pairs(group.outbox) do
		if entry.userId==userId and not (acked[ck] and acked[ck][token]) then table.insert(tokens,token) end
	end
	table.sort(tokens)
	local all=true
	for _,token in ipairs(tokens) do
		if not deliver(player,profile,groupId,token,group.outbox[token]) then all=false end
	end
	return all
end
-- Heals a stale index (removed on another server or before a crash), then
-- settles any satchel transfers left half-way by a crash.
local function recover(player,profile)
	local pending=type(profile.coopOutbox)=="table" and profile.coopOutbox or {}
	table.sort(pending,function(a,b) return a.seq<b.seq end)
	for _,entry in ipairs(pending) do settleDeposit(player,profile,entry) end
	if clean[player] or os.clock()<(retryAt[player] or 0) then return end
	local userId=tostring(player.UserId)
	local indexKey="member_"..userId
	local raw=readRaw(indexKey,profile.preview)
	if raw and not raw.empty and raw.kind~="joined" then
		-- Membership committed but the final index write was lost: finish it.
		local group=read("group_"..raw.groupId,profile.preview)
		if group and not group.disbanded and (group.members or {})[userId] then
			raw=write(indexKey,profile.preview,function(old)
				if old and old.groupId==raw.groupId and not old.empty then return {groupId=old.groupId,kind="joined",token=old.token,gone=history(old)} end
				return old
			end)
		end
	end
	if raw and not raw.empty and raw.kind=="joined" then
		local group=read("group_"..raw.groupId,profile.preview)
		if not group or not (group.members or {})[userId] then
			local gone=group and group.departed and group.departed[userId]
			local healed={empty=true,left=raw.groupId,cooldownUntil=gone and gone.at+Coop.RejoinCooldown or 0,kicked=gone and gone.kicked or nil,reason=gone and gone.reason or nil}
			raw=write(indexKey,profile.preview,function(old)
				if old and old.groupId==raw.groupId and old.kind=="joined" then healed.gone=history(old,raw.groupId); return healed end
				return old
			end)
		end
	end
	-- Stays unclean while any delivery fails, so the next action retries it.
	local settled=true
	if raw and raw.groupId then settled=replayWithdrawals(player,profile,raw.groupId) end
	for _,groupId in ipairs(history(raw)) do
		if groupId~=(raw and raw.groupId) and not replayWithdrawals(player,profile,groupId) then settled=false end
	end
	clean[player]=settled or nil
	-- A delivery that keeps failing (journal cannot save) is retried at most
	-- once per MUTATE_GATE, not on every state request.
	retryAt[player]=not settled and os.clock()+MUTATE_GATE or nil
end
------------------------------------------------------------------------------
-- Membership.
------------------------------------------------------------------------------
local function join(player,profile,groupId,creating,inviteToken)
	local userId=tostring(player.UserId)
	local indexKey="member_"..userId
	-- Reserve the unique user index before group membership. An ambiguous write
	-- leaves the reservation intact; repeating accept/create recovers it safely.
	-- An empty index still carrying a rejoin cooldown cannot be reserved.
	local t=os.time()
	local reservation=write(indexKey,profile.preview,function(old)
		if old and not old.empty then return old end
		if old and (old.cooldownUntil or 0)>t then return nil end
		return {groupId=groupId,kind=creating and "create" or "accept",token=inviteToken or "founder",gone=history(old)}
	end)
	if not reservation then return "Your rejoin cooldown is still running." end
	if reservation.groupId~=groupId then return "You already belong to, or are joining, another homestead." end
	local group=writeGroup(groupId,profile.preview,function(old)
		if not old or old.disbanded then
			if not creating or not founded(groupId,userId) then return nil end
			-- A reused key starts fresh but keeps each user's applied deposit
			-- sequence, so a late journal outbox replay is never applied twice.
			local ledger={}
			for ledgerId,l in pairs(old and old.ledger or {}) do ledger[ledgerId]={gathered=0,deposited=0,withdrawn=0,built=0,worker=0,peak=0,points=0,seq=l.seq or 0} end
			-- Undelivered withdrawals of the disbanded crew stay deliverable.
			old={owner=player.UserId,ironman=profile.ironman==true,members={},invites={},supplies={},decorations={},
				ledger=ledger,generation=old and (old.generation or 1)+1 or 1,outbox=old and old.outbox or {}}
		end
		normalize(old)
		if old.ironman~=(profile.ironman==true) then return nil end
		if old.members[userId] then return old end
		if count(old.members)>=Coop.MaxMembers then return nil end
		if not creating then
			local invite=old.invites[userId]
			if not invite or invite.token~=reservation.token or invite.expires<=os.time() then return nil end
		elseif tostring(old.owner)~=userId then return nil end
		old.members[userId]=player.DisplayName or player.Name or userId
		old.joined[userId]=os.time()
		old.invites[userId]=nil
		old.departed[userId]=nil
		ledgerOf(old,userId).name=old.members[userId]
		note(old,old.members[userId]..(creating and " founded the crew." or " joined the crew."))
		return old
	end)
	if not group then
		-- Revoke this exact invitation atomically before clearing the index.
		-- A delayed join using its old token can no longer add an orphan member.
		local cancelled=writeGroup(groupId,profile.preview,function(old)
			if not old then return nil end
			if not (old.members or {})[userId] and old.invites and old.invites[userId] and old.invites[userId].token==reservation.token then old.invites[userId]=nil end
			return old
		end)
		if not (cancelled and (cancelled.members or {})[userId]) then
			write(indexKey,profile.preview,function(old)
				if old and old.groupId==groupId and old.token==reservation.token and old.kind~="joined" then return {empty=true,gone=history(old)} end
				return old
			end)
		end
		return "Invitation unavailable, homestead full or modes differ. Ask for a new invitation or choose another homestead."
	end
	write(indexKey,profile.preview,function(old)
		if old and old.groupId==groupId then return {groupId=groupId,kind="joined",token=old.token,gone=history(old)} end
		return old
	end)
	if invitations[player] then invitations[player][groupId]=nil end
	publish(player,group,groupId,profile)
	refreshGroup(groupId,profile.preview,player)
	return creating and "Shared homestead founded. Invite up to three friends." or "You joined the shared homestead."
end
-- Moves an index from "joined" to empty with the departure's cooldown.
local function release(userId,profile,groupId,group)
	local gone=group.departed[userId]
	write("member_"..userId,profile.preview,function(old)
		if old and not old.empty and old.groupId==groupId and old.kind=="joined" then
			return {empty=true,left=groupId,gone=history(old,groupId),cooldownUntil=(gone and gone.at or os.time())+Coop.RejoinCooldown,kicked=gone and gone.kicked or nil,reason=gone and gone.reason or nil}
		end
		return old
	end)
end
local function notifyRemoved(targetId,groupId,reason)
	local target=Players:GetPlayerByUserId(tonumber(targetId))
	if not target or cachedGroup[target]~=groupId then return end
	local profile=eligibility(target,false)
	local ok,state=pcall(snapshot,target,profile,"You were removed from the crew: "..reason..". Your own journal and island are unchanged.")
	if ok then changed:FireClient(target,state) end
end
local function perform(player,profile,verb,arg,extra)
	local userId=tostring(player.UserId)
	if verb=="create" or verb=="accept" then
		local raw=readRaw("member_"..userId,profile.preview)
		local pending=raw and not raw.empty and raw or nil
		if pending and pending.kind~="joined" then
			profile=eligibility(player,true)
			if not profile then return "Your journal must save before joining." end
			return join(player,profile,pending.groupId,pending.kind=="create",pending.token)
		end
		if pending then return "You already belong to a homestead." end
		if raw and (raw.cooldownUntil or 0)>os.time() then return "You can join or found another crew in "..span(raw.cooldownUntil-os.time())..". The cooldown prevents crew hopping." end
		local groupId
		if verb=="create" then
			for generation=1,99 do
				local candidate=generation==1 and userId or userId.."-"..generation
				local existing=read("group_"..candidate,profile.preview)
				if not existing or existing.disbanded then groupId=candidate; break end
			end
			if not groupId then return "No homestead charter is available." end
		else groupId=id(arg) end
		if not groupId then return "Choose a valid invitation." end
		local inviteToken
		if verb=="accept" then
			local group=read("group_"..groupId,profile.preview)
			local invite=group and group.invites and group.invites[userId]
			if not group or group.disbanded or group.ironman~=(profile.ironman==true) or not invite or invite.expires<=os.time() then return "An active invitation from the same game mode is required." end
			inviteToken=invite.token
		end
		profile=eligibility(player,true)
		if not profile then return "Your journal must save before joining." end
		return join(player,profile,groupId,verb=="create",inviteToken)
	end
	local index=read("member_"..userId,profile.preview)
	if not index or index.kind~="joined" then return "Create a homestead or accept an invitation first." end
	local groupId=index.groupId
	local key="group_"..groupId
	local reason
	-- Common guard: caller is a current member of a live crew in the same mode.
	local function member(old)
		if not old or old.disbanded then return nil end
		normalize(old)
		if not old.members[userId] or old.ironman~=(profile.ironman==true) then return nil end
		return old
	end
	local function leader(old)
		old=member(old)
		if old and tostring(old.owner)~=userId then reason="Only the crew leader can do that."; return nil end
		return old
	end
	if verb=="invite" then
		local targetId=id(arg)
		local target=targetId and Players:GetPlayerByUserId(tonumber(targetId))
		local targetProfile=target and eligibility(target,false)
		if not targetProfile or target==player then return "Choose another player in this server." end
		if targetProfile.ironman~=profile.ironman or targetProfile.preview~=profile.preview then return "Homestead members must use the same game mode and save environment." end
		local targetIndex=readRaw("member_"..targetId,profile.preview)
		if targetIndex and targetIndex.empty and (targetIndex.cooldownUntil or 0)>os.time() then return "That voyager left a crew recently and can join again in "..span(targetIndex.cooldownUntil-os.time()).."." end
		local expires=os.time()+Coop.InviteSeconds
		local token=HttpService:GenerateGUID(false)
		local group=writeGroup(groupId,profile.preview,function(old)
			old=leader(old)
			if not old then return nil end
			if count(old.members)>=Coop.MaxMembers or old.members[targetId] then return nil end
			old.invites[targetId]={expires=expires,token=token,name=target.DisplayName or target.Name}
			return old
		end)
		if not group then return "Only the crew leader can invite, and the homestead needs an open place." end
		invitations[target]=invitations[target] or {}
		invitations[target][groupId]={expires=expires,owner=player.UserId,name=player.DisplayName or player.Name or userId,ironman=profile.ironman}
		changed:FireClient(target,snapshot(target,targetProfile,"Homestead invitation received. Accept explicitly to join."))
		return "Invitation sent for "..span(Coop.InviteSeconds)..". The leader can revoke it until it is accepted."
	elseif verb=="revoke" then
		local targetId=id(arg)
		if not targetId then return "Choose an invitation to revoke." end
		local group=writeGroup(groupId,profile.preview,function(old)
			old=leader(old)
			if not old then return nil end
			old.invites[targetId]=nil
			return old
		end)
		if not group then return reason or "Only the crew leader can revoke invitations." end
		local target=Players:GetPlayerByUserId(tonumber(targetId))
		if target and invitations[target] then invitations[target][groupId]=nil end
		return "Invitation revoked."
	elseif verb=="leave" then
		if arg~="confirm" then return "Confirm before leaving the crew." end
		local group=writeGroup(groupId,profile.preview,function(old)
			if not old then return nil end
			normalize(old)
			if old.members[userId] then
				local name=old.members[userId]
				depart(old,userId,false,nil,nil)
				note(old,name.." left the crew.")
			end
			return old
		end)
		if not group then return "That homestead record is unavailable." end
		release(userId,profile,groupId,group)
		publish(player,nil,nil,profile)
		if not group.disbanded then refreshGroup(groupId,profile.preview,player) end
		return (group.disbanded and "The crew disbanded. " or "You left the crew; your contributions stay with it. ")..
			"You can join or found another crew in "..span(Coop.RejoinCooldown).."."
	elseif verb=="kick" then
		local targetId=id(arg)
		local text=type(extra)=="string" and kickReasons[extra]
		if not targetId or targetId==userId then return "Choose another crew member." end
		if not text then return "Choose a reason before removing a crew member." end
		local name
		local group=writeGroup(groupId,profile.preview,function(old)
			reason=nil
			old=leader(old)
			if not old then return nil end
			if not old.members[targetId] then
				-- A replay after a lost acknowledgement finds the removal done.
				local gone=old.departed[targetId]
				if gone and gone.kicked and gone.by==userId then name=nameOf(old,targetId); return old end
				reason="That voyager is not in this crew."; return nil
			end
			name=old.members[targetId]
			depart(old,targetId,true,extra,userId)
			note(old,name.." was removed by "..old.members[userId].." ("..text..").")
			return old
		end)
		if not group then return reason or "Only the crew leader can remove members." end
		release(targetId,profile,groupId,group)
		notifyRemoved(targetId,groupId,text)
		refreshGroup(groupId,profile.preview,player)
		return (name or "The voyager").." was removed. Their own journal, satchel and island are untouched."
	elseif verb=="transfer" then
		local targetId=id(arg)
		if extra~="confirm" then return "Confirm before passing leadership." end
		if not targetId then return "Choose a crew member." end
		local group=writeGroup(groupId,profile.preview,function(old)
			reason=nil
			old=member(old)
			if not old then return nil end
			if tostring(old.owner)==targetId and old.members[targetId] then return old end
			if tostring(old.owner)~=userId then reason="Only the crew leader can pass leadership."; return nil end
			if not old.members[targetId] then reason="Leadership can only pass to a current member."; return nil end
			old.owner=tonumber(targetId)
			note(old,old.members[userId].." passed leadership to "..old.members[targetId]..".")
			return old
		end)
		if not group then return reason or "Leadership unavailable." end
		refreshGroup(groupId,profile.preview,player)
		return group.members[targetId].." now leads the crew."
	elseif verb=="build" and costs[arg] then
		local group=writeGroup(groupId,profile.preview,function(old)
			old=member(old)
			if not old then return nil end
			if old.decorations[arg] then return old end
			for resource,amount in pairs(costs[arg]) do if (old.supplies[resource] or 0)<amount then return nil end end
			local spent=0
			for resource,amount in pairs(costs[arg]) do spend(old,resource,amount); spent+=amount end
			old.decorations[arg]=true
			ledgerOf(old,userId).built+=spent
			addXp(old,userId,spent*Coop.ConstructionXp)
			note(old,old.members[userId].." built the "..arg..".")
			return old
		end)
		if not group then return "Gather the required shared supplies on your homestead." end
		refreshGroup(groupId,profile.preview,player)
		return arg.." is built for every homestead member."
	elseif verb=="deposit" or verb=="withdraw" then
		local resource=supplyKinds[arg] and arg
		local amount=tonumber(extra)
		if not resource then return "Choose Timber, Ore, Herb or Fish." end
		if not amount or amount%1~=0 or amount<1 or amount>Coop.TransferMax then return "Move between 1 and "..Coop.TransferMax.." at a time." end
		local group=read(key,profile.preview)
		if not member(group) then return "Homestead membership unavailable." end
		if verb=="deposit" then
			local _,def=levelOf(group)
			if (group.supplies[resource] or 0)+amount>def.storage then return "Shared "..resource.." storage is full ("..def.storage.."). Level the homestead for more room." end
			local debit=invoke(player,false,{deposit={resource=resource,amount=amount,groupId=groupId}})
			local entry=debit and debit.result
			if not entry or not entry.ok then return "You need "..amount.." "..resource.." in your satchel, and your journal must save." end
			local outcome=settleDeposit(player,profile,{seq=entry.seq,resource=resource,amount=amount,groupId=groupId})
			if outcome=="refund" then return "The crew could not accept that deposit; it was returned to your satchel." end
			refreshGroup(groupId,profile.preview,player)
			return "Deposited "..amount.." "..resource.." into the shared stores."
		end
		local token=HttpService:GenerateGUID(false)
		local entry={userId=userId,resource=resource,amount=amount,at=os.time()}
		local committed=writeGroup(groupId,profile.preview,function(old)
			reason=nil
			old=member(old)
			if not old then return nil end
			local free=(old.supplies[resource] or 0)-(old.bound[resource] or 0)
			if free<amount then
				reason="The shared stores hold "..math.max(0,free).." withdrawable "..resource..". Supply-node gathers are for building only."
				return nil
			end
			if allowance(old,userId)<amount then
				reason="You can withdraw "..allowance(old,userId).." more: your own deposits plus your share of crew deposits and worker output."
				return nil
			end
			old.supplies[resource]-=amount
			local l=ledgerOf(old,userId); l.withdrawn+=amount
			old.outbox[token]=entry
			return old
		end)
		if not committed then return reason or "The shared stores do not hold "..amount.." "..resource.."." end
		refreshGroup(groupId,profile.preview,player)
		if not deliver(player,profile,groupId,token,entry) then return "Withdrawal recorded; it arrives in your satchel once your journal saves." end
		return "Withdrew "..amount.." "..resource.." to your satchel."
	elseif verb=="assign" then
		local slot=tonumber(arg)
		local resource=supplyKinds[extra] and extra
		if not resource then return "Choose Timber, Ore, Herb or Fish." end
		local claimed=0
		local group=writeGroup(groupId,profile.preview,function(old)
			reason=nil
			old=member(old)
			if not old then return nil end
			local _,def=levelOf(old)
			if not slot or slot%1~=0 or slot<1 or slot>def.workers then reason="Level the homestead to unlock that shared worker."; return nil end
			local w=old.workers[slot]
			if w and w.resource==resource then return old end
			claimed=0
			if w then claimed=claimWorker(old,w,userId); w.resource=resource; w.lastClaim=os.time()
			else old.workers[slot]={resource=resource,tier=1,lastClaim=os.time()} end
			old.workers[slot].by=userId
			note(old,old.members[userId].." set shared worker "..slot.." to "..resource..".")
			return old
		end)
		if not group then return reason or "Homestead membership unavailable." end
		refreshGroup(groupId,profile.preview,player)
		return "Shared worker "..slot.." now gathers "..resource.."."..(claimed>0 and " Collected "..claimed.." first." or "")
	elseif verb=="upgrade" then
		local slot=tonumber(arg)
		local group=writeGroup(groupId,profile.preview,function(old)
			reason=nil
			old=member(old)
			if not old then return nil end
			local _,def=levelOf(old)
			local w=slot and old.workers[slot]
			if not w or slot>def.workers then reason="Assign that shared worker first."; return nil end
			if w.tier>=def.workerTier then reason="Level the homestead to raise this worker further."; return nil end
			for resource,amount in pairs(Coop.WorkerUpgradeCost) do
				if (old.supplies[resource] or 0)<amount*w.tier then reason="The shared stores need more Timber and Ore."; return nil end
			end
			claimWorker(old,w,userId)
			local spent=0
			for resource,amount in pairs(Coop.WorkerUpgradeCost) do spend(old,resource,amount*w.tier); spent+=amount*w.tier end
			ledgerOf(old,userId).built+=spent
			addXp(old,userId,spent*Coop.ConstructionXp)
			w.tier+=1
			note(old,old.members[userId].." raised shared worker "..slot.." to tier "..w.tier..".")
			return old
		end)
		if not group then return reason or "Homestead membership unavailable." end
		refreshGroup(groupId,profile.preview,player)
		return "Shared worker "..slot.." is now tier "..group.workers[slot].tier.."."
	elseif verb=="claim" then
		local total=0
		local group=writeGroup(groupId,profile.preview,function(old)
			old=member(old)
			if not old then return nil end
			total=0
			local _,def=levelOf(old)
			for slot=1,def.workers do
				local w=old.workers[slot]
				if w then total+=claimWorker(old,w,userId) end
			end
			return old
		end)
		if not group then return "Homestead membership unavailable." end
		refreshGroup(groupId,profile.preview,player)
		return total>0 and "Collected "..total.." from the shared workers into the shared stores." or "Nothing ready (or the shared stores are full)."
	end
	return "Unknown homestead action."
end
-- A player whose co-op state cannot be confirmed (store missing, reads
-- failing) must not keep a crew perk from an old session or a removal made
-- elsewhere: clear it until a snapshot confirms membership again.
local function dropPerk(player)
	if perkSig[player]=="" then return end
	if invoke(player,false,{perk=false}) then perkSig[player]="" end
end
action.OnServerInvoke=function(player,verb,arg,extra)
	if type(verb)~="string" or (arg~=nil and type(arg)~="string") or (extra~=nil and (type(extra)~="string" or #extra>40)) then return nil end
	local now=os.clock()
	if busy[player] or now<(lastRequest[player] or 0) then return nil end
	if verb~="state" then
		local wait=(lastMutate[player] or 0)-now
		if wait>0 then return {busy=true,message="One homestead change every "..MUTATE_GATE.." seconds. Try again in "..math.ceil(wait).."s."} end
		lastMutate[player]=now+MUTATE_GATE
	end
	lastRequest[player]=now+READ_GATE
	local profile=eligibility(player,false)
	if not profile then return {loading=true,message="Waiting for your journal."} end
	busy[player]=true
	local ok,state=pcall(function()
		recover(player,profile)
		profile=eligibility(player,false) or profile
		local message=verb=="state" and "" or perform(player,profile,verb,arg,extra)
		local state=snapshot(player,profile,message)
		if clean[player] or verb~="state" then return state end
		-- The snapshot found a half-finished change: heal it now, once.
		recover(player,profile)
		return snapshot(player,profile,message)
	end)
	busy[player]=nil
	if not ok then
		clean[player]=nil
		dropPerk(player)
		return {unavailable=true,message="Homestead save delayed. Retry the same action to recover safely."}
	end
	return state
end
action.Parent=ReplicatedStorage
-- Shared supplies (§42, owner decision: no hold prompt): the Crew Haven stores
-- are struck nodes. server.server.lua's Strike path validates the strike itself
-- (reach, cadence, token bucket, HP) and, on the break, invokes
-- ServerStorage.IsleCoopStrike:
--   Invoke("check", player, node)  -> ok, message (no side effects; before any damage)
--   Invoke("credit", player, node) -> ok, message, regrowth seconds
-- The credit is the retired supply prompt's, unchanged: +1 to the crew store,
-- batched in memory (no DataStore write), PROMPT_REGROW per member and node,
-- PROMPT_HOURLY per member per UTC hour, the storage cap, membership and the
-- preview / Ironman environment. No personal resource is granted.
local CREW_REACH=13 -- defence in depth: the old prompt's 10 studs + 3
local function supplyCheck(player,node,commit)
	local resource=node:GetAttribute("IsleCoopResource")
	if not resources[resource] or not node:IsDescendantOf(workspace) then return false,"That is not a crew store." end
	local now=os.clock()
	if busy[player] or (commit and now<(lastPrompt[player] or 0)) then return false,"One moment…" end
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health<=0 or not root or (root.Position-node.Position).Magnitude>CREW_REACH then return false,"Move closer to the crew store." end
	local profile=eligibility(player,false)
	if not profile then return false,"Waiting for your journal." end
	if (node:GetAttribute("CoopPreview")==true)~=(profile.preview==true) then return false,"This is another group's homestead." end
	if commit then lastPrompt[player]=now+1 end
	busy[player]=true
	local ok,granted,message,state=pcall(function()
		local groupId=id(node:GetAttribute("CoopId"))
		local userId=tostring(player.UserId)
		local index=groupId and readCached("member_"..userId,profile.preview)
		local function no(text) return false,text,snapshot(player,profile,text) end
		if not index or index.empty or index.groupId~=groupId or index.kind~="joined" then return no("This is another group's homestead.") end
		local key=groupId..":"..resource
		regrow[player]=regrow[player] or {}
		local readyAt=regrow[player][key]
		if readyAt and now<readyAt then return no("This supply is regrowing ("..math.ceil(readyAt-now).."s).") end
		local group=readCached("group_"..groupId,profile.preview)
		if not group or group.disbanded or not (group.members or {})[userId] or group.ironman~=(profile.ironman==true) then return no("Homestead membership unavailable.") end
		normalize(group)
		local hour=math.floor(os.time()/3600)
		local mine=hourly[player]
		if not mine or mine.hour~=hour then
			-- Seed from the durable ledger so hopping servers cannot reset the cap.
			local l=group.ledger[userId]
			mine={hour=hour,n=l and l.promptHour==hour and l.promptCount or 0}
			hourly[player]=mine
		end
		if mine.n>=PROMPT_HOURLY then return no("You have gathered "..PROMPT_HOURLY.." shared supplies this hour. The nodes recover next hour.") end
		local ck=cacheKey("group_"..groupId,profile.preview)
		local batch=pending[ck]
		local queued=0
		if batch then for _,entry in pairs(batch.users) do queued+=entry.res[resource] or 0 end end
		local _,def=levelOf(group)
		if (group.supplies[resource] or 0)+queued>=def.storage then return no("Shared "..resource.." storage is full. Level the homestead for more room.") end
		if not commit then return true,"" end
		if not batch then batch={since=now,users={}}; pending[ck]=batch end
		meta[ck]={groupId=groupId,preview=profile.preview}
		local entry=batch.users[userId] or {ironman=profile.ironman==true,res={}}
		batch.users[userId]=entry
		entry.res[resource]=(entry.res[resource] or 0)+1
		mine.n+=1
		regrow[player][key]=now+PROMPT_REGROW
		if now-batch.since>=FLUSH_EVERY then flush(ck) end
		local text="+1 shared "..resource.." • for building and Homestead XP"
		return true,text,snapshot(player,profile,text)
	end)
	busy[player]=nil
	if not ok then dropPerk(player) return false,"Homestead save delayed. Try again." end
	if commit and state then changed:FireClient(player,state) end
	return granted,message
end
local strikeHook=Instance.new("BindableFunction")
strikeHook.Name="IsleCoopStrike"
strikeHook.OnInvoke=function(mode,player,node)
	if typeof(node)~="Instance" and type(node)~="table" then return false,"That is not a crew store." end
	if mode=="check" then return supplyCheck(player,node,false) end
	if mode=="credit" then
		local ok,message=supplyCheck(player,node,true)
		return ok,message,PROMPT_REGROW
	end
	return false,"Unknown request."
end
strikeHook.Parent=ServerStorage
Players.PlayerRemoving:Connect(function(player)
	busy[player],lastRequest[player],invitations[player],cachedGroup[player],perkSig[player],clean[player]=nil,nil,nil,nil,nil,nil
	lastMutate[player],lastPrompt[player],regrow[player],hourly[player],retryAt[player]=nil,nil,nil,nil,nil
end)
-- Shutdown: commit every pending prompt batch and outbox prune.
pcall(function() game:BindToClose(function() flushDue(true) end) end)
-- Bounded refresh also loads group attributes after the main journal has opened,
-- and picks up leave/kick/transfer changes written by other servers. Every
-- second pass (30 s) flushes all prompt batches; acks are pruned every pass.
task.spawn(function()
	local pass=0
	while task.wait(15) do
		pass+=1
		flushDue(pass%2==0)
		if budget() then
			for _,player in ipairs(Players:GetPlayers()) do
				if not busy[player] then
					local profile=eligibility(player,false)
					if profile then
						local ok,state=pcall(snapshot,player,profile)
						if ok then changed:FireClient(player,state) else dropPerk(player) end
					end
				end
			end
		end
	end
end)
