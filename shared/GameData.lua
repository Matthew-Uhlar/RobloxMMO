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
	miningSpeed={name="Mining Speed",symbol="⸕",color="FFAA00",base=0},
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

return Data
