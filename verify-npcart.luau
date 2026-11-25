-- §52 NPC art: every named townsperson has an outfit spec (forged smooth pieces
-- from art/OutfitCatalog.lua, dyes, region colours) and a trade idle loop
-- (shared/NpcStyle.lua) inside animate.client.lua's joint limits; the outfit
-- meshes pass the §48 facet / segment checks; the MeshForge outfit pool; the
-- server rig's fallback tags and polished nameplate (contrast, fonts, outlines,
-- sizes, lift over tall hats); the client renderer's source rules (local hiding,
-- caps, reduced motion, phones, players untouched); previews and wiring.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function eq(a, b, case) assert(a == b, case .. ": expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

local Data = load("shared/GameData.lua")
local S = load("shared/NpcStyle.lua")
local Outfits = load("art/OutfitCatalog.lua")
local World = load("art/WorldCatalog.lua")
local Core
load("animate.client.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, __GestureTestHarness = function(exports) Core = exports end})
assert(Core and Core.JOINT_LIMITS, "animate.client.lua harness")
local T = Data.Townsfolk
local ROSTER = table.clone(T.Order)
for _, role in ipairs(T.RegionFolkOrder) do table.insert(ROSTER, role) end

------------------------------------------------------------------------------
-- 1. Every NPC has an outfit spec and an idle loop
------------------------------------------------------------------------------
local part1 = checks
local BONE_SLOT = {Head = "head", UpperTorso = "torso", RightHand = "hand"}
local signatures, silhouettes = {}, {}
for _, role in ipairs(ROSTER) do
	local def = T.NPCs[role]
	local spec, explicit = S.roleSpec(role, def)
	ok(explicit, role .. " (" .. def.name .. ") has an explicit NpcStyle.ROLES entry")
	ok(S.TRADES[spec.trade] ~= nil, role .. " trade " .. tostring(spec.trade))
	local outfit = S.outfit(role, def)
	ok(S.IDLES[outfit.idle] ~= nil, role .. " idle loop " .. tostring(outfit.idle))
	ok(#outfit.pieces >= 3, role .. " wears at least three forged pieces (" .. #outfit.pieces .. ")")
	local slots = {}
	for _, piece in ipairs(outfit.pieces) do
		local data = Outfits.shapes[piece.shape]
		ok(data ~= nil and data.kind == "outfit", role .. " piece " .. piece.shape .. " is an authored outfit mesh")
		eq(data and data.slot, BONE_SLOT[piece.bone], role .. " " .. piece.shape .. " is authored around its bone")
		ok(piece.dye == nil or table.find(S.DYES, piece.dye) ~= nil, role .. " " .. piece.shape .. " dye is quantised")
		ok(type(piece.at) == "table" and #piece.at == 3 and type(piece.rot) == "table" and #piece.rot == 3 and piece.k > 0, role .. " " .. piece.shape .. " frame")
		ok(not slots[piece.slot], role .. " one piece per slot (" .. piece.slot .. ")")
		slots[piece.slot] = true
	end
	ok(slots.hat and slots.held, role .. " has a forged hat / hood / helm and a trade prop")
	local torso = 0
	for _, slot in ipairs({"cape", "apron", "mantle", "satchel", "tabard", "belt", "scarf"}) do if slots[slot] then torso += 1 end end
	ok(torso >= 1, role .. " has a layered torso piece (cloak, apron, mantle, satchel, tabard, belt or scarf)")
	local sig = S.signature(outfit)
	ok(not signatures[sig], role .. " outfit is distinct (" .. sig .. ")")
	signatures[sig] = role
	local look = def.look
	local silhouette = sig .. "|" .. look.shirt .. "|" .. look.pants
	ok(not silhouettes[silhouette], role .. " distinct look")
	silhouettes[silhouette] = true
end
-- Named NPCs from the brief keep their trade identity.
local function outfitOf(role) return S.outfit(role, T.NPCs[role]) end
local function wears(outfit, shape) for _, p in ipairs(outfit.pieces) do if p.shape == shape then return p end end return nil end
local maelis = outfitOf("Runebinder")
eq(T.NPCs.Runebinder.name, "Maelis Quillstone", "Runebinder is Maelis Quillstone")
ok(maelis.idle == "rune" and wears(maelis, "HatMage") and wears(maelis, "PropStaff") and wears(maelis, "Mantle"), "Maelis Quillstone: mage hat, rune staff, mantle, glyph tracing")
local pell = outfitOf("Guide")
ok(has(T.NPCs.Guide.name, "Pell") and pell.idle == "wave" and wears(pell, "HatWayfarer") and wears(pell, "PropLantern") and wears(pell, "Cloak"), "Pell: wayfarer's hat, lantern, cloak, waves")
local oriel = outfitOf("Resonator")
ok(has(T.NPCs.Resonator.name, "Oriel") and oriel.idle == "channel" and wears(oriel, "PropStaff"), "Oriel channels resonance through a staff")
local hesketh = outfitOf("Beaconkeeper")
ok(T.NPCs.Beaconkeeper.name == "Old Hesketh Ashby" and hesketh.idle == "poke" and wears(hesketh, "PropPoker") and wears(hesketh, "Apron"), "Old Hesketh Ashby pokes the embers")
ok(outfitOf("Forgemaster").idle == "hammer" and wears(outfitOf("Forgemaster"), "PropHammer") and wears(outfitOf("Forgemaster"), "Apron"), "the smith hammers")
ok(outfitOf("Fisher").idle == "cast" and wears(outfitOf("Fisher"), "PropRod"), "the angler casts")
for _, role in ipairs({"StormScribe", "CrownArchivist", "Astronomer"}) do ok(outfitOf(role).idle == "read" and wears(outfitOf(role), "PropTome"), role .. " the scholar reads") end
for _, role in ipairs(ROSTER) do
	local o = outfitOf(role)
	if T.NPCs[role].shop or (Data.RegionArt and Data.RegionArt.FolkByRole[role] and Data.RegionArt.FolkByRole[role].shop) then
		ok(o.idle ~= nil and #o.pieces >= 3, role .. " shopkeeper dressed")
	end
end
-- Region palettes: every region an NPC lives in has an accent and a dye; the
-- region-dyed pieces (tabards, mantles) take that dye.
for _, role in ipairs(ROSTER) do
	local def = T.NPCs[role]
	local region = S.REGIONS[def.region]
	ok(region ~= nil and region.accent and region.dye, role .. " region " .. tostring(def.region) .. " palette")
	for _, p in ipairs(outfitOf(role).pieces) do
		if p.slot == "tabard" or (p.slot == "mantle" and not (def.look.cape and false)) then eq(p.dye, S.dye(region.dye), role .. " " .. p.slot .. " in the region dye") end
	end
end
-- Data-driven fallback: a role added later still gets a trade by what it holds.
local later = S.outfit("SkyDeckhand", {name = "Test Deckhand", region = "Hub", look = {skin = "E0AC69", shirt = "2F6F6A", pants = "33404A", shoes = "5A3B26", accent = "F9CC77", hair = "7A4A2A", hat = "cap", held = "rod"}})
ok(later.trade == "angler" and later.idle == "cast" and #later.pieces >= 2, "an unlisted role falls back by its held prop")
-- Server fallback styles exist for every new hat / prop.
local OLD_HATS = {wayfarer = true, tophat = true, cap = true, goggles = true, helm = true, souwester = true, tricorn = true, feather = true, hood = true, minerhelm = true, none = true}
local OLD_HELD = {lantern = true, ledger = true, crate = true, hammer = true, sword = true, rod = true, scroll = true, horn = true, saw = true, staff = true, pickaxe = true}
for _, role in ipairs(ROSTER) do
	ok(OLD_HATS[S.fallbackHat(role, T.NPCs[role]) or "none"], role .. " fallback hat style exists on the server rig")
	ok(OLD_HELD[S.fallbackHeld(role, T.NPCs[role])], role .. " fallback prop exists on the server rig")
end
print("PASS: outfits for " .. #ROSTER .. " townsfolk (" .. (checks - part1) .. ")")

------------------------------------------------------------------------------
-- 2. Idle loops: joint limits, seamless, continuous, reduced motion, no allocation
------------------------------------------------------------------------------
local part2 = checks
local used = {}
for _, role in ipairs(ROSTER) do used[outfitOf(role).idle] = true end
for name, loop in pairs(S.IDLES) do
	ok(used[name], name .. " loop is used by someone")
	local keys = loop.keys
	ok(#keys >= 4 and keys[1].t == 0 and math.abs(keys[#keys].t - loop.period) < 1e-9, name .. " keys span the period")
	for i = 2, #keys do ok(keys[i].t > keys[i - 1].t, name .. " key times increase") end
	ok(loop.beat > 0 and loop.beat < loop.period, name .. " beat inside the loop")
	-- Seamless: the last key repeats the first.
	for joint, v in pairs(keys[1].pose) do
		local w = keys[#keys].pose[joint]
		ok(w and w[1] == v[1] and w[2] == v[2] and w[3] == v[3], name .. " loops seamlessly at " .. joint)
	end
	for _, key in ipairs(keys) do
		for joint, v in pairs(key.pose) do
			local limits = Core.JOINT_LIMITS[joint]
			ok(limits ~= nil and S.MOTORS[joint] ~= nil, name .. " joint " .. joint .. " is a known motor")
			for axis = 1, 3 do
				local value = v[axis] or 0
				ok(value >= limits[axis][1] - 1e-9 and value <= limits[axis][2] + 1e-9, string.format("%s %s axis %d = %.1f within animate's JOINT_LIMITS", name, joint, axis, value))
			end
		end
	end
	-- Continuity: no joint moves more than 12 degrees between 30 Hz samples (360 deg/s; taps and strikes snap, nothing teleports).
	local prev = nil
	local buf = {}
	local steps = math.ceil(loop.period * 30)
	local maxStep = 0
	for i = 0, steps do
		local p = S.sample(name, i / 30, buf)
		if prev then
			for joint, v in pairs(p) do
				for axis = 1, 3 do maxStep = math.max(maxStep, math.abs(v[axis] - prev[joint][axis])) end
			end
		end
		prev = prev or {}
		for joint, v in pairs(p) do prev[joint] = prev[joint] or {}; for axis = 1, 3 do prev[joint][axis] = v[axis] end end
	end
	ok(maxStep <= 12, string.format("%s moves smoothly (max %.2f deg per frame)", name, maxStep))
	-- Wraps: t and t + period sample the same pose.
	local a, b = S.sample(name, 1.234, {}), S.sample(name, 1.234 + loop.period, {})
	for joint, v in pairs(a) do for axis = 1, 3 do ok(math.abs(v[axis] - b[joint][axis]) < 1e-6, name .. " wraps at the period") end end
	-- Reduced motion: the loop is calmed toward its first key.
	local full, calm = S.sample(name, loop.beat, {}), S.sample(name, loop.beat, {}, true)
	for joint, v in pairs(full) do
		local base = keys[1].pose[joint] or {0, 0, 0}
		for axis = 1, 3 do
			local d, dc = math.abs(v[axis] - (base[axis] or 0)), math.abs(calm[joint][axis] - (base[axis] or 0))
			ok(dc <= d * S.REDUCED_AMPLITUDE + 1e-6, name .. " reduced motion calms " .. joint)
		end
	end
	-- No allocation: the same buffer and joint tables are reused.
	local out = {}
	local first = S.sample(name, 0.5, out)
	local tables = {}
	for joint, v in pairs(first) do tables[joint] = v end
	local second = S.sample(name, 1.5, out)
	ok(first == second and first == out, name .. " samples into the caller's table")
	for joint, v in pairs(second) do ok(tables[joint] == v, name .. " reuses the joint table " .. joint) end
end
-- Trade identity of the motion itself.
local function at(name, t) return S.sample(name, t, {}) end
ok(at("hammer", 0.55).rightArm[1] > 100 and at("hammer", S.IDLES.hammer.beat).rightArm[1] < 60, "smith: the hammer rises over the shoulder, then strikes on the beat")
ok(at("cast", 2.8).rightWrist[1] < 0 and at("cast", S.IDLES.cast.beat).rightWrist[1] > 0, "angler: wrist cocks then flicks the rod tip")
ok(at("read", 0).neck[1] <= -18, "scholar: eyes down on the page")
ok(at("read", 4.3).leftArm[3] > at("read", 0).leftArm[3], "scholar: the left hand turns a page")
ok(at("poke", S.IDLES.poke.beat).waist[1] <= -12, "beaconkeeper: stoops to the embers")
ok(at("wave", 1.8).leftArm[1] >= 140, "wayfinder: a raised waving hand")
ok(at("rune", S.IDLES.rune.beat).leftArm[1] >= 90, "runebinder: traces the glyph high")
ok(at("herald", S.IDLES.herald.beat).rightArm[1] >= 100, "herald: the horn to the lips")
-- LOD rules.
eq(S.lod(10, false), 2, "full rate up close"); eq(S.lod(60, false), 1, "half rate at mid range"); eq(S.lod(200, false), 0, "off far away")
ok(S.lod(40, true) < S.lod(40, false), "phones step down sooner")
ok(S.DRESS_CAP.phone < S.DRESS_CAP.desktop and S.DRESS_RANGE.phone < S.DRESS_RANGE.desktop, "phones dress fewer, nearer NPCs")
print("PASS: idle loops (" .. (checks - part2) .. ")")

------------------------------------------------------------------------------
-- 3. Outfit meshes: §48 facet / segment checks, palette, budgets, OBJ masters
------------------------------------------------------------------------------
local part3 = checks
local RANGE = {150, 4000} -- §55: smooth re-authored outfits (filleted brims, stadium cloth)
local HARD_EDGE_MAX, COLOUR_EDGE_MAX = 0.2, 0.16
local function edgeRatios(data, points)
	local edges, normals = {}, {}
	for f, face in ipairs(data.faces) do
		local n = (points[face[2]] - points[face[1]]):Cross(points[face[3]] - points[face[1]])
		normals[f] = if n.Magnitude > 0 then n.Unit else Vector3.new(0, 1, 0)
		for k = 1, 3 do
			local a, b = face[k], face[k % 3 + 1]
			local key = if a < b then a * 65536 + b else b * 65536 + a
			local list = edges[key]
			if not list then list = {}; edges[key] = list end
			table.insert(list, f)
		end
	end
	local shared, hard, colour = 0, 0, 0
	local limit = math.cos(math.rad(data.smooth))
	for _, list in pairs(edges) do
		if #list == 2 then
			shared += 1
			if normals[list[1]]:Dot(normals[list[2]]) < limit then hard += 1 end
			if data.faces[list[1]][4] ~= data.faces[list[2]][4] then colour += 1 end
		end
	end
	return hard / math.max(1, shared), colour / math.max(1, shared)
end
local function volumes(data, points)
	local parent = {}
	for i = 1, #points do parent[i] = i end
	local function find(i) while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end return i end
	for _, f in ipairs(data.faces) do parent[find(f[2])] = find(f[1]); parent[find(f[3])] = find(f[1]) end
	local groups = {}
	for _, f in ipairs(data.faces) do local r = find(f[1]); groups[r] = groups[r] or {}; table.insert(groups[r], f) end
	local out = {}
	for _, list in pairs(groups) do
		local c, seen, n = Vector3.zero, {}, 0
		for _, f in ipairs(list) do for k = 1, 3 do if not seen[f[k]] then seen[f[k]] = true; c += points[f[k]]; n += 1 end end end
		c /= n
		local vol = 0
		for _, f in ipairs(list) do vol += (points[f[1]] - c):Dot((points[f[2]] - c):Cross(points[f[3]] - c)) / 6 end
		table.insert(out, vol)
	end
	return out
end
local art = fs.readFile("art/outfit-shapes.cjs")
for _, banned in ipairs({"kit.prism(", "kit.box(", "kit.bevelBox(", "kit.jewel(", "kit.slab(", "kit.spindle(", "kit.ring("}) do
	ok(not has(art, banned), "outfit art never uses the flat / faceted primitive " .. banned)
end
ok(not string.find(art, "color: %(%w+, %w+%) =>"), "no colour callback reads the facet index")
for n in string.gmatch(art, "[^%w]n: (%d+)") do ok(tonumber(n) >= 10, "every ring / tube has >= 10 segments (n: " .. n .. ")") end
for m in string.gmatch(art, "[^%w]m: (%d+)") do ok(tonumber(m) >= 8, "every loft section has >= 8 points (m: " .. m .. ")") end
eq(#Outfits.palette, #World.palette, "outfit catalog shares the palette")
for i, hex in ipairs(World.palette) do eq(Outfits.palette[i], hex, "palette entry " .. i) end
ok(Outfits.tintIndex == World.tintIndex and Outfits.tintDarkIndex == World.tintDarkIndex and Outfits.tintLightIndex == World.tintLightIndex, "outfit tint slots")
local count, total = 0, 0
local usedShapes = {}
for _, role in ipairs(ROSTER) do for _, p in ipairs(outfitOf(role).pieces) do usedShapes[p.shape] = true end end
for name, data in pairs(Outfits.shapes) do
	count += 1
	local faces = data.faces
	total += #faces
	eq(data.kind, "outfit", name .. " kind")
	ok(World.shapes[name] == nil, name .. " is unique across catalogs")
	ok(#faces >= RANGE[1] and #faces <= RANGE[2], name .. " triangles " .. #faces .. " within " .. RANGE[1] .. "-" .. RANGE[2])
	eq(data.tris, #faces, name .. " tris meta")
	ok(data.smooth >= 40 and data.smooth < 90, name .. " is smooth-shaded (crease " .. data.smooth .. ", never flat)")
	local points = {}
	for i, v in ipairs(data.vertices) do points[i] = Vector3.new(v[1], v[2], v[3]) end
	ok(#points < 4096, name .. " fits the vertex packing")
	for _, f in ipairs(faces) do
		ok(Outfits.palette[f[4]] ~= nil, name .. " palette index")
		ok((points[f[2]] - points[f[1]]):Cross(points[f[3]] - points[f[1]]).Magnitude > 1e-9, name .. " no degenerate triangle")
	end
	local hard, colour = edgeRatios(data, points)
	ok(hard <= HARD_EDGE_MAX, string.format("%s hard-edge ratio %.3f <= %.2f (segments vs crease)", name, hard, HARD_EDGE_MAX))
	ok(colour <= COLOUR_EDGE_MAX, string.format("%s colour-boundary ratio %.3f <= %.2f (no facet-index colouring)", name, colour, COLOUR_EDGE_MAX))
	for _, vol in ipairs(volumes(data, points)) do ok(vol > -1e-4, name .. " components wound outward") end
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(points) do lo, hi = lo:Min(p), hi:Max(p) end
	local size = hi - lo
	local biggest = math.max(size.X, size.Y, size.Z)
	if data.slot == "head" then ok(biggest >= 1 and biggest <= 3, name .. " fits a head (" .. biggest .. ")") end
	if data.slot == "torso" then ok(biggest >= 1.5 and biggest <= 4.5, name .. " fits a torso (" .. biggest .. ")") end
	if data.slot == "hand" then ok(biggest >= 0.8 and biggest <= 6, name .. " fits a hand prop (" .. biggest .. ")") end
	if data.slot ~= "hand" then ok(math.abs(lo.X + hi.X) <= 0.25 * size.X + 0.12 or name == "Satchel" or name == "Scarf", name .. " is symmetric across X") end
	ok(usedShapes[name], name .. " is worn by someone")
	ok(Outfits.drop ~= nil, "drop hook")
end
ok(count >= 30, "outfit shapes authored (" .. count .. ")")
-- §55: the 35 re-authored smooth outfits (~75k triangles) raise the cap from 420 KB.
ok(#fs.readFile("art/OutfitCatalog.lua") <= 920 * 1024, "outfit catalog download stays under 920 KB")
for _, name in ipairs({"HatWayfarer", "HatMage", "Cloak", "PropStaff", "PropPoker"}) do
	local data, vi, fi = Outfits.shapes[name], 0, 0
	for line in string.gmatch(fs.readFile("art/" .. name .. ".obj"), "[^\n]+") do
		local x, y, z = string.match(line, "^v (%S+) (%S+) (%S+)")
		if x then
			vi += 1
			local v = data.vertices[vi]
			ok(v and math.abs(v[1] - tonumber(x)) < 1e-6 and math.abs(v[2] - tonumber(y)) < 1e-6 and math.abs(v[3] - tonumber(z)) < 1e-6, name .. " vertex " .. vi .. " = OBJ")
		end
		local shade = string.match(line, "^usemtl Shade(%d+)")
		if shade then fi += 1; ok(data.faces[fi] and data.faces[fi][4] == tonumber(shade), name .. " shade = OBJ") end
	end
	ok(vi == #data.vertices and fi == #data.faces, name .. " packed counts = OBJ")
end
-- Per-NPC triangle budget (§55 QC M3: S.trim to S.NPC_TRIS, 6k phones / 13k
-- desktop) and the town-square worst case.
local function trisOf(shape) return Outfits.shapes[shape].tris end
eq(S.NPC_TRIS.phone, 6000, "[M3] phone outfit budget per NPC")
eq(S.NPC_TRIS.desktop, 13000, "[M3] desktop outfit budget per NPC (lead: full outfits on desktop)")
local worst, worstPhone, trimmed = 0, 0, 0
for _, role in ipairs(ROSTER) do
	local full, desk, phone = outfitOf(role), S.trim(outfitOf(role), trisOf, false), S.trim(outfitOf(role), trisOf, true)
	local tris, ptris = 0, 0
	for _, p in ipairs(desk.pieces) do tris += trisOf(p.shape) end
	for _, p in ipairs(phone.pieces) do ptris += trisOf(p.shape) end
	ok(tris == desk.tris and tris <= S.NPC_TRIS.desktop, role .. " desktop outfit " .. tris .. " triangles <= " .. S.NPC_TRIS.desktop)
	ok(ptris == phone.tris and ptris <= S.NPC_TRIS.phone, role .. " phone outfit " .. ptris .. " triangles <= " .. S.NPC_TRIS.phone)
	ok(#desk.pieces >= 1 and desk.pieces[1].shape == full.pieces[1].shape, role .. " keeps its first piece (hat or prop) on desktop")
	if #desk.pieces < #full.pieces then trimmed += 1 end
	worst, worstPhone = math.max(worst, tris), math.max(worstPhone, ptris)
end
ok(worst * S.DRESS_CAP.desktop <= 190000, "desktop dressed cap within 190k placed triangles (" .. worst * S.DRESS_CAP.desktop .. ")")
ok(worstPhone * S.DRESS_CAP.phone <= 18000, "phone dressed cap within 18k placed triangles (" .. worstPhone * S.DRESS_CAP.phone .. ")")
print(string.format("Outfit budget: worst NPC %d tris desktop / %d phone; %d of %d roles trimmed on desktop", worst, worstPhone, trimmed, #ROSTER))
print(string.format("PASS: outfit meshes (%d) — %d shapes, %d triangles", checks - part3, count, total))

------------------------------------------------------------------------------
-- 4. MeshForge outfit pool (mocked AssetService)
------------------------------------------------------------------------------
local part4 = checks
local Props = load("art/PropCatalog.lua")
local Creatures = load("art/CreatureCatalog.lua")
local function forgeHarness(mobile)
	local calls = {meshes = 0}
	local asset = {}
	function asset.CreateEditableMesh()
		calls.meshes += 1
		local mesh = {n = 0}
		function mesh.AddVertex(self) self.n += 1; return self.n end
		function mesh.AddColor() return 1 end
		function mesh.AddTriangle() return 1 end
		function mesh.SetFaceColors() end
		function mesh.AddNormal() return 1 end
		function mesh.SetFaceNormals() end
		function mesh.Destroy() end
		return mesh
	end
	function asset.CreateMeshPartAsync() return roblox.Instance.new("MeshPart") end
	local tokens = {AetherWorldArt = "world", AetherArt = "props", AetherCreatureArt = "creature", AetherOutfitArt = "outfit"}
	local services = {AssetService = asset, ReplicatedStorage = {WaitForChild = function(_, name) return tokens[name] end},
		Players = {LocalPlayer = {Character = {FindFirstChild = function() return {CFrame = CFrame.new()} end}}},
		UserInputService = {TouchEnabled = mobile, KeyboardEnabled = not mobile}}
	local test = {}
	load("forge.client.lua", {
		game = {GetService = function(_, name) return services[name] end},
		workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
		require = function(token) return ({world = World, props = Props, creature = Creatures, outfit = Outfits})[token] or error("module") end,
		Content = {fromObject = function(object) return {object = object} end},
		MeshForgeTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum, Font = roblox.Font,
		task = {spawn = function(f, ...) if type(f) == "thread" then coroutine.resume(f, ...) else f(...) end end, defer = function() end, wait = function() end},
		warn = function() end, print = function() end,
	})
	return test.forge, calls
end
do
	local forge, calls = forgeHarness(false)
	local api = forge.outfit
	ok(api and api.visual and api.release and api.cap >= 24, "the forge exposes the outfit API with its own pool")
	local dye = Color3.fromHex("2F5233")
	local clone, token, extent, centre = api.visual("HatHood", dye)
	ok(clone and clone:IsA("MeshPart") and type(token) == "number" and extent.Magnitude > 0 and centre ~= nil, "an outfit clone, token, extent and centre")
	eq(forge.stats.outfitTemplates, 1, "one outfit template")
	eq(forge.stats.creatureTemplates, 0, "outfits never count as creatures")
	local _, token2 = api.visual("HatHood", dye)
	eq(calls.meshes, 1, "the same shape and dye share one template")
	local _, token3 = api.visual("HatHood", Color3.fromHex("4B2C7A"))
	eq(forge.stats.outfitTemplates, 2, "desktop keeps the exact dye")
	eq(forge.creature.visual("HatHood", dye), nil, "the creature API refuses outfit shapes")
	eq(api.visual("CreatureBoar", dye), nil, "the outfit API refuses creature shapes")
	eq(api.visual("Boulder", dye), nil, "the outfit API refuses world props")
	ok(api.release(token) and api.release(token2) and api.release(token3), "release")
	eq(forge.stats.outfitInstances, 0, "outfit instances returned")
	-- [QC L] outfit clones never count against the world's instance / triangle limits.
	local _, probe = api.visual("HatHood", dye)
	eq(forge.stats.instances, 0, "[L] an outfit clone is not a world instance")
	eq(forge.stats.placedTriangles, 0, "[L] nor world placed triangles")
	eq(forge.stats.outfitInstances, 1, "[L] it counts in the outfit pool")
	api.release(probe)
	-- Fill the pool with busy templates: a new one waits; idle ones give way (LRU).
	-- (A light prop, so the template count, not the triangle cap, is what fills.)
	local held = {}
	for i = 1, api.cap do
		local _, t = api.visual("PropCrook", Color3.fromRGB(i * 4 % 256, 30 + i, 60))
		ok(t ~= nil, "outfit template " .. i)
		table.insert(held, t)
	end
	local none, reason = api.visual("PropHoe", Color3.fromRGB(1, 2, 3))
	ok(api.cap * Outfits.shapes.PropCrook.tris + Outfits.shapes.PropHoe.tris <= api.triangleCap, "the probe fits the outfit triangle cap")
	ok(none == nil and reason == "budget", "[H1] busy outfit templates are never evicted; the refusal says budget (" .. tostring(none) .. " " .. tostring(reason) .. ")")
	local _, creatureToken = forge.creature.visual("CreatureBoar", Color3.fromHex("A0683D"))
	ok(creatureToken ~= nil, "a full outfit pool never starves the creatures")
	api.release(held[1])
	local _, t = api.visual("PropHoe", Color3.fromRGB(1, 2, 3))
	ok(t ~= nil, "the least recently used idle outfit template gives way")
	ok(forge.stats.outfitTemplates <= api.cap, "within the outfit cap")
	local phone = forgeHarness(true)
	local _, a = phone.outfit.visual("HatCap", Color3.fromHex("C2185B"))
	local _, b = phone.outfit.visual("HatCap", Color3.fromHex("0277BD"))
	ok(a and b and phone.stats.outfitTemplates == 1, "phones share one variant per outfit shape")
	ok(phone.outfit.cap < api.cap, "phones keep a smaller outfit pool")
	-- [H1] the pools are the ones the dressed sets are sized against.
	eq(api.cap, S.POOL.desktop.templates, "[H1] desktop outfit template cap = NpcStyle.POOL")
	eq(api.triangleCap, S.POOL.desktop.triangles, "[H1] desktop outfit triangle cap = NpcStyle.POOL")
	eq(phone.outfit.cap, S.POOL.phone.templates, "[H1] phone outfit template cap = NpcStyle.POOL")
	eq(phone.outfit.triangleCap, S.POOL.phone.triangles, "[H1] phone outfit triangle cap = NpcStyle.POOL")
	local _, gone = api.visual("NoSuchHat", dye)
	eq(gone, "unknown", "[H1] an unknown shape is refused for good (the client never asks again)")
end
-- [QC L] a memory / budget error while building an outfit blocks only the outfit pool.
do
	local asset = {CreateEditableMesh = function()
		local mesh = {n = 0}
		function mesh.AddVertex(self) self.n += 1; return self.n end
		function mesh.AddColor() return 1 end
		function mesh.AddTriangle() return 1 end
		function mesh.SetFaceColors() end
		function mesh.AddNormal() return 1 end
		function mesh.SetFaceNormals() end
		function mesh.Destroy() end
		return mesh
	end, CreateMeshPartAsync = function() error("not enough memory for the mesh budget") end}
	local tokens = {AetherWorldArt = "world", AetherArt = "props", AetherCreatureArt = "creature", AetherOutfitArt = "outfit"}
	local services = {AssetService = asset, ReplicatedStorage = {WaitForChild = function(_, name) return tokens[name] end},
		Players = {LocalPlayer = {Character = {FindFirstChild = function() return {CFrame = CFrame.new()} end}}},
		UserInputService = {TouchEnabled = false, KeyboardEnabled = true}}
	local test = {}
	load("forge.client.lua", {
		game = {GetService = function(_, name) return services[name] end},
		workspace = {GetDescendants = function() return {} end, DescendantAdded = {Connect = function() end}},
		require = function(token) return ({world = World, props = Props, creature = Creatures, outfit = Outfits})[token] or error("module") end,
		Content = {fromObject = function(object) return {object = object} end},
		MeshForgeTest = test, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Instance = roblox.Instance, Enum = Enum, Font = roblox.Font,
		task = {spawn = function(f, ...) if type(f) == "thread" then coroutine.resume(f, ...) else f(...) end end, defer = function() end, wait = function() end},
		warn = function() end, print = function() end,
	})
	local forge = test.forge
	local clone, reason = forge.outfit.visual("HatCap", Color3.fromHex("6D4C41"))
	ok(clone == nil and reason == "unavailable", "[L] a memory failure refuses the outfit (" .. tostring(reason) .. ")")
	ok(forge.outfit.pool.blocked == true, "[L] the outfit pool is blocked")
	ok(forge.stopReason() == nil and forge.creature.pool.blocked ~= true, "[L] the world and creature pools are not")
end
-- [H1] Worst-case dressed sets fit the pool: every subset of DRESS_CAP NPCs of a
-- region (the nearest-N any player can stand among), distinct (shape, dye)
-- templates and their triangles on desktop; distinct shapes (one shared variant)
-- on phones.
do
	local byRegion = {}
	for _, role in ipairs(ROSTER) do
		local region = T.NPCs[role].region
		byRegion[region] = byRegion[region] or {}
		table.insert(byRegion[region], role)
	end
	local function worst(roles, n, phone)
		local bestT, bestTris = 0, 0
		local pick, list = {}, {}
		for i, role in ipairs(roles) do list[i] = S.trim(outfitOf(role), function(shape) return Outfits.shapes[shape].tris end, phone) end
		local function measure()
			local keys, count, tris = {}, 0, 0
			for _, o in ipairs(pick) do
				for _, p in ipairs(o.pieces) do
					local key = if phone then p.shape else p.shape .. "#" .. (p.dye or "")
					if not keys[key] then keys[key] = true; count += 1; tris += Outfits.shapes[p.shape].tris end
				end
			end
			bestT, bestTris = math.max(bestT, count), math.max(bestTris, tris)
		end
		local function choose(start, left)
			if left == 0 or start > #list then measure(); return end
			for i = start, #list do
				table.insert(pick, list[i]); choose(i + 1, left - 1); table.remove(pick)
				if #list - i < left - 1 then break end
			end
		end
		choose(1, math.min(n, #list))
		return bestT, bestTris
	end
	local peak = {0, 0, 0, 0}
	for region, list in pairs(byRegion) do
		local dt, dtris = worst(list, S.DRESS_CAP.desktop, false)
		ok(dt <= S.POOL.desktop.templates and dtris <= S.POOL.desktop.triangles,
			string.format("[H1] %s: the worst %d dressed NPCs need %d templates / %d tris (desktop pool %d / %d)", region, S.DRESS_CAP.desktop, dt, dtris, S.POOL.desktop.templates, S.POOL.desktop.triangles))
		local pt, ptris = worst(list, S.DRESS_CAP.phone, true)
		peak = {math.max(peak[1], dt), math.max(peak[2], dtris), math.max(peak[3], pt), math.max(peak[4], ptris)}
		ok(pt <= S.POOL.phone.templates and ptris <= S.POOL.phone.triangles,
			string.format("[H1] %s: the worst %d dressed NPCs need %d shapes / %d tris (phone pool %d / %d)", region, S.DRESS_CAP.phone, pt, ptris, S.POOL.phone.templates, S.POOL.phone.triangles))
	end
	print(string.format("Outfit pool worst case: desktop %d templates / %d tris (pool %d / %d); phone %d / %d (pool %d / %d)",
		peak[1], peak[2], S.POOL.desktop.templates, S.POOL.desktop.triangles, peak[3], peak[4], S.POOL.phone.templates, S.POOL.phone.triangles))
end
print("PASS: MeshForge outfit pool (" .. (checks - part4) .. ")")

------------------------------------------------------------------------------
-- 5. Server rig: fallback tags and the nameplate (Signs v2 contrast rules)
------------------------------------------------------------------------------
local part5 = checks
local Methods, Meta = {}, {}
local function new(class)
	return setmetatable({__props = {ClassName = class, Name = class}, __children = {}, __attrs = {}}, Meta)
end
Meta.__index = function(self, key)
	if Methods[key] then return Methods[key] end
	local props = rawget(self, "__props")
	if props[key] ~= nil then return props[key] end
	for _, c in ipairs(rawget(self, "__children")) do if c.Name == key then return c end end
	return nil
end
Meta.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		if props.Parent then local l = rawget(props.Parent, "__children"); for i, c in ipairs(l) do if c == self then table.remove(l, i); break end end end
		props.Parent = value
		if value then table.insert(rawget(value, "__children"), self) end
		return
	end
	props[key] = value
end
function Methods:GetChildren() return table.clone(rawget(self, "__children")) end
function Methods:GetDescendants()
	local out = {}
	local function walk(o) for _, c in ipairs(rawget(o, "__children")) do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function Methods:FindFirstChild(name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do if c.Name == name then return c end end
	if recursive then for _, c in ipairs(rawget(self, "__children")) do local f = c:FindFirstChild(name, true); if f then return f end end end
	return nil
end
function Methods:WaitForChild(name) return self:FindFirstChild(name) end
function Methods:IsA(class) if class == "BasePart" then return self.ClassName == "Part" end return self.ClassName == class end
function Methods:SetAttribute(k, v) rawget(self, "__attrs")[k] = v end
function Methods:GetAttribute(k) return rawget(self, "__attrs")[k] end
function Methods:GetPivot() return CFrame.new() end
function Methods:PivotTo() end
local function signal() return {Connect = function() return {Disconnect = function() end} end} end
for _, name in ipairs({"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AttributeChanged", "PlayerAdded", "PlayerRemoving", "CharacterAdded"}) do Methods[name] = signal() end
function Methods:GetPropertyChangedSignal() return signal() end
local serverStorage, styleMarker, dataMarker, themeMarker = new("ServerStorage"), {}, {}, {}
local ThemeServer = load("shared/UiTheme.lua", {Instance = {new = new}, Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint})
load("npc.server.lua", {
	game = {GetService = function(_, name)
		return ({Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
			ReplicatedStorage = {WaitForChild = function(_, child) return if child == "AetherNpcStyle" then styleMarker elseif child == "AetherUiTheme" then themeMarker else dataMarker end},
			ServerStorage = serverStorage})[name]
	end},
	workspace = new("Workspace"),
	require = function(target) return if target == styleMarker then S elseif target == themeMarker then ThemeServer else Data end,
	Instance = {new = new}, RaycastParams = {new = function() return {} end},
	Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, Vector2 = roblox.Vector2, ColorSequence = roblox.ColorSequence,
	task = {delay = function() end, spawn = function() end, wait = function() end, defer = function() end},
})
local stash = serverStorage:FindFirstChild("TownsfolkUnplaced")
local function contrast(a, b) return S.contrast(a:ToHex(), b:ToHex()) end
local labelsSeen = 0
for _, role in ipairs(ROSTER) do
	local model
	for _, m in ipairs(stash:GetChildren()) do if m:GetAttribute("TownsfolkRole") == role then model = m end end
	ok(model ~= nil, role .. " rig built")
	local outfit = outfitOf(role)
	eq(model:GetAttribute("NpcTrade"), outfit.trade, role .. " publishes its trade")
	eq(model:GetAttribute("NpcIdle"), outfit.idle, role .. " publishes its idle loop")
	-- Every hidden-able slot has primitive fallback parts tagged for it.
	for _, piece in ipairs(outfit.pieces) do
		if S.SLOT_HIDES[piece.slot] then
			local tagged = 0
			for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("OutfitSlot") == piece.slot then tagged += 1 end end
			ok(tagged >= 1, role .. " fallback parts tagged OutfitSlot=" .. piece.slot)
		end
	end
	for _, name in ipairs({"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "LeftUpperArm", "RightHand"}) do
		ok(model:FindFirstChild(name):GetAttribute("OutfitSlot") == nil, role .. " body part " .. name .. " is never hidden")
	end
	-- Nameplate.
	local head = model:FindFirstChild("Head")
	local board = head:FindFirstChild("Nameplate")
	local plate = board and board:FindFirstChild("Plate")
	ok(board and plate and board.ClassName == "BillboardGui", role .. " nameplate")
	ok(board.AlwaysOnTop == false and board.MaxDistance <= 120 and board.LightInfluence == 0, role .. " nameplate never draws through walls, bounded, self-lit")
	local spec = S.plate(role, T.NPCs[role])
	ok(math.abs(board.StudsOffset.Y - spec.lift) < 1e-6, role .. " plate lift")
	local hatShape = outfit.hat and S.HATS[outfit.hat]
	if hatShape then
		local data = Outfits.shapes[hatShape]
		local top = -math.huge
		for _, v in ipairs(data.vertices) do top = math.max(top, v[2]) end
		ok(board.StudsOffset.Y >= top + 0.6, string.format("%s plate clears the %s crown (%.2f >= %.2f)", role, hatShape, board.StudsOffset.Y, top + 0.6))
	end
	for _, name in ipairs({"NpcName", "NpcTitle"}) do
		local label = plate:FindFirstChild(name)
		ok(label and label.ClassName == "TextLabel", role .. " " .. name)
		ok(not string.find(label.Font.Name, "Gotham"), role .. " " .. name .. " is not Gotham (" .. label.Font.Name .. ")")
		local fit = label:FindFirstChild("UITextSizeConstraint")
		ok(label.TextScaled and fit and fit.MinTextSize >= S.PLATE.minPx and fit.MaxTextSize <= 17, role .. " " .. name .. " scales between 10 px and its size (QC M1)")
		ok(label.Size.X.Offset == 0 and label.Size.Y.Offset == 0 and label.Position.X.Offset == 0, role .. " " .. name .. " is laid out by scale")
		local strokes = 0
		for _, c in ipairs(label:GetChildren()) do if c.ClassName == "UIStroke" then strokes += 1 end end
		eq(strokes, 1, role .. " " .. name .. " one outline")
		ok(contrast(label.TextColor3, plate.BackgroundColor3) >= S.PLATE.minContrast, string.format("%s %s contrast %.2f on its field", role, name, contrast(label.TextColor3, plate.BackgroundColor3)))
		labelsSeen += 1
	end
	-- [QC M1] sized in studs with a pixel clamp; CLICK is a pixel row under the plate.
	ok(board.Size.X.Scale > 0 and board.Size.Y.Scale > 0 and board.Size.X.Offset >= S.PLATE.minSize[1], role .. " [M1] billboard sized in studs plus a pixel floor")
	local clamp = plate:FindFirstChild("PixelClamp")
	ok(clamp and clamp.MaxSize.X == S.PLATE.width and clamp.MaxSize.Y == S.PLATE.height and clamp.MinSize.X == S.PLATE.minSize[1], role .. " [M1] plate pixel clamp")
	ok(board.MaxDistance <= 60, role .. " [M1] MaxDistance <= 60 (phones 40)")
	local click = plate:FindFirstChild("Click")
	ok(click and click.Position.Y.Scale == 1 and click.Position.Y.Offset >= S.PLATE.clickGap and click.AnchorPoint.Y == 0 and not click.Visible, role .. " [M1] CLICK row under the plate (shown up close)")
	-- [QC M2] a frame-drawn medallion: the trade motif, no font glyph.
	local medal = plate:FindFirstChild("TradeMedallion")
	ok(medal and medal.ClassName == "Frame", role .. " [M2] trade medallion is a frame")
	local icon = medal and medal:FindFirstChild("Icon")
	ok(icon and icon:GetAttribute("Shape") == spec.motif and ThemeServer.ICON_MOTIFS[spec.motif] ~= nil, role .. " [M2] medallion draws the " .. tostring(spec.motif) .. " motif")
	for _, d in ipairs(board:GetDescendants()) do
		if d.ClassName == "TextLabel" and d.Name ~= "NpcName" and d.Name ~= "NpcTitle" then
			ok(not string.find(d.Text, "[\128-\255]"), role .. " [M2] no non-ASCII glyph in " .. d.Name)
		end
	end
	eq(plate.NpcName.Text, T.NPCs[role].name, role .. " name")
	eq(plate.NpcTitle.Text, T.NPCs[role].title, role .. " title")
	ok(plate.RegionBar and string.upper(plate.RegionBar.BackgroundColor3:ToHex()) == spec.accent, role .. " region accent bar")
end
-- [QC M1] overlap: plate, CLICK row and quest marker never overlap, at every
-- distance from 6 studs to MaxDistance on a 1080 p desktop and a 390 p phone
-- (70 degree vertical FOV), and the plate never drops below its pixel floor.
for _, screen in ipairs({{1080, false, S.PLATE.maxDistance}, {390, true, S.PLATE.phone.maxDistance}}) do
	for d = 6, screen[3], 2 do
		local k = screen[1] / (2 * d * math.tan(math.rad(35)))
		local L = S.plateLayout(k, screen[2])
		local function gap(a, b) return math.abs(a[1] - b[1]) - a[2] - b[2] end
		ok(gap(L.plate, L.click) >= 0 and gap(L.plate, L.marker) >= 0 and gap(L.click, L.marker) >= 0,
			string.format("[M1] no overlap at %d studs on a %d p screen", d, screen[1]))
		ok(L.plateH >= (if screen[2] then S.PLATE.phone.minSize[2] else S.PLATE.minSize[2]), "[M1] plate floor")
	end
end
ok(S.PLATE.phone.maxDistance <= 40 and S.PLATE.phone.maxSize[1] < S.PLATE.width, "[M1] a smaller phone variant seen from nearer")
-- [QC M2] no trade relies on a font glyph.
for trade, def in pairs(S.TRADES) do
	ok(def.glyph == nil and type(def.motif) == "string", "[M2] " .. trade .. " medallion is a motif")
end
-- Every region accent yields a legible title.
for region, r in pairs(S.REGIONS) do ok(S.contrast(S.titleColor(r.accent), S.PLATE.field) >= 4.5, region .. " title colour reads on the plate") end
ok(S.contrast(S.PLATE.nameColor, S.PLATE.field) >= 7, "names read at AAA contrast")
print("PASS: server rigs and nameplates (" .. (checks - part5) .. ", " .. labelsSeen .. " labels)")

------------------------------------------------------------------------------
-- 6. Client renderer source rules, previews and wiring
------------------------------------------------------------------------------
local part6 = checks
local client = fs.readFile("npc.client.lua")
ok(has(client, 'require(ReplicatedStorage:WaitForChild("AetherNpcStyle"))'), "npc.client.lua uses the shared NPC style")
ok(has(client, '"outfit"') and has(client, '"outfitRelease"'), "outfits come from the MeshForge outfit API and go back")
ok(has(client, "LocalTransparencyModifier = 1") and has(client, "LocalTransparencyModifier = 0"), "fallback parts are hidden locally and restored")
ok(not string.find(client, "%.Transparency%s*="), "the client never writes a replicated Transparency")
local section = string.sub(client, (string.find(client, "-- NPC registry, quest markers, forged outfits", 1, true)), (string.find(client, "-- (Polish: the tutorial", 1, true)))
ok(#section > 2000 and not has(section, ":SetAttribute("), "the NPC renderer never writes attributes on the townsfolk")
ok(not has(client, ".Transform ="), "NPC motors are posed through C0 (the talk nod owns Transform)")
ok(has(client, "Style.DRESS_CAP") and has(client, "Style.DRESS_RANGE") and has(client, "isPhone()"), "dressing is capped by device")
-- §55 QC M3: one device class (shared/Device.lua) for the forge's pools and the dressed set.
do
	local Device = load("shared/Device.lua")
	ok(Device.isPhone({TouchEnabled = true, KeyboardEnabled = false}) == true, "[M3] a touch-only phone is the phone class")
	ok(Device.isPhone({TouchEnabled = true, KeyboardEnabled = false, ViewportSize = Vector3.new(2048, 1536, 0)}) == true, "[M3] a touch-only tablet is the phone class too")
	ok(Device.isPhone({TouchEnabled = true, KeyboardEnabled = true}) == false and Device.isPhone({TouchEnabled = false, KeyboardEnabled = true}) == false, "[M3] keyboard devices are desktops")
	ok(has(client, 'require(ReplicatedStorage:WaitForChild("AetherDevice"))') and has(client, "Device.isPhone(Input)") and not has(client, "ViewportSize.Y < 500"), "[M3] npc.client.lua uses the shared device class")
	ok(has(fs.readFile("forge.client.lua"), 'ReplicatedStorage:WaitForChild("AetherDevice", 5)') and has(fs.readFile("forge.client.lua"), "Device.isPhone(UserInputService)"), "[M3] forge.client.lua uses the shared device class")
	ok(has(fs.readFile("default.project.json"), '"AetherDevice": { "$path": "shared/Device.lua" }'), "[M3] the device module ships in ReplicatedStorage")
	ok(has(client, "Style.trim(outfit, outfitTris, isPhone())"), "[M3] npc.client.lua trims each outfit to the per-NPC budget")
end
ok(has(client, "Theme.reducedMotion(player)") and has(client, "Style.sample(entry.idle, t, entry.pose, reduced)"), "reduced motion calms the loops (and skips beat FX)")
ok(has(client, "if not color or reduced"), "no beat sparks under reduced motion")
ok(has(client, "Style.lod(distance, phone)"), "idle animation LOD by distance and device")
ok(not has(client, "LocalPlayer.Character:FindFirstChild(\"Humanoid\")") and not has(client, "Animator"), "the NPC loop never touches the player's character or Animator")
local animate = fs.readFile("animate.client.lua")
ok(not has(animate, "NpcStyle") and not has(animate, "OutfitSlot"), "animate.client.lua's player code paths are untouched")
local forgeSource = fs.readFile("forge.client.lua")
ok(has(forgeSource, '"AetherOutfitArt"') and has(forgeSource, 'skip(part, "outfit shape", true)'), "the forge loads the outfit catalog and never Shape-forges outfit pieces")
local project = fs.readFile("default.project.json")
ok(has(project, '"AetherNpcStyle": { "$path": "shared/NpcStyle.lua" }') and has(project, '"AetherOutfitArt": { "$path": "art/OutfitCatalog.lua" }'), "project wiring")
ok(fs.isFile("tools/dump-npcs.luau") and fs.isFile("tools/render-npcs.py"), "preview tools")
ok(fs.isFile("docs/screenshots/npcs-townsfolk.png") and fs.isFile("docs/screenshots/npcs-featured.png"), "preview renders committed")
for _, script in ipairs({"scripts/build.sh", "build.ps1"}) do ok(has(fs.readFile(script), "verify-npcart.luau"), script .. " runs verify-npcart") end
ok(has(fs.readFile("docs/DEPTH-CONTRACT.md"), "## 52."), "contract §52")
print("PASS: client rules and wiring (" .. (checks - part6) .. ")")

------------------------------------------------------------------------------
-- 7. QC round regressions ([M3] art and poses, [L] client lows)
------------------------------------------------------------------------------
local part7 = checks
-- [M3] Old Hesketh Ashby's flat cap sits down on the crown and his stoop keeps the head up.
do
	local cap = wears(hesketh, "HatCap")
	ok(cap ~= nil, "[M3] Hesketh wears the cap")
	local lo, hi = math.huge, -math.huge
	for _, v in ipairs(Outfits.shapes.HatCap.vertices) do lo = math.min(lo, v[2]); hi = math.max(hi, v[2]) end
	ok(lo + cap.at[2] <= 0.34 and hi + cap.at[2] >= 0.8, string.format("[M3] the cap seats on the head (%.2f .. %.2f)", lo + cap.at[2], hi + cap.at[2]))
	for _, key in ipairs(S.IDLES.poke.keys) do
		ok((key.pose.neck or {0})[1] >= -15 and (key.pose.waist or {0})[1] >= -16, "[M3] the poke stoop keeps the cap on top (neck / waist)")
	end
end
-- [M3] the goggles are sculpted: a strap that follows the square head, cups with a bevel, lenses.
do
	local data = Outfits.shapes.HatGoggles
	local corner, cups = 0, 0
	for _, v in ipairs(data.vertices) do
		if math.abs(v[2] - 0.33) < 0.12 and v[3] > -0.55 then corner = math.max(corner, math.sqrt(v[1] * v[1] + v[3] * v[3])) end
		if v[3] < -0.78 then cups += 1 end
	end
	ok(corner >= 0.84, string.format("[M3] the strap follows the head's corners (%.2f)", corner))
	ok(cups >= 20 and data.tris >= 1200, "[M3] domed lenses in bevelled cups (" .. data.tris .. " tris)")
end
-- [M3] Pell's cloak: an opaque deep dye on a cape wide enough for the shoulders.
do
	local cloak = wears(pell, "Cloak")
	ok(cloak and S.contrast(cloak.dye, "FFFFFF") >= 3, "[M3] Pell's cloak is a deep, opaque dye (" .. tostring(cloak and cloak.dye) .. ")")
	local width = 0
	for _, v in ipairs(Outfits.shapes.Cloak.vertices) do if v[2] > 0.5 then width = math.max(width, math.abs(v[1])) end end
	ok(width >= 1.2, string.format("[M3] the cloak's top covers the shoulders (half width %.2f)", width))
end
-- [M3] Maelis' trace and glyph-high frames are clearly different.
do
	local trace, high = at("rune", 0.7), at("rune", S.IDLES.rune.beat)
	ok(high.leftArm[1] - trace.leftArm[1] >= 60 and math.abs(trace.neck[1] - high.neck[1]) >= 20, "[M3] trace (low, eyes on the hand) vs glyph high (overhead, leaning back)")
end
-- [L] client lows (source rules).
do
	local c = fs.readFile("npc.client.lua")
	ok(has(c, "local function restPose(entry)") and has(c, "if entry.animating then restPose(entry) end"), "[L] the rest pose is written when an NPC stops animating")
	ok(has(c, "Style.ANIM_CAP") and has(c, "entry.rank == math.huge"), "[L] only the nearest ANIM_CAP NPCs animate")
	ok(has(c, "reducedCached = Theme.reducedMotion(player)") and has(c, "local reduced = reducedCached"), "[L] reduced motion is sampled every 0.5 s, not per frame")
	local heartbeat = string.sub(c, (string.find(c, "RunService.Heartbeat:Connect", 1, true)))
	ok(not has(heartbeat, "Theme.reducedMotion") and not has(heartbeat, "isPhone()"), "[L] the frame loop makes no closures / service calls for settings")
	ok(has(c, "entry.noBone = true; break") and has(c, "or entry.noBone"), "[L] a missing bone stops retries until the NPC re-registers")
	ok(has(c, 'child.Name == "Head"') and has(c, "task.defer(register, model)"), "[L] a late / replaced Head re-registers the NPC")
	ok(not has(c, "retryAt"), "[H1] no timer retry")
	ok(has(c, "if entry.tokens[i] or entry.failed[i] then continue end"), "[H1] granted pieces are kept; only missing ones are asked for")
	ok(has(c, 'if token == "budget" then refused = "budget"; break end') and has(c, "entry.blockedAt = if refused then poolEpoch else nil"), "[H1] a budget refusal waits for the pool to change")
	ok(has(c, "if entry.blockedAt == poolEpoch then") and has(c, "other.distance <= entry.distance then break end"), "[H1] a nearer NPC takes the pool from the farthest dressed one only")
	ok(has(c, "if released then poolEpoch += 1 end"), "[H1] releasing tokens reopens the pool")
	ok(has(c, "SizeOffset = Vector2.new(0, shift)"), "[M1] the quest marker sits a pixel gap above the plate")
	ok(has(c, "applyPlateVariant(entry)") and has(c, "P.phone.maxSize"), "[M1] phones get the smaller plate")
end
print("PASS: QC regressions (" .. (checks - part7) .. ")")

print(string.format("NPC art QA passed %d checks: %d townsfolk, %d idle loops, %d outfit meshes.", checks, #ROSTER, (function() local n = 0 for _ in pairs(S.IDLES) do n += 1 end return n end)(), count))
print("SUITE-END verify-npcart.luau")
