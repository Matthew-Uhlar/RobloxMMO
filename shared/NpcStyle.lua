--!nocheck
-- NPC art (docs/DEPTH-CONTRACT.md §52): ReplicatedStorage.AetherNpcStyle.
-- Pure rules, no instances, shared by npc.server.lua (fallback rig, nameplate),
-- npc.client.lua (forged outfits, trade idle loops) and the tests / previews.
--
--   S.outfit(role, def)  -> {trade, idle, hat, held, pieces = {{shape, bone, at, rot, k, dye, slot}}, region}
--   S.sample(name, t, out) -> joint -> {rx, ry, rz} (degrees; animate.client.lua's pose
--                          convention: +rx raises an arm forward / leans back, +rz swings a
--                          right arm outward), sampled from the trade's looping keys
--   S.plate(role, def)   -> nameplate spec (fonts, colours, region accent, trade motif medallion, stud size + pixel clamp)
--   S.contrast(a, b)     -> WCAG contrast ratio of two hex colours
--   S.lod(distance, phone, reducedMotion) -> 0 (off) | 1 (15 Hz) | 2 (30 Hz)
local S = {}
S.VERSION = 1

------------------------------------------------------------------------------
-- Dyes: every tinted outfit piece is quantised to one of these, so a town square
-- shares a handful of forged templates (forge outfit pool, desktop 36 / phone 10).
------------------------------------------------------------------------------
S.DYES = {"1A1A1A", "2B2B2B", "3A2A1E", "6D4C41", "8D6E63", "A0522D", "BF360C", "C9A227", "E9B949", "F2E6C8", "ECEFF1",
	"2F5233", "558B2F", "9EE7D2", "00838F", "0277BD", "1F2F4F", "37474F", "4B2C7A", "7B1FA2", "C2185B", "B23A48", "FFD166", "FF8A3D"}
local function channels(hex)
	hex = tostring(hex or "808080")
	return (tonumber(hex:sub(1, 2), 16) or 128) / 255, (tonumber(hex:sub(3, 4), 16) or 128) / 255, (tonumber(hex:sub(5, 6), 16) or 128) / 255
end
function S.dye(hex)
	local r, g, b = channels(hex)
	local best, bestD = S.DYES[1], math.huge
	for _, d in ipairs(S.DYES) do
		local dr, dg, db = channels(d)
		local dist = 0.3 * (r - dr) ^ 2 + 0.59 * (g - dg) ^ 2 + 0.11 * (b - db) ^ 2
		if dist < bestD then best, bestD = d, dist end
	end
	return best
end
-- WCAG relative luminance / contrast.
local function lum(hex)
	local function lin(c) return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4 end
	local r, g, b = channels(hex)
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end
function S.contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

------------------------------------------------------------------------------
-- Regions / factions: nameplate accent and the colour of region-dyed pieces
-- (guard tabards, scholar mantles). Same identities as Signs v2's themes.
------------------------------------------------------------------------------
S.REGIONS = {
	Hub = {name = "Compass Quay", accent = "F7C548", dye = "1F2F4F", crest = "🧭"},
	Meadow = {name = "Sunwheel Downs", accent = "F2C14E", dye = "C9A227", crest = "🌾"},
	Quarry = {name = "Brassfall Cay", accent = "FF9A5A", dye = "BF360C", crest = "⚙"},
	Windpine = {name = "Windpine", accent = "9BD77E", dye = "2F5233", crest = "🌿"},
	Gloomhollow = {name = "Gloomhollow", accent = "C9A6FF", dye = "4B2C7A", crest = "🔮"},
	Tidewater = {name = "Tidewater", accent = "7FE0E8", dye = "00838F", crest = "🐚"},
	Tempest = {name = "Tempest", accent = "9CC8FF", dye = "37474F", crest = "⚡"},
	ShatteredCrown = {name = "Shattered Crown", accent = "FFE08A", dye = "ECEFF1", crest = "👑"},
	Skyreach = {name = "Skyreach", accent = "BFE3FF", dye = "0277BD", crest = "🦅"},
	Home = {name = "Home", accent = "F7C548", dye = "6D4C41", crest = "🏡"},
}

------------------------------------------------------------------------------
-- Shapes (art/OutfitCatalog.lua) and where they sit on the rig. at / rot are in
-- the bone's frame (studs, radians); k scales the authored piece.
------------------------------------------------------------------------------
S.HATS = {wayfarer = "HatWayfarer", tophat = "HatTop", cap = "HatCap", goggles = "HatGoggles", helm = "HatHelm", minerhelm = "HatMiner",
	souwester = "HatSouwester", tricorn = "HatTricorn", feather = "HatFeather", hood = "HatHood", mage = "HatMage", straw = "HatStraw"}
-- New hat styles fall back to the nearest primitive style on the server rig.
S.FALLBACK_HAT = {mage = "hood", straw = "wayfarer"}
-- Per-hat seat on the head (studs; QC M3: the flat cap sits down on the crown).
S.HAT_FRAME = {HatCap = {at = {0, -0.06, 0.03}}}
S.PROPS = {lantern = "PropLantern", ledger = "PropLedger", crate = "PropCrate", hammer = "PropHammer", sword = "PropSword", rod = "PropRod",
	scroll = "PropScroll", horn = "PropHorn", saw = "PropSaw", staff = "PropStaff", pickaxe = "PropPickaxe", tome = "PropTome",
	spear = "PropSpear", poker = "PropPoker", crook = "PropCrook", hoe = "PropHoe"}
S.FALLBACK_HELD = {tome = "ledger", spear = "staff", poker = "staff", crook = "staff", hoe = "staff"}
-- Where each held prop sits on the right hand (the server's fallback props hang
-- from hand * (0, -0.25, 0)).
S.PROP_FRAME = {
	PropLantern = {at = {0, -0.1, 0}}, PropLedger = {at = {0, -0.05, 0}}, PropCrate = {at = {0, -0.25, 0}},
	PropHammer = {at = {0, -0.05, 0}}, PropSword = {at = {0, -0.05, 0}}, PropRod = {at = {0, -0.05, -0.1}, rot = {-0.55, 0, 0}},
	PropScroll = {at = {0, -0.1, 0}}, PropHorn = {at = {0, -0.05, 0}}, PropSaw = {at = {0, -0.05, 0}}, PropStaff = {at = {0, -0.05, 0}},
	PropPickaxe = {at = {0, -0.05, 0}}, PropTome = {at = {-0.35, 0.1, -0.1}}, PropSpear = {at = {0, -0.05, 0}}, PropPoker = {at = {0, -0.05, 0}},
	PropCrook = {at = {0, -0.05, 0}}, PropHoe = {at = {0, -0.05, 0}},
}
-- Props whose tint follows the NPC's accent (crystal, glow, fruit, brass); the
-- rest keep the catalog's own tint (steel, iron, wood) and share one template.
S.ACCENT_PROPS = {PropLantern = true, PropStaff = true, PropCrate = true, PropHorn = true, PropScroll = true, PropTome = true, PropLedger = true}
S.TORSO = {cape = "Cloak", apron = "Apron", mantle = "Mantle", satchel = "Satchel", tabard = "Tabard", belt = "ToolBelt", scarf = "Scarf"}
-- Primitive parts (server) each piece replaces: OutfitSlot attribute values.
S.SLOT_HIDES = {hat = "hat", held = "held", cape = "cape", apron = "apron"}

------------------------------------------------------------------------------
-- Trades: default extras (torso pieces), idle loop and the nameplate medallion: a
-- frame-drawn trade motif (a Theme.ICON_MOTIFS family; no font glyphs, QC M2).
S.TRADES = {
	guide = {idle = "wave", extras = {"satchel"}, motif = "lantern"},
	banker = {idle = "tally", extras = {"mantle"}, motif = "coin"},
	merchant = {idle = "offer", extras = {"satchel"}, motif = "pouch"},
	smith = {idle = "hammer", extras = {"belt"}, motif = "hammer"},
	guard = {idle = "guard", extras = {"tabard"}, motif = "sword"},
	angler = {idle = "cast", extras = {"satchel"}, motif = "rod"},
	auctioneer = {idle = "proclaim", extras = {"mantle"}, motif = "scroll"},
	herald = {idle = "herald", extras = {"scarf"}, motif = "banner"},
	clerk = {idle = "tally", extras = {"mantle"}, motif = "ink"},
	carpenter = {idle = "saw", extras = {"belt"}, motif = "crafttool"},
	druid = {idle = "channel", extras = {}, motif = "sprig"},
	miner = {idle = "mine", extras = {"belt"}, motif = "pickaxe"},
	keeper = {idle = "lantern", extras = {"scarf"}, motif = "lantern"},
	mage = {idle = "channel", extras = {"mantle"}, motif = "staff"},
	farmer = {idle = "offer", extras = {"satchel"}, motif = "crop"},
	shepherd = {idle = "lean", extras = {}, motif = "bell"},
	tinker = {idle = "tinker", extras = {"belt"}, motif = "cog"},
	scholar = {idle = "read", extras = {"mantle"}, motif = "tome"},
	firekeeper = {idle = "poke", extras = {"scarf"}, motif = "ember"},
	runebinder = {idle = "rune", extras = {"mantle"}, motif = "rune"},
}
-- Every named NPC (Data.Townsfolk.Order + RegionFolkOrder). hat / held override
-- the data look for the forged outfit (the server's fallback maps new styles).
S.ROLES = {
	Guide = {trade = "guide", capeDye = "00838F"}, -- Pell Ashgrove: wayfarer's hat, lantern, deep-teal cloak, satchel; waves you over
	Banker = {trade = "banker"}, Merchant = {trade = "merchant"}, Forgemaster = {trade = "smith"},
	Slayer = {trade = "guard"}, Fisher = {trade = "angler"}, Auctioneer = {trade = "auctioneer"}, Herald = {trade = "herald"},
	Registrar = {trade = "clerk", hat = "feather"}, Joiner = {trade = "carpenter"}, Grovekeeper = {trade = "druid", held = "crook"},
	Deepwarden = {trade = "miner"}, SlayerCorvane = {trade = "guard"}, SlayerMaelis = {trade = "keeper", extras = {"mantle"}},
	SlayerVesper = {trade = "mage", extras = {}}, WarpKeeper = {trade = "mage"}, Lamplighter = {trade = "keeper"},
	QuayCrier = {trade = "herald"}, Millwarden = {trade = "farmer", hat = "straw"}, Shepherd = {trade = "shepherd", hat = "straw", held = "crook"},
	SeedSeller = {trade = "farmer", hat = "straw", held = "hoe", extras = {"satchel", "apron"}}, CalderaWatcher = {trade = "miner", extras = {"scarf"}},
	CraneHand = {trade = "tinker"}, ToolTrader = {trade = "clerk", extras = {"belt"}}, Astronomer = {trade = "scholar", held = "tome", hat = "mage"},
	Golemwright = {trade = "tinker"}, UpdraftSupplier = {trade = "angler", extras = {"scarf"}}, CanopyWarden = {trade = "guard", held = "spear", extras = {"satchel"}},
	Sawyer = {trade = "carpenter"}, Forager = {trade = "farmer"}, CrystalReader = {trade = "keeper", extras = {"mantle"}},
	TunnelForeman = {trade = "miner", hat = "minerhelm"}, LanternSeller = {trade = "keeper", extras = {"satchel"}}, Lightkeeper = {trade = "keeper"},
	NetMender = {trade = "angler"}, Fishmonger = {trade = "merchant"}, StormScribe = {trade = "scholar", held = "tome"},
	SpireSentinel = {trade = "guard", held = "spear"}, Stormglazier = {trade = "tinker", held = "hammer"}, CrownArchivist = {trade = "scholar", held = "tome"},
	Shardkeeper = {trade = "guard"}, RelicBroker = {trade = "clerk", extras = {"satchel"}}, Resonator = {trade = "mage", hat = "mage"},
	Beaconkeeper = {trade = "firekeeper", held = "poker"}, -- Old Hesketh Ashby: pokes the embers
	CouncilClerk = {trade = "clerk"}, ContestSteward = {trade = "clerk", hat = "straw"}, TrophyKeeper = {trade = "angler", extras = {"mantle"}},
	RoostKeeper = {trade = "keeper", extras = {"satchel"}}, Runebinder = {trade = "runebinder", hat = "mage"}, -- Maelis Quillstone: traces glyphs
}
-- Fallback for a role added later without an entry: a trade by its held item.
S.HELD_TRADE = {lantern = "keeper", ledger = "clerk", crate = "merchant", hammer = "smith", sword = "guard", rod = "angler", scroll = "scholar",
	horn = "herald", saw = "carpenter", staff = "mage", pickaxe = "miner"}

-- Head dye: a hat's own felt / oilskin colour from the look.
local HAT_DYE = {wayfarer = "hair", tophat = "shoes", tricorn = "shoes", cap = "shirt", feather = "shirt", souwester = "shirt", hood = "cape",
	helm = "accent", minerhelm = "accent", goggles = "accent", mage = "cape", straw = "accent"}

function S.roleSpec(role, def)
	local spec = S.ROLES[role]
	if spec then return spec, true end
	local held = def and def.look and def.look.held
	return {trade = S.HELD_TRADE[held or ""] or "guide"}, false
end
-- Full outfit for a role (def = Data.Townsfolk.NPCs[role]).
function S.outfit(role, def)
	local look = (def and def.look) or {}
	local spec = S.roleSpec(role, def)
	local trade = S.TRADES[spec.trade] or S.TRADES.guide
	local region = S.REGIONS[def and def.region or "Hub"] or S.REGIONS.Hub
	local hat = spec.hat or look.hat
	local held = spec.held or look.held
	local out = {role = role, trade = spec.trade, idle = spec.idle or trade.idle, hat = hat, held = held, region = def and def.region or "Hub", pieces = {}}
	local function add(shape, bone, slot, dye, at, rot, k)
		table.insert(out.pieces, {shape = shape, bone = bone, slot = slot, dye = dye and S.dye(dye) or nil, at = at or {0, 0, 0}, rot = rot or {0, 0, 0}, k = k or 1})
	end
	if hat and S.HATS[hat] then
		local key = HAT_DYE[hat] or "shirt"
		local dye = look[key] or (key == "cape" and look.shirt) or look.shirt
		local frame = S.HAT_FRAME[S.HATS[hat]] or {}
		add(S.HATS[hat], "Head", "hat", dye, frame.at, frame.rot)
	end
	if held and S.PROPS[held] then
		local shape = S.PROPS[held]
		local frame = S.PROP_FRAME[shape] or {}
		add(shape, "RightHand", "held", if S.ACCENT_PROPS[shape] then look.accent else nil, frame.at, frame.rot)
	end
	if look.cape then add(S.TORSO.cape, "UpperTorso", "cape", spec.capeDye or look.cape) end
	if look.apron then add(S.TORSO.apron, "UpperTorso", "apron", look.apron) end
	local extras = spec.extras or trade.extras or {}
	for _, extra in ipairs(extras) do
		local shape = S.TORSO[extra]
		local already = false
		for _, p in ipairs(out.pieces) do if p.shape == shape then already = true end end
		if shape and not already and not (extra == "apron" and look.apron) then
			local dye = if extra == "tabard" or extra == "mantle" then region.dye
				elseif extra == "scarf" then look.accent
				elseif extra == "apron" then (look.pants or "6D4C41")
				else "3A2A1E"
			add(shape, "UpperTorso", extra, dye)
		end
	end
	return out
end
-- The pieces' signature (shape list + dyes), for distinctness checks.
function S.signature(outfit)
	local parts = {}
	for _, p in ipairs(outfit.pieces) do table.insert(parts, p.shape .. ":" .. (p.dye or "")) end
	table.sort(parts)
	return table.concat(parts, ",")
end
-- The primitive hat / held styles the server builds as the fallback.
function S.fallbackHat(role, def)
	local outfit = S.outfit(role, def)
	return S.FALLBACK_HAT[outfit.hat or ""] or outfit.hat
end
function S.fallbackHeld(role, def)
	local outfit = S.outfit(role, def)
	return S.FALLBACK_HELD[outfit.held or ""] or outfit.held
end

------------------------------------------------------------------------------
-- Idle loops: looping keys {t, pose} (t in seconds; the last key equals the
-- first, so a loop is seamless). Poses use animate.client.lua's joints and
-- sign convention and stay inside its Core.JOINT_LIMITS (verify-npcart).
-- beat = seconds into the loop of a prop impact (hammer spark, horn call).
------------------------------------------------------------------------------
local REST = {rightArm = {4, 0, 4}, leftArm = {4, 0, -4}, rightElbow = {12, 0, 0}, leftElbow = {12, 0, 0}}
local function pose(extra)
	local out = {}
	for k, v in pairs(REST) do out[k] = v end
	for k, v in pairs(extra or {}) do out[k] = v end
	return out
end
S.IDLES = {
	-- Smith: raise, strike the anvil (spark on the beat), recoil, steady breath.
	hammer = {period = 2.4, beat = 0.86, keys = {
		{t = 0, pose = pose({rightArm = {38, 0, 10}, rightElbow = {70}, leftArm = {38, 0, -8}, leftElbow = {62}, waist = {-6, 0, 0}, neck = {-14, 0, 0}})},
		{t = 0.55, pose = pose({rightArm = {118, 0, 14}, rightElbow = {98}, rightWrist = {-30, 0, 0}, leftArm = {40, 0, -8}, leftElbow = {64}, waist = {-2, 8, 0}, neck = {-12, 0, 0}})},
		{t = 0.86, pose = pose({rightArm = {46, 0, 10}, rightElbow = {34}, rightWrist = {20, 0, 0}, leftArm = {38, 0, -8}, leftElbow = {62}, waist = {-10, -4, 0}, neck = {-18, 0, 0}})},
		{t = 1.05, pose = pose({rightArm = {58, 0, 10}, rightElbow = {50}, leftArm = {38, 0, -8}, leftElbow = {62}, waist = {-8, 0, 0}, neck = {-16, 0, 0}})},
		{t = 2.4, pose = pose({rightArm = {38, 0, 10}, rightElbow = {70}, leftArm = {38, 0, -8}, leftElbow = {62}, waist = {-6, 0, 0}, neck = {-14, 0, 0}})}}},
	-- Angler: rod held out, a slow bob, a flick of the tip, reel a little, settle.
	cast = {period = 6, beat = 3.1, keys = {
		{t = 0, pose = pose({rightArm = {34, 0, 8}, rightElbow = {58}, leftArm = {20, 0, -6}, leftElbow = {40}, neck = {-4, 0, 0}})},
		{t = 1.5, pose = pose({rightArm = {38, 0, 8}, rightElbow = {62}, leftArm = {20, 0, -6}, leftElbow = {40}, neck = {-2, -6, 0}})},
		{t = 2.8, pose = pose({rightArm = {56, 0, 10}, rightElbow = {80}, rightWrist = {-26, 0, 0}, leftArm = {24, 0, -6}, leftElbow = {44}, waist = {4, 0, 0}})},
		{t = 3.1, pose = pose({rightArm = {30, 0, 8}, rightElbow = {50}, rightWrist = {18, 0, 0}, leftArm = {20, 0, -6}, leftElbow = {40}, waist = {-3, 0, 0}})},
		{t = 4.4, pose = pose({rightArm = {34, 0, 8}, rightElbow = {58}, leftArm = {36, 0, -14}, leftElbow = {78}, neck = {-6, 4, 0}})},
		{t = 6, pose = pose({rightArm = {34, 0, 8}, rightElbow = {58}, leftArm = {20, 0, -6}, leftElbow = {40}, neck = {-4, 0, 0}})}}},
	-- Scholar: book held open, eyes down; a page turn with the left hand.
	read = {period = 7, beat = 4.3, keys = {
		{t = 0, pose = pose({rightArm = {30, 0, -8}, rightElbow = {66}, leftArm = {30, 0, 8}, leftElbow = {66}, neck = {-22, 0, 0}, waist = {-3, 0, 0}})},
		{t = 2.2, pose = pose({rightArm = {32, 0, -8}, rightElbow = {68}, leftArm = {30, 0, 8}, leftElbow = {66}, neck = {-24, 6, 0}, waist = {-3, 0, 0}})},
		{t = 3.8, pose = pose({rightArm = {32, 0, -8}, rightElbow = {68}, leftArm = {44, 0, -10}, leftElbow = {84}, neck = {-20, -4, 0}, waist = {-3, 2, 0}})},
		{t = 4.3, pose = pose({rightArm = {32, 0, -8}, rightElbow = {68}, leftArm = {38, 0, 16}, leftElbow = {60}, neck = {-22, 4, 0}, waist = {-3, -2, 0}})},
		{t = 5.2, pose = pose({rightArm = {30, 0, -8}, rightElbow = {66}, leftArm = {30, 0, 8}, leftElbow = {66}, neck = {-16, 0, 0}, waist = {-1, 0, 0}})},
		{t = 7, pose = pose({rightArm = {30, 0, -8}, rightElbow = {66}, leftArm = {30, 0, 8}, leftElbow = {66}, neck = {-22, 0, 0}, waist = {-3, 0, 0}})}}},
	-- Clerk / banker: ledger on the forearm, the other hand ticks entries.
	tally = {period = 5, beat = 2.6, keys = {
		{t = 0, pose = pose({rightArm = {40, 0, -4}, rightElbow = {84}, leftArm = {30, 0, 4}, leftElbow = {70}, neck = {-18, 0, 0}})},
		{t = 1.2, pose = pose({rightArm = {40, 0, -4}, rightElbow = {84}, leftArm = {38, 0, 14}, leftElbow = {80}, neck = {-20, 4, 0}})},
		{t = 2.0, pose = pose({rightArm = {40, 0, -4}, rightElbow = {84}, leftArm = {36, 0, 2}, leftElbow = {78}, neck = {-20, -2, 0}})},
		{t = 2.6, pose = pose({rightArm = {40, 0, -4}, rightElbow = {84}, leftArm = {40, 0, 10}, leftElbow = {84}, neck = {-20, 2, 0}})},
		{t = 3.6, pose = pose({rightArm = {38, 0, -4}, rightElbow = {82}, leftArm = {14, 0, -6}, leftElbow = {30}, neck = {-2, 10, 0}})},
		{t = 5, pose = pose({rightArm = {40, 0, -4}, rightElbow = {84}, leftArm = {30, 0, 4}, leftElbow = {70}, neck = {-18, 0, 0}})}}},
	-- Merchant: crate on the hip, the free hand presents the wares.
	offer = {period = 6, beat = 2.2, keys = {
		{t = 0, pose = pose({rightArm = {16, 0, 10}, rightElbow = {48}, leftArm = {6, 0, -6}, leftElbow = {16}})},
		{t = 1.4, pose = pose({rightArm = {18, 0, 10}, rightElbow = {50}, leftArm = {48, 0, -34}, leftElbow = {36}, waist = {2, 10, 0}, neck = {0, 14, 0}})},
		{t = 2.2, pose = pose({rightArm = {18, 0, 10}, rightElbow = {50}, leftArm = {56, 0, -40}, leftElbow = {24}, waist = {3, 12, 0}, neck = {2, 18, 0}})},
		{t = 3.4, pose = pose({rightArm = {16, 0, 10}, rightElbow = {48}, leftArm = {10, 0, -8}, leftElbow = {20}, neck = {0, -10, 0}})},
		{t = 6, pose = pose({rightArm = {16, 0, 10}, rightElbow = {48}, leftArm = {6, 0, -6}, leftElbow = {16}})}}},
	-- Guard: weapon grounded, weight shifts, a slow scan of the square.
	guard = {period = 8, beat = 4, keys = {
		{t = 0, pose = pose({rightArm = {10, 0, 8}, rightElbow = {14}, leftArm = {6, 0, -8}, neck = {0, 0, 0}, root = {0, 0, 0}})},
		{t = 2.4, pose = pose({rightArm = {10, 0, 8}, rightElbow = {14}, leftArm = {6, 0, -8}, neck = {2, 32, 0}, waist = {0, 8, 0}, root = {0, 0, 2}})},
		{t = 4, pose = pose({rightArm = {12, 0, 8}, rightElbow = {16}, leftArm = {6, 0, -8}, neck = {2, 0, 0}, waist = {0, 0, 0}, root = {0, 0, 0}})},
		{t = 5.8, pose = pose({rightArm = {10, 0, 8}, rightElbow = {14}, leftArm = {6, 0, -8}, neck = {2, -30, 0}, waist = {0, -8, 0}, root = {0, 0, -2}})},
		{t = 8, pose = pose({rightArm = {10, 0, 8}, rightElbow = {14}, leftArm = {6, 0, -8}, neck = {0, 0, 0}, root = {0, 0, 0}})}}},
	-- Lamplighter / keeper: lift the lantern, peer into the dark, lower it.
	lantern = {period = 6, beat = 2.4, keys = {
		{t = 0, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}})},
		{t = 1.6, pose = pose({rightArm = {70, 0, 16}, rightElbow = {44}, neck = {6, 10, 0}, waist = {3, 6, 0}})},
		{t = 2.4, pose = pose({rightArm = {84, 0, 18}, rightElbow = {36}, neck = {10, 16, 0}, waist = {4, 8, 0}})},
		{t = 3.6, pose = pose({rightArm = {66, 0, 16}, rightElbow = {46}, neck = {4, -8, 0}, waist = {2, -4, 0}})},
		{t = 6, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}})}}},
	-- Herald / crier: raise the horn (or scroll) and call, then a sweeping gesture.
	herald = {period = 8, beat = 3.2, keys = {
		{t = 0, pose = pose({rightArm = {20, 0, 8}, rightElbow = {50}})},
		{t = 2.4, pose = pose({rightArm = {96, 0, 6}, rightElbow = {112}, leftArm = {20, 0, -14}, neck = {12, 0, 0}, waist = {6, 0, 0}})},
		{t = 3.2, pose = pose({rightArm = {104, 0, 6}, rightElbow = {116}, leftArm = {60, 0, -48}, leftElbow = {12}, neck = {16, 0, 0}, waist = {8, 0, 0}})},
		{t = 4.4, pose = pose({rightArm = {40, 0, 8}, rightElbow = {60}, leftArm = {74, 0, -54}, leftElbow = {10}, waist = {2, -10, 0}, neck = {4, -12, 0}})},
		{t = 8, pose = pose({rightArm = {20, 0, 8}, rightElbow = {50}})}}},
	-- Auctioneer: read lots aloud from the scroll, the other hand calls bids.
	proclaim = {period = 6, beat = 2.8, keys = {
		{t = 0, pose = pose({rightArm = {44, 0, -6}, rightElbow = {76}, leftArm = {10, 0, -6}, neck = {-10, 0, 0}})},
		{t = 1.8, pose = pose({rightArm = {46, 0, -6}, rightElbow = {78}, leftArm = {70, 0, -18}, leftElbow = {50}, neck = {4, 8, 0}})},
		{t = 2.8, pose = pose({rightArm = {46, 0, -6}, rightElbow = {78}, leftArm = {108, 0, -10}, leftElbow = {30}, neck = {8, 12, 0}, waist = {4, 6, 0}})},
		{t = 4, pose = pose({rightArm = {44, 0, -6}, rightElbow = {76}, leftArm = {24, 0, -8}, leftElbow = {30}, neck = {-8, 0, 0}})},
		{t = 6, pose = pose({rightArm = {44, 0, -6}, rightElbow = {76}, leftArm = {10, 0, -6}, neck = {-10, 0, 0}})}}},
	-- Carpenter: three saw strokes across a plank, then a breath.
	saw = {period = 3.6, beat = 0.6, keys = {
		{t = 0, pose = pose({rightArm = {30, 0, 6}, rightElbow = {72}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-12, 0, 0}, neck = {-20, 0, 0}})},
		{t = 0.3, pose = pose({rightArm = {52, 0, 6}, rightElbow = {28}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-14, -4, 0}, neck = {-22, 0, 0}})},
		{t = 0.6, pose = pose({rightArm = {30, 0, 6}, rightElbow = {72}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-12, 2, 0}, neck = {-20, 0, 0}})},
		{t = 0.9, pose = pose({rightArm = {52, 0, 6}, rightElbow = {28}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-14, -4, 0}, neck = {-22, 0, 0}})},
		{t = 1.2, pose = pose({rightArm = {30, 0, 6}, rightElbow = {72}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-12, 2, 0}, neck = {-20, 0, 0}})},
		{t = 1.5, pose = pose({rightArm = {52, 0, 6}, rightElbow = {28}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-14, -4, 0}, neck = {-22, 0, 0}})},
		{t = 2.2, pose = pose({rightArm = {24, 0, 8}, rightElbow = {60}, leftArm = {10, 0, -8}, leftElbow = {20}, waist = {-2, 0, 0}, neck = {-4, 8, 0}})},
		{t = 3.6, pose = pose({rightArm = {30, 0, 6}, rightElbow = {72}, leftArm = {30, 0, -8}, leftElbow = {56}, waist = {-12, 0, 0}, neck = {-20, 0, 0}})}}},
	-- Druid / mage: staff upright at the side, the free hand drawing a slow circle of power.
	channel = {period = 6, beat = 3, keys = {
		{t = 0, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {40, 0, -20}, leftElbow = {50}, neck = {0, 0, 0}})},
		{t = 1.5, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {62, 0, -34}, leftElbow = {36}, neck = {4, 10, 0}, waist = {0, 6, 0}})},
		{t = 3, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {78, 0, -14}, leftElbow = {26}, neck = {8, 0, 0}, waist = {2, 0, 0}})},
		{t = 4.5, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {56, 0, -4}, leftElbow = {44}, neck = {4, -8, 0}, waist = {0, -6, 0}})},
		{t = 6, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {40, 0, -20}, leftElbow = {50}, neck = {0, 0, 0}})}}},
	-- Runebinder: trace a glyph low across the body (eyes on the hand), then raise it
	-- high overhead, leaning back (two clearly different frames, QC M3), then study it.
	rune = {period = 5, beat = 1.9, keys = {
		{t = 0, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {40, 0, -10}, leftElbow = {60}, neck = {-4, 0, 0}})},
		{t = 0.7, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {58, -30, 30}, leftElbow = {34}, waist = {0, 14, 0}, neck = {-14, 18, 0}})},
		{t = 1.2, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {62, 20, -36}, leftElbow = {28}, waist = {0, -10, 0}, neck = {-10, -14, 0}})},
		{t = 1.9, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {168, 0, -10}, leftElbow = {6}, neck = {20, 0, 0}, waist = {8, 0, 0}})},
		{t = 3, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {50, 0, -12}, leftElbow = {58}, neck = {-10, 0, 0}})},
		{t = 5, pose = pose({rightArm = {6, 0, 10}, rightElbow = {12}, leftArm = {40, 0, -10}, leftElbow = {60}, neck = {-4, 0, 0}})}}},
	-- Miner: pick on the shoulder, a stretch of the back, a tap on the ground.
	mine = {period = 7, beat = 4.6, keys = {
		{t = 0, pose = pose({rightArm = {34, 0, 10}, rightElbow = {104}})},
		{t = 2.2, pose = pose({rightArm = {36, 0, 10}, rightElbow = {106}, leftArm = {150, 0, -20}, leftElbow = {80}, waist = {10, 0, 0}, neck = {14, 0, 0}})},
		{t = 3.4, pose = pose({rightArm = {34, 0, 10}, rightElbow = {104}, waist = {0, 0, 0}})},
		{t = 4.2, pose = pose({rightArm = {60, 0, 12}, rightElbow = {40}, waist = {-10, 0, 0}, neck = {-16, 0, 0}})},
		{t = 4.6, pose = pose({rightArm = {24, 0, 10}, rightElbow = {12}, waist = {-14, 0, 0}, neck = {-20, 0, 0}})},
		{t = 5.4, pose = pose({rightArm = {34, 0, 10}, rightElbow = {104}, waist = {0, 0, 0}})},
		{t = 7, pose = pose({rightArm = {34, 0, 10}, rightElbow = {104}})}}},
	-- Tinker: quick light taps on a work piece held in the left hand.
	tinker = {period = 3, beat = 0.4, keys = {
		{t = 0, pose = pose({rightArm = {50, 0, 6}, rightElbow = {84}, leftArm = {50, 0, -6}, leftElbow = {80}, neck = {-22, 0, 0}, waist = {-4, 0, 0}})},
		{t = 0.25, pose = pose({rightArm = {64, 0, 6}, rightElbow = {100}, rightWrist = {-20, 0, 0}, leftArm = {50, 0, -6}, leftElbow = {80}, neck = {-22, 0, 0}, waist = {-4, 0, 0}})},
		{t = 0.4, pose = pose({rightArm = {50, 0, 6}, rightElbow = {80}, rightWrist = {10, 0, 0}, leftArm = {50, 0, -6}, leftElbow = {80}, neck = {-22, 0, 0}, waist = {-4, 0, 0}})},
		{t = 0.65, pose = pose({rightArm = {64, 0, 6}, rightElbow = {100}, rightWrist = {-20, 0, 0}, leftArm = {50, 0, -6}, leftElbow = {80}, neck = {-22, 0, 0}, waist = {-4, 0, 0}})},
		{t = 0.8, pose = pose({rightArm = {50, 0, 6}, rightElbow = {80}, rightWrist = {10, 0, 0}, leftArm = {50, 0, -6}, leftElbow = {80}, neck = {-22, 0, 0}, waist = {-4, 0, 0}})},
		{t = 1.8, pose = pose({rightArm = {44, 0, 6}, rightElbow = {76}, leftArm = {58, 0, -2}, leftElbow = {96}, neck = {-26, 10, 0}, waist = {-4, 4, 0}})},
		{t = 3, pose = pose({rightArm = {50, 0, 6}, rightElbow = {84}, leftArm = {50, 0, -6}, leftElbow = {80}, neck = {-22, 0, 0}, waist = {-4, 0, 0}})}}},
	-- Shepherd: lean on the crook, a long look over the downs.
	lean = {period = 9, beat = 5, keys = {
		{t = 0, pose = pose({rightArm = {22, 0, 10}, rightElbow = {18}, leftArm = {30, 0, 10}, leftElbow = {70}, waist = {-6, 0, 0}, root = {0, 0, 3}})},
		{t = 3, pose = pose({rightArm = {22, 0, 10}, rightElbow = {18}, leftArm = {30, 0, 10}, leftElbow = {70}, waist = {-6, 10, 0}, neck = {6, 24, 0}, root = {0, 0, 3}})},
		{t = 5, pose = pose({rightArm = {24, 0, 10}, rightElbow = {20}, leftArm = {28, 0, 10}, leftElbow = {68}, waist = {-4, 0, 0}, neck = {4, 0, 0}, root = {0, 0, 2}})},
		{t = 7, pose = pose({rightArm = {22, 0, 10}, rightElbow = {18}, leftArm = {30, 0, 10}, leftElbow = {70}, waist = {-6, -6, 0}, neck = {2, -18, 0}, root = {0, 0, 3}})},
		{t = 9, pose = pose({rightArm = {22, 0, 10}, rightElbow = {18}, leftArm = {30, 0, 10}, leftElbow = {70}, waist = {-6, 0, 0}, root = {0, 0, 3}})}}},
	-- Beaconkeeper (Old Hesketh Ashby): stoop and poke the embers, stir, straighten.
	poke = {period = 5, beat = 1.5, keys = {
		{t = 0, pose = pose({rightArm = {28, 0, 6}, rightElbow = {30}, leftArm = {14, 0, -6}, leftElbow = {40}, waist = {-4, 0, 0}, neck = {-6, 0, 0}})},
		{t = 1.1, pose = pose({rightArm = {46, 0, 4}, rightElbow = {16}, leftArm = {30, 0, -4}, leftElbow = {80}, waist = {-12, 0, 0}, neck = {-10, 0, 0}})},
		{t = 1.5, pose = pose({rightArm = {38, 0, 4}, rightElbow = {8}, rightWrist = {16, 0, 0}, leftArm = {30, 0, -4}, leftElbow = {80}, waist = {-15, 0, 0}, neck = {-12, 0, 0}})},
		{t = 2.2, pose = pose({rightArm = {42, -8, 10}, rightElbow = {14}, leftArm = {30, 0, -4}, leftElbow = {80}, waist = {-14, 6, 0}, neck = {-12, 0, 0}})},
		{t = 2.9, pose = pose({rightArm = {42, 8, 2}, rightElbow = {14}, leftArm = {30, 0, -4}, leftElbow = {80}, waist = {-14, -6, 0}, neck = {-12, 0, 0}})},
		{t = 3.8, pose = pose({rightArm = {26, 0, 6}, rightElbow = {28}, leftArm = {40, 0, -8}, leftElbow = {100}, waist = {4, 0, 0}, neck = {6, 0, 0}})},
		{t = 5, pose = pose({rightArm = {28, 0, 6}, rightElbow = {30}, leftArm = {14, 0, -6}, leftElbow = {40}, waist = {-4, 0, 0}, neck = {-6, 0, 0}})}}},
	-- Wayfinder (Pell): lantern at the side, a friendly wave every loop.
	wave = {period = 7, beat = 2.2, keys = {
		{t = 0, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}})},
		{t = 1.4, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}, leftArm = {150, 0, -28}, leftElbow = {36}, neck = {4, 10, 0}})},
		{t = 1.8, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}, leftArm = {150, 0, -42}, leftElbow = {20}, neck = {4, 12, 0}})},
		{t = 2.2, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}, leftArm = {150, 0, -22}, leftElbow = {40}, neck = {4, 12, 0}})},
		{t = 2.6, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}, leftArm = {150, 0, -40}, leftElbow = {22}, neck = {4, 10, 0}})},
		{t = 3.6, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}, leftArm = {8, 0, -6}, leftElbow = {16}})},
		{t = 7, pose = pose({rightArm = {22, 0, 10}, rightElbow = {40}})}}},
}
S.JOINTS = {"rightArm", "rightElbow", "rightWrist", "leftArm", "leftElbow", "waist", "neck", "root"}
-- Motor (on the townsfolk rig) driven by each joint.
S.MOTORS = {rightArm = "RightShoulder", rightElbow = "RightElbow", rightWrist = "RightWrist", leftArm = "LeftShoulder", leftElbow = "LeftElbow",
	waist = "Waist", neck = "Neck", root = "Root"}
-- Reduced motion keeps the pose but calms the loop toward its first key.
S.REDUCED_AMPLITUDE = 0.35

-- Samples a loop at t (wrapped) into `out` (joint -> {rx, ry, rz}; tables reused).
local function smooth(a) return a * a * (3 - 2 * a) end
function S.sample(name, t, out, calm)
	local loop = S.IDLES[name] or S.IDLES.guard
	out = out or {}
	local keys = loop.keys
	t = t % loop.period
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then a, b = keys[i], keys[i + 1]; break end
	end
	local span = b.t - a.t
	local alpha = if span > 0 then smooth(math.clamp((t - a.t) / span, 0, 1)) else 0
	local first = keys[1].pose
	for _, joint in ipairs(S.JOINTS) do
		local va, vb = a.pose[joint], b.pose[joint]
		local v = out[joint]
		if not v then v = {0, 0, 0}; out[joint] = v end
		for k = 1, 3 do
			local x = (va and va[k] or 0)
			local y = (vb and vb[k] or 0)
			local value = x + (y - x) * alpha
			if calm then
				local base = first[joint] and first[joint][k] or 0
				value = base + (value - base) * S.REDUCED_AMPLITUDE
			end
			v[k] = value
		end
	end
	return out
end
-- Animation level of detail by distance: 2 = 30 Hz, 1 = 15 Hz, 0 = off.
S.ANIM_RANGE = {desktop = {full = 45, half = 90}, phone = {full = 25, half = 55}}
S.DRESS_RANGE = {desktop = 90, phone = 50} -- forged outfits within this many studs
S.DRESS_CAP = {desktop = 14, phone = 4} -- most NPCs dressed in meshes at once (nearest win)
-- Outfit pool the dressed sets must fit (forge.client.lua OUTFIT_*; verify-npcart sums the
-- distinct templates of the worst-case dressed set per region against both).
S.POOL = {desktop = {templates = 52, triangles = 52000}, phone = {templates = 18, triangles = 20000}}
-- Most NPCs animated at once (nearest win; QC L), re-ranked every 0.5 s.
S.ANIM_CAP = {desktop = 18, phone = 8}
function S.lod(distance, phone)
	local r = if phone then S.ANIM_RANGE.phone else S.ANIM_RANGE.desktop
	if distance <= r.full then return 2 elseif distance <= r.half then return 1 end
	return 0
end

------------------------------------------------------------------------------
-- Nameplate (server BillboardGui "Nameplate"): a dark rounded strip (distinct
-- from the Signs v2 plaques) with a region accent bar and a trade medallion.
-- Contrast >= 4.5:1 for every label on its named field (Signs v2 rule), one
-- outline per label, Builder Sans (never Gotham), >= 10 px.
------------------------------------------------------------------------------
S.PLATE = {width = 252, height = 58, nameSize = 17, titleSize = 13, maxDistance = 60, field = "111822",
	nameColor = "FFE6A6", stroke = "05080C", fontName = "BuilderSansExtraBold", fontTitle = "BuilderSansBold", minPx = 10, minContrast = 4.5,
	-- QC M1: the billboard is sized in studs and the plate clamped in pixels, so it
	-- shrinks with distance down to a legible floor (never a fixed pixel slab).
	studs = {4.6, 1.06}, minSize = {196, 45},
	-- Phones: a smaller plate seen from nearer (npc.client.lua applies it locally).
	phone = {maxDistance = 40, maxSize = {210, 48}, minSize = {176, 40}},
	-- Cues in pixels around the plate: the CLICK row under it, the quest marker above.
	clickGap = 3, markerGap = 6, markerSize = 34}
-- Pixel layout around the billboard's anchor (the plate is centred on it): the
-- plate's half height never exceeds height / 2, the CLICK row sits under it, and
-- the quest marker (its own billboard, SizeOffset in units of its size) above.
S.CLICK_ROW = 18
function S.markerShift()
	local px = S.PLATE.height / 2 + S.PLATE.markerGap + S.PLATE.markerSize / 2
	return px / S.PLATE.markerSize, px
end
-- Rects (centre y, half height; pixels, +y up from the anchor) at k px per stud.
function S.plateLayout(k, phone)
	local P = S.PLATE
	local maxH = if phone then P.phone.maxSize[2] else P.height
	local minH = if phone then P.phone.minSize[2] else P.minSize[2]
	local boardH = P.studs[2] * k + P.minSize[2] + 2 * S.CLICK_ROW
	local plateH = math.clamp(boardH - 2 * S.CLICK_ROW, minH, maxH)
	local _, shift = S.markerShift()
	return {plate = {0, plateH / 2}, click = {-(plateH / 2 + P.clickGap + (S.CLICK_ROW - P.clickGap) / 2), (S.CLICK_ROW - P.clickGap) / 2},
		marker = {shift, P.markerSize / 2}, plateH = plateH}
end
-- Extra lift (studs) over tall hats so the plate clears the crown.
S.PLATE_LIFT = {HatTop = 0.55, HatMage = 0.7, HatHelm = 0.3, HatWayfarer = 0.25, HatStraw = 0.2, HatFeather = 0.2}
local function mix(hex, other, k)
	local r1, g1, b1 = channels(hex)
	local r2, g2, b2 = channels(other)
	return string.format("%02X%02X%02X", math.floor((r1 + (r2 - r1) * k) * 255 + 0.5), math.floor((g1 + (g2 - g1) * k) * 255 + 0.5), math.floor((b1 + (b2 - b1) * k) * 255 + 0.5))
end
-- The title takes the region accent, lightened until it reads on the field.
function S.titleColor(accent)
	local c = accent
	for _ = 1, 10 do
		if S.contrast(c, S.PLATE.field) >= S.PLATE.minContrast then return c end
		c = mix(c, "FFFFFF", 0.2)
	end
	return "FFFFFF"
end
function S.plate(role, def)
	local outfit = S.outfit(role, def)
	local region = S.REGIONS[outfit.region] or S.REGIONS.Hub
	local trade = S.TRADES[outfit.trade] or S.TRADES.guide
	local hatShape = outfit.hat and S.HATS[outfit.hat]
	return {name = def and def.name or role, title = def and def.title or "", accent = region.accent, titleColor = S.titleColor(region.accent),
		nameColor = S.PLATE.nameColor, field = S.PLATE.field, motif = trade.motif, regionName = region.name,
		lift = 2.4 + (hatShape and S.PLATE_LIFT[hatShape] or 0)}
end
return S
