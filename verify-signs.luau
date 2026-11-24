-- Signs (docs/DEPTH-CONTRACT.md §28): every sign in the generated world goes
-- through the shared Signs system in world.server.lua. Builds the real world
-- (static islands plus a home island with its garden, crew haven and builder's
-- terrace) and checks: one archetype per sign model, its frame host and boards
-- carry the sign kit mesh slots (shapes exist, fit boxes valid, declared boxes
-- sane), part counts per archetype, the static part budget, no lights, text
-- that fits its board at every length used (independent re-measure), night
-- readability (LightInfluence, brightness, contrast, distance), fonts, arrow
-- boards that point at their destinations, and no sign standing on a path or
-- swallowing someone else's prompt.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f)
			local c = {Connected = true}
			function c:Disconnect() self.Connected = false end
			table.insert(listeners, {f, c})
			return c
		end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
roblox.implementProperty("ProximityPrompt", "Destroying", function(prompt)
	return signal()
end)
local Data = luau.load(fs.readFile("shared/GameData.lua"), {injectGlobals = true})()
local World = luau.load(fs.readFile("art/WorldCatalog.lua"), {injectGlobals = true})()
local Props = luau.load(fs.readFile("art/PropCatalog.lua"), {injectGlobals = true})()
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
local tags = {}
local env = {
	game = {GetService = function(_, name)
		if name == "Players" then return players end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function(_, obj, tag) tags[tag] = tags[tag] or {}; table.insert(tags[tag], obj) end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = Color3,
	UDim2 = roblox.UDim2, UDim = roblox.UDim, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end, defer = function() end, delay = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local source = fs.readFile("world.server.lua")
luau.load(source:gsub("plans%.Position", "plans.CFrame.Position"), {environment = env, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
local archipelago = world:FindFirstChild("AetherIsles")
ok(islands ~= nil and archipelago ~= nil, "world built")

-- Static budget is counted before any player arrives.
local staticParts, signParts, staticSigns = 0, 0, 0
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") then
		staticParts += 1
		local holder = obj.Parent
		while holder and holder ~= world and holder:GetAttribute("SignArchetype") == nil do holder = holder.Parent end
		if holder and holder ~= world then signParts += 1 end
	elseif obj:IsA("Model") and obj:GetAttribute("SignArchetype") then
		staticSigns += 1
	end
end
ok(staticParts < 4000, "static world stays under the 4000 part budget (" .. staticParts .. ")")

-- A home island (garden, deck, crew haven, builder's terrace) brings the home signs.
local function player(id, attributes)
	local changed = {}
	local p = {UserId = id, Name = "P" .. id, CharacterAdded = signal(), attributes = attributes or {}}
	function p:GetAttribute(key) return self.attributes[key] end
	function p:GetAttributeChangedSignal(key) changed[key] = changed[key] or signal(); return changed[key] end
	function p:SetAttribute(key, value) self.attributes[key] = value; self:GetAttributeChangedSignal(key):Fire() end
	players.PlayerAdded:Fire(p)
	return p
end
local guest = player(77, {HomeGarden = true, HomeDeck = true, Worker1Tier = 1})
pcall(function() guest:SetAttribute("CoopId", "7") end)
pcall(function() guest:SetAttribute("GardenUnlocked", true) end)

------------------------------------------------------------------------------
-- Independent text measure (same rules as the docs: conservative em widths).
------------------------------------------------------------------------------
local EM = {W = 1.0, M = .96, m = .88, w = .8, [" "] = .3, i = .34, l = .34, j = .34, I = .44, t = .42, f = .42, r = .46, ["."] = .32,
	[","] = .32, ["'"] = .28, ["•"] = .5, ["/"] = .44, ["-"] = .44, ["+"] = .64, ["·"] = .36}
local function width(text, size)
	local em = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		em += EM[ch] or (if ch:match("^%u$") then .76 elseif ch:match("^%l$") then .6 elseif ch:match("^%d$") then .66 else .56)
	end
	return em * size
end
local function lines(text, size, w)
	local n, line = 1, ""
	for word in text:gmatch("%S+") do
		local candidate = if line == "" then word else line .. " " .. word
		if line ~= "" and width(candidate, size) > w then n += 1; line = word else line = candidate end
		if width(word, size) > w then return math.huge end
	end
	return n
end
local function luminance(c)
	local function ch(v) return if v <= .03928 then v / 12.92 else ((v + .055) / 1.055) ^ 2.4 end
	return .2126 * ch(c.R) + .7152 * ch(c.G) + .0722 * ch(c.B)
end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + .05) / (math.min(la, lb) + .05)
end
-- Colours a frame really shows: a UIGradient multiplies the background, so a
-- graded frame is white and its keypoints are the true colours.
local function shown(frame)
	local g = frame:FindFirstChildOfClass("UIGradient")
	if not g then return {frame.BackgroundColor3} end
	local out = {}
	for _, k in g.Color.Keypoints do
		local c, b = k.Value, frame.BackgroundColor3
		table.insert(out, Color3.new(c.R * b.R, c.G * b.G, c.B * b.B))
	end
	return out
end
local function worst(color, frame)
	local r = math.huge
	for _, c in shown(frame) do r = math.min(r, contrast(color, c)) end
	return r
end
local function stripTags(text) return (text:gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")) end

------------------------------------------------------------------------------
-- Sign models (§28 v2): one invisible anchor, one floating billboard, no
-- posts, frames, plinths or sign meshes. Ledgers stay physical notice boards.
------------------------------------------------------------------------------
local KINDS = {hanging = true, shop = true, post = true, banner = true, plaque = true, ledger = true}
local FONTS = {["rbxasset://fonts/families/Merriweather.json"] = true, ["rbxasset://fonts/families/BuilderSans.json"] = true,
	["rbxasset://fonts/families/Fondamento.json"] = true}
local TITLE_FONTS = {["rbxasset://fonts/families/Merriweather.json"] = true, ["rbxasset://fonts/families/Fondamento.json"] = true}
local signs, kinds, boards = {}, {}, {}
local guiInstances, labelCount, billboards = 0, 0, 0
for _, model in world:GetDescendants() do
	local kind = model:IsA("Model") and model:GetAttribute("SignArchetype")
	if kind then
		table.insert(signs, model)
		ok(KINDS[kind], model:GetFullName() .. " archetype " .. tostring(kind))
		ok(model.Name == "Sign " .. model:GetAttribute("SignTitle"), model:GetFullName() .. " keeps the Sign <title> name")
		ok(model:GetAttribute("SignVersion") == 2, model:GetFullName() .. " is a v2 sign")
		kinds[kind] = (kinds[kind] or 0) + 1
		local parts = {}
		for _, p in model:GetDescendants() do
			ok(not p:IsA("Light"), model:GetFullName() .. " adds no lights")
			if p:IsA("BasePart") then table.insert(parts, p) end
		end
		ok(#parts == 1, model:GetFullName() .. " is a single part (" .. #parts .. "): no posts, brackets, plinths or frames")
		local p = parts[1]
		ok(not p.CanCollide and not p.CanTouch, p:GetFullName() .. " never blocks a path")
		ok(p:GetAttribute("ShapeBox") == nil, p:GetFullName() .. " has no declared frame box")
		if kind == "ledger" then
			ok(p:GetAttribute("Shape") == "SignNoticeBoard" and p:FindFirstChildOfClass("SurfaceGui") ~= nil, model:GetFullName() .. " ledger keeps its notice board face")
		else
			ok(p:GetAttribute("SignAnchor") == true and p.Transparency == 1 and not p.CanQuery and p:GetAttribute("Shape") == nil,
				p:GetFullName() .. " is an invisible, mesh-free anchor")
			ok(p.Name == model:GetAttribute("SignTitle"), p:GetFullName() .. " anchor is named after the title (returned main part)")
			local guis = {}
			for _, g in p:GetChildren() do if g:IsA("LayerCollector") then table.insert(guis, g) end end
			ok(#guis == 1 and guis[1]:IsA("BillboardGui") and guis[1].Name == "SignBillboard", model:GetFullName() .. " carries one SignBillboard")
			table.insert(boards, {model = model, kind = kind, anchor = p, gui = guis[1]})
		end
	end
end
ok(#tags.AetherSign == #signs, "every sign is tagged AetherSign")
for kind in KINDS do ok((kinds[kind] or 0) >= 1, kind .. " archetype is used in the world") end
ok(#signs >= 80, "signs across the world (" .. #signs .. ")")

------------------------------------------------------------------------------
-- Billboard style: framed, themed, distinct from NPC nameplates, readable.
------------------------------------------------------------------------------
local npcSource = fs.readFile("npc.server.lua")
ok(npcSource:find('"Nameplate"', 1, true) and npcSource:find("GothamBold", 1, true), "NPC nameplates: a dark Gotham strip named Nameplate")
local function find(root, name) return root:FindFirstChild(name) end
for _, b in boards do
	local gui, kind, name = b.gui, b.kind, b.model:GetFullName()
	billboards += 1
	ok(gui.Name ~= "Nameplate", name .. " is not a nameplate")
	ok(not gui.AlwaysOnTop, name .. " never shows through walls")
	ok(gui.MaxDistance == (if kind == "plaque" then 160 else 120), name .. " MaxDistance by archetype (" .. gui.MaxDistance .. ")")
	ok(gui.LightInfluence <= .25 and gui.Brightness >= 1, name .. " self-lights for night reading")
	ok(gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.Size.X.Offset <= 440 and gui.Size.Y.Offset <= 400, name .. " has a bounded design size")
	ok(gui:GetAttribute("SignStyled") == true and gui:GetAttribute("SignKind") == kind, name .. " styled for its archetype")
	local lift = gui:GetAttribute("SignLift")
	ok(type(lift) == "number" and math.abs(gui.StudsOffsetWorldSpace.Y - lift) < 1e-4 and lift >= 2 and lift <= 10, name .. " floats above its anchor")
	local root = gui:FindFirstChild("Sign")
	ok(root and root.ClassName == "CanvasGroup" and root:FindFirstChildOfClass("UIScale") ~= nil, name .. " root fades (CanvasGroup) and scales (UIScale)")
	local cw, ch = root.Size.X.Offset, root.Size.Y.Offset
	-- Ornate plaque vocabulary (absent from NPC nameplates).
	for _, piece in {"Frame", "Panel", "Inlay", "Shadow", "Crest", "Crest glyph", "Crystal", "Crystal glow"} do
		ok(find(root, piece) ~= nil, name .. " has its " .. piece)
	end
	local glow = find(root, "Crystal glow")
	ok(glow:GetAttribute("NightTransparency") < glow:GetAttribute("DayTransparency"), name .. " crystal glows brighter at night")
	local panel = find(root, "Panel")
	for _, c in shown(find(root, "Frame")) do ok(c ~= Color3.fromHex("091923") and c ~= Color3.new(1, 1, 1), name .. " frame is graded metal, not the nameplate ink") end
	if kind ~= "banner" then
		local caps = 0
		for _, c in root:GetChildren() do if c.Name == "Corner cap" then caps += 1 end end
		ok(caps == 4, name .. " has four corner caps")
	end
	local glyph = find(root, "Crest glyph")
	ok(glyph.Text ~= "", name .. " crest glyph painted")
	if kind == "shop" then ok(glyph.Text ~= "✦", name .. " shop crest shows its trade glyph") end
	local titles, arrowsN, destinations = 0, 0, 0
	for _, d in root:GetDescendants() do
		guiInstances += 1
		if d:IsA("GuiObject") and typeof(d:GetAttribute("SignArrowTo")) == "Vector3" then
			arrowsN += 1
			ok(d.Name == "Arrow" and d:FindFirstChild("Head") and d:FindFirstChild("Shaft"), d:GetFullName() .. " arrow glyph")
			local to = d:GetAttribute("SignArrowTo")
			local flat = Vector3.new(to.X - b.anchor.CFrame.Position.X, 0, to.Z - b.anchor.CFrame.Position.Z)
			ok(flat.Magnitude > 3, d:GetFullName() .. " points somewhere else")
		end
		if d:IsA("TextLabel") and d.Name ~= "Crest glyph" and not d.Name:find("Shadow", 1, true) and d.Text ~= "" then
			labelCount += 1
			local w, h, size = d.Size.X.Offset, d.Size.Y.Offset, d.TextSize
			local text = stripTags(d.Text)
			ok(d:GetAttribute("SignPlain") == text, d:GetFullName() .. " plain text recorded ('" .. text .. "')")
			ok(not d.TextScaled and d.TextWrapped, d:GetFullName() .. " uses a fitted text size")
			ok(d:GetAttribute("SignOverflow") == nil, d:GetFullName() .. " '" .. text .. "' fits without overflow")
			ok(FONTS[d.FontFace.Family] == true, d:GetFullName() .. " uses a sign font face")
			local n = lines(text, size, w)
			ok(n <= (d:GetAttribute("SignFitLines") or 1) and n * size * 1.25 <= h + 1, d:GetFullName() .. " '" .. text .. "' fits its box (" .. n .. " lines at " .. size .. "px)")
			ok(d.Position.X.Offset >= 0 and d.Position.Y.Offset >= 0 and d.Position.X.Offset + w <= cw + 1 and d.Position.Y.Offset + h <= ch + 1, d:GetFullName() .. " stays on its plaque")
			local stroke = d:FindFirstChildOfClass("UIStroke") ~= nil
			local shadow = d.Parent:FindFirstChild(d.Name .. "Shadow") ~= nil
			ok(stroke ~= shadow, d:GetFullName() .. " has exactly one outline")
			if d.Name == "Title" or d.Name == "Destination" then
				if d.Name == "Title" then titles += 1; ok(TITLE_FONTS[d.FontFace.Family], d:GetFullName() .. " display title font") end
				if d.Name == "Destination" then destinations += 1 end
				ok(size >= 12, d:GetFullName() .. " title legible (" .. size .. "px)")
				ok(worst(d.TextColor3, panel) >= 4.5, d:GetFullName() .. " title contrast on its panel (night: self-lit)")
			elseif d.Name == "Kicker" then
				ok(size >= 9 and d.RichText, d:GetFullName() .. " small-caps kicker legible")
				ok(worst(d.TextColor3, panel) >= 3, d:GetFullName() .. " kicker contrast")
			end
		end
	end
	if kind == "post" then
		ok(arrowsN >= 1 and arrowsN == destinations, name .. " one arrow per destination (" .. arrowsN .. ")")
	else
		ok(titles == 1 and arrowsN == 0, name .. " has one title")
	end
end
-- Ledger notice boards keep their live rows.
for _, gui in world:GetDescendants() do
	if gui:IsA("SurfaceGui") then
		local holder = gui.Parent and gui.Parent.Parent
		ok(holder and holder:GetAttribute("SignArchetype") == "ledger", gui:GetFullName() .. " SurfaceGuis are only ledger boards")
		ok(gui.MaxDistance >= 80 and not gui.AlwaysOnTop and gui.LightInfluence <= .35, gui:GetFullName() .. " ledger face")
	end
end
for _, name in {"Sign Artificers' Row", "Sign Compass Quay", "Sign Sky Harbor", "Sign Verdant Garden", "Sign Hall of Mastery", "Sign Bestiary"} do
	ok(world:FindFirstChild(name, true) ~= nil, name .. " exists")
end
ok(world:FindFirstChild("Skill Leaderboard", true):FindFirstChild("Row_" .. Data.SkillOrder[1], true) ~= nil, "ledger rows keep their Row_ names")
ok(world:FindFirstChild("Skill Leaderboard", true):FindFirstChild("Value_" .. Data.SkillOrder[1], true) ~= nil, "ledger rows keep their Value_ names")
-- Faction standards keep their prompt (IsleItem/IsleRegion) on the banner anchor.
local standards = 0
for _, m in world:GetDescendants() do
	if m:IsA("Model") and m:GetAttribute("Faction") then
		local q = m:FindFirstChildWhichIsA("ProximityPrompt", true)
		ok(q and q:GetAttribute("IsleAction") == "factionBoard" and q:GetAttribute("IsleRegion") ~= nil and q.Parent:GetAttribute("SignAnchor") == true
			and q.Parent.Parent:GetAttribute("SignArchetype") == "banner", m.Name .. " standard is a banner sign with its prompt on the anchor")
		standards += 1
	end
end
ok(standards == #Data.Factions.Order, "every faction has a banner standard")

------------------------------------------------------------------------------
-- Placement: anchors swallow no foreign prompt; floating plaques never sit on
-- a prompt's screen spot or on each other.
------------------------------------------------------------------------------
local prompts = {}
for _, obj in world:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then table.insert(prompts, obj) end
end
ok(#prompts > 100, "prompts to check against")
local function inside(model, obj)
	local node = obj
	while node do if node == model then return true end; node = node.Parent end
	return false
end
local function centre(b) return b.anchor.CFrame.Position + Vector3.new(0, b.gui.StudsOffsetWorldSpace.Y, 0) end
local overlaps = {}
for _, b in boards do
	local c = centre(b)
	for _, q in prompts do
		if not inside(b.model, q) then
			local hp = q.Parent.CFrame.Position
			local flat = Vector3.new(hp.X - c.X, 0, hp.Z - c.Z).Magnitude
			ok((hp - b.anchor.CFrame.Position).Magnitude >= .8, b.model:GetFullName() .. " anchor clear of the prompt on " .. q.Parent:GetFullName())
			if not (flat > 2.5 or math.abs(hp.Y - c.Y) > 1.5) then table.insert(overlaps, b.model:GetFullName() .. " covers " .. q.Parent:GetFullName()) end
		end
	end
end
for i, a in boards do
	for j = i + 1, #boards do
		local b = boards[j]
		local ca, cb = centre(a), centre(b)
		if not (Vector3.new(ca.X - cb.X, 0, ca.Z - cb.Z).Magnitude > 3 or math.abs(ca.Y - cb.Y) > 3) then
			table.insert(overlaps, a.model:GetFullName() .. " overlaps " .. b.model:GetFullName())
		end
	end
end
ok(#overlaps == 0, "no plaque covers a prompt or another plaque: " .. table.concat(overlaps, "; "))

------------------------------------------------------------------------------
-- Client view rules (shared/SignView.lua) and the client script.
------------------------------------------------------------------------------
local View = luau.load(fs.readFile("shared/SignView.lua"), {environment = {Vector3 = Vector3}, injectGlobals = true})()
ok(View.CAP.phone < View.CAP.desktop and View.CAP.phone <= 10 and View.CAP.desktop <= 24, "visible sign caps (desktop " .. View.CAP.desktop .. ", phone " .. View.CAP.phone .. ")")
local last = math.huge
for d = 0, 200, 5 do
	local s = View.scaleFor(d, false)
	ok(s <= last and s >= View.SCALE.desktop.min and s <= View.SCALE.desktop.max, "scale shrinks with distance and stays clamped at " .. d)
	ok(View.scaleFor(d, true) <= View.SCALE.phone.max, "phones never draw past their max scale")
	last = s
end
ok(View.scaleFor(5, false) == 1 and View.scaleFor(500, false) == View.SCALE.desktop.min, "full size near, legible floor far")
ok(View.fadeFor(10, 120) == 0 and View.fadeFor(120, 120) == 1 and View.fadeFor(108, 120) > 0 and View.fadeFor(108, 120) < 1, "fades over the last 20% of MaxDistance")
local entries = {}
for i = 1, 40 do table.insert(entries, {d = i * 3, max = 120}) end
table.insert(entries, {d = 130, max = 120})
local chosen = View.select(entries, View.CAP.phone)
ok(#chosen == View.CAP.phone and chosen[1].d == 3 and chosen[#chosen].d == View.CAP.phone * 3, "nearest N signs are shown")
ok(#View.select({{d = 130, max = 120}}, 8) == 0, "signs beyond MaxDistance are never selected")
ok(View.bob(1.3, 0, true) == 0 and math.abs(View.bob(1.3, 0, false)) <= View.BOB.amplitude, "bob is small and off with reduced motion")
local cam = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -10))
local function near(a, b) return math.abs(((a - b + 180) % 360) - 180) < 1 end
ok(near(View.arrowRotation(Vector3.new(0, 0, -1), cam), -90), "ahead points up the screen")
ok(near(View.arrowRotation(Vector3.new(1, 0, 0), cam), 0), "right points right")
ok(near(View.arrowRotation(Vector3.new(-1, 0, 0), cam), 180), "left points left")
ok(near(View.arrowRotation(Vector3.new(0, 0, 1), cam), 90), "behind points down")
ok(View.glowTransparency(0, .7, .35) == .35 and View.glowTransparency(1, .7, .35) == .7, "crystal glow follows the day factor")
local client = fs.readFile("signs.client.lua")
local code = client:gsub("%-%-[^\n]*", "")
ok(code:find("View.select(list, CAP", 1, true) and code:find(".Enabled = on", 1, true), "client caps visible billboards and reuses them")
ok(code:find("Theme.reducedMotion(player)", 1, true) and code:find("View.arrowRotation", 1, true) and code:find("GroupTransparency", 1, true), "client bobs (reduced motion), fades and turns arrows")
ok(not code:find('"Lighting"', 1, true) and not code:find("Instance.new", 1, true), "client never touches Lighting and creates no instances")

------------------------------------------------------------------------------
-- Source and catalog: the physical kit is gone.
------------------------------------------------------------------------------
local _, guiNew = source:gsub('Instance%.new%("SurfaceGui"%)', "")
ok(guiNew == 1, "world.server.lua creates SurfaceGuis only for ledger boards (" .. guiNew .. ")")
ok(source:find("return (Signs.build(parent,cf,spec))", 1, true), "legacy signAt forwards to Signs.build")
for _, gone in {"SignHangingFrame", "SignpostFrame", "BannerStandardFrame", "SignPlinthFrame", "SignLedgerFrame", "SignCarvedBoard",
	"SignScrollBoard", "SignArrowBoard", "SignPlaqueBoard", "BannerCloth"} do
	ok(World.shapes[gone] == nil and not source:find('"' .. gone .. '"', 1, true), gone .. " scrapped")
end
ok(World.shapes.SignNoticeBoard ~= nil, "the ledger notice board mesh stays")

print(string.format("SIGN-BILLBOARDS: %d billboards, %d GUI instances (%d text labels), caps desktop %d / phone %d", billboards, guiInstances, labelCount, View.CAP.desktop, View.CAP.phone))
ok(guiInstances <= 6500 and labelCount <= 700, "sign GUI instances bounded")
local list = {}
for kind, n in kinds do table.insert(list, kind .. " " .. n) end
table.sort(list)
print("Signs v2: " .. #signs .. " signs (" .. staticSigns .. " static), " .. signParts .. " static sign parts of " .. staticParts .. "; by archetype (incl. home): " .. table.concat(list, ", ") .. ".")
print("Sign QA passed " .. checks .. " checks.")
print("SUITE-END verify-signs.luau")
