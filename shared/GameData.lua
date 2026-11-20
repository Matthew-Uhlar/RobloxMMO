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
	{id="Hub",name="Aether Hub",requires={},description="The shared hub: bank, market and guild."},
	{id="Meadow",name="Meadow Reach",requires={},description="Gentle hills. Brambleback boars and Thornlings roam.",monsters={"BramblebackBoar","Thornling"}},
	{id="Quarry",name="Quarry Cay",requires={},description="Copperstone and Aetherite seams.",monsters={"ShaleCrawler","CinderMite"}},
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
	{region="Meadow",name="Meadow Reach Diary",tiers={
		Easy={tasks={k("BramblebackBoar",5),c("Herb",50),c("Timber",50),l("Farming",5)},perk={health=10}},
		Medium={tasks={k("Thornling",25),c("Sunwheat",100),cr("MightDraught",5),l("Farming",20)},perk={farmingFortune=10}},
		Hard={tasks={k("BramblebackBoar",250),c("Glowcap",250),s("Bramble",3),l("Farming",40)},perk={farmingFortune=15,health=15}},
		Elite={tasks={c("AetherLotus",500),k("Thornling",500),s("Bramble",6),l("Farming",75)},perk={farmingFortune=25,health=25}},
	}},
	{region="Quarry",name="Quarry Cay Diary",tiers={
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
Data.TERRACE_OFFSET = {x=-33,z=0}
Data.Hotspots = {
	{id="Bench",name="Workshop Bench",x=-27,z=5.2},
	{id="Hearth",name="Kitchen Hearth",x=-33,z=7.4},
	{id="Storage",name="Storage Nook",x=-39,z=5.2},
	{id="Trophy",name="Trophy Alcove",x=-39,z=-5.2},
	{id="Garden",name="Garden Plot",x=-33,z=-7.4},
	{id="Dock",name="Surveyor Dock",x=-27,z=-5.2},
	{id="Portal",name="Portal Circle",x=-36,z=0},
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
function Data.describeCheck(o)
	local function nameOf(id) local def = Data.Items[id]; return def and def.name or tostring(id) end
	local kind = type(o) == "table" and o.kind
	if kind == "contracts" then return "Claim "..o.count.." guild contracts"
	elseif kind == "quest" then local qd = Data.QuestById[o.quest]; return "Complete "..(qd and qd.title or tostring(o.quest))
	elseif kind == "questPoints" then return o.count.." Quest Points"
	elseif kind == "level" then return o.skill.." level "..o.level
	elseif kind == "collect" then return "Collect "..o.count.." "..nameOf(o.item).." (lifetime)"
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
	Island.RANGE = 8
	Island.RADIUS = 18.5
	Island.BRUSH = 0.3       -- a cell may brush a protected rectangle by this many studs
	Island.MAX_PLACEMENTS = 120   -- the grid holds 124 free cells
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
		{name="homestead sign",x1=-10,z1=13.5,x2=0,z2=14.5},
		{name="lantern spot",x1=-13,z1=-9,x2=-11,z2=-7},
		{name="lantern spot",x1=11,z1=-8,x2=13,z2=-6},
		{name="lantern spot",x1=-14,z1=5,x2=-12,z2=7},
		{name="lantern spot",x1=5,z1=11,x2=7,z2=13},
		{name="garden plot",x1=-14,z1=-2.5,x2=-8,z2=4.5},
		{name="lookout bridge",x1=-4,z1=16,x2=4,z2=20},
		{name="terrace bridge",x1=-20,z1=-4,x2=-16,z2=4},
		{name="terrace sign",x1=-15.5,z1=-10,x2=-14.5,z2=-2},
	}
	Island.Props = {
		-- Fences
		TimberFence={name="Timber Fence",category="Fences",level=1,xp=12,costs={Timber=4},size={1,1},max=40,value=1,color="966B4C",text="A rail of meadow timber."},
		PicketFence={name="Picket Fence",category="Fences",level=8,xp=24,costs={Timber=6,Ore=2},size={1,1},max=40,value=2,color="F9EDCD",text="Painted pickets with copper nails."},
		BrassRailing={name="Brass Railing",category="Fences",level=25,xp=70,costs={WindpineLog=3,BrassIngot=1},size={1,1},max=30,value=4,color="DBAD65",text="Polished brass on windpine posts."},
		-- Paths
		StonePath={name="Stone Path",category="Paths",level=1,xp=8,costs={Ore=3},size={1,1},max=60,value=1,color="687481",text="Flagstones for a tidy walk."},
		Boardwalk={name="Boardwalk",category="Paths",level=5,xp=12,costs={Timber=4},size={1,1},max=60,value=1,color="A0784F",text="Timber planks over the meadow."},
		AetherMosaic={name="Aether Mosaic",category="Paths",level=30,xp=60,costs={Aetherite=6,Ore=4},size={1,1},max=40,value=3,color="7FD6E8",text="Glowing inlaid tiles."},
		-- Lights (utility: lamp glow)
		LanternPost={name="Lantern Post",category="Lights",level=3,xp=20,costs={Timber=3,Ore=2},size={1,1},max=20,value=3,color="8EE6CB",effect={light={color="8EE6CB",range=9}},text="Lights the island at dusk."},
		BrassStreetlamp={name="Brass Streetlamp",category="Lights",level=20,xp=90,costs={WindpineLog=2,BrassIngot=2},size={1,1},max=16,value=6,color="F9CC77",effect={light={color="FFD58A",range=12}},text="A tall lamp with a warm glow."},
		CrystalBrazier={name="Crystal Brazier",category="Lights",level=40,xp=260,costs={Aetherite=12,EmberoakLog=4},size={1,1},max=10,value=12,color="C77DFF",effect={light={color="C77DFF",range=14}},text="Aetherite flames in an ember bowl."},
		-- Garden
		FlowerPlanter={name="Flower Planter",category="Garden",level=2,xp=14,costs={Timber=3,Herb=5},size={1,1},max=30,value=2,color="D67D6A",text="A box of meadow blooms."},
		HedgeRow={name="Hedge Row",category="Garden",level=10,xp=40,costs={Herb=10,Timber=2},size={2,1},max=30,value=3,color="5E8C55",text="A clipped hedge two cells long."},
		YoungWindpine={name="Young Windpine",category="Garden",level=12,xp=50,costs={Timber=8,Herb=6},size={1,1},max=15,value=4,color="6B8E5A",text="A sapling for shade (not a gathering node)."},
		MoonbloomBed={name="Moonbloom Bed",category="Garden",level=45,xp=420,costs={Moonbloom=12,GlimmerbarkLog=4},size={2,2},max=10,value=15,color="B8C0FF",text="A raised bed of night flowers."},
		-- Banners
		GuildBanner={name="Guild Banner",category="Banners",level=6,xp=20,costs={Timber=4,Herb=2},size={1,1},max=20,value=3,color="3C9291",text="The Cartographers' Guild colours."},
		VoyagerPennant={name="Voyager Pennant",category="Banners",level=28,xp=110,costs={WindpineLog=3,BeastHide=4},size={1,1},max=12,value=6,color="D67D6A",text="A hide pennant for far voyages."},
		StormStandard={name="Storm Standard",category="Banners",level=55,xp=900,costs={StarwoodLog=4,Stormglass=1},size={1,1},max=4,value=30,color="7B8CDE",text="Crackling stormglass on a starwood pole."},
		-- Statues
		SurveyorStatue={name="Surveyor Statue",category="Statues",level=15,xp=120,costs={Ore=30,Brassite=8},size={2,2},max=4,value=12,color="B8B2A6",text="A stone surveyor on a plinth."},
		SkywhaleStatue={name="Skywhale Statue",category="Statues",level=50,xp=1100,costs={Aetherite=30,GolemCore=2},size={2,2},max=2,value=40,color="7FD6E8",text="A crystal whale breaching the clouds."},
		AetherObelisk={name="Aether Obelisk",category="Statues",level=65,xp=2200,costs={StarmetalIngot=6,Aetherite=40},size={1,1},max=3,value=50,color="C9D6E3",effect={light={color="8EE6CB",range=16}},text="A starmetal spire humming with aether."},
		-- Structures
		PicnicBench={name="Picnic Bench",category="Structures",level=4,xp=24,costs={Timber=8},size={2,1},max=10,value=3,color="9C6B3E",text="Seats for visiting voyagers."},
		StoneWell={name="Stone Well",category="Structures",level=12,xp=80,costs={Ore=25,Timber=5},size={2,2},max=2,value=8,color="6F7A86",text="A covered well with a brass bucket."},
		SupplyShed={name="Supply Shed",category="Structures",level=18,xp=150,costs={Timber=40,Ore=10},size={2,2},max=3,value=10,color="8A5A3B",text="A small shed with a pitched roof."},
		GardenGazebo={name="Garden Gazebo",category="Structures",level=22,xp=300,costs={WindpineLog=30,BrassIngot=4},size={3,3},max=2,value=25,color="F9EDCD",text="An open pavilion with a brass crown."},
		-- Utility: home crafting prompts reuse the existing station effect.
		CarpenterStump={name="Carpenter's Stump",category="Utility",level=8,xp=40,costs={Timber=20},size={1,1},max=1,value=4,color="7A5634",effect={station="Workbench"},text="Home Workbench station."},
		CampStove={name="Camp Stove",category="Utility",level=10,xp=50,costs={Ore=15,Timber=10},size={1,1},max=1,value=5,color="B5651D",effect={station="Hearth",light={color="FFB36B",range=8}},text="Home Hearth station."},
		FieldAnvil={name="Field Anvil",category="Utility",level=20,xp=120,costs={Ore=20,BrassIngot=3},size={1,1},max=1,value=6,color="485565",effect={station="Forge"},text="Home Forge station."},
		BrewingStand={name="Brewing Stand",category="Utility",level=30,xp=240,costs={Herb=30,EmberoakLog=6},size={1,1},max=1,value=8,color="6A4C93",effect={station="Cauldron"},text="Home Cauldron station."},
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
	-- nil when buildable, else a short reason: "edge" or a protected zone name.
	function Island.cellBlocked(x, z)
		if not int(x) or not int(z) or math.abs(x) > Island.RANGE or math.abs(z) > Island.RANGE then return "edge" end
		local half = Island.CELL / 2
		local cx, cz = x * Island.CELL, z * Island.CELL
		local fx, fz = math.abs(cx) + half, math.abs(cz) + half
		if fx * fx + fz * fz > Island.RADIUS * Island.RADIUS then return "edge" end
		for _, r in ipairs(Island.Protected) do
			local e = half - Island.BRUSH
			if cx + e > r.x1 and cx - e < r.x2 and cz + e > r.z1 and cz - e < r.z2 then return r.name end
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
	-- Geometry check: true, or false + a player-facing reason.
	function Island.check(occupied, propId, x, z, rot)
		local def = type(propId) == "string" and Island.Props[propId]
		if not def then return false, "Choose a prop from the island catalogue." end
		local cells = Island.cells(propId, x, z, rot)
		if not cells then return false, "That spot is not on the island grid." end
		for _, c in ipairs(cells) do
			local blocked = Island.cellBlocked(c[1], c[2])
			if blocked == "edge" then return false, def.name .. " must sit fully on your island." end
			if blocked then return false, "Keep the " .. blocked .. " clear." end
			if occupied and occupied[Island.key(c[1], c[2])] then return false, "Something already stands there." end
		end
		return true
	end
	function Island.value(list)
		local total = 0
		for _, e in ipairs(list) do
			local def = Island.Props[e.prop]
			if def then total += def.value end
		end
		return total
	end
end

------------------------------------------------------------------------------
-- Townsfolk (Guide team; append-only section). NPCs, dialogue graphs, the
-- new-player tutorial, contextual tips and waypoint rules. Consumed by
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
T.RecallTargets = {Hub="the Aether Hub",Home="your Wayfarer's Rest"}
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
------------------------------------------------------------------------------
T.Tutorial = {
	{id="gather",title="Gather supplies",
		text="Mine 6 Copperstone Ore in Quarry Cay and cut 3 Meadow Timber. Walk up to a node and hold the prompt.",
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
	if type(target) ~= "string" or not T.RecallTargets[target] then return false, "Choose Hub or Home to recall to." end
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
			tutorial={tutorial=true,text="Six steps and you'll be a proper islander. Here's where you stand:",options={
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
				{label="Recall me to the Hub",verb="recall",item="Hub"},
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
item("HubwardTablet",{name="Hubward Tablet",kind="material",category="tablet",combatUse=true,rarity="Uncommon",color="F9CC77",value=20,description="Break to teleport to the Aether Hub (spell Hubward). Not while in combat."})
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
function Data.describeCheck(o)
	local kind = type(o) == "table" and o.kind
	if kind == "laps" then
		local course = AG.CourseById[o.course]
		return "Run "..o.count.." "..(if o.count == 1 then "lap" else "laps").." of the "..(course and course.name or tostring(o.course))
	elseif kind == "catches" then
		local creature = HU.CreatureById[o.creature]
		return "Catch "..o.count.." "..(creature and creature.name or tostring(o.creature))
	end
	return describe(o)
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
	for _, layer in ipairs({out.reforgeStats, out.starStats, out.tomeStats}) do
		for stat, v in pairs(layer) do total[stat] = round1((total[stat] or 0) + v) end
	end
	out.total = total
	return out
end
function Gear.upgradeStats(g, itemId) return Gear.breakdown(g, itemId).total end
function Gear.isUpgraded(g, itemId)
	local book = Gear.bookOf(g, itemId)
	return Gear.reforgeOf(g, itemId) ~= nil or Gear.starsOf(g, itemId) > 0 or book.tempering > 0 or book.masterwork
end
-- "Honed Brass Sword ★★★"
function Gear.displayName(g, itemId)
	local def = Data.Items[itemId]
	local name = def and def.name or tostring(itemId)
	local reforge = Gear.reforgeOf(g, itemId)
	if reforge then name = Gear.Reforges[reforge].name.." "..name end
	local stars = Gear.starsOf(g, itemId)
	if stars > 0 then name ..= " "..string.rep("★", stars) end
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
	local tuning = s.stage == "prisms" or (core and s.shielded == true)
	if kind == "ability" then
		local readyAt = tonumber(s.readyAt) or 0
		if now < readyAt then return false, d.ability.name .. " recharging • " .. math.ceil(readyAt - now) .. "s." end
		local id = d.ability.id
		if id == "Bulwark" and not core then return false, d.ability.name .. " needs the boss phase." end
		if id == "Cleave" and not (core and ((tonumber(s.wisps) or 0) > 0 or (not s.shielded and not s.warded))) then return false, "Nothing in reach of " .. d.ability.name .. "." end
		if id == "DisruptingShot" and not (core and s.telegraph) then return false, d.ability.name .. " needs a telegraphing boss." end
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
-- plus Bonus (3 per class feat + 5 for a balanced team, cap 20), clamped to 300.
DC.FEAT_BONUS, DC.BONUS_CAP = 3, 20
function DC.bonusScore(feats, balanced)
	feats = math.max(0, math.floor(tonumber(feats) or 0))
	return math.min(DC.BONUS_CAP, feats * DC.FEAT_BONUS + (if balanced then 5 else 0))
end
-- master: Master Mode runs are timed against DC.par (par x DC.MASTER_PAR).
function DC.score(floorIndex, seconds, deaths, mistakes, found, total, bonus, master)
	local scale = if master == true and (tonumber(floorIndex) or 0) <= DC.MASTER_FLOORS then DC.MASTER_PAR else 1
	local _, parts = Data.dungeonScore(floorIndex, (tonumber(seconds) or 0) / scale, deaths, mistakes)
	total = math.max(0, math.floor(tonumber(total) or 0))
	found = math.clamp(math.floor(tonumber(found) or 0), 0, total)
	local secrets = if total > 0 then found * 100 / total else 100
	bonus = math.clamp(math.floor(tonumber(bonus) or 0), 0, DC.BONUS_CAP)
	local base = (parts.speed + parts.survival + parts.skill + secrets) * 0.75
	local score = math.clamp(math.floor(base + bonus + 0.5), 0, 300)
	return score, {speed=parts.speed,survival=parts.survival,skill=parts.skill,secrets=secrets,bonus=bonus}
end

-- Master Mode (floors I-V): x2 HP and damage, par x1.6, one extra chest roll,
-- x2.2 XP and coins (a Master clear takes ~2x as long, so it must pay >= normal per hour).
-- Unlocked per floor by an S+ normal-mode clear (best score >= the S+ minimum).
DC.MASTER_FLOORS = 5
DC.MASTER_MULT, DC.MASTER_XP, DC.MASTER_ROLLS, DC.MASTER_PAR = 2, 2.2, 1, 1.6
-- Par time (seconds) of a floor; Master Mode runs get x1.6.
function DC.par(floorIndex, master)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	return f.par * (if master == true and f.index <= DC.MASTER_FLOORS then DC.MASTER_PAR else 1)
end
function DC.masterUnlocked(floorIndex, bestScore)
	return type(floorIndex) == "number" and floorIndex >= 1 and floorIndex <= DC.MASTER_FLOORS
		and (tonumber(bestScore) or 0) >= Data.DungeonGradeById["S+"].min
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
	local mult = f.hpMult * (if master == true and f.index <= DC.MASTER_FLOORS then DC.MASTER_MULT else 1)
	return math.ceil(wave.hp * math.sqrt(mult) - 1e-9)
end
function DC.floorStats(floorIndex, master)
	local s = Data.dungeonFloorStats(floorIndex)
	s.bossDamageMult = 1
	master = master == true and floorIndex <= DC.MASTER_FLOORS
	if master then
		local m = DC.MASTER_MULT
		s.guardianHp, s.coreHp, s.guardianHit = s.guardianHp * m, s.coreHp * m, s.guardianHit * m
		s.bossDamageMult = m
	end
	s.addHp = DC.wispHp(floorIndex, master)
	s.par = DC.par(floorIndex, master)
	return s
end

-- Class XP for one credited clear (the selected class only).
function DC.classXp(floorIndex, grade, master, teamMult)
	local f = Data.DungeonFloors[floorIndex] or Data.DungeonFloors[1]
	local g = Data.DungeonGradeById[grade] or Data.DungeonGradeById.B
	local team = math.clamp(tonumber(teamMult) or 1, 1, 1 + DC.TEAM_STEP * (#DC.order - 1))
	return math.floor(f.rewards.dungeoneeringXp * 0.75 * g.mult * (if master then DC.MASTER_XP else 1) * team)
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
		r.dungeoneeringXp = math.floor(r.dungeoneeringXp * DC.MASTER_XP)
		r.combatXp = math.floor(r.combatXp * DC.MASTER_XP)
		r.coins = math.floor(r.coins * DC.MASTER_XP)
	end
	r.coins += math.floor(r.coins * 0.05 * found)
	r.items.ObservatoryEssence += found
	r.rolls = 1 + (if master then DC.MASTER_ROLLS else 0)
	r.classXp = if DC.valid(opts.class) then DC.classXp(floorIndex, grade, master, opts.teamMult) else 0
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
function Data.describeCheck(o)
	local kind = type(o) == "table" and o.kind
	if kind == "offerings" then
		local r = o.remains and PR.RemainsById[o.remains]
		return "Offer "..o.count.." "..(if r then r.name else "remains").." at an altar"
	elseif kind == "thefts" then
		local t = TH.TargetById[o.target]
		local verb = t and TH.Kinds[t.kind].verb or "Rob"
		return verb.." the "..(t and t.name or tostring(o.target)).." "..o.count.." "..(if o.count == 1 then "time" else "times")
	end
	return describe(o)
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
ST.Superiors, ST.SuperiorOf, ST.SuperiorOrder = {}, {}, {}
for _, f in ipairs(ST.Families) do
	if not f.sea then
		for _, baseId in ipairs(f.monsters) do
			local base = Data.Monsters[baseId]
			local id = "Superior"..baseId
			local drops = {{item="EclipsedIchor",chance=1,min=1,max=3},{item="SlayerToken",chance=1,min=1,max=2},{item="DuskhunterSigil",chance=1/40,min=1,max=1}}
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
function ST.rollSuperior(unlocked, monsterId, roll)
	if not unlocked then return nil end
	local id = ST.SuperiorOf[monsterId]
	if not id or type(roll) ~= "function" then return nil end
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

return Data
