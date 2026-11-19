-- Executes the production co-op service with retry/failure-injectable storage.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local Vector3=require("@lune/roblox").Vector3
local function copy(x)
	if type(x)~="table" then return x end
	local out={}; for k,v in pairs(x) do out[k]=copy(v) end; return out
end
local function signal()
	local listeners={}
	return {Connect=function(_,f) table.insert(listeners,f) end,Fire=function(_,...) for _,f in ipairs(listeners) do f(...) end end}
end
local clock,utc,guid=100,1500000000,0
local data,objects,online={},{},{}
local loseAck,failBefore,race,failHook=nil,nil,nil,false
local db={}
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key,transform)
	if failBefore==key then failBefore=nil; error("precommit storage failure") end
	if race then local callback=race; race=nil; callback(key) end
	-- Roblox may retry transforms. Discard the speculative first result.
	transform(copy(data[key]))
	local value=transform(copy(data[key]))
	if value then data[key]=copy(value) end
	if loseAck==key then loseAck=nil; error("durable write lost acknowledgement") end
	return copy(value)
end
local workspace={}
local hook={Invoke=function(_,p,seal)
	if not p.ready or (seal and failHook) then return {ready=false} end
	if seal then p.sealed=true end
	return {ready=true,ironman=p.ironman,preview=p.preview}
end}
local services={
	Players={PlayerRemoving=signal(),GetPlayers=function() return online end,
		GetPlayerByUserId=function(_,id) for _,p in ipairs(online) do if p.UserId==id then return p end end end},
	ReplicatedStorage={},ServerStorage={FindFirstChild=function(_,name) return name=="IsleCoopProfile" and hook or nil end},
	DataStoreService={GetDataStore=function() return db end},ProximityPromptService={PromptTriggered=signal()},
	HttpService={GenerateGUID=function() guid+=1; return "invite-"..guid end},
}
luau.load(fs.readFile("coop.server.lua"),{injectGlobals=true,environment={
	game={GetService=function(_,name) return services[name] end},workspace=workspace,
	Instance={new=function(class)
		local object={FireClient=function(_,p,state) p.last=state end}; objects[class]=object; return object
	end},os={clock=function() return clock end,time=function() return utc end},
	task={spawn=function(f) assert(coroutine.resume(coroutine.create(f))) end,wait=function() coroutine.yield() end},
}})()
local function player(id,ironman,preview)
	local root={Position=Vector3.zero}
	local humanoid={Health=100}
	local p={UserId=id,Name="Player"..id,DisplayName="Player"..id,ready=true,ironman=ironman==true,preview=preview==true}
	function p:SetAttribute(name,value) self[name]=value end
	p.Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end}
	table.insert(online,p); return p
end
local function cmd(p,verb,arg)
	clock+=2; utc+=2
	return objects.RemoteFunction.OnServerInvoke(p,verb,arg)
end
local function prompt(groupId,resource,distance)
	return {Enabled=true,MaxActivationDistance=10,IsDescendantOf=function(_,parent) return parent==workspace end,
		GetAttribute=function(_,key) return ({CoopId=groupId,IsleCoopResource=resource})[key] end,
		FindFirstAncestorWhichIsA=function() return {Position=Vector3.new(distance or 0,0,0)} end}
end
local function gather(p,groupId,resource,distance)
	clock+=2; utc+=2
	services.ProximityPromptService.PromptTriggered:Fire(prompt(groupId,resource,distance),p)
	return p.last
end
local count=0
local function eq(actual,expected,label)
	assert(actual==expected,label..": expected "..tostring(expected)..", got "..tostring(actual)); count+=1
end
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
eq(cmd(b,"invite","3").message,"Only the founder can invite, and the homestead needs an open place.","nonfounder cannot invite")
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
print("PASS: "..count.." co-op persistence/membership assertions.")
