-- Shared homesteads use their own supplies. No personal inventory is transferred.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")
local DataStoreService=game:GetService("DataStoreService")
local ProximityPromptService=game:GetService("ProximityPromptService")
local HttpService=game:GetService("HttpService")
local store
pcall(function() store=DataStoreService:GetDataStore("Aether_Coop_v1") end)
local action=Instance.new("RemoteFunction")
action.Name="IsleCoopAction"
local changed=Instance.new("RemoteEvent")
changed.Name="IsleCoopUpdate"
changed.Parent=ReplicatedStorage
local busy,lastRequest,invitations,cachedGroup={},{},{},{}
local previewData={}
local costs={Garden={Herb=3,Timber=3},Lanterns={Timber=5},Deck={Timber=10,Ore=5}}
local resources={Timber=true,Ore=true,Herb=true}
local function clone(value)
	if type(value)~="table" then return value end
	local out={}; for k,v in pairs(value) do out[k]=clone(v) end; return out
end
local function eligibility(player,seal)
	local hook=ServerStorage:FindFirstChild("IsleCoopProfile")
	if not hook then return nil end
	local ok,profile=pcall(function() return hook:Invoke(player,seal==true) end)
	if not ok or type(profile)~="table" or not profile.ready then return nil end
	return profile
end
local function read(key,preview)
	if preview then local value=clone(previewData[key]); return value and not value.empty and value or nil end
	if not store then error("Co-op saving unavailable") end
	local value=store:GetAsync(key)
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
local function id(value)
	if type(value)~="string" or #value>16 or not value:match("^%d+$") then return nil end
	local n=tonumber(value)
	if not n or n<=0 or n%1~=0 then return nil end
	return tostring(n)
end
local function publish(player,group,groupId,preview)
	local member=group and group.members[tostring(player.UserId)]
	if not member then group=nil; groupId=nil end
	cachedGroup[player]=groupId
	player:SetAttribute("CoopPreview",preview==true)
	player:SetAttribute("CoopId",groupId)
	player:SetAttribute("CoopOwner",group and group.owner or nil)
	for name in pairs(costs) do player:SetAttribute("Coop"..name,group and group.decorations[name]==true or false) end
end
local function snapshot(player,profile,message)
	local index=read("member_"..player.UserId,profile.preview)
	local group=index and read("group_"..index.groupId,profile.preview)
	local member=group and group.members[tostring(player.UserId)]
	if member then publish(player,group,index.groupId,profile.preview) else publish(player,nil,nil,profile.preview) end
	local members={}
	if member then
		for userId,name in pairs(group.members) do table.insert(members,{userId=tonumber(userId),name=name}) end
		table.sort(members,function(a,b) return a.userId<b.userId end)
	end
	local invites={}
	for groupId,invite in pairs(invitations[player] or {}) do
		if invite.expires>os.time() then table.insert(invites,{groupId=groupId,owner=invite.owner,name=invite.name,ironman=invite.ironman}) end
	end
	table.sort(invites,function(a,b) return a.owner<b.owner end)
	return {groupId=member and index.groupId or nil,pendingGroup=index and not member and index.groupId or nil,
		owner=member and group.owner or nil,members=members,ironman=member and group.ironman or profile.ironman,
		supplies=member and clone(group.supplies) or {},decorations=member and clone(group.decorations) or {},
		invites=invites,preview=profile.preview==true,message=message or ""}
end
local function refreshGroup(groupId,preview)
	for _,player in ipairs(Players:GetPlayers()) do
		if cachedGroup[player]==groupId then
			local profile=eligibility(player,false)
			if profile and (profile.preview==true)==(preview==true) then
				local ok,state=pcall(snapshot,player,profile)
				if ok then changed:FireClient(player,state) end
			end
		end
	end
end
local function join(player,profile,groupId,creating,inviteToken)
	local userId=tostring(player.UserId)
	local indexKey="member_"..userId
	-- Reserve the unique user index before group membership. An ambiguous write
	-- leaves the reservation intact; repeating accept/create recovers it safely.
	local reservation=write(indexKey,profile.preview,function(old)
		if old and not old.empty then return old end
		return {groupId=groupId,kind=creating and "create" or "accept",token=inviteToken or "founder"}
	end)
	if not reservation or reservation.groupId~=groupId then return "You already belong to, or are joining, another homestead." end
	local group=write("group_"..groupId,profile.preview,function(old)
		if not old then
			if not creating or groupId~=userId then return nil end
			old={owner=player.UserId,ironman=profile.ironman==true,members={},invites={},supplies={},decorations={}}
		end
		if old.ironman~=(profile.ironman==true) then return nil end
		if old.members[userId] then return old end
		local count=0; for _ in pairs(old.members) do count+=1 end
		if count>=4 then return nil end
		if not creating then
			local invite=old.invites[userId]
			if not invite or invite.token~=reservation.token or invite.expires<=os.time() then return nil end
		elseif old.owner~=player.UserId then return nil end
		old.members[userId]=player.DisplayName or player.Name or userId
		old.invites[userId]=nil
		return old
	end)
	if not group then
		-- Revoke this exact invitation atomically before clearing the index.
		-- A delayed join using its old token can no longer add an orphan member.
		local cancelled=write("group_"..groupId,profile.preview,function(old)
			if not old then return nil end
			if not old.members[userId] and old.invites[userId] and old.invites[userId].token==reservation.token then old.invites[userId]=nil end
			return old
		end)
		if cancelled and not cancelled.members[userId] and not creating then
			write(indexKey,profile.preview,function(old)
				if old and old.groupId==groupId and old.token==reservation.token then return {empty=true} end
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
	publish(player,group,groupId,profile.preview)
	refreshGroup(groupId,profile.preview)
	return creating and "Shared homestead founded. Invite up to three friends." or "You joined the shared homestead."
end
local function perform(player,profile,verb,arg)
	if verb=="create" or verb=="accept" then
		local pending=read("member_"..player.UserId,profile.preview)
		if pending and pending.kind~="joined" then
			profile=eligibility(player,true)
			if not profile then return "Your journal must save before joining." end
			return join(player,profile,pending.groupId,pending.kind=="create",pending.token)
		end
		local groupId=verb=="create" and tostring(player.UserId) or id(arg)
		if not groupId then return "Choose a valid invitation." end
		local inviteToken
		if verb=="accept" then
			local group=read("group_"..groupId,profile.preview)
			local member=group and group.members[tostring(player.UserId)]
			local invite=group and group.invites[tostring(player.UserId)]
			if not group or group.ironman~=(profile.ironman==true) or (not member and (not invite or invite.expires<=os.time())) then return "An active invitation from the same game mode is required." end
			inviteToken=invite and invite.token
		end
		profile=eligibility(player,true)
		if not profile then return "Your journal must save before joining." end
		return join(player,profile,groupId,verb=="create",inviteToken)
	end
	local index=read("member_"..player.UserId,profile.preview)
	if not index then return "Create a homestead or accept an invitation first." end
	local key="group_"..index.groupId
	if verb=="invite" then
		local targetId=id(arg)
		local target=targetId and Players:GetPlayerByUserId(tonumber(targetId))
		local targetProfile=target and eligibility(target,false)
		if not targetProfile or target==player then return "Choose another player in this server." end
		if targetProfile.ironman~=profile.ironman or targetProfile.preview~=profile.preview then return "Homestead members must use the same game mode and save environment." end
		local expires=os.time()+600
		local token=HttpService:GenerateGUID(false)
		local group=write(key,profile.preview,function(old)
			if not old or old.owner~=player.UserId or not old.members[tostring(player.UserId)] then return nil end
			local count=0; for _ in pairs(old.members) do count+=1 end
			if count>=4 or old.members[targetId] then return nil end
			old.invites[targetId]={expires=expires,token=token}
			return old
		end)
		if not group then return "Only the founder can invite, and the homestead needs an open place." end
		invitations[target]=invitations[target] or {}
		invitations[target][index.groupId]={expires=expires,owner=player.UserId,name=player.DisplayName or player.Name or tostring(player.UserId),ironman=profile.ironman}
		changed:FireClient(target,snapshot(target,targetProfile,"Homestead invitation received. Accept explicitly to join."))
		return "Invitation sent for 10 minutes. Joining is permanent in this version."
	elseif verb=="build" and costs[arg] then
		local group=write(key,profile.preview,function(old)
			if not old or not old.members[tostring(player.UserId)] or old.ironman~=(profile.ironman==true) then return nil end
			if old.decorations[arg] then return old end
			for resource,amount in pairs(costs[arg]) do if (old.supplies[resource] or 0)<amount then return nil end end
			for resource,amount in pairs(costs[arg]) do old.supplies[resource]-=amount end
			old.decorations[arg]=true
			return old
		end)
		if not group then return "Gather the required shared supplies on your homestead." end
		refreshGroup(index.groupId,profile.preview)
		return arg.." is built for every homestead member."
	end
	return "Unknown homestead action."
end
action.OnServerInvoke=function(player,verb,arg)
	if type(verb)~="string" or (arg~=nil and type(arg)~="string") then return nil end
	if busy[player] or os.clock()<(lastRequest[player] or 0) then return nil end
	lastRequest[player]=os.clock()+0.6
	local profile=eligibility(player,false)
	if not profile then return {loading=true,message="Waiting for your journal."} end
	busy[player]=true
	local ok,state=pcall(function()
		local message=verb=="state" and "" or perform(player,profile,verb,arg)
		return snapshot(player,profile,message)
	end)
	busy[player]=nil
	if not ok then return {unavailable=true,message="Homestead save delayed. Retry the same action to recover safely."} end
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
		local group=write("group_"..groupId,profile.preview,function(old)
			if not old or not old.members[tostring(player.UserId)] or old.ironman~=(profile.ironman==true) then return nil end
			old.supplies[resource]=math.min(999,(old.supplies[resource] or 0)+1)
			return old
		end)
		if not group then return snapshot(player,profile,"Homestead membership unavailable.") end
		return snapshot(player,profile,"+1 shared "..resource.." • homestead supply")
	end)
	busy[player]=nil
	if ok then changed:FireClient(player,state) end
end)
Players.PlayerRemoving:Connect(function(player)
	busy[player],lastRequest[player],invitations[player],cachedGroup[player]=nil,nil,nil,nil
end)
-- Bounded refresh also loads group attributes after the main journal has opened.
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
