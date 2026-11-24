-- §52 item icons (shared/UiTheme.lua): every Data.Items id resolves, by data
-- alone, to a non-fallback icon family with an authored motif; new items of any
-- known kind fall in automatically; weapon / armour / tool families agree with
-- Data.Held; rarity colours follow Data.Rarity; the template cache reuses built
-- icons and stays bounded (phones smaller); live viewports are bounded; the
-- satchel, atlas and hotbar draw these icons (no initials or text glyphs);
-- nothing in an icon animates (reduced motion).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local H = require("./tools/ui-harness")

local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(a, b, case) assert(a == b, case .. ": expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local Data = H.Data
local Items = Data.Items
local env = {Instance = {new = function(class) return H.new(class) end}, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
	Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint}
local T = H.loadTheme(env)
T.useItems(Items)

------------------------------------------------------------------------------
-- 1. Coverage: every item → a non-fallback family with a motif
------------------------------------------------------------------------------
local part1 = checks
local ids = {}
for id in pairs(Items) do table.insert(ids, id) end
table.sort(ids)
local rules, families, generic, materials = {}, {}, 0, 0
for _, id in ipairs(ids) do
	local def = Items[id]
	local spec = T.iconSpec(def, Items)
	ok(spec.rule ~= "fallback", id .. " resolves to a non-fallback icon (" .. spec.family .. ")")
	local motif = T.ICON_MOTIFS[spec.family]
	ok(motif ~= nil, id .. " family " .. spec.family .. " has a motif")
	rules[spec.rule] = (rules[spec.rule] or 0) + 1
	families[spec.family] = (families[spec.family] or 0) + 1
	if def.kind == "material" then
		materials += 1
		if spec.rule == "kind" then generic += 1 end
	end
	eq(spec.rarity, def.rarity or "Common", id .. " rarity carried")
	ok(spec.key ~= nil and has(spec.key, spec.family), id .. " cache key")
end
ok(generic <= math.max(2, math.floor(materials * 0.03)), "at most 3% of materials use the kind's generic default (" .. generic .. "/" .. materials .. ")")
local familyCount = 0
for _ in pairs(families) do familyCount += 1 end
ok(familyCount >= 70, "items spread over many families (" .. familyCount .. ")")
-- Motifs: bounded layer counts, known tones, layer geometry inside the box.
local tones = T.iconTones({color = "336699"})
for family, layers in pairs(T.ICON_MOTIFS) do
	ok(#layers >= 3 and #layers <= T.ICON_LAYER_MAX, family .. " has 3.." .. T.ICON_LAYER_MAX .. " layers (" .. #layers .. ")")
	local lit = 0
	for _, L in ipairs(layers) do
		ok(tones[L[6]] ~= nil or L[6] == "rarity", family .. " tone " .. tostring(L[6]))
		ok(L[1] >= -0.05 and L[1] <= 1.05 and L[2] >= -0.05 and L[2] <= 1.05 and L[3] > 0 and L[4] > 0, family .. " layer inside the icon box")
		local flags = L[8] or {}
		if not flags.g and not flags.ring and not flags.soft then lit += 1 end
	end
	ok(lit >= 2, family .. " has at least two lit (gradient) layers: never flat")
end
-- Spot checks across kinds.
local expect = {Ore = "ore", SunsteelOre = "ore", Aetherite = "crystal", BrassIngot = "bar", StarmetalIngot = "bar", Timber = "log", StarwoodLog = "log",
	Sunwheat = "crop", SunwheatSeeds = "seed", Fish = "fish", CookedFish = "cooked", GrousePie = "pie", Tonic = "potion", EmberRune = "rune",
	SparkGlyph = "glyph", Skyjade = "gem", RoughSkyjade = "roughgem", DewquartzRing = "ring", SkyjadeAmulet = "amulet", EverwakeLantern = "lantern",
	StarlightCrown = "crown", EmberfoxPet = "pet", TrailCasketElite = "casket", WarpScrollHub = "scroll", SmallPouch = "pouch", BrassArrow = "arrow",
	BrassHeads = "arrowhead", CuredLeather = "leather", SpiderSilk = "thread", StormFeather = "feather", ArcaneDust = "dust", VoidEssence = "essence",
	GolemCore = "core", FlintStriker = "striker", BoxTrap = "trap", WorkerCoffer = "coffer"}
for id, family in pairs(expect) do
	if Items[id] then eq(T.iconSpec(Items[id], Items).family, family, id .. " family") end
end
-- Gear families agree with the held-item classes (Data.Held) and armour slots.
local HELD = {sword = "sword", greatblade = "greatblade", dagger = "dagger", maul = "maul", glaive = "glaive", shortbow = "bow", longbow = "bow", staff = "staff", wand = "wand",
	pickaxe = "pickaxe", hatchet = "hatchet", rod = "rod", hoe = "hoe", hammer = "hammer"}
for _, id in ipairs(ids) do
	local def = Items[id]
	local spec = T.iconSpec(def, Items)
	if (def.kind == "weapon" or def.kind == "tool") and Data.Held and Data.Held.classOf(def) then
		eq(spec.family, HELD[Data.Held.classOf(def)], id .. " icon matches its held class " .. Data.Held.classOf(def))
	end
	if def.kind == "armor" then eq(spec.family, T.ICON_SLOT[def.slot], id .. " icon matches its slot") end
	if string.sub(id, 1, 9) == "Condensed" or string.sub(id, 1, 7) == "Radiant" then
		ok(spec.modifier ~= nil, id .. " is a compressed material")
		local base = Items[string.gsub(string.gsub(id, "^Condensed", ""), "^Radiant", "")]
		if base then eq(spec.family, T.iconSpec(base, Items).family, id .. " keeps its base item's family") end
	end
end
print("PASS: coverage of " .. #ids .. " items over " .. familyCount .. " families (" .. (checks - part1) .. ")")

------------------------------------------------------------------------------
-- 2. Data-driven: new items (another team's Skysailing content) fall in
------------------------------------------------------------------------------
local part2 = checks
local newcomers = {
	{id = "SkysailCanvas", kind = "material", color = "E9DFC7"}, {id = "GaleRiggingKit", kind = "material", color = "8A6A3B"},
	{id = "CloudkeelIngot", kind = "material", color = "B8C6CF"}, {id = "SkysailHelm", kind = "armor", slot = "helmet", color = "6E7BFF"},
	{id = "WindreaverBlade", kind = "weapon", name = "Windreaver Blade", color = "D8E6F0"}, {id = "SkiffHarpoon", kind = "weapon", name = "Skiff Spear", color = "9FB4C8"},
	{id = "GaleBow", kind = "weapon", style = "ranged", name = "Gale Bow", color = "C99A62"}, {id = "SkysailRod", kind = "tool", toolKind = "Rod", color = "8B5A2B"},
	{id = "DeckhandRation", kind = "consumable", category = "food", color = "C98A4A"}, {id = "UpdraftElixir", kind = "consumable", category = "potion", color = "9FE6F2"},
	{id = "CloudwhaleCalf", kind = "pet", color = "BFE3FF"}, {id = "Skyfin", kind = "resource", skill = "Fishing", color = "7FE0E8"},
	{id = "SailmakersCharm", kind = "accessory", color = "F2C14E"}, {id = "StormsailBanner", kind = "trail", category = "banner", color = "1F2F4F"},
	{id = "CondensedSkyfin", kind = "material", category = "condensed", color = "7FE0E8"},
}
local extended = table.clone(Items)
extended.Skyfin = newcomers[12]
for _, def in ipairs(newcomers) do
	local spec = T.iconSpec(def, extended)
	ok(spec.rule ~= "fallback" and T.ICON_MOTIFS[spec.family] ~= nil, def.id .. " (a new " .. def.kind .. ") gets a real icon: " .. spec.family)
end
eq(T.iconSpec(newcomers[4], extended).family, "helmet", "a new helmet")
eq(T.iconSpec(newcomers[5], extended).family, "sword", "a new blade")
eq(T.iconSpec(newcomers[6], extended).family, "glaive", "a new spear by name")
eq(T.iconSpec(newcomers[7], extended).family, "bow", "a new bow by style")
eq(T.iconSpec(newcomers[3], extended).family, "bar", "a new ingot by keyword")
eq(T.iconSpec(newcomers[15], extended).family, "fish", "a new compressed fish keeps the fish")
eq(T.iconSpec(newcomers[15], extended).modifier, "condensed", "and wears the compressed block")
eq(T.iconSpec({id = "Mystery", kind = "starship"}, extended).rule, "fallback", "an unknown kind is the only fallback")
eq(T.iconSpec(nil).rule, "fallback", "a missing def falls back")
print("PASS: data-driven rules (" .. (checks - part2) .. ")")

------------------------------------------------------------------------------
-- 3. Rarity colours (Data.Rarity), halo, gear gem, locked veil
------------------------------------------------------------------------------
local part3 = checks
local function hue(c)
	local h = c:ToHSV()
	return h * 360
end
for _, rarity in ipairs(Data.RarityOrder) do
	local dataHex = Data.Rarity[rarity]
	dataHex = if type(dataHex) == "table" then (dataHex.color or dataHex.hex) else dataHex
	local themeColor = T.rarity(rarity).color
	local dataColor = roblox.Color3.fromHex(dataHex)
	local _, s = dataColor:ToHSV()
	if s > 0.1 then
		local d = math.abs(hue(themeColor) - hue(dataColor))
		d = math.min(d, 360 - d)
		ok(d <= 25, string.format("%s icon colour follows Data.Rarity's hue (%.0f deg apart)", rarity, d))
	else
		local _, ts = themeColor:ToHSV()
		ok(ts <= 0.1, rarity .. " stays neutral")
	end
end
local function count(root, name)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do if d.Name == name then n += 1 end end
	return n
end
local root = H.new("Frame")
local sword, ore = Items.SunsteelSword, Items.Ore
local mythic
for _, id in ipairs(ids) do if Items[id].kind == "weapon" and Items[id].rarity == "Mythic" then mythic = Items[id]; break end end
local swordIcon = T.icon(root, sword, 40)
eq(swordIcon:GetAttribute("Shape"), "sword", "sword icon")
eq(count(swordIcon, "RarityHalo"), 1, "a Rare sword sits on a rarity halo")
eq(count(swordIcon, "RarityGem"), 1, "gear wears the rarity gem")
local oreIcon = T.icon(root, ore, 40)
eq(count(oreIcon, "RarityHalo"), 0, "a Common ore has no halo")
eq(count(oreIcon, "RarityGem"), 0, "materials have no gear gem")
local gem = nil
for _, d in ipairs(T.icon(root, mythic, 40):GetDescendants()) do if d.Name == "RarityGem" then gem = d end end
ok(gem ~= nil, "mythic gem")
local function grad(f) for _, c in ipairs(f:GetChildren()) do if c.ClassName == "UIGradient" then return c end end return nil end
ok(grad(gem) ~= nil and gem.BackgroundColor3 == roblox.Color3.new(1, 1, 1), "the gem is lit by a gradient in the rarity colour")
local radiant = T.icon(root, Items.RadiantOre, 44)
ok(count(radiant, "Compressed") == 1 and count(radiant, "Radiance") == 1 and count(radiant, "Spark") == 1, "Radiant materials glow on a compressed block")
local slot = T.slot(root, {size = 44})
T.setSlot(slot, {id = "Ore", def = ore, count = 3, locked = true})
ok(slot:FindFirstChild("Icon"):FindFirstChild("Veil").Visible, "locked items wear the veil")
T.setSlot(slot, {id = "Ore", def = ore, count = 3})
ok(not slot:FindFirstChild("Icon"):FindFirstChild("Veil").Visible, "the veil lifts")
-- Instance budget per icon (a satchel page is 28 of these).
local biggest = 0
for family in pairs(T.ICON_MOTIFS) do
	local def
	for _, id in ipairs(ids) do if T.iconSpec(Items[id], Items).family == family then def = Items[id]; break end end
	if def then
		local icon = T.buildIcon(def, 44)
		biggest = math.max(biggest, #icon:GetDescendants())
	end
end
ok(biggest <= 60, "an icon is at most 60 GUI instances (" .. biggest .. ")")
ok(biggest * 28 <= 1700, "a satchel page of icons stays under 1,700 instances")
print("PASS: rarity, halo, gem, veil, instance budget (" .. (checks - part3) .. ")")

------------------------------------------------------------------------------
-- 4. Cache reuse and bounds; viewport budget
------------------------------------------------------------------------------
local part4 = checks
local T2 = H.loadTheme(env)
T2.useItems(Items)
local page = {"Ore", "SunsteelOre", "Timber", "StarwoodLog", "Fish", "Glassfin", "Sunwheat", "Moonbloom", "BrassIngot", "StarmetalIngot", "CookedFish", "GrousePie",
	"Tonic", "TitanBrew", "EmberRune", "AstralRune", "SparkGlyph", "Skyjade", "SunsteelSword", "EmberoakWand", "SunsteelRod", "BrassHelm", "BrassBoots",
	"DewquartzRing", "EverwakeLantern", "EmberfoxPet", "TrailCasketElite", "SmallPouch"}
local function satchelRefresh()
	local panel = H.new("Frame")
	for _, id in ipairs(page) do
		local s = T2.slot(panel, {size = 44})
		T2.setSlot(s, {id = id, def = Items[id], count = 5})
	end
	return panel
end
local first = satchelRefresh()
local builds = T2.IconCache.builds
eq(builds, #page, "the first satchel page builds each icon once")
first:Destroy()
satchelRefresh()
eq(T2.IconCache.builds, builds, "a refresh rebuilds nothing (cached templates)")
eq(T2.IconCache.clones, #page, "every icon of the refresh is a clone")
-- Same item, same slot: setSlot keeps the icon instance.
local panel = H.new("Frame")
local s1 = T2.slot(panel, {size = 44})
T2.setSlot(s1, {id = "Ore", def = Items.Ore, count = 1})
local icon1 = s1:FindFirstChild("Icon")
T2.setSlot(s1, {id = "Ore", def = Items.Ore, count = 99})
ok(s1:FindFirstChild("Icon") == icon1, "a count change keeps the icon instance")
-- Bounded: far more distinct icons than the cap evict least recently used.
local T3 = H.loadTheme(env)
T3.useItems(Items)
for i = 1, T3.IconCache.max + 40 do T3.icon(nil, Items[ids[(i - 1) % #ids + 1]], 30 + (i % 3)) end
ok(T3.IconCache.count <= T3.IconCache.max, "desktop cache bounded (" .. T3.IconCache.count .. ")")
ok(T3.IconCache.evictions > 0, "older templates evicted (LRU)")
T3.iconCacheCompact(true)
T3.icon(nil, Items.Ore, 77)
ok(T3.IconCache.count <= T3.IconCache.compactMax, "phones keep a smaller cache (" .. T3.IconCache.count .. " <= " .. T3.IconCache.compactMax .. ")")
ok(T3.IconCache.compactMax < T3.IconCache.max, "compact cap below desktop")
-- Viewports: only big previews, bounded per page and device.
ok(not T.iconViewportAllowed(44, 0, false), "a 44 px satchel slot never gets a live viewport")
ok(not T.iconViewportAllowed(40, 0, false) and not T.iconViewportAllowed(55, 0, false), "under 56 px: vector icons only")
ok(T.iconViewportAllowed(64, 0, false) and not T.iconViewportAllowed(64, T.ICON_VIEWPORTS.desktop, false), "desktop viewport cap")
ok(T.iconViewportAllowed(64, 0, true) and not T.iconViewportAllowed(64, T.ICON_VIEWPORTS.compact, true), "phone viewport cap")
ok(T.ICON_VIEWPORTS.compact < T.ICON_VIEWPORTS.desktop and T.ICON_VIEWPORTS.desktop <= 8, "viewport budget is small")
print("PASS: cache reuse and budgets (" .. (checks - part4) .. ")")

------------------------------------------------------------------------------
-- 5. Wiring: satchel, atlas, hotbar, tooltips; no animation in icons
------------------------------------------------------------------------------
local part5 = checks
local theme = fs.readFile("shared/UiTheme.lua")
local iconSection = string.sub(theme, (string.find(theme, "-- §52 item icons", 1, true)), (string.find(theme, "-- Item slot: well + rarity border", 1, true)))
ok(#iconSection > 5000, "the icon renderer lives in the shared theme")
ok(not has(iconSection, "Tween") and not has(iconSection, "RenderStepped") and not has(iconSection, "Heartbeat"), "icons never animate (reduced motion safe, no per-frame work)")
ok(not has(iconSection, "ImageLabel") and not has(iconSection, "rbxasset"), "no uploaded images: frames, gradients and strokes only")
local ui = fs.readFile("ui.client.lua")
ok(has(ui, "UI.T.iconViewportAllowed(size,thumbnailCount,THUMBS.compact)"), "the atlas asks the viewport budget before a 3D thumbnail")
ok(has(ui, "UI.T.icon(holder,def or {id=tostring(id),name=tostring(id)},math.floor(size*.86))"), "the atlas falls back to the vector icon, not initials")
ok(has(ui, "UI.T.useItems(result.Items)") and has(ui, "UI.T.iconCacheCompact(compactAtlas)"), "the atlas shares Data.Items and the phone cache size")
local hud = fs.readFile("hud.client.lua")
ok(has(hud, "T.useItems(Data.Items)") and has(hud, "T.iconCacheCompact(L.short)"), "the satchel (hud.client.lua) shares Data.Items and the phone cache size")
local hotbar = fs.readFile("hotbar.client.lua")
ok(has(hotbar, "pcall(IconTheme.icon, b, def,") and has(hotbar, 'b:GetAttribute("IconItem") ~= (id or "")'), "the hotbar draws vector icons, rebuilt only when the item changes")
ok(has(hotbar, "glyph.Visible = not (IconTheme and def and b:FindFirstChild(\"Icon\"))"), "the hotbar's text glyph is only the fallback")
local overlay = fs.readFile("overlay.client.lua")
ok(has(overlay, "T.setSlot("), "the pickup feed uses Theme slots (vector icons)")
for _, script in ipairs({"scripts/build.sh", "build.ps1"}) do ok(has(fs.readFile(script), "verify-icons.luau"), script .. " runs verify-icons") end
ok(fs.isFile("tools/render-icons.luau") and fs.isFile("docs/screenshots/icons-families.png") and fs.isFile("docs/screenshots/icons-satchel.png"), "icon previews")
print("PASS: wiring (" .. (checks - part5) .. ")")

local ruleList = {}
for rule, n in pairs(rules) do table.insert(ruleList, rule .. " " .. n) end
table.sort(ruleList)
print(string.format("Item icon QA passed %d checks: %d items, %d families (%s).", checks, #ids, familyCount, table.concat(ruleList, ", ")))
print("SUITE-END verify-icons.luau")
