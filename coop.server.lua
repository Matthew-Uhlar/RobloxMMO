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
-- next action from that player settles the transfer exactly once.
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
local function readRaw(key,preview)
	if preview then return clone(previewData[key]) end
	if not store then error("Co-op saving unavailable") end
	return store:GetAsync(key)
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
	return store:UpdateAsync(key,transform)
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
	g.outbox=g.outbox or {}; g.log=g.log or {}; g.xp=tonumber(g.xp) or 0
	local t=os.time()
	for userId in pairs(g.members) do g.joined[userId]=g.joined[userId] or 0 end
	for userId,invite in pairs(g.invites) do if type(invite)~="table" or invite.expires<=t then g.invites[userId]=nil end end
	for userId,gone in pairs(g.departed) do if gone.at+Coop.RejoinCooldown*2<t then g.departed[userId]=nil end end
	return g
end
local function ledgerOf(g,userId)
	local l=g.ledger[userId]
	if not l then l={gathered=0,deposited=0,withdrawn=0,built=0,worker=0,peak=0,seq=0,points=0}; g.ledger[userId]=l end
	return l
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
		g.invites={}; g.workers={}; g.supplies={}
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
	end
	return amount
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
	local raw=readRaw("member_"..userId,profile.preview)
	local index=raw and not raw.empty and raw or nil
	local group=index and read("group_"..index.groupId,profile.preview)
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
	write("group_"..entry.groupId,profile.preview,function(old)
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
	write("group_"..groupId,profile.preview,function(old)
		if not old or not old.outbox or not old.outbox[token] then return nil end
		old.outbox[token]=nil
		return old
	end)
	return true
end
local function replayWithdrawals(player,profile,groupId)
	local userId=tostring(player.UserId)
	local group=read("group_"..groupId,profile.preview)
	if not group or not group.outbox then return end
	local tokens={}
	for token,entry in pairs(group.outbox) do if entry.userId==userId then table.insert(tokens,token) end end
	table.sort(tokens)
	for _,token in ipairs(tokens) do deliver(player,profile,groupId,token,group.outbox[token]) end
end
-- Heals a stale index (removed on another server or before a crash), then
-- settles any satchel transfers left half-way by a crash.
local function recover(player,profile)
	local pending=type(profile.coopOutbox)=="table" and profile.coopOutbox or {}
	table.sort(pending,function(a,b) return a.seq<b.seq end)
	for _,entry in ipairs(pending) do settleDeposit(player,profile,entry) end
	if clean[player] then return end
	local userId=tostring(player.UserId)
	local indexKey="member_"..userId
	local raw=readRaw(indexKey,profile.preview)
	if raw and not raw.empty and raw.kind~="joined" then
		-- Membership committed but the final index write was lost: finish it.
		local group=read("group_"..raw.groupId,profile.preview)
		if group and not group.disbanded and (group.members or {})[userId] then
			raw=write(indexKey,profile.preview,function(old)
				if old and old.groupId==raw.groupId and not old.empty then return {groupId=old.groupId,kind="joined",token=old.token} end
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
				if old and old.groupId==raw.groupId and old.kind=="joined" then return healed end
				return old
			end)
		end
	end
	if raw and raw.groupId then replayWithdrawals(player,profile,raw.groupId) end
	if raw and raw.left then replayWithdrawals(player,profile,raw.left) end
	clean[player]=true
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
		return {groupId=groupId,kind=creating and "create" or "accept",token=inviteToken or "founder"}
	end)
	if not reservation then return "Your rejoin cooldown is still running." end
	if reservation.groupId~=groupId then return "You already belong to, or are joining, another homestead." end
	local group=write("group_"..groupId,profile.preview,function(old)
		if not old or old.disbanded then
			if not creating or not founded(groupId,userId) then return nil end
			-- A reused key starts fresh but keeps each user's applied deposit
			-- sequence, so a late journal outbox replay is never applied twice.
			local ledger={}
			for ledgerId,l in pairs(old and old.ledger or {}) do ledger[ledgerId]={gathered=0,deposited=0,withdrawn=0,built=0,worker=0,peak=0,points=0,seq=l.seq or 0} end
			old={owner=player.UserId,ironman=profile.ironman==true,members={},invites={},supplies={},decorations={},
				ledger=ledger,generation=old and (old.generation or 1)+1 or 1}
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
		local cancelled=write("group_"..groupId,profile.preview,function(old)
			if not old then return nil end
			if not (old.members or {})[userId] and old.invites and old.invites[userId] and old.invites[userId].token==reservation.token then old.invites[userId]=nil end
			return old
		end)
		if not (cancelled and (cancelled.members or {})[userId]) then
			write(indexKey,profile.preview,function(old)
				if old and old.groupId==groupId and old.token==reservation.token and old.kind~="joined" then return {empty=true} end
				return old
			end)
		end
		return "Invitation unavailable, homestead full or modes differ. Ask for a new invitation or choose another homestead."
	end
	write(indexKey,profile.preview,function(old)
		if old and old.groupId==groupId then return {groupId=groupId,kind="joined",token=old.token} end
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
			return {empty=true,left=groupId,cooldownUntil=(gone and gone.at or os.time())+Coop.RejoinCooldown,kicked=gone and gone.kicked or nil,reason=gone and gone.reason or nil}
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
		local group=write(key,profile.preview,function(old)
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
		local group=write(key,profile.preview,function(old)
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
		local group=write(key,profile.preview,function(old)
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
		local group=write(key,profile.preview,function(old)
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
		local group=write(key,profile.preview,function(old)
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
		local group=write(key,profile.preview,function(old)
			old=member(old)
			if not old then return nil end
			if old.decorations[arg] then return old end
			for resource,amount in pairs(costs[arg]) do if (old.supplies[resource] or 0)<amount then return nil end end
			local spent=0
			for resource,amount in pairs(costs[arg]) do old.supplies[resource]-=amount; spent+=amount end
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
		local committed=write(key,profile.preview,function(old)
			old=member(old)
			if not old or (old.supplies[resource] or 0)<amount then return nil end
			old.supplies[resource]-=amount
			local l=ledgerOf(old,userId); l.withdrawn+=amount
			old.outbox[token]=entry
			return old
		end)
		if not committed then return "The shared stores do not hold "..amount.." "..resource.."." end
		refreshGroup(groupId,profile.preview,player)
		if not deliver(player,profile,groupId,token,entry) then return "Withdrawal recorded; it arrives in your satchel once your journal saves." end
		return "Withdrew "..amount.." "..resource.." to your satchel."
	elseif verb=="assign" then
		local slot=tonumber(arg)
		local resource=supplyKinds[extra] and extra
		if not resource then return "Choose Timber, Ore, Herb or Fish." end
		local claimed=0
		local group=write(key,profile.preview,function(old)
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
		local group=write(key,profile.preview,function(old)
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
			for resource,amount in pairs(Coop.WorkerUpgradeCost) do old.supplies[resource]-=amount*w.tier; spent+=amount*w.tier end
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
		local group=write(key,profile.preview,function(old)
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
action.OnServerInvoke=function(player,verb,arg,extra)
	if type(verb)~="string" or (arg~=nil and type(arg)~="string") or (extra~=nil and (type(extra)~="string" or #extra>40)) then return nil end
	if busy[player] or os.clock()<(lastRequest[player] or 0) then return nil end
	lastRequest[player]=os.clock()+0.6
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
	if not ok then clean[player]=nil; return {unavailable=true,message="Homestead save delayed. Retry the same action to recover safely."} end
	return state
end
action.Parent=ReplicatedStorage
ProximityPromptService.PromptTriggered:Connect(function(prompt,player)
	local resource=prompt:GetAttribute("IsleCoopResource")
	if not resources[resource] or not prompt.Enabled or not prompt:IsDescendantOf(workspace) then return end
	if busy[player] or os.clock()<(lastRequest[player] or 0) then return end
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local base=prompt:FindFirstAncestorWhichIsA("BasePart")
	if not humanoid or humanoid.Health<=0 or not root or not base or (root.Position-base.Position).Magnitude>prompt.MaxActivationDistance+3 then return end
	local profile=eligibility(player,false)
	if not profile then return end
	if (prompt:GetAttribute("CoopPreview")==true)~=(profile.preview==true) then return end
	lastRequest[player]=os.clock()+1
	busy[player]=true
	local ok,state=pcall(function()
		local groupId=prompt:GetAttribute("CoopId")
		local index=read("member_"..player.UserId,profile.preview)
		if not index or index.groupId~=groupId then return snapshot(player,profile,"This is another group's homestead.") end
		local userId=tostring(player.UserId)
		local full=false
		local group=write("group_"..groupId,profile.preview,function(old)
			if not old or old.disbanded or not (old.members or {})[userId] or old.ironman~=(profile.ironman==true) then return nil end
			normalize(old)
			local _,def=levelOf(old)
			full=(old.supplies[resource] or 0)>=def.storage
			if full then return nil end
			old.supplies[resource]=(old.supplies[resource] or 0)+1
			ledgerOf(old,userId).gathered+=1
			addXp(old,userId,1)
			return old
		end)
		if full then return snapshot(player,profile,"Shared "..resource.." storage is full. Level the homestead for more room.") end
		if not group then return snapshot(player,profile,"Homestead membership unavailable.") end
		return snapshot(player,profile,"+1 shared "..resource.." • homestead supply")
	end)
	busy[player]=nil
	if ok then changed:FireClient(player,state) end
end)
Players.PlayerRemoving:Connect(function(player)
	busy[player],lastRequest[player],invitations[player],cachedGroup[player],perkSig[player],clean[player]=nil,nil,nil,nil,nil,nil
end)
-- Bounded refresh also loads group attributes after the main journal has opened,
-- and picks up leave/kick/transfer changes written by other servers.
task.spawn(function()
	while task.wait(15) do
		for _,player in ipairs(Players:GetPlayers()) do
			if not busy[player] then
				local profile=eligibility(player,false)
				if profile then
					local ok,state=pcall(snapshot,player,profile)
					if ok then changed:FireClient(player,state) end
				end
			end
		end
	end
end)
