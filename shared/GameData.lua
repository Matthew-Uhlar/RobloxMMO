-- Aether Isles shared game data. Pure data + generated tables, no Roblox APIs.
-- Mechanics follow OSRS (1-99 skills, tiered resources, level-gated gear) and
-- Hypixel SkyBlock (stat sheet, collections, accessories, pets, slayers).
-- All names, creatures, places and items are original to Aether Isles.
local Data = {}

------------------------------------------------------------------------------
-- Skills: OSRS experience curve, level 99 cap (200M XP hard cap).
------------------------------------------------------------------------------
Data.MAX_LEVEL = 99
Data.MAX_XP = 200000000
Data.XP_TABLE = {}
do
	local points = 0
	Data.XP_TABLE[1] = 0
	for lvl = 1, Data.MAX_LEVEL - 1 do
		points += math.floor(lvl + 300 * 2 ^ (lvl / 7))
		Data.XP_TABLE[lvl + 1] = math.floor(points / 4)
	end
end

-- category: gathering / production / combat / support (OSRS categories).
-- perLevel: SkyBlock-style permanent stat reward per level above 1.
Data.SkillOrder = {"Combat","Mining","Woodcutting","Fishing","Farming","Smithing","Cooking","Alchemy","Enchanting","Taming","Dungeoneering","Carpentry"}
Data.Skills = {
	Combat={category="combat",color="C8553D",title="Warrior",perLevel={critChance=0.5,strength=1},description="Fight creatures of the isles. Raises Strength and Crit Chance."},
	Mining={category="gathering",color="8C7A6B",title="Prospector",perLevel={defense=1,miningFortune=4},description="Break ore veins with pickaxes. Raises Defense and Mining Fortune."},
	Woodcutting={category="gathering",color="5E8C4A",title="Lumberjack",perLevel={strength=1,foragingFortune=4},description="Fell trees across the isles. Raises Strength and Foraging Fortune."},
	Fishing={category="gathering",color="3F7CAC",title="Angler",perLevel={health=2,fishingFortune=3},description="Catch fish from sky-lakes. Raises Health and Fishing Fortune."},
	Farming={category="gathering",color="C9A227",title="Cultivator",perLevel={health=2,farmingFortune=4},description="Grow and harvest crops. Raises Health and Farming Fortune."},
	Smithing={category="production",color="B5651D",title="Forgemaster",perLevel={defense=1},description="Smelt ingots and forge gear and tools. Raises Defense."},
	Cooking={category="production",color="D9822B",title="Hearthkeeper",perLevel={health=1},description="Cook meals that heal and grant buffs. Raises Health."},
	Alchemy={category="production",color="8E5BB5",title="Brewer",perLevel={intelligence=1},description="Brew potions with timed buffs. Raises Intelligence."},
	Enchanting={category="production",color="4FB0C6",title="Runesmith",perLevel={intelligence=2},description="Enchant gear with lasting power. Raises Intelligence."},
	Taming={category="support",color="E07A5F",title="Beastfriend",perLevel={petLuck=1},description="Raise and level companion pets. Raises Pet Luck."},
	Dungeoneering={category="combat",color="5A5A8C",title="Delver",perLevel={health=2},description="Clear the Observatory expeditions. Raises Health."},
	Carpentry={category="support",color="A0784F",title="Builder",perLevel={health=1},description="Build furniture and island upgrades. Raises Health."},
}
-- Coins awarded the moment a level is reached (SkyBlock skill rewards).
function Data.levelCoinReward(lvl)
	if lvl <= 10 then return 25 * lvl elseif lvl <= 25 then return 100 * lvl elseif lvl <= 50 then return 250 * lvl end
	return 500 * lvl
end

------------------------------------------------------------------------------
-- Rarity (SkyBlock colours + accessory Magical Power).
------------------------------------------------------------------------------
Data.RarityOrder = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"}
Data.Rarity = {
	Common={color="FFFFFF",power=3,rank=1},Uncommon={color="55FF55",power=5,rank=2},Rare={color="5555FF",power=8,rank=3},
	Epic={color="AA00AA",power=12,rank=4},Legendary={color="FFAA00",power=16,rank=5},Mythic={color="FF55FF",power=22,rank=6},
}

------------------------------------------------------------------------------
-- Stats (SkyBlock stat sheet).
------------------------------------------------------------------------------
Data.StatOrder = {"health","defense","strength","critChance","critDamage","speed","intelligence","attackSpeed","miningSpeed","miningFortune","foragingFortune","farmingFortune","fishingFortune","seaCreatureChance","magicFind","petLuck"}
Data.Stats = {
	health={name="Health",symbol="❤",color="FF5555",base=100},
	defense={name="Defense",symbol="❈",color="55FF55",base=0},
	strength={name="Strength",symbol="❁",color="FF5555",base=0},
	critChance={name="Crit Chance",symbol="☣",color="5555FF",base=30,cap=100,percent=true},
	critDamage={name="Crit Damage",symbol="☠",color="5555FF",base=50,percent=true},
	speed={name="Speed",symbol="✦",color="FFFFFF",base=100,cap=400},
	intelligence={name="Intelligence",symbol="✎",color="55FFFF",base=100},
	attackSpeed={name="Attack Speed",symbol="⚔",color="FFFF55",base=0,cap=100,percent=true},
	miningSpeed={name="Mining Speed",symbol="❖",color="FFAA00",base=0},
	miningFortune={name="Mining Fortune",symbol="☘",color="FFAA00",base=0},
	foragingFortune={name="Foraging Fortune",symbol="☘",color="FFAA00",base=0},
	farmingFortune={name="Farming Fortune",symbol="☘",color="FFAA00",base=0},
	fishingFortune={name="Fishing Fortune",symbol="☘",color="FFAA00",base=0},
	seaCreatureChance={name="Sea Creature Chance",symbol="α",color="00AAAA",base=5,cap=100,percent=true},
	magicFind={name="Magic Find",symbol="✯",color="55FFFF",base=0},
	petLuck={name="Pet Luck",symbol="♣",color="FF55FF",base=0},
}

------------------------------------------------------------------------------
-- Items. Every item: name, kind, rarity, color (hex), description, optional
-- stats/slot/requires/tier/heal/buff/value (merchant price).
------------------------------------------------------------------------------
Data.Items = {}
local function item(id, def)
	def.id = id
	def.rarity = def.rarity or "Common"
	def.value = def.value or 1
	Data.Items[id] = def
	return def
end

-- Gathering resources: OSRS-style tiers. level = skill level to harvest,
-- xp = experience per harvest, tool = minimum tool tier required (0 = hands),
-- respawn = node respawn seconds. Tier 1 of each keeps the original ids.
Data.ResourceTiers = {
	Mining={
		{id="Ore",name="Copperstone Ore",level=1,xp=12,tool=0,respawn=3,value=4,color="B87333"},
		{id="Aetherite",name="Aetherite",level=3,xp=18,tool=0,respawn=5,value=7,color="7FD6E8"},
		{id="Brassite",name="Brassite Ore",level=15,xp=35,tool=1,respawn=6,value=12,color="D4A84B"},
		{id="SunsteelOre",name="Sunsteel Ore",level=30,xp=65,tool=2,respawn=8,value=22,color="F2C14E"},
		{id="Voidstone",name="Voidstone",level=45,xp=95,tool=3,respawn=10,value=38,color="5B3F8C"},
		{id="StarmetalOre",name="Starmetal Ore",level=60,xp=140,tool=4,respawn=12,value=60,color="C9D6E3"},
		{id="Prismite",name="Prismite",level=75,xp=200,tool=5,respawn=15,value=95,color="E86FB8"},
		{id="Celestium",name="Celestium",level=85,xp=300,tool=6,respawn=20,value=150,color="FFF3B0"},
	},
	Woodcutting={
		{id="Timber",name="Meadow Timber",level=1,xp=12,tool=0,respawn=3,value=3,color="9C6B3E"},
		{id="WindpineLog",name="Windpine Log",level=15,xp=35,tool=1,respawn=6,value=10,color="6B8E5A"},
		{id="EmberoakLog",name="Emberoak Log",level=30,xp=65,tool=2,respawn=8,value=20,color="B5482A"},
		{id="GlimmerbarkLog",name="Glimmerbark Log",level=45,xp=95,tool=3,respawn=10,value=34,color="8FD3C7"},
		{id="StarwoodLog",name="Starwood Log",level=60,xp=140,tool=4,respawn=12,value=55,color="3B4C7A"},
		{id="AetherheartLog",name="Aetherheart Log",level=75,xp=200,tool=5,respawn=15,value=90,color="F0E6A8"},
	},
	Fishing={
		{id="Fish",name="Skylake Minnow",level=1,xp=12,tool=0,respawn=3,value=5,color="8FB8D6"},
		{id="Glassfin",name="Glassfin",level=15,xp=35,tool=1,respawn=6,value=12,color="CFEFFF"},
		{id="Stormeel",name="Stormeel",level=30,xp=65,tool=2,respawn=8,value=24,color="4B6584"},
		{id="Lanternray",name="Lanternray",level=45,xp=95,tool=3,respawn=10,value=40,color="FFD166"},
		{id="AbyssKoi",name="Abyss Koi",level=60,xp=140,tool=4,respawn=12,value=62,color="EF476F"},
		{id="LeviathanScale",name="Leviathan Scale",level=75,xp=200,tool=5,respawn=15,value=100,color="06D6A0"},
	},
	Farming={
		{id="Herb",name="Meadow Herb",level=1,xp=12,tool=0,respawn=3,value=2,color="6BBF59"},
		{id="Sunwheat",name="Sunwheat",level=15,xp=35,tool=1,respawn=6,value=9,color="E9C46A"},
		{id="Glowcap",name="Glowcap",level=30,xp=65,tool=2,respawn=8,value=18,color="F4A261"},
		{id="Moonbloom",name="Moonbloom",level=45,xp=95,tool=3,respawn=10,value=30,color="B8C0FF"},
		{id="Starfruit",name="Starfruit",level=60,xp=140,tool=4,respawn=12,value=52,color="FFE66D"},
		{id="AetherLotus",name="Aether Lotus",level=75,xp=200,tool=5,respawn=15,value=85,color="FF9ECD"},
	},
}
Data.ResourceSkill = {}
Data.ToolKind = {Mining="Pickaxe",Woodcutting="Hatchet",Fishing="Rod",Farming="Hoe"}
Data.FortuneStat = {Mining="miningFortune",Woodcutting="foragingFortune",Fishing="fishingFortune",Farming="farmingFortune"}
for skill, tiers in pairs(Data.ResourceTiers) do
	for index, r in ipairs(tiers) do
		r.skill = skill
		r.index = index
		Data.ResourceSkill[r.id] = skill
		item(r.id, {name=r.name,kind="resource",skill=skill,tier=index,color=r.color,value=r.value,
			rarity=if index>=6 then "Epic" elseif index>=4 then "Rare" elseif index>=2 then "Uncommon" else "Common",
			description="Gathered with "..skill.." "..r.level..". +"..r.xp.." XP per harvest."})
	end
end

-- Special drops / currencies.
item("Shard",{name="Warden Shard",kind="material",rarity="Uncommon",color="9AD1D4",value=15,description="Dropped by Wardens. Used for enchanting."})
item("Stormglass",{name="Stormglass",kind="material",rarity="Rare",color="7B8CDE",value=60,description="Recovered from the Observatory expedition."})
item("ArcaneDust",{name="Arcane Dust",kind="material",rarity="Uncommon",color="C77DFF",value=8,description="Shimmering residue of slain creatures. Fuel for enchanting."})
item("BeastHide",{name="Beast Hide",kind="material",rarity="Common",color="8D6346",value=4,description="Tough hide from island beasts."})
item("GolemCore",{name="Golem Core",kind="material",rarity="Rare",color="E0B04A",value=45,description="The humming heart of a Brass Golem."})
item("SpiderSilk",{name="Gloomsilk",kind="material",rarity="Uncommon",color="D8D8E8",value=12,description="Strong silk from Gloomfang spiders."})
item("VoidEssence",{name="Void Essence",kind="material",rarity="Rare",color="6A4C93",value=40,description="Condensed void, gathered from wisps and wraiths."})
item("StormFeather",{name="Storm Feather",kind="material",rarity="Uncommon",color="A8DADC",value=14,description="Crackling plumage of a Storm Harrier."})
item("StarFragment",{name="Star Fragment",kind="material",rarity="Epic",color="FFF1A8",value=180,description="A shard of a fallen star. Extremely rare."})
item("SlayerToken",{name="Slayer Seal",kind="material",rarity="Rare",color="B23A48",value=25,description="Proof of a slain slayer boss. Spent on slayer gear."})

-- Legacy items (kept so existing saves remain valid).
item("Pickaxe",{name="Copper Pickaxe",kind="tool",toolKind="Pickaxe",toolTier=1,rarity="Common",color="B87333",stats={miningSpeed=20},value=10,description="+1 Ore per harvest. Tier 1 pickaxe."})
item("ReinforcedPickaxe",{name="Reinforced Pickaxe",kind="tool",toolKind="Pickaxe",toolTier=1,rarity="Uncommon",color="7FD6E8",stats={miningSpeed=40,miningFortune=20},value=60,description="+2 Ore and +1 Aetherite per harvest. Tier 1 pickaxe."})
item("Blade",{name="Copper Blade",kind="weapon",slot="weapon",rarity="Common",color="B87333",stats={damage=20,strength=5},value=12,description="A simple blade. +8 Warden strike damage."})
item("Stormblade",{name="Stormblade",kind="weapon",slot="weapon",rarity="Rare",color="7B8CDE",stats={damage=60,strength=20,critDamage=15},requires={Combat=5},value=240,description="Forged from Stormglass. +12 Warden strike damage."})
item("Skyplate",{name="Skyplate",kind="armor",slot="chest",rarity="Uncommon",color="7FD6E8",stats={defense=25,health=10},value=80,description="Aether-plated chestpiece. +2 defense."})
item("Tonic",{name="Meadow Tonic",kind="consumable",category="food",rarity="Common",color="6BBF59",heal=40,value=6,description="Restore up to 40 health."})
item("ExpeditionRation",{name="Expedition Ration",kind="consumable",category="food",rarity="Uncommon",color="D9822B",heal=65,recovery=12,value=14,description="Restore up to 65 health; 12 second recovery."})
item("AlloyIngot",{name="Alloy Ingot",kind="material",rarity="Common",color="B08D57",value=12,description="Refined from Ore and Timber."})
item("AetherIngot",{name="Aether Ingot",kind="material",rarity="Uncommon",color="7FD6E8",value=30,description="Refined from Aetherite and Alloy."})

------------------------------------------------------------------------------
-- Metal tiers: ingots, tools, weapons, armor sets (generated).
------------------------------------------------------------------------------
Data.ArmorSlots = {"helmet","chest","legs","boots"}
Data.EquipSlots = {"weapon","helmet","chest","legs","boots","pickaxe","hatchet","rod","hoe"}
local slotShare = {helmet=0.6,chest=1,legs=0.85,boots=0.5}
local slotNames = {helmet="Helm",chest="Chestplate",legs="Greaves",boots="Boots"}
local slotIngots = {helmet=5,chest=8,legs=7,boots=4}
Data.MetalTiers = {
	{id="Brass",ore="Brassite",log="WindpineLog",crop="Sunwheat",fish="Glassfin",level=15,combat=5,rarity="Uncommon",color="D4A84B",
		weapon={damage=40,strength=10},armor={defense=40,health=20},set={name="Steadfast",bonus={defense=30},text="+30 Defense"}},
	{id="Sunsteel",ore="SunsteelOre",log="EmberoakLog",crop="Glowcap",fish="Stormeel",level=30,combat=12,rarity="Rare",color="F2C14E",
		weapon={damage=70,strength=25,critDamage=10},armor={defense=70,health=40,strength=5},set={name="Solar Vigor",bonus={strength=25,health=50},text="+25 Strength, +50 Health"}},
	{id="Voidforged",ore="Voidstone",log="GlimmerbarkLog",crop="Moonbloom",fish="Lanternray",level=45,combat=20,rarity="Rare",color="5B3F8C",
		weapon={damage=110,strength=40,critDamage=25},armor={defense=105,health=70,critDamage=5},set={name="Hollow Hunger",bonus={critDamage=40,strength=20},text="+40 Crit Damage, +20 Strength"}},
	{id="Starmetal",ore="StarmetalOre",log="StarwoodLog",crop="Starfruit",fish="AbyssKoi",level=60,combat=30,rarity="Epic",color="C9D6E3",
		weapon={damage=160,strength=60,critChance=5,critDamage=40},armor={defense=150,health=110,critChance=2},set={name="Constellation",bonus={critChance=10,critDamage=50},text="+10 Crit Chance, +50 Crit Damage"}},
	{id="Prismatic",ore="Prismite",log="AetherheartLog",crop="AetherLotus",fish="LeviathanScale",level=75,combat=40,rarity="Epic",color="E86FB8",
		weapon={damage=220,strength=90,critChance=10,critDamage=60},armor={defense=210,health=160,strength=15},set={name="Refraction",bonus={strength=60,critDamage=60,health=100},text="+60 Strength, +60 Crit Damage, +100 Health"}},
	{id="Celestial",ore="Celestium",log="AetherheartLog",crop="AetherLotus",fish="LeviathanScale",level=85,combat=50,rarity="Legendary",color="FFF3B0",
		weapon={damage=300,strength=130,critChance=15,critDamage=90},armor={defense=280,health=220,critChance=4,critDamage=10},set={name="Ascendant",bonus={health=250,defense=150,strength=80,critDamage=80},text="+250 Health, +150 Defense, +80 Strength, +80 Crit Damage"}},
}
Data.Sets = {}
Data.Recipes = {}
local function recipe(id, def)
	def.id = id
	def.output = def.output or id
	def.amount = def.amount or 1
	Data.Recipes[id] = def
	return def
end
local function scaled(stats, share)
	local out = {}
	for k, v in pairs(stats) do out[k] = math.max(1, math.floor(v * share + 0.5)) end
	return out
end
for index, tier in ipairs(Data.MetalTiers) do
	tier.index = index
	local ingot = tier.id.."Ingot"
	tier.ingot = ingot
	item(ingot,{name=tier.id.." Ingot",kind="material",rarity=tier.rarity,color=tier.color,value=Data.Items[tier.ore].value*3+8,description="Smelted from "..Data.Items[tier.ore].name.." with "..Data.Items[tier.log].name.." fuel."})
	recipe(ingot,{skill="Smithing",level=tier.level,xp=math.floor(tier.level*1.6+10),costs={[tier.ore]=3,[tier.log]=1},repeatable=true,station="Forge",category="Ingots"})
	-- Weapon
	local sword = tier.id.."Sword"
	item(sword,{name=tier.id.." Sword",kind="weapon",slot="weapon",tier=index+1,rarity=tier.rarity,color=tier.color,stats=table.clone(tier.weapon),requires={Combat=tier.combat},value=Data.Items[ingot].value*6,description="Requires Combat "..tier.combat.."."})
	recipe(sword,{skill="Smithing",level=tier.level,xp=tier.level*4,costs={[ingot]=6,[tier.log]=2},collectionTier={[tier.ore]=2},station="Forge",category="Weapons"})
	-- Armor
	Data.Sets[tier.id] = {id=tier.id,name=tier.set.name,pieces={},bonus=tier.set.bonus,text=tier.set.text,color=tier.color}
	for _, slot in ipairs(Data.ArmorSlots) do
		local id = tier.id..slotNames[slot]
		item(id,{name=tier.id.." "..slotNames[slot],kind="armor",slot=slot,set=tier.id,tier=index+1,rarity=tier.rarity,color=tier.color,stats=scaled(tier.armor,slotShare[slot]),requires={Combat=tier.combat},value=Data.Items[ingot].value*slotIngots[slot],description="Part of the "..tier.set.name.." set. Requires Combat "..tier.combat.."."})
		recipe(id,{skill="Smithing",level=tier.level,xp=tier.level*slotIngots[slot]//2,costs={[ingot]=slotIngots[slot],[tier.crop]=slotIngots[slot]//2},collectionTier={[tier.ore]=3},station="Forge",category="Armor"})
		table.insert(Data.Sets[tier.id].pieces, id)
	end
	-- Tools: tool tier index+1 lets you harvest resource tier index+2 (tool req = index+1).
	local toolDefs = {
		{kind="Pickaxe",slot="pickaxe",suffix="Pickaxe",skill="Mining",stats={miningSpeed=40*(index+1),miningFortune=15*(index+1)},extra={[tier.log]=2}},
		{kind="Hatchet",slot="hatchet",suffix="Hatchet",skill="Woodcutting",stats={foragingFortune=15*(index+1),strength=3*index},extra={[tier.log]=3}},
		{kind="Rod",slot="rod",suffix="Rod",skill="Fishing",stats={fishingFortune=15*(index+1),seaCreatureChance=index},extra={[tier.log]=3,[tier.fish]=2}},
		{kind="Hoe",slot="hoe",suffix="Hoe",skill="Farming",stats={farmingFortune=15*(index+1)},extra={[tier.log]=2,[tier.crop]=2}},
	}
	for _, t in ipairs(toolDefs) do
		local id = tier.id..t.suffix
		local costs = {[ingot]=3}
		for k, v in pairs(t.extra) do costs[k] = v end
		item(id,{name=tier.id.." "..t.suffix,kind="tool",toolKind=t.kind,slot=t.slot,toolTier=index+1,tier=index+1,rarity=tier.rarity,color=tier.color,stats=t.stats,requires={[t.skill]=tier.level},value=Data.Items[ingot].value*4,description="Tier "..(index+1).." "..string.lower(t.kind)..". Requires "..t.skill.." "..tier.level.."."})
		recipe(id,{skill="Smithing",level=tier.level,xp=tier.level*3,costs=costs,collectionTier={[tier.ore]=1},station="Forge",category="Tools"})
	end
end
-- Starter tools (tier 1) for the three skills that lacked one.
item("CopperHatchet",{name="Copper Hatchet",kind="tool",toolKind="Hatchet",slot="hatchet",toolTier=1,tier=1,rarity="Common",color="B87333",stats={foragingFortune=10},value=10,description="Tier 1 hatchet."})
item("WovenRod",{name="Woven Rod",kind="tool",toolKind="Rod",slot="rod",toolTier=1,tier=1,rarity="Common",color="9C6B3E",stats={fishingFortune=10},value=10,description="Tier 1 fishing rod."})
item("CopperHoe",{name="Copper Hoe",kind="tool",toolKind="Hoe",slot="hoe",toolTier=1,tier=1,rarity="Common",color="B87333",stats={farmingFortune=10},value=10,description="Tier 1 hoe."})
Data.Items.Pickaxe.slot = "pickaxe"
Data.Items.ReinforcedPickaxe.slot = "pickaxe"
recipe("CopperHatchet",{skill="Smithing",level=1,xp=20,costs={AlloyIngot=2,Timber=3},station="Forge",category="Tools"})
recipe("WovenRod",{skill="Smithing",level=1,xp=20,costs={Timber=4,Herb=3},station="Forge",category="Tools"})
recipe("CopperHoe",{skill="Smithing",level=1,xp=20,costs={AlloyIngot=2,Timber=2},station="Forge",category="Tools"})

------------------------------------------------------------------------------
-- Cooking: one meal per fish tier (OSRS food ladder) + buff feasts.
------------------------------------------------------------------------------
for index, fish in ipairs(Data.ResourceTiers.Fishing) do
	local id = "Cooked"..fish.id
	local crop = Data.ResourceTiers.Farming[index].id
	item(id,{name="Seared "..fish.name,kind="consumable",category="food",rarity=if index>=5 then "Rare" elseif index>=3 then "Uncommon" else "Common",color=fish.color,heal=40+index*35,recovery=4,value=fish.value*2+2,requires={Cooking=fish.level},description="Restore up to "..(40+index*35).." health."})
	recipe(id,{skill="Cooking",level=fish.level,xp=fish.xp+8,costs={[fish.id]=1,[crop]=1},repeatable=true,station="Hearth",category="Meals"})
end
item("HuntersFeast",{name="Hunter's Feast",kind="consumable",category="buff",rarity="Rare",color="D9822B",buff={stats={strength=30,health=60},duration=600},value=90,description="+30 Strength, +60 Health for 10 minutes."})
recipe("HuntersFeast",{skill="Cooking",level=35,xp=120,costs={CookedStormeel=2,Glowcap=3,BeastHide=2},repeatable=true,station="Hearth",category="Feasts"})
item("StarlitBanquet",{name="Starlit Banquet",kind="consumable",category="buff",rarity="Epic",color="FFE66D",buff={stats={strength=60,critDamage=40,health=150},duration=900},value=300,description="+60 Strength, +40 Crit Damage, +150 Health for 15 minutes."})
recipe("StarlitBanquet",{skill="Cooking",level=65,xp=320,costs={CookedAbyssKoi=2,Starfruit=4,StarFragment=1},repeatable=true,station="Hearth",category="Feasts"})

------------------------------------------------------------------------------
-- Alchemy: timed potions (SkyBlock potion buffs, OSRS herblore levels).
------------------------------------------------------------------------------
local potions = {
	{id="MightDraught",name="Might Draught",level=5,xp=30,costs={Herb=3,Fish=1},buff={strength=15},duration=300,color="E63946"},
	{id="IronbarkTonic",name="Ironbark Tonic",level=12,xp=45,costs={Herb=2,WindpineLog=2},buff={defense=40},duration=300,color="6B8E5A"},
	{id="SwiftwindElixir",name="Swiftwind Elixir",level=18,xp=60,costs={Sunwheat=3,Glassfin=1},buff={speed=40},duration=300,color="A8DADC"},
	{id="ProspectorsBrew",name="Prospector's Brew",level=25,xp=80,costs={Sunwheat=2,Brassite=3},buff={miningFortune=60,miningSpeed=80},duration=600,color="D4A84B"},
	{id="KeeneyeTincture",name="Keen-eye Tincture",level=32,xp=100,costs={Glowcap=3,StormFeather=1},buff={critChance=10,critDamage=20},duration=480,color="5555FF"},
	{id="HarvestCordial",name="Harvest Cordial",level=38,xp=115,costs={Glowcap=2,Sunwheat=4},buff={farmingFortune=60,foragingFortune=60},duration=600,color="E9C46A"},
	{id="AnglersInfusion",name="Angler's Infusion",level=44,xp=130,costs={Moonbloom=2,Lanternray=1},buff={fishingFortune=60,seaCreatureChance=10},duration=600,color="3F7CAC"},
	{id="TitanBrew",name="Titan Brew",level=55,xp=170,costs={Moonbloom=3,VoidEssence=1},buff={strength=50,health=80},duration=480,color="B23A48"},
	{id="FortunesFavour",name="Fortune's Favour",level=68,xp=230,costs={Starfruit=3,StarFragment=1},buff={magicFind=20},duration=900,color="FFAA00"},
	{id="AetherApotheosis",name="Aether Apotheosis",level=82,xp=320,costs={AetherLotus=3,VoidEssence=2,StarFragment=1},buff={strength=80,critDamage=60,defense=80,health=150},duration=900,color="FF9ECD"},
}
for _, p in ipairs(potions) do
	item(p.id,{name=p.name,kind="consumable",category="potion",rarity=if p.level>=60 then "Epic" elseif p.level>=30 then "Rare" else "Uncommon",color=p.color,buff={stats=p.buff,duration=p.duration},value=p.xp,requires={Alchemy=p.level},description="Potion: "..p.duration//60 .." minute buff."})
	recipe(p.id,{skill="Alchemy",level=p.level,xp=p.xp,costs=p.costs,repeatable=true,station="Cauldron",category="Potions"})
end

------------------------------------------------------------------------------
-- Accessories (talismans): Magical Power by rarity + flat stats.
------------------------------------------------------------------------------
local accessories = {
	{id="MeadowCharm",name="Meadow Charm",rarity="Common",stats={health=10},costs={Herb=64},collectionTier={Herb=2}},
	{id="QuarryTalisman",name="Quarry Talisman",rarity="Common",stats={miningFortune=10},costs={Ore=96},collectionTier={Ore=2}},
	{id="TimberRing",name="Timber Ring",rarity="Common",stats={foragingFortune=10},costs={Timber=96},collectionTier={Timber=2}},
	{id="AnglerBead",name="Angler's Bead",rarity="Common",stats={fishingFortune=10},costs={Fish=64},collectionTier={Fish=2}},
	{id="WardenSigil",name="Warden Sigil",rarity="Uncommon",stats={strength=5,defense=5},costs={Shard=10,AlloyIngot=4},collectionTier={Shard=1}},
	{id="BrassBand",name="Brass Band",rarity="Uncommon",stats={defense=10},costs={BrassIngot=8},collectionTier={Brassite=3}},
	{id="FeatherfallTalisman",name="Featherfall Talisman",rarity="Uncommon",stats={speed=5},costs={StormFeather=12},collectionTier={StormFeather=1}},
	{id="HideBracer",name="Hide Bracer",rarity="Uncommon",stats={health=25},costs={BeastHide=32},collectionTier={BeastHide=2}},
	{id="SunsteelSeal",name="Sunsteel Seal",rarity="Rare",stats={strength=10,critDamage=5},costs={SunsteelIngot=10,GolemCore=2},collectionTier={SunsteelOre=4}},
	{id="GloomsilkCord",name="Gloomsilk Cord",rarity="Rare",stats={critChance=3},costs={SpiderSilk=48},collectionTier={SpiderSilk=3}},
	{id="VoidLocket",name="Void Locket",rarity="Epic",stats={critDamage=15,intelligence=20},costs={VoidEssence=24,VoidforgedIngot=6},collectionTier={Voidstone=4}},
	{id="SlayerEmblem",name="Slayer's Emblem",rarity="Epic",stats={strength=15,critDamage=10},costs={SlayerToken=16},collectionTier={SlayerToken=1}},
	{id="StarlightCrown",name="Starlight Diadem",rarity="Legendary",stats={critChance=5,critDamage=25,magicFind=5},costs={StarFragment=6,StarmetalIngot=10},collectionTier={StarmetalOre=5}},
	{id="AetherHeartstone",name="Aether Heartstone",rarity="Mythic",stats={health=100,strength=30,defense=30,magicFind=10},costs={StarFragment=12,CelestialIngot=12,AetherheartLog=64},collectionTier={Celestium=4}},
}
for _, a in ipairs(accessories) do
	item(a.id,{name=a.name,kind="accessory",rarity=a.rarity,color=Data.Rarity[a.rarity].color,stats=a.stats,value=40*Data.Rarity[a.rarity].rank^2,description="Accessory. Magical Power "..Data.Rarity[a.rarity].power.."."})
	recipe(a.id,{skill="Carpentry",level=1,xp=40*Data.Rarity[a.rarity].rank,costs=a.costs,collectionTier=a.collectionTier,station="Workbench",category="Accessories"})
end
Data.AccessoryBag = {baseSlots=3,slotsPerLevel={skill="Combat",every=5},maxSlots=24}

------------------------------------------------------------------------------
-- Pets: level 1-100, gain a share of their skill's XP, stats scale by level.
------------------------------------------------------------------------------
Data.Pets = {
	{id="Tidewing",name="Tidewing",skill="Fishing",rarity="Rare",color="3F7CAC",perLevel={fishingFortune=0.6,seaCreatureChance=0.05,health=0.5},ability="Sky Diver: +10% Fishing XP"},
	{id="Burrowmole",name="Burrowmole",skill="Mining",rarity="Uncommon",color="8C7A6B",perLevel={miningFortune=0.8,defense=0.3},ability="Deep Digger: +10% Mining XP"},
	{id="Mossback",name="Mossback Tortoise",skill="Farming",rarity="Uncommon",color="5E8C4A",perLevel={farmingFortune=0.8,health=0.8},ability="Rooted: +10% Farming XP"},
	{id="Sapling",name="Sapling Sprite",skill="Woodcutting",rarity="Rare",color="6BBF59",perLevel={foragingFortune=0.8,strength=0.2},ability="Grove Song: +10% Woodcutting XP"},
	{id="Emberfox",name="Emberfox",skill="Combat",rarity="Epic",color="E07A5F",perLevel={strength=0.4,critDamage=0.3},ability="Kindled Fury: +10% Combat XP"},
	{id="Gloomwing",name="Gloomwing Bat",skill="Combat",rarity="Rare",color="5A5A8C",perLevel={critChance=0.1,speed=0.2,intelligence=0.3},ability="Echo Hunt: +5% Magic Find"},
	{id="Aurelion",name="Aurelion",skill="Combat",rarity="Legendary",color="FFAA00",perLevel={strength=0.6,critDamage=0.6,critChance=0.1,health=1},ability="Starborn Pride: +20% Combat XP"},
	{id="Cindercrab",name="Cindercrab",skill="Smithing",rarity="Uncommon",color="C8553D",perLevel={defense=0.6,miningSpeed=1},ability="Forge Heat: +10% Smithing XP"},
}
Data.PetById = {}
for _, pet in ipairs(Data.Pets) do
	Data.PetById[pet.id] = pet
	item(pet.id.."Pet",{name=pet.name.." Pet",kind="pet",pet=pet.id,rarity=pet.rarity,color=pet.color,value=200*Data.Rarity[pet.rarity].rank^2,description="Summon from your pet menu. "..pet.ability})
end
Data.PET_MAX_LEVEL = 100
function Data.petXpToNext(level, rarity)
	local mult = ({Common=1,Uncommon=1.3,Rare=1.7,Epic=2.2,Legendary=3,Mythic=4})[rarity] or 1
	return math.floor(100 * level ^ 1.55 * mult)
end

------------------------------------------------------------------------------
-- Collections: SkyBlock-style 9 tiers per item; tiers unlock recipes.
------------------------------------------------------------------------------
Data.CollectionTiers = {50,100,250,500,1000,2500,5000,10000,25000}
Data.CollectionTierAmount = Data.CollectionTiers
Data.CollectionItems = {}
for _, skill in ipairs({"Mining","Woodcutting","Fishing","Farming"}) do
	for _, r in ipairs(Data.ResourceTiers[skill]) do table.insert(Data.CollectionItems, r.id) end
end
for _, id in ipairs({"Shard","BeastHide","SpiderSilk","VoidEssence","StormFeather","GolemCore","SlayerToken","ArcaneDust"}) do
	table.insert(Data.CollectionItems, id)
end
-- Drop-only collections reach their tiers sooner.
Data.CollectionScale = {Shard=0.1,GolemCore=0.05,SlayerToken=0.04,VoidEssence=0.2,StormFeather=0.3,SpiderSilk=0.5,BeastHide=0.5,ArcaneDust=1}
-- Coins and a skill XP reward granted per collection tier claim.
function Data.collectionTierReward(tier) return {coins=50*tier*tier} end

------------------------------------------------------------------------------
-- Enchantments (SkyBlock-style, OSRS-style level gates).
------------------------------------------------------------------------------
Data.Enchants = {
	Sharpness={name="Sharpness",appliesTo="weapon",maxLevel=5,perLevel={damagePercent=5},level=1,description="+5% weapon damage per level"},
	Critical={name="Critical",appliesTo="weapon",maxLevel=5,perLevel={critDamage=10},level=10,description="+10 Crit Damage per level"},
	Vampirism={name="Lifesteal",appliesTo="weapon",maxLevel=3,perLevel={lifesteal=1},level=35,description="Heal 1% of max health per hit per level"},
	Protection={name="Protection",appliesTo="armor",maxLevel=5,perLevel={defense=4},level=1,description="+4 Defense per level"},
	Growth={name="Growth",appliesTo="armor",maxLevel=5,perLevel={health=15},level=10,description="+15 Health per level"},
	Efficiency={name="Efficiency",appliesTo="tool",maxLevel=5,perLevel={miningSpeed=20},level=5,description="+20 tool speed per level"},
	Fortune={name="Fortune",appliesTo="tool",maxLevel=4,perLevel={fortune=10},level=20,description="+10 fortune for the tool's skill per level"},
}
-- Cost of applying enchant level L: Arcane Dust and coins; XP awarded.
function Data.enchantCost(level) return {ArcaneDust=4*level*level,coins=100*level*level} end
function Data.enchantXp(level) return 30*level*level end
function Data.enchantSkillLevel(enchant, level) return math.min(99, enchant.level + (level-1)*12) end

------------------------------------------------------------------------------
-- Regions: travel destinations with requirements (OSRS gated areas).
------------------------------------------------------------------------------
Data.Regions = {
	{id="Hub",name="Compass Quay",requires={},description="The shared hub: bank, market and guild."},
	{id="Meadow",name="Sunwheel Downs",requires={},description="Gentle hills. Brambleback boars and Thornlings roam.",monsters={"BramblebackBoar","Thornling"}},
	{id="Quarry",name="Brassfall Cay",requires={},description="Copperstone and Aetherite seams.",monsters={"ShaleCrawler","CinderMite"}},
	{id="Skyreach",name="Skyreach Heights",requires={quest=6},description="Rich Aetherite and Brass golems.",monsters={"BrassGolem","StormHarrier"}},
	{id="Windpine",name="Windpine Grove",requires={skills={Woodcutting=10}},description="Ancient windpines and emberoaks. Bark Stalkers hunt here.",monsters={"BarkStalker","GaleSprite"}},
	{id="Gloomhollow",name="Gloomhollow Caverns",requires={skills={Mining=30,Combat=15}},description="Voidstone deep below. Gloomfang spiders nest here.",monsters={"GloomfangSpider","VoidWisp"}},
	{id="Tidewater",name="Tidewater Shoals",requires={skills={Fishing=30}},description="Skylakes teeming with rare fish.",monsters={"ReefLurker"}},
	{id="Tempest",name="Tempest Spire",requires={skills={Combat=40}},description="The storm-wracked summit. Wraiths and starborn sentinels.",monsters={"TempestWraith","StarbornSentinel"}},
}
Data.RegionById = {}
for _, r in ipairs(Data.Regions) do Data.RegionById[r.id] = r end

------------------------------------------------------------------------------
-- Monsters: level, hp, damage, defense, xp, coins, drop table.
-- chance is a probability per kill (Magic Find multiplies chances < 5%).
------------------------------------------------------------------------------
Data.Monsters = {
	BramblebackBoar={name="Brambleback Boar",level=2,region="Meadow",hp=120,damage=12,defense=0,xp=12,coins=4,speed=12,color="8D6346",slayer="Bramble",
		drops={{item="BeastHide",chance=0.8,min=1,max=2},{item="ArcaneDust",chance=0.15,min=1,max=1}}},
	Thornling={name="Thornling",level=5,region="Meadow",hp=220,damage=20,defense=5,xp=20,coins=6,speed=14,color="5E8C4A",slayer="Bramble",
		drops={{item="Herb",chance=0.6,min=1,max=3},{item="ArcaneDust",chance=0.2,min=1,max=1},{item="MossbackPet",chance=0.002,min=1,max=1}}},
	ShaleCrawler={name="Shale Crawler",level=8,region="Quarry",hp=350,damage=30,defense=15,xp=28,coins=8,speed=11,color="8C7A6B",
		drops={{item="Ore",chance=0.7,min=2,max=4},{item="ArcaneDust",chance=0.25,min=1,max=2},{item="BurrowmolePet",chance=0.002,min=1,max=1}}},
	CinderMite={name="Cinder Mite",level=12,region="Quarry",hp=500,damage=45,defense=20,xp=36,coins=10,speed=16,color="C8553D",
		drops={{item="Aetherite",chance=0.5,min=1,max=2},{item="ArcaneDust",chance=0.3,min=1,max=2},{item="CindercrabPet",chance=0.0015,min=1,max=1}}},
	BarkStalker={name="Bark Stalker",level=18,region="Windpine",hp=900,damage=70,defense=40,xp=55,coins=14,speed=15,color="6B8E5A",slayer="Bramble",
		drops={{item="WindpineLog",chance=0.6,min=2,max=4},{item="BeastHide",chance=0.5,min=1,max=3},{item="ArcaneDust",chance=0.35,min=1,max=3},{item="SaplingPet",chance=0.0015,min=1,max=1}}},
	GaleSprite={name="Gale Sprite",level=24,region="Windpine",hp=1200,damage=85,defense=30,xp=70,coins=18,speed=20,color="A8DADC",
		drops={{item="StormFeather",chance=0.4,min=1,max=2},{item="ArcaneDust",chance=0.4,min=1,max=3}}},
	BrassGolem={name="Brass Golem",level=28,region="Skyreach",hp=2200,damage=110,defense=120,xp=95,coins=25,speed=9,color="D4A84B",
		drops={{item="Brassite",chance=0.8,min=2,max=5},{item="GolemCore",chance=0.08,min=1,max=1},{item="ArcaneDust",chance=0.45,min=2,max=4}}},
	StormHarrier={name="Storm Harrier",level=32,region="Skyreach",hp=1800,damage=140,defense=50,xp=105,coins=28,speed=22,color="7B8CDE",
		drops={{item="StormFeather",chance=0.7,min=1,max=3},{item="ArcaneDust",chance=0.45,min=2,max=4},{item="GloomwingPet",chance=0.001,min=1,max=1}}},
	GloomfangSpider={name="Gloomfang Spider",level=40,region="Gloomhollow",hp=4000,damage=210,defense=90,xp=160,coins=40,speed=18,color="3D3D5C",slayer="Gloom",
		drops={{item="SpiderSilk",chance=0.8,min=1,max=3},{item="Voidstone",chance=0.25,min=1,max=2},{item="ArcaneDust",chance=0.5,min=2,max=5}}},
	VoidWisp={name="Void Wisp",level=50,region="Gloomhollow",hp=6000,damage=280,defense=120,xp=220,coins=55,speed=19,color="6A4C93",slayer="Gloom",
		drops={{item="VoidEssence",chance=0.5,min=1,max=2},{item="ArcaneDust",chance=0.6,min=3,max=6},{item="StarFragment",chance=0.003,min=1,max=1}}},
	ReefLurker={name="Reef Lurker",level=36,region="Tidewater",hp=3000,damage=170,defense=80,xp=130,coins=34,speed=14,color="06D6A0",
		drops={{item="Stormeel",chance=0.6,min=1,max=3},{item="ArcaneDust",chance=0.45,min=2,max=4},{item="TidewingPet",chance=0.0015,min=1,max=1}}},
	TempestWraith={name="Tempest Wraith",level=65,region="Tempest",hp=12000,damage=420,defense=180,xp=360,coins=80,speed=20,color="4B6584",slayer="Tempest",
		drops={{item="VoidEssence",chance=0.7,min=1,max=3},{item="StormFeather",chance=0.6,min=2,max=4},{item="ArcaneDust",chance=0.7,min=4,max=8},{item="EmberfoxPet",chance=0.001,min=1,max=1}}},
	StarbornSentinel={name="Starborn Sentinel",level=80,region="Tempest",hp=20000,damage=600,defense=300,xp=520,coins=120,speed=12,color="FFF3B0",slayer="Tempest",
		drops={{item="StarmetalOre",chance=0.6,min=2,max=4},{item="StarFragment",chance=0.02,min=1,max=1},{item="ArcaneDust",chance=0.8,min=5,max=10},{item="AurelionPet",chance=0.0005,min=1,max=1}}},
}
-- Remove placeholder rows with zero chance (kept data tables tidy).
for _, m in pairs(Data.Monsters) do
	local kept = {}
	for _, d in ipairs(m.drops) do if d.chance > 0 and Data.Items[d.item] then table.insert(kept, d) end end
	m.drops = kept
end
-- Bestiary milestones: kills per tier give permanent bonus (SkyBlock bestiary).
Data.BestiaryTiers = {10,25,50,100,250,500,1000}
Data.BestiaryBonus = {health=1,strength=0.5}

------------------------------------------------------------------------------
-- Slayer: three lines, four tiers each; slayer levels 1-9.
------------------------------------------------------------------------------
Data.SlayerLevels = {5,15,200,1000,5000,20000,100000,400000,1000000}
Data.SlayerOrder = {"Bramble","Gloom","Tempest"}
Data.Slayers = {
	Bramble={name="Brambleback Matriarch",line="Beast",color="8D6346",requires={Combat=5},rewardStat={health=4},
		tiers={
			{hp=1500,damage=40,cost=200,xp=5,spawnXp=150,combatLevel=5,drops={{item="BeastHide",chance=1,min=5,max=10},{item="SlayerToken",chance=1,min=1,max=1}}},
			{hp=6000,damage=110,cost=1000,xp=25,spawnXp=500,combatLevel=12,drops={{item="BeastHide",chance=1,min=10,max=20},{item="SlayerToken",chance=1,min=2,max=3},{item="MossbackPet",chance=0.01,min=1,max=1}}},
			{hp=25000,damage=260,cost=5000,xp=100,spawnXp=1200,combatLevel=20,drops={{item="SlayerToken",chance=1,min=4,max=6},{item="ArcaneDust",chance=1,min=10,max=20},{item="StarFragment",chance=0.01,min=1,max=1}}},
			{hp=80000,damage=520,cost=25000,xp=500,spawnXp=3000,combatLevel=30,drops={{item="SlayerToken",chance=1,min=8,max=12},{item="StarFragment",chance=0.04,min=1,max=1},{item="EmberfoxPet",chance=0.005,min=1,max=1}}},
		}},
	Gloom={name="Gloomfang Broodmother",line="Arachnid",color="3D3D5C",requires={Combat=20},rewardStat={critDamage=2},
		tiers={
			{hp=12000,damage=200,cost=2000,xp=5,spawnXp=800,combatLevel=20,drops={{item="SpiderSilk",chance=1,min=10,max=20},{item="SlayerToken",chance=1,min=2,max=2}}},
			{hp=40000,damage=380,cost=7500,xp=25,spawnXp=2000,combatLevel=28,drops={{item="SpiderSilk",chance=1,min=20,max=40},{item="SlayerToken",chance=1,min=3,max=5},{item="GloomwingPet",chance=0.01,min=1,max=1}}},
			{hp=120000,damage=640,cost=20000,xp=100,spawnXp=4000,combatLevel=36,drops={{item="SlayerToken",chance=1,min=6,max=9},{item="VoidEssence",chance=1,min=4,max=8},{item="StarFragment",chance=0.03,min=1,max=1}}},
			{hp=350000,damage=1000,cost=60000,xp=500,spawnXp=8000,combatLevel=45,drops={{item="SlayerToken",chance=1,min=12,max=18},{item="StarFragment",chance=0.08,min=1,max=2}}},
		}},
	Tempest={name="Tempest Revenant",line="Spectral",color="4B6584",requires={Combat=40},rewardStat={strength=3},
		tiers={
			{hp=60000,damage=500,cost=10000,xp=5,spawnXp=3000,combatLevel=40,drops={{item="VoidEssence",chance=1,min=5,max=10},{item="SlayerToken",chance=1,min=4,max=5}}},
			{hp=200000,damage=800,cost=30000,xp=25,spawnXp=6000,combatLevel=48,drops={{item="SlayerToken",chance=1,min=6,max=9},{item="StarFragment",chance=0.04,min=1,max=1}}},
			{hp=600000,damage=1300,cost=80000,xp=100,spawnXp=12000,combatLevel=56,drops={{item="SlayerToken",chance=1,min=10,max=15},{item="StarFragment",chance=0.1,min=1,max=2}}},
			{hp=1500000,damage=2000,cost=200000,xp=500,spawnXp=25000,combatLevel=64,drops={{item="SlayerToken",chance=1,min=20,max=30},{item="StarFragment",chance=0.25,min=1,max=3},{item="AurelionPet",chance=0.01,min=1,max=1}}},
		}},
}

------------------------------------------------------------------------------
-- Workers (SkyBlock minions): tiers 1-7, slots unlock by unique tiers built.
------------------------------------------------------------------------------
Data.WorkerTiers = {
	{interval=120,capacity=120},{interval=90,capacity=240},{interval=60,capacity=360},
	{interval=48,capacity=480},{interval=40,capacity=640},{interval=32,capacity=800},{interval=26,capacity=1000},
}

------------------------------------------------------------------------------
-- Dungeons (owned by the Dungeons team; append-only section).
-- Observatory floors I-V (Catacombs-style floors, OSRS raid-style grading).
-- Pure data + pure rules: expedition.server.lua runs the encounter, the
-- IsleExpeditionReward handler in server.server.lua pays out, and
-- verify-expedition.luau checks these formulas directly.
------------------------------------------------------------------------------
item("ObservatoryEssence",{name="Observatory Essence",kind="material",rarity="Rare",color="8E7CC3",value=30,description="Condensed starlight from cleared Observatory floors."})
Data.Sets.Observatory = {id="Observatory",name="Starwright Regalia",pieces={},bonus={intelligence=40,magicFind=6,health=60},text="+40 Intelligence, +6 Magic Find, +60 Health",color="8E7CC3"}
local observatoryArmor = {
	{id="ObservatoryHelm",slot="helmet",name="Starwright Hood",stats={defense=45,health=35,intelligence=15},level=5},
	{id="ObservatoryVestment",slot="chest",name="Starwright Vestment",stats={defense=85,health=70,intelligence=25},level=12},
	{id="ObservatoryGreaves",slot="legs",name="Starwright Greaves",stats={defense=70,health=55,intelligence=20},level=12},
	{id="ObservatoryTreads",slot="boots",name="Starwright Treads",stats={defense=40,health=30,speed=5},level=5},
}
for _, a in ipairs(observatoryArmor) do
	item(a.id,{name=a.name,kind="armor",slot=a.slot,set="Observatory",rarity="Epic",color="8E7CC3",stats=a.stats,dungeon=true,
		requires={Combat=a.level,Dungeoneering=a.level},value=400+a.level*30,
		description="Observatory chest drop. Part of the Starwright Regalia set. Requires Dungeoneering "..a.level.."."})
	table.insert(Data.Sets.Observatory.pieces, a.id)
end
item("LenswrightSaber",{name="Lenswright Saber",kind="weapon",slot="weapon",rarity="Rare",color="7FB8E8",dungeon=true,
	stats={damage=85,strength=35,critDamage=20,intelligence=20},requires={Combat=8,Dungeoneering=5},value=520,
	description="Observatory Floor II+ chest drop. Requires Dungeoneering 5."})
item("EclipseGlaive",{name="Eclipse Glaive",kind="weapon",slot="weapon",rarity="Epic",color="E0A458",dungeon=true,
	stats={damage=150,strength=60,critChance=5,critDamage=40},requires={Combat=20,Dungeoneering=20},value=2400,
	description="Observatory Floor IV+ chest drop. Requires Dungeoneering 20."})
item("AstrarchFang",{name="Astrarch Fang",kind="weapon",slot="weapon",rarity="Legendary",color="B48EF0",dungeon=true,
	stats={damage=230,strength=90,critChance=8,critDamage=70,intelligence=40},requires={Combat=30,Dungeoneering=30},value=9000,
	description="Observatory Floor V chest drop. Requires Dungeoneering 30."})
-- Dungeon-only accessories: no recipe; only Observatory chests drop them.
item("AstrolabeCharm",{name="Astrolabe Charm",kind="accessory",rarity="Epic",color=Data.Rarity.Epic.color,dungeon=true,
	stats={magicFind=4,intelligence=15,health=20},value=40*Data.Rarity.Epic.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Epic.power..". Dungeon-only: Observatory chests."})
item("UmbralOrrery",{name="Umbral Orrery",kind="accessory",rarity="Legendary",color=Data.Rarity.Legendary.color,dungeon=true,
	stats={magicFind=6,strength=10,critDamage=10},value=40*Data.Rarity.Legendary.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Legendary.power..". Dungeon-only: Observatory Floor V."})

-- Party, pad, cooldown and credit rules.
Data.Dungeons = {
	maxParty = 5,              -- the matchmaking pad admits at most five delvers
	padSeconds = 10,           -- stand on the pad within this window to join the run
	padRadius = 8,             -- studs from the pad centre (horizontal)
	clearCooldown = 90,        -- seconds between reward credits per player
	ironmanDamageShare = 0.30, -- Ironman credited only when solo or >= 30% of party damage
	contributionShare = 0.10,  -- "contributed" = >= 10% of the party's contribution points
	tuneWeight = 0.05,         -- one prism tuning = 5% of the floor's total HP in contribution points
	baseGuardianHp = 6, baseCoreHp = 12, baseGuardianHit = 6,
}
-- mechanics: orderedPrisms (II+), shieldPhases (III+: core HP fractions that
-- raise a shield until the prisms are retuned), addWaves (IV+: wisps that ward
-- the core while alive), enrage (V: after N seconds boss damage and tempo rise).
-- boss.kind: pulse (stand outside radius), ring (stand inside inner),
-- meteor (move off the marked delver), eclipse (alternates pulse and ring).
Data.DungeonFloors = {
	{index=1,numeral="I",name="Observatory Floor I",subtitle="Entrance",level=1,hpMult=1,damageMult=1,par=180,mechanics={},
		boss={name="Eclipse Heart",attack="Amber Pulse",kind="pulse",radius=13.5,damage=18,interval=5,telegraph=1.5},
		rewards={dungeoneeringXp=60,combatXp=80,coins=35,stormglass=1,essence=1},
		chest={{item="ObservatoryEssence",chance=0.25,min=1,max=2},{item="AstrolabeCharm",chance=0.004,min=1,max=1}}},
	{index=2,numeral="II",name="Observatory Floor II",subtitle="Lens Gallery",level=5,hpMult=1.75,damageMult=1.5,par=240,mechanics={orderedPrisms=true},
		boss={name="Lens Tyrant",attack="Refraction Ring",kind="ring",inner=10,radius=30,damage=24,interval=6,telegraph=2},
		rewards={dungeoneeringXp=150,combatXp=180,coins=90,stormglass=1,essence=2},
		chest={{item="ObservatoryEssence",chance=0.35,min=1,max=3},{item="LenswrightSaber",chance=0.02,min=1,max=1},{item="ObservatoryHelm",chance=0.03,min=1,max=1},
			{item="ObservatoryTreads",chance=0.03,min=1,max=1},{item="AstrolabeCharm",chance=0.006,min=1,max=1}}},
	{index=3,numeral="III",name="Observatory Floor III",subtitle="Gyre Vault",level=12,hpMult=2.75,damageMult=2.1,par=300,mechanics={orderedPrisms=true,shieldPhases={0.66,0.33}},
		boss={name="Gyre Oracle",attack="Starfall",kind="meteor",radius=9,damage=30,interval=6,telegraph=2},
		rewards={dungeoneeringXp=320,combatXp=360,coins=200,stormglass=2,essence=4},
		chest={{item="ObservatoryEssence",chance=0.45,min=2,max=4},{item="ObservatoryVestment",chance=0.025,min=1,max=1},{item="ObservatoryGreaves",chance=0.025,min=1,max=1},
			{item="LenswrightSaber",chance=0.03,min=1,max=1},{item="AstrolabeCharm",chance=0.01,min=1,max=1}}},
	{index=4,numeral="IV",name="Observatory Floor IV",subtitle="Regent's Dome",level=20,hpMult=4,damageMult=2.8,par=360,
		mechanics={orderedPrisms=true,shieldPhases={0.5},addWaves={every=20,count=2,hp=4}},
		boss={name="Hollow Regent",attack="Eclipse Sweep",kind="pulse",radius=20,damage=34,interval=5,telegraph=2},
		rewards={dungeoneeringXp=600,combatXp=650,coins=400,stormglass=3,essence=6},
		chest={{item="ObservatoryEssence",chance=0.55,min=3,max=6},{item="EclipseGlaive",chance=0.012,min=1,max=1},{item="ObservatoryVestment",chance=0.04,min=1,max=1},
			{item="StarFragment",chance=0.03,min=1,max=1},{item="AstrolabeCharm",chance=0.015,min=1,max=1}}},
	{index=5,numeral="V",name="Observatory Floor V",subtitle="Umbral Apex",level=30,hpMult=5.5,damageMult=3.6,par=420,
		mechanics={orderedPrisms=true,shieldPhases={0.66,0.33},addWaves={every=18,count=3,hp=5},enrage={after=240,damageMult=2,intervalMult=0.5}},
		boss={name="Umbral Astrarch",attack="Total Eclipse",kind="eclipse",inner=10,radius=13.5,damage=40,interval=5,telegraph=2},
		rewards={dungeoneeringXp=1000,combatXp=1050,coins=750,stormglass=4,essence=9},
		chest={{item="ObservatoryEssence",chance=0.65,min=4,max=8},{item="AstrarchFang",chance=0.006,min=1,max=1},{item="EclipseGlaive",chance=0.02,min=1,max=1},
			{item="StarFragment",chance=0.05,min=1,max=2},{item="AstrolabeCharm",chance=0.02,min=1,max=1},{item="UmbralOrrery",chance=0.004,min=1,max=1}}},
}
-- Grades: score 0-300 (speed + survival + puzzle, 100 each). mult scales XP,
-- coins and essence; chance scales the chest's rare roll (before Magic Find).
Data.DungeonGrades = {
	{grade="S+",min=290,mult=1.6,chance=2,bonusStormglass=1},
	{grade="S",min=260,mult=1.35,chance=1.5,bonusStormglass=1},
	{grade="A",min=220,mult=1.15,chance=1.25,bonusStormglass=0},
	{grade="B",min=170,mult=1,chance=1,bonusStormglass=0},
	{grade="C",min=110,mult=0.8,chance=0.8,bonusStormglass=0},
	{grade="D",min=0,mult=0.6,chance=0.5,bonusStormglass=0},
}
Data.DungeonGradeById = {}
for _, g in ipairs(Data.DungeonGrades) do Data.DungeonGradeById[g.grade] = g end
function Data.dungeonFloorStats(floorIndex)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local d = Data.Dungeons
	return {guardianHp=math.ceil(d.baseGuardianHp*f.hpMult),coreHp=math.ceil(d.baseCoreHp*f.hpMult),
		guardianHit=math.floor(d.baseGuardianHit*f.damageMult),addHp=f.mechanics.addWaves and math.ceil(f.mechanics.addWaves.hp*f.hpMult) or 0}
end
-- Score: speed (full until par, 0 at twice par) + survival (-20 per death)
-- + puzzle skill (-15 per wrong tuning), each clamped to 0..100.
function Data.dungeonScore(floorIndex, seconds, deaths, mistakes)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local over = math.max(0, (seconds or 0) - f.par)
	local speed = math.clamp(100 - over * 100 / f.par, 0, 100)
	local survival = math.clamp(100 - (deaths or 0) * 20, 0, 100)
	local skill = math.clamp(100 - (mistakes or 0) * 15, 0, 100)
	return math.floor(speed + survival + skill + 0.5), {speed=speed,survival=survival,skill=skill}
end
function Data.dungeonGrade(score)
	for _, g in ipairs(Data.DungeonGrades) do if score >= g.min then return g.grade end end
	return "D"
end
-- Rewards for one credited clear. chest is a drop table for Progression.rollDrops.
function Data.dungeonRewards(floorIndex, grade)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local g = Data.DungeonGradeById[grade] or Data.DungeonGradeById.B
	local r = f.rewards
	local chest = {}
	for _, d in ipairs(f.chest) do
		table.insert(chest,{item=d.item,chance=math.min(1,d.chance*g.chance),min=d.min,max=d.max})
	end
	return {dungeoneeringXp=math.floor(r.dungeoneeringXp*g.mult),combatXp=math.floor(r.combatXp*g.mult),coins=math.floor(r.coins*g.mult),
		items={Stormglass=r.stormglass+g.bonusStormglass,ObservatoryEssence=math.max(1,math.floor(r.essence*g.mult))},chest=chest}
end
function Data.dungeonCooldownReady(lastClear, now)
	return lastClear == nil or now - lastClear >= Data.Dungeons.clearCooldown
end
-- Ironman journals keep solo integrity: credited when they ran the floor alone
-- or personally dealt >= 30% of the party's damage. Other journals always pass.
function Data.dungeonIronmanCredit(ironman, partySize, damageShare)
	if not ironman then return true end
	return (partySize or 1) <= 1 or (damageShare or 0) >= Data.Dungeons.ironmanDamageShare
end
-- Meaningful participation: damage + weighted tunings >= 10% of the party total.
function Data.dungeonContributed(points, totalPoints)
	if not points or points <= 0 or not totalPoints or totalPoints <= 0 then return false end
	return points / totalPoints >= Data.Dungeons.contributionShare
end
function Data.dungeonFloorUnlocked(floorIndex, dungeoneeringLevel)
	local f = Data.DungeonFloors[floorIndex]
	return f ~= nil and (dungeoneeringLevel or 1) >= f.level
end
-- End Dungeons section.

------------------------------------------------------------------------------
-- Economy (Bazaar standing orders + Auction House). Appended by the Economy team.
-- Bazaar: any resource/material item; prices are per unit. Auction House: one
-- gear item per listing, 1% listing fee (coin sink), 24 hour expiry.
------------------------------------------------------------------------------
Data.Economy = {
	orderCap=10, listingCap=10, maxQuantity=640, minPrice=1, maxPrice=1000000,
	bookCap=400, auctionCap=600, accountCap=3000, depth=5, pageSize=8, maxPage=75,
	auctionDuration=86400, feePercent=1,
	auctionCategories={"weapon","armor","tool","accessory","pet"},
	categoryNames={weapon="Weapons",armor="Armor",tool="Tools",accessory="Accessories",pet="Pets"},
	bazaarGroups={"Mining","Woodcutting","Fishing","Farming","Materials"},
}
-- Listing fee: 1% of the buy-it-now price, rounded up, at least 1 coin.
function Data.Economy.auctionFee(price)
	return math.max(1, math.ceil(price * Data.Economy.feePercent / 100))
end
function Data.Economy.isCommodity(id)
	local def = type(id) == "string" and Data.Items[id]
	return def ~= nil and def ~= false and (def.kind == "resource" or def.kind == "material")
end
-- Auction category (item kind) for gear, or nil.
function Data.Economy.auctionCategory(id)
	local def = type(id) == "string" and Data.Items[id]
	if not def then return nil end
	for _, kind in ipairs(Data.Economy.auctionCategories) do
		if def.kind == kind then return kind end
	end
	return nil
end
-- Bazaar chooser group for a commodity (gathering skill, or Materials).
function Data.Economy.bazaarGroup(id)
	local def = Data.Items[id]
	if def and def.kind == "resource" then return Data.ResourceSkill[id] or "Materials" end
	return "Materials"
end

------------------------------------------------------------------------------
-- Quests & Achievements (Quests team; append-only section).
-- OSRS-style quest line with Quest Points and choose-a-skill XP lamps,
-- per-region achievement diaries (Easy/Medium/Hard/Elite) and Carpentry
-- construction on fixed home hotspots (SkyBlock island building).
--
-- A check is {kind=..., ...}; the server evaluates every check from profile
-- state (never from the client):
--   contracts {count}          guild contracts claimed (p.questCompleted)
--   quest {quest}              a Data.Quests entry claimed
--   questPoints {count}        Quest Points held
--   level {skill,level}        skill level (OSRS curve)
--   collect {item,count}       lifetime collection count
--   collectionTier {item,tier} collection tier
--   have {item,count,consume}  satchel count; consume=true hands items in on claim
--   kills {monster,count}      bestiary kills
--   craft {item,count}         items crafted (p.counters.crafts)
--   gather {region,count}      harvests at that region's nodes (p.counters.gathers)
--   build {furniture}          furniture ever built (p.counters.built)
--   slayer {line,level}        slayer level of a line
--   flag {flag}                p[flag] == true (e.g. skyreachVisited)
-- Rewards: coins, items={id=n}, xp={Skill=n}, lamp={xp=n,skills={...}|nil,exclude={...}|nil},
-- (a lamp without a skills list never trains Dungeoneering or Carpentry: those
-- skills have floor/hotspot gates, so `exclude` lists them and the server enforces it),
-- points (Quest Points), perk={stat=v} (written to p.perkStats),
-- unlock={accessorySlots=n, workerHaste=fraction, shortcut=regionId}.
------------------------------------------------------------------------------
do
local function qlist(...) return {...} end
Data.Quests = {
	-- Main line: continues after the eight guild contracts.
	{id="SurveyorsOath",title="The Surveyor's Oath",line="main",region="Meadow",
		story="Warden-captain Ysolde asks you to prove the guild charter in the field: thin the boars trampling the meadow herb beds.",
		requires=qlist({kind="contracts",count=8}),
		objectives=qlist({kind="kills",monster="BramblebackBoar",count=10},{kind="collect",item="Herb",count=100}),
		rewards={coins=400,points=1,lamp={xp=600,exclude={"Dungeoneering","Carpentry"}}}},
	{id="BrassfallEchoes",title="Echoes under Brassfall",line="main",region="Quarry",
		story="Something knocks beneath Brassfall Quarry. Clear the crawlers and smelt brass for the shoring beams.",
		requires=qlist({kind="quest",quest="SurveyorsOath"},{kind="level",skill="Mining",level=15}),
		objectives=qlist({kind="kills",monster="ShaleCrawler",count=15},{kind="collect",item="Brassite",count=50},{kind="craft",item="BrassIngot",count=5}),
		rewards={coins=900,points=2,xp={Smithing=1200},unlock={accessorySlots=1}}},
	{id="WindpineVigil",title="Windpine Vigil",line="main",region="Windpine",
		story="The old grove-keeper Tamsin hears the windpines whisper of a stalker among the roots. Keep vigil and cut a clearing.",
		requires=qlist({kind="quest",quest="BrassfallEchoes"},{kind="level",skill="Woodcutting",level=15}),
		objectives=qlist({kind="gather",region="Windpine",count=40},{kind="kills",monster="BarkStalker",count=12}),
		rewards={coins=1500,points=2,items={MightDraught=3},lamp={xp=2000,skills={"Mining","Woodcutting","Fishing","Farming"}}}},
	{id="HollowLantern",title="The Hollow Lantern",line="main",region="Gloomhollow",
		story="A miner's lantern still burns deep in Gloomhollow. Follow its light past the Gloomfang nests and weave a silk lifeline home.",
		requires=qlist({kind="quest",quest="WindpineVigil"},{kind="level",skill="Mining",level=30},{kind="level",skill="Combat",level=15}),
		objectives=qlist({kind="kills",monster="GloomfangSpider",count=20},{kind="collect",item="Voidstone",count=40},{kind="have",item="SpiderSilk",count=16,consume=true}),
		rewards={coins=4000,points=3,lamp={xp=6000,exclude={"Dungeoneering","Carpentry"}},unlock={shortcut="Gloomhollow"}}},
	{id="CrownOfTempest",title="Crown of the Tempest",line="main",region="Tempest",
		story="The storm atop Tempest Spire has a heart. Break the wraith host and the starborn sentinels, then face the Revenant itself.",
		requires=qlist({kind="quest",quest="HollowLantern"},{kind="level",skill="Combat",level=40},{kind="questPoints",count=14}),
		objectives=qlist({kind="kills",monster="TempestWraith",count=25},{kind="kills",monster="StarbornSentinel",count=5},{kind="slayer",line="Tempest",level=1}),
		rewards={coins=20000,points=4,lamp={xp=25000,exclude={"Dungeoneering","Carpentry"}},perk={strength=10,critDamage=10},unlock={workerHaste=0.05}}},
	-- Side quests.
	{id="TidewingLullaby",title="A Lullaby for the Tidewing",line="side",region="Hub",
		story="The harbour Tidewings are restless. Bring fresh minnows and learn the angler's lullaby.",
		requires=qlist({kind="contracts",count=4}),
		objectives=qlist({kind="have",item="Fish",count=20,consume=true},{kind="level",skill="Fishing",level=10}),
		rewards={coins=300,points=1,items={CookedFish=5},xp={Taming=400}}},
	{id="ThornlingGarden",title="The Thornling Garden",line="side",region="Meadow",
		story="Thornlings have rooted in the sunwheat rows. Weed them out and bring in the harvest.",
		requires=qlist({kind="contracts",count=2}),
		objectives=qlist({kind="kills",monster="Thornling",count=15},{kind="collect",item="Sunwheat",count=50}),
		rewards={coins=600,points=1,lamp={xp=800,skills={"Farming","Woodcutting"}},perk={farmingFortune=5}}},
	{id="BuildersCharter",title="The Builder's Charter",line="side",region="Hub",
		story="Master joiner Orrin will register your homestead terrace once you raise your first workbench on it.",
		requires=qlist({kind="contracts",count=3}),
		objectives=qlist({kind="build",furniture="SturdyWorkbench"}),
		rewards={coins=500,points=1,xp={Carpentry=800}}},
	{id="CinderCartography",title="Cinder Cartography",line="side",region="Quarry",
		story="The guild's quarry charts end where the cinder mites begin. Map the seams and the heights above them.",
		requires=qlist({kind="collectionTier",item="Ore",tier=3},{kind="contracts",count=7}),
		objectives=qlist({kind="kills",monster="CinderMite",count=10},{kind="gather",region="Skyreach",count=20}),
		rewards={coins=800,points=1,xp={Mining=1500}}},
	{id="GolemHeartbeat",title="The Golem's Heartbeat",line="side",region="Skyreach",
		story="Brass golems on Skyreach beat in time. A tinker wants one of their cores to learn why.",
		requires=qlist({kind="contracts",count=6},{kind="level",skill="Smithing",level=20}),
		objectives=qlist({kind="kills",monster="BrassGolem",count=10},{kind="have",item="GolemCore",count=1,consume=true}),
		rewards={coins=2500,points=2,items={SunsteelIngot=5},unlock={accessorySlots=1}}},
	{id="FeathersAloft",title="Feathers Aloft",line="side",region="Skyreach",
		story="Storm Harriers ride the updrafts above Skyreach. Gather their feathers for the guild's wind-reading charms.",
		requires=qlist({kind="quest",quest="GolemHeartbeat"},{kind="level",skill="Combat",level=25}),
		objectives=qlist({kind="kills",monster="StormHarrier",count=15},{kind="collect",item="StormFeather",count=30}),
		rewards={coins=2000,points=2,perk={speed=5}}},
	{id="ReefSong",title="Song of the Reef",line="side",region="Tidewater",
		story="Reef Lurkers drown out the shoal's song. Quiet them and land the lanternrays that carry the melody.",
		requires=qlist({kind="level",skill="Fishing",level=30},{kind="questPoints",count=3}),
		objectives=qlist({kind="kills",monster="ReefLurker",count=15},{kind="gather",region="Tidewater",count=30},{kind="collect",item="Lanternray",count=25}),
		rewards={coins=3000,points=2,lamp={xp=4000,skills={"Fishing","Cooking"}},perk={fishingFortune=10},unlock={shortcut="Tidewater"}}},
	{id="LeyLines",title="Charting the Ley Lines",line="side",region="Hub",
		story="With a portal frame on your terrace, the guild's ley-reader can tune it to the far isles.",
		requires=qlist({kind="quest",quest="HollowLantern"},{kind="level",skill="Carpentry",level=30}),
		objectives=qlist({kind="build",furniture="PortalFrame"},{kind="gather",region="Windpine",count=100}),
		rewards={coins=5000,points=3,unlock={shortcut="Tempest"}}},
}
Data.QuestById = {}
for i, quest in ipairs(Data.Quests) do quest.index = i; Data.QuestById[quest.id] = quest end
-- Each claimed guild contract also counts as one Quest Point.
Data.CONTRACT_QUEST_POINTS = 1

------------------------------------------------------------------------------
-- Achievement diaries: per region, four tiers, each claimed in order.
------------------------------------------------------------------------------
Data.DiaryTiers = {"Easy","Medium","Hard","Elite"}
Data.DiaryCoins = {Easy=500,Medium=2500,Hard=10000,Elite=50000}
local function k(monster, count) return {kind="kills",monster=monster,count=count} end
local function c(item, count) return {kind="collect",item=item,count=count} end
local function l(skill, lvl) return {kind="level",skill=skill,level=lvl} end
local function cr(item, count) return {kind="craft",item=item,count=count} end
local function g(region, count) return {kind="gather",region=region,count=count} end
local function s(line, lvl) return {kind="slayer",line=line,level=lvl} end
local function q(quest) return {kind="quest",quest=quest} end
Data.Diaries = {
	{region="Meadow",name="Sunwheel Downs Diary",tiers={
		Easy={tasks={k("BramblebackBoar",5),c("Herb",50),c("Timber",50),l("Farming",5)},perk={health=10}},
		Medium={tasks={k("Thornling",25),c("Sunwheat",100),cr("MightDraught",5),l("Farming",20)},perk={farmingFortune=10}},
		Hard={tasks={k("BramblebackBoar",250),c("Glowcap",250),s("Bramble",3),l("Farming",40)},perk={farmingFortune=15,health=15}},
		Elite={tasks={c("AetherLotus",500),k("Thornling",500),s("Bramble",6),l("Farming",75)},perk={farmingFortune=25,health=25}},
	}},
	{region="Quarry",name="Brassfall Cay Diary",tiers={
		Easy={tasks={c("Ore",100),k("ShaleCrawler",5),cr("AlloyIngot",5),l("Mining",5)},perk={defense=5}},
		Medium={tasks={c("Brassite",100),k("CinderMite",25),cr("BrassIngot",10),l("Mining",20)},perk={miningFortune=10}},
		Hard={tasks={c("SunsteelOre",250),k("CinderMite",250),cr("SunsteelIngot",25),l("Mining",45)},perk={miningFortune=15,defense=10}},
		Elite={tasks={c("Celestium",250),cr("CelestialIngot",20),l("Mining",85),l("Smithing",75)},perk={miningFortune=25,defense=20}},
	}},
	{region="Skyreach",name="Skyreach Heights Diary",tiers={
		Easy={tasks={{kind="flag",flag="skyreachVisited"},g("Skyreach",10),k("BrassGolem",1)},perk={speed=2}},
		Medium={tasks={g("Skyreach",100),k("StormHarrier",25),k("BrassGolem",25),c("StormFeather",50)},perk={strength=5}},
		Hard={tasks={k("BrassGolem",250),c("GolemCore",10),q("GolemHeartbeat"),l("Combat",35)},perk={strength=10,defense=10}},
		Elite={tasks={k("StormHarrier",1000),g("Skyreach",2000),q("FeathersAloft"),l("Combat",60)},perk={strength=15,critDamage=10}},
	}},
	{region="Windpine",name="Windpine Grove Diary",tiers={
		Easy={tasks={g("Windpine",10),k("BarkStalker",1),l("Woodcutting",15)},perk={foragingFortune=5}},
		Medium={tasks={g("Windpine",150),k("GaleSprite",25),c("EmberoakLog",100),q("WindpineVigil")},perk={foragingFortune=10}},
		Hard={tasks={k("BarkStalker",250),c("GlimmerbarkLog",250),l("Woodcutting",50),cr("VoidforgedHatchet",1)},perk={foragingFortune=15,strength=5}},
		Elite={tasks={c("AetherheartLog",500),g("Windpine",3000),l("Woodcutting",80),k("GaleSprite",1000)},perk={foragingFortune=25,strength=10}},
	}},
	{region="Gloomhollow",name="Gloomhollow Caverns Diary",tiers={
		Easy={tasks={g("Gloomhollow",10),k("GloomfangSpider",1),c("Voidstone",10)},perk={defense=5}},
		Medium={tasks={k("GloomfangSpider",50),c("SpiderSilk",100),q("HollowLantern"),s("Gloom",1)},perk={critChance=1}},
		Hard={tasks={k("VoidWisp",100),c("Prismite",100),s("Gloom",4),l("Mining",60)},perk={critDamage=10,defense=10}},
		Elite={tasks={k("VoidWisp",1000),c("VoidEssence",500),s("Gloom",7),l("Mining",80)},perk={critChance=3,critDamage=15}},
	}},
	{region="Tidewater",name="Tidewater Shoals Diary",tiers={
		Easy={tasks={g("Tidewater",10),k("ReefLurker",1),l("Fishing",30)},perk={fishingFortune=5}},
		Medium={tasks={k("ReefLurker",50),c("Lanternray",100),cr("CookedStormeel",25),q("ReefSong")},perk={fishingFortune=10,seaCreatureChance=1}},
		Hard={tasks={c("AbyssKoi",250),k("ReefLurker",500),l("Fishing",60),cr("HuntersFeast",10)},perk={fishingFortune=15,health=20}},
		Elite={tasks={c("LeviathanScale",500),g("Tidewater",3000),l("Fishing",85),l("Cooking",75)},perk={fishingFortune=25,seaCreatureChance=3}},
	}},
	{region="Tempest",name="Tempest Spire Diary",tiers={
		Easy={tasks={g("Tempest",10),k("TempestWraith",1),l("Combat",40)},perk={strength=5}},
		Medium={tasks={k("TempestWraith",50),c("StarmetalOre",100),q("CrownOfTempest"),s("Tempest",1)},perk={strength=10}},
		Hard={tasks={k("StarbornSentinel",100),s("Tempest",4),c("StarmetalOre",1000),l("Combat",60)},perk={critDamage=15,strength=10}},
		Elite={tasks={k("StarbornSentinel",1000),s("Tempest",7),c("Celestium",1000),l("Combat",85)},perk={strength=20,critDamage=25,magicFind=3}},
	}},
}
Data.DiaryByRegion = {}
for _, d in ipairs(Data.Diaries) do Data.DiaryByRegion[d.region] = d end
end

------------------------------------------------------------------------------
-- Carpentry construction: furniture on fixed home hotspots. Hotspot x/z are
-- offsets from the home island centre (the Builder's Terrace sits west).
-- effect: station={...} home crafting prompts, perk={stat=v},
-- accessorySlots=n, workerHaste=fraction, portal={regionId...} (attunable).
------------------------------------------------------------------------------
-- §40 (spread): the add-ons stand in districts out on the big island
-- (terrace west at r52, garden north-west, worker yard south-east, lookout
-- north); Island.migrate relocates any decoration on their new ground.
Data.TERRACE_OFFSET = {x=-52,z=0}
Data.Hotspots = {
	{id="Bench",name="Workshop Bench",x=-46,z=5.2},
	{id="Hearth",name="Kitchen Hearth",x=-52,z=7.4},
	{id="Storage",name="Storage Nook",x=-58,z=5.2},
	{id="Trophy",name="Trophy Alcove",x=-58,z=-5.2},
	{id="Garden",name="Garden Plot",x=-52,z=-7.4},
	{id="Dock",name="Surveyor Dock",x=-46,z=-5.2},
	{id="Portal",name="Portal Circle",x=-55,z=0},
}
Data.HotspotById = {}
for i, h in ipairs(Data.Hotspots) do h.index = i; Data.HotspotById[h.id] = h end
Data.FurnitureRefund = 0.5
Data.Furniture = {
	SturdyWorkbench={name="Sturdy Workbench",hotspot="Bench",level=1,xp=60,costs={Timber=20,Ore=10},color="9C6B3E",effect={station={"Workbench"}},text="Home Workbench station."},
	BrassWorkbench={name="Brass-bound Workbench",hotspot="Bench",level=25,xp=900,costs={WindpineLog=40,BrassIngot=10},color="D4A84B",effect={station={"Workbench","Forge"}},text="Home Workbench and Forge stations."},
	StarforgedBench={name="Starforged Bench",hotspot="Bench",level=60,xp=9000,costs={StarwoodLog=60,StarmetalIngot=12},color="C9D6E3",effect={station={"Workbench","Forge"},perk={strength=5,miningSpeed=20}},text="Home Workbench and Forge; +5 Strength, +20 Mining Speed."},
	ClayHearth={name="Clay Hearth",hotspot="Hearth",level=10,xp=250,costs={Timber=30,Ore=40,Herb=10},color="B5651D",effect={station={"Hearth"}},text="Home Hearth station."},
	EmberoakRange={name="Emberoak Range",hotspot="Hearth",level=40,xp=2500,costs={EmberoakLog=50,SunsteelIngot=8},color="E07A5F",effect={station={"Hearth","Cauldron"},perk={health=15}},text="Home Hearth and Cauldron; +15 Health."},
	TrinketCabinet={name="Trinket Cabinet",hotspot="Storage",level=15,xp=400,costs={WindpineLog=30,BrassIngot=6},color="6B8E5A",effect={accessorySlots=1},text="+1 accessory bag slot."},
	GildedReliquary={name="Gilded Reliquary",hotspot="Storage",level=50,xp=5000,costs={GlimmerbarkLog=40,VoidforgedIngot=10,GolemCore=2},color="FFAA00",effect={accessorySlots=2},text="+2 accessory bag slots."},
	TrophyStand={name="Beast Trophy Stand",hotspot="Trophy",level=20,xp=650,costs={WindpineLog=25,BeastHide=40},color="8D6346",effect={perk={strength=3}},text="+3 Strength."},
	GrandTrophyWall={name="Grand Trophy Wall",hotspot="Trophy",level=55,xp=7000,costs={StarwoodLog=30,SpiderSilk=60,VoidEssence=10},color="5A5A8C",effect={perk={strength=6,critDamage=6}},text="+6 Strength, +6 Crit Damage."},
	HerbPlanter={name="Herb Planter",hotspot="Garden",level=5,xp=120,costs={Timber=25,Herb=30},color="6BBF59",effect={perk={farmingFortune=8}},text="+8 Farming Fortune."},
	MoonbloomTerrace={name="Moonbloom Terrace",hotspot="Garden",level=45,xp=3500,costs={GlimmerbarkLog=30,Moonbloom=60},color="B8C0FF",effect={perk={farmingFortune=20,foragingFortune=10}},text="+20 Farming Fortune, +10 Foraging Fortune."},
	SurveyorDock={name="Surveyor Dock",hotspot="Dock",level=25,xp=900,costs={WindpineLog=40,BrassIngot=8},color="3C9291",effect={workerHaste=0.05},text="Workers gather 5% faster."},
	ClockworkDock={name="Clockwork Dock",hotspot="Dock",level=60,xp=9000,costs={StarwoodLog=50,StarmetalIngot=8,GolemCore=3},color="E0B04A",effect={workerHaste=0.1},text="Workers gather 10% faster."},
	PortalFrame={name="Portal Frame",hotspot="Portal",level=30,xp=1400,costs={EmberoakLog=40,SunsteelIngot=6,Aetherite=50},color="8EE6CB",effect={portal={"Skyreach","Windpine"}},text="Home portal to Skyreach or Windpine (quests attune more isles)."},
	StormglassGate={name="Stormglass Gate",hotspot="Portal",level=65,xp=12000,costs={StarwoodLog=40,StarmetalIngot=10,Stormglass=3},color="7B8CDE",effect={portal={"Skyreach","Windpine","Gloomhollow","Tidewater"},perk={speed=5}},text="Home portal to four regions (quests attune Tempest); +5 Speed."},
}
Data.FurnitureOrder = {}
for id, f in pairs(Data.Furniture) do f.id = id; table.insert(Data.FurnitureOrder, id) end
table.sort(Data.FurnitureOrder, function(a, b)
	local fa, fb = Data.Furniture[a], Data.Furniture[b]
	if fa.level ~= fb.level then return fa.level < fb.level end
	return a < b
end)
Data.PortalRegions = {"Skyreach","Windpine","Gloomhollow","Tidewater","Tempest"}
Data.MAX_PERK_SLOTS = 6
Data.MAX_WORKER_HASTE = 0.3

-- Human-readable text for one check (shared by server messages and the UI).
-- regional = true: a regional quest objective (kills / collect / gather count
-- since the quest was accepted, so "collect" is not a lifetime total there).
function Data.describeCheck(o, regional)
	local function nameOf(id) local def = Data.Items[id]; return def and def.name or tostring(id) end
	local kind = type(o) == "table" and o.kind
	if kind == "contracts" then return "Claim "..o.count.." guild contracts"
	elseif kind == "quest" then local qd = Data.QuestById[o.quest]; return "Complete "..(qd and qd.title or tostring(o.quest))
	elseif kind == "questPoints" then return o.count.." Quest Points"
	elseif kind == "level" then return o.skill.." level "..o.level
	elseif kind == "collect" then return "Collect "..o.count.." "..nameOf(o.item)..(if regional then " (since accepting)" else " (lifetime)")
	elseif kind == "collectionTier" then return nameOf(o.item).." collection tier "..o.tier
	elseif kind == "have" then return (if o.consume then "Hand in " else "Hold ")..o.count.." "..nameOf(o.item)
	elseif kind == "kills" then local m = Data.Monsters[o.monster]; return "Defeat "..o.count.." "..(m and m.name or tostring(o.monster))
	elseif kind == "craft" then return "Craft "..o.count.." "..nameOf(o.item)
	elseif kind == "gather" then local r = Data.RegionById[o.region]; return "Gather "..o.count.." times in "..(r and r.name or tostring(o.region))
	elseif kind == "build" then local f = Data.Furniture[o.furniture]; return "Build a "..(f and f.name or tostring(o.furniture))
	elseif kind == "slayer" then return o.line.." Slayer level "..o.level
	elseif kind == "flag" then return if o.flag == "skyreachVisited" then "Survey the Skyreach summit" else "Complete "..tostring(o.flag)
	end
	return "Unknown task"
end

------------------------------------------------------------------------------
-- Sea creatures (Sea Creatures team). Rolled on a successful Fishing gather
-- with Sea Creature Chance (stats + best rod + rod enchants, capped at 100%).
-- Defined in Data.SeaCreatures and reachable as Data.Monsters[id] through an
-- __index fallback, so lookups (combat, bestiary, quests) see them while
-- pairs(Data.Monsters) still lists only marker monsters with spawn markers.
------------------------------------------------------------------------------
Data.SeaCreatureCap = 3          -- live sea creatures per player
Data.SeaCreatureLifetime = 90    -- seconds before an unfought creature submerges
item("BrineShell",{name="Brine Shell",kind="material",rarity="Common",color="E8D5B7",value=6,description="A ridged shell shed by sea creatures."})
item("GlowJelly",{name="Glow Jelly",kind="material",rarity="Uncommon",color="C3A6FF",value=14,description="Softly luminous jelly from drifting bells."})
item("SeaScale",{name="Sea Scale",kind="material",rarity="Uncommon",color="5FA8A0",value=18,description="A slick scale from skylake eels and rays."})
item("AbyssInk",{name="Abyss Ink",kind="material",rarity="Rare",color="2B2D42",value=40,description="Ink so dark it drinks the lantern light."})
item("ShoalPearl",{name="Shoal Pearl",kind="material",rarity="Rare",color="F4F1DE",value=60,description="A pearl grown inside a coralback's shell."})
item("StormScale",{name="Stormscale",kind="material",rarity="Epic",color="7B8CDE",value=120,description="A crackling scale from a Stormcoil Serpent."})
item("TidewyrmFang",{name="Tidewyrm Fang",kind="material",rarity="Legendary",color="BFF7E6",value=400,description="The fang of a Tidewyrm Matriarch."})
-- Rare accessories: one drop-only, one crafted from sea materials.
item("TidecallerPearl",{name="Tidecaller Pearl",kind="accessory",rarity="Legendary",color=Data.Rarity.Legendary.color,stats={seaCreatureChance=2,fishingFortune=20,health=20},value=40*Data.Rarity.Legendary.rank^2,description="Accessory. Magical Power "..Data.Rarity.Legendary.power..". Drops from deep sea creatures."})
item("BrineCharm",{name="Brine Charm",kind="accessory",rarity="Uncommon",color=Data.Rarity.Uncommon.color,stats={seaCreatureChance=1,fishingFortune=5},value=40*Data.Rarity.Uncommon.rank^2,description="Accessory. Magical Power "..Data.Rarity.Uncommon.power.."."})
recipe("BrineCharm",{skill="Carpentry",level=1,xp=40*Data.Rarity.Uncommon.rank,costs={BrineShell=48,GlowJelly=8},station="Workbench",category="Accessories"})
-- Rare pet drop.
do
	local pet = {id="Pearlwhisker",name="Pearlwhisker Otter",skill="Fishing",rarity="Epic",color="C9A27E",perLevel={seaCreatureChance=0.08,fishingFortune=0.5,defense=0.2},ability="Tide Sense: +10% Fishing XP"}
	table.insert(Data.Pets, pet)
	Data.PetById[pet.id] = pet
	item(pet.id.."Pet",{name=pet.name.." Pet",kind="pet",pet=pet.id,rarity=pet.rarity,color=pet.color,value=200*Data.Rarity[pet.rarity].rank^2,description="Summon from your pet menu. "..pet.ability})
end
-- fishing = Fishing level to hook it; waters = regions it lives in (nil = any water);
-- xp = Combat XP, fishingXp = Fishing XP; weight = relative roll weight; body = combat model plan.
Data.SeaCreatureOrder = {"ShellsnapCrab","DriftbellJelly","ReedfinEel","MistwingRay","InkveilDrifter","CoralbackBruiser","StormcoilSerpent","DuskfinManta","TidewyrmMatriarch"}
Data.SeaCreatures = {
	ShellsnapCrab={name="Shellsnap Crab",fishing=5,level=6,hp=300,damage=24,defense=10,xp=20,fishingXp=40,coins=8,speed=11,weight=100,body="crab",color="D9774B",
		drops={{item="BrineShell",chance=0.9,min=1,max=3},{item="Fish",chance=0.5,min=1,max=2}}},
	DriftbellJelly={name="Driftbell Jelly",fishing=10,level=11,hp=450,damage=34,defense=5,xp=28,fishingXp=60,coins=10,speed=9,weight=80,body="jelly",color="B39DDB",
		drops={{item="GlowJelly",chance=0.8,min=1,max=2},{item="BrineShell",chance=0.4,min=1,max=2}}},
	ReedfinEel={name="Reedfin Eel",fishing=15,level=17,hp=800,damage=60,defense=20,xp=40,fishingXp=90,coins=14,speed=15,weight=70,body="serpent",color="7FA35A",
		drops={{item="SeaScale",chance=0.7,min=1,max=2},{item="Glassfin",chance=0.5,min=1,max=2}}},
	MistwingRay={name="Mistwing Ray",fishing=22,level=24,hp=1300,damage=85,defense=30,xp=60,fishingXp=140,coins=20,speed=17,weight=55,body="ray",color="8FB8D6",
		drops={{item="SeaScale",chance=0.8,min=1,max=3},{item="GlowJelly",chance=0.3,min=1,max=2},{item="TidewingPet",chance=0.002,min=1,max=1}}},
	InkveilDrifter={name="Inkveil Drifter",fishing=30,level=33,hp=2400,damage=140,defense=50,xp=95,fishingXp=220,coins=30,speed=12,weight=45,body="jelly",color="3D3D6B",waters={"Tidewater","Gloomhollow"},
		drops={{item="AbyssInk",chance=0.7,min=1,max=2},{item="GlowJelly",chance=0.5,min=1,max=3}}},
	CoralbackBruiser={name="Coralback Bruiser",fishing=40,level=44,hp=4200,damage=210,defense=140,xp=150,fishingXp=360,coins=45,speed=10,weight=35,body="crab",color="EF6F6C",waters={"Tidewater"},
		drops={{item="BrineShell",chance=0.9,min=2,max=5},{item="ShoalPearl",chance=0.25,min=1,max=1},{item="PearlwhiskerPet",chance=0.002,min=1,max=1}}},
	StormcoilSerpent={name="Stormcoil Serpent",fishing=50,level=55,hp=7000,damage=300,defense=120,xp=230,fishingXp=520,coins=65,speed=18,weight=25,body="serpent",color="4B6584",
		drops={{item="StormScale",chance=0.35,min=1,max=1},{item="SeaScale",chance=0.8,min=2,max=4},{item="TidecallerPearl",chance=0.004,min=1,max=1}}},
	DuskfinManta={name="Duskfin Manta",fishing=60,level=66,hp=11000,damage=400,defense=160,xp=330,fishingXp=760,coins=85,speed=19,weight=15,body="ray",color="5A3E8C",waters={"Gloomhollow","Tidewater"},
		drops={{item="AbyssInk",chance=0.8,min=2,max=4},{item="ShoalPearl",chance=0.3,min=1,max=2},{item="PearlwhiskerPet",chance=0.003,min=1,max=1}}},
	TidewyrmMatriarch={name="Tidewyrm Matriarch",fishing=75,level=82,hp=24000,damage=650,defense=300,xp=600,fishingXp=1500,coins=160,speed=14,weight=5,body="serpent",color="06D6A0",waters={"Tidewater"},
		drops={{item="TidewyrmFang",chance=0.5,min=1,max=1},{item="StormScale",chance=0.5,min=1,max=2},{item="TidecallerPearl",chance=0.02,min=1,max=1},{item="PearlwhiskerPet",chance=0.01,min=1,max=1}}},
}
for id, sc in pairs(Data.SeaCreatures) do
	sc.id, sc.seaCreature = id, true
	sc.region = sc.waters and sc.waters[1] or nil -- display only; nil = any water
	local kept = {}
	for _, d in ipairs(sc.drops) do if d.chance > 0 and Data.Items[d.item] then table.insert(kept, d) end end
	sc.drops = kept
end
setmetatable(Data.Monsters, {__index = Data.SeaCreatures})
-- Sea Creature Chance in percent from computed stats plus the rod (tools are not in computeStats).
function Data.seaCreatureChance(stats, rodStats, enchantStats)
	local function get(t) return type(t) == "table" and tonumber(t.seaCreatureChance) or 0 end
	local total = get(stats) + get(rodStats) + get(enchantStats)
	if total ~= total then return 0 end
	return math.clamp(total, 0, Data.Stats.seaCreatureChance.cap or 100)
end
-- Creatures a cast can hook: Fishing level gate and water (region id, nil = home waters).
function Data.seaCreaturePool(fishingLevel, region)
	local pool = {}
	for _, id in ipairs(Data.SeaCreatureOrder) do
		local sc = Data.SeaCreatures[id]
		if (tonumber(fishingLevel) or 0) >= sc.fishing and (sc.waters == nil or table.find(sc.waters, region) ~= nil) then table.insert(pool, id) end
	end
	return pool
end
-- One cast: roll() < chance% hooks a creature, then a weighted pick from the pool.
function Data.rollSeaCreature(fishingLevel, region, chance, roll)
	chance = math.clamp(tonumber(chance) or 0, 0, 100)
	if chance <= 0 or roll() * 100 >= chance then return nil end
	local pool, total = Data.seaCreaturePool(fishingLevel, region), 0
	for _, id in ipairs(pool) do total += Data.SeaCreatures[id].weight end
	if total <= 0 then return nil end
	local pick = roll() * total
	for _, id in ipairs(pool) do
		pick -= Data.SeaCreatures[id].weight
		if pick < 0 then return id end
	end
	return pool[#pool]
end
-- End of sea creatures

------------------------------------------------------------------------------
-- Co-op (owned by the Co-op team; append-only section).
-- Shared homestead progression (SkyBlock co-op / OSRS Group Ironman style).
-- coop.server.lua reads these; verify-coop.luau checks them. Homestead XP
-- comes from member contributions: +1 per shared-prompt gather, +1 per unit of
-- net-new satchel deposit (deposit/withdraw cycling earns nothing), and
-- +ConstructionXp per supply spent on shared construction.
------------------------------------------------------------------------------
Data.Coop = {
	MaxMembers = 4,
	RejoinCooldown = 86400, -- after leaving or being removed, before any new crew
	InviteSeconds = 600,
	Resources = {"Timber","Ore","Herb","Fish"},
	TransferMax = 100, -- per deposit / withdrawal request
	LogSize = 8,
	ConstructionXp = 2,
	KickReasons = {
		{id="Inactive",text="Inactive for a long time"},
		{id="Stores",text="Misused the shared stores"},
		{id="Conduct",text="Unkind to the crew"},
		{id="Course",text="The crew is changing course"},
	},
	-- storage = per-resource shared supply cap; workers = shared worker slots;
	-- workerTier = highest shared worker tier (Data.WorkerTiers); stats are
	-- written to every member's p.perkStats.coop (Progression.computeStats).
	Levels = {
		{xp=0,storage=250,workers=0,workerTier=0,stats={}},
		{xp=60,storage=400,workers=1,workerTier=2,stats={health=5}},
		{xp=200,storage=600,workers=1,workerTier=3,stats={health=10,defense=3}},
		{xp=450,storage=800,workers=2,workerTier=4,stats={health=15,defense=5,magicFind=1}},
		{xp=900,storage=1000,workers=2,workerTier=5,stats={health=20,defense=8,magicFind=2}},
		{xp=1600,storage=1500,workers=2,workerTier=6,stats={health=30,defense=10,magicFind=3}},
	},
	WorkerUpgradeCost = {Timber=8,Ore=5}, -- x current tier, from shared supplies
}
function Data.coopLevel(xp)
	local levels = Data.Coop.Levels
	local n = 1
	for i, def in ipairs(levels) do if (tonumber(xp) or 0) >= def.xp then n = i end end
	return n, levels[n]
end
-- End Co-op section.

------------------------------------------------------------------------------
-- Events: the Skyward Calendar and its recurring festivals (Events team).
-- Pure and deterministic: every server and client derives the same date from
-- os.time() (seconds since the Unix epoch, always UTC, so DST never applies).
--   1 isle day  = 9,150 s (2 h 32.5 min);  1 season = 12 days (~30.5 h)
--   1 isle year = 4 seasons x 12 days = 48 days = 439,200 s (~5.08 real days)
-- The year is deliberately not a whole number of real days: each year begins
-- ~2 h later on the wall clock, so every event visits every time zone.
-- festival.server.lua publishes the date as workspace attributes (AetherYear,
-- AetherSeason, AetherDay, AetherEvent, AetherEventEnds, AetherEventKey); server hooks only
-- honour an attribute that matches this calendar (Data.eventState).
------------------------------------------------------------------------------
Data.Calendar = {
	epoch = 1577836800, -- 2020-01-01 00:00:00 UTC: dawn of Year 1, Bloomtide 1
	dayLength = 9150,
	daysPerSeason = 12,
	seasonChance = 0.2, -- ambient season bonus: 20% chance of +1 for the season's skill
	seasons = {
		{id="Bloomtide",name="Bloomtide",skill="Farming",color="9BD77E",text="Spring growth: crop harvests have a 20% chance of +1."},
		{id="Sunreach",name="Sunreach",skill="Fishing",color="FFD166",text="Long bright days: catches have a 20% chance of +1 fish."},
		{id="Emberfall",name="Emberfall",skill="Woodcutting",color="E07A3F",text="Dry autumn wood: logs have a 20% chance of +1."},
		{id="Frostveil",name="Frostveil",skill="Mining",color="A8D8F0",text="Frost-split seams: ore has a 20% chance of +1."},
	},
}
Data.Calendar.daysPerYear = #Data.Calendar.seasons * Data.Calendar.daysPerSeason
Data.Calendar.yearLength = Data.Calendar.daysPerYear * Data.Calendar.dayLength
Data.SeasonById = {}
for index, season in ipairs(Data.Calendar.seasons) do season.index = index; Data.SeasonById[season.id] = season end

-- Event-only items (icons come from existing kinds via Catalog.iconShape).
item("SunscaleCarp",{name="Sunscale Carp",kind="resource",skill="Fishing",tier=3,rarity="Rare",color="F4B860",value=30,description="Festival-only catch: bites only during the Glimmertide Festival. Traded at the Festival Vendor."})
item("GloamCandyOrb",{name="Gloamdrop Candy",kind="material",rarity="Uncommon",color="C77DFF",value=6,description="Hollow Night candy dropped by island creatures. Event currency for the Festival Vendor."})
item("StarfallShard",{name="Starfall Shard",kind="material",rarity="Rare",color="BFE3FF",value=20,description="A cold sliver of the Starfall Vigil gift. Event currency for the Festival Vendor."})
item("StarfallCocoa",{name="Starfall Cocoa",kind="consumable",category="buff",rarity="Uncommon",color="A0694B",buff={stats={speed=20,intelligence=40,health=40},duration=900},value=40,description="+20 Speed, +40 Intelligence, +40 Health for 15 minutes."})
local eventAccessories = {
	{id="TidebloomCharm",name="Tidebloom Charm",rarity="Uncommon",stats={fishingFortune=15,seaCreatureChance=2},text="Glimmertide keepsake."},
	{id="GloamlightLantern",name="Gloamlight Lantern",rarity="Rare",stats={strength=8,magicFind=3},text="Hollow Night keepsake."},
	{id="FrostveilLocket",name="Frostveil Locket",rarity="Epic",stats={health=40,defense=15,intelligence=15},text="Starfall Vigil keepsake."},
}
for _, a in ipairs(eventAccessories) do
	item(a.id,{name=a.name,kind="accessory",rarity=a.rarity,color=Data.Rarity[a.rarity].color,stats=a.stats,value=40*Data.Rarity[a.rarity].rank^2,
		event=true,description=a.text.." Accessory. Magical Power "..Data.Rarity[a.rarity].power.."."})
end

-- Recurring events: `days` are days of `season`; each window opens `at` seconds
-- after that isle day's dawn and lasts `duration` seconds (all fit inside a day).
Data.EventOrder = {"BloomtideFair","GlimmertideFestival","DeepveinSurge","HollowNight","StarfallVigil"}
Data.Events = {
	BloomtideFair={name="Bloomtide Fair",season="Bloomtide",days={4,10},at=1800,duration=3600,color="9BD77E",skill="Farming",gatherBonus=1,featuredMult=2,
		text="Every crop harvest +1. The Island Assembly ballot picks a featured crop that yields double."},
	GlimmertideFestival={name="Glimmertide Festival",season="Sunreach",days={3,7,11},at=600,duration=2400,color="FFD166",skill="Fishing",gatherBonus=1,
		drop={item="SunscaleCarp",chance=0.25},text="Every catch +1 fish, and a 25% chance of a festival-only Sunscale Carp."},
	DeepveinSurge={name="Deepvein Surge",season="Emberfall",days={2,8},at=3000,duration=1800,color="D4A84B",skill="Mining",xpMult=2,
		text="Double Mining XP on every ore vein."},
	HollowNight={name="Hollow Night",season="Emberfall",days={5,12},at=5400,duration=2700,color="C77DFF",
		candy={item="GloamCandyOrb",chance=0.5,per=25},text="Every creature has a 50% chance to drop Gloamdrop Candy (more from stronger foes)."},
	StarfallVigil={name="Starfall Vigil",season="Frostveil",days={2,5,8,11},at=4200,duration=3600,color="BFE3FF",
		gift={StarfallShard=3,StarfallCocoa=1},text="Claim one Starfall gift per vigil from the Calendar."},
}
-- Festival Vendor stock (hub prompt). `unique` rewards cannot be bought while owned.
Data.EventVendor = {
	{id="TidebloomCharm",reward={TidebloomCharm=1},costs={SunscaleCarp=16},unique=true},
	{id="ArcaneDustBundle",reward={ArcaneDust=12},costs={GloamCandyOrb=8}},
	{id="GloamlightLantern",reward={GloamlightLantern=1},costs={GloamCandyOrb=40},unique=true},
	{id="StarfallCocoa",reward={StarfallCocoa=1},costs={StarfallShard=2}},
	{id="StarFragment",reward={StarFragment=1},costs={StarfallShard=8,SunscaleCarp=8}},
	{id="FrostveilLocket",reward={FrostveilLocket=1},costs={StarfallShard=10,GloamCandyOrb=30},unique=true},
}
Data.EventVendorById = {}
for _, offer in ipairs(Data.EventVendor) do Data.EventVendorById[offer.id] = offer end
Data.EVENT_VENDOR_SECONDS = 300 -- trading stays open this long after visiting the vendor

-- Every event window of the isle year starting at yearStart, sorted by start.
-- key = "<eventId>:<start>" names one occurrence (claims are per occurrence).
function Data.eventWindows(yearStart)
	local cal, list = Data.Calendar, {}
	for _, id in ipairs(Data.EventOrder) do
		local ev = Data.Events[id]
		local season = Data.SeasonById[ev.season]
		for _, d in ipairs(ev.days) do
			local starts = yearStart + ((season.index - 1) * cal.daysPerSeason + d - 1) * cal.dayLength + ev.at
			table.insert(list, {id=id, starts=starts, ends=starts+ev.duration, key=id..":"..starts})
		end
	end
	table.sort(list, function(a, b) return a.starts < b.starts end)
	return list
end
-- Date for a UTC timestamp. Floor division keeps dates before the epoch valid.
function Data.calendarAt(t)
	local cal = Data.Calendar
	t = math.floor(tonumber(t) or 0)
	local yearIndex = (t - cal.epoch) // cal.yearLength
	local yearStart = cal.epoch + yearIndex * cal.yearLength
	local dayIndex = (t - yearStart) // cal.dayLength
	local seasonIndex = dayIndex // cal.daysPerSeason + 1
	local season = cal.seasons[seasonIndex]
	local dayStart = yearStart + dayIndex * cal.dayLength
	local out = {year=yearIndex+1, yearStart=yearStart, yearEnds=yearStart+cal.yearLength, dayOfYear=dayIndex+1,
		season=season.id, seasonName=season.name, seasonIndex=seasonIndex, day=dayIndex%cal.daysPerSeason+1,
		dayStart=dayStart, dayEnds=dayStart+cal.dayLength, seasonEnds=yearStart+seasonIndex*cal.daysPerSeason*cal.dayLength}
	for _, w in ipairs(Data.eventWindows(yearStart)) do
		if w.starts <= t and t < w.ends then out.event, out.eventStarts, out.eventEnds, out.eventKey = w.id, w.starts, w.ends, w.key end
	end
	return out
end
-- The next `n` windows that have not ended at t (the current one first), across years.
function Data.upcomingEvents(t, n)
	n = n or 3
	local out = {}
	local yearStart = Data.calendarAt(t).yearStart
	while #out < n do
		for _, w in ipairs(Data.eventWindows(yearStart)) do
			if w.ends > t and #out < n then table.insert(out, w) end
		end
		yearStart += Data.Calendar.yearLength
	end
	return out
end
-- Server-side event state from the published attributes (`source` has
-- GetAttribute, e.g. workspace). An attribute only counts while it matches the
-- calendar at `now`, so stale or missing publications grant nothing.
function Data.eventState(source, now)
	local function get(key)
		local ok, value = pcall(function() return source:GetAttribute(key) end)
		return if ok then value else nil
	end
	local cal = Data.calendarAt(now)
	local state = {featured=get("FestivalResource")}
	if get("AetherSeason") == cal.season then state.season = cal.season end
	-- The occurrence key is a string, so the match is exact whatever the number precision.
	if cal.event and get("AetherEvent") == cal.event and get("AetherEventKey") == cal.eventKey then
		state.event, state.ends, state.key = cal.event, cal.eventEnds, cal.eventKey
	end
	return state
end
-- Gathering effects for one harvest: bonus joins the harvest base (before
-- fortune); mult and xpMult apply once to the final result; extra = bonus items.
function Data.eventGather(item, state, roll)
	local out = {bonus=0, mult=1, xpMult=1, extra={}}
	local skill = Data.ResourceSkill[item]
	if not skill or type(state) ~= "table" then return out end
	local season = Data.SeasonById[state.season]
	if season and season.skill == skill and roll() < Data.Calendar.seasonChance then out.bonus += 1 end
	local ev = Data.Events[state.event]
	if ev and ev.skill == skill then
		out.bonus += ev.gatherBonus or 0
		out.xpMult = ev.xpMult or 1
		if ev.featuredMult and state.featured == item then out.mult = ev.featuredMult end
		if ev.drop and roll() < ev.drop.chance then out.extra[ev.drop.item] = 1 end
	end
	return out
end
-- Event-only creature drops (Hollow Night candy) for one kill.
function Data.eventKillDrops(monsterId, state, roll)
	local monster = Data.Monsters[monsterId]
	local ev = type(state) == "table" and Data.Events[state.event]
	if not monster or not ev or not ev.candy then return {} end
	if roll() >= ev.candy.chance then return {} end
	return {[ev.candy.item] = 1 + monster.level // ev.candy.per}
end
-- Starfall gift claims and Festival Vendor trades. Mutates the profile `p`
-- (p.items, p.eventClaims) and grants through grant(p, itemId, count).
-- Claims are keyed per occurrence and pruned once that occurrence has ended.
function Data.eventAction(p, verb, arg, state, now, grant, atVendor)
	local claims = if type(p.eventClaims) == "table" then p.eventClaims else {}
	p.eventClaims = claims
	for key, ends in pairs(claims) do
		if type(ends) ~= "number" or ends <= now then claims[key] = nil end
	end
	local function names(map)
		local parts = {}
		for id, n in pairs(map) do table.insert(parts, n.." "..(Data.Items[id] and Data.Items[id].name or id)) end
		table.sort(parts)
		return table.concat(parts, ", ")
	end
	if verb == "eventGift" then
		local ev = type(state) == "table" and Data.Events[state.event]
		if not ev or not ev.gift or not state.key or now >= (state.ends or 0) then return "No Starfall gift is waiting. Check the Calendar for the next Starfall Vigil." end
		if claims[state.key] then return "You already opened this vigil's Starfall gift." end
		claims[state.key] = state.ends
		for id, n in pairs(ev.gift) do grant(p, id, n) end
		return "Starfall gift opened • +"..names(ev.gift)
	elseif verb == "eventTrade" then
		local offer = type(arg) == "string" and Data.EventVendorById[arg]
		if not offer then return "The Festival Vendor does not stock that." end
		if not atVendor then return "Visit the Festival Vendor on the hub to trade." end
		if offer.unique then
			for id in pairs(offer.reward) do
				if (p.items[id] or 0) > 0 then return "You already own a "..Data.Items[id].name.."." end
			end
		end
		for id, n in pairs(offer.costs) do
			if (p.items[id] or 0) < n then return "You need "..names(offer.costs).."." end
		end
		for id, n in pairs(offer.costs) do p.items[id] -= n end
		for id, n in pairs(offer.reward) do grant(p, id, n) end
		return "Traded "..names(offer.costs).." for "..names(offer.reward).."."
	end
	return "Unknown festival action."
end
-- Events end


------------------------------------------------------------------------------
-- Island placement (Island Builder team; append-only section).
-- Free-form decor on the player's own home island, beside the terrace hotspots.
-- Grid: CELL-stud cells addressed by integer (x, z) in [-RANGE, RANGE]; cell
-- (x, z) is the square centred CELL*x, CELL*z studs from the home island centre.
-- A prop of footprint w x d cells anchored at (x, z) covers x..x+w'-1 and
-- z..z+d'-1 (w', d' swapped when rot is 1 or 3). A cell is buildable when every
-- corner lies within RADIUS studs of the centre and it does not overlap a
-- Protected rectangle (stud offsets: spawn landing, worker stations, signs,
-- legacy decorations, bridges and the terrace approach) by more than BRUSH.
-- Record "id:propId:x:z:rot" (id = smallest free integer 1..MAX_PLACEMENTS);
-- the profile keeps p.island = {placed={record...}, paid={[propId]=n}} and the
-- server replicates the records joined by ";" as player attribute IslandPlacements.
-- Pickup refunds REFUND (100%) of materials; Carpentry XP is paid once per copy
-- (paid[propId] is a high-water mark, never above prop.max), so moving decor
-- around is free and cannot farm XP.
-- effect: light={color,range} (lamp glow), station=kind (home crafting prompt).
------------------------------------------------------------------------------
do
	local Island = {}
	Data.Island = Island
	Island.CELL = 2
	-- Home islands (§27, Data.Home below): the grid grows with the Homestead
	-- level. RANGE / MAX_PLACEMENTS are the absolute bounds (largest stage);
	-- Island.radius(stage) / Island.cap(stage) are what a player may use now.
	-- The legacy core (RADIUS 18.5, RANGE 8) keeps its cell coordinates, so
	-- old saves migrate at offset (0, 0) (Island.migrate).
	Island.RANGE = 74             -- cells; Data.Home.Stages[5].radius 148 / CELL
	Island.RADIUS = 90            -- stage-0 build radius (was 18.5)
	Island.LEGACY_RADIUS = 18.5
	Island.LEGACY_RANGE = 8
	Island.BRUSH = 0.3       -- a cell may brush a protected rectangle by this many studs
	Island.MAX_PLACEMENTS = 200   -- absolute cap (record ids 1..200); Island.cap(stage) = BASE_CAP + CAP_STEP * stage = 120 + 20 * stage
	Island.BASE_CAP = 120
	Island.CAP_STEP = 20
	-- Part budget (§27 performance): the placements of one home may build at
	-- most PART_BUDGET primitive parts (prop.parts each, asserted against the
	-- world builders by verify-home). Checked by the place verb and by
	-- Island.migrate (records past the budget are refunded in full, never deleted).
	Island.PART_BUDGET = 600
	Island.RATE = 3          -- placement verbs per second (token bucket)
	Island.BURST = 6
	Island.REFUND = 1
	Island.Categories = {"Fences","Paths","Lights","Garden","Banners","Statues","Structures","Utility"}
	Island.Protected = {
		{name="home landing",x1=-2.5,z1=2.5,x2=2.5,z2=7.5},
		{name="windpine",x1=-8,z1=-2,x2=-4,z2=2},
		{name="Wayfarer's sign",x1=1.5,z1=-5.5,x2=10.5,z2=-4.5},
		{name="quay beacon",x1=-3,z1=-12,x2=3,z2=-10},
		{name="worker station",x1=6.7,z1=1.7,x2=11.3,z2=6.3},
		{name="worker station",x1=10.7,z1=-3.3,x2=15.3,z2=1.3},
		{name="worker station",x1=-12.3,z1=-12.3,x2=-7.7,z2=-7.7},
		{name="worker cache",x1=9.7,z1=7.9,x2=12.3,z2=10.1},
		{name="lamp",x1=-5.7,z1=-9.7,x2=-4.3,z2=-8.3},
		{name="homestead plans",x1=-8.5,z1=10,x2=-1.5,z2=12.5},
		{name="homestead sign",x1=-12,z1=13.5,x2=0,z2=14.5},
		{name="lantern spot",x1=-13,z1=-9,x2=-11,z2=-7},
		{name="lantern spot",x1=11,z1=-8,x2=13,z2=-6},
		{name="lantern spot",x1=-14,z1=5,x2=-12,z2=7},
		{name="lantern spot",x1=5,z1=11,x2=7,z2=13},
		{name="garden plot",x1=-14,z1=-2.5,x2=-8,z2=4.5},
		{name="lookout bridge",x1=-4,z1=16,x2=4,z2=20},
		{name="terrace bridge",x1=-20,z1=-4,x2=-16,z2=4},
		{name="terrace sign",x1=-38.5,z1=-10,x2=-37.5,z2=-8}, -- §40 QC: beside the terrace walk at the plaza (world: centre + (-38, 0, -9)); a floating §28 sign, no post
		-- Home islands (§27): the add-ons now stand on the big island.
		{name="terrace path",x1=-41.5,z1=-3,x2=-19.5,z2=3},
		{name="lookout path",x1=-3,z1=19.5,x2=3,z2=39.5},
	}
	-- Circular protected zones (x, z centre and r in studs): a cell is blocked
	-- when its square (shrunk by BRUSH) reaches inside the circle.
	Island.ProtectedCircles = {
		{name="worker yard",x=40,z=-38,r=19},          -- yard r12 + its ramp (§40: moved out)
		{name="Builder's Terrace",x=-52,z=0,r=11.5},
		{name="Verdant Garden",x=-40,z=40,r=14.5},
		{name="lookout deck",x=0,z=46,r=7.5},
		{name="survey stake",x=10,z=-21,r=2},
	}
	-- Walk capsules (§40 QC M1): the walks from the core out to the moved
	-- add-ons are oriented strips, so they are protected as segment capsules
	-- (ax, az) -> (bx, bz) with half-width hw (path width / 2) in studs. The
	-- endpoints mirror world.server.lua: the garden walk runs from 20 studs out
	-- towards the Verdant Garden to its lawn edge (GARDEN_R 14 - 0.5); the yard
	-- path from HOME_CORE - 1 to the foot of the yard ramp (YARD_R 12 + 5.4 - 0.6).
	-- The terrace and lookout walks are axis-aligned rectangles (Protected).
	Island.ProtectedSegments = {}
	do
		local function walk(name, tx, tz, fromR, toBack, width)
			local len = math.sqrt(tx * tx + tz * tz)
			local ux, uz = tx / len, tz / len
			table.insert(Island.ProtectedSegments, {name=name, ax=ux * fromR, az=uz * fromR,
				bx=tx - ux * toBack, bz=tz - uz * toBack, hw=width / 2})
		end
		walk("garden walk", -40, 40, 20, 13.5, 5)
		walk("worker yard path", 40, -38, 20, 16.8, 5)
	end
	Island.Props = {
		-- Fences
		TimberFence={name="Timber Fence",category="Fences",level=1,xp=12,costs={Timber=4},size={1,1},parts=4,max=40,value=1,color="966B4C",text="A rail of meadow timber."},
		PicketFence={name="Picket Fence",category="Fences",level=8,xp=24,costs={Timber=6,Ore=2},size={1,1},parts=6,max=40,value=2,color="F9EDCD",text="Painted pickets with copper nails."},
		BrassRailing={name="Brass Railing",category="Fences",level=25,xp=70,costs={WindpineLog=3,BrassIngot=1},size={1,1},parts=6,max=30,value=4,color="DBAD65",text="Polished brass on windpine posts."},
		-- Paths
		StonePath={name="Stone Path",category="Paths",level=1,xp=8,costs={Ore=3},size={1,1},parts=3,max=60,value=1,color="687481",text="Flagstones for a tidy walk."},
		Boardwalk={name="Boardwalk",category="Paths",level=5,xp=12,costs={Timber=4},size={1,1},parts=6,max=60,value=1,color="A0784F",text="Timber planks over the meadow."},
		AetherMosaic={name="Aether Mosaic",category="Paths",level=30,xp=60,costs={Aetherite=6,Ore=4},size={1,1},parts=5,max=40,value=3,color="7FD6E8",text="Glowing inlaid tiles."},
		-- Lights (utility: lamp glow)
		LanternPost={name="Lantern Post",category="Lights",level=3,xp=20,costs={Timber=3,Ore=2},size={1,1},parts=5,max=20,value=3,color="8EE6CB",effect={light={color="8EE6CB",range=9}},text="Lights the island at dusk."},
		BrassStreetlamp={name="Brass Streetlamp",category="Lights",level=20,xp=90,costs={WindpineLog=2,BrassIngot=2},size={1,1},parts=6,max=16,value=6,color="F9CC77",effect={light={color="FFD58A",range=12}},text="A tall lamp with a warm glow."},
		CrystalBrazier={name="Crystal Brazier",category="Lights",level=40,xp=260,costs={Aetherite=12,EmberoakLog=4},size={1,1},parts=6,max=10,value=12,color="C77DFF",effect={light={color="C77DFF",range=14}},text="Aetherite flames in an ember bowl."},
		-- Garden
		FlowerPlanter={name="Flower Planter",category="Garden",level=2,xp=14,costs={Timber=3,Herb=5},size={1,1},parts=6,max=30,value=2,color="D67D6A",text="A box of meadow blooms."},
		HedgeRow={name="Hedge Row",category="Garden",level=10,xp=40,costs={Herb=10,Timber=2},size={2,1},parts=4,max=30,value=3,color="5E8C55",text="A clipped hedge two cells long."},
		YoungWindpine={name="Young Windpine",category="Garden",level=12,xp=50,costs={Timber=8,Herb=6},size={1,1},parts=4,max=15,value=4,color="6B8E5A",text="A sapling for shade (not a gathering node)."},
		MoonbloomBed={name="Moonbloom Bed",category="Garden",level=45,xp=420,costs={Moonbloom=12,GlimmerbarkLog=4},size={2,2},parts=8,max=10,value=15,color="B8C0FF",text="A raised bed of night flowers."},
		-- Banners
		GuildBanner={name="Guild Banner",category="Banners",level=6,xp=20,costs={Timber=4,Herb=2},size={1,1},parts=5,max=20,value=3,color="3C9291",text="The Cartographers' Guild colours."},
		VoyagerPennant={name="Voyager Pennant",category="Banners",level=28,xp=110,costs={WindpineLog=3,BeastHide=4},size={1,1},parts=5,max=12,value=6,color="D67D6A",text="A hide pennant for far voyages."},
		StormStandard={name="Storm Standard",category="Banners",level=55,xp=900,costs={StarwoodLog=4,Stormglass=1},size={1,1},parts=5,max=4,value=30,color="7B8CDE",text="Crackling stormglass on a starwood pole."},
		-- Statues
		SurveyorStatue={name="Surveyor Statue",category="Statues",level=15,xp=120,costs={Ore=30,Brassite=8},size={2,2},parts=6,max=4,value=12,color="B8B2A6",text="A stone surveyor on a plinth."},
		SkywhaleStatue={name="Skywhale Statue",category="Statues",level=50,xp=1100,costs={Aetherite=30,GolemCore=2},size={2,2},parts=8,max=2,value=40,color="7FD6E8",text="A crystal whale breaching the clouds."},
		AetherObelisk={name="Aether Obelisk",category="Statues",level=65,xp=2200,costs={StarmetalIngot=6,Aetherite=40},size={1,1},parts=5,max=3,value=50,color="C9D6E3",effect={light={color="8EE6CB",range=16}},text="A starmetal spire humming with aether."},
		-- Structures
		PicnicBench={name="Picnic Bench",category="Structures",level=4,xp=24,costs={Timber=8},size={2,1},parts=5,max=10,value=3,color="9C6B3E",text="Seats for visiting voyagers."},
		StoneWell={name="Stone Well",category="Structures",level=12,xp=80,costs={Ore=25,Timber=5},size={2,2},parts=9,max=2,value=8,color="6F7A86",text="A covered well with a brass bucket."},
		SupplyShed={name="Supply Shed",category="Structures",level=18,xp=150,costs={Timber=40,Ore=10},size={2,2},parts=6,max=3,value=10,color="8A5A3B",text="A small shed with a pitched roof."},
		GardenGazebo={name="Garden Gazebo",category="Structures",level=22,xp=300,costs={WindpineLog=30,BrassIngot=4},size={3,3},parts=9,max=2,value=25,color="F9EDCD",text="An open pavilion with a brass crown."},
		-- Utility: home crafting prompts reuse the existing station effect.
		CarpenterStump={name="Carpenter's Stump",category="Utility",level=8,xp=40,costs={Timber=20},size={1,1},parts=4,max=1,value=4,color="7A5634",effect={station="Workbench"},text="Home Workbench station."},
		CampStove={name="Camp Stove",category="Utility",level=10,xp=50,costs={Ore=15,Timber=10},size={1,1},parts=5,max=1,value=5,color="B5651D",effect={station="Hearth",light={color="FFB36B",range=8}},text="Home Hearth station."},
		FieldAnvil={name="Field Anvil",category="Utility",level=20,xp=120,costs={Ore=20,BrassIngot=3},size={1,1},parts=5,max=1,value=6,color="485565",effect={station="Forge"},text="Home Forge station."},
		BrewingStand={name="Brewing Stand",category="Utility",level=30,xp=240,costs={Herb=30,EmberoakLog=6},size={1,1},parts=6,max=1,value=8,color="6A4C93",effect={station="Cauldron"},text="Home Cauldron station."},
	}
	Island.PropOrder = {}
	Island.CategoryOf = {}
	for i, c in ipairs(Island.Categories) do Island.CategoryOf[c] = i end
	for id, def in pairs(Island.Props) do def.id = id; table.insert(Island.PropOrder, id) end
	table.sort(Island.PropOrder, function(a, b)
		local pa, pb = Island.Props[a], Island.Props[b]
		if pa.category ~= pb.category then return Island.CategoryOf[pa.category] < Island.CategoryOf[pb.category] end
		if pa.level ~= pb.level then return pa.level < pb.level end
		return a < b
	end)
	-- Island value tiers (shown in the UI; cosmetic).
	Island.ValueTiers = {
		{at=0,name="Bare Rock"},{at=25,name="Homely Camp"},{at=100,name="Charming Cottage"},
		{at=250,name="Grand Estate"},{at=500,name="Legendary Isle"},
	}
	function Island.tier(value)
		local index = 1
		for i, t in ipairs(Island.ValueTiers) do if value >= t.at then index = i end end
		return index, Island.ValueTiers[index]
	end
	local function int(n) return type(n) == "number" and n == n and n == math.floor(n) and math.abs(n) < 1e6 end
	-- Footprint in cells after rotation.
	function Island.footprint(def, rot)
		local w, d = def.size[1], def.size[2]
		if rot % 2 == 1 then return d, w end
		return w, d
	end
	-- Prop centre offset (studs) from the island centre, and its yaw (radians).
	function Island.centerOffset(propId, x, z, rot)
		local w, d = Island.footprint(Island.Props[propId], rot)
		return (x + (w - 1) / 2) * Island.CELL, (z + (d - 1) / 2) * Island.CELL, rot * math.pi / 2
	end
	-- Anchor cell for a prop centred near stud offset (ox, oz) (client snapping).
	function Island.snap(propId, rot, ox, oz)
		local w, d = Island.footprint(Island.Props[propId], rot)
		return math.floor(ox / Island.CELL - (w - 1) / 2 + 0.5), math.floor(oz / Island.CELL - (d - 1) / 2 + 0.5)
	end
	-- Expansion stage (0 .. #Data.Home.Stages - 1) from any value.
	function Island.stage(stage)
		local n = tonumber(stage)
		local top = (Data.Home and #Data.Home.Stages or 1) - 1
		if not n or n ~= n then return 0 end
		return math.clamp(math.floor(n), 0, top)
	end
	function Island.radius(stage)
		if not Data.Home then return Island.RADIUS end
		return Data.Home.Stages[Island.stage(stage) + 1].radius
	end
	function Island.cap(stage) return math.min(Island.MAX_PLACEMENTS, Island.BASE_CAP + Island.CAP_STEP * Island.stage(stage)) end
	-- nil when buildable, else a short reason: "edge" or a protected zone name.
	-- `stage` (default 0) is the owner's expansion stage; `radius` overrides it
	-- (the legacy grid check passes Island.LEGACY_RADIUS).
	-- Squared distance from segment g (ax,az)-(bx,bz) to the axis-aligned
	-- square centred (cx, cz) with half-size e; 0 when they touch.
	local function segmentBoxDist2(g, cx, cz, e)
		local x0, z0, x1, z1 = cx - e, cz - e, cx + e, cz + e
		-- Liang-Barsky: does the segment cross the square?
		local dx, dz = g.bx - g.ax, g.bz - g.az
		local t0, t1 = 0, 1
		local crosses = true
		for _, pq in ipairs({{-dx, g.ax - x0}, {dx, x1 - g.ax}, {-dz, g.az - z0}, {dz, z1 - g.az}}) do
			local p, q = pq[1], pq[2]
			if p == 0 then
				if q < 0 then crosses = false break end
			else
				local t = q / p
				if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
				if t0 > t1 then crosses = false break end
			end
		end
		if crosses then return 0 end
		-- Otherwise the closest pair involves a vertex of one of the two.
		local function ptBox(px, pz)
			local ex = math.max(math.abs(px - cx) - e, 0)
			local ez = math.max(math.abs(pz - cz) - e, 0)
			return ex * ex + ez * ez
		end
		local len2 = dx * dx + dz * dz
		local function ptSeg(px, pz)
			local t = if len2 > 0 then math.clamp(((px - g.ax) * dx + (pz - g.az) * dz) / len2, 0, 1) else 0
			local ex, ez = g.ax + dx * t - px, g.az + dz * t - pz
			return ex * ex + ez * ez
		end
		return math.min(ptBox(g.ax, g.az), ptBox(g.bx, g.bz), ptSeg(x0, z0), ptSeg(x1, z0), ptSeg(x0, z1), ptSeg(x1, z1))
	end
	function Island.cellBlocked(x, z, stage, radius)
		if not int(x) or not int(z) or math.abs(x) > Island.RANGE or math.abs(z) > Island.RANGE then return "edge" end
		local half = Island.CELL / 2
		local cx, cz = x * Island.CELL, z * Island.CELL
		local fx, fz = math.abs(cx) + half, math.abs(cz) + half
		local R = radius or Island.radius(stage)
		if fx * fx + fz * fz > R * R then return "edge" end
		local e = half - Island.BRUSH
		for _, r in ipairs(Island.Protected) do
			if cx + e > r.x1 and cx - e < r.x2 and cz + e > r.z1 and cz - e < r.z2 then return r.name end
		end
		for _, c in ipairs(Island.ProtectedCircles) do
			local dx = math.max(math.abs(c.x - cx) - e, 0)
			local dz = math.max(math.abs(c.z - cz) - e, 0)
			if dx * dx + dz * dz < c.r * c.r then return c.name end
		end
		-- Walk capsules never take a cell of the legacy disc (old saves keep
		-- every legacy-valid cell; the walks start at its rim).
		local legacy = fx * fx + fz * fz <= Island.LEGACY_RADIUS * Island.LEGACY_RADIUS
		for _, g in ipairs(if legacy then {} else Island.ProtectedSegments) do
			if segmentBoxDist2(g, cx, cz, e) < g.hw * g.hw then return g.name end
		end
		return nil
	end
	function Island.key(x, z) return x .. "," .. z end
	-- Cells covered by a placement, or nil for a malformed request.
	function Island.cells(propId, x, z, rot)
		local def = type(propId) == "string" and Island.Props[propId]
		if not def or not int(x) or not int(z) or not int(rot) or rot < 0 or rot > 3 then return nil end
		local w, d = Island.footprint(def, rot)
		local out = {}
		for i = 0, w - 1 do
			for j = 0, d - 1 do table.insert(out, {x + i, z + j}) end
		end
		return out
	end
	-- Records: "id:propId:x:z:rot".
	function Island.parseRecord(text)
		if type(text) ~= "string" or #text > 40 then return nil end
		local id, propId, x, z, rot = string.match(text, "^(%d+):(%w+):(%-?%d+):(%-?%d+):(%d)$")
		id, x, z, rot = tonumber(id), tonumber(x), tonumber(z), tonumber(rot)
		if not id or id < 1 or id > Island.MAX_PLACEMENTS or not Island.Props[propId] or rot > 3 then return nil end
		if math.abs(x) > Island.RANGE or math.abs(z) > Island.RANGE then return nil end
		return {id=id, prop=propId, x=x, z=z, rot=rot}
	end
	function Island.record(e) return e.id .. ":" .. e.prop .. ":" .. e.x .. ":" .. e.z .. ":" .. e.rot end
	-- Payload of the place verb: "propId:x:z:rot" -> propId, x, z, rot (or nil).
	function Island.parseRequest(text)
		if type(text) ~= "string" or #text > 40 then return nil end
		local propId, x, z, rot = string.match(text, "^(%w+):(%-?%d+):(%-?%d+):(%d)$")
		x, z, rot = tonumber(x), tonumber(z), tonumber(rot)
		if not propId or not x or not z or not rot then return nil end
		return propId, x, z, rot
	end
	function Island.encode(list)
		local parts = {}
		for i, e in ipairs(list) do parts[i] = Island.record(e) end
		return table.concat(parts, ";")
	end
	-- Lenient decode: unknown or malformed records are skipped.
	function Island.decode(text)
		local out = {}
		if type(text) ~= "string" then return out end
		for chunk in string.gmatch(text, "[^;]+") do
			if #out >= Island.MAX_PLACEMENTS then break end
			local e = Island.parseRecord(chunk)
			if e then table.insert(out, e) end
		end
		return out
	end
	-- Cell key -> placement id for every listed placement.
	function Island.occupancy(list)
		local occupied = {}
		for _, e in ipairs(list) do
			for _, c in ipairs(Island.cells(e.prop, e.x, e.z, e.rot) or {}) do occupied[Island.key(c[1], c[2])] = e.id end
		end
		return occupied
	end
	-- Geometry check: true, or false + a player-facing reason. `stage` is the
	-- owner's expansion stage (default 0).
	function Island.check(occupied, propId, x, z, rot, stage, radius)
		local def = type(propId) == "string" and Island.Props[propId]
		if not def then return false, "Choose a prop from the island catalogue." end
		local cells = Island.cells(propId, x, z, rot)
		if not cells then return false, "That spot is not on the island grid." end
		for _, c in ipairs(cells) do
			local blocked = Island.cellBlocked(c[1], c[2], stage, radius)
			if blocked == "edge" then return false, def.name .. " must sit fully on your island." end
			if blocked then return false, "Keep the " .. blocked .. " clear." end
			if occupied and occupied[Island.key(c[1], c[2])] then return false, "Something already stands there." end
		end
		return true
	end
	-- Primitive parts the listed placements build (Island.PART_BUDGET caps it).
	function Island.parts(list)
		local total = 0
		for _, e in ipairs(list) do
			local def = Island.Props[e.prop]
			if def then total += def.parts end
		end
		return total
	end
	function Island.value(list)
		local total = 0
		for _, e in ipairs(list) do
			local def = Island.Props[e.prop]
			if def then total += def.value end
		end
		return total
	end
	-- Home islands (§27): nearest anchor where a prop fits, searching square
	-- rings of growing distance around (x, z), saved rotation first.
	function Island.relocate(occupied, propId, x, z, rot, stage)
		local R = Island.RANGE
		if not int(x) or not int(z) or not int(rot) then return nil end
		x, z, rot = math.clamp(x, -R, R), math.clamp(z, -R, R), rot % 4
		local function try(px, pz)
			for k = 0, 3 do
				local r = (rot + k) % 4
				if Island.check(occupied, propId, px, pz, r, stage) then return r end
			end
			return nil
		end
		local r0 = try(x, z)
		if r0 then return x, z, r0 end
		for d = 1, 2 * R do
			for i = -d, d - 1 do
				-- Four sides of the ring, each walked once (corners included once).
				for _, c in ipairs({{x + i, z - d}, {x + d, z + i}, {x - i, z + d}, {x - d, z - i}}) do
					if math.abs(c[1]) <= R and math.abs(c[2]) <= R then
						local r = try(c[1], c[2])
						if r then return c[1], c[2], r end
					end
				end
			end
		end
		return nil
	end
	-- Load-time sanitiser and layout migration (server Isle.migrate). It never
	-- deletes a decoration it can parse: a record that no longer fits (legacy
	-- layout, overlap, protected zone, duplicate id, outside the radius) moves
	-- to the nearest free cell with the smallest free id; only a record that
	-- cannot stand at all (over its per-prop max, over the stage cap, past the
	-- PART_BUDGET in save order, or no free cell) is refunded in full. Saves without v = VERSION are legacy
	-- (pre-§27) and shift by LEGACY_OFFSET first: the legacy core kept its
	-- offsets, so the shift is (0, 0) and every legacy-valid record stays put.
	-- Returns {placed = {record...}, v = VERSION}, refunds {[material] = n},
	-- report {kept, moved, refunded}.
	Island.VERSION = 2
	Island.LEGACY_OFFSET = {x = 0, z = 0}
	function Island.migrate(raw, stage)
		raw = if type(raw) == "table" then raw else {}
		local legacy = raw.v ~= Island.VERSION
		local admitted, counts, refunds = {}, {}, {}
		local report = {kept = 0, moved = 0, refunded = 0}
		local cap = Island.cap(stage)
		local parts = 0
		local function refund(e)
			for material, n in pairs(Island.Props[e.prop].costs) do refunds[material] = (refunds[material] or 0) + n end
			report.refunded += 1
		end
		if type(raw.placed) == "table" then
			local seen = 0
			for _, record in ipairs(raw.placed) do
				seen += 1
				if seen > Island.MAX_PLACEMENTS * 2 then break end -- bounds work on junk saves
				local e = Island.parseRecord(record)
				if e then
					if legacy then e.x += Island.LEGACY_OFFSET.x; e.z += Island.LEGACY_OFFSET.z end
					local def = Island.Props[e.prop]
					if #admitted < cap and (counts[e.prop] or 0) < def.max and parts + def.parts <= Island.PART_BUDGET then
						counts[e.prop] = (counts[e.prop] or 0) + 1
						parts += def.parts
						table.insert(admitted, e)
					else
						refund(e)
					end
				end
			end
		end
		local placed, used, occupied, moving = {}, {}, {}, {}
		local function accept(e)
			used[e.id] = true
			for _, c in ipairs(Island.cells(e.prop, e.x, e.z, e.rot)) do occupied[Island.key(c[1], c[2])] = e.id end
			table.insert(placed, Island.record(e))
		end
		for _, e in ipairs(admitted) do
			if not used[e.id] and Island.check(occupied, e.prop, e.x, e.z, e.rot, stage) then
				accept(e)
				report.kept += 1
			else
				table.insert(moving, e)
			end
		end
		for _, e in ipairs(moving) do
			local x, z, rot = Island.relocate(occupied, e.prop, e.x, e.z, e.rot, stage)
			if x then
				if used[e.id] then
					local id = 1
					while used[id] do id += 1 end
					e.id = id
				end
				e.x, e.z, e.rot = x, z, rot
				accept(e)
				report.moved += 1
			else
				refund(e)
			end
		end
		return {placed = placed, v = Island.VERSION}, refunds, report
	end
end

------------------------------------------------------------------------------
-- Home islands (Home Islands team; §27 in docs/DEPTH-CONTRACT.md).
-- Each player's WayfarersRest_<UserId> is a SkyBlock-style private island: a
-- flat build disc of Stages[level].radius studs (stage 0: r90, about 160 x 160
-- studs) inside a MARGIN-wide natural edge band (cliffs, a beach, a pond,
-- trees and ore rocks the owner gathers), grown by four expansion rings that
-- raise the Homestead level 1 -> 5 (each ring adds ~25-30% area). A ring is a
-- server-validated purchase (verb "homeExpand": Carpentry gate, coins and
-- materials), saved as p.homestead.level and published as the player
-- attribute HomesteadLevel (1..5); world.server.lua resizes the island and
-- moves the edge band out when it changes. The legacy core (r21: spawn,
-- windpine, beacon, worker stations 1-3, plans) and the add-ons (Worker Yard,
-- Builder's Terrace, Verdant Garden, lookout deck) keep their offsets and are
-- protected zones of the placement grid (Data.Island). Homes are laid out by
-- slotCenter on a PITCH grid far from every static island, so the largest
-- island (meadow r158 + skirt) never meets a neighbour.
------------------------------------------------------------------------------
do
	local Home = {}
	Data.Home = Home
	Home.CORE = 21          -- legacy core meadow radius (fixed objects keep their offsets)
	Home.MARGIN = 10        -- natural edge band beyond the build radius
	Home.SKIRT = 6          -- cliff skirt reach beyond the meadow rim
	Home.PART_BUDGET = 250  -- fixed geometry per home (every addition built, every station active)
	Home.LIGHT_BUDGET = 12  -- fixed lights per home (lamps), placements add at most Data.Island glows
	-- Lazy homes (§27 performance): a home's placements and terrace furniture
	-- exist on the server only while a player (owner or visitor) stands within
	-- LIVE_RANGE studs (flat) of its centre; they are torn down LIVE_LINGER
	-- seconds after the last one leaves. Shell, edge band and core always stay.
	Home.LIVE_RANGE = 250
	Home.LIVE_LINGER = 30
	Home.LIVE_TICK = 1      -- seconds between presence checks (world.server.lua)
	Home.Stages = {
		{radius = 90},
		{radius = 102, carpentry = 10, coins = 2500, costs = {Timber = 150, Ore = 100}},
		{radius = 115, carpentry = 25, coins = 10000, costs = {WindpineLog = 80, BrassIngot = 20}},
		{radius = 130, carpentry = 40, coins = 30000, costs = {EmberoakLog = 80, Aetherite = 60}},
		{radius = 148, carpentry = 55, coins = 90000, costs = {StarwoodLog = 60, StarmetalIngot = 15}},
	}
	Home.MAX_LEVEL = #Home.Stages
	-- Grid allocator: COLUMNS homes per row from ORIGIN, PITCH studs apart, far
	-- north of the hub (dungeon arenas sit near z 1700-1800, minigames at x -2400).
	Home.PITCH = 360
	Home.COLUMNS = 8
	Home.ORIGIN = {x = -1260, z = 2400}
	-- Edge band features: angle (radians, x = cos, z = sin) around the rim.
	Home.Edge = {
		{kind = "beach", a = 0.6},
		{kind = "cliff", a = 3.75}, {kind = "cliff", a = 4.05}, {kind = "cliff", a = 4.35},
		{kind = "pond", a = 2.15},
		{kind = "windpine", a = 1.55}, {kind = "windpine", a = 2.75}, {kind = "windpine", a = 5.2},
		{kind = "ore", a = 3.2}, {kind = "ore", a = 4.8}, {kind = "ore", a = 5.75},
		{kind = "pine", a = 1.2}, {kind = "pine", a = 2.45}, {kind = "tree", a = 5.48},
	}
	function Home.level(value)
		local n = tonumber(value)
		if not n or n ~= n then return 1 end
		return math.clamp(math.floor(n), 1, Home.MAX_LEVEL)
	end
	function Home.stage(level) return Home.level(level) - 1 end
	function Home.radius(level) return Home.Stages[Home.level(level)].radius end
	function Home.meadow(level) return Home.radius(level) + Home.MARGIN end
	function Home.area(level) return math.pi * Home.radius(level) ^ 2 end
	-- Footprint radius of the largest island (meadow + cliff skirt).
	function Home.footprint() return Home.meadow(Home.MAX_LEVEL) + Home.SKIRT end
	function Home.slotCenter(slot)
		slot = math.max(1, math.floor(tonumber(slot) or 1))
		local col, row = (slot - 1) % Home.COLUMNS, (slot - 1) // Home.COLUMNS
		return Home.ORIGIN.x + col * Home.PITCH, Home.ORIGIN.z + row * Home.PITCH
	end
	-- Next ring for a level, or nil at the top.
	function Home.nextRing(level) return Home.Stages[Home.level(level) + 1] end
	-- Purchase check: true, ring | false, player-facing reason.
	function Home.canExpand(level, carpentry, coins, items)
		local ring = Home.nextRing(level)
		if not ring then return false, "Your island is fully expanded." end
		if (tonumber(carpentry) or 0) < ring.carpentry then return false, "The next expansion ring requires Carpentry " .. ring.carpentry .. "." end
		if (tonumber(coins) or 0) < ring.coins then return false, "The next expansion ring costs " .. ring.coins .. " coins." end
		for material, n in pairs(ring.costs) do
			if ((items or {})[material] or 0) < n then
				local def = Data.Items and Data.Items[material]
				return false, "The next expansion ring needs " .. n .. " " .. (def and def.name or material) .. "."
			end
		end
		return true, ring
	end
	-- One-line cost text for prompts and the journal.
	function Home.costText(level)
		local ring = Home.nextRing(level)
		if not ring then return "Fully expanded" end
		local parts = {ring.coins .. " coins"}
		local names = {}
		for material in pairs(ring.costs) do table.insert(names, material) end
		table.sort(names)
		for _, material in ipairs(names) do
			local def = Data.Items and Data.Items[material]
			table.insert(parts, ring.costs[material] .. " " .. (def and def.name or material))
		end
		return table.concat(parts, " + ") .. " · Carpentry " .. ring.carpentry
	end
end

------------------------------------------------------------------------------
-- Townsfolk (Guide team; append-only section). NPCs, dialogue graphs, the
-- (retired, see "Polish" in MMO Features: the Wayfarer's Path replaced it)
-- new-player tutorial data, contextual tips and waypoint rules. Consumed by
-- npc.server.lua (ServerScriptService.Townsfolk), npc.client.lua
-- (StarterPlayerScripts.Dialogue) and nav.client.lua (StarterPlayerScripts.Wayfinder).
--
-- Placement (docs/DEPTH-CONTRACT.md §10): an NPC stands on the part named
-- Anchor_NPC_<Role> anywhere under Workspace.Islands; until that anchor exists
-- it stands on a ring around the IslandCenter of the island whose Region
-- attribute matches its region (falling back to the Hub island). Never a
-- hard-coded coordinate.
--
-- Dialogue: npc.start names the first node. A node is {text, options} or
-- {tutorial=true, text, options} (the tutorial checklist is drawn above its
-- options). An option has a label, an optional `when` condition id and exactly
-- one action:
--   to=<node id>             show another node of the same NPC
--   atlas=<station>          open an atlas page (sets IsleStation/IsleStationVisit
--                            like a world station); one of T.AtlasStations
--   waypoint={spec...}|"tutorial"   guide the player there (first spec that
--                            resolves wins); "tutorial" = the current step's targets
--   tip=<kind>               contextual advice from the snapshot (T.Tips)
--   verb=<verb>, item=<str>  call an existing IsleAction verb (T.Verbs)
--   close=true               end the conversation
-- Waypoint specs are "kind:arg" strings, kinds in T.TargetKinds.
------------------------------------------------------------------------------
do
local T = {}
Data.Townsfolk = T
T.RECALL_COOLDOWN = 90        -- seconds between recalls (server enforced)
T.RECALL_HURT_GRACE = 8       -- no recall within this many seconds of taking damage
T.ARRIVE_RADIUS = 12          -- flat studs from the target that count as arrival
T.ARRIVE_HEIGHT = 18          -- ...within this vertical band
T.WAYPOINT_TIMEOUT = 900      -- an untouched waypoint clears itself after 15 minutes
T.LOST_GRACE = 6              -- a target that cannot be resolved for this long is dropped
T.MINIMAP_INTERVAL = 0.1      -- minimap redraw interval (10 Hz)
T.IDLE_RANGE = 90             -- NPC idles animate only within this many studs
T.GRADUATE_CONTRACTS = 3      -- veterans with this many contracts skip the tutorial
-- Atlas pages the field guide (ui.client.lua stationTabs) opens from IsleStation.
T.AtlasStations = {Forge="Workshop · Forge",Hearth="Workshop · Hearth",Cauldron="Workshop · Cauldron",Workbench="Workshop · Workbench",
	Slayer="Hunt · Slayer",Construction="Journal · Construction",Calendar="Journal · Calendar"}
-- Existing IsleAction verbs dialogue may call (item rules per verb).
T.Verbs = {quest={item=false},claim={item=false},slayerStart={item=false},slayerClaim={item=false},sell={item=false},
	recall={item={Hub=true,Home=true}}}
T.RecallTargets = {Hub="Compass Quay",Home="your Wayfarer's Rest"}
T.TargetKinds = {anchor=true,npc=true,region=true,station=true,gather=true,monster=true,warp=true,warpReturn=true,home=true}

------------------------------------------------------------------------------
-- Snapshot helpers (tolerate partial / loading snapshots).
------------------------------------------------------------------------------
local function tab(v) return if type(v) == "table" then v else {} end
local function num(v) return if type(v) == "number" and v == v then v else 0 end
local function count(s, id) return num(tab(tab(s).items)[id]) end
local function collected(s, id) return num(tab(tab(s).collection)[id]) end
local function skillLevel(s, skill)
	local depthSkill = tab(tab(tab(s).depth).skills)[skill]
	if type(depthSkill) == "table" and type(depthSkill.level) == "number" then return depthSkill.level end
	local legacy = tab(tab(s).levels)[skill]
	return if type(legacy) == "number" then legacy else 1
end
local function contracts(s)
	local journal = tab(tab(s).journal)
	if type(journal.contracts) == "number" then return journal.contracts end
	local quest = tab(tab(s).quest)
	if quest.complete then return num(quest.total) end
	return math.max(0, num(quest.stage) - 1)
end
local function itemName(id) local def = Data.Items[id]; return if def then def.name else tostring(id) end
local function anyKills(s)
	if num(tab(s).kills) > 0 then return true end
	for _, n in pairs(tab(tab(tab(s).depth).bestiary)) do if num(n) > 0 then return true end end
	return false
end
local function ownsWeapon(s)
	if tab(tab(tab(s).depth).equipment).weapon then return true end
	for id, n in pairs(tab(tab(s).items)) do
		local def = Data.Items[id]
		if def and def.kind == "weapon" and num(n) > 0 then return true end
	end
	return false
end
T.skillLevel, T.contracts = skillLevel, contracts

------------------------------------------------------------------------------
-- Tutorial: the first ten minutes (gather → craft → equip → fight → bank → contract).
-- Every check reads only the server snapshot, so progress survives rejoins.
-- RETIRED (Polish, T.TUTORIAL_RETIRED): kept as pure data only; nothing offers,
-- tracks or draws it. Onboarding is the Wayfarer's Path (Data.Features.Guide).
------------------------------------------------------------------------------
T.Tutorial = {
	{id="gather",title="Gather supplies",
		text="Mine 6 Copperstone Ore in Brassfall Cay and cut 3 Meadow Timber. Walk up to a node and left-click it to swing your tool.",
		progress=function(s) return math.min(6, collected(s, "Ore")) + math.min(3, collected(s, "Timber")), 9 end,
		waypoint={"gather:Ore","region:Quarry"}},
	{id="craft",title="Forge a Copper Blade",
		text="At a Forge, craft a Copper Blade (4 Ore, 3 Timber). Brannoch the Forgemaster can open the forge for you.",
		progress=function(s) return if ownsWeapon(s) then 1 else 0, 1 end,
		waypoint={"station:Forge","anchor:Waypoint_Forge","npc:Forgemaster"},atlas="Forge"},
	{id="equip",title="Equip your blade",
		text="Open the Atlas → Hero → Gear and equip your new weapon.",
		progress=function(s) return if tab(tab(tab(s).depth).equipment).weapon then 1 else 0, 1 end},
	{id="fight",title="Win your first fight",
		text="Defeat a creature: Brambleback Boars roam Meadow Reach. Tap or click a creature to strike.",
		progress=function(s) return if anyKills(s) then 1 else 0, 1 end,
		waypoint={"monster:BramblebackBoar","monster:Thornling","region:Meadow"}},
	{id="bank",title="Bank your coins",
		text="Coins in your purse are at risk. Deposit some with Odile at the vault (Atlas → Ledger → Bank).",
		progress=function(s) return if num(tab(s).bank) > 0 then 1 else 0, 1 end,
		waypoint={"npc:Banker","anchor:Waypoint_Bank","region:Hub"}},
	{id="contract",title="Claim your first guild contract",
		text="Return to Pell and claim your first guild contract for its reward.",
		progress=function(s) return math.min(1, contracts(s)), 1 end,
		waypoint={"npc:Guide","region:Hub"}},
}
T.TutorialById = {}
for i, step in ipairs(T.Tutorial) do step.index = i; T.TutorialById[step.id] = step end
-- {steps={{id,title,have,need,done}}, current=index|nil, done=n, total=n, complete=bool}
function T.tutorialState(s)
	local out = {steps={}, done=0, total=#T.Tutorial}
	if type(s) ~= "table" or s.loading then out.complete = false; out.loading = true; return out end
	for i, step in ipairs(T.Tutorial) do
		local have, need = step.progress(s)
		local done = have >= need
		out.steps[i] = {id=step.id, title=step.title, have=have, need=need, done=done}
		if done then out.done += 1 elseif not out.current then out.current = i end
	end
	out.graduated = contracts(s) >= T.GRADUATE_CONTRACTS
	out.complete = out.current == nil or out.graduated
	return out
end

------------------------------------------------------------------------------
-- Conditions for `when` (snapshot s, context ctx = {event=id|nil, now=n}).
------------------------------------------------------------------------------
T.Conditions = {
	tutorialActive=function(s) local t = T.tutorialState(s); return not t.loading and not t.complete end,
	tutorialComplete=function(s) return T.tutorialState(s).complete end,
	contractReady=function(s) local q = tab(tab(s).quest); return q.ready == true and not q.complete end,
	workerReady=function(s) return num(tab(s).workerReady) > 0 end,
	huntIdle=function(s) return tab(s).slayer ~= nil and not tab(tab(s).slayer).active end,
	huntReady=function(s) return tab(tab(s).slayer).ready == true end,
	eventActive=function(_, ctx) return type(tab(ctx).event) == "string" and Data.Events[ctx.event] ~= nil end,
	hasBasics=function(s) for _, id in ipairs({"Timber","Ore","Herb","Fish"}) do if count(s, id) > 0 then return true end end return false end,
}
function T.visibleOptions(node, s, ctx)
	local out = {}
	for _, option in ipairs(node.options or {}) do
		local test = option.when and T.Conditions[option.when]
		if not option.when or (test and test(s, ctx)) then table.insert(out, option) end
	end
	return out
end

------------------------------------------------------------------------------
-- Contextual tips: T.Tips[kind](s, ctx) → text (never errors on partial data).
------------------------------------------------------------------------------
local function contractTip(s)
	local q = tab(tab(s).quest)
	if q.complete then return "Every guild contract is signed. Your Journal quests carry the story onward." end
	if not q.title then return "Your contract ledger is still syncing. Ask me again in a moment." end
	local head = "Guild contract " .. num(q.stage) .. "/" .. num(q.total) .. " — " .. q.title .. ": " .. tostring(q.detail or "")
	return if q.ready then head .. " It's ready: claim it with me or in the Journal." else head
end
local function questTip(s)
	local journal = tab(tab(s).journal)
	for i, def in ipairs(Data.Quests) do
		local state = tab(tab(journal.quests)[i])
		if state.available and not state.done then
			local parts = {}
			for j, o in ipairs(def.objectives) do
				local pr = tab(tab(state.objectives)[j])
				local have, need = num(pr[1]), num(pr[2])
				if have < need then
					local what = if o.kind == "kills" then "defeat " .. ((Data.Monsters[o.monster] or {}).name or o.monster)
						elseif o.kind == "collect" or o.kind == "have" then "gather " .. itemName(o.item)
						elseif o.kind == "craft" then "craft " .. itemName(o.item)
						elseif o.kind == "gather" then "harvest in " .. ((Data.RegionById[o.region] or {}).name or o.region)
						elseif o.kind == "level" then "reach " .. o.skill .. " " .. o.level
						else o.kind
					table.insert(parts, what .. " " .. have .. "/" .. need)
				end
			end
			if state.ready then return "\"" .. def.title .. "\" is complete — claim it in Journal → Quests." end
			return "\"" .. def.title .. "\": " .. table.concat(parts, ", ") .. "."
		end
	end
	if contracts(s) < 8 then return "Quests open up as you sign guild contracts. " .. contractTip(s) end
	return "No quest is open right now. Train your skills to meet the next quest's requirements."
end
local function unlockTip(s)
	local options = {}
	for skill, tiers in pairs(Data.ResourceTiers) do
		local lvl = skillLevel(s, skill)
		for _, r in ipairs(tiers) do
			if r.level > lvl then
				table.insert(options, {gap=r.level - lvl, text=skill .. " " .. lvl .. " → " .. r.name .. " at " .. r.level .. (if r.tool > 0 then " (tier " .. r.tool .. " tool)" else "")})
				break
			end
		end
	end
	table.sort(options, function(a, b) if a.gap ~= b.gap then return a.gap < b.gap end return a.text < b.text end)
	local lines = {}
	for i = 1, math.min(3, #options) do table.insert(lines, options[i].text) end
	for _, r in ipairs(tab(tab(tab(s).depth).regions)) do
		if type(r) == "table" and r.unlocked == false then
			table.insert(lines, "Next region: " .. tostring(r.name) .. " — " .. tostring(r.requirement or "keep training"))
			break
		end
	end
	if #lines == 0 then return "You have outgrown every unlock I know of. Impressive." end
	return "Coming up: " .. table.concat(lines, " · ")
end
local function itemsTip(s)
	local lines = {}
	local equipment = tab(tab(tab(s).depth).equipment)
	local equipped = {}
	for _, id in pairs(equipment) do equipped[id] = true end
	local bag = {}
	for _, id in ipairs(tab(tab(tab(s).depth).accessoryBag)) do bag[id] = true end
	local ids = {}
	for id, n in pairs(tab(tab(s).items)) do if num(n) > 0 and Data.Items[id] then table.insert(ids, id) end end
	table.sort(ids)
	local seen = {}
	local function add(key, text) if not seen[key] and #lines < 4 then seen[key] = true; table.insert(lines, text) end end
	for _, id in ipairs(ids) do
		local def = Data.Items[id]
		if (def.kind == "weapon" or def.kind == "armor") and not equipped[id] and def.slot and not equipment[def.slot] then
			add("equip", "Equip your " .. def.name .. " (Atlas → Hero → Gear).")
		elseif def.kind == "pet" then add("pet", "Adopt your " .. def.name .. " (Atlas → Hero → Pets).")
		elseif def.kind == "accessory" and not bag[id] then add("acc", "Slot your " .. def.name .. " into the Accessory Bag.")
		elseif def.kind == "consumable" then add("food", "Keep your " .. def.name .. " for tough fights — use it from the Hero page.")
		end
	end
	local surplus = {}
	for _, id in ipairs({"Ore","Timber","Herb","Fish"}) do if count(s, id) >= 20 then table.insert(surplus, itemName(id)) end end
	if #surplus > 0 then add("sell", "Surplus " .. table.concat(surplus, ", ") .. ": refine it at the Forge, or sell it to Tobin or on the Bazaar.") end
	if #lines == 0 then return "Your satchel is tidy. Gather, craft and fight to fill it." end
	return table.concat(lines, " ")
end
local function bankTip(s)
	local coins, bank = num(tab(s).coins), num(tab(s).bank)
	local text = "Purse: " .. coins .. " coins · Vault: " .. bank .. " coins."
	if coins >= 100 and coins > bank then return text .. " Consider depositing — Atlas → Ledger → Bank." end
	return text .. " The vault keeps savings apart from your spending purse."
end
local function slayerTip(s)
	local quest = tab(tab(tab(tab(s).depth).slayer).quest)
	if quest.line then
		if quest.bossReady then return "Your " .. quest.line .. " boss is ready — it will rise near you. Steel yourself!" end
		return quest.line .. " tier " .. num(quest.tier) .. ": " .. num(quest.progress) .. "/" .. num(quest.needed) .. " slayer XP. Hunt " .. quest.line .. " creatures."
	end
	local hunt = tab(tab(s).slayer)
	if hunt.active then return "Warden hunt: " .. num(hunt.progress) .. "/" .. num(hunt.target) .. " Wardens defeated." end
	local combat = skillLevel(s, "Combat")
	for _, line in ipairs(Data.SlayerOrder) do
		local def = Data.Slayers[line]
		local tier = def and def.tiers and def.tiers[1]
		local need = tier and tier.combatLevel
		if type(need) == "number" and combat >= need then return "You can take a " .. line .. " slayer contract (Hunt → Slayer)." end
	end
	return "At Combat " .. combat .. ", start with a Warden hunt and the meadow beasts. Slayer contracts open with Combat levels."
end
local function eventTip(_, ctx)
	ctx = tab(ctx)
	local def = type(ctx.event) == "string" and Data.Events[ctx.event]
	if def then return def.name .. " is on now! " .. def.text end
	local nextDef = type(ctx.nextEvent) == "string" and Data.Events[ctx.nextEvent]
	if nextDef then return "No festival right now. Next up: " .. nextDef.name .. " — " .. nextDef.text end
	return "The calendar is quiet. Check the Skyward Calendar for the next festival."
end
local function nextTip(s, ctx)
	local t = T.tutorialState(s)
	if t.loading then return "Your journal is still opening. Ask me again in a moment." end
	if not t.complete then
		local step = T.Tutorial[t.current]
		return "Step " .. t.current .. "/" .. t.total .. " — " .. step.title .. ": " .. step.text
	end
	if T.Conditions.contractReady(s) then return contractTip(s) end
	local q = tab(tab(s).quest)
	if not q.complete and q.title then return contractTip(s) end
	return questTip(s)
end
T.Tips = {next=nextTip, contract=contractTip, quest=questTip, unlock=unlockTip, items=itemsTip, bank=bankTip, slayer=slayerTip, event=eventTip}

------------------------------------------------------------------------------
-- Waypoints: "kind:arg" target specs and a pure lifecycle.
------------------------------------------------------------------------------
function T.parseTarget(spec)
	if type(spec) ~= "string" then return nil end
	local kind, arg = string.match(spec, "^(%a+):?([%w_]*)$")
	if not kind or not T.TargetKinds[kind] then return nil end
	if arg == "" and kind ~= "warpReturn" and kind ~= "home" then return nil end
	return kind, arg
end
-- index = {anchors={[name]={pos}}, npcs={[role]=pos}, islands={[region]=pos},
--   station={[id]={pos}}, gather={[id]={pos}}, monster={[id]={pos}}, warp={[region]={pos}},
--   warpReturn={pos}, home=pos}. Lists pick the entry nearest `from`.
local function nearest(list, from)
	if type(list) ~= "table" then return nil end
	if list.X then return list end
	local best, bestD
	for _, p in ipairs(list) do
		local d = if from then (p - from).Magnitude else 0
		if not bestD or d < bestD then best, bestD = p, d end
	end
	return best
end
function T.resolveTarget(spec, index, from)
	local kind, arg = T.parseTarget(spec)
	if not kind or type(index) ~= "table" then return nil end
	if kind == "anchor" then return nearest(tab(index.anchors)["Anchor_" .. arg], from)
	elseif kind == "npc" then return tab(index.npcs)[arg]
	elseif kind == "region" then return tab(index.islands)[arg]
	elseif kind == "warpReturn" then return nearest(index.warpReturn, from)
	elseif kind == "home" then return index.home
	end
	return nearest(tab(index[kind])[arg], from)
end
function T.resolveFirst(specs, index, from)
	for _, spec in ipairs(tab(specs)) do
		local pos = T.resolveTarget(spec, index, from)
		if pos then return pos, spec end
	end
	return nil
end
-- Display name for a target spec ("npc:Banker" → "Odile Marrowcoin").
function T.targetLabel(spec)
	local kind, arg = T.parseTarget(spec)
	if not kind then return "Waypoint" end
	if kind == "npc" then return if T.NPCs[arg] then T.NPCs[arg].name else arg
	elseif kind == "region" then return if Data.RegionById[arg] then Data.RegionById[arg].name else arg
	elseif kind == "station" then return if T.AtlasStations[arg] then arg else arg .. " station"
	elseif kind == "gather" or kind == "monster" then
		local def = if kind == "gather" then Data.Items[arg] else Data.Monsters[arg]
		return if def and def.name then def.name else arg
	elseif kind == "warp" then return "Beacon to " .. (if Data.RegionById[arg] then Data.RegionById[arg].name else arg)
	elseif kind == "warpReturn" then return "Homeward beacon"
	elseif kind == "home" then return "Wayfarer's Rest"
	end
	return (string.gsub(string.gsub(arg, "^Waypoint_", ""), "_", " "))
end
function T.newWaypoint(specs, label, now)
	return {specs=specs, label=label or "Waypoint", started=now, seen=now, status="active"}
end
-- Advances a waypoint: status "active" | "arrived" | "expired" | "lost".
function T.stepWaypoint(wp, playerPos, targetPos, now)
	if wp.status ~= "active" then return wp.status end
	if now - wp.started > T.WAYPOINT_TIMEOUT then wp.status = "expired"; return wp.status end
	if not targetPos then
		if now - wp.seen > T.LOST_GRACE then wp.status = "lost" end
		return wp.status
	end
	wp.seen, wp.target = now, targetPos
	if playerPos then
		local delta = targetPos - playerPos
		wp.distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
		if wp.distance <= T.ARRIVE_RADIUS and math.abs(delta.Y) <= T.ARRIVE_HEIGHT then wp.status = "arrived" end
	end
	return wp.status
end

------------------------------------------------------------------------------
-- Recall (server hook "recall"): cooldown and recent-damage gate.
------------------------------------------------------------------------------
function T.recallCheck(target, now, lastRecall, lastHurt)
	if type(target) ~= "string" or not T.RecallTargets[target] then return false, "Choose Compass Quay (Hub) or Home to recall to." end
	if lastHurt and now - lastHurt < T.RECALL_HURT_GRACE then return false, "You can't recall mid-fight. Catch your breath first." end
	if lastRecall and now - lastRecall < T.RECALL_COOLDOWN then
		return false, "Your recall charm is recharging (" .. math.ceil(T.RECALL_COOLDOWN - (now - lastRecall)) .. "s)."
	end
	return true, "Recalled to " .. T.RecallTargets[target] .. "."
end

------------------------------------------------------------------------------
-- Placement against Workspace.Islands (contract §10).
------------------------------------------------------------------------------
-- folder: Workspace.Islands. Returns {regions={[region]={center,radius,model}}, anchors={[name]={part...}}}.
function T.scanIslands(folder)
	local out = {regions={}, anchors={}, list={}}
	if not folder then return out end
	for _, model in ipairs(folder:GetChildren()) do
		local center, radius = model:GetAttribute("IslandCenter"), model:GetAttribute("IslandRadius")
		local region = model:GetAttribute("Region")
		if typeof(center) == "Vector3" and type(radius) == "number" then
			local entry = {center=center, radius=radius, model=model, region=region}
			table.insert(out.list, entry)
			if type(region) == "string" and not out.regions[region] then out.regions[region] = entry end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 7) == "Anchor_" then
				out.anchors[d.Name] = out.anchors[d.Name] or {}
				table.insert(out.anchors[d.Name], d)
			end
		end
	end
	return out
end
-- Fallback ring slot for an NPC on its island (distinct angle per NPC).
function T.fallbackOffset(slot, slots, radius)
	local angle = (slot - 1) * 2 * math.pi / math.max(1, slots) + 0.35
	local distance = math.clamp(radius * 0.32, 7, 42)
	return math.cos(angle) * distance, math.sin(angle) * distance
end
-- {source="anchor", part=} | {source="fallback", island=entry, x=, z=} | nil (no island yet).
function T.placement(role, scan)
	local def = T.NPCs[role]
	if not def then return nil end
	local anchors = scan.anchors["Anchor_NPC_" .. role]
	if anchors and anchors[1] then return {source="anchor", part=anchors[1]} end
	local island = scan.regions[def.region] or scan.regions.Hub
	if not island then return nil end
	local slot, slots = 0, 0
	for _, other in ipairs(T.Order) do
		local o = T.NPCs[other]
		local home = if scan.regions[o.region] then o.region else "Hub"
		if home == (island.region or "Hub") then
			slots += 1
			if other == role then slot = slots end
		end
	end
	local x, z = T.fallbackOffset(math.max(1, slot), math.max(1, slots), island.radius)
	return {source="fallback", island=island, x=x, z=z}
end

------------------------------------------------------------------------------
-- The townsfolk. look: skin/shirt/pants/shoes/accent/hair hex, hat, held, extras.
------------------------------------------------------------------------------
T.Order = {"Guide","Banker","Merchant","Forgemaster","Slayer","Fisher","Auctioneer","Herald","Registrar","Joiner","Grovekeeper","Deepwarden"}
local farewell = {label="Farewell", close=true}
local function back(to) return {label="Back", to=to or "hello"} end
T.NPCs = {
	Guide={name="Pell Ashgrove",title="Wayfinder of the Skyway",region="Hub",portrait="🧭",
		look={skin="E0AC69",shirt="2F6F6A",pants="33404A",shoes="5A3B26",accent="F9CC77",hair="7A4A2A",hat="wayfarer",held="lantern",cape="9EE7D2",beard=false},
		start="hello",nodes={
			hello={text="Well met, wayfarer! I'm Pell — I chart the Skyway for every new arrival. Where shall we begin?",options={
				{label="Walk me through the basics",to="tutorial",when="tutorialActive"},
				{label="Claim my guild contract",verb="quest",when="contractReady"},
				{label="What should I do next?",tip="next"},
				{label="Where is everything?",to="places"},
				{label="How do I get around?",to="travel"},
				farewell}},
			tutorial={tutorial=true,text="A few steps and you'll be a proper islander. Here's where you stand:",options={
				{label="Show me the way",waypoint="tutorial"},
				{label="Check my progress again",to="tutorial"},
				{label="Claim my guild contract",verb="quest",when="contractReady"},
				back()}},
			places={text="Everyone on the Skyway has a trade. Who are you looking for?",options={
				{label="The Forge",waypoint={"station:Forge","anchor:Waypoint_Forge","npc:Forgemaster"}},
				{label="Odile at the vault",waypoint={"npc:Banker","anchor:Waypoint_Bank"}},
				{label="Tobin the merchant",waypoint={"npc:Merchant"}},
				{label="Captain Ysolde, Slayer Master",waypoint={"npc:Slayer","station:Slayer"}},
				{label="Sabine, the Calendar Herald",waypoint={"npc:Herald"}},
				back()}},
			travel={text="Beacons link the isles — step up and use one. Your map's Navigate list can point the way, and once every 90 seconds I can lend you a recall charm.",options={
				{label="Recall me home",verb="recall",item="Home"},
				{label="Recall me to Compass Quay",verb="recall",item="Hub"},
				{label="Guide me to a homeward beacon",waypoint={"warpReturn","anchor:Waypoint_Homeward","region:Hub"}},
				back()}},
		}},
	Banker={name="Odile Marrowcoin",title="Keeper of the Vault",region="Hub",portrait="🪙",
		look={skin="C68642",shirt="1F2F4F",pants="1A1F2B",shoes="2B2B2B",accent="F9CC77",hair="D9D9D9",hat="tophat",held="ledger",spectacles=true},
		start="hello",nodes={
			hello={text="Coins in a purse are coins at risk, dear. The vault keeps them safe from every mishap on the isles.",options={
				{label="How much do I hold?",tip="bank"},
				{label="Why should I bank?",to="why"},
				farewell}},
			why={text="Your purse pays for crafting and trades. Your vault is savings — open the Atlas, choose Ledger → Bank, and move coins either way whenever you like.",options={
				{label="How much do I hold?",tip="bank"},back()}},
		}},
	Merchant={name="Tobin Saltwhistle",title="Quay Merchant",region="Hub",portrait="📦",
		look={skin="F1C27D",shirt="A0522D",pants="4A3B2A",shoes="3B2A1A",accent="E9C46A",hair="2B1B0E",hat="cap",held="crate",apron="D9C7A0",beard=true},
		start="hello",nodes={
			hello={text="Fresh off the skyships! I'll take timber, ore, herbs and fish off your hands at the quay rate.",options={
				{label="Sell my basic supplies",to="sell",when="hasBasics"},
				{label="What should I do with my items?",tip="items"},
				farewell}},
			sell={text="All your Meadow Timber, Copperstone Ore, Meadow Herb and Skylake Minnows, at the quay rate. Deal?",options={
				{label="Deal — sell them",verb="sell"},
				{label="On second thought…",to="hello"}}},
		}},
	Forgemaster={name="Brannoch Embervein",title="Forgemaster",region="Hub",portrait="⚒",
		look={skin="8D5524",shirt="5C3A21",pants="2E2A26",shoes="1E1A16",accent="E8806A",hair="1B1B1B",hat="goggles",held="hammer",apron="3A2A1E",beard=true},
		start="hello",nodes={
			hello={text="Hah! Another pair of hands. Bring ore and timber and I'll teach you to make something worth swinging.",options={
				{label="Open the forge",atlas="Forge"},
				{label="Show me to a forge",waypoint={"station:Forge","anchor:Waypoint_Forge"}},
				{label="What can I unlock next?",tip="unlock"},
				{label="Other crafting stations",to="stations"},
				farewell}},
			stations={text="The Hearth cooks, the Cauldron brews, the Workbench shapes accessories. Which do you need?",options={
				{label="Open the Hearth",atlas="Hearth"},
				{label="Open the Cauldron",atlas="Cauldron"},
				{label="Open the Workbench",atlas="Workbench"},
				back()}},
		}},
	Slayer={name="Captain Ysolde Thornmantle",title="Slayer Master",region="Hub",portrait="⚔",
		look={skin="E0AC69",shirt="3B2F4A",pants="2A2433",shoes="1B1B22",accent="B23A48",hair="C0392B",hat="helm",held="sword",cape="B23A48"},
		start="hello",nodes={
			hello={text="The wilds don't thin themselves. Take a contract, bring back proof, and you'll be paid in coin and renown.",options={
				{label="Show me slayer contracts",atlas="Slayer"},
				{label="How is my hunt going?",tip="slayer"},
				{label="Begin a Warden hunt",verb="slayerStart",when="huntIdle"},
				{label="Claim my Warden hunt",verb="slayerClaim",when="huntReady"},
				{label="Where should I fight?",waypoint={"monster:BramblebackBoar","monster:Thornling","region:Meadow"}},
				farewell}},
		}},
	Fisher={name="Nell Driftwhistle",title="Harbour Angler",region="Hub",portrait="🎣",
		look={skin="FFDBAC",shirt="E9B949",pants="2F4F6F",shoes="2B3A4A",accent="8FB8D6",hair="B5651D",hat="souwester",held="rod"},
		start="hello",nodes={
			hello={text="Skylake minnows bite best at dawn, but they'll bite any time for a patient hand.",options={
				{label="Where can I fish?",waypoint={"gather:Fish","region:Tidewater"}},
				{label="Cook my catch",atlas="Hearth"},
				{label="Tell me about sea creatures",to="sea"},
				farewell}},
			sea={text="Cast long enough and something big takes the line — sea creatures! Better rods and Sea Creature Chance call them up more often. Fight them where they surface.",options={
				{label="What can I unlock next?",tip="unlock"},back()}},
		}},
	Auctioneer={name="Quill Varrow",title="Quartermaster & Auctioneer",region="Hub",portrait="📜",
		look={skin="D1A27A",shirt="5B3F8C",pants="2A1F3D",shoes="1A1426",accent="C9A227",hair="F2E8D5",hat="tricorn",held="scroll"},
		start="hello",nodes={
			hello={text="Buy low, sell high, and never bid in a hurry. What brings you to my stall?",options={
				{label="How do the Bazaar and Auctions work?",to="market"},
				{label="What should I do with my items?",tip="items"},
				farewell}},
			market={text="The Bazaar trades raw goods by standing orders. The Auction House sells one piece of gear per listing for a 1% fee. Both live in your Atlas → Ledger.",options={
				{label="What should I do with my items?",tip="items"},back()}},
		}},
	Herald={name="Sabine Larkspur",title="Calendar Herald",region="Hub",portrait="📯",
		look={skin="FFDBAC",shirt="C2185B",pants="F2E8D5",shoes="6D4C41",accent="FFD166",hair="F4D03F",hat="feather",held="horn"},
		start="hello",nodes={
			hello={text="Hear ye! The Skyward Calendar turns, and every season brings its festival.",options={
				{label="What's happening now?",tip="event"},
				{label="Open the Skyward Calendar",atlas="Calendar"},
				farewell}},
		}},
	Registrar={name="Hollis Brightknot",title="Crew Registrar",region="Hub",portrait="🤝",
		look={skin="A0522D",shirt="2E7D32",pants="3E2723",shoes="212121",accent="9EE7D2",hair="111111",hat="none",held="ledger",spectacles=true},
		start="hello",nodes={
			hello={text="Crews share a homestead, its workers and its glory. Shall I tell you how it works?",options={
				{label="How do crews work?",to="crews"},
				{label="How are my contracts?",tip="contract"},
				{label="Collect my worker's haul",verb="claim",when="workerReady"},
				farewell}},
			crews={text="Invite friends from the Atlas → Journal → Crew. Contributions raise your Homestead level, unlock shared workers and a crew stat perk for everyone.",options={back()}},
		}},
	Joiner={name="Master Orrin Pegwright",title="Master Joiner",region="Hub",portrait="🪚",
		look={skin="C68642",shirt="8D6E63",pants="4E342E",shoes="3E2723",accent="F9CC77",hair="9E9E9E",hat="cap",held="saw",apron="BCAAA4",beard=true},
		start="hello",nodes={
			hello={text="A homestead is only as good as its joinery. Raise a workbench on your terrace and I'll register it.",options={
				{label="Show me construction plans",atlas="Construction"},
				{label="Open the workbench",atlas="Workbench"},
				{label="Take me home",verb="recall",item="Home"},
				farewell}},
		}},
	Grovekeeper={name="Old Tamsin",title="Grove-keeper of Windpine",region="Windpine",portrait="🌲",
		look={skin="E0AC69",shirt="3E6B3A",pants="4B3A26",shoes="3A2A1A",accent="9BD77E",hair="E0E0E0",hat="hood",held="staff",cape="2F5233"},
		start="hello",nodes={
			hello={text="Hush… the windpines whisper. They tell me you are seeking something.",options={
				{label="What should I do next?",tip="quest"},
				{label="Where are the windpines?",waypoint={"gather:WindpineLog","region:Windpine"}},
				{label="Lead me back to the Skyway",waypoint={"warpReturn","region:Hub"}},
				farewell}},
		}},
	Deepwarden={name="Ferrin Lanternhand",title="Deepwarden of Gloomhollow",region="Gloomhollow",portrait="🏮",
		look={skin="8D5524",shirt="37474F",pants="263238",shoes="1C1C1C",accent="FFD166",hair="3E2723",hat="minerhelm",held="pickaxe",beard=true},
		start="hello",nodes={
			hello={text="Keep your lantern lit down here. The Gloomfangs hate the light — and they hate visitors more.",options={
				{label="Where's the voidstone?",waypoint={"gather:Voidstone","region:Gloomhollow"}},
				{label="How is my hunt going?",tip="slayer"},
				{label="What can I unlock next?",tip="unlock"},
				{label="Lead me back to the Skyway",waypoint={"warpReturn","region:Hub"}},
				farewell}},
		}},
}
end
-- End Townsfolk section.

------------------------------------------------------------------------------
-- Combat styles (Combat Styles team; append-only section).
-- The combat triangle (OSRS melee / ranged / magic) with SkyBlock-style mana:
--   * One weapon slot; the style comes from the weapon (def.style, default
--     "melee"). Bows carry def.ranged = {power, speed, range, maxAmmoTier};
--     staves and wands carry def.magic = {power, speed, elements}.
--   * Arrows sit in the new "ammo" equipment slot (shown as the Quiver); every
--     shot consumes one. Spells cost glyphs (items) and mana (Intelligence).
--   * Monsters carry attackStyle, weakness and defenceStyle: +30% damage from
--     their weakness, -30% from the style they resist (Data.CombatStyles).
-- Skills: Ranged and Magic (trained by damage dealt), Fletching (bows, shafts,
-- arrows) and Glyphcraft (glyphs, staves, tablets).
-- Formulas live in shared/Progression.lua (rangedDamage, hitChance,
-- spellDamage, styleModifier, maxMana, manaRegen, styleXp, glyphCost).
------------------------------------------------------------------------------
do
local CS = {
	order = {"melee","ranged","magic"},
	names = {melee="Melee",ranged="Ranged",magic="Magic"},
	skill = {melee="Combat",ranged="Ranged",magic="Magic"},
	-- Triangle: each style beats the next. A monster of style S is weak to the
	-- style that beats S and resists the style S beats.
	beats = {melee="ranged",ranged="magic",magic="melee"},
	beatenBy = {ranged="melee",magic="ranged",melee="magic"},
	weaknessBonus = 0.3, resistPenalty = 0.3,
	maxRange = 40,              -- studs, ranged and magic (player root to monster surface)
	damageXpRate = 1,           -- style XP per point of damage = rate * monster xp / monster hp
	combatShare = 1/3,          -- ranged/magic damage XP also feeds Combat (Hitpoints-like share)
	bossXpShare = 0.5,          -- slayer bosses: rate uses tier.spawnXp * share / tier.hp
	manaRegenPercent = 4,       -- % of max mana per second (before Ability Damage etc.; flat)
	combatLock = 5,             -- seconds after being struck before Hubward works
	accuracyParity = 0.85,      -- ranged hit chance when attack and defence rolls match
	hitFloor = 0.25, hitCeiling = 0.98,
	ammoSlot = "ammo",
	slotNames = {ammo="Quiver"},
	elements = {
		Gale={name="Gale",color="C9F2FF",glyph="GaleGlyph"},
		Tide={name="Tide",color="3F7CAC",glyph="TideGlyph"},
		Stone={name="Stone",color="8C7A6B",glyph="StoneGlyph"},
		Ember={name="Ember",color="FF7A3D",glyph="EmberGlyph"},
	},
	elementOrder = {"Gale","Tide","Stone","Ember"},
}
Data.CombatStyles = CS
table.insert(Data.EquipSlots, "ammo")

-- New skills (registered in SkillOrder so snapshots, totals and saves include them).
for _, id in ipairs({"Ranged","Magic","Fletching","Glyphcraft"}) do table.insert(Data.SkillOrder, id) end
Data.Skills.Ranged = {category="combat",color="6FA35A",title="Marksman",perLevel={rangedStrength=1,rangedAccuracy=1},description="Loose arrows from bows. Raises Ranged Strength and Ranged Accuracy."}
Data.Skills.Magic = {category="combat",color="5C7AEA",title="Spellwright",perLevel={intelligence=2,abilityDamage=0.2},description="Cast glyph spells with staves and wands. Raises Intelligence and Ability Damage."}
Data.Skills.Fletching = {category="production",color="A7B66B",title="Bowyer",perLevel={rangedStrength=0.5},description="Fletch bows, shafts and arrows. Raises Ranged Strength."}
Data.Skills.Glyphcraft = {category="production",color="9A7FD1",title="Glyphwright",perLevel={intelligence=1},description="Inscribe glyphs, staves and tablets. Raises Intelligence."}

-- New stats.
Data.Stats.rangedStrength = {name="Ranged Strength",symbol="➶",color="6FA35A",base=0}
Data.Stats.rangedAccuracy = {name="Ranged Accuracy",symbol="◎",color="6FA35A",base=0}
Data.Stats.abilityDamage = {name="Ability Damage",symbol="๑",color="FF5555",base=0,percent=true}
for _, id in ipairs({"rangedStrength","rangedAccuracy","abilityDamage"}) do table.insert(Data.StatOrder, id) end

local function rarityFor(tier)
	return if tier >= 7 then "Legendary" elseif tier >= 5 then "Epic" elseif tier >= 4 then "Rare" elseif tier >= 2 then "Uncommon" else "Common"
end

-- Fletching materials. combatUse marks items the combat bridge may consume.
item("DriftPlume",{name="Drift Plume",kind="material",rarity="Common",color="E9F1F7",value=1,description="A light vane for arrows. Dropped by sky creatures or fletched from leaves."})
item("ArrowShaft",{name="Arrow Shaft",kind="material",rarity="Common",color="C49A6C",value=1,description="Fletched from logs. Fifteen shafts per Meadow Timber."})
item("Bowstring",{name="Sinew Bowstring",kind="material",rarity="Common",color="D8C3A5",value=6,description="Strings the first three bow tiers."})
item("SilkString",{name="Gloomsilk Bowstring",kind="material",rarity="Rare",color="D8D8E8",value=30,description="Strings Glimmerbark, Starwood and Aetherheart bows."})
recipe("DriftPlume",{skill="Fletching",level=1,xp=4,costs={Herb=2},amount=6,repeatable=true,station="Workbench",category="Fletching"})
recipe("ArrowShaft",{skill="Fletching",level=1,xp=5,costs={Timber=1},amount=15,repeatable=true,station="Workbench",category="Fletching"})
recipe("WindpineShafts",{output="ArrowShaft",skill="Fletching",level=15,xp=12,costs={WindpineLog=1},amount=30,repeatable=true,station="Workbench",category="Fletching"})
recipe("Bowstring",{skill="Fletching",level=1,xp=8,costs={BeastHide=1},amount=2,repeatable=true,station="Workbench",category="Fletching"})
recipe("SilkString",{skill="Fletching",level=40,xp=40,costs={SpiderSilk=2},amount=3,repeatable=true,collectionTier={SpiderSilk=1},station="Workbench",category="Fletching"})
for id, d in pairs({Thornling={0.5,1,3},GaleSprite={0.6,2,5},StormHarrier={0.8,3,6},MistwingRay={0.5,2,4}}) do
	local m = Data.Monsters[id]
	table.insert(m.drops, {item="DriftPlume",chance=d[1],min=d[2],max=d[3]})
end
table.insert(Data.CollectionItems, "DriftPlume")
Data.CollectionScale.DriftPlume = 0.5

-- Arrows: one per metal tier (Copper uses Alloy Ingots). Smithing forges
-- arrowheads; Fletching assembles 15 arrows from 15 shafts, plumes and heads.
-- ammo = {tier, power}; bows accept arrows up to their maxAmmoTier.
CS.arrowTiers = {
	{id="Copper",ingot="AlloyIngot",level=1,color="B87333"},
}
for _, t in ipairs(Data.MetalTiers) do
	table.insert(CS.arrowTiers, {id=t.id,ingot=t.ingot,level=t.level,ore=t.ore,color=t.color})
end
local arrowPower = {5,12,22,35,50,68,90}
local arrowRanged = {1,5,12,20,30,40,50}
CS.arrowOrder = {}
for index, t in ipairs(CS.arrowTiers) do
	t.index, t.power, t.ranged = index, arrowPower[index], arrowRanged[index]
	local heads, arrow = t.id.."Heads", t.id.."Arrow"
	t.heads, t.arrow = heads, arrow
	table.insert(CS.arrowOrder, arrow)
	item(heads,{name=t.id.." Arrowheads",kind="material",rarity=rarityFor(index),color=t.color,value=math.max(1,math.floor(Data.Items[t.ingot].value/12)),description="Forged at the Forge. Fletch into "..t.id.." Arrows."})
	recipe(heads,{skill="Smithing",level=t.level,xp=math.floor(t.level*1.2+8),costs={[t.ingot]=1},amount=15,repeatable=true,collectionTier=if t.ore then {[t.ore]=1} else nil,station="Forge",category="Arrowheads"})
	item(arrow,{name=t.id.." Arrow",kind="material",category="ammo",combatUse=true,slot="ammo",ammo={tier=index,power=t.power},tier=index,rarity=rarityFor(index),color=t.color,
		requires={Ranged=t.ranged},value=math.max(1,math.floor(Data.Items[t.ingot].value/10)),description="Ammunition (Quiver). +"..t.power.." arrow power. Requires Ranged "..t.ranged.."."})
	recipe(arrow,{skill="Fletching",level=t.level,xp=math.floor(t.level*1.5+10),costs={ArrowShaft=15,DriftPlume=15,[heads]=15},amount=15,repeatable=true,
		collectionTier=if index >= 3 and t.ore then {[t.ore]=2} else nil,station="Workbench",category="Arrows"})
end

-- Bows: shortbow (fast, shorter reach) and longbow (slow, full reach) per wood tier.
CS.woodTiers = {
	{prefix="Meadow",log="Timber",level=1,ranged=1,string="Bowstring",staff={Aetherite=6},color="9C6B3E"},
	{prefix="Windpine",log="WindpineLog",level=15,ranged=10,string="Bowstring",staff={Shard=4},color="6B8E5A"},
	{prefix="Emberoak",log="EmberoakLog",level=30,ranged=20,string="Bowstring",staff={GolemCore=1,ArcaneDust=20},color="B5482A"},
	{prefix="Glimmerbark",log="GlimmerbarkLog",level=45,ranged=30,string="SilkString",staff={VoidEssence=6},color="8FD3C7"},
	{prefix="Starwood",log="StarwoodLog",level=60,ranged=40,string="SilkString",staff={StarFragment=1,VoidEssence=8},color="3B4C7A"},
	{prefix="Aetherheart",log="AetherheartLog",level=75,ranged=50,string="SilkString",staff={StarFragment=3,Prismite=10},color="F0E6A8"},
}
local shortPower = {15,35,60,95,140,195}
local staffPower = {10,25,45,70,100,140}
local staffInt = {20,40,70,110,160,220}
local staffElements = {{"Gale"},{"Tide"},{"Stone"},{"Ember"},{"Gale","Tide"},{"Gale","Tide","Stone","Ember"}}
CS.bowOrder, CS.staffOrder = {}, {}
for index, t in ipairs(CS.woodTiers) do
	t.index = index
	local rarity = rarityFor(index + 1)
	local gate = if index >= 2 then {[t.log]=2} else nil
	local short, long = t.prefix.."Shortbow", t.prefix.."Longbow"
	item(short,{name=t.prefix.." Shortbow",kind="weapon",slot="weapon",style="ranged",tier=index+1,rarity=rarity,color=t.color,stats={critChance=2*index,rangedAccuracy=10*index},
		ranged={power=shortPower[index],speed=0.7,range=30,maxAmmoTier=index+1},requires={Ranged=t.ranged},value=Data.Items[t.log].value*12,
		description="Ranged weapon. Fast shots, 30 stud reach. Arrows up to tier "..(index+1)..". Requires Ranged "..t.ranged.."."})
	recipe(short,{skill="Fletching",level=t.level,xp=t.level*3+15,costs={[t.log]=6,[t.string]=1},collectionTier=gate,station="Workbench",category="Bows"})
	item(long,{name=t.prefix.." Longbow",kind="weapon",slot="weapon",style="ranged",tier=index+1,rarity=rarity,color=t.color,stats={critDamage=8*index,rangedAccuracy=14*index},
		ranged={power=math.floor(shortPower[index]*1.45),speed=1.05,range=CS.maxRange,maxAmmoTier=index+1},requires={Ranged=t.ranged},value=Data.Items[t.log].value*18,
		description="Ranged weapon. Heavy shots, "..CS.maxRange.." stud reach. Arrows up to tier "..(index+1)..". Requires Ranged "..t.ranged.."."})
	recipe(long,{skill="Fletching",level=math.min(99,t.level+5),xp=t.level*4+20,costs={[t.log]=10,[t.string]=1},collectionTier=gate,station="Workbench",category="Bows"})
	table.insert(CS.bowOrder, short); table.insert(CS.bowOrder, long)
	-- Staves (slow, strong, elemental: free glyphs of their elements) and wands (fast, light).
	local staff, wand = t.prefix.."Staff", t.prefix.."Wand"
	local staffCost, wandCost = {[t.log]=4+index*2}, {[t.log]=2+index}
	for id, n in pairs(t.staff) do staffCost[id] = n; wandCost[id] = math.max(1, n // 2) end
	local elements = staffElements[index]
	local elementText = table.concat(elements, ", ")
	item(staff,{name=t.prefix.." Staff",kind="weapon",slot="weapon",style="magic",tier=index+1,rarity=rarity,color=t.color,stats={intelligence=staffInt[index]},
		magic={power=staffPower[index],speed=1.2,elements=elements},requires={Magic=t.ranged},value=Data.Items[t.log].value*16,
		description="Magic weapon. Supplies unlimited "..elementText.." glyphs. Requires Magic "..t.ranged.."."})
	recipe(staff,{skill="Glyphcraft",level=t.level,xp=t.level*3+20,costs=staffCost,collectionTier=gate,station="Workbench",category="Staves"})
	item(wand,{name=t.prefix.." Wand",kind="weapon",slot="weapon",style="magic",tier=index+1,rarity=rarity,color=t.color,stats={intelligence=staffInt[index]//2,abilityDamage=index},
		magic={power=math.floor(staffPower[index]*0.6),speed=0.8,elements={}},requires={Magic=t.ranged},value=Data.Items[t.log].value*10,
		description="Magic weapon. Quick casts. Requires Magic "..t.ranged.."."})
	recipe(wand,{skill="Glyphcraft",level=t.level,xp=t.level*2+12,costs=wandCost,collectionTier=gate,station="Workbench",category="Staves"})
	table.insert(CS.staffOrder, staff); table.insert(CS.staffOrder, wand)
end

-- Glyphs (Glyphcraft): elemental glyphs + one catalyst per spell tier + utility.
CS.glyphOrder = {"GaleGlyph","TideGlyph","StoneGlyph","EmberGlyph","SparkGlyph","SurgeGlyph","TorrentGlyph","VitaGlyph","BindGlyph"}
local glyphs = {
	GaleGlyph={name="Gale Glyph",level=1,xp=6,costs={Aetherite=1},amount=5,color="C9F2FF"},
	TideGlyph={name="Tide Glyph",level=5,xp=8,costs={Aetherite=1,Fish=1},amount=5,color="3F7CAC"},
	StoneGlyph={name="Stone Glyph",level=9,xp=10,costs={Aetherite=1,Ore=1},amount=5,color="8C7A6B"},
	EmberGlyph={name="Ember Glyph",level=14,xp=12,costs={Aetherite=1,Timber=1},amount=5,color="FF7A3D"},
	SparkGlyph={name="Spark Glyph",level=1,xp=10,costs={Aetherite=1,ArcaneDust=1},amount=3,color="FFE680"},
	VitaGlyph={name="Vita Glyph",level=20,xp=24,costs={Aetherite=2,Herb=2},amount=2,color="6BBF59"},
	BindGlyph={name="Bind Glyph",level=25,xp=28,costs={Aetherite=2,BeastHide=1},amount=2,color="5E8C4A"},
	SurgeGlyph={name="Surge Glyph",level=35,xp=40,costs={Voidstone=1,ArcaneDust=2},amount=3,color="8E5BB5",gate={Voidstone=1}},
	TorrentGlyph={name="Torrent Glyph",level=65,xp=90,costs={Prismite=1,VoidEssence=1},amount=3,color="E86FB8",gate={Prismite=1}},
}
for id, g in pairs(glyphs) do
	item(id,{name=g.name,kind="material",category="glyph",combatUse=true,rarity=if g.level>=60 then "Epic" elseif g.level>=30 then "Rare" elseif g.level>=10 then "Uncommon" else "Common",
		color=g.color,value=math.max(2,g.level//2),description="Spell glyph. Inscribed with Glyphcraft "..g.level.."."})
	recipe(id,{skill="Glyphcraft",level=g.level,xp=g.xp,costs=g.costs,amount=g.amount,repeatable=true,collectionTier=g.gate,station="Cauldron",category="Glyphs"})
end
item("HubwardTablet",{name="Hubward Tablet",kind="material",category="tablet",combatUse=true,rarity="Uncommon",color="F9CC77",value=20,description="Break to teleport to Compass Quay (spell Hubward). Not while in combat."})
recipe("HubwardTablet",{skill="Glyphcraft",level=15,xp=25,costs={Aetherite=2,GaleGlyph=3},repeatable=true,station="Cauldron",category="Tablets"})
-- Style accessories.
item("FletcherQuiver",{name="Fletcher's Quiver",kind="accessory",rarity="Uncommon",color=Data.Rarity.Uncommon.color,stats={rangedStrength=5,rangedAccuracy=5},value=40*Data.Rarity.Uncommon.rank^2,description="Accessory. Magical Power "..Data.Rarity.Uncommon.power.."."})
recipe("FletcherQuiver",{skill="Fletching",level=10,xp=60,costs={BeastHide=32,Bowstring=4},collectionTier={BeastHide=2},station="Workbench",category="Accessories"})
item("GlyphboundTome",{name="Glyphbound Tome",kind="accessory",rarity="Rare",color=Data.Rarity.Rare.color,stats={intelligence=30,abilityDamage=3},value=40*Data.Rarity.Rare.rank^2,description="Accessory. Magical Power "..Data.Rarity.Rare.power.."."})
recipe("GlyphboundTome",{skill="Glyphcraft",level=40,xp=160,costs={VoidEssence=12,SparkGlyph=50,SpiderSilk=16},collectionTier={VoidEssence=1},station="Workbench",category="Accessories"})

-- Spells. kind: damage | snare | heal | teleport. Damage tiers: Dart (light),
-- Lance (heavy), Cascade (devastating). costs = glyph items per cast (a staff's
-- elements are free); mana = mana per cast; cooldown = own cooldown (utility),
-- damage spells follow the weapon speed. xp = Magic XP per cast.
Data.Spells, Data.SpellOrder = {}, {}
local function spell(id, def)
	def.id = id
	def.range = def.range or CS.maxRange
	def.costs = def.costs or {}
	if def.requiresWeapon == nil then def.requiresWeapon = true end
	Data.Spells[id] = def
	table.insert(Data.SpellOrder, id)
	return def
end
CS.spellTiers = {
	{id="Dart",name="Dart",catalyst="SparkGlyph",elementCost=1,mana=6,scaling=0.5,xp=6,levels={1,5,9,13},damage={20,24,28,32}},
	{id="Lance",name="Lance",catalyst="SurgeGlyph",elementCost=2,mana=15,scaling=0.7,xp=14,levels={30,35,40,45},damage={70,78,86,94}},
	{id="Cascade",name="Cascade",catalyst="TorrentGlyph",elementCost=3,mana=30,scaling=0.9,xp=25,levels={60,65,70,75},damage={150,165,180,195}},
}
for _, tier in ipairs(CS.spellTiers) do
	for i, element in ipairs(CS.elementOrder) do
		local e = CS.elements[element]
		spell(element..tier.id,{name=e.name.." "..tier.name,kind="damage",tier=tier.id,element=element,level=tier.levels[i],damage=tier.damage[i],
			scaling=tier.scaling,mana=tier.mana,xp=tier.xp,autocast=true,color=e.color,costs={[e.glyph]=tier.elementCost,[tier.catalyst]=1}})
	end
end
spell("Rootbind",{name="Rootbind",kind="snare",level=25,mana=20,xp=25,duration=5,cooldown=8,color="5E8C4A",costs={BindGlyph=1,StoneGlyph=2}})
spell("Mend",{name="Mend",kind="heal",level=20,mana=40,xp=30,heal=25,cooldown=12,requiresWeapon=false,color="6BBF59",costs={VitaGlyph=1,TideGlyph=2}})
spell("Hubward",{name="Hubward",kind="teleport",level=1,mana=0,xp=10,cooldown=3,requiresWeapon=false,tablet=true,color="F9CC77",costs={HubwardTablet=1}})

-- Triangle data: set fields on existing monsters, sea creatures and slayer lines.
CS.monsterStyle = {
	BramblebackBoar="melee",Thornling="magic",ShaleCrawler="melee",CinderMite="magic",BarkStalker="melee",GaleSprite="magic",
	BrassGolem="melee",StormHarrier="ranged",GloomfangSpider="ranged",VoidWisp="magic",ReefLurker="melee",TempestWraith="magic",
	StarbornSentinel="ranged",
	ShellsnapCrab="melee",DriftbellJelly="magic",ReedfinEel="melee",MistwingRay="ranged",InkveilDrifter="magic",
	CoralbackBruiser="melee",StormcoilSerpent="magic",DuskfinManta="ranged",TidewyrmMatriarch="magic",
	-- Slayer lines (bosses)
	Bramble="melee",Gloom="ranged",Tempest="magic",
}
local function applyStyle(def, style)
	def.attackStyle = style
	def.weakness = CS.beatenBy[style]
	def.defenceStyle = CS.beats[style]
end
for id, def in pairs(Data.Monsters) do applyStyle(def, CS.monsterStyle[id] or "melee") end
for id, def in pairs(Data.SeaCreatures) do applyStyle(def, CS.monsterStyle[id] or "melee") end
for line, def in pairs(Data.Slayers) do applyStyle(def, CS.monsterStyle[line] or "melee") end
end
-- End Combat styles section.

------------------------------------------------------------------------------
-- Agility & Hunter (New Skills team; append-only section).
-- Agility (OSRS rooftop courses on floating islets): each course is a loop of
-- obstacles run in order; the server checks order, timing and position, moves
-- the player along the obstacle, rolls failures at low level, pays XP per
-- obstacle plus a lap bonus and rolls Skymarks (traded at the Skymark Exchange
-- for the Windrunner outfit). Agility levels gate world shortcuts.
-- Hunter (OSRS Hunter): snare / box / bird traps tick server-side (max traps
-- 1 + level/20), nets catch swarming creatures on the spot. Catches give XP,
-- pelts, plumes, essences, meat and rare pets; the hunter log is a bestiary.
-- server.server.lua (Skills block) runs both; world.server.lua builds courses,
-- shortcuts, hunting grounds and vendors; verify-skills.luau checks them.
-- Profile (all optional; migrated): p.agility = {laps={[course]=n}, best={[course]=seconds}},
-- p.hunterLog = {[creature]=catches}. Trap and run state is session-only.
------------------------------------------------------------------------------
do
local AG, HU = {}, {}
Data.Agility, Data.Hunter = AG, HU
for _, id in ipairs({"Agility","Hunter"}) do table.insert(Data.SkillOrder, id) end
Data.Skills.Agility = {category="support",color="62C2B0",title="Skyrunner",perLevel={speed=0.5},description="Run obstacle courses and shortcuts between the isles. Raises Speed."}
Data.Skills.Hunter = {category="gathering",color="A8763E",title="Tracker",perLevel={petLuck=0.5,huntingFortune=1},description="Trap, snare and net the wild creatures of the isles. Raises Pet Luck and Hunting Fortune."}
-- New stats: Surefoot cuts obstacle failure chance (a stamina-like perk),
-- Trap Luck raises every catch chance, Hunting Fortune adds primary drops.
Data.Stats.surefoot = {name="Surefoot",symbol="❦",color="62C2B0",base=0,cap=100,percent=true}
Data.Stats.trapLuck = {name="Trap Luck",symbol="⌖",color="A8763E",base=0,cap=100,percent=true}
Data.Stats.huntingFortune = {name="Hunting Fortune",symbol="☘",color="FFAA00",base=0}
for _, id in ipairs({"surefoot","trapLuck","huntingFortune"}) do table.insert(Data.StatOrder, id) end

local function rarityAt(level)
	return if level >= 75 then "Epic" elseif level >= 45 then "Rare" elseif level >= 15 then "Uncommon" else "Common"
end

------------------------------------------------------------------------------
-- Agility
------------------------------------------------------------------------------
-- Obstacle kinds: verb (prompt text), anim (client animation id, player
-- attribute AgilityMove), duration (seconds the server moves the player),
-- arc (studs of lift at the middle of the move).
AG.Kinds = {
	climb={verb="Climb",anim="climb",duration=2.6,arc=0},
	beam={verb="Cross",anim="balance",duration=3.0,arc=0},
	swing={verb="Swing",anim="swing",duration=2.2,arc=-3},
	ledge={verb="Shimmy",anim="ledge",duration=2.8,arc=0},
	gap={verb="Leap",anim="leap",duration=1.3,arc=3},
	vault={verb="Vault",anim="vault",duration=1.4,arc=1.5},
	zip={verb="Ride",anim="zip",duration=2.4,arc=-1},
	drop={verb="Slide",anim="drop",duration=1.6,arc=0},
}
AG.KindOrder = {"climb","beam","swing","ledge","gap","vault","zip","drop"}
AG.STEP_WINDOW = 30      -- seconds to start the next obstacle after landing
AG.FAIL_FADE = 20        -- failures fade out this many levels above the course
AG.OVERLEVEL = 20        -- Skymark chance halves this many levels above the course
AG.MARK_ITEM = "Skymark"
AG.LapTiers = {25,100,250}          -- per course: each milestone grants LapBonus
AG.LapBonus = {speed=1}
AG.MAX_LAP_SECONDS = 3600

item("Skymark",{name="Skymark",kind="material",rarity="Rare",color="7FE3D0",value=25,description="A glinting token left on the courses for nimble runners. Spend at the Skymark Exchange."})

-- risk = failure chance at the course's own level (fades to 0 by +FAIL_FADE).
-- The first obstacle always climbs from the island; the last returns to it.
local function ob(kind, name, risk) return {kind=kind,name=name,risk=risk} end
AG.Courses = {
	{id="QuayRigging",name="Quay Rigging Run",region="Hub",level=1,markChance=0.25,color="DBAD65",obstacles={
		ob("climb","Harbor net"),ob("beam","Mooring spar"),ob("swing","Rigging rope",0.08),ob("ledge","Hull ledge",0.1),ob("gap","Bollard gap"),ob("drop","Sailcloth slide")}},
	{id="MosswakeHedgerow",name="Mosswake Hedgerow Hop",region="Meadow",level=10,markChance=0.25,color="8DB86E",obstacles={
		ob("climb","Ivy trellis"),ob("gap","Hedge gap",0.1),ob("beam","Fallen bough",0.12),ob("vault","Stile fence"),ob("swing","Willow vine",0.12),ob("drop","Haystack drop")}},
	{id="BrassfallScaffold",name="Brassfall Scaffold Circuit",region="Quarry",level=20,markChance=0.26,color="D4A84B",obstacles={
		ob("climb","Mine ladder"),ob("ledge","Scaffold ledge",0.14),ob("beam","Rail girder",0.12),ob("gap","Cart gap",0.12),ob("vault","Ore crates"),ob("zip","Ore-cart cable")}},
	{id="WindpineCanopy",name="Windpine Canopy Loop",region="Windpine",level=30,markChance=0.28,color="9BD18B",obstacles={
		ob("climb","Bark wall"),ob("beam","Pine limb",0.14),ob("swing","Canopy vine",0.14),ob("gap","Branch gap",0.12),ob("ledge","Hollow ledge",0.15),ob("vault","Root arch"),ob("zip","Needle zipline")}},
	{id="SkyreachUpdraft",name="Skyreach Updraft Course",region="Skyreach",level=40,markChance=0.3,color="96ACAB",obstacles={
		ob("climb","Cliff pitons"),ob("gap","Updraft gap",0.15),ob("beam","Brass girder",0.14),ob("ledge","Wind ledge",0.16),ob("swing","Golem chain",0.15),ob("vault","Beacon rail"),ob("drop","Gale chute")}},
	{id="TidewaterMastwalk",name="Tidewater Mastwalk",region="Tidewater",level=50,markChance=0.32,color="5EC8D8",obstacles={
		ob("climb","Mast rigging"),ob("beam","Boom spar",0.15),ob("swing","Halyard swing",0.16),ob("gap","Buoy hop",0.15),ob("ledge","Lighthouse rail",0.16),ob("vault","Net barrels"),ob("zip","Sailcloth zipline")}},
	{id="GloomhollowChasm",name="Gloomhollow Chasm Run",region="Gloomhollow",level=60,markChance=0.34,color="A58CE0",obstacles={
		ob("climb","Crystal wall"),ob("ledge","Silk ledge",0.17),ob("gap","Chasm gap",0.16),ob("beam","Voidstone spine",0.17),ob("swing","Web strand",0.17),ob("vault","Fungal cap"),ob("gap","Wisp stones",0.15),ob("drop","Rappel drop")}},
	{id="TempestStormrun",name="Tempest Stormrun",region="Tempest",level=75,markChance=0.36,color="C6DCFF",obstacles={
		ob("climb","Pylon ladder"),ob("beam","Arc girder",0.18),ob("gap","Thunder gap",0.18),ob("swing","Storm chain",0.18),ob("ledge","Spire ledge",0.2),ob("vault","Crystal rail"),ob("gap","Cloud stones",0.18),ob("zip","Lightning line")}},
}
AG.CourseById = {}
for ci, course in ipairs(AG.Courses) do
	course.index = ci
	course.lapXp = math.floor(30 + course.level * 4)
	course.lapMarks = 1
	AG.CourseById[course.id] = course
	for i, o in ipairs(course.obstacles) do
		local kind = AG.Kinds[o.kind]
		o.index = i
		o.risk = o.risk or 0
		o.duration = kind.duration
		o.xp = math.floor(5 + course.level * 0.9 + (if o.risk > 0 then 2 else 0))
	end
end
-- XP for one full lap (every obstacle + the lap bonus).
function AG.lapTotal(course)
	local total = course.lapXp
	for _, o in ipairs(course.obstacles) do total += o.xp end
	return total
end
-- Chance (0..1) of failing an obstacle: risk at the course level, fading to 0
-- FAIL_FADE levels above it, reduced by Surefoot percent.
function AG.failChance(course, obstacle, level, surefoot)
	local risk = obstacle.risk or 0
	if risk <= 0 then return 0 end
	local fade = math.clamp(1 - ((level or 1) - course.level) / AG.FAIL_FADE, 0, 1)
	return risk * fade * (1 - math.clamp(surefoot or 0, 0, 100) / 100)
end
function AG.markChance(course, level)
	local chance = course.markChance
	if (level or 1) >= course.level + AG.OVERLEVEL then chance *= 0.5 end
	return chance
end
-- Pure run state machine. run = {course, next, readyAt, deadline, startedAt} | nil.
-- Returns verdict, newRun: "start" (obstacle 1 begins a lap), "next" (in order),
-- "lap" (final obstacle), "busy" (still moving), "order" (out of order or a
-- different course), "expired" (too long since the last landing).
function AG.step(run, courseId, index, now)
	local course = AG.CourseById[courseId]
	if not course or type(index) ~= "number" or index < 1 or index > #course.obstacles or index % 1 ~= 0 then return "order", run end
	if run and now < (run.readyAt or 0) then return "busy", run end
	local o = course.obstacles[index]
	local landing = now + o.duration
	if index == 1 then
		return "start", {course=courseId,next=2,readyAt=landing,deadline=landing+AG.STEP_WINDOW,startedAt=now}
	end
	if not run or run.course ~= courseId or run.next ~= index then return "order", run end
	if now > run.deadline then return "expired", nil end
	local verdict = if index == #course.obstacles then "lap" else "next"
	return verdict, {course=courseId,next=if verdict == "lap" then 1 else index + 1,readyAt=landing,deadline=landing+AG.STEP_WINDOW,startedAt=run.startedAt}
end
-- Permanent lap milestone perk across every course (stored in p.perkStats["agility:laps"]).
function AG.lapPerk(laps)
	local tiers = 0
	for id, n in pairs(type(laps) == "table" and laps or {}) do
		if AG.CourseById[id] and type(n) == "number" then
			for _, need in ipairs(AG.LapTiers) do if n >= need then tiers += 1 end end
		end
	end
	if tiers == 0 then return nil, 0 end
	local out = {}
	for stat, v in pairs(AG.LapBonus) do out[stat] = v * tiers end
	return out, tiers
end

-- Shortcuts: two ends (A, B) the world builds; the server moves the player to
-- the other end. region = destination region the traveller must have unlocked.
AG.Shortcuts = {
	{id="CinderSlide",name="Cinder Shelf Slide",level=8,kind="drop",duration=3,xp=8,description="Slide from Brassfall Quarry down to the Cinder Shelf."},
	{id="MosswakeRopeBridge",name="Windpine Rope Bridge",level=20,kind="beam",duration=7,xp=20,region="Windpine",description="A swaying rope bridge from Mosswake Grove to Windpine Grove."},
	{id="SkyreachUpdraft",name="Skyreach Updraft Climb",level=35,kind="climb",duration=6,xp=35,region="Skyreach",description="Climb the updraft holds from Brassfall Quarry to Skyreach."},
	{id="TidewaterSteps",name="Tidewater Stepping Stones",level=45,kind="gap",duration=7,xp=45,region="Tidewater",description="Leap the drifting stones from Meadow Reach to Tidewater Shoals."},
	{id="GloomRappel",name="Gloomhollow Rappel",level=55,kind="drop",duration=7,xp=60,region="Gloomhollow",description="Rappel from the Cinder Shelf into the mouth of Gloomhollow."},
	{id="TempestGaleLine",name="Tempest Gale Line",level=70,kind="zip",duration=7,xp=80,region="Tempest",description="Ride the gale line from Skyreach up to Tempest Spire."},
}
AG.ShortcutById = {}
for i, sc in ipairs(AG.Shortcuts) do sc.index = i; AG.ShortcutById[sc.id] = sc end

-- Windrunner outfit (Skymark Exchange): speed and Surefoot, set bonus.
Data.Sets.Windrunner = {id="Windrunner",name="Windrunner",pieces={},bonus={speed=15,surefoot=15},text="+15 Speed, +15 Surefoot",color="62C2B0"}
local windrunner = {
	{id="WindrunnerHood",slot="helmet",name="Windrunner Hood",stats={speed=4,surefoot=5},marks=20},
	{id="WindrunnerJerkin",slot="chest",name="Windrunner Jerkin",stats={speed=6,surefoot=8,health=10},marks=30},
	{id="WindrunnerLeggings",slot="legs",name="Windrunner Leggings",stats={speed=5,surefoot=6},marks=25},
	{id="WindrunnerBoots",slot="boots",name="Windrunner Boots",stats={speed=8,surefoot=4},marks=20},
}
AG.Shop = {}
for _, w in ipairs(windrunner) do
	item(w.id,{name=w.name,kind="armor",slot=w.slot,set="Windrunner",tier=2,rarity="Rare",color="62C2B0",stats=w.stats,requires={Agility=5},value=w.marks*20,
		description="Part of the Windrunner outfit (Skymark Exchange). Requires Agility 5."})
	table.insert(Data.Sets.Windrunner.pieces, w.id)
	table.insert(AG.Shop, {item=w.id,cost={Skymark=w.marks}})
end
item("FeatherstepCharm",{name="Featherstep Charm",kind="accessory",rarity="Rare",color=Data.Rarity.Rare.color,stats={speed=6,surefoot=6},value=40*Data.Rarity.Rare.rank^2,description="Accessory. Magical Power "..Data.Rarity.Rare.power..". Skymark Exchange."})
item("GaleDraught",{name="Gale Draught",kind="consumable",category="potion",rarity="Uncommon",color="A8F0E0",buff={stats={speed=30,surefoot=20},duration=300},value=30,description="Potion: 5 minute buff. +30 Speed, +20 Surefoot."})
item("SkymarkSatchel",{name="Skymark Satchel",kind="material",rarity="Uncommon",color="7FE3D0",value=60,description="Sell to a merchant for coins (Skymark Exchange)."})
table.insert(AG.Shop, {item="FeatherstepCharm",cost={Skymark=40}})
table.insert(AG.Shop, {item="GaleDraught",cost={Skymark=3}})
table.insert(AG.Shop, {item="SkymarkSatchel",cost={Skymark=2}})

------------------------------------------------------------------------------
-- Hunter
------------------------------------------------------------------------------
-- Methods: traps (snare, box, bird) tick server-side; nets roll on the spot.
-- kit = item that must be owned (never consumed).
HU.Methods = {
	snare={name="Snare",kit="SnareKit",verb="Set snare",trap=true},
	box={name="Box trap",kit="BoxTrap",verb="Set box trap",trap=true},
	bird={name="Bird snare",kit="BirdSnare",verb="Set bird snare",trap=true},
	net={name="Net",kit="SkyNet",verb="Swing net",trap=false},
}
HU.MethodOrder = {"snare","bird","box","net"}
-- Pacing (verify-skills.luau models XP/h from these and holds every creature
-- within 0.5x..1.5x of the gathering tier open at the same level; the top
-- creature lands near 1.3x Celestium mining).
HU.TICK = 4               -- seconds between trap rolls
HU.MAX_TICKS = 40         -- an unsprung trap collapses after this many rolls
HU.DISMANTLE_WINDOW = 4   -- trigger a set trap twice within this many seconds to pick it up
HU.MAX_TRAPS = 5
HU.NET_MISS_COOLDOWN = 2  -- seconds before the same swarm can be netted again after a miss (per player)
HU.LEVEL_BONUS = 0.01     -- catch chance x(1 + this per Hunter level above the creature's)
HU.MAX_CHANCE = 0.6       -- level-scaled chance ceiling, before Trap Luck
HU.TRAP_LUCK_CAP = 50     -- Trap Luck above this does nothing for catch chance
HU.TRAP_LUCK_EFFECT = 0.5 -- each capped point of Trap Luck adds this % (max +25%)
HU.LogTiers = {10,25,50,100,250,500,1000}
HU.LogBonus = {trapLuck=0.5,huntingFortune=1}
function HU.maxTraps(level) return math.min(HU.MAX_TRAPS, 1 + (level or 1) // 20) end
-- Per-roll (traps) or per-swing (nets) catch chance in 0..1.
function HU.catchChance(creature, level, trapLuck)
	local c = creature.base * (1 + math.max(0, (level or 1) - creature.level) * HU.LEVEL_BONUS)
	c = math.min(c, HU.MAX_CHANCE)
	c *= 1 + math.clamp(tonumber(trapLuck) or 0, 0, HU.TRAP_LUCK_CAP) * HU.TRAP_LUCK_EFFECT / 100
	return math.min(0.95, c)
end
function HU.logPerk(log)
	local tiers = 0
	for id, n in pairs(type(log) == "table" and log or {}) do
		if HU.CreatureById[id] and type(n) == "number" then
			for _, need in ipairs(HU.LogTiers) do if n >= need then tiers += 1 end end
		end
	end
	if tiers == 0 then return nil, 0 end
	local out = {}
	for stat, v in pairs(HU.LogBonus) do out[stat] = v * tiers end
	return out, tiers
end

-- Materials (furs, feathers, essences, meat). Feathers feed Fletching, meat
-- Cooking, essences Alchemy, pelts the Thicketstalker outfit.
local materials = {
	{id="DownyPelt",name="Downy Pelt",color="E8DCC8",value=6,rarity="Common",text="Soft fur of a Puffcap Hopper."},
	{id="HopperHaunch",name="Raw Hopper Haunch",color="C97B63",value=4,rarity="Common",text="Raw meat. Roast it at a Hearth."},
	{id="SunwingDust",name="Sunwing Dust",color="F7D774",value=9,rarity="Common",text="Glittering scales of the Sunwing Moth. Brewed at a Cauldron."},
	{id="GrouseQuill",name="Grouse Quill",color="B08A5A",value=10,rarity="Uncommon",text="Stiff quills. Fletch into arrow plumes."},
	{id="RawGrouse",name="Raw Grouse",color="B5654A",value=8,rarity="Uncommon",text="Raw fowl. Bake it into a pie at a Hearth."},
	{id="EmberPelt",name="Ember Pelt",color="D9642B",value=22,rarity="Uncommon",text="Warm fur of a Cinder Ferret."},
	{id="GlintEssence",name="Glint Essence",color="8EF0F8",value=30,rarity="Rare",text="Wing-light of the Glintwing Dragonfly. Brewed at a Cauldron."},
	{id="GalePlume",name="Gale Plume",color="DDEBFF",value=34,rarity="Rare",text="Wind-stiff plume of a Gale Kestrel. Fletch into plumes."},
	{id="ShadowPelt",name="Shadow Pelt",color="3D3654",value=60,rarity="Rare",text="Light-drinking fur of a Gloom Lynx."},
	{id="StormmaneHide",name="Stormmane Hide",color="8FA3C8",value=90,rarity="Epic",text="Crackling hide of a Stormmane Ibex."},
	{id="IbexShank",name="Raw Ibex Shank",color="A85E4E",value=40,rarity="Rare",text="Raw meat. Slow-roast it at a Hearth."},
	{id="StormmaneHorn",name="Stormmane Horn",color="F2F0D8",value=400,rarity="Epic",text="A rare spiral horn, humming with stored lightning."},
}
for _, m in ipairs(materials) do
	item(m.id,{name=m.name,kind="material",rarity=m.rarity,color=m.color,value=m.value,description=m.text})
end

-- Kits (owned, never consumed). kind=material keeps them out of tool slots.
item("SnareKit",{name="Snare Kit",kind="material",category="trap",rarity="Common",color="B08A5A",value=20,hunterMethod="snare",description="Hunter kit: set snares at warren and trail spots. Never used up."})
item("BirdSnare",{name="Bird Snare",kind="material",category="trap",rarity="Common",color="C9B994",value=40,hunterMethod="bird",description="Hunter kit: set bird snares on perches. Never used up."})
item("BoxTrap",{name="Box Trap",kind="material",category="trap",rarity="Uncommon",color="8C6A4A",value=140,hunterMethod="box",description="Hunter kit: bait box traps at dens. Never used up."})
item("SkyNet",{name="Sky Net",kind="material",category="trap",rarity="Common",color="E9F1F7",value=30,hunterMethod="net",description="Hunter kit: swing at swarms of moths and dragonflies. Never used up."})
item("GossamerNet",{name="Gossamer Net",kind="material",category="trap",rarity="Rare",color="D8D8E8",value=300,hunterMethod="net",netBonus=0.1,description="Hunter kit: a silk net. +10% net catch chance. Never used up."})
HU.Kits = {snare={"SnareKit"},bird={"BirdSnare"},box={"BoxTrap"},net={"GossamerNet","SkyNet"}}
recipe("GossamerNet",{skill="Hunter",level=35,xp=180,costs={SpiderSilk=12,SkyNet=1},collectionTier={GlintEssence=1},station="Workbench",category="Hunter"})

-- Creatures: method, Hunter level, region, XP per catch, base catch chance;
-- drops[1] is the primary drop (Hunting Fortune applies to it). respawn = net
-- swarm cooldown after a catch, shared by every player at that spot.
HU.Creatures = {
	{id="PuffcapHopper",name="Puffcap Hopper",method="snare",level=1,region="Meadow",xp=24,base=0.5,color="E8DCC8",
		drops={{item="DownyPelt",chance=1,min=1,max=1},{item="HopperHaunch",chance=0.8,min=1,max=1},{item="PuffkinPet",chance=0.002,min=1,max=1}}},
	{id="SunwingMoth",name="Sunwing Moth",method="net",level=9,region="Meadow",xp=30,base=0.5,respawn=22,color="F7D774",
		drops={{item="SunwingDust",chance=1,min=1,max=2},{item="DriftPlume",chance=0.3,min=1,max=3}}},
	{id="PinecrestGrouse",name="Pinecrest Grouse",method="bird",level=18,region="Windpine",xp=70,base=0.2,color="B08A5A",
		drops={{item="GrouseQuill",chance=1,min=2,max=4},{item="RawGrouse",chance=0.7,min=1,max=1}}},
	{id="CinderFerret",name="Cinder Ferret",method="box",level=27,region="Quarry",xp=110,base=0.1,color="D9642B",
		drops={{item="EmberPelt",chance=1,min=1,max=1},{item="ArcaneDust",chance=0.3,min=1,max=2},{item="PuffkinPet",chance=0.001,min=1,max=1}}},
	{id="GlintwingDragonfly",name="Glintwing Dragonfly",method="net",level=36,region="Tidewater",xp=120,base=0.45,respawn=40,color="8EF0F8",
		drops={{item="GlintEssence",chance=1,min=1,max=2},{item="GlimmerflyPet",chance=0.0015,min=1,max=1}}},
	{id="GaleKestrel",name="Gale Kestrel",method="bird",level=48,region="Skyreach",xp=200,base=0.06,color="DDEBFF",
		drops={{item="GalePlume",chance=1,min=2,max=3},{item="StormFeather",chance=0.3,min=1,max=1}}},
	{id="GloomLynx",name="Gloom Lynx",method="box",level=62,region="Gloomhollow",xp=280,base=0.04,color="3D3654",
		drops={{item="ShadowPelt",chance=1,min=1,max=1},{item="VoidEssence",chance=0.15,min=1,max=1},{item="GlimmerflyPet",chance=0.001,min=1,max=1}}},
	{id="StormmaneIbex",name="Stormmane Ibex",method="snare",level=80,region="Tempest",xp=380,base=0.035,color="8FA3C8",
		drops={{item="StormmaneHide",chance=1,min=1,max=1},{item="IbexShank",chance=0.8,min=1,max=2},{item="StormmaneHorn",chance=0.04,min=1,max=1},{item="StormkidPet",chance=0.001,min=1,max=1}}},
}
HU.CreatureById = {}
for i, c in ipairs(HU.Creatures) do c.index = i; HU.CreatureById[c.id] = c end

-- Pets: three Hunter companions and an Agility lap pet.
for _, pet in ipairs({
	{id="Puffkin",name="Puffkin",skill="Hunter",rarity="Uncommon",color="E8DCC8",perLevel={petLuck=0.1,trapLuck=0.05,health=0.4},ability="Burrow Sense: +10% Hunter XP"},
	{id="Glimmerfly",name="Glimmerfly",skill="Hunter",rarity="Rare",color="8EF0F8",perLevel={huntingFortune=0.6,intelligence=0.3},ability="Glint Trail: +10% Hunter XP"},
	{id="Stormkid",name="Stormkid",skill="Hunter",rarity="Epic",color="8FA3C8",perLevel={trapLuck=0.1,speed=0.2,strength=0.3},ability="Storm Hooves: +15% Hunter XP"},
	{id="Gustling",name="Gustling",skill="Agility",rarity="Rare",color="7FE3D0",perLevel={speed=0.25,surefoot=0.1},ability="Tailwind: +10% Agility XP"},
}) do
	table.insert(Data.Pets, pet)
	Data.PetById[pet.id] = pet
	item(pet.id.."Pet",{name=pet.name.." Pet",kind="pet",pet=pet.id,rarity=pet.rarity,color=pet.color,value=200*Data.Rarity[pet.rarity].rank^2,description="Summon from your pet menu. "..pet.ability})
end
AG.LapDrops = {{item="GustlingPet",chance=0.0008,min=1,max=1}}

-- Thicketstalker outfit (Hunter, crafted at a Workbench from pelts).
Data.Sets.Thicketstalker = {id="Thicketstalker",name="Thicketstalker",pieces={},bonus={trapLuck=10,huntingFortune=20},text="+10 Trap Luck, +20 Hunting Fortune",color="7A8B4E"}
for _, t in ipairs({
	{id="ThicketstalkerCap",slot="helmet",name="Thicketstalker Cap",stats={trapLuck=3,huntingFortune=5},level=15,costs={DownyPelt=12,BeastHide=6}},
	{id="ThicketstalkerVest",slot="chest",name="Thicketstalker Vest",stats={trapLuck=4,huntingFortune=8,health=15},level=25,costs={EmberPelt=10,DownyPelt=10}},
	{id="ThicketstalkerTrousers",slot="legs",name="Thicketstalker Trousers",stats={trapLuck=3,huntingFortune=7},level=22,costs={EmberPelt=8,BeastHide=10}},
	{id="ThicketstalkerBoots",slot="boots",name="Thicketstalker Boots",stats={trapLuck=2,speed=4,huntingFortune=5},level=18,costs={DownyPelt=8,GrouseQuill=6}},
}) do
	item(t.id,{name=t.name,kind="armor",slot=t.slot,set="Thicketstalker",tier=2,rarity="Uncommon",color="7A8B4E",stats=t.stats,requires={Hunter=t.level},value=120+t.level*6,
		description="Part of the Thicketstalker outfit. Requires Hunter "..t.level.."."})
	recipe(t.id,{skill="Hunter",level=t.level,xp=t.level*8,costs=t.costs,station="Workbench",category="Hunter"})
	table.insert(Data.Sets.Thicketstalker.pieces, t.id)
end
item("LynxfangTalisman",{name="Lynxfang Talisman",kind="accessory",rarity="Epic",color=Data.Rarity.Epic.color,stats={trapLuck=5,huntingFortune=10,critChance=1},value=40*Data.Rarity.Epic.rank^2,description="Accessory. Magical Power "..Data.Rarity.Epic.power.."."})
recipe("LynxfangTalisman",{skill="Hunter",level=60,xp=600,costs={ShadowPelt=16,StormFeather=8},collectionTier={ShadowPelt=1},station="Workbench",category="Accessories"})

-- Links into other skills.
-- Fletching: quills and plumes become arrow plumes in bulk.
recipe("QuillPlumes",{output="DriftPlume",skill="Fletching",level=10,xp=10,costs={GrouseQuill=1},amount=10,repeatable=true,station="Workbench",category="Fletching"})
recipe("GalePlumes",{output="DriftPlume",skill="Fletching",level=40,xp=30,costs={GalePlume=1},amount=30,repeatable=true,station="Workbench",category="Fletching"})
-- Cooking: hunted meat.
item("RoastHopper",{name="Roast Hopper",kind="consumable",category="food",rarity="Common",color="C97B63",heal=60,recovery=4,value=10,requires={Cooking=5},description="Restore up to 60 health."})
recipe("RoastHopper",{skill="Cooking",level=5,xp=18,costs={HopperHaunch=1,Herb=1},repeatable=true,station="Hearth",category="Meals"})
item("GrousePie",{name="Grouse Pie",kind="consumable",category="food",rarity="Uncommon",color="D9A066",heal=150,recovery=4,value=30,requires={Cooking=25},description="Restore up to 150 health."})
recipe("GrousePie",{skill="Cooking",level=25,xp=60,costs={RawGrouse=1,Sunwheat=2},repeatable=true,station="Hearth",category="Meals"})
item("StormmaneRoast",{name="Stormmane Roast",kind="consumable",category="buff",rarity="Epic",color="A85E4E",buff={stats={strength=40,speed=20,health=100},duration=600},value=220,description="+40 Strength, +20 Speed, +100 Health for 10 minutes."})
recipe("StormmaneRoast",{skill="Cooking",level=70,xp=280,costs={IbexShank=2,Starfruit=2},repeatable=true,station="Hearth",category="Feasts"})
-- Alchemy: hunted essences.
item("FeatherlightDraught",{name="Featherlight Draught",kind="consumable",category="potion",rarity="Uncommon",color="F7D774",buff={stats={speed=25,surefoot=15},duration=300},value=40,requires={Alchemy=15},description="Potion: 5 minute buff. +25 Speed, +15 Surefoot."})
recipe("FeatherlightDraught",{skill="Alchemy",level=15,xp=55,costs={SunwingDust=3,Herb=2},repeatable=true,station="Cauldron",category="Potions"})
item("TrackersFocus",{name="Tracker's Focus",kind="consumable",category="potion",rarity="Rare",color="8EF0F8",buff={stats={trapLuck=15,huntingFortune=30},duration=600},value=120,requires={Alchemy=40},description="Potion: 10 minute buff. +15 Trap Luck, +30 Hunting Fortune."})
recipe("TrackersFocus",{skill="Alchemy",level=40,xp=125,costs={GlintEssence=2,Moonbloom=1},repeatable=true,station="Cauldron",category="Potions"})

-- Trackers' Lodge (Hunter vendor): kits for coins (+ timber for the box trap).
HU.Shop = {
	{item="SnareKit",cost={coins=50}},
	{item="SkyNet",cost={coins=80}},
	{item="BirdSnare",cost={coins=150}},
	{item="BoxTrap",cost={coins=500,Timber=20}},
}
-- Vendors stay open this long after visiting their prompt.
Data.SKILL_VENDOR_SECONDS = 300
Data.SkillVendors = {
	Agility={name="Skymark Exchange",shop=AG.Shop},
	Hunter={name="Trackers' Lodge",shop=HU.Shop},
}

-- Collections for the new materials (drop-like items reach tiers sooner).
for id, scale in pairs({Skymark=0.05,DownyPelt=0.5,SunwingDust=0.5,GrouseQuill=0.5,EmberPelt=0.3,GlintEssence=0.3,GalePlume=0.3,ShadowPelt=0.2,StormmaneHide=0.2}) do
	table.insert(Data.CollectionItems, id)
	Data.CollectionScale[id] = scale
end

------------------------------------------------------------------------------
-- Quest checks: laps {course,count} and catches {creature,count}.
------------------------------------------------------------------------------
local describe = Data.describeCheck
function Data.describeCheck(o, ...) -- ... = regional flag (§33), passed through
	local kind = type(o) == "table" and o.kind
	if kind == "laps" then
		local course = AG.CourseById[o.course]
		return "Run "..o.count.." "..(if o.count == 1 then "lap" else "laps").." of the "..(course and course.name or tostring(o.course))
	elseif kind == "catches" then
		local creature = HU.CreatureById[o.creature]
		return "Catch "..o.count.." "..(creature and creature.name or tostring(o.creature))
	end
	return describe(o, ...)
end
local function laps(course, count) return {kind="laps",course=course,count=count} end
local function catches(creature, count) return {kind="catches",creature=creature,count=count} end
for _, q in ipairs({
	{id="FirstFootfalls",title="First Footfalls",line="side",region="Hub",
		story="Harbourmaster Wren swears the quay rigging is the best teacher in the isles. Run her course until your feet stop arguing with you.",
		requires={{kind="contracts",count=2}},
		objectives={laps("QuayRigging",5),{kind="level",skill="Agility",level=5}},
		rewards={coins=400,points=1,items={Skymark=3},xp={Agility=500}}},
	{id="TrappersApprentice",title="The Trapper's Apprentice",line="side",region="Meadow",
		story="Old Marrow of the Trackers' Lodge needs a steady hand at the warrens. Snare the hoppers and bring their pelts in.",
		requires={{kind="contracts",count=3}},
		objectives={catches("PuffcapHopper",10),{kind="have",item="DownyPelt",count=5,consume=true},{kind="level",skill="Hunter",level=10}},
		rewards={coins=600,points=1,items={BirdSnare=1},xp={Hunter=800}}},
	{id="WindsOverWindpine",title="Winds over Windpine",line="side",region="Windpine",
		story="The canopy runners and the grouse trappers of Windpine share one secret: read the wind. Run the canopy and trap its birds.",
		requires={{kind="quest",quest="FirstFootfalls"},{kind="level",skill="Agility",level=30},{kind="level",skill="Hunter",level=18}},
		objectives={laps("WindpineCanopy",10),catches("PinecrestGrouse",15)},
		rewards={coins=3000,points=2,perk={speed=3},lamp={xp=3000,skills={"Agility","Hunter"}}}},
	{id="StormmaneTrail",title="The Stormmane Trail",line="side",region="Tempest",
		story="Something with a lightning-white mane grazes the top of the Spire. Outrun the storm and trap the beast, then bring back its horn.",
		requires={{kind="quest",quest="TrappersApprentice"},{kind="level",skill="Hunter",level=80},{kind="level",skill="Agility",level=60}},
		objectives={catches("StormmaneIbex",10),laps("TempestStormrun",5),{kind="have",item="StormmaneHorn",count=1,consume=true}},
		rewards={coins=25000,points=3,perk={trapLuck=5,huntingFortune=10}}},
}) do
	table.insert(Data.Quests, q)
	q.index = #Data.Quests
	Data.QuestById[q.id] = q
end
-- Diary tasks in existing regional diaries (tiers stay within 3-5 tasks).
for _, add in ipairs({
	{"Meadow","Medium",catches("PuffcapHopper",25)},
	{"Quarry","Hard",laps("BrassfallScaffold",25)},
	{"Skyreach","Medium",laps("SkyreachUpdraft",10)},
	{"Windpine","Medium",catches("PinecrestGrouse",25)},
	{"Gloomhollow","Hard",catches("GloomLynx",50)},
	{"Tidewater","Hard",catches("GlintwingDragonfly",50)},
	{"Tempest","Elite",laps("TempestStormrun",100)},
}) do
	local diary = Data.DiaryByRegion[add[1]]
	table.insert(diary.tiers[add[2]].tasks, add[3])
end
end
-- End Agility & Hunter section.

------------------------------------------------------------------------------
-- Mastery (Skill Mastery team; append-only section).
-- Per-activity perk trees (SkyBlock "mountain heart" style) for the five
-- gathering skills and the three combat styles, plus OSRS-style skill
-- milestones (titles, auras, 99 mantles with a stat perk).
--   * Points: each tree draws on its skill: 1 point per level above
--     POINT_START_LEVEL, plus 1 per POST_MAX_STEP XP beyond level 99. Mastery
--     Tokens (1 per collection reaching a TOKEN_TIERS tier) are a shared pool
--     that pays for whatever a tree's own points cannot.
--   * Nodes: {id, name, x (1-5), y (row 1-6), max, cost (points per level),
--     level (skill gate), requires (ANY listed node owned; roots have none),
--     stats (per level, added to computeStats), perks (per level, read by
--     harvest / the Hunter path / the combat bridge), ability (capstone)}.
--   * Capstone abilities: verb `ability "<tree>"`, server cooldown, timed effect.
--   * Respec: verb `masteryRespec "<tree>"`, coins = respecCost(spent, count).
-- Rules live in shared/Progression.lua (mastery*), server verbs in
-- server.server.lua (Mastery block), UI in Hero › Mastery.
-- Profile (optional; migrated): p.mastery = {trees={[tree]={[node]=level}},
--   respecs={[tree]=n}, cooldowns={[tree]=os.time}, active={[tree]={started,expires}},
--   cape=skill|nil, aura=skill|nil, title=skill|nil}.
------------------------------------------------------------------------------
do
local MA = {
	POINT_START_LEVEL = 10,       -- 1 point per level above this (89 at 99)
	POST_MAX_STEP = 1000000,      -- +1 point per 1M XP beyond level 99 (up to 186 more)
	TOKEN_TIERS = {5, 9},         -- collection tiers that each award one Mastery Token
	RESPEC_BASE = 1000, RESPEC_PER_POINT = 60, RESPEC_GROWTH = 1.5, RESPEC_CAP = 2000000,
	PERK_CAP = 100,               -- every chance perk is capped at 100%
	PERK_CAPS = {rareFind=15},    -- tighter totals (after a capstone adds its share)
	PASSIVE_CAPS = {respawnSkip=50, rareFind=15}, -- node totals before a capstone adds its share
	REGROWTH_FLOOR = 2,           -- regrowth never drops below max(2 s, 25% of the node's base)
	REGROWTH_FLOOR_SHARE = 0.25,
	TreeOrder = {"Mining","Woodcutting","Fishing","Farming","Hunter","Melee","Ranged","Magic"},
	Trees = {}, TreeById = {}, TreeOfSkill = {},
}
Data.Mastery = MA

-- Perk vocabulary: how each perk key reads (value is a total, after levels).
MA.Perks = {
	xpBoost     = {name="Lore",          text="+%s%% skill XP from this activity"},
	doubleYield = {name="Twin yield",    text="%s%% chance to double a harvest"},
	tripleYield = {name="Bountiful",     text="%s%% chance to triple a harvest"},
	respawnSkip = {name="Quick regrowth",text="Nodes regrow %s%% faster (floor: 25%% of the timer, min 2 s)"},
	autoSmelt   = {name="Ember touch",   text="%s%% chance to smelt a bonus ingot from the ore"},
	coinFind    = {name="Glint",         text="%s%% chance to find coins (5x the resource value)"},
	trapTick    = {name="Hair trigger",  text="Traps check %s%% faster"},
	rareFind    = {name="Keen nose",     text="+%s Magic Find on catches"},
	firstStrike = {name="Opening blow",  text="%s%% chance your first hit on a fresh foe crits"},
	execute     = {name="Finisher",      text="+%s%% damage to foes below 30%% health"},
	arrowSave   = {name="Quiver thrift", text="%s%% chance a shot keeps its arrow"},
	glyphSave   = {name="Ink thrift",    text="%s%% chance a cast keeps its glyphs"},
	manaThrift  = {name="Lean casting",  text="-%s%% spell mana cost"},
	multishot   = {name="Volley",        text="Shots strike %s targets"},
	yieldMult   = {name="Surge",         text="Harvests yield x%s"},
}

-- Shared shape: a five-column, six-row lattice that branches from one root,
-- merges in the middle and narrows to the capstone (x=3, y=6). Keystones at
-- (1,6)/(5,6) are late-game side nodes. requires lists ANY-of prerequisites.
local function tree(def)
	def.nodes = def.nodes or {}
	def.NodeById = {}
	for index, n in ipairs(def.nodes) do
		n.index = index
		n.max = n.max or 1
		n.cost = n.cost or 1
		n.level = n.level or 1
		n.requires = n.requires or {}
		def.NodeById[n.id] = n
		if n.ability then def.capstone = n.id end
	end
	table.insert(MA.Trees, def)
	MA.TreeById[def.id] = def
	MA.TreeOfSkill[def.skill] = def.id
	return def
end

tree({id="Mining",skill="Mining",name="Deepvein Lattice",color="8C7A6B",activity="gather",
	blurb="Read the stone: richer seams, ember-smelted ingots and veins that regrow under your pick.",nodes={
	{id="SteadyPick",name="Steady Pick",x=3,y=1,max=10,stats={miningFortune=2}},
	{id="QuarrySense",name="Quarry Sense",x=2,y=2,max=5,requires={"SteadyPick"},perks={xpBoost=2}},
	{id="SeamReader",name="Seam Reader",x=4,y=2,max=5,requires={"SteadyPick"},perks={doubleYield=2}},
	{id="Stoneskin",name="Stoneskin",x=1,y=3,max=10,level=15,requires={"QuarrySense"},stats={defense=2}},
	{id="EmberVein",name="Ember Vein",x=3,y=3,max=5,level=25,requires={"QuarrySense","SeamReader"},perks={autoSmelt=3}},
	{id="RichStrata",name="Rich Strata",x=5,y=3,max=10,level=15,requires={"SeamReader"},stats={miningFortune=3}},
	{id="EchoingSeam",name="Echoing Seam",x=2,y=4,max=5,level=35,requires={"Stoneskin","EmberVein"},perks={respawnSkip=4}},
	{id="GlintEye",name="Glint Eye",x=4,y=4,max=5,level=35,requires={"EmberVein","RichStrata"},perks={coinFind=2}},
	{id="DelversLungs",name="Delver's Lungs",x=1,y=5,max=5,level=40,requires={"EchoingSeam"},stats={health=8}},
	{id="FaultLine",name="Fault Line",x=3,y=5,max=3,cost=2,level=50,requires={"EchoingSeam","GlintEye"},perks={doubleYield=5}},
	{id="MoltenCore",name="Molten Core",x=5,y=5,max=5,level=50,requires={"GlintEye"},perks={autoSmelt=3}},
	{id="VeinSurge",name="Vein Surge",x=3,y=6,cost=5,level=60,requires={"FaultLine"},
		ability={duration=20,cooldown=300,yieldMult=2,text="For 20 s every mining harvest yields x2."}},
	{id="BedrockInstinct",name="Bedrock Instinct",x=1,y=6,max=3,cost=3,level=75,requires={"DelversLungs"},stats={miningFortune=8}},
	{id="Geomancer",name="Geomancer",x=5,y=6,max=3,cost=3,level=85,requires={"MoltenCore"},perks={xpBoost=4}},
}})

tree({id="Woodcutting",skill="Woodcutting",name="Canopy Codex",color="5E8C4A",activity="gather",
	blurb="Fell with the grain: twin logs, amber sap and saplings that spring back as you watch.",nodes={
	{id="KeenEdge",name="Keen Edge",x=3,y=1,max=10,stats={foragingFortune=2}},
	{id="GrainReader",name="Grain Reader",x=2,y=2,max=5,requires={"KeenEdge"},perks={xpBoost=2}},
	{id="TwinFell",name="Twin Fell",x=4,y=2,max=5,requires={"KeenEdge"},perks={doubleYield=2}},
	{id="LumberShoulders",name="Lumber Shoulders",x=1,y=3,max=10,level=15,requires={"GrainReader"},stats={strength=1}},
	{id="AmberSap",name="Amber Sap",x=3,y=3,max=5,level=25,requires={"GrainReader","TwinFell"},perks={coinFind=2}},
	{id="Heartwood",name="Heartwood",x=5,y=3,max=10,level=15,requires={"TwinFell"},stats={foragingFortune=3}},
	{id="SwiftSaplings",name="Swift Saplings",x=2,y=4,max=5,level=35,requires={"LumberShoulders","AmberSap"},perks={respawnSkip=5}},
	{id="WoodlandStride",name="Woodland Stride",x=4,y=4,max=5,level=35,requires={"AmberSap","Heartwood"},stats={speed=2}},
	{id="BarkHide",name="Bark Hide",x=1,y=5,max=5,level=40,requires={"SwiftSaplings"},stats={defense=3}},
	{id="SplittingMaul",name="Splitting Maul",x=3,y=5,max=3,cost=2,level=50,requires={"SwiftSaplings","WoodlandStride"},perks={doubleYield=5}},
	{id="GroveWisdom",name="Grove Wisdom",x=5,y=5,max=5,level=50,requires={"WoodlandStride"},perks={xpBoost=3}},
	{id="TimberTempest",name="Timber Tempest",x=3,y=6,cost=5,level=60,requires={"SplittingMaul"},
		ability={duration=30,cooldown=360,yieldMult=2,respawnSkip=25,text="For 30 s logs yield x2 and trees regrow 25% faster."}},
	{id="Elderbark",name="Elderbark",x=1,y=6,max=3,cost=3,level=75,requires={"BarkHide"},stats={foragingFortune=8}},
}})

tree({id="Fishing",skill="Fishing",name="Tidewright Chart",color="3F7CAC",activity="gather",
	blurb="Read the currents: doubled catches, salvaged trinkets and the deep things that rise to your line.",nodes={
	{id="PatientLine",name="Patient Line",x=3,y=1,max=10,stats={fishingFortune=2}},
	{id="LureCraft",name="Lure Craft",x=2,y=2,max=5,requires={"PatientLine"},perks={xpBoost=2}},
	{id="DoubleHook",name="Double Hook",x=4,y=2,max=5,requires={"PatientLine"},perks={doubleYield=2}},
	{id="DeepCurrent",name="Deep Current",x=1,y=3,max=5,level=20,requires={"LureCraft"},stats={seaCreatureChance=1}},
	{id="Salvager",name="Salvager",x=3,y=3,max=5,level=25,requires={"LureCraft","DoubleHook"},perks={coinFind=3}},
	{id="BrineBlood",name="Brine Blood",x=5,y=3,max=10,level=15,requires={"DoubleHook"},stats={health=6}},
	{id="AbyssalCall",name="Abyssal Call",x=1,y=4,max=5,level=40,requires={"DeepCurrent"},stats={seaCreatureChance=1}},
	{id="ShoalSense",name="Shoal Sense",x=3,y=4,max=5,level=35,requires={"DeepCurrent","Salvager","BrineBlood"},perks={respawnSkip=4}},
	{id="KrakenGrip",name="Kraken Grip",x=5,y=4,max=10,level=35,requires={"BrineBlood"},stats={fishingFortune=3}},
	{id="LeviathanLore",name="Leviathan Lore",x=2,y=5,max=5,level=50,requires={"AbyssalCall","ShoalSense"},stats={strength=2,critDamage=2}},
	{id="CastNet",name="Cast Net",x=4,y=5,max=3,cost=2,level=50,requires={"ShoalSense","KrakenGrip"},perks={doubleYield=5}},
	{id="Tidecall",name="Tidecall",x=3,y=6,cost=5,level=60,requires={"LeviathanLore","CastNet"},
		ability={duration=30,cooldown=360,yieldMult=2,stats={seaCreatureChance=20},text="For 30 s catches yield x2 and +20 Sea Creature Chance."}},
	{id="Stormsailor",name="Stormsailor",x=1,y=6,max=3,cost=3,level=75,requires={"LeviathanLore"},stats={seaCreatureChance=2}},
	{id="Brinewise",name="Brinewise",x=5,y=6,max=3,cost=3,level=85,requires={"CastNet"},stats={fishingFortune=8}},
}})

tree({id="Farming",skill="Farming",name="Greenward Almanac",color="C9A227",activity="gather",
	blurb="Tend the rows: bumper crops, triple furrows and fields that sprout again before you turn.",nodes={
	{id="TilledRows",name="Tilled Rows",x=3,y=1,max=10,stats={farmingFortune=2}},
	{id="AlmanacStudy",name="Almanac Study",x=2,y=2,max=5,requires={"TilledRows"},perks={xpBoost=2}},
	{id="BumperCrop",name="Bumper Crop",x=4,y=2,max=5,requires={"TilledRows"},perks={doubleYield=2}},
	{id="HeartyHarvest",name="Hearty Harvest",x=1,y=3,max=10,level=15,requires={"AlmanacStudy"},stats={health=6}},
	{id="MarketEye",name="Market Eye",x=3,y=3,max=5,level=25,requires={"AlmanacStudy","BumperCrop"},perks={coinFind=3}},
	{id="RichLoam",name="Rich Loam",x=5,y=3,max=10,level=15,requires={"BumperCrop"},stats={farmingFortune=3}},
	{id="QuickSprout",name="Quick Sprout",x=2,y=4,max=5,level=35,requires={"HeartyHarvest","MarketEye"},perks={respawnSkip=5}},
	{id="SeedSaver",name="Seed Saver",x=4,y=4,max=5,level=35,requires={"MarketEye","RichLoam"},perks={doubleYield=2}},
	{id="SunlitRows",name="Sunlit Rows",x=1,y=5,max=5,level=45,requires={"QuickSprout"},stats={farmingFortune=1}},
	{id="TripleFurrow",name="Triple Furrow",x=3,y=5,max=3,cost=2,level=50,requires={"QuickSprout","SeedSaver"},perks={doubleYield=5}},
	{id="Pollinator",name="Pollinator",x=5,y=5,max=5,level=50,requires={"SeedSaver"},stats={petLuck=1}},
	{id="VerdantBloom",name="Verdant Bloom",x=3,y=6,cost=5,level=60,requires={"TripleFurrow"},
		ability={duration=20,cooldown=300,yieldMult=2,text="For 20 s every crop harvest yields x2."}},
	{id="Harvestlord",name="Harvestlord",x=5,y=6,max=3,cost=3,level=75,requires={"Pollinator"},stats={farmingFortune=6}},
}})

tree({id="Hunter",skill="Hunter",name="Trackways Map",color="A8763E",activity="hunt",
	blurb="Know the trail: faster traps, twin catches and a nose for the rare pelt.",nodes={
	{id="QuietStep",name="Quiet Step",x=3,y=1,max=10,stats={huntingFortune=2}},
	{id="TrailLore",name="Trail Lore",x=2,y=2,max=5,requires={"QuietStep"},perks={xpBoost=2}},
	{id="SnugKnots",name="Snug Knots",x=4,y=2,max=5,requires={"QuietStep"},stats={trapLuck=1}},
	{id="SpringTension",name="Spring Tension",x=1,y=3,max=5,level=20,requires={"TrailLore"},perks={trapTick=3}},
	{id="TwinSnare",name="Twin Snare",x=3,y=3,max=5,level=25,requires={"TrailLore","SnugKnots"},perks={doubleYield=3}},
	{id="KeenNose",name="Keen Nose",x=5,y=3,max=5,level=25,requires={"SnugKnots"},perks={rareFind=1}},
	{id="HairTrigger",name="Hair Trigger",x=2,y=4,max=5,level=40,requires={"SpringTension","TwinSnare"},perks={trapTick=3}},
	{id="PeltGrader",name="Pelt Grader",x=4,y=4,max=10,level=35,requires={"TwinSnare","KeenNose"},stats={huntingFortune=4}},
	{id="Fleetfoot",name="Fleetfoot",x=1,y=5,max=5,level=45,requires={"HairTrigger"},stats={speed=2}},
	{id="MasterTrapper",name="Master Trapper",x=3,y=5,max=3,cost=2,level=50,requires={"HairTrigger","PeltGrader"},stats={trapLuck=2}},
	{id="WildBond",name="Wild Bond",x=5,y=5,max=5,level=50,requires={"PeltGrader"},stats={petLuck=2}},
	{id="LureSong",name="Lure Song",x=3,y=6,cost=5,level=60,requires={"MasterTrapper"},
		ability={duration=60,cooldown=420,doubleYield=100,stats={trapLuck=25},text="For 60 s every catch pays double and +25 Trap Luck."}},
	{id="Packmaster",name="Packmaster",x=1,y=6,max=3,cost=3,level=75,requires={"Fleetfoot"},perks={rareFind=3}},
}})

tree({id="Melee",skill="Combat",style="melee",name="Warpath Codex",color="C8553D",activity="combat",
	blurb="Steel and nerve: opening blows that crit, finishing strikes and a warcry that shakes the isles.",nodes={
	{id="IronGrip",name="Iron Grip",x=3,y=1,max=10,stats={strength=2}},
	{id="BattleRhythm",name="Battle Rhythm",x=2,y=2,max=5,requires={"IronGrip"},stats={attackSpeed=1}},
	{id="KeenBlade",name="Keen Blade",x=4,y=2,max=5,requires={"IronGrip"},stats={critChance=1}},
	{id="Bulwark",name="Bulwark",x=1,y=3,max=10,level=15,requires={"BattleRhythm"},stats={defense=3}},
	{id="OpeningBlow",name="Opening Blow",x=3,y=3,max=5,level=25,requires={"BattleRhythm","KeenBlade"},perks={firstStrike=10}},
	{id="CruelEdge",name="Cruel Edge",x=5,y=3,max=10,level=15,requires={"KeenBlade"},stats={critDamage=3}},
	{id="Bloodthirst",name="Bloodthirst",x=2,y=4,max=5,level=35,requires={"Bulwark","OpeningBlow"},stats={lifesteal=1}},
	{id="Finisher",name="Finisher",x=4,y=4,max=5,level=35,requires={"OpeningBlow","CruelEdge"},perks={execute=4}},
	{id="Warhide",name="Warhide",x=1,y=5,max=10,level=40,requires={"Bloodthirst"},stats={health=10}},
	{id="WeaponLore",name="Weapon Lore",x=3,y=5,max=5,level=45,requires={"Bloodthirst","Finisher"},perks={xpBoost=3}},
	{id="RendingStrikes",name="Rending Strikes",x=5,y=5,max=5,cost=2,level=50,requires={"Finisher"},stats={strength=4}},
	{id="WarcryCrescendo",name="Warcry Crescendo",x=3,y=6,cost=5,level=60,requires={"WeaponLore","RendingStrikes"},
		ability={duration=15,cooldown=240,stats={strength=60,critChance=20},text="For 15 s +60 Strength and +20 Crit Chance."}},
	{id="Unbroken",name="Unbroken",x=1,y=6,max=3,cost=3,level=75,requires={"Warhide"},stats={defense=15}},
	{id="Bladesong",name="Bladesong",x=5,y=6,max=3,cost=3,level=85,requires={"RendingStrikes"},stats={critDamage=10}},
}})

tree({id="Ranged",skill="Ranged",style="ranged",name="Fletchline Doctrine",color="6FA35A",activity="combat",
	blurb="Draw, breathe, loose: arrows that come back to the quiver, pinning shots and the Volley.",nodes={
	{id="SteadyDraw",name="Steady Draw",x=3,y=1,max=10,stats={rangedStrength=2}},
	{id="EagleSight",name="Eagle Sight",x=2,y=2,max=5,requires={"SteadyDraw"},stats={rangedAccuracy=3}},
	{id="QuiverThrift",name="Quiver Thrift",x=4,y=2,max=5,requires={"SteadyDraw"},perks={arrowSave=3}},
	{id="LightFeet",name="Light Feet",x=1,y=3,max=5,level=15,requires={"EagleSight"},stats={speed=2}},
	{id="PinningShot",name="Pinning Shot",x=3,y=3,max=5,level=25,requires={"EagleSight","QuiverThrift"},perks={firstStrike=10}},
	{id="BarbedHeads",name="Barbed Heads",x=5,y=3,max=10,level=15,requires={"QuiverThrift"},stats={critDamage=3}},
	{id="WindReader",name="Wind Reader",x=2,y=4,max=5,level=35,requires={"LightFeet","PinningShot"},stats={rangedAccuracy=4}},
	{id="FletchersEye",name="Fletcher's Eye",x=4,y=4,max=5,level=35,requires={"PinningShot","BarbedHeads"},perks={arrowSave=4}},
	{id="Skirmisher",name="Skirmisher",x=1,y=5,max=5,level=40,requires={"WindReader"},stats={critChance=1}},
	{id="Deadeye",name="Deadeye",x=3,y=5,max=5,cost=2,level=50,requires={"WindReader","FletchersEye"},stats={rangedStrength=5}},
	{id="QuarryMark",name="Quarry Mark",x=5,y=5,max=5,level=50,requires={"FletchersEye"},perks={execute=4}},
	{id="Volley",name="Volley",x=3,y=6,cost=5,level=60,requires={"Deadeye"},
		ability={duration=10,cooldown=180,multishot=3,stats={rangedStrength=20},text="For 10 s each shot strikes 3 targets, +20 Ranged Strength."}},
	{id="Longwatch",name="Longwatch",x=5,y=6,max=3,cost=3,level=75,requires={"QuarryMark"},perks={xpBoost=4}},
}})

tree({id="Magic",skill="Magic",style="magic",name="Glyphbound Grimoire",color="5C7AEA",activity="combat",
	blurb="Ink and will: glyphs that are not spent, leaner casting and the Glyphstorm.",nodes={
	{id="FocusedMind",name="Focused Mind",x=3,y=1,max=10,stats={intelligence=5}},
	{id="InkThrift",name="Ink Thrift",x=2,y=2,max=5,requires={"FocusedMind"},perks={glyphSave=3}},
	{id="ManaWeave",name="Mana Weave",x=4,y=2,max=5,requires={"FocusedMind"},perks={manaThrift=2}},
	{id="WardedRobes",name="Warded Robes",x=1,y=3,max=10,level=15,requires={"InkThrift"},stats={defense=2}},
	{id="ArcaneSurge",name="Arcane Surge",x=3,y=3,max=5,level=25,requires={"InkThrift","ManaWeave"},stats={abilityDamage=1}},
	{id="DeepWell",name="Deep Well",x=5,y=3,max=10,level=15,requires={"ManaWeave"},stats={intelligence=8}},
	{id="ScribesPatience",name="Scribe's Patience",x=2,y=4,max=5,level=35,requires={"WardedRobes","ArcaneSurge"},perks={glyphSave=4}},
	{id="LeanCasting",name="Lean Casting",x=4,y=4,max=5,level=35,requires={"ArcaneSurge","DeepWell"},perks={manaThrift=3}},
	{id="RunicSkin",name="Runic Skin",x=1,y=5,max=5,level=40,requires={"ScribesPatience"},stats={health=8}},
	{id="Spellweaver",name="Spellweaver",x=3,y=5,max=5,cost=2,level=50,requires={"ScribesPatience","LeanCasting"},stats={abilityDamage=2}},
	{id="Studious",name="Studious",x=5,y=5,max=5,level=45,requires={"LeanCasting"},perks={xpBoost=3}},
	{id="Glyphstorm",name="Glyphstorm",x=3,y=6,cost=5,level=60,requires={"Spellweaver"},
		ability={duration=15,cooldown=240,manaThrift=50,glyphSave=100,stats={abilityDamage=25},text="For 15 s spells cost half mana, spend no glyphs, +25% Ability Damage."}},
	{id="Archmage",name="Archmage",x=1,y=6,max=3,cost=3,level=75,requires={"RunicSkin"},stats={intelligence=40}},
}})

-- Ore -> ingot for Ember touch (auto-smelt).
MA.SmeltOf = {Ore="AlloyIngot"}
for _, tier in ipairs(Data.MetalTiers) do MA.SmeltOf[tier.ore] = tier.ingot end

-- Respec price: grows with points spent and with every earlier respec of that tree.
function MA.respecCost(spent, count)
	local cost = (MA.RESPEC_BASE + MA.RESPEC_PER_POINT * math.max(0, spent or 0)) * MA.RESPEC_GROWTH ^ math.max(0, count or 0)
	return math.min(MA.RESPEC_CAP, math.floor(cost))
end

------------------------------------------------------------------------------
-- Skill milestones (OSRS-style unlock list): titles at 10/25/50/75/99, auras
-- at 50 and 75, a mantle (skillcape) at 99 whose stat perk applies while worn.
-- Coin rewards stay Data.levelCoinReward (paid by the server on level-up).
------------------------------------------------------------------------------
MA.MilestoneLevels = {10, 25, 50, 75, 99}
MA.TitlePrefix = {[10]="Fledgling",[25]="Adept",[50]="Seasoned",[75]="Master",[99]="Grand"}
MA.AuraLevels = {[50]="Ember",[75]="Radiant"}
MA.CapePerk = {
	Combat={strength=10,critDamage=10}, Mining={miningFortune=25,defense=10}, Woodcutting={foragingFortune=25,strength=5},
	Fishing={fishingFortune=20,seaCreatureChance=2}, Farming={farmingFortune=25,health=20}, Smithing={defense=20},
	Cooking={health=50}, Alchemy={intelligence=30,health=10}, Enchanting={intelligence=30,magicFind=2}, Taming={petLuck=10},
	Dungeoneering={health=50,defense=10}, Carpentry={health=30,defense=5}, Ranged={rangedStrength=10,rangedAccuracy=10},
	Magic={intelligence=50,abilityDamage=5}, Fletching={rangedStrength=8,speed=3}, Glyphcraft={intelligence=25,abilityDamage=3},
	Agility={speed=10,surefoot=10}, Hunter={trapLuck=5,huntingFortune=10},
}
MA.DefaultCapePerk = {health=25}
function MA.capePerk(skill) return MA.CapePerk[skill] or MA.DefaultCapePerk end
function MA.title(skill, level)
	local def = Data.Skills[skill]
	local best = nil
	for _, at in ipairs(MA.MilestoneLevels) do if (level or 1) >= at then best = at end end
	if not best or not def then return nil end
	return MA.TitlePrefix[best].." "..(def.title or skill), best
end
-- Ordered milestone list for a skill: {level, kind ("title"|"aura"|"cape"), name, text, coins, stats?}.
function MA.milestones(skill)
	local def = Data.Skills[skill]
	if not def then return {} end
	local out = {}
	for _, at in ipairs(MA.MilestoneLevels) do
		local entry = {level=at,kind="title",name=MA.TitlePrefix[at].." "..(def.title or skill),coins=Data.levelCoinReward(at)}
		entry.text = "Title: "..entry.name
		if MA.AuraLevels[at] then entry.kind = "aura"; entry.aura = MA.AuraLevels[at]; entry.text ..= " · "..MA.AuraLevels[at].." "..skill.." aura" end
		if at == Data.MAX_LEVEL then
			entry.kind = "cape"; entry.cape = "Mantle of the "..(def.title or skill); entry.stats = MA.capePerk(skill)
			entry.text ..= " · "..entry.cape.." (skillcape)"
		end
		table.insert(out, entry)
	end
	return out
end
end
-- End Mastery section.

-- Gear depth (Gear Depth team; append-only section).
-- SkyBlock-style item upgrades layered on top of an item's base stats:
--   reforges p.reforges[itemId] = reforgeId    rarity-scaled bonus; rolled at the
--            Reforge Anvil for coins, or a specific (stronger) one applied with a
--            reforge stone. Tool reforges' "fortune" becomes the tool skill's fortune.
--   stars    p.stars[itemId] = 0..5            each star adds STAR_PERCENT% of the
--            item's base stats (dungeon gear DUNGEON_STAR_PERCENT%); costs essence + coins.
--   tomes    p.books[itemId] = {tempering=0..10, masterwork=true|nil}
--            Tempering Tome: flat stats per tome (weapons and armor); Masterwork Tome:
--            rarity +1 tier (cap Mythic), which raises reforge scaling, reforge cost
--            and an accessory's Magical Power.
-- Items are stackable counts per id (p.items[id]), so like enchants every upgrade
-- is bound to the item id in the journal: all copies of an id share it and it
-- survives selling the last copy. Upgraded ids cannot be auctioned.
-- Every helper takes `g` = any table with {reforges, stars, books} (a profile or
-- the snapshot's depth.gear), so the server, Progression and the UI share them.
------------------------------------------------------------------------------
do
local Gear = {}
Data.Gear = Gear
Gear.Categories = {"melee","ranged","magic","armor","tool","accessory"}
Gear.CategoryNames = {melee="Melee weapon",ranged="Bow",magic="Staff or wand",armor="Armor",tool="Tool",accessory="Accessory"}
-- Reforge bonus multiplier by (effective) rarity.
Gear.RarityScale = {Common=1,Uncommon=1.5,Rare=2,Epic=3,Legendary=4,Mythic=5}
-- Reforge Anvil coins per roll (and per stone application) by effective rarity.
Gear.ReforgeCost = {Common=250,Uncommon=500,Rare=1000,Epic=2500,Legendary=5000,Mythic=10000}
Gear.STAR_MAX = 5
-- Extra upgrade layers appended by later sections: {id, stats(g, itemId, def, breakdown) -> level, stats}.
Gear.Layers = {}
Gear.STAR_PERCENT = 2
Gear.DUNGEON_STAR_PERCENT = 4
Gear.StarEssence = {10,20,35,55,80} -- essence for star k, x (1 + 0.25 * (rank - 1)) by base rarity
Gear.StarCoins = 200                -- coins for star k: StarCoins * k^2 * rank
Gear.TEMPERING_MAX = 10
Gear.Tempering = {melee={damage=2,strength=2},ranged={rangedStrength=2,rangedAccuracy=2},magic={intelligence=4},armor={health=4,defense=2}}

local function add(id, def) def.id = id; return def end
-- stats are Common values; stone = the item that applies it (never rolled at the anvil).
-- toolKinds limits a tool reforge to those tool kinds (nil = every tool).
Gear.Reforges = {
	-- Melee weapons
	Honed=add("Honed",{name="Honed",category="melee",stats={critChance=1,critDamage=3}}),
	Vicious=add("Vicious",{name="Vicious",category="melee",stats={strength=3,critDamage=1}}),
	Brisk=add("Brisk",{name="Brisk",category="melee",stats={attackSpeed=1,strength=1}}),
	Burnished=add("Burnished",{name="Burnished",category="melee",stats={damage=2,strength=1}}),
	Stalwart=add("Stalwart",{name="Stalwart",category="melee",stats={defense=2,strength=2}}),
	Savage=add("Savage",{name="Savage",category="melee",stats={strength=2,critDamage=3}}),
	Runic=add("Runic",{name="Runic",category="melee",stats={intelligence=4,strength=1}}),
	Emberwrought=add("Emberwrought",{name="Emberwrought",category="melee",stone="EmberheartCinder",stats={strength=4,critDamage=5,attackSpeed=1}}),
	Starbitten=add("Starbitten",{name="Starbitten",category="melee",stone="StarbiteShard",stats={critChance=2,critDamage=6,strength=3,damage=2}}),
	-- Bows
	Steady=add("Steady",{name="Steady",category="ranged",stats={rangedAccuracy=3,critChance=1}}),
	Piercing=add("Piercing",{name="Piercing",category="ranged",stats={rangedStrength=3}}),
	Hawkeyed=add("Hawkeyed",{name="Hawkeyed",category="ranged",stats={critChance=2,rangedAccuracy=1}}),
	Taut=add("Taut",{name="Taut",category="ranged",stats={rangedStrength=2,critDamage=2}}),
	Featherlight=add("Featherlight",{name="Featherlight",category="ranged",stats={speed=1,rangedAccuracy=2}}),
	Barbed=add("Barbed",{name="Barbed",category="ranged",stats={critDamage=4,rangedStrength=1}}),
	Windborne=add("Windborne",{name="Windborne",category="ranged",stats={attackSpeed=1,rangedAccuracy=1}}),
	Galestrung=add("Galestrung",{name="Galestrung",category="ranged",stone="GalestringCoil",stats={rangedStrength=4,rangedAccuracy=4,critDamage=4}}),
	Undertow=add("Undertow",{name="Undertow",category="ranged",stone="UndertowBarb",stats={critChance=2,rangedStrength=3,critDamage=3}}),
	-- Staves and wands
	Lucid=add("Lucid",{name="Lucid",category="magic",stats={intelligence=6}}),
	Runebound=add("Runebound",{name="Runebound",category="magic",stats={intelligence=4,abilityDamage=0.5}}),
	Ethereal=add("Ethereal",{name="Ethereal",category="magic",stats={intelligence=5,speed=1}}),
	Focused=add("Focused",{name="Focused",category="magic",stats={abilityDamage=1}}),
	Glyphic=add("Glyphic",{name="Glyphic",category="magic",stats={intelligence=3,abilityDamage=0.5}}),
	Serene=add("Serene",{name="Serene",category="magic",stats={intelligence=4,health=4}}),
	Flickering=add("Flickering",{name="Flickering",category="magic",stats={intelligence=2,speed=2}}),
	Voidsung=add("Voidsung",{name="Voidsung",category="magic",stone="VoidhymnShard",stats={intelligence=10,abilityDamage=1.5}}),
	Astral=add("Astral",{name="Astral",category="magic",stone="AstralLens",stats={intelligence=8,abilityDamage=1,health=5}}),
	-- Armor
	Bulwark=add("Bulwark",{name="Bulwark",category="armor",stats={defense=4}}),
	Vital=add("Vital",{name="Vital",category="armor",stats={health=6}}),
	Hardy=add("Hardy",{name="Hardy",category="armor",stats={defense=2,health=3}}),
	Nimble=add("Nimble",{name="Nimble",category="armor",stats={speed=1,defense=1}}),
	Fervent=add("Fervent",{name="Fervent",category="armor",stats={strength=2,defense=1}}),
	Scholarly=add("Scholarly",{name="Scholarly",category="armor",stats={intelligence=5,defense=1}}),
	Gilded=add("Gilded",{name="Gilded",category="armor",stats={magicFind=0.5,health=2}}),
	Coralclad=add("Coralclad",{name="Coralclad",category="armor",stone="CoralplateFragment",stats={defense=5,health=8}}),
	Wardbound=add("Wardbound",{name="Wardbound",category="armor",stone="WardstoneSeal",stats={defense=4,health=6,strength=2}}),
	Starwoven=add("Starwoven",{name="Starwoven",category="armor",stone="StarwovenThread",stats={defense=3,health=5,intelligence=6,critDamage=2}}),
	-- Gathering tools
	Diligent=add("Diligent",{name="Diligent",category="tool",stats={fortune=3,miningSpeed=6}}),
	Thrifty=add("Thrifty",{name="Thrifty",category="tool",stats={fortune=4}}),
	Hearty=add("Hearty",{name="Hearty",category="tool",stats={fortune=2,health=4}}),
	Fortuitous=add("Fortuitous",{name="Fortuitous",category="tool",stats={fortune=2,magicFind=0.3}}),
	Quickhand=add("Quickhand",{name="Quickhand",category="tool",stats={fortune=1,miningSpeed=10}}),
	Brined=add("Brined",{name="Brined",category="tool",toolKinds={"Rod"},stats={fortune=2,seaCreatureChance=0.3}}),
	Verdant=add("Verdant",{name="Verdant",category="tool",toolKinds={"Hoe","Hatchet"},stats={fortune=5}}),
	Deepvein=add("Deepvein",{name="Deepvein",category="tool",stone="DeepveinGeode",stats={fortune=8,miningSpeed=10}}),
	Tidebound=add("Tidebound",{name="Tidebound",category="tool",stone="TidepearlKnot",toolKinds={"Rod"},stats={fortune=6,seaCreatureChance=0.6}}),
	-- Accessories (magicalPower adds to the Magical Power total)
	Gleaming=add("Gleaming",{name="Gleaming",category="accessory",stats={magicalPower=1}}),
	Hale=add("Hale",{name="Hale",category="accessory",stats={health=2}}),
	Watchful=add("Watchful",{name="Watchful",category="accessory",stats={critChance=0.5}}),
	Fiery=add("Fiery",{name="Fiery",category="accessory",stats={strength=1,critDamage=0.5}}),
	Clever=add("Clever",{name="Clever",category="accessory",stats={intelligence=2}}),
	Charmed=add("Charmed",{name="Charmed",category="accessory",stats={magicFind=0.2,petLuck=0.2}}),
	Warded=add("Warded",{name="Warded",category="accessory",stats={defense=1,health=1}}),
	Resonant=add("Resonant",{name="Resonant",category="accessory",stone="ResonanceCrystal",stats={magicalPower=3,strength=1}}),
	Prismlit=add("Prismlit",{name="Prismlit",category="accessory",stone="PrismlitLens",stats={magicalPower=2,critDamage=1,intelligence=2}}),
}
-- Anvil pools and display order per category (stone reforges last).
Gear.ReforgeOrder = {}
Gear.StoneFor = {}
for _, category in ipairs(Gear.Categories) do Gear.ReforgeOrder[category] = {} end
for id, r in pairs(Gear.Reforges) do table.insert(Gear.ReforgeOrder[r.category], id) end
for _, list in pairs(Gear.ReforgeOrder) do
	table.sort(list, function(a, b)
		local sa, sb = Gear.Reforges[a].stone ~= nil, Gear.Reforges[b].stone ~= nil
		if sa ~= sb then return sb end
		return a < b
	end)
end

-- Materials: reforge stones, essences and tomes (all Bazaar commodities).
local stoneInfo = {
	EmberheartCinder={name="Emberheart Cinder",rarity="Rare",color="E0703A",where="Cinder Mites and Brambleback Matriarchs"},
	StarbiteShard={name="Starbite Shard",rarity="Epic",color="FFE7A0",where="Tempest Wraiths and Tempest Revenants"},
	GalestringCoil={name="Galestring Coil",rarity="Rare",color="A8DADC",where="Gale Sprites and Storm Harriers"},
	UndertowBarb={name="Undertow Barb",rarity="Epic",color="2E6F8E",where="Stormcoil Serpents and Duskfin Mantas"},
	VoidhymnShard={name="Voidhymn Shard",rarity="Epic",color="7D5BBE",where="Void Wisps and Gloomfang Broodmothers"},
	AstralLens={name="Astral Lens",rarity="Epic",color="B9A8F0",where="Observatory chests (Floor III+)"},
	CoralplateFragment={name="Coralplate Fragment",rarity="Rare",color="EF6F6C",where="Coralback Bruisers and Reef Lurkers"},
	WardstoneSeal={name="Wardstone Seal",rarity="Rare",color="9C8A6E",where="slayer bosses"},
	StarwovenThread={name="Starwoven Thread",rarity="Epic",color="8E7CC3",where="Observatory chests (Floor II+)"},
	DeepveinGeode={name="Deepvein Geode",rarity="Rare",color="7A6A9E",where="Shale Crawlers and Brass Golems"},
	TidepearlKnot={name="Tidepearl Knot",rarity="Epic",color="BFF7E6",where="Inkveil Drifters and Tidewyrm Matriarchs"},
	ResonanceCrystal={name="Resonance Crystal",rarity="Legendary",color="FF9ECD",where="tier IV slayer bosses and Tempest Wraiths"},
	PrismlitLens={name="Prismlit Lens",rarity="Legendary",color="E86FB8",where="Observatory chests (Floor IV+)"},
}
for reforgeId, r in pairs(Gear.Reforges) do
	if r.stone then
		local s = stoneInfo[r.stone]
		Gear.StoneFor[reforgeId] = r.stone
		item(r.stone,{name=s.name,kind="material",rarity=s.rarity,color=s.color,reforgeStone=reforgeId,value=150*Data.Rarity[s.rarity].rank^2,
			description="Reforge stone. Applies the "..r.name.." reforge to a "..string.lower(Gear.CategoryNames[r.category]).." at the Reforge Anvil. Dropped by "..s.where.."."})
	end
end
item("WildheartEssence",{name="Wildheart Essence",kind="material",rarity="Rare",color="C8553D",value=25,essence=true,description="Feral essence torn from slayer bosses. Stars weapons and armor."})
item("BrinelightEssence",{name="Brinelight Essence",kind="material",rarity="Rare",color="4FB0C6",value=25,essence=true,description="Glowing brine from sea creatures. Stars gathering tools."})
Data.Items.ObservatoryEssence.essence = true
item("TemperingTome",{name="Tempering Tome",kind="material",rarity="Epic",color="D9822B",value=400,tome=true,
	description="Up to 10 per weapon or armor piece: +2 Damage and +2 Strength (bows +2 Ranged Strength and Accuracy, staves +4 Intelligence), armor +4 Health and +2 Defense."})
item("MasterworkTome",{name="Masterwork Tome",kind="material",rarity="Legendary",color="FFAA00",value=4000,tome=true,
	description="Raises one item's rarity by a tier (once). Higher rarity scales its reforge and an accessory's Magical Power."})
recipe("TemperingTome",{skill="Enchanting",level=20,xp=180,costs={ArcaneDust=96,BeastHide=16,Shard=2},repeatable=true,station="Workbench",category="Tomes"})
Gear.Tomes = {TemperingTome=true,MasterworkTome=true}
Gear.Essences = {"ObservatoryEssence","WildheartEssence","BrinelightEssence"}

-- Drops (appended to existing tables; chances < 1 so guaranteed rolls are unchanged).
-- Starborn Sentinel and Brambleback Boar tables are left untouched (event tests queue their rolls).
local function drop(list, itemId, chance, min, max) table.insert(list, {item=itemId,chance=chance,min=min or 1,max=max or min or 1}) end
local M, SC = Data.Monsters, Data.SeaCreatures
drop(M.CinderMite.drops, "EmberheartCinder", 0.004)
drop(M.TempestWraith.drops, "StarbiteShard", 0.006)
drop(M.GaleSprite.drops, "GalestringCoil", 0.004)
drop(M.StormHarrier.drops, "GalestringCoil", 0.004)
drop(M.VoidWisp.drops, "VoidhymnShard", 0.005)
drop(M.ReefLurker.drops, "CoralplateFragment", 0.004)
drop(M.ShaleCrawler.drops, "DeepveinGeode", 0.003)
drop(M.BrassGolem.drops, "DeepveinGeode", 0.006)
drop(M.TempestWraith.drops, "ResonanceCrystal", 0.003)
drop(M.VoidWisp.drops, "TemperingTome", 0.01)
drop(M.TempestWraith.drops, "TemperingTome", 0.02)
drop(M.TempestWraith.drops, "MasterworkTome", 0.002)
drop(SC.StormcoilSerpent.drops, "UndertowBarb", 0.02)
drop(SC.DuskfinManta.drops, "UndertowBarb", 0.02)
drop(SC.CoralbackBruiser.drops, "CoralplateFragment", 0.03)
drop(SC.InkveilDrifter.drops, "TidepearlKnot", 0.01)
drop(SC.TidewyrmMatriarch.drops, "TidepearlKnot", 0.05)
drop(SC.TidewyrmMatriarch.drops, "MasterworkTome", 0.01)
for index, id in ipairs(Data.SeaCreatureOrder) do
	drop(SC[id].drops, "BrinelightEssence", math.min(0.9, 0.25 + 0.08 * index), 1 + index // 3, 2 + index // 2)
end
local slayerEssence = {{2,4},{5,8},{10,16},{20,30}}
for _, line in ipairs(Data.SlayerOrder) do
	for t, tier in ipairs(Data.Slayers[line].tiers) do
		drop(tier.drops, "WildheartEssence", 0.95, slayerEssence[t][1], slayerEssence[t][2])
		if t >= 2 then drop(tier.drops, "TemperingTome", 0.1 * t) end
		drop(tier.drops, "WardstoneSeal", 0.02 + 0.01 * t)
	end
end
drop(Data.Slayers.Bramble.tiers[3].drops, "EmberheartCinder", 0.05)
drop(Data.Slayers.Bramble.tiers[4].drops, "EmberheartCinder", 0.1)
drop(Data.Slayers.Gloom.tiers[3].drops, "VoidhymnShard", 0.05)
drop(Data.Slayers.Gloom.tiers[4].drops, "VoidhymnShard", 0.1)
drop(Data.Slayers.Tempest.tiers[3].drops, "StarbiteShard", 0.04)
drop(Data.Slayers.Tempest.tiers[4].drops, "StarbiteShard", 0.08)
for _, line in ipairs(Data.SlayerOrder) do
	drop(Data.Slayers[line].tiers[4].drops, "ResonanceCrystal", 0.06)
	drop(Data.Slayers[line].tiers[4].drops, "MasterworkTome", 0.05)
end
local floors = Data.DungeonFloors
drop(floors[2].chest, "StarwovenThread", 0.01)
drop(floors[3].chest, "StarwovenThread", 0.015)
drop(floors[3].chest, "AstralLens", 0.01)
drop(floors[3].chest, "TemperingTome", 0.08)
drop(floors[4].chest, "StarwovenThread", 0.02)
drop(floors[4].chest, "AstralLens", 0.015)
drop(floors[4].chest, "PrismlitLens", 0.01)
drop(floors[4].chest, "TemperingTome", 0.12)
drop(floors[4].chest, "MasterworkTome", 0.01)
drop(floors[5].chest, "AstralLens", 0.02)
drop(floors[5].chest, "PrismlitLens", 0.015)
drop(floors[5].chest, "TemperingTome", 0.2)
drop(floors[5].chest, "MasterworkTome", 0.02)

-- Rules ---------------------------------------------------------------------
local function round1(x) return math.floor(x * 10 + 0.5) / 10 end
local function tab(v) return if type(v) == "table" then v else nil end
local toolSkill = {}
for skill, kind in pairs(Data.ToolKind) do toolSkill[kind] = skill end
-- Upgrade category of an item definition: melee | ranged | magic | armor | tool | accessory | nil.
function Gear.category(def)
	if type(def) ~= "table" then return nil end
	if def.kind == "weapon" then return if def.style == "ranged" or def.style == "magic" then def.style else "melee" end
	if def.kind == "armor" or def.kind == "tool" or def.kind == "accessory" then return def.kind end
	return nil
end
function Gear.categoryOf(itemId) return Gear.category(Data.Items[itemId]) end
function Gear.isWeaponCategory(category) return category == "melee" or category == "ranged" or category == "magic" end
function Gear.canStar(category) return category ~= nil and category ~= "accessory" end
function Gear.canTemper(category) return Gear.Tempering[category] ~= nil end
function Gear.toolSkill(def) return type(def) == "table" and toolSkill[def.toolKind] or nil end
function Gear.reforgeOf(g, itemId)
	local id = tab(g) and tab(g.reforges) and g.reforges[itemId]
	return if type(id) == "string" and Gear.Reforges[id] then id else nil
end
function Gear.starsOf(g, itemId)
	local n = tab(g) and tab(g.stars) and tonumber(g.stars[itemId]) or 0
	if n ~= n then return 0 end
	return math.clamp(math.floor(n), 0, Gear.STAR_MAX)
end
function Gear.bookOf(g, itemId)
	local b = tab(g) and tab(g.books) and tab(g.books[itemId])
	local n = b and tonumber(b.tempering) or 0
	if n ~= n then n = 0 end
	return {tempering=math.clamp(math.floor(n), 0, Gear.TEMPERING_MAX), masterwork=b ~= nil and b.masterwork == true}
end
-- Rarity after a Masterwork Tome (one tier up, capped at Mythic).
function Gear.bumpRarity(rarity)
	local rank = Data.Rarity[rarity] and Data.Rarity[rarity].rank or 1
	return Data.RarityOrder[math.min(#Data.RarityOrder, rank + 1)]
end
function Gear.effectiveRarity(g, itemId)
	local def = Data.Items[itemId]
	if not def then return "Common" end
	if Gear.bookOf(g, itemId).masterwork then return Gear.bumpRarity(def.rarity) end
	return def.rarity
end
-- A reforge's stats at a rarity; tool "fortune" becomes the skill's fortune stat.
function Gear.reforgeStats(reforgeId, rarity, skill)
	local r = Gear.Reforges[reforgeId]
	local out = {}
	if not r then return out end
	local scale = Gear.RarityScale[rarity] or 1
	for stat, v in pairs(r.stats) do
		local key = if stat == "fortune" and skill then Data.FortuneStat[skill] else stat
		out[key] = (out[key] or 0) + round1(v * scale)
	end
	return out
end
function Gear.starPercent(def) return if type(def) == "table" and def.dungeon then Gear.DUNGEON_STAR_PERCENT else Gear.STAR_PERCENT end
function Gear.starStats(def, stars)
	local out = {}
	if type(def) ~= "table" or not def.stats or (stars or 0) <= 0 then return out end
	local pct = Gear.starPercent(def) * stars / 100
	for stat, v in pairs(def.stats) do
		local bonus = round1(v * pct)
		if bonus ~= 0 then out[stat] = bonus end
	end
	return out
end
function Gear.tomeStats(def, count)
	local out = {}
	local per = Gear.Tempering[Gear.category(def)]
	if not per or (count or 0) <= 0 then return out end
	for stat, v in pairs(per) do out[stat] = v * count end
	return out
end
-- Every upgrade layer of an item: {rarity, reforge, reforgeStats, stars, starStats,
-- tempering, tomeStats, masterwork, total}. total is what computeStats adds.
function Gear.breakdown(g, itemId)
	local def = Data.Items[itemId]
	local rarity = Gear.effectiveRarity(g, itemId)
	local book = Gear.bookOf(g, itemId)
	local category = Gear.category(def)
	local reforge = category and Gear.reforgeOf(g, itemId)
	if reforge and Gear.Reforges[reforge].category ~= category then reforge = nil end
	local stars = if Gear.canStar(category) then Gear.starsOf(g, itemId) else 0
	local tempering = if Gear.canTemper(category) then book.tempering else 0
	local out = {rarity=rarity,reforge=reforge,stars=stars,tempering=tempering,masterwork=book.masterwork,
		reforgeStats=if reforge then Gear.reforgeStats(reforge, rarity, Gear.toolSkill(def)) else {},
		starStats=Gear.starStats(def, stars),tomeStats=Gear.tomeStats(def, tempering)}
	local total = {}
	local layers = {out.reforgeStats, out.starStats, out.tomeStats}
	-- Extension layers (Gear.Layers, e.g. Dungeon endgame Master stars): each adds
	-- out[layer.id] = level and out[layer.id.."Stats"] = stats, summed into total.
	for _, layer in ipairs(Gear.Layers) do
		local level, stats = layer.stats(g, itemId, def, out)
		out[layer.id] = level or 0
		out[layer.id .. "Stats"] = stats or {}
		table.insert(layers, out[layer.id .. "Stats"])
	end
	for _, layer in ipairs(layers) do
		for stat, v in pairs(layer) do total[stat] = round1((total[stat] or 0) + v) end
	end
	out.total = total
	return out
end
function Gear.upgradeStats(g, itemId) return Gear.breakdown(g, itemId).total end
function Gear.isUpgraded(g, itemId)
	local book = Gear.bookOf(g, itemId)
	if Gear.reforgeOf(g, itemId) ~= nil or Gear.starsOf(g, itemId) > 0 or book.tempering > 0 or book.masterwork then return true end
	for _, layer in ipairs(Gear.Layers) do if ((layer.stats(g, itemId, Data.Items[itemId], nil)) or 0) > 0 then return true end end
	return false
end
-- "Honed Brass Sword ★★★"
function Gear.displayName(g, itemId)
	local def = Data.Items[itemId]
	local name = def and def.name or tostring(itemId)
	local reforge = Gear.reforgeOf(g, itemId)
	if reforge then name = Gear.Reforges[reforge].name.." "..name end
	local stars = Gear.starsOf(g, itemId)
	if stars > 0 then name ..= " "..string.rep("★", stars) end
	for _, layer in ipairs(Gear.Layers) do
		local level = layer.glyph and (layer.stats(g, itemId, def, nil)) or 0
		if level > 0 then name ..= string.rep(layer.glyph, level) end
	end
	return name
end
function Gear.reforgeCost(g, itemId) return Gear.ReforgeCost[Gear.effectiveRarity(g, itemId)] or Gear.ReforgeCost.Common end
-- Random-roll pool (stones excluded) for an item definition.
function Gear.reforgePool(def)
	local category = Gear.category(def)
	local pool = {}
	for _, id in ipairs(category and Gear.ReforgeOrder[category] or {}) do
		local r = Gear.Reforges[id]
		if not r.stone and (r.toolKinds == nil or table.find(r.toolKinds, def.toolKind) ~= nil) then table.insert(pool, id) end
	end
	return pool
end
function Gear.reforgeFits(reforgeId, def)
	local r = Gear.Reforges[reforgeId]
	return r ~= nil and r.category == Gear.category(def) and (r.toolKinds == nil or table.find(r.toolKinds, def.toolKind) ~= nil)
end
-- roll in [0,1) picks uniformly among the pool minus the current reforge.
function Gear.rollReforge(def, current, roll)
	local pool = {}
	for _, id in ipairs(Gear.reforgePool(def)) do if id ~= current then table.insert(pool, id) end end
	if #pool == 0 then return nil end
	return pool[math.clamp(math.floor((tonumber(roll) or 0) * #pool) + 1, 1, #pool)]
end
-- Essence used to star an item: Observatory gear, rods/tools, everything else.
function Gear.essenceFor(def)
	if type(def) ~= "table" then return nil end
	if def.dungeon then return "ObservatoryEssence" end
	if def.kind == "tool" then return "BrinelightEssence" end
	return "WildheartEssence"
end
-- Cost of star k (1..5): {essence=id, amount=n, coins=c}, by the base rarity.
function Gear.starCost(def, k)
	if type(def) ~= "table" or not Gear.StarEssence[k] then return nil end
	local rank = Data.Rarity[def.rarity] and Data.Rarity[def.rarity].rank or 1
	return {essence=Gear.essenceFor(def),amount=math.floor(Gear.StarEssence[k] * (1 + 0.25 * (rank - 1))),coins=Gear.StarCoins * k * k * rank}
end
end
-- End Gear depth section.

------------------------------------------------------------------------------
-- Garden (Farming Depth team; append-only section).
-- The Verdant Garden: a personal islet beside each home with growing plots
-- (OSRS farming patches + SkyBlock Garden). Pure data and pure rules; the
-- server block "Garden" in server.server.lua runs them with os.time() and the
-- server roll, world.server.lua renders the islet from player attributes and
-- verify-garden.luau checks everything below.
--   * Plots: G.BASE_PLOTS at the start, one more per G.PLOT_LEVELS garden level
--     and per G.PLOT_FARMING Farming level (G.MAX_PLOTS = 12).
--   * Crops grow over real time (works offline): progress seconds accrue at
--     G.rate (1 + compost + watering + Rootwarden set + garden level, capped at
--     G.MAX_RATE); 4 visible stages, ripe crops wait forever.
--   * Disease: rolled when planted (G.diseaseChance, halved by compost); it
--     strikes at a hidden growth fraction unless the crop is treated with a
--     Blightward Salve, halts growth, and kills the crop G.DEATH_SECONDS later.
--   * Pests: each G.PEST_INTERVAL a planted crop may gain a pest (G.PEST_CHANCE,
--     at most G.PEST_MAX_ROLLS rolls per refresh, so offline time is capped);
--     a pest cuts the harvest by G.PEST_PENALTY until cleared.
--   * Harvest: base yield rolled with Farming Fortune (stats + hoe + crop
--     milestone fortune) and Greenward mastery; returns seeds; Farming XP and
--     garden XP; crop milestones (G.MILESTONES x crop scale) pay coins, crop
--     fortune and +1 Farming Fortune each.
--   * Composter (garden level G.COMPOSTER_LEVEL): organic matter becomes
--     Compost every interval and Bloom Dust every G.DUST_EVERY composts.
--   * Visitors arrive every G.VISITOR_INTERVAL up to G.visitorCap(level)
--     (offline arrivals stop at the cap) and trade crops for coins, garden XP,
--     Verdant Marks and rare items; Marks buy the garden shop.
-- Profile: p.garden = {xp, plots = {12 plot tables ({} = empty)}, harvested =
-- {[crop]=n}, milestones = {[crop]=tier paid}, composter = {matter, out, dust,
-- cycles, at, upgrade}, visitors = {visitor...}, nextVisitor, seq, served,
-- skin, skins = {[skin]=true}, fieldSeeds = {[crop]=n}, lastSeed}; bounded (~3 KB).
------------------------------------------------------------------------------
do
local G = {}
Data.Garden = G
G.MARK, G.DUST, G.COMPOST, G.SALVE, G.CHITIN = "VerdantMark", "BloomDust", "Compost", "BlightwardSalve", "PestChitin"
G.MAX_PLOTS, G.BASE_PLOTS = 12, 3
G.PLOT_LEVELS = {2, 3, 5, 7, 9, 12}   -- garden levels that add a plot
G.PLOT_FARMING = {15, 35, 55}          -- Farming levels that add a plot
G.STAGES = 4
G.STAGE_NAMES = {"Sprouting", "Growing", "Budding", "Ripe"}
G.STAGE_SCALE = {0.35, 0.6, 0.85, 1}   -- world crop mesh ShapeScale per stage
G.TICK = 20                            -- server refresh loop (seconds)
G.WATER_SECONDS, G.WATER_BOOST = 1800, 0.20
G.COMPOST_BOOST, G.SET_BOOST, G.LEVEL_BOOST, G.MAX_RATE = 0.25, 0.10, 0.01, 1.6
G.DEATH_SECONDS = 7200
G.COMPOST_CLEANSE = 0.5                -- chance that compost clears a hidden blight
G.PEST_INTERVAL, G.PEST_CHANCE, G.PEST_MAX_ROLLS, G.PEST_PENALTY = 600, 0.06, 6, 0.4
G.PEST_SEED_CHANCE = 0.2
G.SEED_RETURN_CHANCE = 0.8             -- a harvest saves one seed on this roll (net < 1 seed per planting)
G.SEED_BONUS_CHANCE = 0.1              -- garden-only crops (no field seed pouch) may save a second
G.SEED_VALUE_SHARE = 0.2               -- seeds sell for this share of the crop value (never a coin source)
G.FIELD_SEED_EVERY = 20                -- every Nth field harvest of a crop bundles one seed
G.VISITOR_INTERVAL = 900
G.COMPOSTER_LEVEL = 2
G.COMPOST_MATTER, G.COMPOST_SECONDS, G.DUST_EVERY = 60, 600, 4
G.COMPOST_OUT_CAP, G.MATTER_CAP = 64, 4000
G.MILESTONES = {100, 300, 750, 1500, 3000, 6000, 12000, 25000, 50000}
G.MILESTONE_CROP_FORTUNE = 4           -- garden fortune for that crop per tier
G.MILESTONE_FORTUNE = 1                -- Farming Fortune everywhere per tier (perk)
G.LEVEL_XP = {0, 60, 180, 400, 750, 1250, 2000, 3000, 4400, 6200, 8500, 11500, 15500, 20500, 27000}
G.MAX_LEVEL = #G.LEVEL_XP
G.SET = "Rootwarden"

-- Crops: id = harvested item, seed = planted item, level = Farming level,
-- grow = seconds at rate 1, yield = base harvest before fortune, xp = Farming
-- XP per harvest, gxp = garden XP, disease = base blight chance,
-- shape/tint = world crop mesh, scale = milestone threshold multiplier.
-- Ladder (base rate, no fortune): Farming XP per grow-second and coins per
-- plot-hour (yield x value x 3600 / grow) both climb >= 1.1x per tier, and
-- every plot at G.MAX_RATE on the top crop stays under top field Farming XP/h
-- (G.xpPerSecond, G.coinsPerHour; verify-garden.luau checks both).
G.Crops = {
	{id="Herb",seed="MeadowSeeds",seedName="Meadow Herb Seeds",level=1,grow=300,yield=6,xp=50,gxp=4,disease=0.06,shape="CropBush",tint="6BBF59",scale=1},
	{id="Sunwheat",seed="SunwheatSeeds",seedName="Sunwheat Seeds",level=15,grow=600,yield=4,xp=115,gxp=8,disease=0.08,shape="CropWheat",tint="E9C46A",scale=1},
	{id="Duskberry",seed="DuskberrySeeds",seedName="Duskberry Seeds",level=22,grow=1200,yield=6,xp=260,gxp=13,disease=0.10,shape="CropBush",tint="7A4E9E",scale=0.8},
	{id="Glowcap",seed="GlowcapSpores",seedName="Glowcap Spores",level=30,grow=1800,yield=8,xp=440,gxp=18,disease=0.11,shape="CropGlowcap",tint="F4A261",scale=0.7},
	{id="Moonbloom",seed="MoonbloomBulb",seedName="Moonbloom Bulb",level=45,grow=3600,yield=11,xp=1000,gxp=30,disease=0.13,shape="CropBloom",tint="B8C0FF",scale=0.5},
	{id="Cloudgourd",seed="CloudgourdSeeds",seedName="Cloudgourd Seeds",level=52,grow=5400,yield=14,xp=1700,gxp=40,disease=0.14,shape="CropGlowcap",tint="D9ECF7",scale=0.45},
	{id="Starfruit",seed="StarfruitPit",seedName="Starfruit Pit",level=60,grow=7200,yield=16,xp=2560,gxp=55,disease=0.16,shape="CropBush",tint="FFE66D",scale=0.35},
	{id="AetherLotus",seed="LotusBud",seedName="Aether Lotus Bud",level=75,grow=14400,yield=22,xp=5800,gxp=90,disease=0.18,shape="CropBloom",tint="FF9ECD",scale=0.25},
}
G.CropById, G.CropBySeed = {}, {}
-- Garden-only crops (no field nodes): Duskberry and Cloudgourd.
item("Duskberry",{name="Duskberry",kind="resource",skill="Farming",tier=3,rarity="Uncommon",color="7A4E9E",value=14,description="A dusk-dark berry grown only in the Verdant Garden."})
item("Cloudgourd",{name="Cloudgourd",kind="resource",skill="Farming",tier=5,rarity="Rare",color="D9ECF7",value=40,description="A feather-light gourd grown only in the Verdant Garden."})
for i, c in ipairs(G.Crops) do
	c.index = i
	c.exclusive = Data.ResourceSkill[c.id] == nil   -- garden-only: no field nodes, no seed pouch
	G.CropById[c.id] = c
	G.CropBySeed[c.seed] = c
	local def = Data.Items[c.id]
	item(c.seed,{name=c.seedName,kind="resource",skill="Farming",category="seed",crop=c.id,tier=i,rarity=def.rarity,color=c.tint,value=math.floor(def.value*G.SEED_VALUE_SHARE),
		description="Plant in a Verdant Garden plot (Farming "..c.level.."). Ripens in "..(if c.grow>=3600 then (c.grow//3600).." h" else (c.grow//60).." min").."."})
end

-- Garden materials, treatment and currency.
item(G.MARK,{name="Verdant Mark",kind="material",rarity="Uncommon",color="5FBF77",value=20,description="Token of a satisfied garden visitor. Spent at the Verdant Garden shop."})
item(G.DUST,{name="Bloom Dust",kind="material",rarity="Rare",color="F7B2D9",value=45,description="Glittering residue from the composter. Upgrades the composter and garden gear."})
item(G.COMPOST,{name="Rich Compost",kind="material",category="fertiliser",rarity="Common",color="6B4F33",value=6,description="Fertilise a plot: +25% growth speed and a chance to purge blight."})
item(G.SALVE,{name="Blightward Salve",kind="material",category="treatment",rarity="Uncommon",color="9FD8A6",value=18,description="Treat a plot: cures blight and keeps the crop immune until harvest."})
item(G.CHITIN,{name="Pest Chitin",kind="material",rarity="Common",color="8C6A4A",value=5,description="Shell of a garden pest. Rich composter matter."})
recipe(G.SALVE,{skill="Alchemy",level=12,xp=40,costs={Herb=4,Sunwheat=2},amount=2,repeatable=true,station="Cauldron",category="Garden"})
-- Cooking and Alchemy use the garden-only crops.
item("DuskberryTart",{name="Duskberry Tart",kind="consumable",category="food",rarity="Uncommon",color="7A4E9E",heal=220,recovery=4,value=40,requires={Cooking=25},description="Restore up to 220 health."})
recipe("DuskberryTart",{skill="Cooking",level=25,xp=70,costs={Duskberry=3,Sunwheat=2},repeatable=true,station="Hearth",category="Meals"})
item("CloudgourdBroth",{name="Cloudgourd Broth",kind="consumable",category="buff",rarity="Rare",color="D9ECF7",buff={stats={farmingFortune=40,health=40},duration=600},value=120,description="+40 Farming Fortune, +40 Health for 10 minutes."})
recipe("CloudgourdBroth",{skill="Cooking",level=50,xp=180,costs={Cloudgourd=3,Moonbloom=1},repeatable=true,station="Hearth",category="Feasts"})
item("VerdantElixir",{name="Verdant Elixir",kind="consumable",category="potion",rarity="Rare",color="5FBF77",buff={stats={farmingFortune=80},duration=600},value=140,requires={Alchemy=48},description="Potion: 10 minute buff. +80 Farming Fortune."})
recipe("VerdantElixir",{skill="Alchemy",level=48,xp=150,costs={Duskberry=3,Cloudgourd=2},repeatable=true,station="Cauldron",category="Potions"})

-- Garden gear (shop only): hoes upgrade in place, the Rootwarden set, a charm.
item("SproutwoodHoe",{name="Sproutwood Hoe",kind="tool",toolKind="Hoe",slot="hoe",toolTier=2,tier=2,rarity="Uncommon",color="8DBF5A",stats={farmingFortune=45},requires={Farming=15},value=400,description="Tier 2 hoe from the Verdant Garden shop. Requires Farming 15."})
item("GreenwardHoe",{name="Greenward Hoe",kind="tool",toolKind="Hoe",slot="hoe",toolTier=4,tier=4,rarity="Rare",color="4FA36B",stats={farmingFortune=100},requires={Farming=40},value=1600,description="Tier 4 hoe; upgrades the Sproutwood Hoe. Requires Farming 40."})
item("EverbloomHoe",{name="Everbloom Hoe",kind="tool",toolKind="Hoe",slot="hoe",toolTier=6,tier=6,rarity="Epic",color="F7B2D9",stats={farmingFortune=170},requires={Farming=70},value=5200,description="Tier 6 hoe; upgrades the Greenward Hoe. Requires Farming 70."})
Data.Sets[G.SET] = {id=G.SET,name="Rootwarden",pieces={},bonus={farmingFortune=40,health=30},text="+40 Farming Fortune, +30 Health; garden crops grow 10% faster",color="6F9E4B"}
G.Armor = {
	{id="RootwardenHat",slot="helmet",name="Rootwarden Hat",stats={farmingFortune=10,health=10},marks=25,level=4},
	{id="RootwardenVest",slot="chest",name="Rootwarden Vest",stats={farmingFortune=15,health=20},marks=40,level=5},
	{id="RootwardenTrousers",slot="legs",name="Rootwarden Trousers",stats={farmingFortune=12,health=15},marks=35,level=5},
	{id="RootwardenClogs",slot="boots",name="Rootwarden Clogs",stats={farmingFortune=8,health=10},marks=25,level=4},
}
for _, a in ipairs(G.Armor) do
	item(a.id,{name=a.name,kind="armor",slot=a.slot,set=G.SET,tier=2,rarity="Rare",color="6F9E4B",stats=a.stats,requires={Farming=10},value=a.marks*20,
		description="Part of the Rootwarden set (Verdant Garden shop). Requires Farming 10."})
	table.insert(Data.Sets[G.SET].pieces, a.id)
end
item("VerdantCharm",{name="Verdant Charm",kind="accessory",rarity="Rare",color=Data.Rarity.Rare.color,stats={farmingFortune=15,health=10},value=40*Data.Rarity.Rare.rank^2,description="Accessory. Magical Power "..Data.Rarity.Rare.power..". Verdant Garden shop."})

-- Plot skins: frame and soil colours (cosmetic; "Loam" is free).
G.Skins = {
	{id="Loam",name="Tilled Loam",frame="966B4C",soil="4A3526"},
	{id="Mossbed",name="Mossbed",frame="5E8C4A",soil="3E4A2C"},
	{id="Terracotta",name="Terracotta",frame="C46A44",soil="5A3A28"},
	{id="Emberbrick",name="Emberbrick",frame="8E3B2E",soil="3B2622"},
	{id="Starlit",name="Starlit",frame="3B4C7A",soil="262B44"},
}
G.SkinById = {}
for i, s in ipairs(G.Skins) do s.index = i; G.SkinById[s.id] = s end

-- Garden shop: kind "item" (amount per purchase; unique = one owned at most;
-- upgrade = item consumed) or "skin". level = garden level.
G.Shop = {
	{id="MeadowSeeds",kind="item",item="MeadowSeeds",amount=4,cost={coins=20},level=1},
	{id="SunwheatSeeds",kind="item",item="SunwheatSeeds",amount=4,cost={coins=60},level=1},
	{id="DuskberrySeeds",kind="item",item="DuskberrySeeds",amount=3,cost={coins=120},level=2},
	{id="GlowcapSpores",kind="item",item="GlowcapSpores",amount=3,cost={coins=180},level=3},
	{id="MoonbloomBulb",kind="item",item="MoonbloomBulb",amount=2,cost={coins=300,VerdantMark=1},level=4},
	{id="CloudgourdSeeds",kind="item",item="CloudgourdSeeds",amount=2,cost={coins=450,VerdantMark=2},level=5},
	{id="StarfruitPit",kind="item",item="StarfruitPit",amount=2,cost={coins=700,VerdantMark=3},level=6},
	{id="LotusBud",kind="item",item="LotusBud",amount=1,cost={coins=900,VerdantMark=5},level=8},
	{id="Compost",kind="item",item="Compost",amount=3,cost={VerdantMark=2},level=1},
	{id="BlightwardSalve",kind="item",item="BlightwardSalve",amount=2,cost={VerdantMark=3},level=2},
	{id="SproutwoodHoe",kind="item",item="SproutwoodHoe",amount=1,cost={VerdantMark=30,BloomDust=4},level=3,unique=true},
	{id="GreenwardHoe",kind="item",item="GreenwardHoe",amount=1,cost={VerdantMark=90,BloomDust=16},level=7,unique=true,upgrade="SproutwoodHoe"},
	{id="EverbloomHoe",kind="item",item="EverbloomHoe",amount=1,cost={VerdantMark=220,BloomDust=48},level=11,unique=true,upgrade="GreenwardHoe"},
	{id="VerdantCharm",kind="item",item="VerdantCharm",amount=1,cost={VerdantMark=60,BloomDust=10},level=6,unique=true},
	{id="SkinMossbed",kind="skin",skin="Mossbed",cost={VerdantMark=15},level=2},
	{id="SkinTerracotta",kind="skin",skin="Terracotta",cost={VerdantMark=25},level=4},
	{id="SkinEmberbrick",kind="skin",skin="Emberbrick",cost={VerdantMark=40,BloomDust=8},level=7},
	{id="SkinStarlit",kind="skin",skin="Starlit",cost={VerdantMark=80,BloomDust=20},level=10},
}
for _, a in ipairs(G.Armor) do
	table.insert(G.Shop, {id=a.id,kind="item",item=a.id,amount=1,cost={VerdantMark=a.marks},level=a.level,unique=true})
end
G.ShopById = {}
for i, e in ipairs(G.Shop) do e.index = i; G.ShopById[e.id] = e end
-- Seeds whose shop entry costs Verdant Marks: never auto-planted unless chosen.
G.MarkSeeds = {}
for _, c in ipairs(G.Crops) do
	local e = G.ShopById[c.seed]
	if e and e.cost.VerdantMark then G.MarkSeeds[c.seed] = true end
end

-- Composter: matter per fed item, upgrades (interval -12% and +1500 matter each).
G.ORGANIC_EXTRA = {BeastHide=4, PestChitin=12, Timber=1, WindpineLog=2}
function G.organic(itemId)
	local c = G.CropById[itemId]
	if c then return math.max(2, Data.Items[itemId].value) end
	return G.ORGANIC_EXTRA[itemId] or 0
end
G.ComposterUpgrades = {
	{dust=4,marks=8},{dust=10,marks=20},{dust=20,marks=40},{dust=36,marks=70},{dust=60,marks=120},
}
function G.composterInterval(upgrade) return math.floor(G.COMPOST_SECONDS * (1 - 0.12 * math.clamp(upgrade or 0, 0, #G.ComposterUpgrades))) end
function G.matterCap(upgrade) return G.MATTER_CAP + 1500 * math.clamp(upgrade or 0, 0, #G.ComposterUpgrades) end

-- Pests (a light combat link): clearing one pays Combat and Farming XP.
G.Pests = {
	{id="Leafnibbler",name="Leafnibbler",color="8BC34A",combatXp=12},
	{id="Rootgrub",name="Rootgrub",color="8D6346",combatXp=16},
	{id="Dustmoth",name="Dustmoth",color="B8A27A",combatXp=20},
	{id="Thripling",name="Thripling",color="C8553D",combatXp=24},
}

-- Visitors: rarity sets the pick weight, reward multiplier and Verdant Marks.
G.VisitorRarity = {
	Common={weight=60,mult=1,marks=2,rank=1},Uncommon={weight=27,mult=1.4,marks=4,rank=2},
	Rare={weight=11,mult=2,marks=7,rank=3},Legendary={weight=2,mult=3,marks=14,rank=4},
}
G.Visitors = {
	{id="Pell",name="Pell the Thatcher",rarity="Common",level=1,color="C9A227",likes={"Herb","Sunwheat"},line="My roof wants patching and my belly wants bread."},
	{id="Odessa",name="Odessa Brightloam",rarity="Common",level=1,color="9BD77E",likes={"Sunwheat","Duskberry"},line="I judge a garden by its rows. Yours will do."},
	{id="Bramwick",name="Bramwick Furrowfoot",rarity="Common",level=1,color="8D6346",likes={"Herb","Glowcap"},line="Walked all the way from Meadow Reach for this."},
	{id="Tamsin",name="Tamsin of the Quay Kitchens",rarity="Uncommon",level=2,color="D9822B",likes={"Glowcap","Moonbloom"},line="The quay stew needs something brighter."},
	{id="Corvel",name="Corvel Ledgerleaf",rarity="Uncommon",level=3,color="4FB0C6",likes={"Duskberry","Cloudgourd"},line="I pay fairly, and I always pay in Marks."},
	{id="Mirabel",name="Mirabel Skyhive",rarity="Uncommon",level=4,color="F2C14E",likes={"Moonbloom","Starfruit"},line="My bees adore a moonlit bloom."},
	{id="Gideon",name="Gideon Tidewell",rarity="Rare",level=5,color="3F7CAC",likes={"Cloudgourd","Starfruit"},line="Sailors swear by gourd broth before a storm."},
	{id="Sefa",name="Sefa the Lanternkeeper",rarity="Rare",level=6,color="FFD166",likes={"Glowcap","AetherLotus"},line="Glowcaps light the long watch."},
	{id="Quillon",name="Archivist Quillon",rarity="Rare",level=8,color="8E5BB5",likes={"Moonbloom","AetherLotus"},line="For the herbarium. Pressed, catalogued, adored."},
	{id="Auralie",name="Auralie Dawnpetal",rarity="Legendary",level=10,color="FF9ECD",likes={"AetherLotus","Starfruit"},line="The isles bloom where you walk, gardener."},
}
G.VisitorById = {}
for i, v in ipairs(G.Visitors) do v.index = i; G.VisitorById[v.id] = v end
G.MAX_VISITORS = 5
function G.visitorCap(level) return math.min(G.MAX_VISITORS, 2 + math.floor((math.max(1, level or 1) - 1) / 4)) end

------------------------------------------------------------------------------
-- Pure rules.
------------------------------------------------------------------------------
function G.level(xp)
	xp = tonumber(xp) or 0
	local lvl = 1
	for i, need in ipairs(G.LEVEL_XP) do if xp >= need then lvl = i end end
	return lvl
end
-- level, xp at this level's start, xp for the next level (nil at max).
function G.progress(xp)
	local lvl = G.level(xp)
	return lvl, G.LEVEL_XP[lvl], G.LEVEL_XP[lvl + 1]
end
function G.plotCount(gardenLevel, farmingLevel)
	local n = G.BASE_PLOTS
	for _, l in ipairs(G.PLOT_LEVELS) do if (gardenLevel or 1) >= l then n += 1 end end
	for _, l in ipairs(G.PLOT_FARMING) do if (farmingLevel or 1) >= l then n += 1 end end
	return math.min(G.MAX_PLOTS, n)
end
-- Text for the next plot unlock ("Garden level 5" / "Farming 35"), nil when all are open.
function G.nextPlotUnlock(gardenLevel, farmingLevel)
	local nextGarden, nextFarming
	for _, l in ipairs(G.PLOT_LEVELS) do if (gardenLevel or 1) < l then nextGarden = l; break end end
	for _, l in ipairs(G.PLOT_FARMING) do if (farmingLevel or 1) < l then nextFarming = l; break end end
	local parts = {}
	if nextGarden then table.insert(parts, "Garden level "..nextGarden) end
	if nextFarming then table.insert(parts, "Farming "..nextFarming) end
	return if #parts > 0 then table.concat(parts, " or ") else nil
end
function G.milestoneThreshold(cropId, tier)
	local c = G.CropById[cropId]
	local base = G.MILESTONES[tier]
	if not c or not base then return nil end
	return math.max(5, math.floor(base * c.scale / 5 + 0.5) * 5)
end
function G.milestoneTier(cropId, harvested)
	local tier = 0
	for t = 1, #G.MILESTONES do
		local need = G.milestoneThreshold(cropId, t)
		if need and (harvested or 0) >= need then tier = t end
	end
	return tier
end
function G.milestoneReward(cropId, tier)
	local c = G.CropById[cropId]
	if not c or tier < 1 then return {coins=0,gxp=0} end
	return {coins=math.floor(150 * tier * tier * (1 + 0.2 * (c.index - 1))),gxp=15 * tier}
end
-- Total milestone tiers across crops (each grants G.MILESTONE_FORTUNE Farming Fortune).
function G.milestonePerk(harvested)
	local tiers = 0
	for _, c in ipairs(G.Crops) do tiers += G.milestoneTier(c.id, type(harvested) == "table" and harvested[c.id] or 0) end
	return if tiers > 0 then {farmingFortune=tiers * G.MILESTONE_FORTUNE} else nil, tiers
end
-- Growth rate: ctx = {level = garden level, set = Rootwarden set active}.
function G.rate(plot, ctx, watered)
	ctx = ctx or {}
	local r = 1 + (plot.compost and G.COMPOST_BOOST or 0) + (ctx.set and G.SET_BOOST or 0)
		+ G.LEVEL_BOOST * (math.clamp(ctx.level or 1, 1, G.MAX_LEVEL) - 1) + (watered and G.WATER_BOOST or 0)
	return math.min(G.MAX_RATE, r)
end
function G.diseaseChance(crop, composted)
	local c = type(crop) == "table" and crop or G.CropById[crop]
	if not c then return 0 end
	return c.disease * (if composted then 0.5 else 1)
end
-- A new crop in `plot` (mutated). Rolls disease unless pre-treated. Returns plot.
function G.plant(plot, cropId, now, roll)
	local c = G.CropById[cropId]
	plot.crop, plot.planted, plot.at, plot.grown = cropId, now, now, 0
	plot.sick, plot.dead, plot.pest, plot.blight, plot.water = nil, nil, nil, nil, nil
	plot.pestCheck = now
	if not plot.treated and roll() < G.diseaseChance(c, plot.compost) then
		plot.blight = math.floor((0.2 + 0.6 * roll()) * 1000) / 1000
	end
	return plot
end
-- Advance growth to `now` (offline-safe). Watering boosts only until it
-- expires; disease strikes at blight * grow seconds and halts growth; a sick
-- crop dies DEATH_SECONDS after the strike.
function G.advance(plot, now, ctx)
	local c = plot and G.CropById[plot.crop]
	if not c then return plot end
	local t = plot.at or now
	if now <= t then return plot end
	if not plot.dead and not plot.sick then
		local need = c.grow
		local strike = if plot.blight and not plot.treated then plot.blight * need else nil
		local function run(untilT, watered)
			if untilT <= t then return end
			if plot.sick or plot.grown >= need then t = untilT return end
			local rate = G.rate(plot, ctx, watered)
			local target = plot.grown + (untilT - t) * rate
			if strike and plot.grown < strike and target >= strike then
				plot.sick = math.ceil(t + (strike - plot.grown) / rate)
				plot.grown = strike
			else
				plot.grown = math.min(need, target)
			end
			t = untilT
		end
		if (plot.water or 0) > t then run(math.min(now, plot.water), true) end
		run(now, false)
	end
	if plot.sick and not plot.dead and now - plot.sick >= G.DEATH_SECONDS then plot.dead = true end
	plot.at = now
	return plot
end
function G.ripe(plot)
	local c = plot and G.CropById[plot.crop]
	return c ~= nil and not plot.dead and not plot.sick and (plot.grown or 0) >= c.grow
end
-- 0 empty, 1-3 growing, 4 ripe.
function G.stage(plot)
	local c = plot and G.CropById[plot.crop]
	if not c then return 0 end
	if (plot.grown or 0) >= c.grow then return G.STAGES end
	return math.clamp(1 + math.floor(3 * (plot.grown or 0) / c.grow), 1, 3)
end
-- Seconds until ripe at the current rates (0 ripe; nil sick, dead or empty).
function G.timeLeft(plot, now, ctx)
	local c = plot and G.CropById[plot.crop]
	if not c or plot.dead or plot.sick then return nil end
	local remain = c.grow - (plot.grown or 0)
	if remain <= 0 then return 0 end
	local dry = G.rate(plot, ctx, false)
	local wet = G.rate(plot, ctx, true)
	local window = math.max(0, (plot.water or 0) - now)
	if window * wet >= remain then return math.ceil(remain / wet) end
	return math.ceil(window + (remain - window * wet) / dry)
end
-- Pest rolls for the time since plot.pestCheck (capped). Returns true when a pest arrived.
function G.pestRoll(plot, now, roll)
	if not (plot and G.CropById[plot.crop]) or plot.dead then return false end
	plot.pestCheck = plot.pestCheck or now
	local rolls = math.floor((now - plot.pestCheck) / G.PEST_INTERVAL)
	if rolls <= 0 then return false end
	plot.pestCheck += rolls * G.PEST_INTERVAL
	if plot.pest then return false end
	for _ = 1, math.min(rolls, G.PEST_MAX_ROLLS) do
		if roll() < G.PEST_CHANCE then
			plot.pest = math.clamp(math.floor(roll() * #G.Pests) + 1, 1, #G.Pests)
			return true
		end
	end
	return false
end
-- Harvest amount after fortune and pests: base yield (x mult, the mastery
-- Twin/Bountiful proc or surge, joined before fortune as in field gathering)
-- rolled with fortune (every 100 = +1 guaranteed base, remainder a chance),
-- then pest penalty.
function G.yieldFor(cropId, fortune, pest, roll, mult)
	local c = G.CropById[cropId]
	if not c then return 0 end
	fortune = math.max(0, fortune or 0)
	local base = math.floor(c.yield * math.max(1, tonumber(mult) or 1))
	local amount = base * (1 + math.floor(fortune / 100))
	if roll() < (fortune % 100) / 100 then amount += base end
	if pest then amount = math.max(1, math.floor(amount * (1 - G.PEST_PENALTY))) end
	return amount
end
-- Seeds saved by one harvest: 1 on a G.SEED_RETURN_CHANCE roll, plus (garden-
-- only crops) a G.SEED_BONUS_CHANCE second. Expected < 1, so seeds are a
-- consumable topped up by pests, visitors, the field seed pouch and the shop.
function G.seedReturn(crop, roll)
	local c = type(crop) == "table" and crop or G.CropById[crop]
	if not c then return 0 end
	local n = if roll() < G.SEED_RETURN_CHANCE then 1 else 0
	if c.exclusive and roll() < G.SEED_BONUS_CHANCE then n += 1 end
	return n
end
function G.expectedSeeds(crop)
	local c = type(crop) == "table" and crop or G.CropById[crop]
	if not c then return 0 end
	return G.SEED_RETURN_CHANCE + (if c.exclusive then G.SEED_BONUS_CHANCE else 0)
end
-- Base-rate ladder metrics (rate 1, no fortune).
function G.xpPerSecond(c) return c.xp / c.grow end
function G.coinsPerHour(c) return c.yield * Data.Items[c.id].value * 3600 / c.grow end
-- The seed a contextual "Plant" uses: the last seed the player chose (if
-- owned and allowed), else the cheapest owned seed that is not bought with
-- Verdant Marks. Returns the crop or nil.
function G.autoSeed(items, farmingLevel, lastSeed)
	items = type(items) == "table" and items or {}
	local function usable(c) return c ~= nil and (tonumber(items[c.seed]) or 0) >= 1 and (farmingLevel or 1) >= c.level end
	local last = type(lastSeed) == "string" and G.CropBySeed[lastSeed] or nil
	if usable(last) then return last end
	for _, c in ipairs(G.Crops) do   -- crops are listed cheapest seed first
		if usable(c) and not G.MarkSeeds[c.seed] then return c end
	end
	return nil
end
-- Composter: run whole cycles up to now. Idle time (no matter, output full) is not banked.
-- c = {matter, out, dust, cycles, at, upgrade}. Returns cycles run.
function G.composterAdvance(c, now)
	local interval = G.composterInterval(c.upgrade)
	c.at = c.at or now
	if now <= c.at then return 0 end
	local byTime = math.floor((now - c.at) / interval)
	local byMatter = math.floor((c.matter or 0) / G.COMPOST_MATTER)
	local bySpace = math.max(0, G.COMPOST_OUT_CAP - (c.out or 0))
	local n = math.min(byTime, byMatter, bySpace)
	local before = c.cycles or 0
	c.matter = (c.matter or 0) - n * G.COMPOST_MATTER
	c.out = (c.out or 0) + n
	c.cycles = before + n
	c.dust = (c.dust or 0) + (math.floor(c.cycles / G.DUST_EVERY) - math.floor(before / G.DUST_EVERY))
	if n < byTime then c.at = now else c.at += n * interval end
	return n
end
-- Visitor arrivals: returns how many arrive and the next arrival time. A full
-- queue never banks time (offline arrivals stop at the cap).
function G.visitorsDue(nextAt, now, have, cap)
	nextAt = nextAt or now
	local n = 0
	while nextAt <= now and have + n < cap do
		n += 1
		nextAt += G.VISITOR_INTERVAL
	end
	if have + n >= cap and nextAt <= now then nextAt = now + G.VISITOR_INTERVAL end
	return n, nextAt
end
-- One visitor request (deterministic for a roll sequence). Roll order: pick,
-- second want (Uncommon+), per want {liked?, crop, count}, dust (Uncommon+),
-- seeds (Rare+), pet (Legendary).
function G.makeVisitor(seq, gardenLevel, farmingLevel, roll)
	local eligible, total = {}, 0
	for _, v in ipairs(G.Visitors) do
		if v.level <= (gardenLevel or 1) then table.insert(eligible, v); total += G.VisitorRarity[v.rarity].weight end
	end
	local pick, r = eligible[1], roll() * total
	for _, v in ipairs(eligible) do
		r -= G.VisitorRarity[v.rarity].weight
		if r < 0 then pick = v; break end
	end
	local rar = G.VisitorRarity[pick.rarity]
	local available = {}
	for _, c in ipairs(G.Crops) do if c.level <= (farmingLevel or 1) then table.insert(available, c) end end
	local wantsCount = if rar.rank >= 2 and roll() < 0.5 then 2 else 1
	wantsCount = math.min(wantsCount, #available)
	local wants, list, coins, gxp, xp, top = {}, {}, 0, 0, 0, 1
	for _ = 1, wantsCount do
		local pool = {}
		local liked = roll() < 0.7
		if liked then
			for _, id in ipairs(pick.likes) do
				local c = G.CropById[id]
				if c.level <= (farmingLevel or 1) and not wants[id] then table.insert(pool, c) end
			end
		end
		if #pool == 0 then
			for _, c in ipairs(available) do if not wants[c.id] then table.insert(pool, c) end end
		end
		local c = pool[math.clamp(math.floor(roll() * #pool) + 1, 1, #pool)]
		local n = math.max(2, math.floor(c.yield * (1.5 + 3 * roll()) * math.sqrt(rar.mult)))
		wants[c.id] = n
		table.insert(list, c.id)
		coins += Data.Items[c.id].value * n
		xp += c.xp * n / c.yield
		gxp += 3 * c.index
		top = math.max(top, c.index)
	end
	table.sort(list, function(a, b) return G.CropById[a].index < G.CropById[b].index end)
	local items = {}
	if rar.rank >= 2 and roll() < 0.35 then items[G.DUST] = rar.rank - 1 end
	if rar.rank >= 3 and roll() < 0.4 then
		local seedCrop = G.Crops[math.min(#G.Crops, top + 1)]
		items[seedCrop.seed] = 2
	end
	if rar.rank >= 4 and roll() < 0.1 then items.MossbackPet = 1 end
	return {id=seq,npc=pick.id,wants=wants,order=list,coins=math.floor(coins * 2 * rar.mult),marks=rar.marks + math.floor(top / 3),
		gxp=math.floor((6 + gxp) * rar.mult),xp=math.floor(xp * 0.25),items=items}
end
-- Fresh, empty record.
function G.fresh(now)
	local plots = {}
	for i = 1, G.MAX_PLOTS do plots[i] = {} end
	return {xp=0,plots=plots,harvested={},milestones={},composter={matter=0,out=0,dust=0,cycles=0,at=now or 0,upgrade=0},
		visitors={},nextVisitor=(now or 0) + 60,seq=0,served=0,skin="Loam",skins={Loam=true},fieldSeeds={}}
end
-- Sanitise a saved record (unknown ids dropped, numbers clamped, sizes bounded).
function G.sanitize(g, now)
	local out = G.fresh(now)
	if type(g) ~= "table" then return out end
	local function n(v, lo, hi) v = tonumber(v); if not v or v ~= v then return nil end return math.clamp(v, lo, hi) end
	out.xp = math.floor(n(g.xp, 0, 1e9) or 0)
	if type(g.plots) == "table" then
		for i = 1, G.MAX_PLOTS do
			local s = g.plots[i]
			if type(s) == "table" then
				local plot = {}
				if type(s.crop) == "string" and G.CropById[s.crop] then
					local c = G.CropById[s.crop]
					plot.crop = s.crop
					plot.planted = n(s.planted, 0, 4e9) or now
					plot.at = math.min(n(s.at, 0, 4e9) or now, now)
					plot.grown = n(s.grown, 0, c.grow) or 0
					plot.water = n(s.water, 0, now + G.WATER_SECONDS)
					plot.blight = n(s.blight, 0.05, 0.95)
					plot.sick = n(s.sick, 0, now)
					plot.dead = if s.dead == true then true else nil
					plot.pest = n(s.pest, 1, #G.Pests)
					if plot.pest then plot.pest = math.floor(plot.pest) end
					plot.pestCheck = math.min(n(s.pestCheck, 0, 4e9) or now, now)
				end
				plot.compost = if s.compost == true then true else nil
				plot.treated = if s.treated == true then true else nil
				out.plots[i] = plot
			end
		end
	end
	for _, key in ipairs({"harvested","fieldSeeds"}) do
		if type(g[key]) == "table" then
			for id, v in pairs(g[key]) do
				local x = n(v, 0, 1e9)
				if type(id) == "string" and G.CropById[id] and x then out[key][id] = math.floor(x) end
			end
		end
	end
	if type(g.milestones) == "table" then
		for id, v in pairs(g.milestones) do
			local x = n(v, 0, #G.MILESTONES)
			if type(id) == "string" and G.CropById[id] and x then out.milestones[id] = math.floor(x) end
		end
	end
	local c = type(g.composter) == "table" and g.composter or {}
	local up = math.floor(n(c.upgrade, 0, #G.ComposterUpgrades) or 0)
	out.composter = {upgrade=up,matter=math.floor(n(c.matter, 0, G.matterCap(up)) or 0),out=math.floor(n(c.out, 0, G.COMPOST_OUT_CAP) or 0),
		dust=math.floor(n(c.dust, 0, 1e6) or 0),cycles=math.floor(n(c.cycles, 0, 1e9) or 0),at=math.min(n(c.at, 0, 4e9) or now, now)}
	if type(g.visitors) == "table" then
		for _, v in ipairs(g.visitors) do
			if #out.visitors >= G.MAX_VISITORS then break end
			if type(v) == "table" and type(v.npc) == "string" and G.VisitorById[v.npc] and type(v.wants) == "table" and n(v.id, 1, 1e9) then
				local wants, order = {}, {}
				for id, x in pairs(v.wants) do
					x = n(x, 1, 10000)
					if type(id) == "string" and G.CropById[id] and x and #order < 2 then wants[id] = math.floor(x); table.insert(order, id) end
				end
				table.sort(order, function(a, b) return G.CropById[a].index < G.CropById[b].index end)
				local items = {}
				if type(v.items) == "table" then
					for id, x in pairs(v.items) do
						x = n(x, 1, 100)
						if type(id) == "string" and Data.Items[id] and x then items[id] = math.floor(x) end
					end
				end
				if #order > 0 then
					table.insert(out.visitors, {id=math.floor(v.id),npc=v.npc,wants=wants,order=order,coins=math.floor(n(v.coins, 0, 1e7) or 0),
						marks=math.floor(n(v.marks, 0, 100) or 0),gxp=math.floor(n(v.gxp, 0, 1e5) or 0),xp=math.floor(n(v.xp, 0, 1e6) or 0),items=items})
				end
			end
		end
	end
	out.seq = math.floor(n(g.seq, 0, 1e9) or 0)
	for _, v in ipairs(out.visitors) do out.seq = math.max(out.seq, v.id) end
	out.nextVisitor = n(g.nextVisitor, 0, now + G.VISITOR_INTERVAL) or out.nextVisitor
	out.served = math.floor(n(g.served, 0, 1e9) or 0)
	if type(g.skins) == "table" then
		for id, v in pairs(g.skins) do if v == true and type(id) == "string" and G.SkinById[id] then out.skins[id] = true end end
	end
	out.skin = if type(g.skin) == "string" and out.skins[g.skin] then g.skin else "Loam"
	out.lastSeed = if type(g.lastSeed) == "string" and G.CropBySeed[g.lastSeed] then g.lastSeed else nil
	return out
end
end
-- End Garden section.

------------------------------------------------------------------------------
-- Endgame (Endgame team; append-only section).
-- The Shattered Crown: a gated archipelago of crown-shard islets above the
-- Tempest Spire (OSRS wilderness bosses / SkyBlock dragons and Kuudra).
--   * Region "ShatteredCrown": Combat 60 and the main quest Crown of the Tempest
--     (requires.questsDone, checked by server regionAllowed). Four monsters
--     (levels 85-110), a ninth mining tier and a seventh woodcutting and fishing
--     tier (level 90+, tool tier 7), and Crownforged tools (tool tier 8).
--   * World bosses (Data.WorldBosses, resolved through Data.Monsters[id] like
--     sea creatures, never iterated by pairs(Data.Monsters)):
--       Aurelith  summoned at the Sovereign Altar by SIGILS Crown Sigils (any
--                 players, at most ALTAR_PER_PLAYER each; SkyBlock eyes).
--       Nyxwyrm   scheduled once per isle day (Skyward Calendar, 2 h 32.5 min),
--                 SCHEDULE.offset seconds after dawn, announced WARNING s early.
--     Phases by health fraction; each phase cycles its telegraphed attacks:
--       disc  (warning disc on a participant: leave it)
--       ring  (nova around the boss: get out of radius)
--       safe  (eclipse: everyone OUTSIDE radius of the boss is struck: get in)
--       adds  (a wave of region monsters; while any lives the boss is warded and
--              takes WARD x damage)
--     Enrage after def.enrage seconds: damage x ENRAGE_DAMAGE, attacks faster.
--     The boss departs after def.duration seconds (no loot).
--   * Contribution loot: share = damage dealt / boss max health. Credit needs
--     share >= MIN_SHARE, alive and within def.creditRange of the arena at the
--     kill, a hit in the last ACTIVE_WINDOW seconds, and (Ironman) share >=
--     IRONMAN_SHARE. Guaranteed rewards (coins, Essence, guaranteed rows) scale
--     with the share; the tier (ContributionTiers) sets the loot weight:
--     loot weight = tier weight + rank bonus + summoner bonus scales the chance
--     of every roll (capped at 1); Magic Find then applies (Progression.rollDrops).
--     Damage XP is the normal on-kill accrual (def.xp over def.hp).
-- combat.server.lua (World Boss section) runs fights; server.server.lua pays
-- through bridge "worldBoss"; world.server.lua builds the region; tests in
-- verify-endgame.luau.
------------------------------------------------------------------------------
do
local E = {}
Data.Endgame = E
E.REGION = "ShatteredCrown"
E.MIN_SHARE = 0.01          -- of the boss's max health
E.IRONMAN_SHARE = 0.3       -- Ironman journals carry their own weight
E.ACTIVE_WINDOW = 60        -- seconds: last hit this recently before the kill
E.WARD = 0.5                -- damage taken while an add wave lives
E.ENRAGE_DAMAGE = 2         -- damage multiplier once enraged
E.ENRAGE_TEMPO = 0.6        -- attack interval multiplier once enraged
E.ALTAR_PER_PLAYER = 2      -- sigils one player may place per summoning
E.SUMMONER_BONUS = 0.25     -- loot weight per own sigil in the summoning
E.SUMMONER_CAP = 0.5
E.RANK_BONUS = {0.5, 0.3, 0.15}
E.HUD_RANGE = 200           -- studs from the arena centre for the boss HUD
E.TOP = 5                   -- leaderboard rows
-- Highest tier first. The tier sets the loot weight of chance rolls; the
-- guaranteed rewards (coins, Sovereign Essence, guaranteed loot rows) scale
-- with the contribution share itself, so splitting a kill across many small
-- contributors (alts, leeches) never pays more than the damage dealt.
-- maxShare (derived) is the next tier's threshold: a payload's share is
-- clamped into its tier's band.
E.ContributionTiers = {
	{id="Champion",name="Champion",minShare=0.25,weight=3,color="FFAA00"},
	{id="Vanguard",name="Vanguard",minShare=0.10,weight=1.25,color="AA00AA"},
	{id="Valiant",name="Valiant",minShare=0.03,weight=0.5,color="5555FF"},
	{id="Participant",name="Participant",minShare=0.01,weight=0.2,color="55FF55"},
}
E.TierById = {}
for i, t in ipairs(E.ContributionTiers) do
	t.index = i
	t.maxShare = if i == 1 then 1 else E.ContributionTiers[i - 1].minShare
	E.TierById[t.id] = t
end
-- Guaranteed payout per kill (the shares of one kill sum to at most 1):
--   coins   = max(COIN_FLOOR, share x boss hp x COIN_RATE x the best regional
--             monster's coins per damage): a flat 2x the regional coin rate
--   essence = max(1, round(share x ESSENCE_POOL))
--   guaranteed loot rows (chance 1): max(1, round(row amount x share x GUARANTEED_POOL))
E.COIN_RATE = 2
E.COIN_FLOOR = 300
E.ESSENCE_POOL = 40
E.GUARANTEED_POOL = 10
-- Altar refunds owed to journals that were not on this server (applied on join).
E.REFUND_CAP = 8

------------------------------------------------------------------------------
-- Region
------------------------------------------------------------------------------
local region = {id="ShatteredCrown",name="The Shattered Crown",requires={skills={Combat=60},questsDone={"CrownOfTempest"}},
	description="Islets of a sky-crown shattered above the storm. Riftmaws, glass seers, crownforged colossi and voidcrown drakes guard the Sovereign Altar.",
	monsters={"RiftmawStalker","ShardglassSeer","CrownforgedColossus","VoidcrownDrake","Aurelith","Nyxwyrm"}}
table.insert(Data.Regions, region)
Data.RegionById[region.id] = region
-- Human-readable region requirement (server notices, world signs, UI).
function E.requirementParts(def)
	local parts = {}
	local requires = type(def) == "table" and def.requires or {}
	if requires.quest then table.insert(parts, "Complete "..requires.quest.." guild contracts") end
	local skills = {}
	for skill in pairs(requires.skills or {}) do table.insert(skills, skill) end
	table.sort(skills)
	for _, skill in ipairs(skills) do table.insert(parts, skill.." "..requires.skills[skill]) end
	for _, id in ipairs(requires.questsDone or {}) do
		local q = Data.QuestById[id]
		table.insert(parts, "Quest: "..(q and q.title or id))
	end
	return parts
end
-- Pure gate: levels = {[skill]=level}, done = {[questId]=true}, contracts = n.
function E.regionOpen(def, levels, done, contracts)
	local requires = type(def) == "table" and def.requires or {}
	if requires.quest and (tonumber(contracts) or 0) < requires.quest then return false end
	for skill, lvl in pairs(requires.skills or {}) do if (tonumber(levels and levels[skill]) or 1) < lvl then return false end end
	for _, id in ipairs(requires.questsDone or {}) do if not (done and done[id]) then return false end end
	return true
end

------------------------------------------------------------------------------
-- Materials
------------------------------------------------------------------------------
item("CrownShard",{name="Crown Shard",kind="material",rarity="Rare",color="E9D58A",value=40,description="A splinter of the shattered sky-crown. Dropped across the Shattered Crown."})
item("RiftHide",{name="Riftmaw Hide",kind="material",rarity="Rare",color="7A3FA0",value=60,description="Rift-stitched hide of a Riftmaw Stalker. Leather for the Eclipse Stalker set."})
item("SeerGlass",{name="Seerglass Lens",kind="material",rarity="Epic",color="9FE6F2",value=90,description="A singing lens shed by a Shardglass Seer. Inscribed into Riftweave."})
item("ColossusCore",{name="Colossus Heartstone",kind="material",rarity="Epic",color="C9A24D",value=120,description="The furnace heart of a Crownforged Colossus. Tempers Sovereign plate."})
item("DrakeScale",{name="Voidcrown Scale",kind="material",rarity="Epic",color="3A2466",value=120,description="A night-black scale of a Voidcrown Drake."})
item("SovereignEssence",{name="Sovereign Essence",kind="material",rarity="Legendary",color="FFD86B",value=250,description="Crown-light poured from a felled world boss. Every endgame recipe needs it."})
item("SovereignCrest",{name="Sovereign Crest",kind="material",rarity="Legendary",color="FFAA00",value=2500,description="A rare crest from a world boss's hoard. Crowns every endgame weapon and chestpiece."})
item("CrownSigil",{name="Crown Sigil",kind="material",rarity="Epic",color="F2D27A",value=600,description="Placed in the Sovereign Altar. Four sigils wake Aurelith, the Shattered Sovereign."})
for id, scale in pairs({CrownShard=0.2,RiftHide=0.3,SeerGlass=0.2,ColossusCore=0.1,DrakeScale=0.1,SovereignEssence=0.05}) do
	table.insert(Data.CollectionItems, id)
	Data.CollectionScale[id] = scale
end

------------------------------------------------------------------------------
-- Resource tiers (level 90+, tool tier 7) and the Crownsteel ingot
------------------------------------------------------------------------------
E.Resources = {
	{skill="Mining",id="Crownstone",name="Crownstone Ore",level=92,xp=420,tool=7,respawn=25,value=220,color="D8B4FF"},
	{skill="Woodcutting",id="ShatterbarkLog",name="Shatterbark Log",level=90,xp=320,tool=7,respawn=20,value=140,color="B9A6E8"},
	{skill="Fishing",id="Riftfin",name="Riftfin",level=90,xp=320,tool=7,respawn=20,value=150,color="8E7CF0"},
}
for _, r in ipairs(E.Resources) do
	local tiers = Data.ResourceTiers[r.skill]
	local def = {id=r.id,name=r.name,level=r.level,xp=r.xp,tool=r.tool,respawn=r.respawn,value=r.value,color=r.color}
	table.insert(tiers, def)
	def.skill, def.index = r.skill, #tiers
	Data.ResourceSkill[r.id] = r.skill
	item(r.id,{name=r.name,kind="resource",skill=r.skill,tier=def.index,color=r.color,value=r.value,rarity="Legendary",
		description="Gathered with "..r.skill.." "..r.level.." (tool tier "..r.tool.."). +"..r.xp.." XP per harvest. Only in the Shattered Crown."})
	table.insert(Data.CollectionItems, r.id)
end
item("CookedRiftfin",{name="Seared Riftfin",kind="consumable",category="food",rarity="Epic",color="8E7CF0",heal=300,recovery=4,value=310,requires={Cooking=90},description="Restore up to 300 health."})
recipe("CookedRiftfin",{skill="Cooking",level=90,xp=330,costs={Riftfin=1,AetherLotus=1},repeatable=true,station="Hearth",category="Meals"})
item("CrownsteelIngot",{name="Crownsteel Ingot",kind="material",rarity="Legendary",color="E3C9FF",value=700,description="Smelted from Crownstone with Shatterbark fuel."})
recipe("CrownsteelIngot",{skill="Smithing",level=90,xp=200,costs={Crownstone=3,ShatterbarkLog=1},repeatable=true,station="Forge",category="Ingots"})

-- Crownforged tools: tool tier 8 (above Celestial).
local toolDefs = {
	{kind="Pickaxe",slot="pickaxe",skill="Mining",stats={miningSpeed=340,miningFortune=135},extra={ShatterbarkLog=2}},
	{kind="Hatchet",slot="hatchet",skill="Woodcutting",stats={foragingFortune=135,strength=24},extra={ShatterbarkLog=4}},
	{kind="Rod",slot="rod",skill="Fishing",stats={fishingFortune=135,seaCreatureChance=8},extra={ShatterbarkLog=3,Riftfin=4}},
	{kind="Hoe",slot="hoe",skill="Farming",stats={farmingFortune=135},extra={ShatterbarkLog=2,AetherLotus=8}},
}
E.ToolOrder = {}
for _, t in ipairs(toolDefs) do
	local id = "Crownforged"..t.kind
	local costs = {CrownsteelIngot=3,CrownShard=12}
	for k, v in pairs(t.extra) do costs[k] = v end
	item(id,{name="Crownforged "..t.kind,kind="tool",toolKind=t.kind,slot=t.slot,toolTier=8,tier=8,rarity="Legendary",color="E3C9FF",stats=t.stats,
		requires={[t.skill]=90},value=2800,description="Tier 8 "..string.lower(t.kind)..". Requires "..t.skill.." 90."})
	recipe(id,{skill="Smithing",level=90,xp=600,costs=costs,collectionTier={Crownstone=1},station="Forge",category="Tools"})
	table.insert(E.ToolOrder, id)
end

------------------------------------------------------------------------------
-- Monsters (levels 85-110)
------------------------------------------------------------------------------
E.MonsterOrder = {"RiftmawStalker","ShardglassSeer","CrownforgedColossus","VoidcrownDrake"}
local monsters = {
	RiftmawStalker={name="Riftmaw Stalker",level=85,region="ShatteredCrown",hp=32000,damage=760,defense=360,xp=700,coins=150,speed=16,color="7A3FA0",style="melee",
		drops={{item="CrownShard",chance=0.7,min=1,max=3},{item="RiftHide",chance=0.45,min=1,max=2},{item="Crownstone",chance=0.3,min=1,max=2},{item="ArcaneDust",chance=0.8,min=6,max=12}}},
	ShardglassSeer={name="Shardglass Seer",level=92,region="ShatteredCrown",hp=42000,damage=900,defense=300,xp=880,coins=180,speed=13,color="9FE6F2",style="magic",
		drops={{item="CrownShard",chance=0.8,min=2,max=4},{item="SeerGlass",chance=0.35,min=1,max=1},{item="VoidEssence",chance=0.6,min=2,max=4},{item="StarFragment",chance=0.02,min=1,max=1}}},
	CrownforgedColossus={name="Crownforged Colossus",level=100,region="ShatteredCrown",hp=70000,damage=1150,defense=650,xp=1250,coins=240,speed=9,color="C9A24D",style="melee",
		drops={{item="CrownShard",chance=0.9,min=3,max=6},{item="ColossusCore",chance=0.25,min=1,max=1},{item="Crownstone",chance=0.6,min=2,max=4},{item="StarFragment",chance=0.03,min=1,max=1}}},
	VoidcrownDrake={name="Voidcrown Drake",level=110,region="ShatteredCrown",hp=95000,damage=1400,defense=480,xp=1600,coins=320,speed=18,color="3A2466",style="ranged",
		drops={{item="CrownShard",chance=0.9,min=3,max=6},{item="DrakeScale",chance=0.3,min=1,max=1},{item="SovereignEssence",chance=0.05,min=1,max=1},{item="ShardlingPet",chance=0.0008,min=1,max=1}}},
}
local CS = Data.CombatStyles
local function applyStyle(def, style)
	def.attackStyle = style
	def.weakness = CS.beatenBy[style]
	def.defenceStyle = CS.beats[style]
end

------------------------------------------------------------------------------
-- Pet and drop-only uniques
------------------------------------------------------------------------------
local shardling = {id="Shardling",name="Shardling",skill="Combat",rarity="Legendary",color="F2D27A",perLevel={strength=0.7,critDamage=0.7,health=1.2,magicFind=0.05},ability="Crownbound: +5% Magic Find on world bosses"}
table.insert(Data.Pets, shardling)
Data.PetById.Shardling = shardling
item("ShardlingPet",{name="Shardling Pet",kind="pet",pet="Shardling",rarity="Legendary",color="F2D27A",value=200*Data.Rarity.Legendary.rank^2,description="Summon from your pet menu. "..shardling.ability})
item("SovereignSignet",{name="Sovereign Signet",kind="accessory",rarity="Mythic",color=Data.Rarity.Mythic.color,stats={strength=40,critDamage=30,health=80},value=40*Data.Rarity.Mythic.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Mythic.power..". Only Aurelith's hoard holds one."})
item("NyxwingCharm",{name="Nyxwing Charm",kind="accessory",rarity="Mythic",color=Data.Rarity.Mythic.color,stats={intelligence=60,rangedStrength=20,magicFind=6},value=40*Data.Rarity.Mythic.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Mythic.power..". Only Nyxwyrm's hoard holds one."})
item("Crownbreaker",{name="Crownbreaker",kind="weapon",slot="weapon",tier=9,rarity="Mythic",color="FFD86B",stats={damage=380,strength=175,critChance=18,critDamage=110},requires={Combat=70},value=60000,
	description="Melee. Aurelith's own sceptre-blade. Requires Combat 70."})
item("Duskpiercer",{name="Duskpiercer",kind="weapon",slot="weapon",style="ranged",tier=9,rarity="Mythic",color="6B4AB8",stats={critDamage=50,rangedAccuracy=90,rangedStrength=20},
	ranged={power=300,speed=0.95,range=CS.maxRange,maxAmmoTier=7},requires={Ranged=70},value=60000,
	description="Ranged weapon. Strung with Nyxwyrm's sinew. "..CS.maxRange.." stud reach. Arrows up to tier 7. Requires Ranged 70."})

------------------------------------------------------------------------------
-- Endgame gear: one set per combat style, stats above Celestial.
------------------------------------------------------------------------------
local slotShare = {helmet=0.6,chest=1,legs=0.85,boots=0.5}
local slotNames = {helmet="Helm",chest="Chestplate",legs="Greaves",boots="Boots"}
local slotUnits = {helmet=5,chest=8,legs=7,boots=4}
E.Sets = {
	{id="Sovereign",name="Sovereign's Mandate",style="melee",skill="Smithing",station="Forge",level=92,combat={Combat=60},color="FFD86B",rarity="Legendary",
		piece="Sovereign",names={helmet="Crown",chest="Cuirass",legs="Tassets",boots="Sabatons"},
		armor={defense=360,health=320,strength=15,critDamage=15},bonus={strength=70,critDamage=80,health=400,defense=200},
		text="+70 Strength, +80 Crit Damage, +400 Health, +200 Defense",
		unit={CrownsteelIngot=1},extra={ColossusCore=1,SovereignEssence=1},
		weapon={id="SovereignGreatblade",name="Sovereign Greatblade",stats={damage=360,strength=160,critChance=16,critDamage=100},
			costs={CrownsteelIngot=10,ColossusCore=4,SovereignEssence=8,SovereignCrest=1},level=94}},
	{id="EclipseStalker",name="Umbral Volley",style="ranged",skill="Fletching",station="Workbench",level=92,combat={Ranged=60},color="6B4AB8",rarity="Legendary",
		piece="Eclipse",names={helmet="Cowl",chest="Jerkin",legs="Chaps",boots="Treads"},
		armor={defense=300,health=270,rangedStrength=12,rangedAccuracy=8},bonus={rangedStrength=30,rangedAccuracy=30,critChance=8,critDamage=50,health=300,defense=150},
		text="+30 Ranged Strength, +30 Ranged Accuracy, +8 Crit Chance, +50 Crit Damage, +300 Health, +150 Defense",
		unit={RiftHide=2},extra={DrakeScale=1,SovereignEssence=1},
		weapon={id="EclipseLongbow",name="Eclipse Longbow",stats={critDamage=40,rangedAccuracy=80,rangedStrength=20},
			ranged={power=300,speed=1.0,range=CS.maxRange,maxAmmoTier=7},
			costs={ShatterbarkLog=12,SilkString=2,DrakeScale=4,SovereignEssence=8,SovereignCrest=1},level=94}},
	{id="Riftweave",name="Rift Attunement",style="magic",skill="Glyphcraft",station="Workbench",level=92,combat={Magic=60},color="9FE6F2",rarity="Legendary",
		piece="Riftweave",names={helmet="Circlet",chest="Robe",legs="Leggings",boots="Slippers"},
		armor={defense=290,health=260,intelligence=40,abilityDamage=2},bonus={intelligence=80,abilityDamage=8,health=350,defense=150},
		text="+80 Intelligence, +8% Ability Damage, +350 Health, +150 Defense",
		unit={SpiderSilk=3},extra={SeerGlass=1,SovereignEssence=1},
		weapon={id="RiftcrownStaff",name="Riftcrown Staff",stats={intelligence=180,abilityDamage=6},
			magic={power=190,speed=1.15,elements={"Gale","Tide","Stone","Ember"}},
			costs={ShatterbarkLog=10,SeerGlass=6,SovereignEssence=8,SovereignCrest=1},level=94}},
}
E.SetById = {}
E.GearOrder = {}
for _, set in ipairs(E.Sets) do
	E.SetById[set.id] = set
	Data.Sets[set.id] = {id=set.id,name=set.name,pieces={},bonus=set.bonus,text=set.text,color=set.color}
	for _, slot in ipairs(Data.ArmorSlots) do
		local id = set.piece..slotNames[slot]
		local n = slotUnits[slot]
		local costs = {}
		for k, v in pairs(set.unit) do costs[k] = v * n end
		for k, v in pairs(set.extra) do costs[k] = math.max(1, v * n // 2) end
		costs.CrownShard = 6 * n
		if slot == "chest" then costs.SovereignCrest = 1 end
		item(id,{name=set.piece.." "..set.names[slot],kind="armor",slot=slot,set=set.id,tier=9,rarity=set.rarity,color=set.color,
			stats=(function() local out = {} for k, v in pairs(set.armor) do out[k] = math.max(1, math.floor(v * slotShare[slot] + 0.5)) end return out end)(),
			requires=table.clone(set.combat),value=5000*n,description="Part of the "..set.name.." set ("..Data.CombatStyles.names[set.style].."). "..set.text.." with all four."})
		recipe(id,{skill=set.skill,level=set.level,xp=90*n,costs=costs,collectionTier={CrownShard=2},station=set.station,category="Armor"})
		table.insert(Data.Sets[set.id].pieces, id)
		table.insert(E.GearOrder, id)
	end
	local w = set.weapon
	local def = {name=w.name,kind="weapon",slot="weapon",tier=9,rarity=set.rarity,color=set.color,stats=table.clone(w.stats),requires=table.clone(set.combat),value=50000}
	if set.style ~= "melee" then def.style = set.style end
	if w.ranged then def.ranged = table.clone(w.ranged) end
	if w.magic then def.magic = {power=w.magic.power,speed=w.magic.speed,elements=table.clone(w.magic.elements)} end
	def.description = if set.style == "ranged" then "Ranged weapon. "..CS.maxRange.." stud reach. Arrows up to tier 7."
		elseif set.style == "magic" then "Magic weapon. Supplies unlimited Gale, Tide, Stone and Ember glyphs."
		else "Melee. Forged from Crownsteel and a Sovereign Crest."
	item(w.id, def)
	recipe(w.id,{skill=set.skill,level=w.level,xp=1500,costs=w.costs,collectionTier={CrownShard=3},station=set.station,category=if set.style=="melee" then "Weapons" elseif set.style=="ranged" then "Bows" else "Staves"})
	table.insert(E.GearOrder, w.id)
end
-- Summoning: a Crown Sigil needs every regional drop.
recipe("CrownSigil",{skill="Glyphcraft",level=85,xp=450,costs={CrownShard=24,RiftHide=2,SeerGlass=2,ColossusCore=1,DrakeScale=1},repeatable=true,
	collectionTier={CrownShard=1},station="Cauldron",category="Glyphs"})

------------------------------------------------------------------------------
-- World bosses
------------------------------------------------------------------------------
-- attacks: kind disc|ring|safe|adds; radius studs; windup seconds from the
-- warning to the strike; mult x boss damage per player struck.
Data.WorldBosses = {
	Aurelith={name="Aurelith, the Shattered Sovereign",short="Aurelith",level=120,hp=3000000,damage=1500,defense=500,xp=40000,coins=0,speed=9,color="F2D27A",
		style="melee",body="sovereign",summon="altar",sigils=4,duration=600,enrage=420,arenaRange=70,creditRange=120,leash=26,
		phases={
			{at=1,name="Crowned",attacks={"slam","nova"},interval=7},
			{at=0.66,name="Fractured",attacks={"slam","adds","nova"},interval=6},
			{at=0.33,name="Shattered",attacks={"eclipse","slam","adds","nova"},interval=5},
		},
		attacks={
			slam={kind="disc",name="Crown Slam",radius=9,windup=2.0,mult=1.2},
			nova={kind="ring",name="Shard Nova",radius=18,windup=2.6,mult=1.5},
			eclipse={kind="safe",name="Sovereign Eclipse",radius=14,windup=3.2,mult=2.0},
			adds={kind="adds",name="Riftmaw Pack",monster="RiftmawStalker",count=3,radius=14},
		},
		loot={
			{item="CrownShard",chance=1,min=8,max=16},
			{item="SovereignEssence",chance=1,min=2,max=4},
			{item="StarFragment",chance=0.3,min=1,max=3},
			{item="SovereignCrest",chance=0.06,min=1,max=1},
			{item="SovereignSignet",chance=0.01,min=1,max=1},
			{item="ShardlingPet",chance=0.004,min=1,max=1},
			{item="Crownbreaker",chance=0.004,min=1,max=1},
		}},
	Nyxwyrm={name="Nyxwyrm, the Eclipse Tyrant",short="Nyxwyrm",level=130,hp=4500000,damage=1800,defense=450,xp=55000,coins=0,speed=12,color="4B2C7A",
		style="magic",body="wyrm",summon="schedule",duration=720,enrage=540,arenaRange=75,creditRange=125,leash=28,
		phases={
			{at=1,name="Dusk",attacks={"breath","sweep"},interval=7},
			{at=0.66,name="Gloaming",attacks={"breath","brood","sweep"},interval=6},
			{at=0.33,name="Eclipse",attacks={"nightfall","breath","brood","sweep"},interval=4.5},
		},
		attacks={
			breath={kind="disc",name="Umbral Breath",radius=12,windup=2.2,mult=1.3},
			sweep={kind="ring",name="Tail Sweep",radius=16,windup=2.4,mult=1.4},
			nightfall={kind="safe",name="Nightfall",radius=12,windup=3.4,mult=2.2},
			brood={kind="adds",name="Glass Brood",monster="ShardglassSeer",count=2,radius=16},
		},
		loot={
			{item="CrownShard",chance=1,min=10,max=18},
			{item="SovereignEssence",chance=1,min=3,max=5},
			{item="DrakeScale",chance=0.5,min=1,max=3},
			{item="SovereignCrest",chance=0.06,min=1,max=1},
			{item="NyxwingCharm",chance=0.01,min=1,max=1},
			{item="ShardlingPet",chance=0.004,min=1,max=1},
			{item="Duskpiercer",chance=0.004,min=1,max=1},
		}},
}
E.BossOrder = {"Aurelith","Nyxwyrm"}
-- Skyward Calendar schedule: once per isle day, `offset` seconds after dawn.
E.SCHEDULE = {boss="Nyxwyrm",offset=6600,window=180,warning=300}
for id, def in pairs(Data.WorldBosses) do
	def.id, def.worldBoss, def.region = id, true, E.REGION
	def.drops = def.loot -- bestiary display
	applyStyle(def, def.style)
end
for id, def in pairs(monsters) do
	def.id = id
	applyStyle(def, def.style)
	def.style = nil
	Data.Monsters[id] = def
end
-- Lookups by id reach sea creatures and world bosses; pairs() sees marker monsters only.
setmetatable(Data.Monsters, {__index = function(_, id)
	return rawget(Data.SeaCreatures, id) or rawget(Data.WorldBosses, id)
end})
-- Drift plume from drakes (fletching supply).
table.insert(Data.Monsters.VoidcrownDrake.drops, {item="DriftPlume",chance=0.8,min=4,max=8})

------------------------------------------------------------------------------
-- Pure rules
------------------------------------------------------------------------------
function E.boss(id) return type(id) == "string" and rawget(Data.WorldBosses, id) or nil end
-- Phase index for a health fraction (1 = full health).
function E.phaseFor(def, fraction)
	local index = 1
	for i, phase in ipairs(def.phases) do if fraction <= phase.at + 1e-9 then index = i end end
	return index
end
-- Seconds between telegraphed attacks in a phase (faster once enraged).
function E.attackInterval(def, phase, enraged)
	local p = def.phases[phase] or def.phases[1]
	return p.interval * (if enraged then E.ENRAGE_TEMPO else 1)
end
-- The attack id at rotation step n (1-based) of a phase.
function E.attackAt(def, phase, n)
	local list = (def.phases[phase] or def.phases[1]).attacks
	return list[((math.max(1, math.floor(n)) - 1) % #list) + 1]
end
-- Whether a point is struck by a resolving telegraph. Flat distance.
function E.struck(attack, center, pos)
	local dx, dz = pos.X - center.X, pos.Z - center.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if attack.kind == "disc" or attack.kind == "ring" then return d <= attack.radius end
	if attack.kind == "safe" then return d > attack.radius end
	return false
end
-- Contribution tier for a share of the boss's max health (nil below MIN_SHARE).
function E.contributionTier(share)
	share = tonumber(share) or 0
	if share ~= share then return nil end
	for _, t in ipairs(E.ContributionTiers) do if share >= t.minShare then return t end end
	return nil
end
-- Credit check at the kill. c = {share, alive, distance, ironman, lastHit, now}.
function E.eligible(def, c)
	if type(c) ~= "table" then return false, "invalid" end
	local share = tonumber(c.share) or 0
	if share < E.MIN_SHARE then return false, "share" end
	if c.alive ~= true then return false, "dead" end
	if not c.distance or c.distance > (def.creditRange or 120) then return false, "range" end
	if not c.lastHit or not c.now or c.now - c.lastHit > E.ACTIVE_WINDOW then return false, "idle" end
	if c.ironman and share < E.IRONMAN_SHARE then return false, "ironman" end
	return true
end
-- Loot weight: tier weight + rank bonus + summoner bonus (own sigils).
function E.lootWeight(tierId, rank, sigils)
	local t = E.TierById[tierId]
	if not t then return 0 end
	local bonus = E.RANK_BONUS[tonumber(rank) or 0] or 0
	local summon = math.min(E.SUMMONER_CAP, E.SUMMONER_BONUS * math.max(0, math.floor(tonumber(sigils) or 0)))
	return t.weight + bonus + summon
end
-- Best coins per point of damage among the regional monsters (the reference
-- rate world boss coins are tuned against).
function E.regionalCoinRate()
	local best = 0
	for _, id in ipairs(E.MonsterOrder) do
		local m = Data.Monsters[id]
		best = math.max(best, m.coins / m.hp)
	end
	return best
end
-- Guaranteed coins for a share of a boss's max health (0 for no share).
function E.bossCoins(bossId, share)
	local def = E.boss(bossId)
	share = tonumber(share) or 0
	if not def or share ~= share or share <= 0 then return 0 end
	return math.max(E.COIN_FLOOR, math.floor(math.min(1, share) * def.hp * E.regionalCoinRate() * E.COIN_RATE))
end
-- Reward plan for one credited player: guaranteed items/coins and a drop table
-- for Progression.rollDrops (chances x weight, capped at 1; Magic Find applies
-- to the rolls afterwards). Guaranteed rows (chance 1) scale with the share.
-- share (of max health) is clamped into the tier's band; missing -> the tier minimum.
function E.bossRewards(bossId, tierId, rank, sigils, share)
	local def, t = E.boss(bossId), E.TierById[tierId]
	if not def or not t then return nil end
	share = tonumber(share)
	if not share or share ~= share then share = t.minShare end
	share = math.clamp(share, t.minShare, t.maxShare)
	local weight = E.lootWeight(tierId, rank, sigils)
	local function scaled(n, pool) return math.max(1, math.floor(n * share * pool + 0.5)) end
	local out = {coins=E.bossCoins(bossId, share),items={SovereignEssence=scaled(1, E.ESSENCE_POOL)},drops={},weight=weight,share=share}
	for _, d in ipairs(def.loot) do
		if d.chance >= 1 then
			table.insert(out.drops, {item=d.item,chance=1,min=scaled(d.min, E.GUARANTEED_POOL),max=scaled(d.max, E.GUARANTEED_POOL)})
		else
			table.insert(out.drops, {item=d.item,chance=math.min(1, d.chance * weight),min=d.min,max=d.max})
		end
	end
	return out
end
-- Ranking: list of {player, damage, lastHit} -> sorted by damage (ties: earlier
-- last hit first), each given rank and share of maxHp.
function E.rank(list, maxHp)
	local out = table.clone(list)
	table.sort(out, function(a, b)
		if a.damage ~= b.damage then return a.damage > b.damage end
		return (a.lastHit or 0) < (b.lastHit or 0)
	end)
	for i, e in ipairs(out) do e.rank = i; e.share = if maxHp > 0 then e.damage / maxHp else 0 end
	return out
end
-- Scheduled window around t: {boss, key, starts, ends, open, warnAt}.
-- Each isle day's window starts SCHEDULE.offset seconds after its dawn.
function E.scheduleAt(t)
	local s = E.SCHEDULE
	t = math.floor(tonumber(t) or 0)
	local cal = Data.calendarAt(t)
	local starts = cal.dayStart + s.offset
	if t >= starts + s.window then starts += Data.Calendar.dayLength end
	return {boss=s.boss,key=s.boss..":"..starts,starts=starts,ends=starts+s.window,open=t>=starts and t<starts+s.window,warnAt=starts-s.warning}
end
-- Altar placement check (pure): state = {placed={{user, n}...} or count}, returns ok, reason.
function E.canPlaceSigil(bossId, total, mine, active)
	local def = E.boss(bossId)
	if not def or def.summon ~= "altar" then return false, "boss" end
	if active then return false, "active" end
	if (tonumber(total) or 0) >= def.sigils then return false, "full" end
	if (tonumber(mine) or 0) >= E.ALTAR_PER_PLAYER then return false, "mine" end
	return true
end

------------------------------------------------------------------------------
-- Quests (endgame line) and the Shattered Crown diary
------------------------------------------------------------------------------
local function kills(monster, count) return {kind="kills",monster=monster,count=count} end
for _, q in ipairs({
	{id="WhereTheCrownFell",title="Where the Crown Fell",line="main",region="ShatteredCrown",
		story="Beyond the storm's heart, the sky itself is broken. Warden-captain Ysolde wants the riftmaws thinned and the shards counted.",
		requires={{kind="quest",quest="CrownOfTempest"},{kind="level",skill="Combat",level=60}},
		objectives={kills("RiftmawStalker",25),{kind="collect",item="CrownShard",count=60}},
		rewards={coins=30000,points=2,lamp={xp=30000,exclude={"Dungeoneering","Carpentry"}}}},
	{id="TheGlassChoir",title="The Glass Choir",line="main",region="ShatteredCrown",
		story="The seers sing to the colossi, and the colossi keep the altar. Break the choir and inscribe a sigil from what they guard.",
		requires={{kind="quest",quest="WhereTheCrownFell"}},
		objectives={kills("ShardglassSeer",20),kills("CrownforgedColossus",10),{kind="craft",item="CrownSigil",count=1}},
		rewards={coins=50000,points=3,perk={intelligence=20,strength=10},xp={Glyphcraft=20000}}},
	{id="TheSovereignsFall",title="The Sovereign's Fall",line="main",region="ShatteredCrown",
		story="Two powers rule the broken crown: the Sovereign who wakes at the altar and the Tyrant who rides each dusk. Fell them both.",
		requires={{kind="quest",quest="TheGlassChoir"}},
		objectives={kills("Aurelith",1),kills("Nyxwyrm",1),kills("VoidcrownDrake",15)},
		rewards={coins=150000,points=5,perk={strength=15,critDamage=20,magicFind=3},unlock={accessorySlots=1}}},
}) do
	table.insert(Data.Quests, q)
	q.index = #Data.Quests
	Data.QuestById[q.id] = q
end
E.QuestLine = {"WhereTheCrownFell","TheGlassChoir","TheSovereignsFall"}
local diary = {region="ShatteredCrown",name="Shattered Crown Diary",tiers={
	Easy={tasks={{kind="gather",region="ShatteredCrown",count=10},kills("RiftmawStalker",10),{kind="collect",item="CrownShard",count=25}},perk={strength=5,health=20}},
	Medium={tasks={kills("ShardglassSeer",50),{kind="quest",quest="WhereTheCrownFell"},{kind="craft",item="CrownsteelIngot",count=10},{kind="level",skill="Mining",level=90}},perk={critDamage=10,defense=10}},
	Hard={tasks={kills("CrownforgedColossus",100),kills("Aurelith",1),kills("Nyxwyrm",1),{kind="collect",item="Crownstone",count=250}},perk={strength=10,defense=20,health=40}},
	Elite={tasks={kills("Aurelith",25),kills("Nyxwyrm",25),kills("VoidcrownDrake",500),{kind="quest",quest="TheSovereignsFall"}},perk={strength=20,critDamage=25,magicFind=5}},
}}
table.insert(Data.Diaries, diary)
Data.DiaryByRegion[diary.region] = diary
end
-- End Endgame section.


------------------------------------------------------------------------------
-- Workers depth (Workers team; append-only section).
-- SkyBlock-minion depth for island workers, all names original:
--   * Worker types: one per gathering resource tier (Data.ResourceTiers) plus
--     combat workers that produce monster drops. Type ids for gathering are the
--     resource ids (legacy saves keep "Ore", "Timber", ...).
--   * Slots: 3 base, up to 12, unlocked by unique worker crafts (a type at a
--     tier, recorded when a worker is built/upgraded or a blueprint drafted).
--   * Fuel (timed or permanent speed boost), two upgrade slots (press,
--     auto-seller, storage annex, bonus sprinkler) and one chest slot.
--   * Condensed / Radiant forms: 160 raw -> 1 Condensed, 160 Condensed -> 1
--     Radiant; craftable at the Workbench, Bazaar commodities (kind material).
-- Production is pure integer maths on server os.time(), so it is deterministic
-- and capped: W.settle credits at most MAX_ACCRUAL seconds per settle and never
-- beyond the worker's storage (an auto-seller empties full storage into coins).
------------------------------------------------------------------------------
do
local W = {}
Data.Workers = W
W.BASE_SLOTS = 3
W.MAX_SLOTS = 12
-- Unique worker crafts needed for slot 4, 5, ... 12 (index i opens slot 3+i).
W.SlotUniques = {5, 12, 20, 30, 42, 56, 72, 90, 110}
W.MAX_ACCRUAL = 172800      -- seconds credited per settle (48 h offline cap)
W.RATIO = 160               -- press ratio (raw -> Condensed -> Radiant)
W.SELL_SHARE = 0.5          -- auto-seller pays this share of item value
W.UPGRADE_SLOTS = 2
W.FUEL_STACK = 64           -- a timed fuel may hold at most 64 burns of itself
W.MAX_STORE = 100000        -- sanity bound on any stored count (migration)
-- Passive-vs-active balance (verify-workers.luau section 10 holds the model):
--   * at most MAX_PER_TYPE workers of one type and MAX_COMBAT combat workers;
--   * gathering pace scales with the node's respawn (GATHER_PACE x respawn
--     seconds per tier-1 interval unit; starter resources keep pace 1);
--   * worker XP per item is a tenth of a manual harvest (starters: 3);
--   * combat-worker output credits drop collections at 1/COMBAT_COLLECTION_DIV
--     (25%), and combat workers need the drop's collection tier 3;
--   * high gathering tiers need collection tier 4 (level 60+) or 5 (level 75+)
--     and region-exclusive resources need that region unlocked (ResourceRegion).
-- Over-cap or no-longer-allowed workers (legacy saves) idle: they keep their
-- stored output for claiming but produce nothing until reassigned.
W.MAX_PER_TYPE = 3
W.MAX_COMBAT = 2
W.GATHER_PACE = 0.4
W.XP_DIVISOR = 10
W.COMBAT_COLLECTION_DIV = 4
W.COMBAT_COLLECTION_TIER = 3
-- Resources whose every node lies in one gated region (verify-world.luau
-- checks this map against the built world).
W.ResourceRegion = {
	WindpineLog="Windpine", EmberoakLog="Windpine", AetherheartLog="Windpine", Glowcap="Windpine",
	Voidstone="Gloomhollow", Prismite="Gloomhollow", AbyssKoi="Gloomhollow", Moonbloom="Gloomhollow",
	Stormeel="Tidewater", Lanternray="Tidewater", LeviathanScale="Tidewater", GlimmerbarkLog="Tidewater", AetherLotus="Tidewater",
	StarmetalOre="Tempest", Celestium="Tempest", StarwoodLog="Tempest", Starfruit="Tempest",
	Crownstone="ShatteredCrown", ShatterbarkLog="ShatteredCrown", Riftfin="ShatteredCrown",
}
function W.gatherCollectionTier(r)
	if r.index == 1 then return 0 end
	if r.level >= 75 then return 5 end
	if r.level >= 60 then return 4 end
	if r.level >= 30 then return 2 end
	return 1
end

local function rarityStep(rarity, n)
	local index = table.find(Data.RarityOrder, rarity) or 1
	return Data.RarityOrder[math.min(#Data.RarityOrder, index + n)]
end

------------------------------------------------------------------------------
-- Worker types
------------------------------------------------------------------------------
W.Types, W.TypeById = {}, {}
local roles = {Mining="Delver", Woodcutting="Feller", Fishing="Netcaster", Farming="Tiller"}
local typeShapes = {Mining="OreChunk", Woodcutting="Log", Fishing="Finfish", Farming="CropSheaf"}
local function addType(def)
	def.index = #W.Types + 1
	table.insert(W.Types, def)
	W.TypeById[def.id] = def
	return def
end
for _, skill in ipairs({"Mining", "Woodcutting", "Fishing", "Farming"}) do
	for _, r in ipairs(Data.ResourceTiers[skill]) do
		local short = string.gsub(string.gsub(r.name, " Ore$", ""), " Log$", "")
		addType({id=r.id, kind="gather", name=short.." "..roles[skill], output=r.id, skill=skill,
			level=if r.index == 1 then 1 else r.level, collectionTier=W.gatherCollectionTier(r), region=W.ResourceRegion[r.id],
			speed=if r.index == 1 then 1 else math.floor(r.respawn * W.GATHER_PACE * 10 + 0.5) / 10, xp=if r.index == 1 then 3 else math.max(3, r.xp // W.XP_DIVISOR),
			shape=typeShapes[skill], color=r.color, resourceTier=r.index})
	end
end
-- Combat workers: much slower (speed = interval multiplier), gated by Combat
-- level and the drop's collection tier 3; they produce the drop and grant a
-- little Combat XP. Paces keep two maxed combat workers under ~30% of active
-- farming of the same drop (verify-workers.luau section 10).
for _, c in ipairs({
	{id="HidetanSnare", name="Hidetan Snare", output="BeastHide", level=3, speed=4, xp=3, shape="HideRoll"},
	{id="DustsiftCrucible", name="Dustsift Crucible", output="ArcaneDust", level=8, speed=2.5, xp=3, shape="DustPile"},
	{id="ShardlingSentry", name="Shardling Sentry", output="Shard", level=10, speed=5, xp=5, shape="AetherCrystal"},
	{id="GloomsilkLoom", name="Gloomsilk Loom", output="SpiderSilk", level=15, speed=5, xp=5, shape="HideRoll"},
	{id="GalecatchPerch", name="Galecatch Perch", output="StormFeather", level=20, speed=5, xp=6, shape="Feather"},
	{id="WispglowLantern", name="Wispglow Lantern", output="VoidEssence", level=30, speed=7, xp=8, shape="EssenceOrb"},
}) do
	c.kind, c.skill, c.collectionTier, c.color = "combat", "Combat", W.COMBAT_COLLECTION_TIER, Data.Items[c.output].color
	addType(c)
end

------------------------------------------------------------------------------
-- Condensed and Radiant forms (SkyBlock "enchanted" items: 160 -> 1).
------------------------------------------------------------------------------
W.Press = {}        -- raw id -> {condensed=id, radiant=id}
W.PressSource = {}  -- condensed/radiant id -> {raw=id, level=1|2, units=raw per item}
for _, t in ipairs(W.Types) do
	local raw = t.output
	if not W.Press[raw] then
		local def = Data.Items[raw]
		local cid, rid = "Condensed"..raw, "Radiant"..raw
		W.Press[raw] = {condensed=cid, radiant=rid}
		W.PressSource[cid] = {raw=raw, level=1, units=W.RATIO}
		W.PressSource[rid] = {raw=raw, level=2, units=W.RATIO * W.RATIO}
		item(cid, {name="Condensed "..def.name, kind="material", category="condensed", rarity=rarityStep(def.rarity, 1), color=def.color,
			value=def.value * W.RATIO, condensed={from=raw, level=1},
			description=W.RATIO.." "..def.name.." pressed into one. A Bazaar commodity used in worker blueprints, fuels and parts."})
		item(rid, {name="Radiant "..def.name, kind="material", category="condensed", rarity=rarityStep(def.rarity, 2), color=def.color,
			value=def.value * W.RATIO * W.RATIO, condensed={from=cid, level=2},
			description=W.RATIO.." Condensed "..def.name.." fused into one radiant ingot-form. A Bazaar commodity."})
		recipe(cid, {skill=t.skill, level=1, xp=8, costs={[raw]=W.RATIO}, collectionTier={[raw]=2}, repeatable=true, station="Workbench", category="Compacting"})
		recipe(rid, {skill=t.skill, level=1, xp=60, costs={[cid]=W.RATIO}, collectionTier={[raw]=6}, repeatable=true, station="Workbench", category="Compacting"})
	end
end

------------------------------------------------------------------------------
-- Fuel, upgrades and chests (Workbench, Carpentry).
------------------------------------------------------------------------------
W.Fuels, W.Upgrades, W.Chests = {}, {}, {}
W.FuelOrder, W.UpgradeOrder, W.ChestOrder = {}, {}, {}
-- A part is never worth more than what it is made of (no merchant mints):
-- value = min(declared, floor(input value / amount)).
function W.inputValue(rec)
	local total = 0
	for id, n in pairs(rec.costs) do total += (Data.Items[id] and Data.Items[id].value or 0) * n end
	return total // (rec.amount or 1)
end
local function part(id, def, rec, kind)
	def.kind = "material"
	def.value = math.min(def.value or 10, W.inputValue(rec))
	item(id, def)
	recipe(id, rec)
	rec.station, rec.category, rec.skill, rec.repeatable = "Workbench", "Worker Parts", "Carpentry", true
end
-- Fuel: speed is a percentage added to the worker's base pace; duration in
-- seconds (permanent fuels never burn out and are returned when removed).
for _, f in ipairs({
	{id="CharredBriquette", name="Charred Briquette", rarity="Common", color="4A3B33", speed=5, duration=1800, value=4,
		rec={level=1, xp=6, costs={Timber=24}, amount=2}},
	{id="EmberwoodBrick", name="Emberwood Brick", rarity="Uncommon", color="B5482A", speed=8, duration=21600, value=60,
		rec={level=15, xp=30, costs={EmberoakLog=16, Ore=8}}},
	{id="StormcellCanister", name="Stormcell Canister", rarity="Rare", color="7B8CDE", speed=12, duration=43200, value=1800,
		rec={level=25, xp=90, costs={CondensedWindpineLog=1, StormFeather=4}}},
	{id="SunforgeCatalyst", name="Sunforge Catalyst", rarity="Epic", color="F2C14E", speed=15, duration=86400, value=7000,
		rec={level=40, xp=220, costs={CondensedSunsteelOre=1, CondensedEmberoakLog=1, GolemCore=1}}},
	{id="EverflameHeart", name="Everflame Heart", rarity="Legendary", color="FF7A3D", speed=10, permanent=true, value=25000,
		rec={level=55, xp=600, costs={StarFragment=6, CondensedAetherite=3, GolemCore=4}}},
}) do
	local text = if f.permanent then "+"..f.speed.."% worker speed, permanently (returned when removed)."
		else "+"..f.speed.."% worker speed for "..(if f.duration >= 3600 then (f.duration // 3600).." h" else (f.duration // 60).." min").."."
	part(f.id, {name=f.name, category="workerFuel", rarity=f.rarity, color=f.color, value=f.value,
		workerFuel={speed=f.speed, duration=f.duration, permanent=f.permanent}, description="Worker fuel. "..text}, f.rec)
	W.Fuels[f.id] = {id=f.id, speed=f.speed, duration=f.duration, permanent=f.permanent == true}
	table.insert(W.FuelOrder, f.id)
end
-- Upgrades: two slots per worker; one of each group.
--   press 1 = Condensed forms, press 2 = Condensed and Radiant forms
--   sell = share of value paid when storage is full (storage is then emptied)
--   storage = extra share of the tier's storage; bonus = 1 item every N produced
for _, u in ipairs({
	{id="WorkerBundler", name="Bundling Frame", rarity="Uncommon", color="B08D57", group="press", press=1, value=200,
		text="Packs every 160 output into a Condensed form.", rec={level=10, xp=40, costs={AlloyIngot=8, Timber=96}}},
	{id="WorkerAetherPress", name="Aether Press", rarity="Epic", color="7FD6E8", group="press", press=2, value=6000,
		text="Packs output into Condensed forms and 160 Condensed into a Radiant form.", rec={level=35, xp=160, costs={WorkerBundler=1, CondensedAetherite=2, AetherIngot=8}}},
	{id="WorkerCoinchute", name="Coinchute", rarity="Rare", color="FFD166", group="sell", sell=W.SELL_SHARE, value=400,
		text="When storage fills, sells everything stored for 50% of its value.", rec={level=20, xp=70, costs={BrassIngot=6, AlloyIngot=10}}},
	{id="WorkerStoreAnnex", name="Storehouse Annex", rarity="Uncommon", color="9C6B3E", group="storage", storage=0.5, value=150,
		text="+50% of the worker's tier storage.", rec={level=8, xp=30, costs={Timber=128, Ore=48}}},
	{id="WorkerGleamSprinkler", name="Gleam Sprinkler", rarity="Rare", color="C77DFF", group="bonus", bonus={item="ArcaneDust", every=10}, value=1000,
		text="1 Arcane Dust for every 10 items produced.", rec={level=30, xp=110, costs={CondensedHerb=1, ArcaneDust=24, Aetherite=48}}},
}) do
	part(u.id, {name=u.name, category="workerUpgrade", rarity=u.rarity, color=u.color, value=u.value, workerUpgrade=u.group,
		description="Worker upgrade. "..u.text}, u.rec)
	W.Upgrades[u.id] = {id=u.id, group=u.group, press=u.press, sell=u.sell, storage=u.storage, bonus=u.bonus, text=u.text}
	table.insert(W.UpgradeOrder, u.id)
end
for _, c in ipairs({
	{id="WorkerCoffer", name="Timber Coffer", rarity="Common", color="9C6B3E", capacity=120, value=40, rec={level=5, xp=20, costs={Timber=64}}},
	{id="WorkerBrassChest", name="Brassbound Chest", rarity="Uncommon", color="D4A84B", capacity=360, value=300, rec={level=25, xp=90, costs={WindpineLog=48, BrassIngot=4}}},
	{id="WorkerVaultChest", name="Vaultwork Chest", rarity="Epic", color="C9D6E3", capacity=960, value=12000, rec={level=50, xp=400, costs={CondensedStarwoodLog=1, StarmetalIngot=4}}},
}) do
	part(c.id, {name=c.name, category="workerChest", rarity=c.rarity, color=c.color, value=c.value, workerChest=c.capacity,
		description="Worker chest. +"..c.capacity.." storage."}, c.rec)
	W.Chests[c.id] = {id=c.id, capacity=c.capacity}
	table.insert(W.ChestOrder, c.id)
end

------------------------------------------------------------------------------
-- Rules (pure; the server, UI and tests share them).
------------------------------------------------------------------------------
function W.tierConfig(tier)
	return Data.WorkerTiers[math.clamp(math.floor(tonumber(tier) or 1), 1, #Data.WorkerTiers)]
end
-- Seconds per item: tier interval x type speed, shortened by worker haste.
function W.interval(typeId, tier, haste)
	local t = W.TypeById[typeId]
	haste = math.clamp(tonumber(haste) or 0, 0, Data.MAX_WORKER_HASTE)
	return math.max(1, math.floor(W.tierConfig(tier).interval * (t and t.speed or 1) * (1 - haste) + 0.5))
end
local function upgradeDefs(w)
	local list = {}
	for i = 1, W.UPGRADE_SLOTS do
		local u = type(w.upgrades) == "table" and W.Upgrades[w.upgrades[i]]
		if u then table.insert(list, u) end
	end
	return list
end
W.upgradeDefs = upgradeDefs
-- Storage: tier storage, +annex share, +chest.
function W.capacity(w)
	local base = W.tierConfig(w.tier).capacity
	local extra = 0
	for _, u in ipairs(upgradeDefs(w)) do extra += u.storage or 0 end
	local chest = W.Chests[w.chest]
	return math.floor(base * (1 + extra)) + (chest and chest.capacity or 0)
end
function W.effects(w)
	local press, sell, bonus = 0, nil, nil
	for _, u in ipairs(upgradeDefs(w)) do
		if u.press then press = math.max(press, u.press) end
		if u.sell then sell = u.sell end
		if u.bonus then bonus = u.bonus end
	end
	return press, sell, bonus
end
-- Active fuel definition (nil once a timed fuel has burnt out at `now`).
function W.activeFuel(w, now)
	local f = type(w.fuel) == "table" and W.Fuels[w.fuel.id]
	if not f then return nil end
	if not f.permanent and (tonumber(w.fuel.expires) or 0) <= now then return nil end
	return f
end
function W.speedPercent(w, now)
	local f = W.activeFuel(w, now)
	return 100 + (f and f.speed or 0)
end
-- Output per hour at the current pace (display only).
function W.perHour(w, now, haste)
	return 3600 * W.speedPercent(w, now) / 100 / W.interval(w.resource, w.tier, haste)
end
function W.storeCount(store)
	local n = 0
	for _, v in pairs(store or {}) do n += v end
	return n
end
-- Add up to n raw output to store under capacity `cap`; press 1/2 condense on
-- the fly (an item needs a free slot before it is pressed). Returns made.
function W.produce(store, n, cap, press, raw)
	local ids = W.Press[raw]
	local cid, rid = ids and ids.condensed, ids and ids.radiant
	if not cid then press = 0 end
	local r, c, s = store[raw] or 0, (cid and store[cid]) or 0, (rid and store[rid]) or 0
	local other = W.storeCount(store) - r - c - s
	local made, R = 0, W.RATIO
	if press >= 1 and r >= R then c += r // R; r %= R end
	if press >= 2 and c >= R then s += c // R; c %= R end
	for _ = 1, 10000 do
		if n <= 0 then break end
		local free = cap - (other + s + c + r)
		if free <= 0 then break end
		local need = R - r
		if press == 0 or need > free or n < need then
			local take = math.min(n, free)
			r += take; n -= take; made += take
			break
		end
		r = 0; c += 1; n -= need; made += need
		if press >= 2 and c >= R then c -= R; s += 1 end
		-- Whole blocks from empty raw: block j needs other+s+c+j+(R-1) < cap.
		local blocks = math.max(0, math.min(n // R, cap - (R - 1) - (other + s + c)))
		if press >= 2 then blocks = math.min(blocks, R - c) end
		c += blocks; n -= blocks * R; made += blocks * R
		if press >= 2 and c >= R then c -= R; s += 1 end
	end
	store[raw] = if r > 0 then r else nil
	if cid then store[cid] = if c > 0 then c else nil end
	if rid then store[rid] = if s > 0 then s else nil end
	return made
end
-- Value of everything stored; the auto-seller pays floor(value x share).
function W.storeValue(store)
	local v = 0
	for id, n in pairs(store or {}) do v += (Data.Items[id] and Data.Items[id].value or 0) * n end
	return v
end
-- Advance worker w to `now`. Returns made (raw items produced this settle).
-- w fields: resource, tier, lastClaim, carry (work units), store {id=n},
-- made (pending XP units), coins (auto-sold, pending), bonusCarry, fuel,
-- upgrades {id|false, id|false}, chest.
function W.settle(w, now, haste)
	w.store = w.store or {}
	local t0 = tonumber(w.lastClaim) or now
	if now <= t0 then w.lastClaim = math.min(t0, now); return 0 end
	local span = now - t0
	local start = t0
	if span > W.MAX_ACCRUAL then span = W.MAX_ACCRUAL; start = now - span end
	local boosted, bonusPct = 0, 0
	local f = type(w.fuel) == "table" and W.Fuels[w.fuel.id]
	if f then
		bonusPct = f.speed
		boosted = if f.permanent then span else math.clamp((tonumber(w.fuel.expires) or 0) - start, 0, span)
	end
	local cost = W.interval(w.resource, w.tier, haste) * 100
	local work = (w.carry or 0) + span * 100 + boosted * bonusPct
	local n = work // cost
	w.carry = work % cost
	local t = W.TypeById[w.resource]
	local raw = t and t.output or w.resource
	local cap = W.capacity(w)
	local press, sell, bonus = W.effects(w)
	local made = 0
	for _ = 1, 1000 do
		local got = W.produce(w.store, n - made, cap, press, raw)
		made += got
		if bonus then
			local total = (w.bonusCarry or 0) + got
			local extra = total // bonus.every
			w.bonusCarry = total % bonus.every
			local room = math.max(0, cap - W.storeCount(w.store))
			if math.min(extra, room) > 0 then w.store[bonus.item] = (w.store[bonus.item] or 0) + math.min(extra, room) end
		end
		if made >= n or not sell then break end
		-- Storage is full: the auto-seller empties it into pending coins.
		local value = W.storeValue(w.store)
		if value <= 0 and got == 0 then break end
		w.coins = (w.coins or 0) + math.floor(value * sell)
		w.sold = (w.sold or 0) + W.storeCount(w.store)
		w.store = {}
	end
	if made < n then w.carry = 0 end
	w.made = (w.made or 0) + made
	w.lastClaim = now
	if f and not f.permanent and (tonumber(w.fuel.expires) or 0) <= now then w.fuel = nil end
	return made
end
-- Unique crafts: p.workerUniques[typeId] = bitmask of tiers (bit t-1).
function W.hasUnique(uniques, typeId, tier)
	local mask = type(uniques) == "table" and tonumber(uniques[typeId]) or 0
	return bit32.btest(mask, bit32.lshift(1, tier - 1))
end
function W.addUnique(uniques, typeId, tier)
	if not W.TypeById[typeId] or tier < 1 or tier > #Data.WorkerTiers then return false end
	if W.hasUnique(uniques, typeId, tier) then return false end
	uniques[typeId] = bit32.bor(tonumber(uniques[typeId]) or 0, bit32.lshift(1, tier - 1))
	return true
end
function W.uniqueCount(uniques)
	local n = 0
	for typeId, mask in pairs(uniques or {}) do
		if W.TypeById[typeId] then
			for t = 1, #Data.WorkerTiers do if W.hasUnique(uniques, typeId, t) then n += 1 end end
		end
	end
	return n
end
function W.slotsFor(uniqueCount)
	local slots = W.BASE_SLOTS
	for _, need in ipairs(W.SlotUniques) do if uniqueCount >= need then slots += 1 end end
	return math.min(slots, W.MAX_SLOTS)
end
function W.nextSlotAt(uniqueCount)
	for _, need in ipairs(W.SlotUniques) do if uniqueCount < need then return need end end
	return nil
end
-- Blueprint cost for drafting a unique worker (type, tier) without building it:
-- raw output at tiers 1-3, Condensed output from tier 4.
W.BlueprintRaw = {32, 64, 128}
W.BlueprintCondensed = {[4]=1, [5]=2, [6]=4, [7]=8}
function W.blueprintCost(typeId, tier)
	local t = W.TypeById[typeId]
	if not t or tier < 1 or tier > #Data.WorkerTiers then return nil end
	if W.BlueprintRaw[tier] then return {[t.output]=W.BlueprintRaw[tier]} end
	return {[W.Press[t.output].condensed]=W.BlueprintCondensed[tier]}
end
-- Tier upgrade cost: the original ladder (tiers 1-3 stay cheap); from tier 4
-- an upgrade also spends the worker type's own Condensed output, exactly the
-- blueprint's Condensed cost, so an upgrade is never a cheaper unique craft.
function W.upgradeCost(tier, typeId)
	local cost = {Timber=5 * tier, Ore=3 * tier}
	if tier >= 4 then
		cost.AlloyIngot = 4 * (tier - 3); cost.AetherIngot = 2 * (tier - 3)
		local blueprint = typeId and W.TypeById[typeId] and W.blueprintCost(typeId, tier)
		for id, n in pairs(blueprint or {}) do cost[id] = (cost[id] or 0) + n end
	end
	return cost
end
-- Fleet caps (pure): reason a worker in `slot` may not run type `typeId`
-- given the other workers in `fleet` (array of {resource=typeId}), or nil.
-- With countAll=false only earlier slots count (used to idle excess legacy
-- workers in slot order).
function W.capReason(fleet, slot, typeId, countAll)
	local t = W.TypeById[typeId]
	if not t then return "Unknown worker type." end
	local same, combat = 0, 0
	for i, other in ipairs(fleet) do
		if i ~= slot and (countAll or i < slot) and type(other) == "table" then
			if other.resource == typeId then same += 1 end
			local o = W.TypeById[other.resource]
			if o and o.kind == "combat" then combat += 1 end
		end
	end
	if same >= W.MAX_PER_TYPE then return "At most "..W.MAX_PER_TYPE.." "..t.name.." workers at once." end
	if t.kind == "combat" and combat >= W.MAX_COMBAT then return "At most "..W.MAX_COMBAT.." combat workers at once." end
	return nil
end
function W.buildCost(slot) return {Timber=5 * slot, Ore=3 * slot} end
end
-- End Workers depth section.

------------------------------------------------------------------------------
-- Pets depth
-- Rarities per species (Common..Legendary, stats scaled from the species'
-- base rarity), 2-3 abilities per species unlocking by rarity/level with real
-- effects (stats, skill XP, slayer-family bonuses, garden growth, doubled
-- harvests, extra crafts), held items, per-rarity XP curves, Pet Candy, the
-- Roost (timed rarity upgrades for coins + materials), ten new species,
-- OSRS-style skilling pet drops and companion body plans (pets.client.lua).
-- Instance fields (all optional; older pets read as their species' rarity):
--   pet = {id, level, xp, rarity, item = heldItemId, candy = uses}
--   p.petUpgrade = {pet = <pet table>, from, to, ends}
------------------------------------------------------------------------------
do
local PD = {}
Data.PetDepth = PD
PD.RARITIES = {"Common","Uncommon","Rare","Epic","Legendary"}
PD.MAX_RARITY = "Legendary"
-- Stats scale from the species' base rarity (a pet at its base rarity keeps its
-- exact perLevel numbers); ability values use an absolute rarity multiplier.
PD.STAT_MULT = {Common=0.55,Uncommon=0.7,Rare=0.85,Epic=1,Legendary=1.2}
PD.ABILITY_MULT = {Common=0.6,Uncommon=0.7,Rare=0.8,Epic=0.9,Legendary=1}
-- XP to next level = floor(100 * level^1.55 * XP_MULT[rarity]) (totals to 100:
-- Common ~4.9M ... Legendary ~21.9M, the SkyBlock spread).
PD.XP_MULT = {Common=1,Uncommon=1.5,Rare=2.2,Epic=3.2,Legendary=4.5}
-- Pet XP share of a skill grant: its own skill, a skill of the same category, any other.
PD.SHARE = {match=1,category=0.5,other=0.25}
PD.TAMING_SHARE = 0.1 -- player Taming XP per pet XP point earned from skills
PD.CANDY_MAX = 10 -- Pet Candy uses per pet, ever
PD.SKILL_PET_XP = 400000 -- skilling pet: chance per XP point = 1 / SKILL_PET_XP (x Pet Luck)
PD.SKILL_PET_STEP = 10000 -- XP banked per skill before one roll (rolls never touch small grants)
PD.UPGRADE_SLOTS = 1

function PD.rank(rarity)
	local def = type(rarity) == "string" and Data.Rarity[rarity]
	return def and def.rank or 0
end
function PD.validRarity(rarity)
	return type(rarity) == "string" and PD.STAT_MULT[rarity] ~= nil
end
function PD.nextRarity(rarity)
	local rank = PD.rank(rarity)
	if rank < 1 or rank >= PD.rank(PD.MAX_RARITY) then return nil end
	return PD.RARITIES[rank + 1]
end
local function clampLevel(level)
	level = tonumber(level) or 1
	if level ~= level then level = 1 end
	return math.clamp(math.floor(level), 1, Data.PET_MAX_LEVEL)
end
PD.clampLevel = clampLevel

-- XP curves --------------------------------------------------------------------
function PD.xpToNext(level, rarity)
	return math.floor(100 * math.max(1, tonumber(level) or 1) ^ 1.55 * (PD.XP_MULT[rarity] or 1))
end
Data.petXpToNext = PD.xpToNext -- every caller reads Data.petXpToNext at call time
PD.cumulative = {}
for rarity in pairs(PD.XP_MULT) do
	local t = {0}
	for level = 1, Data.PET_MAX_LEVEL - 1 do t[level + 1] = t[level] + PD.xpToNext(level, rarity) end
	PD.cumulative[rarity] = t
end
function PD.totalXpToMax(rarity) return PD.cumulative[rarity][Data.PET_MAX_LEVEL] end
-- Lifetime XP of a pet (level + progress inside the level).
function PD.totalXp(level, xp, rarity)
	local t = PD.cumulative[rarity] or PD.cumulative.Common
	level = clampLevel(level)
	local inLevel = math.max(0, tonumber(xp) or 0)
	if level >= Data.PET_MAX_LEVEL then inLevel = 0 end
	return t[level] + inLevel
end
-- Level and progress for a lifetime XP total (maxed pets keep xp = 0).
function PD.fromTotal(total, rarity)
	local t = PD.cumulative[rarity] or PD.cumulative.Common
	total = math.max(0, tonumber(total) or 0)
	local lo, hi = 1, Data.PET_MAX_LEVEL
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if t[mid] <= total then lo = mid else hi = mid - 1 end
	end
	if lo >= Data.PET_MAX_LEVEL then return Data.PET_MAX_LEVEL, 0 end
	return lo, total - t[lo]
end
-- Taming: +5% pet XP per 5 levels (max +75%), +2.5% pet stats per 10 levels.
function PD.tamingXpBonus(tamingLevel) return math.min(0.75, math.floor((tonumber(tamingLevel) or 1) / 5) * 0.05) end
function PD.tamingStatBonus(tamingLevel) return math.floor((tonumber(tamingLevel) or 1) / 10) * 0.025 end
function PD.statScale(def, rarity, tamingLevel)
	local base = PD.STAT_MULT[def and def.rarity] or 1
	return (PD.STAT_MULT[rarity] or base) / base * (1 + PD.tamingStatBonus(tamingLevel))
end

-- Abilities -------------------------------------------------------------------
-- kind: xp {skills, per} = +per*L % player XP in those skills
--       stat {stat, per} = +per*L stat (computeStats)
--       family {line, per} = +per*L % coins, slayer progress and Magic Find vs that slayer line
--       garden {per} = +per*L % Verdant Garden growth rate
--       gather {skill, per} = per*L % chance to double a harvest of that skill
--       craft {skills, per} = per*L % chance of an extra output when crafting
-- L = pet level x ABILITY_MULT[rarity]; unlock: rarity (min) and optional level.
local function xp(name, skills, per, rarity, level) return {name=name,kind="xp",skills=skills,per=per,rarity=rarity or "Common",level=level} end
local function stat(name, s, per, rarity, level) return {name=name,kind="stat",stat=s,per=per,rarity=rarity or "Common",level=level} end
local function family(name, line, per, rarity, level) return {name=name,kind="family",line=line,per=per,rarity=rarity or "Common",level=level} end
local function garden(name, per, rarity, level) return {name=name,kind="garden",per=per,rarity=rarity or "Common",level=level} end
local function gather(name, skill, per, rarity, level) return {name=name,kind="gather",skill=skill,per=per,rarity=rarity or "Common",level=level} end
local function craft(name, skills, per, rarity, level) return {name=name,kind="craft",skills=skills,per=per,rarity=rarity or "Common",level=level} end
PD.Abilities = {
	Tidewing={xp("Sky Diver",{"Fishing"},0.1),stat("Spray Sense","seaCreatureChance",0.03,"Rare"),gather("Undertow","Fishing",0.15,"Legendary")},
	Burrowmole={xp("Deep Digger",{"Mining"},0.1),stat("Tunnel Sense","miningFortune",0.3,"Rare"),gather("Twin Seam","Mining",0.15,"Legendary")},
	Mossback={xp("Rooted",{"Farming"},0.1),garden("Green Shell",0.15,"Rare"),stat("Old Growth","farmingFortune",0.3,"Epic",50)},
	Sapling={xp("Grove Song",{"Woodcutting"},0.1),stat("Rootspeak","foragingFortune",0.3,"Rare"),gather("Twin Bough","Woodcutting",0.15,"Legendary")},
	Emberfox={xp("Kindled Fury",{"Combat"},0.1),family("Bramble Bane","Bramble",0.3,"Rare"),stat("Ember Heart","damagePercent",0.1,"Legendary")},
	Gloomwing={stat("Echo Hunt","magicFind",0.05),family("Gloom Stalker","Gloom",0.3,"Rare"),stat("Night Wings","critChance",0.1,"Legendary")},
	Aurelion={xp("Starborn Pride",{"Combat"},0.2),stat("Radiance","damagePercent",0.08,"Rare"),family("Sovereign Roar","Tempest",0.3,"Legendary")},
	Cindercrab={xp("Forge Heat",{"Smithing"},0.1),craft("Slag Sifter",{"Smithing"},0.1,"Rare"),stat("Molten Shell","defense",0.5,"Epic",30)},
	Pearlwhisker={xp("Tide Sense",{"Fishing"},0.1),stat("Pearl Diver","fishingFortune",0.4,"Rare"),stat("Deepcall","seaCreatureChance",0.05,"Epic",25)},
	Puffkin={xp("Burrow Sense",{"Hunter"},0.1),stat("Soft Step","trapLuck",0.1,"Rare")},
	Glimmerfly={xp("Glint Trail",{"Hunter"},0.1),stat("Luminous Lure","huntingFortune",0.3,"Rare"),stat("Fae Fortune","petLuck",0.1,"Legendary")},
	Stormkid={xp("Storm Hooves",{"Hunter"},0.15),stat("Thunder Snare","trapLuck",0.12,"Rare"),stat("Gale Charge","speed",0.2,"Epic",40)},
	Gustling={xp("Tailwind",{"Agility"},0.1),stat("Sure Gust","surefoot",0.1,"Rare"),stat("Updraft","speed",0.3,"Legendary")},
	Shardling={stat("Crownbound","magicFind",0.08),stat("Shard Edge","damagePercent",0.1,"Rare"),stat("Crown Ward","defense",0.6,"Legendary")},
	Hearthpup={xp("Taste Tester",{"Cooking"},0.1),craft("Second Helping",{"Cooking"},0.15,"Rare"),stat("Warm Belly","health",1,"Epic",30)},
	Vialtoad={xp("Brew Lore",{"Alchemy"},0.1),craft("Double Distill",{"Alchemy"},0.12,"Rare"),stat("Toxin Skin","abilityDamage",0.1,"Legendary")},
	Timberkit={xp("Measure Twice",{"Carpentry"},0.1),craft("Spare Plank",{"Carpentry"},0.12,"Rare"),gather("Gnawing","Woodcutting",0.1,"Epic",40)},
	Fletchwren={xp("Feather Sort",{"Fletching"},0.1),craft("Spare Shafts",{"Fletching"},0.15,"Rare"),stat("Keen Eye","rangedAccuracy",0.4,"Epic",30)},
	Runemoth={xp("Dust Wings",{"Glyphcraft"},0.1),craft("Echo Glyph",{"Glyphcraft"},0.12,"Rare"),stat("Arcane Flutter","abilityDamage",0.15,"Legendary")},
	Starquill={xp("Night Study",{"Magic"},0.12),stat("Mana Font","intelligence",1,"Rare"),family("Tempest Hex","Tempest",0.25,"Legendary")},
	Thornquill={xp("Quill Volley",{"Ranged"},0.12),family("Bramble Kin","Bramble",0.25,"Rare"),stat("Barbed Shot","rangedStrength",0.4,"Legendary")},
	Bloomsnail={garden("Slow and Steady",0.2),xp("Mulch Trail",{"Farming"},0.1,"Rare"),gather("Blossom Shell","Farming",0.15,"Epic",50)},
	Bellwisp={stat("Lantern Bell","seaCreatureChance",0.04),stat("Brine Glow","fishingFortune",0.3,"Rare"),xp("Deep Chime",{"Fishing"},0.12,"Legendary")},
	Skipperling={xp("Spring Step",{"Agility"},0.1),stat("Steady Feet","surefoot",0.1,"Rare")},
}
for _, list in pairs(PD.Abilities) do
	for i, a in ipairs(list) do a.index = i; a.id = a.name:gsub("[^%w]", "") end
end
-- Generic fallback for species added later without abilities: +XP in their skill.
function PD.abilitiesFor(def)
	if not def then return {} end
	local list = PD.Abilities[def.id]
	if list then return list end
	list = {xp("Kinship", {def.skill}, 0.1)}
	list[1].index, list[1].id = 1, "Kinship"
	PD.Abilities[def.id] = list
	return list
end
function PD.abilityUnlocked(ability, level, rarity)
	return PD.rank(rarity) >= PD.rank(ability.rarity or "Common") and clampLevel(level) >= (ability.level or 1)
end
function PD.abilityValue(ability, level, rarity)
	local v = ability.per * clampLevel(level) * (PD.ABILITY_MULT[rarity] or 1)
	return math.floor(v * 100 + 0.5) / 100
end
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end
function PD.familyName(line)
	local def = Data.Slayers[line]
	return def and def.line or tostring(line)
end
function PD.abilityText(ability, value)
	local v = tostring(round1(value))
	local k = ability.kind
	if k == "xp" then return "+"..v.."% "..table.concat(ability.skills, "/").." XP" end
	if k == "stat" then
		local sdef = Data.Stats[ability.stat]
		if ability.stat == "damagePercent" then return "+"..v.."% damage" end
		return "+"..v..(if sdef and sdef.percent then "%" else "").." "..(sdef and sdef.name or ability.stat)
	end
	if k == "family" then return "+"..v.."% coins, slayer progress and Magic Find vs "..PD.familyName(ability.line).." foes" end
	if k == "garden" then return "+"..v.."% garden growth" end
	if k == "gather" then return v.."% chance to double "..ability.skill.." harvests" end
	if k == "craft" then return v.."% chance of an extra "..table.concat(ability.skills, "/").." craft" end
	return ""
end
function PD.unlockText(ability)
	local parts = {ability.rarity or "Common"}
	if ability.level then table.insert(parts, "Lv "..ability.level) end
	return table.concat(parts, " · ")
end
-- Ability rows for one pet: {id, name, kind, unlocked, value, text, requires}.
function PD.abilityView(def, level, rarity)
	local out = {}
	for _, a in ipairs(PD.abilitiesFor(def)) do
		local value = PD.abilityValue(a, level, rarity)
		table.insert(out, {id=a.id,name=a.name,kind=a.kind,unlocked=PD.abilityUnlocked(a, level, rarity),value=value,text=PD.abilityText(a, value),requires=PD.unlockText(a)})
	end
	return out
end
-- Aggregated unlocked effects of one pet:
-- {stats={}, xp={[skill]=%}, family={[line]=%}, garden=%, gather={[skill]=%}, craft={[skill]=%}}
function PD.effects(def, level, rarity)
	local fx = {stats={},xp={},family={},garden=0,gather={},craft={}}
	for _, a in ipairs(PD.abilitiesFor(def)) do
		if PD.abilityUnlocked(a, level, rarity) then
			local v = PD.abilityValue(a, level, rarity)
			if a.kind == "xp" then for _, s in ipairs(a.skills) do fx.xp[s] = (fx.xp[s] or 0) + v end
			elseif a.kind == "stat" then fx.stats[a.stat] = (fx.stats[a.stat] or 0) + v
			elseif a.kind == "family" then fx.family[a.line] = (fx.family[a.line] or 0) + v
			elseif a.kind == "garden" then fx.garden += v
			elseif a.kind == "gather" then fx.gather[a.skill] = (fx.gather[a.skill] or 0) + v
			elseif a.kind == "craft" then for _, s in ipairs(a.skills) do fx.craft[s] = (fx.craft[s] or 0) + v end end
		end
	end
	return fx
end

-- New species -----------------------------------------------------------------
for _, pet in ipairs({
	{id="Hearthpup",name="Hearthpup",skill="Cooking",rarity="Uncommon",color="D9822B",perLevel={health=0.6,intelligence=0.1}},
	{id="Vialtoad",name="Vialtoad",skill="Alchemy",rarity="Rare",color="8E5BB5",perLevel={intelligence=0.5,defense=0.1}},
	{id="Timberkit",name="Timberkit",skill="Carpentry",rarity="Uncommon",color="A0784F",perLevel={health=0.4,foragingFortune=0.3}},
	{id="Fletchwren",name="Fletchwren",skill="Fletching",rarity="Uncommon",color="A7B66B",perLevel={rangedStrength=0.3,speed=0.1}},
	{id="Runemoth",name="Runemoth",skill="Glyphcraft",rarity="Rare",color="9A7FD1",perLevel={intelligence=0.6}},
	{id="Starquill",name="Starquill Owl",skill="Magic",rarity="Epic",color="5C7AEA",perLevel={intelligence=1,abilityDamage=0.05}},
	{id="Thornquill",name="Thornquill",skill="Ranged",rarity="Rare",color="6FA35A",perLevel={rangedStrength=0.5,defense=0.2}},
	{id="Bloomsnail",name="Bloomsnail",skill="Farming",rarity="Epic",color="E9A3C9",perLevel={farmingFortune=0.6,health=0.4}},
	{id="Bellwisp",name="Bellwisp",skill="Fishing",rarity="Rare",color="8EE3F0",perLevel={seaCreatureChance=0.06,intelligence=0.3}},
	{id="Skipperling",name="Skipperling",skill="Agility",rarity="Common",color="9BD67E",perLevel={speed=0.2,surefoot=0.05}},
}) do
	table.insert(Data.Pets, pet)
	Data.PetById[pet.id] = pet
	item(pet.id.."Pet",{name=pet.name.." Pet",kind="pet",pet=pet.id,rarity=pet.rarity,color=pet.color,value=200*Data.Rarity[pet.rarity].rank^2,description="Summon from your pet menu."})
end
PD.NEW_SPECIES = {"Hearthpup","Vialtoad","Timberkit","Fletchwren","Runemoth","Starquill","Thornquill","Bloomsnail","Bellwisp","Skipperling"}
-- Every species: a real ability summary replaces the old flavour text.
for _, pet in ipairs(Data.Pets) do
	local list = PD.abilitiesFor(pet)
	local first = list[1]
	local names = {}
	for _, a in ipairs(list) do table.insert(names, a.name) end
	pet.ability = first.name..": up to "..PD.abilityText(first, PD.abilityValue(first, Data.PET_MAX_LEVEL, PD.MAX_RARITY))
	pet.abilityNames = names
	local itemDef = Data.Items[pet.id.."Pet"]
	if itemDef then itemDef.description = "Summon from your pet menu. Abilities: "..table.concat(names, ", ").."." end
end

-- Held items, candy and the Tier Boost --------------------------------------------
-- held: xp = {category|"all" -> pet XP %}, stats, garden (% growth).
PD.HeldItems = {
	ForagersPouch={name="Forager's Pouch",rarity="Uncommon",color="8CB369",xp={gathering=20},text="+20% pet XP from gathering skills"},
	ArtisansThimble={name="Artisan's Thimble",rarity="Uncommon",color="C9A227",xp={production=20},text="+20% pet XP from production skills"},
	WarbandTag={name="Warband Tag",rarity="Uncommon",color="C8553D",xp={combat=20},text="+20% pet XP from combat skills"},
	WayfarersBell={name="Wayfarer's Bell",rarity="Uncommon",color="62C2B0",xp={support=25},text="+25% pet XP from support skills"},
	EverbloomRibbon={name="Everbloom Ribbon",rarity="Epic",color="E9A3C9",xp={all=12},text="+12% pet XP from every skill"},
	IronbarkCollar={name="Ironbark Collar",rarity="Rare",color="7A6A53",stats={defense=25,health=20},text="+25 Defense, +20 Health"},
	FangstoneCollar={name="Fangstone Collar",rarity="Rare",color="D4A84B",stats={strength=12,critDamage=10},text="+12 Strength, +10% Crit Damage"},
	SwiftwindAnklet={name="Swiftwind Anklet",rarity="Uncommon",color="CFEFFF",stats={speed=12},text="+12 Speed"},
	OwlglassLens={name="Owlglass Lens",rarity="Rare",color="5C7AEA",stats={intelligence=40},text="+40 Intelligence"},
	GlimmerClover={name="Glimmer Clover",rarity="Epic",color="55FF55",stats={magicFind=6,petLuck=2},text="+6 Magic Find, +2 Pet Luck"},
	TidepearlPendant={name="Tidepearl Pendant",rarity="Epic",color="8EE3F0",stats={seaCreatureChance=2,fishingFortune=15},text="+2% Sea Creature Chance, +15 Fishing Fortune"},
	VerdantSprig={name="Verdant Sprig",rarity="Rare",color="6BBF59",stats={farmingFortune=20},garden=8,text="+20 Farming Fortune, +8% garden growth"},
}
PD.HELD_ORDER = {"ForagersPouch","ArtisansThimble","WarbandTag","WayfarersBell","EverbloomRibbon","IronbarkCollar","FangstoneCollar","SwiftwindAnklet","OwlglassLens","GlimmerClover","TidepearlPendant","VerdantSprig"}
for id, h in pairs(PD.HeldItems) do
	h.id = id
	item(id,{name=h.name,kind="petitem",petItem="held",rarity=h.rarity,color=h.color,stats=h.stats,value=150*Data.Rarity[h.rarity].rank^2,
		description="Pet held item: "..h.text..". Equip it on a pet from your pet menu."})
end
PD.Candies = {PetCandy={xp=20000},StarlitCandy={xp=250000}}
-- Sell values sit at or below their Hearth inputs (no craft-and-sell mint):
-- Pet Candy 150 <= 162, Starlit 1400 <= 1470 (4 Pet Candy, 2 Star Fragments, 6 Aether Lotus).
item("PetCandy",{name="Pet Candy",kind="petitem",petItem="candy",rarity="Uncommon",color="F7A1C4",value=150,
	description="Feed to a pet for +20,000 pet XP. Each pet can eat "..PD.CANDY_MAX.." candies in its life."})
item("StarlitCandy",{name="Starlit Pet Candy",kind="petitem",petItem="candy",rarity="Epic",color="F2D27A",value=1400,
	description="Feed to a pet for +250,000 pet XP. Counts toward the "..PD.CANDY_MAX.."-candy limit."})
item("AscendantPrism",{name="Ascendant Prism",kind="petitem",petItem="tierBoost",rarity="Legendary",color="FFAA00",value=20000,
	description="Tier Boost: raises a pet's rarity by one tier at once (up to Legendary). Consumed."})
function PD.held(id) return type(id) == "string" and PD.HeldItems[id] or nil end
-- Pet XP multiplier bonus (fraction) a held item gives for XP of `skill`.
function PD.heldXpBonus(id, skill)
	local h = PD.held(id)
	if not h or not h.xp then return 0 end
	local cat = Data.Skills[skill] and Data.Skills[skill].category
	return ((h.xp.all or 0) + (cat and h.xp[cat] or 0)) / 100
end

-- Sources -----------------------------------------------------------------------
-- Crafted pet gear trains Taming at the Workbench; candy is cooked at the Hearth.
for id, r in pairs({
	IronbarkCollar={level=10,costs={BeastHide=40,EmberoakLog=24,SunsteelIngot=4}},
	VerdantSprig={level=15,costs={Glowcap=48,Herb=64,ArcaneDust=24}},
	FangstoneCollar={level=20,costs={BeastHide=64,SpiderSilk=48,SunsteelIngot=8}},
	OwlglassLens={level=25,costs={StormFeather=32,ArcaneDust=64,Glassfin=24}},
	SwiftwindAnklet={level=12,costs={StormFeather=16,DownyPelt=24,WindpineLog=32}},
	EverbloomRibbon={level=40,costs={Moonbloom=48,GlintEssence=32,StarFragment=2}},
}) do
	recipe(id,{skill="Taming",level=r.level,xp=60+r.level*6,costs=r.costs,repeatable=true,station="Workbench",category="Pet Gear"})
end
recipe("PetCandy",{skill="Cooking",level=20,xp=90,costs={Sunwheat=6,Duskberry=4,Starfruit=1},repeatable=true,station="Hearth",category="Pet Treats"})
recipe("StarlitCandy",{skill="Cooking",level=60,xp=600,costs={PetCandy=4,StarFragment=2,AetherLotus=6},repeatable=true,station="Hearth",category="Pet Treats"})
-- No pet recipe mints coins: a crafted pet item sells for at most its inputs
-- (held-item values come from a rarity formula, so clamp crafted ones here).
PD.RECIPE_CATEGORIES = {["Pet Gear"]=true,["Pet Treats"]=true}
function PD.recipeInputValue(rec)
	local total = 0
	for id, n in pairs(rec.costs) do total += (Data.Items[id] and Data.Items[id].value or 0) * n end
	return total
end
for _, rec in pairs(Data.Recipes) do
	if PD.RECIPE_CATEGORIES[rec.category] then
		local out = Data.Items[rec.output]
		local cap = math.floor(PD.recipeInputValue(rec) / (rec.amount or 1))
		if out.value > cap then out.value = cap end
	end
end
-- The Roost keeper sells starter gear and candy for coins.
PD.Shop = {
	{item="PetCandy",coins=8000},
	{item="ForagersPouch",coins=20000},
	{item="ArtisansThimble",coins=20000},
	{item="WarbandTag",coins=20000},
	{item="WayfarersBell",coins=20000},
	{item="SwiftwindAnklet",coins=15000},
}
PD.ShopByItem = {}
for _, e in ipairs(PD.Shop) do PD.ShopByItem[e.item] = e end
-- Drops: rare held items, Starlit Candy, Ascendant Prisms and the Bellwisp.
local function addDrop(list, row) if type(list) == "table" then table.insert(list, row) end end
addDrop(Data.Monsters.GloomfangSpider and Data.Monsters.GloomfangSpider.drops, {item="GlimmerClover",chance=0.003,min=1,max=1})
addDrop(Data.Monsters.BarkStalker and Data.Monsters.BarkStalker.drops, {item="FangstoneCollar",chance=0.004,min=1,max=1})
addDrop(Data.SeaCreatures.DriftbellJelly and Data.SeaCreatures.DriftbellJelly.drops, {item="BellwispPet",chance=0.003,min=1,max=1})
addDrop(Data.SeaCreatures.InkveilDrifter and Data.SeaCreatures.InkveilDrifter.drops, {item="TidepearlPendant",chance=0.01,min=1,max=1})
for _, line in ipairs({"Bramble","Gloom","Tempest"}) do
	local tiers = Data.Slayers[line] and Data.Slayers[line].tiers
	if tiers then
		addDrop(tiers[3] and tiers[3].drops, {item="StarlitCandy",chance=0.04,min=1,max=1})
		addDrop(tiers[4] and tiers[4].drops, {item="StarlitCandy",chance=0.1,min=1,max=1})
		addDrop(tiers[4] and tiers[4].drops, {item="AscendantPrism",chance=0.008,min=1,max=1})
	end
end
-- Skilling pets (OSRS-style): every XP grant in the skill may roll its pet.
PD.SkillPets = {Cooking="HearthpupPet",Alchemy="VialtoadPet",Carpentry="TimberkitPet",Fletching="FletchwrenPet",Glyphcraft="RunemothPet",
	Magic="StarquillPet",Ranged="ThornquillPet",Farming="BloomsnailPet",Agility="SkipperlingPet"}
function PD.skillPetChance(xpAmount, petLuck)
	local x = math.max(0, tonumber(xpAmount) or 0)
	return math.min(0.05, x / PD.SKILL_PET_XP * (1 + math.max(0, tonumber(petLuck) or 0) / 100))
end

-- The Roost: timed rarity upgrades -----------------------------------------------
PD.KEEPER = "Wren Halloway, Roost Keeper"
PD.Upgrade = {
	Uncommon={coins=5000,seconds=3600,items={ArcaneDust=32},material=16},
	Rare={coins=25000,seconds=6*3600,items={ArcaneDust=96},material=48},
	Epic={coins=150000,seconds=24*3600,items={ArcaneDust=192,VoidEssence=24},material=128},
	Legendary={coins=750000,seconds=72*3600,items={StarFragment=8,VoidEssence=96},material=256},
}
-- Species material by skill (the pet's own trade).
PD.UpgradeMaterial = {Combat="BeastHide",Mining="SunsteelOre",Woodcutting="EmberoakLog",Fishing="Stormeel",Farming="Sunwheat",Smithing="SunsteelIngot",
	Hunter="DownyPelt",Agility="Skymark",Cooking="Duskberry",Alchemy="Glowcap",Carpentry="WindpineLog",Fletching="StormFeather",Glyphcraft="GlintEssence",
	Magic="ArcaneDust",Ranged="StormFeather"}
-- Cost to raise a pet of species def from `rarity` one tier: {to, coins, seconds, items} or nil.
function PD.upgradeCost(def, rarity)
	local to = PD.nextRarity(rarity)
	if not def or not to then return nil end
	local u = PD.Upgrade[to]
	local items = table.clone(u.items)
	local mat = PD.UpgradeMaterial[def.skill] or "ArcaneDust"
	items[mat] = (items[mat] or 0) + u.material
	return {to=to,coins=u.coins,seconds=u.seconds,items=items}
end

-- Companion body plans (pets.client.lua) ------------------------------------------
-- form: flyer (wings flap, hovers), quad (four legs, hops), shell (low and slow),
-- float (orb and tendrils, bobs), hopper (round body, big feet).
PD.Looks = {
	Tidewing={form="flyer",accent="CFEFFF"},Burrowmole={form="quad",accent="E8C9A0"},Mossback={form="shell",accent="8CB369"},
	Sapling={form="float",accent="B5E48C"},Emberfox={form="quad",accent="FFD6A5"},Gloomwing={form="flyer",accent="B8C0FF"},
	Aurelion={form="quad",accent="FFF3B0"},Cindercrab={form="shell",accent="FFB703"},Pearlwhisker={form="quad",accent="F1E3D3"},
	Puffkin={form="hopper",accent="FFFFFF"},Glimmerfly={form="flyer",accent="FFFFFF"},Stormkid={form="quad",accent="E0E6F0"},
	Gustling={form="float",accent="FFFFFF"},Shardling={form="float",accent="FFF3B0"},Hearthpup={form="quad",accent="FFE5B4"},
	Vialtoad={form="hopper",accent="C3F584"},Timberkit={form="quad",accent="E8C9A0"},Fletchwren={form="flyer",accent="F4F1DE"},
	Runemoth={form="flyer",accent="E0C3FC"},Starquill={form="flyer",accent="FFF3B0"},Thornquill={form="shell",accent="3B5249"},
	Bloomsnail={form="shell",accent="FFD6E8"},Bellwisp={form="float",accent="FFFFFF"},Skipperling={form="hopper",accent="E9FFDB"},
}
PD.MAX_PARTS = 15
PD.FLOATING = {flyer=true,float=true}
local function part(name, shape, size, offset, color, extra)
	local p = {name=name,shape=shape,size=size,offset=offset,color=color}
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return p
end
-- Parts in pet space (studs, +Z forward, origin at the body centre). shape:
-- Ball | Block | Cylinder | Wedge. flap = "L"/"R" wing; neon = glowing trim.
function PD.bodyPlan(speciesId, rarity)
	local def = Data.PetById[speciesId]
	local look = PD.Looks[speciesId] or {form="float",accent="FFFFFF"}
	local c, a = def and def.color or "CCCCCC", look.accent
	local form = look.form
	local parts = {}
	local function add(...) table.insert(parts, part(...)) end
	if form == "flyer" then
		add("Body","Ball",{1.1,1,1.3},{0,0,0},c)
		add("Head","Ball",{0.8,0.8,0.8},{0,0.55,0.55},c)
		add("Beak","Wedge",{0.2,0.2,0.3},{0,0.5,1},"F2C14E")
		add("WingL","Block",{1.2,0.1,0.7},{-0.95,0.15,0},a,{flap="L"})
		add("WingR","Block",{1.2,0.1,0.7},{0.95,0.15,0},a,{flap="R"})
		add("Tail","Wedge",{0.5,0.12,0.5},{0,0,-0.8},a)
		add("EyeL","Ball",{0.16,0.16,0.16},{-0.2,0.65,0.9},"10141A")
		add("EyeR","Ball",{0.16,0.16,0.16},{0.2,0.65,0.9},"10141A")
	elseif form == "quad" then
		add("Body","Block",{0.9,0.8,1.5},{0,0,0},c)
		add("Head","Ball",{0.85,0.8,0.8},{0,0.45,0.85},c)
		add("Snout","Block",{0.35,0.3,0.35},{0,0.35,1.3},a)
		add("EarL","Wedge",{0.2,0.4,0.2},{-0.25,0.95,0.8},c)
		add("EarR","Wedge",{0.2,0.4,0.2},{0.25,0.95,0.8},c)
		add("Tail","Cylinder",{0.7,0.22,0.22},{0,0.3,-0.95},a,{rot={0,90,30}})
		add("LegFL","Block",{0.22,0.5,0.22},{-0.3,-0.55,0.5},c)
		add("LegFR","Block",{0.22,0.5,0.22},{0.3,-0.55,0.5},c)
		add("LegBL","Block",{0.22,0.5,0.22},{-0.3,-0.55,-0.5},c)
		add("LegBR","Block",{0.22,0.5,0.22},{0.3,-0.55,-0.5},c)
		add("EyeL","Ball",{0.14,0.14,0.14},{-0.2,0.6,1.2},"10141A")
		add("EyeR","Ball",{0.14,0.14,0.14},{0.2,0.6,1.2},"10141A")
	elseif form == "shell" then
		add("Shell","Ball",{1.4,0.9,1.5},{0,0.1,-0.1},c)
		add("Rim","Cylinder",{0.12,1.5,1.5},{0,-0.25,-0.1},a,{rot={0,0,90}})
		add("Head","Ball",{0.6,0.55,0.6},{0,0,0.85},a)
		add("FootL","Block",{0.3,0.25,0.4},{-0.5,-0.4,0.4},a)
		add("FootR","Block",{0.3,0.25,0.4},{0.5,-0.4,0.4},a)
		add("EyeL","Ball",{0.12,0.12,0.12},{-0.15,0.1,1.12},"10141A")
		add("EyeR","Ball",{0.12,0.12,0.12},{0.15,0.1,1.12},"10141A")
	elseif form == "hopper" then
		add("Body","Ball",{1.1,1,1.1},{0,0,0},c)
		add("Belly","Ball",{0.8,0.7,0.5},{0,-0.15,0.35},a)
		add("FootL","Ball",{0.4,0.2,0.6},{-0.35,-0.5,0.2},c)
		add("FootR","Ball",{0.4,0.2,0.6},{0.35,-0.5,0.2},c)
		add("EyeL","Ball",{0.22,0.22,0.22},{-0.25,0.4,0.42},"10141A")
		add("EyeR","Ball",{0.22,0.22,0.22},{0.25,0.4,0.42},"10141A")
	else -- float
		add("Orb","Ball",{1.1,1.1,1.1},{0,0,0},c,{transparency=0.25})
		add("Core","Ball",{0.5,0.5,0.5},{0,0,0},a,{neon=true})
		add("TendrilA","Cylinder",{0.7,0.12,0.12},{-0.25,-0.75,0},c,{rot={0,0,90}})
		add("TendrilB","Cylinder",{0.7,0.12,0.12},{0.25,-0.75,0},c,{rot={0,0,90}})
		add("TendrilC","Cylinder",{0.7,0.12,0.12},{0,-0.75,0.25},c,{rot={0,0,90}})
		add("EyeL","Ball",{0.14,0.14,0.14},{-0.18,0.12,0.5},"10141A")
		add("EyeR","Ball",{0.14,0.14,0.14},{0.18,0.12,0.5},"10141A")
	end
	local rank = PD.rank(rarity)
	if rank >= 4 then add("Halo","Cylinder",{0.06,0.9,0.9},{0,1.25,0},Data.Rarity[rarity].color,{rot={0,0,90},neon=true}) end
	if rank >= 5 then add("Gem","Ball",{0.22,0.22,0.22},{0,1.25,0},"FFFFFF",{neon=true}) end
	-- Rarity grows the companion a little: Common 0.8 ... Legendary 1.12.
	return {form=form,floating=PD.FLOATING[form] == true,scale=0.72 + 0.08 * math.max(1, rank),parts=parts}
end
-- Verdant Garden: ctx.petGrowth (fraction, from the summoned pet's growth
-- abilities and held item; server Garden.ctx) adds to the plot rate, still
-- within G.MAX_RATE so the garden balance invariants hold.
do
	local G = Data.Garden
	local baseRate = G.rate
	function G.rate(plot, ctx, watered)
		local r = baseRate(plot, ctx, watered)
		local boost = type(ctx) == "table" and tonumber(ctx.petGrowth) or 0
		if boost ~= boost or boost <= 0 then return r end
		return math.min(G.MAX_RATE, r + boost)
	end
end
-- Player attribute ActivePet = "speciesId:rarity:level" ("" when none).
function PD.attribute(speciesId, rarity, level) return speciesId..":"..rarity..":"..clampLevel(level) end
function PD.parseAttribute(value)
	if type(value) ~= "string" then return nil end
	local id, rarity, level = value:match("^(%w+):(%a+):(%d+)$")
	if not id or not Data.PetById[id] or not PD.validRarity(rarity) then return nil end
	return id, rarity, clampLevel(tonumber(level))
end
end
-- End Pets depth section.

------------------------------------------------------------------------------
-- Dungeon classes (Dungeon Classes team; append-only section).
-- Five Observatory classes (Aegis tank, Mender healer, Riftblade melee,
-- Starshot ranged, Arcanist magic) with dungeon-only passives, one active
-- ability (cooldown) and an ultimate (charges per run); class levels 1-50 with
-- separate XP per class; a team bonus for unique compositions; Secrets and
-- Bonus score components; Floors VI-VII; Master Mode for floors I-V.
-- Pure data + pure rules: expedition.server.lua runs abilities/secrets,
-- server.server.lua (Classes block) persists p.dungeonClasses and pays class XP,
-- verify-dungeon-classes.luau checks every formula here.
--   p.dungeonClasses = {selected=classId|nil, master=bool, xp={[classId]=n},
--     secrets={["floor"]=best found}, masterBest={["floor"]=score}, masterClears={["floor"]=n}}
------------------------------------------------------------------------------
do
local DC = {}
Data.DungeonClasses = DC
DC.MAX_LEVEL = 50
DC.order = {"Aegis","Mender","Riftblade","Starshot","Arcanist"}
-- attack: encounter hit values at class level 1 (the Observatory counts hits,
-- not stat damage). melee/guardian/wisp = prompt strikes; ranged = {damage, recovery}.
-- perLevel: dungeon-only boosts per class level above 1 (damage = extra hit
-- fraction carried between strikes, mitigation = boss/sentinel damage reduction,
-- healing = heal power). See DC.abilityCheck for when each ability is usable.
DC.defs = {
	Aegis={id="Aegis",name="Aegis",role="Tank",color="6C9BD2",glyph="⛨",
		passive="Takes half damage from boss strikes and sentinel counters.",
		attack={melee=1,guardian=1,wisp=1,mitigation=0.5},
		perLevel={damage=0.004,mitigation=0.004,healing=0},
		ability={id="Bulwark",name="Starwall Bulwark",cooldown=30,power=1,empowered=2,
			text="Brace: the next boss strike (two when empowered) hits only you, at your reduced damage, and spares the party."},
		ultimate={id="Bastion",name="Bastion of the Isles",power=2,
			text="The whole party ignores the next 2 boss strikes."},
		feat={id="Absorb",text="Absorb a boss strike for the party"},
		weapon="BastionMaul"},
	Mender={id="Mender",name="Mender",role="Healer",color="7FE3B0",glyph="✚",
		passive="Every strike heals allies within 20 studs of the core.",
		attack={melee=1,guardian=1,wisp=1,heal=3},
		perLevel={damage=0.004,mitigation=0.002,healing=0.02},
		ability={id="MendingLight",name="Mending Light",cooldown=25,power=0.35,empowered=0.5,
			text="Heal every living delver for 35% of their max health (50% empowered)."},
		ultimate={id="SecondDawn",name="Second Dawn",power=1,window=20,
			text="Boss phase: heal the party to full; one fall within 20 s does not count against survival (never stacks)."},
		feat={id="Heal",text="Restore 50 health (allies or yourself) in one run",need=50},
		weapon="DawnmenderWand"},
	Riftblade={id="Riftblade",name="Riftblade",role="Melee",color="E8806A",glyph="⚔",
		passive="Strikes the core, sentinels and wisps for double damage.",
		attack={melee=2,guardian=2,wisp=2},
		perLevel={damage=0.01,mitigation=0.001,healing=0},
		ability={id="Cleave",name="Rift Cleave",cooldown=15,power=2,empowered=3,
			text="Sweep the arena: 2 damage (3 empowered) to every umbral wisp and to the exposed core."},
		ultimate={id="RendingStorm",name="Rending Storm",power=0.1,
			text="Tear 10% of the boss's max HP from an exposed core and 5 HP from every wisp."},
		feat={id="Wisps",text="Destroy 3 umbral wisps in one run (floors without wisps: land a sentinel's final blow)",need=3},
		weapon="Riftcleaver"},
	Starshot={id="Starshot",name="Starshot",role="Ranged",color="9BD67E",glyph="➶",
		passive="Quick ranged shots at the core from 32 studs.",
		attack={melee=1,guardian=1,wisp=1,ranged={damage=1,recovery=1.2}},
		perLevel={damage=0.01,mitigation=0.001,healing=0},
		ability={id="DisruptingShot",name="Disrupting Shot",cooldown=30,power=1,empowered=2,
			text="Fire into a telegraphing boss: the marked strike is cancelled and the core takes 1 damage (2 empowered)."},
		ultimate={id="CometVolley",name="Comet Volley",power=0.06,
			text="Destroy every umbral wisp; with none alive, strike the core for 6% of its max HP."},
		feat={id="Disrupt",text="Cancel a telegraphed boss strike"},
		weapon="StarpiercerLongbow"},
	Arcanist={id="Arcanist",name="Arcanist",role="Magic",color="8FA8FF",glyph="✦",
		passive="Slow ranged bursts at the core; spells hit wisps twice as hard.",
		attack={melee=1,guardian=1,wisp=2,ranged={damage=3,recovery=2.4}},
		perLevel={damage=0.01,mitigation=0.001,healing=0},
		ability={id="Attune",name="Attune",cooldown=20,power=1,empowered=2,
			text="Tune the next resonance prism (two when empowered) in the correct order from the core."},
		ultimate={id="EclipseRift",name="Eclipse Rift",power=1,
			text="Complete the prism sequence at once (opens the hall or breaks the core shield)."},
		feat={id="Attune",text="Attune a prism or break a shield with a spell"},
		weapon="OrreryStaff"},
}
DC.byAbility = {}
for _, id in ipairs(DC.order) do
	local d = DC.defs[id]
	DC.byAbility[d.ability.id] = {class=id,kind="ability"}
	DC.byAbility[d.ultimate.id] = {class=id,kind="ultimate"}
end
function DC.valid(classId) return type(classId) == "string" and DC.defs[classId] ~= nil end

-- Class XP curve (1-50): total XP to reach level L = floor(8 * (L-1)^2.5).
-- Tuned so maxing one class takes ~1.75x the clears of Dungeoneering 1-50
-- (class XP per clear = 0.75 x the floor's Dungeoneering XP; see DC.classXp).
DC.XP_COEF, DC.XP_EXP = 8, 2.5
function DC.xpForLevel(level)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, DC.MAX_LEVEL)
	return math.floor(DC.XP_COEF * (level - 1) ^ DC.XP_EXP)
end
DC.MAX_XP = DC.xpForLevel(DC.MAX_LEVEL)
function DC.levelForXp(xp)
	xp = tonumber(xp) or 0
	if xp ~= xp or xp <= 0 then return 1 end
	local level = 1
	while level < DC.MAX_LEVEL and xp >= DC.xpForLevel(level + 1) do level += 1 end
	return level
end
-- {level, xp, floor, ceiling, fraction, maxed} for a progress bar.
function DC.progress(xp)
	xp = math.max(0, tonumber(xp) or 0)
	if xp ~= xp then xp = 0 end
	local level = DC.levelForXp(xp)
	local lo, hi = DC.xpForLevel(level), DC.xpForLevel(math.min(DC.MAX_LEVEL, level + 1))
	local maxed = level >= DC.MAX_LEVEL
	return {level=level,xp=math.floor(xp),floor=lo,ceiling=hi,fraction=if maxed then 1 else math.clamp((xp - lo) / math.max(1, hi - lo), 0, 1),maxed=maxed}
end

-- Milestones (every class): ability cooldown cuts, an empowered ability, a
-- second ultimate charge and the Paragon title.
DC.milestones = {
	{level=5,cooldown=0.1,text="Ability cooldown −10%"},
	{level=15,empowered=true,text="Empowered ability"},
	{level=20,cooldown=0.2,text="Ability cooldown −20%"},
	{level=30,charges=2,text="Second ultimate charge per run"},
	{level=40,cooldown=0.3,text="Ability cooldown −30%"},
	{level=50,title=true,text="Paragon title"},
}
function DC.milestoneState(level)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, DC.MAX_LEVEL)
	local out = {cooldown=0,empowered=false,charges=1,title=false}
	for _, m in ipairs(DC.milestones) do
		if level >= m.level then
			if m.cooldown then out.cooldown = math.max(out.cooldown, m.cooldown) end
			if m.empowered then out.empowered = true end
			if m.charges then out.charges = math.max(out.charges, m.charges) end
			if m.title then out.title = true end
		end
	end
	return out
end
-- Dungeon-only boosts at a class level: {damage, mitigation, healing} fractions.
function DC.levelBonus(classId, level)
	local d = DC.defs[classId]
	if not d then return {damage=0,mitigation=0,healing=0} end
	local n = math.clamp(math.floor(tonumber(level) or 1), 1, DC.MAX_LEVEL) - 1
	return {damage=n * d.perLevel.damage,mitigation=n * d.perLevel.mitigation,healing=n * d.perLevel.healing}
end
-- Fraction of boss/sentinel damage taken (Aegis base 0.5; reduction capped at 75%).
function DC.damageTakenMult(classId, level)
	local d = DC.defs[classId]
	if not d then return 1 end
	local reduction = (d.attack.mitigation or 0) + DC.levelBonus(classId, level).mitigation
	return 1 - math.clamp(reduction, 0, 0.75)
end
-- Integer hit with a carried fraction: base * (1 + damage bonus). Returns hit, newCarry.
function DC.hit(base, classId, level, carry)
	base = math.max(0, math.floor(tonumber(base) or 0))
	local extra = base * DC.levelBonus(classId, level).damage + (tonumber(carry) or 0)
	local whole = math.floor(extra + 1e-9)
	return base + whole, math.max(0, extra - whole)
end
-- Mender heal per strike / Mending Light share, scaled by healing power.
function DC.healAmount(base, level)
	return math.floor((tonumber(base) or 0) * (1 + DC.levelBonus("Mender", level).healing) + 0.5)
end
function DC.cooldown(classId, level)
	local d = DC.defs[classId]
	if not d then return math.huge end
	return d.ability.cooldown * (1 - DC.milestoneState(level).cooldown)
end
function DC.abilityPower(classId, level)
	local d = DC.defs[classId]
	if not d then return 0 end
	return if DC.milestoneState(level).empowered then d.ability.empowered else d.ability.power
end
DC.ULTIMATE_GAP = 45 -- seconds between two ultimates of one delver
function DC.ultimateCharges(level) return DC.milestoneState(level).charges end

-- Server-side validation of an ability or ultimate use.
-- s = {inRun, classId, level, now, readyAt, ultimatesUsed, ultimateAt, stage,
--      shielded, warded, telegraph, wisps}. Returns ok, reason.
function DC.abilityCheck(kind, s)
	if type(s) ~= "table" or not s.inRun then return false, "Only delvers inside an Observatory run can use class abilities." end
	local d = DC.defs[s.classId]
	if not d then return false, "Choose a class at the matchmaking pad first." end
	local now = tonumber(s.now) or 0
	local core = s.stage == "core"
	-- Dungeon endgame: the Mirror Gallery and Star Chart rooms are tuning stages too.
	local tuning = s.stage == "prisms" or s.stage == "mirrors" or s.stage == "chart" or (core and s.shielded == true)
	if kind == "ability" then
		local readyAt = tonumber(s.readyAt) or 0
		if now < readyAt then return false, d.ability.name .. " recharging • " .. math.ceil(readyAt - now) .. "s." end
		local id = d.ability.id
		if id == "Bulwark" and not core then return false, d.ability.name .. " needs the boss phase." end
		if id == "Cleave" and not (core and ((tonumber(s.wisps) or 0) > 0 or (not s.shielded and not s.warded))) then return false, "Nothing in reach of " .. d.ability.name .. "." end
		if id == "DisruptingShot" and not (core and (s.telegraph or s.channel == "nova")) then return false, d.ability.name .. " needs a telegraphing boss." end
		if id == "Attune" and not tuning then return false, "No prism to attune right now." end
		return true
	elseif kind == "ultimate" then
		if (tonumber(s.ultimatesUsed) or 0) >= DC.ultimateCharges(s.level) then return false, d.ultimate.name .. " is spent for this run." end
		local last = tonumber(s.ultimateAt)
		if last and now - last < DC.ULTIMATE_GAP then return false, d.ultimate.name .. " recharging • " .. math.ceil(DC.ULTIMATE_GAP - (now - last)) .. "s." end
		local id = d.ultimate.id
		if (id == "Bastion" or id == "SecondDawn") and not core then return false, d.ultimate.name .. " needs the boss phase." end
		if id == "CometVolley" and not (core and ((tonumber(s.wisps) or 0) > 0 or not s.shielded)) then return false, d.ultimate.name .. " needs wisps or an unshielded core." end
		if id == "RendingStorm" and not (core and not s.shielded and not s.warded) then return false, d.ultimate.name .. " needs an exposed core." end
		if id == "EclipseRift" and not tuning then return false, "No prism sequence to complete." end
		return true
	end
	return false, "Unknown ability."
end

-- Team composition: unique classes among classed delvers.
-- xpMult = 1 + 6% per unique class beyond the first; balanced (>= 3 delvers,
-- every one a different class) adds 5 to the Bonus score component.
DC.TEAM_STEP = 0.06
function DC.teamBonus(classes)
	local list = type(classes) == "table" and classes or {}
	local seen, unique, classed = {}, 0, 0
	for _, c in ipairs(list) do
		if DC.valid(c) then
			classed += 1
			if not seen[c] then seen[c] = true; unique += 1 end
		end
	end
	local balanced = #list >= 3 and classed == #list and unique == #list
	return {unique=unique,xpMult=1 + DC.TEAM_STEP * math.max(0, unique - 1),balanced=balanced,bonus=if balanced then 5 else 0}
end

-- Secrets: hidden caches and levers. Counts per floor; spots are offsets from
-- the Observatory origin (core floor and sentinel hall).
DC.secretCounts = {2,2,3,3,4,5,5}
DC.secretSpots = {
	{x=31,z=14,kind="cache"},{x=-31,z=-14,kind="lever"},{x=12,z=33,kind="cache"},{x=-14,z=32,kind="lever"},
	{x=24,z=-112,kind="cache"},{x=-24,z=-128,kind="lever"},{x=-24,z=-92,kind="cache"},{x=24,z=-95,kind="lever"},
	{x=33,z=-2,kind="cache"},{x=-33,z=3,kind="lever"},
}
function DC.secretCount(floorIndex) return DC.secretCounts[floorIndex] or 0 end
-- Deterministic distinct spots for a run: start rotates with floor and seed, step 3 (coprime with 10).
function DC.secretsFor(floorIndex, seed)
	local n = DC.secretCount(floorIndex)
	local spots = DC.secretSpots
	local start = (math.floor(tonumber(seed) or 0) * 3 + (tonumber(floorIndex) or 0)) % #spots
	local out = {}
	for i = 0, n - 1 do
		local index = ((start + i * 3) % #spots) + 1
		table.insert(out, {spot=index,kind=spots[index].kind,x=spots[index].x,z=spots[index].z})
	end
	return out
end

-- Score: speed + survival + puzzle + secrets (each 0-100) scaled to 300 (x0.75),
-- plus Bonus (3 per class feat + 5 for a balanced team, cap 20; Master runs cap
-- 20 + DC.MASTER_SCORE_BONUS, never a flat +5), clamped to 300.
DC.FEAT_BONUS, DC.BONUS_CAP = 3, 20
function DC.bonusScore(feats, balanced, master)
	feats = math.max(0, math.floor(tonumber(feats) or 0))
	local cap = DC.BONUS_CAP + (if master == true then (DC.MASTER_SCORE_BONUS or 0) else 0)
	return math.min(cap, feats * DC.FEAT_BONUS + (if balanced then 5 else 0))
end
-- master: Master Mode runs are timed against DC.par (par x DC.masterScale(floor).par)
-- and may carry DC.MASTER_SCORE_BONUS more Bonus (Dungeon endgame).
function DC.score(floorIndex, seconds, deaths, mistakes, found, total, bonus, master)
	local isMaster = master == true and (tonumber(floorIndex) or 0) <= DC.MASTER_FLOORS
	local scale = if isMaster then DC.masterScale(floorIndex).par else 1
	local _, parts = Data.dungeonScore(floorIndex, (tonumber(seconds) or 0) / scale, deaths, mistakes)
	total = math.max(0, math.floor(tonumber(total) or 0))
	found = math.clamp(math.floor(tonumber(found) or 0), 0, total)
	local secrets = if total > 0 then found * 100 / total else 100
	bonus = math.clamp(math.floor(tonumber(bonus) or 0), 0, DC.BONUS_CAP + (if isMaster then DC.MASTER_SCORE_BONUS else 0))
	local base = (parts.speed + parts.survival + parts.skill + secrets) * 0.75
	local score = math.clamp(math.floor(base + bonus + 0.5), 0, 300)
	return score, {speed=parts.speed,survival=parts.survival,skill=parts.skill,secrets=secrets,bonus=bonus}
end

-- Master Mode (floors I-VII; Dungeon endgame extended it from I-V): Floor I is
-- x2 HP and damage, par x1.6, x2.2 XP and coins; every deeper floor scales harder
-- by DC.MASTER_STEP (Floor VII: x3.2 HP, x3.2 damage, par x2.8, x4 XP and coins),
-- plus one extra chest roll. A Master clear takes longer, so it must pay >= normal per hour.
-- Unlocked per floor by a normal-mode clear at grade S or better (best score >= the S minimum).
DC.MASTER_FLOORS = 7
DC.MASTER_MULT, DC.MASTER_XP, DC.MASTER_ROLLS, DC.MASTER_PAR = 2, 2.2, 1, 1.6
DC.MASTER_STEP = {hp=0.2,damage=0.2,xp=0.3,par=0.2}
DC.MASTER_UNLOCK_GRADE = "S"
DC.MASTER_SCORE_BONUS = 5 -- Master runs: Bonus score may reach BONUS_CAP + 5
-- Master Mode multipliers of a floor: {hp, damage, xp, par}.
function DC.masterScale(floorIndex)
	local n = math.clamp(math.floor(tonumber(floorIndex) or 1), 1, #Data.DungeonFloors) - 1
	local st = DC.MASTER_STEP
	return {hp=DC.MASTER_MULT + st.hp * n,damage=DC.MASTER_MULT + st.damage * n,xp=DC.MASTER_XP + st.xp * n,par=DC.MASTER_PAR + st.par * n}
end
-- Par time (seconds) of a floor; Master Mode runs get x masterScale(floor).par.
function DC.par(floorIndex, master)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	return f.par * (if master == true and f.index <= DC.MASTER_FLOORS then DC.masterScale(f.index).par else 1)
end
function DC.masterUnlocked(floorIndex, bestScore)
	return type(floorIndex) == "number" and floorIndex >= 1 and floorIndex <= DC.MASTER_FLOORS
		and (tonumber(bestScore) or 0) >= Data.DungeonGradeById[DC.MASTER_UNLOCK_GRADE].min
end
-- Umbral wisp HP grows with the square root of the floor's HP multiplier (x2 in
-- Master Mode), so wave clearing keeps pace with party damage on deep floors.
-- At most DC.WISP_CAP wisps live at once; the wave timer pauses while a full
-- wave (count) is still alive (expedition.server.lua).
DC.WISP_CAP = 8
function DC.wispHp(floorIndex, master)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local wave = f.mechanics.addWaves
	if not wave then return 0 end
	local mult = f.hpMult * (if master == true and f.index <= DC.MASTER_FLOORS then DC.masterScale(f.index).hp else 1)
	return math.ceil(wave.hp * math.sqrt(mult) - 1e-9)
end
-- Seconds between wisp waves: Master waves arrive less often in proportion to
-- their tougher wisps, so wave HP per second matches the normal floor.
function DC.waveEvery(floorIndex, master)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local wave = f.mechanics.addWaves
	if not wave then return 0 end
	if not (master == true and f.index <= DC.MASTER_FLOORS) then return wave.every end
	return wave.every * DC.wispHp(f.index, true) / DC.wispHp(f.index, false)
end
function DC.floorStats(floorIndex, master)
	local s = Data.dungeonFloorStats(floorIndex)
	s.bossDamageMult = 1
	master = master == true and floorIndex <= DC.MASTER_FLOORS
	if master then
		local m = DC.masterScale(floorIndex)
		s.guardianHp, s.coreHp, s.guardianHit = math.ceil(s.guardianHp * m.hp - 1e-9), math.ceil(s.coreHp * m.hp - 1e-9), math.floor(s.guardianHit * m.damage)
		s.bossDamageMult = m.damage
	end
	s.addHp = DC.wispHp(floorIndex, master)
	s.waveEvery = DC.waveEvery(floorIndex, master)
	s.par = DC.par(floorIndex, master)
	return s
end

-- Class XP for one credited clear (the selected class only).
function DC.classXp(floorIndex, grade, master, teamMult)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local g = Data.DungeonGradeById[grade] or Data.DungeonGradeById.B
	local team = math.clamp(tonumber(teamMult) or 1, 1, 1 + DC.TEAM_STEP * (#DC.order - 1))
	return math.floor(f.rewards.dungeoneeringXp * 0.75 * g.mult * (if master then DC.masterScale(f.index).xp else 1) * team)
end
-- A class's own dungeon weapon rolls at twice the chance when that class clears.
function DC.classChest(chest, classId)
	local out = {}
	for _, d in ipairs(chest) do
		local def = Data.Items[d.item]
		local boost = def ~= nil and def.dungeonClass ~= nil and def.dungeonClass == classId
		table.insert(out, {item=d.item,chance=math.min(1, d.chance * (if boost then 2 else 1)),min=d.min,max=d.max})
	end
	return out
end
-- Full rewards: Data.dungeonRewards + Master Mode (x2.2 XP and coins, +1 chest roll) +
-- secrets (+1 essence and +5% coins each) + class XP and the class-weighted chest.
function DC.runRewards(floorIndex, grade, opts)
	opts = type(opts) == "table" and opts or {}
	local r = Data.dungeonRewards(floorIndex, grade)
	local master = opts.master == true and floorIndex <= DC.MASTER_FLOORS
	local found = math.clamp(math.floor(tonumber(opts.secrets) or 0), 0, DC.secretCount(floorIndex))
	if master then
		local x = DC.masterScale(floorIndex).xp
		r.dungeoneeringXp = math.floor(r.dungeoneeringXp * x)
		r.combatXp = math.floor(r.combatXp * x)
		r.coins = math.floor(r.coins * x)
	end
	r.coins += math.floor(r.coins * 0.05 * found)
	r.items.ObservatoryEssence += found
	r.rolls = 1 + (if master then DC.MASTER_ROLLS else 0)
	r.classXp = if DC.valid(opts.class) then DC.classXp(floorIndex, grade, master, opts.teamMult) else 0
	-- Dungeon endgame: Master clears pay x EG.MASTER_ESSENCE essence and add the Master-only rows
	-- (at the grade's chance factor, like the floor rows and the bonus chest's EG.bonusPlan).
	local EG = Data.DungeonEndgame
	if master and EG then
		local g = Data.DungeonGradeById[grade] or Data.DungeonGradeById.B
		r.items.ObservatoryEssence = math.floor(r.items.ObservatoryEssence * EG.MASTER_ESSENCE)
		for _, d in ipairs(EG.MasterChest[floorIndex] or {}) do
			table.insert(r.chest, {item=d.item,chance=math.min(1, d.chance * g.chance),min=d.min,max=d.max})
		end
	end
	r.chest = DC.classChest(r.chest, opts.class)
	r.master, r.secrets = master, found
	return r
end

-- Profile migration: always returns a clean p.dungeonClasses table.
function DC.migrate(raw)
	local t = type(raw) == "table" and raw or {}
	local out = {selected=if DC.valid(t.selected) then t.selected else nil,master=t.master == true,xp={},secrets={},masterBest={},masterClears={}}
	local xp = type(t.xp) == "table" and t.xp or {}
	for _, id in ipairs(DC.order) do
		local v = tonumber(xp[id]) or 0
		if v ~= v or v < 0 then v = 0 end
		out.xp[id] = math.min(math.floor(v), DC.MAX_XP)
	end
	local function count(map, key)
		local v = type(map) == "table" and tonumber(map[key]) or nil
		if v == nil or v ~= v or v <= 0 then return nil end
		return math.floor(v)
	end
	for i = 1, #Data.DungeonFloors do
		local key = tostring(i)
		local s = count(t.secrets, key)
		if s then out.secrets[key] = math.min(s, DC.secretCount(i)) end
		if i <= DC.MASTER_FLOORS then
			local b = count(t.masterBest, key)
			if b then out.masterBest[key] = math.min(b, 300) end
			out.masterClears[key] = count(t.masterClears, key)
		end
	end
	return out
end
-- Party HUD attribute: "Name|Class|Level;..." (class "" = unclassed).
function DC.partyString(rows)
	local parts = {}
	for _, r in ipairs(rows) do
		local name = string.gsub(tostring(r.name or "?"), "[|;]", "")
		table.insert(parts, name .. "|" .. (if DC.valid(r.class) then r.class else "") .. "|" .. math.clamp(math.floor(tonumber(r.level) or 1), 1, DC.MAX_LEVEL))
	end
	return table.concat(parts, ";")
end
function DC.parseParty(value)
	local rows = {}
	if type(value) ~= "string" then return rows end
	for entry in string.gmatch(value, "[^;]+") do
		local name, class, level = string.match(entry, "^([^|]*)|(%w*)|(%d+)$")
		if name then table.insert(rows, {name=name,class=if DC.valid(class) then class else nil,level=tonumber(level)}) end
	end
	return rows
end

-- Class weapons (dungeon-only: Floors VI-VII chests) and the Hollow Keystone.
local weaponText = " Dungeon-only: Observatory Floors VI-VII (twice as likely when you clear as its class). Requires Dungeoneering 40."
item("BastionMaul",{name="Bastion Maul",kind="weapon",slot="weapon",rarity="Legendary",color="6C9BD2",dungeon=true,dungeonClass="Aegis",
	stats={damage=200,strength=60,defense=80,health=150},requires={Combat=35,Dungeoneering=40},value=12000,
	description="Aegis class weapon. A starwall hammer that turns blows aside."..weaponText})
item("DawnmenderWand",{name="Dawnmender Wand",kind="weapon",slot="weapon",style="magic",rarity="Legendary",color="7FE3B0",dungeon=true,dungeonClass="Mender",
	stats={intelligence=100,abilityDamage=3,health=120},magic={power=60,speed=0.8,elements={}},requires={Magic=35,Dungeoneering=40},value=12000,
	description="Mender class weapon. Quick casts that hum with dawnlight."..weaponText})
item("Riftcleaver",{name="Riftcleaver",kind="weapon",slot="weapon",rarity="Legendary",color="E8806A",dungeon=true,dungeonClass="Riftblade",
	stats={damage=260,strength=110,critChance=10,critDamage=80},requires={Combat=40,Dungeoneering=40},value=14000,
	description="Riftblade class weapon. Cuts the seam between stars."..weaponText})
item("StarpiercerLongbow",{name="Starpiercer Longbow",kind="weapon",slot="weapon",style="ranged",rarity="Legendary",color="9BD67E",dungeon=true,dungeonClass="Starshot",
	stats={critChance=6,critDamage=30,rangedAccuracy=50},ranged={power=190,speed=1.05,range=Data.CombatStyles.maxRange,maxAmmoTier=7},
	requires={Ranged=40,Dungeoneering=40},value=14000,
	description="Starshot class weapon. Heavy shots that never lose their line."..weaponText})
item("OrreryStaff",{name="Orrery Staff",kind="weapon",slot="weapon",style="magic",rarity="Legendary",color="8FA8FF",dungeon=true,dungeonClass="Arcanist",
	stats={intelligence=160,abilityDamage=2},magic={power=110,speed=1.2,elements={"Gale","Tide","Stone","Ember"}},requires={Magic=40,Dungeoneering=40},value=14000,
	description="Arcanist class weapon. Supplies unlimited Gale, Tide, Stone and Ember glyphs."..weaponText})
DC.weapons = {}
for _, id in ipairs(DC.order) do DC.weapons[id] = DC.defs[id].weapon end
local Gear = Data.Gear
Gear.Reforges.Eventide = {id="Eventide",name="Eventide",category="armor",stone="HollowKeystone",stats={defense=4,health=6,intelligence=4,critDamage=2}}
Gear.StoneFor.Eventide = "HollowKeystone"
table.insert(Gear.ReforgeOrder.armor, "Eventide")
item("HollowKeystone",{name="Hollow Keystone",kind="material",rarity="Legendary",color="5B4A8C",reforgeStone="Eventide",value=150*Data.Rarity.Legendary.rank^2,
	description="Reforge stone. Applies the Eventide reforge to armor at the Reforge Anvil. Dropped by Observatory chests (Floor VI+)."})

-- Floors VI and VII. New mechanics:
--   regen    {every, fraction}: while any umbral wisp lives, the boss heals that fraction of max HP every N s
--   overload {below, intervalMult}: below that HP fraction the boss strikes faster
-- New boss kinds: lances (every delver is marked at once; step off your own mark),
-- collapse (cycles pulse -> ring -> lances).
local floors = Data.DungeonFloors
table.insert(floors, {index=6,numeral="VI",name="Observatory Floor VI",subtitle="Lumen Reliquary",level=40,hpMult=7.5,damageMult=4.5,par=480,
	mechanics={orderedPrisms=true,shieldPhases={0.5},addWaves={every=16,count=3,hp=5},regen={every=12,fraction=0.04}},
	boss={name="Lumen Colossus",attack="Converging Lances",kind="lances",radius=8,damage=46,interval=6,telegraph=2.2},
	rewards={dungeoneeringXp=1600,combatXp=1600,coins=1200,stormglass=5,essence=13},
	chest={{item="ObservatoryEssence",chance=0.75,min=5,max=10},{item="HollowKeystone",chance=0.02,min=1,max=1},{item="StarFragment",chance=0.06,min=1,max=2},
		{item="BastionMaul",chance=0.004,min=1,max=1},{item="DawnmenderWand",chance=0.004,min=1,max=1},{item="Riftcleaver",chance=0.004,min=1,max=1},
		{item="StarpiercerLongbow",chance=0.004,min=1,max=1},{item="OrreryStaff",chance=0.004,min=1,max=1},
		{item="UmbralOrrery",chance=0.006,min=1,max=1},{item="MasterworkTome",chance=0.03,min=1,max=1},{item="TemperingTome",chance=0.25,min=1,max=1}}})
table.insert(floors, {index=7,numeral="VII",name="Observatory Floor VII",subtitle="Sovereign's Eclipse",level=50,hpMult=10,damageMult=5.6,par=540,
	mechanics={orderedPrisms=true,shieldPhases={0.75,0.5,0.25},addWaves={every=15,count=4,hp=5},regen={every=10,fraction=0.03},
		enrage={after=360,damageMult=2,intervalMult=0.6},overload={below=0.5,intervalMult=0.75}},
	boss={name="Hollow Sovereign",attack="Eventide Collapse",kind="collapse",inner=10,radius=14,damage=54,interval=5,telegraph=2},
	rewards={dungeoneeringXp=2400,combatXp=2300,coins=1800,stormglass=6,essence=18},
	chest={{item="ObservatoryEssence",chance=0.85,min=7,max=14},{item="HollowKeystone",chance=0.04,min=1,max=1},{item="StarFragment",chance=0.1,min=1,max=3},
		{item="BastionMaul",chance=0.008,min=1,max=1},{item="DawnmenderWand",chance=0.008,min=1,max=1},{item="Riftcleaver",chance=0.008,min=1,max=1},
		{item="StarpiercerLongbow",chance=0.008,min=1,max=1},{item="OrreryStaff",chance=0.008,min=1,max=1},
		{item="UmbralOrrery",chance=0.01,min=1,max=1},{item="MasterworkTome",chance=0.05,min=1,max=1},{item="PrismlitLens",chance=0.02,min=1,max=1}}})
-- Boss attack for the n-th strike (0-based) of a floor's boss kind.
function DC.attackKind(kind, n)
	n = math.floor(tonumber(n) or 0)
	if kind == "eclipse" then return if n % 2 == 0 then "pulse" else "ring" end
	if kind == "collapse" then return ({"pulse","ring","lances"})[(n % 3) + 1] end
	return kind
end
end
-- End Dungeon classes section.

------------------------------------------------------------------------------
-- Prayer & Thieving (Prayer & Thieving team; append-only section).
-- Prayer (OSRS Prayer): every monster drops remains (8 tiers by monster
-- level, sea creatures and slayer bosses too). Offering them at an altar pays
-- remains.prayerXp x altar.mult, one rite every PR.RITE_SECONDS (batches of
-- PR.BATCH). Prayer points: pool PR.maxPoints(level), persisted; active
-- prayers drain PR.drainPerSecond (cut by Devotion), restored at altars
-- ("pray") or by draughts. 21 prayers (PR.Prayers): wards (Defense +5/10/15%),
-- edges / sights / sparks (melee / ranged / magic damage and accuracy
-- +5/10/15%), protection from each style (PR.PROTECT of that style's
-- damage vs monsters, PR.PROTECT_WORLD_BOSS vs world bosses), Mending Hymn
-- (heal), Hearthsong (mana regeneration), Amber Vigil (buffs last longer),
-- Sapping Rite (hits sap a monster's defence) and two high hymns. Prayers that
-- share a group are exclusive.
-- Thieving (OSRS Thieving): market stalls, pickpocket marks and strongboxes
-- (TH.Targets). Success = TH.chance(target, level, glove bonus, Deftness);
-- a success pays coins + rolled loot, XP and a per-player per-target
-- cooldown (respawn); a failure stuns (no thieving or walking) and hurts.
-- Gloves (owned, never consumed) add success chance.
-- server.server.lua (Prayer & Thieving block) runs both; combat.server.lua
-- (Prayer section) applies offence, sap and mana; world.server.lua builds
-- altars, stalls, marks and strongboxes; verify-prayer.luau checks them.
-- Profile (optional; migrated): p.prayer = {points, quick={id,id}, offered=
-- {[remains]=n}, active={[id]=true}, credit={[id]=prepaid s}, since (all
-- three cleared on load)}, p.thieving = {thefts={[target]=n}, cooldowns=
-- {[target]=os.time ready}, stunUntil=os.time (expired entries pruned)}.
------------------------------------------------------------------------------
do
local PR, TH = {}, {}
Data.Prayer, Data.Thieving = PR, TH
for _, id in ipairs({"Prayer","Thieving"}) do table.insert(Data.SkillOrder, id) end
Data.Skills.Prayer = {category="combat",color="E8D9A0",title="Devout",perLevel={defense=0.5,devotion=0.2},description="Offer remains at the isles' altars and call on prayers in battle. Raises Defense and Devotion."}
Data.Skills.Thieving = {category="support",color="8C7BC4",title="Nightglove",perLevel={deftness=0.5,speed=0.1},description="Lift from market stalls, pick pockets and crack strongboxes. Raises Deftness and Speed."}
-- Devotion slows prayer drain (OSRS prayer bonus); Deftness adds theft chance.
Data.Stats.devotion = {name="Devotion",symbol="✧",color="E8D9A0",base=0,cap=60}
Data.Stats.deftness = {name="Deftness",symbol="✋",color="8C7BC4",base=0,cap=50}
for _, id in ipairs({"devotion","deftness"}) do table.insert(Data.StatOrder, id) end

------------------------------------------------------------------------------
-- Prayer
------------------------------------------------------------------------------
PR.TICK = 3                  -- seconds between server drain / heal ticks
PR.POINTS_BASE = 10          -- max points = POINTS_BASE + Prayer level
PR.DEVOTION_SCALE = 30       -- drain / (1 + devotion / 30)
PR.PROTECT = 0.4             -- protection: share of that style's damage removed (monsters)
PR.PROTECT_WORLD_BOSS = 0.25 -- ... against world bosses
PR.SAP_PER_HIT = 0.03        -- Sapping Rite: share of base defence sapped per landed hit
PR.SAP_MAX = 0.3             -- ... never more than this share in total
PR.RITE_SECONDS = 1.8        -- one offering per this many seconds
PR.BATCH = 10                -- remains offered per altar use
PR.ALTAR_SECONDS = 60        -- the atlas may offer chosen remains this long after an altar visit
PR.QUICK_SLOTS = 2
PR.Groups = {defence="Wards",melee="Melee",ranged="Ranged",magic="Magic",protect="Protection"}
-- drain = points per minute. defence = % Defense; offence = {style = %} (damage
-- and, for ranged, accuracy); protect = style; heal = % max health per tick;
-- mana = mana regeneration multiplier bonus; preserve = buffs last (1+x) as long.
local function prayer(id, def) def.id = id; def.groups = def.groups or {}; return def end
PR.Prayers = {
	prayer("BarkhideWard",{name="Barkhide Ward",level=1,drain=3,groups={"defence"},defence=5,glyph="❖",color="A0825A",text="+5% Defense."}),
	prayer("KindledEdge",{name="Kindled Edge",level=4,drain=3,groups={"melee"},offence={melee=5},glyph="⚔",color="F3A64E",text="+5% melee damage."}),
	prayer("KeenSight",{name="Keen Sight",level=7,drain=3,groups={"ranged"},offence={ranged=5},glyph="➶",color="9BD67E",text="+5% ranged damage and accuracy."}),
	prayer("QuietSpark",{name="Quiet Spark",level=9,drain=3,groups={"magic"},offence={magic=5},glyph="✦",color="8FA8FF",text="+5% spell damage."}),
	prayer("StonehideWard",{name="Stonehide Ward",level=10,drain=6,groups={"defence"},defence=10,glyph="❖",color="B5A68C",text="+10% Defense."}),
	prayer("BlazingEdge",{name="Blazing Edge",level=13,drain=6,groups={"melee"},offence={melee=10},glyph="⚔",color="F28C3A",text="+10% melee damage."}),
	prayer("HawkSight",{name="Hawk Sight",level=16,drain=6,groups={"ranged"},offence={ranged=10},glyph="➶",color="7FC860",text="+10% ranged damage and accuracy."}),
	prayer("RisingSpark",{name="Rising Spark",level=19,drain=6,groups={"magic"},offence={magic=10},glyph="✦",color="7590FF",text="+10% spell damage."}),
	prayer("MendingHymn",{name="Mending Hymn",level=22,drain=5,heal=1.5,glyph="✚",color="7FE3CC",text="Heal 1.5% of max health every "..PR.TICK.." seconds."}),
	prayer("IronbarkWard",{name="Ironbark Ward",level=25,drain=12,groups={"defence"},defence=15,glyph="❖",color="C9C2B0",text="+15% Defense."}),
	prayer("WildfireEdge",{name="Wildfire Edge",level=28,drain=12,groups={"melee"},offence={melee=15},glyph="⚔",color="EF6A2E",text="+15% melee damage."}),
	prayer("FalconSight",{name="Falcon Sight",level=31,drain=12,groups={"ranged"},offence={ranged=15},glyph="➶",color="5FB447",text="+15% ranged damage and accuracy."}),
	prayer("StormSpark",{name="Storm Spark",level=34,drain=12,groups={"magic"},offence={magic=15},glyph="✦",color="5C7AEA",text="+15% spell damage."}),
	prayer("WardOfFangs",{name="Ward of Fangs",level=37,drain=12,groups={"protect"},protect="melee",glyph="⛨",color="F3C66E",text="Melee attacks deal 40% less (25% from world bosses)."}),
	prayer("WardOfQuills",{name="Ward of Quills",level=40,drain=12,groups={"protect"},protect="ranged",glyph="⛨",color="9BD67E",text="Ranged attacks deal 40% less (25% from world bosses)."}),
	prayer("WardOfGlyphs",{name="Ward of Glyphs",level=43,drain=12,groups={"protect"},protect="magic",glyph="⛨",color="8FA8FF",text="Magic attacks deal 40% less (25% from world bosses)."}),
	prayer("Hearthsong",{name="Hearthsong",level=46,drain=4,mana=0.5,glyph="♨",color="9FC3FF",text="+50% mana regeneration."}),
	prayer("AmberVigil",{name="Amber Vigil",level=52,drain=4,preserve=0.5,glyph="⌛",color="F2C14E",text="Potion and meal buffs last 50% longer."}),
	prayer("SappingRite",{name="Sapping Rite",level=58,drain=18,sap=PR.SAP_PER_HIT,glyph="☄",color="C58BE8",text="Each landed hit saps 3% of a monster's defence (up to 30%)."}),
	prayer("ValorHymn",{name="Valor Hymn",level=70,drain=24,groups={"defence","melee"},defence=25,offence={melee=20},glyph="♛",color="FFD27A",text="+20% melee damage and +25% Defense."}),
	prayer("StarwardLitany",{name="Starward Litany",level=74,drain=24,groups={"defence","ranged","magic"},defence=25,offence={ranged=20,magic=20},glyph="✴",color="C9D6FF",text="+20% ranged and spell damage (and ranged accuracy), +25% Defense."}),
}
PR.PrayerById = {}
for i, def in ipairs(PR.Prayers) do def.index = i; PR.PrayerById[def.id] = def end
PR.ProtectFor = {melee="WardOfFangs",ranged="WardOfQuills",magic="WardOfGlyphs"}

function PR.maxPoints(level) return PR.POINTS_BASE + math.clamp(math.floor(tonumber(level) or 1), 1, Data.MAX_LEVEL) end
function PR.conflicts(a, b)
	if a == b then return false end
	for _, g in ipairs(a.groups) do if table.find(b.groups, g) then return true end end
	return false
end
-- Sorted list of active prayer ids from a set or list (unknown ids dropped).
function PR.list(active)
	local out = {}
	if type(active) == "table" then
		for k, v in pairs(active) do
			local id = if type(k) == "string" and v == true then k elseif type(v) == "string" then v else nil
			if id and PR.PrayerById[id] and not table.find(out, id) then table.insert(out, id) end
		end
	end
	table.sort(out, function(a, b) return PR.PrayerById[a].index < PR.PrayerById[b].index end)
	return out
end
-- Pure toggle. Returns verdict, new active set ({[id]=true}), switched-off ids.
-- verdict: "on" | "off" | "unknown" | "level" | "points" (fewer points than the
-- activation cost at that Devotion).
function PR.toggle(active, id, level, points, devotion)
	local def = type(id) == "string" and PR.PrayerById[id]
	local out = {}
	for _, k in ipairs(PR.list(active)) do out[k] = true end
	if not def then return "unknown", out, {} end
	if out[id] then out[id] = nil; return "off", out, {} end
	if (tonumber(level) or 1) < def.level then return "level", out, {} end
	-- Switching on pays one tick of that prayer's drain up front (PR.activationCost).
	if (tonumber(points) or 0) <= 0 or (tonumber(points) or 0) < PR.activationCost(id, devotion) - 1e-9 then return "points", out, {} end
	local dropped = {}
	for k in pairs(out) do
		if PR.conflicts(def, PR.PrayerById[k]) then out[k] = nil; table.insert(dropped, k) end
	end
	table.sort(dropped)
	out[id] = true
	return "on", out, dropped
end
function PR.drainPerMinute(active)
	local total = 0
	for _, id in ipairs(PR.list(active)) do total += PR.PrayerById[id].drain end
	return total
end
function PR.drainPerSecond(active, devotion)
	local dev = math.clamp(tonumber(devotion) or 0, 0, Data.Stats.devotion.cap)
	return PR.drainPerMinute(active) / 60 / (1 + dev / PR.DEVOTION_SCALE)
end
-- Points after `seconds` of drain (never below 0) and whether they ran out.
function PR.drain(points, active, devotion, seconds)
	local left = math.max(0, (tonumber(points) or 0) - PR.drainPerSecond(active, devotion) * math.max(0, tonumber(seconds) or 0))
	left = math.floor(left * 1000 + 0.5) / 1000
	return left, left <= 0 and PR.drainPerMinute(active) > 0
end
-- Time-based drain. Toggling is never free: switching a prayer on pays
-- PR.activationCost (one PR.TICK of its drain) up front and earns that many
-- seconds of prepaid credit; every settle (tick, toggle, prayerOff, draught,
-- altar) then charges each active prayer for the elapsed seconds beyond its
-- remaining credit. A prayer kept on costs exactly its drain rate; a prayer
-- flicked on and off costs at least one tick per activation.
function PR.activationCost(id, devotion)
	if type(id) ~= "string" or not PR.PrayerById[id] then return 0 end
	return PR.drainPerSecond({[id] = true}, devotion) * PR.TICK
end
-- Points after charging `seconds` for every active prayer (credit = {[id] =
-- prepaid seconds}, consumed in place) and whether they ran out.
function PR.charge(points, active, credit, devotion, seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	local dev = math.clamp(tonumber(devotion) or 0, 0, Data.Stats.devotion.cap)
	local cost, any = 0, false
	for _, id in ipairs(PR.list(active)) do
		any = true
		local paid = type(credit) == "table" and math.max(0, tonumber(credit[id]) or 0) or 0
		local used = math.min(paid, seconds)
		if type(credit) == "table" then credit[id] = if paid - used > 0 then paid - used else nil end
		cost += PR.PrayerById[id].drain / 60 / (1 + dev / PR.DEVOTION_SCALE) * (seconds - used)
	end
	local left = math.max(0, (tonumber(points) or 0) - cost)
	left = math.floor(left * 1e6 + 0.5) / 1e6
	return left, left <= 0 and any
end
function PR.secondsLeft(points, active, devotion)
	local rate = PR.drainPerSecond(active, devotion)
	if rate <= 0 then return math.huge end
	return math.max(0, tonumber(points) or 0) / rate
end
-- Combined effects of an active set.
function PR.effects(active)
	local e = {defence=0, offence={melee=0,ranged=0,magic=0}, protect=nil, heal=0, mana=0, preserve=0, sap=0}
	for _, id in ipairs(PR.list(active)) do
		local def = PR.PrayerById[id]
		e.defence = math.max(e.defence, def.defence or 0)
		for style, v in pairs(def.offence or {}) do e.offence[style] = math.max(e.offence[style], v) end
		if def.protect then e.protect = def.protect end
		e.heal = math.max(e.heal, def.heal or 0)
		e.mana = math.max(e.mana, def.mana or 0)
		e.preserve = math.max(e.preserve, def.preserve or 0)
		e.sap = math.max(e.sap, def.sap or 0)
	end
	return e
end
-- Incoming damage multiplier from protection (1 = none).
function PR.protectMult(protect, style, worldBoss)
	if not protect or protect ~= style then return 1 end
	return 1 - (if worldBoss then PR.PROTECT_WORLD_BOSS else PR.PROTECT)
end
-- Raw incoming damage after protection (never below 0) and the defence multiplier.
function PR.incoming(raw, style, effects, worldBoss)
	local e = type(effects) == "table" and effects or {}
	local amount = math.max(0, (tonumber(raw) or 0) * PR.protectMult(e.protect, style, worldBoss))
	return amount, 1 + math.max(0, tonumber(e.defence) or 0) / 100
end
-- Monster defence after one more sapped hit (base = the monster's own defence).
function PR.sapped(current, base, sap)
	base = math.max(0, tonumber(base) or 0)
	-- Rounded up: sapping never removes more than PR.SAP_MAX of a small base.
	local floorDef = math.ceil(base * (1 - PR.SAP_MAX) - 1e-9)
	if (tonumber(sap) or 0) <= 0 or base <= 0 then return current end
	return math.max(floorDef, (tonumber(current) or base) - math.max(1, math.ceil(base * sap)))
end
-- Buff seconds added per `seconds` of real time with Amber Vigil (lasting 1+x as long).
function PR.preserveExtend(seconds, preserve)
	preserve = math.max(0, tonumber(preserve) or 0)
	return (tonumber(seconds) or 0) * preserve / (1 + preserve)
end
-- Points a draught restores: flat + share of max points (never above max).
function PR.restore(points, maxPoints, def)
	local r = type(def) == "table" and def.prayerRestore
	if type(r) ~= "table" then return points end
	return math.min(maxPoints, (tonumber(points) or 0) + (r.flat or 0) + math.floor((r.percent or 0) * maxPoints))
end

-- Remains: dropped by every monster (tier by level); offered at altars.
PR.Remains = {
	{id="BrittleRemains",name="Brittle Remains",xp=3,value=2,rarity="Common",color="D8CFBF",upTo=9},
	{id="WeatheredRemains",name="Weathered Remains",xp=6,value=4,rarity="Common",color="C9BC9F",upTo=19},
	{id="HeavyRemains",name="Heavy Remains",xp=10,value=7,rarity="Uncommon",color="B8A88A",upTo=34},
	{id="EmberscorchedRemains",name="Emberscorched Remains",xp=15,value=11,rarity="Uncommon",color="C9774B",upTo=49},
	{id="VoidmarkedRemains",name="Voidmarked Remains",xp=21,value=16,rarity="Rare",color="7A5AA8",upTo=64},
	{id="StormboundRemains",name="Stormbound Remains",xp=28,value=22,rarity="Rare",color="8FA3C8",upTo=84},
	{id="WyrmRemains",name="Wyrm Remains",xp=34,value=30,rarity="Epic",color="5EC8D8"},
	{id="CrownRemains",name="Crown Remains",xp=40,value=40,rarity="Epic",color="F2D27A"},
}
PR.RemainsById = {}
for i, r in ipairs(PR.Remains) do
	r.tier = i
	PR.RemainsById[r.id] = r
	item(r.id,{name=r.name,kind="material",category="remains",rarity=r.rarity,color=r.color,value=r.value,prayerXp=r.xp,remainsTier=i,
		description="Offer at an altar for "..r.xp.." Prayer XP (more at greater altars)."})
end
-- Remains tier for a monster level (sea creatures 40+ leave Wyrm Remains,
-- the Shattered Crown leaves Crown Remains).
function PR.remainsFor(level, region, sea)
	if region == "ShatteredCrown" then return "CrownRemains" end
	level = tonumber(level) or 1
	if sea and level >= 40 then return "WyrmRemains" end
	for _, r in ipairs(PR.Remains) do if r.upTo and level <= r.upTo then return r.id end end
	return "WyrmRemains"
end
local function addDrop(list, id, chance, min, max) table.insert(list, {item=id,chance=chance,min=min,max=max or min}) end
for _, def in pairs(Data.Monsters) do
	if type(def.drops) == "table" then addDrop(def.drops, PR.remainsFor(def.level, def.region, false), 1, 1) end
end
for _, def in pairs(Data.SeaCreatures) do
	if type(def.drops) == "table" then addDrop(def.drops, PR.remainsFor(def.level, nil, true), 1, 1) end
end
local slayerRemains = {{"WeatheredRemains",3,5},{"EmberscorchedRemains",4,6},{"StormboundRemains",5,8},{"WyrmRemains",6,10}}
for _, line in pairs(Data.Slayers) do
	for t, tier in ipairs(line.tiers) do
		local r = slayerRemains[t]
		if r then addDrop(tier.drops, r[1], 1, r[2], r[3]) end
	end
end

-- Altars: XP multiplier and where they stand (region gates apply).
PR.Altars = {
	{id="QuayChapel",name="Chapel of the Skyward Choir",region="Hub",mult=1,color="E8D9A0",text="The Quay's open-air chapel. Restores prayer points."},
	{id="MossrootShrine",name="Mossroot Shrine",region="Windpine",mult=1.25,color="9BD18B",text="A shrine grown from a living pine. Offerings are worth 25% more."},
	{id="ThunderChoirAltar",name="Altar of the Thunder Choir",region="Tempest",mult=1.5,color="C6DCFF",text="Storm-struck stone on the Spire. Offerings are worth 50% more."},
	{id="CrownReliquary",name="Crown Reliquary",region="ShatteredCrown",mult=1.75,color="F2D27A",text="A reliquary in the broken crown. Offerings are worth 75% more."},
}
PR.AltarById = {}
for i, a in ipairs(PR.Altars) do a.index = i; PR.AltarById[a.id] = a end
-- Prayer XP for offering `count` remains at an altar.
function PR.offerXp(remainsId, altarId, count)
	local r, a = PR.RemainsById[remainsId], PR.AltarById[altarId]
	if not r or not a then return 0 end
	return math.floor(r.xp * a.mult * math.max(0, math.floor(tonumber(count) or 1)) + 0.5)
end
-- Best (highest tier) remains held, or nil.
function PR.bestRemains(items)
	if type(items) ~= "table" then return nil end
	for i = #PR.Remains, 1, -1 do
		local id = PR.Remains[i].id
		if (tonumber(items[id]) or 0) > 0 then return id end
	end
	return nil
end

-- Draughts (Alchemy): restore prayer points.
item("DevotionDraught",{name="Devotion Draught",kind="consumable",category="potion",rarity="Rare",color="E8D9A0",value=45,requires={Alchemy=38},
	prayerRestore={flat=8,percent=0.25},description="Restore 8 + 25% of your prayer points."})
recipe("DevotionDraught",{skill="Alchemy",level=38,xp=110,costs={HeavyRemains=2,Moonbloom=1},repeatable=true,station="Cauldron",category="Potions"})
item("ChoirTonic",{name="Choir Tonic",kind="consumable",category="potion",rarity="Epic",color="F2E6B8",value=120,requires={Alchemy=63},
	prayerRestore={flat=12,percent=0.35},description="Restore 12 + 35% of your prayer points."})
recipe("ChoirTonic",{skill="Alchemy",level=63,xp=240,costs={StormboundRemains=2,Starfruit=1,GlintEssence=1},repeatable=true,station="Cauldron",category="Potions"})
-- Devotion accessories (Workbench, trained with Prayer).
item("ChoirbellCharm",{name="Choirbell Charm",kind="accessory",rarity="Rare",color=Data.Rarity.Rare.color,stats={devotion=8,defense=5},value=40*Data.Rarity.Rare.rank^2,description="Accessory. Magical Power "..Data.Rarity.Rare.power.."."})
recipe("ChoirbellCharm",{skill="Prayer",level=30,xp=300,costs={EmberscorchedRemains=20,Mistpearl=2},station="Workbench",category="Accessories"})
item("SeraphCenser",{name="Seraph's Censer",kind="accessory",rarity="Epic",color=Data.Rarity.Epic.color,stats={devotion=15,health=30},value=40*Data.Rarity.Epic.rank^2,description="Accessory. Magical Power "..Data.Rarity.Epic.power.."."})
recipe("SeraphCenser",{skill="Prayer",level=65,xp=900,costs={StormboundRemains=40,Voidgarnet=2},collectionTier={StormboundRemains=1},station="Workbench",category="Accessories"})

------------------------------------------------------------------------------
-- Thieving
------------------------------------------------------------------------------
TH.LEVEL_STEP = 0.008   -- success chance per Thieving level above the target
TH.MAX_CHANCE = 0.95
TH.DEFT_EFFECT = 0.002  -- per Deftness point (stat cap 50 -> +10%)
TH.ACTION = 0.36 + 0.65 -- interact hold + prompt cooldown (pacing model)
TH.Kinds = {
	stall={name="Stall",verb="Steal from",past="Stole from",fail="A stall guard catches you",wait="restocking"},
	pocket={name="Mark",verb="Pickpocket",past="Picked the pocket of",fail="caught you red-handed",wait="wary"},
	safe={name="Strongbox",verb="Crack",past="Cracked",fail="A spring trap snaps shut",wait="relocking"},
}
TH.KindOrder = {"stall","pocket","safe"}
-- Gems: thieving loot (and the Choirbell / Censer accessories).
for _, g in ipairs({
	{id="SunstoneChip",name="Sunstone Chip",rarity="Uncommon",color="F7C85C",value=15},
	{id="Mistpearl",name="Mistpearl",rarity="Rare",color="DCE8F2",value=45},
	{id="Emberglass",name="Emberglass Gem",rarity="Rare",color="E8643A",value=90},
	{id="Voidgarnet",name="Voidgarnet",rarity="Epic",color="7A2E6B",value=220},
	{id="StarheartGem",name="Starheart Gem",rarity="Legendary",color="FFF3B0",value=900},
}) do
	item(g.id,{name=g.name,kind="material",category="gem",rarity=g.rarity,color=g.color,value=g.value,description="A cut gem. Sell to a merchant, or set into charms."})
end
-- Gloves: owned (never consumed); the best pair adds its bonus to every attempt.
item("LightfingerGloves",{name="Lightfinger Gloves",kind="material",category="gloves",rarity="Uncommon",color="A08A6A",value=60,thievingBonus=0.05,description="Thieving gloves: +5% success chance. Never used up."})
item("SilkshadowGloves",{name="Silkshadow Gloves",kind="material",category="gloves",rarity="Rare",color="5A5470",value=400,thievingBonus=0.1,description="Thieving gloves: +10% success chance. Never used up."})
item("NightveilGloves",{name="Nightveil Gloves",kind="material",category="gloves",rarity="Epic",color="2E2A44",value=1500,thievingBonus=0.15,description="Thieving gloves: +15% success chance. Never used up."})
TH.GloveOrder = {"NightveilGloves","SilkshadowGloves","LightfingerGloves"}
recipe("LightfingerGloves",{skill="Thieving",level=1,xp=20,costs={BeastHide=8},station="Workbench",category="Thieving"})
recipe("SilkshadowGloves",{skill="Thieving",level=35,xp=220,costs={SpiderSilk=24,Mistpearl=2},station="Workbench",category="Thieving"})
recipe("NightveilGloves",{skill="Thieving",level=70,xp=900,costs={ShadowPelt=10,Voidgarnet=3,VoidEssence=10},collectionTier={Voidgarnet=1},station="Workbench",category="Thieving"})
function TH.gloves(items)
	if type(items) == "table" then
		for _, id in ipairs(TH.GloveOrder) do
			if (tonumber(items[id]) or 0) > 0 then return id, Data.Items[id].thievingBonus end
		end
	end
	return nil, 0
end
-- Targets. base = success chance at the target's own level; respawn = per
-- player cooldown after a success; stun = seconds caught; damage = health lost
-- when caught (never lethal); coins = {min, max}; drops roll like monster drops.
local function d(id, chance, min, max) return {item=id,chance=chance,min=min,max=max or min} end
TH.Targets = {
	{id="Farmhand",name="Meadow Farmhand",kind="pocket",level=1,region="Meadow",xp=25,base=0.6,respawn=3,stun=4,damage=5,coins={2,4},color="B5895A",
		drops={d("SunwheatSeeds",0.3,1),d("Herb",0.2,1)}},
	{id="SweetbunStall",name="Sweetbun Stall",kind="stall",level=5,region="Hub",xp=35,base=0.62,respawn=5,stun=5,damage=8,coins={3,7},color="E9C46A",
		drops={d("Sunwheat",0.2,1)}},
	{id="Dockhand",name="Quay Dockhand",kind="pocket",level=15,region="Hub",xp=40,base=0.58,respawn=3.2,stun=4,damage=12,coins={3,6},color="3F7CAC",
		drops={d("Fish",0.3,1),d("SunstoneChip",0.005,1)}},
	{id="HerbalistStall",name="Herbalist's Stall",kind="stall",level=20,region="Meadow",xp=58,base=0.6,respawn=6,stun=5,damage=20,coins={5,10},color="6BBF59",
		drops={d("Herb",0.6,1,3),d("DuskberrySeeds",0.3,1),d("GlowcapSpores",0.2,1),d("MoonbloomBulb",0.05,1),d("Moonbloom",0.05,1)}},
	{id="Watchman",name="Brassfall Watchman",kind="pocket",level=30,region="Quarry",xp=64,base=0.56,respawn=3.5,stun=4.5,damage=30,coins={6,10},color="D4A84B",
		drops={d("ArcaneDust",0.15,1),d("SunstoneChip",0.02,1)}},
	{id="SilkStall",name="Silkweaver's Stall",kind="stall",level=38,region="Windpine",xp=100,base=0.58,respawn=8,stun=5,damage=50,coins={8,14},color="C9B7E0",
		drops={d("SpiderSilk",0.6,1,2),d("BeastHide",0.4,1),d("Mistpearl",0.01,1)}},
	{id="Merchant",name="Tidewater Merchant",kind="pocket",level=45,region="Tidewater",xp=83,base=0.55,respawn=3.8,stun=5,damage=45,coins={9,15},color="5EC8D8",
		drops={d("SunstoneChip",0.08,1),d("Mistpearl",0.02,1)}},
	{id="Strongbox",name="Ironbound Strongbox",kind="safe",level=50,region="Skyreach",xp=447,base=0.5,respawn=40,stun=6,damage=60,coins={100,180},color="8C8C96",
		drops={d("SunstoneChip",0.5,1,2),d("Mistpearl",0.3,1),d("Emberglass",0.1,1),d("StarFragment",0.02,1)}},
	{id="GemStall",name="Gemcutter's Stall",kind="stall",level=55,region="Quarry",xp=142,base=0.55,respawn=10,stun=5,damage=90,coins={10,20},color="E8643A",
		drops={d("SunstoneChip",0.6,1),d("Mistpearl",0.3,1),d("Emberglass",0.05,1)}},
	{id="Scholar",name="Gloomhollow Glyph Scholar",kind="pocket",level=62,region="Gloomhollow",xp=116,base=0.54,respawn=4.8,stun=5,damage=80,coins={12,20},color="A58CE0",
		drops={d("ArcaneDust",0.4,1,2),d("GaleGlyph",0.15,3,6),d("TideGlyph",0.15,3,6)}},
	{id="VaultChest",name="Gilded Vault Chest",kind="safe",level=70,region="Gloomhollow",xp=964,base=0.48,respawn=75,stun=6,damage=140,coins={120,210},color="C9A24D",
		drops={d("Mistpearl",0.5,1,2),d("Emberglass",0.35,1),d("Voidgarnet",0.15,1),d("StarFragment",0.05,1),d("NightveilGloves",0.004,1)}},
	{id="Noble",name="Skyborn Noble",kind="pocket",level=78,region="Hub",xp=153,base=0.52,respawn=5.5,stun=5.5,damage=140,coins={18,30},color="FFD27A",
		drops={d("Emberglass",0.03,1),d("Mistpearl",0.05,1),d("StarheartGem",0.0005,1)}},
	{id="CuriosStall",name="Tidewater Curio Stall",kind="stall",level=82,region="Tidewater",xp=273,base=0.52,respawn=14,stun=6,damage=160,coins={20,35},color="06D6A0",
		drops={d("VoidEssence",0.4,1),d("Emberglass",0.2,1),d("Voidgarnet",0.04,1)}},
	{id="SovereignCoffer",name="Sovereign Coffer",kind="safe",level=88,region="ShatteredCrown",xp=1947,base=0.45,respawn=120,stun=7,damage=260,coins={450,750},color="F2D27A",
		drops={d("Voidgarnet",0.4,1,2),d("StarFragment",0.2,1),d("StarheartGem",0.02,1),d("NightveilGloves",0.01,1)}},
}
TH.TargetById = {}
for i, t in ipairs(TH.Targets) do t.index = i; TH.TargetById[t.id] = t end
TH.MAX_STUN = 0 -- longest stun (bounds the persisted p.thieving.stunUntil)
for _, t in ipairs(TH.Targets) do TH.MAX_STUN = math.max(TH.MAX_STUN, t.stun) end
-- Success chance in 0..MAX_CHANCE (0 below the target's level).
function TH.chance(target, level, gloveBonus, deftness)
	if type(target) ~= "table" then return 0 end
	level = tonumber(level) or 1
	if level < target.level then return 0 end
	local dex = math.clamp(tonumber(deftness) or 0, 0, Data.Stats.deftness.cap)
	local c = target.base + (level - target.level) * TH.LEVEL_STEP + math.max(0, tonumber(gloveBonus) or 0) + dex * TH.DEFT_EFFECT
	return math.clamp(c, 0, TH.MAX_CHANCE)
end
-- Coins for one success (roll: function returning [0,1)).
function TH.coins(target, roll)
	local lo, hi = target.coins[1], target.coins[2]
	return lo + math.floor(roll() * (hi - lo + 1))
end
-- Expected value (coins + item sell values) of one success.
function TH.expected(target)
	local v = (target.coins[1] + target.coins[2]) / 2
	for _, drop in ipairs(target.drops) do
		local def = Data.Items[drop.item]
		v += drop.chance * (drop.min + drop.max) / 2 * (def and def.value or 0)
	end
	return v
end
-- Pacing model: seconds per attempt (success waits the respawn, failure the stun).
function TH.cycle(target, chance)
	return chance * math.max(target.respawn, TH.ACTION) + (1 - chance) * (TH.ACTION + target.stun)
end
function TH.xpPerHour(target, chance)
	if chance <= 0 then return 0 end
	return 3600 * chance * target.xp / TH.cycle(target, chance)
end
function TH.coinsPerHour(target, chance)
	if chance <= 0 then return 0 end
	return 3600 * chance * TH.expected(target) / TH.cycle(target, chance)
end
-- Best income from robbing a region's targets in parallel (coins/h upper
-- bound): each target yields at most its own pace (c / TH.cycle: successes
-- per second, its cooldown respected) and every success occupies the thief
-- for (TH.ACTION + (1 - c) x stun) / c seconds (attempts incl. the expected
-- stun, which blocks all thieving); the best coins-per-busy-second targets
-- fill the hour first. chanceOf(target) -> success chance.
function TH.regionCoinsPerHour(region, chanceOf)
	local options = {}
	for _, t in ipairs(TH.Targets) do
		local c = if t.region == region then math.clamp(tonumber(chanceOf(t)) or 0, 0, 1) else 0
		if c > 0 then
			table.insert(options, {value = TH.expected(t), cap = c / TH.cycle(t, c), busy = (TH.ACTION + (1 - c) * t.stun) / c})
		end
	end
	table.sort(options, function(a, b) return a.value / a.busy > b.value / b.busy end)
	local budget, coins = 1, 0
	for _, o in ipairs(options) do
		local rate = math.min(o.cap, budget / o.busy)
		coins += rate * o.value
		budget -= rate * o.busy
		if budget <= 1e-9 then break end
	end
	return coins * 3600
end

-- Collections: remains and gems (drop-like, reach tiers sooner).
for id, scale in pairs({BrittleRemains=0.5,WeatheredRemains=0.5,HeavyRemains=0.5,EmberscorchedRemains=0.4,VoidmarkedRemains=0.3,StormboundRemains=0.3,WyrmRemains=0.2,CrownRemains=0.2,
	SunstoneChip=0.3,Mistpearl=0.2,Emberglass=0.1,Voidgarnet=0.05,StarheartGem=0.01}) do
	table.insert(Data.CollectionItems, id)
	Data.CollectionScale[id] = scale
end

------------------------------------------------------------------------------
-- Quest checks: offerings {count, remains?} and thefts {target, count}.
------------------------------------------------------------------------------
local describe = Data.describeCheck
function Data.describeCheck(o, ...) -- ... = regional flag (§33), passed through
	local kind = type(o) == "table" and o.kind
	if kind == "offerings" then
		local r = o.remains and PR.RemainsById[o.remains]
		return "Offer "..o.count.." "..(if r then r.name else "remains").." at an altar"
	elseif kind == "thefts" then
		local t = TH.TargetById[o.target]
		local verb = t and TH.Kinds[t.kind].verb or "Rob"
		return verb.." the "..(t and t.name or tostring(o.target)).." "..o.count.." "..(if o.count == 1 then "time" else "times")
	end
	return describe(o, ...)
end
local function offerings(count, remains) return {kind="offerings",count=count,remains=remains} end
local function thefts(target, count) return {kind="thefts",target=target,count=count} end
PR.offeringsCheck, TH.theftsCheck = offerings, thefts
for _, q in ipairs({
	{id="EmbersOfDevotion",title="Embers of Devotion",line="side",region="Hub",
		story="Chorister Amsel keeps the chapel lamps on the Quay lit with the remains of slain beasts. Bring offerings to the altar and learn the first wards.",
		requires={{kind="contracts",count=2}},
		objectives={offerings(25),{kind="level",skill="Prayer",level=10}},
		rewards={coins=500,points=1,items={DevotionDraught=2},xp={Prayer=600}}},
	{id="NimbleFingers",title="Nimble Fingers",line="side",region="Meadow",
		story="A cheerful rogue named Pip bets you cannot lift a purse in Meadow Reach and a bun from the Quay before the bells. Prove her wrong.",
		requires={{kind="contracts",count=2}},
		objectives={thefts("Farmhand",15),thefts("SweetbunStall",10),{kind="level",skill="Thieving",level=10}},
		rewards={coins=700,points=1,items={LightfingerGloves=1},xp={Thieving=800}}},
	{id="ChoirOfTheStorm",title="Choir of the Storm",line="side",region="Tempest",
		story="The Thunder Choir sings only to those who have offered storm-bound remains on its altar. Earn a verse of their hymn.",
		requires={{kind="quest",quest="EmbersOfDevotion"},{kind="level",skill="Prayer",level=50}},
		objectives={offerings(50,"StormboundRemains"),{kind="level",skill="Prayer",level=60}},
		rewards={coins=12000,points=2,perk={devotion=5},lamp={xp=5000,skills={"Prayer"}}}},
	{id="SkybornVault",title="The Skyborn Vault",line="side",region="Gloomhollow",
		story="Pip has heard of a vault chest in Gloomhollow guarded by a scholar who never sleeps. Lift his key and crack the chest, ten times over.",
		requires={{kind="quest",quest="NimbleFingers"},{kind="level",skill="Thieving",level=62}},
		objectives={thefts("Scholar",30),thefts("VaultChest",10)},
		rewards={coins=15000,points=2,perk={deftness=5},items={SilkshadowGloves=1}}},
}) do
	table.insert(Data.Quests, q)
	q.index = #Data.Quests
	Data.QuestById[q.id] = q
end
-- Diary tasks in existing regional diaries (tiers stay within 3-5 tasks).
for _, add in ipairs({
	{"Meadow","Hard",thefts("HerbalistStall",40)},
	{"Quarry","Medium",thefts("Watchman",30)},
	{"Skyreach","Hard",thefts("Strongbox",20)},
	{"Windpine","Hard",offerings(150)},
	{"Tidewater","Medium",thefts("Merchant",50)},
	{"Gloomhollow","Elite",thefts("VaultChest",50)},
	{"Tempest","Hard",{kind="level",skill="Prayer",level=70}},
	{"ShatteredCrown","Elite",thefts("SovereignCoffer",10)},
}) do
	local diary = Data.DiaryByRegion[add[1]]
	if diary and diary.tiers[add[2]] then table.insert(diary.tiers[add[2]].tasks, add[3]) end
end
end
-- End Prayer & Thieving section.



------------------------------------------------------------------------------
-- Treasure Trails (Treasure Trails team; append-only section).
-- OSRS-style clue scrolls with original Aether Isles riddles, maps and boxes.
-- Six tiers (Beginner..Master). A scroll drops from content of its difficulty
-- (kills, gathering, fishing, thieving, hunter catches); a player holds at most
-- one scroll or active trail per tier. Reading a scroll (verb trailBegin) seeds
-- a trail of tier-scaled steps drawn server-side.
-- This section is REPLICATED, so it holds only what clients need: tiers,
-- items, uniques, rewards, scroll sources, pacing, gesture names and the
-- sliding-puzzle moves. The step pool (anchors, offsets, riddle targets, emote
-- places, puzzle scrambles), trail generation, step text and the p.trails
-- sanitiser are server-only: trails.lua (ServerStorage.AetherTrails).
-- The last step yields a casket (trailOpen rolls TR.Rewards with server
-- entropy; Magic Find on rare rows). All names and rewards are original.
------------------------------------------------------------------------------
do
local TR = {}
Data.Trails = TR
TR.VERSION = 1
TR.DIG_RADIUS = 6        -- studs (horizontal) from the hidden point
TR.SEARCH_RADIUS = 14    -- studs from a riddle's NPC or landmark
TR.EMOTE_RADIUS = 12     -- studs from an emote landmark
TR.HEIGHT_TOLERANCE = 12 -- vertical slack (root part above ground)
TR.MAX_MOVES = 48        -- puzzle moves per trailSlide request ("Beginner:" + 48 <= 64 chars)
TR.SOLVED = "123456780"  -- 0 = the empty slot
TR.MASTER_FROM_ELITE = 0.1 -- chance an opened Elite casket holds a Master scroll
TR.SPADE = "TrailSpade"
-- Anti-bot pacing for location steps (dig / riddle / emote), server enforced:
-- a location step completes only MIN_STEP_SECONDS[tier] after it began, and
-- only once the reader could have travelled from the trail's previous location
-- step: distance / TRAVEL_SPEED seconds (max walk speed is 64 studs/s), capped
-- at WARP_SECONDS (any legitimate warp, leaf, beacon, Skyway or recall plus a
-- short walk from its landing).
TR.MIN_STEP_SECONDS = {Beginner=8,Easy=9,Medium=10,Hard=12,Elite=14,Master=15}
TR.TRAVEL_SPEED = 80
TR.WARP_SECONDS = 20
TR.TELEPORT_COOLDOWN = 30 -- seconds between waystone leaves (per player)
TR.ANCHOR_MISS_SECONDS = 5 -- a missing world anchor is looked up again after this long

TR.TierOrder = {"Beginner","Easy","Medium","Hard","Elite","Master"}
local BASE = {"Hub","Meadow","Quarry"}
local function regions(...)
	local set = {}
	for _, id in ipairs(BASE) do set[id] = true end
	for _, id in ipairs({...}) do set[id] = true end
	return set
end
-- steps = {min,max} steps per trail; level = reference level for balance;
-- stepSeconds/killSeconds = pacing model (verify-trails holds coins/h below the
-- comparable Thieving income at that level); scramble = puzzle box random-walk length.
TR.Tiers = {
	Beginner={name="Beginner",adj="Tattered",color="C9B79C",steps={1,3},level=5,stepSeconds=70,killSeconds=6,scramble=12,
		regions=regions(),kinds={dig=3,riddle=3,emote=2,skill=2,puzzle=0}},
	Easy={name="Easy",adj="Weathered",color="8FD18B",steps={2,4},level=20,stepSeconds=80,killSeconds=9,scramble=20,
		regions=regions("Windpine"),kinds={dig=3,riddle=3,emote=2,skill=2,puzzle=1}},
	Medium={name="Medium",adj="Sealed",color="6FB7E8",steps={3,5},level=40,stepSeconds=95,killSeconds=14,scramble=30,
		regions=regions("Windpine","Skyreach","Tidewater"),kinds={dig=3,riddle=3,emote=2,skill=2,puzzle=1}},
	Hard={name="Hard",adj="Gilded",color="C58BE8",steps={4,6},level=60,stepSeconds=110,killSeconds=20,scramble=44,
		regions=regions("Windpine","Skyreach","Tidewater","Gloomhollow","Tempest"),kinds={dig=3,riddle=3,emote=2,skill=2,puzzle=1}},
	Elite={name="Elite",adj="Starlit",color="F2C14E",steps={5,7},level=80,stepSeconds=130,killSeconds=28,scramble=60,
		regions=regions("Windpine","Skyreach","Tidewater","Gloomhollow","Tempest","ShatteredCrown"),kinds={dig=3,riddle=3,emote=2,skill=2,puzzle=1}},
	Master={name="Master",adj="Aurora",color="FF7FD0",steps={6,9},level=95,stepSeconds=150,killSeconds=34,scramble=80,
		regions=regions("Windpine","Skyreach","Tidewater","Gloomhollow","Tempest","ShatteredCrown"),kinds={dig=3,riddle=3,emote=2,skill=2,puzzle=1}},
}
TR.KindOrder = {"dig","riddle","emote","skill","puzzle"}
for i, id in ipairs(TR.TierOrder) do
	local t = TR.Tiers[id]
	t.id, t.index = id, i
	t.scroll, t.casket = "TrailScroll"..id, "TrailCasket"..id
end
function TR.tierIndex(id) local t = type(id) == "string" and TR.Tiers[id] return t and t.index or nil end

------------------------------------------------------------------------------
-- Items: scrolls, caskets, the spade, teleport scrolls (kind "trail": never a
-- Bazaar commodity or auction lot, so Ironman journals lose nothing).
------------------------------------------------------------------------------
local function item(id, def)
	def.id = id
	def.rarity = def.rarity or "Common"
	def.value = def.value or 1
	Data.Items[id] = def
	return def
end
local SCROLL_RARITY = {Beginner="Common",Easy="Uncommon",Medium="Rare",Hard="Epic",Elite="Legendary",Master="Mythic"}
for _, id in ipairs(TR.TierOrder) do
	local t = TR.Tiers[id]
	item(t.scroll,{name=t.adj.." Trail Scroll",kind="trail",category="scroll",trailTier=id,rarity=SCROLL_RARITY[id],color=t.color,value=1,
		description=id.." treasure trail. Read it from Satchel > Trails. One "..id.." trail at a time."})
	item(t.casket,{name=t.adj.." Trail Casket",kind="trail",category="casket",trailTier=id,rarity=SCROLL_RARITY[id],color=t.color,value=1,
		description="The prize at the end of a "..id.." trail. Open it from Satchel > Trails."})
end
item(TR.SPADE,{name="Wayfinder's Spade",kind="trail",category="spade",rarity="Common",color="8C6A43",value=6,
	description="A folding spade for trail digs. Kept, never used up. Forged at a Forge."})
Data.Recipes[TR.SPADE] = {id=TR.SPADE,output=TR.SPADE,amount=1,skill="Smithing",level=1,xp=15,costs={AlloyIngot=1,Timber=2},station="Forge",category="Tools"}
-- Teleport scrolls (common casket rows): one region each, consumed on use.
TR.Teleports = {
	{id="TeleScrollMeadow",region="Meadow",anchor="Waypoint_Entrance_Meadow",name="Meadow Reach"},
	{id="TeleScrollQuarry",region="Quarry",anchor="Waypoint_Entrance_CinderShelf",name="Cinder Shelf"},
	{id="TeleScrollWindpine",region="Windpine",anchor="Waypoint_Entrance_Windpine",name="Windpine Grove"},
	{id="TeleScrollSkyreach",region="Skyreach",anchor="Waypoint_Entrance_Skyreach",name="Skyreach"},
	{id="TeleScrollTidewater",region="Tidewater",anchor="Waypoint_Entrance_Tidewater",name="Tidewater Shoals"},
	{id="TeleScrollGloomhollow",region="Gloomhollow",anchor="Waypoint_Entrance_Gloomhollow",name="Gloomhollow Caverns"},
	{id="TeleScrollTempest",region="Tempest",anchor="Waypoint_Entrance_Tempest",name="Tempest Spire"},
	{id="TeleScrollCrown",region="ShatteredCrown",anchor="Waypoint_Entrance_ShatteredCrown",name="The Shattered Crown"},
}
TR.TeleportById = {}
for _, tp in ipairs(TR.Teleports) do
	TR.TeleportById[tp.id] = tp
	item(tp.id,{name="Waystone Leaf: "..tp.name,kind="trail",category="teleport",rarity="Uncommon",color="9EE7D2",value=8,
		description="Read to step through the Skyway to "..tp.name..". Needs the region unlocked. Consumed."})
end

------------------------------------------------------------------------------
-- Uniques: trail outfits, banners, emote scrolls, accessories and a pet.
------------------------------------------------------------------------------
-- Emotes unlocked by emote scrolls: a name played through a relay gesture.
TR.Emotes = {
	WayfarersJig={name="Wayfarer's Jig",gesture="flip"},
	CourtlyBow={name="Courtly Bow",gesture="interact"},
	GrandToast={name="Grand Toast",gesture="drink"},
	Starcall={name="Starcall",gesture="cast"},
	Benediction={name="Benediction",gesture="heal"},
	AuroraFlourish={name="Aurora Flourish",gesture="flick"},
}
TR.EmoteOrder = {"WayfarersJig","CourtlyBow","GrandToast","Starcall","Benediction","AuroraFlourish"}
local function outfit(prefix, name, rarity, color, stats, tierId)
	local ids = {}
	for _, piece in ipairs({{"Hood","helmet",0.6},{"Coat","chest",1},{"Breeches","legs",0.8},{"Boots","boots",0.5}}) do
		local id = prefix..piece[1]
		local s = {}
		for k, v in pairs(stats) do s[k] = math.max(1, math.floor(v * piece[3] + 0.5)) end
		item(id,{name=name.." "..piece[1],kind="armor",slot=piece[2],rarity=rarity,color=color,stats=s,value=40*Data.Rarity[rarity].rank^2,trailUnique=tierId,
			description="Trail outfit ("..tierId.."). Only a "..tierId.." Trail Casket holds it."})
		table.insert(ids, id)
	end
	return ids
end
local function banner(id, name, rarity, color, tierId, text)
	item(id,{name=name,kind="trail",category="banner",rarity=rarity,color=color,value=30*Data.Rarity[rarity].rank^2,trailUnique=tierId,
		description="Trail banner ("..tierId.."). Raise it from Satchel > Trails: "..text})
	return id
end
local function emoteScroll(id, emote, rarity, tierId)
	item(id,{name="Emote Scroll: "..TR.Emotes[emote].name,kind="trail",category="emote",emote=emote,rarity=rarity,color="E8D9A0",value=25*Data.Rarity[rarity].rank^2,trailUnique=tierId,
		description="Read to learn the "..TR.Emotes[emote].name.." emote for good."})
	return id
end
item("TrailCapWayfarer",{name="Wayfarer's Feathered Cap",kind="armor",slot="helmet",rarity="Uncommon",color="B5895A",stats={speed=2,health=4},value=60,trailUnique="Beginner",
	description="Trail outfit (Beginner). A cap with a gull feather that points the way home."})
local wayfarer = {"TrailCapWayfarer"}
local trailblazer = outfit("Trailblazer","Trailblazer","Rare","8FD18B",{defense=12,health=10,speed=2},"Easy")
local skyrover = outfit("Skyrover","Skyrover","Rare","6FB7E8",{defense=22,health=18,speed=3},"Medium")
local stormcart = outfit("Stormcart","Stormcartographer's","Epic","C58BE8",{defense=40,health=30,speed=4,magicFind=1},"Hard")
local gilded = outfit("GildedWay","Gilded Wayfarer","Legendary","F2C14E",{defense=60,health=45,speed=5,magicFind=2},"Elite")
local aurora = outfit("AuroraPath","Aurora Pathfinder","Mythic","FF7FD0",{defense=85,health=65,speed=6,magicFind=3},"Master")
item("CompassOfLostPaths",{name="Compass of Lost Paths",kind="accessory",rarity="Legendary",color="F2C14E",stats={magicFind=3,speed=3},value=40*Data.Rarity.Legendary.rank^2,trailUnique="Elite",
	description="Accessory. Magical Power "..Data.Rarity.Legendary.power..". Its needle never settles twice on the same island."})
item("EverwakeLantern",{name="Everwake Lantern",kind="accessory",rarity="Mythic",color="FF7FD0",stats={magicFind=5,intelligence=20,speed=4},value=40*Data.Rarity.Mythic.rank^2,trailUnique="Master",
	description="Accessory. Magical Power "..Data.Rarity.Mythic.power..". A lantern lit at the end of every trail at once."})
-- The Trailhound: a pet species (Agility) with its own abilities and look.
local hound = {id="Trailhound",name="Trailhound",skill="Agility",rarity="Legendary",color="C99A5B",perLevel={speed=0.25,magicFind=0.04,health=0.6}}
table.insert(Data.Pets, hound)
Data.PetById.Trailhound = hound
do
	local PD = Data.PetDepth
	local list = {
		{name="Scent of the Trail",kind="xp",skills={"Agility","Hunter"},per=0.1,rarity="Common"},
		{name="Nose for Treasure",kind="stat",stat="magicFind",per=0.04,rarity="Rare"},
		{name="Long Stride",kind="stat",stat="speed",per=0.15,rarity="Epic",level=40},
	}
	for i, a in ipairs(list) do a.index = i; a.id = a.name:gsub("[^%w]", "") end
	PD.Abilities.Trailhound = list
	PD.Looks.Trailhound = {form="quad",accent="F4E1C1"}
	hound.ability = list[1].name..": up to "..PD.abilityText(list[1], PD.abilityValue(list[1], Data.PET_MAX_LEVEL, PD.MAX_RARITY))
	hound.abilityNames = {list[1].name, list[2].name, list[3].name}
	item("TrailhoundPet",{name="Trailhound Pet",kind="pet",pet="Trailhound",rarity="Legendary",color="C99A5B",value=200*Data.Rarity.Legendary.rank^2,trailUnique="Master",
		description="Summon from your pet menu. Abilities: "..table.concat(hound.abilityNames, ", ")..". Found in Aurora Trail Caskets."})
	-- The Voidcrown Drake sometimes swallows a lost Trailhound (a second, very rare source).
	local drake = rawget(Data.Monsters, "VoidcrownDrake")
	if drake then table.insert(drake.drops, {item="TrailhoundPet",chance=0.0002,min=1,max=1}) end
end
-- Uniques listed per tier (the clue log grid). Emote scrolls and banners too.
TR.Uniques = {
	Beginner={wayfarer[1],banner("BannerMeadowlark","Meadowlark Pennant","Uncommon","C9B79C","Beginner","a pennant stitched with a lark over the Meadow."),
		emoteScroll("EmoteScrollJig","WayfarersJig","Uncommon","Beginner")},
	Easy={trailblazer[1],trailblazer[2],trailblazer[3],trailblazer[4],banner("BannerQuayward","Quayward Banner","Rare","8FD18B","Easy","the harbour's anchor on sea-green silk."),
		emoteScroll("EmoteScrollBow","CourtlyBow","Rare","Easy")},
	Medium={skyrover[1],skyrover[2],skyrover[3],skyrover[4],banner("BannerUpdraft","Updraft Standard","Rare","6FB7E8","Medium","a kestrel riding a white spiral."),
		emoteScroll("EmoteScrollToast","GrandToast","Rare","Medium")},
	Hard={stormcart[1],stormcart[2],stormcart[3],stormcart[4],banner("BannerStormchart","Stormchart Banner","Epic","C58BE8","Hard","a chart of the spire inked in lightning."),
		emoteScroll("EmoteScrollStarcall","Starcall","Epic","Hard")},
	Elite={gilded[1],gilded[2],gilded[3],gilded[4],"CompassOfLostPaths",banner("BannerSunken","Sunken Crown Banner","Legendary","F2C14E","Elite","a crown in six gold shards."),
		emoteScroll("EmoteScrollBenediction","Benediction","Legendary","Elite")},
	Master={aurora[1],aurora[2],aurora[3],aurora[4],"EverwakeLantern","TrailhoundPet",emoteScroll("EmoteScrollAurora","AuroraFlourish","Mythic","Master")},
}
TR.UniqueTier = {}
for _, id in ipairs(TR.TierOrder) do for _, u in ipairs(TR.Uniques[id]) do TR.UniqueTier[u] = id end end

------------------------------------------------------------------------------
-- Rewards: rolls per casket; each roll picks one weighted common row (coins or
-- a stack) and then checks every rare row (per-roll chance < 5%, so Magic Find
-- and, for the pet, Pet Luck raise it through Progression.rollDrops).
------------------------------------------------------------------------------
local function cr(itemId, lo, hi, w) return {item=itemId,min=lo,max=hi,weight=w} end
local function coins(lo, hi, w) return {coins={lo,hi},weight=w} end
local function rare(list, chances)
	local rows = {}
	for i, id in ipairs(list) do table.insert(rows, {item=id,chance=chances[i] or chances[#chances],min=1,max=1}) end
	return rows
end
TR.Rewards = {
	Beginner={rolls={1,3},common={coins(15,45,40),cr("Herb",3,8,10),cr("Timber",3,8,10),cr("Ore",3,8,10),cr("Fish",2,5,8),cr("ArcaneDust",1,3,8),
		cr("TeleScrollMeadow",1,1,4),cr("TeleScrollQuarry",1,1,4),cr("CookedFish",2,4,6)},
		rare=rare(TR.Uniques.Beginner,{1/40,1/50,1/45})},
	Easy={rolls={2,4},common={coins(40,110,40),cr("WindpineLog",3,8,8),cr("Brassite",3,8,8),cr("Glassfin",2,6,8),cr("Sunwheat",3,8,8),cr("ArcaneDust",2,5,8),
		cr("BrassIngot",1,2,4),cr("TeleScrollWindpine",1,1,4),cr("TeleScrollMeadow",1,2,3),cr("CookedGlassfin",2,4,5)},
		rare=rare(TR.Uniques.Easy,{1/80,1/80,1/80,1/80,1/90,1/90})},
	Medium={rolls={3,5},common={coins(100,280,40),cr("SunsteelOre",3,8,8),cr("EmberoakLog",3,8,8),cr("Stormeel",2,6,8),cr("Glowcap",3,8,8),cr("ArcaneDust",3,8,8),
		cr("SunsteelIngot",1,2,4),cr("TeleScrollSkyreach",1,1,3),cr("TeleScrollTidewater",1,1,3),cr("StormFeather",2,5,5)},
		rare=rare(TR.Uniques.Medium,{1/120,1/120,1/120,1/120,1/130,1/130})},
	Hard={rolls={4,6},common={coins(240,620,40),cr("Voidstone",3,8,8),cr("GlimmerbarkLog",3,8,8),cr("Lanternray",2,6,8),cr("Moonbloom",3,8,8),cr("VoidEssence",1,3,6),
		cr("VoidforgedIngot",1,2,4),cr("TeleScrollGloomhollow",1,1,3),cr("TeleScrollTempest",1,1,3),cr("ArcaneDust",5,12,6)},
		rare=rare(TR.Uniques.Hard,{1/200,1/200,1/200,1/200,1/220,1/220})},
	Elite={rolls={4,6},common={coins(600,1500,40),cr("StarmetalOre",3,8,8),cr("StarwoodLog",3,8,8),cr("AbyssKoi",2,6,8),cr("Starfruit",3,8,8),cr("VoidEssence",2,5,6),
		cr("StarmetalIngot",1,2,4),cr("TeleScrollCrown",1,1,3),cr("StarFragment",1,1,1),cr("ArcaneDust",8,20,6)},
		rare=rare(TR.Uniques.Elite,{1/300,1/300,1/300,1/300,1/450,1/350,1/320})},
	Master={rolls={5,7},common={coins(1400,3400,40),cr("Prismite",3,8,8),cr("AetherheartLog",3,8,8),cr("LeviathanScale",2,6,8),cr("AetherLotus",3,8,8),cr("VoidEssence",3,8,6),
		cr("PrismaticIngot",1,2,4),cr("TeleScrollCrown",1,2,3),cr("StarFragment",1,2,2),cr("ArcaneDust",12,30,6)},
		rare=rare(TR.Uniques.Master,{1/400,1/400,1/400,1/400,1/700,1/1000,1/450})},
}
for _, id in ipairs(TR.TierOrder) do
	local r = TR.Rewards[id]
	r.totalWeight = 0
	for _, row in ipairs(r.common) do r.totalWeight += row.weight end
end
-- Merchant value of a reward row (coins count at face value).
local function rowValue(row)
	if row.coins then return (row.coins[1] + row.coins[2]) / 2 end
	local def = Data.Items[row.item]
	return (row.min + row.max) / 2 * (def and def.value or 0)
end
-- Expected value of one casket (coins + merchant value of every row).
function TR.expectedCasket(tierId, magicFind)
	local r = TR.Rewards[tierId]
	local perRoll = 0
	for _, row in ipairs(r.common) do perRoll += row.weight / r.totalWeight * rowValue(row) end
	for _, row in ipairs(r.rare) do
		local c = row.chance * (if row.chance < 0.05 then 1 + (magicFind or 0) / 100 else 1)
		perRoll += c * rowValue(row)
	end
	return perRoll * (r.rolls[1] + r.rolls[2]) / 2
end
-- Roll one casket. rng() -> [0,1); rollDrops = Progression.rollDrops.
-- Returns {coins=n, items={[id]=n}, uniques={[id]=n}, master=bool}.
function TR.openCasket(tierId, rng, magicFind, petLuck, rollDrops)
	local r = TR.Rewards[tierId]
	local out = {coins=0,items={},uniques={},master=false}
	local rolls = r.rolls[1] + math.floor(rng() * (r.rolls[2] - r.rolls[1] + 1))
	for _ = 1, rolls do
		local pick = rng() * r.totalWeight
		local chosen = r.common[#r.common]
		for _, row in ipairs(r.common) do
			pick -= row.weight
			if pick < 0 then chosen = row break end
		end
		if chosen.coins then
			out.coins += chosen.coins[1] + math.floor(rng() * (chosen.coins[2] - chosen.coins[1] + 1))
		else
			out.items[chosen.item] = (out.items[chosen.item] or 0) + chosen.min + math.floor(rng() * (chosen.max - chosen.min + 1))
		end
		for id, n in pairs(rollDrops(r.rare, magicFind or 0, rng, petLuck or 0)) do
			out.items[id] = (out.items[id] or 0) + n
			out.uniques[id] = (out.uniques[id] or 0) + n
		end
	end
	if tierId == "Elite" and rng() < TR.MASTER_FROM_ELITE then out.master = true end
	return out
end

------------------------------------------------------------------------------
-- Scroll sources: the tier follows the content's level; chance per event.
------------------------------------------------------------------------------
TR.LevelBands = {{15,"Beginner"},{30,"Easy"},{50,"Medium"},{75,"Hard"},{math.huge,"Elite"}}
TR.SourceChance = {
	kill={Beginner=1/40,Easy=1/64,Medium=1/96,Hard=1/128,Elite=1/192},
	gather={Beginner=1/260,Easy=1/300,Medium=1/350,Hard=1/420,Elite=1/560},
	fish={Beginner=1/200,Easy=1/240,Medium=1/280,Hard=1/330,Elite=1/520},
	thieve={Beginner=1/200,Easy=1/260,Medium=1/340,Hard=1/420,Elite=1/700},
	catch={Beginner=1/45,Easy=1/110,Medium=1/120,Hard=1/130,Elite=1/140},
}
TR.MASTER_KILL_LEVEL = 100
TR.MASTER_KILL_CHANCE = 1/2000
function TR.tierForLevel(level)
	level = tonumber(level) or 1
	for _, band in ipairs(TR.LevelBands) do if level < band[1] then return band[2] end end
	return "Elite"
end
-- Level of the content behind an event (kind, id) or nil.
function TR.sourceLevel(kind, id)
	if type(id) ~= "string" then return nil end
	if kind == "kill" then
		local m = Data.Monsters[id]
		return m and m.level
	elseif kind == "gather" or kind == "fish" then
		local skill = Data.ResourceSkill[id]
		if not skill then return nil end
		for _, r in ipairs(Data.ResourceTiers[skill]) do if r.id == id then return r.level end end
	elseif kind == "thieve" then
		local t = Data.Thieving and Data.Thieving.TargetById[id]
		return t and t.level
	elseif kind == "catch" then
		local c = Data.Hunter and Data.Hunter.CreatureById[id]
		return c and c.level
	end
	return nil
end
-- Rolls for one event: list of {tier, chance}.
function TR.dropsFor(kind, id)
	local level = TR.sourceLevel(kind, id)
	local table_ = TR.SourceChance[kind]
	if not level or not table_ then return {} end
	local tier = TR.tierForLevel(level)
	local out = {{tier=tier,chance=table_[tier]}}
	if kind == "kill" and level >= TR.MASTER_KILL_LEVEL then table.insert(out, {tier="Master",chance=TR.MASTER_KILL_CHANCE}) end
	return out
end
-- Pacing model. SourceSeconds = the fastest pace (seconds per drop event) of
-- each source at each tier's content: kill = the tier's killSeconds; gather and
-- fish = the gather action (1.65 s, nodes rotated so respawns never wait);
-- thieve = (action + expected stun) / success at the 95% cap; catch = five
-- traps (or three net spots) at the level-99 / Trap Luck-cap catch chance.
-- verify-trails derives these from Data.Thieving / Data.Hunter and checks the
-- table is never slower than the systems allow. A scroll comes from the
-- fastest source; Master scrolls come in parallel from Elite caskets (and the
-- mightiest kills), so Elite income carries the Master trails it chains into.
TR.SourceSeconds = {
	gather={Beginner=1.65,Easy=1.65,Medium=1.65,Hard=1.65,Elite=1.65},
	fish={Beginner=1.65,Easy=1.65,Medium=1.65,Hard=1.65,Elite=1.65},
	thieve={Beginner=1.25,Easy=1.25,Medium=1.25,Hard=1.25,Elite=1.25},
	catch={Beginner=1.4,Easy=2.1,Medium=7.4,Hard=12,Elite=15.8},
}
TR.SourceSeconds.kill = {}
for _, id in ipairs(TR.TierOrder) do if id ~= "Master" then TR.SourceSeconds.kill[id] = TR.Tiers[id].killSeconds end end
function TR.avgSteps(tierId) local s = TR.Tiers[tierId].steps return (s[1] + s[2]) / 2 end
-- Fastest seconds per scroll of a tier and the source that gives it.
function TR.scrollSeconds(tierId)
	local best, from = math.huge, nil
	for kind, list in pairs(TR.SourceChance) do
		local pace = TR.SourceSeconds[kind] and TR.SourceSeconds[kind][tierId]
		if pace and list[tierId] then
			local s = pace / list[tierId]
			if s < best then best, from = s, kind end
		end
	end
	return best, from
end
-- Seconds per step: the modelled walk (stepSeconds) or, with bot = true, the
-- enforced floor (MIN_STEP_SECONDS: a perfect bot that never travels).
local function stepTime(tierId, bot)
	return if bot then TR.MIN_STEP_SECONDS[tierId] else TR.Tiers[tierId].stepSeconds
end
-- Seconds to earn and walk one trail of a tier (Master: the Elite trails that
-- find one, plus its own steps).
function TR.clueSeconds(tierId, bot)
	if tierId == "Master" then
		return TR.clueSeconds("Elite", bot) / TR.MASTER_FROM_ELITE + TR.avgSteps("Master") * stepTime("Master", bot)
	end
	return TR.scrollSeconds(tierId) + TR.avgSteps(tierId) * stepTime(tierId, bot)
end
-- Coins per hour of farming a tier. Elite also earns the Master trails its
-- caskets hold, walked in the same hour (parallel tiers).
function TR.coinsPerHour(tierId, magicFind, bot)
	if tierId == "Elite" then
		local m = TR.MASTER_FROM_ELITE
		local coins = TR.expectedCasket("Elite", magicFind) + m * TR.expectedCasket("Master", magicFind)
		local seconds = TR.clueSeconds("Elite", bot) + m * TR.avgSteps("Master") * stepTime("Master", bot)
		return 3600 * coins / seconds
	end
	return 3600 * TR.expectedCasket(tierId, magicFind) / TR.clueSeconds(tierId, bot)
end
-- Comparable activity: the best Thieving income at the tier's reference level
-- (no gloves, no Deftness), the activity trails compete with for time.
function TR.referenceCoinsPerHour(tierId)
	local TH = Data.Thieving
	local level = TR.Tiers[tierId].level
	local best = 0
	for _, target in ipairs(TH.Targets) do
		if target.level <= level then best = math.max(best, TH.coinsPerHour(target, TH.chance(target, level, 0, 0))) end
	end
	return best
end

------------------------------------------------------------------------------
-- Gestures (subset of the gesture relay's names) and the sliding puzzle.
------------------------------------------------------------------------------
TR.Gestures = {flip="Flourish",heal="Benediction",cast="Starcall",interact="Bow",drink="Toast",stir="Stir",hammer="Anvil Salute",
	fish="Cast a Line",mine="Pick Strike",settrap="Kneel",netswing="Net Sweep",saw="Saw",attack="Salute",shoot="Loose",flick="Wand Flick",harvest="Reap",chop="Chop",eat="Feast"}
-- Sliding puzzle: board = 9-char string of digits, "0" = the gap. A move
-- letter names where the gap travels (U/D/L/R).
local DIRS = {U={0,-1},D={0,1},L={-1,0},R={1,0}}
TR.Opposite = {U="D",D="U",L="R",R="L"}
function TR.validBoard(board)
	if type(board) ~= "string" or #board ~= 9 then return false end
	local seen = {}
	for i = 1, 9 do
		local c = board:sub(i, i)
		if not c:match("%d") or tonumber(c) > 8 or seen[c] then return false end
		seen[c] = true
	end
	return true
end
function TR.slide(board, dir)
	local d = DIRS[dir]
	if not d or not TR.validBoard(board) then return nil end
	local gap = string.find(board, "0", 1, true)
	local x, y = (gap - 1) % 3, (gap - 1) // 3
	local nx, ny = x + d[1], y + d[2]
	if nx < 0 or nx > 2 or ny < 0 or ny > 2 then return nil end
	local other = ny * 3 + nx + 1
	local cells = {}
	for i = 1, 9 do cells[i] = board:sub(i, i) end
	cells[gap], cells[other] = cells[other], cells[gap]
	return table.concat(cells)
end
-- Apply a move string; returns the board or nil, index of the first illegal move.
function TR.applyMoves(board, moves)
	if type(moves) ~= "string" or #moves == 0 or #moves > TR.MAX_MOVES then return nil, 0 end
	for i = 1, #moves do
		board = TR.slide(board, moves:sub(i, i))
		if not board then return nil, i end
	end
	return board
end
end
-- End Treasure Trails section.


------------------------------------------------------------------------------
-- Slayer tasks (Slayer team; append-only section). OSRS-style Slayer.
--
-- Two Slayer progressions coexist:
--   * The Slayer SKILL (Data.Skills.Slayer, levels 1-99 on the shared OSRS curve,
--     p.xp.Slayer) is trained by killing the monsters of an assigned TASK
--     (ST.killXp: one Slayer XP per ST.HP_PER_XP max health, so a task kill pays
--     about its Combat XP again) and by slaying boss-line bosses
--     (ST.bossXp: half the boss's health in the same unit).
--   * The three SkyBlock-style boss lines (Data.Slayers: Bramble/Gloom/Tempest,
--     p.slayerXp, levels 1-9) are unchanged and are shown as LINE RANKS.
-- Masters (ST.Masters, Combat / Slayer gates) assign weighted tasks: a monster
-- FAMILY (ST.Families) and an amount. Only families the player can reach are
-- offered: Slayer level, region access (Data.Regions requirements) and, for the
-- sea creature family, the Fishing level to hook one in reachable water.
-- Completing a task pays Slayer points (master points x the streak multiplier
-- of that task number: every 10th x5, 50th x15, 100th x25, 250th x35, 1000th
-- x50) and the master's coin bounty. Points buy: a task skip (streak kept), a
-- block slot entry (up to ST.blockSlots families), unlocks (superiors, the
-- Hunter's Visor, extended tasks, gilded bounties, wider ledger), consumables
-- and titles. Cancelling a task is free but resets the streak.
-- Superiors (unlock "SuperiorCalling"): each task kill of a land family rolls
-- ST.SUPERIOR_CHANCE (1/150) to raise that monster's superior variant
-- (Data.Monsters[id] via __index, not iterated): 8x health, harder hits, owned
-- by the task holder, unique loot (ST.SuperiorLoot). Slayer-only monsters
-- (def.slayerLevel) cannot be harmed below that Slayer level.
-- server.server.lua (Slayer tasks block) runs tasks, points and tickets;
-- combat.server.lua (Slayer tasks section) gates damage, applies the visor and
-- spawns superiors; world.server.lua places the slayer-only monsters and the
-- masters' anchors; ui.client.lua draws Hunt > Slayer. Tests: verify-slayer-tasks.luau.
------------------------------------------------------------------------------
do
local ST = {}
Data.SlayerTasks = ST
local CS, PR = Data.CombatStyles, Data.Prayer
ST.HP_PER_XP = 25            -- task kill Slayer XP = max health / HP_PER_XP
ST.BOSS_XP_SHARE = 0.5       -- boss-line bosses: half of that
ST.SKIP_COST = 30            -- points to skip the current task (streak kept)
ST.BLOCK_COST = 100          -- points to block a family
ST.BLOCK_SLOTS = 3           -- base block slots (+2 with Wider Ledger)
ST.EXTEND_MULT = 1.5         -- extended task amounts
ST.SUPERIOR_CHANCE = 1 / 150 -- per task kill, once Call of the Superior is unlocked
ST.SUPERIOR_LIFETIME = 240   -- seconds before an unfought superior withdraws
ST.SUPERIOR_LIVE = 2         -- live superior tickets per player
ST.SUPERIOR_HP = 8           -- multipliers over the base monster
ST.SUPERIOR_DAMAGE = 1.5
ST.SUPERIOR_DEFENSE = 1.25
ST.SUPERIOR_COINS = 10
ST.MAX_AMOUNT = 400          -- sanity bound on any saved task amount
ST.TASK_SHARE = 0.2          -- task credit: a killer must deal this share of max health (or be the top damager)
ST.SUPERIOR_LEVEL_RATIO = 1 / 3 -- no superior roll when the base monster's level < Combat level x this
ST.SUPERIOR_RARE_LEVEL = 40  -- Eclipsed Ichor and the Duskhunter Sigil drop only from superiors of base level >= this
ST.MIN_CANDIDATES = 2        -- a block may not leave any available master fewer families than this
-- Streak multipliers, highest milestone first (task number divisible by `every`).
ST.Streak = {{every=1000,mult=50},{every=250,mult=35},{every=100,mult=25},{every=50,mult=15},{every=10,mult=5}}

-- The skill ------------------------------------------------------------------
table.insert(Data.SkillOrder, "Slayer")
Data.Skills.Slayer = {category="combat",color="B23A48",title="Grimhunter",perLevel={critDamage=0.3,strength=0.2},
	description="Hunt the monsters a Slayer master assigns. Raises Crit Damage and Strength. Boss-line ranks are kept separately."}

-- Items ---------------------------------------------------------------------
item("HushcapSpore",{name="Hushcap Spore",kind="material",rarity="Uncommon",color="A3B86C",value=60,description="A spore that swallows sound. Dropped by Hollowcap Shriekers."})
item("MirrorscaleShard",{name="Mirrorscale Shard",kind="material",rarity="Rare",color="7FC8C0",value=180,description="A scale that reflects a stare. Dropped by Mirrorscale Basilisks."})
item("ThunderhidePlate",{name="Thunderhide Plate",kind="material",rarity="Rare",color="6E7A8A",value=400,description="Storm-hardened hide. Dropped by Thundercrag Gargants."})
item("DreadmawFang",{name="Dreadmaw Fang",kind="material",rarity="Epic",color="5B3E7A",value=1200,description="A fang that drinks the light. Dropped by Umbral Dreadmaws."})
item("EclipsedIchor",{name="Eclipsed Ichor",kind="material",rarity="Epic",color="7A1F3D",value=800,description="Ichor of a superior monster. Imbues slayer headgear."})
local function charm(id, name, rarity, stats, text)
	item(id,{name=name,kind="accessory",rarity=rarity,color=Data.Rarity[rarity].color,stats=stats,value=600*Data.Rarity[rarity].rank^2,slayerUnique=true,
		description="Accessory. Magical Power "..Data.Rarity[rarity].power..". "..text})
end
charm("HushbellCharm","Hushbell Charm","Rare",{critChance=2,intelligence=10},"A rare Hollowcap Shrieker drop.")
charm("MirrorgazeAmulet","Mirrorgaze Amulet","Epic",{defense=25,critDamage=8},"A rare Mirrorscale Basilisk drop.")
charm("StormcragGauntlet","Stormcrag Gauntlet","Epic",{strength=20,critDamage=10},"A rare Thundercrag Gargant drop.")
charm("DreadmawMantle","Dreadmaw Mantle","Legendary",{strength=25,critDamage=25},"A rare Umbral Dreadmaw drop.")
charm("DuskhunterSigil","Duskhunter Sigil","Legendary",{strength=15,critChance=3,critDamage=15,magicFind=3},"Carried off a superior monster.")
item("HuntersVisor",{name="Hunter's Visor",kind="armor",slot="helmet",rarity="Epic",color="B23A48",stats={defense=40,health=30,strength=10},requires={Slayer=40},
	slayerBonus={damage=15,accuracy=15},value=6000,description="Slayer headgear: +15% damage and accuracy against your task's monsters. Requires Slayer 40."})
item("RadiantHuntersVisor",{name="Radiant Hunter's Visor",kind="armor",slot="helmet",rarity="Legendary",color="E8556B",stats={defense=90,health=70,strength=25,critDamage=10},requires={Slayer=75},
	slayerBonus={damage=22,accuracy=22},value=40000,description="Imbued slayer headgear: +22% damage and accuracy against your task's monsters. Requires Slayer 75."})
item("SlayersBrew",{name="Slayer's Brew",kind="consumable",category="buff",rarity="Rare",color="B23A48",buff={stats={strength=25,critDamage=20},duration=600},value=120,
	description="+25 Strength, +20 Crit Damage for 10 minutes. Bought with Slayer points."})

-- Slayer-only monsters (marker monsters: damage needs def.slayerLevel) -------
local slayerOnly = {
	HollowcapShrieker={name="Hollowcap Shrieker",level=46,region="Gloomhollow",hp=5200,damage=240,defense=110,xp=190,coins=48,speed=13,color="A3B86C",style="magic",slayerLevel=40,
		drops={{item="HushcapSpore",chance=0.7,min=1,max=3},{item="ArcaneDust",chance=0.5,min=2,max=5},{item="VoidEssence",chance=0.15,min=1,max=1},{item="HushbellCharm",chance=0.0025,min=1,max=1}}},
	MirrorscaleBasilisk={name="Mirrorscale Basilisk",level=60,region="Tidewater",hp=9500,damage=350,defense=220,xp=290,coins=70,speed=12,color="7FC8C0",style="ranged",slayerLevel=60,
		drops={{item="MirrorscaleShard",chance=0.6,min=1,max=2},{item="ShoalPearl",chance=0.1,min=1,max=1},{item="ArcaneDust",chance=0.6,min=3,max=6},{item="MirrorgazeAmulet",chance=0.002,min=1,max=1}}},
	ThundercragGargant={name="Thundercrag Gargant",level=78,region="Tempest",hp=18000,damage=540,defense=320,xp=470,coins=110,speed=10,color="6E7A8A",style="melee",slayerLevel=75,
		drops={{item="ThunderhidePlate",chance=0.5,min=1,max=2},{item="StormFeather",chance=0.6,min=2,max=4},{item="StarFragment",chance=0.008,min=1,max=1},{item="StormcragGauntlet",chance=0.0016,min=1,max=1}}},
	UmbralDreadmaw={name="Umbral Dreadmaw",level=96,region="ShatteredCrown",hp=52000,damage=1000,defense=420,xp=1050,coins=210,speed=17,color="2E1F3D",style="magic",slayerLevel=85,
		drops={{item="DreadmawFang",chance=0.45,min=1,max=1},{item="CrownShard",chance=0.6,min=2,max=4},{item="VoidEssence",chance=0.6,min=2,max=4},{item="StarFragment",chance=0.02,min=1,max=1},{item="DreadmawMantle",chance=0.00125,min=1,max=1}}},
}
ST.SlayerOnlyOrder = {"HollowcapShrieker","MirrorscaleBasilisk","ThundercragGargant","UmbralDreadmaw"}
for _, id in ipairs(ST.SlayerOnlyOrder) do
	local def = slayerOnly[id]
	def.id = id
	CS.monsterStyle[id] = def.style
	def.attackStyle, def.weakness, def.defenceStyle = def.style, CS.beatenBy[def.style], CS.beats[def.style]
	def.style = nil
	table.insert(def.drops, {item=PR.remainsFor(def.level, def.region, false),chance=1,min=1,max=1})
	Data.Monsters[id] = def
	local region = Data.RegionById[def.region]
	region.monsters = region.monsters or {}
	table.insert(region.monsters, id)
end
-- Slayer level needed to harm a monster (0 = anyone).
function ST.slayerLevelFor(monsterId)
	local def = type(monsterId) == "string" and Data.Monsters[monsterId]
	return type(def) == "table" and tonumber(def.slayerLevel) or 0
end
function ST.canHarm(monsterId, slayerLevel)
	local need = ST.slayerLevelFor(monsterId)
	return (tonumber(slayerLevel) or 1) >= need, need
end

-- Families -------------------------------------------------------------------
-- monsters: marker monsters (or sea creatures when sea = true); slayer = level
-- needed to be assigned the family; epithet names its superiors.
ST.Families = {
	{id="Thicketkin",name="Thicketkin",slayer=1,color="5E8C4A",epithet="Thornsworn",monsters={"BramblebackBoar","Thornling","BarkStalker"}},
	{id="Burrowers",name="Burrowers",slayer=1,color="8C7A6B",epithet="Magmaborn",monsters={"ShaleCrawler","CinderMite"}},
	{id="Galeborn",name="Galeborn",slayer=10,color="A8DADC",epithet="Squallheart",monsters={"GaleSprite","StormHarrier"}},
	{id="Reefstalkers",name="Reefstalkers",slayer=15,color="06D6A0",epithet="Brinegorged",monsters={"ReefLurker"}},
	{id="Automatons",name="Automatons",slayer=20,color="D4A84B",epithet="Overwound",monsters={"BrassGolem","StarbornSentinel"}},
	{id="Gloomweavers",name="Gloomweavers",slayer=25,color="3D3D5C",epithet="Gravesilk",monsters={"GloomfangSpider"}},
	{id="Voidspawn",name="Voidspawn",slayer=30,color="6A4C93",epithet="Hollowed",monsters={"VoidWisp"}},
	{id="Shriekcaps",name="Shriekcaps",slayer=40,color="A3B86C",epithet="Deafening",monsters={"HollowcapShrieker"}},
	{id="Stormwraiths",name="Stormwraiths",slayer=45,color="4B6584",epithet="Thunderwrought",monsters={"TempestWraith"}},
	{id="Deepwater",name="Deepwater Horrors",slayer=50,color="2F6F8F",sea=true,monsters={"CoralbackBruiser","StormcoilSerpent","DuskfinManta","TidewyrmMatriarch"}},
	{id="Mirrorscales",name="Mirrorscales",slayer=60,color="7FC8C0",epithet="Petrifying",monsters={"MirrorscaleBasilisk"}},
	{id="Crownbound",name="Crownbound",slayer=70,color="C9A24D",epithet="Crownwrought",monsters={"RiftmawStalker","ShardglassSeer","CrownforgedColossus","VoidcrownDrake"}},
	{id="Thundercrags",name="Thundercrags",slayer=75,color="6E7A8A",epithet="Skybreaker",monsters={"ThundercragGargant"}},
	{id="Dreadmaws",name="Dreadmaws",slayer=85,color="5B3E7A",epithet="Nightmare",monsters={"UmbralDreadmaw"}},
}
ST.FamilyById, ST.FamilyOf = {}, {}
for i, f in ipairs(ST.Families) do
	f.index = i
	ST.FamilyById[f.id] = f
	for _, id in ipairs(f.monsters) do
		assert(Data.Monsters[id], "slayer family "..f.id.." names unknown monster "..id)
		ST.FamilyOf[id] = f.id
	end
end
function ST.inFamily(familyId, monsterId)
	return familyId ~= nil and ST.FamilyOf[monsterId] == familyId
end

-- Superiors --------------------------------------------------------------------
-- Fixed superior drops scale with the base monster's level, so a weak family
-- cannot be farmed for endgame materials: Slayer Seals (chance and amount grow
-- with level), Eclipsed Ichor and the Duskhunter Sigil only from base level
-- ST.SUPERIOR_RARE_LEVEL up (Ichor amount and Sigil chance grow to level 90+).
function ST.superiorUniques(baseLevel)
	local lvl = math.max(1, math.floor(tonumber(baseLevel) or 1))
	local drops = {{item="SlayerToken",chance=math.min(1, 0.2 + lvl / 50),min=1,max=math.max(1, math.floor(lvl / 25))}}
	if lvl >= ST.SUPERIOR_RARE_LEVEL then
		table.insert(drops, 1, {item="EclipsedIchor",chance=1,min=math.max(1, math.floor(lvl / 50)),max=math.max(1, math.floor(lvl / 30))})
		table.insert(drops, {item="DuskhunterSigil",chance=math.min(1 / 40, lvl / 3600),min=1,max=1})
	end
	return drops
end
ST.Superiors, ST.SuperiorOf, ST.SuperiorOrder = {}, {}, {}
for _, f in ipairs(ST.Families) do
	if not f.sea then
		for _, baseId in ipairs(f.monsters) do
			local base = Data.Monsters[baseId]
			local id = "Superior"..baseId
			local drops = ST.superiorUniques(base.level)
			for _, d in ipairs(base.drops) do
				if not (PR.RemainsById and PR.RemainsById[d.item]) then
					table.insert(drops, {item=d.item,chance=math.min(1, d.chance*3),min=d.min*2,max=d.max*3})
				end
			end
			local def = {id=id,name=f.epithet.." "..base.name,level=base.level+10,region=base.region,hp=base.hp*ST.SUPERIOR_HP,
				damage=math.floor(base.damage*ST.SUPERIOR_DAMAGE),defense=math.floor((base.defense or 0)*ST.SUPERIOR_DEFENSE),
				xp=base.xp*ST.SUPERIOR_HP,coins=base.coins*ST.SUPERIOR_COINS,speed=base.speed,color=base.color,superior=true,base=baseId,family=f.id,
				slayerLevel=base.slayerLevel,attackStyle=base.attackStyle,weakness=base.weakness,defenceStyle=base.defenceStyle,drops=drops}
			ST.Superiors[id] = def
			ST.SuperiorOf[baseId] = id
			table.insert(ST.SuperiorOrder, id)
		end
	end
end
-- Lookups by id reach superiors too; pairs(Data.Monsters) still lists marker monsters only.
do
	local previous = getmetatable(Data.Monsters)
	local fallback = previous and previous.__index
	setmetatable(Data.Monsters, {__index = function(t, id)
		local found = if type(fallback) == "function" then fallback(t, id) elseif type(fallback) == "table" then fallback[id] else nil
		return found or rawget(ST.Superiors, id)
	end})
end
-- One task kill: the superior variant's id when the roll hits, else nil.
-- combatLevel (optional): no roll when the base monster is far below the killer
-- (level < Combat x ST.SUPERIOR_LEVEL_RATIO), so trivial kills raise nothing.
function ST.rollSuperior(unlocked, monsterId, roll, combatLevel)
	if not unlocked then return nil end
	local id = ST.SuperiorOf[monsterId]
	if not id or type(roll) ~= "function" then return nil end
	local base = Data.Monsters[monsterId]
	if (tonumber(base and base.level) or 0) < (tonumber(combatLevel) or 0) * ST.SUPERIOR_LEVEL_RATIO then return nil end
	if roll() >= ST.SUPERIOR_CHANCE then return nil end
	return id
end

-- Masters ----------------------------------------------------------------------
-- tasks: {family, weight, min, max}. points: Slayer points per completed task
-- (before the streak multiplier); bounty: coins per completed task.
ST.Masters = {
	{id="Ysolde",npc="Slayer",name="Captain Ysolde Thornmantle",region="Hub",combat=3,slayer=1,points=2,bounty=150,color="B23A48",
		blurb="The guild's first master: short tasks close to home.",
		tasks={{family="Thicketkin",weight=8,min=15,max=40},{family="Burrowers",weight=8,min=15,max=40},{family="Galeborn",weight=6,min=15,max=35},
			{family="Reefstalkers",weight=4,min=10,max=30},{family="Automatons",weight=3,min=10,max=25},{family="Gloomweavers",weight=3,min=10,max=25}}},
	{id="Corvane",npc="SlayerCorvane",name="Warden Corvane Mossgrave",region="Windpine",combat=20,slayer=1,points=6,bounty=600,color="5E8C4A",
		blurb="A grove warden who sends hunters into the caves and the storm.",
		tasks={{family="Thicketkin",weight=3,min=50,max=90},{family="Galeborn",weight=6,min=40,max=80},{family="Reefstalkers",weight=6,min=30,max=70},
			{family="Automatons",weight=7,min=30,max=70},{family="Gloomweavers",weight=8,min=30,max=70},{family="Voidspawn",weight=6,min=30,max=60},
			{family="Shriekcaps",weight=6,min=30,max=60},{family="Stormwraiths",weight=4,min=25,max=50}}},
	{id="Maelis",npc="SlayerMaelis",name="Sister Maelis Duskward",region="Gloomhollow",combat=45,slayer=20,points=10,bounty=2000,color="6A4C93",
		blurb="A lantern-nun of the deep who keeps the dark in check.",
		tasks={{family="Automatons",weight=6,min=60,max=100},{family="Gloomweavers",weight=6,min=60,max=110},{family="Voidspawn",weight=8,min=60,max=110},
			{family="Shriekcaps",weight=8,min=60,max=110},{family="Stormwraiths",weight=8,min=50,max=100},{family="Deepwater",weight=5,min=20,max=40},
			{family="Mirrorscales",weight=7,min=50,max=100},{family="Thundercrags",weight=5,min=40,max=80}}},
	{id="Vesper",npc="SlayerVesper",name="Vesper Harrowgale",region="Tempest",combat=75,slayer=50,points=15,bounty=5000,color="4B6584",
		blurb="The storm's own huntress. Only the hardest prey.",
		tasks={{family="Automatons",weight=5,min=100,max=150},{family="Voidspawn",weight=5,min=110,max=170},{family="Stormwraiths",weight=8,min=110,max=170},
			{family="Deepwater",weight=6,min=40,max=70},{family="Mirrorscales",weight=8,min=110,max=170},{family="Crownbound",weight=9,min=100,max=160},
			{family="Thundercrags",weight=8,min=100,max=160},{family="Dreadmaws",weight=7,min=90,max=150}}},
}
ST.MasterById = {}
for i, m in ipairs(ST.Masters) do
	m.index = i
	ST.MasterById[m.id] = m
	for _, t in ipairs(m.tasks) do assert(ST.FamilyById[t.family], m.id.." assigns unknown family "..t.family) end
end

-- Points shop --------------------------------------------------------------------
-- kind: unlock (one-time, p.slayerTasks.unlocks[id]), extend (unlock that makes
-- that family's tasks ST.EXTEND_MULT longer), consumable (repeatable, gives
-- items), title (one-time cosmetic), craft (assemble gear from drops; needs `unlock`).
ST.Shop = {
	{id="SuperiorCalling",kind="unlock",name="Call of the Superior",cost=150,text="Task kills may raise superior monsters (1 in 150) with unique loot."},
	{id="VisorCrafting",kind="unlock",name="Visorwright's Lore",cost=80,text="Learn to assemble the Hunter's Visor from slayer drops."},
	{id="GildedBounty",kind="unlock",name="Gilded Bounties",cost=120,text="Masters pay double coin bounties on completed tasks."},
	{id="WiderLedger",kind="unlock",name="Wider Ledger",cost=200,text="Two more block slots."},
	{id="ExtendGloomweavers",kind="extend",family="Gloomweavers",name="Endless Silk",cost=60,text="Gloomweaver tasks are 50% longer."},
	{id="ExtendVoidspawn",kind="extend",family="Voidspawn",name="Void Without End",cost=70,text="Voidspawn tasks are 50% longer."},
	{id="ExtendStormwraiths",kind="extend",family="Stormwraiths",name="Ceaseless Storm",cost=80,text="Stormwraith tasks are 50% longer."},
	{id="ExtendMirrorscales",kind="extend",family="Mirrorscales",name="Hall of Mirrors",cost=90,text="Mirrorscale tasks are 50% longer."},
	{id="ExtendCrownbound",kind="extend",family="Crownbound",name="Crown Unbroken",cost=100,text="Crownbound tasks are 50% longer."},
	{id="ExtendThundercrags",kind="extend",family="Thundercrags",name="Rolling Thunder",cost=100,text="Thundercrag tasks are 50% longer."},
	{id="ExtendDreadmaws",kind="extend",family="Dreadmaws",name="Long Night",cost=120,text="Dreadmaw tasks are 50% longer."},
	{id="BuySlayersBrew",kind="consumable",name="Slayer's Brew",cost=35,gives={SlayersBrew=1},text="+25 Strength, +20 Crit Damage for 10 minutes."},
	{id="BuySlayerSeals",kind="consumable",name="Bundle of Slayer Seals",cost=40,gives={SlayerToken=2},text="Two Slayer Seals for slayer gear."},
	{id="TitleGravewarden",kind="title",name="Title: Gravewarden",title="Gravewarden",cost=250,text="Wear the title Gravewarden."},
	{id="TitleNightstalker",kind="title",name="Title: Nightstalker",title="Nightstalker",cost=500,requires={Slayer=60},text="Wear the title Nightstalker."},
	{id="CraftHuntersVisor",kind="craft",name="Assemble Hunter's Visor",cost=0,unlock="VisorCrafting",requires={Slayer=40},gives={HuntersVisor=1},
		costs={SlayerToken=10,HushcapSpore=20,BeastHide=40},text="+15% damage and accuracy against task monsters."},
	{id="CraftRadiantVisor",kind="craft",name="Imbue Radiant Hunter's Visor",cost=0,unlock="VisorCrafting",requires={Slayer=75},gives={RadiantHuntersVisor=1},
		costs={HuntersVisor=1,EclipsedIchor=12,ThunderhidePlate=10,SlayerToken=30},text="+22% damage and accuracy against task monsters."},
}
ST.ShopById = {}
for i, e in ipairs(ST.Shop) do
	e.index = i
	ST.ShopById[e.id] = e
	if e.kind == "extend" then assert(ST.FamilyById[e.family], e.id.." extends an unknown family") end
end
-- Shop verdict: ok, reason. st = {points, unlocks = {[id] = true}, levels = {[skill] = lvl}, items = {[id] = n}}.
function ST.canBuy(entryId, st)
	local e = type(entryId) == "string" and ST.ShopById[entryId]
	if not e then return false, "Choose something from the Slayer shop." end
	local unlocks = type(st.unlocks) == "table" and st.unlocks or {}
	if (e.kind == "unlock" or e.kind == "extend" or e.kind == "title") and unlocks[e.id] then return false, e.name.." is already yours." end
	if e.unlock and not unlocks[e.unlock] then return false, e.name.." needs "..ST.ShopById[e.unlock].name.." first." end
	for skill, lvl in pairs(e.requires or {}) do
		if (tonumber(type(st.levels) == "table" and st.levels[skill]) or 1) < lvl then return false, e.name.." requires "..skill.." "..lvl.."." end
	end
	if (tonumber(st.points) or 0) < e.cost then return false, e.name.." costs "..e.cost.." Slayer points." end
	for id, n in pairs(e.costs or {}) do
		if (tonumber(type(st.items) == "table" and st.items[id]) or 0) < n then
			return false, e.name.." needs "..n.." "..(Data.Items[id] and Data.Items[id].name or id).."."
		end
	end
	return true
end
function ST.blockSlots(unlocks)
	return ST.BLOCK_SLOTS + (if type(unlocks) == "table" and unlocks.WiderLedger then 2 else 0)
end

-- Pure rules -------------------------------------------------------------------
-- ctx = {combat = Combat level, slayer = Slayer level, levels = {[skill] = level},
--        regions = {[regionId] = true when the player may enter}}.
function ST.familyReachable(familyId, ctx)
	local f = ST.FamilyById[familyId]
	if not f then return false, "unknown" end
	ctx = type(ctx) == "table" and ctx or {}
	local slayer = tonumber(ctx.slayer) or 1
	if slayer < f.slayer then return false, "Requires Slayer "..f.slayer end
	local regions = type(ctx.regions) == "table" and ctx.regions or {}
	if f.sea then
		local fishing = tonumber(type(ctx.levels) == "table" and ctx.levels.Fishing) or 1
		for _, id in ipairs(f.monsters) do
			local sc = Data.SeaCreatures[id]
			if fishing >= sc.fishing then
				if sc.waters == nil then return true end
				for _, w in ipairs(sc.waters) do if regions[w] then return true end end
			end
		end
		local need = math.huge
		for _, id in ipairs(f.monsters) do need = math.min(need, Data.SeaCreatures[id].fishing) end
		return false, if fishing < need then "Requires Fishing "..need else "No reachable water"
	end
	for _, id in ipairs(f.monsters) do
		if regions[Data.Monsters[id].region] then return true end
	end
	local names = {}
	for _, id in ipairs(f.monsters) do
		local r = Data.RegionById[Data.Monsters[id].region]
		local name = r and r.name or Data.Monsters[id].region
		if not table.find(names, name) then table.insert(names, name) end
	end
	return false, "Needs access to "..table.concat(names, " or ")
end
function ST.masterAvailable(masterId, ctx)
	local m = ST.MasterById[masterId]
	if not m then return false, "unknown" end
	ctx = type(ctx) == "table" and ctx or {}
	if (tonumber(ctx.combat) or 1) < m.combat then return false, "Requires Combat "..m.combat end
	if (tonumber(ctx.slayer) or 1) < m.slayer then return false, "Requires Slayer "..m.slayer end
	return true
end
-- Weighted candidates a master may assign: {{entry, weight}...} and their total.
-- blocked = {familyId...}; avoid = a family to skip when anything else is left.
function ST.candidates(masterId, ctx, blocked, avoid)
	local m = ST.MasterById[masterId]
	local out, total = {}, 0
	if not m then return out, 0 end
	local isBlocked = {}
	for _, id in ipairs(type(blocked) == "table" and blocked or {}) do isBlocked[id] = true end
	for _, entry in ipairs(m.tasks) do
		if not isBlocked[entry.family] and ST.familyReachable(entry.family, ctx) then
			table.insert(out, {entry=entry,weight=entry.weight})
			total += entry.weight
		end
	end
	if avoid and #out > 1 then
		for i, c in ipairs(out) do
			if c.entry.family == avoid then table.remove(out, i); total -= c.weight; break end
		end
	end
	return out, total
end
-- May familyId be added to the block list? Refused when it would leave any
-- master available under ctx with fewer than ST.MIN_CANDIDATES assignable
-- families (and fewer than now), so blocks cannot narrow a master's pool to a
-- single, trivially farmed family. Returns ok, reason.
function ST.blockAllowed(familyId, ctx, blocked)
	if not ST.FamilyById[familyId] then return false, "Choose a monster family to block" end
	local list = {}
	for _, id in ipairs(type(blocked) == "table" and blocked or {}) do table.insert(list, id) end
	local after = table.clone(list)
	table.insert(after, familyId)
	for _, m in ipairs(ST.Masters) do
		if ST.masterAvailable(m.id, ctx) then
			local now, later = #(ST.candidates(m.id, ctx, list)), #(ST.candidates(m.id, ctx, after))
			if later < now and later < ST.MIN_CANDIDATES then
				return false, m.name.." would have fewer than "..ST.MIN_CANDIDATES.." families to assign"
			end
		end
	end
	return true
end
-- Amount range for an entry, extended when the family's extension is unlocked.
function ST.amountRange(entry, unlocks)
	local extended = type(unlocks) == "table" and unlocks["Extend"..entry.family] == true and ST.ShopById["Extend"..entry.family] ~= nil
	if not extended then return entry.min, entry.max, false end
	return math.floor(entry.min * ST.EXTEND_MULT), math.floor(entry.max * ST.EXTEND_MULT), true
end
-- A new task {master, family, amount, killed = 0, extended} or nil, reason.
-- rollA picks the family by weight, rollB the amount (both in [0, 1)).
function ST.assign(masterId, ctx, blocked, unlocks, rollA, rollB, avoid)
	local ok, reason = ST.masterAvailable(masterId, ctx)
	if not ok then return nil, reason end
	local list, total = ST.candidates(masterId, ctx, blocked, avoid)
	if #list == 0 or total <= 0 then return nil, "No task you can reach right now" end
	local pick = math.clamp(tonumber(rollA) or 0, 0, 0.999999) * total
	local chosen = list[#list].entry
	for _, c in ipairs(list) do
		pick -= c.weight
		if pick < 0 then chosen = c.entry break end
	end
	local lo, hi, extended = ST.amountRange(chosen, unlocks)
	local amount = lo + math.floor(math.clamp(tonumber(rollB) or 0, 0, 0.999999) * (hi - lo + 1))
	return {master=masterId,family=chosen.family,amount=amount,killed=0,extended=extended}
end
-- Streak multiplier for the nth completed task of a streak (n >= 1).
function ST.streakMult(n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return 1 end
	for _, s in ipairs(ST.Streak) do if n % s.every == 0 then return s.mult end end
	return 1
end
function ST.pointsFor(masterId, streak)
	local m = ST.MasterById[masterId]
	return if m then m.points * ST.streakMult(streak) else 0
end
function ST.bountyFor(masterId, unlocks)
	local m = ST.MasterById[masterId]
	if not m then return 0 end
	return m.bounty * (if type(unlocks) == "table" and unlocks.GildedBounty then 2 else 1)
end
-- Task credit for one credited killer (normal kill credit is unchanged): it
-- dealt at least ST.TASK_SHARE of max health, or is the (joint) top damager.
-- damage = this killer's damage, top = the most any contributor dealt.
function ST.taskEligible(damage, maxHp, top)
	damage, maxHp, top = tonumber(damage) or 0, tonumber(maxHp) or 0, tonumber(top) or 0
	if damage <= 0 then return false end
	return damage >= top or (maxHp > 0 and damage >= maxHp * ST.TASK_SHARE)
end
-- Slayer XP for one task kill of a monster (or superior) definition.
function ST.killXp(def)
	local hp = type(def) == "table" and tonumber(def.hp) or 0
	if hp <= 0 then return 0 end
	return math.max(1, math.floor(hp / ST.HP_PER_XP + 0.5))
end
-- Slayer skill XP for defeating a boss-line boss.
function ST.bossXp(line, tier)
	local def = Data.Slayers[line]
	local t = def and def.tiers[tonumber(tier) or 0]
	if not t then return 0 end
	return math.floor(t.hp / ST.HP_PER_XP * ST.BOSS_XP_SHARE)
end
-- Visor bonus {damage, accuracy} (percent) of an equipped helmet id, or nil.
function ST.visorBonus(helmetId)
	local def = type(helmetId) == "string" and Data.Items[helmetId]
	local b = type(def) == "table" and def.slayerBonus
	if type(b) ~= "table" then return nil end
	return {damage=b.damage or 0,accuracy=b.accuracy or 0}
end
-- Human text for a task.
function ST.describe(task)
	if type(task) ~= "table" then return "No task" end
	local f = ST.FamilyById[task.family]
	return (f and f.name or tostring(task.family)).." "..tostring(task.killed or 0).." / "..tostring(task.amount or 0)
end

-- Townsfolk: three more masters (Ysolde stays the Hub's "Slayer"). ------------
local T = Data.Townsfolk
if T then
	T.Verbs.slayerTask = {item={}}
	for _, m in ipairs(ST.Masters) do T.Verbs.slayerTask.item[m.id] = true end
	local function taskTip(s)
		local st = type(s) == "table" and type(s.slayerTasks) == "table" and s.slayerTasks or nil
		if not st then return "Speak to a Slayer master for a task: they hand out a monster family and an amount." end
		local t = type(st.task) == "table" and st.task or nil
		if t then
			local f = ST.FamilyById[t.family]
			local where = {}
			for _, id in ipairs(f and f.monsters or {}) do
				local m = Data.Monsters[id]
				if m and not table.find(where, m.name) then table.insert(where, m.name) end
			end
			return "Your task: "..ST.describe(t)..". Hunt "..table.concat(where, ", ")..". Streak "..tostring(st.streak or 0)..", "..tostring(st.points or 0).." points."
		end
		return "No task right now. Ask a master for one; every 10th task in a row pays bonus points."
	end
	T.Tips.slayerTask = taskTip
	T.Conditions.taskIdle = function(s)
		local st = type(s) == "table" and type(s.slayerTasks) == "table" and s.slayerTasks or nil
		return st ~= nil and type(st.task) ~= "table"
	end
	local ysolde = T.NPCs.Slayer
	if ysolde then
		table.insert(ysolde.nodes.hello.options, 2, {label="Assign me a slayer task",verb="slayerTask",item="Ysolde",when="taskIdle"})
		table.insert(ysolde.nodes.hello.options, 3, {label="How is my slayer task going?",tip="slayerTask"})
	end
	local farewell = {label="Farewell", close=true}
	local function master(role, id, look, intro, hunt)
		local m = ST.MasterById[id]
		T.NPCs[role] = {name=m.name,title="Slayer Master",region=m.region,portrait="⚔",look=look,start="hello",nodes={
			hello={text=intro,options={
				{label="Assign me a slayer task",verb="slayerTask",item=id,when="taskIdle"},
				{label="How is my slayer task going?",tip="slayerTask"},
				{label="Show me the Slayer ledger",atlas="Slayer"},
				{label="Where should I hunt?",waypoint=hunt},
				farewell}}}}
		table.insert(T.Order, role)
	end
	master("SlayerCorvane","Corvane",{skin="C68642",shirt="3E5B3A",pants="2E2A26",shoes="2B1E14",accent="9BD77E",hair="4A3B2A",hat="hood",held="sword",cape="2F5233",beard=true},
		"The grove is quiet because someone keeps it so. Take a task and bring the count home.",{"monster:HollowcapShrieker","monster:GloomfangSpider","region:Gloomhollow"})
	master("SlayerMaelis","Maelis",{skin="F1C27D",shirt="2A2433",pants="1B1B22",shoes="141418",accent="C77DFF",hair="E0E0E0",hat="hood",held="lantern",cape="4B2C7A"},
		"The dark is patient. So am I. Your task, and mind your lantern.",{"monster:MirrorscaleBasilisk","monster:VoidWisp","region:Tidewater"})
	master("SlayerVesper","Vesper",{skin="8D5524",shirt="37474F",pants="263238",shoes="1C1C1C",accent="8FB8D6",hair="1B1B1B",hat="feather",held="staff",cape="4B6584"},
		"Only the storm's worst. If you flinch at thunder, come back later.",{"monster:ThundercragGargant","monster:TempestWraith","region:Tempest"})
end
end
-- End Slayer tasks section.

------------------------------------------------------------------------------
-- Minigames (Minigames team; self-contained section). Group minigames on the
-- Skybreach Bastion (minigames.server.lua builds the arena; a ferry beacon on
-- the Guild Terrace is gated through ServerStorage.IsleMinigameAccess):
--   * Skybreach Siege (wave defence): 3-10 players defend the Lumen Keeper
--     against creatures from four rift portals. Portal shields drop one at a
--     time (a random order each match; the next drops early when a portal
--     falls); destroy all four before the Keeper falls. Novice / Veteran /
--     Elite landings by Combat level scale creatures, portals and the Keeper.
--     Contribution points come from strikes on creatures and portals and from
--     barricade repairs (1 Timber, Carpentry XP); MIN_POINTS earns the tier's
--     Commendations on a win. Commendations buy the Lumenward outfit (shared
--     hauberk / greaves / treads and one helm per combat style; the 4-piece set
--     adds the worn helm's style stats via Data.Sets.Lumenward.style inside
--     Progression.computeStats), XP lamps for the
--     combat skills and cosmetic titles.
--   * Tempest Haul (skilling boss): 1-10 players catch and cook stormfish,
--     load them into the deck cannons, repair cracked masts (Carpentry) and
--     douse lightning fires while the Squall Leviathan's energy drains; at zero
--     energy it surfaces and harpoons drain its essence. Fishing, Cooking and
--     Carpentry XP per action; points past MIN_POINTS buy Squall Cache rolls
--     (solo hauls pay SOLO_REWARD of the points). The cache holds the
--     Squallpup pet, the Stormcaller fishing outfit and the Tidebreaker Rod.
-- Balance (verify-minigames.luau): XP/h and currency/h of each game against
-- its solo equivalent sit within 0.8-1.2x (SOCIAL_BONUS included), shop
-- prices are checked in hours, and an idle player earns nothing.
------------------------------------------------------------------------------
do
local MG = {}
Data.Minigames = MG
MG.ISLAND = "Skybreach Bastion"
MG.Order = {"Siege","Haul"}
MG.REJOIN_SECONDS = 90   -- a player who drops mid-match may rejoin with their points
MG.REJOIN_GRACE = 15     -- a rejoiner keeps their idle clock; this long to act or move again
MG.IDLE_SECONDS = 60     -- no credited action and no movement: removed (AFK)
MG.AWAY_RADIUS = 120     -- this far from the arena centre for AWAY_GRACE seconds: removed
MG.AWAY_GRACE = 10
MG.ACTION_COOLDOWN = 1.1 -- seconds between credited actions (strike, repair, catch...)
MG.SOCIAL_BONUS = 1.1    -- group content may pay a little more than its solo twin
MG.LOG_LIMIT = 1e9
MG.MAX_POINTS_PER_SECOND = 12 -- server sanity cap on credited points per match second

local function round(x) return math.floor(x + 0.5) end
MG.round = round
-- Party scale: health pools grow with the party (3 players = x1).
function MG.partyScale(n)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, 10)
	return 0.55 + 0.15 * n
end

------------------------------------------------------------------------------
-- Solo references (the "equivalent solo activity" each game is balanced on).
------------------------------------------------------------------------------
MG.SOLO = {killsPerHour = 300, gatherOverhead = 1.5, cookSeconds = 1.5}
function MG.bestFish(level)
	local best = Data.ResourceTiers.Fishing[1]
	for _, r in ipairs(Data.ResourceTiers.Fishing) do if r.level <= (tonumber(level) or 1) then best = r end end
	return best
end
-- Solo combat: level-appropriate kills of the best ordinary monster at or below the level.
function MG.bestMonster(level)
	local bestId, bestXp = nil, -1
	for id, m in pairs(Data.Monsters) do
		if type(m) == "table" and not m.worldBoss and not m.superior and not m.seaCreature and (m.level or 999) <= math.max(2, level)
			and ((m.xp or 0) > bestXp or ((m.xp or 0) == bestXp and id < bestId)) then
			bestId, bestXp = id, m.xp or 0
		end
	end
	return bestId and Data.Monsters[bestId] or nil
end
function MG.soloCombatXpPerHour(level)
	local m = MG.bestMonster(level)
	return if m then MG.SOLO.killsPerHour * m.xp else 0
end
-- Solo fishing, then cooking the catch at a Hearth.
function MG.soloFishCookXpPerHour(level)
	local f = MG.bestFish(level)
	return 3600 * (f.xp + f.xp + 8) / (f.respawn + MG.SOLO.gatherOverhead + MG.SOLO.cookSeconds)
end
function MG.soloFishCoinsPerHour(level)
	local f = MG.bestFish(level)
	return 3600 * f.value / (f.respawn + MG.SOLO.gatherOverhead)
end

------------------------------------------------------------------------------
-- Skybreach Siege.
------------------------------------------------------------------------------
local S = {id="Siege", name="Skybreach Siege", keeper="Lumen Keeper", color="7FE3CC",
	MIN_PLAYERS=3, MAX_PLAYERS=10, PAD_SECONDS=25, PAD_RADIUS=9,
	TIME_LIMIT=720, FIRST_DROP=30, DROP_INTERVAL=40, WAVE_INTERVAL=14, CREATURE_CAP=24,
	KEEPER_HP=2400, PORTAL_HP=900, BARRICADE_HP=400, REPAIR_HP=120, REPAIR_TIMBER=1,
	MIN_POINTS=50, LANE=60, BARRICADE_AT=0.45, HIT_RANGE=4, FLYER_RANGE=14,
	Points={strike=1, kill=2, portal=2, repair=5},
	-- Contribution gate (S.requiredPoints): at least MIN_POINTS, MIN_POINTS_PER_MINUTE
	-- per minute in the match and MEDIAN_SHARE of the median member's points, plus a
	-- credited action in the last RECENT_SECONDS when the match settles.
	MIN_POINTS_PER_MINUTE=6, MEDIAN_SHARE=0.25, RECENT_SECONDS=45,
	-- Barricade repairs: only when at least the repair amount is missing; per member
	-- per match, repairs pay XP at most REPAIR_XP_LIMIT times and points up to
	-- REPAIR_POINT_CAP (below MIN_POINTS: repairs alone never qualify).
	REPAIR_XP_LIMIT=12, REPAIR_POINT_CAP=25,
	-- Balance model: one match plus its lobby, and how often a public party wins.
	Model={gameSeconds={Novice=300,Veteran=360,Elite=420}, lobbySeconds=45, winRate=0.85},
	rules="Defend the Lumen Keeper while the four rift shields drop one by one. Strike creatures and open portals, repair barricades with Timber. Destroy every portal before the Keeper falls. Earn at least 50 points (more in long matches) and keep fighting to the end to be paid.",
}
MG.Siege = S
S.Tiers = {
	{id="Novice",name="Novice Landing",combat=20,hpMult=1,damageMult=1,commendations=4,color="7FE3CC"},
	{id="Veteran",name="Veteran Landing",combat=50,hpMult=2.6,damageMult=2.2,commendations=5,color="F3C66E"},
	{id="Elite",name="Elite Landing",combat=75,hpMult=5,damageMult=3.6,commendations=6,color="EF7D67"},
}
S.TierById = {}
for i, t in ipairs(S.Tiers) do t.index = i; S.TierById[t.id] = t end
S.Portals = {
	{id="Cinder",name="Cinder Rift",color="E8743B",angle=0},
	{id="Gale",name="Gale Rift",color="9BD1E8",angle=90},
	{id="Rime",name="Rime Rift",color="BFE3FF",angle=180},
	{id="Gloam",name="Gloam Rift",color="8E6BD8",angle=270},
}
S.PortalById = {}
for i, p in ipairs(S.Portals) do p.index = i; S.PortalById[p.id] = p end
-- Rift creatures (minigame-only: never in Data.Monsters, never drop loot).
-- "lane": walks its lane, stops at an intact barricade, then the Keeper;
-- "flyer": crosses barricades and strikes players near its path.
S.Creatures = {
	{id="Riftling",name="Riftling",hp=60,damage=6,speed=9,weight=5,target="lane",color="E8A33B"},
	{id="Shardback",name="Shardback Brute",hp=200,damage=16,speed=5,weight=2,target="lane",breaker=2,color="8C7A6B"},
	{id="Hexwing",name="Hexwing",hp=80,damage=10,speed=8,weight=2,target="flyer",color="8E6BD8"},
	{id="Voidleech",name="Voidleech",hp=70,damage=5,speed=8,weight=1,target="lane",keeperMult=3,color="3D3D5C"},
}
S.CreatureById = {}
for i, c in ipairs(S.Creatures) do c.index = i; S.CreatureById[c.id] = c end
function S.tierFor(combatLevel)
	local best = nil
	for _, t in ipairs(S.Tiers) do if (tonumber(combatLevel) or 0) >= t.combat then best = t end end
	return best
end
function S.canEnter(tierId, combatLevel)
	local t = S.TierById[tierId]
	if not t then return false, "Choose a landing." end
	if (tonumber(combatLevel) or 0) < t.combat then return false, t.name.." needs Combat "..t.combat.."." end
	return true
end
-- Health pools for a match (tier x party).
function S.scaled(tierId, n)
	local t = S.TierById[tierId] or S.Tiers[1]
	local k = MG.partyScale(n)
	return {keeper=round(S.KEEPER_HP * t.hpMult * k), portal=round(S.PORTAL_HP * t.hpMult * k),
		barricade=round(S.BARRICADE_HP * t.hpMult), repair=round(S.REPAIR_HP * t.hpMult), hpMult=t.hpMult, damageMult=t.damageMult, party=k}
end
-- Solo Carpentry XP per Timber: the best XP per material unit of any Carpentry
-- build that uses Timber (workbench recipes, island decor, home furniture) at
-- or below the level. Carpentry is a costly skill; repairs never beat it.
function MG.soloCarpentryXpPerTimber(level)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, 99)
	local best = 0
	local function scan(list, carpentryOnly)
		for _, r in pairs(list or {}) do
			if type(r) == "table" and type(r.costs) == "table" and r.costs.Timber and (r.level or 1) <= level and (r.xp or 0) > 0
				and (not carpentryOnly or r.skill == "Carpentry") then
				local units = 0
				for _, n in pairs(r.costs) do units += n end
				if units > 0 then best = math.max(best, r.xp / units) end
			end
		end
	end
	scan(Data.Recipes, true)
	scan(Data.Island and Data.Island.Props, false)
	scan(Data.Furniture, false)
	return best
end
-- Carpentry XP for one barricade repair: the Timber it costs at the solo rate.
function S.repairXp(level)
	return math.max(1, round(S.REPAIR_TIMBER * MG.soloCarpentryXpPerTimber(level) * MG.SOCIAL_BONUS))
end
-- Repairs need at least one full repair's worth of missing health.
function S.canRepair(hp, max, amount) return (tonumber(max) or 0) - (tonumber(hp) or 0) >= (tonumber(amount) or math.huge) end
function S.creatureHp(id, tierId) local c = S.CreatureById[id]; local t = S.TierById[tierId] or S.Tiers[1]; return round(c.hp * t.hpMult) end
function S.creatureDamage(id, tierId) local c = S.CreatureById[id]; local t = S.TierById[tierId] or S.Tiers[1]; return round(c.damage * t.damageMult) end
-- Strike damage from Combat level (Lumenward adds 15% inside the bastion).
function S.strikeDamage(combatLevel, tierId, lumenward)
	local t = S.TierById[tierId] or S.Tiers[1]
	local base = 18 + 2 * math.clamp(tonumber(combatLevel) or 1, 1, 99)
	return round(base * (0.6 + 0.4 * t.hpMult) * (if lumenward then 1.15 else 1))
end
-- Creatures per wave (per living portal).
function S.waveSize(tierId, n)
	local t = S.TierById[tierId] or S.Tiers[1]
	return math.clamp(1 + math.floor(((tonumber(n) or 1) - 1) / 4) + (t.index - 1), 1, 4)
end
-- Shield order: a permutation of the four portals from a [0,1) roll source.
function S.shieldOrder(rng)
	local ids = {}
	for _, p in ipairs(S.Portals) do table.insert(ids, p.id) end
	for i = #ids, 2, -1 do
		local j = math.clamp(math.floor((rng() or 0) * i) + 1, 1, i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	return ids
end
-- Weighted creature pick from a [0,1) roll.
function S.pickCreature(roll)
	local total = 0
	for _, c in ipairs(S.Creatures) do total += c.weight end
	local x = math.clamp(tonumber(roll) or 0, 0, 0.999999) * total
	for _, c in ipairs(S.Creatures) do
		x -= c.weight
		if x < 0 then return c.id end
	end
	return S.Creatures[1].id
end
-- Points a member needs for a reward: MIN_POINTS, MIN_POINTS_PER_MINUTE of
-- their time in the match, and MEDIAN_SHARE of the median member's points.
function S.requiredPoints(seconds, median)
	local s = math.max(0, tonumber(seconds) or 0)
	local m = math.max(0, tonumber(median) or 0)
	return math.max(S.MIN_POINTS, math.floor(S.MIN_POINTS_PER_MINUTE * s / 60), math.floor(S.MEDIAN_SHARE * m))
end
function MG.median(list)
	local t = {}
	for _, v in ipairs(list or {}) do if type(v) == "number" and v == v then table.insert(t, v) end end
	if #t == 0 then return 0 end
	table.sort(t)
	local mid = (#t + 1) / 2
	return (t[math.floor(mid)] + t[math.ceil(mid)]) / 2
end
-- Reward for one player: Commendations only on a win with the required points
-- (MIN_POINTS when required is omitted).
function S.reward(tierId, points, won, required)
	local t = S.TierById[tierId]
	if not t or not won or (tonumber(points) or 0) < math.max(S.MIN_POINTS, tonumber(required) or 0) then return 0 end
	return t.commendations
end
function S.commendationsPerHour(tierId)
	local t = S.TierById[tierId]
	return 3600 / (S.Model.gameSeconds[tierId] + S.Model.lobbySeconds) * S.Model.winRate * t.commendations
end

------------------------------------------------------------------------------
-- Tempest Haul.
------------------------------------------------------------------------------
local H = {id="Haul", name="Tempest Haul", boss="Squall Leviathan", color="5EC8D8",
	MIN_PLAYERS=1, MAX_PLAYERS=10, PAD_SECONDS=20, PAD_RADIUS=9, SOLO_REWARD=0.75,
	FISHING_LEVEL=20, TIME_LIMIT=900,
	ENERGY=100, ESSENCE=100, RAW_HIT=2.5, COOKED_HIT=5, HARPOON_HIT=8, VULNERABLE_SECONDS=30, RECHARGE=35,
	MASTS=2, CANNONS=2, HULL=100, CARRY=6,
	SURGE_INTERVAL=35, FIRE_INTERVAL=18, FIRE_CAP=5, FIRE_BURN=0.6, -- hull lost per burning fire per second
	MIN_POINTS=150, ROLL_POINTS=400, MAX_ROLLS=12, ROLL_SECONDS=78,
	Points={catch=10, cook=10, loadRaw=10, loadCooked=20, repair=25, douse=15, harpoon=20},
	XP_RATIO=1.1,
	-- Balance model: seconds per action, the share of a match spent on the fish
	-- loop / chores / harpooning, the match length and its lobby.
	Model={catch=3, cook=2, load=2, repair=3, douse=2, loop=0.68, chores=0.17, essence=0.07, gameSeconds=420, lobbySeconds=40, winRate=0.95},
	rules="Catch stormfish, cook them at the brazier and load the cannons. Repair cracked masts and douse lightning fires. When the Squall Leviathan's energy runs out, harpoon it. Earn 150 points for a Squall Cache roll; solo hauls pay 75%.",
}
MG.Haul = H
-- XP per action: each second spent on an action earns XP_RATIO x the solo
-- fish-and-cook XP rate at the player's level, in the action's skill.
-- The server pays an action for the time the player actually spent on it:
-- seconds since their previous credited action, capped at the action's model
-- seconds (H.actionXp(action, levels, seconds)), so XP/h never beats XP_RATIO x
-- solo however fast the cadence. Without seconds: the full modelled action.
H.ActionSkill = {catch="Fishing", cook="Cooking", load="Fishing", repair="Carpentry", douse="Fishing", harpoon="Fishing"}
function H.actionSeconds(action) return H.Model[if action == "harpoon" then "load" else action] end
-- XP per second of play in a skill at a level (XP_RATIO x the solo fish+cook rate).
function H.xpPerSecond(level)
	return H.XP_RATIO * MG.soloFishCookXpPerHour(math.clamp(tonumber(level) or 1, 1, 99)) / 3600
end
function H.actionXp(action, levels, seconds)
	levels = type(levels) == "table" and levels or {}
	local skill = H.ActionSkill[action]
	if not skill then return {} end
	local level = math.clamp(tonumber(levels[skill]) or tonumber(levels.Fishing) or 1, 1, 99)
	local model = H.actionSeconds(action)
	if seconds ~= nil then
		return {[skill] = H.xpPerSecond(level) * math.clamp(tonumber(seconds) or 0, 0, model)}
	end
	return {[skill] = math.max(1, round(H.xpPerSecond(level) * model))}
end
function H.energyHit(cooked, n)
	return (if cooked then H.COOKED_HIT else H.RAW_HIT) / MG.partyScale(n)
end
function H.essenceHit(n) return H.HARPOON_HIT / MG.partyScale(n) end
-- Reward rolls from points (solo pays SOLO_REWARD of the points). With
-- seconds, rolls are also capped by match time (H.maxRolls): a haul never pays
-- more than the modelled game's rolls, scaled down for a shorter game, so
-- stalling the Leviathan to farm points is not profitable.
function H.rolls(points, won, partySize, seconds)
	points = tonumber(points) or 0
	if not won or points < H.MIN_POINTS then return 0 end
	local solo = (tonumber(partySize) or 1) <= 1
	local effective = points * (if solo then H.SOLO_REWARD else 1)
	local cap = H.MAX_ROLLS
	if seconds ~= nil then cap = math.min(cap, H.maxRolls(seconds, solo)) end
	return math.clamp(math.floor(effective / H.ROLL_POINTS), 1, math.max(1, cap))
end
-- Modelled points/h and XP/h (all three skills) for a typical player.
function H.modelPointsPerHour()
	local m, P = H.Model, H.Points
	local loop = 3600 * m.loop / (m.catch + m.cook + m.load) * (P.catch + P.cook + P.loadCooked)
	local chores = 3600 * m.chores / ((m.repair + m.douse) / 2) * ((P.repair + P.douse) / 2)
	local essence = 3600 * m.essence / 2 * P.harpoon
	return loop + chores + essence
end
function H.modelXpPerHour(level)
	local m = H.Model
	local levels = {Fishing = level, Cooking = level, Carpentry = level}
	local function total(action) local s = 0; for _, v in pairs(H.actionXp(action, levels)) do s += v end; return s end
	local loop = 3600 * m.loop / (m.catch + m.cook + m.load) * (total("catch") + total("cook") + total("load"))
	local chores = 3600 * m.chores / ((m.repair + m.douse) / 2) * ((total("repair") + total("douse")) / 2)
	local essence = 3600 * m.essence / 2 * total("harpoon")
	return loop + chores + essence
end
-- Rolls of one modelled game (crew points, no time cap).
function H.modelRollsPerGame()
	return math.floor(H.modelPointsPerHour() * H.Model.gameSeconds / 3600 / H.ROLL_POINTS)
end
-- Time cap: the modelled game's rolls x min(1, seconds / gameSeconds) (solo x SOLO_REWARD).
function H.maxRolls(seconds, solo)
	local share = math.clamp((tonumber(seconds) or 0) / H.Model.gameSeconds, 0, 1)
	local cap = H.modelRollsPerGame() * share * (if solo then H.SOLO_REWARD else 1)
	return math.clamp(math.floor(cap + 0.5), 1, H.MAX_ROLLS)
end
function H.rollsPerHour(solo)
	local m = H.Model
	local points = H.modelPointsPerHour() * m.gameSeconds / 3600
	local perGame = H.rolls(points, true, if solo then 1 else 4, m.gameSeconds)
	return perGame * m.winRate * 3600 / (m.gameSeconds + m.lobbySeconds)
end

------------------------------------------------------------------------------
-- Squall Cache (the Haul reward pool). Each roll: coins plus one weighted
-- entry (fish are the best the roller can catch); uniques roll separately.
------------------------------------------------------------------------------
H.Cache = {
	coins = {0.5, 1.0},              -- coins = roll value x [min, max]
	fish = {weight=50, share=0.35},  -- a fish stack worth about share of the roll value
	entries = {
		{item="Timber",weight=10,min=4,max=10},
		{item="WindpineLog",weight=8,min=2,max=6,level=15},
		{item="ArcaneDust",weight=12,min=2,max=6},
		{item="StormFeather",weight=8,min=1,max=3,level=30},
		{item="Lanternray",weight=6,min=2,max=4,level=45},
		{item="SquallPearl",weight=6,min=1,max=1},
	},
	uniques = {
		{item="SquallpupPet",chance=1/400},
		{item="TidebreakerRod",chance=1/250},
		{item="StormcallerHood",chance=1/150},{item="StormcallerSlicker",chance=1/150},
		{item="StormcallerWaders",chance=1/150},{item="StormcallerBoots",chance=1/150},
	},
}
-- One roll is worth ROLL_SECONDS of solo fishing income at the roller's level.
function H.rollValue(fishingLevel) return H.ROLL_SECONDS * MG.soloFishCoinsPerHour(fishingLevel) / 3600 end
item("SquallPearl",{name="Squall Pearl",kind="material",rarity="Rare",color="BFE9F2",value=120,description="A storm-polished pearl from a Squall Cache. Merchants pay well for it."})
item("TidebreakerRod",{name="Tidebreaker Rod",kind="tool",toolKind="Rod",slot="rod",toolTier=5,tier=5,rarity="Epic",color="2F8FA8",stats={fishingFortune=60,seaCreatureChance=4},requires={Fishing=50},value=4000,
	description="Tier 5 fishing rod. Requires Fishing 50. Only a Squall Cache holds one."})
Data.Sets.Stormcaller = {id="Stormcaller",name="Stormcaller",pieces={},bonus={fishingFortune=30,seaCreatureChance=3},text="+30 Fishing Fortune, +3 Sea Creature Chance",color="3F9FB5"}
for _, s in ipairs({{"StormcallerHood","helmet","Stormcaller Hood",{fishingFortune=8}},{"StormcallerSlicker","chest","Stormcaller Slicker",{fishingFortune=12,health=20}},
	{"StormcallerWaders","legs","Stormcaller Waders",{fishingFortune=10,health=10}},{"StormcallerBoots","boots","Stormcaller Boots",{fishingFortune=6,speed=3}}}) do
	item(s[1],{name=s[3],kind="armor",slot=s[2],set="Stormcaller",tier=4,rarity="Epic",color="3F9FB5",stats=s[4],value=1500,
		description="Fishing outfit (Tempest Haul). Four pieces: "..Data.Sets.Stormcaller.text.."."})
	table.insert(Data.Sets.Stormcaller.pieces, s[1])
end
-- The Squallpup: a Fishing pet species with its own abilities and look.
do
	local pup = {id="Squallpup",name="Squallpup",skill="Fishing",rarity="Epic",color="5EC8D8",perLevel={fishingFortune=0.5,seaCreatureChance=0.04,health=0.4}}
	table.insert(Data.Pets, pup)
	Data.PetById.Squallpup = pup
	local PD = Data.PetDepth
	local list = {
		{name="Squall Sense",kind="xp",skills={"Fishing"},per=0.1,rarity="Common"},
		{name="Briny Luck",kind="stat",stat="fishingFortune",per=0.3,rarity="Rare"},
		{name="Stormcall",kind="stat",stat="seaCreatureChance",per=0.04,rarity="Legendary",level=40},
	}
	for i, a in ipairs(list) do a.index = i; a.id = a.name:gsub("[^%w]", "") end
	PD.Abilities.Squallpup = list
	PD.Looks.Squallpup = {form="hopper",accent="E0F7FF"}
	pup.ability = list[1].name..": up to "..PD.abilityText(list[1], PD.abilityValue(list[1], Data.PET_MAX_LEVEL, PD.MAX_RARITY))
	pup.abilityNames = {list[1].name, list[2].name, list[3].name}
	item("SquallpupPet",{name="Squallpup Pet",kind="pet",pet="Squallpup",rarity="Epic",color="5EC8D8",value=200*Data.Rarity.Epic.rank^2,
		description="Summon from your pet menu. Abilities: "..table.concat(pup.abilityNames, ", ")..". Found in Squall Caches."})
	-- A Stormcoil Serpent sometimes carries a stray Squallpup (a second, very rare source).
	local serpent = Data.SeaCreatures.StormcoilSerpent
	if serpent and type(serpent.drops) == "table" then table.insert(serpent.drops, {item="SquallpupPet",chance=0.0005,min=1,max=1}) end
end
local function cachePool(fishingLevel)
	local f = MG.bestFish(fishingLevel)
	local c = H.Cache
	local n = math.max(1, round(c.fish.share * H.rollValue(fishingLevel) / f.value))
	local pool = {{item=f.id,weight=c.fish.weight,min=math.max(1, n - 1),max=n + 1}}
	for _, e in ipairs(c.entries) do if (e.level or 1) <= fishingLevel then table.insert(pool, e) end end
	local total = 0
	for _, e in ipairs(pool) do total += e.weight end
	return pool, total, f
end
H.cachePool = cachePool
-- Pure roll: rng() in [0,1). Returns {coins, items={[id]=n}}.
function H.rollCache(fishingLevel, rng)
	fishingLevel = math.clamp(tonumber(fishingLevel) or 1, 1, 99)
	local pool, total = cachePool(fishingLevel)
	local c = H.Cache
	local function between(a, b) return a + math.min(b - a, math.floor(rng() * (b - a + 1))) end
	local value = H.rollValue(fishingLevel)
	local out = {coins = between(math.floor(c.coins[1] * value), math.floor(c.coins[2] * value)), items = {}}
	local x = rng() * total
	for _, e in ipairs(pool) do
		x -= e.weight
		if x < 0 then out.items[e.item] = (out.items[e.item] or 0) + between(e.min, e.max); break end
	end
	for _, u in ipairs(c.uniques) do
		if rng() < u.chance then out.items[u.item] = (out.items[u.item] or 0) + 1 end
	end
	return out
end
-- Expected merchant value of one roll (uniques excluded: they are the bonus).
function H.expectedRoll(fishingLevel)
	fishingLevel = math.clamp(tonumber(fishingLevel) or 1, 1, 99)
	local pool, total = cachePool(fishingLevel)
	local c = H.Cache
	local v = H.rollValue(fishingLevel)
	local value = (math.floor(c.coins[1] * v) + math.floor(c.coins[2] * v)) / 2
	for _, e in ipairs(pool) do value += e.weight / total * (e.min + e.max) / 2 * Data.Items[e.item].value end
	return value
end

------------------------------------------------------------------------------
-- Commendation shop: the Lumenward outfit, combat XP lamps and cosmetics.
------------------------------------------------------------------------------
Data.Sets.Lumenward = {id="Lumenward",name="Lumenward",pieces={},helms={},bonus={defense=40,health=60},
	text="+40 Defense, +60 Health, plus the worn helm's style bonus",color="9FE6F2"}
MG.LumenwardStyle = {
	LumenwardWarhelm={style="melee",name="Melee",stats={strength=25,critDamage=20}},
	LumenwardSightcowl={style="ranged",name="Ranged",stats={rangedStrength=20,rangedAccuracy=30}},
	LumenwardStarhood={style="magic",name="Magic",stats={intelligence=80,abilityDamage=10}},
}
MG.Shop = {}
for _, a in ipairs({
	{"LumenwardWarhelm","helmet","Lumenward Warhelm",{defense=18,strength=6},200},
	{"LumenwardSightcowl","helmet","Lumenward Sightcowl",{defense=14,rangedAccuracy=8},200},
	{"LumenwardStarhood","helmet","Lumenward Starhood",{defense=12,intelligence=20},200},
	{"LumenwardHauberk","chest","Lumenward Hauberk",{defense=40,health=30},250},
	{"LumenwardGreaves","legs","Lumenward Greaves",{defense=30,health=20},250},
	{"LumenwardTreads","boots","Lumenward Treads",{defense=14,speed=3},150},
}) do
	local style = MG.LumenwardStyle[a[1]]
	-- minigameUnique: Commendation-shop pieces are Minigames Collection Log entries (credited by collect() on purchase).
	item(a[1],{name=a[3],kind="armor",slot=a[2],set="Lumenward",tier=5,rarity="Epic",color="9FE6F2",stats=a[4],requires={Combat=30},value=a[5]*10,minigameUnique=true,
		description="Lumenward outfit (Commendation shop). Requires Combat 30. Four pieces: "..Data.Sets.Lumenward.text..(if style then ". "..style.name.." helm." else ".")})
	-- Sets list four pieces: any of the three helms fills the helm slot (Data.Sets.Lumenward.helms).
	if style then table.insert(Data.Sets.Lumenward.helms, a[1]) end
	if not style or #Data.Sets.Lumenward.helms == 1 then table.insert(Data.Sets.Lumenward.pieces, a[1]) end
	table.insert(MG.Shop, {id=a[1],kind="armor",item=a[1],cost=a[5]})
end
MG.LAMP_COST = 30
MG.LAMP_HOURS = 0.82 -- one lamp = this many hours of level-appropriate solo combat XP
MG.LampSkills = {Combat=1, Ranged=1, Magic=1, Prayer=0.4, Slayer=0.5}
for _, skill in ipairs({"Combat","Ranged","Magic","Prayer","Slayer"}) do
	table.insert(MG.Shop, {id="Lamp"..skill,kind="lamp",skill=skill,cost=MG.LAMP_COST})
end
table.insert(MG.Shop, {id="TitleKeeperward",kind="cosmetic",title="Keeperward",cost=400})
table.insert(MG.Shop, {id="MantleLumen",kind="cosmetic",title="Lumen-Mantled",cost=600})
table.insert(MG.Shop, {id="TitleRiftsealer",kind="cosmetic",title="Riftsealer",cost=800})
MG.ShopById = {}
for i, e in ipairs(MG.Shop) do e.index = i; MG.ShopById[e.id] = e end
-- XP from one lamp at a skill level (level-appropriate solo combat time).
function MG.lampXp(skill, level)
	local f = MG.LampSkills[skill]
	if not f then return 0 end
	return round(f * MG.LAMP_HOURS * MG.soloCombatXpPerHour(math.clamp(tonumber(level) or 1, 1, 99)))
end
-- Lumenward: with all four pieces validly equipped (equipped = Progression.equipped:
-- owned, right slot, requirements met), the helm's style {style, name, stats}.
-- Progression.computeStats applies it through Data.Sets.Lumenward.style (the
-- set-style hook: after perk stats, before caps), so client and server agree.
function MG.lumenwardStyle(p, equipped)
	if type(p) ~= "table" or type(p.items) ~= "table" or type(equipped) ~= "function" then return nil end
	for _, slot in ipairs(Data.ArmorSlots) do
		local _, def = equipped(p, slot)
		if not def or def.set ~= "Lumenward" then return nil end
	end
	return MG.LumenwardStyle[(equipped(p, "helmet"))]
end
Data.Sets.Lumenward.style = MG.lumenwardStyle
-- Shop purchase check (pure): returns the entry or nil, reason.
function MG.canBuy(id, ledger, levels)
	local e = MG.ShopById[id]
	if not e then return nil, "Choose a Commendation reward." end
	ledger = type(ledger) == "table" and ledger or {}
	if e.kind == "cosmetic" and type(ledger.unlocks) == "table" and ledger.unlocks[id] then return nil, "You already own this." end
	if e.kind == "armor" then
		for skill, lvl in pairs(Data.Items[e.item].requires or {}) do
			if (tonumber((levels or {})[skill]) or 1) < lvl then return nil, Data.Items[e.item].name.." needs "..skill.." "..lvl.."." end
		end
	end
	if (tonumber(ledger.commendations) or 0) < e.cost then return nil, "Needs "..e.cost.." Commendations." end
	return e
end
-- Fresh / sanitised profile ledger p.minigames.
function MG.migrate(r)
	r = type(r) == "table" and r or {}
	local function n(v) v = tonumber(v); if not v or v ~= v or v < 0 then return 0 end return math.floor(math.min(v, MG.LOG_LIMIT)) end
	local out = {commendations=n(r.commendations), rolls=math.min(n(r.rolls), 500), unlocks={}, title="", log={}}
	if type(r.unlocks) == "table" then
		for id, v in pairs(r.unlocks) do local e = MG.ShopById[id]; if v == true and e and e.kind == "cosmetic" then out.unlocks[id] = true end end
	end
	if type(r.title) == "string" and out.unlocks[r.title] then out.title = r.title end
	for _, g in ipairs(MG.Order) do
		local l = type(r.log) == "table" and type(r.log[g]) == "table" and r.log[g] or {}
		out.log[g] = {played=n(l.played), won=n(l.won), points=n(l.points), best=n(l.best), paid=n(l.paid)}
	end
	return out
end
end
-- End Minigames section.
-- Commissions & Logs (Mining & Logs team; append-only section).
-- Data.CommissionsLogs (CL): pure data + pure rules shared by server.server.lua
-- (Logs block), world.server.lua (Commission Board / Museum section) and
-- ui.client.lua (Journal › Commissions, Collection Log, Museum).
--   Commissions: CL.SLOTS daily slots per UTC day (CL.dayOf), drawn
--     deterministically from CL.Tasks by CL.draw(day, salt, ctx) among tasks the
--     journal can reach (CL.eligible: skill levels + region access). Progress
--     counts harvests ("gather"), kills ("kill") or Hunter catches ("catch").
--     Claims pay skill XP, coins and Glimmerdust (CL.reward, milestone boosts).
--   Commission Milestones (CL.Milestones, 1/5/15/50/150 completions): permanent
--     perks (dust %, gem sense, stats via p.perkStats, Forgeheart discount, title).
--   Forgeheart (CL.Forge): Glimmerdust perk shop. Costs rise per level while each
--     level gives less (diminishing returns); the Paragon milestone cuts costs.
--     Hearthglow Fortune shares the progression fortune budget with Skill
--     Mastery (CL.FORTUNE_BUDGET, < 100 so Mastery + Forgeheart can never cross
--     more than one fortune step: the <= 2.5x single-click yield rule holds).
--     Steadfast Pick shortens Mining regrowth; its skip and Mastery's share the
--     passive regrowth cap. Gemseeker adds a rare gem roll on Mining harvests (a
--     separate item, never part of the ore yield).
--   Collection Log (CL.log()): generated lazily from data — every pet, trail /
--     slayer / minigame unique and every drop row with chance < CL.RARE_CHANCE
--     anywhere in Data — each item exactly once, in the first matching tab of
--     CL.LogTabOrder. Tab completion pays coins + a title; CL.logScore / logRank.
--   Museum (CL.museumCategory): donate one of each curated item. Donations are
--     CONSUMED (never lent back); milestones (CL.MuseumMilestones) give coins and
--     stat perks (p.perkStats.museum). No gathering stats: yield-neutral.
------------------------------------------------------------------------------
do
local CL = {}
Data.CommissionsLogs = CL
CL.SLOTS = 4
CL.DAY = 86400
CL.MAX_DUST = 1000000000
CL.MAX_TOTAL = 10000000
CL.RARE_CHANCE = 0.05
CL.FORTUNE_BUDGET = 99
CL.DUST = {name="Glimmerdust", color="B9A7FF", symbol="✧"}
function CL.dayOf(t) return math.floor((tonumber(t) or 0) / CL.DAY) end
function CL.resetIn(t) t = tonumber(t) or 0; return (CL.dayOf(t) + 1) * CL.DAY - math.floor(t) end

-- Task pool. kind: gather (harvests of a resource), kill (monster), catch (Hunter creature).
CL.Tasks = {}
CL.TaskById = {}
local function task(def)
	def.amount = def.amount or 10
	table.insert(CL.Tasks, def)
	CL.TaskById[def.id] = def
	return def
end
local function res(id)
	local skill = Data.ResourceSkill[id]
	for _, r in ipairs(Data.ResourceTiers[skill] or {}) do if r.id == id then return r, skill end end
	return nil, skill
end
-- Mining commissions: one per ore tier (region = where the seam is found).
local mineNames = {Ore="Copperstone Quota",Aetherite="Aetherite Survey",Brassite="Brassite Haul",SunsteelOre="Sunsteel Shift",
	Voidstone="Voidstone Delve",StarmetalOre="Starmetal Bounty",Prismite="Prismite Prospect",Celestium="Celestium Charter",Crownstone="Crownstone Dig"}
local mineRegion = {SunsteelOre="Skyreach",Voidstone="Gloomhollow",StarmetalOre="Tempest",Prismite="Gloomhollow",Celestium="Tempest",Crownstone="ShatteredCrown"}
for i, id in ipairs({"Ore","Aetherite","Brassite","SunsteelOre","Voidstone","StarmetalOre","Prismite","Celestium","Crownstone"}) do
	local r = res(id)
	if r then
		task({id="Mine"..id,name=mineNames[id],kind="gather",target=id,amount=math.max(8, 30 - i * 2),skill="Mining",
			xp=r.xp * 6,coins=20 + r.level * 4,dust=20 + i * 6,levels={Mining=r.level},region=mineRegion[id],group="Mining"})
	end
end
-- Second, larger mining quotas for the busiest seams.
task({id="MineOreBulk",name="Deep Copperstone Contract",kind="gather",target="Ore",amount=45,skill="Mining",xp=200,coins=60,dust=30,levels={Mining=5},group="Mining"})
task({id="MineBrassiteBulk",name="Brassite Freight",kind="gather",target="Brassite",amount=35,skill="Mining",xp=600,coins=140,dust=42,levels={Mining=20},group="Mining"})
task({id="MineVoidstoneBulk",name="Hollow Seam Quota",kind="gather",target="Voidstone",amount=25,skill="Mining",xp=1300,coins=300,dust=60,levels={Mining=50},region="Gloomhollow",group="Mining"})
-- Combat commissions (quarry and cavern monsters first, a few beyond).
local hunts = {
	{"ShaleCrawler","Crawler Cull",15,"Quarry"},{"CinderMite","Mite Sweep",15,"Quarry"},{"BrassGolem","Golem Breaking",8,"Skyreach"},
	{"StormHarrier","Harrier Watch",8,"Skyreach"},{"GloomfangSpider","Nest Clearing",10,"Gloomhollow"},{"VoidWisp","Wisp Snuffing",8,"Gloomhollow"},
	{"HollowcapShrieker","Shrieker Silence",6,"Gloomhollow"},{"BramblebackBoar","Boar Drive",15,"Meadow"},{"Thornling","Thornling Pruning",12,"Meadow"},
	{"BarkStalker","Stalker Patrol",10,"Windpine"},{"ReefLurker","Lurker Lookout",8,"Tidewater"},{"TempestWraith","Wraith Warding",6,"Tempest"},
}
for _, h in ipairs(hunts) do
	local m = rawget(Data.Monsters, h[1])
	if m then
		task({id="Slay"..h[1],name=h[2],kind="kill",target=h[1],amount=h[3],skill="Combat",xp=math.floor(m.xp * h[3] * 0.6),
			coins=math.floor(m.coins * h[3] * 0.5),dust=18 + math.floor(m.level / 3),levels={Combat=math.max(1, m.level - 6)},region=h[4],group="Combat"})
	end
end
-- Variety: woodcutting, fishing, farming and Hunter.
local variety = {
	{"Timber","Timber Tally",30,"Woodcutting"},{"WindpineLog","Windpine Order",22,"Woodcutting","Windpine"},{"EmberoakLog","Emberoak Order",18,"Woodcutting","Windpine"},
	{"GlimmerbarkLog","Glimmerbark Order",14,"Woodcutting","Tidewater"},{"Fish","Minnow Catch",30,"Fishing"},{"Glassfin","Glassfin Netting",22,"Fishing"},
	{"Stormeel","Stormeel Run",18,"Fishing","Tidewater"},{"Lanternray","Lanternray Lure",14,"Fishing","Tidewater"},{"Herb","Herb Picking",30,"Farming"},
	{"Sunwheat","Sunwheat Reaping",22,"Farming"},{"Glowcap","Glowcap Gathering",18,"Farming","Windpine"},{"Moonbloom","Moonbloom Harvest",14,"Farming","Gloomhollow"},
}
for _, v in ipairs(variety) do
	local r = res(v[1])
	if r then
		task({id="Gather"..v[1],name=v[2],kind="gather",target=v[1],amount=v[3],skill=v[4],xp=r.xp * 5,coins=15 + r.level * 3,dust=12 + math.floor(r.level / 4),
			levels={[v[4]]=r.level},region=v[5],group=v[4]})
	end
end
local HU = Data.Hunter
for _, c in ipairs({{"PuffcapHopper","Hopper Count",6},{"SunwingMoth","Moth Netting",6},{"PinecrestGrouse","Grouse Season",5},{"CinderFerret","Ferret Boxing",4}}) do
	local def = HU and HU.CreatureById and HU.CreatureById[c[1]]
	if def then
		task({id="Catch"..c[1],name=c[2],kind="catch",target=c[1],amount=c[3],skill="Hunter",xp=def.xp * c[3],coins=20 + def.level * 3,dust=14 + math.floor(def.level / 4),
			levels={Hunter=def.level},region=def.region,group="Hunter"})
	end
end
-- Region gates only matter for gated regions (others are open to everyone).
function CL.eligible(t, ctx)
	ctx = ctx or {}
	local levels = ctx.levels or {}
	for skill, lvl in pairs(t.levels or {}) do if (levels[skill] or 1) < lvl then return false end end
	if t.region then
		local r = Data.RegionById[t.region]
		if r and r.requires and next(r.requires) and not (ctx.regions and ctx.regions[t.region]) then return false end
	end
	return true
end
-- Deterministic Park-Miller stream: the same day + salt + context always draws
-- the same board, so a rejoin or another server never rerolls it.
local function stream(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483646 + 1
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end
CL.stream = stream
-- Returns CL.SLOTS distinct task ids (fewer only when the pool runs short). The
-- first slot is always a Mining commission (every journal can mine Copperstone).
function CL.draw(day, salt, ctx)
	local rng = stream((tonumber(day) or 0) * 7919 + (tonumber(salt) or 0) * 104729 + 13)
	local pool, mining = {}, {}
	for _, t in ipairs(CL.Tasks) do
		if CL.eligible(t, ctx) then
			table.insert(pool, t.id)
			if t.group == "Mining" then table.insert(mining, t.id) end
		end
	end
	local out, used = {}, {}
	if #mining > 0 then
		local id = mining[1 + math.floor(rng() * #mining)]
		table.insert(out, id); used[id] = true
	end
	local guard = 0
	while #out < CL.SLOTS and guard < 400 do
		guard += 1
		local left = 0
		for _, id in ipairs(pool) do if not used[id] then left += 1 end end
		if left == 0 then break end
		local id = pool[1 + math.floor(rng() * #pool)]
		if not used[id] then table.insert(out, id); used[id] = true end
	end
	return out
end

-- Commission Milestones (total commissions claimed).
CL.Milestones = {
	{at=1,id="FirstShift",name="First Shift",dustPct=10,text="+10% Glimmerdust from commissions."},
	{at=5,id="GemSense",name="Gem Sense",gemChance=0.25,text="Mining harvests may turn up a cut gem (0.25%)."},
	{at=15,id="DelversGrit",name="Delver's Grit",stats={health=20,defense=5},text="+20 Health, +5 Defense."},
	{at=50,id="DeepLedger",name="Deep Ledger",dustPct=25,coinPct=10,text="+25% Glimmerdust and +10% coins from commissions."},
	{at=150,id="ForgeheartParagon",name="Forgeheart Paragon",forgeDiscount=20,title="Forgeheart Paragon",stats={strength=3},
		text="Forgeheart perks cost 20% less; +3 Strength; the Forgeheart Paragon title."},
}
function CL.milestonePerks(total)
	total = tonumber(total) or 0
	local out = {dustPct=0,coinPct=0,gemChance=0,forgeDiscount=0,stats={},reached=0,title=nil}
	for i, m in ipairs(CL.Milestones) do
		if total >= m.at then
			out.reached = i
			out.dustPct += m.dustPct or 0
			out.coinPct += m.coinPct or 0
			out.gemChance += m.gemChance or 0
			out.forgeDiscount += m.forgeDiscount or 0
			for k, v in pairs(m.stats or {}) do out.stats[k] = (out.stats[k] or 0) + v end
			if m.title then out.title = m.title end
		end
	end
	return out
end
-- Claim reward for a task given the journal's total completions so far.
function CL.reward(t, total)
	local perks = CL.milestonePerks(total)
	return {skill=t.skill,xp=t.xp,coins=math.floor(t.coins * (1 + perks.coinPct / 100)),dust=math.floor(t.dust * (1 + perks.dustPct / 100))}
end

-- Forgeheart perk shop (Glimmerdust).
CL.ForgeOrder = {"SteadfastPick","HearthglowFortune","Gemseeker"}
CL.Forge = {
	SteadfastPick={name="Steadfast Pick",stat="miningSpeed",gains={8,7,6,5,5,4,4,3,3,3},skipPerLevel=2,base=40,color="FFAA00",
		text="Mining Speed, and Mining nodes regrow 2% faster per level (shares Mastery's regrowth cap)."},
	HearthglowFortune={name="Hearthglow Fortune",stat="miningFortune",gains={8,7,6,5,5,4,4,3,3,3},base=40,color="D4A84B",
		text="Mining Fortune. Shares the progression fortune budget with Skill Mastery (99 combined)."},
	Gemseeker={name="Gemseeker",stat="gemChance",gains={0.2,0.15,0.1,0.1,0.05},base=70,color="E86FB8",
		text="Chance for a cut gem on each Mining harvest."},
}
for id, f in pairs(CL.Forge) do f.id = id; f.max = #f.gains end
-- Glimmerdust for the next level (level = current level, 0-based) with a % discount.
function CL.forgeCost(id, level, discount)
	local f = CL.Forge[id]
	level = math.floor(tonumber(level) or 0)
	if not f or level < 0 or level >= f.max then return nil end
	local raw = f.base * (level + 1) ^ 1.4
	return math.max(1, math.floor(raw * (1 - math.clamp(tonumber(discount) or 0, 0, 90) / 100) + 0.5))
end
function CL.forgeValue(id, level)
	local f = CL.Forge[id]
	local v = 0
	if not f then return 0 end
	for i = 1, math.min(math.floor(tonumber(level) or 0), f.max) do v += f.gains[i] end
	return v
end
-- Stats Forgeheart adds now: fortune trimmed to the budget Mastery leaves.
function CL.forgeStats(levels, masteryFortune)
	levels = levels or {}
	local speed = CL.forgeValue("SteadfastPick", levels.SteadfastPick)
	local fortune = CL.forgeValue("HearthglowFortune", levels.HearthglowFortune)
	local room = math.max(0, CL.FORTUNE_BUDGET - math.max(0, tonumber(masteryFortune) or 0))
	local out = {}
	if speed > 0 then out.miningSpeed = speed end
	if math.min(fortune, room) > 0 then out.miningFortune = math.min(fortune, room) end
	return out
end
function CL.forgeSkip(levels) return math.min((levels and levels.SteadfastPick or 0), CL.Forge.SteadfastPick.max) * CL.Forge.SteadfastPick.skipPerLevel end
-- Gem chance in percent per Mining harvest.
function CL.gemChance(levels, total)
	return CL.milestonePerks(total).gemChance + CL.forgeValue("Gemseeker", levels and levels.Gemseeker)
end
-- Gem for a Mining harvest of resource tier index (1 = Copperstone ...).
CL.Gems = {{id="SunstoneChip",w=60,tier=1},{id="Mistpearl",w=25,tier=1},{id="Emberglass",w=10,tier=3},{id="Voidgarnet",w=4.5,tier=5},{id="StarheartGem",w=0.5,tier=7}}
function CL.gemFor(tierIndex, r)
	local total = 0
	for _, g in ipairs(CL.Gems) do if (tierIndex or 1) >= g.tier and Data.Items[g.id] then total += g.w end end
	local pick = (r or 0) * total
	for _, g in ipairs(CL.Gems) do
		if (tierIndex or 1) >= g.tier and Data.Items[g.id] then
			pick -= g.w
			if pick < 0 then return g.id end
		end
	end
	return "SunstoneChip"
end

------------------------------------------------------------------------------
-- Collection Log (generated from data).
------------------------------------------------------------------------------
CL.LogTabOrder = {"Pets","Trails","Minigames","Dungeons","Bosses","Slayer","Creatures","Skilling","Events","Curios"}
CL.LogTabs = {
	Pets={name="Pets",title="Beastbound",coins=25000,color="E07A5F"},
	Trails={name="Treasure Trails",title="Pathfinder Laureate",coins=40000,color="F3C66E"},
	Minigames={name="Minigames",title="Gamewright",coins=30000,color="7FC8C0"},
	Dungeons={name="Dungeons",title="Vaultdelver",coins=35000,color="8FB8D6"},
	Bosses={name="World Bosses",title="Crownbreaker",coins=50000,color="FFAA00"},
	Slayer={name="Slayer",title="Grimward",coins=40000,color="C77DFF"},
	Creatures={name="Creatures",title="Wildlorn",coins=30000,color="6BBF59"},
	Skilling={name="Skilling",title="Artisan Savant",coins=25000,color="06D6A0"},
	Events={name="Events",title="Festive Chronicler",coins=15000,color="FF9ECD"},
	Curios={name="Curios",title="Curio Keeper",coins=15000,color="C9D6E3"},
}
-- Data roots and the tab their rare rows belong to.
CL.LogRoots = {DungeonFloors="Dungeons",Dungeons="Dungeons",DungeonClasses="Dungeons",WorldBosses="Bosses",Endgame="Bosses",
	Slayers="Slayer",SlayerTasks="Slayer",Monsters="Creatures",SeaCreatures="Creatures",Thieving="Skilling",Hunter="Skilling",
	Agility="Skilling",Garden="Skilling",Prayer="Skilling",Workers="Skilling",Trails="Trails",Events="Events",EventVendor="Events"}
local SKIP_CATEGORY = {scroll=true,casket=true,spade=true,teleport=true}
local function loggable(def)
	if not def then return false end
	if def.kind == "resource" then return false end
	if def.kind == "trail" and SKIP_CATEGORY[def.category] then return false end
	return true
end
local function rootTab(root)
	if CL.LogRoots[root] then return CL.LogRoots[root] end
	if string.find(string.lower(root), "minigame", 1, true) then return "Minigames" end
	return "Curios"
end
-- Every item the data marks as obtainable-and-unique, with its tab.
-- Returns {Tabs = {[tab] = {itemIds sorted}}, Of = {[itemId] = tab}, Order, total}.
local cached
function CL.log(force)
	if cached and not force then return cached end
	local rank = {}
	for i, t in ipairs(CL.LogTabOrder) do rank[t] = i end
	local best = {}
	local function offer(id, tab)
		if type(id) ~= "string" or not loggable(Data.Items[id]) then return end
		if not best[id] or rank[tab] < rank[best[id]] then best[id] = tab end
	end
	for id, def in pairs(Data.Items) do
		if def.kind == "pet" then offer(id, "Pets") end
		if def.trailUnique then offer(id, "Trails") end
		if def.slayerUnique then offer(id, "Slayer") end
		if def.minigameUnique or def.logUnique == "Minigames" then offer(id, "Minigames")
		elseif type(def.logUnique) == "string" and rank[def.logUnique] then offer(id, def.logUnique) end -- e.g. Factions
	end
	local seen = {}
	local function walk(t, tab, depth)
		if seen[t] or depth > 10 then return end
		seen[t] = true
		local id, chance = rawget(t, "item"), rawget(t, "chance")
		if type(id) == "string" and type(chance) == "number" and chance > 0 and chance < CL.RARE_CHANCE then offer(id, tab) end
		for _, v in pairs(t) do if type(v) == "table" then walk(v, tab, depth + 1) end end
	end
	local roots = {}
	for k, v in pairs(Data) do if type(k) == "string" and type(v) == "table" and k ~= "Items" and k ~= "CommissionsLogs" then table.insert(roots, k) end end
	-- Fixed walk order: mapped roots by tab rank first, then the rest alphabetically,
	-- so shared sub-tables always credit the same root.
	table.sort(roots, function(a, b)
		local ra, rb = rank[rootTab(a)], rank[rootTab(b)]
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	for _, k in ipairs(roots) do walk(Data[k], rootTab(k), 0) end
	-- Non-iterated monsters (sea creatures, world bosses, superiors) reached through __index.
	local Tabs, Of, total = {}, {}, 0
	for _, tab in ipairs(CL.LogTabOrder) do Tabs[tab] = {} end
	for id, tab in pairs(best) do table.insert(Tabs[tab], id); Of[id] = tab; total += 1 end
	local R = Data.Rarity
	for _, list in pairs(Tabs) do
		table.sort(list, function(a, b)
			local ra, rb = R[Data.Items[a].rarity] and R[Data.Items[a].rarity].rank or 0, R[Data.Items[b].rarity] and R[Data.Items[b].rarity].rank or 0
			if ra ~= rb then return ra < rb end
			return a < b
		end)
	end
	local order = {}
	for _, tab in ipairs(CL.LogTabOrder) do if #Tabs[tab] > 0 then table.insert(order, tab) end end
	cached = {Tabs=Tabs,Of=Of,Order=order,total=total}
	return cached
end
-- Score: rarity rank per distinct entry obtained (Common 1 ... Mythic 6).
function CL.entryPoints(id)
	local def = Data.Items[id]
	local r = def and Data.Rarity[def.rarity]
	return r and r.rank or 1
end
function CL.logScore(counts)
	local L = CL.log()
	local score, max, found = 0, 0, 0
	for id in pairs(L.Of) do
		local pts = CL.entryPoints(id)
		max += pts
		if type(counts) == "table" and (tonumber(counts[id]) or 0) > 0 then score += pts; found += 1 end
	end
	return score, max, found
end
CL.LogRanks = {{share=0,name="Driftling"},{share=0.1,name="Wayseeker"},{share=0.25,name="Lorekeeper"},{share=0.5,name="Archivist"},
	{share=0.75,name="Grand Chronicler"},{share=1,name="Aether Annalist"}}
function CL.logRank(score, max)
	local share = if (max or 0) > 0 then score / max else 0
	local out = CL.LogRanks[1]
	for _, r in ipairs(CL.LogRanks) do if share >= r.share - 1e-9 then out = r end end
	return out, share
end

------------------------------------------------------------------------------
-- Museum.
------------------------------------------------------------------------------
CL.MuseumOrder = {"Weapons","Armor","Rarities","Minerals","Trophies"}
CL.MuseumCategories = {
	Weapons={name="Weapons",color="E8643A",text="Blades, bows and staves."},
	Armor={name="Armor",color="8FB8D6",text="Every helm, chestpiece, greave and boot."},
	Rarities={name="Rarities",color="C77DFF",text="Charms, talismans and curios."},
	Minerals={name="Minerals",color="D4A84B",text="Ores, ingots and cut gems."},
	Trophies={name="Trophies",color="FFAA00",text="Rare drops and relics from the Collection Log."},
}
local function isMineral(id, def)
	if Data.ResourceSkill[id] == "Mining" then return true end
	if def.category == "gem" then return true end
	return def.kind == "material" and string.sub(id, -5) == "Ingot"
end
-- Category for an item id, or nil when it cannot be donated.
function CL.museumCategory(id)
	local def = type(id) == "string" and Data.Items[id]
	if not def then return nil end
	if def.kind == "weapon" then return "Weapons" end
	if def.kind == "armor" then return "Armor" end
	if def.kind == "accessory" then return "Rarities" end
	if isMineral(id, def) then return "Minerals" end
	if CL.log().Of[id] and (def.kind == "material" or (def.kind == "trail" and def.category == "banner")) then return "Trophies" end
	return nil
end
local museumCache
function CL.museum()
	if museumCache then return museumCache end
	local Cats, total = {}, 0
	for _, c in ipairs(CL.MuseumOrder) do Cats[c] = {} end
	for id in pairs(Data.Items) do
		local c = CL.museumCategory(id)
		if c then table.insert(Cats[c], id); total += 1 end
	end
	for _, list in pairs(Cats) do table.sort(list) end
	museumCache = {Cats=Cats,total=total}
	return museumCache
end
CL.MuseumMilestones = {
	{at=5,coins=2500,stats={health=10}},
	{at=15,coins=7500,stats={defense=5}},
	{at=30,coins=20000,stats={strength=3}},
	{at=60,coins=50000,stats={critDamage=5}},
	{at=100,coins=100000,stats={magicFind=2}},
	{at=150,coins=200000,stats={health=25}},
	{at=200,coins=400000,stats={strength=5}},
}
function CL.museumPerks(count)
	count = tonumber(count) or 0
	local stats, reached = {}, 0
	for i, m in ipairs(CL.MuseumMilestones) do
		if count >= m.at then
			reached = i
			for k, v in pairs(m.stats) do stats[k] = (stats[k] or 0) + v end
		end
	end
	return stats, reached
end
end
-- End Commissions & Logs section.

------------------------------------------------------------------------------
-- Crafting (Crafting team; append-only section). A 1-99 production skill with
-- OSRS Crafting depth (original names): gem cutting, jewellery, leatherwork,
-- spinning & weaving and glassblowing at three Guild Terrace stations — the
-- Jeweller's Bench, the Tanning Rack and the Glass Furnace.
--   * Recipes live in CR.Recipes (NOT Data.Recipes): they run only through the
--     server's batch verb (craftBatch "recipe:count") at a station the player
--     stands at, one action per branch cadence (CR.Branches[b].seconds), so a
--     batch of 28 takes 28 x cadence seconds. Every action re-checks level,
--     tool, collection gate and materials (CR.check).
--   * Tools are owned, never consumed (Facet Chisel, Hide Needle, Drop Spindle,
--     Blowing Pipe and three jewellery moulds); they are Forge recipes in
--     Data.Recipes (Smithing 1-5), so Ironman journals make their own.
--   * Gem cutting may shatter a rough gem at low level (CR.cutFailChance):
--     the gem becomes Gem Grit and pays CR.SHATTER_XP of the XP.
--   * Rough gems drop from Mining harvests (CR.gemChance / CR.roughFor,
--     gated by the ore tier); cut gems, leathers and jewellery are collections.
--   * Jewellery are accessories (Magical Power by rarity); the four best
--     amulets can be enchanted (skill Enchanting) at the Jeweller's Bench.
--   * Leatherwork makes five four-piece Ranged armour sets (Data.Sets).
--   * Vials from glassblowing go into every Alchemy potion of Alchemy 8+
--     (CR.VIAL_POTIONS, CR.VIALS_IN_POTIONS = true) and into Tanning Oil.
--   * Crafted outputs never sell for more than their inputs (CR.valueCap).
--   * Jewellery of one gem is an accessory family: only the best member
--     counts (Progression.accessoryFamily / activeAccessories).
--   * Balance model: CR.chainRate (see docs/DEPTH-CONTRACT.md §22).
------------------------------------------------------------------------------
do
local CR = {}
Data.Crafting = CR
table.insert(Data.SkillOrder, "Crafting")
Data.Skills.Crafting = {category="production",color="C9708A",title="Artificer",perLevel={defense=0.5,rangedAccuracy=0.5},
	description="Cut gems, set jewellery, work leather and blow glass. Raises Defense and Ranged Accuracy."}
if Data.Mastery and Data.Mastery.CapePerk then Data.Mastery.CapePerk.Crafting = {defense=10,rangedAccuracy=10} end

CR.MAX_BATCH = 28            -- actions per batch (one satchel load)
CR.VISIT_SECONDS = 900       -- a station visit authorises batches this long
CR.STATION_RANGE = 24        -- studs: stay this close to the station while crafting
CR.TICK = 0.3                -- server loop period (s)
CR.SHATTER_XP = 0.25         -- XP share paid for a shattered gem
CR.CUT_FAIL = 0.3            -- shatter chance at the gem's own level
CR.CUT_FADE = 25             -- ... fading to zero this many levels above it
CR.GEM_CHANCE = 0.01         -- rough gem per Mining harvest at ore tier 1
CR.GEM_TIER_BONUS = 0.1      -- +10% of that chance per ore tier above 1
CR.MAX_MADE = 1e9

CR.StationOrder = {"Jeweller","Tannery","Glassworks"}
CR.Stations = {
	Jeweller={id="Jeweller",name="Jeweller's Bench",verb="Cut & set",color="E86FB8",gesture={"hammer"},
		text="Cut rough gems, set rings, necklaces and amulets, and enchant the finest amulets."},
	Tannery={id="Tannery",name="Tanning Rack",verb="Tan & stitch",color="A8763E",gesture={"saw","hammer"},
		text="Tan hides, spin thread, weave cloth and stitch Ranged leathers."},
	Glassworks={id="Glassworks",name="Glass Furnace",verb="Melt & blow",color="5EC8D8",gesture={"stir"},
		text="Sift sand, melt molten glass and blow baubles, vials, orbs and lenses."},
}
-- Branches: station, cadence (seconds per action), tool (owned item) and gesture.
CR.BranchOrder = {"cut","jewel","enchant","tan","spin","weave","leather","sift","melt","blow"}
CR.Branches = {
	cut={name="Gem Cutting",station="Jeweller",seconds=1.8,tool="FacetChisel",gesture="hammer"},
	jewel={name="Jewellery",station="Jeweller",seconds=2.4,gesture="hammer"},
	enchant={name="Amulet Enchanting",station="Jeweller",seconds=3,gesture="stir"},
	tan={name="Tanning",station="Tannery",seconds=1.2,gesture="saw"},
	spin={name="Spinning",station="Tannery",seconds=1.2,tool="DropSpindle",gesture="saw"},
	weave={name="Weaving",station="Tannery",seconds=1.8,tool="DropSpindle",gesture="saw"},
	leather={name="Leatherwork",station="Tannery",seconds=2.4,tool="HideNeedle",gesture="hammer"},
	sift={name="Sand Sifting",station="Glassworks",seconds=1.2,gesture="stir"},
	melt={name="Glassmelting",station="Glassworks",seconds=1.8,gesture="stir"},
	blow={name="Glassblowing",station="Glassworks",seconds=1.8,tool="BlowingPipe",gesture="stir"},
}
for id, b in pairs(CR.Branches) do b.id = id end

------------------------------------------------------------------------------
-- Tools (Forge, Smithing): owned, never used up.
------------------------------------------------------------------------------
CR.ToolOrder = {"FacetChisel","HideNeedle","DropSpindle","BlowingPipe","RingMould","NecklaceMould","AmuletMould"}
for _, t in ipairs({
	{id="FacetChisel",name="Facet Chisel",color="C9D6E3",costs={AlloyIngot=1},level=1,text="Crafting tool: cut rough gems."},
	{id="HideNeedle",name="Hide Needle",color="D8C3A5",costs={AlloyIngot=1},level=1,text="Crafting tool: stitch leather."},
	{id="DropSpindle",name="Drop Spindle",color="C49A6C",costs={Timber=2,AlloyIngot=1},level=1,text="Crafting tool: spin thread and weave cloth."},
	{id="BlowingPipe",name="Blowing Pipe",color="7FD6E8",costs={AlloyIngot=2},level=1,text="Crafting tool: blow molten glass."},
	{id="RingMould",name="Ring Mould",color="D4A84B",costs={AlloyIngot=2},level=1,text="Crafting tool: cast rings."},
	{id="NecklaceMould",name="Necklace Mould",color="D4A84B",costs={AlloyIngot=2,BrassIngot=1},level=5,text="Crafting tool: cast necklaces."},
	{id="AmuletMould",name="Amulet Mould",color="D4A84B",costs={AlloyIngot=2,BrassIngot=1},level=5,text="Crafting tool: cast amulets."},
}) do
	item(t.id,{name=t.name,kind="material",category="craftTool",rarity="Common",color=t.color,value=15,description=t.text.." Never used up."})
	recipe(t.id,{skill="Smithing",level=t.level,xp=10,costs=t.costs,station="Forge",category="Tools"})
end

------------------------------------------------------------------------------
-- Materials and recipes.
------------------------------------------------------------------------------
CR.Recipes, CR.RecipeOrder = {}, {}
local function craft(id, def)
	def.id = id
	def.output = def.output or id
	def.amount = def.amount or 1
	def.skill = def.skill or "Crafting"
	local b = CR.Branches[def.branch]
	assert(b, "crafting branch "..tostring(def.branch))
	def.station = b.station
	def.tool = def.tool or b.tool
	def.seconds = b.seconds
	-- Every pattern can be run again (batches), but only stackable outputs
	-- (materials, consumables) count as `repeatable`: pet extra-craft abilities
	-- (Pets.craftStackable) must never duplicate armour or jewellery.
	local outDef = Data.Items[def.output]
	def.repeatable = outDef ~= nil and (outDef.kind == "material" or outDef.kind == "consumable")
	CR.Recipes[id] = def
	table.insert(CR.RecipeOrder, id)
	return def
end
local function rarityStep(rarity, step)
	local i = table.find(Data.RarityOrder, rarity) or 1
	return Data.RarityOrder[math.clamp(i + step, 1, #Data.RarityOrder)]
end

-- Gems: rough (Mining drop) -> cut (Jeweller's Bench). Five cut gems already
-- exist (Thieving loot, Gemseeker); three are new. minTier = lowest Mining ore
-- tier (1 = Copperstone ... 8 = Celestium) that can turn the rough gem up.
-- stat/stat2 theme the gem's jewellery; ingot casts it. A rough gem sells for
-- the cut gem's value (cutting never mints coins; five cut gems are Thieving
-- loot whose values stay as they are). gems/ingots (optional) raise the cost of
-- the cheap early jewellery so its Magical Power per coin of input stays within
-- 2x of the Workbench talismans of the same rarity (see verify-crafting).
item("Dewquartz",{name="Dewquartz",kind="material",category="gem",rarity="Common",color="BDE8E0",value=8,description="A cut gem. Set into jewellery or sell to a merchant."})
item("Skyjade",{name="Skyjade",kind="material",category="gem",rarity="Rare",color="5FBF8F",value=65,description="A cut gem. Set into jewellery or sell to a merchant."})
item("Stormopal",{name="Stormopal",kind="material",category="gem",rarity="Epic",color="9FB4FF",value=420,description="A cut gem. Set into jewellery or sell to a merchant."})
item("GemGrit",{name="Gem Grit",kind="material",rarity="Common",color="C7C2B8",value=2,description="The glittering dust of a shattered gem. Fluxes molten glass."})
CR.Gems = {
	{cut="Dewquartz",rough="RoughDewquartz",roughName="Rough Dewquartz",level=1,xp=15,minTier=1,w=40,ingot="AlloyIngot",gems=4,ingots=2,stat="health",m=8,stat2="defense",m2=3},
	{cut="SunstoneChip",rough="RoughSunstone",roughName="Rough Sunstone",level=10,xp=24,minTier=1,w=30,ingot="BrassIngot",gems=2,stat="strength",m=3,stat2="health",m2=10},
	{cut="Mistpearl",rough="CloudedMistpearl",roughName="Clouded Mistpearl",level=20,xp=48,minTier=2,w=20,ingot="BrassIngot",gems=2,stat="intelligence",m=10,stat2="health",m2=12},
	{cut="Skyjade",rough="RoughSkyjade",roughName="Rough Skyjade",level=30,xp=64,minTier=3,w=15,ingot="SunsteelIngot",stat="defense",m=8,stat2="rangedAccuracy",m2=5},
	{cut="Emberglass",rough="RoughEmberglass",roughName="Rough Emberglass",level=40,xp=82,minTier=4,w=10,ingot="SunsteelIngot",stat="critDamage",m=6,stat2="strength",m2=4},
	{cut="Voidgarnet",rough="RoughVoidgarnet",roughName="Rough Voidgarnet",level=52,xp=104,minTier=5,w=6,ingot="VoidforgedIngot",stat="critChance",m=2,stat2="critDamage",m2=8},
	{cut="Stormopal",rough="RoughStormopal",roughName="Rough Stormopal",level=64,xp=132,minTier=6,w=3,ingot="StarmetalIngot",stat="rangedStrength",m=6,stat2="rangedAccuracy",m2=8},
	{cut="StarheartGem",rough="RoughStarheart",roughName="Rough Starheart",level=78,xp=166,minTier=7,w=1.2,ingot="PrismaticIngot",stat="magicFind",m=3,stat2="critDamage",m2=12},
}
CR.GemByCut, CR.GemByRough = {}, {}
local roughScale = {0.5,0.4,0.3,0.25,0.2,0.1,0.05,0.02}
for i, g in ipairs(CR.Gems) do
	g.index = i
	CR.GemByCut[g.cut], CR.GemByRough[g.rough] = g, g
	local cut = Data.Items[g.cut]
	g.short = string.gsub(cut.name, " Gem$", "")
	g.short = string.gsub(g.short, " Chip$", "")
	item(g.rough,{name=g.roughName,kind="material",category="roughGem",rarity=rarityStep(cut.rarity,-1),color=cut.color,value=cut.value,
		description="An uncut gem from a Mining seam. Cut it with a Facet Chisel at Crafting "..g.level.."."})
	craft(g.cut,{branch="cut",level=g.level,xp=g.xp,costs={[g.rough]=1},category="Gems",shatter=true})
	table.insert(Data.CollectionItems, g.rough)
	Data.CollectionScale[g.rough] = roughScale[i]
end
-- New cut gems join the gem collections (the five existing ones already are).
for id, scale in pairs({Dewquartz=0.5,Skyjade=0.25,Stormopal=0.05}) do
	table.insert(Data.CollectionItems, id)
	Data.CollectionScale[id] = scale
end

-- Spinning & weaving (Tannery). Thread strings amulets and stitches leather;
-- Skyweave lines the better cowls and jerkins.
item("SpunThread",{name="Spun Thread",kind="material",rarity="Common",color="EDE3CF",value=2,description="Spun from Meadow Herb fibre. Stitches leather and strings amulets."})
item("SkyweaveBolt",{name="Skyweave Bolt",kind="material",rarity="Uncommon",color="B8D4E8",value=16,description="A bolt of woven cloth. Lines cowls and jerkins."})
craft("SpunThread",{branch="spin",level=1,xp=3,costs={Herb=2},amount=3,category="Thread"})
craft("SkyweaveBolt",{branch="weave",level=20,xp=22,costs={SpunThread=4,Sunwheat=1},category="Thread"})

-- Glass (Glassworks): Copperstone sifts into sand; sand + log fuel melts into
-- glass (grit from shattered gems fluxes a richer melt); the pipe blows it.
item("Skysand",{name="Skysand",kind="material",rarity="Common",color="E8D9A8",value=1,description="Crushed Copperstone, sifted fine. Melts into glass."})
item("MoltenGlass",{name="Molten Skyglass",kind="material",rarity="Common",color="9EE7E8",value=6,description="Glowing glass, ready for the Blowing Pipe."})
craft("Skysand",{branch="sift",level=1,xp=1,costs={Ore=1},amount=2,category="Glass"})
craft("MoltenGlass",{branch="melt",level=1,xp=6,costs={Skysand=2,Timber=1},category="Glass"})
craft("MoltenGlassWindpine",{output="MoltenGlass",branch="melt",level=15,xp=12,costs={Skysand=4,WindpineLog=1},amount=2,category="Glass"})
craft("MoltenGlassGrit",{output="MoltenGlass",branch="melt",level=30,xp=14,costs={Skysand=3,GemGrit=1,EmberoakLog=1},amount=3,category="Glass"})
CR.GlassOrder = {"GlassBauble","GlassVial","LanternGlobe","SkyglassOrb","PrismLens"}
for _, g in ipairs({
	{id="GlassBauble",name="Glass Bauble",level=1,xp=12,glass=1,color="CFEFFF",value=8,rarity="Common",text="A pretty bauble. Merchants pay well for a basket of them."},
	{id="GlassVial",name="Skyglass Vial",level=8,xp=20,glass=1,color="A8E6F0",value=10,rarity="Common",text="A stoppered vial. Holds Tanning Oil (and, if the guild agrees, potions)."},
	{id="LanternGlobe",name="Lantern Globe",level=25,xp=38,glass=1,extra={Aetherite=1},color="FFE9A8",value=30,rarity="Uncommon",text="A lamp globe. Sought by builders and merchants."},
	{id="SkyglassOrb",name="Skyglass Orb",level=46,xp=52,glass=2,color="7FD6E8",value=80,rarity="Rare",text="A flawless orb. Set into Farsight Orbs."},
	{id="PrismLens",name="Prism Lens",level=70,xp=96,glass=2,extra={Prismite=1},color="E86FB8",value=220,rarity="Epic",text="A cut prism lens. Set into Prism Monocles."},
}) do
	item(g.id,{name=g.name,kind="material",rarity=g.rarity,color=g.color,value=g.value,description=g.text})
	local costs = {MoltenGlass=g.glass}
	for k, v in pairs(g.extra or {}) do costs[k] = v end
	craft(g.id,{branch="blow",level=g.level,xp=g.xp,costs=costs,category="Glassware"})
end
-- Tanning oil: vial + herbs (the glass -> leather link).
item("TanningOil",{name="Tanning Oil",kind="material",rarity="Common",color="C9A25A",value=8,description="Brushed into pelts to cure them into supple leather."})
craft("TanningOil",{branch="tan",level=10,xp=6,costs={GlassVial=1,Herb=2},category="Tanning"})

-- Leather tiers: hide -> leather (Tannery), leather + thread -> a four-piece
-- Ranged set (Data.Sets; bonus with all four worn).
CR.LeatherOrder = {"CuredLeather","QuiltedLeather","EmberhideLeather","ShadowhideLeather","StormhideLeather"}
CR.Leathers = {
	{id="CuredLeather",name="Cured Leather",hide={BeastHide=1},level=1,tanXp=2,color="9C6B46",value=8,rarity="Common",
		set={id="Wayfarer",name="Wayfarer",level=1,ranged=1,xp=18,rarity="Common",color="9C6B46",
			armor={defense=18,health=10,rangedAccuracy=6,rangedStrength=2},bonus={rangedAccuracy=10},text="+10 Ranged Accuracy"}},
	{id="QuiltedLeather",name="Quilted Leather",hide={DownyPelt=1},oil=1,level=18,tanXp=6,color="E8DCC8",value=18,rarity="Uncommon",
		set={id="Downstride",name="Downstride",level=18,ranged=10,xp=26,rarity="Uncommon",color="D8C8AE",
			armor={defense=35,health=25,rangedAccuracy=12,rangedStrength=5},bonus={rangedAccuracy=15,defense=15},text="+15 Ranged Accuracy, +15 Defense"}},
	{id="EmberhideLeather",name="Emberhide Leather",hide={EmberPelt=1},oil=1,level=38,tanXp=10,color="D9642B",value=45,rarity="Rare",gate={EmberPelt=1},
		set={id="Cinderhide",name="Cinderhide",level=38,ranged=25,xp=56,rarity="Rare",color="C2562A",lining=true,
			armor={defense=60,health=45,rangedAccuracy=20,rangedStrength=6,critChance=1},bonus={rangedStrength=8,critDamage=15},text="+8 Ranged Strength, +15 Crit Damage"}},
	{id="ShadowhideLeather",name="Shadowhide Leather",hide={ShadowPelt=1},oil=1,level=58,tanXp=16,color="3D3654",value=110,rarity="Epic",gate={ShadowPelt=1},
		set={id="Duskprowl",name="Duskprowl",level=58,ranged=40,xp=92,rarity="Epic",color="4A3F6B",lining=true,
			armor={defense=95,health=75,rangedAccuracy=22,rangedStrength=8,critChance=2},bonus={rangedStrength=10,critChance=5,speed=5},text="+10 Ranged Strength, +5 Crit Chance, +5 Speed"}},
	{id="StormhideLeather",name="Stormhide Leather",hide={StormmaneHide=1},oil=2,level=76,tanXp=24,color="8FA3C8",value=170,rarity="Epic",gate={StormmaneHide=1},
		set={id="Stormmantle",name="Stormmantle",level=76,ranged=55,xp=132,rarity="Legendary",color="7F95C8",lining=true,
			armor={defense=140,health=110,rangedAccuracy=18,rangedStrength=9,critChance=3},bonus={rangedStrength=12,critDamage=15,defense=40},text="+12 Ranged Strength, +15 Crit Damage, +40 Defense"}},
}
CR.SetOrder = {}
local slotShare = {helmet=0.6,chest=1,legs=0.85,boots=0.5}
local pieceNames = {helmet="Cowl",chest="Jerkin",legs="Leggings",boots="Treads"}
local pieceLeather = {helmet=1,chest=3,legs=2,boots=1}
local pieceLevel = {boots=0,helmet=3,legs=6,chest=10}
for i, l in ipairs(CR.Leathers) do
	l.index = i
	item(l.id,{name=l.name,kind="material",rarity=l.rarity,color=l.color,value=l.value,description="Tanned at the Tanning Rack. Stitched into "..l.set.name.." leathers."})
	local costs = table.clone(l.hide)
	if l.oil then costs.TanningOil = l.oil end
	craft(l.id,{branch="tan",level=l.level,xp=l.tanXp,costs=costs,category="Tanning",collectionTier=l.gate})
	local s = l.set
	table.insert(CR.SetOrder, s.id)
	Data.Sets[s.id] = {id=s.id,name=s.name,pieces={},bonus=s.bonus,text=s.text,color=s.color,crafting=true}
	for _, slot in ipairs(Data.ArmorSlots) do
		local id = s.id..pieceNames[slot]
		local stats = {}
		for k, v in pairs(s.armor) do stats[k] = math.max(1, math.floor(v * slotShare[slot] + 0.5)) end
		local n = pieceLeather[slot]
		local pcosts = {[l.id]=n,SpunThread=n}
		if s.lining and (slot == "chest" or slot == "helmet") then pcosts.SkyweaveBolt = 1 end
		item(id,{name=s.name.." "..pieceNames[slot],kind="armor",slot=slot,set=s.id,tier=i+1,rarity=s.rarity,color=s.color,stats=stats,requires={Ranged=s.ranged},
			value=l.value*n+10,description="Ranged leather. Part of the "..s.name.." set: "..s.text.." with all four. Requires Ranged "..s.ranged.."."})
		craft(id,{branch="leather",level=math.min(99,s.level+pieceLevel[slot]),xp=s.xp*n+4,costs=pcosts,category=s.name,
			collectionTier=if i >= 2 then {[l.id]=1} else nil})
		table.insert(Data.Sets[s.id].pieces, id)
	end
	table.insert(Data.CollectionItems, l.id)
	Data.CollectionScale[l.id] = ({1,0.6,0.4,0.25,0.15})[i]
end

-- Jewellery (Jeweller's Bench): ingot + cut gem cast in a mould. Rings sit two
-- rarities below the gem, necklaces one, amulets at the gem's rarity.
CR.JewelKinds = {
	{id="Ring",name="Ring",mould="RingMould",dl=3,ingots=1,thread=0,rarity=-2,stats="ring",xpMult=1.1,xpAdd=5},
	{id="Necklace",name="Necklace",mould="NecklaceMould",dl=6,ingots=2,thread=0,rarity=-1,stats="necklace",xpMult=1.3,xpAdd=10},
	{id="Amulet",name="Amulet",mould="AmuletMould",dl=10,ingots=2,thread=1,rarity=0,stats="amulet",xpMult=1.6,xpAdd=15},
}
CR.JewelleryOrder = {}
for _, g in ipairs(CR.Gems) do
	local gemRarity = Data.Items[g.cut].rarity
	for _, k in ipairs(CR.JewelKinds) do
		local id = g.short:gsub("[^%w]", "")..k.id
		local stats = if k.stats == "ring" then {[g.stat]=g.m} elseif k.stats == "necklace" then {[g.stat2]=g.m2} else {[g.stat]=g.m,[g.stat2]=g.m2}
		local rarity = rarityStep(gemRarity, k.rarity)
		local costs = {[g.cut]=g.gems or 1,[g.ingot]=k.ingots+(g.ingots or 0)}
		if k.thread > 0 then costs.SpunThread = k.thread end
		item(id,{name=g.short.." "..k.name,kind="accessory",category="jewellery",gem=g.cut,rarity=rarity,color=Data.Items[g.cut].color,stats=stats,
			value=40*Data.Rarity[rarity].rank^2,description="Jewellery accessory. Magical Power "..Data.Rarity[rarity].power.."."})
		craft(id,{branch="jewel",level=math.min(99,g.level+k.dl),xp=math.floor(g.xp*k.xpMult+k.xpAdd),costs=costs,tool=k.mould,
			collectionTier=if g.index >= 3 then {[g.cut]=1} else nil,category=k.name.."s"})
		table.insert(CR.JewelleryOrder, id)
		if k.id == "Amulet" then g.amulet = id end
	end
end
-- Enchanted amulets (skill Enchanting): the four best amulets gain a rarity and
-- a third stat. Arcane Dust + glyphs (+ extra cut gems where the amulet alone is
-- too cheap for the new rarity), Enchanting level gate. XP: 2 per Arcane Dust,
-- the Tempering Tome rate (180 XP / 96 dust).
CR.ENCHANT_XP_PER_DUST = 2
CR.EnchantOrder = {}
for i, e in ipairs({
	{gem="Emberglass",level=35,dust=24,glyph="SparkGlyph",glyphs=10,extra={strength=6},title="Kindled"},
	{gem="Voidgarnet",level=50,dust=48,glyph="SurgeGlyph",glyphs=6,gems=3,extra={critDamage=10},title="Hollowed"},
	{gem="Stormopal",level=65,dust=80,glyph="SurgeGlyph",glyphs=12,gems=1,extra={speed=4},title="Tempest-bound"},
	{gem="StarheartGem",level=80,dust=128,glyph="TorrentGlyph",glyphs=8,gems=6,extra={health=60},title="Starlit"},
}) do
	local g = CR.GemByCut[e.gem]
	local base = Data.Items[g.amulet]
	local id = "Enchanted"..g.amulet
	local stats = {}
	for k, v in pairs(base.stats) do stats[k] = math.floor(v * 1.5 + 0.5) end
	for k, v in pairs(e.extra) do stats[k] = (stats[k] or 0) + v end
	local rarity = rarityStep(base.rarity, 1)
	item(id,{name=e.title.." "..base.name,kind="accessory",category="jewellery",gem=g.cut,enchanted=true,rarity=rarity,color=base.color,stats=stats,
		value=40*Data.Rarity[rarity].rank^2,description="Enchanted jewellery accessory. Magical Power "..Data.Rarity[rarity].power.."."})
	local costs = {[g.amulet]=1,ArcaneDust=e.dust,[e.glyph]=e.glyphs}
	if e.gems then costs[g.cut] = e.gems end
	craft(id,{skill="Enchanting",branch="enchant",level=e.level,xp=e.dust*CR.ENCHANT_XP_PER_DUST,costs=costs,category="Enchanted"})
	table.insert(CR.EnchantOrder, id)
	table.insert(CR.JewelleryOrder, id)
end
-- Glass accessories.
item("FarsightOrb",{name="Farsight Orb",kind="accessory",category="jewellery",rarity="Rare",color="7FD6E8",stats={intelligence=25,magicFind=1},value=40*9,description="Accessory. Magical Power "..Data.Rarity.Rare.power.."."})
craft("FarsightOrb",{branch="jewel",level=50,xp=180,costs={SkyglassOrb=2,Mistpearl=2,VoidforgedIngot=2},tool="AmuletMould",collectionTier={MoltenGlass=3},category="Glass Charms"})
item("PrismMonocle",{name="Prism Monocle",kind="accessory",category="jewellery",rarity="Epic",color="E86FB8",stats={rangedAccuracy=15,critChance=2},value=40*16,description="Accessory. Magical Power "..Data.Rarity.Epic.power.."."})
craft("PrismMonocle",{branch="jewel",level=74,xp=320,costs={PrismLens=2,Stormopal=1,StarmetalIngot=2},tool="RingMould",collectionTier={MoltenGlass=5},category="Glass Charms"})
table.insert(CR.JewelleryOrder, "FarsightOrb")
table.insert(CR.JewelleryOrder, "PrismMonocle")
table.insert(Data.CollectionItems, "MoltenGlass")
Data.CollectionScale.MoltenGlass = 1

-- No Crafting pattern mints coins (like PD.recipeInputValue for pet recipes):
-- every output sells for at most floor(sum of input values / amount). Inputs
-- may themselves be crafted, so repeat until nothing changes (values only fall).
function CR.inputValue(rec)
	local total = 0
	for id, n in pairs(rec.costs) do total += (Data.Items[id] and Data.Items[id].value or 0) * n end
	return total
end
function CR.valueCap(rec) return math.floor(CR.inputValue(rec) / rec.amount) end
for _ = 1, 10 do
	local changed = false
	for _, id in ipairs(CR.RecipeOrder) do
		local rec = CR.Recipes[id]
		local out = Data.Items[rec.output]
		local cap = CR.valueCap(rec)
		if (out.value or 0) > cap then out.value = cap; changed = true end
	end
	if not changed then break end
end

------------------------------------------------------------------------------
-- Rules (pure; shared by the server, the UI and the tests).
------------------------------------------------------------------------------
-- Shatter chance (0..1) for cutting gem recipe `rec` at Crafting `level`.
function CR.cutFailChance(rec, level)
	if not rec or not rec.shatter then return 0 end
	local over = math.max(0, (tonumber(level) or 1) - rec.level)
	return math.max(0, CR.CUT_FAIL * (1 - over / CR.CUT_FADE))
end
-- Rough gem chance per Mining harvest of ore tier `tierIndex` (1..8+).
function CR.gemChance(tierIndex)
	local t = math.max(1, math.floor(tonumber(tierIndex) or 1))
	return CR.GEM_CHANCE * (1 + CR.GEM_TIER_BONUS * (t - 1))
end
-- Weighted rough gem for ore tier `tierIndex`, r in [0,1).
function CR.roughFor(tierIndex, r)
	local t = math.max(1, math.floor(tonumber(tierIndex) or 1))
	local total = 0
	for _, g in ipairs(CR.Gems) do if t >= g.minTier then total += g.w end end
	local pick = math.clamp(tonumber(r) or 0, 0, 0.999999) * total
	local last
	for _, g in ipairs(CR.Gems) do
		if t >= g.minTier then
			last = g.rough
			pick -= g.w
			if pick < 0 then return g.rough end
		end
	end
	return last
end
-- Copies of `itemId` that are worn (gear slot) or in the accessory bag. A batch
-- never consumes them (Slayer review rule); server and UI share this count.
function CR.heldCount(p, itemId)
	local held = 0
	if type(p) ~= "table" then return 0 end
	if type(p.equipment) == "table" then for _, e in pairs(p.equipment) do if e == itemId then held += 1 end end end
	if type(p.accessoryBag) == "table" then for _, b in ipairs(p.accessoryBag) do if b == itemId then held += 1 end end end
	return held
end
-- Copies of `itemId` a batch may spend (owned minus worn/bagged).
function CR.spare(p, itemId)
	local items = (type(p) == "table" and type(p.items) == "table") and p.items or {}
	return math.max(0, (tonumber(items[itemId]) or 0) - CR.heldCount(p, itemId))
end
-- Actions the satchel can fund right now (spare copies only), capped at MAX_BATCH.
function CR.affordable(p, rec)
	local n = CR.MAX_BATCH
	if type(rec) ~= "table" then return 0 end
	for itemId, need in pairs(rec.costs) do n = math.min(n, math.floor(CR.spare(p, itemId) / math.max(1, need))) end
	return math.max(0, n)
end
-- Can `p` take one action of recipe `id` now? Returns ok, reason.
-- levelOf(skill) and tierOf(item) default to Progression-free reads so the UI
-- can call this with its own snapshot helpers. `p` = {items, equipment,
-- accessoryBag}: worn/bagged copies of a cost item are never counted.
function CR.check(p, id, levelOf, tierOf)
	local rec = type(id) == "string" and CR.Recipes[id]
	if not rec then return false, "Choose a Crafting pattern." end
	local items = (type(p) == "table" and type(p.items) == "table") and p.items or {}
	local out = Data.Items[rec.output]
	local lvl = levelOf(rec.skill)
	if lvl < rec.level then return false, out.name.." requires "..rec.skill.." "..rec.level.."." end
	if rec.tool and (items[rec.tool] or 0) < 1 then return false, "You need a "..Data.Items[rec.tool].name.." (forge one at the Forge)." end
	for itemId, tier in pairs(rec.collectionTier or {}) do
		if tierOf(itemId) < tier then return false, "Unlocks at "..Data.Items[itemId].name.." collection tier "..tier.."." end
	end
	for itemId, n in pairs(rec.costs) do
		if (items[itemId] or 0) < n then return false, "Needs "..n.." "..Data.Items[itemId].name.."." end
	end
	for itemId, n in pairs(rec.costs) do
		if CR.spare(p, itemId) < n then
			return false, "Unequip "..Data.Items[itemId].name.." (or take it out of your accessory bag) first, or carry a spare."
		end
	end
	return true
end
-- Recipes of a station, in CR.RecipeOrder.
function CR.stationRecipes(station)
	local out = {}
	for _, id in ipairs(CR.RecipeOrder) do if CR.Recipes[id].station == station then table.insert(out, CR.Recipes[id]) end end
	return out
end
-- Parse "recipe:count" (count 1..MAX_BATCH, default 1).
function CR.parseBatch(text)
	if type(text) ~= "string" or #text > 64 then return nil end
	local id, n = string.match(text, "^(%w+):(%d+)$")
	if not id then id, n = string.match(text, "^(%w+)$"), "1" end
	n = tonumber(n)
	if not id or not CR.Recipes[id] or not n or n < 1 or n % 1 ~= 0 then return nil end
	return id, math.min(n, CR.MAX_BATCH)
end

------------------------------------------------------------------------------
-- Balance model. Supply-chain XP/h: crafting XP of a recipe and all its
-- crafted inputs, per second of gathering the raw inputs plus every station
-- action (seconds). Raw seconds: resource tiers = max(respawn, GATHER) (the
-- verify-skills gather model); creature/Hunter drops use CR.SourceSeconds.
-- Gem cutting is a bonus on Mining (rough gems are rare) and is reported
-- separately (CR.cutRate). verify-crafting.luau holds each tier's chain rate
-- within 0.5x..2x of the best Smithing/Fletching chain open at that level.
------------------------------------------------------------------------------
CR.GATHER = 1 + 0.65
CR.SourceSeconds = {BeastHide=20,DownyPelt=15,EmberPelt=35,ShadowPelt=70,StormmaneHide=110,ArcaneDust=8,SparkGlyph=4,SurgeGlyph=10,TorrentGlyph=25}
function CR.rawSeconds(id, depth)
	depth = depth or 0
	for _, tiers in pairs(Data.ResourceTiers) do
		for _, r in ipairs(tiers) do if r.id == id then return math.max(r.respawn, CR.GATHER) end end
	end
	if CR.SourceSeconds[id] then return CR.SourceSeconds[id] end
	local rec = CR.Recipes[id]
	if rec and depth < 6 then return CR.chain(rec, depth + 1).seconds / rec.amount end
	local smith = Data.Recipes[id]
	if smith and depth < 6 then
		local s = 0
		for k, n in pairs(smith.costs) do s += n * CR.rawSeconds(k, depth + 1) end
		return s / (smith.amount or 1)
	end
	return 30
end
-- {xp, seconds} for one action of rec including crafted inputs (per action).
-- XP counts only rec.skill (an enchanted amulet's chain includes the amulet's
-- casting time but not its Crafting XP).
function CR.chain(rec, depth)
	depth = depth or 0
	local xp, seconds = rec.xp, rec.seconds
	for k, n in pairs(rec.costs) do
		local sub = CR.Recipes[k]
		if sub and depth < 6 then
			local c = CR.chain(sub, depth + 1)
			if sub.skill == rec.skill then xp += c.xp * n / sub.amount end
			seconds += c.seconds * n / sub.amount
		else
			seconds += n * CR.rawSeconds(k, depth + 1)
		end
	end
	return {xp=xp, seconds=seconds}
end
function CR.chainRate(rec)
	local c = CR.chain(rec)
	return 3600 * c.xp / c.seconds
end
-- XP/h at the station with materials already in the satchel (cadence-bound).
function CR.stationRate(rec) return 3600 * rec.xp * (1 - 0.75 * CR.cutFailChance(rec, rec.level + 10)) / rec.seconds end
-- Expected cutting XP/h from Mining at ore tier t (bonus on top of Mining).
function CR.cutRate(tierIndex, harvestsPerHour)
	local total, xp = 0, 0
	for _, g in ipairs(CR.Gems) do if tierIndex >= g.minTier then total += g.w end end
	for _, g in ipairs(CR.Gems) do if tierIndex >= g.minTier then xp += g.w / total * g.xp end end
	return harvestsPerHour * CR.gemChance(tierIndex) * xp
end

------------------------------------------------------------------------------
-- Alchemy link (lead approved): one Skyglass Vial per potion brewed. Every
-- Data.Recipes potion (category "Potions", Alchemy) of Alchemy level
-- >= CR.VIAL_MIN_ALCHEMY takes one vial; the early potions (Might Draught,
-- the Meadow diary brew) stay vial-free so early Alchemy is not gated behind
-- Crafting. CR.VIAL_POTIONS lists the vial potions (sorted by level, id).
------------------------------------------------------------------------------
CR.VIALS_IN_POTIONS = true
CR.VIAL_MIN_ALCHEMY = 8
CR.VIAL_POTIONS, CR.VIAL_EXEMPT = {}, {}
for id, r in pairs(Data.Recipes) do
	if r.category == "Potions" and r.skill == "Alchemy" then
		table.insert(if r.level >= CR.VIAL_MIN_ALCHEMY then CR.VIAL_POTIONS else CR.VIAL_EXEMPT, id)
	end
end
local function byLevel(a, b)
	local la, lb = Data.Recipes[a].level, Data.Recipes[b].level
	if la ~= lb then return la < lb end
	return a < b
end
table.sort(CR.VIAL_POTIONS, byLevel)
table.sort(CR.VIAL_EXEMPT, byLevel)
if CR.VIALS_IN_POTIONS then
	for _, id in ipairs(CR.VIAL_POTIONS) do
		local r = Data.Recipes[id]
		r.costs.GlassVial = (r.costs.GlassVial or 0) + 1
	end
end

------------------------------------------------------------------------------
-- Commissions: four Crafting tasks (kind "craft": one per crafting action of
-- the target output, credited by the server's batch loop).
------------------------------------------------------------------------------
local CL = Data.CommissionsLogs
if CL and CL.Tasks then
	for _, t in ipairs({
		{id="CraftGlassVial",name="Vial Order",target="GlassVial",amount=20,xp=500,coins=60,dust=20,level=8},
		{id="CraftCuredLeather",name="Tannery Shift",target="CuredLeather",amount=20,xp=300,coins=50,dust=18,level=1},
		{id="CraftSunstoneChip",name="Sunstone Cutting",target="SunstoneChip",amount=4,xp=480,coins=120,dust=30,level=10},
		{id="CraftSkyweaveBolt",name="Skyweave Loom",target="SkyweaveBolt",amount=10,xp=900,coins=140,dust=34,level=20},
	}) do
		t.kind, t.skill, t.group, t.levels, t.level = "craft", "Crafting", "Crafting", {Crafting=t.level}, nil
		table.insert(CL.Tasks, t)
		CL.TaskById[t.id] = t
	end
end
end
-- End Crafting section.

------------------------------------------------------------------------------
-- >>> BEGIN Exploration & Factions (Exploration & Factions team; append-only section) >>>
-- Two systems (docs/DEPTH-CONTRACT.md §24):
--   * Aether Motes (Data.Exploration): 78 hidden collectibles across the 13
--     world islands. Positions are island-relative (Workspace.Islands[isle]
--     IslandCenter + at); the client renders them locally (no server parts),
--     the server validates pickups by distance to the nearest unfound mote.
--     Milestones are claimed at Mote Shrines and paid as p.perkStats.motes.
--   * Factions (Data.Factions): three rival orders with daily tasks (UTC day,
--     roll-forward only), reputation ranks, sigils and a rank-gated shop.
-- Pure rules live here so the client previews match the server.
------------------------------------------------------------------------------
do
local EX = {}
Data.Exploration = EX
EX.MOTE = {name="Aether Mote", plural="Aether Motes", color="9FE6F2", symbol="✧"}
EX.PICKUP_RADIUS = 9     -- studs from the HumanoidRootPart to the mote (server check)
EX.RENDER_RADIUS = 150   -- studs: the client draws unfound motes this close
EX.PICKUP_COOLDOWN = 1   -- seconds between pickups (server, per player)
EX.HINT_SECONDS = 120    -- a Wayglass bearing stays on screen this long
-- Anti-teleport pickup checks (server). Positions are sampled every
-- SAMPLE_SECONDS; a pickup needs DWELL_SECONDS inside the mote's island
-- region since arriving (a jump between samples restarts the clock), and the
-- horizontal travel implied since the last pickup (or sample) may not exceed
-- SPEED_FACTOR x max(BASE_WALK, the humanoid's WalkSpeed) + SPEED_SLACK
-- studs unless a known fast-travel event (waystone leaf, recall, ferry,
-- respawn) happened in between. Perch motes (agility > 0) also need the
-- HumanoidRootPart within PERCH_VERTICAL studs of the mote's height, so a
-- plain jump (JUMP_HEIGHT) from the ground below cannot reach them.
EX.SAMPLE_SECONDS = 1
EX.DWELL_SECONDS = 3
EX.SPEED_FACTOR = 3
EX.BASE_WALK = 16
EX.SPEED_SLACK = 12
EX.TRACK_REACH = 160     -- studs past an island's radius that still count as its region (far arenas)
EX.PERCH_VERTICAL = 1.5
EX.JUMP_HEIGHT = 7.2     -- Roblox default JumpHeight (studs)
EX.ROOT_HEIGHT = 3       -- HumanoidRootPart centre above the feet (studs)
-- Island -> region (matches each island's Region attribute; verified by tests).
EX.IsleRegion = {
	["Compass Quay"]="Hub", ["Warden Reach"]="Hub", ["Guild Terrace"]="Hub",
	["Mosswake Grove"]="Meadow", ["Meadow Reach"]="Meadow",
	["Brassfall Quarry"]="Quarry", ["Cinder Shelf"]="Quarry",
	["Skyreach"]="Skyreach", ["Windpine Grove"]="Windpine", ["Gloomhollow Caverns"]="Gloomhollow",
	["Tidewater Shoals"]="Tidewater", ["Tempest Spire"]="Tempest", ["The Shattered Crown"]="ShatteredCrown",
}
EX.RegionOrder = {"Hub","Meadow","Quarry","Skyreach","Windpine","Gloomhollow","Tidewater","Tempest","ShatteredCrown"}
-- The island each region's Mote Shrine stands on.
EX.ShrineIsle = {Hub="Compass Quay",Meadow="Mosswake Grove",Quarry="Brassfall Quarry",Skyreach="Skyreach",Windpine="Windpine Grove",
	Gloomhollow="Gloomhollow Caverns",Tidewater="Tidewater Shoals",Tempest="Tempest Spire",ShatteredCrown="The Shattered Crown"}
-- at = offset from the island's IslandCenter (studs, hovering ~2.4 above the
-- standing surface). agility = Agility level of the course whose perches hold
-- it (only reachable by running that course). Generated from the built world
-- and re-validated by verify-exploration.luau (supported, not embedded).
EX.Motes = {
	{id="Quay01",isle="Compass Quay",at={-66.8,12.3,-143.2},hint="High on the Quay Rigging Run perches",agility=1},
	{id="Quay02",isle="Compass Quay",at={-70.7,12.7,-98.3},hint="High on the Quay Rigging Run perches",agility=1},
	{id="Quay03",isle="Compass Quay",at={-62.3,6.3,66.4},hint="Behind the founder's statue on the rise"},
	{id="Quay04",isle="Compass Quay",at={-62.1,8.2,-74.5},hint="Beside the brass spyglass on the lookout"},
	{id="Quay05",isle="Compass Quay",at={11.4,2.2,-70.5},hint="Between the Museum's columns"},
	{id="Quay06",isle="Compass Quay",at={-67.9,6.4,42.4},hint="Warming by the furnace on the rise"},
	{id="Quay07",isle="Compass Quay",at={-32.3,2.3,-36.7},hint="Among the stones of the quay pond"},
	{id="Quay08",isle="Compass Quay",at={-41.2,6.4,62.8},hint="Up on the north terrace"},
	{id="Ward01",isle="Warden Reach",at={23.1,2.3,0.0},hint="At the foot of a ruined column"},
	{id="Ward02",isle="Warden Reach",at={-17.0,2.2,51.1},hint="Beneath a signal prism"},
	{id="Ward03",isle="Warden Reach",at={0.0,2.3,-53.2},hint="Under the old vault's lintel"},
	{id="Ward04",isle="Warden Reach",at={-24.5,2.2,2.3},hint="Tucked behind the west rocks"},
	{id="Ward05",isle="Warden Reach",at={-49.2,7.4,-7.4},hint="On the west bluff"},
	{id="Ward06",isle="Warden Reach",at={49.2,9.4,-7.4},hint="On the east bluff"},
	{id="Guild01",isle="Guild Terrace",at={-31.0,2.3,-37.0},hint="Behind the forge chimney"},
	{id="Guild02",isle="Guild Terrace",at={50.5,2.8,15.4},hint="Behind the Bestiary ledger"},
	{id="Guild03",isle="Guild Terrace",at={-59.9,2.4,33.3},hint="Under a terrace tree"},
	{id="Guild04",isle="Guild Terrace",at={-49.8,4.4,-32.5},hint="On the little terrace knoll"},
	{id="Moss01",isle="Mosswake Grove",at={22.5,13.8,-102.0},hint="High on the Mosswake Hedgerow Hop perches",agility=10},
	{id="Moss02",isle="Mosswake Grove",at={0.0,12.7,-115.0},hint="High on the Mosswake Hedgerow Hop perches",agility=10},
	{id="Moss03",isle="Mosswake Grove",at={-13.6,2.3,-23.1},hint="By the mossy pond stones"},
	{id="Moss04",isle="Mosswake Grove",at={-17.2,2.2,30.3},hint="Behind the grove rocks"},
	{id="Moss05",isle="Mosswake Grove",at={40.3,2.4,-45.1},hint="Under the old pine"},
	{id="Moss06",isle="Mosswake Grove",at={-41.8,5.4,27.1},hint="On the grove's high meadow"},
	{id="Moss07",isle="Mosswake Grove",at={-46.4,2.2,-49.4},hint="Near the rope-bridge sign"},
	{id="Mead01",isle="Meadow Reach",at={62.9,2.2,2.4},hint="Behind the eastern rocks"},
	{id="Mead02",isle="Meadow Reach",at={-62.7,2.2,-2.2},hint="Beneath the lone western tree"},
	{id="Mead03",isle="Meadow Reach",at={29.5,2.4,-7.4},hint="At the edge of the fishing pool"},
	{id="Mead04",isle="Meadow Reach",at={51.3,5.4,11.7},hint="On the east hill"},
	{id="Brass01",isle="Brassfall Quarry",at={0.0,14.9,117.0},hint="High on the Brassfall Scaffold Circuit perches",agility=20},
	{id="Brass02",isle="Brassfall Quarry",at={22.5,12.7,78.0},hint="High on the Brassfall Scaffold Circuit perches",agility=20},
	{id="Brass03",isle="Brassfall Quarry",at={49.2,2.3,-36.6},hint="Wedged by the quarry rocks"},
	{id="Brass04",isle="Brassfall Quarry",at={-62.1,2.3,26.6},hint="Under a quarry pine"},
	{id="Brass05",isle="Brassfall Quarry",at={-22.1,2.3,64.1},hint="Under the southern pine"},
	{id="Brass06",isle="Brassfall Quarry",at={17.5,7.4,-42.2},hint="On the quarry's upper shelf"},
	{id="Brass07",isle="Brassfall Quarry",at={35.1,12.4,-46.1},hint="On the quarry's highest ledge"},
	{id="Cinder01",isle="Cinder Shelf",at={44.9,2.2,-31.3},hint="Behind the cinder rocks"},
	{id="Cinder02",isle="Cinder Shelf",at={-3.8,8.4,115.0},hint="Where the bridge meets the shelf"},
	{id="Cinder03",isle="Cinder Shelf",at={33.8,6.4,-38.3},hint="On the scorched rise"},
	{id="Sky01",isle="Skyreach",at={-12.5,13.2,97.3},hint="High on the Skyreach Updraft Course perches",agility=40},
	{id="Sky02",isle="Skyreach",at={45.1,12.0,87.2},hint="High on the Skyreach Updraft Course perches",agility=40},
	{id="Sky03",isle="Skyreach",at={38.7,2.2,-0.9},hint="Behind the windswept rocks"},
	{id="Sky04",isle="Skyreach",at={-35.0,2.3,35.0},hint="Under a crag pine"},
	{id="Sky05",isle="Skyreach",at={-23.0,2.3,-46.0},hint="Under the far crag pine"},
	{id="Sky06",isle="Skyreach",at={26.2,8.4,-6.6},hint="On the summit plateau"},
	{id="Wind01",isle="Windpine Grove",at={57.7,11.7,-120.6},hint="High on the Windpine Canopy Loop perches",agility=30},
	{id="Wind02",isle="Windpine Grove",at={7.8,12.7,-90.1},hint="High on the Windpine Canopy Loop perches",agility=30},
	{id="Wind03",isle="Windpine Grove",at={5.0,2.2,40.0},hint="Along the fallen windpine"},
	{id="Wind04",isle="Windpine Grove",at={36.9,2.2,-46.3},hint="Under the emberoak boughs"},
	{id="Wind05",isle="Windpine Grove",at={47.0,2.2,44.7},hint="Beside the woodcutters' lodge"},
	{id="Wind06",isle="Windpine Grove",at={-11.5,2.4,52.9},hint="Beneath a windpine"},
	{id="Wind07",isle="Windpine Grove",at={35.7,4.9,0.0},hint="On the grove's mossy rise"},
	{id="Gloom01",isle="Gloomhollow Caverns",at={22.6,13.2,-127.6},hint="High on the Gloomhollow Chasm Run perches",agility=60},
	{id="Gloom02",isle="Gloomhollow Caverns",at={-32.0,14.2,-105.0},hint="High on the Gloomhollow Chasm Run perches",agility=60},
	{id="Gloom03",isle="Gloomhollow Caverns",at={0.0,2.3,-19.1},hint="Beside the grotto's heart crystal"},
	{id="Gloom04",isle="Gloomhollow Caverns",at={33.8,2.3,67.7},hint="Behind the cavern forge"},
	{id="Gloom05",isle="Gloomhollow Caverns",at={61.5,2.4,-8.1},hint="Against the eastern cavern wall"},
	{id="Gloom06",isle="Gloomhollow Caverns",at={-44.2,2.4,24.9},hint="By the dark pool"},
	{id="Gloom07",isle="Gloomhollow Caverns",at={53.5,5.4,42.8},hint="On the fungal ledge"},
	{id="Tide01",isle="Tidewater Shoals",at={11.5,11.6,140.2},hint="High on the Tidewater Mastwalk perches",agility=50},
	{id="Tide02",isle="Tidewater Shoals",at={49.6,13.4,112.8},hint="High on the Tidewater Mastwalk perches",agility=50},
	{id="Tide03",isle="Tidewater Shoals",at={-63.8,2.4,53.2},hint="At the lighthouse door"},
	{id="Tide04",isle="Tidewater Shoals",at={-52.8,2.2,19.0},hint="Under a glimmerbark tree"},
	{id="Tide05",isle="Tidewater Shoals",at={-33.3,2.2,46.6},hint="Beneath the beach palms"},
	{id="Tide06",isle="Tidewater Shoals",at={-42.7,2.2,-40.6},hint="Behind the tide rocks"},
	{id="Tide07",isle="Tidewater Shoals",at={-69.8,4.9,-45.1},hint="On the dune top"},
	{id="Storm01",isle="Tempest Spire",at={22.6,13.2,-115.6},hint="High on the Tempest Stormrun perches",agility=75},
	{id="Storm02",isle="Tempest Spire",at={-22.6,12.7,-70.4},hint="High on the Tempest Stormrun perches",agility=75},
	{id="Storm03",isle="Tempest Spire",at={27.5,2.4,27.5},hint="By a storm pylon"},
	{id="Storm04",isle="Tempest Spire",at={-47.0,2.4,23.5},hint="Under the starwood tree"},
	{id="Storm05",isle="Tempest Spire",at={58.9,2.2,-30.2},hint="Behind the stormbeaten rocks"},
	{id="Storm06",isle="Tempest Spire",at={47.1,5.4,-32.4},hint="On the thunder ledge"},
	{id="Crown01",isle="The Shattered Crown",at={-61.1,2.4,42.2},hint="Under a shatterbark tree"},
	{id="Crown02",isle="The Shattered Crown",at={-78.2,2.4,-12.2},hint="Beside a jutting crystal shard"},
	{id="Crown03",isle="The Shattered Crown",at={-163.7,2.4,-30.7},hint="At the roost obelisk"},
	{id="Crown04",isle="The Shattered Crown",at={194.0,2.4,15.6},hint="By a column of the eastern arena"},
	{id="Crown05",isle="The Shattered Crown",at={3.7,2.3,46.4},hint="By the crown's still pond"},
	{id="Crown06",isle="The Shattered Crown",at={0.0,6.4,-26.9},hint="On the crown's broken dais"},
}
EX.MoteById, EX.MotesByRegion, EX.RegionTotal = {}, {}, {}
for _, r in ipairs(EX.RegionOrder) do EX.MotesByRegion[r] = {}; EX.RegionTotal[r] = 0 end
for i, m in ipairs(EX.Motes) do
	m.index = i
	m.region = EX.IsleRegion[m.isle]
	m.agility = m.agility or 0
	EX.MoteById[m.id] = m
	table.insert(EX.MotesByRegion[m.region], m.id)
	EX.RegionTotal[m.region] += 1
end
EX.TOTAL = #EX.Motes
-- Milestones: every STEP motes found is one claimable step (claimed at any
-- Mote Shrine). Each claimed step adds +2 Health; every second step adds +1
-- Defense and +1 Speed. A region whose every mote is found pays a one-off
-- bonus at that region's own shrine (+2 Health and coins).
EX.STEP = 5
EX.STEPS = math.floor(EX.TOTAL / EX.STEP)
EX.REGION_HEALTH = 2
function EX.stepCoins(step) return 500 + 100 * step end
function EX.regionCoins(region) return 2500 + 250 * (EX.RegionTotal[region] or 0) end
-- Permanent stats for `steps` claimed milestone steps and `regions` completed
-- regions (stored by the server in p.perkStats.motes).
function EX.perkStats(steps, regions)
	steps = math.clamp(math.floor(tonumber(steps) or 0), 0, EX.STEPS)
	regions = math.clamp(math.floor(tonumber(regions) or 0), 0, #EX.RegionOrder)
	local out = {}
	local health = 2 * steps + EX.REGION_HEALTH * regions
	if health > 0 then out.health = health end
	local half = math.floor(steps / 2)
	if half > 0 then out.defense = half; out.speed = half end
	return out
end
-- Wayglass bearing (points at the nearest unfound mote of the island region
-- the player stands in): coins, rising gently with the motes already found.
function EX.hintCost(found) return 150 + 15 * math.clamp(math.floor(tonumber(found) or 0), 0, EX.TOTAL) end
-- The motes a journal may pick up: region access is checked by the server;
-- this checks the Agility gate.
function EX.canReach(mote, agilityLevel) return (tonumber(agilityLevel) or 1) >= (mote.agility or 0) end

------------------------------------------------------------------------------
-- Factions: three rival orders. Each faction distrusts the next (a cycle):
-- the Concord's rival is the Circle, the Circle's the Corsairs, the Corsairs'
-- the Concord. Pledging to one multiplies reputation and sigil gains:
-- pledged x1, the pledge's rival x0.25, the third faction x0.6; with no
-- pledge every faction earns x0.6. Shop rows above Kindred need the pledge.
------------------------------------------------------------------------------
local FA = {}
Data.Factions = FA
FA.Order = {"Concord","Circle","Corsairs"}
FA.Factions = {
	Concord={id="Concord",name="Emberwright Concord",short="Concord",color="D4A84B",rival="Circle",isle="Brassfall Quarry",
		regions={"Quarry","Skyreach","Gloomhollow"},lampSkills={"Mining","Smithing"},
		motto="Every seam a promise, every ingot a vow.",text="Smiths and delvers of Brassfall who would tunnel through every isle for its ore."},
	Circle={id="Circle",name="Thornveil Circle",short="Circle",color="8DB86E",rival="Corsairs",isle="Mosswake Grove",
		regions={"Meadow","Windpine"},lampSkills={"Woodcutting","Farming","Hunter"},
		motto="Root, branch and the long patience of seeds.",text="Grove-keepers of Mosswake who tend the meadows and windpines against the Concord's picks."},
	Corsairs={id="Corsairs",name="Galewake Corsairs",short="Corsairs",color="5EC8D8",rival="Concord",isle="Compass Quay",
		regions={"Hub","Tidewater","Tempest"},lampSkills={"Fishing","Agility","Combat"},
		motto="The wind owes no tariff.",text="Sky-sailors of the quay who run the trade lanes, and the Circle's skies, on their own terms."},
}
FA.Ranks = {
	{id="Outsider",name="Outsider",at=0},
	{id="Kindred",name="Kindred",at=500},
	{id="Sworn",name="Sworn",at=2000},
	{id="Vanguard",name="Vanguard",at=5000},
	{id="Luminary",name="Luminary",at=10000},
}
FA.REP_CAP = 25000
FA.SIGIL_CAP = 5000
FA.MULT = {pledged=1, rival=0.25, neutral=0.6, none=0.6}
FA.OPEN_RANK = 2 -- shop rows up to this rank need no pledge (Kindred)
FA.SWITCH_COST = 25000 -- coins to change an existing pledge
FA.SWITCH_COOLDOWN = 7 * 86400 -- seconds after a pledge before it may change
FA.SWITCH_FORFEIT = 0.25 -- share of the old faction's reputation lost on a switch
FA.TASKS = 3 -- daily tasks per faction (slot 1 kill, 2 gather, 3 deliver; a kind with no eligible task falls back to any)
FA.DAY = 86400
function FA.dayOf(t) return math.floor((tonumber(t) or 0) / FA.DAY) end
function FA.resetIn(t) t = tonumber(t) or 0; return (FA.dayOf(t) + 1) * FA.DAY - math.floor(t) end
function FA.rankOf(rep)
	rep = tonumber(rep) or 0
	local index = 1
	for i, r in ipairs(FA.Ranks) do if rep >= r.at then index = i end end
	return index, FA.Ranks[index], FA.Ranks[index + 1]
end
-- Gain multiplier for faction `id` under pledge `pledge` ("" = none).
function FA.mult(id, pledge)
	if type(pledge) ~= "string" or not FA.Factions[pledge] then return FA.MULT.none end
	if pledge == id then return FA.MULT.pledged end
	if FA.Factions[pledge].rival == id then return FA.MULT.rival end
	return FA.MULT.neutral
end
-- Task pool (per faction). kind: kill (monster id), gather (resource id),
-- deliver (hand in items from the satchel). levels/region gate eligibility.
FA.Tasks, FA.TaskById = {}, {}
local function ftask(faction, def)
	def.faction = faction
	def.id = faction .. def.kind:sub(1,1):upper() .. def.kind:sub(2) .. def.target
	def.levels = def.levels or {}
	if def.kind == "kill" then def.rep, def.sigils = 120, 12
	elseif def.kind == "gather" then def.rep, def.sigils = 100, 10
	else def.rep, def.sigils = 150, 15 end
	table.insert(FA.Tasks, def)
	FA.TaskById[def.id] = def
end
local function resourceDef(id)
	for skill, list in pairs(Data.ResourceTiers) do
		for _, r in ipairs(list) do if r.id == id then return r, skill end end
	end
	return nil
end
local function kill(faction, monster, amount)
	local m = rawget(Data.Monsters, monster)
	if not m then return end
	-- Bonus pay on top of the kills themselves: 40% of their XP and coins
	-- (commissions pay 60% / 50%; nine faction tasks a day versus four).
	ftask(faction, {kind="kill",target=monster,amount=amount,skill="Combat",xp=math.floor(m.xp * amount * 0.4),coins=math.floor(m.coins * amount * 0.4),
		levels={Combat=math.max(1, m.level - 6)},region=m.region})
end
local function gather(faction, id, amount, region)
	local r, skill = resourceDef(id)
	if not r then return end
	ftask(faction, {kind="gather",target=id,amount=amount,skill=skill,xp=r.xp * 4,coins=10 + r.level * 2,levels={[skill]=r.level},region=region})
end
local function deliver(faction, id, amount, levels, region)
	local def = Data.Items[id]
	if not def then return end
	-- Coins: 1.3x the merchant value of the items handed in (they are consumed).
	ftask(faction, {kind="deliver",target=id,amount=amount,coins=math.ceil((def.value or 1) * amount * 1.3),levels=levels or {},region=region})
end
-- Emberwright Concord: the quarry, Skyreach and the caverns.
kill("Concord","ShaleCrawler",12); kill("Concord","CinderMite",12); kill("Concord","BrassGolem",6); kill("Concord","StormHarrier",6)
kill("Concord","GloomfangSpider",8); kill("Concord","VoidWisp",6); kill("Concord","HollowcapShrieker",6)
gather("Concord","Ore",25); gather("Concord","Aetherite",22); gather("Concord","Brassite",18); gather("Concord","SunsteelOre",15,"Skyreach")
gather("Concord","Voidstone",12,"Gloomhollow"); gather("Concord","StarmetalOre",10,"Tempest")
deliver("Concord","Ore",30); deliver("Concord","AlloyIngot",4,{Smithing=1}); deliver("Concord","BrassIngot",4,{Smithing=15}); deliver("Concord","SunsteelIngot",3,{Smithing=30})
deliver("Concord","GolemCore",1,{Combat=22},"Skyreach")
-- Thornveil Circle: the meadows and Windpine.
kill("Circle","BramblebackBoar",15); kill("Circle","Thornling",12); kill("Circle","BarkStalker",8); kill("Circle","GaleSprite",8)
gather("Circle","Timber",25); gather("Circle","Herb",25); gather("Circle","WindpineLog",18); gather("Circle","Sunwheat",18)
gather("Circle","EmberoakLog",14,"Windpine"); gather("Circle","Glowcap",14,"Windpine"); gather("Circle","Moonbloom",10,"Gloomhollow")
deliver("Circle","Herb",30); deliver("Circle","Timber",30); deliver("Circle","BeastHide",8); deliver("Circle","WindpineLog",15,{Woodcutting=15})
deliver("Circle","Tonic",3,{Alchemy=1})
-- Galewake Corsairs: the quay, Tidewater and the Tempest.
kill("Corsairs","StormHarrier",6); kill("Corsairs","ReefLurker",8); kill("Corsairs","MirrorscaleBasilisk",5); kill("Corsairs","TempestWraith",4)
kill("Corsairs","ThundercragGargant",3); kill("Corsairs","StarbornSentinel",3)
gather("Corsairs","Fish",25); gather("Corsairs","Glassfin",20); gather("Corsairs","Stormeel",14,"Tidewater"); gather("Corsairs","Lanternray",10,"Tidewater")
gather("Corsairs","AbyssKoi",8,"Tidewater")
deliver("Corsairs","Fish",30); deliver("Corsairs","CookedFish",8,{Cooking=1}); deliver("Corsairs","Glassfin",15,{Fishing=15}); deliver("Corsairs","StormFeather",6,{Combat=18},"Windpine")
deliver("Corsairs","Stormeel",10,{Fishing=30},"Tidewater")
-- ctx = {levels={[skill]=level}, regions={[regionId]=true}} (gated regions only matter).
function FA.eligible(t, ctx)
	ctx = ctx or {}
	local levels = ctx.levels or {}
	for skill, lvl in pairs(t.levels or {}) do if (levels[skill] or 1) < lvl then return false end end
	if t.region then
		local r = Data.RegionById[t.region]
		if r and r.requires and next(r.requires) and not (ctx.regions and ctx.regions[t.region]) then return false end
	end
	return true
end
-- Deterministic board for one faction (day + salt + context): FA.TASKS ids.
local function stream(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483646 + 1
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end
FA.KindOrder = {"kill","gather","deliver"}
function FA.draw(faction, day, salt, ctx)
	local fi = table.find(FA.Order, faction) or 1
	local rng = stream((tonumber(day) or 0) * 6007 + (tonumber(salt) or 0) * 7727 + fi * 911 + 17)
	local byKind, all = {kill={},gather={},deliver={}}, {}
	for _, t in ipairs(FA.Tasks) do
		if t.faction == faction and FA.eligible(t, ctx) then table.insert(byKind[t.kind], t.id); table.insert(all, t.id) end
	end
	local out, used = {}, {}
	for _, kind in ipairs(FA.KindOrder) do
		local pool = byKind[kind]
		local left = {}
		for _, id in ipairs(pool) do if not used[id] then table.insert(left, id) end end
		if #left == 0 then
			for _, id in ipairs(all) do if not used[id] then table.insert(left, id) end end
		end
		if #left > 0 then
			local id = left[1 + math.floor(rng() * #left)]
			table.insert(out, id); used[id] = true
		end
	end
	return out
end
-- Reward for a task under the current pledge: rep and sigils scale with the
-- pledge multiplier; coins and XP do not (the work is the same).
function FA.reward(t, pledge)
	local m = FA.mult(t.faction, pledge)
	return {rep=math.floor(t.rep * m),sigils=math.max(1, math.floor(t.sigils * m)),coins=t.coins or 0,xp=t.xp or 0,skill=t.skill}
end
-- Shop: rank = index into FA.Ranks. kind: title (cosmetic), lamp (XP in one
-- of the faction's lampSkills, repeatable), charm (accessory), crest (accessory
-- upgrade: consumes the faction's charm).
FA.LAMP_HOURS = 0.4 -- one lamp = this many hours of level-appropriate solo XP (Minigames model)
FA.Shop, FA.ShopById = {}, {}
local function shop(faction, def)
	def.faction = faction
	table.insert(FA.Shop, def)
	FA.ShopById[def.id] = def
end
local function accessory(id, name, rarity, stats, text, faction)
	local r = Data.Rarity[rarity]
	-- logUnique: Collection Log › Factions (credited through collect()).
	Data.Items[id] = {id=id,name=name,kind="accessory",rarity=rarity,color=r.color,stats=stats,value=40 * r.rank ^ 2,faction=faction,logUnique="Factions",
		description="Accessory. Magical Power " .. r.power .. ". " .. text}
end
accessory("EmberwrightCharm","Emberwright Charm","Rare",{miningSpeed=20,defense=8},"Sworn of the Emberwright Concord.","Concord")
accessory("EmberwrightCrest","Emberwright Crest","Epic",{miningSpeed=40,defense=15,strength=4},"Luminary of the Emberwright Concord (replaces the Charm).","Concord")
accessory("ThornveilCharm","Thornveil Charm","Rare",{health=25,speed=3},"Sworn of the Thornveil Circle.","Circle")
accessory("ThornveilCrest","Thornveil Crest","Epic",{health=50,speed=6,defense=6},"Luminary of the Thornveil Circle (replaces the Charm).","Circle")
accessory("GalewakeCharm","Galewake Charm","Rare",{critDamage=8,speed=3},"Sworn of the Galewake Corsairs.","Corsairs")
accessory("GalewakeCrest","Galewake Crest","Epic",{critDamage=15,speed=5,critChance=3},"Luminary of the Galewake Corsairs (replaces the Charm).","Corsairs")
for _, f in ipairs({{"Concord","Emberwright","Concord Journeyman","Forgewarden"},{"Circle","Thornveil","Circle Seedkeeper","Grovewarden"},{"Corsairs","Galewake","Corsair Deckhand","Stormcaptain"}}) do
	local id = f[1]
	shop(id, {id=id.."Title1",kind="title",title=f[3],rank=2,sigils=40,coins=0})
	shop(id, {id=id.."Lamp",kind="lamp",rank=3,sigils=100,coins=0})
	shop(id, {id=id.."Charm",kind="charm",item=f[2].."Charm",rank=3,sigils=150,coins=10000})
	shop(id, {id=id.."Title2",kind="title",title=f[4],rank=4,sigils=250,coins=0})
	shop(id, {id=id.."Crest",kind="crest",item=f[2].."Crest",consumes=f[2].."Charm",rank=5,sigils=400,coins=50000})
end
function FA.lampXp(skill, level)
	local MG = Data.Minigames
	if not (MG and MG.soloCombatXpPerHour) then return 0 end
	return math.floor(FA.LAMP_HOURS * MG.soloCombatXpPerHour(math.clamp(tonumber(level) or 1, 1, 99)) + 0.5)
end
-- Purchase check (pure). rec = p.factions; returns entry or nil, reason.
function FA.canBuy(id, rec, coins, skill, levels)
	local e = FA.ShopById[id]
	if not e then return nil, "Choose a faction reward." end
	rec = type(rec) == "table" and rec or {}
	local f = FA.Factions[e.faction]
	local rank = FA.rankOf((rec.rep or {})[e.faction])
	if rank < e.rank then return nil, "Needs " .. FA.Ranks[e.rank].name .. " standing with the " .. f.name .. "." end
	if e.rank > FA.OPEN_RANK and rec.pledge ~= e.faction then return nil, "Pledge to the " .. f.name .. " to buy " .. FA.Ranks[e.rank].name .. " rewards." end
	if e.kind == "title" and type(rec.unlocks) == "table" and rec.unlocks[id] then return nil, "You already hold this title." end
	if e.kind == "lamp" then
		if not (type(skill) == "string" and table.find(f.lampSkills, skill)) then return nil, "Choose a skill this lamp can train: " .. table.concat(f.lampSkills, ", ") .. "." end
	end
	if ((rec.sigils or {})[e.faction] or 0) < e.sigils then return nil, "Needs " .. e.sigils .. " " .. f.short .. " sigils." end
	if (tonumber(coins) or 0) < (e.coins or 0) then return nil, "Needs " .. e.coins .. " coins." end
	return e
end
-- Balance model (verify-exploration.luau prints and bounds it). Minutes of
-- play per task: kills at MG.SOLO.killsPerHour, harvests at respawn + the
-- gather overhead, deliveries 1 minute; plus TRAVEL seconds per task.
FA.MODEL_TRAVEL = 60
-- One kill or harvest advances every board holding a task for it (the Storm
-- Harrier is on both the Concord's and the Corsairs' pools; there is no
-- deduplication), so the model splits a task's work between the factions
-- sharing its kind and target (worst case: both drawn on the same day).
function FA.sharers(t)
	if t.kind == "deliver" then return 1 end
	local n = 0
	for _, o in ipairs(FA.Tasks) do if o.kind == t.kind and o.target == t.target then n += 1 end end
	return math.max(1, n)
end
function FA.taskSeconds(t)
	local MG = Data.Minigames
	local travel = FA.MODEL_TRAVEL
	if t.kind == "kill" then return travel + t.amount * 3600 / MG.SOLO.killsPerHour / FA.sharers(t) end
	if t.kind == "gather" then
		local r = resourceDef(t.target)
		return travel + t.amount * ((r and r.respawn or 3) + MG.SOLO.gatherOverhead) / FA.sharers(t)
	end
	return travel
end
-- Collection Log › Factions: the three Charms and three Crests (the items
-- carry logUnique = "Factions"; CommissionsLogs.log() files them here).
local CLog = Data.CommissionsLogs
if CLog and CLog.LogTabs and not CLog.LogTabs.Factions then
	CLog.LogTabs.Factions = {name="Factions",title="Oathbound",coins=30000,color="D4A84B"}
	table.insert(CLog.LogTabOrder, table.find(CLog.LogTabOrder, "Curios") or #CLog.LogTabOrder + 1, "Factions")
end
end
-- Permanent-stat budget (docs/DEPTH-CONTRACT.md §24): the summed maximum of
-- every p.perkStats source (motes, Museum, commission milestones, Forgeheart,
-- Agility laps, the Hunter log, Garden milestones, the crew perk, quests,
-- diaries and the best furniture per hotspot) stays within these totals.
-- Faction rewards are accessories (one active per faction family), not
-- perkStats. verify-exploration.luau sums the sources and asserts the budget.
Data.PerkBudget = {health=300, defense=125}
-- <<< END Exploration & Factions <<<

------------------------------------------------------------------------------
-- >>> BEGIN Dungeon endgame (Dungeon Depth team; append-only section) >>>
-- Observatory endgame on top of Floors I-VII and the Dungeon classes section:
--   * Floors VI-VII: cumulative room puzzles (VI Mirror Gallery; VII adds the
--     Star Chart), multi-phase bosses whose telegraphed mechanics each check a
--     class role (Reliquary Verdict = tank, Withering Lumen = healer, Eventide
--     Nova = damage/interrupt, Constellation Lock = puzzle/Arcanist), and a
--     gear-score gate (EG.gearScore: rarity + item level + upgrades of the five
--     worn slots) on top of the Dungeoneering level.
--   * Master Mode I-VII (DC.MASTER_FLOORS = 7, DC.masterScale per floor,
--     unlocked by a normal clear at grade S): +5 Bonus score cap, x3 essence,
--     +30% mechanic damage and Master-only chest rows (EG.MasterChest).
--   * Essence: Observatory Essence buys Master stars (✪ 1-5) for dungeon gear
--     with five regular stars (Gear.Layers hook, EG.masterStarCost) and Lodestar
--     Keys at the Essence Exchange (EG.Exchange).
--   * Chest economy: every credited clear rolls a pay-to-open bonus chest once
--     (EG.bonusPlan); the contents are fixed and saved in the journal at the
--     clear (no reroll by rejoining or leaving), opened for coins or a Lodestar
--     Key within EG.CHEST_SECONDS, or skipped. One run id is credited once.
--   * Credit (Minigames-style): contribution >= max(10% of the party,
--     EG.MEDIAN_SHARE x the median member) and a credited action in the last
--     EG.RECENT_SECONDS; delvers who drop may rejoin within EG.REJOIN_SECONDS.
--   * Run log (last EG.LOG_LIMIT clears), weekly bests and a weekly first-clear
--     essence bounty per floor and mode, all-time personal bests.
-- Pure data + pure rules: expedition.server.lua runs rooms and phases,
-- server.server.lua (Endgame block) persists p.dungeonEndgame and the Master
-- stars (p.masterStars), ui.client.lua draws Hunt > Dungeon and Hunt > Essence;
-- verify-dungeon-master.luau checks everything here.
--   p.dungeonEndgame = {log={{t,f,m,g,s,sec,d}}, week={id, best={[key]=score},
--     bounty={[key]=true}}, pb={[key]={score,seconds}}, chest={...}|nil, runs={runId,...}}
--   key = "<floor>" or "<floor>m" (Master Mode)
------------------------------------------------------------------------------
do
local EG = {}
Data.DungeonEndgame = EG
local DC = Data.DungeonClasses
local Gear = Data.Gear
local floors = Data.DungeonFloors

-- Items ---------------------------------------------------------------------
item("LodestarKey",{name="Lodestar Key",kind="material",rarity="Rare",color="E9C46A",value=300,
	description="Opens an Observatory bonus chest without its coin fee. Observatory chests (Floor IV+) or the Essence Exchange."})
item("EclipsedStarcore",{name="Eclipsed Starcore",kind="material",rarity="Epic",color="7A5BC4",value=2500,masterOnly=true,
	description="Master Mode only. A star that burned out inside the Observatory; forges Master stars (✪) onto dungeon gear."})
Data.Sets.Duskwarden = {id="Duskwarden",name="Duskwarden Regalia",pieces={},bonus={strength=40,critDamage=40,health=150},
	text="+40 Strength, +40 Crit Damage, +150 Health",color="5B6FA8"}
local duskwarden = {
	{id="DuskwardenCowl",slot="helmet",name="Duskwarden Cowl",level=40,stats={defense=80,health=70,strength=15,critDamage=10}},
	{id="DuskwardenHauberk",slot="chest",name="Duskwarden Hauberk",level=45,stats={defense=150,health=130,strength=25,critDamage=15}},
	{id="DuskwardenTassets",slot="legs",name="Duskwarden Tassets",level=45,stats={defense=125,health=105,strength=20,critDamage=12}},
	{id="DuskwardenSabatons",slot="boots",name="Duskwarden Sabatons",level=40,stats={defense=70,health=60,speed=8}},
}
for _, a in ipairs(duskwarden) do
	item(a.id,{name=a.name,kind="armor",slot=a.slot,set="Duskwarden",rarity="Legendary",color="5B6FA8",stats=a.stats,dungeon=true,
		requires={Combat=a.level,Dungeoneering=a.level},value=6000+a.level*100,
		description="Observatory Floor VI-VII chest drop. Part of the Duskwarden Regalia set. Requires Dungeoneering "..a.level.."."})
	table.insert(Data.Sets.Duskwarden.pieces, a.id)
end
item("ColossusLumenbrand",{name="Colossus Lumenbrand",kind="weapon",slot="weapon",rarity="Legendary",color="F2E3A0",dungeon=true,
	stats={damage=245,strength=100,critChance=8,critDamage=75,intelligence=30},requires={Combat=40,Dungeoneering=40},value=15000,
	description="Observatory Floor VI+ chest drop: a shard of the Lumen Colossus. Requires Dungeoneering 40."})
item("SovereignNightfall",{name="Sovereign's Nightfall",kind="weapon",slot="weapon",rarity="Legendary",color="3E3570",dungeon=true,
	stats={damage=290,strength=125,critChance=10,critDamage=84},requires={Combat=45,Dungeoneering=50},value=22000,
	description="Observatory Floor VII chest drop: the Hollow Sovereign's blade. Requires Dungeoneering 50."})
item("Thronebreaker",{name="Thronebreaker",kind="weapon",slot="weapon",tier=9,rarity="Mythic",color="C77DFF",dungeon=true,masterOnly=true,
	stats={damage=320,strength=145,critChance=12,critDamage=92},requires={Combat=50,Dungeoneering=50},value=40000,
	description="Master Mode only: Master Floor VI-VII chests. An endgame (tier 9) drop-only unique. Requires Dungeoneering 50."})
item("SovereignHalo",{name="Sovereign Halo",kind="accessory",rarity="Mythic",color=Data.Rarity.Mythic.color,dungeon=true,masterOnly=true,
	stats={strength=20,critDamage=20,intelligence=20,magicFind=4},value=40*Data.Rarity.Mythic.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Mythic.power..". Master Mode only: Master Floor V-VII chests."})
-- Normal chests: Floors VI-VII uniques and keys from Floor IV.
local function drop(list, id, chance, min, max) table.insert(list, {item=id,chance=chance,min=min or 1,max=max or 1}) end
drop(floors[4].chest, "LodestarKey", 0.02)
drop(floors[5].chest, "LodestarKey", 0.03)
drop(floors[6].chest, "LodestarKey", 0.04)
drop(floors[6].chest, "DuskwardenCowl", 0.012)
drop(floors[6].chest, "DuskwardenSabatons", 0.012)
drop(floors[6].chest, "ColossusLumenbrand", 0.005)
drop(floors[7].chest, "LodestarKey", 0.05)
drop(floors[7].chest, "DuskwardenCowl", 0.015)
drop(floors[7].chest, "DuskwardenSabatons", 0.015)
drop(floors[7].chest, "DuskwardenHauberk", 0.01)
drop(floors[7].chest, "DuskwardenTassets", 0.01)
drop(floors[7].chest, "ColossusLumenbrand", 0.006)
drop(floors[7].chest, "SovereignNightfall", 0.004)
-- Master-only rows, appended to the floor's chest on Master clears (DC.runRewards).
EG.MasterChest = {}
for f = 1, #floors do
	local list = {}
	drop(list, "EclipsedStarcore", 0.16 * 0.7 ^ (7 - f)) -- deeper floors are the best Starcore source per hour
	drop(list, "LodestarKey", 0.04 + 0.01 * (f - 1))
	if f >= 5 then drop(list, "SovereignHalo", ({[5]=0.003,[6]=0.005,[7]=0.008})[f]) end
	if f >= 6 then drop(list, "Thronebreaker", ({[6]=0.002,[7]=0.004})[f]) end
	EG.MasterChest[f] = list
end
EG.MASTER_ESSENCE = 3 -- Master clears: essence x3 (after grade and secrets)

-- Gear score ------------------------------------------------------------------
-- Per worn item (weapon + four armor slots): rarity points (effective rarity)
-- + its highest skill requirement + 8 per star + 12 per Master star
-- + 2 per Tempering Tome + 5 for a reforge. Style-agnostic: melee, ranged and
-- magic gear of the same tier score alike.
EG.RarityScore = {Common=10,Uncommon=20,Rare=35,Epic=55,Legendary=80,Mythic=110}
EG.GEAR_SLOTS = {"weapon","helmet","chest","legs","boots"}
EG.STAR_SCORE, EG.MASTER_STAR_SCORE, EG.TOME_SCORE, EG.REFORGE_SCORE = 8, 12, 2, 5
-- gearGate[floor] = {normal, master} minimum gear score.
EG.GearGate = {{0,0},{0,0},{0,0},{0,100},{0,180},{300,380},{420,500}}
function EG.gearGate(floorIndex, master)
	local g = EG.GearGate[tonumber(floorIndex) or 0]
	if not g then return 0 end
	return if master == true then g[2] else g[1]
end
function EG.itemScore(g, itemId)
	local def = Data.Items[itemId]
	if type(def) ~= "table" then return 0 end
	local req = 0
	for _, lvl in pairs(type(def.requires) == "table" and def.requires or {}) do req = math.max(req, tonumber(lvl) or 0) end
	local b = Gear.breakdown(g, itemId)
	return (EG.RarityScore[b.rarity] or 10) + req + EG.STAR_SCORE * b.stars + EG.MASTER_STAR_SCORE * (b.masterStars or 0)
		+ EG.TOME_SCORE * b.tempering + (if b.reforge then EG.REFORGE_SCORE else 0)
end
-- p = {equipment={[slot]=itemId}, items={[id]=n}, reforges, stars, books, masterStars}.
-- Items not owned (count < 1) or in the wrong slot score 0.
function EG.gearScore(p)
	if type(p) ~= "table" or type(p.equipment) ~= "table" then return 0 end
	local items = type(p.items) == "table" and p.items or nil
	local total = 0
	for _, slot in ipairs(EG.GEAR_SLOTS) do
		local id = p.equipment[slot]
		local def = type(id) == "string" and Data.Items[id]
		if def and def.slot == slot and (items == nil or (tonumber(items[id]) or 0) >= 1) then total += EG.itemScore(p, id) end
	end
	return total
end
-- Floor gate for a delver: ok, reason ("level" | "gear" | "master").
function EG.floorAccess(floorIndex, master, level, gearScore, bestScore)
	local f = floors[tonumber(floorIndex) or 0]
	if not f then return false, "floor" end
	if (tonumber(level) or 1) < f.level then return false, "level" end
	if master == true and not DC.masterUnlocked(f.index, bestScore) then return false, "master" end
	if (tonumber(gearScore) or 0) < EG.gearGate(f.index, master) then return false, "gear" end
	return true
end
function EG.accessText(floorIndex, master, reason)
	local f = floors[tonumber(floorIndex) or 1] or floors[1]
	if reason == "level" then return f.name .. " requires Dungeoneering " .. f.level .. "." end
	if reason == "master" then return "Master Mode " .. f.name .. " unlocks after a grade " .. DC.MASTER_UNLOCK_GRADE .. " (or better) clear of the floor." end
	if reason == "gear" then return (if master then "Master Mode " else "") .. f.name .. " needs gear score " .. EG.gearGate(f.index, master) .. " (weapon + armor: rarity, item level, stars and tomes)." end
	return "Unknown floor."
end

-- Master stars (✪) -----------------------------------------------------------
-- Dungeon gear (def.dungeon, not accessories) with five regular stars takes up
-- to five Master stars, each +EG.MASTER_STAR_PERCENT% of the base stats: five
-- regular stars (4% each) + five Master stars (2% each) cap dungeon gear at +30%,
-- so a fully upgraded dungeon piece stays below the 5-star crafted endgame item
-- of the next higher Combat requirement (EG.CraftedRivals, verify-dungeon-master).
-- Costs are tuned so one full set takes about 10 hours of Master VII (essence and
-- Eclipsed Starcores, both counting the bonus chest; EG.model).
EG.MASTER_STAR_MAX = 5
EG.MASTER_STAR_PERCENT = 2
EG.MasterStarEssence = {240,380,560,750,1000} -- x (1 + 0.25 x (rarity rank - 1))
EG.MasterStarCores = {2,3,4,6,8}             -- Eclipsed Starcores
EG.MasterStarCoins = 5000                    -- x k^2
function EG.canMasterStar(def)
	return type(def) == "table" and def.dungeon == true and Gear.canStar(Gear.category(def))
end
function EG.masterStarsOf(g, itemId)
	if not EG.canMasterStar(Data.Items[itemId]) then return 0 end
	local t = type(g) == "table" and type(g.masterStars) == "table" and g.masterStars or nil
	local n = t and tonumber(t[itemId]) or 0
	if n ~= n then return 0 end
	return math.clamp(math.floor(n), 0, EG.MASTER_STAR_MAX)
end
function EG.masterStarCost(def, k)
	if not EG.canMasterStar(def) or not EG.MasterStarEssence[k] then return nil end
	local rank = Data.Rarity[def.rarity] and Data.Rarity[def.rarity].rank or 1
	return {essence="ObservatoryEssence",amount=math.floor(EG.MasterStarEssence[k] * (1 + 0.25 * (rank - 1))),
		cores=EG.MasterStarCores[k],coins=EG.MasterStarCoins * k * k}
end
-- Can star k+1 be bought? g = profile-like table. Returns ok, reason.
function EG.masterStarCheck(g, itemId)
	local def = Data.Items[itemId]
	if not EG.canMasterStar(def) then return false, "Only Observatory weapons and armor take Master stars." end
	if Gear.starsOf(g, itemId) < Gear.STAR_MAX then return false, def.name .. " needs " .. Gear.STAR_MAX .. " regular stars first." end
	local k = EG.masterStarsOf(g, itemId)
	if k >= EG.MASTER_STAR_MAX then return false, def.name .. " already has " .. EG.MASTER_STAR_MAX .. " Master stars." end
	return true
end
-- Gear.Layers hook: Master stars add to Gear.breakdown (and so to
-- Progression.upgradeStats / computeStats, which call Gear.breakdown).
table.insert(Gear.Layers, {id="masterStars",glyph="✪",stats=function(g, itemId, def)
	local n = EG.masterStarsOf(g, itemId)
	if n <= 0 then return 0, {} end
	local pct = EG.MASTER_STAR_PERCENT * n / 100
	local out = {}
	for stat, v in pairs(def.stats or {}) do
		local bonus = math.floor(v * pct * 10 + 0.5) / 10
		if bonus ~= 0 then out[stat] = bonus end
	end
	return n, out
end})

-- Crafted rivals: each endgame dungeon weapon/armor (fully upgraded: 5★ + 5✪) must
-- stay below the 5-star crafted Crown item of the next higher Combat requirement
-- (armor compared as the full set with both set bonuses). Checked by verify-dungeon-master.
EG.CraftedRivals = {
	Thronebreaker="Crownbreaker",SovereignNightfall="SovereignGreatblade",ColossusLumenbrand="SovereignGreatblade",
	DuskwardenCowl="SovereignHelm",DuskwardenHauberk="SovereignChestplate",DuskwardenTassets="SovereignGreaves",DuskwardenSabatons="SovereignBoots",
}

-- Essence Exchange --------------------------------------------------------------
EG.Exchange = {
	{id="LodestarKey",essence=60,coins=0,text="A key for one bonus chest."},
}
EG.ExchangeById = {}
for _, e in ipairs(EG.Exchange) do EG.ExchangeById[e.id] = e end

-- Rooms (cumulative) ---------------------------------------------------------------
-- Mirror Gallery (VI+): four mirrors; the beam reaches mirror i+1 only when
-- mirrors 1..i face their targets. Turning a lit mirror breaks the beam and is
-- a puzzle mistake. Star Chart (VII): press the glyph plates in the order on
-- the lectern; a wrong plate is a mistake and restarts the chart.
EG.Rooms = {[6]={"mirrors"},[7]={"mirrors","chart"}}
floors[6].mechanics.rooms = EG.Rooms[6]
floors[7].mechanics.rooms = EG.Rooms[7]
EG.RoomNames = {mirrors="Mirror Gallery",chart="Star Chart"}
function EG.roomsFor(floorIndex) return EG.Rooms[tonumber(floorIndex) or 0] or {} end
-- Stage after `stage` on a floor: prisms -> rooms... -> guardians.
function EG.nextStage(floorIndex, stage)
	local rooms = EG.roomsFor(floorIndex)
	if stage == "prisms" then return rooms[1] or "guardians" end
	local i = table.find(rooms, stage)
	if i then return rooms[i + 1] or "guardians" end
	return "guardians"
end
EG.MIRRORS = 4
function EG.mirrorTargets(seed)
	seed = math.floor(tonumber(seed) or 0)
	local out = {}
	for i = 1, EG.MIRRORS do out[i] = (seed * 7 + i * 3 + seed // 3) % 4 end
	return out
end
-- Starting facings: never already on target (each mirror needs 1-3 turns).
function EG.mirrorStart(seed)
	seed = math.floor(tonumber(seed) or 0)
	local t, out = EG.mirrorTargets(seed), {}
	for i = 1, EG.MIRRORS do out[i] = (t[i] + 1 + (seed + i) % 3) % 4 end
	return out
end
function EG.beamReach(states, targets)
	local n = 0
	for i = 1, EG.MIRRORS do
		if states[i] ~= targets[i] then break end
		n = i
	end
	return n
end
-- Turn mirror i a quarter: returns the new facing and whether it was a mistake.
function EG.turnMirror(states, targets, i)
	local mistake = i <= EG.beamReach(states, targets)
	states[i] = (states[i] + 1) % 4
	return states[i], mistake
end
EG.CHART_PLATES = 6
EG.Glyphs = {{id="Lantern",glyph="☼"},{id="Crescent",glyph="☾"},{id="Comet",glyph="☄"},{id="Spindle",glyph="✶"},{id="Crown",glyph="♛"},{id="Tide",glyph="≈"}}
function EG.chartLength(master) return if master == true then 5 else 4 end
-- Deterministic per seed (Park-Miller steps); never the same plate twice in a row.
function EG.chartSequence(seed, length)
	local state = (math.floor(math.abs(tonumber(seed) or 0)) * 48271 + 11) % 2147483647
	local out, prev = {}, 0
	for i = 1, length do
		state = (state * 16807) % 2147483647
		local v = ((state // 4096) % EG.CHART_PLATES) + 1
		if v == prev then v = (v % EG.CHART_PLATES) + 1 end
		out[i], prev = v, v
	end
	return out
end
function EG.chartText(seq)
	local parts = {}
	for _, v in ipairs(seq) do table.insert(parts, EG.Glyphs[v].glyph) end
	return table.concat(parts, " ")
end

-- Boss phases and role mechanics (Floors VI-VII) ------------------------------
-- Phase = the highest-index phase whose `below` >= the core's HP fraction.
-- Mechanics (damage as a fraction of max health; Master x(1 + MASTER_MECH)):
--   verdict (Tank)   channel, then one heavy blow on the Aegis with the most
--                    damage (taunt) or, with no living Aegis, the top damage dealer
--   blight  (Healer) every delver withers each `tick` for `duration`; Mending
--                    Light or Second Dawn cleanses it at once
--   nova    (Damage) channel; dealing breakShare of the core's max HP during it,
--                    or a Starshot Disrupting Shot, breaks it; else it strikes
--                    everyone and counts as a puzzle mistake
--   lock    (Puzzle) the final phase seals the core until the Star Chart is
--                    replayed (Arcanist Attune presses the next plate)
EG.MASTER_MECH = 0.3
EG.Mechanics = {
	verdict={name="Reliquary Verdict",role="Tank",channel=3,damage=0.45,glyph="⛨",
		text="Channel, then a heavy blow on the Aegis (taunt) or the top damage dealer."},
	blight={name="Withering Lumen",role="Healer",duration=12,tick=2,damage=0.04,glyph="✚",
		text="Everyone withers for 12 s; a Mender's Mending Light or Second Dawn cleanses it."},
	nova={name="Eventide Nova",role="Damage",channel=6,damage=0.7,breakShare=0.05,glyph="⚔",
		text="A 6 s channel: break it with 5% of the boss's HP or a Disrupting Shot, or it strikes everyone."},
	lock={name="Constellation Lock",role="Puzzle",glyph="✦",
		text="The core seals until the Star Chart is replayed (Attune presses the next plate)."},
}
EG.Bosses = {
	[6]={phases={
		{below=1,name="Radiant Vigil",every={verdict=20}},
		{below=0.6,name="Withering Reliquary",every={verdict=20,blight=24}},
	}},
	[7]={phases={
		{below=1,name="Sovereign's Court",every={verdict=18}},
		{below=0.7,name="Eventide Rite",every={verdict=18,blight=24,nova=30}},
		{below=0.35,name="Constellation Lock",every={verdict=18,blight=24,nova=30},lock="chart"},
	}},
}
function EG.phaseAt(floorIndex, fraction)
	local b = EG.Bosses[tonumber(floorIndex) or 0]
	if not b then return 0, nil end
	fraction = tonumber(fraction) or 1
	local index = 1
	for i, ph in ipairs(b.phases) do if fraction <= ph.below + 1e-9 then index = i end end
	return index, b.phases[index]
end
function EG.mechDamage(kind, maxHealth, master, takenMult)
	local m = EG.Mechanics[kind]
	if not m or not m.damage then return 0 end
	local frac = m.damage * (if master == true then 1 + EG.MASTER_MECH else 1)
	return math.max(1, math.floor((tonumber(maxHealth) or 100) * frac * (tonumber(takenMult) or 1)))
end
-- Verdict target among rows {key, class, damage, alive}: the living Aegis with
-- the most damage (taunt), else the living delver with the most damage.
function EG.verdictTarget(rows)
	local best, bestAegis
	for _, r in ipairs(rows) do
		if r.alive then
			if r.class == "Aegis" and (not bestAegis or (r.damage or 0) > (bestAegis.damage or 0)) then bestAegis = r end
			if not best or (r.damage or 0) > (best.damage or 0) then best = r end
		end
	end
	return bestAegis or best
end
function EG.novaThreshold(coreHp) return math.max(1, math.ceil((tonumber(coreHp) or 0) * EG.Mechanics.nova.breakShare - 1e-9)) end

-- Credit (Minigames-style) -------------------------------------------------------
EG.RECENT_SECONDS = 60    -- a credited action (damage, tuning, puzzle) this recently before the kill
EG.MEDIAN_SHARE = 0.25    -- parties of 3+: points >= 25% of the median member's points
EG.REJOIN_SECONDS = 90    -- a delver who drops mid-run may rejoin with their record
EG.REJOIN_GRACE = 15      -- ... keeping their idle clock plus this many seconds
function EG.median(list)
	local t = {}
	for _, v in ipairs(list) do table.insert(t, tonumber(v) or 0) end
	if #t == 0 then return 0 end
	table.sort(t)
	local mid = (#t + 1) // 2
	return if #t % 2 == 1 then t[mid] else (t[mid] + t[mid + 1]) / 2
end
-- c = {points, total, median, partySize, lastAction, now}. Returns ok, reason.
function EG.creditCheck(c)
	if type(c) ~= "table" then return false, "invalid" end
	if not Data.dungeonContributed(c.points, c.total) then return false, "share" end
	if (tonumber(c.partySize) or 1) >= 3 and (tonumber(c.points) or 0) < EG.MEDIAN_SHARE * (tonumber(c.median) or 0) then return false, "median" end
	if not c.lastAction or not c.now or c.now - c.lastAction > EG.RECENT_SECONDS then return false, "recent" end
	return true
end

-- Bonus chest ------------------------------------------------------------------
-- Rolled once per credited clear (contents saved in the journal at the clear):
-- guaranteed essence (the clear's base essence, x EG.MASTER_ESSENCE on Master
-- clears) + the floor's chest (with the Master rows on Master clears) at
-- x BONUS_CHANCE x the grade's chance factor (the free chest applies the same
-- grade factor to the Master rows, DC.runRewards). Opening costs coins (or one
-- Lodestar Key); unopened chests expire.
-- The contents are shown before paying, so the fee is priced on what is shown:
-- EG.chestFee = max(the floor's minimum fee, CHEST_FEE_SHARE x the shown items'
-- merchant value). Opening is never a blind gamble and never a free reroll.
EG.BonusCost = {50,100,150,250,350,500,700}          -- minimum fee, normal
EG.BonusCostMaster = {100,200,300,450,600,800,1000}  -- minimum fee, Master
EG.CHEST_FEE_SHARE = 0.75
EG.BONUS_CHANCE = 1.5
EG.CHEST_SECONDS = 900
function EG.bonusCost(floorIndex, master)
	local list = if master == true then EG.BonusCostMaster else EG.BonusCost
	return list[tonumber(floorIndex) or 1] or list[1]
end
-- Merchant value of a rolled chest {[itemId]=count}.
function EG.chestValue(items)
	local v = 0
	for id, n in pairs(type(items) == "table" and items or {}) do
		local def = Data.Items[id]
		v += (def and tonumber(def.value) or 0) * math.max(0, tonumber(n) or 0)
	end
	return v
end
-- Fee for the shown contents.
function EG.chestFee(floorIndex, master, items)
	return math.max(EG.bonusCost(floorIndex, master), math.floor(EG.CHEST_FEE_SHARE * EG.chestValue(items)))
end
-- A chest holding a Master-only item or a unique (weapon, armor, accessory).
function EG.chestNotable(items)
	for id in pairs(type(items) == "table" and items or {}) do
		local def = Data.Items[id]
		if def and (def.masterOnly == true or def.kind == "weapon" or def.kind == "armor" or def.kind == "accessory") then return true end
	end
	return false
end
-- A new clear's chest normally replaces an unopened one, but never silently drops
-- a notable chest: the unopened chest is kept unless the new one is notable too and
-- worth more. Returns true to keep the old chest.
function EG.keepOldChest(old, new)
	if type(old) ~= "table" or not EG.chestNotable(old.items) then return false end
	if type(new) == "table" and EG.chestNotable(new.items) and EG.chestValue(new.items) > EG.chestValue(old.items) then return false end
	return true
end
function EG.bonusPlan(floorIndex, grade, master)
	local f = floors[floorIndex] or floors[1]
	local g = Data.DungeonGradeById[grade] or Data.DungeonGradeById.B
	local essence = math.max(1, math.floor(f.rewards.essence * g.mult)) * (if master == true then EG.MASTER_ESSENCE else 1)
	local table_ = {{item="ObservatoryEssence",chance=1,min=essence,max=essence * 2}}
	local function add(list)
		for _, d in ipairs(list) do
			if d.item ~= "ObservatoryEssence" then
				table.insert(table_, {item=d.item,chance=math.min(1, d.chance * g.chance * EG.BONUS_CHANCE),min=d.min,max=d.max})
			end
		end
	end
	add(f.chest)
	if master == true then add(EG.MasterChest[f.index] or {}) end
	return {cost=EG.bonusCost(f.index, master),drops=table_}
end
-- Expected coin value of a drop table (item value x mean count x chance).
function EG.expectedValue(drops)
	local v = 0
	for _, d in ipairs(drops) do
		local def = Data.Items[d.item]
		v += (def and def.value or 0) * d.chance * (d.min + d.max) / 2
	end
	return v
end

-- Run log, weekly bests, personal bests -------------------------------------------
EG.LOG_LIMIT = 12
EG.WEEK = 7 * 24 * 3600
EG.RUN_MEMORY = 8 -- credited run ids remembered (one credit per run id)
function EG.key(floorIndex, master) return tostring(math.floor(tonumber(floorIndex) or 1)) .. (if master == true then "m" else "") end
function EG.weekOf(t) return math.floor((tonumber(t) or 0) / EG.WEEK) end
function EG.weekEnds(t) return (EG.weekOf(t) + 1) * EG.WEEK end
-- Weekly rollover (forward only): a server whose clock is behind the saved week
-- keeps the newer week, so it can never re-open a bounty already claimed.
function EG.rollWeek(state, now)
	local wk = EG.weekOf(now)
	if type(state.week) ~= "table" or (tonumber(state.week.id) or -1) < wk then state.week = {id=wk,best={},bounty={}} end
	return state.week
end
-- Weekly first-clear bounty: the floor's base essence (x2 in Master Mode).
function EG.bounty(floorIndex, master)
	local f = floors[floorIndex] or floors[1]
	return f.rewards.essence * (if master == true then 2 else 1)
end
local function num(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	v = math.floor(v)
	if lo and v < lo then return nil end
	if hi and v > hi then v = hi end
	return v
end
local function validKey(k)
	if type(k) ~= "string" then return false end
	local f, m = string.match(k, "^(%d+)(m?)$")
	f = tonumber(f)
	return f ~= nil and floors[f] ~= nil and (m == "" or f <= DC.MASTER_FLOORS)
end
EG.validKey = validKey
-- Always returns a clean p.dungeonEndgame; drops stale weeks and expired chests.
function EG.migrate(raw, now)
	local t = type(raw) == "table" and raw or {}
	now = tonumber(now) or 0
	local out = {log={},week={id=EG.weekOf(now),best={},bounty={}},pb={},chest=nil,runs={}}
	for _, e in ipairs(type(t.log) == "table" and t.log or {}) do
		if type(e) == "table" and floors[tonumber(e.f) or 0] and #out.log < EG.LOG_LIMIT then
			table.insert(out.log, {t=num(e.t, 0) or 0,f=num(e.f, 1),m=e.m == true,g=if Data.DungeonGradeById[e.g] then e.g else "D",
				s=num(e.s, 0, 300) or 0,sec=num(e.sec, 0) or 0,d=num(e.d, 0, 99) or 0})
		end
	end
	local w = type(t.week) == "table" and t.week or {}
	-- Weeks only move forward: a saved week newer than this server's clock (by at
	-- most one week; anything further is corrupt) is kept with its bests and bounties.
	local savedWeek = num(w.id, 0)
	if savedWeek and savedWeek == out.week.id + 1 then out.week.id = savedWeek end
	if savedWeek == out.week.id then
		for k, v in pairs(type(w.best) == "table" and w.best or {}) do
			local s = num(v, 0, 300)
			if validKey(k) and s then out.week.best[k] = s end
		end
		for k, v in pairs(type(w.bounty) == "table" and w.bounty or {}) do
			if validKey(k) and v == true then out.week.bounty[k] = true end
		end
	end
	for k, v in pairs(type(t.pb) == "table" and t.pb or {}) do
		if validKey(k) and type(v) == "table" then
			local s, sec = num(v.score, 0, 300), num(v.seconds, 1)
			if s and sec then out.pb[k] = {score=s,seconds=sec} end
		end
	end
	local c = t.chest
	if type(c) == "table" and floors[tonumber(c.floor) or 0] and type(c.items) == "table" and (tonumber(c.expires) or 0) > now then
		local items = {}
		for id, n in pairs(c.items) do
			local v = num(n, 1, 9999)
			if type(id) == "string" and Data.Items[id] and v then items[id] = v end
		end
		out.chest = {floor=num(c.floor, 1),master=c.master == true and num(c.floor, 1) <= DC.MASTER_FLOORS,grade=if Data.DungeonGradeById[c.grade] then c.grade else "B",
			items=items,cost=num(c.cost, 0) or 0,expires=num(c.expires, 0)}
	end
	for _, id in ipairs(type(t.runs) == "table" and t.runs or {}) do
		if type(id) == "string" and #id <= 64 and #out.runs < EG.RUN_MEMORY then table.insert(out.runs, id) end
	end
	return out
end
-- Record one credited clear: log row (newest first), weekly best, bounty claim,
-- personal best (higher score, then faster). Returns {bounty=n, weeklyBest=bool, pb=bool}.
function EG.record(state, floorIndex, master, grade, score, seconds, deaths, now)
	local key = EG.key(floorIndex, master)
	EG.rollWeek(state, now)
	table.insert(state.log, 1, {t=now,f=floorIndex,m=master == true,g=grade,s=score,sec=seconds,d=deaths})
	while #state.log > EG.LOG_LIMIT do table.remove(state.log) end
	local out = {bounty=0,weeklyBest=false,pb=false}
	if score > (state.week.best[key] or -1) then state.week.best[key] = score; out.weeklyBest = true end
	if not state.week.bounty[key] then state.week.bounty[key] = true; out.bounty = EG.bounty(floorIndex, master) end
	local pb = state.pb[key]
	if not pb or score > pb.score or (score == pb.score and seconds < pb.seconds) then
		state.pb[key] = {score=score,seconds=math.max(1, seconds)}
		out.pb = true
	end
	return out
end
function EG.rememberRun(state, runId)
	if type(runId) ~= "string" or runId == "" then return true end
	if table.find(state.runs, runId) then return false end
	table.insert(state.runs, 1, runId)
	while #state.runs > EG.RUN_MEMORY do table.remove(state.runs) end
	return true
end

-- Balance model (verify-dungeon-master.luau) ------------------------------------
-- A clear takes MODEL_PAR x the run's par plus MODEL_OVERHEAD seconds (pad,
-- walking, chest), never faster than the 90 s credit cooldown. Rates at grade S
-- with every secret; chest value = expected value of the free chest roll(s).
-- The bonus chest is counted as opened (its fee is a share of the shown value,
-- so opening pays at merchant value): its essence and Starcores join essence/h
-- and cores/h (as do the free chest's), its value less the fee is bonusNet (/h).
EG.MODEL_PAR, EG.MODEL_OVERHEAD = 0.85, 45
function EG.expectedCount(drops, id)
	local n = 0
	for _, d in ipairs(drops) do if d.item == id then n += d.chance * (d.min + d.max) / 2 end end
	return n
end
function EG.model(floorIndex, master, grade)
	grade = grade or "S"
	local seconds = math.max(Data.Dungeons.clearCooldown, DC.par(floorIndex, master) * EG.MODEL_PAR + EG.MODEL_OVERHEAD)
	local runs = 3600 / seconds
	local r = DC.runRewards(floorIndex, grade, {master=master,secrets=DC.secretCount(floorIndex)})
	local chest = EG.expectedValue(r.chest) * r.rolls
	local bonus = EG.bonusPlan(floorIndex, grade, master)
	local bonusValue = EG.expectedValue(bonus.drops)
	local bonusFee = math.max(bonus.cost, EG.CHEST_FEE_SHARE * bonusValue)
	local essence = r.items.ObservatoryEssence + EG.expectedCount(r.chest, "ObservatoryEssence") * r.rolls + EG.expectedCount(bonus.drops, "ObservatoryEssence")
	local cores = EG.expectedCount(r.chest, "EclipsedStarcore") * r.rolls + EG.expectedCount(bonus.drops, "EclipsedStarcore")
	return {seconds=seconds,runsPerHour=runs,dungeoneeringXp=r.dungeoneeringXp * runs,combatXp=r.combatXp * runs,coins=r.coins * runs,
		essence=essence * runs,cores=cores * runs,coresPerRun=cores,chestValue=chest * runs,
		bonusValue=bonusValue,bonusCost=bonusFee,bonusNet=(bonusValue - bonusFee) * runs}
end
-- Collection Log: Master-only rows belong to the Dungeons tab.
if Data.CommissionsLogs and Data.CommissionsLogs.LogRoots then Data.CommissionsLogs.LogRoots.DungeonEndgame = "Dungeons" end
end
-- <<< END Dungeon endgame <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- >>> BEGIN Lairs (Bossing team; append-only section) >>>
-- Instanced lair bosses (docs/DEPTH-CONTRACT.md §25): four original bosses at
-- Combat 30/50/70/90, summoned at lair altars on existing islands and fought
-- solo or with up to two crewmates in an arena built off-map on demand.
-- Pure data and pure rules only; lairs.server.lua runs the instances (arena,
-- teleports, rejoin, rewards relay), combat.server.lua's Lairs section runs
-- the creatures (stances, telegraphs, tiles, brood wards, ordered sigils,
-- enrage), server.server.lua's Lairs block charges fees and pays loot.
------------------------------------------------------------------------------
do
local LR = {}
Data.Lairs = LR
local CS = Data.CombatStyles
LR.MAX_PARTY = 3            -- players per instance (the host + two crewmates)
LR.MAX_INSTANCES = 6        -- concurrent lair instances per server
LR.MAX_ADDS = 4             -- live adds per instance (creature cap: 6 x (1 + 4) = 30)
LR.WARMUP = 15              -- seconds between opening and the boss rising (crewmates may join)
LR.REJOIN_SECONDS = 75      -- a dropped member may rejoin the live fight this long
LR.EXIT_SECONDS = 8         -- after a kill, members return to the altar
LR.AWAY_SECONDS = 8         -- a member outside the arena this long has left the fight
LR.EMPTY_SECONDS = 75       -- a fight with no member present this long ends ("abandoned")
LR.ARENA_RANGE = 40         -- flat studs from the arena centre that count as "inside" (covers the floor corners)
LR.PARTY_HP = 0.85          -- extra boss health per extra member (at the boss's rise)
LR.MIN_FAIR_SHARE = 0.4     -- party credit: damage >= 40% of an equal share of the boss's health
LR.IRONMAN_SHARE = 0.3      -- Ironman journals in a party carry their own weight
LR.RECENT_SECONDS = 60      -- credit needs a hit this recently before the kill
LR.WARD = 0.35              -- boss damage taken while a brood ward (unordered adds) lives
LR.PRAYED = 0.25            -- a stance attack into the matching Ward prayer: x0.25 before the prayer's own -40%
LR.ENRAGE_DAMAGE = 1.6
LR.ENRAGE_TEMPO = 0.7
LR.ATTACK_SECONDS = 2.2     -- basic (stance) attack interval
LR.STANCE_WARN = 1          -- the HUD flags the stance change this many attacks ahead
LR.GRID = 5                 -- tile lattice: GRID x GRID cells of CELL studs (the arena floor)
LR.CELL = 11
LR.MIN_SAFE = 6             -- every tile pattern leaves at least this many safe cells
LR.PET_HOURS = 40           -- pets: expected hours of kills at the model's kill rate
LR.KEEP_LOG = 10            -- recent kills kept in the journal
LR.MAX_KC = 1000000
LR.REWARD_RETRY, LR.REWARD_WINDOW = 5, 120
LR.REJOIN_VERIFY = 3        -- after a rejoin the arena position (and the disconnect health) is re-applied this long
LR.FLEE_HP, LR.FLEE_SECONDS = 0.25, 3 -- a disconnect below 25% health within 3 s of a hit counts as a death
LR.UNIQUE_MAX = 0.85        -- every unique stat <= 85% of its higher-requirement rival's (lead decision)

-- Combat triangle for a weakness w: w deals +30%, the style w beats is resisted.
function LR.triangle(w)
	local style = CS.beats[w]
	return w, CS.beats[style]
end
local function attack(kind, name, fields)
	local a = {kind=kind,name=name}
	for k, v in pairs(fields or {}) do a[k] = v end
	return a
end

-- Bosses ------------------------------------------------------------------------
-- stances: basic attack styles cycled every stanceEvery attacks (phase.stances
-- overrides); the matching Ward prayer is the counter. Specials rotate per
-- phase every `interval` s: disc (on a member), ring (around the boss), safe
-- (only near the boss is safe), tiles (charged lattice cells), adds (a brood
-- ward: the boss takes LR.WARD damage while it lives), sigils (ordered adds:
-- the boss is immune and only the lowest-numbered sigil can be struck).
-- Telegraphs carry no style (dodge them; prayers do not help).
LR.Order = {"Bramblemaw","Aerisca","Pyrewarden","Nihlvar"}
LR.Bosses = {
	Bramblemaw={name="Bramblemaw, the Thorn Matriarch",short="Bramblemaw",lairName="Thornroot Hollow",level=30,combat=30,
		isle="Windpine Grove",region="Windpine",fee=300,color="6BBF59",body="stalker",arenaColor="4E6B3A",floor="LeafyGrass",
		hp=24000,damage=90,defense=60,xp=800,speed=13,coins=550,coinRange={min=400,max=700},weakness="magic",stances={"melee"},stanceEvery=99,
		enrage=150,duration=300,
		blurb="A bramble-wolf grown fat on the grove's thorns. Her brood shields her: cut it down, then strike.",
		mechanics={"Brood ward: Thornspawn shield her (65% less damage) until slain","Thornburst and Bramble Lash telegraphs","Enrage after 2:30"},
		phases={
			{at=1,name="Rooted",rotation={"brood","lash","thornburst"},interval=7},
			{at=0.5,name="Bloodbloom",rotation={"lash","brood","thornburst","lash"},interval=5.5},
		},
		attacks={
			lash=attack("disc","Bramble Lash",{radius=7,windup=1.8,mult=2.0}),
			thornburst=attack("ring","Thornburst",{radius=11,windup=2.2,mult=2.2}),
			brood=attack("adds","Brood Call",{add="Thornspawn",count=3,radius=13}),
		}},
	Aerisca={name="Aerisca, the Squall Siren",short="Aerisca",lairName="Squallglass Eyrie",level=50,combat=50,
		isle="Skyreach",region="Skyreach",fee=800,color="8FD3E8",body="harrier",arenaColor="5A7E95",floor="Glass",
		hp=78000,damage=200,defense=150,xp=3000,speed=16,coins=1750,coinRange={min=1400,max=2100},weakness="ranged",stances={"melee","ranged"},stanceEvery=4,
		enrage=210,duration=360,tiles=true,
		blurb="A storm-singer who calls lightning down the glass lattice. Her talons and quills alternate: pray to match.",
		mechanics={"Stance switch every 4 attacks: Ward of Fangs / Ward of Quills","Squall Lattice: charged tiles strike after 2.6 s","Eye of the Storm: only beside her is safe","Enrage after 3:30"},
		phases={
			{at=1,name="Updraft",rotation={"squall","spear"},interval=8},
			{at=0.6,name="Maelstrom",rotation={"squall","spear","squall","eye"},interval=6.5},
		},
		attacks={
			squall=attack("tiles","Squall Lattice",{count=10,windup=2.6,mult=2.4}),
			spear=attack("disc","Gale Spear",{radius=6,windup=1.6,mult=1.8}),
			eye=attack("safe","Eye of the Storm",{radius=9,windup=3.0,mult=2.5}),
		}},
	Pyrewarden={name="The Pyrewarden",short="Pyrewarden",lairName="Emberforge Vault",level=70,combat=70,
		isle="Cinder Shelf",region="Quarry",fee=2000,color="E8643A",body="golem",arenaColor="5C3A2E",floor="Basalt",
		hp=150000,damage=360,defense=260,xp=5500,speed=11,coins=3700,coinRange={min=3000,max=4400},weakness="melee",stances={"magic","ranged"},stanceEvery=3,
		enrage=240,duration=420,
		blurb="A forge-guardian bound by three sigils. Break them in order to bare its core; its flames and slag shots alternate.",
		mechanics={"Forge Sigils: immune until sigils I, II, III fall in order","Stance switch every 3 attacks: Ward of Glyphs / Ward of Quills","Slag, Flare and Nova telegraphs","Enrage after 4:00"},
		phases={
			{at=1,name="Kindled",rotation={"sigils","slag","flare"},interval=7},
			{at=0.66,name="Smelting",rotation={"slag","sigils","flare","slag"},interval=6},
			{at=0.33,name="Meltdown",rotation={"sigils","flare","slag","nova"},interval=5},
		},
		attacks={
			slag=attack("disc","Slag Spit",{radius=8,windup=1.8,mult=2.2}),
			flare=attack("ring","Forge Flare",{radius=12,windup=2.2,mult=2.4}),
			nova=attack("safe","Heart Nova",{radius=10,windup=3.0,mult=2.8}),
			sigils=attack("sigils","Forge Sigils",{add="ForgeSigil",count=3,radius=17}),
		}},
	Nihlvar={name="Nihlvar, the Hollow Archon",short="Nihlvar",lairName="Riftcrown Sanctum",level=90,combat=85,
		isle="The Shattered Crown",region="ShatteredCrown",fee=4000,color="7A5BC4",body="seer",arenaColor="2E2448",floor="Slate",
		hp=480000,damage=620,defense=380,xp=7600,speed=13,coins=6800,coinRange={min=5800,max=7800},weakness="magic",stances={"melee","ranged","magic"},stanceEvery=3,
		enrage=300,duration=480,tiles=true,
		blurb="An archon of the broken crown. Each phase turns its weakness and its stances cycle all three styles.",
		mechanics={"Stance cycle melee → ranged → magic every 3 attacks (all three Wards)","Weakness shifts magic → ranged → melee by phase","Rift Anchors (ordered, immune) and the Null Lattice tiles","Enrage after 5:00"},
		phases={
			{at=1,name="Hollow Court",weakness="magic",rotation={"rend","anchors","rend","umbra"},interval=7},
			{at=0.66,name="Riftfall",weakness="ranged",rotation={"lattice","rend","anchors","umbra"},interval=6},
			{at=0.33,name="Null Crown",weakness="melee",rotation={"lattice","eclipse","anchors","rend"},interval=5},
		},
		attacks={
			rend=attack("disc","Void Rend",{radius=7,windup=1.7,mult=2.0}),
			umbra=attack("ring","Umbral Ring",{radius=12,windup=2.2,mult=2.4}),
			eclipse=attack("safe","Hollow Eclipse",{radius=9,windup=3.0,mult=2.8}),
			lattice=attack("tiles","Null Lattice",{count=13,windup=2.4,mult=2.6}),
			anchors=attack("sigils","Rift Anchors",{add="RiftAnchor",count=3,radius=16}),
		}},
}
-- Adds: never iterated through Data.Monsters (reached via __index for damage XP).
LR.Adds = {
	Thornspawn={name="Thornspawn",level=24,hp=1500,damage=40,defense=20,xp=40,speed=15,color="8BC34A",style="melee",body="thornling"},
	ForgeSigil={name="Forge Sigil",level=66,hp=12000,damage=0,defense=120,xp=260,speed=0,color="FFB347",style="magic",body="wisp",stationary=true},
	RiftAnchor={name="Rift Anchor",level=88,hp=30000,damage=0,defense=200,xp=520,speed=0,color="B48CFF",style="magic",body="wisp",stationary=true},
}
for i, id in ipairs(LR.Order) do
	local def = LR.Bosses[id]
	def.id, def.index, def.lair = id, i, true
	def.attackStyle = def.stances[1]
	def.weakness, def.defenceStyle = LR.triangle(def.weakness)
	def.coinsAvg = (def.coinRange.min + def.coinRange.max) / 2
	for k, a in pairs(def.attacks) do a.id = k end
end
for id, def in pairs(LR.Adds) do
	def.id, def.lair, def.lairAdd = id, true, true
	def.attackStyle, def.weakness, def.defenceStyle = def.style, CS.beatenBy[def.style], CS.beats[def.style]
	def.coins, def.drops = 0, {}
end
-- Lookups by id reach lair bosses and adds; pairs() still sees marker monsters only.
do
	local mt = getmetatable(Data.Monsters)
	local prior = mt and mt.__index
	setmetatable(Data.Monsters, {__index = function(t, id)
		local v
		if type(prior) == "function" then v = prior(t, id) elseif type(prior) == "table" then v = prior[id] end
		if v ~= nil then return v end
		return rawget(LR.Bosses, id) or rawget(LR.Adds, id)
	end})
end
function LR.boss(id) return type(id) == "string" and rawget(LR.Bosses, id) or nil end

-- Uniques (each below the crafted/dungeon item of the next higher requirement) ---
-- LR.Rivals: unique -> rival item id; verify-bosses.luau checks every stat
-- (and a bow/staff's power/speed/ammo tier) stays strictly below the rival,
-- whose requirement is strictly higher.
LR.Uniques = {
	Bramblemaw={weapon="ThornmawCleaver",accessory="ThornheartLocket",pet="BramblingPet"},
	Aerisca={weapon="GalesongLongbow",accessory="SquallglassPendant",pet="SirenletPet"},
	Pyrewarden={weapon="PyreheartStaff",accessory="EmberwardSeal",pet="ForgekinPet"},
	Nihlvar={weapon="HollowcrownEdge",accessory="ArchonSigil",pet="HollowispPet"},
}
LR.Rivals = {
	ThornmawCleaver="PrismaticSword",GalesongLongbow="AetherheartLongbow",PyreheartStaff="RiftcrownStaff",HollowcrownEdge="Crownbreaker",
	ThornheartLocket="SlayerEmblem",SquallglassPendant="EnchantedStormopalAmulet",EmberwardSeal="SovereignHalo",ArchonSigil="SovereignSignet",
}
local function unique(id, boss, def)
	def.lairBoss, def.logUnique = boss, "Lairs"
	return item(id, def)
end
local R = Data.Rarity
unique("ThornmawCleaver","Bramblemaw",{name="Thornmaw Cleaver",kind="weapon",slot="weapon",tier=5,rarity="Epic",color="6BBF59",
	stats={damage=187,strength=75,critChance=7,critDamage=50},requires={Combat=30},value=4500,
	description="Melee. Bramblemaw's own thorn-fang, still green. Requires Combat 30. Lair unique."})
unique("GalesongLongbow","Aerisca",{name="Galesong Longbow",kind="weapon",slot="weapon",style="ranged",tier=6,rarity="Legendary",color="8FD3E8",
	stats={critDamage=40,rangedAccuracy=71},ranged={power=239,speed=1.05,range=CS.maxRange,maxAmmoTier=6},requires={Ranged=45},value=9000,
	description="Ranged weapon. Strung with Aerisca's storm-gut. "..CS.maxRange.." stud reach. Arrows up to tier 6. Requires Ranged 45. Lair unique."})
unique("PyreheartStaff","Pyrewarden",{name="Pyreheart Staff",kind="weapon",slot="weapon",style="magic",tier=7,rarity="Legendary",color="E8643A",
	stats={intelligence=153,abilityDamage=5},magic={power=161,speed=1.2,elements={"Ember","Stone"}},requires={Magic=55},value=16000,
	description="Magic weapon. The Pyrewarden's banked core. Supplies unlimited Ember, Stone glyphs. Requires Magic 55. Lair unique."})
unique("HollowcrownEdge","Nihlvar",{name="Hollowcrown Edge",kind="weapon",slot="weapon",tier=9,rarity="Mythic",color="7A5BC4",
	stats={damage=323,strength=148,critChance=15,critDamage=93},requires={Combat=65},value=30000,
	special={id="HollowSunder",name="Hollow Sunder",boss=0.25,warded=0.5},
	description="Melee. A shard of Nihlvar's hollow crown. Hollow Sunder: +25% damage to bosses (lair, world and slayer bosses), +50% while a ward, brood or add wave shields them. Requires Combat 65. Lair unique."})
-- Hollow Sunder (Polish; the Hollowcrown Edge's niche after the 85% cap). A
-- melee swing with a weapon carrying `special.boss` multiplies its raw damage by
-- 1 + boss against a boss record (r.boss slayer boss, r.worldBoss, a lair boss;
-- never adds or ordinary monsters), or by 1 + warded while that boss is shielded
-- (lair brood ward / sigils, world boss add wave). verify-bosses models it:
-- general content stays below the Sovereign Greatblade; on bosses it beats the
-- Greatblade and stays below Crownbreaker while unwarded.
function LR.sunderMult(weaponId, target)
	local def = type(weaponId) == "string" and Data.Items[weaponId]
	local sp = def and def.special
	if type(sp) ~= "table" or type(sp.boss) ~= "number" or type(target) ~= "table" or target.boss ~= true then return 1 end
	return 1 + (if target.warded == true then sp.warded or sp.boss else sp.boss)
end
unique("ThornheartLocket","Bramblemaw",{name="Thornheart Locket",kind="accessory",rarity="Rare",color=R.Rare.color,stats={strength=8,critDamage=6},
	value=40*R.Rare.rank^2,description="Accessory. Magical Power "..R.Rare.power..". Only Bramblemaw's den holds one."})
unique("SquallglassPendant","Aerisca",{name="Squallglass Pendant",kind="accessory",rarity="Epic",color=R.Epic.color,stats={rangedAccuracy=9,rangedStrength=6,speed=3},
	value=40*R.Epic.rank^2,description="Accessory. Magical Power "..R.Epic.power..". Only Aerisca's eyrie holds one."})
unique("EmberwardSeal","Pyrewarden",{name="Emberward Seal",kind="accessory",rarity="Legendary",color=R.Legendary.color,stats={intelligence=16,critDamage=14,strength=10},
	value=40*R.Legendary.rank^2,description="Accessory. Magical Power "..R.Legendary.power..". Only the Emberforge Vault holds one."})
unique("ArchonSigil","Nihlvar",{name="Archon's Sigil",kind="accessory",rarity="Mythic",color=R.Mythic.color,stats={strength=34,critDamage=25,health=60},
	value=40*R.Mythic.rank^2,description="Accessory. Magical Power "..R.Mythic.power..". Only the Riftcrown Sanctum holds one."})

-- Boss pets (Data.Pets species + Pet depth abilities and looks) ----------------
do
	local PD = Data.PetDepth
	local species = {
		{boss="Bramblemaw",id="Brambling",name="Brambling",skill="Combat",rarity="Epic",color="6BBF59",perLevel={strength=0.3,health=0.6},form="quad",accent="C5E1A5",
			list={{name="Thorn Pup",kind="xp",skills={"Combat"},per=0.1,rarity="Common"},{name="Bramble Kin",kind="family",line="Bramble",per=0.25,rarity="Rare"},
				{name="Barbed Hide",kind="stat",stat="defense",per=0.4,rarity="Legendary",level=40}}},
		{boss="Aerisca",id="Sirenlet",name="Sirenlet",skill="Ranged",rarity="Epic",color="8FD3E8",perLevel={rangedAccuracy=0.3,speed=0.1},form="flyer",accent="E0F7FF",
			list={{name="Squall Song",kind="xp",skills={"Ranged"},per=0.1,rarity="Common"},{name="Keen Gale",kind="stat",stat="rangedStrength",per=0.3,rarity="Rare"},
				{name="Tailwind",kind="stat",stat="speed",per=0.15,rarity="Legendary",level=40}}},
		{boss="Pyrewarden",id="Forgekin",name="Forgekin",skill="Magic",rarity="Legendary",color="E8643A",perLevel={intelligence=0.8,defense=0.3},form="float",accent="FFD6A5",
			list={{name="Banked Embers",kind="xp",skills={"Magic"},per=0.12,rarity="Common"},{name="Kiln Heart",kind="stat",stat="intelligence",per=0.8,rarity="Rare"},
				{name="Slag Shell",kind="stat",stat="defense",per=0.5,rarity="Legendary",level=40}}},
		{boss="Nihlvar",id="Hollowisp",name="Hollowisp",skill="Combat",rarity="Legendary",color="7A5BC4",perLevel={strength=0.6,critDamage=0.6,health=1},form="float",accent="E0C3FC",
			list={{name="Hollow Hunger",kind="xp",skills={"Combat"},per=0.15,rarity="Common"},{name="Null Edge",kind="stat",stat="damagePercent",per=0.08,rarity="Rare"},
				{name="Archon's Ward",kind="stat",stat="defense",per=0.6,rarity="Legendary",level=40}}},
	}
	LR.PetSpecies = {}
	for _, s in ipairs(species) do
		local pet = {id=s.id,name=s.name,skill=s.skill,rarity=s.rarity,color=s.color,perLevel=s.perLevel}
		table.insert(Data.Pets, pet)
		Data.PetById[s.id] = pet
		for i, a in ipairs(s.list) do a.index = i; a.id = a.name:gsub("[^%w]", "") end
		if PD then
			PD.Abilities[s.id] = s.list
			PD.Looks[s.id] = {form=s.form,accent=s.accent}
			pet.ability = s.list[1].name..": up to "..PD.abilityText(s.list[1], PD.abilityValue(s.list[1], Data.PET_MAX_LEVEL, PD.MAX_RARITY))
		else
			pet.ability = s.list[1].name
		end
		pet.abilityNames = {s.list[1].name, s.list[2].name, s.list[3].name}
		unique(s.id.."Pet", s.boss, {name=s.name.." Pet",kind="pet",pet=s.id,rarity=s.rarity,color=s.color,value=200*R[s.rarity].rank^2,
			description="Summon from your pet menu. Abilities: "..table.concat(pet.abilityNames, ", ")..". "..LR.Bosses[s.boss].short.."'s lair pet."})
		LR.PetSpecies[s.boss] = s.id
	end
end

-- Loot ------------------------------------------------------------------------------
-- Rolled per credited member (Progression.rollDrops: Magic Find raises chances
-- under 5%, Pet Luck also raises pet rows). Non-unique rows stay at >= 5% so
-- only the uniques join the Collection Log (CommissionsLogs.RARE_CHANCE).
-- Pet chance = 1 / (LR.PET_HOURS x the model's kills per hour), rounded.
LR.PetChance = {Bramblemaw=1/900,Aerisca=1/800,Pyrewarden=1/650,Nihlvar=1/550}
LR.Loot = {
	Bramblemaw={
		{item="BeastHide",chance=1,min=8,max=16},{item="ArcaneDust",chance=1,min=8,max=16},{item="Shard",chance=0.4,min=2,max=4},
		{item="GolemCore",chance=0.15,min=1,max=2},
		{item="ThornheartLocket",chance=1/90,min=1,max=1},{item="ThornmawCleaver",chance=1/180,min=1,max=1},
	},
	Aerisca={
		{item="StormFeather",chance=1,min=6,max=12},{item="DriftPlume",chance=1,min=20,max=40},{item="VoidEssence",chance=0.35,min=2,max=4},
		{item="Stormglass",chance=0.15,min=1,max=2},
		{item="SquallglassPendant",chance=1/100,min=1,max=1},{item="GalesongLongbow",chance=1/200,min=1,max=1},
	},
	Pyrewarden={
		{item="GolemCore",chance=1,min=2,max=4},{item="VoidEssence",chance=1,min=3,max=6},{item="StarFragment",chance=0.08,min=1,max=1},
		{item="EmberwardSeal",chance=1/110,min=1,max=1},{item="PyreheartStaff",chance=1/220,min=1,max=1},
	},
	Nihlvar={
		{item="CrownShard",chance=1,min=8,max=14},{item="VoidEssence",chance=1,min=4,max=8},{item="StarFragment",chance=0.15,min=1,max=2},
		{item="SovereignEssence",chance=0.06,min=1,max=1},
		{item="ArchonSigil",chance=1/120,min=1,max=1},{item="HollowcrownEdge",chance=1/240,min=1,max=1},
	},
}
for _, id in ipairs(LR.Order) do
	table.insert(LR.Loot[id], {item=LR.Uniques[id].pet,chance=LR.PetChance[id],min=1,max=1})
	LR.Bosses[id].drops = LR.Loot[id] -- bestiary-style display
end
-- SkyBlock-style drop rarity labels (original names) by chance per kill.
LR.DropTiers = {
	{id="Guaranteed",min=1,color="FFFFFF"},{id="Frequent",min=0.2,color="55FF55"},{id="Occasional",min=0.05,color="5555FF"},
	{id="Rare",min=0.01,color="AA00AA"},{id="Elusive",min=0.002,color="FFAA00"},{id="Fabled",min=0,color="FF55FF"},
}
function LR.dropTier(chance)
	chance = tonumber(chance) or 0
	for _, t in ipairs(LR.DropTiers) do if chance >= t.min - 1e-12 then return t end end
	return LR.DropTiers[#LR.DropTiers]
end
function LR.isUnique(id) local d = type(id) == "string" and Data.Items[id] return d ~= nil and d.lairBoss ~= nil end
function LR.coinRoll(id, r)
	local def = LR.boss(id)
	if not def then return 0 end
	return def.coinRange.min + math.floor(math.clamp(tonumber(r) or 0, 0, 0.999999) * (def.coinRange.max - def.coinRange.min + 1))
end

-- Fight rules -------------------------------------------------------------------------
function LR.partyHp(def, n)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, LR.MAX_PARTY)
	return math.floor(def.hp * (1 + LR.PARTY_HP * (n - 1)))
end
function LR.phaseAt(def, fraction)
	local index = 1
	for i, phase in ipairs(def.phases) do if (tonumber(fraction) or 1) <= phase.at + 1e-9 then index = i end end
	return index
end
function LR.attackAt(def, phase, n)
	local list = (def.phases[phase] or def.phases[1]).rotation
	return list[((math.max(1, math.floor(n)) - 1) % #list) + 1]
end
function LR.interval(def, phase, enraged)
	local p = def.phases[phase] or def.phases[1]
	return p.interval * (if enraged then LR.ENRAGE_TEMPO else 1)
end
function LR.stances(def, phase) return (def.phases[phase] or {}).stances or def.stances end
-- Style of basic attack number n (1-based) in a phase.
function LR.stanceAt(def, phase, n)
	local list = LR.stances(def, phase)
	local every = math.max(1, def.stanceEvery or 99)
	local k = (math.max(1, math.floor(n)) - 1) // every
	return list[(k % #list) + 1]
end
-- Weakness / resisted style in a phase.
function LR.weaknessAt(def, phase)
	local p = def.phases[phase]
	if p and p.weakness then return LR.triangle(p.weakness) end
	return def.weakness, def.defenceStyle
end
-- Prayer check: multiplier on a stance attack of `style` against a protection.
function LR.prayerMult(style, protect)
	if style ~= nil and protect == style then return LR.PRAYED end
	return 1
end
-- Telegraph geometry (flat distance).
function LR.struck(a, cx, cz, x, z)
	local dx, dz = x - cx, z - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if a.kind == "disc" or a.kind == "ring" then return d <= a.radius end
	if a.kind == "safe" then return d > a.radius end
	return false
end
-- Lattice cell (1..GRID^2) under offset (dx, dz) from the arena centre, or nil off the lattice.
function LR.cellAt(dx, dz)
	local half = LR.GRID * LR.CELL / 2
	local i, j = math.floor((dx + half) / LR.CELL) + 1, math.floor((dz + half) / LR.CELL) + 1
	if i < 1 or j < 1 or i > LR.GRID or j > LR.GRID then return nil end
	return (j - 1) * LR.GRID + i
end
-- Offset of a cell's centre from the arena centre.
function LR.cellOffset(index)
	local i, j = (index - 1) % LR.GRID + 1, (index - 1) // LR.GRID + 1
	local half = LR.GRID * LR.CELL / 2
	return -half + (i - 0.5) * LR.CELL, -half + (j - 0.5) * LR.CELL
end
-- Charged cells for one lattice strike: `count` distinct cells (at least
-- LR.MIN_SAFE left safe), deterministic from the fight seed and the step.
function LR.tilePattern(seed, step, count)
	local total = LR.GRID * LR.GRID
	count = math.clamp(math.floor(tonumber(count) or 0), 0, total - LR.MIN_SAFE)
	local x = (math.floor(tonumber(seed) or 0) * 7919 + math.floor(tonumber(step) or 0) * 104729) % 2147483647
	local cells = {}
	for i = 1, total do cells[i] = i end
	for i = total, 2, -1 do
		x = (x * 48271) % 2147483647
		local j = x % i + 1
		cells[i], cells[j] = cells[j], cells[i]
	end
	local out = {}
	for i = 1, count do out[i] = cells[i] end
	table.sort(out)
	return out
end
-- Kill credit for one member: c = {party, share, member, alive, inside, lastHit, now, ironman}.
function LR.credit(c)
	if type(c) ~= "table" or c.member ~= true then return false, "member" end
	local party = math.clamp(math.floor(tonumber(c.party) or 1), 1, LR.MAX_PARTY)
	local share = tonumber(c.share) or 0
	if share ~= share or share <= 0 then return false, "share" end
	if c.alive ~= true then return false, "dead" end
	if c.inside ~= true then return false, "away" end
	if not c.lastHit or not c.now or c.now - c.lastHit > LR.RECENT_SECONDS then return false, "idle" end
	if party > 1 and share < LR.MIN_FAIR_SHARE / party then return false, "share" end
	if party > 1 and c.ironman and share < LR.IRONMAN_SHARE then return false, "ironman" end
	return true
end
-- Entry check. info = {combat, region (allowed bool), coins, busy}.
function LR.canEnter(id, info)
	local def = LR.boss(id)
	if not def then return false, "boss" end
	if type(info) ~= "table" then return false, "invalid" end
	if (tonumber(info.combat) or 0) < def.combat then return false, "level" end
	if info.region == false then return false, "region" end
	if info.busy then return false, "busy" end
	if (tonumber(info.coins) or 0) < def.fee then return false, "coins" end
	return true
end

-- Journal state: p.lairs = {kc={[boss]=n}, pb={[boss]=seconds}, pbParty={[boss]=n},
-- got={[item]=n} (lair uniques looted), deaths={[boss]=n}, log={{b,s,t,n,u}...}}.
local function count(v, cap)
	v = tonumber(v)
	if not v or v ~= v or v < 0 then return nil end
	return math.min(cap or LR.MAX_KC, math.floor(v))
end
function LR.migrate(t)
	t = type(t) == "table" and t or {}
	local out = {kc={},pb={},pbParty={},got={},deaths={},log={}}
	for _, key in ipairs({"kc","deaths"}) do
		for id, n in pairs(type(t[key]) == "table" and t[key] or {}) do
			local v = LR.boss(id) and count(n)
			if v and v > 0 then out[key][id] = v end
		end
	end
	for id, s in pairs(type(t.pb) == "table" and t.pb or {}) do
		local v = LR.boss(id) and count(s, 86400)
		if v and v >= 1 then
			out.pb[id] = v
			local n = type(t.pbParty) == "table" and count(t.pbParty[id], LR.MAX_PARTY)
			out.pbParty[id] = if n and n >= 1 then n else 1
		end
	end
	for id, n in pairs(type(t.got) == "table" and t.got or {}) do
		local v = LR.isUnique(id) and count(n)
		if v and v > 0 then out.got[id] = v end
	end
	for _, e in ipairs(type(t.log) == "table" and t.log or {}) do
		if type(e) == "table" and LR.boss(e.b) and #out.log < LR.KEEP_LOG then
			local u = if type(e.u) == "string" and LR.isUnique(e.u) then e.u else nil
			table.insert(out.log, {b=e.b,s=count(e.s, 86400) or 0,t=count(e.t, 4e9) or 0,n=count(e.n, LR.MAX_PARTY) or 1,u=u})
		end
	end
	-- owed = the open entry {fight, boss, fee}: set when the fee is paid, cleared
	-- when the entry settles; still set at a load -> refunded (server Lairs.settle).
	local o = t.owed
	local od = type(o) == "table" and LR.boss(o.boss)
	if od and type(o.fight) == "string" and #o.fight <= 64 then
		local fee = count(o.fee, od.fee)
		if fee and fee > 0 then out.owed = {fight=o.fight,boss=o.boss,fee=fee} end
	end
	return out
end
-- One credited kill. Returns {kc, pb = bool (new best), uniques = {id...}}.
function LR.record(state, id, seconds, party, drops, now)
	seconds = math.max(1, math.floor(tonumber(seconds) or 1))
	party = math.clamp(math.floor(tonumber(party) or 1), 1, LR.MAX_PARTY)
	state.kc[id] = math.min(LR.MAX_KC, (state.kc[id] or 0) + 1)
	local out = {kc=state.kc[id],pb=false,uniques={}}
	if not state.pb[id] or seconds < state.pb[id] then
		state.pb[id], state.pbParty[id] = seconds, party
		out.pb = true
	end
	local first
	for item, n in pairs(type(drops) == "table" and drops or {}) do
		if LR.isUnique(item) and n > 0 then
			state.got[item] = math.min(LR.MAX_KC, (state.got[item] or 0) + n)
			table.insert(out.uniques, item)
		end
	end
	table.sort(out.uniques)
	first = out.uniques[1]
	table.insert(state.log, 1, {b=id,s=seconds,t=math.floor(tonumber(now) or 0),n=party,u=first})
	while #state.log > LR.KEEP_LOG do table.remove(state.log) end
	return out
end
function LR.formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Balance model (printed and bounded by verify-bosses.luau) -------------------------
-- Player DPS at a level = the best open monster's effective health / MODEL_TTK
-- (the same 300 kills/h solo model the Minigames and Dungeon models use), used
-- for MODEL_UPTIME of the fight (dodging, prayer swaps, adds). The weakness
-- applies (+30%) as players bring the right style. A kill takes the fight plus
-- MODEL_OVERHEAD s (altar, warmup, return, restock). Coins/h = coin roll + the
-- merchant value of expected non-unique drops - the fee; the uniques' (and
-- pets') merchant value is reported separately (uniqueValue per kill, uniques
-- per hour) and kept out of the coins/h ratio (lead decision). The model rolls
-- base drop chances: it ignores Magic Find and Pet Luck, which raise every row
-- under 5% (uniques and pets) for geared players (see DEPTH-CONTRACT §25).
-- Slayer reference: 300 kills/h of the best monster's coins + the best open
-- master's task bounty per task; XP reference: solo Combat XP/h at that level.
LR.MODEL_TTK, LR.MODEL_UPTIME, LR.MODEL_OVERHEAD = 8, 0.75, 60
function LR.dpsAt(level)
	local m = Data.Minigames.bestMonster(level)
	return m.hp * (1 + (m.defense or 0) / 100) / LR.MODEL_TTK
end
-- uniques: nil = every row, false = without the lair uniques (pets included), true = uniques only.
function LR.expectedValue(drops, uniques)
	local v = 0
	for _, d in ipairs(drops) do
		local def = Data.Items[d.item]
		if uniques == nil or (uniques == true) == LR.isUnique(d.item) then
			v += d.chance * (d.min + d.max) / 2 * (def and def.value or 0)
		end
	end
	return v
end
function LR.model(id, party)
	local def = LR.boss(id)
	party = party or 1
	local dps = LR.dpsAt(def.level) * (1 + CS.weaknessBonus)
	local addHp, addXp = 0, 0
	for _, a in pairs(def.attacks) do
		if a.kind == "adds" or a.kind == "sigils" then
			local add = LR.Adds[a.add]
			local waves = #def.phases
			addHp += waves * a.count * add.hp * (1 + add.defense / 100)
			addXp += waves * a.count * add.xp
		end
	end
	local effHp = LR.partyHp(def, party) * (1 + def.defense / 100) + addHp
	local fight = effHp / (dps * party * LR.MODEL_UPTIME)
	local seconds = fight + LR.MODEL_OVERHEAD
	local kph = 3600 / seconds
	local loot = LR.expectedValue(LR.Loot[id], false)
	local uniqueValue = LR.expectedValue(LR.Loot[id], true)
	-- Party XP: each member deals an equal share of the scaled health; damage XP
	-- caps at the fight's real health (combat sends maxHp), so the share pays in full.
	local hp = LR.partyHp(def, party)
	local xpKill = def.xp * math.min(hp / party, hp) / def.hp + addXp / party
	local coinsKill = def.coinsAvg + loot - def.fee
	return {fight=fight,seconds=seconds,kph=kph,xp=xpKill * kph,coins=coinsKill * kph,coinsKill=coinsKill,
		lootValue=loot,uniqueValue=uniqueValue,uniques=uniqueValue * kph,petHours=1 / (LR.PetChance[id] * kph)}
end
function LR.slayerReference(level)
	local MG, ST = Data.Minigames, Data.SlayerTasks
	local m = MG.bestMonster(level)
	local best
	for _, master in ipairs(ST.Masters) do if master.combat <= level then best = master end end
	local amount, weight = 0, 0
	for _, t in ipairs(best.tasks) do amount += t.weight * (t.min + t.max) / 2; weight += t.weight end
	local kills = MG.SOLO.killsPerHour
	return {coins=kills * m.coins + kills / (amount / weight) * best.bounty,xp=MG.soloCombatXpPerHour(level),master=best.id,monster=m.id}
end

-- Collection Log: the Lairs tab (after World Bosses); uniques carry logUnique = "Lairs".
local CLog = Data.CommissionsLogs
if CLog and CLog.LogTabs and not CLog.LogTabs.Lairs then
	CLog.LogTabs.Lairs = {name="Lair Bosses",title="Lairbreaker",coins=40000,color="B48CFF"}
	local at = table.find(CLog.LogTabOrder, "Bosses")
	table.insert(CLog.LogTabOrder, if at then at + 1 else #CLog.LogTabOrder + 1, "Lairs")
	CLog.LogRoots.Lairs = "Lairs"
end
end
-- <<< END Lairs <<<

-- >>> Held items & swings (docs/DEPTH-CONTRACT.md §26) >>>
-- Pure rules shared by held.server.lua (builds the welded model), server.server.lua
-- (`hold` / `hotbarSet` verbs, p.held, auto tool switch), animate.client.lua
-- (which swing a held item plays, hold pose) and hotbar.client.lua.
-- Model specs are plain numbers in the grip frame (hand grip at the origin, the
-- handle runs along -Z, the swing plane is YZ), so this module needs no Roblox
-- types: {n name, s size, o offset, c colour key, m material, shape}.
------------------------------------------------------------------------------
do
local H = {}
Data.Held = H
H.MAX_PARTS = 8
H.AUTO_RETURN = 8 -- seconds after the last gather / attack before an auto-held tool goes back
H.RATE, H.BURST = 2, 5 -- hold / hotbarSet tokens per second, bucket size
H.REBUILD_GAP = 0.5 -- held.server.lua rebuilds a player's model at most once per this many seconds
H.HOTBAR_SLOTS = 9
H.FREE_SLOTS = {3, 4, 5, 6, 7, 8, 9} -- slot 1 = weapon, slot 2 = context tool
-- Classes: every weapon / tool resolves to exactly one. hand = which grip it welds to.
H.CLASSES = {
	sword = {hand = "right", kind = "weapon"}, greatblade = {hand = "right", kind = "weapon"}, dagger = {hand = "right", kind = "weapon"},
	maul = {hand = "right", kind = "weapon"}, glaive = {hand = "right", kind = "weapon"},
	shortbow = {hand = "left", kind = "weapon"}, longbow = {hand = "left", kind = "weapon"},
	staff = {hand = "right", kind = "weapon"}, wand = {hand = "right", kind = "weapon"},
	shield = {hand = "left", kind = "offhand"}, -- no shield items exist yet; the class is ready for them
	pickaxe = {hand = "right", kind = "tool"}, hatchet = {hand = "right", kind = "tool"}, rod = {hand = "right", kind = "tool"},
	hoe = {hand = "right", kind = "tool"}, hammer = {hand = "right", kind = "tool"},
}
H.TOOL_CLASS = {Pickaxe = "pickaxe", Hatchet = "hatchet", Rod = "rod", Hoe = "hoe", Hammer = "hammer"}
H.SKILL_CLASS = {Mining = "pickaxe", Woodcutting = "hatchet", Fishing = "rod", Farming = "hoe"}
-- Named weapons whose silhouette the name patterns below would miss.
H.OVERRIDE = {AstrarchFang = "dagger", SovereignNightfall = "dagger", EclipseGlaive = "glaive", BastionMaul = "maul",
	Thronebreaker = "maul", Riftcleaver = "greatblade", ColossusLumenbrand = "greatblade", SovereignGreatblade = "greatblade",
	Crownbreaker = "greatblade", LenswrightSaber = "sword", Stormblade = "sword", Blade = "sword"}
local PATTERNS = {{"Greatblade", "greatblade"}, {"Cleaver", "greatblade"}, {"Claymore", "greatblade"}, {"Dagger", "dagger"},
	{"Fang", "dagger"}, {"Knife", "dagger"}, {"Maul", "maul"}, {"Hammer", "maul"}, {"Glaive", "glaive"}, {"Spear", "glaive"},
	{"Halberd", "glaive"}, {"Shield", "shield"}, {"Buckler", "shield"}}
for id, class in pairs(H.OVERRIDE) do
	if Data.Items[id] then Data.Items[id].heldClass = class end
end

function H.classOf(def)
	if type(def) ~= "table" then return nil end
	if type(def.heldClass) == "string" and H.CLASSES[def.heldClass] then return def.heldClass end
	if def.kind == "tool" then return H.TOOL_CLASS[def.toolKind] end
	if def.kind == "shield" or def.slot == "offhand" then return "shield" end
	if def.kind ~= "weapon" then return nil end
	local name = tostring(def.name or "")
	if def.style == "ranged" then return if name:find("Shortbow") then "shortbow" else "longbow" end
	if def.style == "magic" then
		local wand = name:find("Wand") ~= nil or (type(def.magic) == "table" and type(def.magic.elements) == "table" and #def.magic.elements == 0)
		return if wand then "wand" else "staff"
	end
	for _, pattern in ipairs(PATTERNS) do
		if name:find(pattern[1]) then return pattern[2] end
	end
	return "sword"
end
function H.holdable(id)
	return type(id) == "string" and H.classOf(Data.Items[id]) ~= nil
end
function H.hand(class) return (H.CLASSES[class] or H.CLASSES.sword).hand end

-- Which gesture a held class swings when its owner attacks, and which held
-- classes stand in for a gesture's temporary prop (the held item itself swings).
H.ATTACK = {sword = "attack", greatblade = "cleave", maul = "cleave", dagger = "thrust", glaive = "lunge", shield = "attack",
	shortbow = "shoot", longbow = "shoot", staff = "cast", wand = "flick"}
H.FITS = {
	mine = {pickaxe = true}, chop = {hatchet = true}, fish = {rod = true}, harvest = {hoe = true}, hammer = {hammer = true, maul = true},
	attack = {sword = true, greatblade = true, dagger = true, glaive = true, maul = true},
	thrust = {dagger = true, sword = true}, cleave = {greatblade = true, maul = true, sword = true}, lunge = {glaive = true},
	shoot = {shortbow = true, longbow = true}, cast = {staff = true, wand = true}, flick = {wand = true, staff = true},
}
function H.fits(gesture, class) return class ~= nil and H.FITS[gesture] ~= nil and H.FITS[gesture][class] == true end
function H.attackGesture(id)
	local class = H.classOf(Data.Items[id or ""])
	return H.ATTACK[class or "sword"] or "attack"
end

-- Tier look: head colour is the item's own; trim and a glowing inlay follow rarity.
local RARITY_RANK = {Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6}
H.WOOD, H.LEATHER, H.BRASS, H.STRING = "8A5A32", "5A3A22", "C9974A", "EDE6D2"
function H.look(def)
	local rank = RARITY_RANK[def.rarity] or 1
	local tier = tonumber(def.tier) or tonumber(def.toolTier) or rank
	local rarity = Data.Rarity and Data.Rarity[def.rarity]
	return {
		head = tostring(def.color or "B0A89A"),
		trim = if rank >= 3 and rarity then rarity.color else H.BRASS,
		glow = if rank >= 4 then tostring(def.color or "FFFFFF") else nil,
		metal = if tier >= 7 then "Foil" elseif tier >= 4 then "DiamondPlate" else "Metal",
		rank = rank, tier = tier,
	}
end

local function p(n, s, o, c, m, shape) return {n = n, s = s, o = o, c = c, m = m, shape = shape} end
-- Part lists per class. c: "head" (tier colour), "trim", "wood", "leather", "string", "glow" (dropped below Epic).
H.SHAPES = {
	sword = {p("Grip", {0.2, 0.2, 0.9}, {0, 0, 0}, "leather", "Fabric"), p("Pommel", {0.3, 0.3, 0.3}, {0, 0, 0.55}, "trim", "Metal", "Ball"),
		p("Guard", {0.95, 0.18, 0.24}, {0, 0, -0.52}, "trim", "Metal"), p("Blade", {0.1, 0.34, 3.0}, {0, 0, -2.1}, "head", "metal"),
		p("Tip", {0.1, 0.2, 0.42}, {0, 0, -3.8}, "head", "metal"), p("Fuller", {0.12, 0.08, 2.3}, {0, 0, -1.95}, "glow", "Neon")},
	greatblade = {p("Grip", {0.22, 0.22, 1.4}, {0, 0, 0.25}, "leather", "Fabric"), p("Pommel", {0.36, 0.36, 0.36}, {0, 0, 1.05}, "trim", "Metal", "Ball"),
		p("Guard", {1.35, 0.26, 0.3}, {0, 0, -0.6}, "trim", "Metal"), p("Blade", {0.14, 0.62, 4.2}, {0, 0, -2.85}, "head", "metal"),
		p("Tip", {0.14, 0.36, 0.5}, {0, 0, -5.15}, "head", "metal"), p("Fuller", {0.16, 0.12, 3.4}, {0, 0, -2.7}, "glow", "Neon")},
	dagger = {p("Grip", {0.18, 0.18, 0.6}, {0, 0, 0.05}, "leather", "Fabric"), p("Pommel", {0.24, 0.24, 0.24}, {0, 0, 0.42}, "trim", "Metal", "Ball"),
		p("Guard", {0.55, 0.14, 0.16}, {0, 0, -0.32}, "trim", "Metal"), p("Blade", {0.08, 0.26, 1.3}, {0, 0, -1.05}, "head", "metal"),
		p("Tip", {0.08, 0.14, 0.3}, {0, 0, -1.85}, "head", "metal"), p("Gem", {0.16, 0.16, 0.16}, {0, 0.12, -0.32}, "glow", "Neon", "Ball")},
	maul = {p("Haft", {0.22, 0.22, 3.2}, {0, 0, -0.8}, "wood", "Wood"), p("Head", {0.8, 1.4, 0.8}, {0, 0, -2.65}, "head", "metal"),
		p("BandTop", {0.86, 0.18, 0.86}, {0, 0.5, -2.65}, "trim", "Metal"), p("BandBottom", {0.86, 0.18, 0.86}, {0, -0.5, -2.65}, "trim", "Metal"),
		p("Butt", {0.3, 0.3, 0.3}, {0, 0, 0.85}, "trim", "Metal"), p("Core", {0.82, 0.3, 0.3}, {0, 0, -2.65}, "glow", "Neon")},
	glaive = {p("Shaft", {0.18, 0.18, 5}, {0, 0, -1.2}, "wood", "Wood"), p("Collar", {0.3, 0.3, 0.32}, {0, 0, -3.75}, "trim", "Metal"),
		p("Blade", {0.1, 0.7, 1.6}, {0, 0.15, -4.65}, "head", "metal"), p("Tip", {0.1, 0.34, 0.5}, {0, 0.3, -5.6}, "head", "metal"),
		p("Butt", {0.26, 0.26, 0.3}, {0, 0, 1.35}, "trim", "Metal"), p("Edge", {0.12, 0.1, 1.5}, {0, 0.5, -4.65}, "glow", "Neon")},
	-- Bows sit in the left hand: limbs along the grip axis, a pale string behind them.
	shortbow = {p("Grip", {0.26, 0.26, 0.6}, {0, 0, 0}, "leather", "Fabric"), p("UpperLimb", {0.16, 0.2, 1.5}, {0, 0.14, -1.0}, "head", "Wood"),
		p("LowerLimb", {0.16, 0.2, 1.5}, {0, 0.14, 1.0}, "head", "Wood"), p("UpperNock", {0.2, 0.24, 0.22}, {0, 0.3, -1.8}, "trim", "Metal"),
		p("LowerNock", {0.2, 0.24, 0.22}, {0, 0.3, 1.8}, "trim", "Metal"), p("String", {0.04, 0.04, 3.6}, {0, 0.42, 0}, "string", "SmoothPlastic"),
		p("Gem", {0.18, 0.18, 0.18}, {0, -0.16, 0}, "glow", "Neon", "Ball")},
	longbow = {p("Grip", {0.26, 0.26, 0.6}, {0, 0, 0}, "leather", "Fabric"), p("UpperLimb", {0.18, 0.22, 2.2}, {0, 0.18, -1.35}, "head", "Wood"),
		p("LowerLimb", {0.18, 0.22, 2.2}, {0, 0.18, 1.35}, "head", "Wood"), p("UpperNock", {0.22, 0.26, 0.24}, {0, 0.38, -2.5}, "trim", "Metal"),
		p("LowerNock", {0.22, 0.26, 0.24}, {0, 0.38, 2.5}, "trim", "Metal"), p("String", {0.04, 0.04, 5.0}, {0, 0.52, 0}, "string", "SmoothPlastic"),
		p("Gem", {0.2, 0.2, 0.2}, {0, -0.18, 0}, "glow", "Neon", "Ball")},
	staff = {p("Shaft", {0.22, 0.22, 5.2}, {0, 0, -0.9}, "wood", "Wood"), p("Cradle", {0.5, 0.5, 0.3}, {0, 0, -3.5}, "trim", "Metal"),
		p("Orb", {0.62, 0.62, 0.62}, {0, 0, -3.88}, "head", "Neon", "Ball"), p("Halo", {0.82, 0.82, 0.08}, {0, 0, -3.88}, "trim", "Metal"),
		p("Butt", {0.28, 0.28, 0.26}, {0, 0, 1.7}, "trim", "Metal"), p("Wrap", {0.26, 0.26, 0.5}, {0, 0, 0}, "leather", "Fabric")},
	wand = {p("Rod", {0.12, 0.12, 1.5}, {0, 0, -0.6}, "wood", "Wood"), p("Grip", {0.16, 0.16, 0.5}, {0, 0, 0.1}, "leather", "Fabric"),
		p("Band", {0.18, 0.18, 0.08}, {0, 0, -0.2}, "trim", "Metal"), p("Tip", {0.26, 0.26, 0.26}, {0, 0, -1.42}, "head", "Neon", "Ball")},
	shield = {p("Board", {1.7, 2.1, 0.22}, {0, 0.2, -0.45}, "head", "metal"), p("Rim", {1.85, 0.16, 0.26}, {0, 1.25, -0.45}, "trim", "Metal"),
		p("RimLow", {1.85, 0.16, 0.26}, {0, -0.85, -0.45}, "trim", "Metal"), p("Boss", {0.5, 0.5, 0.3}, {0, 0.2, -0.62}, "trim", "Metal", "Ball"),
		p("Strap", {0.3, 0.8, 0.12}, {0, 0.2, -0.28}, "leather", "Fabric"), p("Sigil", {0.3, 0.3, 0.05}, {0, 0.8, -0.58}, "glow", "Neon")},
	pickaxe = {p("Handle", {0.22, 0.22, 3}, {0, 0, -1.2}, "wood", "Wood"), p("Wrap", {0.26, 0.26, 0.6}, {0, 0, 0}, "leather", "Fabric"),
		p("Socket", {0.38, 0.42, 0.44}, {0, 0, -2.55}, "trim", "Metal"), p("Head", {0.3, 2, 0.32}, {0, 0, -2.55}, "head", "metal"),
		p("Spike", {0.2, 0.5, 0.2}, {0, -1.15, -2.55}, "head", "metal"), p("Pick", {0.2, 0.42, 0.2}, {0, 1.12, -2.55}, "head", "metal"),
		p("Gem", {0.2, 0.2, 0.2}, {0.2, 0, -2.55}, "glow", "Neon", "Ball")},
	hatchet = {p("Handle", {0.22, 0.22, 2.6}, {0, 0, -1}, "wood", "Wood"), p("Wrap", {0.26, 0.26, 0.55}, {0, 0, 0}, "leather", "Fabric"),
		p("Blade", {0.15, 0.9, 0.75}, {0, 0.4, -2.05}, "head", "metal"), p("Edge", {0.17, 0.12, 0.85}, {0, 0.88, -2.05}, "trim", "Metal"),
		p("Poll", {0.26, 0.32, 0.42}, {0, -0.15, -2.05}, "head", "metal"), p("Gem", {0.18, 0.18, 0.18}, {0.12, 0.3, -2.05}, "glow", "Neon", "Ball")},
	rod = {p("Grip", {0.24, 0.24, 1.2}, {0, 0, -0.3}, "leather", "Fabric"), p("Rod", {0.12, 0.12, 5}, {0, 0, -3.4}, "head", "Wood"),
		p("Reel", {0.4, 0.4, 0.4}, {0, -0.28, -0.2}, "trim", "Metal", "Ball"), p("Guide", {0.18, 0.18, 0.08}, {0, 0, -2.2}, "trim", "Metal"),
		p("Tip", {0.08, 0.08, 0.3}, {0, 0, -6.0}, "trim", "Metal"), p("Line", {0.03, 1.6, 0.03}, {0, -0.8, -6.1}, "string", "SmoothPlastic"),
		p("Bobber", {0.22, 0.22, 0.22}, {0, -1.62, -6.1}, "glow", "Neon", "Ball")},
	hoe = {p("Handle", {0.2, 0.2, 3.2}, {0, 0, -1.3}, "wood", "Wood"), p("Wrap", {0.24, 0.24, 0.55}, {0, 0, 0}, "leather", "Fabric"),
		p("Collar", {0.28, 0.32, 0.3}, {0, 0, -2.85}, "trim", "Metal"), p("Neck", {0.14, 0.4, 0.14}, {0, -0.2, -2.85}, "head", "metal"),
		p("Blade", {0.7, 0.5, 0.12}, {0, -0.6, -2.85}, "head", "metal"), p("Gem", {0.16, 0.16, 0.16}, {0, 0.12, -2.85}, "glow", "Neon", "Ball")},
	hammer = {p("Handle", {0.2, 0.2, 1.6}, {0, 0, -0.5}, "wood", "Wood"), p("Head", {0.42, 0.9, 0.42}, {0, 0, -1.25}, "head", "metal"),
		p("Face", {0.46, 0.14, 0.46}, {0, 0.46, -1.25}, "trim", "Metal")},
}

-- Resolved model spec for an item: {id, class, hand, parts = {{name, size, offset, colour, material, shape}}}.
-- "metal" resolves to the tier's metal; glow parts are dropped below Epic.
function H.spec(id)
	local def = Data.Items[id or ""]
	local class = H.classOf(def)
	if not class then return nil end
	local look = H.look(def)
	local colours = {head = look.head, trim = look.trim, wood = H.WOOD, leather = H.LEATHER, string = H.STRING, glow = look.glow}
	local parts = {}
	for _, part in ipairs(H.SHAPES[class]) do
		local colour = colours[part.c]
		if colour and #parts < H.MAX_PARTS then
			table.insert(parts, {name = part.n, size = part.s, offset = part.o, colour = colour,
				material = if part.m == "metal" then look.metal else part.m, shape = part.shape})
		end
	end
	return {id = id, class = class, hand = H.hand(class), parts = parts, look = look}
end

-- Ownership + requirement check for `hold`. raw: "<itemId>", "~<itemId>" (a
-- temporary auto switch), "" / "none" (empty hands). meets(p, requires) -> bool, missing.
function H.validate(p, raw, meets)
	if raw == nil or raw == "" or raw == "none" then return true, "none", false end
	if type(raw) ~= "string" or #raw > 65 then return false, "Choose an item to hold." end
	local temporary = raw:sub(1, 1) == "~"
	local id = if temporary then raw:sub(2) else raw
	local def = Data.Items[id]
	if not def then return false, "Choose an item to hold." end
	if not H.classOf(def) then return false, (def.name or id) .. " can't be held." end
	if ((p.items or {})[id] or 0) < 1 then return false, "You do not own " .. (def.name or id) .. "." end
	if meets then
		local allowed, missing = meets(p, def.requires)
		if not allowed then return false, (def.name or id) .. " requires " .. tostring(missing) .. "." end
	end
	return true, id, temporary
end
-- What the character visibly holds: a temporary auto switch (autoId, kept out
-- of the profile so it is never saved) when still valid, else p.held when still
-- valid ("none" = empty hands), else the equipped weapon (slot 1).
-- Returns id or nil, and true when the id is the temporary auto switch.
function H.resolve(p, meets, autoId)
	if type(autoId) == "string" and autoId ~= "" then
		local ok, id = H.validate(p, autoId, meets)
		if ok and id ~= "none" then return id, true end
	end
	local held = p.held
	if held == "none" then return nil end
	if type(held) == "string" then
		local ok, id = H.validate(p, held, meets)
		if ok and id ~= "none" then return id end
	end
	local weapon = type(p.equipment) == "table" and p.equipment.weapon or nil
	if type(weapon) == "string" and H.validate(p, weapon, meets) then return weapon end
	return nil
end
-- Hotbar layout (slots 3-9) is saved as string keys (DataStore-safe): p.hotbar = {s3 = id, ...}.
function H.parseSlot(raw)
	if type(raw) ~= "string" or #raw > 70 then return nil end
	local slot, id = raw:match("^(%d):(.*)$")
	slot = tonumber(slot)
	if not slot or not table.find(H.FREE_SLOTS, slot) then return nil end
	return slot, id
end
function H.hotbarString(p)
	local bar = type(p.hotbar) == "table" and p.hotbar or {}
	local out = table.create(#H.FREE_SLOTS, "")
	for i, slot in ipairs(H.FREE_SLOTS) do
		local id = bar["s" .. slot]
		out[i] = if H.assignable(p, id) then id else ""
	end
	return table.concat(out, ",")
end
-- Any owned item can sit in a free slot (SkyBlock style: tools, weapons, food,
-- blocks with their stack count); only holdable ones go into the hand.
function H.assignable(p, id)
	return type(id) == "string" and Data.Items[id] ~= nil and ((p.items or {})[id] or 0) > 0
end
-- Token bucket (hold / hotbarSet): b = {tokens, stamp}.
function H.take(b, now)
	b.tokens = math.min(H.BURST, (b.tokens or H.BURST) + (now - (b.stamp or now)) * H.RATE)
	b.stamp = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end
-- Every holdable item id (sorted), for tests and the hotbar picker.
function H.all()
	local out = {}
	for id in pairs(Data.Items) do if H.holdable(id) then table.insert(out, id) end end
	table.sort(out)
	return out
end
end
-- <<< END Held items & swings <<<
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- >>> World Art & Regions (World Art & Regions team; self-contained section) >>>
-- docs/DEPTH-CONTRACT.md §30. Region identity (display names, palettes,
-- landmarks, ambience, entry banners), regional questgivers, shopkeepers and
-- townsfolk (Data.Townsfolk.RegionFolkOrder), the regional quest chains
-- (appended to Data.Quests with `giver`), and warp scrolls (fast travel: learn
-- a region's scroll once, then the Warp Keeper sends you there).
-- New objective kinds (server: Journal.measure; rejoin-safe in p.regionQuests):
--   talk  {npc=<role>}         speak to that NPC while the quest is accepted (verb rqTalk)
--   visit {landmark=<id>}      survey that landmark's prompt (IsleAction "landmark")
-- Quests with a giver are accepted at the giver (rqAccept) and handed in there
-- (rqClaim) or from the Journal once accepted. rewards.unlock.warp = region also
-- unlocks that region's warp.
------------------------------------------------------------------------------
do
local RA = {}
Data.RegionArt = RA
-- Generic display names get Aether-Isles names; ids stay stable for saves.
local RENAMES = {Hub="Compass Quay", Meadow="Sunwheel Downs", Quarry="Brassfall Cay"}
for id, name in pairs(RENAMES) do
	local r = Data.RegionById[id]
	if r then r.name = name end
	local d = Data.DiaryByRegion and Data.DiaryByRegion[id]
	if d then d.name = name .. " Diary" end
end
-- Per region: banner epithet, palette (ground, accent, glow), landmark (id,
-- display name, world shape, island), ambience (client particle kind; sound =
-- optional asset id hook, "" = none).
RA.Regions = {
	Hub={epithet="Heart of the Skyway",palette={"C9B994","DBAD65","9DF3D7"},
		landmark={id="CompassSpire",name="The Compass Spire",shape="CompassTower",isle="Compass Quay"},ambience={particles="motes",sound=""}},
	Meadow={epithet="Where the Sunwheel turns",palette={"8DB86E","E9C46A","FFE08A"},
		landmark={id="Sunwheel",name="The Sunwheel Mill",shape="Windmill",isle="Meadow Reach"},ambience={particles="pollen",sound=""}},
	Quarry={epithet="Copper, brass and smouldering stone",palette={"9C9682","FF8A3D","FFB86B"},
		landmark={id="EmberCaldera",name="The Ember Caldera",shape="Caldera",isle="Cinder Shelf"},ambience={particles="embers",sound=""}},
	Skyreach={epithet="Highest of the charted isles",palette={"96ACAB","39898E","BFF4FF"},
		landmark={id="SunkenObservatory",name="The Sunken Observatory",shape="Observatory",isle="Skyreach"},ambience={particles="wind",sound=""}},
	Windpine={epithet="The grove that whispers",palette={"5F8A57","9BD18B","E8D98E"},
		landmark={id="AetherheartTree",name="The Aetherheart",shape="AetherheartTree",isle="Windpine Grove"},ambience={particles="leaves",sound=""}},
	Gloomhollow={epithet="Lanterns below the light",palette={"3A3F52","B59CFF","7FD3C4"},
		landmark={id="VoidglassSpire",name="The Voidglass Spire",shape="CrystalSpire",isle="Gloomhollow Caverns"},ambience={particles="spores",sound=""}},
	Tidewater={epithet="Skylakes and singing reefs",palette={"D9C9A0","5EC8D8","E76F7B"},
		landmark={id="ShoalLight",name="The Shoal Light",shape="Lighthouse",isle="Tidewater Shoals"},ambience={particles="spray",sound=""}},
	Tempest={epithet="The storm that never breaks",palette={"4A5266","BFD7FF","8FB8D6"},
		landmark={id="StormCrown",name="The Storm Crown",shape="StormSpire",isle="Tempest Spire"},ambience={particles="sparks",sound=""}},
	ShatteredCrown={epithet="A sky-crown in pieces",palette={"6E6A8C","F2D27A","B59CFF"},
		landmark={id="BrokenCrown",name="The Broken Crown",shape="Obelisk",isle="The Shattered Crown"},ambience={particles="glints",sound=""}},
}
-- Island banners: every static island's entry epithet (the banner title is the island's own name).
RA.Isles = {
	["Compass Quay"]="Sky Harbor · Market Row · Artisans' Rise",["Guild Terrace"]="Stations, the Guild Hall and the Skyway",
	["Warden Reach"]="Waystones around the Shellwarden",["Mosswake Grove"]="Mossy timber and moonleaf beds",
	["Meadow Reach"]="Sunwheat terraces under the Sunwheel",["Brassfall Quarry"]="The crane sings over the copper seams",
	["Cinder Shelf"]="Ash terraces around the Ember Caldera",["Skyreach"]="Thin air, golems and the Sunken Observatory",
	["Windpine Grove"]="Towering windpines round the Aetherheart",["Gloomhollow Caverns"]="Voidstone grottoes and glowshrooms",
	["Tidewater Shoals"]="Sandbars, lagoons and the Shoal Light",["Tempest Spire"]="Crystal pylons crackling in the gale",
	["The Shattered Crown"]="Islets of a broken sky-crown",
}
RA.LandmarkById = {}
for region, art in pairs(RA.Regions) do
	local r = Data.RegionById[region]
	art.title = r and r.name or region
	art.landmark.region = region
	RA.LandmarkById[art.landmark.id] = art.landmark
end
RA.Order = {"Hub","Meadow","Quarry","Skyreach","Windpine","Gloomhollow","Tidewater","Tempest","ShatteredCrown"}
RA.SURVEY_RADIUS = 14 -- studs from a landmark's survey prompt that count as a visit
RA.TALK_RADIUS = 16   -- studs from an NPC that count as speaking to them

------------------------------------------------------------------------------
-- Warp scrolls: read once to learn a region's warp; the Warp Keeper carries
-- you to its entrance anchor afterwards.
------------------------------------------------------------------------------
RA.WARP_COOLDOWN = 20
RA.Warps = {
	{region="Hub",anchor="Waypoint_SkyHarbor",price=150},
	{region="Meadow",anchor="Waypoint_Entrance_Meadow",price=300},
	{region="Quarry",anchor="Waypoint_Entrance_CinderShelf",price=300},
	{region="Skyreach",anchor="Waypoint_Entrance_Skyreach",price=1200},
	{region="Windpine",anchor="Waypoint_Entrance_Windpine",price=1500},
	{region="Gloomhollow",anchor="Waypoint_Entrance_Gloomhollow",price=4000},
	{region="Tidewater",anchor="Waypoint_Entrance_Tidewater",price=4000},
	{region="Tempest",anchor="Waypoint_Entrance_Tempest",price=9000},
	{region="ShatteredCrown",anchor="Waypoint_Entrance_ShatteredCrown",price=20000},
}
RA.WarpByRegion = {}
for _, w in ipairs(RA.Warps) do
	w.scroll = "WarpScroll" .. w.region
	RA.WarpByRegion[w.region] = w
	local name = Data.RegionById[w.region].name
	item(w.scroll,{name="Warp Scroll: "..name,kind="material",category="warp",rarity="Rare",color="C77DFF",value=math.floor(w.price/10),
		description="Read it with the Warp Keeper to learn the warp to "..name..". Learned once, used forever."})
end

------------------------------------------------------------------------------
-- Regional folk: questgivers, shopkeepers, the Warp Keeper and townsfolk.
------------------------------------------------------------------------------
local folk = {
	-- Compass Quay
	{role="WarpKeeper",region="Hub",name="Ilsabet Vanewright",title="Warp Keeper",portrait="🌀",kind="warp",
		look={skin="D1A27A",shirt="4B2C7A",pants="241A33",shoes="17111F",accent="C77DFF",hair="F2E8D5",hat="tophat",held="staff",cape="2E1A4A",spectacles=true},
		greet="Every isle has a thread, wayfarer, and I hold the spindle. Learn a warp scroll and I'll send you along its thread."},
	{role="Lamplighter",region="Hub",name="Corwin Tallowmere",title="Quay Lamplighter",portrait="🕯",
		look={skin="F1C27D",shirt="6D4C41",pants="3E2723",shoes="1B1B1B",accent="FFD166",hair="8D6E63",hat="cap",held="lantern",beard=true},
		greet="Sixty lamps on the Quay and every one wants oil by dusk. Spare a hand?"},
	{role="QuayCrier",region="Hub",name="Mirelle Dunfeather",title="Town Crier",portrait="📣",kind="townsfolk",
		look={skin="FFDBAC",shirt="1E88E5",pants="F2E8D5",shoes="5D4037",accent="FFC107",hair="A1887F",hat="feather",held="scroll"},
		greet="News of the isles! The Sunwheel turns, the Caldera smoulders and the Shoal Light still shines. Folk in regional colours always need a hand!"},
	-- Sunwheel Downs
	{role="Millwarden",region="Meadow",name="Hesper Furrowmilde",title="Millwarden of the Sunwheel",portrait="🌾",
		look={skin="E0AC69",shirt="C9A24E",pants="5D4037",shoes="3E2723",accent="FFE08A",hair="D7CCC8",hat="wayfarer",held="crate",apron="F5E6C8"},
		greet="The Sunwheel grinds for every oven on the Quay. When she stops, the isles go hungry."},
	{role="Shepherd",region="Meadow",name="Bram Oatley",title="Downs Shepherd",portrait="🐑",
		look={skin="C68642",shirt="7CB342",pants="4E342E",shoes="3E2723",accent="F9CC77",hair="5D4037",hat="hood",held="staff",cape="558B2F",beard=true},
		greet="Boars in the barley again. I'd chase 'em myself if my knees were younger."},
	{role="SeedSeller",region="Meadow",name="Tilly Sackbright",title="Seed-seller",portrait="🌱",kind="shop",
		look={skin="FFDBAC",shirt="F06292",pants="6D4C41",shoes="4E342E",accent="AED581",hair="FF8A65",hat="cap",held="crate",apron="FFF3E0"},
		greet="Tonics, tea and the odd trinket, all grown on the Downs!",
		shop={{item="Tonic",price=12,amount=1},{item="CookedFish",price=20,amount=1},{item="WarpScrollMeadow",price=360,amount=1}}},
	-- Brassfall Cay
	{role="CalderaWatcher",region="Quarry",name="Garrick Slagmere",title="Caldera Watcher",portrait="🌋",
		look={skin="8D5524",shirt="BF360C",pants="3E2723",shoes="1B1B1B",accent="FF8A3D",hair="212121",hat="goggles",held="pickaxe",beard=true},
		greet="She's breathing slow today, the Caldera. That's when the mites come up to warm their bellies."},
	{role="CraneHand",region="Quarry",name="Pim Brassbuckle",title="Crane-hand",portrait="🏗",
		look={skin="F1C27D",shirt="FFB300",pants="37474F",shoes="263238",accent="546E7A",hair="6D4C41",hat="minerhelm",held="hammer"},
		greet="The old crane's held together with hope and rivets. Mostly hope."},
	{role="ToolTrader",region="Quarry",name="Dorra Flintwick",title="Tool-trader",portrait="⛏",kind="shop",
		look={skin="A0522D",shirt="5D4037",pants="2E2A26",shoes="1E1A16",accent="D4A84B",hair="9E9E9E",hat="cap",held="ledger",apron="8D6E63",spectacles=true},
		greet="Alloy, dust and a sturdy scroll. Everything a quarry hand needs.",
		shop={{item="AlloyIngot",price=45,amount=1},{item="ArcaneDust",price=30,amount=1},{item="WarpScrollQuarry",price=360,amount=1}}},
	-- Skyreach
	{role="Astronomer",region="Skyreach",name="Aurelie Starling",title="Astronomer of the Observatory",portrait="🔭",
		look={skin="FFDBAC",shirt="1A237E",pants="283593",shoes="1A1A2E",accent="BFF4FF",hair="ECEFF1",hat="hood",held="scroll",cape="0D1B4A",spectacles=true},
		greet="From the Observatory you can see every isle at once. And something else, lately. Something moving."},
	{role="Golemwright",region="Skyreach",name="Tobias Gearwhit",title="Golemwright",portrait="⚙",
		look={skin="E0AC69",shirt="795548",pants="4E342E",shoes="3E2723",accent="D4A84B",hair="BDBDBD",hat="goggles",held="hammer",apron="A1887F"},
		greet="Brass golems tick in unison. Find out why and you'll know more than the guild does."},
	{role="UpdraftSupplier",region="Skyreach",name="Venn Lofthook",title="Updraft Supplier",portrait="🪁",kind="shop",
		look={skin="C68642",shirt="00838F",pants="263238",shoes="212121",accent="80DEEA",hair="3E2723",hat="feather",held="rod"},
		greet="Rope, feathers and courage. Two of those I sell.",
		shop={{item="StormFeather",price=60,amount=1},{item="Tonic",price=16,amount=2},{item="WarpScrollSkyreach",price=1440,amount=1}}},
	-- Windpine
	{role="CanopyWarden",region="Windpine",name="Wren Tallbough",title="Canopy Warden",portrait="🍃",
		look={skin="8D5524",shirt="2E7D32",pants="33691E",shoes="1B5E20",accent="C5E1A5",hair="4E342E",hat="feather",held="staff",cape="1B5E20"},
		greet="Walk softly. The Aetherheart listens through every root on this isle."},
	{role="Sawyer",region="Windpine",name="Osric Pinewhistle",title="Grove Sawyer",portrait="🪓",
		look={skin="F1C27D",shirt="B71C1C",pants="3E2723",shoes="1B1B1B",accent="FFCDD2",hair="BF360C",hat="cap",held="saw",beard=true},
		greet="I only fell what the Warden marks. The stalkers don't share my manners."},
	{role="Forager",region="Windpine",name="Fenna Mossglove",title="Forager",portrait="🍄",kind="shop",
		look={skin="FFDBAC",shirt="827717",pants="5D4037",shoes="4E342E",accent="DCE775",hair="FFB74D",hat="hood",held="crate",cape="9E9D24"},
		greet="Picked at dawn, sold by noon, and none of it poisonous. Mostly.",
		shop={{item="MightDraught",price=180,amount=1},{item="Tonic",price=16,amount=2},{item="WarpScrollWindpine",price=1800,amount=1}}},
	-- Gloomhollow
	{role="CrystalReader",region="Gloomhollow",name="Sable Quillmoth",title="Crystal-reader",portrait="🔮",
		look={skin="D1A27A",shirt="311B92",pants="1A1033",shoes="0D0A14",accent="B59CFF",hair="212121",hat="hood",held="lantern",cape="4527A0"},
		greet="The Voidglass Spire hums a little louder each night. I write down every note."},
	{role="TunnelForeman",region="Gloomhollow",name="Drogan Ashlamp",title="Tunnel Foreman",portrait="⛑",
		look={skin="6D4C41",shirt="455A64",pants="263238",shoes="1C1C1C",accent="FFAB40",hair="9E9E9E",hat="helm",held="pickaxe",beard=true},
		greet="Three tunnels lost to silk this month. I need someone with a sharp blade and a steady lamp."},
	{role="LanternSeller",region="Gloomhollow",name="Mott Candlewick",title="Lantern-seller",portrait="🏮",kind="shop",
		look={skin="FFDBAC",shirt="4E342E",pants="3E2723",shoes="212121",accent="FFD54F",hair="FFFFFF",hat="tricorn",held="lantern",spectacles=true},
		greet="Light's the only currency down here that never loses value.",
		shop={{item="ArcaneDust",price=28,amount=2},{item="Shard",price=90,amount=1},{item="WarpScrollGloomhollow",price=4800,amount=1}}},
	-- Tidewater
	{role="Lightkeeper",region="Tidewater",name="Marisol Brinehart",title="Keeper of the Shoal Light",portrait="🗼",
		look={skin="C68642",shirt="0277BD",pants="01579B",shoes="263238",accent="FFF59D",hair="3E2723",hat="souwester",held="lantern"},
		greet="The Shoal Light has never gone dark. Not once in three hundred years. I'd like to keep it that way."},
	{role="NetMender",region="Tidewater",name="Kel Driftnet",title="Net-mender",portrait="🪢",
		look={skin="8D5524",shirt="00695C",pants="37474F",shoes="263238",accent="B2DFDB",hair="1B1B1B",hat="tricorn",held="rod",beard=true},
		greet="Lurkers chew through a net a night. Lanternrays are worth the trouble, mind."},
	{role="Fishmonger",region="Tidewater",name="Opal Saltreed",title="Fishmonger",portrait="🐟",kind="shop",
		look={skin="F1C27D",shirt="E1F5FE",pants="0288D1",shoes="01579B",accent="E76F7B",hair="FFCC80",hat="souwester",held="crate",apron="B3E5FC"},
		greet="Caught this morning, smoked by lunch. Best on the Shoals!",
		shop={{item="CookedFish",price=32,amount=2},{item="Tonic",price=14,amount=1},{item="WarpScrollTidewater",price=4800,amount=1}}},
	-- Tempest
	{role="StormScribe",region="Tempest",name="Thessaly Vaunt",title="Storm-scribe",portrait="⚡",
		look={skin="FFDBAC",shirt="263238",pants="1C2833",shoes="0B0F14",accent="BFD7FF",hair="CFD8DC",hat="hood",held="scroll",cape="37474F"},
		greet="Every bolt that strikes the Crown, I record. The pattern is almost a word."},
	{role="SpireSentinel",region="Tempest",name="Captain Rook Halberd",title="Spire Sentinel",portrait="🛡",
		look={skin="A0522D",shirt="37474F",pants="263238",shoes="1C1C1C",accent="90CAF9",hair="1B1B1B",hat="helm",held="sword",cape="1565C0",beard=true},
		greet="Hold the line, hold the spire. Do you hold a blade, or just your breath?"},
	{role="Stormglazier",region="Tempest",name="Ivo Sparkwright",title="Stormglazier",portrait="💠",kind="shop",
		look={skin="E0AC69",shirt="5C6BC0",pants="283593",shoes="1A237E",accent="E1F5FE",hair="FFEE58",hat="goggles",held="ledger"},
		greet="Stormglass, blown in lightning. Mind your fingers.",
		shop={{item="Stormglass",price=220,amount=1},{item="MightDraught",price=200,amount=1},{item="WarpScrollTempest",price=10800,amount=1}}},
	-- The Shattered Crown
	{role="CrownArchivist",region="ShatteredCrown",name="Seraphine Gildmourn",title="Crown Archivist",portrait="👑",
		look={skin="D1A27A",shirt="6A1B9A",pants="38006B",shoes="1A0033",accent="F2D27A",hair="FFF8E1",hat="tophat",held="scroll",cape="4A148C"},
		greet="Every shard of the Crown remembers the hand that broke it. I intend to learn whose."},
	{role="Shardkeeper",region="ShatteredCrown",name="Halvard Riftwatch",title="Warden of the Rift",portrait="🗡",
		look={skin="8D5524",shirt="4A148C",pants="1A0033",shoes="0D0014",accent="CE93D8",hair="E0E0E0",hat="helm",held="sword",cape="7B1FA2",beard=true},
		greet="The rift spits out horrors every hour. I count them. I'd rather count fewer."},
	{role="RelicBroker",region="ShatteredCrown",name="Nim Glintwright",title="Relic Broker",portrait="💎",kind="shop",
		look={skin="FFDBAC",shirt="F9A825",pants="4E342E",shoes="3E2723",accent="FFF59D",hair="5D4037",hat="feather",held="ledger",spectacles=true},
		greet="Relics, shards, curios. Nothing cursed. Probably.",
		shop={{item="Stormglass",price=200,amount=2},{item="Shard",price=80,amount=2},{item="WarpScrollShatteredCrown",price=24000,amount=1}}},
}
RA.Folk = folk
RA.FolkByRole = {}
for _, f in ipairs(folk) do RA.FolkByRole[f.role] = f end

------------------------------------------------------------------------------
-- Regional quest chains (appended to Data.Quests; giver = folk role).
------------------------------------------------------------------------------
local function ql(...) return {...} end
local function K(m, n) return {kind="kills",monster=m,count=n} end
local function H(i, n) return {kind="have",item=i,count=n,consume=true} end
local function Cl(i, n) return {kind="collect",item=i,count=n} end
local function G(r, n) return {kind="gather",region=r,count=n} end
local function TALK(role) return {kind="talk",npc=role} end
local function VISIT(id) return {kind="visit",landmark=id} end
local function Q(id) return {kind="quest",quest=id} end
local function LV(skill, n) return {kind="level",skill=skill,level=n} end
local EXCL = {"Dungeoneering","Carpentry"}
RA.Quests = {
	{id="SkywayCharter",title="Charting the Skyway",giver="WarpKeeper",region="Hub",
		story="Ilsabet wants a fresh wayfarer to walk the Quay's threads: meet the Lamplighter and survey the Compass Spire.",
		requires=ql({kind="contracts",count=1}),objectives=ql(TALK("Lamplighter"),VISIT("CompassSpire")),
		rewards={coins=300,points=1,items={WarpScrollMeadow=1}}},
	{id="LampsOfTheQuay",title="Lamps of the Quay",giver="Lamplighter",region="Hub",
		story="Corwin needs timber for new posts and ore for lamp brackets before the Quay goes dark.",
		requires=ql(Q("SkywayCharter")),objectives=ql(H("Timber",15),H("Ore",10)),
		rewards={coins=400,points=1,lamp={xp=500,skills={"Woodcutting","Mining"}}}},
	{id="SunwheelTurns",title="The Sunwheel Turns",giver="Millwarden",region="Meadow",
		story="Hesper's mill has seized. Survey the Sunwheel, bring sunwheat for the stones and fetch Bram's help with the sails.",
		requires=ql({kind="contracts",count=2}),objectives=ql(VISIT("Sunwheel"),Cl("Sunwheat",30),TALK("Shepherd")),
		rewards={coins=600,points=1,xp={Farming=800}}},
	{id="BoarsInTheBarley",title="Boars in the Barley",giver="Shepherd",region="Meadow",
		story="Bram's barley rows are trampled flat. Drive the boars off and bring back hides for new sail-cloth.",
		requires=ql(Q("SunwheelTurns")),objectives=ql(K("BramblebackBoar",12),H("BeastHide",3)),
		rewards={coins=700,points=1,items={MightDraught=1}}},
	{id="MillersFeast",title="The Miller's Feast",giver="Millwarden",region="Meadow",
		story="With the Sunwheel turning again, Hesper throws a harvest feast. She needs sunwheat and herbs for the tables.",
		requires=ql(Q("BoarsInTheBarley")),objectives=ql(H("Sunwheat",40),H("Herb",20)),
		rewards={coins=900,points=2,lamp={xp=1200,skills={"Farming","Cooking"}},unlock={warp="Meadow"}}},
	{id="CalderaWatch",title="Caldera Watch",giver="CalderaWatcher",region="Quarry",
		story="Garrick needs eyes on the Ember Caldera while the cinder mites swarm its rim.",
		requires=ql({kind="contracts",count=3}),objectives=ql(VISIT("EmberCaldera"),K("CinderMite",10)),
		rewards={coins=800,points=1,xp={Mining=1000}}},
	{id="CraneRepairs",title="Rivets and Hope",giver="CraneHand",region="Quarry",
		story="Pim's crane needs alloy rivets and a load of fresh ore to test the winch. Garrick signs off on the lift.",
		requires=ql({kind="contracts",count=3}),objectives=ql(H("AlloyIngot",5),Cl("Ore",60),TALK("CalderaWatcher")),
		rewards={coins=900,points=1,unlock={warp="Quarry"}}},
	{id="SlagAndEmber",title="Slag and Ember",giver="CalderaWatcher",region="Quarry",
		story="The crawlers are tunnelling under the Caldera. Thin them and bring brassite to shore up the vents.",
		requires=ql(Q("CalderaWatch"),Q("CraneRepairs"),LV("Mining",15)),objectives=ql(K("ShaleCrawler",20),H("Brassite",25)),
		rewards={coins=1200,points=2,lamp={xp=2000,skills={"Mining","Smithing"}}}},
	{id="LensOfTheHeights",title="Lens of the Heights",giver="Astronomer",region="Skyreach",
		story="Aurelie's great lens is fogged with golem grit. Survey the Observatory and gather around the heights while she cleans it.",
		requires=ql({kind="contracts",count=6}),objectives=ql(VISIT("SunkenObservatory"),G("Skyreach",15)),
		rewards={coins=1200,points=1,unlock={warp="Skyreach"}}},
	{id="TickingHearts",title="Ticking Hearts",giver="Golemwright",region="Skyreach",
		story="Tobias wants to hear a golem's heart stop. Break a few, then tell Aurelie what the rhythm sounded like.",
		requires=ql({kind="contracts",count=6},LV("Combat",15)),objectives=ql(K("BrassGolem",8),TALK("Astronomer")),
		rewards={coins=1500,points=1,xp={Smithing=1500}}},
	{id="StarChart",title="The Star Chart",giver="Astronomer",region="Skyreach",
		story="Whatever moves past the Observatory rides the updrafts. Harriers fly the same paths; follow them and pluck their feathers.",
		requires=ql(Q("LensOfTheHeights"),Q("TickingHearts")),objectives=ql(K("StormHarrier",10),Cl("StormFeather",15)),
		rewards={coins=2000,points=2,lamp={xp=3000,skills={"Combat","Mining","Smithing"}}}},
	{id="HeartOfTheGrove",title="Heart of the Grove",giver="CanopyWarden",region="Windpine",
		story="Wren asks you to lay a hand on the Aetherheart and gather from the grove so it knows your name.",
		requires=ql(LV("Woodcutting",10)),objectives=ql(VISIT("AetherheartTree"),G("Windpine",25)),
		rewards={coins=1200,points=1,xp={Woodcutting=1500},unlock={warp="Windpine"}}},
	{id="StalkerInTheRoots",title="Stalker in the Roots",giver="Sawyer",region="Windpine",
		story="Osric's crews won't work while bark stalkers lurk. Clear them and stack emberoak for the lodge.",
		requires=ql(LV("Woodcutting",10)),objectives=ql(K("BarkStalker",10),Cl("EmberoakLog",30)),
		rewards={coins=1500,points=1,items={MightDraught=2}}},
	{id="WindsongOath",title="The Windsong Oath",giver="CanopyWarden",region="Windpine",
		story="Gale sprites have stolen the grove's song. Scatter them, then let Osric swear the woodcutters' oath with you.",
		requires=ql(Q("HeartOfTheGrove"),Q("StalkerInTheRoots")),objectives=ql(K("GaleSprite",15),TALK("Sawyer")),
		rewards={coins=2000,points=2,lamp={xp=3000,skills={"Woodcutting","Farming"}}}},
	{id="VoidglassSpire",title="The Voidglass Spire",giver="CrystalReader",region="Gloomhollow",
		story="Sable needs a reading taken at the Spire's foot and voidstone to tune her lenses.",
		requires=ql(LV("Mining",30),LV("Combat",15)),objectives=ql(VISIT("VoidglassSpire"),Cl("Voidstone",25)),
		rewards={coins=2500,points=1,unlock={warp="Gloomhollow"}}},
	{id="SilkAndShadow",title="Silk and Shadow",giver="TunnelForeman",region="Gloomhollow",
		story="Drogan's tunnels are choked with web. Cut the gloomfangs down and bring their silk for safety lines.",
		requires=ql(LV("Mining",30),LV("Combat",15)),objectives=ql(K("GloomfangSpider",15),H("SpiderSilk",8)),
		rewards={coins=2500,points=1,xp={Mining=3000}}},
	{id="EchoesOfTheWisp",title="Echoes of the Wisp",giver="CrystalReader",region="Gloomhollow",
		story="The Spire's hum is the wisps singing back. Silence a dozen and tell Drogan the tunnels are safe.",
		requires=ql(Q("VoidglassSpire"),Q("SilkAndShadow")),objectives=ql(K("VoidWisp",12),TALK("TunnelForeman")),
		rewards={coins=3500,points=2,lamp={xp=5000,exclude=EXCL}}},
	{id="LightOverTheShoals",title="Light over the Shoals",giver="Lightkeeper",region="Tidewater",
		story="Marisol's lamp oil comes from the shoals themselves. Climb to the Shoal Light and harvest the lagoons.",
		requires=ql(LV("Fishing",30)),objectives=ql(VISIT("ShoalLight"),G("Tidewater",20)),
		rewards={coins=2500,points=1,unlock={warp="Tidewater"}}},
	{id="NetsAndLurkers",title="Nets and Lurkers",giver="NetMender",region="Tidewater",
		story="Kel's nets need saving from the lurkers, and the lanternrays won't land themselves. Tell Marisol when the catch is in.",
		requires=ql(LV("Fishing",30)),objectives=ql(K("ReefLurker",10),Cl("Lanternray",15),TALK("Lightkeeper")),
		rewards={coins=3000,points=2,xp={Fishing=3000}}},
	{id="EyeOfTheStorm",title="Eye of the Storm",giver="StormScribe",region="Tempest",
		story="Thessaly must copy the glyphs at the Storm Crown, but wraiths circle it. Survey the Crown and drive them off.",
		requires=ql(LV("Combat",40)),objectives=ql(VISIT("StormCrown"),K("TempestWraith",10)),
		rewards={coins=5000,points=1,unlock={warp="Tempest"}}},
	{id="SentinelsWatch",title="The Sentinel's Watch",giver="SpireSentinel",region="Tempest",
		story="Rook wants proof you can stand where the starborn stand. Fell three, then report to the Storm-scribe.",
		requires=ql(LV("Combat",40)),objectives=ql(K("StarbornSentinel",3),TALK("StormScribe")),
		rewards={coins=6000,points=2,lamp={xp=6000,exclude=EXCL}}},
	{id="ShardsOfTheCrown",title="Shards of the Crown",giver="CrownArchivist",region="ShatteredCrown",
		story="Seraphine catalogues the Broken Crown shard by shard. Survey it, and keep the riftmaws off her ledgers.",
		requires=ql(Q("CrownOfTempest"),LV("Combat",60)),objectives=ql(VISIT("BrokenCrown"),K("RiftmawStalker",10)),
		rewards={coins=10000,points=2,unlock={warp="ShatteredCrown"}}},
	{id="VigilAtTheRift",title="Vigil at the Rift",giver="Shardkeeper",region="ShatteredCrown",
		story="Halvard's count of rift-horrors grows. Shatter the glass seers and bring his tally to the Archivist.",
		requires=ql(Q("CrownOfTempest"),LV("Combat",60)),objectives=ql(K("ShardglassSeer",8),TALK("CrownArchivist")),
		rewards={coins=8000,points=2,lamp={xp=10000,exclude=EXCL}}},
}
RA.QuestById = {}
RA.QuestsByGiver = {}
for _, q in ipairs(RA.Quests) do
	q.line, q.regional = "side", true -- Journal groups them with side quests; `regional` marks the chain
	table.insert(Data.Quests, q)
	q.index = #Data.Quests
	Data.QuestById[q.id] = q
	RA.QuestById[q.id] = q
	RA.QuestsByGiver[q.giver] = RA.QuestsByGiver[q.giver] or {}
	table.insert(RA.QuestsByGiver[q.giver], q)
end
-- Human-readable text for the new objective kinds.
local describe = Data.describeCheck
function Data.describeCheck(o, ...) -- ... = regional flag (§33), passed through
	if type(o) == "table" and o.kind == "talk" then
		local f = RA.FolkByRole[o.npc]
		return "Speak with " .. (if f then f.name else tostring(o.npc))
	elseif type(o) == "table" and o.kind == "visit" then
		local l = RA.LandmarkById[o.landmark]
		return "Survey " .. (if l then l.name else tostring(o.landmark))
	end
	return describe(o, ...)
end
-- Claim items a giver's dialogue may send (quest id, or "id:Skill" for lamps;
-- open lamps offer three common picks here, every skill from the Journal).
function RA.claimItems(q)
	local out = {}
	local lamp = q.rewards.lamp
	if not lamp then table.insert(out, q.id); return out end
	for _, skill in ipairs(lamp.skills or {"Combat", "Mining", "Woodcutting"}) do table.insert(out, q.id .. ":" .. skill) end
	return out
end

------------------------------------------------------------------------------
-- Snapshot helpers for dialogue conditions and quest markers
-- (snapshot.regionQuests {accepted, talked, visited, warps} and snapshot.journal).
------------------------------------------------------------------------------
local function tab(v) return if type(v) == "table" then v else {} end
local function rq(s) return tab(tab(s).regionQuests) end
local function questEntry(s, q)
	local entry = tab(tab(tab(tab(s).journal).quests)[q.index])
	return if entry.id == q.id then entry else {}
end
-- "done" | "ready" | "active" | "offer" | "locked"
function RA.questStatus(s, q)
	local e = questEntry(s, q)
	if e.done then return "done" end
	if tab(rq(s).accepted)[q.id] then return if e.ready then "ready" else "active" end
	if e.available then return "offer" end
	return "locked"
end
local function wantsTalk(s, role)
	if tab(rq(s).talked)[role] then return false end
	for _, q in ipairs(RA.Quests) do
		if RA.questStatus(s, q) == "active" or RA.questStatus(s, q) == "ready" then
			for _, o in ipairs(q.objectives) do if o.kind == "talk" and o.npc == role then return true end end
		end
	end
	return false
end
-- Marker over an NPC's head: "ready" (gold ?), "offer" (gold !), "talk" (gold …),
-- "active" (grey ?) or nil.
function RA.marker(s, role)
	local best
	for _, q in ipairs(RA.QuestsByGiver[role] or {}) do
		local st = RA.questStatus(s, q)
		if st == "ready" then return "ready" end
		if st == "offer" then best = "offer" elseif st == "active" and not best then best = "active" end
	end
	if best == "offer" then return best end
	if wantsTalk(s, role) then return "talk" end
	return best
end

------------------------------------------------------------------------------
-- Dialogue: every folk NPC is a Townsfolk entry (anchor-only placement) with
-- generated quest, shop and warp nodes.
------------------------------------------------------------------------------
local T = Data.Townsfolk
T.RegionFolkOrder = {}
-- Option labels wrap on the dialogue buttons (npc.client.lua) instead of being cut.
RA.LABEL_MAX = 80
-- "How am I doing?" for one regional quest: its own objectives from the snapshot
-- (journal.quests[q.index].objectives = {{have, need}, ...}; regional kills /
-- collect / gather already count since acceptance on the server).
function RA.progressText(s, q)
	local entry = questEntry(s, q)
	local st = RA.questStatus(s, q)
	if st == "done" then return "\"" .. q.title .. "\" is complete. Thank you, wayfarer." end
	if st == "ready" then return "\"" .. q.title .. "\": everything's done. Hand it in to me whenever you like." end
	local lines = {}
	for j, o in ipairs(q.objectives) do
		local pr = tab(tab(entry.objectives)[j])
		local have, need = tonumber(pr[1]) or 0, tonumber(pr[2]) or 1
		table.insert(lines, (if have >= need then "✓ " else "• ") .. Data.describeCheck(o, true) .. (if need > 1 then " (" .. math.min(have, need) .. "/" .. need .. ")" else ""))
	end
	local head = if st == "active" then "\"" .. q.title .. "\" so far:" else "If you take on \"" .. q.title .. "\", you'll need to:"
	return head .. "\n" .. table.concat(lines, "\n")
end
local verbs = {rqAccept={}, rqClaim={}, rqTalk={}, rqBuy={}, warpTo={}, warpBuy={}, warpLearn={}}
local farewell = {label="Farewell", close=true}
local function cond(id, f) T.Conditions[id] = f; return id end
for _, f in ipairs(folk) do
	local nodes, hello = {}, {}
	local role = f.role
	verbs.rqTalk[role] = true
	table.insert(hello, {label="I was sent to speak with you",verb="rqTalk",item=role,when=cond("rqTalk_" .. role, function(s) return wantsTalk(s, role) end)})
	for _, q in ipairs(RA.QuestsByGiver[role] or {}) do
		local nodeId = "quest_" .. q.id
		verbs.rqAccept[q.id] = true
		table.insert(hello, {label="Quest: " .. q.title, to=nodeId,
			when=cond("rqOpen_" .. q.id, function(s) local st = RA.questStatus(s, q); return st ~= "locked" and st ~= "done" end)})
		local opts = {
			{label="I'll do it",verb="rqAccept",item=q.id,when=cond("rqOffer_" .. q.id, function(s) return RA.questStatus(s, q) == "offer" end)},
		}
		for _, claim in ipairs(RA.claimItems(q)) do
			verbs.rqClaim[claim] = true
			local skill = string.match(claim, ":(%w+)$")
			table.insert(opts, {label=if skill then "Hand in (lamp: " .. skill .. ")" else "Hand in the quest",verb="rqClaim",item=claim,
				when=cond("rqReady_" .. claim, function(s) return RA.questStatus(s, q) == "ready" end)})
		end
		local tipId = "rq_" .. q.id
		T.Tips[tipId] = function(s) return RA.progressText(s, q) end
		table.insert(opts, {label="How am I doing?", tip=tipId})
		table.insert(opts, {label="Back", to="hello"})
		nodes[nodeId] = {text=q.story, options=opts}
	end
	if f.shop then
		local shopOpts = {}
		for i, offer in ipairs(f.shop) do
			local key = role .. ":" .. i
			verbs.rqBuy[key] = true
			local def = Data.Items[offer.item]
			table.insert(shopOpts, {label="Buy " .. (if offer.amount > 1 then offer.amount .. "× " else "") .. (def and def.name or offer.item) .. " (" .. offer.price .. "c)",verb="rqBuy",item=key})
		end
		table.insert(shopOpts, {label="Back", to="hello"})
		nodes.shop = {text="Have a look. Coins up front, no haggling.", options=shopOpts}
		table.insert(hello, {label="Show me your wares", to="shop"})
	end
	if f.kind == "warp" then
		local warpOpts, learnOpts, buyOpts = {}, {}, {}
		for _, w in ipairs(RA.Warps) do
			local region = w.region
			local name = Data.RegionById[region].name
			verbs.warpTo[region], verbs.warpBuy[region], verbs.warpLearn[region] = true, true, true
			table.insert(warpOpts, {label="Warp to " .. name,verb="warpTo",item=region,
				when=cond("warpKnown_" .. region, function(s) return tab(rq(s).warps)[region] == true end)})
			table.insert(learnOpts, {label="Read: " .. name,verb="warpLearn",item=region,
				when=cond("warpScroll_" .. region, function(s) return tab(rq(s).warps)[region] ~= true and (tonumber(tab(tab(s).items)[w.scroll]) or 0) > 0 end)})
			table.insert(buyOpts, {label="Scroll: " .. name .. " (" .. w.price .. "c)",verb="warpBuy",item=region,
				when=cond("warpUnknown_" .. region, function(s) return tab(rq(s).warps)[region] ~= true end)})
		end
		table.insert(warpOpts, {label="Back", to="hello"})
		table.insert(learnOpts, {label="Back", to="hello"})
		table.insert(buyOpts, {label="Back", to="hello"})
		nodes.warps = {text="Name the thread and I'll pull you along it.", options=warpOpts}
		nodes.learn = {text="Hand me a scroll and read the name aloud. Once learned, never forgotten.", options=learnOpts}
		nodes.buy = {text="Each scroll is spun from that isle's own wind. Priced accordingly.", options=buyOpts}
		table.insert(hello, {label="Warp me somewhere", to="warps"})
		table.insert(hello, {label="Learn a warp scroll", to="learn"})
		table.insert(hello, {label="Buy a warp scroll", to="buy"})
	end
	local art = RA.Regions[f.region]
	if art then table.insert(hello, {label="Where is " .. art.landmark.name .. "?",waypoint={"anchor:Waypoint_Landmark_" .. art.landmark.id,"region:" .. f.region}}) end
	table.insert(hello, farewell)
	nodes.hello = {text=f.greet, options=hello}
	T.NPCs[role] = {name=f.name,title=f.title,region=f.region,portrait=f.portrait,look=f.look,start="hello",nodes=nodes,anchorOnly=true,folk=f.kind or "quest"}
	table.insert(T.RegionFolkOrder, role)
end
for verb, items in pairs(verbs) do T.Verbs[verb] = {item=items} end
-- Region folk stand only on their Anchor_NPC_<Role> (World Art section of world.server.lua).
local placement = T.placement
function T.placement(role, scan)
	local def = T.NPCs[role]
	if def and def.anchorOnly then
		local anchors = scan.anchors["Anchor_NPC_" .. role]
		return if anchors and anchors[1] then {source="anchor", part=anchors[1]} else nil
	end
	return placement(role, scan)
end
end
-- <<< END World Art & Regions <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- >>> BEGIN MMO Features (Feature Gap team; append-only section, §31) >>>
-- Isle Renown (account level), the Wayfarer's Path (guided onboarding),
-- announcements, shop quantities, Skyward Vents (launch pads) and Resonance
-- (Magical Power stat tuning). Pure data + pure functions; the server block
-- "MMO Features" in server.server.lua owns every grant. docs/DEPTH-CONTRACT.md §31.
------------------------------------------------------------------------------
do
local F = {}
Data.Features = F
local function tab(v) return if type(v) == "table" then v else {} end
local function whole(v) return if type(v) == "number" and v == v and v >= 0 and v < math.huge then math.floor(v) else 0 end
F.whole = whole

-- Isle Renown -----------------------------------------------------------------
-- One account level fed by renown XP from nearly every activity. Renown is
-- DERIVED from the journal (levels, tiers, quests, diaries...), so it is
-- retroactive by construction and can never be counted twice; the server keeps
-- the highest total ever reached (p.renown.xp) so a level never goes down.
local RN = {}
Data.Renown = RN
RN.NAME = "Isle Renown"
RN.XP_PER_LEVEL = 100
-- Skill levels: XP for each level gained past 1, by band (levels 2..99).
RN.SkillBands = {{to=10,xp=5},{to=25,xp=10},{to=50,xp=15},{to=75,xp=20},{to=99,xp=25}}
RN.COLLECTION_TIER = 4
RN.CONTRACT = 10
RN.Quest = {main=50, side=20}
RN.Diary = {Easy=20, Medium=40, Hard=70, Elite=100}
RN.SlayerLevel = {15,25,35,50,75,100,125,150,150}
RN.FLOOR = 20          -- × floor numeral, first normal clear
RN.MASTER_FLOOR = 30   -- × floor numeral, first Master Mode clear
RN.LAIR_FIRST = 75
RN.LairKc = {{kc=25,xp=50},{kc=100,xp=75}}
RN.MUSEUM = 3
RN.MOTE = 2
RN.BESTIARY_TIER = 3
RN.PET_SPECIES = 10
RN.GUIDE_STEP = 10
RN.Sources = {
	{id="skills",name="Skill levels",hint="Every skill level past 1: 5 XP (2-10), 10 (11-25), 15 (26-50), 20 (51-75), 25 (76-99)."},
	{id="collections",name="Collection tiers",hint="4 XP per collection tier reached."},
	{id="quests",name="Quests & contracts",hint="Main quests 50 XP, side quests 20 XP, guild contracts 10 XP."},
	{id="diaries",name="Achievement diaries",hint="Easy 20, Medium 40, Hard 70, Elite 100 XP per region."},
	{id="slayer",name="Slayer lines",hint="Each slayer line level: 15 / 25 / 35 / 50 / 75 / 100 / 125 / 150 / 150 XP."},
	{id="dungeons",name="Observatory floors",hint="First clear of each floor: 20 XP × its numeral; Master Mode: 30 XP × numeral."},
	{id="lairs",name="Lair bosses",hint="First kill 75 XP; 25 kills +50; 100 kills +75."},
	{id="museum",name="Museum",hint="3 XP per item on display."},
	{id="motes",name="Aether Motes",hint="2 XP per mote found."},
	{id="bestiary",name="Bestiary",hint="3 XP per bestiary milestone."},
	{id="pets",name="Companions",hint="10 XP per pet species ever adopted."},
	{id="guide",name="Wayfarer's Path",hint="10 XP per onboarding step."},
}
RN.SourceById = {}
for i, s in ipairs(RN.Sources) do s.index = i; RN.SourceById[s.id] = s end
function RN.skillXp(level)
	level = math.clamp(whole(level), 1, 99)
	local xp, from = 0, 2
	for _, band in ipairs(RN.SkillBands) do
		local to = math.min(level, band.to)
		if to >= from then xp += (to - from + 1) * band.xp end
		from = band.to + 1
	end
	return xp
end
-- Profile -> {total, sources={[id]={xp, count}}}. P = AetherProgression (levels, tiers).
-- `extra` = {guideSteps = n, species = {[petId]=true}} (server-held sets).
function RN.breakdown(p, P, extra)
	p, extra = tab(p), tab(extra)
	local out = {}
	for _, s in ipairs(RN.Sources) do out[s.id] = {xp=0, count=0} end
	local function add(id, xp, n) out[id].xp += xp; out[id].count += n or 1 end
	for _, skill in ipairs(Data.SkillOrder) do
		local lvl = P.levelForXp(tab(p.xp)[skill] or 0)
		if lvl > 1 then add("skills", RN.skillXp(lvl), lvl - 1) end
	end
	for _, id in ipairs(Data.CollectionItems) do
		local t = P.collectionTier(p, id)
		if t > 0 then add("collections", t * RN.COLLECTION_TIER, t) end
	end
	local contracts = math.min(whole(p.questCompleted), 8)
	if contracts > 0 then add("quests", contracts * RN.CONTRACT, contracts) end
	for id, done in pairs(tab(p.questsDone)) do
		local q = done == true and Data.QuestById[id]
		if q then add("quests", RN.Quest[q.line] or RN.Quest.side) end
	end
	for region, claimed in pairs(tab(p.diaries)) do
		if Data.DiaryByRegion[region] then
			for i = 1, math.min(whole(claimed), #Data.DiaryTiers) do add("diaries", RN.Diary[Data.DiaryTiers[i]] or 0) end
		end
	end
	for _, line in ipairs(Data.SlayerOrder) do
		local lvl = P.slayerLevel(tab(p.slayerXp)[line] or 0)
		for i = 1, math.min(lvl, #RN.SlayerLevel) do add("slayer", RN.SlayerLevel[i]) end
	end
	local clears = tab(tab(p.dungeons).clears)
	local master = tab(tab(p.dungeonClasses).masterClears)
	for i in ipairs(Data.DungeonFloors) do
		if whole(clears[tostring(i)]) > 0 or whole(clears[i]) > 0 then add("dungeons", RN.FLOOR * i) end
		if whole(master[tostring(i)]) > 0 or whole(master[i]) > 0 then add("dungeons", RN.MASTER_FLOOR * i) end
	end
	local kc = tab(tab(p.lairs).kc)
	for _, id in ipairs(Data.Lairs and Data.Lairs.Order or {}) do
		local n = whole(kc[id])
		if n > 0 then add("lairs", RN.LAIR_FIRST) end
		for _, m in ipairs(RN.LairKc) do if n >= m.kc then add("lairs", m.xp, 0) end end
	end
	local museum = math.min(whole(tab(p.museum).count), 10000)
	if museum > 0 then add("museum", museum * RN.MUSEUM, museum) end
	local motes = math.min(whole(tab(p.motes).count), Data.Exploration and Data.Exploration.TOTAL or 0)
	if motes > 0 then add("motes", motes * RN.MOTE, motes) end
	for monster, kills in pairs(tab(p.bestiary)) do
		if type(monster) == "string" and rawget(Data.Monsters, monster) then
			for _, need in ipairs(Data.BestiaryTiers) do if whole(kills) >= need then add("bestiary", RN.BESTIARY_TIER) end end
		end
	end
	local species = {}
	for id in pairs(tab(extra.species)) do if Data.PetById[id] then species[id] = true end end
	for _, pet in ipairs(tab(p.pets)) do if type(pet) == "table" and Data.PetById[pet.id] then species[pet.id] = true end end
	for _ in pairs(species) do add("pets", RN.PET_SPECIES) end
	local steps = math.min(whole(extra.guideSteps), 20)
	if steps > 0 then add("guide", steps * RN.GUIDE_STEP, steps) end
	local total = 0
	for _, s in pairs(out) do total += s.xp end
	return {total=total, sources=out}
end
function RN.levelFor(xp) return math.floor(whole(xp) / RN.XP_PER_LEVEL) end
-- Title / nameplate colour bands.
RN.Tiers = {
	{level=0,title="Driftling",color="AAAAAA"},
	{level=10,title="Islander",color="FFFFFF"},
	{level=25,title="Skyfarer",color="FFFF55"},
	{level=50,title="Windcaller",color="55FF55"},
	{level=80,title="Isle Warden",color="2BC0B4"},
	{level=120,title="Cloudmarshal",color="5599FF"},
	{level=160,title="Stormherald",color="AA55FF"},
	{level=200,title="Starbound",color="FF55FF"},
	{level=260,title="Aetherlord",color="FFAA00"},
	{level=330,title="Archon of the Isles",color="FF5555"},
	{level=400,title="Living Legend",color="F7C548"},
}
function RN.tier(level)
	local best = RN.Tiers[1]
	for _, t in ipairs(RN.Tiers) do if whole(level) >= t.level then best = t end end
	return best
end
-- Level-gated rewards: accessory bag slots and minor permanent stats
-- (p.perkStats.renown; Health 20 / Defense 5 at most, inside Data.PerkBudget).
RN.SlotLevels = {10,25,50,100,150}
RN.MAX_SLOTS = #RN.SlotLevels
RN.StatSteps = {
	{stat="health",every=10,per=2,max=20},
	{stat="strength",every=15,per=1,max=10},
	{stat="defense",every=30,per=1,max=5},
	{stat="intelligence",every=20,per=2,max=12},
}
function RN.slots(level)
	local n = 0
	for _, l in ipairs(RN.SlotLevels) do if whole(level) >= l then n += 1 end end
	return n
end
function RN.stats(level)
	local out = {}
	for _, step in ipairs(RN.StatSteps) do
		local v = math.min(step.max, math.floor(whole(level) / step.every) * step.per)
		if v > 0 then out[step.stat] = v end
	end
	return out
end
-- The reward text for exactly reaching `level` (announcements), or nil.
function RN.rewardText(level)
	local parts = {}
	if table.find(RN.SlotLevels, level) then table.insert(parts, "+1 accessory slot") end
	local before, now = RN.stats(level - 1), RN.stats(level)
	for _, step in ipairs(RN.StatSteps) do
		local gain = (now[step.stat] or 0) - (before[step.stat] or 0)
		if gain > 0 then table.insert(parts, "+" .. gain .. " " .. Data.Stats[step.stat].name) end
	end
	for _, t in ipairs(RN.Tiers) do if t.level == level and level > 0 then table.insert(parts, "title " .. t.title) end end
	return if #parts > 0 then table.concat(parts, ", ") else nil
end
-- Upcoming rewards after `level` (at most n), for the Renown page.
function RN.nextUnlocks(level, n)
	level = whole(level)
	local list = {}
	for _, l in ipairs(RN.SlotLevels) do if l > level then table.insert(list, {level=l, text="+1 accessory bag slot"}) end end
	for _, t in ipairs(RN.Tiers) do if t.level > level then table.insert(list, {level=t.level, text="Title: " .. t.title}) end end
	for _, step in ipairs(RN.StatSteps) do
		local at = (math.floor(level / step.every) + 1) * step.every
		if math.floor(at / step.every) * step.per <= step.max then
			table.insert(list, {level=at, text="+" .. step.per .. " " .. Data.Stats[step.stat].name})
		end
	end
	table.sort(list, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.text < b.text end)
	local out = {}
	for i = 1, math.min(n or 6, #list) do out[i] = list[i] end
	return out
end
-- Bag slots from Renown, read by Progression.accessorySlots (p.renown.level is server-set).
function RN.profileSlots(p)
	local r = type(p) == "table" and p.renown
	return if type(r) == "table" then RN.slots(whole(r.level)) else 0
end

-- Wayfarer's Path (guided onboarding) ------------------------------------------
-- A server-driven chain. Each step is done when its check holds (veterans skip
-- what they already did) or its flag was raised by the server (visit, talk,
-- sell). Rewards are paid once per step reached live; steps already satisfied
-- on the first load are marked done without pay (no retroactive windfall).
local G = {}
F.Guide = G
G.NAME = "Wayfarer's Path"
local function anyCollected(p, skill)
	for id, n in pairs(tab(p.collection)) do if whole(n) > 0 and Data.ResourceSkill[id] == skill then return true end end
	return false
end
local function anyCount(t) for _, n in pairs(tab(t)) do if whole(n) > 0 then return true end end return false end
G.Steps = {
	-- Polish QC (lead decision): the account-mode choice OPENS the Path. Gathering
	-- a log sets p.started, so a closing step could only ever pick Standard. Pell
	-- offers it at first contact: Standard is one tap, Ironman sits behind his
	-- explanation and a PERMANENT confirmation, and follows the ironman verb's rule
	-- (refused once p.started, or while in a crew). Choosing at Pell also counts as
	-- finding him (visit / talk flags). Steps are saved by id, never by index.
	{id="mode",title="Choose your journal mode",detail="Talk to Pell in Compass Quay: keep a Standard journal in one tap, or seal an Ironman journal before you gather, craft or fight.",coins=50,
		check=function(p) return p.accountMode == "standard" or p.accountMode == "ironman" or p.ironman == true end},
	{id="chop",title="Chop a log",detail="Left-click a tree to chop it with your axe (tap on mobile): your home isle or Mosswake Grove.",coins=25,
		check=function(p) return anyCollected(p, "Woodcutting") end},
	{id="craft",title="Craft at a workbench",detail="Craft anything at a Workbench, Forge, Hearth or Cauldron (Atlas › Workshop).",coins=40,
		check=function(p) return anyCount(tab(p.counters).crafts) or anyCount(tab(p.crafting).made) end},
	{id="visit",title="Visit Compass Quay",detail="Take the home portal to Compass Quay, the shared hub.",coins=25,flag="visit"},
	{id="talk",title="Talk to Pell",detail="Find Pell Ashgrove, the Wayfinder, in Compass Quay and ask about the Wayfarer's Path.",coins=25,flag="talk"},
	{id="ore",title="Gather ore",detail="Left-click an ore rock to mine it with your pickaxe (tap on mobile), e.g. in Brassfall Cay.",coins=40,
		check=function(p) return anyCollected(p, "Mining") end},
	{id="sell",title="Sell an item",detail="Sell something from your satchel (right-click an item › Sell).",coins=30,flag="sell"},
	{id="equip",title="Equip a weapon",detail="Craft or buy a weapon and wield it (Satchel or Hero › Gear).",coins=50,
		check=function(p) return type(tab(p.equipment).weapon) == "string" end},
	{id="kill",title="Defeat a creature",detail="Brambleback Boars roam Sunwheel Downs. Click a creature to strike.",coins=60,
		check=function(p) return whole(p.kills) > 0 or anyCount(p.bestiary) end},
	{id="quest",title="Accept a quest",detail="Accept a quest from a regional questgiver (gold ! above their head) or complete your first guild contract.",coins=75,
		check=function(p) return next(tab(tab(p.regionQuests).accepted)) ~= nil or next(tab(p.questsDone)) ~= nil or whole(p.questCompleted) > 0 end},
	{id="warp",title="Learn a warp",detail="Buy a warp scroll from Ilsabet the Warp Keeper and read it.",coins=100,
		check=function(_, ctx) return next(tab(tab(ctx).warps)) ~= nil end},
}
-- Wayfinder waypoints per step (T.parseTarget specs; Pell's "Show me the way").
G.Waypoints = {
	chop={"gather:Timber","region:Meadow"}, craft={"station:Workbench","station:Forge"}, visit={"region:Hub"}, talk={"npc:Guide"},
	ore={"gather:Ore","region:Quarry"}, sell={"npc:Merchant"}, kill={"monster:BramblebackBoar","region:Meadow"},
	quest={"npc:WarpKeeper","npc:Guide","region:Hub"}, warp={"npc:WarpKeeper"}, mode={"npc:Guide","region:Hub"},
}
-- Account modes (verb guideMode): Standard, or Ironman with the confirm token.
G.MODE_STANDARD, G.MODE_IRONMAN = "standard", "ironman:confirm"
G.COMPLETE_COINS = 250
-- Saved p.guide schema: 2 = the journal-mode step opens the Path (Features.migrate).
G.VERSION = 2
G.StepById = {}
G.MAX_OWED = G.COMPLETE_COINS
for i, s in ipairs(G.Steps) do s.index = i; G.StepById[s.id] = s; G.MAX_OWED += s.coins end
G.Flags = {visit=true, talk=true, sell=true}
-- A veteran's first load completes the whole path (no rewards).
G.VETERAN_TOTAL_LEVEL = 60
G.VETERAN_CONTRACTS = 2
-- Is step `s` satisfied right now? (flags are p.guide.flags)
function G.satisfied(p, s, ctx)
	if s.flag then return tab(tab(tab(p).guide).flags)[s.flag] == true end
	return s.check(tab(p), ctx) == true
end
-- Sidebar view: {step, total, done, id, title, detail, coins, complete}
function G.view(guide)
	guide = tab(guide)
	local done = tab(guide.done)
	local n = 0
	for _, s in ipairs(G.Steps) do if done[s.id] then n += 1 end end
	for _, s in ipairs(G.Steps) do
		if not done[s.id] and guide.complete ~= true then
			return {step=s.index, total=#G.Steps, done=n, id=s.id, title=s.title, detail=s.detail, coins=s.coins, complete=false}
		end
	end
	return {step=#G.Steps, total=#G.Steps, done=n, complete=true, title="Path complete", detail="Explore the isles: train skills and raise your Isle Renown."}
end

-- Announcements ------------------------------------------------------------------
-- Server queue entries {kind, ...} -> {head, body, color} for the toast and chat line.
function F.announceText(e)
	e = tab(e)
	local item = type(e.item) == "string" and Data.Items[e.item]
	if e.kind == "collection" then
		return {head="COLLECTION UNLOCKED", body=item and item.name or tostring(e.item), color="F7C548"}
	elseif e.kind == "collectionTier" then
		return {head="COLLECTION LEVEL UP", body=(item and item.name or tostring(e.item)) .. " " .. whole(e.tier), color="FFAA00"}
	elseif e.kind == "skill" then
		return {head="SKILL LEVEL UP", body=tostring(e.skill) .. " " .. whole(e.level) .. (if whole(e.coins) > 0 then "  ·  +" .. whole(e.coins) .. " coins" else ""), color="55FFFF"}
	elseif e.kind == "objective" then
		return {head="NEW OBJECTIVE", body=tostring(e.title), color="FFFF55"}
	elseif e.kind == "renown" then
		local t = RN.tier(whole(e.level))
		return {head=string.upper(RN.NAME) .. " " .. whole(e.level), body=t.title .. (if type(e.reward) == "string" then "  ·  " .. e.reward else ""), color=t.color}
	elseif e.kind == "workerRecipe" then
		local t = Data.Workers and type(e.worker) == "string" and Data.Workers.TypeById[e.worker]
		-- Polish QC L3: a skill gate still ahead reads "available at <skill> <level>".
		local gate = if type(e.skill) == "string" and whole(e.level) > 0 then "  ·  available at " .. e.skill .. " " .. whole(e.level) else ""
		return {head="WORKER RECIPE UNLOCKED", body=(t and t.name or tostring(e.worker)) .. "  ·  " .. (item and item.name or tostring(e.item)) .. " collection " .. whole(e.tier) .. gate, color="FFAA00"}
	elseif e.kind == "guide" then
		return {head=string.upper(G.NAME), body=tostring(e.title) .. (if whole(e.coins) > 0 then "  ·  +" .. whole(e.coins) .. " coins" else ""), color="6FE3C8"}
	end
	return {head="NOTICE", body=tostring(e.text or ""), color="FFFFFF"}
end
F.ANNOUNCE_MAX = 12 -- queued per profile between flushes
-- Renown level-ups and path steps always survive a full queue / ring.
F.ANNOUNCE_PRIORITY = {renown=true, guide=true}
-- Trims `list` (oldest first) to `max` entries: drops the oldest ordinary entry
-- first, and the oldest priority entry only when nothing else is left.
function F.trimAnnouncements(list, max)
	while #list > max do
		local drop = 1
		for i, e in ipairs(list) do
			if not F.ANNOUNCE_PRIORITY[tab(e).kind] then drop = i; break end
		end
		table.remove(list, drop)
	end
	return list
end

-- Shop quantities --------------------------------------------------------------
-- rqBuy "Role:i[:qty]", skillBuy "Skill:Item[:qty]", petShop "Item[:qty]".
-- qty counts lots (an offer of 5× buys 5 per lot), 1..MAX_LOTS per call, at the
-- same per-unit price (the ≥ 1.3 × value rule holds per unit).
F.Shop = {MAX_LOTS=64, Presets={1,8,16,32,64}}
-- Wares sold one at a time (the server refuses qty > 1; the picker never opens):
-- warp scrolls and one-of-a-kind gear (armor, accessories, traps).
function F.Shop.singleLot(itemId)
	local def = type(itemId) == "string" and Data.Items[itemId]
	if not def then return true end
	if def.kind == "armor" or def.kind == "accessory" or def.category == "trap" then return true end
	for _, w in ipairs(tab(Data.RegionArt and Data.RegionArt.Warps)) do if w.scroll == itemId then return true end end
	return false
end
-- Splits a trailing ":qty" off a shop item string with `parts` base segments.
-- Returns base, qty (1 when absent) or nil for a malformed quantity.
function F.splitQty(item, parts)
	if type(item) ~= "string" or #item == 0 or #item > 64 then return nil end
	local segs = string.split(item, ":")
	if #segs == parts then return item, 1 end
	if #segs ~= parts + 1 then return nil end
	local raw = segs[#segs]
	if not string.match(raw, "^[1-9]%d?$") then return nil end
	local qty = tonumber(raw)
	if not qty or qty < 1 or qty > F.Shop.MAX_LOTS then return nil end
	table.remove(segs)
	return table.concat(segs, ":"), qty
end

-- Merchant sell quantity (Polish): sell "<id>:<n>" sells n of a stack (the server
-- also checks n <= held - the kept upgraded copy). Returns base, n or nil.
F.SELL_MAX = 1000000
function F.splitSell(item)
	if type(item) ~= "string" or #item == 0 or #item > 64 then return nil end
	local base, raw = string.match(item, "^([%w_]+):([1-9]%d*)$")
	if not base or #raw > 7 then return nil end
	local n = tonumber(raw)
	if not n or n < 1 or n > F.SELL_MAX then return nil end
	return base, n
end

-- Worker unlocks by collection tier (Polish): the worker types whose output is
-- `item` and whose collectionTier lies in (fromTier, toTier] (SkyBlock's minion
-- recipe unlock at a collection tier). Starter types (tier 0) are never listed.
function F.workerUnlocks(item, fromTier, toTier)
	local out = {}
	local W = Data.Workers
	for _, t in ipairs(W and W.Types or {}) do
		if t.output == item and t.collectionTier > whole(fromTier) and t.collectionTier <= whole(toTier) then table.insert(out, t) end
	end
	return out
end

-- Skyward Vents (launch pads) ----------------------------------------------------
-- Gated by the destination region's access rules (IsleRegionAccess); the world
-- sets FastTravelAt, plays a short arc and lands the rider server-side.
local V = {}
Data.Vents = V
V.COOLDOWN = 10      -- seconds per rider
V.FLIGHT = 1.6       -- seconds of arc before the server lands the rider
V.ARC_HEIGHT = 70    -- studs above the higher end
V.RANGE = 9          -- the rider must stand this close to the vent
V.List = {
	{id="MosswakeUpdraft",name="Mosswake Updraft",isle="Mosswake Grove",to="Windpine",land="Windpine Grove",color="9BD18B"},
	{id="WindpineDowndraft",name="Windpine Downdraft",isle="Windpine Grove",to="Meadow",land="Mosswake Grove",color="9BD18B"},
	{id="ShoalwardPlume",name="Shoalward Plume",isle="Meadow Reach",to="Tidewater",land="Tidewater Shoals",color="5EC8D8"},
	{id="TidewaterSpout",name="Tidewater Spout",isle="Tidewater Shoals",to="Meadow",land="Mosswake Grove",color="5EC8D8"},
	{id="CinderChimney",name="Cinder Chimney",isle="Cinder Shelf",to="Tempest",land="Tempest Spire",color="FF8A3D"},
	{id="StormSluice",name="Storm Sluice",isle="Tempest Spire",to="Quarry",land="Cinder Shelf",color="C6DCFF"},
}
V.ById = {}
for _, v in ipairs(V.List) do V.ById[v.id] = v end
-- Launch feel (Polish; client only, features.client.lua): an FOV kick that
-- rises fast and eases back by the landing, a banking roll that peaks mid-arc,
-- and wind streaks. Reduced motion: no FOV / tilt, a lighter wind.
V.Fx = {FOV_KICK=14, TILT=math.rad(7), WIND_RATE=60, WIND_RATE_REDUCED=20}
function V.Fx.fovKick(t)
	t = math.clamp(t, 0, 1)
	if t < 0.2 then return V.Fx.FOV_KICK * (t / 0.2) end
	local u = (t - 0.2) / 0.8
	return V.Fx.FOV_KICK * (1 - u * u)
end
function V.Fx.tilt(t) return V.Fx.TILT * math.sin(math.pi * math.clamp(t, 0, 1)) end
-- Arc height at t ∈ [0,1] from ya to yb peaking `height` above the higher end
-- (a quadratic through both ends and the peak at t = 0.5).
function V.arcY(ya, yb, t, height)
	t = math.clamp(t, 0, 1)
	local top = math.max(ya, yb) + (height or V.ARC_HEIGHT)
	return (1 - t) * (1 - 2 * t) * ya + 4 * t * (1 - t) * top + t * (2 * t - 1) * yb
end

-- Resonance (Magical Power stat tuning) -------------------------------------------
-- The Resonance Keeper in Compass Quay tunes your accessory bag's Magical Power
-- into one stat template. Stats = weight × min(MP, POWER_CAP)^0.75 (applied
-- through p.perkStats.resonance; no Health / Defense, so Data.PerkBudget is
-- unaffected). Balance: at the cap no template's Strength / Crit Damage /
-- Intelligence exceeds 60 % of the comparable endgame source (Sovereign set
-- bonus Strength 70 / Crit Damage 80, Riftcrown Staff Intelligence 180);
-- Starlore's Intelligence sits at ~0.95 × Emberkeen's Strength share.
local R = {}
Data.Resonance = R
R.NAME = "Resonance"
R.EXPONENT = 0.75
R.POWER_CAP = 400 -- Magical Power past this adds no resonance
R.SWITCH_FEE = 250
R.SWITCH_COOLDOWN = 120
R.VISIT_SECONDS = 300
R.Templates = {
	{id="Emberkeen",name="Emberkeen",minPower=0,color="FF6B5A",text="Raw striking power.",weights={strength=0.45,critDamage=0.5}},
	{id="Galewise",name="Galewise",minPower=0,color="DDEEFF",text="Quick feet and a sure eye.",weights={speed=0.12,critChance=0.12,strength=0.2}},
	{id="Starlore",name="Starlore",minPower=10,color="55FFFF",text="Mana for spellcasters.",weights={intelligence=1.1,critDamage=0.3}},
	{id="Tidefortune",name="Tidefortune",minPower=25,color="FF55FF",text="Luck on every drop.",weights={magicFind=0.05,petLuck=0.05,strength=0.2}},
	{id="Lodestone",name="Lodestone",minPower=25,color="FFAA00",text="For miners.",weights={miningFortune=0.5,miningSpeed=1.5}},
	{id="Verdance",name="Verdance",minPower=25,color="8EE05A",text="For foragers and farmers.",weights={foragingFortune=0.45,farmingFortune=0.45}},
	{id="Bladestorm",name="Bladestorm",minPower=60,color="F7C548",text="Balanced fury for veterans.",weights={strength=0.3,critChance=0.08,critDamage=0.45,attackSpeed=0.06}},
}
R.ById = {}
for _, t in ipairs(R.Templates) do R.ById[t.id] = t end
function R.scale(power) return math.min(whole(power), R.POWER_CAP) ^ R.EXPONENT end
function R.stats(id, power)
	local t = type(id) == "string" and R.ById[id]
	if not t or whole(power) < t.minPower then return {} end
	local s = R.scale(power)
	local out = {}
	for stat, w in pairs(t.weights) do
		local v = math.floor(w * s * 10) / 10
		if v > 0 then out[stat] = v end
	end
	return out
end

-- The Resonance Keeper (Compass Quay). A regional folk entry so the World Art
-- section places Anchor_NPC_Resonator and npc.server.lua stands the rig on it.
local T = Data.Townsfolk
local RA = Data.RegionArt
local keeper = {role="Resonator",region="Hub",name="Oriel Thrumwright",title="Resonance Keeper",portrait="🔮",kind="resonance",
	look={skin="C68E62",shirt="35285A",pants="1E1B2E",shoes="15121F",accent="9FE6F2",hair="D9D2F2",hat="feather",held="staff",cape="5A3F8C",spectacles=true},
	greet="Your trinkets hum, wayfarer. Let me tune that hum into something you can feel. One resonance at a time."}
table.insert(RA.Folk, keeper)
RA.FolkByRole[keeper.role] = keeper
T.Verbs.resonanceVisit = {item=false}
T.Verbs.guideTalk = {item=false}
T.Verbs.guideClaim = {item=false}
T.Conditions.guideTalkActive = function(s)
	local g = tab(tab(s).guide)
	return g.id == "talk"
end
-- Polish QC: the Path's first step (journal mode) is open: Pell shows "!".
T.Conditions.guideModeActive = function(s)
	return tab(tab(s).guide).id == "mode"
end
T.Conditions.guideRewardReady = function(s)
	return whole(tab(tab(s).guide).owed) > 0
end
T.NPCs.Resonator = {name=keeper.name,title=keeper.title,region="Hub",portrait=keeper.portrait,look=keeper.look,start="hello",anchorOnly=true,folk="resonance",
	nodes={
		hello={text=keeper.greet,options={
			{label="Tune my Magical Power",verb="resonanceVisit"},
			{label="How does resonance work?",to="explain"},
			{label="Farewell",close=true}}},
		explain={text="Every accessory in your bag adds Magical Power. Pick a resonance and I turn that power into stats; more power, stronger tuning. The first tuning is free; changing it costs "
			.. R.SWITCH_FEE .. " coins and the hum needs " .. R.SWITCH_COOLDOWN // 60 .. " minutes to settle.",options={
			{label="Tune my Magical Power",verb="resonanceVisit"},
			{label="Back",to="hello"},
			{label="Farewell",close=true}}},
	}}
table.insert(T.RegionFolkOrder, keeper.role)
-- Pell offers the onboarding talk step.
local pell = T.NPCs.Guide
if pell and pell.nodes and pell.nodes.hello then
	table.insert(pell.nodes.hello.options, 1, {label="I'm walking the Wayfarer's Path",verb="guideTalk",when="guideTalkActive"})
	table.insert(pell.nodes.hello.options, 2, {label="Claim my Wayfarer's Path rewards",verb="guideClaim",when="guideRewardReady"})
end

-- Polish (lead decision): Pell's older 6-step client tutorial is retired in
-- favour of the Wayfarer's Path. T.Tutorial / T.tutorialState stay as pure data
-- (old snapshots and tests still evaluate), but nothing offers or tracks it:
-- tutorialActive is always false, Pell's "Walk me through the basics" becomes
-- "Walk me through the Wayfarer's Path" (node path), the old "tutorial" node is
-- removed, and the "next" tip reads the Path step. The Path's first step is the account-mode choice.
T.TUTORIAL_RETIRED = true
T.Conditions.tutorialActive = function() return false end
T.Conditions.pathActive = function(s)
	local g = tab(tab(s).guide)
	return type(g.title) == "string" and g.complete ~= true
end
-- Journal mode not chosen yet (and the journal is not Ironman already).
T.Conditions.modeOpen = function(s)
	s = tab(s)
	return s.accountMode == nil and s.ironman ~= true and type(s.items) == "table"
end
-- Ironman can still be sealed: no progression yet (the ironman verb's rule).
T.Conditions.ironmanOpen = function(s)
	s = tab(s)
	return s.ironman ~= true and s.started ~= true and type(s.items) == "table"
end
T.Verbs.guideMode = {item={[G.MODE_STANDARD]=true, [G.MODE_IRONMAN]=true}}
function T.pathStep(s)
	local g = tab(tab(s).guide)
	if type(g.title) ~= "string" or g.complete == true then return nil end
	local step = G.StepById[tostring(g.id)]
	return {index=whole(g.step), total=whole(g.total), id=g.id, title=g.title, detail=tostring(g.detail or ""), waypoint=step and G.Waypoints[step.id] or nil}
end
if pell and pell.nodes then
	for _, o in ipairs(pell.nodes.hello.options) do
		if o.to == "tutorial" then o.label, o.to, o.when = "Walk me through the Wayfarer's Path", "path", "pathActive" end
	end
	-- Polish QC (lead decision): first contact offers the journal mode. Standard is
	-- one tap; Ironman is behind the explanation (node mode) and the PERMANENT
	-- confirmation (node ironman).
	table.insert(pell.nodes.hello.options, 1, {label="Keep a Standard journal",verb="guideMode",item=G.MODE_STANDARD,when="modeOpen"})
	table.insert(pell.nodes.hello.options, 2, {label="Standard or Ironman? Explain journal modes",to="mode",when="modeOpen"})
	pell.nodes.path = {path=true,text="The Wayfarer's Path is " .. #G.Steps .. " steps, from choosing your journal to your first warp. Here's your next step:",options={
		{label="Show me the way",waypoint="path"},
		{label="Choose my journal mode",to="mode",when="modeOpen"},
		{label="Claim my Wayfarer's Path rewards",verb="guideClaim",when="guideRewardReady"},
		{label="Back",to="hello"}}}
	-- The retired tutorial node is removed; its only entry was rewired to node path above.
	pell.nodes.tutorial = nil
	pell.nodes.mode = {text="Every journal picks a mode. STANDARD: trade, use the Bazaar and Auction House, and hunt with anyone. "
		.. "IRONMAN: a permanent charter. No player exchange, Bazaar or Auction House, Warden hunts are solo, and party credit needs a real share of the damage. "
		.. "Ironman can only be sealed before any progression, and it can never be undone.",options={
		{label="Keep a Standard journal",verb="guideMode",item=G.MODE_STANDARD},
		{label="Review the Ironman charter",to="ironman",when="ironmanOpen"},
		{label="Back",to="hello"}}}
	pell.nodes.ironman = {text="Are you sure? Sealing an Ironman journal is PERMANENT: you will never trade with other players or use the Bazaar or Auction House on this journal. "
		.. "If you have already started gathering, crafting or fighting, the seal will refuse and your journal stays Standard.",options={
		{label="Seal my journal as Ironman (permanent)",verb="guideMode",item=G.MODE_IRONMAN},
		{label="Keep a Standard journal",verb="guideMode",item=G.MODE_STANDARD},
		{label="Back",to="mode"}}}
end
T.Tips.next = function(s, ctx)
	local step = T.pathStep(s)
	if step then return "Wayfarer's Path " .. step.index .. "/" .. step.total .. " — " .. step.title .. ": " .. step.detail end
	if type(s) ~= "table" or s.loading or type(s.items) ~= "table" then return "Your journal is still opening. Ask me again in a moment." end
	local q = tab(s.quest)
	if T.Conditions.contractReady(s) or (not q.complete and q.title) then return T.Tips.contract(s) end
	return T.Tips.quest(s)
end
end
-- <<< END MMO Features <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- >>> BEGIN Systems Depth (Systems Depth team; append-only section, §33) >>>
-- Quest helper (step-by-step guides derived from quest / diary / contract
-- data), the goal board, market price history, per-player daily shop stock
-- and the XP calculator. Pure data + pure functions shared by the server
-- block "Systems Depth" in server.server.lua (every grant and check) and the
-- atlas pages in ui.client.lua. docs/DEPTH-CONTRACT.md §33.
------------------------------------------------------------------------------
do
local SY = {}
Data.Systems = SY
local function tab(v) return if type(v) == "table" then v else {} end
local function num(v) return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0 end
local function whole(v) v = num(v); return if v > 0 then math.floor(v) else 0 end
local function nameOf(id) local def = type(id) == "string" and Data.Items[id]; return if def then def.name else tostring(id) end
SY.whole = whole

-- Quest helper -------------------------------------------------------------
-- A guide is {id, kind, title, status, steps, current, total, done}. A step is
-- {text, have, need, met, phase, specs = {waypoint spec...}|nil, npc = role|nil}.
-- specs are Data.Townsfolk target specs ("monster:Thornling", "npc:Shepherd",
-- "region:Meadow"...) for LocalPlayer.WayfinderRequest; the first that resolves wins.
local HP = {}
SY.Helper = HP
HP.PIN_MAX = 48 -- longest pin id ("quest:<id>", "diary:<region>", "contract")
-- Legacy guild contracts (server `quests` list, by stage): where each is done.
HP.ContractSpecs = {
	{"gather:Ore", "region:Quarry"},
	{"station:Forge", "anchor:Waypoint_Forge"},
	{"anchor:Waypoint_WorkerYard", "home"},
	{"anchor:Waypoint_Shellwarden"},
	{"anchor:Waypoint_ExpeditionGate"},
	{"anchor:Waypoint_SkyreachCharter", "region:Quarry"},
	{"region:Skyreach"},
	{"station:Forge", "anchor:Waypoint_Forge"},
}
-- Region access for waypoints: ctx.access = {[regionId] = bool} (the server's
-- regionAllowed / the snapshot's depth.regions). Unknown regions or no access
-- map count as open (pure data callers, tests).
local function regionOpen(ctx, region)
	local access = tab(ctx).access
	if type(region) ~= "string" or type(access) ~= "table" then return true end
	return access[region] ~= false
end
-- "Unlocks with <region>: <requirements>" for a locked region.
function HP.requirement(region)
	local def = Data.RegionById[region]
	local E = Data.Endgame
	local parts = if def and E and E.requirementParts then E.requirementParts(def) else {}
	return "Unlocks with " .. (if def then def.name else tostring(region)) .. (if #parts > 0 then ": " .. table.concat(parts, ", ") else "")
end
local function nodeRegion(id)
	local W = Data.Workers
	return W and W.ResourceRegion and W.ResourceRegion[id] or nil
end
-- Where an item comes from: candidates {specs, region, level, rank} sorted lowest
-- level first (a gathering node, a recipe's station, every creature with a
-- >= 10 % drop); built once, lazily.
local sources
local function addSource(id, src)
	local list = sources[id] or {}
	sources[id] = list
	table.insert(list, src)
end
local function buildSources()
	sources = {}
	local station = {}
	for _, tiers in pairs(Data.ResourceTiers) do
		for _, r in ipairs(tab(tiers)) do
			local region = nodeRegion(r.id)
			local specs = {"gather:" .. r.id}
			if region then table.insert(specs, "region:" .. region) end
			addSource(r.id, {specs = specs, region = region, level = whole(r.level), rank = 1})
		end
	end
	local rids = {}
	for rid in pairs(Data.Recipes) do table.insert(rids, rid) end
	table.sort(rids)
	for _, rid in ipairs(rids) do
		local d = Data.Recipes[rid]
		if type(d) == "table" and type(d.output) == "string" and type(d.station) == "string" and not station[d.output] then
			addSource(d.output, {specs = {"station:" .. d.station}, level = whole(d.level), rank = 2})
			station[d.output] = true
		end
	end
	local CR = Data.Crafting
	for _, rid in ipairs(tab(CR and CR.RecipeOrder)) do
		local d = CR.Recipes[rid]
		if d and type(d.station) == "string" and type(d.output) == "string" and not station[d.output] then
			addSource(d.output, {specs = {"station:" .. d.station}, level = whole(d.level), rank = 2})
			station[d.output] = true
		end
	end
	local ids = {}
	for mid in pairs(Data.Monsters) do table.insert(ids, mid) end
	table.sort(ids)
	for _, mid in ipairs(ids) do
		local m = Data.Monsters[mid]
		local seen = {}
		for _, drop in ipairs(tab(m.drops)) do
			if type(drop) == "table" and type(drop.item) == "string" and not seen[drop.item] and num(drop.chance) >= 0.1 then
				seen[drop.item] = true
				local list = {"monster:" .. mid}
				local region = if type(m.region) == "string" then m.region else nil
				if region then table.insert(list, "region:" .. region) end
				addSource(drop.item, {specs = list, region = region, level = whole(m.level), rank = 3, id = mid})
			end
		end
	end
	for _, list in pairs(sources) do
		table.sort(list, function(a, b)
			if a.level ~= b.level then return a.level < b.level end
			if a.rank ~= b.rank then return a.rank < b.rank end
			return tostring(a.id or a.specs[1]) < tostring(b.id or b.specs[1])
		end)
	end
end
-- specs of the lowest-level source the player can reach, or nil plus the
-- requirement of the nearest locked one (nil, nil: no known source).
local function itemSource(id, ctx)
	if type(id) ~= "string" then return nil end
	if not sources then buildSources() end
	local locked
	for _, src in ipairs(tab(sources[id])) do
		if regionOpen(ctx, src.region) then return table.clone(src.specs) end
		locked = locked or src.region
	end
	return nil, if locked then HP.requirement(locked) else nil
end
HP.itemSource = itemSource
-- The best gathering node a skill level reaches in an open region (for "reach level N" steps).
local function bestNode(skill, lvl, ctx)
	local best
	for _, r in ipairs(tab(Data.ResourceTiers[skill])) do
		if r.level <= math.max(1, lvl) and regionOpen(ctx, nodeRegion(r.id)) then best = r end
	end
	return best and best.id
end
-- Waypoint specs for one check: specs, or nil plus a requirement text when the
-- place lies in a locked region (nil, nil: nowhere in particular to go).
-- ctx = {level = current level for "level" checks, access = {[region] = bool}}.
function HP.specsFor(o, ctx)
	o = tab(o)
	local kind = o.kind
	local function gate(region, list)
		if regionOpen(ctx, region) then return list end
		return nil, HP.requirement(region)
	end
	if kind == "kills" then
		local m = type(o.monster) == "string" and Data.Monsters[o.monster]
		if not m then return nil end
		local list = {"monster:" .. o.monster}
		if type(m.region) == "string" then table.insert(list, "region:" .. m.region) end
		return gate(m.region, list)
	elseif kind == "collect" or kind == "have" or kind == "collectionTier" or kind == "craft" then
		return itemSource(o.item, ctx)
	elseif kind == "gather" then return gate(o.region, {"region:" .. tostring(o.region)})
	elseif kind == "talk" then return {"npc:" .. tostring(o.npc)}
	elseif kind == "visit" then
		local l = Data.RegionArt and Data.RegionArt.LandmarkById[o.landmark]
		local list = {"anchor:Waypoint_Landmark_" .. tostring(o.landmark)}
		if l then table.insert(list, "region:" .. l.region) end
		return gate(l and l.region, list)
	elseif kind == "level" then
		if Data.ResourceTiers[o.skill] then
			local node = bestNode(o.skill, whole(tab(ctx).level), ctx)
			return if node then {"gather:" .. node} else nil
		elseif o.skill == "Combat" then return {"monster:BramblebackBoar", "region:Meadow"} end
		return nil
	elseif kind == "build" then return {"home"}
	elseif kind == "slayer" then return {"npc:Slayer", "anchor:Waypoint_SlayerMaster"}
	elseif kind == "contracts" then return {"npc:Guide"}
	elseif kind == "flag" and o.flag == "skyreachVisited" then return gate("Skyreach", {"region:Skyreach"})
	elseif kind == "laps" then return {"anchor:Waypoint_Agility_" .. tostring(o.course)}
	elseif kind == "catches" then return {"anchor:Waypoint_Hunting_" .. tostring(o.creature)}
	end
	return nil
end
local function describe(o, regional)
	local ok, text = pcall(Data.describeCheck, o, regional)
	return if ok and type(text) == "string" then text else "Task"
end
-- {have, need} from a Journal.state progress list (have capped at need).
local function pairOf(list, i, o)
	local pair = tab(tab(list)[i])
	local need = num(pair[2])
	if need <= 0 then need = math.max(1, num(tab(o).count) + num(tab(o).level) + num(tab(o).tier)) end
	return math.min(num(pair[1]), need), need
end
-- ctx: {access, regional}; a step in a locked region carries `blocked` (the
-- requirement text) instead of waypoint specs.
local function checkStep(o, list, i, phase, ctx)
	ctx = tab(ctx)
	local have, need = pairOf(list, i, o)
	local specs, blocked = HP.specsFor(o, {level = have, access = ctx.access})
	return {text = describe(o, ctx.regional and phase == "task"), have = have, need = need, met = have >= need, phase = phase,
		specs = specs, blocked = if specs then nil else blocked, npc = if tab(o).kind == "talk" then o.npc else nil}
end
local function finish(g)
	g.total, g.done = #g.steps, 0
	for i, s in ipairs(g.steps) do
		if s.met then g.done += 1 elseif not g.current then g.current = i end
	end
	g.current = g.current or #g.steps
	return g
end
-- entry: a Journal.state quest row {done, available, ready, requires = {{have, need}}, objectives = {...}};
-- ctx.accepted: a regional quest taken from its giver; ctx.access: region access.
function HP.questGuide(q, entry, ctx)
	entry, ctx = tab(entry), tab(ctx)
	local RA = Data.RegionArt
	local giver = q.giver and RA and RA.FolkByRole[q.giver]
	local g = {id = "quest:" .. q.id, kind = "quest", title = q.title, steps = {}}
	if entry.done == true then
		g.status = "done"
		table.insert(g.steps, {text = "Quest complete", have = 1, need = 1, met = true, phase = "claim"})
		return finish(g)
	end
	local sctx = {access = ctx.access, regional = q.giver ~= nil}
	for i, o in ipairs(q.requires) do table.insert(g.steps, checkStep(o, entry.requires, i, "requires", sctx)) end
	if giver then
		table.insert(g.steps, {text = "Accept the quest from " .. giver.name, have = if ctx.accepted then 1 else 0, need = 1,
			met = ctx.accepted == true, phase = "accept", specs = {"npc:" .. q.giver}, npc = q.giver})
	end
	for i, o in ipairs(q.objectives) do table.insert(g.steps, checkStep(o, entry.objectives, i, "task", sctx)) end
	if giver then
		table.insert(g.steps, {text = "Return to " .. giver.name .. " to hand it in", have = 0, need = 1, met = false, phase = "claim",
			specs = {"npc:" .. q.giver}, npc = q.giver})
	else
		table.insert(g.steps, {text = "Claim it in your Journal (Quests)", have = 0, need = 1, met = false, phase = "claim"})
	end
	finish(g)
	local cur = g.steps[g.current]
	g.status = if cur.phase == "requires" then "locked" elseif cur.phase == "accept" then "accept" elseif cur.phase == "claim" then "ready" else "active"
	return g
end
-- tier: a Journal.state diary tier {tier, tasks = {{have, need}}, claimable, claimed}.
function HP.diaryGuide(diary, tierName, tier, ctx)
	tier = tab(tier)
	local sctx = {access = tab(ctx).access}
	local def = diary.tiers[tierName]
	local g = {id = "diary:" .. diary.region, kind = "diary", title = diary.name .. " (" .. tierName .. ")", steps = {}}
	for i, o in ipairs(def.tasks) do table.insert(g.steps, checkStep(o, tier.tasks, i, "task", sctx)) end
	table.insert(g.steps, {text = "Claim the " .. tierName .. " tier in Journal › Diaries", have = if tier.claimed then 1 else 0, need = 1,
		met = tier.claimed == true, phase = "claim"})
	finish(g)
	g.status = if tier.claimed then "done" elseif tier.claimable then "ready" else "active"
	return g
end
-- The tier a diary guide follows: the first unclaimed one (Elite once all are claimed).
function HP.diaryTier(claimed)
	return Data.DiaryTiers[math.min(#Data.DiaryTiers, whole(claimed) + 1)]
end
-- state: the snapshot `quest` row {title, detail, ready, stage, total, complete}.
function HP.contractGuide(state)
	state = tab(state)
	local g = {id = "contract", kind = "contract", title = "Guild contract: " .. tostring(state.title or "—"), steps = {}}
	if state.complete then
		g.status = "done"
		table.insert(g.steps, {text = "Every guild contract is complete", have = 1, need = 1, met = true, phase = "claim"})
		return finish(g)
	end
	table.insert(g.steps, {text = tostring(state.detail or state.title or "Contract"), have = if state.ready then 1 else 0, need = 1,
		met = state.ready == true, phase = "task", specs = HP.ContractSpecs[whole(state.stage)]})
	table.insert(g.steps, {text = "Claim it in Journal › Bearing", have = 0, need = 1, met = false, phase = "claim"})
	finish(g)
	g.status = if state.ready then "ready" else "active"
	return g
end
-- One line for the sidebar Objective slot.
function HP.objective(g)
	g = tab(g)
	local s = tab(tab(g.steps)[g.current or 1])
	local text = tostring(s.text or g.title or "")
	if num(s.need) > 1 then text ..= " " .. whole(s.have) .. "/" .. whole(s.need) end
	return text
end
-- Valid pin ids: "quest:<id>", "diary:<region>", "contract".
function HP.validPin(id)
	if id == "contract" then return true end
	if type(id) ~= "string" or #id > HP.PIN_MAX then return false end
	local kind, arg = string.match(id, "^(%a+):(%w+)$")
	if kind == "quest" then return Data.QuestById[arg] ~= nil end
	if kind == "diary" then return Data.DiaryByRegion[arg] ~= nil end
	return false
end

-- Goal board ---------------------------------------------------------------
-- p.goals = {{id, k, a, n, at, done}} (≤ GL.MAX). Spec "kind:arg:n".
local GL = {}
SY.Goals = GL
GL.MAX = 12
GL.WINDOW = 1800 -- seconds of samples behind an ETA (rolling, server-side, session-only)
GL.SAMPLE = 60   -- seconds between samples
GL.Kinds = {
	level = {name = "Skill level", max = 99},
	xp = {name = "Skill XP", max = 200000000},
	tier = {name = "Collection tier"},
	item = {name = "Item count", max = 10000000},
	quest = {name = "Quest", max = 1},
	kills = {name = "Boss kills", max = 100000},
}
GL.Order = {"level", "xp", "tier", "item", "quest", "kills"}
-- Lair bosses (p.lairs.kc) or any bestiary creature, world bosses included (p.bestiary).
local function killSource(id)
	if type(id) ~= "string" then return nil end
	local LR = Data.Lairs
	if LR and LR.Bosses and LR.Bosses[id] then return "lair" end
	if Data.Monsters[id] then return "bestiary" end
	return nil
end
GL.killSource = killSource
function GL.bossName(id)
	local LR = Data.Lairs
	local d = (LR and LR.Bosses and LR.Bosses[id]) or Data.Monsters[id]
	return if d and d.name then d.name else tostring(id)
end
-- Kill-count goal targets for the board: lair bosses, then world bosses.
function GL.bosses()
	local out = {}
	for _, id in ipairs(tab(Data.Lairs and Data.Lairs.Order)) do table.insert(out, id) end
	local world = {}
	for id in pairs(tab(Data.WorldBosses)) do table.insert(world, id) end
	table.sort(world)
	for _, id in ipairs(world) do table.insert(out, id) end
	return out
end
-- Returns goal {k, a, n} or nil, reason.
function GL.parse(spec)
	if type(spec) ~= "string" or #spec > 64 then return nil, "Choose a goal." end
	local k, a, raw = string.match(spec, "^(%a+):(%w+):(%d+)$")
	local kind = k and GL.Kinds[k]
	if not kind then return nil, "Choose a goal." end
	if #raw > 9 or string.match(raw, "^0") then return nil, "Choose a whole target." end
	local n = tonumber(raw)
	if not n or n < 1 then return nil, "Choose a whole target." end
	if k == "level" or k == "xp" then
		if not Data.Skills[a] then return nil, "Choose a skill." end
		if k == "level" and n < 2 then return nil, "Choose a level from 2 to 99." end
	elseif k == "tier" then
		if not table.find(Data.CollectionItems, a) then return nil, "Choose a collection." end
		if n > #Data.CollectionTiers then return nil, "Collections have " .. #Data.CollectionTiers .. " tiers." end
	elseif k == "item" then
		if not Data.Items[a] then return nil, "Choose an item." end
	elseif k == "quest" then
		if not Data.QuestById[a] then return nil, "Choose a quest." end
	elseif k == "kills" then
		if not killSource(a) then return nil, "Choose a creature or boss." end
	end
	if kind.max and n > kind.max then return nil, kind.name .. " goals go up to " .. kind.max .. "." end
	return {k = k, a = a, n = n}
end
-- have, need on the goal's own scale (XP for level goals).
function GL.measure(p, goal, P)
	p, goal = tab(p), tab(goal)
	local k, a, n = goal.k, goal.a, whole(goal.n)
	if k == "level" then return num(tab(p.xp)[a]), Data.XP_TABLE[math.clamp(n, 1, Data.MAX_LEVEL or 99)] or 0
	elseif k == "xp" then return num(tab(p.xp)[a]), n
	elseif k == "tier" then
		local need = if P and P.collectionThreshold then P.collectionThreshold(a, n)
			else math.max(1, math.floor((Data.CollectionTiers[n] or 0) * (Data.CollectionScale[a] or 1)))
		return num(tab(p.collection)[a]), need or 0
	elseif k == "item" then return num(tab(p.items)[a]), n
	elseif k == "quest" then return if tab(p.questsDone)[a] then 1 else 0, 1
	elseif k == "kills" then
		if killSource(a) == "lair" then return num(tab(tab(p.lairs).kc)[a]), n end
		return num(tab(p.bestiary)[a]), n
	end
	return 0, 1
end
function GL.label(goal)
	goal = tab(goal)
	local k, a, n = goal.k, goal.a, whole(goal.n)
	if k == "level" then return tostring(a) .. " level " .. n
	elseif k == "xp" then return tostring(a) .. " " .. n .. " XP"
	elseif k == "tier" then return nameOf(a) .. " collection tier " .. n
	elseif k == "item" then return n .. " " .. nameOf(a)
	elseif k == "quest" then local q = Data.QuestById[a]; return "Complete " .. (if q then q.title else tostring(a))
	elseif k == "kills" then return n .. " " .. GL.bossName(a) .. " kills"
	end
	return "Goal"
end
-- Seconds until `remaining` at `perHour` (nil when there is no recent progress).
function GL.eta(remaining, perHour)
	remaining, perHour = num(remaining), num(perHour)
	if remaining <= 0 then return 0 end
	if perHour <= 0 then return nil end
	return math.ceil(remaining / perHour * 3600)
end
function GL.etaText(seconds)
	if seconds == nil then return "no recent progress" end
	seconds = whole(seconds)
	if seconds <= 0 then return "done" end
	if seconds >= 86400 * 99 then return "over 99 days" end
	local d, h, m = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60
	if d > 0 then return d .. "d " .. h .. "h" end
	if h > 0 then return h .. "h " .. m .. "m" end
	return math.max(1, m) .. "m"
end
-- Rate per hour from samples {{t, v}...} (oldest first) inside the window.
function GL.rate(samples, now)
	local list = tab(samples)
	local last = list[#list]
	if not last then return 0 end
	local first
	for _, s in ipairs(list) do if num(now) - num(s[1]) <= GL.WINDOW then first = s; break end end
	if not first or first == last then return 0 end
	local span = num(last[1]) - num(first[1])
	if span < 60 then return 0 end
	return math.max(0, (num(last[2]) - num(first[2])) / span * 3600)
end

-- Market price history -----------------------------------------------------
-- Hourly buckets kept for PR.HOURS. Bazaar: inside the shared key
-- (bazaar_v1_<item>.history), written in the same atomic transform as the
-- trade. Auction House: in its own key per category (hist:auction:<cat> =
-- {history = {[item] = buckets}, seen = {recent sale ids}, version}), merged by
-- a separate best-effort UpdateAsync after the sale commits (per-server queue,
-- one write per category per PR.FLUSH seconds); the write is at-least-once and
-- PR.mergeAuction drops any sale id already in `seen` (<= PR.SEEN ids), so a
-- retried flush never counts a sale twice. History is cross-server and a
-- replayed order never counts twice.
-- A bucket is {h = os.time() // 3600, n, v, lo, hi, m, c, t, x}:
--   n / v / lo / hi  counted units, their coins, low and high (averages only);
--   x                units left out of the averages (outliers, pair-cap excess);
--   m                volume-weighted median of every pair-capped fill (the next
--                    hour's outlier reference);
--   c                volume-weighted median of the counted fills (omitted when = m);
--   t                distinct traders (makers and takers) in the hour.
-- Only the newest (open) bucket also carries q = {{price, units, counted}}
-- (a price ladder, <= caps.levels rows), u = {trader ids} (<= caps.ids) and
-- pr = {["a|b"] = units} (<= caps.pairs, then one shared "*" row); they are
-- folded into m / c / t and dropped once the hour is over.
-- Wash-trade resistance (§33 QC M1): a fill more than PR.OUTLIER x (or under
-- 1 / PR.OUTLIER x) the previous bucket's median, and any units one maker /
-- taker pair trades beyond caps.pair in one hour, are left out of the averages;
-- prices shown are per-bucket medians; fewer than PR.THIN distinct traders in
-- the window reads "thin market". No tax is involved.
local PR = {}
SY.Prices = PR
PR.HOURS = 168            -- 7 days of hourly buckets
PR.AUCTION_BUCKETS = 1200 -- total buckets per auction history key (oldest evicted first)
PR.AUCTION_ITEMS = 96     -- distinct items tracked per auction history key
PR.SPARK = 28             -- sparkline points: 7 days at 6 hours each
PR.CHECKS = 8             -- price checks remembered per player (session)
PR.OUTLIER = 3            -- fills > 3x / < 1/3x the previous bucket's median skip the averages
PR.THIN = 3               -- fewer distinct traders than this in the window: "thin market"
PR.BazaarCaps = {pair = 160, levels = 24, ids = 8, pairs = 32} -- units per maker/taker pair per hour
PR.AuctionCaps = {pair = 2, levels = 6, ids = 4, pairs = 6}    -- sales per seller/buyer pair per hour
PR.HIST_PREFIX = "hist:auction:" -- auction history key prefix (one key per category)
PR.SEEN = 512             -- recent sale / migration ids kept per auction history key (dedupe)
PR.FLUSH = 6              -- seconds between a server's history flushes (one write per key per 6 s)
PR.QUEUE = 200            -- pending history entries per category per server (oldest dropped)
PR.ATTEMPTS = 5           -- failed flushes before a pending entry is dropped (best effort)
function PR.hour(t) return math.floor(num(t) / 3600) end
-- Volume-weighted median of a price ladder (field 2 = every pair-capped unit, 3 = counted).
local function median(q, field)
	local rows, total = {}, 0
	for _, e in ipairs(tab(q)) do
		local price, w = whole(tab(e)[1]), whole(tab(e)[field])
		if price > 0 and w > 0 then table.insert(rows, {price, w}); total += w end
	end
	if total <= 0 then return nil end
	table.sort(rows, function(a, b) return a[1] < b[1] end)
	local acc = 0
	for _, r in ipairs(rows) do
		acc += r[2]
		if acc * 2 >= total then return r[1] end
	end
	return rows[#rows][1]
end
PR.median = median
-- A bucket's reference median (every pair-capped fill), or nil.
local function refOf(b)
	if type(b.q) == "table" then local m = median(b.q, 2); if m then return m end end
	if num(b.m) > 0 then return whole(b.m) end
	if whole(b.n) > 0 then return math.floor(whole(b.v) / whole(b.n) + 0.5) end
	return nil
end
-- A bucket's shown price: the median of its counted fills (nil when nothing counted).
local function priceOf(b)
	if whole(b.n) <= 0 then return nil end
	if type(b.q) == "table" then local c = median(b.q, 3); if c then return c end end
	if num(b.c) > 0 then return whole(b.c) end
	if num(b.m) > 0 then return whole(b.m) end
	return math.floor(whole(b.v) / whole(b.n) + 0.5) -- legacy bucket (no medians)
end
PR.priceOf = priceOf
-- Distinct traders in a bucket (legacy buckets, which never counted, are not "thin").
local function tradersOf(b)
	if type(b.u) == "table" then return math.max(#b.u, whole(b.t)) end
	if b.t == nil then return PR.THIN end
	return whole(b.t)
end
-- Folds the open-hour ladders into m / c / t.
local function close(b)
	if type(b.q) ~= "table" and b.u == nil and b.pr == nil then return end
	local m, c = refOf(b), priceOf(b)
	b.t = tradersOf(b)
	b.m = m
	b.c = if c and c ~= m then c else nil
	b.q, b.u, b.pr = nil, nil, nil
end
-- Drops malformed buckets and buckets older than 7 days; keeps a bucket up to
-- one hour ahead (another server's clock may run slightly ahead), merges
-- buckets sharing an hour, closes every bucket before `hour` and keeps hour order.
function PR.prune(list, hour)
	local byHour = {}
	local i = 1
	while i <= #list do
		local b = list[i]
		if type(b) ~= "table" or type(b.h) ~= "number" or b.h ~= b.h or b.h <= hour - PR.HOURS or b.h > hour + 1 then
			table.remove(list, i)
		else
			b.h = math.floor(b.h)
			local same = byHour[b.h]
			if same then
				close(same); close(b)
				local n = whole(same.n) + whole(b.n)
				if n > 0 then
					same.c = math.floor(((priceOf(same) or 0) * whole(same.n) + (priceOf(b) or 0) * whole(b.n)) / n + 0.5)
				end
				same.m = same.m or b.m
				same.n, same.v = n, whole(same.v) + whole(b.v)
				same.x = if whole(same.x) + whole(b.x) > 0 then whole(same.x) + whole(b.x) else nil
				if whole(b.n) > 0 then
					same.lo = math.min(if same.lo then whole(same.lo) else math.huge, whole(b.lo))
					same.hi = math.max(whole(same.hi), whole(b.hi))
				end
				same.t = math.max(tradersOf(same), tradersOf(b))
				table.remove(list, i)
			else
				byHour[b.h] = b
				i += 1
			end
		end
	end
	table.sort(list, function(a, b) return a.h < b.h end)
	for _, b in ipairs(list) do if b.h < hour then close(b) end end
	while #list > PR.HOURS do table.remove(list, 1) end
	return list
end
-- Adds units to a price ladder (merged into the nearest price once full).
local function addLevel(q, price, units, counted, levels)
	local best, bestD
	for _, e in ipairs(q) do
		if e[1] == price then best, bestD = e, 0; break end
		local d = math.abs(e[1] - price)
		if not bestD or d < bestD then best, bestD = e, d end
	end
	if not best or (bestD > 0 and #q < levels) then
		table.insert(q, {price, units, counted})
	else
		best[2] += units; best[3] += counted
	end
end
-- Adds one fill (units at a unit price) between traders a (maker / seller) and
-- b (taker / buyer) to a bucket list. caps defaults to PR.BazaarCaps.
function PR.record(list, hour, price, units, a, b, caps)
	price, units = whole(price), whole(units)
	if price <= 0 or units <= 0 then return list end
	caps = if type(caps) == "table" then caps else PR.BazaarCaps
	PR.prune(list, hour)
	local bucket, prev
	for _, x in ipairs(list) do
		if x.h == hour then bucket = x elseif x.h < hour then prev = x end
	end
	if not bucket then
		bucket = {h = hour, n = 0, v = 0}
		local at = #list + 1
		for k, x in ipairs(list) do if x.h > hour then at = k; break end end
		table.insert(list, at, bucket)
	end
	if type(bucket.q) ~= "table" then
		-- Open (or re-open, after a clock-skewed close) the hour's ladders.
		local q = {}
		local m, c = refOf(bucket), priceOf(bucket)
		if c then table.insert(q, {c, whole(bucket.n), whole(bucket.n)}) end
		if m and m ~= c then table.insert(q, {m, 1, 0}) end
		bucket.q, bucket.u, bucket.pr = q, {}, {}
	end
	-- Distinct traders (a bounded list of ids).
	for _, id in ipairs({a or false, b or false}) do
		id = if type(id) == "string" or type(id) == "number" then tostring(id) else nil
		if id and #id <= 24 and #bucket.u < caps.ids and not table.find(bucket.u, id) then table.insert(bucket.u, id) end
	end
	-- Pair cap: units one maker / taker pair adds to this hour's averages.
	local within = units
	if a ~= nil and b ~= nil then
		local x, y = tostring(a), tostring(b)
		local key = if x < y then x .. "|" .. y else y .. "|" .. x
		if #key > 49 then key = "*" end
		if bucket.pr[key] == nil then
			local rows = 0
			for _ in pairs(bucket.pr) do rows += 1 end
			if rows >= caps.pairs then key = "*" end
		end
		local used = whole(bucket.pr[key])
		within = math.clamp(caps.pair - used, 0, units)
		bucket.pr[key] = math.min(caps.pair, used + units)
	end
	-- Outliers against the previous bucket's median.
	local ref = prev and refOf(prev)
	local outlier = ref ~= nil and (price > ref * PR.OUTLIER or price * PR.OUTLIER < ref)
	local counted = if outlier then 0 else within
	if counted > 0 then
		bucket.n = whole(bucket.n) + counted; bucket.v = whole(bucket.v) + price * counted
		bucket.lo = math.min(if bucket.lo then whole(bucket.lo) else math.huge, price)
		bucket.hi = math.max(whole(bucket.hi), price)
	end
	if units > counted then bucket.x = whole(bucket.x) + units - counted end
	if within > 0 then addLevel(bucket.q, price, within, counted, caps.levels) end
	return list
end
-- Auction history: one list per item under one bounded total. Prunes every
-- list to `hour`, drops empty ones and evicts the oldest bucket until the caps
-- hold. The item `keep` is never the one evicted while another item can give a
-- bucket up (and never loses its last bucket).
local function capAuction(hist, hour, keep)
	local items, total = 0, 0
	for id, l in pairs(hist) do
		if type(l) == "table" then PR.prune(l, hour) end
		if type(id) ~= "string" or type(l) ~= "table" or #l == 0 then hist[id] = nil else items += 1; total += #l end
	end
	while total > PR.AUCTION_BUCKETS or items > PR.AUCTION_ITEMS do
		local oldestId, oldestH
		for id, l in pairs(hist) do
			if id ~= keep and (not oldestH or l[1].h < oldestH or (l[1].h == oldestH and id < oldestId)) then oldestId, oldestH = id, l[1].h end
		end
		if not oldestId then
			-- Only the kept item is left: trim its own oldest bucket, never its last.
			local own = keep and hist[keep]
			if not own or #own <= 1 then break end
			oldestId = keep
		end
		table.remove(hist[oldestId], 1)
		total -= 1
		if #hist[oldestId] == 0 then hist[oldestId] = nil; items -= 1 end
	end
	return hist
end
function PR.recordAuction(hist, item, hour, price, seller, buyer)
	local list = type(hist[item]) == "table" and hist[item] or {}
	hist[item] = list
	PR.record(list, hour, price, 1, seller, buyer, PR.AuctionCaps)
	return capAuction(hist, hour, item)
end
function PR.histKey(cat) return PR.HIST_PREFIX .. tostring(cat) end
function PR.normalizeHist(book)
	book = if type(book) == "table" then book else {}
	if type(book.history) ~= "table" then book.history = {} end
	if type(book.seen) ~= "table" then book.seen = {} end
	book.version = 1
	return book
end
-- Merges queued entries into an auction history key value (the UpdateAsync
-- transform). An entry is a sale {id = "s<listing id>", item, h, price, seller,
-- buyer} or a migration {id = "m<auction key revision>", moved = legacy
-- auction_v1_<cat>.history}. Ids already in book.seen are skipped (at-least-once
-- flushes count once). A sale recorded late keeps its hour, clamped to the
-- previous hour at the earliest, so pruning never drops a newer server's bucket.
-- Returns the book and the number of entries applied (0: cancel the write).
function PR.mergeAuction(book, entries, hour)
	book = PR.normalizeHist(book)
	local hist, seen = book.history, book.seen
	local known = {}
	for _, id in ipairs(seen) do known[id] = true end
	local added = 0
	for _, e in ipairs(tab(entries)) do
		local id = if type(e) == "table" and type(e.id) == "string" then e.id else nil
		if id and not known[id] then
			known[id] = true
			table.insert(seen, id)
			added += 1
			if type(e.moved) == "table" then
				for item, list in pairs(e.moved) do
					if type(item) == "string" and type(list) == "table" then
						local own = if type(hist[item]) == "table" then hist[item] else {}
						for _, b in ipairs(list) do table.insert(own, b) end
						hist[item] = own
					end
				end
				capAuction(hist, hour, nil)
			elseif type(e.item) == "string" then
				PR.recordAuction(hist, e.item, math.clamp(whole(e.h), hour - 1, hour), e.price, e.seller, e.buyer)
			end
		end
	end
	while #seen > PR.SEEN do table.remove(seen, 1) end
	return book, added
end
-- Snapshot summary {item, last, avg24, vol24, avg7, vol7, lo7, hi7, traders24,
-- traders7, thin, spark = {PR.SPARK prices; 0 = no trades}, at}. Averages are
-- volume-weighted means of the per-bucket medians over counted units; traders
-- are the most distinct traders seen in one hour of the window.
function PR.summary(list, now, item)
	local hour = PR.hour(now)
	local out = {item = item, vol24 = 0, vol7 = 0, traders24 = 0, traders7 = 0, spark = {}, at = whole(now)}
	local v24, v7 = 0, 0
	local sn, sv = {}, {}
	local lastH
	for _, b in ipairs(tab(list)) do
		if type(b) == "table" and type(b.h) == "number" and b.h == b.h then
			local age = math.max(0, hour - b.h) -- a bucket up to an hour ahead (clock skew) counts as now
			if b.h <= hour + 1 and age < PR.HOURS and (whole(b.n) > 0 or whole(b.x) > 0) then
				local t = tradersOf(b)
				out.traders7 = math.max(out.traders7, t)
				if age < 24 then out.traders24 = math.max(out.traders24, t) end
				local price = priceOf(b)
				if price then
					local n = whole(b.n)
					out.vol7 += n; v7 += price * n
					out.lo7 = math.min(out.lo7 or math.huge, if b.lo then whole(b.lo) else price)
					out.hi7 = math.max(out.hi7 or 0, if b.hi then whole(b.hi) else price)
					if age < 24 then out.vol24 += n; v24 += price * n end
					local slot = PR.SPARK - age // (PR.HOURS // PR.SPARK)
					sn[slot] = (sn[slot] or 0) + n; sv[slot] = (sv[slot] or 0) + price * n
					if not lastH or b.h >= lastH then lastH = b.h; out.last = price end
				end
			end
		end
	end
	for i = 1, PR.SPARK do out.spark[i] = if (sn[i] or 0) > 0 then math.floor(sv[i] / sn[i] + 0.5) else 0 end
	out.avg24 = if out.vol24 > 0 then math.floor(v24 / out.vol24 + 0.5) else nil
	out.avg7 = if out.vol7 > 0 then math.floor(v7 / out.vol7 + 0.5) else nil
	out.thin = out.traders7 < PR.THIN or (out.vol24 > 0 and out.traders24 < PR.THIN)
	return out
end
-- "Price check" line for tooltips and market cards.
function PR.text(s)
	s = tab(s)
	if not s.avg7 then return "No trades in the last 7 days" end
	local parts = {}
	if s.avg24 then table.insert(parts, "24h avg " .. s.avg24 .. " (" .. whole(s.vol24) .. " sold)") else table.insert(parts, "no trades in 24h") end
	table.insert(parts, "7d avg " .. s.avg7)
	if s.lo7 and s.hi7 then table.insert(parts, "range " .. s.lo7 .. "–" .. s.hi7) end
	if s.thin then table.insert(parts, "thin market") end
	return table.concat(parts, "  ·  ")
end
-- Which key holds an item's history: its Bazaar key (commodities) or its
-- auction category's history key. Returns key, kind, category.
function PR.keyFor(id)
	local E = Data.Economy
	if E.isCommodity(id) then return "bazaar_v1_" .. id, "bazaar" end
	local cat = E.auctionCategory(id)
	if cat then return PR.histKey(cat), "auction", cat end
	return nil
end

-- Per-player daily shop stock --------------------------------------------------
-- p.shopStock = {day = UTC day index, n = {[key] = units bought today}}. The day
-- only rolls forward (a server whose clock runs behind keeps the newer day).
-- Limits are per ITEM across every shop (§33 QC M2): a regional shop, a skill
-- vendor and the Roost keeper selling the same ware share one daily count, so
-- the key is "it:<item>" whichever shop is asked (ST.key keeps its old
-- signature for callers). Limits count units, not lots.
local ST = {}
SY.Stock = ST
ST.Limits = {Tonic=64, CookedFish=64, AlloyIngot=64, ArcaneDust=64, StormFeather=32, MightDraught=16, Shard=16, Stormglass=8,
	GaleDraught=32, SkymarkSatchel=64, PetCandy=16}
function ST.day(t) return math.floor(num(t) / 86400) end
-- key("rq", role, item) / key("sv", skill, item) / key("roost", item) -> "it:<item>".
function ST.key(shop, owner, item)
	if shop == "roost" then item = owner end
	return "it:" .. tostring(item)
end
-- Does any shop sell this item (so its limit applies)?
local sold
local function soldAnywhere(id)
	if not sold then
		sold = {}
		for _, f in ipairs(tab(Data.RegionArt and Data.RegionArt.Folk)) do
			for _, o in ipairs(tab(f.shop)) do if type(o.item) == "string" then sold[o.item] = true end end
		end
		for _, v in pairs(tab(Data.SkillVendors)) do
			for _, e in ipairs(tab(v.shop)) do if type(e.item) == "string" then sold[e.item] = true end end
		end
		local PD = Data.PetDepth
		for id in pairs(tab(PD and PD.ShopByItem)) do sold[id] = true end
	end
	return sold[id] == true
end
-- Daily unit limit for a key, or nil (unlimited).
function ST.limit(key)
	if type(key) ~= "string" or #key > 64 then return nil end
	local id = string.match(key, "^it:(%w+)$")
	if id and ST.Limits[id] and soldAnywhere(id) then return ST.Limits[id] end
	return nil
end
-- The item a key counts: "it:<item>", or a legacy per-shop key
-- ("rq:<role>:<item>", "sv:<Skill>:<item>", "roost:<item>") saved before M2.
local function itemOfKey(key)
	if type(key) ~= "string" or #key > 64 then return nil end
	return string.match(key, "^it:(%w+)$") or string.match(key, "^%a+:%w+:(%w+)$") or string.match(key, "^roost:(%w+)$")
end
-- Rolls the record to today's UTC day (forward only); keeps only limited keys
-- (legacy per-shop keys fold into their item's key).
function ST.roll(rec, now)
	rec = tab(rec)
	local today = ST.day(now)
	-- A stored day ahead of this clock keeps its counts (a server clock running
	-- behind never restocks early); a day more than one ahead (tampered or broken
	-- clock) is pulled back to tomorrow, so it can never lock a shop for long.
	local day = whole(rec.day)
	if day > today + 1 then day = today + 1 end
	local counts = {}
	if day >= today then
		for key, v in pairs(tab(rec.n)) do
			local id = itemOfKey(key)
			local k = if id then "it:" .. id else nil
			local lim = k and ST.limit(k)
			if lim and whole(v) > 0 then counts[k] = math.min(whole(counts[k]) + whole(v), lim) end
		end
	end
	return {day = math.max(day, today), n = counts}
end
-- Units left today and the limit (nil, nil when unlimited).
function ST.left(rec, key)
	local lim = ST.limit(key)
	if not lim then return nil, nil end
	return math.max(0, lim - whole(tab(tab(rec).n)[key])), lim
end
function ST.text(left, lim) return whole(left) .. "/" .. whole(lim) .. " left today" end

-- XP calculator ----------------------------------------------------------------
local CA = {}
SY.Calc = CA
-- Actions that train a skill: gathering nodes, Data.Recipes, Crafting patterns
-- and Hunter creatures, {id, name, level, xp, kind}. Base XP (no boosts).
function CA.actions(skill)
	local out = {}
	for _, r in ipairs(tab(Data.ResourceTiers[skill])) do
		table.insert(out, {id = r.id, name = r.name, level = r.level, xp = r.xp, kind = "gather"})
	end
	for id, d in pairs(Data.Recipes) do
		if type(d) == "table" and d.skill == skill and num(d.xp) > 0 then
			table.insert(out, {id = id, name = nameOf(d.output or id), level = whole(d.level), xp = d.xp, kind = "craft"})
		end
	end
	local CR = Data.Crafting
	for _, id in ipairs(tab(CR and CR.RecipeOrder)) do
		local d = CR.Recipes[id]
		if d and d.skill == skill and num(d.xp) > 0 then
			table.insert(out, {id = id, name = nameOf(d.output or id), level = whole(d.level), xp = d.xp, kind = "craft"})
		end
	end
	if skill == "Hunter" and Data.Hunter then
		for _, c in ipairs(tab(Data.Hunter.Creatures)) do
			table.insert(out, {id = c.id, name = c.name, level = whole(c.level), xp = c.xp, kind = "catch"})
		end
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		if a.xp ~= b.xp then return a.xp < b.xp end
		return a.id < b.id
	end)
	return out
end
function CA.skills()
	local out = {}
	for _, skill in ipairs(Data.SkillOrder) do if #CA.actions(skill) > 0 then table.insert(out, skill) end end
	return out
end
-- {remaining, actions, goalXp} to reach `target` from `xp` at `each` XP per action.
function CA.plan(xp, target, each)
	local goal = Data.XP_TABLE[math.clamp(whole(target), 1, Data.MAX_LEVEL or 99)] or 0
	local remaining = math.max(0, goal - num(xp))
	local per = num(each)
	return {remaining = remaining, actions = if per > 0 then math.ceil(remaining / per) else nil, goalXp = goal}
end
end

-- Goal toasts ride the §31 announcement queue (Features.announce).
do
local F = Data.Features
local announceText = F.announceText
function F.announceText(e)
	if type(e) == "table" and e.kind == "goal" then
		return {head = "GOAL COMPLETE", body = tostring(e.title or "Goal"), color = "7CFFB2"}
	end
	return announceText(e)
end
end
-- <<< END Systems Depth <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Player settings (docs/DEPTH-CONTRACT.md §35 QC L6). The IsleSetting*
-- player attributes are client-set (and so never seen by the server); the
-- Settings page also sends the `setting` verb ("Attr=value") so the choice is
-- saved on the profile (p.settings) and re-applied as a server-set attribute
-- on join. Only this whitelist is accepted; values are validated per kind.
------------------------------------------------------------------------------
do
local S = {}
S.list = {
	{attr = "IsleSettingPinSatchel", kind = "bool"},
	{attr = "IsleSettingXpDrops", kind = "bool"},
	{attr = "IsleSettingMinimap", kind = "bool"},
	{attr = "IsleSettingReducedMotion", kind = "bool"},
	{attr = "IsleSettingGraphics", kind = "enum", values = {"High", "Balanced", "Performance"}}, -- = AetherLighting.TIER_ORDER (asserted)
}
S.byAttr = {}
for _, o in ipairs(S.list) do S.byAttr[o.attr] = o end
-- The validated value of a setting (bool / enum string), or nil.
function S.clean(attr, value)
	local o = type(attr) == "string" and S.byAttr[attr]
	if not o then return nil end
	if o.kind == "bool" then
		if value == true or value == "true" then return true end
		if value == false or value == "false" then return false end
		return nil
	end
	if type(value) == "string" and table.find(o.values, value) then return value end
	return nil
end
-- "Attr=value" (the verb's item) -> attr, value; nil when not whitelisted / invalid.
function S.parse(item)
	if type(item) ~= "string" or #item > 64 then return nil end
	local attr, raw = string.match(item, "^([%w_]+)=([%w_]+)$")
	local value = S.clean(attr, raw)
	if value == nil then return nil end
	return attr, value
end
function S.encode(attr, value) return tostring(attr) .. "=" .. tostring(value) end
-- A saved map with only whitelisted, valid entries (unknown keys dropped).
function S.sanitize(map)
	local out = {}
	if type(map) ~= "table" then return out end
	for _, o in ipairs(S.list) do
		local v = S.clean(o.attr, map[o.attr])
		if v ~= nil then out[o.attr] = v end
	end
	return out
end
Data.PlayerSettings = S
end
------------------------------------------------------------------------------
-- >>> BEGIN Beaconry (Beaconry team; append-only section; docs/DEPTH-CONTRACT.md §37) >>>
-- A 1-99 production skill with OSRS Firemaking depth (all names original):
--   * Kindle a log of any wood tier with a Flint Striker (held in the hand,
--     strike gesture "kindle"): level-gated, a success chance that rises with
--     level and striker tier, XP per log tier. A campfire burns for a while,
--     then goes out and leaves Pyre Ash for its kindler.
--   * Beacon network: one beacon pyre per region (B.Beacons). Feeding one
--     B.BEACON_LOGS logs lights it for B.BEACON_SECONDS: Beacon Warmth (a short
--     regional buff) for the lighter, everyone near it and anyone who basks in it
--     while it burns; every lighting counts toward the weekly community goal.
--   * Campfire cooking: Cooking's Hearth meals and feasts at any lit campfire
--     (paced batches, a burn chance by Cooking level, +10% Cooking XP) and two
--     dishes only a campfire can make.
--   * Pyre Ash: Alchemy (Emberward Draught) and Farming (composter matter).
-- Pure data and rules; server.server.lua (Beaconry block) runs it,
-- world.server.lua builds the beacon pyres, beaconry.server.lua draws the
-- campfires and beacon flames, ui.client.lua Workshop › Beaconry shows it.
------------------------------------------------------------------------------
do
local B = {}
Data.Beaconry = B
local function whole(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
	return math.floor(v)
end
B.whole = whole

-- Skill registration (appended: old saves keep their order).
table.insert(Data.SkillOrder, "Beaconry")
Data.Skills.Beaconry = {category="production",color="F26B38",title="Flamewarden",perLevel={health=1,intelligence=0.5},
	description="Kindle fires, cook at your own campfire and keep the isles' beacons burning. Raises Health and Intelligence."}
-- 99 mantle: stats plus "Everflame" (B.CAPE_*): kindles never fail, campfires
-- burn half as long again and beacon warmth lasts twice as long.
if Data.Mastery and Data.Mastery.CapePerk then Data.Mastery.CapePerk.Beaconry = {health=30,intelligence=20} end
B.CAPE_FIRE_MULT, B.CAPE_WARMTH_MULT = 1.5, 2

-- Pacing and bounds.
B.TICK = 0.5                 -- server loop (fires, cooking, week flush)
B.KINDLE_SECONDS = 2.4       -- one kindle attempt per 2.4 s (OSRS: four game ticks)
B.MAX_FIRES = 40             -- campfires burning on one server
B.MAX_PER_PLAYER = 4         -- a fifth kindle snuffs your oldest campfire
B.FIRE_SPACING = 3.5         -- studs between two campfires
B.BEACON_CLEARANCE = 12      -- no campfire this close to a beacon pyre
B.SUCCESS_BASE = 0.45        -- chance at the log's own level with a Flint Striker
B.SUCCESS_FADE = 25          -- levels above the log until a kindle never fails
B.COOK_RANGE = 9             -- studs from a lit campfire to cook on it
B.COOK_SECONDS = 1.8         -- one campfire cook per 1.8 s
B.MAX_BATCH = 28
B.FIRE_XP_MULT = 1.1         -- Cooking XP at a campfire
B.BURN_BASE, B.BURN_FADE = 0.35, 30 -- burn chance at the recipe level, gone 30 levels later
B.BEACON_LOGS = 6
B.BEACON_SECONDS = 600       -- a lit beacon burns ten minutes
B.BEACON_XP_MULT = 1.5       -- XP per log fed to a beacon, vs a campfire
B.BEACON_RANGE = 14          -- studs: bask / light only standing at the pyre
B.WARMTH_SECONDS = 300
B.WARMTH_RADIUS = 110        -- studs: players this close to a beacon when it is lit get warmth
B.WARMTH_ID = "Beacon Warmth" -- p.buffs key (one warmth at a time; a new one replaces it)
B.WEEK = 604800              -- UTC weeks since the epoch (Thursday 00:00 UTC)
B.WEEK_GOAL = 150            -- beacon lightings across every server in one week
B.FLUSH = 30                 -- seconds between community-total DataStore writes
B.WEEK_REFRESH = 60          -- QC M2: re-read the shared total (GetAsync) this often when nothing is pending
B.CLAIM_REFRESH = 10         -- QC M2: a claim refused below the goal re-reads the total at most this often
B.WEEK_KEY = "beaconry_week_"
-- QC M3: the weekly key holds per-server contributions {base=n, s={["<JobId>:<seg>"]={n=, t=}}}.
-- A server writes max(stored, its monotonic local count) for its own hourly
-- segment, so a write that timed out but committed is never counted twice.
-- Entries untouched for B.WEEK_FOLD seconds fold into base (servers write only
-- their current and previous segment, so a folded entry is never written again).
B.WEEK_SEG = 3600
B.WEEK_FOLD = 3 * 3600
-- QC H1: beacon XP is paid for the first B.BEACON_XP_PER_DAY lightings per
-- player per isle day (Data.Calendar.dayLength), saved on the profile, so
-- hopping servers to relight beacons never outpaces banked kindling.
B.BEACON_XP_PER_DAY = 9
B.SPOT_CLEARANCE = 6         -- QC L2: studs from prompts, spawn markers and townsfolk anchors
B.MAX_COUNT = 1000000000
B.ASH = "PyreAsh"
function B.weekOf(t) return math.floor(whole(t) / B.WEEK) end
function B.weekResetIn(t) t = whole(t); return (B.weekOf(t) + 1) * B.WEEK - t end
function B.dayOf(t)
	local cal = Data.Calendar
	return math.floor((whole(t) - (cal and cal.epoch or 0)) / (cal and cal.dayLength or 86400))
end
function B.weekSeg(t) return math.floor(whole(t) / B.WEEK_SEG) end
-- Community total stored under one week key (a legacy plain number is the base).
function B.weekSum(v)
	if type(v) == "number" then return math.max(0, whole(v)) end
	if type(v) ~= "table" then return 0 end
	local total = math.max(0, whole(v.base))
	for _, e in pairs(type(v.s) == "table" and v.s or {}) do
		if type(e) == "table" then total += math.max(0, whole(e.n)) end
	end
	return total
end
-- UpdateAsync transform: this server's segment counts (segs = {[seg] = count},
-- monotonic) merged idempotently; stale entries fold into base.
function B.weekMerge(old, jobId, segs, now)
	local v = {base = 0, s = {}}
	if type(old) == "number" then v.base = math.max(0, whole(old))
	elseif type(old) == "table" then
		v.base = math.max(0, whole(old.base))
		for k, e in pairs(type(old.s) == "table" and old.s or {}) do
			if type(k) == "string" and type(e) == "table" then v.s[k] = {n = math.max(0, whole(e.n)), t = whole(e.t)} end
		end
	end
	now = whole(now)
	for seg, n in pairs(type(segs) == "table" and segs or {}) do
		local key = tostring(jobId) .. ":" .. tostring(seg)
		local cur = v.s[key]
		v.s[key] = {n = math.max(cur and cur.n or 0, math.max(0, whole(n))), t = now}
	end
	for k, e in pairs(v.s) do
		if now - e.t > B.WEEK_FOLD then
			v.base += e.n
			v.s[k] = nil
		end
	end
	return v
end
-- Community reward for a journal that lit at least one beacon in a week whose
-- goal was met: Beaconry XP scaling with level (claimed once per week).
function B.weekXp(level) return 250 + 60 * math.clamp(whole(level), 1, 99) end

------------------------------------------------------------------------------
-- Logs: every Woodcutting tier (seven today). XP is 1.25x the log's
-- Woodcutting XP + 5 (OSRS Firemaking pays ~1.2-1.6x Woodcutting per log).
------------------------------------------------------------------------------
B.Logs, B.LogById = {}, {}
for i, r in ipairs(Data.ResourceTiers.Woodcutting) do
	local def = {id=r.id,name=r.name,level=r.level,tier=i,xp=math.floor(r.xp * 1.25 + 5),color=r.color,
		seconds=45 + 15 * i}  -- campfire burn time
	table.insert(B.Logs, def)
	B.LogById[r.id] = def
end
-- Success chance of one kindle: 45% at the log's level with a Flint Striker,
-- certain 25 levels later; each striker tier above the first adds 5%.
function B.successChance(level, log, strikerTier)
	if type(log) ~= "table" then return 0 end
	level = whole(level)
	if level < log.level then return 0 end
	local over = (level - log.level) / B.SUCCESS_FADE
	local c = B.SUCCESS_BASE + (1 - B.SUCCESS_BASE) * over + 0.05 * math.max(0, whole(strikerTier) - 1)
	return math.clamp(c, 0, 1)
end
function B.fireSeconds(log, cape)
	return math.floor((type(log) == "table" and log.seconds or 60) * (if cape then B.CAPE_FIRE_MULT else 1))
end

------------------------------------------------------------------------------
-- Items: strikers (Forge, Smithing; held class "striker", never used up),
-- Pyre Ash, the Emberward Draught and the two campfire-only dishes.
------------------------------------------------------------------------------
local function item(id, def)
	def.id = id
	def.rarity = def.rarity or "Common"
	def.value = def.value or 1
	Data.Items[id] = def
	return def
end
local function recipe(id, def)
	def.id = id
	def.output = def.output or id
	def.amount = def.amount or 1
	Data.Recipes[id] = def
	return def
end
local function valueOf(costs)
	local v = 0
	for id, n in pairs(costs) do v += (Data.Items[id] and Data.Items[id].value or 0) * n end
	return v
end
B.valueOf = valueOf
B.StrikerOrder = {"FlintStriker","SunsteelStriker","StarmetalStriker"}
B.Strikers = {}
for i, s in ipairs({
	{id="FlintStriker",name="Flint Striker",level=1,smithing=1,color="B9B2A6",costs={AlloyIngot=1,Ore=2},rarity="Common"},
	{id="SunsteelStriker",name="Sunsteel Striker",level=30,smithing=30,color="F2C14E",costs={SunsteelIngot=2,EmberoakLog=1},rarity="Uncommon"},
	{id="StarmetalStriker",name="Starmetal Striker",level=60,smithing=60,color="C9D6E3",costs={StarmetalIngot=2,StarwoodLog=1},rarity="Rare"},
}) do
	s.tier = i
	B.Strikers[s.id] = s
	-- Value stays under the inputs (no coin mint through the Forge).
	item(s.id,{name=s.name,kind="material",category="beaconTool",heldClass="striker",tier=i,rarity=s.rarity,color=s.color,
		value=math.max(1, math.floor(valueOf(s.costs) * 0.8)),requires={Beaconry=s.level},
		description="Beaconry tool (tier "..i.."): strike sparks to kindle logs. "..(if i > 1 then "+"..(5 * (i - 1)).."% kindle chance. " else "").."Never used up."})
	recipe(s.id,{skill="Smithing",level=s.smithing,xp=10 + s.smithing,costs=s.costs,station="Forge",category="Tools"})
end
-- Best striker a journal can use: the striker def or nil. levelOf(skill) -> level.
function B.bestStriker(items, levelOf)
	local best
	for _, id in ipairs(B.StrikerOrder) do
		local s = B.Strikers[id]
		if whole((items or {})[id]) > 0 and (not levelOf or levelOf("Beaconry") >= s.level) then best = s end
	end
	return best
end

item(B.ASH,{name="Pyre Ash",kind="material",rarity="Common",color="8A8178",value=2,
	description="Fine ash left when a campfire burns down. Alchemists bind it into draughts; gardeners feed it to the composter."})
table.insert(Data.CollectionItems, B.ASH)
Data.CollectionScale[B.ASH] = 0.5
-- Farming: ash is rich composter matter (Verdant Garden).
if Data.Garden and Data.Garden.ORGANIC_EXTRA then Data.Garden.ORGANIC_EXTRA[B.ASH] = 6 end
-- Alchemy: one ash potion (takes a Skyglass Vial like every Alchemy 8+ potion, §22).
item("EmberwardDraught",{name="Emberward Draught",kind="consumable",category="potion",rarity="Uncommon",color="E07A3F",
	buff={stats={defense=30,health=40},duration=300},value=20,requires={Alchemy=22},description="Potion: 5 minute buff. Brewed from Pyre Ash."})
recipe("EmberwardDraught",{skill="Alchemy",level=22,xp=70,costs={[B.ASH]=4,Herb=2},repeatable=true,station="Cauldron",category="Potions",
	collectionTier={[B.ASH]=1}})
do
	local CR = Data.Crafting
	if CR and CR.VIAL_POTIONS then
		local r = Data.Recipes.EmberwardDraught
		if CR.VIALS_IN_POTIONS then r.costs.GlassVial = (r.costs.GlassVial or 0) + 1 end
		table.insert(CR.VIAL_POTIONS, "EmberwardDraught")
		table.sort(CR.VIAL_POTIONS, function(a, b)
			local la, lb = Data.Recipes[a].level, Data.Recipes[b].level
			if la ~= lb then return la < lb end
			return a < b
		end)
	end
	Data.Items.EmberwardDraught.value = math.min(Data.Items.EmberwardDraught.value, valueOf(Data.Recipes.EmberwardDraught.costs))
end

-- Campfire-only dishes (B.FireRecipes, not Data.Recipes: the generic craft verb
-- cannot make them). Value never above the inputs.
B.FireRecipes, B.FireRecipeOrder = {}, {}
for _, d in ipairs({
	{id="HearthfireSkewer",name="Hearthfire Skewer",level=22,xp=70,costs={Glassfin=2,Sunwheat=2},rarity="Uncommon",color="E9A23B",
		buff={health=40,defense=15},duration=600},
	{id="BeaconwatchStew",name="Beaconwatch Stew",level=58,xp=200,costs={Lanternray=2,Moonbloom=2,Glowcap=1},rarity="Rare",color="C8553D",
		buff={health=80,strength=20,foragingFortune=20},duration=600},
}) do
	local parts = {}
	for stat, v in pairs(d.buff) do table.insert(parts, "+"..v.." "..((Data.Stats[stat] and Data.Stats[stat].name) or stat)) end
	table.sort(parts)
	item(d.id,{name=d.name,kind="consumable",category="buff",rarity=d.rarity,color=d.color,buff={stats=d.buff,duration=d.duration},
		value=math.max(1, math.floor(valueOf(d.costs) * 0.9)),requires={Cooking=d.level},
		description="Campfire dish: "..table.concat(parts, ", ").." for "..(d.duration // 60).." minutes."})
	local rec = {id=d.id,output=d.id,amount=1,skill="Cooking",level=d.level,xp=d.xp,costs=d.costs,fireOnly=true,category="Campfire"}
	B.FireRecipes[d.id] = rec
	table.insert(B.FireRecipeOrder, d.id)
end
-- A recipe the campfire can cook: Cooking's Hearth meals and feasts, or a
-- campfire dish. Returns the recipe table or nil.
function B.cookRecipe(id)
	if type(id) ~= "string" then return nil end
	local fire = B.FireRecipes[id]
	if fire then return fire end
	local r = Data.Recipes[id]
	if type(r) == "table" and r.skill == "Cooking" and r.station == "Hearth" then return r end
	return nil
end
-- Every campfire recipe, sorted by level then id (UI and tests).
function B.cookList()
	local out = {}
	for id in pairs(Data.Recipes) do if B.cookRecipe(id) then table.insert(out, B.cookRecipe(id)) end end
	for _, id in ipairs(B.FireRecipeOrder) do table.insert(out, B.FireRecipes[id]) end
	table.sort(out, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.id < b.id end)
	return out
end
-- Campfire burn chance (OSRS: open fires burn more than ranges): 35% at the
-- recipe level, falling to 0 thirty Cooking levels later; dishes made for the
-- campfire never burn.
function B.burnChance(cookLevel, rec)
	if type(rec) ~= "table" or rec.fireOnly then return 0 end
	local over = whole(cookLevel) - whole(rec.level)
	return math.clamp(B.BURN_BASE * (1 - over / B.BURN_FADE), 0, B.BURN_BASE)
end
function B.cookXp(rec) return math.floor(whole(rec and rec.xp) * B.FIRE_XP_MULT) end
-- "recipe:count" -> id, count (1..MAX_BATCH) or nil.
function B.parseBatch(text)
	if type(text) ~= "string" or #text > 64 then return nil end
	local id, n = string.match(text, "^(%w+):(%d+)$")
	n = tonumber(n)
	if not id or not B.cookRecipe(id) or not n or n < 1 then return nil end
	return id, math.min(n, B.MAX_BATCH)
end

------------------------------------------------------------------------------
-- Beacons: one pyre per region (world.server.lua builds them on the region's
-- Mote Shrine island, Data.Exploration.ShrineIsle). log = the lowest log tier
-- that can feed it (any higher tier also burns); buff = Beacon Warmth.
------------------------------------------------------------------------------
B.BeaconOrder = {"Hub","Meadow","Quarry","Windpine","Skyreach","Tidewater","Gloomhollow","Tempest","ShatteredCrown"}
B.Beacons = {
	Hub={name="Quayfire Beacon",region="Hub",level=1,log="Timber",buff={health=20},color="FFB347"},
	Meadow={name="Sunwheel Beacon",region="Meadow",level=10,log="Timber",buff={farmingFortune=15},color="F4D35E"},
	Quarry={name="Brassfall Beacon",region="Quarry",level=20,log="WindpineLog",buff={miningFortune=15},color="E9A23B"},
	Windpine={name="Canopy Beacon",region="Windpine",level=30,log="EmberoakLog",buff={foragingFortune=20},color="FF8C42"},
	Skyreach={name="Summit Beacon",region="Skyreach",level=40,log="EmberoakLog",buff={miningSpeed=30},color="FFC15E"},
	Tidewater={name="Shoalward Beacon",region="Tidewater",level=50,log="GlimmerbarkLog",buff={fishingFortune=20},color="7FD6E8"},
	Gloomhollow={name="Hollowlight Beacon",region="Gloomhollow",level=62,log="StarwoodLog",buff={defense=25},color="B59CFF"},
	Tempest={name="Stormcrown Beacon",region="Tempest",level=78,log="AetherheartLog",buff={strength=20,critDamage=10},color="9AD8FF"},
	ShatteredCrown={name="Crownfire Beacon",region="ShatteredCrown",level=90,log="ShatterbarkLog",buff={health=40,critDamage=15},color="D8B4FF"},
}
for i, id in ipairs(B.BeaconOrder) do
	local b = B.Beacons[id]
	b.id, b.index = id, i
	-- A region whose log tier does not exist falls back to the best log there is.
	if not B.LogById[b.log] then b.log = B.Logs[#B.Logs].id end
end
-- Logs that can feed a beacon: its own tier or better.
function B.feedsBeacon(beacon, logId)
	local need, log = B.LogById[beacon and beacon.log or ""], B.LogById[logId or ""]
	return need ~= nil and log ~= nil and log.tier >= need.tier
end
-- The log stack a beacon lighting spends: the lowest qualifying tier with a
-- full feed (B.BEACON_LOGS logs) that the lighter's Beaconry `level` can kindle
-- (QC H1; level omitted = any). Returns the log def or nil.
function B.beaconFuel(beacon, items, level)
	for _, log in ipairs(B.Logs) do
		if B.feedsBeacon(beacon, log.id) and (level == nil or whole(level) >= log.level)
			and whole((items or {})[log.id]) >= B.BEACON_LOGS then return log end
	end
	return nil
end
function B.beaconXp(log) return math.floor(whole(log and log.xp) * B.BEACON_LOGS * B.BEACON_XP_MULT) end
-- XP for lighting a beacon: always its own tier's feed (as the UI and the XP
-- calculator show), never the logs actually spent (QC H1).
function B.beaconXpFor(beacon) return B.beaconXp(B.LogById[beacon and beacon.log or ""]) end
-- QC H1: does this lighting pay XP? Counts it on the journal (c.xpDay) when it does.
function B.takeBeaconXp(c, day)
	day = whole(day)
	if type(c.xpDay) ~= "table" or c.xpDay.id ~= day then
		if type(c.xpDay) == "table" and whole(c.xpDay.id) > day then return false end -- a clock behind never rewinds it
		c.xpDay = {id = day, n = 0}
	end
	if c.xpDay.n >= B.BEACON_XP_PER_DAY then return false end
	c.xpDay.n += 1
	return true
end
function B.warmthSeconds(cape) return B.WARMTH_SECONDS * (if cape then B.CAPE_WARMTH_MULT else 1) end

------------------------------------------------------------------------------
-- Campfire sites. chain = the ground part the kindler stands on and its
-- ancestors, {{name=, bridge=bool}, ...} from the hit part upward. Fires burn
-- only on the open ground of a static isle (under Workspace.Islands) or on the
-- kindler's own home island; never on a path, bridge, rope deck, another
-- player's home, a lair, an arena or the Observatory.
------------------------------------------------------------------------------
local BRIDGE_WORDS = {"bridge","deck","plank","rope","ladder","stair","dock","pier","path"}
-- QC L2: never inside a station, stall or other built structure on an isle.
local STRUCTURE_WORDS = {"stall","station","counter","forge","hearth","cauldron","workbench","anvil","altar",
	"council","dais","vault","booth","kiosk","bench","tanning","furnace","chest","board","statue","fountain",
	-- §40 QC L1: the building kit's hosts ("Roofed house", "Roofed hall floor",
	-- "Hall wall") and walk-in halls; models also carry the Building attribute
	-- (chain node .building, set by the server's chainOf).
	"roofed","hall","house"}
B.STRUCTURE_WORDS = STRUCTURE_WORDS
function B.groundVerdict(chain, userId)
	if type(chain) ~= "table" or #chain == 0 then return false, "Stand on solid ground to kindle a fire." end
	local first = chain[1]
	local name = string.lower(tostring(first.name or ""))
	if first.bridge then return false, "Not on a path or bridge. Step onto open ground." end
	for _, w in ipairs(BRIDGE_WORDS) do
		if string.find(name, w, 1, true) then return false, "Not on a path or bridge. Step onto open ground." end
	end
	local onIsles = false
	for i, node in ipairs(chain) do
		local owner = string.match(tostring(node.name or ""), "^WayfarersRest_(%d+)$")
		if owner then
			if tonumber(owner) ~= tonumber(userId) then return false, "That is another wayfarer's island. Kindle on your own ground." end
			return true
		end
		if node.name == "Islands" then
			onIsles = true
			-- Below the isle model (chain[i - 1]) every node is a part or a built model.
			for j = 1, i - 2 do
				local lower = string.lower(tostring(chain[j].name or ""))
				if chain[j].building then return false, "Not inside a building. Step out onto open ground." end
				for _, w in ipairs(STRUCTURE_WORDS) do
					if string.find(lower, w, 1, true) then return false, "Not inside a station or stall. Step out onto open ground." end
				end
			end
			break
		end
	end
	if not onIsles then return false, "Fires can only be kindled on the open ground of the isles." end
	return true
end
-- Spacing: fires = list of {pos = Vector3-like}, beacons = list of positions,
-- spots = positions of prompts, spawn markers and townsfolk anchors (QC L2).
function B.spacingVerdict(pos, fires, beacons, spots)
	local function flat(a, b) local dx, dz = a.X - b.X, a.Z - b.Z; return math.sqrt(dx * dx + dz * dz), math.abs(a.Y - b.Y) end
	for _, f in ipairs(fires or {}) do
		local d, dy = flat(pos, f.pos)
		if d < B.FIRE_SPACING and dy < 6 then return false, "A fire is already burning here. Step aside." end
	end
	for _, b in ipairs(beacons or {}) do
		local d, dy = flat(pos, b)
		if d < B.BEACON_CLEARANCE and dy < 12 then return false, "Too close to the beacon pyre." end
	end
	for _, q in ipairs(spots or {}) do
		local d, dy = flat(pos, q)
		if d < B.SPOT_CLEARANCE and dy < 12 then return false, "Too close to a station, a townsfolk post or a creature den. Step into the open." end
	end
	return true
end

------------------------------------------------------------------------------
-- Profile p.beaconry = {kindled={[log]=n}, failed=n, beacons={[beacon]=n},
-- cooked=n, burnt=n, ash=n, week={id, lit, claimed}, weeks=n}. Quest flags
-- p.beaconKindled / p.beaconLit / p.beaconNetwork (top-level booleans, flag checks).
------------------------------------------------------------------------------
B.NETWORK_BEACONS = 5 -- distinct beacons lit for the beaconNetwork flag
function B.migrate(raw)
	local c = type(raw) == "table" and raw or {}
	local function counts(t, valid)
		local out = {}
		if type(t) == "table" then
			for id, n in pairs(t) do
				n = whole(n)
				if type(id) == "string" and valid[id] and n > 0 then out[id] = math.min(n, B.MAX_COUNT) end
			end
		end
		return out
	end
	local week = type(c.week) == "table" and c.week or {}
	return {
		kindled = counts(c.kindled, B.LogById), beacons = counts(c.beacons, B.Beacons),
		failed = math.clamp(whole(c.failed), 0, B.MAX_COUNT), cooked = math.clamp(whole(c.cooked), 0, B.MAX_COUNT),
		burnt = math.clamp(whole(c.burnt), 0, B.MAX_COUNT), ash = math.clamp(whole(c.ash), 0, B.MAX_COUNT),
		week = {id = math.max(0, whole(week.id)), lit = math.clamp(whole(week.lit), 0, B.MAX_COUNT), claimed = week.claimed == true},
		weeks = math.clamp(whole(c.weeks), 0, 10000),
		xpDay = if type(c.xpDay) == "table" then {id = whole(c.xpDay.id), n = math.clamp(whole(c.xpDay.n), 0, B.BEACON_XP_PER_DAY)} else nil,
	}
end
function B.distinctBeacons(c)
	local n = 0
	for id, v in pairs(type(c) == "table" and type(c.beacons) == "table" and c.beacons or {}) do
		if B.Beacons[id] and whole(v) > 0 then n += 1 end
	end
	return n
end
-- The journal's week entry for week `w`, rolled forward only (a server whose
-- clock is behind never rewinds it).
function B.rollWeek(c, w)
	if whole(w) > c.week.id then c.week = {id = whole(w), lit = 0, claimed = false} end
	return c.week
end
-- Claim check: (ok, reason). total = the community total for week w.
function B.canClaim(c, w, total)
	if type(c) ~= "table" or type(c.week) ~= "table" or c.week.id ~= whole(w) or c.week.lit < 1 then
		return false, "Light a beacon this week to join the watch."
	end
	if c.week.claimed then return false, "You already claimed this week's beacon reward." end
	if whole(total) < B.WEEK_GOAL then return false, "The isles have lit "..whole(total).."/"..B.WEEK_GOAL.." beacons this week." end
	return true
end

------------------------------------------------------------------------------
-- Balance model (verify-beaconry.luau; documented in §37). Supply chain:
-- chop the log (one node, max(respawn, 1.65) s like §22) then kindle it
-- (B.KINDLE_SECONDS per attempt at the success chance).
------------------------------------------------------------------------------
function B.kindleSecondsPerLog(level, log, strikerTier)
	local c = B.successChance(level, log, strikerTier)
	return if c > 0 then B.KINDLE_SECONDS / c else math.huge
end
local function woodTier(log)
	for _, t in ipairs(Data.ResourceTiers.Woodcutting) do if t.id == log.id then return t end end
	return nil
end
-- XP/h kindling banked logs (cadence-bound).
function B.bankedRate(level, log, strikerTier)
	return log.xp * 3600 / B.kindleSecondsPerLog(level, log, strikerTier)
end
-- XP/h chopping then kindling every log yourself.
function B.chainRate(level, log, strikerTier)
	local t = woodTier(log)
	local chop = math.max(t and t.respawn or 3, 1.65)
	return log.xp * 3600 / (chop + B.kindleSecondsPerLog(level, log, strikerTier))
end
-- Woodcutting XP/h on the same log (one node), for comparison.
function B.woodcuttingRate(log)
	local t = woodTier(log)
	return if t then t.xp * 3600 / math.max(t.respawn, 1.65) else 0
end

------------------------------------------------------------------------------
-- Unlock list for the Skills page (Hero › Skills › Beaconry): {level, text, item}.
------------------------------------------------------------------------------
function B.unlocks()
	local out = {}
	for _, log in ipairs(B.Logs) do
		table.insert(out, {level=log.level,text="Kindle "..log.name.." (+"..log.xp.." XP, burns "..log.seconds.."s)",item=log.id})
	end
	for _, id in ipairs(B.BeaconOrder) do
		local b = B.Beacons[id]
		table.insert(out, {level=b.level,text="Light the "..b.name.." ("..B.BEACON_LOGS.." "..((B.LogById[b.log] or {}).name or b.log).." or better)"})
	end
	for _, id in ipairs(B.StrikerOrder) do
		local s = B.Strikers[id]
		if s.level > 1 then table.insert(out, {level=s.level,text="Strike with a "..s.name.." (+"..(5 * (s.tier - 1)).."% kindle chance)",item=id}) end
	end
	table.insert(out, {level=99,text="Everflame mantle: kindles never fail, campfires burn 50% longer, warmth lasts twice as long"})
	return out
end

------------------------------------------------------------------------------
-- Held items (§26): the striker class (right hand) swings in the "kindle" gesture.
------------------------------------------------------------------------------
do
	local H = Data.Held
	if H then
		H.CLASSES.striker = {hand = "right", kind = "tool"}
		H.FITS.kindle = {striker = true}
		H.SHAPES.striker = {
			{n = "Grip", s = {0.22, 0.22, 0.7}, o = {0, 0, -0.05}, c = "leather", m = "Fabric"},
			{n = "Steel", s = {0.5, 0.16, 0.16}, o = {0, 0.05, -0.55}, c = "head", m = "metal"},
			{n = "Bow", s = {0.12, 0.42, 0.12}, o = {0.22, 0.2, -0.55}, c = "head", m = "metal"},
			{n = "Flint", s = {0.34, 0.34, 0.34}, o = {0, 0.24, -0.72}, c = "trim", m = "Slate", shape = "Ball"},
			{n = "Spark", s = {0.14, 0.14, 0.14}, o = {0, 0.34, -0.86}, c = "glow", m = "Neon", shape = "Ball"},
		}
	end
end

------------------------------------------------------------------------------
-- Commissions (§20): kind "kindle" (target = log id, one credit per campfire).
------------------------------------------------------------------------------
do
	local CL = Data.CommissionsLogs
	if CL and CL.Tasks then
		for _, t in ipairs({
			{id="KindleTimber",name="Hearth Kindling",target="Timber",amount=25,dust=14},
			{id="KindleWindpineLog",name="Windpine Blaze",target="WindpineLog",amount=20,dust=20},
			{id="KindleEmberoakLog",name="Ember Watch",target="EmberoakLog",amount=16,dust=26},
			{id="KindleGlimmerbarkLog",name="Glimmer Pyres",target="GlimmerbarkLog",amount=12,dust=32},
		}) do
			local log = B.LogById[t.target]
			if log then
				t.kind, t.skill, t.group = "kindle", "Beaconry", "Beaconry"
				t.levels = {Beaconry = log.level}
				t.xp = math.floor(log.xp * t.amount * 1.2)
				t.coins = 15 + log.level * 3
				table.insert(CL.Tasks, t)
				CL.TaskById[t.id] = t
			end
		end
	end
end

------------------------------------------------------------------------------
-- Quests (two side quests) and their quest-helper waypoints / check texts.
------------------------------------------------------------------------------
do
	local FLAG_TEXT = {beaconKindled = "Kindle your first campfire", beaconLit = "Light a regional beacon",
		beaconNetwork = "Light "..B.NETWORK_BEACONS.." different beacons"}
	B.FLAG_TEXT = FLAG_TEXT
	local describe = Data.describeCheck
	function Data.describeCheck(o, regional)
		if type(o) == "table" and o.kind == "flag" and FLAG_TEXT[o.flag] then return FLAG_TEXT[o.flag] end
		return describe(o, regional)
	end
	for _, q in ipairs({
		{id="KindlingLessons",title="Kindling Lessons",line="side",region="Hub",
			story="Old Hesketh Ashby, the Beaconkeeper, tends the Quayfire on Compass Quay. He will teach you to strike a spark, if you can keep a campfire going and bring him its ash.",
			requires={{kind="contracts",count=1}},
			objectives={{kind="flag",flag="beaconKindled"},{kind="level",skill="Beaconry",level=10},{kind="collect",item=B.ASH,count=10}},
			rewards={coins=400,points=1,xp={Beaconry=1200,Cooking=400}}},
		{id="TheLongWatch",title="The Long Watch",line="side",region="Hub",
			story="When the beacons of the isles burn together, no ship is lost in the cloud-sea. Light the Quayfire, then carry the flame across the regions.",
			requires={{kind="quest",quest="KindlingLessons"},{kind="level",skill="Beaconry",level=30}},
			objectives={{kind="flag",flag="beaconLit"},{kind="flag",flag="beaconNetwork"},{kind="collect",item=B.ASH,count=100}},
			rewards={coins=2500,points=2,xp={Beaconry=9000},perk={intelligence=5}}},
	}) do
		table.insert(Data.Quests, q)
		q.index = #Data.Quests
		Data.QuestById[q.id] = q
	end
	local SY = Data.Systems
	local HP = SY and SY.Helper
	if HP and HP.specsFor then
		local specsFor = HP.specsFor
		function HP.specsFor(o, ctx)
			if type(o) == "table" then
				if o.kind == "flag" and o.flag == "beaconKindled" then return {"gather:Timber"} end
				if o.kind == "flag" and (o.flag == "beaconLit" or o.flag == "beaconNetwork") then return {"anchor:Waypoint_Beacon_Hub", "region:Hub"} end
				if o.kind == "level" and o.skill == "Beaconry" then return {"anchor:Waypoint_Beacon_Hub", "gather:Timber"} end
				if (o.kind == "collect" or o.kind == "have" or o.kind == "collectionTier") and o.item == B.ASH then return {"gather:Timber"} end
			end
			return specsFor(o, ctx)
		end
	end
	-- XP calculator (§33): campfire logs and beacon feeds train Beaconry.
	local CA = SY and SY.Calc
	if CA and CA.actions then
		local actions = CA.actions
		function CA.actions(skill)
			if skill ~= "Beaconry" then return actions(skill) end
			local out = {}
			for _, log in ipairs(B.Logs) do table.insert(out, {id = log.id, name = "Kindle "..log.name, level = log.level, xp = log.xp, kind = "kindle"}) end
			for _, id in ipairs(B.BeaconOrder) do
				local b = B.Beacons[id]
				table.insert(out, {id = "Beacon"..id, name = b.name, level = b.level, xp = B.beaconXp(B.LogById[b.log]), kind = "beacon"})
			end
			table.sort(out, function(a, c)
				if a.level ~= c.level then return a.level < c.level end
				if a.xp ~= c.xp then return a.xp < c.xp end
				return a.id < c.id
			end)
			return out
		end
	end
end

------------------------------------------------------------------------------
-- The Beaconkeeper (Compass Quay), named in Kindling Lessons: a regional folk
-- entry, so World Art places Anchor_NPC_Beaconkeeper on the hub; the Beaconry
-- section of world.server.lua then moves it beside the Quayfire pyre.
------------------------------------------------------------------------------
do
	local T, RA = Data.Townsfolk, Data.RegionArt
	if T and RA and RA.Folk and T.NPCs then
		B.KEEPER = "Beaconkeeper"
		local keeper = {role=B.KEEPER,region="Hub",name="Old Hesketh Ashby",title="Beaconkeeper",portrait="🔥",kind="beaconry",
			look={skin="C68642",shirt="6B3A22",pants="3A2E24",shoes="231A14",accent="F26B38",hair="D8D2C8",hat="cap",held="lantern",apron="4A3426",beard=true},
			greet="Every beacon on the isles answers the Quayfire, and I've kept it burning longer than you've been walking. Strike a spark, wayfarer, and keep it fed."}
		table.insert(RA.Folk, keeper)
		RA.FolkByRole[keeper.role] = keeper
		if T.AtlasStations then T.AtlasStations.Beaconry = "Workshop · Beaconry" end -- ui.client.lua stationTabs.Beaconry
		local names = {}
		for _, id in ipairs(B.BeaconOrder) do table.insert(names, B.Beacons[id].name) end
		T.NPCs[keeper.role] = {name=keeper.name,title=keeper.title,region="Hub",portrait=keeper.portrait,look=keeper.look,start="hello",anchorOnly=true,folk="beaconry",
			nodes={
				hello={text=keeper.greet,options={
					{label="Teach me to kindle",atlas="Beaconry"},
					{label="Show me the Quayfire",waypoint={"anchor:Waypoint_Beacon_Hub","region:Hub"}},
					{label="Tell me about the beacon network",to="network"},
					{label="Farewell",close=true}}},
				network={text="One beacon stands on every region's shrine isle: "..table.concat(names, ", ")
					..". Feed one "..B.BEACON_LOGS.." logs of its wood or better and it blazes for "..(B.BEACON_SECONDS // 60).." minutes. Everyone near it shares its warmth, "
					.."and every lighting counts toward the week's watch: when the isles reach "..B.WEEK_GOAL..", each keeper who lit one may claim a reward in Workshop › Beaconry.",options={
					{label="Show me the Quayfire",waypoint={"anchor:Waypoint_Beacon_Hub","region:Hub"}},
					{label="Open Workshop › Beaconry",atlas="Beaconry"},
					{label="Back",to="hello"},
					{label="Farewell",close=true}}},
			}}
		table.insert(T.RegionFolkOrder, keeper.role)
	end
end

------------------------------------------------------------------------------
-- Isle Renown (§31): beacons lit (15 per distinct beacon) and community weeks
-- claimed (10 each, at most 52 counted). Bounded: 9 x 15 + 52 x 10 = 655.
------------------------------------------------------------------------------
do
	local RN = Data.Renown
	if RN and RN.breakdown then
		B.RENOWN_BEACON, B.RENOWN_WEEK, B.RENOWN_WEEKS_CAP = 15, 10, 52
		local src = {id="beacons",name="Beacon watch",hint="15 XP per regional beacon you have lit; 10 XP per weekly beacon goal you helped reach (52 at most)."}
		table.insert(RN.Sources, src)
		src.index = #RN.Sources
		RN.SourceById[src.id] = src
		local breakdown = RN.breakdown
		function RN.breakdown(p, P, extra)
			local out = breakdown(p, P, extra)
			local c = type(p) == "table" and type(p.beaconry) == "table" and p.beaconry or {}
			local beacons = B.distinctBeacons(c)
			local weeks = math.min(math.max(0, whole(c.weeks)), B.RENOWN_WEEKS_CAP)
			local xp = beacons * B.RENOWN_BEACON + weeks * B.RENOWN_WEEK
			out.sources.beacons = out.sources.beacons or {xp = 0, count = 0}
			out.sources.beacons.xp += xp
			out.sources.beacons.count += beacons + weeks
			out.total += xp
			return out
		end
	end
end
end
-- <<< END Beaconry <<<
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- >>> BEGIN Isle Council (Isle Council team; append-only section, §36) >>>
-- An elected council in the spirit of SkyBlock's mayors, on the Skyward
-- Calendar (Data.calendarAt): one TERM = one isle year (~5.08 real days).
-- The ballot for the term of year Y+1 opens on day C.OPEN_DAY of year Y and
-- closes at the end of year Y (~2.5 real days of voting); the result is sealed
-- C.GRACE seconds later. Every election seats C.SLATE candidates drawn
-- deterministically from C.Candidates (same slate on every server and client),
-- each running on 2-3 perks drawn from their own four. The winner's perks rule
-- the next term on every server; the runner-up becomes Minister and grants one
-- perk (the first of theirs that does not overlap the winner's).
-- Pure data + pure rules: server.server.lua ("Isle Council" block) owns the
-- ballots (sharded MemoryStore items, idempotent per-account sequence numbers),
-- the sealed result and every perk hook. docs/DEPTH-CONTRACT.md §36.
------------------------------------------------------------------------------
do
local C = {}
local Cal = Data.Calendar
local function tab(v) return if type(v) == "table" then v else {} end
local function whole(v) return if type(v) == "number" and v == v and v >= 0 and v < math.huge then math.floor(v) else 0 end
C.whole = whole
C.NAME = "Isle Council"
C.OPEN_DAY = 25          -- day of the isle year the ballot opens (Emberfall 1); closes at year's end
C.SLATE = 5              -- candidates per election
C.SHARDS = 512           -- MemoryStore shard items per election (UserId % SHARDS); see §36 capacity math
C.SHARD_CAP = 1500       -- ballots per shard item (~29 KB JSON worst case, under MemoryStore's 32 KB item limit; 768k voters)
C.GROUPS = 16            -- count-mirror items per election (tally reads fetch these only, never ballots)
C.MAX_SEQ = 4095         -- highest ballot sequence number (packed with the slot: seq * 8 + slot)
C.GRACE = 120            -- seconds after the close before a server seals; ballots cast before the close are written until GRACE / 2
C.TTL_PAD = 7 * 86400    -- live ballot items expire this long after the seal time
C.FLUSH = 10             -- seconds between a server's ballot flushes (one UpdateAsync per pending shard)
C.MIRROR = 30            -- seconds between a server's count-mirror writes (one UpdateAsync per pending group)
C.BACKOFF_BASE = 2       -- seconds: first retry delay of a failing key (doubles per failure, jittered 50-100%)
C.BACKOFF_MAX = 120      -- seconds: longest retry delay of a failing key
C.READ = 90              -- seconds a server's cached tally stays fresh
C.VIEW_COOLDOWN = 60     -- seconds between one account's forced tally refreshes (councilView)
C.VIEW_FLOOR = 30        -- seconds between any two forced tally refreshes on one server
C.TICK = 3               -- council heartbeat (seconds)
C.SEAL_RETRY = 30        -- seconds between sealing attempts after a failure
C.SEAL_LEASE = 90        -- seconds a server's claim to seal an election lasts (one server reads the shards)
C.VOTE_COOLDOWN = 4      -- seconds between one account's votes
C.MAX_CHANGES = 12       -- ballots per account per election (the first vote and 11 changes)
C.MIN_RENOWN = 5         -- Isle Renown level needed to vote (lead decision: deters throwaway alts)
C.HISTORY = 8            -- past terms kept in the shared history key
C.PREFIX = "council_v1_"   -- DataStore keys: result, history (and legacy v1 ballot shards, swept after the seal)
C.MAP_PREFIX = "council_v2_" -- MemoryStore hash map per election
C.HISTORY_KEY = C.PREFIX .. "history"
C.CLERK = "CouncilClerk"
C.COLOR = "E9C46A"

-- Perks. kind: xp (category of Data.Skills, mult), auctionFee (cut of the listing
-- fee), workers (pct: extra worker work per second, like fuel), magicFind (region,
-- mf: Magic Find against that region's creatures; rare drops under 5% only),
-- dungeonRolls (n extra Observatory chest rolls), factionRep (pct), stats
-- (p.perkStats.council; never Health or Defense, so Data.PerkBudget is untouched).
-- No perk creates coins: fees only fall, and every yield perk scales an
-- existing, already-balanced source.
C.Perks = {
	BountifulToil={name="Bountiful Toil",kind="xp",category="gathering",mult=0.10,color="9BD77E",text="+10% XP in gathering skills."},
	WarbandWrit={name="Warband Writ",kind="xp",category="combat",mult=0.10,color="C8553D",text="+10% XP in combat skills."},
	GuildCharter={name="Guild Charter",kind="xp",category="production",mult=0.10,color="D9822B",text="+10% XP in production skills."},
	HearthAndHound={name="Hearth & Hound",kind="xp",category="support",mult=0.15,color="E07A5F",text="+15% XP in support skills."},
	OpenLedger={name="Open Ledger",kind="auctionFee",cut=0.5,color="F7C548",text="Auction House listing fees halved."},
	TirelessHands={name="Tireless Hands",kind="workers",pct=10,color="B5651D",text="Workers work 10% faster."},
	DeepseamSurvey={name="Deepseam Survey",kind="stats",stats={miningFortune=15},color="8C7A6B",text="+15 Mining Fortune."},
	Tidecaller={name="Tidecaller's Hymn",kind="stats",stats={seaCreatureChance=3},color="3F7CAC",text="+3 Sea Creature Chance: more sea creatures surface."},
	GloomGleaning={name="Gloom Gleaning",kind="magicFind",region="Gloomhollow",mf=20,color="7FD3C4",text="+20 Magic Find against Gloomhollow creatures."},
	SkyreachSpoils={name="Skyreach Spoils",kind="magicFind",region="Skyreach",mf=20,color="7B8CDE",text="+20 Magic Find against Skyreach creatures."},
	WildwoodBounty={name="Wildwood Bounty",kind="magicFind",region="Windpine",mf=20,color="5E8C4A",text="+20 Magic Find against Windpine creatures."},
	TideTrove={name="Tide Trove",kind="magicFind",region="Tidewater",mf=20,color="4FB0C6",text="+20 Magic Find against Tidewater creatures."},
	TempestTithe={name="Tempest Tithe",kind="magicFind",region="Tempest",mf=20,color="BFD7FF",text="+20 Magic Find against Tempest Spire creatures."},
	StarlitCoffers={name="Starlit Coffers",kind="dungeonRolls",n=1,color="BFE3FF",text="+1 roll of every Observatory clear chest."},
	BannerSworn={name="Banner-Sworn",kind="factionRep",pct=0.20,color="D4A84B",text="+20% faction reputation from board tasks."},
}
-- Hard caps on the summed effect of every active perk (winner + minister).
C.CAPS = {xp=0.15, auctionFee=0.5, workers=15, magicFind=25, dungeonRolls=1, factionRep=0.25,
	stats={miningFortune=20, seaCreatureChance=4}}
for id, perk in pairs(C.Perks) do perk.id = id end

-- The candidate pool (all original Aether Isles councillors). perks: four ids.
C.Candidates = {
	{id="Brannoc",name="Brannoc Ashvale",title="Warden of the Ramparts",color="C8553D",portrait="🛡",
		pitch="Steel for the gates, spoils for the brave.",perks={"WarbandWrit","GloomGleaning","StarlitCoffers","BannerSworn"}},
	{id="Ysmay",name="Ysmay Corrowind",title="Factor of the Exchange",color="F7C548",portrait="⚖",
		pitch="A lighter ledger for every honest trader.",perks={"OpenLedger","TirelessHands","GuildCharter","DeepseamSurvey"}},
	{id="Thessaly",name="Thessaly Brightfurrow",title="Voice of the Fields",color="9BD77E",portrait="🌾",
		pitch="Every furrow and every hand rewarded.",perks={"BountifulToil","TirelessHands","HearthAndHound","WildwoodBounty"}},
	{id="Orrin",name="Captain Orrin Saltmere",title="Harbour Tribune",color="3F7CAC",portrait="⚓",
		pitch="Calm skies over the shoals, full nets below.",perks={"Tidecaller","TideTrove","BountifulToil","OpenLedger"}},
	{id="Velka",name="Velka Starhollow",title="Keeper of the Observatory",color="BFE3FF",portrait="🔭",
		pitch="The stars reward those who climb toward them.",perks={"StarlitCoffers","WarbandWrit","SkyreachSpoils","GuildCharter"}},
	{id="Dunstan",name="Dunstan Coggery",title="Master of the Forges",color="B5651D",portrait="⚒",
		pitch="Hot forges, deep seams, busy hands.",perks={"GuildCharter","DeepseamSurvey","TirelessHands","OpenLedger"}},
	{id="Isolde",name="Isolde Venbrook",title="Envoy of the Banners",color="D4A84B",portrait="🏳",
		pitch="Swear to a banner and the isles swear back.",perks={"BannerSworn","HearthAndHound","WildwoodBounty","Tidecaller"}},
	{id="Fennick",name="Fennick Lowlantern",title="Lamplighter of Gloomhollow",color="7FD3C4",portrait="🏮",
		pitch="Light in the caverns, treasure in the dark.",perks={"GloomGleaning","WarbandWrit","HearthAndHound","StarlitCoffers"}},
	{id="Aurelie",name="Aurelie Windspire",title="Stormcaller of the Spire",color="BFD7FF",portrait="🌩",
		pitch="Ride the storm and keep what it drops.",perks={"TempestTithe","SkyreachSpoils","WarbandWrit","Tidecaller"}},
	{id="Pim",name="Pim Quickbarrow",title="Friend of the Hearth",color="E07A5F",portrait="🏡",
		pitch="Pets fed, homes built, neighbours sworn.",perks={"HearthAndHound","BountifulToil","BannerSworn","OpenLedger"}},
}
C.CandidateById = {}
for i, c in ipairs(C.Candidates) do c.index = i; C.CandidateById[c.id] = c end

-- Election calendar ---------------------------------------------------------------
-- The election in progress (or upcoming) at t: e = the term year it elects.
-- {e, opens, closes, open, sealAt, termYear (the year now ruled), termStarts, termEnds}
function C.election(t)
	local cal = Data.calendarAt(t)
	local opens = cal.yearStart + (C.OPEN_DAY - 1) * Cal.dayLength
	return {e=cal.year + 1, opens=opens, closes=cal.yearEnds, open=t >= opens and t < cal.yearEnds, sealAt=cal.yearEnds + C.GRACE,
		termYear=cal.year, termStarts=cal.yearStart, termEnds=cal.yearEnds}
end
-- Wall-clock window of term year `y` (and of its election, held during y-1).
function C.termWindow(y)
	local starts = Cal.epoch + (whole(y) - 1) * Cal.yearLength
	return {starts=starts, ends=starts + Cal.yearLength, opens=starts - Cal.yearLength + (C.OPEN_DAY - 1) * Cal.dayLength, sealAt=starts + C.GRACE}
end

-- Deterministic slate ------------------------------------------------------------
-- Park-Miller generator (exact in doubles), seeded by the election year.
local function generator(seed)
	local state = (whole(seed) * 7919 + 104729) % 2147483647
	if state == 0 then state = 1 end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
local slates = {}
-- {{id, perks = {perkId...}}} for election e (C.SLATE entries, pool order shuffled).
function C.slate(e)
	e = whole(e)
	if slates[e] then return slates[e] end
	local rng = generator(e)
	local pool = {}
	for i = 1, #C.Candidates do pool[i] = i end
	local out = {}
	for i = 1, math.min(C.SLATE, #pool) do
		local j = i + math.floor(rng() * (#pool - i + 1))
		pool[i], pool[j] = pool[j], pool[i]
		local cand = C.Candidates[pool[i]]
		local count = if rng() < 0.5 then 2 else 3
		local idx = {1, 2, 3, 4}
		for k = 1, count do
			local m = k + math.floor(rng() * (#idx - k + 1))
			idx[k], idx[m] = idx[m], idx[k]
		end
		local chosen = {}
		for k = 1, count do chosen[k] = idx[k] end
		table.sort(chosen)
		local perks = {}
		for _, k in ipairs(chosen) do table.insert(perks, cand.perks[k]) end
		table.insert(out, {id=cand.id, perks=perks})
	end
	slates[e] = out
	return out
end
-- Slate position of candidate `id` in election e (nil when not running).
function C.slotOf(e, id)
	for i, s in ipairs(C.slate(e)) do if s.id == id then return i end end
	return nil
end

-- Ballot storage (QC H1) ----------------------------------------------------------
-- Live ballots sit in a MemoryStore hash map per election (C.mapName(e)), split
-- over C.SHARDS shard items (UserId % C.SHARDS). One shard item holds the
-- counts and a compact, bounded ballot map {[UserId] = seq * 8 + slot}, so one
-- atomic UpdateAsync both records a ballot and moves the counts (idempotent by
-- sequence number). Tally reads never download ballots: after each committed
-- shard write the writing server mirrors that shard's counts, tagged with the
-- shard's write version, into one of C.GROUPS small count items (C.mirror keeps
-- the highest version per shard, so late or repeated mirror writes are
-- harmless). Sealing reads the shard items once (authoritative) and persists the
-- result to DataStore. Items expire C.TTL_PAD after the seal time (C.ttl).
function C.shardOf(userId) return (whole(tonumber(userId)) % C.SHARDS) + 1 end
function C.mapName(e) return C.MAP_PREFIX .. whole(e) end
function C.shardKey(shard) return "s" .. whole(shard) end
function C.groupOf(shard) return ((whole(shard) - 1) % C.GROUPS) + 1 end
function C.groupKey(group) return "n" .. whole(group) end
C.SEAL_KEY = "seal"
C.LEGACY_SHARDS = 8      -- v1 stored ballots in 8 DataStore keys per election
-- Legacy (v1) DataStore shard keys, swept once a term's result is in history (QC L5).
function C.legacyKey(e, shard) return C.PREFIX .. whole(e) .. "_s" .. whole(shard) end
function C.resultKey(e) return C.PREFIX .. whole(e) .. "_result" end
-- Expiration (seconds from `now`) for election e's items: past the seal plus a pad, within MemoryStore's 45-day limit.
function C.ttl(e, now)
	return math.clamp(C.termWindow(e).sealAt + C.TTL_PAD - whole(now), 60, 3888000)
end
-- The last moment a ballot cast before the close may still be written (QC M1).
function C.writeDeadline(e) return C.termWindow(e).starts + C.GRACE / 2 end
function C.pack(slot, seq) return whole(seq) * 8 + whole(slot) end
function C.unpack(v)
	v = whole(v)
	return v % 8, v // 8
end
local function emptyCounts() local n = {} for i = 1, C.SLATE do n[i] = 0 end return n end
C.emptyCounts = emptyCounts
function C.newBook(e) return {e=whole(e), v={}, n=emptyCounts(), size=0, ver=0} end
-- A sanitised copy-in-place of a stored shard (a fresh one when it is missing,
-- malformed or for another election).
function C.cleanBook(old, e)
	if type(old) ~= "table" or old.e ~= e or type(old.v) ~= "table" then return C.newBook(e) end
	if type(old.n) ~= "table" then old.n = emptyCounts() end
	for i = 1, C.SLATE do old.n[i] = whole(old.n[i]) end
	old.size, old.ver = whole(old.size), whole(old.ver)
	return old
end
-- Counts recomputed from the ballots themselves (tests; repair).
function C.recount(book)
	local n, size = emptyCounts(), 0
	for _, b in pairs(tab(tab(book).v)) do
		local c = C.unpack(b)
		if c >= 1 and c <= C.SLATE then n[c] += 1 end
		size += 1
	end
	return n, size
end
-- Applies queued ballots {u = "<UserId>", c = slot, s = seq, t = castAt} to a
-- stored shard (the UpdateAsync transform). One ballot per account: a ballot
-- replaces the account's earlier one only when its sequence number is higher,
-- so retries, replays and out-of-order flushes change nothing. A ballot counts
-- only if it was cast (server-stamped t) before the close and is written before
-- C.writeDeadline (QC M1). Returns book, results {[u] = "ok"|"stale"|"full"|
-- "closed"|"bad"}, changed, stored {[u] = {c, s}} (the ballot already stored
-- for every "stale" verdict, QC M3).
function C.applyBallots(old, ops, e, closes, now)
	local book = C.cleanBook(old, e)
	local results, stored, changed = {}, {}, false
	for _, op in ipairs(tab(ops)) do
		local u = type(op) == "table" and op.u
		local c, s = type(op) == "table" and whole(op.c) or 0, type(op) == "table" and whole(op.s) or 0
		local castAt = type(op) == "table" and tonumber(op.t) or nil
		if type(u) ~= "string" or #u == 0 or #u > 20 or not string.match(u, "^%d+$") or c < 1 or c > C.SLATE or s < 1 or s > C.MAX_SEQ then
			if type(u) == "string" then results[u] = "bad" end
		elseif castAt == nil or castAt >= closes or now >= closes + C.GRACE / 2 then
			results[u] = "closed"
		else
			local cur = book.v[u]
			local curC, curSeq = C.unpack(cur)
			if cur ~= nil and curSeq >= s then
				results[u] = "stale"
				stored[u] = {c=curC, s=curSeq}
			elseif cur == nil and book.size >= C.SHARD_CAP then
				results[u] = "full"
			else
				if cur ~= nil and curC >= 1 and curC <= C.SLATE then book.n[curC] = math.max(0, book.n[curC] - 1) end
				if cur == nil then book.size += 1 end
				book.n[c] += 1
				book.v[u] = C.pack(c, s)
				results[u] = "ok"
				changed = true
			end
		end
	end
	if changed then book.ver += 1 end
	return book, results, changed, stored
end
-- Count mirror: a group item {[tostring(shard)] = {ver, n1..nSLATE}}. Merges
-- shard counts carrying their write version; returns the item and whether it
-- changed (an older or equal version never overwrites a newer one).
function C.mirror(old, entries)
	local item = if type(old) == "table" then old else {}
	local changed = false
	for shard, entry in pairs(tab(entries)) do
		local k = tostring(shard)
		local cur = item[k]
		local curVer = type(cur) == "table" and whole(cur[1]) or -1
		if whole(entry.ver) > curVer then
			local row = {whole(entry.ver)}
			for i = 1, C.SLATE do row[i + 1] = whole(tab(entry.n)[i]) end
			item[k] = row
			changed = true
		end
	end
	return item, changed
end
-- Per-shard counts {[shard] = {n...}} from mirror items {[group] = item}.
function C.fromMirror(groups)
	local shards = {}
	for _, item in pairs(tab(groups)) do
		for k, row in pairs(tab(item)) do
			local shard = whole(tonumber(k))
			if shard >= 1 and shard <= C.SHARDS and type(row) == "table" then
				local n = {}
				for i = 1, C.SLATE do n[i] = whole(row[i + 1]) end
				shards[shard] = {ver=whole(row[1]), n=n}
			end
		end
	end
	return shards
end
-- Jittered exponential backoff (seconds) after `fails` consecutive failures on one key; r in [0, 1).
function C.backoff(fails, r)
	local span = math.min(C.BACKOFF_MAX, C.BACKOFF_BASE * 2 ^ math.max(0, whole(fails) - 1))
	return span * (0.5 + 0.5 * math.clamp(tonumber(r) or 0, 0, 1))
end
-- Summed counts across shard count lists {[shard] = {n...}}.
function C.sum(shards)
	local n, total = emptyCounts(), 0
	for _, counts in pairs(tab(shards)) do
		for i = 1, C.SLATE do
			local v = whole(tab(counts)[i])
			n[i] += v
			total += v
		end
	end
	return n, total
end
-- Vote shares (0..1) per slate slot.
function C.shares(counts, total)
	local out = {}
	for i = 1, C.SLATE do out[i] = if total > 0 then whole(tab(counts)[i]) / total else 0 end
	return out
end

-- Results, terms and perks --------------------------------------------------------
-- Effect slot: two perks with the same slot never stack (the minister skips them).
function C.perkSlot(perk)
	if perk.kind == "xp" then return "xp:" .. perk.category end
	if perk.kind == "magicFind" then return "mf:" .. perk.region end
	if perk.kind == "stats" then
		local keys = {}
		for k in pairs(perk.stats) do table.insert(keys, k) end
		table.sort(keys)
		return "stats:" .. table.concat(keys, ",")
	end
	return perk.kind
end
-- The minister's perk: the first of the runner-up's perks whose slot the winner lacks.
function C.ministerPerk(winnerPerks, runnerPerks)
	local used = {}
	for _, id in ipairs(tab(winnerPerks)) do local p = C.Perks[id]; if p then used[C.perkSlot(p)] = true end end
	for _, id in ipairs(tab(runnerPerks)) do
		local p = C.Perks[id]
		if p and not used[C.perkSlot(p)] then return id end
	end
	return nil
end
-- Seals election e from its summed counts: most votes wins; ties go to the
-- earlier slate position (the slate order is itself the seeded draw).
-- {e, winner = id, minister = id, ministerPerk, counts, total}
function C.decide(e, counts)
	local slate = C.slate(e)
	local order = {}
	for i = 1, #slate do order[i] = i end
	counts = tab(counts)
	table.sort(order, function(a, b)
		local ca, cb = whole(counts[a]), whole(counts[b])
		if ca ~= cb then return ca > cb end
		return a < b
	end)
	local n, total = {}, 0
	for i = 1, C.SLATE do n[i] = whole(counts[i]); total += n[i] end
	local w, r = slate[order[1]], slate[order[2]]
	return {e=whole(e), winner=w.id, minister=r and r.id or nil, ministerPerk=r and C.ministerPerk(w.perks, r.perks) or nil, counts=n, total=total}
end
-- A stored result, validated against the deterministic slate (nil when invalid).
function C.cleanResult(r, e)
	if type(r) ~= "table" or whole(r.e) ~= e then return nil end
	local slate = C.slate(e)
	local w = C.slotOf(e, r.winner)
	if not w then return nil end
	local m = if r.minister ~= nil then C.slotOf(e, r.minister) else nil
	local mp = if m and type(r.ministerPerk) == "string" and table.find(slate[m].perks, r.ministerPerk) then r.ministerPerk else nil
	local n, total = {}, 0
	for i = 1, C.SLATE do n[i] = whole(tab(r.counts)[i]); total += n[i] end
	return {e=e, winner=r.winner, minister=if m then r.minister else nil, ministerPerk=mp, counts=n, total=total}
end
-- Active perk ids of a sealed result: the winner's perks, then the minister's one.
function C.termPerks(result)
	if type(result) ~= "table" then return {} end
	local slot = C.slotOf(result.e, result.winner)
	if not slot then return {} end
	local out = table.clone(C.slate(result.e)[slot].perks)
	if result.ministerPerk and C.Perks[result.ministerPerk] and not table.find(out, result.ministerPerk) then table.insert(out, result.ministerPerk) end
	return out
end
-- Summed, capped effects of a perk list.
function C.effects(perkIds)
	local fx = {xp={}, auctionFee=0, workers=0, magicFind={}, dungeonRolls=0, factionRep=0, stats={}}
	for _, id in ipairs(tab(perkIds)) do
		local p = C.Perks[id]
		if p then
			if p.kind == "xp" then fx.xp[p.category] = math.min(C.CAPS.xp, (fx.xp[p.category] or 0) + p.mult)
			elseif p.kind == "auctionFee" then fx.auctionFee = math.min(C.CAPS.auctionFee, fx.auctionFee + p.cut)
			elseif p.kind == "workers" then fx.workers = math.min(C.CAPS.workers, fx.workers + p.pct)
			elseif p.kind == "magicFind" then fx.magicFind[p.region] = math.min(C.CAPS.magicFind, (fx.magicFind[p.region] or 0) + p.mf)
			elseif p.kind == "dungeonRolls" then fx.dungeonRolls = math.min(C.CAPS.dungeonRolls, fx.dungeonRolls + p.n)
			elseif p.kind == "factionRep" then fx.factionRep = math.min(C.CAPS.factionRep, fx.factionRep + p.pct)
			elseif p.kind == "stats" then
				for stat, v in pairs(p.stats) do
					local cap = C.CAPS.stats[stat]
					if cap and stat ~= "health" and stat ~= "defense" then fx.stats[stat] = math.min(cap, (fx.stats[stat] or 0) + v) end
				end
			end
		end
	end
	return fx
end
-- Hook helpers (fx = C.effects(...) or nil when no term is known: no effect).
function C.xpMult(fx, skill)
	local def = type(skill) == "string" and Data.Skills[skill]
	if type(fx) ~= "table" or not def then return 1 end
	return 1 + math.clamp(tonumber(tab(fx.xp)[def.category]) or 0, 0, C.CAPS.xp)
end
function C.auctionFee(fx, price)
	local base = Data.Economy.auctionFee(price)
	local cut = type(fx) == "table" and math.clamp(tonumber(fx.auctionFee) or 0, 0, C.CAPS.auctionFee) or 0
	return math.max(1, math.ceil(base * (1 - cut)))
end
function C.magicFind(fx, monster)
	if type(fx) ~= "table" or type(monster) ~= "table" or type(monster.region) ~= "string" then return 0 end
	return math.clamp(tonumber(tab(fx.magicFind)[monster.region]) or 0, 0, C.CAPS.magicFind)
end
-- Extra worker work units (Data.Workers work: 100 per second) for `seconds` of perk time.
function C.workerWork(fx, seconds)
	if type(fx) ~= "table" then return 0 end
	return math.floor(math.max(0, tonumber(seconds) or 0) * math.clamp(tonumber(fx.workers) or 0, 0, C.CAPS.workers))
end
function C.dungeonRolls(fx)
	return if type(fx) == "table" then math.clamp(whole(fx.dungeonRolls), 0, C.CAPS.dungeonRolls) else 0
end
function C.factionRep(fx, rep)
	rep = whole(rep)
	if type(fx) ~= "table" then return rep end
	return math.floor(rep * (1 + math.clamp(tonumber(fx.factionRep) or 0, 0, C.CAPS.factionRep)))
end
function C.stats(fx)
	local out = {}
	for stat, v in pairs(tab(type(fx) == "table" and fx.stats)) do
		local cap = C.CAPS.stats[stat]
		if cap and stat ~= "health" and stat ~= "defense" and tonumber(v) and v > 0 then out[stat] = math.min(cap, v) end
	end
	return out
end
-- Shared history list (newest first, <= C.HISTORY, one entry per term).
function C.mergeHistory(old, result)
	local list = {}
	for _, r in ipairs(tab(old)) do
		local clean = type(r) == "table" and C.cleanResult(r, whole(r.e))
		if clean and #list < C.HISTORY * 2 then table.insert(list, clean) end
	end
	local added = false
	if type(result) == "table" then
		local found = false
		for _, r in ipairs(list) do if r.e == result.e then found = true end end
		if not found then table.insert(list, result); added = true end
	end
	table.sort(list, function(a, b) return a.e > b.e end)
	while #list > C.HISTORY do table.remove(list) end
	return list, added
end

-- Text ---------------------------------------------------------------------------
function C.perkText(id)
	local p = C.Perks[id]
	return if p then p.name .. ": " .. p.text else tostring(id)
end
function C.candidateName(id)
	local c = C.CandidateById[id]
	return if c then c.name else tostring(id)
end
function C.span(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 86400 then return (seconds // 86400) .. "d " .. ((seconds % 86400) // 3600) .. "h" end
	if seconds >= 3600 then return (seconds // 3600) .. "h " .. ((seconds % 3600) // 60) .. "m" end
	return math.max(1, math.ceil(seconds / 60)) .. "m"
end
Data.Council = C

-- §31 announcements: election open, ballot closed, new term.
local F = Data.Features
if F and F.announceText then
	local announceText = F.announceText
	function F.announceText(e)
		if type(e) == "table" and e.kind == "council" then
			local y = whole(e.e)
			if e.phase == "open" then
				return {head="COUNCIL ELECTION OPEN", body="Year " .. y .. " ballot  ·  " .. C.SLATE .. " candidates  ·  vote in Journal › Council", color=C.COLOR}
			elseif e.phase == "closed" then
				return {head="BALLOT CLOSED", body="Year " .. y .. " votes are being counted", color=C.COLOR}
			end
			local m = if type(e.minister) == "string" then "  ·  Minister " .. C.candidateName(e.minister) else ""
			return {head="NEW COUNCIL TERM", body=C.candidateName(e.winner) .. " leads Year " .. y .. m, color=C.COLOR}
		end
		return announceText(e)
	end
	F.ANNOUNCE_PRIORITY.council = true
end

-- The Council Clerk (Compass Quay): a regional folk entry, so World Art places
-- Anchor_NPC_CouncilClerk on the hub; the Council Hall section of
-- world.server.lua then moves that anchor to the hall's steps.
local T = Data.Townsfolk
local RA = Data.RegionArt
if T and RA then
	local clerk = {role=C.CLERK,region="Hub",name="Wendeline Quillmarsh",title="Clerk of the Isle Council",portrait="📜",kind="council",
		look={skin="D9A273",shirt="3B2F5C",pants="2A2438",shoes="1E1A26",accent="E9C46A",hair="5A3A22",hat="tophat",held="ledger",cape="6A4C93",spectacles=true},
		greet="Order, order! The Isle Council sits each isle year. Read the candidates, cast your ballot, and the isles will feel your choice."}
	table.insert(RA.Folk, clerk)
	RA.FolkByRole[clerk.role] = clerk
	T.Verbs.councilVisit = {item=false}
	T.NPCs[clerk.role] = {name=clerk.name,title=clerk.title,region="Hub",portrait=clerk.portrait,look=clerk.look,start="hello",anchorOnly=true,folk="council",
		nodes={
			hello={text=clerk.greet,options={
				{label="Show me the ballot",verb="councilVisit"},
				{label="How does the council work?",to="explain"},
				{label="Farewell",close=true}}},
			explain={text="Each isle year the council is chosen anew. The ballot opens on Emberfall 1 and closes at year's end. "
				.. "Every account casts one vote and may change it until the close. The winner's perks rule the whole next year on every isle, "
				.. "and the runner-up serves as Minister and lends one perk of their own.",options={
				{label="Show me the ballot",verb="councilVisit"},
				{label="Back",to="hello"},
				{label="Farewell",close=true}}},
		}}
	table.insert(T.RegionFolkOrder, clerk.role)
end
end
-- <<< END Isle Council <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- >>> BEGIN Contests & Trophy Angling (Contests team; append-only section; docs/DEPTH-CONTRACT.md §39) >>>
-- Two competitive skilling layers (SkyBlock's farming contests and trophy
-- fishing in spirit; every name, fish and rule here is original):
--   * Harvest Contests (Data.Contests = CT): every CT.PERIOD seconds (one third
--     of an isle day, ~51 min) a CT.DURATION (20 min) contest opens on the
--     Skyward Calendar featuring three garden crops (deterministic per contest
--     index, so every server and client agrees). A journal enters ONE featured
--     crop (chosen, or the first featured crop it harvests) and every unit of
--     that crop it harvests (field nodes and Verdant Garden plots) during the
--     window counts. Scores meet across servers in MemoryStore SortedMaps:
--     sharded score items (atomic, idempotent max-merge) feed a versioned
--     histogram mirror (live bracket estimates) and a per-contest leaderboard
--     map (top scores per crop); after the close one server seals exact
--     bracket cut-offs into a bounded DataStore ring. Brackets by percentile
--     (Bronze 60 % / Silver 30 % / Gold 10 % / Platinum 5 % / Diamond 2 %, each
--     needing a minimum score and a minimum field of entrants) pay Harvest
--     Medals, a journal currency spent at the Medal Exchange (farming gear,
--     the Furrow Almanac upgrade, titles). Medals never come from coins and
--     nothing in the exchange sells for more than CT.MEDAL_VALUE coins a medal.
--   * Trophy Angling (Data.Trophies = TF): fifteen trophy fish in four
--     waters, each with conditions (isle hour, season / festival, rod tier,
--     bait, Fishing level). A fishing cast that did not hook a sea creature
--     may land one (never both: no double counting); four qualities with pity
--     counters; the Trophy Ledger; the Trophy Keeper's completion rewards
--     (titles, the Gillward Hood, the Glintgill pet); a §31 announcement for
--     every Diamond catch.
-- Pure data and rules; server.server.lua ("Contests & Trophy Angling" block),
-- ui.client.lua (Workshop › Contests, Hunt › Trophies, the contest tracker).
------------------------------------------------------------------------------
do
local Cal = Data.Calendar
local G = Data.Garden
local function tab(v) return if type(v) == "table" then v else {} end
local function whole(v) return if type(v) == "number" and v == v and v >= 0 and v < math.huge then math.floor(v) else 0 end
local function item(id, def)
	def.id = id
	def.rarity = def.rarity or "Common"
	def.value = def.value or 1
	Data.Items[id] = def
	return def
end
local function recipe(id, def)
	def.id = id
	def.output = def.output or id
	def.amount = def.amount or 1
	Data.Recipes[id] = def
	return def
end
local function valueOf(costs)
	local v = 0
	for id, n in pairs(costs) do v += (Data.Items[id] and Data.Items[id].value or 0) * n end
	return v
end
-- Park-Miller stream (deterministic per seed).
local function stream(seed)
	local s = (whole(seed) % 2147483646) + 1
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

------------------------------------------------------------------------------
-- Harvest Contests
------------------------------------------------------------------------------
local CT = {}
Data.Contests = CT
CT.whole = whole
CT.NAME = "Harvest Contest"
CT.COLOR = "E9C46A"
CT.PERIOD = Cal.dayLength // 3      -- 3,050 s: three contests per isle day (dawn, midday, dusk bells)
CT.DURATION = 1200                  -- the scoring window (20 real minutes)
CT.FEATURED = 3                     -- crops per contest
CT.GRACE = 90                       -- seconds after the close before a server seals; scores harvested in time are written until GRACE / 2
CT.SHARDS = 64                      -- score items per contest (UserId % SHARDS)
CT.SHARD_CAP = 1000                 -- entrants per score item (~25 KB JSON worst case, under the 32 KB item limit; 64k per contest)
CT.GROUPS = 16                      -- histogram mirror items per contest (live estimates read these only; QC L5: 4 shards a group, worst case < 32 KB)
CT.SCORE_CAP = 10000000             -- one entry's score never exceeds this
CT.FLUSH = 10                       -- seconds between a server's score flushes (one UpdateAsync per pending shard)
CT.MIRROR = 20                      -- seconds between histogram mirror writes
CT.READ = 45                        -- seconds a server's live estimate / leaderboard stays fresh
CT.LB_BATCH = 40                    -- leaderboard writes per flush (the rest wait for the next one)
CT.LB_TOP = 10                      -- leaderboard rows read per crop
CT.TICK = 5                         -- contest heartbeat (seconds)
CT.BACKOFF_BASE = 2                 -- first retry delay of a failing key (doubles, jittered 50-100 %)
CT.BACKOFF_MAX = 120
CT.SEAL_LEASE = 60                  -- one server's claim to seal a contest
CT.SEAL_RETRY = 30                  -- seconds between sealing attempts / result reads
CT.TTL_PAD = 21600                  -- MemoryStore items expire this long after the close (per-contest TTL; QC M2: 6 h, so a late rejoiner can still get a seal)
CT.RESULT_SLOTS = 64                -- DataStore ring of sealed results (~54 hours of contests)
CT.OPEN_MAX = 8                     -- entries awaiting a sealed result per journal
CT.HISTORY = 12                     -- finished entries kept per journal
CT.ENTER_COOLDOWN = 2               -- seconds between contestEnter changes
CT.MEDAL = "HarvestMedal"           -- journal currency (p.contests.medals), not an item
CT.MEDAL_VALUE = 25                 -- most coins any exchange item sells for, per medal paid (no coin mint)
CT.MAP_PREFIX = "contest_v2_"       -- MemoryStore SortedMaps: <k>_t (score shards, histogram groups, seal), <k>_lb (leaderboard); v2 = the QC L9 packing
CT.RESULT_PREFIX = "contest_v1_result_" -- DataStore ring key <k % RESULT_SLOTS>
CT.STEWARD = "ContestSteward"
CT.QUALIFY_FARMING = 10             -- QC L9 (lead decision): entrants below Farming 10 never count toward a crop's field n
CT.QUALIFY_MEDIAN = 0.25            -- QC L9: nor do scores under 25 % of the crop's median placing score
CT.START_TOAST_FARMING = 5          -- QC L11: the HARVEST CONTEST bell toast goes to Farming 5+ journals ...
CT.START_TOAST_DAYS = 3             -- ... or to journals that scored in a contest within the last 3 days

-- Crops: the Verdant Garden crops (field crops count from nodes and plots,
-- garden-only crops from plots). min = the least score that places.
CT.Crops = {}
CT.CropById = {}
for i, c in ipairs(G.Crops) do
	local entry = {id=c.id, index=i, min=math.max(12, 60 - 7 * (i - 1)), tint=c.tint, exclusive=c.exclusive}
	table.insert(CT.Crops, entry)
	CT.CropById[c.id] = entry
end

-- Brackets, best first: top = share of placing entrants (by rank), minPop =
-- entrants a crop needs before the bracket is awarded at all.
CT.Brackets = {
	{id="Diamond",name="Diamond",top=0.02,minPop=50,medals=9,mult=3.0,color="9AE6FF"},
	{id="Platinum",name="Platinum",top=0.05,minPop=20,medals=6,mult=2.5,color="D8E3EA"},
	{id="Gold",name="Gold",top=0.10,minPop=8,medals=4,mult=2.0,color="F7C548"},
	{id="Silver",name="Silver",top=0.30,minPop=3,medals=2,mult=1.5,color="C9D1D9"},
	{id="Bronze",name="Bronze",top=0.60,minPop=1,medals=1,mult=1.25,color="CD8A4E"},
}
CT.BracketById = {}
for i, b in ipairs(CT.Brackets) do b.rank = #CT.Brackets - i + 1; CT.BracketById[b.id] = b end

-- Schedule ------------------------------------------------------------------------
function CT.indexAt(t) return (math.floor(tonumber(t) or 0) - Cal.epoch) // CT.PERIOD end
function CT.cropsOf(k)
	local draw = stream(whole(k) * 7919 + 104729)
	local pool = {}
	for _, c in ipairs(CT.Crops) do table.insert(pool, c.id) end
	local out = {}
	for _ = 1, CT.FEATURED do
		local i = math.floor(draw() * #pool) + 1
		table.insert(out, table.remove(pool, i))
	end
	return out
end
local windows = {}
-- Contest k: {k, starts, ends, sealAt, writeDeadline, crops}.
function CT.window(k)
	k = math.floor(tonumber(k) or 0)
	local w = windows[k]
	if w then return w end
	local starts = Cal.epoch + k * CT.PERIOD
	w = {k=k, starts=starts, ends=starts + CT.DURATION, sealAt=starts + CT.DURATION + CT.GRACE,
		writeDeadline=starts + CT.DURATION + CT.GRACE // 2, crops=CT.cropsOf(k)}
	local n = 0
	for _ in pairs(windows) do n += 1 end
	if n > 64 then table.clear(windows) end
	windows[k] = w
	return w
end
-- The contest at t: {k, active, starts, ends, crops, next = the next contest's window}.
function CT.at(t)
	t = math.floor(tonumber(t) or 0)
	local k = CT.indexAt(t)
	local w = CT.window(k)
	local active = t >= w.starts and t < w.ends
	return {k=k, active=active, starts=w.starts, ends=w.ends, crops=w.crops, window=w, nextWindow=CT.window(k + 1)}
end
function CT.featured(k, crop)
	for i, id in ipairs(CT.window(k).crops) do if id == crop then return i end end
	return nil
end
function CT.span(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 3600 then return (seconds // 3600) .. "h " .. ((seconds % 3600) // 60) .. "m" end
	if seconds >= 60 then return (seconds // 60) .. "m " .. string.format("%02d", seconds % 60) .. "s" end
	return seconds .. "s"
end

-- Scores ---------------------------------------------------------------------------
-- A stored entry packs the featured slot (1..3), the QC L9 low flag (the
-- journal was below CT.QUALIFY_FARMING when it scored) and the score:
-- score * 8 + low * 4 + slot. unpack -> slot, score, low.
function CT.pack(slot, score, low) return math.min(whole(score), CT.SCORE_CAP) * 8 + (if low then 4 else 0) + math.clamp(whole(slot), 1, 3) end
function CT.unpack(v)
	v = whole(v)
	local slot = v % 4
	if slot < 1 then return nil, 0, false end
	return slot, v // 8, (v // 4) % 2 == 1
end
function CT.shardOf(userId) return whole(userId) % CT.SHARDS + 1 end
function CT.groupOf(shard) return (whole(shard) - 1) % CT.GROUPS + 1 end
function CT.shardKey(shard) return "s" .. whole(shard) end
function CT.groupKey(g) return "g" .. whole(g) end
function CT.mapName(k) return CT.MAP_PREFIX .. whole(k) .. "_t" end
function CT.boardName(k) return CT.MAP_PREFIX .. whole(k) .. "_lb" end
function CT.resultKey(k) return CT.RESULT_PREFIX .. (whole(k) % CT.RESULT_SLOTS) end
-- Seconds a contest's MemoryStore items live (expiration argument), within 45 days.
function CT.ttl(k, now)
	local w = CT.window(k)
	return math.clamp(w.ends + CT.TTL_PAD - math.floor(tonumber(now) or 0), 60, 3888000)
end
function CT.backoff(fails, r)
	local span = math.min(CT.BACKOFF_MAX, CT.BACKOFF_BASE * 2 ^ math.max(0, whole(fails) - 1))
	return span * (0.5 + 0.5 * math.clamp(tonumber(r) or 0, 0, 1))
end
-- Log-scale score buckets for the live histogram (~10 % wide).
CT.BUCKET_BASE = 1.1
function CT.bucket(score)
	score = whole(score)
	if score < 1 then return 0 end
	return math.floor(math.log(score) / math.log(CT.BUCKET_BASE)) + 1
end
-- Per-slot histograms of an entry map {[uid] = packed}: {[slot] = {[bucket] = n}}, counting only placing scores.
function CT.histogram(v, k)
	local crops = CT.window(k).crops
	local h = {{}, {}, {}}
	for _, packed in pairs(tab(v)) do
		local slot, score, low = CT.unpack(packed)
		local crop = slot and CT.CropById[crops[slot]]
		if crop and score >= crop.min and not low then -- QC L9: low-level entrants never join the field
			local b = tostring(CT.bucket(score))
			h[slot][b] = (h[slot][b] or 0) + 1
		end
	end
	return h
end
-- A shard item, sanitised: {k, v = {[uid string] = packed}, h, n, ver}.
function CT.cleanShard(old, k)
	old = tab(old)
	local out = {k=whole(k), v={}, n=0, ver=whole(old.ver)}
	if whole(old.k) ~= out.k then out.ver = 0; return out end
	for uid, packed in pairs(tab(old.v)) do
		if type(uid) == "string" and #uid <= 20 and CT.unpack(packed) then out.v[uid] = whole(packed); out.n += 1 end
	end
	return out
end
-- Atomic shard transform: ops = {[uid string] = {c = slot, s = score, l = low}}
-- (the journal's current entry; l = below CT.QUALIFY_FARMING). Scores only rise (idempotent under retries, lost
-- acknowledgements, rejoins on other servers and out-of-order flushes); a
-- write after the contest's write deadline, or a new entrant into a full
-- shard, is refused. Returns the new item (nil = nothing changed) and
-- verdicts {[uid] = "ok" | "stale" | "late" | "full" | "bad"} with the stored score.
function CT.applyScores(old, ops, k, now)
	local item = CT.cleanShard(old, k)
	local verdicts, changed = {}, false
	local w = CT.window(k)
	local late = math.floor(tonumber(now) or 0) >= w.writeDeadline
	for uid, op in pairs(tab(ops)) do
		local slot, score = whole(tab(op).c), math.min(whole(tab(op).s), CT.SCORE_CAP)
		if type(uid) ~= "string" or #uid > 20 or slot < 1 or slot > CT.FEATURED or score < 1 then
			verdicts[uid] = {v="bad"}
		else
			local oldSlot, oldScore, oldLow = CT.unpack(item.v[uid])
			-- QC L9: the low flag only ever clears (a journal that scores at Farming 10+ stays qualified).
			local low = tab(op).l == true
			local newLow = if oldSlot then oldLow and low else low
			if oldSlot and oldScore >= score and newLow == oldLow then
				verdicts[uid] = {v="stale", s=oldScore}
			elseif late then
				verdicts[uid] = {v="late", s=oldScore}
			elseif not oldSlot and item.n >= CT.SHARD_CAP then
				verdicts[uid] = {v="full", s=0}
			else
				if not oldSlot then item.n += 1 end
				score = math.max(score, oldScore)
				item.v[uid] = CT.pack(oldSlot or slot, score, newLow)
				verdicts[uid] = {v="ok", s=score}
				changed = true
			end
		end
	end
	if not changed then return nil, verdicts end
	item.ver += 1
	item.h = CT.histogram(item.v, k)
	return item, verdicts
end
-- Histogram mirror group: {k, s = {[shard string] = {ver, h}}}; keeps the highest version per shard.
function CT.mirror(old, k, entries)
	old = tab(old)
	local out = {k=whole(k), s={}}
	if whole(old.k) == out.k then for key, e in pairs(tab(old.s)) do out.s[key] = e end end
	local changed = false
	for shard, e in pairs(tab(entries)) do
		local key = tostring(shard)
		local have = tab(out.s[key])
		if whole(e.ver) > whole(have.ver) then out.s[key] = {ver=whole(e.ver), h=e.h}; changed = true end
	end
	return if changed then out else nil
end
-- Summed histograms {[slot] = {buckets = {[b] = n}, n}} from group items.
function CT.sumGroups(groups)
	local out = {{buckets={}, n=0}, {buckets={}, n=0}, {buckets={}, n=0}}
	for _, g in pairs(tab(groups)) do
		for _, e in pairs(tab(tab(g).s)) do
			for slot = 1, CT.FEATURED do
				for b, n in pairs(tab(tab(tab(e).h)[slot])) do
					n = whole(n)
					out[slot].buckets[tostring(b)] = (out[slot].buckets[tostring(b)] or 0) + n
					out[slot].n += n
				end
			end
		end
	end
	return out
end
-- The best bracket a rank earns among n placing entrants (rank 1 = best).
function CT.bracketForRank(rank, n)
	rank, n = whole(rank), whole(n)
	if rank < 1 or n < 1 then return nil end
	for _, b in ipairs(CT.Brackets) do
		if n >= b.minPop and rank <= math.max(1, math.floor(b.top * n)) then return b.id end
	end
	return nil
end
-- Live estimate from a summed histogram: entrants in strictly higher buckets
-- rank ahead of you, and of your own bucket the share above your position in
-- it (scores spread evenly in log space). Returns bracket id | nil, rank, n.
function CT.estimate(hist, score, crop)
	hist = tab(hist)
	local def = CT.CropById[crop]
	score = whole(score)
	if not def or score < def.min then return nil, 0, whole(hist.n) end
	local mine = CT.bucket(score)
	local above, same, n = 0, 0, 0
	for b, count in pairs(tab(hist.buckets)) do
		b, count = tonumber(b) or 0, whole(count)
		n += count
		if b > mine then above += count elseif b == mine then same += count end
	end
	if same == 0 then same, n = 1, n + 1 end -- not mirrored yet: count yourself in
	local position = math.clamp(math.log(score) / math.log(CT.BUCKET_BASE) + 1 - mine, 0, 1)
	local rank = above + math.floor((same - 1) * (1 - position) + 0.5) + 1
	return CT.bracketForRank(rank, n), rank, n
end
-- Median score of a list of {s} sorted best first (0 when empty).
function CT.median(list)
	local m = #tab(list)
	if m == 0 then return 0 end
	return (list[(m + 1) // 2].s + list[m // 2 + 1].s) / 2
end
-- Exact sealing: cut-off scores per slot from every stored entry.
-- QC L9 (lead decision): the field n (bracket shares and minimum fields) and
-- the cut-offs come only from qualified entrants: Farming >= CT.QUALIFY_FARMING
-- when they scored (the packed low flag) and a score >= CT.QUALIFY_MEDIAN x the
-- crop's median placing score. Every placing entrant is still judged by the
-- cut-offs and can hold a top-three row.
-- result = {k, crops, slots = {[slot] = {n, cut = {[bracket] = score}, top = {{u, s}}}}}.
function CT.seal(k, shards)
	local w = CT.window(k)
	local lists = {{}, {}, {}}
	local seen = {}
	for _, sh in pairs(tab(shards)) do
		for uid, packed in pairs(tab(tab(sh).v)) do
			local slot, score, low = CT.unpack(packed)
			local crop = slot and CT.CropById[w.crops[slot]]
			if crop and score >= crop.min and not seen[uid] then
				seen[uid] = true
				table.insert(lists[slot], {u=uid, s=score, low=low})
			end
		end
	end
	local result = {k=w.k, crops=w.crops, slots={}}
	for slot = 1, CT.FEATURED do
		local list = lists[slot]
		table.sort(list, function(a, b) if a.s ~= b.s then return a.s > b.s end return a.u < b.u end)
		local least = CT.QUALIFY_MEDIAN * CT.median(list)
		local field = {}
		for _, e in ipairs(list) do if not e.low and e.s >= least then table.insert(field, e) end end
		local n = #field
		local cut = {}
		for _, b in ipairs(CT.Brackets) do
			if n >= b.minPop then cut[b.id] = field[math.max(1, math.floor(b.top * n))].s end
		end
		local top = {}
		for i = 1, math.min(3, #list) do table.insert(top, {u=list[i].u, s=list[i].s}) end
		result.slots[slot] = {n=n, cut=cut, top=top}
	end
	return result
end
-- QC L5 / L10: the contest k of a server-memory key "<map name>/<key>" (nil
-- when it is not a contest map key).
function CT.keyContest(name)
	local prefix = string.gsub(CT.MAP_PREFIX, "%p", "%%%0")
	return tonumber(string.match(tostring(name), "^" .. prefix .. "(%d+)_"))
end
-- Drops server memory no write can use any more: mirror queues and per-key
-- backoff state of contests past their write deadline (and keys of no contest).
function CT.prune(mirrorQ, keyState, now)
	now = math.floor(tonumber(now) or 0)
	for k in pairs(tab(mirrorQ)) do
		if type(k) ~= "number" or now >= CT.window(k).writeDeadline then mirrorQ[k] = nil end
	end
	for name in pairs(tab(keyState)) do
		local k = CT.keyContest(name)
		if not k or now >= CT.window(k).writeDeadline then keyState[name] = nil end
	end
end
-- QC L11: does contest k's bell toast go to this journal? Farming >=
-- CT.START_TOAST_FARMING, or an entry scored within CT.START_TOAST_DAYS.
function CT.wantsStartToast(farmingLevel, c, k)
	if whole(farmingLevel) >= CT.START_TOAST_FARMING then return true end
	c = tab(c)
	local recent = whole(k) - math.ceil(CT.START_TOAST_DAYS * 86400 / CT.PERIOD)
	local cur = tab(c.cur)
	if whole(cur.s) > 0 and whole(cur.k) >= recent then return true end
	for _, list in ipairs({tab(c.open), tab(c.history)}) do
		for _, e in ipairs(list) do if type(e) == "table" and whole(e.k) >= recent then return true end end
	end
	return false
end
-- A stored result, sanitised (nil when it is not contest k's).
function CT.cleanResult(r, k)
	r = tab(r)
	if whole(r.k) ~= whole(k) or type(r.slots) ~= "table" then return nil end
	local out = {k=whole(k), slots={}}
	for slot = 1, CT.FEATURED do
		local s = tab(r.slots[slot] or r.slots[tostring(slot)])
		local cut = {}
		for _, b in ipairs(CT.Brackets) do
			local v = tab(s.cut)[b.id]
			if type(v) == "number" and v >= 1 then cut[b.id] = whole(v) end
		end
		local top = {}
		for _, e in ipairs(tab(s.top)) do
			if type(e) == "table" and type(e.u) == "string" and #top < 3 then table.insert(top, {u=e.u, s=whole(e.s), n=type(e.n) == "string" and string.sub(e.n, 1, 20) or nil}) end
		end
		out.slots[slot] = {n=whole(s.n), cut=cut, top=top}
	end
	return out
end
-- The bracket a final score earns against a sealed result's cut-offs (nil = no bracket).
function CT.bracketOf(result, slot, score, crop)
	local s = tab(tab(tab(result).slots)[slot])
	local def = CT.CropById[crop]
	score = whole(score)
	if not def or score < def.min then return nil end
	for _, b in ipairs(CT.Brackets) do
		local cut = tab(s.cut)[b.id]
		if type(cut) == "number" and score >= cut then return b.id end
	end
	return nil
end
-- Rewards for a finished entry: medals and Farming XP (placing entrants only).
function CT.reward(crop, bracket, placed)
	local def = CT.CropById[crop]
	if not def or not placed then return 0, 0 end
	local b = CT.BracketById[bracket]
	local xp = math.floor(150 * def.index * (b and b.mult or 1))
	return b and b.medals or 0, xp
end

-- Medal Exchange ------------------------------------------------------------------
-- QC M1: the two medallions are one accessory family (Progression.accessoryFamily
-- reads def.family): only the better one ever counts.
item("FurrowMedallion",{name="Furrow Medallion",kind="accessory",family="contests:medallion",rarity="Uncommon",color=Data.Rarity.Uncommon.color,stats={farmingFortune=8},value=40*Data.Rarity.Uncommon.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Uncommon.power..". Medal Exchange (Harvest Contests)."})
item("LaureateMedallion",{name="Laureate's Medallion",kind="accessory",family="contests:medallion",rarity="Epic",color=Data.Rarity.Epic.color,stats={farmingFortune=20,health=10},value=40*Data.Rarity.Epic.rank^2,
	description="Accessory. Magical Power "..Data.Rarity.Epic.power..". Medal Exchange; upgrades the Furrow Medallion."})
item("MedalistHoe",{name="Medalist's Hoe",kind="tool",toolKind="Hoe",slot="hoe",toolTier=5,tier=5,rarity="Epic",color="E9C46A",stats={farmingFortune=135},requires={Farming=55},value=1800,
	description="Tier 5 hoe from the Medal Exchange. Requires Farming 55."})
item("HarvestTonic",{name="Harvest Tonic",kind="consumable",category="potion",rarity="Uncommon",color="E9C46A",buff={stats={farmingFortune=50},duration=600},value=30,
	description="Potion: +50 Farming Fortune for 10 minutes. Medal Exchange."})
-- kind: item (amount; unique = one owned at most; upgrade = item consumed;
-- level = Farming; gardenLevel = Verdant Garden level), almanac (the next
-- Furrow Almanac volume), title (cosmetic).
-- QC M5: an item the Verdant Garden shop also sells never costs fewer medals
-- than its garden price per unit (coins + materials at their value) /
-- CT.MEDAL_VALUE, behind the same garden-level gate.
function CT.gardenUnitValue(itemId)
	local e = G.ShopById[itemId]
	if not e or e.kind ~= "item" then return nil end
	local v = 0
	for id, n in pairs(e.cost) do v += (if id == "coins" then 1 else (Data.Items[id] and Data.Items[id].value or 0)) * n end
	return v / math.max(1, e.amount)
end
CT.ALMANAC = {5, 5, 5, 5}           -- +Farming Fortune per volume (p.perkStats.contests; never Health / Defense)
CT.ALMANAC_COST = {20, 45, 80, 130}
CT.Titles = {
	{id="Furrowhand",title="Furrowhand",medals=15,color="CD8A4E"},
	{id="GoldenSheaf",title="Golden Sheaf",medals=60,color="F7C548"},
	{id="FieldLaureate",title="Field Laureate",medals=150,color="9AE6FF"},
}
CT.TitleById = {}
for _, t in ipairs(CT.Titles) do CT.TitleById[t.id] = t end
CT.Shop = {
	{id="HarvestTonic",kind="item",item="HarvestTonic",amount=2,medals=3},
	{id="LotusBud",kind="item",item="LotusBud",amount=1,medals=math.ceil(CT.gardenUnitValue("LotusBud") / CT.MEDAL_VALUE),gardenLevel=G.ShopById.LotusBud.level},
	{id="FurrowMedallion",kind="item",item="FurrowMedallion",amount=1,medals=25,unique=true},
	{id="LaureateMedallion",kind="item",item="LaureateMedallion",amount=1,medals=90,unique=true,upgrade="FurrowMedallion"},
	{id="MedalistHoe",kind="item",item="MedalistHoe",amount=1,medals=110,unique=true,level=55},
	{id="Almanac",kind="almanac"},
}
for _, t in ipairs(CT.Titles) do table.insert(CT.Shop, {id="Title"..t.id, kind="title", title=t.id, medals=t.medals}) end
CT.ShopById = {}
for i, e in ipairs(CT.Shop) do e.index = i; CT.ShopById[e.id] = e end
-- QC M1: items that upgrade from `itemId` through the exchange (transitively).
function CT.upgradesOf(itemId)
	local out, frontier = {}, {itemId}
	while #frontier > 0 do
		local from = table.remove(frontier)
		for _, e in ipairs(CT.Shop) do
			if e.upgrade == from and e.item and not table.find(out, e.item) then table.insert(out, e.item); table.insert(frontier, e.item) end
		end
	end
	return out
end
function CT.almanacStats(volumes)
	local ff = 0
	for i = 1, math.min(whole(volumes), #CT.ALMANAC) do ff += CT.ALMANAC[i] end
	return if ff > 0 then {farmingFortune=ff} else nil
end
function CT.offerCost(e, volumes)
	if e.kind == "almanac" then return CT.ALMANAC_COST[whole(volumes) + 1] end
	return e.medals
end

-- Journal record p.contests = {cur = {k, c, s, at} | nil, open = {{k, c, s}},
-- best = {[crop] = score}, medals, earned, entries, placed, brackets = {[id] = n},
-- history = {{k, c, s, b, m}}, almanac, titles = {[id] = true}, title, ann}.
function CT.migrate(raw)
	raw = tab(raw)
	local c = {open={}, best={}, history={}, brackets={}, titles={}, ann=whole(raw.ann)}
	for _, key in ipairs({"medals","earned","entries","placed","almanac","spent"}) do c[key] = whole(raw[key]) end
	c.almanac = math.min(c.almanac, #CT.ALMANAC)
	local cur = tab(raw.cur)
	if whole(cur.k) > 0 and CT.CropById[cur.c] and CT.featured(cur.k, cur.c) then
		c.cur = {k=whole(cur.k), c=cur.c, s=math.min(whole(cur.s), CT.SCORE_CAP), at=whole(cur.at)}
	end
	for _, e in ipairs(tab(raw.open)) do
		if type(e) == "table" and whole(e.k) > 0 and CT.CropById[e.c] and CT.featured(e.k, e.c) and #c.open < CT.OPEN_MAX then
			table.insert(c.open, {k=whole(e.k), c=e.c, s=math.min(whole(e.s), CT.SCORE_CAP)})
		end
	end
	for crop, s in pairs(tab(raw.best)) do if CT.CropById[crop] then c.best[crop] = math.min(whole(s), CT.SCORE_CAP) end end
	for _, e in ipairs(tab(raw.history)) do
		if type(e) == "table" and CT.CropById[e.c] and #c.history < CT.HISTORY then
			table.insert(c.history, {k=whole(e.k), c=e.c, s=whole(e.s), b=CT.BracketById[e.b] and e.b or nil, m=whole(e.m)})
		end
	end
	for _, b in ipairs(CT.Brackets) do local n = whole(tab(raw.brackets)[b.id]); if n > 0 then c.brackets[b.id] = n end end
	for id in pairs(tab(raw.titles)) do if CT.TitleById[id] then c.titles[id] = true end end
	if type(raw.title) == "string" and c.titles[raw.title] then c.title = raw.title end
	return c
end

------------------------------------------------------------------------------
-- Trophy Angling
------------------------------------------------------------------------------
local TF = {}
Data.Trophies = TF
TF.whole = whole
TF.NAME = "Trophy Angling"
TF.COLOR = "5EC8D8"
TF.KEEPER = "TrophyKeeper"
-- Qualities, worst first. weight = base share of trophy catches.
TF.Tiers = {
	{id="Bronze",name="Bronze",weight=0.70,mult=1,color="CD8A4E"},
	{id="Silver",name="Silver",weight=0.22,mult=1.5,color="C9D1D9"},
	{id="Gold",name="Gold",weight=0.07,mult=2.5,color="F7C548"},
	{id="Diamond",name="Diamond",weight=0.01,mult=5,color="9AE6FF"},
}
TF.TierById = {}
for i, t in ipairs(TF.Tiers) do t.index = i; TF.TierById[t.id] = t end
TF.PITY_GOLD = 60                   -- catches of one fish without Gold or better: the next is at least Gold
TF.PITY_DIAMOND = 300               -- catches of one fish without a Diamond: the next is Diamond
TF.ROD_GOLD, TF.ROD_DIAMOND = 0.01, 0.002 -- per rod tier above the fish's requirement
TF.BASE_CHANCE = 0.03               -- a trophy bite per eligible cast
TF.CHANCE_CAP = 0.10
TF.HOOD_CHANCE = 0.01               -- Gillward Hood worn
TF.PET = "Glintgill"
TF.PET_CHANCE = 0.00015             -- per Glintgill level (+1.5 % at level 100)
TF.RarityXp = {Common=40, Uncommon=80, Rare=160, Epic=320, Legendary=640}
-- Waters: region id of the fishing prompt -> water (nil / Meadow / Hub = the Shallows).
TF.Waters = {
	{id="Shallows",name="Sunwheel Shallows",regions={"Meadow","Hub"},color="8FB8D6"},
	{id="Gloomhollow",name="Gloomhollow Mere",regions={"Gloomhollow"},color="6A4C93"},
	{id="Tidewater",name="Tidewater Deeps",regions={"Tidewater"},color="2F8FA8"},
	{id="ShatteredCrown",name="Crownrift Pools",regions={"ShatteredCrown"},color="F2D27A"},
}
TF.WaterById = {}
for _, w in ipairs(TF.Waters) do TF.WaterById[w.id] = w end
function TF.waterOf(region)
	if region == nil or region == "" then return "Shallows" end
	for _, w in ipairs(TF.Waters) do if table.find(w.regions, region) then return w.id end end
	return nil
end
-- Isle clock hour 0..24 (the sidebar's clock; night = hour < 6 or >= 19).
function TF.hourAt(t)
	local into = (math.floor(tonumber(t) or 0) - Cal.epoch) % Cal.dayLength
	return into / Cal.dayLength * 24
end
function TF.inHours(hours, h)
	if type(hours) ~= "table" then return true end
	local from, to = hours[1], hours[2]
	if from <= to then return h >= from and h < to end
	return h >= from or h < to
end
-- Baits (Cooking at the Hearth; one is spent per cast in trophy waters while loaded).
TF.BaitOrder = {"GlowgrubBait","BrineglowLure","AbyssalLure"}
TF.Baits = {
	GlowgrubBait={name="Glowgrub Bait",level=10,bonus=0.01,costs={Fish=2,Herb=2},amount=4,color="C6E377",rarity="Common"},
	BrineglowLure={name="Brineglow Lure",level=35,bonus=0.015,costs={BrineShell=2,GlowJelly=1},amount=4,color="C3A6FF",rarity="Uncommon"},
	AbyssalLure={name="Abyssal Lure",level=60,bonus=0.02,costs={AbyssInk=1,SeaScale=2},amount=4,color="2B2D42",rarity="Rare"},
}
for _, id in ipairs(TF.BaitOrder) do
	local b = TF.Baits[id]
	b.id = id
	recipe(id, {skill="Cooking",level=b.level,xp=12 + b.level,costs=b.costs,amount=b.amount,repeatable=true,station="Hearth",category="Bait"})
	item(id, {name=b.name,kind="material",category="bait",rarity=b.rarity,color=b.color,value=math.floor(valueOf(b.costs) / b.amount * 0.8),
		description="Trophy bait: load it in Hunt › Trophies. +"..(b.bonus * 100).."% trophy chance; some trophy fish bite only on it."})
end
-- The fifteen trophy fish. water, hours = isle clock window, season / event
-- (Data.Calendar), rod = least rod tier, bait = bait item, fishing = level.
TF.Fish = {
	{id="PebblefinDarter",name="Pebblefin Darter",water="Shallows",rod=0,fishing=1,weight=100,rarity="Common",color="A8C5D6",text="Darts between the dock stones of the Shallows at any hour."},
	{id="DawnscaleMinnow",name="Dawnscale Minnow",water="Shallows",hours={5,9},rod=1,fishing=5,weight=60,rarity="Uncommon",color="FFD6A5",text="Rises to the first light: isle hours 5 to 9."},
	{id="BloomtideCarplet",name="Bloomtide Carplet",water="Shallows",season="Bloomtide",rod=1,fishing=10,weight=50,rarity="Uncommon",color="9BD77E",text="Spawns only in the season of Bloomtide."},
	{id="MooncressLoach",name="Mooncress Loach",water="Shallows",hours={19,6},bait="GlowgrubBait",rod=1,fishing=15,weight=35,rarity="Rare",color="B8C0FF",text="Feeds at night, and only on Glowgrub Bait."},
	{id="BrinebarbSnapper",name="Brinebarb Snapper",water="Tidewater",rod=2,fishing=30,weight=90,rarity="Common",color="E07A5F",text="The common brawler of the Tidewater Deeps."},
	{id="SunglintBream",name="Sunglint Bream",water="Tidewater",season="Sunreach",hours={9,17},rod=2,fishing=32,weight=45,rarity="Uncommon",color="FFD166",text="Basks in Sunreach daylight: isle hours 9 to 17."},
	{id="GloamtideRay",name="Gloamtide Ray",water="Tidewater",hours={17,21},bait="BrineglowLure",rod=3,fishing=45,weight=35,rarity="Rare",color="7A6FC2",text="Glides up at dusk (isle hours 17 to 21) for a Brineglow Lure."},
	{id="FestivalSquallfin",name="Glimmer Squallfin",water="Tidewater",event="GlimmertideFestival",rod=3,fishing=40,weight=30,rarity="Epic",color="F4B860",text="Leaps only while the Glimmertide Festival is on."},
	{id="CoralcrownAngler",name="Coralcrown Angler",water="Tidewater",bait="AbyssalLure",rod=5,fishing=70,weight=20,rarity="Epic",color="EF6F6C",text="Lurks in the deepest reef; it takes only an Abyssal Lure on a tier 5 rod."},
	{id="TidewyrmFry",name="Tidewyrm Fry",water="Tidewater",hours={19,6},rod=5,fishing=78,weight=6,rarity="Legendary",color="06D6A0",text="A Matriarch's hatchling, abroad only at night."},
	{id="LanternjawGudgeon",name="Lanternjaw Gudgeon",water="Gloomhollow",rod=4,fishing=60,weight=80,rarity="Uncommon",color="FFE08A",text="Its glowing jaw lights the Gloomhollow Mere."},
	{id="VoidgillCavefish",name="Voidgill Cavefish",water="Gloomhollow",hours={19,6},rod=4,fishing=62,weight=40,rarity="Rare",color="5B3F8C",text="Blind and patient; it surfaces at night."},
	{id="HollowmereEel",name="Hollowmere Eel",water="Gloomhollow",event="HollowNight",rod=4,fishing=64,weight=25,rarity="Epic",color="C77DFF",text="Stirs only on Hollow Night."},
	{id="RiftscaleKoi",name="Riftscale Koi",water="ShatteredCrown",rod=5,fishing=80,weight=50,rarity="Rare",color="F2D27A",text="Swims the Crownrift Pools, scales split by starlight."},
	{id="CrownveilSunfish",name="Crownveil Sunfish",water="ShatteredCrown",season="Frostveil",rod=6,fishing=88,weight=8,rarity="Legendary",color="FFF3B0",text="A Frostveil wonder; only a tier 6 rod holds it."},
}
TF.FishById = {}
for i, f in ipairs(TF.Fish) do f.index = i; TF.FishById[f.id] = f end
-- Does fish f bite for this cast? ctx = {water, hour, season, event, rod, fishing, bait}.
function TF.bites(f, ctx)
	ctx = tab(ctx)
	if f.water ~= ctx.water then return false, "water" end
	if whole(ctx.fishing) < f.fishing then return false, "fishing" end
	if whole(ctx.rod) < f.rod then return false, "rod" end
	if f.season and ctx.season ~= f.season then return false, "season" end
	if f.event and ctx.event ~= f.event then return false, "event" end
	if f.hours and not TF.inHours(f.hours, tonumber(ctx.hour) or 12) then return false, "hours" end
	if f.bait and ctx.bait ~= f.bait then return false, "bait" end
	return true
end
function TF.pool(ctx)
	local out = {}
	for _, f in ipairs(TF.Fish) do if TF.bites(f, ctx) then table.insert(out, f) end end
	return out
end
function TF.waterHasFish(water)
	for _, f in ipairs(TF.Fish) do if f.water == water then return true end end
	return false
end
-- Trophy chance for a cast: base + bait + hood + Glintgill pet level, capped.
function TF.chance(ctx)
	ctx = tab(ctx)
	local c = TF.BASE_CHANCE
	local bait = ctx.bait and TF.Baits[ctx.bait]
	if bait then c += bait.bonus end
	if ctx.hood then c += TF.HOOD_CHANCE end
	c += math.clamp(whole(ctx.petLevel), 0, Data.PET_MAX_LEVEL) * TF.PET_CHANCE
	return math.min(TF.CHANCE_CAP, c)
end
-- Quality for one catch of fish f: rod tiers above the requirement shift
-- weight to Gold / Diamond; pity guarantees Gold after PITY_GOLD catches
-- without Gold+ and Diamond after PITY_DIAMOND without one.
function TF.quality(f, rod, pity, r)
	pity = tab(pity)
	if whole(pity.d) + 1 >= TF.PITY_DIAMOND then return "Diamond", true end
	local above = math.max(0, whole(rod) - f.rod)
	local w = {TF.Tiers[1].weight, TF.Tiers[2].weight, TF.Tiers[3].weight + above * TF.ROD_GOLD, TF.Tiers[4].weight + above * TF.ROD_DIAMOND}
	w[1] = math.max(0.3, 1 - w[2] - w[3] - w[4])
	local total = w[1] + w[2] + w[3] + w[4]
	local pick = (tonumber(r) or 0) * total
	local tier = "Diamond"
	for i = 1, 4 do
		if pick < w[i] then tier = TF.Tiers[i].id; break end
		pick -= w[i]
	end
	if whole(pity.g) + 1 >= TF.PITY_GOLD and TF.TierById[tier].index < 3 then return "Gold", true end
	return tier, false
end
-- One eligible cast: rolls r1 (bite), r2 (which fish), r3 (quality). Returns fish, tier, pityUsed | nil.
function TF.roll(ctx, pityOf, r1, r2, r3)
	local pool = TF.pool(ctx)
	if #pool == 0 or (tonumber(r1) or 1) >= TF.chance(ctx) then return nil end
	local total = 0
	for _, f in ipairs(pool) do total += f.weight end
	local pick, fish = (tonumber(r2) or 0) * total, pool[#pool]
	for _, f in ipairs(pool) do
		pick -= f.weight
		if pick < 0 then fish = f; break end
	end
	local tier, pity = TF.quality(fish, ctx.rod, pityOf and pityOf(fish.id), r3)
	return fish, tier, pity
end
function TF.xp(f, tier)
	local t = TF.TierById[tier]
	return math.floor((TF.RarityXp[f.rarity] or 40) * (t and t.mult or 1))
end
-- Gillward Hood (Trophy Keeper): a fishing helmet under the Stormcaller line.
item("GillwardHood",{name="Gillward Hood",kind="armor",slot="helmet",tier=3,rarity="Rare",color="5EC8D8",stats={fishingFortune=6,health=10,seaCreatureChance=1},requires={Fishing=25},value=600,
	trophyChance=TF.HOOD_CHANCE,description="The Trophy Keeper's gift. +1% trophy fish chance while worn. Requires Fishing 25."})
-- Glintgill: the trophy-fishing pet (Trophy Keeper).
do
	local pet = {id=TF.PET,name="Glintgill",skill="Fishing",rarity="Epic",color="7FE0D0",perLevel={fishingFortune=0.4,seaCreatureChance=0.03,health=0.3}}
	table.insert(Data.Pets, pet)
	Data.PetById[pet.id] = pet
	local PD = Data.PetDepth
	if PD and PD.Abilities then
		local list = {
			{name="Gleam Lure",kind="xp",skills={"Fishing"},per=0.08,rarity="Common"},
			{name="Shoal Sight",kind="stat",stat="fishingFortune",per=0.25,rarity="Rare"},
			{name="Deep Glint",kind="stat",stat="seaCreatureChance",per=0.03,rarity="Legendary",level=40},
		}
		for i, a in ipairs(list) do a.index = i; a.id = a.name:gsub("[^%w]", "") end
		PD.Abilities[pet.id] = list
		if PD.Looks then PD.Looks[pet.id] = {form="hopper",accent="E8FFF9"} end
		pet.ability = list[1].name..": up to "..PD.abilityText(list[1], PD.abilityValue(list[1], Data.PET_MAX_LEVEL, PD.MAX_RARITY))
		pet.abilityNames = {list[1].name, list[2].name, list[3].name}
	else
		pet.ability = "Gleam Lure"
	end
	item(pet.id.."Pet",{name=pet.name.." Pet",kind="pet",pet=pet.id,rarity=pet.rarity,color=pet.color,value=200*Data.Rarity.Epic.rank^2,
		description="Summon from your pet menu. Abilities: "..table.concat(pet.abilityNames or {pet.ability}, ", ")..". Trophy Sense: +"..(TF.PET_CHANCE * 100 * Data.PET_MAX_LEVEL).."% trophy fish chance at level "..Data.PET_MAX_LEVEL..". The Trophy Keeper's reward."})
end
-- The Trophy Ledger: completion tiers claimed from the Trophy Keeper.
-- need = {tier = least quality, count = fish (nil = every fish)}.
TF.Ledger = {
	{id="Novice",name="First Catches",need={tier="Bronze",count=5},title="Trophy Angler",xp=2000,color="CD8A4E"},
	{id="Bronze",name="Bronze Ledger",need={tier="Bronze"},item="GillwardHood",xp=6000,color="CD8A4E"},
	{id="Silver",name="Silver Ledger",need={tier="Silver"},title="Silverline Angler",item=TF.PET.."Pet",xp=20000,color="C9D1D9"},
	{id="Gold",name="Gold Ledger",need={tier="Gold"},title="Gilded Angler",xp=60000,color="F7C548"},
	{id="Diamond",name="Diamond Ledger",need={tier="Diamond"},title="Diamond Tidekeeper",xp=150000,color="9AE6FF"},
}
TF.LedgerById = {}
for i, l in ipairs(TF.Ledger) do l.index = i; TF.LedgerById[l.id] = l end
-- Fish whose best quality is at least `tier`.
function TF.countAt(best, tier)
	local need = TF.TierById[tier] and TF.TierById[tier].index or 1
	local n = 0
	for _, f in ipairs(TF.Fish) do
		local b = TF.TierById[tab(best)[f.id]]
		if b and b.index >= need then n += 1 end
	end
	return n
end
function TF.ledgerNeed(l) return l.need.count or #TF.Fish end
function TF.ledgerDone(best, l) return TF.countAt(best, l.need.tier) >= TF.ledgerNeed(l) end
function TF.titles(claimed)
	local out = {}
	for _, l in ipairs(TF.Ledger) do if l.title and tab(claimed)[l.id] then table.insert(out, l) end end
	return out
end
-- Journal record p.trophy = {caught = {[fish] = {Bronze, Silver, Gold, Diamond counts}},
-- best = {[fish] = tier}, pity = {[fish] = {g, d}}, total, diamonds, bait, claimed = {[ledger] = true}, title, casts, ledgerAnn = {[ledger] = true}}.
function TF.migrate(raw)
	raw = tab(raw)
	local t = {caught={}, best={}, pity={}, claimed={}, total=0, diamonds=0, casts=whole(raw.casts)}
	for _, f in ipairs(TF.Fish) do
		local c = tab(tab(raw.caught)[f.id])
		local row, any = {}, false
		for _, tier in ipairs(TF.Tiers) do
			local n = whole(c[tier.id])
			if n > 0 then row[tier.id] = n; any = true; t.total += n; if tier.id == "Diamond" then t.diamonds += n end; t.best[f.id] = tier.id end
		end
		if any then t.caught[f.id] = row end
		local p = tab(tab(raw.pity)[f.id])
		if whole(p.g) > 0 or whole(p.d) > 0 then t.pity[f.id] = {g=math.min(whole(p.g), TF.PITY_GOLD), d=math.min(whole(p.d), TF.PITY_DIAMOND)} end
	end
	if type(raw.bait) == "string" and TF.Baits[raw.bait] then t.bait = raw.bait end
	for id in pairs(tab(raw.claimed)) do if TF.LedgerById[id] then t.claimed[id] = true end end
	-- QC L2: ledger tiers already announced (known ids only).
	t.ledgerAnn = {}
	for id in pairs(tab(raw.ledgerAnn)) do if TF.LedgerById[id] then t.ledgerAnn[id] = true end end
	if type(raw.title) == "string" then
		for _, l in ipairs(TF.titles(t.claimed)) do if l.id == raw.title then t.title = raw.title end end
	end
	return t
end
-- Record one catch (mutates the record); returns isNewBest.
function TF.record(t, fishId, tier)
	t.caught[fishId] = t.caught[fishId] or {}
	t.caught[fishId][tier] = whole(t.caught[fishId][tier]) + 1
	t.total = whole(t.total) + 1
	if tier == "Diamond" then t.diamonds = whole(t.diamonds) + 1 end
	local p = t.pity[fishId] or {g=0, d=0}
	local idx = TF.TierById[tier].index
	p.g = if idx >= 3 then 0 else math.min(whole(p.g) + 1, TF.PITY_GOLD)
	p.d = if idx >= 4 then 0 else math.min(whole(p.d) + 1, TF.PITY_DIAMOND)
	t.pity[fishId] = p
	local old = TF.TierById[t.best[fishId]]
	if not old or idx > old.index then t.best[fishId] = tier; return true end
	return false
end

------------------------------------------------------------------------------
-- §31 announcements: contest start / result / personal best, trophy catches.
------------------------------------------------------------------------------
local F = Data.Features
if F and F.announceText then
	local announceText = F.announceText
	function F.announceText(e)
		if type(e) == "table" and e.kind == "contest" then
			local crops = {}
			for _, id in ipairs(tab(e.crops)) do table.insert(crops, Data.Items[id] and Data.Items[id].name or tostring(id)) end
			local crop = type(e.crop) == "string" and Data.Items[e.crop] and Data.Items[e.crop].name or tostring(e.crop)
			if e.phase == "start" then
				return {head="HARVEST CONTEST", body=table.concat(crops, "  ·  ") .. "  ·  20 minutes", color=CT.COLOR}
			elseif e.phase == "best" then
				return {head="NEW PERSONAL BEST", body=crop .. "  ·  " .. whole(e.score), color="9EE7D2"}
			end
			local b = CT.BracketById[e.bracket]
			return {head=b and (string.upper(b.name) .. " BRACKET") or "CONTEST RESULT",
				body=crop .. "  ·  " .. whole(e.score) .. (if whole(e.medals) > 0 then "  ·  +" .. whole(e.medals) .. " Harvest Medals" else "  ·  no bracket"),
				color=b and b.color or CT.COLOR}
		elseif type(e) == "table" and (e.kind == "trophy" or e.kind == "trophyWorld") then
			local f = TF.FishById[e.fish]
			local t = TF.TierById[e.tier] or TF.Tiers[1]
			local name = f and f.name or tostring(e.fish)
			if e.kind == "trophyWorld" then
				return {head="DIAMOND TROPHY", body=string.sub(tostring(e.who or "A wayfarer"), 1, 20) .. " landed a Diamond " .. name, color=t.color}
			end
			return {head=string.upper(t.name) .. " TROPHY", body=name .. (if e.new then "  ·  new best" else ""), color=t.color}
		elseif type(e) == "table" and e.kind == "trophyLedger" then
			local l = TF.LedgerById[e.ledger]
			return {head="TROPHY LEDGER", body=(l and l.name or "Ledger") .. " complete  ·  see the Trophy Keeper", color=l and l.color or TF.COLOR}
		end
		return announceText(e)
	end
	F.ANNOUNCE_PRIORITY.contest = true
end

------------------------------------------------------------------------------
-- Townsfolk: the Contest Steward (Sunwheel Downs) and the Trophy Keeper
-- (Tidewater Shoals). Regional folk entries: World Art places their anchors.
------------------------------------------------------------------------------
local T, RA = Data.Townsfolk, Data.RegionArt
if T and RA and RA.Folk and T.NPCs then
	if T.AtlasStations then
		T.AtlasStations.Contests = "Workshop · Contests"
		T.AtlasStations.Trophies = "Hunt · Trophies"
	end
	local steward = {role=CT.STEWARD,region="Meadow",name="Odile Furrowgate",title="Contest Steward",portrait="🌾",kind="contests",
		look={skin="E0AC69",shirt="7A8F3A",pants="4A3B2A",shoes="2E2418",accent="E9C46A",hair="8A5A2B",hat="wayfarer",held="ledger",apron="C9A66B"},
		greet="Three crops to a contest, twenty minutes on the bell, and every isle's farmers on one ledger. Pick your crop and swing that hoe!"}
	table.insert(RA.Folk, steward)
	RA.FolkByRole[steward.role] = steward
	T.NPCs[steward.role] = {name=steward.name,title=steward.title,region="Meadow",portrait=steward.portrait,look=steward.look,start="hello",anchorOnly=true,folk="contests",
		nodes={
			hello={text=steward.greet,options={
				{label="Show me the contests",atlas="Contests"},
				{label="How do contests work?",to="explain"},
				{label="Farewell",close=true}}},
			explain={text="A contest opens three times every isle day and runs for twenty minutes. Each one features three crops. "
				.. "Enter one of them, or simply harvest a featured crop and I'll enter you with it. Everything you harvest of that crop counts, from fields or your garden. "
				.. "When the bell rings, the top sixty in a hundred earn a bracket: Bronze, Silver, Gold, Platinum, and Diamond for the very best. "
				.. "Brackets pay Harvest Medals, which my Medal Exchange takes for tools, tonics and titles.",options={
				{label="Show me the contests",atlas="Contests"},
				{label="Back",to="hello"},
				{label="Farewell",close=true}}},
		}}
	table.insert(T.RegionFolkOrder, steward.role)
	local keeper = {role=TF.KEEPER,region="Tidewater",name="Marlow Gillcrest",title="Trophy Keeper",portrait="🐟",kind="trophies",
		look={skin="C68642",shirt="2F5D6B",pants="2A3A44",shoes="1E2226",accent="5EC8D8",hair="B8B2A7",hat="souwester",held="rod",beard=true},
		greet="Every fish in that ledger I've landed myself, once. Bring me the rarest the isles hide, and the finest of each, and I'll make it worth your while."}
	table.insert(RA.Folk, keeper)
	RA.FolkByRole[keeper.role] = keeper
	T.NPCs[keeper.role] = {name=keeper.name,title=keeper.title,region="Tidewater",portrait=keeper.portrait,look=keeper.look,start="hello",anchorOnly=true,folk="trophies",
		nodes={
			hello={text=keeper.greet,options={
				{label="Open the Trophy Ledger",atlas="Trophies"},
				{label="How does trophy fishing work?",to="explain"},
				{label="Farewell",close=true}}},
			explain={text="Fifteen trophy fish swim four waters: the Sunwheel Shallows, the Tidewater Deeps, Gloomhollow Mere and the Crownrift Pools. "
				.. "Each bites only when its conditions are right: the hour, the season or a festival, your rod, sometimes a bait. "
				.. "Any cast that doesn't raise a sea creature might land one, in Bronze, Silver, Gold or, rarely, Diamond. "
				.. "Fill the ledger and I'll reward you: titles, my old Gillward Hood, even a Glintgill of your own.",options={
				{label="Open the Trophy Ledger",atlas="Trophies"},
				{label="Back",to="hello"},
				{label="Farewell",close=true}}},
		}}
	table.insert(T.RegionFolkOrder, keeper.role)
end
end
-- <<< END Contests & Trophy Angling <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- >>> BEGIN Raids (Raid team; append-only section, §38) >>>
-- The Undertide Vaults: an original party raid for 2-8 players
-- (docs/DEPTH-CONTRACT.md §38). Pure data and pure rules only:
-- raids.server.lua runs the portal lobbies, the instanced vault complex, the
-- room sequence (combat / puzzle / resource / boss), points and settlement;
-- combat.server.lua's Raids section runs the encounters on the Lairs creature
-- machinery (lair-shaped defs: stances, telegraphs, tiles, adds, sigils);
-- server.server.lua's Raids block validates verbs, pays rewards and keeps the
-- Raid Log; raid.client.lua draws the party lobby, the raid HUD and the log.
------------------------------------------------------------------------------
do
local RD = {}
Data.Raids = RD
local LR = Data.Lairs
local CS = Data.CombatStyles
local Rar = Data.Rarity
local function tab(v) return if type(v) == "table" then v else {} end
local function whole(v, cap)
	v = tonumber(v)
	if not v or v ~= v or v < 0 then return 0 end
	v = math.floor(v)
	if cap and v > cap then return cap end
	return v
end
RD.whole = whole

RD.ID = "UndertideVaults"
RD.NAME = "The Undertide Vaults"
RD.COMBAT = 70              -- Combat level to host or join (between the Pyrewarden and Nihlvar)
RD.REGION = "Tidewater"     -- the portal's region gate
RD.ISLE = "Tidewater Shoals"
RD.MIN_PARTY, RD.MAX_PARTY = 2, 8
RD.MAX_RAIDS = 3            -- concurrent raid complexes per server
RD.MAX_LOBBIES = 12
RD.LOBBY_SECONDS = 600      -- an unstarted lobby closes after this long
RD.PORTAL_RANGE = 30        -- studs from the portal to host, join or start
RD.PORTAL_SECONDS = 300     -- a portal visit keeps the lobby board open this long
RD.ROOM_GAP = 6             -- countdown before a room's encounter / puzzle starts
RD.ADVANCE_SECONDS = 6      -- a cleared room moves the party on after this long
RD.EXIT_SECONDS = 15        -- after the Regent falls, members return to the portal
RD.REJOIN_SECONDS = 90      -- a dropped member may rejoin the live raid this long
RD.REJOIN_GRACE = 15        -- a rejoined member's idle clock gets at least this long
RD.REJOIN_VERIFY = 3        -- a rejoin re-applies the room position this long
RD.AWAY_SECONDS = 10        -- outside the complex this long (alive): left the raid
RD.IDLE_SECONDS = 90        -- no movement or credited action this long: removed (no reward)
RD.EMPTY_SECONDS = 90       -- nobody inside this long: the raid ends
RD.RECENT_SECONDS = 90      -- credit: a credited action this recently before the Regent falls
RD.MIN_SHARE = 0.25         -- credit floor: contribution >= 25% of an equal share of the party's (QC M3: room-clear points excluded)
RD.MOVE_STUDS = 3           -- moving this far between samples counts as activity (idle clock)
RD.FLEE_HP, RD.FLEE_SECONDS = 0.25, 3 -- a disconnect below 25% health within 3 s of a hit is a death
RD.PARTY_HP = 0.85          -- extra encounter health per extra member (QC H1: members not offline at the rise, the dead included)
RD.PARTY_DAMAGE = 0.05      -- extra encounter damage per extra member
RD.ARENA_RANGE = LR.ARENA_RANGE
RD.GRID, RD.CELL = LR.GRID, LR.CELL
RD.REWARD_RETRY, RD.REWARD_WINDOW = 5, 120
RD.RUN_MEMORY = 20          -- credited run ids remembered per journal (a repeat is refused)
RD.KEEP_LOG = 12
RD.MAX_KC = 1000000
RD.WARD_MULT = 0.7          -- damage taken while a brewed ward is up (potion)
RD.SUPPLY_COOLDOWN = 4      -- seconds between supplies per member
RD.WARD_REFRESH = 5         -- QC L3: a draught is refused while more than this many seconds of ward remain
RD.MISTAKE_NOTICE = 5       -- QC L3: one party-wide wrong-glyph notice per member per this many seconds
RD.GATHER_COOLDOWN = 1.5    -- seconds between gathers per member
RD.PUZZLE_SECONDS = 240     -- a puzzle not solved by then grinds open (no completion points)
RD.RESOURCE_SECONDS = 210   -- the resource room closes after this long (whatever was made)
RD.RAW_PER_SUPPLY = 2

-- Points (OSRS-raid style, original numbers). Personal points come from
-- damage (a combat room's pool is `combat` x party, split by damage share;
-- the Regent's is `boss` x party), room clears (every member present),
-- puzzle steps (the solver; each step pays once per run), resource work
-- (gather / brew / cook, capped per member) and lose `death` of the total on
-- each death. Challenge Mode multiplies every point by `challenge`.
RD.Points = {combat=3000, boss=6000, clear=500, puzzleStep=250, puzzleMistake=150, gather=40, craft=160, resourceCap=1600,
	death=0.25, challenge=1.2}
RD.POINTS_PER_PERCENT = 4000 -- team points per 1% unique ("purple") chance
RD.UNIQUE_CAP = 0.65
RD.LOOT_POINTS = 2500       -- one regular loot roll per this many personal points
RD.MAX_ROLLS = 12
RD.COINS_PER_POINT = 0.35
RD.Challenge = {hp=1.35, damage=1.3}

-- Encounters ---------------------------------------------------------------
-- Lair-shaped definitions (docs §25) so combat.server.lua's Lairs creature
-- machinery runs them: stances (prayer switching), disc / ring / safe /
-- tiles telegraphs (styleless), adds (a ward: the encounter takes LR.WARD
-- damage while they live) and sigils (ordered, the encounter is immune).
local function attack(kind, name, fields)
	local a = {kind=kind,name=name}
	for k, v in pairs(fields or {}) do a[k] = v end
	return a
end
RD.CombatOrder = {"Gloomfang","Siltmother","Coralglass","Runebound","Undine","Shoalrunner"}
RD.BOSS = "Thalvorn"
RD.Encounters = {
	Gloomfang={name="Gloomfang Sentinel",short="Gloomfang",roomName="Hall of Vigils",level=72,hp=110000,damage=300,defense=200,xp=4400,speed=14,
		color="5FA8D3",body="sentinel",arenaColor="2E4A5C",floor="Slate",weakness="ranged",stances={"melee","magic"},stanceEvery=2,enrage=180,duration=300,
		mechanic="Prayer switching",
		blurb="A vault-sentry that trades fang and glyph every second swing. Keep your Ward in step with it.",
		mechanics={"Stance switch every 2 attacks: Ward of Fangs / Ward of Glyphs","Unsealed (50%): all three styles","Fang Lunge and Watcher's Gaze telegraphs"},
		phases={
			{at=1,name="Watchful",rotation={"fang","gaze"},interval=7},
			{at=0.5,name="Unsealed",stances={"melee","magic","ranged"},rotation={"fang","gaze","fang"},interval=5.5},
		},
		attacks={fang=attack("disc","Fang Lunge",{radius=7,windup=1.8,mult=2.0}),gaze=attack("ring","Watcher's Gaze",{radius=11,windup=2.2,mult=2.0})}},
	Siltmother={name="The Siltmother",short="Siltmother",roomName="Silt Nursery",level=70,hp=100000,damage=280,defense=180,xp=4000,speed=12,
		color="8C7A5B",body="crab",arenaColor="3E3A2E",floor="Sand",weakness="magic",stances={"melee"},stanceEvery=99,enrage=180,duration=300,
		mechanic="Brood ward",
		blurb="A crab-matriarch buried in silt. Her siltlings shield her: clear them, then strike.",
		mechanics={"Brood ward: Siltlings shield her (65% less damage) until slain","Silt Spit and Silt Burst telegraphs"},
		phases={
			{at=1,name="Brooding",rotation={"brood","spit","burst"},interval=7},
			{at=0.5,name="Spawning",rotation={"spit","brood","burst","spit"},interval=5.5},
		},
		attacks={brood=attack("adds","Silt Brood",{add="Siltling",count=4,radius=13}),spit=attack("disc","Silt Spit",{radius=7,windup=1.8,mult=2.0}),
			burst=attack("ring","Silt Burst",{radius=11,windup=2.2,mult=2.2})}},
	Coralglass={name="Coralglass Warden",short="Coralglass",roomName="Coralglass Atrium",level=74,hp=115000,damage=300,defense=210,xp=4600,speed=11,
		color="E58FB0",body="colossus",arenaColor="4A3446",floor="Glass",weakness="melee",stances={"ranged"},stanceEvery=99,enrage=200,duration=300,tiles=true,
		mechanic="Positional lattice",
		blurb="A warden grown from living coral. The atrium floor charges under its song: read the lattice and step clear.",
		mechanics={"Reef Lattice: charged tiles strike after 2.6 s","Coral Shard telegraph on a member","Ranged stance: Ward of Quills"},
		phases={
			{at=1,name="Tidepool",rotation={"lattice","shard"},interval=7.5},
			{at=0.5,name="Riptide",rotation={"lattice","shard","lattice"},interval=6},
		},
		attacks={lattice=attack("tiles","Reef Lattice",{count=10,windup=2.6,mult=2.4}),shard=attack("disc","Coral Shard",{radius=6,windup=1.6,mult=1.8})}},
	Runebound={name="Runebound Colossus",short="Runebound",roomName="Seal Vault",level=75,hp=120000,damage=320,defense=240,xp=4800,speed=10,
		color="C9A54A",body="golem",arenaColor="4A3E22",floor="Basalt",weakness="melee",stances={"magic","ranged"},stanceEvery=3,enrage=200,duration=300,
		mechanic="Ordered seals",
		blurb="A colossus chained by three tide seals. It cannot be harmed until seals I, II and III break, in order.",
		mechanics={"Tide Seals: immune until seals I, II, III fall in order","Stance switch every 3 attacks: Ward of Glyphs / Ward of Quills","Vault Quake and Rune Bolt telegraphs"},
		phases={
			{at=1,name="Bound",rotation={"seals","quake","bolt"},interval=7},
			{at=0.5,name="Unbound",rotation={"quake","seals","bolt","quake"},interval=6},
		},
		attacks={seals=attack("sigils","Tide Seals",{add="TideSeal",count=3,radius=16}),quake=attack("ring","Vault Quake",{radius=12,windup=2.2,mult=2.2}),
			bolt=attack("disc","Rune Bolt",{radius=7,windup=1.7,mult=2.0})}},
	Undine={name="Wailing Undine",short="Undine",roomName="Lament Pool",level=72,hp=105000,damage=290,defense=190,xp=4200,speed=13,
		color="7FD6C8",body="wraith",arenaColor="24403E",floor="Slate",weakness="ranged",stances={"magic"},stanceEvery=99,enrage=180,duration=300,
		mechanic="Safe zone",
		blurb="Her lament floods the pool. When she draws breath, only the calm water beside her is safe.",
		mechanics={"Drowning Lament: only beside her is safe","Wail ring and Brine Spray telegraphs","Magic stance: Ward of Glyphs"},
		phases={
			{at=1,name="Lament",rotation={"lament","wail"},interval=8},
			{at=0.5,name="Dirge",rotation={"lament","wail","lament","spray"},interval=6},
		},
		attacks={lament=attack("safe","Drowning Lament",{radius=9,windup=3.0,mult=2.6}),wail=attack("ring","Wail",{radius=12,windup=2.2,mult=2.2}),
			spray=attack("disc","Brine Spray",{radius=6,windup=1.6,mult=1.8})}},
	Shoalrunner={name="Shoalrunner",short="Shoalrunner",roomName="Shoal Run",level=70,hp=100000,damage=260,defense=170,xp=4000,speed=18,
		color="4F8FBF",body="lurker",arenaColor="1E3448",floor="Slate",weakness="magic",stances={"melee","ranged"},stanceEvery=4,enrage=150,duration=300,
		mechanic="Spread out",
		blurb="A fast hunter that hurls torrents at whoever stands closest together. Spread out, keep moving.",
		mechanics={"Torrent: rapid telegraphs on members (spread out)","Stance switch every 4 attacks","Early enrage (2:30)"},
		phases={
			{at=1,name="Hunting",rotation={"torrent","torrent","surge"},interval=5},
			{at=0.5,name="Frenzy",rotation={"torrent","surge","torrent","torrent"},interval=4},
		},
		attacks={torrent=attack("disc","Torrent",{radius=6,windup=1.5,mult=1.8}),surge=attack("ring","Shoal Surge",{radius=10,windup=2.0,mult=2.0})}},
	Thalvorn={name="Thalvorn, the Undertide Regent",short="Thalvorn",roomName="Drowned Throne",level=90,hp=320000,damage=400,defense=300,xp=12800,speed=13,
		color="3FB8AF",body="serpent",arenaColor="12302E",floor="Slate",weakness="magic",stances={"melee","ranged","magic"},stanceEvery=3,enrage=420,duration=600,
		tiles=true,boss=true,mechanic="Final boss",
		blurb="The Regent of the drowned vaults. Match his stances with your Wards, break his anchors in order, and keep to the calm water when the crown drowns.",
		mechanics={"Stance cycle melee → ranged → magic every 3 attacks (all three Wards)","Undertow (66%): Tide Anchors I–III (ordered, immune) and the Undertow Lattice",
			"Drowning Crown (33%): Drowned Thralls ward him; Maelstrom: only beside him is safe","Weakness turns magic → ranged → melee by phase"},
		phases={
			{at=1,name="Regent's Court",weakness="magic",rotation={"crash","tide","crash"},interval=7},
			{at=0.66,name="Undertow",weakness="ranged",rotation={"anchors","lattice","crash","lattice"},interval=6},
			{at=0.33,name="Drowning Crown",weakness="melee",rotation={"thralls","maelstrom","lattice","crash"},interval=5},
		},
		attacks={crash=attack("disc","Crown Crash",{radius=7,windup=1.7,mult=2.0}),tide=attack("ring","Regal Tide",{radius=12,windup=2.2,mult=2.4}),
			lattice=attack("tiles","Undertow Lattice",{count=12,windup=2.5,mult=2.5}),maelstrom=attack("safe","Maelstrom",{radius=9,windup=3.0,mult=2.8}),
			anchors=attack("sigils","Tide Anchors",{add="TideAnchor",count=3,radius=16}),thralls=attack("adds","Drowned Thralls",{add="DrownedThrall",count=4,radius=13})}},
}
RD.Adds = {
	Siltling={name="Siltling",level=60,hp=6000,damage=120,defense=60,xp=120,speed=15,color="B8A37A",style="melee",body="mite"},
	TideSeal={name="Tide Seal",level=70,hp=20000,damage=0,defense=150,xp=300,speed=0,color="E8C76A",style="magic",body="wisp",stationary=true},
	TideAnchor={name="Tide Anchor",level=88,hp=30000,damage=0,defense=200,xp=450,speed=0,color="6FE3D6",style="magic",body="wisp",stationary=true},
	DrownedThrall={name="Drowned Thrall",level=80,hp=9000,damage=160,defense=80,xp=180,speed=14,color="4A7A78",style="melee",body="lurker"},
}
for id, def in pairs(RD.Encounters) do
	def.id, def.lair, def.raid = id, true, RD.ID
	def.attackStyle = def.stances[1]
	def.weakness, def.defenceStyle = LR.triangle(def.weakness)
	def.coins, def.drops = 0, {}
	for k, a in pairs(def.attacks) do a.id = k end
end
for id, def in pairs(RD.Adds) do
	def.id, def.lair, def.lairAdd, def.raid = id, true, true, RD.ID
	def.attackStyle, def.weakness, def.defenceStyle = def.style, CS.beatenBy[def.style], CS.beats[def.style]
	def.coins, def.drops = 0, {}
end
-- Lair adds resolve raid adds too (combat's lrRegisterAdd / spawnAdds read
-- LR.Adds[id]); pairs(LR.Adds) still sees the lair adds only.
setmetatable(LR.Adds, {__index = RD.Adds})
-- Lookups by id reach raid encounters and adds (damage XP); pairs() never sees them.
do
	local mt = getmetatable(Data.Monsters)
	local prior = mt and mt.__index
	setmetatable(Data.Monsters, {__index = function(t, id)
		local v
		if type(prior) == "function" then v = prior(t, id) elseif type(prior) == "table" then v = prior[id] end
		if v ~= nil then return v end
		return rawget(RD.Encounters, id) or rawget(RD.Adds, id)
	end})
end
function RD.encounter(id) return type(id) == "string" and rawget(RD.Encounters, id) or nil end
-- Scaling by party size (members inside at the encounter's rise) and mode.
function RD.partyHp(def, n, challenge)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY)
	return math.floor(def.hp * (1 + RD.PARTY_HP * (n - 1)) * (if challenge then RD.Challenge.hp else 1))
end
function RD.partyDamage(def, n, challenge)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY)
	return math.floor(def.damage * (1 + RD.PARTY_DAMAGE * (n - 1)) * (if challenge then RD.Challenge.damage else 1))
end
-- A per-fight copy of an encounter with its damage scaled (combat reads
-- def.damage again at enrage, so the scaling must live on the def).
function RD.scaledDef(id, n, challenge)
	local def = RD.encounter(id)
	if not def then return nil end
	local copy = table.clone(def)
	copy.damage = RD.partyDamage(def, n, challenge)
	copy.base = def
	return copy
end

-- Puzzle and resource rooms ----------------------------------------------------
RD.PuzzleOrder = {"Glyphs","Seals","Valves"}
RD.Puzzles = {
	Glyphs={name="Glyph Concord",color="B48CFF",arenaColor="2A2240",
		blurb="Six glyph plates and a lectern that hums a sequence. Press the plates in its order; a wrong glyph restarts the chant.",
		mechanic="Sequence"},
	Seals={name="Weighted Seals",color="E8C76A",arenaColor="3A3220",
		blurb="Lit seals must all be held down at once for a few heartbeats, three times over. Stand together, apart.",
		mechanic="Coordination"},
	Valves={name="Tide Valves",color="6FE3D6",arenaColor="183A3A",
		blurb="Five valves in a ring. Turning one also turns its two neighbours. Open them all to drain the chamber.",
		mechanic="Logic"},
}
RD.GLYPHS = {"Tide","Pearl","Gale","Ember","Star","Moon"}
RD.SEAL_PLATES, RD.SEAL_ROUNDS, RD.SEAL_HOLD, RD.SEAL_RADIUS = 6, 3, 3, 3.2
RD.VALVES = 5
RD.ResourceOrder = {"Grotto","Shallows"}
RD.Resources = {
	Grotto={name="Moonmoss Grotto",color="9FE6A0",arenaColor="1E3A2A",
		blurb="A glowing grotto of moonmoss and gloomcaps. Gather, then brew draughts and cook stew for the Regent's throne room.",
		nodes={
			{id="Moonmoss",name="Moonmoss tuft",verb="Pick",skill="Farming",xp=45,shape="Moonbloom",color="9FE6A0",makes="potion"},
			{id="Gloomcap",name="Gloomcap cluster",verb="Pick",skill="Farming",xp=45,shape="Glowshroom",color="B48CFF",makes="food"},
		},
		stations={
			{id="Cauldron",name="Vault cauldron",verb="Brew",skill="Alchemy",xp=70,shape="Cauldron",makes="potion"},
			{id="Hearth",name="Vault hearth",verb="Cook",skill="Cooking",xp=70,shape="Hearth",makes="food"},
		},
		supplies={potion="Moonmoss Draught",food="Gloomcap Stew"}},
	Shallows={name="Glowfin Shallows",color="7FD6E8",arenaColor="183048",
		blurb="Still, shining shallows. Net glowfin and pull reedroot, then cook broth and brew tonic before the throne room.",
		nodes={
			{id="Glowfin",name="Glowfin shoal",verb="Net",skill="Fishing",xp=50,shape="FishingBuoy",color="7FD6E8",makes="food"},
			{id="Reedroot",name="Reedroot bed",verb="Pull",skill="Farming",xp=45,shape="CropSheaf",color="C9B458",makes="potion"},
		},
		stations={
			{id="Hearth",name="Vault hearth",verb="Cook",skill="Cooking",xp=70,shape="Hearth",makes="food"},
			{id="Cauldron",name="Vault cauldron",verb="Brew",skill="Alchemy",xp=70,shape="Cauldron",makes="potion"},
		},
		supplies={food="Glowfin Broth",potion="Reedroot Tonic"}},
}
RD.NODES_PER_KIND = 3
-- Supplies are a shared team pool used from the raid HUD (verb raidUse):
-- food heals, potions heal a little and raise a ward (damage x RD.WARD_MULT).
RD.Supplies = {food={heal=0.45,label="Food"},potion={heal=0.2,ward=20,label="Draught"}}
function RD.quota(n) return 3 + 2 * math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY) end
function RD.nodeUses(n) return 3 + math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY) end
function RD.glyphLength(n, challenge)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY)
	return 4 + (if n >= 5 then 1 else 0) + (if challenge then 1 else 0)
end
function RD.sealNeed(n) return math.clamp(math.floor(tonumber(n) or 1), 2, 4) end

-- Deterministic generators (seeded per run) ----------------------------------
local function lcg(x) return (x * 48271) % 2147483647 end
local function stream(seed, salt)
	local x = (math.floor(math.abs(tonumber(seed) or 1)) * 7919 + (salt or 0) * 104729) % 2147483646 + 1
	return function(n)
		x = lcg(x)
		return x % n + 1
	end
end
RD.stream = stream
-- Room sequence: two distinct combat rooms, one puzzle, one resource room in a
-- seeded order, then the Regent's throne room.
function RD.sequence(seed)
	local pick = stream(seed, 1)
	local pool = table.clone(RD.CombatOrder)
	local a = table.remove(pool, pick(#pool))
	local b = table.remove(pool, pick(#pool))
	local middle = {{kind="combat",id=a},{kind="combat",id=b},
		{kind="puzzle",id=RD.PuzzleOrder[pick(#RD.PuzzleOrder)]},{kind="resource",id=RD.ResourceOrder[pick(#RD.ResourceOrder)]}}
	for i = #middle, 2, -1 do
		local j = pick(i)
		middle[i], middle[j] = middle[j], middle[i]
	end
	table.insert(middle, {kind="boss",id=RD.BOSS})
	return middle
end
function RD.roomName(room)
	room = tab(room)
	if room.kind == "combat" or room.kind == "boss" then local d = RD.encounter(room.id); return d and d.roomName or "?" end
	if room.kind == "puzzle" then local d = RD.Puzzles[room.id]; return d and d.name or "?" end
	if room.kind == "resource" then local d = RD.Resources[room.id]; return d and d.name or "?" end
	return "?"
end
-- Glyph Concord: n glyph indices (1..#GLYPHS), never the same twice in a row.
function RD.glyphSequence(seed, n)
	local pick = stream(seed, 2)
	local out = {}
	for i = 1, math.clamp(math.floor(tonumber(n) or 4), 1, 12) do
		local g = pick(#RD.GLYPHS)
		if i > 1 and g == out[i - 1] then g = g % #RD.GLYPHS + 1 end
		out[i] = g
	end
	return out
end
-- Weighted Seals: k distinct plates (1..SEAL_PLATES) for a round, sorted.
function RD.sealPattern(seed, round, k)
	local pick = stream(seed, 10 + (tonumber(round) or 1))
	local plates = {}
	for i = 1, RD.SEAL_PLATES do plates[i] = i end
	for i = RD.SEAL_PLATES, 2, -1 do
		local j = pick(i)
		plates[i], plates[j] = plates[j], plates[i]
	end
	local out = {}
	for i = 1, math.clamp(math.floor(tonumber(k) or 2), 1, RD.SEAL_PLATES) do out[i] = plates[i] end
	table.sort(out)
	return out
end
-- Tide Valves: a ring where turning valve i flips i and both neighbours
-- (state[i] = true when open). The start applies 2-3 distinct turns to an
-- all-open ring; with five valves the turn matrix is invertible over GF(2),
-- so the start is never already solved and is always solvable.
function RD.valveToggle(state, i)
	local n = RD.VALVES
	i = math.floor(tonumber(i) or 0)
	if i < 1 or i > n then return state end
	for _, k in ipairs({(i - 2) % n + 1, i, i % n + 1}) do state[k] = not state[k] end
	return state
end
function RD.valveStart(seed)
	local pick = stream(seed, 3)
	local state = {}
	for i = 1, RD.VALVES do state[i] = true end
	local turns = 2 + pick(2) - 1
	local used = {}
	while turns > 0 do
		local i = pick(RD.VALVES)
		if not used[i] then used[i] = true; RD.valveToggle(state, i); turns -= 1 end
	end
	return state
end
function RD.valvesOpen(state)
	local n = 0
	for i = 1, RD.VALVES do if state[i] then n += 1 end end
	return n
end
-- Fewest turns that open every valve (for hints and tests): brute force over 2^5.
function RD.valveSolution(state)
	local best
	for mask = 0, 2 ^ RD.VALVES - 1 do
		local s = table.clone(state)
		local turns = {}
		for i = 1, RD.VALVES do
			if bit32.band(mask, bit32.lshift(1, i - 1)) ~= 0 then RD.valveToggle(s, i); table.insert(turns, i) end
		end
		if RD.valvesOpen(s) == RD.VALVES and (not best or #turns < #best) then best = turns end
	end
	return best
end

-- Points, credit, loot --------------------------------------------------------
function RD.pointMult(challenge) return if challenge then RD.Points.challenge else 1 end
-- A combat room's pool split by damage share (0..1).
function RD.damagePoints(kind, share, n, challenge)
	share = math.clamp(tonumber(share) or 0, 0, 1)
	if share ~= share then share = 0 end
	n = math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY)
	local per = if kind == "boss" then RD.Points.boss else RD.Points.combat
	return math.floor(per * n * share * RD.pointMult(challenge))
end
function RD.deathLoss(points) return math.floor(whole(points) * RD.Points.death) end
-- The most personal points one run can pay (bounds a forged or bugged payload).
function RD.maxPersonal(n, challenge)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, RD.MAX_PARTY)
	local P = RD.Points
	local raw = (2 * P.combat + P.boss) * n + 5 * P.clear + 12 * P.puzzleStep + P.resourceCap
	return math.floor(raw * RD.pointMult(challenge))
end
function RD.uniqueChance(team)
	return math.clamp(whole(team) / (RD.POINTS_PER_PERCENT * 100), 0, RD.UNIQUE_CAP)
end
-- Credit for one member: c = {points, team, party (members being judged),
-- present, removed, lastAction, now, contribution?, teamContribution?}.
-- QC M3: with `contribution` (damage, puzzle and resource points: no flat
-- room-clear points) the floor compares it with an equal share of the
-- judged members' `teamContribution`, so clears plus one hit never qualify.
-- Returns ok, reason.
function RD.credit(c)
	if type(c) ~= "table" then return false, "member" end
	if c.removed then return false, "removed" end
	if c.present ~= true then return false, "away" end
	local points = whole(c.points)
	if points <= 0 then return false, "points" end
	local party = math.clamp(math.floor(tonumber(c.party) or 1), 1, RD.MAX_PARTY)
	local mine, all = points, whole(c.team)
	if c.contribution ~= nil then mine, all = whole(c.contribution), whole(c.teamContribution) end
	if party > 1 and mine < RD.MIN_SHARE * all / party then return false, "share" end
	if not c.lastAction or not c.now or c.now - c.lastAction > RD.RECENT_SECONDS then return false, "idle" end
	return true
end
-- Unique ("purple") recipient: weighted by personal points (r in [0, 1)).
-- entries = {{uid, points}...} in a stable order.
function RD.pickRecipient(entries, r)
	local total = 0
	for _, e in ipairs(entries) do total += whole(e.points) end
	if total <= 0 then return nil end
	local at = math.clamp(tonumber(r) or 0, 0, 0.999999) * total
	for _, e in ipairs(entries) do
		at -= whole(e.points)
		if at < 0 then return e.uid end
	end
	return entries[#entries].uid
end
-- Uniques (each below its endgame rival per the lair rule, docs §25) -----------
local function unique(id, def)
	def.raidUnique, def.logUnique = RD.ID, "Raids"
	return item(id, def)
end
RD.UniqueOrder = {"RegentsPearl","TidewardenVisage","TidewardenCuirass","RegentsTidecleaver","UndertowWarbow","DrownlightScepter","TidewhelpPet"}
-- Weights out of 100 (a unique roll picks one).
RD.UniqueWeights = {RegentsPearl=24,TidewardenVisage=19,TidewardenCuirass=15,RegentsTidecleaver=12,UndertowWarbow=12,DrownlightScepter=12,TidewhelpPet=6}
RD.Rivals = {
	RegentsTidecleaver="Crownbreaker",UndertowWarbow="Duskpiercer",DrownlightScepter="RiftcrownStaff",
	TidewardenVisage="SovereignHelm",TidewardenCuirass="SovereignChestplate",RegentsPearl="NyxwingCharm",
}
RD.UNIQUE_MAX = LR.UNIQUE_MAX
unique("RegentsTidecleaver",{name="Regent's Tidecleaver",kind="weapon",slot="weapon",tier=9,rarity="Legendary",color="3FB8AF",
	stats={damage=300,strength=140,critChance=15,critDamage=92},requires={Combat=62},value=24000,
	special={id="Riptide",name="Riptide",adds=0.35},
	description="Melee. The Undertide Regent's own tide-blade, still dripping. Riptide: +35% damage to a boss's adds, seals and anchors (lair, raid and world boss add waves). Requires Combat 62. Raid unique."})
unique("UndertowWarbow",{name="Undertow Warbow",kind="weapon",slot="weapon",style="ranged",tier=9,rarity="Legendary",color="4F8FBF",
	stats={critDamage=42,rangedAccuracy=76,rangedStrength=17},ranged={power=250,speed=1.0,range=CS.maxRange,maxAmmoTier=7},requires={Ranged=62},value=24000,
	special={id="Undertow",name="Undertow",raid=0.2},
	description="Ranged weapon. Strung with drowned sinew from the vault's deepest hall. Undertow: +20% damage to the Undertide Vaults' guardians and the Regent. "..CS.maxRange.." stud reach. Arrows up to tier 7. Requires Ranged 62. Raid unique."})
unique("DrownlightScepter",{name="Drownlight Scepter",kind="weapon",slot="weapon",style="magic",tier=8,rarity="Legendary",color="7FD6E8",
	stats={intelligence=150,abilityDamage=5},magic={power=160,speed=1.2,elements={"Tide","Gale","Stone"}},requires={Magic=55},value=20000,
	special={id="Drownlight",name="Drownlight",warded=0.2},
	description="Magic weapon. A lamp the Regent kept lit beneath the sea. Drownlight: +20% spell damage to a boss while a ward, brood, seal or add wave shields it. Supplies unlimited Tide, Gale, Stone glyphs. Requires Magic 55. Raid unique."})
-- Lead decision (QC): each raid weapon carries an original special that gives
-- it a niche without lifting it on general content (verify-raid models each
-- against its rival, like Hollow Sunder in verify-bosses):
--   Riptide (Tidecleaver, melee): x(1 + adds) against a boss's adds / seals /
--     anchors (lair, raid, world boss add waves; never slayer superiors).
--   Undertow (Warbow, ranged): x(1 + raid) against raid encounters (not adds).
--   Drownlight (Scepter, magic): x(1 + warded) against a lair / raid / world
--     boss while its adds or seals live.
-- target = {add, boss, raid, warded} (combat.server.lua's L.tideMult builds it
-- from the record). Ordinary monsters and every other weapon: 1.
function RD.tideMult(weaponId, target)
	local def = type(weaponId) == "string" and Data.Items[weaponId]
	local sp = def and def.raidUnique and def.special
	if type(sp) ~= "table" or type(target) ~= "table" then return 1 end
	if target.add == true then return if type(sp.adds) == "number" then 1 + sp.adds else 1 end
	if type(sp.raid) == "number" and target.raid == true then return 1 + sp.raid end
	if type(sp.warded) == "number" and target.boss == true and target.warded == true then return 1 + sp.warded end
	return 1
end
unique("TidewardenVisage",{name="Tidewarden Visage",kind="armor",slot="helmet",tier=8,rarity="Legendary",color="3FB8AF",
	stats={defense=183,health=163,strength=7,critDamage=7},requires={Combat=55},value=16000,
	description="Helm. A drowned warden's coral-crusted visage. Requires Combat 55. Raid unique."})
unique("TidewardenCuirass",{name="Tidewarden Cuirass",kind="armor",slot="chest",tier=8,rarity="Legendary",color="3FB8AF",
	stats={defense=306,health=272,strength=12,critDamage=12},requires={Combat=55},value=26000,
	description="Chestplate. Scale and pearl, forged under the tide. Requires Combat 55. Raid unique."})
unique("RegentsPearl",{name="Regent's Pearl",kind="accessory",rarity="Mythic",color=Rar.Mythic.color,stats={intelligence=48,rangedStrength=16,magicFind=5},
	value=40*Rar.Mythic.rank^2,description="Accessory. Magical Power "..Rar.Mythic.power..". The Regent's crown pearl. Only the Undertide Vaults hold one."})
-- Challenge Mode cosmetic kit (no stats; a trophy and Collection Log entry).
unique("GildedTideKit",{name="Gilded Tide Kit",kind="material",rarity="Mythic",color="FFD86B",value=1,cosmetic=true,
	description="Cosmetic kit. Gilded trim from a Challenge Mode clear of the Undertide Vaults under par. No stats; a trophy for the Raid Log."})
-- Raid pet (Data.Pets species + Pet depth abilities and look).
do
	local PD = Data.PetDepth
	local list = {{name="Tidal Hunger",kind="xp",skills={"Combat"},per=0.15,rarity="Common"},{name="Pearl Sense",kind="stat",stat="magicFind",per=0.05,rarity="Rare"},
		{name="Undertow Shell",kind="stat",stat="defense",per=0.6,rarity="Legendary",level=40}}
	local pet = {id="Tidewhelp",name="Tidewhelp",skill="Combat",rarity="Legendary",color="3FB8AF",perLevel={strength=0.5,health=1,magicFind=0.03}}
	table.insert(Data.Pets, pet)
	Data.PetById.Tidewhelp = pet
	for i, a in ipairs(list) do a.index = i; a.id = a.name:gsub("[^%w]", "") end
	if PD then
		PD.Abilities.Tidewhelp = list
		PD.Looks.Tidewhelp = {form="float",accent="C8FFF6"}
		pet.ability = list[1].name..": up to "..PD.abilityText(list[1], PD.abilityValue(list[1], Data.PET_MAX_LEVEL, PD.MAX_RARITY))
	else
		pet.ability = list[1].name
	end
	pet.abilityNames = {list[1].name, list[2].name, list[3].name}
	unique("TidewhelpPet",{name="Tidewhelp Pet",kind="pet",pet="Tidewhelp",rarity="Legendary",color="3FB8AF",value=200*Rar.Legendary.rank^2,
		description="Summon from your pet menu. Abilities: "..table.concat(pet.abilityNames, ", ")..". The Undertide Vaults' raid pet."})
end
function RD.isUnique(id) local d = if type(id) == "string" then Data.Items[id] else nil; return type(d) == "table" and d.raidUnique ~= nil end
function RD.pickUnique(r)
	local at = math.clamp(tonumber(r) or 0, 0, 0.999999) * 100
	for _, id in ipairs(RD.UniqueOrder) do
		at -= RD.UniqueWeights[id]
		if at < 0 then return id end
	end
	return RD.UniqueOrder[#RD.UniqueOrder]
end
-- Regular loot: one roll per RD.LOOT_POINTS personal points (at most
-- RD.MAX_ROLLS); each roll picks a row by weight. rng() in [0, 1).
RD.Loot = {
	{item="VoidEssence",weight=30,min=3,max=6},{item="CrownShard",weight=30,min=4,max=8},{item="GolemCore",weight=20,min=2,max=4},
	{item="Stormglass",weight=12,min=1,max=3},{item="StarFragment",weight=6,min=1,max=1},{item="SovereignEssence",weight=2,min=1,max=1},
}
function RD.rolls(points) return math.min(RD.MAX_ROLLS, whole(points) // RD.LOOT_POINTS) end
function RD.regularLoot(points, rng)
	local total = 0
	for _, row in ipairs(RD.Loot) do total += row.weight end
	local out = {}
	for _ = 1, RD.rolls(points) do
		local at = math.clamp(tonumber(rng()) or 0, 0, 0.999999) * total
		for _, row in ipairs(RD.Loot) do
			at -= row.weight
			if at < 0 then
				local n = row.min + math.floor(math.clamp(tonumber(rng()) or 0, 0, 0.999999) * (row.max - row.min + 1))
				out[row.item] = (out[row.item] or 0) + n
				break
			end
		end
	end
	return out
end
function RD.rollValue()
	local total, v = 0, 0
	for _, row in ipairs(RD.Loot) do total += row.weight end
	for _, row in ipairs(RD.Loot) do v += row.weight / total * (row.min + row.max) / 2 * (Data.Items[row.item].value or 0) end
	return v
end
function RD.coins(points) return math.floor(whole(points) * RD.COINS_PER_POINT) end

-- Titles (Raid Log): earned once, worn with verb raidTitle.
RD.Titles = {
	{id="Vaultdiver",text="Vaultdiver",hint="Clear the Undertide Vaults.",color="6FE3D6"},
	{id="UndertideChampion",text="Undertide Champion",hint="Clear the Undertide Vaults in Challenge Mode.",color="FFD86B"},
	{id="RegentsBane",text="Regent's Bane",hint="Clear Challenge Mode under par.",color="FF7AD9"},
}
RD.TitleById = {}
for _, t in ipairs(RD.Titles) do RD.TitleById[t.id] = t end

-- Journal: p.raids = {kc, cm, fails, deaths, pb = {[party] = s}, pbCm = {[party] = s},
-- best = {points, team}, got = {[item] = n}, log = {{t, s, n, cm, pts, team, u}}, titles = {[id] = true},
-- title = id | "", runs = {run ids}}.
function RD.migrate(t)
	t = tab(t)
	local out = {kc=whole(t.kc, RD.MAX_KC),cm=whole(t.cm, RD.MAX_KC),fails=whole(t.fails, RD.MAX_KC),deaths=whole(t.deaths, RD.MAX_KC),
		pb={},pbCm={},best={points=whole(tab(t.best).points, 1e7),team=whole(tab(t.best).team, 1e8)},got={},log={},titles={},title="",runs={}}
	for _, key in ipairs({"pb","pbCm"}) do
		for n, s in pairs(tab(t[key])) do
			local party = tonumber(n)
			local secs = whole(s, 86400)
			if party and party % 1 == 0 and party >= RD.MIN_PARTY and party <= RD.MAX_PARTY and secs >= 1 then out[key][tostring(party)] = secs end
		end
	end
	for id, n in pairs(tab(t.got)) do
		local v = RD.isUnique(id) and whole(n, RD.MAX_KC) or 0
		if v > 0 then out.got[id] = v end
	end
	for _, e in ipairs(tab(t.log)) do
		if type(e) == "table" and #out.log < RD.KEEP_LOG then
			table.insert(out.log, {t=whole(e.t, 4e9),s=whole(e.s, 86400),n=math.clamp(whole(e.n), 1, RD.MAX_PARTY),cm=e.cm == true,
				pts=whole(e.pts, 1e7),team=whole(e.team, 1e8),u=if RD.isUnique(e.u) then e.u else nil})
		end
	end
	for id, v in pairs(tab(t.titles)) do if RD.TitleById[id] and v == true then out.titles[id] = true end end
	if type(t.title) == "string" and out.titles[t.title] then out.title = t.title end
	for _, id in ipairs(tab(t.runs)) do
		if type(id) == "string" and #id <= 64 and #out.runs < RD.RUN_MEMORY then table.insert(out.runs, id) end
	end
	return out
end
-- One credited clear. run = {id, seconds, party, points, team, challenge, underPar, unique, now}.
-- Returns {kc, pb, newTitles = {id...}}.
function RD.record(state, run)
	local seconds = math.max(1, whole(run.seconds, 86400))
	local party = math.clamp(whole(run.party), 1, RD.MAX_PARTY)
	local key = tostring(party)
	state.kc = math.min(RD.MAX_KC, state.kc + 1)
	local out = {kc=state.kc,pb=false,newTitles={}}
	local book = if run.challenge then state.pbCm else state.pb
	if run.challenge then state.cm = math.min(RD.MAX_KC, state.cm + 1) end
	if party >= RD.MIN_PARTY and (not book[key] or seconds < book[key]) then book[key] = seconds; out.pb = true end
	state.best.points = math.max(state.best.points, whole(run.points, 1e7))
	state.best.team = math.max(state.best.team, whole(run.team, 1e8))
	if RD.isUnique(run.unique) then state.got[run.unique] = math.min(RD.MAX_KC, (state.got[run.unique] or 0) + 1) end
	if run.kit then state.got.GildedTideKit = math.min(RD.MAX_KC, (state.got.GildedTideKit or 0) + 1) end
	table.insert(state.log, 1, {t=whole(run.now, 4e9),s=seconds,n=party,cm=run.challenge == true,pts=whole(run.points, 1e7),team=whole(run.team, 1e8),
		u=if RD.isUnique(run.unique) then run.unique else nil})
	while #state.log > RD.KEEP_LOG do table.remove(state.log) end
	local function earn(id) if not state.titles[id] then state.titles[id] = true; table.insert(out.newTitles, id) end end
	earn("Vaultdiver")
	if run.challenge then earn("UndertideChampion") end
	if run.challenge and run.underPar then earn("RegentsBane") end
	table.insert(state.runs, 1, run.id)
	while #state.runs > RD.RUN_MEMORY do table.remove(state.runs) end
	return out
end
function RD.seen(state, id)
	for _, v in ipairs(tab(tab(state).runs)) do if v == id then return true end end
	return false
end
function RD.formatTime(seconds) return LR.formatTime(seconds) end
-- Entry check (journal side). info = {combat, region (allowed bool), busy}.
function RD.canJoin(info)
	if type(info) ~= "table" then return false, "invalid" end
	if (tonumber(info.combat) or 0) < RD.COMBAT then return false, "level" end
	if info.region == false then return false, "region" end
	if info.busy then return false, "busy" end
	return true
end

-- Balance model (printed and bounded by verify-raid.luau) ----------------------
-- Per member per hour for a party of n at Combat RD.COMBAT. DPS = the Lairs
-- model (LR.dpsAt: the best open monster's effective health / 8 s) with the
-- weakness used, at MODEL_UPTIME (mechanics, prayer swaps, adds). A combat
-- room = its scaled effective health (plus one wave of adds per phase) /
-- party DPS; the puzzle takes MODEL_PUZZLE s; the resource room the quota's
-- gathers and crafts spread over the party plus MODEL_WALK s; each room adds
-- ROOM_GAP + ADVANCE_SECONDS; a run adds MODEL_OVERHEAD (lobby, portal,
-- return). Coins/h = the raid coin pay + the merchant value of the regular
-- loot; the uniques' value is reported separately (lairs' lead decision).
-- Points assume an equal share and a clean run (no deaths or mistakes).
RD.MODEL_UPTIME, RD.MODEL_PUZZLE, RD.MODEL_WALK, RD.MODEL_OVERHEAD = 0.7, 80, 25, 90
RD.MODEL_STEPS = 5 -- puzzle steps credited in a typical run
function RD.encounterSeconds(id, n, challenge, level)
	local def = RD.encounter(id)
	local dps = LR.dpsAt(level or RD.COMBAT) * (1 + CS.weaknessBonus) * RD.MODEL_UPTIME * n
	local addHp = 0
	for _, a in pairs(def.attacks) do
		if a.kind == "adds" or a.kind == "sigils" then
			local add = RD.Adds[a.add]
			addHp += #def.phases * a.count * add.hp * (1 + add.defense / 100) / 2
		end
	end
	return (RD.partyHp(def, n, challenge) * (1 + def.defense / 100) + addHp) / dps
end
function RD.model(n, opts)
	opts = opts or {}
	n = math.clamp(math.floor(n or 4), 1, RD.MAX_PARTY)
	local cm = opts.challenge == true
	local level = opts.level or RD.COMBAT
	-- Expected combat room time: the average over the pool.
	local combat, xpCombat = 0, 0
	for _, id in ipairs(RD.CombatOrder) do
		combat += RD.encounterSeconds(id, n, cm, level) / #RD.CombatOrder
		local def = RD.encounter(id)
		xpCombat += def.xp * RD.partyHp(def, n, cm) / def.hp / n / #RD.CombatOrder
	end
	local bossDef = RD.encounter(RD.BOSS)
	local boss = RD.encounterSeconds(RD.BOSS, n, cm, level)
	local resource = RD.quota(n) * (RD.RAW_PER_SUPPLY * RD.GATHER_COOLDOWN + 1.5) / n + RD.MODEL_WALK
	local fights = 2 * combat + boss
	local run = fights + RD.MODEL_PUZZLE + resource + 5 * (RD.ROOM_GAP + RD.ADVANCE_SECONDS)
	local seconds = run + RD.MODEL_OVERHEAD
	local runs = 3600 / seconds
	local P = RD.Points
	local quotaShare = RD.quota(n) / n
	local points = math.floor(((2 * P.combat + P.boss) + 5 * P.clear + RD.MODEL_STEPS * P.puzzleStep / n
		+ math.min(P.resourceCap, quotaShare * (P.craft + RD.RAW_PER_SUPPLY * P.gather))) * RD.pointMult(cm))
	local team = points * n
	local coinsRun = RD.coins(points) + RD.rolls(points) * RD.rollValue()
	local xpRun = 2 * xpCombat + bossDef.xp * RD.partyHp(bossDef, n, cm) / bossDef.hp / n
	local uniqueRun = RD.uniqueChance(team) / n
	local uniqueValue = 0
	for _, id in ipairs(RD.UniqueOrder) do uniqueValue += RD.UniqueWeights[id] / 100 * (Data.Items[id].value or 0) end
	local perItemHours = {}
	for _, id in ipairs(RD.UniqueOrder) do perItemHours[id] = 1 / (uniqueRun * RD.UniqueWeights[id] / 100 * runs) end
	return {party=n,challenge=cm,run=run,seconds=seconds,runs=runs,fights=fights,boss=boss,combat=combat,resource=resource,
		points=points,team=team,coins=coinsRun * runs,coinsRun=coinsRun,xp=xpRun * runs,uniqueChance=RD.uniqueChance(team),uniquesPerHour=uniqueRun * runs,
		uniqueValue=uniqueValue * uniqueRun * runs,petHours=perItemHours.TidewhelpPet,perItemHours=perItemHours}
end
-- Challenge Mode par: the modelled clear of the same party size (no lobby overhead).
function RD.par(n) return math.floor(RD.model(n, {challenge=true}).run) end

-- Collection Log: the Raids tab (after Lairs); uniques carry logUnique = "Raids".
local CLog = Data.CommissionsLogs
if CLog and CLog.LogTabs and not CLog.LogTabs.Raids then
	CLog.LogTabs.Raids = {name="Undertide Vaults",title="Vaultbreaker",coins=50000,color="3FB8AF"}
	local at = table.find(CLog.LogTabOrder, "Lairs") or table.find(CLog.LogTabOrder, "Bosses")
	table.insert(CLog.LogTabOrder, if at then at + 1 else #CLog.LogTabOrder + 1, "Raids")
	CLog.LogRoots.Raids = "Raids"
end
-- §31 announcements: a purple drop and a raid title.
local F = Data.Features
if F and F.announceText then
	local announceText = F.announceText
	function F.announceText(e)
		if type(e) == "table" and e.kind == "raidUnique" then
			local d = type(e.item) == "string" and Data.Items[e.item]
			return {head="RAID UNIQUE", body=(d and d.name or tostring(e.item)) .. "  ·  " .. RD.NAME, color="FF7AD9"}
		elseif type(e) == "table" and e.kind == "raidTitle" then
			local t = RD.TitleById[e.title]
			return {head="RAID TITLE", body=t and t.text or tostring(e.title), color=t and t.color or "6FE3D6"}
		end
		return announceText(e)
	end
end
-- §33 goal board: "kills:UndertideVaults:<n>" counts raid clears (p.raids.kc).
local SY = Data.Systems
local GL = SY and SY.Goals
if GL then
	local parse, measure, bossName, bosses, label = GL.parse, GL.measure, GL.bossName, GL.bosses, GL.label
	function GL.label(goal)
		if type(goal) == "table" and goal.k == "kills" and goal.a == RD.ID then return whole(goal.n) .. " " .. RD.NAME .. " clears" end
		return label(goal)
	end
	function GL.parse(spec)
		if type(spec) == "string" and #spec <= 64 then
			local k, a, raw = string.match(spec, "^(%a+):(%w+):(%d+)$")
			if k == "kills" and a == RD.ID then
				local n = tonumber(raw)
				if #raw > 9 or string.match(raw, "^0") or not n or n < 1 then return nil, "Choose a whole target." end
				if n > GL.Kinds.kills.max then return nil, GL.Kinds.kills.name .. " goals go up to " .. GL.Kinds.kills.max .. "." end
				return {k = k, a = a, n = n}
			end
		end
		return parse(spec)
	end
	function GL.measure(p, goal, P)
		if type(goal) == "table" and goal.k == "kills" and goal.a == RD.ID then
			return whole(tab(tab(p).raids).kc), whole(goal.n)
		end
		return measure(p, goal, P)
	end
	function GL.bossName(id)
		if id == RD.ID then return RD.NAME end
		return bossName(id)
	end
	function GL.bosses()
		local out = bosses()
		table.insert(out, 1, RD.ID)
		return out
	end
end
end
-- <<< END Raids <<<
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- >>> QoL Depth (§41) >>>
-- QoL Depth team: the Lumen Lectern (daily Enchanting memory trials), the
-- Wardrobe (saved armour + accessory loadouts), Roost tethers (pet XP sharing
-- with a preview), the Roost keeper as Hub folk, and Vault Charters (bank
-- tiers with a capped daily interest). Data.QoL = Q. Pure rules only; the
-- "QoL Depth" block in server.server.lua owns state. All names original.
------------------------------------------------------------------------------
do
local Q = {}
Data.QoL = Q
Q.DAY = 86400
-- UTC day index; daily records only roll forward (a server whose clock is
-- behind never re-opens a day it already counted).
function Q.dayOf(t) return math.floor((tonumber(t) or 0) / Q.DAY) end
local function whole(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
	v = math.floor(v)
	if lo and v < lo then return nil end
	if hi and v > hi then return nil end
	return v
end
Q.whole = whole

------------------------------------------------------------------------------
-- Lumen Lectern: three memory trials, six tiers gated by Enchanting level.
-- The server generates every puzzle and checks every answer; a snapshot only
-- carries what the lectern is showing right now.
------------------------------------------------------------------------------
local A = {}
Q.Lectern = A
A.NAME = "Lumen Lectern"
A.SKILL = "Enchanting"
A.VISIT_SECONDS = 600 -- a trial starts within 10 minutes of touching the lectern
A.ANSWER_SECONDS = 90 -- per round, after the reveal ends
A.PAIRS_SECONDS = 600 -- a Mirror Pairs board stays open this long
A.BONUS_CAP = 6 -- bonus reveals banked per day
A.GLYPHS = {
	{id="Sun",mark="☼",color="FFD166"},{id="Moon",mark="☾",color="BFD7FF"},{id="Star",mark="✦",color="FFF3B0"},
	{id="Rune",mark="❖",color="C77DFF"},{id="Leaf",mark="✿",color="8CE99A"},{id="Wave",mark="≈",color="66D9E8"},
	{id="Flame",mark="✸",color="FF8A3D"},{id="Gem",mark="◆",color="F783AC"},{id="Eye",mark="◉",color="E9ECEF"},
}
A.Games = {
	seq={id="seq",name="Glyph Sequence",attempts=2,text="The lectern lights glyphs in order, one more each round. Repeat the whole sequence."},
	recall={id="recall",name="Starfall Recall",attempts=2,text="Numbered stars fall onto the grid and fade. Touch their cells in order, 1 first."},
	pairs={id="pairs",name="Mirror Pairs",attempts=1,text="Hidden glyph pairs hold rewards. Each reveal costs one light; a matched pair pays out."},
}
A.GameOrder = {"seq","recall","pairs"}
-- xp: Enchanting XP for round 1 (later rounds pay more); dust: Arcane Dust per dust card;
-- tome / masterwork: chance a Mirror Pairs board hides a Tempering / Masterwork Tome.
A.Tiers = {
	{id="Apprentice",level=1,color="A9B4C0",glyphs=4,seqRounds=6,grid={3,3},recallStart=3,recallRounds=5,pairs=4,xp=12,dust=4},
	{id="Adept",level=15,color="8CE99A",glyphs=5,seqRounds=8,grid={4,3},recallStart=3,recallRounds=6,pairs=5,xp=35,dust=8},
	{id="Scholar",level=30,color="66D9E8",glyphs=6,seqRounds=10,grid={4,4},recallStart=4,recallRounds=7,pairs=6,xp=100,dust=16},
	{id="Savant",level=50,color="C77DFF",glyphs=7,seqRounds=12,grid={5,4},recallStart=4,recallRounds=8,pairs=7,xp=400,dust=28,tome=0.6},
	{id="Magister",level=70,color="F783AC",glyphs=8,seqRounds=14,grid={5,5},recallStart=5,recallRounds=9,pairs=8,xp=900,dust=40,tome=1},
	{id="Luminary",level=85,color="FFD166",glyphs=9,seqRounds=15,grid={5,5},recallStart=5,recallRounds=10,pairs=9,xp=1600,dust=56,tome=1,masterwork=0.25},
}
for i, t in ipairs(A.Tiers) do t.index = i; t.cells = t.grid[1] * t.grid[2] end
function A.tier(i) i = whole(i, 1, #A.Tiers) return if i then A.Tiers[i] else nil end
function A.bestTier(level)
	local best = 1
	for i, t in ipairs(A.Tiers) do if (tonumber(level) or 1) >= t.level then best = i end end
	return best
end
-- Enchanting XP for clearing round r of a tier (+20 % per round after the first).
function A.roundXp(t, r) return math.floor(t.xp * (1 + 0.2 * (math.max(1, r) - 1)) + 0.5) end
function A.rounds(t, game) return if game == "seq" then t.seqRounds elseif game == "recall" then t.recallRounds else 0 end
-- Bonus reveals for today's Mirror Pairs: seq 1 per 3 rounds, recall 1 per 2, +1 for a perfect run.
function A.bonusFor(game, cleared, t)
	cleared = math.max(0, math.floor(tonumber(cleared) or 0))
	local b = if game == "seq" then cleared // 3 elseif game == "recall" then cleared // 2 else 0
	if t and cleared > 0 and cleared >= A.rounds(t, game) then b += 1 end
	return b
end
function A.recallCount(t, r) return math.min(t.cells, t.recallStart + r - 1) end
-- How long (s) the client shows a round before it fades.
function A.revealSeconds(game, n) return if game == "seq" then 1 + 0.7 * n else 2 + 0.45 * n end
-- Generators: rng() returns [0, 1).
local function pick(rng, n) return math.clamp(math.floor(rng() * n) + 1, 1, n) end
function A.makeSequence(t, rng)
	local s = {}
	for i = 1, t.seqRounds do s[i] = pick(rng, t.glyphs) end
	return s
end
-- n distinct cells (1..t.cells); position k holds star number k.
function A.makeRecall(t, r, rng)
	local pool = {}
	for c = 1, t.cells do pool[c] = c end
	local out = {}
	for _ = 1, A.recallCount(t, r) do table.insert(out, table.remove(pool, pick(rng, #pool))) end
	return out
end
A.CELL_CHARS = "123456789abcdefghijklmnop" -- cell index <-> one character (<= 25 cells)
function A.cellChar(c) return string.sub(A.CELL_CHARS, c, c) end
function A.charCell(ch) return (string.find(A.CELL_CHARS, ch, 1, true)) end
-- Answers: seq "1324" (glyph indices), recall "3a7" (cell characters in order).
function A.checkSequence(seq, r, answer)
	if type(answer) ~= "string" or #answer ~= r or not string.match(answer, "^[1-9]+$") then return false end
	for i = 1, r do if tonumber(string.sub(answer, i, i)) ~= seq[i] then return false end end
	return true
end
function A.checkRecall(cells, answer)
	if type(answer) ~= "string" or #answer ~= #cells then return false end
	for i = 1, #cells do if A.charCell(string.sub(answer, i, i)) ~= cells[i] then return false end end
	return true
end
-- Mirror Pairs: 2 x pairs cards {g = glyph, p = pair}; rewards[pair] =
-- {k = "xp"|"item"|"reveal", id, n}. One reveal card per board; tomes by chance.
function A.makeBoard(t, rng)
	local rewards = {}
	if t.masterwork and rng() < t.masterwork then table.insert(rewards, {k="item",id="MasterworkTome",n=1}) end
	if t.tome and rng() < t.tome then table.insert(rewards, {k="item",id="TemperingTome",n=1}) end
	table.insert(rewards, {k="reveal",n=2})
	local i = 0
	while #rewards < t.pairs do
		i += 1
		if i % 2 == 1 then table.insert(rewards, {k="xp",n=t.xp * 4}) else table.insert(rewards, {k="item",id="ArcaneDust",n=t.dust}) end
	end
	-- QC M1: the glyph -> reward link is drawn per board (server RNG): rewards
	-- are shuffled over the pairs and each pair gets a random distinct glyph, so
	-- no glyph always hides the reveal card, a tome or a reward kind.
	for k = #rewards, 2, -1 do local j = pick(rng, k); rewards[k], rewards[j] = rewards[j], rewards[k] end
	local glyphs = {}
	for g = 1, #A.GLYPHS do glyphs[g] = g end
	for k = #glyphs, 2, -1 do local j = pick(rng, k); glyphs[k], glyphs[j] = glyphs[j], glyphs[k] end
	local cards = {}
	for p = 1, t.pairs do
		local glyph = glyphs[p]
		table.insert(cards, {g=glyph,p=p})
		table.insert(cards, {g=glyph,p=p})
	end
	for k = #cards, 2, -1 do local j = pick(rng, k); cards[k], cards[j] = cards[j], cards[k] end
	return cards, rewards
end
function A.baseReveals(t) return 2 * t.pairs + 2 end
function A.reveals(t, bonus) return A.baseReveals(t) + math.clamp(math.floor(tonumber(bonus) or 0), 0, math.min(A.BONUS_CAP, t.pairs)) end
-- Daily ceiling of Enchanting XP (every round cleared, every XP card matched).
function A.dailyMaxXp(t)
	local total = 0
	for _, g in ipairs({"seq","recall"}) do
		local per = 0
		for r = 1, A.rounds(t, g) do per += A.roundXp(t, r) end
		total += per * A.Games[g].attempts
	end
	return total + t.xp * 4 * t.pairs * A.Games.pairs.attempts
end
-- p.lectern = {day, used = {[game] = n}, bonus, best = {[game] = rounds}, runs, s = session | nil}
function A.roll(rec, day)
	if (tonumber(rec.day) or -1) < day then
		rec.day, rec.used, rec.bonus = day, {}, 0
		return true
	end
	return false
end
function A.left(rec, game) return math.max(0, A.Games[game].attempts - (tonumber(rec.used and rec.used[game]) or 0)) end

------------------------------------------------------------------------------
-- Wardrobe: saved armour + accessory loadouts (never the weapon). A set holds
-- item ids only; the items stay in the satchel, so nothing is duplicated.
------------------------------------------------------------------------------
local W = {}
Q.Wardrobe = W
W.MAX = 9
W.SLOTS = {"helmet","chest","legs","boots"}
W.UNLOCKS = {15,30,45} -- Combat levels that add two slots each (3 -> 9)
W.COOLDOWN = 3 -- seconds between swaps
W.HURT_GRACE = 8 -- no swap within this many seconds of taking damage
W.MAX_ACC = 64
function W.slotsFor(combatLevel)
	local n = 3
	for _, lv in ipairs(W.UNLOCKS) do if (tonumber(combatLevel) or 1) >= lv then n += 2 end end
	return math.min(W.MAX, n)
end
function W.capture(equipment, bag)
	local set = {acc={}}
	for _, s in ipairs(W.SLOTS) do set[s] = type(equipment) == "table" and equipment[s] or nil end
	for _, id in ipairs(type(bag) == "table" and bag or {}) do if #set.acc < W.MAX_ACC then table.insert(set.acc, id) end end
	return set
end
function W.empty(set)
	if type(set) ~= "table" then return true end
	for _, s in ipairs(W.SLOTS) do if set[s] then return false end end
	return type(set.acc) ~= "table" or #set.acc == 0
end
-- Sanitise a saved set (unknown items dropped, accessories unique, bounded); nil when empty.
function W.clean(set)
	if type(set) ~= "table" then return nil end
	local out = {acc={}}
	for _, s in ipairs(W.SLOTS) do
		local id = set[s]
		local def = type(id) == "string" and Data.Items[id]
		if def and def.slot == s then out[s] = id end
	end
	local seen = {}
	for _, id in ipairs(type(set.acc) == "table" and set.acc or {}) do
		local def = type(id) == "string" and Data.Items[id]
		if def and def.kind == "accessory" and not seen[id] and #out.acc < W.MAX_ACC then seen[id] = true; table.insert(out.acc, id) end
	end
	if W.empty(out) then return nil end
	return out
end
-- Pure check that `set` can be worn: owned, right slot, requirements, bag room.
-- meets(requires) -> ok, missing. Returns ok, reason.
function W.check(set, items, accessorySlots, meets)
	if type(set) ~= "table" then return false, "That wardrobe slot is empty." end
	for _, s in ipairs(W.SLOTS) do
		local id = set[s]
		if id then
			local def = Data.Items[id]
			if not def or def.slot ~= s then return false, "That loadout holds a piece that no longer fits." end
			if (items[id] or 0) < 1 then return false, "You no longer own " .. def.name .. "." end
			local ok, missing = meets(def.requires)
			if not ok then return false, def.name .. " requires " .. tostring(missing) .. "." end
		end
	end
	local seen = {}
	for _, id in ipairs(set.acc or {}) do
		local def = Data.Items[id]
		if not def or def.kind ~= "accessory" then return false, "That loadout holds an unknown accessory." end
		if seen[id] then return false, "That loadout lists " .. def.name .. " twice." end
		seen[id] = true
		if (items[id] or 0) < 1 then return false, "You no longer own " .. def.name .. "." end
	end
	if #(set.acc or {}) > accessorySlots then return false, "That loadout needs " .. #set.acc .. " accessory slots (you have " .. accessorySlots .. ")." end
	return true
end

------------------------------------------------------------------------------
-- Vault Charters: bank tiers. Interest is paid once per UTC day, on the vault
-- balance up to the charter's insured capacity; nothing builds up while you
-- are away, so a charter never pays more than its daily ceiling.
------------------------------------------------------------------------------
local V = {}
Q.Vault = V
V.Tiers = {
	{id="Strongbox",name="Strongbox Charter",rate=0.001,cap=100000},
	{id="Coffer",name="Coffer Charter",rate=0.0015,cap=500000,cost=25000,needs={Ore=3,Timber=3}},
	{id="Ledger",name="Ledger Charter",rate=0.002,cap=2000000,cost=250000,needs={Ore=5,Timber=5,Fish=4,Herb=4}},
	{id="Gilded",name="Gilded Charter",rate=0.0025,cap=8000000,cost=2000000,needs={SunsteelOre=5,EmberoakLog=5,Stormeel=4,ArcaneDust=5}},
	{id="Treasury",name="Sky Treasury Charter",rate=0.003,cap=25000000,cost=10000000,needs={StarmetalOre=6,StarwoodLog=6,AbyssKoi=5,VoidEssence=6}},
}
for i, t in ipairs(V.Tiers) do t.index = i end
function V.tier(i) return V.Tiers[math.clamp(whole(i) or 1, 1, #V.Tiers)] end
function V.maxDaily(t) return math.floor(t.cap * t.rate) end
function V.interest(t, bank)
	bank = tonumber(bank) or 0
	if bank ~= bank then bank = 0 end
	return math.floor(math.clamp(bank, 0, t.cap) * t.rate)
end
-- p.vault = {tier, day, paid, last, low}. Returns the coins due today (0 unless
-- the day is new). `bank` is the lowest vault balance since the last payment
-- (QC L5: p.vault.low), so a deposit made just before the UTC day earns nothing.
function V.roll(rec, day, bank)
	local seen = tonumber(rec.day)
	if seen and seen >= day then return 0 end
	rec.day = day
	if not seen then return 0 end -- a new charter starts counting tomorrow
	return V.interest(V.tier(rec.tier), bank)
end

------------------------------------------------------------------------------
-- Roost tethers: roster pets that share the summoned pet's pet XP.
------------------------------------------------------------------------------
local K = {}
Q.Tether = K
K.SHARE = 0.1 -- each tethered pet earns 10 % of the pet XP the summoned pet earns
K.UNLOCKS = {10,25,50} -- Taming levels for tether slots 1, 2, 3
function K.slotsFor(tamingLevel)
	local n = 0
	for _, lv in ipairs(K.UNLOCKS) do if (tonumber(tamingLevel) or 1) >= lv then n += 1 end end
	return n
end
-- Preview: pet XP your summoned pet must earn for a tethered pet to gain `need`.
function K.activeXpFor(need) return math.ceil(math.max(0, tonumber(need) or 0) / K.SHARE) end

------------------------------------------------------------------------------
-- The Roost keeper (Wren Halloway, already named by Data.PetDepth.KEEPER) as
-- Hub folk, and the atlas stations Roost (Hero › Pets) and Lectern.
------------------------------------------------------------------------------
do
	local T, RA = Data.Townsfolk, Data.RegionArt
	Q.ROOST_KEEPER = "RoostKeeper"
	if T and RA and RA.Folk and T.NPCs and not RA.FolkByRole[Q.ROOST_KEEPER] then
		local keeper = {role=Q.ROOST_KEEPER,region="Hub",name="Wren Halloway",title="Roost Keeper",portrait="🪺",kind="roost",
			look={skin="E0AC69",shirt="7FA35B",pants="4A3B2A",shoes="2E241A",accent="FFD6A5",hair="8B5A2B",hat="cap",held="lantern",apron="5C7A3A"},
			greet="Every pet on the isles passes my perches sooner or later. Leave one with me for a while and it comes home grander."}
		table.insert(RA.Folk, keeper)
		RA.FolkByRole[keeper.role] = keeper
		if T.AtlasStations then
			T.AtlasStations.Roost = "Hero · Pets"
			T.AtlasStations.Lectern = "Hero · Lectern"
		end
		T.NPCs[keeper.role] = {name=keeper.name,title=keeper.title,region="Hub",portrait=keeper.portrait,look=keeper.look,start="hello",anchorOnly=true,folk="roost",
			nodes={
				hello={text=keeper.greet,options={
					{label="Show me the Roost",atlas="Roost"},
					{label="How do upgrades work?",to="upgrade"},
					{label="Tell me about tethers",to="tether"},
					{label="Farewell",close=true}}},
				upgrade={text="Bring coins and your pet's own trade goods. I raise one pet a rarity at a time: an hour for Uncommon, three days for Legendary. "
					.."Come and go as you please; the perch keeps time while you are away. Claim it in Hero › Pets.",options={
					{label="Show me the Roost",atlas="Roost"},{label="Back",to="hello"},{label="Farewell",close=true}}},
				tether={text="A tethered pet learns from the one at your side: it earns a tenth of every bit of pet XP your summoned pet earns. "
					.."Taming 10 opens your first tether, 25 the second and 50 the third.",options={
					{label="Show me the Roost",atlas="Roost"},{label="Back",to="hello"},{label="Farewell",close=true}}},
			}}
		table.insert(T.RegionFolkOrder, keeper.role)
	end
end
end
-- <<< END QoL Depth <<<
------------------------------------------------------------------------------

-- >>> Gathering Feel (§42): struck nodes >>>
-- Gathering nodes are hit, not held: a left click swings the held tool and the
-- server applies one validated strike (`strike` verb, server.server.lua). Pure
-- rules only (no instances): HP per tier, damage per strike, the swing cadence,
-- the regrowth hand-back that keeps XP / hour level with the old hold prompt,
-- and the fishing cast / bite / reel timings. Shared by the server, the client
-- (overhead bars, hitsplats, label) and the suites.
do
	local ST = {}
	Data.Strike = ST
	-- Seconds between strikes the server accepts (one swing of the §26 gesture).
	ST.SWING = {Mining = 0.7, Woodcutting = 0.7, Farming = 0.6}
	-- Client: the strike is sent at the gesture's impact frame (seconds after the click).
	ST.IMPACT = {Mining = 0.42, Woodcutting = 0.4, Farming = 0.36}
	-- The retired hold prompts (GATHER_HOLD 1 s, FISH_HOLD 1.5 s): the per-harvest
	-- active time the regrowth hand-back is measured against.
	ST.OLD_HOLD = {Mining = 1, Woodcutting = 1, Farming = 1, Fishing = 1.5}
	-- Nominal strikes to break a node with the tier's entry tool, by tier index.
	ST.SWINGS = {3, 3, 4, 4, 5, 5, 6, 6}
	ST.TOLERANCE = 0.12 -- s of network jitter forgiven per strike (never accumulates)
	ST.REACH, ST.FISH_REACH = 10, 14 -- studs from the node's edge (root to node centre minus half its footprint)
	ST.DECAY_AFTER, ST.DECAY_RATE = 4, 0.25 -- abandoned progress heals 25% of max HP a second after 4 s
	ST.REGROW_FLOOR = 1
	ST.LEVEL_BONUS_CAP = 50 -- +1% damage per level over the node's requirement, up to +50%
	ST.SPEED_DIVISOR = 200 -- Mining Speed (and tool Efficiency) scales damage: x(1 + speed / 200)
	ST.MAX_TRACKED = 6 -- nodes with partial progress kept per player
	-- Fishing: a click casts; the fish bites after `bite` s; a click inside the
	-- window reels it in. Too early loses the cast; a missed bite slips away.
	ST.FISH = {gap = 0.8, biteMin = 1.0, biteMax = 2.0, window = 1.2, early = 0.15, late = 0.35, reaction = 0.3}
	ST.VERB = {Mining = "Mine", Woodcutting = "Chop", Fishing = "Fish", Farming = "Harvest"}
	-- The entry resource a special strike node (raid rooms) swings as, per skill.
	ST.ENTRY = {Mining = "Ore", Woodcutting = "Timber", Fishing = "Fish", Farming = "Herb"}
	ST.NOUN = {Mining = "Vein", Woodcutting = "Tree", Fishing = "Spot", Farming = "Patch"}
	ST.GESTURE = {Mining = "mine", Woodcutting = "chop", Fishing = "fish", Farming = "harvest"}
	function ST.resource(id)
		local skill = type(id) == "string" and Data.ResourceSkill[id]
		if not skill then return nil end
		for _, r in ipairs(Data.ResourceTiers[skill]) do if r.id == id then return r end end
		return nil
	end
	function ST.power(toolTier) return 10 + 10 * math.max(0, math.floor(tonumber(toolTier) or 0)) end
	-- The Mining Speed an entry tool of tier t brings (generated pickaxes carry 40 x tier).
	function ST.entrySpeed(r)
		return if r.skill == "Mining" and (r.tool or 0) > 0 then 40 * r.tool else 0
	end
	-- Damage of one strike. speed: Mining Speed for Mining (stats + tool + Efficiency),
	-- tool Efficiency for the others; level: the player's skill level.
	function ST.damage(r, toolTier, speed, level)
		local over = math.clamp((tonumber(level) or 1) - (r.level or 1), 0, ST.LEVEL_BONUS_CAP)
		local base = ST.power(toolTier) * (1 + math.max(0, tonumber(speed) or 0) / ST.SPEED_DIVISOR)
		return math.max(1, math.floor(base * (1 + over / 100)))
	end
	-- Node HP: the nominal strikes x the entry tool's damage at the requirement.
	function ST.maxHp(r)
		if not r or r.skill == "Fishing" then return 0 end
		return (ST.SWINGS[r.index] or 6) * ST.damage(r, r.tool or 0, ST.entrySpeed(r), r.level)
	end
	function ST.strikesFor(r, damage)
		local hp = ST.maxHp(r)
		return if hp > 0 then math.ceil(hp / math.max(1, damage)) else 2
	end
	-- Seconds from the first strike to the break at the nominal damage (the
	-- first strike lands at once; the rest one swing apart). Fishing: the mean
	-- bite plus a reaction.
	function ST.nominalBreak(r)
		if r.skill == "Fishing" then return (ST.FISH.biteMin + ST.FISH.biteMax) / 2 + ST.FISH.reaction end
		return ((ST.SWINGS[r.index] or 6) - 1) * ST.SWING[r.skill]
	end
	-- Regrowth after a break (QC M5): the time the break actually took (first
	-- strike / cast to the break, `elapsed`; the nominal break when omitted) is
	-- handed back against the old hold, so a node's cycle (break + regrowth) is
	-- the old hold + regrowth whatever the tool: a one-shot waits base + hold,
	-- never less, and per-node XP / hour never beats the old prompt. Faster
	-- tools pay off across several nodes (less active time per harvest).
	-- Floored at REGROW_FLOOR.
	function ST.regrowth(r, base, elapsed)
		base = tonumber(base) or tonumber(r.respawn) or 3
		elapsed = math.max(0, tonumber(elapsed) or ST.nominalBreak(r))
		return math.max(ST.REGROW_FLOOR, base + (ST.OLD_HOLD[r.skill] or 1) - elapsed)
	end
	-- Progress left after idling: healed DECAY_RATE x max a second after DECAY_AFTER s.
	function ST.decayed(hp, maxHp, idle)
		idle = (tonumber(idle) or 0) - ST.DECAY_AFTER
		if idle <= 0 then return hp end
		return math.min(maxHp, hp + idle * ST.DECAY_RATE * maxHp)
	end
	-- A deterministic bite delay (no shared RNG draw): a hash of the user and the cast count.
	function ST.biteDelay(userId, n)
		local h = ((math.floor(tonumber(userId) or 0) % 100003) * 7919 + (math.floor(tonumber(n) or 0) % 100003) * 104729) % 1000
		return ST.FISH.biteMin + (ST.FISH.biteMax - ST.FISH.biteMin) * h / 999
	end
	-- Waypoint index of struck node hosts (QC M3; nav.client.lua "gather:<id>"):
	-- {[resource id] = {positions}} from AetherNode-tagged hosts, skipping
	-- nodes owned by another player. `into` (optional) is filled in place.
	function ST.indexNodes(hosts, userId, into)
		local out = into or {}
		for _, host in ipairs(type(hosts) == "table" and hosts or {}) do
			local ok, id, owner, at = pcall(function() return host:GetAttribute("GatherNode"), host:GetAttribute("OwnerUserId"), host.Position end)
			local special = ok and host:GetAttribute("StrikeKind") ~= nil -- crew stores, garden plots, raid rooms
			if ok and not special and type(id) == "string" and ST.resource(id) and (owner == nil or owner == userId) and typeof(at) == "Vector3" then
				out[id] = out[id] or {}
				table.insert(out[id], at)
			end
		end
		return out
	end
	-- "Copperstone Ore" -> "Copperstone Vein"; "Windpine Log" -> "Windpine Tree".
	function ST.nodeName(r)
		local name = tostring(r.name or r.id)
		local noun = ST.NOUN[r.skill] or "Node"
		local stem = name:gsub(" Ore$", ""):gsub(" Log$", ""):gsub(" Timber$", "")
		return stem .. " " .. noun
	end
	-- "Mine Copperstone Vein (Mining 1)"
	function ST.label(r)
		return ST.VERB[r.skill] .. " " .. ST.nodeName(r) .. " (" .. r.skill .. " " .. r.level .. ")"
	end
	-- Old vs new node cycle (s) and XP / hour at the nominal tool, for the docs and tests.
	function ST.balance(r)
		local oldCycle = (ST.OLD_HOLD[r.skill] or 1) + r.respawn
		local newCycle = ST.nominalBreak(r) + ST.regrowth(r, r.respawn)
		return {hp = ST.maxHp(r), strikes = if r.skill == "Fishing" then 2 else (ST.SWINGS[r.index] or 6), breakTime = ST.nominalBreak(r),
			regrowth = ST.regrowth(r, r.respawn), oldCycle = oldCycle, newCycle = newCycle,
			oldXpHour = math.floor(r.xp * 3600 / oldCycle), newXpHour = math.floor(r.xp * 3600 / newCycle)}
	end
end
-- <<< END Gathering Feel <<<
------------------------------------------------------------------------------
-- >>> BEGIN Tutorial (Tutorial team; append-only section; docs/DEPTH-CONTRACT.md §43) >>>
-- Coach cards on top of the Wayfarer's Path (§31) and the first starter
-- quests (guild contracts 1-2, Charting the Skyway, Lamps of the Quay, read
-- through the §33 quest helper). Pure data + pure rules shared by the server
-- "Tutorial" block in server.server.lua (state, the `tutorial` verb, the
-- current card) and tutorial.client.lua (cards, pointer ring, tips).
-- * The current card is DERIVED from server progress (Path step flags, quest
--   acceptance / completion): the first unfinished chapter wins. Buttons never
--   advance a step card; "Got it" only collapses it (seen).
-- * Intro / finale cards (ack = true) are the only ones a button finishes.
-- * Tips fire once per account on a first encounter (client-detected from
--   server signals; the server records each id once, verb "tip:<id>").
------------------------------------------------------------------------------
do
local TU = {}
Data.Tutorial = TU
local function tab(v) return if type(v) == "table" then v else {} end
local function num(v) return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0 end
local function whole(v) v = num(v); return if v > 0 then math.floor(v) else 0 end
TU.whole = whole
TU.VERSION = 1
TU.NAME = "Tutorial"
TU.CONTRACTS = 2 -- the first two guild contracts form the first starter quest
TU.SATCHEL_PAGE = 21 -- distinct stacks that fill the satchel's first page (7 x 3 grid)
-- Pointer targets (tutorial.client.lua resolves them to on-screen GuiObjects,
-- most specific first; the first one visible wins):
--   objective  sidebar Objective line      satchel  sidebar Bag button
--   menu       sidebar Menu button         chart    sidebar Map (Sky Chart) button
--   hotbar:N   hotbar slot N (1 weapon, 2 context tool)
--   orbs       status orbs (Health)        clock    sidebar clock line
--   any other  a GuiObject of that name in the atlas (MenuQuests, SectionHelper…)
local Path = Data.Features.Guide
TU.Cards = {
	{id="welcome", chapter="intro", ack=true, title="Welcome to the Aether Isles",
		body="These coach cards walk you through your first steps: the Wayfarer's Path, then your first quests. Your sidebar Objective always shows what to do next.",
		pointer={"objective"}},
	{id="path:mode", step="mode", title="Choose your journal mode",
		body="Travel to Compass Quay and talk to Pell Ashgrove (the gold ! over his head). Keep a Standard journal in one tap, or read about Ironman first: seal it before you gather.",
		pointer={"objective"}},
	{id="path:chop", step="chop", title="Chop a log",
		body="Left-click a tree to chop it with your axe (tap it on mobile). Each swing chips its health bar; when it breaks, the logs land in your satchel.",
		pointer={"hotbar:2"}},
	{id="path:craft", step="craft", title="Craft at a workbench",
		body="Open a Workbench, Forge, Hearth or Cauldron (or Menu › Recipes) and craft anything: planks, a pickaxe, a meal.",
		pointer={"MenuRecipes", "menu"}},
	{id="path:visit", step="visit", title="Visit Compass Quay",
		body="Compass Quay is the shared hub. Open the Sky Chart (M, or the Map button) and travel there, or step through your home isle's portal.",
		pointer={"chart"}},
	{id="path:talk", step="talk", title="Talk to Pell",
		body="Find Pell Ashgrove on Compass Quay and ask him about the Wayfarer's Path. Follow the glowing beacon.",
		pointer={"objective"}},
	{id="path:ore", step="ore", title="Gather ore",
		body="Left-click an ore rock to mine it with your pickaxe (tap it on mobile). Keep swinging until its health bar breaks.",
		pointer={"hotbar:2"}},
	{id="path:sell", step="sell", title="Sell an item",
		body="Open your satchel (E, or the Bag button), right-click an item (long-press on mobile) and choose Sell.",
		pointer={"satchel"}},
	{id="path:equip", step="equip", title="Equip a weapon",
		body="Open your satchel, right-click a weapon and choose Wield. Hotbar slot 1 always holds your weapon.",
		pointer={"satchel", "hotbar:1"}},
	{id="path:kill", step="kill", title="Defeat a creature",
		body="Brambleback Boars roam Sunwheel Downs. Left-click a creature to attack it with your weapon (tap on mobile) and keep an eye on your Health orb.",
		pointer={"hotbar:1"}},
	{id="path:quest", step="quest", title="Accept a quest",
		body="Accept a regional quest from a questgiver with a gold ! over their head, or complete your first guild contract. Pin it in Menu › Quests › Helper to see its next step.",
		pointer={"SectionHelper", "MenuQuests", "menu"}},
	{id="path:warp", step="warp", title="Learn a warp",
		body="Buy a warp scroll from Ilsabet the Warp Keeper and read it. Then open the Sky Chart (M) to warp straight to that isle.",
		pointer={"chart"}},
	{id="quest:contract", chapter="quests", quest="contract", title="Your first guild contracts",
		body="Guild contracts are your starter quest line. Pin it in Journal › Helper, follow its NEXT step, then claim it in Journal › Bearing.",
		pointer={"SectionBearing", "SectionHelper", "MenuQuests", "menu"}},
	{id="quest:SkywayCharter", chapter="quests", quest="SkywayCharter", title="Charting the Skyway",
		body="Ilsabet the Warp Keeper has your first regional quest. Accept it from her, then follow the quest helper.",
		pointer={"SectionHelper", "MenuQuests", "menu"}},
	{id="quest:LampsOfTheQuay", chapter="quests", quest="LampsOfTheQuay", title="Lamps of the Quay",
		body="Corwin the Lamplighter needs timber and ore before the Quay goes dark. Accept, gather, then hand it in to him.",
		pointer={"SectionHelper", "MenuQuests", "menu"}},
	{id="complete", chapter="finale", ack=true, title="You're ready, wayfarer!",
		body="You walked the Wayfarer's Path and finished your first quests. Train any skill, raise your Isle Renown and explore the isles.",
		pointer={"menu"}},
}
TU.CardById = {}
for i, c in ipairs(TU.Cards) do
	c.index = i
	c.chapter = c.chapter or "path"
	TU.CardById[c.id] = c
end
-- Chapters for the progress dot row (dots count the cards of the card's chapter).
TU.Chapters = {intro = "WELCOME", path = string.upper(Path.NAME), quests = "FIRST QUESTS", finale = "TUTORIAL COMPLETE"}
function TU.dots(id)
	local card = TU.CardById[id]
	if not card then return {index = 0, total = 0, chapter = ""} end
	local index, total = 0, 0
	for _, c in ipairs(TU.Cards) do
		if c.chapter == card.chapter then
			total += 1
			if c.index <= card.index then index += 1 end
		end
	end
	return {index = index, total = total, chapter = TU.Chapters[card.chapter] or ""}
end
-- Waypoint specs for a step card (Path waypoints); quest cards use the helper step's specs.
function TU.specsFor(id)
	local card = TU.CardById[id]
	if card and card.step then return Path.Waypoints[card.step] end
	return nil
end

-- Tips (first encounters; once per account) --------------------------------
TU.Tips = {
	{id="fight", title="Your first fight",
		body="Keep left-clicking (or tapping) the creature to swing. Your Health orb sits beside the minimap; eat food from your hotbar if it runs low.",
		pointer={"orbs"}},
	{id="levelup", title="Level up!",
		body="Every skill level pays coins and unlocks better tools, recipes and places. Menu › Skills shows what each level opens.",
		pointer={"MenuSkills", "menu"}},
	{id="satchelFull", title="Your satchel's first page is full",
		body="Use the page arrows, Sort or Search in your satchel. Sell spare stacks to a merchant, or bank them with Odile in Compass Quay.",
		pointer={"satchel"}},
	{id="night", title="Night falls on the isles",
		body="The sidebar clock shows the isle hour. Lamps light the hubs after dusk; nothing resets at night, so carry on.",
		pointer={"clock"}},
	{id="shop", title="Your first shop",
		body="Prices show before you pay. Right-click (long-press) an offer to buy several at once; some wares restock daily.",
		pointer={}},
	{id="questAccept", title="Quest accepted",
		body="Pin it in Journal › Helper: its next step shows in your sidebar Objective, and Waypoint lights the way.",
		pointer={"objective"}},
}
TU.TipById = {}
for i, t in ipairs(TU.Tips) do t.index = i; TU.TipById[t.id] = t end

-- Saved state ---------------------------------------------------------------
-- p.tutorial = {v, seen = {[card] = true}, tips = {[tip] = true}, card, skipped,
-- off (tips off), vet (a veteran never offered the tutorial), done (finale seen)}
function TU.sanitize(t)
	t = tab(t)
	local out = {v = TU.VERSION, seen = {}, tips = {}}
	for id, v in pairs(tab(t.seen)) do if v == true and TU.CardById[id] then out.seen[id] = true end end
	for id, v in pairs(tab(t.tips)) do if v == true and TU.TipById[id] then out.tips[id] = true end end
	out.card = if type(t.card) == "string" and TU.CardById[t.card] then t.card else nil
	out.skipped = t.skipped == true or nil
	out.off = t.off == true or nil
	out.vet = t.vet == true or nil
	out.done = t.done == true or nil
	return out
end
-- The card the player is on, from real progress (nil: skipped, veteran or finished).
-- p: the profile (guide, questCompleted, questsDone); t: sanitised state.
function TU.current(p, t)
	p, t = tab(p), tab(t)
	if t.skipped or t.vet or t.done then return nil end
	if not tab(t.seen).welcome then return "welcome" end
	local guide = tab(p.guide)
	if guide.complete ~= true then
		local view = Path.view(guide)
		if view.id and TU.CardById["path:" .. view.id] then return "path:" .. view.id end
	end
	if whole(p.questCompleted) < TU.CONTRACTS then return "quest:contract" end
	local done = tab(p.questsDone)
	for _, c in ipairs(TU.Cards) do
		if c.quest and c.quest ~= "contract" and done[c.quest] ~= true then return c.id end
	end
	return "complete"
end
-- Verb argument: "next:<card>" | "dismiss:<card>" | "skip" | "replay" | "tip:<id>" |
-- "tips:on" | "tips:off". Returns (action, arg) or nil.
function TU.parse(item)
	if type(item) ~= "string" or #item > 40 then return nil end
	if item == "skip" or item == "replay" then return item, nil end
	if item == "tips:on" or item == "tips:off" then return "tips", item == "tips:on" end
	local kind, arg = string.match(item, "^(%a+):([%w:]+)$")
	if (kind == "next" or kind == "dismiss") and TU.CardById[arg] then return kind, arg end
	if kind == "tip" and TU.TipById[arg] then return kind, arg end
	return nil
end
-- Rewards summary for the finale card (static data; coins owed come from the
-- snapshot): one short line per source so it fits the card.
-- pathCoins: the Path coins this journal earned (paid to date + still owed, from
-- p.guide.paid / owed); nil (no paid-to-date record) reads "up to <MAX_OWED>".
function TU.rewardSummary(pathCoins)
	local earned = if type(pathCoins) == "number" then whole(pathCoins) .. " coins" else "up to " .. Path.MAX_OWED .. " coins"
	local lines = {Path.NAME .. ": " .. earned}
	for _, c in ipairs(TU.Cards) do
		if c.quest and c.quest ~= "contract" then
			local q = Data.QuestById[c.quest]
			local r = tab(q and q.rewards)
			local parts = {}
			if whole(r.coins) > 0 then table.insert(parts, whole(r.coins) .. " coins") end
			local ids = {}
			for id in pairs(tab(r.items)) do table.insert(ids, id) end
			table.sort(ids)
			for _, id in ipairs(ids) do
				local def = Data.Items[id]
				table.insert(parts, (if whole(r.items[id]) > 1 then whole(r.items[id]) .. "× " else "") .. (if def then def.name else tostring(id)))
			end
			if type(r.lamp) == "table" then table.insert(parts, "an XP lamp") end
			table.insert(lines, (q and q.title or c.title) .. ": " .. table.concat(parts, ", "))
		end
	end
	return lines
end

-- Tip triggers (pure; tutorial.client.lua runs them on every snapshot) -------
-- prev / snap: consecutive snapshots (prev nil on the first); ctx = {night,
-- fight, shop} booleans the client observed from server signals since the last
-- check. Returns the tip ids whose first encounter happened.
local function distinct(items)
	local n = 0
	for _, v in pairs(tab(items)) do if num(v) > 0 then n += 1 end end
	return n
end
local function acceptedCount(s)
	local n = 0
	for _, v in pairs(tab(tab(tab(s).regionQuests).accepted)) do if v == true then n += 1 end end
	return n
end
function TU.detectTips(prev, snap, ctx)
	snap, ctx = tab(snap), tab(ctx)
	local out = {}
	if ctx.fight then table.insert(out, "fight") end
	-- A skill level-up: the §31 SKILL LEVEL UP announcement in the recent ring.
	for _, e in ipairs(tab(tab(snap.announce).list)) do
		if tab(e).kind == "skill" then table.insert(out, "levelup"); break end
	end
	if distinct(snap.items) >= TU.SATCHEL_PAGE then table.insert(out, "satchelFull") end
	if ctx.night then table.insert(out, "night") end
	if ctx.shop then table.insert(out, "shop") end
	if prev ~= nil and acceptedCount(snap) > acceptedCount(prev) then table.insert(out, "questAccept") end
	return out
end
end
-- <<< END Tutorial <<<
------------------------------------------------------------------------------

return Data
