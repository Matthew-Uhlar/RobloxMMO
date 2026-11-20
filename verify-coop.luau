-- Executes the production co-op service with retry/failure-injectable storage.
-- Several service instances can share one DataStore double to exercise
-- cross-server refresh; the journal hook mirrors IsleCoopProfile in
-- server.server.lua (perk slot, deposit outbox, idempotent credit) and can
-- simulate failed journal saves and server crashes (journal reverts to save).
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local Vector3=require("@lune/roblox").Vector3
local Data=luau.load(fs.readFile("shared/GameData.lua"),{debugName="GameData"})()
local Progression=luau.load(fs.readFile("shared/Progression.lua"),{debugName="Progression",environment={script=nil},injectGlobals=true})()
Progression.useData(Data)
local source=fs.readFile("coop.server.lua")
local function copy(x)
	if type(x)~="table" then return x end
	local out={}; for k,v in pairs(x) do out[k]=copy(v) end; return out
end
local function signal()
	local listeners={}
	return {Connect=function(_,f) table.insert(listeners,f) end,Fire=function(_,...) for _,f in ipairs(listeners) do f(...) end end}
end
local clock,utc,guid=100,1500000000,0
local data={}
local loseAck,failBefore,race,failHook,failPersist=nil,nil,nil,false,false
local faults={} -- {key=,kind="before"|"lose",skip=n}: nth matching write fails
local writes,reads=0,0
local db={}
function db:GetAsync(key) reads+=1; return copy(data[key]) end
function db:UpdateAsync(key,transform)
	if failBefore==key then failBefore=nil; error("precommit storage failure") end
	local fault
	for i,f in ipairs(faults) do
		if f.key==key then
			if (f.skip or 0)>0 then f.skip-=1 else fault=f; table.remove(faults,i) end
			break
		end
	end
	if fault and fault.kind=="before" then error("precommit storage failure") end
	if race then local callback=race; race=nil; callback(key) end
	-- Roblox may retry transforms. Discard the speculative first result.
	transform(copy(data[key]))
	local value=transform(copy(data[key]))
	if value then data[key]=copy(value); writes+=1 end
	if loseAck==key then loseAck=nil; error("durable write lost acknowledgement") end
	if fault and fault.kind=="lose" then error("durable write lost acknowledgement") end
	return copy(value)
end
local workspace={}
-- Journal persistence double: a successful save snapshots the journal; crash()
-- restores the last save (what a new server session would load).
local function persist(p)
	if failPersist then failPersist=false; return false end
	p.saved=copy({items=p.items,coopBox=p.coopBox,perkStats=p.perkStats})
	return true
end
local function crash(p)
	local s=p.saved or {items={},perkStats={}}
	p.items=copy(s.items); p.coopBox=copy(s.coopBox); p.perkStats=copy(s.perkStats) or {}
end
local hook={Invoke=function(_,p,seal,request)
	if not p.ready or (seal and failHook) then return {ready=false} end
	if seal then p.sealed=true end
	local box=p.coopBox or {seq=0,pending={},delivered={}}
	p.coopBox=box
	local result
	if type(request)=="table" then
		if request.perk~=nil then
			p.perkStats.coop=type(request.perk)=="table" and copy(request.perk) or nil
			p.perkCalls+=1
		end
		local d,s,c=request.deposit,request.settle,request.credit
		if type(d)=="table" then
			if (p.items[d.resource] or 0)<d.amount then result={ok=false} else
				box.seq+=1
				local key=tostring(box.seq)
				p.items[d.resource]-=d.amount
				box.pending[key]={seq=box.seq,resource=d.resource,amount=d.amount,groupId=d.groupId}
				if persist(p) then result={ok=true,seq=box.seq} else
					p.items[d.resource]+=d.amount; box.pending[key]=nil; result={ok=false}
				end
			end
		elseif type(s)=="table" then
			local entry=box.pending[tostring(s.seq)]
			if entry and s.refund then p.items[entry.resource]=(p.items[entry.resource] or 0)+entry.amount end
			box.pending[tostring(s.seq)]=nil
			result={ok=true}
		elseif type(c)=="table" then
			if table.find(box.delivered,c.token) then result={ok=true} else
				p.items[c.resource]=(p.items[c.resource] or 0)+c.amount
				table.insert(box.delivered,c.token)
				if persist(p) then result={ok=true} else
					p.items[c.resource]-=c.amount; table.remove(box.delivered,#box.delivered); result={ok=false}
				end
			end
		end
	end
	local outbox={}
	for _,entry in pairs(box.pending) do table.insert(outbox,copy(entry)) end
	return {ready=true,ironman=p.ironman,preview=p.preview,coopOutbox=outbox,result=result}
end}
-- One co-op service instance per simulated game server.
local function server()
	local srv={online={},objects={}}
	local services={
		Players={PlayerRemoving=signal(),GetPlayers=function() return srv.online end,
			GetPlayerByUserId=function(_,id) for _,p in ipairs(srv.online) do if p.UserId==id then return p end end end},
		ReplicatedStorage={WaitForChild=function() return "AetherData" end},
		ServerStorage={FindFirstChild=function(_,name) return name=="IsleCoopProfile" and hook or nil end},
		DataStoreService={GetDataStore=function() return db end},ProximityPromptService={PromptTriggered=signal()},
		HttpService={GenerateGUID=function() guid+=1; return "invite-"..guid end},
	}
	srv.services=services
	luau.load(source,{injectGlobals=true,environment={
		game={GetService=function(_,name) return services[name] end},workspace=workspace,
		require=function() return Data end,
		Instance={new=function(class)
			local object={FireClient=function(_,p,state) p.last=state end}; srv.objects[class]=object; return object
		end},os={clock=function() return clock end,time=function() return utc end},
		task={spawn=function(f) srv.loop=coroutine.create(f); assert(coroutine.resume(srv.loop)) end,wait=function() return coroutine.yield() end},
	}})()
	-- One pass of the 15 s refresh loop (other servers' writes become visible).
	function srv.refresh() clock+=15; utc+=15; assert(coroutine.resume(srv.loop,15)) end
	return srv
end
local main=server()
local objects,services,online=main.objects,main.services,main.online
local function player(id,ironman,preview,srv)
	srv=srv or main
	local root={Position=Vector3.zero}
	local humanoid={Health=100}
	local p={UserId=id,Name="Player"..id,DisplayName="Player"..id,ready=true,ironman=ironman==true,preview=preview==true,
		items={},perkStats={},perkCalls=0,server=srv}
	function p:SetAttribute(name,value) self[name]=value end
	p.Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end}
	table.insert(srv.online,p); return p
end
local function cmd(p,verb,arg,extra)
	clock+=2; utc+=2
	return p.server.objects.RemoteFunction.OnServerInvoke(p,verb,arg,extra)
end
local function prompt(groupId,resource,distance)
	return {Enabled=true,MaxActivationDistance=10,IsDescendantOf=function(_,parent) return parent==workspace end,
		GetAttribute=function(_,key) return ({CoopId=groupId,IsleCoopResource=resource})[key] end,
		FindFirstAncestorWhichIsA=function() return {Position=Vector3.new(distance or 0,0,0)} end}
end
local function gather(p,groupId,resource,distance)
	clock+=2; utc+=2
	p.server.services.ProximityPromptService.PromptTriggered:Fire(prompt(groupId,resource,distance),p)
	return p.last
end
local count=0
local function eq(actual,expected,label)
	assert(actual==expected,label..": expected "..tostring(expected)..", got "..tostring(actual)); count+=1
end
local function check(cond,label) assert(cond,label); count+=1 end
local a,b,c,d,e=player(1),player(2),player(3),player(4),player(5)
eq(cmd(a,"state").groupId,nil,"new player has no group")
failHook=true
eq(cmd(a,"create").groupId,nil,"failed mode lock denies group creation")
failHook=false
eq(cmd(a,"create").groupId,"1","founder creates group")
eq(a.sealed,true,"joining locks personal mode")
eq(a.CoopId,"1","group attribute published")
eq(#cmd(a,"create").members,1,"repeated create cannot duplicate member")
eq(cmd(b,"accept","1").groupId,nil,"acceptance requires invitation")
cmd(a,"invite","2")
eq(cmd(b,"state").invites[1].groupId,"1","explicit invitation exposed")
eq(cmd(b,"state").groupId,nil,"invitation does not autojoin")
eq(cmd(b,"accept","1").groupId,"1","explicit acceptance joins")
eq(#cmd(a,"state").members,2,"founder sees joined member")
eq(cmd(b,"create").groupId,"1","member cannot join second group")
-- Intentional change: invitations belong to the crew leader role (transferable).
eq(cmd(b,"invite","3").message,"Only the crew leader can invite, and the homestead needs an open place.","nonleader cannot invite")
local iron=player(6,true)
eq(cmd(a,"invite","6").message,"Homestead members must use the same game mode and save environment.","Ironman mode isolation")
eq(cmd(iron,"accept","1").groupId,nil,"forged mode acceptance denied")
eq(cmd(b,"gather","Timber").supplies.Timber,nil,"remote gather denied")
gather(c,"1","Timber")
eq(cmd(a,"state").supplies.Timber,nil,"nonmember cannot contribute")
gather(b,"1","Timber",100)
eq(cmd(a,"state").supplies.Timber,nil,"distant gather denied")
b.Character:FindFirstChildOfClass("Humanoid").Health=0
gather(b,"1","Timber")
eq(cmd(a,"state").supplies.Timber,nil,"dead gather denied")
b.Character:FindFirstChildOfClass("Humanoid").Health=100
for _=1,5 do gather(b,"1","Timber") end
eq(cmd(a,"state").supplies.Timber,5,"shared supplies visible to founder")
eq(cmd(b,"build","Lanterns").decorations.Lanterns,true,"member builds shared upgrade")
eq(cmd(a,"state").supplies.Timber,0,"build spends shared supply")
eq(a.CoopLanterns,true,"shared build publishes other member attribute")
eq(cmd(b,"build","Lanterns").supplies.Timber,0,"repeat build cannot charge")
eq(cmd(b,"build","Deck").decorations.Deck,nil,"unfunded construction denied")
cmd(a,"invite","3")
loseAck="group_1"
eq(cmd(c,"accept","1").unavailable,true,"join lost acknowledgement reports delay")
eq(data.member_3.groupId,"1","ambiguous join retains index")
eq(cmd(c,"accept","1").groupId,"1","ambiguous join recovers")
eq(#cmd(a,"state").members,3,"join replay does not duplicate member")
cmd(a,"invite","4")
cmd(a,"invite","5")
eq(cmd(d,"accept","1").groupId,"1","fourth member accepted")
eq(cmd(e,"accept","1").groupId,nil,"full group rejects acceptance")
eq(data.member_5.empty,true,"failed full join safely releases index")
eq(cmd(e,"create").groupId,"5","failed join can choose another homestead")
local f,g=player(7),player(8)
cmd(f,"create")
cmd(f,"invite","8")
failBefore="group_7"
eq(cmd(g,"accept","7").unavailable,true,"precommit failure preserves reservation")
eq(cmd(g,"create").groupId,"7","next join request first recovers reserved group")
local h=player(9)
cmd(f,"invite","9")
loseAck="member_9"
eq(cmd(h,"accept","7").unavailable,true,"index acknowledgement loss retained")
eq(cmd(h,"accept","7").groupId,"7","index acknowledgement loss recovers")
-- An expired invitation before reservation cannot trap a new player.
local expired=player(10)
cmd(f,"invite","10")
utc+=601
eq(cmd(expired,"accept","7").groupId,nil,"expired invitation rejected")
eq(cmd(expired,"create").groupId,"10","expired invitation leaves index free")
-- Same-session preview records never enter durable data or durable groups.
local preview=player(11,false,true)
eq(cmd(preview,"create").preview,true,"preview marked explicitly")
eq(data.group_11,nil,"preview does not persist")
eq(preview.CoopPreview,true,"preview world namespace published")
gather(preview,"11","Timber")
eq(cmd(preview,"state").supplies.Timber,nil,"preview player cannot harvest durable world prompt")
eq(cmd(a,"invite","11").message,"Homestead members must use the same game mode and save environment.","preview and durable groups isolated")
local rejoined=player(2)
eq(cmd(rejoined,"state").groupId,"1","membership persists on rejoin")
eq(cmd(rejoined,"state").decorations.Lanterns,true,"shared construction persists on rejoin")
eq(objects.RemoteFunction.OnServerInvoke(a,"invite",{}),nil,"malformed action payload denied")
local legacy=count
------------------------------------------------------------------------------
-- Data contract.
------------------------------------------------------------------------------
local C=Data.Coop
eq(C.MaxMembers,4,"crews hold four")
eq(C.RejoinCooldown,86400,"rejoin cooldown is 24 hours")
local monotonic,maxWorkers=true,0
for i=2,#C.Levels do
	local prev,cur=C.Levels[i-1],C.Levels[i]
	if cur.xp<=prev.xp or cur.storage<prev.storage or cur.workerTier<prev.workerTier then monotonic=false end
	maxWorkers=math.max(maxWorkers,cur.workers)
	for stat in pairs(cur.stats) do if not Data.Stats[stat] then monotonic=false end end
end
check(monotonic,"homestead levels rise monotonically with valid perk stats")
eq(maxWorkers,2,"at most two shared workers")
eq(C.Levels[#C.Levels].workerTier<=#Data.WorkerTiers,true,"shared worker tiers exist")
eq((Data.coopLevel(0)),1,"level 1 at zero xp")
eq((Data.coopLevel(C.Levels[2].xp)),2,"level 2 threshold")
eq((Data.coopLevel(10^9)),#C.Levels,"level caps")
------------------------------------------------------------------------------
-- Shared progression: contributions, ledger and group perks.
------------------------------------------------------------------------------
local L=player(100)
L.items={Timber=60,Ore=60,Herb=10,Fish=5}
local s=cmd(L,"create")
eq(s.groupId,"100","leader founds crew")
eq(s.members[1].role,"Leader","founder holds leader role")
eq(s.level.level,1,"crew starts at homestead level 1")
eq(L.perkStats.coop,nil,"no perk at level 1")
eq(L.CoopLevel,1,"level attribute published")
for _=1,59 do gather(L,"100","Herb") end
s=cmd(L,"state")
eq(s.level.xp,59,"each shared gather earns homestead xp")
eq(s.members[1].gathered,59,"ledger counts gathers")
eq(s.members[1].points,59,"ledger counts contribution points")
eq(s.level.level,1,"below level 2 threshold")
gather(L,"100","Herb")
s=cmd(L,"state")
eq(s.level.level,2,"level 2 reached from contributions")
eq(L.perkStats.coop.health,5,"group perk written into journal perkStats.coop")
eq(L.CoopLevel,2,"level attribute updates")
eq(#s.workers,1,"level 2 unlocks one shared worker slot")
eq(s.level.storage,C.Levels[2].storage,"storage perk raises shared capacity")
local function journal(perks) return {xp={},items={},collection={},equipment={},enchants={},accessoryBag={},pets={},buffs={},bestiary={},slayerXp={},perkStats=perks} end
local base=Progression.computeStats(journal({}),utc)
local boosted=Progression.computeStats(journal({coop=L.perkStats.coop}),utc)
eq(boosted.health-base.health,5,"computeStats applies the crew perk")
local calls=L.perkCalls
cmd(L,"state")
eq(L.perkCalls,calls,"unchanged perk is not rewritten")
-- Satchel deposits and withdrawals (Group Ironman shared storage semantics).
s=cmd(L,"deposit","Timber","20")
eq(s.supplies.Timber,20,"deposit fills shared stores")
eq(L.items.Timber,40,"deposit debits the satchel")
eq(s.members[1].deposited,20,"ledger counts deposits")
eq(s.level.xp,80,"net-new deposit earns homestead xp")
eq(next(L.coopBox.pending),nil,"deposit outbox settled")
s=cmd(L,"withdraw","Timber","10")
eq(s.supplies.Timber,10,"withdraw takes from shared stores")
eq(L.items.Timber,50,"withdraw credits the satchel")
eq(s.members[1].withdrawn,10,"ledger counts withdrawals")
eq(next(data.group_100.outbox),nil,"withdraw outbox settled")
s=cmd(L,"deposit","Timber","10")
eq(s.level.xp,80,"deposit/withdraw cycling earns no xp")
eq(cmd(L,"deposit","Timber","0").supplies.Timber,20,"zero deposit rejected")
eq(cmd(L,"deposit","Timber","101").message,"Move between 1 and 100 at a time.","oversized deposit rejected")
eq(cmd(L,"deposit","Gold","1").message,"Choose Timber, Ore, Herb or Fish.","unknown resource rejected")
eq(cmd(L,"deposit","Timber","2.5").supplies.Timber,20,"fractional deposit rejected")
eq(cmd(L,"deposit","Fish","9").supplies.Fish,nil,"cannot deposit more than held")
eq(L.items.Fish,5,"failed deposit keeps satchel")
eq(cmd(L,"withdraw","Ore","1").supplies.Ore,nil,"cannot withdraw absent supply")
eq(L.items.Ore,60,"failed withdraw changes nothing")
failPersist=true
eq(cmd(L,"deposit","Timber","5").supplies.Timber,20,"unsaved journal blocks deposit")
eq(L.items.Timber,40,"unsaved deposit restored to satchel")
eq(next(L.coopBox.pending),nil,"unsaved deposit leaves no outbox")
-- Crash between journal debit and crew credit.
faults={{key="group_100",kind="before"}}
eq(cmd(L,"deposit","Timber","5").unavailable,true,"crew write failure after debit reports delay")
eq(L.items.Timber,35,"debit committed before crew credit")
check(next(L.coopBox.pending)~=nil,"debit waits in the journal outbox")
eq(data.group_100.supplies.Timber,20,"crew not yet credited")
s=cmd(L,"state")
eq(s.supplies.Timber,25,"next action settles the outbox into the crew")
eq(next(L.coopBox.pending),nil,"outbox cleared after settlement")
eq(cmd(L,"state").supplies.Timber,25,"settlement happens exactly once")
-- Lost acknowledgement on the crew credit, then the journal crashes before
-- the settle is saved: the replay must recognise the applied sequence.
faults={{key="group_100",kind="lose"}}
eq(cmd(L,"deposit","Timber","5").unavailable,true,"lost credit acknowledgement reports delay")
eq(data.group_100.supplies.Timber,30,"credit landed durably")
crash(L)
check(next(L.coopBox.pending)~=nil,"crashed journal still holds the deposit")
s=cmd(L,"state")
eq(s.supplies.Timber,30,"replayed deposit is not credited twice")
eq(next(L.coopBox.pending),nil,"replayed deposit settled")
eq(L.items.Timber,30,"satchel debited exactly once")
-- Withdrawal whose satchel save fails stays in the crew outbox until delivered.
failPersist=true
s=cmd(L,"withdraw","Timber","4")
eq(s.message,"Withdrawal recorded; it arrives in your satchel once your journal saves.","failed delivery is reported")
eq(L.items.Timber,30,"undelivered withdrawal not yet in satchel")
check(next(data.group_100.outbox)~=nil,"undelivered withdrawal kept in crew outbox")
cmd(L,"state")
eq(L.items.Timber,34,"withdrawal delivered on the next action")
eq(next(data.group_100.outbox),nil,"crew outbox cleared after delivery")
cmd(L,"state")
eq(L.items.Timber,34,"withdrawal delivered exactly once")
-- Crash after the satchel save but before the crew outbox is cleared.
faults={{key="group_100",kind="before",skip=1}}
eq(cmd(L,"withdraw","Timber","3").unavailable,true,"outbox clear failure reports delay")
eq(L.items.Timber,37,"satchel credited once")
check(next(data.group_100.outbox)~=nil,"crew outbox still lists the delivery")
cmd(L,"state")
eq(L.items.Timber,37,"token prevents a second credit")
eq(next(data.group_100.outbox),nil,"replay clears the crew outbox")
eq(cmd(L,"state").supplies.Timber,23,"shared stores debited exactly once")
------------------------------------------------------------------------------
-- Shared workers: assignment, offline accrual, claim once across servers.
------------------------------------------------------------------------------
local other=server()
local M=player(101)
cmd(L,"invite","101")
eq(cmd(M,"accept","100").groupId,"100","second member joins")
eq(M.perkStats.coop.health,5,"perk applies to every member")
-- M moves to another server (same user id, separate service instance).
table.remove(main.online,table.find(main.online,M))
M.server=other
table.insert(other.online,M)
eq(cmd(M,"assign","2","Ore").message,"Level the homestead to unlock that shared worker.","locked worker slot refused")
eq(cmd(M,"assign","1","Gold").message,"Choose Timber, Ore, Herb or Fish.","unknown worker resource refused")
s=cmd(M,"assign","1","Ore")
eq(s.workers[1].resource,"Ore","any member assigns a shared worker")
eq(s.workers[1].tier,1,"shared worker starts at tier 1")
local ore=s.supplies.Ore or 0
utc+=Data.WorkerTiers[1].interval*5
eq(cmd(L,"state").workers[1].ready,5,"worker accrues while everyone is offline")
eq(cmd(L,"claim").supplies.Ore,ore+5,"claim moves output into shared stores")
eq(cmd(M,"claim").supplies.Ore,ore+5,"second server cannot claim the same output")
utc+=Data.WorkerTiers[1].interval*3
faults={{key="group_100",kind="lose"}}
eq(cmd(M,"claim").unavailable,true,"lost claim acknowledgement reports delay")
eq(cmd(M,"claim").supplies.Ore,ore+8,"claim retry does not pay twice")
local mine
for _,m in ipairs(cmd(M,"state").members) do if m.userId==101 then mine=m end end
eq(mine.worker,3,"ledger credits the claiming member")
utc+=Data.WorkerTiers[1].interval*100000
eq(cmd(L,"state").workers[1].ready,Data.WorkerTiers[1].capacity,"offline accrual capped at worker capacity")
s=cmd(L,"claim")
eq(s.supplies.Ore,ore+8+Data.WorkerTiers[1].capacity,"capped output claimed")
eq(cmd(L,"state").workers[1].ready,0,"capacity claim resets worker")
s=cmd(L,"upgrade","1")
eq(s.workers[1].tier,2,"shared supplies upgrade worker tier")
eq(s.supplies.Ore,ore+8+Data.WorkerTiers[1].capacity-5,"upgrade spends shared ore")
eq(cmd(L,"upgrade","1").message,"Level the homestead to raise this worker further.","worker tier capped by homestead level")
eq(cmd(L,"upgrade","2").message,"Assign that shared worker first.","unassigned worker cannot upgrade")
utc+=Data.WorkerTiers[2].interval*2
s=cmd(M,"assign","1","Timber")
eq(s.workers[1].resource,"Timber","reassignment changes resource")
eq(s.message,"Shared worker 1 now gathers Timber. Collected 2 first.","reassignment claims pending output first")
-- Storage cap bounds worker output.
local before=cmd(L,"state")
data.group_100.supplies.Timber=before.level.storage-10 -- nearly full stores
local room=10
utc+=Data.WorkerTiers[2].interval*Data.WorkerTiers[2].capacity
s=cmd(L,"claim")
eq(s.supplies.Timber,before.level.storage,"worker output stops at shared storage cap")
eq(s.workers[1].ready,Data.WorkerTiers[2].capacity-room,"unclaimed output stays with the worker")
eq(cmd(L,"deposit","Timber","1").message,"Shared Timber storage is full ("..before.level.storage.."). Level the homestead for more room.","full storage refuses deposits")
-- Level 4 unlocks the second worker for the next assertions.
data.group_100.xp=C.Levels[4].xp
s=cmd(M,"assign","2","Herb")
eq(#s.workers,2,"second shared worker unlocked")
eq(s.workers[2].resource,"Herb","second shared worker assigned")
eq(s.level.stats.magicFind,1,"level 4 perk listed")
eq(M.perkStats.coop.magicFind,1,"perk refreshes when level rises")
------------------------------------------------------------------------------
-- Lifecycle: permissions, kick, transfer, leave, disband, cooldowns.
------------------------------------------------------------------------------
local N,O=player(102),player(103)
N.items={Ore=7}
cmd(L,"invite","102"); cmd(N,"accept","100")
cmd(L,"invite","103"); eq(cmd(O,"accept","100").groupId,"100","crew fills to four")
eq(#cmd(L,"state").members,4,"four members listed")
local P=player(104)
eq(cmd(L,"invite","104").message,"Only the crew leader can invite, and the homestead needs an open place.","full crew cannot invite")
eq(cmd(N,"kick","103","Inactive").message,"Only the crew leader can do that.","nonleader cannot kick")
eq(#cmd(L,"state").members,4,"denied kick changes nothing")
eq(cmd(L,"kick","103").message,"Choose a reason before removing a crew member.","kick needs a reason")
eq(cmd(L,"kick","103","Because").message,"Choose a reason before removing a crew member.","kick reason must be listed")
eq(cmd(L,"kick","100","Inactive").message,"Choose another crew member.","leader cannot kick self")
eq(cmd(L,"kick","104","Inactive").message,"That voyager is not in this crew.","cannot kick a nonmember")
eq(cmd(N,"transfer","102","confirm").message,"Only the crew leader can pass leadership.","nonleader cannot transfer")
eq(cmd(N,"revoke","104").message,"Only the crew leader can do that.","nonleader cannot revoke")
local supplies=copy(cmd(L,"state").supplies)
s=cmd(L,"kick","102","Inactive")
eq(s.message,"Player102 was removed. Their own journal, satchel and island are untouched.","leader kicks with reason")
eq(#s.members,3,"kicked member removed")
eq(N.CoopId,nil,"kicked player's attributes cleared on this server")
eq(N.last.removal.reason,"Inactive for a long time","kicked player told the reason")
eq(N.perkStats.coop,nil,"kicked player loses the crew perk")
eq(N.items.Ore,7,"kicked player's satchel untouched")
eq(data.member_102.empty,true,"kicked index released")
eq(data.member_102.cooldownUntil,data.group_100.departed["102"].at+86400,"kick starts 24 h cooldown")
eq(data.group_100.departed["102"].by,"100","kick records who removed")
eq(cmd(L,"state").supplies.Ore,supplies.Ore,"kick leaves shared supplies")
eq(cmd(N,"state").cooldownUntil,data.member_102.cooldownUntil,"cooldown shown to kicked player")
check(string.find(cmd(N,"create").message,"cooldown prevents crew hopping",1,true)~=nil,"kicked player cannot found a crew during cooldown")
eq(cmd(N,"state").groupId,nil,"cooldown create left no group")
eq(data.group_102,nil,"cooldown create wrote no group")
local other2=player(105)
cmd(other2,"create")
check(string.find(cmd(other2,"invite","102").message,"left a crew recently",1,true)~=nil,"cooldown blocks new invitations")
-- Kick replay after a lost acknowledgement is idempotent.
faults={{key="group_100",kind="lose"}}
eq(cmd(L,"kick","103","Conduct").unavailable,true,"lost kick acknowledgement reports delay")
s=cmd(L,"kick","103","Conduct")
eq(s.message,"Player103 was removed. Their own journal, satchel and island are untouched.","kick replay reports success")
eq(#s.members,2,"kick replay does not remove twice")
eq(data.member_103.empty,true,"kick replay releases index")
-- Crash between the group write and the index write heals on the player's server.
cmd(L,"invite","104")
eq(cmd(P,"accept","104").groupId,nil,"accept requires the exact group id")
eq(cmd(P,"accept","100").groupId,"100","new member joins open place")
faults={{key="member_104",kind="before"}}
eq(cmd(L,"kick","104","Stores").unavailable,true,"index write failure reports delay")
eq(data.member_104.kind,"joined","index left stale by crash")
s=cmd(P,"state")
eq(s.groupId,nil,"stale index treated as removed")
eq(data.member_104.empty,true,"player's next action heals the index")
eq(data.member_104.cooldownUntil,data.group_100.departed["104"].at+86400,"healed index keeps kick cooldown")
-- Cross-server: M on another server sees removal on refresh.
eq(M.CoopId,"100","other-server member attached")
cmd(L,"transfer","101","confirm")
other.refresh()
eq(M.last.owner,101,"other server sees leadership transfer on refresh")
eq(M.CoopOwner,101,"leader attribute refreshed cross-server")
eq(cmd(L,"invite","105").message,"Only the crew leader can invite, and the homestead needs an open place.","former leader loses invite rights")
eq(cmd(L,"transfer","100").message,"Confirm before passing leadership.","transfer needs confirmation")
eq(cmd(M,"transfer","103","confirm").message,"Leadership can only pass to a current member.","transfer only to members")
eq(cmd(M,"kick","100","Course").groupId,"100","new leader can kick")
eq(L.CoopId,"100","removal on another server waits for refresh")
main.refresh()
eq(L.CoopId,nil,"former leader removed")
eq(L.perkStats.coop,nil,"removed leader loses perk")
eq(L.items.Timber,37,"removed leader keeps personal items")
-- Remote removal while the player is on a different server.
local Q=player(106)
cmd(M,"state")
-- M (leader, server 2) invites Q on server 2.
table.remove(main.online,table.find(main.online,Q)); Q.server=other; table.insert(other.online,Q)
cmd(M,"invite","106")
eq(cmd(Q,"accept","100").groupId,"100","invite works on the leader's server")
table.remove(other.online,table.find(other.online,Q)); Q.server=main; table.insert(main.online,Q)
cmd(Q,"state")
eq(Q.CoopId,"100","Q attached on main server")
cmd(M,"kick","106","Inactive")
eq(Q.CoopId,"100","main server not yet refreshed")
main.refresh()
eq(Q.CoopId,nil,"main server sees removal on refresh")
eq(Q.perkStats.coop,nil,"refresh removes perk cross-server")
eq(Q.last.groupId,nil,"refresh pushes removed state")
-- Invitations: revocation and expiry.
local R=player(107)
table.remove(main.online,table.find(main.online,R)); R.server=other; table.insert(other.online,R)
cmd(M,"invite","107")
eq(#cmd(M,"state").outgoing,1,"leader sees pending invitation")
eq(cmd(M,"revoke","107").message,"Invitation revoked.","leader revokes invitation")
eq(#cmd(R,"state").invites,0,"revoked invitation removed from invitee")
eq(cmd(R,"accept","100").groupId,nil,"revoked invitation cannot be accepted")
eq(data.member_107,nil,"revoked acceptance reserved nothing")
cmd(M,"invite","107")
utc+=C.InviteSeconds+1
eq(#cmd(M,"state").outgoing,0,"expired invitation no longer listed")
eq(cmd(R,"accept","100").groupId,nil,"expired invitation cannot be accepted")
-- Leave: leader leaving passes leadership; contributions stay.
cmd(M,"invite","107")
eq(cmd(R,"accept","100").groupId,"100","fresh invitation accepted")
supplies=copy(cmd(M,"state").supplies)
eq(cmd(M,"leave").message,"Confirm before leaving the crew.","leave needs confirmation")
s=cmd(M,"leave","confirm")
eq(s.groupId,nil,"leader leaves")
eq(M.CoopId,nil,"leaver detached")
eq(data.group_100.owner,107,"leadership passes to the remaining member")
eq(data.member_101.cooldownUntil,utc+86400,"leaving starts 24 h cooldown")
eq(cmd(R,"state").supplies.Ore,supplies.Ore,"leaver's contributions stay with the crew")
eq(cmd(R,"state").members[1].role,"Leader","successor holds leader role")
eq(cmd(M,"accept","100").groupId,nil,"leaver cannot rejoin during cooldown")
eq(cmd(M,"leave","confirm").message,"Create a homestead or accept an invitation first.","repeat leave is harmless")
-- Leave replay after lost acknowledgements stays idempotent.
faults={{key="group_100",kind="lose"}}
eq(cmd(R,"leave","confirm").unavailable,true,"lost leave acknowledgement reports delay")
eq(data.group_100.disbanded,true,"last member leaving disbands the crew")
s=cmd(R,"leave","confirm")
eq(s.groupId,nil,"leave replay completes")
eq(data.member_107.empty,true,"leave replay releases the index")
eq(R.perkStats.coop,nil,"disbanded crew perk removed")
-- Withdraw/assign after removal are refused.
eq(cmd(R,"withdraw","Ore","1").message,"Create a homestead or accept an invitation first.","former member cannot withdraw")
-- After the cooldown the founder of a disbanded crew reuses the key.
utc+=86401
s=cmd(R,"create")
eq(s.groupId,"107","player can found a crew after cooldown")
eq(cmd(M,"create").groupId,"101","leaver founds own crew after cooldown")
-- L founded group 100 (now disbanded) and founds again on the same key.
local L2=cmd(L,"create")
eq(L2.groupId,"100","disbanded founder key reused")
eq(#L2.members,1,"reused key starts with a fresh roster")
eq(L2.supplies.Ore,nil,"disbanded supplies do not carry over")
eq(L2.level.level,1,"fresh crew starts at level 1")
eq(L2.members[1].role,"Leader","reused key leader")
eq(L2.members[1].points,0,"reused key resets the contribution ledger")
eq(data.group_100.ledger["100"].seq,L.coopBox.seq,"applied deposit sequence survives key reuse")
cmd(L,"state")
reads,writes=0,0
cmd(L,"state")
eq(reads,2,"settled member refresh costs two reads")
eq(writes,0,"settled member refresh writes nothing")
-- A founder whose original crew lives on gets a generation id.
local S1,S2=player(110),player(111)
cmd(S1,"create"); cmd(S1,"invite","111"); cmd(S2,"accept","110")
cmd(S1,"leave","confirm")
utc+=86401
s=cmd(S1,"create")
eq(s.groupId,"110-2","second crew uses a generation id")
eq(data.group_110.owner,111,"original crew keeps its new leader")
local S3=player(112)
cmd(S1,"invite","112")
eq(cmd(S3,"accept","110-2").groupId,"110-2","generation ids accepted by invitation")
eq(cmd(S3,"accept","110-02").groupId,"110-2","malformed generation id cannot be used")
------------------------------------------------------------------------------
-- Group Ironman: shared stores are the only cross-player channel.
------------------------------------------------------------------------------
local I1,I2,I3=player(200,true),player(201,true),player(202,true)
I1.items={Ore=30}
cmd(I1,"create"); cmd(I1,"invite","201"); cmd(I2,"accept","200")
eq(cmd(I2,"state").ironman,true,"Ironman crew marked")
cmd(I1,"deposit","Ore","10")
s=cmd(I2,"withdraw","Ore","6")
eq(I2.items.Ore,6,"Ironman member receives from own crew")
eq(I1.items.Ore,20,"Ironman deposit debited")
eq(cmd(I3,"withdraw","Ore","1").message,"Create a homestead or accept an invitation first.","outside Ironman cannot withdraw")
local std=player(203)
eq(cmd(I1,"invite","203").message,"Homestead members must use the same game mode and save environment.","standard player cannot join Ironman crew")
eq(cmd(std,"accept","200").groupId,nil,"standard player cannot accept Ironman crew")
-- A deposit made for a crew the player has since left is refunded, not lost.
I3.items={Herb=4}
cmd(I3,"create")
faults={{key="group_202",kind="before"}}
eq(cmd(I3,"deposit","Herb","4").unavailable,true,"deposit interrupted")
eq(I3.items.Herb,0,"interrupted deposit debited")
data.group_202.members={}; data.group_202.disbanded=true -- crew vanished meanwhile
cmd(I3,"state")
eq(I3.items.Herb,4,"orphaned deposit refunded to the satchel")
eq(next(I3.coopBox.pending),nil,"orphaned deposit cleared")
eq(objects.RemoteFunction.OnServerInvoke(I1,"kick","201",string.rep("x",41)),nil,"oversized extra payload denied")
------------------------------------------------------------------------------
-- Crew page (ui.client.lua) renders roster, level, stores, workers and every
-- confirmation against the snapshot shape this service produces.
------------------------------------------------------------------------------
local roblox = require("@lune/roblox")
local H = require("./tools/ui-harness")
local function texts(root, out)
	out = out or {}
	for _, d in ipairs(root:GetDescendants()) do
		local ok, t = pcall(function() return d.Text end)
		if ok and type(t) == "string" and t ~= "" then table.insert(out, t) end
	end
	return out
end
local crew = {
	groupId = "1", owner = 1, ironman = true, maxMembers = 4, message = "",
	members = {
		{ userId = 1, name = "Voyager", role = "Leader", points = 120, gathered = 60, deposited = 40, withdrawn = 5, built = 10, worker = 3 },
		{ userId = 2, name = "Friend", role = "Member", points = 30, gathered = 30, deposited = 0, withdrawn = 0, built = 0, worker = 0 },
	},
	supplies = { Timber = 20, Ore = 8 }, decorations = { Lanterns = true }, invites = {}, outgoing = { { userId = 9, expiresIn = 300 } },
	level = { level = 2, maxLevel = 6, xp = 120, floor = 60, nextXp = 200, storage = 400, workerSlots = 1, workerTier = 2, stats = { health = 5 },
		nextStats = { health = 10, defense = 3 }, nextStorage = 600, nextWorkers = 1 },
	workers = { { slot = 1, resource = "Ore", tier = 1, ready = 4, interval = 120, capacity = 120, maxTier = 2, upgradeCost = { Timber = 8, Ore = 5 } } },
	log = { "Friend joined the crew.", "Voyager founded the crew." },
	kickReasons = { { id = "Inactive", text = "Inactive for a long time" }, { id = "Stores", text = "Misused the shared stores" } },
	resources = { "Timber", "Ore", "Herb", "Fish" }, transferMax = 100,
}
for _, size in ipairs({ roblox.Vector2.new(1366, 768), roblox.Vector2.new(730, 303) }) do
	local ui = H.runAtlas(size, { coop = crew })
	H.press(H.find(ui.gui, "AtlasButton"))
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui.scroll, "SectionCrew"))
	local all = table.concat(texts(ui.scroll), "\n")
	check(all:find("Homestead level 2", 1, true), "level card")
	check(#ui.warnings == 0, "crew page draws without errors")
	check(all:find("Shared worker 1", 1, true), "worker card")
	check(all:find("Friend", 1, true), "roster")
	check(H.find(ui.scroll, "KickButton"), "kick button")
	H.press(H.find(ui.scroll, "KickButton"))
	all = table.concat(texts(ui.scroll), "\n")
	check(all:find("Inactive for a long time", 1, true), "kick reasons shown")
	H.press(H.find(ui.scroll, "LeaveButton"))
	all = table.concat(texts(ui.scroll), "\n")
	check(all:find("Leave this crew?", 1, true), "leave confirm")
	H.press(H.find(ui.scroll, "TransferButton"))
	all = table.concat(texts(ui.scroll), "\n")
	check(all:find("Pass leadership to Friend", 1, true), "transfer confirm")
	H.press(H.find(ui.scroll, "DepositTimber"))
	H.press(H.find(ui.scroll, "ClaimButton"))
	H.press(H.find(ui.scroll, "AssignButton"))
	check(#ui.warnings == 0, "crew confirmations draw without errors")
	-- Out-of-crew states: cooldown and removal.
	local ui2 = H.runAtlas(size, { coop = { members = {}, invites = {}, message = "", cooldownUntil = 5, cooldownText = "23h 59m", removal = { reason = "Inactive" } } })
	H.press(H.find(ui2.gui, "AtlasButton"))
	H.press(ui2.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui2.scroll, "SectionCrew"))
	all = table.concat(texts(ui2.scroll), "\n")
	check(all:find("Rejoin cooldown", 1, true), "cooldown row")
	check(all:find("Removed from your crew", 1, true), "removal row")
end
-- And with a real snapshot from this service (user 1 leads crew "1").
do
	data.group_1.xp=C.Levels[2].xp
	local real=cmd(a,"state")
	eq(real.owner,1,"real snapshot belongs to the crew leader")
	local ui=H.runAtlas(roblox.Vector2.new(1366,768),{coop=real})
	H.press(H.find(ui.gui,"AtlasButton"))
	H.press(ui.tabs:FindFirstChild("JournalButton"))
	H.press(H.find(ui.scroll,"SectionCrew"))
	local all=table.concat(texts(ui.scroll),"\n")
	check(H.find(ui.scroll,"KickButton")~=nil,"leader sees remove buttons on a real roster")
	check(all:find("Player4",1,true)~=nil,"real roster names drawn")
	check(all:find("Shared worker 1",1,true)~=nil,"real worker slot drawn")
	H.press(H.find(ui.scroll,"KickButton"))
	check(table.concat(texts(ui.scroll),"\n"):find("CHOOSE A REASON",1,true)~=nil,"real kick reasons drawn")
	check(#ui.warnings==0,"real crew snapshot draws without errors")
end
print("PASS: "..count.." co-op assertions ("..legacy.." persistence/membership, "..(count-legacy).." lifecycle/progression).")
