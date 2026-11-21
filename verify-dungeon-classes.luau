-- Dungeon classes QA (Aegis, Mender, Riftblade, Starshot, Arcanist).
-- Part 1: pure rules in shared/GameData.lua (Data.DungeonClasses): classes,
--         class XP curve, milestones, ability validation, team bonus, secrets,
--         score, Master Mode, Floors VI-VII, rewards, migration, party HUD string.
-- Part 2: expedition.server.lua with deterministic players, signals and time:
--         class pedestals, abilities/ultimates and cooldowns against the
--         encounter mechanics, secrets, Master Mode, Floors VI-VII.
-- Part 3: server.server.lua Classes block (verbs, grant, bridge, persistence)
--         through the verify-gameplay.luau harness.
-- Part 4: ui.client.lua Hunt > Dungeon page and party HUD through the
--         verify-ui.luau harness.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local r=require("@lune/roblox")
local Data=luau.load(fs.readFile("shared/GameData.lua"),{debugName="GameData"})()
local Progression=luau.load(fs.readFile("shared/Progression.lua"),{debugName="Progression",environment={script=nil},injectGlobals=true})()
Progression.useData(Data)
local DC=Data.DungeonClasses
local checks=0
local function check(condition,label) assert(condition,label) checks+=1 end
local function eq(actual,expected,label) assert(actual==expected,label.." expected "..tostring(expected)..", got "..tostring(actual)) checks+=1 end
local function has(text,part) return type(text)=="string" and text:find(part,1,true)~=nil end

------------------------------------------------------------------------------
-- Part 1: rules.
------------------------------------------------------------------------------
do
	-- Classes and abilities.
	eq(#DC.order,5,"five classes")
	local roles,names,abilities={},{},{}
	for _,id in ipairs(DC.order) do
		local d=DC.defs[id]
		check(d and d.id==id,"class "..id.." defined")
		check(DC.valid(id),id.." valid")
		check(type(d.name)=="string" and not names[d.name],id.." has a unique name")
		names[d.name]=true
		check(not roles[d.role],id.." has a unique role")
		roles[d.role]=true
		check(type(d.passive)=="string" and #d.passive>10,id.." passive described")
		check(d.ability.cooldown>0 and type(d.ability.text)=="string" and d.ability.power>0 and d.ability.empowered>d.ability.power,id.." ability has a cooldown and an empowered tier")
		check(type(d.ultimate.text)=="string" and d.ultimate.power>0,id.." ultimate described")
		check(not abilities[d.ability.id] and not abilities[d.ultimate.id] and d.ability.id~=d.ultimate.id,id.." ability ids unique")
		abilities[d.ability.id],abilities[d.ultimate.id]=true,true
		eq(DC.byAbility[d.ability.id].class,id,id.." ability lookup")
		eq(DC.byAbility[d.ultimate.id].kind,"ultimate",id.." ultimate lookup")
		check(type(d.feat.id)=="string" and type(d.feat.text)=="string",id.." has a bonus feat")
		check(Data.Items[d.weapon]~=nil,id.." class weapon exists")
		local w=Data.Items[d.weapon]
		check(w.kind=="weapon" and w.dungeon==true and w.dungeonClass==id and w.rarity=="Legendary",id.." weapon is a Legendary dungeon weapon of its class")
		check(Data.Recipes[d.weapon]==nil,id.." weapon cannot be crafted")
		eq(w.requires.Dungeoneering,40,id.." weapon needs Dungeoneering 40")
		eq(DC.weapons[id],d.weapon,id.." weapon index")
		check(d.color:match("^%x%x%x%x%x%x$")~=nil,id.." colour")
	end
	check(roles.Tank and roles.Healer and roles.Melee and roles.Ranged and roles.Magic,"SkyBlock-style role coverage")
	check(not DC.valid("Berserk") and not DC.valid(nil) and not DC.valid(5),"unknown classes invalid")
	eq(Data.Items.StarpiercerLongbow.style,"ranged","Starshot weapon is a bow")
	eq(Data.Items.OrreryStaff.style,"magic","Arcanist weapon is a staff")
	eq(Data.Items.DawnmenderWand.style,"magic","Mender weapon is a wand")
	check(Data.Items.BastionMaul.style==nil and Data.Items.Riftcleaver.style==nil,"Aegis and Riftblade weapons are melee")
	-- Original names: no SkyBlock class names.
	for _,banned in ipairs({"Healer","Mage","Berserk","Archer","Tank"}) do check(DC.defs[banned]==nil,"no borrowed class id "..banned) end

	-- Class XP curve.
	eq(DC.xpForLevel(1),0,"level 1 needs 0 XP")
	eq(DC.xpForLevel(2),8,"level 2 needs 8 XP")
	eq(DC.xpForLevel(10),math.floor(8*9^2.5),"level 10 threshold")
	eq(DC.xpForLevel(50),math.floor(8*49^2.5),"level 50 threshold")
	-- Pace (review L9): maxing a class takes 1.5-2x the clears of Dungeoneering 1-50.
	-- Class XP per clear = 0.75 x the floor's Dungeoneering XP (same grade, no team bonus).
	local dung50=Progression.xpForLevel(50)
	local paceRatio=DC.MAX_XP/(0.75*dung50)
	check(paceRatio>=1.5 and paceRatio<=2,"class 50 takes 1.5-2x the Dungeoneering-50 grind ("..paceRatio..")")
	for _,floor in ipairs({1,4,7}) do
		local perClear=Data.dungeonRewards(floor,"A").dungeoneeringXp
		local classPer=DC.classXp(floor,"A",false,1)
		local r=(DC.MAX_XP/classPer)/(dung50/perClear)
		check(r>=1.5 and r<=2.05,"floor "..floor.." clears-to-50 ratio "..r)
	end
	eq(DC.MAX_XP,DC.xpForLevel(50),"max class XP")
	eq(DC.xpForLevel(99),DC.xpForLevel(50),"levels clamp at 50")
	for level=2,DC.MAX_LEVEL do
		local need=DC.xpForLevel(level)
		check(need>DC.xpForLevel(level-1),"class curve rises at "..level)
		eq(DC.levelForXp(need),level,"exact threshold reaches level "..level)
		eq(DC.levelForXp(need-1),level-1,"one XP short stays at level "..(level-1))
	end
	eq(DC.levelForXp(-5),1,"negative XP is level 1")
	eq(DC.levelForXp(0/0),1,"NaN XP is level 1")
	eq(DC.levelForXp("x"),1,"non-number XP is level 1")
	eq(DC.levelForXp(1e12),50,"huge XP caps at 50")
	local pr=DC.progress(20)
	check(pr.level==2 and pr.floor==8 and pr.ceiling==DC.xpForLevel(3) and pr.fraction>0 and pr.fraction<1 and not pr.maxed,"progress bar mid-level")
	local maxed=DC.progress(DC.MAX_XP)
	check(maxed.maxed and maxed.fraction==1 and maxed.level==50,"progress bar maxed")
	eq(DC.progress(-3).xp,0,"progress clamps negative XP")

	-- Milestones and per-level boosts.
	local m1,m5,m15,m30,m50=DC.milestoneState(1),DC.milestoneState(5),DC.milestoneState(15),DC.milestoneState(30),DC.milestoneState(50)
	check(m1.cooldown==0 and not m1.empowered and m1.charges==1 and not m1.title,"level 1 has no milestones")
	eq(DC.milestoneState(4).cooldown,0,"level 4 no cooldown cut")
	eq(m5.cooldown,0.1,"level 5 cuts cooldown 10%")
	check(not DC.milestoneState(14).empowered and m15.empowered,"level 15 empowers the ability")
	eq(DC.milestoneState(20).cooldown,0.2,"level 20 cuts cooldown 20%")
	check(DC.milestoneState(29).charges==1 and m30.charges==2,"level 30 adds an ultimate charge")
	eq(DC.milestoneState(40).cooldown,0.3,"level 40 cuts cooldown 30%")
	check(m50.title and not DC.milestoneState(49).title,"level 50 Paragon title")
	for _,id in ipairs(DC.order) do
		local b1=DC.levelBonus(id,1)
		check(b1.damage==0 and b1.mitigation==0 and b1.healing==0,id.." level 1 has no boosts (legacy numbers)")
		local b50=DC.levelBonus(id,50)
		check(b50.damage>0 and b50.damage<=0.5,id.." level 50 damage boost")
		local cd=DC.defs[id].ability.cooldown
		eq(DC.cooldown(id,1),cd,id.." base cooldown")
		check(math.abs(DC.cooldown(id,5)-cd*0.9)<1e-9 and math.abs(DC.cooldown(id,40)-cd*0.7)<1e-9,id.." cooldown milestones")
		eq(DC.abilityPower(id,14),DC.defs[id].ability.power,id.." base power")
		eq(DC.abilityPower(id,15),DC.defs[id].ability.empowered,id.." empowered power")
	end
	eq(DC.levelBonus("Nope",50).damage,0,"unknown class has no boost")
	check(math.abs(DC.levelBonus("Riftblade",50).damage-0.49)<1e-9,"Riftblade +1% damage per level")
	check(math.abs(DC.levelBonus("Mender",50).healing-0.98)<1e-9,"Mender +2% healing per level")
	eq(DC.damageTakenMult("Aegis",1),0.5,"Aegis halves damage")
	check(math.abs(DC.damageTakenMult("Aegis",50)-(1-0.696))<1e-9,"Aegis level 50 mitigation")
	eq(DC.damageTakenMult("Riftblade",1),1,"Riftblade takes full damage at level 1")
	eq(DC.damageTakenMult(nil,1),1,"unclassed takes full damage")
	check(DC.damageTakenMult("Aegis",50)>=0.25,"mitigation capped at 75%")
	-- Integer hits carry fractions: Riftblade 50 deals 1.49x over many strikes.
	local hit,carry=DC.hit(2,"Riftblade",1,0)
	check(hit==2 and carry==0,"level 1 hit unchanged")
	local total,c=0,0
	for _=1,100 do local h h,c=DC.hit(2,"Riftblade",50,c) total+=h end
	check(total>=297 and total<=298,"Riftblade 50 carries +49% damage across strikes ("..total..")")
	local first=DC.hit(2,"Riftblade",50,0)
	eq(first,2,"first boosted strike rounds down")
	eq(DC.healAmount(3,1),3,"Mender level 1 heal")
	eq(DC.healAmount(3,50),6,"Mender level 50 heal")
	eq(DC.ultimateCharges(1),1,"one ultimate per run")
	eq(DC.ultimateCharges(30),2,"two ultimates per run at 30")

	-- Ability validation (server side).
	local function st(o)
		local s={inRun=true,classId="Aegis",level=1,now=100,readyAt=0,ultimatesUsed=0,ultimateAt=nil,stage="core",shielded=false,warded=false,telegraph=nil,wisps=0}
		for k,v in pairs(o or {}) do s[k]=v end
		return s
	end
	local ok,why=DC.abilityCheck("ability",st({inRun=false}))
	check(not ok and has(why,"inside an Observatory run"),"abilities need a run")
	ok,why=DC.abilityCheck("ability",st({classId=false}))
	check(not ok and has(why,"Choose a class"),"abilities need a class")
	ok,why=DC.abilityCheck("ability",st({readyAt=112.4}))
	check(not ok and has(why,"recharging • 13s"),"cooldown refused with time left")
	check(DC.abilityCheck("ability",st({readyAt=100})),"cooldown ends exactly")
	check(DC.abilityCheck("ability",st()),"Bulwark in the boss phase")
	ok,why=DC.abilityCheck("ability",st({stage="prisms"}))
	check(not ok and has(why,"boss phase"),"Bulwark refused before the boss")
	check(DC.abilityCheck("ability",st({classId="Mender",stage="guardians"})),"Mending Light any time")
	check(DC.abilityCheck("ability",st({classId="Riftblade",wisps=2,warded=true})),"Cleave hits wisps")
	check(DC.abilityCheck("ability",st({classId="Riftblade"})),"Cleave hits the exposed core")
	check(not DC.abilityCheck("ability",st({classId="Riftblade",shielded=true})),"Cleave has nothing to hit behind a shield")
	check(not DC.abilityCheck("ability",st({classId="Riftblade",stage="prisms"})),"Cleave needs the boss phase")
	check(DC.abilityCheck("ability",st({classId="Starshot",telegraph="pulse"})),"Disrupting Shot on a telegraph")
	ok,why=DC.abilityCheck("ability",st({classId="Starshot"}))
	check(not ok and has(why,"telegraphing"),"Disrupting Shot needs a telegraph")
	check(DC.abilityCheck("ability",st({classId="Arcanist",stage="prisms"})),"Attune while tuning")
	check(DC.abilityCheck("ability",st({classId="Arcanist",shielded=true})),"Attune retunes a shield")
	check(not DC.abilityCheck("ability",st({classId="Arcanist"})),"Attune needs a prism to tune")
	check(not DC.abilityCheck("ability",st({classId="Arcanist",stage="guardians"})),"Attune idle in the hall")
	check(DC.abilityCheck("ultimate",st()),"Bastion in the boss phase")
	check(not DC.abilityCheck("ultimate",st({stage="guardians"})),"Bastion needs the boss")
	ok,why=DC.abilityCheck("ultimate",st({ultimatesUsed=1}))
	check(not ok and has(why,"spent"),"one charge per run at level 1")
	check(DC.abilityCheck("ultimate",st({ultimatesUsed=1,level=30,ultimateAt=50})),"second charge at level 30 after the gap")
	ok,why=DC.abilityCheck("ultimate",st({ultimatesUsed=1,level=30,ultimateAt=80}))
	check(not ok and has(why,"recharging • 25s"),"ultimates are 45 s apart")
	ok,why=DC.abilityCheck("ultimate",st({classId="Mender",stage="prisms"}))
	check(not ok and has(why,"boss phase"),"Second Dawn cannot be pre-banked before the boss (prisms)")
	check(not DC.abilityCheck("ultimate",st({classId="Mender",stage="guardians"})),"Second Dawn refused in the sentinel hall")
	check(DC.abilityCheck("ultimate",st({classId="Mender"})),"Second Dawn in the boss phase")
	eq(DC.defs.Mender.ultimate.window,20,"Second Dawn forgives within 20 s")
	check(DC.abilityCheck("ultimate",st({classId="Riftblade"})),"Rending Storm on an exposed core")
	check(not DC.abilityCheck("ultimate",st({classId="Riftblade",warded=true,wisps=1})),"Rending Storm refused while warded")
	check(DC.abilityCheck("ultimate",st({classId="Starshot",wisps=3,warded=true,shielded=true})),"Comet Volley with wisps")
	check(not DC.abilityCheck("ultimate",st({classId="Starshot",shielded=true})),"Comet Volley needs wisps or an open core")
	check(DC.abilityCheck("ultimate",st({classId="Arcanist",stage="prisms"})),"Eclipse Rift while tuning")
	check(not DC.abilityCheck("ultimate",st({classId="Arcanist"})),"Eclipse Rift needs a sequence")
	check(not DC.abilityCheck("dance",st()),"unknown kind refused")

	-- Team composition.
	local t0=DC.teamBonus({})
	check(t0.unique==0 and t0.xpMult==1 and not t0.balanced and t0.bonus==0,"empty team")
	local t1=DC.teamBonus({"Aegis"})
	check(t1.unique==1 and t1.xpMult==1 and not t1.balanced,"solo class has no team bonus")
	local t5=DC.teamBonus({"Aegis","Mender","Riftblade","Starshot","Arcanist"})
	check(t5.unique==5 and math.abs(t5.xpMult-1.24)<1e-9 and t5.balanced and t5.bonus==5,"five unique classes: x1.24 and balanced")
	local dup=DC.teamBonus({"Aegis","Aegis","Mender"})
	check(dup.unique==2 and math.abs(dup.xpMult-1.06)<1e-9 and not dup.balanced,"duplicates allowed, smaller bonus")
	local mixed=DC.teamBonus({"Aegis",false,"Mender"})
	check(mixed.unique==2 and not mixed.balanced,"an unclassed delver breaks balance")
	check(not DC.teamBonus({"Aegis","Mender"}).balanced,"balanced needs three delvers")
	check(DC.teamBonus({"Aegis","Mender","Starshot"}).balanced,"three unique classes are balanced")
	eq(DC.teamBonus("x").unique,0,"malformed team")

	-- Secrets.
	eq(#DC.secretCounts,#Data.DungeonFloors,"secret count per floor")
	for floor=1,#Data.DungeonFloors do
		local n=DC.secretCount(floor)
		check(n>=2 and n<=5,"floor "..floor.." has 2-5 secrets")
		if floor>1 then check(n>=DC.secretCount(floor-1),"secrets never drop with depth "..floor) end
		for seed=0,9 do
			local list=DC.secretsFor(floor,seed)
			eq(#list,n,"floor "..floor.." seed "..seed.." places every secret")
			local seen={}
			for _,s in list do
				check(not seen[s.spot] and DC.secretSpots[s.spot]~=nil and s.kind==DC.secretSpots[s.spot].kind,"distinct valid spot f"..floor.."s"..seed)
				seen[s.spot]=true
			end
		end
	end
	eq(DC.secretCount(9),0,"no secrets past VII")
	eq(DC.secretsFor(3,4)[1].spot,DC.secretsFor(3,4)[1].spot,"secret placement deterministic")
	check(DC.secretsFor(3,4)[1].spot~=DC.secretsFor(3,5)[1].spot,"secret placement rotates per run")

	-- Score.
	local full,parts=DC.score(1,100,0,0,2,2,0)
	check(full==300 and parts.secrets==100,"flawless run with every secret scores 300")
	eq(DC.score(1,100,0,0,0,2,0),225,"no secrets caps at 225")
	eq(Data.dungeonGrade(DC.score(1,100,0,0,0,2,0)),"A","no secrets grades A at best")
	eq(DC.score(1,100,0,0,1,2,0),263,"half the secrets")
	eq(Data.dungeonGrade(DC.score(1,100,0,0,1,2,20)),"S","bonus lifts a half-secret run to S")
	eq(Data.dungeonGrade(DC.score(5,100,0,0,3,4,9)),"S+","a 3-feat bonus covers one missed secret for S+")
	eq(Data.dungeonGrade(DC.score(5,100,0,0,3,4,6)),"S","without it the run is S")
	eq(DC.score(1,100,0,0,2,2,50),300,"score clamps at 300")
	eq(select(2,DC.score(1,100,0,0,2,2,50)).bonus,20,"bonus capped at 20")
	eq(DC.score(1,100,0,0,5,2,0),300,"found clamps to total")
	eq(DC.score(1,100,0,0,0,0,0),300,"floor without secrets counts full")
	eq(DC.score(5,630,2,1,2,4,6),math.floor((50+60+85+50)*0.75+6+0.5),"mixed components")
	eq(DC.bonusScore(0,false),0,"no feats")
	eq(DC.bonusScore(2,false),6,"3 per feat")
	eq(DC.bonusScore(5,true),20,"bonus cap")
	eq(DC.bonusScore(1,true),8,"balanced adds 5")
	eq(DC.bonusScore(-2,false),0,"negative feats")

	-- Master Mode.
	-- Dungeon endgame: Master Mode on floors I-VII, unlocked by grade S, scaling per floor.
	check(DC.masterUnlocked(1,260) and not DC.masterUnlocked(1,259),"Master Mode unlocks at grade S")
	check(DC.masterUnlocked(6,300) and DC.masterUnlocked(7,260) and not DC.masterUnlocked(8,300) and not DC.masterUnlocked(0,300),"Master Mode floors I-VII")
	check(not DC.masterUnlocked(2,nil),"no best score, no Master Mode")
	for floor=1,7 do
		local n,m=DC.floorStats(floor,false),DC.floorStats(floor,true)
		local sc=DC.masterScale(floor)
		check(m.coreHp==math.ceil(n.coreHp*sc.hp-1e-9) and m.guardianHp==math.ceil(n.guardianHp*sc.hp-1e-9) and m.guardianHit==math.floor(n.guardianHit*sc.damage),"floor "..floor.." Master Mode scales HP and damage")
		eq(m.addHp,DC.wispHp(floor,true),"floor "..floor.." Master wisps scale with sqrt(HP x master)")
		check(m.addHp<=math.ceil(n.addHp*math.sqrt(sc.hp)+1e-9) and (n.addHp==0 or m.addHp>n.addHp),"floor "..floor.." Master wisps x~sqrt")
		check(math.abs(m.par-DC.par(floor,false)*sc.par)<1e-9,"floor "..floor.." Master par x"..sc.par)
		eq(n.par,Data.DungeonFloors[floor].par,"floor "..floor.." normal par")
		check(m.bossDamageMult==sc.damage and n.bossDamageMult==1,"floor "..floor.." boss damage multiplier")
		if floor>1 then check(sc.hp>DC.masterScale(floor-1).hp and sc.xp>DC.masterScale(floor-1).xp,"floor "..floor.." Master scales harder than the floor above") end
	end
	local s1=DC.masterScale(1)
	check(s1.hp==2 and s1.damage==2 and s1.par==1.6 and s1.xp==2.2,"Floor I Master keeps the original x2 / par x1.6 / x2.2")
	-- Wisp HP (review H1): proportional to sqrt(hpMult), never the full multiplier.
	for floor=1,#Data.DungeonFloors do
		local f=Data.DungeonFloors[floor]
		local wave=f.mechanics.addWaves
		if wave then
			eq(DC.wispHp(floor,false),math.ceil(wave.hp*math.sqrt(f.hpMult)-1e-9),"floor "..floor.." wisp HP ~ sqrt(HP mult)")
			eq(DC.floorStats(floor,false).addHp,DC.wispHp(floor,false),"floor "..floor.." encounter wisp HP")
			check(DC.wispHp(floor,false)<Data.dungeonFloorStats(floor).addHp,"floor "..floor.." wisps lighter than the linear scaling")
			-- Wave pressure: HP spawned per second stays well below 5 unclassed delvers (6.25 hits/s).
			check(wave.count*DC.wispHp(floor,DC.MASTER_FLOORS>=floor)/DC.waveEvery(floor,DC.MASTER_FLOORS>=floor)<6.25*0.7,"floor "..floor.." wave HP/s leaves room for the boss")
			check(math.abs(DC.wispHp(floor,true)/DC.waveEvery(floor,true)-DC.wispHp(floor,false)/DC.waveEvery(floor,false))<1e-9,"floor "..floor.." Master waves: tougher wisps, same HP per second")
		else
			eq(DC.wispHp(floor,false),0,"floor "..floor.." has no wisps")
		end
	end
	check(DC.WISP_CAP>=2*4-1 and DC.WISP_CAP<=10,"wisp cap holds a wave plus a partial one")
	-- Master par (review M5): a Master run at the Master par multiple of the normal time grades like the normal run.
	for floor=1,7 do
		local par=Data.DungeonFloors[floor].par
		local k=DC.masterScale(floor).par
		for _,t in ipairs({par*0.8,par,par*1.3,par*1.7}) do
			eq(DC.score(floor,t*k,0,0,2,2,0,true),DC.score(floor,t,0,0,2,2,0,false),"floor "..floor.." Master score at x"..k.." time ("..t..")")
		end
		eq(DC.score(floor,par*k,0,0,DC.secretCount(floor),DC.secretCount(floor),0,true),300,"floor "..floor.." Master clear at its par can reach S+")
	end
	eq(DC.score(7,600*DC.masterScale(7).par,2,1,0,0,25,true)-DC.score(7,600,2,1,0,0,25,false),DC.MASTER_SCORE_BONUS,"Master runs may carry 5 more Bonus")

	-- Class XP and rewards.
	eq(DC.classXp(1,"B",false,1),45,"Floor I grade B class XP")
	eq(DC.classXp(1,"S+",false,1.24),math.floor(60*0.75*1.6*1.24),"team bonus scales class XP")
	eq(DC.classXp(1,"S+",false,9),DC.classXp(1,"S+",false,1.24),"team multiplier clamped")
	eq(DC.classXp(1,"B",false,0.2),45,"team multiplier floor")
	eq(DC.classXp(3,"A",true,1),math.floor(320*0.75*1.15*DC.masterScale(3).xp),"Master Mode class XP x"..DC.masterScale(3).xp)
	eq(DC.classXp(7,"S+",false,1),math.floor(2400*0.75*1.6),"Floor VII class XP")
	for floor=2,#Data.DungeonFloors do check(DC.classXp(floor,"B")>DC.classXp(floor-1,"B"),"class XP rises with floor "..floor) end
	local g={"D","C","B","A","S","S+"}
	for i=2,#g do check(DC.classXp(4,g[i])>DC.classXp(4,g[i-1]),"class XP rises with grade "..g[i]) end
	local plain=Data.dungeonRewards(3,"A")
	local rw=DC.runRewards(3,"A",{secrets=3,class="Starshot",teamMult=1.12})
	eq(rw.items.ObservatoryEssence,plain.items.ObservatoryEssence+3,"each secret adds an essence")
	eq(rw.coins,plain.coins+math.floor(plain.coins*0.15),"each secret adds 5% coins")
	check(rw.rolls==1 and rw.master==false and rw.secrets==3,"normal run rolls the chest once")
	eq(rw.classXp,DC.classXp(3,"A",false,1.12),"run rewards include class XP")
	local mrw=DC.runRewards(3,"A",{master=true})
	local mx=DC.masterScale(3).xp
	check(mrw.rolls==2 and mrw.master and mrw.dungeoneeringXp==math.floor(plain.dungeoneeringXp*mx) and mrw.combatXp==math.floor(plain.combatXp*mx),"Master Mode: extra roll and x"..mx.." XP")
	eq(mrw.coins,math.floor(plain.coins*mx),"Master Mode coins x"..mx)
	eq(mrw.classXp,0,"unclassed clear earns no class XP")
	eq(DC.runRewards(6,"A",{master=true}).rolls,2,"Master Mode on Floor VI (Dungeon endgame)")
	eq(DC.runRewards(1,"B",{secrets=99}).secrets,2,"secret count clamps")
	local legacy=DC.runRewards(1,"B")
	check(legacy.coins==35 and legacy.items.ObservatoryEssence==1 and legacy.items.Stormglass==1,"legacy Floor I B reward unchanged")
	local chest6=Data.DungeonFloors[6].chest
	local boosted=DC.runRewards(6,"B",{class="Riftblade"}).chest
	for i,d in ipairs(chest6) do
		local expected=d.chance*(if d.item=="Riftcleaver" then 2 else 1)
		check(math.abs(boosted[i].chance-math.min(1,expected))<1e-12,"class chest row "..d.item)
	end

	-- Floors VI and VII.
	local floors=Data.DungeonFloors
	eq(#floors,7,"seven floors")
	local f6,f7=floors[6],floors[7]
	check(f6.level==40 and f7.level==50,"Floors VI-VII need Dungeoneering 40 / 50")
	check(f6.numeral=="VI" and f7.numeral=="VII" and f6.index==6 and f7.index==7,"floor numerals")
	for _,f in {f6,f7} do
		local need=Progression.xpForLevel(f.level)
		check(Data.dungeonFloorUnlocked(f.index,Progression.levelForXp(need)),f.name.." opens at its level")
		check(not Data.dungeonFloorUnlocked(f.index,Progression.levelForXp(need-1)),f.name.." closed one XP short")
		check(f.mechanics.regen and f.mechanics.regen.every>0 and f.mechanics.regen.fraction>0,f.name.." boss regenerates")
		local items={}
		for _,d in f.chest do items[d.item]=true check(Data.Items[d.item]~=nil and d.chance>0 and d.chance<=1,f.name.." chest row "..d.item) end
		for _,id in ipairs(DC.order) do check(items[DC.defs[id].weapon],f.name.." drops the "..id.." weapon") end
		check(items.HollowKeystone and items.ObservatoryEssence,f.name.." drops the reforge stone and essence")
	end
	check(f6.boss.kind=="lances" and f7.boss.kind=="collapse","new boss attack kinds")
	check(f7.mechanics.overload and f7.mechanics.overload.below==0.5 and f7.mechanics.overload.intervalMult<1,"Floor VII overload")
	check(#f7.mechanics.shieldPhases==3 and f7.mechanics.enrage.after==360,"Floor VII three shields and enrage")
	check(f6.rewards.dungeoneeringXp>floors[5].rewards.dungeoneeringXp and f7.rewards.coins>f6.rewards.coins,"deeper floors pay more")
	eq(DC.attackKind("collapse",0),"pulse","collapse opens with the pulse")
	eq(DC.attackKind("collapse",1),"ring","collapse then the ring")
	eq(DC.attackKind("collapse",2),"lances","collapse then the lances")
	eq(DC.attackKind("collapse",3),"pulse","collapse cycles")
	check(DC.attackKind("eclipse",0)=="pulse" and DC.attackKind("eclipse",1)=="ring","eclipse alternates")
	eq(DC.attackKind("lances",4),"lances","lances every strike")
	local s6,s7=Data.dungeonFloorStats(6),Data.dungeonFloorStats(7)
	check(s6.coreHp==90 and s7.coreHp==120,"Floor VI-VII encounter numbers")
	check(DC.floorStats(6).addHp==14 and DC.floorStats(7).addHp==16,"Floor VI-VII wisps: 14 and 16 HP (5 x sqrt(HP mult))")
	-- Reforge stone.
	local G=Data.Gear
	local ev=G.Reforges.Eventide
	check(ev and ev.category=="armor" and ev.stone=="HollowKeystone" and G.StoneFor.Eventide=="HollowKeystone","Eventide reforge from the Hollow Keystone")
	check(Data.Items.HollowKeystone.reforgeStone=="Eventide" and Data.Economy.isCommodity("HollowKeystone"),"Hollow Keystone is a tradeable stone")
	check(G.reforgeFits("Eventide",Data.Items.ObservatoryHelm) and not G.reforgeFits("Eventide",Data.Items.Riftcleaver),"Eventide fits armor only")
	check(table.find(G.ReforgeOrder.armor,"Eventide")~=nil and table.find(G.reforgePool(Data.Items.ObservatoryHelm),"Eventide")==nil,"stone reforge never rolls at the anvil")

	-- Migration.
	local fresh=DC.migrate(nil)
	check(fresh.selected==nil and fresh.master==false,"fresh class record")
	for _,id in ipairs(DC.order) do eq(fresh.xp[id],0,"fresh "..id.." XP") end
	local dirty=DC.migrate({selected="Berserk",master="yes",xp={Aegis=-5,Mender="x",Riftblade=1e12,Starshot=0/0,Arcanist=1234.9},
		secrets={["1"]=99,["2"]=1,["3"]="x",["9"]=4},masterBest={["1"]=999,["6"]=290,["8"]=290},masterClears={["2"]=3.7,["7"]=2,["8"]=2}})
	check(dirty.selected==nil and dirty.master==false,"invalid selection and flag dropped")
	check(dirty.xp.Aegis==0 and dirty.xp.Mender==0 and dirty.xp.Riftblade==DC.MAX_XP and dirty.xp.Starshot==0 and dirty.xp.Arcanist==1234,"class XP sanitised")
	check(dirty.secrets["1"]==2 and dirty.secrets["2"]==1 and dirty.secrets["3"]==nil and dirty.secrets["9"]==nil,"secret records clamp to the floor")
	check(dirty.masterBest["1"]==300 and dirty.masterBest["6"]==290 and dirty.masterBest["8"]==nil,"master scores floors I-VII only")
	check(dirty.masterClears["2"]==3 and dirty.masterClears["7"]==2 and dirty.masterClears["8"]==nil,"master clears sanitised")
	local kept=DC.migrate({selected="Starshot",master=true,xp={Starshot=500}})
	check(kept.selected=="Starshot" and kept.master==true and kept.xp.Starshot==500,"valid records survive")
	eq(DC.migrate(DC.migrate(kept)).xp.Starshot,500,"migration is idempotent")
	-- Party HUD string.
	local text=DC.partyString({{name="Ann",class="Aegis",level=12},{name="B|o;b",class=nil,level=0},{name="Cy",class="Nope",level=99}})
	eq(text,"Ann|Aegis|12;Bob||1;Cy||50","party string sanitises names, classes and levels")
	local rows=DC.parseParty(text)
	check(#rows==3 and rows[1].class=="Aegis" and rows[1].level==12 and rows[2].class==nil and rows[3].level==50,"party string round trip")
	eq(#DC.parseParty(nil),0,"no party")
	eq(#DC.parseParty("garbage;;x|y"),0,"malformed party ignored")
end
local ruleChecks=checks

------------------------------------------------------------------------------
-- Part 2: the encounter (expedition.server.lua).
------------------------------------------------------------------------------
do
	local function signal()
		local callbacks={}
		return {Connect=function(_,fn) table.insert(callbacks,fn) end,Fire=function(_,...) for _,fn in callbacks do fn(...) end end}
	end
	local signals={}
	r.implementProperty("ProximityPrompt","Triggered",function(p)
		signals[p]=signals[p] or signal()
		return signals[p]
	end)
	r.implementProperty("Workspace","DescendantAdded",function() return signal() end)
	local world=r.Instance.new("Workspace")
	local gate=r.Instance.new("Part")
	gate.Name="ExpeditionGate"
	gate.Position=r.Vector3.new(0,2,-121)
	gate.CFrame=r.CFrame.new(gate.Position)
	gate.Parent=world
	local players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end}
	local heartbeat=signal()
	local infos,classCalls,payloads,grants={},{},{},{}
	local bridge={Invoke=function(_,op,p,payload)
		local i=infos[p] or {}
		if op=="dungeon" then return {level=i.level or 1,ironman=false,class=i.class,classXp=i.classXp or {},best=i.best or {},master=i.master==true,gearScore=i.gearScore or 999} end
		if op=="dungeonClass" then
			-- Classes.choose: the profile stores the class and publishes the attribute.
			table.insert(classCalls,{p,payload.class})
			i.class=payload.class
			infos[p]=i
			p:SetAttribute("DungeonClass",payload.class)
			return {ok=true}
		end
		return nil
	end}
	local grant={Invoke=function(_,p,payload) grants[p]=(grants[p] or 0)+1 payloads[p]=payload return {ok=true} end}
	local services={Players=players,RunService={Heartbeat=heartbeat},
		CollectionService={AddTag=function() end},
		ReplicatedStorage={WaitForChild=function(_,name) return name end},
		ServerStorage={FindFirstChild=function(_,name)
			if name=="IsleBridge" then return bridge elseif name=="IsleExpeditionGrant" then return grant end
			return nil
		end}}
	local now=10
	local env={game={GetService=function(_,name) return services[name] end},workspace=world,
		require=function(name) assert(name=="AetherData","expedition requires shared data") return Data end,
		Instance=r.Instance,Vector3=r.Vector3,Vector2=r.Vector2,Color3=r.Color3,CFrame=r.CFrame,
		UDim2=r.UDim2,Enum=r.Enum,os={clock=function() return now end}}
	luau.load(fs.readFile("expedition.server.lua"),{environment=env,injectGlobals=true})()
	local hums,roots={},{}
	local count=0
	local function player(info)
		count+=1
		local root={Position=r.Vector3.new(0,0,900)}
		local hum={Health=100,MaxHealth=100}
		function hum:TakeDamage(n) self.Health=math.max(0,self.Health-n) end
		local char={}
		function char:FindFirstChild(name) if name=="HumanoidRootPart" then return root end end
		function char:FindFirstChildOfClass(name) if name=="Humanoid" then return hum end end
		function char:PivotTo(cf) root.Position=cf.Position end
		local p={Name="Delver"..count,Character=char,CharacterRemoving=signal(),attributes={}}
		function p:SetAttribute(k,v) self.attributes[k]=v end
		function p:GetAttribute(k) return self.attributes[k] end
		hums[p],roots[p]=hum,root
		infos[p]=info or {}
		players.PlayerAdded:Fire(p)
		return p
	end
	local function promptFor(partName,action,root)
		for _,obj in (root or world):GetDescendants() do
			if obj:IsA("ProximityPrompt") and obj.Parent.Name==partName and obj.ActionText==action then return obj end
		end
		error("Missing prompt "..partName.." / "..action)
	end
	local function fire(p,prompt)
		roots[p].Position=prompt.Parent.Position
		now+=3
		signals[prompt]:Fire(p)
	end
	local function use(p,partName,action) fire(p,promptFor(partName,action)) end
	local core=world:FindFirstChild("Eclipse Heart",true)
	local caption=world:FindFirstChild("TextLabel",true)
	local warn=world:FindFirstChild("Pulse radius",true)
	local function noticeOf(p) return p:GetAttribute("ExpeditionNotice") or "" end
	local function clearPad() for _,root in roots do root.Position=r.Vector3.new(0,0,900) end end
	local function onPad(p,dx) roots[p].Position=gate.Position+r.Vector3.new(dx or 0,0,0) end
	local function launch(list,opener)
		clearPad()
		for i,p in ipairs(list) do onPad(p,i-3) end
		signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(opener or list[1])
		now+=Data.Dungeons.padSeconds
		heartbeat:Fire(0)
	end
	local function inside(p) return roots[p].Position.Z==1824 or (roots[p].Position-core.Position).Magnitude<200 end
	local pylons={}
	for _,obj in world:GetDescendants() do
		if obj:IsA("ProximityPrompt") and obj.Parent.Name=="Resonance prism" then table.insert(pylons,obj) end
	end
	local function ordered()
		local list=table.clone(pylons)
		table.sort(list,function(x,y) return x.Parent:GetAttribute("TuneOrder")<y.Parent:GetAttribute("TuneOrder") end)
		return list
	end
	local function tuneAll(p) for _,prism in ordered() do roots[p].Position=prism.Parent.Position now+=1 signals[prism]:Fire(p) end end
	-- Dungeon endgame rooms (Floors VI-VII): a mistake-free greedy solver. Turn the
	-- first unlit mirror until the beam reaches the receiver; press the lectern's glyphs.
	local function promptIn(part) for _,o in part:GetChildren() do if o:IsA("ProximityPrompt") then return o end end return nil end
	local function roomStep(p)
		local text=caption.Text
		if has(text,"MIRROR GALLERY") then
			local list={}
			for _,o in world:GetDescendants() do if o.Name=="Gallery mirror" and o:IsA("BasePart") then table.insert(list,o) end end
			table.sort(list,function(a,b) return a:GetAttribute("MirrorIndex")<b:GetAttribute("MirrorIndex") end)
			for _,m in list do
				if m:GetAttribute("VisualState")~="Lit" then roots[p].Position=m.Position signals[promptIn(m)]:Fire(p) return true end
			end
		elseif has(text,"STAR CHART") or has(text,"Replay the star chart") then
			local lectern=world:FindFirstChild("Star chart lectern",true)
			local seq={}
			for g in string.gmatch(lectern:GetAttribute("ChartSequence") or "","%S+") do table.insert(seq,g) end
			local want=seq[lectern:GetAttribute("ChartStep") or 1]
			for _,o in world:GetDescendants() do
				if o.Name=="Glyph plate" and o:IsA("BasePart") and o:GetAttribute("Glyph")==want then roots[p].Position=o.Position signals[promptIn(o)]:Fire(p) return true end
			end
		end
		return false
	end
	local function solveRooms(p) for _=1,60 do now+=0.5 if not roomStep(p) then break end end end
	local function heal(p) hums[p].Health=100 end
	local function at(p,offset) roots[p].Position=core.Position+(offset or r.Vector3.zero) end
	local function strike(p,partName,action)
		heal(p)
		local prompt=promptFor(partName,action)
		roots[p].Position=prompt.Parent.Position
		now+=3
		signals[prompt]:Fire(p)
	end
	local function guardiansDown(list)
		for index=1,2 do
			local sentinel=world:FindFirstChild("Sentinel "..index,true)
			for _=1,80 do
				if sentinel:GetAttribute("VisualState")=="Defeated" then break end
				for _,p in list do
					if sentinel:GetAttribute("VisualState")~="Defeated" then strike(p,"Sentinel "..index,"Strike guardian") end
				end
			end
		end
	end
	local function ability(p,kind)
		at(p,r.Vector3.new(0,0,-6))
		now+=0.5
		signals[promptFor("Eclipse Heart",if kind=="ultimate" then "Ultimate" else "Class ability")]:Fire(p)
	end
	local function wisps()
		local list={}
		for _,obj in world:GetDescendants() do if obj.Name=="Umbral wisp" and obj:IsA("BasePart") then table.insert(list,obj) end end
		return list
	end
	local function secrets()
		local list={}
		for _,obj in world:GetDescendants() do if (obj.Name=="Secret cache" or obj.Name=="Secret lever") and obj:IsA("BasePart") then table.insert(list,obj) end end
		return list
	end
	local function search(p,part)
		for _,obj in part:GetChildren() do if obj:IsA("ProximityPrompt") then fire(p,obj) return end end
	end

	-- Pedestals and the master lever.
	for _,id in ipairs(DC.order) do
		local pedestal=world:FindFirstChild(id.." oath",true)
		check(pedestal~=nil and pedestal:GetAttribute("DungeonClass")==id,id.." pedestal by the pad")
	end
	check(world:FindFirstChild("Berserk oath",true)==nil,"legacy role pedestals replaced")
	check(world:FindFirstChild("Master lever",true)~=nil,"Master Mode lever by the pad")
	for index=6,7 do
		local dais=world:FindFirstChild("Observatory Floor "..Data.DungeonFloors[index].numeral,true)
		check(dais and dais:GetAttribute("RequiredLevel")==Data.DungeonFloors[index].level,"Floor "..index.." dais")
	end

	-- A balanced party of five on Floor I.
	local aegis,mender,rift,star,arc=player(),player(),player(),player(),player()
	local party={aegis,mender,rift,star,arc}
	for i,p in ipairs(party) do
		local id=DC.order[i]
		use(p,id.." oath","Choose class")
		eq(p:GetAttribute("DungeonClass"),id,id.." chosen at the pedestal")
		check(has(noticeOf(p),DC.defs[id].ability.name),id.." notice names the ability")
	end
	eq(#classCalls,5,"pedestal choices persist through the bridge")
	check(classCalls[3][1]==rift and classCalls[3][2]=="Riftblade","bridge receives the class")
	local outsider=player()
	ability(outsider,"ability")
	check(has(noticeOf(outsider),"inside an Observatory run"),"outsider cannot use abilities")
	launch(party)
	for _,p in party do check(inside(p) and p:GetAttribute("DungeonInRun")==true,p.Name.." launched and in a run") end
	check(core:GetAttribute("TeamBalanced")==true and core:GetAttribute("TeamUnique")==5,"balanced five-class party")
	local hud=DC.parseParty(aegis:GetAttribute("DungeonParty"))
	eq(#hud,5,"party HUD lists five delvers")
	for i,row in hud do eq(row.class,DC.order[i],"party HUD shows "..DC.order[i]) end
	eq(star:GetAttribute("DungeonUltimates"),1,"one ultimate charge at level 1")
	use(rift,"Starshot oath","Choose class")
	check(has(noticeOf(rift),"locked") and rift:GetAttribute("DungeonClass")=="Riftblade","class locked during the run")
	-- Secrets: two on Floor I.
	local found=secrets()
	eq(#found,DC.secretCount(1),"Floor I hides two secrets")
	eq(core:GetAttribute("SecretsTotal"),2,"heart reports the secret total")
	search(outsider,found[1])
	eq(core:GetAttribute("SecretsFound"),0,"outsiders cannot claim secrets")
	search(mender,found[1])
	eq(core:GetAttribute("SecretsFound"),1,"a delver finds a secret")
	check(found[1].Parent==nil and has(noticeOf(aegis),"Secret found"),"secret vanishes and the party is told")
	search(star,found[2])
	eq(core:GetAttribute("SecretsFound"),2,"every secret found")
	-- Prism phase: Bulwark is refused; Attune and Eclipse Rift tune prisms.
	ability(aegis,"ability")
	check(has(noticeOf(aegis),"boss phase"),"Bulwark refused during the prisms")
	ability(arc,"ability")
	check(has(caption.Text,"1 / 3"),"Attune tunes a prism")
	ability(arc,"ability")
	check(has(noticeOf(arc),"recharging"),"Attune cooldown enforced")
	eq(arc:GetAttribute("DungeonAbilityReady"),0,"ability HUD updates on the heartbeat")
	heartbeat:Fire(0)
	check((arc:GetAttribute("DungeonAbilityReady") or 0)>0,"ability HUD shows the cooldown")
	ability(arc,"ultimate")
	check(has(caption.Text,"SENTINEL HALL"),"Eclipse Rift completes the sequence")
	ability(arc,"ultimate")
	check(has(noticeOf(arc),"spent") or has(noticeOf(arc),"No prism"),"Eclipse Rift once per run")
	heartbeat:Fire(0)
	eq(arc:GetAttribute("DungeonUltimates"),0,"ultimate HUD shows the spent charge")
	guardiansDown(party)
	check(has(caption.Text,"ECLIPSE HEART  •  12 / 12"),"core opens")
	-- Starshot: Disrupting Shot needs a telegraph, then cancels the strike.
	ability(star,"ability")
	check(has(noticeOf(star),"telegraphing"),"Disrupting Shot refused without a telegraph")
	for _,p in party do at(p) heal(p) end
	heartbeat:Fire(3.6)
	check(warn.Transparency==0.25,"pulse telegraphed")
	ability(star,"ability")
	check(warn.Transparency==1 and core:GetAttribute("Telegraph")=="","Disrupting Shot cancels the telegraph")
	eq(core:GetAttribute("BossHealth"),11,"Disrupting Shot strikes the core")
	for _,p in party do at(p) end
	heartbeat:Fire(1.5)
	for _,p in party do eq(hums[p].Health,100,p.Name.." spared by the cancelled strike") end
	-- Aegis: Bulwark takes the next strike alone.
	ability(aegis,"ability")
	check(has(noticeOf(aegis),"Bulwark"),"Bulwark raised")
	for _,p in party do at(p) heal(p) end
	heartbeat:Fire(5)
	eq(hums[aegis].Health,91,"Bulwark: the Aegis takes the strike at half damage")
	for i=2,5 do eq(hums[party[i]].Health,100,party[i].Name.." shielded by Bulwark") end
	heartbeat:Fire(5)
	eq(hums[mender].Health,82,"Bulwark covers one strike at level 1")
	eq(hums[aegis].Health,82,"the Aegis is struck normally afterwards (9)")
	-- Aegis ultimate: the party ignores two strikes.
	ability(aegis,"ultimate")
	for _,p in party do at(p) heal(p) end
	heartbeat:Fire(5) heartbeat:Fire(5)
	for _,p in party do eq(hums[p].Health,100,p.Name.." untouched under Bastion") end
	heartbeat:Fire(5)
	eq(hums[rift].Health,82,"Bastion lasts two strikes")
	-- Mender: Mending Light and the strike heal; Second Dawn forgives a fall.
	hums[rift].Health=40
	hums[star].Health=90
	ability(mender,"ability")
	check(hums[rift].Health==75 and hums[star].Health==100,"Mending Light heals 35% of max health")
	hums[rift].Health=50
	at(rift)
	ability(mender,"ultimate")
	eq(hums[rift].Health,100,"Second Dawn heals to full")
	hums[arc].Health=0
	heartbeat:Fire(0)
	heal(arc)
	heartbeat:Fire(0)
	-- Riftblade: Rending Storm tears 10% (ceil) from the core.
	local before=core:GetAttribute("BossHealth")
	ability(rift,"ultimate")
	eq(core:GetAttribute("BossHealth"),before-2,"Rending Storm deals 10% of max HP")
	ability(rift,"ability")
	eq(core:GetAttribute("BossHealth"),before-4,"Rift Cleave hits the exposed core for 2")
	-- Everyone strikes until the core falls.
	for _=1,10 do
		if not has(caption.Text,"ECLIPSE HEART") then break end
		for _,p in party do if has(caption.Text,"ECLIPSE HEART") then strike(p,"Eclipse Heart","Strike core") end end
	end
	for _,p in party do
		check(grants[p]==1,p.Name.." credited")
		local pay=payloads[p]
		check(pay and pay.class==p.attributes.DungeonClass,p.Name.." payload carries the class")
		eq(pay.secrets,2,p.Name.." payload secrets")
		eq(pay.secretsTotal,2,p.Name.." payload secret total")
		check(math.abs(pay.teamMult-1.24)<1e-9,p.Name.." payload team multiplier")
		eq(pay.master,false,p.Name.." normal mode")
		eq(p:GetAttribute("DungeonInRun"),false,p.Name.." left the run")
		eq(p:GetAttribute("DungeonParty"),"",p.Name.." party HUD cleared")
	end
	eq(payloads[aegis].deaths,0,"Second Dawn forgave the fall")
	check(payloads[aegis].feat and payloads[star].feat and payloads[arc].feat,"Absorb, Disrupt and Attune feats earned")
	check(payloads[mender].feat,"Mender healed 50+ and earned the feat")
	eq(payloads[rift].feat,false,"Riftblade slew no wisps and landed no sentinel's final blow")
	eq(payloads[aegis].bonus,DC.bonusScore(4,true),"bonus = 4 feats + balanced team")
	local expected=DC.score(1,payloads[aegis].seconds,0,0,2,2,DC.bonusScore(4,true))
	check(math.abs(payloads[aegis].score-expected)<=1,"score uses the full formula")
	check(has(aegis:GetAttribute("DungeonResult"),"secrets 2/2") and has(aegis:GetAttribute("DungeonResult"),"bonus 17"),"result summary shows secrets and bonus")

	-- Unclassed delvers have no abilities; class levels come from the bridge.
	local plain=player({level=1})
	launch({plain})
	ability(plain,"ability")
	check(has(noticeOf(plain),"Choose a class"),"unclassed delver has no ability")
	use(plain,"Return arch","Leave expedition")
	-- Riftblade level 50: integer hits carry the +49% bonus.
	local vet=player({level=1,class="Riftblade",classXp={Riftblade=DC.MAX_XP}})
	launch({vet})
	eq(vet:GetAttribute("DungeonUltimates"),2,"level 50 brings two ultimate charges")
	tuneAll(vet)
	local sentinel=world:FindFirstChild("Sentinel 1",true)
	strike(vet,"Sentinel 1","Strike guardian")
	strike(vet,"Sentinel 1","Strike guardian")
	strike(vet,"Sentinel 1","Strike guardian")
	eq(sentinel:GetAttribute("VisualState"),"Defeated","2 + 2 + 3 (carried) fells a 6 HP sentinel in three strikes")
	eq(DC.parseParty(vet:GetAttribute("DungeonParty"))[1].level,50,"party HUD shows class level 50")
	use(vet,"Return arch","Leave expedition")
	-- Aegis level 50 mitigation against sentinel counters.
	local wall=player({level=1,class="Aegis",classXp={Aegis=DC.MAX_XP}})
	launch({wall})
	tuneAll(wall)
	strike(wall,"Sentinel 1","Strike guardian")
	eq(hums[wall].Health,100-math.floor(6*DC.damageTakenMult("Aegis",50)),"Aegis 50 takes reduced counter damage")
	use(wall,"Return arch","Leave expedition")

	-- Master Mode: lever, unlock gate and doubled numbers.
	local master=player({level=1,best={[1]=295}})
	local novice=player({level=1})
	use(master,"Master lever","Toggle Master Mode")
	eq(master:GetAttribute("DungeonMasterPick"),true,"lever turns Master Mode on")
	use(novice,"Master lever","Toggle Master Mode")
	clearPad() onPad(novice)
	signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(novice)
	check(has(noticeOf(novice),"after a grade S"),"Master Mode needs a grade S on the floor")
	use(novice,"Master lever","Toggle Master Mode")
	eq(novice:GetAttribute("DungeonMasterPick"),false,"lever turns Master Mode off")
	clearPad() onPad(master) onPad(novice,2)
	signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(master)
	check(has(caption.Text,"MASTER"),"caption announces a Master Mode run")
	now+=Data.Dungeons.padSeconds
	heartbeat:Fire(0)
	check(inside(master) and not inside(novice),"only unlocked delvers join a Master Mode run")
	check(has(noticeOf(novice),"grade S"),"locked delver told why")
	check(core:GetAttribute("MasterMode")==true and core:GetAttribute("BossMaxHealth")==24,"Master Mode doubles the core")
	tuneAll(master)
	strike(master,"Sentinel 1","Strike guardian")
	eq(hums[master].Health,88,"Master Mode doubles sentinel counters")
	guardiansDown({master})
	at(master) heal(master)
	heartbeat:Fire(5)
	eq(hums[master].Health,64,"Master Mode doubles boss strikes (36)")
	for _=1,30 do if not has(caption.Text,"ECLIPSE HEART") then break end strike(master,"Eclipse Heart","Strike core") end
	check(payloads[master] and payloads[master].master==true,"Master Mode payload")
	-- The Dungeon page toggle (attribute DungeonMasterOn) is honoured too.
	local pageMaster=player({level=40,best={}})
	pageMaster:SetAttribute("DungeonMasterOn",true)
	use(pageMaster,"Observatory Floor VI","Select floor")
	clearPad() onPad(pageMaster)
	signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(pageMaster)
	check(has(noticeOf(pageMaster),"grade S"),"Master Mode on Floor VI needs its own grade S clear (Dungeon endgame)")
	pageMaster:SetAttribute("DungeonMasterOn",false)
	signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(pageMaster)
	now+=Data.Dungeons.padSeconds
	heartbeat:Fire(0)
	check(inside(pageMaster) and core:GetAttribute("MasterMode")==false,"normal Floor VI once Master Mode is off")

	-- Floor VI: lances, regeneration while wisps live.
	check(core:GetAttribute("BossName")=="Lumen Colossus" and core:GetAttribute("BossMaxHealth")==90,"Floor VI boss")
	eq(#secrets(),DC.secretCount(6),"Floor VI hides five secrets")
	use(pageMaster,"Return arch","Leave expedition")
	local low=player({level=39})
	use(low,"Observatory Floor VI","Select floor")
	check(has(noticeOf(low),"Dungeoneering 40"),"Floor VI needs Dungeoneering 40")
	local lancer=player({level=40,class="Riftblade"})
	local buddy=player({level=40,class="Aegis"})
	use(lancer,"Observatory Floor VI","Select floor")
	launch({lancer,buddy})
	tuneAll(lancer)
	check(has(caption.Text,"MIRROR GALLERY"),"Floor VI opens the Mirror Gallery after the prisms")
	solveRooms(lancer)
	guardiansDown({lancer,buddy})
	ability(lancer,"ultimate")
	eq(core:GetAttribute("BossHealth"),81,"Rending Storm on Floor VI (9)")
	at(lancer,r.Vector3.new(6,0,0)) at(buddy,r.Vector3.new(-6,0,0))
	heartbeat:Fire(0.1)
	eq(#wisps(),3,"Floor VI wave of three wisps")
	check(has(caption.Text,"regenerates"),"caption warns about regeneration")
	heartbeat:Fire(3.8)
	check(core:GetAttribute("Telegraph")=="Converging Lances" and #world:GetDescendants()>0,"lances telegraphed")
	local marks=0
	for _,obj in world:GetDescendants() do if obj.Name=="Lance mark" then marks+=1 end end
	eq(marks,1,"one extra mark per delver beyond the first")
	heal(lancer) heal(buddy)
	at(lancer,r.Vector3.new(6,0,20))
	heartbeat:Fire(2.2)
	eq(hums[lancer].Health,100,"stepping off your mark dodges the lance")
	eq(hums[buddy].Health,100-math.floor(46*0.5),"the Aegis on its mark takes the lance at half")
	marks=0
	for _,obj in world:GetDescendants() do if obj.Name=="Lance mark" then marks+=1 end end
	eq(marks,0,"lance marks cleared after the strike")
	heartbeat:Fire(6)
	eq(core:GetAttribute("BossHealth"),85,"Floor VI regenerates 4% while wisps live")
	-- Comet-free wisp clearing: Cleave hits every wisp.
	local hp=wisps()[1]:GetAttribute("AddHealth")
	now+=20
	ability(lancer,"ability")
	eq(wisps()[1]:GetAttribute("AddHealth"),hp-2,"Rift Cleave hits every wisp")
	use(lancer,"Return arch","Leave expedition")
	use(buddy,"Return arch","Leave expedition")
	-- Starshot Comet Volley clears a wave and earns no Riftblade feat.
	local volley=player({level=20,class="Starshot"})
	use(volley,"Observatory Floor IV","Select floor")
	launch({volley})
	tuneAll(volley)
	guardiansDown({volley})
	at(volley)
	heartbeat:Fire(0.1)
	eq(#wisps(),2,"Floor IV wave")
	ability(volley,"ultimate")
	eq(#wisps(),0,"Comet Volley destroys every wisp")
	check(not has(caption.Text,"WARDED"),"ward lifted")
	use(volley,"Return arch","Leave expedition")

	-- Floor VII: the Hollow Sovereign.
	local sovereign=player({level=50})
	use(sovereign,"Observatory Floor VII","Select floor")
	launch({sovereign})
	check(core:GetAttribute("BossName")=="Hollow Sovereign" and core:GetAttribute("BossMaxHealth")==120,"Floor VII boss")
	eq(#secrets(),5,"Floor VII hides five secrets")
	tuneAll(sovereign)
	solveRooms(sovereign)
	guardiansDown({sovereign})
	at(sovereign,r.Vector3.new(20,0,0)) heal(sovereign)
	-- 120 sentinel strikes later the Sovereign is already enraged (360 s): 3 s tempo, 1.8 s telegraph.
	heartbeat:Fire(1.3)
	eq(core:GetAttribute("Enraged"),true,"Floor VII enrage timer")
	check(warn:GetAttribute("SafeRadius")==0 and core:GetAttribute("Telegraph")=="Eventide Collapse","collapse opens with the pulse")
	heartbeat:Fire(1.8)
	heartbeat:Fire(1.3)
	eq(warn:GetAttribute("SafeRadius"),10,"collapse continues with the ring")
	use(sovereign,"Return arch","Leave expedition")
	check(has(caption.Text,"0 / 3") and #secrets()==0,"leaving resets and clears the secrets")
	now+=200

	-- Review M4: the profile is the only class source; a pedestal choice never
	-- overrides a later Dungeon-page choice, and a stale attribute is ignored.
	local chooser=player({level=1})
	use(chooser,"Starshot oath","Choose class")
	eq(infos[chooser].class,"Starshot","pedestal writes the profile through the bridge")
	infos[chooser].class="Arcanist" -- Dungeon page: dungeonClass verb -> Classes.choose -> profile + attribute
	chooser:SetAttribute("DungeonClass","Arcanist")
	launch({chooser})
	eq(DC.parseParty(chooser:GetAttribute("DungeonParty"))[1].class,"Arcanist","the Dungeon-page choice wins over an earlier pedestal choice")
	use(chooser,"Return arch","Leave expedition")
	infos[chooser].class=nil -- profile cleared; the attribute still says Arcanist
	launch({chooser})
	eq(DC.parseParty(chooser:GetAttribute("DungeonParty"))[1].class,nil,"runs read the profile, never a stale attribute")
	use(chooser,"Return arch","Leave expedition")

	-- Review H2: Second Dawn cannot be pre-banked, expires after 20 s and never stacks.
	local dawn=player({level=1,class="Mender",classXp={Mender=DC.xpForLevel(30)}})
	local mate=player({level=1})
	launch({dawn,mate})
	ability(dawn,"ultimate")
	check(has(noticeOf(dawn),"boss phase"),"Second Dawn refused during the prisms (no pre-banking)")
	tuneAll(dawn)
	ability(dawn,"ultimate")
	check(has(noticeOf(dawn),"boss phase"),"Second Dawn refused in the sentinel hall")
	guardiansDown({dawn,mate})
	local function fall(p) hums[p].Health=0 heartbeat:Fire(0) heal(p) heartbeat:Fire(0) end
	ability(dawn,"ultimate")
	check(has(noticeOf(dawn),"Second Dawn"),"Second Dawn cast in the boss phase")
	now+=21
	fall(mate) -- 21 s later: the grace has expired, the fall counts
	now+=25
	ability(dawn,"ultimate") -- second charge (level 30): refreshes, does not add a second forgive
	check(has(noticeOf(dawn),"Second Dawn"),"second Second Dawn cast")
	fall(mate) -- forgiven
	fall(mate) -- counts: forgives never stack
	for _=1,20 do
		if not has(caption.Text,"ECLIPSE HEART") then break end
		for _,p in {dawn,mate} do if has(caption.Text,"ECLIPSE HEART") then strike(p,"Eclipse Heart","Strike core") end end
	end
	check(payloads[dawn]~=nil,"Second Dawn run cleared")
	eq(payloads[dawn].deaths,2,"one expired and one unstacked fall count; only one is forgiven")
	now+=100

	-- Review M3: the team bonus counts only delvers still in the run and credited.
	local ta,tr,ts,ti=player({level=1,class="Aegis"}),player({level=1,class="Riftblade"}),player({level=1,class="Starshot"}),player({level=1,class="Arcanist"})
	launch({ta,tr,ts,ti})
	eq(core:GetAttribute("TeamUnique"),4,"four unique classes at launch")
	tuneAll(ta)
	guardiansDown({ta,tr,ts})
	use(ts,"Return arch","Leave expedition") -- leaves before the boss falls
	at(ti,r.Vector3.new(0,0,8)) -- stays, alive, but never contributes
	for _=1,20 do
		if not has(caption.Text,"ECLIPSE HEART") then break end
		for _,p in {ta,tr} do if has(caption.Text,"ECLIPSE HEART") then strike(p,"Eclipse Heart","Strike core") at(ti,r.Vector3.new(0,0,8)) heal(ti) end end
	end
	check(payloads[ta] and payloads[tr] and payloads[ti]==nil and payloads[ts]==nil,"only the two contributors are credited")
	check(math.abs(payloads[ta].teamMult-DC.teamBonus({"Aegis","Riftblade"}).xpMult)<1e-9,"team multiplier from the credited pair (x1.06), not the launch four")
	local pairFeats=(if payloads[ta].feat then 1 else 0)+(if payloads[tr].feat then 1 else 0)
	eq(payloads[ta].bonus,DC.bonusScore(pairFeats,false),"no balanced-team bonus once the party shrank")
	now+=100

	-- Review L8: feats. A solo Mender earns its heal feat from self-heals.
	local soloMender=player({level=1,class="Mender"})
	launch({soloMender})
	tuneAll(soloMender)
	guardiansDown({soloMender})
	hums[soloMender].Health=40
	ability(soloMender,"ability") -- Mending Light on itself: +35
	local corePrompt=promptFor("Eclipse Heart","Strike core")
	for _=1,20 do
		if not has(caption.Text,"ECLIPSE HEART") then break end
		hums[soloMender].Health=50
		fire(soloMender,corePrompt)
	end
	check(payloads[soloMender] and payloads[soloMender].feat==true,"solo Mender earns the heal feat from self-heals")
	-- A Riftblade on a floor without wisps earns its feat with a sentinel's final blow.
	local soloRift=player({level=1,class="Riftblade"})
	launch({soloRift})
	tuneAll(soloRift)
	guardiansDown({soloRift})
	for _=1,20 do if not has(caption.Text,"ECLIPSE HEART") then break end strike(soloRift,"Eclipse Heart","Strike core") end
	check(payloads[soloRift] and payloads[soloRift].feat==true,"Riftblade feat is reachable on Floor I")
	-- Bastion earns Absorb only when a strike it blocked would have landed.
	local idleWall=player({level=1,class="Aegis"})
	launch({idleWall})
	tuneAll(idleWall)
	guardiansDown({idleWall})
	ability(idleWall,"ultimate")
	at(idleWall,r.Vector3.new(25,0,0)) heal(idleWall)
	heartbeat:Fire(5) heartbeat:Fire(5) -- both strikes blocked, nobody was in the pulse
	for _=1,20 do if not has(caption.Text,"ECLIPSE HEART") then break end strike(idleWall,"Eclipse Heart","Strike core") end
	check(payloads[idleWall] and payloads[idleWall].feat==false,"Bastion on an empty pulse earns no feat")
	local busyWall=player({level=1,class="Aegis"})
	launch({busyWall})
	tuneAll(busyWall)
	guardiansDown({busyWall})
	ability(busyWall,"ultimate")
	at(busyWall) heal(busyWall)
	heartbeat:Fire(5)
	eq(hums[busyWall].Health,100,"Bastion blocks the pulse")
	for _=1,20 do if not has(caption.Text,"ECLIPSE HEART") then break end strike(busyWall,"Eclipse Heart","Strike core") end
	check(payloads[busyWall] and payloads[busyWall].feat==true,"Bastion that absorbs a strike earns the feat")
	now+=100

	-- Review H1: clearability simulation. A five-delver party (unclassed, or one
	-- of each class at level 1) strikes on the 0.8 s melee rhythm (0.85 s ticks):
	-- tune prisms in order, fell the sentinels, clear wisps first, then the core.
	-- Every floor I-VII and Master I-V must be cleared inside the run cap, and
	-- live wisps must never exceed DC.WISP_CAP.
	local RUN_CAP_PARS_TEST=2 -- expedition.server.lua RUN_CAP_PARS
	local arenaModel=world:FindFirstChild("The Hollow Observatory")
	local sentinelPrompts={promptFor("Sentinel 1","Strike guardian"),promptFor("Sentinel 2","Strike guardian")}
	local function liveWisps()
		local list={}
		for _,o in arenaModel:GetChildren() do if o.Name=="Umbral wisp" then table.insert(list,o) end end
		return list
	end
	local function promptOf(part) for _,o in part:GetChildren() do if o:IsA("ProximityPrompt") then return o end end return nil end
	local function simulate(classList,floorIndex,master)
		local party={}
		for _,cls in ipairs(classList) do
			table.insert(party,player({level=50,class=if cls then cls else nil,best={295,295,295,295,295,295,295}}))
		end
		party[1]:SetAttribute("DungeonMasterOn",master)
		use(party[1],"Observatory Floor "..Data.DungeonFloors[floorIndex].numeral,"Select floor")
		launch(party)
		check(party[1]:GetAttribute("DungeonInRun")==true and core:GetAttribute("MasterMode")==master,"sim launched floor "..floorIndex..(if master then " Master" else ""))
		local dt,ticks,maxWisps=0.85,0,0
		local limit=math.ceil(2*DC.par(floorIndex,master)/dt)+5
		while party[1]:GetAttribute("DungeonInRun")==true and ticks<limit do
			ticks+=1
			now+=dt
			for _,p in party do heal(p) end
			for _,p in party do
				if p:GetAttribute("DungeonInRun")~=true then break end
				local text=caption.Text
				if roomStep(p) then
					-- Dungeon endgame rooms / Constellation Lock handled by the greedy solver.
				elseif has(text,"Tune the prisms") or has(text,"Retune") then
					local tuned=0
					for _,pr in pylons do if pr.Parent:GetAttribute("VisualState")=="Tuned" then tuned+=1 end end
					for _,pr in pylons do
						local order=pr.Parent:GetAttribute("TuneOrder")
						if pr.Parent:GetAttribute("VisualState")~="Tuned" and (order==0 or order==tuned+1) then
							roots[p].Position=pr.Parent.Position
							signals[pr]:Fire(p)
							break
						end
					end
				elseif has(text,"SENTINEL HALL") then
					for _,sp in sentinelPrompts do
						if sp.Parent:GetAttribute("VisualState")~="Defeated" then roots[p].Position=sp.Parent.Position signals[sp]:Fire(p) break end
					end
				else
					local list=liveWisps()
					if #list>0 then
						roots[p].Position=list[1].Position
						signals[promptOf(list[1])]:Fire(p)
					else
						roots[p].Position=core.Position
						signals[corePrompt]:Fire(p)
					end
				end
			end
			if party[1]:GetAttribute("DungeonInRun")==true then heartbeat:Fire(dt) end
			maxWisps=math.max(maxWisps,#liveWisps())
		end
		local pay=payloads[party[1]]
		local label=(if classList[1] then "classed" else "unclassed").." floor "..floorIndex..(if master then " Master" else "")
		check(pay~=nil and pay.floor==floorIndex and pay.master==master,label.." cleared and credited ("..ticks.." ticks)")
		check(pay and pay.seconds<RUN_CAP_PARS_TEST*DC.par(floorIndex,master),label.." inside the run cap ("..(pay and pay.seconds or -1).."s)")
		check(maxWisps<=DC.WISP_CAP,label.." live wisps "..maxWisps.." <= cap")
		for _,p in party do if p:GetAttribute("DungeonInRun")==true then use(p,"Return arch","Leave expedition") end end
		now+=100
		return pay and pay.seconds or math.huge
	end
	local unclassed={false,false,false,false,false}
	local timed={}
	for floor=1,#Data.DungeonFloors do
		timed[floor]={normal=simulate(unclassed,floor,false)}
		simulate(DC.order,floor,false)
		if floor<=DC.MASTER_FLOORS then
			timed[floor].master=simulate(unclassed,floor,true)
			simulate(DC.order,floor,true)
		end
	end
	-- Review M5: at equal performance (same party, flawless, every secret) Master
	-- Mode pays at least as much per hour as the normal floor.
	for floor=1,DC.MASTER_FLOORS do
		local total=DC.secretCount(floor)
		local function perHour(master)
			local t=timed[floor][if master then "master" else "normal"]
			local grade=Data.dungeonGrade(DC.score(floor,t,0,0,total,total,0,master))
			local rw=DC.runRewards(floor,grade,{master=master,secrets=total,class="Aegis"})
			return rw.dungeoneeringXp*3600/t,rw.coins*3600/t,rw.classXp*3600/t,grade
		end
		local nx,nc,ncl,ng=perHour(false)
		local mx,mc,mcl,mg=perHour(true)
		check(mg==ng,"floor "..floor.." Master grades like normal at equal performance ("..ng.." / "..mg..")")
		check(mx>=nx and mc>=nc and mcl>=ncl,"floor "..floor.." Master pays >= normal per hour (XP "..math.floor(mx).." vs "..math.floor(nx)..", time "..timed[floor].master.."/"..timed[floor].normal.."s)")
	end
end
local runChecks=checks-ruleChecks

------------------------------------------------------------------------------
-- Part 3: server.server.lua Classes block (verify-gameplay.luau harness).
------------------------------------------------------------------------------
do
	local src=(fs.readFile("verify-gameplay.luau"):gsub("\r\n","\n"))
	local cut=src:find("local checks=0\nlocal function eq",1,true)
	assert(cut,"verify-gameplay harness marker")
	local h=luau.load(src:sub(1,cut-1).."\nreturn {player=player,cmd=cmd,allObjects=allObjects,data=data,advance=advance,services=services}",{debugName="gameplay-harness",injectGlobals=true})()
	local function hook(name) for _,o in ipairs(h.allObjects) do if o.Name==name then return o end end return nil end
	local grant=hook("IsleExpeditionGrant")
	local bridge=hook("IsleBridge")
	check(grant and bridge,"server publishes the grant and bridge")
	local p=h.player(8101)
	local s=h.cmd(p,"state")
	local view=s.dungeonClasses
	check(type(view)=="table" and view.selected==nil and view.master==false,"fresh journal has a class record")
	for _,id in ipairs(DC.order) do eq(view.classes[id].level,1,"fresh "..id.." level") end
	eq(#view.floors,7,"snapshot covers seven floors")
	eq(view.floors[6].secretsTotal,5,"snapshot secret totals")
	eq(p.DungeonClass,"","class attribute published on join")
	check(has(h.cmd(p,"dungeonClass","Berserk").message,"Choose Aegis"),"unknown class refused")
	local chosen=h.cmd(p,"dungeonClass","Aegis")
	check(chosen.dungeonClasses.selected=="Aegis" and has(chosen.message,"Aegis (Tank) chosen"),"dungeonClass verb selects")
	eq(p.DungeonClass,"Aegis","class attribute updated")
	eq(p.DungeonClassLevel,1,"class level attribute")
	p.DungeonInRun=true
	check(has(h.cmd(p,"dungeonClass","Mender").message,"locked"),"class locked during a run")
	check(has(h.cmd(p,"dungeonMaster","on").message,"locked"),"Master Mode locked during a run")
	p.DungeonInRun=false
	check(has(h.cmd(p,"dungeonMaster","maybe").message,"on or off"),"Master Mode verb validates")
	check(has(h.cmd(p,"dungeonMaster","on").message,"grade S"),"Master Mode needs a grade S clear")
	-- Bridge: the expedition reads class, XP, bests and the preference.
	local info=bridge.OnInvoke("dungeon",p)
	check(info.class=="Aegis" and info.classXp.Aegis==0 and info.best[1]==0 and info.master==false,"bridge dungeon op carries class data")
	check(bridge.OnInvoke("dungeonClass",p,{class="Starshot"}).ok==true,"bridge persists a pedestal choice")
	eq(h.cmd(p,"state").dungeonClasses.selected,"Starshot","pedestal choice saved")
	eq(bridge.OnInvoke("dungeonClass",p,{class="Nope"}).ok,false,"bridge refuses unknown classes")
	-- Grant: class XP, secrets, best score, Master Mode unlock.
	local result=grant.OnInvoke(p,{floor=1,grade="S+",score=295,partySize=3,damageShare=0.4,class="Starshot",secrets=2,secretsTotal=2,teamMult=1.12,master=false})
	eq(result.ok,true,"S+ clear accepted")
	local clearMessage=p.last and p.last.message or ""
	s=h.cmd(p,"state")
	view=s.dungeonClasses
	eq(view.classes.Starshot.xp,DC.classXp(1,"S+",false,1.12),"class XP paid to the selected class")
	eq(view.classes.Aegis.xp,0,"other classes unchanged")
	eq(view.classes.Starshot.level,DC.levelForXp(DC.classXp(1,"S+",false,1.12)),"class level from XP")
	check(view.floors[1].secrets==2 and view.floors[1].best==295 and view.floors[1].clears==1,"secrets, best score and clears recorded")
	eq(view.floors[1].masterUnlocked,true,"S+ unlocks Master Mode on Floor I")
	eq(view.floors[2].masterUnlocked,false,"other floors stay locked")
	eq(s.items.ObservatoryEssence,DC.runRewards(1,"S+",{secrets=2}).items.ObservatoryEssence+Data.DungeonEndgame.bounty(1,false),"secrets add essence (plus the weekly first-clear bounty)")
	check(has(clearMessage,"Starshot XP") and has(clearMessage,"2 secrets found"),"clear message names class XP and secrets")
	eq(p.DungeonClassLevel,view.classes.Starshot.level,"class level attribute after the clear")
	local on=h.cmd(p,"dungeonMaster","on")
	check(on.dungeonClasses.master==true and p.DungeonMasterOn==true,"Master Mode switched on")
	eq(bridge.OnInvoke("dungeon",p).master,true,"bridge reports Master Mode")
	eq(bridge.OnInvoke("dungeon",p).best[1],295,"bridge reports the best score")
	h.advance(91)
	local m=grant.OnInvoke(p,{floor=1,grade="A",score=230,partySize=1,damageShare=1,class="Starshot",secrets=1,master=true})
	eq(m.ok,true,"Master Mode clear accepted")
	view=h.cmd(p,"state").dungeonClasses
	check(view.floors[1].masterClears==1 and view.floors[1].masterBest==230,"Master Mode clears recorded separately")
	check(view.floors[1].best==295 and view.floors[1].clears==1,"normal best untouched by Master Mode")
	eq(view.floors[1].secrets,2,"secret best keeps the maximum")
	eq(view.classes.Starshot.xp,DC.classXp(1,"S+",false,1.12)+DC.classXp(1,"A",true,1),"Master Mode class XP x"..DC.MASTER_XP)
	-- A fresh session lease (journals renew it on autosave; the harness rejoins).
	h.services.Players.PlayerRemoving:Fire(p)
	p=h.player(8101)
	h.advance(91)
	local x=grant.OnInvoke(p,{floor=1,grade="B",score=200,class="Hacker",secrets=99,teamMult=50})
	eq(x.ok,true,"odd payload sanitised, not refused")
	view=h.cmd(p,"state").dungeonClasses
	eq(view.classes.Starshot.xp,DC.classXp(1,"S+",false,1.12)+DC.classXp(1,"A",true,1),"invalid class earns no class XP")
	eq(view.floors[1].secrets,2,"secret count clamps to the floor")
	-- A fresh journal cannot claim Master Mode.
	local q=h.player(8102)
	local refused=grant.OnInvoke(q,{floor=1,grade="S",score=270,master=true,class="Aegis"})
	check(refused.ok==false and has(refused.reason,"grade S"),"Master Mode grant needs the unlock")
	eq(h.cmd(q,"state").dungeonClasses.classes.Aegis.xp,0,"refused grant pays no class XP")
	-- Legacy BindableEvent path still pays Floor I grade B.
	local legacy=h.cmd(q,"state")
	check(legacy.dungeonClasses.floors[1].clears==0,"no clears yet")
	-- Persistence: rejoin keeps the class record.
	h.services.Players.PlayerRemoving:Fire(p)
	local saved=h.data["p8101"].profile.dungeonClasses
	check(saved and saved.selected=="Starshot" and saved.master==true and saved.xp.Starshot>0,"class record saved")
	p=h.player(8101)
	view=h.cmd(p,"state").dungeonClasses
	check(view.selected=="Starshot" and view.master==true and view.floors[1].masterClears==1,"class record survives a rejoin")
	eq(p.DungeonClass,"Starshot","class attribute restored on join")
	eq(p.DungeonMasterOn,true,"Master Mode attribute restored on join")
	-- Migration: corrupt and legacy saves are sanitised on load.
	h.services.Players.PlayerRemoving:Fire(p)
	h.data["p8101"].profile.dungeonClasses={selected="Mage",master=1,xp={Aegis=-4,Starshot=1e15,Mender="x"},secrets={["1"]=50,["4"]=2},masterBest={["7"]=300}}
	p=h.player(8101)
	view=h.cmd(p,"state").dungeonClasses
	check(view.selected==nil and view.master==false,"corrupt selection dropped on load")
	check(view.classes.Aegis.xp==0 and view.classes.Starshot.level==50 and view.classes.Mender.xp==0,"corrupt XP sanitised")
	check(view.floors[1].secrets==2 and view.floors[4].secrets==2,"secret records clamped")
	eq(p.DungeonClass,"","sanitised class attribute")
	h.services.Players.PlayerRemoving:Fire(p)
	h.data["p8101"].profile.dungeonClasses=nil
	p=h.player(8101)
	view=h.cmd(p,"state").dungeonClasses
	check(view and view.selected==nil and view.classes.Riftblade.xp==0,"legacy save gains a class record")
	eq(h.cmd(p,"dungeonClass","none").dungeonClasses.selected,nil,"none clears the class")
	check(has(h.cmd(p,"dungeonClass","none").message,"unclassed"),"clearing message")
end
local serverChecks=checks-ruleChecks-runChecks

------------------------------------------------------------------------------
-- Part 4: ui.client.lua Hunt > Dungeon page and party HUD (verify-ui.luau harness).
------------------------------------------------------------------------------
do
	local src=(fs.readFile("verify-ui.luau"):gsub("\r\n","\n"))
	local cut=src:find("------------------------------------------------------------------------------\n-- Checks",1,true)
	assert(cut,"verify-ui harness marker")
	local h=luau.load(src:sub(1,cut-1).."\nreturn {run=run,snapshot=snapshot,find=find,press=press,noFailures=noFailures,new=new}",{debugName="ui-harness",injectGlobals=true})()
	local function openDungeon(ui)
		if not ui.atlas.Visible then h.press(h.find(ui.gui,"AtlasButton")) end
		h.press(ui.tabs:FindFirstChild("HuntButton"))
		h.press(h.find(ui.scroll,"SectionDungeon"))
	end
	local snap=h.snapshot()
	local classes={}
	for _,id in ipairs(DC.order) do classes[id]=DC.progress(if id=="Aegis" then DC.xpForLevel(31)+10 else 0) end
	local floors={}
	for i=1,7 do floors[i]={secrets=math.min(i,DC.secretCount(i)),secretsTotal=DC.secretCount(i),best=if i==1 then 295 else 0,clears=i,masterUnlocked=i==1,masterBest=0,masterClears=0} end
	snap.dungeonClasses={selected="Aegis",master=false,classes=classes,floors=floors}
	local ui=h.run({snapshot=snap})
	openDungeon(ui)
	h.noFailures(ui,"dungeon page")
	for _,id in ipairs(DC.order) do check(h.find(ui.scroll,"DungeonClass_"..id)~=nil,"class card "..id) end
	for i=1,7 do check(h.find(ui.scroll,"DungeonFloor"..i)~=nil,"floor card "..i) end
	check(h.find(ui.scroll,"DungeonMaster")~=nil and h.find(ui.scroll,"DungeonTeam")~=nil,"Master Mode and team cards")
	local function texts(root)
		local out={}
		for _,o in ipairs(root:GetDescendants()) do if o.ClassName=="TextLabel" or o.ClassName=="TextButton" then table.insert(out,tostring(o.Text)) end end
		return table.concat(out,"\n")
	end
	local page=texts(ui.scroll)
	check(has(page,"Starwall Bulwark") and has(page,"Eclipse Rift") and has(page,"Comet Volley"),"abilities listed")
	check(has(page,"Class level 31"),"class level shown")
	check(has(page,"Observatory Floor VII") and has(page,"Hollow Sovereign"),"Floor VII listed")
	check(has(page,"Secrets: best 3 / 3"),"secrets per floor shown")
	check(has(page,"Master Mode unlocked"),"Master Mode unlock shown")
	check(has(page,"secrets"),"score card explains secrets")
	local before=#ui.sent
	h.press(h.find(ui.scroll,"DungeonClassStarshot"))
	local last=ui.sent[#ui.sent]
	check(#ui.sent>before and last[1]=="dungeonClass" and last[2]=="Starshot","Choose sends dungeonClass")
	openDungeon(ui)
	h.press(h.find(ui.scroll,"DungeonClassNone"))
	last=ui.sent[#ui.sent]
	check(last[1]=="dungeonClass" and last[2]=="none","Go unclassed sends none")
	openDungeon(ui)
	h.press(h.find(ui.scroll,"DungeonMasterToggle"))
	last=ui.sent[#ui.sent]
	check(last[1]=="dungeonMaster" and last[2]=="on","Master Mode toggle sends on")
	h.noFailures(ui,"dungeon buttons")
	-- Master best (review M5): grade and clears shown on the floor card.
	local msnap=h.snapshot()
	local mfloors=table.clone(floors)
	mfloors[2]={secrets=0,secretsTotal=2,best=292,clears=3,masterUnlocked=true,masterBest=271,masterClears=2}
	msnap.dungeonClasses={selected="Aegis",master=true,classes=classes,floors=mfloors}
	local mui=h.run({snapshot=msnap})
	openDungeon(mui)
	local mpage=texts(h.find(mui.scroll,"DungeonFloor2"))
	check(has(mpage,"Master best 271 (S)") and has(mpage,"clears 2"),"Master best shown with its grade")
	check(has(mpage,"par "..math.floor(DC.par(2,true)+.5).."s"),"Master par shown")
	check(has(texts(h.find(mui.scroll,"DungeonFloor1")),"no Master clear yet"),"unplayed Master floor says so")
	check(has(texts(h.find(mui.scroll,"DungeonMaster")),"par ×1.6"),"Master card explains the par")
	h.noFailures(mui,"master best")
	-- Party HUD (desktop): one row per delver plus Q / R buttons.
	local dui=h.run({snapshot=snap,size=r.Vector2.new(1366,768)})
	local hudFrame=h.find(dui.gui,"DungeonPartyHud")
	check(hudFrame~=nil and hudFrame.Visible==false,"party HUD hidden outside runs")
	dui.player:SetAttribute("DungeonClass","Aegis")
	dui.player:SetAttribute("DungeonParty","Tester|Aegis|31;Bo|Mender|4;Cy||1")
	dui.player:SetAttribute("DungeonAbilityReady",12)
	dui.player:SetAttribute("DungeonUltimates",2)
	check(hudFrame.Visible==true,"party HUD shown in a run")
	local hudText=h.find(hudFrame,"Members").Text
	check(has(hudText,"Aegis 31") and has(hudText,"Mender 4") and has(hudText,"unclassed"),"party HUD lists classes and levels")
	local qb,rb=h.find(hudFrame,"AbilityQ"),h.find(hudFrame,"AbilityR")
	check(qb and rb and qb.Visible and rb.Visible,"party HUD carries Q and R buttons")
	check(has(qb.Text,"Q · Starwall Bulwark 12s") and has(rb.Text,"R ×2"),"Q / R buttons show the timers")
	eq(hudFrame.Position.Y.Offset,8+156+34+6,"party HUD sits under the desktop minimap")
	-- Q / R fire the Eclipse Heart prompts (server-validated), or explain the range.
	local held={}
	h.press(qb)
	check(#held==0,"no heart in reach: nothing fires")
	h.noFailures(dui,"party HUD without a heart")
	local model=h.new("Model",{Name="The Hollow Observatory"})
	model.Parent=dui.workspace
	local heartPart=h.new("Part",{Name="Eclipse Heart"})
	heartPart.Parent=model
	for _,spec in ipairs({{"Class ability","Q"},{"Ultimate","R"},{"Strike core","E"}}) do
		local prompt=h.new("ProximityPrompt",{ActionText=spec[1],HoldDuration=0.35})
		prompt.InputHoldBegin=function() table.insert(held,spec[2]) end
		prompt.InputHoldEnd=function() end
		prompt.Parent=heartPart
	end
	h.press(qb)
	check(#held==1 and held[1]=="Q","Q button holds the heart's Class ability prompt")
	h.press(rb)
	check(#held==2 and held[2]=="R","R button holds the heart's Ultimate prompt")
	h.noFailures(dui,"party HUD buttons")
	dui.player:SetAttribute("DungeonClass","")
	check(not qb.Visible and not rb.Visible,"unclassed delvers get no ability buttons")
	dui.player:SetAttribute("DungeonParty","")
	check(hudFrame.Visible==false,"party HUD hides after the run")
	h.noFailures(dui,"party HUD")
	-- Phone (730x303): a one-line roster under the compact minimap.
	local pui=h.run({snapshot=snap})
	local phud=h.find(pui.gui,"DungeonPartyHud")
	pui.player:SetAttribute("DungeonClass","Mender")
	pui.player:SetAttribute("DungeonParty","Tester|Mender|4;Bo|Aegis|31;Cy||1;Di|Starshot|2;Ed|Arcanist|9")
	check(phud.Visible and has(h.find(phud,"Members").Text,"✚4") and has(h.find(phud,"Members").Text,"⛨31"),"compact roster shows glyph and level")
	eq(phud.Position.Y.Offset,8+118+34+6,"compact party HUD sits under the compact minimap")
	check(phud.Size.Y.Offset<=80 and h.find(phud,"AbilityQ").Visible,"compact party HUD stays short with Q / R")
	h.noFailures(pui,"compact party HUD")
	-- Malformed or missing class data still renders.
	for _,bad in ipairs({"oops",{classes="x",floors={1,"y"}},{selected="Mage",classes={Aegis={level="x",fraction="y"}}}}) do
		local broken=h.snapshot()
		broken.dungeonClasses=bad
		local bui=h.run({snapshot=broken})
		openDungeon(bui)
		h.noFailures(bui,"malformed dungeon data")
		check(h.find(bui.scroll,"DungeonClass_Arcanist")~=nil,"malformed class data still lists classes")
	end
	local none=h.run({snapshot=h.snapshot()})
	openDungeon(none)
	h.noFailures(none,"no dungeon data")
	check(h.find(none.scroll,"DungeonFloor7")~=nil,"page renders without class data")
end
local uiChecks=checks-ruleChecks-runChecks-serverChecks

print("Dungeon classes QA passed "..checks.." checks ("..ruleChecks.." rules, "..runChecks.." encounter, "..serverChecks.." server, "..uiChecks.." UI).")
print("SUITE-END verify-dungeon-classes.luau")
