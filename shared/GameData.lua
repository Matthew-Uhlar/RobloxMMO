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
HU.TICK = 3               -- seconds between trap rolls
HU.MAX_TICKS = 40         -- an unsprung trap collapses after this many rolls
HU.DISMANTLE_WINDOW = 4   -- trigger a set trap twice within this many seconds to pick it up
HU.MAX_TRAPS = 5
HU.NET_MISS_COOLDOWN = 2  -- seconds before the same swarm can be netted again after a miss
HU.LogTiers = {10,25,50,100,250,500,1000}
HU.LogBonus = {trapLuck=0.5,huntingFortune=1}
function HU.maxTraps(level) return math.min(HU.MAX_TRAPS, 1 + (level or 1) // 20) end
-- Per-roll (traps) or per-swing (nets) catch chance in 0..1.
function HU.catchChance(creature, level, trapLuck)
	local c = creature.base + ((level or 1) - creature.level) * 0.012
	c = math.clamp(c, creature.base * 0.5, 0.85)
	c *= 1 + math.clamp(trapLuck or 0, 0, 100) / 100
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
-- swarm cooldown per player.
HU.Creatures = {
	{id="PuffcapHopper",name="Puffcap Hopper",method="snare",level=1,region="Meadow",xp=24,base=0.3,color="E8DCC8",
		drops={{item="DownyPelt",chance=1,min=1,max=1},{item="HopperHaunch",chance=0.8,min=1,max=1},{item="PuffkinPet",chance=0.002,min=1,max=1}}},
	{id="SunwingMoth",name="Sunwing Moth",method="net",level=9,region="Meadow",xp=36,base=0.55,respawn=5,color="F7D774",
		drops={{item="SunwingDust",chance=1,min=1,max=2},{item="DriftPlume",chance=0.3,min=1,max=3}}},
	{id="PinecrestGrouse",name="Pinecrest Grouse",method="bird",level=18,region="Windpine",xp=70,base=0.26,color="B08A5A",
		drops={{item="GrouseQuill",chance=1,min=2,max=4},{item="RawGrouse",chance=0.7,min=1,max=1}}},
	{id="CinderFerret",name="Cinder Ferret",method="box",level=27,region="Quarry",xp=110,base=0.24,color="D9642B",
		drops={{item="EmberPelt",chance=1,min=1,max=1},{item="ArcaneDust",chance=0.3,min=1,max=2},{item="PuffkinPet",chance=0.001,min=1,max=1}}},
	{id="GlintwingDragonfly",name="Glintwing Dragonfly",method="net",level=36,region="Tidewater",xp=140,base=0.45,respawn=6,color="8EF0F8",
		drops={{item="GlintEssence",chance=1,min=1,max=2},{item="GlimmerflyPet",chance=0.0015,min=1,max=1}}},
	{id="GaleKestrel",name="Gale Kestrel",method="bird",level=48,region="Skyreach",xp=200,base=0.2,color="DDEBFF",
		drops={{item="GalePlume",chance=1,min=2,max=3},{item="StormFeather",chance=0.3,min=1,max=1}}},
	{id="GloomLynx",name="Gloom Lynx",method="box",level=62,region="Gloomhollow",xp=280,base=0.17,color="3D3654",
		drops={{item="ShadowPelt",chance=1,min=1,max=1},{item="VoidEssence",chance=0.15,min=1,max=1},{item="GlimmerflyPet",chance=0.001,min=1,max=1}}},
	{id="StormmaneIbex",name="Stormmane Ibex",method="snare",level=80,region="Tempest",xp=380,base=0.14,color="8FA3C8",
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

return Data
