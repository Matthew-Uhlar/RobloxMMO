-- Treasure Trails step pool and step rules (server-only; ServerStorage.AetherTrails).
-- Everything that would answer a clue lives here, never in the replicated
-- ReplicatedStorage.AetherData: landmark anchors, dig offsets, riddle targets
-- (NPCs and landmarks), emote places and outfits, puzzle scrambles, trail
-- generation, the player-facing step text and the p.trails sanitiser.
-- Shared, non-secret rules (tiers, items, rewards, scroll sources, pacing,
-- gestures and the sliding-puzzle moves the client needs) stay in Data.Trails.
-- Usage: local TR = require(ServerStorage.AetherTrails)(Data) -> a table whose
-- missing keys fall through to Data.Trails. Pure: no Roblox APIs.
-- Step kinds:
--   dig     stand within TR.DIG_RADIUS studs of a point offset from an island
--           anchor (east = +X, north = -Z) and use trailDig with a Wayfinder's Spade
--   riddle  cryptic text naming an NPC or landmark; trailSearch within TR.SEARCH_RADIUS
--   emote   perform a gesture (gesture relay names) at a landmark while wearing items
--   skill   gather / fish / kill / thieve / catch / craft something after the step began
--   puzzle  a 3x3 sliding tile box; trailSlide "Tier:UDLR..." moves the blank
-- Profile p.trails = {active={[tier]={seed,steps={ids},step,base,board,moves,began,
-- lt,lx,lz}}, log={[tier]={completed,opened}}, uniques={[item]=n}, emotes={id...},
-- banner, version}. lt/lx/lz = time and place of the trail's last location step.
-- Seeds come from server entropy (Random.new()) and are never sent to clients.
------------------------------------------------------------------------------
return function(Data)
local TR = setmetatable({}, {__index = Data.Trails})
-- Anchor (without "Anchor_") -> display name and region (the island's Region).
TR.Landmarks = {
	Spawn={"the Sky Harbor landing","Hub"}, Waypoint_SkyHarbor={"the Sky Harbor moorings","Hub"}, Waypoint_Bank={"the vault steps","Hub"},
	Waypoint_Market={"Market Row","Hub"}, Waypoint_Starforge={"the Starforge","Hub"}, Waypoint_Homeward={"the Homeward beacon","Hub"},
	Waypoint_CrewHaven={"the Crew Haven gate","Hub"}, Waypoint_Altar_QuayChapel={"the Quay Chapel","Hub"}, Waypoint_Agility_QuayRigging={"the Quay Rigging","Hub"},
	Waypoint_SkymarkExchange={"the Skymark Exchange","Hub"}, Waypoint_Thieving_SweetbunStall={"the Sweetbun Stall","Hub"},
	Waypoint_Bridge_WardenReach={"the north bridgehead of Compass Quay","Hub"}, Waypoint_Bridge_GuildTerrace={"the south bridgehead of Compass Quay","Hub"},
	Waypoint_ExpeditionGate={"the Observatory gate","Hub"}, Waypoint_Shellwarden={"the Shellwarden's ring","Hub"},
	Waypoint_Forge={"the guild Forge","Hub"}, Waypoint_Hearth={"the guild Hearth","Hub"}, Waypoint_Cauldron={"the guild Cauldron","Hub"},
	Waypoint_Workbench={"the guild Workbench","Hub"}, Waypoint_HallOfMastery={"the Hall of Mastery","Hub"}, Waypoint_Skyway={"the Skyway platform","Hub"},
	Waypoint_SlayerMaster={"the Slayer post","Hub"},
	Waypoint_Moonpool={"the Moonpool","Meadow"}, Waypoint_MoonpoolJetty={"the Moonpool jetty","Meadow"}, Waypoint_Agility_MosswakeHedgerow={"the Mosswake Hedgerow","Meadow"},
	Waypoint_Hunting_SunwingMoth={"the moth meadow","Meadow"}, Waypoint_TrackersLodge={"the Trackers' Lodge","Meadow"}, Waypoint_Hunting_PuffcapHopper={"the hopper warren","Meadow"},
	Waypoint_Thieving_HerbalistStall={"the Herbalist's Stall","Meadow"}, Waypoint_Entrance_Meadow={"the Meadow Reach gate","Meadow"},
	Waypoint_AetheriteSeam={"the Aetherite Seam","Quarry"}, Waypoint_SkyreachCharter={"the Skyreach charter beacon","Quarry"}, Waypoint_Agility_BrassfallScaffold={"the Brassfall Scaffold","Quarry"},
	Waypoint_Thieving_GemStall={"the Gemcutter's Stall","Quarry"}, Waypoint_DeepDescent={"the Deep Descent","Quarry"}, Waypoint_Hunting_CinderFerret={"the ferret burrows","Quarry"},
	Waypoint_Entrance_Skyreach={"the Skyreach landing","Skyreach"}, Waypoint_Agility_SkyreachUpdraft={"the Skyreach Updraft","Skyreach"},
	Waypoint_Hunting_GaleKestrel={"the kestrel eyrie","Skyreach"}, Waypoint_Thieving_Strongbox={"the Ironbound Strongbox","Skyreach"},
	Waypoint_Entrance_Windpine={"the Windpine landing","Windpine"}, Waypoint_Agility_WindpineCanopy={"the Windpine Canopy","Windpine"},
	Waypoint_Altar_MossrootShrine={"the Mossroot Shrine","Windpine"}, Waypoint_Hunting_PinecrestGrouse={"the grouse thicket","Windpine"},
	Waypoint_Thieving_SilkStall={"the Silkweaver's Stall","Windpine"}, Waypoint_Workbench_Windpine={"the grove Workbench","Windpine"},
	Waypoint_Entrance_Gloomhollow={"the Gloomhollow landing","Gloomhollow"}, Waypoint_Forge_Gloomhollow={"the deep Forge","Gloomhollow"},
	Waypoint_Hunting_GloomLynx={"the lynx hollow","Gloomhollow"}, Waypoint_Thieving_VaultChest={"the Gilded Vault Chest","Gloomhollow"},
	Waypoint_Agility_GloomhollowChasm={"the Gloomhollow Chasm","Gloomhollow"},
	Waypoint_Entrance_Tidewater={"the Tidewater landing","Tidewater"}, Waypoint_Hearth_Tidewater={"the shoal Hearth","Tidewater"},
	Waypoint_Hunting_GlintwingDragonfly={"the dragonfly reeds","Tidewater"}, Waypoint_Thieving_CuriosStall={"the Curio Stall","Tidewater"},
	Waypoint_Agility_TidewaterMastwalk={"the Mastwalk","Tidewater"},
	Waypoint_Entrance_Tempest={"the Tempest landing","Tempest"}, Waypoint_Altar_ThunderChoirAltar={"the Thunder Choir Altar","Tempest"},
	Waypoint_Hunting_StormmaneIbex={"the ibex crags","Tempest"}, Waypoint_Agility_TempestStormrun={"the Stormrun","Tempest"},
	Waypoint_Skyway_ShatteredCrown={"the Crown skyway pad","Tempest"},
	Waypoint_Entrance_ShatteredCrown={"the Crown landing","ShatteredCrown"}, Waypoint_CrownForge={"the Crownforge","ShatteredCrown"},
	Waypoint_CrownCauldron={"the Crown cauldron","ShatteredCrown"}, Waypoint_Altar_CrownReliquary={"the Crown Reliquary","ShatteredCrown"},
	Waypoint_Thieving_SovereignCoffer={"the Sovereign Coffer","ShatteredCrown"},
}
for anchorName, l in pairs(TR.Landmarks) do TR.Landmarks[anchorName] = {name=l[1],region=l[2],anchor=anchorName} end


------------------------------------------------------------------------------
-- The step pool. tiers = {min,max} tier indices (Beginner 1 .. Master 6).
------------------------------------------------------------------------------
TR.Steps = {}
TR.StepById = {}
local function add(step)
	assert(not TR.StepById[step.id], "duplicate trail step "..step.id)
	step.tiers = step.tiers or {1,6}
	table.insert(TR.Steps, step)
	step.index = #TR.Steps
	TR.StepById[step.id] = step
	return step
end
-- dig(id, min, max, anchor, east, north, sketch?) — sketch makes it a map step.
local function dig(id, lo, hi, anchorName, east, north, sketch)
	add({id=id,kind="dig",tiers={lo,hi},anchor=anchorName,east=east,north=north,sketch=sketch,region=TR.Landmarks[anchorName] and TR.Landmarks[anchorName].region})
end
dig("DigHarborLanding",1,3,"Spawn",-6,5)
dig("DigVaultSteps",1,3,"Waypoint_Bank",-5,-4,"A coin-sketch: broad steps under a lion-less arch, a ledger left open on the third step. The X sits a few strides behind the counting-house, towards the quay's heart.")
dig("DigMarketRow",1,3,"Waypoint_Market",-7,-3)
dig("DigStarforge",1,4,"Waypoint_Starforge",5,4,"Charcoal lines: a great anvil under a star-shaped hood, raised above the plaza. Someone has drawn a little shovel just off its southern steps.")
dig("DigQuayChapel",1,3,"Waypoint_Altar_QuayChapel",-4,6)
dig("DigHomeward",1,3,"Waypoint_Homeward",-6,6)
dig("DigCrewHaven",1,4,"Waypoint_CrewHaven",-6,7)
dig("DigObservatoryGate",2,5,"Waypoint_ExpeditionGate",4,-6,"A map of a ring of waystones and, beyond them, a tall gate under a dome of brass. The X lies past the gate's left post.")
dig("DigShellwarden",1,4,"Waypoint_Shellwarden",-6,3)
dig("DigMoonpool",1,3,"Waypoint_Moonpool",8,-5,"Ink on reed-paper: a round pool that holds the moon by day, a little jetty, and an X on the dry bank to the east.")
dig("DigHedgerow",1,4,"Waypoint_Agility_MosswakeHedgerow",5,-6)
dig("DigMothMeadow",1,3,"Waypoint_Hunting_SunwingMoth",-6,-5)
dig("DigTrackersLodge",1,4,"Waypoint_TrackersLodge",-6,5,"A pelt-hung lodge with antlers over the door. The X is drawn at the edge of the yard where the snares are stretched to dry.")
dig("DigHopperWarren",1,3,"Waypoint_Hunting_PuffcapHopper",6,6)
dig("DigHerbalist",1,3,"Waypoint_Thieving_HerbalistStall",5,7)
dig("DigAetheriteSeam",1,4,"Waypoint_AetheriteSeam",-7,4,"A miner's doodle: a blue vein zig-zagging through grey rock, and a pick left leaning against a boulder. Dig on the quarry floor beside it.")
dig("DigCharterBeacon",1,4,"Waypoint_SkyreachCharter",-8,2)
dig("DigGemStall",2,5,"Waypoint_Thieving_GemStall",6,5)
dig("DigDeepDescent",2,5,"Waypoint_DeepDescent",-5,-6,"A sooty sketch of a dark stair sinking into a shelf of cinders. The X is up on the shelf, a short walk from the first step.")
dig("DigFerretBurrows",2,5,"Waypoint_Hunting_CinderFerret",7,-3)
dig("DigHallOfMastery",2,6,"Waypoint_HallOfMastery",-6,-4)
dig("DigSkywayPlatform",2,6,"Waypoint_Skyway",6,4,"Lines radiate from a round platform to four smaller pads, like the spokes of a wheel. The X sits beside the hub, on the eastern side.")
dig("DigMossrootShrine",2,6,"Waypoint_Altar_MossrootShrine",6,-5)
dig("DigGrouseThicket",2,6,"Waypoint_Hunting_PinecrestGrouse",-6,6,"Pine needles pressed into wax: a thicket where speckled birds drum. The X is set in the clearing just north of it.")
dig("DigGroveWorkbench",2,6,"Waypoint_Workbench_Windpine",-7,5)
dig("DigKestrelEyrie",3,6,"Waypoint_Hunting_GaleKestrel",7,-7)
dig("DigStrongbox",3,6,"Waypoint_Thieving_Strongbox",7,-4,"An iron chest bound with bands, high where the clouds are thin. Somebody buried what they could not carry a few strides to its north-east.")
dig("DigDragonflyReeds",3,6,"Waypoint_Hunting_GlintwingDragonfly",-6,-6)
dig("DigShoalHearth",3,6,"Waypoint_Hearth_Tidewater",-6,-6,"A cook's map: a fire-pit by the shoals with a fish drawn over it. The X is up the beach, away from the water.")
dig("DigCurioStall",3,6,"Waypoint_Thieving_CuriosStall",5,-7)
dig("DigLynxHollow",4,6,"Waypoint_Hunting_GloomLynx",7,5)
dig("DigVaultChest",4,6,"Waypoint_Thieving_VaultChest",5,7,"Gold leaf on black paper: a gilded chest in a cavern of violet stone. The X sits south-east of it, where the lantern light ends.")
dig("DigThunderChoir",4,6,"Waypoint_Altar_ThunderChoirAltar",6,6)
dig("DigIbexCrags",4,6,"Waypoint_Hunting_StormmaneIbex",-7,-6)
dig("DigCrownReliquary",5,6,"Waypoint_Altar_CrownReliquary",-6,6,"A crown in six shards hangs over a reliquary. A trail of tiny stars leads north-west from its steps to an X.")
dig("DigCrownCauldron",5,6,"Waypoint_CrownCauldron",-4,8)
dig("DigSovereignCoffer",5,6,"Waypoint_Thieving_SovereignCoffer",-5,-7)
dig("DigCrownforge",5,6,"Waypoint_CrownForge",5,8,"A forge cut from one great crown-shard, sparks drawn as tiny suns. The X lies north-east, between the forge and the island's heart.")

-- riddle(id, min, max, target, text): target = "npc:<Role>" or an anchor name.
local function riddle(id, lo, hi, target, text)
	local step = {id=id,kind="riddle",tiers={lo,hi},target=target,text=text}
	local role = string.match(target, "^npc:(%w+)$")
	if role then
		step.npc = role
		step.anchor = "NPC_"..role
		local npc = Data.Townsfolk and Data.Townsfolk.NPCs[role]
		step.region = npc and npc.region
	else
		step.anchor = target
		step.region = TR.Landmarks[target] and TR.Landmarks[target].region
	end
	add(step)
end
riddle("RiddleBanker",1,4,"npc:Banker","Coins sleep behind my iron door; I count them twice, then once more. Ask the keeper whose name rings like bone and gold.")
riddle("RiddleMerchant",1,4,"npc:Merchant","Salt in my whistle, crates at my feet: I'll buy what you gathered and sell what you'll eat.")
riddle("RiddleForgemaster",1,5,"npc:Forgemaster","Embers run in my veins and in my beard. Find the one who taught the Starforge to sing.")
riddle("RiddleGuide",1,3,"npc:Guide","I hold a lantern by day and point every newcomer the same way: onward. Find me where the travellers land.")
riddle("RiddleFisher",1,4,"npc:Fisher","My line is never idle and my boots are always wet. Find the angler who whistles at the harbour's edge.")
riddle("RiddleAuctioneer",2,5,"npc:Auctioneer","A quill for the ledger, a hammer for the sale. Seek the quartermaster who sells to the highest voice.")
riddle("RiddleHerald",1,4,"npc:Herald","I read the turning of the isle's year aloud and blow a horn when the festivals near. Find me in the heart of the quay.")
riddle("RiddleRegistrar",2,5,"npc:Registrar","Two names on one page, tied with a bright knot. Find the one who writes crews into being.")
riddle("RiddleJoiner",2,5,"npc:Joiner","Peg by peg and plank by plank, I build homes in the sky. Seek the master of the saw.")
riddle("RiddleSlayer",2,6,"npc:Slayer","Thorns on my mantle and tallies on my belt; I hand out the hunts no one else will take.")
riddle("RiddleGrovekeeper",2,6,"npc:Grovekeeper","Older than the oldest pine, I keep the grove where the wind never sleeps.")
riddle("RiddleDeepwarden",4,6,"npc:Deepwarden","My lantern is the only sun in the deep. Find the warden who keeps the caverns' dark at bay.")
riddle("RiddleSweetbun",1,3,"Waypoint_Thieving_SweetbunStall","Warm and sweet, sold by the dozen, guarded by a baker's frown. Stand where the smell is strongest.")
riddle("RiddleChapel",1,4,"Waypoint_Altar_QuayChapel","Bones are given, blessings are taken. Kneel where the quay keeps its quiet.")
riddle("RiddleRigging",1,4,"Waypoint_Agility_QuayRigging","Ropes and spars with no ship beneath them: climb them and you'll learn to fall well.")
riddle("RiddleExchange",2,5,"Waypoint_SkymarkExchange","Marks earned by running, spent where runners trade. Find the counter that takes nothing but glints.")
riddle("RiddleHomeward",1,3,"Waypoint_Homeward","A beacon that only ever points one way: back to what is yours.")
riddle("RiddleObservatory",2,5,"Waypoint_ExpeditionGate","Beyond the waystones a dome watches the stars; its door opens only for delvers.")
riddle("RiddleMastery",2,6,"Waypoint_HallOfMastery","A hall where every trade hangs its finest cloak. Stand at its door.")
riddle("RiddleSlayerPost",2,5,"Waypoint_SlayerMaster","Where contracts are pinned with knives, wait for your next quarry.")
riddle("RiddleSkyway",2,6,"Waypoint_Skyway","One wheel, four spokes, each spoke a road to a harder sky.")
riddle("RiddleMoonpool",1,3,"Waypoint_MoonpoolJetty","I hold the moon at noon. Stand on the boards that reach into me.")
riddle("RiddleHedgerow",1,4,"Waypoint_Agility_MosswakeHedgerow","Leap the hedges and balance the stile; the grove's green course starts here.")
riddle("RiddleTrackers",1,4,"Waypoint_TrackersLodge","Antlers over the door, snares on the line, kits for sale to those who mind the trail.")
riddle("RiddleWarren",1,3,"Waypoint_Hunting_PuffcapHopper","Small, round and mushroom-capped, they hop where the meadow is softest.")
riddle("RiddleSeam",1,4,"Waypoint_AetheriteSeam","Blue light runs in grey rock here; the quarry's first treasure shows its vein.")
riddle("RiddleScaffold",2,5,"Waypoint_Agility_BrassfallScaffold","Brass poles, planks and a long way down: the quarry's runners race above it.")
riddle("RiddleDescent",2,5,"Waypoint_DeepDescent","A stair of cinders that leads to the dark where spiders spin.")
riddle("RiddleMossroot",2,6,"Waypoint_Altar_MossrootShrine","Moss on the stone, roots through the altar: the grove's own place of offering.")
riddle("RiddleCanopy",2,6,"Waypoint_Agility_WindpineCanopy","A course among the needles, where the treetops are the floor.")
riddle("RiddleSilk",3,6,"Waypoint_Thieving_SilkStall","Threads finer than hair, sold in a grove where spiders are kept like sheep.")
riddle("RiddleUpdraft",3,6,"Waypoint_Agility_SkyreachUpdraft","The wind itself is the ladder here; ride it, then stand where it begins.")
riddle("RiddleMastwalk",3,6,"Waypoint_Agility_TidewaterMastwalk","Masts with no hulls stand in the shallows; walk them like a gull would.")
riddle("RiddleCurio",3,6,"Waypoint_Thieving_CuriosStall","Shells that sing, glass that glows, oddments the tide drags in. Find the stall that sells them.")
riddle("RiddleChasm",4,6,"Waypoint_Agility_GloomhollowChasm","Swing over nothing in the deep dark; the runners' course in the caverns starts at its lip.")
riddle("RiddleThunderChoir",4,6,"Waypoint_Altar_ThunderChoirAltar","The storm sings hymns here, and the spire's altar answers.")
riddle("RiddleStormrun",4,6,"Waypoint_Agility_TempestStormrun","Run the peaks while the lightning counts your steps.")
riddle("RiddleReliquary",5,6,"Waypoint_Altar_CrownReliquary","A broken crown's prayers are kept here, shard by shard.")
riddle("RiddleCrownforge",5,6,"Waypoint_CrownForge","A forge that burns with the light of a fallen crown.")

-- emote(id, min, max, anchor, gesture, wear{item ids})
local function emote(id, lo, hi, anchorName, gesture, wear)
	add({id=id,kind="emote",tiers={lo,hi},anchor=anchorName,gesture=gesture,wear=wear or {},region=TR.Landmarks[anchorName] and TR.Landmarks[anchorName].region})
end
emote("EmoteMarket",1,3,"Waypoint_Market","flip")
emote("EmoteChapel",1,3,"Waypoint_Altar_QuayChapel","heal")
emote("EmoteMoonpool",1,3,"Waypoint_MoonpoolJetty","fish")
emote("EmoteSeam",1,3,"Waypoint_AetheriteSeam","mine")
emote("EmoteLodge",1,3,"Waypoint_TrackersLodge","settrap")
emote("EmoteHarbor",1,3,"Waypoint_SkyHarbor","interact")
emote("EmoteStarforge",2,4,"Waypoint_Starforge","hammer",{"Blade"})
emote("EmoteHearth",2,4,"Waypoint_Hearth","stir",{"BrassHelm"})
emote("EmoteWorkbench",2,4,"Waypoint_Workbench","saw",{"BrassBoots"})
emote("EmoteHedgerow",2,4,"Waypoint_Agility_MosswakeHedgerow","interact",{"BrassGreaves"})
emote("EmoteMossroot",2,5,"Waypoint_Altar_MossrootShrine","heal",{"BrassChestplate"})
emote("EmoteGrouse",2,5,"Waypoint_Hunting_PinecrestGrouse","netswing",{"BrassSword"})
emote("EmoteObservatory",2,5,"Waypoint_ExpeditionGate","attack",{"BrassSword","BrassHelm"})
emote("EmoteSkyway",3,5,"Waypoint_Skyway","drink",{"SunsteelHelm"})
emote("EmoteUpdraft",3,6,"Waypoint_Agility_SkyreachUpdraft","cast",{"SunsteelBoots","BrassSword"})
emote("EmoteDragonfly",3,6,"Waypoint_Hunting_GlintwingDragonfly","netswing",{"SunsteelGreaves"})
emote("EmoteMastwalk",3,6,"Waypoint_Agility_TidewaterMastwalk","flip",{"SunsteelChestplate"})
emote("EmoteMastery",3,6,"Waypoint_HallOfMastery","interact",{"SunsteelSword","SunsteelHelm"})
emote("EmoteStrongbox",3,6,"Waypoint_Thieving_Strongbox","flick",{"SunsteelBoots"})
emote("EmoteDeepForge",4,6,"Waypoint_Forge_Gloomhollow","hammer",{"VoidforgedHelm","VoidforgedBoots"})
emote("EmoteChasm",4,6,"Waypoint_Agility_GloomhollowChasm","shoot",{"VoidforgedChestplate"})
emote("EmoteThunderChoir",4,6,"Waypoint_Altar_ThunderChoirAltar","heal",{"VoidforgedSword","VoidforgedGreaves"})
emote("EmoteStormrun",4,6,"Waypoint_Agility_TempestStormrun","attack",{"StarmetalHelm"})
emote("EmoteCrownPad",5,6,"Waypoint_Skyway_ShatteredCrown","drink",{"StarmetalChestplate","StarmetalBoots"})
emote("EmoteCrownforge",5,6,"Waypoint_CrownForge","hammer",{"StarmetalSword","StarmetalGreaves"})
emote("EmoteReliquary",6,6,"Waypoint_Altar_CrownReliquary","heal",{"PrismaticHelm","PrismaticChestplate"})
emote("EmoteCrownCauldron",6,6,"Waypoint_CrownCauldron","stir",{"PrismaticSword","PrismaticBoots"})

-- skill(id, min, max, action, target, count): action gather | fish | kill | thieve | catch | craft.
local function skill(lo, hi, action, target, count)
	add({id="Skill"..action:sub(1,1):upper()..action:sub(2)..target,kind="skill",tiers={lo,hi},action=action,target=target,count=count or 1})
end
for _, row in ipairs({
	{1,3,"gather","Ore",3},{1,3,"gather","Timber",3},{1,3,"gather","Herb",3},{1,3,"fish","Fish",2},{2,4,"gather","Aetherite",2},
	{2,4,"gather","Brassite",3},{2,4,"gather","WindpineLog",3},{2,4,"gather","Sunwheat",3},{2,4,"fish","Glassfin",2},
	{3,5,"gather","SunsteelOre",2},{3,5,"gather","EmberoakLog",2},{3,5,"fish","Stormeel",2},{3,5,"gather","Glowcap",2},
	{4,6,"gather","Voidstone",2},{4,6,"fish","Lanternray",2},{4,6,"gather","Moonbloom",2},{4,6,"gather","GlimmerbarkLog",2},
	{5,6,"gather","StarmetalOre",2},{5,6,"fish","AbyssKoi",1},{5,6,"gather","Starfruit",2},{6,6,"gather","Prismite",1},{6,6,"fish","LeviathanScale",1},
	{1,3,"kill","BramblebackBoar",2},{1,3,"kill","ShaleCrawler",1},{2,4,"kill","BarkStalker",1},{3,5,"kill","BrassGolem",1},
	{4,6,"kill","GloomfangSpider",1},{5,6,"kill","TempestWraith",1},{6,6,"kill","RiftmawStalker",1},
	{1,3,"thieve","Farmhand",2},{2,4,"thieve","SweetbunStall",1},{2,4,"thieve","HerbalistStall",1},{3,5,"thieve","Watchman",1},
	{4,6,"thieve","Merchant",1},{5,6,"thieve","Scholar",1},{6,6,"thieve","Noble",1},
	{1,3,"catch","PuffcapHopper",1},{2,4,"catch","SunwingMoth",1},{2,5,"catch","PinecrestGrouse",1},{3,5,"catch","CinderFerret",1},
	{4,6,"catch","GlintwingDragonfly",1},{4,6,"catch","GaleKestrel",1},{5,6,"catch","GloomLynx",1},{6,6,"catch","StormmaneIbex",1},
	{1,3,"craft","CookedFish",1},{2,4,"craft","BrassIngot",2},{2,4,"craft","CookedGlassfin",1},{3,5,"craft","SunsteelIngot",2},
	{3,5,"craft","HuntersFeast",1},{4,6,"craft","VoidforgedIngot",1},{5,6,"craft","StarmetalIngot",1},{6,6,"craft","PrismaticIngot",1},
}) do skill(row[1], row[2], row[3], row[4], row[5]) end

-- puzzle(id, min, max, name)
local function puzzle(id, lo, hi, name, text)
	add({id=id,kind="puzzle",tiers={lo,hi},name=name,text=text})
end
puzzle("PuzzleTinker",2,3,"Tinker's Puzzle Box","A palm-sized box of sliding brass tiles. Put the numbers back in order to spring its lid.")
puzzle("PuzzleGearwright",3,4,"Gearwright's Box","Eight geared tiles and a gap. Slide them home and the box will tick open.")
puzzle("PuzzleCipher",3,5,"Skyreach Cipher Box","Cloud-white tiles with numbers in the old charter script. Order them to read the next clue.")
puzzle("PuzzleStormglass",4,6,"Stormglass Box","Tiles of cold glass that crackle when touched. Slide them into order before the storm inside wakes.")
puzzle("PuzzleLattice",5,6,"Starlit Lattice","A lattice of star-tiles. When the numbers run true, the lattice unfolds.")
puzzle("PuzzleAurora",6,6,"Aurora Cube","A cube that shifts colour with every slide. Order its face and it opens like a flower.")

------------------------------------------------------------------------------
-- Step rules (pure).
------------------------------------------------------------------------------
local function regionName(id) local r = Data.RegionById[id] return r and r.name or tostring(id) end
TR.regionName = regionName
local function itemName(id) local d = Data.Items[id] return d and d.name or tostring(id) end
-- Data definition behind a skill step (resource, monster, target, creature or recipe).
function TR.skillTarget(step)
	local a, id = step.action, step.target
	if a == "gather" or a == "fish" then
		local skill = Data.ResourceSkill[id]
		if not skill or (a == "fish") ~= (skill == "Fishing") then return nil end
		for _, r in ipairs(Data.ResourceTiers[skill]) do if r.id == id then return r end end
	elseif a == "kill" then return rawget(Data.Monsters, id)
	elseif a == "thieve" then return Data.Thieving.TargetById[id]
	elseif a == "catch" then return Data.Hunter.CreatureById[id]
	elseif a == "craft" then return Data.Recipes[id] end
	return nil
end
-- Requirements a reader must meet for the step to be drawn: {skills={}, region}.
function TR.requires(step)
	local skills, region = {}, step.region
	if step.kind == "emote" then
		for _, id in ipairs(step.wear) do
			local def = Data.Items[id]
			for s, lvl in pairs(def and def.requires or {}) do skills[s] = math.max(skills[s] or 0, lvl) end
		end
	elseif step.kind == "skill" then
		local def = TR.skillTarget(step)
		if def then
			local a = step.action
			if a == "gather" or a == "fish" then skills[def.skill] = def.level
			elseif a == "kill" then region = def.region
			elseif a == "thieve" then skills.Thieving = def.level; region = def.region
			elseif a == "catch" then skills.Hunter = def.level; region = def.region
			elseif a == "craft" and def.skill and def.level then skills[def.skill] = def.level end
		end
	end
	return {skills=skills,region=region}
end
-- ctx = {levels={[skill]=n}, regions={[id]=true}} (nil = no reader filter).
function TR.eligible(step, tierId, ctx)
	local t = TR.Tiers[tierId]
	if not t or t.index < step.tiers[1] or t.index > step.tiers[2] then return false end
	local req = TR.requires(step)
	if req.region and not t.regions[req.region] then return false end
	if ctx then
		if req.region and ctx.regions and not ctx.regions[req.region] then return false end
		for s, lvl in pairs(req.skills) do
			if ((ctx.levels or {})[s] or 1) < lvl then return false end
		end
	end
	return true
end
function TR.pool(tierId, ctx)
	local out = {}
	for _, step in ipairs(TR.Steps) do if TR.eligible(step, tierId, ctx) then table.insert(out, step) end end
	return out
end
-- Park-Miller stream: deterministic from an integer seed; returns rng() -> [0,1).
function TR.stream(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if s == 0 then s = 1 end
	return function()
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
end
-- Steps for a trail: count from the tier range, kinds weighted per tier, no
-- repeats. With ctx the reader's levels/regions filter the pool; when too few
-- steps qualify the trail shortens (never below 1). When nothing qualifies the
-- result is {} (never a fall-back to steps the reader cannot do): trailBegin
-- then keeps the scroll. Returns a list of step ids.
function TR.generate(tierId, seed, ctx)
	local t = TR.Tiers[tierId]
	if not t then return {} end
	local rng = TR.stream(seed)
	local pool = TR.pool(tierId, ctx)
	if #pool == 0 then return {} end
	local byKind = {}
	for _, step in ipairs(pool) do
		byKind[step.kind] = byKind[step.kind] or {}
		table.insert(byKind[step.kind], step)
	end
	local count = t.steps[1] + math.floor(rng() * (t.steps[2] - t.steps[1] + 1))
	count = math.min(count, #pool)
	local out = {}
	for _ = 1, count do
		local total = 0
		for _, kind in ipairs(TR.KindOrder) do
			if byKind[kind] and #byKind[kind] > 0 then total += t.kinds[kind] or 0 end
		end
		local kindPick
		if total > 0 then
			local x = rng() * total
			for _, kind in ipairs(TR.KindOrder) do
				local w = (byKind[kind] and #byKind[kind] > 0) and (t.kinds[kind] or 0) or 0
				if w > 0 then
					x -= w
					if x < 0 then kindPick = kind break end
				end
			end
		end
		if not kindPick then
			for _, kind in ipairs(TR.KindOrder) do if byKind[kind] and #byKind[kind] > 0 then kindPick = kind break end end
		end
		if not kindPick then break end
		local list = byKind[kindPick]
		local i = 1 + math.floor(rng() * #list)
		table.insert(out, list[i].id)
		table.remove(list, i)
	end
	return out
end

-- Scrambled board for a step (deterministic): a random walk from solved that
-- never undoes its last move and never ends solved.
function TR.scramble(seed, length)
	local rng = TR.stream(seed)
	local board, last = TR.SOLVED, nil
	local i = 0
	while i < length or board == TR.SOLVED do
		local options = {}
		for _, dir in ipairs({"U","D","L","R"}) do
			if dir ~= (last and TR.Opposite[last]) and TR.slide(board, dir) then table.insert(options, dir) end
		end
		local dir = options[1 + math.floor(rng() * #options)]
		board, last = TR.slide(board, dir), dir
		i += 1
	end
	return board
end
-- Seed for step n of a trail (distinct per step).
function TR.stepSeed(seed, n) return (math.floor(tonumber(seed) or 1) + n * 7919) % 2147483646 + 1 end

-- Player-facing text: {text, hint, guide={specs}} (no answers in riddle,
-- map or puzzle hints; coordinate and emote steps already name their landmark).
local function paces(n, pos, neg)
	if n == 0 then return nil end
	return math.abs(n).." "..(if math.abs(n) == 1 then "pace" else "paces").." "..(if n > 0 then pos else neg)
end
function TR.describe(step)
	local region = step.region and regionName(step.region)
	if step.kind == "dig" then
		local lm = TR.Landmarks[step.anchor]
		if step.sketch then
			return {text="Map: "..step.sketch,hint="The sketch was drawn in "..(region or "the isles")..". Dig with a Wayfinder's Spade.",guide={"region:"..step.region},style="map"}
		end
		local parts = {}
		for _, s in ipairs({paces(step.north, "north", "south"), paces(step.east, "east", "west")}) do table.insert(parts, s) end
		return {text="Bearing: dig "..table.concat(parts, " and ").." of "..lm.name..".",hint="North is the way to Warden Reach from the quay. "..lm.name:gsub("^%l", string.upper).." is in "..region..". Bring a Wayfinder's Spade.",
			guide={"anchor:"..step.anchor,"region:"..step.region},style="coordinate"}
	elseif step.kind == "riddle" then
		return {text="Riddle: "..step.text,hint="Search for the answer somewhere in "..(region or "the isles")..".",guide={"region:"..(step.region or "Hub")},style="riddle"}
	elseif step.kind == "emote" then
		local lm = TR.Landmarks[step.anchor]
		local wear = {}
		for _, id in ipairs(step.wear) do table.insert(wear, itemName(id)) end
		local text = "Perform the "..TR.Gestures[step.gesture].." at "..lm.name..(if #wear > 0 then ", wearing "..table.concat(wear, " and ") else "")..". Beware of strangers."
		return {text=text,hint="Stand close by "..lm.name.." in "..region.." and use Perform.",guide={"anchor:"..step.anchor,"region:"..step.region},style="emote"}
	elseif step.kind == "skill" then
		local def = TR.skillTarget(step)
		local name = def and (def.name or itemName(def.output or step.target)) or step.target
		local verb = ({gather="Gather",fish="Catch",kill="Slay",thieve="Successfully rob",catch="Trap or net",craft="Craft"})[step.action]
		local times = if step.count > 1 then (if step.action == "kill" or step.action == "thieve" then " "..step.count.." times" else " x"..step.count) else ""
		if step.action == "craft" then name = itemName(step.target) end
		local req = TR.requires(step)
		local where = req.region and (" in "..regionName(req.region)) or ""
		return {text="Task: "..verb.." "..(if step.action == "thieve" then "the " else "")..name..times..".",hint="Progress counts from the moment this step began"..where..".",
			guide=req.region and {"region:"..req.region} or {},style="skill"}
	elseif step.kind == "puzzle" then
		return {text="Puzzle box: "..step.name..". "..step.text,hint="Slide tiles into the empty space until they read 1-8 with the gap last.",guide={},style="puzzle"}
	end
	return {text="",hint="",guide={}}
end

-- Profile sanitiser (pure): returns a clean p.trails record and the list of
-- tiers whose trail had to be dropped (the caller refunds their scroll).
-- Unknown or tampered active trails are dropped; a trail whose stored steps
-- vanished from the pool is re-drawn from its seed with the reader's context
-- ctx (levels/regions, as TR.generate), so a re-draw is always walkable; when
-- nothing qualifies the trail is dropped and its tier listed. Legacy fields
-- (the old persisted roll stream `r`) are not carried over.
function TR.sanitize(raw, ctx)
	raw = type(raw) == "table" and raw or {}
	local function whole(v, lo, hi)
		local n = tonumber(v)
		if not n or n ~= n then return nil end
		return math.clamp(math.floor(n), lo, hi)
	end
	local out = {active={},log={},uniques={},emotes={},version=TR.VERSION}
	local lost = {}
	for _, id in ipairs(TR.TierOrder) do
		local l = type(raw.log) == "table" and raw.log[id]
		out.log[id] = {completed=whole(type(l) == "table" and l.completed, 0, 1e9) or 0,opened=whole(type(l) == "table" and l.opened, 0, 1e9) or 0}
		local a = type(raw.active) == "table" and raw.active[id]
		if type(a) == "table" then
			local seed = whole(a.seed, 1, 2147483646)
			if seed then
				local steps, valid = {}, type(a.steps) == "table" and #a.steps >= 1 and #a.steps <= TR.Tiers[id].steps[2]
				if valid then
					for _, sid in ipairs(a.steps) do
						if type(sid) ~= "string" or not TR.StepById[sid] then valid = false break end
						table.insert(steps, sid)
					end
				end
				if not valid then steps = TR.generate(id, seed, ctx) end
				if #steps == 0 then table.insert(lost, id) end
				if #steps > 0 then
					local step = whole(a.step, 1, #steps) or 1
					local rec = {seed=seed,steps=steps,step=step,base=whole(a.base, 0, 1e12) or 0,began=whole(a.began, 0, 1e12) or 0,moves=whole(a.moves, 0, 1e6) or 0}
					local lt, lx, lz = whole(a.lt, 0, 1e12), tonumber(a.lx), tonumber(a.lz)
					if lt and lx and lz and lx == lx and lz == lz then rec.lt, rec.lx, rec.lz = lt, math.clamp(lx, -1e6, 1e6), math.clamp(lz, -1e6, 1e6) end
					if TR.validBoard(a.board) then rec.board = a.board end
					local cur = TR.StepById[steps[step]]
					if cur.kind == "puzzle" and not rec.board then rec.board = TR.scramble(TR.stepSeed(seed, step), TR.Tiers[id].scramble) end
					if cur.kind ~= "puzzle" then rec.board = nil end
					out.active[id] = rec
				end
			end
		end
	end
	if type(raw.uniques) == "table" then
		for idx, n in pairs(raw.uniques) do if TR.UniqueTier[idx] then out.uniques[idx] = whole(n, 0, 1e9) end end
	end
	if type(raw.emotes) == "table" then
		for _, e in ipairs(raw.emotes) do if TR.Emotes[e] and not table.find(out.emotes, e) then table.insert(out.emotes, e) end end
	end
	if type(raw.banner) == "string" and Data.Items[raw.banner] and Data.Items[raw.banner].category == "banner" then out.banner = raw.banner end
	return out, lost
end
return TR
end
