-- Dungeon endgame QA (Observatory Floors VI-VII depth, Master Mode I-VII,
-- essence upgrades, bonus chests, run log, credit rules).
-- Part 1: pure rules in shared/GameData.lua (Data.DungeonEndgame + the Master
--         Mode scaling in Data.DungeonClasses + the Gear.Layers hook), with the
--         balance model printed and bounded.
-- Part 2: expedition.server.lua with deterministic players, signals and time:
--         gear-score gates, Mirror Gallery, Star Chart, boss phases and role
--         mechanics, Constellation Lock, run ids, Minigames-style credit,
--         rejoin and leak-free cleanup.
-- Part 3: server.server.lua Delve block (grant, bonus chest, Master stars,
--         Essence Exchange, run log, persistence) through the verify-gameplay
--         harness.
-- Part 4: ui.client.lua Hunt > Dungeon endgame cards and Hunt > Essence through
--         the verify-ui harness.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local r=require("@lune/roblox")
local Data=luau.load(fs.readFile("shared/GameData.lua"),{debugName="GameData"})()
local Progression=luau.load(fs.readFile("shared/Progression.lua"),{debugName="Progression",environment={script=nil},injectGlobals=true})()
Progression.useData(Data)
local DC=Data.DungeonClasses
local EG=Data.DungeonEndgame
local G=Data.Gear
local checks=0
local function check(condition,label) assert(condition,label) checks+=1 end
local function eq(actual,expected,label) assert(actual==expected,label.." expected "..tostring(expected)..", got "..tostring(actual)) checks+=1 end
local function near(actual,expected,label,tol) assert(math.abs(actual-expected)<=(tol or 1e-9),label.." expected "..tostring(expected)..", got "..tostring(actual)) checks+=1 end
local function has(text,part) return type(text)=="string" and text:find(part,1,true)~=nil end

------------------------------------------------------------------------------
-- Part 1: rules.
------------------------------------------------------------------------------
do
	check(type(EG)=="table","Data.DungeonEndgame exists")
	-- Items: original names, dungeon gear model, Master-only flags.
	local newItems={"LodestarKey","EclipsedStarcore","DuskwardenCowl","DuskwardenHauberk","DuskwardenTassets","DuskwardenSabatons","ColossusLumenbrand","SovereignNightfall","Thronebreaker","SovereignHalo"}
	for _,id in ipairs(newItems) do
		local def=Data.Items[id]
		check(def and def.id==id and type(def.name)=="string" and type(def.description)=="string" and def.value>0,id.." defined")
		check(Data.Recipes[id]==nil,id.." cannot be crafted")
		for _,banned in ipairs({"Catacomb","Necron","Wither","Livid","Sadan","Xeric","Olm","Hypixel","Bonzo","Scarf"}) do
			check(not has(def.name,banned) and not has(def.description,banned),id.." name is original ("..banned..")")
		end
	end
	for _,id in ipairs({"Thronebreaker","SovereignHalo","EclipsedStarcore"}) do eq(Data.Items[id].masterOnly,true,id.." is Master-only") end
	local set=Data.Sets.Duskwarden
	check(set and #set.pieces==4 and set.bonus.strength>0,"Duskwarden Regalia set of four")
	for _,id in ipairs(set.pieces) do
		local d=Data.Items[id]
		check(d.kind=="armor" and d.dungeon==true and d.set=="Duskwarden" and d.rarity=="Legendary" and d.requires.Dungeoneering>=40,id.." is Legendary dungeon armor (Dungeoneering 40+)")
		check(d.stats.defense>Data.Items.ObservatoryHelm.stats.defense,id.." outclasses Starwright armor")
	end
	-- Stat model: below the Combat-60 Crown crafts, above Floor V's Astrarch Fang.
	local fang,lumen,night,throne=Data.Items.AstrarchFang,Data.Items.ColossusLumenbrand,Data.Items.SovereignNightfall,Data.Items.Thronebreaker
	check(fang.stats.damage<lumen.stats.damage and lumen.stats.damage<night.stats.damage and night.stats.damage<throne.stats.damage,"weapon damage climbs V < VI < VII < Master")
	check(throne.stats.damage<Data.Items.Crownbreaker.stats.damage and night.stats.damage<Data.Items.SovereignGreatblade.stats.damage,"dungeon weapons stay under the Crown endgame crafts")
	check(throne.rarity=="Mythic" and throne.requires.Dungeoneering==50,"Thronebreaker: Mythic, Dungeoneering 50")
	-- Chests: normal VI-VII rows, Master-only rows only in Master Mode.
	local function rows(list) local t={} for _,d in ipairs(list) do t[d.item]=d end return t end
	local c6,c7=rows(Data.DungeonFloors[6].chest),rows(Data.DungeonFloors[7].chest)
	check(c6.DuskwardenCowl and c6.ColossusLumenbrand and c6.LodestarKey and not c6.SovereignNightfall,"Floor VI chest uniques")
	check(c7.DuskwardenHauberk and c7.SovereignNightfall and c7.ColossusLumenbrand,"Floor VII chest uniques")
	for f=1,#Data.DungeonFloors do
		for _,d in ipairs(Data.DungeonFloors[f].chest) do check(not Data.Items[d.item].masterOnly,"Floor "..f.." normal chest has no Master-only "..d.item) end
		local m=rows(EG.MasterChest[f])
		check(m.EclipsedStarcore and m.LodestarKey,"Master Floor "..f.." chest: Starcore and key")
		eq(m.SovereignHalo~=nil,f>=5,"Sovereign Halo from Master V+ only (floor "..f..")")
		eq(m.Thronebreaker~=nil,f>=6,"Thronebreaker from Master VI+ only (floor "..f..")")
		local normal=rows(DC.runRewards(f,"A",{}).chest)
		local master=rows(DC.runRewards(f,"A",{master=true}).chest)
		check(normal.EclipsedStarcore==nil and master.EclipsedStarcore~=nil,"Floor "..f.." Starcore only on Master clears")
		if f>1 then check(m.EclipsedStarcore.chance>EG.MasterChest[f-1][1].chance,"Starcore chance rises with the floor "..f) end
	end
	-- Collection Log: the new uniques are Dungeons entries.
	local L=Data.CommissionsLogs.log(true)
	for _,id in ipairs({"Thronebreaker","SovereignHalo","SovereignNightfall","ColossusLumenbrand","DuskwardenHauberk"}) do eq(L.Of[id],"Dungeons",id.." is a Dungeons log entry") end

	-- Master Mode I-VII.
	eq(DC.MASTER_FLOORS,7,"Master Mode covers floors I-VII")
	eq(DC.MASTER_UNLOCK_GRADE,"S","unlocked by a grade S clear")
	check(DC.masterUnlocked(7,Data.DungeonGradeById.S.min) and not DC.masterUnlocked(7,Data.DungeonGradeById.S.min-1),"S threshold")
	for f=1,7 do
		local sc=DC.masterScale(f)
		check(sc.hp>=2 and sc.damage>=2 and sc.xp>sc.hp and sc.par>=1.6,"Floor "..f.." Master scaling (XP outpaces HP)")
		local n,m=DC.floorStats(f,false),DC.floorStats(f,true)
		check(m.coreHp>n.coreHp*1.9 and m.par>n.par,"Floor "..f.." Master is harder")
	end
	near(DC.masterScale(7).hp,3.2,"Floor VII Master HP x3.2")
	near(DC.masterScale(7).xp,4,"Floor VII Master XP x4")
	local plain7,master7=DC.runRewards(7,"S",{}),DC.runRewards(7,"S",{master=true})
	eq(master7.items.ObservatoryEssence,math.floor(plain7.items.ObservatoryEssence*EG.MASTER_ESSENCE),"Master essence x"..EG.MASTER_ESSENCE)
	eq(master7.rolls,2,"Master extra chest roll on Floor VII")

	-- Gear score and gates.
	local starwright={equipment={weapon="AstrarchFang",helmet="ObservatoryHelm",chest="ObservatoryVestment",legs="ObservatoryGreaves",boots="ObservatoryTreads"}}
	eq(EG.itemScore({},"AstrarchFang"),80+30,"item score: Legendary 80 + level 30")
	eq(EG.itemScore({},"ObservatoryHelm"),55+5,"item score: Epic 55 + level 5")
	eq(EG.gearScore(starwright),110+60+67+67+60,"Floor V kit gear score")
	check(EG.gearScore(starwright)>=EG.gearGate(6,false) and EG.gearScore(starwright)<EG.gearGate(7,false),"Floor V kit opens VI, not VII")
	local starred={equipment=starwright.equipment,stars={AstrarchFang=5,ObservatoryHelm=2},reforges={AstrarchFang="Honed"},books={AstrarchFang={tempering=3}}}
	eq(EG.gearScore(starred),EG.gearScore(starwright)+7*EG.STAR_SCORE+EG.REFORGE_SCORE+3*EG.TOME_SCORE,"stars, reforge and tomes raise the score")
	eq(EG.gearScore({equipment=starwright.equipment,items={AstrarchFang=1}}),110,"unowned pieces score 0")
	eq(EG.gearScore({equipment={weapon="ObservatoryHelm"}}),0,"wrong-slot items score 0")
	eq(EG.gearScore(nil),0,"no profile")
	local melee={equipment={weapon="Riftcleaver"}}
	local bow={equipment={weapon="StarpiercerLongbow"}}
	local staff={equipment={weapon="OrreryStaff"}}
	check(EG.gearScore(melee)==EG.gearScore(bow) and EG.gearScore(bow)==EG.gearScore(staff),"gear score is style-agnostic")
	for f=1,7 do
		for _,master in ipairs({false,true}) do
			check(EG.gearGate(f,master)>=0 and (not master or EG.gearGate(f,true)>=EG.gearGate(f,false)),"Floor "..f.." gates ordered")
		end
	end
	eq(EG.gearGate(1,false),0,"Floor I needs no gear")
	check(EG.gearGate(7,true)>EG.gearGate(7,false) and EG.gearGate(7,false)>EG.gearGate(6,false),"gates climb")
	local ok,why=EG.floorAccess(6,false,39,999,0) check(not ok and why=="level","level gate first")
	ok,why=EG.floorAccess(6,false,40,10,0) check(not ok and why=="gear","gear gate")
	ok,why=EG.floorAccess(6,true,40,999,250) check(not ok and why=="master","Master unlock gate")
	ok,why=EG.floorAccess(6,true,40,EG.gearGate(6,true),260) check(ok,"Master VI opens with S and gear")
	ok,why=EG.floorAccess(6,true,40,EG.gearGate(6,true)-1,260) check(not ok and why=="gear","Master gear gate")
	check(has(EG.accessText(7,true,"gear"),tostring(EG.gearGate(7,true))),"gate text names the score")

	-- Master stars through the Gear.Layers hook.
	check(EG.canMasterStar(Data.Items.AstrarchFang) and EG.canMasterStar(Data.Items.DuskwardenCowl),"dungeon gear takes Master stars")
	check(not EG.canMasterStar(Data.Items.UmbralOrrery) and not EG.canMasterStar(Data.Items.Crownbreaker),"accessories and non-dungeon gear do not")
	local g={stars={AstrarchFang=4},masterStars={AstrarchFang=3}}
	eq(EG.masterStarsOf(g,"AstrarchFang"),3,"master stars read")
	local okStar,whyStar=EG.masterStarCheck(g,"AstrarchFang")
	check(not okStar and has(whyStar,"5 regular stars"),"Master stars need five stars")
	g.stars.AstrarchFang=5
	check(EG.masterStarCheck(g,"AstrarchFang"),"five stars open Master stars")
	local b=G.breakdown(g,"AstrarchFang")
	eq(b.masterStars,3,"breakdown carries masterStars")
	near(b.masterStarsStats.damage,230*0.04*3,"each Master star adds 4% of base damage")
	near(b.total.damage,230*0.04*5+230*0.04*3,"stars and Master stars sum",0.11)
	eq(Progression.upgradeStats(g,"AstrarchFang").damage,b.total.damage,"Progression.upgradeStats sees Master stars (no Progression edit needed)")
	check(G.isUpgraded({masterStars={AstrarchFang=1}},"AstrarchFang"),"a Master star counts as an upgrade (no auction)")
	check(has(G.displayName(g,"AstrarchFang"),"★★★★★✪✪✪"),"display name shows ✪")
	eq(EG.masterStarsOf({masterStars={Crownbreaker=5}},"Crownbreaker"),0,"non-dungeon Master stars ignored")
	eq(EG.masterStarsOf({masterStars={AstrarchFang=99}},"AstrarchFang"),5,"Master stars clamp")
	eq(G.breakdown({},"AstrarchFang").masterStars,0,"no Master stars by default")
	local cost1,cost5=EG.masterStarCost(Data.Items.AstrarchFang,1),EG.masterStarCost(Data.Items.AstrarchFang,5)
	check(cost1.amount==200 and cost1.cores==1 and cost1.coins==5000,"Master star 1 cost (Legendary x2 essence)")
	check(cost5.amount==800 and cost5.cores==3 and cost5.coins==125000,"Master star 5 cost")
	eq(EG.masterStarCost(Data.Items.AstrarchFang,6),nil,"no sixth Master star")
	local p={equipment={weapon="AstrarchFang"},items={AstrarchFang=1},stars={AstrarchFang=5},masterStars={},xp={Combat=Progression.xpForLevel(50),Dungeoneering=Progression.xpForLevel(50)}}
	local before=Progression.computeStats(p,0)
	p.masterStars.AstrarchFang=5
	local after=Progression.computeStats(p,0)
	check(after.strength>before.strength,"computeStats includes Master stars")

	-- Rooms.
	eq(#EG.roomsFor(5),0,"Floor V has no new rooms")
	eq(EG.nextStage(5,"prisms"),"guardians","Floor V prisms lead to the sentinels")
	eq(EG.nextStage(6,"prisms"),"mirrors","Floor VI prisms lead to the Mirror Gallery")
	eq(EG.nextStage(6,"mirrors"),"guardians","then the sentinels")
	eq(EG.nextStage(7,"mirrors"),"chart","Floor VII adds the Star Chart (cumulative)")
	eq(EG.nextStage(7,"chart"),"guardians","then the sentinels")
	eq(Data.DungeonFloors[7].mechanics.rooms[1],"mirrors","Floor VII keeps Floor VI's room")
	for seed=0,40 do
		local t,s0=EG.mirrorTargets(seed),EG.mirrorStart(seed)
		for i=1,EG.MIRRORS do
			check(t[i]>=0 and t[i]<=3 and s0[i]~=t[i],"seed "..seed.." mirror "..i.." starts off target")
		end
		eq(EG.beamReach(s0,t),0,"seed "..seed.." beam starts dark")
		local seq=EG.chartSequence(seed,5)
		eq(#seq,5,"chart length")
		for i=2,5 do check(seq[i]~=seq[i-1],"seed "..seed.." chart never repeats a plate") end
		for i=1,5 do check(seq[i]>=1 and seq[i]<=EG.CHART_PLATES,"plate in range") end
		eq(table.concat(EG.chartSequence(seed,5),","),table.concat(seq,","),"chart deterministic")
	end
	local distinct={}
	for seed=0,20 do distinct[table.concat(EG.chartSequence(seed,4),",")]=true end
	local nd=0 for _ in distinct do nd+=1 end
	check(nd>=12,"charts vary between runs ("..nd..")")
	local st,tg={1,2,3,0},{1,2,0,0}
	eq(EG.beamReach(st,tg),2,"beam reaches two")
	local _,mistake=EG.turnMirror(st,tg,1)
	check(mistake and st[1]==2,"turning a lit mirror is a mistake")
	_,mistake=EG.turnMirror(st,tg,4)
	check(not mistake,"turning a dark mirror is not")
	eq(EG.chartLength(false),4,"chart of 4") eq(EG.chartLength(true),5,"Master chart of 5")
	check(has(EG.chartText({1,2}),"☼ ☾"),"chart glyph text")

	-- Phases and role mechanics.
	eq(select(1,EG.phaseAt(6,1)),1,"VI starts in phase 1")
	eq(select(1,EG.phaseAt(6,0.61)),1,"VI phase 1 above 60%")
	eq(select(1,EG.phaseAt(6,0.6)),2,"VI phase 2 at 60%")
	local i7,p7=EG.phaseAt(7,0.3)
	check(i7==3 and p7.lock=="chart","VII final phase seals with the Constellation Lock")
	eq(select(1,EG.phaseAt(7,0.5)),2,"VII phase 2")
	eq(select(1,EG.phaseAt(5,0.1)),0,"no phases before VI")
	for f=6,7 do
		local roles={}
		for _,ph in ipairs(EG.Bosses[f].phases) do
			for kind in pairs(ph.every) do roles[EG.Mechanics[kind].role]=true end
			if ph.lock then roles.Puzzle=true end
		end
		check(roles.Tank and roles.Healer,"Floor "..f.." checks tank and healer")
		if f==7 then check(roles.Damage and roles.Puzzle,"Floor VII adds damage and puzzle checks") end
	end
	local target=EG.verdictTarget({{key="a",class="Riftblade",damage=90,alive=true},{key="b",class="Aegis",damage=5,alive=true},{key="c",class="Aegis",damage=9,alive=true}})
	eq(target.key,"c","Verdict taunted by the Aegis with the most damage")
	target=EG.verdictTarget({{key="a",class="Riftblade",damage=90,alive=true},{key="b",class="Aegis",damage=5,alive=false}})
	eq(target.key,"a","no living Aegis: the top damage dealer")
	eq(EG.verdictTarget({}),nil,"nobody to target")
	eq(EG.mechDamage("verdict",1000,false,1),450,"verdict 45% of max health")
	eq(EG.mechDamage("verdict",1000,false,0.5),225,"Aegis mitigation halves the verdict")
	eq(EG.mechDamage("verdict",1000,true,1),585,"Master mechanics +30%")
	eq(EG.mechDamage("blight",1000,false,1),40,"blight 4% per tick")
	eq(EG.mechDamage("nova",100,false,1),70,"nova 70%")
	eq(EG.mechDamage("lock",100,false,1),0,"the lock deals no damage")
	eq(EG.novaThreshold(120),6,"nova breaks at 5% of the core")
	eq(EG.novaThreshold(5),1,"nova threshold at least 1")

	-- Credit (Minigames-style).
	eq(EG.median({5,1,3}),3,"median odd") eq(EG.median({4,1,3,2}),2.5,"median even") eq(EG.median({}),0,"median empty")
	check(EG.creditCheck({points=30,total=100,median=30,partySize=3,lastAction=10,now=20}),"normal credit")
	check(not EG.creditCheck({points=5,total=100,median=30,partySize=3,lastAction=10,now=20}),"under 10% refused")
	local okm,whym=EG.creditCheck({points=11,total=100,median=45,partySize=3,lastAction=10,now=20})
	check(not okm and whym=="median","under 25% of the median refused in parties of 3+")
	check(EG.creditCheck({points=11,total=100,median=45,partySize=2,lastAction=10,now=20}),"median rule only for 3+")
	local okr,whyr=EG.creditCheck({points=50,total=100,median=50,partySize=1,lastAction=10,now=10+EG.RECENT_SECONDS+1})
	check(not okr and whyr=="recent","stale contribution refused")
	check(not EG.creditCheck(nil),"no payload")

	-- Bonus chest.
	for f=1,7 do
		for _,master in ipairs({false,true}) do
			local plan=EG.bonusPlan(f,"S",master)
			eq(plan.cost,EG.bonusCost(f,master),"Floor "..f.." bonus cost")
			eq(plan.drops[1].item,"ObservatoryEssence","Floor "..f.." bonus chest essence first")
			eq(plan.drops[1].chance,1,"essence guaranteed")
			local ev=EG.expectedValue(plan.drops)
			local ratio=ev/plan.cost
			check(ratio>=0.6 and ratio<=0.85,"Floor "..f..(master and " Master" or "").." bonus chest EV/cost "..string.format("%.2f",ratio).." (blind opening loses coins)")
			local hasMaster=false
			for _,d in ipairs(plan.drops) do
				check(d.chance>0 and d.chance<=1,"chance bounded")
				if Data.Items[d.item].masterOnly then hasMaster=true end
			end
			eq(hasMaster,master,"Floor "..f.." Master-only bonus rows only in Master Mode")
		end
		check(EG.bonusCost(f,true)>EG.bonusCost(f,false),"Master chest costs more")
		if f>1 then check(EG.bonusCost(f,false)>EG.bonusCost(f-1,false),"bonus cost climbs") end
	end
	local planS,planD=EG.bonusPlan(7,"S",false),EG.bonusPlan(7,"D",false)
	check(EG.expectedValue(planS.drops)>EG.expectedValue(planD.drops),"better grades fill the bonus chest")

	-- Run log, weekly bests, personal bests, migration.
	local now=EG.WEEK*3000+100
	local d=EG.migrate(nil,now)
	check(#d.log==0 and d.week.id==EG.weekOf(now) and next(d.pb)==nil and d.chest==nil and #d.runs==0,"fresh endgame record")
	local r1=EG.record(d,7,true,"S",270,600,1,now)
	check(r1.bounty==EG.bounty(7,true) and r1.weeklyBest and r1.pb,"first Master VII clear: bounty, weekly best, PB")
	local r2=EG.record(d,7,true,"A",240,500,0,now+10)
	check(r2.bounty==0 and not r2.weeklyBest and not r2.pb,"lower score: no bounty, no best")
	local r3=EG.record(d,7,true,"S",270,550,0,now+20)
	check(r3.pb and d.pb["7m"].seconds==550,"same score, faster: new PB")
	local r4=EG.record(d,7,false,"B",200,500,0,now+30)
	check(r4.bounty==EG.bounty(7,false) and d.week.best["7"]==200,"normal and Master tracked separately")
	eq(d.log[1].s,200,"log newest first")
	for i=1,20 do EG.record(d,1,false,"B",180,200,0,now+40+i) end
	eq(#d.log,EG.LOG_LIMIT,"log capped")
	local r5=EG.record(d,7,true,"B",180,900,0,now+EG.WEEK)
	check(r5.bounty>0 and r5.weeklyBest,"new week: bounty again")
	check(d.week.best["7"]==nil,"weekly bests reset")
	eq(d.pb["7m"].score,270,"personal bests persist across weeks")
	check(EG.rememberRun(d,"job:1:1") and not EG.rememberRun(d,"job:1:1"),"a run id is credited once")
	for i=2,20 do EG.rememberRun(d,"job:"..i) end
	eq(#d.runs,EG.RUN_MEMORY,"run memory bounded")
	check(EG.rememberRun(d,nil),"legacy payloads without run ids pass")
	local dirty=EG.migrate({log={{t=1,f=99},{t="x",f=2,m=1,g="Z",s=999,sec=-5,d=500},"bad"},week={id=EG.weekOf(now),best={["7m"]=500,["9"]=1,x=2},bounty={["1"]=true,["2"]="y"}},
		pb={["7"]={score=280,seconds=400},["8m"]={score=1,seconds=1},["3"]={score="x"}},chest={floor=7,master=true,grade="S",items={StarFragment=2,Nope=1,ObservatoryEssence=-3},cost=7000,expires=now+60},runs={"a",5,string.rep("x",80)}},now)
	eq(#dirty.log,1,"bad log rows dropped")
	check(dirty.log[1].f==2 and dirty.log[1].m==false and dirty.log[1].g=="D" and dirty.log[1].s==300 and dirty.log[1].sec==0 and dirty.log[1].d==99,"log row sanitised")
	check(dirty.week.best["7m"]==300 and dirty.week.best["9"]==nil and dirty.week.best.x==nil,"weekly best sanitised")
	check(dirty.week.bounty["1"]==true and dirty.week.bounty["2"]==nil,"bounty flags sanitised")
	check(dirty.pb["7"].score==280 and dirty.pb["8m"]==nil and dirty.pb["3"]==nil,"PBs sanitised")
	check(dirty.chest and dirty.chest.items.StarFragment==2 and dirty.chest.items.Nope==nil and dirty.chest.items.ObservatoryEssence==nil,"chest items sanitised")
	check(#dirty.runs==1 and dirty.runs[1]=="a","run ids sanitised")
	eq(EG.migrate({chest={floor=7,items={StarFragment=1},cost=1,expires=now-1}},now).chest,nil,"expired chest dropped on load")
	eq(next(EG.migrate({week={id=1,best={["7"]=200}}},now).week.best),nil,"stale week dropped on load")
	eq(EG.key(7,true),"7m","key")
	check(EG.validKey("7m") and EG.validKey("1") and not EG.validKey("8") and not EG.validKey("m"),"key validation")

	-- Balance model: Dungeoneering XP/h and coins/h against the other endgame activities.
	local MG=Data.Minigames
	local E=Data.Endgame
	print(string.format("%-5s %6s %6s %9s %9s %9s %8s %9s %8s %7s","floor","secs","runs/h","dungXP/h","cmbXP/h","coins/h","ess/h","chest/h","bonusEV","cost"))
	local rates={}
	for f=1,7 do
		for _,master in ipairs({false,true}) do
			local x=EG.model(f,master,"S")
			rates[EG.key(f,master)]=x
			print(string.format("%-5s %6.0f %6.1f %9.0f %9.0f %9.0f %8.0f %9.0f %8.0f %7d",(master and "M" or "")..f,x.seconds,x.runsPerHour,x.dungeoneeringXp,x.combatXp,x.coins,x.essence,x.chestValue,x.bonusValue,x.bonusCost))
		end
	end
	local grind50,grind60=MG.soloCombatXpPerHour(50),MG.soloCombatXpPerHour(60)
	local coins60=MG.SOLO.killsPerHour*MG.bestMonster(60).coins
	local nyx=E.boss("Nyxwyrm")
	print(string.format("reference: solo Combat XP/h at 50 = %d, at 60 = %d; coins/h at 60 = %d; Nyxwyrm 10%% share = %d coins + %d Combat XP per fight (once per isle day)",
		grind50,grind60,coins60,E.bossCoins("Nyxwyrm",0.1),math.floor(nyx.xp*0.1)))
	for f=1,7 do
		local n,m=rates[EG.key(f,false)],rates[EG.key(f,true)]
		local ratio=m.dungeoneeringXp/n.dungeoneeringXp
		check(ratio>=1 and ratio<=1.6,"Floor "..f.." Master XP/h is 1-1.6x normal ("..string.format("%.2f",ratio)..")")
		check(m.essence>=n.essence*0.95,"Floor "..f.." Master essence/h keeps pace ("..math.floor(m.essence).." vs "..math.floor(n.essence)..")")
		if f>1 then check(n.dungeoneeringXp>rates[EG.key(f-1,false)].dungeoneeringXp,"Floor "..f.." pays more Dungeoneering XP/h than the floor above") end
	end
	local f7,m7=rates["7"],rates["7m"]
	check(f7.combatXp<grind50,"Floor VII Combat XP/h stays under solo grinding at Combat 50 (dungeons pay in Dungeoneering)")
	check(m7.combatXp<grind60,"Master VII Combat XP/h stays under solo grinding at Combat 60")
	check(f7.combatXp+f7.dungeoneeringXp>=0.5*grind50,"Floor VII total XP/h is worth the time")
	check(f7.coins<=coins60*1.25,"Floor VII coins/h close to Combat-60 grinding ("..math.floor(f7.coins).." vs "..coins60..")")
	check(m7.coins+m7.chestValue<=3*coins60,"Master VII coins + chest value/h bounded")
	-- Master star path in hours of the essence-richest floor.
	local fullEssence,fullCores=0,0
	for k=1,EG.MASTER_STAR_MAX do local c=EG.masterStarCost(Data.Items.SovereignNightfall,k) fullEssence+=c.amount fullCores+=c.cores end
	local best=0 for _,x in pairs(rates) do best=math.max(best,x.essence) end
	local hours=fullEssence/best
	local coreRate=0
	for _,row in ipairs(EG.MasterChest[7]) do if row.item=="EclipsedStarcore" then coreRate=row.chance*2*m7.runsPerHour end end
	print(string.format("Master stars 1-5 on a Legendary: %d essence (%.1f h at the best essence rate), %d Starcores (%.1f h of Master VII), %d coins",fullEssence,hours,fullCores,fullCores/coreRate,5000*(1+4+9+16+25)))
	check(hours>=5 and hours<=40,"a full Master star set takes 5-40 hours of essence")
	check(fullCores/coreRate>=5 and fullCores/coreRate<=60,"Starcores for a full set take 5-60 Master VII hours")
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
	local infos,payloads,grants={},{},{}
	local bridge={Invoke=function(_,op,p,payload)
		local i=infos[p.Name] or {}
		if op=="dungeon" then return {level=i.level or 1,ironman=false,class=i.class,classXp=i.classXp or {},best=i.best or {},master=false,gearScore=i.gearScore or 0} end
		if op=="dungeonClass" then return {ok=true} end
		return nil
	end}
	local grant={Invoke=function(_,p,payload) grants[p.Name]=(grants[p.Name] or 0)+1 payloads[p.Name]=payload return {ok=true} end}
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
	local hums,roots,byName={},{},{}
	local count=0
	local function makeChar(p)
		local root={Position=r.Vector3.new(0,0,900)}
		local hum={Health=100,MaxHealth=100}
		function hum:TakeDamage(n) self.Health=math.max(0,self.Health-n) end
		local char={}
		function char:FindFirstChild(name) if name=="HumanoidRootPart" then return root end end
		function char:FindFirstChildOfClass(name) if name=="Humanoid" then return hum end end
		function char:PivotTo(cf) root.Position=cf.Position end
		p.Character=char
		hums[p],roots[p]=hum,root
	end
	local function player(info,name)
		count+=1
		name=name or ("Delver"..count)
		local p={Name=name,CharacterRemoving=signal(),CharacterAdded=signal(),attributes={}}
		function p:SetAttribute(k,v) self.attributes[k]=v end
		function p:GetAttribute(k) return self.attributes[k] end
		makeChar(p)
		if info then infos[name]=info end
		byName[name]=p
		players.PlayerAdded:Fire(p)
		return p
	end
	local function promptFor(partName,action)
		for _,obj in world:GetDescendants() do
			if obj:IsA("ProximityPrompt") and obj.Parent.Name==partName and obj.ActionText==action then return obj end
		end
		error("Missing prompt "..partName.." / "..action)
	end
	local function promptIn(part) for _,o in part:GetChildren() do if o:IsA("ProximityPrompt") then return o end end return nil end
	local function fire(p,prompt) roots[p].Position=prompt.Parent.Position now+=1 signals[prompt]:Fire(p) end
	local function use(p,partName,action) fire(p,promptFor(partName,action)) end
	local core=world:FindFirstChild("Eclipse Heart",true)
	local caption=world:FindFirstChild("TextLabel",true)
	local arena=world:FindFirstChild("The Hollow Observatory")
	local lectern=world:FindFirstChild("Star chart lectern",true)
	local receiver=world:FindFirstChild("Beam receiver",true)
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
	local function inRun(p) return p:GetAttribute("DungeonInRun")==true end
	local pylons={}
	for _,obj in world:GetDescendants() do if obj:IsA("ProximityPrompt") and obj.Parent.Name=="Resonance prism" then table.insert(pylons,obj) end end
	local function tuneAll(p)
		local list=table.clone(pylons)
		table.sort(list,function(x,y) return x.Parent:GetAttribute("TuneOrder")<y.Parent:GetAttribute("TuneOrder") end)
		for _,prism in list do roots[p].Position=prism.Parent.Position now+=1 signals[prism]:Fire(p) end
	end
	local mirrorParts={}
	for _,o in arena:GetChildren() do if o.Name=="Gallery mirror" then table.insert(mirrorParts,o) end end
	table.sort(mirrorParts,function(a,b) return a:GetAttribute("MirrorIndex")<b:GetAttribute("MirrorIndex") end)
	local plateParts={}
	for _,o in arena:GetChildren() do if o.Name=="Glyph plate" then table.insert(plateParts,o) end end
	table.sort(plateParts,function(a,b) return a:GetAttribute("PlateIndex")<b:GetAttribute("PlateIndex") end)
	local function lit() local n=0 for _,m in mirrorParts do if m:GetAttribute("VisualState")=="Lit" then n+=1 end end return n end
	local function turn(p,i) fire(p,promptIn(mirrorParts[i])) end
	local function solveMirrors(p)
		for _=1,20 do
			if not has(caption.Text,"MIRROR GALLERY") then return end
			for _,m in mirrorParts do if m:GetAttribute("VisualState")~="Lit" then fire(p,promptIn(m)) break end end
		end
	end
	local function chartSeq()
		local seq={}
		for g in string.gmatch(lectern:GetAttribute("ChartSequence") or "","%S+") do table.insert(seq,g) end
		return seq
	end
	local function plateFor(glyph) for _,pl in plateParts do if pl:GetAttribute("Glyph")==glyph then return pl end end end
	local function pressNext(p)
		local want=chartSeq()[lectern:GetAttribute("ChartStep")]
		fire(p,promptIn(plateFor(want)))
	end
	local function solveChart(p) for _=1,10 do if lectern:GetAttribute("ChartSequence")=="" then return end pressNext(p) end end
	local function heal(p) hums[p].Health=100 end
	local function at(p,offset) roots[p].Position=core.Position+(offset or r.Vector3.zero) end
	local function strike(p,partName,action) heal(p) fire(p,promptFor(partName,action)) end
	local function guardiansDown(list)
		for index=1,2 do
			local sentinel=world:FindFirstChild("Sentinel "..index,true)
			for _=1,400 do
				if sentinel:GetAttribute("VisualState")=="Defeated" then break end
				for _,p in list do if sentinel:GetAttribute("VisualState")~="Defeated" then strike(p,"Sentinel "..index,"Strike guardian") end end
			end
		end
	end
	local corePrompt=promptFor("Eclipse Heart","Strike core")
	local function hitCore(p,n) for _=1,n do if not has(caption.Text,"•  ") or not inRun(p) then return end heal(p) fire(p,corePrompt) end end
	local function ability(p,kind)
		at(p,r.Vector3.new(0,0,-6))
		now+=0.5
		signals[promptFor("Eclipse Heart",if kind=="ultimate" then "Ultimate" else "Class ability")]:Fire(p)
	end
	local function wispList() local l={} for _,o in arena:GetChildren() do if o.Name=="Umbral wisp" then table.insert(l,o) end end return l end
	local function clearWisps(p) for _=1,50 do local l=wispList() if #l==0 then return end fire(p,promptIn(l[1])) end end
	-- One action for a delver in the boss phase: retune, replay the chart, clear wisps, or strike.
	local function act(p)
		if not inRun(p) then return end
		heal(p)
		local text=caption.Text
		if has(text,"Retune") then tuneAll(p)
		elseif has(text,"Replay the star chart") then pressNext(p)
		else
			local l=wispList()
			if #l>0 then fire(p,promptIn(l[1])) else fire(p,corePrompt) end
		end
	end
	local function fight(list,done,limit)
		for _=1,limit or 400 do
			if done() then return end
			for _,p in list do if not done() then act(p) end end
			heartbeat:Fire(0.05)
		end
	end
	local baseline=#arena:GetDescendants()

	-- Gear-score gates at the dais, the gate and the pad.
	local weak=player({level=50,gearScore=120})
	use(weak,"Observatory Floor VI","Select floor")
	check(has(noticeOf(weak),"gear score "..EG.gearGate(6,false)) and has(noticeOf(weak),"yours is 120"),"dais refuses a low gear score")
	eq(world:FindFirstChild("Observatory Floor VII",true):GetAttribute("RequiredGearScore"),EG.gearGate(7,false),"dais shows the gear gate")
	local strong=player({level=50,gearScore=450})
	use(strong,"Observatory Floor VII","Select floor")
	check(has(noticeOf(strong),"selected"),"dais accepts enough gear")
	launch({strong,weak})
	check(inRun(strong) and not inRun(weak),"pad refuses the under-geared delver")
	check(has(noticeOf(weak),"gear score"),"under-geared delver told why")
	use(strong,"Return arch","Leave expedition")
	now+=100
	-- Master VII needs its own S and the Master gate.
	local mst=player({level=50,gearScore=EG.gearGate(7,true)-1,best={[7]=265}})
	mst:SetAttribute("DungeonMasterOn",true)
	use(mst,"Observatory Floor VII","Select floor")
	clearPad() onPad(mst)
	signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(mst)
	check(has(noticeOf(mst),"Master Mode") and has(noticeOf(mst),"gear score "..EG.gearGate(7,true)),"Master VII gear gate at the gate")
	infos[mst.Name].gearScore=EG.gearGate(7,true)
	signals[promptFor("ExpeditionGate","Enter expedition")]:Fire(mst)
	now+=Data.Dungeons.padSeconds
	heartbeat:Fire(0)
	check(inRun(mst) and core:GetAttribute("MasterMode")==true and core:GetAttribute("BossMaxHealth")==DC.floorStats(7,true).coreHp,"Master Mode Floor VII launches (x"..DC.masterScale(7).hp.." core)")
	use(mst,"Return arch","Leave expedition")
	mst:SetAttribute("DungeonMasterOn",false)
	now+=100

	-- Floor VI: Mirror Gallery (mistakes), phases, Verdict taunt, Withering Lumen cleanse.
	local aegis=player({level=40,gearScore=400,class="Aegis"})
	local mender=player({level=40,gearScore=400,class="Mender"})
	local rift=player({level=40,gearScore=400,class="Riftblade"})
	use(aegis,"Observatory Floor VI","Select floor")
	launch({aegis,mender,rift})
	local runId=nil
	check(inRun(aegis) and inRun(mender) and inRun(rift),"Floor VI party launched")
	for _,m in mirrorParts do check(not promptIn(m).Enabled,"mirrors dormant during the prisms") end
	tuneAll(aegis)
	check(has(caption.Text,"MIRROR GALLERY") and has(caption.Text,"0 / 4 lit"),"Mirror Gallery after the prisms")
	for _,m in mirrorParts do check(promptIn(m).Enabled,"mirror prompts enabled") end
	-- Light the first mirror, then turn it again: a mistake that breaks the beam.
	for _=1,4 do if lit()>=1 then break end turn(rift,1) end
	eq(lit(),1,"first mirror lit")
	check(has(caption.Text,"1 / 4 lit"),"caption counts lit mirrors")
	turn(rift,1)
	eq(lit(),0,"turning a lit mirror breaks the beam")
	check(has(noticeOf(rift),"broke the beam"),"mistake notice")
	solveMirrors(mender)
	eq(receiver:GetAttribute("VisualState"),"Lit","receiver lit")
	check(has(caption.Text,"SENTINEL HALL"),"Floor VI moves on to the sentinels after the gallery")
	for _,m in mirrorParts do check(not promptIn(m).Enabled,"mirrors locked once solved") end
	guardiansDown({aegis,mender,rift})
	check(has(caption.Text,"LUMEN COLOSSUS"),"core open")
	heartbeat:Fire(0.1)
	eq(core:GetAttribute("BossPhase"),1,"phase 1")
	eq(core:GetAttribute("PhaseName"),"Radiant Vigil","phase 1 name")
	-- Verdict: the Aegis draws it even when the Riftblade dealt more damage.
	for _=1,8 do heal(rift) fire(rift,corePrompt) end
	for _,p in {aegis,mender,rift} do at(p,r.Vector3.new(0,0,25)) heal(p) end
	clearWisps(rift)
	for _,p in {aegis,mender,rift} do at(p,r.Vector3.new(0,0,25)) heal(p) end
	for _=1,40 do
		heartbeat:Fire(0.5)
		for _,p in {aegis,mender,rift} do heal(p) end
		if core:GetAttribute("Channel")=="Reliquary Verdict" then break end
	end
	eq(core:GetAttribute("Channel"),"Reliquary Verdict","Reliquary Verdict channels")
	check(has(caption.Text,"RELIQUARY VERDICT on "..aegis.Name),"the Aegis is the verdict's target (taunt)")
	local mark=world:FindFirstChild("Verdict mark",true)
	eq(mark.Transparency,0.25,"verdict mark shown")
	for _,p in {aegis,mender,rift} do heal(p) end
	for _=1,8 do heartbeat:Fire(0.5) if core:GetAttribute("Channel")=="" then break end end
	eq(core:GetAttribute("Channel"),"","verdict resolved")
	eq(hums[aegis].Health,100-EG.mechDamage("verdict",100,false,DC.damageTakenMult("Aegis",1)),"the Aegis takes the verdict at its mitigation")
	eq(hums[rift].Health,100,"the Riftblade is spared")
	eq(mark.Transparency,1,"verdict mark hidden")
	-- Phase 2 (60%): Withering Lumen; Mending Light cleanses it.
	for _=1,60 do
		if (core:GetAttribute("BossPhase") or 0)>=2 or not inRun(rift) then break end
		clearWisps(rift)
		for _,p in {aegis,mender,rift} do if (core:GetAttribute("BossPhase") or 0)<2 then heal(p) fire(p,corePrompt) end end
		heartbeat:Fire(0.05)
	end
	eq(core:GetAttribute("BossPhase"),2,"phase 2 at 60% HP")
	check(has(noticeOf(aegis),"Withering Reliquary"),"phase change announced")
	for _=1,60 do
		heartbeat:Fire(0.5)
		if core:GetAttribute("Blight")==true then break end
	end
	eq(core:GetAttribute("Blight"),true,"Withering Lumen starts")
	for _,p in {aegis,mender,rift} do heal(p) end
	heartbeat:Fire(2)
	for _,p in {aegis,mender,rift} do check(hums[p].Health<=100-EG.mechDamage("blight",100,false,1),p.Name.." withers under the blight") end
	now+=26
	ability(mender,"ability")
	eq(core:GetAttribute("Blight"),false,"Mending Light cleanses the blight")
	check(has(noticeOf(rift),"cleansed by "..mender.Name),"cleanse announced")
	-- Clear the floor: payload carries a run id; everyone acted recently.
	for _=1,400 do
		if not inRun(rift) then break end
		for _,p in {aegis,mender,rift} do
			if inRun(p) then
				local l=wispList()
				heal(p)
				if has(caption.Text,"Retune") then tuneAll(p)
				elseif #l>0 then fire(p,promptIn(l[1])) else fire(p,corePrompt) end
			end
		end
		heartbeat:Fire(0.05)
	end
	check(not inRun(rift),"Floor VI cleared")
	for _,p in {aegis,mender,rift} do check(payloads[p.Name] and payloads[p.Name].floor==6,p.Name.." credited ("..noticeOf(p)..")") end
	runId=payloads[aegis.Name].runId
	check(type(runId)=="string" and #runId>0 and runId==payloads[rift.Name].runId,"one run id per run")
	check(payloads[aegis.Name].mistakes>=1,"the broken beam counted as a mistake")
	eq(payloads[aegis.Name].feat,true,"the Aegis earned Absorb from the verdict")
	now+=100

	-- Floor VII: Star Chart, Eventide Nova (broken, interrupted, unbroken), Constellation Lock.
	local a7=player({level=50,gearScore=450,class="Aegis"})
	local s7=player({level=50,gearScore=450,class="Starshot"})
	local r7=player({level=50,gearScore=450,class="Arcanist"})
	use(a7,"Observatory Floor VII","Select floor")
	launch({a7,s7,r7})
	tuneAll(a7)
	check(has(caption.Text,"MIRROR GALLERY"),"Floor VII keeps the Mirror Gallery (cumulative)")
	-- Attune aligns a mirror; Eclipse Rift finishes the gallery.
	ability(r7,"ability")
	eq(lit()>=1,true,"Attune aligns the next mirror")
	ability(r7,"ultimate")
	check(has(caption.Text,"STAR CHART"),"Eclipse Rift lights the gallery; the Star Chart follows")
	local seq=chartSeq()
	eq(#seq,EG.chartLength(false),"chart of four glyphs")
	eq(lectern:GetAttribute("ChartStep"),1,"chart starts at step 1")
	for _,pl in plateParts do check(promptIn(pl).Enabled,"plates active") end
	-- A wrong glyph is a mistake and restarts the chart.
	pressNext(s7)
	eq(lectern:GetAttribute("ChartStep"),2,"right glyph advances")
	local wrong
	for _,pl in plateParts do if pl:GetAttribute("Glyph")~=seq[2] then wrong=pl break end end
	fire(s7,promptIn(wrong))
	eq(lectern:GetAttribute("ChartStep"),1,"wrong glyph restarts the chart")
	check(has(noticeOf(s7),"Wrong glyph"),"wrong glyph notice")
	solveChart(a7)
	check(has(caption.Text,"SENTINEL HALL"),"Floor VII moves on after the Star Chart")
	for _,pl in plateParts do check(not promptIn(pl).Enabled,"plates dormant after the room") end
	guardiansDown({a7,s7,r7})
	heartbeat:Fire(0.1)
	local maxHp=core:GetAttribute("BossMaxHealth")
	-- Phase 2 at 70%.
	fight({a7,s7,r7},function() return (core:GetAttribute("BossPhase") or 0)>=2 end)
	eq(core:GetAttribute("PhaseName"),"Eventide Rite","Floor VII phase 2")
	-- Wait for the nova (no damage dealt): unbroken nova = damage + mistake.
	local function waitChannel(name)
		for i=1,200 do
			if core:GetAttribute("Channel")==name then return true end
			for _,p in {a7,s7,r7} do heal(p) at(p,r.Vector3.new(i%2*3,0,30)) end
			if has(caption.Text,"Retune") then tuneAll(a7) end
			clearWisps(a7)
			if core:GetAttribute("Channel")==name then return true end
			heartbeat:Fire(0.5)
		end
		return false
	end
	check(waitChannel("Eventide Nova"),"Eventide Nova channels")
	check(has(caption.Text,"EVENTIDE NOVA") and has(caption.Text,"break it 0 / "..EG.novaThreshold(maxHp)),"caption shows the break bar")
	local mistakesBefore=nil
	for _,p in {a7,s7,r7} do heal(p) end
	for _=1,20 do heartbeat:Fire(0.5) if core:GetAttribute("Channel")~="Eventide Nova" then break end end
	check(hums[s7].Health<=100-EG.mechDamage("nova",100,false,1),"an unbroken nova strikes everyone")
	check(has(noticeOf(s7),"not broken"),"unbroken nova announced")
	-- Break the next nova with damage.
	check(waitChannel("Eventide Nova"),"second nova")
	for _=1,40 do
		if core:GetAttribute("Channel")~="Eventide Nova" then break end
		act(a7)
	end
	check(core:GetAttribute("Channel")~="Eventide Nova","damage breaks the nova")
	check(has(noticeOf(s7),"broken!"),"break announced")
	-- Interrupt the next one with Disrupting Shot.
	check(waitChannel("Eventide Nova"),"third nova")
	now+=40
	ability(s7,"ability")
	check(core:GetAttribute("Channel")~="Eventide Nova" and has(noticeOf(a7),"interrupted"),"Disrupting Shot interrupts the nova")
	-- Constellation Lock at 35%.
	fight({a7,s7,r7},function() return core:GetAttribute("Lock")=="chart" or not inRun(a7) end)
	eq(core:GetAttribute("Lock"),"chart","Constellation Lock seals the core")
	eq(core:GetAttribute("BossPhase"),3,"phase 3")
	check(has(caption.Text,"SEALED") and has(caption.Text,"Replay the star chart"),"caption asks for the star chart")
	local hp=core:GetAttribute("BossHealth")
	heal(a7) fire(a7,corePrompt)
	eq(core:GetAttribute("BossHealth"),hp,"the sealed core takes no strikes")
	for _,prism in pylons do fire(a7,prism) end
	eq(core:GetAttribute("Lock"),"chart","prism tuning never breaks the Constellation Lock")
	now+=40
	ability(r7,"ability")
	eq(lectern:GetAttribute("ChartStep"),2,"Attune presses the next glyph")
	solveChart(s7)
	eq(core:GetAttribute("Lock"),"","the chart unseals the core")
	fight({a7,s7,r7},function() return not inRun(a7) end,800)
	check(payloads[a7.Name] and payloads[a7.Name].floor==7,"Floor VII cleared and credited")
	check(payloads[a7.Name].runId~=runId,"a new run id per run")
	check(payloads[a7.Name].mistakes>=2,"wrong glyph and unbroken nova counted")
	check(payloads[s7.Name].feat==true,"Starshot Disrupt feat from the nova")
	check(payloads[r7.Name].feat==true,"Arcanist Attune feat from the rooms")
	now+=100

	-- Without an Aegis the verdict hits the top damage dealer.
	local d1=player({level=40,gearScore=400,class="Riftblade"})
	local d2=player({level=40,gearScore=400,class="Mender"})
	use(d1,"Observatory Floor VI","Select floor")
	launch({d1,d2})
	tuneAll(d1) solveMirrors(d1) guardiansDown({d1,d2})
	for _=1,5 do heal(d1) fire(d1,corePrompt) end
	for _=1,80 do
		for _,p in {d1,d2} do heal(p) at(p,r.Vector3.new(0,0,30)) end
		clearWisps(d1)
		if core:GetAttribute("Channel")=="Reliquary Verdict" then break end
		heartbeat:Fire(0.5)
	end
	check(has(caption.Text,"on "..d1.Name),"no Aegis: the verdict targets the top damage dealer")
	for _,p in {d1,d2} do heal(p) end
	for _=1,8 do heartbeat:Fire(0.5) if core:GetAttribute("Channel")=="" then break end end
	eq(hums[d1].Health,100-EG.mechDamage("verdict",100,false,1),"the unprotected damage dealer takes the full verdict")

	-- Rejoin (Minigames rule): d2 disconnects and returns within 90 s with its record.
	for _=1,3 do heal(d2) fire(d2,corePrompt) end
	local leaving=d2
	players.PlayerRemoving:Fire(leaving)
	check(not inRun(leaving),"disconnect removes the delver")
	check(inRun(d1),"the run continues")
	now+=30
	local back=player(nil,leaving.Name)
	check(inRun(back),"rejoin within 90 s restores the delver")
	check(has(noticeOf(back),"rejoined"),"rejoin notice")
	eq(#DC.parseParty(d1:GetAttribute("DungeonParty")),2,"party HUD lists the rejoined delver")
	-- A second disconnect past the window is not restored.
	players.PlayerRemoving:Fire(back)
	now+=EG.REJOIN_SECONDS+1
	local late=player(nil,leaving.Name)
	check(not inRun(late),"rejoin after 90 s refused")
	use(d1,"Return arch","Leave expedition")
	now+=100

	-- Recent-action rule: a delver who stopped acting 60+ s before the kill gets no chest.
	local worker=player({level=1,gearScore=0})
	local idler=player({level=1,gearScore=0})
	use(worker,"Observatory Floor I","Select floor")
	launch({worker,idler})
	tuneAll(idler)
	guardiansDown({worker,idler})
	heal(idler) fire(idler,corePrompt) heal(idler) fire(idler,corePrompt)
	for step=1,14 do
		now+=5
		roots[idler].Position=core.Position+r.Vector3.new(step%2==0 and 3 or -3,0,8) -- keeps moving (not idle-kicked)
		heartbeat:Fire(0.01)
	end
	for _=1,20 do if not inRun(worker) then break end heal(worker) fire(worker,corePrompt) roots[idler].Position=core.Position+r.Vector3.new(0,0,9) end
	check(payloads[worker.Name] and payloads[worker.Name].floor==1,"the active delver is credited")
	check(payloads[idler.Name]==nil and has(noticeOf(idler),"last "..EG.RECENT_SECONDS),"a stale contributor is refused")
	now+=100

	-- Leak check: after every run the arena holds the same parts as before the first.
	eq(#arena:GetDescendants(),baseline,"no parts or prompts left behind across runs")
	eq(world:FindFirstChild("Verdict mark",true).Transparency,1,"verdict mark hidden between runs")
	for _,m in mirrorParts do eq(m:GetAttribute("VisualState"),"Dormant","mirrors dormant between runs") end
end
local runChecks=checks-ruleChecks

------------------------------------------------------------------------------
-- Part 3: server.server.lua Delve block (verify-gameplay.luau harness).
------------------------------------------------------------------------------
do
	local src=fs.readFile("verify-gameplay.luau")
	local cut=src:find("local checks=0\nlocal function eq",1,true)
	assert(cut,"verify-gameplay harness marker")
	local h=luau.load(src:sub(1,cut-1).."\nreturn {player=player,cmd=cmd,allObjects=allObjects,data=data,advance=advance,services=services}",{debugName="gameplay-harness",injectGlobals=true})()
	local function hook(name) for _,o in ipairs(h.allObjects) do if o.Name==name then return o end end return nil end
	local grant=hook("IsleExpeditionGrant")
	local bridge=hook("IsleBridge")
	local function rejoin(id,edit)
		local p=nil
		h.services.Players.PlayerRemoving:Fire(h.current)
		local prof=h.data["p"..id].profile
		if edit then edit(prof) end
		p=h.player(id)
		h.current=p
		return p
	end
	local p=h.player(8301)
	h.current=p
	local s=h.cmd(p,"state")
	check(type(s.dungeonEndgame)=="table" and s.dungeonEndgame.gearScore==0 and s.dungeonEndgame.chest==nil and #s.dungeonEndgame.log==0,"fresh journal endgame state")
	eq(#s.dungeonEndgame.gates,7,"gates for seven floors")
	eq(bridge.OnInvoke("dungeon",p).gearScore,0,"bridge reports the gear score")
	-- Floor VI needs Dungeoneering 40 and gear score 300.
	p=rejoin(8301,function(prof)
		prof.xp.Dungeoneering=Progression.xpForLevel(45)
		prof.xp.Combat=Progression.xpForLevel(45)
	end)
	local refused=grant.OnInvoke(p,{floor=6,grade="S",score=270,partySize=1,damageShare=1,runId="job:1:1"})
	check(refused.ok==false and has(refused.reason,"gear score "..EG.gearGate(6,false)),"grant re-checks the gear gate")
	p=rejoin(8301,function(prof)
		for _,id in ipairs({"AstrarchFang","ObservatoryHelm","ObservatoryVestment","ObservatoryGreaves","ObservatoryTreads"}) do prof.items[id]=1 end
		prof.equipment={weapon="AstrarchFang",helmet="ObservatoryHelm",chest="ObservatoryVestment",legs="ObservatoryGreaves",boots="ObservatoryTreads"}
	end)
	eq(h.cmd(p,"state").dungeonEndgame.gearScore,364,"gear score from the worn kit")
	eq(bridge.OnInvoke("dungeon",p).gearScore,364,"bridge gear score")
	local essenceBefore=h.cmd(p,"state").items.ObservatoryEssence or 0
	local ok=grant.OnInvoke(p,{floor=6,grade="S",score=270,seconds=420,deaths=1,partySize=1,damageShare=1,runId="job:1:1"})
	eq(ok.ok,true,"Floor VI clear accepted")
	local msg=p.last and p.last.message or ""
	check(has(msg,"weekly first clear") and has(msg,"bonus chest waiting") and has(msg,"personal best"),"clear message names bounty, PB and bonus chest")
	s=h.cmd(p,"state")
	local e=s.dungeonEndgame
	check(e.chest and e.chest.floor==6 and e.chest.master==false and e.chest.cost==EG.bonusCost(6,false) and e.chest.expiresIn>0,"bonus chest waiting")
	check((e.chest.items.ObservatoryEssence or 0)>=1,"bonus chest holds essence")
	eq(#e.log,1,"run logged")
	check(e.log[1].f==6 and e.log[1].g=="S" and e.log[1].s==270 and e.log[1].sec==420 and e.log[1].d==1,"log row")
	eq(e.week.best["6"],270,"weekly best")
	eq(e.week.bounty["6"],true,"weekly bounty claimed")
	check(e.pb["6"].score==270 and e.pb["6"].seconds==420,"personal best")
	local runRw=DC.runRewards(6,"S",{})
	local gained=s.items.ObservatoryEssence-essenceBefore
	local base=runRw.items.ObservatoryEssence+EG.bounty(6,false)
	check(gained>=base and gained<=base+10,"essence = clear + weekly bounty (+ the free chest's essence roll) ("..gained..")")
	-- The same run id is never credited twice.
	h.advance(91)
	local dup=grant.OnInvoke(p,{floor=6,grade="S",score=290,partySize=1,damageShare=1,runId="job:1:1"})
	check(dup.ok==false and has(dup.reason,"already credited"),"duplicate run id refused")
	-- Rejoining never rerolls the bonus chest.
	local items=e.chest.items
	p=rejoin(8301)
	local again=h.cmd(p,"state").dungeonEndgame.chest
	check(again and again.cost==e.chest.cost,"chest survives a rejoin")
	for id,n in pairs(items) do eq(again.items[id],n,"chest contents unchanged after rejoin: "..id) end
	-- Opening: coins, key or skip.
	p=rejoin(8301,function(prof) prof.coins=10 end)
	check(has(h.cmd(p,"dungeonChest","open").message,"costs "..EG.bonusCost(6,false)),"not enough coins")
	check(has(h.cmd(p,"dungeonChest","key").message,"no Lodestar Key"),"no key")
	check(has(h.cmd(p,"dungeonChest","peek").message,"Open the bonus chest"),"unknown chest action")
	p=rejoin(8301,function(prof) prof.coins=50000 end)
	local before=h.cmd(p,"state")
	local beforeCoins,beforeItems=before.coins,table.clone(before.items)
	local opened=h.cmd(p,"dungeonChest","open")
	check(has(opened.message,"Bonus chest opened") and opened.coins==beforeCoins-EG.bonusCost(6,false),"open pays the fee")
	for id,n in pairs(items) do eq((opened.items[id] or 0)-(beforeItems[id] or 0),n,"chest item delivered: "..id) end
	eq(opened.dungeonEndgame.chest,nil,"chest gone after opening")
	check(has(h.cmd(p,"dungeonChest","open").message,"No Observatory bonus chest"),"cannot open twice")
	-- Second clear this week: no bounty; a key opens the chest.
	h.advance(91)
	ok=grant.OnInvoke(p,{floor=6,grade="A",score=230,seconds=450,partySize=1,damageShare=1,runId="job:1:2"})
	eq(ok.ok,true,"second clear")
	msg=p.last and p.last.message or ""
	check(not has(msg,"weekly first clear") and not has(msg,"personal best"),"no bounty or PB on a lower repeat")
	s=h.cmd(p,"state")
	eq(#s.dungeonEndgame.log,2,"two log rows")
	eq(s.dungeonEndgame.week.best["6"],270,"weekly best kept")
	p=rejoin(8301,function(prof) prof.items.LodestarKey=1 end)
	local coinsNow=h.cmd(p,"state").coins+0
	local keyed=h.cmd(p,"dungeonChest","key")
	check(has(keyed.message,"Lodestar Key") and keyed.coins==coinsNow and (keyed.items.LodestarKey or 0)==0,"a key opens the chest for free")
	-- A third clear replaces an unopened chest (never stacks).
	h.advance(91)
	grant.OnInvoke(p,{floor=6,grade="B",score=200,seconds=460,partySize=1,damageShare=1,runId="job:1:3"})
	p=rejoin(8301) -- a fresh session lease (journals renew it on autosave)
	h.advance(91)
	local g4=grant.OnInvoke(p,{floor=6,grade="B",score=200,seconds=460,partySize=1,damageShare=1,runId="job:1:4"})
	eq(g4.ok,true,"fourth clear accepted")
	check(has(p.last.message,"left behind"),"an unopened chest is replaced, not stacked")
	check(has(h.cmd(p,"dungeonChest","skip").message,"sealed"),"skip discards the chest")
	-- Expiry.
	p=rejoin(8301)
	h.advance(91)
	grant.OnInvoke(p,{floor=6,grade="B",score=200,seconds=460,partySize=1,damageShare=1,runId="job:1:5"})
	h.advance(EG.CHEST_SECONDS+1)
	eq(h.cmd(p,"state").dungeonEndgame.chest,nil,"unopened chest expires")
	-- Essence Exchange.
	p=rejoin(8301,function(prof) prof.items.ObservatoryEssence=100 prof.coins=1000000 end)
	local bought=h.cmd(p,"essenceBuy","LodestarKey")
	check(has(bought.message,"Exchanged") and bought.items.LodestarKey==1 and bought.items.ObservatoryEssence==40,"essence buys a Lodestar Key")
	check(has(h.cmd(p,"essenceBuy","LodestarKey").message,"costs 60"),"not enough essence")
	check(has(h.cmd(p,"essenceBuy","Nope").message,"Choose"),"unknown exchange item")
	-- Master stars.
	check(has(h.cmd(p,"masterStar","AstrarchFang").message,"5 regular stars"),"Master star needs five stars")
	check(has(h.cmd(p,"masterStar","Crownbreaker").message,"do not own"),"must own the item")
	p=rejoin(8301,function(prof) prof.stars={AstrarchFang=5} prof.items.ObservatoryEssence=10 prof.items.EclipsedStarcore=0 end)
	check(has(h.cmd(p,"masterStar","AstrarchFang").message,"200 Observatory Essence"),"essence cost")
	p=rejoin(8301,function(prof) prof.items.ObservatoryEssence=1000 end)
	check(has(h.cmd(p,"masterStar","AstrarchFang").message,"Eclipsed Starcore"),"Starcore cost")
	p=rejoin(8301,function(prof) prof.items.EclipsedStarcore=2 prof.items.Crownbreaker=1 end)
	check(has(h.cmd(p,"masterStar","Crownbreaker").message,"Only Observatory"),"non-dungeon gear refused")
	local strBefore=h.cmd(p,"state").depth.stats.strength+0
	local starred=h.cmd(p,"masterStar","AstrarchFang")
	check(has(starred.message,"Master star ✪"),"Master star forged")
	eq(starred.depth.gear.masterStars.AstrarchFang,1,"snapshot gear view carries Master stars")
	check(starred.items.ObservatoryEssence==800 and starred.items.EclipsedStarcore==1,"essence and Starcore spent")
	check(starred.depth.stats.strength>strBefore,"Master star raises worn stats")
	eq(starred.dungeonEndgame.gearScore,364+5*EG.STAR_SCORE+EG.MASTER_STAR_SCORE,"gear score counts stars and Master stars")
	-- Persistence and migration.
	h.services.Players.PlayerRemoving:Fire(p)
	local saved=h.data["p8301"].profile
	check(saved.masterStars.AstrarchFang==1 and #saved.dungeonEndgame.log>=2 and saved.dungeonEndgame.pb["6"].score==270,"endgame record saved")
	saved.masterStars={AstrarchFang=99,Crownbreaker=3,Nope=1}
	saved.dungeonEndgame={log="x",week=5,pb={["6"]={score=280,seconds=300}},runs={"job:1:1"}}
	p=h.player(8301)
	h.current=p
	s=h.cmd(p,"state")
	eq(s.depth.gear.masterStars.AstrarchFang,5,"Master stars clamped on load")
	eq(s.depth.gear.masterStars.Crownbreaker,nil,"non-dungeon Master stars dropped on load")
	check(#s.dungeonEndgame.log==0 and s.dungeonEndgame.pb["6"].score==280,"corrupt record sanitised, valid PBs kept")
	h.advance(91)
	local stillDup=grant.OnInvoke(p,{floor=6,grade="S",score=290,partySize=1,damageShare=1,runId="job:1:1"})
	check(stillDup.ok==false,"remembered run ids survive a rejoin")
	-- Master Mode VI: the normal S (270) unlocked it; the Master gate (380) is met by the starred kit.
	p=rejoin(8301)
	h.advance(91)
	local mok=grant.OnInvoke(p,{floor=6,grade="S",score=275,seconds=900,partySize=1,damageShare=1,master=true,runId="job:2:1"})
	eq(mok.ok,true,"Master VI accepted after a grade S normal clear")
	s=h.cmd(p,"state")
	check(s.dungeonEndgame.chest.master==true and s.dungeonEndgame.chest.cost==EG.bonusCost(6,true),"Master bonus chest at the Master fee")
	check(s.dungeonEndgame.log[1].m==true and s.dungeonEndgame.week.best["6m"]==275 and s.dungeonEndgame.pb["6m"].score==275,"Master runs logged separately")
	eq(s.dungeonClasses.floors[6].masterClears,1,"Master clear recorded")
	-- Without the Master gear the grant refuses.
	p=rejoin(8301,function(prof) prof.masterStars={} prof.stars={} end)
	h.advance(91)
	local mlow=grant.OnInvoke(p,{floor=6,grade="S",score=275,seconds=900,partySize=1,damageShare=1,master=true,runId="job:2:2"})
	check(mlow.ok==false and has(mlow.reason,"gear score "..EG.gearGate(6,true)),"Master gear gate re-checked by the journal")
end
local serverChecks=checks-ruleChecks-runChecks

------------------------------------------------------------------------------
-- Part 4: ui.client.lua Hunt > Dungeon endgame and Hunt > Essence.
------------------------------------------------------------------------------
do
	local src=fs.readFile("verify-ui.luau")
	local cut=src:find("------------------------------------------------------------------------------\n-- Checks",1,true)
	assert(cut,"verify-ui harness marker")
	local h=luau.load(src:sub(1,cut-1).."\nreturn {run=run,snapshot=snapshot,find=find,press=press,noFailures=noFailures,new=new}",{debugName="ui-harness",injectGlobals=true})()
	local function texts(root)
		local out={}
		for _,o in ipairs(root:GetDescendants()) do if o.ClassName=="TextLabel" or o.ClassName=="TextButton" then table.insert(out,tostring(o.Text)) end end
		return table.concat(out,"\n")
	end
	local function open(ui,section)
		if not ui.atlas.Visible then h.press(h.find(ui.gui,"AtlasButton")) end
		h.press(ui.tabs:FindFirstChild("HuntButton"))
		h.press(h.find(ui.scroll,"Section"..section))
	end
	local snap=h.snapshot()
	snap.coins=100000
	snap.items=snap.items or {}
	snap.items.ObservatoryEssence=900
	snap.items.EclipsedStarcore=2
	snap.items.LodestarKey=1
	snap.items.AstrarchFang=1
	snap.items.DuskwardenCowl=1
	snap.depth=snap.depth or {}
	snap.depth.gear={reforges={},stars={AstrarchFang=5,DuskwardenCowl=2},books={},masterStars={AstrarchFang=2}}
	snap.dungeonEndgame={gearScore=320,gates={},chest={floor=7,master=true,grade="S",items={ObservatoryEssence=20,Thronebreaker=1},cost=9000,expiresIn=600},
		log={{t=1,f=7,m=true,g="S",s=271,sec=1210,d=1},{t=0,f=6,m=false,g="A",s=240,sec=430,d=0}},
		week={id=1,best={["7m"]=271,["6"]=240},bounty={["7m"]=true},resetIn=3*86400},pb={["7m"]={score=271,seconds=1210}},keys=1,cores=2,essence=900,masterStars={AstrarchFang=2}}
	local classes={}
	for _,id in ipairs(DC.order) do classes[id]=DC.progress(0) end
	local floors={}
	for i=1,7 do floors[i]={secrets=0,secretsTotal=DC.secretCount(i),best=if i<=6 then 270 else 0,clears=1,masterUnlocked=i<=6,masterBest=0,masterClears=0} end
	snap.dungeonClasses={selected=nil,master=false,classes=classes,floors=floors}
	snap.levels=snap.levels or {}
	local ui=h.run({snapshot=snap})
	open(ui,"Dungeon")
	h.noFailures(ui,"dungeon endgame page")
	local page=texts(ui.scroll)
	check(has(page,"Gear score 320"),"summary shows the gear score")
	check(has(page,"Floors I–VII"),"Master card covers floors I–VII")
	check(has(page,"grade S"),"Master card names the S unlock")
	check(has(page,"Thronebreaker"),"Master-only drops listed")
	local f7=texts(h.find(ui.scroll,"DungeonFloor7"))
	check(has(f7,"Needs Dungeoneering 50"),"Floor VII lock reason (level first)")
	check(has(f7,"Constellation Lock") and has(f7,"Eventide Nova") and has(f7,"Reliquary Verdict"),"Floor VII phases and role mechanics listed")
	check(has(f7,"Mirror Gallery → Star Chart"),"Floor VII rooms listed")
	check(has(texts(h.find(ui.scroll,"DungeonFloor6")),"Withering"),"Floor VI phases listed")
	local chest=h.find(ui.scroll,"DungeonBonusChest")
	check(chest and has(texts(chest),"Thronebreaker") and has(texts(chest),"9,000"),"bonus chest card shows the contents and fee")
	local week=texts(h.find(ui.scroll,"DungeonWeekly"))
	check(has(week,"Master VII: 271 (S)") and has(week,"VI: 240 (A)"),"weekly bests shown")
	local log=texts(h.find(ui.scroll,"DungeonRunLog"))
	check(has(log,"Floor Master VII") and has(log,"20:10") and has(log,"Personal bests") and has(log,"Master VII 271 in 20:10"),"run log and personal bests")
	h.press(h.find(ui.scroll,"DungeonChestOpen"))
	local last=ui.sent[#ui.sent]
	check(last and last[1]=="dungeonChest" and last[2]=="open","Open sends dungeonChest open")
	open(ui,"Dungeon")
	h.press(h.find(ui.scroll,"DungeonChestKey"))
	last=ui.sent[#ui.sent]
	check(last[1]=="dungeonChest" and last[2]=="key","Use key sends dungeonChest key")
	open(ui,"Dungeon")
	h.press(h.find(ui.scroll,"DungeonChestSkip"))
	last=ui.sent[#ui.sent]
	check(last[1]=="dungeonChest" and last[2]=="skip","Leave sealed sends skip")
	h.noFailures(ui,"dungeon endgame buttons")
	-- Gear lock reason with enough Dungeoneering.
	local gsnap=h.snapshot()
	gsnap.dungeonEndgame={gearScore=120}
	gsnap.depth=gsnap.depth or {}
	gsnap.depth.skills={Dungeoneering={level=50,xp=Progression.xpForLevel(50)}}
	local gui=h.run({snapshot=gsnap})
	open(gui,"Dungeon")
	h.noFailures(gui,"gear lock")
	local g7=texts(h.find(gui.scroll,"DungeonFloor7"))
	check(has(g7,"Needs gear score "..EG.gearGate(7,false)) and has(g7,"yours 120"),"gear-score lock reason shown")
	check(has(texts(h.find(gui.scroll,"DungeonFloor5")),"Master Mode: clear at grade S"),"Master lock reason shown")
	-- Hunt > Essence.
	open(ui,"Essence")
	h.noFailures(ui,"essence page")
	local ess=texts(ui.scroll)
	check(has(ess,"900 essence") and has(ess,"2 Eclipsed Starcores"),"essence summary")
	check(h.find(ui.scroll,"EssenceGear_AstrarchFang")~=nil and h.find(ui.scroll,"EssenceGear_DuskwardenCowl")~=nil,"owned dungeon gear listed")
	check(has(texts(h.find(ui.scroll,"EssenceGear_AstrarchFang")),"Master star 3"),"next Master star offered")
	h.press(h.find(ui.scroll,"EssenceMasterStar_AstrarchFang"))
	last=ui.sent[#ui.sent]
	check(last[1]=="masterStar" and last[2]=="AstrarchFang","Master star button sends masterStar")
	open(ui,"Essence")
	h.press(h.find(ui.scroll,"EssenceStar_DuskwardenCowl"))
	last=ui.sent[#ui.sent]
	check(last[1]=="star" and last[2]=="DuskwardenCowl","star button sends the regular star verb")
	open(ui,"Essence")
	h.press(h.find(ui.scroll,"EssenceBuyLodestarKey"))
	last=ui.sent[#ui.sent]
	check(last[1]=="essenceBuy" and last[2]=="LodestarKey","Exchange sends essenceBuy")
	h.noFailures(ui,"essence buttons")
	-- Malformed or missing endgame data still renders.
	for _,bad in ipairs({"oops",{chest="x",log={1,"y"},week=5,pb={x=1}},{chest={items="z",cost="q"}}}) do
		local broken=h.snapshot()
		broken.dungeonEndgame=bad
		local bui=h.run({snapshot=broken})
		open(bui,"Dungeon")
		h.noFailures(bui,"malformed endgame data")
		check(h.find(bui.scroll,"DungeonRunLog")~=nil,"run log renders with malformed data")
		open(bui,"Essence")
		h.noFailures(bui,"malformed essence data")
	end
end
local uiChecks=checks-ruleChecks-runChecks-serverChecks

print("Dungeon endgame QA passed "..checks.." checks ("..ruleChecks.." rules, "..runChecks.." encounter, "..serverChecks.." server, "..uiChecks.." UI).")
print("SUITE-END verify-dungeon-master.luau")
